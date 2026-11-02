unit test.spinedit.textengine;

{$mode objfpc}{$H+}

{ #190: TTySpinEdit is a full edit, as LCL's TSpinEdit is a TCustomEdit -- selection by mouse
  and Shift+arrows, SelStart / SelLength / SelText, Cut / Copy / Paste and Undo -- and the
  number rules still hold over all of it: only digits and a leading '-' go in, EditorEnabled =
  False locks every keystroke that would change the text, and the Value commits on Enter or
  on leaving the field. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, LCLType, fpcunit, testregistry,
  tyControls.SpinEdit;

type
  { The clipboard is a string here, so the tests never touch the real one. }
  TSpinClip = class(TTySpinEdit)
  public
    Clip: string;
    procedure Key(AKey: Word; AShift: TShiftState = []);
    procedure TypeIn(const AText: string);
    procedure Enter;
  protected
    function ReadClipboardText: string; override;
    procedure WriteClipboardText(const S: string); override;
  end;

  TTySpinEditTextEngineTest = class(TTestCase)
  private
    FForm: TForm;
    FDone: Integer;
    FDoneValue: Integer;
    function NewSpin(AValue: Integer): TSpinClip;
    procedure OnDone(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestShiftArrowsSelect;
    procedure TestSelTextReplacesTheSelection;
    procedure TestCopyAndCut;
    procedure TestPasteKeepsTheDigits;
    procedure TestPasteKeepsOneLeadingSign;
    procedure TestUndoPutsTheTypedTextBack;
    procedure TestALockedEditorRefusesClipboardAndUndoButCopies;
    procedure TestAReadOnlyFieldRefusesPaste;
    procedure TestEnterCommitsBeforeEditingDone;
    procedure TestPasteEndsTheBlankState;
    procedure TestTextKeepsANonNumberAndCaptionSetsTheValue;
    procedure TestAClickPlacesTheCaret;
    procedure TestAStepStartsFromTheTypedValue;
    procedure TestAButtonPressDoesNotStartASelection;
    procedure TestALongNumberScrollsInsteadOfBeingCut;
  end;

implementation

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

{ TSpinClip }

procedure TSpinClip.Key(AKey: Word; AShift: TShiftState);
var
  k: Word;
begin
  k := AKey;
  KeyDown(k, AShift);
end;

procedure TSpinClip.TypeIn(const AText: string);
var
  i: Integer;
  k: TUTF8Char;
begin
  for i := 1 to Length(AText) do
  begin
    k := AText[i];
    UTF8KeyPress(k);
  end;
end;

procedure TSpinClip.Enter;
begin
  DoEnter;   // the focus from the keyboard: the value is selected
end;

function TSpinClip.ReadClipboardText: string;
begin
  Result := Clip;
end;

procedure TSpinClip.WriteClipboardText(const S: string);
begin
  Clip := S;
end;

{ TTySpinEditTextEngineTest }

procedure TTySpinEditTextEngineTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 200);
  FDone := 0;
  FDoneValue := -1;
end;

procedure TTySpinEditTextEngineTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TTySpinEditTextEngineTest.NewSpin(AValue: Integer): TSpinClip;
begin
  Result := TSpinClip.Create(FForm);
  Result.Parent := FForm;
  Result.SetBounds(0, 0, 120, 26);
  Result.MaxValue := 100000;
  Result.MinValue := -100000;
  Result.Value := AValue;
end;

procedure TTySpinEditTextEngineTest.OnDone(Sender: TObject);
begin
  Inc(FDone);
  FDoneValue := TTySpinEdit(Sender).Value;
end;

procedure TTySpinEditTextEngineTest.TestShiftArrowsSelect;
var
  s: TSpinClip;
begin
  s := NewSpin(1234);
  s.CaretPos := 4;
  s.Key(VK_LEFT, [ssShift]);
  s.Key(VK_LEFT, [ssShift]);
  AssertEquals('two digits selected', 2, s.SelLength);
  AssertEquals('from the third', 2, s.SelStart);
  AssertEquals('34', s.SelText);
  s.TypeIn('9');
  AssertEquals('a digit replaces the selection', '129', s.Text);
end;

procedure TTySpinEditTextEngineTest.TestSelTextReplacesTheSelection;
var
  s: TSpinClip;
begin
  s := NewSpin(1234);
  s.SelStart := 1;
  s.SelLength := 2;
  AssertEquals('23', s.SelText);
  s.SelText := '0';
  AssertEquals('104', s.Text);
  AssertEquals('not committed yet', 1234, s.Value);
end;

procedure TTySpinEditTextEngineTest.TestCopyAndCut;
var
  s: TSpinClip;
begin
  s := NewSpin(1234);
  s.SelStart := 0;
  s.SelLength := 2;
  s.Key(VK_C, [ssCtrl]);
  AssertEquals('copied', '12', s.Clip);
  AssertEquals('copy leaves the text', '1234', s.Text);
  s.Key(VK_X, [ssCtrl]);
  AssertEquals('cut', '12', s.Clip);
  AssertEquals('cut takes it out', '34', s.Text);
  AssertTrue('the user changed it', s.Modified);
end;

procedure TTySpinEditTextEngineTest.TestPasteKeepsTheDigits;
var
  s: TSpinClip;
begin
  s := NewSpin(0);
  s.SelectAll;
  s.Clip := '1,234 px';
  s.Key(VK_V, [ssCtrl]);
  AssertEquals('what is not a digit is dropped', '1234', s.Text);
  s.EditingDone;
  AssertEquals('and it commits as a number', 1234, s.Value);
end;

procedure TTySpinEditTextEngineTest.TestPasteKeepsOneLeadingSign;
var
  s: TSpinClip;
begin
  s := NewSpin(55);
  s.CaretPos := 1;
  s.Clip := '-7';
  s.Key(VK_V, [ssCtrl]);
  AssertEquals('no sign in the middle', '575', s.Text);
  s.CaretPos := 0;
  s.Clip := '-8-';
  s.Key(VK_V, [ssCtrl]);
  AssertEquals('one sign, at the start', '-8575', s.Text);
  s.CaretPos := 0;
  s.Clip := '-';
  s.Key(VK_V, [ssCtrl]);
  AssertEquals('never a second one', '-8575', s.Text);
end;

procedure TTySpinEditTextEngineTest.TestUndoPutsTheTypedTextBack;
var
  s: TSpinClip;
begin
  s := NewSpin(42);
  s.CaretPos := 2;
  s.TypeIn('7');
  AssertEquals('427', s.Text);
  s.Key(VK_Z, [ssCtrl]);
  AssertEquals('undone', '42', s.Text);
end;

procedure TTySpinEditTextEngineTest.TestALockedEditorRefusesClipboardAndUndoButCopies;
var
  s: TSpinClip;
begin
  s := NewSpin(1234);
  s.EditorEnabled := False;
  s.SelStart := 0;
  s.SelLength := 2;
  s.Clip := '9';
  s.Key(VK_V, [ssCtrl]);
  s.Key(VK_X, [ssCtrl]);
  s.Key(VK_BACK);
  s.Key(VK_DELETE);
  s.TypeIn('5');
  AssertEquals('nothing changes the text', '1234', s.Text);
  AssertEquals('and the selection is still there', 2, s.SelLength);
  s.Key(VK_C, [ssCtrl]);
  AssertEquals('copying still works', '12', s.Clip);
  s.Key(VK_LEFT, [ssShift]);
  AssertEquals('and so does selecting', 1, s.SelLength);
  s.Key(VK_UP);
  AssertEquals('and stepping', 1235, s.Value);
end;

procedure TTySpinEditTextEngineTest.TestAReadOnlyFieldRefusesPaste;
var
  s: TSpinClip;
begin
  s := NewSpin(12);
  s.ReadOnly := True;
  s.SelectAll;
  s.Clip := '99';
  s.Key(VK_V, [ssCtrl]);
  AssertEquals('12', s.Text);
end;

procedure TTySpinEditTextEngineTest.TestEnterCommitsBeforeEditingDone;
var
  s: TSpinClip;
begin
  s := NewSpin(42);
  s.OnEditingDone := @OnDone;
  s.Enter;
  s.TypeIn('77');
  AssertEquals('typed, not committed', 42, s.Value);
  s.Key(VK_RETURN);
  AssertEquals('Enter commits', 77, s.Value);
  AssertEquals('one OnEditingDone', 1, FDone);
  AssertEquals('which sees the committed value', 77, FDoneValue);
end;

procedure TTySpinEditTextEngineTest.TestPasteEndsTheBlankState;
var
  s: TSpinClip;
begin
  s := NewSpin(5);
  s.ValueEmpty := True;
  AssertEquals('blank', '', s.Text);
  s.Clip := '8';
  s.Key(VK_V, [ssCtrl]);
  AssertFalse('pasting is input: the field holds a number again', s.ValueEmpty);
  s.EditingDone;
  AssertEquals(8, s.Value);
  AssertEquals('8', s.Text);
end;

procedure TTySpinEditTextEngineTest.TestTextKeepsANonNumberAndCaptionSetsTheValue;
var
  s: TSpinClip;
begin
  s := NewSpin(3);
  s.Text := 'n/a';
  AssertEquals('kept verbatim', 'n/a', s.Text);
  AssertEquals('the value stays', 3, s.Value);
  s.Text := '17';
  AssertEquals('a number sets the value', 17, s.Value);
  TControl(s).Caption := '21';
  AssertEquals('so does Caption', 21, s.Value);
  AssertEquals('21', s.Text);
end;

procedure TTySpinEditTextEngineTest.TestAClickPlacesTheCaret;
var
  s: TSpinClip;
  x: Integer;
begin
  s := NewSpin(1234);
  s.Enter;   // focused, the value selected: a first click into an unfocused edit selects it all (AutoSelect)
  { between the 1 and the 2: the caret goes where the click landed }
  x := s.CaretPixelXAt(1, 96) + 1;
  s.MouseDown(mbLeft, [], x, 13);
  s.MouseUp(mbLeft, [], x, 13);
  AssertEquals(1, s.CaretPos);
  AssertEquals('and the selection is gone', 0, s.SelLength);
end;

{ #160 (main): the arrows, the wheel and the buttons step from what is typed, not from the
  value it has not committed yet -- value 5, type 40, Up gives 41. }
procedure TTySpinEditTextEngineTest.TestAStepStartsFromTheTypedValue;
var
  s: TSpinClip;
  r: TRect;
begin
  s := NewSpin(5);
  s.Enter;
  s.TypeIn('40');
  s.Key(VK_UP);
  AssertEquals('the arrow key', 41, s.Value);
  s.Enter;
  s.TypeIn('70');
  s.DoMouseWheel([], -120, Point(5, 5));
  AssertEquals('the wheel', 69, s.Value);
  s.Enter;
  s.TypeIn('20');
  r := s.UpButtonRect(96);
  s.MouseDown(mbLeft, [], (r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  s.MouseUp(mbLeft, [], (r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('the button', 21, s.Value);
  AssertEquals('21', s.Text);
end;

{ A press on a spin button is the button's: dragging from it over the digits selects nothing,
  as the press never reached the edit's caret-and-drag handling. }
procedure TTySpinEditTextEngineTest.TestAButtonPressDoesNotStartASelection;
var
  s: TSpinClip;
  r: TRect;
  cy: Integer;
begin
  s := NewSpin(1234);
  s.Enter;
  r := s.UpButtonRect(96);
  cy := (r.Top + r.Bottom) div 2;
  s.MouseDown(mbLeft, [], (r.Left + r.Right) div 2, cy);
  s.MouseMove([ssLeft], s.CaretPixelXAt(1, 96), cy);
  s.MouseUp(mbLeft, [], s.CaretPixelXAt(1, 96), cy);
  AssertEquals('stepped once', 1235, s.Value);
  AssertEquals('and nothing is selected', 0, s.SelLength);
end;

{ #160 (main): a number longer than the field scrolls with the caret, as in an edit, instead of
  being cut with an ellipsis and the caret drawn outside it. }
procedure TTySpinEditTextEngineTest.TestALongNumberScrollsInsteadOfBeingCut;
var
  s: TSpinClip;
begin
  s := NewSpin(0);
  s.MaxValue := 0;
  s.MinValue := 0;   // no limit
  s.Enter;
  s.TypeIn('123456789012345678');
  AssertEquals('every digit is there', '123456789012345678', s.Text);
  AssertTrue('the text scrolled so the caret stays in view', s.ScrollX > 0);
  AssertTrue('the caret is inside the text area',
    s.CaretDrawX(96) - s.ScrollX <= s.UpButtonRect(96).Left);
end;

initialization
  RegisterTest(TTySpinEditTextEngineTest);
end.
