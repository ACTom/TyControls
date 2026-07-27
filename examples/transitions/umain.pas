unit umain;

{ Transitions demo -- click a button to make the content panel "reappear" with a
  different transition (slide-in / fade-in).
  Slide-in is cross-platform (it animates the position); fade-in uses AlphaBlend,
  Windows-only, and degrades to a plain show on other platforms. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.Button, tyControls.TyLabel,
  tyControls.Panel, tyControls.Transitions, tyControls.BuiltinThemes,
  tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.TrackBar;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    BtnFade:  TTyButton;
    BtnUp:    TTyButton;
    BtnDown:  TTyButton;
    BtnLeft:  TTyButton;
    BtnRight: TTyButton;
    BtnNone:  TTyButton;
    BtnHide:  TTyButton;
    LblDuration:     TTyLabel;
    DurationBar:     TTyTrackBar;
    LblDurationHint: TTyLabel;
    LblFadeNote:     TTyLabel;
    LblCancelNote:   TTyLabel;
    Target:   TTyPanel;
    LblIn:    TTyLabel;
    LblHint:  TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure BtnFadeClick(Sender: TObject);
    procedure BtnUpClick(Sender: TObject);
    procedure BtnDownClick(Sender: TObject);
    procedure BtnLeftClick(Sender: TObject);
    procedure BtnRightClick(Sender: TObject);
    procedure BtnNoneClick(Sender: TObject);
    procedure BtnHideClick(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  private
    procedure Replay(AKind: TTyTransitionKind);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
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

{ Re-show the panel with the chosen transition. No Visible := True here: the reveal is
  TyPlayTransition's job -- it shows the control itself as the animation starts, which is
  exactly what makes "Hide panel" then "Slide in from left" a real hidden->revealed cycle.
  The duration comes from the slider, so 0 exercises the documented snap path. }
procedure TMainForm.Replay(AKind: TTyTransitionKind);
begin
  TyPlayTransition(Target, AKind, DurationBar.Position);
end;

procedure TMainForm.BtnFadeClick(Sender: TObject);
begin
  // ttFade animates a FORM's opacity via AlphaBlend (Windows; a plain show elsewhere), so it
  // applies to the WINDOW -- a TTyPanel has no AlphaBlend. The slide buttons animate the panel.
  // TyFadeIn / TySlideIn are thin aliases over TyPlayTransition.
  TyFadeIn(Self, DurationBar.Position);
end;
procedure TMainForm.BtnUpClick(Sender: TObject);    begin Replay(ttSlideUp);    end;
procedure TMainForm.BtnDownClick(Sender: TObject);  begin Replay(ttSlideDown);  end;
procedure TMainForm.BtnLeftClick(Sender: TObject);
begin
  // Same call as Replay(ttSlideLeft) -- TySlideIn is the named alias for it.
  TySlideIn(Target, ttSlideLeft, DurationBar.Position);
end;
procedure TMainForm.BtnRightClick(Sender: TObject); begin Replay(ttSlideRight); end;

procedure TMainForm.BtnNoneClick(Sender: TObject);
begin
  // ttNone is the documented no-op -- what an app stores when the user turns animation off.
  // TyPlayTransition returns without touching the control, so the caller does the plain show.
  Target.Visible := True;
  TyPlayTransition(Target, ttNone, DurationBar.Position);
end;

procedure TMainForm.BtnHideClick(Sender: TObject);
begin
  // Give the transition buttons something to reveal.
  Target.Visible := False;
end;

end.
