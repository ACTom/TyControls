unit test.advchart.chordselect;
{$mode objfpc}{$H+}
{ A CHORD SERIES' selectchanged, HELD TO UPSTREAM [F3b].

  tools/advchart-oracle/chord-select.js dispatches select, toggleSelect and
  unselect on chord series (one beside a pie) in the real ECharts 6.1 build
  and records every event each action publishes. A chord's data is linked
  node and edge data, so getAllSelectedIndices lists the selection once per
  data -- 'node' and 'edge' -- and an edge selected by an action lists its
  own index among the nodes'. This replays the actions through the control
  and compares the events. }
interface
uses Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms,
     tyControls.Controller,
     tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart;
type
  TCsProbe = class(TTyAdvanceChart)
  public
    Got: TStringList;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartChordSelectOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot: TJSONData;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSelectChangedListsAsUpstream;
  end;

implementation

procedure TCsProbe.OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType = 'select') or (AEvent.EventType = 'unselect')
    or (AEvent.EventType = 'toggleselect') or (AEvent.EventType = 'selectchanged') then
    Got.Add(AEvent.EventType + #1 + AEvent.Payload);
end;

procedure TAdvChartChordSelectOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-chord-select.json');
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartChordSelectOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

{ upstream's object against the port's text: the same JSON, keys in any
  order }
function SameJson(A, B: TJSONData): Boolean;
var i: Integer; d: TJSONData;
begin
  Result := False;
  if (A = nil) or (B = nil) then Exit(A = B);
  if A.JSONType <> B.JSONType then Exit;
  case A.JSONType of
    jtObject:
      begin
        if A.Count <> B.Count then Exit;
        for i := 0 to A.Count - 1 do
        begin
          d := TJSONObject(B).Find(TJSONObject(A).Names[i]);
          if not SameJson(A.Items[i], d) then Exit;
        end;
      end;
    jtArray:
      begin
        if A.Count <> B.Count then Exit;
        for i := 0 to A.Count - 1 do
          if not SameJson(A.Items[i], B.Items[i]) then Exit;
      end;
    jtNumber: if A.AsFloat <> B.AsFloat then Exit;
  else
    if A.AsJSON <> B.AsJSON then Exit;
  end;
  Result := True;
end;

procedure TAdvChartChordSelectOracleTest.TestTheSelectChangedListsAsUpstream;
var
  cases, steps, evs: TJSONArray;
  cs, st, e: TJSONObject;
  c, k, j, n, bad: Integer;
  chart: TCsProbe;
  got: TJSONData;
  typ, pay, report: string;
  p: Integer;
  bmp: TBitmap;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  n := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    chart := TCsProbe.Create(FForm);
    chart.Got := TStringList.Create;
    try
      chart.Parent := FForm;
      chart.Controller := FCtl;
      chart.SetBounds(0, 0, 400, 300);
      chart.OnChartEvent := @chart.OnEvent;
      chart.SetOption(cs.Objects['option'].AsJSON, True);
      bmp := TBitmap.Create;
      try
        bmp.SetSize(400, 300);
        chart.RenderTo(bmp.Canvas, Rect(0, 0, 400, 300), 96);
      finally
        bmp.Free;
      end;
      steps := cs.Arrays['steps'];
      for k := 0 to steps.Count - 1 do
      begin
        st := steps.Objects[k];
        chart.Got.Clear;
        chart.DispatchAction(st.Objects['action'].AsJSON);
        evs := st.Arrays['events'];
        Inc(n);
        if chart.Got.Count <> evs.Count then
        begin
          Inc(bad);
          report := report + Format('%s step %d: %d events, upstream %d (%s)', [cs.Strings['id'],
            k, chart.Got.Count, evs.Count, chart.Got.CommaText]) + LineEnding;
          Continue;
        end;
        for j := 0 to evs.Count - 1 do
        begin
          e := evs.Objects[j];
          p := Pos(#1, chart.Got[j]);
          typ := Copy(chart.Got[j], 1, p - 1);
          pay := Copy(chart.Got[j], p + 1, MaxInt);
          Inc(n);
          if typ <> e.Strings['type'] then
          begin
            Inc(bad);
            report := report + Format('%s step %d event %d: %s, upstream %s', [cs.Strings['id'],
              k, j, typ, e.Strings['type']]) + LineEnding;
            Continue;
          end;
          if typ <> 'selectchanged' then Continue;
          got := GetJSON(pay);
          try
            if not SameJson(e.Objects['payload'].Arrays['selected'],
              TJSONObject(got).Find('selected')) then
            begin
              Inc(bad);
              report := report + Format('%s step %d: selected %s, upstream %s', [cs.Strings['id'], k,
                TJSONObject(got).Find('selected').AsJSON,
                e.Objects['payload'].Arrays['selected'].AsJSON]) + LineEnding;
            end;
            if TJSONObject(got).Get('fromAction', '') <> e.Objects['payload'].Strings['fromAction'] then
            begin
              Inc(bad);
              report := report + cs.Strings['id'] + ': fromAction differs' + LineEnding;
            end;
          finally
            got.Free;
          end;
        end;
      end;
    finally
      chart.Got.Free;
      chart.Free;
    end;
  end;
  if bad > 0 then Fail(Format('%d of %d differ from upstream:%s%s', [bad, n, LineEnding, report]));
  AssertTrue('steps compared', n >= 8);
end;

initialization
  RegisterTest(TAdvChartChordSelectOracleTest);
end.
