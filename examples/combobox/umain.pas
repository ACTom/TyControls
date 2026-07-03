unit umain;

{ TTyComboBox 示例（纯代码，无 .lfm）：
    左列 csDropDownList（只读，仅能从列表挑选）——展示 Sorted 排序、
      DropDownCount 限制可见行数、以及键盘 type-ahead 前缀跳转。
    右列 csDropDown（可编辑字段 + 前缀自动完成）——键入前缀时弹出过滤后的
      候选列表；同时演示 CharCase（自动转大写）与 MaxLength（限制长度）。
    下方 TTyLabel 状态栏订阅四个事件：
      OnChange / OnSelect / OnDropDown / OnCloseUp。
  窗体继承 TTyForm（无边框自绘窗框）+ 一条 TTyTitleBar；主题经全局
  TyDefaultController 加载后由 ApplyChromeTheme 统一上色。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls,
  tyControls.Controller, tyControls.Form,
  tyControls.ComboBox, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FListCombo: TTyComboBox;   // csDropDownList（只读）
    FEditCombo: TTyComboBox;   // csDropDown（可编辑 + 自动完成）
    FStatus: TTyLabel;         // 事件状态栏
    procedure ComboChange(Sender: TObject);
    procedure ComboSelect(Sender: TObject);
    procedure ComboDropDown(Sender: TObject);
    procedure ComboCloseUp(Sender: TObject);
    procedure SetStatus(const AEvt: string; ACombo: TTyComboBox);
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
  LblList, LblEdit: TTyLabel;
begin
  // TTyForm.CreateNew → 无边框 + 持久引擎，但默认无标题栏
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyComboBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 520, 320);

  // 主题须先加载，再给整套窗框上色
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 标题栏：Owner=Self 即自动关联到本窗体的 TitleBar 属性
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyComboBox  · TyControls';

  // ── 左列：csDropDownList（只读下拉） ──
  LblList := TTyLabel.Create(Self);
  LblList.Parent := Self;
  LblList.SetBounds(24, 52, 224, 20);
  LblList.Caption := '只读下拉（Sorted 排序，可键盘 type-ahead）：';

  FListCombo := TTyComboBox.Create(Self);
  FListCombo.Parent := Self;
  FListCombo.SetBounds(24, 76, 224, 26);
  FListCombo.Style := csDropDownList;   // 只能从列表中挑选
  FListCombo.Sorted := True;            // 保持升序，插入项自动归位
  FListCombo.DropDownCount := 5;        // 最多显示 5 行，超出则滚动
  // 乱序加入 8 项：Sorted=True 会自动排成升序
  FListCombo.Items.Add('Guangzhou');
  FListCombo.Items.Add('Beijing');
  FListCombo.Items.Add('Shanghai');
  FListCombo.Items.Add('Chengdu');
  FListCombo.Items.Add('Hangzhou');
  FListCombo.Items.Add('Nanjing');
  FListCombo.Items.Add('Wuhan');
  FListCombo.Items.Add('Xian');
  FListCombo.ItemIndex := 0;            // 预选首项（排序后为 Beijing）
  FListCombo.OnChange   := @ComboChange;
  FListCombo.OnSelect   := @ComboSelect;
  FListCombo.OnDropDown := @ComboDropDown;
  FListCombo.OnCloseUp  := @ComboCloseUp;

  // ── 右列：csDropDown（可编辑 + 前缀自动完成） ──
  LblEdit := TTyLabel.Create(Self);
  LblEdit.Parent := Self;
  LblEdit.SetBounds(272, 52, 224, 20);
  LblEdit.Caption := '可编辑（前缀自动完成 / 大写 / 限长 10）：';

  FEditCombo := TTyComboBox.Create(Self);
  FEditCombo.Parent := Self;
  FEditCombo.SetBounds(272, 76, 224, 26);
  FEditCombo.Style := csDropDown;       // 可编辑字段 + 前缀自动完成弹窗
  FEditCombo.CharCase := ecUppercase;   // 键入文本自动转大写
  FEditCombo.MaxLength := 10;           // 限制字段长度为 10
  FEditCombo.DropDownCount := 6;
  FEditCombo.Items.Add('APPLE');
  FEditCombo.Items.Add('APRICOT');
  FEditCombo.Items.Add('AVOCADO');
  FEditCombo.Items.Add('BANANA');
  FEditCombo.Items.Add('BLUEBERRY');
  FEditCombo.Items.Add('CHERRY');
  FEditCombo.Items.Add('GRAPE');
  FEditCombo.Items.Add('MANGO');
  FEditCombo.OnChange   := @ComboChange;
  FEditCombo.OnSelect   := @ComboSelect;
  FEditCombo.OnDropDown := @ComboDropDown;
  FEditCombo.OnCloseUp  := @ComboCloseUp;

  // ── 事件状态栏 ──
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 140, 472, 22);
  FStatus.Caption := '事件状态：（等待操作，尝试展开或键入前缀）';

  // 整套窗框 + 背景色随主题
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.SetStatus(const AEvt: string; ACombo: TTyComboBox);
var
  Which: string;
begin
  if ACombo = FListCombo then
    Which := '只读'
  else
    Which := '可编辑';
  FStatus.Caption := Format('事件状态：[%s] %s → Text="%s" (ItemIndex=%d)',
    [Which, AEvt, ACombo.Text, ACombo.ItemIndex]);
end;

procedure TMainForm.ComboChange(Sender: TObject);
begin
  SetStatus('OnChange', Sender as TTyComboBox);
end;

procedure TMainForm.ComboSelect(Sender: TObject);
begin
  SetStatus('OnSelect', Sender as TTyComboBox);
end;

procedure TMainForm.ComboDropDown(Sender: TObject);
begin
  SetStatus('OnDropDown（展开）', Sender as TTyComboBox);
end;

procedure TMainForm.ComboCloseUp(Sender: TObject);
begin
  SetStatus('OnCloseUp（收起）', Sender as TTyComboBox);
end;

end.
