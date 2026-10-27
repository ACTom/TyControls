unit test.advchart.legendtooltip;
{$mode objfpc}{$H+}
{ A LEGEND ITEM'S TOOLTIP, HELD TO UPSTREAM [R5-F, spec 243].

  tools/advchart-oracle/legend-tooltip.js runs the real ECharts 6.1 build in
  node (the harness of toolbox-extra.js): legend.tooltip shown (an item's
  tooltip is its name; a template over it, a position), an item's own
  tooltip with the legend's off, and none at all. Per step it records the
  showtip / hidetip events and the tooltip box (what, its text, its
  top-left).

  This replays the steps through TTyAdvanceChart (the probe of
  test.advchart.tooltipactions: the SSR width table, the box 80 x 40). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.tooltipactions;
type
  { the box's text is protected: a descendant here reads it }
  TLtProbe = class(TTaProbe)
  end;

  TAdvChartLegendTooltipOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FShown: Integer;
    FReport, FWhere: string;
    FLog: TStrings;
    procedure Bad(const AWhat: string);
    procedure Near(const AWhat: string; AGot, AWant: Double);
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheItemsNameAsUpstream;
    procedure TestATemplateAsUpstream;
    procedure TestAnItemsOwnTooltipAsUpstream;
    procedure TestNoTooltipByDefault;
  end;

implementation

const
  cW = 600;
  cH = 400;

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

procedure TAdvChartLegendTooltipOracleTest.SetUp;
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
    sl.LoadFromFile(FixturePath('advchart-legend-tooltip.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FShown := 0;
  FReport := '';
end;

procedure TAdvChartLegendTooltipOracleTest.TearDown;
begin
  FLog.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartLegendTooltipOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartLegendTooltipOracleTest.Near(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if Abs(AGot - AWant) > 1e-6 then
    Bad(Format('%s %g, upstream %g', [AWhat, AGot, AWant]));
end;

procedure TAdvChartLegendTooltipOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType <> 'showtip') and (AEvent.EventType <> 'hidetip') then Exit;
  FLog.Add(AEvent.EventType);
end;

procedure TAdvChartLegendTooltipOracleTest.RunCase(const AId: string);
var
  cases, steps, ev: TJSONArray;
  cs, st, state, tip: TJSONObject;
  probe: TLtProbe;
  i, j: Integer;
  op, want: string;
  now_: Double;
  d: TJSONData;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  probe := TLtProbe.Create(FForm);
  try
    probe.Parent := FForm;
    probe.Controller := FCtl;
    probe.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
      TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
      TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
    probe.TooltipNow := 0;
    probe.SetBounds(0, 0, cW, cH);
    probe.Option := cs.Objects['option'].AsJSON;
    probe.OnChartEvent := @OnEvent;
    probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    now_ := 0;
    steps := cs.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      op := st.Strings['op'];
      FWhere := Format('%s step %d (%s)', [AId, j, op]);
      FLog.Clear;
      if (op = 'move') or (op = 'leave') then
        now_ := now_ + TJSONObject(FRoot).Objects['clock'].Floats['stepDt']
      else if op = 'idle' then
        now_ := now_ + st.Floats['ms'];
      probe.TooltipNow := now_;
      probe.TooltipTick(now_);
      if op = 'move' then probe.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'leave' then probe.Leave;
      probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      { the events, by type }
      ev := st.Arrays['events'];
      Inc(FCompared);
      want := '';
      for i := 0 to ev.Count - 1 do want := want + TJSONArray(ev.Items[i]).Strings[1] + ',';
      FLog.Delimiter := ',';
      FLog.StrictDelimiter := True;
      if FLog.DelimitedText + ',' <> want then
        if not ((FLog.Count = 0) and (want = '')) then
          Bad(Format('events %s, upstream %s', [FLog.DelimitedText, want]));
      state := st.Objects['state'];
      d := state.Find('tip');
      Inc(FCompared);
      if probe.TooltipShown <> (d.JSONType = jtObject) then
        Bad(Format('a box %s, upstream %s', [BoolToStr(probe.TooltipShown, True),
          BoolToStr(d.JSONType = jtObject, True)]))
      else if d.JSONType = jtObject then
      begin
        Inc(FShown);
        tip := TJSONObject(d);
        Inc(FCompared);
        if probe.TooltipShownWhich <> tip.Strings['which'] then
          Bad(Format('the box shows %s, upstream %s', [probe.TooltipShownWhich, tip.Strings['which']]));
        Inc(FCompared);
        if probe.TooltipFormatterText <> tip.Strings['text'] then
          Bad(Format('the text %s, upstream %s', [probe.TooltipFormatterText, tip.Strings['text']]));
        Near('box x', probe.TooltipBox.Left, tip.Arrays['box'].Floats[0]);
        Near('box y', probe.TooltipBox.Top, tip.Arrays['box'].Floats[1]);
      end;
    end;
  finally
    probe.Free;
  end;
  AssertTrue(AId + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AId, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartLegendTooltipOracleTest.TestTheItemsNameAsUpstream;
begin
  RunCase('lg-tip');
  AssertTrue('boxes compared', FShown >= 3);
end;

procedure TAdvChartLegendTooltipOracleTest.TestATemplateAsUpstream;
begin
  RunCase('lg-tip-fmt');
end;

procedure TAdvChartLegendTooltipOracleTest.TestAnItemsOwnTooltipAsUpstream;
begin
  RunCase('lg-tip-item');
end;

procedure TAdvChartLegendTooltipOracleTest.TestNoTooltipByDefault;
begin
  RunCase('lg-tip-off');
end;

initialization
  RegisterTest(TAdvChartLegendTooltipOracleTest);
end.
