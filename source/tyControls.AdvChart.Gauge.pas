unit tyControls.AdvChart.Gauge;
{$mode objfpc}{$H+}
{ The gauge: a dial, a needle and a reading.

  IT IS THE ONE SERIES THAT IS NOT LAID OUT IN A BOX. A pie and a funnel both
  take left/top/right/bottom and shrink the canvas; a gauge takes a CENTRE and
  a RADIUS and measures everything from them -- `center: ['50%','50%']` against
  the canvas' width and height separately, `radius: '75%'` against half its
  shorter side. Upstream's own typing offers a gauge calendar and matrix
  placement and then reads neither; there is no box here to honour.

  EVERY OTHER LENGTH IS A FRACTION OF THAT ONE RADIUS. The track, the split
  lines, the ticks, the labels, the needle, the anchor, the name and the
  reading are all `r` minus something, which is why a gauge rescales cleanly
  and why getting `r` wrong gets the whole dial wrong at once.

  THE ANGLES TAKE TWO STEPS, NOT ONE. The option is degrees in the MATH
  convention -- 0 at three o'clock, counting anticlockwise on screen -- so the
  first step negates into the y-down drawing frame. The second normalises the
  pair with the clockwise flag INVERTED, which puts the start into [0, 2pi) and
  leaves the sweep SIGNED: positive clockwise, negative not. A port that stops
  after the negation draws `startAngle: 0, endAngle: 360` as an empty dial
  instead of a full one, and one that takes the magnitude of the sweep mirrors
  every anticlockwise gauge.

  ONE DELIBERATE DIVERGENCE, written down rather than reproduced. Upstream
  reuses the variable holding the dial's end angle as the colour-stop loop's
  own, so after the loop it holds the LAST STOP's angle -- and that is what the
  ticks, the labels and the value-to-angle map are handed. A final stop below 1
  therefore shrinks the scale while the label values stay at min..max: the dial
  reads wrong and says nothing. Switching the track OFF skips the loop and
  fixes it, which is the tell that nobody meant it. Here they are two fields:
  `EndRad` is the dial and `BandEndRad` is where the colours stop. With the
  default single stop at 1 -- and in every gallery option that colours its
  bands -- the two agree.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL --
  colours arrive as numbers and the measuring goes through ITyTextMeasurer. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Color, tyControls.AdvChart.Series,
  tyControls.AdvChart.Symbol, tyControls.AdvChart.Labels,
  tyControls.AdvChart.LabelOpt, tyControls.AdvChart.Handlers;

const
  TyGaugeSeriesTypeName = 'gauge';
  TyGaugeValueDim = 'value';

type
  { One entry of `axisLine.lineStyle.color`, which is an array of
    [fraction, colour] pairs. The fractions are CUMULATIVE UPPER BOUNDS along
    the dial, so [[0.3, red], [1, green]] is red for the first three tenths and
    green for the rest -- not two bands of 0.3 and 1. }
  TTyGaugeStop = record
    Frac: Double;
    HasColour: Boolean;
    Colour: TTyChartColor;
  end;
  TTyGaugeStopArray = array of TTyGaugeStop;

  TTyGaugeAxisLine = record
    Show: Boolean;
    { Not honoured: this library has no capped arc and no stroke line-cap to
      fake one with. Carried so the option is not silently swallowed and so
      the day a Sausage shape exists there is somewhere to read it. }
    RoundCap: Boolean;
    WidthLogical: Double;
    { Empty means the author wrote nothing, and the theme's own track colour
      covers the whole dial. Upstream's default is a literal grey; a literal
      here would be a grey ring on a dark skin. }
    Stops: TTyGaugeStopArray;
  end;

  { splitLine and axisTick are the same shape with different numbers, so they
    are one record. Upstream keeps them apart only because their option trees
    are separate. }
  TTyGaugeTick = record
    Show: Boolean;
    { `'20%'` is twenty per cent of the gauge RADIUS; a bare number is logical
      px. Upstream types splitLine.length as a number and then parses a percent
      out of it anyway -- the declaration is what is wrong, not the code. }
    Len: TTyBoxValue;
    { ADDED TO THE TRACK'S WIDTH, always: a tick starts at
      `r - (distance + axisLineWidth)` and runs inward. So `distance: 0` is not
      a tick touching the rim, it is one starting just inside the track. }
    Distance: Double;
    WidthLogical: Double;
    { `'auto'` means "the colour of the band this tick stands on", which is why
      the stop list is kept after the bands are drawn. }
    Auto: Boolean;
    HasColour: Boolean;
    Colour: TTyChartColor;
    { axisTick only: how many minor ticks per major interval. }
    SplitNumber: Integer;
  end;

  TTyGaugeLabelRotate = (glrNumber, glrRadial, glrTangential);

  TTyGaugeAxisLabel = record
    Show: Boolean;
    { NOT added to the track's width, unlike the ticks -- and that asymmetry is
      upstream's, not a transcription slip. The label ring sits at
      `r - splitLineLen - (axisLabel.distance + splitLine.distance)`, so it is
      coupled to the SPLIT LINE's options and indifferent to how wide the track
      is. A NEGATIVE distance is ordinary: it pushes the labels out past the
      rim, which is what a half-dial does with its scale. }
    Distance: Double;
    Auto: Boolean;
    HasColour: Boolean;
    Colour: TTyChartColor;
    HasFontSize: Boolean;
    FontSizeLogical: Integer;
    HasWeight: Boolean;
    FontWeight: Integer;
    HasFontName: Boolean;
    FontName: string;
    HasFormatter: Boolean;
    Formatter: string;
    Rotate: TTyGaugeLabelRotate;
    RotateDeg: Double;
  end;

  TTyGaugePointer = record
    Show: Boolean;
    ShowAbove: Boolean;
    { Empty means the built-in needle, a four-cornered kite. Anything else goes
      through the symbol layer, `path://` included -- and the two do not mean
      the same thing by `width`: the kite's is a HALF width and the symbol's is
      the whole box. }
    Icon: string;
    OffsetX, OffsetY: TTyBoxValue;
    Len: TTyBoxValue;
    WidthV: TTyBoxValue;
    KeepAspect: Boolean;
    Auto: Boolean;
    HasColour: Boolean;
    Colour: TTyChartColor;
  end;

  TTyGaugeAnchor = record
    Show: Boolean;
    ShowAbove: Boolean;
    { A RAW NUMBER, not a box value: upstream does not parse a percent here, so
      `size: '50%'` is NaN geometry there and is simply ignored here. }
    Size: Double;
    Icon: string;
    OffsetX, OffsetY: TTyBoxValue;
    KeepAspect: Boolean;
    HasFill: Boolean;
    Fill: TTyChartColor;
    BorderWidthLogical: Double;
    HasBorder: Boolean;
    Border: TTyChartColor;
  end;

  { title and detail. One record: they differ in their defaults and in the
    words they carry, not in how they are placed. }
  TTyGaugeText = record
    Show: Boolean;
    OffsetX, OffsetY: TTyBoxValue;
    { `'inherit'` and `'auto'` both mean "take the colour from what this
      labels" -- the progress arc's fill when there is one, otherwise the band
      the value falls in. An ABSENT colour means the same. A written colour
      wins, and both upstream defaults ARE written colours, which is why a
      default gauge's reading does not follow its bands. }
    Auto: Boolean;
    HasColour: Boolean;
    Colour: TTyChartColor;
    HasFontSize: Boolean;
    FontSizeLogical: Integer;
    HasWeight: Boolean;
    FontWeight: Integer;
    HasFontName: Boolean;
    FontName: string;
    HasFormatter: Boolean;
    Formatter: string;
    { The plate behind the words. Upstream's detail has a transparent
      background, a zero border and a padding of [5, 10] -- so the plate is
      always measured and almost never seen. }
    HasBackground: Boolean;
    Background: TTyChartColor;
    BorderWidthLogical: Double;
    HasBorder: Boolean;
    Border: TTyChartColor;
    BorderRadiusLogical: Double;
    { buAuto means "as wide as the words". }
    Width, Height: TTyBoxValue;
    { top, right, bottom, left -- LOGICAL px, CSS order. }
    Padding: array[0..3] of Double;
  end;

  { A per-datum override of the two text blocks. Read from the series' own
    `data` array rather than from the store's override table, because that
    table interns SCALAR leaves and `offsetCenter` is an array -- so the one
    thing a multi-value gauge must set per datum is the one thing the table
    cannot carry. }
  TTyGaugeItem = record
    Title: TTyGaugeText;
    Detail: TTyGaugeText;
  end;
  TTyGaugeItemArray = array of TTyGaugeItem;

  TTyGaugeProgress = record
    Show: Boolean;
    { True stacks every value on the same outer ring and sorts them by z so the
      smallest is on top; False nests them, each in a band of its own. }
    Overlap: Boolean;
    WidthLogical: Double;
    RoundCap: Boolean;
    { False lets a value past max sweep past the end of the dial. }
    Clip: Boolean;
    Auto: Boolean;
    HasColour: Boolean;
    Colour: TTyChartColor;
  end;

  TTyGaugeSpec = record
    CentreX, CentreY: TTyBoxValue;
    Radius: TTyBoxValue;
    StartDeg, EndDeg: Double;
    Clockwise: Boolean;
    Min_, Max_: Double;
    SplitNumber: Integer;
    AxisLine: TTyGaugeAxisLine;
    SplitLine: TTyGaugeTick;
    AxisTick: TTyGaugeTick;
    AxisLabel: TTyGaugeAxisLabel;
    Needle: TTyGaugePointer;
    Anchor: TTyGaugeAnchor;
    Title: TTyGaugeText;
    Detail: TTyGaugeText;
    Progress: TTyGaugeProgress;
  end;

  { What the spec and the viewport come to, in device pixels. }
  TTyGaugeLayout = record
    Valid: Boolean;
    CX, CY, R: Double;
    { Normalised: StartRad is in [0, 2pi), Span is SIGNED and |Span| <= 2pi,
      and EndRad is StartRad + Span and may therefore exceed 2pi or fall below
      zero. Do not wrap it -- the wrap is what tells a full turn from none. }
    StartRad, EndRad, Span: Double;
    { Where the coloured bands stop: the last stop's fraction along the dial.
      Equal to EndRad whenever the last stop is 1. See the unit header. }
    BandEndRad: Double;
    Clockwise: Boolean;
    { The track's width in DEVICE px, carried because every tick is measured
      inward from it. }
    AxisWidth: Double;
  end;

  { Resolved ink. Everything a theme decides, resolved once by the control and
    handed down, so this unit never asks a controller anything. }
  TTyGaugeVisual = record
    { One per RAW row, the same palette rule a pie and a funnel use. }
    Fills: TTyChartColorArray;
    { The dial's own track, for when the author named no colours. }
    Track: TTyChartColor;
    SplitLine: TTyChartColor;
    Tick: TTyChartColor;
    LabelColour: TTyChartColor;
    LabelFontName: string;
    LabelFontSizeLogical: Integer;
    LabelFontWeight: Integer;
    TitleColour: TTyChartColor;
    TitleFontName: string;
    TitleFontSizeLogical: Integer;
    TitleFontWeight: Integer;
    DetailColour: TTyChartColor;
    DetailFontName: string;
    DetailFontSizeLogical: Integer;
    DetailFontWeight: Integer;
    AnchorFill: TTyChartColor;
    AnchorBorder: TTyChartColor;
    Z: Integer;
  end;

function TyGaugeSpecDefault: TTyGaugeSpec;
function TyGaugeSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyGaugeSpec;
{ The per-datum title/detail overrides, indexed by RAW row. }
function TyGaugeItemsOf(AOption: TTyChartOption; ASlot: Integer;
  const ASpec: TTyGaugeSpec): TTyGaugeItemArray;
function TyGaugeVisual: TTyGaugeVisual;

{ Centre, radius and the two angles, from the control's whole rect.

  AViewport IS THE CANVAS, not a grid and not a solved box: `center` resolves
  against its width and height separately and `radius` against half its shorter
  side. A gauge that took a solved box would be laid out in a rectangle nobody
  asked for. }
function TyGaugeLayoutOf(const ASpec: TTyGaugeSpec; const AViewport: TTyRectF;
  APPI: Integer): TTyGaugeLayout;

{ ---- the arithmetic, exported because each is worth testing alone ---- }

{ A value's angle on the dial. AClamp pins out-of-range values to the ends;
  without it they run past them, which is what `progress.clip: false` asks for.
  NaN answers the START angle, which is where upstream parks a needle it cannot
  place. }
function TyGaugeAngleOf(const ALayout: TTyGaugeLayout;
  AMin, AMax, AValue: Double; AClamp: Boolean): Double;

{ Which stop a fraction falls in, bucketed half-open as (previous, this].
  Answers ADefault for an empty list -- upstream indexes the empty array here
  and throws. A NaN fraction answers the LAST stop, because upstream's every
  comparison against it is false and its loop runs off the end. }
function TyGaugeStopColour(const AStops: TTyGaugeStopArray; AFraction: Double;
  ADefault: TTyChartColor): TTyChartColor;

{ The built-in needle, as four device-space points ALREADY ROTATED to AAngle.

  Shapes in this library carry no rotation -- only captions do -- so the kite is
  built where it lands rather than built upright and turned. AHalfWidth is half
  the shoulder span, and the tail behind the pivot is AHalfWidth doubled unless
  the needle is short: `width >= r / 3` flips it, an exact comparison that turns
  a stubby needle into a long-tailed one. Transcribed literally, epsilon and
  all -- there is no epsilon.

  The offset turns WITH the needle, because upstream puts it in the shape and
  rotates the shape. The anchor's and the title's do not. }
function TyGaugeNeedlePoints(ACX, ACY, AAngleRad, AHalfWidth, ALen,
  AOffsetX, AOffsetY: Double): TTyPointFArray;

{ A `(value)` token -- spelt with braces in the option -- substituted FIRST
  OCCURRENCE ONLY, which is what JavaScript's
  String#replace with a string needle does. No formatter answers the number
  as written. }
function TyGaugeFormat(const AFormatter: string; AHasFormatter: Boolean;
  AValue: Double): string;

{ The label at major position AIndex of ASplitNumber, computed FORWARD from
  min -- `i * (max - min) / splitNumber + min`, multiplied before dividing so
  the rounding error lands where upstream's does. }
function TyGaugeLabelValue(AMin, AMax: Double; AIndex,
  ASplitNumber: Integer): Double;

{ ---- the drawing ---- }

{ The dial itself: the coloured bands, the split lines, the ticks and the scale
  labels. Once per series, whatever the data says. }
function TyBuildGaugeAxis(const ABinding: TTySeriesBinding;
  const ALayout: TTyGaugeLayout; const ASpec: TTyGaugeSpec;
  const AVisual: TTyGaugeVisual; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;

{ Everything the data decides: the progress arcs, the needles, the anchor, the
  names and the readings. }
function TyBuildGaugeValue(const ABinding: TTySeriesBinding;
  const ALayout: TTyGaugeLayout; const ASpec: TTyGaugeSpec;
  const AItems: TTyGaugeItemArray; const AVisual: TTyGaugeVisual;
  AStore: TTyDataStore; ADim: Integer; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;

implementation

const
  cRadian = Pi / 180;
  { A sweep under this is no sweep at all. The shape layer will happily emit a
    radial spoke for a zero sweep rather than nothing, so the guard belongs
    here -- and it is a tolerance, not an equality, because an arc a
    ten-millionth of a radian wide is the same invisible spoke. }
  cSweepEps = 1e-9;

{ ==================== reading the option ==================== }

function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

function BoolIn(ANode: TJSONObject; const AKey: string;
  ADefault: Boolean): Boolean;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtBoolean) then Result := d.AsBoolean;
end;

{ TYPE-CHECKED BEFORE COERCING, and the check is the point: `AsString` on an
  array or an object RAISES, and a formatter written as an ARRAY is legal JSON
  that a half-finished edit produces. }
function StrIn(ANode: TJSONObject; const AKey: string;
  const ADefault: string): string;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

function ObjIn(ANode: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtObject) then Result := TJSONObject(d);
end;

{ A colour key that may also be the word `auto` or `inherit`. Both mean "the
  colour of whatever this sits on", which the caller resolves. }
procedure ReadColour(ANode: TJSONObject; const AKey: string;
  var AAuto, AHas: Boolean; var AColour: TTyChartColor);
var
  d: TJSONData;
  s: string;
  c: TTyChartColor;
begin
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  s := LowerCase(Trim(d.AsString));
  if (s = 'auto') or (s = 'inherit') then
  begin
    AAuto := True;
    AHas := False;
    Exit;
  end;
  if TyTryParseChartColor(d.AsString, c) then
  begin
    AAuto := False;
    AHas := True;
    AColour := c;
  end;
end;

{ CSS' four short forms, which is what upstream's `padding` accepts.
  APad is top, right, bottom, left. }
procedure ReadPadding(ANode: TJSONObject; const AKey: string;
  var APad: array of Double);
var
  d: TJSONData;
  a: TJSONArray;
  v: array[0..3] of Double;
  i, n: Integer;
begin
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  if d.JSONType = jtNumber then
  begin
    for i := 0 to 3 do APad[i] := d.AsFloat;
    Exit;
  end;
  if d.JSONType <> jtArray then Exit;
  a := TJSONArray(d);
  n := a.Count;
  if (n < 1) or (n > 4) then Exit;
  for i := 0 to 3 do v[i] := 0;
  for i := 0 to n - 1 do
    if a.Items[i].JSONType = jtNumber then v[i] := a.Items[i].AsFloat;
  case n of
    1: for i := 0 to 3 do APad[i] := v[0];
    2: begin APad[0] := v[0]; APad[1] := v[1]; APad[2] := v[0]; APad[3] := v[1]; end;
    3: begin APad[0] := v[0]; APad[1] := v[1]; APad[2] := v[2]; APad[3] := v[1]; end;
  else
    for i := 0 to 3 do APad[i] := v[i];
  end;
end;

{ A two-element [x, y] option -- `center`, `offsetCenter`. A scalar is not
  accepted here: upstream's centre is always a pair. }
procedure ReadPair(ANode: TJSONObject; const AKey: string;
  var AX, AY: TTyBoxValue);
var
  d: TJSONData;
  a: TJSONArray;
begin
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  a := TJSONArray(d);
  if a.Count > 0 then AX := TyBoxDataOf(a.Items[0], AX);
  if a.Count > 1 then AY := TyBoxDataOf(a.Items[1], AY);
end;

procedure ReadTick(ANode: TJSONObject; const AKey: string;
  var ATick: TTyGaugeTick; AHasSubSplit: Boolean);
var
  n, ls: TJSONObject;
begin
  n := ObjIn(ANode, AKey);
  if n = nil then Exit;
  ATick.Show := BoolIn(n, 'show', ATick.Show);
  ATick.Len := TyBoxValueOf(n, 'length', ATick.Len);
  ATick.Distance := NumIn(n, 'distance', ATick.Distance);
  if AHasSubSplit then
    ATick.SplitNumber := TyTruncOpt(NumIn(n, 'splitNumber', ATick.SplitNumber),
      ATick.SplitNumber, 0, 10000);
  ls := ObjIn(n, 'lineStyle');
  if ls = nil then Exit;
  ATick.WidthLogical := NumIn(ls, 'width', ATick.WidthLogical);
  ReadColour(ls, 'color', ATick.Auto, ATick.HasColour, ATick.Colour);
end;

procedure ReadText(ANode: TJSONObject; const AKey: string;
  var AText: TTyGaugeText; AWantFormatter: Boolean);
var
  n: TJSONObject;
  v: Double;
begin
  n := ObjIn(ANode, AKey);
  if n = nil then Exit;
  AText.Show := BoolIn(n, 'show', AText.Show);
  ReadPair(n, 'offsetCenter', AText.OffsetX, AText.OffsetY);
  ReadColour(n, 'color', AText.Auto, AText.HasColour, AText.Colour);
  v := NumIn(n, 'fontSize', -1);
  if v > 0 then
  begin
    AText.HasFontSize := True;
    AText.FontSizeLogical := TyRoundOpt(v, AText.FontSizeLogical, 1, 4000);
  end;
  if StrIn(n, 'fontFamily', '') <> '' then
  begin
    AText.HasFontName := True;
    AText.FontName := StrIn(n, 'fontFamily', '');
  end;
  if StrIn(n, 'fontWeight', '') <> '' then
  begin
    AText.HasWeight := True;
    if LowerCase(StrIn(n, 'fontWeight', '')) = 'bold' then
      AText.FontWeight := 700
    else if LowerCase(StrIn(n, 'fontWeight', '')) = 'bolder' then
      AText.FontWeight := 800
    else if LowerCase(StrIn(n, 'fontWeight', '')) = 'lighter' then
      AText.FontWeight := 300
    else
      AText.FontWeight := 400;
  end;
  v := NumIn(n, 'fontWeight', -1);
  if v > 0 then
  begin
    AText.HasWeight := True;
    AText.FontWeight := TyRoundOpt(v, 400, 1, 1000);
  end;
  if AWantFormatter then
  begin
    AText.Formatter := StrIn(n, 'formatter', '');
    AText.HasFormatter := AText.Formatter <> '';
  end;
  { The plate. }
  ReadColour(n, 'backgroundColor', AText.Auto, AText.HasBackground,
    AText.Background);
  AText.BorderWidthLogical := NumIn(n, 'borderWidth', AText.BorderWidthLogical);
  ReadColour(n, 'borderColor', AText.Auto, AText.HasBorder, AText.Border);
  AText.BorderRadiusLogical := NumIn(n, 'borderRadius',
    AText.BorderRadiusLogical);
  AText.Width := TyBoxValueOf(n, 'width', AText.Width);
  AText.Height := TyBoxValueOf(n, 'height', AText.Height);
  ReadPadding(n, 'padding', AText.Padding);
end;

function TyGaugeTextDefault: TTyGaugeText;
begin
  Result := Default(TTyGaugeText);
  Result.Show := True;
  Result.OffsetX := TyBoxPx(0);
  Result.OffsetY := TyBoxPx(0);
  Result.Width := TyBoxAuto;
  Result.Height := TyBoxAuto;
end;

function TyGaugeSpecDefault: TTyGaugeSpec;
begin
  Result := Default(TTyGaugeSpec);
  { Every literal below is GaugeSeries.ts:202-326. Geometry only: the colours
    and the fonts are the theme's and arrive in TTyGaugeVisual. }
  Result.CentreX := TyBoxPercent(50);
  Result.CentreY := TyBoxPercent(50);
  Result.Radius := TyBoxPercent(75);
  Result.StartDeg := 225;
  Result.EndDeg := -45;
  Result.Clockwise := True;
  Result.Min_ := 0;
  Result.Max_ := 100;
  Result.SplitNumber := 10;

  Result.AxisLine.Show := True;
  Result.AxisLine.RoundCap := False;
  Result.AxisLine.WidthLogical := 10;

  Result.SplitLine.Show := True;
  Result.SplitLine.Len := TyBoxPx(10);
  Result.SplitLine.Distance := 10;
  Result.SplitLine.WidthLogical := 3;

  Result.AxisTick.Show := True;
  Result.AxisTick.SplitNumber := 5;
  Result.AxisTick.Len := TyBoxPx(6);
  Result.AxisTick.Distance := 10;
  Result.AxisTick.WidthLogical := 1;

  Result.AxisLabel.Show := True;
  Result.AxisLabel.Distance := 15;
  Result.AxisLabel.HasFontSize := True;
  Result.AxisLabel.FontSizeLogical := 12;
  Result.AxisLabel.Rotate := glrNumber;
  Result.AxisLabel.RotateDeg := 0;

  Result.Needle.Show := True;
  Result.Needle.ShowAbove := True;
  Result.Needle.Icon := '';
  Result.Needle.OffsetX := TyBoxPx(0);
  Result.Needle.OffsetY := TyBoxPx(0);
  Result.Needle.Len := TyBoxPercent(60);
  Result.Needle.WidthV := TyBoxPx(6);
  Result.Needle.KeepAspect := False;

  Result.Anchor.Show := False;
  Result.Anchor.ShowAbove := False;
  Result.Anchor.Size := 6;
  Result.Anchor.Icon := 'circle';
  Result.Anchor.OffsetX := TyBoxPx(0);
  Result.Anchor.OffsetY := TyBoxPx(0);
  Result.Anchor.KeepAspect := False;
  Result.Anchor.BorderWidthLogical := 0;

  Result.Title := TyGaugeTextDefault;
  Result.Title.OffsetY := TyBoxPercent(20);
  Result.Title.HasFontSize := True;
  Result.Title.FontSizeLogical := 16;

  Result.Detail := TyGaugeTextDefault;
  Result.Detail.OffsetY := TyBoxPercent(40);
  Result.Detail.HasFontSize := True;
  Result.Detail.FontSizeLogical := 30;
  Result.Detail.HasWeight := True;
  Result.Detail.FontWeight := 700;
  Result.Detail.Width := TyBoxPx(100);
  Result.Detail.Padding[0] := 5;
  Result.Detail.Padding[1] := 10;
  Result.Detail.Padding[2] := 5;
  Result.Detail.Padding[3] := 10;

  Result.Progress.Show := False;
  Result.Progress.Overlap := True;
  Result.Progress.WidthLogical := 10;
  Result.Progress.RoundCap := False;
  Result.Progress.Clip := True;
end;

function ReadStops(ANode: TJSONObject): TTyGaugeStopArray;
var
  d: TJSONData;
  a, pair: TJSONArray;
  i, n: Integer;
  c: TTyChartColor;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find('color');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  a := TJSONArray(d);
  n := 0;
  SetLength(Result, a.Count);
  for i := 0 to a.Count - 1 do
  begin
    { EACH ENTRY IS A PAIR and neither half is validated upstream. An entry
      that is not a two-element array contributes nothing rather than killing
      the render. }
    if a.Items[i].JSONType <> jtArray then Continue;
    pair := TJSONArray(a.Items[i]);
    if pair.Count < 1 then Continue;
    Result[n] := Default(TTyGaugeStop);
    if pair.Items[0].JSONType = jtNumber then Result[n].Frac := pair.Items[0].AsFloat;
    if (pair.Count > 1) and (pair.Items[1].JSONType = jtString)
      and TyTryParseChartColor(pair.Items[1].AsString, c) then
    begin
      Result[n].HasColour := True;
      Result[n].Colour := c;
    end;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function TyGaugeSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyGaugeSpec;
var
  node, n2, ls: TJSONObject;
  d: TJSONData;
  s: string;
  v: Double;
  ignoreAuto: Boolean;
begin
  Result := TyGaugeSpecDefault;
  ignoreAuto := False;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('series', ASlot);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);

  ReadPair(node, 'center', Result.CentreX, Result.CentreY);
  Result.Radius := TyBoxValueOf(node, 'radius', Result.Radius);
  Result.StartDeg := NumIn(node, 'startAngle', Result.StartDeg);
  Result.EndDeg := NumIn(node, 'endAngle', Result.EndDeg);
  Result.Clockwise := BoolIn(node, 'clockwise', Result.Clockwise);
  Result.Min_ := NumIn(node, 'min', Result.Min_);
  Result.Max_ := NumIn(node, 'max', Result.Max_);
  { A COUNT, so it truncates. Floored at zero rather than at one: zero split
    lines is a legal dial and upstream draws one degenerate position for it,
    which the builders guard rather than the reader. }
  Result.SplitNumber := TyTruncOpt(NumIn(node, 'splitNumber',
    Result.SplitNumber), Result.SplitNumber, 0, 10000);

  n2 := ObjIn(node, 'axisLine');
  if n2 <> nil then
  begin
    Result.AxisLine.Show := BoolIn(n2, 'show', Result.AxisLine.Show);
    Result.AxisLine.RoundCap := BoolIn(n2, 'roundCap', Result.AxisLine.RoundCap);
    ls := ObjIn(n2, 'lineStyle');
    if ls <> nil then
    begin
      Result.AxisLine.WidthLogical := NumIn(ls, 'width',
        Result.AxisLine.WidthLogical);
      Result.AxisLine.Stops := ReadStops(ls);
    end;
  end;

  ReadTick(node, 'splitLine', Result.SplitLine, False);
  ReadTick(node, 'axisTick', Result.AxisTick, True);

  n2 := ObjIn(node, 'axisLabel');
  if n2 <> nil then
  begin
    Result.AxisLabel.Show := BoolIn(n2, 'show', Result.AxisLabel.Show);
    Result.AxisLabel.Distance := NumIn(n2, 'distance', Result.AxisLabel.Distance);
    ReadColour(n2, 'color', Result.AxisLabel.Auto, Result.AxisLabel.HasColour,
      Result.AxisLabel.Colour);
    v := NumIn(n2, 'fontSize', -1);
    if v > 0 then
    begin
      Result.AxisLabel.HasFontSize := True;
      Result.AxisLabel.FontSizeLogical := TyRoundOpt(v, 12, 1, 4000);
    end;
    s := StrIn(n2, 'fontFamily', '');
    if s <> '' then
    begin
      Result.AxisLabel.HasFontName := True;
      Result.AxisLabel.FontName := s;
    end;
    s := LowerCase(StrIn(n2, 'fontWeight', ''));
    if s <> '' then
    begin
      Result.AxisLabel.HasWeight := True;
      if s = 'bold' then Result.AxisLabel.FontWeight := 700
      else if s = 'bolder' then Result.AxisLabel.FontWeight := 800
      else if s = 'lighter' then Result.AxisLabel.FontWeight := 300
      else Result.AxisLabel.FontWeight := 400;
    end;
    v := NumIn(n2, 'fontWeight', -1);
    if v > 0 then
    begin
      Result.AxisLabel.HasWeight := True;
      Result.AxisLabel.FontWeight := TyRoundOpt(v, 400, 1, 1000);
    end;
    Result.AxisLabel.Formatter := StrIn(n2, 'formatter', '');
    Result.AxisLabel.HasFormatter := Result.AxisLabel.Formatter <> '';
    { THE THREE ROTATE FORMS, and the third one is a number. A STRING that is
      not one of the two words -- `rotate: '30'` -- leaves the rotation at
      zero upstream, because its `isNumber` test fails and nothing else
      catches it. Reproduced. }
    d := n2.Find('rotate');
    if d <> nil then
    begin
      if d.JSONType = jtString then
      begin
        s := LowerCase(Trim(d.AsString));
        if s = 'radial' then Result.AxisLabel.Rotate := glrRadial
        else if s = 'tangential' then Result.AxisLabel.Rotate := glrTangential;
      end
      else if d.JSONType = jtNumber then
      begin
        Result.AxisLabel.Rotate := glrNumber;
        { CLAMPED BEFORE IT IS MULTIPLIED. 1e308 degrees times Pi/180 is an
          overflow, and the paint layer would carry the infinity into every
          coordinate. }
        Result.AxisLabel.RotateDeg := Max(Double(-360), Min(Double(360),
          d.AsFloat));
      end;
    end;
  end;

  n2 := ObjIn(node, 'pointer');
  if n2 <> nil then
  begin
    Result.Needle.Show := BoolIn(n2, 'show', Result.Needle.Show);
    Result.Needle.ShowAbove := BoolIn(n2, 'showAbove', Result.Needle.ShowAbove);
    Result.Needle.Icon := StrIn(n2, 'icon', Result.Needle.Icon);
    ReadPair(n2, 'offsetCenter', Result.Needle.OffsetX, Result.Needle.OffsetY);
    Result.Needle.Len := TyBoxValueOf(n2, 'length', Result.Needle.Len);
    Result.Needle.WidthV := TyBoxValueOf(n2, 'width', Result.Needle.WidthV);
    Result.Needle.KeepAspect := BoolIn(n2, 'keepAspect',
      Result.Needle.KeepAspect);
    ReadColour(ObjIn(n2, 'itemStyle'), 'color', Result.Needle.Auto,
      Result.Needle.HasColour, Result.Needle.Colour);
  end;

  n2 := ObjIn(node, 'anchor');
  if n2 <> nil then
  begin
    Result.Anchor.Show := BoolIn(n2, 'show', Result.Anchor.Show);
    Result.Anchor.ShowAbove := BoolIn(n2, 'showAbove', Result.Anchor.ShowAbove);
    Result.Anchor.Size := NumIn(n2, 'size', Result.Anchor.Size);
    Result.Anchor.Icon := StrIn(n2, 'icon', Result.Anchor.Icon);
    ReadPair(n2, 'offsetCenter', Result.Anchor.OffsetX, Result.Anchor.OffsetY);
    Result.Anchor.KeepAspect := BoolIn(n2, 'keepAspect',
      Result.Anchor.KeepAspect);
    ls := ObjIn(n2, 'itemStyle');
    if ls <> nil then
    begin
      { NO `auto` ON THE HUB. Upstream reads the anchor's itemStyle with the
        plain style mapper, which never looks for the word, so `color: 'auto'`
        there is a colour that will not parse and the hub falls back. The flag
        is taken and dropped. }
      ReadColour(ls, 'color', ignoreAuto, Result.Anchor.HasFill,
        Result.Anchor.Fill);
      Result.Anchor.BorderWidthLogical := NumIn(ls, 'borderWidth',
        Result.Anchor.BorderWidthLogical);
      ReadColour(ls, 'borderColor', ignoreAuto, Result.Anchor.HasBorder,
        Result.Anchor.Border);
    end;
  end;

  ReadText(node, 'title', Result.Title, False);
  ReadText(node, 'detail', Result.Detail, True);

  n2 := ObjIn(node, 'progress');
  if n2 <> nil then
  begin
    Result.Progress.Show := BoolIn(n2, 'show', Result.Progress.Show);
    Result.Progress.Overlap := BoolIn(n2, 'overlap', Result.Progress.Overlap);
    Result.Progress.WidthLogical := NumIn(n2, 'width',
      Result.Progress.WidthLogical);
    Result.Progress.RoundCap := BoolIn(n2, 'roundCap',
      Result.Progress.RoundCap);
    Result.Progress.Clip := BoolIn(n2, 'clip', Result.Progress.Clip);
    ReadColour(ObjIn(n2, 'itemStyle'), 'color', Result.Progress.Auto,
      Result.Progress.HasColour, Result.Progress.Colour);
  end;
end;

function TyGaugeItemsOf(AOption: TTyChartOption; ASlot: Integer;
  const ASpec: TTyGaugeSpec): TTyGaugeItemArray;
var
  d: TJSONData;
  node: TJSONObject;
  arr: TJSONArray;
  i: Integer;
begin
  Result := nil;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('series', ASlot);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('data');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  arr := TJSONArray(d);
  SetLength(Result, arr.Count);
  for i := 0 to arr.Count - 1 do
  begin
    Result[i].Title := ASpec.Title;
    Result[i].Detail := ASpec.Detail;
    if arr.Items[i].JSONType <> jtObject then Continue;
    ReadText(TJSONObject(arr.Items[i]), 'title', Result[i].Title, False);
    ReadText(TJSONObject(arr.Items[i]), 'detail', Result[i].Detail, True);
  end;
end;

function TyGaugeVisual: TTyGaugeVisual;
begin
  Result := Default(TTyGaugeVisual);
  Result.Z := 2;
  Result.LabelFontSizeLogical := 12;
  Result.LabelFontWeight := 400;
  Result.TitleFontSizeLogical := 16;
  Result.TitleFontWeight := 400;
  Result.DetailFontSizeLogical := 30;
  Result.DetailFontWeight := 700;
end;

{ ==================== the layout ==================== }

{ A dial length: a PERCENTAGE is of the radius and is already device px, a bare
  number is LOGICAL px and scales with the screen. }
function DialLen(const AValue: TTyBoxValue; AR: Double; APPI: Integer): Double;
begin
  Result := TyBoxResolve(AValue, AR);
  if AValue.Kind = buPx then Result := Result * APPI / 96;
end;

function TyGaugeLayoutOf(const ASpec: TTyGaugeSpec; const AViewport: TTyRectF;
  APPI: Integer): TTyGaugeLayout;
var
  base, startA, endA, frac: Double;
begin
  Result := Default(TTyGaugeLayout);
  if not TyRectFIsValid(AViewport) then Exit;
  TySolveCircle(ASpec.CentreX, ASpec.CentreY, AViewport, Result.CX, Result.CY,
    base);
  Result.R := DialLen(ASpec.Radius, base, APPI);
  if IsNan(Result.R) or (Result.R <= 0) then Exit;
  Result.AxisWidth := ASpec.AxisLine.WidthLogical * APPI / 96;

  { STEP ONE: the option's degrees are the MATH convention and the drawing
    frame has y pointing down, so the sign flips. }
  startA := -ASpec.StartDeg * cRadian;
  endA := -ASpec.EndDeg * cRadian;
  { STEP TWO, and the flag is INVERTED on the way in. }
  TyNormalizeArcAngles(startA, endA, not ASpec.Clockwise);
  Result.StartRad := startA;
  Result.EndRad := endA;
  Result.Span := endA - startA;
  Result.Clockwise := ASpec.Clockwise;

  Result.BandEndRad := endA;
  if ASpec.AxisLine.Show and (Length(ASpec.AxisLine.Stops) > 0) then
  begin
    frac := ASpec.AxisLine.Stops[High(ASpec.AxisLine.Stops)].Frac;
    if IsNan(frac) then frac := 0;
    frac := Max(Double(0), Min(Double(1), frac));
    Result.BandEndRad := startA + Result.Span * frac;
  end;
  Result.Valid := True;
end;

{ ==================== the arithmetic ==================== }

function TyGaugeAngleOf(const ALayout: TTyGaugeLayout;
  AMin, AMax, AValue: Double; AClamp: Boolean): Double;
begin
  { NaN FIRST, because everything below compares. An ordered comparison
    against a quiet NaN raises here rather than answering False. }
  if IsNan(AValue) then Exit(ALayout.StartRad);
  Result := TyLinearMap(AValue, AMin, AMax, ALayout.StartRad, ALayout.EndRad,
    AClamp);
end;

function TyGaugeStopColour(const AStops: TTyGaugeStopArray; AFraction: Double;
  ADefault: TTyChartColor): TTyChartColor;
var
  i: Integer;
  prev: Double;

  function Answer(AIndex: Integer): TTyChartColor;
  begin
    if AStops[AIndex].HasColour then Result := AStops[AIndex].Colour
    else Result := ADefault;
  end;

begin
  { EMPTY IS THE CASE UPSTREAM CANNOT SURVIVE: it reads colorList[0] before
    looking, and colorList[-1] after. }
  if Length(AStops) = 0 then Exit(ADefault);
  { A NaN FRACTION LANDS ON THE LAST STOP, because upstream's every comparison
    against it is false and its loop runs off the end. Reached by a test here
    rather than by a comparison, because comparing against NaN raises. }
  if IsNan(AFraction) then Exit(Answer(High(AStops)));
  if AFraction <= 0 then Exit(Answer(0));
  for i := 0 to High(AStops) do
  begin
    if IsNan(AStops[i].Frac) then Continue;
    if i = 0 then prev := 0 else prev := AStops[i - 1].Frac;
    if IsNan(prev) then prev := 0;
    if (AStops[i].Frac >= AFraction) and (prev < AFraction) then Exit(Answer(i));
  end;
  Result := Answer(High(AStops));
end;

function TyGaugeNeedlePoints(ACX, ACY, AAngleRad, AHalfWidth, ALen,
  AOffsetX, AOffsetY: Double): TTyPointFArray;
var
  s, c, bx, by, k: Double;
begin
  Result := nil;
  if IsNan(AAngleRad) or IsNan(AHalfWidth) or IsNan(ALen) then Exit;
  if IsNan(AOffsetX) or IsNan(AOffsetY) then Exit;
  s := Sin(AAngleRad);
  c := Cos(AAngleRad);
  { THE OFFSET TURNS WITH THE NEEDLE. Composing upstream's element rotation
    with its local frame gives x' = -sin*lx - cos*ly, y' = cos*lx - sin*ly --
    which is why `offsetCenter: [0, 10]` pushes the needle BACKWARDS along its
    own axis rather than down the screen. }
  bx := ACX - s * AOffsetX - c * AOffsetY;
  by := ACY + c * AOffsetX - s * AOffsetY;
  { THE TAIL IS ONE HALF-WIDTH OR TWO, and the switch is exact. A short needle
    -- `width >= r / 3` -- keeps a stubby tail; everything longer gets a tail
    twice the shoulder's half-span. }
  if AHalfWidth >= ALen / 3 then k := 1 else k := 2;
  SetLength(Result, 4);
  Result[0] := TyPointF(bx - AHalfWidth * k * c, by - AHalfWidth * k * s);
  Result[1] := TyPointF(bx + AHalfWidth * s, by - AHalfWidth * c);
  Result[2] := TyPointF(bx + ALen * c, by + ALen * s);
  Result[3] := TyPointF(bx - AHalfWidth * s, by + AHalfWidth * c);
end;

(* A RICH-TEXT RUN, DEGRADED TO ITS WORDS. A formatter of `{a|83}{b| km/h}`
   names two styles the author declared under `rich:` and this port does not
   draw; printed as written it is line noise where a reading should be, and a
   gauge whose only job is to show a number showing `{a|83}` is worse than one
   showing `83`.

   NESTED, because `{a|{value}}` is the commonest form there is and the
   substitution above turns it into `{a|83}` before this runs -- but an
   unsubstituted brace has to survive the walk rather than unbalance it.

   An opening brace with no bar before the next brace is NOT a run, so a
   `{value}` nobody substituted stays exactly as it was.

   PARENTHESISED, not braced: an FPC comment NESTS, so a brace inside one
   opens a level and the file ends before it closes. *)
function StripRich(const AText: string): string;
var
  i, j, depth: Integer;
  isRun: Boolean;
begin
  Result := '';
  i := 1;
  depth := 0;
  while i <= Length(AText) do
  begin
    if AText[i] = '{' then
    begin
      (* Look ahead for the bar that makes it a run. *)
      isRun := False;
      j := i + 1;
      while j <= Length(AText) do
      begin
        if AText[j] = '|' then begin isRun := True; Break; end;
        if (AText[j] = '{') or (AText[j] = '}') then Break;
        Inc(j);
      end;
      if isRun then
      begin
        Inc(depth);
        i := j + 1;
        Continue;
      end;
    end
    else if (AText[i] = '}') and (depth > 0) then
    begin
      Dec(depth);
      Inc(i);
      Continue;
    end;
    Result := Result + AText[i];
    Inc(i);
  end;
end;

function TyGaugeFormat(const AFormatter: string; AHasFormatter: Boolean;
  AValue: Double): string;
begin
  Result := TyChartNumToStr(AValue);
  if not AHasFormatter then Exit;
  Result := TyReplaceFirst(AFormatter, '{value}', Result);
  Result := StripRich(Result);
  { ONE LINE. A caption is drawn as a single run here, so a formatter with
    real line breaks in it would draw its first line and a row of boxes.
    Flattened rather than dropped: the words are still the answer. }
  Result := StringReplace(Result, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
end;

function TyGaugeLabelValue(AMin, AMax: Double; AIndex,
  ASplitNumber: Integer): Double;
begin
  { UPSTREAM DIVIDES BY splitNumber HERE WITH NO GUARD, so `splitNumber: 0`
    is 0/0 in JavaScript -- NaN, and every label reads NaN. Here it would
    raise, and a dial with no divisions still has its two ends. }
  if ASplitNumber = 0 then Exit(AMin);
  { MULTIPLIED BEFORE IT IS DIVIDED, which is upstream's own comment: it keeps
    the error out of the label rather than rounding it away afterwards. }
  Result := AIndex * (AMax - AMin) / ASplitNumber + AMin;
end;

{ ==================== the dial ==================== }

{ THE CAPS OF A ROUND-CAPPED BAND, upstream's Sausage: a half-disc of radius
  half the band's thickness, centred on the band's midline at each end.

  Drawn as WHOLE discs rather than halves, because the band itself covers the
  inner half of each and the two are the same colour. A half-disc would need a
  shape this library does not have; a disc needs one it does. }
procedure AddCaps(const ALayout: TTyGaugeLayout; AR0, AR1, AFrom, ATo: Double;
  AFill: TTyChartColor; AZ, AZ2: Integer; AList: TTyPaintList;
  var ACount: Integer);
var
  dr, rc: Double;
  el: TTyChartElement;

  procedure Cap(AAngle: Double);
  begin
    el := TyChartElement(TyShapeCircle(ALayout.CX + Cos(AAngle) * rc,
      ALayout.CY + Sin(AAngle) * rc, dr));
    el.Style.HasFill := True;
    el.Style.FillColor := AFill;
    el.Z := AZ;
    el.Z2 := AZ2;
    el.Silent := True;
    AList.Add(el);
    Inc(ACount);
  end;

begin
  dr := (AR1 - AR0) / 2;
  if dr <= 0 then Exit;
  rc := AR0 + dr;
  Cap(AFrom);
  Cap(ATo);
end;

{ One band of the track. }
function BandElement(const ALayout: TTyGaugeLayout; AFrom, ATo: Double;
  AFill: TTyChartColor; AZ: Integer): TTyChartElement;
begin
  Result := TyChartElement(TyShapeSector(ALayout.CX, ALayout.CY,
    Max(Double(0), ALayout.R - ALayout.AxisWidth), ALayout.R, AFrom, ATo));
  Result.Style.HasFill := True;
  Result.Style.FillColor := AFill;
  Result.Z := AZ;
  Result.Z2 := 0;
  { A TRACK IS NOT A TARGET. Upstream marks every sector silent; a hover on the
    band behind the needle would report a datum the band does not stand for. }
  Result.Silent := True;
end;

function TickElement(AX1, AY1, AX2, AY2: Double; AColour: TTyChartColor;
  AWidthLogical: Double; AZ: Integer): TTyChartElement;
begin
  Result := TyChartElement(TyShapePolyline([TyPointF(AX1, AY1),
    TyPointF(AX2, AY2)]));
  Result.Style.StrokeColor := AColour;
  Result.Style.StrokeWidthLogical := AWidthLogical;
  Result.Z := AZ;
  Result.Z2 := 0;
  Result.Silent := True;
end;

function TyBuildGaugeAxis(const ABinding: TTySeriesBinding;
  const ALayout: TTyGaugeLayout; const ASpec: TTyGaugeSpec;
  const AVisual: TTyGaugeVisual; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;
var
  i, j, subN, splitN: Integer;
  prevEnd, endA, frac, step, subStep, angle, unitX, unitY: Double;
  splitLen, tickLen, dist, labelDist, x1, y1, x2, y2, tx, ty: Double;
  w, h, rot: Double;
  fsize, fweight: Integer;
  fname: string;
  bands: array of TTyChartElement;
  el: TTyChartElement;
  words: string;
  anchorH: TTyTextAnchorH;
  anchorV: TTyTextAnchorV;
  box: TTyRectF;
begin
  Result := 0;
  if (AList = nil) or not ALayout.Valid then Exit;
  if not ABinding.Resolved then Exit;

  { ---- the track ---- }
  if ASpec.AxisLine.Show and (ALayout.AxisWidth > 0) then
  begin
    if Length(ASpec.AxisLine.Stops) = 0 then
    begin
      { NO STOPS MEANS ONE BAND, in the theme's own track colour. Upstream's
        default is a single stop at 1 holding a literal grey; the literal is
        what a theme replaces. }
      if Abs(ALayout.Span) > cSweepEps then
      begin
        if ASpec.AxisLine.RoundCap then
          AddCaps(ALayout, Max(Double(0), ALayout.R - ALayout.AxisWidth),
            ALayout.R, ALayout.StartRad, ALayout.EndRad, AVisual.Track,
            AVisual.Z, 0, AList, Result);
        AList.Add(BandElement(ALayout, ALayout.StartRad, ALayout.EndRad,
          AVisual.Track, AVisual.Z));
        Inc(Result);
      end;
    end
    else
    begin
      SetLength(bands, Length(ASpec.AxisLine.Stops));
      j := 0;
      prevEnd := ALayout.StartRad;
      for i := 0 to High(ASpec.AxisLine.Stops) do
      begin
        frac := ASpec.AxisLine.Stops[i].Frac;
        if IsNan(frac) then frac := 0;
        frac := Max(Double(0), Min(Double(1), frac));
        endA := ALayout.StartRad + ALayout.Span * frac;
        if Abs(endA - prevEnd) > cSweepEps then
        begin
          if ASpec.AxisLine.Stops[i].HasColour then
            bands[j] := BandElement(ALayout, prevEnd, endA,
              ASpec.AxisLine.Stops[i].Colour, AVisual.Z)
          else
            bands[j] := BandElement(ALayout, prevEnd, endA, AVisual.Track,
              AVisual.Z);
          Inc(j);
        end;
        prevEnd := endA;
      end;
      { ADDED BACKWARDS. Upstream reverses the list before adding it, so the
        FIRST stop ends up topmost -- which only shows when stops overlap, and
        they can, because nothing requires them to ascend. }
      for i := j - 1 downto 0 do
      begin
        if ASpec.AxisLine.RoundCap then
          AddCaps(ALayout, bands[i].Shape.R0, bands[i].Shape.R1,
            bands[i].Shape.StartRad, bands[i].Shape.EndRad,
            bands[i].Style.FillColor, AVisual.Z, 0, AList, Result);
        AList.Add(bands[i]);
        Inc(Result);
      end;
    end;
  end;

  splitN := ASpec.SplitNumber;
  subN := ASpec.AxisTick.SplitNumber;
  { NEITHER DIVISOR IS GUARDED UPSTREAM. `splitNumber: 0` makes the step
    Infinity there and then NaN, and every position after the first is lost;
    here it would raise. One position is what a dial with no divisions has. }
  if splitN < 1 then splitN := 0;
  if subN < 1 then subN := 0;

  { MEASURED WHETHER OR NOT THE SPLIT LINES ARE DRAWN, because the LABELS are
    placed inward of it -- upstream computes it before the show test and the
    labels read it. Hiding the split lines does not move the labels out. }
  splitLen := DialLen(ASpec.SplitLine.Len, ALayout.R, APPI);
  tickLen := DialLen(ASpec.AxisTick.Len, ALayout.R, APPI);

  if splitN = 0 then step := 0
  else step := ALayout.Span / splitN;
  if subN = 0 then subStep := 0 else subStep := step / subN;

  for i := 0 to splitN do
  begin
    { COMPUTED FORWARD rather than accumulated. Upstream adds one sub-step at a
      time and backs one off at the end of each interval; the two differ by
      about 1e-13 radians over a whole dial, which is nowhere near a pixel, and
      forward is the one that cannot drift. }
    angle := ALayout.StartRad + i * step;
    unitX := Cos(angle);
    unitY := Sin(angle);

    if ASpec.SplitLine.Show and (ASpec.SplitLine.WidthLogical > 0) then
    begin
      dist := ASpec.SplitLine.Distance * APPI / 96 + ALayout.AxisWidth;
      x1 := unitX * (ALayout.R - dist) + ALayout.CX;
      y1 := unitY * (ALayout.R - dist) + ALayout.CY;
      x2 := unitX * (ALayout.R - splitLen - dist) + ALayout.CX;
      y2 := unitY * (ALayout.R - splitLen - dist) + ALayout.CY;
      if ASpec.SplitLine.Auto then
        el := TickElement(x1, y1, x2, y2,
          TyGaugeStopColour(ASpec.AxisLine.Stops, i / Max(splitN, 1),
            AVisual.SplitLine), ASpec.SplitLine.WidthLogical, AVisual.Z)
      else if ASpec.SplitLine.HasColour then
        el := TickElement(x1, y1, x2, y2, ASpec.SplitLine.Colour,
          ASpec.SplitLine.WidthLogical, AVisual.Z)
      else
        el := TickElement(x1, y1, x2, y2, AVisual.SplitLine,
          ASpec.SplitLine.WidthLogical, AVisual.Z);
      AList.Add(el);
      Inc(Result);
    end;

    if ASpec.AxisLabel.Show then
    begin
      { THE ONE RADIUS THAT DOES NOT COUNT THE TRACK, and it borrows the SPLIT
        LINE's distance as well as its own. Both are upstream's. }
      labelDist := (ASpec.AxisLabel.Distance + ASpec.SplitLine.Distance)
        * APPI / 96;
      tx := unitX * (ALayout.R - splitLen - labelDist) + ALayout.CX;
      ty := unitY * (ALayout.R - splitLen - labelDist) + ALayout.CY;
      words := TyGaugeFormat(ASpec.AxisLabel.Formatter,
        ASpec.AxisLabel.HasFormatter,
        TyGaugeLabelValue(ASpec.Min_, ASpec.Max_, i, splitN));
      if words <> '' then
      begin
        rot := 0;
        case ASpec.AxisLabel.Rotate of
          glrRadial:
            begin
              rot := -angle + 2 * Pi;
              { NOT MODULAR, and upstream's is not either: past one turn the
                flip silently stops happening. Kept literal. }
              if rot > Pi / 2 then rot := rot + Pi;
            end;
          glrTangential: rot := -angle - Pi / 2;
        else
          rot := ASpec.AxisLabel.RotateDeg * cRadian;
        end;

        anchorH := tahCentre;
        anchorV := tavMiddle;
        if rot = 0 then
        begin
          { THE THRESHOLDS ARE NOT SYMMETRIC -- 0.8 vertically and 0.4
            horizontally -- so a label at forty-five degrees is pinned by its
            right edge and centred vertically. Upstream's numbers. }
          if unitY < -0.8 then anchorV := tavTop
          else if unitY > 0.8 then anchorV := tavBottom
          else anchorV := tavMiddle;
          if unitX < -0.4 then anchorH := tahLeft
          else if unitX > 0.4 then anchorH := tahRight
          else anchorH := tahCentre;
        end;

        { RESOLVED BEFORE IT IS MEASURED, and that ordering is the whole of it:
          the option's own font size beats the theme's, and measuring in one
          and drawing in the other leaves the words in a box too small for
          them. The renderer draws INTO the shape's rect, so `100` came out
          as `00`. }
        fname := AVisual.LabelFontName;
        fsize := AVisual.LabelFontSizeLogical;
        fweight := AVisual.LabelFontWeight;
        if ASpec.AxisLabel.HasFontName then fname := ASpec.AxisLabel.FontName;
        if ASpec.AxisLabel.HasFontSize then
          fsize := ASpec.AxisLabel.FontSizeLogical;
        if ASpec.AxisLabel.HasWeight then
          fweight := ASpec.AxisLabel.FontWeight;
        AMeasurer.MeasureLine(words, fname, fsize, fweight, w, h);
        if (w > 0) and (h > 0) then
        begin
          box := TyAnchorBox(tx, ty, w, h, anchorH, anchorV);
          el := TyChartElement(TyShapeRect(box));
          el.Caption.Text := words;
          el.Caption.FontName := fname;
          el.Caption.FontSizeLogical := fsize;
          el.Caption.FontWeight := fweight;
          if ASpec.AxisLabel.HasColour then
            el.Caption.Colour := ASpec.AxisLabel.Colour
          else if ASpec.AxisLabel.Auto then
            el.Caption.Colour := TyGaugeStopColour(ASpec.AxisLine.Stops,
              i / Max(splitN, 1), AVisual.LabelColour)
          else
            el.Caption.Colour := AVisual.LabelColour;
          el.Caption.X := tx;
          el.Caption.Y := ty;
          el.Caption.AnchorH := anchorH;
          el.Caption.AnchorV := anchorV;
          el.Caption.RotationRad := rot;
          el.Caption.Truncate := False;
          el.Z := AVisual.Z;
          el.Z2 := 0;
          el.Silent := True;
          AList.Add(el);
          Inc(Result);
        end;
      end;
    end;

    { THE LAST MAJOR POSITION GETS NO MINOR TICKS, because its interval runs
      off the end of the dial. }
    if ASpec.AxisTick.Show and (i <> splitN) and (subN > 0)
      and (ASpec.AxisTick.WidthLogical > 0) then
    begin
      dist := ASpec.AxisTick.Distance * APPI / 96 + ALayout.AxisWidth;
      { `j <= subN` IS UPSTREAM'S OWN BOUND, so the last minor tick of one
        interval lands exactly on the first of the next and every interior
        major position carries two coincident lines. Invisible with an opaque
        stroke, twice as dark with a translucent one. Reproduced, because
        thinning it changes where a translucent tick's darkness falls. }
      for j := 0 to subN do
      begin
        angle := ALayout.StartRad + (i + j / subN) * step;
        unitX := Cos(angle);
        unitY := Sin(angle);
        x1 := unitX * (ALayout.R - dist) + ALayout.CX;
        y1 := unitY * (ALayout.R - dist) + ALayout.CY;
        x2 := unitX * (ALayout.R - tickLen - dist) + ALayout.CX;
        y2 := unitY * (ALayout.R - tickLen - dist) + ALayout.CY;
        if ASpec.AxisTick.Auto then
          el := TickElement(x1, y1, x2, y2,
            TyGaugeStopColour(ASpec.AxisLine.Stops,
              (i + j / subN) / Max(splitN, 1), AVisual.Tick),
            ASpec.AxisTick.WidthLogical, AVisual.Z)
        else if ASpec.AxisTick.HasColour then
          el := TickElement(x1, y1, x2, y2, ASpec.AxisTick.Colour,
            ASpec.AxisTick.WidthLogical, AVisual.Z)
        else
          el := TickElement(x1, y1, x2, y2, AVisual.Tick,
            ASpec.AxisTick.WidthLogical, AVisual.Z);
        AList.Add(el);
        Inc(Result);
      end;
    end;
  end;
end;

{ ==================== the data ==================== }

{ One text block -- a name or a reading -- with its plate. }
function AddGaugeText(const AText: TTyGaugeText; const AWords: string;
  ACX, ACY, AR: Double; ADefaultColour, AAutoColour: TTyChartColor;
  const AFontName: string; AFontSize, AWeight, AZ, AZ2: Integer;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AList: TTyPaintList): Integer;
var
  x, y, w, h, bw, bh, padH, padV, scale: Double;
  el: TTyChartElement;
  box: TTyRectF;
  fname: string;
  fsize, fweight: Integer;
begin
  Result := 0;
  if not AText.Show then Exit;
  if AWords = '' then Exit;
  scale := APPI / 96;
  x := ACX + DialLen(AText.OffsetX, AR, APPI);
  y := ACY + DialLen(AText.OffsetY, AR, APPI);
  fname := AFontName;
  fsize := AFontSize;
  fweight := AWeight;
  if AText.HasFontName then fname := AText.FontName;
  if AText.HasFontSize then fsize := AText.FontSizeLogical;
  if AText.HasWeight then fweight := AText.FontWeight;
  AMeasurer.MeasureLine(AWords, fname, fsize, fweight, w, h);
  if (w <= 0) or (h <= 0) then Exit;

  padH := (AText.Padding[1] + AText.Padding[3]) * scale;
  padV := (AText.Padding[0] + AText.Padding[2]) * scale;
  bw := w;
  bh := h;
  if AText.Width.Kind <> buAuto then bw := DialLen(AText.Width, AR, APPI);
  if AText.Height.Kind <> buAuto then bh := DialLen(AText.Height, AR, APPI);

  { THE PLATE, and it is measured even when it is invisible: upstream's
    detail carries a transparent background and a zero border, so the box
    exists, takes part in the bounds, and paints nothing. Only a real fill or
    a real border is emitted here. }
  if (AText.HasBackground or (AText.HasBorder
    and (AText.BorderWidthLogical > 0))) then
  begin
    box := TyAnchorBox(x, y, bw + padH, bh + padV, tahCentre, tavMiddle);
    if AText.BorderRadiusLogical > 0 then
      el := TyChartElement(TyShapeRoundRect(box,
        AText.BorderRadiusLogical * scale))
    else
      el := TyChartElement(TyShapeRect(box));
    if AText.HasBackground then
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := AText.Background;
    end;
    if AText.HasBorder and (AText.BorderWidthLogical > 0) then
    begin
      el.Style.StrokeColor := AText.Border;
      el.Style.StrokeWidthLogical := AText.BorderWidthLogical;
    end;
    el.Z := AZ;
    el.Z2 := AZ2;
    el.Silent := True;
    AList.Add(el);
    Inc(Result);
  end;

  box := TyAnchorBox(x, y, w, h, tahCentre, tavMiddle);
  el := TyChartElement(TyShapeRect(box));
  el.Caption.Text := AWords;
  el.Caption.FontName := fname;
  el.Caption.FontSizeLogical := fsize;
  el.Caption.FontWeight := fweight;
  if AText.HasColour then el.Caption.Colour := AText.Colour
  else if AText.Auto then el.Caption.Colour := AAutoColour
  else el.Caption.Colour := ADefaultColour;
  el.Caption.X := x;
  el.Caption.Y := y;
  el.Caption.AnchorH := tahCentre;
  el.Caption.AnchorV := tavMiddle;
  el.Caption.RotationRad := 0;
  el.Caption.Truncate := False;
  el.Z := AZ;
  el.Z2 := AZ2;
  el.Silent := True;
  AList.Add(el);
  Inc(Result);
end;

function TyBuildGaugeValue(const ABinding: TTySeriesBinding;
  const ALayout: TTyGaugeLayout; const ASpec: TTyGaugeSpec;
  const AItems: TTyGaugeItemArray; const AVisual: TTyGaugeVisual;
  AStore: TTyDataStore; ADim: Integer; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;
var
  k, raw, n, textZ2: Integer;
  val, frac, angle, endA, pw, r0, r1, len, halfW, ox, oy, scale: Double;
  fill, autoC: TTyChartColor;
  el: TTyChartElement;
  pts: TTyPointFArray;
  ti: TTyGaugeItem;
  box: TTyRectF;
  sym: TTySymbolSpec;
  empty: Boolean;
  pathBody: string;
begin
  Result := 0;
  if (AList = nil) or (AStore = nil) or not ALayout.Valid then Exit;
  if not ABinding.Resolved then Exit;
  if (ADim < 0) or (ADim >= AStore.DimCount) then Exit;
  n := AStore.Count;
  if n = 0 then Exit;
  scale := APPI / 96;
  { `pointer.showAbove` DOES NOT LIFT THE POINTER -- it LOWERS the words.
    Upstream never sets a z2 on the needle; what the flag writes is the
    title's and the reading's. }
  if ASpec.Needle.ShowAbove then textZ2 := 0 else textZ2 := 2;

  { ---- the names and the readings, first ---- }
  for k := 0 to n - 1 do
  begin
    raw := AStore.GetRawIndex(k);
    val := AStore.Get(ADim, k);
    frac := TyLinearMap(val, ASpec.Min_, ASpec.Max_, 0, 1, True);
    if IsNan(val) then frac := NaN;
    autoC := TyGaugeStopColour(ASpec.AxisLine.Stops, frac, AVisual.Track);
    { WHEN THERE IS A PROGRESS ARC, `inherit` follows IT rather than the band
      under the value -- upstream chooses between the two on progress.show
      alone. }
    if ASpec.Progress.Show then
    begin
      if (raw >= 0) and (raw <= High(AVisual.Fills)) then
        autoC := AVisual.Fills[raw];
    end;
    ti.Title := ASpec.Title;
    ti.Detail := ASpec.Detail;
    if (raw >= 0) and (raw <= High(AItems)) then ti := AItems[raw];
    Inc(Result, AddGaugeText(ti.Title, AStore.GetName(k),
      ALayout.CX, ALayout.CY, ALayout.R, AVisual.TitleColour, autoC,
      AVisual.TitleFontName, AVisual.TitleFontSizeLogical,
      AVisual.TitleFontWeight, AVisual.Z, textZ2, AMeasurer, APPI, AList));
    Inc(Result, AddGaugeText(ti.Detail,
      TyGaugeFormat(ti.Detail.Formatter, ti.Detail.HasFormatter, val),
      ALayout.CX, ALayout.CY, ALayout.R, AVisual.DetailColour, autoC,
      AVisual.DetailFontName, AVisual.DetailFontSizeLogical,
      AVisual.DetailFontWeight, AVisual.Z, textZ2, AMeasurer, APPI, AList));
  end;

  { ---- the anchor, once, whatever the data says ---- }
  if ASpec.Anchor.Show and (ASpec.Anchor.Size > 0) then
  begin
    ox := ALayout.CX + DialLen(ASpec.Anchor.OffsetX, ALayout.R, APPI);
    oy := ALayout.CY + DialLen(ASpec.Anchor.OffsetY, ALayout.R, APPI);
    len := ASpec.Anchor.Size * scale;
    box := TyRectF(ox - len / 2, oy - len / 2, ox + len / 2, oy + len / 2);
    sym := TySymbolDefault(TyGaugeSeriesTypeName);
    sym.Kind := TySymbolKindOf(ASpec.Anchor.Icon, empty, pathBody);
    sym.Empty := empty;
    sym.PathData := pathBody;
    sym.KeepAspect := ASpec.Anchor.KeepAspect;
    el := TyChartElement(TyBuildSymbolInBox(sym, box));
    el.Style.HasFill := True;
    if ASpec.Anchor.HasFill then el.Style.FillColor := ASpec.Anchor.Fill
    else el.Style.FillColor := AVisual.AnchorFill;
    if ASpec.Anchor.BorderWidthLogical > 0 then
    begin
      el.Style.StrokeWidthLogical := ASpec.Anchor.BorderWidthLogical;
      if ASpec.Anchor.HasBorder then el.Style.StrokeColor := ASpec.Anchor.Border
      else el.Style.StrokeColor := AVisual.AnchorBorder;
    end;
    el.Z := AVisual.Z;
    if ASpec.Anchor.ShowAbove then el.Z2 := 1 else el.Z2 := 0;
    el.Silent := True;
    AList.Add(el);
    Inc(Result);
  end;

  { ---- the arcs and the needles ---- }
  for k := 0 to n - 1 do
  begin
    raw := AStore.GetRawIndex(k);
    val := AStore.Get(ADim, k);
    frac := TyLinearMap(val, ASpec.Min_, ASpec.Max_, 0, 1, True);
    if IsNan(val) then frac := NaN;
    fill := AVisual.Track;
    if (raw >= 0) and (raw <= High(AVisual.Fills)) then fill := AVisual.Fills[raw];
    autoC := TyGaugeStopColour(ASpec.AxisLine.Stops, frac, fill);

    if ASpec.Progress.Show then
    begin
      if ASpec.Progress.Overlap then
      begin
        pw := ASpec.Progress.WidthLogical * scale;
        r0 := ALayout.R - pw;
        r1 := ALayout.R;
      end
      else
      begin
        pw := ALayout.AxisWidth / n;
        r0 := ALayout.R - (k + 1) * pw;
        r1 := ALayout.R - k * pw;
      end;
      endA := TyGaugeAngleOf(ALayout, ASpec.Min_, ASpec.Max_, val,
        ASpec.Progress.Clip);
      if (not IsNan(endA)) and (Abs(endA - ALayout.StartRad) > cSweepEps)
        and (r1 > 0) then
      begin
        el := TyChartElement(TyShapeSector(ALayout.CX, ALayout.CY,
          Max(Double(0), r0), r1, ALayout.StartRad, endA));
        el.Style.HasFill := True;
        if ASpec.Progress.HasColour then el.Style.FillColor := ASpec.Progress.Colour
        else if ASpec.Progress.Auto then el.Style.FillColor := autoC
        else el.Style.FillColor := fill;
        el.Z := AVisual.Z;
        { AN INVERTED RANGE, deliberately: the SMALLEST value paints on top, so
          a short arc is not buried under a long one. Rounded to an integer
          because this list orders by an integer z2 -- two values within one
          per cent of each other therefore tie and fall back to data order. }
        if ASpec.Progress.Overlap then
          el.Z2 := TyRoundOpt(TyLinearMap(val, ASpec.Min_, ASpec.Max_, 100, 0,
            True), 0, 0, 100)
        else
          el.Z2 := 0;
        el.Silent := False;
        el.Datum := TyChartDatum(ABinding.SeriesIndex, k, raw);
        if ASpec.Progress.RoundCap then
          AddCaps(ALayout, Max(Double(0), r0), r1, ALayout.StartRad, endA,
            el.Style.FillColor, AVisual.Z, el.Z2, AList, Result);
        AList.Add(el);
        Inc(Result);
      end;
    end;

    if ASpec.Needle.Show then
    begin
      angle := TyGaugeAngleOf(ALayout, ASpec.Min_, ASpec.Max_, val, True);
      len := DialLen(ASpec.Needle.Len, ALayout.R, APPI);
      halfW := DialLen(ASpec.Needle.WidthV, ALayout.R, APPI);
      ox := DialLen(ASpec.Needle.OffsetX, ALayout.R, APPI);
      oy := DialLen(ASpec.Needle.OffsetY, ALayout.R, APPI);
      if ASpec.Needle.Icon = '' then
      begin
        pts := TyGaugeNeedlePoints(ALayout.CX, ALayout.CY, angle, halfW, len,
          ox, oy);
        if Length(pts) = 4 then
        begin
          el := TyChartElement(TyShapePolygon(pts));
          el.Style.HasFill := True;
          if ASpec.Needle.HasColour then el.Style.FillColor := ASpec.Needle.Colour
          else if ASpec.Needle.Auto then el.Style.FillColor := autoC
          else el.Style.FillColor := fill;
          el.Z := AVisual.Z;
          el.Z2 := 0;
          el.Silent := False;
          el.Datum := TyChartDatum(ABinding.SeriesIndex, k, raw);
          AList.Add(el);
          Inc(Result);
        end;
      end
      else
      begin
        { AN ICON MEANS SOMETHING ELSE BY `width`: the box is the whole width
          and its BOTTOM EDGE sits on the pivot, so nothing is drawn behind it.
          The box is built upright in the dial's own frame and the shape is
          turned about the pivot, which is the only rotation this library
          carries -- and it carries it for a path and nothing else. }
        sym := TySymbolDefault(TyGaugeSeriesTypeName);
        sym.Kind := TySymbolKindOf(ASpec.Needle.Icon, empty, pathBody);
        sym.Empty := empty;
        sym.PathData := pathBody;
        sym.KeepAspect := ASpec.Needle.KeepAspect;
        box := TyRectF(ALayout.CX + ox - halfW / 2, ALayout.CY + oy - len,
          ALayout.CX + ox + halfW / 2, ALayout.CY + oy);
        el := TyChartElement(TyBuildSymbolInBox(sym, box));
        { THE BOX IS BUILT POINTING UP and then turned, so the angle is the
          value's plus a quarter turn -- an icon at twelve o'clock is the
          value angle -Pi/2 and wants no rotation at all. Upstream says the
          same thing with the opposite sign, because its element rotation
          counts anticlockwise and this painter's counts clockwise.

          ABOUT THE HUB, not about the box. `offsetCenter` lives in the frame
          that turns, so the offset has to be carried round by the same
          rotation -- turning the box about its own foot leaves a needle
          meant to sit two thirds of the way out sitting at the centre,
          tilted. }
        if el.Shape.Kind = cskPath then
          el.Shape := TyShapePath(el.Shape.PathData, el.Shape.Bounds,
            angle + Pi / 2, ALayout.CX, ALayout.CY);
        el.Style.HasFill := True;
        if ASpec.Needle.HasColour then el.Style.FillColor := ASpec.Needle.Colour
        else if ASpec.Needle.Auto then el.Style.FillColor := autoC
        else el.Style.FillColor := fill;
        el.Z := AVisual.Z;
        el.Z2 := 0;
        el.Silent := False;
        el.Datum := TyChartDatum(ABinding.SeriesIndex, k, raw);
        AList.Add(el);
        Inc(Result);
      end;
    end;
  end;
end;

end.
