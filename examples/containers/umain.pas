unit umain;

{ Phase-5 容器 & 布局示例。所有控件都在设计器里(umain.lfm)摆放,运行时由 TTyForm 流式加载;
  代码只做「结构装配」——那些无法用 .lfm 属性表达的部分:网格单元格(SetCell)、相对布局规则
  (SetRules)、列头分节(AddSection)、分组列表(AddGroup/AddItem)、Rebar 带宽(SetBandWidth)、
  多选组的初始勾选、以及主题加载。主题走全局 TyDefaultController。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Forms, Controls, BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Controller, tyControls.Form, tyControls.Types, tyControls.Painter,
  tyControls.ColorMath, tyControls.TyLabel, tyControls.Bevel, tyControls.Divider,
  tyControls.PaintPanel, tyControls.SizeBox,
  tyControls.RadioGroup, tyControls.CheckGroup, tyControls.ToolGroupPanel,
  tyControls.ScrollBox, tyControls.ExPanel, tyControls.Button, tyControls.CheckBox,
  tyControls.GridPanel, tyControls.RelativePanel, tyControls.Edit,
  tyControls.ToolBarEx, tyControls.ControlBar, tyControls.CoolBar, tyControls.Panel,
  tyControls.HeaderControl, tyControls.ListGroupPanel;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;
    DivLeft: TTyDivider;
    DivCenter: TTyDivider;
    DivRight: TTyDivider;
    DivBevel: TTyDivider;
    LblBox: TTyLabel;
    BevelBox: TTyBevel;
    BevelFrameLo: TTyBevel;
    BevelFrameHi: TTyBevel;
    LblLines: TTyLabel;
    BevelTopLine: TTyBevel;
    BevelBottomLine: TTyBevel;
    DivPaint: TTyDivider;
    PaintSurface1: TTyPaintPanel;
    DivGroups: TTyDivider;
    RadioSize: TTyRadioGroup;
    CheckFeatures: TTyCheckGroup;
    ToolClip: TTyToolGroupPanel;
    BtnCut: TTyButton;
    BtnCopy: TTyButton;
    BtnPaste: TTyButton;
    BtnFormat: TTyButton;
    DivScroll: TTyDivider;
    ExAdvanced: TTyExPanel;
    ChkWrap: TTyCheckBox;
    ChkMinimap: TTyCheckBox;
    ChkWhitespace: TTyCheckBox;
    ScrollDemo: TTyScrollBox;
    SbBtn1: TTyButton;
    SbBtn2: TTyButton;
    SbBtn3: TTyButton;
    SbBtn4: TTyButton;
    SbBtn5: TTyButton;
    SbBtn6: TTyButton;
    SbBtn7: TTyButton;
    SbBtn8: TTyButton;
    SbBtn9: TTyButton;
    SbBtn10: TTyButton;
    DivLayout: TTyDivider;
    GridForm: TTyGridPanel;
    LblUser: TTyLabel;
    LblMail: TTyLabel;
    LblPhone: TTyLabel;
    EditUser: TTyEdit;
    EditMail: TTyEdit;
    EditPhone: TTyEdit;
    RelForm: TTyRelativePanel;
    BtnTitle: TTyButton;
    BtnCancel: TTyButton;
    BtnOK: TTyButton;
    ListGroups: TTyListGroupPanel;
    HeaderCols: TTyHeaderControl;
    LblHeader: TTyLabel;
    DivBands: TTyDivider;
    BarTools: TTyToolBarEx;
    BarBtn1: TTyButton;
    BarBtn2: TTyButton;
    BarBtn3: TTyButton;
    BarBtn4: TTyButton;
    BarBtn5: TTyButton;
    BarBtn6: TTyButton;
    BarBtn7: TTyButton;
    BarBtn8: TTyButton;
    BarBtn9: TTyButton;
    BarBtn10: TTyButton;
    BarBtn11: TTyButton;
    BarBtn12: TTyButton;
    Rebar: TTyCoolBar;
    Band1: TTyPanel;
    Band2: TTyPanel;
    LblGrip: TTyLabel;
    Grip: TTySizeBox;
    procedure FormCreate(Sender: TObject);
    procedure PaintSurface(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
  private
    procedure WireGrid;
    procedure WireRelative;
    procedure WireBands;
    procedure WireLists;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

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

procedure TMainForm.FormCreate(Sender: TObject);
begin
  // 全局默认控制器:加载主题后所有 Controller=nil 的控件都用它(ActiveController 回退)。
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 多选组的初始勾选(Items 已由 .lfm 流入,FormCreate 时子控件已建好)。
  CheckFeatures.Checked[0] := True;   // 自动保存
  CheckFeatures.Checked[2] := True;   // 深色模式

  WireGrid;       // 网格单元格 + 轨道尺寸
  WireRelative;   // 相对布局规则
  WireLists;      // 列头分节 + 分组列表
  WireBands;      // Rebar 带宽

  // 滚动视口:内容子控件在 .lfm 流入(晚于 Width/Height 触发的 Resize),这里重新量程一次。
  ScrollDemo.UpdateScrollRange;

  // 应用窗口 chrome 主题(标题栏 + 窗口圆角/阴影),与用代码构造时等价。
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.WireGrid;
begin
  // 左列固定 56px 放标签,右列 star 放输入框;3 行。
  GridForm.SetColumnStyle(0, tgtAbsolute, 56);
  GridForm.SetColumnStyle(1, tgtStar);
  GridForm.SetCell(LblUser, 0, 0);   GridForm.SetCell(EditUser, 1, 0);
  GridForm.SetCell(LblMail, 0, 1);   GridForm.SetCell(EditMail, 1, 1);
  GridForm.SetCell(LblPhone, 0, 2);  GridForm.SetCell(EditPhone, 1, 2);
end;

procedure TMainForm.WireRelative;
begin
  // 标题居中贴顶;取消贴右下;确定在取消左侧、与其底对齐。
  RelForm.SetRules(BtnTitle, [traCenterHorizontal, traAlignParentTop]);
  RelForm.SetRules(BtnCancel, [traAlignParentRight, traAlignParentBottom]);
  RelForm.SetRules(BtnOK, [trLeftOf, traAlignBottomOf], BtnCancel);
  RelForm.PerformLayout;
end;

procedure TMainForm.WireLists;
var g: Integer;
begin
  // 列头条:点标题切换排序,拖分节边界调宽。
  HeaderCols.AddSection('名称', 96);
  HeaderCols.AddSection('大小', 60);
  HeaderCols.AddSection('修改日期', 64);

  // Outlook 式分组可折叠列表(手风琴)。
  g := ListGroups.AddGroup('联系人');
  ListGroups.AddItem(g, 'Alice');
  ListGroups.AddItem(g, 'Bob');
  ListGroups.AddItem(g, 'Carol');
  ListGroups.Expanded[g] := True;
  g := ListGroups.AddGroup('任务');
  ListGroups.AddItem(g, '写报告');
  ListGroups.AddItem(g, '发布版本');
end;

procedure TMainForm.WireBands;
begin
  // Rebar:两条可拖抓手调宽的 band(带宽/最小宽是代码级,非 .lfm 属性)。
  Rebar.SetBandWidth(Band1, 220);   Rebar.SetBandMinWidth(Band1, 90);
  Rebar.SetBandWidth(Band2, 260);   Rebar.SetBandMinWidth(Band2, 90);
end;

procedure TMainForm.PaintSurface(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
var ctx: TBGRACanvas2D;
begin
  // 用库绘制器直接画到面板表面,与面板同遍合成(owner-draw)。
  ctx := APainter.Bitmap.Canvas2D;
  ctx.fillStyle(BGRA(59, 130, 246));
  ctx.fillRect(AContent.Left + 14, AContent.Top + 14, 44, 44);
  ctx.fillStyle(BGRA(16, 185, 129));
  ctx.beginPath;
  ctx.arc(AContent.Left + 96, AContent.Top + 36, 22, 0, 2 * Pi, False);
  ctx.fill;
  APainter.DrawText(AContent, 'OnPaintSurface — 应用用 TTyPainter 自绘', 'Segoe UI', 12, 500,
    TyColorFromLCL(clWhite, 255), taCenter, tlBottom, True);
end;

end.
