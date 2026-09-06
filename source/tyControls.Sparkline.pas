unit tyControls.Sparkline;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel;

type
  { Line = accent polyline through the points; Bar = accent bars from the baseline. }
  TTySparkStyle = (ssLine, ssBar);

{ Vertical pixel for AValue inside the padded band [ATop .. ATop+AHeight]. The scale
  is inverted (min -> bottom, max -> top). When AMax <= AMin the band has no range,
  so everything maps to the vertical centre (no div-by-zero). }
function TySparklineY(AValue, AMin, AMax, ATop, AHeight: Double): Double;

{ Vertical pixel of the baseline for a series spanning [AMin .. AMax]: the zero line
  when the range includes zero, otherwise the min line (the bottom of the band). }
function TySparklineBaselineY(AMin, AMax, ATop, AHeight: Double): Double;

type
  { A tiny inline trend chart — no axes, legend or labels, just the shape of a
    series. Feed it a sample array via SetValues; it maps each value to a point in
    the padded client rect (X evenly spread, Y via TySparklineY) and draws either an
    accent polyline (ssLine) or accent bars from the baseline (ssBar), with an
    optional filled dot at the last point. Themed as itself — 'TySparkline'
    (frame/baseline/text), 'TySparklineFill' (line or bars) and 'TySparklineDot' (the
    last-value marker). This is a micro-CHART, not an instrument reading one value: its
    natural family is the chart/table vocabulary (a sparkline in a grid cell must match
    grid text, not a dial), series colour is the most commonly restyled thing in any
    chart, and the last dot is the conventional CONTRAST marker — it had the line's own
    colour, so it could not contrast with anything. Data-driven — no animation. }
  TTySparkline = class(TTyGraphicControl)
  private
    FValues: array of Double;
    FStyle: TTySparkStyle;
    FShowLast: Boolean;
    FAutoRange: Boolean;
    FMinValue, FMaxValue: Double;
    procedure SetStyle(const AValue: TTySparkStyle);
    procedure SetShowLast(const AValue: Boolean);
    procedure SetAutoRange(const AValue: Boolean);
    procedure SetMinValue(const AValue: Double);
    procedure SetMaxValue(const AValue: Double);
    function GetCount: Integer;
    procedure ResolveRange(out AMin, AMax: Double);   // effective [min,max] over the data / props
    procedure DrawLine(P: TTyPainter; const R: TRect; AMin, AMax: Double; const AFillS: TTyStyleSet);
    procedure DrawBars(P: TTyPainter; const R: TRect; AMin, AMax: Double; const AFillS: TTyStyleSet);
    procedure DrawLastDot(P: TTyPainter; const R: TRect; AMin, AMax: Double; const ADotS: TTyStyleSet);
  protected
    function GetStyleTypeKey: string; override;   // 'TySparkline' (+ 'Fill' / 'Dot' sub-parts)
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Store a COPY of AValues into the internal series and repaint. }
    procedure SetValues(const AValues: array of Double);
    property Count: Integer read GetCount;
  published
    property Style: TTySparkStyle read FStyle write SetStyle default ssLine;
    property ShowLast: Boolean read FShowLast write SetShowLast default True;
    property AutoRange: Boolean read FAutoRange write SetAutoRange default True;
    property MinValue: Double read FMinValue write SetMinValue;
    property MaxValue: Double read FMaxValue write SetMaxValue;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

function TySparklineY(AValue, AMin, AMax, ATop, AHeight: Double): Double;
var frac: Double;
begin
  if AMax <= AMin then Exit(ATop + AHeight / 2);   // no range -> vertical centre
  frac := (AValue - AMin) / (AMax - AMin);
  if frac < 0 then frac := 0 else if frac > 1 then frac := 1;
  Result := ATop + (1 - frac) * AHeight;           // inverted: min -> bottom, max -> top
end;

function TySparklineBaselineY(AMin, AMax, ATop, AHeight: Double): Double;
begin
  { Double(0), not 0: Math.Max with an integer operand beside a Double one resolves to
    the SINGLE overload on FPC 3.2.2, and a large positive min came back rounded to
    24 bits, floating the baseline off the bottom of the band. }
  Result := TySparklineY(Math.Max(Double(0), AMin), AMin, AMax, ATop, AHeight);
end;

{ TTySparkline }

constructor TTySparkline.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FStyle := ssLine;
  FShowLast := True;
  FAutoRange := True;
  FMinValue := 0;
  FMaxValue := 100;
  Width := 120;
  Height := 36;
end;

function TTySparkline.GetStyleTypeKey: string;
begin
  { Its own key, not the gauge's: a data-series surface belongs with the chart/grid
    vocabulary, so a skin can recolour the series without touching clock hands or spinners. }
  Result := 'TySparkline';
end;

function TTySparkline.GetCount: Integer;
begin
  Result := Length(FValues);
end;

procedure TTySparkline.SetValues(const AValues: array of Double);
var i: Integer;
begin
  SetLength(FValues, Length(AValues));
  for i := 0 to High(AValues) do
    FValues[i] := AValues[i];      // copy in (never alias the caller's array)
  Invalidate;
end;

procedure TTySparkline.SetStyle(const AValue: TTySparkStyle);
begin if FStyle = AValue then Exit; FStyle := AValue; Invalidate; end;

procedure TTySparkline.SetShowLast(const AValue: Boolean);
begin if FShowLast = AValue then Exit; FShowLast := AValue; Invalidate; end;

procedure TTySparkline.SetAutoRange(const AValue: Boolean);
begin if FAutoRange = AValue then Exit; FAutoRange := AValue; Invalidate; end;

procedure TTySparkline.SetMinValue(const AValue: Double);
begin if FMinValue = AValue then Exit; FMinValue := AValue; if not FAutoRange then Invalidate; end;

procedure TTySparkline.SetMaxValue(const AValue: Double);
begin if FMaxValue = AValue then Exit; FMaxValue := AValue; if not FAutoRange then Invalidate; end;

procedure TTySparkline.ResolveRange(out AMin, AMax: Double);
var i: Integer;
begin
  if FAutoRange then
  begin
    if Length(FValues) = 0 then begin AMin := 0; AMax := 0; Exit; end;
    AMin := FValues[0];
    AMax := FValues[0];
    for i := 1 to High(FValues) do
    begin
      if FValues[i] < AMin then AMin := FValues[i];
      if FValues[i] > AMax then AMax := FValues[i];
    end;
  end
  else
  begin
    AMin := FMinValue;
    AMax := FMaxValue;
  end;
end;

procedure TTySparkline.DrawLine(P: TTyPainter; const R: TRect; AMin, AMax: Double;
  const AFillS: TTyStyleSet);
var
  ctx: TBGRACanvas2D;
  n, i: Integer;
  x, y, yTop, h, w: Double;
begin
  n := Length(FValues);
  if n = 0 then Exit;
  yTop := R.Top;
  h := R.Bottom - R.Top;
  w := R.Right - R.Left;
  ctx := P.Bitmap.Canvas2D;
  ctx.lineWidth := Math.Max(1, P.Scale(2));
  ctx.lineCap := 'round';
  ctx.strokeStyle(TyColorToBGRA(AFillS.Background.Color));
  if n = 1 then
  begin
    // A single sample has no span — draw a flat mark across the width at its level.
    y := TySparklineY(FValues[0], AMin, AMax, yTop, h);
    ctx.beginPath;
    ctx.moveTo(R.Left, y);
    ctx.lineTo(R.Right, y);
    ctx.stroke;
    Exit;
  end;
  ctx.beginPath;
  for i := 0 to n - 1 do
  begin
    x := R.Left + w * (i / (n - 1));
    y := TySparklineY(FValues[i], AMin, AMax, yTop, h);
    if i = 0 then ctx.moveTo(x, y) else ctx.lineTo(x, y);
  end;
  ctx.stroke;
end;

procedure TTySparkline.DrawBars(P: TTyPainter; const R: TRect; AMin, AMax: Double;
  const AFillS: TTyStyleSet);
var
  n, i, gap, x0, x1, yTop, yBase: Integer;
  slot, baseY, y: Double;
  barR: TRect;
begin
  n := Length(FValues);
  if n = 0 then Exit;
  gap := Math.Max(1, P.Scale(1));
  slot := (R.Right - R.Left) / n;
  // Baseline sits at the bottom of the band (or the min-value line when it is above 0).
  baseY := TySparklineBaselineY(AMin, AMax, R.Top, R.Bottom - R.Top);
  yBase := Round(baseY);
  for i := 0 to n - 1 do
  begin
    x0 := R.Left + Round(i * slot) + gap;
    x1 := R.Left + Round((i + 1) * slot) - gap;
    if x1 <= x0 then x1 := x0 + 1;
    y := TySparklineY(FValues[i], AMin, AMax, R.Top, R.Bottom - R.Top);
    yTop := Round(y);
    if yTop <= yBase then barR := Rect(x0, yTop, x1, yBase)   // value above baseline
    else                   barR := Rect(x0, yBase, x1, yTop); // value below baseline
    if barR.Bottom <= barR.Top then barR.Bottom := barR.Top + 1;
    if barR.Right > barR.Left then
      P.FillBackground(barR, AFillS.Background, TyUniformCorners(0));
  end;
end;

procedure TTySparkline.DrawLastDot(P: TTyPainter; const R: TRect; AMin, AMax: Double;
  const ADotS: TTyStyleSet);
var
  ctx: TBGRACanvas2D;
  n: Integer;
  x, y, rad: Double;
begin
  n := Length(FValues);
  if n = 0 then Exit;
  x := R.Right;   // last point is at the far right for both the 1-point and n-point layouts
  y := TySparklineY(FValues[n - 1], AMin, AMax, R.Top, R.Bottom - R.Top);
  rad := Math.Max(2, P.Scale(3));
  ctx := P.Bitmap.Canvas2D;
  ctx.fillStyle(TyColorToBGRA(ADotS.Background.Color));
  ctx.beginPath;
  ctx.arc(x, y, rad, 0, 2 * Pi, False);
  ctx.fill;
end;

procedure TTySparkline.Paint;
var
  P: TTyPainter;
  frameS, fillS, dotS: TTyStyleSet;
  R, band: TRect;
  pad, baseY: Integer;
  vmin, vmax, by: Double;
  ctx: TBGRACanvas2D;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    frameS := CurrentStyle;                                              // TySparkline frame/baseline/text
    { Sub-part keys derived from the box key so the three can never drift apart. }
    fillS := ActiveController.Model.ResolveStyle(GetStyleTypeKey + 'Fill', StyleClass, []);  // line/bars
    dotS := ActiveController.Model.ResolveStyle(GetStyleTypeKey + 'Dot', StyleClass, []);    // last marker

    DrawFrame(P, R, frameS);   // themed background + border

    // Inset a small pad so the accent never rides the frame edge (leave room for the dot too).
    pad := Math.Max(2, P.Scale(4));
    band := Rect(R.Left + pad, R.Top + pad, R.Right - pad, R.Bottom - pad);
    if (band.Right > band.Left) and (band.Bottom > band.Top) and (Length(FValues) > 0) then
    begin
      ResolveRange(vmin, vmax);

      // Faint baseline at the zero (or min) level, in the frame text colour.
      by := TySparklineBaselineY(vmin, vmax, band.Top, band.Bottom - band.Top);
      baseY := Round(by);
      if (baseY > band.Top) and (baseY < band.Bottom) then
      begin
        ctx := P.Bitmap.Canvas2D;
        ctx.lineWidth := 1;
        ctx.strokeStyle(TyColorToBGRA(frameS.TextColor));
        ctx.beginPath;
        ctx.moveTo(band.Left, baseY + 0.5);
        ctx.lineTo(band.Right, baseY + 0.5);
        ctx.stroke;
      end;

      case FStyle of
        ssBar: DrawBars(P, band, vmin, vmax, fillS);
      else
        DrawLine(P, band, vmin, vmax, fillS);
      end;

      if FShowLast then DrawLastDot(P, band, vmin, vmax, dotS);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
