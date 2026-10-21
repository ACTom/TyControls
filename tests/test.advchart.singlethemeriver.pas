unit test.advchart.singlethemeriver;
{$mode objfpc}{$H+}
{ THE SINGLE AXIS AND THE THEMERIVER, HELD TO UPSTREAM [Batch 118, C10].

  tools/advchart-oracle/single-themeriver.js runs the real ECharts 6.1 build
  in node (server-side, animation off, zrender's width table for text,
  TZ=UTC, Math.random the port's xorshift32) and records, chart by chart:

    the singles  each one's rect, orient and position, its axis' extent,
                 inverse flag, type and scale, and every element its view
                 draws -- the line, the arrows, the ticks and minor ticks
                 (with the ticks a hidden label took), the labels (text,
                 place, turn, alignment, hidden), the name, the split lines
                 with their colours and the split areas;
    scatter      every symbol: drawn or not, its layout and its place, its
                 size, its label;
    themeRiver   the gap the layout left, the group's y, every row's data
                 and layout (x, y0, y), every layer's rows, its polygon's
                 bottoms and tops, its ECData index, its rect and its label;
    the legend   the layers after each legend action;
    states       after each action, every element's state list, fill and
                 opacity;
    the pointer  at each probe, every single axis whose pointer shows -- its
                 value, its line or rect, its label -- and the rows the
                 tooltip's axis trigger lists;
    dataZoom     a slider's place and the rows each series keeps;
    conversions  convertToPixel / convertFromPixel / containPixel with
                 single-axis finders.

  This replays it through the control, bit for bit. Text is measured with
  zrender's width table. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StrConsts,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Scale,
     tyControls.AdvanceChart.Coord, tyControls.AdvanceChart.Layout,
     tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Convert,
     tyControls.AdvanceChart.Labels, tyControls.AdvanceChart.States,
     tyControls.AdvanceChart.DataZoomView, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Single, tyControls.AdvanceChart.ThemeRiver,
     tyControls.AdvanceChart, test.advchart.gridbounds,
     test.advchart.categoryminmax;
type
  TSingleRiverProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Pointers(AX, AY: Integer): TTyAxisHitArray;
    function PointerOf(const AHit: TTyAxisHit): Double;
    function Draw(const AHit: TTyAxisHit; AW, AH: Integer;
      out D: TTySinglePointerDraw): Boolean;
    function States(ASeries, ARow: Integer; out AItem: TTyStItem): Boolean;
    function River(ASeriesIndex: Integer): TTyThemeRiverLayout;
    function StoreOf(ASeriesIndex: Integer): TTyDataStore;
    procedure PointerTo(AX, AY: Integer);
  end;

  TAdvChartSingleRiverTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TSingleRiverProbe;
    FRoot, FTable: TJSONData;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure RenderCase(ACase: TJSONObject);
    procedure RenderOption(const AOption: string; AW, AH: Integer);
    function Cases: TJSONArray;
    function CaseById(const AId: string): TJSONObject;
    procedure Finish(const AWhat: string; AMin: Integer);
    function FindEl(ARole: TTyChartAnimRole; ASeries, AIndex: Integer;
      out AEl: TTyChartElement): Integer;
    function FindLabel(AHostIndex: Integer; out AEl: TTyChartElement): Boolean;
    procedure CheckLine(const AWhat: string; const L: TTySingleLine; ARec: TJSONObject);
    procedure CheckSingle(S: TTySingle; ARec: TJSONObject);
    procedure CheckView(S: TTySingle; ARec: TJSONObject);
    procedure CheckScatter(ASeries: TJSONObject);
    procedure CheckRiver(ASeries: TJSONObject);
    procedure CheckSeriesList(ASeries: TJSONArray);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSinglesAreUpstreams;
    procedure TestTheSingleAxisViewsAreUpstreams;
    procedure TestScatterOnASingleAxisIsUpstreams;
    procedure TestTheRiversAreUpstreams;
    procedure TestTheLegendFiltersTheLayers;
    procedure TestTheStatesAreUpstreams;
    procedure TestThePointerOnASingleAxisIsUpstreams;
    procedure TestDataZoomOnASingleAxisIsUpstreams;
    procedure TestSingleAxisFindersConvertAsUpstream;
    { beyond the fixture }
    procedure TestFixDataWalksKeysAsJavaScriptDoes;
    procedure TestTheLayersSortAsV8Does;
    procedure TestALayerIsDrawnAndHit;
    procedure TestASeriesOnAMissingSingleSaysSo;
  end;

implementation

{ ==================== the probe ==================== }

function TSingleRiverProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TSingleRiverProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TSingleRiverProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TSingleRiverProbe.Pointers(AX, AY: Integer): TTyAxisHitArray;
begin
  Result := ResolveAxisPointers(AX, AY);
end;

function TSingleRiverProbe.PointerOf(const AHit: TTyAxisHit): Double;
begin
  Result := PointerValue(AHit);
end;

function TSingleRiverProbe.Draw(const AHit: TTyAxisHit; AW, AH: Integer;
  out D: TTySinglePointerDraw): Boolean;
begin
  Result := SinglePointerGeometry(AHit, Rect(0, 0, AW, AH), NewTextMeasurer(96), 96, D);
end;

function TSingleRiverProbe.States(ASeries, ARow: Integer; out AItem: TTyStItem): Boolean;
begin
  Result := ItemStates(ASeries, ARow, AItem);
end;

function TSingleRiverProbe.River(ASeriesIndex: Integer): TTyThemeRiverLayout;
begin
  Result := RiverLayoutOf(ASeriesIndex);
end;

function TSingleRiverProbe.StoreOf(ASeriesIndex: Integer): TTyDataStore;
begin
  Result := SeriesStore(ASeriesIndex);
end;

procedure TSingleRiverProbe.PointerTo(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

{ ==================== helpers ==================== }

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Txt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B));
end;

function AlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahLeft: Result := 'left';
    tahRight: Result := 'right';
  else
    Result := 'center';
  end;
end;

function VAlignName(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavTop: Result := 'top';
    tavBottom: Result := 'bottom';
  else
    Result := 'middle';
  end;
end;

function StrOrNull(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := '' else Result := AData.AsString;
end;

function KindName(AKind: TTyConvertKind): string;
begin
  case AKind of
    cvkNumber: Result := 'num';
    cvkArray: Result := 'arr';
    cvkError: Result := 'throw';
  else
    Result := 'none';
  end;
end;

{ the oracle's input: every number written as an object whose one key is
  "h", its hex }
function Decode(AData: TJSONData): TJSONData;
var
  o: TJSONObject;
  i: Integer;
begin
  case AData.JSONType of
    jtArray:
      begin
        Result := TJSONArray.Create;
        for i := 0 to AData.Count - 1 do
          TJSONArray(Result).Add(Decode(AData.Items[i]));
      end;
    jtObject:
      begin
        o := TJSONObject(AData);
        if (o.Count = 1) and (o.Names[0] = 'h') and (o.Items[0].JSONType = jtString) then
          Exit(TJSONFloatNumber.Create(FromHex(o.Items[0].AsString)));
        Result := TJSONObject.Create;
        for i := 0 to o.Count - 1 do
          TJSONObject(Result).Add(o.Names[i], Decode(o.Items[i]));
      end;
  else
    Result := AData.Clone;
  end;
end;

{ ==================== the case ==================== }

procedure TAdvChartSingleRiverTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-single-themeriver.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-single-themeriver.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-grid-bounds.json'));
    FTable := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartSingleRiverTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FTable);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartSingleRiverTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartSingleRiverTest.Same(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  if (AWant = nil) or (AWant.JSONType = jtNull) then
  begin
    Bad(AWhat + ': upstream has no number');
    Exit;
  end;
  want := FromHex(AWant.AsString);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartSingleRiverTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartSingleRiverTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True), BoolToStr(AWant, True)]));
end;

procedure TAdvChartSingleRiverTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %d, upstream %d', [AWhat, AGot, AWant]));
end;

procedure TAdvChartSingleRiverTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
end;

function TAdvChartSingleRiverTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function TAdvChartSingleRiverTest.CaseById(const AId: string): TJSONObject;
var i: Integer;
begin
  for i := 0 to Cases.Count - 1 do
    if Cases.Objects[i].Strings['id'] = AId then Exit(Cases.Objects[i]);
  Result := nil;
  Fail('no case ' + AId);
end;

procedure TAdvChartSingleRiverTest.RenderOption(const AOption: string; AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TSingleRiverProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, AW, AH);
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartSingleRiverTest.RenderCase(ACase: TJSONObject);
var
  bt: string;
  k: Integer;
begin
  try
    RenderOption(ACase.Objects['option'].AsJSON, ACase.Integers['W'], ACase.Integers['H']);
  except
    on E: Exception do
    begin
      bt := BackTraceStrFunc(ExceptAddr);
      for k := 0 to ExceptFrameCount - 1 do
        bt := bt + ' | ' + BackTraceStrFunc(ExceptFrames[k]);
      raise Exception.CreateFmt('%s: %s %s', [ACase.Strings['id'], E.Message, bt]);
    end;
  end;
end;

function TAdvChartSingleRiverTest.FindEl(ARole: TTyChartAnimRole; ASeries,
  AIndex: Integer; out AEl: TTyChartElement): Integer;
var
  i: Integer;
  l: TTyPaintList;
begin
  AEl := Default(TTyChartElement);
  Result := -1;
  l := FChart.List;
  if l = nil then Exit;
  for i := 0 to l.Count - 1 do
    if (l.Element(i).Anim.Role = ARole) and (l.Element(i).Anim.Series = ASeries)
      and (l.Element(i).Anim.Index = AIndex) then
    begin
      AEl := l.Element(i);
      Exit(i);
    end;
end;

function TAdvChartSingleRiverTest.FindLabel(AHostIndex: Integer;
  out AEl: TTyChartElement): Boolean;
var
  i: Integer;
  l: TTyPaintList;
begin
  AEl := Default(TTyChartElement);
  Result := False;
  l := FChart.List;
  for i := 0 to l.Count - 1 do
    if (l.Element(i).Anim.Role = carLabel)
      and (l.Element(i).Caption.LmHostPlus1 = AHostIndex + 1) then
    begin
      AEl := l.Element(i);
      Exit(True);
    end;
end;

procedure TAdvChartSingleRiverTest.CheckLine(const AWhat: string;
  const L: TTySingleLine; ARec: TJSONObject);
begin
  Same(AWhat + ' x1', L.X1, ARec.Find('x1'));
  Same(AWhat + ' y1', L.Y1, ARec.Find('y1'));
  Same(AWhat + ' x2', L.X2, ARec.Find('x2'));
  Same(AWhat + ' y2', L.Y2, ARec.Find('y2'));
end;

{ ==================== the singles ==================== }

procedure TAdvChartSingleRiverTest.CheckSingle(S: TTySingle; ARec: TJSONObject);
var a, b: Double;
begin
  Same('rect x', S.Rect.X, ARec.Arrays['rect'].Items[0]);
  Same('rect y', S.Rect.Y, ARec.Arrays['rect'].Items[1]);
  Same('rect w', S.Rect.W, ARec.Arrays['rect'].Items[2]);
  Same('rect h', S.Rect.H, ARec.Arrays['rect'].Items[3]);
  SameStr('orient', S.Orient, ARec.Strings['orient']);
  SameStr('position', S.Position, ARec.Strings['position']);
  SameBool('horizontal', S.Horizontal, ARec.Booleans['horizontal']);
  SameBool('inverse', S.InverseFlag, ARec.Booleans['inverse']);
  S.Axis.LocalExtent(a, b);
  Same('extent 0', a, ARec.Arrays['extent'].Items[0]);
  Same('extent 1', b, ARec.Arrays['extent'].Items[1]);
  SameBool('blank', S.Axis.Scale.Blank, ARec.Booleans['blank']);
  if not ARec.Booleans['blank'] then
  begin
    Same('scale 0', S.Axis.Scale.GetExtent.Start, ARec.Arrays['scale'].Items[0]);
    Same('scale 1', S.Axis.Scale.GetExtent.Stop, ARec.Arrays['scale'].Items[1]);
  end;
end;

procedure TAdvChartSingleRiverTest.TestTheSinglesAreUpstreams;
var
  c, i, n: Integer;
  cs, rec: TJSONObject;
  s: TTySingle;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    RenderCase(cs);
    for i := 0 to cs.Arrays['singles'].Count - 1 do
    begin
      rec := cs.Arrays['singles'].Objects[i];
      FWhere := cs.Strings['id'] + ' single' + IntToStr(rec.Integers['index']);
      s := FChart.SingleLayout(rec.Integers['index']);
      if s = nil then
      begin
        Bad('no single');
        Continue;
      end;
      Inc(n);
      CheckSingle(s, rec);
    end;
    SameInt(cs.Strings['id'] + ' singles', FChart.SingleCount, cs.Arrays['singles'].Count);
  end;
  AssertTrue(Format('enough singles (%d)', [n]), n >= 60);
  Finish('the singles', 700);
end;

procedure TAdvChartSingleRiverTest.CheckView(S: TTySingle; ARec: TJSONObject);
var
  v: TTySingleAxisView;
  arr: TJSONArray;
  o: TJSONObject;
  i, k, built: Integer;
  what: string;
begin
  v := S.View;
  SameBool('shown', v.Shown, ARec.Booleans['shown']);
  if not ARec.Booleans['shown'] then Exit;
  Inc(FCompared);
  if (ARec.Find('line').JSONType = jtNull) <> not v.HasLine then
    Bad('line drawn ' + BoolToStr(v.HasLine, True))
  else if v.HasLine then
    CheckLine('line', v.Line, ARec.Objects['line']);
  arr := ARec.Arrays['arrows'];
  Inc(FCompared);
  if Length(v.Spec.Arrows) <> arr.Count then
    Bad(Format('%d arrows, upstream %d', [Length(v.Spec.Arrows), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      SameStr('arrow type', v.Spec.Arrows[i].SymbolType, o.Strings['type']);
      Same('arrow x', v.Spec.Arrows[i].X, o.Find('x'));
      Same('arrow y', v.Spec.Arrows[i].Y, o.Find('y'));
      Same('arrow rotation', v.Spec.Arrows[i].Rotation, o.Find('rotation'));
      Same('arrow w', v.Spec.Arrows[i].W, o.Find('w'));
      Same('arrow h', v.Spec.Arrows[i].H, o.Find('h'));
    end;
  arr := ARec.Arrays['ticks'];
  Inc(FCompared);
  if Length(v.Ticks) <> arr.Count then
    Bad(Format('%d ticks, upstream %d', [Length(v.Ticks), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      what := 'tick ' + o.Strings['tick'];
      SameStr(what + ' value', TyJsNumberToString(v.Ticks[i].Value), o.Strings['tick']);
      CheckLine(what, v.Ticks[i], o);
      SameBool(what + ' hidden', not v.Ticks[i].Drawn, o.Booleans['ignore']);
    end;
  arr := ARec.Arrays['minorTicks'];
  Inc(FCompared);
  if Length(v.MinorTicks) <> arr.Count then
    Bad(Format('%d minor ticks, upstream %d', [Length(v.MinorTicks), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
      CheckLine('minor tick ' + IntToStr(i), v.MinorTicks[i], arr.Objects[i]);
  arr := ARec.Arrays['labels'];
  built := 0;
  for k := 0 to High(v.Spec.Placements) do
    if v.Spec.Placements[k].Built then Inc(built);
  Inc(FCompared);
  if built <> arr.Count then
    Bad(Format('%d labels built, upstream %d', [built, arr.Count]))
  else
  begin
    i := 0;
    for k := 0 to High(v.Spec.Placements) do
    begin
      if not v.Spec.Placements[k].Built then Continue;
      o := arr.Objects[i];
      what := 'label ' + o.Strings['tick'];
      SameStr(what + ' value', TyJsNumberToString(v.Spec.TickValues[k]), o.Strings['tick']);
      SameStr(what + ' text', v.Spec.Placements[k].Text, o.Strings['text']);
      Same(what + ' x', v.Spec.Placements[k].X, o.Find('x'));
      Same(what + ' y', v.Spec.Placements[k].Y, o.Find('y'));
      Same(what + ' rotation', v.Spec.Placements[k].DecRotation, o.Find('rotation'));
      SameStr(what + ' align', AlignName(v.Spec.Placements[k].AnchorH), o.Strings['align']);
      SameStr(what + ' vertical align', VAlignName(v.Spec.Placements[k].AnchorV), o.Strings['va']);
      SameBool(what + ' hidden', not v.Spec.Placements[k].Shown, o.Booleans['ignore']);
      Inc(i);
    end;
  end;
  Inc(FCompared);
  if ARec.Find('name').JSONType = jtNull then
  begin
    if v.Spec.NamePlacement.Shown then Bad('a name upstream does not draw');
  end
  else if not v.Spec.NamePlacement.Shown then
    Bad('no name')
  else
  begin
    o := ARec.Objects['name'];
    SameStr('name text', v.Spec.NamePlacement.Text, o.Strings['text']);
    Same('name x', v.Spec.NamePlacement.X, o.Find('x'));
    Same('name y', v.Spec.NamePlacement.Y, o.Find('y'));
    Same('name rotation', v.Spec.NamePlacement.RotationRad, o.Find('rotation'));
    SameStr('name align', AlignName(v.Spec.NamePlacement.AnchorH), o.Strings['align']);
    SameStr('name vertical align', VAlignName(v.Spec.NamePlacement.AnchorV), o.Strings['va']);
  end;
  arr := ARec.Arrays['splitLines'];
  Inc(FCompared);
  if Length(v.SplitLines) <> arr.Count then
    Bad(Format('%d split lines, upstream %d', [Length(v.SplitLines), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      what := 'split line ' + IntToStr(i);
      CheckLine(what, v.SplitLines[i], o);
      SameInt(what + ' colour', v.SplitLines[i].ColourIndex, o.Integers['ci']);
    end;
  arr := ARec.Arrays['splitAreas'];
  Inc(FCompared);
  if Length(v.SplitAreas) <> arr.Count then
    Bad(Format('%d split areas, upstream %d', [Length(v.SplitAreas), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      what := 'split area ' + IntToStr(i);
      Same(what + ' x', v.SplitAreas[i].X, o.Find('x'));
      Same(what + ' y', v.SplitAreas[i].Y, o.Find('y'));
      Same(what + ' w', v.SplitAreas[i].W, o.Find('w'));
      Same(what + ' h', v.SplitAreas[i].H, o.Find('h'));
      if o.Integers['ci'] >= 0 then
        SameInt(what + ' colour', v.SplitAreas[i].ColourIndex, o.Integers['ci']);
    end;
end;

procedure TAdvChartSingleRiverTest.TestTheSingleAxisViewsAreUpstreams;
var
  c, i, n: Integer;
  cs, rec: TJSONObject;
  s: TTySingle;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    RenderCase(cs);
    for i := 0 to cs.Arrays['singles'].Count - 1 do
    begin
      rec := cs.Arrays['singles'].Objects[i];
      FWhere := cs.Strings['id'] + ' single' + IntToStr(rec.Integers['index']);
      s := FChart.SingleLayout(rec.Integers['index']);
      if s = nil then
      begin
        Bad('no single');
        Continue;
      end;
      Inc(n);
      CheckView(s, rec.Objects['view']);
    end;
  end;
  AssertTrue(Format('enough axis views (%d)', [n]), n >= 60);
  Finish('the axis views', 8000);
end;

{ ==================== scatter ==================== }

procedure TAdvChartSingleRiverTest.CheckScatter(ASeries: TJSONObject);
var
  si, i, at: Integer;
  sym, cap: TTyChartElement;
  so, lo: TJSONObject;
  what: string;
  role: TTyChartAnimRole;
  have: Boolean;
begin
  si := ASeries.Integers['index'];
  if ASeries.Strings['type'] = 'effectScatter' then role := carEffectSymbol
  else role := carSymbol;
  SameInt(Format('s%d rows', [si]), FChart.StoreOf(si).Count, ASeries.Integers['count']);
  for i := 0 to ASeries.Arrays['symbols'].Count - 1 do
  begin
    so := ASeries.Arrays['symbols'].Objects[i];
    what := Format('s%d symbol %d', [si, i]);
    at := FindEl(role, si, i, sym);
    SameBool(what + ' drawn', at >= 0, so.Booleans['drawn']);
    if (at < 0) or not so.Booleans['drawn'] then Continue;
    Same(what + ' x', sym.Anim.G[5], so.Find('x'));
    Same(what + ' y', sym.Anim.G[6], so.Find('y'));
    { the size: the symbol's half extent, twice }
    if so.Find('size').JSONType = jtString then
      Same(what + ' size', sym.Anim.G[2] * 2, so.Find('size'));
    lo := nil;
    if (so.Find('label') <> nil) and (so.Find('label').JSONType = jtObject) then
      lo := so.Objects['label'];
    if lo = nil then Continue;
    have := FindLabel(at, cap) and not cap.Ignore;
    SameBool(what + ' label drawn', have, lo.Booleans['drawn']);
    if not (have and lo.Booleans['drawn']) then Continue;
    SameStr(what + ' label text', cap.Caption.Text, lo.Strings['text']);
    Same(what + ' label x', cap.Caption.LmBaseX + cap.Caption.LmOffX, lo.Find('x'));
    Same(what + ' label y', cap.Caption.LmBaseY + cap.Caption.LmOffY, lo.Find('y'));
  end;
end;

procedure TAdvChartSingleRiverTest.CheckSeriesList(ASeries: TJSONArray);
var
  k: Integer;
  sr: TJSONObject;
begin
  for k := 0 to ASeries.Count - 1 do
  begin
    sr := ASeries.Objects[k];
    if (sr.Strings['type'] = 'scatter') or (sr.Strings['type'] = 'effectScatter') then
      CheckScatter(sr)
    else if sr.Strings['type'] = 'themeRiver' then
      CheckRiver(sr);
  end;
end;

procedure TAdvChartSingleRiverTest.TestScatterOnASingleAxisIsUpstreams;
var
  c, k, n: Integer;
  cs, sr: TJSONObject;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    RenderCase(cs);
    for k := 0 to cs.Arrays['series'].Count - 1 do
    begin
      sr := cs.Arrays['series'].Objects[k];
      if (sr.Strings['type'] <> 'scatter') and (sr.Strings['type'] <> 'effectScatter') then
        Continue;
      FWhere := cs.Strings['id'];
      Inc(n);
      CheckScatter(sr);
    end;
  end;
  AssertTrue(Format('enough scatter series (%d)', [n]), n >= 20);
  Finish('the scatter', 900);
end;

{ ==================== the rivers ==================== }

procedure TAdvChartSingleRiverTest.CheckRiver(ASeries: TJSONObject);
var
  si, i, j, k, at, raw: Integer;
  L: TTyThemeRiverLayout;
  st: TTyDataStore;
  rows, layers, idx, pts: TJSONArray;
  ro, lo, lab: TJSONObject;
  el, cap: TTyChartElement;
  what: string;
  have: Boolean;
  want: TTyChartColor;
begin
  si := ASeries.Integers['index'];
  L := FChart.River(si);
  st := FChart.StoreOf(si);
  SameBool(Format('s%d laid out', [si]), L.Valid, True);
  if (not L.Valid) or (st = nil) then Exit;
  SameInt(Format('s%d rows', [si]), st.Count, ASeries.Integers['count']);
  if st.Count <> ASeries.Integers['count'] then Exit;
  for i := 0 to st.Count - 1 do
    SameInt(Format('s%d row %d raw', [si, i]), st.GetRawIndex(i),
      ASeries.Arrays['raw'].Integers[i]);
  Same(Format('s%d gap 0', [si]), L.Gap[0], ASeries.Arrays['gap'].Items[0]);
  Same(Format('s%d gap 1', [si]), L.Gap[1], ASeries.Arrays['gap'].Items[1]);
  Same(Format('s%d group y', [si]), L.GroupY, ASeries.Find('groupY'));
  rows := ASeries.Arrays['rows'];
  for i := 0 to rows.Count - 1 do
  begin
    ro := rows.Objects[i];
    what := Format('s%d row %d', [si, i]);
    SameStr(what + ' name', st.GetNameByRaw(st.GetRawIndex(i)), ro.Strings['name']);
    Same(what + ' time', st.Get(0, i), ro.Find('time'));
    Same(what + ' value', st.Get(1, i), ro.Find('value'));
    if ro.Find('x').JSONType = jtNull then Continue;
    Same(what + ' x', L.Rows[i].X, ro.Find('x'));
    Same(what + ' y0', L.Rows[i].Y0, ro.Find('y0'));
    Same(what + ' y', L.Rows[i].Y, ro.Find('y'));
  end;
  layers := ASeries.Arrays['layers'];
  SameInt(Format('s%d layers', [si]), Length(L.Layers), layers.Count);
  if Length(L.Layers) <> layers.Count then Exit;
  for k := 0 to layers.Count - 1 do
  begin
    lo := layers.Objects[k];
    what := Format('s%d layer %d', [si, k]);
    SameStr(what + ' name', L.Layers[k].Name, lo.Strings['name']);
    idx := lo.Arrays['indices'];
    SameInt(what + ' rows', Length(L.Layers[k].Rows), idx.Count);
    if Length(L.Layers[k].Rows) <> idx.Count then Continue;
    for j := 0 to idx.Count - 1 do
      SameInt(what + ' row ' + IntToStr(j), L.Layers[k].Rows[j], idx.Integers[j]);
    { the polygon's points, in the group's frame }
    pts := lo.Arrays['points'];
    SameInt(what + ' points', Length(L.Polygons[k].Bottoms) * 2, pts.Count);
    if Length(L.Polygons[k].Bottoms) * 2 = pts.Count then
      for j := 0 to High(L.Polygons[k].Bottoms) do
      begin
        Same(what + ' bottom x' + IntToStr(j), L.Polygons[k].Bottoms[j].X, pts.Items[j * 2]);
        Same(what + ' bottom y' + IntToStr(j), L.Polygons[k].Bottoms[j].Y, pts.Items[j * 2 + 1]);
      end;
    pts := lo.Arrays['stacked'];
    if Length(L.Polygons[k].Tops) * 2 = pts.Count then
      for j := 0 to High(L.Polygons[k].Tops) do
      begin
        Same(what + ' top x' + IntToStr(j), L.Polygons[k].Tops[j].X, pts.Items[j * 2]);
        Same(what + ' top y' + IntToStr(j), L.Polygons[k].Tops[j].Y, pts.Items[j * 2 + 1]);
      end;
    { the path's own rect, which the enter clip is made from }
    begin
      Same(what + ' rect x', L.Polygons[k].Box.X, lo.Arrays['rect'].Items[0]);
      Same(what + ' rect y', L.Polygons[k].Box.Y, lo.Arrays['rect'].Items[1]);
      Same(what + ' rect w', L.Polygons[k].Box.W, lo.Arrays['rect'].Items[2]);
      Same(what + ' rect h', L.Polygons[k].Box.H, lo.Arrays['rect'].Items[3]);
    end;
    { the element: the layer's ECData index, its fill -- none where no
      point is legal (upstream's path draws nothing there either) }
    at := FindEl(carRiver, si, k, el);
    Inc(FCompared);
    if not TyRiverPathDraws(L.Polygons[k].Cmds) then
    begin
      if at >= 0 then Bad(what + ': a polygon of no legal point');
      Continue;
    end;
    if at < 0 then
    begin
      Bad(what + ': no polygon');
      Continue;
    end;
    SameInt(what + ' data index', el.Datum.DataIndex, lo.Integers['dataIndex']);
    if (lo.Find('fill').JSONType = jtString)
      and TyTryParseChartColor(lo.Strings['fill'], want) then
    begin
      Inc(FCompared);
      if (not el.Style.HasFill) or (el.Style.FillColor <> want) then
        Bad(Format('%s fill %s, upstream %s', [what, IntToHex(el.Style.FillColor, 8),
          lo.Strings['fill']]));
    end;
    if lo.Find('opacity').JSONType = jtString then
      Same(what + ' opacity', el.Style.Alpha, lo.Find('opacity'));
    { the label }
    lab := nil;
    if (lo.Find('label') <> nil) and (lo.Find('label').JSONType = jtObject) then
      lab := lo.Objects['label'];
    if lab = nil then Continue;
    have := FindLabel(at, cap) and not cap.Ignore;
    { a label at no number upstream is no label here }
    if lab.Booleans['drawn'] and IsNan(FromHex(lab.Strings['x'])) then
    begin
      SameBool(what + ' label at no place', have, False);
      Same(what + ' label x', L.Polygons[k].LabelX, lab.Find('x'));
      Continue;
    end;
    SameBool(what + ' label drawn', have, lab.Booleans['drawn']);
    if not (have and lab.Booleans['drawn']) then Continue;
    SameStr(what + ' label text', cap.Caption.Text, lab.Strings['text']);
    { in the group's frame upstream (textConfig.local), the group's y added
      here }
    Same(what + ' label x', L.Polygons[k].LabelX, lab.Find('x'));
    Same(what + ' label y', L.Polygons[k].LabelY, lab.Find('y'));
    Inc(FCompared);
    if not SameBits(cap.Caption.LmBaseY, L.Polygons[k].LabelY + L.GroupY)
      or not SameBits(cap.Caption.LmBaseX, L.Polygons[k].LabelX) then
      Bad(what + ': the caption is not at the label''s place');
    if StrOrNull(lab.Find('align')) = '' then
      SameStr(what + ' label align', AlignName(cap.Caption.LmStyleAH), 'left')
    else
      SameStr(what + ' label align', AlignName(cap.Caption.LmStyleAH), lab.Strings['align']);
    SameStr(what + ' label vertical align', VAlignName(cap.Caption.LmStyleAV), lab.Strings['va']);
    SameBool(what + ' label inside', cap.Caption.LmInkInside, False);
  end;
  { the store's raw rows, each its own raw index }
  raw := 0;
  if raw > 0 then ;
end;

procedure TAdvChartSingleRiverTest.TestTheRiversAreUpstreams;
var
  c, k, n: Integer;
  cs, sr: TJSONObject;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    RenderCase(cs);
    for k := 0 to cs.Arrays['series'].Count - 1 do
    begin
      sr := cs.Arrays['series'].Objects[k];
      if sr.Strings['type'] <> 'themeRiver' then Continue;
      FWhere := cs.Strings['id'];
      Inc(n);
      CheckRiver(sr);
    end;
  end;
  AssertTrue(Format('enough rivers (%d)', [n]), n >= 20);
  Finish('the rivers', 3000);
end;

{ ==================== the legend ==================== }

procedure TAdvChartSingleRiverTest.TestTheLegendFiltersTheLayers;
var
  c, a, n: Integer;
  cs, af: TJSONObject;
  bmp: TBGRABitmap;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'action' then Continue;
    RenderCase(cs);
    for a := 0 to cs.Arrays['after'].Count - 1 do
    begin
      af := cs.Arrays['after'].Objects[a];
      FWhere := cs.Strings['id'] + ' ' + af.Objects['action'].AsJSON;
      AssertTrue(FWhere + ' dispatched', FChart.DispatchAction(af.Objects['action'].AsJSON));
      bmp := TBGRABitmap.Create(cs.Integers['W'], cs.Integers['H'], BGRA(255, 255, 255, 255));
      try
        FChart.Render(bmp.Canvas, Rect(0, 0, cs.Integers['W'], cs.Integers['H']), 96);
      finally
        bmp.Free;
      end;
      Inc(n);
      CheckSeriesList(af.Arrays['series']);
    end;
  end;
  AssertTrue(Format('enough actions (%d)', [n]), n >= 3);
  Finish('the legend', 300);
end;

{ ==================== the states ==================== }

function StatesText(A: TJSONArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to A.Count - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + A.Strings[i];
  end;
end;

procedure TAdvChartSingleRiverTest.TestTheStatesAreUpstreams;
var
  c, s, i, at, n, si: Integer;
  cs, st, it: TJSONObject;
  el: TTyChartElement;
  item: TTyStItem;
  bmp: TBGRABitmap;
  role: TTyChartAnimRole;
  isRiver: Boolean;
  want: TTyChartColor;
  cap: TTyChartElement;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'state' then Continue;
    RenderCase(cs);
    for s := 0 to cs.Arrays['states'].Count - 1 do
    begin
      st := cs.Arrays['states'].Objects[s];
      FWhere := cs.Strings['id'] + ' ' + st.Objects['action'].AsJSON;
      AssertTrue(FWhere + ' dispatched', FChart.DispatchAction(st.Objects['action'].AsJSON));
      bmp := TBGRABitmap.Create(cs.Integers['W'], cs.Integers['H'], BGRA(255, 255, 255, 255));
      try
        FChart.Render(bmp.Canvas, Rect(0, 0, cs.Integers['W'], cs.Integers['H']), 96);
      finally
        bmp.Free;
      end;
      for i := 0 to st.Arrays['items'].Count - 1 do
      begin
        it := st.Arrays['items'].Objects[i];
        si := it.Integers['s'];
        isRiver := cs.Objects['option'].Arrays['series'].Objects[si].Strings['type'] = 'themeRiver';
        if isRiver then role := carRiver else role := carSymbol;
        at := FindEl(role, si, it.Integers['i'], el);
        Inc(FCompared);
        if at < 0 then
        begin
          Bad(Format('s%d i%d: no element', [si, it.Integers['i']]));
          Continue;
        end;
        Inc(n);
        if FChart.States(si, it.Integers['i'], item) then
          SameStr(Format('s%d i%d states', [si, it.Integers['i']]),
            TyStNamesText(item.Host.States), StatesText(it.Arrays['states']))
        else
          Bad(Format('s%d i%d: no state record', [si, it.Integers['i']]));
        if (it.Find('fill') <> nil) and (it.Find('fill').JSONType = jtString)
          and TyTryParseChartColor(it.Strings['fill'], want) then
        begin
          Inc(FCompared);
          if (not el.Style.HasFill) or (el.Style.FillColor <> want) then
            Bad(Format('s%d i%d fill %s, upstream %s', [si, it.Integers['i'],
              IntToHex(el.Style.FillColor, 8), it.Strings['fill']]));
        end;
        if (it.Find('opacity') <> nil) and (it.Find('opacity').JSONType = jtString) then
          Same(Format('s%d i%d opacity', [si, it.Integers['i']]), el.Style.Alpha, it.Find('opacity'));
        { the label a state shows or hides }
        if (it.Find('labelShown') <> nil) and (it.Find('labelShown').JSONType = jtBoolean) then
          SameBool(Format('s%d i%d label shown', [si, it.Integers['i']]),
            FindLabel(at, cap) and not cap.Ignore, it.Booleans['labelShown']);
      end;
    end;
  end;
  AssertTrue(Format('enough elements (%d)', [n]), n >= 40);
  Finish('the states', 150);
end;

{ ==================== the pointer ==================== }

procedure TAdvChartSingleRiverTest.TestThePointerOnASingleAxisIsUpstreams;
var
  c, q, a, h, n, k, j, withSeries, singles, found: Integer;
  cs, pr, ax, el, tipAxis: TJSONObject;
  hits: TTyAxisHitArray;
  d: TTySinglePointerDraw;
  t: string;
  sh, tip, tipList, ser: TJSONArray;
  pts: array[0..3] of Double;
begin
  n := 0;
  withSeries := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'pointer' then Continue;
    RenderCase(cs);
    for q := 0 to cs.Arrays['pointer'].Count - 1 do
    begin
      pr := cs.Arrays['pointer'].Objects[q];
      FWhere := Format('%s @%d,%d', [cs.Strings['id'], pr.Integers['x'], pr.Integers['y']]);
      hits := FChart.Pointers(pr.Integers['x'], pr.Integers['y']);
      singles := 0;
      for h := 0 to High(hits) do
        if hits[h].Single <> nil then Inc(singles);
      SameInt('single pointers', singles, pr.Arrays['axes'].Count);
      for a := 0 to pr.Arrays['axes'].Count - 1 do
      begin
        ax := pr.Arrays['axes'].Objects[a];
        found := -1;
        for h := 0 to High(hits) do
          if (hits[h].Single <> nil) and (hits[h].Single.Index = ax.Integers['single']) then
            found := h;
        Inc(FCompared);
        if found < 0 then
        begin
          Bad('no pointer on single ' + IntToStr(ax.Integers['single']));
          Continue;
        end;
        Inc(n);
        Same('value', FChart.PointerOf(hits[found]), ax.Find('value'));
        FChart.Draw(hits[found], cs.Integers['W'], cs.Integers['H'], d);
        Inc(FCompared);
        if ax.Find('el').JSONType = jtNull then
        begin
          if d.Shape.Kind <> spkNone then Bad('a pointer upstream does not draw');
        end
        else
        begin
          el := ax.Objects['el'];
          t := el.Strings['type'];
          sh := el.Arrays['shape'];
          pts[0] := d.Shape.X1;
          pts[1] := d.Shape.Y1;
          pts[2] := d.Shape.X2;
          pts[3] := d.Shape.Y2;
          case d.Shape.Kind of
            spkLine: SameStr('pointer', 'line', t);
            spkRect: SameStr('pointer', 'rect', t);
          else
            Bad('no pointer element, upstream a ' + t);
          end;
          for h := 0 to 3 do Same('pointer ' + IntToStr(h), pts[h], sh.Items[h]);
        end;
        Inc(FCompared);
        if ax.Find('label').JSONType = jtNull then
        begin
          if d.HasLabel then Bad('a label upstream does not show');
        end
        else if not d.HasLabel then
          Bad('no label')
        else
        begin
          el := ax.Objects['label'];
          SameStr('label', d.Text, el.Strings['text']);
          Same('label x', d.X, el.Find('x'));
          Same('label y', d.Y, el.Find('y'));
          Same('label w', d.W, el.Find('w'));
          Same('label h', d.H, el.Find('h'));
        end;
      end;
      { THE TOOLTIP'S ROWS: every axis the showTip payload lists, the series
        rows on it, against the hit's }
      if (pr.Find('tip') = nil) or (pr.Find('tip').JSONType <> jtArray) then Continue;
      tip := pr.Arrays['tip'];
      for k := 0 to tip.Count - 1 do
      begin
        tipList := tip.Arrays[k];
        for j := 0 to tipList.Count - 1 do
        begin
          tipAxis := tipList.Objects[j];
          found := -1;
          for h := 0 to High(hits) do
            if (hits[h].Single <> nil) and not hits[h].Cross then found := h;
          ser := tipAxis.Arrays['series'];
          Inc(FCompared);
          if found < 0 then
          begin
            if ser.Count > 0 then Bad('no tooltip axis');
            Continue;
          end;
          if Length(hits[found].Slots) <> ser.Count then
          begin
            Bad(Format('%d tooltip rows, upstream %d', [Length(hits[found].Slots), ser.Count]));
            Continue;
          end;
          for h := 0 to ser.Count - 1 do
          begin
            Inc(FCompared);
            if (hits[found].Rows[h] <> ser.Objects[h].Integers['i'])
              or (hits[found].Slots[h] <> ser.Objects[h].Integers['s']) then
              Bad(Format('row %d: s%d i%d, upstream s%d i%d', [h, hits[found].Slots[h],
                hits[found].Rows[h], ser.Objects[h].Integers['s'], ser.Objects[h].Integers['i']]));
          end;
          if ser.Count > 0 then Inc(withSeries);
          Same('tooltip value', hits[found].SnapValue, tipAxis.Find('value'));
        end;
      end;
    end;
  end;
  AssertTrue(Format('enough pointers (%d)', [n]), n >= 40);
  AssertTrue(Format('enough rows (%d)', [withSeries]), withSeries >= 30);
  Finish('the pointer', 400);
end;

{ ==================== dataZoom ==================== }

procedure TAdvChartSingleRiverTest.TestDataZoomOnASingleAxisIsUpstreams;
var
  c, z, n, k: Integer;
  cs, zo, sr: TJSONObject;
  lay: TTyDzSliderLayout;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'zoom' then Continue;
    RenderCase(cs);
    FWhere := cs.Strings['id'];
    for z := 0 to cs.Arrays['zoom'].Count - 1 do
    begin
      zo := cs.Arrays['zoom'].Objects[z];
      lay := FChart.DataZoomSliderLayout(zo.Integers['index']);
      SameBool('slider laid out', lay.Valid, True);
      if not lay.Valid then Continue;
      Inc(n);
      Same('slider x', lay.LocX, zo.Find('x'));
      Same('slider y', lay.LocY, zo.Find('y'));
      Same('slider length', lay.L, zo.Find('w'));
      Same('slider thickness', lay.T, zo.Find('h'));
      SameBool('slider horizontal', lay.Horizontal, zo.Strings['orient'] = 'horizontal');
    end;
    for k := 0 to cs.Arrays['series'].Count - 1 do
    begin
      sr := cs.Arrays['series'].Objects[k];
      Inc(n);
      SameInt(Format('s%d rows', [sr.Integers['index']]),
        FChart.StoreOf(sr.Integers['index']).Count, sr.Integers['count']);
    end;
    CheckSeriesList(cs.Arrays['series']);
  end;
  AssertTrue(Format('enough zooms (%d)', [n]), n >= 6);
  Finish('the dataZoom', 100);
end;

{ ==================== conversions ==================== }

procedure TAdvChartSingleRiverTest.TestSingleAxisFindersConvertAsUpstream;
var
  c, p, i, answered: Integer;
  cs, pb, outNode: TJSONObject;
  op, k: string;
  finder, value: TJSONData;
  r: TTyConvertResult;
  got, want: Boolean;
  arr: TJSONArray;
begin
  answered := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'convert' then Continue;
    RenderCase(cs);
    for p := 0 to cs.Arrays['convert'].Count - 1 do
    begin
      pb := cs.Arrays['convert'].Objects[p];
      op := pb.Strings['op'];
      outNode := pb.Objects['out'];
      k := outNode.Strings['k'];
      FWhere := cs.Strings['id'] + ' ' + op + ' ' + pb.Objects['finder'].Strings['text']
        + ' ' + pb.Objects['value'].Strings['text'];
      finder := Decode(pb.Objects['finder'].Find('in'));
      value := Decode(pb.Objects['value'].Find('in'));
      try
        if op = 'contain' then
        begin
          got := FChart.ContainPixelData(finder, value);
          { where upstream throws (a null pixel) the port answers false }
          want := (k = 'bool') and outNode.Booleans['v'];
          SameBool('contains', got, want);
          Continue;
        end;
        if op = 'to' then r := FChart.ConvertToPixelData(finder, value)
        else r := FChart.ConvertFromPixelData(finder, value);
        SameStr('kind', KindName(r.Kind), k);
        if (k = 'arr') and (r.Kind = cvkArray) then
        begin
          Inc(answered);
          arr := outNode.Arrays['v'];
          if Length(r.Values) <> arr.Count then
            Bad(Format('%d numbers, upstream %d', [Length(r.Values), arr.Count]))
          else
            for i := 0 to arr.Count - 1 do
              Same(Format('[%d]', [i]), r.Values[i], arr.Items[i]);
        end;
      finally
        finder.Free;
        value.Free;
      end;
    end;
  end;
  AssertTrue(Format('enough answers (%d)', [answered]), answered >= 60);
  Finish('the conversions', 300);
end;

{ ==================== beyond the fixture ==================== }

procedure TAdvChartSingleRiverTest.TestFixDataWalksKeysAsJavaScriptDoes;
var
  keys: TTyStringArray;
  order: TTyIntegerArray;

  function Txt2(const A: TTyIntegerArray): string;
  var i: Integer;
  begin
    Result := '';
    for i := 0 to High(A) do Result := Result + keys[A[i]] + ' ';
  end;

begin
  { array-index keys first, ascending, then the rest as they came: '01'
    and '-1' and '4294967295' are no index, '4294967294' is }
  keys := nil;
  SetLength(keys, 9);
  keys[0] := 'b';
  keys[1] := '10';
  keys[2] := '2';
  keys[3] := '01';
  keys[4] := '-1';
  keys[5] := '4294967295';
  keys[6] := '4294967294';
  keys[7] := '0';
  keys[8] := 'a';
  order := TyRiverKeyOrder(keys);
  AssertEquals('the key order', '0 2 10 4294967294 b 01 -1 4294967295 a ', Txt2(order));
  { a river of numeric times on a value axis: the zero rows come in the
    index keys' order, not the data's }
  RenderOption('{"animation":false,"singleAxis":{"type":"value"},"series":[{"type":"themeRiver",'
    + '"data":[[3,1,"a"],[1,2,"a"],[2,5,"b"]]}]}', 600, 400);
  AssertEquals('kept and zero rows', 6, FChart.StoreOf(0).Count);
  { a's times are 3 and 1, so its zero row is 2; b's are 1 then 3 -- the
    index keys ascend, whatever order the data met them in }
  AssertEquals('a''s zero row', 2, FChart.StoreOf(0).Get(0, 3), 0);
  AssertEquals('b''s first zero row', 1, FChart.StoreOf(0).Get(0, 4), 0);
  AssertEquals('b''s second zero row', 3, FChart.StoreOf(0).Get(0, 5), 0);
  { a timestamp on a time axis: its key does not parse back }
  RenderOption('{"animation":false,"singleAxis":{"type":"time"},"series":[{"type":"themeRiver",'
    + '"data":[[1446940800000,1,"a"],[1447027200000,2,"b"]]}]}', 600, 400);
  AssertEquals('kept and zero rows', 4, FChart.StoreOf(0).Count);
  AssertTrue('a zero row of a timestamp is no time', IsNan(FChart.StoreOf(0).Get(0, 2)));
end;

procedure TAdvChartSingleRiverTest.TestTheLayersSortAsV8Does;
var
  items: TTyIntegerArray;
  key: TTyDoubleArray;
  i: Integer;
  s: string;
begin
  { stable: equal keys keep their order }
  SetLength(items, 5);
  SetLength(key, 5);
  for i := 0 to 4 do items[i] := i;
  key[0] := 3; key[1] := 1; key[2] := 3; key[3] := 0; key[4] := 1;
  TyV8SortBy(items, key);
  s := '';
  for i := 0 to 4 do s := s + IntToStr(items[i]);
  AssertEquals('stable ascending', '31402', s);
  { a not-a-number key is a tie wherever it is met: the descending first
    run is reversed and the rest inserted by binary search }
  for i := 0 to 4 do items[i] := i;
  key[0] := 5; key[1] := 4; key[2] := NaN; key[3] := 1; key[4] := 2;
  TyV8SortBy(items, key);
  s := '';
  for i := 0 to 4 do s := s + IntToStr(items[i]);
  { the run: 5 then 4 descends and stops at the tie, reversed to 1 0; then
    2 (a tie with 0) after 0, 3 (key 1) first, 4 (key 2) after 3 }
  AssertEquals('V8''s answer with a NaN', '34102', s);
end;

procedure TAdvChartSingleRiverTest.TestALayerIsDrawnAndHit;
var
  L: TTyThemeRiverLayout;
  d: TTyChartDatumRef;
  pg: TTyRiverPolygon;
  mx, my: Double;
  bmp: TBGRABitmap;
  px: TBGRAPixel;
begin
  RenderOption('{"animation":false,"tooltip":{},"singleAxis":{"type":"value","top":50,"bottom":50},'
    + '"series":[{"type":"themeRiver","label":{"show":false},"data":[[1,5,"a"],[2,8,"a"],[3,4,"a"],'
    + '[1,3,"b"],[2,6,"b"],[3,2,"b"]]}]}', 600, 400);
  L := FChart.River(0);
  AssertTrue('laid out', L.Valid);
  AssertEquals('two layers', 2, Length(L.Polygons));
  { a type that draws says nothing about a missing renderer }
  AssertEquals('no diagnostic', 0, FChart.DiagnosticCount);
  { the middle of layer 1 at its second point }
  pg := L.Polygons[1];
  mx := pg.Bottoms[1].X;
  my := (pg.Bottoms[1].Y + pg.Tops[1].Y) / 2 + L.GroupY;
  d := FChart.List.HitTest(mx, my, 96);
  AssertEquals('the hit series', 0, d.SeriesIndex);
  AssertEquals('the hit is the layer''s index', 1, d.DataIndex);
  { and it is painted there }
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
    px := bmp.GetPixel(Round(mx), Round(my));
    AssertTrue('the layer is filled', (px.red <> 255) or (px.green <> 255) or (px.blue <> 255));
  finally
    bmp.Free;
  end;
  { hovered, it shows the item tooltip of the row its index is -- row 1,
    which is layer a's second point, upstream's setItemGraphicEl(idx) }
  FChart.PointerTo(Round(mx), Round(my));
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
  finally
    bmp.Free;
  end;
  AssertEquals('the item tooltip of row 1', 'item:0:1', FChart.TooltipShownWhich);
end;

procedure TAdvChartSingleRiverTest.TestASeriesOnAMissingSingleSaysSo;
var
  i: Integer;
  found: Boolean;
begin
  RenderOption('{"animation":false,"singleAxis":{"type":"value"},"series":[{"type":"scatter",'
    + '"coordinateSystem":"singleAxis","singleAxisIndex":3,"data":[[1],[2]]},'
    + '{"type":"scatter","coordinateSystem":"singleAxis","data":[[1],[2]]}]}', 600, 400);
  found := False;
  for i := 0 to FChart.DiagnosticCount - 1 do
    if Pos('singleAxis', FChart.Diagnostic(i)) > 0 then found := True;
  AssertTrue('a diagnostic names the coordinate system', found);
  AssertEquals('the other one draws', 2, FChart.StoreOf(1).Count);
end;

initialization
  RegisterTest(TAdvChartSingleRiverTest);
end.
