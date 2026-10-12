unit test.advchart.serieseditor;
{$mode objfpc}{$H+}
{ The design-time series and data editor, everything but the dialog. [Batch 143]

  Three things are held here:

  - THE PATCH (TTyOptTextPatcher). Every output read back by the option's own
    reader is the tree that was patched in -- that is correctness, and it is
    checked on hand-written cases, on random edits of every gallery option,
    and after every model operation. On top of it, fidelity: what did NOT
    change keeps its text byte for byte, and the hand-written cases pin the
    exact text a cut, an append, an insert or a move leaves behind.
  - THE MODEL (TTySeriesEditModel). List operations, the catalog-driven
    fields, the data grid in both directions, the cell typing rules, the
    category-row rule, datasets, and what it says it will cost.
  - THE ROUND TRIP over the 245 gallery options: load and write back with no
    edit gives the text back byte for byte -- including after applying every
    data grid unchanged and writing every field's own text back into it.

  The dialog itself is outside the test build; TheSeriesDialogStaysAShell
  reads its file and fails if it reaches past the model. }
interface
uses Classes, SysUtils, fpcunit, testregistry, fpjson,
     tyControls.AdvChart.TextPatch, tyControls.AdvChart.SeriesEdit;

type
  TAdvChartTextPatchTest = class(TTestCase)
  published
    procedure TestNoEditGivesTheTextBack;
    procedure TestAChangedScalarCostsOneToken;
    procedure TestARemovedMemberTakesItsComma;
    procedure TestAnAddedMemberFollowsTheLayout;
    procedure TestALineCommentStaysWithItsMember;
    procedure TestArraysKeepTheirHeadAndTail;
    procedure TestAMovedElementKeepsItsText;
    procedure TestCommentsInARewrittenValueAreCounted;
    procedure TestTheStyleIsReadOffTheDocument;
    procedure TestATextThatCannotBeMappedIsWrittenWhole;
    procedure TestSameMeansWhatTheOptionMeans;
    procedure TestRandomEditsOfTheGalleryReadBackAsEdited;
  end;

  TAdvChartSeriesEditTest = class(TTestCase)
  published
    procedure TestLoadRefusesWhatIsNotAnOption;
    procedure TestTheSeriesListAddsDeletesAndMoves;
    procedure TestABareSeriesBecomesAListWhenTheListChanges;
    procedure TestAnEditedSeriesThatMovedKeepsItsText;
    procedure TestTheFieldsFollowTheCatalog;
    procedure TestAFieldEditWritesOnlyThatKey;
    procedure TestABadFieldValueChangesNothing;
    procedure TestTheShownTextWrittenBackChangesNothing;
    procedure TestTheCategoryGrid;
    procedure TestARowIsACategory;
    procedure TestThePairGridAndItsColumns;
    procedure TestItemObjectsKeepWhatTheGridDoesNotShow;
    procedure TestACellKeepsItsKind;
    procedure TestOnlyOneValueCartesianDataTakesCategories;
    procedure TestTheDatasetGrids;
    procedure TestWhatTheGridCannotShowSaysWhy;
    procedure TestApplyingTwiceIsApplyingOnce;
    procedure TestALostCommentIsReportedBeforeAnything;
    procedure TestAWholeRewriteIsAskedFirst;
    procedure TestTheDiagnosticsSeeTheEditedText;
    procedure TheSeriesDialogStaysAShell;
  end;

  TAdvChartSeriesEditGalleryTest = class(TTestCase)
  private
    function GalleryDir: string;
  published
    procedure TestEveryGalleryOptionComesBackByteForByte;
    procedure TestGalleryEditsReadBackAsEdited;
  end;

implementation

uses Math, tyControls.AdvChart.Option, tyControls.AdvChart.Diagnose,
  tyControls.StrConsts;

const
  LF = #10;

function Reparse(const AText: string): TJSONData;
var err: TTyOptionError;
begin
  if not TyOptionParseRaw(AText, Result, err) then
    raise Exception.Create('does not read back: ' + err.Message + LF + AText);
end;

function ReadsBackAs(const AText: string; ATree: TJSONData): Boolean;
var d: TJSONData;
begin
  d := Reparse(AText);
  try
    Result := TyOptJsonSame(d, ATree);
  finally
    d.Free;
  end;
end;

{ How much of B differs from A: B's length minus the prefix and suffix the
  two share. }
function ChangedLength(const A, B: string): Integer;
var p, s, n: Integer;
begin
  n := Min(Length(A), Length(B));
  p := 0;
  while (p < n) and (A[p + 1] = B[p + 1]) do Inc(p);
  s := 0;
  while (s < n - p) and (A[Length(A) - s] = B[Length(B) - s]) do Inc(s);
  Result := Length(B) - p - s;
end;

{ AText with ANew patched in, where ANew is AText's tree after AEdit. }
type
  TTreeEdit = procedure(ARoot: TJSONObject);

function PatchWith(const AText: string; AEdit: TTreeEdit; out ALost: Integer): string;
var
  orig, work: TJSONData;
  p: TTyOptTextPatcher;
begin
  orig := Reparse(AText);
  work := orig.Clone;
  p := TTyOptTextPatcher.Create(AText, orig);
  try
    AEdit(TJSONObject(work));
    Result := p.Patch(work);
    ALost := p.Lost;
    if not ReadsBackAs(Result, work) then
      raise Exception.Create('patched text does not read back as the edit:' + LF + Result);
  finally
    p.Free;
    work.Free;
    orig.Free;
  end;
end;

function Obj(ARoot: TJSONObject; const AKey: string): TJSONObject;
begin
  Result := TJSONObject(ARoot.Find(AKey));
end;

{ ---- the edits the patch tests apply ---- }

procedure EdB3(R: TJSONObject); begin R.Elements['b'] := TJSONIntegerNumber.Create(3); end;
procedure EdDelA(R: TJSONObject); begin R.Delete('a'); end;
procedure EdDelB(R: TJSONObject); begin R.Delete('b'); end;
procedure EdDelC(R: TJSONObject); begin R.Delete('c'); end;
procedure EdDelBC(R: TJSONObject); begin R.Delete('b'); R.Delete('c'); end;
procedure EdDelABC(R: TJSONObject); begin R.Delete('a'); R.Delete('b'); R.Delete('c'); end;
procedure EdAddD(R: TJSONObject); begin R.Add('d', 4); end;
procedure EdCutCAddD(R: TJSONObject); begin R.Delete('c'); R.Add('d', 4); end;
procedure EdAddBx(R: TJSONObject); begin R.Add('b', 'x'); end;
procedure EdAddB1(R: TJSONObject); begin R.Add('b', 1); end;
procedure EdAddA1(R: TJSONObject); begin R.Add('a', 1); end;
procedure EdSwapAB(R: TJSONObject); begin R.Delete('a'); R.Add('b', 2); end;
procedure EdAddBC(R: TJSONObject); begin R.Add('b-c', 1); end;
procedure EdAddObj(R: TJSONObject);
var o: TJSONObject;
begin
  o := TJSONObject.Create;
  o.Add('x', TJSONArray.Create([1, 2]));
  R.Add('o', o);
end;
procedure EdA5(R: TJSONObject); begin R.Elements['a'] := TJSONIntegerNumber.Create(5); end;

procedure EdArr20(R: TJSONObject); begin TJSONArray(R.Find('v')).Items[1] := TJSONIntegerNumber.Create(20); end;
procedure EdArrAppend(R: TJSONObject); begin TJSONArray(R.Find('v')).Add(4); end;
procedure EdArrPrepend(R: TJSONObject); begin TJSONArray(R.Find('v')).Insert(0, 0); end;
procedure EdArrDelMid(R: TJSONObject); begin TJSONArray(R.Find('v')).Delete(1); end;
procedure EdArrDelLast(R: TJSONObject); begin TJSONArray(R.Find('v')).Delete(2); end;
procedure EdArrAppend3(R: TJSONObject); begin TJSONArray(R.Find('v')).Add(3); end;
procedure EdArrSwap(R: TJSONObject); begin TJSONArray(R.Find('v')).Move(1, 0); end;

{ ==================== the patch ==================== }

procedure TAdvChartTextPatchTest.TestNoEditGivesTheTextBack;
const
  cTexts: array[0..5] of string = (
    '{ a: 1, // keep' + LF + '  b: [1, 2,], }',
    '/* head */ {"a": "x"} // tail' + LF,
    '{' + #13#10 + '    a: { b: [ 1 , 2 ] },' + #13#10 + '}',
    '{}',
    '{ s: ''it\''s'', t: "中", u: "中" }',
    '{ series: [ { type: ''bar'', data: [1, /* two */ 2] } ] }');
var
  i, lost: Integer;
  orig, work: TJSONData;
  p: TTyOptTextPatcher;
begin
  for i := 0 to High(cTexts) do
  begin
    orig := Reparse(cTexts[i]);
    work := orig.Clone;
    p := TTyOptTextPatcher.Create(cTexts[i], orig);
    try
      AssertTrue('mapped: ' + cTexts[i], p.Mapped);
      AssertEquals('byte for byte', cTexts[i], p.Patch(work));
      lost := p.Lost;
      AssertEquals('nothing lost', 0, lost);
    finally
      p.Free;
      work.Free;
      orig.Free;
    end;
  end;
end;

procedure TAdvChartTextPatchTest.TestAChangedScalarCostsOneToken;
var lost: Integer;
begin
  AssertEquals('{ a: 1, // keep' + LF + '  b: 3 }',
    PatchWith('{ a: 1, // keep' + LF + '  b: 2 }', @EdB3, lost));
  AssertEquals(0, lost);
end;

procedure TAdvChartTextPatchTest.TestARemovedMemberTakesItsComma;
const
  T = '{' + LF + '  a: 1,' + LF + '  b: 2,' + LF + '  c: 3' + LF + '}';
var lost: Integer;
begin
  AssertEquals('first', '{' + LF + '  b: 2,' + LF + '  c: 3' + LF + '}',
    PatchWith(T, @EdDelA, lost));
  AssertEquals('middle', '{' + LF + '  a: 1,' + LF + '  c: 3' + LF + '}',
    PatchWith(T, @EdDelB, lost));
  AssertEquals('last: the survivor''s comma goes',
    '{' + LF + '  a: 1,' + LF + '  b: 2' + LF + '}', PatchWith(T, @EdDelC, lost));
  AssertEquals('a run to the end', '{' + LF + '  a: 1' + LF + '}',
    PatchWith(T, @EdDelBC, lost));
  AssertEquals('everything', '{' + LF + '}', PatchWith(T, @EdDelABC, lost));
  AssertEquals('a trailing comma stays a trailing comma', '{ a: 1, }',
    PatchWith('{ a: 1, b: 2, }', @EdDelB, lost));
  AssertEquals(0, lost);
end;

procedure TAdvChartTextPatchTest.TestAnAddedMemberFollowsTheLayout;
const
  T = '{' + LF + '  a: 1,' + LF + '  b: 2,' + LF + '  c: 3' + LF + '}';
var lost: Integer;
begin
  AssertEquals('one per line, at the members'' indent',
    '{' + LF + '  a: 1,' + LF + '  b: 2,' + LF + '  c: 3,' + LF + '  d: 4' + LF + '}',
    PatchWith(T, @EdAddD, lost));
  AssertEquals('on one line', '{ a: 1, b: ''x'' }', PatchWith('{ a: 1 }', @EdAddBx, lost));
  AssertEquals('after a trailing comma', '{ a: 1, b: 1 }',
    PatchWith('{ a: 1, }', @EdAddB1, lost));
  AssertEquals('quoted where the document quotes', '{"a": "s", "b": 1}',
    PatchWith('{"a": "s"}', @EdAddB1, lost));
  AssertEquals('an empty object is written fresh', '{ a: 1 }',
    PatchWith('{}', @EdAddA1, lost));
  AssertEquals('everything replaced', '{ b: 2 }', PatchWith('{ a: 1 }', @EdSwapAB, lost));
  AssertEquals('a cut at the end and an append: the survivor keeps its comma',
    '{' + LF + '  a: 1,' + LF + '  b: 2,' + LF + '  d: 4' + LF + '}',
    PatchWith(T, @EdCutCAddD, lost));
  AssertEquals(0, lost);
end;

procedure TAdvChartTextPatchTest.TestALineCommentStaysWithItsMember;
const
  T = '{' + LF + '  a: 1, // about a' + LF + '  b: 2, // about b' + LF + '  c: 3' + LF + '}';
var lost: Integer;
begin
  AssertEquals('the middle goes with what was said about it',
    '{' + LF + '  a: 1, // about a' + LF + '  c: 3' + LF + '}',
    PatchWith(T, @EdDelB, lost));
  AssertEquals('the last goes; the comment before it stays put',
    '{' + LF + '  a: 1, // about a' + LF + '  b: 2 // about b' + LF + '}',
    PatchWith(T, @EdDelC, lost));
  AssertEquals('an append lands after the comment, not inside it',
    '{' + LF + '  a: 1, // about a' + LF + '  b: 2, // about b' + LF + '  c: 3,' + LF
      + '  d: 4' + LF + '}',
    PatchWith(T, @EdAddD, lost));
  AssertEquals(0, lost);
end;

procedure TAdvChartTextPatchTest.TestArraysKeepTheirHeadAndTail;
const
  T = '{ v: [1, 2, 3] }';
  M = '{' + LF + '  v: [' + LF + '    1,' + LF + '    2' + LF + '  ]' + LF + '}';
var lost: Integer;
begin
  AssertEquals('in place', '{ v: [1, 20, 3] }', PatchWith(T, @EdArr20, lost));
  AssertEquals('append', '{ v: [1, 2, 3, 4] }', PatchWith(T, @EdArrAppend, lost));
  AssertEquals('prepend', '{ v: [0, 1, 2, 3] }', PatchWith(T, @EdArrPrepend, lost));
  AssertEquals('cut the middle', '{ v: [1, 3] }', PatchWith(T, @EdArrDelMid, lost));
  AssertEquals('cut the last', '{ v: [1, 2] }', PatchWith(T, @EdArrDelLast, lost));
  AssertEquals('packed stays packed', '{ v: [1,2,3,4] }',
    PatchWith('{ v: [1,2,3] }', @EdArrAppend, lost));
  AssertEquals('one per line stays one per line',
    '{' + LF + '  v: [' + LF + '    1,' + LF + '    2,' + LF + '    3' + LF + '  ]' + LF + '}',
    PatchWith(M, @EdArrAppend3, lost));
  AssertEquals(0, lost);
end;

procedure TAdvChartTextPatchTest.TestAMovedElementKeepsItsText;
const
  T = '{ v: [' + LF + '  { a: 1 /* one */ },' + LF + '  { b: 2 } // two' + LF + '] }';
var lost: Integer;
begin
  { both elements verbatim -- the comment INSIDE the moved one moves with it;
    the one after the array's last element stays where it was }
  AssertEquals('{ v: [' + LF + '  { b: 2 },' + LF + '  { a: 1 /* one */ } // two' + LF + '] }',
    PatchWith(T, @EdArrSwap, lost));
  AssertEquals('nothing between the elements, so nothing lost', 0, lost);
  AssertEquals('{ v: [' + LF + '  2,' + LF + '  1' + LF + '] }',
    PatchWith('{ v: [' + LF + '  1, // first' + LF + '  2' + LF + '] }', @EdArrSwap, lost));
  AssertEquals('a comment between rewritten elements is counted', 1, lost);
end;

procedure TAdvChartTextPatchTest.TestCommentsInARewrittenValueAreCounted;
var lost: Integer;
begin
  AssertEquals('{ a: 5, /* kept */ b: 1 }',
    PatchWith('{ a: { x: 1 /* c */, y: 2 // d' + LF + ' }, /* kept */ b: 1 }', @EdA5, lost));
  AssertEquals('the two inside the replaced value', 2, lost);
end;

procedure TAdvChartTextPatchTest.TestTheStyleIsReadOffTheDocument;
const
  Q = '{' + #13#10 + '    "a": "s"' + #13#10 + '}';
var lost: Integer;
begin
  AssertEquals('CRLF, four spaces, quoted keys, double quotes',
    '{' + #13#10 + '    "a": "s",' + #13#10 + '    "b-c": 1' + #13#10 + '}',
    PatchWith(Q, @EdAddBC, lost));
  AssertEquals('a name that is no identifier is quoted the document''s way',
    '{ a: ''s'', ''b-c'': 1 }', PatchWith('{ a: ''s'' }', @EdAddBC, lost));
  AssertEquals('a fresh nested value in the same style',
    '{' + #13#10 + '    "a": "s",' + #13#10 + '    "o": { "x": [1, 2] }' + #13#10 + '}',
    PatchWith(Q, @EdAddObj, lost));
  AssertEquals('the colon as written', '{ a:1, b:1 }', PatchWith('{ a:1 }', @EdAddB1, lost));
end;

procedure TAdvChartTextPatchTest.TestATextThatCannotBeMappedIsWrittenWhole;
var
  wrong, work: TJSONData;
  p: TTyOptTextPatcher;
begin
  { the map is checked against the tree; a tree that is not the text's is
    the stand-in here for any spelling the scanner reads differently }
  wrong := Reparse('{ b: 1 }');
  work := Reparse('{ b: 2 }');
  p := TTyOptTextPatcher.Create('{ a: 1 // c' + LF + '}', wrong);
  try
    AssertFalse('not mapped', p.Mapped);
    AssertEquals('{' + LF + '  b: 2' + LF + '}', p.Patch(work));
    AssertEquals('every comment is counted lost', 1, p.Lost);
    AssertEquals('unchanged is still the text itself', '{ a: 1 // c' + LF + '}',
      p.Patch(wrong));
  finally
    p.Free;
    work.Free;
    wrong.Free;
  end;
end;

procedure TAdvChartTextPatchTest.TestSameMeansWhatTheOptionMeans;
var a, b: TJSONData;
begin
  a := Reparse('{ x: 1, y: [1, 2], z: { p: true } }');
  b := Reparse('{ z: { p: true }, y: [1.0, 2], x: 1 }');
  try
    AssertTrue('key order and 1.0 do not matter', TyOptJsonSame(a, b));
  finally
    b.Free;
  end;
  b := Reparse('{ x: 1, y: [2, 1], z: { p: true } }');
  try
    AssertFalse('element order does', TyOptJsonSame(a, b));
  finally
    b.Free;
  end;
  b := Reparse('{ x: "1", y: [1, 2], z: { p: true } }');
  try
    AssertFalse('a string is not a number', TyOptJsonSame(a, b));
  finally
    b.Free;
    a.Free;
  end;
end;

function GalleryDirOf: string;
var d: string; i: Integer;
begin
  Result := '';
  d := ExtractFilePath(ParamStr(0));
  for i := 0 to 5 do
  begin
    if DirectoryExists(d + 'examples' + PathDelim + 'advchart' + PathDelim + 'gallery') then
      Exit(d + 'examples' + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim);
    d := d + '..' + PathDelim;
  end;
end;

function LoadText(const AFile: string): string;
var fs: TFileStream;
begin
  fs := TFileStream.Create(AFile, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

var
  GRand: Cardinal;

function Rnd(N: Integer): Integer;
begin
  { an LCG of our own: the edits must be the same on every run and every
    machine, whatever else touched the RTL's generator first }
  GRand := GRand * 1103515245 + 12345;
  Result := Integer((GRand shr 8) mod Cardinal(Max(N, 1)));
end;

function RandomScalar: TJSONData;
begin
  case Rnd(4) of
    0: Result := TJSONIntegerNumber.Create(Rnd(1000));
    1: Result := TJSONFloatNumber.Create(Rnd(1000) / 8);
    2: Result := TJSONString.Create('s' + IntToStr(Rnd(99)));
  else
    Result := TJSONBoolean.Create(Rnd(2) = 0);
  end;
end;

procedure RandomEdit(ARoot: TJSONData);
var
  node, child: TJSONData;
  i, k, depth: Integer;
begin
  { walk down a random path of containers, then change the one reached }
  node := ARoot;
  depth := 0;
  while (node.Count > 0) and (Rnd(10) < 6) and (depth < 6) do
  begin
    child := node.Items[Rnd(node.Count)];
    if not (child.JSONType in [jtObject, jtArray]) then Break;
    node := child;
    Inc(depth);
  end;
  k := Rnd(4);
  if node is TJSONObject then
    case k of
      0: if node.Count > 0 then TJSONObject(node).Delete(Rnd(node.Count));
      1: TJSONObject(node).Add('zz' + IntToStr(Rnd(100000)), RandomScalar);
      2: if node.Count > 0 then node.Items[Rnd(node.Count)] := RandomScalar;
    else
      begin
        child := TJSONObject.Create;
        TJSONObject(child).Add('q', RandomScalar);
        TJSONObject(node).Add('zy' + IntToStr(Rnd(100000)), child);
      end;
    end
  else
    case k of
      0: if node.Count > 0 then TJSONArray(node).Delete(Rnd(node.Count));
      1: TJSONArray(node).Insert(Rnd(node.Count + 1), RandomScalar);
      2: if node.Count > 0 then node.Items[Rnd(node.Count)] := RandomScalar;
    else
      if node.Count > 1 then
      begin
        i := Rnd(node.Count);
        TJSONArray(node).Move(i, Rnd(node.Count));
      end;
    end;
end;

procedure TAdvChartTextPatchTest.TestRandomEditsOfTheGalleryReadBackAsEdited;
var
  dir, text, outText: string;
  rec: TSearchRec;
  orig, work: TJSONData;
  p: TTyOptTextPatcher;
  files, edits, e, kept: Integer;
begin
  dir := GalleryDirOf;
  AssertTrue('the gallery is where the test can reach it', dir <> '');
  GRand := 20261012;
  files := 0;
  edits := 0;
  if FindFirst(dir + '*.json', faAnyFile, rec) = 0 then
  try
    repeat
      if rec.Size > 120000 then Continue;
      text := LoadText(dir + rec.Name);
      orig := Reparse(text);
      p := TTyOptTextPatcher.Create(text, orig);
      try
        AssertTrue(rec.Name + ' is mapped', p.Mapped);
        for e := 1 to 4 do
        begin
          work := orig.Clone;
          try
            RandomEdit(work);
            if Rnd(2) = 0 then RandomEdit(work);
            outText := p.Patch(work);
            AssertTrue(rec.Name + ' edit ' + IntToStr(e) + ' reads back as edited',
              ReadsBackAs(outText, work));
            AssertEquals(rec.Name + ': the gallery has no comments to lose', 0, p.Lost);
            Inc(edits);
          finally
            work.Free;
          end;
        end;
        { and the unedited tree is the text, after all that }
        kept := Length(p.Patch(orig));
        AssertEquals(rec.Name, Length(text), kept);
      finally
        p.Free;
        orig.Free;
      end;
      Inc(files);
    until FindNext(rec) <> 0;
  finally
    FindClose(rec);
  end;
  AssertTrue('walked the gallery', files > 200);
  AssertTrue('made the edits', edits > 600);
end;

{ ==================== the model ==================== }

const
  cBar =
    '{' + LF +
    '  xAxis: { type: ''category'', data: [''Mon'', ''Tue'', ''Wed''] },' + LF +
    '  yAxis: { type: ''value'' },' + LF +
    '  series: [' + LF +
    '    { name: ''A'', type: ''bar'', data: [120, 200, 150] },' + LF +
    '    { name: ''B'', type: ''line'', smooth: true, data: [1, 2, 3], custom: { keep: [1, 2] } }' + LF +
    '  ]' + LF +
    '}';
  cSerA = '{ name: ''A'', type: ''bar'', data: [120, 200, 150] }';
  cSerB = '{ name: ''B'', type: ''line'', smooth: true, data: [1, 2, 3], custom: { keep: [1, 2] } }';

function NewModel(const AText: string): TTySeriesEditModel;
begin
  Result := TTySeriesEditModel.Create;
  if not Result.Load(AText) then
  begin
    Result.Free;
    raise Exception.Create('does not load: ' + AText);
  end;
end;

function ModelText(M: TTySeriesEditModel): string;
begin
  Result := M.Text;
  if not ReadsBackAs(Result, M.Tree) then
    raise Exception.Create('the model''s text does not read back as its tree:' + LF + Result);
end;

function Swap1(const S, AOld, ANew: string): string;
var p: Integer;
begin
  p := Pos(AOld, S);
  if p = 0 then raise Exception.Create('not found: ' + AOld);
  Result := Copy(S, 1, p - 1) + ANew + Copy(S, p + Length(AOld), MaxInt);
end;

procedure TAdvChartSeriesEditTest.TestLoadRefusesWhatIsNotAnOption;
var m: TTySeriesEditModel;
begin
  m := TTySeriesEditModel.Create;
  try
    AssertFalse('a parse error', m.Load('{ a: 1,' + LF + '  b: }'));
    AssertTrue('says why', m.Error <> '');
    AssertEquals('and where', 2, m.ErrorLine);
    AssertFalse('an array is no option', m.Load('[1, 2]'));
    AssertEquals(rsTySerEdNotObject, m.Error);
    AssertTrue('empty text is an empty option', m.Load(''));
    AssertEquals(0, m.SeriesCount);
    m.AddSeries('pie');
    AssertEquals('written whole', '{' + LF + '  series: [{ type: ''pie'', data: [] }]' + LF + '}',
      ModelText(m));
    AssertFalse('nothing to lose', m.NeedsConfirm);
  finally
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestTheSeriesListAddsDeletesAndMoves;
var m: TTySeriesEditModel;
begin
  m := NewModel(cBar);
  try
    AssertEquals(2, m.SeriesCount);
    AssertEquals(Format(rsTySerEdCaptionNamed, [0, 'bar', 'A']), m.SeriesCaption(0));
    AssertEquals('line', m.SeriesType(1));
    AssertEquals('untouched is byte for byte', cBar, ModelText(m));

    m.MoveSeries(1, 0);
    AssertEquals('a move rewrites the middle with both texts verbatim',
      Swap1(cBar, cSerA + ',' + LF + '    ' + cSerB, cSerB + ',' + LF + '    ' + cSerA),
      ModelText(m));
    m.MoveSeries(0, 1);
    AssertEquals('and moving back is the text again', cBar, ModelText(m));

    m.DeleteSeries(0);
    AssertEquals(Swap1(cBar, LF + '    ' + cSerA + ',', ''), ModelText(m));
    m.AddSeries('scatter');
    AssertEquals(2, m.SeriesCount);
    AssertEquals(Swap1(cBar, LF + '    ' + cSerA + ',' + LF + '    ' + cSerB,
      LF + '    ' + cSerB + ',' + LF + '    { type: ''scatter'', data: [] }'), ModelText(m));
    m.SetSeriesType(1, 'effectScatter');
    AssertEquals('effectScatter', m.SeriesType(1));
    AssertEquals(Format(rsTySerEdCaption, [1, 'effectScatter']), m.SeriesCaption(1));
  finally
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestAnEditedSeriesThatMovedKeepsItsText;
const
  T = '{ series: [' + LF + '  { type: ''bar'', /* mine */ data: [1] },' + LF
    + '  { type: ''line'', data: [2] }' + LF + '] }';
var
  m: TTySeriesEditModel;
  err: string;
begin
  { renamed AND moved: equal to nothing it was, so only the model's memory of
    which series it is can patch it from its own text -- comment and all }
  m := NewModel(T);
  try
    AssertTrue(m.SetFieldText(0, 'name', 'X', err));
    m.MoveSeries(0, 1);
    AssertEquals('{ series: [' + LF + '  { type: ''line'', data: [2] },' + LF
      + '  { type: ''bar'', /* mine */ data: [1], name: ''X'' }' + LF + '] }', ModelText(m));
    AssertEquals('nothing lost', 0, m.Lost);
  finally
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestABareSeriesBecomesAListWhenTheListChanges;
var m: TTySeriesEditModel;
  err: string;
begin
  m := NewModel('{ series: { type: ''pie'', data: [1] } }');
  try
    AssertEquals('a bare series is a list of one', 1, m.SeriesCount);
    AssertTrue(m.SetFieldText(0, 'name', 'P', err));
    AssertEquals('edited where it is', '{ series: { type: ''pie'', data: [1], name: ''P'' } }',
      ModelText(m));
    m.AddSeries('pie');
    AssertEquals(2, m.SeriesCount);
    AssertEquals('{ series: [{ type: ''pie'', data: [1], name: ''P'' }, { type: ''pie'', data: [] }] }',
      ModelText(m));
  finally
    m.Free;
  end;
end;

function HasField(const A: TTySeriesFieldArray; const APath: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(A) do
    if A[i].Path = APath then Exit(True);
  Result := False;
end;

procedure TAdvChartSeriesEditTest.TestTheFieldsFollowTheCatalog;
var
  m: TTySeriesEditModel;
  types: TStringList;
begin
  m := NewModel('{ series: [{ type: ''line'' }, { type: ''bar'' }, { type: ''pie'' }, { type: ''nope'' }] }');
  types := TStringList.Create;
  try
    AssertTrue('a line smooths', HasField(m.Fields(0), 'smooth'));
    AssertTrue('a line stacks', HasField(m.Fields(0), 'stack'));
    AssertTrue('a line is on axes', HasField(m.Fields(0), 'yAxisIndex'));
    AssertFalse('a bar does not smooth', HasField(m.Fields(1), 'smooth'));
    AssertTrue('a bar stacks', HasField(m.Fields(1), 'stack'));
    AssertFalse('a pie has no axes', HasField(m.Fields(2), 'xAxisIndex'));
    AssertTrue('a pie has a name', HasField(m.Fields(2), 'name'));
    AssertTrue('a pie has labels', HasField(m.Fields(2), 'label.show'));
    AssertTrue('a pie colours', HasField(m.Fields(2), 'itemStyle.color'));
    AssertTrue('a type the catalog does not know gets everything',
      HasField(m.Fields(3), 'smooth') and HasField(m.Fields(3), 'encode'));
    TySeriesTypes(types);
    AssertTrue('the catalog''s types', (types.IndexOf('line') >= 0)
      and (types.IndexOf('sankey') >= 0) and (types.Count >= 20));
  finally
    types.Free;
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestAFieldEditWritesOnlyThatKey;
var
  m: TTySeriesEditModel;
  err: string;
begin
  m := NewModel(cBar);
  try
    AssertTrue(m.SetFieldText(0, 'name', 'Sales', err));
    AssertEquals(Swap1(cBar, 'name: ''A''', 'name: ''Sales'''), ModelText(m));
    m.SetFieldState(0, 'label.show', fsTrue);
    AssertEquals(Ord(fsTrue), Ord(m.FieldState(0, 'label.show')));
    AssertEquals(Swap1(Swap1(cBar, 'name: ''A''', 'name: ''Sales'''),
      'data: [120, 200, 150] }', 'data: [120, 200, 150], label: { show: true } }'),
      ModelText(m));
    m.SetFieldState(0, 'label.show', fsAbsent);
    AssertTrue(m.SetFieldText(0, 'name', 'A', err));
    AssertEquals('the label we made goes with its last key', cBar, ModelText(m));
    m.SetFieldState(1, 'smooth', fsFalse);
    AssertTrue(m.SetFieldText(1, 'encode', '{ x: 0, y: 1 }', err));
    AssertEquals(Swap1(cBar, 'smooth: true, data: [1, 2, 3], custom: { keep: [1, 2] } }',
      'smooth: false, data: [1, 2, 3], custom: { keep: [1, 2] }, encode: { x: 0, y: 1 } }'),
      ModelText(m));
    AssertEquals('{ x: 0, y: 1 }', m.FieldText(1, 'encode'));
  finally
    m.Free;
  end;
  m := NewModel('{ series: [{ type: ''bar'', label: {} }] }');
  try
    m.SetFieldState(0, 'label.show', fsTrue);
    m.SetFieldState(0, 'label.show', fsAbsent);
    AssertEquals('the user''s own empty label stays', '{ series: [{ type: ''bar'', label: {} }] }',
      ModelText(m));
  finally
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestABadFieldValueChangesNothing;
var
  m: TTySeriesEditModel;
  err: string;
begin
  m := NewModel(cBar);
  try
    AssertFalse(m.SetFieldText(0, 'xAxisIndex', 'abc', err));
    AssertEquals(Format(rsTySerEdNotInteger, ['abc']), err);
    AssertFalse(m.SetFieldText(0, 'encode', '{ x: ', err));
    AssertTrue('the reader''s own message', err <> '');
    AssertFalse(m.SetFieldText(0, 'encode', '1, b: 2', err));
    AssertEquals(rsTySerEdOneValue, err);
    AssertFalse(m.SetFieldText(0, 'itemStyle.color', '[1,', err));
    AssertEquals('nothing changed', cBar, ModelText(m));
    AssertTrue('a colour is a string', m.SetFieldText(0, 'itemStyle.color', '#c00', err));
    AssertEquals('#c00', m.FieldText(0, 'itemStyle.color'));
  finally
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestTheShownTextWrittenBackChangesNothing;
const
  T = '{ series: [{ type: ''line'', name: 2015, smooth: 0.5, xAxisIndex: 0, '
    + 'itemStyle: { color: { type: ''linear'', colorStops: [] } } }] }';
var
  m: TTySeriesEditModel;
  f: TTySeriesFieldArray;
  i: Integer;
  err: string;
begin
  { the dialog writes a field back when it loses focus; what it showed must
    be what is there -- a numeric name is not turned into a string, a 0.5
    smooth is not turned into true }
  m := NewModel(T);
  try
    f := m.Fields(0);
    for i := 0 to High(f) do
      if f[i].Kind = sfkBoolean then
        m.SetFieldState(0, f[i].Path, m.FieldState(0, f[i].Path))
      else
        AssertTrue(f[i].Path, m.SetFieldText(0, f[i].Path, m.FieldText(0, f[i].Path), err));
    AssertEquals(T, ModelText(m));
  finally
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestTheCategoryGrid;
var
  m: TTySeriesEditModel;
  t: TTyEditTable;
begin
  m := NewModel(cBar);
  t := m.SeriesTable(0);
  try
    AssertTrue(t.Editable);
    AssertEquals('category + value', 2, t.ColCount);
    AssertEquals(Ord(eckCategory), Ord(t.ColKind(0)));
    AssertEquals(Format(rsTySerEdColCategory, ['xAxis[0]']), t.ColCaption(0));
    AssertEquals(rsTySerEdColValue, t.ColCaption(1));
    AssertEquals(3, t.RowCount);
    AssertEquals('Tue', t.Cells[0, 1]);
    AssertEquals('200', t.Cells[1, 1]);
    AssertEquals(Format(rsTySerEdNoteCategory, ['xAxis[0]']), t.Note);

    t.Cells[1, 1] := '250';
    m.ApplySeriesTable(t);
    AssertEquals('one token', Swap1(cBar, '200', '250'), ModelText(m));
    t.Cells[0, 2] := 'Thu';
    m.ApplySeriesTable(t);
    AssertEquals(Swap1(Swap1(cBar, '200', '250'), '''Wed''', '''Thu'''), ModelText(m));
    t.Cells[0, 2] := 'Wed';
    t.Cells[1, 1] := '200';
    t.AppendRow;
    t.Cells[0, 3] := 'Thu';
    t.Cells[1, 3] := '90';
    m.ApplySeriesTable(t);
    AssertEquals(Swap1(Swap1(cBar, '''Wed'']', '''Wed'', ''Thu'']'),
      '150] }', '150, 90] }'), ModelText(m));
    AssertFalse('a category grid takes no second column', t.CanAddColumn);
  finally
    t.Free;
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestARowIsACategory;
var
  m: TTySeriesEditModel;
  t: TTyEditTable;
  s: string;
begin
  m := NewModel(cBar);
  t := m.SeriesTable(0);
  try
    t.DeleteRow(0);
    m.ApplySeriesTable(t);
    s := ModelText(m);
    AssertEquals('the category, and its value in every series on the axis',
      Swap1(Swap1(Swap1(cBar, '[''Mon'', ''Tue''', '[''Tue'''), '[120, 200', '[200'),
        '[1, 2, 3]', '[2, 3]'), s);
  finally
    t.Free;
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestThePairGridAndItsColumns;
const
  T = '{ series: [{ type: ''scatter'', data: [[1, 2], [3, 4]] }] }';
var
  m: TTySeriesEditModel;
  g: TTyEditTable;
begin
  m := NewModel(T);
  g := m.SeriesTable(0);
  try
    AssertEquals(2, g.ColCount);
    AssertEquals(Format(rsTySerEdColDim, [1]), g.ColCaption(1));
    g.Cells[1, 0] := '5';
    m.ApplySeriesTable(g);
    AssertEquals('{ series: [{ type: ''scatter'', data: [[1, 5], [3, 4]] }] }', ModelText(m));
    AssertTrue(g.CanAddColumn);
    g.AppendColumn;
    m.ApplySeriesTable(g);
    AssertEquals('an empty column writes nothing',
      '{ series: [{ type: ''scatter'', data: [[1, 5], [3, 4]] }] }', ModelText(m));
    g.Cells[2, 1] := '9';
    m.ApplySeriesTable(g);
    AssertEquals('{ series: [{ type: ''scatter'', data: [[1, 5], [3, 4, 9]] }] }', ModelText(m));
    g.DeleteColumn(0);
    m.ApplySeriesTable(g);
    AssertEquals('{ series: [{ type: ''scatter'', data: [[5], [4, 9]] }] }', ModelText(m));
    g.DeleteColumn(0);
    AssertEquals(1, g.ColCount);
    AssertFalse('the last value column stays', g.CanDeleteColumn(0));
  finally
    g.Free;
    m.Free;
  end;
  { a deleted column with no cell touched still changes every row }
  m := NewModel(T);
  g := m.SeriesTable(0);
  try
    g.DeleteColumn(0);
    m.ApplySeriesTable(g);
    AssertEquals('{ series: [{ type: ''scatter'', data: [[2], [4]] }] }', ModelText(m));
  finally
    g.Free;
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestItemObjectsKeepWhatTheGridDoesNotShow;
const
  T = '{ series: [{ type: ''bar'', data: [{ value: 10, itemStyle: { color: ''red'' } }, 20, '
    + '{ value: 30, name: ''x'' }] }] }';
var
  m: TTySeriesEditModel;
  g: TTyEditTable;
begin
  m := NewModel(T);
  g := m.SeriesTable(0);
  try
    AssertEquals('name + value', 2, g.ColCount);
    AssertEquals(Ord(eckName), Ord(g.ColKind(0)));
    AssertEquals('x', g.Cells[0, 2]);
    g.Cells[1, 0] := '11';
    g.Cells[0, 1] := 'y';
    g.Cells[0, 2] := '';
    m.ApplySeriesTable(g);
    AssertEquals('{ series: [{ type: ''bar'', data: [{ value: 11, itemStyle: { color: ''red'' } }, '
      + '{ name: ''y'', value: 20 }, { value: 30 }] }] }', ModelText(m));
  finally
    g.Free;
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestACellKeepsItsKind;
var
  d: TJSONData;
begin
  d := TyEditCellValue('2018', True);
  AssertEquals('kept a string', Ord(jtString), Ord(d.JSONType));
  d.Free;
  d := TyEditCellValue(' 42 ', False);
  AssertEquals(Ord(jtNumber), Ord(d.JSONType));
  AssertEquals('42', TyEditCellText(d));
  d.Free;
  d := TyEditCellValue('1.5e3', False);
  AssertEquals('1500', TyEditCellText(d));
  d.Free;
  d := TyEditCellValue('007', False);
  AssertEquals('an id, not seven', Ord(jtString), Ord(d.JSONType));
  d.Free;
  d := TyEditCellValue('0', False);
  AssertEquals('a lone zero is a number', Ord(jtNumber), Ord(d.JSONType));
  AssertEquals('0', TyEditCellText(d));
  d.Free;
  d := TyEditCellValue('-0.25', False);
  AssertEquals('zero before the point is a number', Ord(jtNumber), Ord(d.JSONType));
  AssertEquals('-0.25', TyEditCellText(d));
  d.Free;
  d := TyEditCellValue('-', False);
  AssertEquals('ECharts'' empty mark stays what it is', '-', d.AsString);
  d.Free;
  d := TyEditCellValue('', False);
  AssertEquals(Ord(jtNull), Ord(d.JSONType));
  AssertEquals('', TyEditCellText(d));
  d.Free;
  d := TyEditCellValue('[1, ''a'']', False);
  AssertEquals(Ord(jtArray), Ord(d.JSONType));
  AssertEquals('[1, ''a'']', TyEditCellText(d));
  d.Free;
  d := TyEditCellValue('[1,', False);
  AssertEquals('not a literal, so a string', Ord(jtString), Ord(d.JSONType));
  d.Free;
  d := TyEditCellValue('true', False);
  AssertEquals(Ord(jtBoolean), Ord(d.JSONType));
  d.Free;
end;

procedure TAdvChartSeriesEditTest.TestOnlyOneValueCartesianDataTakesCategories;
const
  { A is one value per category; B is paired data on the same category axis
    (its categories are in its own x dimension); C is a bar on a polar
    system, in an option that also has a category x axis }
  T = '{ xAxis: { type: ''category'', data: [''Mon'', ''Tue'', ''Wed''] }, yAxis: {}, '
    + 'polar: {}, angleAxis: { type: ''category'', data: [''p'', ''q''] }, radiusAxis: {}, '
    + 'series: [{ type: ''bar'', data: [120, 200, 150] }, '
    + '{ type: ''line'', data: [[0, 5], [1, 6], [2, 7]] }, '
    + '{ type: ''bar'', coordinateSystem: ''polar'', data: [1, 2] }] }';
var
  m: TTySeriesEditModel;
  g: TTyEditTable;
begin
  m := NewModel(T);
  try
    g := m.SeriesTable(1);
    try
      AssertEquals('paired data: two value columns', 2, g.ColCount);
      AssertEquals('paired data takes no category column', Ord(eckValue), Ord(g.ColKind(0)));
      AssertEquals('0', g.Cells[0, 0]);
      AssertEquals('5', g.Cells[1, 0]);
    finally
      g.Free;
    end;
    g := m.SeriesTable(2);
    try
      AssertEquals('a polar series: one value column', 1, g.ColCount);
      AssertEquals('a polar series takes no x-axis categories', Ord(eckValue), Ord(g.ColKind(0)));
    finally
      g.Free;
    end;
    { deleting a category deletes it from the one-value series only: the
      paired series names its categories itself and is left alone }
    g := m.SeriesTable(0);
    try
      AssertEquals(Ord(eckCategory), Ord(g.ColKind(0)));
      g.DeleteRow(0);
      m.ApplySeriesTable(g);
      AssertEquals(Swap1(Swap1(T, '[''Mon'', ''Tue''', '[''Tue'''), '[120, 200', '[200'),
        ModelText(m));
    finally
      g.Free;
    end;
  finally
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestTheDatasetGrids;
const
  T = '{ dataset: { source: [[''product'', ''2015'', ''2016''], [''Matcha'', 43.3, 85.8], '
    + '[''Milk'', 83.1, 73.4]] }, xAxis: { type: ''category'' }, yAxis: {}, '
    + 'series: [{ type: ''bar'' }, { type: ''bar'' }] }';
  O = '{ dataset: { source: [{ product: ''A'', sales: 1 }, { product: ''B'', sales: 2 }] } }';
var
  m: TTySeriesEditModel;
  g: TTyEditTable;
begin
  m := NewModel(T);
  g := m.DatasetTable(0);
  try
    AssertEquals(1, m.DatasetCount);
    AssertTrue(g.Editable);
    AssertEquals(3, g.ColCount);
    AssertEquals(3, g.RowCount);
    AssertTrue('the first row of strings is the header', g.RowIsHeader(0));
    AssertFalse(g.RowIsHeader(1));
    g.Cells[1, 0] := '2018';
    g.Cells[1, 1] := '50';
    g.Cells[0, 2] := '7';
    g.AppendRow;
    g.Cells[0, 3] := 'Tea';
    g.Cells[1, 3] := '1';
    g.Cells[2, 3] := '2';
    m.ApplyDatasetTable(g);
    AssertEquals('{ dataset: { source: [[''product'', ''2018'', ''2016''], [''Matcha'', 50, 85.8], '
      + '[''7'', 83.1, 73.4], [''Tea'', 1, 2]] }, xAxis: { type: ''category'' }, yAxis: {}, '
      + 'series: [{ type: ''bar'' }, { type: ''bar'' }] }', ModelText(m));
  finally
    g.Free;
  end;
  { a series that reads the dataset: an empty grid that writes nothing }
  g := m.SeriesTable(0);
  try
    AssertTrue(g.Editable);
    AssertEquals(0, g.RowCount);
    AssertEquals(rsTySerEdNoteNoData, g.Note);
    m.ApplySeriesTable(g);
    AssertTrue('no data key made', m.SeriesNode(0).Find('data') = nil);
    m.AddSeries('line');
    AssertTrue('a new series reads the dataset too', m.SeriesNode(2).Find('data') = nil);
  finally
    g.Free;
    m.Free;
  end;
  m := NewModel(O);
  g := m.DatasetTable(0);
  try
    AssertEquals('product', g.ColCaption(0));
    AssertEquals('sales', g.ColCaption(1));
    AssertFalse('a key needs a name', g.CanAddColumn);
    g.Cells[1, 1] := '5';
    g.DeleteRow(0);
    m.ApplyDatasetTable(g);
    AssertEquals('{ dataset: { source: [{ product: ''B'', sales: 5 }] } }', ModelText(m));
  finally
    g.Free;
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestWhatTheGridCannotShowSaysWhy;
var
  m: TTySeriesEditModel;
  g: TTyEditTable;
begin
  m := NewModel('{ dataset: [{ source: { a: [1] } }, { transform: { type: ''sort'' } }], '
    + 'series: [{ type: ''tree'', data: [{ name: ''r'', children: [] }] }, '
    + '{ type: ''line'', data: 5 }, null] }');
  try
    g := m.SeriesTable(0);
    try
      AssertFalse(g.Editable);
      AssertEquals(rsTySerEdNoteTree, g.Note);
    finally
      g.Free;
    end;
    g := m.SeriesTable(1);
    try
      AssertEquals(rsTySerEdNoteNotList, g.Note);
    finally
      g.Free;
    end;
    g := m.SeriesTable(2);
    try
      AssertEquals(rsTySerEdNoteHole, g.Note);
      AssertEquals(Format(rsTySerEdCaption, [2, rsTySerEdHole]), m.SeriesCaption(2));
    finally
      g.Free;
    end;
    g := m.DatasetTable(0);
    try
      AssertEquals(rsTySerEdNoteDatasetForm, g.Note);
    finally
      g.Free;
    end;
    g := m.DatasetTable(1);
    try
      AssertFalse(g.Editable);
      AssertEquals(rsTySerEdNoteTransform, g.Note);
    finally
      g.Free;
    end;
  finally
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestApplyingTwiceIsApplyingOnce;
var
  m: TTySeriesEditModel;
  t: TTyEditTable;
  once: string;
begin
  m := NewModel(cBar);
  t := m.SeriesTable(0);
  try
    t.DeleteRow(1);
    t.AppendRow;
    t.Cells[0, 2] := 'Sun';
    t.Cells[1, 2] := '7';
    m.ApplySeriesTable(t);
    once := ModelText(m);
    m.ApplySeriesTable(t);
    AssertEquals('the dialog applies on every keystroke', once, ModelText(m));
    AssertTrue(Pos('[1, 3]', once) > 0);
  finally
    t.Free;
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestAWholeRewriteIsAskedFirst;
const
  { the reader (fcl-json, not strict) stops after the root value and takes
    the `;` pasted from JavaScript with it; the map does not, so the text
    cannot be patched -- an edit rewrites it whole, with no comment to lose }
  T = '{ series: [{ type: ''bar'', name: ''A'', data: [1, 2] }] };';
var
  m: TTySeriesEditModel;
  err: string;
begin
  m := NewModel(T);
  try
    AssertEquals('no edit: the text itself', T, m.Text);
    AssertFalse('no edit: nothing to ask', m.NeedsConfirm);
    AssertTrue(m.SetFieldText(0, 'name', 'B', err));
    AssertTrue('the edited tree reads back', ReadsBackAs(m.Text, m.Tree));
    AssertTrue('written whole', m.RewritesWhole);
    AssertEquals('no comment to lose', 0, m.Lost);
    AssertTrue('a whole rewrite is asked first', m.NeedsConfirm);
  finally
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestALostCommentIsReportedBeforeAnything;
const
  T = '{ series: [{ type: ''bar'', data: [1, /* two */ 2], '
    + 'itemStyle: { color: { type: ''linear'' /* gradient */ } } }] }';
var
  m: TTySeriesEditModel;
  g: TTyEditTable;
  err: string;
begin
  m := NewModel(T);
  g := m.SeriesTable(0);
  try
    g.AppendRow;
    g.Cells[0, 2] := '3';
    m.ApplySeriesTable(g);
    AssertTrue('an append keeps the comment', Pos('[1, /* two */ 2, 3]', ModelText(m)) > 0);
    AssertFalse(m.NeedsConfirm);
    AssertTrue(m.SetFieldText(0, 'itemStyle.color', 'red', err));
    ModelText(m);
    AssertEquals('the gradient''s comment goes with it', 1, m.Lost);
    AssertTrue('so the dialog asks', m.NeedsConfirm);
  finally
    g.Free;
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TestTheDiagnosticsSeeTheEditedText;
var
  m: TTySeriesEditModel;
  d: TTyOptDiagArray;
  i: Integer;
  build: Boolean;
  err: string;
begin
  m := NewModel(cBar);
  try
    d := m.Diagnose;
    for i := 0 to High(d) do
      AssertTrue('no build problem before', d[i].Kind <> odkBuild);
    AssertTrue(m.SetFieldText(0, 'yAxisIndex', '3', err));
    d := m.Diagnose;
    build := False;
    for i := 0 to High(d) do
      if d[i].Kind = odkBuild then build := True;
    AssertTrue('an axis that is not there is reported', build);
  finally
    m.Free;
  end;
end;

procedure TAdvChartSeriesEditTest.TheSeriesDialogStaysAShell;
const
  cReserved: array[0..6] of string = (
    'fpjson', 'TJSON', 'jsonparser', 'TyOptionParseRaw', 'TTyOptTextPatcher',
    'TyOptJsonLiteral', 'TyOptDiagnose');
var
  sl: TStringList;
  d, line, bad, src: string;
  i, k, depth: Integer;
begin
  { THE DIALOG ONLY PUTS THE MODEL IN BOXES. Every JSON decision is in
    SeriesEdit, where the tests above reach it; the dialog file is read --
    all tests/ can do about designtime/ -- and anything below the model is
    refused. Comments name these freely, and a comment decides nothing. }
  d := ExtractFilePath(ParamStr(0));
  for i := 0 to 5 do
  begin
    if FileExists(d + 'designtime' + PathDelim + 'tyControls.Design.AdvChart.SeriesDialog.pas') then
      Break;
    d := d + '..' + PathDelim;
  end;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(d + 'designtime' + PathDelim + 'tyControls.Design.AdvChart.SeriesDialog.pas');
    AssertTrue('read the dialog', sl.Count > 100);
    bad := '';
    depth := 0;
    for i := 0 to sl.Count - 1 do
    begin
      line := sl[i];
      if depth > 0 then
      begin
        for k := 1 to Length(line) do
          if line[k] = '}' then Dec(depth) else if line[k] = '{' then Inc(depth);
        Continue;
      end;
      for k := 1 to Length(line) do
        if line[k] = '{' then Inc(depth) else if line[k] = '}' then Dec(depth);
      if Copy(Trim(line), 1, 1) = '{' then Continue;
      if Copy(Trim(line), 1, 2) = '//' then Continue;
      for src in cReserved do
        if Pos(src, line) > 0 then
          bad := bad + LF + '  line ' + IntToStr(i + 1) + ': ' + Trim(line);
    end;
    AssertEquals('the series dialog reaches past its model -- add what it needs to '
      + 'tyControls.AdvChart.SeriesEdit, where a test can see it:' + bad, '', bad);
  finally
    sl.Free;
  end;
end;

{ ==================== the gallery ==================== }

function TAdvChartSeriesEditGalleryTest.GalleryDir: string;
begin
  Result := GalleryDirOf;
end;

procedure TAdvChartSeriesEditGalleryTest.TestEveryGalleryOptionComesBackByteForByte;
var
  dir, text: string;
  rec: TSearchRec;
  m: TTySeriesEditModel;
  t: TTyEditTable;
  f: TTySeriesFieldArray;
  i, k, files, grids, fields: Integer;
  err: string;
begin
  dir := GalleryDir;
  AssertTrue(dir <> '');
  files := 0;
  grids := 0;
  fields := 0;
  if FindFirst(dir + '*.json', faAnyFile, rec) = 0 then
  try
    repeat
      text := LoadText(dir + rec.Name);
      m := TTySeriesEditModel.Create;
      try
        AssertTrue(rec.Name + ' loads', m.Load(text));
        AssertEquals(rec.Name + ' as loaded', text, m.Text);
        for i := 0 to m.SeriesCount - 1 do
        begin
          t := m.SeriesTable(i);
          try
            if t.Editable then
            begin
              m.ApplySeriesTable(t);
              Inc(grids);
            end;
          finally
            t.Free;
          end;
          f := m.Fields(i);
          for k := 0 to High(f) do
          begin
            if f[k].Kind = sfkBoolean then
              m.SetFieldState(i, f[k].Path, m.FieldState(i, f[k].Path))
            else
              AssertTrue(rec.Name + ' ' + f[k].Path,
                m.SetFieldText(i, f[k].Path, m.FieldText(i, f[k].Path), err));
            Inc(fields);
          end;
        end;
        for i := 0 to m.DatasetCount - 1 do
        begin
          t := m.DatasetTable(i);
          try
            if t.Editable then m.ApplyDatasetTable(t);
          finally
            t.Free;
          end;
        end;
        AssertEquals(rec.Name + ' after every grid and field written back unchanged',
          text, m.Text);
        AssertFalse(rec.Name, m.Changed);
      finally
        m.Free;
      end;
      Inc(files);
    until FindNext(rec) <> 0;
  finally
    FindClose(rec);
  end;
  AssertTrue('walked the gallery', files > 200);
  AssertTrue('applied grids', grids > 300);
  AssertTrue('wrote fields', fields > 2000);
end;

procedure TAdvChartSeriesEditGalleryTest.TestGalleryEditsReadBackAsEdited;
var
  dir, text, s: string;
  rec: TSearchRec;
  m: TTySeriesEditModel;
  t: TTyEditTable;
  r, c, n, files, cells: Integer;
  err: string;
  num: Double;
begin
  dir := GalleryDir;
  files := 0;
  cells := 0;
  if FindFirst(dir + '*.json', faAnyFile, rec) = 0 then
  try
    repeat
      text := LoadText(dir + rec.Name);
      m := TTySeriesEditModel.Create;
      try
        AssertTrue(m.Load(text));
        n := m.SeriesCount;
        if (n > 0) and (m.SeriesNode(0) <> nil) then
        begin
          { a rename costs the name }
          AssertTrue(m.SetFieldText(0, 'name', 'Renamed', err));
          s := ModelText(m);
          AssertTrue(rec.Name + ': a rename touches only the name',
            ChangedLength(text, s) <= Length('name: ''Renamed'',') + 40);
          { one cell costs one token }
          t := m.SeriesTable(0);
          try
            if t.Editable and (t.RowCount > 0) then
              for c := 0 to t.ColCount - 1 do
                if (t.ColKind(c) = eckValue) and (t.Cells[c, 0] <> '')
                  and TryStrToFloat(t.Cells[c, 0], num) then
                begin
                  t.Cells[c, 0] := '424242';
                  m.ApplySeriesTable(t);
                  AssertTrue(rec.Name + ': one cell, one token',
                    ChangedLength(ModelText(m), s) <= 30);
                  Inc(cells);
                  Break;
                end;
          finally
            t.Free;
          end;
          m.AddSeries('line');
          ModelText(m);
          if n > 1 then
          begin
            m.MoveSeries(0, n - 1);
            ModelText(m);
          end;
          m.DeleteSeries(0);
          ModelText(m);
          for r := m.SeriesCount - 1 downto 0 do m.DeleteSeries(r);
          ModelText(m);
          AssertFalse(rec.Name + ': the gallery has no comments to lose', m.NeedsConfirm);
        end;
      finally
        m.Free;
      end;
      Inc(files);
    until FindNext(rec) <> 0;
  finally
    FindClose(rec);
  end;
  AssertTrue(files > 200);
  AssertTrue('edited cells', cells > 100);
end;

initialization
  RegisterTest(TAdvChartTextPatchTest);
  RegisterTest(TAdvChartSeriesEditTest);
  RegisterTest(TAdvChartSeriesEditGalleryTest);
end.
