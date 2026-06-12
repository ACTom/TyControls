unit umain;

{ TTyFormChrome 无边框自绘窗框示例：
  纯代码激活方式：
    1. 在构造函数末尾直接设置 Chrome.Active := True。
    2. TTyFormChrome.SetActive 调用 InstallChrome，后者通过
       HostForm（= Owner as TCustomForm）获取宿主窗体——只要
       Self 已作为 AOwner 传给 TTyFormChrome.Create，Owner 便已就绪，
       即使构造函数尚未返回也没问题。
       （lfm 方案里 Active=True 由流加载器在 FormCreate 之前设置，效果相同。）

  已知缺口（见 docs/KNOWN_GAPS.md）：
    - 无原生 Aero Snap / 磁贴吸附支持
    - 无系统阴影（bsNone 后 GTK/Win32 不绘制投影）
    - Active 只能激活一次：UninstallChrome 后再设 Active=True 无效
    - 最大化基于 Screen.Monitor.WorkareaRect，不支持多显示器动态变化
  纯代码 UI（无 .lfm）。}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FChrome: TTyFormChrome;
    FCountLabel: TTyLabel;
    FClickCount: Integer;
    procedure BtnHelloClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ 从 exe 所在目录向上查找仓库的 themes/ 目录 }
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
  BtnHello: TTyButton;
  InfoLbl: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyFormChrome 示例';   // TitleBar 的 Caption 单独设置
  Position := poScreenCenter;
  SetBounds(0, 0, 480, 320);

  // 主题必须在激活 Chrome 之前加载，否则 TitleBar 初次绘制无样式
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 创建 Chrome——Owner=Self，InstallChrome 通过 Owner 找到宿主窗体
  FChrome := TTyFormChrome.Create(Self);
  FChrome.TitleHeight  := 34;
  FChrome.ShowMinimize := True;
  FChrome.ShowMaximize := True;

  // ── 客户区内容（在 Active 之前创建，位置相对于整个窗体客户区）──
  FChrome.TitleBar.Caption := '自绘窗框示例  · TyControls';

  InfoLbl := TTyLabel.Create(Self);
  InfoLbl.Parent := Self;
  // 注意：TitleBar 高度 34px；正文从 34+16=50 开始
  InfoLbl.SetBounds(24, 50, 400, 20);
  InfoLbl.Caption := '拖动标题栏移动窗口；从边缘拖动可调整大小；双击标题栏最大化。';

  BtnHello := TTyButton.Create(Self);
  BtnHello.Parent := Self;
  BtnHello.SetBounds(24, 82, 140, 32);
  BtnHello.Caption := '点我打招呼';
  BtnHello.StyleClass := 'primary';
  BtnHello.OnClick := @BtnHelloClick;

  FCountLabel := TTyLabel.Create(Self);
  FCountLabel.Parent := Self;
  FCountLabel.SetBounds(176, 90, 260, 20);
  FCountLabel.Caption := '点击次数：0';

  // ── 激活 Chrome ───────────────────────────────────────────
  // SetActive(True) → InstallChrome → HostForm（Owner）→ 设置 bsNone
  // 并将 TitleBar 挂为 alTop 子控件。
  // 必须在构造函数末尾调用（其他子控件已创建之后），
  // 以确保 TitleBar.Align=alTop 推动正文控件正确布局。
  FChrome.Active := True;
end;

procedure TMainForm.BtnHelloClick(Sender: TObject);
begin
  Inc(FClickCount);
  FCountLabel.Caption := Format('点击次数：%d', [FClickCount]);
end;

end.
