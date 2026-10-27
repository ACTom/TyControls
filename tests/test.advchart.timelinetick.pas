unit test.advchart.timelinetick;
{$mode objfpc}{$H+}
{ A TIMELINE TICK AS A DATA ITEM, HELD TO UPSTREAM [R5-I, spec 243b].

  tools/advchart-oracle/timeline-tick.js runs the real ECharts 6.1 build in
  node (the harness of legend-tooltip.js): a tick whose item model says
  tooltip is a data item of the timeline's -- the tooltip shows its label
  (or a formatter over the timeline's params), the chart's mouseover,
  mouseout and click carry those params; one whose item says no tooltip is
  neither. Per step it records the showtip / hidetip and mouse events and
  the tooltip box (what, its text, its top-left).

  This replays the steps through TTyAdvanceChart (the probe of
  test.advchart.tooltipactions: the SSR width table, the box 80 x 40). }
interface
uses
     tyControls.AdvanceChart.Timeline, tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Anim,
     Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.tooltipactions;
type
  { the box's text is protected: a descendant here reads it }
  TTtProbe = class(TTaProbe)
  end;

  TAdvChartTimelineTickOracleTest = class(TTestCase)
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
    procedure TestATicksLabelAndEventsAsUpstream;
    procedure TestATemplateAsUpstream;
    procedure TestNoTooltipNoDataEvents;
    procedure TestAnItemsOwnTooltipAsUpstream;
    procedure TestAClickAsUpstream;
    procedure TestAnEmphasisColourOfNullLiftsAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

procedure TAdvChartTimelineTickOracleTest.SetUp;
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
    sl.LoadFromFile(FixturePath('advchart-timeline-tick.json'));
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

procedure TAdvChartTimelineTickOracleTest.TearDown;
begin
  FLog.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartTimelineTickOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartTimelineTickOracleTest.Near(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if Abs(AGot - AWant) > 1e-6 then
    Bad(Format('%s %g, upstream %g', [AWhat, AGot, AWant]));
end;

procedure TAdvChartTimelineTickOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType = 'showtip') or (AEvent.EventType = 'hidetip') then
    FLog.Add(AEvent.EventType)
  else if (AEvent.EventType = 'mouseover') or (AEvent.EventType = 'mouseout')
    or (AEvent.EventType = 'click') then
  begin
    { a data event: the timeline's params, as the oracle picks them }
    if AEvent.HasParams then
      FLog.Add(Format('%s:%s/%s/%d/%s/%d/%s', [AEvent.EventType, AEvent.Params.ComponentType,
        AEvent.Params.ComponentSubType, AEvent.Params.ComponentIndex, AEvent.Params.Name,
        AEvent.Params.DataIndex, AEvent.Params.ValueText]))
    else
      FLog.Add(AEvent.EventType + ':-');
  end;
end;

procedure TAdvChartTimelineTickOracleTest.RunCase(const AId: string);
var
  cases, steps, ev: TJSONArray;
  cs, st, state, tip: TJSONObject;
  probe: TTtProbe;
  i, j: Integer;
  op, want: string;
  now_: Double;
  d: TJSONData;
  tv: TTyTimelineView;
  k, q: Integer;
  cwant, cgot: TTyChartColor;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  probe := TTtProbe.Create(FForm);
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
      else if op = 'leave' then probe.Leave
      else if op = 'click' then probe.Click(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1]);
      probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      { the events, by type }
      ev := st.Arrays['events'];
      Inc(FCompared);
      want := '';
      { A CLICK changes the timeline (its onclick, before the chart's
        click): the port renders the new option with the box hidden, where
        upstream keeps it and shows it again (the tooltip's click trigger)
        -- the timeline's re-render, R5-G's; the click's data event is
        compared, the box's events not }
      if op = 'click' then
        for i := FLog.Count - 1 downto 0 do
          if (FLog[i] = 'showtip') or (FLog[i] = 'hidetip') then FLog.Delete(i);
      for i := 0 to ev.Count - 1 do
        if (TJSONArray(ev.Items[i]).Strings[1] = 'showtip') or (TJSONArray(ev.Items[i]).Strings[1] = 'hidetip') then
        begin
          if op <> 'click' then want := want + TJSONArray(ev.Items[i]).Strings[1] + ',';
        end
        else
          with TJSONObject(TJSONArray(ev.Items[i]).Items[2]) do
            want := want + Format('%s:%s/%s/%d/%s/%d/%s', [TJSONArray(ev.Items[i]).Strings[1],
              Get('componentType', ''), Get('componentSubType', ''), Get('componentIndex', -1),
              Get('name', ''), Get('dataIndex', -1), Find('value').AsString]) + ',';
      FLog.Delimiter := ',';
      FLog.StrictDelimiter := True;
      if FLog.DelimitedText + ',' <> want then
        if not ((FLog.Count = 0) and (want = '')) then
          Bad(Format('events %s, upstream %s', [FLog.DelimitedText, want]));
      if op = 'click' then Continue;
      state := st.Objects['state'];
      { the ticks' fills (where the case's colours are the author's) }
      if AId = 'tl-emph-null' then
      begin
        tv := probe.TimelineViewAt(0);
        k := 0;
        for q := 0 to High(tv.Els) do
          if tv.RoleOf(q).Kind = tlrTick then
          begin
            if k < state.Arrays['fills'].Count then
            begin
              Inc(FCompared);
              if not (TyTryParseChartColor(state.Arrays['fills'].Strings[k], cwant)
                and (tv.Els[q].StyleValue('fill').Kind = avkString)
                and TyTryParseChartColor(tv.Els[q].StyleValue('fill').Str, cgot)
                and ((cwant and $FFFFFF) = (cgot and $FFFFFF))) then
                Bad(Format('tick %d fill %s, upstream %s', [k, tv.Els[q].StyleValue('fill').Str,
                  state.Arrays['fills'].Strings[k]]));
            end;
            Inc(k);
          end;
      end;
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
        { the default content: its one value, the tick's label }
        if tip.Strings['text'] = 'default' then
        begin
          if probe.TooltipFormatterText <> tip.Strings['plain'] then
            Bad(Format('the text %s, upstream %s', [probe.TooltipFormatterText, tip.Strings['plain']]));
        end
        else if probe.TooltipFormatterText <> tip.Strings['text'] then
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

procedure TAdvChartTimelineTickOracleTest.TestATicksLabelAndEventsAsUpstream;
begin
  RunCase('tl-tip');
  AssertTrue('boxes compared', FShown >= 2);
end;

procedure TAdvChartTimelineTickOracleTest.TestATemplateAsUpstream;
begin
  RunCase('tl-tip-fmt');
end;

procedure TAdvChartTimelineTickOracleTest.TestNoTooltipNoDataEvents;
begin
  RunCase('tl-tip-off');
end;

procedure TAdvChartTimelineTickOracleTest.TestAnItemsOwnTooltipAsUpstream;
begin
  RunCase('tl-tip-item');
end;

procedure TAdvChartTimelineTickOracleTest.TestAClickAsUpstream;
begin
  RunCase('tl-click');
end;

procedure TAdvChartTimelineTickOracleTest.TestAnEmphasisColourOfNullLiftsAsUpstream;
begin
  RunCase('tl-emph-null');
end;

initialization
  RegisterTest(TAdvChartTimelineTickOracleTest);
end.
