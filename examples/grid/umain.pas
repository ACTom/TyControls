unit umain;

{ TTyStringGrid 示例 —— 自绘数据网格。

  **每一页演示一组特性**,页与页之间互不干扰:

    1. 基础与虚拟化 —— 冻结列/固定行、行号槽、汇总带、百万行、稀疏存储、hover、导航
    2. 外观         —— 斑马纹、格线四态与线宽、逐格持久底色、逐格边框、条件着色钩子、
                        表头自绘钩子、列头图标、换行与自动行高
    3. 排序·筛选·分组 —— 多列排序与顺位徽标、列级排序方式、空值位置、大小写、
                        条件类型化过滤与漏斗激活态、分组与全展开/折叠
    4. 编辑         —— **列级声明**(不接事件)、各种单元格类型、逐格只读、
                        导航跳过只读格、宿主自定义编辑器(EditLink)
    5. 选择·数据·剪贴板 —— 选择模式、离散多选、选区聚合、行的隐藏、批量行操作、
                        合并单元格、剪贴板与智能粘贴、CSV / HTML 导出

  窗口、标题栏、分页与各页控件全部在 umain.lfm 里设计;本文件只放数据与事件。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Columns, tyControls.Grid, tyControls.TyLabel, tyControls.ComboBox,
  tyControls.ToggleSwitch, tyControls.Button, tyControls.Edit, tyControls.Panel,
  tyControls.CheckBox, tyControls.SpinEdit, tyControls.PageControl,
  tyControls.TabSheet, tyControls.Painter,
  tyControls.Types, tyControls.ColorMath, tyControls.Dialogs.Color;

type
  { 宿主自带编辑器的最小实现:用一个多行 TTyMemo 编辑「备注」。
    存在的意义是证明扩展点通了 —— 网格答不上来的编辑需求,宿主自己接。 }
  TNoteEditLink = class(TTyGridEditLink)
  private
    FCtl: TTyEdit;
  public
    function  CreateEditor(AParent: TWinControl; ACol, ARow: Integer): TWinControl; override;
    procedure SetBounds(const ARect: TRect); override;
    function  GetValue: string; override;
    procedure SetValue(const AValue: string); override;
    procedure FocusEditor; override;
    procedure ReleaseEditor; override;
  end;

  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    Surface: TTyFormSurface;
    Pages: TTyPageControl;
    LblStatus: TTyLabel;
    ThemeCombo: TTyComboBox;
    DarkSwitch: TTyToggleSwitch;
    BtnAccent: TTyButton;

    PgBasic: TTyTabSheet;
    LblBasicHint: TTyLabel;
    TbBasic: TTyPanel;
    GridBasic: TTyStringGrid;
    BtnRows1W, BtnRows10W, BtnRows100W, BtnRowsReset, BtnGoto: TTyButton;
    ChkFrozenCols, ChkFixedRow, ChkIndicator, ChkFooter: TTyCheckBox;

    PgLook: TTyTabSheet;
    LblLookHint, LblLines, LblLineW, LblLookTip: TTyLabel;
    TbLook1, TbLook2: TTyPanel;
    GridLook: TTyStringGrid;
    ChkZebra, ChkCondColor, ChkCellBorder, ChkHdrHilite, ChkHdrIcons,
      ChkWordWrap: TTyCheckBox;
    CbLines: TTyComboBox;
    SpLineWidth: TTySpinEdit;
    BtnCellColor, BtnCellUncolor, BtnRowColor, BtnAutoFitRows,
      BtnResetRows: TTyButton;

    PgSort: TTyTabSheet;
    LblSortHint, LblFilterCol: TTyLabel;
    TbSort1, TbSort2: TTyPanel;
    GridSort: TTyStringGrid;
    BtnSortQty, BtnSortQtyD, BtnSortAdd, BtnSortClear, BtnFilterClear,
      BtnGroup, BtnExpandAll, BtnCollapseAll: TTyButton;
    ChkBlanksFirst, ChkCaseSens: TTyCheckBox;
    CbFilterCol, CbFilterOp: TTyComboBox;
    EdFilterVal: TTyEdit;

    PgEdit: TTyTabSheet;
    LblEditHint, LblEditTip: TTyLabel;
    TbEdit: TTyPanel;
    GridEdit: TTyStringGrid;
    ChkSkipRO, ChkEditLink: TTyCheckBox;
    BtnCellRO, BtnCellRW: TTyButton;

    PgData: TTyTabSheet;
    LblDataHint, LblSelMode, LblDataTip: TTyLabel;
    TbData1, TbData2: TTyPanel;
    GridData: TTyStringGrid;
    CbSelMode: TTyComboBox;
    BtnSelAll, BtnSelNone, BtnMerge, BtnUnmerge, BtnCopy, BtnCut, BtnPaste,
      BtnInsRow, BtnDelRow, BtnRowUp, BtnRowDown, BtnHideRow, BtnUnhideAll,
      BtnExportCsv, BtnExportHtml: TTyButton;
    ChkAutoGrow: TTyCheckBox;

    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure BtnAccentClick(Sender: TObject);
    procedure AnyGridSelectionChanged(Sender: TObject);

    { 页 1 }
    procedure BtnRows1WClick(Sender: TObject);
    procedure BtnRows10WClick(Sender: TObject);
    procedure BtnRows100WClick(Sender: TObject);
    procedure BtnRowsResetClick(Sender: TObject);
    procedure BtnGotoClick(Sender: TObject);
    procedure ChkBasicChange(Sender: TObject);

    { 页 2 }
    procedure ChkLookChange(Sender: TObject);
    procedure CbLinesChange(Sender: TObject);
    procedure SpLineWidthChange(Sender: TObject);
    procedure BtnCellColorClick(Sender: TObject);
    procedure BtnCellUncolorClick(Sender: TObject);
    procedure BtnRowColorClick(Sender: TObject);
    procedure BtnAutoFitRowsClick(Sender: TObject);
    procedure BtnResetRowsClick(Sender: TObject);
    procedure LookGetCellStyle(Sender: TObject; ACol, ARow: Integer;
      var ABackground: TTyFill; var ATextColor: TTyColor;
      var AFontName: string; var AFontSize, AFontWeight: Integer;
      var AHAlign: TAlignment; var AVAlign: TTextLayout);
    procedure LookGetCellBorder(Sender: TObject; ACol, ARow: Integer;
      var ABorders: TTyGridCellBorders);
    procedure LookGetHeaderStyle(Sender: TObject; ACol: Integer;
      var ABackground: TTyFill; var ATextColor: TTyColor;
      var AFontName: string; var AFontSize, AFontWeight: Integer);
    procedure LookGetCellWordWrap(Sender: TObject; ACol, ARow: Integer;
      var AWordWrap: Boolean);

    { 页 3 }
    procedure BtnSortQtyClick(Sender: TObject);
    procedure BtnSortQtyDClick(Sender: TObject);
    procedure BtnSortAddClick(Sender: TObject);
    procedure BtnSortClearClick(Sender: TObject);
    procedure ChkSortChange(Sender: TObject);
    procedure CbFilterChange(Sender: TObject);
    procedure BtnFilterClearClick(Sender: TObject);
    procedure BtnGroupClick(Sender: TObject);
    procedure BtnExpandAllClick(Sender: TObject);
    procedure BtnCollapseAllClick(Sender: TObject);

    { 页 4 }
    procedure ChkEditChange(Sender: TObject);
    procedure BtnCellROClick(Sender: TObject);
    procedure BtnCellRWClick(Sender: TObject);
    procedure EditGetCellDisplay(Sender: TObject; ACol, ARow: Integer;
      var ADisplay: TTyGridCellDisplay);
    procedure EditCellButtonClick(Sender: TObject; ACol, ARow: Integer);
    procedure EditCreateEditLink(Sender: TObject; ACol, ARow: Integer;
      var ALink: TTyGridEditLink);

    { 页 5 }
    procedure CbSelModeChange(Sender: TObject);
    procedure BtnSelAllClick(Sender: TObject);
    procedure BtnSelNoneClick(Sender: TObject);
    procedure BtnMergeClick(Sender: TObject);
    procedure BtnUnmergeClick(Sender: TObject);
    procedure BtnCopyClick(Sender: TObject);
    procedure BtnCutClick(Sender: TObject);
    procedure BtnPasteClick(Sender: TObject);
    procedure BtnInsRowClick(Sender: TObject);
    procedure BtnDelRowClick(Sender: TObject);
    procedure BtnRowUpClick(Sender: TObject);
    procedure BtnRowDownClick(Sender: TObject);
    procedure BtnHideRowClick(Sender: TObject);
    procedure BtnUnhideAllClick(Sender: TObject);
    procedure BtnExportCsvClick(Sender: TObject);
    procedure BtnExportHtmlClick(Sender: TObject);
    procedure ChkDataChange(Sender: TObject);
  private
    FNoteLink: TNoteEditLink;
    procedure BuildOrderColumns(AGrid: TTyStringGrid; AWithNote: Boolean);
    procedure FillOrders(AGrid: TTyStringGrid; ACount: Integer; AWithNote: Boolean);
    procedure SetupBasic;
    procedure SetupLook;
    procedure SetupSort;
    procedure SetupEdit;
    procedure SetupData;
    function  ActiveGrid: TTyStringGrid;
    procedure Status(const AText: string);
    procedure ShowSelectionInfo;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

uses
  Math, Clipbrd;

const
  cRegions: array[0..5] of string =
    ('华东', '华北', '华南', '西南', '东北', '西北');
  cProducts: array[0..4] of string =
    ('云主机', '对象存储', '数据库', 'CDN', '负载均衡');
  cMarkColors: array[0..3] of string =
    ('#3B82F6', '#22C55E', '#F59E0B', '#EF4444');
  cNotes: array[0..3] of string =
    ('客户要求分批发货,第一批本周内到仓,余下的等下月排产;联系人已换成王工。',
     '合同附件缺少盖章页,已退回补件。',
     '这条走加急通道,物流费由我方承担;需要在发票备注里注明加急原因。',
     '');

  { 列索引 —— 用常量而不是散落的魔数,否则加一列就要满文件找 3、4、7。 }
  cOrderNo = 0; cRegion = 1; cProduct = 2; cQty = 3; cAmount = 4;
  cDate = 5;    cDone = 6;   cRate = 7;    cMark = 8; cNote = 9;

{ ============ 宿主自定义编辑器 ============ }

function TNoteEditLink.CreateEditor(AParent: TWinControl;
  ACol, ARow: Integer): TWinControl;
begin
  FCtl := TTyEdit.Create(AParent);
  FCtl.Parent := AParent;
  FCtl.Controller := TTyStringGrid(AParent).Controller;
  Result := FCtl;
end;

procedure TNoteEditLink.SetBounds(const ARect: TRect);
begin
  { 故意比单元格宽一些 —— 长备注在窄列里也看得见自己在打什么。 }
  FCtl.BoundsRect := Rect(ARect.Left, ARect.Top,
    Max(ARect.Right, ARect.Left + 320), ARect.Bottom);
end;

function TNoteEditLink.GetValue: string;
begin
  Result := FCtl.Text;
end;

procedure TNoteEditLink.SetValue(const AValue: string);
begin
  FCtl.Text := AValue;
end;

procedure TNoteEditLink.FocusEditor;
begin
  if FCtl.CanFocus then FCtl.SetFocus;
end;

procedure TNoteEditLink.ReleaseEditor;
begin
  FreeAndNil(FCtl);
end;

{ ============ 公共:建列与灌数据 ============ }

procedure TMainForm.BuildOrderColumns(AGrid: TTyStringGrid; AWithNote: Boolean);

  function AddCol(const ACaption: string; AWidth: Integer;
    AAlign: TAlignment): TTyGridColumn;
  begin
    Result := AGrid.Header.Columns.Add as TTyGridColumn;
    Result.Text := ACaption;
    Result.Width := AWidth;
    Result.Alignment := AAlign;
  end;

begin
  AGrid.Header.Columns.BeginUpdate;
  try
    AddCol('订单号', 108, taLeftJustify);
    AddCol('大区',    70, taLeftJustify);
    AddCol('产品',   100, taLeftJustify);
    { 数值列必须按**数值**排,否则会排出 '100' < '9'。这是列的属性,不是全表开关。 }
    AddCol('数量',    70, taRightJustify).SortKind := gskNumber;
    AddCol('金额',    96, taRightJustify).SortKind := gskNumber;
    AddCol('日期',    96, taLeftJustify).SortKind := gskDate;
    AddCol('已结算',  70, taCenter);
    AddCol('评分',    86, taLeftJustify);
    AddCol('标记色',  76, taCenter);
    if AWithNote then AddCol('备注', 300, taLeftJustify);
  finally
    AGrid.Header.Columns.EndUpdate;
  end;
end;

procedure TMainForm.FillOrders(AGrid: TTyStringGrid; ACount: Integer;
  AWithNote: Boolean);
var
  r, qty: Integer;
  amount: Double;
begin
  AGrid.RowCount := ACount;
  for r := 0 to ACount - 1 do
  begin
    qty := 1 + (r * 7) mod 40;
    { 每 9 行来一笔负数金额 —— 页 2 的条件着色要靠它才看得出效果。 }
    amount := qty * 128.5;
    if r mod 9 = 4 then amount := -amount;

    AGrid.Cells[cOrderNo, r] := Format('SO-2026%04d', [r + 1]);
    AGrid.Cells[cRegion,  r] := cRegions[r mod Length(cRegions)];
    AGrid.Cells[cProduct, r] := cProducts[r mod Length(cProducts)];
    AGrid.Cells[cQty,     r] := IntToStr(qty);
    AGrid.Cells[cAmount,  r] := Format('%.2f', [amount]);
    { 每 11 行留一个空日期 —— 页 3 的"空值排最前/最后"要靠它。 }
    if r mod 11 <> 3 then
      AGrid.Cells[cDate, r] := FormatDateTime('yyyy-mm-dd',
        EncodeDate(2026, 1 + r mod 12, 1 + r mod 28));
    if r mod 3 = 0 then AGrid.Cells[cDone, r] := '1';
    AGrid.Cells[cRate, r] := IntToStr(1 + r mod 5);
    AGrid.Cells[cMark, r] := cMarkColors[r mod Length(cMarkColors)];
    if AWithNote then AGrid.Cells[cNote, r] := cNotes[r mod Length(cNotes)];
  end;
end;

{ ============ 窗体 ============ }

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);

  FNoteLink := TNoteEditLink.Create;

  SetupBasic;
  SetupLook;
  SetupSort;
  SetupEdit;
  SetupData;

  Status('每一页演示一组特性 —— 从左到右依次看下来即可');
end;

function TMainForm.ActiveGrid: TTyStringGrid;
begin
  case Pages.ActivePageIndex of
    1: Result := GridLook;
    2: Result := GridSort;
    3: Result := GridEdit;
    4: Result := GridData;
  else Result := GridBasic;
  end;
end;

procedure TMainForm.Status(const AText: string);
begin
  LblStatus.Caption := AText;
end;

{ 选区聚合就是给状态栏这句话准备的。挂在**每个**网格的 OnSelectionChanged 上 ——
  从前这行信息只在少数几个按钮里刷新,一点单元格就被别的文案覆盖掉,等于没有。 }
procedure TMainForm.ShowSelectionInfo;
var
  G: TTyStringGrid;
begin
  G := ActiveGrid;
  if G.SelectedCellCount > 1 then
    Status(Format('当前 (列 %d, 行 %d)  ·  共 %d 行 / 显示 %d 行 / 已存 %d 格'
      + '  ·  已选 %d 格,合计 %.2f,平均 %.2f',
      [G.Col, G.Row, G.RowCount, G.DisplayRowCount, G.StoredCellCount,
       G.SelectedCellCount, G.SelectionSum, G.SelectionAvg]))
  else
    Status(Format('当前 (列 %d, 行 %d) = %s  ·  共 %d 行 / 显示 %d 行 / 已存 %d 格',
      [G.Col, G.Row, G.Cells[G.Col, G.Row], G.RowCount, G.DisplayRowCount,
       G.StoredCellCount]));
end;

procedure TMainForm.AnyGridSelectionChanged(Sender: TObject);
begin
  ShowSelectionInfo;
end;

{ ============ 页 1:基础与虚拟化 ============ }

procedure TMainForm.SetupBasic;
begin
  BuildOrderColumns(GridBasic, False);
  FillOrders(GridBasic, 200, False);
  GridBasic.SetColumnAggregate(cOrderNo, gagCount);
  GridBasic.SetColumnAggregate(cQty, gagSum);
  GridBasic.SetColumnAggregate(cAmount, gagSum);
end;

procedure TMainForm.BtnRows1WClick(Sender: TObject);
begin
  FillOrders(GridBasic, 10000, False);
  Status('1 万行 —— 只绘制可视窗口内的几十行,滚动一下试试');
end;

procedure TMainForm.BtnRows10WClick(Sender: TObject);
begin
  FillOrders(GridBasic, 100000, False);
  Status('10 万行 —— 已写满内容,注意状态栏的"已存格数"');
end;

{ 一百万行:**只把 RowCount 拉大,不写任何单元格**。
  存储是稀疏的、绘制只走可视窗口,所以既不吃内存也不卡。 }
procedure TMainForm.BtnRows100WClick(Sender: TObject);
begin
  GridBasic.ClearCells;
  GridBasic.RowCount := 1000000;
  GridBasic.MoveCursor(0, 0);
  Status('100 万行,一格没写 —— 看"已存格数"仍是 0,这就是稀疏存储');
end;

procedure TMainForm.BtnRowsResetClick(Sender: TObject);
begin
  GridBasic.ClearCells;
  FillOrders(GridBasic, 200, False);
  GridBasic.MoveCursor(0, 0);
  Status('已恢复 200 行');
end;

{ 跳转:MoveCursor 之后显式 ScrollIntoView。横向滚动会**跳过冻结列**。 }
procedure TMainForm.BtnGotoClick(Sender: TObject);
begin
  if GridBasic.RowCount < 5001 then FillOrders(GridBasic, 10000, False);
  GridBasic.MoveCursor(2, 5000);
  GridBasic.ScrollIntoView(2, 5000);
  Status('已跳到 (列 2, 行 5000)');
end;

procedure TMainForm.ChkBasicChange(Sender: TObject);
begin
  if ChkFrozenCols.Checked then GridBasic.FixedCols := 2
  else GridBasic.FixedCols := 0;
  if ChkFixedRow.Checked then GridBasic.FixedRows := 1
  else GridBasic.FixedRows := 0;
  GridBasic.ShowIndicator := ChkIndicator.Checked;
  GridBasic.ShowFooter := ChkFooter.Checked;
end;

{ ============ 页 2:外观 ============ }

procedure TMainForm.SetupLook;
begin
  BuildOrderColumns(GridLook, True);
  FillOrders(GridLook, 60, True);
  GridLook.OnGetCellWordWrap := @LookGetCellWordWrap;
end;

procedure TMainForm.ChkLookChange(Sender: TObject);
begin
  GridLook.AlternateRows := ChkZebra.Checked;
  GridLook.WordWrap := ChkWordWrap.Checked;

  { 钩子按需挂/摘 —— 没挂时整个逐格遍历直接跳过,是零成本的。 }
  if ChkCondColor.Checked then GridLook.OnGetCellStyle := @LookGetCellStyle
  else GridLook.OnGetCellStyle := nil;

  if ChkCellBorder.Checked then GridLook.OnGetCellBorder := @LookGetCellBorder
  else GridLook.OnGetCellBorder := nil;

  if ChkHdrHilite.Checked then GridLook.OnGetHeaderStyle := @LookGetHeaderStyle
  else GridLook.OnGetHeaderStyle := nil;

  if ChkHdrIcons.Checked then
    TTyColumn(GridLook.Header.Columns.Items[cAmount]).ImageIndex := 0
  else
    TTyColumn(GridLook.Header.Columns.Items[cAmount]).ImageIndex := -1;

  GridLook.Invalidate;
end;

procedure TMainForm.CbLinesChange(Sender: TObject);
begin
  case CbLines.ItemIndex of
    0: GridLook.GridLineStyle := glsNone;
    1: GridLook.GridLineStyle := glsHorizontal;
    2: GridLook.GridLineStyle := glsVertical;
  else GridLook.GridLineStyle := glsBoth;
  end;
end;

{ 线加粗时**列宽不变** —— 线压在边界上、两侧各占一半,只是单元格内容相应内缩。
  盯住某一列的右边缘就能验证这一点。 }
procedure TMainForm.SpLineWidthChange(Sender: TObject);
begin
  GridLook.GridLineWidth := SpLineWidth.Value;
end;

procedure TMainForm.BtnCellColorClick(Sender: TObject);
var
  c: TTyColor;
begin
  c := TyRGB(255, 236, 179);
  if TySelectColor('给这一格选个底色', c) then
  begin
    GridLook.CellColors[GridLook.Col, GridLook.Row] := c;
    Status(Format('(列 %d, 行 %d) 已上色 —— 这是**落盘**的颜色,排序后跟着数据行走',
      [GridLook.Col, GridLook.Row]));
  end;
end;

procedure TMainForm.BtnCellUncolorClick(Sender: TObject);
begin
  GridLook.CellColors[GridLook.Col, GridLook.Row] := 0;
  Status('已清除本格底色');
end;

procedure TMainForm.BtnRowColorClick(Sender: TObject);
begin
  GridLook.SetRowColor(GridLook.Row, TyRGB(209, 250, 229));
  Status(Format('第 %d 行已整行标色', [GridLook.Row]));
end;

procedure TMainForm.BtnAutoFitRowsClick(Sender: TObject);
begin
  if not GridLook.WordWrap then
  begin
    Status('先勾上「换行」再点自动行高 —— 不换行的话每行都只有一行字,没什么可撑的');
    Exit;
  end;
  GridLook.AutoFitRows;
  Status('行高已按换行后的实际高度自适应(受 MinRowHeight / MaxRowHeight 约束)');
end;

procedure TMainForm.BtnResetRowsClick(Sender: TObject);
var
  i: Integer;
begin
  { 赋 <= 0 表示"清掉显式行高、回到默认",不是"行高为 0"。 }
  for i := 0 to GridLook.RowCount - 1 do
    GridLook.RowHeights[i] := 0;
  Status('行高已恢复默认');
end;

{ 条件着色:负数金额标红加粗、空日期那行标黄。
  ARow 是**数据行**,所以排序之后着色仍然跟着同一条记录走。 }
procedure TMainForm.LookGetCellStyle(Sender: TObject; ACol, ARow: Integer;
  var ABackground: TTyFill; var ATextColor: TTyColor;
  var AFontName: string; var AFontSize, AFontWeight: Integer;
  var AHAlign: TAlignment; var AVAlign: TTextLayout);
begin
  if (ACol = cAmount) and (StrToFloatDef(GridLook.Cells[cAmount, ARow], 0) < 0) then
  begin
    ABackground.Kind := tfkSolid;
    ABackground.Color := TyRGB(254, 226, 226);
    ATextColor := TyRGB(185, 28, 28);
    AFontWeight := 700;
  end
  else if GridLook.Cells[cDate, ARow] = '' then
  begin
    ABackground.Kind := tfkSolid;
    ABackground.Color := TyRGB(254, 249, 195);
  end;
end;

{ 逐格边框:每 10 行画一条加粗的分隔上边线,做出"小计行"的观感。
  四支笔各自可开可关,所以这里只开 Top。 }
procedure TMainForm.LookGetCellBorder(Sender: TObject; ACol, ARow: Integer;
  var ABorders: TTyGridCellBorders);
begin
  if (ARow > 0) and (ARow mod 10 = 0) then
  begin
    ABorders.Top := True;
    ABorders.Width := 2;
    ABorders.Color := TyRGB(59, 130, 246);
  end;
end;

{ 表头自绘:当前排序列高亮。点不同列头排序,高亮跟着走。 }
procedure TMainForm.LookGetHeaderStyle(Sender: TObject; ACol: Integer;
  var ABackground: TTyFill; var ATextColor: TTyColor;
  var AFontName: string; var AFontSize, AFontWeight: Integer);
begin
  if ACol = GridLook.Header.SortColumn then
  begin
    ABackground.Kind := tfkSolid;
    ABackground.Color := TyRGB(219, 234, 254);
    AFontWeight := 700;
  end;
end;

{ 只让「备注」列换行,其余列保持单行 + 省略号。 }
procedure TMainForm.LookGetCellWordWrap(Sender: TObject; ACol, ARow: Integer;
  var AWordWrap: Boolean);
begin
  AWordWrap := ChkWordWrap.Checked and (ACol = cNote);
end;

{ ============ 页 3:排序 · 筛选 · 分组 ============ }

procedure TMainForm.SetupSort;
begin
  BuildOrderColumns(GridSort, False);
  FillOrders(GridSort, 120, False);
  GridSort.SetColumnAggregate(cOrderNo, gagCount);
  GridSort.SetColumnAggregate(cAmount, gagSum);
  CbFilterChange(nil);
end;

procedure TMainForm.BtnSortQtyClick(Sender: TObject);
begin
  GridSort.SortByColumn(cQty, sdAscending);
  Status('按「数量」升序 —— 列级 SortKind = gskNumber,所以 9 排在 100 前面');
end;

procedure TMainForm.BtnSortQtyDClick(Sender: TObject);
begin
  GridSort.SortByColumn(cQty, sdDescending);
  Status('按「数量」降序');
end;

{ 追加次级排序列:数量相同的行,再按大区排。表头会出现 1 / 2 的顺位徽标。 }
procedure TMainForm.BtnSortAddClick(Sender: TObject);
begin
  if GridSort.SortColumnCount = 0 then GridSort.SortByColumn(cQty, sdAscending);
  GridSort.AddSortColumn(cRegion, sdAscending);
  Status(Format('已追加次级排序列 —— 现在有 %d 个排序键,表头显示顺位徽标',
    [GridSort.SortColumnCount]));
end;

procedure TMainForm.BtnSortClearClick(Sender: TObject);
begin
  GridSort.ClearSortColumns;
  Status('已取消排序 —— 行序弹回原始导入顺序');
end;

procedure TMainForm.ChkSortChange(Sender: TObject);
begin
  if ChkBlanksFirst.Checked then GridSort.BlanksPosition := gbpFirst
  else GridSort.BlanksPosition := gbpLast;
  GridSort.SortIgnoreCase := not ChkCaseSens.Checked;
  { 重排一次让改动立刻可见。 }
  if GridSort.SortColumn >= 0 then
    GridSort.SortByColumn(GridSort.SortColumn, sdAscending);
  Status('空值位置与升降序**无关** —— 翻向排序,空日期那几行仍停在同一端');
end;

procedure TMainForm.CbFilterChange(Sender: TObject);
var
  op: TTyGridFilterOp;
begin
  case CbFilterOp.ItemIndex of
    1: op := gfoEquals;
    2: op := gfoNotEquals;
    3: op := gfoStartsWith;
    4: op := gfoEndsWith;
    5: op := gfoGreater;
    6: op := gfoGreaterEqual;
    7: op := gfoLess;
    8: op := gfoLessEqual;
  else op := gfoContains;
  end;
  GridSort.ClearFilters;
  GridSort.SetColumnFilterEx(CbFilterCol.ItemIndex, op, EdFilterVal.Text);
  Status(Format('筛选后 %d 行 / 共 %d 行 —— 该列的漏斗已点亮',
    [GridSort.FilteredRowCount, GridSort.RowCount]));
end;

procedure TMainForm.BtnFilterClearClick(Sender: TObject);
begin
  GridSort.ClearFilters;
  EdFilterVal.Text := '';
  Status('已清除筛选 —— 漏斗灭掉');
end;

procedure TMainForm.BtnGroupClick(Sender: TObject);
begin
  if GridSort.GroupColumn >= 0 then
  begin
    GridSort.UngroupRows;
    BtnGroup.Caption := '按大区分组';
    Status('已取消分组');
  end
  else
  begin
    GridSort.GroupByColumn(cRegion);
    BtnGroup.Caption := '取消分组';
    Status('已按大区分组 —— 点分组行可折叠;注意排序列没有被分组吃掉');
  end;
end;

procedure TMainForm.BtnExpandAllClick(Sender: TObject);
begin
  GridSort.ExpandAllGroups;
  Status('全部展开');
end;

procedure TMainForm.BtnCollapseAllClick(Sender: TObject);
begin
  GridSort.CollapseAllGroups;
  Status('全部折叠 —— 折叠状态按**分组值**记账,重排后仍然对得上');
end;

{ ============ 页 4:编辑与单元格类型 ============ }

procedure TMainForm.SetupEdit;
var
  c: TTyGridColumn;
begin
  BuildOrderColumns(GridEdit, True);
  FillOrders(GridEdit, 40, True);

  { ---- 全部在**列上**声明,一个事件都没接 ---- }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cOrderNo]);
  c.ReadOnly := True;                       { 主键不给改 }

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cRegion]);
  c.EditorKind := gekPickList;              { 下拉,候选项也挂在列上 }
  c.PickList.CommaText := '华东,华北,华南,西南,东北,西北';

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cQty]);
  c.EditorKind := gekNumeric;
  c.ValidChars := '0123456789';             { 按键级过滤:字母根本敲不进去 }
  c.MaxEditLength := 4;

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cAmount]);
  c.EditorKind := gekNumeric;

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cDate]);
  c.EditorKind := gekDate;                  { 日期选择器 }

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cDone]);
  c.EditorKind := gekCheckBox;              { 点方块直接切换 }

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cMark]);
  c.EditorKind := gekColor;                 { 弹取色对话框 }

  { 「评分」显示成星标、「备注」当按钮列用 —— 显示方式与编辑方式是正交的。 }
  GridEdit.OnGetCellDisplay := @EditGetCellDisplay;
  GridEdit.OnCellButtonClick := @EditCellButtonClick;
end;

{ 「评分」画星标,「备注」那一列改画成按钮(标题就是格内容)。 }
procedure TMainForm.EditGetCellDisplay(Sender: TObject; ACol, ARow: Integer;
  var ADisplay: TTyGridCellDisplay);
begin
  if ACol = cRate then ADisplay := gcdRating
  else if ACol = cNote then ADisplay := gcdButton
  else ADisplay := gcdText;
end;

procedure TMainForm.EditCellButtonClick(Sender: TObject; ACol, ARow: Integer);
begin
  Status(Format('按钮格被点击:(列 %d, 行 %d) —— 按下后拖出按钮再松手是不算数的',
    [ACol, ARow]));
end;

procedure TMainForm.ChkEditChange(Sender: TObject);
begin
  GridEdit.SkipReadOnlyCells := ChkSkipRO.Checked;
  if ChkEditLink.Checked then GridEdit.OnCreateEditLink := @EditCreateEditLink
  else GridEdit.OnCreateEditLink := nil;
end;

{ 宿主接管「备注」列的编辑器。给了 link 就整格交给它,内建的一概不出场。 }
procedure TMainForm.EditCreateEditLink(Sender: TObject; ACol, ARow: Integer;
  var ALink: TTyGridEditLink);
begin
  if ACol = cNote then ALink := FNoteLink;
end;

procedure TMainForm.BtnCellROClick(Sender: TObject);
begin
  GridEdit.CellReadOnly[GridEdit.Col, GridEdit.Row] := True;
  Status(Format('(列 %d, 行 %d) 已设为只读 —— 比"整列只读"更细一层',
    [GridEdit.Col, GridEdit.Row]));
end;

procedure TMainForm.BtnCellRWClick(Sender: TObject);
begin
  GridEdit.CellReadOnly[GridEdit.Col, GridEdit.Row] := False;
  Status('本格已恢复可编辑');
end;

{ ============ 页 5:选择 · 数据 · 剪贴板 ============ }

procedure TMainForm.SetupData;
begin
  BuildOrderColumns(GridData, False);
  FillOrders(GridData, 40, False);
end;

procedure TMainForm.CbSelModeChange(Sender: TObject);
begin
  case CbSelMode.ItemIndex of
    1: GridData.SelectionMode := gsmRow;
    2: GridData.SelectionMode := gsmColumn;
  else GridData.SelectionMode := gsmCell;
  end;
  Status('整行/整列模式下,焦点格仍有自己的底色 —— 看得出光标停在哪一格');
end;

procedure TMainForm.BtnSelAllClick(Sender: TObject);
begin
  GridData.SelectAll;
end;

procedure TMainForm.BtnSelNoneClick(Sender: TObject);
begin
  GridData.ClearSelection;
end;

procedure TMainForm.BtnMergeClick(Sender: TObject);
var
  sel: TRect;
begin
  sel := GridData.Selection;
  if (sel.Right <= sel.Left) and (sel.Bottom <= sel.Top) then
  begin
    Status('先拖选一块区域(至少 2x2)再点合并');
    Exit;
  end;
  GridData.MergeCells(sel.Left, sel.Top,
    sel.Right - sel.Left + 1, sel.Bottom - sel.Top + 1);
  Status('已合并 —— 注意合并区**内部没有格线穿过**,外沿仍然有');
end;

procedure TMainForm.BtnUnmergeClick(Sender: TObject);
begin
  GridData.UnmergeCells(GridData.Col, GridData.Row);
  Status('已取消合并(格上原有的底色不会被连坐清掉)');
end;

procedure TMainForm.BtnCopyClick(Sender: TObject);
begin
  GridData.CopySelectionToClipboard;
  Status('已复制 —— 导出走**显示序**,排序筛选后复制的就是屏幕上那块');
end;

procedure TMainForm.BtnCutClick(Sender: TObject);
begin
  GridData.CutToClipboard;
  Status('已剪切(只读格的内容不会被清掉)');
end;

procedure TMainForm.BtnPasteClick(Sender: TObject);
begin
  GridData.PasteFromClipboard;
  Status(Format('已粘贴 —— 现在 %d 行 x %d 列',
    [GridData.RowCount, GridData.Header.Columns.Count]));
end;

procedure TMainForm.ChkDataChange(Sender: TObject);
begin
  GridData.AutoGrowOnPaste := ChkAutoGrow.Checked;
  if ChkAutoGrow.Checked then
    Status('粘贴时表格会自动长大到装得下')
  else
    Status('已关掉自动扩表 —— 超出的行会被丢掉(这正是从前的静默丢数据行为)');
end;

procedure TMainForm.BtnInsRowClick(Sender: TObject);
begin
  GridData.InsertRow(GridData.Row);
  Status('已在当前行上方插入一行');
end;

procedure TMainForm.BtnDelRowClick(Sender: TObject);
begin
  GridData.DeleteRow(GridData.Row);
  Status('已删除当前行');
end;

{ 上移/下移会把底色、行高、合并跨度一起搬走,不是只换文字。 }
procedure TMainForm.BtnRowUpClick(Sender: TObject);
begin
  if GridData.Row <= 0 then Exit;
  GridData.MoveRow(GridData.Row, GridData.Row - 1);
  GridData.MoveCursor(GridData.Col, GridData.Row - 1);
end;

procedure TMainForm.BtnRowDownClick(Sender: TObject);
begin
  if GridData.Row >= GridData.RowCount - 1 then Exit;
  GridData.MoveRow(GridData.Row, GridData.Row + 1);
  GridData.MoveCursor(GridData.Col, GridData.Row + 1);
end;

{ 隐藏与筛选是**两回事**:筛选是条件,隐藏是事实。清筛选不会把隐藏的行放出来。 }
procedure TMainForm.BtnHideRowClick(Sender: TObject);
begin
  GridData.HideRow(GridData.Row);
  Status(Format('已隐藏第 %d 行 —— 共隐藏 %d 行。清筛选不会把它放出来',
    [GridData.Row, GridData.NumHiddenRows]));
end;

procedure TMainForm.BtnUnhideAllClick(Sender: TObject);
begin
  GridData.UnHideAllRows;
  Status('已全部取消隐藏');
end;

procedure TMainForm.BtnExportCsvClick(Sender: TObject);
var
  fn: string;
begin
  fn := ExtractFilePath(ParamStr(0)) + 'grid-export.csv';
  GridData.SaveToCSVFile(fn);
  Status(Format('已导出 %d 行到 %s(走显示序:筛掉的行不出现)',
    [GridData.DisplayRowCount, fn]));
end;

procedure TMainForm.BtnExportHtmlClick(Sender: TObject);
var
  fn: string;
begin
  fn := ExtractFilePath(ParamStr(0)) + 'grid-export.html';
  GridData.SaveToHTMLFile(fn);
  Status('已导出 HTML 到 ' + fn);
end;

{ ============ 换肤 ============ }

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);
end;

{ 主题色(强调色):覆盖 --accent,整套交互色跟着走,且跨主题、跨明暗都保持。
  再点一次恢复主题自带的强调色。 }
procedure TMainForm.BtnAccentClick(Sender: TObject);
var
  c: TTyColor;
begin
  if TyDefaultController.AccentOverride <> '' then
  begin
    TyDefaultController.ResetAccent;
    ApplyChromeTheme(TyDefaultController);
    Status('已恢复主题自带的强调色');
    Exit;
  end;
  c := TyDefaultController.Model.ResolveStyle('TyButton', 'primary', []).Background.Color;
  if TySelectColor('选择主题色', c) then
  begin
    TyDefaultController.SetAccent(TyColorToHex(c, False));
    ApplyChromeTheme(TyDefaultController);
    Status('主题色已改为 ' + TyColorToHex(c, False) + '(再点一次恢复)');
  end;
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  if DarkSwitch.Checked then TyDefaultController.Mode := 'dark'
  else TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

end.
