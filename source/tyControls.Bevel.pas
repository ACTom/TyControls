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
  baseC, hiC, loC, topLeftC, botRightC: TTyColor;
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
    hiC := TyBevelLighten(baseC, 0.55);   // highlight — toward white
    loC := TyBevelDarken(baseC, 0.45);    // shadow    — toward black

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
