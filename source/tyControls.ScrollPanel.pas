unit tyControls.ScrollPanel;
{$mode objfpc}{$H+}

// TTyScrollPanel — an auto-panning scroll container. It is a THIN subclass of
// TTyScrollBox (the batch's scrolling container): it inherits the whole viewport
// + embedded-scrollbar + child-offset machinery and adds ONE behaviour — edge
// AUTO-PAN. While the user drags (a rubber-band, a moved child, a drag-and-drop
// payload) and the pointer enters an EdgeMargin band next to a viewport edge, the
// panel auto-scrolls toward that edge, faster the closer the pointer gets — the
// familiar "drag to the edge of the list and it keeps scrolling" affordance.
//
// The tested CORE is the PURE function TyEdgeAutoPan (below): given the pointer
// position, the viewport rect, the edge margin and a max speed it returns the
// per-tick (dx, dy) scroll delta. That math is fully headless. The timer that
// ticks it and the drag/DnD wiring that feeds it a live pointer are real-machine
// (a TTimer drives AutoPanTick at runtime; see the notes at the bottom).
//
// typeKey: inherited 'TyPanel' (GetStyleTypeKey NOT overridden) — no new .tycss.

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, LCLType,
  tyControls.Types, tyControls.Base, tyControls.ScrollBox;

const
  { Logical (96-ppi) defaults for the auto-pan band + speed. Both are published,
    DPI-scaled at use time (real-machine), so a design-time value stays crisp. }
  TyAutoPanEdgeMargin  = 24;   // px band next to each viewport edge that arms the pan
  TyAutoPanMaxSpeed    = 16;   // px/tick scroll delta at (or past) the very edge
  TyAutoPanIntervalMs  = 16;   // ~60fps auto-pan timer tick

type
  TTyScrollPanel = class(TTyScrollBox)
  private
    FAutoScroll: Boolean;
    FEdgeMargin: Integer;
    FMaxSpeed: Integer;
    FAutoPanActive: Boolean;    // a drag/DnD is arming the auto-pan
    FLastPanPos: TPoint;        // last pointer position fed to the pan (client px)
    FPanTimer: TTimer;          // lazy; only created when auto-pan actually runs
    procedure SetEdgeMargin(AValue: Integer);
    procedure SetMaxSpeed(AValue: Integer);
    procedure SetAutoScroll(AValue: Boolean);
    procedure EnsurePanTimer;
    procedure PanTimerTick(Sender: TObject);
    function ScaledEdgeMargin: Integer;
    function ScaledMaxSpeed: Integer;
  protected
    { One auto-pan step for the current pointer position. Computes the per-tick
      (dx, dy) via TyEdgeAutoPan against the live viewport, then applies it by
      nudging the inherited scroll offset. Returns True iff it scrolled. Called by
      the timer at runtime and directly by tests via an access subclass. The actual
      scroll application delegates to ApplyAutoPanDelta (below) so a test can observe
      the requested delta even without a live TTyScrollBox offset. }
    function AutoPanStep(const AClientPos: TPoint): Boolean; virtual;
    { Apply a computed (dx, dy) pan delta to the inherited scroll position. Kept as
      its own seam so the exact hook into TTyScrollBox's offset lives in ONE place
      (and a subclass/test can override it). Returns True iff the offset moved. }
    function ApplyAutoPanDelta(ADx, ADy: Integer): Boolean; virtual;
    { The viewport rectangle the pan math is measured against — the client area the
      content scrolls within, in the SAME client coords as the pointer. Defaults to
      ClientRect; a subclass narrows it if the ScrollBox reserves a gutter. }
    function AutoPanViewport: TRect; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Arm/refresh the auto-pan with a live pointer (client coords). Call from a drag
      handler (OnDragOver, a rubber-band MouseMove) every time the pointer moves;
      the panel starts a timer that keeps scrolling while the pointer sits in an edge
      band, and stops when it leaves the band. Real-machine (needs a running loop). }
    procedure AutoPanTo(const AClientPos: TPoint);
    { Stop any active auto-pan (call on drag end / MouseUp / OnEndDrag). }
    procedure StopAutoPan;
    { True while the auto-pan timer is live. }
    property AutoPanActive: Boolean read FAutoPanActive;
  published
    { Master switch. When False AutoPanTo is a no-op (the panel still scrolls by
      wheel / scrollbar exactly like its TTyScrollBox base). Default True. }
    property AutoScroll: Boolean read FAutoScroll write SetAutoScroll default True;
    { Logical width (px @96ppi) of the edge band that arms the auto-pan; wider =
      the pan kicks in further from the edge. Default 24. }
    property EdgeMargin: Integer read FEdgeMargin write SetEdgeMargin
      default TyAutoPanEdgeMargin;
    { Logical max scroll delta per tick (px @96ppi) reached AT (or past) the very
      edge; the delta ramps from 0 at the band's inner boundary up to this. Default 16. }
    property MaxSpeed: Integer read FMaxSpeed write SetMaxSpeed
      default TyAutoPanMaxSpeed;
  end;

{ TyEdgeAutoPan — the pure auto-pan kernel (headless-tested).

  Given the pointer position AMousePos, the viewport rectangle AViewport (both in
  the same coord space), the edge band width AEdgeMargin and the max per-tick speed
  AMaxSpeed, returns the per-tick scroll delta (dx, dy) that an edge-drag should
  apply this frame:

    * 0 on an axis when the pointer is deeper than AEdgeMargin from BOTH edges on
      that axis (the calm middle).
    * As the pointer nears an edge the magnitude ramps LINEARLY from 0 at the band's
      inner boundary up to AMaxSpeed exactly AT the edge.
    * NEGATIVE toward / past the TOP or LEFT edge (scroll content up / left), POSITIVE
      toward / past the BOTTOM or RIGHT edge (scroll content down / right).
    * Past an edge (pointer outside the viewport) the magnitude is clamped to AMaxSpeed
      (a drag dragged beyond the edge keeps panning at full speed, never faster).

  Degenerate guards: AEdgeMargin <= 0 or AMaxSpeed <= 0 -> (0,0) (auto-pan disabled);
  a viewport too thin to hold two non-overlapping bands on an axis splits it at the
  midpoint so each half still pans toward its own edge (no dead overlap zone). }
function TyEdgeAutoPan(const AMousePos: TPoint; const AViewport: TRect;
  AEdgeMargin, AMaxSpeed: Integer): TPoint;

implementation

{ ---- pure kernel ---------------------------------------------------------- }

// One-axis ramp. APos is the pointer coord on the axis; ALo/AHi the viewport's
// low/high edge on that axis; AMargin the band width; AMax the peak speed.
// Result: signed per-tick delta (<0 toward ALo, >0 toward AHi, 0 in the middle).
function AxisAutoPan(APos, ALo, AHi, AMargin, AMax: Integer): Integer;
var
  span, half, distLo, distHi: Integer;

  // Ramp a distance-from-edge into a speed: full AMax at/behind the edge (dist<=0),
  // 0 at dist>=AMargin, linear in between.
  function Ramp(ADist: Integer): Integer;
  begin
    if ADist <= 0 then
      Result := AMax
    else if ADist >= AMargin then
      Result := 0
    else
      // (AMargin - ADist)/AMargin of full speed; rounds so a 1px-in pointer still
      // yields a nonzero nudge and the very edge yields exactly AMax.
      Result := (AMax * (AMargin - ADist) + (AMargin div 2)) div AMargin;
  end;

begin
  Result := 0;
  span := AHi - ALo;
  if span <= 0 then Exit;                 // empty axis: nothing to pan
  // Cap the band so the two edge bands never overlap: on a thin axis each band gets
  // at most half the span, and the pointer's nearer edge wins (checked lo-first).
  half := span div 2;
  if AMargin > half then AMargin := half;
  if AMargin <= 0 then Exit;              // too thin to hold any band
  distLo := APos - ALo;                   // >0 inside from the low edge
  distHi := AHi - APos;                   // >0 inside from the high edge
  // Nearer edge wins. Toward the low edge -> negative; toward the high edge -> positive.
  if distLo <= distHi then
  begin
    if distLo < AMargin then
      Result := -Ramp(distLo);
  end
  else
  begin
    if distHi < AMargin then
      Result := Ramp(distHi);
  end;
end;

function TyEdgeAutoPan(const AMousePos: TPoint; const AViewport: TRect;
  AEdgeMargin, AMaxSpeed: Integer): TPoint;
begin
  Result := Point(0, 0);
  if (AEdgeMargin <= 0) or (AMaxSpeed <= 0) then Exit;   // disabled
  Result.X := AxisAutoPan(AMousePos.X, AViewport.Left, AViewport.Right,
    AEdgeMargin, AMaxSpeed);
  Result.Y := AxisAutoPan(AMousePos.Y, AViewport.Top, AViewport.Bottom,
    AEdgeMargin, AMaxSpeed);
end;

{ ---- TTyScrollPanel ------------------------------------------------------- }

constructor TTyScrollPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAutoScroll := True;
  FEdgeMargin := TyAutoPanEdgeMargin;
  FMaxSpeed := TyAutoPanMaxSpeed;
  FAutoPanActive := False;
  FPanTimer := nil;
end;

destructor TTyScrollPanel.Destroy;
begin
  // FPanTimer is owned by Self, but free it explicitly first so its OnTimer can
  // never fire mid-teardown (mirrors TTyScrollBar's timer teardown).
  FreeAndNil(FPanTimer);
  inherited Destroy;
end;

procedure TTyScrollPanel.SetEdgeMargin(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FEdgeMargin = AValue then Exit;
  FEdgeMargin := AValue;
end;

procedure TTyScrollPanel.SetMaxSpeed(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FMaxSpeed = AValue then Exit;
  FMaxSpeed := AValue;
end;

procedure TTyScrollPanel.SetAutoScroll(AValue: Boolean);
begin
  if FAutoScroll = AValue then Exit;
  FAutoScroll := AValue;
  if not FAutoScroll then StopAutoPan;   // turning it off stops any live pan
end;

function TTyScrollPanel.ScaledEdgeMargin: Integer;
begin
  Result := MulDiv(FEdgeMargin, Font.PixelsPerInch, 96);
  if Result < 0 then Result := 0;
end;

function TTyScrollPanel.ScaledMaxSpeed: Integer;
begin
  Result := MulDiv(FMaxSpeed, Font.PixelsPerInch, 96);
  if Result < 0 then Result := 0;
end;

function TTyScrollPanel.AutoPanViewport: TRect;
begin
  // The scrollable client area, in client coords (same space as the pointer that
  // AutoPanTo is fed). ClientRect is the natural viewport; a subclass narrows it
  // if the ScrollBox reserves a scrollbar gutter that should not arm the pan.
  Result := ClientRect;
end;

function TTyScrollPanel.ApplyAutoPanDelta(ADx, ADy: Integer): Boolean;
var
  ox, oy: Integer;
begin
  // Nudge the inherited TTyScrollBox offset via its protected ScrollByDelta (clamps to the
  // scrollable range + syncs the bar thumbs). Report whether the offset actually moved, so an
  // idle auto-pan tick (already at the edge of the range) can stop.
  ox := ScrollX;
  oy := ScrollY;
  ScrollByDelta(ADx, ADy);
  Result := (ScrollX <> ox) or (ScrollY <> oy);
end;

function TTyScrollPanel.AutoPanStep(const AClientPos: TPoint): Boolean;
var
  d: TPoint;
begin
  Result := False;
  if not FAutoScroll then Exit;
  d := TyEdgeAutoPan(AClientPos, AutoPanViewport, ScaledEdgeMargin, ScaledMaxSpeed);
  if (d.X = 0) and (d.Y = 0) then Exit;
  Result := ApplyAutoPanDelta(d.X, d.Y);
end;

procedure TTyScrollPanel.EnsurePanTimer;
begin
  if FPanTimer = nil then
  begin
    FPanTimer := TTimer.Create(Self);
    FPanTimer.Enabled := False;
    FPanTimer.Interval := TyAutoPanIntervalMs;
    FPanTimer.OnTimer := @PanTimerTick;
  end;
end;

procedure TTyScrollPanel.PanTimerTick(Sender: TObject);
begin
  // Keep panning from the last pointer position. If the pointer has left every edge
  // band the step yields (0,0): we DON'T stop the timer here (the drag is still live
  // and may re-enter a band) — StopAutoPan is the explicit end. But if content can't
  // scroll further, the step returns False; that alone doesn't stop the pan either,
  // matching the "hold at the edge" affordance.
  AutoPanStep(FLastPanPos);
end;

procedure TTyScrollPanel.AutoPanTo(const AClientPos: TPoint);
var
  d: TPoint;
begin
  if not FAutoScroll then Exit;
  FLastPanPos := AClientPos;
  d := TyEdgeAutoPan(AClientPos, AutoPanViewport, ScaledEdgeMargin, ScaledMaxSpeed);
  if (d.X <> 0) or (d.Y <> 0) then
  begin
    // Pointer is in an edge band: run the timer so scrolling continues even while
    // the pointer is HELD still at the edge (a drag that stops moving must keep
    // panning). An immediate step gives instant feedback on the first move.
    FAutoPanActive := True;
    EnsurePanTimer;
    FPanTimer.Enabled := True;
    AutoPanStep(AClientPos);
  end
  else
    // Pointer back in the calm middle: pause the timer but stay armed for the next
    // move into a band (the drag is still in progress).
    if FPanTimer <> nil then
      FPanTimer.Enabled := False;
end;

procedure TTyScrollPanel.StopAutoPan;
begin
  FAutoPanActive := False;
  if FPanTimer <> nil then
    FPanTimer.Enabled := False;
end;

end.
</content>
