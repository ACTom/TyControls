unit test.db.grid.edit;
{$mode objfpc}{$H+}

{ The data-aware grid, part three (issue #34 phase 2, plan Task 4): editing, inserting and
  deleting, through the user's own paths -- typing on the grid, F2, a double click, Enter and
  Esc in the editor, the arrows on the grid and in the editor (ChildKey), clicks on a check
  box, Insert, Ctrl+Del, the focus leaving (CM_EXIT).

  * typing puts the dataset in dsEdit; leaving the cell writes the field, leaving the record
    posts it, so does the dataset's own Post while the editor is open;
  * Esc drops the cell's edit, then (no editor) the record's;
  * Down past the last record appends (not with dgDisableInsert, not when the grid cannot
    modify); a new record nobody typed into is dropped by Up, by Down when inserted inside the
    dataset, by the focus leaving (dgCancelOnExit) -- and stays put while it is the appended one;
  * Insert inserts; Ctrl+Del deletes after ConfirmDeleteRecord (the probe answers), not at all
    when it says no, without asking when dgConfirmDelete is off, never with dgDisableDelete;
  * read-only: the grid, dgEditing, the data link, a data source that does not AutoEdit (Edit
    refused), the field, the column, a calculated, auto-increment or lookup field whose key
    cannot change, a memo without dgDisplayMemoText -- typing opens nothing and is swallowed;
  * a check box writes AsBoolean (a boolean field), or the column's words (a 'Y' / 'N' field);
  * a lookup field edits as a pick list of its LookupDataSet and writes its key field;
  * the edit mask is the field's, through OnFieldEditMask; a string field's editor takes no
    more than its Size;
  * a value the field (OnValidate) or the dataset (BeforePost) refuses keeps the editor on its
    cell with the user's text, and the exception reaches the caller.

  The records are read off the dataset, never through the grid. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, StdCtrls, LCLType, LMessages, DB, BufDataset, DBGrids,
  fpcunit, testregistry,
  dbfixtures, tyControls.Grid, tyControls.DB.Grid, test.db.grid.nav;

type
  TDBGridEditTest = class(TTestCase)
  private
    FForm: TForm;
    FRows: TDbRowsFixture;
    FPeople: TDbFixture;
    FKinds: TBufDataset;
    FKindsSrc: TDataSource;
    FGrid: TDBGridProbe;
    FMaskAsked: Integer;
    function DS: TDataSet;
    function ID: Integer;
    function NameOf: string;
    function ColOf(const AFieldName: string): Integer;
    function NameIn(ARecord: Integer): string;
    function ValueIn(ADataSet: TDataSet; const AKeyField: string; const AKey: Variant;
      const AFieldName: string): string;
    procedure GoToCell(const AFieldName: string);
    procedure BindKinds;
    procedure AssertCannotType(const AWhen, AFieldName: string);
    procedure RefuseBad(Sender: TField);
    procedure RefuseBadPost(DataSet: TDataSet);
    procedure MaskForName(Sender: TObject; const Field: TField; var Value: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { typing, writing, posting }
    procedure TestTypingEntersEditAndLeavingTheRecordPosts;
    procedure TestLeavingTheCellWritesTheField;
    procedure TestF2OpensWithTheFieldText;
    procedure TestEnterInTheEditorWritesTheField;
    procedure TestDataSetPostTakesTheOpenEditor;
    procedure TestACharTheFieldRefusesStartsNothing;
    procedure TestStringEditorTakesNoMoreThanTheSize;
    { Esc }
    procedure TestEscDropsTheCellThenTheRecord;
    { appending and inserting }
    procedure TestDownPastTheLastRecordAppends;
    procedure TestPristineAppendedRecordIsDroppedByUp;
    procedure TestTypedAppendedRecordIsPostedByUp;
    procedure TestDownInTheEditorAppends;
    procedure TestDisableInsertStopsTheAppend;
    procedure TestAReadOnlyGridDoesNotAppend;
    procedure TestInsertKeyInserts;
    procedure TestFocusLeavingDropsAPristineRecord;
    { deleting }
    procedure TestCtrlDelAsksFirst;
    procedure TestCtrlDelWithoutConfirmDelete;
    procedure TestDisableDeleteStopsCtrlDel;
    { read-only }
    procedure TestReadOnlyGridAndOptions;
    procedure TestReadOnlyLinkAndRefusedEdit;
    procedure TestReadOnlyFieldAndColumn;
    procedure TestComputedFieldsAreReadOnly;
    procedure TestMemoEditsOnlyAsText;
    { check boxes, lookups, masks }
    procedure TestCheckBoxClickAndSpaceWriteTheBoolean;
    procedure TestCheckBoxOfAWordField;
    procedure TestReadOnlyCheckBoxDoesNotToggle;
    procedure TestLookupPicksFromItsDataSetAndWritesTheKey;
    procedure TestUpDownInAClosedPickListMoveTheRecord;
    procedure TestEditMaskIsTheField;
    { refusals }
    procedure TestFieldRefusalKeepsTheEditor;
    procedure TestPostRefusalKeepsTheEditor;
  end;

implementation

uses
  tyControls.MaskEdit, test.db.edits;

{ ================================================================== TDBGridEditTest ===== }

procedure TDBGridEditTest.SetUp;

  function AddField(AClass: TFieldClass; const AName: string; AKind: TFieldKind): TField;
  begin
    Result := AClass.Create(FKinds);
    Result.FieldName := AName;
    Result.FieldKind := AKind;
    if Result is TStringField then Result.Size := 20;
    Result.DataSet := FKinds;
  end;

var
  look: TField;
begin
  NeedDBWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 500);
  FRows := NewRowsFixture(nil);
  FPeople := NewDbFixture(nil);
  { The field kinds a grid cannot edit, and a lookup into the fixture's cities. }
  FKinds := TBufDataset.Create(nil);
  AddField(TAutoIncField, 'Auto', fkData);
  AddField(TStringField, 'Name', fkData);
  AddField(TIntegerField, 'CityID', fkData);
  AddField(TStringField, 'Calc', fkCalculated);
  look := AddField(TStringField, 'City', fkLookup);
  look.LookupDataSet := FPeople.Cities;
  look.KeyFields := 'CityID';
  look.LookupKeyFields := 'ID';
  look.LookupResultField := 'Name';
  FKinds.CreateDataset;
  FKinds.Append;
  FKinds.FieldByName('Name').AsString := 'One';
  FKinds.FieldByName('CityID').AsInteger := 2;
  FKinds.Post;
  FKinds.Append;
  FKinds.FieldByName('Name').AsString := 'Two';
  FKinds.FieldByName('CityID').AsInteger := 1;
  FKinds.Post;
  FKinds.First;
  FKindsSrc := TDataSource.Create(nil);
  FKindsSrc.DataSet := FKinds;
  FGrid := TDBGridProbe.Create(FForm);
  FGrid.Font.PixelsPerInch := 96;
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 520, 260);
  FGrid.DataSource := FRows.Src;
end;

procedure TDBGridEditTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FKindsSrc);
  FreeAndNil(FKinds);
  FreeAndNil(FRows);
  FreeAndNil(FPeople);
  FGrid := nil;
end;

function TDBGridEditTest.DS: TDataSet;
begin
  Result := FGrid.DataLink.DataSet;
end;

function TDBGridEditTest.ID: Integer;
begin
  Result := DS.FieldByName('ID').AsInteger;
end;

function TDBGridEditTest.NameOf: string;
begin
  Result := DS.FieldByName('Name').AsString;
end;

function TDBGridEditTest.ColOf(const AFieldName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to FGrid.Columns.Count - 1 do
    if SameText(FGrid.Columns[i].FieldName, AFieldName) then Exit(i);
  Fail('no column for ' + AFieldName);
  Result := -1;
end;

{ The Name of the record whose ID is ARecord, read off the table (the grid not involved). }
function TDBGridEditTest.NameIn(ARecord: Integer): string;
var
  bm: TBookmark;
begin
  bm := FRows.DS.GetBookmark;
  try
    if FRows.DS.Locate('ID', ARecord, []) then
      Result := FRows.DS.FieldByName('Name').AsString
    else
      Result := '<none>';
    FRows.DS.GotoBookmark(bm);
  finally
    FRows.DS.FreeBookmark(bm);
  end;
end;

{ AFieldName of ADataSet's record whose AKeyField is AKey, as a string; the table is put
  back where it was. Only while it browses (a Locate would post an edit). }
function TDBGridEditTest.ValueIn(ADataSet: TDataSet; const AKeyField: string;
  const AKey: Variant; const AFieldName: string): string;
var
  bm: TBookmark;
begin
  AssertTrue('read while browsing', ADataSet.State = dsBrowse);
  bm := ADataSet.GetBookmark;
  try
    if ADataSet.Locate(AKeyField, AKey, []) then
      Result := ADataSet.FieldByName(AFieldName).AsString
    else
      Result := '<none>';
    ADataSet.GotoBookmark(bm);
  finally
    ADataSet.FreeBookmark(bm);
  end;
end;

procedure TDBGridEditTest.GoToCell(const AFieldName: string);
begin
  FGrid.Col := ColOf(AFieldName);
  AssertEquals('on the ' + AFieldName + ' column', ColOf(AFieldName), FGrid.Col);
end;

procedure TDBGridEditTest.BindKinds;
begin
  FGrid.DataSource := FKindsSrc;
end;

{ Typing on AFieldName's cell opens no editor, leaves the dataset browsing and is swallowed. }
procedure TDBGridEditTest.AssertCannotType(const AWhen, AFieldName: string);
var
  before: string;
begin
  GoToCell(AFieldName);
  before := DS.FieldByName(AFieldName).AsString;
  AssertEquals(AWhen + ': the key is swallowed', #0, FGrid.TypeChar('7'));
  AssertFalse(AWhen + ': no editor', FGrid.EditorMode);
  AssertTrue(AWhen + ': still browsing', DS.State = dsBrowse);
  FGrid.PressKey(VK_F2);
  AssertFalse(AWhen + ': F2 opens no editor either', FGrid.EditorMode);
  AssertTrue(AWhen + ': still browsing after F2', DS.State = dsBrowse);
  AssertEquals(AWhen + ': the value', before, DS.FieldByName(AFieldName).AsString);
end;

procedure TDBGridEditTest.RefuseBad(Sender: TField);
begin
  if Sender.AsString = 'bad' then raise EDatabaseError.Create('not a name');
end;

procedure TDBGridEditTest.RefuseBadPost(DataSet: TDataSet);
begin
  if DataSet.FieldByName('Name').AsString = 'bad' then
    raise EDatabaseError.Create('not this name');
end;

procedure TDBGridEditTest.MaskForName(Sender: TObject; const Field: TField; var Value: string);
begin
  Inc(FMaskAsked);
  if Field.FieldName = 'Name' then Value := '>LLL;1;_';
end;

{ ----------------------------------------------------- typing, writing, posting ------ }

procedure TDBGridEditTest.TestTypingEntersEditAndLeavingTheRecordPosts;
begin
  GoToCell('Name');
  AssertTrue('browsing', DS.State = dsBrowse);
  AssertEquals('the key opened the editor', #0, FGrid.TypeChar('Z'));
  AssertTrue('the editor is open', FGrid.EditorMode);
  AssertEquals('with the key', 'Z', FGrid.EditorText);
  AssertTrue('typing put the dataset in dsEdit', DS.State = dsEdit);
  FGrid.SetEditorText('Zed');
  FGrid.PressKey(VK_DOWN);
  AssertEquals('Down: the next record', 2, ID);
  AssertTrue('the record left was posted', DS.State = dsBrowse);
  AssertEquals('with what was typed', 'Zed', NameIn(1));
  AssertEquals('nothing else changed', FixRowName(2), NameOf);
end;

procedure TDBGridEditTest.TestLeavingTheCellWritesTheField;
begin
  GoToCell('Name');
  FGrid.TypeChar('Q');
  FGrid.SetEditorText('Quux');
  FGrid.PressKey(VK_RIGHT);
  AssertFalse('the editor closed', FGrid.EditorMode);
  AssertEquals('the next column', ColOf('Name') + 1, FGrid.Col);
  AssertEquals('the field has the text', 'Quux', NameOf);
  AssertTrue('the record is still being edited', DS.State = dsEdit);
  AssertEquals('the cell shows it', 'Quux', FGrid.Cell(ColOf('Name'), FGrid.Row));
end;

procedure TDBGridEditTest.TestF2OpensWithTheFieldText;
var
  amount: TField;
begin
  DS.Next;
  amount := DS.FieldByName('Amount');
  TNumericField(amount).DisplayFormat := '0.000';
  TNumericField(amount).EditFormat := '0.0';
  GoToCell('Amount');
  AssertEquals('F2 consumed', 0, FGrid.PressKey(VK_F2));
  AssertTrue('the editor is open', FGrid.EditorMode);
  AssertEquals('the field''s Text, not its DisplayText', amount.Text, FGrid.EditorText);
  AssertTrue('the display format is not the edit text', amount.Text <> amount.DisplayText);
end;

procedure TDBGridEditTest.TestEnterInTheEditorWritesTheField;
begin
  GoToCell('Name');
  FGrid.PressKey(VK_F2);
  FGrid.SetEditorText('Entered');
  FGrid.PressKeyInEditor(VK_RETURN);
  AssertFalse('Enter closed the editor', FGrid.EditorMode);
  AssertEquals('and wrote the field', 'Entered', NameOf);
  AssertEquals('on the same record', 1, ID);
end;

procedure TDBGridEditTest.TestDataSetPostTakesTheOpenEditor;
begin
  GoToCell('Name');
  FGrid.TypeChar('P');
  FGrid.SetEditorText('Posted');
  DS.Post;                                 // a navigator's Post, say
  AssertTrue('posted', DS.State = dsBrowse);
  AssertEquals('with the open editor''s text', 'Posted', NameIn(1));
  AssertFalse('the editor closed', FGrid.EditorMode);
end;

procedure TDBGridEditTest.TestACharTheFieldRefusesStartsNothing;
begin
  GoToCell('Amount');
  AssertEquals('a letter in a number: swallowed', #0, FGrid.TypeChar('x'));
  AssertFalse('no editor', FGrid.EditorMode);
  AssertTrue('still browsing', DS.State = dsBrowse);
  FGrid.TypeChar('7');
  AssertTrue('a digit opens it', FGrid.EditorMode);
  AssertEquals('with the digit', '7', FGrid.EditorText);
end;

procedure TDBGridEditTest.TestStringEditorTakesNoMoreThanTheSize;
begin
  GoToCell('Name');
  FGrid.PressKey(VK_F2);
  AssertTrue('open', FGrid.EditorMode);
  AssertEquals('MaxLength: the field''s Size', DS.FieldByName('Name').Size,
    FGrid.EditorMaxLength);
end;

{ ---------------------------------------------------------------------- Esc ---------- }

procedure TDBGridEditTest.TestEscDropsTheCellThenTheRecord;
var
  amountText: string;
begin
  GoToCell('Name');
  FGrid.TypeChar('E');
  FGrid.SetEditorText('Edited');
  FGrid.PressKey(VK_RIGHT);                // Name written, still dsEdit
  AssertEquals('Name written', 'Edited', NameOf);
  GoToCell('Amount');
  amountText := DS.FieldByName('Amount').Text;
  FGrid.TypeChar('9');
  FGrid.PressKeyInEditor(VK_ESCAPE);
  AssertFalse('Esc in the editor closed it', FGrid.EditorMode);
  AssertEquals('the cell''s edit dropped', amountText, DS.FieldByName('Amount').Text);
  AssertTrue('the record still being edited', DS.State = dsEdit);
  AssertEquals('the other cell''s change still there', 'Edited', NameOf);
  AssertEquals('Esc on the grid consumed', 0, FGrid.PressKey(VK_ESCAPE));
  AssertTrue('the record cancelled', DS.State = dsBrowse);
  AssertEquals('the name back', FixRowName(1), NameOf);
  AssertEquals('Esc with nothing to cancel is left to the form', VK_ESCAPE,
    FGrid.PressKey(VK_ESCAPE));
end;

{ ------------------------------------------------------- appending and inserting ----- }

procedure TDBGridEditTest.TestDownPastTheLastRecordAppends;
var
  n: Integer;
begin
  DS.Last;
  n := FGrid.RowCount;
  FGrid.PressKey(VK_DOWN);
  AssertTrue('Down past the last record: a new one', DS.State = dsInsert);
  AssertTrue('an empty one', DS.FieldByName('ID').IsNull);
  AssertEquals('on the last row', FGrid.RowCount - 1, FGrid.Row);
  AssertEquals('the window kept its size', n, FGrid.RowCount);
  AssertEquals('the row before it is the old last record', FixRowName(CFixRowCount),
    FGrid.Cell(ColOf('Name'), FGrid.Row - 1));
  FGrid.PressKey(VK_DOWN);
  AssertTrue('Down on it again: it stays', DS.State = dsInsert);
  AssertEquals('no second record', CFixRowCount, FRows.DS.RecordCount);
end;

procedure TDBGridEditTest.TestPristineAppendedRecordIsDroppedByUp;
begin
  DS.Last;
  FGrid.PressKey(VK_DOWN);
  AssertTrue('appended', DS.State = dsInsert);
  FGrid.PressKey(VK_UP);
  AssertTrue('Up on a record nobody typed into: dropped', DS.State = dsBrowse);
  AssertEquals('no record added', CFixRowCount, FRows.DS.RecordCount);
  AssertEquals('back on the last record, not one above it', CFixRowCount, ID);
end;

procedure TDBGridEditTest.TestTypedAppendedRecordIsPostedByUp;
begin
  DS.Last;
  FGrid.PressKey(VK_DOWN);
  GoToCell('Name');
  FGrid.TypeChar('N');
  FGrid.SetEditorText('New');
  FGrid.PressKey(VK_UP);
  AssertTrue('typed into: posted', DS.State = dsBrowse);
  AssertEquals('one record more', CFixRowCount + 1, FRows.DS.RecordCount);
  AssertTrue('it is there', DS.Locate('Name', 'New', []));
end;

procedure TDBGridEditTest.TestDownInTheEditorAppends;
begin
  DS.Last;
  GoToCell('Name');
  FGrid.TypeChar('L');
  FGrid.SetEditorText('Last one');
  AssertTrue('the editor claims Down', FGrid.ChildArrow(VK_DOWN));
  AssertTrue('a new record appended', DS.State = dsInsert);
  AssertFalse('the editor closed', FGrid.EditorMode);
  { Reading the table drops the new record (nobody typed into it). }
  AssertEquals('the record left was posted', 'Last one', NameIn(CFixRowCount));
end;

procedure TDBGridEditTest.TestDisableInsertStopsTheAppend;
begin
  FGrid.Options := FGrid.Options + [dgDisableInsert];
  DS.Last;
  FGrid.PressKey(VK_DOWN);
  AssertTrue('no new record', DS.State = dsBrowse);
  AssertEquals('on the last one', CFixRowCount, ID);
  FGrid.PressKey(VK_INSERT);
  AssertTrue('Insert neither', DS.State = dsBrowse);
end;

procedure TDBGridEditTest.TestAReadOnlyGridDoesNotAppend;
begin
  FGrid.ReadOnly := True;
  DS.Last;
  FGrid.PressKey(VK_DOWN);
  AssertTrue('no new record', DS.State = dsBrowse);
  FGrid.ReadOnly := False;
  FGrid.Options := FGrid.Options - [dgEditing];
  FGrid.PressKey(VK_DOWN);
  AssertTrue('no new record without dgEditing', DS.State = dsBrowse);
end;

procedure TDBGridEditTest.TestInsertKeyInserts;
begin
  DS.MoveBy(2);
  AssertEquals('Insert consumed', 0, FGrid.PressKey(VK_INSERT));
  AssertTrue('a new record', DS.State = dsInsert);
  AssertEquals('on the row it was inserted at', 2, FGrid.Row);
  GoToCell('Name');
  FGrid.TypeChar('I');
  FGrid.SetEditorText('Inserted');
  FGrid.PressKey(VK_DOWN);
  AssertTrue('posted', DS.State = dsBrowse);
  AssertEquals('one more', CFixRowCount + 1, FRows.DS.RecordCount);
  { A pristine one inside the dataset: Down drops it. }
  FGrid.PressKey(VK_INSERT);
  AssertTrue('inserted again', DS.State = dsInsert);
  FGrid.PressKey(VK_DOWN);
  AssertTrue('Down dropped it', DS.State = dsBrowse);
  AssertEquals('still one more', CFixRowCount + 1, FRows.DS.RecordCount);
end;

procedure TDBGridEditTest.TestFocusLeavingDropsAPristineRecord;
begin
  DS.Last;
  FGrid.PressKey(VK_DOWN);
  AssertTrue('appended', DS.State = dsInsert);
  FGrid.Perform(CM_EXIT, 0, 0);
  AssertTrue('the focus left: dropped', DS.State = dsBrowse);
  AssertEquals('no record added', CFixRowCount, FRows.DS.RecordCount);
  FGrid.Options := FGrid.Options - [dgCancelOnExit];
  FGrid.PressKey(VK_DOWN);
  FGrid.Perform(CM_EXIT, 0, 0);
  AssertTrue('without dgCancelOnExit it stays', DS.State = dsInsert);
end;

{ ---------------------------------------------------------------------- deleting ----- }

procedure TDBGridEditTest.TestCtrlDelAsksFirst;
begin
  DS.Next;
  FGrid.ConfirmAnswer := False;
  FGrid.PressKey(VK_DELETE, [ssCtrl]);
  AssertEquals('asked', 1, FGrid.ConfirmCount);
  AssertEquals('"no": nothing deleted', CFixRowCount, FRows.DS.RecordCount);
  AssertEquals('still on it', 2, ID);
  FGrid.ConfirmAnswer := True;
  AssertEquals('consumed', 0, FGrid.PressKey(VK_DELETE, [ssCtrl]));
  AssertEquals('asked again', 2, FGrid.ConfirmCount);
  AssertEquals('"yes": deleted', CFixRowCount - 1, FRows.DS.RecordCount);
  AssertEquals('it is gone', '<none>', NameIn(2));
  FGrid.PressKey(VK_DELETE);
  AssertEquals('Del alone deletes nothing', CFixRowCount - 1, FRows.DS.RecordCount);
end;

procedure TDBGridEditTest.TestCtrlDelWithoutConfirmDelete;
begin
  FGrid.Options := FGrid.Options - [dgConfirmDelete];
  FGrid.ConfirmAnswer := False;
  FGrid.PressKey(VK_DELETE, [ssCtrl]);
  AssertEquals('not asked', 0, FGrid.ConfirmCount);
  AssertEquals('deleted', CFixRowCount - 1, FRows.DS.RecordCount);
end;

procedure TDBGridEditTest.TestDisableDeleteStopsCtrlDel;
begin
  FGrid.Options := FGrid.Options + [dgDisableDelete];
  FGrid.ConfirmAnswer := True;
  FGrid.PressKey(VK_DELETE, [ssCtrl]);
  AssertEquals('nothing deleted', CFixRowCount, FRows.DS.RecordCount);
  FGrid.Options := FGrid.Options - [dgDisableDelete];
  FGrid.ReadOnly := True;
  FGrid.PressKey(VK_DELETE, [ssCtrl]);
  AssertEquals('nor by a read-only grid', CFixRowCount, FRows.DS.RecordCount);
  AssertEquals('never asked', 0, FGrid.ConfirmCount);
end;

{ ---------------------------------------------------------------------- read-only ---- }

procedure TDBGridEditTest.TestReadOnlyGridAndOptions;
begin
  FGrid.ReadOnly := True;
  AssertCannotType('ReadOnly grid', 'Name');
  FGrid.ReadOnly := False;
  FGrid.Options := FGrid.Options - [dgEditing];
  AssertCannotType('no dgEditing', 'Name');
  FGrid.Options := FGrid.Options + [dgEditing];
  FGrid.TypeChar('o');
  AssertTrue('editable again', FGrid.EditorMode);
end;

procedure TDBGridEditTest.TestReadOnlyLinkAndRefusedEdit;
begin
  FGrid.DataLink.ReadOnly := True;
  AssertCannotType('a read-only data link', 'Name');
  FGrid.DataLink.ReadOnly := False;
  FRows.Src.AutoEdit := False;
  { The cell looks editable; the dataset refuses to edit, and that refusal is read-only. }
  AssertCannotType('a data source that does not AutoEdit', 'Name');
  GoToCell('Flag');
  FGrid.PressKey(VK_SPACE);
  AssertTrue('Space on a check box edits nothing either', DS.State = dsBrowse);
  AssertTrue('the flag unchanged', DS.FieldByName('Flag').AsBoolean);
  GoToCell('Name');
  FRows.Src.AutoEdit := True;
  FGrid.TypeChar('o');
  AssertTrue('editable again', FGrid.EditorMode);
end;

procedure TDBGridEditTest.TestReadOnlyFieldAndColumn;
begin
  DS.FieldByName('Name').ReadOnly := True;
  AssertCannotType('a read-only field', 'Name');
  DS.FieldByName('Name').ReadOnly := False;
  FGrid.Columns[ColOf('Name')].ReadOnly := True;
  AssertCannotType('a read-only column', 'Name');
  FGrid.Columns[ColOf('Name')].ReadOnly := False;
  FGrid.TypeChar('o');
  AssertTrue('editable again', FGrid.EditorMode);
end;

procedure TDBGridEditTest.TestComputedFieldsAreReadOnly;
begin
  BindKinds;
  AssertCannotType('an auto-increment field', 'Auto');
  AssertCannotType('a calculated field', 'Calc');
  FKinds.FieldByName('CityID').ReadOnly := True;
  AssertCannotType('a lookup whose key cannot change', 'City');
  FKinds.FieldByName('CityID').ReadOnly := False;
  GoToCell('City');
  FGrid.PressKey(VK_F2);
  AssertTrue('a lookup whose key can change edits', FGrid.EditorMode);
  AssertTrue('as a pick list', FGrid.EditKind(ColOf('City'), FGrid.Row) = gekPickList);
end;

procedure TDBGridEditTest.TestMemoEditsOnlyAsText;
begin
  AssertCannotType('a memo showing (MEMO)', 'Note');
  FGrid.Options := FGrid.Options + [dgDisplayMemoText];
  GoToCell('Note');
  FGrid.PressKey(VK_F2);
  AssertTrue('a memo showing its text edits', FGrid.EditorMode);
  AssertEquals('its content', 'Note 01', FGrid.EditorText);
  FGrid.SetEditorText('Changed note');
  FGrid.PressKey(VK_DOWN);
  AssertEquals('written as its content', 'Changed note', ValueIn(FRows.DS, 'ID', 1, 'Note'));
end;

{ ---------------------------------------------------- check boxes, lookups, masks ----- }

procedure TDBGridEditTest.TestCheckBoxClickAndSpaceWriteTheBoolean;
var
  flag: TField;
  col: Integer;
begin
  flag := DS.FieldByName('Flag');
  col := ColOf('Flag');
  AssertTrue('record 1 is flagged', flag.AsBoolean);
  FGrid.ClickCheckBox(col, 0);
  AssertTrue('the click edits the record', DS.State = dsEdit);
  AssertFalse('unchecked: False', flag.AsBoolean);
  AssertFalse('False, not NULL', flag.IsNull);
  AssertEquals('Space consumed', 0, FGrid.PressKey(VK_SPACE));
  AssertTrue('Space: True again', flag.AsBoolean);
  FGrid.PressKey(VK_SPACE);
  FGrid.PressKey(VK_DOWN);
  AssertEquals('posted False', 'False', ValueIn(FRows.DS, 'ID', 1, 'Flag'));
  AssertEquals('on the next record', 2, ID);
  FGrid.ClickCheckBox(col, 1);
  AssertTrue('record 2 (not flagged) checked', flag.AsBoolean);
end;

procedure TDBGridEditTest.TestCheckBoxOfAWordField;
var
  c: TTyDBGridColumn;
  flag: TField;
begin
  c := FGrid.Columns.Add;
  c.FieldName := 'Flag';
  c.EditorKind := gekCheckBox;
  c.ValueChecked := 'Y';
  c.ValueUnchecked := 'N';
  FGrid.DataSource := FPeople.Src;
  flag := DS.FieldByName('Flag');
  AssertEquals('row 1 is Y', 'Y', flag.AsString);
  AssertTrue('drawn checked', FGrid.CellCheckState(0, 0) = cbChecked);
  FGrid.Col := 0;
  FGrid.PressKey(VK_SPACE);
  AssertEquals('Space writes the unchecked word', 'N', flag.AsString);
  FGrid.ClickCheckBox(0, 0);
  AssertEquals('a click the checked word', 'Y', flag.AsString);
end;

procedure TDBGridEditTest.TestReadOnlyCheckBoxDoesNotToggle;
var
  flag: TField;
begin
  flag := DS.FieldByName('Flag');
  flag.ReadOnly := True;
  AssertTrue('still drawn as a check box', FGrid.EditKind(ColOf('Flag'), 0) = gekCheckBox);
  FGrid.ClickCheckBox(ColOf('Flag'), 0);
  FGrid.PressKey(VK_SPACE);
  AssertTrue('unchanged', flag.AsBoolean);
  AssertTrue('never edited', DS.State = dsBrowse);
end;

procedure TDBGridEditTest.TestLookupPicksFromItsDataSetAndWritesTheKey;
var
  items: TStrings;
begin
  BindKinds;
  AssertEquals('record 1 is in Tokyo', 'Tokyo', FKinds.FieldByName('City').AsString);
  GoToCell('City');
  FGrid.PressKey(VK_F2);
  AssertTrue('a pick list', FGrid.EditorMode);
  items := FGrid.PickEditorItems;
  AssertEquals('the lookup table''s three cities', 3, items.Count);
  AssertEquals('in its order', 'Paris,Tokyo,Lima', items.CommaText);
  AssertEquals('on the current one', 1, FGrid.PickEditorIndex);
  AssertEquals('the lookup table left where it was', 1, FPeople.Cities.RecNo);
  FGrid.SetPickEditorIndex(2);
  FGrid.EndEdit(True);
  AssertEquals('the key field written', 3, FKinds.FieldByName('CityID').AsInteger);
  AssertEquals('the cell shows the pick', 'Lima', FGrid.Cell(ColOf('City'), FGrid.Row));
  FGrid.PressKey(VK_DOWN);
  AssertEquals('posted', '3', ValueIn(FKinds, 'Name', 'One', 'CityID'));
end;

procedure TDBGridEditTest.TestUpDownInAClosedPickListMoveTheRecord;
begin
  { #59 hands a closed pick list's Up/Down to the grid; here that move is the dataset's. }
  BindKinds;
  GoToCell('City');
  FGrid.PressKey(VK_F2);
  AssertTrue('a pick list', FGrid.EditorMode);
  AssertEquals('on the first record', 1, FKinds.RecNo);
  FGrid.PressKeyInPickList(VK_DOWN);
  AssertEquals('Down moved the dataset', 2, FKinds.RecNo);
  AssertEquals('the grid row follows the record', 1, FGrid.Row);
  AssertEquals('the value under the key left alone', '2', ValueIn(FKinds, 'Name', 'One', 'CityID'));
  FGrid.PressKey(VK_F2);
  FGrid.PressKeyInPickList(VK_UP);
  AssertEquals('Up moved it back', 1, FKinds.RecNo);
  AssertEquals('the row too', 0, FGrid.Row);
  AssertEquals('that value left alone too', '1', ValueIn(FKinds, 'Name', 'Two', 'CityID'));
end;

procedure TDBGridEditTest.TestEditMaskIsTheField;
begin
  DS.FieldByName('Name').EditMask := '>LLLL;1;_';
  GoToCell('Name');
  AssertTrue('a mask: the mask editor', FGrid.EditKind(ColOf('Name'), 0) = gekMask);
  FGrid.PressKey(VK_F2);
  AssertTrue('it opened', FGrid.MaskEditorShown);
  AssertEquals('the field''s mask', '>LLLL;1;_', FGrid.MaskOfEditor);
  FGrid.EndEdit(False);
  FGrid.OnFieldEditMask := @MaskForName;
  FGrid.PressKey(VK_F2);
  AssertTrue('the event was asked', FMaskAsked > 0);
  AssertEquals('the event''s mask', '>LLL;1;_', FGrid.MaskOfEditor);
  FGrid.EndEdit(False);
  { A field without a mask, given one by the event. }
  DS.FieldByName('Name').EditMask := '';
  AssertTrue('the current cell asks the event', FGrid.EditKind(ColOf('Name'), 0) = gekMask);
  FGrid.OnFieldEditMask := nil;
  AssertTrue('no mask: text', FGrid.EditKind(ColOf('Name'), 0) = gekText);
end;

{ ---------------------------------------------------------------------- refusals ----- }

procedure TDBGridEditTest.TestFieldRefusalKeepsTheEditor;
var
  raised: Boolean;
begin
  DS.FieldByName('Name').OnValidate := @RefuseBad;
  GoToCell('Name');
  FGrid.TypeChar('b');
  FGrid.SetEditorText('bad');
  raised := False;
  try
    FGrid.PressKeyInEditor(VK_RETURN);
  except
    on E: EDatabaseError do raised := True;
  end;
  AssertTrue('the field''s exception reaches the caller', raised);
  AssertTrue('the editor is open again', FGrid.EditorMode);
  AssertEquals('with what the user typed', 'bad', FGrid.EditorText);
  AssertEquals('on its cell', ColOf('Name'), FGrid.Col);
  AssertEquals('on its record', 1, ID);
  AssertEquals('the field keeps its value', FixRowName(1), NameOf);
  raised := False;
  try
    FGrid.PressKey(VK_DOWN);
  except
    on E: EDatabaseError do raised := True;
  end;
  AssertTrue('Down refused too', raised);
  AssertEquals('Down did not leave the record', 1, ID);
  AssertTrue('the editor still open', FGrid.EditorMode);
  AssertEquals('still the text', 'bad', FGrid.EditorText);
  FGrid.SetEditorText('good');
  FGrid.PressKeyInEditor(VK_RETURN);
  AssertEquals('a good value goes in', 'good', NameOf);
end;

procedure TDBGridEditTest.TestPostRefusalKeepsTheEditor;
var
  raised: Boolean;
begin
  FRows.DS.BeforePost := @RefuseBadPost;
  GoToCell('Name');
  FGrid.TypeChar('b');
  FGrid.SetEditorText('bad');
  raised := False;
  try
    FGrid.ChildArrow(VK_DOWN);
  except
    on E: EDatabaseError do raised := True;
  end;
  AssertTrue('the post''s exception reaches the caller', raised);
  AssertEquals('the record not left', 1, ID);
  AssertTrue('still being edited', DS.State = dsEdit);
  AssertTrue('the editor is open again', FGrid.EditorMode);
  AssertEquals('with what the user typed', 'bad', FGrid.EditorText);
  AssertEquals('on its cell', ColOf('Name'), FGrid.Col);
  FRows.DS.BeforePost := nil;
end;

initialization
  RegisterTest(TDBGridEditTest);
end.
