unit test.advchart.palettefill;
{$mode objfpc}{$H+}
{ PALETTES AND FILLS, held to what ECharts 6.1 does [Batch 105]: the colour
  every series and every datum takes (colorLayer chosen by the requested
  count, colorBy and its scope shared per type-colorBy, a written colour, a
  datum's own, `auto`, the undefined pick past a short layer's end), the
  legend icons, and what an OBJECT fill resolves to on the canvas -- a
  gradient's coordinates against the element's box (the path's, grown by the
  stroke) or in chart coordinates, and a pattern's repetition and matrix.

  tools/advchart-oracle/palette-fill.js records them; each case is replayed
  here and compared bit for bit, colours as the colours they name. The
  pixel tests check that the gradient and the pattern are really painted. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvChart.Render,
     tyControls.AdvChart.Legend,
     tyControls.AdvanceChart;
type
  TPfProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartPaletteFillTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TPfProbe;
    FRoot: TJSONObject;
    FBmp: TBGRABitmap;
    FBad, FCompared, FRows, FEls, FGrads, FPats, FIcons: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; A: Double; AFx: TJSONData);
    function Realise(AData: TJSONData): TJSONData;
    procedure LoadCase(ACase: TJSONObject; APPI: Integer);
    procedure Colour(const AWhat: string; A: TTyChartColor; AFx: TJSONData);
    function FindRowEl(ASeries, ARaw: Integer; out AEl: TTyChartElement): Boolean;
    procedure CheckEl(const AWhat: string; const AEl: TTyChartElement; AFx: TJSONObject);
    procedure CheckGrad(const AWhat: string; const AGrad: TTyChartGradient;
      const AEl: TTyChartElement; APaint: TJSONObject; ARec: TJSONData);
    procedure Load(const AOption: string; AWidth, AHeight, APPI: Integer);
    function Px(AX, AY: Integer): TBGRAPixel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPalettesAndFillsAsUpstream;
    procedure TestAMarkAreaGradientIsPainted;
    procedure TestAPatternTilesInCanvasSpace;
    procedure TestAPatternScalesWithTheDevice;
    procedure TestAnUndefinedPickPaintsNothing;
    procedure TestTheThemeIsTheDefaultPalette;
  end;

implementation

const
  cDefaultPalette = '["#5070dd","#b6d634","#505372","#ff994d","#0ca8df",'
    + '"#ffd10a","#fb628b","#785db0","#3fbe95"]';

procedure TPfProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TPfProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-palette-fill.json';
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
  if IsNan(A) then Exit('NaN');
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

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

procedure TAdvChartPaletteFillTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TPfProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := TJSONObject(GetJSON(sl.Text));
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FRows := 0;
  FEls := 0;
  FGrads := 0;
  FPats := 0;
  FIcons := 0;
  FReport := '';
end;

procedure TAdvChartPaletteFillTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartPaletteFillTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartPaletteFillTest.Num(const AWhat: string; A: Double; AFx: TJSONData);
begin
  Inc(FCompared);
  if IsNull(AFx) then
  begin
    Miss(Format('%s: null upstream, %s here', [AWhat, Fmt(A)]));
    Exit;
  end;
  if not SameNum(A, AFx.AsString) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AFx.AsString)), Fmt(A)]));
end;

{ the option as fed: "@img:<name>" stands for the fixture's image }
function TAdvChartPaletteFillTest.Realise(AData: TJSONData): TJSONData;
var
  i: Integer;
  s: string;
  o: TJSONObject;
begin
  Result := AData;
  case AData.JSONType of
    jtString:
      begin
        s := AData.AsString;
        if Copy(s, 1, 5) = '@img:' then
          Result := TJSONString.Create(FRoot.Objects['images'].Strings[Copy(s, 6, MaxInt)]);
      end;
    jtArray:
      for i := 0 to AData.Count - 1 do
        if AData.Items[i].JSONType in [jtString, jtArray, jtObject] then
          TJSONArray(AData).Items[i] := Realise(AData.Items[i].Clone);
    jtObject:
      begin
        o := TJSONObject(AData);
        for i := 0 to o.Count - 1 do
          if o.Items[i].JSONType in [jtString, jtArray, jtObject] then
            o.Elements[o.Names[i]] := Realise(o.Items[i].Clone);
      end;
  end;
  if Result <> AData then AData.Free;
end;

procedure TAdvChartPaletteFillTest.LoadCase(ACase: TJSONObject; APPI: Integer);
var opt: TJSONObject;
begin
  opt := TJSONObject(Realise(ACase.Objects['option'].Clone));
  try
    { UPSTREAM'S OWN PALETTE where the option names none: the port's default
      is the theme's ramp }
    if opt.Find('color') = nil then opt.Add('color', GetJSON(cDefaultPalette));
    opt.Add('animation', False);
    Load(opt.AsJSON, 800, 600, APPI);
  finally
    opt.Free;
  end;
end;

procedure TAdvChartPaletteFillTest.Load(const AOption: string; AWidth, AHeight,
  APPI: Integer);
var dw, dh: Integer;
begin
  dw := AWidth * APPI div 96;
  dh := AHeight * APPI div 96;
  FBmp.Free;
  FBmp := TBGRABitmap.Create(dw, dh, BGRA(255, 255, 255, 255));
  FChart.Option := '{}';
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, AWidth, AHeight);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, dw, dh), APPI);
end;

function TAdvChartPaletteFillTest.Px(AX, AY: Integer): TBGRAPixel;
begin
  Result := FBmp.GetPixel(AX, AY);
end;

{ a colour as the colour it names; null is no colour (nothing, or clear) }
procedure TAdvChartPaletteFillTest.Colour(const AWhat: string; A: TTyChartColor;
  AFx: TJSONData);
var want: TTyChartColor;
begin
  Inc(FCompared);
  if IsNull(AFx) then
  begin
    if (A shr 24) <> 0 then Miss(Format('%s: none upstream, $%.8x here', [AWhat, A]));
    Exit;
  end;
  if AFx.JSONType <> jtString then Exit;
  if not TyTryParseChartColor(AFx.AsString, want) then
  begin
    Miss(AWhat + ': upstream''s "' + AFx.AsString + '" does not parse');
    Exit;
  end;
  if want <> A then
    Miss(Format('%s: %s ($%.8x) upstream, $%.8x here', [AWhat, AFx.AsString, want, A]));
end;

function TAdvChartPaletteFillTest.FindRowEl(ASeries, ARaw: Integer;
  out AEl: TTyChartElement): Boolean;
var
  k: Integer;
  e: TTyChartElement;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    if e.Ignore or (e.Datum.Kind <> ctkSeries) then Continue;
    if (e.Datum.SeriesIndex <> ASeries) or (e.Datum.RawDataIndex <> ARaw) then Continue;
    if (e.Caption.Text <> '') or (e.Shape.Kind = cskPolyline) then Continue;
    AEl := e;
    Exit(True);
  end;
end;

procedure TAdvChartPaletteFillTest.CheckGrad(const AWhat: string;
  const AGrad: TTyChartGradient; const AEl: TTyChartElement;
  APaint: TJSONObject; ARec: TJSONData);
var
  stops: TJSONArray;
  k: Integer;
  c: TTyChartColor;
  d: TJSONData;
  radial: Boolean;
  x1, y1, x2, y2, r: Double;
  rec: TJSONObject;
begin
  Inc(FGrads);
  Inc(FCompared);
  d := APaint.Find('type');
  radial := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'radial');
  if AGrad.Kind = cgkNone then
  begin
    Miss(AWhat + ': a gradient upstream, none here');
    Exit;
  end;
  if (AGrad.Kind = cgkRadial) <> radial then
  begin
    Miss(AWhat + ': the gradient''s shape');
    Exit;
  end;
  d := APaint.Find('global');
  Inc(FCompared);
  if AGrad.Global <> ((d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean) then
    Miss(AWhat + ': global');
  stops := APaint.Arrays['colorStops'];
  Inc(FCompared);
  if stops.Count <> Length(AGrad.Stops) then
  begin
    Miss(Format('%s: %d stops upstream, %d here', [AWhat, stops.Count, Length(AGrad.Stops)]));
    Exit;
  end;
  for k := 0 to stops.Count - 1 do
  begin
    Inc(FCompared);
    if (stops.Objects[k].Floats['offset'] <> AGrad.Stops[k].Offset)
      or not TyTryParseChartColor(stops.Objects[k].Strings['color'], c)
      or (c <> AGrad.Stops[k].Color) then
      Miss(Format('%s: stop %d', [AWhat, k]));
  end;
  if IsNull(ARec) then
  begin
    Miss(AWhat + ': no canvas gradient recorded');
    Exit;
  end;
  rec := TJSONObject(ARec);
  TyResolveGradientXYWH(AGrad, TyElementGradientBox(AEl, 96), x1, y1, x2, y2, r);
  Num(AWhat + '.x1', x1, rec.Find('x1'));
  Num(AWhat + '.y1', y1, rec.Find('y1'));
  Num(AWhat + '.x2', x2, rec.Find('x2'));
  Num(AWhat + '.y2', y2, rec.Find('y2'));
  Num(AWhat + '.r', r, rec.Find('r'));
end;

procedure TAdvChartPaletteFillTest.CheckEl(const AWhat: string;
  const AEl: TTyChartElement; AFx: TJSONObject);
var
  fill: TJSONData;
  m: TTyDoubleArray;
  k: Integer;
  pat: TJSONObject;
  want: TTyChartColor;
  img: string;
begin
  Inc(FEls);
  fill := AFx.Find('fill');
  Inc(FCompared);
  { 'none', and a colour with no alpha, paint what no fill paints }
  if (fill <> nil) and (fill.JSONType = jtString)
    and (TyChartColorIsNone(fill.AsString)
      or (TyTryParseChartColor(fill.AsString, want) and ((want shr 24) = 0))) then
    fill := nil;
  if IsNull(fill) then
  begin
    if AEl.Style.HasFill and (((AEl.Style.FillColor shr 24) <> 0)
      or (AEl.Style.FillGradient.Kind <> cgkNone) or AEl.Style.FillPattern.Present) then
      Miss(AWhat + ': no fill upstream, one here');
  end
  else if fill.JSONType = jtString then
  begin
    if not AEl.Style.HasFill then
      Miss(AWhat + ': fill ' + fill.AsString + ' upstream, none here')
    else if (AEl.Style.FillGradient.Kind <> cgkNone) or AEl.Style.FillPattern.Present then
      Miss(AWhat + ': fill ' + fill.AsString + ' upstream, an object here')
    else if TyTryParseChartColor(fill.AsString, want) then
      Colour(AWhat + ' fill', AEl.Style.FillColor, fill);
  end
  else if TJSONObject(fill).Find('colorStops') <> nil then
  begin
    if not AEl.Style.HasFill then Miss(AWhat + ': a gradient fill upstream, no fill here')
    else CheckGrad(AWhat + ' fill', AEl.Style.FillGradient, AEl, TJSONObject(fill),
      AFx.Find('grad'));
  end
  else if TJSONObject(fill).Find('image') <> nil then
  begin
    Inc(FPats);
    if not (AEl.Style.HasFill and AEl.Style.FillPattern.Present) then
      Miss(AWhat + ': a pattern upstream, none here')
    else
    begin
      Inc(FCompared);
      img := TJSONObject(fill).Strings['image'];
      if Copy(img, 1, 5) = '@img:' then
        img := FRoot.Objects['images'].Strings[Copy(img, 6, MaxInt)];
      if AEl.Style.FillPattern.Image <> img then
        Miss(AWhat + ': the pattern''s image');
      pat := AFx.Objects['pat'];
      Inc(FCompared);
      if AEl.Style.FillPattern.Repetition <> pat.Strings['repeat'] then
        Miss(AWhat + ': repeat ' + pat.Strings['repeat'] + ' upstream, '
          + AEl.Style.FillPattern.Repetition + ' here');
      TyPatternMatrix(AEl.Style.FillPattern, m);
      for k := 0 to 5 do
        Num(Format('%s pattern[%d]', [AWhat, k]), m[k], pat.Arrays['matrix'].Items[k]);
    end;
  end;
  { a stroke that is a gradient, where there is a stroke to paint }
  if not IsNull(AFx.Find('sgrad')) and not IsNull(AFx.Find('lineWidth'))
    and (FromHex(AFx.Strings['lineWidth']) > 0) then
    CheckGrad(AWhat + ' stroke', AEl.Style.StrokeGradient, AEl,
      AFx.Objects['stroke'], AFx.Find('sgrad'));
end;

procedure TAdvChartPaletteFillTest.TestPalettesAndFillsAsUpstream;
var
  cases, series, rows, areas, legends, items: TJSONArray;
  cs, se, rw, li: TJSONObject;
  c, s, r, k, j, si, raw, li2: Integer;
  el, e: TTyChartElement;
  d: TJSONData;
  got: Boolean;
  dk: string;
  lay: TTyLegendLayout;
begin
  cases := FRoot.Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FName := cs.Strings['id'];
    try
      LoadCase(cs, 96);
    except
      on Ex: Exception do
      begin
        Miss(Ex.ClassName + ': ' + Ex.Message);
        Continue;
      end;
    end;
    series := cs.Arrays['series'];
    for s := 0 to series.Count - 1 do
    begin
      se := series.Objects[s];
      si := se.Integers['index'];
      dk := se.Strings['drawType'];
      { THE SERIES' COLOUR: what seriesStyleTask wrote under drawType }
      d := se.Find(dk);
      if IsNull(d) or (d.JSONType = jtString) then
        Colour(Format('series %d colour', [si]), FChart.PaletteSeriesColour(si), d);
      if se.Booleans['filtered'] then Continue;
      rows := se.Arrays['rows'];
      for r := 0 to rows.Count - 1 do
      begin
        rw := rows.Objects[r];
        if not rw.Booleans['inView'] then Continue;
        raw := rw.Integers['raw'];
        Inc(FRows);
        d := rw.Find('fill');
        if IsNull(d) or (d.JSONType = jtString) then
          Colour(Format('series %d row %d colour', [si, raw]),
            FChart.PaletteDatumColour(si, raw), d);
        if IsNull(rw.Find('el')) then Continue;
        Inc(FCompared);
        if not FindRowEl(si, raw, el) then
        begin
          Miss(Format('series %d row %d: drawn upstream, nothing here', [si, raw]));
          Continue;
        end;
        CheckEl(Format('series %d row %d', [si, raw]), el, rw.Objects['el']);
      end;
      { a line's polyline and its area }
      if not IsNull(se.Find('line')) then
      begin
        got := False;
        for k := 0 to FChart.List.Count - 1 do
        begin
          e := FChart.List.Element(k);
          if (e.Datum.SeriesIndex = si) and (e.Shape.Kind = cskPolyline)
            and (e.Caption.Text = '') and not e.Style.HasFill then
          begin
            if not got then
              CheckEl(Format('series %d line', [si]), e,
                se.Objects['line'].Objects['polyline']);
            got := True;
          end;
        end;
        Inc(FCompared);
        if not got then Miss(Format('series %d: no polyline', [si]));
        if not IsNull(se.Objects['line'].Find('area')) then
        begin
          got := False;
          for k := 0 to FChart.List.Count - 1 do
          begin
            e := FChart.List.Element(k);
            if (e.Datum.SeriesIndex = si) and (e.Shape.Kind = cskPolygon)
              and e.Silent and not got then
            begin
              CheckEl(Format('series %d area', [si]), e,
                se.Objects['line'].Objects['area']);
              got := True;
            end;
          end;
          Inc(FCompared);
          if not got then Miss(Format('series %d: no area', [si]));
        end;
      end;
      { the markAreas }
      if not IsNull(se.Find('areas')) then
      begin
        areas := se.Arrays['areas'];
        for j := 0 to areas.Count - 1 do
        begin
          if IsNull(areas.Objects[j].Find('el')) then Continue;
          got := False;
          for k := 0 to FChart.List.Count - 1 do
          begin
            e := FChart.List.Element(k);
            if (e.Datum.Kind = ctkMarkArea) and (e.Datum.ComponentIndex = si)
              and (e.Datum.DataIndex = areas.Objects[j].Integers['item'])
              and (e.Shape.Kind = cskPolygon) and not got then
            begin
              CheckEl(Format('series %d markArea %d', [si, j]), e,
                areas.Objects[j].Objects['el']);
              got := True;
            end;
          end;
          Inc(FCompared);
          if not got then Miss(Format('series %d markArea %d: not drawn here', [si, j]));
        end;
      end;
    end;
    { THE LEGEND ICONS: the first displayable of each item's icon -- its
      colour, or the object it is painted with }
    legends := cs.Arrays['legends'];
    for li2 := 0 to legends.Count - 1 do
    begin
      items := legends.Arrays[li2];
      for j := 0 to items.Count - 1 do
      begin
        li := items.Objects[j];
        if li.Arrays['icons'].Count = 0 then Continue;
        d := li.Arrays['icons'].Objects[0].Find('fill');
        lay := FChart.LegendLayout(li2);
        Inc(FCompared);
        if j > High(lay.Items) then
        begin
          Miss(Format('legend %d item %d: no item here', [li2, j]));
          Continue;
        end;
        Inc(FCompared);
        if lay.Items[j].Name <> li.Strings['name'] then
          Miss(Format('legend %d item %d: %s upstream, %s here', [li2, j,
            li.Strings['name'], lay.Items[j].Name]));
        { a switched-off item is the inactive ink, not its colour }
        if not lay.Items[j].Selected then Continue;
        Inc(FIcons);
        Inc(FCompared);
        if (d <> nil) and (d.JSONType = jtObject) then
        begin
          if not lay.Items[j].Obj.Present then
            Miss(Format('legend %d item %d: an object upstream, a colour here', [li2, j]))
          else if (TJSONObject(d).Find('image') <> nil)
            <> lay.Items[j].Obj.Pattern.Present then
            Miss(Format('legend %d item %d: the object''s kind', [li2, j]));
        end
        else
        begin
          if lay.Items[j].Obj.Present then
            Miss(Format('legend %d item %d: a colour upstream, an object here', [li2, j]));
          Colour(Format('legend %d item %d (%s)', [li2, j, li.Strings['name']]),
            lay.Items[j].Colour, d);
        end;
      end;
    end;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the rows were compared (%d)', [FRows]), FRows >= 250);
  AssertTrue(Format('the elements were compared (%d)', [FEls]), FEls >= 200);
  AssertTrue(Format('the gradients were compared (%d)', [FGrads]), FGrads >= 20);
  AssertTrue(Format('the patterns were compared (%d)', [FPats]), FPats >= 5);
  AssertTrue(Format('the legend icons were compared (%d)', [FIcons]), FIcons >= 10);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
end;

{ the area of grad-area-linear, red to blue across: the paint follows the
  resolved coordinates, left stop to right }
procedure TAdvChartPaletteFillTest.TestAMarkAreaGradientIsPainted;
var
  k, x, y, n: Integer;
  e: TTyChartElement;
  box: TTyXYWH;
  x1, y1, x2, y2, r, t: Double;
  p: TBGRAPixel;
begin
  Load('{"animation":false,"color":["#aa0000"],"xAxis":{"type":"category",'
    + '"data":["c0","c1","c2","c3"]},"yAxis":{"type":"value","splitLine":{"show":false}},'
    + '"series":[{"type":"line","data":[1,3,2,4],"markArea":{"data":[[{"xAxis":"c1",'
    + '"itemStyle":{"color":{"type":"linear","colorStops":[{"offset":0,"color":"#ff0000"},'
    + '{"offset":1,"color":"#0000ff"}]}}},{"xAxis":"c2"}]]}}]}', 800, 600, 96);
  n := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    if (e.Datum.Kind = ctkMarkArea) and (e.Shape.Kind = cskPolygon) then Break;
  end;
  AssertTrue('the area is there', e.Datum.Kind = ctkMarkArea);
  AssertTrue('it carries the gradient', e.Style.FillGradient.Kind = cgkLinear);
  box := TyElementGradientBox(e, 96);
  TyResolveGradientXYWH(e.Style.FillGradient, box, x1, y1, x2, y2, r);
  AssertTrue('left to right', x2 > x1);
  { the bottom tenth of the plot: under the line, over no split line }
  y := Round(box.Y + box.H * 0.9);
  x := Ceil(box.X) + 2;
  while x < Floor(box.X + box.W) - 2 do
  begin
    t := (x + 0.5 - x1) / (x2 - x1);
    p := Px(x, y);
    AssertTrue(Format('red at %d: %d, want %d', [x, p.red, Round(255 * (1 - t))]),
      Abs(p.red - 255 * (1 - t)) <= 6);
    AssertTrue(Format('blue at %d: %d, want %d', [x, p.blue, Round(255 * t)]),
      Abs(p.blue - 255 * t) <= 6);
    AssertTrue(Format('no green at %d', [x]), p.green <= 6);
    Inc(n);
    Inc(x, 7);
  end;
  AssertTrue('sampled across the area', n >= 10);
end;

{ pat-bar's checker, 2 x 2 red and blue, repeats from the CANVAS origin: a
  device pixel is red where x + y is even, wherever the bar happens to be }
procedure TAdvChartPaletteFillTest.TestAPatternTilesInCanvasSpace;
var
  k, x, y, n: Integer;
  e: TTyChartElement;
  b: TTyRectF;
  p: TBGRAPixel;
begin
  Load('{"animation":false,"legend":{},"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{},"series":[{"type":"bar","name":"p","itemStyle":{"color":{"image":"'
    + FRoot.Objects['images'].Strings['checker'] + '"}},"data":[3,5]}]}', 800, 600, 96);
  { THE LEGEND ICON is painted with the pattern too, as upstream's is }
  n := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    { an icon is no series datum }
    if (e.Datum.SeriesIndex < 0) and e.Style.FillPattern.Present then Inc(n);
  end;
  AssertEquals('one icon carries the pattern', 1, n);
  n := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    if (e.Datum.Kind <> ctkSeries) or (e.Datum.SeriesIndex <> 0)
      or (e.Caption.Text <> '') then Continue;
    AssertTrue('the bar carries the pattern', e.Style.FillPattern.Present);
    b := TyShapeBounds(e.Shape);
    y := Ceil(b.Top) + 2;
    while y < Floor(b.Bottom) - 2 do
    begin
      x := Ceil(b.Left) + 2;
      while x < Floor(b.Right) - 2 do
      begin
        p := Px(x, y);
        if (x + y) mod 2 = 0 then
          AssertTrue(Format('red at %d,%d: %d %d %d', [x, y, p.red, p.green, p.blue]),
            (p.red = 255) and (p.blue = 0))
        else
          AssertTrue(Format('blue at %d,%d: %d %d %d', [x, y, p.red, p.green, p.blue]),
            (p.red = 0) and (p.blue = 255));
        Inc(n);
        Inc(x, 5);
      end;
      Inc(y, 9);
    end;
  end;
  AssertTrue('sampled inside both bars', n >= 100);
end;

{ at twice the pixels each image pixel covers two device pixels each way --
  smoothed, as a canvas smooths a scaled pattern, so each device pixel is
  mostly the image pixel it lies in }
procedure TAdvChartPaletteFillTest.TestAPatternScalesWithTheDevice;
var
  k, x, y, n: Integer;
  e: TTyChartElement;
  b: TTyRectF;
  p: TBGRAPixel;
begin
  Load('{"animation":false,"xAxis":{"type":"category","data":["a"]},"yAxis":{},'
    + '"series":[{"type":"bar","itemStyle":{"color":{"image":"'
    + FRoot.Objects['images'].Strings['checker'] + '"}},"data":[3]}]}', 400, 300, 192);
  n := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    if (e.Datum.Kind <> ctkSeries) or (e.Caption.Text <> '') then Continue;
    b := TyShapeBounds(e.Shape);
    y := Ceil(b.Top) + 3;
    while y < Floor(b.Bottom) - 3 do
    begin
      x := Ceil(b.Left) + 3;
      while x < Floor(b.Right) - 3 do
      begin
        p := Px(x, y);
        if ((x div 2) + (y div 2)) mod 2 = 0 then
          AssertTrue(Format('mostly red at %d,%d: %d %d', [x, y, p.red, p.blue]),
            (p.red >= 150) and (p.red + p.blue >= 250))
        else
          AssertTrue(Format('mostly blue at %d,%d: %d %d', [x, y, p.red, p.blue]),
            (p.blue >= 150) and (p.red + p.blue >= 250));
        Inc(n);
        Inc(x, 5);
      end;
      Inc(y, 7);
    end;
  end;
  AssertTrue('sampled inside the bar', n >= 50);
end;

{ layer-pie-undefined: the one-slice pie asks palette[4] of a two-colour
  layer -- undefined, and nothing is painted where its disc is }
procedure TAdvChartPaletteFillTest.TestAnUndefinedPickPaintsNothing;
var
  cases: TJSONArray;
  c, k: Integer;
  e: TTyChartElement;
  cx, cy, r: Double;
  p: TBGRAPixel;
  found: Boolean;
begin
  cases := FRoot.Arrays['cases'];
  for c := 0 to cases.Count - 1 do
    if cases.Objects[c].Strings['id'] = 'layer-pie-undefined' then
      LoadCase(cases.Objects[c], 96);
  found := False;
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    if (e.Datum.SeriesIndex = 1) and (e.Shape.Kind = cskSector) then
    begin
      found := True;
      AssertTrue('no colour', (e.Style.FillColor shr 24) = 0);
      cx := e.Shape.CX;
      cy := e.Shape.CY;
      r := e.Shape.R1;
      p := Px(Round(cx + r / 2), Round(cy + r / 3));
      AssertTrue(Format('the ground shows through: %d %d %d', [p.red, p.green, p.blue]),
        (p.red = 255) and (p.green = 255) and (p.blue = 255));
    end;
  end;
  AssertTrue('the slice is laid out', found);
  { and the first pie's slices are painted }
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    if (e.Datum.SeriesIndex = 0) and (e.Shape.Kind = cskSector) then
      AssertTrue('a slice of the first pie is coloured', (e.Style.FillColor shr 24) = 255);
  end;
end;

{ with no `color` the theme's nine stand in, through the same cursor: a
  written colour takes no slot, so the third series takes the second slot }
procedure TAdvChartPaletteFillTest.TestTheThemeIsTheDefaultPalette;
var a2, b1, b0, a0: TTyChartColor;
begin
  Load('{"animation":false,"xAxis":{"type":"category","data":["a"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[1]},{"type":"bar","data":[1],'
    + '"itemStyle":{"color":"#123456"}},{"type":"bar","data":[1]}]}', 400, 300, 96);
  a0 := FChart.PaletteSeriesColour(0);
  a2 := FChart.PaletteSeriesColour(2);
  AssertEquals('the written one', Integer($FF123456), Integer(FChart.PaletteSeriesColour(1)));
  Load('{"animation":false,"xAxis":{"type":"category","data":["a"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[1]},{"type":"bar","data":[1]}]}', 400, 300, 96);
  b0 := FChart.PaletteSeriesColour(0);
  b1 := FChart.PaletteSeriesColour(1);
  AssertTrue('two theme slots differ', b0 <> b1);
  AssertEquals('the first slot', Integer(b0), Integer(a0));
  AssertEquals('the third series takes the SECOND slot', Integer(b1), Integer(a2));
  { two series of one name share a slot }
  Load('{"animation":false,"xAxis":{"type":"category","data":["a"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"s","data":[1]},{"type":"bar","name":"s",'
    + '"data":[1]},{"type":"bar","data":[1]}]}', 400, 300, 96);
  AssertEquals('the same name, the same colour', Integer(FChart.PaletteSeriesColour(0)),
    Integer(FChart.PaletteSeriesColour(1)));
  AssertEquals('and the next takes the second slot', Integer(b1),
    Integer(FChart.PaletteSeriesColour(2)));
end;

initialization
  RegisterTest(TAdvChartPaletteFillTest);
end.
