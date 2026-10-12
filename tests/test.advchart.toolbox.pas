unit test.advchart.toolbox;
{$mode objfpc}{$H+}
{ The toolbox -- held to upstream to the bit [Batch 125, C16].

  tools/advchart-oracle/toolbox.js runs the real ECharts 6.1 build through
  cases of pointer steps on zrender's own Handler, actions, merges and the
  dataView panel's buttons, and records after every step: each toolbox's
  layout (the group, every icon's place, fitted path, rects, the background),
  each icon's state (its emphasis, the title shown -- its words, place,
  alignment and colour -- and the render-time adjustment), the features'
  iconStatus, the actions dispatched and the events, the option getOption
  gives, the select dataZooms' windows, the history and the brush's cover,
  the dataView's text, saveAsImage's export options and file name, and the
  custom onclick calls.

  The port is driven the same way -- MouseMove / MouseDown / MouseUp /
  MouseLeave, DispatchAction, SetOption -- with a headless render after each
  step; the dataView's and saveAsImage's dialogs answer through the chart's
  virtual seams, scripted from the steps that follow the click. Compared
  through the chart's own API: ToolboxSpec / ToolboxLayout /
  ToolboxIconState / ToolboxTitle / ToolboxIconStatus / ToolboxHistoryCount /
  ToolboxCover / ToolboxCursorName, the events, OnDataZoom's actions,
  GetOptionJson and AxisZoom. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.Dialogs, tyControls.Memo,
     tyControls.AdvChart.Types,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Events,
     tyControls.AdvChart.ZrPath, tyControls.AdvChart.DataZoom,
     tyControls.AdvChart.DataZoomAct, tyControls.AdvChart.Series,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Builder,
     tyControls.AdvChart.Toolbox, tyControls.AdvChart.ToolboxDlg,
     tyControls.AdvanceChart;
type
  { zrender's widths, from the fixture's table (the font is not asked) }
  TTbMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    Names: TStringList;
    W, H: array of Double;
    Missed: string;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string; AW, AH: Double);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TTbProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
    function ToolboxShowDataView(const ATitle: string; var AText: string;
      AReadOnly: Boolean; const ACloseCaption, ARefreshCaption: string): Boolean; override;
    function ToolboxAskFileName(var AFileName: string; const AType: string): Boolean; override;
  public
    Measurer: ITyTextMeasurer;
    Events: TStringList;
    Zooms: array of TTyDzAction;
    Clicks: TStringList;
    { the data view's script and what it was shown }
    DvEdits: TStringList;
    DvButton: string;
    DvShown, DvReadOnly: Boolean;
    DvTitle, DvText, DvClose, DvRefresh: string;
    { saveAsImage: what it asked, and a file to write when SaveTo is set }
    SaveAsked: Boolean;
    SaveName, SaveType, SaveOpts, SaveTo: string;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    procedure Leave;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
    procedure OnZoom(Sender: TObject; const AAction: TTyDzAction);
    procedure OnSave(Sender: TObject; var AFileName: string;
      const AOptsJson: string; var AHandled: Boolean);
    procedure HitToolA(ASender: TObject; const AFeature, AIcon: string);
    procedure HitToolB(ASender: TObject; const AFeature, AIcon: string);
    procedure HitToolC(ASender: TObject; const AFeature, AIcon: string);
    procedure HitPair(ASender: TObject; const AFeature, AIcon: string);
    procedure HitImg(ASender: TObject; const AFeature, AIcon: string);
  end;

  TAdvChartToolboxOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTbProbe;
    FRoot: TJSONData;
    FMeas: TTbMeasurer;
    FMeasRef: ITyTextMeasurer;
    FBad, FCompared, FSteps, FStepNo: Integer;
    FReport, FName: string;
    { the upstream state carried forward: a record's null fields are the
      record before's }
    FLayout, FToolboxes, FOption, FZoom: TJSONData;
    FIconState: TStringList;
    { upstream's actions and events since the last comparison }
    FActs, FEvs: TJSONArray;
    procedure Miss(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameNum(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure NewChart;
    procedure RenderNow;
    procedure Take(ARec: TJSONObject);
    procedure CheckLayout;
    procedure CheckIcons(ACursorRole: string; ARec: TJSONObject);
    procedure CheckActions(AStep: Integer);
    procedure CheckOption;
    procedure CheckZoom;
    procedure CheckRecord(ARec: TJSONObject; const AHover: string; AStep: Integer);
    procedure RunScenario(ASc: TJSONObject);
    procedure RunGroup(const APrefix1, APrefix2: string);
    function IconIndex(ATb: Integer; const AKey: string): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLayoutAndHoverAsUpstream;
    procedure TestMagicTypeAndRestoreAsUpstream;
    procedure TestSelectZoomAndBackAsUpstream;
    procedure TestDataViewAsUpstream;
    procedure TestSaveAsImageAndCustomAsUpstream;
  end;

  { What the oracle does not reach. }
  TAdvChartToolboxTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTbProbe;
    procedure Show(const AOption: string);
    procedure RenderNow;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDataViewTextAndParseBack;
    procedure TestTheDataViewDialogIsBuiltNotShown;
    procedure TestSaveAsImageGoesThroughTheEventThenTheSeam;
    procedure TestTheActionsByTheApi;
    procedure TestTheToolboxIsDrawnAndExcludedFromTheExport;
    procedure TestAnUnregisteredHandlerDoesNothing;
    procedure TestTheTitlesAreTheResourceStrings;
  end;

implementation

const
  cW = 600;
  cH = 400;

{ ==================== the measurer ==================== }

constructor TTbMeasurer.Create;
begin
  inherited Create;
  Names := TStringList.Create;
  Names.CaseSensitive := True;
end;

destructor TTbMeasurer.Destroy;
begin
  Names.Free;
  inherited Destroy;
end;

procedure TTbMeasurer.Add(const AText: string; AW, AH: Double);
var k: Integer;
begin
  if Names.IndexOf(AText) >= 0 then Exit;
  k := Names.Add(AText);
  SetLength(W, k + 1);
  SetLength(H, k + 1);
  W[k] := AW;
  H[k] := AH;
end;

procedure TTbMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var k: Integer;
begin
  k := Names.IndexOf(AText);
  if k < 0 then
  begin
    AW := 6 * Length(AText);
    AH := 12;
    Exit;
  end;
  AW := W[k];
  AH := H[k];
end;

function TTbMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

{ ==================== the probe ==================== }

function TTbProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Exit(Measurer);
  Result := inherited NewTextMeasurer(APPI);
end;

constructor TTbProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
  Clicks := TStringList.Create;
  DvEdits := TStringList.Create;
  OnChartEvent := @OnEv;
  OnDataZoom := @OnZoom;
  OnToolboxSaveAsImage := @OnSave;
end;

destructor TTbProbe.Destroy;
begin
  Events.Free;
  Clicks.Free;
  DvEdits.Free;
  inherited Destroy;
end;

procedure TTbProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTbProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TTbProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TTbProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TTbProbe.Leave;
begin
  MouseLeave;
end;

procedure TTbProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if AEvent.Payload <> '' then Events.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TTbProbe.OnZoom(Sender: TObject; const AAction: TTyDzAction);
begin
  SetLength(Zooms, Length(Zooms) + 1);
  Zooms[High(Zooms)] := AAction;
end;

procedure TTbProbe.OnSave(Sender: TObject; var AFileName: string;
  const AOptsJson: string; var AHandled: Boolean);
begin
  SaveOpts := AOptsJson;
end;

function TTbProbe.ToolboxShowDataView(const ATitle: string; var AText: string;
  AReadOnly: Boolean; const ACloseCaption, ARefreshCaption: string): Boolean;
var
  i, p: Integer;
  e: string;
begin
  DvShown := True;
  DvTitle := ATitle;
  DvText := AText;
  DvReadOnly := AReadOnly;
  DvClose := ACloseCaption;
  DvRefresh := ARefreshCaption;
  for i := 0 to DvEdits.Count - 1 do
  begin
    e := DvEdits[i];
    p := Pos(#1, e);
    if p > 0 then AText := StringReplace(AText, Copy(e, 1, p - 1),
      Copy(e, p + 1, MaxInt), [rfReplaceAll])
    else AText := e;
  end;
  Result := (DvButton = ARefreshCaption) and not AReadOnly;
end;

function TTbProbe.ToolboxAskFileName(var AFileName: string; const AType: string): Boolean;
begin
  SaveAsked := True;
  SaveName := AFileName;
  SaveType := AType;
  Result := SaveTo <> '';
  if Result then AFileName := SaveTo;
end;

procedure TTbProbe.HitToolA(ASender: TObject; const AFeature, AIcon: string);
begin
  Clicks.Add('ToolA|' + AFeature + '|' + AIcon);
end;

procedure TTbProbe.HitToolB(ASender: TObject; const AFeature, AIcon: string);
begin
  Clicks.Add('ToolB|' + AFeature + '|' + AIcon);
end;

procedure TTbProbe.HitToolC(ASender: TObject; const AFeature, AIcon: string);
begin
  Clicks.Add('ToolC|' + AFeature + '|' + AIcon);
end;

procedure TTbProbe.HitPair(ASender: TObject; const AFeature, AIcon: string);
begin
  Clicks.Add('Pair|' + AFeature + '|' + AIcon);
end;

procedure TTbProbe.HitImg(ASender: TObject; const AFeature, AIcon: string);
begin
  Clicks.Add('Img|' + AFeature + '|' + AIcon);
end;

{ ==================== the fixture's numbers and words ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-toolbox.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  System.Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function Nul(const S: string): string;
begin
  Result := StringReplace(S, #0, '<NUL>', [rfReplaceAll]);
end;

{ a value in one canonical text for both sides: keys sorted, numbers at 17
  digits, a number JSON cannot hold (an object of one key $num upstream, the
  string "NaN" here) the same word }
function Canon(AData: TJSONData): string;
var
  i: Integer;
  keys: TStringList;
  o: TJSONObject;
begin
  if AData = nil then Exit('null');
  case AData.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := Fmt(AData.AsFloat);
    jtString:
      if (AData.AsString = 'NaN') or (AData.AsString = 'Infinity')
        or (AData.AsString = '-Infinity') then Result := 'N:' + AData.AsString
      else Result := '"' + AData.AsString + '"';
    jtArray:
      begin
        Result := '[';
        for i := 0 to AData.Count - 1 do
        begin
          if i > 0 then Result := Result + ',';
          Result := Result + Canon(AData.Items[i]);
        end;
        Result := Result + ']';
      end;
    jtObject:
      begin
        o := TJSONObject(AData);
        if (o.Count = 1) and (o.Names[0] = '$num') then
          Exit('N:' + o.Items[0].AsString);
        keys := TStringList.Create;
        try
          keys.Sorted := True;
          keys.CaseSensitive := True;
          for i := 0 to o.Count - 1 do keys.Add(o.Names[i]);
          Result := '{';
          for i := 0 to keys.Count - 1 do
          begin
            if i > 0 then Result := Result + ',';
            Result := Result + keys[i] + ':' + Canon(o.Find(keys[i]));
          end;
          Result := Result + '}';
        finally
          keys.Free;
        end;
      end;
  else
    Result := '?';
  end;
end;

{ the proxy's data array of a fitted path: the command code, its numbers }
function PathData(const APath: TTyZrPath): TTyDoubleArray;
const cCode: array[TTyZrCmd] of Integer = (1, 2, 3, 4, 5, 6, 7);
var i, k, n: Integer;
begin
  Result := nil;
  for i := 0 to High(APath) do
  begin
    n := Length(Result);
    SetLength(Result, n + 1 + TyZrArgCount(APath[i].Cmd));
    Result[n] := cCode[APath[i].Cmd];
    for k := 0 to TyZrArgCount(APath[i].Cmd) - 1 do Result[n + 1 + k] := APath[i].V[k];
  end;
end;

{ the theme's stand-ins: upstream's two default icon inks }
const
  cUpNormal = '#6578ba';
  cUpEmph = '#404c76';

function ColourWord(const C: TTyTbColour; const ATheme: string): string;
begin
  case C.Kind of
    tbcNone: Result := 'none';
    tbcText: Result := C.Text;
  else
    Result := ATheme;
  end;
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartToolboxOracleTest.SetUp;
var sl: TStringList; ms: TJSONArray; k: Integer;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FMeas := TTbMeasurer.Create;
  FMeasRef := FMeas;
  ms := TJSONObject(FRoot).Arrays['measure'];
  for k := 0 to ms.Count - 1 do
    FMeas.Add(ms.Objects[k].Strings['string'], HexNum(ms.Objects[k].Find('width')),
      HexNum(ms.Objects[k].Find('height')));
  FIconState := TStringList.Create;
  FBad := 0;
  FCompared := 0;
  FSteps := 0;
  FReport := '';
end;

procedure TAdvChartToolboxOracleTest.TearDown;
begin
  TyChartClearToolboxHandlers;
  FreeAndNil(FLayout);
  FreeAndNil(FToolboxes);
  FreeAndNil(FOption);
  FreeAndNil(FZoom);
  FreeAndNil(FActs);
  FreeAndNil(FEvs);
  FreeAndNil(FIconState);
  FreeAndNil(FRoot);
  if FChart <> nil then FChart.Measurer := nil;
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartToolboxOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  { the first few of each kind }
  if (FBad <= 400) and (Pos(FName + ': ' + AWhat, FReport) = 0) then
    FReport := FReport + LineEnding + '  ' + FName + ' @' + IntToStr(FStepNo) + ': ' + AWhat;
end;

procedure TAdvChartToolboxOracleTest.SameHex(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double; ok: Boolean; q: QWord;
begin
  Inc(FCompared);
  want := HexNum(AWant);
  if IsNan(want) or IsNan(AGot) then ok := IsNan(want) and IsNan(AGot)
  else ok := AGot = want;
  if not ok then
  begin
    q := 0;
    System.Move(AGot, q, SizeOf(q));
    Miss(Format('%s is %s upstream, %s here (%s / %s)', [AWhat, Fmt(want), Fmt(AGot),
      AWant.AsString, LowerCase(IntToHex(q, 16))]));
  end;
end;

procedure TAdvChartToolboxOracleTest.SameNum(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  if (AWant = nil) or (AWant.JSONType <> jtNumber) then
  begin
    Miss(AWhat + ': no number upstream');
    Exit;
  end;
  want := AWant.AsFloat;
  if AGot <> want then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartToolboxOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartToolboxOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %s upstream, %s here', [AWhat, BoolToStr(AWant, True),
      BoolToStr(AGot, True)]));
end;

procedure TAdvChartToolboxOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TTbProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := FMeasRef;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
  TyChartRegisterToolboxHandler('ToolA', @FChart.HitToolA);
  TyChartRegisterToolboxHandler('ToolB', @FChart.HitToolB);
  TyChartRegisterToolboxHandler('ToolC', @FChart.HitToolC);
  TyChartRegisterToolboxHandler('Pair', @FChart.HitPair);
  TyChartRegisterToolboxHandler('Img', @FChart.HitImg);
end;

procedure TAdvChartToolboxOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartToolboxOracleTest.IconIndex(ATb: Integer; const AKey: string): Integer;
var
  spec: TTyToolboxSpec;
  i: Integer;
begin
  spec := FChart.ToolboxSpec(ATb);
  for i := 0 to High(spec.Icons) do
    if spec.Icons[i].Feature + '.' + spec.Icons[i].Name = AKey then Exit(i);
  Result := -1;
end;

{ a record's fields into the state carried forward }
procedure TAdvChartToolboxOracleTest.Take(ARec: TJSONObject);
var
  d: TJSONData;
  t, i: Integer;
  ic: TJSONObject;
begin
  d := ARec.Find('layout');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    FreeAndNil(FLayout);
    FLayout := d.Clone;
    { a new layout: every icon's state comes with it }
    FIconState.Clear;
  end;
  d := ARec.Find('toolboxes');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    FreeAndNil(FToolboxes);
    FToolboxes := d.Clone;
    for t := 0 to d.Count - 1 do
      for i := 0 to TJSONObject(d.Items[t]).Arrays['icons'].Count - 1 do
      begin
        ic := TJSONObject(d.Items[t]).Arrays['icons'].Objects[i];
        FIconState.Values[IntToStr(t) + '|' + ic.Strings['key']] := ic.AsJSON;
      end;
  end;
  d := ARec.Find('option');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    FreeAndNil(FOption);
    FOption := d.Clone;
  end;
  d := ARec.Find('zoom');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    FreeAndNil(FZoom);
    FZoom := d.Clone;
  end;
  d := ARec.Find('actions');
  if d is TJSONArray then
    for i := 0 to d.Count - 1 do FActs.Add(d.Items[i].Clone);
  d := ARec.Find('events');
  if d is TJSONArray then
    for i := 0 to d.Count - 1 do FEvs.Add(d.Items[i].Clone);
end;

procedure TAdvChartToolboxOracleTest.CheckLayout;
var
  t, i, k, n: Integer;
  tb, ic, bg: TJSONObject;
  spec: TTyToolboxSpec;
  lay: TTyToolboxLayout;
  e, shown, ap, aa: Boolean;
  r: TTyXYWH;
  data: TTyDoubleArray;
  arr: TJSONArray;
  what: string;
begin
  if FLayout = nil then Exit;
  SameStr('the toolbox count', IntToStr(FChart.ToolboxCount), IntToStr(FLayout.Count));
  for t := 0 to Min(FLayout.Count, FChart.ToolboxCount) - 1 do
  begin
    tb := TJSONObject(FLayout.Items[t]);
    spec := FChart.ToolboxSpec(t);
    lay := FChart.ToolboxLayout(t);
    SameBool(Format('toolbox %d shows', [t]), lay.Valid, tb.Booleans['show']);
    if not tb.Booleans['show'] then Continue;
    SameHex(Format('toolbox %d group x', [t]), lay.GroupX, tb.Arrays['group'].Items[0]);
    SameHex(Format('toolbox %d group y', [t]), lay.GroupY, tb.Arrays['group'].Items[1]);
    bg := nil;
    if tb.Find('background') is TJSONObject then bg := tb.Objects['background'];
    if bg <> nil then
    begin
      SameHex(Format('toolbox %d background x', [t]), lay.Background.X, bg.Find('x'));
      SameHex(Format('toolbox %d background y', [t]), lay.Background.Y, bg.Find('y'));
      SameHex(Format('toolbox %d background width', [t]), lay.Background.W, bg.Find('width'));
      SameHex(Format('toolbox %d background height', [t]), lay.Background.H, bg.Find('height'));
    end;
    arr := tb.Arrays['icons'];
    SameStr(Format('toolbox %d icon count', [t]), IntToStr(Length(spec.Icons)), IntToStr(arr.Count));
    for i := 0 to Min(arr.Count, Length(spec.Icons)) - 1 do
    begin
      ic := arr.Objects[i];
      what := Format('toolbox %d icon %s', [t, ic.Strings['key']]);
      SameStr(what + ' key', spec.Icons[i].Feature + '.' + spec.Icons[i].Name, ic.Strings['key']);
      if ic.Find('title').JSONType = jtNull then
        SameBool(what + ' has a title', spec.Icons[i].HasTitle, False)
      else
        SameStr(what + ' title', spec.Icons[i].Title, ic.Strings['title']);
      SameBool(what + ' is an image', spec.Icons[i].IsImage, ic.Strings['kind'] = 'image');
      SameHex(what + ' x', spec.Icons[i].X, ic.Find('x'));
      SameHex(what + ' y', spec.Icons[i].Y, ic.Find('y'));
      FChart.ToolboxIconState(t, i, e, shown, ap, aa);
      r := TyToolboxIconRect(spec, spec.Icons[i], e);
      SameHex(what + ' rect x', r.X, ic.Arrays['rect'].Items[0]);
      SameHex(what + ' rect y', r.Y, ic.Arrays['rect'].Items[1]);
      SameHex(what + ' rect width', r.W, ic.Arrays['rect'].Items[2]);
      SameHex(what + ' rect height', r.H, ic.Arrays['rect'].Items[3]);
      if ic.Strings['kind'] = 'path' then
      begin
        SameHex(what + ' path rect x', spec.Icons[i].PathRect.X, ic.Arrays['pathRect'].Items[0]);
        SameHex(what + ' path rect y', spec.Icons[i].PathRect.Y, ic.Arrays['pathRect'].Items[1]);
        SameHex(what + ' path rect width', spec.Icons[i].PathRect.W, ic.Arrays['pathRect'].Items[2]);
        SameHex(what + ' path rect height', spec.Icons[i].PathRect.H, ic.Arrays['pathRect'].Items[3]);
        data := PathData(spec.Icons[i].Path);
        n := ic.Arrays['data'].Count;
        SameStr(what + ' data length', IntToStr(Length(data)), IntToStr(n));
        for k := 0 to Min(n, Length(data)) - 1 do
          SameHex(Format('%s data[%d]', [what, k]), data[k], ic.Arrays['data'].Items[k]);
      end;
    end;
  end;
end;

{ each icon's state as upstream carries it }
procedure TAdvChartToolboxOracleTest.CheckIcons(ACursorRole: string; ARec: TJSONObject);
var
  t, i, k: Integer;
  spec: TTyToolboxSpec;
  e, shown, ap, aa: Boolean;
  ic, txt, emph, st, ist, fo: TJSONObject;
  key, what, want, got: string;
  place: TTyTbTitlePlace;
  sty: TTyTbItemStyle;
  pos: TJSONData;
begin
  for t := 0 to FChart.ToolboxCount - 1 do
  begin
    spec := FChart.ToolboxSpec(t);
    { the features' iconStatus }
    if (FToolboxes <> nil) and (t < FToolboxes.Count) then
    begin
      ist := TJSONObject(FToolboxes.Items[t]).Objects['iconStatus'];
      for k := 0 to ist.Count - 1 do
      begin
        fo := TJSONObject(ist.Items[k]);
        for i := 0 to fo.Count - 1 do
          SameStr(Format('toolbox %d %s.%s status', [t, ist.Names[k], fo.Names[i]]),
            FChart.ToolboxIconStatus(t, ist.Names[k], fo.Names[i]), fo.Items[i].AsString);
      end;
    end;
    for i := 0 to High(spec.Icons) do
    begin
      key := spec.Icons[i].Feature + '.' + spec.Icons[i].Name;
      what := Format('toolbox %d icon %s', [t, key]);
      if FIconState.Values[IntToStr(t) + '|' + key] = '' then Continue;
      ic := TJSONObject(GetJSON(FIconState.Values[IntToStr(t) + '|' + key]));
      try
        FChart.ToolboxIconState(t, i, e, shown, ap, aa);
        SameBool(what + ' emphasised', e, ic.Arrays['states'].Count > 0);
        { the stroke: the written one, or the theme for upstream's own }
        st := ic.Objects['style'];
        sty := TyTbStyleOf(spec.Icons[i], e);
        if e then got := ColourWord(sty.Stroke, cUpEmph)
        else got := ColourWord(sty.Stroke, cUpNormal);
        if st.Find('stroke').JSONType = jtString then
          SameStr(what + ' stroke', got, st.Strings['stroke']);
        if st.Find('lineWidth').JSONType = jtNumber then
          SameNum(what + ' line width', sty.LineWidth, st.Find('lineWidth'));
        { the render-time adjustment }
        emph := ic.Objects['emphasis'];
        pos := emph.Find('position');
        if (pos = nil) or (pos.JSONType = jtNull) then
          SameStr(what + ' adjustment', IntToStr(Ord(spec.Icons[i].Adjust)), IntToStr(Ord(tajNone)))
        else if pos.JSONType = jtString then
          SameStr(what + ' adjustment', IntToStr(Ord(spec.Icons[i].Adjust)), IntToStr(Ord(tajTop)))
        else
        begin
          if TJSONArray(pos).Items[0].JSONType = jtString then
            SameStr(what + ' adjustment', IntToStr(Ord(spec.Icons[i].Adjust)), IntToStr(Ord(tajRight)))
          else
            SameStr(what + ' adjustment', IntToStr(Ord(spec.Icons[i].Adjust)), IntToStr(Ord(tajLeft)));
          SameNum(what + ' adjusted y', spec.Icons[i].AdjustY, TJSONArray(pos).Items[1]);
        end;
        { the title }
        if ic.Find('text') is TJSONObject then
        begin
          txt := ic.Objects['text'];
          SameBool(what + ' title shown', shown, not txt.Booleans['ignore']);
          if shown and not txt.Booleans['ignore'] then
          begin
            place := FChart.ToolboxTitle(t, i);
            SameHex(what + ' title x', place.X, txt.Find('x'));
            SameHex(what + ' title y', place.Y, txt.Find('y'));
            SameStr(what + ' title align', place.Align, txt.Strings['align']);
            SameStr(what + ' title vertical align', place.VAlign, txt.Strings['verticalAlign']);
            if txt.Find('text').JSONType = jtString then
              SameStr(what + ' title text', spec.Icons[i].Title, txt.Strings['text']);
            { textFill, else the emphasis fill, else its stroke }
            if spec.Icons[i].TextFill.Kind = tbcText then want := spec.Icons[i].TextFill.Text
            else if spec.Icons[i].Emph.HasFill and (spec.Icons[i].Emph.Fill.Kind = tbcText) then
              want := spec.Icons[i].Emph.Fill.Text
            else want := ColourWord(TyTbStyleOf(spec.Icons[i], True).Stroke, cUpEmph);
            if txt.Find('fill').JSONType = jtString then
              SameStr(what + ' title colour', want, txt.Strings['fill']);
          end;
        end;
      finally
        ic.Free;
      end;
    end;
  end;
  { the cursor }
  if (ARec <> nil) and (ARec.Find('cursor') <> nil) and (ARec.Find('cursor').JSONType = jtString) then
  begin
    want := ARec.Strings['cursor'];
    if want = 'crosshair' then SameStr('the cursor', FChart.ToolboxCursorName, 'crosshair')
    else if (want = 'pointer') and (Copy(ACursorRole, 1, 7) = 'toolbox') then
      SameStr('the cursor', FChart.ToolboxCursorName, 'pointer')
    else if want = 'default' then SameStr('the cursor', FChart.ToolboxCursorName, '');
  end;
end;

{ upstream's actions and events since the last comparison against the
  port's: the toolbox actions by the events they emit, the dataZoom ones by
  OnDataZoom }
procedure TAdvChartToolboxOracleTest.CheckActions(AStep: Integer);
const
  cMagicKeys: array[0..4] of string = ('type', 'stack', 'data', 'smooth', 'barWidth');
  cEvNames: array[0..3] of string = ('magictypechanged', 'restore', 'dataviewchanged',
    'globalcursortaken');
var
  i, j, k, s, si, zi: Integer;
  a, pay, ws, gs, pnew, item, wnew: TJSONObject;
  t, key, id: string;
  port: TJSONData;
  evs: TStringList;
  wsArr, gsArr, b: TJSONArray;
  act: TTyDzAction;
  spec: TTyDataZoomSpec;
  found: Boolean;
  counts: array[0..3] of Integer;

  function PortEvent(const AType: string; ANth: Integer): TJSONObject;
  var q, c: Integer;
  begin
    Result := nil;
    c := 0;
    for q := 0 to evs.Count - 1 do
      if Copy(evs[q], 1, Pos(#9, evs[q]) - 1) = AType then
      begin
        if c = ANth then
        begin
          Result := TJSONObject(GetJSON(Copy(evs[q], Pos(#9, evs[q]) + 1, MaxInt)));
          Exit;
        end;
        Inc(c);
      end;
  end;

  function CountEv(const AType: string): Integer;
  var q: Integer;
  begin
    Result := 0;
    for q := 0 to evs.Count - 1 do
      if Copy(evs[q], 1, Pos(#9, evs[q]) - 1) = AType then Inc(Result);
  end;

  function SeriesOfId(const AId: string): Integer;
  var q: Integer;
  begin
    for q := 0 to 9 do
      if Nul(FChart.ComponentModelId('series', q)) = AId then Exit(q);
    Result := -1;
  end;

begin
  evs := FChart.Events;
  for i := 0 to 3 do counts[i] := 0;
  { the dataZoom batches the toolbox dispatched: OnDataZoom's }
  zi := 0;
  for i := 0 to FActs.Count - 1 do
  begin
    a := TJSONObject(FActs.Items[i]);
    if a.Strings['type'] <> 'dataZoom' then Continue;
    if zi > High(FChart.Zooms) then
    begin
      Miss(Format('step %d: a dataZoom action upstream, none here', [AStep]));
      Continue;
    end;
    act := FChart.Zooms[zi];
    Inc(zi);
    b := a.Arrays['batch'];
    SameStr(Format('step %d: the dataZoom batch length', [AStep]), IntToStr(Length(act.Items)), IntToStr(b.Count));
    for j := 0 to Min(b.Count, Length(act.Items)) - 1 do
    begin
      item := b.Objects[j];
      id := item.Strings['dataZoomId'];
      key := Copy(id, Pos('toolbox-dataZoom_', id) + Length('toolbox-dataZoom_'), MaxInt);
      key := Copy(key, 1, 1) + Copy(key, 6, MaxInt);
      spec := FChart.DataZoomSpec(act.Items[j].DataZoomIndex);
      if Length(spec.Targets) > 0 then
        SameStr(Format('step %d: batch[%d] axis', [AStep, j]),
          spec.Targets[0].Dim + IntToStr(spec.Targets[0].AxisIndex), key);
      SameBool(Format('step %d: batch[%d] by value', [AStep, j]), act.Items[j].IsValue,
        item.Find('startValue') <> nil);
      if item.Find('startValue') <> nil then
      begin
        SameNum(Format('step %d: batch[%d] startValue', [AStep, j]), act.Items[j].Start, item.Find('startValue'));
        SameNum(Format('step %d: batch[%d] endValue', [AStep, j]), act.Items[j].Stop, item.Find('endValue'));
      end
      else
      begin
        SameNum(Format('step %d: batch[%d] start', [AStep, j]), act.Items[j].Start, item.Find('start'));
        SameNum(Format('step %d: batch[%d] end', [AStep, j]), act.Items[j].Stop, item.Find('end'));
      end;
    end;
  end;
  if zi <= High(FChart.Zooms) then
    Miss(Format('step %d: %d dataZoom action(s) here not upstream', [AStep, Length(FChart.Zooms) - zi]));
  { the toolbox's actions by their events: the payload with the event's name }
  for i := 0 to FEvs.Count - 1 do
  begin
    a := TJSONObject(FEvs.Items[i]);
    t := a.Strings['type'];
    if ((t = 'click') or (t = 'mouseover') or (t = 'mouseout'))
      and (a.Find('payload') is TJSONObject)
      and (a.Objects['payload'].Find('componentType') <> nil)
      and (a.Objects['payload'].Find('componentType').JSONType = jtString)
      and (a.Objects['payload'].Strings['componentType'] = 'toolbox') then
      Miss('a toolbox mouse event upstream');
    k := -1;
    for j := 0 to 3 do
      if cEvNames[j] = t then k := j;
    if k < 0 then Continue;
    a := a.Objects['payload'];
    pay := PortEvent(cEvNames[k], counts[k]);
    Inc(counts[k]);
    Inc(FCompared);
    if pay = nil then
    begin
      Miss(Format('step %d: %s upstream, not here', [AStep, t]));
      Continue;
    end;
    try
      if t = 'magictypechanged' then
      begin
        SameStr(Format('step %d: currentType', [AStep]), pay.Get('currentType', ''), a.Strings['currentType']);
        if a.Find('newTitle') <> nil then
          SameStr(Format('step %d: newTitle', [AStep]), Canon(pay.Find('newTitle')), Canon(a.Find('newTitle')))
        else
          SameBool(Format('step %d: no newTitle', [AStep]), pay.Find('newTitle') = nil, True);
        SameStr(Format('step %d: featureName', [AStep]), pay.Get('featureName', ''), a.Strings['featureName']);
        { the series, mapped by the id upstream writes to the position here }
        pnew := pay.Objects['newOption'];
        wnew := a.Objects['newOption'];
        wsArr := wnew.Arrays['series'];
        gsArr := pnew.Arrays['series'];
        for s := 0 to wsArr.Count - 1 do
        begin
          ws := wsArr.Objects[s];
          si := SeriesOfId(ws.Strings['id']);
          if (si < 0) or (si >= gsArr.Count) or not (gsArr.Items[si] is TJSONObject)
            or (TJSONObject(gsArr.Items[si]).Count = 0) then
          begin
            Miss(Format('step %d: series %s changed upstream, not here', [AStep, ws.Strings['id']]));
            Continue;
          end;
          gs := TJSONObject(gsArr.Items[si]);
          for j := 0 to High(cMagicKeys) do
          begin
            key := cMagicKeys[j];
            port := gs.Find(key);
            if (ws.Find(key) = nil) or (ws.Find(key).JSONType = jtNull) then
            begin
              Inc(FCompared);
              if (port <> nil) and (port.JSONType <> jtNull) then
                Miss(Format('step %d: series %d %s absent upstream, %s here', [AStep, si, key, Canon(port)]));
            end
            else if (key = 'smooth') and (port = nil) and (ws.Find(key).JSONType = jtBoolean)
              and not ws.Booleans[key] then
              Inc(FCompared)
            else
              SameStr(Format('step %d: series %d %s', [AStep, si, key]), Canon(port), Canon(ws.Find(key)));
          end;
        end;
        { no series here that upstream left alone }
        for s := 0 to gsArr.Count - 1 do
          if (gsArr.Items[s] is TJSONObject) and (TJSONObject(gsArr.Items[s]).Count > 0) then
          begin
            found := False;
            for j := 0 to wsArr.Count - 1 do
              if SeriesOfId(wsArr.Objects[j].Strings['id']) = s then found := True;
            if not found then Miss(Format('step %d: series %d changed here, not upstream', [AStep, s]));
          end;
        SameStr(Format('step %d: newOption xAxis', [AStep]), Canon(pnew.Find('xAxis')), Canon(wnew.Find('xAxis')));
        SameStr(Format('step %d: newOption yAxis', [AStep]), Canon(pnew.Find('yAxis')), Canon(wnew.Find('yAxis')));
      end
      else if t = 'dataviewchanged' then
        SameStr(Format('step %d: the data view''s option', [AStep]), Canon(pay.Find('newOption')),
          Canon(a.Find('newOption')))
      else if t = 'globalcursortaken' then
      begin
        SameStr(Format('step %d: the cursor key', [AStep]), pay.Get('key', ''), a.Strings['key']);
        SameStr(Format('step %d: the zoom active', [AStep]), Canon(pay.Find('dataZoomSelectActive')),
          Canon(a.Find('dataZoomSelectActive')));
      end;
    finally
      pay.Free;
    end;
  end;
  for j := 0 to 3 do
    if CountEv(cEvNames[j]) <> counts[j] then
      Miss(Format('step %d: %d %s event(s) here, %d upstream', [AStep, CountEv(cEvNames[j]), cEvNames[j], counts[j]]));
  FChart.Events.Clear;
  FChart.Zooms := nil;
  FActs.Clear;
  FEvs.Clear;
end;

procedure TAdvChartToolboxOracleTest.CheckOption;
const
  cOptKeys: array[0..4] of string = ('type', 'name', 'stack', 'data', 'barWidth');
var
  port, ps, us: TJSONData;
  pa, ua: TJSONArray;
  i, j, k: Integer;
  key, ax: string;
  u: TJSONObject;
begin
  if FOption = nil then Exit;
  port := GetJSON(FChart.GetOptionJson);
  try
    u := TJSONObject(FOption);
    ua := u.Arrays['series'];
    pa := nil;
    if TJSONObject(port).Find('series') is TJSONArray then pa := TJSONObject(port).Arrays['series'];
    if pa = nil then
    begin
      Miss('no series in the option here');
      Exit;
    end;
    SameStr('the series count', IntToStr(pa.Count), IntToStr(ua.Count));
    for i := 0 to Min(pa.Count, ua.Count) - 1 do
    begin
      ps := pa.Items[i];
      us := ua.Items[i];
      for k := 0 to High(cOptKeys) do
      begin
        key := cOptKeys[k];
        if TJSONObject(us).Find(key) = nil then
        begin
          if (TJSONObject(ps).Find(key) <> nil) and (TJSONObject(ps).Find(key).JSONType <> jtNull) then
            Miss(Format('series %d %s absent upstream, %s here', [i, key, Canon(TJSONObject(ps).Find(key))]));
          Continue;
        end;
        SameStr(Format('series %d %s', [i, key]), Canon(TJSONObject(ps).Find(key)),
          Canon(TJSONObject(us).Find(key)));
      end;
      { smooth: upstream's default is false }
      if TJSONObject(us).Find('smooth') <> nil then
      begin
        if TJSONObject(ps).Find('smooth') <> nil then
          SameStr(Format('series %d smooth', [i]), Canon(TJSONObject(ps).Find('smooth')),
            Canon(TJSONObject(us).Find('smooth')))
        else
          SameStr(Format('series %d smooth', [i]), 'false', Canon(TJSONObject(us).Find('smooth')));
      end;
    end;
    for k := 0 to 1 do
    begin
      if k = 0 then ax := 'xAxis' else ax := 'yAxis';
      if not (u.Find(ax) is TJSONArray) then Continue;
      ua := u.Arrays[ax];
      pa := nil;
      if TJSONObject(port).Find(ax) is TJSONArray then pa := TJSONObject(port).Arrays[ax];
      for i := 0 to ua.Count - 1 do
      begin
        us := ua.Items[i];
        ps := nil;
        if (pa <> nil) and (i < pa.Count) then ps := pa.Items[i];
        if not (ps is TJSONObject) then Continue;
        { what the tree holds: the written keys }
        for j := 0 to 1 do
        begin
          if j = 0 then key := 'data' else key := 'boundaryGap';
          if TJSONObject(ps).Find(key) <> nil then
            SameStr(Format('%s %d %s', [ax, i, key]), Canon(TJSONObject(ps).Find(key)),
              Canon(TJSONObject(us).Find(key)));
        end;
      end;
    end;
    if u.Find('title') is TJSONArray then
      for i := 0 to u.Arrays['title'].Count - 1 do
      begin
        ps := nil;
        if (TJSONObject(port).Find('title') is TJSONArray) and (i < TJSONObject(port).Arrays['title'].Count) then
          ps := TJSONObject(TJSONObject(port).Arrays['title'].Items[i]).Find('text');
        SameStr(Format('title %d', [i]), Canon(ps), Canon(u.Arrays['title'].Items[i]));
      end;
  finally
    port.Free;
  end;
end;

procedure TAdvChartToolboxOracleTest.CheckZoom;
var
  z: TJSONObject;
  dz: TJSONArray;
  i, k: Integer;
  key: string;
  zoom: TTyAxisZoom;
  win: TTyDzWindow;
  host: Integer;
  r: TTyXYWH;
  hasCover: Boolean;
  ax: TTyAxis;
  ext: TTyRange;
  spec: TTyDataZoomSpec;
begin
  if FZoom = nil then Exit;
  z := TJSONObject(FZoom);
  if z.Find('active').JSONType = jtBoolean then
    SameBool('the zoom is on', FChart.ToolboxZoomActive, z.Booleans['active']);
  SameStr('the history', IntToStr(FChart.ToolboxHistoryCount), IntToStr(z.Integers['history']));
  hasCover := FChart.ToolboxCover(r);
  SameBool('the cover', hasCover, z.Find('cover').JSONType = jtObject);
  if hasCover and (z.Find('cover').JSONType = jtObject) then
  begin
    SameHex('the cover x', r.X, z.Objects['cover'].Arrays['rect'].Items[0]);
    SameHex('the cover y', r.Y, z.Objects['cover'].Arrays['rect'].Items[1]);
    SameHex('the cover width', r.W, z.Objects['cover'].Arrays['rect'].Items[2]);
    SameHex('the cover height', r.H, z.Objects['cover'].Arrays['rect'].Items[3]);
  end;
  dz := z.Arrays['dataZooms'];
  for i := 0 to dz.Count - 1 do
  begin
    key := dz.Objects[i].Strings['key'];
    if Copy(key, 1, 7) = 'author:' then
    begin
      { an author's dataZoom: the window of the first axis it drives }
      spec := FChart.DataZoomSpec(StrToInt(Copy(key, 8, MaxInt)));
      if Length(spec.Targets) = 0 then Continue;
      if not FChart.AxisZoom(spec.Targets[0].Dim + 'Axis', spec.Targets[0].AxisIndex,
        zoom, win, host) then
      begin
        Miss(key + ' zooms nothing here');
        Continue;
      end;
      SameHex(key + ' start', win.Percent[0], dz.Objects[i].Arrays['range'].Items[0]);
      SameHex(key + ' end', win.Percent[1], dz.Objects[i].Arrays['range'].Items[1]);
      Continue;
    end;
    if Copy(key, 1, 7) <> 'select:' then Continue;
    k := StrToInt(Copy(key, 9, MaxInt));
    if key[8] = 'x' then
    begin
      if not FChart.AxisZoom('xAxis', k, zoom, win, host) then
      begin
        Miss(key + ' zooms nothing here');
        Continue;
      end;
    end
    else if not FChart.AxisZoom('yAxis', k, zoom, win, host) then
    begin
      Miss(key + ' zooms nothing here');
      Continue;
    end;
    SameHex(key + ' start', win.Percent[0], dz.Objects[i].Arrays['range'].Items[0]);
    SameHex(key + ' end', win.Percent[1], dz.Objects[i].Arrays['range'].Items[1]);
  end;
  { the axes' extents }
  for i := 0 to z.Objects['extents'].Count - 1 do
  begin
    key := z.Objects['extents'].Names[i];
    if Pos('Text', key) > 0 then Continue;
    k := StrToInt(Copy(key, 2, MaxInt));
    ax := nil;
    if FChart.Build <> nil then ax := FChart.Build.Axis(key[1] + 'Axis', k);
    if ax = nil then Continue;
    ext := ax.Scale.GetExtent;
    SameHex(key + ' extent lo', ext.Start, z.Objects['extents'].Arrays[key].Items[0]);
    SameHex(key + ' extent hi', ext.Stop, z.Objects['extents'].Arrays[key].Items[1]);
  end;
end;

procedure TAdvChartToolboxOracleTest.CheckRecord(ARec: TJSONObject; const AHover: string;
  AStep: Integer);
var
  d: TJSONData;
  o: TJSONObject;
  opts, mine: TJSONObject;
  i: Integer;
  want: string;
begin
  CheckLayout;
  CheckIcons(AHover, ARec);
  CheckActions(AStep);
  CheckOption;
  CheckZoom;
  { saveAsImage }
  d := ARec.Find('saved');
  if d is TJSONObject then
  begin
    o := TJSONObject(d);
    SameBool(Format('step %d: the save was asked', [AStep]), FChart.SaveAsked, True);
    SameStr(Format('step %d: the file name', [AStep]), FChart.SaveName, o.Strings['download']);
    opts := o.Objects['opts'];
    mine := TJSONObject(GetJSON(FChart.SaveOpts));
    try
      SameStr(Format('step %d: the type', [AStep]), Canon(mine.Find('type')), Canon(opts.Find('type')));
      SameStr(Format('step %d: the exclusions', [AStep]), Canon(mine.Find('excludeComponents')),
        Canon(opts.Find('excludeComponents')));
      if opts.Find('pixelRatio') <> nil then
        SameStr(Format('step %d: the pixel ratio', [AStep]), Canon(mine.Find('pixelRatio')),
          Canon(opts.Find('pixelRatio')));
      { upstream's '#fff' is the skin's ground here: no background written }
      if mine.Find('backgroundColor') <> nil then
        SameStr(Format('step %d: the background', [AStep]), Canon(mine.Find('backgroundColor')),
          Canon(opts.Find('backgroundColor')))
      else
        SameStr(Format('step %d: the background', [AStep]), '"#fff"', Canon(opts.Find('backgroundColor')));
    finally
      mine.Free;
    end;
    FChart.SaveAsked := False;
  end;
  { the custom onclick calls }
  d := ARec.Find('clicks');
  if d is TJSONArray then
  begin
    SameStr(Format('step %d: the onclick calls', [AStep]), IntToStr(FChart.Clicks.Count), IntToStr(d.Count));
    for i := 0 to Min(d.Count, FChart.Clicks.Count) - 1 do
    begin
      o := TJSONObject(d.Items[i]);
      want := o.Strings['handler'] + '|' + o.Strings['feature'] + '|' + o.Strings['icon'];
      SameStr(Format('step %d: onclick %d', [AStep, i]), FChart.Clicks[i], want);
    end;
    FChart.Clicks.Clear;
  end;
  { the data view's error }
  d := ARec.Find('error');
  if (d <> nil) and (d.JSONType = jtString) then
    SameBool(Format('step %d: the data view refused its text', [AStep]), FChart.ToolboxError <> '', True);
end;

procedure TAdvChartToolboxOracleTest.RunScenario(ASc: TJSONObject);
var
  steps: TJSONArray;
  st, step, rec, nx: TJSONObject;
  i, j, x, y: Integer;
  t, at, hover: string;
  defer: Boolean;
  dv: TJSONObject;
begin
  FName := ASc.Strings['id'];
  FreeAndNil(FLayout);
  FreeAndNil(FToolboxes);
  FreeAndNil(FOption);
  FreeAndNil(FZoom);
  FIconState.Clear;
  FreeAndNil(FActs);
  FreeAndNil(FEvs);
  FActs := TJSONArray.Create;
  FEvs := TJSONArray.Create;
  NewChart;
  FChart.SetOption(ASc.Objects['option'].AsJSON, True);
  RenderNow;
  FStepNo := -1;
  Take(ASc.Objects['initial']);
  CheckRecord(ASc.Objects['initial'], '', -1);
  steps := ASc.Arrays['steps'];
  for i := 0 to steps.Count - 1 do
  begin
    st := steps.Objects[i];
    FStepNo := i;
    step := st.Objects['step'];
    rec := st.Objects['record'];
    t := step.Strings['type'];
    hover := '';
    if st.Find('hover').JSONType = jtString then hover := st.Strings['hover'];
    defer := False;
    if (t = 'mousemove') or (t = 'mousedown') or (t = 'mouseup') or (t = 'click') then
    begin
      { an icon placed at NaN: upstream's pointer goes to NaN, which hits
        nothing -- a point off the canvas here }
      if step.Find('x').JSONType = jtNumber then x := step.Integers['x'] else x := -10000;
      if step.Find('y').JSONType = jtNumber then y := step.Integers['y'] else y := -10000;
      at := '';
      if step.Find('at').JSONType = jtString then at := step.Strings['at'];
      if t = 'mousemove' then FChart.Move(x, y)
      else if t = 'mousedown' then FChart.Down(x, y)
      else if t = 'mouseup' then
      begin
        { the dataView's panel: the edits and the button that follow its click }
        if at = 'toolbox0.dataView.dataView' then
        begin
          FChart.DvEdits.Clear;
          FChart.DvButton := '';
          for j := i + 1 to steps.Count - 1 do
          begin
            nx := steps.Objects[j].Objects['step'];
            if nx.Strings['type'] = 'dvEdit' then
            begin
              if nx.Find('value') <> nil then FChart.DvEdits.Add(nx.Strings['value'])
              else FChart.DvEdits.Add(nx.Strings['find'] + #1 + nx.Strings['replace']);
            end
            else if nx.Strings['type'] = 'dvButton' then
            begin
              FChart.DvButton := nx.Strings['button'];
              Break;
            end;
          end;
        end;
        FChart.Up(x, y);
        { zrender's mouseup and the click after it are one release here }
        if (i + 1 < steps.Count) and (steps.Objects[i + 1].Objects['step'].Strings['type'] = 'click') then
          defer := True;
      end;
      { click: the release did it }
    end
    else if (t = 'idle') or (t = 'dvEdit') or (t = 'dvButton') then
      { the frame the clock's advance runs }
      FChart.ToolboxFrame
    else if t = 'leave' then FChart.Leave
    else if t = 'action' then FChart.DispatchAction(step.Objects['payload'].AsJSON)
    else if t = 'set' then
    begin
      if (step.Find('notMerge') <> nil) and step.Booleans['notMerge'] then
        FChart.SetOption(step.Objects['option'].AsJSON, True)
      else
        FChart.MergeOption(step.Objects['option'].AsJSON);
    end;
    RenderNow;
    Inc(FSteps);
    Take(rec);
    { the panel: what it showed, against the record of its click }
    dv := nil;
    if rec.Find('dataView') is TJSONObject then dv := rec.Objects['dataView'];
    if (t = 'click') and (dv <> nil) then
    begin
      SameBool('the data view was shown', FChart.DvShown, True);
      SameStr('the data view''s heading', FChart.DvTitle, dv.Strings['header']);
      SameStr('the data view''s text', FChart.DvText, dv.Strings['value']);
      SameBool('the data view is read only', FChart.DvReadOnly, dv.Booleans['readOnly']);
      if dv.Booleans['readOnly'] then
        SameStr('the data view''s buttons', FChart.DvClose, dv.Arrays['buttons'].Items[0].AsString)
      else
      begin
        SameStr('the refresh button', FChart.DvRefresh, dv.Arrays['buttons'].Items[0].AsString);
        SameStr('the close button', FChart.DvClose, dv.Arrays['buttons'].Items[1].AsString);
      end;
      FChart.DvShown := False;
    end;
    { the panel's steps happen inside the click here: compared at the button }
    if (t = 'dvEdit') or ((t = 'click') and (dv <> nil)) then defer := True;
    if not defer then CheckRecord(rec, hover, i);
  end;
end;

procedure TAdvChartToolboxOracleTest.RunGroup(const APrefix1, APrefix2: string);
var
  scs: TJSONArray;
  i: Integer;
  id: string;
begin
  scs := TJSONObject(FRoot).Arrays['scenarios'];
  for i := 0 to scs.Count - 1 do
  begin
    id := scs.Objects[i].Strings['id'];
    if (Copy(id, 1, Length(APrefix1)) = APrefix1)
      or ((APrefix2 <> '') and (Copy(id, 1, Length(APrefix2)) = APrefix2)) then
    try
      RunScenario(scs.Objects[i]);
    except
      on E: Exception do Miss('raised ' + E.ClassName + ': ' + E.Message + ' at '
        + BackTraceStrFunc(ExceptAddr));
    end;
  end;
  if FMeas.Missed <> '' then Miss('texts the table does not measure:' + FMeas.Missed);
  AssertTrue(Format('%d of %d comparisons differ over %d steps:%s',
    [FBad, FCompared, FSteps, FReport]), FBad = 0);
  AssertTrue('something was compared', FCompared > 100);
end;

procedure TAdvChartToolboxOracleTest.TestLayoutAndHoverAsUpstream;
begin
  RunGroup('L-', '');
end;

procedure TAdvChartToolboxOracleTest.TestMagicTypeAndRestoreAsUpstream;
begin
  RunGroup('M-', 'R-');
end;

procedure TAdvChartToolboxOracleTest.TestSelectZoomAndBackAsUpstream;
begin
  RunGroup('Z-', '');
end;

procedure TAdvChartToolboxOracleTest.TestDataViewAsUpstream;
begin
  RunGroup('D-', '');
end;

procedure TAdvChartToolboxOracleTest.TestSaveAsImageAndCustomAsUpstream;
begin
  RunGroup('S-', '');
end;

{ ==================== the hand-written tests ==================== }

procedure TAdvChartToolboxTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TTbProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
end;

procedure TAdvChartToolboxTest.TearDown;
begin
  TyChartClearToolboxHandlers;
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartToolboxTest.Show(const AOption: string);
begin
  FChart.SetOption(AOption, True);
  RenderNow;
end;

procedure TAdvChartToolboxTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartToolboxTest.TestDataViewTextAndParseBack;
var
  g: TTyDvGroupArray;
  l: TTyDvListArray;
  meta: TTyDvMetaArray;
  s, err: string;
  o: TJSONObject;
begin
  SetLength(g, 1);
  g[0].AxisDim := 'x';
  g[0].AxisIndex := 0;
  g[0].Categories := TTyStringArray.Create('a', 'b');
  g[0].Names := TTyStringArray.Create('S');
  SetLength(g[0].Columns, 1);
  g[0].Columns[0] := TTyDoubleArray.Create(1.5, NaN);
  SetLength(l, 1);
  l[0].Name := 'P';
  l[0].RowNames := TTyStringArray.Create('x', '');
  SetLength(l[0].Rows, 2);
  l[0].Rows[0] := TTyDoubleArray.Create(3);
  l[0].Rows[1] := TTyDoubleArray.Create(4, 5);
  s := TyDataViewText(g, l);
  AssertEquals('the table and the list, one block apart',
    ' '#9'S'#10'a'#9'1.5'#10'b'#9'NaN'#10#10 + TyDataViewBlock + #10#10'P'#10'x'#9'3'#10'4'#9'5', s);
  SetLength(meta, 1);
  meta[0].AxisDim := 'x';
  meta[0].AxisIndex := 0;
  o := TyDataViewParse(s, meta, err);
  try
    AssertNotNull('it parses back', o);
    AssertEquals('the series and the axis',
      '{"series":[{"name":"S","data":["1.5","NaN"]},{"name":"P","data":[{"name":"x","value":3},[4,5]]}],"xAxis":[{"data":["a","b"]}]}',
      TyTbJson(o));
  finally
    o.Free;
  end;
  { a tab in a block no axis stands behind: upstream throws }
  o := TyDataViewParse('P'#9'x'#10'1', nil, err);
  AssertNull('no option', o);
  AssertTrue('the reason', err <> '');
end;

procedure TAdvChartToolboxTest.TestTheDataViewDialogIsBuiltNotShown;
var
  d: TTyDialog;
  m: TTyMemo;
begin
  d := TyBuildDataViewDialog('Data View', 'a'#10'b', False, 'Close', 'Refresh', m);
  try
    AssertEquals('the heading is the caption', 'Data View', d.Caption);
    AssertEquals('two buttons', 2, d.ButtonCount);
    AssertEquals('Refresh is the rightmost', 'Refresh', d.Buttons[0].Caption);
    AssertEquals('then Close', 'Close', d.Buttons[1].Caption);
    AssertFalse('the text can be edited', m.ReadOnly);
    AssertEquals('the text', 2, m.Lines.Count);
    AssertEquals('the text', 'a', m.Lines[0]);
    AssertEquals('the text', 'b', m.Lines[1]);
  finally
    d.Free;
  end;
  d := TyBuildDataViewDialog('Table', 'x', True, 'Shut', 'Apply', m);
  try
    AssertEquals('read only: Close alone', 1, d.ButtonCount);
    AssertEquals('Close', 'Shut', d.Buttons[0].Caption);
    AssertTrue('the text is read only', m.ReadOnly);
  finally
    d.Free;
  end;
end;

procedure TAdvChartToolboxTest.TestSaveAsImageGoesThroughTheEventThenTheSeam;
var
  path: string;
  fs: TFileStream;
  b: array[0..7] of Byte;
begin
  Show('{"animation":false,"title":{"text":"Sales"},"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[1,2]}],"toolbox":{"feature":{"saveAsImage":{}}}}');
  AssertTrue('the icon is there', FChart.ToolboxClick(0, 'saveAsImage', 'saveAsImage'));
  AssertTrue('the seam was asked', FChart.SaveAsked);
  AssertEquals('the title names the file', 'Sales.png', FChart.SaveName);
  AssertEquals('png', 'png', FChart.SaveType);
  AssertTrue('the toolbox is excluded', Pos('"excludeComponents":["toolbox"]', FChart.SaveOpts) > 0);
  { the seam answers with a path: the file is written, a PNG }
  path := GetTempDir + 'c16_toolbox_save.png';
  DeleteFile(path);
  FChart.SaveTo := path;
  FChart.SaveAsked := False;
  FChart.ToolboxClick(0, 'saveAsImage', 'saveAsImage');
  AssertTrue('written', FileExists(path));
  fs := TFileStream.Create(path, fmOpenRead);
  try
    fs.ReadBuffer(b, 8);
  finally
    fs.Free;
  end;
  AssertEquals('a PNG', $89, b[0]);
  AssertEquals('a PNG', Ord('P'), b[1]);
  DeleteFile(path);
end;

procedure TAdvChartToolboxTest.TestTheActionsByTheApi;
begin
  Show('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"line","name":"L","data":[1,2,3]}],'
    + '"toolbox":{"feature":{"dataZoom":{},"magicType":{"type":["line","bar"]},"restore":{}}}}');
  AssertTrue('takeGlobalCursor is taken',
    FChart.DispatchAction('{"type":"takeGlobalCursor","key":"dataZoomSelect","dataZoomSelectActive":true}'));
  RenderNow;
  AssertTrue('the zoom is on', FChart.ToolboxZoomActive);
  AssertEquals('the zoom button shows it', 'emphasis', FChart.ToolboxIconStatus(0, 'dataZoom', 'zoom'));
  { another key takes the cursor from it }
  FChart.DispatchAction('{"type":"takeGlobalCursor","key":"brush"}');
  RenderNow;
  AssertFalse('the zoom is off', FChart.ToolboxZoomActive);
  { magicType by its icon, then restore by the API }
  FChart.Events.Clear;
  AssertTrue(FChart.ToolboxClick(0, 'magicType', 'bar'));
  RenderNow;
  AssertTrue('the series is a bar now', Pos('"type":"bar"', FChart.GetOptionJson) > 0);
  { the action's event, then the brushselected its update dispatches -- an
    empty batch with no brush component [Batch 127] }
  AssertEquals('two events', 2, FChart.Events.Count);
  AssertEquals('magictypechanged', 'magictypechanged', Copy(FChart.Events[0], 1, Pos(#9, FChart.Events[0]) - 1));
  AssertEquals('brushselected', 'brushselected'#9'{"type":"brushselected","batch":[]}', FChart.Events[1]);
  AssertTrue(FChart.DispatchAction('{"type":"restore"}'));
  RenderNow;
  AssertTrue('a line again', Pos('"type":"line"', FChart.GetOptionJson) > 0);
  AssertEquals('the bar icon''s status went with the option', '', FChart.ToolboxIconStatus(0, 'magicType', 'bar'));
end;

procedure TAdvChartToolboxTest.TestTheToolboxIsDrawnAndExcludedFromTheExport;
var
  bmp, ex, nx: TBGRABitmap;
  lay: TTyToolboxLayout;
  inkedOn, inkedEx, inkedNx: Integer;

  function InkIn(B: TBGRABitmap): Integer;
  var xx, yy: Integer; q: TBGRAPixel;
  begin
    Result := 0;
    for yy := Trunc(lay.GroupY + lay.Union.Y) to Ceil(lay.GroupY + lay.Union.Y + lay.Union.H) do
      for xx := Trunc(lay.GroupX + lay.Union.X) to Ceil(lay.GroupX + lay.Union.X + lay.Union.W) do
      begin
        if (xx < 0) or (yy < 0) or (xx >= B.Width) or (yy >= B.Height) then Continue;
        q := B.GetPixel(xx, yy);
        if (q.red < 200) or (q.green < 200) or (q.blue < 200) then Inc(Result);
      end;
  end;

begin
  Show('{"animation":false,"backgroundColor":"#ffffff","xAxis":{"type":"category","data":["a","b"]},"yAxis":{"show":false},'
    + '"series":[{"type":"bar","data":[1,2]}],"toolbox":{"top":300,"left":20,"feature":{"restore":{},"dataView":{}}}}');
  lay := FChart.ToolboxLayout(0);
  AssertTrue('laid out', lay.Valid);
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
    inkedOn := InkIn(bmp);
    AssertTrue('the icons are drawn', inkedOn > 20);
  finally
    bmp.Free;
  end;
  ex := FChart.RenderToBitmap('{"excludeComponents":["toolbox"],"backgroundColor":"#ffffff"}');
  nx := FChart.RenderToBitmap('{"backgroundColor":"#ffffff"}');
  try
    inkedEx := InkIn(ex);
    inkedNx := InkIn(nx);
    AssertTrue('the export draws them', inkedNx > 20);
    AssertEquals('excluded, it does not', 0, inkedEx);
  finally
    ex.Free;
    nx.Free;
  end;
end;

procedure TAdvChartToolboxTest.TestAnUnregisteredHandlerDoesNothing;
begin
  Show('{"animation":false,"xAxis":{"type":"category","data":["a"]},"yAxis":{},"series":[{"type":"bar","data":[1]}],'
    + '"toolbox":{"feature":{"myOwn":{"title":"Mine","icon":"path://M0,0L10,10","onclick":"@NobodyRegistered"},'
    + '"myBare":{"title":"Bare","icon":"M0,0L10,10"}}}}');
  AssertEquals('two icons', 2, Length(FChart.ToolboxSpec(0).Icons));
  AssertTrue(FChart.ToolboxClick(0, 'myOwn', 'myOwn'));
  AssertTrue(FChart.ToolboxClick(0, 'myBare', 'myBare'));
  AssertEquals('nothing ran', 0, FChart.Clicks.Count);
  TyChartRegisterToolboxHandler('NobodyRegistered', @FChart.HitToolA);
  FChart.ToolboxClick(0, 'myOwn', 'myOwn');
  AssertEquals('now it runs', 'ToolA|myOwn|myOwn', FChart.Clicks.Text.Trim);
end;

procedure TAdvChartToolboxTest.TestTheTitlesAreTheResourceStrings;
var spec: TTyToolboxSpec;
begin
  Show('{"animation":false,"xAxis":{"type":"category","data":["a"]},"yAxis":{},"series":[{"type":"bar","data":[1]}],'
    + '"toolbox":{"feature":{"saveAsImage":{},"restore":{},"dataView":{},"dataZoom":{},'
    + '"magicType":{"type":["line","bar","stack"]}}}}');
  spec := FChart.ToolboxSpec(0);
  AssertEquals(8, Length(spec.Icons));
  AssertEquals('Save as Image', spec.Icons[0].Title);
  AssertEquals('Restore', spec.Icons[1].Title);
  AssertEquals('Data View', spec.Icons[2].Title);
  AssertEquals('Zoom', spec.Icons[3].Title);
  AssertEquals('Zoom Reset', spec.Icons[4].Title);
  AssertEquals('Switch to Line Chart', spec.Icons[5].Title);
  AssertEquals('Switch to Bar Chart', spec.Icons[6].Title);
  AssertEquals('Stack', spec.Icons[7].Title);
end;

initialization
  RegisterTest(TAdvChartToolboxOracleTest);
  RegisterTest(TAdvChartToolboxTest);
end.
