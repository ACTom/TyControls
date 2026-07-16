unit umain;

{ Phase-4 rich-input & picker demo. Grows as each control lands; showcases the rich edits
  (numeric / currency / mask / URL / combo-edit / track), the colour & font pickers, the
  grouped and rich list/combo boxes, the value-list editor and the calculator edits. The
  window, every control and the live theme switcher are designed in umain.lfm (a TTyForm +
  TTyTitleBar); the code here is theme setup, runtime item/value population and event handlers. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, BGRABitmap,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.IconFont, tyControls.ImageCollection, tyControls.ColorMath,
  tyControls.NumericEdit, tyControls.CurrencyEdit, tyControls.MaskEdit,
  tyControls.URLEdit, tyControls.ComboEdit, tyControls.TrackEdit,
  tyControls.ColorBox, tyControls.ColorListBox, tyControls.FontComboBox,
  tyControls.FontListBox, tyControls.FontSizeComboBox, tyControls.CheckListBox,
  tyControls.ColorComboBox, tyControls.MRUComboBox, tyControls.ComboBoxEx,
  tyControls.OfficeListBox, tyControls.OfficeComboBox, tyControls.ColorGrid,
  tyControls.LColorPicker, tyControls.HSColorPicker, tyControls.CheckComboBox,
  tyControls.AdvancedListBox, tyControls.AdvancedComboBox, tyControls.ValueListEditor,
  tyControls.CalcEdit, tyControls.CalcCurrencyEdit, tyControls.TyLabel,
  tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.Dialogs.SelectPath, tyControls.Dialogs.About;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    L1: TTyLabel;
    L2: TTyLabel;
    L3: TTyLabel;
    L4: TTyLabel;
    L5: TTyLabel;
    L6: TTyLabel;
    L7: TTyLabel;
    L8: TTyLabel;
    L9: TTyLabel;
    L10: TTyLabel;
    L11: TTyLabel;
    L12: TTyLabel;
    L13: TTyLabel;
    L14: TTyLabel;
    L15: TTyLabel;
    L16: TTyLabel;
    L17: TTyLabel;
    L18: TTyLabel;
    L19: TTyLabel;
    L20: TTyLabel;
    L21: TTyLabel;
    L22: TTyLabel;
    L23: TTyLabel;
    L24: TTyLabel;
    L25: TTyLabel;
    L26: TTyLabel;
    LHint: TTyLabel;
    FQty: TTyNumericEdit;
    FPrice: TTyNumericEdit;
    FRanged: TTyNumericEdit;
    FMoney: TTyCurrencyEdit;
    FDate: TTyMaskEdit;
    FUrl: TTyURLEdit;
    FCombo: TTyComboEdit;
    FTrack: TTyTrackEdit;
    FColor: TTyColorBox;
    FFont: TTyFontComboBox;
    FSize: TTyFontSizeComboBox;
    FColorList: TTyColorListBox;
    FFontList: TTyFontListBox;
    FCheckList: TTyCheckListBox;
    FColorCombo: TTyColorComboBox;
    FCheckCombo: TTyCheckComboBox;
    FMRU: TTyMRUComboBox;
    FComboEx: TTyComboBoxEx;
    FOfficeCombo: TTyOfficeComboBox;
    FOfficeList: TTyOfficeListBox;
    FColorGrid: TTyColorGrid;
    FLColor: TTyLColorPicker;
    FHS: TTyHSColorPicker;
    FAdvList: TTyAdvancedListBox;
    FAdvCombo: TTyAdvancedComboBox;
    FVLE: TTyValueListEditor;
    FCalcEdit: TTyCalcEdit;
    FCalcCurr: TTyCalcCurrencyEdit;
    FEcho: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure RangedChange(Sender: TObject);
    procedure ComboDrop(Sender: TObject);
    procedure LumChange(Sender: TObject);
    procedure VleChange(Sender: TObject; ARow: TTyValueRow);
    procedure VleEditDialog(Sender: TObject; ARow: TTyValueRow);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
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
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // ---- Runtime setup that can't be a .lfm property ----

  // Value is a public (not published) property on the numeric edits → set it here.
  FQty.Value := 1250;
  FPrice.Value := 1234567.5;
  FRanged.Value := 42;
  FRanged.OnChange := @RangedChange;   // wire AFTER Value so the initial set doesn't fire it
  FMoney.Value := 1234.5;
  FTrack.Value := 128;
  FSize.FontSize := 14;   // FontSize is a public (not published) property → set it here.

  // Check list (CheckListBox: click the box / Space to toggle; checked state stored in Objects)
  FCheckList.Items.Add('粗体 Bold');
  FCheckList.Items.Add('斜体 Italic');
  FCheckList.Items.Add('下划线 Underline');
  FCheckList.Items.Add('删除线 Strikeout');
  FCheckList.Items.Add('自动换行 Word wrap');
  FCheckList.Items.Add('显示行号 Line numbers');
  FCheckList.Checked[0] := True;
  FCheckList.Checked[2] := True;

  // Check dropdown (CheckComboBox: multi-select, popup stays open, field shows a summary of the checks)
  FCheckCombo.Items.Add('粗体');
  FCheckCombo.Items.Add('斜体');
  FCheckCombo.Items.Add('下划线');
  FCheckCombo.Items.Add('删除线');
  FCheckCombo.Checked[0] := True;
  FCheckCombo.Checked[2] := True;

  // Most-recently-used combo (MRUComboBox: editable; selecting/typing auto-dedupes and moves to top)
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

  FComboEx.Images := Imgs;
  FComboEx.AddItem('保存', 0);
  FComboEx.AddItem('打开', 1);
  FComboEx.AddItem('打印', 2);
  FComboEx.ItemIndex := 0;

  // Grouped combo (OfficeComboBox: dropdown split into sections by group, header rows not selectable)
  FOfficeCombo.AddHeader('水果');
  FOfficeCombo.AddItem('苹果');
  FOfficeCombo.AddItem('芒果');
  FOfficeCombo.AddHeader('蔬菜');
  FOfficeCombo.AddItem('胡萝卜');
  FOfficeCombo.ItemIndex := 1;

  // Grouped list (OfficeListBox: header rows bold and not selectable)
  FOfficeList.AddHeader('收件箱');
  FOfficeList.AddItem('会议纪要');
  FOfficeList.AddItem('周报');
  FOfficeList.AddHeader('已发送');
  FOfficeList.AddItem('给客户的报价');
  FOfficeList.AddItem('回执确认');

  // Luminance bar drives the HS square's brightness (classic HSL linkage); wire after all controls exist.
  FLColor.OnChange := @LumChange;

  // Rich-row list (AdvancedListBox: each row has icon + bold title + dimmed subtitle; reuses the Imgs above)
  FAdvList.Images := Imgs;
  FAdvList.AddItem('保存草稿', '未同步 · 2 分钟前', 0);
  FAdvList.AddItem('打开项目', 'D:\work\ty-controls', 1);
  FAdvList.AddItem('打印报表', '默认打印机', 2);
  FAdvList.AddItem('无图标项', '副标题可留空', -1);

  // Rich-row combo (AdvancedComboBox: two-line rich items in the dropdown, field shows icon + title)
  FAdvCombo.Images := Imgs;
  FAdvCombo.AddItem('保存', '写入磁盘', 0);
  FAdvCombo.AddItem('打开', '选择文件', 1);
  FAdvCombo.AddItem('打印', '发送到打印机', 2);
  FAdvCombo.ItemIndex := 0;

  // Name/value editor (ValueListEditor: property sheet, inline editing in the value column)
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

  // Calculator dropdown (CalcEdit / CalcCurrencyEdit): Value is public, set here.
  FCalcEdit.Value := 1000;
  FCalcCurr.Value := 1234.5;
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
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
