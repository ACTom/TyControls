unit mainform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Graphics, Forms, Controls, Dialogs,
  tyControls.Types, tyControls.Controller, tyControls.Form, tyControls.Button,
  tyControls.TyLabel, tyControls.Panel, tyControls.Memo, tyControls.BuiltinThemes,
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
  private
    FFindDlg: TTyFindDialog;
    FReplaceDlg: TTyReplaceDialog;
    procedure InitThemes;
    procedure ApplyBuiltin(const AName: string);
    procedure Log(const AMsg: string);
    procedure DoFind(Sender: TObject);
    procedure DoReplace(Sender: TObject);
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
  rsPwdEmpty       = 'Password: empty / cancelled';
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

{ TDialogsMainForm }

procedure TDialogsMainForm.FormCreate(Sender: TObject);
begin
  InitThemes;
  // Modeless dialogs are non-visual components created once and reused across Execute calls.
  FFindDlg := TTyFindDialog.Create(Self);
  FFindDlg.OnFind := @DoFind;
  FReplaceDlg := TTyReplaceDialog.Create(Self);
  FReplaceDlg.OnReplace := @DoReplace;
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

{ ---- Modal dialogs ------------------------------------------------------- }

procedure TDialogsMainForm.BtnMessageClick(Sender: TObject);
begin
  // Confirmation box via the primary global API; returns a TModalResult.
  if TyMessageDlg(rsMsgPrompt, mtConfirmation, [mbYes, mbNo]) = mrYes then
    Log(rsMsgYes)
  else
    Log(rsMsgNo);
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
end;

procedure TDialogsMainForm.BtnPasswordClick(Sender: TObject);
var
  pwd: string;
begin
  pwd := TyPasswordBox(rsPwdTitle, rsPwdPrompt);
  if pwd <> '' then
    Log(Format(rsPwdResult, [Length(pwd)]))
  else
    Log(rsPwdEmpty);
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

procedure TDialogsMainForm.BtnColorClick(Sender: TObject);
var
  c: TTyColor;
begin
  c := TyRGBA(255, 128, 0, 255);
  if TySelectColor(rsColorTitle, c) then
    Log(Format(rsColorResult,
      [TyRedOf(c), TyGreenOf(c), TyBlueOf(c), TyAlphaOf(c)]))
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
    prog.Min := 0;
    prog.Max := N;
    prog.Cancelable := True;
    prog.Show;
    for i := 0 to N - 1 do
    begin
      if prog.Cancelled then
      begin
        Log(rsProgCancelled);
        Exit;
      end;
      // The real "work" is instant, so spin a tiny busy loop to let the bar visibly advance.
      busy := 0;
      for j := 1 to 2000000 do Inc(busy);
      prog.SetProgress(i + 1, Format(rsProgItem, [i + 1, N]));   // repaints + pumps
    end;
    Log(rsProgDone);
  finally
    prog.Close;
    prog.Free;
  end;
end;

procedure TDialogsMainForm.BtnAboutClick(Sender: TObject);
begin
  // Global one-liner: a themed About box. Empty fields (here: copyright) are hidden.
  TyShowAbout(rsAboutTitle, 'TyControls', 'Version ' + TyVersion, rsAboutDesc,
    '', 'LGPL', 'https://github.com/ACTom/TyControls');
  Log(rsAboutShown);
end;

end.
