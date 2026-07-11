unit umain;

{ Runtime theme hot-swap demo (TTyForm + TTyTitleBar edition):
  - the three buttons at the top call LoadTheme with light.tycss / dark.tycss / green.tycss;
  - internally LoadTheme calls Changed(), which walks every registered control and Invalidates it,
    so the buttons / edit / checkbox / progress bar in the sample area are recolored "live";
  - it also calls ApplyChromeTheme so the window chrome (title bar + form background) reskins too;
  - a status label shows the current theme name in real time.
  Pure-code UI (no .lfm). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.Button, tyControls.TyLabel,
  tyControls.Edit, tyControls.CheckBox, tyControls.ProgressBar;

type
  TMainForm = class(TTyForm)
  private
    FStatusLabel: TTyLabel;
    { Theme-switch handlers }
    procedure SwitchLight(Sender: TObject);
    procedure SwitchDark(Sender: TObject);
    procedure SwitchGreen(Sender: TObject);
    procedure ApplyTheme(const AFileName: string);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Search upward from the exe's directory for a themes/ directory }
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

  function MakeSwitch(const ACaption, AClass: string; ALeft: Integer;
    AHandler: TNotifyEvent): TTyButton;
  begin
    Result := TTyButton.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(ALeft, 52, 116, 34);
    Result.Caption := ACaption;
    Result.StyleClass := AClass;
    Result.OnClick := AHandler;
  end;

var
  Bar:         TTyTitleBar;
  SampleLbl:   TTyLabel;
  SampleBtn:   TTyButton;
  GhostBtn:    TTyButton;
  DisabledBtn: TTyButton;
  SampleEdit:  TTyEdit;
  SampleCheck: TTyCheckBox;
  Progress:    TTyProgressBar;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + always-on paint engine
  Caption := '主题系统 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 470, 340);

  // Load the initial theme first, then build the chrome
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);         // Owner=Self → auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := '主题系统  · TyControls';

  // ── Theme-switch button row (a click runs LoadTheme + ApplyChromeTheme for a live reskin) ──
  MakeSwitch('亮色 Light', 'primary', 16,  @SwitchLight);
  MakeSwitch('暗色 Dark',  '',        148, @SwitchDark);
  MakeSwitch('绿色 Green', '',        280, @SwitchGreen);

  // Current-theme indicator
  FStatusLabel := TTyLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.SetBounds(16, 96, 430, 20);
  FStatusLabel.Caption := '当前主题：light.tycss';

  // ── Sample-control area: these controls recolor live with the theme ──────────────
  SampleLbl := TTyLabel.Create(Self);
  SampleLbl.Parent := Self;
  SampleLbl.SetBounds(16, 128, 300, 20);
  SampleLbl.Caption := '示例标签 TTyLabel';

  SampleBtn := TTyButton.Create(Self);
  SampleBtn.Parent := Self;
  SampleBtn.SetBounds(16, 156, 120, 34);
  SampleBtn.Caption := '主要按钮';
  SampleBtn.StyleClass := 'primary';

  GhostBtn := TTyButton.Create(Self);
  GhostBtn.Parent := Self;
  GhostBtn.SetBounds(148, 156, 100, 34);
  GhostBtn.Caption := '幽灵按钮';
  GhostBtn.StyleClass := 'ghost';

  DisabledBtn := TTyButton.Create(Self);
  DisabledBtn.Parent := Self;
  DisabledBtn.SetBounds(260, 156, 100, 34);
  DisabledBtn.Caption := '禁用态';
  DisabledBtn.Enabled := False;

  SampleEdit := TTyEdit.Create(Self);
  SampleEdit.Parent := Self;
  SampleEdit.SetBounds(16, 204, 220, 30);
  SampleEdit.Text := '可编辑文本框';

  SampleCheck := TTyCheckBox.Create(Self);
  SampleCheck.Parent := Self;
  SampleCheck.SetBounds(260, 208, 160, 24);
  SampleCheck.Caption := '复选框示例';
  SampleCheck.Checked := True;

  Progress := TTyProgressBar.Create(Self);
  Progress.Parent := Self;
  Progress.SetBounds(16, 252, 420, 18);
  Progress.Min := 0;
  Progress.Max := 100;
  Progress.Position := 65;

  ApplyChromeTheme(TyDefaultController);    // Finally, reskin the chrome + form background together
end;

procedure TMainForm.ApplyTheme(const AFileName: string);
begin
  // Inside LoadTheme: FModel.LoadFromFile → Changed(),
  // Changed() walks every registered control and Invalidates them all → sample controls reskin live;
  // then ApplyChromeTheme makes the title bar + form background follow along.
  TyDefaultController.LoadTheme(ThemesDir + AFileName);
  ApplyChromeTheme(TyDefaultController);
  FStatusLabel.Caption := '当前主题：' + AFileName;
end;

procedure TMainForm.SwitchLight(Sender: TObject);
begin
  ApplyTheme('light.tycss');
end;

procedure TMainForm.SwitchDark(Sender: TObject);
begin
  ApplyTheme('dark.tycss');
end;

procedure TMainForm.SwitchGreen(Sender: TObject);
begin
  ApplyTheme('green.tycss');
end;

end.
