unit umain;

{ Phase-5 容器 & 布局示例。随各控件建成逐步扩充;当前展示 Batch 1 的装饰/绘制叶子:
  TTyBevel(3D 线条/边框)、TTyDivider(带标题分割线)、TTyPaintPanel(自绘表面)、
  TTySizeBox(右下角尺寸手柄)。纯代码创建,主题走全局 TyDefaultController。 }

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
  private
    FSurface: TTyPaintPanel;
    procedure PaintSurface(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
    procedure BuildUI;
    procedure BuildGroups(AX, AY: Integer);
    procedure BuildScroll(AX, AY: Integer);
    procedure BuildLayout(AX, AY: Integer);
    procedure BuildBands(AY: Integer);
    procedure BuildHeaderGroup(AY: Integer);
    function Divider(const ACap: string; AAlign: TAlignment; AY: Integer): TTyDivider;
    function Bevel(AShape: TTyBevelShape; AStyle: TTyBevelStyle; AL, AT, AW, AH: Integer): TTyBevel;
    function Lbl(const AText: string; AL, AT: Integer): TTyLabel;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

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
var Bar: TTyTitleBar;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TyControls — 容器与布局(Phase 5)';
  Position := poScreenCenter;
  SetBounds(0, 0, 1180, 800);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := '容器与布局  · TyControls';

  BuildUI;
  ApplyChromeTheme(TyDefaultController);
end;

function TMainForm.Lbl(const AText: string; AL, AT: Integer): TTyLabel;
begin
  Result := TTyLabel.Create(Self);
  Result.Parent := Self;
  Result.Caption := AText;
  Result.SetBounds(AL, AT, 260, 18);
end;

function TMainForm.Divider(const ACap: string; AAlign: TAlignment; AY: Integer): TTyDivider;
begin
  Result := TTyDivider.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACap;
  Result.Alignment := AAlign;
  Result.SetBounds(20, AY, 580, 24);
end;

function TMainForm.Bevel(AShape: TTyBevelShape; AStyle: TTyBevelStyle;
  AL, AT, AW, AH: Integer): TTyBevel;
begin
  Result := TTyBevel.Create(Self);
  Result.Parent := Self;
  Result.Shape := AShape;
  Result.Style := AStyle;
  Result.SetBounds(AL, AT, AW, AH);
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

procedure TMainForm.BuildGroups(AX, AY: Integer);
var RG: TTyRadioGroup; CG: TTyCheckGroup; TG: TTyToolGroupPanel;
begin
  Divider('分组容器 Radio / Check / ToolGroup', taLeftJustify, AY + 4);

  RG := TTyRadioGroup.Create(Self);
  RG.Parent := Self;
  RG.Caption := '尺寸(2 列 · 互斥单选)';
  RG.Columns := 2;
  RG.Items.CommaText := '特小,小,中,大';
  RG.ItemIndex := 1;
  RG.SetBounds(AX, AY + 34, 260, 96);

  CG := TTyCheckGroup.Create(Self);
  CG.Parent := Self;
  CG.Caption := '启用功能(2 列 · 独立多选)';
  CG.Columns := 2;
  CG.Items.CommaText := '自动保存,拼写检查,深色模式,行号,自动缩进,代码折叠';
  CG.Checked[0] := True;
  CG.Checked[2] := True;
  CG.SetBounds(AX, AY + 142, 260, 120);

  TG := TTyToolGroupPanel.Create(Self);
  TG.Parent := Self;
  TG.Caption := '剪贴板(流式工具按钮)';
  TG.SetBounds(AX, AY + 274, 260, 100);
  TG.AddButton('剪切');
  TG.AddButton('复制');
  TG.AddButton('粘贴');
  TG.AddButton('格式刷');   // 放不下时自动换行
end;

procedure TMainForm.BuildHeaderGroup(AY: Integer);
var H: TTyHeaderControl; LGP: TTyListGroupPanel; g: Integer;
begin
  Divider('列头条 TTyHeaderControl / 分组列表 TTyListGroupPanel', taLeftJustify, AY);

  // 列头条:点标题切换排序,拖分节边界调宽。
  H := TTyHeaderControl.Create(Self);
  H.Parent := Self;
  H.SetBounds(20, AY + 28, 540, 26);
  H.AddSection('名称', 220);
  H.AddSection('大小', 120);
  H.AddSection('修改日期', 180);

  // Outlook 式分组可折叠列表(手风琴)。
  LGP := TTyListGroupPanel.Create(Self);
  LGP.Parent := Self;
  LGP.SetBounds(600, AY + 28, 300, 170);
  g := LGP.AddGroup('联系人');
  LGP.AddItem(g, 'Alice');
  LGP.AddItem(g, 'Bob');
  LGP.AddItem(g, 'Carol');
  LGP.Expanded[g] := True;
  g := LGP.AddGroup('任务');
  LGP.AddItem(g, '写报告');
  LGP.AddItem(g, '发布版本');
end;

procedure TMainForm.BuildBands(AY: Integer);
var Bar: TTyToolBarEx; Cool: TTyCoolBar; Band: TTyPanel; B: TTyButton; i: Integer;
begin
  Divider('底部:溢出工具条 TTyToolBarEx / Rebar TTyCoolBar', taLeftJustify, AY);

  // 溢出工具条:12 个命令,窗口放不下时尾部收进右端的 » 浮层。
  Bar := TTyToolBarEx.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alNone;
  Bar.Wrapable := False;
  Bar.SetBounds(20, AY + 28, 560, 32);
  Bar.ButtonHeight := 26;
  for i := 1 to 12 do
  begin
    B := TTyButton.Create(Self);
    B.Parent := Bar;
    B.Width := 74;
    B.Caption := Format('命令 %d', [i]);
  end;

  // Rebar:两条可拖拽/抓手调宽的 band。
  Cool := TTyCoolBar.Create(Self);
  Cool.Parent := Self;
  Cool.SetBounds(600, AY + 28, 540, 68);
  Cool.GripperWidth := 10;
  for i := 0 to 1 do
  begin
    Band := TTyPanel.Create(Self);
    Band.Parent := Cool;
    Band.Caption := Format('带 %d(拖抓手改宽)', [i + 1]);
    Cool.SetBandWidth(Band, 220 + i * 40);
    Cool.SetBandMinWidth(Band, 90);
  end;
end;

procedure TMainForm.BuildLayout(AX, AY: Integer);
var Grid: TTyGridPanel; RP: TTyRelativePanel; i: Integer; L: TTyLabel; E: TTyEdit;
    Title, BtnOK, BtnCancel: TTyButton;
const Fields: array[0..2] of string = ('用户名', '邮箱', '电话');
begin
  Divider('网格 / 相对布局', taLeftJustify, AY + 4);

  // 网格布局:左列固定 60px 放标签,右列 star 放输入框;3 行 star。
  Grid := TTyGridPanel.Create(Self);
  Grid.Parent := Self;
  Grid.SetBounds(AX, AY + 34, 220, 120);
  Grid.Spacing := 6;
  Grid.ColumnCount := 2;
  Grid.RowCount := 3;
  Grid.SetColumnStyle(0, tgtAbsolute, 56);
  Grid.SetColumnStyle(1, tgtStar);
  for i := 0 to 2 do
  begin
    L := TTyLabel.Create(Grid); L.Parent := Grid; L.Caption := Fields[i];
    Grid.SetCell(L, 0, i);
    E := TTyEdit.Create(Grid); E.Parent := Grid;
    Grid.SetCell(E, 1, i);
  end;

  // 相对布局:标题居中贴顶;取消贴右下;确定在取消左侧、与其顶对齐。
  RP := TTyRelativePanel.Create(Self);
  RP.Parent := Self;
  RP.SetBounds(AX, AY + 166, 220, 100);
  Title := TTyButton.Create(RP); Title.Parent := RP; Title.SetBounds(0, 0, 100, 26);
  Title.Caption := '标题'; RP.SetRules(Title, [traCenterHorizontal, traAlignParentTop]);
  BtnCancel := TTyButton.Create(RP); BtnCancel.Parent := RP; BtnCancel.SetBounds(0, 0, 80, 28);
  BtnCancel.Caption := '取消'; RP.SetRules(BtnCancel, [traAlignParentRight, traAlignParentBottom]);
  BtnOK := TTyButton.Create(RP); BtnOK.Parent := RP; BtnOK.SetBounds(0, 0, 80, 28);
  BtnOK.Caption := '确定'; RP.SetRules(BtnOK, [trLeftOf, traAlignBottomOf], BtnCancel);
  RP.PerformLayout;
end;

procedure TMainForm.BuildScroll(AX, AY: Integer);
var EP: TTyExPanel; Box: TTyScrollBox; Chk: TTyCheckBox; Btn: TTyButton; i: Integer;
begin
  Divider('滚动 / 折叠容器', taLeftJustify, AY + 4);

  // 可折叠面板:点标题栏折叠/展开,body 承载真实子控件。
  EP := TTyExPanel.Create(Self);
  EP.Parent := Self;
  EP.Caption := '高级选项(点标题折叠)';
  EP.SetBounds(AX, AY + 34, 210, 120);
  for i := 0 to 2 do
  begin
    Chk := TTyCheckBox.Create(EP);
    Chk.Parent := EP;
    Chk.SetBounds(12, 10 + i * 26, 180, 22);
    Chk.Caption := Format('选项 %d', [i + 1]);
  end;

  // 滚动视口:内容(10 个按钮)比视口高 → 右侧自动出现垂直滚动条。
  Box := TTyScrollBox.Create(Self);
  Box.Parent := Self;
  Box.SetBounds(AX, AY + 166, 210, 208);
  for i := 0 to 9 do
  begin
    Btn := TTyButton.Create(Box);
    Btn.Parent := Box;
    Btn.SetBounds(10, 10 + i * 40, 160, 30);
    Btn.Caption := Format('第 %d 项', [i + 1]);
  end;
  Box.UpdateScrollRange;
end;

procedure TMainForm.BuildUI;
var grip: TTySizeBox; baseY: Integer;
begin
  baseY := 44;   // below the title bar
  Divider('分割线 TTyDivider(左 / 中 / 右)', taLeftJustify, baseY + 4);
  Divider('居中标题', taCenter, baseY + 32);
  Divider('右对齐', taRightJustify, baseY + 60);

  Divider('装饰 TTyBevel', taLeftJustify, baseY + 96);
  Lbl('Box / Frame(凹 / 凸)', 20, baseY + 122);
  Bevel(tbsBox,   tbsLowered, 20,  baseY + 142, 120, 60);
  Bevel(tbsFrame, tbsLowered, 152, baseY + 142, 120, 60);
  Bevel(tbsFrame, tbsRaised,  284, baseY + 142, 120, 60);
  Lbl('单边线', 430, baseY + 122);
  Bevel(tbsTopLine,    tbsLowered, 430, baseY + 146, 160, 2);
  Bevel(tbsBottomLine, tbsRaised,  430, baseY + 170, 160, 2);

  Divider('自绘表面 TTyPaintPanel', taLeftJustify, baseY + 220);
  FSurface := TTyPaintPanel.Create(Self);
  FSurface.Parent := Self;
  FSurface.SetBounds(20, baseY + 246, 384, 130);
  FSurface.OnPaintSurface := @PaintSurface;

  Lbl('右下角 → 尺寸手柄 TTySizeBox(拖动改窗口大小)', 20, baseY + 386);

  // —— 中栏:Batch 2 分组容器 ——
  BuildGroups(430, baseY);
  // —— 第三列:Batch 3 滚动/折叠容器 ——
  BuildScroll(710, baseY);
  // —— 第四列:Batch 4 布局容器 ——
  BuildLayout(950, baseY);
  // —— 底部整宽:Batch 5 条带/工具栏 ——
  BuildBands(baseY + 456);
  // —— 底部:Batch 6 列头条 / 分组列表 ——
  BuildHeaderGroup(baseY + 560);

  // 右下角尺寸手柄:拖动缩放本窗体(Target 默认取 owner 窗体)。
  grip := TTySizeBox.Create(Self);
  grip.Parent := Self;
  grip.Anchors := [akRight, akBottom];
  grip.SetBounds(ClientWidth - 20, ClientHeight - 20, 16, 16);
end;

end.
