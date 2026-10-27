unit test.advchart.timelinemulti;
{$mode objfpc}{$H+}
{ SEVERAL TIMELINES [R5-G].

  Upstream gives every timeline model its own SliderTimelineView -- its own
  layout, ticks, labels, buttons, checkpoint, hover and play timer -- while
  the two actions its handlers dispatch apply to the FIRST model
  (timelineAction.ts: ecModel.getComponent('timeline')). The replay of
  tools/advchart-oracle/timeline-multi.js is
  TAdvChartTimelineOracleTest.TestSeveralTimelinesAsUpstream; this holds
  what it does not reach: a hit names the timeline it found (HdKind 10,
  HdSeries the slot) and every view's own timer due, and the keyboard's
  stops are TAdvChartComponentKeysTest's. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Timeline,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax, test.advchart.timeline;
type
  TTmProbe = class(TTlProbe)
  public
    function Target(AX, AY: Integer): TTyChartEventTarget;
  end;

  TAdvChartTimelineMultiTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTmProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    procedure NewChart;
    procedure RenderNow;
    function CaseOf(const AId: string): TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryModelHasItsView;
    procedure TestAHitNamesItsTimeline;
    procedure TestEveryViewKeepsItsOwnTimer;
    procedure TestTheOtherViewsGoWithTheirModels;
  end;

implementation

const
  T0 = 1700000000000.0;

function TTmProbe.Target(AX, AY: Integer): TTyChartEventTarget;
begin
  Result := EventTargetAt(AX, AY);
end;

function MultiPath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-timeline-multi.json';
end;

procedure TAdvChartTimelineMultiTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  FBmp := nil;
  AssertTrue('the fixture is where the suite expects it', FileExists(MultiPath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(MultiPath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartTimelineMultiTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartTimelineMultiTest.NewChart;
var m: TJSONObject;
begin
  FChart := TTmProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(m.Arrays['ratio'],
    m.Integers['firstCode']));
  FChart.SetBounds(0, 0, 600, 400);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := T0;
  FChart.TimelineNow := T0;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartTimelineMultiTest.RenderNow;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

function TAdvChartTimelineMultiTest.CaseOf(const AId: string): TJSONObject;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then Exit(cases.Objects[i]);
  Fail('no case ' + AId);
  Result := nil;
end;

procedure TAdvChartTimelineMultiTest.TestEveryModelHasItsView;
var v: TTyTimelineView; k: Integer;
begin
  NewChart;
  FChart.Option := CaseOf('m-layout').Objects['option'].AsJSON;
  RenderNow;
  AssertEquals('a view a model', 3, FChart.TimelineViewCount);
  for k := 0 to 2 do
  begin
    v := FChart.TimelineViewAt(k);
    AssertNotNull('view ' + IntToStr(k), v);
    AssertTrue('view ' + IntToStr(k) + ' shown', v.Shown);
  end;
  AssertTrue('the first is TimelineView', FChart.TimelineView = FChart.TimelineViewAt(0));
  AssertEquals('its own data', 4, FChart.TimelineViewAt(0).Count);
  AssertEquals('its own data', 3, FChart.TimelineViewAt(1).Count);
  AssertEquals('its own index', 1, FChart.TimelineViewAt(1).CurrentIndex, 0);
  AssertEquals('its own index', 0, FChart.TimelineViewAt(2).CurrentIndex, 0);
  AssertTrue('no view past the last', FChart.TimelineViewAt(3) = nil);
  AssertTrue('nor before the first', FChart.TimelineViewAt(-1) = nil);
end;

procedure TAdvChartTimelineMultiTest.TestAHitNamesItsTimeline;
var
  c: TJSONObject;
  st: TJSONArray;
  t1, t0: TTyChartEventTarget;
begin
  NewChart;
  c := CaseOf('m-click');
  FChart.Option := c.Objects['option'].AsJSON;
  RenderNow;
  st := c.Arrays['steps'];
  { step 0: the second timeline's tick 2; step 2: the first's next }
  AssertEquals(1, st.Objects[0].Integers['tl']);
  t1 := FChart.Target(st.Objects[0].Integers['x'], st.Objects[0].Integers['y']);
  AssertEquals('a timeline element', 10, t1.HdKind);
  AssertEquals('the second timeline''s', 1, t1.HdSeries);
  AssertEquals('found in that view''s render', FChart.TimelineViewAt(1).Gen, t1.HdGen);
  AssertTrue('the tick', FChart.TimelineViewAt(1).RoleOf(t1.HdRow).Kind = tlrTick);
  AssertTrue('the third tick', FChart.TimelineViewAt(1).RoleOf(t1.HdRow).Value = 2);
  AssertTrue(st.Objects[2].Find('tl') = nil);
  t0 := FChart.Target(st.Objects[2].Integers['x'], st.Objects[2].Integers['y']);
  AssertEquals(10, t0.HdKind);
  AssertEquals('the first timeline''s', 0, t0.HdSeries);
  AssertTrue('its next button', FChart.TimelineViewAt(0).RoleOf(t0.HdRow).Kind = tlrNext);
  AssertTrue('the two are different targets', t0.Id <> t1.Id);
end;

procedure TAdvChartTimelineMultiTest.TestEveryViewKeepsItsOwnTimer;
begin
  NewChart;
  FChart.Option := CaseOf('m-autoplay-race').Objects['option'].AsJSON;
  RenderNow;
  AssertEquals('the first''s interval', 1000, FChart.TimelineDueAt(0) - T0, 0);
  AssertEquals('the second''s', 900, FChart.TimelineDueAt(1) - T0, 0);
  AssertEquals('TimelineDue is the first''s', 1000, FChart.TimelineDue - T0, 0);
  AssertTrue('no third', IsNan(FChart.TimelineDueAt(2)));
  { the second's fires first: its own index (1) rewound sets the first's;
    the render sets every timer again from then }
  FChart.AnimNow := T0 + 900;
  FChart.TimelineNow := T0 + 900;
  FChart.TimelineTick(T0 + 900);
  RenderNow;
  AssertEquals('the first model', 0, FChart.TimelineViewAt(0).CurrentIndex, 0);
  AssertEquals('the second keeps its own', 1, FChart.TimelineViewAt(1).CurrentIndex, 0);
  AssertEquals('the first''s timer set again', 1900, FChart.TimelineDueAt(0) - T0, 0);
  AssertEquals('the second''s', 1800, FChart.TimelineDueAt(1) - T0, 0);
end;

procedure TAdvChartTimelineMultiTest.TestTheOtherViewsGoWithTheirModels;
var v1: TTyTimelineView;
begin
  NewChart;
  FChart.Option := CaseOf('m-replace').Objects['option'].AsJSON;
  RenderNow;
  v1 := FChart.TimelineViewAt(1);
  AssertNotNull(v1);
  AssertFalse('the second plays', IsNan(FChart.TimelineDueAt(1)));
  FChart.SetOption(CaseOf('m-replace').Arrays['steps'].Objects[1].Objects['option'].AsJSON,
    '{"notMerge":true}');
  RenderNow;
  AssertEquals('one view left', 1, FChart.TimelineViewCount);
  AssertTrue('and its timer', IsNan(FChart.TimelineDueAt(1)));
end;

initialization
  RegisterTest(TAdvChartTimelineMultiTest);
end.
