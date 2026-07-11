unit umain;

{ TTyToggleSwitch demo:
  - Checked: two initial states, off/on by default (ON maps through CurrentStates to :active, and the theme renders a highlighted track)
  - Caption: built-in text label to the right of the switch
  - Enabled: a disabled switch cannot be clicked/toggled
  - OnChange: refreshes the status label at the bottom on toggle
  UI is built entirely in code (no .lfm); the main form is TTyForm + TTyTitleBar, with the theme loaded by the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.ToggleSwitch, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FSwitchDark: TTyToggleSwitch;    // off by default
    FSwitchNotify: TTyToggleSwitch;  // on by default
    FSwitchCaption: TTyToggleSwitch; // with a Caption
    FSwitchDisabled: TTyToggleSwitch; // disabled
    FStatus: TTyLabel;
    procedure SwitchChange(Sender: TObject);
    procedure UpdateStatus;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to find the repo's themes/ folder (handles lib/<cpu>-<os>/ and .app bundles) }
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

function OnOff(B: Boolean): string;
begin
  if B then Result := '开' else Result := '关';
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  LblDark, LblNotify: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistence engine
  Caption := 'ToggleSwitch 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 400, 300);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load the theme first

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'ToggleSwitch  · TyControls';

  // Switch 1: off by default
  LblDark := TTyLabel.Create(Self);
  LblDark.Parent := Self;
  LblDark.SetBounds(24, 56, 220, 24);
  LblDark.Caption := '深色模式：';

  FSwitchDark := TTyToggleSwitch.Create(Self);
  FSwitchDark.Parent := Self;
  FSwitchDark.SetBounds(250, 56, 44, 24);
  FSwitchDark.Checked := False;            // off by default
  FSwitchDark.OnChange := @SwitchChange;

  // Switch 2: on by default (ON -> :active, rendered in the theme's highlight color)
  LblNotify := TTyLabel.Create(Self);
  LblNotify.Parent := Self;
  LblNotify.SetBounds(24, 100, 220, 24);
  LblNotify.Caption := '接收通知：';

  FSwitchNotify := TTyToggleSwitch.Create(Self);
  FSwitchNotify.Parent := Self;
  FSwitchNotify.SetBounds(250, 100, 44, 24);
  FSwitchNotify.Checked := True;           // on by default, CurrentStates includes tysActive
  FSwitchNotify.OnChange := @SwitchChange;

  // Switch 3: built-in Caption (text drawn to the right of the switch)
  FSwitchCaption := TTyToggleSwitch.Create(Self);
  FSwitchCaption.Parent := Self;
  FSwitchCaption.SetBounds(24, 144, 220, 24);
  FSwitchCaption.Caption := '自动保存';    // Caption property
  FSwitchCaption.Checked := True;
  FSwitchCaption.OnChange := @SwitchChange;

  // Switch 4: disabled state (cannot be clicked/toggled)
  FSwitchDisabled := TTyToggleSwitch.Create(Self);
  FSwitchDisabled.Parent := Self;
  FSwitchDisabled.SetBounds(24, 188, 220, 24);
  FSwitchDisabled.Caption := '试验功能（禁用）';
  FSwitchDisabled.Checked := False;
  FSwitchDisabled.Enabled := False;        // Enabled=False -> disabled
  FSwitchDisabled.OnChange := @SwitchChange;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 240, 360, 40);
  UpdateStatus;

  ApplyChromeTheme(TyDefaultController);   // finally, theme the whole chrome + form background in one pass
end;

procedure TMainForm.SwitchChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
begin
  FStatus.Caption := Format('深色模式：%s   接收通知：%s   自动保存：%s',
    [OnOff(FSwitchDark.Checked), OnOff(FSwitchNotify.Checked),
     OnOff(FSwitchCaption.Checked)]);
end;

end.
