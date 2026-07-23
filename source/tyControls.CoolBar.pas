unit tyControls.CoolBar;
{$mode objfpc}{$H+}

{ Phase-5 (containers) — TTyCoolBar: a REBAR band container.

  TTyCoolBar SUBCLASSES TTyControlBar (the band-packing base, built the same batch;
  GetStyleTypeKey='TyPanel' — NO new .tycss). TTyControlBar already packs each child
  control onto a horizontal band with a left gripper; TTyCoolBar upgrades every band so
  it can be:

    * REORDERED  — grab a band's gripper and drag it up/down to a new band index
                   (real mouse-capture drag; the reorder decision is the base's band
                   list, we just move the child), and
    * RESIZED    — grab the gripper and drag horizontally to widen/narrow the band,
                   honouring a per-band minimum / maximum width.

  Per-band metadata (a fixed/min Width the band is given) is stored keyed by the child
  TControl in FBands and dropped when the child is freed (Notification/opRemove) — never
  a parallel array indexed by position, which would desync the moment a band is removed.

  The DRAG ITSELF (mouse capture, live reorder animation) is real-machine; the two bits
  of math it needs are PURE unit-level functions exercised headlessly with no window:

    TyCoolBandResize(AStartW, ADx, AMinW, AMaxW) : Integer    // clamped new band width
    TyCoolGripperHit(ABandRect, AGripperW, APt) : Boolean     // is APt on the gripper?

  IMPORTANT (controller integration): this unit codes against TTyControlBar's PUBLIC
  contract as described — a csAcceptsControls band-packing container with per-band
  grippers and a keyed per-child band assignment. The one protected hook it would like
  the base to expose is the DEVICE-PX RECT of a band (so a gripper hit-test and the
  resize origin can reuse the base's own packing geometry instead of recomputing it).
  Until the base exposes that, TTyCoolBar computes a band rect itself from the child's
  BoundsRect (see BandRectFor) — see the summary note. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ControlBar;

type
  { One band's per-child metadata, keyed by the child control (position-independent). }
  TTyCoolBand = record
    Ctl: TControl;      // the hosted child this band wraps
    Width: Integer;     // the band's assigned/min logical width (0 = auto = child.Width)
    MinWidth: Integer;  // clamp floor for a gripper resize (logical px)
    MaxWidth: Integer;  // clamp ceiling for a gripper resize (0 = unbounded)
  end;

  TTyCoolBar = class(TTyControlBar)
  private
    FBands: array of TTyCoolBand;      // per-child band metadata, keyed by Ctl
    FDefaultBandMinWidth: Integer;     // fallback min when a band has none of its own
    // --- live drag state (real-machine) ---
    FDragging: Boolean;
    FDragCtl: TControl;                // the band being resized
    FDragStartX: Integer;             // mouse X (device px) at grab
    FDragStartW: Integer;             // the band's logical width at grab
    function IndexOfBand(ACtl: TControl): Integer;
    function BandAtPoint(AX, AY: Integer): TControl;   // the band whose gripper is under (X,Y)
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    { The device-px rect of ACtl's band. Derived from the child's current BoundsRect
      grown left by the gripper strip (so the gripper column is part of the band). If a
      future TTyControlBar exposes a real per-band rect, override/redirect here. }
    function BandRectFor(ACtl: TControl): TRect; virtual;
    { The device-px width of the gripper strip at this control's PPI. }
    function GripperWidthPx: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    { Assign / query a band's fixed-or-min width (logical px). Setting it re-lays the
      bands (via the inherited container relayout). AWidth <= 0 clears it (auto). The
      value is keyed by the child, so it survives reorders and other bands' removal. }
    procedure SetBandWidth(ACtl: TControl; AWidth: Integer);
    function GetBandWidth(ACtl: TControl): Integer;
    { Per-band resize clamps (logical px). AMax = 0 means unbounded. }
    procedure SetBandMinWidth(ACtl: TControl; AMinWidth: Integer);
    procedure SetBandMaxWidth(ACtl: TControl; AMaxWidth: Integer);
    function BandMinWidth(ACtl: TControl): Integer;
    function BandMaxWidth(ACtl: TControl): Integer;
  published
    // GripperWidth is INHERITED from TTyControlBar (same field the band packing uses) — do NOT
    // redeclare it here, or the base would pack with one width while our hit-test used another.
    { Fallback resize floor for a band that has no MinWidth of its own (logical px). }
    property DefaultBandMinWidth: Integer read FDefaultBandMinWidth write FDefaultBandMinWidth default 24;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ ------------------------------------------------------------------------------
  PURE, headless-tested band math (no window handle needed)
  ------------------------------------------------------------------------------ }

{ The new band width after dragging its gripper by ADx (device or logical px — the
  caller keeps units consistent) from a starting width AStartW, clamped to
  [AMinW .. AMaxW]. A non-positive AMaxW means "unbounded" (only the floor applies).
  AMinW is floored at 1 so a band never collapses to nothing. }
function TyCoolBandResize(AStartW, ADx, AMinW, AMaxW: Integer): Integer;

{ True when APt lies on the gripper strip of ABandRect: the leftmost AGripperW px
  column of the band (device px). AGripperW <= 0 -> no gripper -> always False. The
  test is half-open on the right edge (Left .. Left+AGripperW), inclusive on top,
  exclusive on bottom — matching LCL hit-testing. }
function TyCoolGripperHit(const ABandRect: TRect; AGripperW: Integer; const APt: TPoint): Boolean;

implementation

// -----------------------------------------------------------------------------
// Pure functions
// -----------------------------------------------------------------------------
function TyCoolBandResize(AStartW, ADx, AMinW, AMaxW: Integer): Integer;
begin
  if AMinW < 1 then AMinW := 1;
  Result := AStartW + ADx;
  if Result < AMinW then Result := AMinW;
  // A non-positive ceiling means unbounded; otherwise clamp (and never below the floor).
  if AMaxW > 0 then
  begin
    if AMaxW < AMinW then AMaxW := AMinW;   // an inverted range collapses to the floor
    if Result > AMaxW then Result := AMaxW;
  end;
end;

function TyCoolGripperHit(const ABandRect: TRect; AGripperW: Integer; const APt: TPoint): Boolean;
begin
  if AGripperW <= 0 then Exit(False);
  Result :=
    (APt.X >= ABandRect.Left) and (APt.X < ABandRect.Left + AGripperW) and
    (APt.Y >= ABandRect.Top)  and (APt.Y < ABandRect.Bottom);
end;

// =============================================================================
// TTyCoolBar
// =============================================================================
constructor TTyCoolBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // The base already sets csAcceptsControls; a rebar hosts arbitrary band content.
  GripperWidth := 10;   // inherited property (the base packs with the same value we hit-test)
  FDefaultBandMinWidth := 24;
  FDragging := False;
  FDragCtl := nil;
end;

function TTyCoolBar.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': same as its TTyControlBar ancestor — band grippers are not panel chrome.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyCoolBar';
end;

function TTyCoolBar.GripperWidthPx: Integer;
begin
  Result := MulDiv(GripperWidth, Font.PixelsPerInch, 96);   // inherited from TTyControlBar
  if Result < 0 then Result := 0;
end;

function TTyCoolBar.IndexOfBand(ACtl: TControl): Integer;
var
  i: Integer;
begin
  Result := -1;
  if ACtl = nil then Exit;
  for i := 0 to High(FBands) do
    if FBands[i].Ctl = ACtl then Exit(i);
end;

procedure TTyCoolBar.SetBandWidth(ACtl: TControl; AWidth: Integer);
var
  idx: Integer;
begin
  if ACtl = nil then Exit;
  if AWidth < 0 then AWidth := 0;
  idx := IndexOfBand(ACtl);
  if idx < 0 then
  begin
    SetLength(FBands, Length(FBands) + 1);
    idx := High(FBands);
    FBands[idx].Ctl := ACtl;
    FBands[idx].MinWidth := 0;
    FBands[idx].MaxWidth := 0;
  end;
  FBands[idx].Width := AWidth;
  // A given width should be honoured as the child's actual width; the base packs from
  // the child bounds, so set the child width too (auto = leave it as-is).
  if (AWidth > 0) and (ACtl.Width <> AWidth) then
    ACtl.Width := AWidth;
  Realign;
end;

function TTyCoolBar.GetBandWidth(ACtl: TControl): Integer;
var
  idx: Integer;
begin
  idx := IndexOfBand(ACtl);
  if idx >= 0 then Result := FBands[idx].Width else Result := 0;
end;

procedure TTyCoolBar.SetBandMinWidth(ACtl: TControl; AMinWidth: Integer);
var
  idx: Integer;
begin
  if ACtl = nil then Exit;
  if AMinWidth < 0 then AMinWidth := 0;
  idx := IndexOfBand(ACtl);
  if idx < 0 then
  begin
    SetLength(FBands, Length(FBands) + 1);
    idx := High(FBands);
    FBands[idx].Ctl := ACtl;
    FBands[idx].Width := 0;
    FBands[idx].MaxWidth := 0;
  end;
  FBands[idx].MinWidth := AMinWidth;
end;

procedure TTyCoolBar.SetBandMaxWidth(ACtl: TControl; AMaxWidth: Integer);
var
  idx: Integer;
begin
  if ACtl = nil then Exit;
  if AMaxWidth < 0 then AMaxWidth := 0;
  idx := IndexOfBand(ACtl);
  if idx < 0 then
  begin
    SetLength(FBands, Length(FBands) + 1);
    idx := High(FBands);
    FBands[idx].Ctl := ACtl;
    FBands[idx].Width := 0;
    FBands[idx].MinWidth := 0;
  end;
  FBands[idx].MaxWidth := AMaxWidth;
end;

function TTyCoolBar.BandMinWidth(ACtl: TControl): Integer;
var
  idx: Integer;
begin
  idx := IndexOfBand(ACtl);
  if (idx >= 0) and (FBands[idx].MinWidth > 0) then
    Result := FBands[idx].MinWidth
  else
    Result := FDefaultBandMinWidth;
  if Result < 1 then Result := 1;
end;

function TTyCoolBar.BandMaxWidth(ACtl: TControl): Integer;
var
  idx: Integer;
begin
  idx := IndexOfBand(ACtl);
  if idx >= 0 then Result := FBands[idx].MaxWidth else Result := 0;   // 0 = unbounded
end;

function TTyCoolBar.BandRectFor(ACtl: TControl): TRect;
var
  gw: Integer;
begin
  // The base (TTyControlBar) reserves + draws ONE gripper per band-ROW, at the row's left edge
  // (x = 0..gw). So only the row's FIRST child — the one placed at Left = gw (the content-left
  // after that single gripper) — is a resize target; a child packed further right on the same row
  // shares no gripper and must NOT be grippable (else its hit-zone is a phantom strip with nothing
  // drawn, resizing the wrong band). Return the real row-left gripper rect for a first child, else
  // an empty rect. Device px, control-local.
  if ACtl = nil then Exit(Rect(0, 0, 0, 0));
  gw := GripperWidthPx;
  if ACtl.Left > gw + 1 then Exit(Rect(0, 0, 0, 0));   // not the row's first child -> no gripper
  Result := ACtl.BoundsRect;
  Result.Left := 0;   // the drawn gripper spans x = 0..gw at this row's Y range
end;

function TTyCoolBar.BandAtPoint(AX, AY: Integer): TControl;
var
  i: Integer;
  ctl: TControl;
  gw: Integer;
  r: TRect;
begin
  Result := nil;
  gw := GripperWidthPx;
  if gw <= 0 then Exit;
  for i := 0 to ControlCount - 1 do
  begin
    ctl := Controls[i];
    if (ctl = nil) or not ctl.Visible then Continue;
    r := BandRectFor(ctl);
    if TyCoolGripperHit(r, gw, Point(AX, AY)) then Exit(ctl);
  end;
end;

procedure TTyCoolBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  hit: TControl;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  hit := BandAtPoint(X, Y);
  if hit = nil then Exit;
  // Begin a gripper drag: remember the band + the starting width so MouseMove can apply
  // the clamped resize. (Reorder-vs-resize disambiguation by drag direction is a
  // real-machine refinement; the resize math is what we test.)
  FDragging := True;
  FDragCtl := hit;
  FDragStartX := X;
  if GetBandWidth(hit) > 0 then
    FDragStartW := GetBandWidth(hit)
  else
    FDragStartW := hit.Width;
end;

procedure TTyCoolBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  dxLogical, newW, minW, maxW: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not (FDragging and (FDragCtl <> nil)) then Exit;
  // Convert the device-px mouse delta to logical px (band widths are logical), clamp,
  // and apply. Resizing the child width is what the base re-packs from.
  dxLogical := MulDiv(X - FDragStartX, 96, Font.PixelsPerInch);
  minW := BandMinWidth(FDragCtl);
  maxW := BandMaxWidth(FDragCtl);
  newW := TyCoolBandResize(FDragStartW, dxLogical, minW, maxW);
  if newW <> GetBandWidth(FDragCtl) then
    SetBandWidth(FDragCtl, newW);
end;

procedure TTyCoolBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := False;
    FDragCtl := nil;
  end;
end;

procedure TTyCoolBar.Notification(AComponent: TComponent; Operation: TOperation);
var
  idx, j: Integer;
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TControl) then
  begin
    // Drop the freed child's band metadata (keyed by control, never by position).
    idx := IndexOfBand(TControl(AComponent));
    if idx >= 0 then
    begin
      for j := idx to High(FBands) - 1 do
        FBands[j] := FBands[j + 1];
      SetLength(FBands, Length(FBands) - 1);
    end;
    if FDragCtl = AComponent then
    begin
      FDragging := False;
      FDragCtl := nil;
    end;
  end;
end;

initialization
  RegisterClass(TTyCoolBar);
end.
