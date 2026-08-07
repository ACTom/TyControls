unit tyControls.Bevel;
{$mode objfpc}{$H+}
{ TTyBevel — a decorative 3D line / frame (a themed re-imagining of TBevel).

  It draws a HIGHLIGHT line (the base colour blended toward white) paired with a
  SHADOW line (blended toward black); the two are swapped for a raised vs. lowered
  look. The base colour is theme-driven (the resolved TyPanel border/surface/text
  token) so the bevel matches the active theme — no colour is ever hard-coded.

  Shapes: a full box outline (tbsBox), a 3D groove/ridge rectangle (tbsFrame), a
  single edge line (tbsTopLine/BottomLine/LeftLine/RightLine), or an invisible
  spacer (tbsSpacer, paints nothing). Which edges a shape occupies is exposed as
  the pure function TyBevelEdges so the geometry can be unit-tested headless. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  { Which decorative shape the bevel draws. }
  TTyBevelShape = (tbsBox, tbsFrame, tbsTopLine, tbsBottomLine,
                   tbsLeftLine, tbsRightLine, tbsSpacer);
  { Lowered = sunk (shadow on top/left), Raised = protruding (highlight on top/left). }
  TTyBevelStyle = (tbsLowered, tbsRaised);

  { One of the four rectangle edges. A shape occupies a SET of these; TyBevelEdges
    returns that set (a pure function, no control state — unit-tested directly). }
  TTyBevelEdge = (tbeTop, tbeBottom, tbeLeft, tbeRight);
  TTyBevelEdges = set of TTyBevelEdge;

  TTyBevel = class(TTyGraphicControl)
  private
    FShape: TTyBevelShape;
    FStyle: TTyBevelStyle;
    procedure SetShape(AValue: TTyBevelShape);
    procedure SetStyle(AValue: TTyBevelStyle);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
  published
    property Shape: TTyBevelShape read FShape write SetShape default tbsBox;
    property Style: TTyBevelStyle read FStyle write SetStyle default tbsLowered;
    property Align;
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

{ Pure geometry: which of the four edges the given shape draws. tbsBox / tbsFrame
  occupy all four; each tbsXxxLine a single edge; tbsSpacer draws nothing (empty
  set). No control state involved — the value of the control is this correct map. }
function TyBevelEdges(AShape: TTyBevelShape): TTyBevelEdges;

{ Blend AColor toward pure white by AAmount (0..1); AAmount=0 returns AColor,
  1 returns white. Alpha is preserved. Used to derive the HIGHLIGHT line. }
function TyBevelLighten(AColor: TTyColor; AAmount: Single): TTyColor;
{ Blend AColor toward pure black by AAmount (0..1); the SHADOW line. }
function TyBevelDarken(AColor: TTyColor; AAmount: Single): TTyColor;

{ Rec.601 luma of AColor, 0..255. The same measure — and below, the same 128 class
  boundary — tests/test.modecoherence.pas uses to class a window's surfaces as light
  or dark. Exposed so the rail choice is checkable without a canvas. }
function TyBevelLuma(AColor: TTyColor): Single;

{ The bevel's two rails: AHigh (the lit edge) and ALow (the shaded edge), derived from
  ABase and from ASurface — the surface the bevel is drawn ON.

  WHY THE SURFACE IS AN INPUT. The rails are blends toward the two extremes, so each one
  spends a FRACTION OF THE HEADROOM in its direction. The two shipped fractions (0.55
  toward white, 0.45 toward black) were tuned on a LIGHT surface, where the base — the
  theme's --border — sits near white: light.tycss's #D1D5DB has only ~42 luma of headroom
  up but ~213 down, so the LARGE fraction lands on the SHORT run (+23 luma) and the small
  one on the LONG run (-96). That pairing is what makes the pair read as a bevel rather
  than as two stripes.

  On a DARK surface both headrooms invert (dark.tycss's --border #3F3F46: ~192 up, ~63
  down), so applying the same fraction to the same direction puts the LARGE fraction on
  the LONG run — the two amplifications compound and the highlight lands at luma ~169 on
  a luma-30 window. That is the glowing rail this fixes; it was never a tuning choice,
  just the light-surface numbers applied with the mode unread.

  Swapping the two fractions on a dark surface restores the pairing the original tuning
  intended (large fraction <-> short headroom). Nothing else moves: the highlight is still
  lighter than the base and the shadow still darker, so raised/lowered keep their meaning.

  A LIGHT surface returns exactly what this control always returned, so the fix cannot move
  a light-mode pixel — TestLightSurfaceRailsAreUnchanged pins that against the raw
  TyBevelLighten/TyBevelDarken calls the old code made. }
procedure TyBevelRails(ABase, ASurface: TTyColor; out AHigh, ALow: TTyColor);

implementation

function TyBevelEdges(AShape: TTyBevelShape): TTyBevelEdges;
begin
  case AShape of
    tbsBox, tbsFrame: Result := [tbeTop, tbeBottom, tbeLeft, tbeRight];
    tbsTopLine:       Result := [tbeTop];
    tbsBottomLine:    Result := [tbeBottom];
    tbsLeftLine:      Result := [tbeLeft];
    tbsRightLine:     Result := [tbeRight];
  else
    Result := [];   // tbsSpacer — invisible
  end;
end;

function ClampUnit(A: Single): Single;
begin
  if A < 0 then Result := 0
  else if A > 1 then Result := 1
  else Result := A;
end;

function TyBevelLighten(AColor: TTyColor; AAmount: Single): TTyColor;
var
  a: Single;
begin
  a := ClampUnit(AAmount);
  Result := TyRGBA(
    Round(TyRedOf(AColor)   + (255 - TyRedOf(AColor))   * a),
    Round(TyGreenOf(AColor) + (255 - TyGreenOf(AColor)) * a),
    Round(TyBlueOf(AColor)  + (255 - TyBlueOf(AColor))  * a),
    TyAlphaOf(AColor));
end;

function TyBevelDarken(AColor: TTyColor; AAmount: Single): TTyColor;
var
  a: Single;
begin
  a := ClampUnit(AAmount);
  Result := TyRGBA(
    Round(TyRedOf(AColor)   * (1 - a)),
    Round(TyGreenOf(AColor) * (1 - a)),
    Round(TyBlueOf(AColor)  * (1 - a)),
    TyAlphaOf(AColor));
end;

const
  { The two blend fractions. Named rather than inlined because WHICH direction each one is
    applied to is now the whole point (see TyBevelRails); as bare literals at the call site
    the swap read as a typo. These are geometry, not colour — every colour stays theme-driven. }
  cBevelHighAmount = 0.55;   { the LARGE fraction — belongs on the SHORT headroom }
  cBevelLowAmount  = 0.45;   { the SMALL fraction — belongs on the LONG headroom }

  { Luma below which a surface counts as dark. Same value and same Rec.601 measure as
    tests/test.modecoherence.pas's cClassBoundary: every shipped surface sits far clear of
    it (light skins >= ~190, dark ones <= ~70), so the exact cut is not delicate. }
  cBevelDarkSurfaceLuma = 128.0;

function TyBevelLuma(AColor: TTyColor): Single;
begin
  Result := 0.299 * TyRedOf(AColor) + 0.587 * TyGreenOf(AColor)
          + 0.114 * TyBlueOf(AColor);
end;

procedure TyBevelRails(ABase, ASurface: TTyColor; out AHigh, ALow: TTyColor);
begin
  if TyBevelLuma(ASurface) < cBevelDarkSurfaceLuma then
  begin
    { Dark surface: the headrooms are inverted, so the fractions swap with them. }
    AHigh := TyBevelLighten(ABase, cBevelLowAmount);
    ALow  := TyBevelDarken(ABase, cBevelHighAmount);
  end
  else
  begin
    { Light surface: byte-for-byte what this control has always produced. }
    AHigh := TyBevelLighten(ABase, cBevelHighAmount);
    ALow  := TyBevelDarken(ABase, cBevelLowAmount);
  end;
end;

{ Resolve the theme base colour the 3D lines are derived from: the border token if
  present, else the surface (background) colour, else the text colour, else a mid
  grey (never reached with a real theme). All theme-driven — no literal colour. }
function BevelBaseColor(const AStyle: TTyStyleSet): TTyColor;
begin
  if tpBorderColor in AStyle.Present then
    Result := AStyle.BorderColor
  else if (tpBackground in AStyle.Present) and (AStyle.Background.Kind = tfkSolid) then
    Result := AStyle.Background.Color
  else if tpTextColor in AStyle.Present then
    Result := AStyle.TextColor
  else
    Result := TyRGB(128, 128, 128);
end;

{ The surface the bevel is drawn ON, for the rail choice only (it never reaches a pixel).

  A bevel is a GRAPHIC control that fills nothing, so what shows around its rails is its
  own resolved background token when the theme gives it one — TyBevel rides the TyPanel
  rule, whose `background: var(--surface)` is precisely the mode's surface seed — and
  otherwise whatever the parent painted. Returns False only when neither is knowable. }
function BevelSurfaceColor(const AStyle: TTyStyleSet; AControl: TControl;
  out AColor: TTyColor): Boolean;
begin
  Result := True;
  if tpBackground in AStyle.Present then
    case AStyle.Background.Kind of
      tfkSolid:
        if TyAlphaOf(AStyle.Background.Color) > 0 then
        begin
          AColor := AStyle.Background.Color;
          Exit;
        end;
      tfkLinearGradient:
        begin
          { Judge a gradient by the mean of its end stops — TTyFill.Color is not the paint
            for a gradient (the FillLuma precedent in test.modecoherence). }
          AColor := TyRGB(
            (TyRedOf(AStyle.Background.GradFrom)   + TyRedOf(AStyle.Background.GradTo))   div 2,
            (TyGreenOf(AStyle.Background.GradFrom) + TyGreenOf(AStyle.Background.GradTo)) div 2,
            (TyBlueOf(AStyle.Background.GradFrom)  + TyBlueOf(AStyle.Background.GradTo))  div 2);
          Exit;
        end;
    end;
  Result := TyResolveParentBg(AControl, AColor);
end;

constructor TTyBevel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShape := tbsBox;
  FStyle := tbsLowered;
  Width := 50;
  Height := 50;
end;

function TTyBevel.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': a bevel draws NO panel: no fill, no border, no caption — only highlight/shadow rails.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyBevel';
end;

procedure TTyBevel.SetShape(AValue: TTyBevelShape);
begin
  if FShape = AValue then Exit;
  FShape := AValue;
  Invalidate;
end;

procedure TTyBevel.SetStyle(AValue: TTyBevelStyle);
begin
  if FStyle = AValue then Exit;
  FStyle := AValue;
  Invalidate;
end;

procedure TTyBevel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
  edges: TTyBevelEdges;
  baseC, surfC, hiC, loC, topLeftC, botRightC: TTyColor;
  hiPx, loPx: TBGRAPixel;
  th, w, h, gw, gap: Integer;

  { Draw a 1px-thick device line from (x1,y1) to (x2,y2). BGRA FillRect is exact
    for horizontal/vertical runs (all our edges are axis-aligned). }
  procedure HLine(ax1, ay, ax2: Integer; APx: TBGRAPixel);
  begin
    P.Bitmap.FillRect(ax1, ay, ax2 + 1, ay + th, APx, dmDrawWithTransparency);
  end;
  procedure VLine(ax, ay1, ay2: Integer; APx: TBGRAPixel);
  begin
    P.Bitmap.FillRect(ax, ay1, ax + th, ay2 + 1, APx, dmDrawWithTransparency);
  end;

begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    w := R.Right - R.Left;
    h := R.Bottom - R.Top;

    if (FShape = tbsSpacer) or (w <= 0) or (h <= 0) then
    begin
      P.EndPaint;
      Exit;   // spacer / degenerate: paint nothing (invisible)
    end;

    th := P.Scale(1);            // 1 logical px, DPI-scaled
    if th < 1 then th := 1;

    baseC := BevelBaseColor(S);
    { The rails now read the SURFACE, not just the base. An unknown surface (no themed
      background AND no parent) falls back to white, which selects the light branch —
      i.e. exactly the pre-fix behaviour. It is a branch selector, never a painted value. }
    if not BevelSurfaceColor(S, Self, surfC) then
      surfC := TyRGB(255, 255, 255);
    TyBevelRails(baseC, surfC, hiC, loC);

    // Raised: highlight sits on the TOP/LEFT edges; lowered: shadow does. The
    // opposite pair carries the other colour so both lines are always present.
    if FStyle = tbsRaised then
    begin
      topLeftC  := hiC;
      botRightC := loC;
    end
    else
    begin
      topLeftC  := loC;
      botRightC := hiC;
    end;
    hiPx := TyColorToBGRA(topLeftC);
    loPx := TyColorToBGRA(botRightC);

    if FShape = tbsFrame then
    begin
      // A 3D groove/ridge: an OUTER bevel plus an INNER bevel one pixel in, with the
      // colours swapped between the two rings — the classic sunken/raised frame.
      gap := th;                          // inner ring offset (1 logical px)
      gw := R.Right - 1;
      // Outer ring (top/left = topLeftC, bottom/right = botRightC)
      HLine(R.Left, R.Top, gw, hiPx);
      VLine(R.Left, R.Top, R.Bottom - 1, hiPx);
      HLine(R.Left, R.Bottom - th, gw, loPx);
      VLine(R.Right - th, R.Top, R.Bottom - 1, loPx);
      // Inner ring, swapped colours -> the groove/ridge illusion
      HLine(R.Left + gap, R.Top + gap, gw - gap, loPx);
      VLine(R.Left + gap, R.Top + gap, R.Bottom - 1 - gap, loPx);
      HLine(R.Left + gap, R.Bottom - th - gap, gw - gap, hiPx);
      VLine(R.Right - th - gap, R.Top + gap, R.Bottom - 1 - gap, hiPx);
    end
    else
    begin
      edges := TyBevelEdges(FShape);
      if tbeTop in edges then
        HLine(R.Left, R.Top, R.Right - 1, hiPx);
      if tbeLeft in edges then
        VLine(R.Left, R.Top, R.Bottom - 1, hiPx);
      if tbeBottom in edges then
        HLine(R.Left, R.Bottom - th, R.Right - 1, loPx);
      if tbeRight in edges then
        VLine(R.Right - th, R.Top, R.Bottom - 1, loPx);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyBevel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
