unit test.advchart.hitstroke;
{$mode objfpc}{$H+}
{ WHAT THE POINTER FINDS AROUND A STROKED ELEMENT, held to upstream. [R7-C]

  tests/fixtures/advchart-hit-stroke.json, from the real ECharts 6.1 build
  (tools/advchart-oracle/hit-stroke.js): per case, rays from each aim's
  centre in eight directions, a pixel a step, and at every step what
  zrender's findHover finds -- Path.contain: the stroked bounding rect, the
  stroke within half its width of the outline (at least
  strokeContainThreshold, 5, where there is no fill), the fill -- as the
  series and data index of the target's ECData (sS/D, sS/eD an edge, sS/-
  none), x a target with none, - nothing; run-length encoded.

  TestTheRaysAsUpstream: the same off the series list's HitTestElement
  without the port's pad, the element's own datum (a run element, a line's
  polyline, is sS/-; a tree's edge, which names none, x). Every ray as
  upstream's, a curve's too: a graph's or a lines' curved edge and the pin
  are tested as their own curves [R7-F; R7-C allowed them a step or two]. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Symbol,
     tyControls.AdvanceChart.ZrPath, tyControls.AdvanceChart.AnimView,
     tyControls.AdvanceChart.Lines,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  THitStrokeProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TAdvChartHitStrokeTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FChart: THitStrokeProbe;
    function CodeAt(AX, AY: Double): string;
    function Picture(const AOption: string): TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRaysAsUpstream;
    procedure TestAFillWrittenNonePaintsAsAClearOne;
    procedure TestTheHitFrameRidesWithTheShape;
    procedure TestALinesCurveHitAsItIsDrawnToAPercent;
    procedure TestThePadTopsThePenUpToFour;
  end;

implementation

const
  cW = 400;
  cH = 300;

function THitStrokeProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure THitStrokeProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function LoadJson(const AName: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartHitStrokeTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FMeasure := LoadJson('advchart-text-style.json');
end;

procedure TAdvChartHitStrokeTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

function TAdvChartHitStrokeTest.CodeAt(AX, AY: Double): string;
var
  el: Integer;
  d: TTyChartDatumRef;
  L: TTyPaintList;
begin
  { the list's own test without the port's pad (a symbol's target grown for
    a mouse), as upstream answers; a combining host's child is its host, a
    tree's edge names no datum (HitTestAt) }
  L := FChart.SeriesList;
  el := L.HitTestElement(AX, AY, 96, False);
  if el < 0 then Exit('-');
  if L.Element(el).Anim.PieceOf > 0 then el := L.Element(el).Anim.PieceOf - 1;
  if L.Element(el).Anim.Role = carTreeEdge then Exit('x');
  d := L.Element(el).Datum;
  if (d.Kind <> ctkSeries) or (d.SeriesIndex < 0) then Exit('x');
  Result := 's' + IntToStr(d.SeriesIndex) + '/';
  if d.DataIndex < 0 then Result := Result + '-'
  else if d.IsEdge then Result := Result + 'e' + IntToStr(d.DataIndex)
  else Result := Result + IntToStr(d.DataIndex);
end;

function PointsText(const APts: TTyPointFArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to Min(High(APts), 5) do Result := Result + Format(' (%g,%g)', [APts[i].X, APts[i].Y]);
end;

procedure TAdvChartHitStrokeTest.TestTheRaysAsUpstream;
var
  fix: TJSONData;
  cs, rays: TJSONArray;
  c, r: TJSONObject;
  i, j, k, n, dx, dy, cnt, nBad, nRays: Integer;
  ox, oy: Double;
  id, code, last, seq, bad: string;
begin
  fix := LoadJson('advchart-hit-stroke.json');
  nBad := 0;
  nRays := 0;
  bad := '';
  try
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      FreeAndNil(FChart);
      FChart := THitStrokeProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
        TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
        TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
      FChart.SetBounds(0, 0, cW, cH);
      FChart.Option := c.Objects['option'].AsJSON;
      AssertEquals(id + ' parses', '', FChart.OptionError);
      FBmp.Fill(BGRA(255, 255, 255, 255));
      { [R7-F] a case whose frame raises is that case's failure, and the
        rest still run (an infinite pen once did, in the painter) }
      try
        FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      except
        on E: Exception do
        begin
          Inc(nBad);
          bad := bad + LineEnding + id + ' raises ' + E.ClassName + ': ' + E.Message;
          if GetEnvironmentVariable('TY_HS_ALL') <> '' then DumpExceptionBackTrace(Output);
          Continue;
        end;
      end;
      if GetEnvironmentVariable('TY_HS_EL') = id then
        for k := 0 to FChart.SeriesList.Count - 1 do
          with FChart.SeriesList.Element(k) do
            WriteLn(Format('%d kind %d role %d s %d d %d edge %s silent %s ign %s fill %s w %g col %x ps %g slop %g pad %g b %g,%g,%g,%g c %g,%g r %g,%g a %g,%g n %d cmds %d zr %s ph %s',
              [k, Ord(Shape.Kind), Ord(Anim.Role), Datum.SeriesIndex, Datum.DataIndex, BoolToStr(Datum.IsEdge, True),
               BoolToStr(Silent, True), BoolToStr(Ignore, True), BoolToStr(Style.HasFill, True), Style.StrokeWidthLogical,
               Style.StrokeColor, Style.PenScale, HitSlopLogical, HitPadLogical, Shape.Bounds.Left, Shape.Bounds.Top,
               Shape.Bounds.Right, Shape.Bounds.Bottom, Shape.CX, Shape.CY, Shape.R0, Shape.R1, Shape.StartRad, Shape.EndRad,
               Length(Shape.Points), Length(Shape.Cmds), BoolToStr(ZrHit.Active, True), BoolToStr(PathHit.Active, True)])
              + PointsText(Shape.Points) + Format(' fillcol %x', [Style.FillColor]));
      rays := c.Arrays['rays'];
      for j := 0 to rays.Count - 1 do
      begin
        r := rays.Objects[j];
        Inc(nRays);
        ox := r.Arrays['o'].Floats[0];
        oy := r.Arrays['o'].Floats[1];
        dx := r.Arrays['d'].Integers[0];
        dy := r.Arrays['d'].Integers[1];
        n := r.Integers['n'];
        seq := '';
        last := '';
        cnt := 0;
        for k := 0 to n - 1 do
        begin
          code := CodeAt(ox + dx * k, oy + dy * k);
          if (cnt > 0) and (code = last) then Inc(cnt)
          else
          begin
            if cnt > 0 then
            begin
              if seq <> '' then seq := seq + ' ';
              seq := seq + last + '*' + IntToStr(cnt);
            end;
            last := code;
            cnt := 1;
          end;
        end;
        if cnt > 0 then
        begin
          if seq <> '' then seq := seq + ' ';
          seq := seq + last + '*' + IntToStr(cnt);
        end;
        if seq <> r.Strings['seq'] then
        begin
          Inc(nBad);
          if (Length(bad) < 6000) or (GetEnvironmentVariable('TY_HS_ALL') <> '') then
            bad := bad + LineEnding + Format('%s (%g,%g) d(%d,%d): want %s have %s',
              [id, ox, oy, dx, dy, r.Strings['seq'], seq]);
        end;
      end;
    end;
  finally
    fix.Free;
  end;
  AssertEquals(IntToStr(nBad) + ' of ' + IntToStr(nRays) + ' rays differ:' + bad, 0, nBad);
end;

function TAdvChartHitStrokeTest.Picture(const AOption: string): TBGRABitmap;
begin
  FreeAndNil(FChart);
  FChart := THitStrokeProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := AOption;
  AssertEquals('parses', '', FChart.OptionError);
  Result := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FChart.Render(Result.Canvas, Rect(0, 0, cW, cH), 96);
end;

{ [R7-F] WHAT THE EYE SEES OF 'none': nothing, as of 'transparent' -- the
  canvas fills neither (hasFill() false; a fill of no alpha). The two differ
  only to the pointer (the rays above). A line's or a radar's area and a
  sunburst's piece took the series' colour for 'none' [was]; a radar's ring
  of an infinite width drew at the default 2 (the canvas takes no such
  width: none, as a width of 0) }
procedure TAdvChartHitStrokeTest.TestAFillWrittenNonePaintsAsAClearOne;
const
  cCases: array[0..6] of string = (
    '{"animation":false,"xAxis":{"type":"category","data":["A","B","C"]},"yAxis":{"type":"value","min":0,"max":10},'
      + '"series":[{"type":"line","symbol":"none","data":[5,5,7],"areaStyle":{"color":"%s"},"lineStyle":{"width":2}}]}',
    '{"animation":false,"radar":{"indicator":[{"name":"p","max":10},{"name":"q","max":10},{"name":"r","max":10}],"radius":110},'
      + '"series":[{"type":"radar","symbol":"none","lineStyle":{"width":4},"areaStyle":{"color":"%s"},"data":[{"value":[8,6,7]}]}]}',
    '{"animation":false,"series":[{"type":"sunburst","radius":[20,120],"label":{"show":false},'
      + '"data":[{"name":"a","value":3,"children":[{"name":"a1","value":3}]},{"name":"b","value":2}],'
      + '"itemStyle":{"color":"%s","borderColor":"#000","borderWidth":6}}]}',
    '{"animation":false,"xAxis":{"type":"category","data":["A","B","C"]},"yAxis":{"type":"value","min":0,"max":10},'
      + '"series":[{"type":"bar","barWidth":60,"data":[4,6,8],"itemStyle":{"color":"%s","borderColor":"#000","borderWidth":8}}]}',
    '{"animation":false,"series":[{"type":"pie","radius":[40,100],"label":{"show":false},"data":[1,2,3],'
      + '"itemStyle":{"color":"%s","borderColor":"#000","borderWidth":6}}]}',
    '{"animation":false,"series":[{"type":"funnel","label":{"show":false},"data":[{"name":"a","value":3},'
      + '{"name":"b","value":2},{"name":"c","value":1}],"itemStyle":{"color":"%s","borderColor":"#000","borderWidth":8}}]}',
    '{"animation":false,"radar":{"indicator":[{"name":"p","max":10},{"name":"q","max":10},{"name":"r","max":10}],"radius":110},'
      + '"series":[{"type":"radar","symbol":"none","lineStyle":{"width":%s},"areaStyle":{},"data":[{"value":[8,6,7]}]}]}');
  { what each case's '%s' is, then what it must paint as }
  cWritten: array[0..6] of string = ('none', 'none', 'none', 'none', 'none', 'none', '"Infinity"');
  cAs: array[0..6] of string = ('transparent', 'transparent', 'transparent', 'transparent', 'transparent',
    'transparent', '0');
var
  i, x, y, n: Integer;
  a, b: TBGRABitmap;
  pa, pb: TBGRAPixel;
begin
  for i := 0 to High(cCases) do
  begin
    a := Picture(Format(cCases[i], [cWritten[i]]));
    try
      b := Picture(Format(cCases[i], [cAs[i]]));
      try
        n := 0;
        for y := 0 to cH - 1 do
          for x := 0 to cW - 1 do
          begin
            pa := a.GetPixel(x, y);
            pb := b.GetPixel(x, y);
            if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue)
              or (pa.alpha <> pb.alpha) then Inc(n);
          end;
        AssertEquals('case ' + IntToStr(i) + ': pixels apart', 0, n);
      finally
        b.Free;
      end;
    finally
      a.Free;
    end;
  end;
end;

{ [R7-F] THE HIT OUTLINE'S FRAME AND THE DRAWN GEOMETRY AGREE through every
  move, scale, turn and mirror a frame or a state puts on the shape: a turned
  oblong rect symbol's unit corners land on its polygon's points, and a
  quadratic edge's middle sample on its curve, after each }
procedure TAdvChartHitStrokeTest.TestTheHitFrameRidesWithTheShape;
const
  cUX: array[0..3] of Double = (-1, 1, 1, -1);
  cUY: array[0..3] of Double = (-1, -1, 1, 1);
var
  spec: TTySymbolSpec;
  sym, edge: TTyChartShape;
  pts: TTyPointFArray;
  k: Integer;
  p0, p2, cp: TTyPointF;

  procedure Check(const AWhat: string);
  var i: Integer; ox, oy, qx, qy: Double;
  begin
    AssertEquals(AWhat + ': a frame', 'rect', sym.HitSym);
    for i := 0 to 3 do
    begin
      TyZrApply(sym.HitM, cUX[i], cUY[i], ox, oy);
      AssertEquals(AWhat + ': corner ' + IntToStr(i) + ' x', sym.Points[i].X, ox, 1e-9);
      AssertEquals(AWhat + ': corner ' + IntToStr(i) + ' y', sym.Points[i].Y, oy, 1e-9);
    end;
    AssertTrue(AWhat + ': a quadratic', edge.HitQuad);
    qx := TyLinesQuadAt(edge.Points[0].X, edge.HitCP.X, edge.Points[16].X, 0.5);
    qy := TyLinesQuadAt(edge.Points[0].Y, edge.HitCP.Y, edge.Points[16].Y, 0.5);
    AssertEquals(AWhat + ': the curve''s middle x', edge.Points[8].X, qx, 1e-9);
    AssertEquals(AWhat + ': the curve''s middle y', edge.Points[8].Y, qy, 1e-9);
  end;

begin
  spec := TySymbolDefault('scatter');
  spec.Kind := tsyRect;
  spec.WidthPx := 30;
  spec.HeightPx := 16;
  spec.RotateDeg := 30;
  spec.OffsetX := 4;
  spec.OffsetY := -2;
  sym := TyBuildSymbol(spec, 100, 80);
  TySymbolHitFrame(sym, spec, 100, 80);
  p0 := TyPointF(20, 30);
  p2 := TyPointF(180, 90);
  cp := TyPointF(140, 10);
  SetLength(pts, 17);
  for k := 0 to 16 do
    pts[k] := TyPointF(TyLinesQuadAt(p0.X, cp.X, p2.X, k / 16), TyLinesQuadAt(p0.Y, cp.Y, p2.Y, k / 16));
  edge := TyShapePolyline(pts);
  edge.HitQuad := True;
  edge.HitCP := cp;
  Check('built');
  TyShapeScaleAbout(sym, 90, 70, 1.5, 0.75);
  TyShapeScaleAbout(edge, 90, 70, 1.5, 0.75);
  Check('scaled');
  TyShapeRotateAbout(sym, 50, 60, 0.7);
  TyShapeRotateAbout(edge, 50, 60, 0.7);
  Check('turned');
  TyShapeMove(sym, 3, -4);
  TyShapeMove(edge, 3, -4);
  Check('moved');
  sym := TyMirrorShape(sym, 100, 100, True, False);
  edge := TyMirrorShape(edge, 100, 100, True, False);
  Check('mirrored across');
  sym := TyMirrorShape(sym, 100, 100, False, True);
  edge := TyMirrorShape(edge, 100, 100, False, True);
  Check('mirrored up');
  sym := TyScaleShape(sym, 1.3);
  edge := TyScaleShape(edge, 1.3);
  Check('grown');
end;

{ [R7-F] a lines row drawn to a percent (Line.beforeUpdate: the first part of
  quadraticSubdivide) is tested as that part, not as the whole curve }
procedure TAdvChartHitStrokeTest.TestALinesCurveHitAsItIsDrawnToAPercent;
var
  k, n: Integer;
  el: TTyChartElement;
  found: Boolean;
begin
  Picture('{"animation":false,"xAxis":{"type":"value","min":0,"max":10},'
    + '"yAxis":{"type":"value","min":0,"max":10},"series":[{"type":"lines","coordinateSystem":"cartesian2d",'
    + '"lineStyle":{"width":12,"curveness":0.3,"opacity":1},"data":[{"coords":[[1,2],[9,8]]}]}]}').Free;
  found := False;
  for k := 0 to FChart.SeriesList.Count - 1 do
    if FChart.SeriesList.Element(k).Shape.HitQuad then
    begin
      el := FChart.SeriesList.Element(k);
      found := True;
      Break;
    end;
  AssertTrue('a curved row', found);
  TyLinesFrameLine(el, 0.4);
  n := High(el.Shape.Points);
  AssertEquals('drawn as points', 32, n);
  AssertEquals('the part''s middle x', el.Shape.Points[16].X,
    TyLinesQuadAt(el.Shape.Points[0].X, el.Shape.HitCP.X, el.Shape.Points[n].X, 0.5), 1e-9);
  AssertEquals('the part''s middle y', el.Shape.Points[16].Y,
    TyLinesQuadAt(el.Shape.Points[0].Y, el.Shape.HitCP.Y, el.Shape.Points[n].Y, 0.5), 1e-9);
end;

{ [R7-F] THE PORT'S PAD (batch 142, a mouse's only): a symbol is found
  within 4 logical px of its outline, the pen's reach topped up to it -- a
  1 px reach with a 3 px pad is 4, not 3 [R7-C answered the larger of the
  two]. Upstream has no pad; the rays above ask without it. }
procedure TAdvChartHitStrokeTest.TestThePadTopsThePenUpToFour;
var
  k: Integer;
  el: TTyChartElement;
  found: Boolean;
begin
  Picture('{"animation":false,"xAxis":{"type":"value","min":0,"max":10},'
    + '"yAxis":{"type":"value","min":0,"max":10},"series":[{"type":"scatter","symbol":"circle",'
    + '"symbolSize":20,"data":[[5,5]],"itemStyle":{"borderColor":"#000","borderWidth":2}}]}').Free;
  found := False;
  for k := 0 to FChart.SeriesList.Count - 1 do
    if (FChart.SeriesList.Element(k).Shape.Kind = cskCircle)
      and (FChart.SeriesList.Element(k).Datum.DataIndex = 0) then
    begin
      el := FChart.SeriesList.Element(k);
      found := True;
      Break;
    end;
  AssertTrue('the symbol', found);
  AssertEquals('its radius', 10, el.Shape.R1, 1e-9);
  AssertTrue('3.8 px off its outline, with the pad',
    TyElementHit(el, el.Shape.CX + 13.8, el.Shape.CY + 0.1, 96, True));
  AssertFalse('4.2 px off', TyElementHit(el, el.Shape.CX + 14.2, el.Shape.CY + 0.1, 96, True));
  AssertFalse('3.8 px off, without the pad (upstream: its pen, 1 px)',
    TyElementHit(el, el.Shape.CX + 13.8, el.Shape.CY + 0.1, 96, False));
  AssertTrue('0.8 px off, without the pad',
    TyElementHit(el, el.Shape.CX + 10.8, el.Shape.CY + 0.1, 96, False));
end;

initialization
  RegisterTest(TAdvChartHitStrokeTest);
end.
