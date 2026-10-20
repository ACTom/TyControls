unit test.advchart.parsekeep;
{$mode objfpc}{$H+}
{ [R2-I6] The parsed data kept between builds of one option tree.

  Every update builds the chart again from its option, and a dataZoom step
  used to parse every series' data again: half a million bars parsed for
  each frame of a drag. What is kept, none of it a pixel:

  - a series' store as its fill left it, for the next build of the SAME
    TREE (TTyChartOption.Generation: a new number with every set, merge,
    clear, media or timeline merge and appendData) by the same recipe on
    the same category lists -- a collecting list given what the fill
    collected, in its order (TestAKeptStoreIsTheParsedStore: every step of
    a dataZoom drag, a resize, a legend toggle, a merge of new data, an
    appendData, over own data, collected and fixed categories, a dataset,
    a polar and a time axis -- the stores and the pixels the same with the
    keep on and off, and the keep used);
  - an axis' category list read once per tree (TestACategoryListIsReadOnce-
    PerTree);
  - the tree's number (TestTheGenerationIsNewWithEveryWrite). }
interface

uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     fpjson,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Data,
     tyControls.AdvChart.Option, tyControls.AdvChart.OptionMerge, tyControls.AdvanceChart;

type
  TPkChart = class(TTyAdvanceChart)
  public
    procedure Cached(ACanvas: TCanvas; const ARect: TRect);
  end;

  TAdvChartParseKeepTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    function NewChart(AW, AH: Integer; const AOption: string): TPkChart;
    { the steps of one option, every store and frame after each, with the
      keep at AMinRows (-1 off) }
    function Run(const AOption: string; ASeries: Integer; const AMerge,
      AAppend: string; AMinRows: Integer; out AKeeps: Integer): TStringList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAKeptStoreIsTheParsedStore;
    procedure TestACategoryListIsReadOncePerTree;
    procedure TestTheGenerationIsNewWithEveryWrite;
  end;

implementation

procedure TPkChart.Cached(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderCached(ACanvas, ARect, 96);
end;

function TAdvChartParseKeepTest.NewChart(AW, AH: Integer; const AOption: string): TPkChart;
begin
  Result := TPkChart.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.AnimationMode := camOff;
  Result.AnimNow := 0;
  Result.ProgressiveStepCostMs := 1;
  Result.SetBounds(0, 0, AW, AH);
  Result.Option := AOption;
end;

procedure TAdvChartParseKeepTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
end;

procedure TAdvChartParseKeepTest.TearDown;
begin
  TyAdvChartStoreKeepForTest(4096);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function Bits(A: Double): string;
begin
  Result := IntToHex(PInt64(@A)^, 16);
end;

function ValueText(const V: TTyDataValue): string;
begin
  Result := IntToStr(Ord(V.Kind)) + ':' + Bits(V.Num) + ':' + V.Text;
end;

{ everything a store holds that a reader can ask }
function StoreDump(S: TTyDataStore): string;
var
  sb: TStringBuilder;
  d, r, k: Integer;
  it: TTyRawItem;
  a: TTyIntegerArray;
begin
  if S = nil then Exit('nil');
  sb := TStringBuilder.Create;
  try
    sb.Append('dims ').Append(S.DimCount).Append(' raw ').Append(S.RawCount)
      .Append(' count ').Append(S.Count).Append(' width ').Append(S.RawWidth)
      .Append(' ovr ').Append(S.OverrideCount).Append(' filtered ')
      .Append(BoolToStr(S.IsFiltered, '1', '0')).Append(#10);
    for d := 0 to S.DimCount - 1 do
    begin
      sb.Append(' dim ').Append(S.DimName(d)).Append(' ').Append(Ord(S.DimType(d)))
        .Append(' ').Append(S.DimCoord(d)).Append(' pos ').Append(S.RawDimPos(d))
        .Append(' cats ').Append(S.CategoryCount(d)).Append(':');
      for k := 0 to S.CategoryCount(d) - 1 do sb.Append(S.CategoryAt(d, k)).Append(',');
      sb.Append(#10);
    end;
    for k := 0 to S.RawWidth - 1 do
      sb.Append(' pos ').Append(k).Append(' ').Append(S.RawDimName(k)).Append(' ')
        .Append(Ord(S.RawPosType(k))).Append(#10);
    a := S.TooltipPositions;
    sb.Append(' tip ').Append(BoolToStr(S.HasTooltipPositions, '1', '0'));
    for k := 0 to High(a) do sb.Append(',').Append(a[k]);
    a := S.LabelPositions;
    sb.Append(' label ').Append(BoolToStr(S.HasLabelPositions, '1', '0'));
    for k := 0 to High(a) do sb.Append(',').Append(a[k]);
    sb.Append(#10);
    for r := 0 to S.RawCount - 1 do
    begin
      sb.Append(' r').Append(r).Append(' ').Append(S.GetNameByRaw(r)).Append('|')
        .Append(S.GetIdByRaw(r)).Append('|');
      for d := 0 to S.DimCount - 1 do sb.Append(Bits(S.GetByRaw(d, r))).Append(',');
      it := S.RawItemByRaw(r);
      sb.Append('|').Append(Ord(it.Shape)).Append(' ').Append(ValueText(it.Scalar));
      for k := 0 to High(it.Cells) do sb.Append(' ').Append(ValueText(it.Cells[k]));
      sb.Append(#10);
    end;
    for r := 0 to S.Count - 1 do sb.Append(S.GetRawIndex(r)).Append(',');
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

function FrameText(B: TBitmap): string;
var
  y: Integer;
  row: string;
begin
  Result := '';
  SetLength(row, B.Width * 3);
  for y := 0 to B.Height - 1 do
  begin
    Move(B.ScanLine[y]^, row[1], B.Width * 3);
    Result := Result + row;
  end;
end;

function TAdvChartParseKeepTest.Run(const AOption: string; ASeries: Integer;
  const AMerge, AAppend: string; AMinRows: Integer; out AKeeps: Integer): TStringList;
var
  chart: TPkChart;
  bmp: TBitmap;
  k0: Integer;

  procedure Note(const AStep: string);
  var s, n: Integer;
  begin
    n := 0;
    chart.Cached(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height));
    while chart.ProgressiveUnfinished and (n < 200) do
    begin
      chart.ProgressTick;
      chart.Cached(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height));
      Inc(n);
    end;
    for s := 0 to ASeries - 1 do
      Result.Add(AStep + ' series ' + IntToStr(s) + #10 + StoreDump(chart.SeriesStore(s)));
    Result.Add(AStep + ' frame ' + FrameText(bmp));
  end;

begin
  TyAdvChartStoreKeepForTest(AMinRows);
  k0 := TyAdvChartStoreKeepsForTest;
  Result := TStringList.Create;
  bmp := TBitmap.Create;
  chart := nil;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(460, 320);
    chart := NewChart(460, 320, AOption);
    AssertEquals('the option parses', '', chart.OptionError);
    Note('first');
    chart.DispatchAction('{"type":"dataZoom","start":20,"end":70}');
    Note('zoom 20-70');
    chart.DispatchAction('{"type":"dataZoom","start":30,"end":80}');
    Note('zoom 30-80');
    chart.SetBounds(0, 0, 420, 300);
    bmp.SetSize(420, 300);
    Note('resized');
    chart.DispatchAction('{"type":"legendToggleSelect","name":"b"}');
    Note('legend off');
    chart.DispatchAction('{"type":"legendToggleSelect","name":"b"}');
    Note('legend on');
    if AMerge <> '' then
    begin
      chart.SetOption(AMerge);
      Note('merged');
    end;
    chart.DispatchAction('{"type":"dataZoom","start":10,"end":90}');
    Note('zoom 10-90');
    if AAppend <> '' then
    begin
      chart.AppendData(0, AAppend);
      Note('appended');
      chart.DispatchAction('{"type":"dataZoom","start":5,"end":95}');
      Note('zoom 5-95');
    end;
    chart.DispatchAction('{"type":"dataZoom","start":0,"end":100}');
    Note('zoom all');
    AKeeps := TyAdvChartStoreKeepsForTest - k0;
  finally
    chart.Free;
    bmp.Free;
    TyAdvChartStoreKeepForTest(4096);
  end;
end;

function Cats(AN: Integer; const APrefix: string): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to AN - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '"' + APrefix + IntToStr(i) + '"';
  end;
end;

function Rows(AN, ASeed: Integer; const AFmt: string): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to AN - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + Format(AFmt, [i, ((i * 37 + ASeed) mod 53) + 1,
      ((i * 11 + ASeed * 3) mod 29) + 2, i mod 7]);
  end;
end;

{ THE KEEP IS THE PARSE: each option through a dataZoom drag, a resize, a
  legend toggle, a merge of new data (the same length: only the tree's
  number tells), an appendData -- the stores and the frames with the keep
  at 0 rows (every store kept) and off. }
procedure TAdvChartParseKeepTest.TestAKeptStoreIsTheParsedStore;
var
  cases: array[0..4] of record
    Opt, Merge, Append: string;
    Series: Integer;
  end;
  c, k, keeps, offKeeps: Integer;
  off, on_: TStringList;
begin
  { own data: a fixed category list with a name twice, a bar of numeric
    strings and names, a line of items with styles, a dataZoom and a legend }
  cases[0].Opt := '{"animation":false,"legend":{},"dataZoom":[{"type":"inside"},{"type":"slider"}],'
    + '"xAxis":{"type":"category","data":[' + Cats(40, 'c') + ',"c3"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"a","data":[' + Rows(41, 1, '{"value":"%1:d.5","name":"n%0:d"}') + ']},'
    + '{"type":"line","name":"b","data":[' + Rows(41, 2, '{"value":%1:d,"itemStyle":{"color":"#%3:d0%3:d0%3:d0"}}') + ']}]}';
  cases[0].Merge := '{"series":[{"data":[' + Rows(41, 5, '"%2:d"') + ']}]}';
  cases[0].Append := '[' + Rows(6, 9, '"%1:d"') + ']';
  cases[0].Series := 2;
  { collected categories: two scatters on one category axis, the second
    bringing names of its own; a value pair on a value axis }
  cases[1].Opt := '{"animation":false,"legend":{},"dataZoom":[{"type":"slider","xAxisIndex":0}],'
    + '"xAxis":{"type":"category"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"scatter","name":"a","data":[' + Rows(30, 1, '["k%2:d",%1:d]') + ']},'
    + '{"type":"scatter","name":"b","data":[' + Rows(30, 4, '["q%3:d",%1:d]') + ',["k1",3]]}]}';
  cases[1].Merge := '{"series":[{},{"data":[' + Rows(31, 6, '["z%3:d",%1:d]') + ']}]}';
  cases[1].Append := '[' + Rows(5, 2, '["new%0:d",%1:d]') + ']';
  cases[1].Series := 2;
  { a dataset: a candlestick and a bar on its collected first column }
  cases[2].Opt := '{"animation":false,"legend":{},"dataZoom":[{"type":"inside"}],'
    + '"dataset":{"source":[' + Rows(36, 3, '["d%0:d",%1:d,%2:d,%3:d,%1:d]') + ']},'
    + '"xAxis":{"type":"category"},"yAxis":{"scale":true},'
    + '"series":[{"type":"candlestick","name":"a"},{"type":"bar","name":"b","encode":{"x":0,"y":3}}]}';
  cases[2].Merge := '{"dataset":{"source":[' + Rows(36, 8, '["d%0:d",%2:d,%1:d,%3:d,%2:d]') + ']}}';
  cases[2].Append := '';
  cases[2].Series := 2;
  { a polar: bars on a collected angle category }
  cases[3].Opt := '{"animation":false,"legend":{},"polar":{},"angleAxis":{"type":"category"},'
    + '"radiusAxis":{},"dataZoom":[{"type":"inside","angleAxisIndex":0}],'
    + '"series":[{"type":"bar","name":"a","coordinateSystem":"polar","data":['
    + Rows(24, 1, '["a%3:d",%1:d]') + ']},{"type":"bar","name":"b","coordinateSystem":"polar","data":['
    + Rows(24, 2, '["a%3:d",%2:d]') + ']}]}';
  cases[3].Merge := '{"series":[{"data":[' + Rows(24, 7, '["b%3:d",%1:d]') + ']}]}';
  cases[3].Append := '';
  cases[3].Series := 2;
  { a time axis read from date strings, the series' own dimensions and
    encode }
  cases[4].Opt := '{"animation":false,"legend":{},"dataZoom":[{"type":"slider"}],'
    + '"xAxis":{"type":"time"},"yAxis":{},'
    + '"series":[{"type":"line","name":"a","dimensions":["when","v","w"],"encode":{"x":"when","y":"w"},'
    + '"data":[' + Rows(28, 1, '["2024-01-%3:d2",%1:d,%2:d]') + ']},'
    + '{"type":"scatter","name":"b","data":[' + Rows(28, 3, '[%0:d000000,%2:d]') + ']}]}';
  cases[4].Merge := '{"series":[{"encode":{"x":"when","y":"v"}}]}';
  cases[4].Append := '[' + Rows(3, 4, '["2024-02-0%3:d",%1:d,%2:d]') + ']';
  cases[4].Series := 2;
  for c := 0 to High(cases) do
  begin
    off := Run(cases[c].Opt, cases[c].Series, cases[c].Merge, cases[c].Append, -1, offKeeps);
    on_ := Run(cases[c].Opt, cases[c].Series, cases[c].Merge, cases[c].Append, 0, keeps);
    try
      AssertEquals(Format('case %d: off keeps none', [c]), 0, offKeeps);
      AssertTrue(Format('case %d: the keep was used (%d)', [c, keeps]), keeps >= 4);
      AssertEquals(Format('case %d: as many records', [c]), off.Count, on_.Count);
      for k := 0 to off.Count - 1 do
        AssertTrue(Format('case %d: %s', [c, Copy(off[k], 1, Pos(#10, off[k] + #10) - 1)]),
          off[k] = on_[k]);
    finally
      off.Free;
      on_.Free;
    end;
  end;
end;

{ AN AXIS' CATEGORY LIST IS READ ONCE PER TREE: the same strings for the
  same node while the tree's number stands, read again after it changes }
procedure TAdvChartParseKeepTest.TestACategoryListIsReadOncePerTree;
var
  o: TTyChartOption;
  a, b: TTyStringArray;
  node: TJSONData;
begin
  o := TTyChartOption.Create;
  try
    AssertTrue(o.SetOptionText('{"xAxis":{"type":"category","data":["x","y"]}}'));
    node := o.Find('xAxis.data');
    AssertTrue('the node', node <> nil);
    AssertFalse('nothing read yet', o.MemoCategories(node, a));
    SetLength(b, 2);
    b[0] := 'x';
    b[1] := 'y';
    o.MemoCategoriesPut(node, b);
    AssertTrue('kept', o.MemoCategories(node, a));
    AssertEquals(2, Length(a));
    AssertEquals('y', a[1]);
    o.Touch;
    AssertFalse('a new tree reads again', o.MemoCategories(node, a));
  finally
    o.Free;
  end;
end;

{ THE TREE'S NUMBER is new with every write a build reads, and unique in
  the process: a second option never has the first one's }
procedure TAdvChartParseKeepTest.TestTheGenerationIsNewWithEveryWrite;
var
  o, p: TTyChartOption;
  g: Int64;
  rep: TTyMergeReport;
begin
  o := TTyChartOption.Create;
  p := TTyChartOption.Create;
  try
    AssertTrue('two options, two numbers', o.Generation <> p.Generation);
    g := o.Generation;
    AssertTrue(o.SetOptionText('{"series":[{"type":"bar","data":[1]}]}'));
    AssertTrue('set', o.Generation <> g);
    g := o.Generation;
    o.Find('series');
    o.ComponentAt('series', 0);
    AssertEquals('a read is no write', g, o.Generation);
    AssertTrue(o.MergeOptionText('{"series":[{"data":[2]}]}', nil, rep));
    AssertTrue('merged', o.Generation <> g);
    g := o.Generation;
    o.Touch;
    AssertTrue('touched', o.Generation <> g);
    g := o.Generation;
    o.Clear;
    AssertTrue('cleared', o.Generation <> g);
  finally
    o.Free;
    p.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartParseKeepTest);
end.
