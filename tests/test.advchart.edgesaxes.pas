unit test.advchart.edgesaxes;
{$mode objfpc}{$H+}
{ THE AXES' EDGES AND THE ROUND'S RESIDUALS [R5-G, spec 244].

  tools/advchart-oracle/edges-axes.js records, on ECharts 6.1: a grid's own
  background rect (GridView: `show`, backgroundColor, the item-style keys of
  the grid model, z2 -1 under the axes); what a chart of no series still
  draws (a toolbox, a timeline, a visualMap); the ends of a radar's pens
  (AxisBuilder's round axis-line cap, the author's caps, joins and
  miterLimit); and a gradient written as an axis piece's colour -- each
  stroked element's stroke-grown box and the canvas gradient over it. The
  replay holds the control to those; the gradients by the pixels along the
  lines, which must ramp as the canvas' gradient ramps.

  Beside the oracle: a PPI change alone lays the chart out again, as a
  chart born at that PPI is laid out. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller, tyControls.Painter,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Export, tyControls.AdvanceChart.Toolbox,
     tyControls.AdvanceChart.Builder, tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart.Layout, tyControls.AdvanceChart.Polar,
     tyControls.AdvanceChart.ThemeRiver, tyControls.AdvanceChart.Coord,
     tyControls.AdvanceChart.Scale, tyControls.AdvanceChart.Title,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TEaProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    { node's text estimate, where a case is held to upstream's overlap
      decisions }
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Grids(AList: TTyPaintList);
    procedure Move(AX, AY: Integer);
  end;

  TAdvChartEdgesAxesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TEaProbe;
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure NewChart(AW, AH: Integer);
    function RenderBmp(APPI: Integer = 96): TBGRABitmap;
    function Cases(const AKey: string): TJSONArray;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGridBackgroundsAreUpstreams;
    procedure TestAShownGridPaintsItsBackground;
    procedure TestAChartOfNoSeriesDrawsItsComponents;
    procedure TestTheRadarPenEndsAreUpstreams;
    procedure TestAGradientAxisPieceRampsAsUpstreams;
    procedure TestAPpiChangeAloneLaysTheChartOutAgain;
    procedure TestEveryBlendModeReachesTheMarks;
    procedure TestTheNonSeparableModesMixAsTheSpecification;
    procedure TestThePorterDuffOperatorsCompositeAsTheCanvas;
    procedure TestAClipOffThePixelGridCutsAtItsEdge;
    procedure TestTheRadarLabelsGiveWayAsUpstreams;
    procedure TestAPolarAxisSnapsByTheWidthItIsDrawnWith;
    procedure TestTheSnapWidthsFollowTheirChains;
    procedure TestARiversGapsOutliveAResizeAsUpstreams;
    procedure TestALogAxisTakesAPointerOverItsMappingExtent;
    procedure TestAlignTicksAsUpstreams;
    procedure TestAHigherZLevelIsOverTheTitleAndTheMask;
    procedure TestATitlesBoxIsTheAuthors;
  end;

implementation

procedure TEaProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TEaProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TEaProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TEaProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TEaProbe.Grids(AList: TTyPaintList);
begin
  AddGridBackgrounds(AList);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-edges-axes.json';
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

function HexOf(AData: TJSONData): Double;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  Result := FromHex(AData.AsString);
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := (A = B) or (IsNan(A) and IsNan(B));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

procedure TAdvChartEdgesAxesOracleTest.SetUp;
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

procedure TAdvChartEdgesAxesOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartEdgesAxesOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 60 then FReport := FReport + LineEnding + '  ' + FWhere + ': ' + AWhat;
end;

procedure TAdvChartEdgesAxesOracleTest.NewChart(AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FChart := TEaProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

function TAdvChartEdgesAxesOracleTest.RenderBmp(APPI: Integer): TBGRABitmap;
begin
  Result := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  FChart.Render(Result.Canvas, Rect(0, 0, FChart.Width, FChart.Height), APPI);
end;

function TAdvChartEdgesAxesOracleTest.Cases(const AKey: string): TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays[AKey];
end;

{ ==================== the grids ==================== }

procedure TAdvChartEdgesAxesOracleTest.TestTheGridBackgroundsAreUpstreams;
var
  cs, g, gradObj: TJSONObject;
  grids: TJSONArray;
  c, k, j, at: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  b: TTyRectF;
  d: TJSONData;
  want: TTyChartColor;
  w: Double;
  wantDash: TTyDoubleArray;
  bmp: TBGRABitmap;
begin
  for c := 0 to Cases('grid').Count - 1 do
  begin
    cs := Cases('grid').Objects[c];
    FWhere := cs.Strings['id'];
    NewChart(600, 400);
    FChart.Option := cs.Objects['option'].AsJSON;
    bmp := RenderBmp;
    bmp.Free;
    lst := TTyPaintList.Create;
    try
      FChart.Grids(lst);
      grids := cs.Arrays['grids'];
      at := 0;
      for k := 0 to grids.Count - 1 do
      begin
        g := grids.Objects[k];
        if not g.Booleans['present'] then Continue;
        Inc(FCompared);
        if at >= lst.Count then
        begin
          Bad(Format('grid %d: a rect upstream, none here', [k]));
          Continue;
        end;
        e := lst.Element(at);
        Inc(at);
        b := TyShapeBounds(e.Shape);
        if not (SameBits(b.Left, HexOf(g.Arrays['rect'][0])) and SameBits(b.Top, HexOf(g.Arrays['rect'][1]))
          and SameBits(b.Right - b.Left, HexOf(g.Arrays['rect'][2]))
          and SameBits(b.Bottom - b.Top, HexOf(g.Arrays['rect'][3]))) then
          Bad(Format('grid %d: rect %s,%s %sx%s', [k, Fmt(b.Left), Fmt(b.Top),
            Fmt(b.Right - b.Left), Fmt(b.Bottom - b.Top)]));
        { the fill: a colour of no alpha is none }
        d := g.Find('fill');
        if d.JSONType = jtString then
        begin
          AssertTrue(FWhere + ' fill parses', TyTryParseChartColor(d.AsString, want));
          if (want shr 24) = 0 then
          begin
            if e.Style.HasFill then Bad(Format('grid %d: a fill here, none upstream', [k]));
          end
          else if not e.Style.HasFill or (e.Style.FillColor <> want) then
            Bad(Format('grid %d: fill %s upstream, %x here', [k, d.AsString, e.Style.FillColor]));
        end
        else
        begin
          gradObj := TJSONObject(d);
          if not e.Style.HasFill or (e.Style.FillGradient.Kind = cgkNone)
            or (Length(e.Style.FillGradient.Stops) <> gradObj.Arrays['stops'].Count)
            or (e.Style.FillGradient.Y2 <> gradObj.Floats['y2']) then
            Bad(Format('grid %d: the gradient fill', [k]))
          else
            for j := 0 to gradObj.Arrays['stops'].Count - 1 do
            begin
              TyTryParseChartColor(gradObj.Arrays['stops'].Arrays[j].Strings[1], want);
              if e.Style.FillGradient.Stops[j].Color <> want then
                Bad(Format('grid %d: gradient stop %d', [k, j]));
            end;
        end;
        { the stroke: 'none' or a width of nought strokes nothing }
        w := HexOf(g.Find('lineWidth'));
        if (g.Strings['stroke'] = 'none') or (w <= 0) then
        begin
          if e.Style.StrokeWidthLogical > 0 then Bad(Format('grid %d: a stroke here', [k]));
        end
        else
        begin
          AssertTrue(FWhere + ' stroke parses', TyTryParseChartColor(g.Strings['stroke'], want));
          if (e.Style.StrokeColor <> want) or (e.Style.StrokeWidthLogical <> w) then
            Bad(Format('grid %d: stroke %s %s upstream, %x %s here', [k, g.Strings['stroke'],
              Fmt(w), e.Style.StrokeColor, Fmt(e.Style.StrokeWidthLogical)]));
          { normalizeLineDash: the words against the width, a list verbatim }
          wantDash := nil;
          d := g.Find('lineDash');
          if d.JSONType = jtString then
          begin
            if d.AsString = 'dashed' then
            begin
              SetLength(wantDash, 2);
              wantDash[0] := 4 * w;
              wantDash[1] := 2 * w;
            end
            else if d.AsString = 'dotted' then
            begin
              SetLength(wantDash, 1);
              wantDash[0] := w;
            end;
          end
          else if d is TJSONArray then
          begin
            SetLength(wantDash, TJSONArray(d).Count);
            for j := 0 to High(wantDash) do wantDash[j] := TJSONArray(d).Floats[j];
          end;
          if Length(wantDash) <> Length(e.Style.DashLogical) then
            Bad(Format('grid %d: dash of %d upstream, %d here', [k, Length(wantDash),
              Length(e.Style.DashLogical)]))
          else
            for j := 0 to High(wantDash) do
              if wantDash[j] <> e.Style.DashLogical[j] then
                Bad(Format('grid %d: dash %d', [k, j]));
          if not IsNan(HexOf(g.Find('lineDashOffset')))
            and (e.Style.DashOffsetLogical <> HexOf(g.Find('lineDashOffset'))) then
            Bad(Format('grid %d: dash offset', [k]));
          if (g.Find('lineCap').JSONType = jtString) and (g.Strings['lineCap'] = 'round')
            <> (e.Style.LineCap = cTyCapRound) then
            Bad(Format('grid %d: the cap', [k]));
        end;
        if IsNan(HexOf(g.Find('opacity'))) then
        begin
          if e.Style.Alpha <> 1 then Bad(Format('grid %d: opacity', [k]));
        end
        else if e.Style.Alpha <> HexOf(g.Find('opacity')) then
          Bad(Format('grid %d: opacity %s here', [k, Fmt(e.Style.Alpha)]));
        if (e.Style.ShadowBlur <> HexOf(g.Find('shadowBlur')))
          or (e.Style.ShadowOffsetX <> HexOf(g.Find('shadowOffsetX')))
          or (e.Style.ShadowOffsetY <> HexOf(g.Find('shadowOffsetY'))) then
          Bad(Format('grid %d: the shadow %s %s %s here', [k, Fmt(e.Style.ShadowBlur),
            Fmt(e.Style.ShadowOffsetX), Fmt(e.Style.ShadowOffsetY)]));
        if (g.Find('shadowColor').JSONType = jtString) and (e.Style.ShadowBlur > 0) then
        begin
          TyTryParseChartColor(g.Strings['shadowColor'], want);
          if e.Style.ShadowColor <> want then Bad(Format('grid %d: the shadow colour', [k]));
        end;
        if (e.Z <> g.Integers['z']) or (e.Z2 <> g.Integers['z2']) or (e.ZLevel <> g.Integers['zlevel'])
          or (e.Silent <> g.Booleans['silent']) then
          Bad(Format('grid %d: z %d z2 %d zlevel %d silent %s here', [k, e.Z, e.Z2, e.ZLevel,
            BoolToStr(e.Silent, True)]));
        if not g.Booleans['underAxes'] then Bad('upstream draws it over an axis');
      end;
      if at <> lst.Count then Bad(Format('%d rects here, %d upstream', [lst.Count, at]));
      if (at > 0) <> (cvGrid in FChart.LastViewsDrawn) then
        Bad('the grid view drew / did not draw');
    finally
      lst.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' disagree:' + FReport, 0, FBad);
  AssertTrue('enough compared', FCompared >= 6);
end;

procedure TAdvChartEdgesAxesOracleTest.TestAShownGridPaintsItsBackground;
var
  bmp: TBGRABitmap;
  r: TTyXYWH;
  p: TBGRAPixel;
  x, y: Integer;
begin
  { a green ground inside the plot, between the bars: the rect is painted,
    under the axes and the bars }
  NewChart(600, 400);
  FChart.Option := '{"animation":false,"grid":{"show":true,"backgroundColor":"#00ff00",'
    + '"borderColor":"#0000ff","borderWidth":4},"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value","splitLine":{"show":false}},"series":[{"type":"bar","data":[1,2]}]}';
  bmp := RenderBmp;
  try
    r := FChart.Build.Grid(0).PlotXYWH;
    { the ground: just inside the left edge, a third of the way down }
    x := Round(r.X + 8);
    y := Round(r.Y + r.H / 3);
    p := bmp.GetPixel(x, y);
    AssertTrue(Format('green inside the plot at %d,%d: %d %d %d', [x, y, p.red, p.green, p.blue]),
      (p.green > 240) and (p.red < 16) and (p.blue < 16));
    { the border: blue on the top edge, mid-way }
    p := bmp.GetPixel(Round(r.X + r.W / 2), Round(r.Y));
    AssertTrue(Format('the blue border: %d %d %d', [p.red, p.green, p.blue]),
      (p.blue > 200) and (p.red < 60) and (p.green < 60));
  finally
    bmp.Free;
  end;
end;

{ ==================== no series ==================== }

procedure TAdvChartEdgesAxesOracleTest.TestAChartOfNoSeriesDrawsItsComponents;
var
  cs, tb: TJSONObject;
  c: Integer;
  bmp: TBGRABitmap;
  lay: TTyToolboxLayout;
begin
  for c := 0 to Cases('alone').Count - 1 do
  begin
    cs := Cases('alone').Objects[c];
    FWhere := cs.Strings['id'];
    NewChart(600, 400);
    FChart.Option := cs.Objects['option'].AsJSON;
    bmp := RenderBmp;
    bmp.Free;
    if cs.Find('toolbox') <> nil then
    begin
      tb := cs.Objects['toolbox'];
      Inc(FCompared);
      if FChart.ToolboxCount < 1 then Bad('no toolbox')
      else
      begin
        lay := FChart.ToolboxLayout(0);
        if not lay.Valid then Bad('the toolbox is not laid out')
        else if not (SameBits(lay.GroupX, FromHex(tb.Strings['x']))
          and SameBits(lay.GroupY, FromHex(tb.Strings['y']))) then
          Bad(Format('the toolbox at %s,%s', [Fmt(lay.GroupX), Fmt(lay.GroupY)]));
        if Length(FChart.ToolboxSpec(0).Icons) <> tb.Integers['icons'] then
          Bad(Format('%d icons here', [Length(FChart.ToolboxSpec(0).Icons)]));
        if not (cvToolbox in FChart.LastViewsDrawn) then Bad('the toolbox drew nothing');
      end;
    end;
    if cs.Find('timeline') <> nil then
    begin
      Inc(FCompared);
      if (cs.Integers['timeline'] > 0) <> (cvTimeline in FChart.LastViewsDrawn) then
        Bad('the timeline');
    end;
    if cs.Find('visualMap') <> nil then
    begin
      Inc(FCompared);
      if (cs.Integers['visualMap'] > 0) <> (cvVisualMap in FChart.LastViewsDrawn) then
        Bad('the visualMap');
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' disagree:' + FReport, 0, FBad);
  AssertTrue('enough compared', FCompared >= 4);
end;

{ ==================== the radar ==================== }

procedure TAdvChartEdgesAxesOracleTest.TestTheRadarPenEndsAreUpstreams;
var
  cs: TJSONObject;
  c, i: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  bmp: TBGRABitmap;
  nLine, nTick, nSplit: Integer;

  function CapOf(AData: TJSONData): Byte;
  begin
    if (AData = nil) or (AData.JSONType <> jtString) then Exit(cTyCapButt);
    Result := TyCapOfWord(AData.AsString);
  end;

  function JoinOf(AData: TJSONData): Byte;
  begin
    if (AData = nil) or (AData.JSONType <> jtString) then Exit(cTyJoinMiter);
    Result := TyJoinOfWord(AData.AsString);
  end;

  { the canvas' miterLimit: 0 here is its 10 }
  function MiterOf(AData: TJSONData): Double;
  begin
    if (AData = nil) or (AData.JSONType <> jtNumber) then Exit(10);
    Result := AData.AsFloat;
  end;

  procedure Ends(const AWhat: string; const AE: TTyChartElement; AWant: TJSONObject);
  var m: Double;
  begin
    Inc(FCompared);
    m := AE.Style.MiterLimit;
    if m <= 0 then m := 10;
    if (AE.Style.LineCap <> CapOf(AWant.Find('cap')))
      or (AE.Style.LineJoin <> JoinOf(AWant.Find('join'))) or (m <> MiterOf(AWant.Find('miter'))) then
      Bad(Format('%s: cap %d join %d miter %s here, %s upstream', [AWhat, AE.Style.LineCap,
        AE.Style.LineJoin, Fmt(m), AWant.AsJSON]));
  end;

begin
  for c := 0 to Cases('radar').Count - 1 do
  begin
    cs := Cases('radar').Objects[c];
    FWhere := cs.Strings['id'];
    NewChart(600, 400);
    FChart.Option := cs.Objects['option'].AsJSON;
    bmp := RenderBmp;
    bmp.Free;
    lst := FChart.List;
    nLine := 0;
    nTick := 0;
    nSplit := 0;
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if e.Datum.SeriesIndex >= 0 then Continue;
      if (e.Shape.Kind <> cskPolyline) and (e.Shape.Kind <> cskCircle) then Continue;
      if e.Style.HasFill or (e.Caption.Text <> '') then Continue;
      case e.Z2 of
        0:
          begin
            Ends('split line', e, cs.Arrays['splitLines'].Objects[0]);
            Inc(nSplit);
          end;
        1:
          begin
            if nLine < cs.Arrays['axisLines'].Count then
              Ends('axis line ' + IntToStr(nLine), e, cs.Arrays['axisLines'].Objects[nLine]);
            Inc(nLine);
          end;
        2:
          begin
            if cs.Arrays['ticks'].Count > 0 then
              Ends('tick', e, cs.Arrays['ticks'].Objects[0]);
            Inc(nTick);
          end;
      end;
    end;
    if nLine <> cs.Arrays['axisLines'].Count then Bad(Format('%d axis lines', [nLine]));
    if (nTick > 0) <> (cs.Arrays['ticks'].Count > 0) then Bad(Format('%d ticks', [nTick]));
    if nSplit = 0 then Bad('no split lines');
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' disagree:' + FReport, 0, FBad);
  AssertTrue('enough compared', FCompared >= 20);
end;

{ ==================== gradients on the axis pieces ==================== }

{ the canvas' linear gradient at (AX, AY): the projection on the vector
  from (X1, Y1) to (X2, Y2), clamped, the stops interpolated in sRGB }
function RampAt(AStops: TJSONArray; X1, Y1, X2, Y2, AX, AY: Double): TBGRAPixel;
var
  dx, dy, t, len2, u: Double;
  k: Integer;
  c0, c1: TTyChartColor;
  o0, o1: Double;
begin
  dx := X2 - X1;
  dy := Y2 - Y1;
  len2 := dx * dx + dy * dy;
  if len2 = 0 then t := 0
  else t := ((AX - X1) * dx + (AY - Y1) * dy) / len2;
  if t < 0 then t := 0;
  if t > 1 then t := 1;
  k := 0;
  while (k < AStops.Count - 2) and (t > AStops.Arrays[k + 1].Floats[0]) do Inc(k);
  o0 := AStops.Arrays[k].Floats[0];
  o1 := AStops.Arrays[k + 1].Floats[0];
  TyTryParseChartColor(AStops.Arrays[k].Strings[1], c0);
  TyTryParseChartColor(AStops.Arrays[k + 1].Strings[1], c1);
  if o1 > o0 then u := (t - o0) / (o1 - o0) else u := 0;
  if u < 0 then u := 0;
  if u > 1 then u := 1;
  Result.red := Round(((c0 shr 16) and $FF) * (1 - u) + ((c1 shr 16) and $FF) * u);
  Result.green := Round(((c0 shr 8) and $FF) * (1 - u) + ((c1 shr 8) and $FF) * u);
  Result.blue := Round((c0 and $FF) * (1 - u) + (c1 and $FF) * u);
  Result.alpha := 255;
end;

procedure TAdvChartEdgesAxesOracleTest.TestAGradientAxisPieceRampsAsUpstreams;
var
  cs, s: TJSONObject;
  c, k, q: Integer;
  bmp: TBGRABitmap;
  x1, y1, x2, y2, gx1, gy1, gx2, gy2, px, py, f: Double;
  want, got: TBGRAPixel;
  role: string;
  samples: Integer;
begin
  samples := 0;
  for c := 0 to Cases('gradient').Count - 1 do
  begin
    cs := Cases('gradient').Objects[c];
    NewChart(600, 400);
    FChart.Option := cs.Objects['option'].AsJSON;
    bmp := RenderBmp;
    try
      for k := 0 to cs.Arrays['strokes'].Count - 1 do
      begin
        s := cs.Arrays['strokes'].Objects[k];
        role := s.Strings['role'];
        FWhere := cs.Strings['id'] + ' ' + s.Strings['axis'] + ' ' + role + ' ' + IntToStr(k);
        x1 := FromHex(s.Arrays['ends'].Strings[0]);
        y1 := FromHex(s.Arrays['ends'].Strings[1]);
        x2 := FromHex(s.Arrays['ends'].Strings[2]);
        y2 := FromHex(s.Arrays['ends'].Strings[3]);
        gx1 := FromHex(s.Arrays['gradient'].Strings[0]);
        gy1 := FromHex(s.Arrays['gradient'].Strings[1]);
        gx2 := FromHex(s.Arrays['gradient'].Strings[2]);
        gy2 := FromHex(s.Arrays['gradient'].Strings[3]);
        { along the line, clear of its ends (caps, the other axis); a split
          line between the bars only (a quarter and three quarters of a
          band in, where no bar stands) }
        for q := 1 to 9 do
        begin
          f := q / 10;
          if role = 'split' then
          begin
            if not (q in [1, 9]) then Continue;
            if q = 1 then f := 0.02 else f := 0.98;
          end;
          px := x1 + (x2 - x1) * f;
          py := y1 + (y2 - y1) * f;
          { the pixel whose centre is nearest the line's centre point }
          want := RampAt(s.Arrays['stops'], gx1, gy1, gx2, gy2, Floor(px) + 0.5, Floor(py) + 0.5);
          got := bmp.GetPixel(Floor(px), Floor(py));
          Inc(FCompared);
          Inc(samples);
          if (Abs(Integer(got.red) - want.red) > 12) or (Abs(Integer(got.green) - want.green) > 12)
            or (Abs(Integer(got.blue) - want.blue) > 12) then
            Bad(Format('at %d,%d: %d %d %d upstream, %d %d %d here', [Floor(px), Floor(py),
              want.red, want.green, want.blue, got.red, got.green, got.blue]));
        end;
      end;
    finally
      bmp.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' disagree:' + FReport, 0, FBad);
  AssertTrue(Format('enough sampled (%d)', [samples]), samples >= 60);
end;

{ ==================== the PPI ==================== }

procedure TAdvChartEdgesAxesOracleTest.TestAPpiChangeAloneLaysTheChartOutAgain;
const
  { the plot holds the labels (containLabel): its edges are the labels'
    widths, measured in the fonts of the PPI the chart is drawn at }
  cOpt = '{"animation":false,"grid":{"left":10,"top":40,"right":30,"bottom":40,"containLabel":true},'
    + '"xAxis":{"type":"category","data":["alpha","beta","gamma"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","data":[1000000,2000000,3000000]}]}';

  function BornAt(APPI: Integer): TTyXYWH;
  var other: TEaProbe; b: TBGRABitmap;
  begin
    other := TEaProbe.Create(FForm);
    try
      other.Parent := FForm;
      other.Controller := FCtl;
      other.AnimationMode := camOff;
      other.SetBounds(0, 0, 600, 400);
      other.Option := cOpt;
      b := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
      try
        other.Render(b.Canvas, Rect(0, 0, 600, 400), APPI);
      finally
        b.Free;
      end;
      Result := other.Build.Grid(0).PlotXYWH;
    finally
      other.Free;
    end;
  end;

var
  bmp: TBGRABitmap;
  moved, born, born96: TTyXYWH;
begin
  NewChart(600, 400);
  FChart.Option := cOpt;
  bmp := RenderBmp(96);
  bmp.Free;
  { the same control, the same pixels, another monitor's DPI }
  bmp := RenderBmp(144);
  bmp.Free;
  moved := FChart.Build.Grid(0).PlotXYWH;
  born := BornAt(144);
  born96 := BornAt(96);
  { the case means something: the two PPIs lay the plot out differently }
  AssertTrue(Format('the PPI moves the plot: %s at 96, %s at 144', [Fmt(born96.X), Fmt(born.X)]),
    (born96.X <> born.X) or (born96.W <> born.W));
  AssertTrue(Format('the plot at 144 PPI: %s,%s %sx%s, born there %s,%s %sx%s',
    [Fmt(moved.X), Fmt(moved.Y), Fmt(moved.W), Fmt(moved.H), Fmt(born.X), Fmt(born.Y),
     Fmt(born.W), Fmt(born.H)]),
    (moved.X = born.X) and (moved.Y = born.Y) and (moved.W = born.W) and (moved.H = born.H));
end;

{ ==================== blend modes ==================== }

procedure TAdvChartEdgesAxesOracleTest.TestEveryBlendModeReachesTheMarks;
var
  cs: TJSONObject;
  c, i, n: Integer;
  e: TTyChartElement;
  bmp: TBGRABitmap;
begin
  for c := 0 to Cases('blend').Count - 1 do
  begin
    cs := Cases('blend').Objects[c];
    FWhere := cs.Strings['mode'];
    NewChart(600, 400);
    FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d"]},'
      + '"yAxis":{"type":"value"},"series":[{"type":"bar","blendMode":"' + cs.Strings['mode']
      + '","data":[5,3,8,2]}]}';
    bmp := RenderBmp;
    bmp.Free;
    n := 0;
    for i := 0 to FChart.List.Count - 1 do
    begin
      e := FChart.List.Element(i);
      if e.Anim.Role <> carBar then Continue;
      Inc(n);
      Inc(FCompared);
      if e.Style.Blend <> cs.Strings['mode'] then Bad('a bar blends ' + e.Style.Blend);
    end;
    if n <> cs.Arrays['blends'].Count then Bad(Format('%d bars', [n]));
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' disagree:' + FReport, 0, FBad);
end;

function NewLayer(AW, AH: Integer; out ABmp: TBGRABitmap): TTyPainter;
var sc: TTyCanvasScale;
begin
  ABmp := TBGRABitmap.Create(AW, AH, BGRAPixelTransparent);
  sc.Scale := 1;
  sc.DeviceUnits := False;
  Result := TTyPainter.Create;
  Result.BeginPaintOnScaled(nil, Rect(0, 0, AW, AH), 96, ABmp, sc);
end;

{ the compositing specification's own words, written out again here }
procedure SpecNonSeparable(const AMode: string; BR, BG, BB, SR, SG, SB: Double;
  out R, G, B: Double);

  function Lum(R_, G_, B_: Double): Double;
  begin
    Result := 0.3 * R_ + 0.59 * G_ + 0.11 * B_;
  end;

  procedure SetLumClip(var R_, G_, B_: Double; L: Double);
  var d, l2, n, x: Double;
  begin
    d := L - Lum(R_, G_, B_);
    R_ := R_ + d; G_ := G_ + d; B_ := B_ + d;
    l2 := Lum(R_, G_, B_);
    n := Min(R_, Min(G_, B_));
    x := Max(R_, Max(G_, B_));
    if n < 0 then
    begin
      R_ := l2 + (R_ - l2) * l2 / (l2 - n);
      G_ := l2 + (G_ - l2) * l2 / (l2 - n);
      B_ := l2 + (B_ - l2) * l2 / (l2 - n);
    end;
    if x > 1 then
    begin
      R_ := l2 + (R_ - l2) * (1 - l2) / (x - l2);
      G_ := l2 + (G_ - l2) * (1 - l2) / (x - l2);
      B_ := l2 + (B_ - l2) * (1 - l2) / (x - l2);
    end;
  end;

  function SatOf(R_, G_, B_: Double): Double;
  begin
    Result := Max(R_, Max(G_, B_)) - Min(R_, Min(G_, B_));
  end;

  procedure SetSat(var R_, G_, B_: Double; S: Double);
  var mx, mn: Double;
    function F(C: Double): Double;
    begin
      if C = mx then Result := S
      else if C = mn then Result := 0
      else Result := (C - mn) * S / (mx - mn);
    end;
  begin
    mx := Max(R_, Max(G_, B_));
    mn := Min(R_, Min(G_, B_));
    if mx = mn then
    begin
      R_ := 0; G_ := 0; B_ := 0;
      Exit;
    end;
    R_ := F(R_); G_ := F(G_); B_ := F(B_);
  end;

begin
  if AMode = 'hue' then
  begin
    R := SR; G := SG; B := SB;
    SetSat(R, G, B, SatOf(BR, BG, BB));
    SetLumClip(R, G, B, Lum(BR, BG, BB));
  end
  else if AMode = 'saturation' then
  begin
    R := BR; G := BG; B := BB;
    SetSat(R, G, B, SatOf(SR, SG, SB));
    SetLumClip(R, G, B, Lum(BR, BG, BB));
  end
  else if AMode = 'color' then
  begin
    R := SR; G := SG; B := SB;
    SetLumClip(R, G, B, Lum(BR, BG, BB));
  end
  else
  begin
    R := BR; G := BG; B := BB;
    SetLumClip(R, G, B, Lum(SR, SG, SB));
  end;
end;

procedure TAdvChartEdgesAxesOracleTest.TestTheNonSeparableModesMixAsTheSpecification;
const
  cModes: array[0..3] of string = ('hue', 'saturation', 'color', 'luminosity');
  { a backdrop and a source that differ in hue, saturation and lightness }
  cB: array[0..2] of Byte = (40, 160, 220);
  cS: array[0..2] of Byte = (230, 90, 20);
var
  p: TTyPainter;
  bmp: TBGRABitmap;
  m: Integer;
  r, g, b: Double;
  px: TBGRAPixel;
begin
  for m := 0 to High(cModes) do
  begin
    p := NewLayer(60, 60, bmp);
    try
      bmp.FillRect(0, 0, 60, 60, BGRA(cB[0], cB[1], cB[2], 255), dmSet);
      p.SetBlendMode(cModes[m]);
      p.BeginPath;
      p.RectPath(10, 10, 50, 50);
      p.FillPath(TyRGBA(cS[0], cS[1], cS[2], 255));
      p.SetBlendMode('');
      p.EndPaint;
      { an opaque source over an opaque backdrop: the blend itself }
      SpecNonSeparable(cModes[m], cB[0] / 255, cB[1] / 255, cB[2] / 255,
        cS[0] / 255, cS[1] / 255, cS[2] / 255, r, g, b);
      px := bmp.GetPixel(30, 30);
      AssertTrue(Format('%s: %d %d %d, the specification %d %d %d', [cModes[m], px.red, px.green,
        px.blue, Round(r * 255), Round(g * 255), Round(b * 255)]),
        (Abs(px.red - Round(r * 255)) <= 1) and (Abs(px.green - Round(g * 255)) <= 1)
        and (Abs(px.blue - Round(b * 255)) <= 1));
      { and not the plain source }
      AssertFalse(cModes[m] + ' is not source over',
        (px.red = cS[0]) and (px.green = cS[1]) and (px.blue = cS[2]));
      px := bmp.GetPixel(5, 5);
      AssertEquals(cModes[m] + ': outside the shape as it was', cB[0], px.red);
    finally
      p.Free;
      bmp.Free;
    end;
  end;
end;

procedure TAdvChartEdgesAxesOracleTest.TestThePorterDuffOperatorsCompositeAsTheCanvas;
var
  p: TTyPainter;
  bmp: TBGRABitmap;
  px: TBGRAPixel;

  { a half-covered backdrop (left half opaque blue), a red square over the
    middle, the operator AOp }
  procedure Run(const AOp: string);
  begin
    p := NewLayer(80, 40, bmp);
    bmp.FillRect(0, 0, 40, 40, BGRA(0, 0, 255, 255), dmSet);
    p.SetBlendMode(AOp);
    p.BeginPath;
    p.RectPath(20, 10, 60, 30);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.SetBlendMode('');
    p.EndPaint;
  end;

  procedure Done;
  begin
    p.Free;
    bmp.Free;
  end;

  function Is_(const APx: TBGRAPixel; R, G, B, A: Integer): Boolean;
  begin
    if A = 0 then Exit(APx.alpha = 0);
    Result := (APx.red = R) and (APx.green = G) and (APx.blue = B) and (APx.alpha = A);
  end;

begin
  { (30, 20): source over the backdrop; (50, 20): source over nothing;
    (10, 20): the backdrop, no source; (70, 20): neither }
  Run('source-atop');
  try
    AssertTrue('source-atop: the source on the backdrop', Is_(bmp.GetPixel(30, 20), 255, 0, 0, 255));
    AssertTrue('source-atop: nothing where there is no backdrop', Is_(bmp.GetPixel(50, 20), 0, 0, 0, 0));
    AssertTrue('source-atop: the backdrop kept', Is_(bmp.GetPixel(10, 20), 0, 0, 255, 255));
  finally
    Done;
  end;
  Run('destination-over');
  try
    AssertTrue('destination-over: the backdrop on top', Is_(bmp.GetPixel(30, 20), 0, 0, 255, 255));
    AssertTrue('destination-over: the source under nothing', Is_(bmp.GetPixel(50, 20), 255, 0, 0, 255));
  finally
    Done;
  end;
  Run('destination-out');
  try
    AssertTrue('destination-out: the backdrop cut away', Is_(bmp.GetPixel(30, 20), 0, 0, 0, 0));
    AssertTrue('destination-out: nothing added', Is_(bmp.GetPixel(50, 20), 0, 0, 0, 0));
    AssertTrue('destination-out: the rest kept', Is_(bmp.GetPixel(10, 20), 0, 0, 255, 255));
  finally
    Done;
  end;
  Run('xor');
  try
    AssertTrue('xor: both there is neither', Is_(bmp.GetPixel(30, 20), 0, 0, 0, 0));
    AssertTrue('xor: the source alone', Is_(bmp.GetPixel(50, 20), 255, 0, 0, 255));
    AssertTrue('xor: the backdrop alone', Is_(bmp.GetPixel(10, 20), 0, 0, 255, 255));
  finally
    Done;
  end;
  { THE CLEARING OPERATORS clear where the source has no ink: the whole
    canvas, as the canvas does }
  Run('source-in');
  try
    AssertTrue('source-in: the source where there was a backdrop', Is_(bmp.GetPixel(30, 20), 255, 0, 0, 255));
    AssertTrue('source-in: nothing where there was none', Is_(bmp.GetPixel(50, 20), 0, 0, 0, 0));
    AssertTrue('source-in: the backdrop outside the source cleared', Is_(bmp.GetPixel(10, 20), 0, 0, 0, 0));
  finally
    Done;
  end;
  Run('copy');
  try
    AssertTrue('copy: the source', Is_(bmp.GetPixel(30, 20), 255, 0, 0, 255));
    AssertTrue('copy: the rest cleared', Is_(bmp.GetPixel(10, 20), 0, 0, 0, 0));
  finally
    Done;
  end;
  Run('destination-in');
  try
    AssertTrue('destination-in: the backdrop under the source', Is_(bmp.GetPixel(30, 20), 0, 0, 255, 255));
    AssertTrue('destination-in: the rest cleared', Is_(bmp.GetPixel(10, 20), 0, 0, 0, 0));
  finally
    Done;
  end;
end;

{ ==================== the clip ==================== }

{ A line's clip is getArea grown by half its width, its y not rounded
  (Line.ts createGridClipPath): a 1 px line on a grid at y 60 clips at 59.5,
  and an area that runs past the axis' max is cut there -- the pixel row 59
  half covered, as the canvas' clip() covers it, not whole }
procedure TAdvChartEdgesAxesOracleTest.TestAClipOffThePixelGridCutsAtItsEdge;
var
  bmp: TBGRABitmap;
  r: TTyXYWH;
  px: TBGRAPixel;
  x: Integer;
begin
  NewChart(400, 300);
  FChart.Option := '{"animation":false,"grid":{"left":40,"right":40,"top":60,"bottom":40},'
    + '"xAxis":{"type":"category","boundaryGap":false,"data":["a","b","c"],"axisLine":{"show":false}},'
    + '"yAxis":{"type":"value","max":5,"splitLine":{"show":false}},'
    + '"series":[{"type":"line","symbol":"none","lineStyle":{"width":1,"color":"#0000ff"},'
    + '"areaStyle":{"color":"#0000ff","opacity":1},"data":[10,10,10]}]}';
  bmp := RenderBmp;
  try
    r := FChart.Build.Grid(0).PlotXYWH;
    AssertEquals('the plot''s top', 60.0, r.Y);
    x := Round(r.X + r.W / 2);
    { inside: the area's own blue }
    px := bmp.GetPixel(x, 61);
    AssertTrue(Format('blue inside: %d %d %d', [px.red, px.green, px.blue]),
      (px.blue > 240) and (px.red < 16));
    { the row the clip's edge halves: half blue over the white ground (the
      painter mixes in linear light, so half is 170, not 128 -- spec 1) }
    px := bmp.GetPixel(x, 59);
    AssertTrue(Format('half covered at y 59: %d %d %d', [px.red, px.green, px.blue]),
      (px.red > 90) and (px.red < 200) and (px.blue > 240));
    { and nothing above it }
    px := bmp.GetPixel(x, 57);
    AssertTrue(Format('nothing at y 57: %d %d %d', [px.red, px.green, px.blue]),
      (px.red > 240) and (px.green > 240));
  finally
    bmp.Free;
  end;
end;

{ ==================== the radar's scale labels ==================== }

procedure TAdvChartEdgesAxesOracleTest.TestTheRadarLabelsGiveWayAsUpstreams;
var
  cs, ax: TJSONObject;
  c, i, spoke, k, ticks: Integer;
  e: TTyChartElement;
  bmp: TBGRABitmap;
  measure: TJSONData;
  sl: TStringList;
  want, got: string;
  lst: TTyPaintList;

  procedure Close;
  var q, nt: Integer;
  begin
    if spoke < 0 then Exit;
    Inc(FCompared);
    if spoke >= cs.Arrays['axes'].Count then
    begin
      Bad(Format('spoke %d here, %d upstream', [spoke, cs.Arrays['axes'].Count]));
      Exit;
    end;
    ax := cs.Arrays['axes'].Objects[spoke];
    want := '';
    for q := 0 to ax.Arrays['labels'].Count - 1 do
      if not ax.Arrays['labels'].Objects[q].Booleans['ignore'] then
        want := want + ' ' + ax.Arrays['labels'].Objects[q].Strings['text'];
    nt := 0;
    for q := 0 to ax.Arrays['ticks'].Count - 1 do
      if not ax.Arrays['ticks'].Booleans[q] then Inc(nt);
    if (want <> got) or (nt <> ticks) then
      Bad(Format('spoke %d: labels [%s] ticks %d here, [%s] %d upstream', [spoke, got, ticks, want, nt]));
  end;

begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'advchart-text-style.json');
    measure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  try
    for c := 0 to Cases('radarLabels').Count - 1 do
    begin
      cs := Cases('radarLabels').Objects[c];
      FWhere := cs.Strings['id'];
      NewChart(600, 400);
      FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
        TJSONObject(measure).Objects['ratios'].Arrays['ratio'],
        TJSONObject(measure).Objects['ratios'].Integers['firstCode']));
      FChart.Option := cs.Objects['option'].AsJSON;
      bmp := RenderBmp;
      bmp.Free;
      lst := FChart.List;
      { the radar's elements in the order built: a spoke's line, its ticks,
        its labels }
      spoke := -1;
      got := '';
      ticks := 0;
      for i := 0 to lst.Count - 1 do
      begin
        e := lst.Element(i);
        if e.Datum.SeriesIndex >= 0 then Continue;
        if (e.Z2 = 1) and (e.Shape.Kind = cskPolyline) and (e.Caption.Text = '') then
        begin
          Close;
          Inc(spoke);
          got := '';
          ticks := 0;
        end
        else if (e.Z2 = 2) and (e.Shape.Kind = cskPolyline) then Inc(ticks)
        else if (e.Z2 = 10) and (e.Caption.Text <> '') then got := got + ' ' + e.Caption.Text;
      end;
      Close;
      k := spoke + 1;
      if k <> cs.Arrays['axes'].Count then Bad(Format('%d spokes here', [k]));
    end;
  finally
    measure.Free;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' disagree:' + FReport, 0, FBad);
  AssertTrue('enough compared', FCompared >= 20);
end;

{ ==================== the snap ==================== }

{ subPixelOptimizeLine takes the width the line is stroked with: the radius
  axis stands up from the centre (the angle axis starts at 90), a 2 px skin
  line on x 300 stays on 300, where a 1 px one goes to 300.5 }
procedure TAdvChartEdgesAxesOracleTest.TestAPolarAxisSnapsByTheWidthItIsDrawnWith;
var
  bmp: TBGRABitmap;
  y1, y2: Double;
begin
  NewChart(600, 400);
  FChart.Option := '{"animation":false,"polar":{},"angleAxis":{"type":"value"},'
    + '"radiusAxis":{"axisTick":{"show":true}},"series":[{"type":"bar","coordinateSystem":"polar","data":[1,2]}]}';
  bmp := RenderBmp;
  bmp.Free;
  y1 := FChart.PolarLayout(0).RadiusView.Line.X1;
  AssertEquals('a 1 px line: on the half pixel', 0.5, Frac(y1));
  FCtl.StyleOverride := 'TyAdvChartAxisLine { border-width: 2px; } TyAdvChartAxisTick { border-width: 2px; }';
  try
    FChart.Invalidate;
    bmp := RenderBmp;
    bmp.Free;
    y2 := FChart.PolarLayout(0).RadiusView.Line.X1;
    AssertEquals('a 2 px skin line: on the whole pixel', 0.0, Frac(y2));
    AssertTrue('a tick snapped by 2 too', Frac(FChart.PolarLayout(0).RadiusView.Ticks[1].Y1) = 0);
  finally
    FCtl.StyleOverride := '';
  end;
end;

procedure TAdvChartEdgesAxesOracleTest.TestTheSnapWidthsFollowTheirChains;
var
  txt: TTyAxisTextStyle;
  node: TJSONObject;
begin
  txt := Default(TTyAxisTextStyle);
  txt.AxisLineWidthLogical := 1.5;
  txt.TickLineWidthLogical := 2.5;
  txt.MinorTickLineWidthLogical := 3.5;
  txt.SplitLineWidthLogical := 4.5;
  node := TJSONObject(GetJSON('{}'));
  try
    AssertEquals('the line: the skin''s', 1.5, TyAxisSnapWidth(node, 0, txt));
    AssertEquals('a tick: the skin''s', 2.5, TyAxisSnapWidth(node, 1, txt));
    AssertEquals('a minor tick: the skin''s', 3.5, TyAxisSnapWidth(node, 2, txt));
    AssertEquals('a split line: the skin''s', 4.5, TyAxisSnapWidth(node, 3, txt));
  finally
    node.Free;
  end;
  node := TJSONObject(GetJSON('{"axisLine":{"lineStyle":{"width":5}},"axisTick":{"width":7,'
    + '"lineStyle":{"width":6}},"splitLine":{"lineStyle":{"width":9}}}'));
  try
    AssertEquals('the line: its lineStyle''s', 5.0, TyAxisSnapWidth(node, 0, txt));
    AssertEquals('a tick: its lineStyle''s', 6.0, TyAxisSnapWidth(node, 1, txt));
    AssertEquals('a minor tick: the axisTick model''s own width', 7.0, TyAxisSnapWidth(node, 2, txt));
    AssertEquals('a split line: its lineStyle''s', 9.0, TyAxisSnapWidth(node, 3, txt));
  finally
    node.Free;
  end;
  node := TJSONObject(GetJSON('{"minorTick":{"lineStyle":{"width":8}},"axisTick":{"width":7}}'));
  try
    AssertEquals('a minor tick: its own lineStyle''s first', 8.0, TyAxisSnapWidth(node, 2, txt));
  finally
    node.Free;
  end;
end;

{ ==================== the river's gaps ==================== }

procedure TAdvChartEdgesAxesOracleTest.TestARiversGapsOutliveAResizeAsUpstreams;
var
  river, st: TJSONObject;
  steps: TJSONArray;
  k: Integer;
  bmp: TBGRABitmap;
  lay: TTyThemeRiverLayout;
begin
  river := TJSONObject(FRoot).Objects['river'];
  steps := river.Arrays['steps'];
  NewChart(600, 400);
  FChart.Option := TJSONObject(river.Objects['option'].Clone).AsJSON;
  for k := 0 to steps.Count - 1 do
  begin
    st := steps.Objects[k];
    FWhere := st.Strings['what'];
    case k of
      1: FChart.SetBounds(0, 0, 600, 300);
      2: FChart.SetOption('{"legend":{}}', False);
      3: FChart.SetOption('{"series":[{"boundaryGap":["10%","20%"]}]}', False);
      4: FChart.SetBounds(0, 0, 600, 400);
    end;
    bmp := RenderBmp;
    bmp.Free;
    lay := FChart.RiverLayoutOf(0);
    Inc(FCompared);
    if not (SameBits(lay.Rect.H, FromHex(st.Arrays['rect'].Strings[3]))
      and SameBits(lay.Gap[0], FromHex(st.Arrays['gap'].Strings[0]))
      and SameBits(lay.Gap[1], FromHex(st.Arrays['gap'].Strings[1]))) then
      Bad(Format('gaps %s %s over %s here, %s %s over %s upstream', [Fmt(lay.Gap[0]), Fmt(lay.Gap[1]),
        Fmt(lay.Rect.H), Fmt(FromHex(st.Arrays['gap'].Strings[0])), Fmt(FromHex(st.Arrays['gap'].Strings[1])),
        Fmt(FromHex(st.Arrays['rect'].Strings[3]))]));
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' disagree:' + FReport, 0, FBad);
end;

{ ==================== a log axis' pointer ==================== }

procedure TAdvChartEdgesAxesOracleTest.TestALogAxisTakesAPointerOverItsMappingExtent;
var
  lp: TJSONObject;
  bmp: TBGRABitmap;
  r: TTyXYWH;
  ax: TTyAxis;
  v: Double;
begin
  lp := TJSONObject(FRoot).Objects['logPointer'];
  NewChart(600, 400);
  FChart.Option := lp.Objects['option'].AsJSON;
  bmp := RenderBmp;
  bmp.Free;
  ax := FChart.Build.Grid(0).XAxis(0);
  v := FromHex(lp.Strings['value']);
  { the value at the plot's third pixel: outside the effective extent,
    inside the mapping one -- the first bar's outer half }
  AssertFalse('outside the effective extent', TyRangeContains(ax.Scale.GetExtent2(sekEffective), v));
  AssertEquals('upstream contains it', True, lp.Booleans['contain']);
  r := FChart.Build.Grid(0).PlotXYWH;
  FChart.Move(Round(FromHex(lp.Strings['px'])), Round(r.Y + r.H / 2));
  bmp := RenderBmp;
  bmp.Free;
  AssertTrue('the pointer stands there and the tooltip shows', FChart.TooltipShown);
end;

{ ==================== alignTicks ==================== }

procedure TAdvChartEdgesAxesOracleTest.TestAlignTicksAsUpstreams;
var
  cs, a: TJSONObject;
  c, k, q: Integer;
  bmp: TBGRABitmap;
  ax: TTyAxis;
  e: TTyRange;
  ticks: TTyScaleTickArray;
  gb: TTyGridBuild;
  s: string;
begin
  for c := 0 to Cases('align').Count - 1 do
  begin
    cs := Cases('align').Objects[c];
    FWhere := cs.Strings['id'];
    NewChart(600, 400);
    FChart.Option := cs.Objects['option'].AsJSON;
    bmp := RenderBmp;
    bmp.Free;
    gb := FChart.Build.Grid(0);
    for k := 0 to cs.Arrays['axes'].Count - 1 do
    begin
      a := cs.Arrays['axes'].Objects[k];
      if a.Strings['dim'] = 'xAxis' then ax := gb.XAxis(a.Integers['index'])
      else ax := gb.YAxis(a.Integers['index']);
      Inc(FCompared);
      e := ax.Scale.GetExtent;
      if not (SameBits(e.Start, FromHex(a.Arrays['extent'].Strings[0]))
        and SameBits(e.Stop, FromHex(a.Arrays['extent'].Strings[1]))) then
        Bad(Format('%s%d: extent %s..%s here, %s..%s upstream', [a.Strings['dim'], a.Integers['index'],
          Fmt(e.Start), Fmt(e.Stop), Fmt(FromHex(a.Arrays['extent'].Strings[0])),
          Fmt(FromHex(a.Arrays['extent'].Strings[1]))]));
      if (ax.Scale is TTyIntervalScale)
        and not SameBits(TTyIntervalScale(ax.Scale).Interval, FromHex(a.Strings['interval'])) then
        Bad(Format('%s%d: interval %s here', [a.Strings['dim'], a.Integers['index'],
          Fmt(TTyIntervalScale(ax.Scale).Interval)]));
      ticks := ax.Scale.GetTicks;
      s := '';
      for q := 0 to High(ticks) do s := s + ' ' + Fmt(ticks[q].Value);
      if Length(ticks) <> a.Arrays['ticks'].Count then
        Bad(Format('%s%d: ticks [%s] here, %d upstream', [a.Strings['dim'], a.Integers['index'], s,
          a.Arrays['ticks'].Count]))
      else
        for q := 0 to High(ticks) do
          if not SameBits(ticks[q].Value, FromHex(a.Arrays['ticks'].Strings[q])) then
          begin
            Bad(Format('%s%d: ticks [%s] here', [a.Strings['dim'], a.Integers['index'], s]));
            Break;
          end;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared) + ' disagree:' + FReport, 0, FBad);
end;

{ ==================== zlevel over the components ==================== }

{ A series of zlevel 1 is a canvas over the title (zlevel 0, z 6): the
  title's red box overlaps the blue symbol and the symbol is on top; and
  over the loading mask (zlevel 0, z 10000): the symbol is not whitened }
procedure TAdvChartEdgesAxesOracleTest.TestAHigherZLevelIsOverTheTitleAndTheMask;
var
  zl: TJSONObject;
  bmp: TBGRABitmap;
  x, y, xx, yy: Integer;
  px: TBGRAPixel;
  s: string;
begin
  zl := TJSONObject(FRoot).Objects['zlevel'];
  AssertEquals('upstream: the symbol at zlevel 1', 1, zl.Objects['symbol'].Integers['zlevel']);
  NewChart(600, 400);
  FChart.Option := TJSONObject(zl.Objects['option']).AsJSON;
  x := Round(FromHex(zl.Objects['symbol'].Strings['x']));
  y := Round(FromHex(zl.Objects['symbol'].Strings['y']));
  bmp := RenderBmp;
  try
    px := bmp.GetPixel(x, y);
    AssertTrue(Format('the symbol over the title''s box at %d,%d: %d %d %d', [x, y, px.red, px.green, px.blue]),
      (px.blue > 240) and (px.red < 16) and (px.green < 16));
    { and the box is there, beside the symbol }
    px := bmp.GetPixel(x - 30, y);
    if not ((px.red > 240) and (px.blue < 16)) then
    begin
      s := '';
      for yy := 30 to 130 do
        for xx := 30 to 300 do
        begin
          px := bmp.GetPixel(xx, yy);
          if (px.red > 240) and (px.green < 30) and (px.blue < 30) then
          begin
            s := s + Format(' %d,%d', [xx, yy]);
            Break;
          end;
        end;
      Fail('the title''s red box beside it; red rows start at' + s);
    end;
  finally
    bmp.Free;
  end;
  FChart.ShowLoading('{"text":"","showSpinner":false}');
  bmp := RenderBmp;
  try
    px := bmp.GetPixel(x, y);
    AssertTrue(Format('the symbol over the mask: %d %d %d', [px.red, px.green, px.blue]),
      (px.blue > 240) and (px.red < 16) and (px.green < 16));
    px := bmp.GetPixel(300, 390);
    AssertTrue(Format('the rest under the mask: %d %d %d', [px.red, px.green, px.blue]),
      (px.red > 200) and (px.green > 200) and (px.blue > 200));
  finally
    bmp.Free;
  end;
  FChart.HideLoading;
end;

{ ==================== the title's box ==================== }

procedure TAdvChartEdgesAxesOracleTest.TestATitlesBoxIsTheAuthors;
var
  tb: TJSONArray;
  bmp: TBGRABitmap;
  lay: TTyTitleLayout;
  px: TBGRAPixel;
  want: TTyChartColor;
  k, x, y: Integer;
begin
  tb := TJSONObject(FRoot).Arrays['titleBox'];
  for k := 0 to tb.Count - 1 do
  begin
    NewChart(400, 300);
    FChart.Option := tb.Objects[k].Objects['option'].AsJSON;
    bmp := RenderBmp;
    try
      lay := FChart.TitleLayoutOf(0);
      y := Round((lay.Frame.Top + lay.Frame.Bottom) / 2);
      { the fill, half way in from the left edge }
      x := Round(lay.Frame.Left + 6);
      px := bmp.GetPixel(x, y);
      if tb.Objects[k].Find('fill').AsString = '#ff0000' then
        AssertTrue(Format('%d: the author''s red fill: %d %d %d', [k, px.red, px.green, px.blue]),
          (px.red > 240) and (px.green < 16) and (px.blue < 16));
      { the pen on the left edge }
      AssertTrue('the stroke parses', TyTryParseChartColor(tb.Objects[k].Strings['stroke'], want));
      px := bmp.GetPixel(Floor(lay.Frame.Left), y);
      AssertTrue(Format('%d: the border %s: %d %d %d', [k, tb.Objects[k].Strings['stroke'], px.red, px.green, px.blue]),
        (Abs(px.red - Integer((want shr 16) and $FF)) < 24) and (Abs(px.green - Integer((want shr 8) and $FF)) < 24)
        and (Abs(px.blue - Integer(want and $FF)) < 24));
    finally
      bmp.Free;
    end;
  end;
end;

initialization
  RegisterTest(TAdvChartEdgesAxesOracleTest);
end.
