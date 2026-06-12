unit umain;

{ TTyScrollBar 最小示例：
  - 一个垂直滚动条（Kind=sbVertical）
  - 一个水平滚动条（Kind=sbHorizontal）
  - 设置 Min / Max / PageSize / Position
  - OnChange 将 Position 实时显示到 TTyLabel
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.ScrollBar, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FVLabel: TTyLabel;   // 显示垂直滚动条当前值
    FHLabel: TTyLabel;   // 显示水平滚动条当前值
    procedure VScrollChanged(Sender: TObject);
    procedure HScrollChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ 从 exe 所在目录向上查找仓库的 themes/ 目录（兼容 lib/<cpu>-<os>/ 与 .app 包） }
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
  VScroll: TTyScrollBar;
  HScroll: TTyScrollBar;
  TitleLbl: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyScrollBar 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 380, 300);

  // 加载亮色主题；TyScrollBar 规则已在 light.tycss 中定义
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 标题标签
  TitleLbl := TTyLabel.Create(Self);
  TitleLbl.Parent := Self;
  TitleLbl.SetBounds(24, 16, 320, 20);
  TitleLbl.Caption := '拖动滚动条观察 Position 实时变化';

  // ── 垂直滚动条 ─────────────────────────────────────────────
  VScroll := TTyScrollBar.Create(Self);
  VScroll.Parent := Self;
  VScroll.Kind := sbVertical;
  VScroll.SetBounds(24, 50, 18, 180);
  VScroll.Min      := 0;
  VScroll.Max      := 100;
  VScroll.PageSize := 20;
  VScroll.Position := 0;
  VScroll.OnChange := @VScrollChanged;

  FVLabel := TTyLabel.Create(Self);
  FVLabel.Parent := Self;
  FVLabel.SetBounds(56, 50, 280, 20);
  FVLabel.Caption := '垂直 Position：0';

  // ── 水平滚动条 ─────────────────────────────────────────────
  HScroll := TTyScrollBar.Create(Self);
  HScroll.Parent := Self;
  HScroll.Kind := sbHorizontal;
  HScroll.SetBounds(24, 240, 280, 18);
  HScroll.Min      := 0;
  HScroll.Max      := 200;
  HScroll.PageSize := 40;
  HScroll.Position := 0;
  HScroll.OnChange := @HScrollChanged;

  FHLabel := TTyLabel.Create(Self);
  FHLabel.Parent := Self;
  FHLabel.SetBounds(316, 240, 52, 18);
  FHLabel.Caption := 'H：0';
end;

procedure TMainForm.VScrollChanged(Sender: TObject);
begin
  FVLabel.Caption := Format('垂直 Position：%d', [(Sender as TTyScrollBar).Position]);
end;

procedure TMainForm.HScrollChanged(Sender: TObject);
begin
  FHLabel.Caption := Format('H：%d', [(Sender as TTyScrollBar).Position]);
end;

end.
