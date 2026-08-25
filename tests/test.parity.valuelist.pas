unit test.parity.valuelist;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, TypInfo, LCLType, Controls, Forms, fpcunit, testregistry,
  tyControls.ListBox, tyControls.ValueListEditor;
type
  { Drives the protected key handler and the protected editor-close, so the guards below exercise
    the SAME paths a user's keystroke does rather than calling the data API underneath them. }
  TValueListKeyDriver = class(TTyValueListEditor)
  public
    procedure Press(AKey: Word; AShift: TShiftState);
    procedure Commit;    // Enter / focus-out: apply the editor's text
    procedure Cancel;    // Escape: throw it away
    function DropHeightFor(ARows: Integer): Integer;   // the enum/colour popup's height
  end;

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
    procedure TestKeysAreWritableAndRowIndexed;
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
    procedure TestDropdownHeightHoldsAllItsRows;
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

  { KeyOptions -- what the USER may do to the row set at run time.

    C:\lazarus\lcl\valedit.pas:310 declares
      property KeyOptions: TKeyOptions read FKeyOptions write SetKeyOptions default [];
    over the set TKeyOption = (keyEdit, keyAdd, keyDelete, keyUnique) at :109.

    Ours had no equivalent at all: rows could only be added (AddRow / InsertRow) or removed
    (DeleteRow) from CODE, the key column was not editable by any gesture, and nothing anywhere
    checked for duplicate keys. So the one thing this control is named for -- a user-editable
    name/value list, the ini or environment-variable editor -- could not be built: the user
    could change values and nothing else.

    Each guard below sits on a decision where a plausible implementation compiles and behaves
    differently, so none is implied by the declaration:
      - the ordinals, because a set property streams as BIT POSITIONS and reordering the enum
        silently renames every flag in every .lfm already saved;
      - keyAdd pulling keyEdit in with it, which is a SETTER that rewrites its argument;
      - the key editor writing Key and not Value, the one-character routing mistake that would
        have made the rename corrupt the row it was opened on;
      - Ctrl+Delete rather than bare Delete;
      - and keyUnique's collision rule, which is the only flag with a REFUSAL behind it. }
  TValueListKeyOptionsTest = class(TTestCase)
  private
    FRenames, FRejects: Integer;
    FLastRejectKey: string;
    FLastRenamed: TTyValueRow;
    procedure OnKeyRenamed(Sender: TObject; ARow: TTyValueRow);
    procedure OnKeyRefused(Sender: TObject; ARow: TTyValueRow; const AKey: string);
    { Three root rows A/B/C (values 1/2/3), KeyOptions as given, selection on row ASel. }
    function Make(AOpts: TTyKeyOptions; ASel: Integer = -1): TValueListKeyDriver;
  published
    { the shape }
    procedure TestKeyOptionOrdinalsAreFrozen;
    procedure TestKeyOptionsIsPublishedAndDefaultsToEmpty;
    procedure TestKeyOptionsRoundTripsThroughTheStream;
    procedure TestKeyAddSilentlyImpliesKeyEdit;
    { keyEdit }
    procedure TestKeyEditOffMeansNoKeyEditorAtAll;
    procedure TestKeyEditOpensTheEditorOverTheKeyColumn;
    procedure TestKeyEditRenamesTheRowAndFiresOnKeyChanged;
    procedure TestKeyEditCommitsToTheKeyNotTheValue;
    procedure TestKeyEditCancelKeepsTheOldName;
    procedure TestClearingKeyEditClosesAnOpenRename;
    { keyAdd }
    procedure TestKeyAddInsertsABlankRowAtTheCurrentPosition;
    procedure TestKeyAddOffLeavesInsertAlone;
    { keyDelete }
    procedure TestKeyDeleteRemovesTheCurrentRowOnCtrlDelete;
    procedure TestKeyDeleteIgnoresBareDelete;
    procedure TestKeyDeleteOffLeavesCtrlDeleteAlone;
    { keyUnique }
    procedure TestKeyUniqueRefusesADuplicateRename;
    procedure TestKeyUniqueFoldsCase;
    procedure TestWithoutKeyUniqueTheDuplicateIsAccepted;
    procedure TestKeyUniqueScopesToSiblingsNotTheWholeTree;
    procedure TestKeyUniqueLetsBlankKeysCoexist;
    procedure TestKeyUniqueDoesNotRefuseARowItsOwnName;
    { ReadOnly outranks all four }
    procedure TestReadOnlyOutranksEveryKeyOption;
    { ...but neither ReadOnly nor keyUnique gates the Keys[] SETTER }
    procedure TestKeysWriteIsTheProgrammaticRenamePath;
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

{ Keys[] is read/WRITE, as LCL declares it (valedit.pas:201 `read GetKey write SetKey`).
  It used to be read-only here, so the programmatic half of a rename had to poke
  Row(i).Key directly -- which repainted nothing and told nobody. Row-indexed like
  GetKey / ValueFromIndex, and with ValueFromIndex's out-of-range contract: a stray
  index is a no-op, never an append. }
procedure TValueListParityTest.TestKeysAreWritableAndRowIndexed;
var e: TTyValueListEditor;
begin
  e := MakeWH;   // Width=100, Height=50
  try
    e.Keys[0] := 'Left';
    AssertEquals('the key changed', 'Left', e.Keys[0]);
    AssertEquals('the VALUE did not move with it', '100', e.ValueFromIndex[0]);
    AssertEquals('the keyed lookup finds the row under its new name', '100', e.Values['Left']);
    AssertEquals('and no longer under the old one', '', e.Values['Width']);
    AssertEquals('the other row is untouched', 'Height', e.Keys[1]);

    e.Keys[99] := 'stray';
    AssertEquals('an out-of-range write appends nothing', 2, e.RowCount);
    e.Keys[-1] := 'stray';
    AssertEquals('...negative neither', 2, e.RowCount);
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

procedure TValueListViewportMetricTest.TestDropdownHeightHoldsAllItsRows;
var
  d: TValueListKeyDriver;
  l: TTyListBox;
  h, i: Integer;
begin
  { The enum/colour dropdown's contract with its content: the popup form is borderless and
    the TTyListBox fills it, so the height BeginDropdown computes IS the list's height --
    and a dropdown showing all N of its options must show them whole with nothing to
    scroll. The list lays rows into its padding-inset content area, so a height of bare
    rows (+ a flat frame allowance) leaves it one row short and every such dropdown grows
    a needless scrollbar. Same contract TTyComboBox pins for its popup. }
  d := TValueListKeyDriver.Create(nil);
  l := TTyListBox.Create(nil);
  try
    d.Font.PixelsPerInch := 96;
    h := d.DropHeightFor(5);
    l.Font.PixelsPerInch := 96;
    for i := 1 to 5 do l.Items.Add('option ' + IntToStr(i));
    l.SetBounds(0, 0, 120, h);
    AssertEquals('the dropdown height shows every one of the 5 rows', 5, l.VisibleRows);
    l.TopIndex := 999;
    AssertEquals('and leaves nothing to scroll to', 0, l.TopIndex);
  finally
    l.Free;
    d.Free;
  end;
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

{ ------------------------------------------------------------------ KeyOptions ------- }

procedure TValueListKeyDriver.Press(AKey: Word; AShift: TShiftState);
var k: Word;
begin
  k := AKey;
  KeyDown(k, AShift);
end;

procedure TValueListKeyDriver.Commit;
begin
  EndEdit(True);
end;

procedure TValueListKeyDriver.Cancel;
begin
  EndEdit(False);
end;

function TValueListKeyDriver.DropHeightFor(ARows: Integer): Integer;
begin
  Result := DropdownHeightFor(ARows);
end;

procedure TValueListKeyOptionsTest.OnKeyRenamed(Sender: TObject; ARow: TTyValueRow);
begin
  Inc(FRenames);
  FLastRenamed := ARow;
end;

procedure TValueListKeyOptionsTest.OnKeyRefused(Sender: TObject; ARow: TTyValueRow;
  const AKey: string);
begin
  Inc(FRejects);
  FLastRejectKey := AKey;
end;

function TValueListKeyOptionsTest.Make(AOpts: TTyKeyOptions; ASel: Integer): TValueListKeyDriver;
begin
  FRenames := 0; FRejects := 0; FLastRejectKey := ''; FLastRenamed := nil;
  Result := TValueListKeyDriver.Create(nil);
  Result.InsertRow('A', '1');
  Result.InsertRow('B', '2');
  Result.InsertRow('C', '3');
  Result.KeyOptions := AOpts;
  Result.OnKeyChanged := @OnKeyRenamed;
  Result.OnKeyRejected := @OnKeyRefused;
  Result.ItemIndex := ASel;
end;

{ A set property streams as a BYTE OF BIT POSITIONS, not as names -- so inserting a flag anywhere
  but the end shifts every ordinal above it and every .lfm already written silently means
  something else (an old `KeyOptions=[keyAdd]` would load as keyDelete). Pinning the four numbers
  is the only thing that makes "append only" enforceable rather than a comment nobody reads. }
procedure TValueListKeyOptionsTest.TestKeyOptionOrdinalsAreFrozen;
begin
  AssertEquals('keyEdit is bit 0',   0, Ord(keyEdit));
  AssertEquals('keyAdd is bit 1',    1, Ord(keyAdd));
  AssertEquals('keyDelete is bit 2', 2, Ord(keyDelete));
  AssertEquals('keyUnique is bit 3', 3, Ord(keyUnique));
  AssertEquals('and there is no fifth flag hiding above them', 3, Ord(High(TTyKeyOption)));
  AssertEquals('...nor below', 0, Ord(Low(TTyKeyOption)));
end;

procedure TValueListKeyOptionsTest.TestKeyOptionsIsPublishedAndDefaultsToEmpty;
var e: TTyValueListEditor;
begin
  e := TTyValueListEditor.Create(nil);
  try
    AssertTrue('KeyOptions must reach the Object Inspector and the streamer',
      IsPublishedProp(e, 'KeyOptions'));
    AssertTrue('and it must be READABLE, or the IDE reports "Cannot read property"',
      GetPropInfo(e, 'KeyOptions')^.GetProc <> nil);
    AssertTrue('and have a real setter, or TWriter.WriteProperty skips it entirely',
      GetPropInfo(e, 'KeyOptions')^.SetProc <> nil);
    AssertTrue('default is [] -- the behaviour that shipped before this existed',
      e.KeyOptions = []);
  finally e.Free; end;
end;

type
  THostFormVLE = class(TForm)
  published
    VLE: TTyValueListEditor;
  end;

{ The ordinals only matter because the set really does travel through the streamer as bits; this
  proves the whole path rather than the enum alone. }
procedure TValueListKeyOptionsTest.TestKeyOptionsRoundTripsThroughTheStream;
const
  Want: TTyKeyOptions = [keyEdit, keyDelete, keyUnique];   // deliberately NOT contiguous
var
  Src, Dst: THostFormVLE;
  MS: TMemoryStream;
  D: TTyValueListEditor;
begin
  Src := THostFormVLE.CreateNew(nil);
  Dst := THostFormVLE.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'HostFormVLE1';
    Src.VLE := TTyValueListEditor.Create(Src);
    Src.VLE.Name := 'VLE';
    Src.VLE.Parent := Src;
    Src.VLE.KeyOptions := Want;
    MS.WriteComponent(Src);
    MS.Position := 0;
    MS.ReadComponent(Dst);

    D := Dst.FindComponent('VLE') as TTyValueListEditor;
    AssertNotNull('the editor survived the round trip', D);
    AssertTrue('and its KeyOptions came back bit-for-bit', D.KeyOptions = Want);
  finally
    MS.Free; Dst.Free; Src.Free;
  end;
end;

{ LCL's setter rewrites its own argument (valedit.pas:1037-1038) -- a row the user can create but
  cannot name is not worth creating. So this reads back MORE than was written, which is exactly
  the kind of asymmetry a later "simplification" removes. }
procedure TValueListKeyOptionsTest.TestKeyAddSilentlyImpliesKeyEdit;
var e: TTyValueListEditor;
begin
  e := TTyValueListEditor.Create(nil);
  try
    e.KeyOptions := [keyAdd];
    AssertTrue('keyAdd survived', keyAdd in e.KeyOptions);
    AssertTrue('and dragged keyEdit in with it', keyEdit in e.KeyOptions);
    e.KeyOptions := [keyDelete];
    AssertFalse('but keyDelete implies nothing', keyEdit in e.KeyOptions);
  finally e.Free; end;
end;

procedure TValueListKeyOptionsTest.TestKeyEditOffMeansNoKeyEditorAtAll;
var e: TValueListKeyDriver;
begin
  e := Make([], 0);
  try
    e.BeginKeyEdit(0);
    AssertEquals('no rename opens without keyEdit', -1, e.EditingRow);
    AssertFalse('and nothing is sitting over the key column', e.IsEditingKey);
    e.Press(VK_F2, [ssShift]);
    AssertEquals('Shift+F2 is inert too', -1, e.EditingRow);
  finally e.Free; end;
end;

procedure TValueListKeyOptionsTest.TestKeyEditOpensTheEditorOverTheKeyColumn;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit], 1);
  try
    e.BeginKeyEdit(1);
    AssertEquals('the rename opened on row 1', 1, e.EditingRow);
    AssertTrue('over the KEY column, not the value', e.IsEditingKey);
    AssertEquals('seeded with the row''s real key', 'B', e.InlineEditor.Text);

    { The value editor is a different cell on the same row: opening it must hand over, not be
      swallowed by a "same row, already editing" early exit. }
    e.BeginEdit(1);
    AssertEquals('still on row 1', 1, e.EditingRow);
    AssertFalse('but now over the VALUE column', e.IsEditingKey);
    AssertEquals('seeded with the row''s value', '2', e.InlineEditor.Text);
  finally e.Free; end;
end;

procedure TValueListKeyOptionsTest.TestKeyEditRenamesTheRowAndFiresOnKeyChanged;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit], 1);
  try
    e.Press(VK_F2, [ssShift]);        // the keyboard route, not the data API
    AssertTrue('Shift+F2 opened the rename', e.IsEditingKey);
    e.InlineEditor.Text := 'Beta';
    e.Commit;
    AssertEquals('the key changed', 'Beta', e.Keys[1]);
    AssertEquals('OnKeyChanged fired once', 1, FRenames);
    AssertSame('naming the row that was renamed', e.Row(1), FLastRenamed);
    AssertEquals('the editor closed', -1, e.EditingRow);
  finally e.Free; end;
end;

{ The routing mistake this exists to catch: the key cell's editor committing through the VALUE
  path, so a rename overwrites the row's data with the row's name. One `col = 0` test apart. }
procedure TValueListKeyOptionsTest.TestKeyEditCommitsToTheKeyNotTheValue;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit], 0);
  try
    e.BeginKeyEdit(0);
    e.InlineEditor.Text := 'Renamed';
    e.Commit;
    AssertEquals('key took the text', 'Renamed', e.Keys[0]);
    AssertEquals('and the VALUE was not touched', '1', e.ValueFromIndex[0]);
    AssertEquals('so no value-change event fired either', 0, FRejects);
  finally e.Free; end;
end;

procedure TValueListKeyOptionsTest.TestKeyEditCancelKeepsTheOldName;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit], 0);
  try
    e.BeginKeyEdit(0);
    e.InlineEditor.Text := 'Discarded';
    e.Cancel;
    AssertEquals('Escape throws the rename away', 'A', e.Keys[0]);
    AssertEquals('and fires nothing', 0, FRenames);
  finally e.Free; end;
end;

{ Turning keyEdit off while a rename is open must not leave a live editor that will still commit
  through a switch the app has just closed. }
procedure TValueListKeyOptionsTest.TestClearingKeyEditClosesAnOpenRename;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit], 0);
  try
    e.BeginKeyEdit(0);
    e.InlineEditor.Text := 'Sneak';
    e.KeyOptions := [];
    AssertEquals('the open rename was closed', -1, e.EditingRow);
    AssertEquals('and discarded, not applied', 'A', e.Keys[0]);
  finally e.Free; end;
end;

{ LCL inserts AT the current row (InsertRow('','',False), valedit.pas:1301) rather than appending,
  so the blank row lands where the user is looking. }
procedure TValueListKeyOptionsTest.TestKeyAddInsertsABlankRowAtTheCurrentPosition;
var e: TValueListKeyDriver;
begin
  e := Make([keyAdd], 1);
  try
    e.Press(VK_INSERT, []);
    AssertEquals('a row appeared', 4, e.RowCount);
    AssertEquals('at the selected position, not the end', '', e.Keys[1]);
    AssertEquals('pushing the old row down', 'B', e.Keys[2]);
    AssertEquals('and the last row is still the last row', 'C', e.Keys[3]);
  finally e.Free; end;
end;

procedure TValueListKeyOptionsTest.TestKeyAddOffLeavesInsertAlone;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit, keyDelete, keyUnique], 1);   // every flag EXCEPT keyAdd
  try
    e.Press(VK_INSERT, []);
    AssertEquals('Insert adds nothing without keyAdd', 3, e.RowCount);
  finally e.Free; end;
end;

procedure TValueListKeyOptionsTest.TestKeyDeleteRemovesTheCurrentRowOnCtrlDelete;
var e: TValueListKeyDriver;
begin
  e := Make([keyDelete], 1);
  try
    e.Press(VK_DELETE, [ssModifier]);
    AssertEquals('one row went', 2, e.RowCount);
    AssertEquals('the SELECTED one', 'A', e.Keys[0]);
    AssertEquals('and the rest closed up', 'C', e.Keys[1]);
  finally e.Free; end;
end;

{ Delphi's help says plain Delete; LCL's own comment (valedit.pas:1308-1309) records that testers
  only ever saw Ctrl+Delete, and bare Delete has to stay with the text being typed. }
procedure TValueListKeyOptionsTest.TestKeyDeleteIgnoresBareDelete;
var e: TValueListKeyDriver;
begin
  e := Make([keyDelete], 1);
  try
    e.Press(VK_DELETE, []);
    AssertEquals('bare Delete removes nothing', 3, e.RowCount);
    AssertEquals('and the row is untouched', 'B', e.Keys[1]);
  finally e.Free; end;
end;

procedure TValueListKeyOptionsTest.TestKeyDeleteOffLeavesCtrlDeleteAlone;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit, keyAdd, keyUnique], 1);   // every flag EXCEPT keyDelete
  try
    e.Press(VK_DELETE, [ssModifier]);
    AssertEquals('Ctrl+Delete removes nothing without keyDelete', 3, e.RowCount);
  finally e.Free; end;
end;

{ The whole obligation behind the flag: the rename must NOT take effect. Shipping keyUnique
  without this would be worse than not shipping it -- the switch would claim a guarantee the
  data does not have. }
procedure TValueListKeyOptionsTest.TestKeyUniqueRefusesADuplicateRename;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit, keyUnique], 0);
  try
    e.BeginKeyEdit(0);
    e.InlineEditor.Text := 'C';        // already the name of root row 2
    e.Commit;
    AssertEquals('the row KEPT its old key', 'A', e.Keys[0]);
    AssertEquals('the other row is untouched too', 'C', e.Keys[2]);
    AssertEquals('OnKeyRejected fired', 1, FRejects);
    AssertEquals('carrying the name that was refused', 'C', FLastRejectKey);
    AssertEquals('and OnKeyChanged did NOT', 0, FRenames);
  finally e.Free; end;
end;

{ LCL compares with AnsiCompareText (valedit.pas:1610) -- case-insensitive, because a list whose
  keys differ only in case is duplicate for every purpose an ini file has. }
procedure TValueListKeyOptionsTest.TestKeyUniqueFoldsCase;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit, keyUnique], 0);
  try
    e.BeginKeyEdit(0);
    e.InlineEditor.Text := 'c';
    e.Commit;
    AssertEquals('a case-only difference is still a duplicate', 'A', e.Keys[0]);
    AssertEquals('and was reported as one', 1, FRejects);
  finally e.Free; end;
end;

procedure TValueListKeyOptionsTest.TestWithoutKeyUniqueTheDuplicateIsAccepted;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit], 0);              // keyEdit WITHOUT keyUnique
  try
    e.BeginKeyEdit(0);
    e.InlineEditor.Text := 'C';
    e.Commit;
    AssertEquals('no uniqueness asked for, none enforced', 'C', e.Keys[0]);
    AssertEquals('nothing was refused', 0, FRejects);
    AssertEquals('and the rename was reported', 1, FRenames);
  finally e.Free; end;
end;

{ SIBLINGS, not the whole tree -- and this is a real divergence from LCL, whose list is flat so
  the two are the same set over there. Ours nests, and the nesting MANUFACTURES duplicates: every
  vekFont row grows children called 'name', 'size', 'bold'. A flat-global rule would make the
  second font row's 'size' un-renameable and declare the control's own tree invalid. }
procedure TValueListKeyOptionsTest.TestKeyUniqueScopesToSiblingsNotTheWholeTree;
var
  e: TValueListKeyDriver;
  parent: TTyValueRow;
begin
  e := Make([keyEdit, keyUnique], -1);
  try
    parent := e.AddRow('font', '');
    parent.AddChild('size', '9');
    parent.AddChild('weight', '400');
    { Rows start Expanded, so SetExpanded(True) would be a no-op here and would NOT rebuild.
      Direct child mutation is invisible until UpdateRows, exactly as the class documents. }
    e.UpdateRows;                       // flat list: 0..2 = A/B/C, 3 = font, 4/5 = its children
    AssertEquals('the tree flattened as expected', 6, e.DisplayRowCount);

    { A child may take a name a ROOT row already has -- different parents, no collision. }
    e.BeginKeyEdit(5);                  // the 'weight' child
    AssertTrue('the child rename opened', e.IsEditingKey);
    e.InlineEditor.Text := 'A';         // 'A' is a ROOT row
    e.Commit;
    AssertEquals('a different branch is not a collision', 'A', parent.Child[1].Key);
    AssertEquals('so nothing was refused', 0, FRejects);

    { Its own sibling, however, is. }
    e.BeginKeyEdit(5);
    e.InlineEditor.Text := 'size';      // its sibling's name
    e.Commit;
    AssertEquals('a SIBLING collision is refused', 'A', parent.Child[1].Key);
    AssertEquals('and reported', 1, FRejects);
  finally e.Free; end;
end;

{ keyAdd inserts BLANK rows, and two of them is the normal state of a list being filled in, so an
  empty key must collide with nothing. LCL skips empty Names[] for the same reason. }
procedure TValueListKeyOptionsTest.TestKeyUniqueLetsBlankKeysCoexist;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit, keyAdd, keyUnique], 0);
  try
    e.Press(VK_INSERT, []);
    e.Press(VK_INSERT, []);
    AssertEquals('two blank rows were inserted', 5, e.RowCount);
    AssertEquals('the first is blank', '', e.Keys[0]);
    AssertEquals('and so is the second', '', e.Keys[1]);

    e.BeginKeyEdit(0);
    e.InlineEditor.Text := '';          // blanking a name is not a duplicate either
    e.Commit;
    AssertEquals('blanking a key is never refused', 0, FRejects);
  finally e.Free; end;
end;

{ Committing a row's OWN name unchanged must not trip the check against itself -- the loop has to
  skip the row being renamed, and "compare against every row" is the obvious wrong version. }
procedure TValueListKeyOptionsTest.TestKeyUniqueDoesNotRefuseARowItsOwnName;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit, keyUnique], 0);
  try
    e.BeginKeyEdit(1);
    e.InlineEditor.Text := 'B';         // exactly what it is already called
    e.Commit;
    AssertEquals('the row keeps its name', 'B', e.Keys[1]);
    AssertEquals('and it was not treated as a clash with itself', 0, FRejects);

    { Same again, differing only in case -- still the same row, still not a clash. }
    e.BeginKeyEdit(1);
    e.InlineEditor.Text := 'b';
    e.Commit;
    AssertEquals('a case-only self-rename goes through', 'b', e.Keys[1]);
    AssertEquals('without a refusal', 0, FRejects);
  finally e.Free; end;
end;

{ ReadOnly means the whole sheet is read-only. KeyOptions describes what is PERMITTED when
  editing is possible at all; it must not become a back door around it. }
procedure TValueListKeyOptionsTest.TestReadOnlyOutranksEveryKeyOption;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit, keyAdd, keyDelete, keyUnique], 1);
  try
    e.ReadOnly := True;
    e.Press(VK_INSERT, []);
    AssertEquals('no row added', 3, e.RowCount);
    e.Press(VK_DELETE, [ssModifier]);
    AssertEquals('no row deleted', 3, e.RowCount);
    e.BeginKeyEdit(1);
    AssertEquals('no rename opened', -1, e.EditingRow);
    e.Press(VK_F2, [ssShift]);
    AssertEquals('not by keyboard either', -1, e.EditingRow);
    AssertEquals('and the list is exactly as it was', 'B', e.Keys[1]);
  finally e.Free; end;
end;

{ The programmatic rename path. Two deliberate bypasses, both LCL's own shape and both
  the kind a well-meaning tidy-up would "fix":

  - keyUnique does NOT gate it. LCL's SetKey is `Cells[0,Index]:=Value` (valedit.pas:1084)
    with no uniqueness check anywhere in it -- the check lives ONLY in the editor path
    (ValidateEntry, :1614). keyUnique polices the USER's gesture; the API is the host's
    own responsibility, exactly like ReadOnly vs `Text :=` on every edit control here.
  - ReadOnly does not gate it either, for the same reason SetValueFromIndex ignores it:
    programmatic writes are not user edits. }
procedure TValueListKeyOptionsTest.TestKeysWriteIsTheProgrammaticRenamePath;
var e: TValueListKeyDriver;
begin
  e := Make([keyEdit, keyUnique], -1);   // A/B/C with the uniqueness flag ON
  try
    e.Keys[0] := 'C';                    // collides with root row 2 -- and lands anyway
    AssertEquals('the write took effect DESPITE keyUnique', 'C', e.Keys[0]);
    AssertEquals('nothing was refused', 0, FRejects);
    AssertEquals('and the rename was reported through OnKeyChanged', 1, FRenames);
    AssertSame('naming the row that changed', e.Row(0), FLastRenamed);

    e.ReadOnly := True;
    e.Keys[1] := 'ZZ';
    AssertEquals('ReadOnly does not gate the programmatic write either', 'ZZ', e.Keys[1]);
    AssertEquals('and it was reported too', 2, FRenames);

    e.Keys[1] := 'ZZ';                   // the same name again
    AssertEquals('a same-name write is not a rename and fires nothing', 2, FRenames);
  finally e.Free; end;
end;

initialization
  RegisterTest(TValueListParityTest);
  RegisterTest(TValueListViewportMetricTest);
  RegisterTest(TValueListRowApiTest);
  RegisterTest(TValueListKeyOptionsTest);
end.
