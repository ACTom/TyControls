unit test.advchart.diagnose;
{$mode objfpc}{$H+}
{ The editor's whole analysis, as one call.

  These are the assertions the design-time dialog would otherwise carry alone,
  where nothing could run them: designtime/ is not in the test build. So the
  question each one answers is not "does the code work" but "is this the right
  thing to SAY, in the right order, pointing at the right place". }
interface
uses Classes, SysUtils, fpcunit, testregistry,
     tyControls.AdvChart.Diagnose;
type
  TAdvChartDiagnoseTest = class(TTestCase)
  private
    function Kinds(const AText: string): string;
    function FirstOf(const AText: string; AKind: TTyOptDiagKind;
      out ADiag: TTyOptDiag): Boolean;
  published
    procedure TestAGoodConfigSaysOnlyThatNothingPaintsYet;
    procedure TestTextThatDoesNotParseYieldsExactlyOneThing;
    procedure TestAPastedJsFunctionIsToldWhatToWriteInstead;
    procedure TestATypoIsNamedPositionedAndGuessedAt;
    procedure TestATypoTwoLevelsDeepStillPointsAtItself;
    procedure TestAMisspelledContainerIsReportedOnceNotPerChild;
    procedure TestABadEnumNamesWhatIsAllowed;
    procedure TestAxisTypeIsNotEnumeratedAndTheBuildSaysSo;
    procedure TestAnUntypedSeriesSaysSoInsteadOfCallingItsKeysUnknown;
    procedure TestABuildProblemIsReportedAndPositioned;
    procedure TestABareObjectDiagnosticStillFindsItsKey;
    procedure TestNothingPaintsYetIsSilentWhenSomethingElseIsWrong;
    procedure TestHostileButParseableTextDoesNotRaise;
    procedure TestABareComponentIsNotCalledUnknown;
    procedure TestATypoInsideTheArrayFormIsStillFound;
    procedure TestATopLevelTypoIsGuessedAtToo;
    procedure TestTheAllClearDoesNotPromiseAxesToAPie;
    procedure TestAValidOptionWithNoSeriesStillSaysSomething;
    procedure TestAnUntypedSeriesIsReportedOnceNotTwice;
    procedure TestTheListIsInTextOrder;
    procedure TestFormatTidiesAndRefusesWhatItCannotParse;
    procedure TestRepeatedDiagnosisDoesNotGrowTheHeap;
  end;

implementation

uses tyControls.StrConsts;

function TAdvChartDiagnoseTest.Kinds(const AText: string): string;
const
  cNames: array[TTyOptDiagKind] of string = (
    'parse', 'unknown', 'enum', 'notype', 'build', 'ok');
var
  all: TTyOptDiagArray;
  i: Integer;
begin
  Result := '';
  all := TyOptDiagnose(AText);
  for i := 0 to High(all) do
  begin
    if Result <> '' then Result := Result + ' ';
    Result := Result + cNames[all[i].Kind];
  end;
end;

function TAdvChartDiagnoseTest.FirstOf(const AText: string;
  AKind: TTyOptDiagKind; out ADiag: TTyOptDiag): Boolean;
var
  all: TTyOptDiagArray;
  i: Integer;
begin
  Result := False;
  ADiag := Default(TTyOptDiag);
  all := TyOptDiagnose(AText);
  for i := 0 to High(all) do
    if all[i].Kind = AKind then
    begin
      ADiag := all[i];
      Exit(True);
    end;
end;

procedure TAdvChartDiagnoseTest.TestAGoodConfigSaysOnlyThatNothingPaintsYet;
begin
  { The one case where saying nothing would be WRONG. A correct bar config
    draws axes and no bars today, and a developer told nothing concludes the
    editor lied to them. }
  AssertEquals('ok', Kinds('{ xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1] }] }'));
end;

procedure TAdvChartDiagnoseTest.TestTextThatDoesNotParseYieldsExactlyOneThing;
var d: TTyOptDiag;
begin
  { And nothing else. Everything below the parse derives from a tree; with no
    tree there is nothing honest to derive, and a page of consequences would
    bury the one line that matters. }
  AssertEquals('parse', Kinds('{ xAxis: { data: ['));
  { NOT on line one: there, a position carried through and a position of 1
    invented from nowhere are the same number. }
  AssertTrue(FirstOf('{' + LineEnding + '  xAxis: {' + LineEnding
    + '    data: [' , odkParseError, d));
  AssertEquals('the parser''s own line comes through', 3, d.Line);
  { The COLUMN is best-effort and often absent: it is scraped out of fpjson's
    message text, which carries a line for this failure and no 'Pos'. Asserting
    a column here would be asserting something the parser does not promise --
    and Line alone is what the editor needs to jump. }
end;

procedure TAdvChartDiagnoseTest.TestAPastedJsFunctionIsToldWhatToWriteInstead;
var d: TTyOptDiag;
begin
  { Pasting a config off the web is the reason the option tree is a string, so
    the commonest paste failure gets the commonest answer. }
  AssertTrue(FirstOf('{ tooltip: { formatter: function (p) { return p; } } }',
    odkParseError, d));
  AssertTrue('names the template form, got: ' + d.Text, Pos('{b}', d.Text) > 0);
  AssertTrue('and the handler form', Pos('@', d.Text) > 0);
end;

procedure TAdvChartDiagnoseTest.TestATypoIsNamedPositionedAndGuessedAt;
var d: TTyOptDiag;
begin
  AssertTrue(FirstOf('{ xAxis: { axisLabl: {} } }', odkUnknownOption, d));
  AssertEquals('xAxis.axisLabl', d.Path);
  AssertTrue('names the offender, got: ' + d.Text,
    Pos('xAxis.axisLabl', d.Text) > 0);
  AssertTrue('and guesses, got: ' + d.Text, Pos('axisLabel', d.Text) > 0);
  AssertEquals('and points at it', 1, d.Line);
  AssertTrue('with a column inside the line', d.Col > 1);
  AssertEquals('and a length to select', 8, d.Len);
end;

procedure TAdvChartDiagnoseTest.TestATypoTwoLevelsDeepStillPointsAtItself;
var d: TTyOptDiag;
begin
  { Not at its container. The nearest-key fallback exists for paths nobody
    typed; a key that IS in the text must be found exactly. }
  AssertTrue(FirstOf('{' + LineEnding + '  xAxis: {' + LineEnding
    + '    axisLabel: { colour: 1 }' + LineEnding + '  }' + LineEnding + '}',
    odkUnknownOption, d));
  AssertEquals('xAxis.axisLabel.colour', d.Path);
  AssertEquals('the line the typo is on', 3, d.Line);
  { THE LINE ALONE PROVES NOTHING HERE: axisLabel and colour are both on line
    3, so a fallback that landed on the container would satisfy it. The column
    is what separates them. }
  AssertEquals('the column of the typo itself', 18, d.Col);
  AssertEquals(6, d.Len);
end;

procedure TAdvChartDiagnoseTest.TestAMisspelledContainerIsReportedOnceNotPerChild;
begin
  { One wrong word must not produce a page. The tree walk stops at an
    unresolvable node, and this is the test that says so out loud. }
  AssertEquals('unknown', Kinds('{ xAxes: { a: 1, b: 2, c: 3 } }'));
end;

procedure TAdvChartDiagnoseTest.TestABadEnumNamesWhatIsAllowed;
var d: TTyOptDiag;
begin
  { xAxis.position, whose schema really does enumerate top and bottom. }
  AssertTrue(FirstOf('{ xAxis: { position: ''middle'' }, yAxis: {} }',
    odkBadEnumValue, d));
  { Swapping the two roles used to leave this green: both words appear either
    way. What carries the roles is the QUOTING and the order. }
  AssertTrue('quotes what was written, got: ' + d.Text,
    Pos('"middle"', d.Text) > 0);
  AssertTrue('and lists what is allowed AFTER it, got: ' + d.Text,
    Pos('bottom', d.Text) > Pos('"middle"', d.Text));
end;

procedure TAdvChartDiagnoseTest.TestAxisTypeIsNotEnumeratedAndTheBuildSaysSo;
var d: TTyOptDiag;
begin
  { THE OBVIOUS FIXTURE FOR AN ENUM TEST IS THE WRONG ONE, and it caught me:
    `xAxis.type` looks like the most enumerated option in the whole schema, and
    it carries NO enumeration at all -- it is one of the 5,776 string options
    whose allowed values live only in prose. TyOptEnumOf's own comment says so.

    So a misspelled axis type is not an enum problem; it reaches the user from
    the BUILD, which resolves the axis type itself and says what it fell back
    to. Pinned because an editor that stayed silent here would be the obvious
    consequence of assuming otherwise. }
  AssertFalse('the catalog does not enumerate it',
    FirstOf('{ xAxis: { type: ''categroy'' }, yAxis: {} }',
      odkBadEnumValue, d));
  AssertTrue('but the build still tells the user',
    FirstOf('{ xAxis: { type: ''categroy'' }, yAxis: {} }', odkBuild, d));
  AssertTrue('naming what was written, got: ' + d.Text,
    Pos('categroy', d.Text) > 0);
end;

procedure TAdvChartDiagnoseTest.TestAnUntypedSeriesSaysSoInsteadOfCallingItsKeysUnknown;
var
  all: TTyOptDiagArray;
  i: Integer;
  d: TTyOptDiag;
begin
  { The catalog kernel is deliberately SILENT here -- an untyped series' keys
    are not unknown, they are unknowable -- and a test over there pins that it
    stays silent. So the useful sentence has to come from this layer. }
  all := TyOptDiagnose('{ xAxis: {}, yAxis: {}, series: [{ data: [1, 2] }] }');
  for i := 0 to High(all) do
    AssertTrue('nothing under an untyped series is called unknown: ' + all[i].Text,
      all[i].Kind <> odkUnknownOption);
  AssertTrue(FirstOf('{ xAxis: {}, yAxis: {}, series: [{ data: [1, 2] }] }',
    odkNoSeriesType, d));
  AssertTrue('offers the tags, got: ' + d.Text, Pos('bar', d.Text) > 0);
  AssertEquals('and points into the text', 1, d.Line);
end;

procedure TAdvChartDiagnoseTest.TestABuildProblemIsReportedAndPositioned;
var d: TTyOptDiag;
begin
  { An option the catalog is perfectly happy with, that no chart can be made
    of. This is the whole reason this unit needs Builder and Series, and it is
    why it is not part of Complete. }
  AssertTrue(FirstOf('{ xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', yAxisIndex: 7, data: [1] }] }',
    odkBuild, d));
  { 'series' appears in five of the eleven build sentences, so matching it
    proves only that SOME build diagnostic fired. Match the one this fixture is
    about, and pin where it points. }
  AssertTrue('names the missing axis, got: ' + d.Text,
    Pos('does not exist', d.Text) > 0);
  AssertEquals('series[0]', d.Path);
  AssertTrue('and it landed in the text', d.Line > 0);
end;

procedure TAdvChartDiagnoseTest.TestABareObjectDiagnosticStillFindsItsKey;
var d: TTyOptDiag;
begin
  { TWO PRODUCERS, TWO SPELLINGS. A bare `xAxis: {...}` is component 0 to the
    builder, so its diagnostic says xAxis[0].type; the text has no subscript at
    all. The caret still has to land on the key. }
  AssertTrue(FirstOf('{ xAxis: { type: ''categroy'' }, yAxis: {} }',
    odkBuild, d));
  AssertEquals('the builder''s subscripted spelling', 'xAxis[0].type', d.Path);
  { NOT `d.Line > 0`, which the container fallback satisfies just as well --
    and the whole point of the [0]-stripping is that it does NOT fall back to
    the container. The column is the discriminator. }
  AssertEquals('landed on `type`, not on `xAxis`', 12, d.Col);
  AssertEquals(4, d.Len);
end;

procedure TAdvChartDiagnoseTest.TestNothingPaintsYetIsSilentWhenSomethingElseIsWrong;
begin
  { It is the "all clear", so it must not appear beside a complaint. The
    fixture is a COMPLETE chart with one typo in it -- an earlier version had
    only an xAxis, and the build's entirely correct grumble about the missing
    yAxis made the assertion about the wrong thing. }
  AssertEquals('unknown', Kinds('{ xAxis: { axisLabl: {} }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1] }] }'));
end;

procedure TAdvChartDiagnoseTest.TestHostileButParseableTextDoesNotRaise;
var all: TTyOptDiagArray;
begin
  { `{ xAxis: { name: [1] } }` is legal JSON in a shape the builder reads as a
    string. AsString on an array RAISES, and the raise escaped before
    TyBuildGrids returned -- so the caller's build variable was never assigned,
    its try/finally never ran, and the whole build leaked. On a design-time
    timer that is an exception per keystroke.

    Every other fixture in this suite is well-typed at every key the builder
    string-reads, which is exactly why nothing here saw it. }
  all := TyOptDiagnose('{ xAxis: { name: [1] }, yAxis: {} }');
  AssertTrue('it returned at all', Length(all) >= 0);
  all := TyOptDiagnose('{ series: [{ type: {} }] }');
  AssertTrue('and again for a non-scalar series type', Length(all) >= 0);
  all := TyOptDiagnose('{ xAxis: { type: [] }, yAxis: {} }');
  AssertTrue('and for a non-scalar axis type', Length(all) >= 0);
end;

procedure TAdvChartDiagnoseTest.TestABareComponentIsNotCalledUnknown;
var
  all: TTyOptDiagArray;
  i: Integer;
begin
  { The bare-object form is what ECharts' own documentation writes. Validation
    resolved no variant for it, so every key under it -- INCLUDING `type` --
    came back as "not an option ECharts knows": a perfectly good config turned
    into a page of complaints. }
  all := TyOptDiagnose('{ xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: { type: ''bar'', data: [1] } }');
  for i := 0 to High(all) do
    AssertTrue('a bare series is not a pile of unknown options: ' + all[i].Text,
      all[i].Kind <> odkUnknownOption);
end;

procedure TAdvChartDiagnoseTest.TestATypoInsideTheArrayFormIsStillFound;
var d: TTyOptDiag;
begin
  { xAxis has no '[]' element node -- the schema describes one axis and lets
    you write a list -- and the walk used to skip an array without one
    entirely. So a typo inside `xAxis: [{ ... }]` produced NO issue and the
    editor said all clear. }
  AssertTrue(FirstOf('{ xAxis: [{ axisLabl: {} }], yAxis: [{}] }',
    odkUnknownOption, d));
  AssertEquals('xAxis[0].axisLabl', d.Path);
end;

procedure TAdvChartDiagnoseTest.TestATopLevelTypoIsGuessedAtToo;
var d: TTyOptDiag;
begin
  { The parent of a root key is the root, and asking the resolver for '' got
    nothing -- so the easiest suggestion in the whole editor was the one place
    it never appeared. }
  AssertTrue(FirstOf('{ xAxes: {} }', odkUnknownOption, d));
  AssertTrue('guesses xAxis, got: ' + d.Text, Pos('xAxis', d.Text) > 0);
end;

procedure TAdvChartDiagnoseTest.TestTheAllClearDoesNotPromiseAxesToAPie;
var d: TTyOptDiag;
begin
  { A pie resolves with no axes at all. Telling its author the chart "draws its
    axes" is precisely the lie this row exists to prevent. }
  AssertTrue(FirstOf('{ series: [{ type: ''pie'', data: [1] }] }',
    odkNothingPaintsYet, d));
  AssertTrue('does not promise axes, got: ' + d.Text,
    Pos('draws its axes', d.Text) = 0);
end;

procedure TAdvChartDiagnoseTest.TestAValidOptionWithNoSeriesStillSaysSomething;
begin
  { An empty list is the silence the all-clear was invented to prevent, and the
    `resolved > 0` gate produced exactly that for an option with no series. }
  AssertEquals('ok', Kinds('{ xAxis: {}, yAxis: {} }'));
  AssertEquals('and for nothing at all', 'ok', Kinds('{}'));
end;

procedure TAdvChartDiagnoseTest.TestAnUntypedSeriesIsReportedOnceNotTwice;
begin
  { Two producers notice it -- this unit and the builder -- in two different
    sentences about the same element. Two rows saying the same thing is how a
    diagnostics list stops being read. FirstOf hid the duplicate; Kinds cannot. }
  AssertEquals('notype',
    Kinds('{ xAxis: {}, yAxis: {}, series: [{ data: [1, 2] }] }'));
end;

procedure TAdvChartDiagnoseTest.TestTheListIsInTextOrder;
var
  all: TTyOptDiagArray;
  i: Integer;
begin
  { The rows are caret targets read top to bottom, so their order has to be the
    text's -- not the order of the three passes that produced them. }
  all := TyOptDiagnose('{' + LineEnding
    + '  xAxis: { position: ''middle'', axisLabl: {} },' + LineEnding
    + '  yAxis: {},' + LineEnding
    + '  series: [{ data: [1] }]' + LineEnding + '}');
  AssertTrue('several things are wrong', Length(all) >= 3);
  for i := 1 to High(all) do
    AssertTrue(Format('row %d is at line %d after a row at line %d',
      [i, all[i].Line, all[i - 1].Line]), all[i].Line >= all[i - 1].Line);
end;

procedure TAdvChartDiagnoseTest.TestFormatTidiesAndRefusesWhatItCannotParse;
var
  outp: string;
begin
  AssertTrue(TyOptFormat('{xAxis:{show:true}}', outp));
  AssertTrue('it reformatted, got: ' + outp, Length(outp) > Length('{xAxis:{show:true}}'));
  AssertTrue('and it is still about the same option', Pos('xAxis', outp) > 0);

  { A Format button must never eat what somebody was in the middle of
    writing. }
  AssertFalse(TyOptFormat('{ xAxis: {', outp));
  AssertEquals('the input comes back untouched', '{ xAxis: {', outp);
end;

procedure TAdvChartDiagnoseTest.TestRepeatedDiagnosisDoesNotGrowTheHeap;
var
  before, after: PtrUInt;
  i: Integer;
begin
  { This runs on a timer while somebody types. It builds a whole chart model
    per call and throws it away; one leaked build per keystroke inside a
    long-running IDE is a real leak, and nothing else in this suite would
    notice. }
  for i := 1 to 20 do
    TyOptDiagnose('{ xAxis: { data: [''A''] }, yAxis: {},'
      + ' series: [{ type: ''bar'', data: [1] }] }');
  before := GetFPCHeapStatus.CurrHeapUsed;
  for i := 1 to 200 do
    TyOptDiagnose('{ xAxis: { data: [''A''] }, yAxis: {},'
      + ' series: [{ type: ''bar'', data: [1] }] }');
  after := GetFPCHeapStatus.CurrHeapUsed;
  AssertTrue(Format('heap grew from %d to %d over two hundred calls',
    [before, after]), after <= before + 65536);
end;

initialization
  RegisterTest(TAdvChartDiagnoseTest);
end.
