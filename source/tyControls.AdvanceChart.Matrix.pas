unit tyControls.AdvanceChart.Matrix;
{$mode objfpc}{$H+}
{ The matrix: a coordinate system of header trees, and the component that
  draws it. ECharts 6.1's coord/matrix (MatrixModel, MatrixDim, Matrix,
  matrixCoordHelper) and component/matrix/MatrixView, part one (D12 MX1,
  batch 145).

  TWO HEADER TREES, x across the top and y down the left. Each leaf is a
  column (a row); a parent spans its leaves; a tree that is shallower in one
  branch stretches its leaf down (across) to the body. The leaves are the
  LAYOUT UNITS along their own direction, and the other tree's LEVELS are
  the units in front of them: along x, first the y tree's levels (the row
  headers' columns), then the x leaves. A unit is sized by a leaf's `size`
  or a level's `levelSize` (px, or a percentage of the matrix), the rest
  share what is left equally, and the last one reaches the far edge unless
  every unit was sized and room is left over.

  A LOCATOR is an integer along one direction: 0.. the body's columns (the
  leaves), -1, -2, .. the header's levels counted from the body outwards.
  An ORDINAL names a header cell: the leaves first, in locator order, then
  the parents. A value placed on the matrix is an ordinal (a name parsed by
  the dimension's category list, or a number rounded) -- a parent covers
  its leaves -- or, when no cell has that ordinal and it is negative, the
  other tree's level at that locator.

  PART ONE: the model, the trees and their layout, the view (cells, the
  background and the border, the dividers, the cell labels with their
  overflow area and clip), and one value per dimension through dataToLayout
  and dataToPoint.

  PART TWO (D12 MX2, batch 147): the whole positioning algebra -- a RANGE
  on either direction (`[[a, b], y]`, a parent and a range mixed, `[x1, x2,
  x3]` read as its two ends), CLAMPING (none / all / body / corner, a value
  that names nothing then covering the whole row or column), pointToData --
  and the cells' interaction (silent, triggerEvent, cursor, the tooltip),
  rotated labels and rich labels laid out in the overflow area.

  PART THREE (D12 MX3, batch 149): the body's and the corner's own cells
  (MatrixBodyCorner) -- `body.data` / `corner.data` items, each located by
  its `coord` (a range, `coordClamp` keeping it to the body or the corner),
  a later item taking a cell whole, a cell's `value` its label -- and
  MERGED CELLS: an item with `mergeCells` unites with every earlier merge
  it meets, a merge whose top-left moved handing a copy of its option the
  union, dataToLayout expanding into a merge unless `ignoreMergeCells`;
  a cell's gradient fill and a label's named formatter.

  PURE: SysUtils, Math, fpjson and the AdvanceChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option,
  tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Layout,
  tyControls.AdvanceChart.Coord, tyControls.AdvanceChart.Paint,
  tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Color;

const
  TyMatrixCoordSysName = 'matrix';
  { the store's three dimensions (Matrix.getDimensionsInfo) }
  TyMatrixXDim = 'x';
  TyMatrixYDim = 'y';
  TyMatrixValueDim = 'value';
  { MatrixView's z2 }
  TyMatrixZ2Background = 0;
  TyMatrixZ2OuterBorder = 99;
  TyMatrixZ2BodyNormal = 25;
  TyMatrixZ2BodySpecial = 100;
  TyMatrixZ2DimNormal = 50;
  TyMatrixZ2DimSpecial = 125;

type
  TTyMatrixCellKind = (tmkLeaf, tmkNonLeaf);

  { A header cell (MatrixDimensionCell). Id and Span by direction: Id[the
    tree's own direction] is its first leaf, Id[the other] its level less
    the level count (negative); Span[own] its leaf count, Span[other] 1, or
    for a leaf the levels down to the body. XY / WH: a leaf's unit along its
    own direction, a parent's span of units. Rect: the cell, both ways. }
  TTyMatrixCell = record
    Kind: TTyMatrixCellKind;
    Ordinal, Level, FirstLeaf: Integer;
    Id, Span: array[0..1] of Integer;
    XY, WH: Double;
    Rect: TTyXYWH;
    { the option value after the unique renaming: what is drawn, and the
      name the cell is found by }
    Value: string;
    { the cell's own option object, nil for a plain string or null }
    Node: TJSONObject;
  end;

  { A tree level (MatrixDimensionLevelInfo): a unit across the other
    direction. Node: `levels[i]` when it is an object. }
  TTyMatrixLevel = record
    XY, WH: Double;
    Node: TJSONObject;
  end;

  { MatrixClampOption: none (0, anything falsy), all (anything truthy but
    the two below), body (2), corner (3) [Batch 147] }
  TTyMatrixClamp = (mclNone, mclAll, mclBody, mclCorner);

  { matrixXYLocatorRange: per direction the first and the last locator a
    coord covers; NaN where it names nothing [Batch 147] }
  TTyMatrixLocRange = array[0..1, 0..1] of Double;

  { One header tree (MatrixDim). }
  TTyMatrixDim = class
  private
    FDimIdx: Integer;
    FNode: TJSONObject;
    FCells: array of TTyMatrixCell;
    FLevels: array of TTyMatrixLevel;
    FLeaves: Integer;
    FMeta: TTyOrdinalMeta;
    FShow: Boolean;
    FCollect: Boolean;
    procedure InitByData(AData: TJSONArray);
    procedure InitLevels(ACount: Integer);
    function GetCell(AIndex: Integer): TTyMatrixCell;
    function GetLevel(AIndex: Integer): TTyMatrixLevel;
  public
    { ADimIdx 0 for x, 1 for y; ANode the option's x / y (anything else is
      an empty object: no data, so the tree collects from its series) }
    constructor Create(ADimIdx: Integer; ANode: TJSONData);
    destructor Destroy; override;
    { A COLLECTING TREE (no `data`, no `length`) takes its leaves from the
      categories its series' stores collected into Meta: call once the
      stores are filled. Each is a leaf at level 0, its value the category
      as written. A tree with data ignores it. }
    procedure TakeCollected;
    { getLocatorCount: the leaves along the tree's own direction, the
      levels across it }
    function LocatorCount(ADimIdx: Integer): Integer;
    { getUnitLayoutInfo: the leaf (own direction) or the level (across) at
      ALocator, as its XY and WH; False when there is none }
    function UnitOf(ADimIdx, ALocator: Integer; out AXY, AWH: Double): Boolean;
    { getCell by an ordinal: the value rounded half up, -1 when no cell has
      it (NaN, negative, past the end) }
    function CellIndexOf(AValue: Double): Integer;
    function CellCount: Integer;
    function LevelCount: Integer;
    property Cells[AIndex: Integer]: TTyMatrixCell read GetCell;
    property Levels[AIndex: Integer]: TTyMatrixLevel read GetLevel;
    property LeafCount: Integer read FLeaves;
    property DimIdx: Integer read FDimIdx;
    property Node: TJSONObject read FNode;
    { the category list a series on this tree parses its names with --
      owned here, borrowed by the stores }
    property Meta: TTyOrdinalMeta read FMeta;
    property Show: Boolean read FShow;
    property Collect: Boolean read FCollect;
  end;

  { WHAT A DRAWN CELL ANSWERS THE POINTER WITH [Batch 147]: createMatrixCell's
    eventData and setTooltipConfig. Target 'x' / 'y' / 'body' / 'corner'; Loc
    the locator pair (a merged cell's top-left); HasText the cell has a
    textValue (a header cell, or a body or corner cell whose item wrote a
    `value` [Batch 149]), Value it as String(), TipName the text after the
    label's formatter (the tooltip's itemName), HasName / Name the label's
    text as drawn (eventData.name: none when the label is not shown). }
  TTyMatrixCellInfo = record
    Target: string;
    Loc: array[0..1] of Integer;
    HasText: Boolean;
    Value, TipName: string;
    HasName: Boolean;
    Name: string;
  end;

  { A BODY OR CORNER CELL THE OPTION NAMED (MatrixBodyCornerCell) [Batch
    149], at its locator pair X, Y. Option the item that covers it last, or
    a copy the map owns (a merge whose top-left moved: Copied, its coord
    nulled); Src that item's index in `data`, -1 for none. A MERGE's
    top-left cell is its Owner: Span its width and height in cells, Loc the
    locator range it stands for -- wider than Span when the merge grew and
    its top-left stayed, as upstream keeps it --, SpanRect where it is
    drawn. InSpanOf: the owner of a merged cell (the owner itself), -1. }
  TTyMatrixBCCell = record
    X, Y: Integer;
    Option: TJSONObject;
    Src: Integer;
    Copied: Boolean;
    Owner: Boolean;
    InSpanOf: Integer;
    HasSpan: Boolean;
    Span: array[0..1] of Integer;
    Loc: TTyMatrixLocRange;
    SpanRect: TTyXYWH;
  end;

  { THE SPARSE CELL MAP of a body or a corner (MatrixBodyCorner) [Batch 149]:
    only the cells an item reached, in the order they were first reached
    (upstream's HashMap order); the merges' owners in the order they were
    settled (its _cellMergeOwnerList). }
  TTyMatrixBodyCorner = class
  private
    FCells: array of TTyMatrixBCCell;
    FCount: Integer;
    FSlots: array of Integer;
    FOwners: array of Integer;
    FOwnerN: Integer;
    FCopies: array of TJSONObject;
    procedure Grow;
    function Ensure(AX, AY: Integer): Integer;
    procedure AddOwner(ACell: Integer);
    function Keep(AObj: TJSONObject): TJSONObject;
    procedure Clear;
  public
    destructor Destroy; override;
    { the cell at a locator pair, -1 where no item reached }
    function Find(AX, AY: Integer): Integer;
    function Count: Integer;
    function Cell(AIndex: Integer): TTyMatrixBCCell;
    function OwnerCount: Integer;
    { the AIndex-th merge's top-left cell, an index into the map }
    function Owner(AIndex: Integer): Integer;
  end;

  { One matrix component. Built from the option before the series' stores
    (they borrow its category lists), laid out on the canvas with Resize. }
  TTyMatrix = class(TTyNonRefCountedObject, ITyCoordSys)
  private
    FNode: TJSONObject;
    FIndex: Integer;
    FDims: array[0..1] of TTyMatrixDim;
    { the body's (0) and the corner's (1) cell maps, built on first use
      after the trees have their leaves [Batch 149] }
    FBC: array[0..1] of TTyMatrixBodyCorner;
    FBCReady: Boolean;
    FBox: TTyRawBox;
    FRect: TTyXYWH;
    FScale: Double;
    FZ: Integer;
    FValid: Boolean;
    FCellInfos: array of TTyMatrixCellInfo;
    FCellInfoN: Integer;
    procedure LayOutUnits(ADimIdx: Integer);
    procedure LayOutRest(ADimIdx: Integer);
    procedure RectOneDim(var R: TTyXYWH; ADimIdx, AId, ASpan: Integer);
    function UnitAt(ADimIdx, ALocator: Integer; out AXY, AWH: Double): Boolean;
    function GetDim(AIndex: Integer): TTyMatrixDim;
    { coordDataToAllCellLevelLayout as locators: the header cell AValue
      names (its first locator and its span along ADimIdx), else -- a
      negative number -- the other tree's level at round(AValue) }
    function CellLayoutOf(ADimIdx: Integer; AValue: Double; out ALoc, ASpan: Integer): Boolean;
    { pointToDataOneDimPrepareCtx: where APoint lies along ADimIdx (0 the
      body, 1 the corner or the header, 2 outside) and the coordinate, clamped }
    procedure PointArea(ADimIdx: Integer; const APoint: TTyPointF; AClamp: TTyMatrixClamp;
      out AArea: Integer; var ACoord: Double);
    { MatrixBodyCorner._ensureCellMap's fillCellMap for AKind (0 the body,
      1 the corner) [Batch 149] }
    procedure BuildCellMap(AKind: Integer);
    procedure EnsureCellMaps;
    procedure LayOutSpans;
    { expandRangeByCellMerge: a single cell in a merge is that merge's
      range; anything else grows by every merge it meets, again until none }
    procedure ExpandByMerge(AKind: Integer; var ALoc: TTyMatrixLocRange);
  public
    constructor Create(AOption: TTyChartOption; AIndex: Integer);
    destructor Destroy; override;
    { _resize: the box on the canvas (getLayoutRect, no margin), then the
      units along x and y, then every header cell's rect }
    procedure Resize(const AContainer: TTyRectF; APPI: Integer);
    { ONE VALUE ON ONE DIRECTION, as dataToLayout places it: the cell the
      ordinal names (a parent: its leaves) or the level a negative locator
      names, as an XY and a WH; NaN both when it names nothing }
    function Locate(ADimIdx: Integer; AValue: Double; out AXY, AWH: Double): Boolean;
    { dataToLayout's rect as upstream holds it: x, y, width, height }
    procedure DataToLayoutXYWH(AX, AY: Double; out ARect: TTyXYWH);
    { parseCoordRangeOptionOnOneDim: the locators AParts covers along
      ADimIdx -- its first and (two or more) its last part, each a header
      cell (a parent: its whole span) or a level; a part that names nothing
      makes both NaN, which a clamp then widens to the whole row or column
      (body: the leaves only; corner: the levels only) and every clamp
      confines. No parts at all (an empty array) is nothing. }
    procedure RangeOneDim(ADimIdx: Integer; const AParts: array of Double;
      AClamp: TTyMatrixClamp; out ALo, AHi: Double);
    { DATATOLAYOUT IN FULL: each direction's parts (one for a single value,
      the array's elements for a range) to the locator range, grown to the
      merged cells it meets unless AIgnoreMerge (`ignoreMergeCells`; the
      body's merges are skipped under the corner clamp, the corner's under
      the body clamp) [Batch 149], then the rect from the units at its two
      ends; NaN on a direction that names nothing }
    procedure DataToLayoutRange(const AX, AY: array of Double; AClamp: TTyMatrixClamp;
      out ARect: TTyXYWH; out ALoc: TTyMatrixLocRange; AIgnoreMerge: Boolean = False);
    { dataToPoint: the centre of that rect }
    function DataToPointRange(const AX, AY: array of Double; AClamp: TTyMatrixClamp): TTyPointF;
    { POINTTODATA: per direction the leaf's locator (the body), the level's
      negative locator (the corner), or -- the point in one header with the
      other direction in the body -- the header cell's ORDINAL there and its
      level's locator across; NaN outside. AClamp first pulls a coordinate
      outside back to the nearest edge (body / corner: of that area only). }
    procedure PointToDataClamp(const APoint: TTyPointF; AClamp: TTyMatrixClamp;
      out AX, AY: Double);
    { A COORD AS AN OPTION WRITES IT, to the number the store would hold: a
      string through the tree's category list (NaN when unknown), a number
      as it is, anything else NaN. For callers holding raw JSON. }
    function ParseCoord(ADimIdx: Integer; AValue: TJSONData): Double;
    { One direction of a coord as an option writes it: an array's elements
      each parsed (an empty array is no parts), anything else one part }
    function ParseCoordParts(ADimIdx: Integer; AValue: TJSONData): TTyDoubleArray;
    { ---- ITyCoordSys: data is [x, y], ordinals or locators ---- }
    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;
    function DataToPoint(const AData: array of Double): TTyPointF;
    { Rect and ContentRect alike: a matrix cell has no content inset }
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    { pointToData with no clamp: [x, y], either NaN [Batch 147] }
    function PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
    { the rect contains the point, edges included }
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): TTyAxis;
    property Dims[AIndex: Integer]: TTyMatrixDim read GetDim;
    property Node: TJSONObject read FNode;
    property Index: Integer read FIndex;
    property Rect: TTyXYWH read FRect;
    property Box: TTyRawBox read FBox;
    property Z: Integer read FZ;
    property Valid: Boolean read FValid;
    { the cells the last TyBuildMatrix drew, by the serial their elements'
      datum carries (ctkMatrix) [Batch 147] }
    function CellInfoCount: Integer;
    function CellInfo(AIndex: Integer): TTyMatrixCellInfo;
    { matrix.triggerEvent (its own key, false by default) }
    function TriggerEvent: Boolean;
    { matrix.tooltip as written (nil when not an object) }
    function TooltipNode: TJSONObject;
    { the body's (0) or the corner's (1) cell map [Batch 149] }
    function CellMap(AKind: Integer): TTyMatrixBodyCorner;
  end;

  { Resolved ink: the control asks the theme, this unit never does.
    Upstream's tokens: a cell border borderTint, a divider border, the
    outer border axisLine, a label secondary. }
  TTyMatrixInk = record
    CellBorder: TTyChartColor;
    Divider: TTyChartColor;
    OuterBorder: TTyChartColor;
    LabelColour: TTyChartColor;
  end;

{ parsePositionSizeOption: a trimmed string ending in `%` a percentage of
  ABase, another string parseFloat, a number itself, a boolean 0 or 1,
  anything else NaN }
function TyMatrixSizeOf(AData: TJSONData; ABase: Double): Double;
{ An option's `clamp` as MatrixClampOption reads it: falsy none, 2 body,
  3 corner, anything else truthy all [Batch 147] }
function TyMatrixClampOf(AData: TJSONData): TTyMatrixClamp;
{ `opt && opt.clamp`: an opt object's clamp, none for anything else }
function TyMatrixClampOfOpt(AOpt: TJSONData): TTyMatrixClamp;
{ `opt && opt.ignoreMergeCells`, truthy [Batch 149] }
function TyMatrixIgnoreMergeOfOpt(AOpt: TJSONData): Boolean;
{ dataToLayout of a coord as JSON writes it [Batch 147]: anything but an
  array names nothing (NaN everywhere, a clamp notwithstanding); an array's
  element 0 is x and 1 is y, each one value or a range (an element that is
  not there is one part that names nothing); merged cells expand it unless
  AIgnoreMerge [Batch 149] }
procedure TyMatrixLayoutJson(AMatrix: TTyMatrix; AData: TJSONData; AClamp: TTyMatrixClamp;
  out ARect: TTyXYWH; out ALoc: TTyMatrixLocRange; AIgnoreMerge: Boolean = False);
{ The picture of one matrix (MatrixView.render), into AList at the matrix's
  z: the header cells (x, then y), the body cells, the corner cells, the
  background, the outer border, the two dividers. A cell label is its own
  element right after its cell, clipped to the cell inside its border. A
  body or corner cell in another's merge is not drawn; a merge is drawn as
  its spanRect [Batch 149]. }
function TyBuildMatrix(AMatrix: TTyMatrix; const AInk: TTyMatrixInk;
  const AGlobal: TTyRtGlobal; const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AList: TTyPaintList): Integer;

implementation

uses Classes, tyControls.AdvanceChart.Scale, tyControls.AdvanceChart.Calendar,
  tyControls.AdvanceChart.RichStyle, tyControls.AdvanceChart.GfxEl,
  tyControls.AdvanceChart.AnimAxis, tyControls.AdvanceChart.JsMath,
  tyControls.AdvanceChart.Handlers;

{ ==================== small readers ==================== }

function ObjIn(ANode: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d is TJSONObject then Result := TJSONObject(d);
end;

function JNull(A: TJSONData): Boolean; inline;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

{ Model.get over a chain: the first node whose value is not null }
function ChainGet(const AChain: array of TJSONObject; const AKey: string): TJSONData;
var i: Integer;
begin
  for i := 0 to High(AChain) do
    if AChain[i] <> nil then
    begin
      Result := AChain[i].Find(AKey);
      if not JNull(Result) then Exit;
    end;
  Result := nil;
end;

{ JavaScript truthiness of an option value }
function Truthy(A: TJSONData): Boolean;
begin
  if JNull(A) then Exit(False);
  case A.JSONType of
    jtBoolean: Result := A.AsBoolean;
    jtNumber: Result := (A.AsFloat <> 0) and not IsNan(A.AsFloat);
    jtString: Result := A.AsString <> '';
  else
    Result := True;
  end;
end;

function StrOf(A: TJSONData): string;
begin
  if (A <> nil) and (A.JSONType = jtString) then Result := A.AsString
  else Result := '';
end;

{ String(v) of an option value, as JavaScript prints it: an array's
  elements joined by commas (null and undefined empty), an object
  '[object Object]' [Batch 149] }
function JsStringOf(A: TJSONData): string;
var i: Integer;
begin
  if A = nil then Exit('undefined');
  case A.JSONType of
    jtNull: Result := 'null';
    jtString: Result := A.AsString;
    jtBoolean: if A.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := TyJsNumberToString(A.AsFloat);
    jtArray:
      begin
        Result := '';
        for i := 0 to A.Count - 1 do
        begin
          if i > 0 then Result := Result + ',';
          if not JNull(A.Items[i]) then Result := Result + JsStringOf(A.Items[i]);
        end;
      end;
  else
    Result := '[object Object]';
  end;
end;

function NumberOr(A: TJSONData; ADefault: Double): Double;
begin
  if (A <> nil) and (A.JSONType = jtNumber) then Result := A.AsFloat
  else Result := ADefault;
end;

function TyMatrixSizeOf(AData: TJSONData; ABase: Double): Double;
var s: string;
begin
  Result := NaN;
  if JNull(AData) then Exit;
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtString:
      begin
        s := TyJsTrim(AData.AsString);
        if (s <> '') and (s[Length(s)] = '%') then
          Result := TyJsParseFloat(AData.AsString) / 100 * ABase + 0
        else
          Result := TyJsParseFloat(AData.AsString);
      end;
  end;
end;

function TyMatrixClampOf(AData: TJSONData): TTyMatrixClamp;
begin
  if not Truthy(AData) then Exit(mclNone);
  if AData.JSONType = jtNumber then
  begin
    if AData.AsFloat = 2 then Exit(mclBody);
    if AData.AsFloat = 3 then Exit(mclCorner);
  end;
  Result := mclAll;
end;

function TyMatrixClampOfOpt(AOpt: TJSONData): TTyMatrixClamp;
begin
  if AOpt is TJSONObject then Result := TyMatrixClampOf(TJSONObject(AOpt).Find('clamp'))
  else Result := mclNone;
end;

function TyMatrixIgnoreMergeOfOpt(AOpt: TJSONData): Boolean;
begin
  Result := (AOpt is TJSONObject) and Truthy(TJSONObject(AOpt).Find('ignoreMergeCells'));
end;

{ -0 by its sign bit }
function NegZero(A: Double): Boolean; inline;
begin
  Result := (A = 0) and (PInt64(@A)^ < 0);
end;

{ Math.max / Math.min of two: NaN wins, +0 is above -0 }
function JMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if (A = 0) and (B = 0) then
  begin
    if NegZero(A) then Exit(B);
    Exit(A);
  end;
  if A >= B then Result := A else Result := B;
end;

function JMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if (A = 0) and (B = 0) then
  begin
    if NegZero(A) then Exit(A);
    Exit(B);
  end;
  if A <= B then Result := A else Result := B;
end;

{ locatorRangeIntersectOneDim: the two ranges meet; a NaN meets nothing }
function Meets1(A0, A1, B0, B1: Double): Boolean; inline;
begin
  Result := not (IsNan(A0) or IsNan(A1) or IsNan(B0) or IsNan(B1))
    and (A1 >= B0) and (A0 <= B1);
end;

{ expandXYLocatorRangeIfIntersect: ALoc grown to cover AOther when the two
  meet on both directions }
function ExpandIfMeets(var ALoc: TTyMatrixLocRange; const AOther: TTyMatrixLocRange): Boolean;
begin
  Result := Meets1(ALoc[0][0], ALoc[0][1], AOther[0][0], AOther[0][1])
    and Meets1(ALoc[1][0], ALoc[1][1], AOther[1][0], AOther[1][1]);
  if not Result then Exit;
  ALoc[0][0] := JMin(ALoc[0][0], AOther[0][0]);
  ALoc[0][1] := JMax(ALoc[0][1], AOther[0][1]);
  ALoc[1][0] := JMin(ALoc[1][0], AOther[1][0]);
  ALoc[1][1] := JMax(ALoc[1][1], AOther[1][1]);
end;

{ confineSize: Math.max(Math.min(n, limit), 0) -- NaN stays NaN, -0 is 0 }
function Confine(AN, ALimit: Double): Double;
begin
  if IsNan(AN) or IsNan(ALimit) then Exit(NaN);
  Result := AN;
  if ALimit < Result then Result := ALimit;
  if not (Result > 0) then Result := 0;
end;

{ ==================== TTyMatrixDim ==================== }

const
  { A `length` past this is no tree at all, and a body of more cells than
    the other is not drawn: one number in an option must not make a
    hundred million rectangles. }
  cMaxLength = 100000;
  cMaxBodyCells = 250000;
  { THE CELL MAP'S BOUNDS [Batch 149]: the `data` items read, the steps the
    merges may take uniting (each meets every earlier one), the cells the
    items may write -- one `coordClamp` item must not fill ten billion }
  cMaxCellItems = 250000;
  cMaxMergeWork = 50000000;
  cMaxCellWrites = 1000000;

constructor TTyMatrixDim.Create(ADimIdx: Integer; ANode: TJSONData);
var
  d, len: TJSONData;
  n, i: Integer;
  arr: TJSONArray;
begin
  inherited Create;
  FDimIdx := ADimIdx;
  if ANode is TJSONObject then FNode := TJSONObject(ANode) else FNode := nil;
  FMeta := TTyOrdinalMeta.Create;
  { shouldShow: !!show, true by default (the defaults are merged into the
    option; a written null is false) }
  FShow := True;
  if FNode <> nil then
  begin
    d := FNode.Find('show');
    if d <> nil then FShow := Truthy(d);
  end;
  d := nil;
  len := nil;
  if FNode <> nil then
  begin
    d := FNode.Find('data');
    len := FNode.Find('length');
  end;
  if JNull(d) then d := nil;
  if (d <> nil) and not (d is TJSONArray) then
  begin
    { not an array: an empty one }
    arr := TJSONArray.Create;
    try
      InitByData(arr);
    finally
      arr.Free;
    end;
  end
  else if d <> nil then
    InitByData(TJSONArray(d))
  else if not JNull(len) then
  begin
    { `length` nulls }
    n := 0;
    if (len.JSONType = jtNumber) and (len.AsFloat >= 0)
      and (len.AsFloat <= cMaxLength) and (Frac(len.AsFloat) = 0) then
      n := Trunc(len.AsFloat);
    arr := TJSONArray.Create;
    try
      for i := 1 to n do arr.Add(TJSONNull.Create);
      InitByData(arr);
    finally
      arr.Free;
    end;
  end
  else
  begin
    { _initBySeriesData: one level, no leaves yet; the category list
      collects (deduplicated) from the series }
    FCollect := True;
    FLeaves := 0;
    InitLevels(1);
  end;
end;

destructor TTyMatrixDim.Destroy;
begin
  FMeta.Free;
  inherited Destroy;
end;

procedure TTyMatrixDim.InitLevels(ACount: Integer);
var
  i: Integer;
  lv: TJSONData;
begin
  SetLength(FLevels, ACount);
  lv := nil;
  if FNode <> nil then lv := FNode.Find('levels');
  for i := 0 to ACount - 1 do
  begin
    FLevels[i].XY := NaN;
    FLevels[i].WH := NaN;
    FLevels[i].Node := nil;
    if (lv is TJSONArray) and (i < lv.Count) and (lv.Items[i] is TJSONObject) then
      FLevels[i].Node := TJSONObject(lv.Items[i]);
  end;
end;

type
  TCellList = array of Integer;

procedure TTyMatrixDim.InitByData(AData: TJSONArray);
var
  pool: array of TTyMatrixCell;
  sameLoc: array of TCellList;
  nLevels, total, i, k, other, loc, own, poolN, orderN: Integer;
  dupBase: Double;
  cats: array of string;
  nulls: array of Boolean;
  seen: TStringList;
  upper, v: string;
  order: TCellList;

  function Traverse(AArr: TJSONArray; AFirstLeaf, ALevel: Integer): Integer;
  var
    j, idx, childSpan, sub: Integer;
    item, val, ch: TJSONData;
    cell: TTyMatrixCell;
  begin
    Result := 0;
    if AArr = nil then Exit;
    for j := 0 to AArr.Count - 1 do
    begin
      item := AArr.Items[j];
      cell := Default(TTyMatrixCell);
      cell.Kind := tmkNonLeaf;
      cell.Ordinal := -1;
      cell.Level := ALevel;
      cell.FirstLeaf := AFirstLeaf;
      cell.Value := '';
      cell.Node := nil;
      { a string is the value; an object (an array is one too) carries it,
        a value that is not a string (or null) is none; anything else is a
        cell with no value }
      if item.JSONType = jtString then
        cell.Value := item.AsString
      else if item.JSONType in [jtObject, jtArray] then
      begin
        if item is TJSONObject then
        begin
          cell.Node := TJSONObject(item);
          val := cell.Node.Find('value');
          if (val <> nil) and (val.JSONType = jtString) then cell.Value := val.AsString;
        end;
      end;
      cell.Span[FDimIdx] := 1;
      cell.Span[1 - FDimIdx] := 1;
      cell.XY := NaN;
      cell.WH := NaN;
      cell.Rect := TyXYWH(NaN, NaN, NaN, NaN);
      { the pool grows by doubling: `length` can make a long flat list }
      idx := poolN;
      if idx >= Length(pool) then
      begin
        SetLength(pool, Max(16, 2 * Length(pool)));
        SetLength(nulls, Length(pool));
      end;
      Inc(poolN);
      pool[idx] := cell;
      { a null value: renamed later }
      nulls[idx] := not ((item.JSONType = jtString)
        or ((item is TJSONObject) and (TJSONObject(item).Find('value') <> nil)
          and (TJSONObject(item).Find('value').JSONType = jtString)));
      if AFirstLeaf >= Length(sameLoc) then
        SetLength(sameLoc, Max(AFirstLeaf + 1, 2 * Length(sameLoc)));
      SetLength(sameLoc[AFirstLeaf], Length(sameLoc[AFirstLeaf]) + 1);
      sameLoc[AFirstLeaf][High(sameLoc[AFirstLeaf])] := idx;
      if ALevel + 1 > nLevels then nLevels := ALevel + 1;
      ch := nil;
      if cell.Node <> nil then ch := cell.Node.Find('children');
      if ch is TJSONArray then childSpan := Traverse(TJSONArray(ch), AFirstLeaf, ALevel + 1)
      else childSpan := 0;
      sub := Max(1, childSpan);
      pool[idx].Span[FDimIdx] := sub;
      Inc(Result, sub);
      Inc(AFirstLeaf, sub);
    end;
  end;

  procedure CalcDupBase(const AVal: string; AIsNull: Boolean);
  var
    p: Integer;
    digits: string;
    n: Double;
  begin
    if AIsNull then Exit;
    { ^X([0-9]+)$ }
    if (Length(AVal) < 2) or (AVal[1] <> upper) then Exit;
    digits := Copy(AVal, 2, MaxInt);
    for p := 1 to Length(digits) do
      if not (digits[p] in ['0'..'9']) then Exit;
    n := TyJsParseFloat(digits) + 1;
    if n > dupBase then dupBase := n;
  end;

begin
  pool := nil;
  sameLoc := nil;
  nulls := nil;
  poolN := 0;
  nLevels := 0;
  total := Traverse(AData, 0, 0);
  FLeaves := total;
  if FDimIdx = 0 then upper := 'X' else upper := 'Y';
  dupBase := 0;
  { postInitCells: the leaves first -- each pass takes the LAST cell pushed
    at every locator, which on the first pass is that locator's leaf }
  order := nil;
  SetLength(order, poolN);
  orderN := 0;
  while orderN < poolN do
  begin
    k := orderN;
    for loc := 0 to High(sameLoc) do
      if Length(sameLoc[loc]) > 0 then
      begin
        own := sameLoc[loc][High(sameLoc[loc])];
        SetLength(sameLoc[loc], Length(sameLoc[loc]) - 1);
        order[orderN] := own;
        Inc(orderN);
        CalcDupBase(pool[own].Value, nulls[own]);
      end;
    if orderN = k then Break;
  end;
  SetLength(order, orderN);
  { ensureValueUnique: a null or a repeat takes X<dupBase++> }
  SetLength(cats, Length(order));
  seen := TStringList.Create;
  try
    { by bytes, as upstream keys a name: the locale compare took
      U+00C5 and U+212B for one letter, and whatever came after [P2] }
    seen.UseLocale := False;
    seen.Sorted := True;
    seen.CaseSensitive := True;
    seen.Duplicates := dupIgnore;
    for i := 0 to High(order) do
    begin
      v := pool[order[i]].Value;
      if nulls[order[i]] or (seen.IndexOf(v) >= 0) then
      begin
        v := upper + TyJsNumberToString(dupBase);
        dupBase := dupBase + 1;
        pool[order[i]].Value := v;
      end;
      cats[i] := v;
      seen.Add(v);
    end;
  finally
    seen.Free;
  end;
  FMeta.SetCategories(cats);
  SetLength(FCells, Length(order));
  for i := 0 to High(order) do
  begin
    FCells[i] := pool[order[i]];
    FCells[i].Ordinal := i;
  end;
  other := 1 - FDimIdx;
  for i := 0 to FLeaves - 1 do
  begin
    FCells[i].Kind := tmkLeaf;
    { the level variation: a leaf reaches down to the body }
    FCells[i].Span[other] := nLevels - FCells[i].Level;
  end;
  for i := 0 to High(FCells) do
  begin
    FCells[i].Id[FDimIdx] := FCells[i].FirstLeaf;
    FCells[i].Id[other] := FCells[i].Level - nLevels;
  end;
  InitLevels(nLevels);
end;

procedure TTyMatrixDim.TakeCollected;
var
  i, n: Integer;
begin
  if not FCollect then Exit;
  n := FMeta.Count;
  SetLength(FCells, n);
  FLeaves := n;
  for i := 0 to n - 1 do
  begin
    FCells[i] := Default(TTyMatrixCell);
    FCells[i].Kind := tmkLeaf;
    FCells[i].Ordinal := i;
    FCells[i].Level := 0;
    FCells[i].FirstLeaf := i;
    FCells[i].Id[FDimIdx] := i;
    FCells[i].Id[1 - FDimIdx] := -Length(FLevels);
    FCells[i].Span[0] := 1;
    FCells[i].Span[1] := 1;
    FCells[i].XY := NaN;
    FCells[i].WH := NaN;
    FCells[i].Rect := TyXYWH(NaN, NaN, NaN, NaN);
    FCells[i].Value := FMeta.CategoryAt(i);
    FCells[i].Node := nil;
  end;
end;

function TTyMatrixDim.LocatorCount(ADimIdx: Integer): Integer;
begin
  if ADimIdx = FDimIdx then Result := FLeaves else Result := Length(FLevels);
end;

function TTyMatrixDim.UnitOf(ADimIdx, ALocator: Integer; out AXY, AWH: Double): Boolean;
var k: Integer;
begin
  AXY := NaN;
  AWH := NaN;
  Result := False;
  if ADimIdx = FDimIdx then
  begin
    if (ALocator < 0) or (ALocator >= FLeaves) then Exit;
    AXY := FCells[ALocator].XY;
    AWH := FCells[ALocator].WH;
  end
  else
  begin
    k := ALocator + Length(FLevels);
    if (k < 0) or (k > High(FLevels)) then Exit;
    AXY := FLevels[k].XY;
    AWH := FLevels[k].WH;
  end;
  Result := True;
end;

function TTyMatrixDim.CellIndexOf(AValue: Double): Integer;
var r: Double;
begin
  Result := -1;
  if IsNan(AValue) or IsInfinite(AValue) then Exit;
  { Ordinal.parse: Math.round; -0 indexes the first cell }
  r := TyJsRound(AValue);
  if (r >= 0) and (r < Length(FCells)) then Result := Trunc(r);
end;

function TTyMatrixDim.CellCount: Integer;
begin
  Result := Length(FCells);
end;

function TTyMatrixDim.LevelCount: Integer;
begin
  Result := Length(FLevels);
end;

function TTyMatrixDim.GetCell(AIndex: Integer): TTyMatrixCell;
begin
  Result := FCells[AIndex];
end;

function TTyMatrixDim.GetLevel(AIndex: Integer): TTyMatrixLevel;
begin
  Result := FLevels[AIndex];
end;

{ ==================== TTyMatrixBodyCorner ==================== }

{$push}{$Q-}{$R-}
function BCHash(AX, AY: Integer): Cardinal;
begin
  Result := (Cardinal(AX) * Cardinal($9E3779B1)) xor (Cardinal(AY) * Cardinal($85EBCA77));
  Result := Result xor (Result shr 15);
end;
{$pop}

destructor TTyMatrixBodyCorner.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TTyMatrixBodyCorner.Clear;
var i: Integer;
begin
  for i := 0 to High(FCopies) do FCopies[i].Free;
  FCopies := nil;
  FCells := nil;
  FCount := 0;
  FSlots := nil;
  FOwners := nil;
  FOwnerN := 0;
end;

function TTyMatrixBodyCorner.Find(AX, AY: Integer): Integer;
var m, s, k: Integer;
begin
  Result := -1;
  m := Length(FSlots);
  if m = 0 then Exit;
  s := Integer(BCHash(AX, AY) and Cardinal(m - 1));
  while True do
  begin
    k := FSlots[s];
    if k = 0 then Exit;
    if (FCells[k - 1].X = AX) and (FCells[k - 1].Y = AY) then Exit(k - 1);
    s := (s + 1) and (m - 1);
  end;
end;

procedure TTyMatrixBodyCorner.Grow;
var m, i, s: Integer;
begin
  m := Max(16, 2 * Length(FSlots));
  FSlots := nil;
  SetLength(FSlots, m);
  for i := 0 to FCount - 1 do
  begin
    s := Integer(BCHash(FCells[i].X, FCells[i].Y) and Cardinal(m - 1));
    while FSlots[s] <> 0 do s := (s + 1) and (m - 1);
    FSlots[s] := i + 1;
  end;
end;

{ ensureBodyOrCornerCell: the cell at AX, AY, made (no option, no span)
  when there is none }
function TTyMatrixBodyCorner.Ensure(AX, AY: Integer): Integer;
var m, s: Integer;
begin
  Result := Find(AX, AY);
  if Result >= 0 then Exit;
  if (FCount + 1) * 2 > Length(FSlots) then Grow;
  if FCount >= Length(FCells) then SetLength(FCells, Max(16, 2 * Length(FCells)));
  Result := FCount;
  Inc(FCount);
  FCells[Result] := Default(TTyMatrixBCCell);
  FCells[Result].X := AX;
  FCells[Result].Y := AY;
  FCells[Result].Src := -1;
  FCells[Result].InSpanOf := -1;
  FCells[Result].Loc[0][0] := NaN;
  FCells[Result].Loc[0][1] := NaN;
  FCells[Result].Loc[1][0] := NaN;
  FCells[Result].Loc[1][1] := NaN;
  FCells[Result].SpanRect := TyXYWH(NaN, NaN, NaN, NaN);
  m := Length(FSlots);
  s := Integer(BCHash(AX, AY) and Cardinal(m - 1));
  while FSlots[s] <> 0 do s := (s + 1) and (m - 1);
  FSlots[s] := Result + 1;
end;

procedure TTyMatrixBodyCorner.AddOwner(ACell: Integer);
begin
  if FOwnerN >= Length(FOwners) then SetLength(FOwners, Max(8, 2 * Length(FOwners)));
  FOwners[FOwnerN] := ACell;
  Inc(FOwnerN);
end;

function TTyMatrixBodyCorner.Keep(AObj: TJSONObject): TJSONObject;
begin
  SetLength(FCopies, Length(FCopies) + 1);
  FCopies[High(FCopies)] := AObj;
  Result := AObj;
end;

function TTyMatrixBodyCorner.Count: Integer;
begin
  Result := FCount;
end;

function TTyMatrixBodyCorner.Cell(AIndex: Integer): TTyMatrixBCCell;
begin
  Result := FCells[AIndex];
end;

function TTyMatrixBodyCorner.OwnerCount: Integer;
begin
  Result := FOwnerN;
end;

function TTyMatrixBodyCorner.Owner(AIndex: Integer): Integer;
begin
  Result := FOwners[AIndex];
end;

{ ==================== TTyMatrix ==================== }

const
  cBoxKeys: array[0..5] of string = ('width', 'left', 'right', 'height', 'top', 'bottom');

constructor TTyMatrix.Create(AOption: TTyChartOption; AIndex: Integer);
var
  d: TJSONData;
  target, input: TTyCalBoxKeys;
  k: Integer;
begin
  inherited Create;
  FIndex := AIndex;
  FNode := nil;
  if AOption <> nil then
  begin
    d := AOption.ComponentAt('matrix', AIndex);
    if d is TJSONObject then FNode := TJSONObject(d);
  end;
  FDims[0] := TTyMatrixDim.Create(0, ObjIn(FNode, 'x'));
  FDims[1] := TTyMatrixDim.Create(1, ObjIn(FNode, 'y'));
  FBC[0] := TTyMatrixBodyCorner.Create;
  FBC[1] := TTyMatrixBodyCorner.Create;
  FBCReady := False;
  FZ := -50;
  if FNode <> nil then FZ := Trunc(NumberOr(FNode.Find('z'), -50));
  { THE BOX: the defaults (10% all round) merged under the option, then
    mergeLayoutParam with the option's own keys -- right and width written
    drop the default left }
  for k := 0 to 5 do
  begin
    target[k] := Default(TTyCalBoxKey);
    input[k] := Default(TTyCalBoxKey);
    if (FNode <> nil) and (FNode.Find(cBoxKeys[k]) <> nil) then
    begin
      input[k].Own := True;
      input[k].V := TyBoxRawOf(FNode.Find(cBoxKeys[k]));
      target[k] := input[k];
    end
    else if not (k in [0, 3]) then
    begin
      target[k].Own := True;
      target[k].V := TyBoxRawStr('10%');
    end;
  end;
  TyCalMergeLayoutParam(target, input, False, False);
  FBox.Width := target[0].V;
  FBox.Left := target[1].V;
  FBox.Right := target[2].V;
  FBox.Height := target[3].V;
  FBox.Top := target[4].V;
  FBox.Bottom := target[5].V;
  { getBoxLayoutParams: a null or undefined key reads the option root [F4c] }
  if AOption <> nil then TyBoxClimbRoot(FBox, AOption.Root);
  FRect := TyXYWH(NaN, NaN, NaN, NaN);
  FScale := 1;
end;

destructor TTyMatrix.Destroy;
begin
  FBC[0].Free;
  FBC[1].Free;
  FDims[0].Free;
  FDims[1].Free;
  inherited Destroy;
end;

function TTyMatrix.GetDim(AIndex: Integer): TTyMatrixDim;
begin
  Result := FDims[AIndex];
end;

function TTyMatrix.UnitAt(ADimIdx, ALocator: Integer; out AXY, AWH: Double): Boolean;
begin
  { a negative locator is the other tree's level, else this tree's leaf }
  if ALocator < 0 then Result := FDims[1 - ADimIdx].UnitOf(ADimIdx, ALocator, AXY, AWH)
  else Result := FDims[ADimIdx].UnitOf(ADimIdx, ALocator, AXY, AWH);
end;

procedure TTyMatrix.Resize(const AContainer: TTyRectF; APPI: Integer);

  function Scaled(const R: TTyBoxRaw): TTyBoxRaw;
  begin
    Result := R;
    if R.Kind = brNumber then Result.Num := R.Num * FScale;
  end;

var
  bx: TTyRawBox;
begin
  if APPI > 0 then FScale := APPI / 96 else FScale := 1;
  bx.Left := Scaled(FBox.Left);
  bx.Right := Scaled(FBox.Right);
  bx.Top := Scaled(FBox.Top);
  bx.Bottom := Scaled(FBox.Bottom);
  bx.Width := Scaled(FBox.Width);
  bx.Height := Scaled(FBox.Height);
  FRect := TyGetLayoutRect(bx, AContainer.Left, AContainer.Top,
    AContainer.Right - AContainer.Left, AContainer.Bottom - AContainer.Top, []);
  LayOutUnits(0);
  LayOutUnits(1);
  LayOutRest(0);
  LayOutRest(1);
  { layOutBodyCornerCellMerge: the maps afresh (a collecting tree has its
    leaves by now), then every merge's spanRect from its id and span
    [Batch 149] }
  FBCReady := False;
  EnsureCellMaps;
  LayOutSpans;
  FValid := True;
end;

{ layOutBodyCornerCellMerge. A merge running from a header level into the
  body has its two ends in different trees: upstream's
  layOutRectOneDimBasedOnUnit asks the header tree for the body locator and
  throws (the whole setOption fails); the port takes each end from its own
  tree and draws the span. }
procedure TTyMatrix.LayOutSpans;
var k, c: Integer;
begin
  for k := 0 to 1 do
    for c := 0 to FBC[k].FCount - 1 do
      if FBC[k].FCells[c].HasSpan then
      begin
        RectOneDim(FBC[k].FCells[c].SpanRect, 0, FBC[k].FCells[c].X, FBC[k].FCells[c].Span[0]);
        RectOneDim(FBC[k].FCells[c].SpanRect, 1, FBC[k].FCells[c].Y, FBC[k].FCells[c].Span[1]);
      end;
end;

procedure TTyMatrix.EnsureCellMaps;
begin
  if FBCReady then Exit;
  FBCReady := True;
  BuildCellMap(0);
  BuildCellMap(1);
end;

function TTyMatrix.CellMap(AKind: Integer): TTyMatrixBodyCorner;
begin
  EnsureCellMaps;
  Result := FBC[AKind];
end;

{ fillCellMap: every item an object with an array `coord` that locates on
  both directions (coordClamp: clamped to the body, or to the corner);
  then, in order, every MERGE united with each earlier merge it meets until
  it meets no more (resolveXYLocatorRangeByCellMerge) -- those give up, and
  when the union's top-left is not the merge's own, the merge gives up too
  and a shallow copy of its option (coord nulled) is pushed at the end with
  the union, to be settled in its turn; a merge whose top-left stayed keeps
  the union as its range and its OWN span. Then every item, in order,
  writes its option into each cell of its span (a later one wins) and a
  merge makes its top-left the owner of them all. }
procedure TTyMatrix.BuildCellMap(AKind: Integer);
type
  TParsed = record
    Id, Span: array[0..1] of Integer;
    Loc: TTyMatrixLocRange;
    Src: Integer;
    Copied, Owner: Boolean;
  end;
var
  bc: TTyMatrixBodyCorner;
  data, d, coord: TJSONData;
  list: array of TParsed;
  marks: array of Boolean;
  n, i, k, q, tl, c, xx, yy, items: Integer;
  clamp: TTyMatrixClamp;
  loc: TTyMatrixLocRange;
  parts: array[0..1] of TTyDoubleArray;
  work, writes, area: Int64;
  grew: Boolean;
  opt: TJSONObject;
  p: TParsed;

  procedure Push(const AP: TParsed);
  begin
    if n >= Length(list) then SetLength(list, Max(16, 2 * Length(list)));
    list[n] := AP;
    Inc(n);
  end;

  { fillIdSpanFromLocatorRange }
  procedure IdSpan(var AP: TParsed);
  begin
    AP.Id[0] := Trunc(AP.Loc[0][0]);
    AP.Id[1] := Trunc(AP.Loc[1][0]);
    AP.Span[0] := Trunc(AP.Loc[0][1]) - AP.Id[0] + 1;
    AP.Span[1] := Trunc(AP.Loc[1][1]) - AP.Id[1] + 1;
  end;

  { the option a copied entry holds: data[ASrc] with its coord nulled }
  function CopyOf(ASrc: Integer): TJSONObject;
  var j: Integer;
  begin
    Result := TJSONObject(data.Items[ASrc].Clone);
    j := Result.IndexOfName('coord');
    if j >= 0 then Result.Delete(j);
    Result.Add('coord', TJSONNull.Create);
    bc.Keep(Result);
  end;

begin
  bc := FBC[AKind];
  bc.Clear;
  data := nil;
  if AKind = 0 then d := ObjIn(FNode, 'body') else d := ObjIn(FNode, 'corner');
  if d <> nil then data := TJSONObject(d).Find('data');
  if not (data is TJSONArray) then Exit;
  if AKind = 0 then clamp := mclBody else clamp := mclCorner;
  list := nil;
  n := 0;
  items := Min(data.Count, cMaxCellItems);
  for i := 0 to items - 1 do
  begin
    d := data.Items[i];
    if not (d is TJSONObject) then Continue;
    coord := TJSONObject(d).Find('coord');
    if not (coord is TJSONArray) then Continue;
    { parseCoordRangeOption: element 0 x, 1 y; one that is not there is a
      part that names nothing }
    for k := 0 to 1 do
      if k < coord.Count then parts[k] := ParseCoordParts(k, coord.Items[k])
      else
      begin
        parts[k] := nil;
        SetLength(parts[k], 1);
        parts[k][0] := NaN;
      end;
    if Truthy(TJSONObject(d).Find('coordClamp')) then
    begin
      RangeOneDim(0, parts[0], clamp, loc[0][0], loc[0][1]);
      RangeOneDim(1, parts[1], clamp, loc[1][0], loc[1][1]);
    end
    else
    begin
      RangeOneDim(0, parts[0], mclNone, loc[0][0], loc[0][1]);
      RangeOneDim(1, parts[1], mclNone, loc[1][0], loc[1][1]);
    end;
    if IsNan(loc[0][0]) or IsNan(loc[0][1]) or IsNan(loc[1][0]) or IsNan(loc[1][1]) then Continue;
    p := Default(TParsed);
    p.Loc := loc;
    IdSpan(p);
    p.Src := i;
    p.Copied := False;
    p.Owner := Truthy(TJSONObject(d).Find('mergeCells'));
    Push(p);
  end;
  { THE MERGES UNITED, in order; a copy pushed meanwhile is settled in its
    turn }
  marks := nil;
  work := 0;
  i := 0;
  while i < n do
  begin
    if list[i].Owner and (work > cMaxMergeWork) then list[i].Owner := False;
    if list[i].Owner then
    begin
      if Length(marks) < i then SetLength(marks, Max(i, 2 * Length(marks)));
      loc := list[i].Loc;
      for q := 0 to i - 1 do marks[q] := False;
      repeat
        grew := False;
        for q := 0 to i - 1 do
        begin
          Inc(work);
          if not marks[q] and list[q].Owner and ExpandIfMeets(loc, list[q].Loc) then
          begin
            marks[q] := True;
            grew := True;
          end;
        end;
      until not grew;
      list[i].Loc := loc;
      for q := 0 to i - 1 do
        if marks[q] then list[q].Owner := False;
      if (loc[0][0] <> list[i].Id[0]) or (loc[1][0] <> list[i].Id[1]) then
      begin
        { the union's top-left is another cell: the last option takes it }
        list[i].Owner := False;
        p := Default(TParsed);
        p.Loc := loc;
        IdSpan(p);
        p.Src := list[i].Src;
        p.Copied := True;
        p.Owner := True;
        Push(p);
      end;
    end;
    Inc(i);
  end;
  { THE OPTIONS TO THE CELLS, in order }
  writes := 0;
  for i := 0 to n - 1 do
  begin
    area := Int64(list[i].Span[0]) * list[i].Span[1];
    if writes + area > cMaxCellWrites then Continue;
    Inc(writes, area);
    if list[i].Copied then opt := CopyOf(list[i].Src)
    else opt := TJSONObject(data.Items[list[i].Src]);
    tl := bc.Ensure(list[i].Id[0], list[i].Id[1]);
    if list[i].Owner then
    begin
      bc.FCells[tl].Owner := True;
      bc.FCells[tl].HasSpan := True;
      bc.FCells[tl].Span[0] := list[i].Span[0];
      bc.FCells[tl].Span[1] := list[i].Span[1];
      bc.FCells[tl].Loc := list[i].Loc;
      bc.FCells[tl].SpanRect := TyXYWH(NaN, NaN, NaN, NaN);
      bc.AddOwner(tl);
    end;
    for yy := 0 to list[i].Span[1] - 1 do
      for xx := 0 to list[i].Span[0] - 1 do
      begin
        c := bc.Ensure(list[i].Id[0] + xx, list[i].Id[1] + yy);
        bc.FCells[c].Option := opt;
        bc.FCells[c].Src := list[i].Src;
        bc.FCells[c].Copied := list[i].Copied;
        if list[i].Owner then bc.FCells[c].InSpanOf := tl;
      end;
  end;
end;

procedure TTyMatrix.ExpandByMerge(AKind: Integer; var ALoc: TTyMatrixLocRange);
var
  bc: TTyMatrixBodyCorner;
  c, q: Integer;
  marks: array of Boolean;
  grew: Boolean;
begin
  bc := FBC[AKind];
  if bc.FOwnerN = 0 then Exit;
  { one cell: a cell is in one merge at most, so its owner's range }
  if not (IsNan(ALoc[0][0]) or IsNan(ALoc[0][1]) or IsNan(ALoc[1][0]) or IsNan(ALoc[1][1]))
    and (ALoc[0][0] = ALoc[0][1]) and (ALoc[1][0] = ALoc[1][1]) then
  begin
    c := bc.Find(Trunc(ALoc[0][0]), Trunc(ALoc[1][0]));
    if (c >= 0) and (bc.FCells[c].InSpanOf >= 0) then
    begin
      ALoc := bc.FCells[bc.FCells[c].InSpanOf].Loc;
      Exit;
    end;
  end;
  marks := nil;
  SetLength(marks, bc.FOwnerN);
  repeat
    grew := False;
    for q := 0 to bc.FOwnerN - 1 do
      if not marks[q] and ExpandIfMeets(ALoc, bc.FCells[bc.FOwners[q]].Loc) then
      begin
        marks[q] := True;
        grew := True;
      end;
  until not grew;
end;

{ layOutUnitsOnDimension }
procedure TTyMatrix.LayOutUnits(ADimIdx: Integer);
var
  thisDim, otherDim: TTyMatrixDim;
  otherShow, notAlign: Boolean;
  restSize, computed, cur, rxy, rwh: Double;
  restCount, maxLoc, i, nLv: Integer;
  sizeOpt: TJSONData;

  function SizedBy(AOpt: TJSONData; AZero: Boolean): Double;
  begin
    { parseSizeOption: confined to the matrix; a px value scaled }
    if AZero then Exit(0);
    Result := TyMatrixSizeOf(AOpt, rwh);
    if (AOpt <> nil) and (AOpt.JSONType in [jtNumber, jtBoolean]) then
      Result := Result * FScale
    else if (AOpt <> nil) and (AOpt.JSONType = jtString)
      and not ((TyJsTrim(AOpt.AsString) <> '')
        and (TyJsTrim(AOpt.AsString)[Length(TyJsTrim(AOpt.AsString))] = '%')) then
      Result := Result * FScale;
    Result := Confine(Result, rwh);
  end;

  procedure Specified(var AWH: Double; ASize: Double);
  begin
    if IsNan(ASize) then Exit;
    AWH := Confine(ASize, restSize);
    restSize := Confine(restSize - AWH, Infinity);
    Dec(restCount);
  end;

  procedure Unspecified(var AXY, AWH: Double; AId: Integer);
  begin
    if IsNan(AWH) then AWH := computed;
    AXY := cur;
    if (AId = maxLoc) and not notAlign then
      { aligned to the far edge, against the cumulative error }
      AWH := rxy + rwh - AXY;
    cur := cur + AWH;
  end;

begin
  thisDim := FDims[ADimIdx];
  otherDim := FDims[1 - ADimIdx];
  if ADimIdx = 0 then
  begin
    rxy := FRect.X;
    rwh := FRect.W;
  end
  else
  begin
    rxy := FRect.Y;
    rwh := FRect.H;
  end;
  otherShow := otherDim.Show;
  { reset }
  for i := 0 to High(thisDim.FCells) do
  begin
    thisDim.FCells[i].XY := NaN;
    thisDim.FCells[i].WH := NaN;
  end;
  nLv := Length(otherDim.FLevels);
  for i := 0 to nLv - 1 do
  begin
    otherDim.FLevels[i].XY := NaN;
    otherDim.FLevels[i].WH := NaN;
  end;
  restSize := rwh;
  restCount := thisDim.FLeaves + nLv;
  { the other tree's levels: levels[i].levelSize, else the tree's levelSize;
    a hidden tree's are nought }
  for i := 0 to nLv - 1 do
  begin
    sizeOpt := nil;
    if otherDim.FLevels[i].Node <> nil then sizeOpt := otherDim.FLevels[i].Node.Find('levelSize');
    if JNull(sizeOpt) and (otherDim.FNode <> nil) then sizeOpt := otherDim.FNode.Find('levelSize');
    if JNull(sizeOpt) then sizeOpt := nil;
    Specified(otherDim.FLevels[i].WH, SizedBy(sizeOpt, not otherShow));
  end;
  { only a leaf takes a size }
  for i := 0 to High(thisDim.FCells) do
    if thisDim.FCells[i].Kind = tmkLeaf then
    begin
      sizeOpt := nil;
      if thisDim.FCells[i].Node <> nil then sizeOpt := thisDim.FCells[i].Node.Find('size');
      if JNull(sizeOpt) then sizeOpt := nil;
      if sizeOpt <> nil then Specified(thisDim.FCells[i].WH, SizedBy(sizeOpt, False));
    end;
  if restCount <> 0 then computed := restSize / restCount else computed := 0;
  { everything sized and room left over (1 against the cumulative error):
    the last unit keeps its size }
  notAlign := (restCount = 0) and (restSize >= 1);
  cur := rxy;
  maxLoc := thisDim.FLeaves - 1;
  for i := 0 to nLv - 1 do
    Unspecified(otherDim.FLevels[i].XY, otherDim.FLevels[i].WH, i - nLv);
  for i := 0 to thisDim.FLeaves - 1 do
    Unspecified(thisDim.FCells[i].XY, thisDim.FCells[i].WH, thisDim.FCells[i].Id[ADimIdx]);
end;

{ layOutRectOneDimBasedOnUnit }
procedure TTyMatrix.RectOneDim(var R: TTyXYWH; ADimIdx, AId, ASpan: Integer);
var xy, wh, xy2, wh2: Double;
begin
  UnitAt(ADimIdx, AId, xy, wh);
  if ASpan > 1 then
  begin
    UnitAt(ADimIdx, AId + ASpan - 1, xy2, wh2);
    wh := xy2 + wh2 - xy;
  end;
  if ADimIdx = 0 then
  begin
    R.X := xy;
    R.W := wh;
  end
  else
  begin
    R.Y := xy;
    R.H := wh;
  end;
end;

{ layOutDimCellsRestInfoByUnit }
procedure TTyMatrix.LayOutRest(ADimIdx: Integer);
var
  d: TTyMatrixDim;
  i: Integer;
begin
  d := FDims[ADimIdx];
  for i := 0 to High(d.FCells) do
  begin
    RectOneDim(d.FCells[i].Rect, ADimIdx, d.FCells[i].Id[ADimIdx], d.FCells[i].Span[ADimIdx]);
    RectOneDim(d.FCells[i].Rect, 1 - ADimIdx, d.FCells[i].Id[1 - ADimIdx],
      d.FCells[i].Span[1 - ADimIdx]);
    if d.FCells[i].Kind = tmkNonLeaf then
      if ADimIdx = 0 then
      begin
        d.FCells[i].XY := d.FCells[i].Rect.X;
        d.FCells[i].WH := d.FCells[i].Rect.W;
      end
      else
      begin
        d.FCells[i].XY := d.FCells[i].Rect.Y;
        d.FCells[i].WH := d.FCells[i].Rect.H;
      end;
  end;
end;

function TTyMatrix.CellLayoutOf(ADimIdx: Integer; AValue: Double; out ALoc, ASpan: Integer): Boolean;
var
  ci: Integer;
  r, xy, wh: Double;
begin
  ALoc := 0;
  ASpan := 1;
  Result := False;
  { getCell: a header cell by its ordinal }
  ci := FDims[ADimIdx].CellIndexOf(AValue);
  if ci >= 0 then
  begin
    ALoc := FDims[ADimIdx].FCells[ci].Id[ADimIdx];
    ASpan := FDims[ADimIdx].FCells[ci].Span[ADimIdx];
    Exit(True);
  end;
  { else a negative number is the other tree's level at its rounding }
  if IsNan(AValue) or IsInfinite(AValue) or not (AValue < 0) then Exit;
  r := TyJsRound(AValue);
  if r < -FDims[1 - ADimIdx].LevelCount then Exit;
  ALoc := Trunc(r);
  Result := FDims[1 - ADimIdx].UnitOf(ADimIdx, ALoc, xy, wh);
end;

procedure TTyMatrix.RangeOneDim(ADimIdx: Integer; const AParts: array of Double;
  AClamp: TTyMatrixClamp; out ALo, AHi: Double);
var
  lower, upper: Double;
  n: Integer;

  { parseCoordRangeOptionOnOneDimOnePart }
  procedure Part(AValue: Double);
  var loc, span: Integer;
  begin
    if not CellLayoutOf(ADimIdx, AValue, loc, span) then
    begin
      ALo := NaN;
      AHi := NaN;
      Exit;
    end;
    { mathMin(lo, a, b) / mathMax(hi, a, b): a NaN stays }
    ALo := JMin(JMin(ALo, loc), loc + span - 1);
    AHi := JMax(JMax(AHi, loc), loc + span - 1);
  end;

begin
  ALo := Infinity;
  AHi := -Infinity;
  n := Length(AParts);
  if n >= 1 then
  begin
    Part(AParts[0]);
    { [x1, x2, x3] is the range [x1, x3] }
    if n > 1 then Part(AParts[n - 1]);
  end
  else
  begin
    ALo := NaN;
    AHi := NaN;
  end;
  if AClamp = mclNone then Exit;
  { the whole row or column, body and corner, then confined: -0 when the
    other tree has no level, as upstream negates a nought }
  lower := FDims[1 - ADimIdx].LocatorCount(ADimIdx);
  lower := -lower;
  upper := FDims[ADimIdx].LocatorCount(ADimIdx) - 1;
  if AClamp = mclBody then lower := JMax(0, lower)
  else if AClamp = mclCorner then upper := JMin(-1, upper);
  if upper < lower then
  begin
    lower := NaN;
    upper := NaN;
  end;
  if IsNan(ALo) then ALo := lower;
  if IsNan(AHi) then AHi := upper;
  ALo := JMax(JMin(ALo, upper), lower);
  AHi := JMax(JMin(AHi, upper), lower);
end;

procedure TTyMatrix.DataToLayoutRange(const AX, AY: array of Double; AClamp: TTyMatrixClamp;
  out ARect: TTyXYWH; out ALoc: TTyMatrixLocRange; AIgnoreMerge: Boolean);

  { xyLocatorRangeToRectOneDim: the units at the two ends (a locator is a
    leaf's ordinal, or the other tree's level) }
  procedure ToRect(ADimIdx: Integer; out AXY, AWH: Double);
  var
    l0, l1, s: Integer;
    xy0, wh0, xy1, wh1: Double;
  begin
    AXY := NaN;
    AWH := NaN;
    if not CellLayoutOf(ADimIdx, ALoc[ADimIdx][0], l0, s) then Exit;
    if not CellLayoutOf(ADimIdx, ALoc[ADimIdx][1], l1, s) then Exit;
    if not UnitAt(ADimIdx, l0, xy0, wh0) then Exit;
    if not UnitAt(ADimIdx, l1, xy1, wh1) then Exit;
    AXY := xy0;
    AWH := xy1 + wh1 - xy0;
  end;

begin
  RangeOneDim(0, AX, AClamp, ALoc[0][0], ALoc[0][1]);
  RangeOneDim(1, AY, AClamp, ALoc[1][0], ALoc[1][1]);
  { expandRangeByCellMerge: the body's merges unless clamped to the corner
    (exactly 3), the corner's unless clamped to the body (exactly 2) }
  if not AIgnoreMerge then
  begin
    EnsureCellMaps;
    if AClamp <> mclCorner then ExpandByMerge(0, ALoc);
    if AClamp <> mclBody then ExpandByMerge(1, ALoc);
  end;
  ToRect(0, ARect.X, ARect.W);
  ToRect(1, ARect.Y, ARect.H);
end;

function TTyMatrix.DataToPointRange(const AX, AY: array of Double;
  AClamp: TTyMatrixClamp): TTyPointF;
var
  r: TTyXYWH;
  loc: TTyMatrixLocRange;
begin
  DataToLayoutRange(AX, AY, AClamp, r, loc);
  Result := TyPointF(r.X + r.W / 2, r.Y + r.H / 2);
end;

function TTyMatrix.Locate(ADimIdx: Integer; AValue: Double; out AXY, AWH: Double): Boolean;
var
  r: TTyXYWH;
  loc: TTyMatrixLocRange;
begin
  if ADimIdx = 0 then DataToLayoutRange([AValue], [NaN], mclNone, r, loc)
  else DataToLayoutRange([NaN], [AValue], mclNone, r, loc);
  if ADimIdx = 0 then
  begin
    AXY := r.X;
    AWH := r.W;
  end
  else
  begin
    AXY := r.Y;
    AWH := r.H;
  end;
  Result := not IsNan(AXY);
end;

procedure TTyMatrix.DataToLayoutXYWH(AX, AY: Double; out ARect: TTyXYWH);
var loc: TTyMatrixLocRange;
begin
  DataToLayoutRange([AX], [AY], mclNone, ARect, loc);
end;

const
  cAreaBody = 0;
  cAreaCorner = 1;
  cAreaOutside = 2;

procedure TTyMatrix.PointArea(ADimIdx: Integer; const APoint: TTyPointF;
  AClamp: TTyMatrixClamp; out AArea: Integer; var ACoord: Double);
var
  thisDim, otherDim: TTyMatrixDim;
  hasBodyMax, hasBody0, hasCornerMin, hasCornerM1: Boolean;
  bmXY, bmWH, b0XY, b0WH, cmXY, cmWH, c1XY, c1WH: Double;
  pxLoc0, pxMin, pxMax: Double;
begin
  thisDim := FDims[ADimIdx];
  otherDim := FDims[1 - ADimIdx];
  hasBodyMax := thisDim.UnitOf(ADimIdx, thisDim.LocatorCount(ADimIdx) - 1, bmXY, bmWH);
  hasBody0 := thisDim.UnitOf(ADimIdx, 0, b0XY, b0WH);
  hasCornerMin := otherDim.UnitOf(ADimIdx, -otherDim.LocatorCount(ADimIdx), cmXY, cmWH);
  hasCornerM1 := otherDim.Show and otherDim.UnitOf(ADimIdx, -1, c1XY, c1WH);
  if ADimIdx = 0 then ACoord := APoint.X else ACoord := APoint.Y;
  if not hasBody0 and not hasCornerM1 then
  begin
    AArea := cAreaOutside;
    Exit;
  end;
  if AClamp = mclBody then
  begin
    if hasBody0 then
    begin
      AArea := cAreaBody;
      ACoord := JMin(bmXY + bmWH, JMax(b0XY, ACoord));
    end
    else
      AArea := cAreaOutside;
    Exit;
  end;
  if AClamp = mclCorner then
  begin
    if hasCornerM1 then
    begin
      AArea := cAreaCorner;
      ACoord := JMin(c1XY + c1WH, JMax(cmXY, ACoord));
    end
    else
      AArea := cAreaOutside;
    Exit;
  end;
  if hasBody0 then pxLoc0 := b0XY
  else if hasCornerM1 then pxLoc0 := c1XY + c1WH
  else pxLoc0 := NaN;
  if hasCornerMin then pxMin := cmXY else pxMin := pxLoc0;
  if hasBodyMax then pxMax := bmXY + bmWH else pxMax := pxLoc0;
  if not IsNan(ACoord) and not IsNan(pxMin) and (ACoord < pxMin) then
  begin
    if AClamp = mclNone then
    begin
      AArea := cAreaOutside;
      Exit;
    end;
    ACoord := pxMin;
  end
  else if not IsNan(ACoord) and not IsNan(pxMax) and (ACoord > pxMax) then
  begin
    if AClamp = mclNone then
    begin
      AArea := cAreaOutside;
      Exit;
    end;
    ACoord := pxMax;
  end;
  if IsNan(ACoord) or IsNan(pxLoc0) then AArea := cAreaOutside
  else if (pxLoc0 <= ACoord) and not IsNan(pxMax) and (ACoord <= pxMax) then AArea := cAreaBody
  else if not IsNan(pxMin) and (pxMin <= ACoord) and (ACoord <= pxLoc0) then AArea := cAreaCorner
  else AArea := cAreaOutside;
end;

procedure TTyMatrix.PointToDataClamp(const APoint: TTyPointF; AClamp: TTyMatrixClamp;
  out AX, AY: Double);
var
  area: array[0..1] of Integer;
  pt: array[0..1] of Double;
  outV: array[0..1] of Double;

  function InRect(ACoord: Double; const R: TTyXYWH; ADimIdx: Integer): Boolean;
  var a, w: Double;
  begin
    if ADimIdx = 0 then
    begin
      a := R.X;
      w := R.W;
    end
    else
    begin
      a := R.Y;
      w := R.H;
    end;
    Result := not IsNan(ACoord) and not IsNan(a) and not IsNan(w)
      and (a <= ACoord) and (ACoord <= a + w);
  end;

  { pointToDataOnlyHeaderFillOut: the header cell under the point, both ways
    -- a parent can be found this way }
  procedure OnlyHeader(ADimIdx: Integer);
  var
    i: Integer;
    d: TTyMatrixDim;
  begin
    if area[ADimIdx] = cAreaOutside then Exit;
    d := FDims[ADimIdx];
    for i := 0 to High(d.FCells) do
      if InRect(pt[ADimIdx], d.FCells[i].Rect, ADimIdx)
        and InRect(pt[1 - ADimIdx], d.FCells[i].Rect, 1 - ADimIdx) then
      begin
        outV[ADimIdx] := d.FCells[i].Ordinal;
        outV[1 - ADimIdx] := d.FCells[i].Id[1 - ADimIdx];
        Exit;
      end;
  end;

  { pointToDataBodyCornerFillOut: the leaf or the level the coordinate is in }
  procedure BodyCorner(ADimIdx: Integer);
  var
    d: TTyMatrixDim;
    i, n: Integer;
    c: Double;
  begin
    if area[ADimIdx] = cAreaOutside then Exit;
    c := pt[ADimIdx];
    if IsNan(c) then Exit;
    if area[ADimIdx] = cAreaCorner then
    begin
      d := FDims[1 - ADimIdx];
      n := Length(d.FLevels);
      for i := 0 to n - 1 do
        if not IsNan(d.FLevels[i].XY) and (d.FLevels[i].XY <= c)
          and (c <= d.FLevels[i].XY + d.FLevels[i].WH) then
        begin
          outV[ADimIdx] := i - n;
          Exit;
        end;
    end
    else
    begin
      d := FDims[ADimIdx];
      for i := 0 to d.FLeaves - 1 do
        if not IsNan(d.FCells[i].XY) and (d.FCells[i].XY <= c)
          and (c <= d.FCells[i].XY + d.FCells[i].WH) then
        begin
          outV[ADimIdx] := d.FCells[i].Id[ADimIdx];
          Exit;
        end;
    end;
  end;

begin
  PointArea(0, APoint, AClamp, area[0], pt[0]);
  PointArea(1, APoint, AClamp, area[1], pt[1]);
  outV[0] := NaN;
  outV[1] := NaN;
  if (area[1] = cAreaCorner) and (area[0] = cAreaBody) then OnlyHeader(0)
  else if (area[0] = cAreaCorner) and (area[1] = cAreaBody) then OnlyHeader(1)
  else
  begin
    BodyCorner(0);
    BodyCorner(1);
  end;
  AX := outV[0];
  AY := outV[1];
end;

function TTyMatrix.ParseCoord(ADimIdx: Integer; AValue: TJSONData): Double;
var o: Integer;
begin
  Result := NaN;
  if JNull(AValue) then Exit;
  case AValue.JSONType of
    jtNumber: Result := AValue.AsFloat;
    jtString:
      begin
        o := FDims[ADimIdx].Meta.GetOrdinal(AValue.AsString);
        if o >= 0 then Result := o;
      end;
  end;
end;

function TTyMatrix.ParseCoordParts(ADimIdx: Integer; AValue: TJSONData): TTyDoubleArray;
var i: Integer;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    SetLength(Result, AValue.Count);
    for i := 0 to AValue.Count - 1 do
      Result[i] := ParseCoord(ADimIdx, AValue.Items[i]);
  end
  else
  begin
    SetLength(Result, 1);
    Result[0] := ParseCoord(ADimIdx, AValue);
  end;
end;

procedure TyMatrixLayoutJson(AMatrix: TTyMatrix; AData: TJSONData; AClamp: TTyMatrixClamp;
  out ARect: TTyXYWH; out ALoc: TTyMatrixLocRange; AIgnoreMerge: Boolean);
var
  parts: array[0..1] of TTyDoubleArray;
  k: Integer;
begin
  ARect := TyXYWH(NaN, NaN, NaN, NaN);
  ALoc[0][0] := NaN;
  ALoc[0][1] := NaN;
  ALoc[1][0] := NaN;
  ALoc[1][1] := NaN;
  if (AMatrix = nil) or not (AData is TJSONArray) then Exit;
  for k := 0 to 1 do
    if k < AData.Count then parts[k] := AMatrix.ParseCoordParts(k, AData.Items[k])
    else
    begin
      SetLength(parts[k], 1);
      parts[k][0] := NaN;
    end;
  AMatrix.DataToLayoutRange(parts[0], parts[1], AClamp, ARect, ALoc, AIgnoreMerge);
end;

function TTyMatrix.CoordSysName: string;
begin
  Result := TyMatrixCoordSysName;
end;

function TTyMatrix.DimCount: Integer;
begin
  Result := 2;
end;

function TTyMatrix.GetRect: TTyRectF;
begin
  Result := TyRectF(FRect.X, FRect.Y, FRect.X + FRect.W, FRect.Y + FRect.H);
end;

function TTyMatrix.DataToPoint(const AData: array of Double): TTyPointF;
var r: TTyXYWH;
begin
  if Length(AData) < 2 then Exit(TyPointF(NaN, NaN));
  DataToLayoutXYWH(AData[0], AData[1], r);
  Result := TyPointF(r.X + r.W / 2, r.Y + r.H / 2);
end;

function TTyMatrix.DataToLayout(const AData: array of Double): TTyCoordLayout;
var r: TTyXYWH;
begin
  if Length(AData) < 2 then
    r := TyXYWH(NaN, NaN, NaN, NaN)
  else
    DataToLayoutXYWH(AData[0], AData[1], r);
  Result.Rect := TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H);
  Result.ContentRect := Result.Rect;
end;

function TTyMatrix.PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
begin
  SetLength(AData, 2);
  PointToDataClamp(APoint, mclNone, AData[0], AData[1]);
  Result := True;
end;

function TTyMatrix.ContainPoint(const APoint: TTyPointF): Boolean;
begin
  Result := (APoint.X >= FRect.X) and (APoint.X <= FRect.X + FRect.W)
    and (APoint.Y >= FRect.Y) and (APoint.Y <= FRect.Y + FRect.H);
end;

function TTyMatrix.AxisCount: Integer;
begin
  Result := 0;
end;

function TTyMatrix.CellInfoCount: Integer;
begin
  Result := FCellInfoN;
end;

function TTyMatrix.CellInfo(AIndex: Integer): TTyMatrixCellInfo;
begin
  if (AIndex < 0) or (AIndex >= FCellInfoN) then Exit(Default(TTyMatrixCellInfo));
  Result := FCellInfos[AIndex];
end;

function TTyMatrix.TriggerEvent: Boolean;
begin
  Result := (FNode <> nil) and Truthy(FNode.Find('triggerEvent'));
end;

function TTyMatrix.TooltipNode: TJSONObject;
begin
  Result := ObjIn(FNode, 'tooltip');
end;

function TTyMatrix.GetAxis(AIndex: Integer): TTyAxis;
begin
  Result := nil;
end;

{ ==================== the picture ==================== }

type
  { getItemStyle over a cell's own style and its parent's }
  TCellStyle = record
    HasFill: Boolean;
    Fill: TTyChartColor;
    Stroke: TTyChartColor;
    LineWidth: Double;
    Opacity: Double;
    Dash: TTyDoubleArray;
    { a fill that is an object: a gradient or an image [Batch 149] }
    Grad: TTyChartGradient;
    Pat: TTyChartPattern;
  end;

var
  { MatrixModel's defaultLabelOption less its colour, which is the skin's:
    show, overflow 'break', lineOverflow 'truncate', padding [2, 3, 2, 3],
    distance 0 }
  GLabelDefaults: TJSONObject;

function ColourOf(const C: TTyOptColor; out ANone: Boolean): TTyChartColor;
begin
  ANone := C.IsNone;
  if C.IsNone then Result := 0 else Result := C.Color;
end;

{ A style block read as a lineStyle (width, type) wherever it sits }
function LineBlockOf(ANode: TJSONObject; const AKey: string): TTyOptStyle;
var
  sub: TJSONObject;
  tmp: TJSONObject;
begin
  sub := ObjIn(ANode, AKey);
  if sub = nil then Exit(TyReadOptStyle(nil, 'lineStyle'));
  tmp := TJSONObject.Create;
  try
    tmp.Add('lineStyle', sub.Clone);
    Result := TyReadOptStyle(tmp, 'lineStyle');
  finally
    tmp.Free;
  end;
end;

{ ACell's AKey block over AParent's, over the defaults: no fill, a 1 px
  border in AStroke (none with ANoStroke), opaque, solid }
function CellStyleOf(ACell, AParent: TJSONObject; const AKey: string;
  AStroke: TTyChartColor; ANoStroke: Boolean): TCellStyle;
var
  a, b: TTyOptStyle;
  none: Boolean;
  c: TTyChartColor;
begin
  a := TyReadOptStyle(ACell, AKey);
  b := TyReadOptStyle(AParent, AKey);
  Result := Default(TCellStyle);
  none := True;
  c := 0;
  if a.Color.Written then
  begin
    c := ColourOf(a.Color, none);
    Result.Grad := a.Color.Gradient;
    Result.Pat := a.Color.Pattern;
  end
  else if b.Color.Written then
  begin
    c := ColourOf(b.Color, none);
    Result.Grad := b.Color.Gradient;
    Result.Pat := b.Color.Pattern;
  end;
  Result.HasFill := not none;
  Result.Fill := c;
  if a.BorderColor.Written then c := ColourOf(a.BorderColor, none)
  else if b.BorderColor.Written then c := ColourOf(b.BorderColor, none)
  else if ANoStroke then c := 0
  else c := AStroke;
  Result.Stroke := c;
  if not IsNan(a.BorderWidthLogical) then Result.LineWidth := a.BorderWidthLogical
  else if not IsNan(b.BorderWidthLogical) then Result.LineWidth := b.BorderWidthLogical
  else Result.LineWidth := 1;
  if not IsNan(a.Opacity) then Result.Opacity := a.Opacity
  else if not IsNan(b.Opacity) then Result.Opacity := b.Opacity
  else Result.Opacity := 1;
  Result.Dash := nil;
  if a.Dash <> todNone then
    Result.Dash := TyDashPattern(a.Dash, a.DashLogical, Result.LineWidth)
  else if b.Dash <> todNone then
    Result.Dash := TyDashPattern(b.Dash, b.DashLogical, Result.LineWidth);
end;

{ a dimension's dividerLineStyle: width 1 in AStroke by default }
function DividerStyleOf(ADimNode: TJSONObject; AStroke: TTyChartColor): TCellStyle;
var
  a: TTyOptStyle;
  none: Boolean;
begin
  a := LineBlockOf(ADimNode, 'dividerLineStyle');
  Result := Default(TCellStyle);
  if a.Color.Written then Result.Stroke := ColourOf(a.Color, none)
  else Result.Stroke := AStroke;
  if not IsNan(a.BorderWidthLogical) then Result.LineWidth := a.BorderWidthLogical
  else Result.LineWidth := 1;
  if not IsNan(a.Opacity) then Result.Opacity := a.Opacity else Result.Opacity := 1;
  Result.Dash := nil;
  if a.Dash <> todNone then
    Result.Dash := TyDashPattern(a.Dash, a.DashLogical, Result.LineWidth);
end;

function AdjX(AX, AW: Double; AAlign: TTyRtAlign; AInverse: Boolean): Double;
begin
  Result := AX;
  if AAlign = rtaRight then
  begin
    if AInverse then Result := AX + AW else Result := AX - AW;
  end
  else if AAlign = rtaCenter then
  begin
    if AInverse then Result := AX + AW / 2 else Result := AX - AW / 2;
  end;
end;

function AdjY(AY, AH: Double; AVAlign: TTyRtVAlign; AInverse: Boolean): Double;
begin
  Result := AY;
  if AVAlign = rtvMiddle then
  begin
    if AInverse then Result := AY + AH / 2 else Result := AY - AH / 2;
  end
  else if AVAlign = rtvBottom then
  begin
    if AInverse then Result := AY + AH else Result := AY - AH;
  end;
end;

{ BoundingRect.intersect with clamp, on one dimension: [A0, A1] met by
  [B0, B1]; apart, the edge of A nearer to B with no size }
procedure Intersect1(A0, A1, B0, B1: Double; out AX, AW: Double);
var d0, d1: Double;
begin
  d0 := Abs(A1 - B0);
  d1 := Abs(B1 - A0);
  if (A1 < B0) or (B1 < A0) then
  begin
    if d0 < d1 then AX := A1 else AX := A0;
    AW := 0;
  end
  else
  begin
    AX := Max(A0, B0);
    AW := Min(A1, B1) - AX;
  end;
end;

function AlignOfWord(const S: string): TTyRtAlign;
begin
  if S = 'center' then Result := rtaCenter
  else if S = 'right' then Result := rtaRight
  else if S = 'left' then Result := rtaLeft
  else Result := rtaNone;
end;

function VAlignOfWord(const S: string): TTyRtVAlign;
begin
  if S = 'middle' then Result := rtvMiddle
  else if S = 'bottom' then Result := rtvBottom
  else if S = 'top' then Result := rtvTop
  else Result := rtvNone;
end;

{ Transformable.getLocalTransform with no scale, skew or anchor, its order
  of operations exactly (matrix.rotate about [0, 0]) [Batch 147] }
procedure ZrLocal(AX, AY, AOX, AOY, ARot: Double; out M: TTyMat2D);
var aa, ac, atx, ab, ad, aty, st, ct: Double;
begin
  if (AOX <> 0) or (AOY <> 0) then
  begin
    M[4] := -AOX * 1 - 0 * AOY * 1;
    M[5] := -AOY * 1 - 0 * AOX * 1;
  end
  else
  begin
    M[4] := 0;
    M[5] := 0;
  end;
  M[0] := 1;
  M[3] := 1;
  M[1] := 0;
  M[2] := 0;
  if (ARot <> 0) and not IsNan(ARot) then
  begin
    aa := M[0]; ac := M[2]; atx := M[4];
    ab := M[1]; ad := M[3]; aty := M[5];
    st := TyJsSin(ARot);
    ct := TyJsCos(ARot);
    M[0] := aa * ct + ab * st;
    M[1] := -aa * st + ab * ct;
    M[2] := ac * ct + ad * st;
    M[3] := -ac * st + ct * ad;
    M[4] := ct * (atx - 0) + st * (aty - 0) + 0;
    M[5] := ct * (aty - 0) - st * (atx - 0) + 0;
  end;
  M[4] := M[4] + (AOX + AX);
  M[5] := M[5] + (AOY + AY);
end;

function TyBuildMatrix(AMatrix: TTyMatrix; const AInk: TTyMatrixInk;
  const AGlobal: TTyRtGlobal; const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AList: TTyPaintList): Integer;
var
  scale: Double;
  z, outerZ2, added: Integer;
  node: TJSONObject;
  triggerEv, tipShow: Boolean;
  { [F6a] the next cell rect's cursor ('' the prototype's pointer) }
  rectCursor: string;

  { a new cell's serial in AMatrix's table }
  function NewInfo(const ATarget: string; ALocX, ALocY: Integer): Integer;
  begin
    if AMatrix.FCellInfoN >= Length(AMatrix.FCellInfos) then
      SetLength(AMatrix.FCellInfos, Max(16, 2 * Length(AMatrix.FCellInfos)));
    Result := AMatrix.FCellInfoN;
    Inc(AMatrix.FCellInfoN);
    AMatrix.FCellInfos[Result] := Default(TTyMatrixCellInfo);
    AMatrix.FCellInfos[Result].Target := ATarget;
    AMatrix.FCellInfos[Result].Loc[0] := ALocX;
    AMatrix.FCellInfos[Result].Loc[1] := ALocY;
  end;

  { createMatrixRect: the edges on the pixel grid of the border's width;
    answers the shape drawn }
  function AddRect(const AShape: TTyXYWH; const S: TCellStyle; AZ2: Integer;
    ASilent: Boolean = True; AInfo: Integer = -1; ABand: Double = 0): TTyXYWH;
  var
    x2, y2, lw: Double;
    el: TTyChartElement;
  begin
    Result := AShape;
    lw := S.LineWidth * scale;
    if (lw <> 0) and not IsNan(lw) then
    begin
      x2 := Result.X + Result.W;
      y2 := Result.Y + Result.H;
      Result.X := TySubPixelOptimize(Result.X, lw, True);
      Result.Y := TySubPixelOptimize(Result.Y, lw, True);
      Result.W := TySubPixelOptimize(x2, lw, True) - Result.X;
      Result.H := TySubPixelOptimize(y2, lw, True) - Result.Y;
    end;
    el := TyChartElement(TyShapeRect(TyRectF(Result.X, Result.Y,
      Result.X + Result.W, Result.Y + Result.H)));
    el.Style.HasFill := S.HasFill and (((S.Fill shr 24) <> 0)
      or (S.Grad.Kind <> cgkNone) or S.Pat.Present);
    el.Style.FillColor := S.Fill;
    el.Style.FillGradient := S.Grad;
    el.Style.FillPattern := S.Pat;
    el.Style.StrokeColor := S.Stroke;
    if ((S.Stroke shr 24) = 0) or IsNan(S.LineWidth) then el.Style.StrokeWidthLogical := 0
    else el.Style.StrokeWidthLogical := S.LineWidth;
    el.Style.DashLogical := S.Dash;
    el.Style.Alpha := S.Opacity;
    el.Z := z;
    el.Z2 := AZ2;
    el.Silent := ASilent;
    if AInfo >= 0 then el.Datum := TyChartComponentDatum(ctkMatrix, AMatrix.Index, AInfo);
    el.HitStrokeBand := ABand;
    el.Cursor := rectCursor;
    AList.Add(el);
    Inc(added);
  end;

  { createMatrixLine: a line along x or y on the pixel grid of its width }
  procedure AddLine(AX1, AY1, AX2, AY2: Double; const S: TCellStyle; AZ2: Integer);
  var el: TTyChartElement;
  begin
    TySubPixelOptimizeLine(AX1, AY1, AX2, AY2, S.LineWidth * scale);
    el := TyChartElement(TyShapePolyline([TyPointF(AX1, AY1), TyPointF(AX2, AY2)]));
    el.Style.HasFill := False;
    el.Style.StrokeColor := S.Stroke;
    if ((S.Stroke shr 24) = 0) or IsNan(S.LineWidth) then el.Style.StrokeWidthLogical := 0
    else el.Style.StrokeWidthLogical := S.LineWidth;
    el.Style.DashLogical := S.Dash;
    el.Style.Alpha := S.Opacity;
    el.Z := z;
    el.Z2 := AZ2;
    el.Silent := True;
    AList.Add(el);
    Inc(added);
  end;

  { A CELL'S LABEL (createMatrixCell's setLabelStyle, Element.updateInnerText
    with autoOverflowArea and the cell as its layoutRect, Text's
    calcInnerTextOverflowArea and parsePlainText): placed by its position
    on the drawn shape, its width and height what the overflow area leaves
    inside the padding, clipped to the shape inside its border }
  procedure AddLabel(const AText: string; AValue: TJSONData; ALocX, ALocY: Integer;
    ACellLabel, AParentLabel: TJSONObject; const AShape: TTyXYWH;
    ALineWidth: Double; AZ2, AInfo: Integer);
  var
    prm: TTyChartCallbackParams;
    chain: array[0..2] of TJSONObject;
    text, fam, alignS, valignS: string;
    d: TJSONData;
    rt: TTyRtBlockStyle;
    size, weight: Integer;
    tx, ty, dist, ix, iy, iw, ih, baseX, baseY, padH, padV, half: Double;
    offX, offY, rot, rotDeg: Double;
    hasOff: Boolean;
    m, mi: TTyMat2D;
    ovr, cl: TTyXYWH;
    align: TTyRtAlign;
    valign: TTyRtVAlign;
    pieces: TTyRtPieceArray;
    el: TTyChartElement;
    ah: TTyTextAnchorH;
    av: TTyTextAnchorV;
    clip: TTyXYWH;
    silent: Boolean;
  begin
    chain[0] := ACellLabel;
    chain[1] := AParentLabel;
    chain[2] := GLabelDefaults;
    text := AText;
    d := ChainGet(chain, 'formatter');
    if (d <> nil) and (d.JSONType = jtString) and TyChartIsHandlerRef(d.AsString) then
    begin
      { A FUNCTION FORMATTER, the port's named handler [Batch 149]:
        componentType, componentIndex, name (the text), value (the cell's
        value: its String() in ValueText, a number also in Values) and the
        locator pair in Coord }
      prm := TyChartBlankParams;
      prm.ComponentType := TyMatrixCoordSysName;
      prm.ComponentIndex := AMatrix.Index;
      prm.Name := AText;
      prm.ValueText := AText;
      prm.DefaultText := AText;
      if (AValue <> nil) and (AValue.JSONType = jtNumber) then
      begin
        SetLength(prm.Values, 1);
        prm.Values[0] := AValue.AsFloat;
      end;
      SetLength(prm.Coord, 2);
      prm.Coord[0] := ALocX;
      prm.Coord[1] := ALocY;
      text := TyChartRunHandler(d.AsString, TyChartOneParams(prm));
    end
    else if (d <> nil) and (d.JSONType = jtString) then
      { formatTplSimple over the params, in their order }
      text := TyCalFormatTpl(d.AsString,
        ['componentType', 'componentIndex', 'name', 'value', 'coord', '$vars'],
        ['matrix', IntToStr(AMatrix.Index), AText, AText,
         IntToStr(ALocX) + ',' + IntToStr(ALocY), 'name,value,coord']);
    { setTooltipConfig's itemName is the text after the formatter, shown or
      not }
    AMatrix.FCellInfos[AInfo].TipName := text;
    if not Truthy(ChainGet(chain, 'show')) then Exit;
    rt := TyRtResolve(chain, AGlobal, TyRtResolveOpt(True));
    fam := '';
    d := ChainGet(chain, 'fontFamily');
    if (d <> nil) and (d.JSONType = jtString) then fam := d.AsString;
    if fam = '' then fam := AGlobal.FontFamily;
    size := TyOptFontSize(ChainGet(chain, 'fontSize'), AGlobal.FontSizeLogical);
    weight := TyFontWeightOf(ChainGet(chain, 'fontWeight'), AGlobal.FontWeight);
    TyRtFinish(rt, fam, size, weight, AGlobal, False, 0);
    { the label's colour is always written upstream (the token); the skin's
      where the option wrote none }
    if not rt.Style.HasFill then
    begin
      rt.Style.HasFill := True;
      rt.Style.FillNone := False;
      rt.Style.Fill := AInk.LabelColour;
    end;
    { calculateTextPosition on the shape }
    dist := NumberOr(ChainGet(chain, 'distance'), 0) * scale;
    TyGfxTextPosition(ChainGet(chain, 'position'), dist, AShape, tx, ty, alignS, valignS);
    if IsNan(tx) or IsNan(ty) then Exit;
    { THE TEXT'S OWN TRANSFORM (Element.updateInnerText): the offset moves it
      and becomes its origin, negated; createTextConfig's rotation (degrees
      written) turns it about that origin [Batch 147] }
    hasOff := False;
    offX := 0;
    offY := 0;
    d := ChainGet(chain, 'offset');
    if (d is TJSONArray) and (d.Count >= 2) then
    begin
      hasOff := True;
      offX := NumberOr(d.Items[0], 0);
      offY := NumberOr(d.Items[1], 0);
    end;
    rot := 0;
    d := ChainGet(chain, 'rotate');
    if d <> nil then
    begin
      rotDeg := NaN;
      if d.JSONType = jtNumber then rotDeg := d.AsFloat
      else if d.JSONType = jtString then rotDeg := TyJsToNumber(d.AsString);
      rot := rotDeg * (Pi / 180);
    end;
    if IsNan(rot) then rot := 0;
    if hasOff then
      ZrLocal(tx / scale + offX, ty / scale + offY, -offX, -offY, rot, m)
    else
      ZrLocal(tx / scale, ty / scale, 0, 0, rot, m);
    align := rt.Style.Align;
    if align = rtaNone then align := AlignOfWord(alignS);
    if align = rtaNone then align := rtaLeft;
    valign := rt.Style.VAlign;
    if valign = rtvNone then valign := VAlignOfWord(valignS);
    if valign = rtvNone then valign := rtvTop;
    { THE OVERFLOW AREA: the shape through the inverse of the text's
      transform (BoundingRect.applyTransform: a turned shape's bounding box),
      met by a box twice its size hung at the base by the alignment; the
      base moves to the meeting, the meeting is the room -- for plain and
      rich text alike [Batch 147: rotated, and rich] }
    if not TyMatInvert(m, mi) then Exit;
    ovr := TyRectApplyMat(TyXYWH(AShape.X / scale, AShape.Y / scale, AShape.W / scale,
      AShape.H / scale), mi);
    Intersect1(ovr.X, ovr.X + ovr.W, AdjX(0, ovr.W * 2, align, False),
      AdjX(0, ovr.W * 2, align, False) + ovr.W * 2, ix, iw);
    Intersect1(ovr.Y, ovr.Y + ovr.H, AdjY(0, ovr.H * 2, valign, False),
      AdjY(0, ovr.H * 2, valign, False) + ovr.H * 2, iy, ih);
    baseX := AdjX(ix, iw, align, True);
    baseY := AdjY(iy, ih, valign, True);
    begin
      padH := 0;
      padV := 0;
      if rt.Style.HasPadding then
      begin
        padH := rt.Style.Padding[1] + rt.Style.Padding[3];
        padV := rt.Style.Padding[0] + rt.Style.Padding[2];
      end;
      if rt.Style.WidthKind = rtwNone then
      begin
        rt.Style.WidthKind := rtwNumber;
        rt.Style.Width := iw - padH;
      end;
      if not rt.Style.HasHeight then
      begin
        rt.Style.HasHeight := True;
        rt.Style.Height := ih - padV;
      end;
    end;
    case align of
      rtaCenter: ah := tahCentre;
      rtaRight: ah := tahRight;
    else
      ah := tahLeft;
    end;
    case valign of
      rtvMiddle: av := tavMiddle;
      rtvBottom: av := tavBottom;
    else
      av := tavTop;
    end;
    pieces := TyRtLayAt(text, rt, TyRtDefaultOf(True, AInk.LabelColour, False, 0, True,
      ah, av), baseX, baseY, scale, AMeasurer);
    if Length(pieces) = 0 then Exit;
    { the anchor is the transform's translation: the frame's origin }
    tx := m[4] * scale;
    ty := m[5] * scale;
    el := TyChartElement(TyShapeRect(TyRtDeviceBox(pieces, tx, ty, rot, scale)));
    el.Caption.Text := text;
    el.Caption.FontName := fam;
    el.Caption.FontSizeLogical := size;
    el.Caption.FontWeight := weight;
    el.Caption.Colour := rt.Style.Fill;
    el.Caption.X := tx;
    el.Caption.Y := ty;
    el.Caption.AnchorH := ah;
    el.Caption.AnchorV := av;
    el.Caption.RotationRad := rot;
    el.Caption.RtPieces := pieces;
    el.Caption.RtScale := scale;
    AMatrix.FCellInfos[AInfo].HasName := True;
    AMatrix.FCellInfos[AInfo].Name := text;
    { THE CLIP when the words may overflow: the shape inside half its border
      (expandOrShrinkRect, shrinking, never past nought) }
    if Truthy(ChainGet(chain, 'overflow')) and (StrOf(ChainGet(chain, 'overflow')) <> 'none')
      and Truthy(ChainGet(chain, 'lineOverflow')) then
    begin
      half := ALineWidth * scale / 2;
      if IsNan(half) or (half < 0) then half := 0;
      clip := AShape;
      clip.W := clip.W + (-half + -half);
      if clip.W < 0 then
      begin
        if half <> 0 then clip.X := clip.X + AShape.W * -half / (-half + -half);
        clip.W := 0;
      end
      else
        clip.X := clip.X - -half;
      clip.H := clip.H + (-half + -half);
      if clip.H < 0 then
      begin
        if half <> 0 then clip.Y := clip.Y + AShape.H * -half / (-half + -half);
        clip.H := 0;
      end
      else
        clip.Y := clip.Y - -half;
      { A TURNED TEXT'S CLIP is the cell's box in its own frame, turned back:
        the port clips to that turned box's bounding box (the same rect at a
        right angle, looser at any other) }
      if rot <> 0 then
      begin
        cl := TyRectApplyMat(TyXYWH(clip.X / scale, clip.Y / scale, clip.W / scale,
          clip.H / scale), mi);
        cl := TyRectApplyMat(cl, m);
        clip := TyXYWH(cl.X * scale, cl.Y * scale, cl.W * scale, cl.H * scale);
      end;
      el.HasClip := True;
      el.ClipRect := TyRectF(clip.X, clip.Y, clip.X + clip.W, clip.Y + clip.H);
    end;
    el.Z := z;
    { traverseUpdateZ: a text content is its host's z2 plus two }
    el.Z2 := AZ2 + 2;
    { THE LABEL'S OWN silent: as written, else answering the pointer only
      for triggerEvent or a shown tooltip; it ignores its host's [Batch 147] }
    d := ChainGet(chain, 'silent');
    if d <> nil then silent := Truthy(d)
    else silent := not (triggerEv or tipShow);
    el.Silent := silent;
    el.Datum := TyChartComponentDatum(ctkMatrix, AMatrix.Index, AInfo);
    AList.Add(el);
    Inc(added);
  end;

  { createMatrixCell }
  procedure AddCell(ACell, AParent: TJSONObject; const AShape: TTyXYWH;
    AHasText: Boolean; const AText: string; AValue: TJSONData; ANormal, ASpecial: Integer;
    AStroke: TTyChartColor; ANoStroke: Boolean; ALocX, ALocY: Integer;
    const ATarget: string);
  var
    s: TCellStyle;
    z2, info: Integer;
    d: TJSONData;
    sh: TTyXYWH;
    rectSilent: Boolean;
    band: Double;
  begin
    info := NewInfo(ATarget, ALocX, ALocY);
    AMatrix.FCellInfos[info].HasText := AHasText;
    AMatrix.FCellInfos[info].Value := AText;
    s := CellStyleOf(ACell, AParent, 'itemStyle', AStroke, ANoStroke);
    { z2: the cell's, its parent's, else special for a cell with its own
      itemStyle }
    d := nil;
    if ACell <> nil then d := ACell.Find('z2');
    if (d = nil) or (d.JSONType <> jtNumber) then
    begin
      d := nil;
      if AParent <> nil then d := AParent.Find('z2');
    end;
    if (d <> nil) and (d.JSONType = jtNumber) then z2 := Trunc(d.AsFloat)
    else if (ACell <> nil) and Truthy(ACell.Find('itemStyle')) then z2 := ASpecial
    else z2 := ANormal;
    { THE RECT'S silent: the cell's, its parent's, else silent unless it is
      filled -- with no fill only the outline would answer, which upstream
      deliberately avoids; written false, it is that outline (zrender's
      stroke band, at least 5 px) and nothing with no stroke [Batch 147] }
    d := nil;
    if ACell <> nil then d := ACell.Find('silent');
    if JNull(d) and (AParent <> nil) then d := AParent.Find('silent');
    if not JNull(d) then rectSilent := Truthy(d)
    else rectSilent := not s.HasFill;
    band := 0;
    if not rectSilent and not s.HasFill then
    begin
      if ((s.Stroke shr 24) <> 0) and (s.LineWidth > 0) then band := Max(s.LineWidth, 5)
      else rectSilent := True;
    end;
    { [F6a] `cursor`: the cell's, its parent's (_tmpCellModel.get) }
    d := nil;
    if ACell <> nil then d := ACell.Find('cursor');
    if JNull(d) and (AParent <> nil) then d := AParent.Find('cursor');
    if (d <> nil) and (d.JSONType = jtString) then rectCursor := d.AsString
    else rectCursor := '';
    sh := AddRect(AShape, s, z2, rectSilent, info, band);
    rectCursor := '';
    if AHasText then
      AddLabel(AText, AValue, ALocX, ALocY, ObjIn(ACell, 'label'), ObjIn(AParent, 'label'),
        sh, s.LineWidth, z2, info);
  end;

  { createBodyOrCornerCells, one cell [Batch 149]: not drawn in another's
    merge; a merge's top-left drawn as its spanRect; its item's option the
    cell's own, its `value` the label }
  procedure AddBodyCorner(AKind, AX, AY: Integer; AParent: TJSONObject;
    AStroke: TTyChartColor; ANoStroke: Boolean; const ATarget: string);
  var
    bc: TTyMatrixBodyCorner;
    c: Integer;
    sh: TTyXYWH;
    opt: TJSONObject;
    v: TJSONData;
  begin
    bc := AMatrix.FBC[AKind];
    c := bc.Find(AX, AY);
    if (c >= 0) and (bc.FCells[c].InSpanOf >= 0) and (bc.FCells[c].InSpanOf <> c) then Exit;
    if (c >= 0) and bc.FCells[c].HasSpan then sh := bc.FCells[c].SpanRect
    else
    begin
      AMatrix.UnitAt(0, AX, sh.X, sh.W);
      AMatrix.UnitAt(1, AY, sh.Y, sh.H);
    end;
    opt := nil;
    if c >= 0 then opt := bc.FCells[c].Option;
    v := nil;
    if opt <> nil then v := opt.Find('value');
    if JNull(v) then
      AddCell(opt, AParent, sh, False, '', nil, TyMatrixZ2BodyNormal, TyMatrixZ2BodySpecial,
        AStroke, ANoStroke, AX, AY, ATarget)
    else
      AddCell(opt, AParent, sh, True, JsStringOf(v), v, TyMatrixZ2BodyNormal,
        TyMatrixZ2BodySpecial, AStroke, ANoStroke, AX, AY, ATarget);
  end;

var
  xd, yd, dm: TTyMatrixDim;
  di, i, ix, iy, nx, ny: Integer;
  c: TTyMatrixCell;
  bodyNode, cornerNode, tip: TJSONObject;
  bg, border: TCellStyle;
  bs: TTyOptStyle;
  none: Boolean;
  d: TJSONData;
  x0, w0, y0, h0: Double;
begin
  Result := 0;
  added := 0;
  if AMatrix <> nil then AMatrix.FCellInfoN := 0;
  if (AMatrix = nil) or not AMatrix.Valid or (AList = nil) then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  z := AMatrix.Z;
  node := AMatrix.Node;
  triggerEv := AMatrix.TriggerEvent;
  tip := AMatrix.TooltipNode;
  tipShow := (tip <> nil) and Truthy(tip.Find('show'));
  xd := AMatrix.Dims[0];
  yd := AMatrix.Dims[1];

  { ---- the header cells, x then y ---- }
  for di := 0 to 1 do
  begin
    dm := AMatrix.Dims[di];
    if not dm.Show then Continue;
    for i := 0 to dm.CellCount - 1 do
    begin
      c := dm.Cells[i];
      if di = 0 then
        AddCell(c.Node, dm.Node, c.Rect, True, c.Value, nil, TyMatrixZ2DimNormal,
          TyMatrixZ2DimSpecial, AInk.CellBorder, False, c.Id[0], c.Id[1], 'x')
      else
        AddCell(c.Node, dm.Node, c.Rect, True, c.Value, nil, TyMatrixZ2DimNormal,
          TyMatrixZ2DimSpecial, AInk.CellBorder, False, c.Id[0], c.Id[1], 'y');
    end;
  end;

  { ---- the body: the y leaves, the x leaves; the cells the body's items
    named carry their options, a merge is drawn once [Batch 149] ---- }
  bodyNode := ObjIn(node, 'body');
  AMatrix.EnsureCellMaps;
  if Int64(xd.LeafCount) * yd.LeafCount <= cMaxBodyCells then
  for iy := 0 to yd.LeafCount - 1 do
    for ix := 0 to xd.LeafCount - 1 do
      AddBodyCorner(0, ix, iy, bodyNode, AInk.CellBorder, False, 'body');

  { ---- the corner, when both trees show: x's levels, y's levels ---- }
  if xd.Show and yd.Show then
  begin
    cornerNode := ObjIn(node, 'corner');
    nx := xd.LevelCount;
    ny := yd.LevelCount;
    for iy := 0 to nx - 1 do
      for ix := 0 to ny - 1 do
        AddBodyCorner(1, ix - ny, iy - nx, cornerNode, 0, True, 'corner');
  end;

  { ---- the background (no border) and the outer border (no fill) ---- }
  bs := TyReadOptStyle(node, 'backgroundStyle');
  bg := Default(TCellStyle);
  if bs.Color.Written then bg.Fill := ColourOf(bs.Color, none) else none := True;
  bg.HasFill := not none;
  bg.Stroke := 0;
  bg.LineWidth := 0;
  if not IsNan(bs.Opacity) then bg.Opacity := bs.Opacity else bg.Opacity := 1;
  AddRect(AMatrix.Rect, bg, TyMatrixZ2Background);
  border := Default(TCellStyle);
  border.HasFill := False;
  if bs.BorderColor.Written then border.Stroke := ColourOf(bs.BorderColor, none)
  else border.Stroke := AInk.OuterBorder;
  if not IsNan(bs.BorderWidthLogical) then border.LineWidth := bs.BorderWidthLogical
  else border.LineWidth := 1;
  border.Opacity := bg.Opacity;
  if bs.Dash <> todNone then
    border.Dash := TyDashPattern(bs.Dash, bs.DashLogical, border.LineWidth);
  outerZ2 := TyMatrixZ2OuterBorder;
  d := nil;
  if node <> nil then d := node.Find('borderZ2');
  if (d <> nil) and (d.JSONType = jtNumber) then outerZ2 := Trunc(d.AsFloat);
  AddRect(AMatrix.Rect, border, outerZ2);

  { ---- the dividers under the x header and beside the y header ---- }
  if xd.UnitOf(0, 0, x0, w0) and yd.UnitOf(1, 0, y0, h0) then
  begin
    if xd.Show then
      AddLine(AMatrix.Rect.X, y0, AMatrix.Rect.X + AMatrix.Rect.W, y0,
        DividerStyleOf(xd.Node, AInk.Divider), outerZ2 - 1);
    if yd.Show then
      AddLine(x0, AMatrix.Rect.Y, x0, AMatrix.Rect.Y + AMatrix.Rect.H,
        DividerStyleOf(yd.Node, AInk.Divider), outerZ2 - 1);
  end;
  Result := added;
end;

initialization
  GLabelDefaults := TJSONObject(GetJSON(
    '{"show": true, "overflow": "break", "lineOverflow": "truncate",'
    + ' "padding": [2, 3, 2, 3], "distance": 0}'));

finalization
  FreeAndNil(GLabelDefaults);

end.
