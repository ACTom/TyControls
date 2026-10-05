unit test.db.numeric;
{$mode objfpc}{$H+}

{ The data-aware numeric controls (issue #34, plan Task 4): TTyDBNumericEdit, TTyDBCurrencyEdit,
  TTyDBSpinEdit and TTyDBFloatSpinEdit, through the shared C1-C8 run of test.db.edits plus what
  only numbers have:

  * the value goes into the field as a number, so a locale whose DecimalSeparator is ',' does
    not see the control's '.' (the field's Text would);
  * NULL is an empty field and an emptied field is NULL (D5);
  * focus arriving and leaving reformats the text (raw while focused, grouped after) and fires
    OnChange with the value unchanged -- the shape of "a load mistaken for an edit" most likely
    to slip through here (V5), so every check of it first proves the text did change;
  * a field value outside MinValue..MaxValue is shown clamped and not written back unless the
    user changes it. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, LCLType, DB, TypInfo, fpcunit, testregistry,
  dbfixtures, test.db.edits, tyControls.Types, tyControls.SpinEdit, tyControls.DB.Edits;

type
  TProbeDBNumericEdit = class(TTyDBNumericEdit)
  protected
    function ReadClipboardText: string; override;
  public
    Clip: string;
  end;

  TProbeDBCurrencyEdit = class(TTyDBCurrencyEdit)
  protected
    function ReadClipboardText: string; override;
  public
    Clip: string;
  end;

  TProbeDBFloatSpinEdit = class(TTyDBFloatSpinEdit)
  protected
    function ReadClipboardText: string; override;
  public
    Clip: string;
  end;

  TProbeDBSpinEdit = class(TTyDBSpinEdit)
  public
    ValueChanges: Integer;
    procedure CountValueChange(Sender: TObject);
    { The middle of the up button, where the control's own hit test puts it. }
    function UpButtonCenter: TPoint;
  end;

  { What the three edit-based controls share: typing, the clipboard, Enter. }
  TDBNumberEditTestBase = class(TDBControlTestBase)
  protected
    procedure SetClip(const S: string); virtual; abstract;
    procedure UserEdit; override;
    procedure UserEditUnguarded; override;
    procedure Commit; override;
    function Shown: string; override;
    procedure PutAmount(AValue: Double);
    procedure PutBound(AValue: Double);
  published
    procedure TestEmptiedFieldWritesNull;
    procedure TestValueIsWrittenAsANumberWhateverTheDecimalSeparator;
    procedure TestRangeSetAfterBindingIsNotAnEdit;
    procedure TestDecimalsSetAfterBindingIsNotAnEdit;
    procedure TestOldValuePutBackAfterAWriteIsWritten;
  end;

  TDBNumericEditTest = class(TDBNumberEditTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure SetClip(const S: string); override;
    procedure AssertFieldHoldsEdit; override;
    function Ed: TProbeDBNumericEdit;
  published
    procedure TestFocusRoundTripReformatsButDoesNotEdit;
    procedure TestOutOfRangeValueShowsClampedAndIsNotWritten;
    procedure TestUserChangeOfAClampedValueIsWritten;
  end;

  TDBCurrencyEditTest = class(TDBNumberEditTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function ExpectedFocused(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure SetClip(const S: string); override;
    procedure AssertFieldHoldsEdit; override;
    function Ed: TProbeDBCurrencyEdit;
  published
    procedure TestFocusRoundTripReformatsButDoesNotEdit;
  end;

  TDBFloatSpinEditTest = class(TDBNumberEditTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure SetClip(const S: string); override;
    { A step, not typing: the arrows are this control's own way of editing. }
    procedure UserEdit; override;
    procedure AssertFieldHoldsEdit; override;
    function Ed: TProbeDBFloatSpinEdit;
  published
    procedure TestTypedValueIsWritten;
    procedure TestRefusedStepLeavesTheControlUntouched;
  end;

  TDBSpinEditTest = class(TDBControlTestBase)
  protected
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    procedure UserEdit; override;
    { The wheel: a second road to a step, guarded on its own. }
    procedure UserEditUnguarded; override;
    procedure Commit; override;
    procedure AssertFieldHoldsEdit; override;
    function Spin: TProbeDBSpinEdit;
  published
    procedure TestNullRowIsValueEmpty;
    procedure TestTypedDigitsAreWrittenOnEnter;
    procedure TestOutOfRangeValueShowsClampedAndIsNotWritten;
    procedure TestRangeSetAfterBindingIsNotAnEdit;
    procedure TestNullRowStaysBlankUnderANewRange;
    procedure TestRefusedStepFiresNoValueChange;
    procedure TestRefusedSpinButtonDoesNotStep;
    procedure TestOldValuePutBackAfterAWriteIsWritten;
  end;

implementation

type
  { This unit's own way in to the protected input methods (a cracker class only opens them in
    the unit that declares it). }
  TNumInput = class(TWinControl);

function TProbeDBNumericEdit.ReadClipboardText: string;
begin
  Result := Clip;
end;

function TProbeDBCurrencyEdit.ReadClipboardText: string;
begin
  Result := Clip;
end;

function TProbeDBFloatSpinEdit.ReadClipboardText: string;
begin
  Result := Clip;
end;

procedure TProbeDBSpinEdit.CountValueChange(Sender: TObject);
begin
  Inc(ValueChanges);
end;

function TProbeDBSpinEdit.UpButtonCenter: TPoint;
var
  ppi, bw: Integer;
begin
  ppi := Font.PixelsPerInch;
  bw := MulDiv(ActiveController.Metric('--field-button-width', TyFieldButtonWidth), ppi, 96);
  Result := CenterPoint(TySpinUpButtonRect(ClientRect, ppi, bw));
end;

{ ========================================================== TDBNumberEditTestBase ========= }

procedure TDBNumberEditTestBase.UserEdit;
begin
  EnterControl;
  Key(VK_A, [ssCtrl]);
  TypeText('42.5');
end;

procedure TDBNumberEditTestBase.UserEditUnguarded;
begin
  SetClip('9');
  Key(VK_A, [ssCtrl]);
  Key(VK_V, [ssCtrl]);
end;

procedure TDBNumberEditTestBase.Commit;
begin
  Key(VK_RETURN);
end;

function TDBNumberEditTestBase.Shown: string;
begin
  Result := TNumInput(FCtl).Caption;   // Caption is Text on every edit of the library
end;

procedure TDBNumberEditTestBase.PutAmount(AValue: Double);
begin
  FFix.DS.Edit;
  FFix.DS.FieldByName('Amount').AsFloat := AValue;
  FFix.DS.Post;
end;

procedure TDBNumberEditTestBase.PutBound(AValue: Double);
begin
  FFix.DS.Edit;
  BoundField.AsFloat := AValue;
  FFix.DS.Post;
end;

{ D5 }
procedure TDBNumberEditTestBase.TestEmptiedFieldWritesNull;
begin
  Bind(FieldName);
  EnterControl;
  Key(VK_A, [ssCtrl]);
  Key(VK_BACK);
  AssertEquals('emptied', '', Shown);
  AssertTrue('an edit', FFix.DS.State = dsEdit);
  Commit;
  AssertTrue('NULL', BoundField.IsNull);
  LeaveControl;
  AssertEquals('and leaving does not make it 0', '', Shown);
end;

{ The control always shows and types a '.', the field's Text follows the locale: written as
  text, '42.5' would not parse (or would parse as something else) where ',' is the separator. }
procedure TDBNumberEditTestBase.TestValueIsWrittenAsANumberWhateverTheDecimalSeparator;
var
  saved: TFormatSettings;
begin
  saved := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := ',';
    DefaultFormatSettings.ThousandSeparator := '.';
    Bind(FieldName);
    UserEdit;
    Commit;
    AssertFieldHoldsEdit;
  finally
    DefaultFormatSettings := saved;
  end;
end;

{ D6: the program narrowing the range after the control is bound re-clamps what is shown --
  and that is all it does. The display changes (checked first, so a range that clamped nothing
  cannot pass), the dataset is not put in dsEdit, a focus round trip afterwards (which
  reformats) does not edit either, and a Post made elsewhere does not write the clamped value. }
procedure TDBNumberEditTestBase.TestRangeSetAfterBindingIsNotAnEdit;
var
  before: Double;
begin
  Bind(FieldName);
  before := BoundField.AsFloat;
  { Clamped UP to a number that groups, so focus coming and going changes the text (raw
    '1000.00' focused, '1,000.00' not) and fires the change notification at the new value.
    The float spin edit does not group by default; here it must. }
  SetOrdProp(FCtl, 'UseThousands', Ord(True));
  SetFloatProp(FCtl, 'MinValue', 1000);
  SetFloatProp(FCtl, 'MaxValue', 2000);
  AssertTrue('shown clamped: the display changed', Shown <> ExpectedShown(1));
  AssertBrowsing('a range set from code');
  EnterControl;
  LeaveControl;
  AssertBrowsing('a focus round trip under the new range');
  GoRow(2);
  GoRow(1);
  AssertEquals('the field after scrolling away and back', before, BoundField.AsFloat, 0);
  FFix.DS.Edit;              // someone else edits the record
  FFix.DS.Post;
  AssertEquals('a Post elsewhere does not write the clamped value', before,
    BoundField.AsFloat, 0);
end;

{ Decimals set from code after binding is the program's doing too: the base control rounds the
  display to the new number of places and fires its change notification, and that is no edit.
  Fewer places first -- the display changes (checked, so a setting that rounded nothing cannot
  pass) -- then a focus round trip and a Post made elsewhere leave the field as it was. More
  places again show the FIELD at the new precision, not the rounded display padded with zeros. }
procedure TDBNumberEditTestBase.TestDecimalsSetAfterBindingIsNotAnEdit;
const
  CValue = 1234.5678;
begin
  PutBound(CValue);
  Bind(FieldName);
  AssertTrue('two places: ' + Shown, Pos('234.57', Shown) > 0);
  SetOrdProp(FCtl, 'Decimals', 0);
  AssertTrue('no places: the display changed: ' + Shown,
    (Pos('235', Shown) > 0) and (Pos('.', Shown) = 0));
  AssertBrowsing('Decimals set from code');
  EnterControl;
  LeaveControl;
  AssertBrowsing('a focus round trip under the new Decimals');
  FFix.DS.Edit;              // someone else edits the record
  FFix.DS.Post;
  AssertEquals('a Post elsewhere does not write the rounded value', CValue,
    BoundField.AsFloat, 1e-9);
  SetOrdProp(FCtl, 'Decimals', 4);
  AssertTrue('four places: the field''s own digits: ' + Shown, Pos('234.5678', Shown) > 0);
  AssertBrowsing('more places');
end;

{ Enter wrote the edit, so the field holds it now: putting the old number back -- one paste
  over everything -- is an edit like any other, and EditingDone writes it. }
procedure TDBNumberEditTestBase.TestOldValuePutBackAfterAWriteIsWritten;
var
  before: Double;
begin
  Bind(FieldName);
  before := BoundField.AsFloat;
  UserEdit;
  Commit;
  AssertFieldHoldsEdit;
  SetClip(ExpectedFocused(1));
  Key(VK_A, [ssCtrl]);
  Key(VK_V, [ssCtrl]);
  AssertEquals('the old value, back in one change', ExpectedFocused(1), Shown);
  FCtl.EditingDone;
  AssertEquals('EditingDone writes it', before, BoundField.AsFloat, 0);
end;

{ ============================================================= TDBNumericEditTest ========= }

function TDBNumericEditTest.NewControl: TControl;
begin
  Result := TProbeDBNumericEdit.Create(FForm);
end;

function TDBNumericEditTest.Ed: TProbeDBNumericEdit;
begin
  Result := TProbeDBNumericEdit(FCtl);
end;

function TDBNumericEditTest.FieldName: string;
begin
  Result := 'Amount';
end;

function TDBNumericEditTest.ExpectedShown(ARow: Integer): string;
begin
  case ARow of
    1: Result := '12.50';
    2: Result := '-4.75';
  else
    Result := '';
  end;
end;

function TDBNumericEditTest.OtherFieldName: string;
begin
  Result := 'Stars';
end;

function TDBNumericEditTest.OtherShown: string;
begin
  Result := '3.50';
end;

procedure TDBNumericEditTest.SetClip(const S: string);
begin
  Ed.Clip := S;
end;

procedure TDBNumericEditTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field, as a number', 42.5, BoundField.AsFloat, 0);
end;

{ V5. 1234.5 groups when it is not focused, so the text DOES change both ways. }
procedure TDBNumericEditTest.TestFocusRoundTripReformatsButDoesNotEdit;
begin
  PutAmount(1234.5);
  Bind('Amount');
  AssertEquals('grouped', '1,234.50', Ed.Text);
  EnterControl;
  AssertEquals('raw while focused: the text changed', '1234.50', Ed.Text);
  AssertBrowsing('focus arriving');
  LeaveControl;
  AssertEquals('grouped again', '1,234.50', Ed.Text);
  AssertBrowsing('focus leaving');
end;

procedure TDBNumericEditTest.TestOutOfRangeValueShowsClampedAndIsNotWritten;
begin
  Ed.MinValue := 0;
  Ed.MaxValue := 10;
  PutAmount(99);
  Bind('Amount');
  AssertEquals('shown clamped', '10.00', Ed.Text);
  AssertBrowsing('loading a clamped value');
  FFix.DS.Edit;              // someone else edits the record
  EnterControl;
  LeaveControl;
  FFix.DS.Post;
  AssertEquals('not written: the user did not touch it', 99, BoundField.AsFloat, 0);
end;

procedure TDBNumericEditTest.TestUserChangeOfAClampedValueIsWritten;
begin
  Ed.MinValue := 0;
  Ed.MaxValue := 10;
  PutAmount(99);
  Bind('Amount');
  EnterControl;
  Key(VK_A, [ssCtrl]);
  TypeText('7');
  Commit;
  AssertEquals('written', 7, BoundField.AsFloat, 0);
end;

{ ============================================================ TDBCurrencyEditTest ========= }

function TDBCurrencyEditTest.NewControl: TControl;
begin
  Result := TProbeDBCurrencyEdit.Create(FForm);
end;

function TDBCurrencyEditTest.Ed: TProbeDBCurrencyEdit;
begin
  Result := TProbeDBCurrencyEdit(FCtl);
end;

function TDBCurrencyEditTest.FieldName: string;
begin
  Result := 'Price';
end;

function TDBCurrencyEditTest.ExpectedShown(ARow: Integer): string;
begin
  case ARow of
    1: Result := '$3.25';
    2: Result := '$1,000.00';
  else
    Result := '';
  end;
end;

function TDBCurrencyEditTest.ExpectedFocused(ARow: Integer): string;
begin
  case ARow of
    1: Result := '3.25';
    2: Result := '1000.00';
  else
    Result := '';
  end;
end;

function TDBCurrencyEditTest.OtherFieldName: string;
begin
  Result := 'Amount';
end;

function TDBCurrencyEditTest.OtherShown: string;
begin
  Result := '$12.50';
end;

procedure TDBCurrencyEditTest.SetClip(const S: string);
begin
  Ed.Clip := S;
end;

procedure TDBCurrencyEditTest.AssertFieldHoldsEdit;
begin
  AssertTrue('the field, as a currency', BoundField.AsCurrency = 42.5);
end;

{ The symbol comes and goes with focus, at every value. }
procedure TDBCurrencyEditTest.TestFocusRoundTripReformatsButDoesNotEdit;
begin
  Bind('Price');
  GoRow(2);
  AssertEquals('display form', '$1,000.00', Ed.Text);
  EnterControl;
  AssertEquals('raw while focused: the text changed', '1000.00', Ed.Text);
  AssertBrowsing('focus arriving');
  LeaveControl;
  AssertEquals('display form again', '$1,000.00', Ed.Text);
  AssertBrowsing('focus leaving');
end;

{ =========================================================== TDBFloatSpinEditTest ========= }

function TDBFloatSpinEditTest.NewControl: TControl;
begin
  Result := TProbeDBFloatSpinEdit.Create(FForm);
end;

function TDBFloatSpinEditTest.Ed: TProbeDBFloatSpinEdit;
begin
  Result := TProbeDBFloatSpinEdit(FCtl);
end;

function TDBFloatSpinEditTest.FieldName: string;
begin
  Result := 'Amount';
end;

function TDBFloatSpinEditTest.ExpectedShown(ARow: Integer): string;
begin
  case ARow of
    1: Result := '12.50';
    2: Result := '-4.75';
  else
    Result := '';
  end;
end;

function TDBFloatSpinEditTest.OtherFieldName: string;
begin
  Result := 'Stars';
end;

function TDBFloatSpinEditTest.OtherShown: string;
begin
  Result := '3.50';
end;

procedure TDBFloatSpinEditTest.SetClip(const S: string);
begin
  Ed.Clip := S;
end;

procedure TDBFloatSpinEditTest.UserEdit;
begin
  EnterControl;
  Key(VK_UP);
end;

procedure TDBFloatSpinEditTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field, one step up', 13.5, BoundField.AsFloat, 0);
end;

procedure TDBFloatSpinEditTest.TestTypedValueIsWritten;
begin
  Bind('Amount');
  EnterControl;
  Key(VK_A, [ssCtrl]);
  TypeText('2.25');
  Commit;
  AssertEquals('written', 2.25, BoundField.AsFloat, 0);
end;

{ Refused before the step, not undone after it: the control's own dirty flag (Modified, which
  a step sets) stays clear. }
procedure TDBFloatSpinEditTest.TestRefusedStepLeavesTheControlUntouched;
begin
  FFix.Src.AutoEdit := False;
  Bind('Amount');
  EnterControl;
  AssertFalse('loaded, not modified', Ed.Modified);
  Key(VK_UP);
  AssertEquals('the value', '12.50', Ed.Text);
  AssertFalse('a refused step does not mark the control modified', Ed.Modified);
  AssertBrowsing('a refused step');
end;

{ ================================================================ TDBSpinEditTest ========= }

function TDBSpinEditTest.NewControl: TControl;
begin
  Result := TProbeDBSpinEdit.Create(FForm);
end;

function TDBSpinEditTest.Spin: TProbeDBSpinEdit;
begin
  Result := TProbeDBSpinEdit(FCtl);
end;

function TDBSpinEditTest.FieldName: string;
begin
  Result := 'Qty';
end;

function TDBSpinEditTest.Shown: string;
begin
  Result := Spin.Text;
end;

function TDBSpinEditTest.ExpectedShown(ARow: Integer): string;
begin
  if ARow <= 2 then Result := IntToStr(CFixQtys[ARow]) else Result := '';
end;

function TDBSpinEditTest.OtherFieldName: string;
begin
  Result := 'CityID';
end;

function TDBSpinEditTest.OtherShown: string;
begin
  Result := IntToStr(CFixCityIDs[1]);
end;

procedure TDBSpinEditTest.UserEdit;
begin
  EnterControl;
  Key(VK_UP);
end;

procedure TDBSpinEditTest.UserEditUnguarded;
begin
  TNumInput(FCtl).DoMouseWheel([], 120, Point(10, 10));
end;

procedure TDBSpinEditTest.Commit;
begin
  LeaveControl;
end;

procedure TDBSpinEditTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field, one step up', CFixQtys[1] + 1, BoundField.AsInteger);
end;

{ D5: the spin edit shows NULL as its blank state. }
procedure TDBSpinEditTest.TestNullRowIsValueEmpty;
begin
  Bind('Qty');
  AssertFalse('row 1 has a number', Spin.ValueEmpty);
  GoRow(3);
  AssertTrue('NULL: ValueEmpty', Spin.ValueEmpty);
  GoRow(2);
  AssertFalse('row 2 (0) has a number again', Spin.ValueEmpty);
  AssertEquals('and shows it', '0', Spin.Text);
end;

procedure TDBSpinEditTest.TestTypedDigitsAreWrittenOnEnter;
begin
  Bind('Qty');
  EnterControl;
  TypeText('5');
  AssertEquals('typed after the 7', '75', Spin.Text);
  AssertTrue('typing edits', FFix.DS.State = dsEdit);
  Key(VK_RETURN);
  AssertEquals('Enter writes it', 75, BoundField.AsInteger);
end;

procedure TDBSpinEditTest.TestOutOfRangeValueShowsClampedAndIsNotWritten;
begin
  Spin.MinValue := 0;
  Spin.MaxValue := 5;
  Bind('Qty');
  AssertEquals('shown clamped', '5', Spin.Text);
  AssertBrowsing('loading a clamped value');
  FFix.DS.Edit;
  EnterControl;
  LeaveControl;
  FFix.DS.Post;
  AssertEquals('not written', CFixQtys[1], BoundField.AsInteger);
end;

{ D6, as for the edits: a range set from code re-clamps the display and edits nothing. }
procedure TDBSpinEditTest.TestRangeSetAfterBindingIsNotAnEdit;
begin
  Bind('Qty');
  Spin.MinValue := 0;
  Spin.MaxValue := 5;
  AssertEquals('shown clamped', '5', Spin.Text);
  AssertBrowsing('a range set from code');
  EnterControl;
  LeaveControl;
  AssertBrowsing('a focus round trip under the new range');
  GoRow(2);
  GoRow(1);
  AssertEquals('the field after scrolling away and back', CFixQtys[1], BoundField.AsInteger);
  FFix.DS.Edit;
  FFix.DS.Post;
  AssertEquals('a Post elsewhere does not write the clamped value', CFixQtys[1],
    BoundField.AsInteger);
end;

{ The base re-clamps through its Value setter, which ends the blank state: a NULL field must
  not turn into the range's floor on screen. }
procedure TDBSpinEditTest.TestNullRowStaysBlankUnderANewRange;
begin
  Bind('Qty');
  GoRow(3);
  AssertTrue('NULL: ValueEmpty', Spin.ValueEmpty);
  Spin.MinValue := 2;
  Spin.MaxValue := 9;
  AssertTrue('still blank', Spin.ValueEmpty);
  AssertEquals('nothing shown', '', Spin.Text);
  AssertBrowsing('a range set on the NULL row');
end;

{ Refused before the value moves: a step that is undone afterwards would still have told the
  application the value changed. }
procedure TDBSpinEditTest.TestRefusedStepFiresNoValueChange;
begin
  FFix.Src.AutoEdit := False;
  Bind('Qty');
  Spin.OnValueChange := @Spin.CountValueChange;
  EnterControl;
  Key(VK_UP);
  TNumInput(FCtl).DoMouseWheel([], 120, Point(10, 10));
  AssertEquals('no OnValueChange', 0, Spin.ValueChanges);
  AssertEquals('the value', CFixQtys[1], Spin.Value);
  AssertBrowsing('refused steps');
end;

procedure TDBSpinEditTest.TestRefusedSpinButtonDoesNotStep;
var
  c: TPoint;
begin
  FFix.Src.AutoEdit := False;
  Bind('Qty');
  Spin.OnValueChange := @Spin.CountValueChange;
  c := Spin.UpButtonCenter;
  TNumInput(FCtl).MouseDown(mbLeft, [ssLeft], c.X, c.Y);
  TNumInput(FCtl).MouseUp(mbLeft, [], c.X, c.Y);
  AssertEquals('no step', CFixQtys[1], Spin.Value);
  AssertEquals('not even one that was undone: no OnValueChange', 0, Spin.ValueChanges);
  AssertBrowsing('a refused button press');
  FFix.Src.AutoEdit := True;
  TNumInput(FCtl).MouseDown(mbLeft, [ssLeft], c.X, c.Y);
  TNumInput(FCtl).MouseUp(mbLeft, [], c.X, c.Y);
  AssertEquals('allowed, it steps', CFixQtys[1] + 1, Spin.Value);
  AssertTrue('and edits', FFix.DS.State = dsEdit);
end;

{ Enter wrote the step, so the field holds it now: stepping back to the old number is an edit
  like any other, and EditingDone writes it. }
procedure TDBSpinEditTest.TestOldValuePutBackAfterAWriteIsWritten;
begin
  Bind('Qty');
  EnterControl;
  Key(VK_UP);
  Key(VK_RETURN);
  AssertEquals('Enter wrote the step', CFixQtys[1] + 1, BoundField.AsInteger);
  Key(VK_DOWN);
  AssertEquals('one step back: the old value', IntToStr(CFixQtys[1]), Spin.Text);
  FCtl.EditingDone;
  AssertEquals('EditingDone writes it', CFixQtys[1], BoundField.AsInteger);
end;

initialization
  RegisterTest(TDBNumericEditTest);
  RegisterTest(TDBCurrencyEditTest);
  RegisterTest(TDBFloatSpinEditTest);
  RegisterTest(TDBSpinEditTest);
end.
