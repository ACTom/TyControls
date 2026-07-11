unit umain;

{ Phase-4 rich-input & picker demo. Grows as each control lands; currently showcases
  TTyNumericEdit (numeric editing: input filtering + on-blur grouped formatting + clamping).
  Built purely in code; themed via the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, BGRABitmap,
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
  tyControls.CalcEdit, tyControls.CalcCurrencyEdit, tyControls.TyLabel,
  tyControls.Dialogs.SelectPath, tyControls.Dialogs.About;

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

{ Walk up from the exe's directory to locate the repo's themes/ directory }
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
  VR, VS: TTyValueRow;

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

  // Integer (no decimals, thousands separators)
  L1 := TTyLabel.Create(Self);
  L1.Parent := Self;
  L1.SetBounds(24, 56, 200, 20);
  L1.Caption := '数量(整数,Decimals=0):';
  FQty := TTyNumericEdit.Create(Self);
  FQty.Parent := Self;
  FQty.SetBounds(240, 52, 180, 28);
  FQty.Decimals := 0;
  FQty.Value := 1250;

  // Amount (2 decimals + thousands separators)
  L2 := TTyLabel.Create(Self);
  L2.Parent := Self;
  L2.SetBounds(24, 100, 200, 20);
  L2.Caption := '金额(2 位小数 + 千分位):';
  FPrice := TTyNumericEdit.Create(Self);
  FPrice.Parent := Self;
  FPrice.SetBounds(240, 96, 180, 28);
  FPrice.Value := 1234567.5;

  // Clamp 0..100
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

  // Currency (CurrencyEdit: symbol shown only in the on-blur display state)
  L4 := TTyLabel.Create(Self);
  L4.Parent := Self;
  L4.SetBounds(24, 188, 200, 20);
  L4.Caption := '货币(TTyCurrencyEdit,¥):';
  FMoney := TTyCurrencyEdit.Create(Self);
  FMoney.Parent := Self;
  FMoney.SetBounds(240, 184, 180, 28);
  FMoney.CurrencySymbol := '¥';
  FMoney.Value := 1234.5;

  // Mask (MaskEdit: date, append-style entry + auto-inserted /)
  L5 := TTyLabel.Create(Self);
  L5.Parent := Self;
  L5.SetBounds(24, 232, 200, 20);
  L5.Caption := '日期掩码(##/##/####):';
  FDate := TTyMaskEdit.Create(Self);
  FDate.Parent := Self;
  FDate.SetBounds(240, 228, 180, 28);
  FDate.Mask := '##/##/####';

  // URL (URLEdit: trailing → button opens it in the default browser)
  L6 := TTyLabel.Create(Self);
  L6.Parent := Self;
  L6.SetBounds(24, 276, 200, 20);
  L6.Caption := 'URL(TTyURLEdit,点 →):';
  FUrl := TTyURLEdit.Create(Self);
  FUrl.Parent := Self;
  FUrl.SetBounds(240, 272, 180, 28);
  FUrl.Text := 'https://github.com/ACTom/TyControls';

  // Dropdown (ComboEdit: clicking the button fires OnDropDown; you decide what pops up)
  L7 := TTyLabel.Create(Self);
  L7.Parent := Self;
  L7.SetBounds(24, 320, 200, 20);
  L7.Caption := '下拉(TTyComboEdit):';
  FCombo := TTyComboEdit.Create(Self);
  FCombo.Parent := Self;
  FCombo.SetBounds(240, 316, 180, 28);
  FCombo.OnDropDown := @ComboDrop;

  // Value + inline slider (TrackEdit: drag the thumb or type directly)
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

  // Color combo (ColorBox: the field and every dropdown item carry a swatch)
  L9 := TTyLabel.Create(Self);
  L9.Parent := Self;
  L9.SetBounds(24, 408, 200, 20);
  L9.Caption := '颜色(TTyColorBox):';
  FColor := TTyColorBox.Create(Self);
  FColor.Parent := Self;
  FColor.SetBounds(240, 404, 180, 28);

  // Font combo (FontComboBox: each item is drawn in its own font)
  L10 := TTyLabel.Create(Self);
  L10.Parent := Self;
  L10.SetBounds(24, 452, 200, 20);
  L10.Caption := '字体(TTyFontComboBox):';
  FFont := TTyFontComboBox.Create(Self);
  FFont.Parent := Self;
  FFont.SetBounds(240, 448, 128, 28);

  // Font size (FontSizeComboBox: editable, presets + free entry), right next to the font combo
  FSize := TTyFontSizeComboBox.Create(Self);
  FSize.Parent := Self;
  FSize.SetBounds(372, 448, 48, 28);
  FSize.FontSize := 14;

  // Color list (ColorListBox: persistent list on the right, each row a swatch + name)
  L11 := TTyLabel.Create(Self);
  L11.Parent := Self;
  L11.SetBounds(440, 52, 190, 20);
  L11.Caption := '颜色列表(TTyColorListBox):';
  FColorList := TTyColorListBox.Create(Self);
  FColorList.Parent := Self;
  FColorList.SetBounds(440, 76, 180, 296);

  // Font list (FontListBox: on the right, each row drawn in its own font)
  L12 := TTyLabel.Create(Self);
  L12.Parent := Self;
  L12.SetBounds(440, 380, 190, 20);
  L12.Caption := '字体列表(TTyFontListBox):';
  FFontList := TTyFontListBox.Create(Self);
  FFontList.Parent := Self;
  FFontList.SetBounds(440, 404, 180, 164);

  // Check list (CheckListBox: click the box / Space to toggle; checked state stored in Objects)
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

  // Color combo + "More…" (ColorComboBox: picking "More…" from the dropdown opens the color dialog)
  L14 := TTyLabel.Create(Self);
  L14.Parent := Self;
  L14.SetBounds(640, 380, 190, 20);
  L14.Caption := '颜色 + 更多(TTyColorComboBox):';
  FColorCombo := TTyColorComboBox.Create(Self);
  FColorCombo.Parent := Self;
  FColorCombo.SetBounds(640, 404, 180, 28);
  FColorCombo.MoreCaption := '更多颜色…';

  // Check dropdown (CheckComboBox: multi-select, popup stays open, field shows a summary of the checks), placed under ColorCombo in column 3
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

  // ---- Column 4: a batch of new controls ----
  // Most-recently-used combo (MRUComboBox: editable; selecting/typing auto-dedupes and moves to top)
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

  // Combo with icons (ComboBoxEx: every item carries an icon). Icon source = 3 symbols rendered from the icon font → image collection → virtual image list.
  Icf := TTyIconFont.Create(Self);
  Icf.FontFamily := 'Segoe UI Symbol';   // system symbol font (without it RenderGlyph returns a transparent bitmap = no icon)
  Coll := TTyImageCollection.Create(Self);
  Imgs := TTyVirtualImageList.Create(Self);
  Imgs.Collection := Coll;
  AddGlyph('save',  $2B07, clNavy);    // ⬇ save
  AddGlyph('open',  $25B6, clGreen);   // ▶ open
  AddGlyph('print', $2699, clMaroon);  // ⚙ print

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

  // Grouped combo (OfficeComboBox: dropdown split into sections by group, header rows not selectable)
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

  // Grouped list (OfficeListBox: header rows bold and not selectable)
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

  // Swatch grid + luminance bar (ColorGrid: click a cell to pick a color / LColorPicker: drag to pick luminance)
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
  FLColor.OnChange := @LumChange;   // dragging the luminance bar → drives the HS square's brightness (classic HSL linkage)

  // ---- Column 5 ----
  // Hue × saturation picker square (HSColorPicker: 2D drag to pick Hue/Sat; brightness driven by the LColorPicker above)
  L20 := TTyLabel.Create(Self);
  L20.Parent := Self;
  L20.SetBounds(1080, 52, 220, 20);
  L20.Caption := 'HS 取色方块(TTyHSColorPicker):';
  FHS := TTyHSColorPicker.Create(Self);
  FHS.Parent := Self;
  FHS.SetBounds(1080, 76, 180, 130);
  FHS.Hue := 210;
  FHS.Sat := 0.8;
  FHS.Value := 0.6;   // matches FLColor.Position; dragging the L bar updates it

  // Rich-row list (AdvancedListBox: each row has icon + bold title + dimmed subtitle; reuses the Imgs above)
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

  // Rich-row combo (AdvancedComboBox: two-line rich items in the dropdown, field shows icon + title)
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

  // Name/value editor (ValueListEditor: property sheet, inline editing in the value column), placed at the bottom
  L24 := TTyLabel.Create(Self);
  L24.Parent := Self;
  L24.SetBounds(24, 600, 340, 20);
  L24.Caption := '名/值编辑器(TTyValueListEditor,点值列 / F2 编辑):';
  FVLE := TTyValueListEditor.Create(Self);
  FVLE.Parent := Self;
  FVLE.SetBounds(24, 624, 360, 160);
  FVLE.KeyColumnWidth := 96;
  FVLE.AddRow('宽度', '1280').EditorKind := vekInteger;
  FVLE.AddRow('标题', 'Rich Inputs 示例');         // plain text
  VR := FVLE.AddRow('对齐', 'taCenter');           // enum → dropdown
  VR.EditorKind := vekEnum;
  VR.EnumValues := 'taLeftJustify'#10'taCenter'#10'taRightJustify';
  FVLE.AddRow('前景色', 'clNavy').EditorKind := vekColor;    // color → swatch dropdown (last "More…" row opens the dialog)
  FVLE.AddRow('字体', 'Segoe UI, 9').EditorKind := vekFont;  // leaf font → text + "…" opens the font dialog
  VR := FVLE.AddRow('数据路径', 'D:\data');         // text + "…" → the library's own path dialog (OnEditRow)
  VR.EditorKind := vekDialog;
  VR := FVLE.AddRow('关于', 'TyControls 2.2.0');    // user-side custom: "…" opens a read-only About dialog, no write-back
  VR.EditorKind := vekDialog;
  VR := FVLE.AddRow('主题', 'light.tycss');        // read-only + display-name override (i18n)
  VR.DisplayKey := '主题(只读)';
  VR.ReadOnly := True;
  VR := FVLE.AddRow('Font', 'Segoe UI, 9');        // expandable multi-level + vekFont: "…" opens the font dialog and writes back the child properties
  VR.EditorKind := vekFont;
  VR.AddChild('Name', 'Segoe UI');
  VR.AddChild('Size', '9').EditorKind := vekInteger;
  VR.AddChild('Color', 'clWindowText').EditorKind := vekColor;
  VS := VR.AddChild('Style', 'Regular');           // second-level child (unlimited nesting: Font→Style→Bold)
  VS.AddChild('Bold', 'False').EditorKind := vekBoolean;
  VS.AddChild('Italic', 'False').EditorKind := vekBoolean;
  VS.AddChild('Underline', 'False').EditorKind := vekBoolean;
  VS.AddChild('StrikeOut', 'False').EditorKind := vekBoolean;
  FVLE.UpdateRows;                                 // refresh after adding child rows
  FVLE.OnValueChanged := @VleChange;
  FVLE.OnEditRow := @VleEditDialog;

  // Calculator dropdown (CalcEdit / CalcCurrencyEdit: click the trailing button to pop the calculator; = or close writes back), placed to the right of the VLE
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
  // Real-world use: pop a color grid / calculator / date picker here, then write the result back into FCombo.Text.
  FCombo.Text := '你点了下拉按钮!';
end;

procedure TMainForm.LumChange(Sender: TObject);
begin
  // The luminance bar drives the HS square's brightness: the two controls together form a classic HSL color picker.
  FHS.Value := FLColor.Position;
end;

procedure TMainForm.VleChange(Sender: TObject; ARow: TTyValueRow);
begin
  FEcho.Caption := Format('改了「%s」= %s', [ARow.Key, ARow.Value]);
end;

procedure TMainForm.VleEditDialog(Sender: TObject; ARow: TTyValueRow);
var dir: string;
begin
  // vekDialog = fully user-side custom: clicking "…" fires this event; each row decides what to pop up and whether to write the value back.
  if SameText(ARow.Key, '关于') then
    // Informational only (read-only content): pop the library's own read-only About dialog; leave ARow.Value unchanged.
    TyShowAbout('关于', 'TyControls Rich Inputs 示例', 'v2.2.0',
      'ValueListEditor 用户侧自定义行处理演示', '© 2026 ACTom', 'MIT 许可',
      'https://github.com/ACTom/TyControls')
  else
  begin
    // Pop the [library's own] path dialog (not the native one), then write the result back into ARow.Value (which updates the display).
    dir := ARow.Value;
    if TySelectDirectory('选择数据路径', '', dir) then
    begin
      ARow.Value := dir;
      FEcho.Caption := Format('改了「%s」= %s', [ARow.Key, ARow.Value]);
    end;
  end;
end;

end.
