unit umain;

{ TTyEdit demo (TTyForm custom-drawn window frame + TTyTitleBar):
    Showcases TTyEdit's core published properties, one mode per input box:
      - TextHint      placeholder hint (shown dimmed when the text is empty)
      - PasswordChar  password mask character
      - CharCase      case forcing (ecUppercase)
      - MaxLength     maximum character-count limit
      - NumbersOnly   digits only
      - ReadOnly      read-only
      - Alignment     text alignment (taRightJustify)
    The first input box hooks OnChange to echo its content live into the
    bottom status-bar TTyLabel.
  UI is built purely in code (no .lfm); the theme is loaded via the global
  TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls,
  tyControls.Controller, tyControls.Form,
  tyControls.TyLabel, tyControls.Edit;

type
  TMainForm = class(TTyForm)
  private
    FStatus: TTyLabel;
    procedure EditChanged(Sender: TObject);   // OnChange -> status bar
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to find the repo's themes/ folder (handles
  lib/<cpu>-<os>/ and .app bundles) }
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

  { Helper: create a description label on the left + an input box on the right,
    returning the input box for further tweaking }
  function AddRow(const ACaption: string; ATop: Integer): TTyEdit;
  var
    Lbl: TTyLabel;
  begin
    Lbl := TTyLabel.Create(Self);
    Lbl.Parent := Self;
    Lbl.SetBounds(24, ATop + 5, 130, 22);
    Lbl.Caption := ACaption;

    Result := TTyEdit.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(160, ATop, 260, 30);
  end;

var
  Bar: TTyTitleBar;
  Ed: TTyEdit;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistent engine
  Caption := 'TTyEdit 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 460, 400);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load the theme first

  Bar := TTyTitleBar.Create(Self);         // Owner=Self auto-associates as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyEdit  · TyControls';

  // 1) TextHint: empty-text placeholder hint + OnChange wired to the status bar
  Ed := AddRow('占位提示 + OnChange', 52);
  Ed.TextHint := '在此输入，下方实时回显…';
  Ed.OnChange := @EditChanged;             // echo on every keystroke

  // 2) PasswordChar: password mask
  Ed := AddRow('密码遮罩', 92);
  Ed.PasswordChar := '●';                  // shown as bullets
  Ed.Text := 'secret';

  // 3) CharCase: force uppercase
  Ed := AddRow('强制大写', 132);
  Ed.CharCase := ecUppercase;              // input auto-uppercased
  Ed.TextHint := '输入将转为大写';

  // 4) MaxLength: at most 8 characters
  Ed := AddRow('最大长度 8', 172);
  Ed.MaxLength := 8;
  Ed.TextHint := '最多 8 字';

  // 5) NumbersOnly: digits only
  Ed := AddRow('仅数字', 212);
  Ed.NumbersOnly := True;                  // non-digit characters are rejected
  Ed.TextHint := '只能输入 0-9';

  // 6) ReadOnly: read-only
  Ed := AddRow('只读', 252);
  Ed.ReadOnly := True;
  Ed.Text := '只读内容，无法编辑';

  // 7) Alignment: right-justified
  Ed := AddRow('右对齐', 292);
  Ed.Alignment := taRightJustify;
  Ed.Text := '1234.56';

  // bottom status bar
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 348, 412, 24);
  FStatus.Caption := '（第一个输入框内容将在此显示）';

  ApplyChromeTheme(TyDefaultController);   // finally, color the whole frame + background
end;

procedure TMainForm.EditChanged(Sender: TObject);
begin
  // read TTyEdit.Text live
  FStatus.Caption := '当前输入：' + (Sender as TTyEdit).Text;
end;

end.
