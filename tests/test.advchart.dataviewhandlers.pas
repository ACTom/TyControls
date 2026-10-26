unit test.advchart.dataviewhandlers;
{$mode objfpc}{$H+}
{ The data view's optionToContent / contentToOption [spec 237].

  TAdvChartDataViewHandlersOracleTest replays
  tools/advchart-oracle/dataview-handlers.js: the real ECharts 6.1 build
  opens the data view with '@Name' functions in the option and presses its
  buttons; the fixture records what the panel showed, every call of the
  functions (the option they were handed, the cells and the text a
  contentToOption read), the changeDataView it dispatched and the option
  after. The port registers Pascal handlers of the same names that do the
  same things to the port's arguments, opens the view through the real
  content dialog (built, not shown: the scripted cell edit goes into its
  grid, Refresh reads it back) and compares.

  TAdvChartDataViewHandlersTest: the registries, the html tables, the four
  content forms and their pages, the round trip through contentToOption,
  the two events before the built-ins, a control content's lifetime, and
  the answers that merge nothing or are refused. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Forms, StdCtrls, BGRABitmap, BGRABitmapTypes,
     tyControls.Grid, tyControls.Columns, tyControls.StrConsts, tyControls.Controller,
     tyControls.Dialogs, tyControls.Memo, tyControls.TyLabel,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Handlers,
     tyControls.AdvanceChart.Data,
     tyControls.AdvanceChart.Events, tyControls.AdvanceChart.TipHtml,
     tyControls.AdvanceChart.ToolboxDlg, tyControls.AdvanceChart,
     test.advchart.toolbox;
type
  { what a test does to the real content dialog before its button }
  TDvhPagesEvent = procedure(APages: TTyDataViewPages) of object;

  TDvhProbe = class(TTbProbe)
  protected
    function ToolboxShowDataViewContent(const ATitle: string;
      var AContent: TTyChartDataViewContent; AReadOnly, AEditable: Boolean;
      const ACloseCaption, ARefreshCaption: string): Boolean; override;
  public
    CShown, CReadOnly, CEditable: Boolean;
    CTitle, CClose, CRefresh: string;
    { the content as the seam was handed it }
    CContent: TTyChartDataViewContent;
    { set: the real dialog is built and handed here before the button }
    CPages: TDvhPagesEvent;
    { the handlers' calls made before the seam returned }
    CCallsAtSeam: Integer;
  end;

  { the Pascal twins of the oracle's functions, and what they were given }
  TDvhHandlers = class
  public
    Calls: TJSONArray;
    constructor Create;
    destructor Destroy; override;
    procedure Register;
    function Table(const AOption: string): TTyChartDataViewContent;
    function HeadTable(const AOption: string): TTyChartDataViewContent;
    function Read(const AContent: TTyChartDataViewContent; const AOption: string): string;
    function ReadFull(const AContent: TTyChartDataViewContent; const AOption: string): string;
    function Nothing(const AContent: TTyChartDataViewContent; const AOption: string): string;
    function Boom(const AContent: TTyChartDataViewContent; const AOption: string): string;
    function NewSeries(const AContent: TTyChartDataViewContent; const AOption: string): string;
    function Items(const AContent: TTyChartDataViewContent; const AOption: string): string;
  end;

  TAdvChartDataViewHandlersOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TDvhProbe;
    FH: TDvhHandlers;
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FName: string;
    { the scripted edits of the open view: row, col, value }
    FEditRow, FEditCol: array of Integer;
    FEditVal: array of string;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot, AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure ApplyEdits(APages: TTyDataViewPages);
    procedure CheckCalls(const AWhat: string; AFrom, ATo: Integer; AWant: TJSONArray);
    procedure CheckAfter(const AWhat: string; ARec: TJSONObject; AEvents: Integer);
    procedure RunScenario(ASc: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheHandlersAsUpstream;
  end;

  TAdvChartDataViewHandlersTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TDvhProbe;
    FH: TDvhHandlers;
    { what the events and the hand handlers saw }
    FEvContent, FEvApply, FTextCalls, FTableCalls: Integer;
    FApplyKind: TTyChartDataViewKind;
    FApplyText, FTextGot, FAnswer: string;
    FTablesGot: TTyChartDataViewTables;
    FControlFreed, FOwnedFreed: Boolean;
    FOwnedControl: TWinControl;
    procedure Show(const AOption: string);
    procedure OnContent(Sender: TObject; const AOptionJson: string;
      var AContent: TTyChartDataViewContent; var AHandled: Boolean);
    procedure OnContentDeclines(Sender: TObject; const AOptionJson: string;
      var AContent: TTyChartDataViewContent; var AHandled: Boolean);
    procedure OnApply(Sender: TObject; const AContent: TTyChartDataViewContent;
      const AOptionJson: string; var ANewOption: string; var AHandled: Boolean);
    procedure OnApplyDeclines(Sender: TObject; const AContent: TTyChartDataViewContent;
      const AOptionJson: string; var ANewOption: string; var AHandled: Boolean);
    function TextContent(const AOption: string): TTyChartDataViewContent;
    function TablesContent(const AOption: string): TTyChartDataViewContent;
    function ControlContent(const AOption: string): TTyChartDataViewContent;
    function OwnedControlContent(const AOption: string): TTyChartDataViewContent;
    function RaiseContent(const AOption: string): TTyChartDataViewContent;
    function TakeText(const AContent: TTyChartDataViewContent; const AOption: string): string;
    function TakeTables(const AContent: TTyChartDataViewContent; const AOption: string): string;
    function Answer(const AContent: TTyChartDataViewContent; const AOption: string): string;
    procedure EditFirstCell(APages: TTyDataViewPages);
    procedure EditMemo(APages: TTyDataViewPages);
    procedure NoEdit(APages: TTyDataViewPages);
    procedure ControlFreed(Sender: TObject);
    procedure OwnedFreed(Sender: TObject);
    function DataViewEvents: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRegistriesFindReplaceAndForget;
    procedure TestTheTablesOfHtml;
    procedure TestTheCellsGoBackIntoTheHtml;
    procedure TestAnHtmlContentsPages;
    procedure TestTheOtherContentForms;
    procedure TestAnEditedCellComesBackThroughContentToOption;
    procedure TestAnEditedTextComesBackThroughContentToOption;
    procedure TestTheEventsComeBeforeTheHandlers;
    procedure TestApplyUnderTheDefaultView;
    procedure TestAControlNobodyOwnsIsFreed;
    procedure TestAnswersThatMergeNothingOrAreRefused;
    procedure TestAContentThatRaisesOpensNothing;
    procedure TestThePageCaptionsAreTheResourceStrings;
  end;

implementation

const
  cW = 600;
  cH = 400;

{ ==================== JSON helpers ==================== }

function JsonOf(const AText: string): TJSONData;
begin
  Result := GetJSON(AText);
end;

{ structural equality: numbers by value, objects by key set }
function JEq(A, B: TJSONData): Boolean;
var
  i: Integer;
  o: TJSONObject;
begin
  if (A = nil) or (A.JSONType = jtNull) then Exit((B = nil) or (B.JSONType = jtNull));
  if (B = nil) or (B.JSONType = jtNull) then Exit(False);
  if A.JSONType <> B.JSONType then Exit(False);
  case A.JSONType of
    jtNumber: Result := A.AsFloat = B.AsFloat;
    jtString: Result := A.AsString = B.AsString;
    jtBoolean: Result := A.AsBoolean = B.AsBoolean;
    jtArray:
      begin
        if A.Count <> B.Count then Exit(False);
        for i := 0 to A.Count - 1 do
          if not JEq(TJSONArray(A).Items[i], TJSONArray(B).Items[i]) then Exit(False);
        Result := True;
      end;
    jtObject:
      begin
        o := TJSONObject(B);
        if A.Count <> B.Count then Exit(False);
        for i := 0 to A.Count - 1 do
          if not JEq(TJSONObject(A).Items[i], o.Find(TJSONObject(A).Names[i])) then Exit(False);
        Result := True;
      end;
  else
    Result := True;
  end;
end;

function ArrOf(AData: TJSONData): TJSONArray;
begin
  if AData is TJSONArray then Result := TJSONArray(AData) else Result := nil;
end;

{ a value as JavaScript's String() prints it }
function JsStr(AData: TJSONData): string;
begin
  if AData = nil then Exit('undefined');
  case AData.JSONType of
    jtNumber: Result := TyChartValueText(AData.AsFloat);
    jtString: Result := AData.AsString;
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
  else
    Result := AData.AsJSON;
  end;
end;

function ValOf(AData: TJSONData): TJSONData;
begin
  if AData is TJSONObject then Result := TJSONObject(AData).Find('value')
  else Result := AData;
end;

{ the oracle's optPick: the series' names and data, xAxis[0].data }
function OptPick(const AOption: string): TJSONObject;
var
  o: TJSONData;
  ser, out: TJSONArray;
  so: TJSONObject;
  i: Integer;
  d: TJSONData;
begin
  Result := TJSONObject.Create;
  o := GetJSON(AOption);
  try
    out := TJSONArray.Create;
    Result.Add('series', out);
    ser := ArrOf(TJSONObject(o).Find('series'));
    if ser <> nil then
      for i := 0 to ser.Count - 1 do
      begin
        so := TJSONObject.Create;
        d := TJSONObject(ser.Items[i]).Find('name');
        if d = nil then so.Add('name', TJSONNull.Create) else so.Add('name', d.Clone);
        d := TJSONObject(ser.Items[i]).Find('data');
        if d = nil then so.Add('data', TJSONNull.Create) else so.Add('data', d.Clone);
        out.Add(so);
      end;
    d := TJSONObject(o).Find('xAxis');
    if (d is TJSONArray) and (TJSONArray(d).Count > 0) and (TJSONArray(d).Items[0] is TJSONObject)
      and (TJSONObject(TJSONArray(d).Items[0]).Find('data') <> nil) then
      Result.Add('xAxisData', TJSONObject(TJSONArray(d).Items[0]).Find('data').Clone)
    else
      Result.Add('xAxisData', TJSONNull.Create);
  finally
    o.Free;
  end;
end;

{ the cells a contentToOption reads: the first table's header and rows }
function RowsOf(const AContent: TTyChartDataViewContent): TJSONArray;
var
  t: TTyChartDataViewTable;
  r, c: Integer;
  row: TJSONArray;
begin
  Result := TJSONArray.Create;
  if Length(AContent.Tables) = 0 then Exit;
  t := AContent.Tables[0];
  if Length(t.Header) > 0 then
  begin
    row := TJSONArray.Create;
    for c := 0 to High(t.Header) do row.Add(t.Header[c]);
    Result.Add(row);
  end;
  for r := 0 to High(t.Rows) do
  begin
    row := TJSONArray.Create;
    for c := 0 to High(t.Rows[r]) do row.Add(t.Rows[r][c]);
    Result.Add(row);
  end;
end;

{ ==================== the probe ==================== }

function TDvhProbe.ToolboxShowDataViewContent(const ATitle: string;
  var AContent: TTyChartDataViewContent; AReadOnly, AEditable: Boolean;
  const ACloseCaption, ARefreshCaption: string): Boolean;
var
  d: TTyDialog;
  v: TTyDataViewPages;
begin
  CShown := True;
  CTitle := ATitle;
  CContent := AContent;
  CReadOnly := AReadOnly;
  CEditable := AEditable;
  CClose := ACloseCaption;
  CRefresh := ARefreshCaption;
  Result := (DvButton = ARefreshCaption) and not AReadOnly;
  if not Assigned(CPages) then Exit;
  d := TyBuildDataViewContentDialog(ATitle, AContent, AReadOnly, AEditable,
    ACloseCaption, ARefreshCaption, v);
  try
    CPages(v);
    if Result then v.ReadBack(AContent);
  finally
    if v.Control <> nil then v.Control.Parent := nil;
    d.Free;
  end;
end;

{ ==================== the handlers ==================== }

constructor TDvhHandlers.Create;
begin
  inherited Create;
  Calls := TJSONArray.Create;
end;

destructor TDvhHandlers.Destroy;
begin
  Calls.Free;
  inherited Destroy;
end;

procedure TDvhHandlers.Register;
begin
  TyChartRegisterOptionToContent('Table', @Table);
  TyChartRegisterOptionToContent('HeadTable', @HeadTable);
  TyChartRegisterContentToOption('Read', @Read);
  TyChartRegisterContentToOption('ReadFull', @ReadFull);
  TyChartRegisterContentToOption('Nothing', @Nothing);
  TyChartRegisterContentToOption('Boom', @Boom);
  TyChartRegisterContentToOption('NewSeries', @NewSeries);
  TyChartRegisterContentToOption('Items', @Items);
end;

function TableHtml(const AOption: string; AHead: Boolean): string;
var
  o: TJSONData;
  ser, axis: TJSONArray;
  i, s: Integer;
  nm: string;
begin
  o := GetJSON(AOption);
  try
    axis := ArrOf(TJSONObject(TJSONArray(TJSONObject(o).Find('xAxis')).Items[0]).Find('data'));
    ser := ArrOf(TJSONObject(o).Find('series'));
    if AHead then Result := '<table><caption>Sales</caption><thead><tr><th>Day</th>'
    else Result := '<table style="width:100%;text-align:center"><tbody><tr><td>Day</td>';
    for s := 0 to ser.Count - 1 do
    begin
      nm := JsStr(TJSONObject(ser.Items[s]).Find('name'));
      if AHead then Result := Result + '<th>' + nm + '</th>'
      else Result := Result + '<td>' + nm + '</td>';
    end;
    if AHead then Result := Result + '</tr></thead><tbody>'
    else Result := Result + '</tr>';
    for i := 0 to axis.Count - 1 do
    begin
      Result := Result + '<tr><td>' + JsStr(axis.Items[i]) + '</td>';
      for s := 0 to ser.Count - 1 do
        Result := Result + '<td>' + JsStr(ValOf(ArrOf(TJSONObject(ser.Items[s]).Find('data')).Items[i])) + '</td>';
      Result := Result + '</tr>';
    end;
    Result := Result + '</tbody></table>';
    if AHead then Result := Result + '<p>Units: <b>k</b></p>';
  finally
    o.Free;
  end;
end;

function TDvhHandlers.Table(const AOption: string): TTyChartDataViewContent;
var c: TJSONObject;
begin
  c := OptPick(AOption);
  c.Add('fn', 'Table');
  Calls.Add(c);
  Result := Default(TTyChartDataViewContent);
  Result.Kind := cdvHtml;
  Result.Text := TableHtml(AOption, False);
end;

function TDvhHandlers.HeadTable(const AOption: string): TTyChartDataViewContent;
var c: TJSONObject;
begin
  c := OptPick(AOption);
  c.Add('fn', 'HeadTable');
  Calls.Add(c);
  Result := Default(TTyChartDataViewContent);
  Result.Kind := cdvHtml;
  Result.Text := TableHtml(AOption, True);
end;

procedure LogC2O(ACalls: TJSONArray; const AFn: string;
  const AContent: TTyChartDataViewContent; const AOption: string);
var c: TJSONObject;
begin
  c := OptPick(AOption);
  c.Add('fn', AFn);
  c.Add('rows', RowsOf(AContent));
  c.Add('content', AContent.Text);
  ACalls.Add(c);
end;

function TDvhHandlers.Read(const AContent: TTyChartDataViewContent; const AOption: string): string;
var
  rows: TJSONArray;
  k, r: Integer;
  ser, dat: string;
begin
  LogC2O(Calls, 'Read', AContent, AOption);
  rows := RowsOf(AContent);
  try
    ser := '';
    if rows.Count > 0 then
      for k := 1 to TJSONArray(rows.Items[0]).Count - 1 do
      begin
        dat := '';
        for r := 1 to rows.Count - 1 do
        begin
          if dat <> '' then dat := dat + ',';
          dat := dat + TyChartValueText(
            TyJsToNumber(TJSONArray(rows.Items[r]).Items[k].AsString) + 1);
        end;
        if ser <> '' then ser := ser + ',';
        ser := ser + '{"name":"' + StringToJSONString(TJSONArray(rows.Items[0]).Items[k].AsString)
          + '","data":[' + dat + ']}';
      end;
  finally
    rows.Free;
  end;
  Result := '{"series":[' + ser + ']}';
end;

function TDvhHandlers.ReadFull(const AContent: TTyChartDataViewContent; const AOption: string): string;
var
  o: TJSONObject;
  dat: TJSONArray;
begin
  LogC2O(Calls, 'ReadFull', AContent, AOption);
  o := TJSONObject(GetJSON(AOption));
  try
    dat := TJSONArray(TJSONObject(TJSONArray(o.Find('series')).Items[1]).Find('data'));
    dat.Items[0] := TJSONIntegerNumber.Create(999);
    if o.IndexOfName('title') >= 0 then o.Delete('title');
    o.Add('title', TJSONArray.Create([TJSONObject.Create(['text', 'Edited'])]));
    Result := o.AsJSON;
  finally
    o.Free;
  end;
end;

function TDvhHandlers.Nothing(const AContent: TTyChartDataViewContent; const AOption: string): string;
begin
  LogC2O(Calls, 'Nothing', AContent, AOption);
  Result := '';
end;

function TDvhHandlers.Boom(const AContent: TTyChartDataViewContent; const AOption: string): string;
begin
  LogC2O(Calls, 'Boom', AContent, AOption);
  raise Exception.Create('bad cell');
end;

function TDvhHandlers.NewSeries(const AContent: TTyChartDataViewContent; const AOption: string): string;
begin
  LogC2O(Calls, 'NewSeries', AContent, AOption);
  Result := '{"series":[{"name":"Email","data":[1,2,3,4,5]},{"name":"Extra","data":[[1,2],[3,4]]},'
    + '{"data":[5,6]}],"title":{"text":"T"}}';
end;

function TDvhHandlers.Items(const AContent: TTyChartDataViewContent; const AOption: string): string;
begin
  LogC2O(Calls, 'Items', AContent, AOption);
  Result := '{"series":[{"name":"Ads","data":[1,2,3,{"value":4,"name":"four"},5]}]}';
end;

{ ==================== the oracle ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-dataview-handlers.json';
end;

procedure TAdvChartDataViewHandlersOracleTest.SetUp;
var s: TStringList;
begin
  inherited SetUp;
  s := TStringList.Create;
  try
    s.LoadFromFile(FixturePath);
    FRoot := GetJSON(s.Text);
  finally
    s.Free;
  end;
  FH := TDvhHandlers.Create;
  FH.Register;
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
end;

procedure TAdvChartDataViewHandlersOracleTest.TearDown;
begin
  TyChartClearOptionToContents;
  TyChartClearContentToOptions;
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FH);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartDataViewHandlersOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 30 then FReport := FReport + LineEnding + FName + ': ' + AWhat;
end;

procedure TAdvChartDataViewHandlersOracleTest.Same(const AWhat: string; AGot, AWant: TJSONData);
var g, w: string;
begin
  Inc(FCompared);
  if JEq(AGot, AWant) then Exit;
  if AGot = nil then g := 'nil' else g := AGot.AsJSON;
  if AWant = nil then w := 'nil' else w := AWant.AsJSON;
  Miss(AWhat + ': got ' + Copy(g, 1, 300) + ' want ' + Copy(w, 1, 300));
end;

procedure TAdvChartDataViewHandlersOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Miss(AWhat + ': got "' + Copy(AGot, 1, 200) + '" want "' + Copy(AWant, 1, 200) + '"');
end;

procedure TAdvChartDataViewHandlersOracleTest.ApplyEdits(APages: TTyDataViewPages);
var
  i, row: Integer;
begin
  for i := 0 to High(FEditRow) do
  begin
    { the html's rows count the header row; the grid's do not }
    row := FEditRow[i];
    if Length(APages.Blocks[0].Header) > 0 then Dec(row);
    APages.Grids[0].Cells[FEditCol[i], row] := FEditVal[i];
  end;
end;

procedure TAdvChartDataViewHandlersOracleTest.CheckCalls(const AWhat: string;
  AFrom, ATo: Integer; AWant: TJSONArray);
var
  i: Integer;
  g, w: TJSONObject;
begin
  Inc(FCompared);
  if ATo - AFrom <> AWant.Count then
  begin
    Miss(AWhat + ' calls: ' + IntToStr(ATo - AFrom) + ' want ' + IntToStr(AWant.Count));
    Exit;
  end;
  for i := 0 to AWant.Count - 1 do
  begin
    g := TJSONObject(FH.Calls.Items[AFrom + i]);
    w := TJSONObject(AWant.Items[i]);
    SameStr(AWhat + ' call ' + IntToStr(i) + ' fn', g.Get('fn', ''), w.Get('fn', ''));
    Same(AWhat + ' call ' + IntToStr(i) + ' series', g.Find('series'), w.Find('series'));
    Same(AWhat + ' call ' + IntToStr(i) + ' xAxisData', g.Find('xAxisData'), w.Find('xAxisData'));
    if w.Find('rows') <> nil then
    begin
      Same(AWhat + ' call ' + IntToStr(i) + ' rows', g.Find('rows'), w.Find('rows'));
      SameStr(AWhat + ' call ' + IntToStr(i) + ' content', g.Get('content', ''), w.Get('content', ''));
    end;
  end;
end;

{ the changeDataView events since AEvents, and the option after }
procedure TAdvChartDataViewHandlersOracleTest.CheckAfter(const AWhat: string;
  ARec: TJSONObject; AEvents: Integer);
const
  cKeys: array[0..2] of string = ('type', 'name', 'data');
var
  want, gotSer, outSer: TJSONArray;
  ev: TJSONArray;
  i, n, p: Integer;
  e, opt, pay: TJSONData;
  so, ps: TJSONObject;
  d: TJSONData;
  titles: TJSONArray;
begin
  { the events: one a changeDataView; the option it carried as the action
    was dispatched (upstream's event hands on the same object, which the
    merge has filled with defaults by then), unless it is a getOption dump
    (upstream's carries the model's defaults, the port's GetOptionJson the
    option as written) }
  want := TJSONArray(ARec.Find('actions'));
  ev := TJSONArray.Create;
  try
    for i := AEvents to FChart.Events.Count - 1 do
    begin
      p := Pos(#9, FChart.Events[i]);
      if Copy(FChart.Events[i], 1, p - 1) <> 'dataviewchanged' then Continue;
      pay := GetJSON(Copy(FChart.Events[i], p + 1, MaxInt));
      try
        d := TJSONObject(pay).Find('newOption');
        if d = nil then ev.Add(TJSONNull.Create) else ev.Add(d.Clone);
      finally
        pay.Free;
      end;
    end;
    Inc(FCompared);
    if ev.Count <> want.Count then
      Miss(AWhat + ' dataviewchanged: ' + IntToStr(ev.Count) + ' want ' + IntToStr(want.Count))
    else
      for i := 0 to want.Count - 1 do
      begin
        d := TJSONObject(want.Items[i]).Find('newOption');
        if not ((d is TJSONObject) and (TJSONObject(d).Find('darkMode') <> nil)) then
          Same(AWhat + ' newOption', ev.Items[i], d);
      end;
  finally
    ev.Free;
  end;
  { getOption's series and titles }
  opt := GetJSON(FChart.GetOptionJson);
  outSer := TJSONArray.Create;
  titles := TJSONArray.Create;
  try
    gotSer := ArrOf(TJSONObject(opt).Find('series'));
    if gotSer <> nil then
      for i := 0 to gotSer.Count - 1 do
      begin
        so := TJSONObject(gotSer.Items[i]);
        ps := TJSONObject.Create;
        for n := 0 to 2 do
        begin
          e := so.Find(cKeys[n]);
          if e = nil then ps.Add(cKeys[n], TJSONNull.Create)
          else ps.Add(cKeys[n], e.Clone);
        end;
        outSer.Add(ps);
      end;
    d := TJSONObject(opt).Find('title');
    if d is TJSONArray then
      for i := 0 to d.Count - 1 do
        if (TJSONArray(d).Items[i] is TJSONObject) and (TJSONObject(TJSONArray(d).Items[i]).Find('text') <> nil) then
          titles.Add(TJSONObject(TJSONArray(d).Items[i]).Find('text').Clone)
        else
          titles.Add(TJSONNull.Create);
    Same(AWhat + ' option series', outSer, TJSONObject(ARec.Find('option')).Find('series'));
    Same(AWhat + ' option title', titles, TJSONObject(ARec.Find('option')).Find('title'));
  finally
    outSer.Free;
    titles.Free;
    opt.Free;
  end;
end;

procedure TAdvChartDataViewHandlersOracleTest.RunScenario(ASc: TJSONObject);
var
  steps, want: TJSONArray;
  s, j, callsBefore, evBefore: Integer;
  st, rec, panel, ta, nx: TJSONObject;
  typ, button: string;
  bmp: TBGRABitmap;
begin
  FName := ASc.Get('id', '');
  FreeAndNil(FForm);
  FForm := TForm.CreateNew(nil);
  FChart := TDvhProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
  FChart.CPages := @ApplyEdits;
  FChart.SetOption(ASc.Find('option').AsJSON, True);
  AssertEquals(FName + ' option', '', FChart.OptionError);
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
  finally
    bmp.Free;
  end;
  steps := TJSONArray(ASc.Find('steps'));
  s := 0;
  while s < steps.Count do
  begin
    st := TJSONObject(TJSONObject(steps.Items[s]).Find('step'));
    rec := TJSONObject(TJSONObject(steps.Items[s]).Find('record'));
    typ := st.Get('type', '');
    AssertEquals(FName + ' a scenario starts with open', 'open', typ);
    { the steps up to the button script the modal view }
    FEditRow := nil;
    FEditCol := nil;
    FEditVal := nil;
    FChart.DvEdits.Clear;
    button := '';
    j := s + 1;
    while (j < steps.Count) and (button = '') do
    begin
      nx := TJSONObject(TJSONObject(steps.Items[j]).Find('step'));
      if nx.Get('type', '') = 'cell' then
      begin
        SetLength(FEditRow, Length(FEditRow) + 1);
        SetLength(FEditCol, Length(FEditCol) + 1);
        SetLength(FEditVal, Length(FEditVal) + 1);
        FEditRow[High(FEditRow)] := nx.Get('row', 0);
        FEditCol[High(FEditCol)] := nx.Get('col', 0);
        FEditVal[High(FEditVal)] := nx.Get('value', '');
      end
      else if nx.Get('type', '') = 'text' then
        FChart.DvEdits.Add(nx.Get('value', ''))
      else if nx.Get('type', '') = 'button' then
        button := nx.Get('button', '');
      Inc(j);
    end;
    FChart.DvButton := button;
    FChart.DvShown := False;
    FChart.CShown := False;
    FChart.CCallsAtSeam := -1;
    callsBefore := FH.Calls.Count;
    evBefore := FChart.Events.Count;
    AssertTrue(FName + ' the icon', FChart.ToolboxClick(0, 'dataView', 'dataView'));
    { the open record: the panel }
    panel := TJSONObject(rec.Find('panel'));
    Inc(FCompared);
    if panel.Get('custom', False) <> FChart.CShown then Miss('custom content shown')
    else if FChart.CShown then
    begin
      SameStr('header', FChart.CTitle, panel.Get('header', ''));
      SameStr('content', FChart.CContent.Text, panel.Get('content', ''));
      Inc(FCompared);
      if FChart.CReadOnly <> (TJSONArray(panel.Find('buttons')).Count = 1) then Miss('Refresh shown');
      SameStr('close', FChart.CClose, TJSONArray(panel.Find('buttons')).Items[
        TJSONArray(panel.Find('buttons')).Count - 1].AsString);
      if not FChart.CReadOnly then
        SameStr('refresh', FChart.CRefresh, TJSONArray(panel.Find('buttons')).Items[0].AsString);
    end
    else
    begin
      ta := TJSONObject(panel.Find('textarea'));
      SameStr('header', FChart.DvTitle, panel.Get('header', ''));
      SameStr('textarea', FChart.DvText, ta.Get('value', ''));
      Inc(FCompared);
      if FChart.DvReadOnly <> ta.Get('readOnly', False) then Miss('textarea readOnly');
    end;
    { the calls the open made: those before the seam }
    want := TJSONArray(rec.Find('calls'));
    if FChart.CShown then
      CheckCalls('open', callsBefore, callsBefore + want.Count, want)
    else
      CheckCalls('open', callsBefore, callsBefore, want);
    { the button's record: the calls after the open's, the events, the
      option, the error }
    rec := TJSONObject(TJSONObject(steps.Items[j - 1]).Find('record'));
    CheckCalls('button', callsBefore + TJSONArray(TJSONObject(TJSONObject(steps.Items[s]).Find('record')).Find('calls')).Count,
      FH.Calls.Count, TJSONArray(rec.Find('calls')));
    CheckAfter('button', rec, evBefore);
    Inc(FCompared);
    if (rec.Find('error').JSONType = jtNull) <> (FChart.ToolboxError = '') then
      Miss('error: got "' + FChart.ToolboxError + '"')
    else if (FChart.ToolboxError <> '') and (Pos('bad cell', FChart.ToolboxError) = 0) then
      Miss('error text: ' + FChart.ToolboxError);
    s := j;
  end;
end;

procedure TAdvChartDataViewHandlersOracleTest.TestTheHandlersAsUpstream;
var
  scs: TJSONArray;
  i: Integer;
begin
  scs := TJSONArray(TJSONObject(FRoot).Find('scenarios'));
  AssertEquals('the fixture''s scenarios', 14, scs.Count);
  for i := 0 to scs.Count - 1 do RunScenario(TJSONObject(scs.Items[i]));
  AssertEquals('mismatches: ' + FReport, 0, FBad);
  AssertTrue('compared ' + IntToStr(FCompared), FCompared >= 250);
end;

{ ==================== the hand-written tests ==================== }

const
  cOpt = '{"animation":false,"legend":{"show":false},'
    + '"xAxis":{"type":"category","data":["Mon","Tue","Wed"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","name":"Rain","data":[2,4,7]}],'
    + '"toolbox":{"feature":{"dataView":%s}}}';

procedure TAdvChartDataViewHandlersTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TDvhProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
  FH := TDvhHandlers.Create;
  FH.Register;
  TyChartRegisterOptionToContent('TextContent', @TextContent);
  TyChartRegisterOptionToContent('TablesContent', @TablesContent);
  TyChartRegisterOptionToContent('ControlContent', @ControlContent);
  TyChartRegisterOptionToContent('OwnedControlContent', @OwnedControlContent);
  TyChartRegisterOptionToContent('RaiseContent', @RaiseContent);
  TyChartRegisterContentToOption('TakeText', @TakeText);
  TyChartRegisterContentToOption('TakeTables', @TakeTables);
  TyChartRegisterContentToOption('Answer', @Answer);
end;

procedure TAdvChartDataViewHandlersTest.TearDown;
begin
  TyChartClearOptionToContents;
  TyChartClearContentToOptions;
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FH);
  inherited TearDown;
end;

procedure TAdvChartDataViewHandlersTest.Show(const AOption: string);
var bmp: TBGRABitmap;
begin
  FChart.SetOption(AOption, True);
  FChart.Events.Clear;
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartDataViewHandlersTest.DataViewEvents: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to FChart.Events.Count - 1 do
    if Copy(FChart.Events[i], 1, 16) = 'dataviewchanged'#9 then Inc(Result);
end;

procedure TAdvChartDataViewHandlersTest.OnContent(Sender: TObject; const AOptionJson: string;
  var AContent: TTyChartDataViewContent; var AHandled: Boolean);
begin
  Inc(FEvContent);
  AContent.Kind := cdvText;
  AContent.Text := 'from the event';
  AHandled := True;
end;

procedure TAdvChartDataViewHandlersTest.OnContentDeclines(Sender: TObject;
  const AOptionJson: string; var AContent: TTyChartDataViewContent; var AHandled: Boolean);
begin
  Inc(FEvContent);
  { scribbled on and declined: the chart must not keep the scribble }
  AContent.Kind := cdvText;
  AContent.Text := 'scribble';
end;

procedure TAdvChartDataViewHandlersTest.OnApply(Sender: TObject;
  const AContent: TTyChartDataViewContent; const AOptionJson: string;
  var ANewOption: string; var AHandled: Boolean);
begin
  Inc(FEvApply);
  FApplyKind := AContent.Kind;
  FApplyText := AContent.Text;
  ANewOption := '{"series":[{"name":"Rain","data":[9,9,9]}]}';
  AHandled := True;
end;

procedure TAdvChartDataViewHandlersTest.OnApplyDeclines(Sender: TObject;
  const AContent: TTyChartDataViewContent; const AOptionJson: string;
  var ANewOption: string; var AHandled: Boolean);
begin
  Inc(FEvApply);
  ANewOption := '{"series":[{"name":"Rain","data":[0,0,0]}]}';
end;

function TAdvChartDataViewHandlersTest.TextContent(const AOption: string): TTyChartDataViewContent;
begin
  Result := Default(TTyChartDataViewContent);
  Result.Kind := cdvText;
  Result.Text := 'Rain: 2, 4, 7'#10'second line';
end;

function TAdvChartDataViewHandlersTest.TablesContent(const AOption: string): TTyChartDataViewContent;
begin
  Result := Default(TTyChartDataViewContent);
  Result.Kind := cdvTable;
  SetLength(Result.Tables, 2);
  Result.Tables[0].Caption := 'First';
  Result.Tables[0].Header := TTyStringArray.Create('Day', 'Rain');
  SetLength(Result.Tables[0].Rows, 2);
  Result.Tables[0].Rows[0] := TTyStringArray.Create('Mon', '2');
  Result.Tables[0].Rows[1] := TTyStringArray.Create('Tue', '4');
  SetLength(Result.Tables[1].Rows, 1);
  Result.Tables[1].Rows[0] := TTyStringArray.Create('a', 'b', 'c');
end;

type
  TDvhFreeProbe = class(TTyMemo)
  public
    OnGone: TNotifyEvent;
    destructor Destroy; override;
  end;

destructor TDvhFreeProbe.Destroy;
begin
  if Assigned(OnGone) then OnGone(Self);
  inherited Destroy;
end;

function TAdvChartDataViewHandlersTest.ControlContent(const AOption: string): TTyChartDataViewContent;
var m: TDvhFreeProbe;
begin
  m := TDvhFreeProbe.Create(nil);
  m.OnGone := @ControlFreed;
  m.Text := 'mine';
  Result := Default(TTyChartDataViewContent);
  Result.Kind := cdvControl;
  Result.Control := m;
end;

function TAdvChartDataViewHandlersTest.OwnedControlContent(const AOption: string): TTyChartDataViewContent;
var m: TDvhFreeProbe;
begin
  m := TDvhFreeProbe.Create(FForm);
  m.OnGone := @OwnedFreed;
  FOwnedControl := m;
  Result := Default(TTyChartDataViewContent);
  Result.Kind := cdvControl;
  Result.Control := FOwnedControl;
end;

function TAdvChartDataViewHandlersTest.RaiseContent(const AOption: string): TTyChartDataViewContent;
begin
  raise Exception.Create('no content today');
end;

procedure TAdvChartDataViewHandlersTest.ControlFreed(Sender: TObject);
begin
  FControlFreed := True;
end;

function TAdvChartDataViewHandlersTest.TakeText(const AContent: TTyChartDataViewContent;
  const AOption: string): string;
begin
  Inc(FTextCalls);
  FTextGot := AContent.Text;
  Result := '{"series":[{"name":"Rain","data":[5,5,5]}]}';
end;

function TAdvChartDataViewHandlersTest.TakeTables(const AContent: TTyChartDataViewContent;
  const AOption: string): string;
begin
  Inc(FTableCalls);
  FTablesGot := AContent.Tables;
  Result := '{"series":[{"name":"Rain","data":[' + AContent.Tables[0].Rows[0][1] + ',1,1]}]}';
end;

function TAdvChartDataViewHandlersTest.Answer(const AContent: TTyChartDataViewContent;
  const AOption: string): string;
begin
  Result := FAnswer;
end;

procedure TAdvChartDataViewHandlersTest.EditFirstCell(APages: TTyDataViewPages);
begin
  APages.Grids[0].Cells[1, 0] := '42';
end;

procedure TAdvChartDataViewHandlersTest.EditMemo(APages: TTyDataViewPages);
begin
  APages.Memo.Text := 'edited';
end;

procedure TAdvChartDataViewHandlersTest.NoEdit(APages: TTyDataViewPages);
begin
  { the control is on the dialog while it is up }
  if APages.Control <> nil then
    AssertTrue('shown on the dialog', APages.Control.Parent = APages.Dialog);
end;

procedure TAdvChartDataViewHandlersTest.OwnedFreed(Sender: TObject);
begin
  FOwnedFreed := True;
end;

function RainData(AChart: TTyAdvanceChart): string;
var o: TJSONData;
begin
  o := GetJSON(AChart.GetOptionJson);
  try
    Result := TJSONObject(TJSONArray(TJSONObject(o).Find('series')).Items[0]).Find('data').AsJSON;
  finally
    o.Free;
  end;
end;

procedure TAdvChartDataViewHandlersTest.TestTheRegistriesFindReplaceAndForget;
var
  o: TTyChartOptionToContent;
  c: TTyChartContentToOption;
begin
  AssertTrue('registered', TyChartFindOptionToContent('Table', o));
  AssertTrue('any case, as every registry', TyChartFindOptionToContent('table', o));
  AssertFalse('the other registry does not hold it', TyChartFindContentToOption('Table', c));
  AssertTrue(TyChartFindContentToOption('Read', c));
  { registering again replaces }
  TyChartRegisterOptionToContent('Table', @TextContent);
  AssertTrue(TyChartFindOptionToContent('Table', o));
  AssertEquals('replaced', Ord(cdvText), Ord(o('{}').Kind));
  TyChartUnregisterOptionToContent('Table');
  AssertFalse('forgotten', TyChartFindOptionToContent('Table', o));
  AssertTrue('the others stay', TyChartFindOptionToContent('HeadTable', o));
  TyChartUnregisterContentToOption('Read');
  AssertFalse(TyChartFindContentToOption('Read', c));
  TyChartRegisterOptionToContent('', @TextContent);
  AssertFalse('no empty name', TyChartFindOptionToContent('', o));
  TyChartClearOptionToContents;
  TyChartClearContentToOptions;
  AssertFalse(TyChartFindOptionToContent('HeadTable', o));
  AssertFalse(TyChartFindContentToOption('Items', c));
end;

procedure TAdvChartDataViewHandlersTest.TestTheTablesOfHtml;
var
  t: TTyChartDataViewTables;
  outside: string;
begin
  t := TyHtmlTables('<p>Before</p><table border="1" data-x="a>b"><caption> The <i>cap</i> </caption>'
    + '<thead><tr><th>A</th><th>B &amp; C</th></tr></thead>'
    + '<tbody><tr><td> 1 </td><td>x<br>y</td></tr><tr><td>2<td><table><tr><td>in</td><td>ner</td></tr></table></tr>'
    + '</tbody></table>After <b>this</b>'
    + '<table><tr><td>p</td><th>q</th></tr><tr><th>r</th><th>s</th></tr></table>'
    + '<table><tr><th>h1</th><th>h2</th></tr><tr><td>1</td><td>2</td></tr>', outside);
  AssertEquals('three outer tables', 3, Length(t));
  AssertEquals('the caption''s text', 'The cap', t[0].Caption);
  AssertEquals('a thead row is the header', 2, Length(t[0].Header));
  AssertEquals('A', t[0].Header[0]);
  AssertEquals('entities read', 'B & C', t[0].Header[1]);
  AssertEquals('two body rows', 2, Length(t[0].Rows));
  AssertEquals('trimmed', '1', t[0].Rows[0][0]);
  AssertEquals('a line break is a space', 'x y', t[0].Rows[0][1]);
  AssertEquals('an unclosed td ends at the next', '2', t[0].Rows[1][0]);
  AssertEquals('a nested table is its cell''s text', 'inner', StringReplace(t[0].Rows[1][1], ' ', '', [rfReplaceAll]));
  AssertEquals('a first row that is not all th is no header', 0, Length(t[1].Header));
  AssertEquals('so both rows are rows', 2, Length(t[1].Rows));
  AssertEquals('a later th row is a row', 's', t[1].Rows[1][1]);
  AssertEquals('a first row all th is the header', 'h2', t[2].Header[1]);
  AssertEquals('an unclosed table ends with the text', 1, Length(t[2].Rows));
  AssertEquals('the text outside', 'Before'#10'After this', TyHtmlPlainText(outside));
  { no table at all }
  t := TyHtmlTables('<b>bold</b> text', outside);
  AssertEquals(0, Length(t));
  AssertEquals('bold text', TyHtmlPlainText(outside));
  AssertEquals('a <br> line and an empty one', 'a'#10#10'b', TyHtmlPlainText('a<br><br>b'));
end;

procedure TAdvChartDataViewHandlersTest.TestTheCellsGoBackIntoTheHtml;
const
  cHtml = '<p>x</p><table><thead><tr><th>Day</th><th><b>Rain</b></th></tr></thead>'
    + '<tr><td>Mon</td><td> 2 </td></tr><tr><td>Tue</td><td>4</td></tr></table>';
var
  t: TTyChartDataViewTables;
  outside: string;
begin
  t := TyHtmlTables(cHtml, outside);
  AssertEquals('untouched: byte for byte', cHtml, TyHtmlSetCells(cHtml, t));
  { two edits of other lengths, one needing encoding; the header and the
    markup of the cells left alone stay as written }
  t[0].Rows[0][1] := '20';
  t[0].Rows[1][0] := 'a<b & c';
  AssertEquals('<p>x</p><table><thead><tr><th>Day</th><th><b>Rain</b></th></tr></thead>'
    + '<tr><td>Mon</td><td>20</td></tr><tr><td>a&lt;b &amp; c</td><td>4</td></tr></table>',
    TyHtmlSetCells(cHtml, t));
  { a changed header cell }
  t := TyHtmlTables(cHtml, outside);
  t[0].Header[0] := 'Date';
  AssertEquals('<p>x</p><table><thead><tr><th>Date</th><th><b>Rain</b></th></tr></thead>'
    + '<tr><td>Mon</td><td> 2 </td></tr><tr><td>Tue</td><td>4</td></tr></table>',
    TyHtmlSetCells(cHtml, t));
  { cells past the html's own are left out }
  SetLength(t[0].Rows, 3);
  t[0].Rows[2] := TTyStringArray.Create('Wed', '9');
  AssertEquals('no third row to write', Pos('Wed', TyHtmlSetCells(cHtml, t)), 0);
end;

procedure TAdvChartDataViewHandlersTest.TestAnHtmlContentsPages;
var
  c: TTyChartDataViewContent;
  d: TTyDialog;
  v: TTyDataViewPages;
  outside: string;
begin
  c := Default(TTyChartDataViewContent);
  c.Kind := cdvHtml;
  c.Text := '<table><caption>Sales</caption><thead><tr><th>Day</th><th>Rain</th></tr></thead>'
    + '<tr><td>Mon</td><td>2</td></tr><tr><td>Tue</td><td>4</td></tr></table><p>Units: <b>k</b></p>';
  c.Tables := TyHtmlTables(c.Text, outside);
  d := TyBuildDataViewContentDialog('T', c, False, False, 'Close', 'Refresh', v);
  try
    AssertEquals('two pages', 2, v.Pages.PageCount);
    AssertTrue('the table page first', v.Pages.Pages[0] = v.TablePage);
    AssertEquals('one grid', 1, v.GridCount);
    AssertTrue('its header shown', hoVisible in v.Grids[0].Header.Options);
    AssertEquals('the header''s cells', 'Rain', TTyColumn(v.Grids[0].Header.Columns.Items[1]).Text);
    AssertEquals('the body', 2, v.Grids[0].RowCount);
    AssertEquals('Tue', v.Grids[0].Cells[0, 1]);
    AssertTrue('the caption heads it', (v.Headings[0] <> nil) and (v.Headings[0].Caption = 'Sales'));
    AssertTrue('not editable: nothing reads it back', v.Grids[0].ReadOnly);
    AssertEquals('the text outside the table', 'Units: k', v.Memo.Text);
    AssertTrue('the reading of html is never edited', v.Memo.ReadOnly);
  finally
    d.Free;
  end;
  { editable; a table alone has no text page; Refresh and Close }
  c.Text := '<table><tr><td>a</td><td>b</td></tr></table>';
  c.Tables := TyHtmlTables(c.Text, outside);
  d := TyBuildDataViewContentDialog('T', c, False, True, 'Close', 'Refresh', v);
  try
    AssertEquals('one page', 1, v.Pages.PageCount);
    AssertTrue('no text page', v.TextPage = nil);
    AssertFalse('editable', v.Grids[0].ReadOnly);
    AssertFalse('no header row', hoVisible in v.Grids[0].Header.Options);
    AssertTrue('no caption, no heading', v.Headings[0] = nil);
  finally
    d.Free;
  end;
  { editable, with text outside: the reading of the html stays read-only }
  c.Text := '<table><tr><td>a</td></tr></table>note';
  c.Tables := TyHtmlTables(c.Text, outside);
  d := TyBuildDataViewContentDialog('T', c, False, True, 'Close', 'Refresh', v);
  try
    AssertEquals(2, v.Pages.PageCount);
    AssertFalse(v.Grids[0].ReadOnly);
    AssertTrue('never edited, even when the cells are', v.Memo.ReadOnly);
    AssertEquals('note', v.Memo.Text);
  finally
    d.Free;
  end;
  { html with no table: its text }
  c.Text := 'just <i>words</i>';
  c.Tables := TyHtmlTables(c.Text, outside);
  d := TyBuildDataViewContentDialog('T', c, True, False, 'Close', 'Refresh', v);
  try
    AssertEquals('one page', 1, v.Pages.PageCount);
    AssertTrue('no table page', v.TablePage = nil);
    AssertEquals('just words', v.Memo.Text);
  finally
    d.Free;
  end;
end;

procedure TAdvChartDataViewHandlersTest.TestTheOtherContentForms;
var
  c: TTyChartDataViewContent;
  d: TTyDialog;
  v: TTyDataViewPages;
begin
  { text: one page, as written, editable when asked }
  c := TextContent('');
  d := TyBuildDataViewContentDialog('T', c, False, True, 'Close', 'Refresh', v);
  try
    AssertEquals(1, v.Pages.PageCount);
    AssertTrue(v.TablePage = nil);
    AssertEquals('as written', 'Rain: 2, 4, 7'#10'second line', v.MemoText);
    AssertFalse('editable', v.Memo.ReadOnly);
  finally
    d.Free;
  end;
  d := TyBuildDataViewContentDialog('T', c, False, False, 'Close', 'Refresh', v);
  try
    AssertTrue('not editable', v.Memo.ReadOnly);
  finally
    d.Free;
  end;
  { tables: two grids in the box, the captioned one headed }
  c := TablesContent('');
  d := TyBuildDataViewContentDialog('T', c, False, True, 'Close', 'Refresh', v);
  try
    AssertEquals(1, v.Pages.PageCount);
    AssertTrue(v.TextPage = nil);
    AssertEquals(2, v.GridCount);
    AssertTrue('several: a box', v.ScrollBox <> nil);
    AssertTrue((v.Headings[0] <> nil) and (v.Headings[0].Caption = 'First'));
    AssertTrue('no caption, no heading', v.Headings[1] = nil);
    AssertEquals('c', v.Grids[1].Cells[2, 0]);
    AssertEquals('read back untouched', '4', v.ReadTables[0].Rows[1][1]);
    AssertEquals('the header kept', 'Rain', v.ReadTables[0].Header[1]);
  finally
    d.Free;
  end;
  { a control: in place of the pages, taken off before the dialog goes }
  FControlFreed := False;
  c := ControlContent('');
  try
    d := TyBuildDataViewContentDialog('T', c, True, False, 'Close', 'Refresh', v);
    try
      AssertTrue('no pages', v.Pages = nil);
      AssertTrue('the control is shown', TControl(c.Control).Parent = d);
      AssertTrue(v.Control = c.Control);
      v.Control.Parent := nil;
    finally
      d.Free;
    end;
    AssertFalse('the dialog does not free it', FControlFreed);
  finally
    c.Control.Free;
  end;
end;

procedure TAdvChartDataViewHandlersTest.TestAnEditedCellComesBackThroughContentToOption;
begin
  Show(Format(cOpt, ['{"optionToContent":"@TablesContent","contentToOption":"@TakeTables"}']));
  FChart.DvButton := 'Refresh';
  FChart.CPages := @EditFirstCell;
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertTrue('the content view', FChart.CShown);
  AssertTrue('editable: contentToOption reads it', FChart.CEditable);
  AssertEquals('one call', 1, FTableCalls);
  AssertEquals('the edited cell', '42', FTablesGot[0].Rows[0][1]);
  AssertEquals('the second table too', 'c', FTablesGot[1].Rows[0][2]);
  AssertEquals('', FChart.ToolboxError);
  AssertEquals('merged', '[42, 1, 1]', RainData(FChart));
  AssertEquals('dataviewchanged', 1, DataViewEvents);
  { Close: nothing }
  FChart.DvButton := 'Close';
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals('no second call', 1, FTableCalls);
  { readOnly: no Refresh, not editable }
  Show(Format(cOpt, ['{"optionToContent":"@TablesContent","contentToOption":"@TakeTables","readOnly":true}']));
  FChart.DvButton := 'Refresh';
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertTrue(FChart.CReadOnly);
  AssertFalse(FChart.CEditable);
  AssertEquals('Refresh is not there to press', 1, FTableCalls);
end;

procedure TAdvChartDataViewHandlersTest.TestAnEditedTextComesBackThroughContentToOption;
begin
  Show(Format(cOpt, ['{"optionToContent":"@TextContent","contentToOption":"@TakeText"}']));
  FChart.DvButton := 'Refresh';
  FChart.CPages := @EditMemo;
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals(1, FTextCalls);
  AssertEquals('the edited text', 'edited', FTextGot);
  AssertEquals('[5, 5, 5]', RainData(FChart));
  { optionToContent alone: Refresh only closes }
  Show(Format(cOpt, ['{"optionToContent":"@TextContent"}']));
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertFalse('nothing reads it back: not editable', FChart.CEditable);
  AssertEquals('ignored', '[2, 4, 7]', RainData(FChart));
  AssertEquals(0, DataViewEvents);
end;

procedure TAdvChartDataViewHandlersTest.TestTheEventsComeBeforeTheHandlers;
begin
  { OnDataViewContent handles: its content, the handler not called }
  FChart.OnDataViewContent := @OnContent;
  Show(Format(cOpt, ['{"optionToContent":"@TablesContent","contentToOption":"@TakeText"}']));
  FChart.DvButton := 'Refresh';
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals(1, FEvContent);
  AssertEquals('the event''s content', 'from the event', FChart.CContent.Text);
  AssertEquals('then contentToOption', 1, FTextCalls);
  AssertEquals('[5, 5, 5]', RainData(FChart));
  { declining: the handler runs, the scribble is gone }
  FChart.OnDataViewContent := @OnContentDeclines;
  Show(Format(cOpt, ['{"optionToContent":"@TextContent","contentToOption":"@TakeText"}']));
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals(2, FEvContent);
  AssertEquals('the handler''s content', 'Rain: 2, 4, 7'#10'second line', FChart.CContent.Text);
  { the event alone, with nothing to read it back: ignored }
  FChart.OnDataViewContent := @OnContent;
  Show(Format(cOpt, ['{}']));
  FTextCalls := 0;
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertTrue('the event''s content shown', FChart.CShown);
  AssertEquals('one without the other: ignored', '[2, 4, 7]', RainData(FChart));
  { OnDataViewApply handles: its option, contentToOption not called }
  FChart.OnDataViewApply := @OnApply;
  Show(Format(cOpt, ['{"optionToContent":"@TextContent","contentToOption":"@TakeText"}']));
  FTextCalls := 0;
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals(1, FEvApply);
  AssertEquals('handled by the event', 0, FTextCalls);
  AssertEquals('[9, 9, 9]', RainData(FChart));
  { the event alone reads the content back: editable, and not ignored }
  Show(Format(cOpt, ['{"optionToContent":"@TextContent"}']));
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertTrue('the apply event makes the content editable', FChart.CEditable);
  AssertEquals(2, FEvApply);
  AssertEquals('handled, so not ignored', '[9, 9, 9]', RainData(FChart));
  { declining: contentToOption runs, the event's answer is not used }
  FChart.OnDataViewApply := @OnApplyDeclines;
  Show(Format(cOpt, ['{"optionToContent":"@TextContent","contentToOption":"@TakeText"}']));
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals(3, FEvApply);
  AssertEquals(1, FTextCalls);
  AssertEquals('[5, 5, 5]', RainData(FChart));
end;

procedure TAdvChartDataViewHandlersTest.TestApplyUnderTheDefaultView;
begin
  FChart.OnDataViewApply := @OnApply;
  Show(Format(cOpt, ['{}']));
  FChart.DvButton := 'Refresh';
  FChart.DvEdits.Add(' '#9'Rain'#10'Mon'#9'1'#10'Tue'#9'1'#10'Wed'#9'1');
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertFalse('the default view', FChart.CShown);
  AssertEquals(1, FEvApply);
  AssertEquals('the text it read back', Ord(cdvText), Ord(FApplyKind));
  AssertEquals(' '#9'Rain'#10'Mon'#9'1'#10'Tue'#9'1'#10'Wed'#9'1', FApplyText);
  AssertEquals('the event''s option, not the parse', '[9, 9, 9]', RainData(FChart));
  { declined: the parse }
  FChart.OnDataViewApply := @OnApplyDeclines;
  Show(Format(cOpt, ['{}']));
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals('the parse of the text', '["1", "1", "1"]', RainData(FChart));
  { contentToOption alone under the default view: ignored }
  FChart.OnDataViewApply := nil;
  Show(Format(cOpt, ['{"contentToOption":"@TakeText"}']));
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals('not called', 0, FTextCalls);
  AssertEquals('[2, 4, 7]', RainData(FChart));
  { an optionToContent nobody registered: the default view, and the
    contentToOption is handed its text }
  Show(Format(cOpt, ['{"optionToContent":"@Nobody","contentToOption":"@TakeText"}']));
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertFalse(FChart.CShown);
  AssertEquals(1, FTextCalls);
  AssertEquals(' '#9'Rain'#10'Mon'#9'1'#10'Tue'#9'1'#10'Wed'#9'1', FTextGot);
end;

procedure TAdvChartDataViewHandlersTest.TestAControlNobodyOwnsIsFreed;
begin
  FControlFreed := False;
  Show(Format(cOpt, ['{"optionToContent":"@ControlContent","contentToOption":"@Answer"}']));
  FChart.DvButton := 'Refresh';
  FChart.CPages := @NoEdit;
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals(Ord(cdvControl), Ord(FChart.CContent.Kind));
  AssertTrue('freed once the view is done', FControlFreed);
  { Close frees it too }
  FControlFreed := False;
  FChart.DvButton := 'Close';
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertTrue(FControlFreed);
  { one with an owner is its owner's }
  Show(Format(cOpt, ['{"optionToContent":"@OwnedControlContent","contentToOption":"@Answer"}']));
  FOwnedFreed := False;
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertFalse('its owner''s to free', FOwnedFreed);
  AssertTrue('taken off the dialog', FOwnedControl.Parent = nil);
end;

procedure TAdvChartDataViewHandlersTest.TestAnswersThatMergeNothingOrAreRefused;
const
  cFalsy: array[0..5] of string = ('', '   ', 'null', 'false', '0', '""');
var
  i: Integer;
  deep: string;
begin
  Show(Format(cOpt, ['{"optionToContent":"@TextContent","contentToOption":"@Answer"}']));
  FChart.DvButton := 'Refresh';
  for i := 0 to High(cFalsy) do
  begin
    FAnswer := cFalsy[i];
    AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
    AssertEquals('falsy merges nothing: ' + cFalsy[i], 0, DataViewEvents);
    AssertEquals('and is no error: ' + cFalsy[i], '', FChart.ToolboxError);
  end;
  FAnswer := '{"series": [';
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertTrue('not JSON: refused', FChart.ToolboxError <> '');
  AssertEquals(0, DataViewEvents);
  deep := StringOfChar('[', 5000) + StringOfChar(']', 5000);
  FAnswer := deep;
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertTrue('too deep: refused', Pos('256', FChart.ToolboxError) > 0);
  AssertEquals(0, DataViewEvents);
  FAnswer := '{"series":[{"name":"Rain","data":[3,3,3]}]}';
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals('an object: merged', '', FChart.ToolboxError);
  AssertEquals(1, DataViewEvents);
  AssertEquals('[3, 3, 3]', RainData(FChart));
  { a truthy answer that is no object: dispatched, merges nothing }
  FAnswer := '5';
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertEquals(2, DataViewEvents);
  AssertEquals('[3, 3, 3]', RainData(FChart));
end;

procedure TAdvChartDataViewHandlersTest.TestAContentThatRaisesOpensNothing;
begin
  Show(Format(cOpt, ['{"optionToContent":"@RaiseContent","contentToOption":"@TakeText"}']));
  FChart.DvButton := 'Refresh';
  AssertTrue(FChart.ToolboxClick(0, 'dataView', 'dataView'));
  AssertFalse('no content view', FChart.CShown);
  AssertFalse('no default view', FChart.DvShown);
  AssertEquals('the message', 'no content today', FChart.ToolboxError);
  AssertEquals(0, FTextCalls);
end;

procedure TAdvChartDataViewHandlersTest.TestThePageCaptionsAreTheResourceStrings;
var
  c: TTyChartDataViewContent;
  d: TTyDialog;
  v: TTyDataViewPages;
begin
  c := TablesContent('');
  d := TyBuildDataViewContentDialog('T', c, False, False, rsMsgBtnClose,
    rsTyChartToolboxDataViewRefresh, v);
  try
    AssertEquals(rsTyChartToolboxDataViewTable, v.TablePage.Caption);
  finally
    d.Free;
  end;
  c := TextContent('');
  d := TyBuildDataViewContentDialog('T', c, False, False, rsMsgBtnClose,
    rsTyChartToolboxDataViewRefresh, v);
  try
    AssertEquals(rsTyChartToolboxDataViewText, v.TextPage.Caption);
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartDataViewHandlersOracleTest);
  RegisterTest(TAdvChartDataViewHandlersTest);
end.
