unit umain;

{ TTyStringGrid 示例:自绘数据网格。

  演示要点:
  - Header.Columns —— 列模型(标题 / 宽度 / 对齐);拖列头分隔条可改列宽
  - FixedCols —— 冻结左侧列:横向滚动时它们钉住不动
  - ShowIndicator —— 最左的行号槽
  - Cells[列,行] —— **稀疏**存储:只有写过的单元格才占内存
  - 二维光标:鼠标点选、方向键 / Home / End / PageUp / PageDown 导航
  - 一百万行:RowCount 拉到 1000000 也秒开,因为只绘制可视窗口内的几十行

  窗口、标题栏、网格与换肤下拉全部在 umain.lfm 里设计;本文件只放事件处理。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Columns, tyControls.Grid, tyControls.TyLabel, tyControls.ComboBox,
  tyControls.ToggleSwitch, tyControls.Button, tyControls.Edit, tyControls.Panel,
  tyControls.Types, tyControls.ColorMath, tyControls.Dialogs.Color;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    Grid: TTyStringGrid;
    LblStatus: TTyLabel;
    BtnMillion: TTyButton;
    EdFilter: TTyEdit;
    BtnCsv: TTyButton;
    BtnGroup: TTyButton;
    ToolBar: TTyPanel;
    LblFilter: TTyLabel;
    LblHint: TTyLabel;
    BtnAccent: TTyButton;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure BtnAccentClick(Sender: TObject);
    procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer; var ACanSelect: Boolean);
    procedure GridGetEditorKind(Sender: TObject; ACol, ARow: Integer;
      var AKind: TTyGridEditorKind);
    procedure GridCellEdited(Sender: TObject; ACol, ARow: Integer;
      const AOldText, ANewText: string; var AAccept: Boolean);
    procedure GridCompareCells(Sender: TObject; ACol, ARow1, ARow2: Integer;
      var AResult: Integer);
    procedure GridGetPickList(Sender: TObject; ACol, ARow: Integer; AItems: TStrings);
    procedure BtnMillionClick(Sender: TObject);
    procedure EdFilterChange(Sender: TObject);
    procedure BtnCsvClick(Sender: TObject);
    procedure BtnGroupClick(Sender: TObject);
    procedure GridGetCellDisplay(Sender: TObject; ACol, ARow: Integer;
      var ADisplay: TTyGridCellDisplay);
  private
    procedure BuildColumns;
    procedure FillSampleRows;
    procedure UpdateStatus;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

const
  cRegions: array[0..5] of string =
    ('华东', '华北', '华南', '西南', '东北', '西北');
  cProducts: array[0..4] of string =
    ('云主机', '对象存储', '数据库', 'CDN', '负载均衡');

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  { 内置主题是编译进来的,换肤下拉不需要去找 themes/ 目录。 }
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);

  BuildColumns;
  FillSampleRows;
  UpdateStatus;
end;

procedure TMainForm.BuildColumns;

  procedure AddCol(const ACaption: string; AWidth: Integer; AAlign: TAlignment);
  var c: TTyColumn;
  begin
    c := Grid.Header.Columns.Add as TTyColumn;
    c.Text := ACaption;
    c.Width := AWidth;
    c.Alignment := AAlign;
  end;

begin
  Grid.Header.Columns.BeginUpdate;
  try
    AddCol('订单号',  110, taLeftJustify);
    AddCol('大区',     70, taLeftJustify);
    AddCol('产品',    110, taLeftJustify);
    AddCol('数量',     70, taRightJustify);
    AddCol('金额',    100, taRightJustify);
    AddCol('负责人',   90, taLeftJustify);
    AddCol('已结算',   70, taCenter);
    AddCol('完成度',  120, taLeftJustify);
    AddCol('评分',     90, taLeftJustify);
  finally
    Grid.Header.Columns.EndUpdate;
  end;
  { 冻结头两列:横向滚动时"订单号 / 大区"钉住不动。 }
  Grid.FixedCols := 2;
  { 打开点列头排序(升序 → 降序 → 取消)。 }
  Grid.Header.Options := Grid.Header.Options + [hoHeaderClickAutoSort, hoShowSortGlyphs];
  { 底部汇总带:数量求和、金额求和、订单号计数。聚合只统计**筛选后可见**的行,
    所以在筛选框里打字,底部数字会跟着变。 }
  Grid.ShowFooter := True;
  Grid.SetColumnAggregate(0, gagCount);
  Grid.SetColumnAggregate(3, gagSum);
  Grid.SetColumnAggregate(4, gagSum);
end;

procedure TMainForm.FillSampleRows;
var
  r, qty: Integer;
begin
  Grid.RowCount := 200;
  for r := 0 to Grid.RowCount - 1 do
  begin
    qty := 1 + (r * 7) mod 40;
    Grid.Cells[0, r] := Format('SO-2026%04d', [r + 1]);
    Grid.Cells[1, r] := cRegions[r mod Length(cRegions)];
    Grid.Cells[2, r] := cProducts[r mod Length(cProducts)];
    Grid.Cells[3, r] := IntToStr(qty);
    Grid.Cells[4, r] := Format('%.2f', [qty * 128.5]);
    Grid.Cells[5, r] := Format('员工%02d', [1 + r mod 12]);
    if r mod 3 = 0 then Grid.Cells[6, r] := '1';    { 勾选列:三行勾一行 }
    Grid.Cells[7, r] := IntToStr((r * 13) mod 101);  { 完成度 0..100 → 进度条 }
    Grid.Cells[8, r] := IntToStr(1 + r mod 5);       { 评分 1..5 → 星标 }
  end;
end;

{ 一百万行:只是把 RowCount 拉大,不写任何单元格。
  存储是稀疏的、绘制只走可视窗口,所以既不吃内存也不卡。 }
procedure TMainForm.BtnMillionClick(Sender: TObject);
begin
  Grid.ClearCells;
  Grid.RowCount := 1000000;
  Grid.Row := 0;
  Grid.Col := 0;
  FillSampleRows;                 { 只填前 200 行,其余留空 }
  Grid.RowCount := 1000000;       { FillSampleRows 会把行数改回 200,这里再拉回去 }
  UpdateStatus;
end;

{ 导出 CSV 到程序目录。导出走**显示序** —— 过滤掉的行不会出现,
  排序后的次序被原样保留,所见即所得。 }
procedure TMainForm.BtnCsvClick(Sender: TObject);
var
  fn: string;
begin
  fn := ExtractFilePath(ParamStr(0)) + 'grid-export.csv';
  Grid.SaveToCSVFile(fn);
  LblStatus.Caption := Format('已导出 %d 行到 %s', [Grid.VisibleRowCount, fn]);
end;

{ 边打字边筛选「产品」列(包含匹配,不区分大小写)。
  过滤只影响显示序,底下的数据一格都不动。 }
procedure TMainForm.EdFilterChange(Sender: TObject);
begin
  Grid.SetColumnFilter(2, EdFilter.Text);
  LblStatus.Caption := Format('筛选“%s” —— 命中 %d 行 / 共 %d 行',
    [EdFilter.Text, Grid.VisibleRowCount, Grid.RowCount]);
end;

{ 逐列指定编辑器:数量/金额走数值编辑器,订单号只读,其余普通文本。 }
procedure TMainForm.GridGetEditorKind(Sender: TObject; ACol, ARow: Integer;
  var AKind: TTyGridEditorKind);
begin
  case ACol of
    0:    AKind := gekNone;       { 订单号不给改 }
    1:    AKind := gekPickList;   { 大区:从固定候选里选 }
    3, 4, 7, 8: AKind := gekNumeric;   { 数量 / 金额 / 完成度 / 评分 }
    6:    AKind := gekCheckBox;   { 已结算:点一下就切换 }
  else    AKind := gekText;
  end;
end;

{ 按「大区」分组 / 取消分组。分组行可点击折叠。 }
procedure TMainForm.BtnGroupClick(Sender: TObject);
begin
  if Grid.GroupColumn >= 0 then
  begin
    Grid.UngroupRows;
    BtnGroup.Caption := '按大区分组';
  end
  else
  begin
    Grid.GroupByColumn(1);
    BtnGroup.Caption := '取消分组';
  end;
  UpdateStatus;
end;

{ 「完成度」画进度条,「评分」画星标 —— 显示方式与编辑方式是正交的:
  这两列显示成图形,双击仍然按数值编辑。 }
procedure TMainForm.GridGetCellDisplay(Sender: TObject; ACol, ARow: Integer;
  var ADisplay: TTyGridCellDisplay);
begin
  case ACol of
    7: ADisplay := gcdProgress;
    8: ADisplay := gcdRating;
  else ADisplay := gcdText;
  end;
end;

{ 「大区」列的下拉候选。 }
procedure TMainForm.GridGetPickList(Sender: TObject; ACol, ARow: Integer;
  AItems: TStrings);
var i: Integer;
begin
  if ACol <> 1 then Exit;
  for i := 0 to High(cRegions) do AItems.Add(cRegions[i]);
end;

{ 编辑提交回调:可在这里做业务校验并否决。 }
procedure TMainForm.GridCellEdited(Sender: TObject; ACol, ARow: Integer;
  const AOldText, ANewText: string; var AAccept: Boolean);
begin
  AAccept := True;
  LblStatus.Caption := Format('已修改 (列 %d, 行 %d):%s → %s',
    [ACol, ARow, AOldText, ANewText]);
end;

{ 数量/金额两列按**数值**比较,否则会排出 '10' < '9' 这种结果。
  其余列返回 0 = 不接管,交给控件按文本比。 }
procedure TMainForm.GridCompareCells(Sender: TObject; ACol, ARow1, ARow2: Integer;
  var AResult: Integer);
var
  a, b: Double;
begin
  AResult := 0;
  if not (ACol in [3, 4]) then Exit;
  a := StrToFloatDef(Grid.Cells[ACol, ARow1], 0);
  b := StrToFloatDef(Grid.Cells[ACol, ARow2], 0);
  if a < b then AResult := -1
  else if a > b then AResult := 1;
end;

procedure TMainForm.GridSelectCell(Sender: TObject; ACol, ARow: Integer;
  var ACanSelect: Boolean);
begin
  ACanSelect := True;
  { 光标还没真正移动,所以状态栏用回调带来的目标坐标。 }
  LblStatus.Caption := Format('当前单元格:(列 %d, 行 %d)  内容:%s   —— 共 %d 行 / 已存 %d 格',
    [ACol, ARow, Grid.Cells[ACol, ARow], Grid.RowCount, Grid.StoredCellCount]);
end;

procedure TMainForm.UpdateStatus;
begin
  LblStatus.Caption := Format('当前单元格:(列 %d, 行 %d)  内容:%s   —— 共 %d 行 / 已存 %d 格',
    [Grid.Col, Grid.Row, Grid.Cells[Grid.Col, Grid.Row], Grid.RowCount,
     Grid.StoredCellCount]);
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);
end;

{ 主题色(强调色):覆盖 --accent,整套交互色(hover/active/焦点环/选中)跟着走,
  并且**跨主题、跨明暗都保持**。再点一次可以恢复主题自带的强调色。 }
procedure TMainForm.BtnAccentClick(Sender: TObject);
var
  c: TTyColor;
begin
  if TyDefaultController.AccentOverride <> '' then
  begin
    TyDefaultController.ResetAccent;
    ApplyChromeTheme(TyDefaultController);
    LblStatus.Caption := '已恢复主题自带的强调色';
    Exit;
  end;
  c := TyDefaultController.Model.ResolveStyle('TyButton', 'primary', []).Background.Color;
  if TySelectColor('选择主题色', c) then
  begin
    TyDefaultController.SetAccent(TyColorToHex(c, False));
    ApplyChromeTheme(TyDefaultController);
    LblStatus.Caption := '主题色已改为 ' + TyColorToHex(c, False) + '(再点一次恢复)';
  end;
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

end.
