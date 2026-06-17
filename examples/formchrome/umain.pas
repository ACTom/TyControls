unit umain;

{ TTyForm 无边框自绘窗框示例（纯代码方式）：
    1. 窗体直接继承 TTyForm —— 构造时即为无边框，但默认是空的（无标题栏）。
    2. 代码创建一条 TTyTitleBar（Owner=窗体）即自动关联到 TTyForm.TitleBar
       （Form.Menu→TMainMenu 同款机制），引擎随之接上拖拽/最大化。
    3. 内容控件直接放在窗体上、标题栏下方即可。
    4. 加载主题后调用 ApplyChromeTheme(TyDefaultController) 给整套窗框
       上色，并从 TyForm 令牌同步窗体背景色。

  已知缺口（见 docs/KNOWN_GAPS.md）：
    - 无原生 Aero Snap / 磁贴吸附支持
    - 无系统阴影（bsNone 后 GTK/Win32 不绘制投影）
    - 最大化基于 Screen.Monitor.WorkareaRect，不支持多显示器动态变化
  纯代码 UI（无 .lfm）。}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
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
  Bar: TTyTitleBar;
  BtnHello: TTyButton;
  InfoLbl: TTyLabel;
begin
  // TTyForm.CreateNew → 无边框 + 持久引擎，但默认无标题栏
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyForm 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 480, 320);

  // 主题须先加载，再给整套窗框上色（含 TitleBar 初次绘制有样式）
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 创建一条标题栏，Owner=Self 即自动关联到本窗体的 TitleBar 属性，引擎随之接上
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := '自绘窗框示例  · TyControls';

  // ── 客户区内容：直接放窗体上、标题栏下方 ──
  InfoLbl := TTyLabel.Create(Self);
  InfoLbl.Parent := Self;
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

  // 整套窗框 + 背景色随主题（从 TyForm 令牌同步）
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.BtnHelloClick(Sender: TObject);
begin
  Inc(FClickCount);
  FCountLabel.Caption := Format('点击次数：%d', [FClickCount]);
end;

end.
