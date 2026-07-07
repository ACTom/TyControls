unit umain;

{ Phase-4 富输入 & 选择器示例。随各控件建成逐步扩充;当前展示 TTyNumericEdit
  (数值编辑:输入过滤 + 失焦分组格式化 + 限幅)。纯代码创建,主题走全局 TyDefaultController。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, BGRABitmap,
  tyControls.Controller, tyControls.Form, tyControls.IconFont,
  tyControls.ImageCollection, tyControls.ColorMath,
  tyControls.NumericEdit, tyControls.CurrencyEdit, tyControls.MaskEdit,
  tyControls.URLEdit, tyControls.ComboEdit, tyControls.TrackEdit,
  tyControls.ColorBox, tyControls.ColorListBox, tyControls.FontComboBox,
  tyControls.FontListBox, tyControls.FontSizeComboBox, tyControls.CheckListBox,
  tyControls.ColorComboBox, tyControls.MRUComboBox, tyControls.ComboBoxEx,
  tyControls.OfficeListBox, tyControls.OfficeComboBox, tyControls.ColorGrid,
  tyControls.LColorPicker, tyControls.HSColorPicker, tyControls.CheckComboBox,
  tyControls.AdvancedListBox, tyControls.AdvancedComboBox, tyControls.ValueListEditor,
  tyControls.CalcEdit, tyControls.CalcCurrencyEdit, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FQty, FPrice, FRanged: TTyNumericEdit;
    FMoney: TTyCurrencyEdit;
    FDate: TTyMaskEdit;
    FUrl: TTyURLEdit;
    FCombo: TTyComboEdit;
    FTrack: TTyTrackEdit;
    FColor: TTyColorBox;
    FColorList: TTyColorListBox;
    FFont: TTyFontComboBox;
    FFontList: TTyFontListBox;
    FSize: TTyFontSizeComboBox;
    FCheckList: TTyCheckListBox;
    FColorCombo: TTyColorComboBox;
    FMRU: TTyMRUComboBox;
    FComboEx: TTyComboBoxEx;
    FOfficeCombo: TTyOfficeComboBox;
    FOfficeList: TTyOfficeListBox;
    FColorGrid: TTyColorGrid;
    FLColor: TTyLColorPicker;
    FCheckCombo: TTyCheckComboBox;
    FHS: TTyHSColorPicker;
    FAdvList: TTyAdvancedListBox;
    FAdvCombo: TTyAdvancedComboBox;
    FVLE: TTyValueListEditor;
    FCalcEdit: TTyCalcEdit;
    FCalcCurr: TTyCalcCurrencyEdit;
    FEcho: TTyLabel;
    procedure RangedChange(Sender: TObject);
    procedure ComboDrop(Sender: TObject);
    procedure LumChange(Sender: TObject);
    procedure VleChange(Sender: TObject; ARow: TTyValueRow);
    procedure VleEditDialog(Sender: TObject; ARow: TTyValueRow);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ 从 exe 所在目录向上查找仓库的 themes/ 目录 }
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
  L1, L2, L3, L4, L5, L6, L7, L8, L9, L10, L11, L12, L13, L14: TTyLabel;
  L15, L16, L17, L18, L19, L20, L21, L22, L23, L24, L25, L26, LHint: TTyLabel;
  Icf: TTyIconFont;
  Coll: TTyImageCollection;
  Imgs: TTyVirtualImageList;
  VR: TTyValueRow;

  { Rasterise one system-symbol glyph into the collection + register it in the image list.
    (No .ttf shipped, so this uses a Unicode symbol via the system font — same placeholder
    convention as the buttons example; on a real machine point IconFont at an icon .ttf.) }
  procedure AddGlyph(const AName: string; ACodepoint: Cardinal; AColor: TColor);
  var B: TBGRABitmap;
  begin
    Icf.MapGlyph(AName, ACodepoint);
    B := Icf.RenderGlyph(AName, 32, TyColorFromLCL(AColor, 255));
    try
      Coll.AddBitmap(AName, B);   // takes a copy — free ours
    finally
      B.Free;
    end;
    Imgs.Names.Add(AName);
  end;

begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Rich Inputs 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 1300, 800);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'Rich Inputs  · TyControls';

  // 整数(无小数、带千分位)
  L1 := TTyLabel.Create(Self);
  L1.Parent := Self;
  L1.SetBounds(24, 56, 200, 20);
  L1.Caption := '数量(整数,Decimals=0):';
  FQty := TTyNumericEdit.Create(Self);
  FQty.Parent := Self;
  FQty.SetBounds(240, 52, 180, 28);
  FQty.Decimals := 0;
  FQty.Value := 1250;

  // 金额(2 位小数 + 千分位)
  L2 := TTyLabel.Create(Self);
  L2.Parent := Self;
  L2.SetBounds(24, 100, 200, 20);
  L2.Caption := '金额(2 位小数 + 千分位):';
  FPrice := TTyNumericEdit.Create(Self);
  FPrice.Parent := Self;
  FPrice.SetBounds(240, 96, 180, 28);
  FPrice.Value := 1234567.5;

  // 限幅 0..100
  L3 := TTyLabel.Create(Self);
  L3.Parent := Self;
  L3.SetBounds(24, 144, 200, 20);
  L3.Caption := '限幅(MinValue=0 / MaxValue=100):';
  FRanged := TTyNumericEdit.Create(Self);
  FRanged.Parent := Self;
  FRanged.SetBounds(240, 140, 180, 28);
  FRanged.MinValue := 0;
  FRanged.MaxValue := 100;
  FRanged.Value := 42;
  FRanged.OnChange := @RangedChange;

  // 货币(CurrencyEdit:仅失焦显示态加符号)
  L4 := TTyLabel.Create(Self);
  L4.Parent := Self;
  L4.SetBounds(24, 188, 200, 20);
  L4.Caption := '货币(TTyCurrencyEdit,¥):';
  FMoney := TTyCurrencyEdit.Create(Self);
  FMoney.Parent := Self;
  FMoney.SetBounds(240, 184, 180, 28);
  FMoney.CurrencySymbol := '¥';
  FMoney.Value := 1234.5;

  // 掩码(MaskEdit:日期,追加式录入 + 自动补 /)
  L5 := TTyLabel.Create(Self);
  L5.Parent := Self;
  L5.SetBounds(24, 232, 200, 20);
  L5.Caption := '日期掩码(##/##/####):';
  FDate := TTyMaskEdit.Create(Self);
  FDate.Parent := Self;
  FDate.SetBounds(240, 228, 180, 28);
  FDate.Mask := '##/##/####';

  // URL(URLEdit:尾部 → 按钮用默认浏览器打开)
  L6 := TTyLabel.Create(Self);
  L6.Parent := Self;
  L6.SetBounds(24, 276, 200, 20);
  L6.Caption := 'URL(TTyURLEdit,点 →):';
  FUrl := TTyURLEdit.Create(Self);
  FUrl.Parent := Self;
  FUrl.SetBounds(240, 272, 180, 28);
  FUrl.Text := 'https://github.com/ACTom/TyControls';

  // 下拉(ComboEdit:点按钮触发 OnDropDown,弹什么由你决定)
  L7 := TTyLabel.Create(Self);
  L7.Parent := Self;
  L7.SetBounds(24, 320, 200, 20);
  L7.Caption := '下拉(TTyComboEdit):';
  FCombo := TTyComboEdit.Create(Self);
  FCombo.Parent := Self;
  FCombo.SetBounds(240, 316, 180, 28);
  FCombo.OnDropDown := @ComboDrop;

  // 数值 + 内嵌滑块(TrackEdit:拖滑块或直接键入)
  L8 := TTyLabel.Create(Self);
  L8.Parent := Self;
  L8.SetBounds(24, 364, 200, 20);
  L8.Caption := '滑块数值(TTyTrackEdit,0..255):';
  FTrack := TTyTrackEdit.Create(Self);
  FTrack.Parent := Self;
  FTrack.SetBounds(240, 360, 180, 28);
  FTrack.MinValue := 0;
  FTrack.MaxValue := 255;
  FTrack.Value := 128;

  // 颜色组合框(ColorBox:字段/下拉每项都带色块)
  L9 := TTyLabel.Create(Self);
  L9.Parent := Self;
  L9.SetBounds(24, 408, 200, 20);
  L9.Caption := '颜色(TTyColorBox):';
  FColor := TTyColorBox.Create(Self);
  FColor.Parent := Self;
  FColor.SetBounds(240, 404, 180, 28);

  // 字体组合框(FontComboBox:每项用自己的字体画)
  L10 := TTyLabel.Create(Self);
  L10.Parent := Self;
  L10.SetBounds(24, 452, 200, 20);
  L10.Caption := '字体(TTyFontComboBox):';
  FFont := TTyFontComboBox.Create(Self);
  FFont.Parent := Self;
  FFont.SetBounds(240, 448, 128, 28);

  // 字号(FontSizeComboBox:可编辑,预设 + 手输),紧挨字体框
  FSize := TTyFontSizeComboBox.Create(Self);
  FSize.Parent := Self;
  FSize.SetBounds(372, 448, 48, 28);
  FSize.FontSize := 14;

  // 颜色列表(ColorListBox:右侧常驻列表,每行色块+名)
  L11 := TTyLabel.Create(Self);
  L11.Parent := Self;
  L11.SetBounds(440, 52, 190, 20);
  L11.Caption := '颜色列表(TTyColorListBox):';
  FColorList := TTyColorListBox.Create(Self);
  FColorList.Parent := Self;
  FColorList.SetBounds(440, 76, 180, 296);

  // 字体列表(FontListBox:右侧,每行用自己的字体画)
  L12 := TTyLabel.Create(Self);
  L12.Parent := Self;
  L12.SetBounds(440, 380, 190, 20);
  L12.Caption := '字体列表(TTyFontListBox):';
  FFontList := TTyFontListBox.Create(Self);
  FFontList.Parent := Self;
  FFontList.SetBounds(440, 404, 180, 164);

  // 勾选列表(CheckListBox:点框 / 空格切换,勾选状态存 Objects)
  L13 := TTyLabel.Create(Self);
  L13.Parent := Self;
  L13.SetBounds(640, 52, 190, 20);
  L13.Caption := '勾选列表(TTyCheckListBox):';
  FCheckList := TTyCheckListBox.Create(Self);
  FCheckList.Parent := Self;
  FCheckList.SetBounds(640, 76, 180, 280);
  FCheckList.Items.Add('粗体 Bold');
  FCheckList.Items.Add('斜体 Italic');
  FCheckList.Items.Add('下划线 Underline');
  FCheckList.Items.Add('删除线 Strikeout');
  FCheckList.Items.Add('自动换行 Word wrap');
  FCheckList.Items.Add('显示行号 Line numbers');
  FCheckList.Checked[0] := True;
  FCheckList.Checked[2] := True;

  // 颜色组合框 + "更多…"(ColorComboBox:下拉选"更多…"开取色对话框)
  L14 := TTyLabel.Create(Self);
  L14.Parent := Self;
  L14.SetBounds(640, 380, 190, 20);
  L14.Caption := '颜色 + 更多(TTyColorComboBox):';
  FColorCombo := TTyColorComboBox.Create(Self);
  FColorCombo.Parent := Self;
  FColorCombo.SetBounds(640, 404, 180, 28);
  FColorCombo.MoreCaption := '更多颜色…';

  // 勾选下拉(CheckComboBox:多选、弹层常开,字段显勾选汇总),放第 3 列 ColorCombo 下方
  L23 := TTyLabel.Create(Self);
  L23.Parent := Self;
  L23.SetBounds(640, 452, 190, 20);
  L23.Caption := '勾选下拉(TTyCheckComboBox):';
  FCheckCombo := TTyCheckComboBox.Create(Self);
  FCheckCombo.Parent := Self;
  FCheckCombo.SetBounds(640, 476, 190, 28);
  FCheckCombo.Items.Add('粗体');
  FCheckCombo.Items.Add('斜体');
  FCheckCombo.Items.Add('下划线');
  FCheckCombo.Items.Add('删除线');
  FCheckCombo.EmptyText := '(未选择样式)';
  FCheckCombo.Checked[0] := True;
  FCheckCombo.Checked[2] := True;

  // ---- 第 4 列:批量新控件 ----
  // 最近使用组合框(MRUComboBox:可编辑,选中/录入自动去重置顶)
  L15 := TTyLabel.Create(Self);
  L15.Parent := Self;
  L15.SetBounds(840, 52, 200, 20);
  L15.Caption := '最近使用(TTyMRUComboBox):';
  FMRU := TTyMRUComboBox.Create(Self);
  FMRU.Parent := Self;
  FMRU.SetBounds(840, 76, 190, 28);
  FMRU.MaxItems := 6;
  FMRU.AddToHistory('第一次搜索');
  FMRU.AddToHistory('第二次搜索');
  FMRU.AddToHistory('最近这次(在最上)');

  // 带图标组合框(ComboBoxEx:每项带图标)。图标源 = 图标字体渲染的 3 个符号 → 图像集 → 虚拟图像列表。
  Icf := TTyIconFont.Create(Self);
  Icf.FontFamily := 'Segoe UI Symbol';   // 系统符号字体(无它 RenderGlyph 返回透明图=无图标)
  Coll := TTyImageCollection.Create(Self);
  Imgs := TTyVirtualImageList.Create(Self);
  Imgs.Collection := Coll;
  AddGlyph('save',  $2B07, clNavy);    // ⬇ 保存
  AddGlyph('open',  $25B6, clGreen);   // ▶ 打开
  AddGlyph('print', $2699, clMaroon);  // ⚙ 打印

  L16 := TTyLabel.Create(Self);
  L16.Parent := Self;
  L16.SetBounds(840, 116, 200, 20);
  L16.Caption := '图文组合(TTyComboBoxEx):';
  FComboEx := TTyComboBoxEx.Create(Self);
  FComboEx.Parent := Self;
  FComboEx.SetBounds(840, 140, 190, 28);
  FComboEx.Images := Imgs;
  FComboEx.AddItem('保存', 0);
  FComboEx.AddItem('打开', 1);
  FComboEx.AddItem('打印', 2);
  FComboEx.ItemIndex := 0;

  // 分组组合框(OfficeComboBox:下拉按组分节,标题行不可选)
  L17 := TTyLabel.Create(Self);
  L17.Parent := Self;
  L17.SetBounds(840, 180, 200, 20);
  L17.Caption := '分组组合(TTyOfficeComboBox):';
  FOfficeCombo := TTyOfficeComboBox.Create(Self);
  FOfficeCombo.Parent := Self;
  FOfficeCombo.SetBounds(840, 204, 190, 28);
  FOfficeCombo.AddHeader('水果');
  FOfficeCombo.AddItem('苹果');
  FOfficeCombo.AddItem('芒果');
  FOfficeCombo.AddHeader('蔬菜');
  FOfficeCombo.AddItem('胡萝卜');
  FOfficeCombo.ItemIndex := 1;

  // 分组列表(OfficeListBox:标题行加粗、不可选)
  L18 := TTyLabel.Create(Self);
  L18.Parent := Self;
  L18.SetBounds(840, 244, 200, 20);
  L18.Caption := '分组列表(TTyOfficeListBox):';
  FOfficeList := TTyOfficeListBox.Create(Self);
  FOfficeList.Parent := Self;
  FOfficeList.SetBounds(840, 268, 190, 150);
  FOfficeList.AddHeader('收件箱');
  FOfficeList.AddItem('会议纪要');
  FOfficeList.AddItem('周报');
  FOfficeList.AddHeader('已发送');
  FOfficeList.AddItem('给客户的报价');
  FOfficeList.AddItem('回执确认');

  // 色板网格 + 明度取色条(ColorGrid 点格选色 / LColorPicker 拖动取明度)
  L19 := TTyLabel.Create(Self);
  L19.Parent := Self;
  L19.SetBounds(840, 428, 220, 20);
  L19.Caption := '色板 ColorGrid + 明度 LColorPicker:';
  FColorGrid := TTyColorGrid.Create(Self);
  FColorGrid.Parent := Self;
  FColorGrid.SetBounds(840, 452, 150, 96);
  FColorGrid.Columns := 8;
  FColorGrid.Selected := clRed;
  FLColor := TTyLColorPicker.Create(Self);
  FLColor.Parent := Self;
  FLColor.SetBounds(1000, 452, 28, 96);
  FLColor.Hue := 210;
  FLColor.Sat := 0.8;
  FLColor.Position := 0.6;
  FLColor.OnChange := @LumChange;   // 拖明度条 → 驱动 HS 方块的亮度(经典 HSL 联动)

  // ---- 第 5 列 ----
  // 色相×饱和度取色方块(HSColorPicker:2D 拖动选 Hue/Sat;亮度由上面的 LColorPicker 驱动)
  L20 := TTyLabel.Create(Self);
  L20.Parent := Self;
  L20.SetBounds(1080, 52, 220, 20);
  L20.Caption := 'HS 取色方块(TTyHSColorPicker):';
  FHS := TTyHSColorPicker.Create(Self);
  FHS.Parent := Self;
  FHS.SetBounds(1080, 76, 180, 130);
  FHS.Hue := 210;
  FHS.Sat := 0.8;
  FHS.Value := 0.6;   // 与 FLColor.Position 一致;拖 L 条会更新它

  // 富行列表(AdvancedListBox:每行 图标 + 加粗标题 + 暗色副标题;复用上面的 Imgs)
  L21 := TTyLabel.Create(Self);
  L21.Parent := Self;
  L21.SetBounds(1080, 218, 220, 20);
  L21.Caption := '富行列表(TTyAdvancedListBox):';
  FAdvList := TTyAdvancedListBox.Create(Self);
  FAdvList.Parent := Self;
  FAdvList.SetBounds(1080, 242, 200, 150);
  FAdvList.Images := Imgs;
  FAdvList.AddItem('保存草稿', '未同步 · 2 分钟前', 0);
  FAdvList.AddItem('打开项目', 'D:\work\ty-controls', 1);
  FAdvList.AddItem('打印报表', '默认打印机', 2);
  FAdvList.AddItem('无图标项', '副标题可留空', -1);

  // 富行组合框(AdvancedComboBox:下拉两行富项,字段显图标+标题)
  L22 := TTyLabel.Create(Self);
  L22.Parent := Self;
  L22.SetBounds(1080, 404, 220, 20);
  L22.Caption := '富行组合(TTyAdvancedComboBox):';
  FAdvCombo := TTyAdvancedComboBox.Create(Self);
  FAdvCombo.Parent := Self;
  FAdvCombo.SetBounds(1080, 428, 200, 28);
  FAdvCombo.Images := Imgs;
  FAdvCombo.AddItem('保存', '写入磁盘', 0);
  FAdvCombo.AddItem('打开', '选择文件', 1);
  FAdvCombo.AddItem('打印', '发送到打印机', 2);
  FAdvCombo.ItemIndex := 0;

  // 名/值编辑器(ValueListEditor:属性表,值列内联编辑),放底部
  L24 := TTyLabel.Create(Self);
  L24.Parent := Self;
  L24.SetBounds(24, 600, 340, 20);
  L24.Caption := '名/值编辑器(TTyValueListEditor,点值列 / F2 编辑):';
  FVLE := TTyValueListEditor.Create(Self);
  FVLE.Parent := Self;
  FVLE.SetBounds(24, 624, 360, 160);
  FVLE.KeyColumnWidth := 96;
  FVLE.AddRow('宽度', '1280').EditorKind := vekInteger;
  FVLE.AddRow('标题', 'Rich Inputs 示例');         // 纯文本
  VR := FVLE.AddRow('对齐', 'taCenter');           // 枚举 → 下拉
  VR.EditorKind := vekEnum;
  VR.EnumValues := 'taLeftJustify'#10'taCenter'#10'taRightJustify';
  FVLE.AddRow('前景色', 'clNavy').EditorKind := vekColor;    // 颜色 → 色板对话框 + 色块
  FVLE.AddRow('字体', 'Segoe UI, 9').EditorKind := vekFont;  // 字体 → 字体对话框
  VR := FVLE.AddRow('数据路径', 'D:\data');         // 自定义 "…" 对话框(走 OnEditRow)
  VR.EditorKind := vekDialog;
  VR := FVLE.AddRow('主题', 'light.tycss');        // 只读 + 显示名覆盖(国际化)
  VR.DisplayKey := '主题(只读)';
  VR.ReadOnly := True;
  VR := FVLE.AddRow('Font', '(TFont)');            // 可展开的多级 + 类型化子行
  VR.AddChild('Size', '9').EditorKind := vekInteger;
  VR.AddChild('Bold', 'False').EditorKind := vekBoolean;
  VR.AddChild('Color', 'clWindowText').EditorKind := vekColor;
  FVLE.UpdateRows;                                 // 加了子行后刷新
  FVLE.OnValueChanged := @VleChange;
  FVLE.OnEditRow := @VleEditDialog;

  // 计算器下拉(CalcEdit / CalcCurrencyEdit:点尾部按钮弹计算器,= 或关闭写回),放 VLE 右侧
  L25 := TTyLabel.Create(Self);
  L25.Parent := Self;
  L25.SetBounds(410, 600, 260, 20);
  L25.Caption := '计算器数值(TTyCalcEdit,点尾部小按钮):';
  FCalcEdit := TTyCalcEdit.Create(Self);
  FCalcEdit.Parent := Self;
  FCalcEdit.SetBounds(410, 624, 200, 28);
  FCalcEdit.Value := 1000;

  L26 := TTyLabel.Create(Self);
  L26.Parent := Self;
  L26.SetBounds(410, 662, 260, 20);
  L26.Caption := '计算器货币(TTyCalcCurrencyEdit):';
  FCalcCurr := TTyCalcCurrencyEdit.Create(Self);
  FCalcCurr.Parent := Self;
  FCalcCurr.SetBounds(410, 686, 200, 28);
  FCalcCurr.CurrencySymbol := '¥';
  FCalcCurr.Value := 1234.5;

  FEcho := TTyLabel.Create(Self);
  FEcho.Parent := Self;
  FEcho.SetBounds(24, 496, 400, 20);
  FEcho.Caption := '限幅值 = 42.00';

  LHint := TTyLabel.Create(Self);
  LHint.Parent := Self;
  LHint.SetBounds(24, 536, 400, 40);
  LHint.Caption := '试试:只能输数字 / 负号 / 小数点;聚焦时去掉千分位方便编辑,'
    + '失焦后重新分组;限幅框输入 >100 的值,失焦后夹紧到 100。';

  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.RangedChange(Sender: TObject);
begin
  FEcho.Caption := Format('限幅值 = %.2f  (失焦后夹紧到 0..100)', [FRanged.Value]);
end;

procedure TMainForm.ComboDrop(Sender: TObject);
begin
  // 真实用法:在这里弹颜色格 / 计算器 / 日期选择器,选完写回 FCombo.Text。
  FCombo.Text := '你点了下拉按钮!';
end;

procedure TMainForm.LumChange(Sender: TObject);
begin
  // 明度条驱动 HS 方块的亮度:两个控件合成一个经典 HSL 取色器。
  FHS.Value := FLColor.Position;
end;

procedure TMainForm.VleChange(Sender: TObject; ARow: TTyValueRow);
begin
  FEcho.Caption := Format('改了「%s」= %s', [ARow.Key, ARow.Value]);
end;

procedure TMainForm.VleEditDialog(Sender: TObject; ARow: TTyValueRow);
begin
  // vekDialog:真实用法在这里弹自定义对话框(选路径 / 输入等),选完写回 ARow.Value。
  if InputQuery('数据路径', '输入路径:', ARow.Value) then
    FEcho.Caption := Format('改了「%s」= %s', [ARow.Key, ARow.Value]);
end;

end.
