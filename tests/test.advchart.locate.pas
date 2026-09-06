unit test.advchart.locate;
{$mode objfpc}{$H+}
{ The forward scanner: where in the text does an option path live?

  Most of these are edge cases on purpose. The happy path -- a well-formed
  document with one key -- is the case that cannot go wrong; what breaks a
  scanner is a quote inside a comment, a comment marker inside a string, an
  escaped quote, an unclosed brace, and the array index, which is the one piece
  of state the backward scanner next door deliberately does NOT keep. }
interface
uses Classes, SysUtils, fpcunit, testregistry,
     tyControls.AdvChart.Locate;
type
  TAdvChartLocateTest = class(TTestCase)
  private
    function PathAt(const AText, APath: string; out ALine, ACol, ALen: Integer): Boolean;
    function Paths(const AText: string): string;
  published
    procedure TestAKeyIsFoundWithItsLineAndColumn;
    procedure TestNestingBuildsADottedPath;
    procedure TestArrayElementsAreNumbered;
    procedure TestASecondArrayStartsItsOwnNumbering;
    procedure TestTheIndexAdvancesOnlyInTheArrayItIsIn;
    procedure TestAKeyInsideAStringIsNotAKey;
    procedure TestAnEscapedQuoteDoesNotEndTheString;
    procedure TestAnEscapedLineBreakIsStillALineBreak;
    procedure TestAWordWithNoColonIsNotAKey;
    procedure TestADottedNameIsNotOneKey;
    procedure TestATokenNotStartingWithANameIsSkippedWhole;
    procedure TestABareObjectMatchesASubscriptedDiagnostic;
    procedure TestCommentsAreSkippedIncludingBracesInside;
    procedure TestAQuoteInsideACommentIsNotAString;
    procedure TestCrlfAndLfGiveTheSameLineNumbers;
    procedure TestAStringSpanningLinesStillCountsThem;
    procedure TestAnUnclosedBraceStillYieldsEveryKeyBeforeIt;
    procedure TestAnUnterminatedStringStopsCleanly;
    procedure TestAValueIsNotMistakenForAKey;
    procedure TestNearestKeyFallsBackToTheLongestPrefix;
    procedure TestPathInMessageNeedsASubscript;
    procedure TestPathInMessageTakesTheFirstOfSeveral;
  end;

implementation

function TAdvChartLocateTest.PathAt(const AText, APath: string;
  out ALine, ACol, ALen: Integer): Boolean;
var
  pos: TTyOptKeyPos;
begin
  ALine := 0; ACol := 0; ALen := 0;
  Result := TyOptFindKey(TyOptKeyPositions(AText), APath, pos);
  if Result then
  begin
    ALine := pos.Line;
    ACol := pos.Col;
    ALen := pos.Len;
  end;
end;

{ Every path found, in document order, space separated -- so a test can pin the
  whole shape of a document in one assertion. }
function TAdvChartLocateTest.Paths(const AText: string): string;
var
  all: TTyOptKeyPosArray;
  i: Integer;
begin
  Result := '';
  all := TyOptKeyPositions(AText);
  for i := 0 to High(all) do
  begin
    if Result <> '' then Result := Result + ' ';
    Result := Result + all[i].Path;
  end;
end;

procedure TAdvChartLocateTest.TestAKeyIsFoundWithItsLineAndColumn;
var line, col, len: Integer;
begin
  AssertTrue(PathAt('{ xAxis: {} }', 'xAxis', line, col, len));
  AssertEquals('line', 1, line);
  AssertEquals('column of the first NAME character', 3, col);
  AssertEquals('length of the name', 5, len);

  { Quoted, and the column still points INSIDE the quotes: what an editor wants
    to select is the name, not the punctuation around it. }
  AssertTrue(PathAt('{ "xAxis": {} }', 'xAxis', line, col, len));
  AssertEquals(4, col);
  AssertEquals(5, len);

  { NOT ON LINE ONE. On the first line the line start IS the document start, so
    a column measured from the wrong origin has the same value -- a mutation
    that broke it survived this test until the fixture moved off line 1. }
  AssertTrue(PathAt('{' + LineEnding + '  "yAxis": 1 }', 'yAxis',
    line, col, len));
  AssertEquals('line', 2, line);
  AssertEquals('column counted from THIS line''s start', 4, col);
end;

procedure TAdvChartLocateTest.TestNestingBuildsADottedPath;
var line, col, len: Integer;
begin
  { The spelling is not a choice: it has to match what TyOptValidate puts in a
    TTyOptIssue, or a lookup silently never matches. Root carries no leading
    dot. }
  AssertEquals('xAxis xAxis.axisLabel xAxis.axisLabel.show',
    Paths('{ xAxis: { axisLabel: { show: true } } }'));
  AssertTrue(PathAt('{ xAxis: { axisLabel: { show: true } } }',
    'xAxis.axisLabel.show', line, col, len));
end;

procedure TAdvChartLocateTest.TestArrayElementsAreNumbered;
begin
  { The whole reason this scanner exists separately. The backward scanner
    deliberately ignores the index -- which options are legal inside series[3]
    is the same question as inside series[0] -- but a runtime path IS the
    index. }
  AssertEquals('series series[0].type series[1].type',
    Paths('{ series: [ { type: 1 }, { type: 2 } ] }'));
end;

procedure TAdvChartLocateTest.TestASecondArrayStartsItsOwnNumbering;
begin
  AssertEquals('xAxis xAxis[0].name xAxis[1].name yAxis yAxis[0].name',
    Paths('{ xAxis: [ { name: 1 }, { name: 2 } ], yAxis: [ { name: 3 } ] }'));
end;

procedure TAdvChartLocateTest.TestTheIndexAdvancesOnlyInTheArrayItIsIn;
begin
  { A comma INSIDE an element must not advance the element counter. This is the
    increment's obvious failure mode and it produces paths that look plausible
    and point at the wrong element. }
  AssertEquals('series series[0].a series[0].b series[1].a',
    Paths('{ series: [ { a: 1, b: 2 }, { a: 3 } ] }'));
end;

procedure TAdvChartLocateTest.TestAKeyInsideAStringIsNotAKey;
begin
  { 'title.text' holds a colon and a word. Neither makes it a key. }
  AssertEquals('title title.text',
    Paths('{ title: { text: ''xAxis: not a key'' } }'));
end;

procedure TAdvChartLocateTest.TestAnEscapedQuoteDoesNotEndTheString;
begin
  { THE FIXTURE MATTERS MORE THAN THE ASSERTION HERE, and the first version of
    this test proved it: with `text: 'a \' b: c'` the escape could be deleted
    from the scanner and the answer did not change. Closing the string early
    left the residue in a frame whose ExpectKey the earlier colon had already
    cleared, so nothing was emitted either way and the mutant survived a test
    written to catch it.

    A COMMA is what makes it lethal: it puts the frame back at a key position,
    so a wrongly-closed string turns `b` into a key that does not exist. }
  AssertEquals('a c', Paths('{ a: ''x \'' , b: 2'', c: 3 }'));

  { And the plain shape still holds. }
  AssertEquals('title title.text',
    Paths('{ title: { text: ''a \'' b: c'' } }'));
end;

procedure TAdvChartLocateTest.TestAnEscapedLineBreakIsStillALineBreak;
var line, col, len: Integer;
begin
  { The escape skips a character; if that character is a break it must still be
    COUNTED. Missing it puts every later key a line too high AND measures its
    column from the wrong line start -- the editor jumps confidently to the
    wrong place, which is worse than not jumping. All three break spellings,
    because CRLF happened to survive the bug by accident. }
  AssertTrue(PathAt('{ a: ''x\' + #10 + ' y'', b: 1 }', 'b', line, col, len));
  AssertEquals('LF after a backslash', 2, line);
  AssertEquals(6, col);

  AssertTrue(PathAt('{ a: ''x\' + #13 + ' y'', b: 1 }', 'b', line, col, len));
  AssertEquals('lone CR after a backslash', 2, line);

  AssertTrue(PathAt('{ a: ''x\' + #13#10 + ' y'', b: 1 }', 'b', line, col, len));
  AssertEquals('CRLF after a backslash', 2, line);
end;

procedure TAdvChartLocateTest.TestAWordWithNoColonIsNotAKey;
begin
  { What makes a name a key is the COLON after it. Emitting on the token
    instead gave `a` in `{ a b: 1 }` a path of its own -- a phantom nothing
    could ever look up, because no issue and no diagnostic can name it. }
  AssertEquals('b', Paths('{ a b: 1 }'));
  AssertEquals('and a lone word yields nothing at all', '', Paths('{ xAxis'));
end;

procedure TAdvChartLocateTest.TestADottedNameIsNotOneKey;
begin
  { '.' is the nesting separator, so it cannot also be a name character:
    `a.b: 1` used to emit the single path 'a.b', which collides with the
    spelling for `a` containing `b` and which fcl-json cannot parse unquoted
    anyway. }
  AssertEquals('a', Paths('{ a.b: 1 }'));
end;

procedure TAdvChartLocateTest.TestATokenNotStartingWithANameIsSkippedWhole;
begin
  { Entering `5x` or `-foo` mid-token reported `x` / `foo` as a key, at an
    offset a few columns off -- a key nobody wrote, pointing nearly at it. }
  AssertEquals('', Paths('{ 5x: 1 }'));
  AssertEquals('', Paths('{ -foo: 1 }'));
  AssertEquals('a real key beside one still comes through',
    'ok', Paths('{ 5x: 1, ok: 2 }'));
end;

procedure TAdvChartLocateTest.TestABareObjectMatchesASubscriptedDiagnostic;
var
  all: TTyOptKeyPosArray;
  pos: TTyOptKeyPos;
begin
  { TWO PRODUCERS SPELL THE SAME TEXT DIFFERENTLY. `xAxis: { type: ... }` is a
    bare object; the builder loops over ComponentCount, which reports 1 for it,
    so its diagnostic says 'xAxis[0].type'. TyOptValidate says 'xAxis.type'.
    The text has neither subscript.

    Without the [0] fallback the walk degrades two steps past the key that IS
    in the text and lands on the container -- so the caret misses the very
    thing the message is about. }
  all := TyOptKeyPositions('{ xAxis: { type: ''categroy'' } }');
  AssertTrue(TyOptFindNearestKey(all, 'xAxis[0].type', pos));
  AssertEquals('xAxis.type', pos.Path);

  { But a path naming a LATER element is talking about a real array, and must
    not be rewritten. }
  AssertTrue(TyOptFindNearestKey(all, 'xAxis[2].type', pos));
  AssertEquals('xAxis', pos.Path);
end;

procedure TAdvChartLocateTest.TestCommentsAreSkippedIncludingBracesInside;
begin
  AssertEquals('a brace in a line comment pushes no frame',
    'xAxis yAxis', Paths('{ xAxis: 1, // { nope: 2' + LineEnding + ' yAxis: 3 }'));
  AssertEquals('nor one in a block comment',
    'xAxis yAxis', Paths('{ xAxis: 1, /* { nope: 2 */ yAxis: 3 }'));
end;

procedure TAdvChartLocateTest.TestAQuoteInsideACommentIsNotAString;
begin
  { An apostrophe in a comment used to open a string that never closed, which
    swallowed the rest of the document. }
  AssertEquals('xAxis yAxis',
    Paths('{ xAxis: 1, // don''t' + LineEnding + ' yAxis: 3 }'));
end;

procedure TAdvChartLocateTest.TestCrlfAndLfGiveTheSameLineNumbers;
var l1, l2, c, n: Integer;
begin
  AssertTrue(PathAt('{' + #10 + '  yAxis: 1' + #10 + '}', 'yAxis', l1, c, n));
  AssertTrue(PathAt('{' + #13#10 + '  yAxis: 1' + #13#10 + '}', 'yAxis', l2, c, n));
  AssertEquals('LF says line 2', 2, l1);
  AssertEquals('and CRLF is the same one break, not two', l1, l2);
end;

procedure TAdvChartLocateTest.TestAStringSpanningLinesStillCountsThem;
var line, col, len: Integer;
begin
  { A break inside a string is still a break. Missing it puts every later key
    on the wrong line, which is worse than not finding them at all: the editor
    jumps confidently to the wrong place. }
  AssertTrue(PathAt('{ a: ''one' + #10 + 'two'',' + #10 + '  yAxis: 1 }',
    'yAxis', line, col, len));
  AssertEquals(3, line);
end;

procedure TAdvChartLocateTest.TestAnUnclosedBraceStillYieldsEveryKeyBeforeIt;
begin
  { Half-typed text is the normal state in an editor. }
  AssertEquals('xAxis xAxis.axisLabel xAxis.axisLabel.show',
    Paths('{ xAxis: { axisLabel: { show: true'));
end;

procedure TAdvChartLocateTest.TestAnUnterminatedStringStopsCleanly;
begin
  AssertEquals('everything before the open quote survives',
    'xAxis yAxis', Paths('{ xAxis: 1, yAxis: ''still typing'));
end;

procedure TAdvChartLocateTest.TestAValueIsNotMistakenForAKey;
begin
  { After a colon comes a value, and a value that happens to be a bare word is
    not a key. }
  AssertEquals('series series[0].type',
    Paths('{ series: [ { type: bar } ] }'));

  { The shape where the guard still earns its place. Emitting on the colon
    already stops a value becoming a key in every WELL-FORMED document -- the
    value is held, no colon follows, nothing is emitted. What is left is
    malformed input, which a tolerant scanner sees constantly: in `a: b: 1`
    only `a` is a key, and without the guard `b` becomes one too.

    Worth stating plainly because mutation showed the guard is nearly dead:
    this is the whole of what it still buys. }
  AssertEquals('a', Paths('{ a: b: 1 }'));
end;

procedure TAdvChartLocateTest.TestNearestKeyFallsBackToTheLongestPrefix;
var
  all: TTyOptKeyPosArray;
  pos: TTyOptKeyPos;
begin
  { A diagnostic can name something that is not a key at all -- a leaf the build
    derived, or one that was deleted. Jumping to the container is useful;
    refusing to jump is not. }
  all := TyOptKeyPositions('{ series: [ { itemStyle: { color: 1 } } ] }');
  AssertFalse('the exact path is not in the text',
    TyOptFindKey(all, 'series[0].itemStyle.nope', pos));
  AssertTrue('but a prefix is',
    TyOptFindNearestKey(all, 'series[0].itemStyle.nope', pos));
  AssertEquals('series[0].itemStyle', pos.Path);

  { AND AN ARRAY ELEMENT IS NOT A KEY. 'series[0]' is a place, not something
    anybody typed a name for, so the walk steps straight over it to the
    container. Worth pinning because the fallback looks like it should stop
    there, and a caller expecting a caret inside the element gets one on
    `series` instead. }
  AssertTrue(TyOptFindNearestKey(all, 'series[0].data.7', pos));
  AssertEquals('series', pos.Path);

  AssertFalse('and a path sharing nothing finds nothing',
    TyOptFindNearestKey(all, 'legend.data', pos));
end;

procedure TAdvChartLocateTest.TestPathInMessageNeedsASubscript;
begin
  { A subscript is what separates a path from the English around it. Without
    that test the first noun of every sentence would come back as a path. }
  AssertEquals('series[0]',
    TyOptPathInMessage('series[0] has no type, so it is not drawn'));
  AssertEquals('xAxis[1]',
    TyOptPathInMessage('xAxis[1] names no grid, so it is not drawn'));
  AssertEquals('a subscripted path with a tail keeps the tail',
    'xAxis[0].type',
    TyOptPathInMessage('xAxis[0].type: "wat" is not one of value, category'));
  AssertEquals('no subscript, no guess', '',
    TyOptPathInMessage('xAxis or yAxis without the other: no grid was created'));
end;

procedure TAdvChartLocateTest.TestPathInMessageTakesTheFirstOfSeveral;
begin
  { 'series[2]: xAxis[0] and yAxis[1] are not on one grid' names three. The
    subject is the first. }
  AssertEquals('series[2]',
    TyOptPathInMessage('series[2]: xAxis[0] and yAxis[1] are not on one grid'));
end;

initialization
  RegisterTest(TAdvChartLocateTest);
end.
