unit test.parity.numeric;
{ LCL parity guards for the five numeric controls: TTySpinEdit, TTyUpDown,
  TTyTrackBar, TTyProgressBar, TTyScrollBar.

  Every guard here was watched RED before its fix shipped -- the behaviour changes
  against the pre-fix source, the added members against a deliberately broken build
  (a member cannot be asserted absent in a language that will not compile the call).
  The mutants are recorded in the commit message. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller,
  tyControls.SpinEdit, tyControls.UpDown, tyControls.TrackBar,
  tyControls.ProgressBar, tyControls.ScrollBar;

type
  { --- probes: the protected input/paint seams these controls keep to themselves --- }

  TSpinProbe = class(TTySpinEdit)
  public
    procedure TypeChar(const C: TUTF8Char);
    procedure DoKey(K: Word);
    function Buffer: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Preferred(out AW, AH: Integer);
    function WheelUp: Boolean;
  end;

  { A descendant that changes the number rules through the three public seams, which is
    the whole point of their being virtual. }
  TSpinHexProbe = class(TSpinProbe)
  public
    function ValueToStr(const AValue: Integer): string; override;
    function StrToValue(const S: string): Integer; override;
    function GetLimitedValue(const AValue: Integer): Integer; override;
  end;

  TUpDownArrowProbe = class(TTyUpDown)
  public
    procedure PressUp;
    procedure PressDown;
  end;

  TTrackProbe = class(TTyTrackBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Preferred(out AW, AH: Integer);
  end;

  TProgressProbe = class(TTyProgressBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TScrollProbe = class(TTyScrollBar)
  public
    procedure DoKey(K: Word);
  end;

  TCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  { --- 1. TTySpinEdit: the fresh control's range contract (claim 16) --- }
  TSpinDefaultRangeTest = class(TTestCase)
  published
    procedure FreshMaxValueIsZero;
    procedure FreshControlDoesNotClampATypedNumber;
    procedure AnExplicitRangeStillClamps;
  end;

  { --- 2. TTySpinEdit: EditorEnabled vs ReadOnly (claim 14) --- }
  TSpinEditorEnabledTest = class(TTestCase)
  published
    procedure DefaultsToTrue;
    procedure FalseBlocksTypingButKeepsTheArrows;
    procedure FalseBlocksBackspaceAndDelete;
    procedure ReadOnlyStillBlocksBothWays;
  end;

  { --- 3. TTySpinEdit: Text, CaretPos, Modified, ValueEmpty, TextHint (17/24/25/26/15) --- }
  TSpinEditorStateTest = class(TTestCase)
  published
    procedure TextReadsTheUncommittedBuffer;
    procedure TextWriteOfANumberSetsValue;
    procedure TextWriteOfNonNumberIsKeptVerbatim;
    procedure CaretPosReadsAndWritesClamped;
    procedure ModifiedIsFalseUntilTheUserTypes;
    procedure ModifiedClearedByAProgrammaticWrite;
    procedure ModifiedSetByAnArrowStep;
    procedure ModifiedSurvivesTheCommit;
    procedure ValueEmptyBlanksTheField;
    procedure ValueEmptyIsClearedByTyping;
    procedure ValueEmptyIsClearedByAValueMove;
    procedure TextHintPaintsWhileBlank;
  end;

  { --- 4. TTySpinEdit: the three virtual seams (claim 27) --- }
  TSpinSeamTest = class(TTestCase)
  published
    procedure ValueToStrDrivesTheDisplay;
    procedure StrToValueDrivesTheParse;
    procedure GetLimitedValueDrivesTheClamp;
  end;

  { --- 5. TTySpinEdit: AutoSize has something to ask (claim 45) --- }
  TSpinPreferredSizeTest = class(TTestCase)
  published
    procedure HeightOnlyAndFollowsTheThemeFont;
  end;

  { --- 6. TTyUpDown: what the arrow handler is allowed to read (claim 34) --- }
  TUpDownArrowOrderTest = class(TTestCase)
  private
    FSeenPos: Integer;
    FSeenBtn: TTyUpDownButton;
    FClicks: Integer;
    procedure HandleArrow(Sender: TObject; AButton: TTyUpDownButton);
  published
    procedure ArrowClickSeesTheNewPosition;
    procedure ArrowClickStillFiresWhenPinned;
  end;

  { --- 7. TTyUpDown: the veto (claims 28, 29) --- }
  TUpDownVetoTest = class(TTestCase)
  private
    FAllow: Boolean;
    FCeiling: Integer;
    FSeenValue: Integer;
    FSeenDir: TTyUpDownDirection;
    FExCalls, FChanges, FClicks: Integer;
    procedure Veto(Sender: TObject; var AAllowChange: Boolean);
    procedure VetoEx(Sender: TObject; var AAllowChange: Boolean;
      ANewValue: Integer; ADirection: TTyUpDownDirection);
    procedure CountChange(Sender: TObject);
    procedure CountClick(Sender: TObject; AButton: TTyUpDownButton);
  published
    procedure RefusedStepDoesNotMove;
    procedure RefusedStepAnnouncesNothing;
    procedure AllowedStepStillMoves;
    procedure ChangingExSeesTheProposedValueAndDirection;
    procedure ChangingExCanRefuseOneValueOnly;
    procedure AProgrammaticWriteIsNotAProposal;
  end;

  { --- 8. TTyUpDown: MinRepeatInterval (claim 32) --- }
  TUpDownRepeatTest = class(TTestCase)
  published
    procedure DefaultMatchesLCL;
    procedure ClampedUpToTwentyFive;
  end;

  { --- 9. TTyTrackBar: Reversed (claim 5) --- }
  TTrackReversedTest = class(TTestCase)
  published
    procedure DefaultsFalse;
    procedure ReversedHorizontalPutsMinOnTheRight;
    procedure ReversedVerticalPutsMinOnTop;
    procedure ReversedDragAgrees;
  end;

  { --- 10. TTyTrackBar: TickStyle / TickMarks (claims 7, 8) --- }
  TTrackTickTest = class(TTestCase)
  published
    procedure DefaultsMatchLCL;
    procedure TickStyleNoneDrawsNothing;
    procedure TickStyleManualDrawsOnlyPlacedTicks;
    procedure SetTickRejectsOutOfRangeAndDuplicates;
    procedure ClearTicksEmptiesTheList;
    procedure TickMarksTopLeftMovesTheInk;
    procedure TickMarksBothDrawsTwoSides;
  end;

  { --- 11. TTyTrackBar: AutoSize has something to ask (claim 42) --- }
  TTrackPreferredSizeTest = class(TTestCase)
  published
    procedure CrossAxisOnlyHorizontal;
    procedure CrossAxisOnlyVertical;
  end;

  { --- 12. TTyProgressBar: Step / StepIt / StepBy (claim 9) --- }
  TProgressStepTest = class(TTestCase)
  published
    procedure StepDefaultsToTen;
    procedure StepItAdvancesByStep;
    procedure StepItClampsAtMax;
    procedure StepItNotifies;
    procedure StepByUsesItsOwnDelta;
  end;

  { --- 13. TTyProgressBar: all four fill directions (claim 13) --- }
  TProgressDirectionTest = class(TTestCase)
  published
    procedure RightToLeftFillsFromTheRight;
    procedure TopDownFillsFromTheTop;
    procedure FullAndEmptyStayCorrectInEveryDirection;
  end;

  { --- 14. TTyProgressBar: BarShowText (claim 10) --- }
  TProgressTextTest = class(TTestCase)
  published
    procedure DefaultsOff;
    procedure BarTextFillsTheTemplate;
    procedure BarTextHandlesADegenerateRange;
    procedure BarShowTextPaintsInk;
  end;

  { --- 15. TTyScrollBar: LargeChange (claim 4) --- }
  TScrollLargeChangeTest = class(TTestCase)
  published
    procedure DefaultFollowsPageSize;
    procedure SetLargeChangePagesByItself;
    procedure ThumbSizeStillFollowsPageSizeAlone;
    procedure NegativeFallsBackToPageSize;
  end;

implementation

const
  { A theme with a white face and black ink, so "is there ink here" is a real question.
    Colours live in the test, never in the control. }
  cInkTheme =
    'TyTrackBar { background: #FFFFFF; color: #000000; border-width: 0px; border-radius: 0px; }' +
    'TyTrackThumb { background: #FFFFFF; border-radius: 0px; }' +
    'TyProgressBar { background: #FFFFFF; color: #000000; border-width: 0px; border-radius: 0px; }' +
    'TyProgressFill { background: #FFFFFF; border-radius: 0px; }' +
    'TySpinEdit { background: #FFFFFF; color: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTextHint { color: #000000; }';

{ True when the rectangle holds any pixel darker than near-white. }
function HasInk(ABmp: TBitmap; const AZone: TRect): Boolean;
var
  reread: TBGRABitmap;
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  reread := TBGRABitmap.Create(ABmp);
  try
    for x := AZone.Left to AZone.Right - 1 do
      for y := AZone.Top to AZone.Bottom - 1 do
      begin
        px := reread.GetPixel(x, y);
        if (px.red < 200) or (px.green < 200) or (px.blue < 200) then
          Exit(True);
      end;
  finally
    reread.Free;
  end;
end;

function WhiteCanvas(AW, AH: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(0, 0, AW, AH);
end;

procedure TCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

{ --- probes --- }

procedure TSpinProbe.TypeChar(const C: TUTF8Char);
var K: TUTF8Char;
begin
  K := C;
  UTF8KeyPress(K);
end;

procedure TSpinProbe.DoKey(K: Word);
var W: Word;
begin
  W := K;
  KeyDown(W, []);
end;

function TSpinProbe.Buffer: string;
begin
  Result := FEditText;
end;

procedure TSpinProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TSpinProbe.Preferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, False);
end;

function TSpinProbe.WheelUp: Boolean;
begin
  Result := DoMouseWheel([], 120, Point(0, 0));
end;

function TSpinHexProbe.ValueToStr(const AValue: Integer): string;
begin
  Result := 'x' + IntToHex(GetLimitedValue(AValue), 2);
end;

function TSpinHexProbe.StrToValue(const S: string): Integer;
var
  T: string;
begin
  T := Trim(S);
  if (T <> '') and (T[1] = 'x') then T := Copy(T, 2, MaxInt);
  Result := GetLimitedValue(StrToIntDef('$' + T, Value));
end;

function TSpinHexProbe.GetLimitedValue(const AValue: Integer): Integer;
begin
  // Snap to multiples of 4 on top of whatever the base class enforces.
  Result := (inherited GetLimitedValue(AValue) div 4) * 4;
end;

procedure TUpDownArrowProbe.PressUp;
begin
  MouseDown(mbLeft, [], ClientWidth div 2, 2);
  MouseUp(mbLeft, [], ClientWidth div 2, 2);
end;

procedure TUpDownArrowProbe.PressDown;
begin
  MouseDown(mbLeft, [], ClientWidth div 2, ClientHeight - 2);
  MouseUp(mbLeft, [], ClientWidth div 2, ClientHeight - 2);
end;

procedure TTrackProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTrackProbe.Preferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, False);
end;

procedure TProgressProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TScrollProbe.DoKey(K: Word);
var W: Word;
begin
  W := K;
  KeyDown(W, []);
end;

{ --- 1 --- }

procedure TSpinDefaultRangeTest.FreshMaxValueIsZero;
var S: TTySpinEdit;
begin
  S := TTySpinEdit.Create(nil);
  try
    AssertEquals('fresh MinValue', 0, S.MinValue);
    AssertEquals('fresh MaxValue (LCL spin.pp DefMaxValue = 0 == unbounded)', 0, S.MaxValue);
  finally S.Free; end;
end;

procedure TSpinDefaultRangeTest.FreshControlDoesNotClampATypedNumber;
var S: TTySpinEdit;
begin
  S := TTySpinEdit.Create(nil);
  try
    S.Value := 5000;
    AssertEquals('a fresh spin edit is unbounded, so 5000 survives', 5000, S.Value);
  finally S.Free; end;
end;

procedure TSpinDefaultRangeTest.AnExplicitRangeStillClamps;
var S: TTySpinEdit;
begin
  S := TTySpinEdit.Create(nil);
  try
    S.MinValue := 0;
    S.MaxValue := 100;
    S.Value := 5000;
    AssertEquals('an explicit range is still honoured', 100, S.Value);
  finally S.Free; end;
end;

{ --- 2 --- }

procedure TSpinEditorEnabledTest.DefaultsToTrue;
var S: TTySpinEdit;
begin
  S := TTySpinEdit.Create(nil);
  try
    AssertTrue('LCL spin.pp:79 default True', S.EditorEnabled);
  finally S.Free; end;
end;

procedure TSpinEditorEnabledTest.FalseBlocksTypingButKeepsTheArrows;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 10;
    S.EditorEnabled := False;
    S.TypeChar('7');
    AssertEquals('the keyboard is locked', '10', S.Buffer);
    S.DoKey(VK_UP);
    AssertEquals('the arrows are not', 11, S.Value);
    AssertTrue('and neither is the wheel', S.WheelUp);
    AssertEquals('wheel stepped', 12, S.Value);
  finally S.Free; end;
end;

procedure TSpinEditorEnabledTest.FalseBlocksBackspaceAndDelete;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.Value := 123;
    S.EditorEnabled := False;
    S.DoKey(VK_BACK);
    AssertEquals('backspace blocked', '123', S.Buffer);
    S.CaretPos := 0;
    S.DoKey(VK_DELETE);
    AssertEquals('delete blocked', '123', S.Buffer);
  finally S.Free; end;
end;

procedure TSpinEditorEnabledTest.ReadOnlyStillBlocksBothWays;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 10;
    S.ReadOnly := True;
    S.TypeChar('7');
    AssertEquals('typing blocked', '10', S.Buffer);
    S.DoKey(VK_UP);
    AssertEquals('and so is stepping (win32wsspin.pp:274)', 10, S.Value);
  finally S.Free; end;
end;

{ --- 3 --- }

procedure TSpinEditorStateTest.TextReadsTheUncommittedBuffer;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.Value := 12;
    S.TypeChar('9');
    AssertEquals('typed but not committed', '129', S.Text);
    AssertEquals('Value has not moved yet', 12, S.Value);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.TextWriteOfANumberSetsValue;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100;
    S.Text := '42';
    AssertEquals('parsed into Value', 42, S.Value);
    AssertEquals('and re-rendered', '42', S.Buffer);
    S.Text := '900';
    AssertEquals('clamped on the way in', 100, S.Value);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.TextWriteOfNonNumberIsKeptVerbatim;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.Value := 7;
    S.Text := '--';
    AssertEquals('kept as typed (LCL spinedit.inc:64-67)', '--', S.Text);
    AssertEquals('Value untouched', 7, S.Value);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.CaretPosReadsAndWritesClamped;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.Value := 1234;
    AssertEquals('caret parks at the end after a value write', 4, S.CaretPos);
    S.CaretPos := 2;
    AssertEquals('settable', 2, S.CaretPos);
    S.CaretPos := 99;
    AssertEquals('clamped to the buffer length', 4, S.CaretPos);
    S.CaretPos := -5;
    AssertEquals('and to zero', 0, S.CaretPos);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.ModifiedIsFalseUntilTheUserTypes;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    AssertFalse('fresh control is clean', S.Modified);
    S.TypeChar('5');
    AssertTrue('a typed digit dirties it', S.Modified);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.ModifiedClearedByAProgrammaticWrite;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.TypeChar('5');
    AssertTrue('dirty', S.Modified);
    S.Value := 3;
    AssertFalse('the code wrote it, so the user did not', S.Modified);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.ModifiedSetByAnArrowStep;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 5;
    AssertFalse('clean after the setup write', S.Modified);
    S.DoKey(VK_UP);
    AssertTrue('the arrows are the user editing too', S.Modified);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.ModifiedSurvivesTheCommit;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 5;
    S.TypeChar('9');
    S.DoKey(VK_RETURN);       // commit
    AssertEquals('committed', 59, S.Value);
    AssertTrue('finishing an edit is not the code overwriting the field', S.Modified);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.ValueEmptyBlanksTheField;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.Value := 17;
    AssertFalse('default', S.ValueEmpty);
    S.ValueEmpty := True;
    AssertEquals('blank, not "0"', '', S.Buffer);
    AssertEquals('the value itself is untouched', 17, S.Value);
    S.ValueEmpty := False;
    AssertEquals('and comes back', '17', S.Buffer);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.ValueEmptyIsClearedByTyping;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.ValueEmpty := True;
    S.TypeChar('4');
    AssertFalse('real input ends the blank state (LCL spinedit.inc:76)', S.ValueEmpty);
    AssertEquals('4', S.Buffer);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.ValueEmptyIsClearedByAValueMove;
var S: TSpinProbe;
begin
  S := TSpinProbe.Create(nil);
  try
    S.ValueEmpty := True;
    S.Value := 9;
    AssertFalse('a number was written, so there is one to show', S.ValueEmpty);
    AssertEquals('9', S.Buffer);
  finally S.Free; end;
end;

procedure TSpinEditorStateTest.TextHintPaintsWhileBlank;

  function Painted(const AHint: string): Boolean;
  var
    Ctl: TTyStyleController;
    S: TSpinProbe;
    bmp: TBitmap;
  begin
    Ctl := TTyStyleController.Create(nil);
    S := TSpinProbe.Create(nil);
    bmp := WhiteCanvas(120, 28);
    try
      Ctl.LoadThemeCss(cInkTheme);
      S.Controller := Ctl;
      S.Font.PixelsPerInch := 96;
      S.SetBounds(0, 0, 120, 28);
      S.TextHint := AHint;
      S.ValueEmpty := True;      // nothing to show but the hint
      S.RenderTo(bmp.Canvas, Rect(0, 0, 120, 28), 96);
      // Left of the spin buttons only, so the arrow glyphs cannot answer for the hint.
      Result := HasInk(bmp, Rect(0, 0, 90, 28));
    finally
      bmp.Free; S.Free; Ctl.Free;
    end;
  end;

begin
  AssertFalse('nothing drawn without a hint', Painted(''));
  AssertTrue('the hint is drawn in the muted TyTextHint ink', Painted('year'));
end;

{ --- 4 --- }

procedure TSpinSeamTest.ValueToStrDrivesTheDisplay;
var S: TSpinHexProbe;
begin
  S := TSpinHexProbe.Create(nil);
  try
    S.Value := 32;
    AssertEquals('the descendant formats the buffer', 'x20', S.Buffer);
  finally S.Free; end;
end;

procedure TSpinSeamTest.StrToValueDrivesTheParse;
var S: TSpinHexProbe;
begin
  S := TSpinHexProbe.Create(nil);
  try
    S.Value := 0;
    S.TypeChar('4');
    S.TypeChar('0');
    S.DoKey(VK_RETURN);
    AssertEquals('the descendant parses the buffer as hex', 64, S.Value);
  finally S.Free; end;
end;

procedure TSpinSeamTest.GetLimitedValueDrivesTheClamp;
var S: TSpinHexProbe;
begin
  S := TSpinHexProbe.Create(nil);
  try
    S.Value := 7;
    AssertEquals('the descendant snaps the value', 4, S.Value);
  finally S.Free; end;
end;

{ --- 5 --- }

procedure TSpinPreferredSizeTest.HeightOnlyAndFollowsTheThemeFont;
var
  Ctl: TTyStyleController;
  S: TSpinProbe;
  w1, h1, w2, h2: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  S := TSpinProbe.Create(nil);
  try
    Ctl.LoadThemeCss('TySpinEdit { font-size: 9px; padding: 2px; border-width: 1px; }');
    S.Controller := Ctl;
    S.Font.PixelsPerInch := 96;
    S.Preferred(w1, h1);
    AssertEquals('width is the form author''s (0 == no preference)', 0, w1);
    AssertTrue('a height is proposed', h1 > 0);
    Ctl.LoadThemeCss('TySpinEdit { font-size: 24px; padding: 2px; border-width: 1px; }');
    S.Preferred(w2, h2);
    AssertTrue('a bigger theme font asks for a taller field: '
      + IntToStr(h1) + ' -> ' + IntToStr(h2), h2 > h1);
  finally
    S.Free; Ctl.Free;
  end;
end;

{ --- 6 --- }

procedure TUpDownArrowOrderTest.HandleArrow(Sender: TObject; AButton: TTyUpDownButton);
begin
  Inc(FClicks);
  FSeenPos := TTyUpDown(Sender).Position;
  FSeenBtn := AButton;
end;

procedure TUpDownArrowOrderTest.ArrowClickSeesTheNewPosition;
var UD: TUpDownArrowProbe;
begin
  UD := TUpDownArrowProbe.Create(nil);
  try
    UD.Min := 0; UD.Max := 10; UD.Position := 4; UD.Increment := 1;
    FClicks := 0; FSeenPos := -1;
    UD.OnArrowClick := @HandleArrow;
    UD.PressUp;
    AssertEquals('the arrow handler ran', 1, FClicks);
    AssertEquals('LCL fires OnClick AFTER Position moves (customupdown.inc:372)',
      5, FSeenPos);
    AssertEquals('direction still carried', Ord(udbNext), Ord(FSeenBtn));
  finally UD.Free; end;
end;

procedure TUpDownArrowOrderTest.ArrowClickStillFiresWhenPinned;
var UD: TUpDownArrowProbe;
begin
  UD := TUpDownArrowProbe.Create(nil);
  try
    UD.Min := 0; UD.Max := 10; UD.Position := 10;
    FClicks := 0; FSeenPos := -1;
    UD.OnArrowClick := @HandleArrow;
    UD.PressUp;
    AssertEquals('a press that moves nothing is still a press', 1, FClicks);
    AssertEquals('and it reports the (unmoved) position', 10, FSeenPos);
  finally UD.Free; end;
end;

{ --- 7 --- }

procedure TUpDownVetoTest.Veto(Sender: TObject; var AAllowChange: Boolean);
begin
  AAllowChange := FAllow;
end;

procedure TUpDownVetoTest.VetoEx(Sender: TObject; var AAllowChange: Boolean;
  ANewValue: Integer; ADirection: TTyUpDownDirection);
begin
  Inc(FExCalls);
  FSeenValue := ANewValue;
  FSeenDir := ADirection;
  if (FCeiling > 0) and (ANewValue > FCeiling) then AAllowChange := False;
end;

procedure TUpDownVetoTest.CountChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TUpDownVetoTest.CountClick(Sender: TObject; AButton: TTyUpDownButton);
begin
  Inc(FClicks);
end;

procedure TUpDownVetoTest.RefusedStepDoesNotMove;
var UD: TUpDownArrowProbe;
begin
  UD := TUpDownArrowProbe.Create(nil);
  try
    UD.Min := 0; UD.Max := 10; UD.Position := 4;
    FAllow := False;
    UD.OnChanging := @Veto;
    UD.PressUp;
    AssertEquals('the handler refused', 4, UD.Position);
  finally UD.Free; end;
end;

procedure TUpDownVetoTest.RefusedStepAnnouncesNothing;
var UD: TUpDownArrowProbe;
begin
  UD := TUpDownArrowProbe.Create(nil);
  try
    UD.Min := 0; UD.Max := 10; UD.Position := 4;
    FAllow := False; FChanges := 0; FClicks := 0;
    UD.OnChanging := @Veto;
    UD.OnChange := @CountChange;
    UD.OnArrowClick := @CountClick;
    UD.PressUp;
    AssertEquals('a refused step is not a change', 0, FChanges);
    AssertEquals('and not a press either (LCL: customupdown.inc:369 exits first)', 0, FClicks);
  finally UD.Free; end;
end;

procedure TUpDownVetoTest.AllowedStepStillMoves;
var UD: TUpDownArrowProbe;
begin
  UD := TUpDownArrowProbe.Create(nil);
  try
    UD.Min := 0; UD.Max := 10; UD.Position := 4;
    FAllow := True; FChanges := 0; FClicks := 0;
    UD.OnChanging := @Veto;
    UD.OnChange := @CountChange;
    UD.OnArrowClick := @CountClick;
    UD.PressUp;
    AssertEquals('moved', 5, UD.Position);
    AssertEquals('announced once', 1, FChanges);
    AssertEquals('and pressed once', 1, FClicks);
  finally UD.Free; end;
end;

procedure TUpDownVetoTest.ChangingExSeesTheProposedValueAndDirection;
var UD: TUpDownArrowProbe;
begin
  UD := TUpDownArrowProbe.Create(nil);
  try
    UD.Min := 0; UD.Max := 10; UD.Position := 4; UD.Increment := 3;
    FCeiling := 0; FExCalls := 0; FSeenValue := -1;
    UD.OnChangingEx := @VetoEx;
    UD.PressUp;
    AssertEquals('asked once', 1, FExCalls);
    AssertEquals('the value the step WOULD land on', 7, FSeenValue);
    AssertEquals('heading up', Ord(uddUp), Ord(FSeenDir));
    UD.PressDown;
    AssertEquals('and the other way', Ord(uddDown), Ord(FSeenDir));
    AssertEquals('with its own proposal', 4, FSeenValue);
  finally UD.Free; end;
end;

procedure TUpDownVetoTest.ChangingExCanRefuseOneValueOnly;
var UD: TUpDownArrowProbe;
begin
  UD := TUpDownArrowProbe.Create(nil);
  try
    UD.Min := 0; UD.Max := 10; UD.Position := 4;
    FCeiling := 6;
    UD.OnChangingEx := @VetoEx;
    UD.PressUp;
    AssertEquals('5 is under the ceiling', 5, UD.Position);
    UD.PressUp;
    AssertEquals('6 is the ceiling', 6, UD.Position);
    UD.PressUp;
    AssertEquals('7 is refused, and refusing does not push it back', 6, UD.Position);
  finally UD.Free; end;
end;

procedure TUpDownVetoTest.AProgrammaticWriteIsNotAProposal;
var UD: TUpDownArrowProbe;
begin
  UD := TUpDownArrowProbe.Create(nil);
  try
    UD.Min := 0; UD.Max := 10; UD.Position := 4;
    FAllow := False;
    UD.OnChanging := @Veto;
    UD.Position := 9;
    AssertEquals('code instructs, it does not ask (LCL: SetPosition never calls CanChange)',
      9, UD.Position);
  finally UD.Free; end;
end;

{ --- 8 --- }

procedure TUpDownRepeatTest.DefaultMatchesLCL;
var UD: TTyUpDown;
begin
  UD := TTyUpDown.Create(nil);
  try
    AssertEquals('customupdown.inc:226', 100, UD.MinRepeatInterval);
  finally UD.Free; end;
end;

procedure TUpDownRepeatTest.ClampedUpToTwentyFive;
var UD: TTyUpDown;
begin
  UD := TTyUpDown.Create(nil);
  try
    UD.MinRepeatInterval := 5;
    AssertEquals('floor, as in customupdown.inc:669', 25, UD.MinRepeatInterval);
    UD.MinRepeatInterval := 250;
    AssertEquals('a slower repeat is honoured as-is', 250, UD.MinRepeatInterval);
  finally UD.Free; end;
end;

{ --- 9 --- }

procedure TTrackReversedTest.DefaultsFalse;
var T: TTyTrackBar;
begin
  T := TTyTrackBar.Create(nil);
  try
    AssertFalse('comctrls.pp:2789 default False', T.Reversed);
  finally T.Free; end;
end;

procedure TTrackReversedTest.ReversedHorizontalPutsMinOnTheRight;
var T: TTyTrackBar;
begin
  T := TTyTrackBar.Create(nil);
  try
    T.Font.PixelsPerInch := 96;
    T.SetBounds(0, 0, 160, 24);
    T.Min := 0; T.Max := 100; T.Position := 0;
    AssertEquals('un-reversed: Min at the left', 0, T.ThumbRect.Left);
    T.Reversed := True;
    AssertEquals('reversed: Min at the right', 160 - 12, T.ThumbRect.Left);
  finally T.Free; end;
end;

procedure TTrackReversedTest.ReversedVerticalPutsMinOnTop;
var T: TTyTrackBar;
begin
  T := TTyTrackBar.Create(nil);
  try
    T.Font.PixelsPerInch := 96;
    T.SetBounds(0, 0, 24, 160);
    T.Orientation := toVertical;
    T.Min := 0; T.Max := 100; T.Position := 0;
    AssertEquals('un-reversed vertical: Max on top, so Min sits at the bottom',
      160 - 12, T.ThumbRect.Top);
    T.Reversed := True;
    AssertEquals('reversed vertical: Min on top', 0, T.ThumbRect.Top);
  finally T.Free; end;
end;

procedure TTrackReversedTest.ReversedDragAgrees;
var T: TTyTrackBar;
begin
  T := TTyTrackBar.Create(nil);
  try
    T.Font.PixelsPerInch := 96;
    T.SetBounds(0, 0, 160, 24);
    T.Min := 0; T.Max := 100; T.Reversed := True;
    T.DragTo(6);                 // the far left, thumb-centred
    AssertEquals('dragging left now means Max', 100, T.Position);
    T.DragTo(154);
    AssertEquals('and right means Min', 0, T.Position);
  finally T.Free; end;
end;

{ --- 10 --- }

{ Renders a 160x40 horizontal bar under the ink theme and reports whether the named
  cross-axis strip picked up any tick ink. }
function TickInk(AConfigure: TNotifyEvent; const AZone: TRect): Boolean;
var
  Ctl: TTyStyleController;
  T: TTrackProbe;
  bmp: TBitmap;
begin
  Ctl := TTyStyleController.Create(nil);
  T := TTrackProbe.Create(nil);
  bmp := WhiteCanvas(160, 40);
  try
    Ctl.LoadThemeCss(cInkTheme);
    T.Controller := Ctl;
    T.Orientation := toHorizontal;
    T.Min := 0; T.Max := 100; T.Frequency := 20;
    T.Font.PixelsPerInch := 96;
    T.SetBounds(0, 0, 160, 40);
    if Assigned(AConfigure) then AConfigure(T);
    T.RenderTo(bmp.Canvas, Rect(0, 0, 160, 40), 96);
    Result := HasInk(bmp, AZone);
  finally
    bmp.Free; T.Free; Ctl.Free;
  end;
end;

type
  { Tiny holder so the tick cases can each hand TickInk a different setup. }
  TTickSetup = class
  public
    Style: TTyTrackTickStyle;
    Marks: TTyTrackTickMark;
    Manual: array of Integer;
    procedure Apply(Sender: TObject);
  end;

procedure TTickSetup.Apply(Sender: TObject);
var
  T: TTyTrackBar;
  i: Integer;
begin
  T := TTyTrackBar(Sender);
  T.TickStyle := Style;
  T.TickMarks := Marks;
  for i := 0 to High(Manual) do T.SetTick(Manual[i]);
end;

procedure TTrackTickTest.DefaultsMatchLCL;
var T: TTyTrackBar;
begin
  T := TTyTrackBar.Create(nil);
  try
    AssertEquals('comctrls.pp:2796', Ord(ttsAuto), Ord(T.TickStyle));
    AssertEquals('comctrls.pp:2795', Ord(ttmBottomRight), Ord(T.TickMarks));
    AssertEquals('no hand-placed ticks yet', 0, T.TickCount);
  finally T.Free; end;
end;

procedure TTrackTickTest.TickStyleNoneDrawsNothing;
var S: TTickSetup;
begin
  S := TTickSetup.Create;
  try
    S.Style := ttsAuto; S.Marks := ttmBottomRight;
    AssertTrue('auto ticks are there to lose', TickInk(@S.Apply, Rect(0, 30, 160, 40)));
    S.Style := ttsNone;
    AssertFalse('ttsNone draws none of them', TickInk(@S.Apply, Rect(0, 30, 160, 40)));
  finally S.Free; end;
end;

procedure TTrackTickTest.TickStyleManualDrawsOnlyPlacedTicks;
var S: TTickSetup;
begin
  S := TTickSetup.Create;
  try
    S.Style := ttsManual; S.Marks := ttmBottomRight;
    AssertFalse('manual with no ticks placed draws nothing',
      TickInk(@S.Apply, Rect(0, 30, 160, 40)));
    SetLength(S.Manual, 1);
    S.Manual[0] := 50;
    AssertTrue('a hand-placed tick is drawn', TickInk(@S.Apply, Rect(0, 30, 160, 40)));
    // ...and only near where it was placed: value 50 lands mid-track, so the far left
    // strip (which the automatic Frequency=20 ticks WOULD have covered) stays clean.
    AssertFalse('and nowhere else', TickInk(@S.Apply, Rect(28, 30, 60, 40)));
  finally S.Free; end;
end;

procedure TTrackTickTest.SetTickRejectsOutOfRangeAndDuplicates;
var T: TTyTrackBar;
begin
  T := TTyTrackBar.Create(nil);
  try
    T.Min := 0; T.Max := 10;
    T.SetTick(5);
    AssertEquals('placed', 1, T.TickCount);
    T.SetTick(5);
    AssertEquals('a tick placed twice is still one tick', 1, T.TickCount);
    T.SetTick(-1);
    T.SetTick(11);
    AssertEquals('outside the range is not a tick', 1, T.TickCount);
  finally T.Free; end;
end;

procedure TTrackTickTest.ClearTicksEmptiesTheList;
var T: TTyTrackBar;
begin
  T := TTyTrackBar.Create(nil);
  try
    T.Min := 0; T.Max := 10;
    T.SetTick(2); T.SetTick(7);
    AssertEquals(2, T.TickCount);
    T.ClearTicks;
    AssertEquals('a tick list you can only add to is a leak', 0, T.TickCount);
  finally T.Free; end;
end;

procedure TTrackTickTest.TickMarksTopLeftMovesTheInk;
var S: TTickSetup;
begin
  S := TTickSetup.Create;
  try
    S.Style := ttsAuto; S.Marks := ttmTopLeft;
    AssertTrue('ticks moved to the top strip', TickInk(@S.Apply, Rect(0, 0, 160, 6)));
    AssertFalse('and left the bottom one', TickInk(@S.Apply, Rect(0, 30, 160, 40)));
  finally S.Free; end;
end;

procedure TTrackTickTest.TickMarksBothDrawsTwoSides;
var S: TTickSetup;
begin
  S := TTickSetup.Create;
  try
    S.Style := ttsAuto; S.Marks := ttmBoth;
    AssertTrue('top', TickInk(@S.Apply, Rect(0, 0, 160, 6)));
    AssertTrue('bottom', TickInk(@S.Apply, Rect(0, 30, 160, 40)));
  finally S.Free; end;
end;

{ --- 11 --- }

procedure TTrackPreferredSizeTest.CrossAxisOnlyHorizontal;
var
  T: TTrackProbe;
  w, h: Integer;
begin
  T := TTrackProbe.Create(nil);
  try
    T.Font.PixelsPerInch := 96;
    T.Orientation := toHorizontal;
    T.Preferred(w, h);
    AssertEquals('the track length is the form author''s', 0, w);
    AssertTrue('the thickness follows the theme''s thumb + ticks', h > 0);
  finally T.Free; end;
end;

procedure TTrackPreferredSizeTest.CrossAxisOnlyVertical;
var
  T: TTrackProbe;
  w, h: Integer;
begin
  T := TTrackProbe.Create(nil);
  try
    T.Font.PixelsPerInch := 96;
    T.Orientation := toVertical;
    T.Preferred(w, h);
    AssertTrue('now the width is the cross axis', w > 0);
    AssertEquals('and the length is left alone', 0, h);
  finally T.Free; end;
end;

{ --- 12 --- }

procedure TProgressStepTest.StepDefaultsToTen;
var P: TTyProgressBar;
begin
  P := TTyProgressBar.Create(nil);
  try
    AssertEquals('comctrls.pp:1853', 10, P.Step);
  finally P.Free; end;
end;

procedure TProgressStepTest.StepItAdvancesByStep;
var P: TTyProgressBar;
begin
  P := TTyProgressBar.Create(nil);
  try
    P.Min := 0; P.Max := 100; P.Position := 0;
    P.StepIt;
    AssertEquals(10, P.Position);
    P.Step := 25;
    P.StepIt;
    AssertEquals(35, P.Position);
  finally P.Free; end;
end;

procedure TProgressStepTest.StepItClampsAtMax;
var P: TTyProgressBar;
begin
  P := TTyProgressBar.Create(nil);
  try
    P.Min := 0; P.Max := 100; P.Position := 95;
    P.StepIt;
    AssertEquals('clamped, as in progressbar.inc:238', 100, P.Position);
  finally P.Free; end;
end;

procedure TProgressStepTest.StepItNotifies;
var
  P: TTyProgressBar;
  C: TCounter;
begin
  P := TTyProgressBar.Create(nil);
  C := TCounter.Create;
  try
    P.Min := 0; P.Max := 100; P.Position := 0;
    P.OnChange := @C.Handle;
    P.StepIt;
    AssertEquals('a step is a position change like any other', 1, C.Count);
  finally P.Free; C.Free; end;
end;

procedure TProgressStepTest.StepByUsesItsOwnDelta;
var P: TTyProgressBar;
begin
  P := TTyProgressBar.Create(nil);
  try
    P.Min := 0; P.Max := 100; P.Position := 10; P.Step := 10;
    P.StepBy(7);
    AssertEquals('StepBy ignores Step', 17, P.Position);
    P.StepBy(-5);
    AssertEquals('and goes backwards', 12, P.Position);
  finally P.Free; end;
end;

{ --- 13 --- }

procedure TProgressDirectionTest.RightToLeftFillsFromTheRight;
var R: TRect;
begin
  R := TyProgressFillRect(Rect(0, 0, 100, 20), 0, 100, 30, tpoRightToLeft);
  AssertEquals('anchored at the right edge', 100, R.Right);
  AssertEquals('and grows leftward', 70, R.Left);
end;

procedure TProgressDirectionTest.TopDownFillsFromTheTop;
var R: TRect;
begin
  R := TyProgressFillRect(Rect(0, 0, 20, 100), 0, 100, 30, tpoTopDown);
  AssertEquals('anchored at the top edge', 0, R.Top);
  AssertEquals('and drains downward', 30, R.Bottom);
end;

procedure TProgressDirectionTest.FullAndEmptyStayCorrectInEveryDirection;
var R: TRect;
begin
  R := TyProgressFillRect(Rect(0, 0, 100, 20), 0, 100, 0, tpoRightToLeft);
  AssertEquals('empty right-to-left is a zero-width sliver at the right', 0, R.Right - R.Left);
  R := TyProgressFillRect(Rect(0, 0, 100, 20), 0, 100, 100, tpoRightToLeft);
  AssertEquals('full covers the track', 0, R.Left);
  R := TyProgressFillRect(Rect(0, 0, 20, 100), 0, 100, 0, tpoTopDown);
  AssertEquals('empty top-down is a zero-height sliver at the top', 0, R.Bottom - R.Top);
  R := TyProgressFillRect(Rect(0, 0, 20, 100), 0, 100, 100, tpoTopDown);
  AssertEquals('full covers the track', 100, R.Bottom);
end;

{ --- 14 --- }

procedure TProgressTextTest.DefaultsOff;
var P: TTyProgressBar;
begin
  P := TTyProgressBar.Create(nil);
  try
    AssertFalse('comctrls.pp:1855 default False', P.BarShowText);
  finally P.Free; end;
end;

procedure TProgressTextTest.BarTextFillsTheTemplate;
var P: TTyProgressBar;
begin
  P := TTyProgressBar.Create(nil);
  try
    P.Min := 0; P.Max := 200; P.Position := 50;
    AssertEquals('the default template is the percentage people ask for', '25%', P.BarText);
    P.BarTextFormat := '%v from [%l-%u] (=%p%%)';   // LCL's own (progressbar.inc:48)
    AssertEquals('50 from [0-200] (=25%)', P.BarText);
  finally P.Free; end;
end;

procedure TProgressTextTest.BarTextHandlesADegenerateRange;
var P: TTyProgressBar;
begin
  P := TTyProgressBar.Create(nil);
  try
    P.Min := 5; P.Max := 5; P.Position := 5;
    AssertEquals('no travel, no division', '0%', P.BarText);
  finally P.Free; end;
end;

procedure TProgressTextTest.BarShowTextPaintsInk;

  function Painted(AShow: Boolean): Boolean;
  var
    Ctl: TTyStyleController;
    P: TProgressProbe;
    bmp: TBitmap;
  begin
    Ctl := TTyStyleController.Create(nil);
    P := TProgressProbe.Create(nil);
    bmp := WhiteCanvas(200, 20);
    try
      Ctl.LoadThemeCss(cInkTheme);
      P.Controller := Ctl;
      P.Font.PixelsPerInch := 96;
      P.SetBounds(0, 0, 200, 20);
      P.Min := 0; P.Max := 100; P.Position := 47;
      P.BarShowText := AShow;
      P.RenderTo(bmp.Canvas, Rect(0, 0, 200, 20), 96);
      Result := HasInk(bmp, Rect(0, 0, 200, 20));
    finally
      bmp.Free; P.Free; Ctl.Free;
    end;
  end;

begin
  AssertFalse('a white bar on a white track paints nothing while the readout is off',
    Painted(False));
  AssertTrue('and the readout when it is on', Painted(True));
end;

{ --- 15 --- }

procedure TScrollLargeChangeTest.DefaultFollowsPageSize;
var S: TScrollProbe;
begin
  S := TScrollProbe.Create(nil);
  try
    AssertEquals('0 == follow PageSize', 0, S.LargeChange);
    S.Min := 0; S.Max := 100; S.PageSize := 20; S.Position := 0;
    S.DoKey(VK_NEXT);
    AssertEquals('paged by PageSize, exactly as before the property existed',
      20, S.Position);
  finally S.Free; end;
end;

procedure TScrollLargeChangeTest.SetLargeChangePagesByItself;
var S: TScrollProbe;
begin
  S := TScrollProbe.Create(nil);
  try
    S.Min := 0; S.Max := 100; S.PageSize := 20; S.LargeChange := 5; S.Position := 50;
    S.DoKey(VK_NEXT);
    AssertEquals('page down by LargeChange', 55, S.Position);
    S.DoKey(VK_PRIOR);
    AssertEquals('and back up by it', 50, S.Position);
  finally S.Free; end;
end;

procedure TScrollLargeChangeTest.ThumbSizeStillFollowsPageSizeAlone;
var
  wide, narrow: TRect;
begin
  { The point of splitting them: the thumb keeps sizing off PageSize while the page
    step is free to be something else. }
  wide := TyScrollThumbRect(Rect(0, 0, 12, 120), sbVertical, 0, 100, 0, 50);
  narrow := TyScrollThumbRect(Rect(0, 0, 12, 120), sbVertical, 0, 100, 0, 5);
  AssertTrue('a bigger PageSize is still a bigger thumb',
    (wide.Bottom - wide.Top) > (narrow.Bottom - narrow.Top));
end;

procedure TScrollLargeChangeTest.NegativeFallsBackToPageSize;
var S: TScrollProbe;
begin
  S := TScrollProbe.Create(nil);
  try
    S.Min := 0; S.Max := 100; S.PageSize := 20; S.Position := 0;
    S.LargeChange := -5;
    AssertEquals('a backwards page action is not a thing', 0, S.LargeChange);
    S.DoKey(VK_NEXT);
    AssertEquals(20, S.Position);
  finally S.Free; end;
end;

initialization
  RegisterTest(TSpinDefaultRangeTest);
  RegisterTest(TSpinEditorEnabledTest);
  RegisterTest(TSpinEditorStateTest);
  RegisterTest(TSpinSeamTest);
  RegisterTest(TSpinPreferredSizeTest);
  RegisterTest(TUpDownArrowOrderTest);
  RegisterTest(TUpDownVetoTest);
  RegisterTest(TUpDownRepeatTest);
  RegisterTest(TTrackReversedTest);
  RegisterTest(TTrackTickTest);
  RegisterTest(TTrackPreferredSizeTest);
  RegisterTest(TProgressStepTest);
  RegisterTest(TProgressDirectionTest);
  RegisterTest(TProgressTextTest);
  RegisterTest(TScrollLargeChangeTest);
end.
