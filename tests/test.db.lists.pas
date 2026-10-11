unit test.db.lists;
{$mode objfpc}{$H+}

{ The data-aware lists (issue #34, plan Task 6): TTyDBComboBox, TTyDBListBox, TTyDBLookupComboBox
  and TTyDBLookupListBox, through the shared C1-C8 run of test.db.edits plus what only lists
  have.

  The combo box and the list box hold a text value, written on Enter, EditingDone or leaving
  the control, and Escape takes it back -- in the combo box by cancelling the record when the
  combo box started the edit (LCL's EditingSource rule). The lookup controls write the picked
  row's key into the record at once, as LCL's do; the lookup combo box still takes Escape as a
  Cancel of the record it put in dsEdit, the lookup list box (like LCL's) has no pending edit
  for Escape to drop.

  Every change is the user's: keys to the control (KeyDown / UTF8KeyPress), and for an editable
  combo box the keys its child edit gets -- typed characters (IntfUTF8KeyPress) and Escape /
  Enter as the widgetset delivers them (CN_KEYDOWN, then LM_KEYDOWN when the edit leaves the
  key alone), which is the only way they reach the combo box. }

interface

uses
  Classes, SysUtils, Controls, Forms, LCLType, LMessages, Variants, DB, BufDataset, TypInfo,
  fpcunit, testregistry,
  dbfixtures, test.db.edits, tyControls.Edit, tyControls.ComboBox, tyControls.ListBox,
  tyControls.DB.Lists;

type
  TDBComboBoxTest = class(TDBControlTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure UserEdit; override;
    { Type-ahead: a letter picks the item it starts. }
    procedure UserEditUnguarded; override;
    procedure Commit; override;
    procedure AssertFieldHoldsEdit; override;
    function Combo: TTyDBComboBox;
    { The editable field of a csDropDown combo box: a child TTyEdit. }
    function Editor: TTyEdit;
    procedure EditorType(const S: string);
    { AKey to the editable field as a widgetset sends it. }
    procedure EditorKey(AKey: Word);
  published
    procedure TestTypingInTheEditableFieldEditsAtOnce;
    procedure TestEnterInTheEditableFieldWrites;
    procedure TestEscapeInTheEditableFieldCancels;
    procedure TestReadOnlyListPickIsUndone;
    procedure TestEscapeCancelsTheRecordThisControlStarted;
    procedure TestEscapeOnlyResetsWhenSomeoneElseStartedTheEdit;
    procedure TestChangeWhileTheControlIsReadIsNotAnEdit;
    procedure TestLeavingWritesThePick;
  end;

  TDBListBoxTest = class(TDBControlTestBase)
  protected
    FLastUser: Boolean;
    FSelectionEvents: Integer;
    procedure RecordSelection(Sender: TObject; AUser: Boolean);
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure UserEdit; override;
    procedure UserEditUnguarded; override;
    procedure Commit; override;
    procedure AssertFieldHoldsEdit; override;
    function List: TTyDBListBox;
  published
    procedure TestSelectionFromCodeIsNotAnEdit;
    procedure TestFieldTextInNoItemSelectsNothing;
    procedure TestRefusedPickIsUndoneAsTheProgramsSelection;
    procedure TestEnterWritesThePick;
  end;

  { What both lookup controls owe: the list from ListSource, the key written back, KeyValue,
    EmptyValue / DisplayEmpty, NullValueKey, a lookup table that changes, a lookup field. }
  TDBLookupTestBase = class(TDBControlTestBase)
  protected
    function NewControl: TControl; override;
    function NewLookupControl: TControl; virtual; abstract;
    function FieldName: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure AssertFieldHoldsEdit; override;
    function KeyValueOf: Variant; virtual; abstract;
    procedure SetKeyValueOf(const AValue: Variant); virtual; abstract;
    function ListItems: TStrings; virtual; abstract;
  published
    procedure TestPickIsWrittenAtOnce;
    procedure TestKeyValueOnAPlainList;
    procedure TestKeyValueOfTheBoundRow;
    procedure TestKeyValueFromCodeIsNotAnEdit;
    procedure TestEmptyValueAddsAFirstRow;
    procedure TestNullValueKeyClearsTheField;
    procedure TestNullValueKeyIsRefusedWhenNotEditable;
    procedure TestListFollowsTheLookupTable;
    procedure TestLookupFieldBringsItsOwnDefinition;
  end;

  TDBLookupComboBoxTest = class(TDBLookupTestBase)
  protected
    function NewLookupControl: TControl; override;
    function Shown: string; override;
    procedure UserEdit; override;
    procedure UserEditUnguarded; override;
    procedure Commit; override;
    function KeyValueOf: Variant; override;
    procedure SetKeyValueOf(const AValue: Variant); override;
    function ListItems: TStrings; override;
    function Combo: TTyDBLookupComboBox;
  published
    procedure TestDefaultStyleIsDropDownList;
  end;

  TDBLookupListBoxTest = class(TDBLookupTestBase)
  protected
    function NewLookupControl: TControl; override;
    function Shown: string; override;
    function EscapeRestores: Boolean; override;
    procedure UserEdit; override;
    procedure UserEditUnguarded; override;
    procedure Commit; override;
    function KeyValueOf: Variant; override;
    procedure SetKeyValueOf(const AValue: Variant); override;
    function ListItems: TStrings; override;
    function List: TTyDBLookupListBox;
  end;

implementation

type
  TListInput = class(TWinControl);
  TListComponent = class(TComponent);

procedure PutText(AFix: TDbFixture; const AName, AText: string);
begin
  AFix.DS.Edit;
  AFix.DS.FieldByName(AName).AsString := AText;
  AFix.DS.Post;
end;

{ ================================================================ TDBComboBoxTest ========= }

function TDBComboBoxTest.NewControl: TControl;
var
  c: TTyDBComboBox;
begin
  c := TTyDBComboBox.Create(FForm);
  c.Items.Add('alpha');
  c.Items.Add('beta');
  c.Items.Add('gamma');
  Result := c;
end;

function TDBComboBoxTest.Combo: TTyDBComboBox;
begin
  Result := TTyDBComboBox(FCtl);
end;

function TDBComboBoxTest.Editor: TTyEdit;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to Combo.ControlCount - 1 do
    if Combo.Controls[i] is TTyEdit then Exit(TTyEdit(Combo.Controls[i]));
  Fail('the combo box has no editable field');
end;

procedure TDBComboBoxTest.EditorType(const S: string);
var
  i: Integer;
  k: TUTF8Char;
begin
  for i := 1 to Length(S) do
  begin
    k := S[i];
    Editor.IntfUTF8KeyPress(k, 1, False);
  end;
end;

procedure TDBComboBoxTest.EditorKey(AKey: Word);
begin
  if Editor.Perform(CN_KEYDOWN, AKey, 0) = 0 then
    Editor.Perform(LM_KEYDOWN, AKey, 0);
end;

function TDBComboBoxTest.FieldName: string;
begin
  Result := 'Kind';
end;

function TDBComboBoxTest.Shown: string;
begin
  Result := Combo.Text;
end;

function TDBComboBoxTest.ExpectedShown(ARow: Integer): string;
begin
  if ARow <= 2 then Result := CFixKinds[ARow] else Result := '';
end;

function TDBComboBoxTest.OtherFieldName: string;
begin
  Result := 'Name';
end;

function TDBComboBoxTest.OtherShown: string;
begin
  Result := CFixNames[1];   // in no item: shown as the text it is
end;

procedure TDBComboBoxTest.UserEdit;
begin
  EnterControl;
  Key(VK_DOWN);
end;

procedure TDBComboBoxTest.UserEditUnguarded;
var
  c: TUTF8Char;
begin
  c := 'g';
  TListInput(FCtl).UTF8KeyPress(c);
end;

procedure TDBComboBoxTest.Commit;
begin
  Key(VK_RETURN);
end;

procedure TDBComboBoxTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field', 'beta', BoundField.AsString);
end;

{ D6: the editable field's typing reaches the combo box through Change, synchronously --
  not LCL's posted message. }
procedure TDBComboBoxTest.TestTypingInTheEditableFieldEditsAtOnce;
begin
  Combo.Style := csDropDown;
  Bind('Kind');
  AssertEquals('the editable field shows the field', 'alpha', Editor.Text);
  AssertBrowsing('bound');
  EditorType('z');
  AssertTrue('typed', Combo.Text <> 'alpha');
  AssertEquals('the combo box follows its field', Editor.Text, Combo.Text);
  AssertTrue('one key: dsEdit', FFix.DS.State = dsEdit);
  AssertTrue('the link is editing', Link.Editing);
end;

procedure TDBComboBoxTest.TestEnterInTheEditableFieldWrites;
var
  typed: string;
begin
  Combo.Style := csDropDown;
  Bind('Kind');
  EditorType('z');
  typed := Combo.Text;
  EditorKey(VK_RETURN);
  AssertEquals('Enter in the field writes it', typed, BoundField.AsString);
end;

procedure TDBComboBoxTest.TestEscapeInTheEditableFieldCancels;
begin
  Combo.Style := csDropDown;
  Bind('Kind');
  EditorType('z');
  AssertTrue('editing', FFix.DS.State = dsEdit);
  EditorKey(VK_ESCAPE);
  AssertEquals('the field shows the record again', 'alpha', Editor.Text);
  AssertEquals('and so does the combo box', 'alpha', Combo.Text);
  AssertBrowsing('Escape in the field');
  AssertEquals('nothing written', 'alpha', BoundField.AsString);
end;

{ V11 / D4: ReadOnly reaches only the editable field; a pick from the list must be undone. }
procedure TDBComboBoxTest.TestReadOnlyListPickIsUndone;
begin
  Bind('Kind');
  Combo.ReadOnly := True;
  EnterControl;
  Key(VK_DOWN);
  Key(VK_END);
  AssertEquals('the pick is undone', 'alpha', Combo.Text);
  AssertEquals('and the item with it', 0, Combo.ItemIndex);
  AssertBrowsing('picks in a read-only csDropDownList');
end;

{ The combo box put the record in dsEdit: Escape cancels all of it -- another field's change in
  the same edit goes too. }
procedure TDBComboBoxTest.TestEscapeCancelsTheRecordThisControlStarted;
begin
  Bind('Kind');
  EnterControl;
  Key(VK_DOWN);
  AssertTrue('editing', FFix.DS.State = dsEdit);
  FFix.DS.FieldByName('Name').AsString := 'Changed';
  Key(VK_ESCAPE);
  AssertEquals('the combo box', 'alpha', Combo.Text);
  AssertBrowsing('Escape after the combo box began the edit');
  AssertEquals('the whole record went back', CFixNames[1], FFix.DS.FieldByName('Name').AsString);
end;

{ Someone else put the record in dsEdit: Escape is this control's undo only. }
procedure TDBComboBoxTest.TestEscapeOnlyResetsWhenSomeoneElseStartedTheEdit;
begin
  Bind('Kind');
  FFix.DS.Edit;
  FFix.DS.FieldByName('Name').AsString := 'Changed';
  EnterControl;
  Key(VK_DOWN);
  AssertEquals('picked', 'beta', Combo.Text);
  Key(VK_ESCAPE);
  AssertEquals('the combo box went back', 'alpha', Combo.Text);
  AssertTrue('the record is still being edited', FFix.DS.State = dsEdit);
  AssertEquals('the other change stays', 'Changed', FFix.DS.FieldByName('Name').AsString);
  FFix.DS.Post;
  AssertEquals('and the pick was not written', 'alpha', BoundField.AsString);
end;

{ A form being read sets ItemIndex (and the base applies a waiting one in Loaded): the base
  fires Change for it, and it is not the user's. }
procedure TDBComboBoxTest.TestChangeWhileTheControlIsReadIsNotAnEdit;
begin
  Bind('Kind');
  TListComponent(FCtl).Loading;
  try
    Combo.ItemIndex := 2;
    AssertEquals('applied while loading', 'gamma', Combo.Text);
    AssertBrowsing('ItemIndex read from a form');
  finally
    TListComponent(FCtl).Loaded;
  end;
  AssertBrowsing('the control loaded');
end;

procedure TDBComboBoxTest.TestLeavingWritesThePick;
begin
  Bind('Kind');
  EnterControl;
  Key(VK_DOWN);
  LeaveControl;
  AssertEquals('written on leaving', 'beta', BoundField.AsString);
end;

{ ================================================================= TDBListBoxTest ========= }

procedure TDBListBoxTest.RecordSelection(Sender: TObject; AUser: Boolean);
begin
  FLastUser := AUser;
  Inc(FSelectionEvents);
end;

function TDBListBoxTest.NewControl: TControl;
var
  l: TTyDBListBox;
begin
  l := TTyDBListBox.Create(FForm);
  l.Items.Add('alpha');
  l.Items.Add('beta');
  l.Items.Add('gamma');
  Result := l;
end;

function TDBListBoxTest.List: TTyDBListBox;
begin
  Result := TTyDBListBox(FCtl);
end;

function TDBListBoxTest.FieldName: string;
begin
  Result := 'Kind';
end;

function TDBListBoxTest.Shown: string;
begin
  if List.ItemIndex >= 0 then Result := List.Items[List.ItemIndex] else Result := '';
end;

function TDBListBoxTest.ExpectedShown(ARow: Integer): string;
begin
  if ARow <= 2 then Result := CFixKinds[ARow] else Result := '';
end;

function TDBListBoxTest.OtherFieldName: string;
begin
  Result := 'Name';
end;

function TDBListBoxTest.OtherShown: string;
begin
  Result := '';   // 'Alice' is no item
end;

procedure TDBListBoxTest.UserEdit;
begin
  EnterControl;
  Key(VK_DOWN);
end;

procedure TDBListBoxTest.UserEditUnguarded;
begin
  Key(VK_END);
end;

procedure TDBListBoxTest.Commit;
begin
  LeaveControl;
end;

procedure TDBListBoxTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field', 'beta', BoundField.AsString);
end;

procedure TDBListBoxTest.TestSelectionFromCodeIsNotAnEdit;
begin
  Bind('Kind');
  List.ItemIndex := 2;
  AssertEquals('selected', 'gamma', Shown);
  AssertBrowsing('ItemIndex from code');
end;

procedure TDBListBoxTest.TestFieldTextInNoItemSelectsNothing;
begin
  Bind('Kind');
  PutText(FFix, 'Kind', 'zeta');
  AssertEquals('nothing selected', -1, List.ItemIndex);
  AssertBrowsing('a value in no item');
end;

{ The refused pick is undone inside the user's key handler; the undo is the program's, and
  OnSelectionChange must say so (LCL's User flag). }
procedure TDBListBoxTest.TestRefusedPickIsUndoneAsTheProgramsSelection;
begin
  FFix.Src.AutoEdit := False;
  Bind('Kind');
  List.OnSelectionChange := @RecordSelection;
  EnterControl;
  Key(VK_DOWN);
  AssertEquals('undone', 'alpha', Shown);
  AssertEquals('the move and its undo', 2, FSelectionEvents);
  AssertFalse('the undo is not reported as the user''s', FLastUser);
  AssertBrowsing('a refused pick');
end;

procedure TDBListBoxTest.TestEnterWritesThePick;
begin
  Bind('Kind');
  EnterControl;
  Key(VK_DOWN);
  Key(VK_RETURN);
  AssertEquals('written on Enter', 'beta', BoundField.AsString);
end;

{ ============================================================== TDBLookupTestBase ========= }

function TDBLookupTestBase.NewControl: TControl;
begin
  Result := NewLookupControl;
  SetObjectProp(Result, 'ListSource', FFix.CitySrc);
  SetStrProp(Result, 'KeyField', 'ID');
  SetStrProp(Result, 'ListField', 'Name');
end;

function TDBLookupTestBase.FieldName: string;
begin
  Result := 'CityID';
end;

function TDBLookupTestBase.ExpectedShown(ARow: Integer): string;
begin
  if ARow <= 2 then Result := CFixCityNames[CFixCityIDs[ARow]] else Result := '';
end;

function TDBLookupTestBase.OtherFieldName: string;
begin
  Result := 'Qty';
end;

function TDBLookupTestBase.OtherShown: string;
begin
  Result := '';   // 7 is no city's ID
end;

procedure TDBLookupTestBase.AssertFieldHoldsEdit;
begin
  AssertEquals('the key of the picked row', 2, BoundField.AsInteger);
end;

procedure TDBLookupTestBase.TestPickIsWrittenAtOnce;
begin
  Bind('CityID');
  UserEdit;
  AssertEquals('picked', 'Tokyo', Shown);
  AssertTrue('editing', FFix.DS.State = dsEdit);
  AssertEquals('the key is in the record already', 2, BoundField.AsInteger);
end;

procedure TDBLookupTestBase.TestKeyValueOnAPlainList;
begin
  AssertEquals('the list without a DataSource', 3, ListItems.Count);
  SetKeyValueOf(3);
  AssertEquals('the row with key 3', 'Lima', Shown);
  AssertEquals('read back', 3, Integer(KeyValueOf));
  SetKeyValueOf(Null);
  AssertEquals('no key, no row', '', Shown);
end;

procedure TDBLookupTestBase.TestKeyValueOfTheBoundRow;
begin
  Bind('CityID');
  AssertEquals('row 1', 1, Integer(KeyValueOf));
  GoRow(2);
  AssertEquals('row 2', 3, Integer(KeyValueOf));
  GoRow(3);
  AssertTrue('the NULL row: no key', VarIsNull(KeyValueOf));
end;

procedure TDBLookupTestBase.TestKeyValueFromCodeIsNotAnEdit;
begin
  Bind('CityID');
  SetKeyValueOf(2);
  AssertEquals('selected', 'Tokyo', Shown);
  AssertBrowsing('KeyValue from code');
  AssertEquals('the field keeps its key', 1, BoundField.AsInteger);
end;

procedure TDBLookupTestBase.TestEmptyValueAddsAFirstRow;
begin
  SetStrProp(FCtl, 'EmptyValue', '-1');
  SetStrProp(FCtl, 'DisplayEmpty', '(none)');
  AssertEquals('one more row', 4, ListItems.Count);
  AssertEquals('first, the empty row', '(none)', ListItems[0]);
  Bind('CityID');
  AssertEquals('row 1', 'Paris', Shown);
  EnterControl;
  Key(VK_HOME);
  AssertEquals('the empty row picked', '(none)', Shown);
  AssertEquals('its value written', -1, BoundField.AsInteger);
end;

{ LCL's TDBLookup.HandleNullKey is private; the controls have their own. }
procedure TDBLookupTestBase.TestNullValueKeyClearsTheField;
begin
  SetOrdProp(FCtl, 'NullValueKey', KeyToShortCut(VK_DELETE, []));
  Bind('CityID');
  EnterControl;
  Key(VK_DELETE);
  AssertTrue('NULL', BoundField.IsNull);
  AssertEquals('nothing shown', '', Shown);
  Key(VK_DELETE, [ssCtrl]);   // not the shortcut: no harm done, nothing more cleared
  AssertTrue('still NULL', BoundField.IsNull);
end;

procedure TDBLookupTestBase.TestNullValueKeyIsRefusedWhenNotEditable;
begin
  FFix.Src.AutoEdit := False;
  SetOrdProp(FCtl, 'NullValueKey', KeyToShortCut(VK_DELETE, []));
  Bind('CityID');
  EnterControl;
  Key(VK_DELETE);
  AssertFalse('not cleared', BoundField.IsNull);
  AssertEquals('still Paris', 'Paris', Shown);
  AssertBrowsing('a refused NullValueKey');
end;

{ TDBLookup's DatasetChange: the list is the table's, kept in step. }
procedure TDBLookupTestBase.TestListFollowsTheLookupTable;
begin
  Bind('CityID');
  FFix.Cities.AppendRecord([4, 'Oslo']);
  AssertEquals('a row added', 4, ListItems.Count);
  AssertTrue('Oslo listed', ListItems.IndexOf('Oslo') >= 0);
  AssertEquals('row 1 still shown', 'Paris', Shown);
  AssertTrue('Oslo found', FFix.Cities.Locate('ID', 4, []));
  FFix.Cities.Delete;
  AssertEquals('a row deleted', 3, ListItems.Count);
  AssertEquals('Oslo gone', -1, ListItems.IndexOf('Oslo'));
end;

{ A lookup field brings its own LookupDataSet / LookupKeyFields / LookupResultField; the pick
  writes its key field. }
procedure TDBLookupTestBase.TestLookupFieldBringsItsOwnDefinition;
var
  ds: TBufDataset;
  src: TDataSource;
  f: TField;
begin
  ds := TBufDataset.Create(nil);
  src := TDataSource.Create(nil);
  try
    f := TIntegerField.Create(ds);
    f.FieldName := 'ID';
    f.DataSet := ds;
    f := TIntegerField.Create(ds);
    f.FieldName := 'CityID';
    f.DataSet := ds;
    f := TStringField.Create(ds);
    f.FieldName := 'City';
    f.Size := 20;
    f.FieldKind := fkLookup;
    f.KeyFields := 'CityID';
    f.LookupDataSet := FFix.Cities;
    f.LookupKeyFields := 'ID';
    f.LookupResultField := 'Name';
    f.DataSet := ds;
    ds.CreateDataset;
    ds.AppendRecord([1, 2]);
    ds.First;
    src.DataSet := ds;
    SetObjectProp(FCtl, 'ListSource', nil);
    SetStrProp(FCtl, 'KeyField', '');
    SetStrProp(FCtl, 'ListField', '');
    SetStrProp(FCtl, 'DataField', 'City');
    SetObjectProp(FCtl, 'DataSource', src);
    AssertEquals('the cities, from the field''s LookupDataSet', 3, ListItems.Count);
    AssertEquals('the row of key 2', 'Tokyo', Shown);
    EnterControl;
    Key(VK_DOWN);
    AssertEquals('picked', 'Lima', Shown);
    AssertEquals('the key field written', 3, ds.FieldByName('CityID').AsInteger);
    ds.Post;
    AssertEquals('and the lookup field follows', 'Lima', ds.FieldByName('City').AsString);
  finally
    SetObjectProp(FCtl, 'DataSource', nil);
    src.Free;
    ds.Free;
  end;
end;

{ ========================================================= TDBLookupComboBoxTest ========= }

function TDBLookupComboBoxTest.NewLookupControl: TControl;
begin
  Result := TTyDBLookupComboBox.Create(FForm);
end;

function TDBLookupComboBoxTest.Combo: TTyDBLookupComboBox;
begin
  Result := TTyDBLookupComboBox(FCtl);
end;

function TDBLookupComboBoxTest.Shown: string;
begin
  Result := Combo.Text;
end;

procedure TDBLookupComboBoxTest.UserEdit;
begin
  EnterControl;
  Key(VK_DOWN);
end;

procedure TDBLookupComboBoxTest.UserEditUnguarded;
var
  c: TUTF8Char;
begin
  c := 'L';
  TListInput(FCtl).UTF8KeyPress(c);
end;

procedure TDBLookupComboBoxTest.Commit;
begin
  Key(VK_RETURN);
end;

function TDBLookupComboBoxTest.KeyValueOf: Variant;
begin
  Result := Combo.KeyValue;
end;

procedure TDBLookupComboBoxTest.SetKeyValueOf(const AValue: Variant);
begin
  Combo.KeyValue := AValue;
end;

function TDBLookupComboBoxTest.ListItems: TStrings;
begin
  Result := Combo.Items;
end;

{ D6 / D10: LCL's lookup combo box defaults to csDropDown; a lookup holds only list values. }
procedure TDBLookupComboBoxTest.TestDefaultStyleIsDropDownList;
begin
  AssertTrue('csDropDownList', Combo.Style = csDropDownList);
  AssertEquals('the declared default, so a form file leaves it out', Ord(csDropDownList),
    GetPropInfo(Combo, 'Style')^.Default);
end;

{ ========================================================== TDBLookupListBoxTest ========= }

function TDBLookupListBoxTest.NewLookupControl: TControl;
begin
  Result := TTyDBLookupListBox.Create(FForm);
end;

function TDBLookupListBoxTest.List: TTyDBLookupListBox;
begin
  Result := TTyDBLookupListBox(FCtl);
end;

function TDBLookupListBoxTest.Shown: string;
begin
  if List.ItemIndex >= 0 then Result := List.Items[List.ItemIndex] else Result := '';
end;

function TDBLookupListBoxTest.EscapeRestores: Boolean;
begin
  Result := False;   // the pick is in the record already, as in LCL's TDBLookupListBox
end;

procedure TDBLookupListBoxTest.UserEdit;
begin
  EnterControl;
  Key(VK_DOWN);
end;

procedure TDBLookupListBoxTest.UserEditUnguarded;
begin
  Key(VK_END);
end;

procedure TDBLookupListBoxTest.Commit;
begin
  { Nothing: the pick is written as it is made. }
end;

function TDBLookupListBoxTest.KeyValueOf: Variant;
begin
  Result := List.KeyValue;
end;

procedure TDBLookupListBoxTest.SetKeyValueOf(const AValue: Variant);
begin
  List.KeyValue := AValue;
end;

function TDBLookupListBoxTest.ListItems: TStrings;
begin
  Result := List.Items;
end;

initialization
  RegisterTest(TDBComboBoxTest);
  RegisterTest(TDBListBoxTest);
  RegisterTest(TDBLookupComboBoxTest);
  RegisterTest(TDBLookupListBoxTest);
end.
