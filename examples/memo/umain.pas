unit umain;

{ TTyMemo demo (borderless self-drawn TTyForm chrome + TTyTitleBar):
  - Lines: multi-line text model (Enter for new line, Backspace/Delete merge across lines, arrow/Home/End navigation)
  - ScrollBars: defaults to ssAutoVertical; a vertical scrollbar appears on the right when content overflows; mouse wheel supported
    (the combo below the memo walks every TScrollStyle; the horizontal bar only applies while WordWrap is off)
  - ReadOnly: when checked, all user edits are ignored (navigation/selection/copy still work)
  - WordWrap: when checked, long logical lines soft-wrap at word boundaries into multiple visual lines
  - HideSelection / MaxLength / WantTabs / WantReturns: the remaining published knobs, one checkbox each
  - Undo / Redo / CanUndo / CanRedo: the built-in coalescing undo stack (Ctrl+Z, Ctrl+Y, Ctrl+Shift+Z)
  - SelectAll / CopyToClipboard / CutToClipboard / PasteFromClipboard: the clipboard API behind the gestures
  - OnChange: fires whenever the text model changes; updates the line/character count labels live
  - OnSelectionChange: fires on caret/selection moves; reads the flat CaretPos/SelStart/SelLength/SelText accessors
  The window, the memo, every toggle and the live theme switcher are designed in umain.lfm
  (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, StdCtrls, LazUTF8,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Memo, tyControls.TyLabel, tyControls.CheckBox, tyControls.ComboBox,
  tyControls.ToggleSwitch, tyControls.Button;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblPrompt: TTyLabel;
    Memo: TTyMemo;
    ChkReadOnly: TTyCheckBox;
    ChkWordWrap: TTyCheckBox;
    LblInfo: TTyLabel;
    BtnSelectAll: TTyButton;
    BtnCopy: TTyButton;
    BtnCut: TTyButton;
    BtnPaste: TTyButton;
    BtnUndo: TTyButton;
    BtnRedo: TTyButton;
    LblKeys: TTyLabel;
    LblOptions: TTyLabel;
    ChkHideSel: TTyCheckBox;
    ChkWantTabs: TTyCheckBox;
    ChkWantReturns: TTyCheckBox;
    BtnDefault: TTyButton;
    ChkLimit: TTyCheckBox;
    LblScroll: TTyLabel;
    CmbScroll: TTyComboBox;
    LblScrollHint: TTyLabel;
    LblCaret: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure MemoChange(Sender: TObject);
    procedure MemoSelectionChange(Sender: TObject);
    procedure ReadOnlyClick(Sender: TObject);
    procedure WordWrapClick(Sender: TObject);
    procedure SelectAllClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure CutClick(Sender: TObject);
    procedure PasteClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure HideSelectionClick(Sender: TObject);
    procedure WantTabsClick(Sender: TObject);
    procedure WantReturnsClick(Sender: TObject);
    procedure MaxLengthClick(Sender: TObject);
    procedure DefaultButtonClick(Sender: TObject);
    procedure ScrollBarsChange(Sender: TObject);
  private
    procedure UpdateInfo;
    procedure UpdateCaretInfo;
    procedure UpdateUndoButtons;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // The seed lines come from the .lfm; compute the initial line/char stats.
  UpdateInfo;
  // Fill the caret readout once so it is not blank before the first click, and
  // grey out Undo/Redo until the undo stack actually has something on it.
  UpdateCaretInfo;
  UpdateUndoButtons;
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.UpdateInfo;
var
  i, chars: Integer;
  cap: string;
begin
  // MaxLength charges CONTENT codepoints only (the line breaks are free), so the
  // readout counts the same way and walks visibly up to the ceiling.
  chars := 0;
  for i := 0 to Memo.Lines.Count - 1 do
    Inc(chars, UTF8Length(Memo.Lines[i]));
  if Memo.MaxLength > 0 then
    cap := IntToStr(Memo.MaxLength)
  else
    cap := 'no cap';
  LblInfo.Caption := Format('Line count: %d    Char count: %d / %s',
    [Memo.Lines.Count, chars, cap]);
end;

procedure TMainForm.UpdateCaretInfo;
begin
  // The flat accessors address the whole document by codepoint offset (one offset
  // for the line break between two lines), exactly like a native TMemo.
  LblCaret.Caption := Format('CaretPos %d · SelStart %d · SelLength %d · selected: "%s"',
    [Memo.CaretPos, Memo.SelStart, Memo.SelLength, UTF8Copy(Memo.SelText, 1, 20)]);
end;

procedure TMainForm.UpdateUndoButtons;
begin
  // CanUndo/CanRedo drive the buttons the way a real editor greys out its toolbar.
  BtnUndo.Enabled := Memo.CanUndo;
  BtnRedo.Enabled := Memo.CanRedo;
end;

procedure TMainForm.MemoChange(Sender: TObject);
begin
  // OnChange: refresh the stats whenever the text model changes
  UpdateInfo;
  UpdateCaretInfo;
  UpdateUndoButtons;
end;

procedure TMainForm.MemoSelectionChange(Sender: TObject);
begin
  // OnSelectionChange: caret moves and shift/drag selection, without a text edit.
  UpdateCaretInfo;
end;

procedure TMainForm.ReadOnlyClick(Sender: TObject);
begin
  Memo.ReadOnly := ChkReadOnly.Checked;
end;

procedure TMainForm.WordWrapClick(Sender: TObject);
begin
  Memo.WordWrap := ChkWordWrap.Checked;
end;

procedure TMainForm.SelectAllClick(Sender: TObject);
begin
  Memo.SelectAll;
  UpdateCaretInfo;
end;

procedure TMainForm.CopyClick(Sender: TObject);
begin
  // Copy/Cut need a selection; Cut on a ReadOnly memo degrades to Copy.
  Memo.CopyToClipboard;
end;

procedure TMainForm.CutClick(Sender: TObject);
begin
  Memo.CutToClipboard;
end;

procedure TMainForm.PasteClick(Sender: TObject);
begin
  // Paste splits the clipboard text on CR/LF into one or more logical lines.
  Memo.PasteFromClipboard;
end;

procedure TMainForm.UndoClick(Sender: TObject);
begin
  Memo.Undo;                 // typing coalesces into one step, so this eats a word
  UpdateUndoButtons;
end;

procedure TMainForm.RedoClick(Sender: TObject);
begin
  Memo.Redo;
  UpdateUndoButtons;
end;

procedure TMainForm.HideSelectionClick(Sender: TObject);
begin
  // Only changes the UNFOCUSED look: select some text, then click another control.
  Memo.HideSelection := ChkHideSel.Checked;
end;

procedure TMainForm.WantTabsClick(Sender: TObject);
begin
  Memo.WantTabs := ChkWantTabs.Checked;
end;

procedure TMainForm.WantReturnsClick(Sender: TObject);
begin
  // Off: the memo leaves Enter alone, so the form's default button gets it.
  Memo.WantReturns := ChkWantReturns.Checked;
end;

procedure TMainForm.MaxLengthClick(Sender: TObject);
begin
  // 0 = unlimited. 800 sits just above the seed text, so a short burst of typing
  // reaches the cap and stops there instead of being rejected outright.
  if ChkLimit.Checked then
    Memo.MaxLength := 800
  else
    Memo.MaxLength := 0;
  UpdateInfo;
end;

procedure TMainForm.DefaultButtonClick(Sender: TObject);
begin
  LblInfo.Caption := 'Default button fired - Enter fell through because WantReturns=False';
end;

procedure TMainForm.ScrollBarsChange(Sender: TObject);
begin
  if CmbScroll.ItemIndex < 0 then Exit;
  // The combo items are listed in TScrollStyle declaration order, so the index IS
  // the enum value: ssNone, ssHorizontal, ssVertical, ssBoth, ssAutoHorizontal,
  // ssAutoVertical, ssAutoBoth.
  Memo.ScrollBars := TScrollStyle(CmbScroll.ItemIndex);
end;

end.
