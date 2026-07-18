unit test.dialogs;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Dialogs, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.Dialogs, tyControls.Button, tyControls.Panel,
  tyControls.Edit, tyControls.Memo, tyControls.ListBox,
  tyControls.TyLabel;   // the message body is a TTyLabel — the tests read its measured height
type
  TDialogButtonBarTest = class(TTestCase)
  published
    procedure TestSingleButtonRightAligned;
    procedure TestTwoButtonsOrderedRightToLeft;
    procedure TestMarginAndSpacing;
  end;

  TMsgMappingTest = class(TTestCase)
  published
    procedure TestButtonResult;
    procedure TestButtonCaptionNonEmpty;
    procedure TestOrderedButtonsCompleteAndStable;
    procedure TestTypeSymbol;
    procedure TestTypeCaption;
    procedure TestEmptyButtonsDefaultsOK;
  end;

  TMessageBuildTest = class(TTestCase)
  published
    procedure TestBuildConfirmationHasYesNo;
    procedure TestBuildInformationHasOK;
    procedure TestConfirmationDismissIsMrCancel;
    procedure TestLongMessageGrowsTheDialog;
    procedure TestWideMessageWidensBeforeGrowingTall;
    procedure TestShortMessageStaysNarrow;
  end;

  TDialogBaseTest = class(TTestCase)
  published
    procedure TestAddButtonWiresModalResult;
    procedure TestCloseGivesCancel;
    procedure TestTwoButtonLayoutRightToLeft;
  end;

  TResizeProbeDialog = class(TTyDialog)
  public
    Content: TTyPanel;   // stand-in windowed content widget
    procedure LayoutContent; override;   // fills ContentRect
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
  end;

  TDialogResizeTest = class(TTestCase)
  published
    procedure TestLayoutContentFillsContentRect;
    procedure TestReflowOnClientResize;
  end;

  TInputDialogTest = class(TTestCase)
  published
    procedure TestBuildSeedsEditAndButtons;
    procedure TestBoxReturnsDefaultOnCancelLogic;
  end;

  TPasswordDialogTest = class(TTestCase)
  published
    procedure TestBuildMasksEdit;
  end;

  // access subclass exposes the protected LayoutContent/Resize for the resize tests
  TTyTextFormAccess = class(TTyTextDialogForm);

  TTextDialogTest = class(TTestCase)
  published
    procedure TestBuildSeedsMemoResizable;
    procedure TestMemoReflowsOnResize;
    procedure TestResizeInvokesLayoutContent;
  end;

  TSelectValueTest = class(TTestCase)
  published
    procedure TestBuildSeedsListAndSelection;
    procedure TestResultIndexLogic;
  end;

  { The shared TyForwardDialogEvents helper is the exact seam every modal wrapper's
    Execute uses just before ShowModal (build the form, forward the 3 events, show).
    ShowModal can't run headlessly, so exercise the forward against a built dialog. }
  TDialogEventForwardTest = class(TTestCase)
  private
    procedure HandleShow(Sender: TObject);
    procedure HandleClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure HandleCanClose(Sender: TObject; var CanClose: Boolean);
  published
    procedure TestForwardOntoBuiltMessageDialog;
    procedure TestForwardNilFormIsNoOp;
  end;

implementation

procedure TDialogButtonBarTest.TestSingleButtonRightAligned;
var r: TTyRectArray;
begin
  // one 80-wide button in a 300 bar, margin 12 -> right edge at 300-12=288, left at 208
  r := TyDialogButtonBar([Size(80, 28)], 300, 12, 8);
  AssertEquals('count', 1, Length(r));
  AssertEquals('right', 288, r[0].Right);
  AssertEquals('left', 208, r[0].Left);
end;

procedure TDialogButtonBarTest.TestTwoButtonsOrderedRightToLeft;
var r: TTyRectArray;
begin
  // buttons[0]=60, buttons[1]=80; index 0 is the RIGHTMOST (primary). margin 12, spacing 8.
  // r[0] right=288 left=228 ; r[1] right=228-8=220 left=140
  r := TyDialogButtonBar([Size(60, 28), Size(80, 28)], 300, 12, 8);
  AssertEquals('r0.right', 288, r[0].Right);
  AssertEquals('r0.left', 228, r[0].Left);
  AssertEquals('r1.right', 220, r[1].Right);
  AssertEquals('r1.left', 140, r[1].Left);
end;

procedure TDialogButtonBarTest.TestMarginAndSpacing;
var r: TTyRectArray;
begin
  r := TyDialogButtonBar([Size(50, 24), Size(50, 24)], 200, 10, 6);
  AssertEquals('r0.right', 190, r[0].Right);   // 200-10
  AssertEquals('r1.right', 134, r[1].Right);   // 190-50-6
end;

procedure TMsgMappingTest.TestButtonResult;
begin
  AssertEquals('yes', Ord(mrYes), Ord(TyMsgButtonResult(mbYes)));
  AssertEquals('no', Ord(mrNo), Ord(TyMsgButtonResult(mbNo)));
  AssertEquals('ok', Ord(mrOK), Ord(TyMsgButtonResult(mbOK)));
  AssertEquals('cancel', Ord(mrCancel), Ord(TyMsgButtonResult(mbCancel)));
  AssertEquals('help', 0, Ord(TyMsgButtonResult(mbHelp)));
end;

procedure TMsgMappingTest.TestButtonCaptionNonEmpty;
var b: TMsgDlgBtn;
begin
  for b := Low(TMsgDlgBtn) to High(TMsgDlgBtn) do
    AssertTrue('caption for '+IntToStr(Ord(b)), TyMsgButtonCaption(b) <> '');
end;

procedure TMsgMappingTest.TestOrderedButtonsCompleteAndStable;
var a: TMsgDlgBtnArray;
begin
  a := TyMsgOrderedButtons([mbYes, mbNo, mbCancel]);
  AssertEquals('n', 3, Length(a));
  AssertTrue('yes first', a[0] = mbYes);
  AssertTrue('no second', a[1] = mbNo);
  AssertTrue('cancel third', a[2] = mbCancel);
end;

procedure TMsgMappingTest.TestTypeSymbol;
begin
  AssertTrue('warning symbol', TyMsgTypeSymbol(mtWarning) <> '');
  AssertTrue('error symbol', TyMsgTypeSymbol(mtError) <> '');
  AssertTrue('confirmation symbol', TyMsgTypeSymbol(mtConfirmation) <> '');
  AssertEquals('error exact', #$C3#$97, TyMsgTypeSymbol(mtError));
end;

procedure TMsgMappingTest.TestTypeCaption;
begin
  AssertEquals('warning', 'Warning', TyMsgTypeCaption(mtWarning));
  AssertEquals('error', 'Error', TyMsgTypeCaption(mtError));
  AssertEquals('confirm', 'Confirm', TyMsgTypeCaption(mtConfirmation));
  AssertEquals('information', 'Information', TyMsgTypeCaption(mtInformation));
  AssertEquals('custom empty', '', TyMsgTypeCaption(mtCustom));
end;

procedure TMsgMappingTest.TestEmptyButtonsDefaultsOK;
var a: TMsgDlgBtnArray;
begin
  a := TyMsgOrderedButtons([]);
  AssertEquals('empty -> OK', 1, Length(a));
  AssertTrue('is OK', a[0] = mbOK);
end;

{ NOTE (deviation from the plan): we do NOT call SetDesigning here. Empirically, on the
  headless LCL-Win32 runner, SetDesigning(True, False) on a TTyForm followed by parenting a
  *windowed* child (TTyPanel/TTyButton) raises "Failed to create win32 control, error 1407"
  (form is csDesigning, child is not -> handle-class mismatch). A bare TTyForm.CreateNew does
  NOT arm the chrome engine at construction (ArmEngine runs on show/Loaded and self-guards on
  csDesigning), and parenting windowed children to a plain runtime TTyForm succeeds, so the
  construct-only path is safe without SetDesigning. }

procedure TDialogBaseTest.TestAddButtonWiresModalResult;
var d: TTyDialog; b: TTyButton;
begin
  d := TTyDialog.CreateNew(nil);
  try
    b := d.AddButton('OK', mrOk, True, False);
    AssertTrue('button created', b <> nil);
    AssertEquals('caption', 'OK', b.Caption);
    b.Click;                     // TTyButton.Click routes its ModalResult to the host form
    AssertEquals('modal result set', Ord(mrOk), Ord(d.ModalResult));
  finally d.Free; end;
end;

procedure TDialogBaseTest.TestCloseGivesCancel;
var d: TTyDialog;
begin
  d := TTyDialog.CreateNew(nil);
  try
    d.AddButton('Cancel', mrCancel, False, True);
    d.CancelDialog;              // the Esc / programmatic cancel path
    AssertEquals('cancel', Ord(mrCancel), Ord(d.ModalResult));
  finally d.Free; end;
end;

procedure TDialogBaseTest.TestTwoButtonLayoutRightToLeft;
var d: TTyDialog; primary, secondary: TTyButton;
begin
  d := TTyDialog.CreateNew(nil);
  try
    primary := d.AddButton('OK', mrOk, True, False);      // index 0 -> rightmost
    secondary := d.AddButton('Cancel', mrCancel, False, True);
    d.AutoSizeToContent(200, 100);   // give the bar a real width + relayout
    AssertTrue('primary is right of secondary', primary.Left > secondary.Left);
  finally d.Free; end;
end;

procedure TMessageBuildTest.TestBuildConfirmationHasYesNo;
var d: TTyDialog;
begin
  d := TyBuildMessageDialog('Delete it?', mtConfirmation, [mbYes, mbNo]);
  try
    AssertEquals('two buttons', 2, TyDialogButtonCount(d));
    AssertEquals('btn0 caption', 'Yes', TyDialogButton(d, 0).Caption);
    AssertEquals('btn0 result', Ord(mrYes), Ord(TyDialogButton(d, 0).ModalResult));
    AssertEquals('btn1 caption', 'No', TyDialogButton(d, 1).Caption);
  finally d.Free; end;
end;

procedure TMessageBuildTest.TestBuildInformationHasOK;
var d: TTyDialog;
begin
  d := TyBuildMessageDialog('Saved.', mtInformation, []);
  try
    AssertEquals('one button', 1, TyDialogButtonCount(d));
    AssertEquals('OK', 'OK', TyDialogButton(d, 0).Caption);
  finally d.Free; end;
end;

procedure TMessageBuildTest.TestConfirmationDismissIsMrCancel;
var d: TTyDialog;
begin
  // A [mbYes,mbNo] confirmation must dismiss (Esc / title-bar X) to mrCancel,
  // NOT the negative button — Esc and the X agree.
  d := TyBuildMessageDialog('Delete it?', mtConfirmation, [mbYes, mbNo]);
  try
    d.CancelDialog;                       // the Esc / programmatic dismiss path
    AssertEquals('dismiss -> mrCancel', Ord(mrCancel), Ord(d.ModalResult));
  finally d.Free; end;
end;

{ TResizeProbeDialog }

constructor TResizeProbeDialog.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Resizable := True;
  Content := TTyPanel.Create(Self);
  Content.Parent := Self;
  AddButton('OK', mrOk, True, False);
  AutoSizeToContent(300, 200);
end;

procedure TResizeProbeDialog.LayoutContent;
var r: TRect;
begin
  if Content = nil then Exit;
  r := ContentRect;
  Content.SetBounds(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
end;

{ TDialogResizeTest }

procedure TDialogResizeTest.TestLayoutContentFillsContentRect;
var d: TResizeProbeDialog; r: TRect;
begin
  d := TResizeProbeDialog.CreateNew(nil);
  try
    d.LayoutContent;
    r := d.ContentRect;
    AssertEquals('content left', r.Left, d.Content.Left);
    AssertEquals('content width', r.Right - r.Left, d.Content.Width);
    AssertEquals('content bottom', r.Bottom, d.Content.Top + d.Content.Height);
  finally d.Free; end;
end;

procedure TDialogResizeTest.TestReflowOnClientResize;
var d: TResizeProbeDialog; w0: Integer;
begin
  d := TResizeProbeDialog.CreateNew(nil);
  try
    d.LayoutContent; w0 := d.Content.Width;
    d.ClientWidth := d.ClientWidth + 120;   // grow
    d.LayoutContent;                          // reflow (Resize would call this live)
    AssertTrue('content widened with the dialog', d.Content.Width > w0);
  finally d.Free; end;
end;

{ TInputDialogTest }

procedure TInputDialogTest.TestBuildSeedsEditAndButtons;
var d: TTyDialog; e: TTyEdit;
begin
  d := TyBuildInputDialog('Rename', 'New name:', 'old.txt', e);
  try
    AssertTrue('edit created', e <> nil);
    AssertEquals('edit seeded', 'old.txt', e.Text);
    AssertEquals('two buttons', 2, TyDialogButtonCount(d));
    AssertEquals('ok caption', 'OK', TyDialogButton(d, 0).Caption);
  finally d.Free; end;
end;

procedure TInputDialogTest.TestBoxReturnsDefaultOnCancelLogic;
var d: TTyDialog; e: TTyEdit;
begin
  d := TyBuildInputDialog('X', 'p', 'def', e);
  try
    e.Text := 'typed';
    AssertEquals('cancel -> default kept', 'def', TyInputResult(e, 'def', mrCancel));
    AssertEquals('ok -> typed', 'typed', TyInputResult(e, 'def', mrOk));
  finally d.Free; end;
end;

{ TPasswordDialogTest }

procedure TPasswordDialogTest.TestBuildMasksEdit;
var d: TTyDialog; e: TTyEdit;
begin
  d := TyBuildPasswordDialog('Login', 'Password:', '●', e);
  try
    AssertTrue('edit created', e <> nil);
    AssertEquals('masked', '●', e.PasswordChar);
    AssertEquals('two buttons', 2, TyDialogButtonCount(d));
  finally d.Free; end;
end;

{ TTextDialogTest }

procedure TTextDialogTest.TestBuildSeedsMemoResizable;
var d: TTyTextDialogForm; m: TTyMemo;
begin
  d := TyBuildTextDialog('Notes', 'Enter notes:', 'line1' + LineEnding + 'line2', m);
  try
    AssertTrue('memo created', m <> nil);
    // TTyMemo.Text uses TStrings.Text semantics: always appends a trailing LineEnding.
    AssertEquals('memo seeded', 'line1' + LineEnding + 'line2' + LineEnding, m.Text);
    AssertTrue('resizable', d.Resizable);
    AssertEquals('two buttons', 2, TyDialogButtonCount(d));
  finally d.Free; end;
end;

procedure TTextDialogTest.TestMemoReflowsOnResize;
var d: TTyTextDialogForm; m: TTyMemo; w0: Integer;
begin
  d := TyBuildTextDialog('T', 'p', '', m);
  try
    TTyTextFormAccess(d).LayoutContent; w0 := m.Width;
    d.ClientWidth := d.ClientWidth + 100;
    TTyTextFormAccess(d).LayoutContent;
    AssertTrue('memo widened', m.Width > w0);
  finally d.Free; end;
end;

procedure TTextDialogTest.TestResizeInvokesLayoutContent;
var d: TTyTextDialogForm; m: TTyMemo; w0: Integer;
begin
  // exercises the LIVE Resize override (base Task 1): Resize -> LayoutButtonBar + LayoutContent
  d := TyBuildTextDialog('T', 'p', '', m);
  try
    w0 := m.Width;
    d.ClientWidth := d.ClientWidth + 100;
    TTyTextFormAccess(d).Resize;   // must reflow the memo via LayoutContent
    AssertTrue('memo widened via Resize', m.Width > w0);
  finally d.Free; end;
end;

{ TSelectValueTest }

procedure TSelectValueTest.TestBuildSeedsListAndSelection;
var d: TTyDialog; lb: TTyListBox; items: TStringList;
begin
  items := TStringList.Create;
  try
    items.Add('Red'); items.Add('Green'); items.Add('Blue');
    d := TyBuildSelectValueDialog('Pick', 'Colour:', items, 1, lb);
    try
      AssertTrue('list created', lb <> nil);
      AssertEquals('items copied', 3, lb.Items.Count);
      AssertEquals('seeded selection', 1, lb.ItemIndex);
    finally d.Free; end;
  finally items.Free; end;
end;

procedure TSelectValueTest.TestResultIndexLogic;
var d: TTyDialog; lb: TTyListBox; items: TStringList;
begin
  items := TStringList.Create;
  try
    items.Add('A'); items.Add('B');
    d := TyBuildSelectValueDialog('X', 'p', items, 0, lb);
    try
      lb.ItemIndex := 1;
      AssertEquals('ok -> chosen', 1, TySelectValueResult(lb, 0, mrOK));
      AssertEquals('cancel -> initial', 0, TySelectValueResult(lb, 0, mrCancel));
    finally d.Free; end;
  finally items.Free; end;
end;

{ TDialogEventForwardTest }

procedure TDialogEventForwardTest.HandleShow(Sender: TObject);
begin end;

procedure TDialogEventForwardTest.HandleClose(Sender: TObject; var CloseAction: TCloseAction);
begin end;

procedure TDialogEventForwardTest.HandleCanClose(Sender: TObject; var CanClose: Boolean);
begin end;

procedure TDialogEventForwardTest.TestForwardOntoBuiltMessageDialog;
var d: TTyDialog;
begin
  d := TyBuildMessageDialog('Hi', mtInformation, [mbOK]);
  try
    TyForwardDialogEvents(d, @HandleShow, @HandleClose, @HandleCanClose);
    AssertTrue('OnShow forwarded', d.OnShow = TNotifyEvent(@HandleShow));
    AssertTrue('OnClose forwarded', d.OnClose = TCloseEvent(@HandleClose));
    AssertTrue('OnCanClose -> OnCloseQuery', d.OnCloseQuery = TCloseQueryEvent(@HandleCanClose));
  finally d.Free; end;
end;

procedure TDialogEventForwardTest.TestForwardNilFormIsNoOp;
begin
  // Must not raise on a nil form (the helper's guard).
  TyForwardDialogEvents(nil, @HandleShow, @HandleClose, @HandleCanClose);
  AssertTrue('nil form tolerated', True);
end;

{ The message body used to be pinned to a 260x40 box — exactly two lines — so a third line, or
  one long unbroken run, was silently cut off. These three guard that the dialog is sized to the
  text's MEASURED wrapped size instead. }

function MsgBodyLabel(ADlg: TTyDialog): TTyLabel;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ADlg.ComponentCount - 1 do
    if ADlg.Components[i] is TTyLabel then Exit(TTyLabel(ADlg.Components[i]));
end;

procedure TMessageBuildTest.TestLongMessageGrowsTheDialog;
var
  dShort, dLong: TTyDialog;
begin
  dShort := TyBuildMessageDialog('Saved.', mtInformation, [mbOK]);
  try
    dLong := TyBuildMessageDialog(
      'The operation could not be completed because the destination folder is read-only, the '
      + 'source file is still open in another application, and the volume has less free space '
      + 'than the copy requires. Close the other application, free some space, then retry. If '
      + 'the problem persists, check the folder permissions and try a different destination.',
      mtError, [mbOK]);
    try
      // The body must GROW with the text. It was pinned to 40px — exactly two lines — so
      // everything past line two was silently cut. Asserted on the BODY, not the dialog:
      // the dialog only gets taller once the text outgrows the icon column beside it, which
      // depends on the runtime font size.
      AssertTrue(Format('the body grows with the text (short %d, long %d)',
        [MsgBodyLabel(dShort).Height, MsgBodyLabel(dLong).Height]),
        MsgBodyLabel(dLong).Height > MsgBodyLabel(dShort).Height);
      AssertTrue('and the dialog is tall enough to contain it',
        dLong.ClientHeight >= MsgBodyLabel(dLong).Height);
    finally
      dLong.Free;
    end;
  finally
    dShort.Free;
  end;
end;

procedure TMessageBuildTest.TestWideMessageWidensBeforeGrowingTall;
var dShort, dLong: TTyDialog; wShort: Integer;
begin
  dShort := TyBuildMessageDialog('Saved.', mtInformation, [mbOK]);
  try wShort := dShort.ClientWidth; finally dShort.Free; end;
  dLong := TyBuildMessageDialog(
    'The operation could not be completed because the destination folder is read-only and the '
    + 'source file is still open in another application. Close it, then retry.',
    mtError, [mbOK]);
  try
    // A paragraph must not become a ribbon 40 lines long: the text column widens first.
    AssertTrue(Format('a long message widens the dialog (short %d, long %d)',
      [wShort, dLong.ClientWidth]), dLong.ClientWidth > wShort);
  finally dLong.Free; end;
end;

procedure TMessageBuildTest.TestShortMessageStaysNarrow;
var d: TTyDialog;
begin
  // Sizing to the text must not stretch a one-liner across the screen.
  d := TyBuildMessageDialog('Saved.', mtInformation, [mbOK]);
  try
    AssertTrue(Format('a one-liner stays narrow (%d)', [d.ClientWidth]), d.ClientWidth < 420);
    AssertTrue('and short', d.ClientHeight < 220);
  finally d.Free; end;
end;

initialization
  RegisterTest(TDialogButtonBarTest);
  RegisterTest(TMsgMappingTest);
  RegisterTest(TDialogBaseTest);
  RegisterTest(TMessageBuildTest);
  RegisterTest(TDialogResizeTest);
  RegisterTest(TInputDialogTest);
  RegisterTest(TPasswordDialogTest);
  RegisterTest(TTextDialogTest);
  RegisterTest(TSelectValueTest);
  RegisterTest(TDialogEventForwardTest);
end.
