unit umain;

{ TTyGroupBox demo:
  - Caption: each group box carries a title
  - Alignment: title left / center / right (taLeftJustify / taCenter / taRightJustify)
  - Hosting child controls: TTyRadioButton / TTyCheckBox placed inside a group box
  - A TTyEdit embedded in a group box, showing that any child control can be a container member
  - Events funnel into the bottom TTyLabel status bar
  The window, every group box + child control and the live theme switcher are designed in
  umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.GroupBox, tyControls.CheckBox, tyControls.Edit,
  tyControls.TyLabel, tyControls.ComboBox;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    GroupSize: TTyGroupBox;      // left-aligned title + radio buttons
    RadioA: TTyRadioButton;
    RadioB: TTyRadioButton;
    RadioC: TTyRadioButton;
    GroupOpt: TTyGroupBox;       // centered title + check boxes
    CheckBold: TTyCheckBox;
    CheckItalic: TTyCheckBox;
    GroupName: TTyGroupBox;      // right-aligned title + embedded edit
    NameEdit: TTyEdit;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure RadioClick(Sender: TObject);
    procedure CheckClick(Sender: TObject);
    procedure NameChange(Sender: TObject);
  private
    procedure UpdateStatus;
    function SelectedRadio: string;
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

  UpdateStatus;                            // fill the status bar with the initial selection
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

function TMainForm.SelectedRadio: string;
begin
  Result := '（未选）';
  if RadioA.Checked then Result := RadioA.Caption
  else if RadioB.Checked then Result := RadioB.Caption
  else if RadioC.Checked then Result := RadioC.Caption;
end;

procedure TMainForm.RadioClick(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.CheckClick(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.NameChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
var
  Styles: string;
begin
  Styles := '';
  if CheckBold.Checked then Styles := Styles + '加粗 ';
  if CheckItalic.Checked then Styles := Styles + '斜体 ';
  if Styles = '' then Styles := '（无）';

  LblStatus.Caption := Format('字体大小：%s    样式：%s    名称：%s',
    [SelectedRadio, Trim(Styles),
     IfThen(NameEdit.Text = '', '（空）', NameEdit.Text)]);
end;

end.
