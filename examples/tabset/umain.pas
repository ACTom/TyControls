unit umain;

{ TTyTabSet 示例：纯页签条控件（无页面容器），选择态 = TabIndex + OnChange。
  - Tabs：TStrings 字符串列表，逐条添加页签标题
  - TabIndex：当前选中页签；初始置为 0（第一个）
  - OnChange：切换后触发，底部状态标签实时显示当前页签
  - OnChanging：切换前否决钩子，演示禁止跳转到"锁定"页签
  - TabsClosable + OnTabClose：页签头显示关闭 × 字形，可 AllowClose:=False 否决
  - OnReorder：拖拽重排页签提交后触发，状态标签汇报 从→到
  - TabHeight：页签条高度
  纯代码创建 UI（无 .lfm），主体为 TTyForm + TTyTitleBar，
  主题经全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.TabSet, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FTabSet: TTyTabSet;
    FStatus: TTyLabel;
    procedure TabChanged(Sender: TObject);
    procedure TabChanging(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean);
    procedure TabClosing(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
    procedure TabReordered(Sender: TObject; AFromIndex, AToIndex: Integer);
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
  Result := 'themes' + PathDelim; { 兜底：相对当前目录 }
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
begin
  inherited CreateNew(AOwner, 0);          { TTyForm：无边框 + 常驻引擎 }
  Caption  := 'TTyTabSet 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 520, 220);

  { 先加载亮色主题；未显式指定 Controller 的控件自动使用全局 TyDefaultController }
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);         { Owner=Self -> 自动关联为 TTyForm.TitleBar }
  Bar.Parent  := Self;
  Bar.Align   := alTop;
  Bar.Height  := 34;
  Bar.Caption := 'TTyTabSet  · TyControls';

  { ── 页签条 ─────────────────────────────────────────────────────────────── }
  FTabSet := TTyTabSet.Create(Self);
  FTabSet.Parent := Self;
  FTabSet.SetBounds(20, 56, 480, 34);
  FTabSet.TabHeight := 32;

  { Tabs：字符串列表逐条添加；"通知(锁定)"演示 OnChanging 否决 }
  FTabSet.Tabs.Add('概览');
  FTabSet.Tabs.Add('详情');
  FTabSet.Tabs.Add('通知(锁定)');
  FTabSet.Tabs.Add('设置');
  FTabSet.Tabs.Add('关于');

  FTabSet.TabIndex := 0;                    { 初始选中第一个页签 }

  { 可关闭页签：页签头右侧出现关闭 × 字形，点击触发 OnTabClose }
  FTabSet.TabsClosable := True;

  FTabSet.OnChange   := @TabChanged;
  FTabSet.OnChanging := @TabChanging;
  FTabSet.OnTabClose := @TabClosing;
  FTabSet.OnReorder  := @TabReordered;      { 拖拽重排页签后触发 }

  { ── 状态标签 ───────────────────────────────────────────────────────────── }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent  := Self;
  FStatus.SetBounds(20, 110, 480, 66);
  FStatus.WordWrap := True;
  FStatus.Caption :=
    '当前页签：概览' + LineEnding +
    '提示：点击切换 · 拖拽可重排 · 点 × 关闭 · "通知(锁定)"页禁止选中';

  ApplyChromeTheme(TyDefaultController);    { 最后统一主题化窗体外壳与背景 }
end;

{ 页签切换回调：更新状态标签显示当前页签标题 }
procedure TMainForm.TabChanged(Sender: TObject);
begin
  FStatus.Caption := Format('当前页签：%s（TabIndex=%d）',
    [FTabSet.TabCaption(FTabSet.TabIndex), FTabSet.TabIndex]);
end;

{ 切换前否决钩子：ANewIndex 为拟切换到的目标索引；清空 AllowChange 可中止切换。
  此处禁止选中第 3 个页签"通知(锁定)"以演示否决。 }
procedure TMainForm.TabChanging(Sender: TObject; ANewIndex: Integer;
  var AllowChange: Boolean);
begin
  if ANewIndex = 2 then
  begin
    AllowChange := False;
    FStatus.Caption := '"通知(锁定)"页已被 OnChanging 否决，无法选中。';
  end;
end;

{ 页签关闭回调：点击页签头的关闭 × 字形时触发。默认放行（AllowClose 进入时为 True），
  控件随后自动从 Tabs 移除该页签并修正 TabIndex。此处否决关闭第一个页签"概览"。 }
procedure TMainForm.TabClosing(Sender: TObject; AIndex: Integer;
  var AllowClose: Boolean);
begin
  if AIndex = 0 then
  begin
    AllowClose := False;
    FStatus.Caption := '"概览"页被 OnTabClose 否决，不予关闭。';
  end
  else
    FStatus.Caption := Format('正在关闭页签：%s', [FTabSet.TabCaption(AIndex)]);
end;

{ 拖拽重排提交回调：一次干净的拖拽手势完成后触发一次 }
procedure TMainForm.TabReordered(Sender: TObject; AFromIndex, AToIndex: Integer);
begin
  FStatus.Caption := Format('页签已重排：%d → %d（当前：%s）',
    [AFromIndex, AToIndex, FTabSet.TabCaption(FTabSet.TabIndex)]);
end;

end.
