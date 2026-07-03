unit umain;

{ TTySpinEdit 示例：
  演示该整数微调框的主要已发布属性与事件（源码为整数实现，不支持小数）：
    - Value / MinValue / MaxValue / Increment，OnChange 实时写入状态栏
    - 负值范围（-50..50，步进 5）
    - Alignment（右对齐）、MaxLength（限制输入位数）
    - ReadOnly（锁定：禁止编辑/步进/滚轮）
  交互方式：上/下小箭头按钮、键盘 ↑/↓、鼠标滚轮、直接键入后回车提交。
  纯代码创建 UI（无 .lfm）；主窗体为 TTyForm + TTyTitleBar，主题经全局
  TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.SpinEdit, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FSpinQty: TTySpinEdit;      // 0..100 步进 1
    FSpinOfs: TTySpinEdit;      // -50..50 步进 5（负值范围）
    FSpinYear: TTySpinEdit;     // 右对齐 + MaxLength
    FSpinLock: TTySpinEdit;     // ReadOnly 锁定
    FStatus: TTyLabel;          // OnChange 状态输出
    procedure SpinChange(Sender: TObject);
    procedure UpdateStatus(const ATag: string; ASpin: TTySpinEdit);
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
  Bar: TTyTitleBar;
  Lbl: TTyLabel;

  function AddLabel(ATop: Integer; const ACaption: string): TTyLabel;
  begin
    Result := TTyLabel.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(24, ATop, 380, 20);
    Result.Caption := ACaption;
  end;

begin
  inherited CreateNew(AOwner, 0);          // TTyForm：无边框 + 常驻绘制引擎
  Caption := 'TTySpinEdit 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 440, 420);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // 先加载主题

  Bar := TTyTitleBar.Create(Self);         // Owner=Self → 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'SpinEdit  · TyControls';

  // ① 数量：0..100，步进 1
  AddLabel(52, '数量（0..100，步进 1；箭头/方向键/滚轮/键入）：');
  FSpinQty := TTySpinEdit.Create(Self);
  FSpinQty.Parent := Self;
  FSpinQty.SetBounds(24, 76, 130, 28);
  FSpinQty.MinValue := 0;
  FSpinQty.MaxValue := 100;
  FSpinQty.Increment := 1;
  FSpinQty.Value := 10;
  FSpinQty.OnChange := @SpinChange;

  // ② 偏移：-50..50，步进 5（负值范围 + 自定义步进）
  AddLabel(120, '偏移（-50..50，步进 5，含负值范围）：');
  FSpinOfs := TTySpinEdit.Create(Self);
  FSpinOfs.Parent := Self;
  FSpinOfs.SetBounds(24, 144, 130, 28);
  FSpinOfs.MinValue := -50;
  FSpinOfs.MaxValue := 50;
  FSpinOfs.Increment := 5;
  FSpinOfs.Value := 0;
  FSpinOfs.OnChange := @SpinChange;

  // ③ 年份：右对齐 + MaxLength=4（限制输入位数）
  AddLabel(188, '年份（右对齐 Alignment，MaxLength=4）：');
  FSpinYear := TTySpinEdit.Create(Self);
  FSpinYear.Parent := Self;
  FSpinYear.SetBounds(24, 212, 130, 28);
  FSpinYear.MinValue := 1900;
  FSpinYear.MaxValue := 2100;
  FSpinYear.Alignment := taRightJustify;
  FSpinYear.MaxLength := 4;
  FSpinYear.Value := 2026;
  FSpinYear.OnChange := @SpinChange;

  // ④ 锁定：ReadOnly=True（禁止编辑/步进/滚轮）
  AddLabel(256, '锁定（ReadOnly=True：不可编辑/步进/滚轮）：');
  FSpinLock := TTySpinEdit.Create(Self);
  FSpinLock.Parent := Self;
  FSpinLock.SetBounds(24, 280, 130, 28);
  FSpinLock.MinValue := 0;
  FSpinLock.MaxValue := 999;
  FSpinLock.Value := 42;
  FSpinLock.ReadOnly := True;
  FSpinLock.OnChange := @SpinChange;

  // 状态栏：任一 SpinEdit 的 OnChange 都在此输出
  Lbl := AddLabel(332, '状态：');
  Lbl.SetBounds(24, 332, 60, 20);
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(84, 332, 336, 20);
  FStatus.Caption := '（改变任一数值以查看 OnChange 输出）';

  ApplyChromeTheme(TyDefaultController);   // 最后统一为整套窗体外观 + 背景上色
end;

procedure TMainForm.UpdateStatus(const ATag: string; ASpin: TTySpinEdit);
begin
  FStatus.Caption := Format('%s → %d', [ATag, ASpin.Value]);
end;

procedure TMainForm.SpinChange(Sender: TObject);
begin
  if Sender = FSpinQty then
    UpdateStatus('数量', FSpinQty)
  else if Sender = FSpinOfs then
    UpdateStatus('偏移', FSpinOfs)
  else if Sender = FSpinYear then
    UpdateStatus('年份', FSpinYear)
  else if Sender = FSpinLock then
    UpdateStatus('锁定', FSpinLock);
end;

end.
