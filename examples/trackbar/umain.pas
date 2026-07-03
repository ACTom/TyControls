unit umain;

{ TTyTrackBar 示例：
  - 水平轨迹条（0..100），OnChange 实时更新状态栏
  - 自定义范围轨迹条（-50..50，展示负值区间）
  - 垂直轨迹条（Orientation = toVertical）
  - StyleClass 变体（'primary'）
  主窗体为 TTyForm + TTyTitleBar；纯代码创建 UI（无 .lfm），
  主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.TrackBar, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FTrack1: TTyTrackBar;   // 0..100 水平
    FTrack2: TTyTrackBar;   // -50..50 水平
    FTrack3: TTyTrackBar;   // 垂直
    FStatus: TTyLabel;      // OnChange 状态读出
    procedure Track1Change(Sender: TObject);
    procedure Track2Change(Sender: TObject);
    procedure Track3Change(Sender: TObject);
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
  LblA, LblB, LblC, LblStyle: TTyLabel;
  FTrack4: TTyTrackBar;   // StyleClass 变体演示
begin
  inherited CreateNew(AOwner, 0);          // TTyForm：无边框 + 常驻引擎
  Caption := 'TrackBar 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 460, 380);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // 先加载主题

  Bar := TTyTitleBar.Create(Self);         // Owner=Self → 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TrackBar  · TyControls';

  // 轨迹条一：0..100（水平），拖动 / 键盘左右键步进 / 滚轮
  LblA := TTyLabel.Create(Self);
  LblA.Parent := Self;
  LblA.SetBounds(16, 48, 320, 20);
  LblA.Caption := '音量（0..100，Min/Max/Position）：';

  FTrack1 := TTyTrackBar.Create(Self);
  FTrack1.Parent := Self;
  FTrack1.SetBounds(16, 70, 300, 24);
  FTrack1.Min := 0;
  FTrack1.Max := 100;
  FTrack1.Position := 50;
  FTrack1.Frequency := 10;         // 每 10 个单位一条刻度
  FTrack1.OnChange := @Track1Change;

  // 轨迹条二：-50..50（水平），展示负值范围
  LblB := TTyLabel.Create(Self);
  LblB.Parent := Self;
  LblB.SetBounds(16, 108, 320, 20);
  LblB.Caption := '平衡（-50..50）：';

  FTrack2 := TTyTrackBar.Create(Self);
  FTrack2.Parent := Self;
  FTrack2.SetBounds(16, 130, 300, 24);
  FTrack2.Min := -50;
  FTrack2.Max := 50;
  FTrack2.Position := 0;
  FTrack2.OnChange := @Track2Change;

  // 轨迹条四：StyleClass 变体（'primary'）
  LblStyle := TTyLabel.Create(Self);
  LblStyle.Parent := Self;
  LblStyle.SetBounds(16, 168, 320, 20);
  LblStyle.Caption := 'StyleClass = ''primary''：';

  FTrack4 := TTyTrackBar.Create(Self);
  FTrack4.Parent := Self;
  FTrack4.SetBounds(16, 190, 300, 24);
  FTrack4.Min := 0;
  FTrack4.Max := 100;
  FTrack4.Position := 70;
  FTrack4.StyleClass := 'primary';        // 对应 .tycss 中 TyTrackBar.primary
  FTrack4.OnChange := @Track1Change;

  // 轨迹条三：垂直（Orientation = toVertical）
  LblC := TTyLabel.Create(Self);
  LblC.Parent := Self;
  LblC.SetBounds(350, 48, 100, 20);
  LblC.Caption := '垂直：';

  FTrack3 := TTyTrackBar.Create(Self);
  FTrack3.Parent := Self;
  FTrack3.SetBounds(380, 70, 24, 200);
  FTrack3.Orientation := toVertical;      // 垂直方向
  FTrack3.Min := 0;
  FTrack3.Max := 100;
  FTrack3.Position := 40;
  FTrack3.OnChange := @Track3Change;

  // 状态栏：任一轨迹条 OnChange 都会写入这里
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 236, 320, 20);
  FStatus.Caption := Format('音量：%d', [FTrack1.Position]);

  ApplyChromeTheme(TyDefaultController);   // 最后统一应用 chrome + 窗体背景主题
end;

procedure TMainForm.Track1Change(Sender: TObject);
begin
  FStatus.Caption := Format('音量：%d', [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track2Change(Sender: TObject);
begin
  FStatus.Caption := Format('平衡：%d', [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track3Change(Sender: TObject);
begin
  FStatus.Caption := Format('垂直：%d', [(Sender as TTyTrackBar).Position]);
end;

end.
