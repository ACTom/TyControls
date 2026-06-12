unit umain;

{ TTyProgressBar + TTyTrackBar 联动示例：
  - TTyTrackBar（0..100）拖动 → TTyProgressBar.Position 实时跟随
  - TTyLabel 分别显示进度条数值和轨迹条数值
  - 展示跨控件事件联动（OnChange 驱动）
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.ProgressBar, tyControls.TrackBar,
  tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FTrackBar: TTyTrackBar;
    FProgressBar: TTyProgressBar;
    FTrackLabel: TTyLabel;
    FProgressLabel: TTyLabel;
    procedure TrackBarChange(Sender: TObject);
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
  LblTitle: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyProgressBar 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 360, 260);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  LblTitle := TTyLabel.Create(Self);
  LblTitle.Parent := Self;
  LblTitle.SetBounds(16, 16, 320, 20);
  LblTitle.Caption := '拖动轨迹条驱动进度条：';

  // 进度条
  FProgressBar := TTyProgressBar.Create(Self);
  FProgressBar.Parent := Self;
  FProgressBar.SetBounds(16, 48, 320, 20);
  FProgressBar.Min := 0;
  FProgressBar.Max := 100;
  FProgressBar.Position := 0;

  FProgressLabel := TTyLabel.Create(Self);
  FProgressLabel.Parent := Self;
  FProgressLabel.SetBounds(16, 76, 320, 20);
  FProgressLabel.Caption := '进度：0 / 100';

  // 分隔标题
  TTyLabel.Create(Self).Parent := Self;
  with TTyLabel(Self.Controls[Self.ControlCount - 1]) do
  begin
    SetBounds(16, 112, 320, 20);
    Caption := '轨迹条（拖动或键盘左右键）：';
  end;

  // 轨迹条：OnChange → 进度条同步
  FTrackBar := TTyTrackBar.Create(Self);
  FTrackBar.Parent := Self;
  FTrackBar.SetBounds(16, 140, 320, 24);
  FTrackBar.Min := 0;
  FTrackBar.Max := 100;
  FTrackBar.Position := 0;
  FTrackBar.OnChange := @TrackBarChange;

  FTrackLabel := TTyLabel.Create(Self);
  FTrackLabel.Parent := Self;
  FTrackLabel.SetBounds(16, 172, 320, 20);
  FTrackLabel.Caption := '轨迹值：0';
end;

procedure TMainForm.TrackBarChange(Sender: TObject);
var
  Val: Integer;
begin
  Val := (Sender as TTyTrackBar).Position;
  // 轨迹条驱动进度条（跨控件联动）
  FProgressBar.Position := Val;
  FTrackLabel.Caption   := Format('轨迹值：%d', [Val]);
  FProgressLabel.Caption := Format('进度：%d / 100', [Val]);
end;

end.
