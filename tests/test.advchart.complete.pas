unit test.advchart.complete;
{$mode objfpc}{$H+}
{ Caret-aware completion over the option catalog.

  This is the design-time editor's brain, kept out of the editor so it can be
  tested at all: the SynEdit dialog is a shell, and the same split is why
  Css.Complete exists separately from Design.Css.Editor.

  The scan is deliberately tolerant of BROKEN text. Every case below is a
  fragment with an unclosed brace, because that is the normal state of a
  document while someone is typing -- a completion list that only appeared once
  the JSON was valid would appear approximately never. }
interface
uses Classes, SysUtils, fpcunit, testregistry,
     tyControls.AdvChart.Catalog, tyControls.AdvChart.Complete,
     tyControls.StrConsts;
type
  TIntArray = array of Integer;

  TAdvChartCompleteTest = class(TTestCase)
  private
    FList: TStringList;
    procedure SetUp; override;
    procedure TearDown; override;
    function Has(const AItem: string): Boolean;
  published
    { ---- where am I ---- }
    procedure TestRootOffersTopLevelComponents;
    procedure TestInsideAContainerOffersItsOwnOptions;
    procedure TestNestedTwoDeep;
    procedure TestPartialFiltersByPrefix;
    procedure TestPartialIsCaseInsensitive;
    { ---- key vs value ---- }
    procedure TestAfterAColonItIsAValuePosition;
    procedure TestValuePositionOffersTheEnum;
    procedure TestValuePositionOffersNothingWhenNotEnumerated;
    procedure TestInsideAnOpenStringStillCompletes;
    { ---- unions ---- }
    procedure TestSeriesElementResolvesByItsOwnType;
    procedure TestADifferentTypeGivesDifferentOptions;
    procedure TestTypeWrittenAfterTheCaretIsNotSeen;
    procedure TestMissingTypeSaysSoRatherThanOfferingNothing;
    { ---- tolerance ---- }
    procedure TestCommentsAreSkipped;
    procedure TestClosedContainersDoNotLeak;
    procedure TestBracesInsideStringsDoNotCount;
    procedure TestEscapedQuotesDoNotEndTheString;
    procedure TestUnknownContainerOffersNothing;
    procedure TestEmptyTextIsTheRoot;
    procedure TestSliceBeforeCountsLinesFromOne;
    procedure TestSliceBeforeHandlesCrlfAndLoneCr;
    procedure TestSliceBeforeClampsAColumnPastTheLineEnd;
    procedure TestEdgesKeepTheStructureChildNamesDrops;
    procedure TestSummarySaysTypeDefaultAndSince;
    procedure TestValueCandidatesWidenAnEnumToBooleansAndDefaults;
    procedure TestVariantHelpAsksForTypeThenOffersTheTags;
    procedure TestStatusNamesThePathOrAsksForAType;
    procedure TestACompletedEnumValueIsQuoted;
    procedure TestACompletedKeyBringsItsOwnBracesOrQuotes;
    procedure TestTreeInsertAddsTheCommaOnlyWhenSomethingFollows;
    procedure TestSuggestNameIsSilentWhenNothingIsClose;
    procedure TestThePartialAndTheItemDetailAreAvailableWithoutTheContext;
    { ---- searching the whole catalog ---- }
    procedure TestSearchFindsAKeyNobodyCouldScrollTo;
    procedure TestSearchAnswersShallowestFirst;
    procedure TestSearchNamesEachNodeOnce;
    procedure TestSearchNamesANodeByItsShortestPath;
    procedure TestSearchCarriesTheNodeSoNobodyReparsesThePath;
    procedure TestSearchHonoursItsLimitAndItsEmptyCase;
  end;
implementation

procedure TAdvChartCompleteTest.SetUp;
begin
  inherited SetUp;
  FList := TStringList.Create;
end;

procedure TAdvChartCompleteTest.TearDown;
begin
  FreeAndNil(FList);
  inherited TearDown;
end;

function TAdvChartCompleteTest.Has(const AItem: string): Boolean;
begin
  Result := FList.IndexOf(AItem) >= 0;
end;

{ ============================ where am I ============================ }

procedure TAdvChartCompleteTest.TestRootOffersTopLevelComponents;
begin
  AssertTrue('something to offer', TyOptCompletionsAt('{ ', FList));
  AssertTrue('series', Has('series'));
  AssertTrue('xAxis', Has('xAxis'));
  AssertTrue('tooltip', Has('tooltip'));
  AssertFalse('but not an option from inside something', Has('smooth'));
end;

procedure TAdvChartCompleteTest.TestInsideAContainerOffersItsOwnOptions;
begin
  AssertTrue('offers', TyOptCompletionsAt('{ grid: { ', FList));
  AssertTrue('left', Has('left'));
  AssertTrue('containLabel', Has('containLabel'));
  AssertFalse('and not the root vocabulary any more', Has('series'));
end;

procedure TAdvChartCompleteTest.TestNestedTwoDeep;
begin
  AssertTrue('offers', TyOptCompletionsAt('{ xAxis: { axisLabel: { ', FList));
  AssertTrue('rotate', Has('rotate'));
  AssertTrue('formatter', Has('formatter'));
  AssertFalse('not the axis level', Has('boundaryGap'));
end;

procedure TAdvChartCompleteTest.TestPartialFiltersByPrefix;
begin
  AssertTrue('offers', TyOptCompletionsAt('{ grid: { bor', FList));
  AssertTrue('borderColor', Has('borderColor'));
  AssertTrue('borderWidth', Has('borderWidth'));
  AssertFalse('left is filtered out', Has('left'));
end;

procedure TAdvChartCompleteTest.TestPartialIsCaseInsensitive;
begin
  AssertTrue('offers', TyOptCompletionsAt('{ grid: { BOR', FList));
  AssertTrue('borderColor', Has('borderColor'));
end;

{ ============================ key vs value ============================ }

procedure TAdvChartCompleteTest.TestAfterAColonItIsAValuePosition;
var ctx: TTyOptCaretContext;
begin
  ctx := TyOptContextAt('{ legend: { orient: ');
  AssertTrue('value position', ctx.Kind = ockValue);
  AssertEquals('and it knows which key', 'orient', ctx.ValueOf);
  ctx := TyOptContextAt('{ legend: { ');
  AssertTrue('key position', ctx.Kind = ockKey);
end;

procedure TAdvChartCompleteTest.TestValuePositionOffersTheEnum;
begin
  AssertTrue('offers', TyOptCompletionsAt('{ legend: { orient: ', FList));
  AssertEquals('two values', 2, FList.Count);
  AssertTrue('horizontal', Has('horizontal'));
  AssertTrue('vertical', Has('vertical'));
end;

procedure TAdvChartCompleteTest.TestValuePositionOffersNothingWhenNotEnumerated;
begin
  { grid.left is a number-or-string with no enumerated values in the schema.
    Offering something invented would be worse than offering nothing. }
  AssertFalse('nothing to offer', TyOptCompletionsAt('{ grid: { left: ', FList));
  AssertEquals('and the list stays empty', 0, FList.Count);
end;

procedure TAdvChartCompleteTest.TestInsideAnOpenStringStillCompletes;
begin
  { The quote is open -- the user is mid-word inside it. This is the ONLY state
    a value ever gets completed in, so if it did not work here it would never
    work at all. }
  AssertTrue('offers', TyOptCompletionsAt('{ legend: { orient: ''ver', FList));
  AssertEquals('filtered to one', 1, FList.Count);
  AssertTrue('vertical', Has('vertical'));
end;

{ ============================ unions ============================ }

procedure TAdvChartCompleteTest.TestSeriesElementResolvesByItsOwnType;
begin
  { series[0] is one of twenty-three shapes, and only its own `type` says which.
    This is the whole reason a catalog is generated rather than a flat list. }
  AssertTrue('offers', TyOptCompletionsAt('{ series: [{ type: ''bar'', ', FList));
  AssertTrue('stack is a bar option', Has('stack'));
  AssertFalse('roseType is not', Has('roseType'));
end;

procedure TAdvChartCompleteTest.TestADifferentTypeGivesDifferentOptions;
begin
  AssertTrue('offers', TyOptCompletionsAt('{ series: [{ type: ''pie'', ', FList));
  AssertTrue('roseType is a pie option', Has('roseType'));
  AssertFalse('stack is not', Has('stack'));
end;

procedure TAdvChartCompleteTest.TestTypeWrittenAfterTheCaretIsNotSeen;
var ctx: TTyOptCaretContext;
begin
  { The scan only sees text BEFORE the caret, which is the honest limit: a type
    written later has not been read. It must say so rather than guess a variant. }
  ctx := TyOptContextAt('{ series: [{ ');
  AssertTrue('unresolved', ctx.Node < 0);
  AssertTrue('and it says why', ctx.NeedsVariantType);
end;

procedure TAdvChartCompleteTest.TestMissingTypeSaysSoRatherThanOfferingNothing;
var ctx: TTyOptCaretContext;
begin
  { An editor can turn NeedsVariantType into "write a type first" instead of an
    empty popup that looks like a broken feature. }
  ctx := TyOptContextAt('{ series: [{ name: ''x'', ');
  AssertTrue('still unresolved', ctx.Node < 0);
  AssertTrue('for a reason it can name', ctx.NeedsVariantType);
  AssertFalse('so nothing is offered', TyOptCompletionsAt('{ series: [{ name: ''x'', ', FList));
end;

{ ============================ tolerance ============================ }

procedure TAdvChartCompleteTest.TestCommentsAreSkipped;
begin
  AssertTrue('offers', TyOptCompletionsAt(
    '{ /* a note */ grid: { // another' + LineEnding + '  ', FList));
  AssertTrue('left', Has('left'));
end;

procedure TAdvChartCompleteTest.TestClosedContainersDoNotLeak;
begin
  { grid was opened and closed; the caret is back at the root. }
  AssertTrue('offers', TyOptCompletionsAt('{ grid: { left: 10 }, ', FList));
  AssertTrue('series is back', Has('series'));
  AssertFalse('and grid options are gone', Has('containLabel'));
end;

procedure TAdvChartCompleteTest.TestBracesInsideStringsDoNotCount;
begin
  { A formatter template really does contain braces. Counting them as structure
    would put the caret in an imaginary container. }
  AssertTrue('offers', TyOptCompletionsAt(
    '{ tooltip: { formatter: ''{b}: {c}'', ', FList));
  AssertTrue('still inside tooltip', Has('trigger'));
end;

procedure TAdvChartCompleteTest.TestEscapedQuotesDoNotEndTheString;
begin
  { An escaped quote inside a value ends the string early if escapes are not
    skipped -- and then the braces in the rest of the template are read as
    structure, putting the caret in a container that does not exist. Found by
    mutation: removing the escape skip left every other test green, because
    none of them had an escape in a string. }
  AssertTrue('offers', TyOptCompletionsAt(
    '{ tooltip: { formatter: ''it\''s {b}'', ', FList));
  AssertTrue('still inside tooltip', Has('trigger'));
  AssertFalse('and not somewhere invented', Has('series'));
end;

procedure TAdvChartCompleteTest.TestUnknownContainerOffersNothing;
begin
  { A misspelled container has no vocabulary. Falling back to the root's would
    offer options that are wrong in a way the user cannot see. }
  AssertFalse('nothing', TyOptCompletionsAt('{ giid: { ', FList));
end;

procedure TAdvChartCompleteTest.TestEmptyTextIsTheRoot;
begin
  { No outer brace typed yet. Resolving against nothing would mean the very
    first keystroke in an empty editor gets no help. }
  AssertTrue('offers', TyOptCompletionsAt('', FList));
  AssertTrue('series', Has('series'));
end;

{ ============ the editor primitives ============ }

procedure TAdvChartCompleteTest.TestSliceBeforeCountsLinesFromOne;
const
  cText = 'ab' + #10 + 'cdef' + #10 + 'gh';
begin
  { 1-based line, 1-based column, and column 1 means "before the first
    character of that line", not after it. }
  AssertEquals('', TyOptSliceBefore(cText, 1, 1));
  AssertEquals('a', TyOptSliceBefore(cText, 1, 2));
  AssertEquals('ab' + #10, TyOptSliceBefore(cText, 2, 1));
  AssertEquals('ab' + #10 + 'cd', TyOptSliceBefore(cText, 2, 3));
  AssertEquals('ab' + #10 + 'cdef' + #10, TyOptSliceBefore(cText, 3, 1));
end;

procedure TAdvChartCompleteTest.TestSliceBeforeHandlesCrlfAndLoneCr;
begin
  { A SynEdit document is CRLF on Windows and LF elsewhere, and text pasted
    from a web page can carry either -- or a lone CR from an old Mac file.
    Getting the line count wrong by one puts the caret in the wrong object. }
  AssertEquals('ab' + #13#10, TyOptSliceBefore('ab' + #13#10 + 'cd', 2, 1));
  AssertEquals('ab' + #13, TyOptSliceBefore('ab' + #13 + 'cd', 2, 1));
  AssertEquals('the CRLF pair is one break, not two',
    'ab' + #13#10 + 'c', TyOptSliceBefore('ab' + #13#10 + 'cd', 2, 2));
end;

procedure TAdvChartCompleteTest.TestSliceBeforeClampsAColumnPastTheLineEnd;
begin
  { Clicking past the end of a line. The CSS editor turns eoScrollPastEol off
    to stop it, but a column can still arrive out of range, and the answer has
    to be this line's text -- never the next line's. }
  AssertEquals('ab', TyOptSliceBefore('ab' + #10 + 'cd', 1, 99));
  AssertEquals('ab' + #10 + 'cd', TyOptSliceBefore('ab' + #10 + 'cd', 2, 99));
  AssertEquals('a line past the end gives the whole text',
    'ab' + #10 + 'cd', TyOptSliceBefore('ab' + #10 + 'cd', 9, 1));
end;

procedure TAdvChartCompleteTest.TestEdgesKeepTheStructureChildNamesDrops;
var
  lk: TTyOptLookup;
  edges: TTyOptEdgeArray;
  i, arrays, variants, props: Integer;
  names: TStringList;
begin
  { series is the union: twenty-three tagged members and NOTHING else. Its
    array-ness is in its type string, not in an edge -- worth pinning, because
    assuming an '[]' edge here is the mistake this test was written making. }
  lk := TyOptFind('series');
  AssertTrue('series resolves', lk.Found);
  AssertEquals('Array', TyOptTypeOf(lk.Node));
  edges := TyOptEdgesOf(lk.Node);
  arrays := 0; variants := 0; props := 0;
  for i := 0 to High(edges) do
    case edges[i].Kind of
      oekArrayItem: Inc(arrays);
      oekVariant: Inc(variants);
      oekProperty: Inc(props);
    end;
  AssertEquals('no array edge -- the type string carries that', 0, arrays);
  AssertEquals('twenty-three tagged members', 23, variants);
  AssertEquals('and no plain property of its own', 0, props);

  names := TStringList.Create;
  try
    TyOptChildNames(lk.Node, names);
    AssertEquals('a completion list here would offer nothing at all',
      0, names.Count);
  finally
    names.Free;
  end;

  { And where an array edge DOES exist it is kept. Forty-three nodes carry one;
    legend.data is one of them. }
  lk := TyOptFind('legend.data');
  AssertTrue('legend.data resolves', lk.Found);
  edges := TyOptEdgesOf(lk.Node);
  arrays := 0;
  for i := 0 to High(edges) do
    if edges[i].Kind = oekArrayItem then Inc(arrays);
  AssertEquals('its element edge survives', 1, arrays);
end;

procedure TAdvChartCompleteTest.TestSummarySaysTypeDefaultAndSince;
var
  lk: TTyOptLookup;
  sum: string;
begin
  lk := TyOptFind('xAxis.show');
  AssertTrue('xAxis.show resolves', lk.Found);
  sum := TyOptSummary(lk.Node);
  AssertTrue('names its type, got: ' + sum,
    Pos('boolean', LowerCase(sum)) > 0);
  AssertTrue('and its default, got: ' + sum, Pos('true', LowerCase(sum)) > 0);

  AssertEquals('an unknown node summarises to nothing', '', TyOptSummary(-1));
end;

procedure TAdvChartCompleteTest.TestValueCandidatesWidenAnEnumToBooleansAndDefaults;
var
  lk: TTyOptLookup;
  l: TStringList;
begin
  l := TStringList.Create;
  try
    { A boolean carries no enumeration in the schema, yet true/false is the
      most-typed value in an option tree. TyOptEnumOf must stay silent about
      it -- that is its contract -- so the widening lives here. }
    lk := TyOptFind('xAxis.show');
    AssertFalse('the schema enumerates nothing for a boolean',
      TyOptEnumOf(lk.Node, l));
    AssertTrue('but a value list is offerable', TyOptValueCandidates(lk.Node, l));
    AssertTrue('true is offered', l.IndexOf('true') >= 0);
    AssertTrue('false is offered', l.IndexOf('false') >= 0);
  finally
    l.Free;
  end;
end;

procedure TAdvChartCompleteTest.TestVariantHelpAsksForTypeThenOffersTheTags;
var
  l: TStringList;
begin
  l := TStringList.Create;
  try
    { Inside a series element with no type yet. There is exactly one useful
      thing to say, and it is not an empty popup. }
    AssertTrue('help is offered at a key position',
      TyOptVariantHelpAt('{ series: [{ ', l));
    AssertEquals('and it is one word', 1, l.Count);
    AssertEquals('type', l[0]);

    AssertTrue('and at that key''s value the tags come out',
      TyOptVariantHelpAt('{ series: [{ type: ', l));
    AssertTrue('bar is among them', l.IndexOf('bar') >= 0);
    AssertTrue('line is among them', l.IndexOf('line') >= 0);

    AssertFalse('nothing to say once the type is decided',
      TyOptVariantHelpAt('{ series: [{ type: ''bar'', ', l));
  finally
    l.Free;
  end;
end;

procedure TAdvChartCompleteTest.TestStatusNamesThePathOrAsksForAType;
begin
  AssertEquals('the root says so rather than showing an empty bar',
    rsTyOptStatusRoot, TyOptStatusAt('{ '));
  AssertEquals('xAxis', TyOptStatusAt('{ xAxis: { '));
  AssertEquals('an undecided union asks for the type',
    rsTyOptStatusNeedsType, TyOptStatusAt('{ series: [{ '));
  AssertEquals('and a decided one is variant-qualified',
    'series-bar', TyOptStatusAt('{ series: [{ type: ''bar'', '));
end;

procedure TAdvChartCompleteTest.TestACompletedEnumValueIsQuoted;
var
  ins: string;
  back: Integer;
begin
  { fcl-json is relaxed about KEYS -- unquoted is fine -- and strict about
    string VALUES. Inserting a bare `bar` for `type` yields a document that
    cannot parse, which is a completion that breaks the thing it completed. }
  AssertTrue(TyOptCompletionInsert('{ series: [{ type: ', 'bar', ins, back));
  AssertEquals('''bar''', ins);
  AssertEquals(0, back);

  { Unless the caret is already inside an open string, where a second pair of
    quotes is exactly wrong. }
  AssertTrue(TyOptCompletionInsert('{ series: [{ type: ''', 'bar', ins, back));
  AssertEquals('bar', ins);

  { And a value that is not a string does not acquire quotes. }
  AssertTrue(TyOptCompletionInsert('{ xAxis: { show: ', 'true', ins, back));
  AssertEquals('true', ins);
end;

procedure TAdvChartCompleteTest.TestACompletedKeyBringsItsOwnBracesOrQuotes;
var
  ins: string;
  back: Integer;
begin
  { The punctuation is the part nobody wants to type, and getting it from the
    catalog's own type is free. }
  AssertTrue(TyOptCompletionInsert('{ ', 'xAxis', ins, back));
  AssertEquals('xAxis: {}', ins);
  AssertEquals('caret inside the braces', 1, back);

  AssertTrue(TyOptCompletionInsert('{ ', 'series', ins, back));
  AssertEquals('series: []', ins);
  AssertEquals('caret inside the brackets', 1, back);
end;

procedure TAdvChartCompleteTest.TestTreeInsertAddsTheCommaOnlyWhenSomethingFollows;
var
  lk: TTyOptLookup;
begin
  lk := TyOptFind('xAxis');
  AssertTrue(lk.Found);
  AssertEquals('nothing follows, no comma',
    'show: ', TyOptTreeInsert(lk.Node, 'show', oekProperty, '   '));
  AssertEquals('a closing brace follows, still no comma',
    'show: ', TyOptTreeInsert(lk.Node, 'show', oekProperty, ' }'));
  AssertEquals('a comma already follows, do not add a second',
    'show: ', TyOptTreeInsert(lk.Node, 'show', oekProperty, ', type: 1'));
  AssertEquals('a real key follows, so separate them',
    'show: ,', TyOptTreeInsert(lk.Node, 'show', oekProperty, 'type: 1'));
end;

procedure TAdvChartCompleteTest.TestSuggestNameIsSilentWhenNothingIsClose;
var
  lk: TTyOptLookup;
begin
  lk := TyOptFind('series-bar');
  AssertTrue('series-bar resolves', lk.Found);
  AssertEquals('a one-character slip is caught',
    'itemStyle', TyOptSuggestName(lk.Node, 'itemStile'));
  { The important half. A confident wrong suggestion is worse than none: the
    reader stops looking for their own typo. }
  AssertEquals('a genuinely novel key gets no guess',
    '', TyOptSuggestName(lk.Node, 'zzzzzzzzzz'));
  AssertEquals('and neither does an empty one',
    '', TyOptSuggestName(lk.Node, ''));
end;

procedure TAdvChartCompleteTest.TestThePartialAndTheItemDetailAreAvailableWithoutTheContext;
begin
  { These two exist so the design-time dialog never has to call TyOptContextAt
    itself. That is not a style preference: designtime/ is outside the test
    build, so anything worked out in there is worked out where nothing can check
    it -- and a guard in test.release.pas now fails if the editor reaches past
    this layer. The pair has to actually do the job, hence these. }
  AssertEquals('the run being typed', 'xAx', TyOptPartialAt('{ xAx'));
  AssertEquals('nothing typed yet', '', TyOptPartialAt('{ '));

  AssertTrue('a known child gets a summary, got: '
    + TyOptCompletionDetail('{ ', 'xAxis'),
    TyOptCompletionDetail('{ ', 'xAxis') <> '');
  AssertEquals('an unknown one gets none', '',
    TyOptCompletionDetail('{ ', 'nosuchoption'));
  AssertEquals('and so does an empty item', '', TyOptCompletionDetail('{ ', ''));
end;

{ ============ searching the whole catalog ============ }

procedure TAdvChartCompleteTest.TestSearchFindsAKeyNobodyCouldScrollTo;
begin
  { The tree is lazy because building 2,455 nodes up front costs a visible pause
    on every open. The price is that nothing in the tree helps you find a key
    unless you already know which branch it lives on -- which is what the filter
    is for. }
  AssertTrue('axisLabel is found', TyOptSearch('axisLabel', FList) > 0);
  AssertTrue('and by its dotted path', Has('xAxis.axisLabel'));

  { Case-insensitive, and a SUBSTRING: someone hunting for a key half-remembers
    the middle of it as often as the start. }
  AssertTrue(TyOptSearch('AXISLABEL', FList) > 0);
  AssertTrue(Has('xAxis.axisLabel'));
  AssertTrue(TyOptSearch('ymbolsi', FList) > 0);
end;

{ How deep a path READS: one step per '.', one per variant '-'. Counting only
  dots calls `dataZoom-slider.handleLabel` shallower than `tooltip.textStyle`,
  which is not what anyone reading the list would say. }
function Depth(const APath: string): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 1 to Length(APath) do
    if (APath[i] = '.') or (APath[i] = '-') then Inc(Result);
end;

procedure TAdvChartCompleteTest.TestSearchAnswersShallowestFirst;
const
  cTerms: array[0..3] of string = ('label', 'style', 'color', 'width');
var
  i, t, prev: Integer;
begin
  { Breadth-first, so the first answer is the shortest path to the key. Someone
    who types `label` wants `series-bar.label` near the top, not forty
    `markPoint.label.rich.*` rows first.

    Asserting a root-level hit lands first would prove nothing: a depth-first
    walk visits the root's own properties before descending too, so `tooltip`
    comes out first either way. Neither does comparing everything against the
    FIRST row -- `label` has no root-level occurrence, so depth-first also opens
    with a depth-1 path and every later row is still at least that deep.

    So this checks the two things separately. Here: the list READS
    shortest-first, all the way down. Below: each node is named by its SHORTEST
    path, which is the part the breadth-first walk is actually for. }
  AssertTrue(TyOptSearch('tooltip', FList) > 0);
  AssertEquals('the root-level one comes first', 'tooltip', FList[0]);

  for t := 0 to High(cTerms) do
  begin
    AssertTrue(TyOptSearch(cTerms[t], FList) > 0);
    AssertTrue(cTerms[t] + ' has real depth to get wrong', FList.Count > 10);
    prev := Depth(FList[0]);
    for i := 1 to FList.Count - 1 do
    begin
      AssertTrue(Format('%s (depth %d) came after a depth-%d path',
        [FList[i], Depth(FList[i]), prev]), Depth(FList[i]) >= prev);
      prev := Depth(FList[i]);
    end;
  end;
end;

procedure TAdvChartCompleteTest.TestSearchNamesEachNodeOnce;
var
  i, j: Integer;
begin
  { `label` is reachable by hundreds of paths through a DAG. Following every one
    of them does not finish, and reporting the same node under six spellings is
    not six answers. }
  AssertTrue(TyOptSearch('label', FList) > 0);
  AssertTrue('and it terminates at all', FList.Count < 2455);
  for i := 0 to FList.Count - 1 do
    for j := i + 1 to FList.Count - 1 do
    begin
      AssertTrue('duplicate path ' + FList[i], FList[i] <> FList[j]);
      { Distinct PATHS is the weaker claim and the one that passes by accident:
        drop the visited check and the same node comes back under six different
        spellings, all of them distinct strings. The nodes are what must not
        repeat. }
      AssertTrue(Format('%s and %s are the same node', [FList[i], FList[j]]),
        FList.Objects[i] <> FList.Objects[j]);
    end;
end;

{ The fewest steps from the root to each node, counted the way a path spells
  them: a property or a variant costs one, an array element costs nothing.
  Deliberately unlike TyOptSearch -- no paths, no names, no strings -- so it can
  disagree with it. }
function MinSteps: TIntArray;
var
  q: array of Integer;
  head, tail, n, i, c, cost: Integer;
  edges: TTyOptEdgeArray;
begin
  SetLength(Result, 2600);
  for i := 0 to High(Result) do Result[i] := -1;
  SetLength(q, 2600);
  head := 0; tail := 0;
  Result[TyOptRoot] := 0;
  q[tail] := TyOptRoot; Inc(tail);
  while head < tail do
  begin
    n := q[head]; Inc(head);
    edges := TyOptEdgesOf(n);
    for i := 0 to High(edges) do
    begin
      c := edges[i].Node;
      if (c < 0) or (c > High(Result)) or (Result[c] >= 0) then Continue;
      if edges[i].Kind = oekArrayItem then cost := 0 else cost := 1;
      Result[c] := Result[n] + cost;
      q[tail] := c; Inc(tail);
    end;
  end;
end;

procedure TAdvChartCompleteTest.TestSearchNamesANodeByItsShortestPath;
const
  cTerms: array[0..4] of string = ('textStyle', 'axisLine', 'label',
    'itemStyle', 'emphasis');
var
  i, t: Integer;
  min_: TIntArray;
begin
  { A shared node is reachable by a short path and a long one, and it is
    reported ONCE -- so which path it gets is decided entirely by the order of
    the walk. Breadth-first gives the short one. A depth-first walk would dive
    into the first branch it met, claim the node down there, and the obvious
    path would then be missing from the list altogether: someone filtering for
    `textStyle` would be shown `series-sunburst.levels.label.rich.<style_name>`
    and not `title.textStyle`.

    Ordering alone cannot catch that. The short path is not late in the list --
    it is not in the list. }
  { Named examples are no good here: pick `title.textStyle` and the test passes
    under any walk order, because that node hangs off title alone and there is
    no second path to lose it to. The nodes this is about are the SHARED ones,
    and which those are is not something to guess at.

    So compute the answer independently. MinSteps below is its own breadth-first
    pass over the same edges that measures depth ONLY -- no paths, no strings --
    and every result must sit at exactly that depth. }
  min_ := MinSteps;
  for t := 0 to High(cTerms) do
  begin
    AssertTrue(cTerms[t] + ' finds something', TyOptSearch(cTerms[t], FList) > 0);
    for i := 0 to FList.Count - 1 do
      { +1 because Depth counts SEPARATORS and MinSteps counts EDGES: the
        one-segment path `textStyle` has no separator and one edge. }
      AssertEquals(FList[i] + ' is not the shortest path to its node',
        min_[Integer(PtrInt(FList.Objects[i]))], Depth(FList[i]) + 1);
  end;

  { ECharts has a root-level textStyle, and that is the shallowest of all. }
  AssertTrue(TyOptSearch('textStyle', FList) > 0);
  AssertEquals('the shallowest opens the list', 'textStyle', FList[0]);
end;

procedure TAdvChartCompleteTest.TestSearchCarriesTheNodeSoNobodyReparsesThePath;
const
  cTerms: array[0..7] of string = ('axisLabel', 'data', 'elements', 'pieces',
    'links', 'levels', 'categories', 'symbol');
var
  i, t, node: Integer;
begin
  { The caller shows a result by looking the node up. Handing the path BACK to
    TyOptFind would make two producers of the same string, which is how the
    spellings drift apart -- so the search carries the node it already had, and
    this is the check that the two still agree.

    Several terms, not one: `axisLabel` alone crosses no array edge, so a search
    that started writing `xAxis[].axisLabel` again -- a spelling TyOptFind
    cannot resolve -- would sail straight past it. The terms below reach into
    `graphic.elements`, `visualMap.pieces` and the graph series, which are
    arrays in the schema. }
  for t := 0 to High(cTerms) do
  begin
    AssertTrue(cTerms[t] + ' finds something at all',
      TyOptSearch(cTerms[t], FList) > 0);
    for i := 0 to FList.Count - 1 do
    begin
      node := Integer(PtrInt(FList.Objects[i]));
      AssertTrue(FList[i] + ' carries a real node', node > 0);
      AssertEquals(FList[i] + ' resolves to the same node', node,
        TyOptFind(FList[i]).Node);
    end;
  end;
end;

procedure TAdvChartCompleteTest.TestSearchHonoursItsLimitAndItsEmptyCase;
begin
  AssertEquals('a one-letter filter is capped, not answered in full',
    5, TyOptSearch('a', FList, 5));
  AssertEquals(5, FList.Count);

  { Empty is "show me the tree", not "show me nothing", and the caller decides
    which -- FilterChange checks for it before ever calling here.

    The early exit is belt-and-braces: FPC's Pos('', s) returns 0, so an empty
    needle already matches nothing, and removing the guard changes the cost of a
    cleared filter box (a full walk of 2,455 nodes on the keystroke that clears
    it) without changing this answer. The answer is what is pinned here, so it
    still catches a Pos that decided '' matches everything. }
  AssertEquals(0, TyOptSearch('', FList));
  AssertEquals(0, FList.Count);
  AssertEquals(0, TyOptSearch('   ', FList));

  AssertEquals('and a miss is a miss', 0, TyOptSearch('zzzznotakey', FList));
end;

initialization
  RegisterTest(TAdvChartCompleteTest);
end.
