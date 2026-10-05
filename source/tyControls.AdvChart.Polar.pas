unit tyControls.AdvChart.Polar;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the polar coordinate system and its two axis views.
  [Batch 111, C3]

  UPSTREAM'S coord/polar (Polar.ts, polarCreator.ts, AngleAxis.ts,
  RadiusAxis.ts), component/axis/AngleAxisView.ts and RadiusAxisView.ts and
  the shapes of component/axisPointer/PolarAxisPointer.ts, transcribed.

  THE TWO AXES ARE ORDINARY AXES WITH A CANVAS EXTENT. A radius axis maps a
  value to a distance from the centre in device px, an angle axis maps one
  to DEGREES; both are TTyAxis with an identity pixel map (SetPxExtent), so
  the scale, the band, DataToCoord and CoordToData are the cartesian ones.
  Upstream's Axis does not apply `inverse` to the extent -- polarCreator
  writes the extent already turned round -- so the TTyAxis' own Inverse stays
  False and the polar keeps the two flags itself: the angle's is `inverse
  !== clockwise`, and a raw extent that runs backwards toggles either AFTER
  the extents were set, which then moves nothing but what reads the flag (the
  angle line's direction, pointToCoord, the radius' name).

  THE ANGLES ARE THE MATHS CONVENTION: anticlockwise from screen-right in
  degrees, y taken down at the point-building step (coordToPoint subtracts
  the sine). A zrender arc, sector or circle takes radians CLOCKWISE on
  screen, so every arc this unit hands out has its angles negated and turned
  into radians as upstream writes them (-deg * PI / 180).

  THE RADIUS AXIS IS AN AxisBuilder AXIS -- line, arrows, ticks, labels,
  name -- in a frame of its own at the centre turned by the start angle, with
  its labels and ticks on the -1 side and AxisBuilder's rules: the spec is
  the grid's (TyFillAxisLayoutSpec) and laid out by the same routines. THE
  ANGLE AXIS IS NOT: its view puts each label at r + margin, aligned by which
  side of the centre it fell on, never thins one for crowding, and measures
  its category interval from one line's height over the band in degrees.

  WHAT IS RECORDED is the geometry upstream draws -- each tick and split
  line's two ends, each circle, arc, ring and sector -- so the paint pass
  draws it and the tests hold it to upstream's elements.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Builder, tyControls.AdvChart.Convert;

const
  TyPolarCoordSysName = 'polar';
  { the two dimensions, upstream's polarDimensions order }
  TyPolarRadiusDim = 'radius';
  TyPolarAngleDim = 'angle';

type
  { One straight piece: a tick, a split line, the radius line. Value is the
    tick it stands for (not a number where it has none); Drawn says whether
    it is drawn (a radius tick whose label was hidden goes with it);
    ColourIndex picks from the colour list (split lines). }
  TTyPolarLine = record
    X1, Y1, X2, Y2: Double;
    Value: Double;
    Drawn: Boolean;
    ColourIndex: Integer;
  end;
  TTyPolarLineArray = array of TTyPolarLine;

  { zrender's Circle (CX, CY, R), Arc (and StartAngle, EndAngle, Clockwise),
    Ring (R, R0) and Sector (all of them), angles in radians clockwise on the
    screen. }
  TTyPolarArcKind = (pakCircle, pakArc, pakRing, pakSector);
  TTyPolarArc = record
    Kind: TTyPolarArcKind;
    CX, CY, R0, R, StartAngle, EndAngle: Double;
    Clockwise: Boolean;
    ColourIndex: Integer;
    Value: Double;
  end;
  TTyPolarArcArray = array of TTyPolarArc;

  { An angle label: its text, the point it hangs by and how. }
  TTyPolarLabel = record
    Value: Double;
    Text: string;
    X, Y: Double;
    AnchorH: TTyTextAnchorH;
    AnchorV: TTyTextAnchorV;
    { the block, where the label's style needs one (a time axis' tags) }
    Rt: TTyRtPieceArray;
  end;
  TTyPolarLabelArray = array of TTyPolarLabel;

  { WHAT ONE AXIS VIEW DRAWS. The radius' labels, name and arrows are in
    Spec (Placements, NamePlacement, Arrows), as a grid axis' are; the angle's
    labels in Labels. Its line is Line (radius) or LineArc (angle); the split
    lines are lines on the angle and circles or arcs on the radius. }
  TTyPolarAxisView = record
    Shown: Boolean;
    Blank: Boolean;
    Furn: TTyAxisFurniture;
    Spec: TTyAxisLayoutSpec;
    HasLine: Boolean;
    Line: TTyPolarLine;
    LineArc: TTyPolarArc;
    Ticks, MinorTicks: TTyPolarLineArray;
    SplitLines, MinorSplitLines: TTyPolarLineArray;
    SplitCircles, MinorSplitCircles: TTyPolarArcArray;
    SplitAreas: TTyPolarArcArray;
    Labels: TTyPolarLabelArray;
    { the lengths of the colour lists the split lines and areas count in }
    SplitLineInkCount, SplitAreaInkCount: Integer;
  end;

  { One polar. Owns its two axes. Non-refcounted, as every coordinate system
    here: the chart owns it. }
  TTyPolar = class(TTyNonRefCountedObject, ITyCoordSys)
  private
    FIndex: Integer;
    FId, FName: string;
    FCX, FCY: Double;
    FRadiusAxis, FAngleAxis: TTyAxis;
    FRadiusInverse, FAngleInverse: Boolean;
  public
    RadiusView, AngleView: TTyPolarAxisView;
    { Takes ownership of both axes. }
    constructor Create(AIndex: Integer; ARadiusAxis, AAngleAxis: TTyAxis);
    destructor Destroy; override;
    procedure SetCentre(ACX, ACY: Double);
    { Polar.coordToPoint: a radius in px and an angle in degrees to a point }
    function CoordToPoint(ARadius, AAngle: Double): TTyPointF;
    { Polar.pointToCoord: the distance from the centre and the angle, moved
      into a full turn from the angle extent's lesser end (the greater one
      on an inverse axis) }
    procedure PointToCoord(AX, AY: Double; out ARadius, AAngle: Double);
    { RadiusAxis / AngleAxis.pointToData: the axis' own half of pointToData }
    function AxisPointToData(AAxis: TTyAxis; AX, AY: Double): Double;
    { Polar.containPoint: both axes contain their coordinate }
    function ContainXY(AX, AY: Double): Boolean;
    { Polar.getBaseAxis: an ordinal axis, then a time one, then the angle }
    function BaseAxis: TTyAxis;
    function OtherAxis(AAxis: TTyAxis): TTyAxis;
    { 'radius' or 'angle'; nil for anything else }
    function AxisByDim(const ADim: string): TTyAxis;
    { an axis' extent, upstream's getExtent() }
    procedure AxisExtent(AAxis: TTyAxis; out A0, A1: Double);
    { ---- ITyCoordSys ---- }
    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;
    { [radius, angle] in data space }
    function DataToPoint(const AData: array of Double): TTyPointF;
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    function PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): TTyAxis;
    property Index: Integer read FIndex;
    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property CX: Double read FCX;
    property CY: Double read FCY;
    property RadiusAxis: TTyAxis read FRadiusAxis;
    property AngleAxis: TTyAxis read FAngleAxis;
    { upstream's axis.inverse of each -- see the unit header }
    property RadiusInverse: Boolean read FRadiusInverse write FRadiusInverse;
    property AngleInverse: Boolean read FAngleInverse write FAngleInverse;
  end;
  TTyPolarArray = array of TTyPolar;

{ ---- building ---- }

{ polarCreator.create: one polar per polar component (a replaceMerge hole
  is nil), its angle and radius axes the LAST of each family that names it
  (findAxisModel), the axes' types, scales and categories, the angle extent
  from startAngle / endAngle / clockwise / inverse, the centre and the radius
  extent from polar.center and polar.radius on AViewport (resizePolar). A
  polar missing either axis is not built (upstream throws there); its index
  and the family are in ANotes, one entry each as 'polarIndex:mainType'. }
function TyBuildPolars(AOption: TTyChartOption; const AViewport: TTyRectF;
  out AMissing: TTyStringArray): TTyPolarArray;

{ updatePolarScale: each axis' raw extent (no series yet), its nice step --
  the grid's own routine -- and, when the raw extent ran backwards, its
  inverse toggled; then a category angle axis without a band gives up one
  band of its extent so the last category does not sit on the first. }
procedure TyPolarApplyExtents(AOption: TTyChartOption; const APolars: TTyPolarArray);

{ Both axis views of every polar, as AngleAxisView and RadiusAxisView build
  them. AMinorTickLenLogical is the theme's minor tick length where the
  option writes none. }
procedure TyLayoutPolars(const APolars: TTyPolarArray; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorTickLenLogical: Double; AMemory: TTyAxisMemoryStore);

{ ---- the arithmetic, exported for the tests ---- }

{ AngleAxis.calculateCategoryInterval before its cache: one line's height
  (at least 7) over a band's span in degrees, floored; 0 for an axis of one
  category; +Infinity where the band has no span. }
function TyPolarAngleCategoryInterval(ALineHeight, AUnitSpan: Double;
  ASpanLessThanOne: Boolean): Double;
{ fixAngleOverlap: whether a list whose first and last coordinates are a
  full turn apart (within 1e-4) drops its last }
function TyPolarFullTurn(AFirst, ALast: Double): Boolean;
{ getAxisLineShape: the line at AAngle between two radii, from the greater }
function TyPolarRadialLine(APolar: TTyPolar; AR0, AR1, AAngle: Double): TTyPolarLine;
{ graphic.subPixelOptimizeLine, with Math.round }
procedure TyPolarSubPixelLine(var ALine: TTyPolarLine; AWidth: Double);

{ ---- the pointer ---- }
type
  TTyPolarPointerKind = (plpkNone, plpkLine, plpkCircle, plpkSector);
  TTyPolarPointerShape = record
    Kind: TTyPolarPointerKind;
    X1, Y1, X2, Y2: Double;
    CX, CY, R0, R, StartAngle, EndAngle: Double;
  end;

{ PolarAxisPointer's pointerShapeBuilder: a line pointer is a radial line
  across the other axis' extent on the angle axis and a circle on the radius;
  a shadow is a sector a band wide across the radius extent on the angle
  axis, and a ring a band deep (clamped to the extent) on the radius. }
function TyPolarPointerShape(APolar: TTyPolar; AAxis: TTyAxis; ACoord,
  ABandWidth: Double; AShadow: Boolean): TTyPolarPointerShape;
{ calcAxisPointerShadowBandWidth with no series: a category's band (at least
  1), anything else 1 -- in degrees on the angle axis }
function TyPolarPointerBand(AAxis: TTyAxis): Double;
{ getLabelPosition: where the pointer's label hangs and how }
procedure TyPolarPointerLabelAnchor(APolar: TTyPolar; AAxis: TTyAxis; ACoord,
  AMarginPx, ALabelRotateRad: Double; out AX, AY: Double;
  out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);

{ ---- the conversions ---- }

{ Polar.dataToPoint of a JSON value: its first element on the radius axis,
  its second on the angle axis, each through scale.parse; an error where
  upstream indexes a null value }
function TyPolarToPixel(APolar: TTyPolar; AValue: TJSONData): TTyConvertResult;
{ Polar.pointToData of a pixel as ToNumber reads its two elements }
function TyPolarFromPixel(APolar: TTyPolar; AValue: TJSONData): TTyConvertResult;
function TyPolarContainJson(APolar: TTyPolar; APoint: TJSONData): Boolean;

implementation

uses tyControls.AdvChart.JsMath, tyControls.AdvChart.AxisLabels,
  tyControls.AdvChart.AxisName, tyControls.AdvChart.Series,
  tyControls.AdvChart.ZrPath;

const
  cTwoPi = 2 * Pi;

function Radian: Double; inline;
begin
  { Math.PI / 180 }
  Result := Pi / 180;
end;

function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

{ ---- option readers ---- }

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData.JSONType = jtObject) then Result := TJSONObject(AData)
  else Result := nil;
end;

function FindIn(ANode: TJSONObject; const AKey: string): TJSONData;
begin
  if ANode = nil then Exit(nil);
  Result := ANode.Find(AKey);
end;

function BoolIn(ANode: TJSONObject; const AKey: string; ADefault: Boolean): Boolean;
var d: TJSONData;
begin
  Result := ADefault;
  d := FindIn(ANode, AKey);
  if (d <> nil) and (d.JSONType = jtBoolean) then Result := d.AsBoolean;
end;

function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  d := FindIn(ANode, AKey);
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

function StrIn(ANode: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  d := FindIn(ANode, AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

{ a lineStyle width under ANode.AKey, or ADefault }
function LineWidthIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var sub: TJSONObject;
begin
  Result := ADefault;
  sub := ObjOf(FindIn(ObjOf(FindIn(ANode, AKey)), 'lineStyle'));
  if sub <> nil then Result := NumIn(sub, 'width', ADefault);
end;

{ how many colours a split list counts in: a list's length, one for
  anything else written, ADefault where nothing is }
function InkCountIn(ANode: TJSONObject; const AKey, AStyle: string;
  ADefault: Integer): Integer;
var d: TJSONData;
begin
  Result := ADefault;
  d := FindIn(ObjOf(FindIn(ObjOf(FindIn(ANode, AKey)), AStyle)), 'color');
  if d = nil then Exit;
  if d.JSONType = jtArray then Result := d.Count
  else Result := 1;
end;

{ ==================== TTyPolar ==================== }

constructor TTyPolar.Create(AIndex: Integer; ARadiusAxis, AAngleAxis: TTyAxis);
begin
  inherited Create;
  FIndex := AIndex;
  FRadiusAxis := ARadiusAxis;
  FAngleAxis := AAngleAxis;
  FCX := 0;
  FCY := 0;
end;

destructor TTyPolar.Destroy;
begin
  FRadiusAxis.Free;
  FAngleAxis.Free;
  inherited Destroy;
end;

procedure TTyPolar.SetCentre(ACX, ACY: Double);
begin
  FCX := ACX;
  FCY := ACY;
end;

procedure TTyPolar.AxisExtent(AAxis: TTyAxis; out A0, A1: Double);
begin
  { the TTyAxis' own Inverse is never set on a polar axis, so its local
    extent is the extent as written }
  AAxis.LocalExtent(A0, A1);
end;

function TTyPolar.CoordToPoint(ARadius, AAngle: Double): TTyPointF;
var rad: Double;
begin
  rad := AAngle / 180 * Pi;
  Result.X := TyJsCos(rad) * ARadius + FCX;
  { Inverse the y }
  Result.Y := -TyJsSin(rad) * ARadius + FCY;
end;

procedure TTyPolar.PointToCoord(AX, AY: Double; out ARadius, AAngle: Double);
var
  dx, dy, e0, e1, minA, maxA, radian, dir: Double;
  mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    dx := AX - FCX;
    dy := AY - FCY;
    AxisExtent(FAngleAxis, e0, e1);
    minA := Math.Min(e0, e1);
    maxA := Math.Max(e0, e1);
    if IsNan(e0) or IsNan(e1) then
    begin
      minA := NaN;
      maxA := NaN;
    end;
    { Fix fixed extent in polarCreator }
    if FAngleInverse then minA := maxA - 360
    else maxA := minA + 360;
    ARadius := Sqrt(dx * dx + dy * dy);
    dx := dx / ARadius;
    dy := dy / ARadius;
    radian := TyJsAtan2(-dy, dx) / Pi * 180;
    { move to angleExtent }
    if radian < minA then dir := 1 else dir := -1;
    if not (IsNan(radian) or IsInfinite(radian)) and not IsInfinite(minA)
      and not IsInfinite(maxA) then
      while (radian < minA) or (radian > maxA) do
        radian := radian + dir * 360;
    AAngle := radian;
  finally
    UnmaskFP(mask);
  end;
end;

function TTyPolar.AxisPointToData(AAxis: TTyAxis; AX, AY: Double): Double;
var r, a: Double;
begin
  PointToCoord(AX, AY, r, a);
  if AAxis = FRadiusAxis then Result := FRadiusAxis.CoordToData(r)
  else if AAxis = FAngleAxis then Result := FAngleAxis.CoordToData(a)
  else Result := NaN;
end;

{ Axis.contain: between the extent's ends, both included }
function AxisContains(AAxis: TTyAxis; ACoord: Double): Boolean;
var a, b: Double;
begin
  AAxis.LocalExtent(a, b);
  if IsNan(ACoord) then Exit(False);
  Result := (ACoord >= Math.Min(a, b)) and (ACoord <= Math.Max(a, b));
end;

function TTyPolar.ContainXY(AX, AY: Double): Boolean;
var r, a: Double;
begin
  PointToCoord(AX, AY, r, a);
  Result := AxisContains(FRadiusAxis, r) and AxisContains(FAngleAxis, a);
end;

function TTyPolar.BaseAxis: TTyAxis;
begin
  { getAxesByScale('ordinal')[0] || ('time')[0] || the angle: the angle
    first within each kind }
  if FAngleAxis.AxisType = atCategory then Exit(FAngleAxis);
  if FRadiusAxis.AxisType = atCategory then Exit(FRadiusAxis);
  if FAngleAxis.AxisType = atTime then Exit(FAngleAxis);
  if FRadiusAxis.AxisType = atTime then Exit(FRadiusAxis);
  Result := FAngleAxis;
end;

function TTyPolar.OtherAxis(AAxis: TTyAxis): TTyAxis;
begin
  if AAxis = FAngleAxis then Result := FRadiusAxis else Result := FAngleAxis;
end;

function TTyPolar.AxisByDim(const ADim: string): TTyAxis;
begin
  if ADim = TyPolarRadiusDim then Result := FRadiusAxis
  else if ADim = TyPolarAngleDim then Result := FAngleAxis
  else Result := nil;
end;

function TTyPolar.CoordSysName: string;
begin
  Result := TyPolarCoordSysName;
end;

function TTyPolar.DimCount: Integer;
begin
  Result := 2;
end;

function TTyPolar.GetRect: TTyRectF;
var a, b, r: Double;
begin
  { getArea's bounding box: the outer radius round the centre }
  FRadiusAxis.LocalExtent(a, b);
  r := Math.Max(a, b);
  Result := TyRectF(FCX - r, FCY - r, FCX + r, FCY + r);
end;

function TTyPolar.DataToPoint(const AData: array of Double): TTyPointF;
var r, a: Double;
begin
  if Length(AData) < 2 then Exit(TyPointF(NaN, NaN));
  r := FRadiusAxis.DataToCoord(AData[0]);
  a := FAngleAxis.DataToCoord(AData[1]);
  Result := CoordToPoint(r, a);
end;

function TTyPolar.DataToLayout(const AData: array of Double): TTyCoordLayout;
var p: TTyPointF;
begin
  { a polar has no cell: the anchor, collapsed }
  p := DataToPoint(AData);
  Result.Rect := TyRectF(p.X, p.Y, p.X, p.Y);
  Result.ContentRect := Result.Rect;
end;

function TTyPolar.PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
var r, a: Double;
begin
  PointToCoord(APoint.X, APoint.Y, r, a);
  SetLength(AData, 2);
  AData[0] := FRadiusAxis.CoordToData(r);
  AData[1] := FAngleAxis.CoordToData(a);
  Result := True;
end;

function TTyPolar.ContainPoint(const APoint: TTyPointF): Boolean;
begin
  Result := ContainXY(APoint.X, APoint.Y);
end;

function TTyPolar.AxisCount: Integer;
begin
  Result := 2;
end;

function TTyPolar.GetAxis(AIndex: Integer): TTyAxis;
begin
  { getAxes: the radius, then the angle }
  if AIndex = 0 then Result := FRadiusAxis
  else if AIndex = 1 then Result := FAngleAxis
  else Result := nil;
end;

{ ==================== building ==================== }

function TyBuildPolars(AOption: TTyChartOption; const AViewport: TTyRectF;
  out AMissing: TTyStringArray): TTyPolarArray;
var
  n, p, q, cnt, ai, ri: Integer;
  ids: TTyStringArray;
  holes: array of Boolean;
  d, c0, c1, r0d, r1d: TJSONData;
  node, an, rn: TJSONObject;
  ra, aa: TTyAxis;
  polar: TTyPolar;
  u: string;
  w, h, size, start, stop, r0, r1: Double;
  inv: Boolean;
  mask: TFPUExceptionMask;

  { findAxisModel: the last of the family whose polar is this one }
  function FindAxis(const AMainType: string): Integer;
  var k: Integer;
  begin
    Result := -1;
    cnt := AOption.ComponentCount(AMainType);
    for k := 0 to cnt - 1 do
    begin
      node := ObjOf(AOption.ComponentAt(AMainType, k));
      if node = nil then Continue;
      if TyResolveComponentRef(node, 'polarIndex', 'polarId', n, ids, holes) = p then
        Result := k;
    end;
  end;

  procedure Missing(const AMainType: string);
  begin
    SetLength(AMissing, Length(AMissing) + 1);
    AMissing[High(AMissing)] := IntToStr(p) + ':' + AMainType;
  end;

begin
  Result := nil;
  AMissing := nil;
  if AOption = nil then Exit;
  n := AOption.ComponentCount('polar');
  if n = 0 then Exit;
  SetLength(ids, n);
  SetLength(holes, n);
  for p := 0 to n - 1 do
  begin
    d := AOption.ComponentAt('polar', p);
    holes[p] := (d <> nil) and (d.JSONType <> jtObject);
    ids[p] := StrIn(ObjOf(d), 'id');
  end;
  SetLength(Result, n);
  w := AViewport.Right - AViewport.Left;
  h := AViewport.Bottom - AViewport.Top;
  mask := MaskFP;
  try
    for p := 0 to n - 1 do
    begin
      Result[p] := nil;
      if holes[p] then Continue;
      ai := FindAxis('angleAxis');
      ri := FindAxis('radiusAxis');
      if (ai < 0) or (ri < 0) then
      begin
        if ai < 0 then Missing('angleAxis');
        if ri < 0 then Missing('radiusAxis');
        Continue;
      end;
      ra := TyCreateAxis(AOption, 'radiusAxis', ri, TyPolarRadiusDim, True, u);
      aa := TyCreateAxis(AOption, 'angleAxis', ai, TyPolarAngleDim, False, u);
      polar := TTyPolar.Create(p, ra, aa);
      Result[p] := polar;
      node := ObjOf(AOption.ComponentAt('polar', p));
      polar.Id := StrIn(node, 'id');
      polar.Name := StrIn(node, 'name');
      rn := ObjOf(AOption.ComponentAt('radiusAxis', ri));
      an := ObjOf(AOption.ComponentAt('angleAxis', ai));
      { setAxis }
      polar.RadiusInverse := BoolIn(rn, 'inverse', False);
      inv := BoolIn(an, 'inverse', False) <> BoolIn(an, 'clockwise', True);
      polar.AngleInverse := inv;
      start := NumIn(an, 'startAngle', 90);
      d := FindIn(an, 'endAngle');
      if (d <> nil) and (d.JSONType = jtNumber) then stop := d.AsFloat
      else if inv then stop := start + -360
      else stop := start + 360;
      aa.SetPxExtent(start, stop);
      { resizePolar: the centre against the container, the radius against
        half its shorter side }
      d := FindIn(node, 'center');
      c0 := nil;
      c1 := nil;
      if d = nil then
      begin
        polar.SetCentre(TyBoxRawResolve(TyBoxRawStr('50%'), w) + AViewport.Left,
          TyBoxRawResolve(TyBoxRawStr('50%'), h) + AViewport.Top);
      end
      else
      begin
        if (d.JSONType = jtArray) and (d.Count > 0) then c0 := d.Items[0];
        if (d.JSONType = jtArray) and (d.Count > 1) then c1 := d.Items[1];
        polar.SetCentre(TyBoxRawResolve(TyBoxRawOf(c0), w) + AViewport.Left,
          TyBoxRawResolve(TyBoxRawOf(c1), h) + AViewport.Top);
      end;
      size := Math.Min(w, h) / 2;
      d := FindIn(node, 'radius');
      if d = nil then
      begin
        { the model's default, '80%' }
        r0 := TyBoxRawResolve(TyBoxRawNum(0), size);
        r1 := TyBoxRawResolve(TyBoxRawStr('80%'), size);
      end
      else if d.JSONType = jtNull then
      begin
        r0 := TyBoxRawResolve(TyBoxRawNum(0), size);
        r1 := TyBoxRawResolve(TyBoxRawStr('100%'), size);
      end
      else if d.JSONType = jtArray then
      begin
        r0d := nil;
        r1d := nil;
        if d.Count > 0 then r0d := d.Items[0];
        if d.Count > 1 then r1d := d.Items[1];
        r0 := TyBoxRawResolve(TyBoxRawOf(r0d), size);
        r1 := TyBoxRawResolve(TyBoxRawOf(r1d), size);
      end
      else
      begin
        r0 := TyBoxRawResolve(TyBoxRawNum(0), size);
        r1 := TyBoxRawResolve(TyBoxRawOf(d), size);
      end;
      if polar.RadiusInverse then ra.SetPxExtent(r1, r0)
      else ra.SetPxExtent(r0, r1);
    end;
  finally
    UnmaskFP(mask);
  end;
end;

procedure TyPolarApplyExtents(AOption: TTyChartOption; const APolars: TTyPolarArray);
var
  i: Integer;
  p: TTyPolar;
  e0, e1, diff: Double;
  cnt: Integer;
  mask: TFPUExceptionMask;

  { the polar's two axis models default splitNumber themselves: 12 on the
    angle axis, 5 on the radius -- over the time axis' 6 on either }
  function Nice(AAxis: TTyAxis; ADefaultSplit: Double): Boolean;
  var
    node: TJSONObject;
    raw: TTyAxisRawExtent;
  begin
    node := ObjOf(AOption.ComponentAt(AAxis.MainType, AAxis.ComponentIndex));
    { the series on this polar join the raw extent with C4; none yet }
    raw := TyAxisRawExtent(node, AAxis, Infinity, NegInfinity, False);
    TyNiceAxisScale(AOption, AAxis, node, raw, False, nil, NaN, False, False,
      False, Result, ADefaultSplit);
  end;

begin
  for i := 0 to High(APolars) do
  begin
    p := APolars[i];
    if p = nil then Continue;
    if Nice(p.AngleAxis, 12) then p.AngleInverse := not p.AngleInverse;
    if Nice(p.RadiusAxis, 5) then p.RadiusInverse := not p.RadiusInverse;
    { Fix extent of category angle axis }
    if (p.AngleAxis.AxisType = atCategory) and not p.AngleAxis.OnBand
      and (p.AngleAxis.Scale is TTyOrdinalScale) then
    begin
      mask := MaskFP;
      try
        p.AxisExtent(p.AngleAxis, e0, e1);
        cnt := TTyOrdinalScale(p.AngleAxis.Scale).Count;
        diff := 360 / cnt;
        if p.AngleInverse then e1 := e1 + diff else e1 := e1 - diff;
        p.AngleAxis.SetPxExtent(e0, e1);
      finally
        UnmaskFP(mask);
      end;
    end;
  end;
end;

{ ==================== the arithmetic ==================== }

function TyPolarAngleCategoryInterval(ALineHeight, AUnitSpan: Double;
  ASpanLessThanOne: Boolean): Double;
var
  maxH, dh: Double;
  mask: TFPUExceptionMask;
begin
  if ASpanLessThanOne then Exit(0);
  mask := MaskFP;
  try
    maxH := Math.Max(ALineHeight, Double(7));
    if IsNan(ALineHeight) then maxH := NaN;
    dh := maxH / Abs(AUnitSpan);
    { 0/0 is NaN, 1/0 is Infinity }
    if IsNan(dh) then dh := Infinity;
    { Math.floor: an infinity, and a number past the integers, is itself }
    if IsInfinite(dh) or (Abs(dh) >= 4503599627370496.0) then Result := dh
    else Result := Floor64(dh);
    Result := Math.Max(Double(0), Result);
  finally
    UnmaskFP(mask);
  end;
end;

function TyPolarFullTurn(AFirst, ALast: Double): Boolean;
begin
  if IsNan(AFirst) or IsNan(ALast) then Exit(False);
  Result := Abs(Abs(AFirst - ALast) - 360) < 1e-4;
end;

function TyPolarRadialLine(APolar: TTyPolar; AR0, AR1, AAngle: Double): TTyPolarLine;
var
  s, e: TTyPointF;
  t: Double;
begin
  { rExtent[1] > rExtent[0]: from the greater }
  if AR1 > AR0 then
  begin
    t := AR0;
    AR0 := AR1;
    AR1 := t;
  end;
  s := APolar.CoordToPoint(AR0, AAngle);
  e := APolar.CoordToPoint(AR1, AAngle);
  Result := Default(TTyPolarLine);
  Result.X1 := s.X;
  Result.Y1 := s.Y;
  Result.X2 := e.X;
  Result.Y2 := e.Y;
  Result.Value := NaN;
  Result.Drawn := True;
end;

procedure TyPolarSubPixelLine(var ALine: TTyPolarLine; AWidth: Double);
begin
  if IsNan(AWidth) or (AWidth = 0) then Exit;
  if TyJsRound(ALine.X1 * 2) = TyJsRound(ALine.X2 * 2) then
  begin
    ALine.X1 := TyZrSubPixelOptimize(ALine.X1, AWidth, True);
    ALine.X2 := ALine.X1;
  end;
  if TyJsRound(ALine.Y1 * 2) = TyJsRound(ALine.Y2 * 2) then
  begin
    ALine.Y1 := TyZrSubPixelOptimize(ALine.Y1, AWidth, True);
    ALine.Y2 := ALine.Y1;
  end;
end;

{ ==================== the views ==================== }

{ the mark list getTicksCoords gives, in the axis' own coordinates: a
  category axis every interval-th category and its ends, moved onto the
  band edges unless aligned; a custom list; else every major tick }
function TickMarks(AOption: TTyChartOption; AAxis: TTyAxis;
  const ASpec: TTyAxisLayoutSpec; const AFurn: TTyAxisFurniture;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): TTyAxisMarkArray;
var
  node: TJSONObject;
  custom: TTyDoubleArray;
  has: Boolean;
  iv: Double;
  vals: TTyIntegerArray;
  offs: TTyBoolArray;
  ticks: TTyScaleTickArray;
  i, k, n: Integer;
begin
  Result := nil;
  if AAxis.Scale.Blank then Exit;
  node := ObjOf(AOption.ComponentAt(AAxis.MainType, AAxis.ComponentIndex));
  custom := TyCustomValuesOf(ObjOf(FindIn(node, 'axisTick')), AAxis, has);
  if has then
  begin
    SetLength(Result, Length(custom));
    for i := 0 to High(custom) do
    begin
      Result[i] := Default(TTyAxisMark);
      Result[i].Value := custom[i];
      Result[i].Coord := AAxis.DataToLocal(custom[i]);
    end;
    if AAxis.Scale is TTyOrdinalScale then
      TyFixOnBandMarks(Result, AAxis.OnBand, AFurn.AlignWithLabel,
        AAxis.BandWidth, Round(AAxis.Scale.GetExtent.Stop));
  end
  else if AAxis.AxisType = atCategory then
  begin
    n := TyCategoryLabelCount(ASpec);
    if n = 0 then Exit;
    { axisTick.interval, else the labels' }
    if IsNan(AFurn.TickInterval) then
      iv := TyCategoryLabelInterval(ASpec, TyRectF(0, 0, 1, 1), AMeasurer, APPI)
    else
      iv := AFurn.TickInterval;
    TyCategoryBuiltList(ASpec.OrdinalStart, n, iv, vals, offs);
    SetLength(Result, Length(vals));
    for i := 0 to High(vals) do
    begin
      Result[i] := Default(TTyAxisMark);
      Result[i].Value := vals[i];
      Result[i].OffInterval := offs[i];
      Result[i].Coord := AAxis.DataToLocal(vals[i]);
    end;
    TyFixOnBandMarks(Result, AAxis.OnBand, AFurn.AlignWithLabel,
      AAxis.BandWidth, ASpec.OrdinalStart + n - 1);
  end
  else
  begin
    ticks := TyDrawnTicks(AAxis.Scale);
    SetLength(Result, Length(ticks));
    k := 0;
    for i := 0 to High(ticks) do
    begin
      if ticks[i].Level <> 0 then Continue;
      Result[k] := Default(TTyAxisMark);
      Result[k].Value := ticks[i].Value;
      Result[k].Coord := AAxis.DataToLocal(ticks[i].Value);
      Inc(k);
    end;
    SetLength(Result, k);
  end;
  for i := 0 to High(Result) do
  begin
    Result[i].Local := Result[i].Coord;
    Result[i].Drawn := True;
  end;
end;

{ the minor ticks' coordinates (getMinorTicksCoords): none on a category axis }
function MinorCoords(AAxis: TTyAxis): TTyDoubleArray;
var
  ticks: TTyScaleTickArray;
  i, k: Integer;
begin
  Result := nil;
  if (AAxis.AxisType = atCategory) or AAxis.Scale.Blank then Exit;
  ticks := TyDrawnTicks(AAxis.Scale);
  SetLength(Result, Length(ticks));
  k := 0;
  for i := 0 to High(ticks) do
  begin
    if ticks[i].Level = 0 then Continue;
    Result[k] := AAxis.DataToLocal(ticks[i].Value);
    Inc(k);
  end;
  SetLength(Result, k);
end;

{ a point through the axis group's matrix -- none where it needs no local
  transform }
procedure Apply(const M: TTyMat2D; AHas: Boolean; AX, AY: Double;
  out OX, OY: Double);
begin
  if not AHas then
  begin
    OX := AX;
    OY := AY;
    Exit;
  end;
  OX := M[0] * AX + M[2] * AY + M[4];
  OY := M[1] * AX + M[3] * AY + M[5];
end;

procedure LayoutRadius(P: TTyPolar; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorLen: Double; AMemory: TTyAxisMemoryStore);
var
  v: TTyPolarAxisView;
  ax: TTyAxis;
  node: TJSONObject;
  fr: TTyAxisNameFrame;
  axisAngle, e0, e1, a0, a1, len, endCoord, raw, used, w, mw: Double;
  M: TTyMat2D;
  hasM, full: Boolean;
  marks: TTyAxisMarkArray;
  minors: TTyDoubleArray;
  i, k, q, cnt: Integer;
  ln: TTyPolarLine;
  arc: TTyPolarArc;
  geoms: TTyLabelGeomArray;
  rect: TTyRectF;
begin
  v := Default(TTyPolarAxisView);
  ax := P.RadiusAxis;
  node := ObjOf(AOption.ComponentAt(ax.MainType, ax.ComponentIndex));
  v.Shown := ax.Visible;
  v.Blank := ax.Scale.Blank;
  v.Furn := TyAxisFurnitureOf(node, ax, True, True);
  if not v.Shown then
  begin
    P.RadiusView := v;
    Exit;
  end;
  rect := TyRectF(0, 0, 1, 1);
  TyFillAxisLayoutSpec(v.Spec, ax, node, v.Furn, AText, AMeasurer, APPI,
    False, False);
  { AxisBuilder's frame: at the centre, turned by the angle axis' start,
    labels and ticks on the -1 side, the name on the +1; no `inside` }
  P.AxisExtent(P.AngleAxis, a0, a1);
  axisAngle := a0 / 180 * Pi;
  P.AxisExtent(ax, e0, e1);
  fr := Default(TTyAxisNameFrame);
  fr.PosX := P.CX;
  fr.PosY := P.CY;
  fr.Rotation := axisAngle;
  fr.Ext0 := e0;
  fr.Ext1 := e1;
  fr.LabelOffset := 0;
  fr.NameDirection := 1;
  fr.Inverse := P.RadiusInverse;
  v.Spec.Side := asBottom;
  v.Spec.FreeFrame := True;
  v.Spec.LabelDirection := -1;
  v.Spec.TickInside := False;
  v.Spec.LabelInside := False;
  v.Spec.Inverse := P.RadiusInverse;
  v.Spec.NameFrame := fr;
  v.Spec.HasNameFrame := True;
  if v.Blank then v.Spec.ShowLabels := False;
  { the category interval through the axis model's store, as the grid's }
  if (v.Spec.LabelKind = lakCategory) and (v.Spec.ForcedLabelStep = 0)
    and not v.Blank and (TyCategoryLabelCount(v.Spec) >= 2) then
  begin
    raw := TyCategoryLabelInterval(v.Spec, rect, AMeasurer, APPI);
    used := raw;
    if AMemory <> nil then
      used := TyCategoryIntervalHold(AMemory.Find(ax.MainType
        + IntToStr(ax.ComponentIndex), True), raw, TyCategoryLabelCount(v.Spec),
        e0, e1);
    if (not IsNan(used)) and (not IsInfinite(used)) and (used >= 0)
      and (used < MaxInt - 1) then
      v.Spec.ForcedLabelStep := Trunc(used) + 1;
  end;
  v.Spec.LabelStep := TyAxisLabelStep(v.Spec, rect, AMeasurer, APPI);
  if v.Spec.LabelStep < 1 then v.Spec.LabelStep := 1;
  v.Spec.Placements := TyLayoutAxisLabels(v.Spec, rect, AMeasurer, APPI);
  { the name, moved off its own labels }
  if v.Spec.Name <> '' then
  begin
    geoms := TyAxisLabelGeoms(v.Spec, rect, AMeasurer, APPI);
    TySortLabelGeoms(geoms, fr);
    if v.Spec.NameNoMove then geoms := nil;
    v.Spec.NamePlacement := TyLayoutAxisName(v.Spec, fr, 0, geoms, [], 0,
      AMeasurer, APPI);
  end;
  { the blocks where they hang }
  if v.Spec.LabelRt.Needed then
    for i := 0 to High(v.Spec.Placements) do
      if v.Spec.Placements[i].Shown then
        v.Spec.Placements[i].Rt := TyAxisRtPieces(v.Spec, v.Spec.LabelRt,
          v.Spec.Placements[i].Text, v.Spec.FontName, v.Spec.FontSizeLogical,
          v.Spec.FontWeight, v.Spec.HasLabelColour, v.Spec.LabelColour,
          v.Spec.Placements[i].AnchorH, v.Spec.Placements[i].AnchorV, AMeasurer);
  if v.Spec.NameRt.Needed and v.Spec.NamePlacement.Shown then
  begin
    if v.Spec.NameFontSizeLogical > 0 then
      v.Spec.NamePlacement.Rt := TyAxisRtPieces(v.Spec, v.Spec.NameRt,
        v.Spec.NamePlacement.Text, v.Spec.NameFontName, v.Spec.NameFontSizeLogical,
        v.Spec.NameFontWeight, v.Spec.HasNameColour, v.Spec.NameColour,
        v.Spec.NamePlacement.AnchorH, v.Spec.NamePlacement.AnchorV, AMeasurer)
    else
      v.Spec.NamePlacement.Rt := TyAxisRtPieces(v.Spec, v.Spec.NameRt,
        v.Spec.NamePlacement.Text, v.Spec.FontName, v.Spec.FontSizeLogical,
        v.Spec.FontWeight, v.Spec.HasNameColour, v.Spec.NameColour,
        v.Spec.NamePlacement.AnchorH, v.Spec.NamePlacement.AnchorV, AMeasurer);
  end;

  hasM := TyNeedLocal(P.CX, P.CY, axisAngle);
  M := TyMatLocal(P.CX, P.CY, axisAngle);
  { the line, on the pixel grid }
  if v.Furn.ShowLine then
  begin
    v.HasLine := True;
    v.Line := Default(TTyPolarLine);
    Apply(M, hasM, e0, 0, v.Line.X1, v.Line.Y1);
    Apply(M, hasM, e1, 0, v.Line.X2, v.Line.Y2);
    v.Line.Value := NaN;
    v.Line.Drawn := True;
    TyPolarSubPixelLine(v.Line, AxisScaleF(LineWidthIn(node, 'axisLine', 1), APPI));
    v.Spec.Arrows := TyAxisArrows(fr, v.Furn, APPI);
  end;
  marks := TickMarks(AOption, ax, v.Spec, v.Furn, AMeasurer, APPI);
  { the ticks: tickDirection -1, sub-pixel optimised; a tick whose label was
    built and hidden goes with it (syncLabelIgnoreToMajorTicks, by value),
    unless it is on a band edge or the minor ticks are shown }
  if v.Furn.ShowTicks and not v.Blank then
  begin
    len := AxisScaleF(v.Spec.TickLengthLogical, APPI);
    endCoord := -1 * len;
    w := AxisScaleF(LineWidthIn(node, 'axisTick', 1), APPI);
    SetLength(v.Ticks, Length(marks));
    for i := 0 to High(marks) do
    begin
      ln := Default(TTyPolarLine);
      Apply(M, hasM, marks[i].Coord, 0, ln.X1, ln.Y1);
      Apply(M, hasM, marks[i].Coord, endCoord, ln.X2, ln.Y2);
      TyPolarSubPixelLine(ln, w);
      ln.Value := marks[i].Value;
      ln.Drawn := True;
      if (not v.Furn.MinorTickOption) and not marks[i].OnBand then
        for q := 0 to High(v.Spec.Placements) do
          if v.Spec.Placements[q].Built and not v.Spec.Placements[q].Shown
            and (q <= High(v.Spec.TickValues))
            and (v.Spec.TickValues[q] = marks[i].Value) then
          begin
            ln.Drawn := False;
            Break;
          end;
      v.Ticks[i] := ln;
    end;
  end;
  minors := MinorCoords(ax);
  if v.Furn.ShowMinorTick and not v.Blank then
  begin
    if IsNan(v.Furn.MinorTickLengthLogical) then
      len := AxisScaleF(AMinorLen, APPI)
    else
      len := AxisScaleF(v.Furn.MinorTickLengthLogical, APPI);
    endCoord := -1 * len;
    mw := AxisScaleF(LineWidthIn(node, 'minorTick',
      LineWidthIn(node, 'axisTick', 1)), APPI);
    SetLength(v.MinorTicks, Length(minors));
    for i := 0 to High(minors) do
    begin
      ln := Default(TTyPolarLine);
      Apply(M, hasM, minors[i], 0, ln.X1, ln.Y1);
      Apply(M, hasM, minors[i], endCoord, ln.X2, ln.Y2);
      TyPolarSubPixelLine(ln, mw);
      ln.Value := NaN;
      ln.Drawn := True;
      v.MinorTicks[i] := ln;
    end;
  end;
  { the view's own: a circle (an arc on a part turn) per tick, a sector
    ring between two, a circle per minor tick }
  full := Abs(a1 - a0) = 360;
  v.SplitLineInkCount := InkCountIn(node, 'splitLine', 'lineStyle', 1);
  v.SplitAreaInkCount := InkCountIn(node, 'splitArea', 'areaStyle', 2);
  if v.Furn.ShowSplitLine and not v.Blank then
  begin
    SetLength(v.SplitCircles, Length(marks));
    for i := 0 to High(marks) do
    begin
      arc := Default(TTyPolarArc);
      if full then arc.Kind := pakCircle else arc.Kind := pakArc;
      arc.CX := P.CX;
      arc.CY := P.CY;
      { ensure circle radius >= 0 }
      arc.R := Math.Max(marks[i].Coord, Double(0));
      arc.StartAngle := -a0 * Radian;
      arc.EndAngle := -a1 * Radian;
      arc.Clockwise := P.AngleInverse;
      arc.ColourIndex := i mod Math.Max(1, v.SplitLineInkCount);
      arc.Value := marks[i].Value;
      v.SplitCircles[i] := arc;
    end;
  end;
  if v.Furn.ShowSplitArea and not v.Blank and (Length(marks) > 0) then
  begin
    cnt := Length(marks) - 1;
    SetLength(v.SplitAreas, cnt);
    for i := 1 to High(marks) do
    begin
      arc := Default(TTyPolarArc);
      arc.Kind := pakSector;
      arc.CX := P.CX;
      arc.CY := P.CY;
      arc.R0 := marks[i - 1].Coord;
      arc.R := marks[i].Coord;
      arc.StartAngle := 0;
      arc.EndAngle := Pi * 2;
      arc.Clockwise := True;
      arc.ColourIndex := (i - 1) mod Math.Max(1, v.SplitAreaInkCount);
      arc.Value := marks[i - 1].Value;
      v.SplitAreas[i - 1] := arc;
    end;
  end;
  if v.Furn.ShowMinorSplitLine and not v.Blank then
  begin
    SetLength(v.MinorSplitCircles, Length(minors));
    for k := 0 to High(minors) do
    begin
      arc := Default(TTyPolarArc);
      arc.Kind := pakCircle;
      arc.CX := P.CX;
      arc.CY := P.CY;
      arc.R := minors[k];
      arc.Value := NaN;
      v.MinorSplitCircles[k] := arc;
    end;
  end;
  P.RadiusView := v;
end;

procedure LayoutAngle(P: TTyPolar; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorLen: Double; AMemory: TTyAxisMemoryStore);
var
  v: TTyPolarAxisView;
  ax: TTyAxis;
  node: TJSONObject;
  a0, a1, re0, re1, r, rIn, rOut, margin, len, iv, unitSpan, lw, lh, scale, used: Double;
  rId: Integer;
  marks: TTyAxisMarkArray;
  minors: TTyDoubleArray;
  vals: TTyIntegerArray;
  offs: TTyBoolArray;
  i, k, n, cnt, idx: Integer;
  lab: TTyPolarLabel;
  pt: TTyPointF;
  arc: TTyPolarArc;
  ln: TTyPolarLine;
  clockwise: Boolean;
  prev, coord: Double;
  mask: TFPUExceptionMask;

  { the angle's radial extent, index 0 or 1, as upstream indexes it }
  function RAt(AIndex: Integer): Double;
  begin
    if AIndex = 0 then Result := re0 else Result := re1;
  end;

  procedure AddLabel(AIndex: Integer);
  begin
    lab := Default(TTyPolarLabel);
    lab.Value := v.Spec.TickValues[AIndex];
    lab.Text := v.Spec.Labels[AIndex];
    { the coordinate of its tick (getTickValueOutermost) }
    lab.X := ax.DataToLocal(lab.Value);
    SetLength(v.Labels, Length(v.Labels) + 1);
    v.Labels[High(v.Labels)] := lab;
  end;

begin
  v := Default(TTyPolarAxisView);
  ax := P.AngleAxis;
  node := ObjOf(AOption.ComponentAt(ax.MainType, ax.ComponentIndex));
  v.Shown := ax.Visible;
  v.Blank := ax.Scale.Blank;
  v.Furn := TyAxisFurnitureOf(node, ax, True, True);
  if not v.Shown then
  begin
    P.AngleView := v;
    Exit;
  end;
  mask := MaskFP;
  try
    TyFillAxisLayoutSpec(v.Spec, ax, node, v.Furn, AText, AMeasurer, APPI,
      False, False);
    P.AxisExtent(ax, a0, a1);
    P.AxisExtent(P.RadiusAxis, re0, re1);
    if P.RadiusInverse then rId := 0 else rId := 1;
    { THE ANGLE'S OWN CATEGORY INTERVAL: one line's height -- of the first
      category's NUMBER, which is what upstream measures -- over a band's
      span in degrees, held by the axis model's store as long as it is a
      step smaller and the count is within one. Measured in CSS px, so a
      denser screen does not thin the ring. }
    if (v.Spec.LabelKind = lakCategory) and (v.Spec.ForcedLabelStep = 0)
      and not v.Blank and (ax.Scale is TTyOrdinalScale) then
    begin
      n := TTyOrdinalScale(ax.Scale).Count;
      unitSpan := ax.DataToLocal(ax.Scale.GetExtent.Start + 1)
        - ax.DataToLocal(ax.Scale.GetExtent.Start);
      lh := 0;
      if AMeasurer <> nil then
        AMeasurer.MeasureLine(TyJsNumberToString(ax.Scale.GetExtent.Start),
          v.Spec.FontName, v.Spec.FontSizeLogical, v.Spec.FontWeight, lw, lh);
      if APPI > 0 then scale := APPI / 96 else scale := 1;
      iv := TyPolarAngleCategoryInterval(lh / scale, unitSpan,
        ax.Scale.GetExtent.Stop - ax.Scale.GetExtent.Start < 1);
      used := iv;
      if AMemory <> nil then
        { the angle axis' store: no extent check }
        used := TyCategoryIntervalHold(AMemory.Find(ax.MainType
          + IntToStr(ax.ComponentIndex), True), iv, n, 0, 0);
      if (not IsNan(used)) and (not IsInfinite(used)) and (used >= 0)
        and (used < MaxInt - 1) then
        v.Spec.ForcedLabelStep := Trunc(used) + 1
      else
        v.Spec.ForcedLabelStep := MaxInt;
    end;

    { THE LABELS: every interval-th category but not the ends the interval
      missed, or every tick; then the last dropped when it lies a full turn
      from the first }
    if v.Furn.ShowLabels and not v.Blank then
    begin
      n := Length(v.Spec.Labels);
      if (v.Spec.LabelKind = lakCategory) and not v.Spec.CustomLabels then
      begin
        if v.Spec.ForcedLabelStep > 0 then iv := v.Spec.ForcedLabelStep - 1
        else iv := 0;
        if v.Spec.ForcedLabelStep = MaxInt then iv := Infinity;
        TyCategoryBuiltList(v.Spec.OrdinalStart, n, iv, vals, offs);
        for k := 0 to High(vals) do
        begin
          if offs[k] then Continue;
          idx := vals[k] - v.Spec.OrdinalStart;
          if (idx >= 0) and (idx < n) then AddLabel(idx);
        end;
      end
      else
        for k := 0 to n - 1 do AddLabel(k);
      if (Length(v.Labels) > 0)
        and TyPolarFullTurn(v.Labels[0].X, v.Labels[High(v.Labels)].X) then
        SetLength(v.Labels, Length(v.Labels) - 1);
      margin := AText.LabelMarginLogical;
      if not IsNan(v.Furn.LabelMarginLogical) then margin := v.Furn.LabelMarginLogical;
      margin := AxisScaleF(margin, APPI);
      r := RAt(rId);
      for k := 0 to High(v.Labels) do
      begin
        coord := v.Labels[k].X;
        pt := P.CoordToPoint(r + margin, coord);
        v.Labels[k].X := pt.X;
        v.Labels[k].Y := pt.Y;
        if Abs(pt.X - P.CX) / r < 0.3 then v.Labels[k].AnchorH := tahCentre
        else if pt.X > P.CX then v.Labels[k].AnchorH := tahLeft
        else v.Labels[k].AnchorH := tahRight;
        if Abs(pt.Y - P.CY) / r < 0.3 then v.Labels[k].AnchorV := tavMiddle
        else if pt.Y > P.CY then v.Labels[k].AnchorV := tavTop
        else v.Labels[k].AnchorV := tavBottom;
        if v.Spec.LabelRt.Needed then
          v.Labels[k].Rt := TyAxisRtPieces(v.Spec, v.Spec.LabelRt,
            v.Labels[k].Text, v.Spec.FontName, v.Spec.FontSizeLogical,
            v.Spec.FontWeight, v.Spec.HasLabelColour, v.Spec.LabelColour,
            v.Labels[k].AnchorH, v.Labels[k].AnchorV, AMeasurer);
      end;
    end;

    { THE LINE: a circle or an arc round the outer radius, or a ring when the
      inner one is not nought }
    if v.Furn.ShowLine then
    begin
      v.HasLine := True;
      arc := Default(TTyPolarArc);
      arc.CX := P.CX;
      arc.CY := P.CY;
      arc.R := RAt(rId);
      arc.Value := NaN;
      if RAt(1 - rId) = 0 then
      begin
        if Abs(a1 - a0) = 360 then arc.Kind := pakCircle else arc.Kind := pakArc;
        arc.StartAngle := -a0 * Radian;
        arc.EndAngle := -a1 * Radian;
        arc.Clockwise := P.AngleInverse;
      end
      else
      begin
        arc.Kind := pakRing;
        arc.R0 := RAt(1 - rId);
      end;
      v.LineArc := arc;
    end;

    marks := TickMarks(AOption, ax, v.Spec, v.Furn, AMeasurer, APPI);
    if (Length(marks) > 0)
      and TyPolarFullTurn(marks[0].Coord, marks[High(marks)].Coord) then
      SetLength(marks, Length(marks) - 1);
    minors := MinorCoords(ax);
    r := RAt(rId);
    if v.Furn.ShowTicks and not v.Blank then
    begin
      len := AxisScaleF(v.Spec.TickLengthLogical, APPI);
      if v.Furn.TickInside then len := -1 * len;
      SetLength(v.Ticks, Length(marks));
      for i := 0 to High(marks) do
      begin
        v.Ticks[i] := TyPolarRadialLine(P, r, r + len, marks[i].Coord);
        v.Ticks[i].Value := marks[i].Value;
      end;
    end;
    if v.Furn.ShowMinorTick and not v.Blank then
    begin
      if IsNan(v.Furn.MinorTickLengthLogical) then len := AxisScaleF(AMinorLen, APPI)
      else len := AxisScaleF(v.Furn.MinorTickLengthLogical, APPI);
      if v.Furn.TickInside then len := -1 * len;
      SetLength(v.MinorTicks, Length(minors));
      for i := 0 to High(minors) do
        v.MinorTicks[i] := TyPolarRadialLine(P, r, r + len, minors[i]);
    end;
    v.SplitLineInkCount := InkCountIn(node, 'splitLine', 'lineStyle', 1);
    v.SplitAreaInkCount := InkCountIn(node, 'splitArea', 'areaStyle', 2);
    if v.Furn.ShowSplitLine and not v.Blank then
    begin
      SetLength(v.SplitLines, Length(marks));
      for i := 0 to High(marks) do
      begin
        ln := TyPolarRadialLine(P, re0, re1, marks[i].Coord);
        ln.Value := marks[i].Value;
        ln.ColourIndex := i mod Math.Max(1, v.SplitLineInkCount);
        v.SplitLines[i] := ln;
      end;
    end;
    if v.Furn.ShowMinorSplitLine and not v.Blank then
    begin
      SetLength(v.MinorSplitLines, Length(minors));
      for i := 0 to High(minors) do
        v.MinorSplitLines[i] := TyPolarRadialLine(P, re0, re1, minors[i]);
    end;
    if v.Furn.ShowSplitArea and not v.Blank and (Length(marks) > 0) then
    begin
      rIn := Math.Min(re0, re1);
      rOut := Math.Max(re0, re1);
      clockwise := BoolIn(node, 'clockwise', True);
      cnt := Length(marks);
      SetLength(v.SplitAreas, cnt);
      prev := -marks[0].Coord * Radian;
      for i := 1 to cnt do
      begin
        if i = cnt then coord := marks[0].Coord else coord := marks[i].Coord;
        arc := Default(TTyPolarArc);
        arc.Kind := pakSector;
        arc.CX := P.CX;
        arc.CY := P.CY;
        arc.R0 := rIn;
        arc.R := rOut;
        arc.StartAngle := prev;
        arc.EndAngle := -coord * Radian;
        arc.Clockwise := clockwise;
        arc.ColourIndex := (i - 1) mod Math.Max(1, v.SplitAreaInkCount);
        arc.Value := marks[i - 1].Value;
        v.SplitAreas[i - 1] := arc;
        prev := -coord * Radian;
      end;
    end;
  finally
    UnmaskFP(mask);
  end;
  P.AngleView := v;
end;

procedure TyLayoutPolars(const APolars: TTyPolarArray; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorTickLenLogical: Double; AMemory: TTyAxisMemoryStore);
var i: Integer;
begin
  for i := 0 to High(APolars) do
  begin
    if APolars[i] = nil then Continue;
    LayoutRadius(APolars[i], AOption, AMeasurer, APPI, AText,
      AMinorTickLenLogical, AMemory);
    LayoutAngle(APolars[i], AOption, AMeasurer, APPI, AText,
      AMinorTickLenLogical, AMemory);
  end;
end;

{ ==================== the pointer ==================== }

function TyPolarPointerBand(AAxis: TTyAxis): Double;
var w: Double;
begin
  Result := 1;
  if (AAxis = nil) or not (AAxis.Scale is TTyOrdinalScale) then Exit;
  w := AAxis.BandWidth;
  if IsNan(w) or IsInfinite(w) then Exit;
  Result := Math.Max(Double(1), w);
end;

function TyPolarPointerShape(APolar: TTyPolar; AAxis: TTyAxis; ACoord,
  ABandWidth: Double; AShadow: Boolean): TTyPolarPointerShape;
var
  t0, t1, o0, o1: Double;
  p1, p2: TTyPointF;
begin
  Result := Default(TTyPolarPointerShape);
  Result.Kind := plpkNone;
  if (APolar = nil) or (AAxis = nil) or IsNan(ACoord) then Exit;
  APolar.AxisExtent(AAxis, t0, t1);
  APolar.AxisExtent(APolar.OtherAxis(AAxis), o0, o1);
  Result.CX := APolar.CX;
  Result.CY := APolar.CY;
  if not AShadow then
  begin
    if AAxis = APolar.AngleAxis then
    begin
      p1 := APolar.CoordToPoint(o0, ACoord);
      p2 := APolar.CoordToPoint(o1, ACoord);
      Result.Kind := plpkLine;
      Result.X1 := p1.X;
      Result.Y1 := p1.Y;
      Result.X2 := p2.X;
      Result.Y2 := p2.Y;
    end
    else
    begin
      Result.Kind := plpkCircle;
      Result.R := ACoord;
    end;
    Exit;
  end;
  Result.Kind := plpkSector;
  if AAxis = APolar.AngleAxis then
  begin
    { In ECharts the screen y is negative if angle is positive }
    Result.R0 := o0;
    Result.R := o1;
    Result.StartAngle := (-ACoord - ABandWidth / 2) * Radian;
    Result.EndAngle := (-ACoord + ABandWidth / 2) * Radian;
  end
  else
  begin
    Result.R0 := Math.Max(Math.Min(t0, t1), ACoord - ABandWidth / 2);
    Result.R := Math.Min(ACoord + ABandWidth / 2, Math.Max(t0, t1));
    Result.StartAngle := 0;
    Result.EndAngle := Pi * 2;
  end;
end;

procedure TyPolarPointerLabelAnchor(APolar: TTyPolar; AAxis: TTyAxis; ACoord,
  AMarginPx, ALabelRotateRad: Double; out AX, AY: Double;
  out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);
var
  axisAngle, a0, a1, r0, r1, ct, st, y: Double;
  m: array[0..5] of Double;
  pt: TTyPointF;
  mask: TFPUExceptionMask;
begin
  AX := NaN;
  AY := NaN;
  AH := tahCentre;
  AV := tavMiddle;
  if (APolar = nil) or (AAxis = nil) then Exit;
  mask := MaskFP;
  try
    APolar.AxisExtent(APolar.AngleAxis, a0, a1);
    axisAngle := a0 / 180 * Pi;
    APolar.AxisExtent(APolar.RadiusAxis, r0, r1);
    if AAxis = APolar.RadiusAxis then
    begin
      { matrix.rotate(identity, axisAngle), then translate by the centre }
      ct := TyJsCos(axisAngle);
      st := TyJsSin(axisAngle);
      m[0] := ct;
      m[1] := -st;
      m[2] := st;
      m[3] := ct;
      m[4] := 0;
      m[5] := 0;
      m[4] := m[4] + APolar.CX;
      m[5] := m[5] + APolar.CY;
      y := -AMarginPx;
      AX := m[0] * ACoord + m[2] * y + m[4];
      AY := m[1] * ACoord + m[3] * y + m[5];
      TyInnerTextLayout(axisAngle, ALabelRotateRad, -1, AH, AV);
    end
    else
    begin
      pt := APolar.CoordToPoint(r1 + AMarginPx, ACoord);
      AX := pt.X;
      AY := pt.Y;
      if Abs(AX - APolar.CX) / r1 < 0.3 then AH := tahCentre
      else if AX > APolar.CX then AH := tahLeft
      else AH := tahRight;
      if Abs(AY - APolar.CY) / r1 < 0.3 then AV := tavMiddle
      else if AY > APolar.CY then AV := tavTop
      else AV := tavBottom;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

{ ==================== the conversions ==================== }

function TyPolarToPixel(APolar: TTyPolar; AValue: TJSONData): TTyConvertResult;
var
  e0, e1, own0, own1: TJSONData;
  r, a: Double;
  pt: TTyPointF;
  mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  if APolar = nil then Exit;
  { data[0] and data[1]: a null value is indexed, and throws }
  e0 := TyJsonElement(AValue, 0, own0);
  try
    e1 := TyJsonElement(AValue, 1, own1);
    try
      mask := MaskFP;
      try
        r := TyAxisCoordJs(APolar.RadiusAxis, TyAxisParseJson(APolar.RadiusAxis, e0));
        a := TyAxisCoordJs(APolar.AngleAxis, TyAxisParseJson(APolar.AngleAxis, e1));
        pt := APolar.CoordToPoint(r, a);
        Result := TyConvertXY(pt.X, pt.Y);
      finally
        UnmaskFP(mask);
      end;
    finally
      own1.Free;
    end;
  finally
    own0.Free;
  end;
end;

function TyPolarFromPixel(APolar: TTyPolar; AValue: TJSONData): TTyConvertResult;
var
  pt: TTyPointF;
  d: TTyDoubleArray;
  mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  if APolar = nil then Exit;
  pt := TyJsonPoint(AValue);
  mask := MaskFP;
  try
    APolar.PointToData(pt, d);
    Result := TyConvertXY(d[0], d[1]);
  finally
    UnmaskFP(mask);
  end;
end;

function TyPolarContainJson(APolar: TTyPolar; APoint: TJSONData): Boolean;
var
  pt: TTyPointF;
  mask: TFPUExceptionMask;
begin
  Result := False;
  if APolar = nil then Exit;
  pt := TyJsonPoint(APoint);
  mask := MaskFP;
  try
    Result := APolar.ContainXY(pt.X, pt.Y);
  finally
    UnmaskFP(mask);
  end;
end;

end.
