unit test.advchart.edgesinteract;
{$mode objfpc}{$H+}
{ R5-G, THE INTERACTION EDGE CASES (spec section 244).

  tools/advchart-oracle/edges-interact.js records, on ECharts 6.1: the
  dragNode payloads a drag on a sankey node dispatches (seriesId, the keys in
  order); which drags pan a sankey whose roamTrigger is 'selfRect' (the main
  group's own box); what a global brush area selects among bars on a polar
  (a rect or a polygon every one, a lineX none); and that a click which
  drills a sunburst, zooms a treemap or folds a tree brings a brushselected
  event. The replay drives the control's own pointer and actions. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart.Graph,
     tyControls.AdvanceChart,
     test.advchart.graphic;
type
  TEiProbe = class(TGfxProbe)
  public
    Payloads: TStringList;
    BrushSel, Roams: Integer;
    LastSel: string;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OnLog(Sender: TObject; const AEvent: TTyChartEvent);
    procedure OnBrush(Sender: TObject; const AEvent: TTyChartEvent);
    procedure OnRoam(Sender: TObject; const APayload: TTyGraphRoamPayload);
  end;

  TAdvChartEdgesInteractOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TEiProbe;
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure RenderNow;
    procedure Load(ACase: TJSONObject);
    procedure Finish(const AWhat: string);
    function CaseOf(const AId: string): TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestADragNodeNamesItsSeriesById;
    procedure TestASelfRectTriggerIsTheGroupsOwnBox;
    procedure TestABrushSelectsPolarBarsAsUpstream;
    procedure TestADrillingClickRunsTheBrush;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-edges-interact.json';
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

constructor TEiProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Payloads := TStringList.Create;
end;

destructor TEiProbe.Destroy;
begin
  Payloads.Free;
  inherited Destroy;
end;

procedure TEiProbe.OnLog(Sender: TObject; const AEvent: TTyChartEvent);
begin
  Payloads.Add(AEvent.Payload);
end;

procedure TEiProbe.OnBrush(Sender: TObject; const AEvent: TTyChartEvent);
begin
  Inc(BrushSel);
  LastSel := AEvent.Payload;
end;

procedure TEiProbe.OnRoam(Sender: TObject; const APayload: TTyGraphRoamPayload);
begin
  Inc(Roams);
end;

procedure TAdvChartEdgesInteractOracleTest.SetUp;
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

procedure TAdvChartEdgesInteractOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartEdgesInteractOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 60 then FReport := FReport + LineEnding + '  ' + FWhere + ': ' + AWhat;
end;

procedure TAdvChartEdgesInteractOracleTest.Finish(const AWhat: string);
begin
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(AWhat + ' (' + IntToStr(FCompared) + ' compared)' + FReport, 0, FBad);
end;

procedure TAdvChartEdgesInteractOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartEdgesInteractOracleTest.Load(ACase: TJSONObject);
begin
  FWhere := ACase.Strings['id'];
  FreeAndNil(FChart);
  FChart := TEiProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, ACase.Integers['W'], ACase.Integers['H']);
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  AssertEquals(FWhere + ' parses', '', FChart.OptionError);
  RenderNow;
end;

function TAdvChartEdgesInteractOracleTest.CaseOf(const AId: string): TJSONObject;
var all: TJSONArray; i: Integer;
begin
  Result := nil;
  all := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to all.Count - 1 do
    if all.Objects[i].Strings['id'] = AId then Exit(all.Objects[i]);
  Fail('no case ' + AId);
end;

{ the payloads by key, in order; the seriesId with the NULs fpjson drops
  dropped on both sides }
procedure TAdvChartEdgesInteractOracleTest.TestADragNodeNamesItsSeriesById;
var
  c, want: TJSONObject;
  d: TJSONArray;
  x, y, k, j: Integer;
  p: TJSONData;
  keys, wkeys: string;
begin
  c := CaseOf('sd-drag');
  Load(c);
  FChart.ChartOn('dragnode', @FChart.OnLog);
  x := c.Arrays['press'].Integers[0];
  y := c.Arrays['press'].Integers[1];
  FChart.Down(x, y);
  for k := 0 to c.Arrays['moves'].Count - 1 do
  begin
    Inc(x, c.Arrays['moves'].Arrays[k].Integers[0]);
    Inc(y, c.Arrays['moves'].Arrays[k].Integers[1]);
    FChart.Move(x, y);
    RenderNow;
  end;
  FChart.Up(x, y);
  d := c.Arrays['dispatched'];
  Inc(FCompared);
  if FChart.Payloads.Count <> d.Count then
    Bad(Format('%d dragNode upstream, %d here', [d.Count, FChart.Payloads.Count]));
  for k := 0 to Min(d.Count, FChart.Payloads.Count) - 1 do
  begin
    want := d.Objects[k];
    p := GetJSON(FChart.Payloads[k]);
    try
      keys := '';
      for j := 0 to TJSONObject(p).Count - 1 do keys := keys + TJSONObject(p).Names[j] + ',';
      wkeys := '';
      for j := 0 to want.Arrays['keys'].Count - 1 do wkeys := wkeys + want.Arrays['keys'].Strings[j] + ',';
      Inc(FCompared);
      if keys <> wkeys then Bad(Format('payload %d keys %s upstream, %s here', [k, wkeys, keys]));
      Inc(FCompared);
      if (TJSONObject(p).Find('seriesId') = nil)
        or (TJSONObject(p).Strings['seriesId'] <> StringReplace(want.Strings['seriesId'], '<NUL>', '', [rfReplaceAll])) then
        Bad(Format('payload %d seriesId %s upstream', [k, want.Strings['seriesId']]));
    finally
      p.Free;
    end;
  end;
  Finish('the dragNode payloads');
end;

{ each probe: a drag from it pans or not, as upstream's }
procedure TAdvChartEdgesInteractOracleTest.TestASelfRectTriggerIsTheGroupsOwnBox;
var
  c, pr: TJSONObject;
  k, x, y: Integer;
  panned: Boolean;
begin
  c := CaseOf('st-self');
  Load(c);
  AssertTrue('the dragNode', FChart.DispatchAction(Format(
    '{"type":"dragNode","seriesIndex":0,"dataIndex":3,"localX":%s,"localY":0.2}',
    [FloatToStr(c.Floats['localD'], DefaultFormatSettings)])));
  RenderNow;
  FChart.OnSankeyRoam := @FChart.OnRoam;
  for k := 0 to c.Arrays['probes'].Count - 1 do
  begin
    pr := c.Arrays['probes'].Objects[k];
    x := pr.Integers['x'];
    y := pr.Integers['y'];
    FChart.Roams := 0;
    FChart.Down(x, y);
    FChart.Move(x + 20, y + 5);
    FChart.Up(x + 20, y + 5);
    panned := FChart.Roams > 0;
    if panned then
      FChart.DispatchAction('{"type":"sankeyRoam","seriesIndex":0,"dx":-20,"dy":-5}');
    RenderNow;
    Inc(FCompared);
    if panned <> pr.Booleans['panned'] then
      Bad(Format('a drag from %d,%d: pans %s upstream', [x, y, BoolToStr(pr.Booleans['panned'], True)]));
  end;
  Finish('the sankey trigger');
end;

procedure TAdvChartEdgesInteractOracleTest.TestABrushSelectsPolarBarsAsUpstream;
const cIds: array[0..2] of string = ('pb-rect', 'pb-linex', 'pb-polygon');
var
  c: TJSONObject;
  i, k, j: Integer;
  ev, ws, hs: TJSONData;
  want, got: string;

  function Sel(AData: TJSONData): string;
  var q, r: Integer; s: TJSONObject;
  begin
    Result := '';
    for q := 0 to TJSONArray(AData).Count - 1 do
    begin
      s := TJSONArray(AData).Objects[q];
      Result := Result + IntToStr(s.Integers['seriesIndex']) + ':';
      for r := 0 to s.Arrays['dataIndex'].Count - 1 do
        Result := Result + IntToStr(s.Arrays['dataIndex'].Integers[r]) + ' ';
      Result := Result + '| ';
    end;
  end;

begin
  for i := 0 to High(cIds) do
  begin
    c := CaseOf(cIds[i]);
    Load(c);
    FChart.ChartOn('brushselected', @FChart.OnBrush);
    FChart.BrushSel := 0;
    AssertTrue('the brush', FChart.DispatchAction('{"type":"brush","areas":'
      + c.Arrays['areas'].AsJSON + '}'));
    RenderNow;
    Inc(FCompared);
    if FChart.BrushSel = 0 then
    begin
      Bad('no brushselected');
      Continue;
    end;
    want := Sel(c.Arrays['selected']);
    ev := GetJSON(FChart.LastSel);
    try
      hs := TJSONObject(ev).Arrays['batch'].Objects[0].Arrays['selected'];
      got := Sel(hs);
    finally
      ev.Free;
    end;
    if want <> got then Bad('selected ' + want + 'upstream, ' + got + 'here');
  end;
  Finish('the polar brush');
end;

procedure TAdvChartEdgesInteractOracleTest.TestADrillingClickRunsTheBrush;
const cIds: array[0..2] of string = ('gb-sunburst', 'gb-treemap', 'gb-tree');
var
  c: TJSONObject;
  i, k, n, x, y: Integer;
begin
  for i := 0 to High(cIds) do
  begin
    c := CaseOf(cIds[i]);
    Load(c);
    FChart.ChartOn('brushselected', @FChart.OnBrush);
    FChart.BrushSel := 0;
    x := c.Arrays['click'].Integers[0];
    y := c.Arrays['click'].Integers[1];
    FChart.Move(x, y);
    FChart.Down(x, y);
    FChart.Up(x, y);
    RenderNow;
    n := 0;
    for k := 0 to c.Arrays['events'].Count - 1 do
      if c.Arrays['events'].Strings[k] = 'brushselected' then Inc(n);
    Inc(FCompared);
    if FChart.BrushSel <> n then
      Bad(Format('%d brushselected upstream, %d here', [n, FChart.BrushSel]));
  end;
  Finish('the drilling clicks');
end;

initialization
  RegisterTest(TAdvChartEdgesInteractOracleTest);
end.
