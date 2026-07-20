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
    6. 事件与钩子   —— 每个开关对应一个钩子:悬停提示、点击否决、右键、表头点击/右键、
                        列宽行高事件、列换位否决、勾选框事件、剪贴板钩子、查找替换、CSV 导入、
                        回车/滚动提示、编辑否决与逐键校验、增删行否决、光标否决、
                        单击双击、评分、排序否决与自定义比较、逐行过滤、候选值接管
    7. 单元格能力   —— 三态勾选框、批注(角标+悬停)、逐格字体样式、逐格与列级显示类型、
                        超链接列、显示格式化、大小写/合法字符/长度上限
    8. 呈现与表头   —— 滚动条三态、背景图与铺法/范围、焦点格外框、失焦选区变淡、
                        表头换行与高度自适应、多级表头分组、底部固定行/右侧冻结列
    9. 数据进出     —— JSON/HTML/CSV 导出(含只导选区)、流往返、追加导入与行数限制、
                        区域清空、选区文本与文本粘贴、页脚文案钩子与汇总接管、强制重算

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
  tyControls.Types, tyControls.ColorMath, tyControls.Dialogs, tyControls.Dialogs.Color,
  tyControls.IconFont, tyControls.ImageCollection, BGRABitmap, BGRABitmapTypes, StdCtrls;

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
    BtnSaveLayout, BtnLoadLayout: TTyButton;

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
      BtnGroup, BtnExpandAll, BtnCollapseAll, BtnGroup2: TTyButton;
    ChkPhysicalSort, ChkFilterRow, ChkTree: TTyCheckBox;
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
    TbData1, TbData2, TbData3: TTyPanel;
    LblColTip: TTyLabel;
    GridData: TTyStringGrid;
    CbSelMode: TTyComboBox;
    BtnSelAll, BtnSelNone, BtnMerge, BtnUnmerge, BtnCopy, BtnCut, BtnPaste,
      BtnInsRow, BtnDelRow, BtnRowUp, BtnRowDown, BtnHideRow, BtnUnhideAll,
      BtnExportCsv, BtnExportHtml, BtnUndo, BtnRedo,
      BtnInsCol, BtnDelCol, BtnMoveCol: TTyButton;
    ChkAutoGrow: TTyCheckBox;

    PgEvents: TTyTabSheet;
    LblEvHint, LblEvTip: TTyLabel;
    TbEv1, TbEv2: TTyPanel;
    GridEvents: TTyStringGrid;
    ChkEvHint, ChkEvLockRow, ChkEvRightClick, ChkEvHeader, ChkEvSize,
      ChkEvColMove, ChkEvCheck, ChkEvClip,
      ChkEvRowMove, ChkEvEditorProp,
      ChkEvReturn, ChkEvScrollHint, ChkEvCanEdit, ChkEvEditChange,
      ChkEvCellEdited, ChkEvRowVeto, ChkEvSelectCell,
      ChkEvClick, ChkEvRating, ChkEvCanSort, ChkEvCompare,
      ChkEvFilterRow, ChkEvFilterVals, ChkEvPickList: TTyCheckBox;
    TbEv3, TbEv4: TTyPanel;
    BtnEvFind, BtnEvReplace, BtnEvImportCsv: TTyButton;
    EdEvFind, EdEvRepl: TTyEdit;

    PgCells: TTyTabSheet;
    LblCellsHint, LblCellDisp, LblCase, LblMaxLen: TTyLabel;
    TbCells1, TbCells2: TTyPanel;
    GridCells: TTyStringGrid;
    ChkTriState, ChkFormat, ChkLinkCol, ChkColProgress,
      ChkDigitsOnly: TTyCheckBox;
    BtnComment, BtnCommentClear, BtnBold, BtnBoldClear: TTyButton;
    CbCellDisp, CbCase: TTyComboBox;
    SpMaxLen: TTySpinEdit;

    PgView: TTyTabSheet;
    LblViewHint, LblVScroll, LblHScroll: TTyLabel;
    TbView1, TbView2: TTyPanel;
    GridView: TTyStringGrid;
    CbVScroll, CbHScroll, CbBackMode, CbBackScope: TTyComboBox;
    ChkBackImage, ChkFocusCell, ChkDimInactive, ChkHdrWrap, ChkHdrAuto,
      ChkHdrGroups, ChkHdrGroups2, ChkFixBottom, ChkFixRight: TTyCheckBox;
    BtnLongCaption: TTyButton;

    PgIo: TTyTabSheet;
    LblIoHint, LblIoMax, LblIoSkip: TTyLabel;
    TbIo1, TbIo2: TTyPanel;
    GridIo: TTyStringGrid;
    BtnIoJson, BtnIoHtml, BtnIoCsvSel, BtnIoStream, BtnIoSelText,
      BtnIoPasteText, BtnIoClearRows, BtnIoClearCols, BtnIoImport,
      BtnIoRecalc: TTyButton;
    ChkIoAppend, ChkIoFooterHook, ChkIoColCalc: TTyCheckBox;
    SpIoMax, SpIoSkip: TTySpinEdit;

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
    procedure BtnGroup2Click(Sender: TObject);
    procedure ChkPhysicalSortChange(Sender: TObject);
    procedure ChkFilterRowChange(Sender: TObject);
    procedure ChkTreeChange(Sender: TObject);
    procedure TreeNodeLevel(Sender: TObject; ARow: Integer;
      var ALevel: Integer);
    procedure TreeHasChildren(Sender: TObject; ARow: Integer;
      var AHas: Boolean);
    procedure BtnSaveLayoutClick(Sender: TObject);
    procedure BtnLoadLayoutClick(Sender: TObject);
    procedure HandleRowMoveVeto(Sender: TObject; AFrom, ATo: Integer;
      var AAllow: Boolean);
    procedure HandleEditorProp(Sender: TObject; ACol, ARow: Integer;
      AEditor: TControl);
    procedure BtnExpandAllClick(Sender: TObject);
    procedure BtnCollapseAllClick(Sender: TObject);

    { 页 4 }
    procedure ChkEditChange(Sender: TObject);
    procedure BtnCellROClick(Sender: TObject);
    procedure BtnCellRWClick(Sender: TObject);
    procedure EditGetCellDisplay(Sender: TObject; ACol, ARow: Integer;
      var ADisplay: TTyGridCellDisplay);
    procedure EditCellButtonClick(Sender: TObject; ACol, ARow: Integer);
    procedure EditEllipsisClick(Sender: TObject; ACol, ARow: Integer;
      var AText: string; var AAccept: Boolean);
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
    procedure BtnInsColClick(Sender: TObject);
    procedure BtnDelColClick(Sender: TObject);
    procedure BtnMoveColClick(Sender: TObject);
    procedure BtnUndoClick(Sender: TObject);
    procedure BtnRedoClick(Sender: TObject);
    procedure ChkDataChange(Sender: TObject);

    { 页 6 }
    procedure ChkEvChange(Sender: TObject);
    procedure BtnEvFindClick(Sender: TObject);
    procedure BtnEvReplaceClick(Sender: TObject);
    procedure BtnEvImportCsvClick(Sender: TObject);

    { 页 6 补齐的钩子 }
    procedure ChkEv3Change(Sender: TObject);
    procedure EvReturn(Sender: TObject; ACol, ARow: Integer);
    procedure EvCtrlReturn(Sender: TObject; ACol, ARow: Integer);
    procedure EvScrollHint(Sender: TObject; ARow: Integer; var AHint: string);
    procedure EvCanEdit(Sender: TObject; ACol, ARow: Integer;
      var AAllow: Boolean);
    procedure EvEditChange(Sender: TObject; ACol, ARow: Integer;
      const AText: string);
    procedure EvCellEdited(Sender: TObject; ACol, ARow: Integer;
      const AOldText, ANewText: string; var AAccept: Boolean);
    procedure EvCanInsertRow(Sender: TObject; ARow: Integer;
      var AAllow: Boolean);
    procedure EvCanDeleteRow(Sender: TObject; ARow: Integer;
      var AAllow: Boolean);
    procedure EvSelectCell(Sender: TObject; ACol, ARow: Integer;
      var ACanSelect: Boolean);
    procedure EvClickCell(Sender: TObject; ACol, ARow: Integer);
    procedure EvDblClickCell(Sender: TObject; ACol, ARow: Integer);
    procedure EvRatingChange(Sender: TObject; ACol, ARow: Integer;
      AValue: Integer);
    procedure EvCanSort(Sender: TObject; ACol: Integer; var AAllow: Boolean);
    procedure EvCompareCells(Sender: TObject; ACol, ARow1, ARow2: Integer;
      var AResult: Integer);
    procedure EvFilterRow(Sender: TObject; ARow: Integer; var AVisible: Boolean);
    procedure EvGetFilterValues(Sender: TObject; ACol: Integer;
      AItems: TStrings; var AHandled: Boolean);
    procedure EvGetPickList(Sender: TObject; ACol, ARow: Integer;
      AItems: TStrings);

    { 页 9 }
    procedure ChkIoChange(Sender: TObject);
    procedure BtnIoJsonClick(Sender: TObject);
    procedure BtnIoHtmlClick(Sender: TObject);
    procedure BtnIoCsvSelClick(Sender: TObject);
    procedure BtnIoStreamClick(Sender: TObject);
    procedure BtnIoSelTextClick(Sender: TObject);
    procedure BtnIoPasteTextClick(Sender: TObject);
    procedure BtnIoClearRowsClick(Sender: TObject);
    procedure BtnIoClearColsClick(Sender: TObject);
    procedure BtnIoImportClick(Sender: TObject);
    procedure BtnIoRecalcClick(Sender: TObject);
    procedure IoGetFooterText(Sender: TObject; ACol: Integer;
      var AText: string);
    procedure IoColumnCalc(Sender: TObject; ACol: Integer;
      var AValue: Double; var AHandled: Boolean);

    { 页 8 }
    procedure ChkViewChange(Sender: TObject);
    procedure CbScrollChange(Sender: TObject);
    procedure CbBackChange(Sender: TObject);
    procedure BtnLongCaptionClick(Sender: TObject);

    { 页 7 }
    procedure ChkCellsChange(Sender: TObject);
    procedure BtnCommentClick(Sender: TObject);
    procedure BtnCommentClearClick(Sender: TObject);
    procedure BtnBoldClick(Sender: TObject);
    procedure BtnBoldClearClick(Sender: TObject);
    procedure CbCellDispChange(Sender: TObject);
    procedure CbCaseChange(Sender: TObject);
    procedure SpMaxLenChange(Sender: TObject);
    procedure CellsGetFormat(Sender: TObject; ACol, ARow: Integer;
      var AText: string);
    procedure CellsLinkClick(Sender: TObject; ACol, ARow: Integer);
    procedure EvGetCellHint(Sender: TObject; ACol, ARow: Integer; var AHint: string);
    procedure EvCanClickCell(Sender: TObject; ACol, ARow: Integer;
      var ACanClick: Boolean);
    procedure EvRightClickCell(Sender: TObject; ACol, ARow: Integer);
    procedure EvHeaderClick(Sender: TObject; ACol: Integer);
    procedure EvHeaderRightClick(Sender: TObject; ACol: Integer);
    procedure EvColumnSizing(Sender: TObject; AIndex: Integer;
      var ANewSize: Integer; var AAllow: Boolean);
    procedure EvEndColumnSize(Sender: TObject; AIndex, ANewSize: Integer);
    procedure EvRowSizing(Sender: TObject; AIndex: Integer;
      var ANewSize: Integer; var AAllow: Boolean);
    procedure EvEndRowSize(Sender: TObject; AIndex, ANewSize: Integer);
    procedure EvColumnMove(Sender: TObject; AFromCol, AToCol: Integer;
      var AAllow: Boolean);
    procedure EvCanToggleCheck(Sender: TObject; ACol, ARow: Integer;
      var AAllow: Boolean);
    procedure EvCheckBoxChange(Sender: TObject; ACol, ARow: Integer;
      AChecked: Boolean);
    procedure EvClipboardCopy(Sender: TObject; var AText: string;
      var AAllow: Boolean);
    procedure EvBeforePasteCell(Sender: TObject; ACol, ARow: Integer;
      var ANewText: string; var AAllow: Boolean);
    procedure EvAfterPasteCell(Sender: TObject; ACol, ARow: Integer);
  private
    FNoteLink: TNoteEditLink;
    { 背景图由**宿主**持有并释放 —— 控件只借用(与 Images 同一约定,
      免得两边都以为对方会 Free)。 }
    FBackBmp: TBGRABitmap;
    FSizingCount, FPasteCount: Integer;
    { 「记住版式」存下来的那一串 —— 真实工程里进注册表或配置文件。
      **必须放 private**:表单类的字段区默认是 published,而字符串不能 published。 }
    FSavedLayout: string;
    function  ColorSelectedCells(AColor: TTyColor): Integer;
    procedure VirtualCellText(Sender: TObject; ACol, ARow: Integer;
      var AText: string);
    procedure BuildOrderColumns(AGrid: TTyStringGrid; AWithNote: Boolean;
      AWithEditorCols: Boolean = False);
    procedure FillOrders(AGrid: TTyStringGrid; ACount: Integer; AWithNote: Boolean;
      AWithEditorCols: Boolean = False);
    procedure SetupBasic;
    procedure SetupLook;
    procedure SetupSort;
    procedure SetupEdit;
    procedure SetupData;
    procedure SetupEvents;
    procedure SetupCells;
    procedure SetupView;
    procedure SetupIo;
    procedure ApplyHeaderGroups;
    function  MakeWatermark: TBGRABitmap;
    function  HeaderGroupLevels: Integer;
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
  { 只有「编辑与单元格类型」那一页才建的额外列 —— 每一列专门演示一种内建编辑器,
    否则 16 种编辑器里有好几种在示例里根本露不了面。 }
  cDiscount = 10; cProgress = 11; cETA = 12; cPin = 13;

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

procedure TMainForm.BuildOrderColumns(AGrid: TTyStringGrid; AWithNote: Boolean;
  AWithEditorCols: Boolean);

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
    if AWithEditorCols then
    begin
      AddCol('折扣%', 70, taRightJustify).SortKind := gskNumber;
      AddCol('进度%', 96, taLeftJustify).SortKind := gskNumber;
      AddCol('交期',   80, taCenter);
      AddCol('口令',   90, taLeftJustify);
    end;
  finally
    AGrid.Header.Columns.EndUpdate;
  end;
end;

procedure TMainForm.FillOrders(AGrid: TTyStringGrid; ACount: Integer;
  AWithNote: Boolean; AWithEditorCols: Boolean);
var
  r, qty: Integer;
  amount: Double;
begin
  { 批量灌数据必须锁住重画 —— 不锁的话每写一格就往 LCL 送一次失效,
    10 万行 x 9 列 = 90 万次,界面看起来就是死的。 }
  AGrid.BeginUpdate;
  try
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
    if AWithEditorCols then
    begin
      AGrid.Cells[cDiscount, r] := IntToStr(r mod 30);
      AGrid.Cells[cProgress, r] := IntToStr((r * 13) mod 101);
      AGrid.Cells[cETA,      r] := Format('%.2d:%.2d', [8 + r mod 10, (r * 7) mod 60]);
      AGrid.Cells[cPin,      r] := 'pw' + IntToStr(1000 + r);
    end;
  end;
  finally
    AGrid.EndUpdate;
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
  FBackBmp := nil;

  SetupBasic;
  SetupLook;
  SetupSort;
  SetupEdit;
  SetupData;
  SetupEvents;
  SetupCells;
  SetupView;
  SetupIo;

  Status('每一页演示一组特性 —— 从左到右依次看下来即可');
end;

function TMainForm.ActiveGrid: TTyStringGrid;
begin
  case Pages.ActivePageIndex of
    1: Result := GridLook;
    2: Result := GridSort;
    3: Result := GridEdit;
    4: Result := GridData;
    5: Result := GridEvents;
    6: Result := GridCells;
    7: Result := GridView;
    8: Result := GridIo;
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
  GridBasic.OnGetCellText := nil;   { 摘掉虚拟数据源 }
  FillOrders(GridBasic, 10000, False);
  Status('1 万行 —— 只绘制可视窗口内的几十行,滚动一下试试');
end;

procedure TMainForm.BtnRows10WClick(Sender: TObject);
begin
  GridBasic.OnGetCellText := nil;   { 摘掉虚拟数据源 }
  FillOrders(GridBasic, 100000, False);
  Status('10 万行 —— 这次是**真写满**了 90 万格,对比上面那个百万行看"已存格数"');
end;

{ 一百万行:**一格都不写**,内容由 OnGetCellText 按需生成。

  这才是虚拟化的正题:表里有数据、"已存格数"仍是 0、滚动照样瞬时。
  从前这里是 ClearCells + 拉大 RowCount —— 技术上没错(确实证明了稀疏存储),
  但用户看到的是一张**空表**,只会读成"表格被清空了"。
  空白证明不了任何东西,能滚的百万行数据才能。 }
procedure TMainForm.VirtualCellText(Sender: TObject; ACol, ARow: Integer;
  var AText: string);
var
  qty: Integer;
begin
  qty := 1 + (ARow * 7) mod 40;
  case ACol of
    cOrderNo: AText := Format('SO-2026%06d', [ARow + 1]);
    cRegion:  AText := cRegions[ARow mod Length(cRegions)];
    cProduct: AText := cProducts[ARow mod Length(cProducts)];
    cQty:     AText := IntToStr(qty);
    cAmount:  AText := Format('%.2f', [qty * 128.5]);
    cDate:    AText := FormatDateTime('yyyy-mm-dd',
                EncodeDate(2026, 1 + ARow mod 12, 1 + ARow mod 28));
    cDone:    if ARow mod 3 = 0 then AText := '1' else AText := '';
    cRate:    AText := IntToStr(1 + ARow mod 5);
    cMark:    AText := cMarkColors[ARow mod Length(cMarkColors)];
  else
    AText := '';
  end;
end;

procedure TMainForm.BtnRows100WClick(Sender: TObject);
begin
  GridBasic.ClearCells;
  { 挂上虚拟数据源。GetCellText 先问事件,事件给空串才回落到自带存储 ——
    所以挂着它的时候不要再往里写格子(下面几个按钮会先摘掉它)。 }
  GridBasic.OnGetCellText := @VirtualCellText;
  GridBasic.RowCount := 1000000;
  GridBasic.MoveCursor(0, 0);
  Status('100 万行 —— 内容由回调按需生成,"已存格数"仍是 0:这就是虚拟化 + 稀疏存储');
end;

procedure TMainForm.BtnRowsResetClick(Sender: TObject);
begin
  GridBasic.OnGetCellText := nil;   { 摘掉虚拟数据源,回到自带存储 }
  GridBasic.ClearCells;
  FillOrders(GridBasic, 200, False);
  GridBasic.MoveCursor(0, 0);
  Status('已恢复 200 行');
end;

{ 跳转:MoveCursor 之后显式 ScrollIntoView。横向滚动会**跳过冻结列**。 }
procedure TMainForm.BtnGotoClick(Sender: TObject);
begin
  GridBasic.OnGetCellText := nil;   { 摘掉虚拟数据源 }
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
  { 「行号槽」= 那条槽 + 槽里的数字。两件事在控件上是分开的两个属性:
    ShowIndicator 只铺出那条槽,不打开 ShowRowNumbers 的话它是一条空白带。 }
  GridBasic.ShowIndicator := ChkIndicator.Checked;
  GridBasic.ShowRowNumbers := ChkIndicator.Checked;
  GridBasic.ShowFooter := ChkFooter.Checked;
end;

{ ============ 页 2:外观 ============ }

procedure TMainForm.SetupLook;
var
  icf: TTyIconFont;
  coll: TTyImageCollection;
  imgs: TTyVirtualImageList;
  b: TBGRABitmap;
begin
  BuildOrderColumns(GridLook, True);
  FillOrders(GridLook, 60, True);
  GridLook.OnGetCellWordWrap := @LookGetCellWordWrap;

  { 列头图标要有**图标来源**才画得出来 —— 列上的 ImageIndex 只是"用第几个",
    网格的 Images 为 nil 时它是天然无效的(勾了没反应就是这么来的)。
    这里从图标字体渲一个符号进图像集合,再挂成虚拟图像列表。 }
  icf := TTyIconFont.Create(Self);
  icf.FontFamily := 'Segoe UI Symbol';
  coll := TTyImageCollection.Create(Self);
  imgs := TTyVirtualImageList.Create(Self);
  imgs.Collection := coll;
  icf.MapGlyph('money', $00A5);                 { ¥ }
  b := icf.RenderGlyph('money', 32, TyRGB(180, 83, 9));
  try
    coll.AddBitmap('money', b);
  finally
    b.Free;
  end;
  imgs.Names.Add('money');
  GridLook.Images := imgs;

  { 行号槽只铺底不画号 —— 得显式打开。两件事是分开的:
    ShowIndicator 是那条槽,ShowRowNumbers 才是槽里的数字。 }
  GridLook.ShowIndicator := True;
  GridLook.ShowRowNumbers := True;
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

{ 对**整个选区**生效 —— 选了多格却只染一格,是把用户的选择丢掉了。

  这里从前是自己写的双重循环。它遍历得没错(走显示序、寻址用数据行,
  所以排序筛选之后颜色跟着数据走),但**漏了事务** ——
  涂一片之后按 Ctrl+Z 是一格一格退的。
  遍历选区这件事本来就该由控件收口(只读那半边早就收口了),
  现在写这半边也有了:`SetSelectionColor` 内部包事务,一次涂色一次撤销。 }
function TMainForm.ColorSelectedCells(AColor: TTyColor): Integer;
begin
  Result := GridLook.SetSelectionColor(AColor);
end;

procedure TMainForm.BtnCellColorClick(Sender: TObject);
var
  c: TTyColor;
begin
  c := TyRGB(255, 236, 179);
  if TySelectColor('给选中的格选个底色', c) then
    Status(Format('%d 格已上色 —— 这是**落盘**的颜色,排序后跟着数据行走',
      [ColorSelectedCells(c)]));
end;

procedure TMainForm.BtnCellUncolorClick(Sender: TObject);
begin
  Status(Format('已清除 %d 格的底色', [ColorSelectedCells(0)]));
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
  { 赋 <= 0 表示"清掉显式行高、回到默认",不是"行高为 0"。
    包进 BeginUpdate/EndUpdate —— 行高是可撤销的,一次"恢复"就该是一次
    Ctrl+Z 退回去,而不是一行一行退。宿主写批量循环时都要记得这一层。 }
  GridLook.BeginUpdate;
  try
    for i := 0 to GridLook.RowCount - 1 do
      GridLook.RowHeights[i] := 0;
  finally
    GridLook.EndUpdate;
  end;
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

{ 多级分组:先按大区、再按城市。关键在于**同名子组出现在不同父组下**时
  互不影响 —— 折叠状态按层级路径记,不是按值记。 }
procedure TMainForm.BtnGroup2Click(Sender: TObject);
begin
  if Length(GridSort.GroupColumns) > 1 then
  begin
    GridSort.UngroupRows;
    BtnGroup2.Caption := '按大区 + 产品分组';
    Status('已取消分组');
  end
  else
  begin
    GridSort.GroupByColumns([cRegion, cProduct]);
    BtnGroup2.Caption := '取消多级分组';
    Status('两级分组 —— 小计按层级各算各的;折叠状态按**路径**记,' +
      '所以不同大区下的同名产品互不影响');
  end;
end;

{ 物理排序:点列头时真的把数据换位置(像 Excel)。排完显示序就等于数据序,
  于是"排过序就不许合并 / 不许拖行"那几条限制自动解除。
  有筛选/分组/虚拟源时控件会自动退回普通排序 —— 那时搬数据会损坏数据。 }
procedure TMainForm.ChkPhysicalSortChange(Sender: TObject);
begin
  if ChkPhysicalSort.Checked then
  begin
    GridSort.SortMode := gsmData;
    Status('排序会真的搬数据(可撤销)—— 排完之后合并和拖行不再被拒绝;' +
      '一挂上筛选或分组会自动退回普通排序');
  end
  else
  begin
    GridSort.SortMode := gsmDisplay;
    Status('排序只换显示顺序,数据不动(默认)');
  end;
end;

{ 版式持久化:列宽 / 列序 / 可见性 / 排序键 / 冻结数存成一个字符串。
  存哪儿由宿主决定 —— 这里就放个字段,真实工程里进注册表或配置文件。
  **不含行高与筛选**:行高更贴近数据(百万行的表存成一个字符串不是"版式"),
  筛选是"我此刻想看什么"而不是"我把表调成什么样"。 }
procedure TMainForm.BtnSaveLayoutClick(Sender: TObject);
begin
  FSavedLayout := GridBasic.SaveLayoutToString;
  Status('版式已记下 —— 现在随便拖列宽、换列序、改冻结数,再点「还原版式」');
end;

procedure TMainForm.BtnLoadLayoutClick(Sender: TObject);
begin
  if FSavedLayout = '' then
  begin
    Status('还没记过版式 —— 先点「记住版式」');
    Exit;
  end;
  { 读回来是**全有或全无**:整串先校验完才动控件。
    半套版式(列宽还原了、列序没还原)比完全不还原更难排查。 }
  if GridBasic.LoadLayoutFromString(FSavedLayout) then
    Status('版式已还原(列宽 / 列序 / 可见性 / 排序键 / 冻结数)')
  else
    Status('这串版式不认识 —— 什么都没动');
end;

{ 拖行之前问一句。返回 False 就否决这一次移动。 }
procedure TMainForm.HandleRowMoveVeto(Sender: TObject; AFrom, ATo: Integer;
  var AAllow: Boolean);
begin
  AAllow := ATo > 0;
  if not AAllow then
    Status(Format('OnRowMove 否决了:不许把第 %d 行拖到首行', [AFrom]));
end;

{ 编辑器建好之后、交回调用方之前触发,拿到的是**真正那个控件**。
  想改字体 / 限长 / 颜色都来得及,不必为了一点微调去写整个 OnCreateEditLink。 }
procedure TMainForm.HandleEditorProp(Sender: TObject; ACol, ARow: Integer;
  AEditor: TControl);
begin
  if AEditor is TTyEdit then
  begin
    TTyEdit(AEditor).Font.Color := clRed;
    Status(Format('OnGetEditorProp:把 (%d, %d) 的编辑器染红了', [ACol, ARow]));
  end;
end;

{ 内嵌筛选行:列头下面一条带,每列一个输入位。
  语法走 TyGridParseFilterExpr —— `>1000`、`<=5`、`<>华东`、`300..600`,
  `;` 分隔的多个条件之间是 OR。输入即筛(防抖),回车立刻生效,Esc 放弃。 }
procedure TMainForm.ChkFilterRowChange(Sender: TObject);
begin
  GridSort.ShowFilterRow := ChkFilterRow.Checked;
  if ChkFilterRow.Checked then
    Status('筛选行开了 —— 在「数量」列打 >20,或在「大区」列打 华东;华北 试试' +
      '(; 是或,a..b 是区间)')
  else
    Status('筛选行关了');
end;

{ 树形单元格:**控件不持有树** —— 层级和"有没有孩子"由这两个回调回答。
  这里按大区分层:每个大区的第一条当父节点,同大区的其余条目当它的孩子。 }
procedure TMainForm.TreeNodeLevel(Sender: TObject; ARow: Integer;
  var ALevel: Integer);
begin
  if (ARow mod 4) = 0 then ALevel := 0 else ALevel := 1;
end;

procedure TMainForm.TreeHasChildren(Sender: TObject; ARow: Integer;
  var AHas: Boolean);
begin
  AHas := (ARow mod 4) = 0;
end;

procedure TMainForm.ChkTreeChange(Sender: TObject);
begin
  if ChkTree.Checked then
  begin
    GridSort.OnGetNodeLevel := @TreeNodeLevel;
    GridSort.OnGetHasChildren := @TreeHasChildren;
    GridSort.TreeColumn := cOrderNo;
    Status('树形列开了 —— 点第一列的三角折叠/展开;' +
      '层级由宿主给,控件不持有树');
  end
  else
  begin
    GridSort.TreeColumn := -1;
    GridSort.OnGetNodeLevel := nil;
    GridSort.OnGetHasChildren := nil;
    Status('树形列关了');
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
  BuildOrderColumns(GridEdit, True, True);
  FillOrders(GridEdit, 40, True, True);

  { ---- 全部在**列上**声明,一个事件都没接 ---- }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cOrderNo]);
  c.ReadOnly := True;                       { 主键不给改 }

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cRegion]);
  c.EditorKind := gekPickList;              { 下拉,候选项也挂在列上 }
  c.PickList.CommaText := '华东,华北,华南,西南,东北,西北';

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cQty]);
  c.EditorKind := gekSpin;                  { 数值微调:带上下按钮 }
  c.MinValue := 0;
  c.MaxValue := 200;

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cDate]);
  c.EditorKind := gekDate;                  { 日期选择器 }

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cDone]);
  c.EditorKind := gekCheckBox;              { 点方块直接切换 }

  c := TTyGridColumn(GridEdit.Header.Columns.Items[cMark]);
  c.EditorKind := gekColor;                 { 弹取色对话框 }

  { 评分:**点第几颗星就是几分**,不弹编辑器(与勾选框同一种手感)。 }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cRate]);
  c.EditorKind := gekRating;

  { 订单号改成掩码编辑 —— 掩码挂在列上,交给 TTyMaskEdit 解释。
    (它同时还是只读的演示对象,所以这里先放开只读。) }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cOrderNo]);
  c.ReadOnly := False;
  c.EditorKind := gekMask;
  c.EditMask := 'CC-99999999';

  { 金额:带计算器的数值 —— 金额本来就常要现算一下。
    (从前这里写的是滑动条,而且同一列的 EditorKind 被赋了两遍、前一句是死代码:
     金额是 '%.2f' 文本,滑动条按整数解析,拖出来永远是 0。) }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cAmount]);
  c.EditorKind := gekCalculator;

  { 产品:省略号按钮 —— 点右边的 … 弹自己的对话框,这是"自定义编辑"的入口。 }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cProduct]);
  c.EditorKind := gekEllipsis;

  { 折扣:朴素数值输入。 }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cDiscount]);
  c.EditorKind := gekNumeric;

  { 进度:滑动条 —— 整数、有明确区间,滑块本来就该用在这种列上。
    编辑时滑块自带数值读数,拖到哪儿一眼看得见。 }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cProgress]);
  c.EditorKind := gekSlider;
  c.MinValue := 0;
  c.MaxValue := 100;

  { 交期:只选时间。 }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cETA]);
  c.EditorKind := gekTime;

  { 窄列上编辑器自己加宽到看得清 —— 加宽的是编辑器,列宽一点没动。 }
  GridEdit.MinEditorWidth := 160;
  { 大区的下拉单独放宽:列只有 70 宽,候选项按列宽显示会被截成一小截。 }
  TTyGridColumn(GridEdit.Header.Columns.Items[cRegion]).DropDownWidth := 160;

  { 口令:输入时打点。 }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cPin]);
  c.EditorKind := gekPassword;

  { 备注多行编辑。 }
  c := TTyGridColumn(GridEdit.Header.Columns.Items[cNote]);
  c.EditorKind := gekMemo;

  { 「评分」显示成星标、「备注」当按钮列用 —— 显示方式与编辑方式是正交的。 }
  GridEdit.OnGetCellDisplay := @EditGetCellDisplay;
  GridEdit.OnCellButtonClick := @EditCellButtonClick;
  { 省略号按钮:格子右缘那个 … 。挂上它,宿主爱弹什么对话框弹什么 ——
    这是"网格答不上来的编辑需求"的一等公民入口(比自写 EditLink 轻得多)。 }
  GridEdit.OnEllipsisClick := @EditEllipsisClick;
end;

{ 「评分」画星标,「备注」那一列改画成按钮(标题就是格内容)。 }
procedure TMainForm.EditGetCellDisplay(Sender: TObject; ACol, ARow: Integer;
  var ADisplay: TTyGridCellDisplay);
begin
  if ACol = cRate then ADisplay := gcdRating
  else if ACol = cMark then ADisplay := gcdColor    { 画色块,不是把 '#RRGGBB' 显示出来 }
  else if ACol = cNote then ADisplay := gcdButton
  else ADisplay := gcdText;
end;

{ 省略号按钮被点。改不改、改成什么,全由宿主说了算。 }
procedure TMainForm.EditEllipsisClick(Sender: TObject; ACol, ARow: Integer;
  var AText: string; var AAccept: Boolean);
var
  v: string;
begin
  v := AText;
  AAccept := TyInputQuery('选择产品',
    Format('第 %d 行的产品(可用:%s)', [ARow + 1, string.Join('/', cProducts)]), v);
  if AAccept then AText := v;
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
begin
  { 跨度由网格自己从选区算 —— 宿主**别**自己算。
    选区矩形活在显示序空间,而 Selection 对外给的是数据行坐标,
    两个数据行下标之差在任何空间里都不是"几行"(排过序的表上这么算,
    会吞掉几十行)。 }
  if GridData.MergeSelection then
    Status('已合并 —— 注意合并区**内部没有格线穿过**,外沿仍然有')
  else
    Status('没合并:要么没拖选出一块区域,'
      + '要么这几行在数据里并不相邻(排过序/藏过行)—— 那样合成一块,换个排序就散了');
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

{ 上移/下移会把底色、行高、合并跨度一起搬走,不是只换文字。
  也可以**直接在行头槽里拖行**(与列头拖列对称)——
  但排过序/分过组/藏过行时拖不动:那时显示序不是数据序,
  把行拖到某个屏幕位置没有意义,松手排序就会把它放回去。 }
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

{ 撤销覆盖的不只是格里的字。给某行涂个底色、拖高它、再上移一格,
  然后按这里(或 Ctrl+Z)—— 底色、行高、合并跨度都跟着回原位。
  它们各自有记录点,不是靠"整行交换"记一笔。 }
{ 列的增删与换位 —— 这三个现在都进撤销栈(P3.6)。
  删一列之后按 Ctrl+Z,回来的不只是那些格子:宽度、标题、对齐、编辑器种类、
  只读、下拉候选、以及那一列上的筛选,全都跟着回来。 }
procedure TMainForm.BtnInsColClick(Sender: TObject);
begin
  GridData.InsertColumn(GridData.Col);
  Status(Format('在第 %d 列前插了一列 —— Ctrl+Z 可以撤销', [GridData.Col]));
end;

procedure TMainForm.BtnDelColClick(Sender: TObject);
var
  c: TTyColumn;
begin
  if GridData.Header.Columns.Count <= 1 then
  begin
    Status('只剩一列了,不删');
    Exit;
  end;
  c := TTyColumn(GridData.Header.Columns.Items[GridData.Col]);
  Status(Format('删掉了「%s」(宽 %d)—— 按 Ctrl+Z,它连同宽度/标题/' +
    '编辑器种类/筛选一起回来', [c.Text, c.Width]));
  GridData.DeleteColumn(GridData.Col);
end;

procedure TMainForm.BtnMoveColClick(Sender: TObject);
begin
  if GridData.Col >= GridData.Header.Columns.Count - 1 then
  begin
    Status('已经是最后一列了');
    Exit;
  end;
  GridData.MoveColumn(GridData.Col, GridData.Col + 1);
  Status('本列与右邻换了位置 —— 换位也能撤销');
end;

procedure TMainForm.BtnUndoClick(Sender: TObject);
begin
  if not GridData.CanUndo then
  begin
    Status('没有可撤销的操作了');
    Exit;
  end;
  GridData.Undo;
  Status('已撤销 —— 底色、行高、合并跨度会跟着一起回来');
end;

procedure TMainForm.BtnRedoClick(Sender: TObject);
begin
  if not GridData.CanRedo then
  begin
    Status('没有可重做的操作了');
    Exit;
  end;
  GridData.Redo;
  Status('已重做');
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


{ ============ 页 6:事件与钩子 ============ }

procedure TMainForm.SetupEvents;
begin
  BuildOrderColumns(GridEvents, False);
  FillOrders(GridEvents, 60, False);
  { 让「标记色」列画成色块。 }
  GridEvents.OnGetCellDisplay := @EditGetCellDisplay;
  { 拖列换位要开这两个开关(列级的 coDraggable 默认就有)。 }
  GridEvents.Header.Options := GridEvents.Header.Options + [hoDrag];
  ChkEvChange(nil);
end;

{ 每个开关按需挂/摘对应的钩子。没挂时控件走的是完全没有该钩子的那条路径 ——
  这正是"开/关对比"能说明问题的原因。 }
procedure TMainForm.ChkEvChange(Sender: TObject);
begin
  if ChkEvHint.Checked then GridEvents.OnGetCellHint := @EvGetCellHint
  else GridEvents.OnGetCellHint := nil;

  if ChkEvLockRow.Checked then GridEvents.OnCanClickCell := @EvCanClickCell
  else GridEvents.OnCanClickCell := nil;

  if ChkEvRightClick.Checked then GridEvents.OnRightClickCell := @EvRightClickCell
  else GridEvents.OnRightClickCell := nil;

  { 拖行的否决钩子 —— 在行号槽里往上拖到首行会被挡住。 }
  if ChkEvRowMove.Checked then GridEvents.OnRowMove := @HandleRowMoveVeto
  else GridEvents.OnRowMove := nil;

  { 编辑器微调钩子 —— 双击进编辑,字会是红的。 }
  if ChkEvEditorProp.Checked then GridEvents.OnGetEditorProp := @HandleEditorProp
  else GridEvents.OnGetEditorProp := nil;

  if ChkEvHeader.Checked then
  begin
    GridEvents.OnHeaderClick := @EvHeaderClick;
    GridEvents.OnHeaderRightClick := @EvHeaderRightClick;
  end
  else
  begin
    GridEvents.OnHeaderClick := nil;
    GridEvents.OnHeaderRightClick := nil;
  end;

  if ChkEvSize.Checked then
  begin
    GridEvents.OnColumnSizing := @EvColumnSizing;
    GridEvents.OnEndColumnSize := @EvEndColumnSize;
    GridEvents.OnRowSizing := @EvRowSizing;
    GridEvents.OnEndRowSize := @EvEndRowSize;
  end
  else
  begin
    GridEvents.OnColumnSizing := nil;
    GridEvents.OnEndColumnSize := nil;
    GridEvents.OnRowSizing := nil;
    GridEvents.OnEndRowSize := nil;
  end;

  if ChkEvColMove.Checked then GridEvents.OnColumnMove := @EvColumnMove
  else GridEvents.OnColumnMove := nil;

  if ChkEvCheck.Checked then
  begin
    GridEvents.OnCanToggleCheck := @EvCanToggleCheck;
    GridEvents.OnCheckBoxChange := @EvCheckBoxChange;
  end
  else
  begin
    GridEvents.OnCanToggleCheck := nil;
    GridEvents.OnCheckBoxChange := nil;
  end;

  if ChkEvClip.Checked then
  begin
    GridEvents.OnClipboardCopy := @EvClipboardCopy;
    GridEvents.OnBeforePasteCell := @EvBeforePasteCell;
    GridEvents.OnAfterPasteCell := @EvAfterPasteCell;
  end
  else
  begin
    GridEvents.OnClipboardCopy := nil;
    GridEvents.OnBeforePasteCell := nil;
    GridEvents.OnAfterPasteCell := nil;
  end;
end;

{ 悬停提示:控件只在**换格**时才回调,所以气泡内容跟着格变而不卡顿。 }
procedure TMainForm.EvGetCellHint(Sender: TObject; ACol, ARow: Integer;
  var AHint: string);
begin
  case ACol of
    cAmount: AHint := Format('金额 %s(含税)', [GridEvents.Cells[cAmount, ARow]]);
    cDate:   if GridEvents.Cells[cDate, ARow] = '' then AHint := '这一单还没排期'
             else AHint := '交货日期:' + GridEvents.Cells[cDate, ARow];
  else       AHint := '';      { 空串 = 这一列不弹提示 }
  end;
end;

{ 点击否决:被否决的格**光标都不会移过去** —— 不只是不发 OnClickCell。
  左键右键两条路径都过这个钩子。 }
procedure TMainForm.EvCanClickCell(Sender: TObject; ACol, ARow: Integer;
  var ACanClick: Boolean);
begin
  if ARow = 2 then ACanClick := False;
end;

{ 右键只"问"不"选":不动光标、不进编辑(与资源管理器一致)。
  先左键选中某格,再右键别处 —— 选中框不会跑。 }
procedure TMainForm.EvRightClickCell(Sender: TObject; ACol, ARow: Integer);
begin
  Status(Format('右键点在 (列 %d, 行 %d) —— 注意左边的选中框没有跟着跑',
    [ACol, ARow]));
end;

procedure TMainForm.EvHeaderClick(Sender: TObject; ACol: Integer);
begin
  Status(Format('表头点击:列 %d —— 事件先发,内建的排序照常进行(宿主搭车,不夺走默认行为)',
    [ACol]));
end;

procedure TMainForm.EvHeaderRightClick(Sender: TObject; ACol: Integer);
begin
  { 表头右键的典型用途:自适应列宽 / 隐藏列 / 清除排序。这里演示自适应。 }
  GridEvents.AutoFitColumn(ACol);
  Status(Format('表头右键:列 %d 已按内容自适应宽度', [ACol]));
end;

{ 拖动过程中每一帧都发 Sizing(可改写尺寸、也可否决),松手才发一次 EndSize。
  这里把宽度吸附到 20 的倍数 —— 拖起来能感到一格一格跳。 }
procedure TMainForm.EvColumnSizing(Sender: TObject; AIndex: Integer;
  var ANewSize: Integer; var AAllow: Boolean);
begin
  Inc(FSizingCount);
  ANewSize := (ANewSize div 20) * 20;
end;

procedure TMainForm.EvEndColumnSize(Sender: TObject; AIndex, ANewSize: Integer);
begin
  Status(Format('列 %d 宽度定为 %d —— 拖动中发了 %d 次 Sizing,松手只发这 1 次 EndSize'
    + '(宿主拿它保存列宽偏好)', [AIndex, ANewSize, FSizingCount]));
  FSizingCount := 0;
end;

procedure TMainForm.EvRowSizing(Sender: TObject; AIndex: Integer;
  var ANewSize: Integer; var AAllow: Boolean);
begin
  Inc(FSizingCount);
end;

procedure TMainForm.EvEndRowSize(Sender: TObject; AIndex, ANewSize: Integer);
begin
  { AIndex 是**数据行** —— 排序/筛选之后它仍然指向同一条记录。 }
  Status(Format('数据行 %d 高度定为 %d(拖行高要在左侧行号槽里拖)',
    [AIndex, ANewSize]));
  FSizingCount := 0;
end;

{ 钉住第 0 列:序号列永远排第一。 }
procedure TMainForm.EvColumnMove(Sender: TObject; AFromCol, AToCol: Integer;
  var AAllow: Boolean);
begin
  if (AFromCol = 0) or (AToCol = 0) then
  begin
    AAllow := False;
    Status('第 0 列被钉住了 —— 拖不动它,也没法把别的列拖到它前面');
  end
  else
    Status(Format('列换位:%d → %d', [AFromCol, AToCol]));
end;

{ 勾选框否决:点得中、光标会移过去,但勾不上 —— 与 OnCanClickCell 挡住整格不同。 }
procedure TMainForm.EvCanToggleCheck(Sender: TObject; ACol, ARow: Integer;
  var AAllow: Boolean);
begin
  if ARow mod 5 = 0 then
  begin
    AAllow := False;
    Status(Format('第 %d 行已锁定,勾不动(但光标是能移过去的)', [ARow]));
  end;
end;

{ 只在**真的切换成功之后**才发 —— 宿主不用自己再判一次有没有变。 }
procedure TMainForm.EvCheckBoxChange(Sender: TObject; ACol, ARow: Integer;
  AChecked: Boolean);
begin
  if AChecked then Status(Format('第 %d 行已勾选', [ARow]))
  else Status(Format('第 %d 行已取消勾选', [ARow]));
end;

{ 复制前改写将要进剪贴板的文本。 }
procedure TMainForm.EvClipboardCopy(Sender: TObject; var AText: string;
  var AAllow: Boolean);
begin
  AText := '// 来自 TTyStringGrid' + LineEnding + AText;
  Status('复制的内容已被钩子加上一行注释 —— 粘到记事本里看看');
end;

{ 逐格校验:数量列只收数字,非法的格直接跳过(不是整块放弃)。 }
procedure TMainForm.EvBeforePasteCell(Sender: TObject; ACol, ARow: Integer;
  var ANewText: string; var AAllow: Boolean);
var
  dummy: Double;
begin
  if ACol = cQty then
    AAllow := TryStrToFloat(Trim(ANewText), dummy);
end;

{ 逐格落地后:把被改过的格染色,粘完一眼看出动了哪些。 }
procedure TMainForm.EvAfterPasteCell(Sender: TObject; ACol, ARow: Integer);
begin
  Inc(FPasteCount);
  GridEvents.CellColors[ACol, ARow] := TyRGB(254, 240, 138);
  Status(Format('本次粘贴写入 %d 格(被改的格已染色)', [FPasteCount]));
end;

{ 从光标下一格起环绕查找,自动把命中处滚进视野;连按能不重不漏走遍全表。 }
procedure TMainForm.BtnEvFindClick(Sender: TObject);
begin
  if GridEvents.FindNext(EdEvFind.Text, False, False) then
    Status(Format('找到 —— 光标已跳到 (列 %d, 行 %d) 并滚进视野',
      [GridEvents.Col, GridEvents.Row]))
  else
    Status('没有更多匹配');
end;

procedure TMainForm.BtnEvReplaceClick(Sender: TObject);
var
  n: Integer;
begin
  n := GridEvents.ReplaceCells(EdEvFind.Text, EdEvRepl.Text, True, False, False);
  Status(Format('已替换 %d 处(只读格会被自动跳过)', [n]));
end;

{ 导入:第一行当表头自动建列、清空旧数据、并复位筛选与排序。
  这里故意用一段**带引号内换行**的 CSV —— 那是 Excel 导出的常见形态。 }
procedure TMainForm.BtnEvImportCsvClick(Sender: TObject);
const
  cSample =
    '编号,客户,备注' + LineEnding +
    '1,阿里,"第一行' + LineEnding + '第二行"' + LineEnding +
    '2,腾讯,"含,逗号的备注"' + LineEnding +
    '3,字节,普通备注';
begin
  GridEvents.LoadFromCSVText(cSample, ',');
  Status('已导入 —— 注意第 1 行的备注里**含换行**却没有把行数撑乱,逗号也没把字段切开');
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

{ ============ 页 7:单元格能力 ============

  这一页的共同点:**都挂在格子或列上**,一个绘制事件都不接。
  批注、逐格字体样式、逐格显示类型三样都存进逐格属性存储 ——
  于是它们自动可撤销、自动跟着排序/插行走,宿主什么都不用管。 }

procedure TMainForm.SetupCells;
var
  c: TTyGridColumn;
begin
  BuildOrderColumns(GridCells, True, False);
  FillOrders(GridCells, 30, True, False);

  { 勾选框列 —— 三态开关就作用在它上面。 }
  c := TTyGridColumn(GridCells.Header.Columns.Items[cDone]);
  c.EditorKind := gekCheckBox;

  { 候选列:**非编辑态也会画一个下拉箭头** —— 不点进去也看得出这格有候选项。 }
  c := TTyGridColumn(GridCells.Header.Columns.Items[cRegion]);
  c.EditorKind := gekPickList;
  c.PickList.CommaText := '华东,华北,华南,西南,东北,西北';

  GridCells.OnCellLinkClick := @CellsLinkClick;

  { 开局先放一条批注和一处加粗,免得用户对着一张干净的表猜"该点哪儿"。 }
  GridCells.CellComment[cNote, 2] := '这条是样例批注 —— 鼠标停在右上角小三角上就会显示';
  GridCells.CellFontStyles[cProduct, 2] := [fsBold];

  Status('页 7:批注/加粗/显示类型都存在逐格属性里 —— 排序、插行之后它们仍跟着原来那条记录');
end;

procedure TMainForm.ChkCellsChange(Sender: TObject);
var
  c: TTyGridColumn;
begin
  { 三态:关着时切换只在两态间走,灰显不会凭空冒出来。 }
  GridCells.AllowGrayed := ChkTriState.Checked;

  { 格式化只改**显示** —— 编辑器里、导出里都还是原值。 }
  if ChkFormat.Checked then GridCells.OnGetFormat := @CellsGetFormat
  else GridCells.OnGetFormat := nil;

  { 超链接:整列的显示类型走**列属性**,不是逐格、也不是事件。 }
  c := TTyGridColumn(GridCells.Header.Columns.Items[cOrderNo]);
  if ChkLinkCol.Checked then c.CellDisplay := gcdHyperlink
  else c.CellDisplay := gcdText;

  c := TTyGridColumn(GridCells.Header.Columns.Items[cQty]);
  if ChkColProgress.Checked then c.CellDisplay := gcdProgress
  else c.CellDisplay := gcdText;

  { 数量列只收数字:非法按键根本到不了编辑器。 }
  c := TTyGridColumn(GridCells.Header.Columns.Items[cQty]);
  if ChkDigitsOnly.Checked then c.ValidChars := '0123456789'
  else c.ValidChars := '';

  GridCells.Invalidate;
  Status('三态=' + BoolToStr(ChkTriState.Checked, '开', '关')
    + ' · 格式化=' + BoolToStr(ChkFormat.Checked, '开', '关')
    + ' · 链接列=' + BoolToStr(ChkLinkCol.Checked, '开', '关'));
end;

procedure TMainForm.BtnCommentClick(Sender: TObject);
var
  txt: string;
begin
  txt := '在 ' + FormatDateTime('hh:nn:ss', Now) + ' 加的批注';
  GridCells.CellComment[GridCells.Col, GridCells.Row] := txt;
  Status(Format('(%d, %d) 加了批注 —— 右上角多出一个小三角,悬停显示;Ctrl+Z 可撤销',
    [GridCells.Col, GridCells.Row]));
end;

procedure TMainForm.BtnCommentClearClick(Sender: TObject);
begin
  GridCells.CellComment[GridCells.Col, GridCells.Row] := '';
  Status('批注已清 —— 小三角随之消失');
end;

procedure TMainForm.BtnBoldClick(Sender: TObject);
begin
  GridCells.CellFontStyles[GridCells.Col, GridCells.Row] := [fsBold];
  Status(Format('(%d, %d) 加粗 —— 逐格字体样式,同样进撤销栈',
    [GridCells.Col, GridCells.Row]));
end;

procedure TMainForm.BtnBoldClearClick(Sender: TObject);
begin
  GridCells.CellFontStyles[GridCells.Col, GridCells.Row] := [];
  Status('已取消加粗');
end;

{ 逐格显示类型:比列级更具体,压过列级。 }
procedure TMainForm.CbCellDispChange(Sender: TObject);
const
  kinds: array[0..4] of TTyGridCellDisplay =
    (gcdText, gcdProgress, gcdRating, gcdHyperlink, gcdColor);
begin
  if CbCellDisp.ItemIndex < 0 then Exit;
  GridCells.CellDisplays[GridCells.Col, GridCells.Row] :=
    kinds[CbCellDisp.ItemIndex];
  Status(Format('(%d, %d) 的显示类型改了 —— 逐格比列级更具体,压过列级声明',
    [GridCells.Col, GridCells.Row]));
end;

procedure TMainForm.CbCaseChange(Sender: TObject);
const
  cases: array[0..2] of TEditCharCase = (ecNormal, ecUpperCase, ecLowerCase);
var
  c: TTyGridColumn;
begin
  if CbCase.ItemIndex < 0 then Exit;
  c := TTyGridColumn(GridCells.Header.Columns.Items[cOrderNo]);
  c.CharCase := cases[CbCase.ItemIndex];
  Status('订单号列的大小写规则改了 —— 双击进编辑输入就看得出来');
end;

procedure TMainForm.SpMaxLenChange(Sender: TObject);
var
  c: TTyGridColumn;
begin
  c := TTyGridColumn(GridCells.Header.Columns.Items[cNote]);
  c.MaxEditLength := SpMaxLen.Value;
  if SpMaxLen.Value = 0 then Status('备注列不限长度')
  else Status(Format('备注列最多输入 %d 个字符', [SpMaxLen.Value]));
end;

{ 只作用于显示。**别在这里改数据** —— 编辑器、导出、排序拿到的都必须是原值。 }
procedure TMainForm.CellsGetFormat(Sender: TObject; ACol, ARow: Integer;
  var AText: string);
var
  v: Double;
begin
  if ACol <> cAmount then Exit;
  if TryStrToFloat(AText, v) then AText := Format('¥ %.2f', [v]);
end;

procedure TMainForm.CellsLinkClick(Sender: TObject; ACol, ARow: Integer);
begin
  Status(Format('点了链接:%s(第 %d 行)—— 真实应用里这里会打开明细',
    [GridCells.Cells[ACol, ARow], ARow]));
end;

{ ============ 页 8:呈现与表头 ============ }

procedure TMainForm.SetupView;
begin
  BuildOrderColumns(GridView, True, False);
  FillOrders(GridView, 40, True, False);
  GridView.Header.Options := GridView.Header.Options + [hoVisible];
  Status('页 8:滚动条三态、背景图、焦点/选区显示、表头换行与分组');
end;

{ 分组带按勾选重建。**每次重建而不是增量改** —— 组是"哪几列属于同一类"的声明,
  列数/开关一变就该整体重算,增量维护只会攒出对不上的状态。 }
procedure TMainForm.ApplyHeaderGroups;
var
  g: TTyGridHeaderGroup;
begin
  GridView.HeaderGroups.Clear;
  if not ChkHdrGroups.Checked then
  begin
    GridView.Invalidate;
    Exit;
  end;

  g := GridView.HeaderGroups.Add;
  g.Text := '订单信息';
  g.FirstCol := cOrderNo; g.LastCol := cProduct; g.Level := 0;

  g := GridView.HeaderGroups.Add;
  g.Text := '金额与进度';
  g.FirstCol := cQty; g.LastCol := cRate; g.Level := 0;

  { 第二级:Level=1 画在 0 级下面那一条里。分组带会自动长高一条。 }
  if ChkHdrGroups2.Checked then
  begin
    g := GridView.HeaderGroups.Add;
    g.Text := '主键与归属';
    g.FirstCol := cOrderNo; g.LastCol := cRegion; g.Level := 1;

    g := GridView.HeaderGroups.Add;
    g.Text := '数量/金额';
    g.FirstCol := cQty; g.LastCol := cAmount; g.Level := 1;
  end;
  GridView.Invalidate;
end;

procedure TMainForm.ChkViewChange(Sender: TObject);
begin
  { 背景图:宿主建、宿主释放。 }
  if ChkBackImage.Checked then
  begin
    if FBackBmp = nil then FBackBmp := MakeWatermark;
    GridView.BackgroundBitmap := FBackBmp;
  end
  else
    GridView.BackgroundBitmap := nil;

  GridView.ShowFocusCell := ChkFocusCell.Checked;
  GridView.HideSelectionWhenInactive := ChkDimInactive.Checked;
  GridView.HeaderWordWrap := ChkHdrWrap.Checked;
  GridView.HeaderAutoHeight := ChkHdrAuto.Checked;

  if ChkFixBottom.Checked then GridView.FixedRowsBottom := 1
  else GridView.FixedRowsBottom := 0;
  if ChkFixRight.Checked then GridView.FixedColsRight := 1
  else GridView.FixedColsRight := 0;

  ApplyHeaderGroups;
  Status('表头换行=' + BoolToStr(ChkHdrWrap.Checked, '开', '关')
    + ' · 自适应高度=' + BoolToStr(ChkHdrAuto.Checked, '开', '关')
    { 级数由**宿主自己**算 —— 分组是宿主建的,它本来就知道有几级;
      为了一句状态文案去扩控件的公开面是本末倒置。 }
    + ' · 分组级数=' + IntToStr(HeaderGroupLevels));
end;

procedure TMainForm.CbScrollChange(Sender: TObject);
const
  modes: array[0..2] of TTyGridScrollBarMode = (gsbAuto, gsbAlways, gsbNever);
begin
  if CbVScroll.ItemIndex >= 0 then
    GridView.VertScrollBarMode := modes[CbVScroll.ItemIndex];
  if CbHScroll.ItemIndex >= 0 then
    GridView.HorzScrollBarMode := modes[CbHScroll.ItemIndex];
  Status('滚动条「隐藏」只是不显示 —— 滚轮、方向键、PageDown 照样走得到底');
end;

procedure TMainForm.CbBackChange(Sender: TObject);
const
  bmodes: array[0..2] of TTyGridBackgroundMode = (gbmTile, gbmStretch, gbmCenter);
  scopes: array[0..1] of TTyGridBackgroundScope = (gbsWholeGrid, gbsBodyOnly);
begin
  if CbBackMode.ItemIndex >= 0 then
    GridView.BackgroundMode := bmodes[CbBackMode.ItemIndex];
  if CbBackScope.ItemIndex >= 0 then
    GridView.BackgroundScope := scopes[CbBackScope.ItemIndex];
  Status('范围决定图被**适配到哪个矩形** —— 列头带每帧都被重画,底下铺什么都看不见');
end;

procedure TMainForm.BtnLongCaptionClick(Sender: TObject);
var
  c: TTyColumn;
begin
  c := TTyColumn(GridView.Header.Columns.Items[cNote]);
  if Pos('换行', c.Text) > 0 then c.Text := '备注'
  else c.Text := '这是一个很长的列标题 用来演示换行与自适应高度';
  GridView.Invalidate;
  Status('再勾「表头换行」和「表头高度自适应」看效果');
end;

function TMainForm.HeaderGroupLevels: Integer;
var
  i, lv: Integer;
begin
  Result := 0;
  for i := 0 to GridView.HeaderGroups.Count - 1 do
  begin
    lv := TTyGridHeaderGroup(GridView.HeaderGroups.Items[i]).Level;
    if lv + 1 > Result then Result := lv + 1;
  end;
end;

{ 一张淡淡的水印图。用代码生成而不是带一个图片文件:
  例子要能直接跑起来,不该依赖外部资源。 }
function TMainForm.MakeWatermark: TBGRABitmap;
var
  i: Integer;
begin
  Result := TBGRABitmap.Create(120, 120, BGRA(0, 0, 0, 0));
  for i := 0 to 119 do
  begin
    Result.SetPixel(i, i, BGRA(120, 160, 220, 40));
    Result.SetPixel(119 - i, i, BGRA(120, 160, 220, 40));
  end;
end;

{ ============ 页 9:数据进出 ============

  统一的分寸:导出走**显示序**(排序/筛选/折叠之后导出的就是屏幕上那些),
  导入默认是替换式,追加是显式选项。 }

procedure TMainForm.SetupIo;
begin
  BuildOrderColumns(GridIo, True, False);
  FillOrders(GridIo, 25, True, False);
  GridIo.SetColumnAggregate(cQty, gagSum);
  GridIo.SetColumnAggregate(cAmount, gagSum);
  Status('页 9:导出/导入/流往返/页脚接管');
end;

procedure TMainForm.ChkIoChange(Sender: TObject);
begin
  if ChkIoFooterHook.Checked then GridIo.OnGetFooterText := @IoGetFooterText
  else GridIo.OnGetFooterText := nil;

  if ChkIoColCalc.Checked then GridIo.OnColumnCalc := @IoColumnCalc
  else GridIo.OnColumnCalc := nil;

  GridIo.Invalidate;
  Status('页脚钩子=' + BoolToStr(ChkIoFooterHook.Checked, '开', '关')
    + ' · 金额列接管=' + BoolToStr(ChkIoColCalc.Checked, '开', '关'));
end;

procedure TMainForm.BtnIoJsonClick(Sender: TObject);
var
  js: string;
begin
  js := GridIo.SaveToJSONText;
  TyShowMessage('JSON 导出(前 800 字):' + LineEnding + LineEnding + Copy(js, 1, 800));
  Status(Format('导出了 %d 字节 JSON —— 键取列标题,只导可见行', [Length(js)]));
end;

procedure TMainForm.BtnIoHtmlClick(Sender: TObject);
var
  h: string;
begin
  h := GridIo.SaveToHTMLText;
  TyShowMessage('HTML 导出(前 800 字):' + LineEnding + LineEnding + Copy(h, 1, 800));
  Status(Format('导出了 %d 字节 HTML', [Length(h)]));
end;

{ 同一个方法,加上行列范围参数就是"只导选区"。 }
procedure TMainForm.BtnIoCsvSelClick(Sender: TObject);
var
  sel: TRect;
  csv: string;
begin
  sel := GridIo.Selection;
  csv := GridIo.SaveToCSVText(',', sel.Top, sel.Bottom - sel.Top + 1,
                                   sel.Left, sel.Right - sel.Left + 1);
  TyShowMessage('选区 CSV:' + LineEnding + LineEnding + Copy(csv, 1, 800));
  Status(Format('导出了选区 %d 行 x %d 列',
    [sel.Bottom - sel.Top + 1, sel.Right - sel.Left + 1]));
end;

{ 存进内存流再读回来 —— 证明流接口两头对得上。 }
procedure TMainForm.BtnIoStreamClick(Sender: TObject);
var
  st: TMemoryStream;
  before: Integer;
begin
  before := GridIo.RowCount;
  st := TMemoryStream.Create;
  try
    GridIo.SaveToStream(st);
    st.Position := 0;
    GridIo.LoadFromStream(st);
    Status(Format('流往返一圈:%d 行 → %d 字节 → %d 行',
      [before, st.Size, GridIo.RowCount]));
  finally
    st.Free;
  end;
end;

procedure TMainForm.BtnIoSelTextClick(Sender: TObject);
begin
  TyShowMessage('选区文本(制表符分隔,没碰剪贴板):' + LineEnding + LineEnding
    + Copy(GridIo.SelectionAsText, 1, 800));
end;

{ 不经过剪贴板直接粘一块进来 —— 这样粘贴钩子在没有外部剪贴板的环境也演示得了。 }
procedure TMainForm.BtnIoPasteTextClick(Sender: TObject);
const
  blk = 'AAA'#9'华东'#9'甲产品'#13#10'BBB'#9'华北'#9'乙产品';
begin
  GridIo.PasteFromText(blk);
  Status('从一段硬编码文本粘进来了 2 行 —— 走的是与剪贴板同一条路径');
end;

procedure TMainForm.BtnIoClearRowsClick(Sender: TObject);
var
  sel: TRect;
begin
  sel := GridIo.Selection;
  GridIo.ClearRows(sel.Top, sel.Bottom - sel.Top + 1);
  Status(Format('清空了 %d 行的内容 —— 整批算**一条**撤销记录,按一次 Ctrl+Z 就回来',
    [sel.Bottom - sel.Top + 1]));
end;

procedure TMainForm.BtnIoClearColsClick(Sender: TObject);
begin
  GridIo.ClearCols(GridIo.Col, 1);
  Status(Format('清空了第 %d 列 —— 同样是一条撤销记录', [GridIo.Col]));
end;

{ 追加 / 最多读几行 / 跳过前几行,三个参数一起演示。 }
procedure TMainForm.BtnIoImportClick(Sender: TObject);
const
  csv = '订单号,大区,产品,数量,金额' + LineEnding
      + '# 这一行是说明,不是数据' + LineEnding
      + 'IMP-001,华东,甲产品,10,1285.00' + LineEnding
      + 'IMP-002,华北,乙产品,20,2570.00' + LineEnding
      + 'IMP-003,华南,丙产品,30,3855.00' + LineEnding
      + 'IMP-004,西南,丁产品,40,5140.00';
var
  before, maxRows: Integer;
begin
  before := GridIo.RowCount;
  maxRows := SpIoMax.Value;
  if maxRows = 0 then maxRows := -1;      { 0 = 不限 }
  GridIo.LoadFromCSVText(csv, ',', ChkIoAppend.Checked, maxRows, SpIoSkip.Value);
  Status(Format('导入:%d 行 → %d 行(%s,最多 %s 行,跳过 %d 行说明)',
    [before, GridIo.RowCount,
     BoolToStr(ChkIoAppend.Checked, '追加', '替换'),
     BoolToStr(maxRows < 0, '不限', IntToStr(maxRows)), SpIoSkip.Value]));
end;

procedure TMainForm.BtnIoRecalcClick(Sender: TObject);
begin
  GridIo.CalcFooter(cAmount);
  GridIo.Invalidate;
  Status('只让金额那一列重算 —— 整表失效(InvalidateAggregates)对这件事太钝');
end;

procedure TMainForm.IoGetFooterText(Sender: TObject; ACol: Integer;
  var AText: string);
begin
  if (ACol = cAmount) and (AText <> '') then AText := '合计 ¥' + AText;
end;

{ 宿主接管这一列的汇总。**不进缓存** —— 外部数据变了控件收不到通知,
  缓存住就等于把一个陈旧的数钉在页脚上。 }
procedure TMainForm.IoColumnCalc(Sender: TObject; ACol: Integer;
  var AValue: Double; var AHandled: Boolean);
var
  vals: array of Double;
  pos, dataRow, n: Integer;
  v: Double;
  i, j: Integer;
  t: Double;
begin
  if ACol <> cAmount then Exit;
  SetLength(vals, 0);
  n := 0;
  for pos := 0 to GridIo.DisplayRowCount - 1 do
  begin
    dataRow := GridIo.DisplayToData(pos);
    if dataRow < 0 then Continue;
    if TryStrToFloat(GridIo.Cells[ACol, dataRow], v) then
    begin
      SetLength(vals, n + 1);
      vals[n] := v;
      Inc(n);
    end;
  end;
  if n = 0 then Exit;
  for i := 0 to n - 2 do
    for j := 0 to n - 2 - i do
      if vals[j] > vals[j + 1] then
      begin
        t := vals[j]; vals[j] := vals[j + 1]; vals[j + 1] := t;
      end;
  if n mod 2 = 1 then AValue := vals[n div 2]
  else AValue := (vals[n div 2 - 1] + vals[n div 2]) / 2;
  AHandled := True;
end;

{ ============ 页 6 补齐的钩子 ============

  与本页原有的开关同一个约定:**每个开关对应一个钩子**,勾上再去操作,
  状态栏会说出它介入了什么。 }

procedure TMainForm.ChkEv3Change(Sender: TObject);
var
  c: TTyGridColumn;
begin
  if ChkEvReturn.Checked then
  begin
    GridEvents.OnReturn := @EvReturn;
    GridEvents.OnCtrlReturn := @EvCtrlReturn;
  end
  else
  begin
    GridEvents.OnReturn := nil;
    GridEvents.OnCtrlReturn := nil;
  end;

  if ChkEvScrollHint.Checked then GridEvents.OnScrollHint := @EvScrollHint
  else GridEvents.OnScrollHint := nil;

  if ChkEvCanEdit.Checked then GridEvents.OnCanEditCell := @EvCanEdit
  else GridEvents.OnCanEditCell := nil;

  if ChkEvEditChange.Checked then GridEvents.OnEditChange := @EvEditChange
  else GridEvents.OnEditChange := nil;

  if ChkEvCellEdited.Checked then GridEvents.OnCellEdited := @EvCellEdited
  else GridEvents.OnCellEdited := nil;

  if ChkEvRowVeto.Checked then
  begin
    GridEvents.OnCanInsertRow := @EvCanInsertRow;
    GridEvents.OnCanDeleteRow := @EvCanDeleteRow;
  end
  else
  begin
    GridEvents.OnCanInsertRow := nil;
    GridEvents.OnCanDeleteRow := nil;
  end;

  if ChkEvSelectCell.Checked then GridEvents.OnSelectCell := @EvSelectCell
  else GridEvents.OnSelectCell := nil;

  if ChkEvClick.Checked then
  begin
    GridEvents.OnClickCell := @EvClickCell;
    GridEvents.OnDblClickCell := @EvDblClickCell;
  end
  else
  begin
    GridEvents.OnClickCell := nil;
    GridEvents.OnDblClickCell := nil;
  end;

  if ChkEvRating.Checked then GridEvents.OnRatingChange := @EvRatingChange
  else GridEvents.OnRatingChange := nil;

  if ChkEvCanSort.Checked then GridEvents.OnCanSort := @EvCanSort
  else GridEvents.OnCanSort := nil;

  if ChkEvCompare.Checked then GridEvents.OnCompareCells := @EvCompareCells
  else GridEvents.OnCompareCells := nil;

  if ChkEvFilterRow.Checked then GridEvents.OnFilterRow := @EvFilterRow
  else GridEvents.OnFilterRow := nil;

  if ChkEvFilterVals.Checked then
    GridEvents.OnGetFilterValues := @EvGetFilterValues
  else GridEvents.OnGetFilterValues := nil;

  { 动态候选项:挂上事件之后,列上那份静态 PickList 就不再说了算。 }
  c := TTyGridColumn(GridEvents.Header.Columns.Items[cRegion]);
  c.EditorKind := gekPickList;
  if ChkEvPickList.Checked then GridEvents.OnGetPickList := @EvGetPickList
  else GridEvents.OnGetPickList := nil;

  GridEvents.Invalidate;
  Status('钩子开关已应用 —— 去操作网格,这一行会说出钩子介入了什么');
end;

procedure TMainForm.EvReturn(Sender: TObject; ACol, ARow: Integer);
begin
  Status(Format('回车:打开第 %d 行的明细(编辑态的回车仍是"提交并下移",没被改掉)',
    [ARow]));
end;

procedure TMainForm.EvCtrlReturn(Sender: TObject; ACol, ARow: Integer);
begin
  Status(Format('Ctrl+回车:第 %d 行 —— 另一个动作,与普通回车分开', [ARow]));
end;

procedure TMainForm.EvScrollHint(Sender: TObject; ARow: Integer;
  var AHint: string);
begin
  AHint := Format('第 %d 行 / 共 %d 行', [ARow + 1, GridEvents.RowCount]);
end;

{ 与"只读"的区别:被拦下的格子**照样按原来的样子显示**(勾选框还是勾选框),
  只是改不动。做成 gekNone 会把显示也一起改掉。 }
procedure TMainForm.EvCanEdit(Sender: TObject; ACol, ARow: Integer;
  var AAllow: Boolean);
begin
  if ARow = 2 then
  begin
    AAllow := False;
    Status('第 2 行禁改 —— 注意它的勾选框仍然画成勾选框,只是点不动');
  end;
end;

procedure TMainForm.EvEditChange(Sender: TObject; ACol, ARow: Integer;
  const AText: string);
begin
  Status(Format('正在输入 (%d, %d):「%s」—— 每敲一下就发一次,不是提交时',
    [ACol, ARow, AText]));
end;

procedure TMainForm.EvCellEdited(Sender: TObject; ACol, ARow: Integer;
  const AOldText, ANewText: string; var AAccept: Boolean);
begin
  if Trim(ANewText) = '' then
  begin
    AAccept := False;
    Status(Format('(%d, %d) 不许清空 —— 提交被否决,格子还是「%s」',
      [ACol, ARow, AOldText]));
  end
  else
    Status(Format('(%d, %d):「%s」→「%s」', [ACol, ARow, AOldText, ANewText]));
end;

procedure TMainForm.EvCanInsertRow(Sender: TObject; ARow: Integer;
  var AAllow: Boolean);
begin
  AAllow := False;
  Status('插入被否决 —— 一行都没插进去(复数版里任何一行被否决就整批不做)');
end;

procedure TMainForm.EvCanDeleteRow(Sender: TObject; ARow: Integer;
  var AAllow: Boolean);
begin
  AAllow := False;
  Status('删除被否决');
end;

procedure TMainForm.EvSelectCell(Sender: TObject; ACol, ARow: Integer;
  var ACanSelect: Boolean);
begin
  if ACol = 0 then
  begin
    ACanSelect := False;
    Status('光标进不了第 0 列 —— 方向键会直接跳过它');
  end;
end;

procedure TMainForm.EvClickCell(Sender: TObject; ACol, ARow: Integer);
begin
  Status(Format('单击 (%d, %d)', [ACol, ARow]));
end;

procedure TMainForm.EvDblClickCell(Sender: TObject; ACol, ARow: Integer);
begin
  Status(Format('双击 (%d, %d) —— 真实应用里这里通常是"打开明细"', [ACol, ARow]));
end;

procedure TMainForm.EvRatingChange(Sender: TObject; ACol, ARow: Integer;
  AValue: Integer);
begin
  Status(Format('评分改成 %d 星(第 %d 行)—— 点第几颗星就是几分,不弹编辑器',
    [AValue, ARow]));
end;

{ 接服务端排序时的必需品:拦下本地排序,自己去请求。 }
procedure TMainForm.EvCanSort(Sender: TObject; ACol: Integer;
  var AAllow: Boolean);
begin
  if ACol = cRegion then
  begin
    AAllow := False;
    Status('大区列不许本地排序 —— 真实场景里这里会转成一次服务端请求');
  end;
end;

{ 按业务顺序排,而不是按字面。 }
procedure TMainForm.EvCompareCells(Sender: TObject; ACol, ARow1, ARow2: Integer;
  var AResult: Integer);
const
  order: array[0..5] of string = ('华东', '华北', '华南', '西南', '东北', '西北');

  function Rank(const AText: string): Integer;
  var i: Integer;
  begin
    for i := 0 to High(order) do
      if order[i] = AText then Exit(i);
    Result := High(order) + 1;
  end;

begin
  if ACol <> cRegion then Exit;
  AResult := Rank(GridEvents.Cells[ACol, ARow1])
           - Rank(GridEvents.Cells[ACol, ARow2]);
end;

procedure TMainForm.EvFilterRow(Sender: TObject; ARow: Integer;
  var AVisible: Boolean);
var
  v: Double;
begin
  AVisible := TryStrToFloat(GridEvents.Cells[cAmount, ARow], v) and (v < 0);
end;

{ 虚拟表/服务端场景:候选值不该靠遍历全表得来。 }
procedure TMainForm.EvGetFilterValues(Sender: TObject; ACol: Integer;
  AItems: TStrings; var AHandled: Boolean);
begin
  if ACol <> cRegion then Exit;
  AItems.Clear;
  AItems.Add('华东');
  AItems.Add('华北');
  AItems.Add('(服务端还有更多)');
  AHandled := True;
end;

procedure TMainForm.EvGetPickList(Sender: TObject; ACol, ARow: Integer;
  AItems: TStrings);
begin
  if ACol <> cRegion then Exit;
  AItems.Clear;
  { 逐格给不同的候选 —— 静态 PickList 做不到这件事。 }
  if ARow mod 2 = 0 then AItems.CommaText := '华东,华北,华南'
  else AItems.CommaText := '西南,东北,西北';
end;

end.
