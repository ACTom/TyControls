unit test.advchart.datazoominteract;
{$mode objfpc}{$H+}
{ dataZoom interaction -- a slider's handles, move bar, body click and brush,
  its labels on a hover or a drag, an inside's wheel zoom and drag pan, the
  action that links every dataZoom on a shared axis, and the throttle both
  dispatch paths go through -- held to what ECharts 6.1 does, step by step.

  tools/advchart-oracle/datazoom-interact.js drives zrender's real Handler
  with synthetic pointer events and a fake clock, and records after every
  step each dataZoom's window and range modes, each slider view's ends,
  range, drag, label visibility and text, brush and emphasis, each inside's
  range, every action dispatched (deferred or not), whether the event was
  stopped, the cursor and what the pointer is over. The port is fed the
  same steps through DataZoomPointer, with DataZoomNow and DataZoomTick as
  the clock.

  EXACT where upstream is: the ends, ranges and windows bit for bit. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.DataZoom, tyControls.AdvChart.DataZoomView,
     tyControls.AdvChart.DataZoomAct, tyControls.AdvChart.Series, tyControls.AdvanceChart;
type
  TDziMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    Names: TStringList;
    W, H: array of Double;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string; AW, AH: Double);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TDziProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { the control's own mouse handlers, as the widgetset calls them }
    procedure Press(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Release(AX, AY: Integer);
    function Wheel(AX, AY, ADelta: Integer): Boolean;
  end;

  TAdvChartDataZoomInteractOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TDziProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FMeas: TDziMeasurer;
    FBad, FCompared: Integer;
    FReport, FName: string;
    FActions: array of TTyDzAction;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; AData: TJSONData);
    procedure OnZoom(Sender: TObject; const AAction: TTyDzAction);
    procedure CheckStep(AScenario, AStep: TJSONObject; APrevented: Boolean);
    procedure RunScenarios(const AGroups: array of string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSliderHandlesAsUpstream;
    procedure TestMoveClickAndBrushAsUpstream;
    procedure TestHoverAndOrientationAsUpstream;
    procedure TestLinkedDataZoomsAsUpstream;
    procedure TestInsideWheelAndPanAsUpstream;
    procedure TestTheApiActionLinksSharedAxes;
    procedure TestTheMouseDrivesTheSliderAndTheWheel;
    procedure TestADeferredRunIsDatedWhenDue;
  end;

implementation

constructor TDziMeasurer.Create;
begin
  inherited Create;
  Names := TStringList.Create;
  Names.CaseSensitive := True;
end;

destructor TDziMeasurer.Destroy;
begin
  Names.Free;
  inherited Destroy;
end;

procedure TDziMeasurer.Add(const AText: string; AW, AH: Double);
var k: Integer;
begin
  if Names.IndexOf(AText) >= 0 then Exit;
  k := Names.Add(AText);
  SetLength(W, k + 1);
  SetLength(H, k + 1);
  W[k] := AW;
  H[k] := AH;
end;

procedure TDziMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var k: Integer;
begin
  k := Names.IndexOf(AText);
  if k < 0 then
  begin
    AW := 0;
    AH := 12;
    Exit;
  end;
  AW := W[k];
  AH := H[k];
end;

function TDziMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

function TDziProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Exit(Measurer);
  Result := inherited NewTextMeasurer(APPI);
end;

procedure TDziProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TDziProbe.Press(AX, AY: Integer);
begin
  MouseDown(mbLeft, [ssLeft], AX, AY);
end;

procedure TDziProbe.Move(AX, AY: Integer);
begin
  MouseMove([ssLeft], AX, AY);
end;

procedure TDziProbe.Release(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

function TDziProbe.Wheel(AX, AY, ADelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], ADelta, Point(AX, AY));
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

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameNum(A: Double; const AHex: string): Boolean;
var b: Double;
begin
  b := FromHex(AHex);
  if IsNan(A) or IsNan(b) then Exit(IsNan(A) and IsNan(b));
  if (A = 0) and (b = 0) then Exit(True);
  Result := Bits(A) = Bits(b);
end;

procedure TAdvChartDataZoomInteractOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartDataZoomInteractOracleTest.Num(const AWhat: string;
  AGot: Double; AData: TJSONData);
begin
  Inc(FCompared);
  if (AData = nil) or (AData.JSONType = jtNull) then
  begin
    if not IsNan(AGot) then Miss(Format('%s: none upstream, %s here', [AWhat, Fmt(AGot)]));
    Exit;
  end;
  if not SameNum(AGot, AData.AsString) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AData.AsString)), Fmt(AGot)]));
end;

procedure TAdvChartDataZoomInteractOracleTest.OnZoom(Sender: TObject;
  const AAction: TTyDzAction);
begin
  SetLength(FActions, Length(FActions) + 1);
  FActions[High(FActions)] := AAction;
end;

procedure TAdvChartDataZoomInteractOracleTest.CheckStep(AScenario,
  AStep: TJSONObject; APrevented: Boolean);
var
  dzs, acts, items, targets, labels: TJSONArray;
  dz, a, win, lay, lb, br, ev: TJSONObject;
  k, j, i, idx: Integer;
  st: TTyDzSliderState;
  L: TTyDzSliderLayout;
  spec: TTyDataZoomSpec;
  zoom: TTyAxisZoom;
  w: TTyDzWindow;
  host: Integer;
  found: Boolean;
  lo, hi: Double;
  typ, want, got: string;
  d: TJSONData;
begin
  ev := AStep.Objects['event'];
  typ := ev.Strings['type'];
  { the actions this step dispatched }
  acts := AStep.Arrays['actions'];
  Inc(FCompared);
  if acts.Count <> Length(FActions) then
    Miss(Format('%d actions upstream, %d here', [acts.Count, Length(FActions)]))
  else
    for k := 0 to acts.Count - 1 do
    begin
      a := acts.Objects[k];
      Inc(FCompared);
      if a.Booleans['deferred'] <> FActions[k].Deferred then
        Miss(Format('action %d deferred %s upstream', [k, BoolToStr(a.Booleans['deferred'], True)]));
      d := a.Find('batch');
      if (d <> nil) and (d.JSONType = jtArray) then
      begin
        items := TJSONArray(d);
        Inc(FCompared);
        if (not FActions[k].Batch) or (items.Count <> Length(FActions[k].Items)) then
        begin
          Miss(Format('action %d: a batch of %d upstream', [k, items.Count]));
          Continue;
        end;
        for j := 0 to items.Count - 1 do
        begin
          Inc(FCompared);
          if items.Objects[j].Integers['dataZoomIndex'] <> FActions[k].Items[j].DataZoomIndex then
            Miss(Format('action %d item %d: dataZoom %d upstream', [k, j,
              items.Objects[j].Integers['dataZoomIndex']]));
          Num(Format('action %d item %d start', [k, j]), FActions[k].Items[j].Start,
            items.Objects[j].Find('start'));
          Num(Format('action %d item %d end', [k, j]), FActions[k].Items[j].Stop,
            items.Objects[j].Find('end'));
        end;
      end
      else
      begin
        Inc(FCompared);
        if FActions[k].Batch or (Length(FActions[k].Items) <> 1) then
        begin
          Miss(Format('action %d: a single item upstream', [k]));
          Continue;
        end;
        Num(Format('action %d start', [k]), FActions[k].Items[0].Start, a.Find('start'));
        Num(Format('action %d end', [k]), FActions[k].Items[0].Stop, a.Find('end'));
      end;
    end;
  { stopped }
  if (typ = 'mousemove') or (typ = 'mousewheel') then
  begin
    Inc(FCompared);
    if AStep.Booleans['prevented'] <> APrevented then
      Miss(Format('%s stopped %s upstream', [typ, BoolToStr(AStep.Booleans['prevented'], True)]));
  end;
  { what the pointer is over, and the cursor it leaves }
  if typ = 'mousemove' then
  begin
    d := AStep.Find('hover');
    if (d = nil) or (d.JSONType = jtNull) then want := ''
    else if Pos('dz', d.AsString) = 1 then want := d.AsString
    else want := 'other';
    Inc(FCompared);
    if want <> FChart.DataZoomHoverName then
      Miss(Format('over "%s" upstream, "%s" here', [want, FChart.DataZoomHoverName]));
    if AStep.Arrays['cursors'].Count > 0 then
    begin
      want := AStep.Arrays['cursors'].Strings[AStep.Arrays['cursors'].Count - 1];
      got := FChart.DataZoomCursorName;
      Inc(FCompared);
      if want <> got then Miss(Format('cursor %s upstream, %s here', [want, got]));
    end;
  end;
  { every dataZoom }
  dzs := AStep.Arrays['dataZooms'];
  for k := 0 to dzs.Count - 1 do
  begin
    dz := dzs.Objects[k];
    idx := dz.Integers['index'];
    spec := FChart.DataZoomSpec(idx);
    { the range modes }
    for j := 0 to 1 do
    begin
      Inc(FCompared);
      if (dz.Arrays['rangePropMode'].Strings[j] = 'percent') <> (spec.Mode[j] = dzmPercent) then
        Miss(Format('dz%d end %d in %s mode upstream', [idx, j,
          dz.Arrays['rangePropMode'].Strings[j]]));
    end;
    { the representative window: the first target it hosts, else the first }
    targets := nil;
    for j := 0 to AScenario.Objects['layout'].Arrays['dataZooms'].Count - 1 do
    begin
      lay := AScenario.Objects['layout'].Arrays['dataZooms'].Objects[j];
      if lay.Integers['index'] = idx then targets := lay.Arrays['targets'];
    end;
    found := False;
    win := nil;
    d := dz.Find('window');
    if (d <> nil) and (d.JSONType = jtObject) then win := TJSONObject(d);
    if (targets <> nil) and (win <> nil) then
    begin
      for i := 0 to targets.Count - 1 do
        if FChart.AxisZoom(targets.Objects[i].Strings['dim'] + 'Axis',
          targets.Objects[i].Integers['index'], zoom, w, host) and (host = idx) then
        begin
          found := True;
          Break;
        end;
      if not found then
        found := FChart.AxisZoom(targets.Objects[0].Strings['dim'] + 'Axis',
          targets.Objects[0].Integers['index'], zoom, w, host);
      Inc(FCompared);
      if not found then Miss(Format('dz%d: no window here', [idx]))
      else
        for j := 0 to 1 do
        begin
          Num(Format('dz%d window value %d', [idx, j]), w.Value[j], win.Arrays['value'].Items[j]);
          Num(Format('dz%d window percent %d', [idx, j]), w.Percent[j], win.Arrays['percent'].Items[j]);
        end;
    end;
    if dz.Strings['subType'] = 'slider' then
    begin
      st := FChart.DataZoomSliderState(idx);
      L := FChart.DataZoomSliderLayout(idx);
      for j := 0 to 1 do
      begin
        Num(Format('dz%d end %d', [idx, j]), st.Ends[j], dz.Arrays['handleEnds'].Items[j]);
        Num(Format('dz%d range %d', [idx, j]), st.Range[j], dz.Arrays['range'].Items[j]);
        Num(Format('dz%d laid-out end %d', [idx, j]), L.HandleEnds[j], dz.Arrays['handleEnds'].Items[j]);
      end;
      Inc(FCompared);
      if st.Dragging <> dz.Booleans['dragging'] then
        Miss(Format('dz%d dragging %s upstream', [idx, BoolToStr(dz.Booleans['dragging'], True)]));
      Inc(FCompared);
      if st.Brushing <> dz.Booleans['brushing'] then
        Miss(Format('dz%d brushing %s upstream', [idx, BoolToStr(dz.Booleans['brushing'], True)]));
      labels := dz.Arrays['labels'];
      for j := 0 to Min(1, labels.Count - 1) do
      begin
        lb := labels.Objects[j];
        Inc(FCompared);
        if L.Labels[j].Visible = lb.Booleans['invisible'] then
          Miss(Format('dz%d label %d invisible %s upstream', [idx, j,
            BoolToStr(lb.Booleans['invisible'], True)]));
        Inc(FCompared);
        if L.Labels[j].Text <> lb.Strings['text'] then
          Miss(Format('dz%d label %d "%s" upstream, "%s" here', [idx, j,
            lb.Strings['text'], L.Labels[j].Text]));
      end;
      d := dz.Find('brushRect');
      Inc(FCompared);
      if (d = nil) or (d.JSONType = jtNull) then
      begin
        if st.HasBrush then Miss(Format('dz%d: a brush rect here', [idx]));
      end
      else
      begin
        br := TJSONObject(d);
        if not st.HasBrush then Miss(Format('dz%d: no brush rect here', [idx]))
        else
        begin
          Num(Format('dz%d brush x', [idx]), st.BrushX, br.Find('x'));
          Num(Format('dz%d brush width', [idx]), st.BrushW, br.Find('width'));
          Inc(FCompared);
          if st.BrushIgnored <> br.Booleans['ignore'] then
            Miss(Format('dz%d brush ignored %s upstream', [idx, BoolToStr(br.Booleans['ignore'], True)]));
        end;
      end;
      for j := 0 to 1 do
      begin
        Inc(FCompared);
        if (dz.Arrays['handleHover'].Integers[j] <> 0) <> st.HandleHover[j] then
          Miss(Format('dz%d handle %d hover %d upstream', [idx, j,
            dz.Arrays['handleHover'].Integers[j]]));
      end;
      d := dz.Find('moveHandle');
      Inc(FCompared);
      if (d = nil) or (d.JSONType <> jtObject) then
      begin
        { no move bar without the brush }
        if st.MoveBits <> 0 then Miss(Format('dz%d: move handle bits here', [idx]));
      end
      else if (TJSONObject(d).Integers['highByOuter'] and 3) <> (st.MoveBits and 3) then
        Miss(Format('dz%d move handle bits %d upstream, %d here', [idx,
          TJSONObject(d).Integers['highByOuter'], st.MoveBits]));
    end
    else if dz.Strings['subType'] = 'inside' then
    begin
      FChart.DataZoomInsideRange(idx, lo, hi);
      Num(Format('dz%d inside range 0', [idx]), lo, dz.Arrays['range'].Items[0]);
      Num(Format('dz%d inside range 1', [idx]), hi, dz.Arrays['range'].Items[1]);
    end;
  end;
end;

procedure TAdvChartDataZoomInteractOracleTest.RunScenarios(
  const AGroups: array of string; AMin: Integer);
var
  scs, steps: TJSONArray;
  sc, st, ev, keys: TJSONObject;
  s, k, g: Integer;
  ours: Boolean;
  typ: string;
  x, y, t: Double;
  shift: TShiftState;
  prevented: Boolean;
begin
  scs := TJSONObject(FRoot).Arrays['scenarios'];
  for s := 0 to scs.Count - 1 do
  begin
    sc := scs.Objects[s];
    ours := False;
    for g := 0 to High(AGroups) do
      if sc.Strings['id'] = AGroups[g] then ours := True;
    if not ours then Continue;
    { a fresh chart: the same text twice is no change at all }
    FChart.Option := '{}';
    FChart.Option := sc.Objects['option'].AsJSON;
    FChart.DataZoomNow := NaN;
    FChart.SetBounds(0, 0, 800, 600);
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
    FActions := nil;
    steps := sc.Arrays['steps'];
    for k := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[k];
      ev := st.Objects['event'];
      typ := ev.Strings['type'];
      FName := Format('%s step %d (%s)', [sc.Strings['id'], k, typ]);
      t := ev.Floats['t'];
      FActions := nil;
      FChart.DataZoomNow := t;
      try
        FChart.DataZoomTick(t);
        prevented := False;
        if typ <> 'idle' then
        begin
          x := FromHex(ev.Strings['x']);
          y := FromHex(ev.Strings['y']);
          shift := [];
          if (ev.Find('keys') <> nil) and (ev.Find('keys').JSONType = jtObject) then
          begin
            keys := ev.Objects['keys'];
            if (keys.Find('shift') <> nil) and keys.Booleans['shift'] then Include(shift, ssShift);
            if (keys.Find('ctrl') <> nil) and keys.Booleans['ctrl'] then Include(shift, ssCtrl);
            if (keys.Find('alt') <> nil) and keys.Booleans['alt'] then Include(shift, ssAlt);
          end;
          if typ = 'mousemove' then
            prevented := FChart.DataZoomPointer(dpMove, x, y, shift, 0)
          else if typ = 'mousedown' then
            prevented := FChart.DataZoomPointer(dpDown, x, y, shift, 0)
          else if typ = 'mouseup' then
            prevented := FChart.DataZoomPointer(dpUp, x, y, shift, 0)
          else if typ = 'click' then
            prevented := FChart.DataZoomPointer(dpClick, x, y, shift, 0)
          else if typ = 'mousewheel' then
            prevented := FChart.DataZoomPointer(dpWheel, x, y, shift, ev.Floats['delta']);
        end;
      except
        on E: Exception do
        begin
          Miss(E.ClassName + ': ' + E.Message);
          Break;
        end;
      end;
      CheckStep(sc, st, prevented);
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > AMin);
end;

procedure TAdvChartDataZoomInteractOracleTest.SetUp;
var sl: TStringList; ms: TJSONArray; k: Integer; m: TJSONObject; slider: TJSONData;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TDziProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.OnDataZoom := @OnZoom;
  FBmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-datazoom-interact.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-datazoom-interact.json'));
    FRoot := GetJSON(sl.Text);
    { zrender's own text widths, from the slider oracle's table: the axis
      labels decide nothing here unless they overflow, and the handle
      labels are compared by text only }
    sl.LoadFromFile(FixturePath('advchart-datazoom-slider.json'));
    slider := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FMeas := TDziMeasurer.Create;
  FChart.Measurer := FMeas;
  try
    ms := TJSONObject(slider).Arrays['measure'];
    for k := 0 to ms.Count - 1 do
    begin
      m := ms.Objects[k];
      FMeas.Add(m.Strings['string'], FromHex(m.Strings['width']),
        FromHex(m.Strings['height']));
    end;
  finally
    slider.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartDataZoomInteractOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  if FChart <> nil then FChart.Measurer := nil;
  FChart := nil;
  FMeas := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartDataZoomInteractOracleTest.TestSliderHandlesAsUpstream;
begin
  RunScenarios(['H0R50', 'H0R50s', 'H1L80', 'H0CLAMP0', 'H1CLAMPLEN', 'H0CROSS',
    'SPANS', 'MINVALUESPAN', 'ZOOMLOCK', 'THROTTLE', 'RT-FALSE', 'RT-FALSE-VALUE',
    'RT-FALSE-CLICKHANDLE', 'RT-TRUE-CLICKHANDLE', 'SL-TIME', 'SL-VALUE'], 200);
end;

procedure TAdvChartDataZoomInteractOracleTest.TestMoveClickAndBrushAsUpstream;
begin
  RunScenarios(['MOVEZONE', 'FILLER', 'CLICK-BODY', 'CLICK-3PX', 'CLICK-6PX',
    'CLICK-NOBRUSH', 'CLICK-SPLIT', 'BRUSH', 'BRUSH-SLOW3', 'BRUSH-STALE',
    'BRUSH-CLAMP', 'BRUSH-CLAMP0', 'BRUSH-MINSPAN'], 200);
end;

procedure TAdvChartDataZoomInteractOracleTest.TestHoverAndOrientationAsUpstream;
begin
  RunScenarios(['HOVER', 'HOVER-OVERLAP', 'HOVER-SHOW', 'HOVER-EMPH-OFF', 'VERTICAL', 'VERTICAL-INV',
    'INVERSE'], 100);
end;

procedure TAdvChartDataZoomInteractOracleTest.TestLinkedDataZoomsAsUpstream;
begin
  RunScenarios(['TWO-SLIDERS', 'SLIDER-INSIDE', 'CHAIN', 'CHAIN2', 'SPANS-HOST'], 50);
end;

procedure TAdvChartDataZoomInteractOracleTest.TestInsideWheelAndPanAsUpstream;
begin
  RunScenarios(['IN-WHEEL', 'IN-WHEEL-EDGE', 'IN-WHEEL-MANY', 'IN-WHEEL-CLAMP',
    'IN-WHEEL-CLAMP2', 'IN-MINSPAN', 'IN-VALUESPAN', 'IN-OUTSIDE', 'IN-PAN',
    'IN-PAN-END', 'IN-Y', 'IN-INVERSE', 'IN-SHIFT', 'IN-CTRL-MOVE', 'IN-NOMOVE',
    'IN-DISABLED', 'IN-ZOOMLOCK', 'IN-ZOOMLOCK-WHEELMOVE', 'IN-WHEELMOVE',
    'IN-WHEELMOVE-ONLY', 'IN-XY', 'IN-XY-LOCK', 'IN-XY-DISABLED', 'IN-NOPREVENT',
    'IN-TIME'], 200);
end;

procedure TAdvChartDataZoomInteractOracleTest.TestTheApiActionLinksSharedAxes;
var lo, hi: Double;
begin
  { a slider and an inside on one x axis: the API names the slider, both move }
  FChart.Option := '{"xAxis": {"type": "category", "data": ["a", "b", "c", "d", "e"]},'
    + ' "yAxis": {}, "series": [{"type": "bar", "data": [1, 2, 3, 4, 5]}],'
    + ' "dataZoom": [{"type": "slider"}, {"type": "inside"}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  FActions := nil;
  AssertTrue('dispatched', FChart.DispatchDataZoom(0, 25, 75));
  AssertEquals('one action', 1, Length(FActions));
  AssertEquals('the slider''s range', 25, FChart.DataZoomSliderState(0).Range[0], 1e-12);
  FChart.DataZoomInsideRange(1, lo, hi);
  AssertEquals('the inside follows', 25, lo, 1e-12);
  AssertEquals('the inside follows (end)', 75, hi, 1e-12);
  AssertTrue('now in percent mode', FChart.DataZoomSpec(1).Mode[0] = dzmPercent);
  AssertFalse('no such dataZoom', FChart.DispatchDataZoom(5, 0, 10));
end;

procedure TAdvChartDataZoomInteractOracleTest.TestTheMouseDrivesTheSliderAndTheWheel;
var lo, hi, a, b, pp: Double;
begin
  { H0R50 through the widgetset's own calls: handle 0 of a 20-60 slider sits
    at (244, 570); fifty pixels right on a 600 px slider is 8 1/3 percent }
  FChart.Option := '{"xAxis": {"type": "category", "data": ["c0", "c1", "c2", "c3",'
    + ' "c4", "c5", "c6", "c7", "c8", "c9", "c10", "c11", "c12", "c13", "c14",'
    + ' "c15", "c16", "c17", "c18", "c19"]}, "yAxis": {"type": "value"},'
    + ' "series": [{"type": "line", "data": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,'
    + ' 12, 13, 14, 15, 16, 17, 18, 19, 20]}],'
    + ' "dataZoom": [{"type": "slider", "start": 20, "end": 60}, {"type": "inside"}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  FActions := nil;
  FChart.Move(244, 570);
  FChart.Press(244, 570);
  FChart.Move(294, 570);
  FChart.Release(294, 570);
  AssertTrue('the drag dispatched', Length(FActions) >= 1);
  AssertEquals('the new start', 20 + 50 / 6, FChart.DataZoomSliderState(0).Range[0], 1e-9);
  FChart.DataZoomInsideRange(1, lo, hi);
  AssertEquals('the inside on the same axis follows', 20 + 50 / 6, lo, 1e-9);
  { a wheel notch (120) up in the grid is one zrender notch: 1 / 1.1 of the
    span about the pointer, the grid's middle (120 + 300) }
  a := lo;
  b := hi;
  pp := 300 / 600 * (b - a) + a;
  AssertTrue('the wheel is the dataZoom''s', FChart.Wheel(420, 293, 120));
  FChart.DataZoomInsideRange(1, lo, hi);
  AssertEquals('a notch up, start', (a - pp) * (1 / 1.1) + pp, lo, 1e-9);
  AssertEquals('a notch up, end', (b - pp) * (1 / 1.1) + pp, hi, 1e-9);
  { outside the grid it is not }
  AssertFalse('a wheel outside the grid', FChart.Wheel(10, 10, 120));
end;

procedure TAdvChartDataZoomInteractOracleTest.TestADeferredRunIsDatedWhenDue;
var T: TTyDzThrottle;
begin
  { 'fixRate' at 100 ms: a call at 1000 runs, one at 1040 waits for 1100 }
  T := Default(TTyDzThrottle);
  AssertTrue('the first call runs', TyDzThrottleCall(T, 1000, 100));
  AssertFalse('inside the rate it waits', TyDzThrottleCall(T, 1040, 100));
  AssertEquals('due at the last run plus the rate', 1100, T.Due, 0);
  AssertFalse('not yet', TyDzThrottleFire(T, 1099));
  { the timer fires late (the clock stepped past it): it ran when it was due,
    so a call 100 ms after THAT runs at once }
  AssertTrue('fired', TyDzThrottleFire(T, 1500));
  AssertEquals('dated when due', 1100, T.LastExec, 0);
  AssertTrue('100 ms after the due time', TyDzThrottleCall(T, 1200, 100));
end;

initialization
  RegisterTest(TAdvChartDataZoomInteractOracleTest);
end.
