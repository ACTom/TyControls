unit test.advchart.rootstyles;
{$mode objfpc}{$H+}
{ THE STYLES WRITTEN AT THE OPTION ROOT, held to upstream. [R7-U]

  Every series and component model has the GlobalModel for its parent, and
  getModel builds a child model with the parent's model of the same path
  under it, so a view that reads `itemStyle`, `lineStyle` or `areaStyle`
  through getModel / get(path) climbs to the root's block for every key the
  series (its type's defaults merged in) leaves out or null. The series'
  visual style reads its block with ignoreParent: the root's never reach the
  visual, nor anything that takes it from there.

  tests/fixtures/advchart-root-styles.json, from the real ECharts 6.1 build
  (tools/advchart-oracle/root-styles.js): per case settled, the set of the
  pens of every path under the series' views (part '') or the marker
  components' (part 'marker'), as advchart-series-borders.json records
  them, and -- where the case asks -- the set of their looks (opacity and
  shadow) and their fills, each rect's and sector's shape with its corners,
  and each line's or curve's ends and control point. And `defaults`, the
  leaves each type's defaultOption holds under the three blocks: the port's
  table must be that list.

  TestTheRootStylesAsUpstream: the same off the port's frame -- every
  element of a series that is no text and no label line, or of a marker,
  or (part all: a timeline, a calendar, an axis pointer) every element of
  the chart with its pen's colour left out -- the defaults', which the
  port's skin stands in for. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart.Render, tyControls.AdvanceChart.Diagnose,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TRootStyleProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartRootStylesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FChart: TRootStyleProbe;
    procedure Draw;
    procedure Settle(AStart: Double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRootStylesAsUpstream;
    procedure TestTheDefaultsTableIsTheDist;
    procedure TestTheDiagnosticsKnowTheRootKeys;
  end;

implementation

const
  cW = 400;
  cH = 300;
  T0 = 1700000000000.0;

function TRootStyleProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TRootStyleProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TRootStyleProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
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

procedure TAdvChartRootStylesOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FMeasure := LoadJson('advchart-text-style.json');
end;

procedure TAdvChartRootStylesOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartRootStylesOracleTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartRootStylesOracleTest.Settle(AStart: Double);
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

function NumText(AV: Double): string;
begin
  Result := FloatToStr(AV);
end;

{ String(Math.round(v * 10^ADigits) / 10^ADigits) }
function RoundText(AV: Double; ADigits: Integer): string;
var p: Double;
begin
  p := IntPower(10, ADigits);
  AV := Floor(AV * p + 0.5) / p;
  if AV = 0 then AV := 0;
  Result := FloatToStr(AV);
end;

function ColourText(AC: TTyChartColor): string;
var c: Cardinal;
begin
  c := Cardinal(AC);
  Result := LowerCase(Format('#%.2x%.2x%.2x%.2x', [(c shr 16) and $FF, (c shr 8) and $FF,
    c and $FF, c shr 24]));
end;

function ScaledPen(const AEl: TTyChartElement): Boolean;
begin
  Result := AEl.Anim.Role in [carPictorialGlyph, carPictorialClip];
end;

{ stroke|width|dash|offset|cap/join/miterLimit, as the oracle writes it }
function PenOf(const AEl: TTyChartElement): string;
var
  dash: TTyDoubleArray;
  i: Integer;
  ds: string;
  ps: Double;
begin
  ps := AEl.Style.PenScale;
  if not (ps > 0) then ps := 1;
  if AEl.Style.StrokeGradient.Kind <> cgkNone then Result := 'grad'
  else Result := ColourText(AEl.Style.StrokeColor);
  if (AEl.Style.DashWord <> 0) and ScaledPen(AEl) then
    dash := TyDashOfWord(AEl.Style.DashWord, AEl.Style.StrokeWidthLogical * ps)
  else if AEl.Style.DashWord <> 0 then
    dash := Copy(AEl.Style.DashLogical, 0, Length(AEl.Style.DashLogical))
  else
  begin
    dash := Copy(AEl.Style.DashLogical, 0, Length(AEl.Style.DashLogical));
    for i := 0 to High(dash) do dash[i] := dash[i] * ps;
  end;
  ds := '';
  for i := 0 to High(dash) do
  begin
    if IsNan(dash[i]) or IsInfinite(dash[i]) or (dash[i] < 0) then
    begin
      ds := '';
      Break;
    end;
    if i > 0 then ds := ds + ',';
    if ScaledPen(AEl) then ds := ds + RoundText(dash[i], 4)
    else ds := ds + NumText(dash[i]);
  end;
  if ds = '' then ds := 'solid';
  if ScaledPen(AEl) then
    Result := Result + '|' + RoundText(AEl.Style.StrokeWidthLogical * ps, 4) + '|' + ds + '|'
      + RoundText(AEl.Style.DashOffsetLogical * ps, 4) + '|'
  else
    Result := Result + '|' + NumText(AEl.Style.StrokeWidthLogical) + '|' + ds + '|'
      + NumText(AEl.Style.DashOffsetLogical) + '|';
  case AEl.Style.LineCap of
    1: Result := Result + 'round';
    2: Result := Result + 'square';
  else
    Result := Result + 'butt';
  end;
  case AEl.Style.LineJoin of
    1: Result := Result + '/round';
    2: Result := Result + '/bevel';
  else
    Result := Result + '/miter';
  end;
  if AEl.Style.MiterLimit > 0 then Result := Result + '/' + NumText(AEl.Style.MiterLimit)
  else Result := Result + '/10';
end;

{ opacity|shadowBlur|shadowOffsetX|shadowOffsetY|shadowColor, the colour
  where a shadow is cast }
function LooksOf(const AEl: TTyChartElement): string;
begin
  Result := NumText(AEl.Style.Alpha) + '|' + NumText(AEl.Style.ShadowBlur) + '|'
    + NumText(AEl.Style.ShadowOffsetX) + '|' + NumText(AEl.Style.ShadowOffsetY) + '|';
  if (AEl.Style.ShadowBlur > 0) or (AEl.Style.ShadowOffsetX <> 0) or (AEl.Style.ShadowOffsetY <> 0) then
    Result := Result + ColourText(AEl.Style.ShadowColor);
end;

function CornersText(const AR: TTyCornerRadii): string;
begin
  Result := '';
  if (AR[0] > 0) or (AR[1] > 0) or (AR[2] > 0) or (AR[3] > 0) then
    Result := '|r:' + RoundText(AR[0], 2) + ',' + RoundText(AR[1], 2) + ','
      + RoundText(AR[2], 2) + ',' + RoundText(AR[3], 2);
end;

{ the oracle's type|cx|cy|r0|r|start|sweep[|r:corners], rect|x|y|w|h[|r:..];
  '' every other kind }
function ShapeText(const AEl: TTyChartElement): string;
var a: Double;
begin
  case AEl.Shape.Kind of
    cskSector:
      begin
        if AEl.Shape.Sausage then Result := 'sausage' else Result := 'sector';
        a := AEl.Shape.StartRad - Floor(AEl.Shape.StartRad / (2 * Pi)) * 2 * Pi;
        Result := Result + '|' + RoundText(AEl.Shape.CX, 2) + '|' + RoundText(AEl.Shape.CY, 2) + '|'
          + RoundText(AEl.Shape.R0, 2) + '|' + RoundText(AEl.Shape.R1, 2) + '|' + RoundText(a, 4)
          + '|' + RoundText(Abs(AEl.Shape.EndRad - AEl.Shape.StartRad), 4)
          + CornersText(AEl.Shape.SectorRadii);
      end;
    cskRect:
      Result := 'rect|' + RoundText(AEl.Shape.Bounds.Left, 2) + '|' + RoundText(AEl.Shape.Bounds.Top, 2)
        + '|' + RoundText(AEl.Shape.Bounds.Right - AEl.Shape.Bounds.Left, 2) + '|'
        + RoundText(AEl.Shape.Bounds.Bottom - AEl.Shape.Bounds.Top, 2);
    cskRoundRect:
      Result := 'rect|' + RoundText(AEl.Shape.Bounds.Left, 2) + '|' + RoundText(AEl.Shape.Bounds.Top, 2)
        + '|' + RoundText(AEl.Shape.Bounds.Right - AEl.Shape.Bounds.Left, 2) + '|'
        + RoundText(AEl.Shape.Bounds.Bottom - AEl.Shape.Bounds.Top, 2) + CornersText(AEl.Shape.Radii);
  else
    Result := '';
  end;
end;

{ a line's or a curve's ends and its (first) control point: an edge drawn as
  one quadratic (HitQuad), a path's first curve, a two-point polyline }
function CurveText(const AEl: TTyChartElement): string;
var
  n, k: Integer;
  x0, y0: Double;
begin
  Result := '';
  n := Length(AEl.Shape.Points);
  if AEl.Shape.HitQuad and (n >= 2) then
    Exit(RoundText(AEl.Shape.Points[0].X, 2) + '|' + RoundText(AEl.Shape.Points[0].Y, 2) + '|'
      + RoundText(AEl.Shape.Points[n - 1].X, 2) + '|' + RoundText(AEl.Shape.Points[n - 1].Y, 2) + '|'
      + RoundText(AEl.Shape.HitCP.X, 2) + '|' + RoundText(AEl.Shape.HitCP.Y, 2));
  x0 := 0;
  y0 := 0;
  for k := 0 to High(AEl.Shape.Cmds) do
    case AEl.Shape.Cmds[k].Kind of
      pckMove:
        begin
          x0 := AEl.Shape.Cmds[k].X;
          y0 := AEl.Shape.Cmds[k].Y;
        end;
      pckCurve:
        Exit(RoundText(x0, 2) + '|' + RoundText(y0, 2) + '|' + RoundText(AEl.Shape.Cmds[k].X, 2)
          + '|' + RoundText(AEl.Shape.Cmds[k].Y, 2) + '|' + RoundText(AEl.Shape.Cmds[k].X1, 2)
          + '|' + RoundText(AEl.Shape.Cmds[k].Y1, 2));
    end;
  if (AEl.Shape.Kind = cskPolyline) and (n = 2) then
    Result := RoundText(AEl.Shape.Points[0].X, 2) + '|' + RoundText(AEl.Shape.Points[0].Y, 2) + '|'
      + RoundText(AEl.Shape.Points[1].X, 2) + '|' + RoundText(AEl.Shape.Points[1].Y, 2) + '|-|-';
end;

{ a polygon's points, two places }
function PolyText(const AEl: TTyChartElement): string;
var k: Integer;
begin
  Result := '';
  if AEl.Shape.Kind <> cskPolygon then Exit;
  for k := 0 to High(AEl.Shape.Points) do
  begin
    if k > 0 then Result := Result + ';';
    Result := Result + RoundText(AEl.Shape.Points[k].X, 2) + ',' + RoundText(AEl.Shape.Points[k].Y, 2);
  end;
end;

{ a symbol's box, no pen, two places }
function BoxText(const AEl: TTyChartElement): string;
var b: TTyRectF;
begin
  Result := '';
  if not (AEl.Anim.Role in [carSymbol, carLineSymbol, carPictorialGlyph, carEffectSymbol]) then Exit;
  b := TyShapeBounds(AEl.Shape);
  Result := RoundText(b.Left, 2) + '|' + RoundText(b.Top, 2) + '|' + RoundText(b.Right - b.Left, 2)
    + '|' + RoundText(b.Bottom - b.Top, 2);
end;

function FillText(const AEl: TTyChartElement): string;
var c: Cardinal;
begin
  Result := '';
  if not AEl.Style.HasFill then Exit;
  if AEl.Style.FillGradient.Kind <> cgkNone then Exit('grad');
  c := Cardinal(AEl.Style.FillColor);
  if (c shr 24) = 0 then Exit;
  Result := ColourText(AEl.Style.FillColor);
end;

function NewSet(ADup: TDuplicates): TStringList;
begin
  { the oracle's sort is JS's, by code unit }
  Result := TStringList.Create;
  Result.UseLocale := False;
  Result.CaseSensitive := True;
  Result.Sorted := True;
  Result.Duplicates := ADup;
end;

procedure TAdvChartRootStylesOracleTest.TestTheRootStylesAsUpstream;
var
  fix: TJSONData;
  cs, pens: TJSONArray;
  c: TJSONObject;
  i, k, nBad, nCases, nMarker: Integer;
  lst: TTyPaintList;
  el: TTyChartElement;
  got, shapes, fills, looks, curves, polys, boxes: TStringList;
  want, have, id, bad, part, s: string;
  arr: TJSONArray;
  isMarker: Boolean;

  function SetText(AList: TStringList): string;
  var j: Integer;
  begin
    Result := '';
    for j := 0 to AList.Count - 1 do Result := Result + ' ' + AList[j];
  end;

  function ArrText(AArr: TJSONArray; ASkipClear: Boolean): string;
  var j: Integer;
  begin
    Result := '';
    for j := 0 to AArr.Count - 1 do
      if not (ASkipClear and (Copy(AArr.Strings[j], 8, 2) = '00')) then
        Result := Result + ' ' + AArr.Strings[j];
  end;

  procedure Compare(const AKey: string; AHere: TStringList; ASkipClear: Boolean);
  begin
    arr := c.Find(AKey) as TJSONArray;
    if arr = nil then Exit;
    want := want + ' ' + AKey + ArrText(arr, ASkipClear);
    have := have + ' ' + AKey + SetText(AHere);
  end;

begin
  fix := LoadJson('advchart-root-styles.json');
  got := NewSet(dupIgnore);
  shapes := NewSet(dupAccept);
  fills := NewSet(dupIgnore);
  looks := NewSet(dupIgnore);
  curves := NewSet(dupAccept);
  polys := NewSet(dupAccept);
  boxes := NewSet(dupAccept);
  nBad := 0;
  nCases := 0;
  nMarker := 0;
  bad := '';
  try
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      part := c.Strings['part'];
      FreeAndNil(FChart);
      FChart := TRootStyleProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
        TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
        TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
      FChart.AnimationMode := camAlways;
      FChart.AnimNow := T0;
      FChart.SetBounds(0, 0, cW, cH);
      FChart.Option := c.Objects['option'].AsJSON;
      AssertEquals(id + ' parses', '', FChart.OptionError);
      Draw;
      Settle(T0);
      lst := FChart.Frame;
      got.Clear;
      shapes.Clear;
      fills.Clear;
      looks.Clear;
      curves.Clear;
      polys.Clear;
      boxes.Clear;
      for k := 0 to lst.Count - 1 do
      begin
        el := lst.Element(k);
        if GetEnvironmentVariable('TY_ROOTSTYLE_DUMP') = id then
          WriteLn(id + ' el ' + IntToStr(k) + ' role ' + IntToStr(Ord(el.Anim.Role)) + ' kind '
            + IntToStr(Ord(el.Datum.Kind)) + ' s ' + IntToStr(el.Datum.SeriesIndex) + ' i '
            + IntToStr(el.Datum.DataIndex) + ' shape ' + IntToStr(Ord(el.Shape.Kind)) + ' ign '
            + BoolToStr(el.Ignore, True) + ' pen ' + PenOf(el) + ' fill ' + FillText(el)
            + ' looks ' + LooksOf(el) + ' text "' + el.Caption.Text + '"');
        if el.Ignore or el.IsGuide or (el.Anim.Role in [carLabel, carMarkLineLabel,
          carMarkPointLabel, carEndLabel, carLinesLabel, carGraphEdgeLabel]) then Continue;
        { words: a host carries its label's text, the words are their own element }
        if el.Caption.FontSizeLogical > 0 then Continue;
        isMarker := el.Datum.Kind in [ctkMarkPoint, ctkMarkLine, ctkMarkArea];
        if part = 'all' then
          { every path of the chart }
        else if part = 'marker' then
        begin
          if not isMarker then Continue;
        end
        else if not (((el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex >= 0))
          or ((el.Anim.UtTag = 1) and (el.Anim.Series >= 0))) then Continue;
        looks.Add(LooksOf(el));
        s := ShapeText(el);
        if s <> '' then shapes.Add(s);
        s := CurveText(el);
        if s <> '' then curves.Add(s);
        s := PolyText(el);
        if s <> '' then polys.Add(s);
        s := BoxText(el);
        if s <> '' then boxes.Add(s);
        s := FillText(el);
        if s <> '' then fills.Add(s);
        if not (el.Style.StrokeWidthLogical > 0) then Continue;
        if ((el.Style.StrokeColor shr 24) = 0) and (el.Style.StrokeGradient.Kind = cgkNone) then Continue;
        { part all: the pen without its colour (the theme's) }
        if part = 'all' then
        begin
          s := PenOf(el);
          got.Add(Copy(s, Pos('|', s) + 1, MaxInt));
        end
        else
          got.Add(PenOf(el));
      end;
      pens := c.Arrays['pens'];
      want := '';
      for k := 0 to pens.Count - 1 do
        if Copy(pens.Strings[k], 1, 2) <> 'x:' then
          want := want + ' ' + StringReplace(pens.Strings[k], '|ignored|', '|solid|', []);
      have := SetText(got);
      Inc(nCases);
      if part = 'marker' then Inc(nMarker);
      Compare('shapes', shapes, False);
      Compare('fills', fills, True);
      Compare('looks', looks, False);
      Compare('curves', curves, False);
      Compare('polys', polys, False);
      Compare('boxes', boxes, False);
      if have <> want then
      begin
        Inc(nBad);
        bad := bad + LineEnding + Format('  %s: %s here, upstream %s', [id, Trim(have),
          Trim(want)]);
      end;
    end;
  finally
    got.Free;
    shapes.Free;
    fills.Free;
    looks.Free;
    curves.Free;
    polys.Free;
    boxes.Free;
    fix.Free;
  end;
  AssertTrue('cases', nCases >= 40);
  AssertTrue('marker cases', nMarker >= 2);
  AssertTrue(Format('%d of %d differ from upstream:%s', [nBad, nCases, bad]), nBad = 0);
end;

{ the port's table of the type defaults under the root's style blocks is the
  dist's }
procedure TAdvChartRootStylesOracleTest.TestTheDefaultsTableIsTheDist;
var
  fix: TJSONData;
  arr: TJSONArray;
  mine: TTyStringArray;
  want, have: TStringList;
  i: Integer;
begin
  fix := LoadJson('advchart-root-styles.json');
  want := NewSet(dupAccept);
  have := NewSet(dupAccept);
  try
    arr := TJSONObject(fix).Arrays['defaults'];
    for i := 0 to arr.Count - 1 do want.Add(arr.Strings[i]);
    mine := TyRootStyleDefaultPaths;
    for i := 0 to High(mine) do have.Add(mine[i]);
    AssertEquals('the defaults under the root''s style blocks', want.Text, have.Text);
  finally
    want.Free;
    have.Free;
    fix.Free;
  end;
end;

{ none of the root's keys the models read is an unknown option to the
  diagnostics }
procedure TAdvChartRootStylesOracleTest.TestTheDiagnosticsKnowTheRootKeys;
const
  cKeys: array[0..7] of string = ('itemStyle', 'lineStyle', 'areaStyle', 'symbolSize',
    'roseType', 'center', 'min', 'max');
var
  fix: TJSONData;
  cs: TJSONArray;
  opt: TJSONObject;
  diags: TTyOptDiagArray;
  i, k, j, n: Integer;
  bad: string;
begin
  fix := LoadJson('advchart-root-styles.json');
  n := 0;
  bad := '';
  try
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      opt := cs.Objects[i].Objects['option'];
      diags := TyOptDiagnose(opt.AsJSON);
      for k := 0 to High(cKeys) do
      begin
        if opt.Find(cKeys[k]) = nil then Continue;
        Inc(n);
        for j := 0 to High(diags) do
          if (diags[j].Kind = odkUnknownOption) and (diags[j].Path = cKeys[k]) then
            bad := bad + ' ' + cs.Objects[i].Strings['id'] + ':' + cKeys[k];
      end;
    end;
  finally
    fix.Free;
  end;
  AssertTrue('root keys looked at', n >= 60);
  AssertEquals('the root keys reported unknown', '', bad);
end;

initialization
  RegisterTest(TAdvChartRootStylesOracleTest);
end.
