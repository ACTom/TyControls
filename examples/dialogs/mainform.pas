unit mainform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Graphics, Forms, Controls, Dialogs,
  tyControls.Types, tyControls.Controller, tyControls.Form, tyControls.Button,
  tyControls.TyLabel, tyControls.Panel, tyControls.Memo, tyControls.BuiltinThemes,
  tyControls.Dialogs, tyControls.Dialogs.SelectPath, tyControls.Dialogs.Color,
  tyControls.Dialogs.Font, tyControls.Dialogs.Find, tyControls.Dialogs.Progress;

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

{ TDialogsMainForm }

procedure TDialogsMainForm.FormCreate(Sender: TObject);
begin
  InitThemes;
  // Modeless dialogs are non-visual components created once and reused across Execute calls.
  FFindDlg := TTyFindDialog.Create(Self);
  FFindDlg.OnFind := @DoFind;
  FReplaceDlg := TTyReplaceDialog.Create(Self);
  FReplaceDlg.OnReplace := @DoReplace;
  Log('Ready. Click a button to open the matching dialog.');
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
  if TyMessageDlg('Delete the selected item?', mtConfirmation, [mbYes, mbNo]) = mrYes then
    Log('Message: user chose Yes')
  else
    Log('Message: user chose No');
end;

procedure TDialogsMainForm.BtnInputClick(Sender: TObject);
var
  s: string;
begin
  s := 'Untitled';
  if TyInputQuery('Rename', 'Enter a new name:', s) then
    Log('Input: ' + s)
  else
    Log('Input: cancelled');
end;

procedure TDialogsMainForm.BtnPasswordClick(Sender: TObject);
var
  pwd: string;
begin
  pwd := TyPasswordBox('Login', 'Enter your password:');
  if pwd <> '' then
    Log(Format('Password: %d character(s) entered', [Length(pwd)]))
  else
    Log('Password: empty / cancelled');
end;

procedure TDialogsMainForm.BtnTextClick(Sender: TObject);
var
  note: string;
begin
  note := '';
  if TyTextQuery('Edit note', 'Enter a multiline note:', note) then
  begin
    note := TrimRight(note);   // TyTextQuery appends a trailing LineEnding (TStrings.Text semantics)
    Log('Text: ' + StringReplace(note, LineEnding, ' / ', [rfReplaceAll]));
  end
  else
    Log('Text: cancelled');
end;

procedure TDialogsMainForm.BtnSelectValueClick(Sender: TObject);
var
  items: TStringList;
  idx: Integer;
begin
  items := TStringList.Create;
  try
    items.Add('Option A');
    items.Add('Option B');
    items.Add('Option C');
    idx := 0;
    if TySelectValue('Pick one', 'Choose an option:', items, idx) then
      Log('SelectValue: ' + items[idx])
    else
      Log('SelectValue: cancelled');
  finally
    items.Free;
  end;
end;

procedure TDialogsMainForm.BtnSelectPathClick(Sender: TObject);
var
  dir: string;
begin
  dir := '';
  if TySelectDirectory('Select a folder', '', dir) then
    Log('SelectPath: ' + dir)
  else
    Log('SelectPath: cancelled');
end;

procedure TDialogsMainForm.BtnColorClick(Sender: TObject);
var
  c: TTyColor;
begin
  c := TyRGBA(255, 128, 0, 255);
  if TySelectColor('Select a colour', c) then
    Log(Format('Color: R=%d G=%d B=%d A=%d',
      [TyRedOf(c), TyGreenOf(c), TyBlueOf(c), TyAlphaOf(c)]))
  else
    Log('Color: cancelled');
end;

procedure TDialogsMainForm.BtnFontClick(Sender: TObject);
var
  f: TFont;
begin
  f := TFont.Create;
  try
    f.Assign(Memo1.Font);
    if TyFontDialog(f) then
      Log(Format('Font: %s %dpt', [f.Name, f.Size]))
    else
      Log('Font: cancelled');
  finally
    f.Free;
  end;
end;

{ ---- Modeless dialogs ---------------------------------------------------- }

procedure TDialogsMainForm.BtnFindClick(Sender: TObject);
begin
  // Modeless: Execute returns immediately; results surface through DoFind.
  Log('Find: dialog opened (modeless)');
  FFindDlg.Execute;
end;

procedure TDialogsMainForm.DoFind(Sender: TObject);
var
  d: TTyFindDialog;
begin
  d := Sender as TTyFindDialog;
  Log(Format('  Find Next: "%s"  (MatchCase=%s, WholeWord=%s)',
    [d.FindText, BoolToStr(frMatchCase in d.Options, True),
     BoolToStr(frWholeWord in d.Options, True)]));
end;

procedure TDialogsMainForm.BtnReplaceClick(Sender: TObject);
begin
  Log('Replace: dialog opened (modeless)');
  FReplaceDlg.Execute;
end;

procedure TDialogsMainForm.DoReplace(Sender: TObject);
var
  d: TTyReplaceDialog;
begin
  d := Sender as TTyReplaceDialog;
  // Replace and Replace All both fire OnReplace; tell them apart via frReplaceAll.
  if frReplaceAll in d.Options then
    Log(Format('  Replace ALL: "%s" -> "%s"', [d.FindText, d.ReplaceText]))
  else
    Log(Format('  Replace: "%s" -> "%s"', [d.FindText, d.ReplaceText]));
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
    prog.Caption := 'Working…';
    prog.Min := 0;
    prog.Max := N;
    prog.Cancelable := True;
    prog.Show;
    for i := 0 to N - 1 do
    begin
      if prog.Cancelled then
      begin
        Log('Progress: cancelled by user');
        Exit;
      end;
      // The real "work" is instant, so spin a tiny busy loop to let the bar visibly advance.
      busy := 0;
      for j := 1 to 2000000 do Inc(busy);
      prog.SetProgress(i + 1, Format('Item %d of %d', [i + 1, N]));   // repaints + pumps
    end;
    Log('Progress: completed');
  finally
    prog.Close;
    prog.Free;
  end;
end;

end.
