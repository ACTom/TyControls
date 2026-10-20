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
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Data,
     tyControls.AdvanceChart.Option, tyControls.AdvanceChart.OptionMerge, tyControls.AdvanceChart;

type
  TPkChart = class(TTyAdvanceChart)
  public
    procedure Cached(ACanvas: TCanvas; const ARect: TRect);
    procedure HoverAt(AX, AY: Integer);
    procedure LeaveNow;
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

  { [R2-I6] the paint order repaired where an element moved }
  TAdvChartPaintOrderTest = class(TTestCase)
  protected
    procedure TearDown; override;
  published
    procedure TestARepairedOrderIsTheSortedOrder;
    procedure TestACutTailIsRepairedNotSortedWhole;
    procedure TestAHoverSweepIsTheSameRepaired;
  end;

  { [R2-I6] the option text read without fcl-json's scanner }
  TAdvChartFastJsonTest = class(TTestCase)
  protected
    procedure TearDown; override;
  published
    procedure TestTheFastReaderIsTheReader;
    procedure TestTheFastReaderTakesPlainJsonOnly;
  end;

implementation

procedure TPkChart.Cached(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderCached(ACanvas, ARect, 96);
end;

procedure TPkChart.HoverAt(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TPkChart.LeaveNow;
begin
  MouseLeave;
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

{ ---------------------------------------------------------- the reader }

procedure TAdvChartFastJsonTest.TearDown;
begin
  TyJsonFastForTest(True);
  inherited TearDown;
end;

{ two trees the same: node classes, kinds, keys in order, strings by bytes,
  numbers by their bits }
function JsonSame(A, B: TJSONData; out AWhy: string): Boolean;
var
  k: Integer;
  fa, fb: Double;
begin
  Result := False;
  AWhy := '';
  if (A = nil) or (B = nil) then
  begin
    Result := (A = nil) and (B = nil);
    if not Result then AWhy := 'one is nil';
    Exit;
  end;
  if A.ClassType <> B.ClassType then
  begin
    AWhy := A.ClassName + ' / ' + B.ClassName + ' at ' + A.AsJSON;
    Exit;
  end;
  case A.JSONType of
    jtNumber:
      if A is TJSONFloatNumber then
      begin
        fa := A.AsFloat;
        fb := B.AsFloat;
        if PInt64(@fa)^ <> PInt64(@fb)^ then
        begin
          AWhy := 'float ' + A.AsJSON + ' / ' + B.AsJSON;
          Exit;
        end;
      end
      else if A is TJSONQWordNumber then
      begin
        if A.AsQWord <> B.AsQWord then
        begin
          AWhy := 'qword ' + A.AsJSON;
          Exit;
        end;
      end
      else if A.AsInt64 <> B.AsInt64 then
      begin
        AWhy := 'integer ' + A.AsJSON + ' / ' + B.AsJSON;
        Exit;
      end;
    jtString:
      if A.AsString <> B.AsString then
      begin
        AWhy := 'string ' + A.AsJSON + ' / ' + B.AsJSON;
        Exit;
      end;
    jtBoolean:
      if A.AsBoolean <> B.AsBoolean then
      begin
        AWhy := 'boolean';
        Exit;
      end;
    jtArray, jtObject:
      begin
        if A.Count <> B.Count then
        begin
          AWhy := 'count ' + IntToStr(A.Count) + ' / ' + IntToStr(B.Count);
          Exit;
        end;
        for k := 0 to A.Count - 1 do
        begin
          if (A.JSONType = jtObject)
            and (TJSONObject(A).Names[k] <> TJSONObject(B).Names[k]) then
          begin
            AWhy := 'key ' + TJSONObject(A).Names[k] + ' / ' + TJSONObject(B).Names[k];
            Exit;
          end;
          if not JsonSame(A.Items[k], B.Items[k], AWhy) then Exit;
        end;
      end;
  end;
  Result := True;
end;

const
  cEdges: array[0..65] of string = (
    '0', '-0', '5', '-5', '7', '999999999', '-999999999', '1000000000', '-1000000000',
    '2147483647', '2147483648', '-2147483647', '-2147483648', '-2147483649',
    '9223372036854775807', '9223372036854775808', '-9223372036854775808',
    '-9223372036854775809', '18446744073709551615', '18446744073709551616',
    '123456789012345678901234567890', '0.1', '-0.0', '1e5', '1E-5', '1e+5', '-1.5e+300',
    '1e400', '-1e400', '4.9e-324', '2.4703282292062327e-324', '1.7976931348623157e308',
    '0.30000000000000004', '1.00000000000000011102230246251565404236316680908203125',
    '123456.789012345678', '9007199254740993', '9007199254740993.0', '0.1e1', '1.5e-7',
    '[1,2,3]', '[ 1 , 2 ]', ' {"a": [1, {"b": null}], "c": true, "d": false} ',
    '{"a":1,"a":2}', '{"a":"x\"y{["}', '"\n\t\/\b\f\r\\\''"', '[1,]', '{"a":1,}',
    '{}', '[]', 'true', 'nullx', 'True', '"'#$C3#$A9#$E6#$BC#$A2'"', '"abc\u0041"',
    '''x''', '{a:1}', '// c'#10'1', '1 2', '[1 2]', '{"k" 1}', '"a'#9'b"', '012', '.5',
    '-', '{"a":"\q"}', '1.');

{ THE FAST READER IS THE READER: every edge above and a thousand plain
  documents of every shape, read with the fast reader on and off (the long
  way: the escape pre-decode, fcl-json in relaxed mode, TyJsonFixNumbers):
  the same answer -- the same tree, or the same error }
procedure TAdvChartFastJsonTest.TestTheFastReaderIsTheReader;
var
  k, taken: Integer;
  texts: TStringList;
  a, b: TJSONData;
  ea, eb: TTyOptionError;
  oka, okb: Boolean;
  why, rej: string;
  seed: LongWord;

  function R(AMax: Integer): Integer;
  begin
    {$push}{$R-}{$Q-}
    seed := seed * 1664525 + 1013904223;
    {$pop}
    Result := Integer((seed shr 8) mod LongWord(AMax));
  end;

  function NumText: string;
  var i: Integer;
  begin
    case R(9) of
      0: Result := IntToStr(R(1000));
      1: Result := IntToStr(-R(100000));
      2: Result := IntToStr(R(1000000000)) + IntToStr(R(1000000000));
      3: Result := '-' + IntToStr(R(9) + 1) + IntToStr(R(1000000000)) + IntToStr(R(1000000000));
      4: Result := IntToStr(R(1000)) + '.' + IntToStr(R(1000000));
      5: Result := '-' + IntToStr(R(100)) + '.' + IntToStr(R(10)) + 'e' + IntToStr(R(40) - 20);
      6:
        begin
          Result := '0.';
          for i := 1 to 15 + R(8) do Result := Result + Chr(Ord('0') + R(10));
        end;
      7: Result := IntToStr(R(10)) + 'E+' + IntToStr(R(320));
    else
      Result := IntToStr(R(100000)) + '.' + IntToStr(R(100000)) + IntToStr(R(100000)) + IntToStr(R(100000));
    end;
  end;

  function StrText: string;
  var i: Integer;
  begin
    Result := '"';
    for i := 1 to R(8) do
      case R(12) of
        0: Result := Result + '\n';
        1: Result := Result + '\"';
        2: Result := Result + '\\';
        3: Result := Result + #$E4#$B8#$AD;
        4: Result := Result + '{';
        5: Result := Result + ' ';
      else
        Result := Result + Chr(Ord('a') + R(26));
      end;
    Result := Result + '"';
  end;

  function Doc(ADepth: Integer): string;
  var i, n: Integer;
  begin
    case R(ADepth + 6) of
      0: Result := NumText;
      1: Result := StrText;
      2: if R(2) = 0 then Result := 'true' else Result := 'null';
      3, 4:
        begin
          Result := '[';
          n := R(5);
          for i := 0 to n - 1 do
          begin
            if i > 0 then Result := Result + ',' + StringOfChar(' ', R(2));
            if ADepth > 0 then Result := Result + Doc(ADepth - 1) else Result := Result + NumText;
          end;
          Result := Result + ']';
        end;
    else
      begin
        Result := '{';
        n := R(5);
        for i := 0 to n - 1 do
        begin
          if i > 0 then Result := Result + ',' + #10;
          Result := Result + '"k' + IntToStr(i) + '":';
          if ADepth > 0 then Result := Result + Doc(ADepth - 1) else Result := Result + StrText;
        end;
        Result := Result + '}';
      end;
    end;
  end;

begin
  texts := TStringList.Create;
  try
    for k := 0 to High(cEdges) do texts.Add(cEdges[k]);
    texts.Add(StringOfChar('[', 256) + StringOfChar(']', 256));
    texts.Add(StringOfChar('[', 257) + StringOfChar(']', 257));
    texts.Add('{"s":"' + StringOfChar('{', 300) + '"}');
    texts.Add('{"s":"\"' + StringOfChar('{', 300) + '"}');
    seed := 12345;
    for k := 0 to 999 do texts.Add(Doc(4));
    taken := 0;
    rej := '';
    for k := 0 to texts.Count - 1 do
    begin
      if TyJsonFastParse(texts[k], a) then
      begin
        Inc(taken);
        a.Free;
      end
      else if (k > High(cEdges) + 4) and (Length(rej) < 600) then
        rej := rej + ' | ' + Copy(texts[k], 1, 150);
      a := nil;
      b := nil;
      TyJsonFastForTest(True);
      oka := TyOptionParseRaw(texts[k], a, ea);
      TyJsonFastForTest(False);
      okb := TyOptionParseRaw(texts[k], b, eb);
      TyJsonFastForTest(True);
      try
        AssertEquals('parsed alike: ' + texts[k], okb, oka);
        if oka then
        begin
          AssertTrue(Format('the same tree for %s: %s', [Copy(texts[k], 1, 200), why]),
            JsonSame(a, b, why));
        end
        else
        begin
          AssertEquals('the same error: ' + texts[k], eb.Message, ea.Message);
          AssertEquals('the same line: ' + texts[k], eb.Line, ea.Line);
          AssertEquals('the same column: ' + texts[k], eb.Col, ea.Col);
        end;
      finally
        a.Free;
        b.Free;
      end;
    end;
    { the random documents are plain: nearly every one is taken }
    AssertTrue(Format('the fast reader took %d of %d: %s', [taken, texts.Count, rej]), taken > 900);
  finally
    texts.Free;
  end;
end;

{ WHAT IT LEAVES TO THE LONG WAY: a comment, a single quote, a code-unit
  escape, an identifier key, a trailing comma, a leading zero, a lone dot,
  a capitalised literal, a control character in a string, something after
  the value, an escape the scanner does not know, more than
  TyOptionMaxNesting levels }
procedure TAdvChartFastJsonTest.TestTheFastReaderTakesPlainJsonOnly;
const
  cLeft: array[0..12] of string = ('// c'#10'1', '''x''', '"\u0041"', '{a:1}', '[1,]',
    '012', '.5', 'True', '"a'#9'b"', '1 2', '{"a":1,}', '1.', '"\q"');
var
  k: Integer;
  d: TJSONData;
begin
  for k := 0 to High(cLeft) do
  begin
    AssertFalse('left: ' + cLeft[k], TyJsonFastParse(cLeft[k], d));
    AssertTrue('nothing made: ' + cLeft[k], d = nil);
  end;
  AssertFalse('too deep', TyJsonFastParse(StringOfChar('[', 257) + StringOfChar(']', 257), d));
  AssertTrue('as deep as allowed', TyJsonFastParse(StringOfChar('[', 256) + StringOfChar(']', 256), d));
  d.Free;
  AssertTrue('plain', TyJsonFastParse('{"a":[1,-2,3.5,"x\ny"],"b":{"c":null}}', d));
  try
    AssertEquals(2, d.Count);
    AssertEquals('x'#10'y', TJSONObject(d).Arrays['a'].Strings[3]);
    AssertTrue('an Integer', TJSONObject(d).Arrays['a'].Items[1] is TJSONIntegerNumber);
    AssertTrue('a float', TJSONObject(d).Arrays['a'].Items[2] is TJSONFloatNumber);
  finally
    d.Free;
  end;
end;

{ ---------------------------------------------------------- the order }

procedure TAdvChartPaintOrderTest.TearDown;
begin
  TyPaintListRepairForTest(True);
  inherited TearDown;
end;

{ THE REPAIRED ORDER IS THE SORTED ORDER: a list of three thousand elements
  on a few z and z2, sorted, then two hundred rounds of writes -- some that
  move an element (its z, its z2, both, the same one twice), some that do
  not, a journal rewound now and then, the tail cut and added to again --
  and after each, the order the list
  paints in is the order a list of the same elements added afresh is
  sorted in }
procedure TAdvChartPaintOrderTest.TestARepairedOrderIsTheSortedOrder;
var
  list, fresh: TTyPaintList;
  e: TTyChartElement;
  i, rnd, k, n, idx, r0: Integer;
  seed: LongWord;
  journal: Boolean;

  function R(AMax: Integer): Integer;
  begin
    {$push}{$R-}{$Q-}
    seed := seed * 1664525 + 1013904223;
    {$pop}
    Result := Integer((seed shr 8) mod LongWord(AMax));
  end;

begin
  seed := 777;
  r0 := TyPaintListRepairsForTest;
  list := TTyPaintList.Create;
  try
    for i := 0 to 2999 do
    begin
      e := Default(TTyChartElement);
      e.Z := R(4);
      e.Z2 := R(21) - 5;
      e.Style.Alpha := i;
      list.Add(e);
    end;
    list.PaintOrder(0);
    for rnd := 0 to 199 do
    begin
      journal := R(5) = 0;
      if journal then
      begin
        list.JournalOpen;
        list.JournalRecord(True);
      end;
      n := 1 + R(40);
      if R(10) = 0 then n := 300;
      for k := 1 to n do
      begin
        idx := R(3000);
        idx := idx mod list.Count;
        e := list.Element(idx);
        case R(5) of
          0: e.Z := R(4);
          1: e.Z2 := R(21) - 5;
          2:
            begin
              e.Z := R(4);
              e.Z2 := R(21) - 5;
            end;
          3: e.Style.Alpha := R(1000);
        else
          Inc(e.Z2, 10);
        end;
        list.SetElement(idx, e);
      end;
      if journal then
      begin
        list.JournalRecord(False);
        list.JournalClose;
        { the patched frame paints (its order repaired) before the next
          patch rewinds the journal: the rewound elements move back }
        list.PaintOrder(0);
        if R(2) = 0 then list.JournalRewind;
      end
      { the tail cut and built again (ListTailRebuild) }
      else if R(4) = 0 then
      begin
        list.Truncate(list.Count - 1 - R(60));
        for k := 1 to R(80) do
        begin
          e := Default(TTyChartElement);
          e.Z := R(4);
          e.Z2 := R(21) - 5;
          list.Add(e);
        end;
      end;
      fresh := TTyPaintList.Create;
      try
        for i := 0 to list.Count - 1 do fresh.Add(list.Element(i));
        for i := 0 to list.Count - 1 do
          AssertEquals(Format('round %d place %d', [rnd, i]), fresh.PaintOrder(i),
            list.PaintOrder(i));
      finally
        fresh.Free;
      end;
    end;
    AssertTrue('repaired, not sorted whole, most rounds',
      TyPaintListRepairsForTest - r0 > 100);
  finally
    list.Free;
  end;
end;

{ A CUT TAIL BUILT AGAIN (ListTailRebuild) IS REPAIRED: Truncate takes the
  cut elements out of the order, so the order of the rest stands and the
  new tail merges in -- the sorted order, by a repair, not a sort of the
  whole list }
procedure TAdvChartPaintOrderTest.TestACutTailIsRepairedNotSortedWhole;
var
  list, fresh: TTyPaintList;
  e: TTyChartElement;
  i, r0: Integer;
begin
  list := TTyPaintList.Create;
  fresh := TTyPaintList.Create;
  try
    for i := 0 to 499 do
    begin
      e := Default(TTyChartElement);
      e.Z := i mod 3;
      e.Z2 := (i * 7) mod 11;
      e.Style.Alpha := i;
      list.Add(e);
    end;
    list.PaintOrder(0);
    r0 := TyPaintListRepairsForTest;
    list.Truncate(400);
    for i := 0 to 49 do
    begin
      e := Default(TTyChartElement);
      e.Z := (i * 5) mod 3;
      e.Z2 := (i * 3) mod 13 - 2;
      e.Style.Alpha := 1000 + i;
      list.Add(e);
    end;
    list.PaintOrder(0);
    AssertEquals('the cut and built tail was repaired', 1, TyPaintListRepairsForTest - r0);
    for i := 0 to list.Count - 1 do fresh.Add(list.Element(i));
    for i := 0 to list.Count - 1 do
      AssertEquals(Format('place %d', [i]), fresh.PaintOrder(i), list.PaintOrder(i));
  finally
    fresh.Free;
    list.Free;
  end;
end;

{ A HOVER SWEEP over a heatmap of ten thousand cells with a visualMap,
  frame by frame the same with the order repaired and sorted whole }
procedure TAdvChartPaintOrderTest.TestAHoverSweepIsTheSameRepaired;
var
  frames: array[Boolean] of TStringList;
  rep: Boolean;
  chart: TPkChart;
  bmp: TBitmap;
  form: TForm;
  ctl: TTyStyleController;
  sb: TStringBuilder;
  i, j, k, r0, used: Integer;
  opt: string;
begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"animation": false, "tooltip": {}, "xAxis": {"type": "category"},');
    sb.Append(' "yAxis": {"type": "category"},');
    sb.Append(' "visualMap": {"min": 0, "max": 1, "calculable": true, "orient": "horizontal", "left": "center", "bottom": 0},');
    sb.Append(' "series": [{"type": "heatmap", "progressive": 1000, "data": [');
    for i := 0 to 99 do
      for j := 0 to 99 do
      begin
        if (i > 0) or (j > 0) then sb.Append(',');
        sb.Append('[').Append(i).Append(',').Append(j).Append(',')
          .Append(FloatToStr(((i * 37 + j * 11) mod 100) / 100, DefaultFormatSettings)).Append(']');
      end;
    sb.Append(']}]}');
    opt := sb.ToString;
  finally
    sb.Free;
  end;
  frames[False] := TStringList.Create;
  frames[True] := TStringList.Create;
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  bmp := TBitmap.Create;
  used := 0;
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(480, 340);
    for rep := False to True do
    begin
      TyPaintListRepairForTest(rep);
      r0 := TyPaintListRepairsForTest;
      chart := TPkChart.Create(form);
      try
        chart.Parent := form;
        chart.Controller := ctl;
        chart.AnimationMode := camOff;
        chart.AnimNow := 0;
        chart.ProgressiveStepCostMs := 1;
        chart.SetBounds(0, 0, 480, 340);
        chart.Option := opt;
        chart.Cached(bmp.Canvas, Rect(0, 0, 480, 340));
        k := 0;
        while chart.ProgressiveUnfinished and (k < 100) do
        begin
          chart.ProgressTick;
          chart.Cached(bmp.Canvas, Rect(0, 0, 480, 340));
          Inc(k);
        end;
        for k := 0 to 15 do
        begin
          chart.HoverAt(70 + k * 24, 60 + k * 14);
          chart.Cached(bmp.Canvas, Rect(0, 0, 480, 340));
          frames[rep].Add(FrameText(bmp));
        end;
        chart.LeaveNow;
        chart.Cached(bmp.Canvas, Rect(0, 0, 480, 340));
        frames[rep].Add(FrameText(bmp));
        if rep then used := TyPaintListRepairsForTest - r0;
      finally
        chart.Free;
      end;
    end;
    AssertEquals('as many frames', frames[False].Count, frames[True].Count);
    for k := 0 to frames[False].Count - 1 do
      AssertTrue(Format('frame %d the same', [k]), frames[False][k] = frames[True][k]);
    AssertTrue(Format('the order was repaired (%d)', [used]), used > 0);
  finally
    bmp.Free;
    ctl.Free;
    form.Free;
    frames[False].Free;
    frames[True].Free;
    TyPaintListRepairForTest(True);
  end;
end;

initialization
  RegisterTest(TAdvChartParseKeepTest);
  RegisterTest(TAdvChartPaintOrderTest);
  RegisterTest(TAdvChartFastJsonTest);
end.
