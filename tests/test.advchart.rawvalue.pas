unit test.advchart.rawvalue;
{$mode objfpc}{$H+}
{ A raw value written as text, read the way upstream reads it -- held to the
  bit.

  tools/advchart-oracle/raw-value.js runs ECharts 6.1's numericToNumber and
  addCommas over 133 hand-picked strings and 500 drawn ones, and records the
  number each one reads as and the tooltip cell that number prints as.

  THE RULES IT HOLDS THE PORT TO: JavaScript's white space is wider than
  Trim's (no-break space, U+FEFF, the space separators); Number() takes the
  whole string or nothing, '' as nought, 0x / 0o / 0b integers; parseFloat()
  takes the longest decimal prefix; numericToNumber keeps parseFloat only
  when Number agrees -- and never a nought read off a string with an `x` past
  its first character. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Data;
type
  TAdvChartRawValueOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryStringReadsAsUpstreamReadsIt;
    procedure TestNumberAndParseFloatApart;
    procedure TestEveryDoubleReadsBackFromItsOwnText;
    procedure TestARawItemPrintsAsString;
    procedure TestAKeyFindsItsPosition;
    procedure TestACellReadsAsItsDimensionSays;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-raw-value.json';
end;

function HexNum(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Result := 0;
  Move(q, Result, SizeOf(Result));
end;

function BitsOf(A: Double): QWord;
begin
  Result := 0;
  Move(A, Result, SizeOf(Result));
end;

function Txt(const AText: string): TTyDataValue;
begin
  Result := Default(TTyDataValue);
  Result.Kind := dvkText;
  Result.Text := AText;
end;

function Num(A: Double): TTyDataValue;
begin
  Result := Default(TTyDataValue);
  Result.Kind := dvkNumber;
  Result.Num := A;
end;

procedure TAdvChartRawValueOracleTest.SetUp;
var sl: TStringList;
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
end;

procedure TAdvChartRawValueOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartRawValueOracleTest.TestEveryStringReadsAsUpstreamReadsIt;
var
  recs: TJSONArray;
  r: TJSONObject;
  i, bad, nans, infs, commas: Integer;
  got, want: Double;
  cell, report: string;
  mask: TFPUExceptionMask;
begin
  recs := TJSONObject(FRoot).Arrays['records'];
  AssertEquals('every record is there', 633, recs.Count);
  bad := 0;
  nans := 0;
  infs := 0;
  commas := 0;
  report := '';
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    for i := 0 to recs.Count - 1 do
    begin
      r := recs.Objects[i];
      want := HexNum(r.Strings['nBits']);
      got := TyJsNumericToNumber(Txt(r.Strings['in']));
      if IsNan(want) then Inc(nans)
      else if IsInfinite(want) then Inc(infs);
      { To the bit -- minus nought is not nought -- and not-a-number as
        itself, whatever its payload. }
      if not ((IsNan(want) and IsNan(got)) or (BitsOf(got) = BitsOf(want))) then
      begin
        Inc(bad);
        if bad <= 30 then
          report := report + LineEnding + Format('  [%d] %s: got %s (%.16x), want %s',
            [i, StringReplace(r.Strings['in'], #10, '\n', [rfReplaceAll]),
             TyJsNumberToString(got), BitsOf(got), r.Strings['nText']]);
        Continue;
      end;
      if TyJsNumberToString(got) <> r.Strings['nText'] then
      begin
        Inc(bad);
        if bad <= 30 then
          report := report + LineEnding + Format('  [%d] String(n) %s, want %s',
            [i, TyJsNumberToString(got), r.Strings['nText']]);
      end;
      if r.Find('cell').JSONType <> jtNull then
      begin
        cell := TyJsAddCommas(TyJsNumberToString(got));
        if Pos(',', cell) > 0 then Inc(commas);
        if cell <> r.Strings['cell'] then
        begin
          Inc(bad);
          if bad <= 30 then
            report := report + LineEnding + Format('  [%d] cell %s, want %s',
              [i, cell, r.Strings['cell']]);
        end;
      end;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
  AssertEquals('every string reads as upstream reads it:' + report, 0, bad);
  { The fixture bites where it says it does. }
  AssertTrue('not-a-number rows', nans >= 50);
  AssertTrue('infinite rows', infs >= 10);
  AssertTrue('cells with a comma', commas >= 20);
end;

procedure TAdvChartRawValueOracleTest.TestNumberAndParseFloatApart;
const
  NBSP = #$C2#$A0;
  BOM = #$EF#$BB#$BF;
  MONGOLIAN = #$E1#$A0#$8E; // U+180E is no longer white space
var mask: TFPUExceptionMask;
begin
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    { Number(): the whole string, or nothing. }
    AssertEquals('Number('''') is nought', 0, TyJsToNumber(''));
    AssertEquals('Number('' '') is nought', 0, TyJsToNumber(' '));
    AssertTrue('Number(''12px'') is NaN', IsNan(TyJsToNumber('12px')));
    AssertEquals('Number(0x10)', 16, TyJsToNumber('0x10'));
    AssertEquals('Number(0XfF)', 255, TyJsToNumber('0XfF'));
    AssertEquals('Number(0o17)', 15, TyJsToNumber('0o17'));
    AssertEquals('Number(0b101)', 5, TyJsToNumber('0b101'));
    AssertTrue('Number(0b2) is NaN', IsNan(TyJsToNumber('0b2')));
    AssertTrue('Number(-0x10) is NaN', IsNan(TyJsToNumber('-0x10')));
    AssertTrue('Number(0x) is NaN', IsNan(TyJsToNumber('0x')));
    AssertEquals('Number(NBSP 12 BOM)', 12, TyJsToNumber(NBSP + '12' + BOM));
    AssertTrue('U+180E is no white space', IsNan(TyJsToNumber(MONGOLIAN + '1')));
    AssertTrue('Number(-Infinity)', IsInfinite(TyJsToNumber('-Infinity'))
      and (TyJsToNumber('-Infinity') < 0));
    AssertTrue('Number(infinity) is NaN', IsNan(TyJsToNumber('infinity')));
    AssertTrue('Number(1e) is NaN', IsNan(TyJsToNumber('1e')));
    AssertTrue('Number(.) is NaN', IsNan(TyJsToNumber('.')));
    AssertEquals('Number(.5)', 0.5, TyJsToNumber('.5'));
    AssertEquals('Number(5.)', 5, TyJsToNumber('5.'));
    AssertTrue('Number(-0) is minus nought', BitsOf(TyJsToNumber('-0')) = QWord($8000000000000000));
    AssertTrue('Number(1e400) overflows', IsInfinite(TyJsToNumber('1e400')));
    AssertEquals('Number(1e-400) underflows', 0, TyJsToNumber('1e-400'));
    { parseFloat(): the longest prefix; no radix; the tail unread. }
    AssertEquals('parseFloat(12px)', 12, TyJsParseFloat('12px'));
    AssertEquals('parseFloat(1e)', 1, TyJsParseFloat('1e'));
    AssertEquals('parseFloat(1e+)', 1, TyJsParseFloat('1e+'));
    AssertEquals('parseFloat(0x10)', 0, TyJsParseFloat('0x10'));
    AssertTrue('parseFloat('''') is NaN', IsNan(TyJsParseFloat('')));
    AssertTrue('parseFloat(.) is NaN', IsNan(TyJsParseFloat('.')));
    AssertTrue('parseFloat(Infinityx)', IsInfinite(TyJsParseFloat(' Infinityx')));
    AssertEquals('parseFloat keeps no trailing space', 3, TyJsParseFloat(NBSP + '3 ' + NBSP));
    { numericToNumber on what is not text. }
    AssertEquals('a number is itself', 7.25, TyJsNumericToNumber(Num(7.25)));
    AssertTrue('a minus nought is nought',
      BitsOf(TyJsNumericToNumber(Num(-0.0))) = 0);
    AssertTrue('a boolean is NaN', IsNan(TyJsNumericToNumber(Default(TTyDataValue))));
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ Number(String(x)) is x, to the bit, for every Double -- the shortest text
  a Double prints as is the one that reads back to it, so a reader off by a
  unit anywhere shows here: normals, denormals, the half-way cases around
  them, the extremes. }
procedure TAdvChartRawValueOracleTest.TestEveryDoubleReadsBackFromItsOwnText;
var
  seed, bits, back: QWord;
  i, bad: Integer;
  x, y: Double;
  txt, report: string;
  mask: TFPUExceptionMask;
begin
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exUnderflow, exZeroDivide, exPrecision]);
  seed := QWord($9E3779B97F4A7C15);
  bad := 0;
  report := '';
  try
    for i := 0 to 19999 do
    begin
      seed := seed xor (seed shl 13);
      seed := seed xor (seed shr 7);
      seed := seed xor (seed shl 17);
      bits := seed;
      { A quarter of them denormal or near the bottom, a few at the top. }
      case i mod 8 of
        0: bits := bits and $000FFFFFFFFFFFFF;
        1: bits := (bits and $800FFFFFFFFFFFFF) or $0010000000000000;
        2: bits := (bits and $800FFFFFFFFFFFFF) or $7FE0000000000000;
      end;
      if i = 0 then bits := 1;
      if i = 1 then bits := $7FEFFFFFFFFFFFFF;
      if i = 2 then bits := $000FFFFFFFFFFFFF;
      x := 0;
      Move(bits, x, SizeOf(x));
      if IsNan(x) or IsInfinite(x) then Continue;
      txt := TyJsNumberToString(x);
      y := TyJsToNumber(txt);
      back := 0;
      Move(y, back, SizeOf(y));
      if (back <> bits) and not ((x = 0) and (y = 0)) then
      begin
        Inc(bad);
        if bad <= 20 then
          report := report + LineEnding + Format('  %.16x -> %s -> %.16x', [bits, txt, back]);
      end;
      { parseFloat reads the same text the same way. }
      y := TyJsParseFloat(txt + 'px');
      Move(y, back, SizeOf(y));
      if (back <> bits) and not ((x = 0) and (y = 0)) then
      begin
        Inc(bad);
        if bad <= 20 then
          report := report + LineEnding + Format('  parseFloat %s -> %.16x', [txt, back]);
      end;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
  AssertEquals('every Double reads back from its own text:' + report, 0, bad);
end;

procedure TAdvChartRawValueOracleTest.TestARawItemPrintsAsString;
var it: TTyRawItem; b: TTyDataValue;
begin
  it := Default(TTyRawItem);
  AssertEquals('nothing kept', '', TyRawItemText(it));
  it.Shape := rshAbsent;
  AssertEquals('absent', 'undefined', TyRawItemText(it));
  it.Shape := rshNull;
  AssertEquals('null', 'null', TyRawItemText(it));
  it.Shape := rshObject;
  AssertEquals('object', '[object Object]', TyRawItemText(it));
  it.Shape := rshScalar;
  it.Scalar := Txt(' 12 ');
  AssertEquals('text verbatim', ' 12 ', TyRawItemText(it));
  it.Shape := rshArray;
  b := Default(TTyDataValue);
  b.Kind := dvkBool;
  b.Num := 1;
  it.Cells := [Num(1.5), Default(TTyDataValue), Txt('x'), b];
  AssertEquals('cells joined, a gap as nothing', '1.5,,x,true', TyRawItemText(it));
  AssertEquals('a gap in its own place', '-', TyJsValueText(Default(TTyDataValue), '-'));
end;

procedure TAdvChartRawValueOracleTest.TestAKeyFindsItsPosition;
var
  s: TTyDataStore;
  it: TTyRawItem;
  c: TTyDataValue;
  mask: TFPUExceptionMask;
begin
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  s := TTyDataStore.Create;
  try
    s.SetRawDimName(0, 'x');
    s.SetRawDimName(2, 'value1');
    AssertEquals('a declared name', 0, s.RawPosOf('x'));
    AssertEquals('a later name', 2, s.RawPosOf('value1'));
    AssertEquals('`[n]` is a position', 3, s.RawPosOf('[3]'));
    AssertEquals('`[]` is nought', 0, s.RawPosOf('[]'));
    AssertEquals('a numeric-looking key', 1, s.RawPosOf('1'));
    AssertEquals('a numeric-looking key with space', 1, s.RawPosOf(' 1 '));
    AssertTrue('an unknown name', IsNan(s.RawPosOf('nope')));
    AssertTrue('`[a]` is not-a-number', IsNan(s.RawPosOf('[a]')));
    it := Default(TTyRawItem);
    it.Shape := rshArray;
    it.Cells := [Num(10), Num(20), Num(30)];
    AssertTrue('an array cell', TTyDataStore.RawCell(it, 1, c) and (c.Num = 20));
    AssertFalse('past the end', TTyDataStore.RawCell(it, 3, c));
    AssertFalse('a fraction', TTyDataStore.RawCell(it, 0.5, c));
    AssertFalse('not-a-number', TTyDataStore.RawCell(it, NaN, c));
    AssertFalse('below nought', TTyDataStore.RawCell(it, -1, c));
    it.Shape := rshScalar;
    it.Scalar := Num(5);
    AssertTrue('a scalar answers any key', TTyDataStore.RawCell(it, NaN, c) and (c.Num = 5));
    it.Shape := rshNull;
    AssertFalse('null answers no key', TTyDataStore.RawCell(it, 0, c));
  finally
    s.Free;
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ makeValueReadable by dimension type. An ORDINAL cell is never parsed: its
  text as written ('-' when blank), a finite number without commas. Any
  other type goes through numericToNumber first. }
procedure TAdvChartRawValueOracleTest.TestACellReadsAsItsDimensionSays;
var b: TTyDataValue;
begin
  b := Default(TTyDataValue);
  b.Kind := dvkBool;
  b.Num := 1;
  AssertEquals('an ordinal text', '12.50', TyReadableCell(Txt('12.50'), ddtOrdinal));
  AssertEquals('an ordinal blank', '-', TyReadableCell(Txt(' '), ddtOrdinal));
  AssertEquals('an ordinal number, no commas', '1234.5', TyReadableCell(Num(1234.5), ddtOrdinal));
  AssertEquals('an ordinal infinity', '-', TyReadableCell(Num(Infinity), ddtOrdinal));
  AssertEquals('an ordinal boolean', '-', TyReadableCell(b, ddtOrdinal));
  AssertEquals('a float text, parsed', '12.5', TyReadableCell(Txt('12.50'), ddtFloat));
  AssertEquals('a float number, commas', '1,234.5', TyReadableCell(Num(1234.5), ddtFloat));
  AssertEquals('a float text that is no number', 'abc', TyReadableCell(Txt('abc'), ddtFloat));
  AssertEquals('a float blank', '-', TyReadableCell(Txt(#9), ddtFloat));
  AssertEquals('a float boolean', 'true', TyReadableCell(b, ddtFloat));
  AssertEquals('a gap', '-', TyReadableCell(Default(TTyDataValue), ddtFloat));
end;

initialization
  RegisterTest(TAdvChartRawValueOracleTest);
end.
