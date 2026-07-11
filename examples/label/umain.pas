unit umain;

{ TTyLabel demo (TTyForm + TTyTitleBar):
  Showcases the core published features of TTyLabel --
    - Alignment: taLeftJustify / taCenter / taRightJustify horizontal alignment
    - Layout: tlTop / tlCenter / tlBottom vertical alignment (within a fixed height)
    - WordWrap: long text auto-wraps at spaces to fit the control width
    - AutoSize: on = shrink/grow to fit the text; off = fixed bounds
    - Transparent: True = transparent background; False = filled with the theme panel color
    - FocusControl + & mnemonic: Alt+letter sends focus to the associated TTyEdit
  UI is built purely in code (no .lfm); the theme is loaded via the global TyDefaultController.
  Note: font size/weight and StyleClass.primary are driven by the theme (light.tycss); TyLabel
  has no rule for them, so this demo does not exercise those inapplicable properties. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics,
  tyControls.Controller, tyControls.Form,
  tyControls.TyLabel, tyControls.Edit;

type
  TMainForm = class(TTyForm)
  private
    { fields + event handlers }
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Search upward from the exe's directory for the repo's themes/ dir (handles lib/<cpu>-<os>/ and .app bundles) }
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
  LHead, L: TTyLabel;
  LFocus: TTyLabel;
  Ed: TTyEdit;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + resident engine
  Caption := 'TTyLabel 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 480, 440);
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load the theme first

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyLabel  · TyControls';

  // ===== Section header (font size/weight decided by the theme; no ineffective Font override here) =====
  LHead := TTyLabel.Create(Self);
  LHead.Parent := Self;
  LHead.SetBounds(20, 46, 440, 26);
  LHead.Caption := '标签特性一览';

  // ===== Alignment: three horizontal alignments (AutoSize=False so the effect is visible) =====
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 82, 440, 22);
  L.AutoSize := False;
  L.Alignment := taLeftJustify;
  L.Caption := '左对齐（taLeftJustify）';

  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 108, 440, 22);
  L.AutoSize := False;
  L.Alignment := taCenter;
  L.Caption := '居中对齐（taCenter）';

  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 134, 440, 22);
  L.AutoSize := False;
  L.Alignment := taRightJustify;
  L.Caption := '右对齐（taRightJustify）';

  // ===== Transparent=False: fill the background with the theme panel color (unlike the other transparent labels) =====
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 166, 440, 22);
  L.AutoSize := False;
  L.Transparent := False;
  L.Alignment := taCenter;
  L.Caption := 'Transparent=False：带填充背景';

  // ===== AutoSize=True: bounds tighten around the text (default) =====
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 194, 10, 10);           // size will be overridden by AutoSize
  L.AutoSize := True;
  L.Caption := 'AutoSize=True：宽高随文字自适应';

  // ===== WordWrap: long text auto-wraps at spaces to fit the control width =====
  //  Wrapping only happens at ASCII spaces, so this uses space-separated words to make the effect genuinely visible.
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 224, 440, 60);
  L.AutoSize := False;
  L.WordWrap := True;
  L.Alignment := taLeftJustify;
  L.Caption := 'WordWrap=True : this label wraps onto several lines because '
             + 'the words are separated by spaces — 中文 与 English 混排 也 '
             + '能 在 空格 处 换行，超出 控件 宽度 就 自动 折行。';

  // ===== FocusControl + & mnemonic: Alt+N focuses the input box below =====
  Ed := TTyEdit.Create(Self);
  Ed.Parent := Self;
  Ed.SetBounds(180, 300, 240, 28);
  Ed.Text := '';

  LFocus := TTyLabel.Create(Self);
  LFocus.Parent := Self;
  LFocus.SetBounds(20, 304, 150, 22);
  LFocus.Caption := '姓名(&N)：';        // & builds a mnemonic: pressing Alt+N triggers it
  LFocus.FocusControl := Ed;             // clicking the label / Alt+N -> Ed gets focus

  ApplyChromeTheme(TyDefaultController);   // finally color the whole window chrome + background in one pass
end;

end.
