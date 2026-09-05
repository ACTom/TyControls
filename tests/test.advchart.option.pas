unit test.advchart.option;
{$mode objfpc}{$H+}
{ The option tree -- the chart's API.

  The tests that matter are the relaxed-syntax ones and the failure behaviour.
  Path lookup is ordinary and mostly proves itself; what would quietly ruin the
  product is a parser that rejects the configs people actually paste, or one that
  blanks a chart because someone was mid-keystroke. }
interface
uses Classes, SysUtils, fpjson, fpcunit, testregistry, tyControls.AdvChart.Option;
type
  TAdvChartOptionTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { ---- the relaxed syntax people actually paste ---- }
    procedure TestStrictJsonStillWorks;
    procedure TestUnquotedKeys;
    procedure TestSingleQuotedStringsAndKeys;
    procedure TestTrailingCommas;
    procedure TestLineAndBlockComments;
    procedure TestARealisticEChartsConfig;
    { ---- failure behaviour ---- }
    procedure TestAFunctionValueIsRejectedWithAUsefulMessage;
    procedure TestARejectedOptionLeavesNoOption;
    procedure TestErrorCarriesAPosition;
    procedure TestEmptyTextIsNotAnError;
    procedure TestASuccessfulSetClearsAPreviousError;
    { ---- path lookup ---- }
    procedure TestDottedPath;
    procedure TestArrayIndex;
    procedure TestNestedArrayThenObject;
    procedure TestMissingPathIsNilNotAnError;
    procedure TestIndexOutOfRangeIsNil;
    procedure TestIndexingANonArrayIsNil;
    { ---- typed reads ---- }
    procedure TestTypedDefaultsWhenAbsent;
    procedure TestTypedDefaultsOnTheWrongType;
    procedure TestNumbersReadAsIntAndFloat;
    procedure TestCountAt;
    procedure TestABareComponentIsOneComponent;
    procedure TestAComponentArrayStillCounts;
    procedure TestAnAbsentOrNullComponentIsNone;
    procedure TestComponentAtIndexesBothForms;
    { ---- lifetime ---- }
    procedure TestRepeatedSetDoesNotGrowTheHeap;
    procedure TestAdjacentUnicodeEscapesSurviveIntact;
    procedure TestABackslashBeforeUIsNotAnEscape;
  end;
implementation

procedure TAdvChartOptionTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
end;

procedure TAdvChartOptionTest.TearDown;
begin
  FreeAndNil(FOpt);
  inherited TearDown;
end;

{ ================= the relaxed syntax people actually paste ================= }

procedure TAdvChartOptionTest.TestStrictJsonStillWorks;
begin
  AssertTrue('parsed', FOpt.SetOptionText('{"title":{"text":"Hi"}}'));
  AssertEquals('Hi', FOpt.GetStr('title.text', ''));
end;

procedure TAdvChartOptionTest.TestUnquotedKeys;
begin
  { A JS object literal, which is what every ECharts example is. }
  AssertTrue('parsed', FOpt.SetOptionText('{ title: { text: "Hi" } }'));
  AssertEquals('Hi', FOpt.GetStr('title.text', ''));
end;

procedure TAdvChartOptionTest.TestSingleQuotedStringsAndKeys;
begin
  AssertTrue('parsed', FOpt.SetOptionText('{ ''xAxis'': { type: ''category'' } }'));
  AssertEquals('category', FOpt.GetStr('xAxis.type', ''));
end;

procedure TAdvChartOptionTest.TestTrailingCommas;
begin
  AssertTrue('parsed', FOpt.SetOptionText('{ series: [{ type: ''bar'', }], }'));
  AssertEquals('bar', FOpt.GetStr('series[0].type', ''));
end;

procedure TAdvChartOptionTest.TestLineAndBlockComments;
begin
  AssertTrue('line comment', FOpt.SetOptionText(
    '{ a: 1 // the answer' + LineEnding + '}'));
  AssertEquals('a', 1, FOpt.GetInt('a', 0));
  AssertTrue('block comment', FOpt.SetOptionText('{ /* hi */ b: 2 }'));
  AssertEquals('b', 2, FOpt.GetInt('b', 0));
end;

procedure TAdvChartOptionTest.TestARealisticEChartsConfig;
begin
  { Pasted in the shape the documentation writes it. If this fails, the entire
    reason for choosing an option tree over published properties is gone. }
  AssertTrue('parsed', FOpt.SetOptionText(
    '{' + LineEnding +
    '  xAxis: { type: ''category'', data: [''Mon'', ''Tue'', ''Wed''] },' + LineEnding +
    '  yAxis: { type: ''value'' },' + LineEnding +
    '  series: [{ name: ''Sales'', type: ''bar'', data: [120, 200, 150] }]' + LineEnding +
    '}'));
  AssertEquals('axis type', 'category', FOpt.GetStr('xAxis.type', ''));
  AssertEquals('category count', 3, FOpt.CountAt('xAxis.data'));
  AssertEquals('series name', 'Sales', FOpt.GetStr('series[0].name', ''));
  AssertEquals('a datum', 200, FOpt.GetInt('series[0].data[1]', 0));
end;

{ ========================= failure behaviour ========================= }

procedure TAdvChartOptionTest.TestAFunctionValueIsRejectedWithAUsefulMessage;
begin
  AssertFalse('rejected', FOpt.SetOptionText(
    '{ tooltip: { formatter: function(p){ return p.name; } } }'));
  AssertTrue('flagged', FOpt.Error.Failed);
  { A bare "unexpected token" leaves the user with no idea what to do. The two
    things they CAN write have to be in the message. }
  AssertTrue('mentions a template string, got: ' + FOpt.Error.Message,
             Pos('{b}', FOpt.Error.Message) > 0);
  AssertTrue('mentions a registered handler',
             Pos('@', FOpt.Error.Message) > 0);
end;

procedure TAdvChartOptionTest.TestARejectedOptionLeavesNoOption;
begin
  AssertTrue('first one takes', FOpt.SetOptionText('{ title: { text: ''Good'' } }'));
  AssertEquals('and reads back', 'Good', FOpt.GetStr('title.text', ''));

  AssertFalse('second is rejected', FOpt.SetOptionText('{ title: { text: '));
  { The tree GOES. Keeping the last good one meant the option said one thing
    while anything reading it got another, with nothing to tell them apart --
    and the reason for it (an editor re-applying text on every keystroke) is
    not how the editor was built. }
  AssertEquals('the previous option is gone', '',
               FOpt.GetStr('title.text', ''));
  AssertTrue('and the error says why', FOpt.Error.Failed);
end;

procedure TAdvChartOptionTest.TestErrorCarriesAPosition;
begin
  AssertFalse('rejected', FOpt.SetOptionText('{ a: 1,' + LineEnding + '  b: }'));
  AssertTrue('a line was extracted, got ' + IntToStr(FOpt.Error.Line),
             FOpt.Error.Line > 0);
end;

procedure TAdvChartOptionTest.TestEmptyTextIsNotAnError;
begin
  AssertTrue('empty is fine', FOpt.SetOptionText(''));
  AssertFalse('and not an error', FOpt.Error.Failed);
  AssertTrue('whitespace too', FOpt.SetOptionText('   ' + LineEnding));
  AssertFalse('still not an error', FOpt.Error.Failed);
end;

procedure TAdvChartOptionTest.TestASuccessfulSetClearsAPreviousError;
begin
  AssertFalse('bad', FOpt.SetOptionText('{ oops'));
  AssertTrue('flagged', FOpt.Error.Failed);
  AssertTrue('good', FOpt.SetOptionText('{ a: 1 }'));
  AssertFalse('the error is gone', FOpt.Error.Failed);
  AssertEquals('and the message with it', '', FOpt.Error.Message);
end;

{ ============================ path lookup ============================ }

procedure TAdvChartOptionTest.TestDottedPath;
begin
  FOpt.SetOptionText('{ a: { b: { c: 42 } } }');
  AssertEquals('three deep', 42, FOpt.GetInt('a.b.c', 0));
end;

procedure TAdvChartOptionTest.TestArrayIndex;
begin
  FOpt.SetOptionText('{ series: [{n:1},{n:2},{n:3}] }');
  AssertEquals('second', 2, FOpt.GetInt('series[1].n', 0));
end;

procedure TAdvChartOptionTest.TestNestedArrayThenObject;
begin
  FOpt.SetOptionText('{ grid: [{ left: 10 }, { left: 20 }] }');
  AssertEquals('second grid', 20, FOpt.GetInt('grid[1].left', 0));
end;

procedure TAdvChartOptionTest.TestMissingPathIsNilNotAnError;
begin
  FOpt.SetOptionText('{ a: 1 }');
  AssertFalse('absent', FOpt.Has('b.c.d'));
  { An option nobody set is the normal case, not a fault -- most of the ~1,950
    paths are absent in any real config. }
  AssertFalse('and no error was raised', FOpt.Error.Failed);
end;

procedure TAdvChartOptionTest.TestIndexOutOfRangeIsNil;
begin
  FOpt.SetOptionText('{ series: [{n:1}] }');
  AssertFalse('past the end', FOpt.Has('series[5].n'));
  AssertEquals('and reads as the default', 99, FOpt.GetInt('series[5].n', 99));
end;

procedure TAdvChartOptionTest.TestIndexingANonArrayIsNil;
begin
  FOpt.SetOptionText('{ series: { n: 1 } }');
  AssertFalse('subscripting an object', FOpt.Has('series[0].n'));
end;

{ ============================ typed reads ============================ }

procedure TAdvChartOptionTest.TestTypedDefaultsWhenAbsent;
begin
  FOpt.SetOptionText('{ }');
  AssertEquals('str', 'line', FOpt.GetStr('series[0].type', 'line'));
  AssertEquals('int', 60, FOpt.GetInt('grid.left', 60));
  AssertEquals('float', 1.5, FOpt.GetFloat('lineStyle.width', 1.5), 1e-9);
  AssertTrue('bool', FOpt.GetBool('legend.show', True));
end;

procedure TAdvChartOptionTest.TestTypedDefaultsOnTheWrongType;
begin
  { A config that says grid.left is an object is wrong, but a chart still has to
    draw. Falling back beats raising in the middle of a paint. }
  FOpt.SetOptionText('{ grid: { left: { oops: 1 } }, n: "text" }');
  AssertEquals('object where a number was wanted', 60, FOpt.GetInt('grid.left', 60));
  AssertEquals('text where a number was wanted', 7, FOpt.GetInt('n', 7));
  AssertEquals('and float likewise', 2.5, FOpt.GetFloat('n', 2.5), 1e-9);
end;

procedure TAdvChartOptionTest.TestNumbersReadAsIntAndFloat;
begin
  FOpt.SetOptionText('{ a: 10, b: 2.75 }');
  AssertEquals('int', 10, FOpt.GetInt('a', 0));
  AssertEquals('float of an int', 10.0, FOpt.GetFloat('a', 0), 1e-9);
  AssertEquals('float', 2.75, FOpt.GetFloat('b', 0), 1e-9);
end;

procedure TAdvChartOptionTest.TestABareComponentIsOneComponent;
begin
  { `xAxis: {...}` and `xAxis: [{...}]` are the same option -- ECharts
    normalises before anything reads it, and most of its gallery writes the bare
    form. Counting it as zero is not a wrong number, it is a chart that draws
    nothing and says nothing about why. }
  AssertTrue(FOpt.SetOptionText('{ xAxis: { type: ''category'' }, series: { type: ''bar'' } }'));
  AssertEquals('one x axis', 1, FOpt.ComponentCount('xAxis'));
  AssertEquals('one series', 1, FOpt.ComponentCount('series'));
  AssertEquals('and CountAt still says an object is not an array',
    0, FOpt.CountAt('xAxis'));
end;

procedure TAdvChartOptionTest.TestAComponentArrayStillCounts;
begin
  AssertTrue(FOpt.SetOptionText('{ yAxis: [{}, {}], series: [{}, {}, {}] }'));
  AssertEquals(2, FOpt.ComponentCount('yAxis'));
  AssertEquals(3, FOpt.ComponentCount('series'));
end;

procedure TAdvChartOptionTest.TestAnAbsentOrNullComponentIsNone;
begin
  { `xAxis: null` is written, but written as nothing -- distinguishing it from
    absent would make a difference no caller can act on. }
  AssertTrue(FOpt.SetOptionText('{ xAxis: null, series: [] }'));
  AssertEquals('null', 0, FOpt.ComponentCount('xAxis'));
  AssertEquals('empty array', 0, FOpt.ComponentCount('series'));
  AssertEquals('absent', 0, FOpt.ComponentCount('grid'));
  AssertTrue('and nothing to index', FOpt.ComponentAt('xAxis', 0) = nil);
end;

procedure TAdvChartOptionTest.TestComponentAtIndexesBothForms;
var d: TJSONData;
begin
  AssertTrue(FOpt.SetOptionText('{ xAxis: { type: ''category'' }, yAxis: [{ type: ''value'' }, { type: ''log'' }] }'));
  d := FOpt.ComponentAt('xAxis', 0);
  AssertTrue('the bare object is index 0', d <> nil);
  AssertEquals('category', TJSONObject(d).Get('type', ''));
  AssertTrue('and there is no index 1', FOpt.ComponentAt('xAxis', 1) = nil);
  d := FOpt.ComponentAt('yAxis', 1);
  AssertTrue('the array indexes normally', d <> nil);
  AssertEquals('log', TJSONObject(d).Get('type', ''));
  AssertTrue('past the end is nothing', FOpt.ComponentAt('yAxis', 2) = nil);
  AssertTrue('and so is a negative index', FOpt.ComponentAt('yAxis', -1) = nil);
end;

procedure TAdvChartOptionTest.TestCountAt;
begin
  FOpt.SetOptionText('{ series: [{},{},{}], title: {} }');
  AssertEquals('three series', 3, FOpt.CountAt('series'));
  AssertEquals('an object is not an array', 0, FOpt.CountAt('title'));
  AssertEquals('and an absent path is none', 0, FOpt.CountAt('nope'));
end;

procedure TAdvChartOptionTest.TestRepeatedSetDoesNotGrowTheHeap;
var
  cfg: string;
  i: Integer;
  before, after: PtrUInt;
begin
  { Replacing the option is the hot path -- it is what happens every time a chart
    is reconfigured, and in a design-time editor it happens on a timer while
    someone types. Dropping the previous tree without freeing it leaks a whole
    parse per keystroke.

    Nothing else in this suite looks at memory (there is no heaptrc here), and
    mutation proved it: removing the FreeAndNil left every other test green. So
    this is the one place that watches, and it watches the case that matters. }
  cfg := '{ series: [{ type: ''bar'', data: [';
  for i := 0 to 199 do
  begin
    if i > 0 then cfg := cfg + ',';
    cfg := cfg + IntToStr(i);
  end;
  cfg := cfg + '] }] }';

  { Warm up first, so one-off allocations (the parser's own buffers, the
    string) are not counted as growth. }
  for i := 1 to 20 do
    FOpt.SetOptionText(cfg);
  before := GetFPCHeapStatus.CurrHeapUsed;
  for i := 1 to 200 do
    FOpt.SetOptionText(cfg);
  after := GetFPCHeapStatus.CurrHeapUsed;

  AssertEquals('the option still parsed', 200, FOpt.CountAt('series[0].data'));
  { A leaked tree is several KB; 200 of them is megabytes. A generous bound, so
    this fails on the bug and not on allocator noise. }
  AssertTrue('heap did not grow with the replacements (before='
             + IntToStr(before) + ' after=' + IntToStr(after) + ')',
             after < before + 512 * 1024);
end;

procedure TAdvChartOptionTest.TestAdjacentUnicodeEscapesSurviveIntact;
var
  o: TTyChartOption;
begin
  { TWO ESCAPES IN A ROW is what every CJK string written in \u form looks
    like, and FPC 3.2.2's json scanner loses bytes across that boundary: the
    second escape overwrites the tail of the first, so a two-character Chinese
    title came back four bytes long instead of six. One ASCII character between
    them and it decodes correctly, which is exactly why nothing caught it. }
  o := TTyChartOption.Create;
  try
    AssertTrue(o.SetOptionText('{ "title": { "text": "\u4e2d\u6587" } }'));
    AssertEquals('two adjacent escapes decode to both characters',
      #$E4#$B8#$AD#$E6#$96#$87, o.GetStr('title.text', ''));

    { The case that always worked, so the fix is not just moving the failure. }
    AssertTrue(o.SetOptionText('{ "title": { "text": "A\u4e2dB\u6587C" } }'));
    AssertEquals('A' + #$E4#$B8#$AD + 'B' + #$E6#$96#$87 + 'C',
      o.GetStr('title.text', ''));

    { Three in a row, since the bug is about the boundary between them. }
    AssertTrue(o.SetOptionText('{ "title": { "text": "\u4e2d\u6587\u5b57" } }'));
    AssertEquals(#$E4#$B8#$AD#$E6#$96#$87#$E5#$AD#$97,
      o.GetStr('title.text', ''));

    { A surrogate pair is ONE character, not two halves encoded separately. }
    AssertTrue(o.SetOptionText('{ "title": { "text": "\ud83d\udcc8" } }'));
    AssertEquals('a surrogate pair joins into one codepoint',
      #$F0#$9F#$93#$88, o.GetStr('title.text', ''));
  finally
    o.Free;
  end;
end;

procedure TAdvChartOptionTest.TestABackslashBeforeUIsNotAnEscape;
var
  o: TTyChartOption;
begin
  { A DOUBLED BACKSLASH is one literal backslash, so the `u` after it is text.
    Decoding it would turn a Windows path or a regexp in a formatter string
    into a character the author never wrote -- and the decoder runs over the
    whole option, so this is the case that says it is not too eager. }
  o := TTyChartOption.Create;
  try
    AssertTrue(o.SetOptionText('{ "title": { "text": "\\u0041" } }'));
    AssertEquals('the escape is the backslash, not the u',
      '\u0041', o.GetStr('title.text', ''));

    { And a bare \u that is not four hex digits is left for the parser to
      judge rather than silently swallowed. }
    AssertTrue(o.SetOptionText('{ "title": { "text": "100\u00a5" } }'));
    AssertEquals('100' + #$C2#$A5, o.GetStr('title.text', ''));
  finally
    o.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartOptionTest);
end.
