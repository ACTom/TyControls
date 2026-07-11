unit umain;

{ TTyGroupBox demo:
  - Caption: each group box carries a title
  - Alignment: title left / center / right (taLeftJustify / taCenter / taRightJustify)
  - Hosting child controls: TTyRadioButton / TTyCheckBox placed inside a group box
  - A TTyEdit embedded in a group box, showing that any child control can be a container member
  - Events funnel into the bottom TTyLabel status bar
  UI built purely in code (no .lfm); the main form is a TTyForm with a TTyTitleBar,
  and the theme is loaded through the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.GroupBox, tyControls.CheckBox, tyControls.Edit,
  tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FGroupSize: TTyGroupBox;      // left-aligned title + radio buttons
    FGroupOpt: TTyGroupBox;       // centered title + check boxes
    FGroupName: TTyGroupBox;      // right-aligned title + embedded edit
    FStatus: TTyLabel;
    FRadioA, FRadioB, FRadioC: TTyRadioButton;
    FCheckBold, FCheckItalic: TTyCheckBox;
    FNameEdit: TTyEdit;
    procedure RadioClick(Sender: TObject);
    procedure CheckClick(Sender: TObject);
    procedure NameChange(Sender: TObject);
    procedure UpdateStatus;
    function SelectedRadio: string;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Search upward from the exe's directory for the repo's themes/ folder (handles lib/<cpu>-<os>/ and .app bundles) }
function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

function TMainForm.SelectedRadio: string;
begin
  Result := '（未选）';
  if FRadioA.Checked then Result := FRadioA.Caption
  else if FRadioB.Checked then Result := FRadioB.Caption
  else if FRadioC.Checked then Result := FRadioC.Caption;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + resident engine
  Caption := 'TTyGroupBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 620, 320);

  // Load the theme first: controls without an explicit Controller fall back to the global TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);         // Owner=Self → auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'GroupBox  · TyControls';

  // ── Group box 1: left-aligned title (default), containing radio buttons ──
  FGroupSize := TTyGroupBox.Create(Self);
  FGroupSize.Parent := Self;
  FGroupSize.SetBounds(16, 52, 185, 130);
  FGroupSize.Caption := '字体大小（左对齐）';
  FGroupSize.Alignment := taLeftJustify;

  FRadioA := TTyRadioButton.Create(FGroupSize);
  FRadioA.Parent := FGroupSize;
  FRadioA.SetBounds(10, 24, 160, 26);
  FRadioA.Caption := '小（12pt）';
  FRadioA.OnClick := @RadioClick;

  FRadioB := TTyRadioButton.Create(FGroupSize);
  FRadioB.Parent := FGroupSize;
  FRadioB.SetBounds(10, 54, 160, 26);
  FRadioB.Caption := '中（14pt）';
  FRadioB.Checked := True;                 // checked by default
  FRadioB.OnClick := @RadioClick;

  FRadioC := TTyRadioButton.Create(FGroupSize);
  FRadioC.Parent := FGroupSize;
  FRadioC.SetBounds(10, 84, 160, 26);
  FRadioC.Caption := '大（18pt）';
  FRadioC.OnClick := @RadioClick;

  // ── Group box 2: centered title, containing check boxes ──
  FGroupOpt := TTyGroupBox.Create(Self);
  FGroupOpt.Parent := Self;
  FGroupOpt.SetBounds(217, 52, 185, 130);
  FGroupOpt.Caption := '样式（居中）';
  FGroupOpt.Alignment := taCenter;

  FCheckBold := TTyCheckBox.Create(FGroupOpt);
  FCheckBold.Parent := FGroupOpt;
  FCheckBold.SetBounds(10, 24, 160, 26);
  FCheckBold.Caption := '加粗';
  FCheckBold.OnClick := @CheckClick;

  FCheckItalic := TTyCheckBox.Create(FGroupOpt);
  FCheckItalic.Parent := FGroupOpt;
  FCheckItalic.SetBounds(10, 54, 160, 26);
  FCheckItalic.Caption := '斜体';
  FCheckItalic.OnClick := @CheckClick;

  // ── Group box 3: right-aligned title, embedding an edit box ──
  FGroupName := TTyGroupBox.Create(Self);
  FGroupName.Parent := Self;
  FGroupName.SetBounds(418, 52, 185, 130);
  FGroupName.Caption := '名称（右对齐）';
  FGroupName.Alignment := taRightJustify;

  FNameEdit := TTyEdit.Create(FGroupName);
  FNameEdit.Parent := FGroupName;
  FNameEdit.SetBounds(10, 28, 160, 30);
  FNameEdit.TextHint := '请输入名称…';
  FNameEdit.OnChange := @NameChange;

  // ── Bottom status bar ──
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 200, 588, 60);
  UpdateStatus;

  ApplyChromeTheme(TyDefaultController);    // finally, theme the form chrome + background in one pass
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
  if FCheckBold.Checked then Styles := Styles + '加粗 ';
  if FCheckItalic.Checked then Styles := Styles + '斜体 ';
  if Styles = '' then Styles := '（无）';

  FStatus.Caption := Format('字体大小：%s    样式：%s    名称：%s',
    [SelectedRadio, Trim(Styles),
     IfThen(FNameEdit.Text = '', '（空）', FNameEdit.Text)]);
end;

end.
