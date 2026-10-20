unit tyControls.AdvanceChart.SeriesEdit;
{$mode objfpc}{$H+}
{ The design-time series and data editor's whole model. [Batch 143]

  WHY THIS IS IN source/ AND NOT BESIDE THE DIALOG. The same reason Complete,
  Locate and Diagnose are: designtime/ is outside the test build, so anything
  decided in there is decided with nothing behind it. Everything the series
  dialog does to an option -- which series there are and what to call them,
  which keys a series type offers, what a grid cell turns into, what deleting
  a row on a category axis deletes, what goes back into the text and what it
  costs -- is a function here. The dialog puts it in boxes; a guard in
  tests/test.advchart.serieseditor.pas reads the dialog's file and fails if it
  ever touches fcl-json itself.

  WHAT IT EDITS. A tree read from the user's text with the option's own reader
  (TyOptionParseRaw: no preprocessor, no merge -- the tree as written), edited
  in place, and written back by TTyOptTextPatcher, which changes only the text
  of what changed. Loading and writing back with no edit in between gives the
  text back byte for byte; every key the editor does not know about, in every
  series it does, is carried along untouched because it is never looked at.

  THE GRID. A series' data (or a dataset's source) is shown as a table of
  strings, TTyEditTable. The table keeps a snapshot of what it was built from
  and the original text of every cell, and Apply recomputes the data from the
  snapshot and the cells -- so applying is idempotent (the dialog applies on
  every keystroke) and a cell nobody changed keeps its exact JSON: the string
  '2015' in a dataset header stays a string, a 120 stays the integer it was.

  LCL-free: SysUtils, Classes, fcl-json and the AdvanceChart units. }
interface
uses
  SysUtils, Classes, fpjson,
  tyControls.AdvanceChart.TextPatch, tyControls.AdvanceChart.Diagnose;

type
  { How a per-series key is edited. }
  TTySeriesFieldKind = (
    { a string; empty removes the key }
    sfkText,
    { a whole number }
    sfkInteger,
    { three states: absent, true, false }
    sfkBoolean,
    { a string, or -- when it starts with a brace or a bracket -- a literal
      (a gradient) }
    sfkColor,
    { any value, written as option text: encode's object of dimensions }
    sfkLiteral);

  TTySeriesField = record
    { Under the series: 'name', 'label.show'. }
    Path: string;
    Kind: TTySeriesFieldKind;
  end;
  TTySeriesFieldArray = array of TTySeriesField;

  TTyFieldState = (fsAbsent, fsTrue, fsFalse);

  TTyEditColKind = (
    { the category axis' names, one per row }
    eckCategory,
    { a data item's `name` }
    eckName,
    { a dimension of the value, or a dataset column }
    eckValue);

  TTyEditCol = record
    Caption: string;
    Kind: TTyEditColKind;
    { the dimension (or dataset column, or object key index) it came from,
      -1 for a column added in the grid }
    Origin: Integer;
    { the key an object-row dataset column reads }
    Key: string;
  end;

  TTyEditCell = record
    Text: string;
    { the text the cell was built with, when HasOrig }
    Orig: string;
    HasOrig: Boolean;
  end;

  TTyEditRow = record
    { the index in the snapshot it was built from, -1 for a row added }
    Origin: Integer;
    Cells: array of TTyEditCell;
  end;

  TTyAlignedData = record
    Series: Integer;
    Data: TJSONArray;
  end;

  { A list shown as a grid of strings. Built by the model, edited by the
    dialog, applied by the model. }
  TTyEditTable = class
  private
    FCols: array of TTyEditCol;
    FRows: array of TTyEditRow;
    FEditable: Boolean;
    FNote: string;
    { dataset: how many leading rows are the header }
    FHeaderRows: Integer;
    FObjectRows: Boolean;
    FIsDataset: Boolean;
    FOwner: Integer;
    FHadData: Boolean;
    FColsDeleted: Boolean;
    FSnap: TJSONArray;
    FCats: TJSONArray;
    FCatKey: string;
    FCatIndex: Integer;
    FAligned: array of TTyAlignedData;
    FSnapRows: Integer;
    function GetCell(ACol, ARow: Integer): string;
    procedure SetCell(ACol, ARow: Integer; const AValue: string);
    procedure AddCol(const ACaption: string; AKind: TTyEditColKind;
      AOrigin: Integer; const AKey: string = '');
    function AddRowRaw(AOrigin: Integer): Integer;
    procedure Put(ACol, ARow: Integer; const AText: string; AHasOrig: Boolean);
    function CellChanged(ACol, ARow: Integer): Boolean;
    function ValueColCount: Integer;
  public
    destructor Destroy; override;
    function ColCount: Integer;
    function RowCount: Integer;
    function ColCaption(ACol: Integer): string;
    function ColKind(ACol: Integer): TTyEditColKind;
    { A dataset header row: its cells stay strings. }
    function RowIsHeader(ARow: Integer): Boolean;
    property Cells[ACol, ARow: Integer]: string read GetCell write SetCell;
    procedure AppendRow;
    procedure DeleteRow(ARow: Integer);
    function CanAddColumn: Boolean;
    procedure AppendColumn;
    function CanDeleteColumn(ACol: Integer): Boolean;
    procedure DeleteColumn(ACol: Integer);
    { False when the list is not something a grid can show -- a tree's
      children, a column-keyed dataset; Note says why. }
    property Editable: Boolean read FEditable;
    { One sentence for under the grid, or ''. }
    property Note: string read FNote;
  end;

  TTySeriesEditModel = class
  private
    FText: string;
    FOrig: TJSONData;
    FWork: TJSONObject;
    FPatcher: TTyOptTextPatcher;
    FHadValue: Boolean;
    FError: string;
    FErrorLine, FErrorCol: Integer;
    FLost: Integer;
    FWhole: Boolean;
    { per series in the working list: its index in the original list, -1 when
      it was added here }
    FOrigin: array of Integer;
    procedure Reset;
    function SeriesSlot: TJSONData;
    function SeriesList: TJSONArray;
    function OrigSeries(AIndex: Integer): TJSONObject;
    function FieldKindOf(const APath: string; out AKind: TTySeriesFieldKind): Boolean;
    procedure PutPath(AIndex: Integer; const APath: string; AValue: TJSONData);
    procedure DropPath(AIndex: Integer; const APath: string);
    function CategoryAxisOf(ANode: TJSONObject; out AKey: string;
      out AIndex: Integer; out AData: TJSONArray): Boolean;
    function Style: TTyOptTextStyle;
  public
    constructor Create;
    destructor Destroy; override;

    { Read AText. False -- with Error, ErrorLine, ErrorCol -- when it does not
      parse or is not an object; the model is then empty. Empty text is an
      empty option. }
    function Load(const AText: string): Boolean;
    property Error: string read FError;
    property ErrorLine: Integer read FErrorLine;
    property ErrorCol: Integer read FErrorCol;

    { ---- the series list ---- }
    function SeriesCount: Integer;
    { nil for a slot that holds no object (a null hole) }
    function SeriesNode(AIndex: Integer): TJSONObject;
    function SeriesType(AIndex: Integer): string;
    { what the list shows: index, type and name }
    function SeriesCaption(AIndex: Integer): string;
    procedure SetSeriesType(AIndex: Integer; const AType: string);
    { a new series of AType at the end; its index }
    function AddSeries(const AType: string): Integer;
    procedure DeleteSeries(AIndex: Integer);
    procedure MoveSeries(AFrom, ATo: Integer);

    { ---- the common keys ---- }
    { the keys this series' type has, in a fixed order }
    function Fields(AIndex: Integer): TTySeriesFieldArray;
    function FieldText(AIndex: Integer; const APath: string): string;
    function FieldState(AIndex: Integer; const APath: string): TTyFieldState;
    { False with AError when AText is not a value of the field's kind; the
      option is then unchanged. Empty text removes the key. }
    function SetFieldText(AIndex: Integer; const APath, AText: string;
      out AError: string): Boolean;
    procedure SetFieldState(AIndex: Integer; const APath: string;
      AState: TTyFieldState);

    { ---- the data ---- }
    { the caller frees the table }
    function SeriesTable(AIndex: Integer): TTyEditTable;
    procedure ApplySeriesTable(ATable: TTyEditTable);
    function DatasetCount: Integer;
    function DatasetTable(AIndex: Integer): TTyEditTable;
    procedure ApplyDatasetTable(ATable: TTyEditTable);

    { ---- writing back ---- }
    { The text with every edit patched in; the loaded text itself when
      nothing changed. }
    function Text: string;
    { After Text: comments the write drops. }
    property Lost: Integer read FLost;
    { After Text: the text could not be patched piece by piece and is
      written out whole. }
    property RewritesWhole: Boolean read FWhole;
    { After Text: whether writing it back should be confirmed first. }
    function NeedsConfirm: Boolean;
    function Changed: Boolean;
    { what the option editor would say about Text }
    function Diagnose: TTyOptDiagArray;
    property Tree: TJSONObject read FWork;
  end;

{ The series types the catalog knows, in its order. }
procedure TySeriesTypes(AList: TStrings);

{ A value written as option text -- an object, `'red'`, `[1, 2]` --
  read with the option's own reader. }
function TyOptParseLiteral(const AText: string; out AData: TJSONData;
  out AError: string): Boolean;

{ What a grid cell shows for a value: a string as it is, a number as JS
  prints it, null as nothing, anything else as compact option text. }
function TyEditCellText(AData: TJSONData): string;

{ What a typed cell becomes: a string when AKeepString (a header, a name, a
  cell that held a string); otherwise null for nothing, true / false / null,
  a number when it reads as one, a literal when it starts with a bracket or
  a brace and
  parses, a string for anything else. }
function TyEditCellValue(const AText: string; AKeepString: Boolean): TJSONData;

implementation

uses
  tyControls.StrConsts, tyControls.AdvanceChart.Option,
  tyControls.AdvanceChart.Complete, tyControls.AdvanceChart.Builder,
  tyControls.AdvanceChart.Coord;

const
  cFields: array[0..15] of TTySeriesField = (
    (Path: 'name'; Kind: sfkText),
    (Path: 'coordinateSystem'; Kind: sfkText),
    (Path: 'xAxisIndex'; Kind: sfkInteger),
    (Path: 'yAxisIndex'; Kind: sfkInteger),
    (Path: 'polarIndex'; Kind: sfkInteger),
    (Path: 'radarIndex'; Kind: sfkInteger),
    (Path: 'singleAxisIndex'; Kind: sfkInteger),
    (Path: 'parallelIndex'; Kind: sfkInteger),
    (Path: 'calendarIndex'; Kind: sfkInteger),
    (Path: 'geoIndex'; Kind: sfkInteger),
    (Path: 'datasetIndex'; Kind: sfkInteger),
    (Path: 'stack'; Kind: sfkText),
    (Path: 'smooth'; Kind: sfkBoolean),
    (Path: 'label.show'; Kind: sfkBoolean),
    (Path: 'itemStyle.color'; Kind: sfkColor),
    (Path: 'encode'; Kind: sfkLiteral));

{ ---- helpers --------------------------------------------------------------- }

function ComponentOf(ARoot: TJSONObject; const AKey: string; AIndex: Integer): TJSONData;
var d: TJSONData;
begin
  { normalizeToArray, as TTyChartOption.ComponentAt reads a slot }
  Result := nil;
  if (ARoot = nil) or (AIndex < 0) then Exit;
  d := ARoot.Find(AKey);
  if d = nil then Exit;
  if d is TJSONArray then
  begin
    if AIndex < d.Count then Result := d.Items[AIndex];
  end
  else if (d is TJSONObject) and (AIndex = 0) then
    Result := d;
end;

function ComponentCountOf(ARoot: TJSONObject; const AKey: string): Integer;
var d: TJSONData;
begin
  Result := 0;
  if ARoot = nil then Exit;
  d := ARoot.Find(AKey);
  if d is TJSONArray then Result := d.Count
  else if d is TJSONObject then Result := 1;
end;

function FindPath(ANode: TJSONData; const APath: string): TJSONData;
var
  rest, seg: string;
  p: Integer;
begin
  Result := ANode;
  rest := APath;
  while (Result <> nil) and (rest <> '') do
  begin
    p := Pos('.', rest);
    if p > 0 then
    begin
      seg := Copy(rest, 1, p - 1);
      rest := Copy(rest, p + 1, MaxInt);
    end
    else
    begin
      seg := rest;
      rest := '';
    end;
    if Result is TJSONObject then Result := TJSONObject(Result).Find(seg)
    else Result := nil;
  end;
end;

function IntOf(ANode: TJSONObject; const AKey: string; ADefault: Integer): Integer;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    if (d.AsFloat >= -MaxInt) and (d.AsFloat <= MaxInt) then
      Result := Trunc(d.AsFloat);
  end;
end;

function StrOf(ANode: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

{ Replace or add AKey in place: a key that exists keeps its position. }
procedure SetKey(AObj: TJSONObject; const AKey: string; AValue: TJSONData);
begin
  if AObj.IndexOfName(AKey) >= 0 then AObj.Elements[AKey] := AValue
  else AObj.Add(AKey, AValue);
end;

{ Replace AKey only when the new value differs, so a no-op write leaves the
  exact JSON (an integer stays an integer) for the patcher to keep. }
procedure SetKeyIfChanged(AObj: TJSONObject; const AKey: string; AValue: TJSONData);
begin
  if TyOptJsonSame(AObj.Find(AKey), AValue) then AValue.Free
  else SetKey(AObj, AKey, AValue);
end;

function IsJsonNumber(const S: string; out AIsInt: Boolean): Boolean;
var
  i, n, digits: Integer;
begin
  { JSON's number grammar, which is also the literal the option reader
    takes: -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)? -- with the reader's
    leniency for a leading '.' and leading zeros left out on purpose: a cell
    typed '007' is an id, not seven. }
  Result := False;
  AIsInt := True;
  n := Length(S);
  i := 1;
  if (i <= n) and (S[i] = '-') then Inc(i);
  if i > n then Exit;
  if S[i] = '0' then Inc(i)
  else if S[i] in ['1'..'9'] then
    while (i <= n) and (S[i] in ['0'..'9']) do Inc(i)
  else Exit;
  if (i <= n) and (S[i] = '.') then
  begin
    AIsInt := False;
    Inc(i);
    digits := 0;
    while (i <= n) and (S[i] in ['0'..'9']) do begin Inc(i); Inc(digits); end;
    if digits = 0 then Exit;
  end;
  if (i <= n) and (S[i] in ['e', 'E']) then
  begin
    AIsInt := False;
    Inc(i);
    if (i <= n) and (S[i] in ['+', '-']) then Inc(i);
    digits := 0;
    while (i <= n) and (S[i] in ['0'..'9']) do begin Inc(i); Inc(digits); end;
    if digits = 0 then Exit;
  end;
  Result := i > n;
end;

function TyEditCellValue(const AText: string; AKeepString: Boolean): TJSONData;
var
  t, err: string;
  isInt: Boolean;
  i64: Int64;
  f: Double;
  fs: TFormatSettings;
  lit: TJSONData;
begin
  if AKeepString then Exit(TJSONString.Create(AText));
  t := Trim(AText);
  if t = '' then Exit(TJSONNull.Create);
  if t = 'true' then Exit(TJSONBoolean.Create(True));
  if t = 'false' then Exit(TJSONBoolean.Create(False));
  if t = 'null' then Exit(TJSONNull.Create);
  if IsJsonNumber(t, isInt) then
  begin
    if isInt and TryStrToInt64(t, i64) then
    begin
      if (i64 >= Low(Integer)) and (i64 <= High(Integer)) then
        Exit(TJSONIntegerNumber.Create(Integer(i64)))
      else
        Exit(TJSONInt64Number.Create(i64));
    end;
    fs := DefaultFormatSettings;
    fs.DecimalSeparator := '.';
    fs.ThousandSeparator := #0;
    if TryStrToFloat(t, f, fs) then Exit(TJSONFloatNumber.Create(f));
  end;
  if t[1] in ['[', '{'] then
    if TyOptParseLiteral(t, lit, err) then Exit(lit);
  Result := TJSONString.Create(AText);
end;

function TyEditCellText(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit('');
  if AData.JSONType = jtString then Exit(AData.AsString);
  Result := TyOptJsonCompact(AData, TyOptDefaultTextStyle);
end;

function TyOptParseLiteral(const AText: string; out AData: TJSONData;
  out AError: string): Boolean;
var
  d: TJSONData;
  err: TTyOptionError;
begin
  { Through the option's own reader -- the nesting guard, the escape decode,
    the relaxed spelling -- by wrapping the literal as the one member of an
    object. The line break keeps a trailing // comment from eating the brace. }
  AData := nil;
  AError := '';
  Result := False;
  if Trim(AText) = '' then
  begin
    AError := rsTySerEdEmptyLiteral;
    Exit;
  end;
  if not TyOptionParseRaw('{"v":' + AText + #10'}', d, err) then
  begin
    AError := err.Message;
    Exit;
  end;
  try
    if not (d is TJSONObject) or (d.Count <> 1)
      or (TJSONObject(d).Names[0] <> 'v') then
    begin
      AError := rsTySerEdOneValue;
      Exit;
    end;
    AData := TJSONObject(d).Extract(0);
    Result := True;
  finally
    d.Free;
  end;
end;

procedure TySeriesTypes(AList: TStrings);
var lk: TTyOptLookup;
begin
  AList.Clear;
  lk := TyOptFind('series');
  if lk.Found then TyOptVariantTags(lk.Node, AList);
end;

{ ---- the table ----------------------------------------------------------- }

destructor TTyEditTable.Destroy;
var i: Integer;
begin
  FSnap.Free;
  FCats.Free;
  for i := 0 to High(FAligned) do FAligned[i].Data.Free;
  inherited Destroy;
end;

function TTyEditTable.ColCount: Integer;
begin
  Result := Length(FCols);
end;

function TTyEditTable.RowCount: Integer;
begin
  Result := Length(FRows);
end;

function TTyEditTable.ColCaption(ACol: Integer): string;
begin
  Result := FCols[ACol].Caption;
end;

function TTyEditTable.ColKind(ACol: Integer): TTyEditColKind;
begin
  Result := FCols[ACol].Kind;
end;

function TTyEditTable.RowIsHeader(ARow: Integer): Boolean;
begin
  Result := FIsDataset and (FRows[ARow].Origin >= 0)
    and (FRows[ARow].Origin < FHeaderRows);
end;

function TTyEditTable.GetCell(ACol, ARow: Integer): string;
begin
  Result := FRows[ARow].Cells[ACol].Text;
end;

procedure TTyEditTable.SetCell(ACol, ARow: Integer; const AValue: string);
begin
  FRows[ARow].Cells[ACol].Text := AValue;
end;

procedure TTyEditTable.AddCol(const ACaption: string; AKind: TTyEditColKind;
  AOrigin: Integer; const AKey: string);
var
  i, n: Integer;
begin
  n := Length(FCols);
  SetLength(FCols, n + 1);
  FCols[n].Caption := ACaption;
  FCols[n].Kind := AKind;
  FCols[n].Origin := AOrigin;
  FCols[n].Key := AKey;
  for i := 0 to High(FRows) do
  begin
    SetLength(FRows[i].Cells, n + 1);
    FRows[i].Cells[n].Text := '';
    FRows[i].Cells[n].Orig := '';
    FRows[i].Cells[n].HasOrig := False;
  end;
end;

function TTyEditTable.AddRowRaw(AOrigin: Integer): Integer;
var c: Integer;
begin
  Result := Length(FRows);
  SetLength(FRows, Result + 1);
  FRows[Result].Origin := AOrigin;
  SetLength(FRows[Result].Cells, Length(FCols));
  for c := 0 to High(FCols) do
  begin
    FRows[Result].Cells[c].Text := '';
    FRows[Result].Cells[c].Orig := '';
    FRows[Result].Cells[c].HasOrig := False;
  end;
end;

procedure TTyEditTable.Put(ACol, ARow: Integer; const AText: string; AHasOrig: Boolean);
begin
  FRows[ARow].Cells[ACol].Text := AText;
  FRows[ARow].Cells[ACol].Orig := AText;
  FRows[ARow].Cells[ACol].HasOrig := AHasOrig;
end;

function TTyEditTable.CellChanged(ACol, ARow: Integer): Boolean;
begin
  if FRows[ARow].Cells[ACol].HasOrig then
    Result := FRows[ARow].Cells[ACol].Text <> FRows[ARow].Cells[ACol].Orig
  else
    Result := FRows[ARow].Cells[ACol].Text <> '';
end;

function TTyEditTable.ValueColCount: Integer;
var c: Integer;
begin
  Result := 0;
  for c := 0 to High(FCols) do
    if FCols[c].Kind = eckValue then Inc(Result);
end;

procedure TTyEditTable.AppendRow;
begin
  if FEditable then AddRowRaw(-1);
end;

procedure TTyEditTable.DeleteRow(ARow: Integer);
var i: Integer;
begin
  if (not FEditable) or (ARow < 0) or (ARow > High(FRows)) then Exit;
  for i := ARow to High(FRows) - 1 do FRows[i] := FRows[i + 1];
  SetLength(FRows, Length(FRows) - 1);
end;

function TTyEditTable.CanAddColumn: Boolean;
begin
  { A category grid is one value per category: a second column would turn
    the items into pairs and the categories would stop being the rows. An
    object-row dataset's columns are its keys, and a key needs a name. }
  Result := FEditable and (FCats = nil) and not FObjectRows;
end;

procedure TTyEditTable.AppendColumn;
var cap: string;
begin
  if not CanAddColumn then Exit;
  cap := Format(rsTySerEdColDim, [ValueColCount]);
  AddCol(cap, eckValue, -1);
end;

function TTyEditTable.CanDeleteColumn(ACol: Integer): Boolean;
begin
  Result := FEditable and (not FObjectRows) and (ACol >= 0)
    and (ACol <= High(FCols)) and (FCols[ACol].Kind = eckValue)
    and (ValueColCount > 1);
end;

procedure TTyEditTable.DeleteColumn(ACol: Integer);
var i, c: Integer;
begin
  if not CanDeleteColumn(ACol) then Exit;
  for c := ACol to High(FCols) - 1 do FCols[c] := FCols[c + 1];
  SetLength(FCols, Length(FCols) - 1);
  for i := 0 to High(FRows) do
  begin
    for c := ACol to High(FRows[i].Cells) - 1 do
      FRows[i].Cells[c] := FRows[i].Cells[c + 1];
    SetLength(FRows[i].Cells, Length(FRows[i].Cells) - 1);
  end;
  FColsDeleted := True;
end;

{ ---- the model --------------------------------------------------------------- }

constructor TTySeriesEditModel.Create;
begin
  inherited Create;
  FWork := TJSONObject.Create;
end;

destructor TTySeriesEditModel.Destroy;
begin
  Reset;
  FWork.Free;
  inherited Destroy;
end;

procedure TTySeriesEditModel.Reset;
begin
  FreeAndNil(FPatcher);
  FreeAndNil(FOrig);
  FreeAndNil(FWork);
  FWork := TJSONObject.Create;
  FOrigin := nil;
  FText := '';
  FHadValue := False;
  FError := '';
  FErrorLine := 0;
  FErrorCol := 0;
  FLost := 0;
  FWhole := False;
end;

function TTySeriesEditModel.Load(const AText: string): Boolean;
var
  d: TJSONData;
  err: TTyOptionError;
  i: Integer;
begin
  Reset;
  FText := AText;
  if not TyOptionParseRaw(AText, d, err) then
  begin
    FError := err.Message;
    FErrorLine := err.Line;
    FErrorCol := err.Col;
    Exit(False);
  end;
  if d = nil then
    { nothing written yet: an empty option, which the first edit writes out
      whole -- there is no layout to keep }
    d := TJSONObject.Create
  else
    FHadValue := True;
  if not (d is TJSONObject) then
  begin
    d.Free;
    FHadValue := False;
    FError := rsTySerEdNotObject;
    Exit(False);
  end;
  FOrig := d;
  FWork.Free;
  FWork := TJSONObject(FOrig.Clone);
  FPatcher := TTyOptTextPatcher.Create(AText, FOrig);
  SetLength(FOrigin, SeriesCount);
  for i := 0 to High(FOrigin) do FOrigin[i] := i;
  Result := True;
end;

function TTySeriesEditModel.SeriesSlot: TJSONData;
begin
  Result := FWork.Find('series');
end;

function TTySeriesEditModel.SeriesList: TJSONArray;
var
  slot, one: TJSONData;
  idx: Integer;
begin
  slot := SeriesSlot;
  if slot is TJSONArray then Exit(TJSONArray(slot));
  Result := TJSONArray.Create;
  idx := FWork.IndexOfName('series');
  if slot is TJSONObject then
  begin
    { the bare form becomes the array form the moment the list changes shape:
      a list of one is still a list }
    one := FWork.Extract(idx);
    Result.Add(one);
    FWork.Add('series', Result);
  end
  else if idx >= 0 then
    FWork.Elements['series'] := Result
  else
    FWork.Add('series', Result);
end;

function TTySeriesEditModel.SeriesCount: Integer;
begin
  Result := ComponentCountOf(FWork, 'series');
end;

function TTySeriesEditModel.SeriesNode(AIndex: Integer): TJSONObject;
var d: TJSONData;
begin
  d := ComponentOf(FWork, 'series', AIndex);
  if d is TJSONObject then Result := TJSONObject(d) else Result := nil;
end;

function TTySeriesEditModel.OrigSeries(AIndex: Integer): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(FOrigin)) or (FOrigin[AIndex] < 0) then Exit;
  if not (FOrig is TJSONObject) then Exit;
  d := ComponentOf(TJSONObject(FOrig), 'series', FOrigin[AIndex]);
  if d is TJSONObject then Result := TJSONObject(d);
end;

function TTySeriesEditModel.SeriesType(AIndex: Integer): string;
begin
  Result := StrOf(SeriesNode(AIndex), 'type');
end;

function TTySeriesEditModel.SeriesCaption(AIndex: Integer): string;
var
  node: TJSONObject;
  tp, nm: string;
begin
  node := SeriesNode(AIndex);
  if node = nil then Exit(Format(rsTySerEdCaption, [AIndex, rsTySerEdHole]));
  tp := StrOf(node, 'type');
  if tp = '' then tp := rsTySerEdNoType;
  nm := TyEditCellText(node.Find('name'));
  if nm = '' then Result := Format(rsTySerEdCaption, [AIndex, tp])
  else Result := Format(rsTySerEdCaptionNamed, [AIndex, tp, nm]);
end;

procedure TTySeriesEditModel.SetSeriesType(AIndex: Integer; const AType: string);
begin
  if SeriesNode(AIndex) = nil then Exit;
  if Trim(AType) = '' then DropPath(AIndex, 'type')
  else PutPath(AIndex, 'type', TJSONString.Create(Trim(AType)));
end;

function TTySeriesEditModel.AddSeries(const AType: string): Integer;
var
  node: TJSONObject;
  list: TJSONArray;
  i, n: Integer;
  ownData: Boolean;
begin
  { A new series gets `data: []` -- something for the grid to fill -- except
    in an option that draws from a dataset and whose series bring no data of
    their own: there an empty data array would win over the dataset and the
    new series would draw nothing. }
  ownData := FWork.Find('dataset') = nil;
  n := SeriesCount;
  for i := 0 to n - 1 do
    if (SeriesNode(i) <> nil) and (SeriesNode(i).Find('data') <> nil) then
      ownData := True;
  node := TJSONObject.Create;
  if Trim(AType) <> '' then node.Add('type', Trim(AType));
  if ownData then node.Add('data', TJSONArray.Create);
  list := SeriesList;
  Result := list.Add(node);
  SetLength(FOrigin, Result + 1);
  FOrigin[Result] := -1;
end;

procedure TTySeriesEditModel.DeleteSeries(AIndex: Integer);
var
  list: TJSONArray;
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= SeriesCount) then Exit;
  list := SeriesList;
  list.Delete(AIndex);
  for i := AIndex to High(FOrigin) - 1 do FOrigin[i] := FOrigin[i + 1];
  SetLength(FOrigin, Length(FOrigin) - 1);
end;

procedure TTySeriesEditModel.MoveSeries(AFrom, ATo: Integer);
var
  list: TJSONArray;
  o, i: Integer;
begin
  if (AFrom = ATo) or (AFrom < 0) or (ATo < 0) or (AFrom >= SeriesCount)
    or (ATo >= SeriesCount) then Exit;
  list := SeriesList;
  list.Move(AFrom, ATo);
  o := FOrigin[AFrom];
  if AFrom < ATo then
    for i := AFrom to ATo - 1 do FOrigin[i] := FOrigin[i + 1]
  else
    for i := AFrom downto ATo + 1 do FOrigin[i] := FOrigin[i - 1];
  FOrigin[ATo] := o;
end;

{ ---- fields ------------------------------------------------------------------ }

function TTySeriesEditModel.Fields(AIndex: Integer): TTySeriesFieldArray;
var
  tp: string;
  i, n: Integer;
  filter: Boolean;
begin
  Result := nil;
  if SeriesNode(AIndex) = nil then Exit;
  tp := SeriesType(AIndex);
  { The catalog decides: smooth is offered to a line and not to a bar. A type
    the catalog does not know gets every field -- refusing to edit its name
    because of a typo in its type would be the wrong way round. }
  filter := (tp <> '') and TyOptFind('series-' + tp).Found;
  SetLength(Result, Length(cFields));
  n := 0;
  for i := 0 to High(cFields) do
    if (not filter) or TyOptFind('series-' + tp + '.' + cFields[i].Path).Found then
    begin
      Result[n] := cFields[i];
      Inc(n);
    end;
  SetLength(Result, n);
end;

function TTySeriesEditModel.Style: TTyOptTextStyle;
begin
  if FPatcher <> nil then Result := FPatcher.Style
  else Result := TyOptDefaultTextStyle;
end;

function TTySeriesEditModel.FieldKindOf(const APath: string;
  out AKind: TTySeriesFieldKind): Boolean;
var i: Integer;
begin
  for i := 0 to High(cFields) do
    if cFields[i].Path = APath then
    begin
      AKind := cFields[i].Kind;
      Exit(True);
    end;
  AKind := sfkLiteral;
  Result := False;
end;

function TTySeriesEditModel.FieldText(AIndex: Integer; const APath: string): string;
var d: TJSONData;
begin
  d := FindPath(SeriesNode(AIndex), APath);
  if d = nil then Exit('');
  case d.JSONType of
    jtString: Result := d.AsString;
    jtNull: Result := 'null';
    jtObject, jtArray: Result := TyOptJsonCompact(d, Style);
  else
    Result := TyEditCellText(d);
  end;
end;

function TTySeriesEditModel.FieldState(AIndex: Integer; const APath: string): TTyFieldState;
var d: TJSONData;
begin
  d := FindPath(SeriesNode(AIndex), APath);
  if d = nil then Exit(fsAbsent);
  case d.JSONType of
    jtBoolean: if d.AsBoolean then Result := fsTrue else Result := fsFalse;
    jtNumber: if d.AsFloat <> 0 then Result := fsTrue else Result := fsFalse;
    jtString: if d.AsString <> '' then Result := fsTrue else Result := fsFalse;
    jtNull: Result := fsFalse;
  else
    Result := fsTrue;
  end;
end;

procedure TTySeriesEditModel.PutPath(AIndex: Integer; const APath: string;
  AValue: TJSONData);
var
  obj: TJSONObject;
  child: TJSONData;
  rest, seg: string;
  p: Integer;
begin
  obj := SeriesNode(AIndex);
  if obj = nil then
  begin
    AValue.Free;
    Exit;
  end;
  rest := APath;
  p := Pos('.', rest);
  while p > 0 do
  begin
    seg := Copy(rest, 1, p - 1);
    rest := Copy(rest, p + 1, MaxInt);
    child := obj.Find(seg);
    if not (child is TJSONObject) then
    begin
      child := TJSONObject.Create;
      SetKey(obj, seg, child);
    end;
    obj := TJSONObject(child);
    p := Pos('.', rest);
  end;
  SetKeyIfChanged(obj, rest, AValue);
end;

procedure TTySeriesEditModel.DropPath(AIndex: Integer; const APath: string);
var
  node, parent: TJSONObject;
  orig: TJSONData;
  p: Integer;
  parentPath, leaf: string;
begin
  node := SeriesNode(AIndex);
  if node = nil then Exit;
  p := LastDelimiter('.', APath);
  if p = 0 then
  begin
    if node.IndexOfName(APath) >= 0 then node.Delete(APath);
    Exit;
  end;
  parentPath := Copy(APath, 1, p - 1);
  leaf := Copy(APath, p + 1, MaxInt);
  if not (FindPath(node, parentPath) is TJSONObject) then Exit;
  parent := TJSONObject(FindPath(node, parentPath));
  if parent.IndexOfName(leaf) >= 0 then parent.Delete(leaf);
  { A parent emptied by the removal goes too -- unless the series was loaded
    with it already empty, which is the user's empty label and not ours. }
  if parent.Count = 0 then
  begin
    orig := FindPath(OrigSeries(AIndex), parentPath);
    if (orig is TJSONObject) and (orig.Count = 0) then Exit;
    p := LastDelimiter('.', parentPath);
    if p = 0 then node.Delete(parentPath)
    else if FindPath(node, Copy(parentPath, 1, p - 1)) is TJSONObject then
      TJSONObject(FindPath(node, Copy(parentPath, 1, p - 1))).Delete(
        Copy(parentPath, p + 1, MaxInt));
  end;
end;

function TTySeriesEditModel.SetFieldText(AIndex: Integer; const APath,
  AText: string; out AError: string): Boolean;
var
  kind: TTySeriesFieldKind;
  t: string;
  n: Integer;
  v: TJSONData;
begin
  AError := '';
  Result := False;
  if SeriesNode(AIndex) = nil then Exit;
  { WHAT WAS SHOWN, WRITTEN BACK, CHANGES NOTHING. The dialog writes a field
    when it loses focus; a name that is the number 2015 is shown as 2015 and
    must not come back as the string '2015'. }
  if AText = FieldText(AIndex, APath) then Exit(True);
  FieldKindOf(APath, kind);
  t := Trim(AText);
  if t = '' then
  begin
    DropPath(AIndex, APath);
    Exit(True);
  end;
  v := nil;
  case kind of
    sfkText:
      v := TJSONString.Create(AText);
    sfkInteger:
      if TryStrToInt(t, n) then v := TJSONIntegerNumber.Create(n)
      else AError := Format(rsTySerEdNotInteger, [t]);
    sfkBoolean:
      if t = 'true' then v := TJSONBoolean.Create(True)
      else if t = 'false' then v := TJSONBoolean.Create(False)
      else AError := Format(rsTySerEdNotBoolean, [t]);
    sfkColor:
      if t[1] in ['{', '['] then TyOptParseLiteral(t, v, AError)
      else v := TJSONString.Create(t);
    sfkLiteral:
      TyOptParseLiteral(t, v, AError);
  end;
  if v = nil then Exit;
  PutPath(AIndex, APath, v);
  Result := True;
end;

procedure TTySeriesEditModel.SetFieldState(AIndex: Integer; const APath: string;
  AState: TTyFieldState);
begin
  if SeriesNode(AIndex) = nil then Exit;
  { a smooth of 0.5 shows as on, and staying on must leave it 0.5 }
  if FieldState(AIndex, APath) = AState then Exit;
  if AState = fsAbsent then DropPath(AIndex, APath)
  else PutPath(AIndex, APath, TJSONBoolean.Create(AState = fsTrue));
end;

{ ---- data tables --------------------------------------------------------------- }

function TTySeriesEditModel.CategoryAxisOf(ANode: TJSONObject; out AKey: string;
  out AIndex: Integer; out AData: TJSONArray): Boolean;
const
  cKeys: array[0..1] of string = ('xAxis', 'yAxis');
var
  tp, cs, unknown: string;
  k: Integer;
  ax, data: TJSONData;
  at: TTyAxisType;
begin
  { The axis whose categories a one-value-per-item series lines up with: a
    cartesian series' x axis, else its y axis (a horizontal bar), when that
    axis is a category axis -- by the builder's own rule, an explicit type or
    a `data` key -- and carries its names in `data`. }
  Result := False;
  AKey := '';
  AIndex := 0;
  AData := nil;
  if ANode = nil then Exit;
  tp := StrOf(ANode, 'type');
  if (tp = '') or not TyOptFind('series-' + tp + '.xAxisIndex').Found then Exit;
  cs := StrOf(ANode, 'coordinateSystem');
  if (cs <> '') and (cs <> 'cartesian2d') then Exit;
  for k := 0 to High(cKeys) do
  begin
    ax := ComponentOf(FWork, cKeys[k], IntOf(ANode, cKeys[k] + 'Index', 0));
    if not (ax is TJSONObject) then Continue;
    TyResolveAxisType(TJSONObject(ax), at, unknown);
    if at <> atCategory then Continue;
    data := TJSONObject(ax).Find('data');
    if not (data is TJSONArray) then Continue;
    AKey := cKeys[k];
    AIndex := IntOf(ANode, cKeys[k] + 'Index', 0);
    AData := TJSONArray(data);
    Exit(True);
  end;
end;

function ItemDims(AItem: TJSONData): Integer;
var v: TJSONData;
begin
  if AItem = nil then Exit(0);
  case AItem.JSONType of
    jtArray: Result := AItem.Count;
    jtObject:
      begin
        v := TJSONObject(AItem).Find('value');
        if v is TJSONArray then Result := v.Count
        else if v <> nil then Result := 1
        else Result := 0;
      end;
    jtNull: Result := 0;
  else
    Result := 1;
  end;
end;

function ItemValue(AItem: TJSONData): TJSONData;
begin
  if AItem is TJSONObject then Result := TJSONObject(AItem).Find('value')
  else Result := AItem;
end;

function TTySeriesEditModel.SeriesTable(AIndex: Integer): TTyEditTable;
var
  node, other: TJSONObject;
  data, item, v, dims, names: TJSONData;
  cats, otherCats: TJSONArray;
  i, j, d, r, c, rows, catCol, nameCol, firstVal, oIdx: Integer;
  catKey, oKey, cap: string;
  hasName: Boolean;
begin
  Result := TTyEditTable.Create;
  Result.FOwner := AIndex;
  Result.FEditable := False;
  node := SeriesNode(AIndex);
  if node = nil then
  begin
    Result.FNote := rsTySerEdNoteHole;
    Exit;
  end;
  data := node.Find('data');
  Result.FHadData := data <> nil;
  if (data <> nil) and not (data is TJSONArray) then
  begin
    Result.FNote := rsTySerEdNoteNotList;
    Exit;
  end;
  if data <> nil then
    for i := 0 to data.Count - 1 do
      if (data.Items[i] is TJSONObject)
        and (TJSONObject(data.Items[i]).Find('children') <> nil) then
      begin
        Result.FNote := rsTySerEdNoteTree;
        Exit;
      end;

  Result.FEditable := True;
  if data <> nil then Result.FSnap := TJSONArray(data.Clone)
  else
  begin
    Result.FSnap := TJSONArray.Create;
    Result.FNote := rsTySerEdNoteNoData;
  end;
  Result.FSnapRows := Result.FSnap.Count;

  d := 0;
  hasName := False;
  for i := 0 to Result.FSnap.Count - 1 do
  begin
    item := Result.FSnap.Items[i];
    if ItemDims(item) > d then d := ItemDims(item);
    if (item is TJSONObject) and (TJSONObject(item).Find('name') <> nil) then
      hasName := True;
  end;

  catCol := -1;
  nameCol := -1;
  if (d <= 1) and CategoryAxisOf(node, catKey, oIdx, cats) then
  begin
    Result.FCats := TJSONArray(cats.Clone);
    Result.FCatKey := catKey;
    Result.FCatIndex := oIdx;
    catCol := 0;
    Result.AddCol(Format(rsTySerEdColCategory, [catKey + '[' + IntToStr(oIdx) + ']']),
      eckCategory, 0);
    Result.FNote := Format(rsTySerEdNoteCategory,
      [catKey + '[' + IntToStr(oIdx) + ']']);
    { every other series that lines up with the same categories, so a row
      deleted here can be deleted there too }
    for j := 0 to SeriesCount - 1 do
    begin
      if j = AIndex then Continue;
      other := SeriesNode(j);
      if other = nil then Continue;
      if not (other.Find('data') is TJSONArray) then Continue;
      if not CategoryAxisOf(other, oKey, i, otherCats) then Continue;
      if (oKey <> catKey) or (i <> oIdx) then Continue;
      d := 0;
      for r := 0 to other.Find('data').Count - 1 do
        if ItemDims(other.Find('data').Items[r]) > d then
          d := ItemDims(other.Find('data').Items[r]);
      if d > 1 then Continue;
      SetLength(Result.FAligned, Length(Result.FAligned) + 1);
      Result.FAligned[High(Result.FAligned)].Series := j;
      Result.FAligned[High(Result.FAligned)].Data :=
        TJSONArray(other.Find('data').Clone);
    end;
    d := 1;
  end;
  if hasName then
  begin
    nameCol := Length(Result.FCols);
    Result.AddCol(rsTySerEdColName, eckName, 0);
  end;

  if d < 1 then d := 1;
  { the dimension names, when the series gives them }
  dims := node.Find('dimensions');
  firstVal := Length(Result.FCols);
  for c := 0 to d - 1 do
  begin
    cap := '';
    if (dims is TJSONArray) and (c < dims.Count) then
    begin
      names := dims.Items[c];
      if names.JSONType = jtString then cap := names.AsString
      else if names is TJSONObject then cap := StrOf(TJSONObject(names), 'name');
    end;
    if cap = '' then
      if d = 1 then cap := rsTySerEdColValue
      else cap := Format(rsTySerEdColDim, [c]);
    Result.AddCol(cap, eckValue, c);
  end;

  rows := Result.FSnap.Count;
  if (Result.FCats <> nil) and (Result.FCats.Count > rows) then
    rows := Result.FCats.Count;
  for r := 0 to rows - 1 do
  begin
    Result.AddRowRaw(r);
    if catCol >= 0 then
      if r < Result.FCats.Count then
        Result.Put(catCol, r, TyEditCellText(ItemValue(Result.FCats.Items[r])), True)
      else
        Result.Put(catCol, r, '', False);
    if r >= Result.FSnap.Count then Continue;
    item := Result.FSnap.Items[r];
    if nameCol >= 0 then
      if item is TJSONObject then
        Result.Put(nameCol, r, TyEditCellText(TJSONObject(item).Find('name')), True)
      else
        Result.Put(nameCol, r, '', True);
    v := ItemValue(item);
    for c := 0 to d - 1 do
      if v is TJSONArray then
      begin
        if c < v.Count then
          Result.Put(firstVal + c, r, TyEditCellText(v.Items[c]), True);
      end
      else if c = 0 then
        Result.Put(firstVal, r, TyEditCellText(v), True);
  end;
end;

{ One value of a row: the original element where the cell is untouched,
  the typed one otherwise -- typed as a string when the original was one. }
function CellJson(T: TTyEditTable; ACol, ARow: Integer; AOrig: TJSONData;
  AKeepString: Boolean): TJSONData;
begin
  if (AOrig <> nil) and T.FRows[ARow].Cells[ACol].HasOrig
    and not T.CellChanged(ACol, ARow) then
    Exit(AOrig.Clone);
  Result := TyEditCellValue(T.FRows[ARow].Cells[ACol].Text,
    AKeepString or ((AOrig <> nil) and (AOrig.JSONType = jtString)));
end;

{ The value part of row ARow, from its value columns. ABase is the original
  value (scalar or array) or nil. Nil back when the row has no value at all. }
function RowValue(T: TTyEditTable; ARow: Integer; ABase: TJSONData;
  AHeader: Boolean): TJSONData;
var
  c, k, last, origLen: Integer;
  vc: array of Integer;
  arr: TJSONArray;
  orig: TJSONData;
begin
  { the value columns, in table order }
  vc := nil;
  for c := 0 to High(T.FCols) do
    if T.FCols[c].Kind = eckValue then
    begin
      SetLength(vc, Length(vc) + 1);
      vc[High(vc)] := c;
    end;
  if vc = nil then Exit(nil);
  last := -1;
  for k := 0 to High(vc) do
    if T.FRows[ARow].Cells[vc[k]].Text <> '' then last := k;

  { ONE VALUE stays one value: a scalar is written back as a scalar unless a
    second column has been filled in }
  if not ((ABase is TJSONArray) or (last > 0)) then
  begin
    if (ABase = nil) and (last < 0) then Exit(nil);
    if (ABase <> nil) and (ABase.JSONType in [jtArray, jtObject]) then orig := nil
    else orig := ABase;
    Exit(CellJson(T, vc[0], ARow, orig, AHeader));
  end;

  if ABase is TJSONArray then origLen := ABase.Count else origLen := 0;
  arr := TJSONArray.Create;
  for k := 0 to High(vc) do
  begin
    c := vc[k];
    orig := nil;
    if (ABase is TJSONArray) and (T.FCols[c].Origin >= 0)
      and (T.FCols[c].Origin < origLen) then
      orig := ABase.Items[T.FCols[c].Origin]
    else if (ABase <> nil) and not (ABase is TJSONArray) and (k = 0) then
      orig := ABase;
    arr.Add(CellJson(T, c, ARow, orig, AHeader));
  end;
  { cells past the original's end that hold nothing are not written: a column
    added for one row does not pad every other row with nulls }
  while (arr.Count > 0)
    and (T.FRows[ARow].Cells[vc[arr.Count - 1]].Text = '')
    and ((T.FCols[vc[arr.Count - 1]].Origin < 0)
      or (T.FCols[vc[arr.Count - 1]].Origin >= origLen)) do
    arr.Delete(arr.Count - 1);
  Result := arr;
end;

function RowChanged(T: TTyEditTable; ARow: Integer): Boolean;
var c: Integer;
begin
  if T.FColsDeleted then Exit(True);
  for c := 0 to High(T.FCols) do
    if (T.FCols[c].Kind <> eckCategory) and T.CellChanged(c, ARow) then
      Exit(True);
  Result := False;
end;

{ The data item of row ARow; nil when the row has no data. }
function RowItem(T: TTyEditTable; ARow: Integer): TJSONData;
var
  o, c: Integer;
  base, v, nm: TJSONData;
  obj: TJSONObject;
  nameCol: Integer;
begin
  o := T.FRows[ARow].Origin;
  base := nil;
  if (o >= 0) and (o < T.FSnap.Count) then base := T.FSnap.Items[o];
  if (base <> nil) and not RowChanged(T, ARow) then Exit(base.Clone);

  nameCol := -1;
  for c := 0 to High(T.FCols) do
    if T.FCols[c].Kind = eckName then nameCol := c;

  v := RowValue(T, ARow, ItemValue(base), False);
  if base is TJSONObject then
  begin
    obj := TJSONObject(base.Clone);
    if v = nil then
    begin
      if obj.IndexOfName('value') >= 0 then obj.Elements['value'] := TJSONNull.Create;
    end
    else
      SetKeyIfChanged(obj, 'value', v);
    if (nameCol >= 0) and T.CellChanged(nameCol, ARow) then
    begin
      if T.FRows[ARow].Cells[nameCol].Text = '' then
      begin
        if obj.IndexOfName('name') >= 0 then obj.Delete('name');
      end
      else
      begin
        nm := TJSONObject(base).Find('name');
        SetKeyIfChanged(obj, 'name', CellJson(T, nameCol, ARow, nm, True));
      end;
    end;
    Exit(obj);
  end;

  if (nameCol >= 0) and (T.FRows[ARow].Cells[nameCol].Text <> '') then
  begin
    { a name typed for a plain value turns it into an item object }
    obj := TJSONObject.Create;
    obj.Add('name', T.FRows[ARow].Cells[nameCol].Text);
    if v = nil then v := TJSONNull.Create;
    obj.Add('value', v);
    Exit(obj);
  end;
  if (v = nil) and (base <> nil) then v := TJSONNull.Create;
  Result := v;
end;

procedure TTySeriesEditModel.ApplySeriesTable(ATable: TTyEditTable);
var
  node, other, axis: TJSONObject;
  items, cats: array of TJSONData;
  newData, newCats, otherData: TJSONArray;
  r, last, lastCat, o, i, j, catCol: Integer;
  base: TJSONData;
  kept: array of Boolean;
  ax: TJSONData;
begin
  if (ATable = nil) or (ATable.FIsDataset) or not ATable.FEditable then Exit;
  node := SeriesNode(ATable.FOwner);
  if node = nil then Exit;

  SetLength(items, ATable.RowCount);
  last := -1;
  for r := 0 to ATable.RowCount - 1 do
  begin
    items[r] := RowItem(ATable, r);
    if items[r] <> nil then last := r;
  end;
  newData := TJSONArray.Create;
  for r := 0 to last do
    if items[r] <> nil then newData.Add(items[r])
    else newData.Add(TJSONNull.Create);
  for r := last + 1 to ATable.RowCount - 1 do items[r].Free;
  if (not ATable.FHadData) and (newData.Count = 0) then
    newData.Free
  else
    SetKeyIfChanged(node, 'data', newData);

  if ATable.FCats = nil then Exit;

  { the categories: the rows, in order, each its original entry where the
    cell is untouched }
  catCol := -1;
  for i := 0 to ATable.ColCount - 1 do
    if ATable.FCols[i].Kind = eckCategory then catCol := i;
  SetLength(cats, ATable.RowCount);
  lastCat := -1;
  for r := 0 to ATable.RowCount - 1 do
  begin
    o := ATable.FRows[r].Origin;
    base := nil;
    if (o >= 0) and (o < ATable.FCats.Count) then base := ATable.FCats.Items[o];
    cats[r] := nil;
    if (base <> nil) and not ATable.CellChanged(catCol, r) then
      cats[r] := base.Clone
    else if base is TJSONObject then
    begin
      cats[r] := base.Clone;
      SetKey(TJSONObject(cats[r]), 'value',
        TJSONString.Create(ATable.FRows[r].Cells[catCol].Text));
    end
    else if (base <> nil) or (ATable.FRows[r].Cells[catCol].Text <> '') then
      cats[r] := TJSONString.Create(ATable.FRows[r].Cells[catCol].Text);
    if cats[r] <> nil then lastCat := r;
  end;
  newCats := TJSONArray.Create;
  for r := 0 to lastCat do
    if cats[r] <> nil then newCats.Add(cats[r])
    else newCats.Add(TJSONString.Create(''));
  for r := lastCat + 1 to ATable.RowCount - 1 do cats[r].Free;
  ax := ComponentOf(FWork, ATable.FCatKey, ATable.FCatIndex);
  if ax is TJSONObject then
  begin
    axis := TJSONObject(ax);
    SetKeyIfChanged(axis, 'data', newCats);
  end
  else
    newCats.Free;

  { A ROW IS A CATEGORY. Deleting one deletes that category's value from
    every series lined up with the same axis, or every series after it would
    slide one category to the left. }
  SetLength(kept, ATable.FSnapRows);
  if (ATable.FCats.Count > Length(kept)) then SetLength(kept, ATable.FCats.Count);
  for i := 0 to High(kept) do kept[i] := False;
  for r := 0 to ATable.RowCount - 1 do
    if ATable.FRows[r].Origin >= 0 then kept[ATable.FRows[r].Origin] := True;
  for i := 0 to High(ATable.FAligned) do
  begin
    other := SeriesNode(ATable.FAligned[i].Series);
    if other = nil then Continue;
    otherData := TJSONArray.Create;
    for j := 0 to ATable.FAligned[i].Data.Count - 1 do
      if (j > High(kept)) or kept[j] then
        otherData.Add(ATable.FAligned[i].Data.Items[j].Clone);
    SetKeyIfChanged(other, 'data', otherData);
  end;
end;

function TTySeriesEditModel.DatasetCount: Integer;
begin
  Result := ComponentCountOf(FWork, 'dataset');
end;

function TTySeriesEditModel.DatasetTable(AIndex: Integer): TTyEditTable;
var
  ds: TJSONData;
  src, row, dims, nm, sh: TJSONData;
  keys: TStringList;
  i, c, w, r: Integer;
  allArrays, allObjects, strings: Boolean;
  cap: string;
begin
  Result := TTyEditTable.Create;
  Result.FIsDataset := True;
  Result.FOwner := AIndex;
  Result.FEditable := False;
  ds := ComponentOf(FWork, 'dataset', AIndex);
  if not (ds is TJSONObject) then
  begin
    Result.FNote := rsTySerEdNoteHole;
    Exit;
  end;
  src := TJSONObject(ds).Find('source');
  if src = nil then
  begin
    if (TJSONObject(ds).Find('transform') <> nil)
      or (TJSONObject(ds).Find('fromDatasetIndex') <> nil)
      or (TJSONObject(ds).Find('fromDatasetId') <> nil) then
      Result.FNote := rsTySerEdNoteTransform
    else
      Result.FNote := rsTySerEdNoteDatasetForm;
    Exit;
  end;
  if not (src is TJSONArray) then
  begin
    Result.FNote := rsTySerEdNoteDatasetForm;
    Exit;
  end;
  allArrays := True;
  allObjects := True;
  for i := 0 to src.Count - 1 do
  begin
    if not (src.Items[i] is TJSONArray) then allArrays := False;
    if not (src.Items[i] is TJSONObject) then allObjects := False;
  end;
  if src.Count = 0 then allObjects := False;
  if not (allArrays or allObjects) then
  begin
    Result.FNote := rsTySerEdNoteDatasetForm;
    Exit;
  end;
  Result.FEditable := True;
  Result.FSnap := TJSONArray(src.Clone);
  Result.FSnapRows := src.Count;
  dims := TJSONObject(ds).Find('dimensions');

  if allObjects then
  begin
    Result.FObjectRows := True;
    keys := TStringList.Create;
    try
      for i := 0 to src.Count - 1 do
        for c := 0 to src.Items[i].Count - 1 do
          if keys.IndexOf(TJSONObject(src.Items[i]).Names[c]) < 0 then
            keys.Add(TJSONObject(src.Items[i]).Names[c]);
      for c := 0 to keys.Count - 1 do
        Result.AddCol(keys[c], eckValue, c, keys[c]);
      for r := 0 to src.Count - 1 do
      begin
        Result.AddRowRaw(r);
        for c := 0 to keys.Count - 1 do
        begin
          row := TJSONObject(src.Items[r]).Find(keys[c]);
          Result.Put(c, r, TyEditCellText(row), row <> nil);
        end;
      end;
    finally
      keys.Free;
    end;
    Exit;
  end;

  w := 0;
  for i := 0 to src.Count - 1 do
    if src.Items[i].Count > w then w := src.Items[i].Count;
  if w < 1 then w := 1;
  for c := 0 to w - 1 do
  begin
    cap := '';
    if (dims is TJSONArray) and (c < dims.Count) then
    begin
      nm := dims.Items[c];
      if nm.JSONType = jtString then cap := nm.AsString
      else if nm is TJSONObject then cap := StrOf(TJSONObject(nm), 'name');
    end;
    if cap = '' then cap := Format(rsTySerEdColDim, [c]);
    Result.AddCol(cap, eckValue, c);
  end;
  { the header: sourceHeader as written, or -- as upstream guesses when it
    is not -- a first row of strings above rows that are not all strings }
  sh := TJSONObject(ds).Find('sourceHeader');
  if (sh <> nil) and (sh.JSONType = jtBoolean) then
  begin
    if sh.AsBoolean then Result.FHeaderRows := 1;
  end
  else if (sh <> nil) and (sh.JSONType = jtNumber) then
    Result.FHeaderRows := IntOf(TJSONObject(ds), 'sourceHeader', 0)
  else if (dims = nil) and (src.Count > 1) then
  begin
    strings := src.Items[0].Count > 0;
    for c := 0 to src.Items[0].Count - 1 do
      if src.Items[0].Items[c].JSONType <> jtString then strings := False;
    if strings then Result.FHeaderRows := 1;
  end;
  for r := 0 to src.Count - 1 do
  begin
    Result.AddRowRaw(r);
    for c := 0 to src.Items[r].Count - 1 do
      Result.Put(c, r, TyEditCellText(src.Items[r].Items[c]), True);
  end;
end;

procedure TTySeriesEditModel.ApplyDatasetTable(ATable: TTyEditTable);
var
  ds: TJSONData;
  newSrc: TJSONArray;
  obj: TJSONObject;
  r, c, o: Integer;
  base, v, row: TJSONData;
  any: Boolean;
begin
  if (ATable = nil) or not ATable.FIsDataset or not ATable.FEditable then Exit;
  ds := ComponentOf(FWork, 'dataset', ATable.FOwner);
  if not (ds is TJSONObject) then Exit;
  newSrc := TJSONArray.Create;
  for r := 0 to ATable.RowCount - 1 do
  begin
    o := ATable.FRows[r].Origin;
    base := nil;
    if (o >= 0) and (o < ATable.FSnap.Count) then base := ATable.FSnap.Items[o];
    if (base <> nil) and not RowChanged(ATable, r) then
    begin
      newSrc.Add(base.Clone);
      Continue;
    end;
    if ATable.FObjectRows then
    begin
      if base <> nil then obj := TJSONObject(base.Clone)
      else obj := TJSONObject.Create;
      any := base <> nil;
      for c := 0 to ATable.ColCount - 1 do
      begin
        if not ATable.CellChanged(c, r) then Continue;
        if ATable.FRows[r].Cells[c].Text = '' then
        begin
          if obj.IndexOfName(ATable.FCols[c].Key) >= 0 then
            obj.Delete(ATable.FCols[c].Key);
        end
        else
        begin
          if base <> nil then v := TJSONObject(base).Find(ATable.FCols[c].Key)
          else v := nil;
          SetKeyIfChanged(obj, ATable.FCols[c].Key,
            CellJson(ATable, c, r, v, False));
          any := True;
        end;
      end;
      if any then newSrc.Add(obj) else obj.Free;
    end
    else
    begin
      v := RowValue(ATable, r, base, ATable.RowIsHeader(r));
      if v = nil then Continue;
      if not (v is TJSONArray) then
      begin
        { a dataset row is always a row }
        row := TJSONArray.Create;
        TJSONArray(row).Add(v);
        newSrc.Add(row);
      end
      else
        newSrc.Add(v);
    end;
  end;
  SetKeyIfChanged(TJSONObject(ds), 'source', newSrc);
end;

{ ---- writing back ------------------------------------------------------------ }

function TTySeriesEditModel.Changed: Boolean;
begin
  Result := not TyOptJsonSame(FOrig, FWork);
end;

function TTySeriesEditModel.Text: string;
begin
  FLost := 0;
  FWhole := False;
  if FPatcher = nil then Exit(FText);
  { the series list's identity: which original series each one is, so a
    series that was edited AND moved is patched from its own text }
  if (SeriesSlot is TJSONArray) and (FOrig is TJSONObject)
    and (TJSONObject(FOrig).Find('series') is TJSONArray) then
    FPatcher.SetArrayHint(SeriesSlot, FOrigin)
  else
    FPatcher.SetArrayHint(nil, []);
  Result := FPatcher.Patch(FWork);
  FLost := FPatcher.Lost;
  FWhole := FHadValue and (not FPatcher.Mapped) and Changed;
end;

function TTySeriesEditModel.NeedsConfirm: Boolean;
begin
  Result := (FLost > 0) or FWhole;
end;

function TTySeriesEditModel.Diagnose: TTyOptDiagArray;
begin
  Result := TyOptDiagnose(Text);
end;

end.
