unit umain;

{ TTyEdit demo (TTyForm custom-drawn window frame + TTyTitleBar):
    Showcases TTyEdit's core published properties, one mode per input box:
      - TextHint      placeholder hint (shown dimmed when the text is empty)
      - PasswordChar  password mask character
      - CharCase      case forcing (ecUppercase / ecLowerCase)
      - MaxLength     maximum character-count limit
      - NumbersOnly   digits only
      - ReadOnly      read-only (OnClick still fires on it)
      - Alignment     text alignment (taCenter / taRightJustify)
    The first input box hooks OnChange to echo its content live into the
    bottom status-bar TTyLabel.
    The button rows at the bottom drive TTyEdit's RUNTIME api, which the
    keyboard reaches too:
      - Undo / Redo / CanUndo / CanRedo   the built-in undo stack (Ctrl+Z / Ctrl+Y)
      - Copy / Cut / PasteFromClipboard   clipboard (Ctrl+C / Ctrl+X / Ctrl+V),
                                          suppressed while PasswordChar is set
      - SelectAll / SelStart / SelLength / SelText   the selection accessors
  The window, every input box and the live theme switcher are designed in
  umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers +
  theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.Edit, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.Button;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblHint: TTyLabel;
    EdHint: TTyEdit;
    LblPassword: TTyLabel;
    EdPassword: TTyEdit;
    LblUpper: TTyLabel;
    EdUpper: TTyEdit;
    LblMaxLen: TTyLabel;
    EdMaxLen: TTyEdit;
    LblNumbers: TTyLabel;
    EdNumbers: TTyEdit;
    LblReadOnly: TTyLabel;
    EdReadOnly: TTyEdit;
    LblRight: TTyLabel;
    EdRight: TTyEdit;
    LblLower: TTyLabel;
    EdLower: TTyEdit;
    LblCenter: TTyLabel;
    EdCenter: TTyEdit;
    LblRuntime: TTyLabel;
    LblUndo: TTyLabel;
    BtnUndo: TTyButton;
    BtnRedo: TTyButton;
    LblUndoHint: TTyLabel;
    LblClip: TTyLabel;
    BtnCopy: TTyButton;
    BtnCut: TTyButton;
    BtnPaste: TTyButton;
    LblMask: TTyLabel;
    BtnCopyPwd: TTyButton;
    LblSel: TTyLabel;
    BtnSelectAll: TTyButton;
    BtnSelectRange: TTyButton;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure EditChanged(Sender: TObject);   // OnChange -> status bar
    procedure ReadOnlyClicked(Sender: TObject);   // OnClick fires even when ReadOnly
    procedure BtnUndoClick(Sender: TObject);
    procedure BtnRedoClick(Sender: TObject);
    procedure BtnCopyClick(Sender: TObject);
    procedure BtnCutClick(Sender: TObject);
    procedure BtnPasteClick(Sender: TObject);
    procedure BtnCopyPwdClick(Sender: TObject);
    procedure BtnSelectAllClick(Sender: TObject);
    procedure BtnSelectRangeClick(Sender: TObject);
  private
    procedure UpdateUndoRedo;   // mirror EdHint.CanUndo / CanRedo onto the two buttons
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
  UpdateUndoRedo;   // nothing typed yet, so both buttons start greyed out
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

procedure TMainForm.EditChanged(Sender: TObject);
begin
  // read TTyEdit.Text live
  LblStatus.Caption := 'Current input:' + (Sender as TTyEdit).Text;
  UpdateUndoRedo;   // every edit changes what the undo stack can offer
end;

procedure TMainForm.UpdateUndoRedo;
begin
  // CanUndo / CanRedo report the undo stack's state; typing is coalesced into
  // one step, and paste / cut / select-and-replace each collapse into one too.
  BtnUndo.Enabled := EdHint.CanUndo;
  BtnRedo.Enabled := EdHint.CanRedo;
end;

procedure TMainForm.ReadOnlyClicked(Sender: TObject);
begin
  // ReadOnly blocks editing, not events -- OnClick still reaches the app.
  LblStatus.Caption := 'Read-only box clicked (OnClick still fires)';
end;

procedure TMainForm.BtnUndoClick(Sender: TObject);
begin
  EdHint.Undo;      // identical to pressing Ctrl+Z inside the box
  UpdateUndoRedo;
end;

procedure TMainForm.BtnRedoClick(Sender: TObject);
begin
  EdHint.Redo;      // identical to pressing Ctrl+Y inside the box
  UpdateUndoRedo;
end;

procedure TMainForm.BtnCopyClick(Sender: TObject);
begin
  // CopyToClipboard acts on the selection only, so select everything first
  // when the user has not dragged one out.
  if not EdHint.HasSelection then
    EdHint.SelectAll;
  if not EdHint.HasSelection then
  begin
    LblStatus.Caption := 'Nothing to copy - type into the top box first';
    Exit;
  end;
  EdHint.CopyToClipboard;
  LblStatus.Caption := 'Copied to clipboard: ' + EdHint.SelText;
end;

procedure TMainForm.BtnCutClick(Sender: TObject);
var
  taken: string;
begin
  if not EdHint.HasSelection then
    EdHint.SelectAll;
  if not EdHint.HasSelection then
  begin
    LblStatus.Caption := 'Nothing to cut - type into the top box first';
    Exit;
  end;
  taken := EdHint.SelText;
  EdHint.CutToClipboard;   // copy + delete land in a SINGLE undo step
  UpdateUndoRedo;
  // set the caption after the cut: it fires OnChange, which rewrites the label
  LblStatus.Caption := 'Cut to clipboard: ' + taken;
end;

procedure TMainForm.BtnPasteClick(Sender: TObject);
begin
  EdHint.PasteFromClipboard;   // line breaks stripped; also a single undo step
  UpdateUndoRedo;
  LblStatus.Caption := 'Pasted, the box now reads: ' + EdHint.Text;
end;

procedure TMainForm.BtnCopyPwdClick(Sender: TObject);
begin
  // Deliberate security behaviour: with PasswordChar set, Copy and Cut are
  // no-ops, so masked text can never reach the clipboard.
  EdPassword.SelectAll;
  EdPassword.CopyToClipboard;
  LblStatus.Caption := 'Nothing was copied - PasswordChar blocks Copy and Cut';
end;

procedure TMainForm.BtnSelectAllClick(Sender: TObject);
begin
  EdReadOnly.SelectAll;   // the same thing a double-click in the box does
  LblStatus.Caption := 'SelStart=' + IntToStr(EdReadOnly.SelStart) +
    ', SelLength=' + IntToStr(EdReadOnly.SelLength);
end;

procedure TMainForm.BtnSelectRangeClick(Sender: TObject);
begin
  // Writing SelStart collapses the selection there; writing SelLength re-extends
  // it. Indices are codepoints, not bytes.
  EdReadOnly.SelStart := 2;
  EdReadOnly.SelLength := 5;
  LblStatus.Caption := 'SelText = "' + EdReadOnly.SelText + '"';
end;

end.
