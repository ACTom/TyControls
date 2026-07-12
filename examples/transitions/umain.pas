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
  tyControls.ComboBox;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    BtnFade:  TTyButton;
    BtnUp:    TTyButton;
    BtnDown:  TTyButton;
    BtnLeft:  TTyButton;
    BtnRight: TTyButton;
    Target:   TTyPanel;
    LblIn:    TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure BtnFadeClick(Sender: TObject);
    procedure BtnUpClick(Sender: TObject);
    procedure BtnDownClick(Sender: TObject);
    procedure BtnLeftClick(Sender: TObject);
    procedure BtnRightClick(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
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

{ Re-show the panel with the chosen transition. }
procedure TMainForm.Replay(AKind: TTyTransitionKind);
begin
  Target.Visible := True;
  TyPlayTransition(Target, AKind, 300);
end;

procedure TMainForm.BtnFadeClick(Sender: TObject);  begin Replay(ttFade);       end;
procedure TMainForm.BtnUpClick(Sender: TObject);    begin Replay(ttSlideUp);    end;
procedure TMainForm.BtnDownClick(Sender: TObject);  begin Replay(ttSlideDown);  end;
procedure TMainForm.BtnLeftClick(Sender: TObject);  begin Replay(ttSlideLeft);  end;
procedure TMainForm.BtnRightClick(Sender: TObject); begin Replay(ttSlideRight); end;

end.
