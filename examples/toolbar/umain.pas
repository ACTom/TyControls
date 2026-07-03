unit umain;

{ TTyToolBar + TTyToolSeparator 示例:
  - alTop 顶部工具条,内含多个 TTyButton 工具按钮(工具条会把 Flat 按钮统一改成 ghost 变体)
  - TTyToolSeparator 在按钮组之间插入分隔竖线
  - ButtonHeight / ButtonSpacing / Indent 控制按钮尺寸与排布
  - Flat(平面/ghost) · Wrapable(超宽自动换行,行数变化时工具条自动增高)
  - 每个工具按钮的 OnClick 汇报到底部 TTyLabel 状态标签
  纯代码创建 UI(无 .lfm),主体为 TTyForm + TTyTitleBar,主题经全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.ToolBar, tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FStatus: TTyLabel;
    procedure ToolClicked(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ 从 exe 所在目录向上查找仓库的 themes/ 目录(兼容 lib/<cpu>-<os>/ 与 .app 包) }
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

  { 往工具条添加一个工具按钮。Parent=工具条 -> 由工具条负责排布与 ghost 变体。 }
  function AddTool(ABar: TTyToolBar; const ACaption: string; AWidth: Integer): TTyButton;
  begin
    Result := TTyButton.Create(Self);
    Result.Parent := ABar;
    Result.Width := AWidth;   { 高度由工具条 ButtonHeight 统一接管 }
    Result.Caption := ACaption;
    Result.OnClick := @ToolClicked;
  end;

var
  Bar: TTyTitleBar;
  ToolBar: TTyToolBar;
  Sep: TTyToolSeparator;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm:无边框 + 常驻引擎
  Caption := 'TTyToolBar 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 560, 320);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // 先加载主题

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyToolBar  · TyControls';

  // 顶部工具条:alTop 紧贴标题栏下方,工具条会随行数自动增高。
  ToolBar := TTyToolBar.Create(Self);
  ToolBar.Parent := Self;
  ToolBar.Align := alTop;          // 默认即 alTop,这里显式声明
  ToolBar.Top := 34;               // 位于标题栏之下
  ToolBar.Flat := True;            // 平面工具按钮(子按钮被统一改成 ghost 变体)
  ToolBar.Wrapable := True;        // 宽度不足时自动换行,行数增加则工具条增高
  ToolBar.ButtonHeight := 28;      // 统一按钮高度
  ToolBar.ButtonSpacing := 4;      // 相邻按钮间距
  ToolBar.Indent := 6;             // 首按钮/顶边留白

  // 第一组:文件操作
  AddTool(ToolBar, '新建', 72);
  AddTool(ToolBar, '打开', 72);
  AddTool(ToolBar, '保存', 72);

  // 分隔线:在两组之间插入一条竖线(Parent=工具条,参与排布)
  Sep := TTyToolSeparator.Create(Self);
  Sep.Parent := ToolBar;

  // 第二组:编辑操作
  AddTool(ToolBar, '剪切', 72);
  AddTool(ToolBar, '复制', 72);
  AddTool(ToolBar, '粘贴', 72);

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 120, 512, 24);
  FStatus.Caption := '就绪:点击任一工具按钮';

  ApplyChromeTheme(TyDefaultController);   // 最后统一主题化窗体外壳与背景
end;

procedure TMainForm.ToolClicked(Sender: TObject);
begin
  FStatus.Caption := Format('已触发工具:%s', [(Sender as TTyButton).Caption]);
end;

end.
