unit tyControls.AdvChart.Radar;
{$mode objfpc}{$H+}
{ The radar: a coordinate system made of spokes, and the series drawn on it.

  IT IS THE FIRST COORDINATE SYSTEM IN THIS PORT THAT IS NOT A RECTANGLE, and
  almost everything awkward about it follows from that. The grid layer, the
  axis-thickness solver and the axis painter all begin by asking which SIDE of
  a rect an axis lives on; a spoke has no side. So a radar lays itself out, and
  draws its own furniture into the paint list, the way a pie and a funnel do --
  the sharing stops at the axis object and the scale behind it, which are
  geometry-free and carry the whole value-to-position mapping already.

  THE ANGLES ARE THE MATHS CONVENTION, KEPT. Upstream does NOT negate a radar's
  startAngle the way it negates a pie's; instead `coordToPoint` subtracts the
  sine:

      x = cx + coord * cos(angle)
      y = cy - coord * sin(angle)

  so the angle counts anticlockwise on screen and `startAngle: 90` points the
  first indicator straight up. Two consequences a transcription gets wrong:
  the default `clockwise: false` means indicator 1, 2, 3 run ANTICLOCKWISE, and
  every angle handed to this unit's own point function must NOT be passed on to
  a painter that measures clockwise without flipping its sine first.

  EVERY RING IS EVENLY SPACED, whatever the axis' own ticks say. Upstream
  force-aligns every indicator axis to one dummy scale of exactly `splitNumber`
  intervals, so ring k sits at `r0 + (r - r0) * k / splitNumber` on every spoke
  and the label at that ring is `min + (max - min) * k / splitNumber`. A port
  that drew a ring per nice tick would give one indicator six rings and its
  neighbour five, and the polygon rings would not close.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Scale,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Color, tyControls.AdvChart.Series,
  tyControls.AdvChart.Symbol, tyControls.AdvChart.Labels,
  tyControls.AdvChart.LabelOpt, tyControls.AdvChart.Handlers;

const
  TyRadarSeriesTypeName = 'radar';
  TyRadarCoordSysName = 'radar';
  { The dimension an indicator axis carries, `indicator_<i>` upstream. }
  TyRadarDimPrefix = 'indicator_';

type
  TTyRadarShape = (rsPolygon, rsCircle);

  { One spoke's declaration. `min` and `max` are ABSENT rather than zero, and
    the absence is load-bearing -- see TyRadarIndicatorExtent. }
  TTyRadarIndicator = record
    Name: string;
    HasMin, HasMax: Boolean;
    Min_, Max_: Double;
    HasColour: Boolean;
    Colour: TTyChartColor;
  end;
  TTyRadarIndicatorArray = array of TTyRadarIndicator;

  TTyRadarNameSpec = record
    Show: Boolean;
    HasColour: Boolean;
    Colour: TTyChartColor;
    HasFontSize: Boolean;
    FontSizeLogical: Integer;
    HasFormatter: Boolean;
    Formatter: string;
    GapLogical: Double;
  end;

  { axisLine and splitLine. The colour is an ARRAY because a split line may
    alternate; a single colour is one entry, which is what makes "alternating"
    and "not alternating" the same code. }
  TTyRadarLineSpec = record
    Show: Boolean;
    WidthLogical: Double;
    Colours: TTyChartColorArray;
  end;

  TTyRadarAreaSpec = record
    Show: Boolean;
    Colours: TTyChartColorArray;
  end;

  TTyRadarTickSpec = record
    Show: Boolean;
    LengthLogical: Double;
  end;

  TTyRadarLabelSpec = record
    Show: Boolean;
    MarginLogical: Double;
    HasColour: Boolean;
    Colour: TTyChartColor;
    HasFontSize: Boolean;
    FontSizeLogical: Integer;
  end;

  TTyRadarSpec = record
    CentreX, CentreY: TTyBoxValue;
    { `radius: '50%'` is normalised to [0, '50%'] -- a scalar is the OUTER
      radius and the hole is nothing. }
    R0V, R1V: TTyBoxValue;
    StartDeg: Double;
    Clockwise: Boolean;
    SplitNumber: Integer;
    { `scale: false` is the default and means "include zero", which is what
      actually produces the familiar min of 0. }
    Scale_: Boolean;
    Shape: TTyRadarShape;
    AxisName: TTyRadarNameSpec;
    AxisLine: TTyRadarLineSpec;
    AxisTick: TTyRadarTickSpec;
    AxisLabel: TTyRadarLabelSpec;
    SplitLine: TTyRadarLineSpec;
    SplitArea: TTyRadarAreaSpec;
    Indicators: TTyRadarIndicatorArray;
  end;

  { The coordinate system. Non-refcounted, like the cartesian and for the same
    reason: the chart owns it while the box containers that hold an ITyCoordSys
    are temporaries. }
  TTyRadar = class(TTyNonRefCountedObject, ITyCoordSys)
  private
    FSpec: TTyRadarSpec;
    FAxes: array of TTyAxis;
    FAngles: TTyDoubleArray;
    FCX, FCY, FR0, FR1: Double;
    FValid: Boolean;
    FRect: TTyRectF;
    FPPI: Integer;
    { EACH SPOKE'S ALIGNED TICKS, and where each lands -- empty for a spoke
      whose extent was set bare, which then falls back to even spacing. }
    FTicks: array of TTyDoubleArray;
    FCoords: array of TTyDoubleArray;
    { Which spokes were aligned: an aligned spoke with no ticks at all -- a
      step rounded to nothing -- has no rings, which is not the same as a
      spoke set bare. }
    FAligned: array of Boolean;
  public
    constructor Create(const ASpec: TTyRadarSpec);
    destructor Destroy; override;
    { Centre, radii and the spoke angles, from the CONTROL's rect. A radar has
      no left/top/right/bottom at all -- its option carries no box -- so this
      is the canvas and nothing shrinks it. }
    procedure Resize(const AViewport: TTyRectF; APPI: Integer);
    { The value range of one spoke, after the whole min/max chain, set BARE --
      no alignment, rings evenly spaced. }
    procedure SetAxisExtent(AIndex: Integer; ALo, AHi: Double);
    { UPSTREAM'S RADAR: the spoke's raw extent aligned to a dummy scale of
      exactly splitNumber segments (scaleCalcAlign), with which ends the
      author fixed and whether zero is included -- over the spoke's LOGICAL
      pixel span, which decides how the step is rounded when both ends are
      fixed. The rings then stand at the aligned ticks. }
    procedure AlignAxis(AIndex: Integer; ALo, AHi: Double;
      AFixLo, AFixHi, AIncl0: Boolean);
    { How many rings past the centre: the fewest any spoke has on a polygon,
      the first spoke's on a circle; splitNumber on a spoke set bare. }
    function RingCount: Integer;
    { Ring k's radius on spoke AIndex: where its tick lands. }
    function RingRadiusOf(AIndex, AK: Integer): Double;
    function AxisExtent(AIndex: Integer): TTyRange;
    { A radius, in device px, to a point. }
    function CoordToPoint(ACoord: Double; AIndex: Integer): TTyPointF;
    { A value on spoke AIndex to a point. }
    function ValueToPoint(AValue: Double; AIndex: Integer): TTyPointF;
    function AngleOf(AIndex: Integer): Double;
    { Ring k's radius on the FIRST spoke -- the circle's. }
    function RingRadius(AK: Integer): Double;
    { The value ring k stands for on spoke AIndex. }
    function RingValue(AIndex, AK: Integer): Double;
    { ---- ITyCoordSys ---- }
    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;
    function DataToPoint(const AData: array of Double): TTyPointF;
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    function PointToData(const APoint: TTyPointF;
      out AData: TTyDoubleArray): Boolean;
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): TTyAxis;
    property CX: Double read FCX;
    property CY: Double read FCY;
    property R0: Double read FR0;
    property R1: Double read FR1;
    property Valid: Boolean read FValid;
    property Spec: TTyRadarSpec read FSpec;
  end;

  { Resolved ink, the same seam every other series uses: the control asks the
    theme, this unit never does. }
  TTyRadarInk = record
    AxisLine: TTyChartColor;
    SplitLine: TTyChartColor;
    SplitAreaA, SplitAreaB: TTyChartColor;
    Tick: TTyChartColor;
    NameColour: TTyChartColor;
    NameFontName: string;
    NameFontSizeLogical: Integer;
    NameFontWeight: Integer;
    LabelColour: TTyChartColor;
    LabelFontName: string;
    LabelFontSizeLogical: Integer;
    LabelFontWeight: Integer;
    Z: Integer;
  end;

  TTyRadarVisual = record
    { ONE COLOUR PER RAW ROW. A radar colours by DATUM, not by series: two
      rings on one radar are two rows of one series and have to be told apart,
      which is also what makes the legend name them. Fill is the fallback for
      a row the palette has nothing for. }
    Fills: TTyChartColorArray;
    Fill: TTyChartColor;
    LineWidthLogical: Double;
    { areaStyle. Absent means no filled polygon at all, which is upstream's
      rule and not a style detail: a radar with no areaStyle is a wire. }
    HasArea: Boolean;
    { True only when the author named a colour for it -- otherwise the area
      follows the ROW, which is the whole point of colouring by datum. }
    AreaAuthored: Boolean;
    Area: TTyChartColor;
    AreaOpacity: Double;
    Symbol: TTySymbolSpec;
    EmptyFill: TTyChartColor;
    Z: Integer;
    Z2: Integer;
  end;

function TyRadarSpecDefault: TTyRadarSpec;
function TyRadarSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyRadarSpec;
function TyRadarInk: TTyRadarInk;
function TyRadarVisual(AFill: TTyChartColor): TTyRadarVisual;

{ ---- the arithmetic, exported because each is worth testing alone ---- }

{ Spoke AIndex's angle, in the MATHS convention: anticlockwise from
  screen-right, with y taken to point down at the point-building step.

  Normalised into (-Pi, Pi] the way upstream does it, with atan2 of its own
  sine and cosine -- which is not decoration: the alignment table for an axis
  name is written against that range and reads a bare 3*Pi/2 as the wrong
  quadrant. }
function TyRadarAngle(AStartRad: Double; AIndex, ACount: Integer;
  AClockwise: Boolean): Double;

{ The whole min/max chain for one spoke, in upstream's order.

  ADataLo/ADataHi are the data's own extent, or NaN when there is no data.
  AScale is the option's `scale`, and it is INVERTED on the way in: `false`,
  the default, means "include zero".

  The three rules that matter, and each is easy to miss:
    * a written `max` above zero pins `min` to zero (and the mirror image),
      and the test is FALSY rather than a null check, so an explicit `min: 0`
      counts as unset;
    * with `scale` off, an all-positive range has its floor dropped to zero and
      an all-negative range has its ceiling raised to it -- but only on the end
      the author did not write;
    * a range of no width is expanded rather than left flat, and HOW depends on
      whether zero was included. }
procedure TyRadarIndicatorExtent(const AInd: TTyRadarIndicator;
  ADataLo, ADataHi: Double; AScale: Boolean; out ALo, AHi: Double);
{ THE SAME, with which ends the author fixed (after the pre-pass) and whether
  zero is included -- what the alignment needs. The flags stay BY INDEX when
  a reversed pair is swapped: `min: 3` over data at 1 is [1, 3] with the LOW
  end fixed. }
procedure TyRadarIndicatorExtent(const AInd: TTyRadarIndicator;
  ADataLo, ADataHi: Double; AScale: Boolean; out ALo, AHi: Double;
  out AFixLo, AFixHi, AIncl0: Boolean);

(* The value token -- spelt with braces in the option -- substituted into an
   axis name's formatter, FIRST OCCURRENCE ONLY.

   Parenthesised: an FPC comment NESTS, so a brace inside a braced one opens a
   level the file never closes. *)
function TyRadarNameText(const AInd: TTyRadarIndicator;
  const ASpec: TTyRadarNameSpec): string;

{ Which colour bucket ring or band AIndex falls in. Answers False for an empty
  list -- upstream takes a remainder by the length and gets NaN, which silently
  draws nothing; here it would raise. }
function TyRadarBucket(const AColours: TTyChartColorArray; AIndex: Integer;
  out AColour: TTyChartColor): Boolean;

{ ---- the drawing ---- }

{ The radar's own furniture: split areas, split lines, spokes, ticks, scale
  labels and indicator names. Once per radar, whatever the data says. }
function TyBuildRadarGrid(ARadar: TTyRadar; const AInk: TTyRadarInk;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AList: TTyPaintList): Integer;

{ One series: the ring, the area under it and a symbol per spoke. }
function TyBuildRadarMarks(const ABinding: TTySeriesBinding; ARadar: TTyRadar;
  const AVisual: TTyRadarVisual; AStore: TTyDataStore;
  const ADims: TTyIntegerArray; APPI: Integer; AList: TTyPaintList): Integer;

implementation

const
  cRadian = Pi / 180;

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

{ TYPE-CHECKED BEFORE COERCING: AsString on an array or an object RAISES, and
  a half-finished edit produces exactly that. }
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

{ A colour key that may be one colour or a LIST of them. One colour comes back
  as a one-entry list, which is what makes "alternating" and "not alternating"
  the same code downstream. }
function ColoursIn(ANode: TJSONObject; const AKey: string;
  const ADefault: TTyChartColorArray): TTyChartColorArray;
var
  d: TJSONData;
  a: TJSONArray;
  i, n: Integer;
  c: TTyChartColor;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  if d.JSONType = jtString then
  begin
    if TyTryParseChartColor(d.AsString, c) then
    begin
      SetLength(Result, 1);
      Result[0] := c;
    end;
    Exit;
  end;
  if d.JSONType <> jtArray then Exit;
  a := TJSONArray(d);
  SetLength(Result, a.Count);
  n := 0;
  for i := 0 to a.Count - 1 do
    if (a.Items[i].JSONType = jtString)
      and TyTryParseChartColor(a.Items[i].AsString, c) then
    begin
      Result[n] := c;
      Inc(n);
    end;
  SetLength(Result, n);
end;

procedure ReadLine(ANode: TJSONObject; const AKey: string;
  var ALine: TTyRadarLineSpec);
var n, ls: TJSONObject;
begin
  n := ObjIn(ANode, AKey);
  if n = nil then Exit;
  ALine.Show := BoolIn(n, 'show', ALine.Show);
  ls := ObjIn(n, 'lineStyle');
  if ls = nil then Exit;
  ALine.WidthLogical := NumIn(ls, 'width', ALine.WidthLogical);
  ALine.Colours := ColoursIn(ls, 'color', ALine.Colours);
end;

function TyRadarSpecDefault: TTyRadarSpec;
begin
  Result := Default(TTyRadarSpec);
  { RadarModel.ts:201-244. Geometry and counts only; every colour comes from
    the theme through TTyRadarInk. }
  Result.CentreX := TyBoxPercent(50);
  Result.CentreY := TyBoxPercent(50);
  Result.R0V := TyBoxPx(0);
  Result.R1V := TyBoxPercent(50);
  { NINETY DEGREES, and NOT negated: a radar counts anticlockwise and its point
    function subtracts the sine, so 90 is straight up. }
  Result.StartDeg := 90;
  Result.Clockwise := False;
  Result.SplitNumber := 5;
  Result.Scale_ := False;
  Result.Shape := rsPolygon;

  Result.AxisName.Show := True;
  Result.AxisName.GapLogical := 15;

  Result.AxisLine.Show := True;
  Result.AxisLine.WidthLogical := 1;

  { OFF BY DEFAULT, both of them -- upstream flips the value axis' own defaults
    for a radar, so a plain radar shows its rings and its names and nothing
    else. }
  Result.AxisTick.Show := False;
  Result.AxisTick.LengthLogical := 5;
  Result.AxisLabel.Show := False;
  Result.AxisLabel.MarginLogical := 8;

  Result.SplitLine.Show := True;
  Result.SplitLine.WidthLogical := 1;
  { AND SPLIT AREA IS ON, which is the other flip: a cartesian value axis
    defaults it off. }
  Result.SplitArea.Show := True;
end;

function TyRadarInk: TTyRadarInk;
begin
  Result := Default(TTyRadarInk);
  Result.NameFontSizeLogical := 12;
  Result.NameFontWeight := 400;
  Result.LabelFontSizeLogical := 12;
  Result.LabelFontWeight := 400;
  Result.Z := 0;
end;

function TyRadarVisual(AFill: TTyChartColor): TTyRadarVisual;
begin
  Result := Default(TTyRadarVisual);
  Result.Fill := AFill;
  Result.LineWidthLogical := 2;
  Result.HasArea := False;
  Result.AreaOpacity := 0.7;
  Result.Symbol := TySymbolDefault(TyRadarSeriesTypeName);
  Result.Z := 2;
  Result.Z2 := 0;
end;

function ReadIndicators(ANode: TJSONObject): TTyRadarIndicatorArray;
var
  d: TJSONData;
  a: TJSONArray;
  o: TJSONObject;
  i, n: Integer;
  c: TTyChartColor;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find('indicator');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  a := TJSONArray(d);
  SetLength(Result, a.Count);
  n := 0;
  for i := 0 to a.Count - 1 do
  begin
    if a.Items[i].JSONType <> jtObject then Continue;
    o := TJSONObject(a.Items[i]);
    Result[n] := Default(TTyRadarIndicator);
    { `text` IS THE OLD SPELLING and it loses to `name`, because the merge that
      introduces it runs with the indicator's own keys winning. }
    Result[n].Name := StrIn(o, 'text', '');
    Result[n].Name := StrIn(o, 'name', Result[n].Name);
    d := o.Find('min');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      Result[n].HasMin := True;
      Result[n].Min_ := d.AsFloat;
    end;
    d := o.Find('max');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      Result[n].HasMax := True;
      Result[n].Max_ := d.AsFloat;
    end;
    if TyTryParseChartColor(StrIn(o, 'color', ''), c) then
    begin
      Result[n].HasColour := True;
      Result[n].Colour := c;
    end;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function TyRadarSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyRadarSpec;
var
  node, n2, ts: TJSONObject;
  d: TJSONData;
  a: TJSONArray;
  s: string;
  v: Double;
begin
  Result := TyRadarSpecDefault;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('radar', ASlot);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);

  d := node.Find('center');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    a := TJSONArray(d);
    if a.Count > 0 then Result.CentreX := TyBoxDataOf(a.Items[0], Result.CentreX);
    if a.Count > 1 then Result.CentreY := TyBoxDataOf(a.Items[1], Result.CentreY);
  end;
  { A SCALAR RADIUS IS THE OUTER ONE. Upstream normalises `'50%'` to
    `[0, '50%']` rather than to `['50%', '50%']`, so a radar with one number
    has no hole. }
  d := node.Find('radius');
  if d <> nil then
  begin
    if d.JSONType = jtArray then
    begin
      a := TJSONArray(d);
      if a.Count > 0 then Result.R0V := TyBoxDataOf(a.Items[0], Result.R0V);
      if a.Count > 1 then Result.R1V := TyBoxDataOf(a.Items[1], Result.R1V);
    end
    else
    begin
      Result.R0V := TyBoxPx(0);
      Result.R1V := TyBoxDataOf(d, Result.R1V);
    end;
  end;

  Result.StartDeg := NumIn(node, 'startAngle', Result.StartDeg);
  Result.Clockwise := BoolIn(node, 'clockwise', Result.Clockwise);
  { upstream's ensureValidSplitNumber: zero, NaN and everything falsy are the
    default five, then Math.round(max(it, 1)) -- 2.5 is THREE. Capped at a
    thousand, which upstream is not. [Revised in batch 48: rounded the
    banker's way, so 2.5 was two.] }
  v := NumIn(node, 'splitNumber', Result.SplitNumber);
  Result.SplitNumber := Min(TyValidSplitNumber(v, 5), 1000);
  Result.Scale_ := BoolIn(node, 'scale', Result.Scale_);
  { COMPARED WHOLE against the one word. `'Circle'` and every typo draw a
    polygon, silently, which is upstream's behaviour and not a slip here. }
  if StrIn(node, 'shape', '') = 'circle' then Result.Shape := rsCircle;

  n2 := ObjIn(node, 'axisName');
  if n2 <> nil then
  begin
    Result.AxisName.Show := BoolIn(n2, 'show', Result.AxisName.Show);
    s := StrIn(n2, 'color', '');
    if TyTryParseChartColor(s, Result.AxisName.Colour) then
      Result.AxisName.HasColour := True;
    v := NumIn(n2, 'fontSize', -1);
    if v > 0 then
    begin
      Result.AxisName.HasFontSize := True;
      Result.AxisName.FontSizeLogical := TyRoundOpt(v, 12, 1, 4000);
    end;
    Result.AxisName.Formatter := StrIn(n2, 'formatter', '');
    Result.AxisName.HasFormatter := Result.AxisName.Formatter <> '';
  end;
  Result.AxisName.GapLogical := NumIn(node, 'axisNameGap',
    Result.AxisName.GapLogical);

  ReadLine(node, 'axisLine', Result.AxisLine);
  ReadLine(node, 'splitLine', Result.SplitLine);

  n2 := ObjIn(node, 'axisTick');
  if n2 <> nil then
  begin
    Result.AxisTick.Show := BoolIn(n2, 'show', Result.AxisTick.Show);
    Result.AxisTick.LengthLogical := NumIn(n2, 'length',
      Result.AxisTick.LengthLogical);
  end;

  n2 := ObjIn(node, 'axisLabel');
  if n2 <> nil then
  begin
    Result.AxisLabel.Show := BoolIn(n2, 'show', Result.AxisLabel.Show);
    Result.AxisLabel.MarginLogical := NumIn(n2, 'margin',
      Result.AxisLabel.MarginLogical);
    if TyTryParseChartColor(StrIn(n2, 'color', ''), Result.AxisLabel.Colour) then
      Result.AxisLabel.HasColour := True;
    v := NumIn(n2, 'fontSize', -1);
    if v > 0 then
    begin
      Result.AxisLabel.HasFontSize := True;
      Result.AxisLabel.FontSizeLogical := TyRoundOpt(v, 12, 1, 4000);
    end;
  end;

  n2 := ObjIn(node, 'splitArea');
  if n2 <> nil then
  begin
    Result.SplitArea.Show := BoolIn(n2, 'show', Result.SplitArea.Show);
    ts := ObjIn(n2, 'areaStyle');
    if ts <> nil then
      Result.SplitArea.Colours := ColoursIn(ts, 'color',
        Result.SplitArea.Colours);
  end;

  Result.Indicators := ReadIndicators(node);
end;

{ ==================== the arithmetic ==================== }

function TyRadarAngle(AStartRad: Double; AIndex, ACount: Integer;
  AClockwise: Boolean): Double;
var
  sign, a: Double;
begin
  { GUARDED HERE, NOT HOISTED. Upstream reaches this division only from inside
    a loop over the axes, so it never divides by zero -- but the obvious
    transcription lifts `2*Pi / Count` above the loop and does. }
  if ACount <= 0 then Exit(AStartRad);
  if AClockwise then sign := -1 else sign := 1;
  a := AStartRad + sign * AIndex * 2 * Pi / ACount;
  { atan2 OF ITS OWN SINE AND COSINE, which folds into (-Pi, Pi]. Not
    decoration: the name-alignment table is written against that range. }
  Result := ArcTan2(Sin(a), Cos(a));
end;

procedure TyRadarIndicatorExtent(const AInd: TTyRadarIndicator;
  ADataLo, ADataHi: Double; AScale: Boolean; out ALo, AHi: Double);
var fl, fh, z: Boolean;
begin
  TyRadarIndicatorExtent(AInd, ADataLo, ADataHi, AScale, ALo, AHi, fl, fh, z);
end;

procedure TyRadarIndicatorExtent(const AInd: TTyRadarIndicator;
  ADataLo, ADataHi: Double; AScale: Boolean; out ALo, AHi: Double;
  out AFixLo, AFixHi, AIncl0: Boolean);
var
  ind: TTyRadarIndicator;
  t: Double;
begin
  ind := AInd;
  { THE PRE-PASS, and its tests are FALSY rather than null checks: a written
    `min: 0` counts as unset. It also runs whatever `scale` says -- a radar
    with `scale: true` and a written `max` still has its floor pinned to
    zero, and that is the ONLY fixture that can tell this pass from the
    include-zero one below, which does the same job for every default.

    THE `or (ind.Min_ = 0)` HALF IS AN EQUIVALENT MUTANT and is recorded here
    rather than chased: where it differs -- a written min that is already zero
    -- the branch it admits assigns that same zero back. It is kept because it
    says what upstream's falsy test MEANS, and the day the branch does
    anything else the two stop agreeing. }
  if ind.HasMax and (ind.Max_ > 0) and ((not ind.HasMin) or (ind.Min_ = 0)) then
  begin
    ind.HasMin := True;
    ind.Min_ := 0;
  end
  else if ind.HasMin and (ind.Min_ < 0)
    and ((not ind.HasMax) or (ind.Max_ = 0)) then
  begin
    ind.HasMax := True;
    ind.Max_ := 0;
  end;

  ALo := ADataLo;
  AHi := ADataHi;
  if ind.HasMin then ALo := ind.Min_;
  if ind.HasMax then AHi := ind.Max_;
  AFixLo := ind.HasMin;
  AFixHi := ind.HasMax;
  AIncl0 := not AScale;

  { NO DATA AND NO DECLARATION is an axis of nothing, which upstream ends up
    calling 0..1. Tested with IsNan first, because every comparison below
    would raise on one. }
  if IsNan(ALo) or IsNan(AHi) or IsInfinite(ALo) or IsInfinite(AHi) then
  begin
    ALo := 0;
    AHi := 1;
    Exit;
  end;

  { `scale: false` -- the default -- MEANS INCLUDE ZERO, and only on the end
    the author left alone. }
  if not AScale then
  begin
    if (ALo > 0) and (AHi > 0) and (not ind.HasMin) then ALo := 0;
    if (ALo < 0) and (AHi < 0) and (not ind.HasMax) then AHi := 0;
  end;

  { SWAPPED, THE FLAGS NOT: they stay by index. }
  if ALo > AHi then
  begin
    t := ALo;
    ALo := AHi;
    AHi := t;
  end;
  { A RANGE OF NO WIDTH IS LEFT FLAT HERE. It is opened by the alignment's
    own validation, which knows the pins -- a fixed max opens the low side
    only. [Revised in batch 48: opened both ways here, whatever the pins.] }
end;

function TyRadarNameText(const AInd: TTyRadarIndicator;
  const ASpec: TTyRadarNameSpec): string;
begin
  Result := AInd.Name;
  if ASpec.HasFormatter then
    Result := TyReplaceFirst(ASpec.Formatter, '{value}', Result);
end;

function TyRadarBucket(const AColours: TTyChartColorArray; AIndex: Integer;
  out AColour: TTyChartColor): Boolean;
var i: Integer;
begin
  AColour := 0;
  { EMPTY IS A REAL OPTION -- `color: []` is legal JSON -- and upstream takes a
    remainder by zero here, gets NaN, indexes a property nothing iterates, and
    draws nothing without a word. Answering False draws nothing too, and
    without raising. }
  if Length(AColours) = 0 then Exit(False);
  i := AIndex mod Length(AColours);
  if i < 0 then i := i + Length(AColours);
  AColour := AColours[i];
  Result := True;
end;

{ ==================== the coordinate system ==================== }

constructor TTyRadar.Create(const ASpec: TTyRadarSpec);
var
  i: Integer;
  sc: TTyIntervalScale;
begin
  inherited Create;
  FSpec := ASpec;
  SetLength(FAxes, Length(ASpec.Indicators));
  SetLength(FAngles, Length(ASpec.Indicators));
  for i := 0 to High(FAxes) do
  begin
    sc := TTyIntervalScale.Create;
    sc.SetExtent(TyRange(0, 1));
    { Horizontal is meaningless on a spoke and is never read: the radar writes
      the pixel extent itself and never asks the axis to reflow against a
      rect. }
    FAxes[i] := TTyAxis.Create(TyRadarDimPrefix + IntToStr(i), sc, True);
    FAxes[i].AxisType := atValue;
    FAngles[i] := 0;
  end;
end;

destructor TTyRadar.Destroy;
var i: Integer;
begin
  for i := 0 to High(FAxes) do FAxes[i].Free;
  FAxes := nil;
  inherited Destroy;
end;

procedure TTyRadar.Resize(const AViewport: TTyRectF; APPI: Integer);
var
  i: Integer;
  base, startRad: Double;
begin
  FValid := False;
  FRect := AViewport;
  if not TyRectFIsValid(AViewport) then Exit;
  { THREE PERCENTAGES, TWO BASES. The centre's run against the width and the
    height separately; BOTH radii run against half the shorter side. }
  TySolveCircle(FSpec.CentreX, FSpec.CentreY, AViewport, FCX, FCY, base);
  FR0 := TyBoxResolve(FSpec.R0V, base);
  FR1 := TyBoxResolve(FSpec.R1V, base);
  if FSpec.R0V.Kind = buPx then FR0 := FR0 * APPI / 96;
  if FSpec.R1V.Kind = buPx then FR1 := FR1 * APPI / 96;
  FPPI := APPI;
  if IsNan(FCX) or IsNan(FCY) or IsNan(FR0) or IsNan(FR1) then Exit;
  if FR1 <= 0 then Exit;
  if Length(FAxes) = 0 then Exit;

  startRad := FSpec.StartDeg * cRadian;
  for i := 0 to High(FAxes) do
  begin
    { NOT NORMALISED INTO ORDER. A radius pair written the other way round is
      legal and mirrors the whole axis; sorting it here would quietly draw a
      different chart from the one the option asked for. }
    FAxes[i].SetPxExtent(FR0, FR1);
    FAngles[i] := TyRadarAngle(startRad, i, Length(FAxes), FSpec.Clockwise);
  end;
  FValid := True;
end;

procedure TTyRadar.SetAxisExtent(AIndex: Integer; ALo, AHi: Double);
begin
  if (AIndex < 0) or (AIndex > High(FAxes)) then Exit;
  FAxes[AIndex].Scale.SetExtent(TyRange(ALo, AHi));
  if Length(FTicks) <> Length(FAxes) then
  begin
    SetLength(FTicks, Length(FAxes));
    SetLength(FCoords, Length(FAxes));
    SetLength(FAligned, Length(FAxes));
  end;
  FTicks[AIndex] := nil;
  FCoords[AIndex] := nil;
  FAligned[AIndex] := False;
end;

procedure TTyRadar.AlignAxis(AIndex: Integer; ALo, AHi: Double;
  AFixLo, AFixHi, AIncl0: Boolean);
var
  ai: TTyAlignInput;
  r: TTyAlignResult;
  n, k: Integer;
  sc: TTyIntervalScale;
  tk: TTyScaleTickArray;
  ppi: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FAxes)) then Exit;
  SetAxisExtent(AIndex, ALo, AHi);
  if not (FAxes[AIndex].Scale is TTyIntervalScale) then Exit;
  sc := TTyIntervalScale(FAxes[AIndex].Scale);
  { THE DUMMY: [0, splitNumber], a step of one, every tick whole. }
  n := FSpec.SplitNumber;
  if n < 1 then n := 1;
  ai := Default(TTyAlignInput);
  SetLength(ai.RefTicks, n + 1);
  for k := 0 to n do ai.RefTicks[k] := k;
  ai.RefExpTicks := ai.RefTicks;
  ai.RefInterval := 1;
  ai.Lo := ALo;
  ai.Hi := AHi;
  ai.FixLo := AFixLo;
  ai.FixHi := AFixHi;
  ai.Incl0 := AIncl0;
  ai.IsLog := False;
  ai.Base := 10;
  { LOGICAL px: the radii are device px, and the precision a both-fixed
    step is rounded to comes from the span upstream measures in CSS px. }
  ppi := FPPI;
  if ppi <= 0 then ppi := 96;
  ai.PxSpan := Abs(FR1 - FR0) * 96 / ppi;
  r := TyScaleCalcAlign(ai);
  sc.SetAligned(r.Lo, r.Hi, r.Interval, r.Precision, r.Seg, r.NiceLo, r.NiceHi);
  FAligned[AIndex] := True;
  tk := sc.GetTicks;
  SetLength(FTicks[AIndex], 0);
  for k := 0 to High(tk) do
    if tk[k].Level = 0 then
    begin
      SetLength(FTicks[AIndex], Length(FTicks[AIndex]) + 1);
      FTicks[AIndex][High(FTicks[AIndex])] := tk[k].Value;
    end;
  SetLength(FCoords[AIndex], Length(FTicks[AIndex]));
  for k := 0 to High(FTicks[AIndex]) do
    FCoords[AIndex][k] := FAxes[AIndex].DataToCoord(FTicks[AIndex][k]);
end;

function TTyRadar.RingCount: Integer;
var i, c: Integer;

  function CountOf(AI: Integer): Integer;
  begin
    { A spoke set bare counts as splitNumber; an aligned one with no ticks
      has none, and minus one rings is none drawn. }
    if FAligned[AI] then Result := Length(FTicks[AI]) - 1
    else Result := FSpec.SplitNumber;
  end;

begin
  Result := FSpec.SplitNumber;
  if Length(FAligned) = 0 then Exit;
  if FSpec.Shape = rsCircle then Exit(CountOf(0));
  Result := MaxInt;
  for i := 0 to High(FAligned) do
  begin
    c := CountOf(i);
    if c < Result then Result := c;
  end;
end;

function TTyRadar.RingRadiusOf(AIndex, AK: Integer): Double;
begin
  if (AIndex >= 0) and (AIndex <= High(FCoords))
    and (AK >= 0) and (AK <= High(FCoords[AIndex])) then
    Exit(FCoords[AIndex][AK]);
  if FSpec.SplitNumber < 1 then Exit(FR1);
  Result := FR0 + (FR1 - FR0) * AK / FSpec.SplitNumber;
end;

function TTyRadar.AxisExtent(AIndex: Integer): TTyRange;
begin
  Result := TyRange(0, 1);
  if (AIndex < 0) or (AIndex > High(FAxes)) then Exit;
  Result := FAxes[AIndex].Scale.GetExtent;
end;

function TTyRadar.AngleOf(AIndex: Integer): Double;
begin
  if (AIndex < 0) or (AIndex > High(FAngles)) then Exit(0);
  Result := FAngles[AIndex];
end;

function TTyRadar.CoordToPoint(ACoord: Double; AIndex: Integer): TTyPointF;
var a: Double;
begin
  if IsNan(ACoord) then Exit(TyPointF(FCX, FCY));
  a := AngleOf(AIndex);
  { THE MINUS ON Y is the whole convention. The angle counts anticlockwise and
    the screen's y counts down, so the sine is subtracted rather than added --
    which is why a radar's startAngle is NOT negated the way a pie's is. }
  Result := TyPointF(FCX + ACoord * Cos(a), FCY - ACoord * Sin(a));
end;

function TTyRadar.ValueToPoint(AValue: Double; AIndex: Integer): TTyPointF;
begin
  if (AIndex < 0) or (AIndex > High(FAxes)) then Exit(TyPointF(FCX, FCY));
  if IsNan(AValue) then Exit(TyPointF(FCX, FCY));
  Result := CoordToPoint(FAxes[AIndex].DataToCoord(AValue), AIndex);
end;

function TTyRadar.RingRadius(AK: Integer): Double;
begin
  { WHERE THE FIRST SPOKE'S TICK LANDS -- a ring is a tick, rounded to the
    step's precision, not a fraction of the radius: 2167 on a 6500 spoke of
    three is 33.338 of 100, not 33.333. [Revised in batch 48: evenly spaced
    by construction.] }
  Result := RingRadiusOf(0, AK);
end;

function TTyRadar.RingValue(AIndex, AK: Integer): Double;
var e: TTyRange;
begin
  if (AIndex >= 0) and (AIndex <= High(FTicks))
    and (AK >= 0) and (AK <= High(FTicks[AIndex])) then
    Exit(FTicks[AIndex][AK]);
  e := AxisExtent(AIndex);
  if FSpec.SplitNumber < 1 then Exit(e.Stop);
  Result := e.Start + (e.Stop - e.Start) * AK / FSpec.SplitNumber;
end;

function TTyRadar.CoordSysName: string;
begin
  Result := TyRadarCoordSysName;
end;

function TTyRadar.DimCount: Integer;
begin
  Result := Length(FAxes);
end;

function TTyRadar.GetRect: TTyRectF;
begin
  Result := TyRectF(FCX - FR1, FCY - FR1, FCX + FR1, FCY + FR1);
end;

function TTyRadar.DataToPoint(const AData: array of Double): TTyPointF;
begin
  { A RADAR'S DATUM IS A WHOLE ROW, one value per spoke, so the one-point
    question only makes sense for one spoke at a time. The two-element form is
    (spoke index, value), which is also what PointToData answers. }
  if Length(AData) < 2 then Exit(TyInvalidPointF);
  Result := ValueToPoint(AData[1], TyTruncOpt(AData[0], -1, -1, 100000));
end;

function TTyRadar.DataToLayout(const AData: array of Double): TTyCoordLayout;
begin
  Result := Default(TTyCoordLayout);
  Result.Rect := GetRect;
  Result.ContentRect := Result.Rect;
end;

function TTyRadar.PointToData(const APoint: TTyPointF;
  out AData: TTyDoubleArray): Boolean;
var
  dx, dy, radius, radian, best, diff: Double;
  i, bestIdx: Integer;
begin
  AData := nil;
  Result := False;
  if not FValid then Exit;
  dx := APoint.X - FCX;
  dy := APoint.Y - FCY;
  radius := Sqrt(dx * dx + dy * dy);
  { THE CENTRE IS THE CASE UPSTREAM DOES NOT GUARD: it divides by the radius,
    gets NaN, compares NaN against every axis, falls out with an index of -1
    and hands that back. Here the division would be by zero and the comparison
    would raise, so the question is answered instead: no spoke is nearest to
    the middle. }
  if radius <= 0 then Exit;
  radian := ArcTan2(-dy / radius, dx / radius);
  best := Infinity;
  bestIdx := -1;
  for i := 0 to High(FAngles) do
  begin
    diff := Abs(radian - FAngles[i]);
    if IsNan(diff) then Continue;
    if diff < best then
    begin
      best := diff;
      bestIdx := i;
    end;
  end;
  if bestIdx < 0 then Exit;
  SetLength(AData, 2);
  AData[0] := bestIdx;
  AData[1] := FAxes[bestIdx].CoordToData(radius);
  Result := True;
end;

function TTyRadar.ContainPoint(const APoint: TTyPointF): Boolean;
var dx, dy: Double;
begin
  Result := False;
  if not FValid then Exit;
  dx := APoint.X - FCX;
  dy := APoint.Y - FCY;
  Result := Sqrt(dx * dx + dy * dy) <= Max(FR0, FR1);
end;

function TTyRadar.AxisCount: Integer;
begin
  Result := Length(FAxes);
end;

function TTyRadar.GetAxis(AIndex: Integer): TTyAxis;
begin
  if (AIndex < 0) or (AIndex > High(FAxes)) then Exit(nil);
  Result := FAxes[AIndex];
end;

{ ==================== the furniture ==================== }

{ The perpendicular to a spoke, in the direction ticks and labels are pushed.

  UPSTREAM'S OWN LOCAL FRAME, worked through: every part of an axis is written
  on the segment from (0,0) to (extent, 0) and then run through a rotation, so
  local +y maps to (sin a, cos a) on screen. Both the tick length and the label
  margin are NEGATIVE in that frame, which is why they end up on the
  anticlockwise side of the spoke. }
function PerpOf(AAngle: Double): TTyPointF;
begin
  Result := TyPointF(Sin(AAngle), Cos(AAngle));
end;

function RingPoints(ARadar: TTyRadar; AK: Integer): TTyPointFArray;
var
  i, n: Integer;
begin
  n := ARadar.AxisCount;
  Result := nil;
  if n = 0 then Exit;
  SetLength(Result, n + 1);
  { EACH SPOKE AT ITS OWN TICK: the ticks are rounded per spoke, so a
    polygon's corners are not all at one radius. }
  for i := 0 to n - 1 do
    Result[i] := ARadar.CoordToPoint(ARadar.RingRadiusOf(i, AK), i);
  { CLOSED EXPLICITLY. The polygon kind closes itself, but the split LINE is a
    polyline and would leave the last edge missing. }
  Result[n] := Result[0];
end;

function TyBuildRadarGrid(ARadar: TTyRadar; const AInk: TTyRadarInk;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AList: TTyPaintList): Integer;
var
  spec: TTyRadarSpec;
  n, k, i, j: Integer;
  c: TTyChartColor;
  el: TTyChartElement;
  outer, inner, band: TTyPointFArray;
  a, r, rOut, rIn, len, margin, w, h: Double;
  p, q, perp: TTyPointF;
  words: string;
  anchorH: TTyTextAnchorH;
  anchorV: TTyTextAnchorV;
  box: TTyRectF;
begin
  Result := 0;
  if (AList = nil) or (ARadar = nil) or not ARadar.Valid then Exit;
  spec := ARadar.Spec;
  n := ARadar.AxisCount;
  if n = 0 then Exit;

  { ---- the bands, innermost first, under everything ---- }
  if spec.SplitArea.Show then
    for k := 0 to ARadar.RingCount - 1 do
    begin
      { BAND k SITS BETWEEN RING k AND RING k+1 and takes colour k. Both
        shapes agree about that, though upstream reaches it by two different
        index expressions -- and one of them starts at minus one and parks its
        first band on an array property nothing ever draws. }
      if not TyRadarBucket(spec.SplitArea.Colours, k, c) then
      begin
        if Odd(k) then c := AInk.SplitAreaB else c := AInk.SplitAreaA;
      end;
      rOut := ARadar.RingRadius(k + 1);
      rIn := ARadar.RingRadius(k);
      if Abs(rOut - rIn) < 1e-9 then Continue;
      if spec.Shape = rsCircle then
      begin
        el := TyChartElement(TyShapeSector(ARadar.CX, ARadar.CY,
          Min(rIn, rOut), Max(rIn, rOut), 0, 2 * Pi));
      end
      else
      begin
        outer := RingPoints(ARadar, k + 1);
        inner := RingPoints(ARadar, k);
        if (Length(outer) < 3) or (Length(inner) < 3) then Continue;
        { ONE CONTOUR, out along the outer ring and back along the inner one
          REVERSED, which is what leaves the hole unfilled under either fill
          rule. Two separate polygons would paint the hole twice. }
        SetLength(band, Length(outer) + Length(inner));
        for i := 0 to High(outer) do band[i] := outer[i];
        for i := 0 to High(inner) do
          band[Length(outer) + i] := inner[High(inner) - i];
        el := TyChartElement(TyShapePolygon(band));
        el.Style.FillEvenOdd := True;
      end;
      el.Style.HasFill := True;
      el.Style.FillColor := c;
      el.Z := AInk.Z;
      el.Z2 := 0;
      el.Silent := True;
      AList.Add(el);
      Inc(Result);
    end;

  { ---- the rings ---- }
  if spec.SplitLine.Show and (spec.SplitLine.WidthLogical > 0) then
    for k := 0 to ARadar.RingCount do
    begin
      if not TyRadarBucket(spec.SplitLine.Colours, k, c) then
        c := AInk.SplitLine;
      r := ARadar.RingRadius(k);
      { A RING OF NO RADIUS IS A DOT, not a ring. Upstream emits it anyway and
        leaves the rasteriser to draw nothing; here a zero-radius circle and a
        polygon of coincident points are two different kinds of trouble. }
      if Abs(r) < 1e-9 then Continue;
      if spec.Shape = rsCircle then
        el := TyChartElement(TyShapeCircle(ARadar.CX, ARadar.CY, r))
      else
      begin
        outer := RingPoints(ARadar, k);
        if Length(outer) < 3 then Continue;
        el := TyChartElement(TyShapePolyline(outer));
      end;
      el.Style.StrokeColor := c;
      el.Style.StrokeWidthLogical := spec.SplitLine.WidthLogical;
      el.Z := AInk.Z;
      el.Z2 := 0;
      el.Silent := True;
      AList.Add(el);
      Inc(Result);
    end;

  { ---- the spokes, and the name at the end of each ---- }
  for i := 0 to n - 1 do
  begin
    a := ARadar.AngleOf(i);
    perp := PerpOf(a);

    if spec.AxisLine.Show and (spec.AxisLine.WidthLogical > 0) then
    begin
      p := ARadar.CoordToPoint(ARadar.R0, i);
      q := ARadar.CoordToPoint(ARadar.R1, i);
      el := TyChartElement(TyShapePolyline([p, q]));
      if not TyRadarBucket(spec.AxisLine.Colours, 0, c) then c := AInk.AxisLine;
      el.Style.StrokeColor := c;
      el.Style.StrokeWidthLogical := spec.AxisLine.WidthLogical;
      el.Z := AInk.Z;
      el.Z2 := 1;
      el.Silent := True;
      AList.Add(el);
      Inc(Result);
    end;

    if spec.AxisName.Show then
    begin
      words := TyRadarNameText(spec.Indicators[i], spec.AxisName);
      if words <> '' then
      begin
        p := ARadar.CoordToPoint(ARadar.R1
          + spec.AxisName.GapLogical * APPI / 96, i);
        { THE ALIGNMENT TABLE, said in the frame it is actually about. Upstream
          writes it against a rotation difference; on a spoke that comes to
          the same three cases -- straight up, straight down, and everything
          else pinned by whichever edge faces the centre. The threshold is
          upstream's own one ten-thousandth of a radian, so a spoke a
          hundredth of a degree off vertical is NOT centred. }
        if Abs(Cos(a)) < 1e-4 then
        begin
          anchorH := tahCentre;
          if Sin(a) > 0 then anchorV := tavBottom else anchorV := tavTop;
        end
        else
        begin
          anchorV := tavMiddle;
          if Cos(a) < 0 then anchorH := tahRight else anchorH := tahLeft;
        end;
        AMeasurer.MeasureLine(words, AInk.NameFontName,
          AInk.NameFontSizeLogical, AInk.NameFontWeight, w, h);
        if (w > 0) and (h > 0) then
        begin
          box := TyAnchorBox(p.X, p.Y, w, h, anchorH, anchorV);
          el := TyChartElement(TyShapeRect(box));
          el.Caption.Text := words;
          el.Caption.FontName := AInk.NameFontName;
          el.Caption.FontSizeLogical := AInk.NameFontSizeLogical;
          el.Caption.FontWeight := AInk.NameFontWeight;
          if spec.Indicators[i].HasColour then
            el.Caption.Colour := spec.Indicators[i].Colour
          else if spec.AxisName.HasColour then
            el.Caption.Colour := spec.AxisName.Colour
          else
            el.Caption.Colour := AInk.NameColour;
          if spec.AxisName.HasFontSize then
            el.Caption.FontSizeLogical := spec.AxisName.FontSizeLogical;
          el.Caption.X := p.X;
          el.Caption.Y := p.Y;
          el.Caption.AnchorH := anchorH;
          el.Caption.AnchorV := anchorV;
          el.Z := AInk.Z;
          el.Z2 := 1;
          el.Silent := True;
          AList.Add(el);
          Inc(Result);
        end;
      end;
    end;

    { ---- the ticks and the scale labels, on EVERY spoke ---- }
    if spec.AxisTick.Show and (spec.AxisTick.LengthLogical > 0) then
    begin
      len := spec.AxisTick.LengthLogical * APPI / 96;
      for k := 0 to ARadar.RingCount do
      begin
        p := ARadar.CoordToPoint(ARadar.RingRadiusOf(i, k), i);
        q := TyPointF(p.X - perp.X * len, p.Y - perp.Y * len);
        el := TyChartElement(TyShapePolyline([p, q]));
        el.Style.StrokeColor := AInk.Tick;
        el.Style.StrokeWidthLogical := 1;
        el.Z := AInk.Z;
        el.Z2 := 2;
        el.Silent := True;
        AList.Add(el);
        Inc(Result);
      end;
    end;

    if spec.AxisLabel.Show then
    begin
      margin := spec.AxisLabel.MarginLogical * APPI / 96;
      { ONE LABEL PER RING ON EVERY SPOKE, which is upstream's own answer and
        not an oversight -- turning a radar's labels on is meant to be loud.
        The alignment is a DIFFERENT table from the name's: it is written about
        the perpendicular rather than about the spoke. }
      if Abs(Sin(a)) < 1e-4 then
      begin
        anchorH := tahCentre;
        if Cos(a) > 0 then anchorV := tavBottom else anchorV := tavTop;
      end
      else
      begin
        anchorV := tavMiddle;
        if Sin(a) > 0 then anchorH := tahRight else anchorH := tahLeft;
      end;
      for k := 0 to ARadar.RingCount do
      begin
        { Interval.getLabel: the tick's own decimals, thousands grouped.
          [Revised in batch 48: printed with no grouping.] }
        words := TyScaleValueLabel(ARadar.GetAxis(i).Scale,
          ARadar.RingValue(i, k), Default(TTyLabelPrecision));
        if words = '' then Continue;
        p := ARadar.CoordToPoint(ARadar.RingRadiusOf(i, k), i);
        p := TyPointF(p.X - perp.X * margin, p.Y - perp.Y * margin);
        AMeasurer.MeasureLine(words, AInk.LabelFontName,
          AInk.LabelFontSizeLogical, AInk.LabelFontWeight, w, h);
        if (w <= 0) or (h <= 0) then Continue;
        box := TyAnchorBox(p.X, p.Y, w, h, anchorH, anchorV);
        el := TyChartElement(TyShapeRect(box));
        el.Caption.Text := words;
        el.Caption.FontName := AInk.LabelFontName;
        el.Caption.FontSizeLogical := AInk.LabelFontSizeLogical;
        el.Caption.FontWeight := AInk.LabelFontWeight;
        if spec.AxisLabel.HasColour then
          el.Caption.Colour := spec.AxisLabel.Colour
        else
          el.Caption.Colour := AInk.LabelColour;
        if spec.AxisLabel.HasFontSize then
          el.Caption.FontSizeLogical := spec.AxisLabel.FontSizeLogical;
        el.Caption.X := p.X;
        el.Caption.Y := p.Y;
        el.Caption.AnchorH := anchorH;
        el.Caption.AnchorV := anchorV;
        el.Z := AInk.Z;
        el.Z2 := 10;
        el.Silent := True;
        AList.Add(el);
        Inc(Result);
      end;
    end;
  end;
  j := 0;
  if j <> 0 then Exit;
end;

{ ==================== the series ==================== }

function TyBuildRadarMarks(const ABinding: TTySeriesBinding; ARadar: TTyRadar;
  const AVisual: TTyRadarVisual; AStore: TTyDataStore;
  const ADims: TTyIntegerArray; APPI: Integer; AList: TTyPaintList): Integer;
var
  k, i, n, rows, raw, m: Integer;
  pts, ring: TTyPointFArray;
  rowColour: TTyChartColor;
  v: Double;
  el: TTyChartElement;
  sym: TTyChartShape;
begin
  Result := 0;
  if (AList = nil) or (AStore = nil) or (ARadar = nil) then Exit;
  if not ARadar.Valid then Exit;
  if not ABinding.Resolved then Exit;
  n := ARadar.AxisCount;
  if n = 0 then Exit;
  rows := AStore.Count;

  for k := 0 to rows - 1 do
  begin
    raw := AStore.GetRawIndex(k);
    if (raw >= 0) and (raw <= High(AVisual.Fills)) then
      rowColour := AVisual.Fills[raw]
    else
      rowColour := AVisual.Fill;
    SetLength(pts, n);
    m := 0;
    for i := 0 to n - 1 do
    begin
      { A SPOKE THE STORE IS TOO NARROW FOR. The store is exactly as wide as
        the FIRST data row, while the spokes come from the radar component, so
        five indicators and a row of three is ordinary. Upstream indexes a
        dimension that is not there and reads column minus one; here the spoke
        is simply missing. }
      if (i > High(ADims)) or (ADims[i] < 0) or (ADims[i] >= AStore.DimCount) then
        Continue;
      v := AStore.Get(ADims[i], k);
      { A MISSING VALUE LEAVES THE RING RATHER THAN COLLAPSING IT. Upstream
        pushes a NaN point and the canvas silently skips it, joining the two
        neighbours; the same picture, reached deliberately. }
      if IsNan(v) then Continue;
      pts[m] := ARadar.ValueToPoint(v, i);
      if IsNan(pts[m].X) or IsNan(pts[m].Y) then Continue;
      Inc(m);
    end;
    if m < 2 then Continue;
    SetLength(ring, m + 1);
    for i := 0 to m - 1 do ring[i] := pts[i];
    ring[m] := pts[0];

    { THE AREA FIRST, so the ring is drawn over its own fill. Equal z and z2,
      so the order in the list is the order on the screen. }
    if AVisual.HasArea then
    begin
      el := TyChartElement(TyShapePolygon(Copy(ring, 0, m)));
      el.Style.HasFill := True;
      if AVisual.AreaAuthored then
        el.Style.FillColor := AVisual.Area
      else
        el.Style.FillColor := rowColour;
      el.Style.Alpha := AVisual.AreaOpacity;
      el.Z := AVisual.Z;
      el.Z2 := AVisual.Z2;
      el.Silent := False;
      el.Datum := TyChartDatum(ABinding.SeriesIndex, k, raw);
      AList.Add(el);
      Inc(Result);
    end;

    el := TyChartElement(TyShapePolyline(ring));
    el.Style.StrokeColor := rowColour;
    el.Style.StrokeWidthLogical := AVisual.LineWidthLogical;
    el.Z := AVisual.Z;
    el.Z2 := AVisual.Z2;
    el.Silent := False;
    { A RING IS ONE ELEMENT FOR A WHOLE ROW, so it answers with the row and no
      spoke -- the same shape a line series' run has. }
    el.Datum := TyChartDatum(ABinding.SeriesIndex, k, raw);
    el.HitSlopLogical := AVisual.LineWidthLogical / 2 + 4;
    AList.Add(el);
    Inc(Result);

    if AVisual.Symbol.Kind <> tsyNone then
      for i := 0 to m - 1 do
      begin
        sym := TyBuildSymbol(AVisual.Symbol, pts[i].X, pts[i].Y);
        if not TyRectFIsValid(TyShapeBounds(sym)) then Continue;
        el := TyChartElement(sym);
        el.Style.HasFill := True;
        if AVisual.Symbol.Empty or (AVisual.Symbol.Kind = tsyLine) then
        begin
          el.Style.StrokeColor := rowColour;
          el.Style.StrokeWidthLogical := 2;
          if AVisual.Symbol.Kind = tsyLine then
            el.Style.FillColor := 0
          else
            el.Style.FillColor := AVisual.EmptyFill;
        end
        else
          el.Style.FillColor := rowColour;
        el.Z := AVisual.Z;
        el.Z2 := AVisual.Z2 + 1;
        el.Silent := False;
        el.Datum := TyChartDatum(ABinding.SeriesIndex, k, raw);
        el.HitSlopLogical := 4;
        AList.Add(el);
        Inc(Result);
      end;
  end;
end;

end.
