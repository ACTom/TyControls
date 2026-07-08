unit tyControls.ExPanel;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls,
  BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Panel,
  tyControls.Animation;

const
  // Logical (96ppi) default header-band height. Chosen to match the compact
  // caption bands used elsewhere (GroupBox 16 + a little breathing room).
  TyExPanelDefaultHeaderHeight = 26;

type
  { The three corners of the expand/collapse chevron (device pixels). }
  TTyTriangle = array[0..2] of TPoint;

  { TTyExPanel — a collapsible/expandable panel.

    A HEADER band across the top draws the Caption + an expand/collapse chevron;
    clicking it toggles Collapsed. The BODY below the header hosts the user's child
    controls (a real container: csAcceptsControls). When Collapsed the control's
    Height animates down to just the header height; ExpandedHeight remembers the
    full height so expanding restores it.

    Only the header is painted by the panel (it is NOT a child control). The body
    children are the user's — AdjustClientRect insets the client below the header
    so dropped controls sit in the body.

    Reuses the 'TyPanel' typeKey (inherited GetStyleTypeKey) — no new .tycss. The
    header caption uses the TyPanel resolved TextColor/FontName; the chevron uses
    the same TextColor. All values are theme-driven. }

  TTyExPanel = class(TTyPanel)
  private
    FCollapsed: Boolean;
    FHeaderHeight: Integer;
    FExpandedHeight: Integer;      // remembered full height while collapsed
    FAnimationDuration: Integer;   // ms; a real timer drives frames at runtime
    FAnimator: TTyAnimator;        // 0..1 traversal driving FAnimFromH -> FAnimToH
    FAnimFromH, FAnimToH: Integer; // height endpoints for the collapse ease
    FTimer: TTimer;                // lazy; only while actually animating
    FOnExpand: TNotifyEvent;
    FOnCollapse: TNotifyEvent;
    FHeaderHover: Boolean;
    procedure SetCollapsed(AValue: Boolean);
    procedure SetHeaderHeight(AValue: Integer);
    function ScaledHeaderHeight: Integer;
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    { Drive the control's Height to the animation's current eased endpoint. At
      runtime the timer calls this per frame; headless it is never called (the
      Collapsed setter snaps Height directly). }
    procedure ApplyAnimatedHeight;
    { Start (or restart) the collapse/expand ease toward ATargetH from the current
      Height. With a window handle a timer eases; headless it snaps immediately. }
    procedure StartHeightAnimation(ATargetH: Integer);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The full (expanded) height. While collapsed this is the height the panel
      returns to when expanded; while expanded it tracks the live Height. }
    property ExpandedHeight: Integer read FExpandedHeight write FExpandedHeight;
  published
    property Collapsed: Boolean read FCollapsed write SetCollapsed default False;
    property HeaderHeight: Integer read FHeaderHeight write SetHeaderHeight
      default TyExPanelDefaultHeaderHeight;
    { Collapse/expand animation duration in milliseconds (0 = snap instantly). A
      real timer drives the frames at runtime; headless the height snaps. }
    property AnimationDuration: Integer read FAnimationDuration write FAnimationDuration
      default 160;
    property OnExpand: TNotifyEvent read FOnExpand write FOnExpand;
    property OnCollapse: TNotifyEvent read FOnCollapse write FOnCollapse;
    { Caption is inherited (published) from TTyPanel; drawn in the header band. }
  end;

{ PURE, headless-tested geometry. All in DEVICE pixels (caller scales HeaderHeight). }

{ The header band across the top of the client rect: full width, AHeaderHeight tall,
  clamped so it never exceeds the client height. }
function TyExPanelHeaderRect(const AClient: TRect; AHeaderHeight: Integer): TRect;

{ The three points of the expand/collapse chevron triangle, centered in a small square
  zone at the LEFT of AHeaderRect. When AExpanded the triangle points DOWN (body shown);
  when collapsed it points RIGHT (body hidden). Device pixels. }
function TyExPanelChevronPoints(const AHeaderRect: TRect; AExpanded: Boolean): TTyTriangle;

{ Interpolated height at ease parameter t in 0..1, from ACollapsedH toward AExpandedH.
  t=0 -> ACollapsedH, t=1 -> AExpandedH (linear in t; the CALLER passes an eased t). }
function TyExPanelHeightAt(ACollapsedH, AExpandedH: Integer; t: Single): Integer;

implementation

{ ---- pure geometry ---- }

function TyExPanelHeaderRect(const AClient: TRect; AHeaderHeight: Integer): TRect;
var
  h, clientH: Integer;
begin
  clientH := AClient.Bottom - AClient.Top;
  h := AHeaderHeight;
  if h < 0 then h := 0;
  if h > clientH then h := clientH;   // never taller than the client
  Result := Rect(AClient.Left, AClient.Top, AClient.Right, AClient.Top + h);
end;

function TyExPanelChevronPoints(const AHeaderRect: TRect; AExpanded: Boolean): TTyTriangle;
var
  bandH, zone, cx, cy, half: Integer;
begin
  // A small square zone at the header's left, vertically centered. The chevron
  // is ~40% of the band height so it stays a clean caret regardless of band size.
  bandH := AHeaderRect.Bottom - AHeaderRect.Top;
  if bandH < 1 then bandH := 1;
  zone := (bandH * 40) div 100;
  if zone < 5 then zone := 5;
  if Odd(zone) then Dec(zone);        // keep it even so the apex sits on a pixel
  half := zone div 2;
  // Center of the zone: one band-height in from the left edge (a comfortable gutter),
  // vertically centered in the band.
  cx := AHeaderRect.Left + bandH div 2;
  cy := (AHeaderRect.Top + AHeaderRect.Bottom) div 2;
  if AExpanded then
  begin
    // Down-pointing: apex at bottom-center, base across the top.
    Result[0] := Point(cx - half, cy - half);
    Result[1] := Point(cx + half, cy - half);
    Result[2] := Point(cx,        cy + half);
  end
  else
  begin
    // Right-pointing: apex at right-center, base down the left.
    Result[0] := Point(cx - half, cy - half);
    Result[1] := Point(cx - half, cy + half);
    Result[2] := Point(cx + half, cy);
  end;
end;

function TyExPanelHeightAt(ACollapsedH, AExpandedH: Integer; t: Single): Integer;
begin
  Result := TyLerpI(ACollapsedH, AExpandedH, t);
end;

{ ---- TTyExPanel ---- }

constructor TTyExPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // TTyPanel already adds csAcceptsControls (real container) and sets a default size.
  FCollapsed := False;
  FHeaderHeight := TyExPanelDefaultHeaderHeight;
  FAnimationDuration := 160;
  // A taller default than the base panel so there is a visible body under the header.
  Width := 200;
  Height := 140;
  FExpandedHeight := Height;
  FAnimator := TyAnimatorInit(FAnimationDuration, teEaseOutCubic);
  FAnimator.SetTargetImmediate(1);   // settled (not mid-animation)
  FAnimFromH := Height;
  FAnimToH := Height;
end;

destructor TTyExPanel.Destroy;
begin
  // Free the timer first so its callback can never fire mid-teardown.
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyExPanel.ScaledHeaderHeight: Integer;
begin
  Result := MulDiv(FHeaderHeight, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

procedure TTyExPanel.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  // The body (where child controls live) starts below the header band.
  Inc(ARect.Top, ScaledHeaderHeight);
  if ARect.Top > ARect.Bottom then ARect.Top := ARect.Bottom;
end;

procedure TTyExPanel.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;   // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyExPanel.HandleTimer(Sender: TObject);
begin
  if FAnimator.Advance(FTimer.Interval) then
    ApplyAnimatedHeight;
  if not FAnimator.Running then
    FTimer.Enabled := False;
end;

procedure TTyExPanel.ApplyAnimatedHeight;
begin
  // Drive Height along the eased curve between the two endpoints. Setting Height
  // re-lays-out the children and repaints via the LCL.
  Height := TyExPanelHeightAt(FAnimFromH, FAnimToH, FAnimator.Eased);
end;

procedure TTyExPanel.StartHeightAnimation(ATargetH: Integer);
begin
  FAnimFromH := Height;
  FAnimToH := ATargetH;
  FAnimator.DurationMs := FAnimationDuration;
  if HandleAllocated and (FAnimationDuration > 0) then
  begin
    // Real window: ease the height over time.
    FAnimator.Progress := 0;
    FAnimator.Target := 1;
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else
  begin
    // Headless (no handle) or zero duration: SNAP to the final height so the
    // geometry is settled immediately (documented contract for tests).
    FAnimator.SetTargetImmediate(1);
    Height := ATargetH;
  end;
end;

procedure TTyExPanel.SetCollapsed(AValue: Boolean);
var
  targetH: Integer;
begin
  if FCollapsed = AValue then Exit;
  FCollapsed := AValue;
  if FCollapsed then
  begin
    // Remember the full height so expanding restores it. But if a height animation is still in
    // flight (e.g. collapsing mid-EXPAND), the live Height is an interim eased value — keep the
    // already-captured FExpandedHeight (the settled full height from before the animation) so the
    // panel still restores to its true size.
    if (FTimer = nil) or not FTimer.Enabled then
      FExpandedHeight := Height;
    targetH := ScaledHeaderHeight;
    StartHeightAnimation(targetH);
    if Assigned(FOnCollapse) then FOnCollapse(Self);
  end
  else
  begin
    targetH := FExpandedHeight;
    if targetH < ScaledHeaderHeight then targetH := ScaledHeaderHeight;
    StartHeightAnimation(targetH);
    if Assigned(FOnExpand) then FOnExpand(Self);
  end;
  Invalidate;
end;

procedure TTyExPanel.SetHeaderHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FHeaderHeight = AValue then Exit;
  FHeaderHeight := AValue;
  // Collapsed height equals the header height, so keep it in step while collapsed
  // (unless an animation is currently in flight driving the height itself).
  if FCollapsed and ((FTimer = nil) or not FTimer.Enabled) then
    Height := ScaledHeaderHeight;
  Realign;   // body inset changed
  Invalidate;
end;

procedure TTyExPanel.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  hdr: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button = mbLeft) and Enabled then
  begin
    hdr := TyExPanelHeaderRect(ClientRect, ScaledHeaderHeight);
    if PtInRect(hdr, Point(X, Y)) then
      SetCollapsed(not FCollapsed);
  end;
end;

procedure TTyExPanel.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  hdr: TRect;
  overHeader: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  hdr := TyExPanelHeaderRect(ClientRect, ScaledHeaderHeight);
  overHeader := PtInRect(hdr, Point(X, Y));
  if overHeader <> FHeaderHover then
  begin
    FHeaderHover := overHeader;
    Invalidate;
  end;
end;

procedure TTyExPanel.MouseLeave;
begin
  inherited MouseLeave;
  if FHeaderHover then
  begin
    FHeaderHover := False;
    Invalidate;
  end;
end;

procedure TTyExPanel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, hdr, textRect: TRect;
  hdrH, chevW: Integer;
  tri: TTyTriangle;
  ctx: TBGRACanvas2D;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // The frame (background + border) spans the WHOLE control — header and body share
    // the one themed surface, so the header is just the top band of it.
    DrawFrame(P, R, S);

    hdrH := MulDiv(FHeaderHeight, APPI, 96);
    if hdrH < 1 then hdrH := 1;
    hdr := TyExPanelHeaderRect(R, hdrH);

    // Chevron: a filled triangle in the TyPanel TextColor, pointing down when expanded
    // and right when collapsed. Uses the pure point math so paint == hit geometry.
    tri := TyExPanelChevronPoints(hdr, not FCollapsed);
    ctx := P.Bitmap.Canvas2D;
    ctx.beginPath;
    ctx.moveTo(tri[0].X + 0.5, tri[0].Y + 0.5);
    ctx.lineTo(tri[1].X + 0.5, tri[1].Y + 0.5);
    ctx.lineTo(tri[2].X + 0.5, tri[2].Y + 0.5);
    ctx.closePath;
    ctx.fillStyle(TyColorToBGRA(S.TextColor));
    ctx.fill;

    // Caption text to the right of the chevron gutter, vertically centered in the band.
    if Caption <> '' then
    begin
      chevW := hdr.Bottom - hdr.Top;   // gutter width == band height (matches chevron center)
      textRect := Rect(hdr.Left + chevW, hdr.Top,
        hdr.Right - P.Scale(S.Padding.Right), hdr.Bottom);
      P.DrawText(textRect, Caption, S.FontName, ResolveFontSize(S), S.FontWeight,
        S.TextColor, taLeftJustify, tlCenter, True);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyExPanel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
