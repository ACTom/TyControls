unit test.advchart.customseries2;
{$mode objfpc}{$H+}
{ THE CUSTOM SERIES, SECOND PART, HELD TO UPSTREAM [Batch 124, C15].

  tools/advchart-oracle/custom-series2.js runs the real ECharts 6.1 build in
  node with every renderItem a recorder around a JavaScript function and
  writes down, state by state, what custom-series.js does -- the calls, the
  elements, the order, the pointer -- for:

    the coordinate systems  a polar (sectors: coord's four numbers, size in
                            px and radians), a calendar (api.coord of a
                            date, api.layout), a single axis (bare values,
                            a bare size) and none;
    the visuals             api.visual over a continuous and a piecewise
                            visualMap;
    the transitions         enterFrom with an enterAnimation, the default
                            transition, 'all', per-prop lists, the words
                            'shape' and 'style' with an updateAnimation: the
                            elements sampled on the animation clock;
    the leave               a leaveTo on a removed item: upstream throws;
    the hover               the root's focus / blurScope, emphasisDisabled,
                            tooltipDisabled.

  This replays it through the control with a Pascal transcription of every
  renderItem (TCu2Mirror), bit for bit, on the C14 suite's harness
  (TCuOracleBase). The calendar case runs under TZ=UTC upstream; the port
  reads a date on the local wall clock as upstream does, so its instants
  are written down less the zone's shift (TCuMirror.FShift). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Anim,
     tyControls.AdvChart.GfxEl, tyControls.AdvChart.Custom,
     tyControls.AdvanceChart,
     test.advchart.customseries;
type
  { The renderItems of custom-series2.js, transcribed: every api call in its
    own statement, in JavaScript's order. }
  TCu2Mirror = class(TCuMirror)
  protected
    { api.value of a calendar's time dimension: the instant written less the
      zone's shift }
    function TimeValue(AApi: TTyCustomApi; ADim: Integer): Double;
    { api.coord / api.layout of one bare value (ARec is what the oracle
      wrote for it) }
    function CoordAt(AApi: TTyCustomApi; AV, ARec: Double): TTyDoubleArray;
    function LayoutAt(AApi: TTyCustomApi; AV, ARec: Double): TTyCustomLayout;
    { api.size of bare values on a single axis: one number }
    function SizeAt(AApi: TTyCustomApi; ASize, AV: Double): Double;
  public
    function PolarBar(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function CalCell(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function SingleDot(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function FreeRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function VmDot(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function EnterRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function MoveRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function LeaveRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function FocusRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function TipRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  TAdvChartCustomSeries2OracleTest = class(TCuOracleBase)
  private
    FSamples: Integer;
    procedure CheckSnap(AEl: TTyGfxEl; ASnap: TJSONObject);
    procedure CheckAnim(AState: TJSONObject; AStart: Double);
    procedure CheckThrow(AState: TJSONObject);
  protected
    function FixtureName: string; override;
    function NewMirror: TCuMirror; override;
    procedure RunCase(ACase: TJSONObject); override;
  published
    procedure TestTheCoordinateSystemsAreUpstreams;
    procedure TestTheVisualsAreUpstreams;
    procedure TestTheTransitionsAreUpstreams;
    procedure TestALeaveToThrowsAsUpstreams;
    procedure TestTheFocusAndTheTooltipAreUpstreams;
  end;

  { What the fixture does not reach. }
  TAdvChartCustomSeries2Test = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCuProbe;
    FCount: Integer;
    FApiLog: TStringList;
    procedure Show(const AOption: string; AAnimate: Boolean);
    procedure RenderNow;
    function Diag: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  public
    function Grow(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Keep(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Probe(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  published
    procedure TestSwitchingTheAnimationOffSnapsTheTransitions;
    procedure TestATransitionEndsOnTheChartsClock;
    procedure TestARadarCustomSaysItIsNotDrawn;
    procedure TestTheRenderAfterALeaveToThrowStartsOver;
    procedure TestTheApiAnswersNothingWhereUpstreamHasNoFunction;
  end;

implementation

{ ==================== the mirror ==================== }

function TCu2Mirror.TimeValue(AApi: TTyCustomApi; ADim: Integer): Double;
begin
  Result := AApi.Value(ADim);
  Log('value', RvNums([ADim]), RvNum(Result - FShift));
end;

function TCu2Mirror.CoordAt(AApi: TTyCustomApi; AV, ARec: Double): TTyDoubleArray;
begin
  Result := AApi.Coord([AV]);
  Log('coord', RvNums([ARec]), RvNums(Result));
end;

function TCu2Mirror.LayoutAt(AApi: TTyCustomApi; AV, ARec: Double): TTyCustomLayout;
var
  args: TJSONArray;
  ret: TJSONData;

  function RectRec(const R: TTyCustomRect): TJSONObject;
  begin
    Result := TJSONObject.Create(['x', RvNum(R.X), 'y', RvNum(R.Y),
      'width', RvNum(R.Width), 'height', RvNum(R.Height)]);
  end;

begin
  Result := AApi.Layout([AV]);
  args := TJSONArray.Create;
  args.Add(RvNums([ARec]));
  if Result.Valid then
    ret := TJSONObject.Create(['rect', RectRec(Result.Rect),
      'contentRect', RectRec(Result.ContentRect)])
  else
    ret := TJSONNull.Create;
  Log('layout', args, ret);
end;

function TCu2Mirror.SizeAt(AApi: TTyCustomApi; ASize, AV: Double): Double;
var r: TTyDoubleArray;
begin
  r := AApi.Size([ASize], [AV]);
  if Length(r) > 0 then Result := r[0] else Result := NaN;
  if Length(r) > 0 then Log('size', RvNums([ASize, AV]), RvNum(Result))
  else Log('size', RvNums([ASize, AV]), TJSONNull.Create);
end;

{ RENDER.polarBar }
function TCu2Mirror.PolarBar(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  r, a: Double;
  p, s: TTyDoubleArray;
  lay: TTyCustomBarLayout;
  c: TJSONData;
  shape, info: TJSONObject;
begin
  Open('polarBar', AParams);
  r := Value(AApi, 0);
  a := Value(AApi, 1);
  p := Coord(AApi, r, a);
  s := Size2(AApi, 2, 1, r, a);
  lay := BarLayout(AApi, TJSONObject.Create(['count', 1]));
  c := Visual(AApi, 'color');
  shape := TJSONObject.Create(['cx', Num(AParams.CoordSys.Cx), 'cy', Num(AParams.CoordSys.Cy),
    'r0', Num(AParams.CoordSys.R0), 'r', Num(p[2]),
    'startAngle', Num(-p[3] - s[1] / 2), 'endAngle', Num(-p[3] + s[1] / 2)]);
  info := TJSONObject.Create(['band', Num(s[0]), 'none', Length(lay) = 0]);
  Result := Done(TJSONObject.Create(['type', 'sector', 'shape', shape,
    'style', TJSONObject.Create(['fill', c, 'stroke', '#fff']), 'info', info]));
end;

{ RENDER.calCell }
function TCu2Mirror.CalCell(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  t, v, rr: Double;
  p: TTyDoubleArray;
  lay: TTyCustomLayout;
  c: TJSONData;
  rect, circle: TJSONObject;
begin
  Open('calCell', AParams);
  t := TimeValue(AApi, 0);
  v := Value(AApi, 1);
  p := CoordAt(AApi, t, t - FShift);
  lay := LayoutAt(AApi, t, t - FShift);
  c := Visual(AApi, 'color');
  if IsNan(p[0]) then
  begin
    c.Free;
    Exit(Done(nil));
  end;
  rr := Min(AParams.CoordSys.CellWidth, AParams.CoordSys.CellHeight) / 4;
  rect := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', Num(lay.ContentRect.X), 'y', Num(lay.ContentRect.Y),
      'width', Num(lay.ContentRect.Width), 'height', Num(lay.ContentRect.Height)]),
    'style', TJSONObject.Create(['fill', c, 'opacity', Num(v / 10)])]);
  circle := TJSONObject.Create(['type', 'circle',
    'shape', TJSONObject.Create(['cx', Num(p[0]), 'cy', Num(p[1]), 'r', Num(rr)]),
    'style', TJSONObject.Create(['fill', '#fff'])]);
  Result := Done(TJSONObject.Create(['type', 'group', 'children',
    TJSONArray.Create([rect, circle])]));
end;

{ RENDER.singleDot }
function TCu2Mirror.SingleDot(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  v, w, s: Double;
  p: TTyDoubleArray;
  c: TJSONData;
begin
  Open('singleDot', AParams);
  v := Value(AApi, 0);
  w := Value(AApi, 1);
  p := CoordAt(AApi, v, v);
  s := SizeAt(AApi, w, v);
  c := Visual(AApi, 'color');
  Result := Done(TJSONObject.Create(['type', 'circle',
    'shape', TJSONObject.Create(['cx', Num(p[0]), 'cy', Num(p[1]), 'r', Num(s / 2)]),
    'style', TJSONObject.Create(['fill', c]),
    'info', TJSONObject.Create(['mid', Num(AParams.CoordSys.Y + AParams.CoordSys.Height / 2)])]));
end;

{ RENDER.free }
function TCu2Mirror.FreeRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y, w, h: Double;
  c: TJSONData;
  cs: string;
begin
  Open('free', AParams);
  x := Value(AApi, 0);
  y := Value(AApi, 1);
  w := Value(AApi, 2);
  h := Height(AApi);
  c := Visual(AApi, 'color');
  if AParams.CoordSys.Type_ = '' then cs := 'none' else cs := AParams.CoordSys.Type_;
  Result := Done(TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', Num(x), 'y', Num(y), 'width', Num(w), 'height', Num(h / 20)]),
    'style', TJSONObject.Create(['fill', c]),
    'info', TJSONObject.Create(['cs', cs])]));
end;

{ RENDER.vmDot }
function TCu2Mirror.VmDot(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y, r: Double;
  p: TTyDoubleArray;
  c, sz, sym, d: TJSONData;
  st, sty, info: TJSONObject;
begin
  Open('vmDot', AParams);
  x := Value(AApi, 0);
  y := Value(AApi, 1);
  p := Coord(AApi, x, y);
  c := Visual(AApi, 'color');
  sz := Visual(AApi, 'symbolSize');
  sym := Visual(AApi, 'symbol');
  Visual(AApi, 'opacity').Free;
  Visual(AApi, 'liftZ').Free;
  st := Style(AApi, nil);
  try
    { (sz || 10) / 2 }
    if (sz <> nil) and (sz.JSONType = jtNumber) and (sz.AsFloat <> 0)
      and not IsNan(sz.AsFloat) then r := sz.AsFloat / 2
    else r := 10 / 2;
    sty := TJSONObject.Create(['fill', c]);
    info := TJSONObject.Create;
    if sym = nil then info.Add('sym', TJSONNull.Create) else info.Add('sym', sym);
    d := st.Find('opacity');
    if (d <> nil) and (d.JSONType <> jtNull) then sty.Add('opacity', d.Clone);
    Result := Done(TJSONObject.Create(['type', 'circle',
      'shape', TJSONObject.Create(['cx', Num(p[0]), 'cy', Num(p[1]), 'r', Num(r)]),
      'style', sty, 'info', info]));
  finally
    st.Free;
    sz.Free;
  end;
end;

{ RENDER.enterRI }
function TCu2Mirror.EnterRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y: Double;
  p: TTyDoubleArray;
  c: TJSONData;
  i: Integer;
begin
  Open('enterRI', AParams);
  x := Value(AApi, 0);
  y := Value(AApi, 1);
  p := Coord(AApi, x, y);
  c := Visual(AApi, 'color');
  i := AParams.DataIndex;
  if i = 0 then
    Exit(Done(TJSONObject.Create(['type', 'rect', 'x', Num(p[0]), 'y', Num(p[1]),
      'shape', TJSONObject.Create(['x', -15, 'y', -10, 'width', 30, 'height', 20]),
      'style', TJSONObject.Create(['fill', c, 'enterFrom', TJSONObject.Create(['opacity', 0])]),
      'enterFrom', TJSONObject.Create(['y', Num(p[1] + 80)]),
      'enterAnimation', TJSONObject.Create(['duration', 800, 'easing', 'linear', 'delay', 100])])));
  if i = 1 then
    Exit(Done(TJSONObject.Create(['type', 'circle',
      'shape', TJSONObject.Create(['cx', Num(p[0]), 'cy', Num(p[1]), 'r', 12,
        'enterFrom', TJSONObject.Create(['r', 0])]),
      'style', TJSONObject.Create(['fill', c])])));
  Result := Done(TJSONObject.Create(['type', 'group', 'x', Num(p[0]), 'y', Num(p[1]),
    'enterFrom', TJSONObject.Create(['scaleX', 0, 'scaleY', 0]),
    'children', TJSONArray.Create([
      TJSONObject.Create(['type', 'rect',
        'shape', TJSONObject.Create(['x', -10, 'y', -10, 'width', 20, 'height', 20]),
        'style', TJSONObject.Create(['fill', c, 'enterFrom', TJSONObject.Create(['opacity', 0])])]),
      TJSONObject.Create(['type', 'circle',
        'shape', TJSONObject.Create(['cx', 0, 'cy', 0, 'r', 4]),
        'style', TJSONObject.Create(['fill', '#fff'])])])]));
end;

{ RENDER.moveRI }
function TCu2Mirror.MoveRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y, k: Double;
  p: TTyDoubleArray;
  c, fill: TJSONData;
begin
  Open('moveRI', AParams);
  x := Value(AApi, 0);
  y := Value(AApi, 1);
  k := Value(AApi, 2);
  p := Coord(AApi, x, y);
  c := Visual(AApi, 'color');
  if k = 0 then
    Exit(Done(TJSONObject.Create(['type', 'rect', 'x', Num(p[0]), 'y', Num(p[1]),
      'shape', TJSONObject.Create(['x', -10, 'y', -10, 'width', 20, 'height', Num(10 + y)]),
      'style', TJSONObject.Create(['fill', c])])));
  if k = 1 then
  begin
    if y > 5 then
    begin
      c.Free;
      fill := TJSONString.Create('#ee6666');
    end
    else
      fill := c;
    Exit(Done(TJSONObject.Create(['type', 'rect', 'x', Num(p[0]), 'y', Num(p[1]),
      'transition', 'all',
      'shape', TJSONObject.Create(['x', -10, 'y', -10, 'width', Num(10 + y * 2), 'height', 20]),
      'style', TJSONObject.Create(['fill', fill, 'opacity', Num(0.5 + y / 20)])])));
  end;
  if k = 2 then
  begin
    if y > 5 then
    begin
      c.Free;
      fill := TJSONString.Create('#fac858');
    end
    else
      fill := c;
    Exit(Done(TJSONObject.Create(['type', 'circle', 'x', Num(p[0]), 'y', Num(p[1]),
      'transition', TJSONArray.Create(['x']),
      'shape', TJSONObject.Create(['cx', 0, 'cy', 0, 'r', Num(5 + y),
        'transition', TJSONArray.Create(['r'])]),
      'style', TJSONObject.Create(['fill', fill, 'stroke', '#333', 'lineWidth', Num(y / 2),
        'transition', TJSONArray.Create(['fill'])])])));
  end;
  Result := Done(TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', Num(p[0] - 10), 'y', Num(p[1] - 10), 'width', 20, 'height', 20]),
    'transition', TJSONArray.Create(['shape', 'style']),
    'updateAnimation', TJSONObject.Create(['duration', 300, 'easing', 'linear']),
    'style', TJSONObject.Create(['fill', c, 'opacity', Num(0.3 + y / 20)])]));
end;

{ RENDER.leaveRI }
function TCu2Mirror.LeaveRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y: Double;
  p: TTyDoubleArray;
  c: TJSONData;
  el, sty: TJSONObject;
begin
  Open('leaveRI', AParams);
  x := Value(AApi, 0);
  y := Value(AApi, 1);
  p := Coord(AApi, x, y);
  c := Visual(AApi, 'color');
  sty := TJSONObject.Create(['fill', c]);
  el := TJSONObject.Create(['type', 'rect', 'x', Num(p[0]), 'y', Num(p[1]),
    'shape', TJSONObject.Create(['x', -10, 'y', -10, 'width', 20, 'height', 20]),
    'style', sty]);
  if AParams.DataIndex = 2 then
  begin
    el.Add('leaveTo', TJSONObject.Create(['y', Num(p[1] + 50)]));
    sty.Add('leaveTo', TJSONObject.Create(['opacity', 0]));
  end;
  Result := Done(el);
end;

{ RENDER.focusRI }
function TCu2Mirror.FocusRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  v0, v1: Double;
  p, base: TTyDoubleArray;
  c: TJSONData;
  s: Integer;
  el: TJSONObject;
begin
  Open('focusRI', AParams);
  v0 := Value(AApi, 0);
  v1 := Value(AApi, 1);
  p := Coord(AApi, v0, v1);
  base := Coord(AApi, v0, 0);
  c := Visual(AApi, 'color');
  s := AParams.SeriesIndex;
  el := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', Num(p[0] - 15 + s * 10), 'y', Num(p[1]), 'width', 10,
      'height', Num(base[1] - p[1])]),
    'style', TJSONObject.Create(['fill', c])]);
  if s = 0 then el.Add('focus', 'self');
  if s = 1 then
  begin
    el.Add('focus', 'series');
    el.Add('blurScope', 'global');
  end;
  if (s = 2) and (AParams.DataIndex = 1) then el.Add('emphasisDisabled', True);
  Result := Done(el);
end;

{ RENDER.tipRI }
function TCu2Mirror.TipRI(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y: Double;
  p: TTyDoubleArray;
  c: TJSONData;
  i: Integer;
begin
  Open('tipRI', AParams);
  x := Value(AApi, 0);
  y := Value(AApi, 1);
  p := Coord(AApi, x, y);
  c := Visual(AApi, 'color');
  i := AParams.DataIndex;
  if i = 0 then
    Exit(Done(TJSONObject.Create(['type', 'circle', 'tooltipDisabled', True,
      'shape', TJSONObject.Create(['cx', Num(p[0]), 'cy', Num(p[1]), 'r', 15]),
      'style', TJSONObject.Create(['fill', c])])));
  if i = 1 then
    Exit(Done(TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([
      TJSONObject.Create(['type', 'rect', 'tooltipDisabled', True,
        'shape', TJSONObject.Create(['x', Num(p[0] - 30), 'y', Num(p[1] - 10), 'width', 25, 'height', 20]),
        'style', TJSONObject.Create(['fill', c])]),
      TJSONObject.Create(['type', 'rect',
        'shape', TJSONObject.Create(['x', Num(p[0] + 5), 'y', Num(p[1] - 10), 'width', 25, 'height', 20]),
        'style', TJSONObject.Create(['fill', '#91cc75'])])])])));
  if i = 3 then
    Exit(Done(TJSONObject.Create(['type', 'group', 'tooltipDisabled', True,
      'children', TJSONArray.Create([
      TJSONObject.Create(['type', 'rect',
        'shape', TJSONObject.Create(['x', Num(p[0] - 10), 'y', Num(p[1] - 10), 'width', 20, 'height', 20]),
        'style', TJSONObject.Create(['fill', c])])])])));
  Result := Done(TJSONObject.Create(['type', 'circle',
    'shape', TJSONObject.Create(['cx', Num(p[0]), 'cy', Num(p[1]), 'r', 15]),
    'style', TJSONObject.Create(['fill', c])]));
end;

{ ==================== the oracle test ==================== }

function TAdvChartCustomSeries2OracleTest.FixtureName: string;
begin
  Result := 'advchart-custom-series2.json';
end;

function TAdvChartCustomSeries2OracleTest.NewMirror: TCuMirror;
var m: TCu2Mirror;
begin
  m := TCu2Mirror.Create;
  TyChartRegisterRenderItem('polarBar', @m.PolarBar);
  TyChartRegisterRenderItem('calCell', @m.CalCell);
  TyChartRegisterRenderItem('singleDot', @m.SingleDot);
  TyChartRegisterRenderItem('free', @m.FreeRI);
  TyChartRegisterRenderItem('vmDot', @m.VmDot);
  TyChartRegisterRenderItem('enterRI', @m.EnterRI);
  TyChartRegisterRenderItem('moveRI', @m.MoveRI);
  TyChartRegisterRenderItem('leaveRI', @m.LeaveRI);
  TyChartRegisterRenderItem('focusRI', @m.FocusRI);
  TyChartRegisterRenderItem('tipRI', @m.TipRI);
  FSamples := 0;
  Result := m;
end;

{ a sample: the transform props, the style keys (through the prototype's
  defaults, as el.style[k] reads them) and the shape keys }
procedure TAdvChartCustomSeries2OracleTest.CheckSnap(AEl: TTyGfxEl; ASnap: TJSONObject);
var
  i: Integer;
  key: string;
begin
  for i := 0 to ASnap.Count - 1 do
  begin
    key := ASnap.Names[i];
    if Copy(key, 1, 6) = 'style.' then
      SameValue(key, AEl.StyleValue(Copy(key, 7, MaxInt)), ASnap.Items[i])
    else
      SameValue(key, AEl.GetAnimProp(key), ASnap.Items[i]);
  end;
end;

{ an animation state: the calls, every sample on the chart's clock from the
  setOption instant, the elements at rest after the last }
procedure TAdvChartCustomSeries2OracleTest.CheckAnim(AState: TJSONObject; AStart: Double);
var
  samples: TJSONArray;
  smp, els: TJSONObject;
  i, k, idx: Integer;
  t: Double;
  got: TStringList;
  was: string;
begin
  CheckCalls(AState.Arrays['calls']);
  samples := AState.Arrays['samples'];
  was := FWhere;
  for i := 0 to samples.Count - 1 do
  begin
    smp := samples.Objects[i];
    t := smp.Floats['t'];
    FWhere := Format('%s t=%d', [was, Round(t)]);
    FChart.AnimNow := AStart + t;
    FChart.AnimTick(AStart + t);
    Inc(FSamples);
    els := smp.Objects['els'];
    got := Keyed;
    try
      SameInt('present', got.Count, els.Count);
      for k := 0 to els.Count - 1 do
      begin
        idx := got.IndexOf(els.Names[k]);
        if idx < 0 then
        begin
          Bad('missing ' + els.Names[k]);
          Continue;
        end;
        FWhere := Format('%s t=%d %s', [was, Round(t), els.Names[k]]);
        CheckSnap(TTyGfxEl(got.Objects[idx]), TJSONObject(els.Items[k]));
      end;
    finally
      got.Free;
    end;
  end;
  FWhere := was;
  { the transforms the paint computes }
  RenderNow;
  CheckEls(AState.Arrays['els']);
end;

{ the render upstream threw out of: the calls before it, the error, the
  roots left in the group }
procedure TAdvChartCustomSeries2OracleTest.CheckThrow(AState: TJSONObject);
var view: TTyCustomView;
begin
  CheckCalls(AState.Arrays['calls']);
  view := FChart.CustomView(0);
  if view = nil then
  begin
    Bad('no view');
    Exit;
  end;
  SameStr('the throw', view.Error, AState.Strings['throws']);
  SameInt('roots', Length(view.Root.Children), AState.Integers['roots']);
end;

procedure TAdvChartCustomSeries2OracleTest.RunCase(ACase: TJSONObject);
var
  steps, states, smp: TJSONArray;
  step, st: TJSONObject;
  j, si: Integer;
  nowMs, t0, clock, start, last: Double;
  pointer, anim: Boolean;
begin
  FWhere := ACase.Strings['id'];
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  anim := ACase.Find('samplesMs') is TJSONArray;
  t0 := TJSONObject(FRoot).Objects['clock'].Floats['T0'];
  last := 0;
  if anim then
  begin
    smp := ACase.Arrays['samplesMs'];
    last := smp.Floats[smp.Count - 1];
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := t0;
  end;
  FChart.TooltipNow := 0;
  FMirror.Calls.Clear;
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  RenderNow;
  states := ACase.Arrays['states'];
  FWhere := ACase.Strings['id'] + ' state 0';
  if anim then CheckAnim(states.Objects[0], t0)
  else CheckState(states.Objects[0], False);
  clock := t0 + last;
  steps := ACase.Arrays['steps'];
  si := 0;
  for j := 0 to steps.Count - 1 do
  begin
    step := steps.Objects[j];
    FWhere := Format('%s step %d', [ACase.Strings['id'], j]);
    if step.Find('wait') <> nil then
    begin
      clock := clock + step.Floats['wait'];
      FChart.AnimNow := clock;
      FChart.AnimTick(clock);
      Continue;
    end;
    Inc(si);
    st := states.Objects[si];
    pointer := False;
    nowMs := si * 1000;
    if anim then FChart.AnimNow := clock
    else FChart.TooltipNow := nowMs;
    if step.Find('move') <> nil then
    begin
      FChart.Move(st.Arrays['point'].Integers[0], st.Arrays['point'].Integers[1]);
      pointer := True;
    end
    else if step.Find('leave') <> nil then
    begin
      FChart.Leave;
      pointer := True;
    end
    else if step.Find('merge') <> nil then
      FChart.SetOption(step.Objects['merge'].AsJSON, False);
    if not anim then
    begin
      FChart.TooltipTick(nowMs + 500);
      FChart.TooltipNow := nowMs + 500;
    end;
    RenderNow;
    Inc(FSteps);
    if not IsNull(st.Find('throws')) then
    begin
      CheckThrow(st);
      Continue;
    end;
    if anim then
    begin
      start := clock;
      CheckAnim(st, start);
      clock := start + last;
    end
    else
      CheckState(st, pointer);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartCustomSeries2OracleTest.TestTheCoordinateSystemsAreUpstreams;
begin
  RunGroup('coords', 1500);
end;

procedure TAdvChartCustomSeries2OracleTest.TestTheVisualsAreUpstreams;
begin
  RunGroup('visual', 300);
end;

procedure TAdvChartCustomSeries2OracleTest.TestTheTransitionsAreUpstreams;
begin
  RunGroup('anim', 3000);
  AssertTrue('samples compared', FSamples >= 40);
end;

procedure TAdvChartCustomSeries2OracleTest.TestALeaveToThrowsAsUpstreams;
begin
  RunGroup('leave', 100);
end;

procedure TAdvChartCustomSeries2OracleTest.TestTheFocusAndTheTooltipAreUpstreams;
begin
  RunGroup('hover', 300);
end;

{ ==================== hand-written ==================== }

procedure TAdvChartCustomSeries2Test.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  FCount := 0;
  FApiLog := TStringList.Create;
  TyChartClearRenderItems;
end;

procedure TAdvChartCustomSeries2Test.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FApiLog);
  TyChartClearRenderItems;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartCustomSeries2Test.Show(const AOption: string; AAnimate: Boolean);
begin
  FreeAndNil(FChart);
  FChart := TCuProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  if AAnimate then
  begin
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := 1000000;
  end
  else
    FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, 400, 300);
  FChart.SetOption(AOption, True);
  RenderNow;
end;

procedure TAdvChartCustomSeries2Test.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartCustomSeries2Test.Diag: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FChart.DiagnosticCount - 1 do
    Result := Result + FChart.Diagnostic(i) + '|';
end;

{ a circle growing in from nothing (the shape's enterFrom) }
function TAdvChartCustomSeries2Test.Grow(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  v0, v1: Double;
  c: TTyDoubleArray;
begin
  Inc(FCount);
  v0 := AApi.Value(0);
  v1 := AApi.Value(1);
  c := AApi.Coord([v0, v1]);
  Result := TJSONObject.Create(['type', 'circle',
    'shape', TJSONObject.Create(['cx', c[0], 'cy', c[1], 'r', 10,
      'enterFrom', TJSONObject.Create(['r', 0])]),
    'style', TJSONObject.Create(['fill', '#ff0000'])]);
end;

{ a square per item, the last of three with a leaveTo }
function TAdvChartCustomSeries2Test.Keep(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  v0, v1: Double;
  c: TTyDoubleArray;
  o: TJSONObject;
begin
  Inc(FCount);
  v0 := AApi.Value(0);
  v1 := AApi.Value(1);
  c := AApi.Coord([v0, v1]);
  o := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', c[0] - 5, 'y', c[1] - 5, 'width', 10, 'height', 10]),
    'style', TJSONObject.Create(['fill', '#00aa00'])]);
  if AParams.DataIndex = 2 then o.Add('leaveTo', TJSONObject.Create(['x', 50]));
  Result := o;
end;

{ what the api answers on each system, written down; nothing drawn }
function TAdvChartCustomSeries2Test.Probe(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  c, s: TTyDoubleArray;
  lay: TTyCustomLayout;
  bl: TTyCustomBarLayout;
  o: TJSONObject;
begin
  Inc(FCount);
  c := AApi.Coord([1, 2]);
  s := AApi.Size([1, 1]);
  lay := AApi.Layout([1]);
  o := TJSONObject.Create(['count', 1]);
  try
    bl := AApi.BarLayout(o);
  finally
    o.Free;
  end;
  FApiLog.Add(Format('%s coord %d size %d layout %s bar %d', [AParams.CoordSys.Type_,
    Length(c), Length(s), BoolToStr(lay.Valid, True), Length(bl)]));
  Result := nil;
end;

procedure TAdvChartCustomSeries2Test.TestSwitchingTheAnimationOffSnapsTheTransitions;
var el: TTyGfxEl;
begin
  TyChartRegisterRenderItem('Grow', @Grow);
  Show('{"animation":true,"xAxis":{"type":"value","min":0,"max":10},'
    + '"yAxis":{"type":"value","min":0,"max":10},'
    + '"series":[{"type":"custom","renderItem":"@Grow","data":[[2,3],[5,5]]}]}', True);
  el := FChart.CustomView(0).ElOf(1);
  AssertTrue('drawn', el <> nil);
  AssertEquals('it enters from nothing', 0, el.Shape.Floats['r'], 0);
  AssertTrue('and is moving', el.AnimatorCount > 0);
  FChart.AnimationMode := camOff;
  AssertEquals('switched off, it is where renderItem put it', 10, el.Shape.Floats['r'], 0);
  AssertEquals('and nothing moves it any more', 0, el.AnimatorCount);
end;

procedure TAdvChartCustomSeries2Test.TestATransitionEndsOnTheChartsClock;
var
  el: TTyGfxEl;
  r: Double;
begin
  TyChartRegisterRenderItem('Grow', @Grow);
  Show('{"animation":true,"xAxis":{"type":"value","min":0,"max":10},'
    + '"yAxis":{"type":"value","min":0,"max":10},'
    + '"series":[{"type":"custom","renderItem":"@Grow","data":[[2,3]]}]}', True);
  el := FChart.CustomView(0).ElOf(0);
  FChart.AnimNow := 1000000 + 500;
  FChart.AnimTick(1000000 + 500);
  r := el.Shape.Floats['r'];
  AssertTrue(Format('half way (1000 ms cubicInOut) it is between: %g', [r]), (r > 0) and (r < 10));
  FChart.AnimNow := 1000000 + 2000;
  FChart.AnimTick(1000000 + 2000);
  AssertEquals('past the end it rests', 10, el.Shape.Floats['r'], 0);
  AssertEquals('and its animator is done', 0, el.AnimatorCount);
  AssertEquals('renderItem was asked once', 1, FCount);
end;

procedure TAdvChartCustomSeries2Test.TestARadarCustomSaysItIsNotDrawn;
begin
  TyChartRegisterRenderItem('Grow', @Grow);
  Show('{"radar":{"indicator":[{"name":"a","max":10},{"name":"b","max":10},'
    + '{"name":"c","max":10}]},'
    + '"series":[{"type":"custom","coordinateSystem":"radar","renderItem":"@Grow",'
    + '"data":[[1,2,3]]}]}', False);
  AssertEquals('not asked', 0, FCount);
  AssertTrue('the note names the system: ' + Diag, Pos('radar', Diag) > 0);
end;

{ upstream's render throws on the leaveTo and keeps throwing at every
  update that removes that item again (its _data never moved on); the port
  starts the next render over: every item enters anew }
procedure TAdvChartCustomSeries2Test.TestTheRenderAfterALeaveToThrowStartsOver;
var view: TTyCustomView;
begin
  TyChartRegisterRenderItem('Keep', @Keep);
  Show('{"xAxis":{"type":"value","min":0,"max":10},"yAxis":{"type":"value","min":0,"max":10},'
    + '"series":[{"type":"custom","renderItem":"@Keep","data":[[2,3],[5,5],[8,7]]}]}', False);
  view := FChart.CustomView(0);
  AssertEquals('three drawn', 3, Length(view.Root.Children));
  FChart.SetOption('{"series":[{"data":[[2,3],[5,5]]}]}', False);
  RenderNow;
  AssertEquals('the leaveTo stopped the render', TyCustomLeaveThrow, view.Error);
  AssertTrue('and the chart says so: ' + Diag, Pos('updateAnimation', Diag) > 0);
  FCount := 0;
  FChart.SetOption('{"series":[{"data":[[1,1],[2,2]]}]}', False);
  RenderNow;
  AssertEquals('the next render runs to its end', '', view.Error);
  AssertEquals('every item asked', 2, FCount);
  AssertEquals('and drawn, nothing of the stopped one kept', 2, Length(view.Root.Children));
end;

procedure TAdvChartCustomSeries2Test.TestTheApiAnswersNothingWhereUpstreamHasNoFunction;
begin
  TyChartRegisterRenderItem('Probe', @Probe);
  Show('{"series":[{"type":"custom","coordinateSystem":"none","renderItem":"@Probe",'
    + '"data":[[1,2]]}]}', False);
  Show('{"calendar":{"range":"2017-02"},"series":[{"type":"custom",'
    + '"coordinateSystem":"calendar","renderItem":"@Probe","data":[["2017-02-03",1]]}]}', False);
  Show('{"polar":{},"angleAxis":{"type":"category","data":["a","b"]},"radiusAxis":{},'
    + '"series":[{"type":"custom","coordinateSystem":"polar","renderItem":"@Probe",'
    + '"data":[[1,0]]}]}', False);
  Show('{"singleAxis":{"type":"value"},"series":[{"type":"custom",'
    + '"coordinateSystem":"singleAxis","renderItem":"@Probe","data":[[3]]}]}', False);
  AssertEquals('every system asked', 4, FCount);
  AssertEquals('none: no coord, no size, no layout, no barLayout',
    ' coord 0 size 0 layout False bar 0', FApiLog[0]);
  AssertEquals('a calendar: a point and a layout, no size',
    'calendar coord 2 size 0 layout True bar 0', FApiLog[1]);
  AssertEquals('a polar: four numbers and a size, no layout, no barLayout',
    'polar coord 4 size 2 layout False bar 0', FApiLog[2]);
  AssertEquals('a single axis: a point and one number',
    'singleAxis coord 2 size 1 layout False bar 0', FApiLog[3]);
end;

initialization
  RegisterTest(TAdvChartCustomSeries2OracleTest);
  RegisterTest(TAdvChartCustomSeries2Test);
end.
