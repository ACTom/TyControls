unit mainform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Graphics, Forms, Controls, Dialogs,
  tyControls.Types, tyControls.Controller, tyControls.Form, tyControls.Button,
  tyControls.TyLabel, tyControls.Panel, tyControls.Memo, tyControls.BuiltinThemes,
  tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.Edit,
  tyControls.Dialogs, tyControls.Dialogs.SelectPath, tyControls.Dialogs.Color,
  tyControls.Dialogs.Font, tyControls.Dialogs.Find, tyControls.Dialogs.Progress,
  tyControls.Dialogs.About;

type

  { TDialogsMainForm — a single showcase form for every custom dialog. Visual controls (the docked
    TTyTitleBar, the button grid, and the status memo) live in mainform.lfm; this unit only wires the
    theme (InitThemes/ApplyBuiltin, mirroring the demo) and the per-button dialog handlers. The two
    modeless components (Find/Replace) are created in FormCreate; Progress is created on demand. }

  TDialogsMainForm = class(TTyForm)
    TyController: TTyStyleController;
    Surface: TTyFormSurface;
    TyTitleBar1: TTyTitleBar;
    Panel1: TTyPanel;
    LblIntro: TTyLabel;
    Memo1: TTyMemo;
    BtnMessage: TTyButton;
    BtnInput: TTyButton;
    BtnPassword: TTyButton;
    BtnText: TTyButton;
    BtnSelectValue: TTyButton;
    BtnSelectPath: TTyButton;
    BtnColor: TTyButton;
    BtnFont: TTyButton;
    BtnFind: TTyButton;
    BtnReplace: TTyButton;
    BtnProgress: TTyButton;
    BtnAbout: TTyButton;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    LblMsgTypes: TTyLabel;
    Panel2: TTyPanel;
    BtnMsgInfo: TTyButton;
    BtnMsgWarning: TTyButton;
    BtnMsgError: TTyButton;
    BtnShowMessage: TTyButton;
    BtnMessagePos: TTyButton;
    BtnSelectPathRooted: TTyButton;
    BtnCloseFind: TTyButton;
    BtnCustomDialog: TTyButton;
    LblComponents: TTyLabel;
    Panel3: TTyPanel;
    BtnCompMessage: TTyButton;
    BtnCompInput: TTyButton;
    BtnCompColor: TTyButton;
    { Non-visual dialog components: everything they show is configured in mainform.lfm. }
    DlgMessage: TTyMessage;
    DlgInput: TTyInputDialog;
    DlgColor: TTyColorDialog;
    procedure FormCreate(Sender: TObject);
    procedure BtnMessageClick(Sender: TObject);
    procedure BtnInputClick(Sender: TObject);
    procedure BtnPasswordClick(Sender: TObject);
    procedure BtnTextClick(Sender: TObject);
    procedure BtnSelectValueClick(Sender: TObject);
    procedure BtnSelectPathClick(Sender: TObject);
    procedure BtnColorClick(Sender: TObject);
    procedure BtnFontClick(Sender: TObject);
    procedure BtnFindClick(Sender: TObject);
    procedure BtnReplaceClick(Sender: TObject);
    procedure BtnProgressClick(Sender: TObject);
    procedure BtnAboutClick(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure BtnMsgInfoClick(Sender: TObject);
    procedure BtnMsgWarningClick(Sender: TObject);
    procedure BtnMsgErrorClick(Sender: TObject);
    procedure BtnShowMessageClick(Sender: TObject);
    procedure BtnMessagePosClick(Sender: TObject);
    procedure BtnSelectPathRootedClick(Sender: TObject);
    procedure BtnCloseFindClick(Sender: TObject);
    procedure BtnCustomDialogClick(Sender: TObject);
    procedure BtnCompMessageClick(Sender: TObject);
    procedure BtnCompInputClick(Sender: TObject);
    procedure BtnCompColorClick(Sender: TObject);
    { Shared by all three non-visual components: TyForwardDialogEvents relays the wrapper's
      OnShow/OnCanClose onto the transient form it builds, so Sender is that FORM. }
    procedure DlgComponentShow(Sender: TObject);
    procedure DlgComponentCanClose(Sender: TObject; var CanClose: Boolean);
  private
    FFindDlg: TTyFindDialog;
    FReplaceDlg: TTyReplaceDialog;
    procedure InitThemes;
    procedure ApplyBuiltin(const AName: string);
    procedure Log(const AMsg: string);
    procedure DoFind(Sender: TObject);
    procedure DoReplace(Sender: TObject);
    procedure ProgressCancel(Sender: TObject);
    function ResultName(AResult: TModalResult): string;
  end;

var
  DialogsMainForm: TDialogsMainForm;

implementation

{$R *.lfm}

resourcestring
  { User-facing strings shown in the log pane and passed to the dialog APIs. English is the
    msgid; Simplified-Chinese lives in examples/dialogs/languages/tydialogs.zh_CN.po, which
    SetDefaultLang loads to translate BOTH these resourcestrings and the mainform.lfm captions. }
  rsReady          = 'Ready. Click a button to open the matching dialog.';
  rsMsgPrompt      = 'Delete the selected item?';
  rsMsgYes         = 'Message: user chose Yes';
  rsMsgNo          = 'Message: user chose No';
  rsInputTitle     = 'Rename';
  rsInputPrompt    = 'Enter a new name:';
  rsInputDefault   = 'Untitled';
  rsInputResult    = 'Input: %s';
  rsInputCancelled = 'Input: cancelled';
  rsPwdTitle       = 'Login';
  rsPwdPrompt      = 'Enter your password:';
  rsPwdResult      = 'Password: %d character(s) entered';
  rsPwdEmpty       = 'Password: OK pressed, but empty';
  rsPwdCancelled   = 'Password: cancelled';
  rsTextTitle      = 'Edit note';
  rsTextPrompt     = 'Enter a multiline note:';
  rsTextResult     = 'Text: %s';
  rsTextCancelled  = 'Text: cancelled';
  rsSVTitle        = 'Pick one';
  rsSVPrompt       = 'Choose an option:';
  rsSVOptA         = 'Option A';
  rsSVOptB         = 'Option B';
  rsSVOptC         = 'Option C';
  rsSVResult       = 'SelectValue: %s';
  rsSVCancelled    = 'SelectValue: cancelled';
  rsSPTitle        = 'Select a folder';
  rsSPResult       = 'SelectPath: %s';
  rsSPCancelled    = 'SelectPath: cancelled';
  rsColorTitle     = 'Select a colour';
  rsColorResult    = 'Color: R=%d G=%d B=%d A=%d';
  rsColorCancelled = 'Color: cancelled';
  rsFontResult     = 'Font: %s %dpt';
  rsFontCancelled  = 'Font: cancelled';
  rsFindOpened     = 'Find: dialog opened (modeless)';
  rsFindNext       = '  Find Next: "%s"  (MatchCase=%s, WholeWord=%s)';
  rsReplaceOpened  = 'Replace: dialog opened (modeless)';
  rsReplaceAllMsg  = '  Replace ALL: "%s" -> "%s"';
  rsReplaceOneMsg  = '  Replace: "%s" -> "%s"';
  rsProgWorking    = 'Working…';
  rsProgItem       = 'Item %d of %d';
  rsProgCancelled  = 'Progress: cancelled by user';
  rsProgDone       = 'Progress: completed';
  rsAboutTitle     = 'About TyControls';
  rsAboutDesc      = 'A skinnable / styleable Lazarus component library';
  rsAboutShown     = 'About: dialog shown';
  rsVersionFmt     = 'Version %s';
  rsThemeApplied   = 'Theme: "%s" — open any dialog now, it adopts the app theme';
  rsModeApplied    = 'Mode: %s';
  rsMsgInfoText    = 'Export finished.';
  rsMsgWarnText    = 'Unsaved changes will be lost.';
  rsMsgErrorText   = 'Could not open the file.';
  rsMsgTypeResult  = 'Message (%s): %s';
  rsShowMsgText    = 'Done.';
  rsShowMsgClosed  = 'ShowMessage: closed (no result to inspect)';
  rsMsgPosText     = 'This one opened at screen position 40,40.';
  rsMsgPosResult   = 'MessageDlgPos: %s';
  rsInputBoxResult = 'InputBox (returns the default on cancel): %s';
  rsSPRootTitle    = 'Pick a sub-folder';
  rsSPRootResult   = 'SelectPath (rooted at the app folder): %s';
  rsColorLCLTitle  = 'Select an LCL colour';
  rsColorLCLResult = 'Color (TColor + alpha overload): R=%d G=%d B=%d A=%d';
  rsFindClosed     = 'Find: CloseDialog dismissed the modeless window';
  rsProgPreparing  = 'Preparing…';
  rsProgCancelEvt  = 'Progress: OnCancel fired';
  rsCustomTitle    = 'Custom dialog';
  rsCustomSeed     = 'Type something here';
  rsCustomSave     = 'Save';
  rsCustomCancel   = 'Cancel';
  rsCustomResult   = 'Custom dialog: %s';
  rsCustomCancelled = 'Custom dialog: cancelled';
  rsCompShown      = 'Component OnShow: "%s" is on screen';
  rsCompCanClose   = 'Component OnCanClose: "%s" is allowed to close';
  rsCompMsgResult  = 'DlgMessage.Execute: %s';
  rsCompInputResult = 'DlgInput.Execute: %s (the component remembers it for next time)';
  rsCompInputCancel = 'DlgInput.Execute: cancelled';
  rsCompColorResult = 'DlgColor.Execute: R=%d G=%d B=%d A=%d';
  rsCompColorCancel = 'DlgColor.Execute: cancelled';

{ TDialogsMainForm }

procedure TDialogsMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  InitThemes;
  // Fill the title-bar theme switcher with every compiled-in theme. Switching it re-themes the
  // app AND every dialog opened afterwards — a CreateNew dialog adopts the owner form's
  // controller in TTyDialog.ApplyOwnerController, which is what makes the two match.
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  // Modeless dialogs are non-visual components created once and reused across Execute calls.
  FFindDlg := TTyFindDialog.Create(Self);
  FFindDlg.OnFind := @DoFind;
  // Pre-seed them: the Find window opens with the text already filled in, "Match case" already
  // ticked (frDown = search downwards, the default direction) and centred on the main form.
  FFindDlg.FindText := 'TyControls';
  FFindDlg.Options := [frDown, frMatchCase];
  FFindDlg.Position := poMainFormCenter;
  FReplaceDlg := TTyReplaceDialog.Create(Self);
  FReplaceDlg.OnReplace := @DoReplace;
  FReplaceDlg.FindText := 'TyControls';
  FReplaceDlg.ReplaceText := 'TyComponents';
  // DlgColor's seed is a TTyColor ($AARRGGBB, alpha in the top byte), which has no readable
  // literal form in an .lfm — everything else about that component is set in the designer.
  DlgColor.Color := TyRGBA(64, 128, 255, 204);
  Log(rsReady);
end;

procedure TDialogsMainForm.InitThemes;
begin
  // Register the compiled-in theme pack, pick 'default', and push it into the window chrome so the
  // form AND the dialogs (which fall back to the same default controller) share one look.
  TyRegisterBuiltinThemes;
  ApplyBuiltin('default');
end;

procedure TDialogsMainForm.ApplyBuiltin(const AName: string);
begin
  TyController.ThemeName := AName;
  ApplyChromeTheme(TyController);
end;

procedure TDialogsMainForm.Log(const AMsg: string);
begin
  Memo1.Lines.Add(AMsg);
end;

function TDialogsMainForm.ResultName(AResult: TModalResult): string;
begin
  // Every modal dialog here answers with a TModalResult; name it so the log is readable.
  case AResult of
    mrOK:     Result := 'mrOK';
    mrCancel: Result := 'mrCancel';
    mrYes:    Result := 'mrYes';
    mrNo:     Result := 'mrNo';
    mrAbort:  Result := 'mrAbort';
    mrRetry:  Result := 'mrRetry';
    mrIgnore: Result := 'mrIgnore';
  else
    Result := Format('mr(%d)', [AResult]);
  end;
end;

{ ---- Runtime theme switcher --------------------------------------------- }

procedure TDialogsMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  ApplyBuiltin(ThemeCombo.Items[ThemeCombo.ItemIndex]);
  Log(Format(rsThemeApplied, [ThemeCombo.Items[ThemeCombo.ItemIndex]]));
end;

procedure TDialogsMainForm.DarkSwitchChange(Sender: TObject);
begin
  // The light/dark @mode axis is independent of which theme ThemeCombo picked.
  if DarkSwitch.Checked then
    TyController.Mode := 'dark'
  else
    TyController.Mode := 'light';
  ApplyChromeTheme(TyController);
  if DarkSwitch.Checked then Log(Format(rsModeApplied, ['dark']))
                        else Log(Format(rsModeApplied, ['light']));
end;

{ ---- Modal dialogs ------------------------------------------------------- }

procedure TDialogsMainForm.BtnMessageClick(Sender: TObject);
begin
  // Confirmation box via the primary global API; returns a TModalResult.
  if TyMessageDlg(rsMsgPrompt, mtConfirmation, [mbYes, mbNo]) = mrYes then
    Log(rsMsgYes)
  else
    Log(rsMsgNo);
end;

{ mtInformation / mtWarning / mtError each draw their own semantic icon (TyMsgTypeSymbol), and
  the button set is laid out in the API's own fixed order (TyMsgOrderedButtons) — not in the
  order the set is written. Four buttons, four looks. }

procedure TDialogsMainForm.BtnMsgInfoClick(Sender: TObject);
begin
  Log(Format(rsMsgTypeResult,
    ['mtInformation', ResultName(TyMessageDlg(rsMsgInfoText, mtInformation, [mbOK]))]));
end;

procedure TDialogsMainForm.BtnMsgWarningClick(Sender: TObject);
begin
  Log(Format(rsMsgTypeResult,
    ['mtWarning', ResultName(TyMessageDlg(rsMsgWarnText, mtWarning, [mbOK, mbCancel]))]));
end;

procedure TDialogsMainForm.BtnMsgErrorClick(Sender: TObject);
begin
  // Written Abort/Retry/Ignore; drawn Retry, Ignore, Abort — the API orders them, not the caller.
  Log(Format(rsMsgTypeResult,
    ['mtError', ResultName(TyMessageDlg(rsMsgErrorText, mtError, [mbAbort, mbRetry, mbIgnore]))]));
end;

procedure TDialogsMainForm.BtnShowMessageClick(Sender: TObject);
begin
  // The one-liner: information icon, single OK, no result.
  TyShowMessage(rsShowMsgText);
  Log(rsShowMsgClosed);
end;

procedure TDialogsMainForm.BtnMessagePosClick(Sender: TObject);
begin
  // ...Pos places the window itself (Position := poDesigned) instead of centring on the main form.
  Log(Format(rsMsgPosResult,
    [ResultName(TyMessageDlgPos(rsMsgPosText, mtInformation, [mbOK], 0, 40, 40))]));
end;

procedure TDialogsMainForm.BtnInputClick(Sender: TObject);
var
  s: string;
begin
  s := rsInputDefault;
  if TyInputQuery(rsInputTitle, rsInputPrompt, s) then
    Log(Format(rsInputResult, [s]))
  else
    Log(rsInputCancelled);
  // Same dialog, the other entry point: TyInputBox is a function and cannot report a cancel —
  // it simply hands the default back, so Cancel and "unchanged" look identical to the caller.
  Log(Format(rsInputBoxResult, [TyInputBox(rsInputTitle, rsInputPrompt, rsInputDefault)]));
end;

procedure TDialogsMainForm.BtnPasswordClick(Sender: TObject);
var
  pwd: string;
begin
  pwd := '';
  // TyPasswordQuery is the var-parameter form: unlike TyPasswordBox (which returns '') it tells
  // an EMPTY password apart from a CANCELLED dialog.
  if TyPasswordQuery(rsPwdTitle, rsPwdPrompt, pwd) then
  begin
    if pwd = '' then
      Log(rsPwdEmpty)
    else
      Log(Format(rsPwdResult, [Length(pwd)]));
  end
  else
    Log(rsPwdCancelled);
end;

procedure TDialogsMainForm.BtnTextClick(Sender: TObject);
var
  note: string;
begin
  note := '';
  if TyTextQuery(rsTextTitle, rsTextPrompt, note) then
  begin
    note := TrimRight(note);   // TyTextQuery appends a trailing LineEnding (TStrings.Text semantics)
    Log(Format(rsTextResult, [StringReplace(note, LineEnding, ' / ', [rfReplaceAll])]));
  end
  else
    Log(rsTextCancelled);
end;

procedure TDialogsMainForm.BtnSelectValueClick(Sender: TObject);
var
  items: TStringList;
  idx: Integer;
begin
  items := TStringList.Create;
  try
    items.Add(rsSVOptA);
    items.Add(rsSVOptB);
    items.Add(rsSVOptC);
    idx := 0;
    if TySelectValue(rsSVTitle, rsSVPrompt, items, idx) then
      Log(Format(rsSVResult, [items[idx]]))
    else
      Log(rsSVCancelled);
  finally
    items.Free;
  end;
end;

procedure TDialogsMainForm.BtnSelectPathClick(Sender: TObject);
var
  dir: string;
begin
  dir := '';
  if TySelectDirectory(rsSPTitle, '', dir) then
    Log(Format(rsSPResult, [dir]))
  else
    Log(rsSPCancelled);
end;

procedure TDialogsMainForm.BtnSelectPathRootedClick(Sender: TObject);
var
  root, dir: string;
begin
  // ARoot <> '' constrains the tree to ONE root instead of listing every drive; seeding the
  // in/out Directory with a path inside that root makes the dialog open revealed on it.
  root := ExtractFilePath(ExpandFileName(ParamStr(0)));
  dir := root;
  if TySelectDirectory(rsSPRootTitle, root, dir) then
    Log(Format(rsSPRootResult, [dir]))
  else
    Log(rsSPCancelled);
end;

procedure TDialogsMainForm.BtnColorClick(Sender: TObject);
var
  c: TTyColor;
  lcl: TColor;
  alpha: Byte;
begin
  c := TyRGBA(255, 128, 0, 255);
  if TySelectColor(rsColorTitle, c) then
    Log(Format(rsColorResult,
      [TyRedOf(c), TyGreenOf(c), TyBlueOf(c), TyAlphaOf(c)]))
  else
    Log(rsColorCancelled);
  // Second overload: plain LCL TColor + a separate alpha byte, for code that already speaks TColor.
  lcl := ColorToRGB(Memo1.Font.Color);
  alpha := 255;
  if TySelectColor(rsColorLCLTitle, lcl, alpha) then
    Log(Format(rsColorLCLResult, [Red(lcl), Green(lcl), Blue(lcl), alpha]))
  else
    Log(rsColorCancelled);
end;

procedure TDialogsMainForm.BtnFontClick(Sender: TObject);
var
  f: TFont;
begin
  f := TFont.Create;
  try
    f.Assign(Memo1.Font);
    if TyFontDialog(f) then
      Log(Format(rsFontResult, [f.Name, f.Size]))
    else
      Log(rsFontCancelled);
  finally
    f.Free;
  end;
end;

{ ---- Modeless dialogs ---------------------------------------------------- }

procedure TDialogsMainForm.BtnFindClick(Sender: TObject);
begin
  // Modeless: Execute returns immediately; results surface through DoFind.
  Log(rsFindOpened);
  FFindDlg.Execute;
end;

procedure TDialogsMainForm.DoFind(Sender: TObject);
var
  d: TTyFindDialog;
begin
  d := Sender as TTyFindDialog;
  Log(Format(rsFindNext,
    [d.FindText, BoolToStr(frMatchCase in d.Options, True),
     BoolToStr(frWholeWord in d.Options, True)]));
end;

procedure TDialogsMainForm.BtnCloseFindClick(Sender: TObject);
begin
  // A modeless dialog can be dismissed from the app, not only by its own Close button.
  FFindDlg.CloseDialog;
  Log(rsFindClosed);
end;

procedure TDialogsMainForm.BtnReplaceClick(Sender: TObject);
begin
  Log(rsReplaceOpened);
  FReplaceDlg.Execute;
end;

procedure TDialogsMainForm.DoReplace(Sender: TObject);
var
  d: TTyReplaceDialog;
begin
  d := Sender as TTyReplaceDialog;
  // Replace and Replace All both fire OnReplace; tell them apart via frReplaceAll.
  if frReplaceAll in d.Options then
    Log(Format(rsReplaceAllMsg, [d.FindText, d.ReplaceText]))
  else
    Log(Format(rsReplaceOneMsg, [d.FindText, d.ReplaceText]));
end;

procedure TDialogsMainForm.BtnProgressClick(Sender: TObject);
const
  N = 40;
var
  prog: TTyProgressDialog;
  i, j: Integer;
  busy: Int64;
begin
  prog := TTyProgressDialog.Create(Self);
  try
    prog.Caption := rsProgWorking;
    prog.Text := rsProgPreparing;      // seeds the status line BEFORE the window first paints
    prog.Min := 0;
    prog.Max := N;
    prog.Cancelable := True;
    prog.OnCancel := @ProgressCancel;  // fired the moment Cancel (or Esc) is hit
    prog.Show;
    for i := 0 to N - 1 do
    begin
      // OnCancel only NOTIFIES; the worker still has to poll Cancelled to stop the loop.
      if prog.Cancelled then
      begin
        Log(rsProgCancelled);
        Exit;
      end;
      // The real "work" is instant, so spin a tiny busy loop to let the bar visibly advance.
      busy := 0;
      for j := 1 to 2000000 do Inc(busy);
      if i < N div 2 then
        prog.SetProgress(i + 1, Format(rsProgItem, [i + 1, N]))   // absolute position + new text
      else
        prog.Step(1);   // Step advances Position by ADelta and keeps the current text
    end;
    Log(rsProgDone);
  finally
    prog.Close;
    prog.Free;
  end;
end;

procedure TDialogsMainForm.ProgressCancel(Sender: TObject);
begin
  Log(rsProgCancelEvt);
end;

procedure TDialogsMainForm.BtnAboutClick(Sender: TObject);
begin
  // Global one-liner: a themed About box. Empty fields (here: copyright) are hidden.
  TyShowAbout(rsAboutTitle, 'TyControls', Format(rsVersionFmt, [TyVersion]), rsAboutDesc,
    '', 'LGPL', 'https://github.com/ACTom/TyControls');
  Log(rsAboutShown);
end;

{ ---- Build your own dialog on the shared base ---------------------------- }

procedure TDialogsMainForm.BtnCustomDialogClick(Sender: TObject);
var
  dlg: TTyDialog;
  edt: TTyEdit;
begin
  // Every dialog above is built from TTyDialog: a themed frame, a content area (ContentRect)
  // and a right-aligned button bar. Nothing stops an app from authoring one the same way.
  dlg := TTyDialog.CreateNew(Self);
  try
    dlg.Caption := rsCustomTitle;
    dlg.Resizable := True;             // adds the edge-drag border (the X stays the only button)
    edt := TTyEdit.Create(dlg);
    edt.Parent := dlg;
    edt.Text := rsCustomSeed;
    // ContentRect = the client area minus the title strip and the button bar.
    edt.SetBounds(dlg.ContentRect.Left + TyDlgPad, dlg.ContentRect.Top + TyDlgPad,
      TyDlgEditW, TyDlgEditH);
    // Index 0 is the RIGHTMOST button; Enter picks the default, Esc the cancel one.
    dlg.AddButton(rsCustomSave, mrOK, True, False);
    dlg.AddButton(rsCustomCancel, mrCancel, False, True);
    dlg.AutoSizeToContent(TyDlgEditW + TyDlgPad, TyDlgEditH + 2 * TyDlgPad);
    if dlg.ShowModal = mrOK then
      Log(Format(rsCustomResult, [edt.Text]))
    else
      Log(rsCustomCancelled);
  finally
    dlg.Free;
  end;
end;

{ ---- The component API (configured in mainform.lfm) ---------------------- }

procedure TDialogsMainForm.BtnCompMessageClick(Sender: TObject);
begin
  // Title / Msg / DlgType / Buttons all come from the Object Inspector — no arguments here.
  Log(Format(rsCompMsgResult, [ResultName(DlgMessage.Execute)]));
end;

procedure TDialogsMainForm.BtnCompInputClick(Sender: TObject);
begin
  // Value is in AND out: what the user accepts becomes the next Execute's default.
  if DlgInput.Execute then
    Log(Format(rsCompInputResult, [DlgInput.Value]))
  else
    Log(rsCompInputCancel);
end;

procedure TDialogsMainForm.BtnCompColorClick(Sender: TObject);
begin
  if DlgColor.Execute then
    Log(Format(rsCompColorResult, [TyRedOf(DlgColor.Color), TyGreenOf(DlgColor.Color),
      TyBlueOf(DlgColor.Color), DlgColor.Alpha]))
  else
    Log(rsCompColorCancel);
end;

procedure TDialogsMainForm.DlgComponentShow(Sender: TObject);
begin
  Log(Format(rsCompShown, [(Sender as TCustomForm).Caption]));
end;

procedure TDialogsMainForm.DlgComponentCanClose(Sender: TObject; var CanClose: Boolean);
begin
  // The veto seam: set CanClose := False here and the dialog refuses to go away.
  CanClose := True;
  Log(Format(rsCompCanClose, [(Sender as TCustomForm).Caption]));
end;

end.
