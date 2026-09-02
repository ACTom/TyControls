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
     tyControls.AdvChart.Catalog, tyControls.AdvChart.Complete;
type
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

initialization
  RegisterTest(TAdvChartCompleteTest);
end.
