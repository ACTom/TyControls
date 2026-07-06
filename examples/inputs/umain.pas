unit umain;

{ Phase-4 富输入 & 选择器示例。随各控件建成逐步扩充;当前展示 TTyNumericEdit
  (数值编辑:输入过滤 + 失焦分组格式化 + 限幅)。纯代码创建,主题走全局 TyDefaultController。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.NumericEdit, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FQty, FPrice, FRanged: TTyNumericEdit;
    FEcho: TTyLabel;
    procedure RangedChange(Sender: TObject);
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
  L1, L2, L3, LHint: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Rich Inputs 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 460, 300);

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

  FEcho := TTyLabel.Create(Self);
  FEcho.Parent := Self;
  FEcho.SetBounds(24, 184, 410, 20);
  FEcho.Caption := '限幅值 = 42.00';

  LHint := TTyLabel.Create(Self);
  LHint.Parent := Self;
  LHint.SetBounds(24, 224, 410, 40);
  LHint.Caption := '试试:只能输数字 / 负号 / 小数点;聚焦时去掉千分位方便编辑,'
    + '失焦后重新分组;限幅框输入 >100 的值,失焦后夹紧到 100。';

  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.RangedChange(Sender: TObject);
begin
  FEcho.Caption := Format('限幅值 = %.2f  (失焦后夹紧到 0..100)', [FRanged.Value]);
end;

end.
