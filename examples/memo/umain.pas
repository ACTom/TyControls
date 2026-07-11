unit umain;

{ TTyMemo demo (borderless self-drawn TTyForm chrome + TTyTitleBar):
  - Lines: multi-line text model (Enter for new line, Backspace/Delete merge across lines, arrow/Home/End navigation)
  - ScrollBars: defaults to ssAutoVertical; a vertical scrollbar appears on the right when content overflows; mouse wheel supported
  - ReadOnly: when checked, all user edits are ignored (navigation/selection/copy still work)
  - WordWrap: when checked, long logical lines soft-wrap at word boundaries into multiple visual lines
  - OnChange: fires whenever the text model changes; updates the line/character count labels live
  UI is created purely in code (no .lfm); the theme is loaded via the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls,
  tyControls.Controller, tyControls.Form,
  tyControls.Memo, tyControls.TyLabel, tyControls.CheckBox;

type
  TMainForm = class(TTyForm)
  private
    FMemo: TTyMemo;
    FInfo: TTyLabel;
    FReadOnlyChk: TTyCheckBox;
    FWordWrapChk: TTyCheckBox;
    procedure MemoChange(Sender: TObject);
    procedure ReadOnlyClick(Sender: TObject);
    procedure WordWrapClick(Sender: TObject);
    procedure UpdateInfo;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to locate the repo's themes/ directory (handles lib/<cpu>-<os>/ and .app bundles) }
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
  Lbl: TTyLabel;
begin
  // TTyForm.CreateNew -> borderless + persistence engine, but no title bar by default
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyMemo 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 480, 420);

  // Load the theme first; controls without an explicit Controller fall back to the global TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // Title bar: Owner=Self auto-associates it with this form's TitleBar property
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyMemo  · TyControls';

  // ── Client-area content (below the title bar) ──
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(16, 46, 448, 20);
  Lbl.Caption := '多行文本编辑器（回车换行、方向键导航、滚轮滚动）：';

  // Editable multi-line TTyMemo
  FMemo := TTyMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.SetBounds(16, 72, 448, 240);
  // ssAutoVertical is the default: a vertical scrollbar appears on the right when content overflows
  FMemo.ScrollBars := ssAutoVertical;
  FMemo.WordWrap := False;   // no soft-wrap initially, so long lines can scroll horizontally
  // Seed a few lines to demonstrate the vertical scrollbar
  FMemo.Lines.Text :=
    '第一行：欢迎使用 TyControls TTyMemo 多行编辑控件。' + LineEnding +
    '第二行：按回车换行，退格/删除可跨行合并。' + LineEnding +
    '第三行：方向键、Home/End 用于光标导航，支持选择与复制粘贴。' + LineEnding +
    '第四行：内容超出可见区域时右侧出现垂直滚动条。' + LineEnding +
    '第五行：也可以用鼠标滚轮上下滚动。' + LineEnding +
    '第六行：勾选下方“自动换行”后，超长的一行会按词边界折行为多个视觉行——这是一条足够长用于演示软换行效果的文字。' + LineEnding +
    '第七行：勾选“只读”后将无法编辑，但仍可导航与复制。' + LineEnding +
    '第八行：最后一行。';
  FMemo.OnChange := @MemoChange;

  // Read-only toggle
  FReadOnlyChk := TTyCheckBox.Create(Self);
  FReadOnlyChk.Parent := Self;
  FReadOnlyChk.SetBounds(16, 322, 120, 24);
  FReadOnlyChk.Caption := '只读 (ReadOnly)';
  FReadOnlyChk.OnClick := @ReadOnlyClick;

  // Word-wrap toggle
  FWordWrapChk := TTyCheckBox.Create(Self);
  FWordWrapChk.Parent := Self;
  FWordWrapChk.SetBounds(150, 322, 140, 24);
  FWordWrapChk.Caption := '自动换行 (WordWrap)';
  FWordWrapChk.OnClick := @WordWrapClick;

  // Status label (line count / character count)
  FInfo := TTyLabel.Create(Self);
  FInfo.Parent := Self;
  FInfo.SetBounds(16, 356, 448, 20);
  UpdateInfo;

  // Apply the theme to the whole window frame + background color
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.UpdateInfo;
begin
  FInfo.Caption := Format('行数：%d    字符数：%d',
    [FMemo.Lines.Count, Length(FMemo.Text)]);
end;

procedure TMainForm.MemoChange(Sender: TObject);
begin
  // OnChange: refresh the stats whenever the text model changes
  UpdateInfo;
end;

procedure TMainForm.ReadOnlyClick(Sender: TObject);
begin
  FMemo.ReadOnly := FReadOnlyChk.Checked;
end;

procedure TMainForm.WordWrapClick(Sender: TObject);
begin
  FMemo.WordWrap := FWordWrapChk.Checked;
end;

end.
