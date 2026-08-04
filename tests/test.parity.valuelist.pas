unit test.parity.valuelist;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.ValueListEditor;
type
  { LCL / Delphi API-parity guards for TTyValueListEditor's two value indexers.

    C:\lazarus\lcl\valedit.pas:201-202 declares
      property Keys[Index: Integer]: string      read GetKey   write SetKey;
      property Values[const Key: string]: string  read GetValue write SetValue;

    so on every other TValueListEditor `VLE.Values['Name'] := 'Bob'` is THE way to read and
    write a row, and Values[] takes a KEY. Ours used to take a ROW NUMBER, with the keyed form
    hidden under ValueOf[] -- which meant Values[0] named two different rows on the two
    libraries and ported code that compiled at all did the wrong thing in silence.

    These guards pin the SHAPE (Values by key, ValueFromIndex by root-row number) and the three
    behaviours ported code leans on: the key lookup folds case, writing an unknown key appends
    the row, and reading an unknown key yields ''. Each is a place where a plausible
    implementation compiles and answers wrongly, so none of them is self-evident from the
    declaration alone. }
  TValueListParityTest = class(TTestCase)
  private
    FFired: Integer;
    FLastRow: TTyValueRow;
    procedure OnValChanged(Sender: TObject; ARow: TTyValueRow);
    function MakeWH: TTyValueListEditor;   // Width=100, Height=50
  published
    procedure TestValuesAreIndexedByKey;
    procedure TestValuesAndValueFromIndexAreDifferentLookups;
    procedure TestValuesWriteByKeyHitsThatRowAndFiresEvent;
    procedure TestValuesKeyLookupFoldsCase;
    procedure TestValuesWriteOfUnknownKeyAppendsRow;
    procedure TestValuesReadOfUnknownKeyIsEmpty;
    procedure TestValueFromIndexIsRowIndexed;
  end;

  { The second collision on this class, and the same shape as the first: a public member whose
    NAME is LCL's and whose MEANING is not.

    LCL's TValueListEditor = class(TCustomStringGrid) (valedit.pas:120) inherits
    VisibleRowCount from TCustomGrid (grids.pas:1301, body :2274, republished public on
    TCustomDrawGrid at :1538), where it is a VIEWPORT metric: how many rows fit on screen right
    now. Ours (tyControls.ValueListEditor.pas, public block from :170) returned
    Length(FFlatRow) -- a DATA metric: how many rows exist once expanded nodes are counted.

    Both are `function ...: Integer` with no arguments, both public, so ported paging maths
    (`TopIndex := TopIndex + VLE.VisibleRowCount`) compiled and paged the whole list at once.
    That is the collision fixed on TTyCustomGrid in 03c29b3; it did not land here because this
    class is a TTyListBox, not a grid. The data meaning is now DisplayRowCount -- the grid's
    name for the same idea. }
  TValueListViewportMetricTest = class(TTestCase)
  private
    function MakeRows(ACount: Integer): TTyValueListEditor;
  published
    procedure TestVisibleRowCountIsBoundedByTheViewportNotTheDisplayCount;
    procedure TestVisibleRowCountShrinksWithTheViewport;
    procedure TestVisibleRowCountCountsEveryRowWhenTheyAllFit;
    procedure TestDisplayRowCountCountsExpandedDescendants;
  end;

  { The two members whose SHAPE differed from LCL's.

    valedit.pas:188  function InsertRow(const KeyName, Value: string; Append: Boolean): Integer
    valedit.pas:237  property RowCount: Integer read GetRowCount write SetRowCount

    Ours were a two-argument PROCEDURE that always appended, and a read-only FUNCTION. So a
    ported call failed to compile on arity, `VLE.RowCount := 0` did not compile at all, and --
    the part no signature shows -- there was no insert-at-a-position anywhere on the class:
    AddRow appends, DeleteRow removes, and building a list in a chosen order meant rebuilding
    it wholesale. }
  TValueListRowApiTest = class(TTestCase)
  published
    procedure TestInsertRowReturnsTheIndexAndCanInsertNotAppend;
    procedure TestInsertRowAtPlacesTheRowExactly;
    procedure TestRowCountIsReadWrite;
  end;

implementation

procedure TValueListParityTest.OnValChanged(Sender: TObject; ARow: TTyValueRow);
begin
  Inc(FFired);
  FLastRow := ARow;
end;

function TValueListParityTest.MakeWH: TTyValueListEditor;
begin
  FFired := 0; FLastRow := nil;
  Result := TTyValueListEditor.Create(nil);
  Result.InsertRow('Width', '100');
  Result.InsertRow('Height', '50');
end;

procedure TValueListParityTest.TestValuesAreIndexedByKey;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('Values[key] reads that key''s row', '100', e.Values['Width']);
    AssertEquals('...and so does the second key', '50', e.Values['Height']);
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValuesAndValueFromIndexAreDifferentLookups;
var e: TTyValueListEditor;
begin
  { The two indexers must not be able to collapse into each other. A row whose KEY is the
    digit '0' -- and whose value differs from root row 0's -- is the case that tells them
    apart: with a key-indexed Values[] the two reads below disagree, and any implementation
    that resolves the key as a row number (the exact confusion this rename removes) makes
    them agree. The plain lookups in the test above would survive such a regression whenever
    the keys happen not to look like numbers; this one cannot. }
  e := MakeWH;
  try
    e.InsertRow('0', 'key-is-zero');
    AssertEquals('Values[''0''] = the row KEYED ''0''', 'key-is-zero', e.Values['0']);
    AssertEquals('ValueFromIndex[0] = root row 0', '100', e.ValueFromIndex[0]);
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValuesWriteByKeyHitsThatRowAndFiresEvent;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    e.OnValueChanged := @OnValChanged;
    e.Values['Height'] := '75';
    AssertEquals('read back by key', '75', e.Values['Height']);
    AssertEquals('the KEYED row changed', '75', e.ValueFromIndex[1]);
    AssertEquals('the other row did not', '100', e.ValueFromIndex[0]);
    AssertEquals('no row appended', 2, e.RowCount);
    AssertEquals('event fired once', 1, FFired);
    AssertTrue('event carried the keyed row', FLastRow = e.Row(1));
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValuesKeyLookupFoldsCase;
var e: TTyValueListEditor;
begin
  { LCL resolves the key through Strings.IndexOfName (valedit.pas:1094/1105), which compares
    with TStringList.DoCompareText on a list whose CaseSensitive is never set -- i.e. False.
    A case-SENSITIVE lookup here would compile and then read '' for a ported Values['height'],
    and worse, a ported write would APPEND a second 'height' row beside the 'Height' one. }
  e := MakeWH;
  try
    AssertEquals('lower-case key finds it', '50', e.Values['height']);
    AssertEquals('upper-case key finds it', '50', e.Values['HEIGHT']);
    e.Values['hEiGhT'] := '75';
    AssertEquals('the existing row was written', '75', e.ValueFromIndex[1]);
    AssertEquals('no duplicate row appended', 2, e.RowCount);
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValuesWriteOfUnknownKeyAppendsRow;
var e: TTyValueListEditor;
begin
  { LCL's setter falls through to Strings.Add when the key is absent (valedit.pas:1110-1114),
    so ported code populates the editor by assigning to keys that do not exist yet. Dropping
    the write instead would be silent data loss. }
  e := MakeWH;
  try
    e.OnValueChanged := @OnValChanged;
    e.Values['Depth'] := '7';
    AssertEquals('row appended', 3, e.RowCount);
    AssertEquals('appended with that key', 'Depth', e.Keys[2]);
    AssertEquals('appended with that value', '7', e.Values['Depth']);
    AssertEquals('and it has a display position', 3, e.DisplayRowCount);
    { Appending is a row ADD, not a value CHANGE -- AddRow / InsertRow are silent too, and a
      handler that repaints "the row that changed" has no prior row to be told about. }
    AssertEquals('append fires no OnValueChanged', 0, FFired);
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValuesReadOfUnknownKeyIsEmpty;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('unknown key reads empty', '', e.Values['Depth']);
    AssertEquals('reading did not create it', 2, e.RowCount);
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValueFromIndexIsRowIndexed;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('root row 0', '100', e.ValueFromIndex[0]);
    AssertEquals('root row 1', '50', e.ValueFromIndex[1]);
    e.ValueFromIndex[0] := '200';
    AssertEquals('written by row number', '200', e.ValueFromIndex[0]);
    AssertEquals('same row seen through its key', '200', e.Values['Width']);
    AssertEquals('out of range reads empty', '', e.ValueFromIndex[99]);
    { The row form addresses EXISTING rows only: unlike the key setter it must never append,
      or a stray index would quietly grow the list with an empty-keyed row. }
    e.ValueFromIndex[99] := 'x';
    AssertEquals('out-of-range write appended nothing', 2, e.RowCount);
  finally e.Free; end;
end;

{ ---- TValueListViewportMetricTest ---- }

function TValueListViewportMetricTest.MakeRows(ACount: Integer): TTyValueListEditor;
var i: Integer;
begin
  Result := TTyValueListEditor.Create(nil);
  { Pin BOTH the row height and the scale it is measured at: ItemHeight is logical px and the
    control works in device px, so without a fixed PPI the arithmetic below is whatever the
    test machine's font happens to report (72 here, which made 20 logical px into 15 device). }
  Result.Font.PixelsPerInch := 96;
  Result.ItemHeight := 20;          // the default follows the theme's --item-height
  Result.SetBounds(0, 0, 200, 200); // 200px tall => ~10 rows of viewport, never 200
  for i := 1 to ACount do
    Result.InsertRow('k' + IntToStr(i), IntToStr(i));
end;

procedure TValueListViewportMetricTest.TestVisibleRowCountIsBoundedByTheViewportNotTheDisplayCount;
var e: TTyValueListEditor; n: Integer;
begin
  { The regression in one line: 200 rows in a 200px-tall control and VisibleRowCount answered
    200. A viewport metric cannot exceed what the viewport can hold. }
  e := MakeRows(200);
  try
    n := e.VisibleRowCount;
    AssertEquals('all 200 rows have a display position', 200, e.DisplayRowCount);
    AssertTrue('VisibleRowCount must not be the display count (it is a viewport metric)',
      n <> e.DisplayRowCount);
    AssertTrue(Format('a viewport metric cannot exceed the rows the viewport holds ' +
      '(got %d, Height=%d, ItemHeight=%d)', [n, e.Height, e.ItemHeight]),
      n <= e.Height div e.ItemHeight);
    AssertTrue('a 200px viewport over 20px rows shows several of them', n > 1);
  finally e.Free; end;
end;

procedure TValueListViewportMetricTest.TestVisibleRowCountShrinksWithTheViewport;
var e: TTyValueListEditor; tall, short: Integer;
begin
  { The property that tells the two metrics apart with no arithmetic: resizing the control
    changes a viewport metric and cannot change a data metric. }
  e := MakeRows(200);
  try
    e.SetBounds(0, 0, 200, 400);
    tall := e.VisibleRowCount;
    e.SetBounds(0, 0, 200, 100);
    short := e.VisibleRowCount;
    AssertTrue('a shorter viewport shows fewer rows', short < tall);
    AssertEquals('while the display count is untouched by resizing', 200, e.DisplayRowCount);
  finally e.Free; end;
end;

procedure TValueListViewportMetricTest.TestVisibleRowCountCountsEveryRowWhenTheyAllFit;
var e: TTyValueListEditor;
begin
  { LCL drops the paging-overlap row when the whole grid fits (`if GridHeight<=ClientHeight
    then inc(Result)`), so a list that fits reports ALL of its rows -- not one less. }
  e := MakeRows(5);
  try
    e.SetBounds(0, 0, 200, 400);
    AssertEquals('a list that fits reports all of its rows', 5, e.VisibleRowCount);
    e.Clear;
    AssertEquals('an empty list shows nothing', 0, e.VisibleRowCount);
  finally e.Free; end;
end;

procedure TValueListViewportMetricTest.TestDisplayRowCountCountsExpandedDescendants;
var e: TTyValueListEditor; f: TTyValueRow;
begin
  { The other half of the split: DisplayRowCount is the DATA metric, so it moves with
    expand/collapse and not with the control's height. }
  e := TTyValueListEditor.Create(nil);
  try
    e.Font.PixelsPerInch := 96;
    e.ItemHeight := 20;
    e.SetBounds(0, 0, 200, 400);
    f := e.AddRow('Font', 'Segoe UI, 9');
    f.AddChild('Name', 'Segoe UI');
    f.AddChild('Size', '9');
    e.AddRow('Width', '100');
    e.SetExpanded(f, False);
    AssertEquals('collapsed: the two root rows', 2, e.DisplayRowCount);
    e.SetExpanded(f, True);
    AssertEquals('expanded: the children join them', 4, e.DisplayRowCount);
    e.SetBounds(0, 0, 200, 40);
    AssertEquals('and shrinking the control does not collapse anything', 4, e.DisplayRowCount);
  finally e.Free; end;
end;

{ ------------------------------------------------------------ InsertRow / RowCount ---- }

procedure TValueListRowApiTest.TestInsertRowReturnsTheIndexAndCanInsertNotAppend;
var
  e: TTyValueListEditor;
begin
  e := TTyValueListEditor.Create(nil);
  try
    AssertEquals('appending returns the new row''s index', 0, e.InsertRow('A', '1'));
    AssertEquals('and the next one', 1, e.InsertRow('B', '2'));
    AssertEquals('C', 2, e.InsertRow('C', '3'));

    { Append=False inserts at the CURRENT row, which is what LCL's not-Append means. }
    e.ItemIndex := 1;                       // 'B' selected
    AssertEquals('inserting reports where it went', 1, e.InsertRow('B2', '9', False));
    AssertEquals('and it went there', 'B2', e.Keys[1]);
    AssertEquals('pushing the old occupant down', 'B', e.Keys[2]);
    AssertEquals('nothing above it moved', 'A', e.Keys[0]);
    AssertEquals('and the tail is intact', 'C', e.Keys[3]);
    AssertEquals('four rows now', 4, e.RowCount);

    { The default is Append, so every call already written keeps working. }
    e.InsertRow('D', '4');
    AssertEquals('the two-argument form still appends', 'D', e.Keys[4]);
  finally e.Free; end;
end;

procedure TValueListRowApiTest.TestInsertRowAtPlacesTheRowExactly;
var
  e: TTyValueListEditor;
  r: TTyValueRow;
begin
  e := TTyValueListEditor.Create(nil);
  try
    e.InsertRow('A', '1');
    e.InsertRow('C', '3');
    r := e.InsertRowAt(1, 'B', '2');
    AssertNotNull('the row comes back for further configuration', r);
    AssertEquals('placed at the index asked for', 'B', e.Keys[1]);
    AssertEquals('A still first', 'A', e.Keys[0]);
    AssertEquals('C pushed down', 'C', e.Keys[2]);

    e.InsertRowAt(0, 'Z', '0');
    AssertEquals('index 0 inserts at the front', 'Z', e.Keys[0]);
    e.InsertRowAt(999, 'Tail', 'x');
    AssertEquals('an index past the end appends', 'Tail', e.Keys[4]);
    AssertEquals('and nothing was lost on the way', 5, e.RowCount);
  finally e.Free; end;
end;

procedure TValueListRowApiTest.TestRowCountIsReadWrite;
var
  e: TTyValueListEditor;
begin
  e := TTyValueListEditor.Create(nil);
  try
    e.InsertRow('A', '1');
    e.InsertRow('B', '2');
    e.InsertRow('C', '3');
    AssertEquals('reads as a property', 3, e.RowCount);

    e.RowCount := 2;
    AssertEquals('trimming drops rows from the END', 2, e.RowCount);
    AssertEquals('so the first ones survive', 'A', e.Keys[0]);
    AssertEquals('and the second', 'B', e.Keys[1]);

    e.RowCount := 4;
    AssertEquals('growing adds blank rows', 4, e.RowCount);
    AssertEquals('named ones untouched', 'B', e.Keys[1]);
    AssertEquals('the grown ones are blank', '', e.Keys[3]);

    e.RowCount := 0;
    AssertEquals('the one-line clear idiom', 0, e.RowCount);
    AssertEquals('and nothing is left displayed', 0, e.DisplayRowCount);
  finally e.Free; end;
end;

initialization
  RegisterTest(TValueListParityTest);
  RegisterTest(TValueListViewportMetricTest);
  RegisterTest(TValueListRowApiTest);
end.
