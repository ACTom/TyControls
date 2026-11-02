unit test.advchart.gaugereads;
{$mode objfpc}{$H+}
{ WHAT A GAUGE READS [R7-D], against tests/fixtures/advchart-gauge-reads.json
  (tools/advchart-oracle/gauge-reads.js, the real ECharts 6.1 dist).

  Its rows: createSeriesDataSimply(this, ['value']) hands no encode and no
  encode defaulter on, so the value is the first dimension whatever `encode`
  says and a dataset row has no name -- a name-first table's reading is the
  name, with no title. A first column upstream calls ordinal keeps its cells
  as written: the reading is the cell, the dial maps `+cell`. Its 'auto'
  colours: the band under the part, the track's colour with no bands written
  (the default list [[1, neutral10]]). The item's own pointer and progress
  keys. min / max / startAngle / endAngle written as numeric strings.

  Per case and series, the port's drawn list against upstream's view: each
  row's reading (the carGaugeDetail element at its index) and the titles
  drawn, each pointer's angle, shape numbers and fill, each progress arc's
  end angle and fill, and the split lines' or ticks' strokes in order. A
  colour equal to the series' default band (`band`) is the track's, which a
  skin decides here: it is compared with the skin's track colour. A case
  with `inks` compares each reading's fill too; one with `at` runs animated
  and compares the readings of the frame at T0 + at (a cell that is a word
  does not count).

  [R7-H] min / max / startAngle / endAngle written as null or a word are NaN
  upstream: a case with `arcs` compares the axis line's bands (one at NaN is
  not drawn), the tick labels drawn (their words, 'NaN' for a NaN extent;
  one at NaN is not drawn), how many split lines and ticks are drawn, and
  the angle each pointer is DRAWN at (zrender reads a NaN rotation as 0).
  A missing cell of a category column is undefined: NaN to the dial. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Gauge, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart;
type
  TGrProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TAdvChartGaugeReadsOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGrProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FCase: string;
    FMisses: TStringList;
    FCompared: Integer;
    FTrack: TTyChartColor;
    FMode: TTyChartAnimationMode;
    FAt: Boolean;
    function Elements: TTyPaintList;
    procedure Miss(const AWhat: string);
    procedure SameColour(const AWhat, AUp, ABand: string; APort: TTyChartColor);
    procedure SameNum(const AWhat: string; AGot: Double; const AHex: string);
    function Find(ARole: TTyChartAnimRole; ASeries, AIndex: Integer;
      out AEl: TTyChartElement): Boolean;
    procedure CheckSeries(S: TJSONObject);
    procedure CheckDial(S: TJSONObject);
    function Bands(ASeries: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGaugesReadAsUpstream;
    procedure TestAHostDivisionByZeroIsStillOne;
  end;

implementation

procedure TGrProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGrProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TGrProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

const
  cT0 = 1700000000000.0;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-gauge-reads.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Result := PDouble(@q)^;
end;

{ '#rrggbbaa' as ARGB }
function ArgbOf(const AText: string; out AColour: TTyChartColor): Boolean;
var r, g, b, a: Integer;
begin
  Result := (Length(AText) = 9) and (AText[1] = '#');
  if not Result then Exit;
  r := StrToInt('$' + Copy(AText, 2, 2));
  g := StrToInt('$' + Copy(AText, 4, 2));
  b := StrToInt('$' + Copy(AText, 6, 2));
  a := StrToInt('$' + Copy(AText, 8, 2));
  AColour := TTyChartColor((Cardinal(a) shl 24) or (Cardinal(r) shl 16)
    or (Cardinal(g) shl 8) or Cardinal(b));
end;

function Str(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := ''
  else Result := AData.AsString;
end;

procedure TAdvChartGaugeReadsOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := TGrProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 400, 300);
  FMode := FChart.AnimationMode;
  { the track's colour: the skin's, the key GaugeVisual reads }
  FTrack := TTyChartColor(FCtl.Model.ResolveStyle('TyAdvChartEmptyCircle', '',
    []).Background.Color);
  FMisses := TStringList.Create;
end;

procedure TAdvChartGaugeReadsOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  FMisses.Free;
  inherited TearDown;
end;

{ the drawn list, or the frame of an animated case }
function TAdvChartGaugeReadsOracleTest.Elements: TTyPaintList;
begin
  if FAt then Result := FChart.Frame else Result := FChart.List;
end;

procedure TAdvChartGaugeReadsOracleTest.Miss(const AWhat: string);
begin
  FMisses.Add(FCase + ': ' + AWhat);
end;

procedure TAdvChartGaugeReadsOracleTest.SameColour(const AWhat, AUp, ABand: string;
  APort: TTyChartColor);
var c: TTyChartColor;
begin
  Inc(FCompared);
  if (ABand <> '') and (AUp = ABand) then
  begin
    if APort <> FTrack then
      Miss(Format('%s: the track''s (%s upstream), %s here, the track %s',
        [AWhat, AUp, IntToHex(APort, 8), IntToHex(FTrack, 8)]));
    Exit;
  end;
  if not ArgbOf(AUp, c) then
  begin
    Miss(Format('%s: %s upstream, not a colour', [AWhat, AUp]));
    Exit;
  end;
  if c <> APort then
    Miss(Format('%s: %s upstream, %s here', [AWhat, AUp, IntToHex(APort, 8)]));
end;

procedure TAdvChartGaugeReadsOracleTest.SameNum(const AWhat: string; AGot: Double;
  const AHex: string);
var w: Double;
begin
  Inc(FCompared);
  w := FromHex(AHex);
  if IsNan(w) <> IsNan(AGot) then
    Miss(Format('%s: %g upstream, %g here', [AWhat, w, AGot]))
  else if not IsNan(w) and (Abs(w - AGot) > 1e-9 * Max(Double(1), Abs(w))) then
    Miss(Format('%s: %.17g upstream, %.17g here', [AWhat, w, AGot]));
end;

function TAdvChartGaugeReadsOracleTest.Find(ARole: TTyChartAnimRole;
  ASeries, AIndex: Integer; out AEl: TTyChartElement): Boolean;
var k: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  if Elements = nil then Exit;
  for k := 0 to Elements.Count - 1 do
    if (Elements.Element(k).Anim.Role = ARole)
      and (Elements.Element(k).Anim.Series = ASeries)
      and (Elements.Element(k).Anim.Index = AIndex) then
    begin
      AEl := Elements.Element(k);
      Exit(True);
    end;
end;

procedure TAdvChartGaugeReadsOracleTest.CheckSeries(S: TJSONObject);
var
  si, k, n: Integer;
  band, up, where: string;
  rows, arr: TJSONArray;
  el: TTyChartElement;
  p: TJSONObject;
  ups, here: TStringList;
  ends, starts: Double;
begin
  si := S.Integers['index'];
  band := Str(S.Find('band'));
  rows := S.Arrays['rows'];
  { the readings, row by row: '' and null draw nothing }
  arr := S.Arrays['details'];
  for k := 0 to rows.Count - 1 do
  begin
    up := Str(arr.Items[k]);
    where := Format('s%d row %d reading', [si, k]);
    Inc(FCompared);
    if not Find(carGaugeDetail, si, k, el) then
    begin
      if up <> '' then Miss(Format('%s "%s" upstream, none here', [where, up]));
    end
    else if up = '' then
      Miss(Format('%s none upstream, "%s" here', [where, el.Caption.Text]))
    else if el.Caption.Text <> up then
      Miss(Format('%s "%s" upstream, "%s" here', [where, up, el.Caption.Text]))
    else if S.Find('inks') is TJSONArray then
      SameColour(where + ' ink', Str(S.Arrays['inks'].Items[k]), band, el.Caption.Colour);
  end;
  { a frame of the count holds the readings only }
  if FAt then Exit;
  { the titles drawn: the series' words that are no reading, as a set }
  ups := TStringList.Create;
  here := TStringList.Create;
  try
    ups.Sorted := True;
    ups.Duplicates := dupAccept;
    here.Sorted := True;
    here.Duplicates := dupAccept;
    arr := S.Arrays['titles'];
    for k := 0 to arr.Count - 1 do
      if Str(arr.Items[k]) <> '' then ups.Add(Str(arr.Items[k]));
    { [R7-H] and the tick labels drawn ('NaN' for a NaN extent; one at NaN
      is not drawn) }
    if S.Find('labels') is TJSONArray then
      for k := 0 to S.Arrays['labels'].Count - 1 do
        if (S.Arrays['labels'].Objects[k].Strings['x'] <> 'NaN')
          and (S.Arrays['labels'].Objects[k].Strings['y'] <> 'NaN') then
          ups.Add(S.Arrays['labels'].Objects[k].Strings['text']);
    if FChart.List <> nil then
      for k := 0 to FChart.List.Count - 1 do
      begin
        el := FChart.List.Element(k);
        if (el.Caption.FontSizeLogical > 0) and (el.Caption.Text <> '')
          and (el.Anim.Role <> carGaugeDetail) then here.Add(el.Caption.Text);
      end;
    Inc(FCompared);
    if ups.Text <> here.Text then
      Miss(Format('s%d titles [%s] upstream, [%s] here', [si,
        StringReplace(Trim(ups.Text), LineEnding, ',', [rfReplaceAll]),
        StringReplace(Trim(here.Text), LineEnding, ',', [rfReplaceAll])]));
  finally
    ups.Free;
    here.Free;
  end;
  { the pointers }
  arr := S.Arrays['pointers'];
  for k := 0 to arr.Count - 1 do
  begin
    where := Format('s%d row %d pointer', [si, k]);
    Inc(FCompared);
    if arr.Items[k].JSONType = jtNull then
    begin
      if Find(carGaugePointer, si, k, el) then Miss(where + ': none upstream');
      Continue;
    end;
    p := TJSONObject(arr.Items[k]);
    if not Find(carGaugePointer, si, k, el) then
    begin
      Miss(where + ': none here');
      Continue;
    end;
    { [R7-H] the angle it is drawn at where the case records it }
    if p.Find('drawn') <> nil then
      SameNum(where + ' drawn angle', el.Anim.G[2], p.Strings['drawn'])
    else
      SameNum(where + ' angle', el.Anim.G[2], p.Strings['angle']);
    SameColour(where + ' fill', Str(p.Find('fill')), band, el.Style.FillColor);
    if p.Find('w') <> nil then
    begin
      SameNum(where + ' width', el.Caption.LgG[0], p.Strings['w']);
      SameNum(where + ' length', el.Caption.LgG[1], p.Strings['r']);
      SameNum(where + ' offset x', el.Caption.LgG[2], p.Strings['x']);
      SameNum(where + ' offset y', el.Caption.LgG[3], p.Strings['y']);
    end;
  end;
  { the progress arcs: one that sweeps nothing, or NaN, is not drawn here }
  arr := S.Arrays['progress'];
  for k := 0 to arr.Count - 1 do
  begin
    where := Format('s%d row %d arc', [si, k]);
    Inc(FCompared);
    if arr.Items[k].JSONType = jtNull then
    begin
      if Find(carGaugeProgress, si, k, el) then Miss(where + ': none upstream');
      Continue;
    end;
    p := TJSONObject(arr.Items[k]);
    starts := FromHex(p.Strings['start']);
    if p.Strings['end'] = 'NaN' then ends := NaN else ends := FromHex(p.Strings['end']);
    if IsNan(ends) or (Abs(ends - starts) <= 1e-9) then
    begin
      if Find(carGaugeProgress, si, k, el) then
        Miss(Format('%s: sweeps nothing upstream (%s), drawn here', [where, p.Strings['end']]));
      Continue;
    end;
    if not Find(carGaugeProgress, si, k, el) then
    begin
      Miss(where + ': none here');
      Continue;
    end;
    SameNum(where + ' end', el.Anim.G[5], p.Strings['end']);
    SameColour(where + ' fill', Str(p.Find('fill')), band, el.Style.FillColor);
  end;
  { the split lines or the ticks, in order }
  arr := S.Arrays['lines'];
  n := 0;
  if FChart.List <> nil then
    for k := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(k);
      if (el.Shape.Kind <> cskPolyline) or (Length(el.Shape.Points) <> 2)
        or el.Style.HasFill or (el.Caption.FontSizeLogical > 0) then Continue;
      if n < arr.Count then
        SameColour(Format('s%d line %d stroke', [si, n]), Str(arr.Items[n]), band,
          el.Style.StrokeColor);
      Inc(n);
    end;
  { [R7-H] a dial with NaN angles makes lines at NaN, none drawn: its count
    is the drawn ones' (CheckDial) }
  Inc(FCompared);
  if (n <> arr.Count) and (S.Find('ticks') = nil) then
    Miss(Format('s%d: %d lines upstream, %d here', [si, arr.Count, n]));
  if S.Find('arcs') is TJSONArray then CheckDial(S);
end;

{ [R7-H] the dial of a case with NaN angles or extents }
procedure TAdvChartGaugeReadsOracleTest.CheckDial(S: TJSONObject);
var
  si, k, n: Integer;
  arr: TJSONArray;
  el: TTyChartElement;
  p: TJSONObject;
begin
  si := S.Integers['index'];
  { the axis line's bands drawn: those at finite angles that sweep }
  arr := S.Arrays['arcs'];
  n := 0;
  for k := 0 to arr.Count - 1 do
  begin
    p := arr.Objects[k];
    if (p.Strings['start'] <> 'NaN') and (p.Strings['end'] <> 'NaN')
      and (Abs(FromHex(p.Strings['end']) - FromHex(p.Strings['start'])) > 1e-9) then Inc(n);
  end;
  Inc(FCompared);
  if n <> Bands(si) then
    Miss(Format('s%d: %d axis line bands drawn upstream, %d here', [si, n, Bands(si)]));
  { the split lines and ticks drawn }
  n := 0;
  if FChart.List <> nil then
    for k := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(k);
      if (el.Shape.Kind = cskPolyline) and (Length(el.Shape.Points) = 2)
        and not el.Style.HasFill and (el.Caption.FontSizeLogical <= 0) then Inc(n);
    end;
  Inc(FCompared);
  if n <> S.Integers['ticks'] then
    Miss(Format('s%d: %d split lines and ticks upstream, %d here', [si, S.Integers['ticks'], n]));
end;

{ the axis line's bands the port drew for series ASeries }
function TAdvChartGaugeReadsOracleTest.Bands(ASeries: Integer): Integer;
var k: Integer;
begin
  Result := 0;
  if FChart.List = nil then Exit;
  for k := 0 to FChart.List.Count - 1 do
    if (FChart.List.Element(k).Shape.Kind = cskSector)
      and (FChart.List.Element(k).Anim.Role <> carGaugeProgress) then Inc(Result);
end;

procedure TAdvChartGaugeReadsOracleTest.TestTheGaugesReadAsUpstream;
var
  cases, series: TJSONArray;
  cs: TJSONObject;
  c, k: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FCase := cs.Strings['name'];
    FAt := cs.Find('at') <> nil;
    { a fresh chart, as upstream's every case: a count enters from nothing }
    FreeAndNil(FChart);
    FChart := TGrProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, 400, 300);
    if FAt then
    begin
      FChart.AnimationMode := camAlways;
      FChart.AnimNow := cT0;
    end
    else
      FChart.AnimationMode := FMode;
    FChart.Option := cs.Objects['option'].AsJSON;
    if FChart.OptionError <> '' then
    begin
      Miss('the option: ' + FChart.OptionError);
      Continue;
    end;
    FBmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
    if FAt then FChart.AnimTick(cT0 + cs.Integers['at']);
    series := cs.Arrays['series'];
    for k := 0 to series.Count - 1 do CheckSeries(series.Objects[k]);
  end;
  if FMisses.Count > 0 then
    Fail(Format('%d of %d differ from upstream:%s%s', [FMisses.Count, FCompared,
      LineEnding, FMisses.Text]));
  AssertTrue(Format('only %d comparisons', [FCompared]), FCompared >= 300);
end;

{ [R7-H] A NaN DIAL AND A LABEL WHOSE WIDTH IS A WORD are laid out with the
  FPU's traps masked; once they are drawn the host's own division by zero
  is reported as that, not as an invalid operation a sticky flag left }
procedure TAdvChartGaugeReadsOracleTest.TestAHostDivisionByZeroIsStillOne;
var
  a, b, c: Double;
  what: string;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[3,4],'
    + '"label":{"show":true,"width":"50%","backgroundColor":"#eeeeee"}},'
    + '{"type":"gauge","startAngle":null,"min":"x","data":[40]}]}';
  AssertEquals('the option', '', FChart.OptionError);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
  a := 1;
  b := 0;
  what := 'nothing';
  try
    c := a / b;
    what := 'no error: ' + FloatToStr(c);
  except
    on E: Exception do what := E.ClassName;
  end;
  AssertEquals('a division by zero', 'EZeroDivide', what);
end;

initialization
  RegisterTest(TAdvChartGaugeReadsOracleTest);
end.
