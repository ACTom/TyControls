unit test.advchart.stateshier;
{$mode objfpc}{$H+}
{ GRAPH, TREE AND TREEMAP ON THE SHARED STATE MODEL, held to upstream
  [F2a, spec section 198].

  tools/advchart-oracle/states-hier.js drives the real ECharts 6.1 build
  through pointer moves, clicks (move, press, release, click), a move off the
  canvas and dispatchAction, a frame after every step, and records the
  events published and every element's state: the flags (hoverState,
  selected, __highByOuter), the state list, z2 and its rest, fill / stroke /
  lineWidth / opacity and their rest, a symbol's scale, the labels, a graph
  edge's arrows and label transform, a tree node's edge, a treemap node's
  background and content and its breadcrumb items, and the series'
  selectedMap and selected indices.

  This replays every case on a new control (the oracle makes a new chart per
  case) through MouseMove / MouseDown / MouseUp and DispatchAction, a render
  after every step, and compares through the state records (ItemStates,
  EdgeStates) and the drawn list:
    the events -- types and order, an action event's payload, a mouse
      event's componentType / seriesIndex / dataIndex / dataType / name /
      selfType / nodeData;
    the selection -- the map (key order too) and the indices;
    per element -- the state list, the flags, the proxy, the opacity (bit
      for bit), the z2 lift over rest, the colours, a symbol's scale (the
      rest scale times the port's ratio, bit for bit), a label's list,
      visibility, opacity and lift;
    the breadcrumb -- each item's drawn fill and z2, its words' ink and z2;
    the graph's edge labels -- the anchor and the turn the transform holds.
  Colours: a fixture colour equal to its rest is the port's rest colour, its
  lift the lift of the port's rest; '#3c3c41' is the skin's title ink and
  '#f4f7fd' the skin's breadcrumb hover; every other colour is declared and
  compared exactly. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.Types,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Events,
     tyControls.AdvChart.Style, tyControls.AdvChart.Color,
     tyControls.AdvChart.States, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimView,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TShProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    Log: TStrings;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Primary: TTyChartColor;
    function CrumbHover: TTyChartColor;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
    function TargetText(AX, AY: Integer): string;
  end;

  TAdvChartStatesHierOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TShProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FSteps: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure NewChart(AOption: TJSONObject);
    procedure CompareEvents(AWant: TJSONArray);
    procedure CompareSeries(ASer: TJSONObject);
    procedure CompareEl(const AWhat: string; AWant: TJSONObject; const AEl: TTyStElement);
    procedure CompareText(const AWhat: string; AWant: TJSONData; const AEl: TTyStElement);
    procedure CompareColour(const AWhat: string; const AWant, AWantRest: TJSONData;
      const AObj, ARest: TTyStObject; AKey: TTyStKey);
    procedure CompareCrumbs(ASeries: Integer; ACrumbs: TJSONArray);
    procedure CompareEdgeLabel(const AWhat: string; ASeries, AEdge: Integer; AWant: TJSONObject);
    procedure CompareNodeLabel(const AWhat: string; ASeries, ARow: Integer; AWant: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestStatesAsUpstream;
  end;

  { WHAT THE ORACLE DOES NOT REACH: the state transitions these series now
    run on the AN3b engine (hover and highlight through each element's
    proxy), and the list taking the states at once without a timer. }
  TAdvChartStatesHierTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TShProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    procedure NewChart(const AOption: string; AMode: TTyChartAnimationMode);
    procedure Draw;
    procedure Settle(AStart: Double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAGraphEdgeHighlightTransitionsOnItsOwnProxy;
    procedure TestATreemapLeafsBackgroundAndContentTransitionTogether;
    procedure TestATreeNodesEdgeTransitionsWhenItFollows;
    procedure TestWithoutAProxyTheListTakesTheStatesAtOnce;
  end;

implementation

const
  cEvents: array[0..10] of string = ('highlight', 'downplay', 'select',
    'unselect', 'toggleselect', 'selectchanged', 'treemapzoomtonode',
    'treemaproottonode', 'mouseover', 'mouseout', 'click');

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

{ ==================== the probe ==================== }

function TShProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TShProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TShProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TShProbe.Primary: TTyChartColor;
begin
  Result := StPrimaryInk;
end;

function TShProbe.CrumbHover: TTyChartColor;
begin
  Result := TTyChartColor(ActiveController.Model.ResolveStyle(
    'TyAdvChartBreadcrumb', '', [tysHover]).Background.Color);
end;

function TShProbe.TargetText(AX, AY: Integer): string;
var tg: TTyChartEventTarget; i, k: Integer;
begin
  tg := EventTargetAt(AX, AY);
  Result := Format('id %d kind %d s %d row %d gen %d', [tg.Id, tg.HdKind, tg.HdSeries, tg.HdRow, tg.HdGen]);
  for i := 0 to SeriesList.Count - 1 do
    if SeriesList.Element(i).Anim.Role = carTmCrumb then
      with SeriesList.Element(i) do
        for k := 0 to High(Shape.Points) do Result := Result + Format(' [%d:%.2f,%.2f]', [Anim.Index, Shape.Points[k].X, Shape.Points[k].Y]);
end;

function JsonOrNull(const AText: string): string;
begin
  if AText = '' then Result := 'null' else Result := AText;
end;

procedure TShProbe.Handle(Sender: TObject; const AEvent: TTyChartEvent);
var o: TJSONObject;
begin
  if Log = nil then Exit;
  if AEvent.Payload <> '' then
  begin
    Log.Add(AEvent.EventType + #9 + AEvent.Payload);
    Exit;
  end;
  o := TJSONObject.Create;
  try
    o.Add('componentType', AEvent.Params.ComponentType);
    if AEvent.Params.SeriesIndex >= 0 then o.Add('seriesIndex', AEvent.Params.SeriesIndex)
    else o.Add('seriesIndex', TJSONNull.Create);
    if AEvent.Params.DataIndex >= 0 then o.Add('dataIndex', AEvent.Params.DataIndex)
    else o.Add('dataIndex', TJSONNull.Create);
    if AEvent.Params.DataType <> '' then o.Add('dataType', AEvent.Params.DataType)
    else o.Add('dataType', TJSONNull.Create);
    if AEvent.Params.SelfType = 'breadcrumb' then o.Add('name', TJSONNull.Create)
    else o.Add('name', AEvent.Params.Name);
    if AEvent.Params.SelfType <> '' then o.Add('selfType', AEvent.Params.SelfType)
    else o.Add('selfType', TJSONNull.Create);
    o.Add('nodeData', GetJSON(JsonOrNull(AEvent.Params.NodeData)));
    Log.Add(AEvent.EventType + #9 + o.AsJSON);
  finally
    o.Free;
  end;
end;

{ ==================== numbers and JSON ==================== }

function HexNum(AData: TJSONData; out AValue: Double): Boolean;
var
  s: string;
  q: QWord;
begin
  AValue := NaN;
  Result := False;
  if not (AData is TJSONArray) or (AData.Count < 2) then Exit;
  if AData.Items[0].JSONType <> jtString then
  begin
    { a non-finite number: its readable twin }
    s := AData.Items[1].AsString;
    if s = 'NaN' then AValue := NaN
    else if s = 'Infinity' then AValue := Infinity
    else if s = '-Infinity' then AValue := NegInfinity;
    Exit(True);
  end;
  s := AData.Items[0].AsString;
  q := StrToQWord('$' + s);
  Move(q, AValue, SizeOf(AValue));
  Result := True;
end;

function SameBits(A, B: Double): Boolean;
var qa, qb: QWord;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Move(A, qa, 8);
  Move(B, qb, 8);
  Result := (qa = qb) or ((A = 0) and (B = 0));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

{ upstream's generated ids, the view uids and objects stand for themselves }
function SameJson(AWant, AGot: TJSONData): Boolean;
var
  i, k: Integer;
  wo, go: TJSONObject;
begin
  Result := False;
  if (AWant = nil) or (AGot = nil) then Exit(AWant = AGot);
  if (AWant.JSONType = jtString) and ((AWant.AsString = '<auto id>')
    or (AWant.AsString = '<view uid>') or (Copy(AWant.AsString, 1, 1) = '[')) then
    Exit(True);
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
        for i := 0 to wo.Count - 1 do
        begin
          k := go.IndexOfName(wo.Names[i]);
          { a key whose value is a placeholder may be the port's own }
          if k < 0 then
          begin
            if (wo.Items[i].JSONType = jtString) and SameJson(wo.Items[i], wo.Items[i])
              and ((wo.Items[i].AsString = '<auto id>') or (wo.Items[i].AsString = '<view uid>')
                or (Copy(wo.Items[i].AsString, 1, 1) = '[')) then Continue;
            Exit;
          end;
          if not SameJson(wo.Items[i], go.Items[k]) then Exit;
        end;
        for i := 0 to go.Count - 1 do
          if wo.IndexOfName(go.Names[i]) < 0 then Exit;
        Result := True;
      end;
  end;
end;

{ zrender's liftColor of a '#rrggbb' / '#rgb': each channel * 1.1 | 0 }
function JsLift(const AColour: string; out AOut: TTyChartColor): Boolean;
var c: TTyChartColor;
begin
  Result := TyTryParseChartColor(AColour, c);
  if Result then AOut := TyChartLiftColor(c);
end;

{ ==================== the harness ==================== }

procedure TAdvChartStatesHierOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-states-hier.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FSteps := 0;
  FReport := '';
end;

procedure TAdvChartStatesHierOracleTest.TearDown;
begin
  if FChart <> nil then
  begin
    FChart.Log.Free;
    FChart.Log := nil;
  end;
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartStatesHierOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 60 then FReport := FReport + LineEnding + '  ' + FWhere + ': ' + AWhat;
end;

procedure TAdvChartStatesHierOracleTest.NewChart(AOption: TJSONObject);
var i: Integer;
begin
  if FChart <> nil then
  begin
    FChart.Log.Free;
    FChart.Log := nil;
    FChart.Free;
  end;
  FChart := TShProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Log := TStringList.Create;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.Option := AOption.AsJSON;
  FChart.SetBounds(0, 0, 600, 400);
  for i := 0 to High(cEvents) do FChart.ChartOn(cEvents[i], @FChart.Handle);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

procedure TAdvChartStatesHierOracleTest.CompareEvents(AWant: TJSONArray);
var
  i, t: Integer;
  want: TJSONObject;
  got: TJSONData;
  line: string;
begin
  Inc(FCompared);
  if AWant.Count <> FChart.Log.Count then
  begin
    line := '';
    for i := 0 to FChart.Log.Count - 1 do line := line + ' | ' + FChart.Log[i];
    Bad(Format('%d events upstream, %d here:%s', [AWant.Count, FChart.Log.Count, line]));
    Exit;
  end;
  for i := 0 to AWant.Count - 1 do
  begin
    want := AWant.Objects[i];
    line := FChart.Log[i];
    t := Pos(#9, line);
    Inc(FCompared, 2);
    if Copy(line, 1, t - 1) <> want.Strings['type'] then
    begin
      Bad(Format('event %d is %s upstream, %s here', [i, want.Strings['type'], Copy(line, 1, t - 1)]));
      Continue;
    end;
    { A VIEW'S OWN DISPATCH (a node's or a breadcrumb item's click): its
      payload {type, from, seriesId, targetNode} key for key -- the view uid
      and the TreeNode (the port's its id) stand for themselves [R2-B: only
      the type was compared, the port named the series by index] }
    got := GetJSON(Copy(line, t + 1, MaxInt));
    try
      if not SameJson(want.Find('payload'), got) then
        Bad(Format('event %d (%s): %s upstream, %s here', [i, want.Strings['type'],
          want.Find('payload').AsJSON, got.AsJSON]));
    finally
      got.Free;
    end;
  end;
end;

procedure TAdvChartStatesHierOracleTest.CompareColour(const AWhat: string;
  const AWant, AWantRest: TJSONData; const AObj, ARest: TTyStObject; AKey: TTyStKey);
var
  ws, rs: string;
  want, lifted: TTyChartColor;
  has: Boolean;
begin
  Inc(FCompared);
  has := TyStHasColour(AObj, AKey);
  if (AWant = nil) or (AWant.JSONType = jtNull) then
  begin
    if has then Bad(AWhat + ': none upstream, a colour here');
    Exit;
  end;
  ws := AWant.AsString;
  rs := '';
  if (AWantRest <> nil) and (AWantRest.JSONType = jtString) then rs := AWantRest.AsString;
  if not has then
  begin
    Bad(AWhat + ': ' + ws + ' upstream, none here');
    Exit;
  end;
  if ws = rs then
  begin
    if not (TyStHasColour(ARest, AKey) and (ARest.Color[AKey] = AObj.Color[AKey])) then
      Bad(AWhat + ': the rest colour upstream, ' + IntToHex(AObj.Color[AKey], 8) + ' here');
    Exit;
  end;
  if (rs <> '') and JsLift(rs, lifted) and TyTryParseChartColor(ws, want) and (want = lifted) then
  begin
    if not (TyStHasColour(ARest, AKey) and (AObj.Color[AKey] = TyChartLiftColor(ARest.Color[AKey]))) then
      Bad(AWhat + ': the rest colour lifted upstream (' + ws + '), ' + IntToHex(AObj.Color[AKey], 8) + ' here');
    Exit;
  end;
  if ws = '#3c3c41' then want := FChart.Primary
  else if ws = '#f4f7fd' then want := FChart.CrumbHover
  else if not TyTryParseChartColor(ws, want) then
  begin
    Bad(AWhat + ': cannot read ' + ws);
    Exit;
  end;
  { a declared colour lifted (a select fill under emphasis) }
  if AObj.Color[AKey] <> want then
    Bad(AWhat + ': ' + ws + ' upstream, ' + IntToHex(AObj.Color[AKey], 8) + ' here');
end;

procedure TAdvChartStatesHierOracleTest.CompareEl(const AWhat: string; AWant: TJSONObject;
  const AEl: TTyStElement);
var
  rest: TJSONObject;
  v: Double;
begin
  Inc(FCompared);
  if AWant = nil then
  begin
    if AEl.Exists then Bad(AWhat + ': no element upstream, one here');
    Exit;
  end;
  if not AEl.Exists then
  begin
    Bad(AWhat + ': an element upstream, none here');
    Exit;
  end;
  rest := AWant.Objects['rest'];
  Inc(FCompared, 5);
  if TyStNamesText(AEl.States) <> AWant.Strings['st'] then
    Bad(Format('%s: states "%s" upstream, "%s" here', [AWhat, AWant.Strings['st'],
      TyStNamesText(AEl.States)]));
  if AEl.Selected <> AWant.Booleans['sel'] then
    Bad(Format('%s: selected %s upstream', [AWhat, BoolToStr(AWant.Booleans['sel'], True)]));
  if AEl.Proxy <> AWant.Booleans['px'] then
    Bad(Format('%s: proxy %s upstream', [AWhat, BoolToStr(AWant.Booleans['px'], True)]));
  if HexNum(AWant.Find('opacity'), v) and not SameBits(AEl.Cur.Num[stkOpacity], v) then
    Bad(Format('%s: opacity %s upstream, %s here', [AWhat, Fmt(v), Fmt(AEl.Cur.Num[stkOpacity])]));
  if Round(AEl.Cur.Num[stkZ2] - AEl.Rest.Num[stkZ2]) <> AWant.Integers['z2'] - rest.Integers['z2'] then
    Bad(Format('%s: z2 lift %d upstream, %s here', [AWhat, AWant.Integers['z2'] - rest.Integers['z2'],
      Fmt(AEl.Cur.Num[stkZ2] - AEl.Rest.Num[stkZ2])]));
  CompareColour(AWhat + ' fill', AWant.Find('fill'), rest.Find('fill'), AEl.Cur, AEl.Rest, stkFill);
  CompareColour(AWhat + ' stroke', AWant.Find('stroke'), rest.Find('stroke'), AEl.Cur, AEl.Rest, stkStroke);
  { a width is compared where a stroke is drawn }
  if TyStHasColour(AEl.Cur, stkStroke) and HexNum(AWant.Find('lineWidth'), v) then
  begin
    Inc(FCompared);
    if not SameBits(AEl.Cur.Num[stkLineWidth], v) then
      Bad(Format('%s: lineWidth %s upstream, %s here', [AWhat, Fmt(v), Fmt(AEl.Cur.Num[stkLineWidth])]));
  end;
end;

procedure TAdvChartStatesHierOracleTest.CompareText(const AWhat: string; AWant: TJSONData;
  const AEl: TTyStElement);
var
  w, rest: TJSONObject;
  v: Double;
  ign: Boolean;
begin
  Inc(FCompared);
  if not (AWant is TJSONObject) then
  begin
    { no text upstream: the port may hold none, or a hidden one }
    if AEl.Exists and (AEl.Cur.Num[stkIgnore] = 0) then Bad(AWhat + ': no label upstream, a shown one here');
    Exit;
  end;
  w := TJSONObject(AWant);
  rest := w.Objects['rest'];
  if not AEl.Exists then
  begin
    { a label upstream hides (and ignores) without being drawn here }
    if not w.Booleans['ignore'] then Bad(AWhat + ': a label upstream, none here');
    Exit;
  end;
  Inc(FCompared, 4);
  if TyStNamesText(AEl.States) <> w.Strings['st'] then
    Bad(Format('%s: states "%s" upstream, "%s" here', [AWhat, w.Strings['st'], TyStNamesText(AEl.States)]));
  ign := AEl.Cur.Num[stkIgnore] <> 0;
  if ign <> w.Booleans['ignore'] then
    Bad(Format('%s: ignore %s upstream', [AWhat, BoolToStr(w.Booleans['ignore'], True)]));
  if HexNum(w.Find('opacity'), v) and not SameBits(AEl.Cur.Num[stkOpacity], v) then
    Bad(Format('%s: opacity %s upstream, %s here', [AWhat, Fmt(v), Fmt(AEl.Cur.Num[stkOpacity])]));
  if HexNum(rest.Find('opacity'), v) and not SameBits(AEl.Rest.Num[stkOpacity], v) then
    Bad(Format('%s: rest opacity %s upstream, %s here', [AWhat, Fmt(v), Fmt(AEl.Rest.Num[stkOpacity])]));
  if Round(AEl.Cur.Num[stkZ2] - AEl.Rest.Num[stkZ2]) <> w.Integers['z2'] - rest.Integers['z2'] then
    Bad(Format('%s: z2 lift %d upstream, %s here', [AWhat, w.Integers['z2'] - rest.Integers['z2'],
      Fmt(AEl.Cur.Num[stkZ2] - AEl.Rest.Num[stkZ2])]));
end;

procedure TAdvChartStatesHierOracleTest.CompareCrumbs(ASeries: Integer; ACrumbs: TJSONArray);
var
  l: TTyPaintList;
  i, j, k, n, hi: Integer;
  el, cap: TTyChartElement;
  w, rest, tx: TJSONObject;
  want: TTyChartColor;
  ws: string;
begin
  l := FChart.List;
  n := 0;
  for i := 0 to l.Count - 1 do
  begin
    el := l.Element(i);
    if (el.Anim.Role <> carTmCrumb) or (el.Anim.Series <> ASeries) then Continue;
    k := el.Anim.Index;
    Inc(n);
    if k >= ACrumbs.Count then
    begin
      Bad(Format('crumb %d: none upstream', [k]));
      Continue;
    end;
    w := ACrumbs.Objects[k];
    rest := w.Objects['rest'];
    Inc(FCompared, 3);
    if el.Z2 - 100000 <> w.Integers['z2'] - rest.Integers['z2'] then
      Bad(Format('crumb %d: z2 lift %d upstream, %d here', [k, w.Integers['z2'] - rest.Integers['z2'], el.Z2 - 100000]));
    ws := w.Strings['fill'];
    if ws = '#f4f7fd' then want := FChart.CrumbHover
    else TyTryParseChartColor(ws, want);
    if el.Style.FillColor <> want then
      Bad(Format('crumb %d: fill %s upstream, %s here', [k, ws, IntToHex(el.Style.FillColor, 8)]));
    { its words }
    tx := w.Objects['text'];
    for j := 0 to l.Count - 1 do
    begin
      cap := l.Element(j);
      if cap.Caption.FontSizeLogical <= 0 then Continue;
      hi := cap.Caption.LmHostPlus1 - 1;
      if (hi < 0) or (hi >= l.Count) or (l.Element(hi).Anim.Role <> carTmCrumb)
        or (l.Element(hi).Anim.Index <> k) or (l.Element(hi).Anim.Series <> ASeries) then Continue;
      Inc(FCompared, 2);
      if cap.Z2 - 100002 <> tx.Integers['z2'] - tx.Objects['rest'].Integers['z2'] then
        Bad(Format('crumb %d words: z2 lift %d upstream, %d here', [k,
          tx.Integers['z2'] - tx.Objects['rest'].Integers['z2'], cap.Z2 - 100002]));
      if TyTryParseChartColor(tx.Strings['fill'], want) and (cap.Caption.Colour <> want) then
        Bad(Format('crumb %d words: ink %s upstream, %s here', [k, tx.Strings['fill'],
          IntToHex(cap.Caption.Colour, 8)]));
    end;
  end;
  Inc(FCompared);
  if n <> ACrumbs.Count then Bad(Format('%d crumbs upstream, %d here', [ACrumbs.Count, n]));
end;

{ the label's transform [m0..m5]: its anchor m4, m5 and its turn (m0 = cos,
  m1 = -sin under a unit scale) }
procedure TAdvChartStatesHierOracleTest.CompareEdgeLabel(const AWhat: string; ASeries,
  AEdge: Integer; AWant: TJSONObject);
var
  l: TTyPaintList;
  i: Integer;
  el: TTyChartElement;
  m: TJSONArray;
  m0, m1, m4, m5: Double;
  item: TTyStItem;
begin
  if not FChart.EdgeStates(ASeries, AEdge, item) or not item.Label_.Exists then Exit;
  m := AWant.Arrays['m'];
  HexNum(m.Items[0], m0);
  HexNum(m.Items[1], m1);
  HexNum(m.Items[4], m4);
  HexNum(m.Items[5], m5);
  l := FChart.List;
  for i := 0 to l.Count - 1 do
  begin
    el := l.Element(i);
    if (el.Caption.FontSizeLogical <= 0) or not el.Datum.IsEdge
      or (el.Datum.SeriesIndex <> ASeries) or (el.Caption.ItemSpec <> AEdge + 1) then Continue;
    Inc(FCompared, 3);
    if (Abs(el.Caption.FixedX - m4) > 1e-9) or (Abs(el.Caption.FixedY - m5) > 1e-9) then
      Bad(Format('%s: anchored at (%s, %s) upstream, (%s, %s) here', [AWhat, Fmt(m4), Fmt(m5),
        Fmt(el.Caption.FixedX), Fmt(el.Caption.FixedY)]));
    if (Abs(Cos(el.Caption.FixedRotationRad) - m0) > 1e-12)
      or (Abs(-Sin(el.Caption.FixedRotationRad) - m1) > 1e-12) then
      Bad(Format('%s: turned (%s, %s) upstream, %s rad here', [AWhat, Fmt(m0), Fmt(m1),
        Fmt(el.Caption.FixedRotationRad)]));
    Exit;
  end;
end;

{ [R2-B] A NODE'S LABEL WHERE IT IS DRAWN: its transform's translation (the
  anchor) -- on its symbol scaled under emphasis, as updateInnerText puts
  it; to 1e-9 (the port moves the rest anchor by the scaled box's) }
procedure TAdvChartStatesHierOracleTest.CompareNodeLabel(const AWhat: string; ASeries,
  ARow: Integer; AWant: TJSONObject);
var
  idx: Integer;
  el: TTyChartElement;
  m: TJSONArray;
  m4, m5: Double;
begin
  m := AWant.Arrays['m'];
  HexNum(m.Items[4], m4);
  HexNum(m.Items[5], m5);
  idx := FChart.StatePartIndex(ASeries, ARow, 'label');
  Inc(FCompared);
  if idx < 0 then
  begin
    if not AWant.Booleans['ignore'] then Bad(AWhat + ': no label element here');
    Exit;
  end;
  el := FChart.List.Element(idx);
  if (Abs(el.Caption.X - m4) > 1e-9) or (Abs(el.Caption.Y - m5) > 1e-9) then
    Bad(Format('%s: at (%s, %s) upstream, (%s, %s) here', [AWhat, Fmt(m4), Fmt(m5),
      Fmt(el.Caption.X), Fmt(el.Caption.Y)]));
end;

procedure TAdvChartStatesHierOracleTest.CompareSeries(ASer: TJSONObject);
var
  s, i, k: Integer;
  typ, w: string;
  arr, arrows: TJSONArray;
  o, p: TJSONObject;
  item: TTyStItem;
  idx: TTyIntegerArray;
  got: TJSONData;
  v, rsx: Double;
  n: Integer;
begin
  s := ASer.Integers['s'];
  typ := ASer.Strings['type'];
  { the selection }
  Inc(FCompared, 2);
  got := GetJSON(FChart.SelectedMapText(s));
  try
    if not SameJson(ASer.Find('selectedMap'), got) then
      Bad(Format('series %d: selectedMap %s upstream, %s here', [s, ASer.Find('selectedMap').AsJSON, got.AsJSON]));
  finally
    got.Free;
  end;
  idx := FChart.SelectedDataIndices(s);
  arr := ASer.Arrays['selectedIndices'];
  w := '';
  for k := 0 to High(idx) do w := w + IntToStr(idx[k]) + ',';
  if arr.AsJSON <> '[' + Copy(w, 1, Length(w) - 1) + ']' then
  begin
    { fpjson prints [0, 1]; compare the numbers }
    k := 0;
    if Length(idx) = arr.Count then
      for i := 0 to arr.Count - 1 do if arr.Integers[i] = idx[i] then Inc(k);
    if k <> arr.Count then Bad(Format('series %d: indices %s upstream, [%s] here', [s, arr.AsJSON, w]));
  end;
  if typ = 'graph' then
  begin
    arr := ASer.Arrays['nodes'];
    for i := 0 to arr.Count - 1 do
    begin
      if arr.Items[i].JSONType <> jtObject then Continue;
      o := arr.Objects[i];
      w := Format('s%d node %d', [s, i]);
      if not FChart.ItemStates(s, i, item) then
      begin
        Bad(w + ': no state record');
        Continue;
      end;
      Inc(FCompared, 2);
      if item.GroupHover <> o.Integers['hs'] then
        Bad(Format('%s: hover %d upstream, %d here', [w, o.Integers['hs'], item.GroupHover]));
      if (item.GroupHbo <> 0) <> (o.Integers['hbo'] <> 0) then Bad(w + ': hbo differs');
      p := o.Objects['path'];
      CompareEl(w, p, item.Host);
      { the symbol's scale: the rest scale times the port's ratio }
      if HexNum(p.Find('sx'), v) and HexNum(p.Find('rsx'), rsx) then
      begin
        Inc(FCompared);
        if item.Host.Cur.Has[stkScale] then rsx := rsx * item.Host.Cur.Num[stkScale];
        if not SameBits(rsx, v) then Bad(Format('%s: scale %s upstream, %s here', [w, Fmt(v), Fmt(rsx)]));
      end;
      CompareText(w + ' label', o.Find('label'), item.Label_);
      if (o.Find('label') is TJSONObject) and (o.Objects['label'].Find('m') <> nil) then
        CompareNodeLabel(w + ' label', s, i, o.Objects['label']);
    end;
    arr := ASer.Arrays['edges'];
    for i := 0 to arr.Count - 1 do
    begin
      if arr.Items[i].JSONType <> jtObject then Continue;
      o := arr.Objects[i];
      w := Format('s%d edge %d', [s, i]);
      if not FChart.EdgeStates(s, i, item) then
      begin
        Bad(w + ': no state record');
        Continue;
      end;
      Inc(FCompared, 2);
      if item.Host.HoverState <> o.Integers['hs'] then
        Bad(Format('%s: hover %d upstream, %d here', [w, o.Integers['hs'], item.Host.HoverState]));
      if (item.Host.HighByOuter <> 0) <> (o.Integers['hbo'] <> 0) then Bad(w + ': hbo differs');
      CompareEl(w, o.Objects['line'], item.Host);
      { the arrows: the parts, in order, where upstream has them }
      arrows := o.Arrays['arrows'];
      n := 0;
      for k := 0 to arrows.Count - 1 do
      begin
        if arrows.Items[k].JSONType <> jtObject then Continue;
        if n > High(item.Parts) then
        begin
          Bad(w + ': an arrow upstream, none here');
          Break;
        end;
        CompareEl(Format('%s arrow %d', [w, k]), arrows.Objects[k], item.Parts[n]);
        Inc(n);
      end;
      CompareText(w + ' label', o.Find('label'), item.Label_);
      if o.Find('label') is TJSONObject then CompareEdgeLabel(w + ' label', s, i, o.Objects['label']);
    end;
  end
  else if typ = 'tree' then
  begin
    arr := ASer.Arrays['nodes'];
    for i := 0 to arr.Count - 1 do
    begin
      if arr.Items[i].JSONType <> jtObject then Continue;
      o := arr.Objects[i];
      w := Format('s%d tree node %d', [s, i]);
      if not FChart.ItemStates(s, i, item) then
      begin
        Bad(w + ': no state record');
        Continue;
      end;
      Inc(FCompared, 2);
      if item.GroupHover <> o.Integers['hs'] then
        Bad(Format('%s: hover %d upstream, %d here', [w, o.Integers['hs'], item.GroupHover]));
      if (item.GroupHbo <> 0) <> (o.Integers['hbo'] <> 0) then Bad(w + ': hbo differs');
      p := o.Objects['path'];
      CompareEl(w, p, item.Host);
      if HexNum(p.Find('sx'), v) and HexNum(p.Find('rsx'), rsx) then
      begin
        Inc(FCompared);
        if item.Host.Cur.Has[stkScale] then rsx := rsx * item.Host.Cur.Num[stkScale];
        if not SameBits(rsx, v) then Bad(Format('%s: scale %s upstream, %s here', [w, Fmt(v), Fmt(rsx)]));
      end;
      CompareText(w + ' label', o.Find('label'), item.Label_);
      if (o.Find('label') is TJSONObject) and (o.Objects['label'].Find('m') <> nil) then
        CompareNodeLabel(w + ' label', s, i, o.Objects['label']);
      { the edge it draws }
      if o.Find('edge') is TJSONObject then
      begin
        if not FChart.EdgeStates(s, i, item) then
          Bad(w + ': an edge upstream, no record here')
        else
        begin
          Inc(FCompared);
          if item.Host.HoverState <> o.Objects['edge'].Integers['hs'] then
            Bad(Format('%s edge: hover %d upstream, %d here', [w, o.Objects['edge'].Integers['hs'],
              item.Host.HoverState]));
          CompareEl(w + ' edge', o.Objects['edge'], item.Host);
        end;
      end;
    end;
  end
  else if typ = 'treemap' then
  begin
    arr := ASer.Arrays['nodes'];
    for i := 0 to arr.Count - 1 do
    begin
      if arr.Items[i].JSONType <> jtObject then Continue;
      o := arr.Objects[i];
      w := Format('s%d treemap node %d', [s, i]);
      if not FChart.ItemStates(s, i, item) then
      begin
        Bad(w + ': no state record');
        Continue;
      end;
      Inc(FCompared, 2);
      if o.Find('hs') is TJSONNumber then
      begin
        if item.HasGroup then k := item.GroupHover else k := item.Host.HoverState;
        if k <> o.Integers['hs'] then
          Bad(Format('%s: hover %d upstream, %d here', [w, o.Integers['hs'], k]));
        if item.HasGroup then k := item.GroupHbo else k := item.Host.HighByOuter;
        if (k <> 0) <> (o.Integers['hbo'] <> 0) then Bad(w + ': hbo differs');
      end;
      if o.Booleans['leaf'] then
      begin
        CompareEl(w + ' content', o.Objects['content'], item.Host);
        CompareText(w + ' label', o.Objects['content'].Find('label'), item.Label_);
        if o.Find('bg') is TJSONObject then
        begin
          if Length(item.Parts) = 0 then Bad(w + ': a background upstream, none here')
          else CompareEl(w + ' background', o.Objects['bg'], item.Parts[0]);
        end;
      end
      else
      begin
        CompareEl(w + ' background', o.Objects['bg'], item.Host);
        CompareText(w + ' header', o.Objects['bg'].Find('label'), item.Label_);
      end;
    end;
    CompareCrumbs(s, ASer.Arrays['crumbs']);
  end
  else
  begin
    { the other series of a cross-series case: their items' lists and
      opacity }
    arr := ASer.Arrays['items'];
    for i := 0 to arr.Count - 1 do
    begin
      if arr.Items[i].JSONType <> jtObject then Continue;
      w := Format('s%d item %d', [s, i]);
      if not FChart.ItemStates(s, i, item) then
      begin
        Bad(w + ': no state record');
        Continue;
      end;
      CompareEl(w, arr.Objects[i], item.Host);
    end;
  end;
end;

procedure TAdvChartStatesHierOracleTest.TestStatesAsUpstream;
var
  cases, steps, ser: TJSONArray;
  cs, st: TJSONObject;
  c, k, i: Integer;
  typ: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FWhere := cs.Strings['id'] + ' init';
    NewChart(cs.Objects['option']);
    steps := cs.Arrays['steps'];
    for k := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[k];
      FWhere := Format('%s step %d', [cs.Strings['id'], k]);
      typ := st.Strings['type'];
      FChart.Log.Clear;
      if (typ = 'move') and (GetEnvironmentVariable('SH_DEBUG') = '1') then
        WriteLn(FWhere, ' ', FChart.TargetText(st.Integers['x'], st.Integers['y']));
      if typ = 'move' then
        FChart.MouseMove([], st.Integers['x'], st.Integers['y'])
      else if typ = 'click' then
      begin
        FChart.MouseMove([], st.Integers['x'], st.Integers['y']);
        FChart.MouseDown(mbLeft, [ssLeft], st.Integers['x'], st.Integers['y']);
        FChart.MouseUp(mbLeft, [], st.Integers['x'], st.Integers['y']);
      end
      else if typ = 'leave' then
        FChart.MouseMove([], -50, -50)
      else if typ = 'action' then
        FChart.DispatchAction(st.Objects['payload'].AsJSON);
      if typ <> 'init' then
      begin
        FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
        Inc(FSteps);
        CompareEvents(st.Arrays['events']);
      end;
      ser := st.Objects['state'].Arrays['series'];
      for i := 0 to ser.Count - 1 do CompareSeries(ser.Objects[i]);
    end;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s', [FBad, FCompared, FReport]),
    FBad = 0);
  AssertTrue(Format('the steps ran (%d) and a good deal was compared (%d)', [FSteps, FCompared]),
    (FSteps >= 80) and (FCompared >= 5000));
end;

{ ==================== what the oracle does not reach ==================== }

const
  T0 = 1700000000000.0;
  T1 = T0 + 10000;
  cGraph = '{"series":[{"type":"graph","layout":"none","symbolSize":30,"left":100,"top":100,'
    + '"width":300,"height":150,"lineStyle":{"color":"#888888","width":2},'
    + '"data":[{"name":"a","x":100,"y":100,"itemStyle":{"color":"#5070dd"}},'
    + '{"name":"b","x":300,"y":100,"itemStyle":{"color":"#b6d634"}},'
    + '{"name":"c","x":200,"y":250,"itemStyle":{"color":"#505372"}}],'
    + '"links":[{"source":"a","target":"b"},{"source":"b","target":"c"}]}]}';
  cTreemap = '{"series":[{"type":"treemap","roam":false,"nodeClick":false,'
    + '"breadcrumb":{"show":false},"emphasis":{"focus":"self"},'
    + '"data":[{"name":"A","children":[{"name":"a1","value":6,"itemStyle":{"color":"#b6d634"}},'
    + '{"name":"a2","value":4,"itemStyle":{"color":"#505372"}}]},'
    + '{"name":"B","value":8,"itemStyle":{"color":"#ff994d"}}]}]}';
  cTree = '{"series":[{"type":"tree","expandAndCollapse":false,"left":60,"top":40,'
    + '"bottom":40,"right":160,"symbol":"circle","itemStyle":{"color":"#5070dd"},'
    + '"lineStyle":{"color":"#999999","width":2},'
    + '"data":[{"name":"root","children":[{"name":"A","children":[{"name":"A1"}]}]}]}]}';

procedure TAdvChartStatesHierTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartStatesHierTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartStatesHierTest.NewChart(const AOption: string; AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TShProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Option := AOption;
  Draw;
end;

procedure TAdvChartStatesHierTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

procedure TAdvChartStatesHierTest.Settle(AStart: Double);
var t: Integer;
begin
  t := 16;
  while t <= 5000 do
  begin
    FChart.AnimNow := AStart + t;
    FChart.AnimTick(AStart + t);
    Inc(t, 250);
  end;
  Draw;
end;

{ a graph's edge is a Line group of its own: its path's proxy runs the
  stroke's lift over the series' 300 ms }
procedure TAdvChartStatesHierTest.TestAGraphEdgeHighlightTransitionsOnItsOwnProxy;
var
  p: TTyChartAnimProxy;
  c: TTyChartColor;
  item: TTyStItem;
begin
  NewChart(cGraph, camAlways);
  Settle(T0);
  FChart.AnimNow := T1;
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataType":"edge","dataIndex":1}');
  Draw;
  AssertTrue('the edge is in emphasis', FChart.EdgeStates(0, 1, item)
    and (stnEmphasis in item.Host.States));
  AssertTrue('a transition runs', FChart.AnimLive);
  p := FChart.AnimStateProxy(0, 1, 'edge');
  AssertNotNull('the edge has a proxy of its own', p);
  FChart.AnimTick(T1 + 1);
  FChart.AnimTick(T1 + 150);
  AssertTrue(TyTryParseChartColor(p.GetAnimProp('style.stroke').Str, c));
  AssertTrue('half way the stroke is neither the rest nor the lift',
    (c <> TTyChartColor($FF888888)) and (c <> TyChartLiftColor(TTyChartColor($FF888888))));
  FChart.AnimTick(T1 + 400);
  AssertFalse('at rest', FChart.AnimLive);
  AssertTrue(TyTryParseChartColor(p.GetAnimProp('style.stroke').Str, c));
  AssertEquals('the lift at the end', IntToHex(TyChartLiftColor(TTyChartColor($FF888888)), 8),
    IntToHex(c, 8));
end;

{ a leaf's group: the content hosts, the background is a part -- each on a
  proxy of its own, the two lists the same }
procedure TAdvChartStatesHierTest.TestATreemapLeafsBackgroundAndContentTransitionTogether;
var
  host, part: TTyChartAnimProxy;
  item: TTyStItem;
begin
  NewChart(cTreemap, camAlways);
  Settle(T0);
  FChart.AnimNow := T1;
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":2}');
  Draw;
  AssertTrue(FChart.ItemStates(0, 2, item));
  AssertEquals('a leaf has its background as a part', 1, Length(item.Parts));
  AssertEquals('one list', TyStNamesText(item.Host.States), TyStNamesText(item.Parts[0].States));
  host := FChart.AnimStateProxy(0, 2, 'host');
  part := FChart.AnimStateProxy(0, 2, 'part0');
  AssertNotNull('the content''s proxy', host);
  AssertNotNull('the background''s proxy', part);
  AssertEquals('both in emphasis', host.CurrentStates, part.CurrentStates);
  AssertTrue('a transition runs', FChart.AnimLive);
end;

{ a tree node's edge follows it into emphasis (its parent not blurred) and
  transitions on its own proxy }
procedure TAdvChartStatesHierTest.TestATreeNodesEdgeTransitionsWhenItFollows;
var
  item: TTyStItem;
  p: TTyChartAnimProxy;
begin
  NewChart(cTree, camAlways);
  Settle(T0);
  FChart.AnimNow := T1;
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":2}');
  Draw;
  AssertTrue('the node''s edge', FChart.EdgeStates(0, 2, item));
  AssertEquals('it followed the node', TyStHoverEmphasis, item.Host.HoverState);
  p := FChart.AnimStateProxy(0, 2, 'edge');
  AssertNotNull('on a proxy of its own', p);
  AssertEquals('emphasis', 'emphasis', p.CurrentStates);
end;

{ no timer (camOff): the list itself takes the state values at once -- a
  highlighted graph node grown and lifted in the static list }
procedure TAdvChartStatesHierTest.TestWithoutAProxyTheListTakesTheStatesAtOnce;
var
  i: Integer;
  el: TTyChartElement;
  found: Boolean;
  rest: Double;
begin
  NewChart(cGraph, camOff);
  rest := NaN;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (el.Datum.SeriesIndex = 0) and not el.Datum.IsEdge and (el.Datum.DataIndex = 0)
      and (el.Caption.FontSizeLogical <= 0) then rest := el.Shape.R1;
  end;
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":0}');
  Draw;
  found := False;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (el.Datum.SeriesIndex <> 0) or el.Datum.IsEdge or (el.Datum.DataIndex <> 0)
      or (el.Caption.FontSizeLogical > 0) then Continue;
    found := True;
    AssertEquals('lifted', IntToHex(TyChartLiftColor(TTyChartColor($FF5070DD)), 8),
      IntToHex(el.Style.FillColor, 8));
    AssertEquals('grown by max(1.1, 3/15) about its centre', rest * 1.1, el.Shape.R1, 1e-9);
  end;
  AssertTrue('the node is drawn', found);
end;

initialization
  RegisterTest(TAdvChartStatesHierOracleTest);
  RegisterTest(TAdvChartStatesHierTest);
end.
