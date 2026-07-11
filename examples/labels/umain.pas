unit umain;

{ Label family demo: plain label / hyperlink label / shadow label / glow label.
  Main form is a TTyForm + TTyTitleBar; UI is built entirely in code (no .lfm). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Types, tyControls.Controller, tyControls.Form,
  tyControls.TyLabel, tyControls.LinkLabel, tyControls.ShadowLabel, tyControls.GlowLabel;

type
  TMainForm = class(TTyForm)
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

function ThemesDir: string;
var Dir: string; i: Integer;
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

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  Plain: TTyLabel;
  Link: TTyLinkLabel;
  Shadow: TTyShadowLabel;
  Glow: TTyGlowLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Labels 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 420, 300);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'Labels  · TyControls';

  Plain := TTyLabel.Create(Self);
  Plain.Parent := Self;
  Plain.SetBounds(24, 56, 360, 24);
  Plain.Caption := '普通标签 TTyLabel';

  Link := TTyLinkLabel.Create(Self);
  Link.Parent := Self;
  Link.SetBounds(24, 100, 360, 24);
  Link.Caption := '超链接标签 TTyLinkLabel(点击打开主页)';
  Link.URL := 'https://github.com/ACTom/TyControls';

  Shadow := TTyShadowLabel.Create(Self);
  Shadow.Parent := Self;
  Shadow.SetBounds(24, 144, 360, 30);
  Shadow.Caption := '投影标签 TTyShadowLabel';
  Shadow.ShadowColor := TyRGBA(0, 0, 0, 150);
  Shadow.ShadowOffsetX := 2;
  Shadow.ShadowOffsetY := 2;

  Glow := TTyGlowLabel.Create(Self);
  Glow.Parent := Self;
  Glow.SetBounds(24, 192, 360, 32);
  Glow.Caption := '发光标签 TTyGlowLabel';
  Glow.GlowColor := TyRGBA($3B, $82, $F6, 200);
  Glow.GlowRadius := 5;

  ApplyChromeTheme(TyDefaultController);
end;

end.
