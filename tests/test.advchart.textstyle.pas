unit test.advchart.textstyle;
{$mode objfpc}{$H+}
{ AUTHORED TEXT STYLES, held to upstream.

  tools/advchart-oracle/text-style.js runs the real ECharts 6.1 build over
  axis labels and names, titles, legends and series labels with authored
  fontSize / fontWeight / fontFamily / color, the root textStyle, string
  font sizes, backgroundColor and darkMode, and records every text zrender
  paints. This compares the port's picture with it:

    an author's fontSize is CSS px (a number, '14' or '14px');
    the root textStyle reaches a text property by property, and only where
      the component has no default of its own (an axis label's 12px shuts out
      a root fontSize, not a root fontWeight; a legend's colour shuts out a
      root colour; an attached series label never takes one);
    darkMode forces whether the ground counts as dark -- which decides an
      inside label's halo.

  A PROPERTY IS COMPARED WHERE UPSTREAM MOVED IT: against the same
  component's value in the 'default-everything' case. Where upstream kept
  its default the port must keep the theme's (no author colour recorded, no
  pixel size): the defaults are the skin's business, not upstream's. Axis
  labels' and names' anchors are compared exactly, measured with zrender's
  own SSR table. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits, tyControls.Types,
     tyControls.Painter,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Layout, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Color, tyControls.AdvChart.Title,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TTsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure PaintStyles(ASpec: PTyAxisLayoutSpec; out ALabel, APrimary,
      AName: TTyStyleSet);
  end;

  TAdvChartTextStyleOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTsProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    FCase: string;
    { the 'default-everything' texts, per component }
    FBase: TJSONObject;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Miss(const AWhat: string);
    procedure Draw(ACase: TJSONObject);
    function Baseline(const AComponent: string): TJSONObject;
    procedure CheckFont(const AWhat: string; T: TJSONObject; AName: string;
      ASize, AWeight: Integer; AHasColour: Boolean; AColour: TTyChartColor;
      AColourToo: Boolean = True);
    procedure CheckAxes(ACase: TJSONObject);
    procedure CheckTitles(ACase: TJSONObject);
    procedure CheckCaptions(ACase: TJSONObject; const AComponent: string);
    procedure CheckGrid(ACase: TJSONObject);
    procedure Run(AMinimum: Integer);
  published
    procedure TestAuthoredTextAsUpstream;
    procedure TestAStringSizeIsPx;
    procedure TestTheAxisIsPaintedInWhatItWasMeasuredIn;
    procedure TestThePainterReadsAPixelSize;
  end;

implementation

{ none: the one the harness could not hold (a 'mono' family, which zrender's
  SSR measure counts by characters) TZrSsrMeasurer now measures so }
const
  cDeferred: array[0..0] of string = ('');

{ ==================== the probe ==================== }

function TTsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TTsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TTsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TTsProbe.PaintStyles(ASpec: PTyAxisLayoutSpec; out ALabel, APrimary,
  AName: TTyStyleSet);
begin
  AxisTextStyles(ASpec, ALabel, APrimary, AName);
end;

{ ==================== plumbing ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-text-style.json';
end;

function Hex(AData: TJSONData): Double;
var q: QWord; s: string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  s := AData.AsString;
  q := StrToQWord('$' + s);
  Move(q, Result, SizeOf(Result));
end;

function Str(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit('');
  Result := AData.AsString;
end;

{ a CSS weight word as a number }
function WeightOf(const AWord: string): Integer;
begin
  if (AWord = 'bold') or (AWord = 'bolder') then Exit(700);
  if (AWord = '') or (AWord = 'normal') then Exit(400);
  Result := StrToIntDef(AWord, 400);
end;

procedure TAdvChartTextStyleOracleTest.SetUp;
var
  sl: TStringList;
  cases: TJSONArray;
  i, k: Integer;
  t: TJSONObject;
  comp: string;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TTsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FRoot).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FRoot).Objects['ratios'].Integers['firstCode']));
  { the baseline: the first text of each component with nothing authored }
  FBase := TJSONObject.Create;
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['name'] = 'default-everything' then
      for k := 0 to cases.Objects[i].Arrays['texts'].Count - 1 do
      begin
        t := cases.Objects[i].Arrays['texts'].Objects[k];
        comp := t.Strings['component'];
        if FBase.Find(comp) = nil then FBase.Add(comp, t.Clone);
      end;
  { a title and a legend are not in it: their own default cases stand in }
  for i := 0 to cases.Count - 1 do
    if (cases.Objects[i].Strings['name'] = 'title-default')
      or (cases.Objects[i].Strings['name'] = 'legend-default') then
      for k := 0 to cases.Objects[i].Arrays['texts'].Count - 1 do
      begin
        t := cases.Objects[i].Arrays['texts'].Objects[k];
        comp := t.Strings['component'];
        if FBase.Find(comp) = nil then FBase.Add(comp, t.Clone);
      end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartTextStyleOracleTest.TearDown;
begin
  FChart.Measurer := nil;
  FBase.Free;
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartTextStyleOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 6000 then
    FReport := FReport + LineEnding + '  ' + FCase + ': ' + AWhat;
end;

procedure TAdvChartTextStyleOracleTest.Draw(ACase: TJSONObject);
var w, h: Integer;
begin
  w := ACase.Get('W', 600);
  h := ACase.Get('H', 400);
  FBmp.SetSize(w, h);
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, w, h);
  FChart.Render(FBmp.Canvas, Rect(0, 0, w, h), 96);
end;

function TAdvChartTextStyleOracleTest.Baseline(const AComponent: string): TJSONObject;
var d: TJSONData;
begin
  d := FBase.Find(AComponent);
  if d is TJSONObject then Result := TJSONObject(d) else Result := nil;
end;

{ one text's font and colour against upstream's, where upstream moved them }
procedure TAdvChartTextStyleOracleTest.CheckFont(const AWhat: string;
  T: TJSONObject; AName: string; ASize, AWeight: Integer; AHasColour: Boolean;
  AColour: TTyChartColor; AColourToo: Boolean);
var
  b: TJSONObject;
  px: Double;
  c: TTyChartColor;
  fill: string;
begin
  b := Baseline(T.Strings['component']);
  if b = nil then
  begin
    Miss(AWhat + ': no baseline for ' + T.Strings['component']);
    Exit;
  end;
  px := T.Get('px', 12.0);
  Inc(FCompared);
  if px <> b.Get('px', 12.0) then
  begin
    if not TyFontSizeIsPx(ASize) or (Abs(TyFontPxOf(ASize) - px) > 1e-9) then
      Miss(Format('%s "%s": %s px upstream, size %d here',
        [AWhat, T.Strings['text'], FloatToStr(px), ASize]));
  end
  else if TyFontSizeIsPx(ASize) and (Abs(TyFontPxOf(ASize) - px) > 1e-9) then
    Miss(Format('%s "%s": upstream kept its default, here %s px',
      [AWhat, T.Strings['text'], FloatToStr(TyFontPxOf(ASize))]));
  Inc(FCompared);
  if Str(T.Find('fontWeight')) <> Str(b.Find('fontWeight')) then
  begin
    if WeightOf(Str(T.Find('fontWeight'))) <> AWeight then
      Miss(Format('%s "%s": weight %s upstream, %d here',
        [AWhat, T.Strings['text'], Str(T.Find('fontWeight')), AWeight]));
  end;
  Inc(FCompared);
  if Str(T.Find('fontFamily')) <> Str(b.Find('fontFamily')) then
  begin
    if Str(T.Find('fontFamily')) <> AName then
      Miss(Format('%s "%s": family %s upstream, %s here',
        [AWhat, T.Strings['text'], Str(T.Find('fontFamily')), AName]));
  end;
  { THE COLOUR: authored where upstream's differs from its default }
  if not AColourToo then Exit;
  fill := Str(T.Find('fill'));
  Inc(FCompared);
  if fill <> Str(b.Find('fill')) then
  begin
    if not TyTryParseChartColor(fill, c) then
      Miss(AWhat + ': unreadable upstream fill ' + fill)
    else if not AHasColour or (AColour <> c) then
      Miss(Format('%s "%s": fill %s upstream, %s here',
        [AWhat, T.Strings['text'], fill, BoolToStr(AHasColour, IntToHex(AColour, 8), 'the theme''s')]));
  end
  else if AHasColour then
    Miss(Format('%s "%s": upstream kept its default colour, here %s',
      [AWhat, T.Strings['text'], IntToHex(AColour, 8)]));
end;

procedure TAdvChartTextStyleOracleTest.CheckGrid(ACase: TJSONObject);
var
  g: TJSONArray;
  r: TJSONObject;
  pr: TTyRectF;
begin
  g := ACase.Arrays['grids'];
  if (g.Count = 0) or (FChart.Build = nil) or (FChart.Build.GridCount = 0) then Exit;
  r := g.Objects[0].Objects['rect'];
  pr := FChart.Build.Grid(0).PlotRect;
  Inc(FCompared);
  if (Abs(pr.Left - Hex(r.Find('x'))) > 1e-9) or (Abs(pr.Top - Hex(r.Find('y'))) > 1e-9)
    or (Abs(pr.Right - pr.Left - Hex(r.Find('width'))) > 1e-9)
    or (Abs(pr.Bottom - pr.Top - Hex(r.Find('height'))) > 1e-9) then
    Miss(Format('grid %s,%s %sx%s upstream, %s,%s %sx%s here', [
      FloatToStr(Hex(r.Find('x'))), FloatToStr(Hex(r.Find('y'))),
      FloatToStr(Hex(r.Find('width'))), FloatToStr(Hex(r.Find('height'))),
      FloatToStr(pr.Left), FloatToStr(pr.Top), FloatToStr(pr.Right - pr.Left),
      FloatToStr(pr.Bottom - pr.Top)]));
end;

procedure TAdvChartTextStyleOracleTest.CheckAxes(ACase: TJSONObject);
var
  texts: TJSONArray;
  t: TJSONObject;
  i, q: Integer;
  owner, comp: string;
  gb: TTyGridBuild;
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  found: Boolean;
  used: array of Boolean;
begin
  if (FChart.Build = nil) or (FChart.Build.GridCount = 0) then Exit;
  gb := FChart.Build.Grid(0);
  texts := ACase.Arrays['texts'];
  for i := 0 to texts.Count - 1 do
  begin
    t := texts.Objects[i];
    comp := t.Strings['component'];
    if (comp <> 'axisLabel') and (comp <> 'axisName') then Continue;
    owner := t.Get('owner', '');
    if owner = 'xAxis0' then ax := gb.XAxis(0)
    else if owner = 'yAxis0' then ax := gb.YAxis(0)
    else Continue;
    spec := gb.SpecFor(ax);
    if spec = nil then Continue;
    if comp = 'axisName' then
    begin
      Inc(FCompared);
      if not spec^.NamePlacement.Shown or (spec^.NamePlacement.Text <> t.Strings['text']) then
      begin
        Miss(owner + ' name "' + t.Strings['text'] + '" not drawn');
        Continue;
      end;
      CheckFont(owner + ' name', t, spec^.NameFontName, spec^.NameFontSizeLogical,
        spec^.NameFontWeight, spec^.HasNameColour, spec^.NameColour);
      Inc(FCompared);
      if (Abs(spec^.NamePlacement.X - Hex(t.Find('x'))) > 1e-6)
        or (Abs(spec^.NamePlacement.Y - Hex(t.Find('y'))) > 1e-6) then
        Miss(Format('%s name at (%s, %s) upstream, (%s, %s) here', [owner,
          FloatToStr(Hex(t.Find('x'))), FloatToStr(Hex(t.Find('y'))),
          FloatToStr(spec^.NamePlacement.X), FloatToStr(spec^.NamePlacement.Y)]));
      Continue;
    end;
    { a label: the shown placement with its words }
    SetLength(used, Length(spec^.Placements));
    found := False;
    for q := 0 to High(spec^.Placements) do
      if spec^.Placements[q].Shown and (spec^.Placements[q].Text = t.Strings['text']) then
      begin
        found := True;
        Inc(FCompared);
        if (Abs(spec^.Placements[q].X - Hex(t.Find('x'))) > 1e-6)
          or (Abs(spec^.Placements[q].Y - Hex(t.Find('y'))) > 1e-6) then
          Miss(Format('%s label "%s" at (%s, %s) upstream, (%s, %s) here', [owner,
            t.Strings['text'], FloatToStr(Hex(t.Find('x'))), FloatToStr(Hex(t.Find('y'))),
            FloatToStr(spec^.Placements[q].X), FloatToStr(spec^.Placements[q].Y)]));
        Break;
      end;
    Inc(FCompared);
    if not found then
    begin
      Miss(owner + ' label "' + t.Strings['text'] + '" not shown');
      Continue;
    end;
    CheckFont(owner + ' label', t, spec^.FontName, spec^.FontSizeLogical,
      spec^.FontWeight, spec^.HasLabelColour, spec^.LabelColour);
  end;
end;

procedure TAdvChartTextStyleOracleTest.CheckTitles(ACase: TJSONObject);
var
  texts: TJSONArray;
  t: TJSONObject;
  i, line: Integer;
  f: TTyTitleFont;
begin
  texts := ACase.Arrays['texts'];
  for i := 0 to texts.Count - 1 do
  begin
    t := texts.Objects[i];
    if t.Strings['component'] = 'title' then line := 0
    else if t.Strings['component'] = 'subtitle' then line := 1
    else Continue;
    Inc(FCompared);
    if FChart.TitleCount = 0 then
    begin
      Miss('no title');
      Continue;
    end;
    f := FChart.TitleFontUsed(0, line);
    CheckFont('title line ' + IntToStr(line), t, f.Name, f.SizeLogical, f.Weight,
      f.HasColour, f.Colour);
  end;
end;

{ legend items and series labels: the drawn captions, matched by their words }
procedure TAdvChartTextStyleOracleTest.CheckCaptions(ACase: TJSONObject;
  const AComponent: string);
var
  texts: TJSONArray;
  t: TJSONObject;
  i, k: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  found: Boolean;
  isLegend: Boolean;
  skin: TTyChartColor;
  stroke: string;
  c: TTyChartColor;
begin
  lst := FChart.List;
  if lst = nil then Exit;
  texts := ACase.Arrays['texts'];
  isLegend := AComponent = 'legend';
  for i := 0 to texts.Count - 1 do
  begin
    t := texts.Objects[i];
    if t.Strings['component'] <> AComponent then Continue;
    found := False;
    for k := 0 to lst.Count - 1 do
    begin
      e := lst.Element(k);
      if (e.Caption.FontSizeLogical <= 0) or (e.Caption.Text <> t.Strings['text']) then
        Continue;
      if isLegend <> (e.Datum.SeriesIndex < 0) then Continue;
      { a series label is its owner's: the same words sit on several }
      if not isLegend and (t.Get('owner', '') <> 'series' + IntToStr(e.Datum.SeriesIndex)) then
        Continue;
      found := True;
      Break;
    end;
    Inc(FCompared);
    if not found then
    begin
      Miss(AComponent + ' "' + t.Strings['text'] + '" not drawn');
      Continue;
    end;
    { a legend's ink: AUTHORED when it is not the skin's legend colour -- so
      a root colour the legend's own default should have shut out shows up
      as a colour upstream kept and the port did not; a series label's ink
      is its mark's business, so only the font is compared there }
    if isLegend then
    begin
      skin := TTyChartColor(FCtl.Model.ResolveStyle('TyAdvChartLegend', '', []).TextColor);
      CheckFont('legend', t, e.Caption.FontName, e.Caption.FontSizeLogical,
        e.Caption.FontWeight, e.Caption.Colour <> skin, e.Caption.Colour);
    end
    else
    begin
      { its fill is the auto ink's, held by earlier batches: the font only }
      CheckFont('label', t, e.Caption.FontName, e.Caption.FontSizeLogical,
        e.Caption.FontWeight, False, 0, False);
      { THE HALO: whether the ground counts as dark decides it }
      if Copy(ACase.Strings['name'], 1, 3) = 'bg-' then
      begin
        stroke := Str(t.Find('stroke'));
        Inc(FCompared);
        if (stroke <> '') <> (e.Caption.StrokeWidthLogical > 0) then
          Miss(Format('label "%s": stroke %s upstream, width %s here', [t.Strings['text'],
            stroke, FloatToStr(e.Caption.StrokeWidthLogical)]))
        else if (stroke <> '') and TyTryParseChartColor(stroke, c)
          and ((c or $FF000000) <> (e.Caption.StrokeColour or $FF000000)) then
          Miss(Format('label "%s": stroke %s upstream, %s here', [t.Strings['text'],
            stroke, IntToHex(e.Caption.StrokeColour, 8)]));
      end;
    end;
  end;
end;

procedure TAdvChartTextStyleOracleTest.Run(AMinimum: Integer);
var
  cases: TJSONArray;
  cs: TJSONObject;
  c, k: Integer;
  skip: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FCase := cs.Strings['name'];
    skip := False;
    for k := 0 to High(cDeferred) do
      if FCase = cDeferred[k] then skip := True;
    if skip then Continue;
    Draw(cs);
    CheckGrid(cs);
    CheckAxes(cs);
    CheckTitles(cs);
    CheckCaptions(cs, 'legend');
    CheckCaptions(cs, 'seriesLabel');
  end;
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]),
    FBad = 0);
  AssertTrue(Format('only %d compared', [FCompared]), FCompared >= AMinimum);
end;

procedure TAdvChartTextStyleOracleTest.TestAuthoredTextAsUpstream;
begin
  Run(2000);
end;

{ '14' and '14px' ARE 14 PX, as zrender's parseFontSize reads them; a size it
  cannot read is no size at all here (upstream draws 12px -- the theme's
  default stands for that). }
procedure TAdvChartTextStyleOracleTest.TestAStringSizeIsPx;
var
  gb: TTyGridBuild;
  spec: PTyAxisLayoutSpec;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"],'
    + '"axisLabel":{"fontSize":"14px"},"nameTextStyle":{"fontSize":"15"},"name":"N"},'
    + '"yAxis":{"type":"value","axisLabel":{"fontSize":"big"}},'
    + '"series":[{"type":"bar","data":[1]}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.XAxis(0));
  AssertEquals('14px', 14.0, TyFontPxOf(spec^.FontSizeLogical), 1e-9);
  AssertEquals('"15"', 15.0, TyFontPxOf(spec^.NameFontSizeLogical), 1e-9);
  spec := gb.SpecFor(gb.YAxis(0));
  AssertFalse('"big" is no size', TyFontSizeIsPx(spec^.FontSizeLogical));
end;

{ WHAT PaintAxis PAINTS IN IS WHAT THE LAYOUT MEASURED: the spec the oracle
  test holds is only half the story unless the paint pass takes its font and
  colour from it rather than from the theme alone. }
procedure TAdvChartTextStyleOracleTest.TestTheAxisIsPaintedInWhatItWasMeasuredIn;
var
  gb: TTyGridBuild;
  spec: PTyAxisLayoutSpec;
  l, p, n: TTyStyleSet;
begin
  FChart.Option := '{"animation":false,"textStyle":{"fontWeight":"bold"},'
    + '"xAxis":{"type":"category","data":["a","b"],"name":"N",'
    + '"axisLabel":{"fontSize":17,"color":"#c23531","fontFamily":"serif"},'
    + '"nameTextStyle":{"fontSize":19,"color":"#123456"}},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1,2]}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.XAxis(0));
  FChart.PaintStyles(spec, l, p, n);
  AssertEquals('label size', 17.0, TyFontPxOf(l.FontSize), 1e-9);
  AssertEquals('label family', 'serif', l.FontName);
  AssertEquals('label weight from the root', 700, l.FontWeight);
  AssertEquals('label colour', Integer(TTyColor($FFC23531)), Integer(l.TextColor));
  AssertEquals('an emphasised label the same size', 17.0, TyFontPxOf(p.FontSize), 1e-9);
  AssertEquals('name size', 19.0, TyFontPxOf(n.FontSize), 1e-9);
  AssertEquals('name colour', Integer(TTyColor($FF123456)), Integer(n.TextColor));
end;

{ A PIXEL SIZE IS DECODED WHERE THE FONT IS SET: 12px is the height 9pt
  gives on the BGRA surface at 96 and 144 DPI and on the measuring canvas at
  96, and 14px, which no whole point holds, is 14. At 144 the canvas' point
  path rounds its size to whole points (13.5 to 14) and the pixel path does
  not: there 12px is exactly half as tall again as at 96. }
procedure TAdvChartTextStyleOracleTest.TestThePainterReadsAPixelSize;
var
  b: TBGRABitmap;
  bm: TBitmap;
  h9, h12, h96: Integer;
  ppi: Integer;
begin
  b := TBGRABitmap.Create(4, 4);
  bm := TBitmap.Create;
  try
    for ppi in [96, 144] do
    begin
      TyConfigureTextFont(b, 'Arial', 9, 400, ppi);
      h9 := b.FontHeight;
      TyConfigureTextFont(b, 'Arial', TyFontSizeFromPx(12), 400, ppi);
      AssertEquals('BGRA 12px = 9pt at ' + IntToStr(ppi), h9, b.FontHeight);
      TyConfigureTextFont(b, 'Arial', TyFontSizeFromPx(14), 400, ppi);
      AssertEquals('BGRA 14px at ' + IntToStr(ppi), Round(14 * ppi / 96), b.FontHeight);
      TyConfigureMeasureFont(bm.Canvas, 'Arial', 9, 400, ppi);
      h9 := bm.Canvas.Font.Height;
      TyConfigureMeasureFont(bm.Canvas, 'Arial', TyFontSizeFromPx(12), 400, ppi);
      h12 := bm.Canvas.Font.Height;
      if ppi = 96 then
      begin
        AssertEquals('canvas 12px = 9pt at 96', h9, h12);
        h96 := h12;
      end
      else
        AssertEquals('canvas 12px at 144 is half again its 96 height',
          Round(h96 * 1.5), h12);
    end;
  finally
    bm.Free;
    b.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartTextStyleOracleTest);
end.
