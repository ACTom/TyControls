unit tyControls.ExPanel;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls,
  BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Panel,
  tyControls.StyleModel, tyControls.Animation;

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

    Theming: 'TyExPanel' is the surface (background/border/radius/padding — everything
    TTyPanel's frame draws). 'TyExPanelHeader' is the header BAND: its background is an
    opt-in tint (no background => the panel's own surface shows through, unfilled) and
    its color/font drive BOTH the caption and the chevron, so a caret and its caption
    always tint together. The band is also the hit zone, so it takes ':hover' while the
    pointer is over it — that is what makes the header-hover repaint visible. Every
    value is theme-driven. }

  TTyExPanel = class(TTyPanel)
  private
    FCollapsed: Boolean;
    FHeaderHeight: Integer;
    FHeaderHeightExplicit: Boolean;   { True once set; False = follow --expander-header-height (density) }
    FExpandedHeight: Integer;      // remembered full height while collapsed
    FAnimationDuration: Integer;   // ms; a real timer drives frames at runtime
    FAnimator: TTyAnimator;        // 0..1 traversal driving FAnimFromH -> FAnimToH
    FAnimFromH, FAnimToH: Integer; // height endpoints for the collapse ease
    FTimer: TTimer;                // lazy; only while actually animating
    FOnExpand: TNotifyEvent;
    FOnCollapse: TNotifyEvent;
    { Pointer is over the header BAND (not merely over the control). Drives the
      ':hover' state of the 'TyExPanelHeader' key — which is what makes the repaint
      MouseMove/MouseLeave already ask for actually change something. }
    FHeaderHover: Boolean;
    procedure SetCollapsed(AValue: Boolean);
    function GetHeaderHeight: Integer;
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
    { The resolved 'TyExPanelHeader' style — ONLY what that key itself declared, so the
      caller can tell "the theme tinted the band" from "the band inherits the surface".
      Its states are the panel's, except that ':hover' follows the BAND (FHeaderHover):
      the band is the click target, so hovering the body must not light it up. }
    function HeaderStyle: TTyStyleSet;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Its own key, NOT the base panel's. This control paints two things a plain panel
      never paints — an interactive header band and a chevron — and pinned to 'TyPanel'
      a theme had no name to reach them by: it could not tint the band, weight its
      caption or accent the caret without restyling every panel in the app. }
    function GetStyleTypeKey: string; override;
    { The full (expanded) height. While collapsed this is the height the panel
      returns to when expanded; while expanded it tracks the live Height. }
    property ExpandedHeight: Integer read FExpandedHeight write FExpandedHeight;
  published
    property Collapsed: Boolean read FCollapsed write SetCollapsed default False;
    { Left unset it follows --expander-header-height (26 classic / 36 modern), so the
      header band grows with density; set it and that value wins and is streamed. }
    property HeaderHeight: Integer read GetHeaderHeight write SetHeaderHeight
      stored FHeaderHeightExplicit;
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
  FHeaderHeight := TyExPanelDefaultHeaderHeight;   { fallback; unused while not explicit }
  FHeaderHeightExplicit := False;                  { follow --expander-header-height (density) }
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

function TTyExPanel.GetStyleTypeKey: string;
begin
  Result := 'TyExPanel';
end;

function TTyExPanel.HeaderStyle: TTyStyleSet;
var
  states: TTyStateSet;
begin
  // Swap the control-wide hover for the BAND hover: TTyCustomControl sets FHover for the
  // whole client area, but only the band is clickable, so only the band may read as hot.
  states := CurrentStates;
  Exclude(states, tysHover);
  if FHeaderHover and Enabled then Include(states, tysHover);
  Result := ActiveController.Model.ResolveStyle('TyExPanelHeader', StyleClass, states);
end;

{ Effective header height: an explicit set wins; otherwise follow the theme's
  --expander-header-height (density pack raises it for modern). Resolved live so a
  density toggle re-heights the header on the next layout. }
function TTyExPanel.GetHeaderHeight: Integer;
begin
  if FHeaderHeightExplicit then
    Result := FHeaderHeight
  else
    Result := ActiveController.Metric('--expander-header-height', TyExPanelDefaultHeaderHeight);
end;

function TTyExPanel.ScaledHeaderHeight: Integer;
begin
  Result := MulDiv(GetHeaderHeight, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

procedure TTyExPanel.AdjustClientRect(var ARect: TRect);
var
  S: TTyStyleSet;
  bw: Integer;
begin
  inherited AdjustClientRect(ARect);
  // The body (where child controls live) starts below the header band.
  Inc(ARect.Top, ScaledHeaderHeight);
  // ...and clears the BORDER on the other three sides. DrawFrame strokes the border INSIDE
  // the control's rect, so without this an alClient child starts at x=0 — directly on top of
  // the border line, which reads as the content spilling out of the panel. (The header band
  // already covers the top edge.) Only the border, deliberately not the themed padding: this
  // is TTyPanel's client rect, and insetting it further would silently re-lay-out every
  // existing ExPanel's children.
  S := CurrentStyle;
  if TyBorderVisible(S) then bw := MulDiv(S.BorderWidth, Font.PixelsPerInch, 96) else bw := 0;
  if bw > 0 then
  begin
    Inc(ARect.Left, bw);
    Dec(ARect.Right, bw);
    Dec(ARect.Bottom, bw);
  end;
  if ARect.Top > ARect.Bottom then ARect.Top := ARect.Bottom;
  if ARect.Left > ARect.Right then ARect.Left := ARect.Right;
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
  FHeaderHeightExplicit := True;   { host pinned it, even at the fallback value }
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
  S, HD, HS: TTyStyleSet;
  R, hdr, textRect, bandRect: TRect;
  hdrH, chevW, bw, bwLogical: Integer;
  corners, bandCorners: TTyCorners;
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

    hdrH := MulDiv(GetHeaderHeight, APPI, 96);
    if hdrH < 1 then hdrH := 1;
    hdr := TyExPanelHeaderRect(R, hdrH);

    // The header band is its own themable part. HD holds ONLY what 'TyExPanelHeader'
    // declared (so the tint below can stay opt-in); HS is the panel surface with those
    // declarations laid over it — what the chevron and caption actually draw with, so a
    // theme that names neither still gets exactly the panel's ink.
    HD := HeaderStyle;
    HS := S;
    TyMergeStyleSet(HS, HD);

    // Band tint is OPT-IN: only a header key that declares a background paints one. Say
    // nothing and the panel's single surface is left exactly as DrawFrame laid it down —
    // a second fill would re-blend the frame's antialiased corner arcs. When it IS
    // painted, the band is pulled off the border stroke and its OUTER corners follow the
    // panel's, so a tint can never spill into the corner arcs or over the frame.
    if tpBackground in HD.Present then
    begin
      if TyBorderVisible(S) then
      begin
        bw := P.Scale(S.BorderWidth);   // device px: the fill inset
        bwLogical := S.BorderWidth;     // logical px: FillBackground scales corners itself
      end
      else
      begin
        bw := 0;
        bwLogical := 0;                 // border present-but-not-drawn keeps the full radius
      end;
      corners := TyEffectiveCorners(S);
      bandCorners := Default(TTyCorners);
      bandCorners.TL := corners.TL - bwLogical;
      bandCorners.TR := corners.TR - bwLogical;
      if bandCorners.TL < 0 then bandCorners.TL := 0;
      if bandCorners.TR < 0 then bandCorners.TR := 0;
      bandRect := Rect(hdr.Left + bw, hdr.Top + bw, hdr.Right - bw, hdr.Bottom);
      if (bandRect.Right > bandRect.Left) and (bandRect.Bottom > bandRect.Top) then
        P.FillBackground(bandRect, HD.Background, bandCorners);
    end;

    // Chevron: a filled triangle in the HEADER's color (caret and caption tint together —
    // that is how a real collapse header behaves), pointing down when expanded and right
    // when collapsed. Uses the pure point math so paint == hit geometry.
    tri := TyExPanelChevronPoints(hdr, not FCollapsed);
    ctx := P.Bitmap.Canvas2D;
    ctx.beginPath;
    ctx.moveTo(tri[0].X + 0.5, tri[0].Y + 0.5);
    ctx.lineTo(tri[1].X + 0.5, tri[1].Y + 0.5);
    ctx.lineTo(tri[2].X + 0.5, tri[2].Y + 0.5);
    ctx.closePath;
    ctx.fillStyle(TyColorToBGRA(HS.TextColor));
    ctx.fill;

    // Caption text to the right of the chevron gutter, vertically centered in the band.
    if Caption <> '' then
    begin
      chevW := hdr.Bottom - hdr.Top;   // gutter width == band height (matches chevron center)
      // Right inset stays the PANEL's padding: the band's box is the panel's box, and only
      // its ink (font + colour) is the header key's business.
      textRect := Rect(hdr.Left + chevW, hdr.Top,
        hdr.Right - P.Scale(S.Padding.Right), hdr.Bottom);
      P.DrawText(textRect, Caption, HS.FontName, ResolveFontSize(HS), HS.FontWeight,
        HS.TextColor, taLeftJustify, tlCenter, True);
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
