unit test.db.edits;
{$mode objfpc}{$H+}

{ The data-aware text controls (issue #34, plan Task 3): TTyDBEdit, TTyDBMaskEdit, TTyDBMemo and
  TTyDBText.

  TDBControlTestBase runs the eight criteria every data-aware control owes (plan C1-C8) against
  whatever control a subclass builds: the subclass says which field it binds, what the control
  shows for each fixture row, how a USER changes it and how the user finishes. Every subclass
  registered runs the whole set, so a control cannot pass by having been left out of one. The
  numeric suite (test.db.numeric) derives from the same base.

  Every change is made the way a user makes it -- focus arriving (DoEnter), keys (KeyDown /
  UTF8KeyPress), Enter, focus leaving (DoExit), EditingDone -- never by writing the control's
  Text: a write from code is exactly what a control must NOT mistake for the user, so it cannot
  stand in for one. The control-specific tests follow the base. }

interface

uses
  Classes, SysUtils, Controls, Forms, LCLType, LMessages, DB, DBCtrls, TypInfo,
  fpcunit, testregistry,
  dbfixtures, tyControls.DB.Edits;

type
  { Protected input methods, reached the way the widgetset reaches them. }
  TInputAccess = class(TWinControl);

  { The clipboard a paste reads, without the system's. }
  TProbeDBEdit = class(TTyDBEdit)
  protected
    function ReadClipboardText: string; override;
  public
    Clip: string;
  end;

  TProbeDBMaskEdit = class(TTyDBMaskEdit)
  protected
    function ReadClipboardText: string; override;
  public
    Clip: string;
  end;

  TProbeDBMemo = class(TTyDBMemo)
  protected
    function ReadClipboardText: string; override;
  public
    Clip: string;
  end;

  TDBControlTestBase = class(TTestCase)
  protected
    FForm: TForm;
    FFix: TDbFixture;
    FCtl: TControl;
    procedure SetUp; override;
    procedure TearDown; override;
    { --- what a subclass says about its control --- }
    function NewControl: TControl; virtual; abstract;
    function FieldName: string; virtual; abstract;
    { What the control shows now, and what it should show for fixture row 1, 2 or 3 (3: every
      field NULL) while it does not have focus. }
    function Shown: string; virtual; abstract;
    function ExpectedShown(ARow: Integer): string; virtual; abstract;
    { The same while it has focus (an edit shows Field.Text then). Default: ExpectedShown. }
    function ExpectedFocused(ARow: Integer): string; virtual;
    { A second field of row 1 and what the control shows for it (C7: a new DataField). }
    function OtherFieldName: string; virtual; abstract;
    function OtherShown: string; virtual; abstract;
    { False for a control the user cannot change (TTyDBText): C3-C6 do not apply. }
    function Editable: Boolean; virtual;
    { What the control shows with no field at all. Default: what it shows for NULL (row 3) --
      not so for a check box, which shows NULL grayed and no field unchecked, as LCL's does. }
    function ExpectedUnbound: string; virtual;
    { False for a choice, which writes its value into the record the moment it is made: there
      Escape has nothing to take back, and C5 checks that it takes nothing. }
    function EscapeRestores: Boolean; virtual;
    { The user, on row 1: focus the control and change its value by keys or clicks. }
    procedure UserEdit; virtual; abstract;
    { A change no key gate sees -- a paste. Default: none. }
    procedure UserEditUnguarded; virtual;
    { The user finishing: Enter, EditingDone or leaving the control. }
    procedure Commit; virtual; abstract;
    { The field holds what UserEdit typed, compared as its type (AsFloat, AsInteger...). }
    procedure AssertFieldHoldsEdit; virtual; abstract;
    { --- helpers --- }
    procedure Bind(const AField: string);
    procedure SetControlReadOnly(AValue: Boolean);
    function ControlDataSource: TObject;
    procedure GoRow(ARow: Integer);
    function Link: TFieldDataLink;
    function BoundField: TField;
    procedure Key(AKey: Word; AShift: TShiftState = []);
    procedure TypeText(const S: string);
    procedure EnterControl;
    procedure LeaveControl;
    procedure AssertBrowsing(const AWhen: string);
    procedure AssertRefused(const AWhen, AFieldBefore: string);
  published
    procedure TestC1ShowsTheRowItIsOn;
    procedure TestC2LoadingNeverEdits;
    procedure TestC3UserEditEditsAndMarksModified;
    procedure TestC4CommitWritesTheValue;
    procedure TestC5EscapeBringsTheFieldBack;
    procedure TestC6ReadOnlyControlRefusesTheEdit;
    procedure TestC6ReadOnlyFieldRefusesTheEdit;
    procedure TestC6NoAutoEditRefusesTheEdit;
    procedure TestC7FreedDataSourceLeavesNoDanglingLink;
    procedure TestC7DataSourceRemovedFromItsOwnerUnbinds;
    procedure TestC7NewDataFieldIsLoaded;
    procedure TestC8GetDataLinkAnswersTheLink;
  end;

  TDBEditTest = class(TDBControlTestBase)
  protected
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
    function Ed: TProbeDBEdit;
  published
    procedure TestFocusShowsFieldTextAndBlurShowsDisplayText;
    procedure TestStringFieldSetsMaxLength;
    procedure TestAuthorsMaxLengthIsKept;
    procedure TestFieldAlignmentIsCopied;
    procedure TestTypingEditsBeforeTheKeyLands;
    procedure TestCharacterTheFieldRefusesNeverLands;
    procedure TestBackspaceRefusedWhenNotEditable;
    procedure TestPasteRefusedWhenFieldIsReadOnly;
    procedure TestEmptyTextWritesNullToANumberField;
  end;

  TDBMaskEditTest = class(TDBControlTestBase)
  protected
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
    function Ed: TProbeDBMaskEdit;
    procedure PutKind(const AValue: string);
  published
    procedure TestFieldEditMaskIsApplied;
    procedure TestMaskedEditWritesTheMaskedValue;
    procedure TestHashMaskIsNotAppliedAndDoesNotRaise;
    procedure TestCustomEditMaskKeepsTheControlsMask;
    procedure TestChangingTheMaskKeepsShowingTheField;
  end;

  TDBMemoTest = class(TDBControlTestBase)
  protected
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
    function Memo: TProbeDBMemo;
  published
    procedure TestAutoDisplayOffShowsTheLabelUntilEnter;
    procedure TestNothingIsTypedIntoTheUnloadedLabel;
    procedure TestLinesAddIsNotAnEdit;
    procedure TestNonBlobFieldShowsDisplayTextUnfocused;
  end;

  TDBTextTest = class(TDBControlTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    function Editable: Boolean; override;
    procedure UserEdit; override;
    procedure Commit; override;
    procedure AssertFieldHoldsEdit; override;
    function Lbl: TTyDBText;
  published
    procedure TestUnboundIsEmptyAtRunTime;
    procedure TestUnboundShowsItsNameInTheDesigner;
    procedure TestShowsDisplayText;
  end;

  TComponentAccess = class(TComponent);

{ The form test controls sit on needs the widgetset once (as test.corehooks does). }
procedure NeedDBWidgetSet;

implementation

var
  WidgetSetReady: Boolean = False;

procedure NeedDBWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

function TProbeDBEdit.ReadClipboardText: string;
begin
  Result := Clip;
end;

function TProbeDBMaskEdit.ReadClipboardText: string;
begin
  Result := Clip;
end;

function TProbeDBMemo.ReadClipboardText: string;
begin
  Result := Clip;
end;

{ ============================================================== TDBControlTestBase ======== }

procedure TDBControlTestBase.SetUp;
begin
  NeedDBWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FFix := NewDbFixture(nil);
  FCtl := NewControl;
  FCtl.Parent := FForm;
  FCtl.SetBounds(8, 8, 200, 60);
end;

procedure TDBControlTestBase.TearDown;
begin
  FreeAndNil(FForm);   // the control first: it is bound to the fixture's data source
  FreeAndNil(FFix);
end;

function TDBControlTestBase.ExpectedFocused(ARow: Integer): string;
begin
  Result := ExpectedShown(ARow);
end;

function TDBControlTestBase.Editable: Boolean;
begin
  Result := True;
end;

function TDBControlTestBase.ExpectedUnbound: string;
begin
  Result := ExpectedShown(3);
end;

function TDBControlTestBase.EscapeRestores: Boolean;
begin
  Result := True;
end;

procedure TDBControlTestBase.UserEditUnguarded;
begin
end;

procedure TDBControlTestBase.Bind(const AField: string);
begin
  SetStrProp(FCtl, 'DataField', AField);
  SetObjectProp(FCtl, 'DataSource', FFix.Src);
end;

procedure TDBControlTestBase.SetControlReadOnly(AValue: Boolean);
begin
  SetOrdProp(FCtl, 'ReadOnly', Ord(AValue));
end;

function TDBControlTestBase.ControlDataSource: TObject;
begin
  Result := GetObjectProp(FCtl, 'DataSource');
end;

procedure TDBControlTestBase.GoRow(ARow: Integer);
begin
  AssertTrue('row ' + IntToStr(ARow) + ' found', FFix.DS.Locate('ID', ARow, []));
end;

function TDBControlTestBase.Link: TFieldDataLink;
begin
  Result := TFieldDataLink(PtrUInt(FCtl.Perform(CM_GETDATALINK, 0, 0)));
  AssertNotNull('CM_GETDATALINK answers a link', Result);
end;

function TDBControlTestBase.BoundField: TField;
begin
  Result := FFix.DS.FieldByName(FieldName);
end;

procedure TDBControlTestBase.Key(AKey: Word; AShift: TShiftState);
var
  k: Word;
begin
  k := AKey;
  TInputAccess(FCtl).KeyDown(k, AShift);
end;

procedure TDBControlTestBase.TypeText(const S: string);
var
  i: Integer;
  c: TUTF8Char;
begin
  for i := 1 to Length(S) do
  begin
    c := S[i];
    TInputAccess(FCtl).UTF8KeyPress(c);
  end;
end;

procedure TDBControlTestBase.EnterControl;
begin
  TInputAccess(FCtl).DoEnter;
end;

procedure TDBControlTestBase.LeaveControl;
begin
  TInputAccess(FCtl).DoExit;
end;

procedure TDBControlTestBase.AssertBrowsing(const AWhen: string);
begin
  AssertTrue(AWhen + ': the dataset stays in dsBrowse', FFix.DS.State = dsBrowse);
  AssertFalse(AWhen + ': the link is not editing', Link.Editing);
end;

procedure TDBControlTestBase.AssertRefused(const AWhen, AFieldBefore: string);
begin
  AssertBrowsing(AWhen);
  AssertEquals(AWhen + ': the control shows the field', ExpectedFocused(1), Shown);
  AssertEquals(AWhen + ': the field is untouched', AFieldBefore, BoundField.AsString);
end;

{ C1 }
procedure TDBControlTestBase.TestC1ShowsTheRowItIsOn;
var
  r: Integer;
begin
  Bind(FieldName);
  for r := 1 to 3 do
  begin
    GoRow(r);
    AssertEquals('row ' + IntToStr(r), ExpectedShown(r), Shown);
  end;
  GoRow(1);   // and back: row 3's empty display is not where it stays
  AssertEquals('row 1 again', ExpectedShown(1), Shown);
end;

{ C2. Each step below reloads the control, and each load fires the control's change
  notification; the display is checked after each so a load that did not happen cannot pass
  as one that did not edit. }
procedure TDBControlTestBase.TestC2LoadingNeverEdits;
begin
  Bind(FieldName);
  AssertEquals('bound', ExpectedShown(1), Shown);
  AssertBrowsing('binding');
  GoRow(2);
  AssertEquals('row 2', ExpectedShown(2), Shown);
  AssertBrowsing('moving to row 2');
  GoRow(3);
  AssertEquals('row 3', ExpectedShown(3), Shown);
  AssertBrowsing('moving to the NULL row');
  GoRow(1);
  { What Refresh announces to the controls (deDataSetChange). Not Refresh itself: a TBufDataset
    with no database behind it refreshes only after MergeChangeLog, and then reads its blob
    fields back as garbage. }
  FFix.DS.Resync([]);
  AssertEquals('resynced', ExpectedShown(1), Shown);
  AssertBrowsing('Resync');
  if FCtl is TWinControl then
  begin
    EnterControl;
    AssertBrowsing('focus arriving');
    LeaveControl;
    AssertBrowsing('focus leaving');
    AssertEquals('after a focus round trip', ExpectedShown(1), Shown);
  end;
end;

{ C3. The modified mark is what makes a Post made ELSEWHERE write the control's value. }
procedure TDBControlTestBase.TestC3UserEditEditsAndMarksModified;
begin
  if not Editable then
  begin
    AssertFalse('takes no input, so C3-C6 do not apply', FCtl is TWinControl);
    Exit;
  end;
  Bind(FieldName);
  UserEdit;
  AssertTrue('the user''s change put the dataset in dsEdit', FFix.DS.State = dsEdit);
  AssertTrue('the link is editing', Link.Editing);
  FFix.DS.Post;
  AssertFieldHoldsEdit;
end;

{ C4 }
procedure TDBControlTestBase.TestC4CommitWritesTheValue;
begin
  if not Editable then
  begin
    AssertFalse('takes no input, so C3-C6 do not apply', FCtl is TWinControl);
    Exit;
  end;
  Bind(FieldName);
  UserEdit;
  Commit;
  AssertFieldHoldsEdit;
  FFix.DS.Post;
  AssertFieldHoldsEdit;
end;

{ C5 }
procedure TDBControlTestBase.TestC5EscapeBringsTheFieldBack;
var
  before: string;
begin
  if not Editable then
  begin
    AssertFalse('takes no input, so C3-C6 do not apply', FCtl is TWinControl);
    Exit;
  end;
  Bind(FieldName);
  before := BoundField.AsString;
  UserEdit;
  AssertTrue('the edit took', Shown <> ExpectedFocused(1));
  if not EscapeRestores then
  begin
    Key(VK_ESCAPE);
    AssertFieldHoldsEdit;   // a choice is in the record already; Escape is not its undo
    Exit;
  end;
  Key(VK_ESCAPE);
  AssertEquals('Escape shows the field again', ExpectedFocused(1), Shown);
  FFix.DS.Post;
  AssertEquals('and nothing is written', before, BoundField.AsString);
end;

{ C6 }
procedure TDBControlTestBase.TestC6ReadOnlyControlRefusesTheEdit;
var
  before: string;
begin
  if not Editable then
  begin
    AssertFalse('takes no input, so C3-C6 do not apply', FCtl is TWinControl);
    Exit;
  end;
  Bind(FieldName);
  SetControlReadOnly(True);
  before := BoundField.AsString;
  UserEdit;
  AssertRefused('read-only control, keys', before);
  UserEditUnguarded;
  AssertRefused('read-only control, paste', before);
end;

procedure TDBControlTestBase.TestC6ReadOnlyFieldRefusesTheEdit;
var
  before: string;
begin
  if not Editable then
  begin
    AssertFalse('takes no input, so C3-C6 do not apply', FCtl is TWinControl);
    Exit;
  end;
  BoundField.ReadOnly := True;
  Bind(FieldName);
  before := BoundField.AsString;
  UserEdit;
  AssertRefused('read-only field, keys', before);
  UserEditUnguarded;
  AssertRefused('read-only field, paste', before);
end;

procedure TDBControlTestBase.TestC6NoAutoEditRefusesTheEdit;
var
  before: string;
begin
  if not Editable then
  begin
    AssertFalse('takes no input, so C3-C6 do not apply', FCtl is TWinControl);
    Exit;
  end;
  FFix.Src.AutoEdit := False;
  Bind(FieldName);
  before := BoundField.AsString;
  UserEdit;
  AssertRefused('AutoEdit off, keys', before);
  UserEditUnguarded;
  AssertRefused('AutoEdit off, paste', before);
end;

{ C7. TDataSource.Destroy unhooks its links itself, so here the control has to survive the
  data source going and keep working unbound. }
procedure TDBControlTestBase.TestC7FreedDataSourceLeavesNoDanglingLink;
begin
  Bind(FieldName);
  FFix.Src.Free;
  AssertNull('DataSource', ControlDataSource);
  AssertEquals('an unbound control is empty', ExpectedUnbound, Shown);
  if FCtl is TWinControl then
  begin
    EnterControl;
    TypeText('1');
    Key(VK_BACK);
    Key(VK_ESCAPE);
    FCtl.EditingDone;
    LeaveControl;
  end;
  AssertNull('still unbound', ControlDataSource);
end;

{ The other way a data source goes away: its owner lets it go (RemoveComponent, which is what
  moving it to another owner does). The owner tells its other components (opRemove), and a
  control on the same owner must let go of it too, as LCL's do. }
procedure TDBControlTestBase.TestC7DataSourceRemovedFromItsOwnerUnbinds;
var
  src: TDataSource;
begin
  src := TDataSource.Create(FForm);   // owned like the control
  try
    src.DataSet := FFix.DS;
    SetStrProp(FCtl, 'DataField', FieldName);
    SetObjectProp(FCtl, 'DataSource', src);
    AssertEquals('bound', ExpectedShown(1), Shown);
    FForm.RemoveComponent(src);
    AssertNull('DataSource after opRemove', ControlDataSource);
    AssertEquals('unbound, empty', ExpectedUnbound, Shown);
  finally
    src.Free;
  end;
end;

procedure TDBControlTestBase.TestC7NewDataFieldIsLoaded;
begin
  Bind(FieldName);
  AssertEquals('first field', ExpectedShown(1), Shown);
  SetStrProp(FCtl, 'DataField', OtherFieldName);
  AssertEquals('the new field', OtherShown, Shown);
  AssertBrowsing('changing DataField');
end;

{ C8: what a DB grid or navigator asks a control for (LCL's protocol). }
procedure TDBControlTestBase.TestC8GetDataLinkAnswersTheLink;
var
  p: PtrInt;
begin
  Bind(FieldName);
  p := FCtl.Perform(CM_GETDATALINK, 0, 0);
  AssertTrue('a link', p <> 0);
  AssertTrue('a field data link', TObject(PtrUInt(p)) is TFieldDataLink);
  AssertSame('the link is this control''s', FCtl, TFieldDataLink(PtrUInt(p)).Control);
  AssertSame('bound to the field', BoundField, TFieldDataLink(PtrUInt(p)).Field);
end;

{ ====================================================================== TDBEditTest ======= }

function TDBEditTest.NewControl: TControl;
begin
  Result := TProbeDBEdit.Create(FForm);
end;

function TDBEditTest.Ed: TProbeDBEdit;
begin
  Result := TProbeDBEdit(FCtl);
end;

function TDBEditTest.FieldName: string;
begin
  Result := 'Name';
end;

function TDBEditTest.Shown: string;
begin
  Result := Ed.Text;
end;

function TDBEditTest.ExpectedShown(ARow: Integer): string;
begin
  if ARow <= 2 then Result := CFixNames[ARow] else Result := '';
end;

function TDBEditTest.OtherFieldName: string;
begin
  Result := 'Kind';
end;

function TDBEditTest.OtherShown: string;
begin
  Result := CFixKinds[1];
end;

procedure TDBEditTest.UserEdit;
begin
  EnterControl;
  Key(VK_A, [ssCtrl]);
  TypeText('Zed');
end;

procedure TDBEditTest.UserEditUnguarded;
begin
  Ed.Clip := 'Pasted';
  Key(VK_A, [ssCtrl]);
  Key(VK_V, [ssCtrl]);
end;

procedure TDBEditTest.Commit;
begin
  Key(VK_RETURN);
end;

procedure TDBEditTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field', 'Zed', BoundField.AsString);
end;

{ LCL's rule: the editable form while focused (Field.Text), the formatted one otherwise. }
procedure TDBEditTest.TestFocusShowsFieldTextAndBlurShowsDisplayText;
var
  saved: TFormatSettings;
begin
  saved := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := '.';
    { FCL's Field.Text uses DisplayFormat too when there is no EditFormat, so both are set:
      the two forms have to differ for the test to say which one is shown. }
    TFloatField(FFix.DS.FieldByName('Amount')).DisplayFormat := '0.00 元';
    TFloatField(FFix.DS.FieldByName('Amount')).EditFormat := '0.##';
    Bind('Amount');
    AssertEquals('unfocused', '12.50 元', Ed.Text);
    EnterControl;
    AssertEquals('focused', '12.5', Ed.Text);
    LeaveControl;
    AssertEquals('unfocused again', '12.50 元', Ed.Text);
    AssertBrowsing('a focus round trip');
  finally
    DefaultFormatSettings := saved;
  end;
end;

procedure TDBEditTest.TestStringFieldSetsMaxLength;
begin
  Bind('Name');
  AssertEquals('ftString(40)', 40, Ed.MaxLength);
  SetStrProp(FCtl, 'DataField', 'Kind');
  AssertEquals('ftString(10): the field''s size follows the field', 10, Ed.MaxLength);
  SetStrProp(FCtl, 'DataField', 'Amount');
  AssertEquals('a number field sets no limit, and leaves none behind', 0, Ed.MaxLength);
end;

procedure TDBEditTest.TestAuthorsMaxLengthIsKept;
begin
  Ed.MaxLength := 5;
  Bind('Name');
  AssertEquals('the author''s limit', 5, Ed.MaxLength);
  SetStrProp(FCtl, 'DataField', 'Amount');
  AssertEquals('still the author''s', 5, Ed.MaxLength);
end;

procedure TDBEditTest.TestFieldAlignmentIsCopied;
begin
  FFix.DS.FieldByName('Name').Alignment := taRightJustify;
  Bind('Name');
  AssertTrue('right-justified like the field', Ed.Alignment = taRightJustify);
end;

{ LCL's order: the dataset goes into dsEdit BEFORE the character lands -- a key is never typed
  into a record that then turns out not to be editable. }
procedure TDBEditTest.TestTypingEditsBeforeTheKeyLands;
begin
  Bind('Name');
  EnterControl;
  AssertBrowsing('focused, nothing typed');
  TypeText('x');
  AssertTrue('one key: dsEdit', FFix.DS.State = dsEdit);
  AssertEquals('and the key landed (it replaced the auto-selection)', 'x', Ed.Text);
end;

{ A letter in an integer field: the field refuses it (IsValidChar), so it never reaches the
  text -- and the record is not put in edit mode for a key that does nothing. }
procedure TDBEditTest.TestCharacterTheFieldRefusesNeverLands;
begin
  Bind('Qty');
  EnterControl;
  Ed.SelStart := Length(Ed.Text);
  TypeText('a');
  AssertEquals('the text', IntToStr(CFixQtys[1]), Ed.Text);
  AssertBrowsing('a refused letter');
  TypeText('5');
  AssertEquals('a digit lands', IntToStr(CFixQtys[1]) + '5', Ed.Text);
end;

procedure TDBEditTest.TestBackspaceRefusedWhenNotEditable;
begin
  FFix.Src.AutoEdit := False;
  Bind('Name');
  EnterControl;
  Ed.SelStart := Length(Ed.Text);
  Key(VK_BACK);
  AssertEquals('Backspace did nothing', CFixNames[1], Ed.Text);
  AssertBrowsing('Backspace without AutoEdit');
end;

procedure TDBEditTest.TestPasteRefusedWhenFieldIsReadOnly;
begin
  FFix.DS.FieldByName('Name').ReadOnly := True;
  Bind('Name');
  EnterControl;
  Ed.Clip := 'Pasted';
  Key(VK_V, [ssCtrl]);
  AssertEquals('the paste is undone', CFixNames[1], Ed.Text);
  AssertBrowsing('pasting into a read-only field');
end;

{ D5: an emptied edit writes Field.Text := '', which a number field takes as NULL. }
procedure TDBEditTest.TestEmptyTextWritesNullToANumberField;
begin
  Bind('Qty');
  EnterControl;
  Key(VK_A, [ssCtrl]);
  Key(VK_BACK);
  AssertEquals('emptied', '', Ed.Text);
  Commit;
  AssertTrue('NULL', FFix.DS.FieldByName('Qty').IsNull);
end;

{ ================================================================== TDBMaskEditTest ======= }

function TDBMaskEditTest.NewControl: TControl;
begin
  Result := TProbeDBMaskEdit.Create(FForm);
end;

function TDBMaskEditTest.Ed: TProbeDBMaskEdit;
begin
  Result := TProbeDBMaskEdit(FCtl);
end;

function TDBMaskEditTest.FieldName: string;
begin
  Result := 'Name';
end;

function TDBMaskEditTest.Shown: string;
begin
  Result := Ed.Text;
end;

function TDBMaskEditTest.ExpectedShown(ARow: Integer): string;
begin
  if ARow <= 2 then Result := CFixNames[ARow] else Result := '';
end;

function TDBMaskEditTest.OtherFieldName: string;
begin
  Result := 'Kind';
end;

function TDBMaskEditTest.OtherShown: string;
begin
  Result := CFixKinds[1];
end;

procedure TDBMaskEditTest.UserEdit;
begin
  EnterControl;
  Key(VK_A, [ssCtrl]);
  TypeText('Zed');
end;

procedure TDBMaskEditTest.UserEditUnguarded;
begin
  Ed.Clip := 'Pasted';
  Key(VK_A, [ssCtrl]);
  Key(VK_V, [ssCtrl]);
end;

procedure TDBMaskEditTest.Commit;
begin
  Key(VK_RETURN);
end;

procedure TDBMaskEditTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field', 'Zed', BoundField.AsString);
end;

procedure TDBMaskEditTest.PutKind(const AValue: string);
begin
  FFix.DS.Edit;
  FFix.DS.FieldByName('Kind').AsString := AValue;
  FFix.DS.Post;
end;

procedure TDBMaskEditTest.TestFieldEditMaskIsApplied;
begin
  PutKind('555-1234');
  FFix.DS.FieldByName('Kind').EditMask := '000-0000;1;_';
  Bind('Kind');
  AssertEquals('the field''s mask', '000-0000;1;_', Ed.EditMask);
  AssertEquals('the value, through it', '555-1234', Ed.Text);
  AssertBrowsing('binding a masked field');
end;

procedure TDBMaskEditTest.TestMaskedEditWritesTheMaskedValue;
begin
  PutKind('555-1234');
  FFix.DS.FieldByName('Kind').EditMask := '000-0000;1;_';
  Bind('Kind');
  EnterControl;
  Key(VK_A, [ssCtrl]);
  TypeText('8675309');
  AssertEquals('typed through the mask', '867-5309', Ed.Text);
  Commit;
  AssertEquals('the literal is kept (;1;)', '867-5309', FFix.DS.FieldByName('Kind').AsString);
end;

{ '#' is a code the library's mask refuses (MaskEdit.pas): a field carrying it gets no mask
  rather than an exception out of DataChange -- which would abort the scroll that loaded it. }
procedure TDBMaskEditTest.TestHashMaskIsNotAppliedAndDoesNotRaise;
begin
  FFix.DS.FieldByName('Kind').EditMask := '##-##';
  Bind('Kind');
  AssertEquals('no mask', '', Ed.EditMask);
  AssertEquals('the value shows as it is', CFixKinds[1], Ed.Text);
end;

procedure TDBMaskEditTest.TestCustomEditMaskKeepsTheControlsMask;
begin
  FFix.DS.FieldByName('Kind').EditMask := '000-0000;1;_';
  Ed.CustomEditMask := True;
  Ed.EditMask := 'lllll';
  Bind('Kind');
  AssertEquals('the control''s own mask', 'lllll', Ed.EditMask);
  AssertEquals('the value', CFixKinds[1], Ed.MaskedValue);
end;

{ A new mask empties a masked edit (MaskEdit.pas SetMask); bound, it shows the field again. }
procedure TDBMaskEditTest.TestChangingTheMaskKeepsShowingTheField;
begin
  Ed.CustomEditMask := True;
  Bind('Kind');
  AssertEquals('unmasked', CFixKinds[1], Ed.Text);
  Ed.EditMask := 'lllll';
  AssertEquals('masked, still the field', CFixKinds[1], Ed.MaskedValue);
  AssertBrowsing('changing the mask');
end;

{ ======================================================================= TDBMemoTest ======= }

function TDBMemoTest.NewControl: TControl;
begin
  Result := TProbeDBMemo.Create(FForm);
end;

function TDBMemoTest.Memo: TProbeDBMemo;
begin
  Result := TProbeDBMemo(FCtl);
end;

function TDBMemoTest.FieldName: string;
begin
  Result := 'Note';
end;

{ The memo's Text ends in the line break TStrings.Text adds after the last line. }
function TDBMemoTest.Shown: string;
begin
  Result := Memo.Text;
  if (Memo.Lines.Count > 0) and (Copy(Result, Length(Result) - Length(LineEnding) + 1,
    MaxInt) = LineEnding) then
    SetLength(Result, Length(Result) - Length(LineEnding));
end;

function TDBMemoTest.ExpectedShown(ARow: Integer): string;
begin
  if ARow <= 2 then Result := CFixNotes[ARow] else Result := '';
end;

function TDBMemoTest.OtherFieldName: string;
begin
  Result := 'Name';
end;

function TDBMemoTest.OtherShown: string;
begin
  Result := CFixNames[1];
end;

procedure TDBMemoTest.UserEdit;
begin
  EnterControl;
  Key(VK_A, [ssCtrl]);
  TypeText('Zed');
end;

procedure TDBMemoTest.UserEditUnguarded;
begin
  Memo.Clip := 'Pasted';
  Key(VK_A, [ssCtrl]);
  Key(VK_V, [ssCtrl]);
end;

procedure TDBMemoTest.Commit;
begin
  Memo.EditingDone;
end;

procedure TDBMemoTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field, without a trailing line break', 'Zed', BoundField.AsString);
end;

procedure TDBMemoTest.TestAutoDisplayOffShowsTheLabelUntilEnter;
begin
  Memo.AutoDisplay := False;
  Bind('Note');
  AssertEquals('the stand-in', '(Note)', Shown);
  EnterControl;
  Key(VK_RETURN);
  AssertEquals('Enter loads it', CFixNotes[1], Shown);
  AssertBrowsing('loading on Enter');
  TypeText('!');
  AssertTrue('loaded, it can be edited', FFix.DS.State = dsEdit);
end;

procedure TDBMemoTest.TestNothingIsTypedIntoTheUnloadedLabel;
begin
  Memo.AutoDisplay := False;
  Bind('Note');
  EnterControl;
  TypeText('x');
  Key(VK_BACK);
  AssertEquals('the stand-in is untouched', '(Note)', Shown);
  Memo.Clip := 'Pasted';
  Key(VK_V, [ssCtrl]);
  AssertEquals('a paste is undone', '(Note)', Shown);
  AssertBrowsing('typing into the stand-in');
  FCtl.EditingDone;
  AssertEquals('and nothing is written', CFixNotes[1], BoundField.AsString);
end;

{ Lines is handed out bare and a change through it does not notify the memo (Memo.pas,
  LinesChanged): code appending a line is not the user editing the record. }
procedure TDBMemoTest.TestLinesAddIsNotAnEdit;
begin
  Bind('Note');
  Memo.Lines.Add('appended by code');
  AssertEquals('two lines', 2, Memo.Lines.Count);
  AssertBrowsing('Lines.Add');
end;

procedure TDBMemoTest.TestNonBlobFieldShowsDisplayTextUnfocused;
var
  saved: TFormatSettings;
begin
  saved := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := '.';
    TFloatField(FFix.DS.FieldByName('Amount')).DisplayFormat := '0.000';
    TFloatField(FFix.DS.FieldByName('Amount')).EditFormat := '0.##';
    Bind('Amount');
    AssertEquals('unfocused', '12.500', Shown);
    EnterControl;
    AssertEquals('focused', '12.5', Shown);
  finally
    DefaultFormatSettings := saved;
  end;
end;

{ ======================================================================= TDBTextTest ======= }

function TDBTextTest.NewControl: TControl;
begin
  Result := TTyDBText.Create(FForm);
end;

function TDBTextTest.Lbl: TTyDBText;
begin
  Result := TTyDBText(FCtl);
end;

function TDBTextTest.FieldName: string;
begin
  Result := 'Name';
end;

function TDBTextTest.Shown: string;
begin
  Result := Lbl.Caption;
end;

function TDBTextTest.ExpectedShown(ARow: Integer): string;
begin
  if ARow <= 2 then Result := CFixNames[ARow] else Result := '';
end;

function TDBTextTest.OtherFieldName: string;
begin
  Result := 'Kind';
end;

function TDBTextTest.OtherShown: string;
begin
  Result := CFixKinds[1];
end;

function TDBTextTest.Editable: Boolean;
begin
  Result := False;
end;

procedure TDBTextTest.UserEdit;
begin
end;

procedure TDBTextTest.Commit;
begin
end;

procedure TDBTextTest.AssertFieldHoldsEdit;
begin
end;

procedure TDBTextTest.TestUnboundIsEmptyAtRunTime;
begin
  Lbl.Name := 'DBText1';
  AssertEquals('no Name in the caption at run time', '', Lbl.Caption);
end;

procedure TDBTextTest.TestUnboundShowsItsNameInTheDesigner;
begin
  TComponentAccess(TComponent(Lbl)).SetDesigning(True);
  Lbl.Name := 'DBText1';
  AssertEquals('its Name, to be found on the form', 'DBText1', Lbl.Caption);
  Bind('Name');
  AssertEquals('bound, the field', CFixNames[1], Lbl.Caption);
end;

procedure TDBTextTest.TestShowsDisplayText;
var
  saved: TFormatSettings;
begin
  saved := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := '.';
    TFloatField(FFix.DS.FieldByName('Amount')).DisplayFormat := '0.000';
    Bind('Amount');
    AssertEquals('formatted', '12.500', Lbl.Caption);
  finally
    DefaultFormatSettings := saved;
  end;
end;

initialization
  RegisterTest(TDBEditTest);
  RegisterTest(TDBMaskEditTest);
  RegisterTest(TDBMemoTest);
  RegisterTest(TDBTextTest);
end.
