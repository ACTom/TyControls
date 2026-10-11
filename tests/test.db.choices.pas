unit test.db.choices;
{$mode objfpc}{$H+}

{ The data-aware choices (issue #34, plan Task 5): TTyDBCheckBox, TTyDBToggleSwitch,
  TTyDBRadioGroup, TTyDBSegmented and TTyDBRating, through the shared C1-C8 run of
  test.db.edits plus what only choices have.

  A choice is written into the record the moment it is made, so C4's "commit" is nothing at
  all here (the field must already hold the value), and C5 checks that Escape takes nothing
  back -- there is no pending edit for it to drop; the record's Cancel is the undo.

  Every change is the user's: a press and release delivered as the widgetset delivers them
  (LM_LBUTTONDOWN / LM_LBUTTONUP, which LCL turns into Click), a key (KeyDown), a click on the
  radio group's CHILD button -- never a write to State, Checked, ItemIndex or Value, which is
  exactly what a control must not take for the user. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, StdCtrls, LCLType, LMessages, DB, TypInfo,
  fpcunit, testregistry,
  dbfixtures, test.db.edits, tyControls.Types, tyControls.Controller, tyControls.StyleModel,
  tyControls.Rating, tyControls.DB.Choices;

type
  { What every choice suite shares: the commit that is no commit, Escape, and a counter for
    the application's OnChange (a refused change must not even announce itself). }
  TDBChoiceTestBase = class(TDBControlTestBase)
  protected
    FChanges: Integer;
    FClicks: Integer;
    procedure CountChange(Sender: TObject);
    procedure CountClick(Sender: TObject);
    function EscapeRestores: Boolean; override;
    procedure Commit; override;
    { Press and release the left button at (X, Y) of AControl, as the widgetset sends them. }
    procedure PressAndRelease(AControl: TControl; X, Y: Integer);
    procedure ClickCenter(AControl: TControl);
    procedure PutField(const AName, AText: string);
  end;

  TDBCheckBoxTest = class(TDBChoiceTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function ExpectedUnbound: string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure UserEdit; override;
    { Space: the key path to the same Click. }
    procedure UserEditUnguarded; override;
    procedure AssertFieldHoldsEdit; override;
    function Box: TTyDBCheckBox;
  published
    procedure TestWordListsMatchAnyWordWithoutCase;
    procedure TestWritesTheFirstWordOfTheList;
    procedure TestClickIsWrittenAtOnce;
    procedure TestRefusedClickDoesNotFlip;
    procedure TestClickToGrayedWritesNull;
  end;

  TDBToggleSwitchTest = class(TDBChoiceTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure UserEdit; override;
    { Space: the base switch toggles on it without going through Click. }
    procedure UserEditUnguarded; override;
    procedure AssertFieldHoldsEdit; override;
    function Switch: TTyDBToggleSwitch;
  published
    procedure TestSpaceAndEnterToggleAndWrite;
    procedure TestRefusedKeysAndClickDoNotFlip;
    procedure TestWordListsMap;
  end;

  TDBRadioGroupTest = class(TDBChoiceTestBase)
  protected
    procedure SetUp; override;
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure UserEdit; override;
    { Space on an option: the radio button's key path to its Click. }
    procedure UserEditUnguarded; override;
    procedure AssertFieldHoldsEdit; override;
    function Group: TTyDBRadioGroup;
  published
    procedure TestClickOnAChildButtonEdits;
    procedure TestValuesStandInForItems;
    procedure TestValueReadsAndWritesTheSelection;
    procedure TestFieldValueInNoOptionSelectsNothing;
  end;

  TDBSegmentedTest = class(TDBChoiceTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure UserEdit; override;
    { An arrow key: the other road to a new segment. }
    procedure UserEditUnguarded; override;
    procedure AssertFieldHoldsEdit; override;
    function Seg: TTyDBSegmented;
  published
    procedure TestValuesStandInForItems;
    procedure TestValueReadsAndWritesTheSelection;
    procedure TestFieldValueInNoSegmentSelectsNothing;
  end;

  TDBRatingTest = class(TDBChoiceTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure UserEdit; override;
    { An arrow key: half a star up. }
    procedure UserEditUnguarded; override;
    procedure AssertFieldHoldsEdit; override;
    function Stars: TTyDBRating;
    { X of the right half of star AStar (1-based), which picks that whole star. }
    function StarX(AStar: Integer): Integer;
  published
    procedure TestWithoutHalvesShowsAndWritesWholeStars;
    procedure TestClearingToNoStarsWritesNull;
    procedure TestClearingToNoStarsWritesZeroWhenRequired;
    procedure TestReadOnlyFollowsTheControlAndTheField;
    procedure TestStarsResolveLikeTheBaseControls;
  end;

implementation

type
  TChoiceInput = class(TWinControl);

{ ============================================================== TDBChoiceTestBase ========= }

procedure TDBChoiceTestBase.CountChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TDBChoiceTestBase.CountClick(Sender: TObject);
begin
  Inc(FClicks);
end;

function TDBChoiceTestBase.EscapeRestores: Boolean;
begin
  Result := False;
end;

procedure TDBChoiceTestBase.Commit;
begin
  { Nothing: a choice is in the record as soon as it is made, and C4 checks just that. }
end;

procedure TDBChoiceTestBase.PressAndRelease(AControl: TControl; X, Y: Integer);
var
  pos: PtrInt;
begin
  pos := PtrInt((Y shl 16) or (X and $FFFF));
  AControl.Perform(LM_LBUTTONDOWN, MK_LBUTTON, pos);
  AControl.Perform(LM_LBUTTONUP, 0, pos);
end;

procedure TDBChoiceTestBase.ClickCenter(AControl: TControl);
begin
  AssertTrue('the control has an area to click', (AControl.Width > 0) and (AControl.Height > 0));
  PressAndRelease(AControl, AControl.Width div 2, AControl.Height div 2);
end;

procedure TDBChoiceTestBase.PutField(const AName, AText: string);
begin
  FFix.DS.Edit;
  FFix.DS.FieldByName(AName).AsString := AText;
  FFix.DS.Post;
end;

{ ================================================================ TDBCheckBoxTest ========= }

function StateName(AState: TCheckBoxState): string;
begin
  case AState of
    cbChecked: Result := 'checked';
    cbUnchecked: Result := 'unchecked';
  else
    Result := 'grayed';
  end;
end;

function TDBCheckBoxTest.NewControl: TControl;
begin
  Result := TTyDBCheckBox.Create(FForm);
  TTyDBCheckBox(Result).Caption := 'Active';
end;

function TDBCheckBoxTest.Box: TTyDBCheckBox;
begin
  Result := TTyDBCheckBox(FCtl);
end;

function TDBCheckBoxTest.FieldName: string;
begin
  Result := 'Active';
end;

function TDBCheckBoxTest.Shown: string;
begin
  Result := StateName(Box.State);
end;

function TDBCheckBoxTest.ExpectedShown(ARow: Integer): string;
begin
  case ARow of
    1: Result := 'checked';     // True
    2: Result := 'unchecked';   // False
  else
    Result := 'grayed';         // NULL (D5)
  end;
end;

function TDBCheckBoxTest.ExpectedUnbound: string;
begin
  Result := 'unchecked';
end;

function TDBCheckBoxTest.OtherFieldName: string;
begin
  Result := 'Flag';
end;

function TDBCheckBoxTest.OtherShown: string;
begin
  Result := 'grayed';   // 'Y' is in neither default list ('-1' / '0')
end;

procedure TDBCheckBoxTest.UserEdit;
begin
  EnterControl;
  ClickCenter(FCtl);
end;

procedure TDBCheckBoxTest.UserEditUnguarded;
begin
  Key(VK_SPACE);
end;

procedure TDBCheckBoxTest.AssertFieldHoldsEdit;
begin
  AssertFalse('the field, a boolean, not NULL', BoundField.IsNull);
  AssertFalse('the field, as a boolean', BoundField.AsBoolean);
end;

procedure TDBCheckBoxTest.TestWordListsMatchAnyWordWithoutCase;
begin
  Box.ValueChecked := 'Y;Yes';
  Box.ValueUnchecked := 'N;No';
  Bind('Flag');
  AssertEquals('row 1: Y', 'checked', Shown);
  GoRow(2);
  AssertEquals('row 2: N', 'unchecked', Shown);
  GoRow(1);
  Box.DataField := 'Kind';    // a wider text field, for whole words
  PutField('Kind', 'yes');
  AssertEquals('the second word, other case', 'checked', Shown);
  PutField('Kind', ' NO ');
  AssertEquals('spaces around the word', 'unchecked', Shown);
  PutField('Kind', 'maybe');
  AssertEquals('in neither list', 'grayed', Shown);
  AssertBrowsing('loading the word lists');
end;

{ LCL writes the whole ValueChecked string; with a list that would put 'Yes;Y' in the field. }
procedure TDBCheckBoxTest.TestWritesTheFirstWordOfTheList;
begin
  Box.ValueChecked := 'Yes;Y';
  Box.ValueUnchecked := 'No;N';
  Bind('Kind');
  AssertEquals('alpha is in neither list', 'grayed', Shown);
  ClickCenter(FCtl);
  AssertEquals('clicked', 'checked', Shown);
  AssertEquals('the first word of ValueChecked', 'Yes', FFix.DS.FieldByName('Kind').AsString);
  ClickCenter(FCtl);
  AssertEquals('the first word of ValueUnchecked', 'No', FFix.DS.FieldByName('Kind').AsString);
end;

{ LCL's TDBCheckBox: Edit, Modified, UpdateRecord -- the record holds the value without an
  EditingDone or a Post. }
procedure TDBCheckBoxTest.TestClickIsWrittenAtOnce;
begin
  Bind('Active');
  ClickCenter(FCtl);
  AssertTrue('editing', FFix.DS.State = dsEdit);
  AssertFalse('already in the record', BoundField.AsBoolean);
end;

{ D4 and M11: refused BEFORE the box flips. Flipping and flipping back would end in the same
  State, so the check is that nothing was announced: no OnChange, no OnClick. }
procedure TDBCheckBoxTest.TestRefusedClickDoesNotFlip;
begin
  FFix.Src.AutoEdit := False;
  Bind('Active');
  Box.OnChange := @CountChange;
  Box.OnClick := @CountClick;
  ClickCenter(FCtl);
  Key(VK_SPACE);
  AssertEquals('the state', 'checked', Shown);
  AssertEquals('it never flipped: no OnChange', 0, FChanges);
  AssertEquals('and no OnClick', 0, FClicks);
  AssertBrowsing('refused clicks');
  FFix.Src.AutoEdit := True;
  ClickCenter(FCtl);
  AssertEquals('allowed, it flips', 'unchecked', Shown);
  AssertEquals('once', 1, FChanges);
end;

{ D5: the grayed state is NULL, and with AllowGrayed the user can click to it. }
procedure TDBCheckBoxTest.TestClickToGrayedWritesNull;
begin
  Box.AllowGrayed := True;
  Bind('Active');
  ClickCenter(FCtl);
  AssertEquals('checked -> grayed', 'grayed', Shown);
  AssertTrue('NULL', BoundField.IsNull);
  ClickCenter(FCtl);
  AssertEquals('grayed -> unchecked', 'unchecked', Shown);
  AssertFalse('a value again', BoundField.IsNull);
  AssertFalse('False', BoundField.AsBoolean);
end;

{ ============================================================ TDBToggleSwitchTest ========= }

function TDBToggleSwitchTest.NewControl: TControl;
begin
  Result := TTyDBToggleSwitch.Create(FForm);
  TTyDBToggleSwitch(Result).AnimationsEnabled := False;
end;

function TDBToggleSwitchTest.Switch: TTyDBToggleSwitch;
begin
  Result := TTyDBToggleSwitch(FCtl);
end;

function TDBToggleSwitchTest.FieldName: string;
begin
  Result := 'Active';
end;

function TDBToggleSwitchTest.Shown: string;
begin
  if Switch.Checked then Result := 'on' else Result := 'off';
end;

function TDBToggleSwitchTest.ExpectedShown(ARow: Integer): string;
begin
  if ARow = 1 then Result := 'on' else Result := 'off';   // True, False, NULL (D5)
end;

function TDBToggleSwitchTest.OtherFieldName: string;
begin
  Result := 'Flag';
end;

function TDBToggleSwitchTest.OtherShown: string;
begin
  Result := 'off';   // 'Y' is not in the default ValueChecked ('-1')
end;

procedure TDBToggleSwitchTest.UserEdit;
begin
  EnterControl;
  ClickCenter(FCtl);
end;

procedure TDBToggleSwitchTest.UserEditUnguarded;
begin
  Key(VK_SPACE);
end;

procedure TDBToggleSwitchTest.AssertFieldHoldsEdit;
begin
  AssertFalse('the field, a boolean, not NULL', BoundField.IsNull);
  AssertFalse('the field, as a boolean', BoundField.AsBoolean);
end;

{ M12: the base switch toggles on Space and Enter in its KeyDown, without Click. }
procedure TDBToggleSwitchTest.TestSpaceAndEnterToggleAndWrite;
begin
  Bind('Active');
  EnterControl;
  Key(VK_SPACE);
  AssertEquals('Space', 'off', Shown);
  AssertTrue('an edit', FFix.DS.State = dsEdit);
  AssertFalse('written', BoundField.AsBoolean);
  Key(VK_RETURN);
  AssertEquals('Enter', 'on', Shown);
  AssertTrue('written', BoundField.AsBoolean);
  FFix.DS.Post;
  AssertTrue('posted', BoundField.AsBoolean);
end;

procedure TDBToggleSwitchTest.TestRefusedKeysAndClickDoNotFlip;
begin
  FFix.Src.AutoEdit := False;
  Bind('Active');
  Switch.OnChange := @CountChange;
  EnterControl;
  Key(VK_SPACE);
  Key(VK_RETURN);
  ClickCenter(FCtl);
  AssertEquals('the switch', 'on', Shown);
  AssertEquals('it never moved: no OnChange', 0, FChanges);
  AssertBrowsing('refused keys and click');
end;

procedure TDBToggleSwitchTest.TestWordListsMap;
begin
  Switch.ValueChecked := 'Y;Yes';
  Switch.ValueUnchecked := 'N;No';
  Bind('Flag');
  AssertEquals('row 1: Y', 'on', Shown);
  GoRow(2);
  AssertEquals('row 2: N', 'off', Shown);
  ClickCenter(FCtl);
  AssertEquals('the first word of ValueChecked', 'Y', FFix.DS.FieldByName('Flag').AsString);
end;

{ ============================================================== TDBRadioGroupTest ========= }

procedure TDBRadioGroupTest.SetUp;
begin
  inherited SetUp;
  FCtl.SetBounds(8, 8, 240, 160);   // room for three options to be clicked
end;

function TDBRadioGroupTest.NewControl: TControl;
var
  g: TTyDBRadioGroup;
begin
  g := TTyDBRadioGroup.Create(FForm);
  g.Caption := 'Kind';
  g.Items.Add('alpha');
  g.Items.Add('beta');
  g.Items.Add('gamma');
  Result := g;
end;

function TDBRadioGroupTest.Group: TTyDBRadioGroup;
begin
  Result := TTyDBRadioGroup(FCtl);
end;

function TDBRadioGroupTest.FieldName: string;
begin
  Result := 'Kind';
end;

function TDBRadioGroupTest.Shown: string;
begin
  Result := IntToStr(Group.ItemIndex);
end;

function TDBRadioGroupTest.ExpectedShown(ARow: Integer): string;
begin
  case ARow of
    1: Result := '0';     // alpha
    2: Result := '1';     // beta
  else
    Result := '-1';       // NULL (D5)
  end;
end;

function TDBRadioGroupTest.OtherFieldName: string;
begin
  Result := 'Name';
end;

function TDBRadioGroupTest.OtherShown: string;
begin
  Result := '-1';   // 'Alice' is no option
end;

procedure TDBRadioGroupTest.UserEdit;
begin
  ClickCenter(Group.Buttons[2]);
end;

procedure TDBRadioGroupTest.UserEditUnguarded;
var
  k: Word;
begin
  k := VK_SPACE;
  TChoiceInput(Group.Buttons[1]).KeyDown(k, []);
end;

procedure TDBRadioGroupTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field', 'gamma', BoundField.AsString);
end;

{ M13: the click lands on the child button, not on the group. }
procedure TDBRadioGroupTest.TestClickOnAChildButtonEdits;
begin
  Bind('Kind');
  ClickCenter(Group.Buttons[1]);
  AssertEquals('selected', 1, Group.ItemIndex);
  AssertTrue('an edit', FFix.DS.State = dsEdit);
  AssertEquals('written at once', 'beta', BoundField.AsString);
end;

{ LCL's GetButtonValue: Values[i] when it is there and not empty, Items[i] otherwise. }
procedure TDBRadioGroupTest.TestValuesStandInForItems;
begin
  Group.Values.Add('');
  Group.Values.Add('B');      // option 1 stands for 'B'; option 2 has no line: 'gamma'
  Bind('Kind');
  AssertEquals('alpha: an empty Values line', 0, Group.ItemIndex);
  GoRow(2);
  AssertEquals('beta is no option''s value now', -1, Group.ItemIndex);
  PutField('Kind', 'B');
  AssertEquals('B', 1, Group.ItemIndex);
  PutField('Kind', 'gamma');
  AssertEquals('gamma: past the end of Values', 2, Group.ItemIndex);
  ClickCenter(Group.Buttons[1]);
  AssertEquals('the value written', 'B', BoundField.AsString);
end;

{ On a data-aware radio group, as on LCL's, choosing from code is an edit as well: the group's
  one change notification does not tell the two apart. }
procedure TDBRadioGroupTest.TestValueReadsAndWritesTheSelection;
begin
  Bind('Kind');
  AssertEquals('read', 'alpha', Group.Value);
  Group.Value := 'gamma';
  AssertEquals('selected', 2, Group.ItemIndex);
  AssertTrue('an edit', FFix.DS.State = dsEdit);
  AssertEquals('written', 'gamma', BoundField.AsString);
end;

procedure TDBRadioGroupTest.TestFieldValueInNoOptionSelectsNothing;
begin
  Bind('Kind');
  PutField('Kind', 'zeta');
  AssertEquals('nothing selected', -1, Group.ItemIndex);
  AssertEquals('no value', '', Group.Value);
  AssertBrowsing('a value in no option');
end;

{ =============================================================== TDBSegmentedTest ========= }

function TDBSegmentedTest.NewControl: TControl;
var
  s: TTyDBSegmented;
begin
  s := TTyDBSegmented.Create(FForm);
  s.Items.Add('alpha');
  s.Items.Add('beta');
  s.Items.Add('gamma');
  Result := s;
end;

function TDBSegmentedTest.Seg: TTyDBSegmented;
begin
  Result := TTyDBSegmented(FCtl);
end;

function TDBSegmentedTest.FieldName: string;
begin
  Result := 'Kind';
end;

function TDBSegmentedTest.Shown: string;
begin
  Result := IntToStr(Seg.ItemIndex);
end;

function TDBSegmentedTest.ExpectedShown(ARow: Integer): string;
begin
  case ARow of
    1: Result := '0';
    2: Result := '1';
  else
    Result := '-1';
  end;
end;

function TDBSegmentedTest.OtherFieldName: string;
begin
  Result := 'Name';
end;

function TDBSegmentedTest.OtherShown: string;
begin
  Result := '-1';
end;

procedure TDBSegmentedTest.UserEdit;
var
  c: TPoint;
begin
  c := CenterPoint(Seg.TySegmentRect(2));
  PressAndRelease(FCtl, c.X, c.Y);
end;

procedure TDBSegmentedTest.UserEditUnguarded;
begin
  Key(VK_RIGHT);
end;

procedure TDBSegmentedTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field', 'gamma', BoundField.AsString);
end;

procedure TDBSegmentedTest.TestValuesStandInForItems;
var
  c: TPoint;
begin
  Seg.Values.Add('');
  Seg.Values.Add('B');
  Bind('Kind');
  AssertEquals('alpha: an empty Values line', 0, Seg.ItemIndex);
  PutField('Kind', 'B');
  AssertEquals('B', 1, Seg.ItemIndex);
  PutField('Kind', 'beta');
  AssertEquals('beta is no segment''s value now', -1, Seg.ItemIndex);
  c := CenterPoint(Seg.TySegmentRect(1));
  PressAndRelease(FCtl, c.X, c.Y);
  AssertEquals('the value written', 'B', BoundField.AsString);
end;

{ Unlike the radio group, the segmented control hears the user only through its own mouse and
  keys, so choosing from code selects the segment and edits nothing. }
procedure TDBSegmentedTest.TestValueReadsAndWritesTheSelection;
begin
  Bind('Kind');
  AssertEquals('read', 'alpha', Seg.Value);
  Seg.Value := 'gamma';
  AssertEquals('selected', 2, Seg.ItemIndex);
  AssertEquals('read back', 'gamma', Seg.Value);
  AssertBrowsing('Value set from code');
end;

procedure TDBSegmentedTest.TestFieldValueInNoSegmentSelectsNothing;
begin
  Bind('Kind');
  PutField('Kind', 'zeta');
  AssertEquals('nothing selected', -1, Seg.ItemIndex);
  AssertEquals('no value', '', Seg.Value);
end;

{ ================================================================== TDBRatingTest ========= }

function TDBRatingTest.NewControl: TControl;
begin
  Result := TTyDBRating.Create(FForm);
  TTyDBRating(Result).AllowHalf := True;   // the fixture's 3.5 shows as it is
  { A press asks a tab-stop rating for the focus, unguarded -- and the test form is never
    shown, so SetFocus would raise. Focus is not what these tests are about. }
  TTyDBRating(Result).TabStop := False;
end;

function TDBRatingTest.Stars: TTyDBRating;
begin
  Result := TTyDBRating(FCtl);
end;

function TDBRatingTest.StarX(AStar: Integer): Integer;
begin
  Result := (Stars.ClientWidth * AStar) div Stars.Count - 1;
end;

function TDBRatingTest.FieldName: string;
begin
  Result := 'Stars';
end;

function TDBRatingTest.Shown: string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FormatFloat('0.0', Stars.Value, fs);
end;

function TDBRatingTest.ExpectedShown(ARow: Integer): string;
begin
  case ARow of
    1: Result := '3.5';
    2: Result := '1.0';
  else
    Result := '0.0';   // NULL: no stars (D5)
  end;
end;

function TDBRatingTest.OtherFieldName: string;
begin
  Result := 'Amount';
end;

function TDBRatingTest.OtherShown: string;
begin
  Result := '5.0';   // 12.5, as many stars as there are
end;

procedure TDBRatingTest.UserEdit;
begin
  EnterControl;
  TChoiceInput(FCtl).MouseDown(mbLeft, [ssLeft], StarX(2), 10);
  TChoiceInput(FCtl).MouseUp(mbLeft, [], StarX(2), 10);
end;

procedure TDBRatingTest.UserEditUnguarded;
begin
  Key(VK_RIGHT);
end;

procedure TDBRatingTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field, as a number', 2, BoundField.AsFloat, 0);
end;

procedure TDBRatingTest.TestWithoutHalvesShowsAndWritesWholeStars;
begin
  Stars.AllowHalf := False;
  Bind('Stars');
  AssertEquals('3.5 shows as 4 whole stars', '4.0', Shown);
  AssertBrowsing('loading a half star into whole ones');
  EnterControl;
  Key(VK_RIGHT);
  AssertEquals('one whole star up', '5.0', Shown);
  AssertEquals('written whole', 5, BoundField.AsFloat, 0);
end;

{ D5: clicking the single star that is lit clears the rating -- and no stars is NULL. }
procedure TDBRatingTest.TestClearingToNoStarsWritesNull;
begin
  Stars.AllowHalf := False;
  Bind('Stars');
  GoRow(2);
  AssertEquals('one star', '1.0', Shown);
  TChoiceInput(FCtl).MouseDown(mbLeft, [ssLeft], StarX(1), 10);
  TChoiceInput(FCtl).MouseUp(mbLeft, [], StarX(1), 10);
  AssertEquals('cleared', '0.0', Shown);
  AssertTrue('NULL', BoundField.IsNull);
end;

procedure TDBRatingTest.TestClearingToNoStarsWritesZeroWhenRequired;
begin
  Stars.AllowHalf := False;
  BoundField.Required := True;
  Bind('Stars');
  GoRow(2);
  TChoiceInput(FCtl).MouseDown(mbLeft, [ssLeft], StarX(1), 10);
  TChoiceInput(FCtl).MouseUp(mbLeft, [], StarX(1), 10);
  AssertEquals('cleared', '0.0', Shown);
  AssertFalse('a required field gets a number', BoundField.IsNull);
  AssertEquals('0', 0, BoundField.AsFloat, 0);
end;

{ D4: the base control's own ReadOnly is what refuses a click before the stars move. }
procedure TDBRatingTest.TestReadOnlyFollowsTheControlAndTheField;
begin
  Bind('Stars');
  AssertFalse('editable field: the stars take clicks', TTyCustomRating(FCtl).ReadOnly);
  Stars.ReadOnly := True;
  AssertTrue('ReadOnly', TTyCustomRating(FCtl).ReadOnly);
  Stars.ReadOnly := False;
  AssertFalse('ReadOnly off again', TTyCustomRating(FCtl).ReadOnly);
  BoundField.ReadOnly := True;
  GoRow(2);
  AssertTrue('a read-only field', TTyCustomRating(FCtl).ReadOnly);
  BoundField.ReadOnly := False;
  GoRow(1);
  AssertFalse('the field editable again', TTyCustomRating(FCtl).ReadOnly);
  FFix.Src.AutoEdit := False;
  GoRow(2);
  AssertFalse('AutoEdit is not CanModify: refused after the click instead',
    TTyCustomRating(FCtl).ReadOnly);
end;

{ The filled stars are resolved as the control's key + 'Star': 'TyDBRatingStar', which must
  fall back to the base rating's star, or a theme that never names it draws them blank. }
procedure TDBRatingTest.TestStarsResolveLikeTheBaseControls;
var
  db, base: TTyStyleSet;
begin
  db := TyDefaultController.Model.ResolveStyle('TyDBRatingStar', '', []);
  base := TyDefaultController.Model.ResolveStyle('TyRatingStar', '', []);
  AssertTrue('the base star has a fill', tpBackground in base.Present);
  AssertTrue('the data-aware star too', tpBackground in db.Present);
  AssertEquals('the same fill', Int64(base.Background.Color), Int64(db.Background.Color));
end;

initialization
  RegisterTest(TDBCheckBoxTest);
  RegisterTest(TDBToggleSwitchTest);
  RegisterTest(TDBRadioGroupTest);
  RegisterTest(TDBSegmentedTest);
  RegisterTest(TDBRatingTest);
end.
