unit umain;

{ TTyPanel demo (TTyForm custom-drawn window frame + title bar):
    - Caption: the panel's title text (note: TTyPanel.Caption is always drawn centered)
    - Alignment: horizontal alignment reference for the child controls (used here as a layout note)
    - As a container: place TTyLabel / TTyEdit / TTyButton inside the panel, and nest a sub-panel
    - Align: alBottom / alLeft docking demo, width/height auto-stretch with the form
  The panel's background, border and rounded corners all come from the theme's TyPanel rules;
  no need to hand-code colors here.
  UI is built purely in code (no .lfm); the theme is loaded via the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.Panel, tyControls.Button, tyControls.TyLabel, tyControls.Edit;

type
  TMainForm = class(TTyForm)
  private
    FNameEdit: TTyEdit;
    FResultLabel: TTyLabel;
    procedure GreetClicked(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to find the repo's themes/ directory }
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

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  OuterPanel, InnerPanel, RightPanel, BottomPanel: TTyPanel;
  Lbl: TTyLabel;
  Btn: TTyButton;
begin
  // TTyForm.CreateNew → borderless + persistent engine, but no title bar by default
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyPanel 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 560, 400);

  // The theme must be loaded first
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // Title bar: Owner=Self auto-associates it as TTyForm.TitleBar
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyPanel  · TyControls';

  { --- Outer container Panel: Caption left-aligned --- }
  OuterPanel := TTyPanel.Create(Self);
  OuterPanel.Parent := Self;
  OuterPanel.Caption := '用户信息（Caption 左对齐）';
  OuterPanel.Alignment := taLeftJustify;   // title text left-aligned
  OuterPanel.SetBounds(16, 50, 340, 190);

  { Inside the container: label }
  Lbl := TTyLabel.Create(OuterPanel);
  Lbl.Parent := OuterPanel;
  Lbl.SetBounds(12, 40, 64, 24);
  Lbl.Caption := '姓名：';

  { Inside the container: edit box }
  FNameEdit := TTyEdit.Create(OuterPanel);
  FNameEdit.Parent := OuterPanel;
  FNameEdit.SetBounds(80, 40, 240, 26);
  FNameEdit.Text := '';

  { Inside the container: button }
  Btn := TTyButton.Create(OuterPanel);
  Btn.Parent := OuterPanel;
  Btn.SetBounds(80, 80, 120, 32);
  Btn.Caption := '打招呼';
  Btn.StyleClass := 'primary';
  Btn.OnClick := @GreetClicked;

  { Inside the container: nested sub-panel (proves Panel is a real container control), Caption centered (default) }
  InnerPanel := TTyPanel.Create(OuterPanel);
  InnerPanel.Parent := OuterPanel;
  InnerPanel.Caption := '嵌套子面板（居中）';
  InnerPanel.Alignment := taCenter;        // taCenter is the default; shown explicitly here
  InnerPanel.SetBounds(12, 124, 316, 52);

  { --- Right-column Panel: a genuinely themed container, Caption (drawn centered) + embedded child controls --- }
  RightPanel := TTyPanel.Create(Self);
  RightPanel.Parent := Self;
  RightPanel.Caption := '说明';               // Caption is drawn centered by the theme in the panel's top area
  RightPanel.SetBounds(372, 50, 172, 190);

  { Description label inside the right-column container (proves the panel truly hosts child controls) }
  Lbl := TTyLabel.Create(RightPanel);
  Lbl.Parent := RightPanel;
  Lbl.SetBounds(12, 40, 148, 140);
  Lbl.Caption := '面板的背景、边框与圆角均来自主题 TyPanel 规则，无需手写颜色。';

  { --- Result label --- }
  FResultLabel := TTyLabel.Create(Self);
  FResultLabel.Parent := Self;
  FResultLabel.SetBounds(16, 252, 528, 24);
  FResultLabel.Caption := '点击“打招呼”按钮试试…';

  { --- Bottom-docked Panel: demonstrates Align=alBottom (width auto-stretches with the form) --- }
  BottomPanel := TTyPanel.Create(Self);
  BottomPanel.Parent := Self;
  BottomPanel.Caption := 'Align = alBottom';   // Caption drawn centered
  BottomPanel.Align := alBottom;
  BottomPanel.Height := 44;

  // Full window frame + background color follow the theme
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.GreetClicked(Sender: TObject);
var
  UserName: string;
begin
  UserName := FNameEdit.Text;
  if UserName = '' then
    FResultLabel.Caption := '请先输入姓名！'
  else
    FResultLabel.Caption := Format('你好，%s！欢迎使用 TyControls。', [UserName]);
end;

end.
