unit tyControls.AdvChart.Pie;
{$mode objfpc}{$H+}
{ The first series that is not on a coordinate system.

  Everything the chart drew until now went through a cartesian: a datum became a
  point because an axis mapped it. A pie has no axis. Its geometry comes from a
  CENTRE and a RADIUS solved out of the series' own box, and its angles come
  from the values' share of a total. That is a second, parallel way of turning
  data into shapes, and it lives here rather than in AdvChart.Marks because that
  unit's entry point requires a cartesian and two axes before it will look at
  anything -- correctly, since a bar without a base axis is meaningless.

  PORTED FROM src/chart/pie/pieLayout.ts, ECharts 6.1.0, plus getCircleLayout in
  src/util/layout.ts. The arithmetic below is that file's, transcribed; where a
  line reads oddly it is because upstream reads oddly and a tidier version would
  be a different chart.

  FIVE THINGS THAT ARE EASY TO GET WRONG, all of them checked against the source
  rather than against the documentation:

  1. THE TWO PERCENTAGE BASES ARE DIFFERENT. `center` is a percentage of the
     view rect's WIDTH and HEIGHT separately, plus its origin. `radius` is a
     percentage of min(width, height) / 2 -- half the shorter side. So the
     default radius '50%' is a quarter of the shorter side, not half of it, and
     the catalog's transcribed [0, '75%'] is a full third too large.

  2. THE ANGLES ARE NEGATED. The option's startAngle is the mathematical
     convention -- degrees counter-clockwise from three o'clock. The layout
     turns it into canvas radians, where +y is down and increasing angles run
     clockwise, by negating it. The default 90 becomes -Pi/2: twelve o'clock.

  3. THE SECOND PASS IS NOT AN EDGE CASE. `restAngle` starts at the whole sweep
     and only shrinks when a sector hits minAngle, so the "some sector was
     constrained" test `restAngle < 2*Pi` is TRUE for every pie that does not go
     all the way round -- a half doughnut included. The first pass sized those
     sectors against a full turn; the second is what fits them into the half.
     Skip it as an edge case and every partial pie overflows its own arc.

  4. NEGATIVE VALUES ARE REMOVED, not clamped and not drawn backwards. Upstream
     filters them out in a processor before the layout ever runs, so they take
     no angle, contribute nothing to the sum, and do not even hold a place in
     the ordering. A NaN is not the same thing: it keeps its place.

  5. ONE DIVISION UPSTREAM GETS AWAY WITH. When every sector is pinned to
     minAngle, the second pass divides by a sum of zero; JavaScript answers
     Infinity and the value is then never used, because the same test that
     pinned each sector also selects the pinned branch. Free Pascal would raise.
     The guard here is that division, not a behaviour change.

  PURE, like everything upstream of AdvChart.Measure: SysUtils, Math, fpjson and
  the AdvChart units. Colours arrive resolved. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Series,
  tyControls.AdvChart.Layout;

type
  { roseType: absent, 'radius' or 'area'.

    Both draw a datum's radius from its value; they differ in the ANGLE. Only
    'area' gives every sector the same angle -- which is what makes its sectors'
    areas proportional, since area goes with the square of the radius. }
  TTyRoseType = (prtNone, prtRadius, prtArea);

  TTyBoxValueArray = array of TTyBoxValue;

  { The pie-shaped options of one series, read off its option node.

    Angles are kept in DEGREES here, exactly as the option spells them, and
    turned into radians inside the layout. Storing them pre-converted would put
    the negation in two places. }
  TTyPieSpec = record
    { left/top/right/bottom/width/height -- the series' own box. Its default is
      the whole viewport, which is why an ordinary pie is centred on the
      control and not on a grid. }
    Box: TTyBoxSpec;
    CentreX, CentreY: TTyBoxValue;
    Radius0, Radius1: TTyBoxValue;
    StartAngleDeg: Double;
    { endAngle: 'auto' is the default and means "one full turn from the start".
      A number is an absolute angle in the same convention as the start. }
    EndAngleAuto: Boolean;
    EndAngleDeg: Double;
    Clockwise: Boolean;
    MinAngleDeg: Double;
    PadAngleDeg: Double;
    { Not used by the layout; carried so the label pass can ask. }
    MinShowLabelAngleDeg: Double;
    Rose: TTyRoseType;
    { When every value is zero, still show equal slices rather than nothing. }
    StillShowZeroSum: Boolean;
    PercentPrecision: Integer;
    ShowEmptyCircle: Boolean;
    { itemStyle.borderRadius, UNRESOLVED. A percentage here is a percentage
      of a radius the sector does not have yet -- and under roseType every
      sector has a different one -- so the values are carried as written and
      resolved per sector when the marks are built. }
    Corners: TTyBoxValueArray;
  end;

  { One datum's wedge, in DEVICE px and canvas radians.

    Angle is the sweep the datum was GIVEN, before padAngle bit into it, which
    is what minAngle is compared against and what a label pass tests against
    minShowLabelAngle. StartRad..EndRad is what gets drawn. }
  TTyPieSector = record
    RawIndex: Integer;
    { The same row in the store's CURRENT VIEW. Not derivable from the
      subscript: a negative value is removed from the layout entirely, so the
      sector index counts sectors and nothing else. Kept here because this is
      the one pass that has both numbers in hand. }
    Index: Integer;
    { False when the value is not a number. The sector still exists and still
      holds its place in the ordering; it simply has no geometry. }
    Valid: Boolean;
    Value: Double;
    Angle: Double;
    StartRad, EndRad: Double;
    CX, CY, R0, R1: Double;
  end;
  TTyPieSectorArray = array of TTyPieSector;

  { The whole series' geometry: the ring the sectors live on, and the sectors.

    The ring is kept even when there are no sectors, because showEmptyCircle
    draws exactly that. }
  TTyPieLayout = record
    { False when the series could not be laid out at all -- no store, or a
      dimension that is not there. }
    Valid: Boolean;
    ViewRect: TTyRectF;
    CX, CY, R0, R1: Double;
    StartRad, EndRad: Double;
    Clockwise: Boolean;
    Sectors: TTyPieSectorArray;
  end;

  { What a pie looks like, resolved by the control.

    ONE COLOUR PER DATUM, not one per series: a pie is colorBy:'data', and a
    single-colour pie would be one disc. The array is cycled, so a caller may
    hand over as many as it likes. }
  TTyPieVisual = record
    Fills: array of TTyChartColor;
    { per sector: the fill as an object -- a gradient or a pattern, the
      series' or the datum's own -- or nothing [Batch 105] }
    Objs: TTyChartObjFillArray;
    { per sector: a visualMap's opacity, NaN where none was written }
    Alphas: TTyDoubleArray;
    Stroke: TTyChartColor;
    StrokeWidthLogical: Double;
    { device px per logical px: a border grows a gradient's box by its
      width on the device [Batch 105] }
    PxScale: Double;
    { showEmptyCircle's ring, drawn when nothing else is. }
    EmptyFill: TTyChartColor;
    Z, Z2: Integer;
  end;

const
  { ECharts' own spelling of both, in one place: the chart names the type when
    it decides which pass to run, and names the dimension when it builds the
    store and again when it reads it back. }
  TyPieSeriesTypeName = 'pie';
  TyPieValueDim = 'value';

{ THE BOX A SECTOR'S LOCAL GRADIENT NORMALISES AGAINST: the bounding rect of
  the path roundSector.buildPath draws (no corners) -- the arc's own extent
  with the centre or the inner arc, not the whole disc -- in zrender's
  bbox arithmetic and with JavaScript's trigonometry. [Batch 105] }
function TyPieSectorPathBox(ACX, ACY, AR0, AR, AStart, AEnd: Double;
  AClockwise: Boolean): TTyXYWH;

{ ---- the option ---- }
{ Upstream's defaults, all of them from PieSeries.ts rather than the docs. }
function TyPieSpecDefault: TTyPieSpec;
function TyPieSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyPieSpec;

{ ---- the arithmetic, exposed because each is worth testing on its own ---- }
{ zrender's normalizeArcAngles: wrap the start into [0, 2*Pi) and pull the end
  onto the correct side of it, never further than one turn away.

  THE RULE MOVED to the shape layer, where angles live and where a second
  series can reach it -- a gauge asking a PIE which way its dial runs is the
  borrowed-name mistake wearing another hat. Only the name is here, and only
  because this unit's own tests call it. }
procedure TyNormalizeArcAngles(var AStart, AEnd: Double; AAnticlockwise: Boolean);

{ parsePercent, in the one form this unit needs: a value against a base. }
function TyPieResolve(const AValue: TTyBoxValue; ABase: Double): Double;

{ The largest remainder method, so a pie's percentages add up to 100. }
function TyPiePercentSeats(const AValues: array of Double;
  APrecision: Integer): TTyDoubleArray;

{ Each sector's percentage, index-parallel to ALayout.Sectors -- the `{d}` a
  label or a tooltip template shows. Over the sectors that exist: the legend's
  filtered rows, the negatives already gone, a missing value counted as 0. A
  total of nothing is 0 for every slice, as upstream's `seats[i] || 0` -- and
  so is every slice of a precision too large to count in. }
function TyPieSectorPercents(const ALayout: TTyPieLayout;
  APrecision: Integer): TTyDoubleArray;

{ ---- the layout ---- }
{ ADim is the store column holding the value. AViewport is the control's own
  rect: the series' box is solved against it. }
function TyPieLayoutOf(const ASpec: TTyPieSpec; const AViewport: TTyRectF;
  AStore: TTyDataStore; ADim: Integer): TTyPieLayout;

{ Resolve one sector's corner radii against its own geometry.

  THE PERCENTAGE BASE IS THE OUTER RADIUS, NOT THE RING'S THICKNESS, and
  that is upstream's operator precedence rather than upstream's intent:
  sectorHelper.ts:37 writes `Math.abs(shape.r || 0 - shape.r0 || 0)`, and `-`
  binds tighter than `||`, so the expression is `r || (0 - r0) || 0` and a
  non-zero r wins outright. Run it with r = 80 and r0 = 30 and it answers 80,
  not the 50 the name dr suggests. Transcribed, because a port that quietly
  did the sensible thing would draw different corners from every ECharts
  chart it is compared against. }
function TyPieCornersFor(const ASpec: TTyPieSpec;
  AR0, AR1: Double): TTyDoubleArray;

{ ---- the marks ---- }
{ Append this pie's sectors to AList and answer how many were added. A sector
  with no sweep adds nothing; a layout with no sectors at all adds the empty
  ring when the option asks for it. }
function TyBuildPieMarks(const ABinding: TTySeriesBinding;
  const ALayout: TTyPieLayout; const ASpec: TTyPieSpec;
  const AVisual: TTyPieVisual; AList: TTyPaintList): Integer;

function TyPieVisual(AFill: TTyChartColor): TTyPieVisual;

implementation

uses tyControls.AdvChart.Scale, tyControls.AdvChart.ZrPath,
     tyControls.AdvChart.JsMath;

function TyPieSectorPathBox(ACX, ACY, AR0, AR, AStart, AEnd: Double;
  AClockwise: Boolean): TTyXYWH;
const
  cE = 1e-4;
var
  p: TTyZrPath;
  radius, inner, t, arc, m: Double;
begin
  Result := Default(TTyXYWH);
  p := nil;
  radius := Math.Max(AR, 0);
  inner := Math.Max(AR0, 0);
  if (radius <= 0) and (inner <= 0) then Exit;
  if radius <= 0 then
  begin
    radius := inner;
    inner := 0;
  end;
  if inner > radius then
  begin
    t := radius;
    radius := inner;
    inner := t;
  end;
  if IsNan(AStart) or IsNan(AEnd) then Exit;
  arc := Abs(AEnd - AStart);
  if arc > 2 * Pi then
  begin
    m := arc - Int(arc / (2 * Pi)) * (2 * Pi);
    if m > cE then arc := m;
  end;
  if not (radius > cE) then
    TyZrMoveTo(p, ACX, ACY)
  else if arc > 2 * Pi - cE then
  begin
    TyZrMoveTo(p, ACX + radius * TyJsCos(AStart), ACY + radius * TyJsSin(AStart));
    TyZrArc(p, ACX, ACY, radius, AStart, AEnd, not AClockwise);
    if inner > cE then
    begin
      TyZrMoveTo(p, ACX + inner * TyJsCos(AEnd), ACY + inner * TyJsSin(AEnd));
      TyZrArc(p, ACX, ACY, inner, AEnd, AStart, AClockwise);
    end;
  end
  else
  begin
    if not (arc > cE) then
      TyZrMoveTo(p, ACX + radius * TyJsCos(AStart), ACY + radius * TyJsSin(AStart))
    else
    begin
      TyZrMoveTo(p, ACX + radius * TyJsCos(AStart), ACY + radius * TyJsSin(AStart));
      TyZrArc(p, ACX, ACY, radius, AStart, AEnd, not AClockwise);
    end;
    TyZrLineTo(p, ACX + inner * TyJsCos(AEnd), ACY + inner * TyJsSin(AEnd));
    if (inner > cE) and (arc > cE) then
      TyZrArc(p, ACX, ACY, inner, AEnd, AStart, AClockwise);
  end;
  TyZrClose(p);
  Result := TyZrBBox(p);
end;

const
  cRadian = Pi / 180;
  cTwoPi = Pi * 2;

{ ==================== the option ==================== }

function TyPieSpecDefault: TTyPieSpec;
begin
  Result.Box := TyBoxSpec;
  { PieSeries.ts:258-263. All four edges pinned at zero and no size given, so
    the box solves to the whole container -- which is what makes an ordinary
    pie centre on the control. }
  Result.Box.Left := TyBoxPx(0);
  Result.Box.Top := TyBoxPx(0);
  Result.Box.Right := TyBoxPx(0);
  Result.Box.Bottom := TyBoxPx(0);
  Result.CentreX := TyBoxPercent(50);
  Result.CentreY := TyBoxPercent(50);
  { PieSeries.ts:229 -- [0, '50%'], NOT the [0, '75%'] the catalog transcribed
    from the documentation. Half the shorter side is the DIAMETER, so this is a
    quarter of it. }
  Result.Radius0 := TyBoxPx(0);
  Result.Radius1 := TyBoxPercent(50);
  Result.StartAngleDeg := 90;
  Result.EndAngleAuto := True;
  Result.EndAngleDeg := 0;
  Result.Clockwise := True;
  Result.MinAngleDeg := 0;
  Result.PadAngleDeg := 0;
  Result.MinShowLabelAngleDeg := 0;
  Result.Rose := prtNone;
  Result.StillShowZeroSum := True;
  Result.PercentPrecision := 2;
  Result.ShowEmptyCircle := True;
  Result.Corners := nil;
end;

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData is TJSONObject) then
    Result := TJSONObject(AData)
  else
    Result := nil;
end;

function ParseFloatIn(const AText: string; out AValue: Double): Boolean;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := TryStrToFloat(Trim(AText), AValue, fs);
end;

{ parsePositionOption's keyword table plus its two number forms. A value that
  parses to nothing keeps the default, which is where this and upstream part
  company: JavaScript answers NaN and lets the arithmetic carry it. A NaN
  centre would put the whole pie nowhere, so an unreadable option is treated as
  absent instead. }
function TyPieMeasureOf(AData: TJSONData; const ADefault: TTyBoxValue): TTyBoxValue;
var
  s: string;
  v: Double;
begin
  Result := ADefault;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  if AData.JSONType = jtNumber then Exit(TyBoxPx(AData.AsFloat));
  if AData.JSONType <> jtString then Exit;
  s := Trim(AData.AsString);
  if s = '' then Exit;
  if (s = 'center') or (s = 'centre') or (s = 'middle') then Exit(TyBoxPercent(50));
  if (s = 'left') or (s = 'top') then Exit(TyBoxPercent(0));
  if (s = 'right') or (s = 'bottom') then Exit(TyBoxPercent(100));
  if s[Length(s)] = '%' then
  begin
    if ParseFloatIn(Copy(s, 1, Length(s) - 1), v) then Exit(TyBoxPercent(v));
    Exit;
  end;
  if ParseFloatIn(s, v) then Result := TyBoxPx(v);
end;

function TyPieResolve(const AValue: TTyBoxValue; ABase: Double): Double;
begin
  { THE RULE MOVED to where the type lives. One implementation, two names, and
    only the name is here -- this is what the pie's own tests call it. }
  Result := TyBoxResolve(AValue, ABase);
end;

{ A pair option in ECharts' two spellings: an array of two, or a scalar.

  WHAT A SCALAR MEANS IS NOT THE SAME FOR THE TWO KEYS, which is why this
  takes a flag rather than working it out. layout.ts:209 duplicates a bare
  CENTRE into both axes; layout.ts:236 rebuilds a bare RADIUS as [0, radius],
  so the scalar is the outer one and the inner is forced to zero. One shared
  rule gives a doughnut whose hole is the whole disc, which draws nothing. }
procedure ReadPair(ANode: TJSONObject; const AKey: string;
  var A0, A1: TTyBoxValue; ADuplicateScalar: Boolean);
var
  d: TJSONData;
  arr: TJSONArray;
begin
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  if d is TJSONArray then
  begin
    arr := TJSONArray(d);
    if arr.Count > 0 then A0 := TyPieMeasureOf(arr.Items[0], A0);
    if arr.Count > 1 then A1 := TyPieMeasureOf(arr.Items[1], A1);
    Exit;
  end;
  A1 := TyPieMeasureOf(d, A1);
  if ADuplicateScalar then A0 := A1;
end;

function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  Result := d.AsFloat;
end;

function BoolIn(ANode: TJSONObject; const AKey: string; ADefault: Boolean): Boolean;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtBoolean) then Exit;
  Result := d.AsBoolean;
end;

{ itemStyle.borderRadius, kept in whatever units it was written in.

  A SCALAR IS EXPANDED TO FOUR HERE, not left as one, because upstream does
  it before zrender ever sees it -- sectorHelper.ts:34-36 -- and zrender's
  own rule for a ONE-ELEMENT array is different from its rule for a number:
  `5` rounds all four corners while `[5]` rounds only the inner pair. Leave
  the scalar alone and a plain `borderRadius: 8` on a doughnut rounds the
  hole and leaves the rim square. }
function ReadCorners(ANode: TJSONObject): TTyBoxValueArray;
var
  d, item: TJSONData;
  arr: TJSONArray;
  i, n: Integer;
  none: TTyBoxValue;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find('itemStyle');
  if (d = nil) or not (d is TJSONObject) then Exit;
  d := TJSONObject(d).Find('borderRadius');
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  none := TyBoxPx(0);
  if not (d is TJSONArray) then
  begin
    SetLength(Result, 4);
    for i := 0 to 3 do Result[i] := TyPieMeasureOf(d, none);
    Exit;
  end;
  arr := TJSONArray(d);
  n := arr.Count;
  if n > 4 then n := 4;
  if n = 0 then Exit;
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    item := arr.Items[i];
    Result[i] := TyPieMeasureOf(item, none);
  end;
end;

function TyPieSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyPieSpec;
var
  node: TJSONObject;
  d: TJSONData;
  s: string;
begin
  Result := TyPieSpecDefault;
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('series', ASlot));
  if node = nil then Exit;

  Result.Box.Left := TyPieMeasureOf(node.Find('left'), Result.Box.Left);
  Result.Box.Top := TyPieMeasureOf(node.Find('top'), Result.Box.Top);
  Result.Box.Right := TyPieMeasureOf(node.Find('right'), Result.Box.Right);
  Result.Box.Bottom := TyPieMeasureOf(node.Find('bottom'), Result.Box.Bottom);
  Result.Box.Width := TyPieMeasureOf(node.Find('width'), Result.Box.Width);
  Result.Box.Height := TyPieMeasureOf(node.Find('height'), Result.Box.Height);

  ReadPair(node, 'center', Result.CentreX, Result.CentreY, True);
  { The inner radius of a bare `radius: '60%'` is ZERO, not the default inner
    radius: upstream rebuilds the pair as [0, radius]. }
  d := node.Find('radius');
  if (d <> nil) and (d.JSONType <> jtNull) and not (d is TJSONArray) then
    Result.Radius0 := TyBoxPx(0);
  ReadPair(node, 'radius', Result.Radius0, Result.Radius1, False);

  Result.StartAngleDeg := NumIn(node, 'startAngle', Result.StartAngleDeg);
  d := node.Find('endAngle');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.EndAngleAuto := False;
    Result.EndAngleDeg := d.AsFloat;
  end;
  Result.Clockwise := BoolIn(node, 'clockwise', Result.Clockwise);
  Result.MinAngleDeg := NumIn(node, 'minAngle', Result.MinAngleDeg);
  Result.PadAngleDeg := NumIn(node, 'padAngle', Result.PadAngleDeg);
  Result.MinShowLabelAngleDeg :=
    NumIn(node, 'minShowLabelAngle', Result.MinShowLabelAngleDeg);
  Result.StillShowZeroSum :=
    BoolIn(node, 'stillShowZeroSum', Result.StillShowZeroSum);
  Result.PercentPrecision :=
    TyRoundOpt(NumIn(node, 'percentPrecision', Result.PercentPrecision),
      Result.PercentPrecision);
  Result.ShowEmptyCircle :=
    BoolIn(node, 'showEmptyCircle', Result.ShowEmptyCircle);
  Result.Corners := ReadCorners(node);

  { roseType is tested for TRUTH, not for membership: pieLayout.ts:159 asks
    `roseType ?` and :119 asks `roseType !== 'area'`. So `true` behaves as
    'radius' and any unknown string does too -- which is why this is not a
    strict enum match. }
  d := node.Find('roseType');
  if d <> nil then
    case d.JSONType of
      jtString:
        begin
          s := d.AsString;
          if s = 'area' then Result.Rose := prtArea
          else if s <> '' then Result.Rose := prtRadius;
        end;
      jtBoolean:
        if d.AsBoolean then Result.Rose := prtRadius;
      jtNumber:
        if d.AsFloat <> 0 then Result.Rose := prtRadius;
    end;
end;

function TyPieVisual(AFill: TTyChartColor): TTyPieVisual;
begin
  SetLength(Result.Fills, 1);
  Result.Fills[0] := AFill;
  Result.Stroke := 0;
  Result.StrokeWidthLogical := 0;
  Result.PxScale := 1;
  Result.EmptyFill := AFill;
  { upstream's series z }
  Result.Z := 2;
  Result.Z2 := 0;
end;

{ ==================== the angle normaliser ==================== }

procedure TyNormalizeArcAngles(var AStart, AEnd: Double; AAnticlockwise: Boolean);
begin
  tyControls.AdvChart.Shape.TyNormalizeArcAngles(AStart, AEnd, AAnticlockwise);
end;

{ ==================== percentages that add up ==================== }

function SeatsJs(const AValues: array of Double;
  APrecision: Integer): TTyDoubleArray;
var
  i, n, maxId: Integer;
  sum, v, digits, target, currentSum, best: Double;
  votes, seats, remainder: TTyDoubleArray;
begin
  Result := nil;
  n := Length(AValues);
  if n = 0 then Exit;
  sum := 0;
  for i := 0 to n - 1 do
    if not IsNan(AValues[i]) then sum := sum + AValues[i];
  { number.ts:406 -- a total of zero answers an EMPTY array, not zeroes, and
    the caller reads a missing seat as 0. Two spellings of the same number, but
    the empty one is what a test can pin. }
  if sum = 0 then Exit;

  { getPercentSeats, line for line. DOUBLES THROUGHOUT: digits is
    Math.pow(10, precision), so a precision of -1 counts in tenths of a whole
    per cent rather than being clamped to whole ones, and a precision of 8
    wants ten thousand million seats, which an Integer does not hold. }
  digits := TyJsPow10(APrecision);
  target := digits * 100;
  SetLength(votes, n);
  SetLength(seats, n);
  SetLength(remainder, n);
  currentSum := 0;
  for i := 0 to n - 1 do
  begin
    if IsNan(AValues[i]) then v := 0 else v := AValues[i];
    votes[i] := v / sum * digits * 100;
    { Math.floor, in the Double: Floor answers a 32-bit Integer }
    seats[i] := Int(votes[i]);
    if seats[i] > votes[i] then seats[i] := seats[i] - 1;
    currentSum := currentSum + seats[i];
    remainder[i] := votes[i] - seats[i];
  end;

  while currentSum < target do
  begin
    best := NegInfinity;
    maxId := -1;
    for i := 0 to n - 1 do
      if remainder[i] > best then
      begin
        best := remainder[i];
        maxId := i;
      end;
    if maxId < 0 then Break;
    seats[maxId] := seats[maxId] + 1;
    remainder[maxId] := 0;
    { WHERE UPSTREAM NEVER STOPS: past 2^53 a seat more is no change to the
      running sum, and `++currentSum` spins forever -- a percentPrecision of
      14 or so hangs the browser tab. The seats given so far are the answer
      here. }
    if currentSum + 1 = currentSum then Break;
    currentSum := currentSum + 1;
  end;

  SetLength(Result, n);
  for i := 0 to n - 1 do
    Result[i] := seats[i] / digits;
end;

function TyPiePercentSeats(const AValues: array of Double;
  APrecision: Integer): TTyDoubleArray;
var mask: TFPUExceptionMask;
begin
  { THE ARITHMETIC CARRIES ON where FPC would stop: a precision past 308 makes
    digits Infinity (and one past -323 makes it 0), a slice of nothing then
    votes 0 * Infinity, and every seat comes out not-a-number -- which the
    caller turns into 0, as upstream's `seats[i] || 0` does. }
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide]);
  try
    Result := SeatsJs(AValues, APrecision);
  finally
    ClearExceptions(False);
    {$IFDEF CPUX86_64}
    SetMXCSR(GetMXCSR and not LongWord($3F));
    {$ENDIF}
    SetExceptionMask(mask);
  end;
end;

function TyPieSectorPercents(const ALayout: TTyPieLayout;
  APrecision: Integer): TTyDoubleArray;
var
  vals, seats: TTyDoubleArray;
  i: Integer;
begin
  vals := nil;
  SetLength(vals, Length(ALayout.Sectors));
  for i := 0 to High(vals) do vals[i] := ALayout.Sectors[i].Value;
  seats := TyPiePercentSeats(vals, APrecision);
  Result := nil;
  SetLength(Result, Length(vals));
  { `seats[i] || 0`: a missing seat and a not-a-number one are both 0 }
  for i := 0 to High(Result) do
    if (i <= High(seats)) and not IsNan(seats[i]) then Result[i] := seats[i]
    else Result[i] := 0;
end;

{ ==================== the layout ==================== }

{ linearMap without clamping, which is how pieLayout calls it. }
function LinearMap(AVal, AD0, AD1, AR0, AR1: Double): Double;
var subDomain, subRange: Double;
begin
  subDomain := AD1 - AD0;
  subRange := AR1 - AR0;
  if subDomain = 0 then
  begin
    if subRange = 0 then Exit(AR0);
    Exit((AR0 + AR1) / 2);
  end;
  Result := (AVal - AD0) / subDomain * subRange + AR0;
end;

function PieLayoutOfImpl(const ASpec: TTyPieSpec; const AViewport: TTyRectF;
  AStore: TTyDataStore; ADim: Integer): TTyPieLayout; forward;

{ AN INFINITE SLICE IS DATA NOW -- 'Infinity' reads as what upstream reads it
  as -- and its arithmetic goes on to not-a-number angles the way
  JavaScript's does, where FPC would raise. }
function TyPieLayoutOf(const ASpec: TTyPieSpec; const AViewport: TTyRectF;
  AStore: TTyDataStore; ADim: Integer): TTyPieLayout;
var mask: TFPUExceptionMask;
begin
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide]);
  try
    Result := PieLayoutOfImpl(ASpec, AViewport, AStore, ADim);
  finally
    ClearExceptions(False);
    {$IFDEF CPUX86_64}
    SetMXCSR(GetMXCSR and not LongWord($3F));
    {$ENDIF}
    SetExceptionMask(mask);
  end;
end;

function PieLayoutOfImpl(const ASpec: TTyPieSpec; const AViewport: TTyRectF;
  AStore: TTyDataStore; ADim: Integer): TTyPieLayout;
var
  size, startA, endA, padA, minA, minPad, halfPad: Double;
  unitRad, sum, angleRange, restAngle, sumBig, cur, ang, endOfIt: Double;
  actualStart, actualEnd, maxV, v: Double;
  dir: Double;
  validCount, i, n, k: Integer;
  rows: array of Integer;
  views: array of Integer;
  vals: TTyDoubleArray;
  anti: Boolean;
begin
  Result := Default(TTyPieLayout);
  Result.Clockwise := ASpec.Clockwise;

  { getCircleLayout, layout.ts:225-251. The two bases are different and that is
    the whole point of doing it here rather than reusing the grid's solver. }
  Result.ViewRect := TySolveBox(ASpec.Box, TyFixedContainer(AViewport));
  Result.CX := TyPieResolve(ASpec.CentreX, TyRectFWidth(Result.ViewRect))
    + Result.ViewRect.Left;
  Result.CY := TyPieResolve(ASpec.CentreY, TyRectFHeight(Result.ViewRect))
    + Result.ViewRect.Top;
  size := Min(TyRectFWidth(Result.ViewRect), TyRectFHeight(Result.ViewRect));
  Result.R0 := TyPieResolve(ASpec.Radius0, size / 2);
  Result.R1 := TyPieResolve(ASpec.Radius1, size / 2);

  { pieLayout.ts:45-53. }
  startA := -ASpec.StartAngleDeg * cRadian;
  padA := ASpec.PadAngleDeg * cRadian;
  if ASpec.EndAngleAuto then
    endA := startA - cTwoPi
  else
    endA := -ASpec.EndAngleDeg * cRadian;
  minA := ASpec.MinAngleDeg * cRadian;
  minPad := minA + padA;

  if ASpec.Clockwise then dir := 1 else dir := -1;
  halfPad := dir * padA / 2;
  anti := not ASpec.Clockwise;
  TyNormalizeArcAngles(startA, endA, anti);
  Result.StartRad := startA;
  Result.EndRad := endA;
  angleRange := Abs(endA - startA);

  if AStore = nil then Exit;
  if (ADim < 0) or (ADim >= AStore.DimCount) then Exit;
  Result.Valid := True;

  { THE NEGATIVE FILTER, src/processor/negativeDataFilter.ts:28-36. A negative
    value is removed from the data before the layout sees it, so it is not a
    sector with no angle -- it is not a sector. A NaN is kept: it holds its
    place, which the equal-angle branch below counts on. }
  n := AStore.Count;
  SetLength(rows, n);
  SetLength(views, n);
  SetLength(vals, n);
  k := 0;
  for i := 0 to n - 1 do
  begin
    v := AStore.Get(ADim, i);
    if (not IsNan(v)) and (v < 0) then Continue;
    rows[k] := AStore.GetRawIndex(i);
    views[k] := i;
    vals[k] := v;
    Inc(k);
  end;
  SetLength(rows, k);
  SetLength(views, k);
  SetLength(vals, k);
  n := k;

  validCount := 0;
  sum := 0;
  maxV := 0;
  for i := 0 to n - 1 do
    if not IsNan(vals[i]) then
    begin
      Inc(validCount);
      sum := sum + vals[i];
      if vals[i] > maxV then maxV := vals[i];
    end;

  { pieLayout.ts:62 -- `Math.PI / (sum || validDataCount) * 2`. A total of zero
    falls back to the COUNT, which is what gives equal slices when every value
    is zero. Both zero means there is nothing to draw and the loop below never
    runs, so the divisor is never asked for. }
  if sum <> 0 then unitRad := Pi / sum * 2
  else if validCount <> 0 then unitRad := Pi / validCount * 2
  else unitRad := 0;

  SetLength(Result.Sectors, n);
  restAngle := angleRange;
  sumBig := 0;
  cur := startA;

  for i := 0 to n - 1 do
  begin
    Result.Sectors[i].RawIndex := rows[i];
    Result.Sectors[i].Index := views[i];
    Result.Sectors[i].Value := vals[i];
    Result.Sectors[i].CX := Result.CX;
    Result.Sectors[i].CY := Result.CY;
    Result.Sectors[i].R0 := Result.R0;

    if IsNan(vals[i]) then
    begin
      Result.Sectors[i].Valid := False;
      Result.Sectors[i].Angle := NaN;
      Result.Sectors[i].StartRad := NaN;
      Result.Sectors[i].EndRad := NaN;
      if ASpec.Rose <> prtNone then
        Result.Sectors[i].R1 := NaN
      else
        Result.Sectors[i].R1 := Result.R1;
      Continue;
    end;

    Result.Sectors[i].Valid := True;
    if ASpec.Rose <> prtArea then
    begin
      if (sum = 0) and ASpec.StillShowZeroSum then
        ang := unitRad
      else
        ang := vals[i] * unitRad;
    end
    else
      { 'area' gives every sector the SAME angle -- the radius is what carries
        the value, and equal angles are what make the areas proportional. }
      ang := angleRange / validCount;

    if ang < minPad then
    begin
      ang := minPad;
      restAngle := restAngle - minPad;
    end
    else
      sumBig := sumBig + vals[i];

    endOfIt := cur + dir * ang;
    if padA > ang then
    begin
      actualStart := cur + dir * ang / 2;
      actualEnd := actualStart;
    end
    else
    begin
      actualStart := cur + halfPad;
      actualEnd := endOfIt - halfPad;
    end;

    Result.Sectors[i].Angle := ang;
    Result.Sectors[i].StartRad := actualStart;
    Result.Sectors[i].EndRad := actualEnd;
    if ASpec.Rose <> prtNone then
      Result.Sectors[i].R1 := LinearMap(vals[i], 0, maxV, Result.R0, Result.R1)
    else
      Result.Sectors[i].R1 := Result.R1;

    cur := endOfIt;
  end;

  { THE SECOND PASS, pieLayout.ts:169-223, and it is NOT an edge case. See the
    header: restAngle starts at the whole sweep, so this runs for every pie
    that does not go the whole way round. }
  if (restAngle < cTwoPi) and (validCount > 0) then
  begin
    if restAngle <= 1e-3 then
    begin
      { Nothing left to share out: every sector gets the same angle, placed by
        its INDEX. A NaN sector still consumes an index, so a gap in the data
        leaves a gap in the ring rather than closing it up. }
      ang := angleRange / validCount;
      for i := 0 to n - 1 do
      begin
        if IsNan(vals[i]) then Continue;
        Result.Sectors[i].Angle := ang;
        if ang < padA then
        begin
          actualStart := startA + dir * (i + 0.5) * ang;
          actualEnd := actualStart;
        end
        else
        begin
          actualStart := startA + dir * i * ang + halfPad;
          actualEnd := startA + dir * (i + 1) * ang - halfPad;
        end;
        Result.Sectors[i].StartRad := actualStart;
        Result.Sectors[i].EndRad := actualEnd;
      end;
    end
    else
    begin
      { WHERE UPSTREAM DIVIDES BY ZERO AND GETS AWAY WITH IT. sumBig is zero
        only when every sector was pinned to minPad, and then the test below
        picks the pinned branch for all of them and the quotient is never read.
        JavaScript would have produced Infinity; Free Pascal would raise, so
        the division is guarded rather than the behaviour changed. }
      if sumBig <> 0 then unitRad := restAngle / sumBig else unitRad := 0;
      cur := startA;
      for i := 0 to n - 1 do
      begin
        if IsNan(vals[i]) then Continue;
        { EXACT equality, as upstream writes it: the pinned sectors were
          ASSIGNED minPad, so they carry the identical bit pattern and a
          tolerance would only widen the test to sectors that merely landed
          near it. }
        if Result.Sectors[i].Angle = minPad then
          ang := minPad
        else
          ang := vals[i] * unitRad;
        if ang < padA then
        begin
          actualStart := cur + dir * ang / 2;
          actualEnd := actualStart;
        end
        else
        begin
          actualStart := cur + halfPad;
          actualEnd := cur + dir * ang - halfPad;
        end;
        Result.Sectors[i].StartRad := actualStart;
        Result.Sectors[i].EndRad := actualEnd;
        cur := cur + dir * ang;
      end;
    end;
  end;
end;

{ ==================== the marks ==================== }

function TyPieCornersFor(const ASpec: TTyPieSpec;
  AR0, AR1: Double): TTyDoubleArray;
var
  i: Integer;
  dr: Double;
begin
  Result := nil;
  if Length(ASpec.Corners) = 0 then Exit;
  if AR1 <> 0 then dr := Abs(AR1)
  else if AR0 <> 0 then dr := Abs(AR0)
  else dr := 0;
  SetLength(Result, Length(ASpec.Corners));
  for i := 0 to High(ASpec.Corners) do
    Result[i] := TyPieResolve(ASpec.Corners[i], dr);
end;

function TyBuildPieMarks(const ABinding: TTySeriesBinding;
  const ALayout: TTyPieLayout; const ASpec: TTyPieSpec;
  const AVisual: TTyPieVisual; AList: TTyPaintList): Integer;
var
  i, drawn: Integer;
  el: TTyChartElement;
  sh: TTyChartShape;
begin
  Result := 0;
  if (AList = nil) or not ALayout.Valid then Exit;
  if not ABinding.Resolved then Exit;

  drawn := 0;
  for i := 0 to High(ALayout.Sectors) do
  begin
    if not ALayout.Sectors[i].Valid then Continue;
    { A sector with no sweep has no ink. Not an error: padAngle eats a whole
      slice this way, and so does a zero value on a pie whose total is not
      zero. }
    if ALayout.Sectors[i].EndRad = ALayout.Sectors[i].StartRad then Continue;
    if IsNan(ALayout.Sectors[i].R1) or (ALayout.Sectors[i].R1 <= 0) then Continue;

    sh := TyShapeSector(ALayout.Sectors[i].CX, ALayout.Sectors[i].CY,
      ALayout.Sectors[i].R0, ALayout.Sectors[i].R1,
      ALayout.Sectors[i].StartRad, ALayout.Sectors[i].EndRad,
      TyPieCornersFor(ASpec, ALayout.Sectors[i].R0, ALayout.Sectors[i].R1));
    el := TyChartElement(sh);
    el.Style.HasFill := True;
    if Length(AVisual.Fills) > 0 then
      el.Style.FillColor := AVisual.Fills[i mod Length(AVisual.Fills)]
    else
      el.Style.FillColor := AVisual.EmptyFill;
    el.Style.StrokeColor := AVisual.Stroke;
    el.Style.StrokeWidthLogical := AVisual.StrokeWidthLogical;
    { A GRADIENT OR A PATTERN, normalised against the sector's PATH box --
      the arc's extent -- grown by the border when there is one [Batch 105] }
    if (i <= High(AVisual.Objs)) and AVisual.Objs[i].Present then
    begin
      el.Style.FillGradient := AVisual.Objs[i].Gradient;
      el.Style.FillPattern := AVisual.Objs[i].Pattern;
      el.Style.GradBoxSet := True;
      el.Style.GradBox := TyPieSectorPathBox(ALayout.Sectors[i].CX,
        ALayout.Sectors[i].CY, ALayout.Sectors[i].R0, ALayout.Sectors[i].R1,
        ALayout.Sectors[i].StartRad, ALayout.Sectors[i].EndRad, ALayout.Clockwise);
      if (AVisual.StrokeWidthLogical > 0) and ((AVisual.Stroke shr 24) > 0) then
        el.Style.GradBox := TyGrowByStroke(el.Style.GradBox, True,
          AVisual.StrokeWidthLogical * AVisual.PxScale);
    end;
    if (i <= High(AVisual.Alphas)) and not IsNan(AVisual.Alphas[i]) then
      el.Style.Alpha := Min(Double(1), Max(Double(0), AVisual.Alphas[i]));
    el.Z := AVisual.Z;
    el.Z2 := AVisual.Z2;
    el.Silent := False;
    { BOTH SPACES, because a pie is the one place they part: a negative value
      is removed from the layout entirely (not drawn as a zero-angle sector),
      so the sector subscript is neither the view row nor the raw one. The
      layout kept the raw index; the view index comes back through the store's
      own inverse, which answers -1 for a row a filter has since dropped. }
    el.Datum := TyChartDatum(ABinding.SeriesIndex,
      ALayout.Sectors[i].Index, ALayout.Sectors[i].RawIndex);
    { the enter animation sweeps it, or grows its radius [Batch 89] }
    el.Anim.Role := carSector;
    el.Anim.Series := ABinding.SeriesIndex;
    el.Anim.Index := ALayout.Sectors[i].Index;
    { upstream's shape as the layout gave it -- the angles NOT swapped into
      the order TyShapeSector keeps }
    el.Anim.G[0] := ALayout.Sectors[i].CX;
    el.Anim.G[1] := ALayout.Sectors[i].CY;
    el.Anim.G[2] := ALayout.Sectors[i].R0;
    el.Anim.G[3] := ALayout.Sectors[i].R1;
    el.Anim.G[4] := ALayout.Sectors[i].StartRad;
    el.Anim.G[5] := ALayout.Sectors[i].EndRad;
    { layout.angle, the sweep the datum was given: a shape key upstream's
      update tweens with the rest [Batch 90] }
    el.Anim.G[6] := ALayout.Sectors[i].Angle;
    AList.Add(el);
    Inc(drawn);
  end;

  { showEmptyCircle, PieView.ts:263-271: when the data drew NOTHING the ring
    itself is drawn in grey, so an empty pie is a visible empty pie rather than
    a blank rectangle. It is silent -- there is no datum behind it to report. }
  if (drawn = 0) and ASpec.ShowEmptyCircle and (ALayout.R1 > 0) then
  begin
    sh := TyShapeSector(ALayout.CX, ALayout.CY, ALayout.R0, ALayout.R1,
      ALayout.StartRad, ALayout.EndRad);
    el := TyChartElement(sh);
    el.Style.HasFill := True;
    el.Style.FillColor := AVisual.EmptyFill;
    el.Z := AVisual.Z;
    el.Z2 := AVisual.Z2;
    el.Silent := True;
    AList.Add(el);
    Inc(drawn);
  end;

  Result := drawn;
end;

end.
