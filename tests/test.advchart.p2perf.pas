unit test.advchart.p2perf;
{$mode objfpc}{$H+}
{ [P2] The second half of the performance work: what may not change while a
  frame gets cheaper.

  TAdvChartStPatchTest: a frame whose states alone changed puts the list back
  to what the last build's state writes went over and writes them again
  (StPatchList) instead of building the whole list. Two charts on one option
  take the same pointer sweep, one patching and one building (the test
  switch TyAdvChartStPatchForTest); after every frame the two lists hold the
  same elements (TyElementsSame) and the two frames the same pixels -- on the
  whole-layer path and the dirty-rect one. The tooltip is off: its fade runs
  on the wall clock and the two charts would draw it a moment apart.

  TAdvChartPaintJournalTest: the paint list's journal on its own.

  TAdvChartStDeclareMemoTest: a sync's declarations read the three state
  styles once for the rows of a series with no object of their own; a row
  with its own object reads its own, and the next plain row the series'. }
interface

uses Classes, SysUtils, Math, Types, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.DirtyRect, tyControls.AdvChart.Geo,
     tyControls.AdvanceChart;

type
  TP2Probe = class(TTyAdvanceChart)
  public
    procedure Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Whole(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Hover(AX, AY: Integer);
    procedure SetNow(AMs: Double);
    function List: TTyPaintList;
  end;

  TAdvChartStPatchTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    procedure SetUp; override;
    procedure TearDown; override;
    { the sweep over AOption; answers how many frames patched }
    function Sweep(const AOption: string; ADirty, AWhole: Boolean;
      AStep: Integer): Integer;
  published
    procedure TestAHoveredBarAndItsBlurPatchAsABuildWould;
    procedure TestASymbolLineAndItsMarkersPatchAsABuildWould;
    procedure TestAPieAGraphAndATreemapPatchAsABuildWould;
    procedure TestAProgressiveScatterRedrawsItsChunks;
    procedure TestTheDirtyRectPathPatchesAsABuildWould;
    procedure TestRenderToPatchesAsABuildWould;
    procedure TestAPolarLinePatchesAsABuildWould;
    procedure TestAGeoAndAMapSeriesAsABuildWould;
    procedure TestNoStateChangeNoPatch;
  end;

  TAdvChartPaintJournalTest = class(TTestCase)
  private
    function El(AZ2: Integer; const AText: string): TTyChartElement;
  published
    procedure TestARewindPutsBackWhatTheRecordedWritesWentOver;
    procedure TestAWriteOutsideTheRecordingIsTheBuildsOwn;
    procedure TestAWriteAfterTheSessionTaintsIt;
    procedure TestClearForgetsTheJournal;
    procedure TestAnElementAddedInTheSessionIsJournaledToo;
    procedure TestARecordedWriteAfterTheSessionTaintsItToo;
    procedure TestARefPastTheEndIsTheSharedEmptyElement;
  end;

  TAdvChartStDeclareMemoTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TP2Probe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw;
    function FillOfRow(ASeries, ARow: Integer): TTyChartColor;
    procedure HoverRow(ASeries, ARow: Integer);
  published
    procedure TestARowWithItsOwnEmphasisDoesNotLendItToTheNext;
    procedure TestTwoSeriesKeepTheirOwnEmphasis;
  end;

implementation

{ ==================== the probe ==================== }

procedure TP2Probe.Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

procedure TP2Probe.Whole(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TP2Probe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TP2Probe.SetNow(AMs: Double);
begin
  AnimNow := AMs;
end;

function TP2Probe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

{ ==================== the patch against a build ==================== }

procedure TAdvChartStPatchTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
end;

procedure TAdvChartStPatchTest.TearDown;
begin
  TyAdvChartStPatchForTest(True);
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function PixelsDiffer(A, B: TBitmap): Integer;
var y, x: Integer; pa, pb: PByte;
begin
  Result := 0;
  for y := 0 to A.Height - 1 do
  begin
    pa := A.ScanLine[y];
    pb := B.ScanLine[y];
    for x := 0 to A.Width * 3 - 1 do
      if pa[x] <> pb[x] then Inc(Result);
  end;
end;

function TAdvChartStPatchTest.Sweep(const AOption: string; ADirty, AWhole: Boolean;
  AStep: Integer): Integer;
const
  W = 400;
  H = 300;
var
  ca, cb: TP2Probe;
  ba, bb: TBitmap;
  x, y, frame, i, p0: Integer;
  where: string;

  procedure Paint(AChart: TP2Probe; ABmp: TBitmap; APatch: Boolean);
  begin
    TyAdvChartStPatchForTest(APatch);
    if AWhole then AChart.Whole(ABmp.Canvas, Rect(0, 0, W, H), 96)
    else AChart.Layered(ABmp.Canvas, Rect(0, 0, W, H), 96);
    TyAdvChartStPatchForTest(True);
  end;

begin
  ca := TP2Probe.Create(FForm);
  cb := TP2Probe.Create(FForm);
  ba := TBitmap.Create;
  bb := TBitmap.Create;
  try
    ba.PixelFormat := pf24bit;
    ba.SetSize(W, H);
    bb.PixelFormat := pf24bit;
    bb.SetSize(W, H);
    for i := 0 to 1 do
    begin
      if i = 0 then
      begin
        ca.Parent := FForm;
        ca.Controller := FCtl;
        ca.AnimationMode := camOff;
        ca.UseDirtyRect := ADirty;
        ca.SetBounds(0, 0, W, H);
        ca.SetNow(1000);
        ca.Option := AOption;
      end
      else
      begin
        cb.Parent := FForm;
        cb.Controller := FCtl;
        cb.AnimationMode := camOff;
        cb.UseDirtyRect := ADirty;
        cb.SetBounds(0, 0, W, H);
        cb.SetNow(1000);
        cb.Option := AOption;
      end;
    end;
    Paint(ca, ba, True);
    Paint(cb, bb, False);
    p0 := TyAdvChartStPatchesForTest;
    frame := 0;
    y := 10;
    while y < H do
    begin
      x := 5;
      while x < W + 10 do
      begin
        Inc(frame);
        ca.SetNow(1000 + frame * 40);
        cb.SetNow(1000 + frame * 40);
        TyAdvChartStPatchForTest(True);
        ca.Hover(x, y);
        Paint(ca, ba, True);
        TyAdvChartStPatchForTest(False);
        cb.Hover(x, y);
        Paint(cb, bb, False);
        where := Format(' at (%d, %d)', [x, y]);
        AssertTrue('the lists are there' + where, (ca.List <> nil) and (cb.List <> nil));
        AssertEquals('as many elements' + where, cb.List.Count, ca.List.Count);
        for i := 0 to ca.List.Count - 1 do
          if not TyElementsSame(ca.List.Element(i), cb.List.Element(i)) then
            Fail(Format('element %d differs from the build''s%s', [i, where]));
        AssertEquals('the same pixels' + where, 0, PixelsDiffer(ba, bb));
        Inc(x, AStep);
      end;
      Inc(y, AStep);
    end;
    Result := TyAdvChartStPatchesForTest - p0;
  finally
    ba.Free;
    bb.Free;
    ca.Free;
    cb.Free;
  end;
end;

const
  cNoTip = 'tooltip: { show: false }, animation: false, ';

procedure TAdvChartStPatchTest.TestAHoveredBarAndItsBlurPatchAsABuildWould;
var n: Integer;
begin
  n := Sweep('{ ' + cNoTip + 'legend: {}, xAxis: { data: [''a'', ''b'', ''c'', ''d''] }, yAxis: {},'
    + ' series: [{ name: ''one'', type: ''bar'', data: [5, 20, 36, 10],'
    + '   emphasis: { focus: ''series'', itemStyle: { color: ''#c00'' } },'
    + '   label: { show: true }, select: { itemStyle: { borderWidth: 3 } } },'
    + ' { name: ''two'', type: ''bar'', data: [8, 12, 18, 30], emphasis: { focus: ''self'' } }] }',
    False, False, 23);
  AssertTrue('frames were patched, not built', n > 3);
end;

procedure TAdvChartStPatchTest.TestASymbolLineAndItsMarkersPatchAsABuildWould;
var n: Integer;
begin
  { a markPoint / markLine are written by StSyncMarks after the legend and
    the markers are added: their journal entries are the states', not the
    construction's }
  n := Sweep('{ ' + cNoTip + 'xAxis: { data: [''a'', ''b'', ''c'', ''d'', ''e''] }, yAxis: {},'
    + ' series: [{ type: ''line'', data: [5, 20, 36, 10, 14], symbolSize: 12,'
    + '   emphasis: { focus: ''series'', scale: 2 }, areaStyle: {},'
    + '   markPoint: { data: [{ type: ''max'' }, { type: ''min'' }] },'
    + '   markLine: { data: [{ type: ''average'' }] },'
    + '   markArea: { data: [[{ xAxis: ''b'' }, { xAxis: ''c'' }]] } },'
    + ' { type: ''line'', data: [15, 2, 6, 30, 4], emphasis: { focus: ''self'' } }] }',
    False, False, 17);
  AssertTrue('frames were patched, not built', n > 3);
end;

procedure TAdvChartStPatchTest.TestAPieAGraphAndATreemapPatchAsABuildWould;
var n: Integer;
begin
  n := Sweep('{ ' + cNoTip + 'series: [{ type: ''pie'', data: [{ name: ''a'', value: 3 },'
    + ' { name: ''b'', value: 5 }, { name: ''c'', value: 2 }], label: { show: true },'
    + ' labelLine: { show: true }, emphasis: { focus: ''self'' } }] }', False, False, 19);
  AssertTrue('the pie patched', n > 3);
  n := Sweep('{ ' + cNoTip + 'series: [{ type: ''graph'', layout: ''none'', roam: false,'
    + ' label: { show: true }, emphasis: { focus: ''adjacency'' },'
    + ' data: [{ name: ''a'', x: 50, y: 50, symbolSize: 30 }, { name: ''b'', x: 250, y: 60, symbolSize: 30 },'
    + ' { name: ''c'', x: 150, y: 200, symbolSize: 30 }, { name: ''d'', x: 330, y: 220, symbolSize: 30 }],'
    + ' links: [{ source: ''a'', target: ''b'' }, { source: ''b'', target: ''c'' },'
    + ' { source: ''c'', target: ''d'', label: { show: true } }] }] }', False, False, 19);
  AssertTrue('the graph patched', n > 3);
  n := Sweep('{ ' + cNoTip + 'series: [{ type: ''treemap'', leafDepth: 1, data: [{ name: ''a'', value: 10,'
    + ' children: [{ name: ''a1'', value: 6 }, { name: ''a2'', value: 4 }] },'
    + ' { name: ''b'', value: 6, children: [{ name: ''b1'', value: 6 }] }, { name: ''c'', value: 3 }] }] }',
    False, False, 19);
  AssertTrue('the treemap patched', n > 3);
end;

procedure TAdvChartStPatchTest.TestAProgressiveScatterRedrawsItsChunks;
var
  s: string;
  i, n: Integer;
  st: LongWord;
begin
  { THE INCREMENTAL LAYER holds the chunks as they were drawn: a patch
    draws it again, as a build does -- left alone, a hovered point's
    emphasis stayed out of the picture (scatter-jitter, scatter-painter-
    choice) }
  s := '';
  st := 5;
  for i := 0 to 1199 do
  begin
    {$push}{$R-}{$Q-}
    st := st * 1103515245 + 12345;
    {$pop}
    if i > 0 then s := s + ',';
    s := s + Format('[%d,%d]', [(st shr 8) mod 1000, (st shr 18) mod 1000]);
  end;
  n := Sweep('{ ' + cNoTip + 'xAxis: {}, yAxis: {}, series: [{ type: ''scatter'','
    + ' progressive: 200, progressiveThreshold: 500, symbolSize: 8,'
    + ' emphasis: { itemStyle: { color: ''#f00'', borderColor: ''#000'', borderWidth: 2 } },'
    + ' data: [' + s + '] }] }', False, False, 21);
  AssertTrue('frames were patched', n > 0);
end;

procedure TAdvChartStPatchTest.TestTheDirtyRectPathPatchesAsABuildWould;
var n: Integer;
begin
  n := Sweep('{ ' + cNoTip + 'xAxis: { data: [''a'', ''b'', ''c'', ''d''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [5, 20, 36, 10], emphasis: { focus: ''series'' },'
    + '   markPoint: { data: [{ type: ''max'' }] } },'
    + ' { type: ''line'', data: [8, 12, 18, 30], symbolSize: 10 }] }', True, False, 23);
  AssertTrue('frames were patched', n > 3);
end;

procedure TAdvChartStPatchTest.TestRenderToPatchesAsABuildWould;
var n: Integer;
begin
  n := Sweep('{ ' + cNoTip + 'xAxis: { data: [''a'', ''b'', ''c'', ''d''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [5, 20, 36, 10], emphasis: { focus: ''series'' },'
    + '   label: { show: true } },'
    + ' { type: ''line'', data: [8, 12, 18, 30], symbolSize: 10 }] }', False, True, 23);
  AssertTrue('frames were patched', n > 3);
end;

procedure TAdvChartStPatchTest.TestAPolarLinePatchesAsABuildWould;
var n: Integer;
begin
  { a polar line's symbols once carried stack garbage in their animation
    record (the symbol area the polar path never set): a patched list and a
    fresh build never compared equal }
  n := Sweep('{ ' + cNoTip + 'polar: {}, angleAxis: { type: ''category'','
    + ' data: [''a'', ''b'', ''c'', ''d'', ''e'', ''f''] }, radiusAxis: {},'
    + ' series: [{ type: ''line'', coordinateSystem: ''polar'', symbolSize: 10,'
    + ' data: [5, 20, 36, 10, 14, 30], emphasis: { focus: ''series'' } }] }', True, False, 17);
  AssertTrue('the dirty-rect path patched', n > 0);
  n := Sweep('{ ' + cNoTip + 'polar: {}, angleAxis: { type: ''category'','
    + ' data: [''a'', ''b'', ''c'', ''d'', ''e'', ''f''] }, radiusAxis: {},'
    + ' series: [{ type: ''line'', coordinateSystem: ''polar'', symbolSize: 10,'
    + ' data: [5, 20, 36, 10, 14, 30], emphasis: { focus: ''series'' } }] }', False, False, 17);
  AssertTrue('the whole-layer path patched', n > 0);
end;

procedure TAdvChartStPatchTest.TestAGeoAndAMapSeriesAsABuildWould;
const
  cMap = '{"type":"FeatureCollection","features":['
    + '{"type":"Feature","properties":{"name":"A"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}},'
    + '{"type":"Feature","properties":{"name":"B"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[10,0],[20,0],[20,10],[10,10],[10,0]]]}},'
    + '{"type":"Feature","properties":{"name":"C"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[0,10],[20,10],[10,20],[0,10]]]}}]}';
var n: Integer;
begin
  AssertTrue(TyChartRegisterMap('p2sq', cMap));
  try
    { a geo component's regions: their flags are drawn by the build alone
      (TyBuildGeo), so a change of them is built again, never patched }
    Sweep('{ ' + cNoTip + 'geo: { map: ''p2sq'', label: { show: true },'
      + ' emphasis: { itemStyle: { areaColor: ''#f80'' } } },'
      + ' series: [{ type: ''scatter'', coordinateSystem: ''geo'','
      + ' data: [[5, 5, 1], [15, 5, 2]], symbolSize: 14 }] }', False, False, 19);
    { a map series' regions are its rows: rewritten with the states
      (MapRepatch) }
    n := Sweep('{ ' + cNoTip + 'series: [{ type: ''map'', map: ''p2sq'','
      + ' label: { show: true }, data: [{ name: ''A'', value: 1 }, { name: ''B'', value: 2 },'
      + ' { name: ''C'', value: 3 }], emphasis: { itemStyle: { areaColor: ''#0c0'' } } }] }',
      False, False, 19);
    AssertTrue('the map series patched', n > 0);
  finally
    TyChartClearMaps;
  end;
end;

procedure TAdvChartStPatchTest.TestNoStateChangeNoPatch;
var
  c: TP2Probe;
  b: TBitmap;
  p0: Integer;
begin
  { a frame with no state change neither builds nor patches: the patch
    answers only StApplyChanged }
  c := TP2Probe.Create(FForm);
  b := TBitmap.Create;
  try
    b.PixelFormat := pf24bit;
    b.SetSize(400, 300);
    c.Parent := FForm;
    c.Controller := FCtl;
    c.AnimationMode := camOff;
    c.SetBounds(0, 0, 400, 300);
    c.Option := '{ ' + cNoTip + 'xAxis: { data: [''a'', ''b''] }, yAxis: {},'
      + ' series: [{ type: ''bar'', data: [5, 20] }] }';
    c.Layered(b.Canvas, Rect(0, 0, 400, 300), 96);
    p0 := TyAdvChartStPatchesForTest;
    c.Layered(b.Canvas, Rect(0, 0, 400, 300), 96);
    c.Hover(2, 2);
    c.Layered(b.Canvas, Rect(0, 0, 400, 300), 96);
    AssertEquals('nothing patched', p0, TyAdvChartStPatchesForTest);
  finally
    b.Free;
    c.Free;
  end;
end;

{ ==================== the journal ==================== }

function TAdvChartPaintJournalTest.El(AZ2: Integer; const AText: string): TTyChartElement;
begin
  Result := TyChartElement(TyShapeRect(TyRectF(0, 0, 10, 10)));
  Result.Z2 := AZ2;
  Result.Caption.Text := AText;
end;

procedure TAdvChartPaintJournalTest.TestARewindPutsBackWhatTheRecordedWritesWentOver;
var l: TTyPaintList;
begin
  l := TTyPaintList.Create;
  try
    l.Add(El(1, 'a'));
    l.Add(El(2, 'b'));
    l.Add(El(3, 'c'));
    l.JournalOpen;
    l.JournalRecord(True);
    l.SetElement(1, El(20, 'B'));
    l.SetElement(1, El(21, 'BB'));
    l.SetElement(2, El(30, 'C'));
    l.JournalRecord(False);
    l.JournalClose;
    AssertTrue('ready', l.JournalReady);
    AssertEquals('written', 'BB', l.Element(1).Caption.Text);
    l.JournalRewind;
    AssertEquals('the first value back, not the second write''s', 'b', l.Element(1).Caption.Text);
    AssertEquals('its z2 too', 2, l.Element(1).Z2);
    AssertEquals('c back', 'c', l.Element(2).Caption.Text);
    AssertEquals('a untouched', 'a', l.Element(0).Caption.Text);
    { the paint order is worked out again from the restored z2 }
    AssertEquals('paint order: a first', 0, l.PaintOrder(0));
    AssertEquals('then b', 1, l.PaintOrder(1));
    AssertFalse('a rewind opens a new session', l.JournalReady);
    { the new session records afresh }
    l.JournalRecord(True);
    l.SetElement(0, El(9, 'A'));
    l.JournalRecord(False);
    l.JournalClose;
    l.JournalRewind;
    AssertEquals('the new session''s entry', 'a', l.Element(0).Caption.Text);
    AssertEquals('the old session''s entries gone', 'b', l.Element(1).Caption.Text);
  finally
    l.Free;
  end;
end;

procedure TAdvChartPaintJournalTest.TestAWriteOutsideTheRecordingIsTheBuildsOwn;
var l: TTyPaintList;
begin
  l := TTyPaintList.Create;
  try
    l.Add(El(1, 'a'));
    l.Add(El(2, 'b'));
    l.JournalOpen;
    { the build's own construction write: kept through a rewind }
    l.SetElement(0, El(1, 'built'));
    l.JournalRecord(True);
    l.SetElement(1, El(2, 'state'));
    l.JournalRecord(False);
    l.JournalClose;
    AssertTrue('a write inside the session does not taint it', l.JournalReady);
    l.JournalRewind;
    AssertEquals('the construction stays', 'built', l.Element(0).Caption.Text);
    AssertEquals('the state goes', 'b', l.Element(1).Caption.Text);
  finally
    l.Free;
  end;
end;

procedure TAdvChartPaintJournalTest.TestAWriteAfterTheSessionTaintsIt;
var l: TTyPaintList;
begin
  l := TTyPaintList.Create;
  try
    l.Add(El(1, 'a'));
    AssertFalse('never opened: not ready', l.JournalReady);
    l.JournalOpen;
    AssertFalse('open: not ready', l.JournalReady);
    l.JournalClose;
    AssertTrue('closed: ready', l.JournalReady);
    l.SetElement(0, El(1, 'later'));
    AssertFalse('a write after it: tainted', l.JournalReady);
    { recording asked for outside a session records nothing }
    l.JournalRecord(True);
    l.SetElement(0, El(1, 'again'));
    AssertFalse('still tainted', l.JournalReady);
  finally
    l.Free;
  end;
end;

procedure TAdvChartPaintJournalTest.TestClearForgetsTheJournal;
var l: TTyPaintList;
begin
  l := TTyPaintList.Create;
  try
    l.Add(El(1, 'a'));
    l.JournalOpen;
    l.JournalRecord(True);
    l.SetElement(0, El(1, 'x'));
    l.JournalRecord(False);
    l.JournalClose;
    l.Clear;
    AssertFalse('cleared: not ready', l.JournalReady);
    l.Add(El(1, 'n'));
    l.SetElement(0, El(1, 'm'));
    AssertFalse('a write after Clear does not make it ready', l.JournalReady);
    l.JournalOpen;
    l.JournalClose;
    l.JournalRewind;
    AssertEquals('nothing of the old session comes back', 'm', l.Element(0).Caption.Text);
  finally
    l.Free;
  end;
end;

procedure TAdvChartPaintJournalTest.TestAnElementAddedInTheSessionIsJournaledToo;
var l: TTyPaintList;
begin
  l := TTyPaintList.Create;
  try
    l.Add(El(1, 'a'));
    l.JournalOpen;
    { a marker, added after the states were first written }
    l.Add(El(5, 'marker'));
    l.JournalRecord(True);
    l.SetElement(1, El(15, 'marker emphasised'));
    l.JournalRecord(False);
    l.JournalClose;
    l.JournalRewind;
    AssertEquals('put back as added', 'marker', l.Element(1).Caption.Text);
    AssertEquals('both still there', 2, l.Count);
  finally
    l.Free;
  end;
end;

{ Recording switched on outside a session records nothing: the write
  taints the journal, as an unrecorded one would (MapApplyChanged writes
  the regions so, between builds). [fin: recording outside a session
  survived] }
procedure TAdvChartPaintJournalTest.TestARecordedWriteAfterTheSessionTaintsItToo;
var l: TTyPaintList;
begin
  l := TTyPaintList.Create;
  try
    l.Add(El(1, 'a'));
    l.JournalOpen;
    l.JournalClose;
    AssertTrue('closed: ready', l.JournalReady);
    l.JournalRecord(True);
    l.SetElement(0, El(1, 'late'));
    l.JournalRecord(False);
    AssertFalse('a recorded write after the session taints it too', l.JournalReady);
  finally
    l.Free;
  end;
end;

{ Ref out of range on either side: the one shared empty element, never a
  slot of the list's spare capacity. [fin: an unbounded Ref survived] }
procedure TAdvChartPaintJournalTest.TestARefPastTheEndIsTheSharedEmptyElement;
var l: TTyPaintList;
begin
  l := TTyPaintList.Create;
  try
    l.Add(El(1, 'a'));
    AssertTrue('in range: the element itself', l.Ref(0) <> l.Ref(-1));
    AssertEquals('a', l.Ref(0)^.Caption.Text);
    AssertTrue('just past the end: the shared empty element', l.Ref(1) = l.Ref(-1));
    AssertTrue('far past it: the same', l.Ref(1000) = l.Ref(-1));
    AssertEquals('empty', '', l.Ref(1)^.Caption.Text);
  finally
    l.Free;
  end;
end;

{ ==================== the declarations' memo ==================== }

procedure TAdvChartStDeclareMemoTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TP2Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, 400, 300);
  FBmp := nil;
end;

procedure TAdvChartStDeclareMemoTest.TearDown;
begin
  FreeAndNil(FBmp);
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartStDeclareMemoTest.Draw;
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(400, 300, BGRA(255, 0, 255, 255));
  FChart.Whole(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
end;

function TAdvChartStDeclareMemoTest.FillOfRow(ASeries, ARow: Integer): TTyChartColor;
var k: Integer;
begin
  k := FChart.List.IndexOfDatumInk(ASeries, ARow);
  AssertTrue(Format('series %d row %d is drawn', [ASeries, ARow]), k >= 0);
  Result := FChart.List.Element(k).Style.FillColor;
end;

procedure TAdvChartStDeclareMemoTest.HoverRow(ASeries, ARow: Integer);
var
  k: Integer;
  b: TTyRectF;
begin
  k := FChart.List.IndexOfDatumInk(ASeries, ARow);
  AssertTrue(Format('series %d row %d is drawn', [ASeries, ARow]), k >= 0);
  b := TyShapeBounds(FChart.List.Element(k).Shape);
  FChart.Hover(Round((b.Left + b.Right) / 2), Round((b.Top + b.Bottom) / 2));
  Draw;
end;

procedure TAdvChartStDeclareMemoTest.TestARowWithItsOwnEmphasisDoesNotLendItToTheNext;
begin
  { row 1 has an object with its own emphasis colour; rows 0 and 2 have
    none and read the series' -- a memo that kept row 1's styles for the
    next plain row would paint row 2 green }
  FChart.Option := '{ animation: false, tooltip: { show: false },'
    + ' xAxis: { data: [''a'', ''b'', ''c''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', emphasis: { itemStyle: { color: ''#0000ff'' } },'
    + ' data: [5, { value: 7, emphasis: { itemStyle: { color: ''#00ff00'' } } }, 9] }] }';
  Draw;
  HoverRow(0, 2);
  AssertEquals('row 2 takes the series'' emphasis', Int64($FF0000FF), Int64(FillOfRow(0, 2)));
  HoverRow(0, 1);
  AssertEquals('row 1 its own', Int64($FF00FF00), Int64(FillOfRow(0, 1)));
  HoverRow(0, 0);
  AssertEquals('row 0 the series''', Int64($FF0000FF), Int64(FillOfRow(0, 0)));
end;

procedure TAdvChartStDeclareMemoTest.TestTwoSeriesKeepTheirOwnEmphasis;
begin
  FChart.Option := '{ animation: false, tooltip: { show: false },'
    + ' xAxis: { data: [''a'', ''b''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', emphasis: { itemStyle: { color: ''#0000ff'' } }, data: [5, 6] },'
    + ' { type: ''bar'', emphasis: { itemStyle: { color: ''#ff0000'' } }, data: [7, 8] }] }';
  Draw;
  HoverRow(1, 0);
  AssertEquals('the second series'' own', Int64($FFFF0000), Int64(FillOfRow(1, 0)));
  HoverRow(0, 1);
  AssertEquals('the first series'' own', Int64($FF0000FF), Int64(FillOfRow(0, 1)));
end;

initialization
  RegisterTest(TAdvChartStPatchTest);
  RegisterTest(TAdvChartPaintJournalTest);
  RegisterTest(TAdvChartStDeclareMemoTest);
end.
