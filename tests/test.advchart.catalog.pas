unit test.advchart.catalog;
{$mode objfpc}{$H+}
{ The generated ECharts option catalog, and the lookup/validation over it.

  The most important test here is the DRIFT guard. The repo's other generated
  units are guarded two ways: the CSS catalog's test only checks that the
  catalog invents nothing (so anything ADDED upstream stays green -- explicitly
  not the model to copy), while tyControls.Icons.Lucide carries SHA-1 digests of
  both its input and its generator, which catches an upstream change nobody
  re-emitted AND a hand-edit of the generated file. This follows Lucide. }
interface
uses Classes, SysUtils, sha1, fpcunit, testregistry,
     tyControls.AdvChart.Catalog, tyControls.AdvChart.Complete,
     tyControls.AdvChart.Option;
type
  TAdvChartCatalogTest = class(TTestCase)
  private
    function RepoRoot: string;
    function ReadLF(const AFile: string): string;
  published
    { ---- drift ---- }
    procedure TestCatalogMatchesItsCommittedInput;
    procedure TestCatalogMatchesTheGeneratorThatProducedIt;
    procedure TestTheDagExpandsToTheRecordedOccurrenceCount;
    procedure TestCountsAreSelfConsistent;
    { ---- the vocabulary is really there ---- }
    procedure TestWellKnownPathsResolve;
    procedure TestSeriesIsAVariantContainerWithTwentyThreeMembers;
    procedure TestVariantsDifferFromEachOther;
    procedure TestTypesAndDefaultsCameThrough;
    procedure TestSinceVersionCameThrough;
    procedure TestEnumsCameThrough;
    procedure TestRenderItemReturnWasExcluded;
    procedure TestRichStyleNameIsAWildcard;
    { ---- lookup ---- }
    procedure TestUnknownPathReportsWhichSegmentFailed;
    procedure TestChildNamesExcludeStructuralEdges;
    procedure TestRuntimePathNeedsTheTreeToPickAVariant;
    { ---- validation ---- }
    procedure TestValidOptionHasNoIssues;
    procedure TestUnknownOptionIsReported;
    procedure TestAnUnknownSubtreeIsReportedOnce;
    procedure TestBadEnumValueIsReported;
    procedure TestAnUntypedSeriesIsNotReportedAsUnknownOptions;
  end;
implementation

function TAdvChartCatalogTest.RepoRoot: string;
begin
  { The test exe lives in tests/. Same idiom as test.designregistry. }
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

function TAdvChartCatalogTest.ReadLF(const AFile: string): string;
var st: TFileStream;
begin
  Result := '';
  st := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, st.Size);
    if st.Size > 0 then st.ReadBuffer(Result[1], st.Size);
  finally
    st.Free;
  end;
end;

{ ============================ drift ============================ }

procedure TAdvChartCatalogTest.TestCatalogMatchesItsCommittedInput;
var
  f, raw: string;
begin
  f := RepoRoot + 'tools' + PathDelim + 'advchart' + PathDelim + 'catalog.json';
  AssertTrue('the committed intermediate exists: ' + f, FileExists(f));
  raw := ReadLF(f);
  { Byte-for-byte, no newline normalisation: catalog.json is machine-written
    JSON on one line, so there are no line endings for a checkout to change. }
  AssertEquals('tyControls.AdvChart.Catalog.pas is out of date -- '
             + 'run: node tools/advchart/gen-catalog.js',
               TyOptCatalogDigest, UpperCase(SHA1Print(SHA1String(raw))));
end;

procedure TAdvChartCatalogTest.TestCatalogMatchesTheGeneratorThatProducedIt;
var
  f, src: string;
begin
  { Pins the TRANSFORMATION, not just the input. This is what catches a
    generator someone changed and never re-ran, and equally a hand-edit of the
    generated unit -- neither of which an input digest can see. }
  f := RepoRoot + 'tools' + PathDelim + 'advchart' + PathDelim + 'gen-catalog.js';
  AssertTrue('the generator exists: ' + f, FileExists(f));
  src := ReadLF(f);
  { CRLF -> LF, so a checkout with a different core.autocrlf does not turn this
    red for no reason. The generator digests itself the same way. }
  src := StringReplace(src, #13#10, #10, [rfReplaceAll]);
  AssertEquals('tyControls.AdvChart.Catalog.pas was produced by a different '
             + 'gen-catalog.js -- re-run: node tools/advchart/gen-catalog.js',
               TyOptGeneratorDigest, UpperCase(SHA1Print(SHA1String(src))));
end;

procedure TAdvChartCatalogTest.TestTheDagExpandsToTheRecordedOccurrenceCount;
var
  seen: array of Integer;

  function Expand(ANode: Integer): Integer;
  var i: Integer;
  begin
    { Deliberately NOT memoised: the point is to re-expand the DAG back into the
      tree it was folded from and check the total against the number the
      extractor recorded. A memoised walk would count each shape once and prove
      nothing about the folding being lossless. }
    Result := 1;
    for i := TyOptNodes[ANode].FirstChild to
             TyOptNodes[ANode].FirstChild + TyOptNodes[ANode].ChildCount - 1 do
      Result := Result + Expand(TyOptEdges[i].Node);
  end;

begin
  SetLength(seen, 0);
  AssertEquals('the DAG must expand to exactly the tree it was folded from',
               TyOptOccurrences, Expand(TyOptRoot));
end;

procedure TAdvChartCatalogTest.TestCountsAreSelfConsistent;
var
  i, edgeTotal: Integer;
begin
  AssertEquals('node count', TyOptNodeCount, Length(TyOptNodes));
  AssertEquals('edge count', TyOptEdgeCount, Length(TyOptEdges));
  AssertEquals('pool count', TyOptStrCount, Length(TyOptStr));
  AssertEquals('empty string is index 0', '', TyOptStr[0]);
  edgeTotal := 0;
  for i := 0 to High(TyOptNodes) do
  begin
    edgeTotal := edgeTotal + TyOptNodes[i].ChildCount;
    AssertTrue('node ' + IntToStr(i) + ' child slice is in range',
               (TyOptNodes[i].FirstChild >= 0) and
               (TyOptNodes[i].FirstChild + TyOptNodes[i].ChildCount <= Length(TyOptEdges)));
  end;
  AssertEquals('every edge belongs to exactly one node', Length(TyOptEdges), edgeTotal);
  for i := 0 to High(TyOptEdges) do
    AssertTrue('edge ' + IntToStr(i) + ' points at a real node',
               (TyOptEdges[i].Node >= 0) and (TyOptEdges[i].Node < Length(TyOptNodes)));
end;

{ =================== the vocabulary is really there =================== }

procedure TAdvChartCatalogTest.TestWellKnownPathsResolve;
const
  Paths: array[0..7] of string = (
    'grid.left', 'xAxis.type', 'yAxis.axisLabel.rotate', 'legend.orient',
    'tooltip.trigger', 'series-line.smooth', 'series-bar.stack',
    'series-pie.roseType');
var i: Integer;
    r: TTyOptLookup;
begin
  for i := 0 to High(Paths) do
  begin
    r := TyOptFind(Paths[i]);
    AssertTrue(Paths[i] + ' should be in the catalog (failed at segment '
               + IntToStr(r.FailedAt) + ': ' + r.FailedName + ')', r.Found);
  end;
end;

procedure TAdvChartCatalogTest.TestSeriesIsAVariantContainerWithTwentyThreeMembers;
var
  r: TTyOptLookup;
  tags: TStringList;
begin
  r := TyOptFind('series');
  AssertTrue('series resolves', r.Found);
  AssertTrue('series is a discriminated union', TyOptIsVariantContainer(r.Node));
  tags := TStringList.Create;
  try
    AssertTrue('it reports its tags', TyOptVariantTags(r.Node, tags));
    AssertEquals('ECharts 6.1 has 23 series types', 23, tags.Count);
    AssertTrue('line is one of them', tags.IndexOf('line') >= 0);
    AssertTrue('and so is custom', tags.IndexOf('custom') >= 0);
  finally
    tags.Free;
  end;
end;

procedure TAdvChartCatalogTest.TestVariantsDifferFromEachOther;
begin
  { The whole reason the catalog is variant-qualified. If these resolved the
    same, `series[0].itemStyle` would mean one thing for twenty-three shapes. }
  AssertTrue('bar has stack', TyOptFind('series-bar.stack').Found);
  AssertFalse('pie does not', TyOptFind('series-pie.stack').Found);
  AssertTrue('pie has roseType', TyOptFind('series-pie.roseType').Found);
  AssertFalse('bar does not', TyOptFind('series-bar.roseType').Found);
end;

procedure TAdvChartCatalogTest.TestTypesAndDefaultsCameThrough;
var
  r: TTyOptLookup;
  def: string;
begin
  r := TyOptFind('grid.show');
  AssertTrue('grid.show resolves', r.Found);
  AssertEquals('its type', 'boolean', TyOptTypeOf(r.Node));
  AssertTrue('it has a default', TyOptDefaultOf(r.Node, def));
  AssertEquals('and the default is false', 'false', def);

  r := TyOptFind('grid.left');
  AssertTrue('grid.left resolves', r.Found);
  { A union type is kept verbatim -- 'left' really can be a number or a string,
    and flattening that to one type would make the validator wrong. }
  AssertEquals('its type is a union', 'string|number', TyOptTypeOf(r.Node));
end;

procedure TAdvChartCatalogTest.TestSinceVersionCameThrough;
var
  r: TTyOptLookup;
  v: string;
begin
  { The version markers live only inside the description HTML in the source
    schema; if the extraction regex ever stops matching, every option silently
    becomes unversioned rather than failing loudly. }
  r := TyOptFind('grid.outerBoundsMode');
  AssertTrue('a v6 option resolves', r.Found);
  v := TyOptSinceOf(r.Node);
  AssertEquals('outerBoundsMode is new in ECharts 6', '6.0.0', v);
  r := TyOptFind('grid.left');
  AssertEquals('an old option carries no version', '', TyOptSinceOf(r.Node));
end;

procedure TAdvChartCatalogTest.TestEnumsCameThrough;
var
  r: TTyOptLookup;
  list: TStringList;
begin
  r := TyOptFind('legend.orient');
  AssertTrue('legend.orient resolves', r.Found);
  list := TStringList.Create;
  try
    AssertTrue('it is enumerated', TyOptEnumOf(r.Node, list));
    AssertEquals('two values', 2, list.Count);
    AssertTrue('horizontal', list.IndexOf('horizontal') >= 0);
    AssertTrue('vertical', list.IndexOf('vertical') >= 0);
  finally
    list.Free;
  end;
end;

procedure TAdvChartCatalogTest.TestRenderItemReturnWasExcluded;
begin
  { renderItem.return_* documents the JS return value of a callback, not option
    paths. Offering them in completion would be a lie, so the extractor drops
    them -- and this is the guard that it kept dropping them. }
  AssertTrue('custom has renderItem', TyOptFind('series-custom.renderItem').Found);
  AssertFalse('but not its return shapes',
              TyOptFind('series-custom.renderItem.return_rect').Found);
end;

procedure TAdvChartCatalogTest.TestRichStyleNameIsAWildcard;
begin
  { Rich-text style names are user-chosen. Without wildcard resolution every
    real style name would validate as an unknown option. }
  AssertTrue('a made-up style name resolves',
             TyOptFind('title.textStyle.rich.myOwnStyle.color').Found);
  AssertTrue('and so does another',
             TyOptFind('title.textStyle.rich.header.fontSize').Found);
end;

{ ============================ lookup ============================ }

procedure TAdvChartCatalogTest.TestUnknownPathReportsWhichSegmentFailed;
var r: TTyOptLookup;
begin
  r := TyOptFind('grid.notAnOption');
  AssertFalse('rejected', r.Found);
  { An editor has to underline something. A bare False would leave it guessing. }
  AssertEquals('the failing segment index', 1, r.FailedAt);
  AssertEquals('and its text', 'notAnOption', r.FailedName);
end;

procedure TAdvChartCatalogTest.TestChildNamesExcludeStructuralEdges;
var
  r: TTyOptLookup;
  list: TStringList;
  i: Integer;
begin
  r := TyOptFind('series');
  list := TStringList.Create;
  try
    TyOptChildNames(r.Node, list);
    { '=line' and '[]' are spellings the schema invented; a completion list that
      offered them would be offering things nobody can type. }
    for i := 0 to list.Count - 1 do
    begin
      AssertTrue('no variant edges in completion: ' + list[i],
                 Copy(list[i], 1, 1) <> '=');
      AssertTrue('no array edges either: ' + list[i], list[i] <> '[]');
    end;
  finally
    list.Free;
  end;
end;

procedure TAdvChartCatalogTest.TestRuntimePathNeedsTheTreeToPickAVariant;
var
  opt: TTyChartOption;
  r: TTyOptLookup;
begin
  opt := TTyChartOption.Create;
  try
    opt.SetOptionText('{ series: [{ type: ''bar'', stack: ''x'' }] }');
    r := TyOptFindFor(opt, 'series[0].stack');
    AssertTrue('with type:bar in the tree, stack resolves', r.Found);

    opt.SetOptionText('{ series: [{ type: ''pie'' }] }');
    r := TyOptFindFor(opt, 'series[0].stack');
    AssertFalse('with type:pie it does not -- which is the point', r.Found);
  finally
    opt.Free;
  end;
end;

{ ============================ validation ============================ }

procedure TAdvChartCatalogTest.TestValidOptionHasNoIssues;
var
  opt: TTyChartOption;
  issues: TTyOptIssueArray;
  i: Integer;
  msg: string;
begin
  opt := TTyChartOption.Create;
  try
    opt.SetOptionText(
      '{ xAxis: { type: ''category'', data: [''Mon'',''Tue''] },' +
      '  yAxis: { type: ''value'' },' +
      '  series: [{ type: ''bar'', name: ''Sales'', data: [1,2] }] }');
    issues := TyOptValidate(opt);
    msg := '';
    for i := 0 to High(issues) do
      msg := msg + ' ' + issues[i].Path;
    AssertEquals('a textbook config must validate clean, got:' + msg, 0, Length(issues));
  finally
    opt.Free;
  end;
end;

procedure TAdvChartCatalogTest.TestUnknownOptionIsReported;
var
  opt: TTyChartOption;
  issues: TTyOptIssueArray;
begin
  opt := TTyChartOption.Create;
  try
    opt.SetOptionText('{ grid: { lefft: 10 } }');
    issues := TyOptValidate(opt);
    AssertEquals('one issue', 1, Length(issues));
    AssertTrue('it is an unknown option', issues[0].Kind = oikUnknownOption);
    AssertEquals('named by its full path', 'grid.lefft', issues[0].Path);
  finally
    opt.Free;
  end;
end;

procedure TAdvChartCatalogTest.TestAnUnknownSubtreeIsReportedOnce;
var
  opt: TTyChartOption;
  issues: TTyOptIssueArray;
begin
  opt := TTyChartOption.Create;
  try
    { One misspelled container must not produce a page of noise about everything
      inside it. }
    opt.SetOptionText('{ giid: { left: 1, top: 2, backgroundColor: ''#fff'' } }');
    issues := TyOptValidate(opt);
    AssertEquals('just the container', 1, Length(issues));
    AssertEquals('giid', issues[0].Path);
  finally
    opt.Free;
  end;
end;

procedure TAdvChartCatalogTest.TestBadEnumValueIsReported;
var
  opt: TTyChartOption;
  issues: TTyOptIssueArray;
begin
  opt := TTyChartOption.Create;
  try
    opt.SetOptionText('{ legend: { orient: ''sideways'' } }');
    issues := TyOptValidate(opt);
    AssertEquals('one issue', 1, Length(issues));
    AssertTrue('a bad enum value', issues[0].Kind = oikBadEnumValue);
    AssertEquals('legend.orient', issues[0].Path);
    AssertEquals('sideways', issues[0].Value);
    { The message has to say what IS allowed, or the user is left guessing. }
    AssertTrue('and it lists what is allowed: ' + issues[0].Allowed,
               Pos('horizontal', issues[0].Allowed) > 0);
  finally
    opt.Free;
  end;
end;

procedure TAdvChartCatalogTest.TestAnUntypedSeriesIsNotReportedAsUnknownOptions;
var
  opt: TTyChartOption;
  issues: TTyOptIssueArray;
begin
  opt := TTyChartOption.Create;
  try
    { A series with no `type` cannot be resolved to a variant. Reporting all of
      its perfectly good options as unknown would be actively misleading -- the
      thing that is missing is the type, not the options. }
    opt.SetOptionText('{ series: [{ name: ''x'', data: [1,2,3] }] }');
    issues := TyOptValidate(opt);
    AssertEquals('nothing is claimed to be unknown', 0, Length(issues));
  finally
    opt.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartCatalogTest);
end.
