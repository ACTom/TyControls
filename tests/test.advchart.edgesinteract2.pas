unit test.advchart.edgesinteract2;
{$mode objfpc}{$H+}
{ R5-G, THE INTERACTION EDGE CASES, SECOND ROUND (spec section 244).

  tools/advchart-oracle/edges-interact2.js records, on ECharts 6.1: the x
  axis' proxy window after dataZoom actions whose ends differ in kind, name
  categories or leave an end out; the window a toolbox dataZoom select gives
  when the host dataZoom's minValueSpan / maxValueSpan / minSpan restrict it;
  whether a drag starts a graph's roam or a parallel axis' area select when
  it starts on a series drawn higher (onIrrelevantElement); and what a
  brush selects of a jittered scatter. The replay drives the control's own
  actions and pointer. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart.Graph, tyControls.AdvanceChart.DataZoom,
     tyControls.AdvanceChart.Series,
     tyControls.AdvanceChart,
     test.advchart.graphic;
type
  TEi2Probe = class(TGfxProbe)
  public
    Roams, Selects, BrushSel: Integer;
    LastSel: string;
    procedure OnRoam(Sender: TObject; const APayload: TTyGraphRoamPayload);
    procedure OnSel(Sender: TObject; const AEvent: TTyChartEvent);
    procedure OnBrush(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartEdgesInteract2OracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TEi2Probe;
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure RenderNow;
    procedure Load(ACase: TJSONObject);
    procedure Finish(const AWhat: string);
    procedure CheckWindow(const AWhat: string; AWant: TJSONObject);
    function Cases(const AGroup: string): TJSONArray;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestADataZoomActionSetsEachEndAsWritten;
    procedure TestAToolboxSelectKeepsToTheHostsSpans;
    procedure TestAHigherSeriesIsIrrelevantToARoamAndAPanel;
    procedure TestABrushSelectsTheJitteredPoints;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-edges-interact2.json';
end;

function LoadText(const APath: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Txt(V: Double): string;
begin
  Result := FloatToStr(V, DefaultFormatSettings);
end;

function Near(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Abs(A - B) <= 1e-9 * Max(Double(1), Abs(B));
end;

procedure TEi2Probe.OnRoam(Sender: TObject; const APayload: TTyGraphRoamPayload);
begin
  Inc(Roams);
end;

procedure TEi2Probe.OnSel(Sender: TObject; const AEvent: TTyChartEvent);
begin
  Inc(Selects);
end;

procedure TEi2Probe.OnBrush(Sender: TObject; const AEvent: TTyChartEvent);
begin
  Inc(BrushSel);
  LastSel := AEvent.Payload;
end;

procedure TAdvChartEdgesInteract2OracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := GetJSON(LoadText(FixturePath));
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartEdgesInteract2OracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartEdgesInteract2OracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 60 then FReport := FReport + LineEnding + '  ' + FWhere + ': ' + AWhat;
end;

procedure TAdvChartEdgesInteract2OracleTest.Finish(const AWhat: string);
begin
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(AWhat + ' (' + IntToStr(FCompared) + ' compared)' + FReport, 0, FBad);
end;

procedure TAdvChartEdgesInteract2OracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartEdgesInteract2OracleTest.Load(ACase: TJSONObject);
begin
  FWhere := ACase.Strings['id'];
  FreeAndNil(FChart);
  FChart := TEi2Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  { [R7-AB] every clock the chart reads stands with the test's, not the machine's }
  FChart.DataZoomNow := 1000;
  FChart.BrushNow := 1000;
  FChart.ParallelExpandNow := 1000;
  FChart.TimelineNow := 1000;
  FChart.SetBounds(0, 0, ACase.Integers['W'], ACase.Integers['H']);
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  AssertEquals(FWhere + ' parses', '', FChart.OptionError);
  RenderNow;
end;

function TAdvChartEdgesInteract2OracleTest.Cases(const AGroup: string): TJSONArray;
var all: TJSONArray; i: Integer;
begin
  Result := TJSONArray.Create;
  all := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to all.Count - 1 do
    if all.Objects[i].Strings['group'] = AGroup then
      Result.Add(all.Objects[i].Clone);
end;

{ the x axis' window against upstream's proxy window, value and percent }
procedure TAdvChartEdgesInteract2OracleTest.CheckWindow(const AWhat: string; AWant: TJSONObject);
var
  z: TTyAxisZoom;
  w: TTyDzWindow;
  host, k: Integer;
  wv, wp: TJSONArray;
begin
  Inc(FCompared);
  if not FChart.AxisZoom('xAxis', 0, z, w, host) then
  begin
    Bad(AWhat + ': no window');
    Exit;
  end;
  wv := AWant.Objects['value'].Arrays['hex'];
  wp := AWant.Objects['percent'].Arrays['hex'];
  for k := 0 to 1 do
  begin
    if not Near(w.Value[k], FromHex(wv.Strings[k])) then
      Bad(Format('%s: value[%d] %s upstream, %s here', [AWhat, k,
        AWant.Objects['value'].Arrays['text'].Strings[k], Txt(w.Value[k])]));
    if not Near(w.Percent[k], FromHex(wp.Strings[k])) then
      Bad(Format('%s: percent[%d] %s upstream, %s here', [AWhat, k,
        AWant.Objects['percent'].Arrays['text'].Strings[k], Txt(w.Percent[k])]));
  end;
end;

procedure TAdvChartEdgesInteract2OracleTest.TestADataZoomActionSetsEachEndAsWritten;
var
  cs: TJSONArray;
  c: TJSONObject;
  i, k: Integer;
begin
  cs := Cases('dz-action');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      Load(c);
      for k := 0 to c.Arrays['actions'].Count - 1 do
      begin
        AssertTrue(FWhere + ' the action', FChart.DispatchAction(c.Arrays['actions'].Objects[k].AsJSON));
        RenderNow;
        CheckWindow('after action ' + IntToStr(k), c.Arrays['after'].Objects[k]);
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('the dataZoom actions');
end;

procedure TAdvChartEdgesInteract2OracleTest.TestAToolboxSelectKeepsToTheHostsSpans;
var
  cs, dr: TJSONArray;
  c: TJSONObject;
  i, x0, y0, x1, y1: Integer;
begin
  cs := Cases('tb-span');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      Load(c);
      AssertTrue(FWhere + ' the cursor', FChart.DispatchAction(
        '{"type":"takeGlobalCursor","key":"dataZoomSelect","dataZoomSelectActive":true}'));
      RenderNow;
      dr := c.Arrays['drag'];
      x0 := dr.Arrays[0].Integers[0];
      y0 := dr.Arrays[0].Integers[1];
      x1 := dr.Arrays[1].Integers[0];
      y1 := dr.Arrays[1].Integers[1];
      FChart.Down(x0, y0);
      FChart.Move((x0 + x1) div 2, (y0 + y1) div 2);
      FChart.Move(x1, y1);
      FChart.Up(x1, y1);
      RenderNow;
      CheckWindow('after the select', c.Objects['after']);
    end;
  finally
    cs.Free;
  end;
  Finish('the toolbox selects');
end;

procedure TAdvChartEdgesInteract2OracleTest.TestAHigherSeriesIsIrrelevantToARoamAndAPanel;
var
  cs, rs: TJSONArray;
  c, r: TJSONObject;
  i, k, x, y, x1, y1: Integer;
  got: Boolean;
begin
  cs := Cases('irrelevant');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      Load(c);
      FChart.OnGraphRoam := @FChart.OnRoam;
      FChart.ChartOn('axisareaselected', @FChart.OnSel);
      rs := c.Arrays['results'];
      for k := 0 to rs.Count - 1 do
      begin
        r := rs.Objects[k];
        x := r.Arrays['at'].Integers[0];
        y := r.Arrays['at'].Integers[1];
        Inc(FCompared);
        if r.Find('roamed') <> nil then
        begin
          FChart.Roams := 0;
          FChart.Down(x, y);
          FChart.Move(x + 20, y + 10);
          FChart.Move(x + 40, y + 20);
          FChart.Up(x + 40, y + 20);
          got := FChart.Roams > 0;
          if got then
            FChart.DispatchAction('{"type":"graphRoam","seriesIndex":0,"dx":-40,"dy":-20}');
          RenderNow;
          if got <> r.Booleans['roamed'] then
            Bad(Format('a drag from %d,%d: roams %s upstream', [x, y, BoolToStr(r.Booleans['roamed'], True)]));
        end
        else
        begin
          x1 := r.Arrays['to'].Integers[0];
          y1 := r.Arrays['to'].Integers[1];
          FChart.Selects := 0;
          FChart.Down(x, y);
          FChart.Move((x + x1) div 2, (y + y1) div 2);
          FChart.Move(x1, y1);
          FChart.Up(x1, y1);
          RenderNow;
          got := FChart.Selects > 0;
          if got <> r.Booleans['selected'] then
            Bad(Format('an area select from %d,%d: starts %s upstream', [x, y,
              BoolToStr(r.Booleans['selected'], True)]));
        end;
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('the irrelevant elements');
end;

procedure TAdvChartEdgesInteract2OracleTest.TestABrushSelectsTheJitteredPoints;
var
  cs, rg, sel: TJSONArray;
  c: TJSONObject;
  i, k: Integer;
  ev: TJSONData;
  want, got, areas: string;
begin
  cs := Cases('jitter-brush');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      Load(c);
      FChart.ChartOn('brushselected', @FChart.OnBrush);
      rg := c.Arrays['range'];
      areas := Format('{"type":"brush","areas":[{"brushType":"rect","range":[[%s,%s],[%s,%s]]}]}',
        [FloatToStr(FromHex(rg.Objects[0].Arrays['hex'].Strings[0]), DefaultFormatSettings),
         FloatToStr(FromHex(rg.Objects[0].Arrays['hex'].Strings[1]), DefaultFormatSettings),
         FloatToStr(FromHex(rg.Objects[1].Arrays['hex'].Strings[0]), DefaultFormatSettings),
         FloatToStr(FromHex(rg.Objects[1].Arrays['hex'].Strings[1]), DefaultFormatSettings)]);
      AssertTrue(FWhere + ' the brush', FChart.DispatchAction(areas));
      RenderNow;
      Inc(FCompared);
      if FChart.BrushSel = 0 then
      begin
        Bad('no brushselected');
        Continue;
      end;
      want := '';
      for k := 0 to c.Arrays['selected'].Count - 1 do
        want := want + IntToStr(c.Arrays['selected'].Integers[k]) + ' ';
      ev := GetJSON(FChart.LastSel);
      try
        sel := TJSONObject(ev).Arrays['batch'].Objects[0].Arrays['selected'].Objects[0].Arrays['dataIndex'];
        got := '';
        for k := 0 to sel.Count - 1 do got := got + IntToStr(sel.Integers[k]) + ' ';
      finally
        ev.Free;
      end;
      if want <> got then Bad('selected ' + want + 'upstream, ' + got + 'here');
    end;
  finally
    cs.Free;
  end;
  Finish('the jittered brush');
end;

initialization
  RegisterTest(TAdvChartEdgesInteract2OracleTest);
end.
