unit tyControls.AdvChart.Matrix;
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
  and dataToPoint. Ranges, clamping, pointToData, merged cells and the body
  and corner `data` are parts two and three.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Shape, tyControls.AdvChart.Color;

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

  { One matrix component. Built from the option before the series' stores
    (they borrow its category lists), laid out on the canvas with Resize. }
  TTyMatrix = class(TTyNonRefCountedObject, ITyCoordSys)
  private
    FNode: TJSONObject;
    FIndex: Integer;
    FDims: array[0..1] of TTyMatrixDim;
    FBox: TTyRawBox;
    FRect: TTyXYWH;
    FScale: Double;
    FZ: Integer;
    FValid: Boolean;
    procedure LayOutUnits(ADimIdx: Integer);
    procedure LayOutRest(ADimIdx: Integer);
    procedure RectOneDim(var R: TTyXYWH; ADimIdx, AId, ASpan: Integer);
    function UnitAt(ADimIdx, ALocator: Integer; out AXY, AWH: Double): Boolean;
    function GetDim(AIndex: Integer): TTyMatrixDim;
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
    { A COORD AS AN OPTION WRITES IT, to the number the store would hold: a
      string through the tree's category list (NaN when unknown), a number
      as it is, anything else NaN. For callers holding raw JSON. }
    function ParseCoord(ADimIdx: Integer; AValue: TJSONData): Double;
    { ---- ITyCoordSys: data is [x, y], ordinals or locators ---- }
    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;
    function DataToPoint(const AData: array of Double): TTyPointF;
    { Rect and ContentRect alike: a matrix cell has no content inset }
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    { part two (MX2): answers False }
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
{ The picture of one matrix (MatrixView.render), into AList at the matrix's
  z: the header cells (x, then y), the body cells, the corner cells, the
  background, the outer border, the two dividers. A cell label is its own
  element right after its cell, clipped to the cell inside its border. }
function TyBuildMatrix(AMatrix: TTyMatrix; const AInk: TTyMatrixInk;
  const AGlobal: TTyRtGlobal; const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AList: TTyPaintList): Integer;

implementation

uses Classes, tyControls.AdvChart.Scale, tyControls.AdvChart.Calendar,
  tyControls.AdvChart.RichStyle, tyControls.AdvChart.GfxEl,
  tyControls.AdvChart.AnimAxis;

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
  FRect := TyXYWH(NaN, NaN, NaN, NaN);
  FScale := 1;
end;

destructor TTyMatrix.Destroy;
begin
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
  FValid := True;
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

function TTyMatrix.Locate(ADimIdx: Integer; AValue: Double; out AXY, AWH: Double): Boolean;
var
  d: TTyMatrixDim;
  ci, locA, locB, lo, hi: Integer;
  r, xy0, wh0, xy1, wh1: Double;
begin
  AXY := NaN;
  AWH := NaN;
  Result := False;
  d := FDims[ADimIdx];
  { coordDataToAllCellLevelLayout: a header cell by its ordinal, else a
    negative number is the other tree's level }
  ci := d.CellIndexOf(AValue);
  if ci >= 0 then
  begin
    locA := d.FCells[ci].Id[ADimIdx];
    locB := locA + d.FCells[ci].Span[ADimIdx] - 1;
  end
  else
  begin
    if IsNan(AValue) or not (AValue < 0) or IsInfinite(AValue) then Exit;
    r := TyJsRound(AValue);
    if r < -FDims[1 - ADimIdx].LevelCount then Exit;
    locA := Trunc(r);
    if not FDims[1 - ADimIdx].UnitOf(ADimIdx, locA, xy0, wh0) then Exit;
    locB := locA;
  end;
  lo := Min(locA, locB);
  hi := Max(locA, locB);
  { xyLocatorRangeToRectOneDim: the two ends' units }
  if not UnitAt(ADimIdx, lo, xy0, wh0) then Exit;
  if not UnitAt(ADimIdx, hi, xy1, wh1) then Exit;
  AXY := xy0;
  AWH := xy1 + wh1 - xy0;
  Result := True;
end;

procedure TTyMatrix.DataToLayoutXYWH(AX, AY: Double; out ARect: TTyXYWH);
begin
  Locate(0, AX, ARect.X, ARect.W);
  Locate(1, AY, ARect.Y, ARect.H);
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
  AData := nil;
  Result := False;
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
  if a.Color.Written then c := ColourOf(a.Color, none)
  else if b.Color.Written then c := ColourOf(b.Color, none);
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

function TyBuildMatrix(AMatrix: TTyMatrix; const AInk: TTyMatrixInk;
  const AGlobal: TTyRtGlobal; const AMeasurer: ITyTextMeasurer; APPI: Integer;
  AList: TTyPaintList): Integer;
var
  scale: Double;
  z, outerZ2, added: Integer;
  node: TJSONObject;

  { createMatrixRect: the edges on the pixel grid of the border's width;
    answers the shape drawn }
  function AddRect(const AShape: TTyXYWH; const S: TCellStyle; AZ2: Integer): TTyXYWH;
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
    el.Style.HasFill := S.HasFill and ((S.Fill shr 24) <> 0);
    el.Style.FillColor := S.Fill;
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
  procedure AddLabel(const AText: string; ALocX, ALocY: Integer;
    ACellLabel, AParentLabel: TJSONObject; const AShape: TTyXYWH;
    ALineWidth: Double; AZ2: Integer);
  var
    chain: array[0..2] of TJSONObject;
    text, fam, alignS, valignS: string;
    d: TJSONData;
    rt: TTyRtBlockStyle;
    size, weight: Integer;
    tx, ty, dist, ox, oy, ix, iy, iw, ih, baseX, baseY, padH, padV, half: Double;
    align: TTyRtAlign;
    valign: TTyRtVAlign;
    pieces: TTyRtPieceArray;
    el: TTyChartElement;
    ah: TTyTextAnchorH;
    av: TTyTextAnchorV;
    clip: TTyXYWH;
  begin
    chain[0] := ACellLabel;
    chain[1] := AParentLabel;
    chain[2] := GLabelDefaults;
    if not Truthy(ChainGet(chain, 'show')) then Exit;
    text := AText;
    d := ChainGet(chain, 'formatter');
    if (d <> nil) and (d.JSONType = jtString) then
      { formatTplSimple over the params, in their order }
      text := TyCalFormatTpl(d.AsString,
        ['componentType', 'componentIndex', 'name', 'value', 'coord', '$vars'],
        ['matrix', IntToStr(AMatrix.Index), AText, AText,
         IntToStr(ALocX) + ',' + IntToStr(ALocY), 'name,value,coord']);
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
    { calculateTextPosition on the shape, then the offset }
    dist := NumberOr(ChainGet(chain, 'distance'), 0) * scale;
    TyGfxTextPosition(ChainGet(chain, 'position'), dist, AShape, tx, ty, alignS, valignS);
    d := ChainGet(chain, 'offset');
    if (d is TJSONArray) and (d.Count >= 2) then
    begin
      tx := tx + NumberOr(d.Items[0], 0) * scale;
      ty := ty + NumberOr(d.Items[1], 0) * scale;
    end;
    if IsNan(tx) or IsNan(ty) then Exit;
    align := rt.Style.Align;
    if align = rtaNone then align := AlignOfWord(alignS);
    if align = rtaNone then align := rtaLeft;
    valign := rt.Style.VAlign;
    if valign = rtvNone then valign := VAlignOfWord(valignS);
    if valign = rtvNone then valign := rtvTop;
    { THE OVERFLOW AREA: the shape in the text's own frame, met by a box
      twice its size hung at the base by the alignment; the base moves to
      the meeting, the meeting is the room }
    ox := AShape.X + -tx;
    oy := AShape.Y + -ty;
    if Abs(scale - 1) > 1e-12 then
    begin
      ox := ox / scale;
      oy := oy / scale;
    end;
    Intersect1(ox, ox + AShape.W / scale, AdjX(0, AShape.W / scale * 2, align, False),
      AdjX(0, AShape.W / scale * 2, align, False) + AShape.W / scale * 2, ix, iw);
    Intersect1(oy, oy + AShape.H / scale, AdjY(0, AShape.H / scale * 2, valign, False),
      AdjY(0, AShape.H / scale * 2, valign, False) + AShape.H / scale * 2, iy, ih);
    baseX := AdjX(ix, iw, align, True);
    baseY := AdjY(iy, ih, valign, True);
    if not rt.IsRich then
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
    el := TyChartElement(TyShapeRect(TyRtDeviceBox(pieces, tx, ty, 0, scale)));
    el.Caption.Text := text;
    el.Caption.FontName := fam;
    el.Caption.FontSizeLogical := size;
    el.Caption.FontWeight := weight;
    el.Caption.Colour := rt.Style.Fill;
    el.Caption.X := tx;
    el.Caption.Y := ty;
    el.Caption.AnchorH := ah;
    el.Caption.AnchorV := av;
    el.Caption.RotationRad := 0;
    el.Caption.RtPieces := pieces;
    el.Caption.RtScale := scale;
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
      el.HasClip := True;
      el.ClipRect := TyRectF(clip.X, clip.Y, clip.X + clip.W, clip.Y + clip.H);
    end;
    el.Z := z;
    { traverseUpdateZ: a text content is its host's z2 plus two }
    el.Z2 := AZ2 + 2;
    el.Silent := True;
    AList.Add(el);
    Inc(added);
  end;

  { createMatrixCell }
  procedure AddCell(ACell, AParent: TJSONObject; const AShape: TTyXYWH;
    AHasText: Boolean; const AText: string; ANormal, ASpecial: Integer;
    AStroke: TTyChartColor; ANoStroke: Boolean; ALocX, ALocY: Integer);
  var
    s: TCellStyle;
    z2: Integer;
    d: TJSONData;
    sh: TTyXYWH;
  begin
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
    sh := AddRect(AShape, s, z2);
    if AHasText then
      AddLabel(AText, ALocX, ALocY, ObjIn(ACell, 'label'), ObjIn(AParent, 'label'),
        sh, s.LineWidth, z2);
  end;

var
  xd, yd, dm: TTyMatrixDim;
  di, i, ix, iy, nx, ny: Integer;
  sh: TTyXYWH;
  c: TTyMatrixCell;
  bodyNode, cornerNode: TJSONObject;
  bg, border: TCellStyle;
  bs: TTyOptStyle;
  none: Boolean;
  d: TJSONData;
  x0, w0, y0, h0: Double;
begin
  Result := 0;
  added := 0;
  if (AMatrix = nil) or not AMatrix.Valid or (AList = nil) then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  z := AMatrix.Z;
  node := AMatrix.Node;
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
      AddCell(c.Node, dm.Node, c.Rect, True, c.Value, TyMatrixZ2DimNormal,
        TyMatrixZ2DimSpecial, AInk.CellBorder, False, c.Id[0], c.Id[1]);
    end;
  end;

  { ---- the body: the y leaves, the x leaves ---- }
  bodyNode := ObjIn(node, 'body');
  if Int64(xd.LeafCount) * yd.LeafCount <= cMaxBodyCells then
  for iy := 0 to yd.LeafCount - 1 do
    for ix := 0 to xd.LeafCount - 1 do
    begin
      xd.UnitOf(0, ix, sh.X, sh.W);
      yd.UnitOf(1, iy, sh.Y, sh.H);
      AddCell(nil, bodyNode, sh, False, '', TyMatrixZ2BodyNormal, TyMatrixZ2BodySpecial,
        AInk.CellBorder, False, ix, iy);
    end;

  { ---- the corner, when both trees show: x's levels, y's levels ---- }
  if xd.Show and yd.Show then
  begin
    cornerNode := ObjIn(node, 'corner');
    nx := xd.LevelCount;
    ny := yd.LevelCount;
    for iy := 0 to nx - 1 do
      for ix := 0 to ny - 1 do
      begin
        yd.UnitOf(0, ix - ny, sh.X, sh.W);
        xd.UnitOf(1, iy - nx, sh.Y, sh.H);
        AddCell(nil, cornerNode, sh, False, '', TyMatrixZ2BodyNormal, TyMatrixZ2BodySpecial,
          0, True, ix - ny, iy - nx);
      end;
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
