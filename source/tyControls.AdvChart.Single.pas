unit tyControls.AdvChart.Single;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the single axis coordinate system and its axis view.
  [Batch 118, C10]

  UPSTREAM'S coord/single (Single.ts, SingleAxis.ts, singleCreator.ts,
  AxisModel.ts, singleAxisHelper.ts), component/axis/SingleAxisView.ts and
  the shapes of component/axisPointer/SingleAxisPointer.ts, transcribed.

  ONE AXIS IN A BOX. A singleAxis component is its own coordinate system:
  a rect laid out from left / top / right / bottom / width / height (5% on
  every side unless written, merged as mergeLayoutParam merges a box) and
  one axis across it. The axis is the grid's kind of axis -- its extent is
  [0, width] or [0, height], turned round when inverse, mapped onto the
  canvas by the rect's left or top edge, and a vertical one counts up from
  the bottom -- so it is a TTyAxis with the grid's layout extent.

  TWO WORDS THAT DO NOT ALWAYS AGREE. `position` (top, bottom, left, right)
  decides isHorizontal(): which side of the rect the extent is laid along,
  the pointer's dimension and the split lines' direction; `orient`
  (horizontal, vertical) decides dataToPoint's dimension and the axis
  group's turn. They agree on every sane option; where they do not, each
  reader here asks the one upstream asks.

  THE AXIS VIEW IS AN AxisBuilder AXIS -- line, arrows, ticks, labels,
  name -- in a frame at the rect's edge, turned a quarter for a vertical
  orient, its labels, ticks and name on the position's side (axisTick.inside
  and axisLabel.inside turn the first two round), laid out by the grid's
  own routines (TyFillAxisLayoutSpec, FreeFrame and LabelDirection, as the
  polar's radius axis is). The view adds its own split lines across the
  rect -- every one drawn, coloured in turn, sub-pixel optimised -- and
  rectCoordAxisBuildSplitArea's split areas.

  UPSTREAM'S QUIRKS, KEPT. dataToPoint puts the cross coordinate at the
  rect's middle; a vertical containPoint compares the x with the rect's
  y range; the pointer reads dataToPoint(value)[0], so a vertical axis'
  pointer line sits at the rect's centre column whatever the value.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Builder, tyControls.AdvChart.Convert,
  tyControls.AdvChart.Data, tyControls.AdvChart.Series;

const
  { the series' coordinateSystem word and the component's main type }
  TySingleCoordSysName = 'singleAxis';
  { the dimension, upstream's singleDimensions }
  TySingleDim = 'single';

type
  { One straight piece: the line, a tick, a split line. Value is the tick it
    stands for (not a number where it has none); Drawn says whether it is
    drawn (a tick whose label was hidden goes with it); ColourIndex picks
    from the colour list (split lines). }
  TTySingleLine = record
    X1, Y1, X2, Y2: Double;
    Value: Double;
    Drawn: Boolean;
    ColourIndex: Integer;
  end;
  TTySingleLineArray = array of TTySingleLine;

  { One split area: a rect from one tick to the next, the colour of the
    list it takes, the tick it starts at. }
  TTySingleArea = record
    X, Y, W, H: Double;
    Value: Double;
    ColourIndex: Integer;
  end;
  TTySingleAreaArray = array of TTySingleArea;

  { WHAT THE AXIS VIEW DRAWS. The labels, the name and the arrows are in Spec
    (Placements, NamePlacement, Arrows), as a grid axis' are. }
  TTySingleAxisView = record
    Shown: Boolean;
    Blank: Boolean;
    Furn: TTyAxisFurniture;
    Spec: TTyAxisLayoutSpec;
    HasLine: Boolean;
    Line: TTySingleLine;
    Ticks, MinorTicks: TTySingleLineArray;
    SplitLines: TTySingleLineArray;
    SplitAreas: TTySingleAreaArray;
    { the length of the split-line colour list (its colour index's modulus) }
    SplitLineInkCount: Integer;
  end;

  { One single axis. Owns its axis. Non-refcounted, as every coordinate
    system here: the chart owns it. }
  TTySingle = class(TTyNonRefCountedObject, ITyCoordSys)
  private
    FIndex: Integer;
    FId, FName: string;
    FRect: TTyXYWH;
    FAxis: TTyAxis;
    FOrient: string;
    FPosition: string;
    FInverseFlag: Boolean;
  public
    View: TTySingleAxisView;
    { Takes ownership of the axis. }
    constructor Create(AIndex: Integer; AAxis: TTyAxis);
    destructor Destroy; override;
    { SingleAxis.isHorizontal: the position is top or bottom }
    function Horizontal: Boolean;
    { orient === 'horizontal': dataToPoint's dimension is x }
    function OrientHorizontal: Boolean;
    { Single.dataToPoint of a number (upstream's `+val`): the axis'
      coordinate in the orient's dimension, the rect's middle in the other }
    function ValueToPoint(AValue: Double): TTyPointF;
    { Single.pointToData: the axis' value at the orient's coordinate }
    function PointXYToData(AX, AY: Double): Double;
    { Single.containPoint, as upstream writes it -- see the unit header }
    function ContainXY(AX, AY: Double): Boolean;
    { the rect's extent in dimension AIndex (0 x, 1 y): getGlobalExtent }
    procedure GlobalExtent(AIndex: Integer; out A0, A1: Double);
    { ---- ITyCoordSys ---- }
    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;
    { the single dimension's value in AData[0] }
    function DataToPoint(const AData: array of Double): TTyPointF;
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    function PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): TTyAxis;
    property Index: Integer read FIndex;
    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property Rect: TTyXYWH read FRect write FRect;
    property Axis: TTyAxis read FAxis;
    property Orient: string read FOrient write FOrient;
    property Position: string read FPosition write FPosition;
    { upstream's axis.inverse after the scale: the option's, toggled where
      the raw extent ran backwards (the extent itself was laid out before) }
    property InverseFlag: Boolean read FInverseFlag write FInverseFlag;
  end;
  TTySingleArray = array of TTySingle;

{ ---- building ---- }

{ singleCreator.create: one single per singleAxis component (a replaceMerge
  hole is nil), its axis' type, scale and categories, the rect from the box
  on AViewport and the extent along it (resize). }
function TyBuildSingles(AOption: TTyChartOption; const AViewport: TTyRectF): TTySingleArray;
{ [Batch 154] Single.resize again in createBoxLayoutReference's container
  ARef -- a matrix cell or a calendar day: getLayoutRect of the box there
  (not the shared solver: a cell's edges are fractional), then _adjustAxis.
  A cell of no position or no size: the box far off the canvas
  (TyBoxNowhere), as a grid's. }
procedure TySingleResizeIn(AOption: TTyChartOption; ASingle: TTySingle;
  const ARef: TTyXYWH);

{ THE SERIES ON A SINGLE: every binding that resolved to one takes its axis
  -- XAxis and BaseAxis the single's axis, YAxis and ValueAxis nil -- and
  the single itself in Single. }
procedure TyAttachSingleSeries(var ABindings: TTySeriesBindingArray;
  const ASingles: TTySingleArray);

{ Single.update: the axis' raw extent -- the series on it, a dataZoom's
  window -- and its nice step, the grid's own routine; a raw extent that
  ran backwards toggles InverseFlag. }
procedure TySingleApplyExtents(AOption: TTyChartOption; const ASingles: TTySingleArray;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex;
  const AZooms: TTyAxisZoomArray);

{ Every single's axis view, as SingleAxisView builds it. AMinorTickLenLogical
  is the theme's minor tick length where the option writes none, and
  ATickLenLogical the single axis' own tick length (its model's 6). }
procedure TyLayoutSingles(const ASingles: TTySingleArray; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorTickLenLogical, ATickLenLogical: Double; AMemory: TTyAxisMemoryStore);

{ singleAxisHelper.layout's directions: the position's side (top and left
  -1, bottom and right 1), turned round by axisTick.inside (ATick) or
  axisLabel.inside (ALabel) }
function TySingleDirection(ASingle: TTySingle; AOption: TTyChartOption;
  const AWhich: string): Integer;

{ graphic.subPixelOptimizeLine, with Math.round }
procedure TySingleSubPixelLine(var ALine: TTySingleLine; AWidth: Double);

{ ---- the pointer ---- }
type
  TTySinglePointerKind = (spkNone, spkLine, spkRect);
  TTySinglePointerShape = record
    Kind: TTySinglePointerKind;
    { a line's two ends, or a rect's x, y, width and height }
    X1, Y1, X2, Y2: Double;
  end;

{ SingleAxisPointer's pointerShapeBuilder at the pixel APixel
  (dataToPoint(value)[0]): a line across the other extent, or a shadow a
  band wide clamped to this extent }
function TySinglePointerShape(ASingle: TTySingle; APixel, ABandWidth: Double;
  AShadow: Boolean): TTySinglePointerShape;
{ buildCartesianSingleLabelElOption's anchor: the value's coordinate through
  the axis group's matrix, the margin on the labels' side, aligned as
  innerTextLayout aligns an unturned label }
procedure TySinglePointerLabelAnchor(ASingle: TTySingle; AOption: TTyChartOption;
  AValue, AMarginPx: Double; out AX, AY: Double; out AH: TTyTextAnchorH;
  out AV: TTyTextAnchorV);

{ ---- the conversions ---- }

{ Single.dataToPoint of a JSON value: an array's first element, then `+v` }
function TySingleToPixel(ASingle: TTySingle; AValue: TJSONData): TTyConvertResult;
{ Single.pointToData of a pixel: one number, in an array }
function TySingleFromPixel(ASingle: TTySingle; AValue: TJSONData): TTyConvertResult;
{ Single.containPoint of a pixel as ToNumber reads its two elements }
function TySingleContainJson(ASingle: TTySingle; APoint: TJSONData): Boolean;

implementation

uses tyControls.AdvChart.JsMath, tyControls.AdvChart.AxisLabels,
  tyControls.AdvChart.AxisName, tyControls.AdvChart.ZrPath;

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

function StrIn(ANode: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  d := FindIn(ANode, AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

{ a lineStyle width under ANode.AKey, or ADefault }
function LineWidthIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var
  sub: TJSONObject;
  d: TJSONData;
begin
  Result := ADefault;
  sub := ObjOf(FindIn(ObjOf(FindIn(ANode, AKey)), 'lineStyle'));
  if sub = nil then Exit;
  d := sub.Find('width');
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

{ how many colours a split list counts in: a list's length, one for anything
  else written, ADefault where nothing is }
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

{ JavaScript truth of ANode.AKey.inside }
function InsideIn(ANode: TJSONObject; const AKey: string): Boolean;
var d: TJSONData;
begin
  d := FindIn(ObjOf(FindIn(ANode, AKey)), 'inside');
  if d = nil then Exit(False);
  case d.JSONType of
    jtBoolean: Result := d.AsBoolean;
    jtNumber: Result := (not IsNan(d.AsFloat)) and (d.AsFloat <> 0);
    jtString: Result := d.AsString <> '';
    jtArray, jtObject: Result := True;
  else
    Result := False;
  end;
end;

{ ==================== TTySingle ==================== }

constructor TTySingle.Create(AIndex: Integer; AAxis: TTyAxis);
begin
  inherited Create;
  FIndex := AIndex;
  FAxis := AAxis;
  FOrient := 'horizontal';
  FPosition := 'bottom';
end;

destructor TTySingle.Destroy;
begin
  FAxis.Free;
  inherited Destroy;
end;

function TTySingle.Horizontal: Boolean;
begin
  Result := (FPosition = 'top') or (FPosition = 'bottom');
end;

function TTySingle.OrientHorizontal: Boolean;
begin
  Result := FOrient = 'horizontal';
end;

function TTySingle.ValueToPoint(AValue: Double): TTyPointF;
var
  c: Double;
  mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    { axis.toGlobalCoord(axis.dataToCoord(+val)), a log axis' nought an
      infinite pixel as Math.log gives it }
    c := TyAxisCoordJs(FAxis, AValue);
    if OrientHorizontal then
    begin
      Result.X := c;
      Result.Y := FRect.Y + FRect.H / 2;
    end
    else
    begin
      Result.Y := c;
      Result.X := FRect.X + FRect.W / 2;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

function TTySingle.PointXYToData(AX, AY: Double): Double;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    if OrientHorizontal then Result := FAxis.CoordToData(AX)
    else Result := FAxis.CoordToData(AY);
  finally
    UnmaskFP(mask);
  end;
end;

{ Axis.contain: between the extent's ends, both included }
function AxisContains(AAxis: TTyAxis; ACoord: Double): Boolean;
var a, b: Double;
begin
  AAxis.LocalExtent(a, b);
  if IsNan(ACoord) then Exit(False);
  Result := (ACoord >= Math.Min(a, b)) and (ACoord <= Math.Max(a, b));
end;

function TTySingle.ContainXY(AX, AY: Double): Boolean;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    if FOrient = 'horizontal' then
      Result := AxisContains(FAxis, FAxis.ToLocal(AX))
        and (AY >= FRect.Y) and (AY <= FRect.Y + FRect.H)
    else
      { the x against the rect's y range: upstream's }
      Result := AxisContains(FAxis, FAxis.ToLocal(AY))
        and (AX >= FRect.Y) and (AX <= FRect.Y + FRect.H);
  finally
    UnmaskFP(mask);
  end;
end;

procedure TTySingle.GlobalExtent(AIndex: Integer; out A0, A1: Double);
begin
  if AIndex = 0 then
  begin
    A0 := FRect.X;
    A1 := FRect.X + FRect.W;
  end
  else
  begin
    A0 := FRect.Y;
    A1 := FRect.Y + FRect.H;
  end;
end;

function TTySingle.CoordSysName: string;
begin
  Result := TySingleCoordSysName;
end;

function TTySingle.DimCount: Integer;
begin
  Result := 1;
end;

function TTySingle.GetRect: TTyRectF;
begin
  Result := TyRectOfXYWH(FRect);
end;

function TTySingle.DataToPoint(const AData: array of Double): TTyPointF;
begin
  if Length(AData) < 1 then Exit(TyPointF(NaN, NaN));
  Result := ValueToPoint(AData[0]);
end;

function TTySingle.DataToLayout(const AData: array of Double): TTyCoordLayout;
var p: TTyPointF;
begin
  { a single has no cell: the anchor, collapsed }
  p := DataToPoint(AData);
  Result.Rect := TyRectF(p.X, p.Y, p.X, p.Y);
  Result.ContentRect := Result.Rect;
end;

function TTySingle.PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
begin
  SetLength(AData, 1);
  AData[0] := PointXYToData(APoint.X, APoint.Y);
  Result := True;
end;

function TTySingle.ContainPoint(const APoint: TTyPointF): Boolean;
begin
  Result := ContainXY(APoint.X, APoint.Y);
end;

function TTySingle.AxisCount: Integer;
begin
  Result := 1;
end;

function TTySingle.GetAxis(AIndex: Integer): TTyAxis;
begin
  if AIndex = 0 then Result := FAxis else Result := nil;
end;

{ ==================== building ==================== }

{ resize's box params: 5% on every side by default, merged as
  mergeLayoutParam merges the option's own over them, raw; a key left null
  or undefined read from the option root (getBoxLayoutParams' getShallow)
  [F4c] }
function SingleBoxRaw(ANode: TJSONObject; ARoot: TJSONData): TTyRawBox;
begin
  Result := Default(TTyRawBox);
  Result.Left := TyBoxRawStr('5%');
  Result.Top := TyBoxRawStr('5%');
  Result.Right := TyBoxRawStr('5%');
  Result.Bottom := TyBoxRawStr('5%');
  Result := TyMergeBoxLayout(ANode, Result);
  TyBoxClimbRoot(Result, ARoot);
end;

{ _adjustAxis: [0, width] along x, [0, height] along y -- by the position's
  isHorizontal -- the base the rect's left or top }
procedure SingleAdjustAxis(S: TTySingle);
begin
  if S.Horizontal then S.Axis.SetLayoutExtent(S.Rect.X, S.Rect.W, False)
  else S.Axis.SetLayoutExtent(S.Rect.Y, S.Rect.H, True);
end;

procedure TySingleResizeIn(AOption: TTyChartOption; ASingle: TTySingle;
  const ARef: TTyXYWH);
var
  node: TJSONObject;
  box: TTyXYWH;
begin
  if (AOption = nil) or (ASingle = nil) then Exit;
  node := ObjOf(AOption.ComponentAt(TySingleCoordSysName, ASingle.Index));
  box := TyGetLayoutRect(SingleBoxRaw(node, AOption.Root), ARef.X, ARef.Y,
    ARef.W, ARef.H, []);
  if not TyXYWHIsValid(box) then
    box := TyXYWH(TyBoxNowhere, TyBoxNowhere, TyBoxNowhereSize, TyBoxNowhereSize);
  ASingle.Rect := box;
  SingleAdjustAxis(ASingle);
end;

function TyBuildSingles(AOption: TTyChartOption; const AViewport: TTyRectF): TTySingleArray;
var
  n, p: Integer;
  d: TJSONData;
  node: TJSONObject;
  ax: TTyAxis;
  s: TTySingle;
  u, pos: string;
  box: TTyXYWH;
  vertical: Boolean;
begin
  Result := nil;
  if AOption = nil then Exit;
  n := AOption.ComponentCount(TySingleCoordSysName);
  if n = 0 then Exit;
  SetLength(Result, n);
  for p := 0 to n - 1 do
  begin
    Result[p] := nil;
    d := AOption.ComponentAt(TySingleCoordSysName, p);
    { a replaceMerge hole keeps its index and builds nothing }
    if (d <> nil) and (d.JSONType <> jtObject) then Continue;
    node := ObjOf(d);
    { the position: SingleAxis' `position || 'bottom'` }
    pos := StrIn(node, 'position');
    if pos = '' then pos := 'bottom';
    vertical := not ((pos = 'top') or (pos = 'bottom'));
    ax := TyCreateAxis(AOption, TySingleCoordSysName, p, TySingleDim, not vertical, u);
    s := TTySingle.Create(p, ax);
    Result[p] := s;
    s.Id := StrIn(node, 'id');
    s.Name := StrIn(node, 'name');
    s.Position := pos;
    s.Orient := 'horizontal';
    d := FindIn(node, 'orient');
    if (d <> nil) and (d.JSONType = jtString) then s.Orient := d.AsString;
    if pos = 'top' then ax.Side := asTop
    else if pos = 'left' then ax.Side := asLeft
    else if pos = 'right' then ax.Side := asRight
    else ax.Side := asBottom;
    ax.Inverse := BoolIn(node, 'inverse', False);
    s.InverseFlag := ax.Inverse;
    { resize: getLayoutRect of the box params, 5% on every side by default,
      merged as mergeLayoutParam merges the option's own over them }
    { [F4c] getLayoutRect itself: the keywords and the flip }
    box := TyGetLayoutRect(SingleBoxRaw(node, AOption.Root), AViewport.Left,
      AViewport.Top, AViewport.Right - AViewport.Left,
      AViewport.Bottom - AViewport.Top, []);
    s.Rect := box;
    { _adjustAxis: [0, width] along x, [0, height] along y -- by the
      position's isHorizontal -- the base the rect's left or top }
    if s.Horizontal then ax.SetLayoutExtent(box.X, box.W, False)
    else ax.SetLayoutExtent(box.Y, box.H, True);
  end;
end;

procedure TyAttachSingleSeries(var ABindings: TTySeriesBindingArray;
  const ASingles: TTySingleArray);
var
  i: Integer;
  s: TTySingle;
begin
  for i := 0 to High(ABindings) do
  begin
    if not ABindings[i].Resolved then Continue;
    if ABindings[i].CoordSysName <> TySingleCoordSysName then Continue;
    if (ABindings[i].SingleIndex < 0) or (ABindings[i].SingleIndex > High(ASingles)) then Continue;
    s := ASingles[ABindings[i].SingleIndex];
    if s = nil then Continue;
    ABindings[i].Single := s;
    ABindings[i].XAxis := s.Axis;
    ABindings[i].YAxis := nil;
    { Single.getBaseAxis: its one axis }
    ABindings[i].BaseAxis := s.Axis;
    ABindings[i].ValueAxis := nil;
  end;
end;

procedure TySingleApplyExtents(AOption: TTyChartOption; const ASingles: TTySingleArray;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex;
  const AZooms: TTyAxisZoomArray);
var
  i, k, zi: Integer;
  s: TTySingle;
  ax: TTyAxis;
  node: TJSONObject;
  raw: TTyAxisRawExtent;
  any, fixLo, fixHi, toggle: Boolean;
begin
  for i := 0 to High(ASingles) do
  begin
    s := ASingles[i];
    if s = nil then Continue;
    ax := s.Axis;
    node := ObjOf(AOption.ComponentAt(ax.MainType, ax.ComponentIndex));
    fixLo := False;
    fixHi := False;
    zi := -1;
    for k := 0 to High(AZooms) do
      if AZooms[k].Axis = ax then zi := k;
    if zi >= 0 then
    begin
      { a dataZoom's window, its pinned ends fixed }
      raw := AZooms[zi].Raw;
      any := AZooms[zi].Any;
      if not IsNan(AZooms[zi].ZoomLo) then
      begin
        raw.Lo := AZooms[zi].ZoomLo;
        raw.FixLo := True;
        fixLo := True;
      end;
      if not IsNan(AZooms[zi].ZoomHi) then
      begin
        raw.Hi := AZooms[zi].ZoomHi;
        raw.FixHi := True;
        fixHi := True;
      end;
    end
    else if AIndex <> nil then
      raw := TyAxisNoZoomExtent(AOption, ABindings, AStores, AStacks, AIndex,
        ax, ax.MainType, any)
    else
    begin
      raw := TyAxisRawExtent(node, ax, Infinity, NegInfinity, False);
      any := False;
    end;
    { the type's own splitNumber: a single axis' model writes none }
    TyNiceAxisScale(AOption, ax, node, raw, any, nil, NaN, fixLo, fixHi,
      False, toggle);
    if toggle then s.InverseFlag := not s.InverseFlag;
  end;
end;

function TySingleDirection(ASingle: TTySingle; AOption: TTyChartOption;
  const AWhich: string): Integer;
var node: TJSONObject;
begin
  { directionMap: top -1, bottom 1, right 1, left -1 }
  if (ASingle.Position = 'top') or (ASingle.Position = 'left') then Result := -1
  else Result := 1;
  if AWhich = '' then Exit;
  node := ObjOf(AOption.ComponentAt(ASingle.Axis.MainType, ASingle.Axis.ComponentIndex));
  if InsideIn(node, AWhich) then Result := -Result;
end;

procedure TySingleSubPixelLine(var ALine: TTySingleLine; AWidth: Double);
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

{ ==================== the view ==================== }

{ the frame AxisBuilder is given: layout.position and layout.rotation }
function FrameOf(S: TTySingle; AOption: TTyChartOption): TTyAxisNameFrame;
var
  e0, e1: Double;
  r: TTyXYWH;
begin
  Result := Default(TTyAxisNameFrame);
  r := S.Rect;
  { [orient vertical ? the left or right edge : the rect's left,
     orient horizontal ? the top or bottom edge : the rect's bottom] --
    a position the orient does not know is not a number }
  if S.Orient = 'vertical' then
  begin
    if S.Position = 'left' then Result.PosX := r.X
    else if S.Position = 'right' then Result.PosX := r.X + r.W
    else Result.PosX := NaN;
  end
  else
    Result.PosX := r.X;
  if S.Orient = 'horizontal' then
  begin
    if S.Position = 'top' then Result.PosY := r.Y
    else if S.Position = 'bottom' then Result.PosY := r.Y + r.H
    else Result.PosY := NaN;
  end
  else
    Result.PosY := r.Y + r.H;
  if S.Orient = 'horizontal' then Result.Rotation := 0
  else if S.Orient = 'vertical' then Result.Rotation := Pi / 2 * 1
  else Result.Rotation := NaN;
  S.Axis.LocalExtent(e0, e1);
  Result.Ext0 := e0;
  Result.Ext1 := e1;
  Result.LabelOffset := 0;
  Result.NameDirection := TySingleDirection(S, AOption, '');
  Result.Inverse := S.InverseFlag;
end;

{ the mark list getTicksCoords gives for a tick model, in the axis' own
  coordinates: a custom list; a category axis every interval-th category
  (the model's interval, else the labels') and its ends, moved onto the
  band edges unless aligned; else every major tick }
function TickMarks(AOption: TTyChartOption; AAxis: TTyAxis;
  const ASpec: TTyAxisLayoutSpec; AOptInterval: Double; AAlign: Boolean;
  ALabelInterval: Double; ALineTicks: Boolean = False): TTyAxisMarkArray;
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
  { the TICK model's customValues whoever asks (createAxisTicks) }
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
      TyFixOnBandMarks(Result, AAxis.OnBand, AAlign,
        AAxis.BandWidth, Round(AAxis.Scale.GetExtent.Stop));
  end
  else if AAxis.AxisType = atCategory then
  begin
    n := TyCategoryLabelCount(ASpec);
    if n = 0 then Exit;
    if IsNan(AOptInterval) then iv := ALabelInterval else iv := AOptInterval;
    TyCategoryBuiltList(ASpec.OrdinalStart, n, iv, vals, offs);
    SetLength(Result, Length(vals));
    for i := 0 to High(vals) do
    begin
      Result[i] := Default(TTyAxisMark);
      Result[i].Value := vals[i];
      Result[i].OffInterval := offs[i];
      Result[i].Coord := AAxis.DataToLocal(vals[i]);
    end;
    TyFixOnBandMarks(Result, AAxis.OnBand, AAlign, AAxis.BandWidth,
      ASpec.OrdinalStart + n - 1);
  end
  else
  begin
    { THE SPLIT LINES' AND AREAS' TICKS on an axis with breaks: no break end,
      the normal ones pruned but for the extent's two ends (breakTicks
      'none', pruneByBreak 'preserve_extent_bound') [F4a] }
    if ALineTicks and (AAxis.Scale.BreakMapper <> nil) then
      ticks := TyDrawnTicksOpt(AAxis.Scale, TyTicksOpt(tbmNone, tpmPreserveExtentBound))
    else
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

procedure LayoutBody(S: TTySingle; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorLen, ATickLen: Double; AMemory: TTyAxisMemoryStore);
var
  v: TTySingleAxisView;
  ax: TTyAxis;
  node: TJSONObject;
  fr: TTyAxisNameFrame;
  len, endCoord, raw, used, w, mw, labelIv, c, prev: Double;
  M: TTyMat2D;
  hasM: Boolean;
  marks, lineMarks, areaMarks: TTyAxisMarkArray;
  minors: TTyDoubleArray;
  i, q, cnt, tickDir: Integer;
  ln: TTySingleLine;
  area: TTySingleArea;
  geoms: TTyLabelGeomArray;
  rect: TTyRectF;
  r: TTyXYWH;
  mem: PTyAxisMemory;
  mask: TFPUExceptionMask;
begin
  v := Default(TTySingleAxisView);
  ax := S.Axis;
  node := ObjOf(AOption.ComponentAt(ax.MainType, ax.ComponentIndex));
  v.Shown := ax.Visible;
  v.Blank := ax.Scale.Blank;
  v.Furn := TyAxisFurnitureOf(node, ax, True, True, True);
  if not v.Shown then
  begin
    S.View := v;
    Exit;
  end;
  rect := TyRectF(0, 0, 1, 1);
  { layout.labelRotate: negated on a top axis }
  TyFillAxisLayoutSpec(v.Spec, ax, node, v.Furn, AText, AMeasurer, APPI,
    S.Position = 'top', False);
  { the model's tick length where the option writes none }
  if IsNan(v.Furn.TickLengthLogical) then v.Spec.TickLengthLogical := ATickLen;
  fr := FrameOf(S, AOption);
  v.Spec.FreeFrame := True;
  v.Spec.LabelDirection := TySingleDirection(S, AOption, 'axisLabel');
  v.Spec.TickInside := False;
  v.Spec.LabelInside := False;
  v.Spec.Inverse := S.InverseFlag;
  v.Spec.NameFrame := fr;
  v.Spec.HasNameFrame := True;
  if v.Blank then v.Spec.ShowLabels := False;
  { the category interval through the axis model's store, as the grid's }
  labelIv := NaN;
  if (v.Spec.LabelKind = lakCategory) and not v.Blank
    and (TyCategoryLabelCount(v.Spec) >= 2) then
  begin
    raw := TyCategoryLabelInterval(v.Spec, rect, AMeasurer, APPI);
    used := raw;
    if AMemory <> nil then
      used := TyCategoryIntervalHold(AMemory.Find(ax.MainType
        + IntToStr(ax.ComponentIndex), True), raw, TyCategoryLabelCount(v.Spec),
        fr.Ext0, fr.Ext1);
    labelIv := used;
    if (v.Spec.ForcedLabelStep = 0) and (not IsNan(used)) and (not IsInfinite(used))
      and (used >= 0) and (used < MaxInt - 1) then
      v.Spec.ForcedLabelStep := Trunc(used) + 1;
  end
  else if (v.Spec.LabelKind = lakCategory) and not v.Blank then
    labelIv := 0;
  { a written label interval is the ticks' 'auto' too }
  if (v.Spec.LabelKind = lakCategory) and (v.Furn.LabelStep > 0) then
    labelIv := v.Furn.LabelStep - 1;
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

  mask := MaskFP;
  try
    hasM := TyNeedLocal(fr.PosX, fr.PosY, fr.Rotation);
    M := TyMatLocal(fr.PosX, fr.PosY, fr.Rotation);
    { the line, on the pixel grid }
    if v.Furn.ShowLine then
    begin
      v.HasLine := True;
      v.Line := Default(TTySingleLine);
      Apply(M, hasM, fr.Ext0, 0, v.Line.X1, v.Line.Y1);
      Apply(M, hasM, fr.Ext1, 0, v.Line.X2, v.Line.Y2);
      v.Line.Value := NaN;
      v.Line.Drawn := True;
      TySingleSubPixelLine(v.Line, AxisScaleF(LineWidthIn(node, 'axisLine', 1), APPI));
      v.Spec.Arrows := TyAxisArrows(fr, v.Furn, APPI);
      { cut at the breaks (axisLine.breakLine) [F4a] }
      TyAxisBreakLineOf(v.Spec, ax, AOption,
        AxisScaleF(LineWidthIn(node, 'axisLine', 1), APPI));
    end;
    marks := TickMarks(AOption, ax, v.Spec, v.Furn.TickInterval,
      v.Furn.AlignWithLabel, labelIv);
    { the ticks: tickDirection, sub-pixel optimised; a tick whose label was
      built and hidden goes with it (syncLabelIgnoreToMajorTicks, by value),
      unless it is on a band edge or the minor ticks are shown }
    tickDir := TySingleDirection(S, AOption, 'axisTick');
    if v.Furn.ShowTicks and not v.Blank then
    begin
      len := AxisScaleF(v.Spec.TickLengthLogical, APPI);
      endCoord := tickDir * len;
      w := AxisScaleF(LineWidthIn(node, 'axisTick', 1), APPI);
      SetLength(v.Ticks, Length(marks));
      for i := 0 to High(marks) do
      begin
        ln := Default(TTySingleLine);
        Apply(M, hasM, marks[i].Coord, 0, ln.X1, ln.Y1);
        Apply(M, hasM, marks[i].Coord, endCoord, ln.X2, ln.Y2);
        TySingleSubPixelLine(ln, w);
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
      endCoord := tickDir * len;
      mw := AxisScaleF(LineWidthIn(node, 'minorTick',
        LineWidthIn(node, 'axisTick', 1)), APPI);
      SetLength(v.MinorTicks, Length(minors));
      for i := 0 to High(minors) do
      begin
        ln := Default(TTySingleLine);
        Apply(M, hasM, minors[i], 0, ln.X1, ln.Y1);
        Apply(M, hasM, minors[i], endCoord, ln.X2, ln.Y2);
        TySingleSubPixelLine(ln, mw);
        ln.Value := NaN;
        ln.Drawn := True;
        v.MinorTicks[i] := ln;
      end;
    end;
    { THE VIEW'S OWN SPLIT LINES: one across the rect per split-line tick,
      every one drawn, the colour list taken in turn, on the pixel grid }
    r := S.Rect;
    v.SplitLineInkCount := InkCountIn(node, 'splitLine', 'lineStyle', 1);
    if v.Furn.ShowSplitLine and not v.Blank then
    begin
      lineMarks := TickMarks(AOption, ax, v.Spec, v.Furn.SplitLineInterval,
        v.Furn.SplitLineAlign, labelIv, True);
      w := AxisScaleF(LineWidthIn(node, 'splitLine', 1), APPI);
      SetLength(v.SplitLines, Length(lineMarks));
      for i := 0 to High(lineMarks) do
      begin
        c := ax.ToGlobal(lineMarks[i].Coord);
        ln := Default(TTySingleLine);
        if S.Horizontal then
        begin
          ln.X1 := c;
          ln.Y1 := r.Y;
          ln.X2 := c;
          ln.Y2 := r.Y + r.H;
        end
        else
        begin
          ln.X1 := r.X;
          ln.Y1 := c;
          ln.X2 := r.X + r.W;
          ln.Y2 := c;
        end;
        TySingleSubPixelLine(ln, w);
        ln.Value := lineMarks[i].Value;
        ln.Drawn := True;
        ln.ColourIndex := i mod Math.Max(1, v.SplitLineInkCount);
        v.SplitLines[i] := ln;
      end;
    end;
    { rectCoordAxisBuildSplitArea: a rect from each split-area tick to the
      next, the colours taken from the last render's by tick value }
    if v.Furn.ShowSplitArea and not v.Blank then
    begin
      areaMarks := TickMarks(AOption, ax, v.Spec, v.Furn.SplitAreaInterval,
        v.Furn.SplitAreaAlign, labelIv, True);
      if Length(areaMarks) > 0 then
      begin
        cnt := v.Furn.SplitAreaInkCount;
        if Length(v.Furn.SplitAreaInks) = 0 then cnt := 2;
        mem := nil;
        if AMemory <> nil then
          mem := AMemory.Find(ax.MainType + IntToStr(ax.ComponentIndex), True);
        TySplitAreaColours(areaMarks, cnt, mem);
        prev := ax.ToGlobal(areaMarks[0].Coord);
        SetLength(v.SplitAreas, Length(areaMarks) - 1);
        for i := 1 to High(areaMarks) do
        begin
          c := ax.ToGlobal(areaMarks[i].Coord);
          area := Default(TTySingleArea);
          if S.Horizontal then
          begin
            area.X := prev;
            area.Y := r.Y;
            area.W := c - area.X;
            area.H := r.H;
            prev := area.X + area.W;
          end
          else
          begin
            area.X := r.X;
            area.Y := prev;
            area.W := r.W;
            area.H := c - area.Y;
            prev := area.Y + area.H;
          end;
          area.Value := areaMarks[i - 1].Value;
          area.ColourIndex := areaMarks[i - 1].ColourIndex;
          v.SplitAreas[i - 1] := area;
        end;
      end;
    end;
    { THE BREAK AREAS across the single's rect (SingleAxisView's breakArea:
      rectCoordBuildBreakAxis into the view's group) [F4a] }
    if not v.Blank then
      TyLayoutAxisBreakAreas(v.Spec, ax, S.Rect, AOption, AMemory);
  finally
    UnmaskFP(mask);
  end;
  S.View := v;
end;

{ ONE VIEW UNDER MASKED TRAPS: a frame of no position (a vertical orient at
  the default bottom) puts every label at not-a-number, and upstream's
  comparisons of such boxes are simply false }
procedure LayoutOne(S: TTySingle; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorLen, ATickLen: Double; AMemory: TTyAxisMemoryStore);
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    LayoutBody(S, AOption, AMeasurer, APPI, AText, AMinorLen, ATickLen, AMemory);
  finally
    UnmaskFP(mask);
  end;
end;

procedure TyLayoutSingles(const ASingles: TTySingleArray; AOption: TTyChartOption;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; const AText: TTyAxisTextStyle;
  AMinorTickLenLogical, ATickLenLogical: Double; AMemory: TTyAxisMemoryStore);
var i: Integer;
begin
  if AOption = nil then Exit;
  for i := 0 to High(ASingles) do
    if ASingles[i] <> nil then
      LayoutOne(ASingles[i], AOption, AMeasurer, APPI, AText,
        AMinorTickLenLogical, ATickLenLogical, AMemory);
end;

{ ==================== the pointer ==================== }

function TySinglePointerShape(ASingle: TTySingle; APixel, ABandWidth: Double;
  AShadow: Boolean): TTySinglePointerShape;
var
  d: Integer;
  t0, t1, o0, o1, lo, hi, span: Double;
  mask: TFPUExceptionMask;
begin
  Result := Default(TTySinglePointerShape);
  if ASingle = nil then Exit;
  { getPointDimIndex: the position's isHorizontal }
  if ASingle.Horizontal then d := 0 else d := 1;
  ASingle.GlobalExtent(d, t0, t1);
  ASingle.GlobalExtent(1 - d, o0, o1);
  mask := MaskFP;
  try
    if not AShadow then
    begin
      Result.Kind := spkLine;
      { makeLineShape([px, other0], [px, other1], d) }
      if d = 0 then
      begin
        Result.X1 := APixel;
        Result.Y1 := o0;
        Result.X2 := APixel;
        Result.Y2 := o1;
      end
      else
      begin
        Result.X1 := o0;
        Result.Y1 := APixel;
        Result.X2 := o1;
        Result.Y2 := APixel;
      end;
      Exit;
    end;
    Result.Kind := spkRect;
    span := o1 - o0;
    { calcAxisPointerShadowEnds: [max(min end, px - bw/2), min(px + bw/2,
      max end)] }
    lo := Math.Max(Math.Min(t0, t1), APixel - ABandWidth / 2);
    if IsNan(APixel) or IsNan(ABandWidth) then lo := NaN;
    hi := Math.Min(APixel + ABandWidth / 2, Math.Max(t0, t1));
    if IsNan(APixel) or IsNan(ABandWidth) then hi := NaN;
    { makeRectShape([min, other0], [max - min, span], d) }
    if d = 0 then
    begin
      Result.X1 := lo;
      Result.Y1 := o0;
      Result.X2 := hi - lo;
      Result.Y2 := span;
    end
    else
    begin
      Result.X1 := o0;
      Result.Y1 := lo;
      Result.X2 := span;
      Result.Y2 := hi - lo;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

procedure TySinglePointerLabelAnchor(ASingle: TTySingle; AOption: TTyChartOption;
  AValue, AMarginPx: Double; out AX, AY: Double; out AH: TTyTextAnchorH;
  out AV: TTyTextAnchorV);
var
  fr: TTyAxisNameFrame;
  M: TTyMat2D;
  c, t: Double;
  dir: Integer;
  mask: TFPUExceptionMask;
begin
  AX := NaN;
  AY := NaN;
  AH := tahCentre;
  AV := tavMiddle;
  if ASingle = nil then Exit;
  fr := FrameOf(ASingle, AOption);
  { layout(axisModel): the label direction with axisLabel.inside's turn }
  dir := TySingleDirection(ASingle, AOption, 'axisLabel');
  mask := MaskFP;
  try
    { getTransformedPosition: rotate, then translate to the position, over
      [axis.dataToCoord(value), labelOffset + labelDirection * margin] }
    c := ASingle.Axis.DataToLocal(AValue);
    t := 0 + dir * AMarginPx;
    M := TyMatLocal(fr.PosX, fr.PosY, fr.Rotation);
    AX := M[0] * c + M[2] * t + M[4];
    AY := M[1] * c + M[3] * t + M[5];
    TyInnerTextLayout(fr.Rotation, 0, dir, AH, AV);
  finally
    UnmaskFP(mask);
  end;
end;

{ ==================== the conversions ==================== }

function TySingleToPixel(ASingle: TTySingle; AValue: TJSONData): TTyConvertResult;
var
  v: TJSONData;
  own: TJSONData;
  p: TTyPointF;
  mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  if ASingle = nil then Exit;
  { `if (val instanceof Array) val = val[0]`, then `+val`: a null value is
    nought here, never indexed }
  own := nil;
  v := AValue;
  try
    if TyJsonIsArray(AValue) then v := TyJsonElement(AValue, 0, own);
    mask := MaskFP;
    try
      p := ASingle.ValueToPoint(TyJsonToNumber(v));
      Result := TyConvertXY(p.X, p.Y);
    finally
      UnmaskFP(mask);
    end;
  finally
    own.Free;
  end;
end;

function TySingleFromPixel(ASingle: TTySingle; AValue: TJSONData): TTyConvertResult;
var
  e, own: TJSONData;
  idx: Integer;
  mask: TFPUExceptionMask;
begin
  Result := TyConvertNone;
  if ASingle = nil then Exit;
  { point[orient === 'horizontal' ? 0 : 1]: a null pixel is indexed, and
    throws }
  if ASingle.OrientHorizontal then idx := 0 else idx := 1;
  e := TyJsonElement(AValue, idx, own);
  try
    mask := MaskFP;
    try
      Result.Kind := cvkArray;
      SetLength(Result.Values, 1);
      Result.Values[0] := ASingle.Axis.CoordToData(TyJsonToNumber(e));
    finally
      UnmaskFP(mask);
    end;
  finally
    own.Free;
  end;
end;

function TySingleContainJson(ASingle: TTySingle; APoint: TJSONData): Boolean;
var
  pt: TTyPointF;
begin
  Result := False;
  if ASingle = nil then Exit;
  pt := TyJsonPoint(APoint);
  Result := ASingle.ContainXY(pt.X, pt.Y);
end;

end.
