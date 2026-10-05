unit test.advchart.treeinteract;
{$mode objfpc}{$H+}
{ TREE INTERACTION -- a click or the API expanding and collapsing a node,
  the view a zoom, a centre or a roam leaves, and a hover's emphasis --
  held to what ECharts 6.1 draws after each step.

  tools/advchart-oracle/tree-interact.js replays each case's steps on the
  real chart and records the frame after every one. The port replays the
  same steps on the control -- the API for a toggle and a roam action, real
  mouse presses for a click, a drag and a wheel -- and its paint list is
  compared with the frame, in GLOBAL coordinates: a node where its symbol's
  transform puts it, an edge through the main group's transform, a label
  where its own transform puts it.

  Upstream's animation-free redraw leaves ghost edges behind a collapse; the
  fixture records the clean frame, which is what the port draws.

  THE HOVERED NODE'S LABEL, when it sits outside its node, is passed over,
  counted: upstream lays it against the grown symbol and the port keeps it
  where the normal one put it. Its lifted fill, a theme colour, likewise. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvChart.Graph, tyControls.AdvChart.Tooltip,
     tyControls.AdvanceChart;
type
  TTiProbe = class(TTyAdvanceChart)
  public
    Events: TStringList;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    procedure Wheel(AX, AY, ADelta: Integer);
    procedure Hover(AX, AY: Integer);
    function ContentFor(ARow: Integer): TTyTooltipBlock;
    procedure Toggled(Sender: TObject; ASeriesIndex, ADataIndex: Integer);
    procedure Roamed(Sender: TObject; const APayload: TTyGraphRoamPayload);
  end;

  TAdvChartTreeInteractOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTiProbe;
    FRoot: TJSONData;
    FBad, FCompared, FStates, FNodes, FEdges, FLabels, FSkipped: Integer;
    FReport, FName: string;
    FNoView: Boolean;
    { the row a hover step is over, or -1 }
    FHoverRow: Integer;
    FHoverLabelsPassed: Integer;
    procedure Miss(const AWhat: string);
    procedure CompareState(AState: TJSONObject);
    procedure CompareHover(AHover: TJSONObject; AScale: Double);
    procedure RunPart(const APart: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestClicksAndTogglesAsUpstream;
    procedure TestTheViewAndItsRoamAsUpstream;
    procedure TestTheHoverAsUpstream;
    procedure TestTheTooltipAsUpstream;
    procedure TestPressOnTheLabelReleaseOnTheDiscIsNoClick;
  end;

implementation

procedure TTiProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TTiProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TTiProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [ssLeft], AX, AY);
end;

procedure TTiProbe.Move(AX, AY: Integer);
begin
  MouseMove([ssLeft], AX, AY);
end;

procedure TTiProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

function TTiProbe.ContentFor(ARow: Integer): TTyTooltipBlock;
var d: TTyChartDatumRef;
begin
  d := TyChartDatum(0, ARow, ARow);
  Result := TooltipContent(d, TooltipSpecFor(d));
end;

procedure TTiProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TTiProbe.Wheel(AX, AY, ADelta: Integer);
begin
  DoMouseWheel([], ADelta, Point(AX, AY));
end;

procedure TTiProbe.Toggled(Sender: TObject; ASeriesIndex, ADataIndex: Integer);
begin
  if Events <> nil then Events.Add('toggle ' + IntToStr(ADataIndex));
end;

procedure TTiProbe.Roamed(Sender: TObject; const APayload: TTyGraphRoamPayload);
begin
  if Events <> nil then Events.Add('roam');
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-tree-interact.json';
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function Same(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  if (A = 0) and (B = 0) then Exit(True);
  Result := Bits(A) = Bits(B);
end;

function Near(A, B: Double): Boolean;
begin
  Result := Abs(A - B) <= 1e-9 * Max(1, Abs(B));
end;

function Num(A: TJSONData): Double;
begin
  if (A = nil) or (A.JSONType = jtNull) then Exit(NaN);
  if A.JSONType = jtString then
  begin
    if A.AsString = '-0' then Exit(-0.0);
    if A.AsString = 'Infinity' then Exit(Infinity);
    if A.AsString = '-Infinity' then Exit(NegInfinity);
    Exit(NaN);
  end;
  Result := A.AsFloat;
end;

procedure TAdvChartTreeInteractOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TTiProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Events := TStringList.Create;
  FChart.OnTreeExpandAndCollapse := @FChart.Toggled;
  FChart.OnTreeRoam := @FChart.Roamed;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FStates := 0;
  FNodes := 0;
  FEdges := 0;
  FLabels := 0;
  FSkipped := 0;
  FReport := '';
end;

procedure TAdvChartTreeInteractOracleTest.TearDown;
begin
  FRoot.Free;
  FChart.Events.Free;
  FChart.Events := nil;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartTreeInteractOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

{ one recorded frame against the paint list }
procedure TAdvChartTreeInteractOracleTest.CompareState(AState: TJSONObject);
var
  rows, edges: TJSONArray;
  row, sy, lb, ed, sh, st: TJSONObject;
  mt: TJSONArray;
  lst: TTyPaintList;
  e: TTyChartElement;
  n, k, j, ri: Integer;
  symAt, capAt, edgeAt: array of Integer;
  cx, cy, z, mx, my, lx, ly: Double;
  b: TTyRectF;
  w_: string;
  want: TTyChartColor;
  d: TJSONData;

  function GX(AX, AY: Double): Double;
  begin
    { zrender's matrix: (m0*x + m2*y) + m4 }
    Result := (z * AX + 0 * AY) + mx;
  end;
  function GY(AX, AY: Double): Double;
  begin
    Result := (0 * AX + z * AY) + my;
  end;

begin
  Inc(FStates);
  lst := FChart.List;
  rows := AState.Arrays['rows'];
  n := rows.Count;
  SetLength(symAt, 0); SetLength(capAt, 0); SetLength(edgeAt, 0);
  SetLength(symAt, n); SetLength(capAt, n); SetLength(edgeAt, n);
  for k := 0 to n - 1 do
  begin
    symAt[k] := -1;
    capAt[k] := -1;
    edgeAt[k] := -1;
  end;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Datum.SeriesIndex <> 0) or (e.Datum.DataIndex < 0) or (e.Datum.DataIndex >= n) then Continue;
    if (e.Caption.FontSizeLogical > 0) and (e.Caption.Text <> '') then
      capAt[e.Datum.DataIndex] := k
    else if e.Z2 >= 100 then
      symAt[e.Datum.DataIndex] := k
    else
      edgeAt[e.Datum.DataIndex] := k;
  end;
  mt := AState.Objects['view'].Arrays['mainTransform'];
  z := Num(mt.Items[0]);
  mx := Num(mt.Items[4]);
  my := Num(mt.Items[5]);
  for ri := 0 to n - 1 do
  begin
    row := rows.Objects[ri];
    w_ := Format('row %d (%s)', [ri, row.Get('name', '')]);
    { expanded or not, as the API answers it }
    if ri > 0 then
    begin
      Inc(FCompared);
      if row.Get('isExpand', True) <> FChart.TreeExpanded(0, ri) then
        Miss(Format('%s: expanded %s upstream, %s here', [w_,
          BoolToStr(row.Get('isExpand', True), True), BoolToStr(FChart.TreeExpanded(0, ri), True)]));
    end;
    Inc(FCompared);
    if row.Get('drawn', False) <> (symAt[ri] >= 0) then
    begin
      if row.Get('drawn', False) then Miss(w_ + ': a node upstream, none here')
      else Miss(w_ + ': no node upstream, one here');
      Continue;
    end;
    if not row.Get('drawn', False) then Continue;
    Inc(FNodes);
    sy := row.Objects['symbol'];
    e := lst.Element(symAt[ri]);
    b := TyShapeBounds(e.Shape);
    { the symbol's own transform: its centre, and its half-size as its scale }
    cx := Num(sy.Arrays['transform'].Items[4]);
    cy := Num(sy.Arrays['transform'].Items[5]);
    Inc(FCompared, 2);
    if (e.Shape.Kind = cskCircle) and not (Same(e.Shape.CX, cx) and Same(e.Shape.CY, cy)) then
      Miss(Format('%s: at (%s, %s) upstream, (%s, %s) here', [w_, Fmt(cx), Fmt(cy),
        Fmt(e.Shape.CX), Fmt(e.Shape.CY)]))
    else if (e.Shape.Kind <> cskCircle) and not (Near((b.Left + b.Right) / 2, cx)
      and Near((b.Top + b.Bottom) / 2, cy)) then
      Miss(Format('%s: centred at (%s, %s) upstream, (%s, %s) here', [w_, Fmt(cx), Fmt(cy),
        Fmt((b.Left + b.Right) / 2), Fmt((b.Top + b.Bottom) / 2)]));
    if sy.Get('pathType', '') = 'circle' then
      if not Near(b.Right - b.Left, 2 * Num(sy.Arrays['transform'].Items[0])) then
        Miss(Format('%s: %s across upstream, %s here', [w_,
          Fmt(2 * Num(sy.Arrays['transform'].Items[0])), Fmt(b.Right - b.Left)]));
    { solid when it hides children }
    st := sy.Objects['ink'];
    if ri = FHoverRow then
      { lifted from the theme's colour: not comparable }
    else if sy.Get('emptyBrush', False) then
    begin
      Inc(FCompared);
      if (st.Get('fill', '') = st.Get('stroke', '')) and (e.Style.FillColor <> e.Style.StrokeColor) then
        Miss(w_ + ': solid upstream, hollow here')
      else if (st.Get('fill', '') <> st.Get('stroke', '')) and (e.Style.FillColor = e.Style.StrokeColor) then
        Miss(w_ + ': hollow upstream, solid here');
    end
    else if (st.Get('fill', '') <> 'lightsteelblue') and TyTryParseChartColor(st.Get('fill', ''), want) then
    begin
      Inc(FCompared);
      if e.Style.FillColor <> want then Miss(w_ + ': the fill differs');
    end;
    { its label }
    d := row.Find('label');
    Inc(FCompared);
    if (d = nil) or (d.JSONType <> jtObject) or (TJSONObject(d).Get('text', '') = '') then
    begin
      if capAt[ri] >= 0 then Miss(w_ + ': no label upstream, one here');
      Continue;
    end;
    lb := TJSONObject(d);
    if capAt[ri] < 0 then
    begin
      Miss(w_ + ': label upstream, none here');
      Continue;
    end;
    Inc(FLabels);
    e := lst.Element(capAt[ri]);
    lx := Num(lb.Arrays['transform'].Items[4]);
    ly := Num(lb.Arrays['transform'].Items[5]);
    if (ri = FHoverRow) and (lb.Objects['textConfig'].Get('position', 'inside') <> 'inside') then
    begin
      Inc(FHoverLabelsPassed);
      lx := e.Caption.X;
      ly := e.Caption.Y;
    end;
    Inc(FCompared, 2);
    if e.Caption.Text <> lb.Get('text', '') then
      Miss(Format('%s: label "%s" upstream, "%s" here', [w_, lb.Get('text', ''), e.Caption.Text]));
    if not (Same(e.Caption.X, lx) and Same(e.Caption.Y, ly)) then
      Miss(Format('%s: label at (%s, %s) upstream, (%s, %s) here [%x %x / %x %x]', [w_, Fmt(lx), Fmt(ly),
        Fmt(e.Caption.X), Fmt(e.Caption.Y), Bits(lx), Bits(ly), Bits(e.Caption.X), Bits(e.Caption.Y)]));
  end;
  { the edges: curves by the row they lead to, forks by their owner }
  edges := AState.Arrays['edges'];
  for j := 0 to edges.Count - 1 do
  begin
    ed := edges.Objects[j];
    if ed.Get('kind', '') = 'curve' then ri := ed.Arrays['to'].Integers[0]
    else ri := ed.Integers['owner'];
    w_ := Format('%s edge of row %d', [ed.Get('kind', ''), ri]);
    Inc(FCompared);
    if (ri < 0) or (ri >= n) or (edgeAt[ri] < 0) then
    begin
      Miss(w_ + ': drawn upstream, not here');
      Continue;
    end;
    Inc(FEdges);
    e := lst.Element(edgeAt[ri]);
    if ed.Get('kind', '') = 'curve' then
    begin
      sh := ed.Objects['shape'];
      Inc(FCompared);
      if (Length(e.Shape.Cmds) <> 2) or not (Same(e.Shape.Cmds[0].X, GX(Num(sh.Find('x1')), Num(sh.Find('y1'))))
        and Same(e.Shape.Cmds[0].Y, GY(Num(sh.Find('x1')), Num(sh.Find('y1'))))
        and Same(e.Shape.Cmds[1].X1, GX(Num(sh.Find('cpx1')), Num(sh.Find('cpy1'))))
        and Same(e.Shape.Cmds[1].Y1, GY(Num(sh.Find('cpx1')), Num(sh.Find('cpy1'))))
        and Same(e.Shape.Cmds[1].X2, GX(Num(sh.Find('cpx2')), Num(sh.Find('cpy2'))))
        and Same(e.Shape.Cmds[1].Y2, GY(Num(sh.Find('cpx2')), Num(sh.Find('cpy2'))))
        and Same(e.Shape.Cmds[1].X, GX(Num(sh.Find('x2')), Num(sh.Find('y2'))))
        and Same(e.Shape.Cmds[1].Y, GY(Num(sh.Find('x2')), Num(sh.Find('y2'))))) then
        Miss(w_ + ': the curve differs');
    end
    else
    begin
      Inc(FCompared);
      if Length(e.Shape.Cmds) <> ed.Arrays['commands'].Count then
        Miss(Format('%s: %d commands upstream, %d here', [w_, ed.Arrays['commands'].Count,
          Length(e.Shape.Cmds)]))
      else
        for k := 0 to High(e.Shape.Cmds) do
          if not (Same(e.Shape.Cmds[k].X, GX(Num(ed.Arrays['commands'].Objects[k].Arrays['args'].Items[0]),
              Num(ed.Arrays['commands'].Objects[k].Arrays['args'].Items[1])))
            and Same(e.Shape.Cmds[k].Y, GY(Num(ed.Arrays['commands'].Objects[k].Arrays['args'].Items[0]),
              Num(ed.Arrays['commands'].Objects[k].Arrays['args'].Items[1])))) then
          begin
            Miss(Format('%s: command %d differs', [w_, k]));
            Break;
          end;
    end;
  end;
  { none here that upstream does not draw }
  for ri := 0 to n - 1 do
    if edgeAt[ri] >= 0 then
    begin
      k := 0;
      for j := 0 to edges.Count - 1 do
        if ((edges.Objects[j].Get('kind', '') = 'curve') and (edges.Objects[j].Arrays['to'].Integers[0] = ri))
          or ((edges.Objects[j].Get('kind', '') <> 'curve') and (edges.Objects[j].Integers['owner'] = ri)) then
          k := 1;
      Inc(FCompared);
      if k = 0 then Miss(Format('an edge of row %d here, none upstream', [ri]));
    end;
end;

{ what a hover left on each row: the symbol's opacity, order and size, its
  label's opacity and order, its own edge's opacity and order }
procedure TAdvChartTreeInteractOracleTest.CompareHover(AHover: TJSONObject; AScale: Double);
var
  els: TJSONArray;
  h, sy, lb, ed: TJSONObject;
  lst: TTyPaintList;
  e: TTyChartElement;
  k, j, row: Integer;
  w_: string;
  found: Boolean;

  procedure Check(const AWhat: string; AWantOp: Double; AWantZ2: Integer; const AEl: TTyChartElement);
  begin
    Inc(FCompared, 2);
    if Abs(AEl.Style.Alpha - AWantOp) > 1e-12 then
      Miss(Format('%s: opacity %s upstream, %s here', [AWhat, Fmt(AWantOp), Fmt(AEl.Style.Alpha)]));
    if AEl.Z2 <> AWantZ2 then
      Miss(Format('%s: z2 %d upstream, %d here', [AWhat, AWantZ2, AEl.Z2]));
  end;

begin
  lst := FChart.List;
  els := AHover.Arrays['elements'];
  for k := 0 to els.Count - 1 do
  begin
    h := els.Objects[k];
    row := h.Integers['row'];
    for j := 0 to lst.Count - 1 do
    begin
      e := lst.Element(j);
      if (e.Datum.SeriesIndex <> 0) or (e.Datum.DataIndex <> row) then Continue;
      if (e.Caption.FontSizeLogical > 0) and (e.Caption.Text <> '') then
      begin
        if h.Find('label') is TJSONObject then
        begin
          lb := h.Objects['label'];
          w_ := Format('row %d label', [row]);
          Check(w_, Num(lb.Find('opacity')), lb.Integers['z2'], e);
        end;
      end
      else if e.Z2 >= 100 then
      begin
        if h.Find('symbol') is TJSONObject then
        begin
          sy := h.Objects['symbol'];
          w_ := Format('row %d symbol', [row]);
          Check(w_, Num(sy.Find('opacity')), sy.Integers['z2'], e);
          Inc(FCompared);
          { the local scale through the view's zoom and compensation }
          if (e.Shape.Kind = cskCircle) and not Near(e.Shape.R1, AScale * Num(sy.Find('scaleX'))) then
            Miss(Format('%s: half-size %s upstream, %s here', [w_,
              Fmt(AScale * Num(sy.Find('scaleX'))), Fmt(e.Shape.R1)]));
        end;
      end
      else if h.Find('edge') is TJSONObject then
      begin
        ed := h.Objects['edge'];
        Check(Format('row %d edge', [row]), Num(ed.Find('opacity')), ed.Integers['z2'], e);
      end;
    end;
  end;
end;

procedure TAdvChartTreeInteractOracleTest.RunPart(const APart: string);
var
  cases, steps, states, evs: TJSONArray;
  cs, st: TJSONObject;
  c, k, j, W, H, want: Integer;
  bmp: TBGRABitmap;
  text, kind: string;
  p: TTyGraphRoamPayload;
  path: TJSONArray;
  wantRoam, gotRoam: Integer;

  procedure Paint;
  begin
    bmp.SetSize(W, H);
    FChart.SetBounds(0, 0, W, H);
    FChart.Render(bmp.Canvas, Classes.Rect(0, 0, W, H), 96);
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  try
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      if cs.Get('part', '') <> APart then Continue;
      if FNoView and ((Pos('"zoom"', cs.Objects['option'].AsJSON) > 0)
        or (Pos('"center"', cs.Objects['option'].AsJSON) > 0)) then
      begin
        Inc(FSkipped);
        Continue;
      end;
      FName := cs.Get('id', '');
      steps := cs.Arrays['steps'];
      states := cs.Arrays['states'];
      text := cs.Objects['option'].AsJSON;
      W := states.Objects[0].Get('W', 800);
      H := states.Objects[0].Get('H', 600);
      FChart.Option := '';
      FChart.Option := text;
      FChart.Events.Clear;
      try
        Paint;
      except
        on E: Exception do
        begin
          Miss(E.ClassName + ': ' + E.Message);
          Continue;
        end;
      end;
      FHoverRow := -1;
      CompareState(states.Objects[0]);
      for k := 0 to steps.Count - 1 do
      begin
        st := steps.Objects[k];
        kind := st.Get('type', '');
        FName := Format('%s step %d (%s)', [cs.Get('id', ''), k + 1, kind]);
        { a step that turns on zrender's exact hit geometry -- the port's
          targets are more forgiving -- ends the replay }
        if st.Get('hitSensitive', False) then
        begin
          Inc(FSkipped);
          Break;
        end;
        FChart.Events.Clear;
        if kind = 'hover' then FHoverRow := st.Get('row', -1) else FHoverRow := -1;
        if kind = 'toggle' then
          FChart.TreeToggle(st.Get('seriesIndex', 0), st.Get('dataIndex', 0))
        else if kind = 'click' then
        begin
          if GetEnvironmentVariable('TI_DEBUG') = '1' then
            with FChart.HitTestAt(st.Get('x', 0), st.Get('y', 0)) do
              WriteLn(Format('DEBUG %s hit series %d row %d edge %s', [FName, SeriesIndex,
                DataIndex, BoolToStr(IsEdge, True)]));
          FChart.Down(st.Get('x', 0), st.Get('y', 0));
          { the pointer travels to the release point: a roam pans that far }
          if (st.Get('upX', st.Get('x', 0)) <> st.Get('x', 0))
            or (st.Get('upY', st.Get('y', 0)) <> st.Get('y', 0)) then
            FChart.Move(st.Get('upX', st.Get('x', 0)), st.Get('upY', st.Get('y', 0)));
          FChart.Up(st.Get('upX', st.Get('x', 0)), st.Get('upY', st.Get('y', 0)));
        end
        else if (kind = 'roam') or (kind = 'zoom') then
        begin
          p := Default(TTyGraphRoamPayload);
          p.SeriesIndex := st.Get('seriesIndex', -1);
          { a pan only when both deltas are there }
          p.HasPan := (st.Find('dx') <> nil) and (st.Find('dy') <> nil);
          p.DX := st.Get('dx', 0.0);
          p.DY := st.Get('dy', 0.0);
          p.HasZoom := st.Find('factor') <> nil;
          p.Zoom := st.Get('factor', 1.0);
          p.OriginX := st.Get('originX', 0.0);
          p.OriginY := st.Get('originY', 0.0);
          FChart.TreeDispatchRoam(p);
        end
        else if kind = 'wheel' then
          FChart.Wheel(st.Get('x', 0), st.Get('y', 0), st.Get('delta', 0))
        else if kind = 'drag' then
        begin
          path := st.Arrays['path'];
          FChart.Down(path.Arrays[0].Integers[0], path.Arrays[0].Integers[1]);
          for j := 1 to path.Count - 1 do
            FChart.Move(path.Arrays[j].Integers[0], path.Arrays[j].Integers[1]);
          FChart.Up(path.Arrays[path.Count - 1].Integers[0], path.Arrays[path.Count - 1].Integers[1]);
        end
        else if (kind = 'hover') or (kind = 'leave') then
          FChart.Hover(st.Get('x', 0), st.Get('y', 0))
        else if kind = 'resize' then
        begin
          W := st.Get('width', W);
          H := st.Get('height', H);
        end
        else if kind = 'reset' then
        begin
          FChart.Option := '';
          FChart.Option := text;
        end
        else
        begin
          Inc(FSkipped);
          Break;
        end;
        { after a click or a drag the pointer is parked where nothing is, as
          the oracle parks it, so no hover is left over }
        if (kind = 'click') or (kind = 'drag') then FChart.Hover(1, 1);
        Paint;
        { the toggles the step fired }
        evs := states.Objects[k + 1].Arrays['events'];
        want := 0;
        wantRoam := 0;
        for j := 0 to evs.Count - 1 do
          if evs.Objects[j].Get('type', '') = 'treeExpandAndCollapse' then Inc(want)
          else if evs.Objects[j].Get('type', '') = 'treeRoam' then Inc(wantRoam);
        gotRoam := 0;
        for j := 0 to FChart.Events.Count - 1 do
          if FChart.Events[j] = 'roam' then Inc(gotRoam);
        Inc(FCompared, 2);
        if want <> FChart.Events.Count - gotRoam then
          Miss(Format('%d toggles fired upstream, %d here', [want, FChart.Events.Count - gotRoam]));
        if wantRoam <> gotRoam then
          Miss(Format('%d roams fired upstream, %d here', [wantRoam, gotRoam]));
        CompareState(states.Objects[k + 1]);
        if states.Objects[k + 1].Find('hover') is TJSONObject then
          CompareHover(states.Objects[k + 1].Objects['hover'],
            Num(states.Objects[k + 1].Objects['view'].Find('zoom'))
            * Num(states.Objects[k + 1].Objects['view'].Find('nodeScale')));
      end;
    end;
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartTreeInteractOracleTest.TestClicksAndTogglesAsUpstream;
begin
  RunPart('T3a');
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d states, %d nodes, %d edges, %d labels (%d replays cut short)',
    [FStates, FNodes, FEdges, FLabels, FSkipped]), (FStates >= 150) and (FNodes >= 1000));
end;

procedure TAdvChartTreeInteractOracleTest.TestTheViewAndItsRoamAsUpstream;
begin
  RunPart('T3b');
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d states, %d nodes, %d edges, %d labels (%d replays cut short)',
    [FStates, FNodes, FEdges, FLabels, FSkipped]), (FStates >= 70) and (FNodes >= 400));
end;

procedure TAdvChartTreeInteractOracleTest.TestTheHoverAsUpstream;
begin
  RunPart('T3c');
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d states, %d nodes, %d edges, %d labels (%d replays cut short, %d hovered outside labels passed over)',
    [FStates, FNodes, FEdges, FLabels, FSkipped, FHoverLabelsPassed]),
    (FStates >= 60) and (FNodes >= 300) and (FHoverLabelsPassed <= 5));
end;

{ a tree node's tooltip: one bare row, the dotted path and the first value }
procedure TAdvChartTreeInteractOracleTest.TestTheTooltipAsUpstream;
var
  tips: TJSONArray;
  t, mk: TJSONObject;
  k, n: Integer;
  bmp: TBGRABitmap;
  b, row: TTyTooltipBlock;
begin
  tips := TJSONObject(FRoot).Arrays['tooltips'];
  bmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  n := 0;
  try
    for k := 0 to tips.Count - 1 do
    begin
      t := tips.Objects[k];
      { a template formatter's words are the formatter's, not the default }
      if t.Get('template', False) then Continue;
      FName := t.Get('id', '');
      FChart.Option := '';
      FChart.Option := t.Objects['option'].AsJSON;
      FChart.SetBounds(0, 0, 800, 600);
      FChart.Render(bmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
      mk := t.Objects['markup'];
      b := FChart.ContentFor(t.Integers['dataIndex']);
      try
        Inc(FCompared);
        if (b = nil) or (b.BlockCount <> 1) then
        begin
          Miss('not one row here');
          Continue;
        end;
        Inc(n);
        row := b.Blocks[0];
        Inc(FCompared, 3);
        if row.Name <> mk.Get('name', '') then
          Miss(Format('named "%s" upstream, "%s" here', [mk.Get('name', ''), row.Name]));
        if row.NoValue <> mk.Get('noValue', False) then
          Miss('the value''s presence differs');
        if row.Marker <> ttmNone then Miss('a marker here, none upstream');
      finally
        b.Free;
      end;
    end;
  finally
    bmp.Free;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d tooltips', [n]), n >= 10);
end;

{ A NODE'S DISC AND ITS LABEL ARE TWO TARGETS: pressed on the one and
  released on the other is no click, whatever the distance -- zrender
  compares the elements, the datum they share is not enough. Measured on the
  port's own hit geometry, which is more forgiving than zrender's (the
  oracle's steps for this rule depend on zrender's and are skipped). }
procedure TAdvChartTreeInteractOracleTest.TestPressOnTheLabelReleaseOnTheDiscIsNoClick;
var
  bmp: TBGRABitmap;
  lst: TTyPaintList;
  k: Integer;
  cx, cy: Double;
begin
  bmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  try
    FChart.Option := '{"animation":false,"series":[{"type":"tree","label":{"position":"left"},'
      + '"data":[{"name":"A","children":[{"name":"BBBBBBBB","children":[{"name":"D"}]},{"name":"C"}]}]}]}';
    FChart.SetBounds(0, 0, 800, 600);
    FChart.Render(bmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
    lst := FChart.List;
    cx := NaN;
    cy := NaN;
    for k := 0 to lst.Count - 1 do
      if (lst.Element(k).Datum.DataIndex = 2) and (lst.Element(k).Shape.Kind = cskCircle) then
      begin
        cx := lst.Element(k).Shape.CX;
        cy := lst.Element(k).Shape.CY;
      end;
    AssertFalse('B is drawn', IsNan(cx));
    { on the label, ten left of the centre: past the disc's reach }
    AssertEquals('the press is on the label', 2, FChart.HitTestAt(Round(cx) - 10, Round(cy)).DataIndex);
    FChart.Events.Clear;
    FChart.Down(Round(cx) - 10, Round(cy));
    FChart.Up(Round(cx) - 7, Round(cy));
    AssertEquals('label then disc is no click', 0, FChart.Events.Count);
    AssertTrue('B is still open', FChart.TreeExpanded(0, 2));
    { and the same distance on the label alone is one }
    FChart.Down(Round(cx) - 13, Round(cy));
    FChart.Up(Round(cx) - 10, Round(cy));
    AssertEquals('label then label is a click', 1, FChart.Events.Count);
  finally
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartTreeInteractOracleTest);
end.
