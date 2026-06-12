unit umain;

{ TTyTrackBar 示例：
  - 单个轨迹条（0..100），OnChange 实时更新数值标签
  - 支持鼠标拖动拇指以及键盘左右键步进（每按一次 ±1）
  - 第二个轨迹条展示自定义范围（-50..50）
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.TrackBar, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FTrack1: TTyTrackBar;
    FLabel1: TTyLabel;
    FTrack2: TTyTrackBar;
    FLabel2: TTyLabel;
    procedure Track1Change(Sender: TObject);
    procedure Track2Change(Sender: TObject);
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
  LblA, LblB: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyTrackBar 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 360, 260);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 轨迹条一：0..100
  LblA := TTyLabel.Create(Self);
  LblA.Parent := Self;
  LblA.SetBounds(16, 24, 320, 20);
  LblA.Caption := '音量（0..100，拖动或键盘左右键）：';

  FTrack1 := TTyTrackBar.Create(Self);
  FTrack1.Parent := Self;
  FTrack1.SetBounds(16, 52, 320, 24);
  FTrack1.Min := 0;
  FTrack1.Max := 100;
  FTrack1.Position := 50;     // 初始值居中
  FTrack1.OnChange := @Track1Change;

  FLabel1 := TTyLabel.Create(Self);
  FLabel1.Parent := Self;
  FLabel1.SetBounds(16, 84, 320, 20);
  FLabel1.Caption := Format('音量：%d', [FTrack1.Position]);

  // 轨迹条二：-50..50，展示负值范围
  LblB := TTyLabel.Create(Self);
  LblB.Parent := Self;
  LblB.SetBounds(16, 136, 320, 20);
  LblB.Caption := '平衡（-50..50）：';

  FTrack2 := TTyTrackBar.Create(Self);
  FTrack2.Parent := Self;
  FTrack2.SetBounds(16, 164, 320, 24);
  FTrack2.Min := -50;
  FTrack2.Max := 50;
  FTrack2.Position := 0;      // 初始值居中
  FTrack2.OnChange := @Track2Change;

  FLabel2 := TTyLabel.Create(Self);
  FLabel2.Parent := Self;
  FLabel2.SetBounds(16, 196, 320, 20);
  FLabel2.Caption := '平衡：0';
end;

procedure TMainForm.Track1Change(Sender: TObject);
begin
  FLabel1.Caption := Format('音量：%d', [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track2Change(Sender: TObject);
begin
  FLabel2.Caption := Format('平衡：%d', [(Sender as TTyTrackBar).Position]);
end;

end.
