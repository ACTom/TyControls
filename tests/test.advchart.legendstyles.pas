unit test.advchart.legendstyles;
{$mode objfpc}{$H+}
{ THE STYLE OF A LEGEND ICON'S PATHS, held to ECharts 6.1. [R7-T, spec 274]

  tools/advchart-oracle/legend-styles.js runs the real dist: line series'
  own icons (the rule styled by the legend's lineStyle over the series'
  legendLineStyle visual, the marker by the legend's itemStyle over the
  style visual), the default icon of bars, scatters and pies, selected and
  not, with the legend's and the items' own lineStyle / itemStyle written,
  'inherit' and 'auto' included. For each item: its group's hit rect and
  each icon path's place and style as the canvas takes it.

  The control renders each option; legend 0's items are compared path by
  path, the paths that paint nothing (no fill, or a line's degenerate
  fill, and no pen) left out on both sides. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StyleModel, tyControls.FontUnits,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart.Legend,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLstProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartLegendStylesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLstProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FItems, FPaths: Integer;
    FReport, FName: string;
    { the skin's disabled ink, which upstream's disabled token (#cfd2d7) is here }
    FInactive: TTyChartColor;
    function UpColour(const AText: string; out AColour: TTyChartColor): Boolean;
    procedure NewChart;
    procedure Miss(const AWhat: string);
    procedure Near(const AWhat: string; AGot: Double; const AHex: string);
    procedure CheckPath(AIndex: Integer; const AEl: TTyChartElement; P: TJSONObject);
    procedure CheckCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLegendIconStylesAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TLstProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLstProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLstProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function HexOr(P: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  d := P.Find(AKey);
  if (d = nil) or (d.JSONType <> jtString) then Exit(ADefault);
  Result := FromHex(d.AsString);
end;

function StrOr(P: TJSONObject; const AKey, ADefault: string): string;
var d: TJSONData;
begin
  d := P.Find(AKey);
  if (d = nil) or (d.JSONType <> jtString) then Exit(ADefault);
  Result := d.AsString;
end;

{ what the canvas takes: a fill paints where it is a colour and the path
  has an area (a 'line' symbol's has none); a pen where it is a colour and
  the width is above nought }
function UpFills(P: TJSONObject): Boolean;
begin
  Result := (StrOr(P, 'fill', 'none') <> 'none') and (StrOr(P, 'symbolType', '') <> 'line');
end;

function UpStrokes(P: TJSONObject): Boolean;
begin
  Result := (StrOr(P, 'stroke', 'none') <> 'none') and (HexOr(P, 'lineWidth', 1) > 0);
end;

function PortFills(const AEl: TTyChartElement): Boolean;
begin
  Result := AEl.Style.HasFill;
end;

function PortStrokes(const AEl: TTyChartElement): Boolean;
begin
  Result := (AEl.Style.StrokeWidthLogical > 0)
    and (((LongWord(AEl.Style.StrokeColor) shr 24) <> 0)
      or (AEl.Style.StrokeGradient.Kind <> cgkNone));
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-legend-styles.json';
end;

procedure TAdvChartLegendStylesOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FInactive := TTyChartColor(FCtl.Model.ResolveStyle('TyAdvChartLegendInactive', '', []).TextColor);
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FItems := 0;
  FPaths := 0;
  FReport := '';
end;

procedure TAdvChartLegendStylesOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TLstProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartLegendStylesOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartLegendStylesOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 400 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

function TAdvChartLegendStylesOracleTest.UpColour(const AText: string;
  out AColour: TTyChartColor): Boolean;
begin
  if LowerCase(AText) = '#cfd2d7' then
  begin
    AColour := FInactive;
    Exit(True);
  end;
  Result := TyTryParseChartColor(AText, AColour);
end;

procedure TAdvChartLegendStylesOracleTest.Near(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameValue(AGot, FromHex(AHex), 1e-9) then
    Miss(Format('%s %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartLegendStylesOracleTest.CheckPath(AIndex: Integer;
  const AEl: TTyChartElement; P: TJSONObject);
var
  c: TTyChartColor;
  up, here: Double;
  dash: TJSONArray;
  r: TJSONArray;
  b: TTyRectF;
  j, capUp, joinUp: Integer;
  s, what: string;
  upShadow, hereShadow: Boolean;
begin
  Inc(FPaths);
  what := Format('path %d ', [AIndex]);
  { the fill }
  Inc(FCompared);
  if UpFills(P) <> PortFills(AEl) then
    Miss(Format('%sfills %s upstream, %s here', [what, BoolToStr(UpFills(P), True),
      BoolToStr(PortFills(AEl), True)]))
  else if UpFills(P) and UpColour(StrOr(P, 'fill', ''), c) then
  begin
    Inc(FCompared);
    if (c <> AEl.Style.FillColor) and (AEl.Style.FillGradient.Kind = cgkNone) then
      Miss(Format('%sfill %s upstream, $%.8x here', [what, StrOr(P, 'fill', ''), AEl.Style.FillColor]));
  end;
  { the pen }
  Inc(FCompared);
  if UpStrokes(P) <> PortStrokes(AEl) then
  begin
    Miss(Format('%sstrokes %s upstream (%s at %s), %s here (at %s)', [what,
      BoolToStr(UpStrokes(P), True), StrOr(P, 'stroke', 'none'),
      Fmt(HexOr(P, 'lineWidth', 1)), BoolToStr(PortStrokes(AEl), True),
      Fmt(AEl.Style.StrokeWidthLogical)]));
  end
  else if UpStrokes(P) then
  begin
    s := StrOr(P, 'stroke', '');
    Inc(FCompared);
    if s = '#object' then
    begin
      if AEl.Style.StrokeGradient.Kind = cgkNone then
        Miss(what + 'a gradient pen upstream, none here');
    end
    else if UpColour(s, c) and (c <> AEl.Style.StrokeColor) then
      Miss(Format('%sstroke %s upstream, $%.8x here', [what, s, AEl.Style.StrokeColor]));
    Near(what + 'lineWidth', AEl.Style.StrokeWidthLogical, StrOr(P, 'lineWidth', ''));
    { the dash, as dashStyle normalised it }
    dash := nil;
    if (P.Find('dash') <> nil) and (P.Find('dash').JSONType = jtArray) then
      dash := P.Arrays['dash'];
    Inc(FCompared);
    if (dash = nil) <> (Length(AEl.Style.DashLogical) = 0) then
      Miss(Format('%sdashed %s upstream, %s here', [what, BoolToStr(dash <> nil, True),
        BoolToStr(Length(AEl.Style.DashLogical) > 0, True)]))
    else if dash <> nil then
    begin
      Inc(FCompared);
      if dash.Count <> Length(AEl.Style.DashLogical) then
        Miss(Format('%s%d dash lengths upstream, %d here', [what, dash.Count, Length(AEl.Style.DashLogical)]))
      else
        for j := 0 to dash.Count - 1 do
          Near(Format('%sdash[%d]', [what, j]), AEl.Style.DashLogical[j], dash.Strings[j]);
      up := HexOr(P, 'dashOffset', 0);
      Inc(FCompared);
      if not SameValue(up, AEl.Style.DashOffsetLogical, 1e-9) then
        Miss(Format('%sdashOffset %s upstream, %s here', [what, Fmt(up), Fmt(AEl.Style.DashOffsetLogical)]));
    end;
    { cap, join, miter }
    s := StrOr(P, 'cap', 'butt');
    if s = 'round' then capUp := 1 else if s = 'square' then capUp := 2 else capUp := 0;
    s := StrOr(P, 'join', 'miter');
    if s = 'round' then joinUp := 1 else if s = 'bevel' then joinUp := 2 else joinUp := 0;
    Inc(FCompared, 2);
    if capUp <> AEl.Style.LineCap then
      Miss(Format('%scap %d upstream, %d here', [what, capUp, AEl.Style.LineCap]));
    if joinUp <> AEl.Style.LineJoin then
      Miss(Format('%sjoin %d upstream, %d here', [what, joinUp, AEl.Style.LineJoin]));
    up := HexOr(P, 'miter', 10);
    here := AEl.Style.MiterLimit;
    if here <= 0 then here := 10;
    Inc(FCompared);
    if not SameValue(up, here, 1e-9) then
      Miss(Format('%smiterLimit %s upstream, %s here', [what, Fmt(up), Fmt(here)]));
  end;
  { the opacity: one the canvas does not take (no finite number) is its 1 }
  up := HexOr(P, 'opacity', 1);
  if IsNan(up) or IsInfinite(up) then up := 1;
  Inc(FCompared);
  if not SameValue(up, AEl.Style.Alpha, 1e-9) then
    Miss(Format('%sopacity %s upstream, %s here', [what, Fmt(up), Fmt(AEl.Style.Alpha)]));
  { the shadow: one where a blur or an offset is above nought }
  upShadow := (HexOr(P, 'shadowBlur', 0) > 0) or (HexOr(P, 'shadowOffsetX', 0) <> 0)
    or (HexOr(P, 'shadowOffsetY', 0) <> 0);
  hereShadow := (AEl.Style.ShadowBlur > 0) or (AEl.Style.ShadowOffsetX <> 0)
    or (AEl.Style.ShadowOffsetY <> 0);
  Inc(FCompared);
  if upShadow <> hereShadow then
    Miss(Format('%sshadow %s upstream, %s here', [what, BoolToStr(upShadow, True),
      BoolToStr(hereShadow, True)]))
  else if upShadow then
  begin
    Near(what + 'shadowBlur', AEl.Style.ShadowBlur, StrOr(P, 'shadowBlur', '0000000000000000'));
    Near(what + 'shadowOffsetX', AEl.Style.ShadowOffsetX, StrOr(P, 'shadowOffsetX', '0000000000000000'));
    Near(what + 'shadowOffsetY', AEl.Style.ShadowOffsetY, StrOr(P, 'shadowOffsetY', '0000000000000000'));
    Inc(FCompared);
    if TyTryParseChartColor(StrOr(P, 'shadowColor', '#000'), c) and (c <> AEl.Style.ShadowColor) then
      Miss(Format('%sshadowColor %s upstream, $%.8x here', [what, StrOr(P, 'shadowColor', '#000'),
        AEl.Style.ShadowColor]));
  end;
  { where: the shape's centre, and its size without the pen (upstream's
    rect is grown by the whole width where it strokes) }
  r := P.Arrays['rect'];
  b := TyShapeBounds(AEl.Shape);
  up := FromHex(r.Strings[0]) + FromHex(r.Strings[2]) / 2;
  Inc(FCompared, 4);
  if not SameValue((b.Left + b.Right) / 2, up, 1e-6) then
    Miss(Format('%scentre x %s upstream, %s here', [what, Fmt(up), Fmt((b.Left + b.Right) / 2)]));
  up := FromHex(r.Strings[1]) + FromHex(r.Strings[3]) / 2;
  if not SameValue((b.Top + b.Bottom) / 2, up, 1e-6) then
    Miss(Format('%scentre y %s upstream, %s here', [what, Fmt(up), Fmt((b.Top + b.Bottom) / 2)]));
  if StrOr(P, 'stroke', 'none') <> 'none' then here := HexOr(P, 'lineWidth', 1) else here := 0;
  if here < 0 then here := 0;
  up := FromHex(r.Strings[2]) - here;
  if not SameValue(b.Right - b.Left, up, 1e-6) then
    Miss(Format('%swidth %s upstream, %s here', [what, Fmt(up), Fmt(b.Right - b.Left)]));
  up := FromHex(r.Strings[3]) - here;
  if not SameValue(b.Bottom - b.Top, up, 1e-6) then
    Miss(Format('%sheight %s upstream, %s here', [what, Fmt(up), Fmt(b.Bottom - b.Top)]));
end;

procedure TAdvChartLegendStylesOracleTest.CheckCase(ACase: TJSONObject);
var
  items, paths, hit, acts: TJSONArray;
  it: TJSONObject;
  i, k, idx, first, last, n, m: Integer;
  lay: TTyLegendLayout;
  l: TTyPaintList;
  pe: PTyChartElement;
  b: TTyRectF;
  ups: array of TJSONObject;
  heres: array of Integer;
begin
  NewChart;
  FChart.Option := ACase.Objects['option'].AsJSON;
  AssertEquals(ACase.Strings['id'] + ': the option parses', '', FChart.OptionError);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  if ACase.Find('actions') <> nil then
  begin
    acts := ACase.Arrays['actions'];
    for k := 0 to acts.Count - 1 do
    begin
      AssertTrue(ACase.Strings['id'] + ': the action is taken',
        FChart.DispatchAction(acts.Objects[k].AsJSON));
      FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
    end;
  end;
  lay := FChart.LegendLayout(0);
  l := FChart.List;
  items := ACase.Arrays['items'];
  for i := 0 to items.Count - 1 do
  begin
    it := items.Objects[i];
    FName := Format('%s %s', [ACase.Strings['id'], it.Strings['name']]);
    idx := -1;
    for k := 0 to High(lay.Items) do
      if lay.Items[k].Name = it.Strings['name'] then idx := k;
    Inc(FCompared);
    if idx < 0 then
    begin
      Miss('no such item');
      Continue;
    end;
    Inc(FItems);
    hit := it.Arrays['hit'];
    b := lay.Items[idx].Bounds;
    Near('hit x', b.Left, hit.Strings[0]);
    Near('hit y', b.Top, hit.Strings[1]);
    Near('hit w', b.Right - b.Left, hit.Strings[2]);
    Near('hit h', b.Bottom - b.Top, hit.Strings[3]);
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
    Inc(FCompared);
    if first < 0 then
    begin
      Miss('no hit rect');
      Continue;
    end;
    { the paths that paint, both sides }
    ups := nil;
    paths := it.Arrays['paths'];
    for k := 0 to paths.Count - 1 do
      if UpFills(paths.Objects[k]) or UpStrokes(paths.Objects[k]) then
      begin
        n := Length(ups);
        SetLength(ups, n + 1);
        ups[n] := paths.Objects[k];
      end;
    heres := nil;
    for k := first to last do
    begin
      pe := l.Ref(k);
      if (pe^.Caption.Text <> '') or (pe^.Caption.FontSizeLogical <> 0) then Continue;
      if not (PortFills(pe^) or PortStrokes(pe^)) then Continue;
      m := Length(heres);
      SetLength(heres, m + 1);
      heres[m] := k;
    end;
    Inc(FCompared);
    if Length(ups) <> Length(heres) then
    begin
      Miss(Format('%d painted paths upstream, %d here', [Length(ups), Length(heres)]));
      Continue;
    end;
    for k := 0 to High(ups) do
      CheckPath(k, l.Ref(heres[k])^, ups[k]);
  end;
end;

procedure TAdvChartLegendStylesOracleTest.TestTheLegendIconStylesAsUpstream;
var
  cases: TJSONArray;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
    CheckCase(cases.Objects[c]);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('items compared (%d)', [FItems]), FItems >= 60);
  AssertTrue(Format('paths compared (%d)', [FPaths]), FPaths >= 80);
end;

initialization
  RegisterTest(TAdvChartLegendStylesOracleTest);
end.
