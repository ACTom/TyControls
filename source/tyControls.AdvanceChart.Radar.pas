unit tyControls.AdvanceChart.Radar;
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

  PURE: SysUtils, Math, fpjson and the AdvanceChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option,
  tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Layout,
  tyControls.AdvanceChart.Coord, tyControls.AdvanceChart.Scale,
  tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
  tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Series,
  tyControls.AdvanceChart.Symbol, tyControls.AdvanceChart.Labels,
  tyControls.AdvanceChart.LabelOpt, tyControls.AdvanceChart.Handlers;

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
    { [R5-A] fontStyle as written (TyFontStyleCode) }
    FontStyle: Byte;
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
    { [R5-B] the rest of the lineStyle: `type` (a word against the width,
      or lengths), `dashOffset`, `opacity` -- 1 when not written }
    Dash: TTyOptDash;
    DashLogical: TTyDoubleArray;
    DashOffset: Double;
    Opacity: Double;
    { [R5-A] its lineStyle's shadow (getLineStyle) }
    Shadow: TTyChartShadow;
    { [R5-G] getLineStyle's cap, join and miterLimit (cTyCap* / cTyJoin*,
      MiterLimit 0 the canvas' 10); the axis line's cap is AxisBuilder's
      `lineCap: 'round'` under the author's }
    Cap, Join: Byte;
    MiterLimit: Double;
  end;

  TTyRadarAreaSpec = record
    Show: Boolean;
    Colours: TTyChartColorArray;
    { [R5-J] index-parallel to Colours: an entry written as a gradient (its
      Colours entry the first stop), cgkNone for a colour; empty when none
      is one }
    Grads: TTyChartGradientArray;
    { [R5-B] areaStyle.opacity, 1 when not written }
    Opacity: Double;
    { [R5-A] its areaStyle's shadow (getAreaStyle) }
    Shadow: TTyChartShadow;
  end;

  { [R5-B] THE TICKS' PEN as AxisBuilder strokes them: axisTick.lineStyle,
    its colour else the axis line's (the radar's axisLine, which every
    indicator's axis model is handed), its width 1 unless written }
  TTyRadarTickSpec = record
    Show: Boolean;
    LengthLogical: Double;
    HasColour: Boolean;
    Colour: TTyChartColor;
    WidthLogical: Double;
    Dash: TTyOptDash;
    DashLogical: TTyDoubleArray;
    DashOffset: Double;
    Opacity: Double;
    { [R5-G] cap, join, miterLimit of axisTick.lineStyle (no default) }
    Cap, Join: Byte;
    MiterLimit: Double;
  end;

  TTyRadarLabelSpec = record
    Show: Boolean;
    MarginLogical: Double;
    { [R5-G] AxisBuilder's end rules and hideOverlap on every spoke:
      showMinLabel / showMaxLabel (null: auto), hideOverlap, and the
      textMargin a hideOverlap box is padded by ([0, 3] by default: the
      value axis' own, which every indicator axis is merged over) }
    ShowMin, ShowMax: TTyAxisEndLabel;
    HideOverlap: Boolean;
    TextMarginV, TextMarginH: Double;
    HasColour: Boolean;
    Colour: TTyChartColor;
    HasFontSize: Boolean;
    FontSizeLogical: Integer;
    { [R5-A] fontStyle as written (TyFontStyleCode) }
    FontStyle: Byte;
    { [R7-I] axisLabel.formatter (makeLabelFormatter on the indicator's
      value axis): a template's first '{value}' is the rawLabel, a handler
      ('@name') is handed the tick's value and its index }
    HasFormatter: Boolean;
    Formatter: string;
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
    { [Batch 154] Radar.resize in createBoxLayoutReference's container,
      given as x / y / width / height: a matrix cell or a calendar day (a
      cell's fractional edges make right-less-left differ from its width) }
    procedure ResizeXYWH(const ARef: TTyXYWH; APPI: Integer);
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
    { [R7-F] the series' lineStyle.width is +Infinity: the ring strokes
      nothing (the canvas takes no such width) and its stroked rect is
      not-a-number upstream -- it is never hit }
    LineInf: Boolean;
    { [R2-B] lineStyle.type (getLineStyle's lineDash, drawn as zrender's
      normalizeLineDash against the width), the series' and -- RowLineSet --
      an item's own lineStyle width and type over it }
    LineDash: TTyOptDash;
    LineDashExplicit: TTyDoubleArray;
    RowLineSet: array of Boolean;
    RowLineWidth: TTyDoubleArray;
    { [R7-Y] an item's own lineStyle.width is +Infinity (the item's over the
      series' LineInf, where it writes one) }
    RowLineInf: array of Boolean;
    RowLineDash: array of TTyOptDash;
    RowLineDashExplicit: array of TTyDoubleArray;
    { [R2-I2] lineStyle.dashOffset: the series', an item's own over it }
    LineDashOffset: Double;
    RowLineDashOffsetSet: array of Boolean;
    RowLineDashOffset: TTyDoubleArray;
    { areaStyle. Absent means no filled polygon at all, which is upstream's
      rule and not a style detail: a radar with no areaStyle is a wire. }
    HasArea: Boolean;
    { True only when the author named a colour for it -- otherwise the area
      follows the ROW, which is the whole point of colouring by datum. }
    AreaAuthored: Boolean;
    { [R7-F] the series' areaStyle.color is 'none': no fill, no inside for
      the pointer (an item's own colour over it is a fill) }
    AreaNone: Boolean;
    Area: TTyChartColor;
    AreaOpacity: Double;
    { A STATE WRITES AN areaStyle [F2b]: `emphasis`, `select` or `blur` --
      upstream's polygon is always there, ignored at rest without an
      areaStyle and shown in a state that has one (RadarView.ts:212-218);
      it is built, ignored, for the states to show }
    StateArea: Boolean;
    Symbol: TTySymbolSpec;
    { per raw row: a visualMap's symbolSize, NaN where none }
    Sizes: TTyDoubleArray;
    EmptyFill: TTyChartColor;
    Z: Integer;
    Z2: Integer;
    { per RAW row, the item's decal: the area polygon takes it through
      defaults(areaStyle, {decal}) and every point -- createSymbol's, which
      keeps it -- through the item's style [F4a] }
    Decals: TTyChartDecalArray;
    { AN ITEM'S OWN areaStyle, per RAW row [F4a]: RadarView reads the area
      through the item's model, whose parent is the series' -- an item that
      writes one shows its polygon though the series writes none, and its
      colour and opacity sit over the series' }
    RowArea: TTyBoolArray;
    RowAreaColourSet: TTyBoolArray;
    RowAreaColour: TTyChartColorArray;
    RowAreaOpacitySet: TTyBoolArray;
    RowAreaOpacity: TTyDoubleArray;
    { [R2-A] THE POINTS' LABELS: the series' `label` (position 'top' unless
      written, RadarSeries' default) and, per RAW row, an item's own over it;
      the series' name for `{a}`. A zero Label_ shows nothing. }
    Label_: TTyLabelSpec;
    ItemLabels: TTyLabelSpecArray;
    HasItemLabel: TTyBoolArray;
    SeriesName: string;
    { [R2-A] AN ITEM'S OWN symbol, symbolSize, symbolRotate over the
      series', per RAW row (data.getItemVisual) }
    RowSyms: TTySymbolSpecArray;
    RowSymSet: TTyBoolArray;
    { [R5-G] THE RING'S lineStyle.color (getLineStyle's stroke over the
      defaults' `stroke: color`): the series' (LineColour) and, per RAW row,
      an item's own over it; a gradient strokes as one. LineNone / RowLineNone:
      'none', no pen. Unset: the row's colour. [was: the series' moved the
      row-less fallback Fill, an item's not read] }
    LineColourSet, LineNone: Boolean;
    LineColour: TTyChartColor;
    LineGrad: TTyChartGradient;
    RowLineColourSet, RowLineNone: TTyBoolArray;
    RowLineColour: TTyChartColorArray;
    RowLineGrad: array of TTyChartGradient;
    { [R6-D] THE SYMBOLS' PEN, the item's visual style (RadarView:
      symbolPath.useStyle(itemStyle)): getItemStyle's borderColor and
      borderWidth, the series' and, per RAW row, an item's own over it key by
      key (dataStyleTask extends it). The series' 'auto' is its palette colour
      (BorderAuto, seriesStyleTask); an item's is a word the canvas does not
      take. A width is NaN where none is written (zrender's 1). }
    Border: TTyOptColor;
    BorderAuto: TTyChartColor;
    BorderWidthLogical: Double;
    RowBorder: array of TTyOptColor;
    RowBorderWidth: TTyDoubleArray;
    { [R7-Y] the border's width is +Infinity, the series' and an item's own
      over it: stroked at the lineWidth the canvas had, never hit }
    BorderWidthInf: Boolean;
    RowBorderWidthInf: array of Boolean;
    { [R7-L] THE SYMBOLS' OPACITY, the item's visual style's: the series'
      itemStyle.opacity and, per RAW row, an item's own over it; NaN where
      none is written (1). Their labels take it (defaultOpacity). }
    Opacity: Double;
    RowOpacity: TTyDoubleArray;
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

type
  { [R7-I] AN INDICATOR'S TEXT the grid drew (an AxisBuilder's name or
    label upstream): the list element, its spoke, its ring (a label's index
    among the axis' labels; -1 a name), and a label's rawLabel
    (scale.getLabel of its tick: what its eventData's value and a tooltip's
    {c} are, the formatter's output being the drawn text) }
  TTyRadarText = record
    Element, Spoke, Ring: Integer;
    IsName: Boolean;
    Raw: string;
  end;
  TTyRadarTextArray = array of TTyRadarText;

{ ... and the texts it drew, in the order it drew them }
function TyBuildRadarGridTexts(ARadar: TTyRadar; const AInk: TTyRadarInk;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AList: TTyPaintList; out ATexts: TTyRadarTextArray): Integer;

{ One series: the ring, the area under it and a symbol per spoke. }
function TyBuildRadarMarks(const ABinding: TTySeriesBinding; ARadar: TTyRadar;
  const AVisual: TTyRadarVisual; AStore: TTyDataStore;
  const ADims: TTyIntegerArray; APPI: Integer; AList: TTyPaintList): Integer;

implementation

uses tyControls.FontUnits, tyControls.AdvanceChart.LabelGuide, tyControls.AdvanceChart.JsMath,
  tyControls.AdvanceChart.States, tyControls.AdvanceChart.AxisLabels,
  tyControls.AdvanceChart.Builder;

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

{ [R5-J] THE SPLIT AREA'S COLOURS with their gradients: ColoursIn's
  entries, and a gradient object (in the list or alone) as one more, its
  first stop the colour; AGrads index-parallel, nil when no entry is one }
function AreaColoursIn(ANode: TJSONObject; const AKey: string;
  const ADefault: TTyChartColorArray; out AGrads: TTyChartGradientArray): TTyChartColorArray;
var
  d: TJSONData;
  a: TJSONArray;
  i, n: Integer;
  c: TTyChartColor;
  g: TTyChartGradient;
  any: Boolean;
begin
  AGrads := nil;
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
  { one gradient, not in a list: [color] upstream }
  if (d is TJSONObject) and TyTryReadGradient(d, g) then
  begin
    SetLength(Result, 1);
    Result[0] := TyGradientSolid(g);
    SetLength(AGrads, 1);
    AGrads[0] := g;
    Exit;
  end;
  if d.JSONType <> jtArray then Exit;
  a := TJSONArray(d);
  SetLength(Result, a.Count);
  SetLength(AGrads, a.Count);
  n := 0;
  any := False;
  for i := 0 to a.Count - 1 do
    if (a.Items[i].JSONType = jtString)
      and TyTryParseChartColor(a.Items[i].AsString, c) then
    begin
      Result[n] := c;
      AGrads[n] := Default(TTyChartGradient);
      Inc(n);
    end
    else if TyTryReadGradient(a.Items[i], g) then
    begin
      Result[n] := TyGradientSolid(g);
      AGrads[n] := g;
      any := True;
      Inc(n);
    end;
  SetLength(Result, n);
  if any then SetLength(AGrads, n) else AGrads := nil;
end;

{ [R5-G] getLineStyle's lineCap / lineJoin / miterLimit off a lineStyle
  object: a word the canvas knows, a positive number }
procedure ReadPenEnds(ALs: TJSONObject; var ACap, AJoin: Byte;
  var AMiter: Double);
var d: TJSONData;
begin
  if ALs = nil then Exit;
  d := ALs.Find('cap');
  if (d <> nil) and (d.JSONType = jtString) then ACap := TyCapOfWord(d.AsString);
  d := ALs.Find('join');
  if (d <> nil) and (d.JSONType = jtString) then AJoin := TyJoinOfWord(d.AsString);
  d := ALs.Find('miterLimit');
  if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat > 0) then
    AMiter := d.AsFloat;
end;

procedure ReadLine(ANode: TJSONObject; const AKey: string;
  var ALine: TTyRadarLineSpec);
var
  n, ls: TJSONObject;
  st: TTyOptStyle;
begin
  n := ObjIn(ANode, AKey);
  if n = nil then Exit;
  ALine.Show := BoolIn(n, 'show', ALine.Show);
  ls := ObjIn(n, 'lineStyle');
  if ls = nil then Exit;
  ALine.WidthLogical := NumIn(ls, 'width', ALine.WidthLogical);
  ALine.Colours := ColoursIn(ls, 'color', ALine.Colours);
  { the rest of getLineStyle [R5-B] }
  st := TyReadOptLineStyleOf(ls);
  if st.Dash <> todNone then
  begin
    ALine.Dash := st.Dash;
    ALine.DashLogical := Copy(st.DashLogical, 0, Length(st.DashLogical));
  end;
  if st.DashOffsetHas then ALine.DashOffset := st.DashOffset;
  if not IsNan(st.Opacity) then ALine.Opacity := st.Opacity;
  TyStReadShadow([ls], [], [], ALine.Shadow);
  ReadPenEnds(ls, ALine.Cap, ALine.Join, ALine.MiterLimit);
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
  Result.AxisLine.Opacity := 1;
  { [R5-G] AxisBuilder's axis line: extend({lineCap: 'round'}, lineStyle) }
  Result.AxisLine.Cap := cTyCapRound;

  { OFF BY DEFAULT, both of them -- upstream flips the value axis' own defaults
    for a radar, so a plain radar shows its rings and its names and nothing
    else. }
  Result.AxisTick.Show := False;
  Result.AxisTick.LengthLogical := 5;
  Result.AxisTick.WidthLogical := 1;
  Result.AxisTick.Opacity := 1;
  Result.AxisLabel.Show := False;
  Result.AxisLabel.MarginLogical := 8;
  { [R5-G] axisDefault's textMargin [0, 3] }
  Result.AxisLabel.TextMarginV := 0;
  Result.AxisLabel.TextMarginH := 3;

  Result.SplitLine.Show := True;
  Result.SplitLine.WidthLogical := 1;
  Result.SplitLine.Opacity := 1;
  { AND SPLIT AREA IS ON, which is the other flip: a cartesian value axis
    defaults it off. }
  Result.SplitArea.Show := True;
  Result.SplitArea.Opacity := 1;
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
  Result.BorderWidthLogical := NaN;
  Result.Opacity := NaN;
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
  st: TTyOptStyle;
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
      Result.AxisName.FontSizeLogical := TyFontSizeFromPx(v);  // CSS px [Batch 83]
    end;
    Result.AxisName.FontStyle := TyFontStyleCode(n2.Find('fontStyle'));
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
    { the ticks' own lineStyle [R5-B] }
    st := TyReadOptLineStyleOf(ObjIn(n2, 'lineStyle'));
    if st.Color.Written and not st.Color.IsAuto and not st.Color.IsNone then
    begin
      Result.AxisTick.HasColour := True;
      Result.AxisTick.Colour := st.Color.Color;
    end;
    if not IsNan(st.BorderWidthLogical) then
      Result.AxisTick.WidthLogical := st.BorderWidthLogical;
    Result.AxisTick.Dash := st.Dash;
    Result.AxisTick.DashLogical := Copy(st.DashLogical, 0, Length(st.DashLogical));
    if st.DashOffsetHas then Result.AxisTick.DashOffset := st.DashOffset;
    if not IsNan(st.Opacity) then Result.AxisTick.Opacity := st.Opacity;
    ReadPenEnds(ObjIn(n2, 'lineStyle'), Result.AxisTick.Cap, Result.AxisTick.Join,
      Result.AxisTick.MiterLimit);
  end;
  { ELSE THE LINE'S COLOUR: defaults(tickStyle, {stroke: axisLine's}) }
  if not Result.AxisTick.HasColour and (Length(Result.AxisLine.Colours) > 0) then
  begin
    Result.AxisTick.HasColour := True;
    Result.AxisTick.Colour := Result.AxisLine.Colours[0];
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
      Result.AxisLabel.FontSizeLogical := TyFontSizeFromPx(v);
    end;
    Result.AxisLabel.FontStyle := TyFontStyleCode(n2.Find('fontStyle'));
    { [R7-I] its formatter [was: not read -- the labels were the rawLabel] }
    Result.AxisLabel.Formatter := StrIn(n2, 'formatter', '');
    Result.AxisLabel.HasFormatter := Result.AxisLabel.Formatter <> '';
    { [R5-G] the end rules' switches }
    d := n2.Find('showMinLabel');
    if (d <> nil) and (d.JSONType = jtBoolean) then
      if d.AsBoolean then Result.AxisLabel.ShowMin := aelShow else Result.AxisLabel.ShowMin := aelHide;
    d := n2.Find('showMaxLabel');
    if (d <> nil) and (d.JSONType = jtBoolean) then
      if d.AsBoolean then Result.AxisLabel.ShowMax := aelShow else Result.AxisLabel.ShowMax := aelHide;
    d := n2.Find('hideOverlap');
    Result.AxisLabel.HideOverlap := (d <> nil) and (((d.JSONType = jtBoolean) and d.AsBoolean)
      or ((d.JSONType = jtNumber) and (d.AsFloat <> 0)) or ((d.JSONType = jtString) and (d.AsString <> '')));
    d := n2.Find('textMargin');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      Result.AxisLabel.TextMarginV := d.AsFloat;
      Result.AxisLabel.TextMarginH := d.AsFloat;
    end
    else if (d is TJSONArray) and (TJSONArray(d).Count >= 2)
      and (TJSONArray(d).Items[0].JSONType = jtNumber)
      and (TJSONArray(d).Items[1].JSONType = jtNumber) then
    begin
      Result.AxisLabel.TextMarginV := TJSONArray(d).Items[0].AsFloat;
      Result.AxisLabel.TextMarginH := TJSONArray(d).Items[1].AsFloat;
    end;
  end;

  n2 := ObjIn(node, 'splitArea');
  if n2 <> nil then
  begin
    Result.SplitArea.Show := BoolIn(n2, 'show', Result.SplitArea.Show);
    ts := ObjIn(n2, 'areaStyle');
    if ts <> nil then
    begin
      { [R5-J] its gradients too [was: an entry written as a gradient was
        dropped from the list] }
      Result.SplitArea.Colours := AreaColoursIn(ts, 'color',
        Result.SplitArea.Colours, Result.SplitArea.Grads);
      { areaStyle.opacity [R5-B] }
      Result.SplitArea.Opacity := NumIn(ts, 'opacity', Result.SplitArea.Opacity);
      { [R5-A] its shadow (getAreaStyle) }
      TyStReadShadow([ts], [], [], Result.SplitArea.Shadow);
    end;
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
  { [F3c] JavaScript's Math.sin / cos / atan2 (V8's), bit for bit }
  Result := TyJsAtan2(TyJsSin(a), TyJsCos(a));
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
var prm: TTyChartCallbackParams;
begin
  Result := AInd.Name;
  { a named handler is given the name and the indicator's max, upstream's
    formatter(name, indicator) }
  if ASpec.HasFormatter and TyChartIsHandlerRef(ASpec.Formatter) then
  begin
    prm := TyChartBlankParams;
    prm.ComponentType := 'radar';
    prm.Name := AInd.Name;
    { an unwritten max is undefined upstream, and says so -- unless a
      negative min made RadarModel write it as 0 }
    if not AInd.HasMax and AInd.HasMin and (AInd.Min_ < 0) then
    begin
      SetLength(prm.Values, 1);
      prm.Values[0] := 0;
      prm.ValueText := '0';
    end
    else if AInd.HasMax then
    begin
      SetLength(prm.Values, 1);
      prm.Values[0] := AInd.Max_;
      prm.ValueText := TyChartValueText(AInd.Max_);
    end
    else
      prm.ValueText := 'undefined';
    Exit(TyChartRunHandler(ASpec.Formatter, TyChartOneParams(prm)));
  end;
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
begin
  FValid := False;
  FRect := AViewport;
  if not TyRectFIsValid(AViewport) then Exit;
  ResizeXYWH(TyXYWHOfRect(AViewport), APPI);
  FRect := AViewport;
end;

procedure TTyRadar.ResizeXYWH(const ARef: TTyXYWH; APPI: Integer);
var
  i: Integer;
  base, startRad: Double;
begin
  FValid := False;
  FRect := TyRectOfXYWH(ARef);
  { THREE PERCENTAGES, TWO BASES. The centre's run against the width and the
    height separately; BOTH radii run against half the shorter side --
    parsePercent(center[0], width) + x, as upstream adds them. A cell of no
    position or no size: not-a-number, nothing drawn. }
  FCX := TyBoxResolve(FSpec.CentreX, ARef.W) + ARef.X;
  FCY := TyBoxResolve(FSpec.CentreY, ARef.H) + ARef.Y;
  if IsNan(ARef.W) or IsNan(ARef.H) then base := NaN
  else base := Min(ARef.W, ARef.H) / 2;
  FR0 := TyBoxResolve(FSpec.R0V, base);
  FR1 := TyBoxResolve(FSpec.R1V, base);
  if FSpec.R0V.Kind = buPx then FR0 := FR0 * APPI / 96;
  if FSpec.R1V.Kind = buPx then FR1 := FR1 * APPI / 96;
  FPPI := APPI;
  if IsNan(FCX) or IsNan(FCY) or IsNan(FR0) or IsNan(FR1) then Exit;
  if FR1 <= 0 then Exit;
  if Length(FAxes) = 0 then Exit;

  { [F3c] radarModel.get('startAngle') * Math.PI / 180, in its order }
  startRad := FSpec.StartDeg * Pi / 180;
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
  { [F3c] Math.cos / sin: V8's }
  Result := TyPointF(FCX + ACoord * TyJsCos(a), FCY - ACoord * TyJsSin(a));
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
var texts: TTyRadarTextArray;
begin
  Result := TyBuildRadarGridTexts(ARadar, AInk, AMeasurer, APPI, AList, texts);
end;

function TyBuildRadarGridTexts(ARadar: TTyRadar; const AInk: TTyRadarInk;
  const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AList: TTyPaintList; out ATexts: TTyRadarTextArray): Integer;
var
  spec: TTyRadarSpec;
  n, k, i, j: Integer;
  c: TTyChartColor;
  el: TTyChartElement;
  outer, inner, band: TTyPointFArray;
  a, r, rOut, rIn, len, margin, w, h: Double;
  p, q, perp: TTyPointF;
  words, raw: string;
  anchorH: TTyTextAnchorH;
  anchorV: TTyTextAnchorV;
  box: TTyRectF;
  hidden: TTyBoolArray;
  { [R5-J] the gradient bands: their list index, colour bucket and box }
  bandEl, bandBucket: TTyIntegerArray;
  bandBox: array of TTyRectF;
  gi, nb: Integer;
  { [R5-J] a polygon radar's bands merged by colour: the contours, the
    points, the box, the colour }
  mergeCmds: array of TTyPathCmdArray;
  mergePts: array of TTyPointFArray;
  mergeBox: array of TTyRectF;
  mergeHas: TTyBoolArray;
  mergeColour: TTyChartColorArray;
  u: TTyRectF;
  pe: PTyChartElement;

  { [R5-G] the size a scale label is drawn at -- and so measured at: the
    author's fontSize, else the skin's [was: measured at the skin's whatever
    the author wrote] }
  function LabelSize: Integer;
  begin
    if spec.AxisLabel.HasFontSize then Result := spec.AxisLabel.FontSizeLogical
    else Result := AInk.LabelFontSizeLogical;
  end;

  { [R7-I] ring AQ's label on spoke AI as drawn: makeLabelFormatter over the
    rawLabel ARaw (Interval.getLabel: the tick's own decimals, grouped) --
    a template's first '{value}' replaced, a handler run with the value and
    the index; the rawLabel itself without one }
  function LabelWords(AI, AQ: Integer; const ARaw: string): string;
  begin
    if not spec.AxisLabel.HasFormatter then Exit(ARaw);
    if TyChartIsHandlerRef(spec.AxisLabel.Formatter) then
      Exit(TyAxisTickLabelAt(ARadar.GetAxis(AI), ARadar.RingValue(AI, AQ), AQ,
        True, spec.AxisLabel.Formatter));
    Result := TyReplaceFirst(spec.AxisLabel.Formatter, '{value}', ARaw);
  end;

  procedure AddText(ASpoke, ARing: Integer; AIsName: Boolean; const ARaw: string);
  begin
    SetLength(ATexts, Length(ATexts) + 1);
    ATexts[High(ATexts)].Element := AList.Count - 1;
    ATexts[High(ATexts)].Spoke := ASpoke;
    ATexts[High(ATexts)].Ring := ARing;
    ATexts[High(ATexts)].IsName := AIsName;
    ATexts[High(ATexts)].Raw := ARaw;
  end;

  { [R5-G] the labels of spoke AI at angle AA as AxisBuilder weighs them:
    each ring's words, measured and anchored as they are drawn below, a
    box each (upright: the label is not turned with the spoke), then the
    end rules and hideOverlap. AHidden[k]: ring k's label (and tick) is
    not drawn }
  procedure RadarLabelsShown(AI: Integer; AA: Double; const APerp: TTyPointF;
    var AHidden: TTyBoolArray);
  var
    cands: TTyLabelCandidateArray;
    rings: TTyIntegerArray;
    q, m: Integer;
    lw, lh, mg, x0, y0, padH, padV: Double;
    lp: TTyPointF;
    ah: TTyTextAnchorH;
    av: TTyTextAnchorV;
    txt: string;
  begin
    mg := spec.AxisLabel.MarginLogical * APPI / 96;
    if Abs(Sin(AA)) < 1e-4 then
    begin
      ah := tahCentre;
      if Cos(AA) > 0 then av := tavBottom else av := tavTop;
    end
    else
    begin
      av := tavMiddle;
      if Sin(AA) > 0 then ah := tahRight else ah := tahLeft;
    end;
    cands := nil;
    rings := nil;
    SetLength(cands, ARadar.RingCount + 1);
    SetLength(rings, ARadar.RingCount + 1);
    m := 0;
    for q := 0 to ARadar.RingCount do
    begin
      txt := TyScaleValueLabel(ARadar.GetAxis(AI).Scale, ARadar.RingValue(AI, q),
        Default(TTyLabelPrecision));
      if txt = '' then Continue;
      txt := LabelWords(AI, q, txt);
      if txt = '' then Continue;
      lp := ARadar.CoordToPoint(ARadar.RingRadiusOf(AI, q), AI);
      lp := TyPointF(lp.X - APerp.X * mg, lp.Y - APerp.Y * mg);
      AMeasurer.MeasureLine(txt, AInk.LabelFontName, LabelSize,
        TyFontStyleCodeOver(spec.AxisLabel.FontStyle, AInk.LabelFontWeight), lw, lh);
      cands[m] := Default(TTyLabelCandidate);
      cands[m].Index := q;
      cands[m].Priority := 10;
      x0 := 0;
      case ah of
        tahRight: x0 := -lw;
        tahCentre: x0 := -lw / 2;
      end;
      y0 := 0;
      case av of
        tavBottom: y0 := -lh;
        tavMiddle: y0 := -lh / 2;
      end;
      cands[m].Bare.LocalRect := TyXYWH(x0, y0, lw, lh);
      padV := spec.AxisLabel.TextMarginV * APPI / 96;
      padH := spec.AxisLabel.TextMarginH * APPI / 96;
      cands[m].Margin.LocalRect := TyRectExpand(cands[m].Bare.LocalRect, padV, padH, padV, padH);
      cands[m].Bare.M := TyMatLocal(lp.X, lp.Y, 0);
      cands[m].Margin.M := cands[m].Bare.M;
      cands[m].Bare.Rect := TyRectApplyMat(cands[m].Bare.LocalRect, cands[m].Bare.M);
      cands[m].Margin.Rect := TyRectApplyMat(cands[m].Margin.LocalRect, cands[m].Margin.M);
      cands[m].Bare.AxisAligned := True;
      cands[m].Margin.AxisAligned := True;
      cands[m].HasBox := (lw > 0) and (lh > 0);
      rings[m] := q;
      Inc(m);
    end;
    SetLength(cands, m);
    TyFixMinMaxLabelShow(cands, lakValue, False, spec.AxisLabel.ShowMin,
      spec.AxisLabel.ShowMax, spec.AxisLabel.HideOverlap, False);
    if spec.AxisLabel.HideOverlap then TyHideOverlap(cands);
    for q := 0 to m - 1 do
      if cands[q].Ignore then AHidden[rings[q]] := True;
  end;

  { the rest of a line's lineStyle on its element: the dash against its
    width, the phase, the opacity [R5-B] }
  procedure LinePen(var AEl: TTyChartElement; const ALine: TTyRadarLineSpec);
  begin
    AEl.Style.DashLogical := TyDashPattern(ALine.Dash, ALine.DashLogical,
      ALine.WidthLogical);
    AEl.Style.DashOffsetLogical := ALine.DashOffset;
    AEl.Style.Alpha := ALine.Opacity;
    AEl.Style.LineCap := ALine.Cap;
    AEl.Style.LineJoin := ALine.Join;
    AEl.Style.MiterLimit := ALine.MiterLimit;
  end;

begin
  Result := 0;
  ATexts := nil;
  if (AList = nil) or (ARadar = nil) or not ARadar.Valid then Exit;
  spec := ARadar.Spec;
  n := ARadar.AxisCount;
  if n = 0 then Exit;

  { ---- the bands, innermost first, under everything ---- }
  { [R5-J] RadarView MERGES THE BANDS OF ONE COLOUR into one path
    (mergePath) and adds those paths in colour order: a polygon radar's
    bands of a colour are one element here (its contours in Cmds), so no
    seam shows between two bands of one colour and a gradient spans their
    box; a circle radar's rings stay an element each (a sector), the
    gradient over their union [was: an element per band, a gradient entry
    dropped from the list] }
  bandEl := nil;
  bandBucket := nil;
  bandBox := nil;
  mergeCmds := nil;
  mergePts := nil;
  mergeBox := nil;
  mergeHas := nil;
  mergeColour := nil;
  nb := Length(spec.SplitArea.Colours);
  if nb = 0 then nb := 2;
  if spec.SplitArea.Show then
  begin
    SetLength(mergeCmds, nb);
    SetLength(mergePts, nb);
    SetLength(mergeBox, nb);
    SetLength(mergeHas, nb);
    SetLength(mergeColour, nb);
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
      gi := k mod nb;
      rOut := ARadar.RingRadius(k + 1);
      rIn := ARadar.RingRadius(k);
      if Abs(rOut - rIn) < 1e-9 then Continue;
      if spec.Shape = rsCircle then
      begin
        el := TyChartElement(TyShapeSector(ARadar.CX, ARadar.CY,
          Min(rIn, rOut), Max(rIn, rOut), 0, 2 * Pi));
        el.Style.HasFill := True;
        el.Style.FillColor := c;
        if (gi <= High(spec.SplitArea.Grads)) and (spec.SplitArea.Grads[gi].Kind <> cgkNone) then
        begin
          el.Style.FillGradient := spec.SplitArea.Grads[gi];
          SetLength(bandEl, Length(bandEl) + 1);
          bandEl[High(bandEl)] := AList.Count;
          SetLength(bandBucket, Length(bandBucket) + 1);
          bandBucket[High(bandBucket)] := gi;
          SetLength(bandBox, Length(bandBox) + 1);
          bandBox[High(bandBox)] := TyRectF(ARadar.CX - Max(rIn, rOut),
            ARadar.CY - Max(rIn, rOut), ARadar.CX + Max(rIn, rOut), ARadar.CY + Max(rIn, rOut));
        end;
        { areaStyle.opacity [R5-B] }
        el.Style.Alpha := spec.SplitArea.Opacity;
        TyStyleSetShadow(el.Style, spec.SplitArea.Shadow);
        el.Z := AInk.Z;
        el.Z2 := 0;
        el.Silent := True;
        AList.Add(el);
        Inc(Result);
        Continue;
      end;
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
      { into its colour's path }
      j := Length(mergeCmds[gi]);
      SetLength(mergeCmds[gi], j + Length(band) + 1);
      for i := 0 to High(band) do
      begin
        mergeCmds[gi][j + i] := Default(TTyPathCmd);
        if i = 0 then mergeCmds[gi][j + i].Kind := pckMove
        else mergeCmds[gi][j + i].Kind := pckLine;
        mergeCmds[gi][j + i].X := band[i].X;
        mergeCmds[gi][j + i].Y := band[i].Y;
      end;
      mergeCmds[gi][j + Length(band)] := Default(TTyPathCmd);
      mergeCmds[gi][j + Length(band)].Kind := pckClose;
      j := Length(mergePts[gi]);
      SetLength(mergePts[gi], j + Length(band));
      for i := 0 to High(band) do
      begin
        mergePts[gi][j + i] := band[i];
        if not mergeHas[gi] then
        begin
          mergeBox[gi] := TyRectF(band[i].X, band[i].Y, band[i].X, band[i].Y);
          mergeHas[gi] := True;
        end;
        if band[i].X < mergeBox[gi].Left then mergeBox[gi].Left := band[i].X;
        if band[i].X > mergeBox[gi].Right then mergeBox[gi].Right := band[i].X;
        if band[i].Y < mergeBox[gi].Top then mergeBox[gi].Top := band[i].Y;
        if band[i].Y > mergeBox[gi].Bottom then mergeBox[gi].Bottom := band[i].Y;
      end;
      mergeColour[gi] := c;
    end;
  end;
  { the polygon radar's merged paths, in colour order }
  for gi := 0 to High(mergeCmds) do
  begin
    if Length(mergeCmds[gi]) = 0 then Continue;
    el := TyChartElement(TyShapePolygon(mergePts[gi]));
    el.Shape.Cmds := mergeCmds[gi];
    el.Shape.HasCmdBounds := True;
    el.Shape.CmdBounds := mergeBox[gi];
    el.Style.FillEvenOdd := True;
    el.Style.HasFill := True;
    el.Style.FillColor := mergeColour[gi];
    if (gi <= High(spec.SplitArea.Grads)) and (spec.SplitArea.Grads[gi].Kind <> cgkNone) then
      el.Style.FillGradient := spec.SplitArea.Grads[gi];
    { areaStyle.opacity [R5-B] }
    el.Style.Alpha := spec.SplitArea.Opacity;
    TyStyleSetShadow(el.Style, spec.SplitArea.Shadow);
    el.Z := AInk.Z;
    el.Z2 := 0;
    el.Silent := True;
    AList.Add(el);
    Inc(Result);
  end;
  { a circle radar's gradient rings: the union of their colour's }
  for k := 0 to High(bandEl) do
  begin
    u := bandBox[k];
    for i := 0 to High(bandEl) do
      if bandBucket[i] = bandBucket[k] then
      begin
        if bandBox[i].Left < u.Left then u.Left := bandBox[i].Left;
        if bandBox[i].Top < u.Top then u.Top := bandBox[i].Top;
        if bandBox[i].Right > u.Right then u.Right := bandBox[i].Right;
        if bandBox[i].Bottom > u.Bottom then u.Bottom := bandBox[i].Bottom;
      end;
    pe := AList.Ref(bandEl[k]);
    pe^.Style.GradBoxSet := True;
    pe^.Style.GradBox := TyRectToXYWH(u);
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
      { the rest of the lineStyle [R5-B] }
      LinePen(el, spec.SplitLine);
      TyStyleSetShadow(el.Style, spec.SplitLine.Shadow);
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
      LinePen(el, spec.AxisLine);
      TyStyleSetShadow(el.Style, spec.AxisLine.Shadow);
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
          AInk.NameFontSizeLogical,
          TyFontStyleCodeOver(spec.AxisName.FontStyle, AInk.NameFontWeight), w, h);
        if (w > 0) and (h > 0) then
        begin
          box := TyAnchorBox(p.X, p.Y, w, h, anchorH, anchorV);
          el := TyChartElement(TyShapeRect(box));
          el.Caption.Text := words;
          el.Caption.FontName := AInk.NameFontName;
          el.Caption.FontSizeLogical := AInk.NameFontSizeLogical;
          el.Caption.FontWeight := TyFontStyleCodeOver(spec.AxisName.FontStyle,
            AInk.NameFontWeight);
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
          AddText(i, -1, True, '');
          Inc(Result);
        end;
      end;
    end;

    { [R5-G] WHICH LABELS SHOW, before the ticks: AxisBuilder's
      fixMinMaxLabelShow on the spoke's labels in value order (an end that
      crowds its neighbour gives way, unless showMinLabel / showMaxLabel
      keeps it), hideOverlap when asked -- and a tick whose label was
      hidden goes with it (syncLabelIgnoreToMajorTicks: a radar has no
      minor ticks) [was: every label and every tick drawn] }
    SetLength(hidden, ARadar.RingCount + 1);
    for k := 0 to High(hidden) do hidden[k] := False;
    if spec.AxisLabel.Show then
      RadarLabelsShown(i, a, perp, hidden);

    { ---- the ticks and the scale labels, on EVERY spoke ---- }
    if spec.AxisTick.Show and (spec.AxisTick.LengthLogical > 0) then
    begin
      len := spec.AxisTick.LengthLogical * APPI / 96;
      for k := 0 to ARadar.RingCount do
      begin
        if hidden[k] then Continue;
        p := ARadar.CoordToPoint(ARadar.RingRadiusOf(i, k), i);
        q := TyPointF(p.X - perp.X * len, p.Y - perp.Y * len);
        el := TyChartElement(TyShapePolyline([p, q]));
        { the ticks' own pen, the line's colour, else the skin's [R5-B] }
        if spec.AxisTick.HasColour then el.Style.StrokeColor := spec.AxisTick.Colour
        else el.Style.StrokeColor := AInk.Tick;
        el.Style.StrokeWidthLogical := spec.AxisTick.WidthLogical;
        el.Style.DashLogical := TyDashPattern(spec.AxisTick.Dash,
          spec.AxisTick.DashLogical, spec.AxisTick.WidthLogical);
        el.Style.DashOffsetLogical := spec.AxisTick.DashOffset;
        el.Style.Alpha := spec.AxisTick.Opacity;
        el.Style.LineCap := spec.AxisTick.Cap;
        el.Style.LineJoin := spec.AxisTick.Join;
        el.Style.MiterLimit := spec.AxisTick.MiterLimit;
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
        if hidden[k] then Continue;
        raw := TyScaleValueLabel(ARadar.GetAxis(i).Scale,
          ARadar.RingValue(i, k), Default(TTyLabelPrecision));
        if raw = '' then Continue;
        words := LabelWords(i, k, raw);
        if words = '' then Continue;
        p := ARadar.CoordToPoint(ARadar.RingRadiusOf(i, k), i);
        p := TyPointF(p.X - perp.X * margin, p.Y - perp.Y * margin);
        AMeasurer.MeasureLine(words, AInk.LabelFontName, LabelSize,
          TyFontStyleCodeOver(spec.AxisLabel.FontStyle, AInk.LabelFontWeight), w, h);
        if (w <= 0) or (h <= 0) then Continue;
        box := TyAnchorBox(p.X, p.Y, w, h, anchorH, anchorV);
        el := TyChartElement(TyShapeRect(box));
        el.Caption.Text := words;
        el.Caption.FontName := AInk.LabelFontName;
        el.Caption.FontSizeLogical := AInk.LabelFontSizeLogical;
        el.Caption.FontWeight := TyFontStyleCodeOver(spec.AxisLabel.FontStyle,
          AInk.LabelFontWeight);
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
        AddText(i, k, False, raw);
        Inc(Result);
      end;
    end;
  end;
  j := 0;
  if j <> 0 then Exit;
end;

{ ==================== the series ==================== }

{ [R2-A] ONE POINT'S WORDS (RadarView: setLabelStyle on the symbol with
  labelDimIndex the spoke): no formatter, the spoke's STORED value -- a
  number, printed as String() prints it, and nothing for NaN; a template,
  with `{c}` the spoke's RAW value as written (getFormattedLabel takes
  params.value[labelDimIndex]: '12.50', '-', null, undefined past the end).
  A handler is called once per point with that value. }
function RadarLabelText(const ASpec: TTyLabelSpec; AStore: TTyDataStore;
  ARow, ADim, ASeriesIndex: Integer; const ASeriesName: string;
  AColour: TTyChartColor): string;
var
  it: TTyRawItem;
  cell: TTyDataValue;
  v: Double;
  vt: string;
  prm: TTyChartCallbackParams;
  has: Boolean;
begin
  vt := '';
  if ASpec.HasFormatter then
  begin
    it := AStore.RawItem(ARow);
    has := False;
    if it.Shape = rshNone then
    begin
      v := AStore.Get(ADim, ARow);
      vt := TyJsNumberToString(v);
    end
    else if TTyDataStore.RawCell(it, AStore.RawDimPos(ADim), cell) then
    begin
      vt := TyJsValueText(cell, 'null');
      has := True;
    end
    else
      vt := 'undefined';
    if TyChartIsHandlerRef(ASpec.Formatter) then
    begin
      { getFormattedLabel narrows params.value to the point's
        (labelDimIndex) before the handler sees it }
      prm := TyLabelParams(AStore, ARow, ASeriesName, ADim, 0, False,
        ASeriesIndex, TyRadarSeriesTypeName, AColour, '');
      prm.ValueText := vt;
      prm.Raw := Default(TTyRawItem);
      if has then
      begin
        prm.Raw.Shape := rshScalar;
        prm.Raw.Scalar := cell;
      end;
      Exit(TyChartRunHandler(ASpec.Formatter, TyChartOneParams(prm)));
    end;
  end
  else
  begin
    v := AStore.Get(ADim, ARow);
    if not IsNan(v) then vt := TyJsNumberToString(v);
  end;
  Result := TyLabelText(ASpec.Formatter, ASpec.HasFormatter, tldValue, AStore,
    ARow, ASeriesName, -1, 0, False, ASeriesIndex, TyRadarSeriesTypeName,
    AColour, '', True, vt);
end;

function TyBuildRadarMarks(const ABinding: TTySeriesBinding; ARadar: TTyRadar;
  const AVisual: TTyRadarVisual; AStore: TTyDataStore;
  const ADims: TTyIntegerArray; APPI: Integer; AList: TTyPaintList): Integer;

  { [R6-D] one key of the pen's colour: 'none' no pen, a colour or a
    gradient; the series' 'auto' its palette colour, any other word none }
  procedure TakeColour(const AColour: TTyOptColor; ASeries: Boolean;
    var AStyle: TTyChartElementStyle);
  begin
    if not AColour.Written then Exit;
    AStyle.StrokeGradient := Default(TTyChartGradient);
    if AColour.IsNone then AStyle.StrokeColor := 0
    else if AColour.IsAuto then
    begin
      if ASeries then AStyle.StrokeColor := AVisual.BorderAuto
      else AStyle.StrokeColor := 0;
    end
    else
    begin
      AStyle.StrokeColor := AColour.Color;
      AStyle.StrokeGradient := AColour.Gradient;
    end;
  end;

  { the item's visual style's pen: the series' border, an item's own over it
    key by key }
  function PenOf(ARaw: Integer; var AStyle: TTyChartElementStyle): Boolean;
  begin
    AStyle.StrokeColor := 0;
    AStyle.StrokeGradient := Default(TTyChartGradient);
    AStyle.StrokeWidthLogical := 1;
    TakeColour(AVisual.Border, True, AStyle);
    if not IsNan(AVisual.BorderWidthLogical) then
      AStyle.StrokeWidthLogical := AVisual.BorderWidthLogical;
    { [R7-Y] whether the width is +Infinity: the item's where it writes one }
    Result := AVisual.BorderWidthInf;
    if (ARaw < 0) or (ARaw > High(AVisual.RowBorder)) then Exit;
    TakeColour(AVisual.RowBorder[ARaw], False, AStyle);
    if (ARaw <= High(AVisual.RowBorderWidth)) and not IsNan(AVisual.RowBorderWidth[ARaw]) then
    begin
      AStyle.StrokeWidthLogical := AVisual.RowBorderWidth[ARaw];
      Result := (ARaw <= High(AVisual.RowBorderWidthInf)) and AVisual.RowBorderWidthInf[ARaw];
    end;
  end;

var
  k, i, n, rows, raw, m: Integer;
  pts, ring: TTyPointFArray;
  spoke: TTyIntegerArray;
  rowColour: TTyChartColor;
  v, op: Double;
  el: TTyChartElement;
  sym: TTyChartShape;
  rowSym: TTySymbolSpec;
  rowArea, rowItemLabel: Boolean;
  rowLabel: TTyLabelSpec;
  lineInf: Boolean;
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
    SetLength(spoke, n);
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
      { A MISSING VALUE IS A POINT AT THE CENTRE: radarLayout replaces a point
        it cannot place with getValueMissingPoint, [cx, cy], and the ring,
        its symbol and its label go there.
        [R2-A: the spoke was skipped and its neighbours joined, on the belief
        that upstream pushed a NaN point the canvas then skipped.] }
      pts[m] := ARadar.ValueToPoint(v, i);
      if IsNan(v) or IsNan(pts[m].X) or IsNan(pts[m].Y) then
        pts[m] := TyPointF(ARadar.CX, ARadar.CY);
      spoke[m] := i;
      Inc(m);
    end;
    if m < 2 then Continue;
    SetLength(ring, m + 1);
    for i := 0 to m - 1 do ring[i] := pts[i];
    ring[m] := pts[0];

    el := TyChartElement(TyShapePolyline(ring));
    el.Style.StrokeColor := rowColour;
    { [R5-G] the lineStyle's colour, the item's over the series' }
    if (raw >= 0) and (raw <= High(AVisual.RowLineColourSet))
      and AVisual.RowLineColourSet[raw] then
    begin
      if AVisual.RowLineNone[raw] then el.Style.StrokeColor := 0
      else
      begin
        el.Style.StrokeColor := AVisual.RowLineColour[raw];
        el.Style.StrokeGradient := AVisual.RowLineGrad[raw];
      end;
    end
    else if AVisual.LineColourSet then
    begin
      if AVisual.LineNone then el.Style.StrokeColor := 0
      else
      begin
        el.Style.StrokeColor := AVisual.LineColour;
        el.Style.StrokeGradient := AVisual.LineGrad;
      end;
    end;
    el.Style.StrokeWidthLogical := AVisual.LineWidthLogical;
    { [R7-Y] whether the width is +Infinity: the item's own where it writes
      one, else the series' [was: the series' alone, and kept under an
      item's number] }
    lineInf := AVisual.LineInf;
    { [R2-B] the ring's lineStyle width and type: the item's own over the
      series' (RadarView: itemModel.getModel('lineStyle').getLineStyle()) }
    if (raw >= 0) and (raw <= High(AVisual.RowLineSet)) and AVisual.RowLineSet[raw] then
    begin
      if not IsNan(AVisual.RowLineWidth[raw]) then
      begin
        el.Style.StrokeWidthLogical := AVisual.RowLineWidth[raw];
        lineInf := (raw <= High(AVisual.RowLineInf)) and AVisual.RowLineInf[raw];
      end;
      if AVisual.RowLineDash[raw] <> todNone then
      begin
        el.Style.DashLogical := TyDashPattern(AVisual.RowLineDash[raw],
          AVisual.RowLineDashExplicit[raw], el.Style.StrokeWidthLogical);
        el.Style.DashWord := TyDashWord(AVisual.RowLineDash[raw]);
      end
      else
      begin
        el.Style.DashLogical := TyDashPattern(AVisual.LineDash, AVisual.LineDashExplicit,
          el.Style.StrokeWidthLogical);
        el.Style.DashWord := TyDashWord(AVisual.LineDash);
      end;
    end
    else
    begin
      el.Style.DashLogical := TyDashPattern(AVisual.LineDash, AVisual.LineDashExplicit,
        el.Style.StrokeWidthLogical);
      el.Style.DashWord := TyDashWord(AVisual.LineDash);
    end;
    if lineInf then
    begin
      el.Style.StrokeWidthLogical := 0;
      el.HitNone := True;
      { [R7-W] stroked at the lineWidth the canvas had (TyLinesCanvasLeftovers) }
      el.CanvasFlags := el.CanvasFlags or cTyCanvasWidthLeft;
    end;
    { [R2-I2] its phase, key by key the same way }
    el.Style.DashOffsetLogical := AVisual.LineDashOffset;
    if (raw >= 0) and (raw <= High(AVisual.RowLineDashOffsetSet))
      and AVisual.RowLineDashOffsetSet[raw] then
      el.Style.DashOffsetLogical := AVisual.RowLineDashOffset[raw];
    el.Z := AVisual.Z;
    el.Z2 := AVisual.Z2;
    el.Silent := False;
    { A RING IS ONE ELEMENT FOR A WHOLE ROW, so it answers with the row and no
      spoke -- the same shape a line series' run has. }
    el.Datum := TyChartDatum(ABinding.SeriesIndex, k, raw);
    { [R2-I3] zrender's Path.contain on a stroke with no fill: max(lineWidth,
      strokeContainThreshold 5), half each side -- the ring's own width, as a
      line series' run and a graph's edge [was: the series' width / 2 + 4] }
    el.HitSlopLogical := Math.Max(el.Style.StrokeWidthLogical, Double(5)) / 2;
    el.Anim.Role := carRadarLine;
    el.Anim.Series := ABinding.SeriesIndex;
    el.Anim.Index := k;
    el.Anim.G[0] := ARadar.CX;
    el.Anim.G[1] := ARadar.CY;
    AList.Add(el);
    Inc(Result);

    { THE AREA AFTER THE RING, as RadarView adds them to the item's group
      (polyline, polygon, symbols): equal z and z2, so the order in the list
      is the order on the screen and the fill covers the ring [R2-B: it was
      drawn first, the ring over it]. Without an areaStyle it is built
      ignored when a state has one [F2b]. An item's own areaStyle shows it
      too [F4a]. }
    rowArea := AVisual.HasArea;
    if (raw >= 0) and (raw <= High(AVisual.RowArea)) and AVisual.RowArea[raw] then
      rowArea := True;
    if rowArea or AVisual.StateArea then
    begin
      el := TyChartElement(TyShapePolygon(Copy(ring, 0, m)));
      el.Ignore := not rowArea;
      el.Style.HasFill := True;
      if (raw >= 0) and (raw <= High(AVisual.RowAreaColourSet))
        and AVisual.RowAreaColourSet[raw] then
        el.Style.FillColor := AVisual.RowAreaColour[raw]
      else if AVisual.AreaAuthored then
        el.Style.FillColor := AVisual.Area
      else if AVisual.AreaNone then
      begin
        el.Style.HasFill := False;
        el.Style.FillColor := 0;
        el.Style.HitNoFill := True;
      end
      else
        el.Style.FillColor := rowColour;
      if (raw >= 0) and (raw <= High(AVisual.RowAreaOpacitySet))
        and AVisual.RowAreaOpacitySet[raw] then
        el.Style.Alpha := AVisual.RowAreaOpacity[raw]
      else
        el.Style.Alpha := AVisual.AreaOpacity;
      if (raw >= 0) and (raw <= High(AVisual.Decals)) then
        el.Style.Decal := AVisual.Decals[raw];
      el.Z := AVisual.Z;
      el.Z2 := AVisual.Z2;
      el.Silent := False;
      el.Datum := TyChartDatum(ABinding.SeriesIndex, k, raw);
      { its points grow out of the centre (RadarView.ts:111-130) [Batch 89] }
      el.Anim.Role := carRadarArea;
      el.Anim.Series := ABinding.SeriesIndex;
      el.Anim.Index := k;
      el.Anim.G[0] := ARadar.CX;
      el.Anim.G[1] := ARadar.CY;
      AList.Add(el);
      Inc(Result);
    end;

    rowSym := AVisual.Symbol;
    { [R2-A] the item's own symbol over the series' -- placed as RadarView's
      createSymbol places it: no offset, no kept aspect }
    if (raw >= 0) and (raw <= High(AVisual.RowSymSet)) and AVisual.RowSymSet[raw]
      and (raw <= High(AVisual.RowSyms)) then
      rowSym := AVisual.RowSyms[raw];
    rowSym.OffsetX := 0;
    rowSym.OffsetY := 0;
    rowSym.KeepAspect := False;
    if (raw >= 0) and (raw <= High(AVisual.Sizes)) and not IsNan(AVisual.Sizes[raw]) then
    begin
      rowSym.WidthPx := AVisual.Sizes[raw];
      rowSym.HeightPx := AVisual.Sizes[raw];
    end;
    { [R2-A] the row's label: its item's own over the series' }
    rowLabel := AVisual.Label_;
    rowItemLabel := (raw >= 0) and (raw <= High(AVisual.HasItemLabel))
      and AVisual.HasItemLabel[raw] and (raw <= High(AVisual.ItemLabels));
    if rowItemLabel then rowLabel := AVisual.ItemLabels[raw];
    if rowSym.Kind <> tsyNone then
      for i := 0 to m - 1 do
      begin
        sym := TyBuildSymbolUnit(rowSym, pts[i].X, pts[i].Y);
        if not TyRectFIsValid(TyShapeBounds(sym)) then Continue;
        { [R7-F] hit in its own frame, as RadarView's createSymbol }
        TySymbolHitFrame(sym, rowSym, pts[i].X, pts[i].Y);
        el := TyChartElement(sym);
        { [R7-P] its pen through the unit path's transform (strokeNoScale) }
        TyStyleNoScalePen(el.Style, TySymbolUnitFrame(rowSym, pts[i].X, pts[i].Y));
        el.Style.HasFill := True;
        { [R6-D] the item's visual style first (useStyle(itemStyle)): its
          border's colour and width, zrender's 1 where none is written --
          [R7-Y] a width of +Infinity strokes at the lineWidth the canvas had
          (TyLinesCanvasLeftovers) and its stroked rect is not a number:
          never hit [was: no pen, hit] }
        if PenOf(raw, el.Style) then
        begin
          el.Style.StrokeWidthLogical := 0;
          if ((el.Style.StrokeColor shr 24) <> 0) or (el.Style.StrokeGradient.Kind <> cgkNone) then
          begin
            el.HitNone := True;
            el.CanvasFlags := el.CanvasFlags or cTyCanvasWidthLeft;
          end;
        end;
        { [R7-L] and its opacity, which the point's label takes as well
          [was: never read -- the symbols opaque, their labels at 1] }
        op := AVisual.Opacity;
        if (raw >= 0) and (raw <= High(AVisual.RowOpacity))
          and not IsNan(AVisual.RowOpacity[raw]) then
          op := AVisual.RowOpacity[raw];
        if not IsNan(op) then el.Style.Alpha := Min(Double(1), Max(Double(0), op));
        { then setColor(color): an empty symbol's pen is the colour at 2, a
          line's the colour at the border's width [was: both at 2, the
          border never drawn] }
        if rowSym.Empty or (rowSym.Kind = tsyLine) then
        begin
          el.Style.StrokeColor := rowColour;
          el.Style.StrokeGradient := Default(TTyChartGradient);
          if rowSym.Kind = tsyLine then
            el.Style.FillColor := 0
          else
          begin
            el.Style.StrokeWidthLogical := 2;
            el.Style.FillColor := AVisual.EmptyFill;
          end;
        end
        else
          el.Style.FillColor := rowColour;
        if (raw >= 0) and (raw <= High(AVisual.Decals)) then
          el.Style.Decal := AVisual.Decals[raw];
        el.Z := AVisual.Z;
        { z2 100 (RadarView.ts:67): above every item's ring even when one
          is lifted by an emphasis or a select [F2b] }
        el.Z2 := AVisual.Z2 + 100;
        el.Silent := False;
        el.Datum := TyChartDatum(ABinding.SeriesIndex, k, raw);
        { [R2-I3] a Symbol path: upstream's reach and the port's mouse pad,
          as every other symbol [was: a fixed 4 px] }
        TySymbolHitSlop(el);
        { [F3c] the symbol path RadarView makes (createSymbol(-1, -1, 2, 2)
          under half its size, turned, at the point; strokeNoScale), after
          the line and the area in the item's group }
        el.Anim.Series := ABinding.SeriesIndex;
        el.Anim.UtTag := 1;
        el.Anim.UtRow := k;
        el.Anim.UtOrder := 2 + i;
        el.Anim.UtBase := TTyDoubleArray.Create(3);
        el.Anim.UtNoScale := True;
        { [R2-I2] its spoke + 1: an update slides it on the proxy of that
          spoke (TyRadarSymRole) }
        el.Anim.Sub := i + 1;
        el.Caption.LgSymbol := TyGuideSymbolName(rowSym);
        el.Caption.LgKeepAspect := rowSym.KeepAspect;
        el.Caption.LgG[0] := rowSym.WidthPx;
        el.Caption.LgG[1] := rowSym.HeightPx;
        el.Caption.LgG[2] := rowSym.RotateDeg;
        el.Caption.LgG[3] := 0;
        el.Caption.LgG[4] := 0;
        el.Caption.LgG[5] := pts[i].X;
        el.Caption.LgG[6] := pts[i].Y;
        { [R2-A] THE POINT'S LABEL, hung on its symbol (RadarView's
          setLabelStyle): the expansion places it off the box zrender lays a
          symbol's text against -- the unit path's box grown by the stroke,
          through the symbol's scale and turn -- and fades it in. Built when
          a state shows it too; an empty text (NaN, no formatter) is none. }
        if (rowLabel.Show or rowLabel.StateShow) and (rowLabel.Position <> tlpNone) then
        begin
          el.Caption.Text := RadarLabelText(rowLabel, AStore, k, ADims[spoke[i]],
            ABinding.SeriesIndex, AVisual.SeriesName, rowColour);
          if rowItemLabel then el.Caption.ItemSpec := raw + 1;
          { one of the item's several labels }
          el.Caption.LabelSub := i + 1;
          { and a label line's host: the symbol (LabelManager's
            _updateLabelLine), in the item's colour }
          el.Caption.LgKind := cTyGuideHostSymbol;
          el.Caption.LgColor := rowColour;
          el.Caption.HasSymBox := True;
          el.Caption.SymBox := TySymbolLabelBox(rowSym, pts[i].X, pts[i].Y,
            el.Style.StrokeWidthLogical,
            (el.Style.StrokeWidthLogical > 0) and (el.Style.StrokeColor <> 0),
            el.Style.HasFill);
        end;
        AList.Add(el);
        Inc(Result);
      end;
  end;
end;

end.
