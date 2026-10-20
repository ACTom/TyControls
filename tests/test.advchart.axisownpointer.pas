unit test.advchart.axisownpointer;
{$mode objfpc}{$H+}
{ AN AXIS' OWN POINTER AND WHEN THE TOOLTIP'S FUNCTIONS RUN, HELD TO
  UPSTREAM [round-2 batch R2-I7].

  tools/advchart-oracle/axis-own-pointer.js runs the real ECharts 6.1 build
  in node as tooltip-keep.js does. Its first cases collect axes for their
  own `axisPointer.show` (on the axis, or the root's) under tooltips that do
  not trigger on the axis -- 'none', 'item', none at all -- with
  triggerTooltip false, a category axis, a link across two grids, show
  'auto', a shadow, label templates and a function label; the rest count
  how often a function formatter, a function position and a valueFormatter
  run per show (an item's, an axis', one kept across a setOption, one
  waiting out showDelay). Per step it records the events, the axisPointer
  model's axes (status, value, rows, and for a shown one the pointer line's
  coordinate and its label's text), the box and its text, and the calls.

  This replays them through TTyAdvanceChart with test.advchart.tooltipactions'
  probe, and RENDERS TWICE after every step: a function that runs on every
  paint rather than once per show is counted twice here. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Data, tyControls.AdvChart.Events,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.AxisPointer,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax, test.advchart.tooltipactions;
type
  TAopProbe = class(TTaProbe)
  public
    { the pointer line's coordinate along its axis, as it is drawn }
    function LineAt(const AHit: TTyAxisHit): Double;
    { the label's text; '' when the pointer draws none }
    function LabelOf(const AHit: TTyAxisHit): string;
    function BoxText: string;
  end;

  TAdvChartAxisOwnPointerOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FLog: TStrings;
    FFmt, FPos, FVf, FPtrFmt: Integer;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure Finish(const AWhat: string);
    function Ssr: ITyTextMeasurer;
    function NewProbe(const AOptionJson: string; ATag: Integer): TAopProbe;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure CompareEvents(AWant: TJSONArray);
    procedure CompareState(AChart: TAopProbe; AState: TJSONObject; AIndex: Integer);
    procedure CompareCalls(ACalls: TJSONObject);
    procedure RunCase(const AId: string);
    function HFmt(const AParams: TTyChartParams): string;
    function HVf(const AParams: TTyChartParams): string;
    function HPtrFmt(const AParams: TTyChartParams): string;
    function HPos(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { an axis' own pointer }
    procedure TestTheRootShowUnderANoneTooltipAsUpstream;
    procedure TestAnAxisShowUnderAnItemTooltipAsUpstream;
    procedure TestTriggerTooltipFalseAsUpstream;
    procedure TestACategoryAxisShowAsUpstream;
    procedure TestAShowBesideAnAxisTooltipAsUpstream;
    procedure TestLinkedOwnPointersAsUpstream;
    procedure TestNoTooltipComponentAsUpstream;
    procedure TestShowAutoIsNotCollectedAsUpstream;
    procedure TestTheOwnLabelAsUpstream;
    procedure TestAnOwnShadowAsUpstream;
    { the tooltip's functions }
    procedure TestAnItemShowCallsEachOnceAsUpstream;
    procedure TestAValueFormatterWithoutAFormatterAsUpstream;
    procedure TestAnAxisShowCallsAsUpstream;
    procedure TestAKeptAxisTooltipCallsAsUpstream;
    procedure TestShowDelayDefersTheCallsAsUpstream;
    procedure TestTheMarkupIsBuiltWhenTheShowIsTriedAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cNulMark = #$E2#$90#$80;

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
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

procedure FromIsUid(AData: TJSONData);
var i: Integer;
begin
  if AData = nil then Exit;
  if AData is TJSONObject then
  begin
    for i := 0 to AData.Count - 1 do
      if (TJSONObject(AData).Names[i] = 'from') and (AData.Items[i].JSONType = jtString) then
        AData.Items[i].AsString := '<view uid>'
      else
        FromIsUid(AData.Items[i]);
  end
  else if AData is TJSONArray then
    for i := 0 to AData.Count - 1 do FromIsUid(AData.Items[i]);
end;

function ParsePort(const AJson: string): TJSONData;
begin
  Result := GetJSON(StringReplace(AJson, '\u0000', cNulMark, [rfReplaceAll]));
  FromIsUid(Result);
end;

function SameJson(AWant, AGot: TJSONData): Boolean;
var
  i: Integer;
  wo, go: TJSONObject;
begin
  Result := False;
  if (AWant = nil) or (AGot = nil) then Exit(AWant = AGot);
  if AWant.JSONType <> AGot.JSONType then Exit;
  case AWant.JSONType of
    jtNull: Result := True;
    jtBoolean: Result := AWant.AsBoolean = AGot.AsBoolean;
    jtNumber: Result := AWant.AsFloat = AGot.AsFloat;
    jtString: Result := AWant.AsString = AGot.AsString;
    jtArray:
      begin
        if AWant.Count <> AGot.Count then Exit;
        for i := 0 to AWant.Count - 1 do
          if not SameJson(TJSONArray(AWant).Items[i], TJSONArray(AGot).Items[i]) then Exit;
        Result := True;
      end;
    jtObject:
      begin
        wo := TJSONObject(AWant);
        go := TJSONObject(AGot);
        if wo.Count <> go.Count then Exit;
        for i := 0 to wo.Count - 1 do
        begin
          if go.Names[i] <> wo.Names[i] then Exit;
          if not SameJson(wo.Items[i], go.Items[i]) then Exit;
        end;
        Result := True;
      end;
  end;
end;

function FixSdiText(AArr: TJSONArray): string;
var k: Integer;
begin
  Result := '';
  for k := 0 to AArr.Count - 1 do
  begin
    if k > 0 then Result := Result + ';';
    Result := Result + IntToStr(TJSONArray(AArr.Items[k]).Integers[0]) + ','
      + IntToStr(TJSONArray(AArr.Items[k]).Integers[1]) + ','
      + IntToStr(TJSONArray(AArr.Items[k]).Integers[2]);
  end;
end;

{ ==================== the probe ==================== }

function TAopProbe.LineAt(const AHit: TTyAxisHit): Double;
begin
  Result := NaN;
  if AHit.Axis = nil then Exit;
  Result := AHit.Axis.DataToCoord(PointerValueOf(AHit), True);
end;

function TAopProbe.LabelOf(const AHit: TTyAxisHit): string;
begin
  Result := '';
  if (AHit.Axis = nil) or not AHit.Spec.LabelSpec.Show then Exit;
  Result := PointerLabelText(AHit, PointerValueOf(AHit));
end;

function TAopProbe.BoxText: string;
begin
  Result := TooltipFormatterText;
end;

{ ==================== the oracle test ==================== }

function TAdvChartAxisOwnPointerOracleTest.HFmt(const AParams: TTyChartParams): string;
var i: Integer;
begin
  Inc(FFmt);
  Result := '';
  for i := 0 to High(AParams) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + IntToStr(AParams[i].SeriesIndex) + ':'
      + IntToStr(AParams[i].RawDataIndex) + '@';
    { params.axisDim + params.axisIndex: an axis tooltip's section, an
      item's undefined }
    if AParams[i].AxisDimension = '' then Result := Result + 'undefinedundefined'
    else Result := Result + AParams[i].AxisDimension + IntToStr(AParams[i].AxisIndex);
  end;
end;

function TAdvChartAxisOwnPointerOracleTest.HVf(const AParams: TTyChartParams): string;
begin
  Inc(FVf);
  Result := 'v';
  if Length(AParams) > 0 then Result := Result + AParams[0].ValueText;
end;

function TAdvChartAxisOwnPointerOracleTest.HPtrFmt(const AParams: TTyChartParams): string;
begin
  Inc(FPtrFmt);
  Result := 'P';
  if Length(AParams) > 0 then Result := Result + AParams[0].ValueText;
end;

function TAdvChartAxisOwnPointerOracleTest.HPos(
  const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  Inc(FPos);
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpPoint;
  Result.X.Kind := cpvNumber;
  Result.X.Num := 10;
  Result.Y.Kind := cpvNumber;
  Result.Y.Num := 10;
end;

procedure TAdvChartAxisOwnPointerOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FLog := TStringList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-axis-own-pointer.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  TyChartRegisterFormatter('fmt', @HFmt);
  TyChartRegisterFormatter('vf', @HVf);
  TyChartRegisterFormatter('ptrfmt', @HPtrFmt);
  TyChartRegisterPositionHandler('pos', @HPos);
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartAxisOwnPointerOracleTest.TearDown;
begin
  TyChartUnregisterFormatter('fmt');
  TyChartUnregisterFormatter('vf');
  TyChartUnregisterFormatter('ptrfmt');
  TyChartUnregisterPositionHandler('pos');
  FLog.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartAxisOwnPointerOracleTest.Ssr: ITyTextMeasurer;
begin
  Result := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
end;

procedure TAdvChartAxisOwnPointerOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartAxisOwnPointerOracleTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if HexOf(AGot) <> LowerCase(AHex) then
    Bad(Format('%s %s (%s), upstream %s (%s)', [AWhat, Txt(AGot), HexOf(AGot),
      Txt(FromHex(AHex)), AHex]));
end;

procedure TAdvChartAxisOwnPointerOracleTest.Finish(const AWhat: string);
begin
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartAxisOwnPointerOracleTest.NewProbe(const AOptionJson: string;
  ATag: Integer): TAopProbe;
begin
  Result := TAopProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Measurer := Ssr;
  Result.Tag := ATag;
  Result.TooltipNow := 0;
  Result.SetBounds(0, 0, cW, cH);
  Result.Option := AOptionJson;
  Result.OnChartEvent := @OnEvent;
  Result.ChartOn('updated', @OnEvent);
  Result.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartAxisOwnPointerOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType <> 'updateaxispointer') and (AEvent.EventType <> 'showtip')
    and (AEvent.EventType <> 'hidetip') and (AEvent.EventType <> 'updated') then Exit;
  FLog.Add(IntToStr(TComponent(Sender).Tag) + #9 + AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TAdvChartAxisOwnPointerOracleTest.CompareEvents(AWant: TJSONArray);
var
  i, n: Integer;
  e: TJSONArray;
  parts: TStringList;
  got: TJSONData;
begin
  Inc(FCompared);
  if FLog.Count <> AWant.Count then
  begin
    Bad(Format('%d events, upstream %d', [FLog.Count, AWant.Count]));
    for i := 0 to Min(FLog.Count, AWant.Count + 3) - 1 do
      Bad(Format('  port %d: %s', [i, Copy(StringReplace(FLog[i], #9, ' ', [rfReplaceAll]), 1, 160)]));
    for i := 0 to AWant.Count - 1 do
      Bad(Format('  upstream %d: %s', [i, Copy(AWant.Items[i].AsJSON, 1, 160)]));
  end;
  n := Min(FLog.Count, AWant.Count);
  parts := TStringList.Create;
  try
    parts.Delimiter := #9;
    parts.StrictDelimiter := True;
    for i := 0 to n - 1 do
    begin
      e := TJSONArray(AWant.Items[i]);
      parts.DelimitedText := FLog[i];
      Inc(FCompared);
      if (parts[0] <> IntToStr(e.Integers[0])) or (parts[1] <> e.Strings[1]) then
      begin
        Bad(Format('event %d: chart %s %s, upstream chart %d %s', [i, parts[0], parts[1],
          e.Integers[0], e.Strings[1]]));
        Continue;
      end;
      if e.Items[2].JSONType = jtNull then Continue;
      got := ParsePort(parts[2]);
      try
        Inc(FCompared);
        if not SameJson(e.Items[2], got) then
          Bad(Format('event %d (%s %s): %s, upstream %s', [i, parts[0], parts[1],
            Copy(got.AsJSON, 1, 400), Copy(e.Items[2].AsJSON, 1, 400)]));
      finally
        got.Free;
      end;
    end;
  finally
    parts.Free;
  end;
end;

procedure TAdvChartAxisOwnPointerOracleTest.CompareState(AChart: TAopProbe;
  AState: TJSONObject; AIndex: Integer);
var
  axes: TJSONArray;
  ax, tip, dr: TJSONObject;
  hits: TTyAxisHitArray;
  k, c, h, n: Integer;
  shown: Boolean;
  box: TTyRectF;
  at: TTyPointF;
  who, lab: string;
begin
  who := 'chart ' + IntToStr(AIndex);
  hits := AChart.Hits;
  axes := AState.Arrays['axes'];
  n := 0;
  for k := 0 to axes.Count - 1 do
  begin
    ax := axes.Objects[k];
    h := -1;
    for c := 0 to High(hits) do
      if (hits[c].Axis.Dim = ax.Strings['dim'])
        and (hits[c].Axis.ComponentIndex = ax.Integers['index']) then h := c;
    Inc(FCompared);
    if (ax.Strings['status'] = 'show') <> (h >= 0) then
    begin
      Bad(Format('%s %s: shown %s, upstream %s', [who, ax.Strings['key'],
        BoolToStr(h >= 0, True), ax.Strings['status']]));
      Continue;
    end;
    if h < 0 then Continue;
    Inc(n);
    Same(who + ' ' + ax.Strings['key'] + ' value', AChart.PointerValueOf(hits[h]), ax.Strings['value']);
    Inc(FCompared);
    if AChart.RowsText(hits[h]) <> FixSdiText(ax.Arrays['sdi']) then
      Bad(Format('%s %s rows %s, upstream %s', [who, ax.Strings['key'],
        AChart.RowsText(hits[h]), FixSdiText(ax.Arrays['sdi'])]));
    { what the pointer draws: the line where it stands, the label's text }
    dr := ax.Objects['draw'];
    if dr.Find('pixel').JSONType = jtString then
    begin
      Inc(FCompared);
      if hits[h].Spec.PointerType <> aptLine then
        Bad(Format('%s %s: no line, upstream one', [who, ax.Strings['key']]))
      else
        Same(who + ' ' + ax.Strings['key'] + ' line', AChart.LineAt(hits[h]), dr.Strings['pixel']);
    end;
    lab := AChart.LabelOf(hits[h]);
    Inc(FCompared);
    if dr.Find('label').JSONType = jtNull then
    begin
      if lab <> '' then
        Bad(Format('%s %s: label %s, upstream none', [who, ax.Strings['key'], lab]));
    end
    else if lab <> dr.Strings['label'] then
      Bad(Format('%s %s: label %s, upstream %s', [who, ax.Strings['key'], lab,
        dr.Strings['label']]));
  end;
  Inc(FCompared);
  if n <> Length(hits) then
    Bad(Format('%s: %d pointers, upstream %d', [who, Length(hits), n]));
  if AState.Find('tip').JSONType = jtNull then Exit;
  tip := AState.Objects['tip'];
  shown := AChart.TooltipShown;
  Inc(FCompared);
  if shown <> tip.Booleans['visible'] then
  begin
    Bad(Format('%s: box shown %s, upstream %s', [who, BoolToStr(shown, True),
      BoolToStr(tip.Booleans['visible'], True)]));
    Exit;
  end;
  Inc(FCompared);
  if AChart.TooltipShowFlag <> tip.Booleans['show'] then
    Bad(Format('%s: _show %s, upstream %s', [who, BoolToStr(AChart.TooltipShowFlag, True),
      BoolToStr(tip.Booleans['show'], True)]));
  if not shown then Exit;
  Inc(FCompared);
  if tip.Strings['which'] <> AChart.Which then
    Bad(Format('%s: the box shows %s, upstream %s', [who, AChart.Which, tip.Strings['which']]));
  at := AChart.TooltipAnchorF;
  Same(who + ' anchor x', at.X, tip.Arrays['anchor'].Strings[0]);
  Same(who + ' anchor y', at.Y, tip.Arrays['anchor'].Strings[1]);
  box := AChart.TooltipBox;
  Same(who + ' box x', box.Left, tip.Arrays['box'].Strings[0]);
  Same(who + ' box y', box.Top, tip.Arrays['box'].Strings[1]);
  { a function formatter's text; the default markup is upstream's richText,
    not compared }
  if (tip.Find('text') <> nil) and (tip.Find('text').JSONType = jtString)
    and (Pos('{', tip.Strings['text']) = 0) then
  begin
    Inc(FCompared);
    if AChart.BoxText <> tip.Strings['text'] then
      Bad(Format('%s: the box says %s, upstream %s', [who, AChart.BoxText,
        tip.Strings['text']]));
  end;
end;

procedure TAdvChartAxisOwnPointerOracleTest.CompareCalls(ACalls: TJSONObject);

  procedure One(const AName: string; AGot: Integer);
  begin
    Inc(FCompared);
    if AGot <> ACalls.Integers[AName] then
      Bad(Format('%s ran %d times, upstream %d', [AName, AGot, ACalls.Integers[AName]]));
  end;

begin
  One('fmt', FFmt);
  One('pos', FPos);
  One('vf', FVf);
end;

procedure TAdvChartAxisOwnPointerOracleTest.RunCase(const AId: string);
var
  cases, charts, steps: TJSONArray;
  cs, st: TJSONObject;
  probes: array of TAopProbe;
  i, j, c, r: Integer;
  op: string;
  now_: Double;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  charts := cs.Arrays['charts'];
  SetLength(probes, charts.Count);
  for i := 0 to High(probes) do probes[i] := nil;
  try
    for i := 0 to charts.Count - 1 do
      probes[i] := NewProbe(charts.Objects[i].Objects['option'].AsJSON, i);
    now_ := 0;
    steps := cs.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      op := st.Strings['op'];
      FWhere := Format('%s step %d (%s)', [AId, j, op]);
      FLog.Clear;
      FFmt := 0;
      FPos := 0;
      FVf := 0;
      FPtrFmt := 0;
      if (op = 'move') or (op = 'leave') then
        now_ := now_ + TJSONObject(FRoot).Objects['clock'].Floats['stepDt']
      else if op = 'idle' then
        now_ := now_ + st.Floats['ms'];
      if op <> 'setOption' then
        for i := 0 to High(probes) do
        begin
          probes[i].TooltipNow := now_;
          probes[i].TooltipTick(now_);
        end;
      c := st.Integers['chart'];
      if op = 'move' then
        probes[c].Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'leave' then
        probes[c].Leave
      else if op = 'setOption' then
        probes[c].SetOption(st.Objects['option'].AsJSON, st.Booleans['notMerge']);
      { TWICE: what runs per paint is counted twice }
      for r := 1 to 2 do
        for i := 0 to High(probes) do
          probes[i].Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      CompareEvents(st.Arrays['events']);
      for i := 0 to High(probes) do
        CompareState(probes[i], st.Arrays['state'].Objects[i], i);
      CompareCalls(st.Objects['calls']);
    end;
  finally
    for i := 0 to High(probes) do probes[i].Free;
  end;
  Finish(AId);
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestTheRootShowUnderANoneTooltipAsUpstream;
begin
  RunCase('own-root-none');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestAnAxisShowUnderAnItemTooltipAsUpstream;
begin
  RunCase('own-x-item');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestTriggerTooltipFalseAsUpstream;
begin
  RunCase('own-trigger-false');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestACategoryAxisShowAsUpstream;
begin
  RunCase('own-category');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestAShowBesideAnAxisTooltipAsUpstream;
begin
  RunCase('own-plus-tooltip-axis');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestLinkedOwnPointersAsUpstream;
begin
  RunCase('own-link');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestNoTooltipComponentAsUpstream;
begin
  RunCase('own-no-tooltip');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestShowAutoIsNotCollectedAsUpstream;
begin
  RunCase('own-auto');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestTheOwnLabelAsUpstream;
begin
  RunCase('own-label');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestAnOwnShadowAsUpstream;
begin
  RunCase('own-shadow');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestAnItemShowCallsEachOnceAsUpstream;
begin
  RunCase('calls-item');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestAValueFormatterWithoutAFormatterAsUpstream;
begin
  RunCase('calls-item-vf');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestAnAxisShowCallsAsUpstream;
begin
  RunCase('calls-axis');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestAKeptAxisTooltipCallsAsUpstream;
begin
  RunCase('calls-axis-keep');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestShowDelayDefersTheCallsAsUpstream;
begin
  RunCase('calls-delay');
end;

procedure TAdvChartAxisOwnPointerOracleTest.TestTheMarkupIsBuiltWhenTheShowIsTriedAsUpstream;
begin
  RunCase('calls-delay-vf');
end;

initialization
  RegisterTest(TAdvChartAxisOwnPointerOracleTest);
end.
