unit test.advchart.speedkeep;
{$mode objfpc}{$H+}
{ [R5-G] WHAT THE SPEED-UPS OF THE FIFTH ROUND KEEP, AND WHEN THEY LET GO.

  None of them is a pixel. The control used to walk every item of a series'
  `data` -- a million items for scatter-large -- in five places on every
  build (row fills, decals, item labels, item symbols, candle rows), each
  asking every item whether it is an object, and to allocate a symbol table
  as long as the data whether any item had a symbol of its own:

  - ObjectRowsOf: which items of an option array are objects, kept for the
    tree they were read off (TTyChartOption.Generation) -- the same frames
    and the same paint lists with the keep on and off over a dataZoom drag,
    a resize, a legend toggle, a merge and an appendData of object items
    into the array the keep holds (TestTheObjectRowsAreKeptForTheTree; an
    append that is not seen is red there);
  - a halo's trace, kept by the ink it was traced from -- the padded alpha
    of the ink's box, where the box stands, the scale -- and given back as a
    copy: the same outline as a fresh trace for the same ink, for the same
    ink moved, for one pixel changed, for a box under the same hash
    (TestATraceIsKeptByItsInk);
  - a notMerge option's first sync carries the old view's row records only
    where it kept some: a large series' rows had none, and the carry sized
    them to the store and diffed every key for nothing
    (TestNoRecordIsCarriedWhereNoneWasKept: a large scatter carries nothing,
    a small one still carries its hovered row's emphasis);
  - the option reader's short decimal read from the digits it has already
    scanned, bit for bit the long way's value
    (TestAShortDecimalIsTheLongWaysNumber). }
interface

uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     fpjson,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Render,
     BGRABitmap, BGRABitmapTypes,
     tyControls.AdvanceChart.Option, tyControls.AdvanceChart;

type
  TSkChart = class(TTyAdvanceChart)
  public
    procedure Cached(ACanvas: TCanvas; const ARect: TRect);
    function ListSig: string;
  end;

  TAdvChartSpeedKeepTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    function Run(const AOption, AMerge, AAppend: string; AMinItems: Integer;
      out AKept: Integer): TStringList;
    procedure Same(const AName, AOption, AMerge, AAppend: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheObjectRowsAreKeptForTheTree;
    procedure TestAShortDecimalIsTheLongWaysNumber;
    procedure TestATraceIsKeptByItsInk;
    procedure TestNoRecordIsCarriedWhereNoneWasKept;
  end;

implementation

procedure TSkChart.Cached(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderCached(ACanvas, ARect, 96);
end;

function Bits(A: Double): string;
begin
  Result := IntToHex(PInt64(@A)^, 16);
end;

{ what each element of the series list is: kind, box, points, ink, text }
function TSkChart.ListSig: string;
var
  k, j: Integer;
  e: TTyChartElement;
  sb: TStringBuilder;
begin
  sb := TStringBuilder.Create;
  try
    if SeriesList = nil then Exit('nil');
    for k := 0 to SeriesList.Count - 1 do
    begin
      e := SeriesList.Element(k);
      sb.Append(Ord(e.Shape.Kind)).Append(' ').Append(Bits(e.Shape.Bounds.Left))
        .Append(Bits(e.Shape.Bounds.Top)).Append(Bits(e.Shape.Bounds.Right))
        .Append(Bits(e.Shape.Bounds.Bottom)).Append(' p').Append(Length(e.Shape.Points));
      for j := 0 to High(e.Shape.Points) do
        sb.Append(',').Append(Bits(e.Shape.Points[j].X)).Append(Bits(e.Shape.Points[j].Y));
      sb.Append(' ').Append(e.Shape.PathData).Append(' f').Append(IntToHex(e.Style.FillColor, 8))
        .Append(' s').Append(IntToHex(e.Style.StrokeColor, 8))
        .Append(' g').Append(Ord(e.Style.FillGradient.Kind))
        .Append(' t').Append(e.Caption.Text).Append(#10);
    end;
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

procedure TAdvChartSpeedKeepTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
end;

procedure TAdvChartSpeedKeepTest.TearDown;
begin
  TyAdvChartObjRowsForTest(4096);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
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

function TAdvChartSpeedKeepTest.Run(const AOption, AMerge, AAppend: string;
  AMinItems: Integer; out AKept: Integer): TStringList;
var
  chart: TSkChart;
  bmp: TBitmap;
  k0: Integer;

  procedure Note(const AStep: string);
  var n: Integer;
  begin
    n := 0;
    chart.Cached(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height));
    while chart.ProgressiveUnfinished and (n < 200) do
    begin
      chart.ProgressTick;
      chart.Cached(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height));
      Inc(n);
    end;
    Result.Add(AStep + ' list ' + chart.ListSig);
    Result.Add(AStep + ' frame ' + FrameText(bmp));
  end;

begin
  TyAdvChartObjRowsForTest(AMinItems);
  k0 := TyAdvChartObjRowsKeptForTest;
  Result := TStringList.Create;
  bmp := TBitmap.Create;
  chart := nil;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(460, 320);
    chart := TSkChart.Create(FForm);
    chart.Parent := FForm;
    chart.Controller := FCtl;
    chart.AnimationMode := camOff;
    chart.SetBounds(0, 0, 460, 320);
    chart.Option := AOption;
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
    chart.DispatchAction('{"type":"dataZoom","start":0,"end":100}');
    Note('zoom all');
    if AAppend <> '' then
    begin
      AssertTrue('appended', chart.AppendData(0, AAppend));
      Note('appended');
      chart.DispatchAction('{"type":"dataZoom","start":5,"end":95}');
      Note('zoom 5-95');
      AssertTrue('appended again', chart.AppendData(0, AAppend));
      Note('appended again');
    end;
    AKept := TyAdvChartObjRowsKeptForTest - k0;
  finally
    chart.Free;
    bmp.Free;
    TyAdvChartObjRowsForTest(4096);
  end;
end;

procedure TAdvChartSpeedKeepTest.Same(const AName, AOption, AMerge, AAppend: string);
var
  a, b: TStringList;
  ka, kb, k: Integer;
begin
  a := Run(AOption, AMerge, AAppend, 1, ka);
  b := nil;
  try
    b := Run(AOption, AMerge, AAppend, -1, kb);
    AssertEquals(AName + ': as many steps', b.Count, a.Count);
    for k := 0 to a.Count - 1 do
      if a[k] <> b[k] then
        Fail(AName + ': kept and read again differ at ' + Copy(b[k], 1, 40));
    AssertTrue(AName + ': the keep answered', ka > 0);
    AssertEquals(AName + ': off, nothing kept', 0, kb);
  finally
    a.Free;
    b.Free;
  end;
end;

{ object items among plain ones: a symbol, a label, a gradient colour, a
  decal of their own; the append brings more objects into the array the
  keep holds -- in place, the tree touched }
procedure TAdvChartSpeedKeepTest.TestTheObjectRowsAreKeptForTheTree;
var
  i: Integer;
  sc, bars, cats, candles: string;
begin
  sc := '';
  bars := '';
  cats := '';
  candles := '';
  for i := 0 to 59 do
  begin
    if i > 0 then
    begin
      sc := sc + ',';
      bars := bars + ',';
      cats := cats + ',';
      candles := candles + ',';
    end;
    cats := cats + '"c' + IntToStr(i) + '"';
    case i mod 7 of
      3: sc := sc + Format('{"value":[%d,%d],"symbol":"rect","symbolSize":14}', [i, (i * 37) mod 50]);
      5: sc := sc + Format('{"value":[%d,%d],"label":{"show":true,"formatter":"L"}}', [i, (i * 37) mod 50]);
    else
      sc := sc + Format('[%d,%d]', [i, (i * 37) mod 50]);
    end;
    case i mod 5 of
      2: bars := bars + Format('{"value":%d,"itemStyle":{"color":{"type":"linear","x":0,"y":0,"x2":0,"y2":1,'
        + '"colorStops":[{"offset":0,"color":"#f00"},{"offset":1,"color":"#00f"}]},"decal":{"symbol":"circle"}}}',
        [(i * 13) mod 40 + 1]);
    else
      bars := bars + IntToStr((i * 13) mod 40 + 1);
    end;
    if i mod 6 = 1 then
      candles := candles + Format('{"value":[%d,%d,%d,%d],"itemStyle":{"color":"#0a0","borderColor":"#060"}}',
        [10 + i mod 9, 12 + i mod 7, 5, 20])
    else
      candles := candles + Format('[%d,%d,%d,%d]', [10 + i mod 9, 12 + i mod 7, 5, 20]);
  end;
  Same('scatter',
    '{"animation":false,"legend":{},"aria":{"decal":{"show":true}},"xAxis":{},"yAxis":{},'
    + '"dataZoom":[{"type":"inside"}],"series":[{"type":"scatter","name":"a","data":[' + sc + ']},'
    + '{"type":"scatter","name":"b","data":[[1,2],[3,4]]}]}',
    '{"series":[{"data":[' + sc + ',{"value":[70,7],"symbol":"diamond"}]}]}',
    '[[80,9],{"value":[81,10],"symbol":"triangle","symbolSize":20,"label":{"show":true}}]');
  Same('bars',
    '{"animation":false,"legend":{},"aria":{"decal":{"show":true}},"xAxis":{"data":[' + cats + ']},"yAxis":{},'
    + '"dataZoom":[{"type":"slider"}],"series":[{"type":"bar","name":"a","data":[' + bars + ']},'
    + '{"type":"bar","name":"b","data":[3,4,5]}]}',
    '', '');
  Same('candles',
    '{"animation":false,"legend":{},"xAxis":{"data":[' + cats + ']},"yAxis":{"scale":true},'
    + '"dataZoom":[{"type":"inside"}],"series":[{"type":"candlestick","name":"a","data":[' + candles + ']},'
    + '{"type":"line","name":"b","data":[3,4,5]}]}',
    '', '');
end;

{ the short path's numbers -- no exponent, at most fifteen significant
  digits, a fraction of up to 22 -- and their neighbours past it, read the
  fast way and the long way (fcl-json and TyJsonFixNumbers) }
procedure TAdvChartSpeedKeepTest.TestAShortDecimalIsTheLongWaysNumber;
const
  cTexts: array[0..27] of string = (
    '0.0', '-0.0', '0.000', '-0.000', '0.5', '-0.5', '12.25', '-12.25',
    '1.000000000000000', '1.00000000000000', '123456789012345.6', '12345678901234.56',
    '0.1234567890123456', '0.123456789012345', '0.0000000000000000000001',
    '0.00000000000000000000001', '-0.0000000000000000000009', '9007199254740.993',
    '0.30000000000000004', '0.3', '2.675', '1.005', '-99999999999999.9', '5e-324',
    '1.5e3', '0.1e1', '100.0', '-7.000000000000001');
var
  k, i: Integer;
  s: string;
  a, b: TJSONData;
  ea, eb: TTyOptionError;
  seed: LongWord;

  function R(N: Integer): Integer;
  begin
    seed := seed xor (seed shl 13);
    seed := seed xor (seed shr 17);
    seed := seed xor (seed shl 5);
    Result := seed mod LongWord(N);
  end;

  procedure Check(const AText: string);
  var j: Integer; fa, fb: Double;
  begin
    a := nil;
    b := nil;
    TyJsonFastForTest(True);
    AssertTrue('fast: ' + AText, TyOptionParseRaw(AText, a, ea));
    TyJsonFastForTest(False);
    AssertTrue('long: ' + AText, TyOptionParseRaw(AText, b, eb));
    TyJsonFastForTest(True);
    try
      AssertEquals('as many: ' + AText, b.Count, a.Count);
      for j := 0 to a.Count - 1 do
      begin
        AssertEquals('the same kind: ' + TJSONArray(b).Items[j].AsJSON,
          TJSONArray(b).Items[j].ClassName, TJSONArray(a).Items[j].ClassName);
        fa := TJSONArray(a).Items[j].AsFloat;
        fb := TJSONArray(b).Items[j].AsFloat;
        AssertEquals('the same bits: ' + TJSONArray(b).Items[j].AsJSON, Bits(fb), Bits(fa));
      end;
    finally
      a.Free;
      b.Free;
    end;
  end;

begin
  s := '[';
  for k := 0 to High(cTexts) do
  begin
    if k > 0 then s := s + ',';
    s := s + cTexts[k];
  end;
  Check(s + ']');
  { and random ones: sign, integer part, fraction, sometimes leading noughts }
  seed := 2463534242;
  for k := 0 to 49 do
  begin
    s := '[';
    for i := 0 to 199 do
    begin
      if i > 0 then s := s + ',';
      if R(2) = 0 then s := s + '-';
      case R(3) of
        0: s := s + '0.' + StringOfChar('0', R(12));
        1: s := s + IntToStr(R(100000)) + '.';
      else
        s := s + IntToStr(100000000 + R(900000000)) + IntToStr(R(10000)) + '.';
      end;
      s := s + IntToStr(R(1000000)) + StringOfChar('0', R(4));
    end;
    Check(s + ']');
  end;
end;

function SameD(const A, B: TTyDoubleArray): Boolean;
begin
  Result := (Length(A) = Length(B))
    and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A) * SizeOf(Double)));
end;

procedure TAdvChartSpeedKeepTest.TestATraceIsKeptByItsInk;
var
  m: array[0..3] of TBGRABitmap;
  fresh: array[0..3] of TTyDoubleArray;
  got: TTyDoubleArray;
  k, h0, collide: Integer;
begin
  { an ellipse and a stroke of ink; the same moved by (3, 2); the first with
    one pixel's alpha a step off; the first at scale 2 }
  for k := 0 to 3 do
  begin
    m[k] := TBGRABitmap.Create(64, 48, BGRAPixelTransparent);
    if k = 1 then
    begin
      m[k].FillEllipseAntialias(27.3, 20.6, 14.2, 9.7, BGRAWhite);
      m[k].DrawLineAntialias(9, 34, 51, 41, BGRAWhite, 2.5);
    end
    else
    begin
      m[k].FillEllipseAntialias(24.3, 18.6, 14.2, 9.7, BGRAWhite);
      m[k].DrawLineAntialias(6, 32, 48, 39, BGRAWhite, 2.5);
    end;
  end;
  { a pixel on the ellipse's edge, a little more covered }
  m[2].ScanLine[18][38].alpha := m[2].ScanLine[18][38].alpha + 9;
  try
    for collide := 0 to 1 do
    begin
      TyAdvChartTraceKeepForTest(False);
      for k := 0 to 3 do fresh[k] := TyTraceMaskOutlineForTest(m[k], 1 + Ord(k = 3));
      AssertFalse('the moved ink is another outline', SameD(fresh[0], fresh[1]));
      AssertFalse('the changed pixel is another outline', SameD(fresh[0], fresh[2]));
      AssertFalse('the scale is another outline', SameD(fresh[0], fresh[3]));
      TyAdvChartTraceKeepForTest(True, collide = 1);
      h0 := TyAdvChartTraceKeptHitsForTest;
      AssertTrue('traced', SameD(fresh[0], TyTraceMaskOutlineForTest(m[0], 1)));
      AssertEquals('nothing kept yet', h0, TyAdvChartTraceKeptHitsForTest);
      got := TyTraceMaskOutlineForTest(m[0], 1);
      AssertEquals('the same ink is kept', h0 + 1, TyAdvChartTraceKeptHitsForTest);
      AssertTrue('the kept outline', SameD(fresh[0], got));
      for k := 1 to 3 do
      begin
        AssertTrue(Format('case %d, collide %d: as a fresh trace', [k, collide]),
          SameD(fresh[k], TyTraceMaskOutlineForTest(m[k], 1 + Ord(k = 3))));
        AssertTrue(Format('case %d, collide %d: kept as it is', [k, collide]),
          SameD(fresh[k], TyTraceMaskOutlineForTest(m[k], 1 + Ord(k = 3))));
      end;
      AssertEquals('each kept once met again', h0 + 4, TyAdvChartTraceKeptHitsForTest);
      AssertTrue('the first still its own', SameD(fresh[0], TyTraceMaskOutlineForTest(m[0], 1)));
    end;
  finally
    TyAdvChartTraceKeepForTest(True);
    for k := 0 to 3 do m[k].Free;
  end;
end;

procedure TAdvChartSpeedKeepTest.TestNoRecordIsCarriedWhereNoneWasKept;
var
  chart: TSkChart;
  bmp: TBitmap;
  big, small: string;
  i, d0: Integer;

  function Opt(const AData: string; ALarge: Boolean): string;
  begin
    Result := '{"animation":false,"xAxis":{},"yAxis":{},"series":[{"type":"scatter","id":"s",'
      + '"large":' + BoolToStr(ALarge, 'true', 'false') + ',"largeThreshold":100,'
      + '"emphasis":{"itemStyle":{"color":"#f00"}},"data":[' + AData + ']}]}';
  end;

begin
  big := '';
  for i := 0 to 2999 do
  begin
    if i > 0 then big := big + ',';
    big := big + Format('[%d,%d]', [i, (i * 37) mod 100]);
  end;
  small := '[1,1],[2,5],[3,2],[4,8]';
  bmp := TBitmap.Create;
  chart := TSkChart.Create(FForm);
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(400, 300);
    chart.Parent := FForm;
    chart.Controller := FCtl;
    chart.AnimationMode := camOff;
    chart.SetBounds(0, 0, 400, 300);
    { large: no record kept, none carried, twice over }
    chart.Option := Opt(big, True);
    chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
    d0 := TyAdvChartStCarryDiffsForTest;
    chart.Option := Opt(big + ',[3000,5]', True);
    chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
    chart.Option := Opt(big + ',[3000,6]', True);
    chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
    AssertEquals('a large series carries nothing', d0, TyAdvChartStCarryDiffsForTest);
    AssertEquals('and keeps no record', 0, chart.StRowRecordsForTest(0));
    { small: its records carried -- the highlighted row stays highlighted }
    chart.Option := Opt(small, False);
    chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
    chart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":1}');
    chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
    d0 := TyAdvChartStCarryDiffsForTest;
    chart.Option := Opt(small + ',[5,3]', False);
    chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
    AssertEquals('a hosted series carries its records', d0 + 1, TyAdvChartStCarryDiffsForTest);
    AssertTrue('records kept', chart.StRowRecordsForTest(0) > 0);
  finally
    chart.Free;
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartSpeedKeepTest);
end.
