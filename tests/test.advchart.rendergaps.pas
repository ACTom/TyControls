unit test.advchart.rendergaps;
{$mode objfpc}{$H+}
{ THE FOUR PICTURE DIFFERENCES R7-C'S HIT ORACLE STEPPED ROUND, held to
  upstream. [R7-G]

  tests/fixtures/advchart-render-gaps.json, from the real ECharts 6.1 build
  (tools/advchart-oracle/render-gaps.js):

  subpixel   every element zrender builds with subPixelOptimize: a lines
             series' straight line and a graph's straight edge (ECLinePath,
             snapped in its own frame -- a graph's under the view's roam --
             with its own lineWidth), the axis pointer's line, a title's
             background rect; buildPath's calls, the global transform and
             the points through it.
  pictorial  a pictorial bar's borderWidth in its layout: valueLineWidth,
             the repeat count, every glyph's place, the bar rect.
  inset      a bar's getLineWidth: which borderColor values take the border
             out of the layout.
  axishit    what findHover finds on every part of every kind of axis: a
             series' datum, an axis' eventData, a target with neither, or
             nothing; and the cursor. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Title,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TRenderGapsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    function CodeAt(AX, AY: Integer): string;
    function HoverCodeAt(AX, AY: Integer): string;
    function CursorAt(AX, AY: Integer): string;
    function Frame: TTyPaintList;
  end;

  TAdvChartRenderGapsTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FFix: TJSONData;
    FBmp: TBGRABitmap;
    FChart: TRenderGapsProbe;
    procedure Build(AOption: TJSONObject; const AId: string);
    function Section(const AName: string): TJSONArray;
    function Find(const AId: string; const AName: string): TJSONObject;
    function Ink(AX, AY: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLinesAndGraphEdgesSnapAsUpstream;
    procedure TestEveryEnterFrameIsSnapped;
    procedure TestThePointerLineIsOnTheHalfPixel;
    procedure TestTheTitleFrameSnapsInItsGroup;
    procedure TestTheTitleFrameIsDrawnSnapped;
    procedure TestTheTitleFillIsDrawnOnTheFrame;
    procedure TestTheLegendAndTooltipBoxesAreNotSnapped;
    procedure TestPictorialBorderTakesPartInTheLayout;
    procedure TestBarInsetFollowsTheBorderColourAsWritten;
    procedure TestAxisPartsAnswerThePointerAsUpstream;
  end;

implementation

const
  cW = 400;
  cH = 300;

function TRenderGapsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TRenderGapsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TRenderGapsProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

{ the event target at a point, as the oracle writes findHover's: sS/D a
  series' datum, e:T an axis' eventData of targetType T, x a target with
  neither, - none }
function TRenderGapsProbe.CodeAt(AX, AY: Integer): string;
var t: TTyChartEventTarget;
begin
  t := EventTargetAt(AX, AY);
  if t.Id = 0 then Exit('-');
  if t.HdKind in [1, 2, 16, 31] then
    Exit('s' + IntToStr(t.HdSeries) + '/' + IntToStr(t.HdRow));
  if t.HasData and (t.Params.TargetType <> '') then Exit('e:' + t.Params.TargetType);
  Result := 'x';
end;

{ what the hover, the tooltip and a press find there (HitTestAt): a
  series' datum, or nothing -- an axis' part over a series hides it }
function TRenderGapsProbe.HoverCodeAt(AX, AY: Integer): string;
var d: TTyChartDatumRef;
begin
  d := HitTestAt(AX, AY);
  if (d.Kind <> ctkSeries) or (d.SeriesIndex < 0) then Exit('-');
  Result := 's' + IntToStr(d.SeriesIndex) + '/' + IntToStr(d.DataIndex);
end;

{ the cursor the pointer moved there shows }
function TRenderGapsProbe.CursorAt(AX, AY: Integer): string;
begin
  MouseMove([], AX, AY);
  Result := CursorName;
end;

{ the list a frame of motion is drawn from (the list itself at rest) }
function TRenderGapsProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
  if Result = nil then Result := SeriesList;
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

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function HexAt(AArr: TJSONArray; AIndex: Integer): Double;
begin
  Result := FromHex(AArr.Strings[AIndex]);
end;

procedure TAdvChartRenderGapsTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FMeasure := LoadJson('advchart-text-style.json');
  FFix := LoadJson('advchart-render-gaps.json');
end;

procedure TAdvChartRenderGapsTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  FreeAndNil(FFix);
  inherited TearDown;
end;

procedure TAdvChartRenderGapsTest.Build(AOption: TJSONObject; const AId: string);
begin
  FreeAndNil(FChart);
  FChart := TRenderGapsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := AOption.AsJSON;
  AssertEquals(AId + ' parses', '', FChart.OptionError);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartRenderGapsTest.Section(const AName: string): TJSONArray;
begin
  Result := TJSONObject(FFix).Arrays[AName];
end;

function TAdvChartRenderGapsTest.Find(const AId: string; const AName: string): TJSONObject;
var a: TJSONArray; i: Integer;
begin
  a := Section(AName);
  for i := 0 to a.Count - 1 do
    if a.Objects[i].Strings['id'] = AId then Exit(a.Objects[i]);
  Fail('no case ' + AId);
  Result := nil;
end;

{ how far a pixel of the last render is from the white ground (0: none) }
function TAdvChartRenderGapsTest.Ink(AX, AY: Integer): Integer;
var c: TBGRAPixel;
begin
  c := FBmp.GetPixel(AX, AY);
  Result := (255 - c.red) + (255 - c.green) + (255 - c.blue);
end;

{ ==================== subpixel ==================== }

{ A lines series' straight line and a graph's straight edge: the element's
  two points are upstream's buildPath points through the global transform
  -- subPixelOptimizeLine on the shape in the element's own frame (a
  graph's under the view's roam transform) with its own lineWidth, before
  the percent. Curves and slanted lines are not moved (the curve is
  sampled here: its ends only). }
procedure TAdvChartRenderGapsTest.TestLinesAndGraphEdgesSnapAsUpstream;
var
  cs, els, pts, calls: TJSONArray;
  c, e: TJSONObject;
  i, k, n, nEl, nCmp, nBad: Integer;
  id, bad: string;
  el: TTyChartElement;
  L: TTyPaintList;
  isGraph: Boolean;
begin
  cs := Section('subpixel');
  nCmp := 0;
  nBad := 0;
  bad := '';
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if (Pos('lines.', id) <> 1) and (Pos('graph.', id) <> 1) then Continue;
    isGraph := Pos('graph.', id) = 1;
    Build(c.Objects['option'], id);
    els := c.Arrays['els'];
    L := FChart.SeriesList;
    n := 0;
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> 0) then Continue;
      if el.Shape.Kind <> cskPolyline then Continue;
      if isGraph <> el.Datum.IsEdge then Continue;
      if (not isGraph) and (el.Anim.Role <> carLinesLine) then Continue;
      nEl := el.Datum.DataIndex;
      AssertTrue(id + ': element ' + IntToStr(nEl) + ' in the fixture', nEl < els.Count);
      e := els.Objects[nEl];
      calls := e.Arrays['calls'];
      pts := e.Arrays['pts'];
      Inc(n);
      { a curve: its ends only (the port samples it) }
      if (calls.Count <> 2) or (calls.Arrays[1].Strings[0] <> 'lineTo') then
      begin
        AssertTrue(id + ': a curve has its samples', Length(el.Shape.Points) > 2);
        Continue;
      end;
      AssertEquals(id + ': two points', 2, Length(el.Shape.Points));
      Inc(nCmp);
      if (HexOf(el.Shape.Points[0].X) <> pts.Arrays[0].Strings[0])
        or (HexOf(el.Shape.Points[0].Y) <> pts.Arrays[0].Strings[1])
        or (HexOf(el.Shape.Points[1].X) <> pts.Arrays[1].Strings[0])
        or (HexOf(el.Shape.Points[1].Y) <> pts.Arrays[1].Strings[1]) then
      begin
        Inc(nBad);
        if Length(bad) < 1500 then
          bad := bad + Format('%s#%d: (%g,%g)-(%g,%g), upstream (%g,%g)-(%g,%g); ',
            [id, nEl, el.Shape.Points[0].X, el.Shape.Points[0].Y, el.Shape.Points[1].X,
             el.Shape.Points[1].Y, HexAt(pts.Arrays[0], 0), HexAt(pts.Arrays[0], 1),
             HexAt(pts.Arrays[1], 0), HexAt(pts.Arrays[1], 1)]);
      end;
    end;
    AssertEquals(id + ': every line of the fixture drawn', els.Count, n);
  end;
  AssertEquals('compared', 19, nCmp);
  AssertEquals(bad, 0, nBad);
end;

{ A line's enter: shape.percent from 0 (linear, 1000 ms) -- Line.buildPath
  snaps the shape's ends first and then cuts it at the percent, every frame.
  At 300 and 700 ms each straight line's two points in the frame, to the
  bit: a graph's edges under a zoom and on axes, a lines series' (one
  slanting by under a pixel: not snapped whole, so not when cut either). }
procedure TAdvChartRenderGapsTest.TestEveryEnterFrameIsSnapped;
var
  cs, samples, els, pts: TJSONArray;
  c, sm, e: TJSONObject;
  i, j, k, n, nCmp, nBad: Integer;
  id, bad: string;
  t0, t: Double;
  L: TTyPaintList;
  el: TTyChartElement;
  isGraph: Boolean;
begin
  cs := Section('frames');
  nCmp := 0;
  nBad := 0;
  bad := '';
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    isGraph := Pos('frame.graph', id) = 1;
    t0 := c.Floats['T0'];
    FreeAndNil(FChart);
    FChart := TRenderGapsProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
      TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
      TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
    FChart.SetBounds(0, 0, cW, cH);
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := t0;
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    AssertEquals(id + ' parses', '', FChart.OptionError);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    samples := c.Arrays['samples'];
    for j := 0 to samples.Count - 1 do
    begin
      sm := samples.Objects[j];
      t := t0 + sm.Floats['t'];
      FChart.AnimNow := t;
      FChart.AnimTick(t);
      FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      els := sm.Arrays['els'];
      L := FChart.Frame;
      n := 0;
      for k := 0 to L.Count - 1 do
      begin
        el := L.Element(k);
        if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> 0) then Continue;
        if el.Shape.Kind <> cskPolyline then Continue;
        if isGraph <> el.Datum.IsEdge then Continue;
        if (not isGraph) and (el.Anim.Role <> carLinesLine) then Continue;
        if (el.Datum.DataIndex < 0) or (el.Datum.DataIndex >= els.Count) then Continue;
        e := els.Objects[el.Datum.DataIndex];
        Inc(n);
        if not e.Booleans['straight'] then Continue;
        pts := e.Arrays['pts'];
        Inc(nCmp);
        if (Length(el.Shape.Points) <> 2)
          or (HexOf(el.Shape.Points[0].X) <> pts.Arrays[0].Strings[0])
          or (HexOf(el.Shape.Points[0].Y) <> pts.Arrays[0].Strings[1])
          or (HexOf(el.Shape.Points[1].X) <> pts.Arrays[1].Strings[0])
          or (HexOf(el.Shape.Points[1].Y) <> pts.Arrays[1].Strings[1]) then
        begin
          Inc(nBad);
          if Length(bad) < 2000 then
            bad := bad + Format('%s t=%g #%d: (%g,%g)-(%g,%g), upstream (%g,%g)-(%g,%g); ',
              [id, sm.Floats['t'], el.Datum.DataIndex, el.Shape.Points[0].X, el.Shape.Points[0].Y,
               el.Shape.Points[High(el.Shape.Points)].X, el.Shape.Points[High(el.Shape.Points)].Y,
               HexAt(pts.Arrays[0], 0), HexAt(pts.Arrays[0], 1),
               HexAt(pts.Arrays[1], 0), HexAt(pts.Arrays[1], 1)]);
        end;
      end;
      AssertEquals(Format('%s t=%g: every line in the frame', [id, sm.Floats['t']]), els.Count, n);
    end;
  end;
  AssertEquals('compared', 16, nCmp);
  AssertEquals(bad, 0, nBad);
end;

{ The axis pointer's line (CartesianAxisPointer: subPixelOptimize true):
  the mouse at the oracle's place, the line's columns or rows of ink are
  whole -- upstream's x 150.5 at width 1 on a value axis, y 142.5 at width 3
  on a band's centre (142.33 before the move) -- and the pixels either
  side of them have none. }
procedure TAdvChartRenderGapsTest.TestThePointerLineIsOnTheHalfPixel;
var
  cs, els, calls: TJSONArray;
  c, e: TJSONObject;
  i, k, q, x0, x1, lo, hi, probe, mv0, mv1: Integer;
  id: string;
  v, w, a, b: Double;
  vertical: Boolean;
begin
  cs := Section('subpixel');
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if Pos('pointer.', id) <> 1 then Continue;
    Build(c.Objects['option'], id);
    mv0 := c.Arrays['move'].Integers[0];
    mv1 := c.Arrays['move'].Integers[1];
    FChart.Move(mv0, mv1);
    FBmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    els := c.Arrays['els'];
    AssertEquals(id + ': one line', 1, els.Count);
    for k := 0 to els.Count - 1 do
    begin
      e := els.Objects[k];
      calls := e.Arrays['calls'];
      w := FromHex(e.Strings['lw']);
      a := HexAt(calls.Arrays[0], 1);
      b := HexAt(calls.Arrays[1], 1);
      vertical := a = b;
      if vertical then v := a else v := HexAt(calls.Arrays[0], 2);
      { the ink spans [v - w/2, v + w/2], whole pixels }
      lo := Round(v - w / 2);
      hi := Round(v + w / 2) - 1;
      AssertEquals(id + ': on whole pixels', v - w / 2, Double(lo));
      { a place along the line away from the series and the other line }
      if vertical then probe := mv1 + 30 else probe := mv0 + 40;
      for q := lo - 1 to hi + 1 do
      begin
        if vertical then x0 := Ink(q, probe) else x0 := Ink(probe, q);
        if (q < lo) or (q > hi) then
          AssertEquals(Format('%s line %d: no ink beside it at %d', [id, k, q]), 0, x0)
        else
        begin
          { whole cover: as much ink as the line's middle }
          if vertical then x1 := Ink(lo + (hi - lo) div 2, probe)
          else x1 := Ink(probe, lo + (hi - lo) div 2);
          AssertTrue(Format('%s line %d: ink at %d', [id, k, q]), x0 > 0);
          AssertEquals(Format('%s line %d: whole cover at %d', [id, k, q]), x1, x0);
        end;
      end;
    end;
  end;
end;

{ A title's background (title/install.ts: a Rect with subPixelOptimize,
  its own shape the group's box less the padding, in the group's frame;
  the group placed at the title's anchor): TyTitleFrameDrawn from the
  local shape and the group's place, against buildPath's rect through the
  transform. No border width, no move. }
procedure TAdvChartRenderGapsTest.TestTheTitleFrameSnapsInItsGroup;
var
  cs, els, sh, m, pts: TJSONArray;
  c, e: TJSONObject;
  i, n: Integer;
  id: string;
  lay: TTyTitleLayout;
  r: TTyRectF;
begin
  cs := Section('subpixel');
  n := 0;
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if Pos('title.', id) <> 1 then Continue;
    els := c.Arrays['els'];
    AssertEquals(id + ': one rect', 1, els.Count);
    e := els.Objects[0];
    sh := e.Arrays['shape'];
    m := e.Arrays['m'];
    pts := e.Arrays['pts'];
    lay := Default(TTyTitleLayout);
    lay.TextX := HexAt(m, 4);
    lay.TextY := HexAt(m, 5);
    lay.FrameLX := HexAt(sh, 0);
    lay.FrameLY := HexAt(sh, 1);
    lay.FrameW := HexAt(sh, 2);
    lay.FrameH := HexAt(sh, 3);
    r := TyTitleFrameDrawn(lay, FromHex(e.Strings['lw']));
    AssertEquals(id + ' left', pts.Arrays[0].Strings[0], HexOf(r.Left));
    AssertEquals(id + ' top', pts.Arrays[0].Strings[1], HexOf(r.Top));
    AssertEquals(id + ' right', pts.Arrays[1].Strings[0], HexOf(r.Right));
    AssertEquals(id + ' bottom', pts.Arrays[1].Strings[1], HexOf(r.Bottom));
    Inc(n);
  end;
  AssertEquals('title cases', 4, n);
end;

{ ... and the chart draws the frame there: title.left's 1 px border is at
  x 10.8 upstream (10.3 before the move), so column 9 takes no ink and
  column 11 some; with no move column 9 had a fifth. }
procedure TAdvChartRenderGapsTest.TestTheTitleFrameIsDrawnSnapped;
var c: TJSONObject; y: Integer;
begin
  c := Find('title.left', 'subpixel');
  Build(c.Objects['option'], 'title.left');
  { half way down the frame (7.7 .. 34.7) }
  y := 20;
  AssertEquals('column 9 clear', 0, Ink(9, y));
  AssertTrue('column 10 inked', Ink(10, y) > 0);
  AssertTrue('column 11 inked', Ink(11, y) > 0);
  AssertTrue('column 10 the darker', Ink(10, y) > Ink(11, y));
end;

{ [R7-I] ... and its fill with it, to the fraction: title.b0 (no border, so
  no move) is filled from x 10.3, y 7.2 upstream -- column 10 takes seven
  tenths of a full pixel's ink, row 7 eight tenths, column 9 and row 6
  none; its far edges likewise at the fraction the frame ends at (the
  title's own size: the skin's font). [Was: the fill rounded to whole
  pixels: column 10 full.] }
procedure TAdvChartRenderGapsTest.TestTheTitleFillIsDrawnOnTheFrame;
var
  c: TJSONObject;
  full, x, y, xr, yb: Integer;
  r: TTyRectF;
  pts: TJSONArray;
begin
  c := Find('title.b0', 'subpixel');
  Build(c.Objects['option'], 'title.b0');
  r := TyTitleFrameDrawn(FChart.TitleLayoutOf(0), 0);
  pts := c.Arrays['els'].Objects[0].Arrays['pts'];
  AssertEquals('left as upstream', HexAt(pts.Arrays[0], 0), r.Left, 1e-9);
  AssertEquals('top as upstream', HexAt(pts.Arrays[0], 1), r.Top, 1e-9);
  x := Trunc(r.Left);
  y := Trunc(r.Top);
  xr := Trunc(r.Right);
  yb := Trunc(r.Bottom);
  full := Ink(x + 2, y + 2);
  AssertTrue('a full pixel of the fill', full > 30);
  AssertEquals('the column after full', full, Ink(x + 1, y + 2));
  AssertEquals('the column before clear', 0, Ink(x - 1, y + 2));
  AssertEquals('the row before clear', 0, Ink(x + 2, y - 1));
  AssertEquals('the left column at its fraction', 1 - Frac(r.Left), Ink(x, y + 2) / full, 0.08);
  AssertEquals('the top row at its fraction', 1 - Frac(r.Top), Ink(x + 2, y) / full, 0.08);
  AssertEquals('the right column at its fraction', Frac(r.Right), Ink(xr, y + 2) / full, 0.08);
  AssertEquals('the bottom row at its fraction', Frac(r.Bottom), Ink(x + 2, yb) / full, 0.08);
  AssertEquals('the column after clear', 0, Ink(xr + 1, y + 2));
end;

{ [R7-I] THE OTHER BOXES, which upstream never snaps: a legend's background
  (listComponent.makeBackground: a Rect without subPixelOptimize --
  `legend: {left: 10.3, top: 7.2}` fills from x 10.3, y 7.2 in the real
  dist's SVG, `translate(16.3 12.7)` of a path from (-6, -5.5)) and a
  tooltip's (TooltipRichContent: its rect at the place, to the fraction, a
  border and a shadow of nought adding nothing): column 10 / 50 and row 7 /
  40 take part of a pixel's ink (the list's rects blend as BGRA does), the
  ones before none. [The legend's frame was already there, but drawn in the
  skin's colour whatever backgroundColor said -- invisible here; the
  tooltip was rounded to whole pixels.] }
procedure TAdvChartRenderGapsTest.TestTheLegendAndTooltipBoxesAreNotSnapped;
var
  o: TJSONObject;
  full: Integer;
begin
  o := TJSONObject(GetJSON('{"animation":false,"legend":{"left":10.3,"top":7.2,'
    + '"backgroundColor":"#000","padding":[5.5,6]},'
    + '"series":[{"type":"pie","name":"a","radius":40,"label":{"show":false},'
    + '"data":[{"name":"x","value":1}]}]}'));
  try
    Build(o, 'legend');
  finally
    o.Free;
  end;
  AssertEquals('legend: its left', 10.3, FChart.LegendLayout(0).Frame.Left, 1e-9);
  AssertEquals('legend: its top', 7.2, FChart.LegendLayout(0).Frame.Top, 1e-9);
  full := Ink(14, 12);
  AssertTrue('legend: the written colour', full > 600);
  AssertEquals('legend: column 9 clear', 0, Ink(9, 12));
  AssertTrue('legend: column 10 part of a pixel', (Ink(10, 12) > 0) and (Ink(10, 12) < full));
  AssertEquals('legend: column 11 full', full, Ink(11, 12));
  AssertEquals('legend: row 6 clear', 0, Ink(14, 6));
  AssertTrue('legend: row 7 part of a pixel', (Ink(14, 7) > 0) and (Ink(14, 7) < full));

  o := TJSONObject(GetJSON('{"animation":false,"tooltip":{"position":[50.3,40.6],"hideDelay":0,'
    + '"backgroundColor":"#000","borderWidth":0,"shadowBlur":0,"shadowColor":"transparent",'
    + '"padding":6,"renderMode":"richText"},'
    + '"xAxis":{"type":"category","data":["A","B"]},"yAxis":{"type":"value","max":10},'
    + '"series":[{"type":"bar","data":[3,5]}]}'));
  try
    Build(o, 'tooltip');
  finally
    o.Free;
  end;
  FChart.TooltipNow := 0;
  FChart.Move(270, 200);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  AssertTrue('tooltip: shown', FChart.TooltipShown);
  AssertEquals('tooltip: its left', 50.3, FChart.TooltipBox.Left, 1e-9);
  AssertEquals('tooltip: its top', 40.6, FChart.TooltipBox.Top, 1e-9);
  full := Ink(55, 45);
  AssertTrue('tooltip: a full pixel', full > 600);
  AssertEquals('tooltip: column 49 clear', 0, Ink(49, 45));
  AssertTrue('tooltip: column 50 part of a pixel', (Ink(50, 45) > 0) and (Ink(50, 45) < full));
  AssertEquals('tooltip: column 51 full', full, Ink(51, 45));
  AssertEquals('tooltip: row 39 clear', 0, Ink(55, 39));
  AssertTrue('tooltip: row 40 part of a pixel', (Ink(55, 40) > 0) and (Ink(55, 40) < full));
  AssertEquals('tooltip: row 41 full', full, Ink(55, 41));
end;

{ ==================== pictorial ==================== }

{ PictorialBarView: valueLineWidth -- borderWidth over the glyph's line
  scale (pathForLineWidth's transform: the symbol scale and the rotation),
  times its scale along the value axis, signed -- joins the glyph's length
  in the unit, so the glyph's place, a repeat's count and spacing and the
  bar rect all move by it. Every glyph's centre and the bar rect, to the
  bit. }
procedure TAdvChartRenderGapsTest.TestPictorialBorderTakesPartInTheLayout;
var
  cs, items, glyphs, g, rect: TJSONArray;
  c, it: TJSONObject;
  i, k, j, idx, nG, nBad, nCmp: Integer;
  id, bad: string;
  L: TTyPaintList;
  el: TTyChartElement;
  gx, gy: Double;
  seen: array of Integer;
begin
  cs := Section('pictorial');
  nBad := 0;
  nCmp := 0;
  bad := '';
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    Build(c.Objects['option'], id);
    items := c.Arrays['items'];
    L := FChart.SeriesList;
    seen := nil;
    SetLength(seen, items.Count);
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> 0) then Continue;
      idx := el.Datum.DataIndex;
      if (idx < 0) or (idx >= items.Count) then Continue;
      it := items.Objects[idx];
      if el.Anim.Role = carPictorialRect then
      begin
        rect := it.Arrays['rect'];
        for j := 0 to 3 do
        begin
          Inc(nCmp);
          if HexOf(el.Anim.G[j]) <> rect.Strings[j] then
          begin
            Inc(nBad);
            if Length(bad) < 1500 then
              bad := bad + Format('%s#%d rect[%d] %g, upstream %g; ',
                [id, idx, j, el.Anim.G[j], HexAt(rect, j)]);
          end;
        end;
        Continue;
      end;
      if not (el.Anim.Role in [carPictorialGlyph, carPictorialClip]) then Continue;
      glyphs := it.Arrays['glyphs'];
      j := el.Anim.Sub;
      Inc(seen[idx]);
      if j >= glyphs.Count then
      begin
        Inc(nBad);
        bad := bad + Format('%s#%d: glyph %d of %d; ', [id, idx, j, glyphs.Count]);
        Continue;
      end;
      g := glyphs.Arrays[j];
      { the glyph's place: its place in the bundle and the bundle's }
      gx := el.Caption.LgG[0] + el.Caption.LgG[6];
      gy := el.Caption.LgG[1] + el.Caption.LgG[7];
      Inc(nCmp);
      if (HexOf(gx) <> g.Strings[4]) or (HexOf(gy) <> g.Strings[5]) then
      begin
        Inc(nBad);
        if Length(bad) < 1500 then
          bad := bad + Format('%s#%d glyph %d (%g,%g), upstream (%g,%g); ',
            [id, idx, j, gx, gy, HexAt(g, 4), HexAt(g, 5)]);
      end;
    end;
    for idx := 0 to items.Count - 1 do
    begin
      nG := items.Objects[idx].Arrays['glyphs'].Count;
      if seen[idx] <> nG then
      begin
        Inc(nBad);
        bad := bad + Format('%s#%d: %d glyphs, upstream %d; ', [id, idx, seen[idx], nG]);
      end;
    end;
  end;
  AssertTrue('compared', nCmp > 100);
  AssertEquals(bad, 0, nBad);
end;

{ ==================== inset ==================== }

{ BarView's getLineWidth: the border comes out of the layout when the item
  model's itemStyle.borderColor is truthy and not 'none' -- the item's own
  over the series' (null climbs, '' does not) -- whatever the pen draws:
  'transparent', a colour of no alpha, a word the canvas does not know, a
  gradient, a number. A polar bar's layout never is. }
procedure TAdvChartRenderGapsTest.TestBarInsetFollowsTheBorderColourAsWritten;
var
  cs, items, v: TJSONArray;
  c, it: TJSONObject;
  i, k, idx, nBad, nCmp: Integer;
  id, bad, want, have: string;
  L: TTyPaintList;
  el: TTyChartElement;
  got: array of string;
  x, y, w, h: Double;
begin
  cs := Section('inset');
  nBad := 0;
  nCmp := 0;
  bad := '';
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    Build(c.Objects['option'], id);
    items := c.Arrays['items'];
    got := nil;
    SetLength(got, items.Count);
    L := FChart.SeriesList;
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> 0) then Continue;
      idx := el.Datum.DataIndex;
      if (idx < 0) or (idx >= items.Count) or (got[idx] <> '') then Continue;
      if el.Shape.Kind in [cskRect, cskRoundRect] then
        got[idx] := Format('rect %s %s %s %s', [HexOf(el.Shape.Bounds.Left),
          HexOf(el.Shape.Bounds.Top), HexOf(el.Shape.Bounds.Right), HexOf(el.Shape.Bounds.Bottom)])
      else if el.Shape.Kind = cskSector then
        got[idx] := Format('sector %s %s', [HexOf(el.Shape.R0), HexOf(el.Shape.R1)]);
    end;
    for idx := 0 to items.Count - 1 do
    begin
      if items.Items[idx].JSONType = jtNull then want := ''
      else
      begin
        it := items.Objects[idx];
        v := it.Arrays['v'];
        if it.Strings['kind'] = 'rect' then
        begin
          x := HexAt(v, 0);
          y := HexAt(v, 1);
          w := HexAt(v, 2);
          h := HexAt(v, 3);
          want := Format('rect %s %s %s %s', [HexOf(Min(x, x + w)), HexOf(Min(y, y + h)),
            HexOf(Max(x, x + w)), HexOf(Max(y, y + h))]);
        end
        else
          want := Format('sector %s %s', [v.Strings[2], v.Strings[3]]);
      end;
      have := got[idx];
      Inc(nCmp);
      if have <> want then
      begin
        Inc(nBad);
        if Length(bad) < 1500 then bad := bad + Format('%s#%d: [%s] want [%s]; ', [id, idx, have, want]);
      end;
    end;
  end;
  AssertTrue('compared', nCmp >= 60);
  AssertEquals(bad, 0, nBad);
end;

{ ==================== axishit ==================== }

{ AxisBuilder's parts (line and ticks silent; labels and name
  isLabelSilent: silent, or neither triggerEvent nor tooltip.show -- a
  single axis' tooltip shows by default), an angle axis' ticks and minor
  ticks (not silent, within half their width), split lines and areas
  (silent), a radar's indicator names (only triggerEvent), a gauge's
  furniture (silent): at each of the oracle's probes the event target is
  what findHover found -- the series under a silent part, the part over a
  series below it in z (a tie goes to the series, drawn later), an axis'
  eventData where triggerEvent asks -- the hover's own hit test finds the
  series only where upstream did, and the cursor is the target's. }
procedure TAdvChartRenderGapsTest.TestAxisPartsAnswerThePointerAsUpstream;
var
  cs, probes: TJSONArray;
  c, p: TJSONObject;
  i, k, nBad, nCmp: Integer;
  id, bad, code, cur, wantCur: string;
begin
  cs := Section('axishit');
  nBad := 0;
  nCmp := 0;
  bad := '';
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    Build(c.Objects['option'], id);
    probes := c.Arrays['probes'];
    for k := 0 to probes.Count - 1 do
    begin
      p := probes.Objects[k];
      code := FChart.CodeAt(p.Integers['x'], p.Integers['y']);
      Inc(nCmp);
      if code <> p.Strings['code'] then
      begin
        Inc(nBad);
        if Length(bad) < 3000 then
          bad := bad + Format('%s %s %s (%d,%d): %s, upstream %s; ', [id, p.Strings['own'],
            p.Strings['part'], p.Integers['x'], p.Integers['y'], code, p.Strings['code']]);
      end;
      { the hover's own test: the series' datum where upstream found one,
        none where an axis' part (or nothing) was found }
      code := FChart.HoverCodeAt(p.Integers['x'], p.Integers['y']);
      if Copy(p.Strings['code'], 1, 1) = 's' then wantCur := p.Strings['code']
      else wantCur := '-';
      Inc(nCmp);
      if code <> wantCur then
      begin
        Inc(nBad);
        if Length(bad) < 3000 then
          bad := bad + Format('%s hover (%d,%d): %s, upstream %s; ', [id,
            p.Integers['x'], p.Integers['y'], code, wantCur]);
      end;
    end;
    { and then the cursor a pointer moved onto an axis' target shows (a
      move hovers, so after every code was read) }
    for k := 0 to probes.Count - 1 do
    begin
      p := probes.Objects[k];
      code := p.Strings['code'];
      if (code <> 'x') and (Copy(code, 1, 2) <> 'e:') then Continue;
      wantCur := p.Strings['cursor'];
      cur := FChart.CursorAt(p.Integers['x'], p.Integers['y']);
      Inc(nCmp);
      if cur <> wantCur then
      begin
        Inc(nBad);
        if Length(bad) < 3000 then
          bad := bad + Format('%s cursor (%d,%d): %s, upstream %s; ', [id,
            p.Integers['x'], p.Integers['y'], cur, wantCur]);
      end;
    end;
  end;
  AssertTrue('compared', nCmp > 150);
  AssertEquals(bad, 0, nBad);
end;

initialization
  RegisterTest(TAdvChartRenderGapsTest);
end.
