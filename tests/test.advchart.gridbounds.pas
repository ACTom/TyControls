unit test.advchart.gridbounds;
{$mode objfpc}{$H+}
{ Where a grid's plot ends up once its labels have been measured -- held to
  upstream's own rects.

  tools/advchart-oracle/grid-bounds.js runs the real ECharts 6.1 build and
  records, per case, the grid's raw rect, the outer bounds, the clamp, every
  label box the estimate laid out on the raw rect (with the proportion the
  shrink divides by), the margin and the final rect.

  THE TEXT IS MEASURED THE SAME WAY ON BOTH SIDES. In node, zrender has no
  canvas and measures with a fixed table: each printable ASCII character is a
  set fraction of the font size, anything else the whole size, a line the
  font size tall. TZrSsrMeasurer is that table -- its ratios read from the
  fixture as bits, never retyped -- and it is checked against zrender's own
  widths, bit for bit, before anything else is.

  THREE LEVELS:
  1. the measurer itself, bitwise;
  2. the shrink, bitwise: upstream's own label boxes and proportions fed to
     TyOuterBoundsMargin and TyShrinkRect must give upstream's margin and
     rect to the last bit;
  3. the whole pipeline -- options read, labels formatted, thinned, placed,
     turned, padded, shrunk -- bitwise too.
     [Batch 51: this used to be within the case's tolerance, "zrender's
     matrices round differently". Two causes, both gone: the label matrix is
     now decomposed and recomposed as zrender does, and the rect is read as
     x, y, width, height -- `Right - Left` is not the width it was built
     from (118.16 + 421.84 - 118.16 = 421.84000000000003).] }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.FontUnits,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
     tyControls.AdvChart.Layout;
type
  { zrender's measureText with no canvas (platform.ts): a table of widths. }
  TZrSsrMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  private
    FRatio: array[32..126] of Double;
  public
    constructor Create(ARatios: TJSONArray; AFirst: Integer);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartGridBoundsOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FM: ITyTextMeasurer;
    FOpt: TTyChartOption;
    FBuild: TTyChartBuild;
    FStores: array of TTyDataStore;
    FIndex: TTyAxisSeriesIndex;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure FreeRun;
    procedure RunCase(ACase: TJSONObject);
  published
    procedure TestTheMeasurerIsZrendersToTheBit;
    procedure TestTheShrinkIsUpstreamsToTheBit;
    procedure TestEveryGridAsUpstreamSolvesIt;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-grid-bounds.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Num(AObj: TJSONObject; const AKey: string): Double;
begin
  Result := FromHex(AObj.Strings[AKey]);
end;

function XYWHOf(AObj: TJSONObject): TTyXYWH;
begin
  Result := TyXYWH(Num(AObj, 'x'), Num(AObj, 'y'), Num(AObj, 'width'),
    Num(AObj, 'height'));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function IsDeferred(ACase: TJSONObject): Boolean;
begin
  Result := (ACase.Find('deferred') <> nil) and ACase.Booleans['deferred'];
end;

{ ==================== the measurer ==================== }

constructor TZrSsrMeasurer.Create(ARatios: TJSONArray; AFirst: Integer);
var i: Integer;
begin
  inherited Create;
  for i := Low(FRatio) to High(FRatio) do FRatio[i] := NaN;
  for i := 0 to ARatios.Count - 1 do
    if (AFirst + i >= Low(FRatio)) and (AFirst + i <= High(FRatio)) then
      FRatio[AFirst + i] := FromHex(ARatios.Strings[i]);
end;

procedure TZrSsrMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var
  px, w: Double;
  i, lines, cp, len: Integer;
  b: Byte;
begin
  { the size in px -- an author's size arrives encoded as px, the rest as a
    number this measurer has always read as px; the family, weight and style
    count for nothing }
  if TyFontSizeIsPx(AFontSizeLogical) then px := TyFontPxOf(AFontSizeLogical)
  else px := AFontSizeLogical;
  AW := 0;
  w := 0;
  lines := 1;
  i := 1;
  while i <= Length(AText) do
  begin
    b := Ord(AText[i]);
    if b = 10 then
    begin
      if w > AW then AW := w;
      w := 0;
      Inc(lines);
      Inc(i);
      Continue;
    end;
    { one UTF-8 code point, counted as JavaScript counts it: in UTF-16 units }
    if b < $80 then begin cp := b; len := 1; end
    else if b < $E0 then begin cp := b and $1F; len := 2; end
    else if b < $F0 then begin cp := b and $0F; len := 3; end
    else begin cp := b and $07; len := 4; end;
    Inc(i, len);
    { a font whose string says 'mono' is a whole size per unit, whatever the
      character (platform.ts) }
    if (cp >= Low(FRatio)) and (cp <= High(FRatio)) and (len = 1)
      and (Pos('mono', AFontName) = 0) then
      w := w + FRatio[cp] * px
    else
    begin
      w := w + px;
      { past the basic plane a character is two units, each a whole size }
      if len = 4 then w := w + px;
    end;
  end;
  if w > AW then AW := w;
  AH := px * lines;
end;

function TZrSsrMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

{ ==================== plumbing ==================== }

procedure TAdvChartGridBoundsOracleTest.SetUp;
var
  sl: TStringList;
  ratios: TJSONObject;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  ratios := TJSONObject(FRoot).Objects['ratios'];
  FM := TZrSsrMeasurer.Create(ratios.Arrays['ratio'], ratios.Integers['firstCode']);
  FOpt := TTyChartOption.Create;
  FIndex := TTyAxisSeriesIndex.Create;
end;

procedure TAdvChartGridBoundsOracleTest.FreeRun;
var i: Integer;
begin
  { a store borrows its axis' categories: the stores go before the build }
  for i := 0 to High(FStores) do FStores[i].Free;
  FStores := nil;
  FreeAndNil(FBuild);
end;

procedure TAdvChartGridBoundsOracleTest.TearDown;
begin
  FreeRun;
  FreeAndNil(FIndex);
  FreeAndNil(FOpt);
  FM := nil;
  FreeAndNil(FRoot);
  inherited TearDown;
end;

function TestTextStyle: TTyAxisTextStyle;
begin
  Result := Default(TTyAxisTextStyle);
  Result.FontName := 'sans-serif';
  { upstream's axis label: 12px, margin 8, tick 5; the name gap its 15 }
  Result.FontSizeLogical := 12;
  Result.FontWeight := 400;
  Result.LabelMarginLogical := 8;
  Result.TickLengthLogical := 5;
  Result.NameGapLogical := 15;
  { and its name, in the same }
  Result.NameFontName := 'sans-serif';
  Result.NameFontSizeLogical := 12;
  Result.NameFontWeight := 400;
end;

procedure TAdvChartGridBoundsOracleTest.RunCase(ACase: TJSONObject);
var
  bind: TTySeriesBindingArray;
  dims: TTySeriesDimArray;
  i, k: Integer;
  st: TTyDataStore;
begin
  FreeRun;
  AssertTrue(ACase.Strings['name'] + ' parses',
    FOpt.SetOptionText(ACase.Objects['option'].AsJSON));
  FBuild := TyBuildGrids(FOpt, TyRectF(0, 0, ACase.Integers['W'],
    ACase.Integers['H']));
  bind := TyBindSeries(FOpt, FBuild);
  SetLength(FStores, Length(bind));
  for i := 0 to High(bind) do
  begin
    st := TTyDataStore.Create;
    FStores[i] := st;
    if not bind[i].HasAxes then Continue;
    dims := TySeriesCartesianDims(bind[i].Cart, 0);
    for k := 0 to High(dims) do
    begin
      st.AddDimension(dims[k].Name, dims[k].Kind);
      if dims[k].Axis <> nil then st.UseOrdinalMeta(k, dims[k].Axis.Categories);
    end;
    TyFillSeriesStore(FOpt, i, dims, st);
  end;
  FIndex.Clear;
  TyIndexSeries(bind, FIndex);
  TyApplyAxisExtents(FOpt, FBuild, bind, FStores, nil, FIndex);
  TyLayoutGrids(FBuild, FOpt, FM, 96, TestTextStyle);
end;

{ ==================== 1. the measurer ==================== }

procedure TAdvChartGridBoundsOracleTest.TestTheMeasurerIsZrendersToTheBit;
var
  list: TJSONArray;
  m: TJSONObject;
  i, bad: Integer;
  w, h: Double;
  report: string;
begin
  list := TJSONObject(FRoot).Arrays['measure'];
  bad := 0;
  report := '';
  for i := 0 to list.Count - 1 do
  begin
    m := list.Objects[i];
    FM.MeasureLine(m.Strings['text'], 'sans-serif', m.Integers['px'], 400, w, h);
    if (w <> Num(m, 'width')) or (h <> Num(m, 'height')) then
    begin
      Inc(bad);
      report := report + LineEnding + Format('  %s @%d: %s x %s upstream, %s x %s here',
        [m.Strings['text'], m.Integers['px'], m.Strings['widthText'],
         m.Strings['heightText'], Fmt(w), Fmt(h)]);
    end;
  end;
  AssertTrue('enough strings', list.Count >= 40);
  AssertEquals(IntToStr(bad) + ' widths differ:' + report, 0, bad);
end;

{ ==================== 2. the shrink ==================== }

procedure TAdvChartGridBoundsOracleTest.TestTheShrinkIsUpstreamsToTheBit;
var
  cases, axes, labels: TJSONArray;
  cs, ax, lb: TJSONObject;
  c, a, l, n, bad, compared: Integer;
  items: TTyBoundsItemArray;
  m, want: TTyMargin4;
  r, w: TTyXYWH;
  mt: TJSONArray;
  report: string;
  d: TJSONData;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  compared := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if IsDeferred(cs) then Continue;
    if not (cs.Find('margin') is TJSONArray) then Continue;
    { UPSTREAM'S OWN BOXES, fed to the port's arithmetic }
    items := nil;
    n := 0;
    axes := cs.Arrays['estimate'];
    for a := 0 to axes.Count - 1 do
    begin
      ax := axes.Objects[a];
      labels := ax.Arrays['labels'];
      for l := 0 to labels.Count - 1 do
      begin
        lb := labels.Objects[l];
        SetLength(items, n + 1);
        items[n].R := XYWHOf(lb.Objects['rect']);
        items[n].AlongY := ax.Strings['dim'] = 'y';
        items[n].Proportion := Num(lb, 'p');
        Inc(n);
      end;
      { A NAME COUNTS UNDER 'all' ONLY -- the fixture records it whatever
        the grid contains.
        [Revised in batch 38: every recorded name was added, which the name
        cases, deferred until then, never showed.] }
      d := ax.Find('nameRect');
      if (d is TJSONObject) and (cs.Get('contain', '') = 'all') then
      begin
        SetLength(items, n + 1);
        items[n].R := XYWHOf(TJSONObject(d));
        items[n].AlongY := ax.Strings['dim'] = 'y';
        items[n].Proportion := Num(ax, 'nameP');
        Inc(n);
      end;
    end;
    m := TyOuterBoundsMargin(XYWHOf(cs.Objects['outer']), XYWHOf(cs.Objects['raw']),
      items);
    mt := cs.Arrays['margin'];
    for a := 0 to 3 do want[a] := FromHex(mt.Strings[a]);
    r := XYWHOf(cs.Objects['raw']);
    TyShrinkRect(r, m, FromHex(cs.Arrays['clamp'].Strings[0]),
      FromHex(cs.Arrays['clamp'].Strings[1]));
    w := XYWHOf(cs.Objects['rect']);
    Inc(compared);
    if (m[0] <> want[0]) or (m[1] <> want[1]) or (m[2] <> want[2])
      or (m[3] <> want[3]) or (r.X <> w.X) or (r.Y <> w.Y) or (r.W <> w.W)
      or (r.H <> w.H) then
    begin
      Inc(bad);
      if bad <= 20 then
        report := report + LineEnding + Format('  %s: margin %s,%s,%s,%s / rect %s,%s,%s,%s here',
          [cs.Strings['name'], Fmt(m[0]), Fmt(m[1]), Fmt(m[2]), Fmt(m[3]),
           Fmt(r.X), Fmt(r.Y), Fmt(r.W), Fmt(r.H)]);
    end;
  end;
  AssertTrue(Format('enough was compared (%d)', [compared]), compared >= 40);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared)
    + ' shrinks differ:' + report, 0, bad);
end;

{ ==================== 3. the pipeline ==================== }

procedure TAdvChartGridBoundsOracleTest.TestEveryGridAsUpstreamSolvesIt;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c, g, bad, compared: Integer;
  want: TTyXYWH;
  xywh: TTyXYWH;
  report: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  compared := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if IsDeferred(cs) then Continue;
    try
      RunCase(cs);
    except
      on E: Exception do
      begin
        Inc(bad);
        report := report + LineEnding + '  ' + cs.Strings['name'] + ': '
          + E.ClassName + ': ' + E.Message;
        Continue;
      end;
    end;
    g := 0;
    if cs.Find('grid') <> nil then g := cs.Integers['grid'];
    want := XYWHOf(cs.Objects['rect']);
    Inc(compared);
    if g >= FBuild.GridCount then
    begin
      Inc(bad);
      report := report + LineEnding + '  ' + cs.Strings['name'] + ': no grid';
      Continue;
    end;
    xywh := FBuild.Grid(g).PlotXYWH;
    if (xywh.X <> want.X) or (xywh.Y <> want.Y)
      or (xywh.W <> want.W) or (xywh.H <> want.H) then
    begin
      Inc(bad);
      if bad <= 30 then
        report := report + LineEnding + Format('  %s: %s,%s,%s,%s upstream, %s,%s,%s,%s here',
          [cs.Strings['name'], cs.Objects['rectText'].Strings['x'],
           cs.Objects['rectText'].Strings['y'],
           cs.Objects['rectText'].Strings['width'],
           cs.Objects['rectText'].Strings['height'], Fmt(xywh.X),
           Fmt(xywh.Y), Fmt(xywh.W), Fmt(xywh.H)]);
    end;
  end;
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared)
    + ' grids differ from upstream:' + report, 0, bad);
  AssertTrue(Format('enough was compared (%d)', [compared]), compared >= 60);
end;

initialization
  RegisterTest(TAdvChartGridBoundsOracleTest);
end.
