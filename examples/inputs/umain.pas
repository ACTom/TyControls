unit umain;

{ Phase-4 富输入 & 选择器示例。随各控件建成逐步扩充;当前展示 TTyNumericEdit
  (数值编辑:输入过滤 + 失焦分组格式化 + 限幅)。纯代码创建,主题走全局 TyDefaultController。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.NumericEdit, tyControls.CurrencyEdit, tyControls.MaskEdit,
  tyControls.URLEdit, tyControls.ComboEdit, tyControls.TrackEdit,
  tyControls.ColorBox, tyControls.ColorListBox, tyControls.FontComboBox,
  tyControls.FontListBox, tyControls.FontSizeComboBox, tyControls.TyLabel;

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
    FEcho: TTyLabel;
    procedure RangedChange(Sender: TObject);
    procedure ComboDrop(Sender: TObject);
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
  L1, L2, L3, L4, L5, L6, L7, L8, L9, L10, L11, L12, LHint: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Rich Inputs 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 640, 600);

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
  FUrl.Text := 'https://gitee.com/';

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

end.
