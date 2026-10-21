unit test.advchart.tooltipkeep;
{$mode objfpc}{$H+}
{ THE TOOLTIP SHOWN BY A CLICK, AND THE BOX A RE-RENDER LEAVES UP, HELD TO
  UPSTREAM [fix batch F4b].

  tools/advchart-oracle/tooltip-keep.js runs the real ECharts 6.1 build in
  node as tooltip-actions.js does: triggerOn 'click' and 'mousemove|click'
  with item and axis triggers (alwaysShowContent too), and TooltipView's
  _keepShow -- a setOption or an action whose update renders the view
  leaves the box up and a timeout shows the tip again at the last point;
  not under triggerOn 'none' or 'click', not after a hideTip cleared the
  point, not for a highlight (no render), and a notMerge setOption makes a
  new view (the box goes). Per step it records every updateaxispointer,
  showtip, hidetip and updated, the axisPointer model's axes and the box.

  This replays them through TTyAdvanceChart exactly as
  test.advchart.tooltipactions does (its probe), with one more step:
  setOption (SetOption with the step's notMerge).

  [R2-E] More of the same oracle: the frozen box says what it said until
  the keep timer shows it again (the content's text, a template
  formatter's); a roam and a dataZoom handle's hover render no tooltip view
  (nothing kept), a legendScroll does (kept); and an axis' own status
  'show' -- cartesian, polar, single, a time axis' date string -- drawn
  before anything moves, rewritten by a pointer event, back only where a
  setOption writes it (or a notMerge). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax, test.advchart.tooltipactions;
type
  TAdvChartTooltipKeepOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FLog: TStrings;
    FSkipRows: Boolean;
    FText, FPtr, FBorder: Boolean;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure Finish(const AWhat: string);
    function Ssr: ITyTextMeasurer;
    function NewProbe(const AOptionJson: string; ATag: Integer): TTaProbe;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure CompareEvents(AWant: TJSONArray);
    procedure CompareState(AChart: TTaProbe; AState: TJSONObject; AIndex: Integer);
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAClickShowsAnItemAsUpstream;
    procedure TestMoveOrClickAsUpstream;
    procedure TestAClickUnderAlwaysShowContentAsUpstream;
    procedure TestAClickShowsTheAxisTooltipAsUpstream;
    procedure TestASetOptionKeepsTheAxisTooltipAsUpstream;
    procedure TestASetOptionKeepsTheItemTooltipAsUpstream;
    procedure TestADataZoomKeepsTheBoxAsUpstream;
    procedure TestTheKeptPointFindsNothingAsUpstream;
    procedure TestAHighlightKeepsNothingAsUpstream;
    procedure TestAlwaysShowContentKeepsTheBoxAsUpstream;
    procedure TestTriggerOnClickKeepsNothingAsUpstream;
    procedure TestTriggerOnNoneKeepsNothingAsUpstream;
    procedure TestAHiddenBoxKeepsNothingAsUpstream;
    procedure TestTheKeptShowWaitsOutShowDelayAsUpstream;
    procedure TestAShowTipPointIsKeptAsUpstream;
    procedure TestAnAxisTipTurnedItemKeepsNoDataByCoordSysAsUpstream;
    { [R2-E] }
    procedure TestTheFrozenBoxKeepsItsTextAsUpstream;
    procedure TestTheFrozenAxisBoxKeepsItsTextAsUpstream;
    procedure TestTheFrozenBoxOfAGoneRowAsUpstream;
    procedure TestARoamKeepsNothingAsUpstream;
    procedure TestALegendScrollKeepsTheBoxAsUpstream;
    procedure TestADataZoomHandleHoverKeepsNothingAsUpstream;
    procedure TestACartesianStatusShowAsUpstream;
    procedure TestAPolarAngleStatusShowAsUpstream;
    procedure TestAPolarRadiusStatusShowAsUpstream;
    procedure TestASingleAxisStatusShowAsUpstream;
    procedure TestATimeAxisStatusShowAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cNulMark = #$E2#$90#$80;

type
  { an axis' own status 'show' [R2-E] }
  TTkProbe = class(TTaProbe)
  end;

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

{ ==================== the oracle test ==================== }

procedure TAdvChartTooltipKeepOracleTest.SetUp;
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
    sl.LoadFromFile(FixturePath('advchart-tooltip-keep.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartTooltipKeepOracleTest.TearDown;
begin
  FLog.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartTooltipKeepOracleTest.Ssr: ITyTextMeasurer;
begin
  Result := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
end;

procedure TAdvChartTooltipKeepOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartTooltipKeepOracleTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if HexOf(AGot) <> LowerCase(AHex) then
    Bad(Format('%s %s (%s), upstream %s (%s)', [AWhat, Txt(AGot), HexOf(AGot),
      Txt(FromHex(AHex)), AHex]));
end;

procedure TAdvChartTooltipKeepOracleTest.Finish(const AWhat: string);
begin
  if GetEnvironmentVariable('TY_TOOLTIPKEEP_COUNTS') = '1' then
    WriteLn(StdErr, AWhat, ': ', FCompared, ' comparisons');
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartTooltipKeepOracleTest.NewProbe(const AOptionJson: string;
  ATag: Integer): TTaProbe;
begin
  Result := TTkProbe.Create(FForm);
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

procedure TAdvChartTooltipKeepOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType <> 'updateaxispointer') and (AEvent.EventType <> 'showtip')
    and (AEvent.EventType <> 'hidetip') and (AEvent.EventType <> 'updated') then Exit;
  FLog.Add(IntToStr(TComponent(Sender).Tag) + #9 + AEvent.EventType + #9 + AEvent.Payload);
end;

procedure TAdvChartTooltipKeepOracleTest.CompareEvents(AWant: TJSONArray);
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

procedure TAdvChartTooltipKeepOracleTest.CompareState(AChart: TTaProbe;
  AState: TJSONObject; AIndex: Integer);
var
  axes: TJSONArray;
  ax, tip: TJSONObject;
  hits: TTyAxisHitArray;
  k, c, h, n: Integer;
  shown: Boolean;
  box: TTyRectF;
  at: TTyPointF;
  who, bs: string;
  bc: TTyColor;
begin
  who := 'chart ' + IntToStr(AIndex);
  hits := AChart.Hits;
  { [R2-E] what is drawn: the pointer's hits, else the axes' own status
    'show' }
  if FPtr and (Length(hits) = 0) then hits := TTkProbe(AChart).OptionPointerHits;
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
    { [R2-E] the value through the axis' scale where the oracle gives it }
    if (ax.Find('parsed') <> nil) and (ax.Find('parsed').JSONType = jtString) then
      Same(who + ' ' + ax.Strings['key'] + ' parsed', AChart.PointerValueOf(hits[h]), ax.Strings['parsed'])
    else
      Same(who + ' ' + ax.Strings['key'] + ' value', AChart.PointerValueOf(hits[h]), ax.Strings['value']);
    { a pointer kept across a dataZoom: the model's seriesDataIndices keep
      the raw dataIndex they were written with beside dataIndexInside; the
      port keeps the view row (the deviation the spec records) }
    if FSkipRows then Continue;
    Inc(FCompared);
    if AChart.RowsText(hits[h]) <> FixSdiText(ax.Arrays['sdi']) then
      Bad(Format('%s %s rows %s, upstream %s', [who, ax.Strings['key'],
        AChart.RowsText(hits[h]), FixSdiText(ax.Arrays['sdi'])]));
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
  { [R2-E] the content's text: a template formatter's }
  if FText and (tip.Find('text') <> nil) and (tip.Find('text').JSONType = jtString) then
  begin
    Inc(FCompared);
    if TTkProbe(AChart).TooltipFormatterText <> tip.Strings['text'] then
      Bad(Format('%s: the box says %s, upstream %s', [who, TTkProbe(AChart).TooltipFormatterText,
        tip.Strings['text']]));
  end;
  { [r2v] its border colour (setContent's), as '#rrggbb' }
  if FBorder and (tip.Find('border') <> nil) and (tip.Find('border').JSONType = jtString) then
  begin
    Inc(FCompared);
    bc := TTkProbe(AChart).TooltipBorderColour;
    bs := LowerCase(Format('#%.2x%.2x%.2x', [TyRedOf(bc), TyGreenOf(bc), TyBlueOf(bc)]));
    if bs <> tip.Strings['border'] then
      Bad(Format('%s: the box border is %s, upstream %s', [who, bs, tip.Strings['border']]));
  end;
end;

procedure TAdvChartTooltipKeepOracleTest.RunCase(const AId: string);
var
  cases, charts, steps: TJSONArray;
  cs, st: TJSONObject;
  probes: array of TTaProbe;
  i, j, c: Integer;
  op: string;
  now_: Double;
  noFrame: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  charts := cs.Arrays['charts'];
  SetLength(probes, charts.Count);
  for i := 0 to High(probes) do probes[i] := nil;
  FSkipRows := False;
  FText := (cs.Find('text') <> nil) and cs.Booleans['text'];
  FBorder := (cs.Find('border') <> nil) and cs.Booleans['border'];
  FPtr := (cs.Find('ptr') <> nil) and cs.Booleans['ptr'];
  try
    for i := 0 to charts.Count - 1 do
      probes[i] := NewProbe(charts.Objects[i].Objects['option'].AsJSON, i);
    { [R2-E] the state before any step }
    if cs.Find('initial') <> nil then
    begin
      FWhere := AId + ' initial';
      CompareState(probes[0], cs.Objects['initial'], 0);
    end;
    now_ := 0;
    steps := cs.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      op := st.Strings['op'];
      FWhere := Format('%s step %d (%s)', [AId, j, op]);
      FLog.Clear;
      if (op = 'move') or (op = 'click') or (op = 'wheel') or (op = 'leave') then
        now_ := now_ + TJSONObject(FRoot).Objects['clock'].Floats['stepDt']
      else if op = 'idle' then
        now_ := now_ + st.Floats['ms'];
      if (op <> 'action') and (op <> 'setOption') then
        for i := 0 to High(probes) do
        begin
          probes[i].TooltipNow := now_;
          probes[i].TooltipTick(now_);
        end;
      if op <> 'idle' then c := st.Integers['chart'] else c := -1;
      if op = 'move' then
        probes[c].Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'click' then
        probes[c].Click(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'leave' then
        probes[c].Leave
      else if op = 'action' then
      begin
        probes[c].DispatchAction(StringReplace(st.Objects['payload'].AsJSON, cNulMark,
          '\u0000', [rfReplaceAll]));
        if st.Objects['payload'].Get('type', '') = 'dataZoom' then FSkipRows := True;
      end
      else if op = 'setOption' then
        probes[c].SetOption(st.Objects['option'].AsJSON, st.Booleans['notMerge']);
      { a step the next one follows before any frame: its events alone }
      noFrame := (st.Find('noFrame') <> nil) and st.Booleans['noFrame'];
      if not noFrame then
        for i := 0 to High(probes) do
          probes[i].Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      CompareEvents(st.Arrays['events']);
      if not noFrame then
        for i := 0 to High(probes) do
          CompareState(probes[i], st.Arrays['state'].Objects[i], i);
    end;
  finally
    for i := 0 to High(probes) do probes[i].Free;
  end;
  Finish(AId);
end;

procedure TAdvChartTooltipKeepOracleTest.TestAClickShowsAnItemAsUpstream;
begin
  RunCase('click-item');
end;

procedure TAdvChartTooltipKeepOracleTest.TestMoveOrClickAsUpstream;
begin
  RunCase('click-move-item');
end;

procedure TAdvChartTooltipKeepOracleTest.TestAClickUnderAlwaysShowContentAsUpstream;
begin
  RunCase('click-always');
end;

procedure TAdvChartTooltipKeepOracleTest.TestAClickShowsTheAxisTooltipAsUpstream;
begin
  RunCase('click-axis');
end;

procedure TAdvChartTooltipKeepOracleTest.TestASetOptionKeepsTheAxisTooltipAsUpstream;
begin
  RunCase('keep-axis');
end;

procedure TAdvChartTooltipKeepOracleTest.TestASetOptionKeepsTheItemTooltipAsUpstream;
begin
  RunCase('keep-item');
end;

procedure TAdvChartTooltipKeepOracleTest.TestADataZoomKeepsTheBoxAsUpstream;
begin
  RunCase('keep-datazoom');
end;

procedure TAdvChartTooltipKeepOracleTest.TestTheKeptPointFindsNothingAsUpstream;
begin
  RunCase('keep-legend');
end;

procedure TAdvChartTooltipKeepOracleTest.TestAHighlightKeepsNothingAsUpstream;
begin
  RunCase('keep-highlight');
end;

procedure TAdvChartTooltipKeepOracleTest.TestAlwaysShowContentKeepsTheBoxAsUpstream;
begin
  RunCase('keep-always');
end;

procedure TAdvChartTooltipKeepOracleTest.TestTriggerOnClickKeepsNothingAsUpstream;
begin
  RunCase('keep-click');
end;

procedure TAdvChartTooltipKeepOracleTest.TestTriggerOnNoneKeepsNothingAsUpstream;
begin
  RunCase('keep-none');
end;

procedure TAdvChartTooltipKeepOracleTest.TestAHiddenBoxKeepsNothingAsUpstream;
begin
  RunCase('keep-hidden');
end;

procedure TAdvChartTooltipKeepOracleTest.TestTheKeptShowWaitsOutShowDelayAsUpstream;
begin
  RunCase('keep-delay');
end;

procedure TAdvChartTooltipKeepOracleTest.TestAShowTipPointIsKeptAsUpstream;
begin
  RunCase('keep-showtip-point');
end;

procedure TAdvChartTooltipKeepOracleTest.TestAnAxisTipTurnedItemKeepsNoDataByCoordSysAsUpstream;
begin
  RunCase('keep-axis-to-item');
end;

procedure TAdvChartTooltipKeepOracleTest.TestTheFrozenBoxKeepsItsTextAsUpstream;
begin
  RunCase('keep-frozen-text');
  { the series coloured anew meanwhile: the frozen box keeps its border }
  RunCase('keep-frozen-border');
  { a show not drawn yet when the re-render freezes the box: its text }
  RunCase('keep-frozen-unpainted');
end;

procedure TAdvChartTooltipKeepOracleTest.TestTheFrozenAxisBoxKeepsItsTextAsUpstream;
begin
  RunCase('keep-frozen-axis-text');
end;

procedure TAdvChartTooltipKeepOracleTest.TestTheFrozenBoxOfAGoneRowAsUpstream;
begin
  RunCase('keep-frozen-gone');
end;

procedure TAdvChartTooltipKeepOracleTest.TestARoamKeepsNothingAsUpstream;
begin
  RunCase('keep-roam');
end;

procedure TAdvChartTooltipKeepOracleTest.TestALegendScrollKeepsTheBoxAsUpstream;
begin
  RunCase('keep-legend-scroll');
end;

procedure TAdvChartTooltipKeepOracleTest.TestADataZoomHandleHoverKeepsNothingAsUpstream;
begin
  RunCase('keep-dz-hover');
end;

procedure TAdvChartTooltipKeepOracleTest.TestACartesianStatusShowAsUpstream;
begin
  RunCase('ptr-cartesian');
end;

procedure TAdvChartTooltipKeepOracleTest.TestAPolarAngleStatusShowAsUpstream;
begin
  RunCase('ptr-polar');
end;

procedure TAdvChartTooltipKeepOracleTest.TestAPolarRadiusStatusShowAsUpstream;
begin
  RunCase('ptr-radius');
end;

procedure TAdvChartTooltipKeepOracleTest.TestASingleAxisStatusShowAsUpstream;
begin
  RunCase('ptr-single');
end;

procedure TAdvChartTooltipKeepOracleTest.TestATimeAxisStatusShowAsUpstream;
begin
  RunCase('ptr-time');
end;

initialization
  RegisterTest(TAdvChartTooltipKeepOracleTest);
end.
