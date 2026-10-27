unit test.advchart.authorstyles;
{$mode objfpc}{$H+}
{ THE AUTHOR'S STYLES ON THE FURNITURE, held to upstream [R5-B].

  tools/advchart-oracle/author-styles.js runs the real ECharts 6.1 build and
  records, for every axis of every case -- cartesian, single, polar (angle
  and radius), parallel and radar -- the style each piece was stroked or
  filled with: the line, the ticks, the minor ticks, the split lines, the
  minor split lines, the split areas, the arrows and the name, each with
  where each value came from ('author': the option wrote it somewhere along
  upstream's chain; 'theme': the theme's default).

  THE REPLAY asks the control's own resolution -- the furniture's pens over
  the light skin, TyAxisStrokeOf, the name's colour in the layout spec, the
  radar's elements -- and compares: an author's value with upstream's, a
  theme value with the skin's (the skin stands in for the theme); widths,
  dashes (a word normalised against the width as canvas/dashStyle.ts does),
  phases, caps and opacities always with upstream's, whose defaults are the
  port's.

  Hand-written beside it, on the screen: the pens are what the axes are
  drawn with -- a line's colour and width, ticks, arrows and the name after
  it, a split line's dash and opacity, a band's opacity, and an axis of each
  other kind in its author's colour. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Coord, tyControls.AdvanceChart.Builder,
     tyControls.AdvanceChart.Layout, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Single, tyControls.AdvanceChart.Polar,
     tyControls.AdvanceChart.Parallel, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Lines, tyControls.AdvanceChart.Legend, tyControls.FontUnits,
     tyControls.AdvanceChart;
type
  TAsProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartAuthorStylesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAsProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure NewChart(ACase: TJSONObject);
    function Skin(const AKey: string): TTyStyleSet;
    procedure CheckPen(const APart: string; ARec: TJSONObject;
      const AStroke: TTyAxisStroke; const ASkin: TTyStyleSet);
    procedure CheckSplit(ARec: TJSONObject; const AFurn: TTyAxisFurniture);
    procedure CheckArea(ARec: TJSONObject; const AFurn: TTyAxisFurniture);
    procedure CheckAxis(AAxis: TJSONObject; const AFurn: TTyAxisFurniture;
      const ASpec: TTyAxisLayoutSpec; AAngle: Boolean);
    procedure CheckRadar(AAxis: TJSONObject);
    procedure Finish(const AWhat: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheAxisPensAreUpstreams;
    procedure TestTheRadarPensAreUpstreams;
    procedure TestTheBarBackgroundsAreUpstreams;
    procedure TestTheTreemapCornersAreUpstreams;
    procedure TestTheColorByDataIsUpstreams;
    procedure TestAGradientPaletteEntryIsTheFill;
    procedure TestALegendItemsOwnStyleIsUpstreams;
    procedure TestTheHoveredSelectorIsUpstreams;
    procedure TestTheHoveredRichLabelIsUpstreams;
  end;

  TAdvChartAuthorStylesPaintTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAsProbe;
    FBmp: TBGRABitmap;
    procedure Draw(const AOption: string);
    function CountNear(R, G, B, ATol: Integer): Integer;
    function CountIn(const ARect: TRect; R, G, B, ATol: Integer): Integer;
    { pixels whose channel AStrong is at least 200 and the other two in
      [ALo, AHi]: a pure colour (ALo 0), or the same colour faded (ALo
      above 0) -- the renderer blends in linear light, so half of #0000ff
      over white is not 128 but about 170 }
    function CountTint(const ARect: TRect; AStrong, ALo, AHi: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnAxisLineIsDrawnInItsColourAndWidth;
    procedure TestTicksArrowsAndNameFollowTheLine;
    procedure TestASplitLineDashesAndFades;
    procedure TestABandTakesItsOpacity;
    procedure TestMinorTicksTakeTheLinesColour;
    procedure TestEveryOtherAxisTakesItsColour;
    procedure TestABarBackgroundIsDrawnInItsStyle;
    procedure TestATreemapHasRoundCorners;
  end;

implementation

var GDumpN: Integer = 0;

const
  cW = 600;
  cH = 400;

{ ==================== the probe ==================== }

procedure TAsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TAsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-author-styles.json';
end;

function Txt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function ColourText(C: TTyChartColor): string;
begin
  Result := '$' + IntToHex(C, 8);
end;

{ zrender's normalizeLineDash: a word against the width, a number, a list }
function UpDash(AData: TJSONData; AWidth: Double): TTyDoubleArray;
var i: Integer; s: string;
begin
  Result := nil;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  if not (AWidth > 0) then Exit;
  if AData.JSONType = jtString then
  begin
    s := AData.AsString;
    if s = 'dashed' then
    begin
      SetLength(Result, 2);
      Result[0] := 4 * AWidth;
      Result[1] := 2 * AWidth;
    end
    else if s = 'dotted' then
    begin
      SetLength(Result, 1);
      Result[0] := AWidth;
    end;
    Exit;
  end;
  if AData.JSONType = jtNumber then
  begin
    SetLength(Result, 1);
    Result[0] := AData.AsFloat;
    Exit;
  end;
  if AData is TJSONArray then
  begin
    SetLength(Result, TJSONArray(AData).Count);
    for i := 0 to TJSONArray(AData).Count - 1 do
      Result[i] := TJSONArray(AData).Items[i].AsFloat;
  end;
end;

function DashText(const A: TTyDoubleArray): string;
var i: Integer;
begin
  Result := '[';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + Txt(A[i]);
  end;
  Result := Result + ']';
end;

function SameDash(const A, B: TTyDoubleArray): Boolean;
var i: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for i := 0 to High(A) do
    if A[i] <> B[i] then Exit(False);
end;

function CapOf(const S: string): TTyAxisCap;
begin
  if S = 'round' then Result := acRound
  else if S = 'square' then Result := acSquare
  else Result := acButt;
end;

function SkinWidth(const AStyle: TTyStyleSet): Double;
begin
  if tpBorderWidth in AStyle.Present then Result := AStyle.BorderWidth
  else Result := 1;
  if Result < 0.05 then Result := 0.05;
end;

{ the control's own resolution of one piece over the skin -- what PaintAxis
  and its siblings stroke with }
function Resolve(const APen: TTyAxisPen; const ASkin: TTyStyleSet;
  ACap: TTyAxisCap): TTyAxisStroke;
begin
  Result := TyAxisStrokeOf(APen, tpBorderColor in ASkin.Present,
    TTyChartColor(ASkin.BorderColor), SkinWidth(ASkin), ACap);
end;

{ ==================== the oracle ==================== }

procedure TAdvChartAuthorStylesOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
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
  FReport := '';
end;

procedure TAdvChartAuthorStylesOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAuthorStylesOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartAuthorStylesOracleTest.Finish(const AWhat: string);
begin
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartAuthorStylesOracleTest.NewChart(ACase: TJSONObject);
var opt: TJSONObject;
begin
  FreeAndNil(FChart);
  FChart := TAsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  opt := TJSONObject(ACase.Objects['option'].Clone);
  try
    opt.Add('animation', False);
    FChart.Option := opt.AsJSON;
  finally
    opt.Free;
  end;
  FChart.SetBounds(0, 0, ACase.Integers['W'], ACase.Integers['H']);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartAuthorStylesOracleTest.Skin(const AKey: string): TTyStyleSet;
begin
  Result := FCtl.Model.ResolveStyle(AKey, '', []);
end;

{ one stroked piece: its first style }
procedure TAdvChartAuthorStylesOracleTest.CheckPen(const APart: string;
  ARec: TJSONObject; const AStroke: TTyAxisStroke; const ASkin: TTyStyleSet);
var
  st, src: TJSONObject;
  want: TTyChartColor;
  w: Double;
  dash: TTyDoubleArray;
begin
  st := ARec.Arrays['styles'].Objects[0];
  src := ARec.Objects['src'];
  Inc(FCompared);
  { a width that is not above nought strokes nothing (zrender's hasStroke) }
  if not (st.Floats['lineWidth'] > 0) then
  begin
    if AStroke.Drawn then Bad(APart + ': drawn here, upstream''s width is nought');
    Exit;
  end;
  if not AStroke.Drawn then
  begin
    Bad(APart + ': not drawn here');
    Exit;
  end;
  if src.Strings['stroke'] = 'author' then
  begin
    if not TyTryParseChartColor(st.Strings['stroke'], want) then
      Bad(APart + ': upstream stroke ' + st.Strings['stroke'] + ' unreadable')
    else if AStroke.Colour <> want then
      Bad(Format('%s: stroke %s, upstream %s', [APart, ColourText(AStroke.Colour),
        st.Strings['stroke']]));
  end
  else if AStroke.Colour <> TTyChartColor(ASkin.BorderColor) then
    Bad(Format('%s: stroke %s, the skin''s %s', [APart, ColourText(AStroke.Colour),
      ColourText(TTyChartColor(ASkin.BorderColor))]));
  w := st.Floats['lineWidth'];
  if AStroke.WidthLogical <> w then
    Bad(Format('%s: width %s, upstream %s', [APart, Txt(AStroke.WidthLogical), Txt(w)]));
  dash := UpDash(st.Find('lineDash'), w);
  if not SameDash(AStroke.Dash, dash) then
    Bad(Format('%s: dash %s, upstream %s', [APart, DashText(AStroke.Dash), DashText(dash)]));
  if AStroke.DashOffset <> st.Floats['lineDashOffset'] then
    Bad(Format('%s: dash offset %s, upstream %s', [APart, Txt(AStroke.DashOffset),
      Txt(st.Floats['lineDashOffset'])]));
  if AStroke.Cap <> CapOf(st.Strings['lineCap']) then
    Bad(Format('%s: cap %d, upstream %s', [APart, Ord(AStroke.Cap), st.Strings['lineCap']]));
  if AStroke.Opacity <> st.Floats['opacity'] then
    Bad(Format('%s: opacity %s, upstream %s', [APart, Txt(AStroke.Opacity),
      Txt(st.Floats['opacity'])]));
end;

{ the split lines: a pen, and a colour per style when the author wrote them }
procedure TAdvChartAuthorStylesOracleTest.CheckSplit(ARec: TJSONObject;
  const AFurn: TTyAxisFurniture);
var
  styles: TJSONArray;
  k: TTyAxisStroke;
  i: Integer;
  want: TTyChartColor;
  one: TJSONObject;
begin
  styles := ARec.Arrays['styles'];
  k := Resolve(AFurn.SplitPen, Skin('TyAdvChartSplitLine'), acButt);
  if ARec.Objects['src'].Strings['stroke'] = 'author' then
  begin
    Inc(FCompared);
    if Length(AFurn.SplitLineInks) <> styles.Count then
      Bad(Format('split: %d inks, upstream %d styles', [Length(AFurn.SplitLineInks), styles.Count]))
    else
      for i := 0 to styles.Count - 1 do
        if TyTryParseChartColor(styles.Objects[i].Strings['stroke'], want)
          and (AFurn.SplitLineInks[i].Colour <> want) then
          Bad(Format('split ink %d: %s, upstream %s', [i,
            ColourText(AFurn.SplitLineInks[i].Colour), styles.Objects[i].Strings['stroke']]));
    { the pen without its colour }
    one := TJSONObject(ARec.Clone);
    try
      TJSONObject(one.Arrays['styles'].Objects[0]).Strings['stroke'] :=
        styles.Objects[0].Strings['stroke'];
      one.Objects['src'].Strings['stroke'] := 'author';
      if Length(AFurn.SplitLineInks) > 0 then k.Colour := AFurn.SplitLineInks[0].Colour;
      k.Drawn := k.Drawn or (k.WidthLogical > 0);
      CheckPen('split', one, k, Skin('TyAdvChartSplitLine'));
    finally
      one.Free;
    end;
  end
  else
    CheckPen('split', ARec, k, Skin('TyAdvChartSplitLine'));
end;

procedure TAdvChartAuthorStylesOracleTest.CheckArea(ARec: TJSONObject;
  const AFurn: TTyAxisFurniture);
var
  styles: TJSONArray;
  i: Integer;
  want: TTyChartColor;
  op: Double;
begin
  styles := ARec.Arrays['styles'];
  Inc(FCompared);
  if ARec.Objects['src'].Strings['fill'] = 'author' then
  begin
    if Length(AFurn.SplitAreaInks) <> styles.Count then
      Bad(Format('area: %d inks, upstream %d', [Length(AFurn.SplitAreaInks), styles.Count]))
    else
      for i := 0 to styles.Count - 1 do
        if TyTryParseChartColor(styles.Objects[i].Strings['fill'], want)
          and (AFurn.SplitAreaInks[i].Colour <> want) then
          Bad(Format('area ink %d: %s, upstream %s', [i,
            ColourText(AFurn.SplitAreaInks[i].Colour), styles.Objects[i].Strings['fill']]));
  end
  else if Length(AFurn.SplitAreaInks) > 0 then
    Bad('area: inks here, the theme''s upstream');
  op := AFurn.AreaOpacity;
  if IsNan(op) then op := 1;
  if op <> styles.Objects[0].Floats['opacity'] then
    Bad(Format('area: opacity %s, upstream %s', [Txt(op),
      Txt(styles.Objects[0].Floats['opacity'])]));
end;

procedure TAdvChartAuthorStylesOracleTest.CheckAxis(AAxis: TJSONObject;
  const AFurn: TTyAxisFurniture; const ASpec: TTyAxisLayoutSpec; AAngle: Boolean);
var
  parts, rec: TJSONObject;
  lineCap: TTyAxisCap;
  want: TTyChartColor;
  k: TTyAxisStroke;
begin
  parts := AAxis.Objects['parts'];
  if AAngle then lineCap := acButt else lineCap := acRound;
  if parts.Find('line') <> nil then
    CheckPen('line', parts.Objects['line'],
      Resolve(AFurn.LinePen, Skin('TyAdvChartAxisLine'), lineCap), Skin('TyAdvChartAxisLine'));
  if parts.Find('tick') <> nil then
    CheckPen('tick', parts.Objects['tick'],
      Resolve(AFurn.TickPen, Skin('TyAdvChartAxisTick'), acButt), Skin('TyAdvChartAxisTick'));
  if parts.Find('minorTick') <> nil then
    CheckPen('minorTick', parts.Objects['minorTick'],
      Resolve(AFurn.MinorTickPen, Skin('TyAdvChartMinorTick'), acButt), Skin('TyAdvChartMinorTick'));
  if parts.Find('minorSplit') <> nil then
    CheckPen('minorSplit', parts.Objects['minorSplit'],
      Resolve(AFurn.MinorSplitPen, Skin('TyAdvChartMinorSplitLine'), acButt),
      Skin('TyAdvChartMinorSplitLine'));
  if parts.Find('split') <> nil then CheckSplit(parts.Objects['split'], AFurn);
  if parts.Find('area') <> nil then CheckArea(parts.Objects['area'], AFurn);
  if parts.Find('arrow') <> nil then
  begin
    rec := parts.Objects['arrow'];
    Inc(FCompared);
    k := Resolve(AFurn.LinePen, Skin('TyAdvChartAxisLine'), lineCap);
    if rec.Objects['src'].Strings['fill'] = 'author' then
    begin
      if TyTryParseChartColor(rec.Arrays['styles'].Objects[0].Strings['fill'], want)
        and (k.Colour <> want) then
        Bad(Format('arrow: %s, upstream %s', [ColourText(k.Colour),
          rec.Arrays['styles'].Objects[0].Strings['fill']]));
    end
    else if k.Colour <> TTyChartColor(Skin('TyAdvChartAxisLine').BorderColor) then
      Bad('arrow: not the skin''s line colour');
  end;
  if parts.Find('name') <> nil then
  begin
    rec := parts.Objects['name'];
    Inc(FCompared);
    if rec.Objects['src'].Strings['fill'] = 'author' then
    begin
      if not ASpec.HasNameColour then
        Bad('name: the skin''s colour, upstream ' + rec.Arrays['styles'].Objects[0].Strings['fill'])
      else if TyTryParseChartColor(rec.Arrays['styles'].Objects[0].Strings['fill'], want)
        and (TTyChartColor(ASpec.NameColour) <> want) then
        Bad(Format('name: %s, upstream %s', [ColourText(TTyChartColor(ASpec.NameColour)),
          rec.Arrays['styles'].Objects[0].Strings['fill']]));
    end
    else if ASpec.HasNameColour then
      Bad('name: a colour of its own, the theme''s upstream');
  end;
end;

procedure TAdvChartAuthorStylesOracleTest.TestTheAxisPensAreUpstreams;
var
  cases, axes: TJSONArray;
  c, a: TJSONObject;
  i, j, k, idx: Integer;
  kind, mt: string;
  grid: TTyGridBuild;
  ax: TTyAxis;
  pol: TTyPolar;
  par: TTyParallel;
  sgl: TTySingle;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    NewChart(c);
    axes := c.Arrays['axes'];
    for j := 0 to axes.Count - 1 do
    begin
      a := axes.Objects[j];
      kind := a.Strings['kind'];
      mt := a.Strings['mainType'];
      idx := a.Integers['index'];
      FWhere := c.Strings['id'] + ' ' + mt + IntToStr(idx);
      if kind = 'cartesian' then
      begin
        grid := FChart.Build.Grid(0);
        ax := nil;
        if mt = 'xAxis' then
        begin
          for k := 0 to grid.XAxisCount - 1 do
            if grid.XAxis(k).ComponentIndex = idx then ax := grid.XAxis(k);
        end
        else
          for k := 0 to grid.YAxisCount - 1 do
            if grid.YAxis(k).ComponentIndex = idx then ax := grid.YAxis(k);
        if ax = nil then
        begin
          Bad('no such axis');
          Continue;
        end;
        CheckAxis(a, grid.FurnitureFor(ax), grid.SpecFor(ax)^, False);
      end
      else if kind = 'single' then
      begin
        sgl := FChart.SingleLayout(idx);
        if sgl = nil then begin Bad('no single axis'); Continue; end;
        CheckAxis(a, sgl.View.Furn, sgl.View.Spec, False);
      end
      else if (kind = 'angle') or (kind = 'radius') then
      begin
        pol := FChart.PolarLayout(0);
        if pol = nil then begin Bad('no polar'); Continue; end;
        if kind = 'angle' then CheckAxis(a, pol.AngleView.Furn, pol.AngleView.Spec, True)
        else CheckAxis(a, pol.RadiusView.Furn, pol.RadiusView.Spec, False);
      end
      else if kind = 'parallel' then
      begin
        par := FChart.ParallelLayout(0);
        if (par = nil) or (idx > High(par.Views)) then begin Bad('no parallel axis'); Continue; end;
        CheckAxis(a, par.Views[idx].Furn, par.Views[idx].Spec, False);
      end;
    end;
  end;
  Finish('the axis pens');
end;

{ the radar's furniture is in the paint list: silent, z 0 -- the bands and
  rings at z2 0, the spokes at 1, the ticks at 2 }
procedure TAdvChartAuthorStylesOracleTest.CheckRadar(AAxis: TJSONObject);
var
  parts: TJSONObject;
  l: TTyPaintList;
  i, n: Integer;
  pe: PTyChartElement;
  sp, st: TJSONObject;
  want: TTyChartColor;
  dash: TTyDoubleArray;

  procedure Pen(const APart: string; AZ2: Integer);
  var j: Integer; e: PTyChartElement; seen: Boolean;
  begin
    if parts.Find(APart) = nil then Exit;
    st := parts.Objects[APart].Arrays['styles'].Objects[0];
    seen := False;
    for j := 0 to l.Count - 1 do
    begin
      e := l.Ref(j);
      if not e^.Silent or (e^.Z <> 0) or (e^.Z2 <> AZ2) or e^.Style.HasFill
        or (e^.Caption.Text <> '') then Continue;
      seen := True;
      Inc(FCompared);
      if (parts.Objects[APart].Objects['src'].Strings['stroke'] = 'author')
        and TyTryParseChartColor(st.Strings['stroke'], want) and (e^.Style.StrokeColor <> want)
        and not ((APart = 'split') and (parts.Objects[APart].Arrays['styles'].Count > 1)) then
        Bad(Format('%s: stroke %s, upstream %s', [APart, ColourText(e^.Style.StrokeColor),
          st.Strings['stroke']]));
      if e^.Style.StrokeWidthLogical <> st.Floats['lineWidth'] then
        Bad(Format('%s: width %s, upstream %s', [APart, Txt(e^.Style.StrokeWidthLogical),
          Txt(st.Floats['lineWidth'])]));
      dash := UpDash(st.Find('lineDash'), st.Floats['lineWidth']);
      if not SameDash(e^.Style.DashLogical, dash) then
        Bad(Format('%s: dash %s, upstream %s', [APart, DashText(e^.Style.DashLogical),
          DashText(dash)]));
      if e^.Style.DashOffsetLogical <> st.Floats['lineDashOffset'] then
        Bad(APart + ': dash offset');
      if e^.Style.Alpha <> st.Floats['opacity'] then
        Bad(Format('%s: opacity %s, upstream %s', [APart, Txt(e^.Style.Alpha),
          Txt(st.Floats['opacity'])]));
      Break;
    end;
    if not seen then Bad(APart + ': no element');
  end;

begin
  parts := AAxis.Objects['parts'];
  l := FChart.List;
  Pen('line', 1);
  Pen('tick', 2);
  Pen('split', 0);
  if parts.Find('area') <> nil then
  begin
    sp := parts.Objects['area'].Arrays['styles'].Objects[0];
    n := 0;
    for i := 0 to l.Count - 1 do
    begin
      pe := l.Ref(i);
      if not pe^.Silent or (pe^.Z <> 0) or (pe^.Z2 <> 0) or not pe^.Style.HasFill then Continue;
      Inc(n);
      Inc(FCompared);
      if pe^.Style.Alpha <> sp.Floats['opacity'] then
        Bad(Format('area: opacity %s, upstream %s', [Txt(pe^.Style.Alpha),
          Txt(sp.Floats['opacity'])]));
    end;
    if n = 0 then Bad('area: no element');
  end;
end;

procedure TAdvChartAuthorStylesOracleTest.TestTheRadarPensAreUpstreams;
var
  cases, axes: TJSONArray;
  c: TJSONObject;
  i, j: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    axes := c.Arrays['axes'];
    for j := 0 to axes.Count - 1 do
      if axes.Objects[j].Strings['kind'] = 'radar' then
      begin
        NewChart(c);
        FWhere := c.Strings['id'];
        CheckRadar(axes.Objects[j]);
      end;
  end;
  Finish('the radar pens');
end;

{ the bar backgrounds of series 0, in their order: silent, faded in where a
  universal transition morphs (UtTag 2, UtRow -2 - the row) }
procedure TAdvChartAuthorStylesOracleTest.TestTheBarBackgroundsAreUpstreams;
var
  cases, items: TJSONArray;
  c, it, st: TJSONObject;
  i, j, k, n: Integer;
  l: TTyPaintList;
  pe: PTyChartElement;
  found: Boolean;
  want: TTyChartColor;
  fillD: TJSONData;
  w: Double;
  dash: TTyDoubleArray;
  radii: TTyCornerRadii;
  rs: array of Double;
  skinBg: TTyChartColor;
begin
  skinBg := TTyChartColor(Skin('TyAdvChartBarBackground').Background.Color);
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    if c.Strings['group'] <> 'barbg' then Continue;
    NewChart(c);
    l := FChart.List;
    items := c.Arrays['series'].Objects[0].Arrays['items'];
    for j := 0 to items.Count - 1 do
    begin
      it := items.Objects[j];
      FWhere := Format('%s bg %d', [c.Strings['id'], j]);
      found := False;
      pe := nil;
      for k := 0 to l.Count - 1 do
      begin
        pe := l.Ref(k);
        if (pe^.Anim.UtTag = 2) and (pe^.Anim.Series = 0) and (pe^.Anim.UtRow = -2 - j)
          and pe^.Silent then
        begin
          found := True;
          Break;
        end;
      end;
      Inc(FCompared);
      if not found then
      begin
        Bad('no background element');
        Continue;
      end;
      st := it.Objects['style'];
      { the fill: the theme's strip where upstream's default is, else the
        author's colour, gradient, or none }
      fillD := st.Find('fill');
      Inc(FCompared);
      if fillD is TJSONObject then
      begin
        if (pe^.Style.FillGradient.Kind <> cgkLinear)
          or (Length(pe^.Style.FillGradient.Stops) <> TJSONObject(fillD).Arrays['colorStops'].Count) then
          Bad('fill: not the gradient')
        else
          for n := 0 to High(pe^.Style.FillGradient.Stops) do
            if TyTryParseChartColor(TJSONObject(fillD).Arrays['colorStops'].Objects[n].Strings['color'], want)
              and (pe^.Style.FillGradient.Stops[n].Color <> want) then
              Bad(Format('fill stop %d: %s', [n, ColourText(pe^.Style.FillGradient.Stops[n].Color)]));
      end
      else if (fillD <> nil) and (fillD.JSONType = jtString) then
      begin
        if fillD.AsString = 'none' then
        begin
          if pe^.Style.HasFill then Bad('fill: drawn, none upstream');
        end
        else if fillD.AsString = 'rgba(180, 180, 180, 0.2)' then
        begin
          if (not pe^.Style.HasFill) or (pe^.Style.FillColor <> skinBg) then
            Bad('fill: not the skin''s strip ' + ColourText(pe^.Style.FillColor));
        end
        else if TyTryParseChartColor(fillD.AsString, want)
          and ((not pe^.Style.HasFill) or (pe^.Style.FillColor <> want)) then
          Bad(Format('fill %s, upstream %s', [ColourText(pe^.Style.FillColor), fillD.AsString]));
      end;
      { the pen: drawn where a colour and a width above nought are }
      w := st.Floats['lineWidth'];
      Inc(FCompared);
      if (st.Find('stroke').JSONType = jtString) and (w > 0) then
      begin
        if not TyTryParseChartColor(st.Strings['stroke'], want) then Bad('stroke unreadable')
        else if pe^.Style.StrokeColor <> want then
          Bad(Format('stroke %s, upstream %s', [ColourText(pe^.Style.StrokeColor), st.Strings['stroke']]));
        if pe^.Style.StrokeWidthLogical <> w then
          Bad(Format('width %s, upstream %s', [Txt(pe^.Style.StrokeWidthLogical), Txt(w)]));
        dash := UpDash(st.Find('lineDash'), w);
        if not SameDash(pe^.Style.DashLogical, dash) then
          Bad(Format('dash %s, upstream %s', [DashText(pe^.Style.DashLogical), DashText(dash)]));
        if pe^.Style.DashOffsetLogical <> st.Floats['lineDashOffset'] then
          Bad(Format('dash offset %s, upstream %s', [Txt(pe^.Style.DashOffsetLogical),
            Txt(st.Floats['lineDashOffset'])]));
      end
      else if pe^.Style.StrokeWidthLogical > 0 then
        Bad('a pen here, none upstream');
      Inc(FCompared);
      if pe^.Style.Alpha <> st.Floats['opacity'] then
        Bad(Format('opacity %s, upstream %s', [Txt(pe^.Style.Alpha), Txt(st.Floats['opacity'])]));
      { the corners of a rect }
      if (it.Strings['type'] = 'rect') and (it.Find('r') is TJSONArray) then
      begin
        SetLength(rs, it.Arrays['r'].Count);
        for n := 0 to High(rs) do rs[n] := it.Arrays['r'].Floats[n];
        radii := TyCornerRadii(rs);
        Inc(FCompared);
        if pe^.Shape.Kind <> cskRoundRect then Bad('no corners')
        else
          for n := 0 to 3 do
            if pe^.Shape.Radii[n] <> radii[n] then
              Bad(Format('corner %d: %s, upstream %s', [n, Txt(pe^.Shape.Radii[n]), Txt(radii[n])]));
      end;
    end;
  end;
  Finish('the bar backgrounds');
end;

{ every treemap rect of upstream's with a rounded corner: the port's rect at
  the same place, with the same corners }
procedure TAdvChartAuthorStylesOracleTest.TestTheTreemapCornersAreUpstreams;
var
  cases, rects: TJSONArray;
  c, r: TJSONObject;
  i, j, k, n: Integer;
  l: TTyPaintList;
  pe: PTyChartElement;
  x, y, w, h: Double;
  found, ok: Boolean;
  rs: array of Double;
  want: TTyChartShape;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    if c.Strings['group'] <> 'treemap' then Continue;
    NewChart(c);
    l := FChart.List;
    rects := c.Arrays['series'].Objects[0].Arrays['rects'];
    for j := 0 to rects.Count - 1 do
    begin
      r := rects.Objects[j];
      FWhere := Format('%s rect %d', [c.Strings['id'], j]);
      x := r.Floats['x'];
      y := r.Floats['y'];
      w := r.Floats['width'];
      h := r.Floats['height'];
      if r.Find('r') is TJSONArray then
      begin
        SetLength(rs, r.Arrays['r'].Count);
        for n := 0 to High(rs) do rs[n] := r.Arrays['r'].Floats[n];
      end
      else
      begin
        SetLength(rs, 1);
        rs[0] := r.Floats['r'];
      end;
      want := TyShapeRoundRect(TyRectF(x, y, x + w, y + h), rs);
      { a parent's background and its only child's rects can share a place:
        one of the port's rects there has to have upstream's corners }
      found := False;
      Inc(FCompared);
      for k := 0 to l.Count - 1 do
      begin
        pe := l.Ref(k);
        if pe^.Anim.Role <> carTmRect then Continue;
        if (Abs(pe^.Shape.Bounds.Left - x) > 1e-9) or (Abs(pe^.Shape.Bounds.Top - y) > 1e-9)
          or (Abs(pe^.Shape.Bounds.Right - (x + w)) > 1e-9)
          or (Abs(pe^.Shape.Bounds.Bottom - (y + h)) > 1e-9) then Continue;
        if TyHasCorner(want.Radii) then
        begin
          if pe^.Shape.Kind <> cskRoundRect then Continue;
          ok := True;
          for n := 0 to 3 do
            if Abs(pe^.Shape.Radii[n] - want.Radii[n]) > 1e-9 then ok := False;
          if ok then found := True;
        end
        else if not ((pe^.Shape.Kind = cskRoundRect) and TyHasCorner(pe^.Shape.Radii)) then
          found := True;
      end;
      if not found then
        Bad(Format('no rect at (%s, %s, %s, %s) with corners [%s, %s, %s, %s]', [Txt(x),
          Txt(y), Txt(w), Txt(h), Txt(want.Radii[0]), Txt(want.Radii[1]), Txt(want.Radii[2]),
          Txt(want.Radii[3])]));
    end;
  end;
  Finish('the treemap corners');
end;

{ colorBy 'data': each row's stroke as the solve gave it -- a lines' row
  ink, a parallel's row -- against upstream's visual, the palette written
  in the option }
procedure TAdvChartAuthorStylesOracleTest.TestTheColorByDataIsUpstreams;
var
  cases, cols: TJSONArray;
  c, s: TJSONObject;
  i, k, r, raw: Integer;
  want, got: TTyChartColor;
  lsol: TTyLinesSolved;
  psol: TTyParallelSolved;
  typ: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    if c.Strings['group'] <> 'colorby' then Continue;
    NewChart(c);
    s := c.Arrays['series'].Objects[0];
    typ := s.Strings['type'];
    cols := s.Arrays['colors'];
    for k := 0 to cols.Count - 1 do
    begin
      raw := cols.Objects[k].Integers['raw'];
      FWhere := Format('%s row %d', [c.Strings['id'], raw]);
      Inc(FCompared);
      if not TyTryParseChartColor(cols.Objects[k].Strings['color'], want) then
      begin
        Bad('upstream colour unreadable');
        Continue;
      end;
      got := 0;
      if typ = 'lines' then
      begin
        lsol := FChart.LinesSolvedOf(s.Integers['seriesIndex']);
        if raw > High(lsol.Inks) then begin Bad('no ink'); Continue; end;
        got := lsol.Inks[raw].Stroke;
      end
      else if typ = 'parallel' then
      begin
        psol := FChart.ParallelSolvedOf(s.Integers['seriesIndex']);
        got := 0;
        for r := 0 to High(psol.Rows) do
          if psol.Rows[r].Raw = raw then got := psol.Rows[r].Stroke;
      end;
      if got <> want then
        Bad(Format('stroke %s, upstream %s', [ColourText(got), cols.Objects[k].Strings['color']]));
    end;
  end;
  Finish('colorBy data');
end;

{ upstream's fill against an element's: a string its solid and no
  gradient, an object the gradient stop by stop }
function SameFill(AUp: TJSONData; const AGrad: TTyChartGradient; ASolid: TTyChartColor;
  out AWhy: string): Boolean;
var
  k: Integer;
  want: TTyChartColor;
  stops: TJSONArray;
begin
  AWhy := '';
  if AUp is TJSONObject then
  begin
    stops := TJSONObject(AUp).Arrays['colorStops'];
    if (AGrad.Kind <> cgkLinear) or (Length(AGrad.Stops) <> stops.Count) then
    begin
      AWhy := 'not the gradient';
      Exit(False);
    end;
    for k := 0 to stops.Count - 1 do
      if not TyTryParseChartColor(stops.Objects[k].Strings['color'], want)
        or (AGrad.Stops[k].Color <> want) or (AGrad.Stops[k].Offset <> stops.Objects[k].Floats['offset']) then
      begin
        AWhy := Format('stop %d', [k]);
        Exit(False);
      end;
    Exit(True);
  end;
  if (AUp = nil) or (AUp.JSONType <> jtString) or not TyTryParseChartColor(AUp.AsString, want) then
  begin
    AWhy := 'unreadable upstream';
    Exit(False);
  end;
  if AGrad.Kind <> cgkNone then
  begin
    AWhy := 'a gradient here, ' + AUp.AsString + ' upstream';
    Exit(False);
  end;
  Result := ASolid = want;
  if not Result then AWhy := ColourText(ASolid) + ', upstream ' + AUp.AsString;
end;

{ a palette entry that is a gradient: a bar's rects, a pie's sectors by
  datum, a line's polyline and area }
procedure TAdvChartAuthorStylesOracleTest.TestAGradientPaletteEntryIsTheFill;
var
  cases, ser, fills: TJSONArray;
  c, s: TJSONObject;
  i, j, k, q, raw, si: Integer;
  l: TTyPaintList;
  pe: PTyChartElement;
  why: string;
  found, strokeOk, areaOk: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    if c.Strings['group'] <> 'palgrad' then Continue;
    NewChart(c);
    l := FChart.List;
    ser := c.Arrays['series'];
    for j := 0 to ser.Count - 1 do
    begin
      s := ser.Objects[j];
      si := s.Integers['seriesIndex'];
      if s.Strings['type'] = 'line' then
      begin
        FWhere := Format('%s line %d', [c.Strings['id'], si]);
        strokeOk := False;
        areaOk := False;
        for q := 0 to l.Count - 1 do
        begin
          pe := l.Ref(q);
          if (pe^.Datum.SeriesIndex <> si) then Continue;
          if (pe^.Style.StrokeWidthLogical > 0) and not pe^.Style.HasFill
            and SameFill(s.Find('stroke'), pe^.Style.StrokeGradient, pe^.Style.StrokeColor, why) then
            strokeOk := True;
          if pe^.Style.HasFill and SameFill(s.Find('area'), pe^.Style.FillGradient,
            pe^.Style.FillColor, why) then areaOk := True;
        end;
        Inc(FCompared, 2);
        if not strokeOk then Bad('no line stroked in upstream''s colour');
        if not areaOk then Bad('no area filled in upstream''s colour');
        Continue;
      end;
      fills := s.Arrays['fills'];
      for k := 0 to fills.Count - 1 do
      begin
        raw := fills.Objects[k].Integers['raw'];
        FWhere := Format('%s series %d row %d', [c.Strings['id'], si, raw]);
        found := False;
        Inc(FCompared);
        for q := 0 to l.Count - 1 do
        begin
          pe := l.Ref(q);
          if (pe^.Datum.Kind <> ctkSeries) or (pe^.Datum.SeriesIndex <> si)
            or (pe^.Datum.RawDataIndex <> raw) or not pe^.Style.HasFill then Continue;
          found := True;
          if not SameFill(fills.Objects[k].Find('fill'), pe^.Style.FillGradient,
            pe^.Style.FillColor, why) then Bad('fill: ' + why);
          Break;
        end;
        if not found then Bad('no element');
      end;
    end;
  end;
  Finish('gradient palette entries');
end;

{ the colour upstream drew, when the case's option wrote it (else the
  theme's, which is the skin's here and not compared) }
function Written(ACase: TJSONObject; const AColour: string; out AWant: TTyChartColor): Boolean;
begin
  Result := (AColour <> '') and (Pos('"' + LowerCase(AColour) + '"',
    LowerCase(ACase.Objects['option'].AsJSON)) > 0)
    and TyTryParseChartColor(AColour, AWant);
end;

{ legend.data[i]'s own textStyle, itemStyle, lineStyle and inactive colours:
  each item's elements -- its hit rect (the legend's datum) and what follows
  it up to the next -- against upstream's words and icon paths }
procedure TAdvChartAuthorStylesOracleTest.TestALegendItemsOwnStyleIsUpstreams;
var
  cases, items, icons: TJSONArray;
  c, it, tx, ic: TJSONObject;
  i, j, k, q, idx, first, last: Integer;
  l: TTyPaintList;
  pe: PTyChartElement;
  lay: TTyLegendLayout;
  want: TTyChartColor;
  found: Boolean;
  w: Double;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    if (c.Strings['group'] <> 'legend') or (c.Strings['id'] = 'lg-selector-emph') then Continue;
    NewChart(c);
    l := FChart.List;
    lay := FChart.LegendLayout(0);
    items := c.Arrays['series'].Objects[0].Arrays['items'];
    for j := 0 to items.Count - 1 do
    begin
      it := items.Objects[j];
      FWhere := Format('%s %s', [c.Strings['id'], it.Strings['name']]);
      idx := -1;
      for k := 0 to High(lay.Items) do
        if lay.Items[k].Name = it.Strings['name'] then idx := k;
      Inc(FCompared);
      if idx < 0 then
      begin
        Bad('no such item');
        Continue;
      end;
      { the item's run of elements }
      first := -1;
      last := l.Count - 1;
      for k := 0 to l.Count - 1 do
      begin
        pe := l.Ref(k);
        if pe^.Datum.Kind <> ctkLegend then Continue;
        if first >= 0 then
        begin
          last := k - 1;
          Break;
        end;
        if pe^.Datum.DataIndex = idx then first := k + 1;
      end;
      if first < 0 then
      begin
        Bad('no hit rect');
        Continue;
      end;
      { the words }
      tx := it.Objects['text'];
      found := False;
      for k := first to last do
      begin
        pe := l.Ref(k);
        if pe^.Caption.Text = '' then Continue;
        found := True;
        if Written(c, tx.Strings['fill'], want) and (pe^.Caption.Colour <> want) then
          Bad(Format('words %s, upstream %s', [ColourText(pe^.Caption.Colour), tx.Strings['fill']]));
        if TyFontPxOf(pe^.Caption.FontSizeLogical) <> tx.Floats['fontSize'] then
          if Pos('"fontSize"', c.Objects['option'].AsJSON) > 0 then
            Bad(Format('words %s px, upstream %s', [Txt(TyFontPxOf(pe^.Caption.FontSizeLogical)),
              Txt(tx.Floats['fontSize'])]));
        if (tx.Strings['fontWeight'] = 'bold') <> (pe^.Caption.FontWeight >= 700) then
          Bad(Format('words weight %d, upstream %s', [pe^.Caption.FontWeight, tx.Strings['fontWeight']]));
        Break;
      end;
      if not found then Bad('no words');
      { the icon paths: each upstream path with a colour the option wrote is
        an element of the item's in that colour, its width and opacity }
      icons := it.Arrays['icons'];
      for q := 0 to icons.Count - 1 do
      begin
        ic := icons.Objects[q];
        if (ic.Find('stroke').JSONType = jtString) and (ic.Floats['lineWidth'] > 0)
          and Written(c, ic.Strings['stroke'], want) then
        begin
          Inc(FCompared);
          found := False;
          w := ic.Floats['lineWidth'];
          for k := first to last do
          begin
            pe := l.Ref(k);
            if (pe^.Caption.Text = '') and (pe^.Style.StrokeColor = want)
              and (pe^.Style.StrokeWidthLogical = w) then found := True;
          end;
          if not found then
            Bad(Format('no pen %s at %s', [ic.Strings['stroke'], Txt(w)]));
        end;
        if (ic.Find('fill').JSONType = jtString) and Written(c, ic.Strings['fill'], want) then
        begin
          Inc(FCompared);
          found := False;
          for k := first to last do
          begin
            pe := l.Ref(k);
            if (pe^.Caption.Text = '') and pe^.Style.HasFill and (pe^.Style.FillColor = want) then
            begin
              found := True;
              if Abs(pe^.Style.Alpha - ic.Floats['opacity']) > 1e-12 then
                Bad(Format('fill %s at opacity %s, upstream %s', [ic.Strings['fill'],
                  Txt(pe^.Style.Alpha), Txt(ic.Floats['opacity'])]));
            end;
          end;
          if not found then Bad('no fill ' + ic.Strings['fill']);
        end;
        { an unselected icon with no pen upstream has none here }
        if (ic.Floats['lineWidth'] = 0) and (ic.Find('fill').JSONType = jtString)
          and Written(c, ic.Strings['fill'], want) then
          for k := first to last do
          begin
            pe := l.Ref(k);
            if (pe^.Caption.Text = '') and pe^.Style.HasFill and (pe^.Style.FillColor = want)
              and (pe^.Style.StrokeWidthLogical > 0) then
              Bad('a pen here, none upstream');
          end;
      end;
    end;
  end;
  Finish('the legend items');
end;

{ the selector button's emphasis label: its pieces as laid out hovered --
  the box's fill and pen, the words' fill, weight and size }
procedure TAdvChartAuthorStylesOracleTest.TestTheHoveredSelectorIsUpstreams;
var
  cases: TJSONArray;
  c, st: TJSONObject;
  i, k: Integer;
  lay: TTyLegendLayout;
  want: TTyChartColor;
  sawRect, sawText: Boolean;
  pc: TTyRtPiece;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    if c.Strings['id'] <> 'lg-selector-emph' then Continue;
    NewChart(c);
    lay := FChart.LegendLayout(0);
    st := c.Arrays['series'].Objects[0].Arrays['selectors'].Objects[0];
    FWhere := c.Strings['id'];
    Inc(FCompared);
    if Length(lay.Selector) = 0 then
    begin
      Bad('no selector');
      Continue;
    end;
    sawRect := False;
    sawText := False;
    for k := 0 to High(lay.Selector[0].EmphPieces) do
    begin
      pc := lay.Selector[0].EmphPieces[k];
        if pc.Kind = rpkRect then
        begin
          sawRect := True;
          if TyTryParseChartColor(st.Strings['backgroundColor'], want)
            and not (pc.HasFill and (pc.Fill = want)) then
            Bad(Format('box fill %s, upstream %s', [ColourText(pc.Fill), st.Strings['backgroundColor']]));
          if TyTryParseChartColor(st.Strings['borderColor'], want)
            and not (pc.HasStroke and (pc.Stroke = want)) then
            Bad(Format('box pen %s, upstream %s', [ColourText(pc.Stroke), st.Strings['borderColor']]));
        end
        else
        begin
          sawText := True;
          if TyTryParseChartColor(st.Strings['fill'], want) and (pc.Fill <> want) then
            Bad(Format('words %s, upstream %s', [ColourText(pc.Fill), st.Strings['fill']]));
          if pc.FontSizePx <> st.Floats['fontSize'] then
            Bad(Format('words %s px, upstream %s', [Txt(pc.FontSizePx), Txt(st.Floats['fontSize'])]));
          if (st.Strings['fontWeight'] = 'bold') <> (pc.FontWeight >= 700) then
            Bad(Format('words weight %d, upstream %s', [pc.FontWeight, st.Strings['fontWeight']]));
        end;
    end;
    if not (sawRect and sawText) then Bad('not a box and its words');
  end;
  Finish('the hovered selector');
end;

{ emphasis.label.rich: each label's pieces at rest and hovered -- the text
  piece of each `{name|text}` token in upstream's fill, size and weight }
procedure TAdvChartAuthorStylesOracleTest.TestTheHoveredRichLabelIsUpstreams;
var
  cases, labels: TJSONArray;
  c, lb: TJSONObject;
  i, j, k, seen: Integer;
  l: TTyPaintList;
  pe: PTyChartElement;
  names, texts: array of string;
  tok, rest: string;
  p, q: Integer;

  procedure Check(const APieces: TTyRtPieceArray; AStates: TJSONObject; const AWhich: string);
  var n, m: Integer; st: TJSONObject; want: TTyChartColor; hit: Boolean;
  begin
    for n := 0 to High(names) do
    begin
      if AStates.Find(names[n]) = nil then Continue;
      st := AStates.Objects[names[n]];
      hit := False;
      Inc(FCompared);
      for m := 0 to High(APieces) do
      begin
        if (APieces[m].Kind <> rpkText) or (APieces[m].Text <> texts[n]) then Continue;
        hit := True;
        if TyTryParseChartColor(st.Strings['fill'], want) and (APieces[m].Fill <> want) then
          Bad(Format('%s %s: fill %s, upstream %s', [AWhich, names[n],
            ColourText(APieces[m].Fill), st.Strings['fill']]));
        if APieces[m].FontSizePx <> st.Floats['fontSize'] then
          Bad(Format('%s %s: %s px, upstream %s', [AWhich, names[n],
            Txt(APieces[m].FontSizePx), Txt(st.Floats['fontSize'])]));
        if (st.Strings['fontWeight'] = 'bold') <> (APieces[m].FontWeight >= 700) then
          Bad(Format('%s %s: weight %d, upstream %s', [AWhich, names[n],
            APieces[m].FontWeight, st.Strings['fontWeight']]));
      end;
      if not hit then Bad(Format('%s %s: no piece', [AWhich, names[n]]));
    end;
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    if c.Strings['group'] <> 'emphrich' then Continue;
    NewChart(c);
    l := FChart.List;
    labels := c.Arrays['series'].Objects[0].Arrays['labels'];
    seen := 0;
    for j := 0 to labels.Count - 1 do
    begin
      lb := labels.Objects[j];
      FWhere := Format('%s label %d', [c.Strings['id'], j]);
      { the tokens: {name|text} }
      names := nil;
      texts := nil;
      rest := lb.Strings['text'];
      while True do
      begin
        p := Pos('{', rest);
        q := Pos('}', rest);
        if (p = 0) or (q < p) then Break;
        tok := Copy(rest, p + 1, q - p - 1);
        if Pos('|', tok) > 0 then
        begin
          SetLength(names, Length(names) + 1);
          SetLength(texts, Length(texts) + 1);
          names[High(names)] := Copy(tok, 1, Pos('|', tok) - 1);
          texts[High(texts)] := Copy(tok, Pos('|', tok) + 1, MaxInt);
        end;
        rest := Copy(rest, q + 1, MaxInt);
      end;
      { the j-th label caption with a block }
      k := 0;
      pe := nil;
      while k < l.Count do
      begin
        if Length(l.Ref(k)^.Caption.RtEmph) > 0 then
        begin
          if seen = j then
          begin
            pe := l.Ref(k);
            Break;
          end;
          Inc(seen);
        end;
        Inc(k);
      end;
      seen := 0;
      Inc(FCompared);
      if pe = nil then
      begin
        Bad('no label block');
        Continue;
      end;
      Check(pe^.Caption.RtPieces, lb.Objects['normal'], 'at rest');
      Check(pe^.Caption.RtEmph, lb.Objects['emphasis'], 'hovered');
    end;
  end;
  Finish('the hovered rich label');
end;

{ ==================== on the screen ==================== }

procedure TAdvChartAuthorStylesPaintTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartAuthorStylesPaintTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAuthorStylesPaintTest.Draw(const AOption: string);
begin
  FreeAndNil(FChart);
  FChart := TAsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  if GetEnvironmentVariable('R5B_DUMP') <> '' then
  begin
    Inc(GDumpN);
    FBmp.SaveToFile(GetEnvironmentVariable('R5B_DUMP') + IntToStr(GDumpN) + '.png');
  end;
end;

function TAdvChartAuthorStylesPaintTest.CountIn(const ARect: TRect;
  R, G, B, ATol: Integer): Integer;
var
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := 0;
  for y := Max(0, ARect.Top) to Min(FBmp.Height, ARect.Bottom) - 1 do
    for x := Max(0, ARect.Left) to Min(FBmp.Width, ARect.Right) - 1 do
    begin
      p := FBmp.GetPixel(x, y);
      if (Abs(p.red - R) <= ATol) and (Abs(p.green - G) <= ATol)
        and (Abs(p.blue - B) <= ATol) then Inc(Result);
    end;
end;

function TAdvChartAuthorStylesPaintTest.CountTint(const ARect: TRect;
  AStrong, ALo, AHi: Integer): Integer;
var
  x, y: Integer;
  p: TBGRAPixel;
  c: array[0..2] of Integer;
  k: Integer;
  ok: Boolean;
begin
  Result := 0;
  for y := Max(0, ARect.Top) to Min(FBmp.Height, ARect.Bottom) - 1 do
    for x := Max(0, ARect.Left) to Min(FBmp.Width, ARect.Right) - 1 do
    begin
      p := FBmp.GetPixel(x, y);
      c[0] := p.red;
      c[1] := p.green;
      c[2] := p.blue;
      ok := c[AStrong] >= 200;
      for k := 0 to 2 do
        if (k <> AStrong) and ((c[k] < ALo) or (c[k] > AHi)) then ok := False;
      if ok then Inc(Result);
    end;
end;

function TAdvChartAuthorStylesPaintTest.CountNear(R, G, B, ATol: Integer): Integer;
begin
  Result := CountIn(Rect(0, 0, cW, cH), R, G, B, ATol);
end;

const
  cBars = '"series":[{"type":"bar","data":[5,3,8,2,6],"itemStyle":{"color":"#dddddd"}}]';
  { data that draws nothing, so the axes have a scale and nothing covers
    them }
  cNoInk = '"series":[{"type":"bar","data":[5,3,8,2,6],"itemStyle":{"opacity":0}}]';

procedure TAdvChartAuthorStylesPaintTest.TestAnAxisLineIsDrawnInItsColourAndWidth;
var thin, thick: Integer;
begin
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"],'
    + '"axisLine":{"lineStyle":{"color":"#ff0000"}}},"yAxis":{"type":"value"},' + cNoInk + '}');
  thin := CountNear(255, 0, 0, 40);
  AssertTrue('the line is in the author''s red: ' + IntToStr(thin), thin > 300);
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"],'
    + '"axisLine":{"lineStyle":{"color":"#ff0000","width":3}}},"yAxis":{"type":"value"},' + cNoInk + '}');
  thick := CountNear(255, 0, 0, 40);
  AssertTrue(Format('three times as wide: %d against %d', [thick, thin]),
    (thick > 2.5 * thin) and (thick < 3.5 * thin));
  { the default: no red at all }
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value"},' + cBars + '}');
  AssertEquals('the skin''s line is not red', 0, CountNear(255, 0, 0, 40));
end;

procedure TAdvChartAuthorStylesPaintTest.TestTicksArrowsAndNameFollowTheLine;
var
  grid: TTyGridBuild;
  plot: TTyRectF;
  below, right, nameInk: Integer;
begin
  Draw('{"animation":false,"xAxis":{"type":"category","boundaryGap":false,"name":"NAME",'
    + '"data":["a","b","c","d","e"],"axisLine":{"symbol":["none","arrow"],'
    + '"lineStyle":{"color":"#ff0000"}}},"yAxis":{"type":"value"},' + cNoInk + '}');
  grid := FChart.Build.Grid(0);
  plot := grid.PlotRect;
  { the ticks hang below the line, inside the plot's span }
  below := CountIn(Rect(Round(plot.Left) + 2, Round(plot.Bottom) + 2,
    Round(plot.Right) - 2, Round(plot.Bottom) + 6), 255, 0, 0, 60);
  AssertTrue('red ticks under the line: ' + IntToStr(below), below >= 5 * 3);
  { the arrow at the end of the line, above it }
  right := CountIn(Rect(Round(plot.Right) - 16, Round(plot.Bottom) - 7,
    Round(plot.Right) + 10, Round(plot.Bottom) - 1), 255, 0, 0, 60);
  AssertTrue(Format('a red arrow at the end: %d (plot %g %g %g %g)', [right, plot.Left, plot.Top, plot.Right, plot.Bottom]), right >= 10);
  { the name, past the arrow }
  nameInk := CountIn(Rect(Round(plot.Right) + 14, Round(plot.Bottom) - 12,
    cW, Round(plot.Bottom) + 12), 255, 0, 0, 90);
  AssertTrue('a red name: ' + IntToStr(nameInk), nameInk >= 10);
end;

procedure TAdvChartAuthorStylesPaintTest.TestASplitLineDashesAndFades;
var
  solid, dashed, faded, full: Integer;
begin
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value","splitLine":{"lineStyle":{"color":"#0000ff"}}},' + cBars + '}');
  solid := CountNear(0, 0, 255, 40);
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value","splitLine":{"lineStyle":{"color":"#0000ff","type":"dashed"}}},'
    + cBars + '}');
  dashed := CountNear(0, 0, 255, 40);
  AssertTrue(Format('a dash leaves gaps: %d against %d', [dashed, solid]),
    (dashed > 0.5 * solid) and (dashed < 0.8 * solid));
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value","splitLine":{"lineStyle":{"color":"#0000ff","opacity":0.5}}},'
    + cBars + '}');
  faded := CountTint(Rect(0, 0, cW, cH), 2, 100, 215);
  full := CountNear(0, 0, 255, 40);
  AssertTrue(Format('half the blue: %d faded, %d full', [faded, full]),
    (faded > 0.8 * solid) and (full = 0));
end;

procedure TAdvChartAuthorStylesPaintTest.TestABandTakesItsOpacity;
var full, half: Integer;
begin
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value","splitLine":{"show":false},"splitArea":{"show":true,'
    + '"areaStyle":{"color":["#00ff00","#00ff00"]}}},' + cNoInk + '}');
  full := CountNear(0, 255, 0, 20);
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value","splitLine":{"show":false},"splitArea":{"show":true,'
    + '"areaStyle":{"color":["#00ff00","#00ff00"],"opacity":0.5}}},' + cNoInk + '}');
  half := CountTint(Rect(0, 0, cW, cH), 1, 100, 215);
  AssertTrue('the bands are green: ' + IntToStr(full), full > 10000);
  AssertTrue(Format('at half: %d against %d', [half, full]), half > 0.95 * full);
  AssertEquals('none at full', 0, CountNear(0, 255, 0, 20));
end;

procedure TAdvChartAuthorStylesPaintTest.TestMinorTicksTakeTheLinesColour;
var
  grid: TTyGridBuild;
  plot: TTyRectF;
  red: Integer;
begin
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value","axisLine":{"show":true,"lineStyle":{"color":"#ff0000"}},'
    + '"axisTick":{"show":true,"length":8},"minorTick":{"show":true,"length":3}},' + cBars + '}');
  grid := FChart.Build.Grid(0);
  plot := grid.PlotRect;
  { the strip between the end of a minor tick and the end of a major one
    holds only majors; the strip next to the line holds both }
  red := CountIn(Rect(Round(plot.Left) - 3, Round(plot.Top), Round(plot.Left) - 1,
    Round(plot.Bottom)), 255, 0, 0, 60);
  AssertTrue('red minor ticks next to the line: ' + IntToStr(red),
    red > 2 * CountIn(Rect(Round(plot.Left) - 7, Round(plot.Top), Round(plot.Left) - 5,
      Round(plot.Bottom)), 255, 0, 0, 60));
end;

procedure TAdvChartAuthorStylesPaintTest.TestEveryOtherAxisTakesItsColour;
const
  cRed = '"axisLine":{"lineStyle":{"color":"#ff0000","width":3}}';
begin
  Draw('{"animation":false,"singleAxis":{"type":"value","top":50,"height":100,' + cRed + '},'
    + '"series":[{"type":"scatter","coordinateSystem":"singleAxis","data":[1,3,7]}]}');
  AssertTrue('a single axis', CountNear(255, 0, 0, 40) > 300);
  Draw('{"animation":false,"polar":{},"angleAxis":{"type":"value",' + cRed + '},'
    + '"radiusAxis":{"type":"value"},'
    + '"series":[{"type":"line","coordinateSystem":"polar","data":[[1,30],[3,120]]}]}');
  AssertTrue('an angle axis', CountNear(255, 0, 0, 40) > 300);
  Draw('{"animation":false,"polar":{},"angleAxis":{"type":"value"},'
    + '"radiusAxis":{"type":"value",' + cRed + '},'
    + '"series":[{"type":"line","coordinateSystem":"polar","data":[[1,30],[3,120]]}]}');
  AssertTrue('a radius axis', CountNear(255, 0, 0, 40) > 100);
  Draw('{"animation":false,"parallelAxis":[{"dim":0},{"dim":1,' + cRed + '}],'
    + '"series":[{"type":"parallel","lineStyle":{"color":"#dddddd"},"data":[[1,2],[3,4]]}]}');
  AssertTrue('a parallel axis', CountNear(255, 0, 0, 40) > 100);
  Draw('{"animation":false,"radar":{"indicator":[{"name":"a","max":10},{"name":"b","max":10},'
    + '{"name":"c","max":10}],"axisLine":{"lineStyle":{"color":"#ff0000","type":"dashed"}},'
    + '"splitArea":{"areaStyle":{"color":["#00ff00"],"opacity":0.5}}},'
    + '"series":[{"type":"radar","lineStyle":{"color":"#dddddd"},"data":[{"value":[3,5,7]}]}]}');
  AssertTrue('the radar''s spokes', CountTint(Rect(0, 0, cW, cH), 0, 0, 140) > 30);
  AssertTrue('the radar''s bands at half', CountTint(Rect(0, 0, cW, cH), 1, 100, 215) > 1000);
  AssertEquals('none at full', 0, CountNear(0, 255, 0, 20));
end;

procedure TAdvChartAuthorStylesPaintTest.TestABarBackgroundIsDrawnInItsStyle;
var plain, styled, pen: Integer;
begin
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value","max":10,"splitLine":{"show":false}},"series":[{"type":"bar",'
    + '"data":[5,3,8,2,6],"itemStyle":{"color":"#dddddd"},"showBackground":true}]}');
  plain := CountTint(Rect(0, 0, cW, cH), 1, 0, 140);
  Draw('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value","max":10,"splitLine":{"show":false}},"series":[{"type":"bar",'
    + '"data":[5,3,8,2,6],"itemStyle":{"color":"#dddddd"},"showBackground":true,'
    + '"backgroundStyle":{"color":"#00ff00","borderColor":"#ff0000","borderWidth":2}}]}');
  styled := CountTint(Rect(0, 0, cW, cH), 1, 0, 140);
  pen := CountNear(255, 0, 0, 60);
  AssertEquals('the skin''s strip is not green', 0, plain);
  AssertTrue('the strips are green: ' + IntToStr(styled), styled > 5000);
  AssertTrue('and outlined in red: ' + IntToStr(pen), pen > 500);
end;

procedure TAdvChartAuthorStylesPaintTest.TestATreemapHasRoundCorners;
var square, round: Integer;
begin
  Draw('{"animation":false,"series":[{"type":"treemap","roam":false,"nodeClick":false,'
    + '"breadcrumb":{"show":false},"label":{"show":false},"itemStyle":{"borderWidth":0,"gapWidth":0},'
    + '"data":[{"name":"a","value":1,"itemStyle":{"color":"#0000ff"}}]}]}');
  square := CountNear(0, 0, 255, 40);
  Draw('{"animation":false,"series":[{"type":"treemap","roam":false,"nodeClick":false,'
    + '"breadcrumb":{"show":false},"label":{"show":false},"itemStyle":{"borderWidth":0,"gapWidth":0,'
    + '"borderRadius":40},"data":[{"name":"a","value":1,"itemStyle":{"color":"#0000ff"}}]}]}');
  round := CountNear(0, 0, 255, 40);
  { four corners of radius 40 take (4 - pi) * 40^2 = 1373 px off }
  AssertTrue(Format('the corners are cut: %d against %d', [round, square]),
    (square - round > 1100) and (square - round < 1650));
end;

initialization
  RegisterTest(TAdvChartAuthorStylesOracleTest);
  RegisterTest(TAdvChartAuthorStylesPaintTest);
end.
