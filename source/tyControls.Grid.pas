{ 自绘数据网格 —— 控件本体。

  设计见 docs/design/2026-07-18-grid-control.md。类层次:
      TTyCustomGrid   本单元:几何/窗格/滚动/选择/绘制管线/键鼠/主题(不含数据)
        TTyDrawGrid   纯自绘:内容由 OnDrawCell / OnGetCellText 提供
        TTyStringGrid 完整体:单元格存储 + 编辑 + 排序/过滤/分组/合并 + 剪贴板

  刻意的分工:
  * **列模型**整份复用 tyControls.Columns(TTyHeader/TTyColumns)—— 列宽约束、位置↔索引
    映射、分隔条命中、自动适宽、弹性分配都已在那里实现且有无头测试。
  * **纯几何**放在 tyControls.Grid.Layout(窗格切分、行矩形、虚拟化窗口、行轴命中),
    本单元只负责把控件状态装配成 TTyGridMetrics 再调用它。

  本控件为独立实现,不含任何第三方网格的代码。 }
unit tyControls.Grid;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, contnrs, Clipbrd, Controls, Graphics, LCLType, LMessages, StdCtrls,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Columns,
  tyControls.ScrollBar, tyControls.Edit, tyControls.ComboBox, tyControls.DateTimePicker, tyControls.Popover, tyControls.CheckListBox, tyControls.ColorMath,
  tyControls.SpinEdit, tyControls.TrackBar, tyControls.Memo, tyControls.MaskEdit,
  tyControls.CalcEdit, tyControls.Panel, tyControls.Button, tyControls.CheckBox,
  tyControls.Css.Values, tyControls.ImageCollection, tyControls.Dialogs.Color,
  tyControls.StrConsts,
  tyControls.Grid.Layout;

type
  { 列头筛选下拉里的值列表:每个值右侧显示"有多少行是这个值"。

    计数不能存进 Items.Objects —— 那里放的是勾选状态(TTyCheckListBox 就是这么
    存的,好让状态跟着 Sorted/Delete 一起走)。所以另存一份平行数组,
    与 Items 一起整体重建(搜索框每改一次就重建一次,不存在漂移窗口)。 }
  TTyGridFilterList = class(TTyCheckListBox)
  private
    FCounts: array of Integer;
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  public
    procedure SetCounts(const ACounts: array of Integer);
  end;

  TTyGridCellDisplay = (
    gcdText,      { 默认:文字 }
    gcdProgress,  { 进度条,值取 0..100 }
    gcdRating,    { 评分星,值取 0..5 }
    gcdImage,     { 图片:值是 Images 里的索引 }
    gcdButton,    { 按钮:文字是按钮标题,点击走 OnCellButtonClick }
    gcdColor      { 色块:值是 '#RRGGBB'。与 gekColor 编辑器配对 ——
                    从前只有编辑侧、没有显示侧,那一列看起来就是一串脏数据 }
  );

  { 编辑器种类与聚合方式 —— 放在 type 段最前面,因为列类要用它们。 }
  TTyGridEditorKind = (
    gekNone,      { 该格只读 }
    gekText,      { 普通文本 }
    gekNumeric,   { 只收数字(含负号与小数点) }
    gekCheckBox,  { 勾选框:不弹编辑器,点一下就切换 }
    gekPickList,  { 下拉选取:从 OnGetPickList 给的候选里选 }
    gekDate,      { 日期:弹日期选择器 }
    gekColor,     { 颜色:弹取色对话框,值存 #RRGGBB }
    { 以下几种都是把库里**现成的控件**接进来当编辑器,不是另造一套。 }
    gekSpin,      { 数值微调:TTySpinEdit,范围取列的 MinValue/MaxValue }
    gekSlider,    { 滑动条:TTyTrackBar,范围同上 }
    gekRating,    { 星级:**点哪颗星就是几分**,不弹编辑器(与勾选框同一种手感) }
    gekMemo,      { 多行文本:TTyMemo }
    gekMask,      { 掩码:TTyMaskEdit,掩码取列的 EditMask }
    gekTime,      { 时间:TTyDateTimePicker 的 dtkTime }
    gekPassword,  { 密码:TTyEdit 的 PasswordChar }
    gekCalculator,{ 带计算器的数值:TTyCalcEdit }
    gekEllipsis   { 文本 + 格右缘一个"…"按钮:点按钮走 OnEllipsisClick,
                    宿主爱弹什么对话框弹什么。对标 AdvGrid 的 edEditBtn ——
                    它那一族里最常用的一个。文字本身照常可以行内编辑。 }
  );

  { 单元格的**显示**方式(与编辑方式正交:一个格可以显示成进度条、编辑时仍是数值框)。 }
  TTyGridGetCellDisplayEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var ADisplay: TTyGridCellDisplay) of object;

  { 完全自绘一个单元格。置 AHandled:=True 即接管该格,控件不再画它的内容
    (背景与选中底色仍由控件先铺好,所以宿主只需画自己那部分)。 }
  TTyGridDrawCellEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    const ARect: TRect; APainter: TTyPainter; var AHandled: Boolean) of object;

  { 单元格提示(悬停显示)。返回空串 = 该格无提示。 }
  TTyGridGetCellHintEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var AHint: string) of object;

  { 逐行行高(逻辑像素)。不接 = 全部用 DefaultRowHeight。 }
  TTyGridGetRowHeightEvent = procedure(Sender: TObject; ARow: Integer;
    var AHeight: Integer) of object;

  { 排序比较方式。 }
  { 排序时怎么比。gskAuto 只在**列级**有意义 —— 表示"沿用网格的 SortKind"。 }
  TTyGridSortKind = (gskText, gskNumber, gskDate, gskAuto);

  { 选择粒度。gsmCell = 单元格矩形选区(默认);gsmRow = 整行;gsmColumn = 整列。 }
  TTyGridSelectionMode = (gsmCell, gsmRow, gsmColumn);

  { 列聚合方式(汇总带用)。一律只统计**通过过滤的行** —— 筛完总计要跟着变。 }
  TTyGridAggregate = (gagNone, gagSum, gagAvg, gagMin, gagMax, gagCount);

  { 宿主自带编辑器的扩展点。

    内建的三种编辑器(文本 / 下拉 / 日期)与两个模态动作(颜色 / 勾选)继续走
    网格自己那条路 —— **刻意不把它们改写成 EditLink**:它们已经被一整批测试盯着,
    重写只为"形式统一"而没有用户可见的收益,风险却是实打实的。
    EditLink 是给"网格答不上来的编辑器"准备的逃生口(自定义控件、第三方控件)。

    生命周期:BeginEdit 时 CreateEditor → SetBounds → SetValue → FocusEditor;
    EndEdit(True) 时 GetValue 写回;控件由 EditLink 自己负责释放。 }
  TTyGridEditLink = class
  public
    { 造一个编辑控件并挂到 AParent 上。返回 nil = 放弃编辑。 }
    function  CreateEditor(AParent: TWinControl; ACol, ARow: Integer): TWinControl; virtual; abstract;
    procedure SetBounds(const ARect: TRect); virtual; abstract;
    function  GetValue: string; virtual; abstract;
    procedure SetValue(const AValue: string); virtual; abstract;
    procedure FocusEditor; virtual; abstract;
    { 返回 True = 这个键被编辑器吃掉了,网格不再处理。 }
    function  HandleKey(var AKey: Word; AShift: TShiftState): Boolean; virtual;
    procedure ReleaseEditor; virtual; abstract;
  end;

  { 宿主给某一格提供 EditLink。留 nil = 用内建编辑器。 }
  TTyGridCreateEditLinkEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var ALink: TTyGridEditLink) of object;

  { 一条**表头分组**:横跨若干相邻列的上层标题。

    模型刻意做成"平铺一层组"而不是任意深的树:真实报表里两级(分组 + 列)覆盖了
    绝大多数场景,而任意深的树会把命中、拖列、排序按钮归属全部复杂化一个量级。
    需要三级时把组再套一层即可(Level 属性留着),但默认只画两级。

    FirstCol/LastCol 是**列索引**区间(闭区间)。列被拖动重排后组会跟着断开 ——
    这是对的:组的含义是"这几列属于同一类",顺序变了就不再是同一类。 }
  TTyGridHeaderGroup = class(TCollectionItem)
  private
    FText:      string;
    FFirstCol:  Integer;
    FLastCol:   Integer;
    FLevel:     Integer;
    FAlignment: TAlignment;
    procedure Changed;
    procedure SetText(const AValue: string);
    procedure SetFirstCol(AValue: Integer);
    procedure SetLastCol(AValue: Integer);
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(ASource: TPersistent); override;
  published
    property Text: string read FText write SetText;
    property FirstCol: Integer read FFirstCol write SetFirstCol default 0;
    property LastCol: Integer read FLastCol write SetLastCol default 0;
    { 第几级(0 = 最上面那条带)。目前只画 0 级。 }
    property Level: Integer read FLevel write FLevel default 0;
    property Alignment: TAlignment read FAlignment write FAlignment default taCenter;
  end;

  TTyGridHeaderGroups = class(TCollection)
  private
    FOnChange: TNotifyEvent;
  protected
    procedure Update(AItem: TCollectionItem); override;
  public
    constructor Create;
    function Add: TTyGridHeaderGroup;
    { 覆盖 ACol 的那条组(没有就返回 nil)。 }
    function GroupAt(ALevel, ACol: Integer): TTyGridHeaderGroup;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { 网格线要画哪几轴。只要横线的报表式表格很常见,从前只有一个全有/全无的开关。 }
  TTyGridLineStyle = (glsNone, glsHorizontal, glsVertical, glsBoth);

  { 空值排在最前还是最后。翻方向时**位置不变** —— 否则一翻向,空行就冒到最上面。 }
  TTyGridBlanksPosition = (gbpLast, gbpFirst);

  { 过滤条件的比较方式。从前只有"包含"一种 —— 数值列想筛 >1000 完全做不到。 }
  TTyGridFilterOp = (
    gfoContains,     { 默认:包含(不区分大小写) }
    gfoEquals,
    gfoNotEquals,
    gfoStartsWith,
    gfoEndsWith,
    gfoGreater,      { 以下四个按**数值**比;非数值格一律不通过 }
    gfoGreaterEqual,
    gfoLess,
    gfoLessEqual);

  { 一个排序键。多列排序 = 一串键,前面的相等才看后面的。 }
  TTyGridSortKey = record
    Col: Integer;
    Dir: TTySortDirection;
  end;
  TTyGridSortKeys = array of TTyGridSortKey;

  { 网格自己的列。

    **不往共享的 TTyColumn 里塞网格专属字段** —— 它同时被 ListView / TreeView 用着,
    多一个字段就多一份"这三个控件都得管"的负担。派生一个网格自己的列类,
    网格的 TTyColumns 创建它;共享单元只多了一个"可以指定列类"的构造重载。

    有了列级属性,设计期不接任何事件就能配出"这列数字、那列下拉、这列只读"。 }
  TTyGridColumn = class(TTyColumn)
  private
    FEditorKind: TTyGridEditorKind;
    FReadOnly:   Boolean;
    FPickList:   TStrings;
    FAggregate:  TTyGridAggregate;
    FFormat:     string;
    FValidChars: string;
    FMaxEditLength: Integer;
    FSortKind: TTyGridSortKind;
    FMinValue: Integer;
    FMaxValue: Integer;
    FEditMask: string;
    FCharCase: TEditCharCase;
    FUseEditorKind: Boolean;
    procedure SetPickList(AValue: TStrings);
    procedure SetEditorKind(AValue: TTyGridEditorKind);
  public
    constructor Create(ACollection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(ASource: TPersistent); override;
    { 有没有显式设过 EditorKind。没设过就让宿主事件/网格默认值说了算 ——
      光看"等于 gekText"分不清"没设"和"显式设成文本"。 }
    property UseEditorKind: Boolean read FUseEditorKind write FUseEditorKind;
  published
    { gekSpin / gekSlider 的取值范围。 }
    property MinValue: Integer read FMinValue write FMinValue default 0;
    property MaxValue: Integer read FMaxValue write FMaxValue default 100;
    { gekMask 的掩码 —— 交给 TTyMaskEdit 解释,不自造一套掩码语法。 }
    property EditMask: string read FEditMask write FEditMask;
    { 输入时强制大小写(对标 AdvGrid 的 edUpperCase / edLowerCase)。 }
    property CharCase: TEditCharCase read FCharCase write FCharCase default ecNormal;
    { 只允许输入这些字符(空 = 不限)。按键级过滤,非法键直接不进编辑框。 }
    property ValidChars: string read FValidChars write FValidChars;
    { 编辑框最多输入几个字符(0 = 不限)。 }
    property MaxEditLength: Integer read FMaxEditLength write FMaxEditLength default 0;
    { 这一列用什么编辑器。设过之后优先级高于 DefaultEditorKind,低于 OnGetEditorKind。 }
    property EditorKind: TTyGridEditorKind read FEditorKind write SetEditorKind
      default gekText;
    { 整列只读。 }
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    { gekPickList 的候选项(不接 OnGetPickList 时用这个)。 }
    property PickList: TStrings read FPickList write SetPickList;
    { 这一列按什么比。混合表里日期列按文本排会得到 '10/1' < '2/1' —— 排序方式
      本来就该跟着列走,而不是全表一个开关。gskAuto = 沿用网格的 SortKind。 }
    property SortKind: TTyGridSortKind read FSortKind write FSortKind default gskAuto;
    { 汇总带上这一列显示什么统计。 }
    property Aggregate: TTyGridAggregate read FAggregate write FAggregate
      default gagNone;
    { 显示用的格式串(FormatFloat/FormatDateTime 语义,由派生网格解释)。 }
    property Format: string read FFormat write FFormat;
  end;

  { 一格显示成什么。放在这里(而不是 TTyStringGrid 那段)是因为基类要用它
    判断按钮格的命中矩形。 }

  { 单元格级鼠标事件。ACol/ARow 是**数据行**。 }
  TTyGridCellMouseEvent = procedure(Sender: TObject; ACol, ARow: Integer) of object;
  { 否决一次点击。置 ACanClick:=False 会让**整次点击**作废 ——
    光标不动、不进编辑、不切勾选、不触发 OnClickCell。
    只挡住 OnClickCell 而让光标照样跑,是最容易写出来的半吊子实现。 }
  TTyGridCanClickCellEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var ACanClick: Boolean) of object;
  TTyGridHeaderMouseEvent = procedure(Sender: TObject; ACol: Integer) of object;
  { 能不能按这一列排。置 AAllow:=False 拦下 —— 接服务端排序时的必需品。 }
  TTyGridCanSortEvent = procedure(Sender: TObject; ACol: Integer;
    var AAllow: Boolean) of object;
  { 逐格边框。四支笔各自可开可关,宽度/颜色独立 —— 报表要画分区块粗线、小计行双线。 }
  TTyGridCellBorders = record
    Left, Top, Right, Bottom: Boolean;
    Width: Integer;
    Color: TTyColor;
  end;
  TTyGridGetCellBorderEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var ABorders: TTyGridCellBorders) of object;

  { 表头格自绘钩子:必填列表头标红、当前排序列高亮。 }
  TTyGridGetHeaderStyleEvent = procedure(Sender: TObject; ACol: Integer;
    var ABackground: TTyFill; var ATextColor: TTyColor;
    var AFontName: string; var AFontSize, AFontWeight: Integer) of object;

  { 列宽 / 行高的交互事件。ASizing 阶段可以改 ANewSize 或否决。 }
  TTyGridSizingEvent = procedure(Sender: TObject; AIndex: Integer;
    var ANewSize: Integer; var AAllow: Boolean) of object;
  TTyGridSizedEvent = procedure(Sender: TObject; AIndex, ANewSize: Integer) of object;
  { 列被拖动重排。 }
  TTyGridColumnMoveEvent = procedure(Sender: TObject; AFromCol, AToCol: Integer;
    var AAllow: Boolean) of object;

  { 内置控件单元格的交互事件。勾选框一勾就该能触发宿主逻辑,
    而不是逼宿主去 OnCellEdited 里认字符串。 }
  TTyGridCanToggleEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var AAllow: Boolean) of object;
  { 省略号按钮被点。宿主在这里弹自己的对话框,把结果写进 ANewText;
    置 AAccept:=False 表示用户取消了。 }
  TTyGridEllipsisEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var ANewText: string; var AAccept: Boolean) of object;
  TTyGridCheckChangeEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    AChecked: Boolean) of object;
  TTyGridRatingChangeEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    AValue: Integer) of object;

  { 复制/粘贴前后的钩子。置 AAllow:=False 可整体拦下。 }
  TTyGridClipboardEvent = procedure(Sender: TObject; var AText: string;
    var AAllow: Boolean) of object;
  { 逐格粘贴。ANewText 可改写,AAllow:=False 跳过这一格。 }
  TTyGridPasteCellEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var ANewText: string; var AAllow: Boolean) of object;

  { 这一格要不要换行显示。 }
  TTyGridGetCellWordWrapEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var AWordWrap: Boolean) of object;

  { 逐格外观钩子:宿主按数据决定某一格长什么样(负数标红、超期标黄……)。
    一个钩子覆盖底色/文字色/字体/两轴对齐 —— 分成七八个事件对宿主更难用。
    ARow 是**数据行**,不是显示行:宿主关心的是"这条记录",排序筛选不该影响判断。 }
  TTyGridGetCellStyleEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var ABackground: TTyFill; var ATextColor: TTyColor;
    var AFontName: string; var AFontSize, AFontWeight: Integer;
    var AHAlign: TAlignment; var AVAlign: TTextLayout) of object;

  { 一格最终的外观。背景那趟与文字那趟都从这里取,**两趟不可能各算各的**。 }
  TTyGridCellAppearance = record
    HasBackground: Boolean;
    Background:    TTyFill;
    { 底色是不是**用户显式指定的**(逐格色/行色/宿主钩子),而不是主题装饰
      (斑马纹、焦点格、选区)。装饰层不许把它抹掉 —— 用户标的颜色是这一格
      最具体的一句话,盖掉它等于把信息弄丢了。 }
    HasExplicitBackground: Boolean;
    { 文字色是不是主题明确给的。没给就退回控件本体的前景色 ——
      这个判断从前每格重做一次,现在随基础外观一起缓存。 }
    HasTextColor:  Boolean;
    TextColor:     TTyColor;
    FontName:      string;
    FontSize:      Integer;
    FontWeight:    Integer;
    HAlign:        TAlignment;
    VAlign:        TTextLayout;
    WordWrap:      Boolean;
  end;

  { 一格的**附加属性**。稀疏:绝大多数格根本没有条目。

    这里把从前散在各处的逐格信息并到一起。分家的直接后果是增删行时容易漏搬其中一种
    —— `ShiftCells` 就只搬了文字、没搬合并区,在合并块上方插一行会让内容跟着走、
    合并框留在原地。并进同一份存储后,搬家是一趟走完的事。

    Background/TextColor/Alignment/FontStyle/ReadOnly 是给后面几批留的槽位,
    现在先只有合并跨度在用。 }
  TTyGridCellAttr = class
  public
    ColSpan, RowSpan: Integer;      { 1,1 = 未合并 }
    HasBackground:    Boolean;
    Background:       TTyColor;
    HasTextColor:     Boolean;
    TextColor:        TTyColor;
    HasAlignment:     Boolean;
    Alignment:        TAlignment;
    HasFontStyle:     Boolean;
    FontStyle:        TFontStyles;
    ReadOnly:         Boolean;
    constructor Create;
    { 全是默认值 = 这条可以丢掉,别让稀疏存储攒垃圾。 }
    function IsDefault: Boolean;
    procedure Assign(ASrc: TTyGridCellAttr);
  end;

  { 逐格属性的稀疏存储,键空间与单元格文本一致('col:row')。 }
  TTyGridCellAttrStore = class
  private
    FItems: TStringList;      { Sorted + OwnsObjects → 二分查找、自动释放 }
  public
    constructor Create;
    destructor Destroy; override;
    { 没有条目时返回 nil —— **查询不要凭空建条目**,否则遍历一遍表就把稀疏性毁了。 }
    function  Find(const AKey: string): TTyGridCellAttr;
    function  Ensure(const AKey: string): TTyGridCellAttr;
    procedure Remove(const AKey: string);
    { 条目退化成全默认值时把它丢掉。 }
    procedure DropIfDefault(const AKey: string);
    procedure Clear;
    procedure MoveEntry(const AFrom, ATo: string);
    function  IsEmpty: Boolean;
    function  Count: Integer;
    procedure SnapshotKeys(ADest: TStrings);
  end;

  { 网格基类:有几何、有外观,但不规定数据从哪来。 }
  TTyCustomGrid = class(TTyCustomControl)
  private
    FHeader:           TTyHeader;
    FRowCount:         Integer;
    FDefaultRowHeight: Integer;
    FFixedCols:        Integer;
    FFixedRows:        Integer;
    FIndicatorWidth:   Integer;
    FShowIndicator:    Boolean;
    FGridLineStyle:    TTyGridLineStyle;
    { 分组表头。空 = 只有一条列头带,与从前完全一致。 }
    FHeaderGroups:     TTyGridHeaderGroups;
    FGroupHeaderHeight:Integer;
    { 隔行底色。按**显示行号**取,不是数据行号 —— 否则排序筛选之后条纹会跟着
      数据行乱跳,看起来像随机涂色。 }
    FAlternateRows:    Boolean;
    { 行头槽里显示行号(按**显示序**,排序后屏幕第一行仍是 1)。
      从前那条槽只铺了个底、一个数字都不画,而文档管它叫"行号槽"。 }
    FShowRowNumbers:   Boolean;
    FOnGetCellStyle:   TTyGridGetCellStyleEvent;
    FOnGetCellBorder:  TTyGridGetCellBorderEvent;
    FOnGetHeaderStyle: TTyGridGetHeaderStyleEvent;
    FOnColumnSizing:   TTyGridSizingEvent;
    FOnEndColumnSize:  TTyGridSizedEvent;
    FOnRowSizing:      TTyGridSizingEvent;
    FOnEndRowSize:     TTyGridSizedEvent;
    FOnColumnMove:     TTyGridColumnMoveEvent;
    { 全局上下限 —— 自动行高/自适应列宽的护栏,否则一条超长文本能把行撑爆。 }
    FMinRowHeight:     Integer;
    FMaxRowHeight:     Integer;
    FMinColWidth:      Integer;
    FMaxColWidth:      Integer;
    FOnClickCell:      TTyGridCellMouseEvent;
    FOnDblClickCell:   TTyGridCellMouseEvent;
    FOnRightClickCell: TTyGridCellMouseEvent;
    FOnCanClickCell:   TTyGridCanClickCellEvent;
    FOnCellButtonClick:TTyGridCellMouseEvent;
    FOnCanToggleCheck: TTyGridCanToggleEvent;
    FOnCheckBoxChange: TTyGridCheckChangeEvent;
    FOnRatingChange:   TTyGridRatingChangeEvent;
    FOnEllipsisClick:  TTyGridEllipsisEvent;
    FOnGetCellWordWrap:TTyGridGetCellWordWrapEvent;
    FWordWrap:         Boolean;
    { 显式行高的稀疏存储:行号 -> 高度(逻辑像素)。
      从前只有 OnGetRowHeight 回调,网格自己不存 —— 于是拖拽改行高、自动行高
      都**无处落盘**。优先级:显式存储 > 回调 > DefaultRowHeight。 }
    FRowHeights:       TStringList;
    { 正在拖的行分隔线(-1 = 没在拖)。与列那套 FResizeCol 对称。 }
    FResizeRow:        Integer;
    FResizeStartY:     Integer;
    FResizeStartH:     Integer;
    FOnHeaderClick:    TTyGridHeaderMouseEvent;
    FOnHeaderRightClick: TTyGridHeaderMouseEvent;
    { 正被按下的按钮格(-1 = 无)。三态里的 pressed 靠它。 }
    FPressedBtnCol:    Integer;
    FPressedBtnRow:    Integer;
    FGridLineWidth:    Integer;
    { 鼠标当前所在的格(-1 = 不在任何格上)。`TyGridCell:hover` 这条主题规则
      从前永远不会触发,就是因为没人记这个。 }
    FHoverCol:         Integer;
    FHoverRow:         Integer;
    { 逐格样式解析的记忆化。**这是 A2 渲染管线逐格化能不掉速的全部原因**:
      按状态组合缓存,绝大多数格状态相同(空集)于是整帧只解析一次;
      只有 hover/选中/被钩子改过的那几格才多解析几次。 }
    FCellStyleStates:  array of TTyStateSet;
    FCellStyleCache:   array of TTyStyleSet;
    { 与 FCellStyleCache 一一对应的**基础外观**(底色/文字色/字体名/字号/字重)。

      单独缓存字号的理由:`ResolveFontSize` 在样式没写 font-size 时会去查
      `--font-size-base` 这个主题变量 —— **按字符串名查表**。它只取决于已经
      记忆化的样式,却被放在逐格路径上,实测每格 32 微秒、占整帧一半。 }
    FCellBaseCache:    array of TTyGridCellAppearance;
    { **跨帧**的单元格文本位图缓存。
      实测(60 帧 x 20 列 x 约 40 行)里,单元格文字占了 94% 的渲染时间:
      每格一次 TextSize(省略号测量,占 57%)+ 一次 TextRect。两者都是
      BGRA 的重活(每次要配字体、走 LCL 字体引擎)。数据静止时同一格
      每帧画的是**一模一样**的东西,所以按外观整体缓存成小位图直接 blit。
      键含文字/字体/字号/字重/颜色/尺寸/对齐 —— 任何一项变了都是新条目,
      因此换主题、改列宽、切深色都不需要显式失效。 }
    FTextCache:        TStringList;   { Sorted;Objects 存 TBGRABitmap,自己拥有 }
    { 一次绘制期间的 GridMetrics 记忆化。CellRect/CellVisibleRect/CellPane 都要它,
      于是每格要重算三四次;而每次都得遍历列求冻结带宽、还要为 HeaderBands 分配数组。
      一帧内网格状态不可能变,所以整帧只算一次 —— 实测这是文字之外最大的一块开销。 }
    FMetricsCached:    Boolean;
    FMetricsCache:     TTyGridMetrics;
    { 列的**未加滚动**左缘与宽度(设备像素),按列索引。
      从前 ColumnLeftPx 每次都要从头累加一遍可见列宽,而它在每格要被调好几次
      (CellRect / CellVisibleRect / 格线 / 表头)—— 于是每帧是 O(格数 x 列数)
      次带虚方法的 Items[] 访问。横向滚动**不影响**这份缓存(滚动量在读取时才减),
      所以滚动不必重建它。 }
    FColBasePx:        array of Integer;
    FColWidthPx:       array of Integer;
    FColCacheValid:    Boolean;
    FColCachePPI:      Integer;
    { --- 脏区重绘 ---
      上一帧的完整表面。滚动时正文那一大块像素是可以整体平移复用的,
      只有露出来的那一条带需要重画。

      安全性靠**默认作废**保证:Invalidate 一律把表面作废,只有滚动那一条
      路径在调完 Invalidate 之后重新点亮它。于是任何我没想到的失效点
      (改数据、换主题、hover、选区……)都天然走整幅重画,不会留下陈旧像素。 }
    FSurface:          TBGRABitmap;
    FSurfaceFresh:     Boolean;
    FSurfacePendingDy: Integer;
    { 走过快路径的帧数。脏区重绘从画面上完全看不出来 —— 它要是被
      静默关掉,只会变慢。给测试一个能直接观测"这一帧到底走没走快路径"的口子。 }
    FFastScrollFrames: Integer;
    { 上一次鼠标按下命中的是哪儿。DblClick 拿不到坐标(LCL 的签名里没有),
      而"双击落在哪"决定了它该做什么 —— 双击总是紧跟在一次按下之后,
      所以在按下时记账是**准确**的,比在 DblClick 里回读光标位置可靠。 }
    FLastDownHit: TTyGridHit;
    FShowFooter:       Boolean;
    { 列头图标与 gcdImage 单元格共用的图像源。
      注意**不用**共享单元里的 TTyHeader.Images —— 那是 LCL 的 TCustomImageList,
      而我们的 TTyVirtualImageList 并非它的后代;不跟共享单元较劲,网格自带一份。
      索引仍走共享的 TTyColumn.ImageIndex。 }
    FImages:           TTyVirtualImageList;
    FFooterHeight:     Integer;
    FScrollX:          Integer;
    FScrollY:          Integer;
    FDragCol:          Integer;   { 正在拖动的列索引;-1 = 没在拖 }
    FDragStartX:       Integer;
    FResizeCol:        Integer;   { 正在拖宽的列;-1 = 没在拖 }
    FResizeStartX:     Integer;
    FResizeStartW:     Integer;
    FVScroll:          TTyScrollBar;
    FHScroll:          TTyScrollBar;
    FSyncingScroll:    Boolean;      { 防止程序改 Position 反弹回来 }
    procedure VScrollChange(Sender: TObject);
    procedure HScrollChange(Sender: TObject);
    procedure HeaderChanged(Sender: TObject);
    procedure SetHeader(AValue: TTyHeader);
    procedure SetRowCount(AValue: Integer);
    procedure SetDefaultRowHeight(AValue: Integer);
    procedure SetFixedCols(AValue: Integer);
    procedure SetFixedRows(AValue: Integer);
    procedure SetIndicatorWidth(AValue: Integer);
    procedure SetShowIndicator(AValue: Boolean);
    procedure SetShowGridLines(AValue: Boolean);
    procedure SetShowFooter(AValue: Boolean);
    procedure SetImages(AValue: TTyVirtualImageList);
    procedure SetGridLineWidth(AValue: Integer);
    procedure SetGridLineStyle(AValue: TTyGridLineStyle);
    procedure HeaderGroupsChanged(Sender: TObject);
    procedure SetHeaderGroups(AValue: TTyGridHeaderGroups);
    procedure SetGroupHeaderHeight(AValue: Integer);
    procedure SetAlternateRows(AValue: Boolean);
    procedure SetShowRowNumbers(AValue: Boolean);
    { 把"以行下标为键"的旁挂表整体平移(行高、隐藏行)。 }
    procedure ShiftRowKeyedTable(AList: TStringList; AFromIndex, ADelta: Integer);
    { 把行号画进行头槽。ShowRowNumbers 关着时整段跳过。 }
    procedure RenderRowNumbers(P: TTyPainter; const M: TTyGridMetrics;
      AHeaderH, AIndicatorW: Integer); virtual;
    procedure SetWordWrap(AValue: Boolean);
    function  GetRowHeights(ARow: Integer): Integer;
    procedure SetRowHeights(ARow, AValue: Integer);
    { Y 落在哪一行的下边界附近(行头槽内才算)。不在分隔线上返回 -1。 }
    function  RowDividerAtY(AX, AY: Integer): Integer;
    function  GetGridLines: Boolean;
    procedure SetFooterHeight(AValue: Integer);
  protected
    function GetStyleTypeKey: string; override;
    { 行数变了 → 行序间接层失效。基类无序可失效,派生类改写。 }
    procedure InvalidateGridOrder; virtual;

    { 逻辑像素 → 设备像素。几何层收的全是设备像素。 }
    function Dpi: Integer;
    function ScaleI(AValue: Integer): Integer;
    function UnscaleI(AValue: Integer): Integer;

    { 冻结带宽度(设备像素)= 行头槽 + 各固定列宽之和。 }
    { 网格线宽(设备像素)。关掉格线时为 0 —— 这样几何层无需再判 GridLines。 }
    { 某一格自己的状态。**刻意不掺入网格的 CurrentStates** —— 掺进去的话
      鼠标一按下网格进 :active,满屏单元格会跟着集体变样(勾选框那次就是这么栽的)。 }
    function CellStates(ACol, ARow: Integer): TTyStateSet; virtual;
    { 逐格解析 TyGridCell,带记忆化。每帧开头调 ResetCellStyleCache。 }
    function ResolveCellStyle(ACol, ARow: Integer): TTyStyleSet;
    { 该格状态组合在缓存里的槽位(顺带把基础外观算好)。 }
    function CellStyleSlot(ACol, ARow: Integer): Integer;
    procedure ResetCellStyleCache;
    { 鼠标所在格换了没有;换了就重绘(**换格才重绘** —— 每像素都重绘会把
      大表拖垮,而且鼠标一动就满屏闪)。 }
    procedure UpdateHoverCell(X, Y: Integer);
    { 指针形状跟着"这里能不能拖"走。**必须与命中判定同源** ——
      指针承诺了能拖就得真能拖,否则用户会对着一个假暗示较劲。
      (ListView / TreeView 早就这么做了,网格一直漏着。) }
    procedure UpdateHoverCursor(X, Y: Integer);
    { 把一格文字画出来,尽量走缓存。语义与 P.DrawText 一致(含省略号截断)。 }
    procedure DrawCellText(P: TTyPainter; const ARect: TRect; const AText: string;
      const AFontName: string; AFontSize, AFontWeight: Integer; AColor: TTyColor;
      AHAlign: TAlignment; AVAlign: TTextLayout; AWordWrap: Boolean = False);
    procedure ClearTextCache;
    { 作废持久表面(下一帧整幅重画)。 }
    procedure InvalidateSurface;
    property FastScrollFrames: Integer read FFastScrollFrames;
    { 纵向滚动 ADy 像素,并让下一帧走快路径。 }
    procedure ScrollVerticallyBy(ADy: Integer);
    { 把表面上 [ATop, ABottom) 这一段整体上移/下移 ADy 像素(逐扫描行 Move)。 }
    procedure ShiftSurfaceRows(ATop, ABottom, ADy: Integer);
    { 单元格最多跨几行。基类不认识合并,给 1;TTyStringGrid 覆盖成真实跨度。
      脏区重绘用它来决定接缝处要多让出几行。 }
    function MaxRowSpanHint: Integer; virtual;
    { 行高变了 → 行几何的缓存(前缀和)要失效。基类没有缓存;TTyStringGrid 改写。 }
    procedure InvalidateRowMetrics; virtual;
    { 有没有任何一行设过显式行高。 }
    function  HasExplicitRowHeights: Boolean;
    { 一格最终外观 = 主题 TyGridCell(按状态) → 斑马纹 → 逐格属性 → 宿主钩子。
      ADisplayPos 只用于斑马纹;ARow 是数据行。 }
    function CellAppearance(ACol, ARow, ADisplayPos: Integer;
      const AFrame: TTyStyleSet): TTyGridCellAppearance; virtual;
    procedure DoGetCellStyle(ACol, ARow: Integer;
      var AAppearance: TTyGridCellAppearance); virtual;
    { 逐格边框:宿主没接钩子时四支笔全关,一个像素都不多画。 }
    procedure RenderCellBorders(P: TTyPainter; const M: TTyGridMetrics); virtual;
    { 这一格能不能点。所有点击路径都必须先问它。 }
    function  CanClickCell(ACol, ARow: Integer): Boolean;
    { 这一格是不是"焦点格"(光标所在)。基类没有光标概念,恒 False。 }
    function  IsActiveCell(ACol, ARow: Integer): Boolean; virtual;
    { 逐格属性查询。基类没有属性存储,恒 nil;TTyStringGrid 改写。 }
    function  FAttrs2Find(ACol, ARow: Integer): TTyGridCellAttr; virtual;
    { 网格自己的列类;列还没建时返回 nil。 }
    function  GridColumn(ACol: Integer): TTyGridColumn;
  public
    { --- 列的显式隐藏 ---
      底层就是 TTyColumn.Options 里的 coVisible;这三个方法只是免得宿主
      自己去记集合运算。隐藏列不占宽度、不被绘制、光标也不会停上去。 }
    procedure HideColumn(ACol: Integer);
    procedure ShowColumn(ACol: Integer);
    function  IsHiddenColumn(ACol: Integer): Boolean;
    { 从 AFrom 起沿 AStep 找第一个**可见**列;找不到就原样返回。 }
    function  NextVisibleCol(AFrom, AStep: Integer): Integer;
    { 第一个 / 最后一个可见列。 }
    function  FirstVisibleCol: Integer;
    function  LastVisibleCol: Integer;

  public
    { 显式行高。设为 <= 0 表示"清掉,回到回调/默认值"。
      **public**:宿主按行设高度是正常用法(示例里"恢复行高"就靠它)。 }
    property RowHeights[ARow: Integer]: Integer read GetRowHeights write SetRowHeights;
  protected
    { 按内容自适应列宽。基类没有数据、什么都不做;TTyStringGrid 改写。 }
    procedure AutoFitColumnWidth(ACol: Integer); virtual;
    { 把点在星级格上的坐标翻成分值并写回。 }
    procedure SetRatingByPoint(ACol, ARow, X, Y: Integer); virtual;
    procedure SetPressedButton(ACol, ARow: Integer);
    procedure GetPressedButton(out ACol, ARow: Integer);
    { 按钮格的按钮矩形(单元格内缩 2 逻辑像素)。不是按钮格时返回空矩形。 }
    function  CellButtonRect(ACol, ARow: Integer): TRect; virtual;
    function  CellDisplayOf(ACol, ARow: Integer): TTyGridCellDisplay; virtual;
    procedure RenderButtonCell(P: TTyPainter; ACol, ARow: Integer;
      const AText: string; const AFrame: TTyStyleSet); virtual;
    function GroupBandHeightPx: Integer; virtual;
    { 重建列几何缓存。列增删/改宽、行头槽变化、PPI 变化都要让它失效。 }
    procedure BuildColumnCache;
    procedure InvalidateColumnCache;
    function GridLineWidthPx: Integer; virtual;
    procedure Invalidate; override;
    procedure DblClick; override;
    procedure CMMouseLeave(var Msg: TLMessage); message CM_MOUSELEAVE;
    function FrozenWidthPx: Integer; virtual;
    { 冻结带高度(设备像素)= 列头带 + 固定行 * 行高。 }
    function FrozenHeightPx: Integer; virtual;
    { 页脚汇总带高度(设备像素)。它钉在视口底部、不参与滚动。 }
    function FooterHeightPx: Integer; virtual;
    { 逐行行高(逻辑像素)。基类恒为 DefaultRowHeight;派生类可按行覆盖。 }
    function RowHeightOf(ARow: Integer): Integer; virtual;
    { 行高前缀和(设备像素),喂给几何层。全等高时返回空数组 = 走统一行高快路径。 }
    function RowTops: TTyIntArray; virtual;

    { 把控件当前状态装配成纯几何层要的度量。所有几何都必须经由它,
      不允许任何地方另算一套 —— 那正是绘制/命中漂移的源头。 }
    function GridMetrics: TTyGridMetrics; virtual;

    { 第 ACol 列左边界的客户区横坐标(设备像素)——**列轴几何的唯一出处**。
      固定列钉在冻结带里不随横向滚动;正文列随 ScrollX 平移。
      CellRect 与 ColumnAtX 都必须走它,否则绘制与命中会分叉。 }
    function ColumnLeftPx(ACol: Integer): Integer; virtual;
    function ColumnWidthPx(ACol: Integer): Integer;
    { 横坐标落在哪一列 —— ColumnLeftPx 的逆;不在任何列上时答 -1。 }
    function ColumnAtX(AX: Integer): Integer; virtual;

    { 网格线颜色:优先取 TyGridLine 的 background,主题没定义时退回本体的 border-color
      —— 让只写了 TyGrid 一条规则的皮肤也能画出可辨认的格子。 }
    function GridLineColor(const AFrame: TTyStyleSet): TBGRAPixel;

    { 用某个 typeKey 的 background 填一块区域;该键没定义背景就什么都不画
      (于是那块区域透出网格表面本色 —— 这正是"皮肤没写就优雅退化"的做法)。 }
    procedure FillRegion(P: TTyPainter; const ARect: TRect; const AKey: string);

    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    { 列头上 X 处的分隔条索引(拖它改列宽);没命中返回 -1。 }
    function  DividerAtX(AX: Integer): Integer;

    { 该列是否显示筛选按钮。基类不筛,恒 False。 }
    function ShowsFilterButton(ACol: Integer): Boolean; virtual;
    { 这一列在不在过滤中 / 是第几顺位的排序键 / 一共几个排序键。
      基类没有数据模型,一律答"没有";TTyStringGrid 改写。
      放在基类是因为**表头渲染在基类**,而它需要这三个答案。 }
    { 全表有没有任何合并区。没有就让格线走"整条画完"的快路径 ——
      逐段画要多出 列数 x 行数 次 FillRect,不能让没用合并的表白白付这个钱。 }
    function HasMergedCells: Boolean; virtual;
    { 两个格是不是属于**同一个**合并区。是的话它们之间的那条边界不该画线。 }
    function SameMergedCell(ACol1, ARow1, ACol2, ARow2: Integer): Boolean; virtual;
    function ColumnFilterActive(ACol: Integer): Boolean; virtual;
    function SortRankOf(ACol: Integer): Integer; virtual;
    function SortColumnCountOf: Integer; virtual;
    { 列头上筛选按钮的槽(命中与绘制共用)。 }
    function HeaderFilterRect(ACol, AHeaderH: Integer): TRect;

    { 列头里每一列的分段:底色、标题文字、排序字形。 }
    procedure RenderHeaderSections(P: TTyPainter; const M: TTyGridMetrics;
      AHeaderH: Integer); virtual;

    { 列头带 / 行头槽 / 固定列区的填充。绘制次序即遮挡次序,必须与 CellAt 的判定次序一致:
      列头横跨整幅并盖住左上角 → 行头槽 → 固定列。 }
    procedure RenderChrome(P: TTyPainter; const M: TTyGridMetrics); virtual;
    { 逐格背景。与文字分成两趟:文字那趟在派生类里(基类不知道数据从哪来),
      而背景只取决于格的**状态**,基类就能画完 —— hover/选中/斑马纹/逐格底色
      因此对三层都自动生效。 }
    procedure RenderCellBackgrounds(P: TTyPainter; const M: TTyGridMetrics); virtual;
    { 分组表头带。没有分组时什么都不画。 }
    procedure RenderHeaderGroups(P: TTyPainter; const M: TTyGridMetrics); virtual;

    { 单元格内容。基类不画任何内容(它不知道数据从哪来)——由派生类改写。
      在 chrome 之后、格线之前调用。 }
    procedure RenderCells(P: TTyPainter; const M: TTyGridMetrics;
      const AFrame: TTyStyleSet); virtual;
    { 底部汇总带。基类只铺底色,内容由派生类填。 }
    procedure RenderFooter(P: TTyPainter; const M: TTyGridMetrics;
      const AFooterRect: TRect; const AFrame: TTyStyleSet); virtual;

    { 分窗格绘制的总入口。无头可测:直接对着任意 canvas 画,不需要窗口句柄。 }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); virtual;
    procedure RenderGridLines(P: TTyPainter; const M: TTyGridMetrics;
      const AFrame: TTyStyleSet); virtual;
    procedure Paint; override;

    procedure SetScrollX(AValue: Integer);
    procedure SetScrollY(AValue: Integer);
    property ScrollX: Integer read FScrollX write SetScrollX;
    property ScrollY: Integer read FScrollY write SetScrollY;

    { 内容总尺寸与最大可滚距离(设备像素)。滚动量必须钳在 [0, Max],
      否则能把内容滚出视口、留下一片空白还回不来。 }
    function ContentHeightPx: Integer; virtual;
    function ContentWidthPx: Integer; virtual;
    function MaxScrollY: Integer;
    function MaxScrollX: Integer;

    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;

    { 视口 = 客户区扣掉可见滚动条占去的那条。所有几何都用它,而不是 ClientWidth/Height,
      否则最后一行/列会钻到滚动条底下。 }
    function ViewportW: Integer;
    function ViewportH: Integer;
    { 按内容与视口决定两条滚动条的可见性、范围与位置。 }
    procedure UpdateScrollBars; virtual;
    { 把当前滚动量推给滑块。**每一次程序性滚动都必须调它** —— 滚轮、键盘跟随、
      ScrollIntoView 改的都只是 FScrollX/Y,不同步的话内容滚了滑块还停在原处。 }
    procedure SyncScrollBars;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    property VScrollBar: TTyScrollBar read FVScroll;
    property HScrollBar: TTyScrollBar read FHScroll;

    { **行序间接层** —— 全设计的中心不变量。
      排序/过滤只置换"显示序",而选择、光标、编辑一律按**稳定的数据行**记账,
      于是重排之后光标不会跑到别的数据上去。基类是恒等映射;TTyStringGrid 排序后覆写。

      约定:所有对外 API(CellRect / CellAt / Col,Row / Cells)吃的都是**数据行**;
      只有几何层(TyGridRowRect / TyGridVisibleRows)按显示序工作。 }
    function DisplayToData(APos: Integer): Integer; virtual;
    { 数据行 → 显示序。**被过滤掉的行返回 -1**(它没有显示位置)。 }
    function DataToDisplay(ARow: Integer): Integer; virtual;
    { 实际参与显示的行数。过滤后 < RowCount;几何层用的是它,不是 RowCount。 }
    function DisplayRowCount: Integer; virtual;

    { 单元格所属窗格。P0 只按列区分(固定列 → gpLeft,其余 → gpBody):
      FixedRows 目前只在冻结带里**预留高度**,固定行自身的行寻址随 P1 的数据模型一起做。 }
    function CellPane(ACol, ARow: Integer): TTyGridPane;

    { 单元格的几何矩形,客户区坐标 —— **未裁剪**。派生类可覆写(合并区)。绘制时要先裁到所属窗格;
      正文列横向滚到冻结带底下的那一段就在这里被裁掉。 }
    function CellRect(ACol, ARow: Integer): TRect; virtual;

    { 单元格**实际可见**的矩形 = CellRect ∩ 所属窗格。CellAt 正是它的逆:
      被冻结带盖住的部分本来就点不到,所以不变量必须以可见矩形表述,而非几何矩形。 }
    function CellVisibleRect(ACol, ARow: Integer): TRect;
    { 落在合并区内的坐标归到基准格。基类无合并,原样返回。 }
    procedure MapToBaseCell(var ACol, ARow: Integer); virtual;

    { 点命中,客户区坐标 —— **CellVisibleRect 的逆**(见上:被冻结带盖住的部分点不到)。 }
    function CellAt(AX, AY: Integer): TTyGridHit;

    { 把某个单元格滚进可视区(最小移动量)。光标一旦走出视口就得靠它跟上,
      否则按方向键会"把光标走丢"。 }
    procedure ScrollIntoView(ACol, ARow: Integer);
  published
    { 列模型(含列集合、列头高度、排序列、自动适宽列)。 }
    property Header: TTyHeader read FHeader write SetHeader;
    { 数据行数(不含列头与固定行)。 }
    property RowCount: Integer read FRowCount write SetRowCount default 0;
    { 统一行高,逻辑像素(P0 不支持可变行高)。 }
    property DefaultRowHeight: Integer read FDefaultRowHeight write SetDefaultRowHeight default 22;
    { 冻结在左侧、不随横向滚动的列数。 }
    property FixedCols: Integer read FFixedCols write SetFixedCols default 0;
    { 冻结在顶部、不随纵向滚动的数据行数(列头带另计)。 }
    property FixedRows: Integer read FFixedRows write SetFixedRows default 0;
    { 最左侧的行头/行号槽。 }
    property ShowIndicator: Boolean read FShowIndicator write SetShowIndicator default False;
    { 在行头槽里画行号(按显示序)。需要 ShowIndicator 也打开。 }
    property ShowRowNumbers: Boolean read FShowRowNumbers write SetShowRowNumbers
      default False;
    property IndicatorWidth: Integer read FIndicatorWidth write SetIndicatorWidth default 30;
    { 单元格之间的格线。颜色取 TyGridLine 的 background,主题没定义则退回本体的 border-color。
      **兼容别名** —— 真正的存储是 GridLineStyle。`stored False` 保证它不会被写进 .lfm
      (两个属性都写进去会互相打架),但老 .lfm 里的 GridLines=False 照样读得进来。 }
    property GridLines: Boolean read GetGridLines write SetShowGridLines
      stored False default True;
    { 分组表头:横跨若干相邻列的上层标题。空集合 = 只有一条列头带(默认)。 }
    property HeaderGroups: TTyGridHeaderGroups read FHeaderGroups write SetHeaderGroups;
    { 分组带的高度(逻辑像素)。 }
    property GroupHeaderHeight: Integer read FGroupHeaderHeight
      write SetGroupHeaderHeight default 22;
    { 格线画哪几轴。 }
    property GridLineStyle: TTyGridLineStyle read FGridLineStyle write SetGridLineStyle
      default glsBoth;
    { 隔行底色(主题键 TyGridCellAlt)。 }
    property AlternateRows: Boolean read FAlternateRows write SetAlternateRows default False;
    { 单元格文字换行的默认值;OnGetCellWordWrap 可逐格覆盖。 }
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
    { 格线粗细,逻辑像素。**不占布局像素** —— 线画在单元格边界上、压住两侧各一半,
      列宽就是列宽,不会因为线变粗而挪位(与 LCL TCustomGrid / 常见商业网格一致)。
      粗线只会让单元格**内容**相应内缩,免得文字压在线底下。 }
    property GridLineWidth: Integer read FGridLineWidth write SetGridLineWidth default 1;
    { 列头图标(TTyColumn.ImageIndex)与 gcdImage 单元格共用的图像源。 }
    property Images: TTyVirtualImageList read FImages write SetImages;
    { 逐格外观钩子。 }
    property OnGetCellStyle: TTyGridGetCellStyleEvent
      read FOnGetCellStyle write FOnGetCellStyle;
    { 逐格边框(四支笔)。 }
    property OnGetCellBorder: TTyGridGetCellBorderEvent
      read FOnGetCellBorder write FOnGetCellBorder;
    { 表头格自绘。 }
    property OnGetHeaderStyle: TTyGridGetHeaderStyleEvent
      read FOnGetHeaderStyle write FOnGetHeaderStyle;
    { 列宽/行高的交互事件 —— 有了它们,列宽偏好能保存恢复,不用轮询。 }
    property OnColumnSizing: TTyGridSizingEvent read FOnColumnSizing write FOnColumnSizing;
    property OnEndColumnSize: TTyGridSizedEvent read FOnEndColumnSize write FOnEndColumnSize;
    property OnRowSizing: TTyGridSizingEvent read FOnRowSizing write FOnRowSizing;
    property OnEndRowSize: TTyGridSizedEvent read FOnEndRowSize write FOnEndRowSize;
    property OnColumnMove: TTyGridColumnMoveEvent read FOnColumnMove write FOnColumnMove;
    { 行高/列宽的全局上下限(逻辑像素)。0 = 不限。 }
    property MinRowHeight: Integer read FMinRowHeight write FMinRowHeight default 0;
    property MaxRowHeight: Integer read FMaxRowHeight write FMaxRowHeight default 0;
    property MinColWidth: Integer read FMinColWidth write FMinColWidth default 0;
    property MaxColWidth: Integer read FMaxColWidth write FMaxColWidth default 0;
    { 单元格级鼠标事件。 }
    property OnClickCell: TTyGridCellMouseEvent read FOnClickCell write FOnClickCell;
    property OnDblClickCell: TTyGridCellMouseEvent read FOnDblClickCell write FOnDblClickCell;
    property OnRightClickCell: TTyGridCellMouseEvent read FOnRightClickCell write FOnRightClickCell;
    property OnCanClickCell: TTyGridCanClickCellEvent read FOnCanClickCell write FOnCanClickCell;
    property OnCellButtonClick: TTyGridCellMouseEvent read FOnCellButtonClick write FOnCellButtonClick;
    { 勾选框:能否决、也能在切换后收到通知。 }
    property OnCanToggleCheck: TTyGridCanToggleEvent
      read FOnCanToggleCheck write FOnCanToggleCheck;
    property OnCheckBoxChange: TTyGridCheckChangeEvent
      read FOnCheckBoxChange write FOnCheckBoxChange;
    property OnRatingChange: TTyGridRatingChangeEvent
      read FOnRatingChange write FOnRatingChange;
    { gekEllipsis 的"…"按钮被点。 }
    property OnEllipsisClick: TTyGridEllipsisEvent
      read FOnEllipsisClick write FOnEllipsisClick;
    property OnGetCellWordWrap: TTyGridGetCellWordWrapEvent
      read FOnGetCellWordWrap write FOnGetCellWordWrap;
    property OnHeaderClick: TTyGridHeaderMouseEvent read FOnHeaderClick write FOnHeaderClick;
    property OnHeaderRightClick: TTyGridHeaderMouseEvent read FOnHeaderRightClick write FOnHeaderRightClick;
    { 底部汇总带。内容由派生类给(TTyStringGrid 按列聚合)。 }
    property ShowFooter: Boolean read FShowFooter write SetShowFooter default False;
    property FooterHeight: Integer read FFooterHeight write SetFooterHeight default 24;

    { LCL 标准布局属性 —— 基类没有发布它们,必须在这里发布。
      漏发布的后果只在**运行时流式化**才暴露(设计器里写了 Anchors,启动时报
      "Unknown property: Anchors"),编译期完全看不出来。 }
    property Align;
    property Anchors;
    property BorderSpacing;
    property Constraints;
    property Visible;
    property PopupMenu;
    property TabStop default True;
    { 主题接线。 }
    property StyleClass;
    property Controller;
  end;

  { 单元格文本由宿主提供 —— 对齐 LCL TDrawGrid 的"内容不归控件管"的定位。 }
  TTyGridGetCellTextEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var AText: string) of object;

  { 纯自绘网格:自己不存任何数据,每个单元格的文本现问宿主要。
    因为不存数据,它天然就是"虚拟"的 —— 一百万行也不占内存。 }
  TTyDrawGrid = class(TTyCustomGrid)
  private
    FOnGetCellText: TTyGridGetCellTextEvent;
  protected
    { 取一个单元格要显示的文本。派生类可改写以接自己的存储。 }
    function GetCellText(ACol, ARow: Integer): string; virtual;
    { 该格要不要画文字。自己画图形的格返回 False。 }
    function ShouldDrawCellText(ACol, ARow: Integer): Boolean; virtual;
    { 给宿主一次完全接管该格绘制的机会;返回 True 表示已被接管。 }
    function DoDrawCell(P: TTyPainter; ACol, ARow: Integer): Boolean; virtual;
    procedure RenderCells(P: TTyPainter; const M: TTyGridMetrics;
      const AFrame: TTyStyleSet); override;
  published
    property OnGetCellText: TTyGridGetCellTextEvent
      read FOnGetCellText write FOnGetCellText;
  end;

  TTyGridSelectCellEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var ACanSelect: Boolean) of object;

  { 单元格编辑器种类。AdvGrid 那一长串编辑器类型其实是"少量控件 x 修饰符"的笛卡尔积,
    这里先落地最常用的一档;浮层类(颜色/备忘/计算器…)将来统一由 TTyPopover 承载。 }

  { 分组行(合成行,不对应任何数据行)。 }
  TTyGridGroupInfo = record
    Key:      string;    { 分组值 }
    Count:    Integer;   { 组内行数 }
    Collapsed: Boolean;
    { 组内的**数据行**。分组小计要按它统计 —— 不能按显示序算:
      组一折叠,成员行就不在显示序里了,小计会变成 0。 }
    Rows:     array of Integer;
  end;

  { 覆盖某列汇总文字的钩子(比如加货币符号、或做自定义统计)。 }
  TTyGridGetFooterTextEvent = procedure(Sender: TObject; ACol: Integer;
    var AText: string) of object;

  TTyGridCompareEvent = procedure(Sender: TObject; ACol, ARow1, ARow2: Integer;
    var AResult: Integer) of object;

  { 逐行过滤钩子。AVisible 进来是"已通过列过滤"的结果,可再否决。 }
  TTyGridFilterRowEvent = procedure(Sender: TObject; ARow: Integer;
    var AVisible: Boolean) of object;

  TTyGridGetEditorKindEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var AKind: TTyGridEditorKind) of object;
  { gekPickList 的候选项。宿主往 AItems 里填。 }
  TTyGridGetPickListEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    AItems: TStrings) of object;
  TTyGridCellEditedEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    const AOldText, ANewText: string; var AAccept: Boolean) of object;

  { 完整体:自带**稀疏**单元格存储 + 二维光标 + 键鼠导航。
    稀疏的意思是只有写过的单元格才占内存 —— 100 万 x 100 的空表不花一分钱。 }
  TTyStringGrid = class(TTyDrawGrid)
  private
    { 'col:row' -> 文本,只存写过的格。
      **必须是哈希表**:早先用有序 TStringList + Values[] 查找,而 IndexOfName 是
      **线性扫描** —— 排序时 O(n^2) 次比较里每次再套一次 O(n) 查找,1000 行直接卡死。 }
    FCells: TFPStringHashTable;
    { 与 FCells 同步的键表。哈希表本身不提供好用的键枚举(Iterate 要全局回调),
      而行列增删与自动适宽都需要遍历"写过的格" —— 单独维护一份键更简单也更快。 }
    FCellKeys: TStringList;
    FCol: Integer;                { 当前单元格(光标) }
    FRow: Integer;
    FOnSelectCell: TTyGridSelectCellEvent;
    FEditor: TTyEdit;
    FEditing: Boolean;
    FEditCol: Integer;
    FEditRow: Integer;
    FEndingEdit: Boolean;         { 防重入:提交过程里又触发提交 }
    FReadOnly: Boolean;
    FDefaultEditorKind: TTyGridEditorKind;
    FOnGetEditorKind: TTyGridGetEditorKindEvent;
    FOnCellEdited: TTyGridCellEditedEvent;
    FPickEditor: TTyComboBox;
    FOnGetPickList: TTyGridGetPickListEvent;
    FOnCreateEditLink: TTyGridCreateEditLinkEvent;
    FOnClipboardCopy:  TTyGridClipboardEvent;
    FOnClipboardPaste: TTyGridClipboardEvent;
    FOnBeforePasteCell: TTyGridPasteCellEvent;
    FOnAfterPasteCell:  TTyGridCellMouseEvent;
    { 粘贴超出网格时自动扩行/扩列。默认开 —— 静默丢数据比多几行空行糟糕得多。 }
    FAutoGrowOnPaste:  Boolean;
    { 当前正在用的宿主 EditLink(nil = 走内建编辑器)。 }
    FEditLink: TTyGridEditLink;
    { 内建编辑器。都是库里现成的控件,网格只负责摆位置、灌值、取值。 }
    FSpinEditor:   TTySpinEdit;
    FSliderEditor: TTyTrackBar;
    FMemoEditor:   TTyMemo;
    FMaskEditor:   TTyMaskEdit;
    FCalcEditor:   TTyCalcEdit;
    FEditLinkCtl: TWinControl;
    FDateEditor: TTyDateTimePicker;
    FOnGetCellDisplay: TTyGridGetCellDisplayEvent;
    FDefaultCellDisplay: TTyGridCellDisplay;
    FOnGetRowHeight: TTyGridGetRowHeightEvent;
    FOnDrawCell: TTyGridDrawCellEvent;
    FOnGetCellHint: TTyGridGetCellHintEvent;
    FHintCol: Integer;
    FHintRow: Integer;
    FRowTopsCache: TTyIntArray;
    FRowTopsValid: Boolean;
    FAggregates: TStringList;      { 列索引 -> 聚合方式序号 }
    { 逐格附加属性(合并跨度、以及留给后面几批的底色/字体/只读)。
      与 FCells 同一套键。**合并信息从前是自己一张表**,增删行时漏搬,已并进来。 }
    FAttrs: TTyGridCellAttrStore;
    FOnGetFooterText: TTyGridGetFooterTextEvent;
    FGroupCol: Integer;                        { -1 = 不分组 }
    FFilterPopup: TTyPopover;
    FFilterList: TTyGridFilterList;
    FFilterCol: Integer;
    { --- Excel 式筛选下拉的部件 --- }
    FFilterPanel:  TTyPanel;      { Popover.Content 只收**一个**控件,得有个容器 }
    FFilterSearch: TTyEdit;
    FFilterSelAll: TTyCheckBox;
    FFilterOk, FFilterCancel: TTyButton;
    { 全部候选值(Objects 里放该值的行数),与当前勾选集合。

      **勾选状态必须按"值"记,不能按列表下标记** —— 搜索框一narrow,
      下标就全变了;按下标记账的话,搜完再勾会勾到别的值上。 }
    FFilterAllValues: TStringList;
    FFilterChecked:   TStringList;
    FFilterAccepted:  Boolean;    { 点了确定才提交;取消/点空白处丢弃 }
    FShowFilterButtons: Boolean;
    FShowGroupSubtotals: Boolean;
    FSelectionMode: TTyGridSelectionMode;
    FGroups: array of TTyGridGroupInfo;
    FCollapsed: TStringList;                   { 记住哪些组被折叠(按分组值) }
    { 行序间接层。FOrder[显示序]=数据行(**只含通过过滤的行**);
      FRank[数据行]=显示序,被过滤掉的行为 -1。两者互为逆。
      惰性重建:改行数/改过滤/排序才失效,改单元格内容**不**失效
      —— 否则编辑一格就当场重排,用户会看着行乱跳。 }
    FOrder: array of Integer;
    FRank: array of Integer;
    FOrderValid: Boolean;
    FColFilters: TStringList;     { 列索引 -> 过滤文本(包含匹配,不区分大小写) }
    FValFilters: TStringList;     { 列索引 -> 允许值集合(换行分隔);空 = 该列不按值过滤 }
    FOnFilterRow: TTyGridFilterRowEvent;
    FSelAnchorCol: Integer;       { 选区锚点(数据行),与光标一起决定**活动**矩形选区 }
    FSelAnchorRow: Integer;
    { 已提交的离散选区,**显示序空间**(Left/Right = 列,Top/Bottom = 显示行)。
      单矩形选区是它为空时的退化情形 —— 所以老行为天然 0 回归。
      用显示序而不是数据行:Ctrl+点出来的"这几行"在用户眼里就是屏幕上那几条,
      排序之后跟着屏幕走才符合直觉。 }
    FSelRects: array of TRect;
    FOnSelectionChanged: TNotifyEvent;
    FSortCol: Integer;
    { 完整的排序键序列;FSortCol/FSortDir 是它的第 0 项(保留成兼容视图)。 }
    FSortKeys: TTyGridSortKeys;
    FBlanksPosition: TTyGridBlanksPosition;
    FSortIgnoreCase: Boolean;
    FOnCanSort: TTyGridCanSortEvent;
    FUpdatingOrder: Integer;
    { 显式隐藏的行(数据行号)。 }
    FHiddenRows: TStringList;
    { 当前有多少个合并区。只为了让格线绘制能 O(1) 地判断"要不要走逐段慢路径"。 }
    FMergeCount: Integer;
    FMaxColSpan: Integer;
    FMaxRowSpan: Integer;
  protected
    procedure FilterSearchChanged(Sender: TObject);
    procedure FilterItemChecked(Sender: TObject);
    procedure FilterSelectAllClick(Sender: TObject);
    procedure FilterOkClick(Sender: TObject);
    procedure FilterCancelClick(Sender: TObject);
    procedure RebuildFilterList;
    procedure SyncFilterSelectAll;
    function MaxRowSpanHint: Integer; override;
    { 这段数据行此刻是不是正连续升序地显示着。 }
    function RowsDisplayedConsecutively(ABaseRow, ACount: Integer): Boolean;
  private
    FSkipReadOnly: Boolean;
    FGroupRowFormat: string;
    FSortDir: TTySortDirection;
    FSortKind: TTyGridSortKind;
    FOnCompareCells: TTyGridCompareEvent;
    procedure ShiftCells(AFromIndex, ADelta: Integer; ARows: Boolean);
    procedure FilterPopupClosed(Sender: TObject);
    procedure InvalidateOrder;
    procedure RebuildOrder;
    procedure BuildGroups;
    function  RowPassesFilter(ARow: Integer): Boolean;
    procedure EnsureOrder;
    procedure ResetOrder;
    function  CompareRows(ACol, ARow1, ARow2: Integer): Integer;
    procedure MergeSortOrder(ACol: Integer; ADirection: TTySortDirection);
    procedure MergeSortOrderByKeys(const AKeys: TTyGridSortKeys);
    function  CompareRowsByKeys(const AKeys: TTyGridSortKeys;
      ARow1, ARow2: Integer): Integer;
    function  BlankVerdict(ACol, ARow1, ARow2: Integer;
      out ACmp: Integer): Boolean;
    { 实际生效的排序键 = (分组列,如果有) + 用户的排序键。
      **分组不再改写 FSortCol** —— 从前 BuildGroups 直接把 FSortCol 赋成分组列,
      于是一分组就悄悄丢掉用户选的排序列。 }
    function  EffectiveSortKeys: TTyGridSortKeys;
    procedure DateEditorExit(Sender: TObject);
    procedure PickEditorChange(Sender: TObject);
    procedure PickEditorExit(Sender: TObject);
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorExit(Sender: TObject);
    function  CellKey(ACol, ARow: Integer): string;
    function  GetCells(ACol, ARow: Integer): string;
    procedure SetCells(ACol, ARow: Integer; const AValue: string);
    procedure SetCol(AValue: Integer);
    procedure SetSelectionMode(AValue: TTyGridSelectionMode);
    function  GetCellColor(ACol, ARow: Integer): TTyColor;
    procedure SetCellColor(ACol, ARow: Integer; AValue: TTyColor);
    function  GetCellTextColor(ACol, ARow: Integer): TTyColor;
    procedure SetCellTextColor(ACol, ARow: Integer; AValue: TTyColor);
    function  GetCellReadOnly(ACol, ARow: Integer): Boolean;
    procedure SetCellReadOnly(ACol, ARow: Integer; AValue: Boolean);
    { 把当前的活动矩形固化进 FSelRects(Ctrl+点时用)。 }
    procedure CommitActiveSelection;
    function  ActiveSelectionRect: TRect;   { 显示序空间 }
    procedure SelectionChanged;
    procedure SetRow(AValue: Integer);
  protected
    function  GetCellText(ACol, ARow: Integer): string; override;
    procedure RenderCells(P: TTyPainter; const M: TTyGridMetrics;
      const AFrame: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { 直接敲可打印字符就进编辑并把这个字符当作第一笔 —— 表格录入的基本手感。
      从前只有 KeyDown、没有 KeyPress 覆写,必须先按 F2 或双击才能输入。 }
    procedure KeyPress(var Key: Char); override;
    { 这一格允许输入哪些字符(空 = 不限)。取自列级 ValidChars。 }
    { gekSpin / gekSlider 的范围与 gekMask 的掩码,取自列;列没配就用默认。 }
    function  EditorMinFor(ACol: Integer): Integer; virtual;
    function  EditorMaxFor(ACol: Integer): Integer; virtual;
    function  EditMaskFor(ACol: Integer): string; virtual;
    function  CharCaseFor(ACol: Integer): TEditCharCase; virtual;
    function  ValidCharsFor(ACol, ARow: Integer): string; virtual;
    function  MaxEditLengthFor(ACol, ARow: Integer): Integer; virtual;
    { 内建的行内文本编辑器。protected 暴露给派生类与测试 —— 用来断言
      "宿主 EditLink 接管时内建编辑器不出场"。 }
    property InlineEditor: TTyEdit read FEditor;
    property SpinEditor: TTySpinEdit read FSpinEditor;
    property SliderEditor: TTyTrackBar read FSliderEditor;
    property MemoEditor: TTyMemo read FMemoEditor;
    property MaskEditor: TTyMaskEdit read FMaskEditor;
    property CalcEditor: TTyCalcEdit read FCalcEditor;
    property DateEditor: TTyDateTimePicker read FDateEditor;
    { 星级格里第 AStar 颗星(1-based)的矩形。绘制与命中共用它。 }
    function RatingStarRect(ACol, ARow, AStar: Integer): TRect;
    procedure SetRatingByPoint(ACol, ARow, X, Y: Integer); override;
    { 触发省略号按钮:问宿主要新值,接受就写回(照常走 OnCellEdited)。 }
    procedure InvokeEllipsis(ACol, ARow: Integer); virtual;
    procedure DblClick; override;
    { 该格该用哪种编辑器。默认取 DefaultEditorKind,OnGetEditorKind 可逐格覆盖。 }
    function EditorKindFor(ACol, ARow: Integer): TTyGridEditorKind; virtual;
    { 勾选框语义:'1'/'true'/'是'/'y' 都算勾上。写回时统一成 '1'/''。 }
    function  CellDisplayFor(ACol, ARow: Integer): TTyGridCellDisplay; virtual;
    { 基类的问法(按钮矩形/命中要用),转给上面这个。 }
    function  CellDisplayOf(ACol, ARow: Integer): TTyGridCellDisplay; override;
    function  IsActiveCell(ACol, ARow: Integer): Boolean; override;
    function  FAttrs2Find(ACol, ARow: Integer): TTyGridCellAttr; override;
    function  ShouldDrawCellText(ACol, ARow: Integer): Boolean; override;
    function  DoDrawCell(P: TTyPainter; ACol, ARow: Integer): Boolean; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    function  RowHeightOf(ARow: Integer): Integer; override;
    function  RowTops: TTyIntArray; override;
    procedure InvalidateRowMetrics; override;
    procedure RenderColorCell(P: TTyPainter; ACol, ARow: Integer;
      const AFrame: TTyStyleSet); virtual;
    procedure RenderImageCell(P: TTyPainter; ACol, ARow: Integer;
      const AFrame: TTyStyleSet); virtual;
    procedure RenderProgressCell(P: TTyPainter; ACol, ARow: Integer;
      const AFrame: TTyStyleSet); virtual;
    procedure RenderRatingCell(P: TTyPainter; ACol, ARow: Integer;
      const AFrame: TTyStyleSet); virtual;
    function  CellChecked(ACol, ARow: Integer): Boolean;
    procedure ToggleCellChecked(ACol, ARow: Integer);
    { 弹取色对话框改这一格的颜色(值存 #RRGGBB)。 }
    procedure ToggleCellColor(ACol, ARow: Integer);
    { 勾选框的绘制槽(单元格内居中的小方块)。命中与绘制共用它。 }
    function  CheckBoxRect(ACol, ARow: Integer): TRect;
    { 省略号按钮的矩形(贴格右缘)。不是省略号格时返回空矩形;与绘制同源。 }
    function  EllipsisRect(ACol, ARow: Integer): TRect;
    procedure RenderEllipsisCell(P: TTyPainter; ACol, ARow: Integer;
      const AFrame: TTyStyleSet); virtual;
    procedure RenderCheckCell(P: TTyPainter; ACol, ARow: Integer;
      const AFrame: TTyStyleSet); virtual;
    procedure RenderFooter(P: TTyPainter; const M: TTyGridMetrics;
      const AFooterRect: TRect; const AFrame: TTyStyleSet); override;
    procedure AccumulateCell(ACol, ADataRow: Integer; AKind: TTyGridAggregate;
      var AAcc: Double; var ACount: Integer; var AStarted: Boolean);
    function  AggregatePrefix(AKind: TTyGridAggregate): string;
    procedure RenderGroupRow(P: TTyPainter; APos, AGroupIndex: Integer;
      const M: TTyGridMetrics; const AFrame: TTyStyleSet); virtual;
    { 分组行上的折叠三角槽。命中与绘制共用。 }
    function  GroupToggleRect(APos: Integer): TRect;
    function DisplayToData(APos: Integer): Integer; override;
    function DataToDisplay(ARow: Integer): Integer; override;
    function DisplayRowCount: Integer; override;
    procedure SetShowGroupSubtotals(AValue: Boolean);
    procedure SetShowFilterButtons(AValue: Boolean);
    function ShowsFilterButton(ACol: Integer): Boolean; override;
    function HasMergedCells: Boolean; override;
    function SameMergedCell(ACol1, ARow1, ACol2, ARow2: Integer): Boolean; override;
    function ColumnFilterActive(ACol: Integer): Boolean; override;
    function SortRankOf(ACol: Integer): Integer; override;
    function SortColumnCountOf: Integer; override;
    procedure InvalidateGridOrder; override;
    { 合并区:基准格的矩形跨满整个区,被它覆盖的格没有自己的矩形。 }
    function CellRect(ACol, ARow: Integer): TRect; override;
    procedure MapToBaseCell(var ACol, ARow: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { --- 行列增删 ---
      按**数据行**下标操作;内容随之整体搬移(稀疏存储只搬写过的格)。 }
    procedure InsertRow(ARow: Integer);
    procedure DeleteRow(ARow: Integer);
    procedure InsertColumn(ACol: Integer);
    procedure DeleteColumn(ACol: Integer);
    { 复数版。一次搬完再重排一次显示序,比循环调单数版快得多
      —— 后者每插一行都要重建一遍 FOrder。 }
    { 批量期间挂起显示序重建 —— 否则每插一行都要重建一遍 FOrder。
      成对使用,可嵌套。 }
    procedure BeginUpdateOrder;
    procedure EndUpdateOrder;
    procedure InsertRows(ARow, ACount: Integer);
    procedure RemoveRows(ARow, ACount: Integer);
    procedure InsertCols(ACol, ACount: Integer);
    procedure RemoveCols(ACol, ACount: Integer);
    { 按**数据行**搬动。显示序会在下一次重建时自然跟上。 }
    procedure MoveRow(AFrom, ATo: Integer);
    procedure SwapRows(ARow1, ARow2: Integer);
    procedure MoveColumn(AFrom, ATo: Integer);
    { 剪切 = 复制 + 清空(只读格不清)。 }
    procedure CutToClipboard;

    { 把某列宽度自动适配到内容(取表头与**已写入**单元格里最宽的那个)。
      只量已写过的格,所以百万行空表也不会扫全表。 }
    procedure AutoFitColumn(ACol: Integer);
    procedure AutoFitColumnWidth(ACol: Integer); override;

    { 清空全部单元格内容(不动行列结构)。 }
    procedure ClearCells;
    { 写过的单元格个数 —— 稀疏性的可观测证据。 }
    function StoredCellCount: Integer;

    { 开始编辑当前(或指定)单元格。只读、或该格编辑器为 gekNone 时不开。 }
    function BeginEdit: Boolean; overload;
    function BeginEdit(ACol, ARow: Integer): Boolean; overload;
    { 结束编辑。ACommit=True 写回存储(经 OnCellEdited 可否决)。 }
    procedure EndEdit(ACommit: Boolean);
    { 某个单元格是否在当前矩形选区内(锚点 ↔ 光标)。
      纵向按**显示序**判定 —— 选区是屏幕上的一块矩形,不是数据行号的区间;
      排序后行的相对位置变了,选区自然跟着屏幕走。 }
    function IsCellSelected(ACol, ARow: Integer): Boolean;
    { 把选区锚点钉在当前光标处(单击时调用),之后 Shift+点/Shift+方向键即可拉出区域。 }
    procedure AnchorSelection;
    { 把光标移到 (ACol,ARow),越界自动钳制;OnSelectCell 可否决。
      **public**:用代码定位光标(跳转到某条记录)是最常见的宿主动作之一。 }
    procedure MoveCursor(ACol, ARow: Integer); virtual;
    { 按内容(含换行)把一行/所有行的高度调到刚好放得下。 }
    procedure AutoFitRow(ARow: Integer);
    procedure AutoFitRows;

    { --- 选择 API(从前一个 public 的都没有) --- }
    procedure SelectAll;
    { 数据行坐标;越界自动钳制。 }
    procedure SelectRange(ACol1, ARow1, ACol2, ARow2: Integer);
    procedure SelectRows(ARow1, ARow2: Integer);
    { --- 行的显式隐藏 ---
      与"用过滤间接隐藏"不是一回事:过滤是条件,隐藏是**事实**;
      ClearFilters 会把过滤抹掉,却不该把用户手工隐藏的行放出来。 }
    procedure HideRow(ARow: Integer);
    procedure UnHideRow(ARow: Integer);
    function  IsHiddenRow(ARow: Integer): Boolean;
    function  NumHiddenRows: Integer;
    procedure UnHideAllRows;
    procedure ClearSelection;
    { 活动选区(数据行坐标)。离散多选时只代表最后那一块。 }
    function  Selection: TRect;
    { 选中的单元格总数(0 表示只有光标那一格)。 }
    function SelectedCellCount: Integer;
    { 选区聚合 —— 状态栏那句"已选 12 项,合计 3400"。
      只统计**数值可解析**的格,非数值格直接跳过(与列聚合同一条规则)。 }
    function SelectionSum: Double;
    function SelectionAvg: Double;
    function SelectionMin: Double;
    function SelectionMax: Double;
  private
    procedure ForEachSelectedNumber(out ACount: Integer;
      out ASum, AMin, AMax: Double);
  public

    { 该列出现过的**去重值**(按显示序的原始数据,不受本列自身过滤影响)——
      列头筛选下拉就是拿它当候选。 }
    procedure DistinctColumnValues(ACol: Integer; AItems: TStrings);
    { 打开某列的列头筛选下拉。 }
    procedure ShowColumnFilterDropDown(ACol: Integer);

    { 给某列设"包含"过滤(不区分大小写)。传空串即清掉该列的过滤。 }
    procedure SetColumnFilter(ACol: Integer; const AText: string);
    { 带比较方式的过滤。SetColumnFilter 等价于 gfoContains。 }
    procedure SetColumnFilterEx(ACol: Integer; AOp: TTyGridFilterOp;
      const AText: string);
    function  ColumnFilterOp(ACol: Integer): TTyGridFilterOp;
    { 这一列现在有没有在过滤(漏斗要不要点亮)。 }
    function  ColumnIsFiltered(ACol: Integer): Boolean;
    { 过滤之后还剩多少行。 }
    function  FilteredRowCount: Integer;
    function  ColumnFilter(ACol: Integer): string;
    { 按**值集合**过滤某列(列头下拉勾选用)。AValues=nil 或空即清掉。
      与文本包含过滤是 AND 关系。 }
    procedure SetColumnValueFilter(ACol: Integer; AValues: TStrings);
    { 候选值 + 每个值的行数(计数放在 AItems.Objects 里)。 }
    procedure DistinctColumnValueCounts(ACol: Integer; AItems: TStrings);
    procedure ColumnValueFilter(ACol: Integer; AOut: TStrings);
    procedure ClearFilters;
    { 通过过滤的行数(= 当前显示的行数)。 }
    function  VisibleRowCount: Integer;

    { --- 分组 ---
      按某列分组:显示序里插入**合成的分组行**(它不对应任何数据行)。
      FOrder 里 >=0 是数据行,<0 是分组行(编码为 -(组号+1))。 }
    procedure GroupByColumn(ACol: Integer);
    procedure UngroupRows;
    property  GroupColumn: Integer read FGroupCol;
    { 该显示位置是不是分组行;是则给出组号。 }
    function  IsGroupRow(APos: Integer; out AGroupIndex: Integer): Boolean;
    function  GroupInfo(AIndex: Integer): TTyGridGroupInfo;
    function  GroupCount: Integer;
    procedure ToggleGroup(AIndex: Integer);

    { --- 汇总 ---
      聚合只统计**通过过滤的行**,所以筛完总计会跟着变(这才是用户要的)。 }
    procedure SetColumnAggregate(ACol: Integer; AKind: TTyGridAggregate);
    function  ColumnAggregate(ACol: Integer): TTyGridAggregate;
    { 某列的聚合结果。gagCount 返回可见行数;其余按数值统计,非数值格跳过。 }
    function  AggregateValue(ACol: Integer): Double;
    { 某一组内、某一列的小计(按组的成员数据行算,折叠着也算得出来)。 }
    function  GroupAggregateValue(AGroupIndex, ACol: Integer): Double;
    { 分组行上该列显示的小计文字(与页脚同一套前缀与格式)。 }
    function  GroupFooterText(AGroupIndex, ACol: Integer): string;
    { 汇总带上该列显示的文字(已格式化;OnGetFooterText 可覆盖)。 }
    function  FooterText(ACol: Integer): string;

    { --- 逐格持久外观 ---
      与钩子的区别:钩子是"每次画都问一遍"的规则,这里是**落盘**的事实 ——
      用户手工把某几格涂黄,关掉再打开还得是黄的。设成 clNone 即清除。 }
    property CellColors[ACol, ARow: Integer]: TTyColor
      read GetCellColor write SetCellColor;
    property CellTextColors[ACol, ARow: Integer]: TTyColor
      read GetCellTextColor write SetCellTextColor;
    { 整行底色 —— 内部就是把该行每一格都设一遍(行数远少于格数,不心疼)。 }
    procedure SetRowColor(ARow: Integer; AColor: TTyColor);
    { 逐格只读。比"整列只读"更细,用于"已审核的这几行不可改"。 }
    property CellReadOnly[ACol, ARow: Integer]: Boolean
      read GetCellReadOnly write SetCellReadOnly;

    { --- 单元格合并 ---
      只记基准格的跨度;被覆盖的格没有自己的矩形,命中时归到基准格。 }
    { 把**当前选区**合并成一块。返回 False = 没合(选区不足一块,
      或者它在数据行上不连续 —— 见实现里的说明)。

      宿主**不要**自己算跨度:选区矩形活在显示序空间,而 Selection 对外给的是
      数据行坐标,两个数据行下标之差在任何空间里都不是"几行"。
      这个陷阱已经真实咬过一次(排过序的表上合并,吞掉几十行)。 }
    function  MergeSelection: Boolean;
    procedure MergeCells(ACol, ARow, AColSpan, ARowSpan: Integer);
    procedure UnmergeCells(ACol, ARow: Integer);
    procedure ClearMerges;
    { (ACol,ARow) 是不是某个合并区的**基准格**(左上角)。 }
    function  IsBaseCell(ACol, ARow: Integer): Boolean;
    { 取 (ACol,ARow) 所属合并区的基准格;不在任何合并区里就是它自己。 }
    procedure BaseCellOf(ACol, ARow: Integer; out ABaseCol, ABaseRow: Integer);
    function  CellSpan(ACol, ARow: Integer; out AColSpan, ARowSpan: Integer): Boolean;

    { --- 查找 / 替换 ---
      按**显示序**从当前光标之后环绕查找 —— 用户找的是他看到的顺序,不是数据行号。 }
    function  FindCell(const AText: string; ACaseSensitive, AWholeCell: Boolean;
      out ACol, ARow: Integer): Boolean;
    { 找到就把光标移过去并滚进视野。 }
    function  FindNext(const AText: string; ACaseSensitive, AWholeCell: Boolean): Boolean;
    { 替换;AAll=True 替换全部,返回替换个数。只读格跳过。 }
    function  ReplaceCells(const AFind, AReplace: string;
      ACaseSensitive, AWholeCell, AAll: Boolean): Integer;

    { --- 剪贴板 / CSV ---
      导出走**显示序**(所见即所得:过滤掉的行不出现,排序后的次序被保留);
      而寻址仍是数据行 —— 两者由行序间接层桥接。 }
    { 当前选区导出为制表符分隔文本(Excel 剪贴板即这种格式,可直接粘进去)。 }
    function  SelectionAsText: string;
    procedure CopySelectionToClipboard;
    { 从制表符/换行分隔的文本粘贴到以当前光标为左上角的区域。 }
    procedure PasteFromText(const AText: string);
    procedure PasteFromClipboard;
    { CSV。ADelimiter 默认逗号;含分隔符/引号/换行的字段自动加引号。 }
    function  SaveToCSVText(ADelimiter: Char = ','): string;
    { 导出 HTML 表格(含表头)。与 CSV 一致走显示序:所见即所得。 }
    function  SaveToHTMLText: string;
    procedure SaveToHTMLFile(const AFileName: string);
    procedure LoadFromCSVText(const AText: string; ADelimiter: Char = ',');
    procedure SaveToCSVFile(const AFileName: string; ADelimiter: Char = ',');
    procedure LoadFromCSVFile(const AFileName: string; ADelimiter: Char = ',');

    { 按某列排序。ACol < 0 表示取消排序、回到原始数据顺序。 }
    procedure SortByColumn(ACol: Integer; ADirection: TTySortDirection);
    { 点列头的默认行为:同列则反向,换列则升序;再点第三次取消排序。 }
    procedure ToggleSortColumn(ACol: Integer);
    property SortColumn: Integer read FSortCol;
    { 追加一个次级排序列(Shift+点列头就是它);已在键里就翻转它的方向。 }
    procedure AddSortColumn(ACol: Integer; ADirection: TTySortDirection);
    procedure ClearSortColumns;
    function  SortColumnCount: Integer;
    function  SortColumnAt(AIndex: Integer): TTyGridSortKey;
    { 某一列当前的排序方向;不是排序键时答升序。 }
    function  SortDirectionOf(ACol: Integer): TTySortDirection;
    { 分组行显示成什么。默认走 GroupRowFormat(初值取自 resourcestring,可翻译);
      派生类可以整个改写。 }
    function  GroupRowText(const AKey: string; ACount: Integer): string; virtual;
    { 分组全展开 / 全折叠。 }
    { 导航时跳过不可编辑的格。默认关 —— 打开后方向键/Tab 会掠过只读列,
      录入长表时手指不用一直"撞墙"。 }
    property SkipReadOnlyCells: Boolean read FSkipReadOnly write FSkipReadOnly
      default False;
    function  NextEditableCol(AFrom, AStep, ARow: Integer): Integer;
    procedure ExpandAllGroups;
    procedure CollapseAllGroups;
    property SortDirection: TTySortDirection read FSortDir;

    property Editing: Boolean read FEditing;
    property Editor: TTyEdit read FEditor;
    property PickEditor: TTyComboBox read FPickEditor;
    property Cells[ACol, ARow: Integer]: string read GetCells write SetCells;
  published
    { 当前单元格。 }
    property Col: Integer read FCol write SetCol default 0;
    property Row: Integer read FRow write SetRow default 0;
    property OnSelectCell: TTyGridSelectCellEvent read FOnSelectCell write FOnSelectCell;
    { 整表只读:任何编辑都开不起来。 }
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    { 选择粒度:单元格矩形 / 整行 / 整列。 }
    { 分组行的格式串:%s = 分组值,%d = 组内行数。 }
    property GroupRowFormat: string read FGroupRowFormat write FGroupRowFormat;
    property SelectionMode: TTyGridSelectionMode
      read FSelectionMode write SetSelectionMode default gsmCell;
    property OnSelectionChanged: TNotifyEvent
      read FOnSelectionChanged write FOnSelectionChanged;
    property DefaultEditorKind: TTyGridEditorKind
      read FDefaultEditorKind write FDefaultEditorKind default gekText;
    property OnGetEditorKind: TTyGridGetEditorKindEvent
      read FOnGetEditorKind write FOnGetEditorKind;
    property OnCellEdited: TTyGridCellEditedEvent read FOnCellEdited write FOnCellEdited;
    { 排序比较方式:文本还是数值。数值列用 gskText 排会得到 '10' < '9' 这种结果。 }
    property SortKind: TTyGridSortKind read FSortKind write FSortKind default gskText;
    { 空值排最前还是最后(翻方向时位置不变)。 }
    property BlanksPosition: TTyGridBlanksPosition read FBlanksPosition
      write FBlanksPosition default gbpLast;
    { 文本比较区不区分大小写。从前写死 CompareText(恒不区分)。 }
    property SortIgnoreCase: Boolean read FSortIgnoreCase write FSortIgnoreCase
      default True;
    property OnCanSort: TTyGridCanSortEvent read FOnCanSort write FOnCanSort;
    { 自定义比较;置 AResult 即接管该列的比较。 }
    property OnCompareCells: TTyGridCompareEvent read FOnCompareCells write FOnCompareCells;
    property OnFilterRow: TTyGridFilterRowEvent read FOnFilterRow write FOnFilterRow;
    property OnGetPickList: TTyGridGetPickListEvent read FOnGetPickList write FOnGetPickList;
    { 宿主自带编辑器的扩展点。留 nil 就走内建编辑器。 }
    property OnCreateEditLink: TTyGridCreateEditLinkEvent
      read FOnCreateEditLink write FOnCreateEditLink;
    { 粘贴块超出网格时自动扩行/扩列。 }
    property AutoGrowOnPaste: Boolean read FAutoGrowOnPaste write FAutoGrowOnPaste
      default True;
    property OnClipboardCopy: TTyGridClipboardEvent
      read FOnClipboardCopy write FOnClipboardCopy;
    property OnClipboardPaste: TTyGridClipboardEvent
      read FOnClipboardPaste write FOnClipboardPaste;
    property OnBeforePasteCell: TTyGridPasteCellEvent
      read FOnBeforePasteCell write FOnBeforePasteCell;
    property OnAfterPasteCell: TTyGridCellMouseEvent
      read FOnAfterPasteCell write FOnAfterPasteCell;
    property OnGetFooterText: TTyGridGetFooterTextEvent
      read FOnGetFooterText write FOnGetFooterText;
    { 单元格显示方式(与编辑方式正交)。 }
    property DefaultCellDisplay: TTyGridCellDisplay
      read FDefaultCellDisplay write FDefaultCellDisplay default gcdText;
    property OnGetCellDisplay: TTyGridGetCellDisplayEvent
      read FOnGetCellDisplay write FOnGetCellDisplay;
    { 逐行行高。接了它即启用可变行高;不接则全表等高(走整除快路径)。 }
    property OnGetRowHeight: TTyGridGetRowHeightEvent
      read FOnGetRowHeight write FOnGetRowHeight;
    { 完全自绘某个单元格(置 AHandled 即接管)。 }
    property OnDrawCell: TTyGridDrawCellEvent read FOnDrawCell write FOnDrawCell;
    { 逐格提示文本(悬停显示)。 }
    property OnGetCellHint: TTyGridGetCellHintEvent
      read FOnGetCellHint write FOnGetCellHint;
    { 列头上显示筛选按钮(点它弹出去重值的勾选下拉)。 }
    property ShowFilterButtons: Boolean
      read FShowFilterButtons write SetShowFilterButtons default False;
    { 分组行上按列显示小计。哪些列有小计,由 SetColumnAggregate 决定 ——
      与页脚汇总用的是同一份配置,不必再配一遍。 }
    property ShowGroupSubtotals: Boolean
      read FShowGroupSubtotals write SetShowGroupSubtotals default True;
  end;

var
  { 勾选框额外认作"真"的**本地化**词(中文表里常见 '是')。
    默认从 resourcestring 播种,可在运行时改 —— 与本库 TyFallbackFontName 同一惯例。
    通用真值 1/true/yes/y 永远认,不受它影响。 }
  TyGridCheckedWord: string;

implementation

const
  { "没设颜色"的哨兵:alpha = 0 的颜色在本库里恒不可见,拿来当"无"最省事,
    不必再多一个平行的 Boolean。 }
  TyColorNone: TTyColor = 0;

  { "这不是个日期"的哨兵。用一个不可能出现的 TDateTime 值,
    比再拿一个 Boolean 数组去记省事,也不会和真实日期撞上。 }
  NoDateSentinel = -1.0e18;
  { 星级的满分。绘制与命中都用它,别各写一个 5。 }
  TyGridRatingMax = 5;

{ 过滤表达式的存储格式是 '<op序号>|<文本>' —— 一条字符串装下两样东西,
  沿用既有的 name=value 存储,不必再开一张表。 }
function TyGridEncodeFilter(AOp: TTyGridFilterOp; const AText: string): string;
begin
  Result := IntToStr(Ord(AOp)) + '|' + AText;
end;

procedure TyGridDecodeFilter(const AEncoded: string; out AOp: TTyGridFilterOp;
  out AText: string);
var
  bar: Integer;
begin
  AOp := gfoContains;
  AText := AEncoded;
  bar := Pos('|', AEncoded);
  if bar <= 0 then Exit;              { 老格式(纯文本)= 包含 }
  AOp := TTyGridFilterOp(StrToIntDef(Copy(AEncoded, 1, bar - 1), 0));
  AText := Copy(AEncoded, bar + 1, MaxInt);
end;

{ 一个格值符不符合一条过滤表达式。 }
function TyGridFilterMatches(const ACellText, AEncoded: string): Boolean;
var
  op: TTyGridFilterOp;
  pat, a, b: string;
  va, vb: Double;
begin
  TyGridDecodeFilter(AEncoded, op, pat);
  if pat = '' then Exit(True);

  a := UpperCase(ACellText);
  b := UpperCase(pat);
  case op of
    gfoEquals:     Exit(a = b);
    gfoNotEquals:  Exit(a <> b);
    gfoStartsWith: Exit(Copy(a, 1, Length(b)) = b);
    gfoEndsWith:   Exit((Length(a) >= Length(b)) and
                        (Copy(a, Length(a) - Length(b) + 1, Length(b)) = b));
    gfoGreater, gfoGreaterEqual, gfoLess, gfoLessEqual:
      begin
        { 数值比较:格里不是数就一律不通过 —— 把 'abc' 算作 0 会让
          "筛 >-1"把整列文本都放进来,那不是用户要的。 }
        va := StrToFloatDef(Trim(ACellText), NaN);
        vb := StrToFloatDef(Trim(pat), NaN);
        if IsNan(va) or IsNan(vb) then Exit(False);
        case op of
          gfoGreater:      Exit(va > vb);
          gfoGreaterEqual: Exit(va >= vb);
          gfoLess:         Exit(va < vb);
        else               Exit(va <= vb);
        end;
      end;
  end;
  Result := Pos(b, a) > 0;            { gfoContains }
end;

{ 一段文字在给定宽度下会占几行 —— 与 BGRA 的 Wordbreak 断法保持一致:
  在空格处断,单个"词"仍超宽时按字符硬断(CJK 没有空格,靠的就是这条)。

  测量与绘制必须用**同一支已配置好的位图字体**(ABmp),否则算出来的行数
  和画出来的对不上。 }
function TyCountWrappedLines(ABmp: TBGRABitmap; const AText: string;
  AMaxWidth: Integer): Integer;
var
  i, lineW, chW, n: Integer;
  ch: string;
  lastSpace, lineStart: Integer;
  cur: string;
begin
  Result := 1;
  if (AText = '') or (AMaxWidth <= 0) then Exit;
  cur := '';
  i := 1;
  n := Length(AText);
  lineW := 0;
  lastSpace := 0;
  lineStart := 1;
  while i <= n do
  begin
    { 按 UTF-8 字符前进,别把多字节切开。 }
    chW := 1;
    if Byte(AText[i]) >= $C0 then
    begin
      if Byte(AText[i]) >= $F0 then chW := 4
      else if Byte(AText[i]) >= $E0 then chW := 3
      else chW := 2;
    end;
    ch := Copy(AText, i, chW);
    if ch = ' ' then lastSpace := i;

    Inc(lineW, ABmp.TextSize(ch).cx);
    if lineW > AMaxWidth then
    begin
      Inc(Result);
      if lastSpace > lineStart then
      begin
        i := lastSpace + 1;      { 回退到上一个空格处断行 }
        lineStart := i;
        lastSpace := 0;
        lineW := 0;
        Continue;
      end;
      lineStart := i;
      lineW := ABmp.TextSize(ch).cx;
    end;
    Inc(i, chW);
  end;
end;

{ ---- 表头分组 ------------------------------------------------------------- }

constructor TTyGridHeaderGroup.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FAlignment := taCenter;
end;

procedure TTyGridHeaderGroup.Changed;
begin
  if (Collection <> nil) and (Collection is TTyGridHeaderGroups) then
    if Assigned(TTyGridHeaderGroups(Collection).OnChange) then
      TTyGridHeaderGroups(Collection).OnChange(Collection);
end;

procedure TTyGridHeaderGroup.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Changed;
end;

procedure TTyGridHeaderGroup.SetFirstCol(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FFirstCol = AValue then Exit;
  FFirstCol := AValue;
  Changed;
end;

procedure TTyGridHeaderGroup.SetLastCol(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FLastCol = AValue then Exit;
  FLastCol := AValue;
  Changed;
end;

procedure TTyGridHeaderGroup.Assign(ASource: TPersistent);
begin
  if ASource is TTyGridHeaderGroup then
  begin
    FText := TTyGridHeaderGroup(ASource).Text;
    FFirstCol := TTyGridHeaderGroup(ASource).FirstCol;
    FLastCol := TTyGridHeaderGroup(ASource).LastCol;
    FLevel := TTyGridHeaderGroup(ASource).Level;
    FAlignment := TTyGridHeaderGroup(ASource).Alignment;
    Changed;
  end
  else
    inherited Assign(ASource);
end;

constructor TTyGridHeaderGroups.Create;
begin
  inherited Create(TTyGridHeaderGroup);
end;

function TTyGridHeaderGroups.Add: TTyGridHeaderGroup;
begin
  Result := TTyGridHeaderGroup(inherited Add);
end;

procedure TTyGridHeaderGroups.Update(AItem: TCollectionItem);
begin
  inherited Update(AItem);
  if Assigned(FOnChange) then FOnChange(Self);
end;

function TTyGridHeaderGroups.GroupAt(ALevel, ACol: Integer): TTyGridHeaderGroup;
var
  i: Integer;
  g: TTyGridHeaderGroup;
begin
  Result := nil;
  for i := 0 to Count - 1 do
  begin
    g := TTyGridHeaderGroup(Items[i]);
    if (g.Level = ALevel) and (ACol >= g.FirstCol) and (ACol <= g.LastCol) then
      Exit(g);
  end;
end;

{ ---- TTyGridColumn -------------------------------------------------------- }

constructor TTyGridColumn.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FEditorKind := gekText;
  FAggregate := gagNone;
  FSortKind := gskAuto;
  FMinValue := 0;
  FMaxValue := 100;
  FPickList := TStringList.Create;
end;

destructor TTyGridColumn.Destroy;
begin
  FPickList.Free;
  inherited Destroy;
end;

procedure TTyGridColumn.SetPickList(AValue: TStrings);
begin
  FPickList.Assign(AValue);
end;

procedure TTyGridColumn.SetEditorKind(AValue: TTyGridEditorKind);
begin
  FEditorKind := AValue;
  { 一旦被写过就算"显式设过" —— 包括显式写成 gekText。 }
  FUseEditorKind := True;
end;

procedure TTyGridColumn.Assign(ASource: TPersistent);
begin
  inherited Assign(ASource);
  if ASource is TTyGridColumn then
  begin
    FEditorKind := TTyGridColumn(ASource).EditorKind;
    FUseEditorKind := TTyGridColumn(ASource).UseEditorKind;
    FReadOnly := TTyGridColumn(ASource).ReadOnly;
    FPickList.Assign(TTyGridColumn(ASource).PickList);
    FAggregate := TTyGridColumn(ASource).Aggregate;
    FFormat := TTyGridColumn(ASource).Format;
    FValidChars := TTyGridColumn(ASource).ValidChars;
    FMaxEditLength := TTyGridColumn(ASource).MaxEditLength;
    FSortKind := TTyGridColumn(ASource).SortKind;
    FMinValue := TTyGridColumn(ASource).MinValue;
    FMaxValue := TTyGridColumn(ASource).MaxValue;
    FEditMask := TTyGridColumn(ASource).EditMask;
    FCharCase := TTyGridColumn(ASource).CharCase;
  end;
end;

{ ---- TTyGridCellAttr / Store ---------------------------------------------- }

constructor TTyGridCellAttr.Create;
begin
  inherited Create;
  ColSpan := 1;
  RowSpan := 1;
  Alignment := taLeftJustify;
end;

function TTyGridCellAttr.IsDefault: Boolean;
begin
  Result := (ColSpan = 1) and (RowSpan = 1)
    and not HasBackground and not HasTextColor
    and not HasAlignment and not HasFontStyle
    and not ReadOnly;
end;

procedure TTyGridCellAttr.Assign(ASrc: TTyGridCellAttr);
begin
  if ASrc = nil then Exit;
  ColSpan := ASrc.ColSpan;           RowSpan := ASrc.RowSpan;
  HasBackground := ASrc.HasBackground; Background := ASrc.Background;
  HasTextColor := ASrc.HasTextColor;   TextColor := ASrc.TextColor;
  HasAlignment := ASrc.HasAlignment;   Alignment := ASrc.Alignment;
  HasFontStyle := ASrc.HasFontStyle;   FontStyle := ASrc.FontStyle;
  ReadOnly := ASrc.ReadOnly;
end;

constructor TTyGridCellAttrStore.Create;
begin
  inherited Create;
  FItems := TStringList.Create;
  FItems.Sorted := True;
  FItems.Duplicates := dupIgnore;
  FItems.OwnsObjects := True;
end;

destructor TTyGridCellAttrStore.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TTyGridCellAttrStore.Find(const AKey: string): TTyGridCellAttr;
var
  i: Integer;
begin
  i := FItems.IndexOf(AKey);
  if i < 0 then Result := nil else Result := TTyGridCellAttr(FItems.Objects[i]);
end;

function TTyGridCellAttrStore.Ensure(const AKey: string): TTyGridCellAttr;
var
  i: Integer;
begin
  Result := Find(AKey);
  if Result <> nil then Exit;
  Result := TTyGridCellAttr.Create;
  i := FItems.AddObject(AKey, Result);
  { dupIgnore 时重复键不会收下对象 —— 不管的话就是内存泄漏(文本缓存那里踩过)。 }
  if (i < 0) or (FItems.Objects[i] <> Result) then
  begin
    Result.Free;
    if i < 0 then Exit(nil);
    Result := TTyGridCellAttr(FItems.Objects[i]);
  end;
end;

procedure TTyGridCellAttrStore.Remove(const AKey: string);
var
  i: Integer;
begin
  i := FItems.IndexOf(AKey);
  if i >= 0 then FItems.Delete(i);     { OwnsObjects → 顺带释放 }
end;

procedure TTyGridCellAttrStore.DropIfDefault(const AKey: string);
var
  a: TTyGridCellAttr;
begin
  a := Find(AKey);
  if (a <> nil) and a.IsDefault then Remove(AKey);
end;

procedure TTyGridCellAttrStore.Clear;
begin
  FItems.Clear;
end;

procedure TTyGridCellAttrStore.MoveEntry(const AFrom, ATo: string);
var
  src, dst: TTyGridCellAttr;
begin
  src := Find(AFrom);
  if src = nil then
  begin
    Remove(ATo);      { 源没有属性 → 目标也不该留着旧的 }
    Exit;
  end;
  dst := Ensure(ATo);
  if dst = nil then Exit;
  dst.Assign(src);
  Remove(AFrom);
end;

function TTyGridCellAttrStore.IsEmpty: Boolean;
begin
  Result := FItems.Count = 0;
end;

function TTyGridCellAttrStore.Count: Integer;
begin
  Result := FItems.Count;
end;

procedure TTyGridCellAttrStore.SnapshotKeys(ADest: TStrings);
begin
  ADest.Assign(FItems);
end;

constructor TTyCustomGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { 让表头造网格自己的列类。 }
  FHeader := TTyHeader.Create(TTyGridColumn);
  FHeader.OnChange := @HeaderChanged;
  FRowCount := 0;
  FDefaultRowHeight := 22;
  FFixedCols := 0;
  FFixedRows := 0;
  FIndicatorWidth := 30;
  FShowIndicator := False;
  FGridLineStyle := glsBoth;
  FHeaderGroups := TTyGridHeaderGroups.Create;
  FHeaderGroups.OnChange := @HeaderGroupsChanged;
  FGroupHeaderHeight := 22;
  FGridLineWidth := 1;
  FHoverCol := -1;
  FHoverRow := -1;
  FPressedBtnCol := -1;
  FPressedBtnRow := -1;
  FResizeRow := -1;
  FRowHeights := TStringList.Create;
  FRowHeights.Sorted := True;
  FRowHeights.Duplicates := dupIgnore;
  FTextCache := TStringList.Create;
  FTextCache.Sorted := True;          { 排序 → IndexOf 走二分 }
  FTextCache.Duplicates := dupIgnore;
  FTextCache.OwnsObjects := True;
  FShowFooter := False;
  FFooterHeight := 24;
  FScrollX := 0;
  FScrollY := 0;
  FDragCol := -1;
  FResizeCol := -1;

  { 两条内嵌滚动条。csNoDesignVisible:内部子控件不该出现在设计器的对象树里。 }
  FVScroll := TTyScrollBar.Create(Self);
  FVScroll.Parent := Self;
  FVScroll.Kind := sbVertical;
  FVScroll.AnimationsEnabled := False;
  FVScroll.OnChange := @VScrollChange;
  FVScroll.ControlStyle := FVScroll.ControlStyle + [csNoDesignVisible];
  FVScroll.Visible := False;

  FHScroll := TTyScrollBar.Create(Self);
  FHScroll.Parent := Self;
  FHScroll.Kind := sbHorizontal;
  FHScroll.AnimationsEnabled := False;
  FHScroll.OnChange := @HScrollChange;
  FHScroll.ControlStyle := FHScroll.ControlStyle + [csNoDesignVisible];
  FHScroll.Visible := False;
end;

destructor TTyCustomGrid.Destroy;
begin
  { 先摘监听再释放:否则析构过程中列集合的变更会回调到半毁的控件上。 }
  FHeader.OnChange := nil;
  FHeader.Free;
  FTextCache.Free;      { OwnsObjects → 顺带释放缓存的位图 }
  FSurface.Free;
  FRowHeights.Free;
  FHeaderGroups.Free;
  inherited Destroy;
end;

function TTyCustomGrid.GetStyleTypeKey: string;
begin
  { 自己的 typeKey,绝不借用树/列表的键 —— 借来的键在外观主题层够不着,
    而且改它会波及那些控件。 }
  Result := 'TyGrid';
end;

function TTyCustomGrid.Dpi: Integer;
begin
  Result := Font.PixelsPerInch;
  if Result <= 0 then Result := 96;
end;

function TTyCustomGrid.ScaleI(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Dpi, 96);
end;

function TTyCustomGrid.UnscaleI(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, 96, Dpi);
end;

procedure TTyCustomGrid.HeaderChanged(Sender: TObject);
begin
  InvalidateColumnCache;   { 列宽/列数/可见性变了 → 列几何缓存作废 }
  UpdateScrollBars;   { 列宽/列数变了,横向内容量随之变 }
  Invalidate;
end;

procedure TTyCustomGrid.SetHeader(AValue: TTyHeader);
begin
  FHeader.Assign(AValue);
end;

procedure TTyCustomGrid.SetRowCount(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FRowCount = AValue then Exit;
  FRowCount := AValue;
  InvalidateGridOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyCustomGrid.SetDefaultRowHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FDefaultRowHeight = AValue then Exit;
  FDefaultRowHeight := AValue;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyCustomGrid.SetFixedCols(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FFixedCols = AValue then Exit;
  FFixedCols := AValue;
  Invalidate;
end;

procedure TTyCustomGrid.SetFixedRows(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FFixedRows = AValue then Exit;
  FFixedRows := AValue;
  Invalidate;
end;

procedure TTyCustomGrid.SetIndicatorWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FIndicatorWidth = AValue then Exit;
  FIndicatorWidth := AValue;
  InvalidateColumnCache;   { 行头槽宽度进了每列的基准左缘 }
  Invalidate;
end;

procedure TTyCustomGrid.SetShowIndicator(AValue: Boolean);
begin
  if FShowIndicator = AValue then Exit;
  FShowIndicator := AValue;
  InvalidateColumnCache;
  Invalidate;
end;

function TTyCustomGrid.FrozenWidthPx: Integer;
var
  n, i, logical: Integer;
  c: TTyColumn;
begin
  logical := 0;
  if FShowIndicator then Inc(logical, FIndicatorWidth);

  { 固定列数可能被设得比实际列数还多(设计期先设 FixedCols 再加列很常见),
    按实际列数封顶,别越界求和。 }
  n := FFixedCols;
  if n > FHeader.Columns.Count then n := FHeader.Columns.Count;
  for i := 0 to n - 1 do
  begin
    c := TTyColumn(FHeader.Columns.Items[i]);
    if coVisible in c.Options then
      Inc(logical, c.Width);
  end;

  Result := ScaleI(logical);
end;

function TTyCustomGrid.FrozenHeightPx: Integer;
var
  i, px: Integer;
begin
  px := 0;
  if hoVisible in FHeader.Options then Inc(px, ScaleI(FHeader.Height));
  { 分组带也在上冻结带里 —— 漏了它固定行和正文都会往上顶,压住分组标题。 }
  Inc(px, GroupBandHeightPx);
  { 逐行累加真实高度(而非 行数×默认行高)—— 可变行高时固定行也可能各不相同。 }
  for i := 0 to FFixedRows - 1 do
    Inc(px, ScaleI(RowHeightOf(i)));
  Result := px;
end;

procedure TTyCustomGrid.SetShowGridLines(AValue: Boolean);
begin
  { 布尔别名:开 = 两轴都画,关 = 都不画。 }
  if AValue then SetGridLineStyle(glsBoth) else SetGridLineStyle(glsNone);
  Exit;
  Invalidate;
end;

function TTyCustomGrid.ViewportW: Integer;
begin
  Result := ClientWidth;
  if (FVScroll <> nil) and FVScroll.Visible then Dec(Result, FVScroll.Width);
  if Result < 0 then Result := 0;
end;

function TTyCustomGrid.ViewportH: Integer;
begin
  Result := ClientHeight;
  if (FHScroll <> nil) and FHScroll.Visible then Dec(Result, FHScroll.Height);
  { 汇总带钉在底部、不滚动 —— 从视口里扣掉,否则最后一行会钻到它底下。 }
  Dec(Result, FooterHeightPx);
  if Result < 0 then Result := 0;
end;

procedure TTyCustomGrid.VScrollChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  ScrollY := FVScroll.Position;   { 走收口点,拿到脏区重绘 }
end;

procedure TTyCustomGrid.HScrollChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  FScrollX := FHScroll.Position;
  Invalidate;
end;

procedure TTyCustomGrid.Resize;
begin
  inherited Resize;
  UpdateScrollBars;
end;

procedure TTyCustomGrid.SyncScrollBars;
begin
  if (FVScroll = nil) or (FHScroll = nil) then Exit;
  if FSyncingScroll then Exit;      { 正在由 UpdateScrollBars 推值,别自己撞自己 }
  FSyncingScroll := True;
  try
    { **落位,不缓动** —— 这里是"网格已经滚过去了,把结果同步给滑块"。
      走普通的 Position 赋值会触发缓动,滑块要慢半拍才追上内容。 }
    if FVScroll.Visible and not FVScroll.Dragging then
      FVScroll.SetPositionSnapped(FScrollY);
    if FHScroll.Visible and not FHScroll.Dragging then
      FHScroll.SetPositionSnapped(FScrollX);
  finally
    FSyncingScroll := False;
  end;
end;

procedure TTyCustomGrid.UpdateScrollBars;
var
  sb, vw, vh, pass, bodyH, bodyW, maxV, maxH: Integer;
  needV, needH: Boolean;
begin
  if csDestroying in ComponentState then Exit;
  if (FVScroll = nil) or (FHScroll = nil) then Exit;

  sb := ScaleI(TyScrollbarSize);
  needV := False;
  needH := False;

  { 自动列宽:让 AutoSizeIndex 那一列吸收剩余宽度。此前 ApplyAutoSize **零调用**
    —— hoAutoResize / AutoSizeIndex 已 published 却完全不生效。
    放在两趟收敛**之前**:列宽变了会影响横向内容量,进而影响横条是否出现。 }
  if (hoAutoResize in FHeader.Options) and (FHeader.AutoSizeIndex >= 0)
     and not FSyncingScroll then
    FHeader.Columns.ApplyAutoSize(UnscaleI(ClientWidth - FrozenWidthPx),
      FHeader.AutoSizeIndex);

  { 两趟收敛"互夺":一条轴出现滚动条会吃掉另一条轴的可用空间,可能反过来又逼出对方。 }
  for pass := 0 to 1 do
  begin
    vw := ClientWidth  - IfThen(needV, sb, 0);
    vh := ClientHeight - IfThen(needH, sb, 0);
    if vw < 0 then vw := 0;
    if vh < 0 then vh := 0;
    needV := ContentHeightPx > (vh - FrozenHeightPx);
    needH := ContentWidthPx  > vw;
  end;

  vw := ClientWidth  - IfThen(needV, sb, 0);
  vh := ClientHeight - IfThen(needH, sb, 0);
  if vw < 0 then vw := 0;
  if vh < 0 then vh := 0;

  bodyH := vh - FrozenHeightPx; if bodyH < 0 then bodyH := 0;
  bodyW := vw - FrozenWidthPx;  if bodyW < 0 then bodyW := 0;
  maxV := ContentHeightPx - bodyH;                if maxV < 0 then maxV := 0;
  maxH := (ContentWidthPx - FrozenWidthPx) - bodyW; if maxH < 0 then maxH := 0;

  if FScrollY > maxV then FScrollY := maxV;
  if FScrollX > maxH then FScrollX := maxH;

  FSyncingScroll := True;
  try
    if needV then
    begin
      FVScroll.Controller := Self.Controller;
      FVScroll.Width := sb;
      if not FVScroll.Dragging then
        FVScroll.SetBounds(ClientWidth - sb, 0, sb, vh);
      FVScroll.Min := 0;
      { Max = **最大位置**而非内容尺寸 —— 滑块按 PageSize/((Max-Min)+PageSize) 定大小,
        喂内容尺寸会让滑块偏小、底部永远留一截、拖到底还会弹回。与列表/树同一约定。 }
      FVScroll.Max := maxV;
      FVScroll.PageSize := bodyH;
      { 同样是镜像:落位。而且要避开用户正在拖的那一刻 —— 原先这里没判 Dragging,
        重算滚动范围时会把滑块从用户手里抢走。 }
      if not FVScroll.Dragging then FVScroll.SetPositionSnapped(FScrollY);
    end;
    FVScroll.Visible := needV;

    if needH then
    begin
      FHScroll.Controller := Self.Controller;
      FHScroll.Height := sb;
      if not FHScroll.Dragging then
        FHScroll.SetBounds(0, ClientHeight - sb, vw, sb);
      FHScroll.Min := 0;
      FHScroll.Max := maxH;
      FHScroll.PageSize := bodyW;
      if not FHScroll.Dragging then FHScroll.SetPositionSnapped(FScrollX);
    end;
    FHScroll.Visible := needH;
  finally
    FSyncingScroll := False;
  end;
end;

function TTyCustomGrid.ContentHeightPx: Integer;
begin
  { 走几何层,这样可变行高时自然取前缀和末项,不必在这里再算一遍。 }
  Result := TyGridContentHeight(GridMetrics);
end;

function TTyCustomGrid.ContentWidthPx: Integer;
var
  i, logical: Integer;
  c: TTyColumn;
begin
  logical := 0;
  if FShowIndicator then Inc(logical, FIndicatorWidth);
  for i := 0 to FHeader.Columns.Count - 1 do
  begin
    c := TTyColumn(FHeader.Columns.Items[i]);
    if coVisible in c.Options then Inc(logical, c.Width);
  end;
  Result := ScaleI(logical);
end;

function TTyCustomGrid.MaxScrollY: Integer;
var
  body: Integer;
begin
  body := ViewportH - FrozenHeightPx;
  Result := ContentHeightPx - body;
  if Result < 0 then Result := 0;
end;

function TTyCustomGrid.MaxScrollX: Integer;
var
  body: Integer;
begin
  { 正文区可用宽 = 客户区 - 冻结带;内容里同样要扣掉冻结部分(它不参与滚动)。 }
  body := ViewportW - FrozenWidthPx;
  Result := (ContentWidthPx - FrozenWidthPx) - body;
  if Result < 0 then Result := 0;
end;

procedure TTyCustomGrid.ScrollIntoView(ACol, ARow: Integer);
var
  M: TTyGridMetrics;
  body, r, cell: TRect;
begin
  M := GridMetrics;
  body := TyGridPaneRect(M, gpBody);

  { 纵向:用行矩形判断,最小移动量把它拉进正文区。 }
  r := TyGridRowRect(DataToDisplay(ARow), M);
  if r.Top < body.Top then
    SetScrollY(FScrollY - (body.Top - r.Top))
  else if r.Bottom > body.Bottom then
    SetScrollY(FScrollY + (r.Bottom - body.Bottom));

  { 横向:固定列本来就在冻结带里,不需要也不能滚。 }
  if ACol >= FFixedCols then
  begin
    cell := CellRect(ACol, ARow);
    if cell.Left < body.Left then
      SetScrollX(FScrollX - (body.Left - cell.Left))
    else if cell.Right > body.Right then
      SetScrollX(FScrollX + (cell.Right - body.Right));
  end;
end;

function TTyCustomGrid.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  step: Integer;
begin
  { 一格滚轮走三行 —— 与列表/树保持一致的手感。 }
  step := 3 * ScaleI(FDefaultRowHeight);
  if WheelDelta > 0 then SetScrollY(FScrollY - step)
  else SetScrollY(FScrollY + step);
  Result := True;
end;

procedure TTyCustomGrid.SetShowFooter(AValue: Boolean);
begin
  if FShowFooter = AValue then Exit;
  FShowFooter := AValue;
  UpdateScrollBars;
  Invalidate;
end;

function TTyCustomGrid.CellStates(ACol, ARow: Integer): TTyStateSet;
begin
  Result := [];
  if (ACol = FHoverCol) and (ARow = FHoverRow) then Include(Result, tysHover);
end;

procedure TTyCustomGrid.ResetCellStyleCache;
begin
  SetLength(FCellStyleStates, 0);
  SetLength(FCellStyleCache, 0);
  SetLength(FCellBaseCache, 0);
end;

function TTyCustomGrid.CellStyleSlot(ACol, ARow: Integer): Integer;
var
  st: TTyStateSet;
  n: Integer;
  i: Integer;
  sty: TTyStyleSet;
begin
  st := CellStates(ACol, ARow);
  { 线性找:状态组合的种类是个位数(空集/hover/选中/两者),
    线性扫比建哈希快,也不产生分配。 }
  for i := 0 to High(FCellStyleStates) do
    if FCellStyleStates[i] = st then Exit(i);

  sty := ActiveController.Model.ResolveStyle('TyGridCell', StyleClass, st);
  n := Length(FCellStyleStates);
  SetLength(FCellStyleStates, n + 1);
  SetLength(FCellStyleCache, n + 1);
  SetLength(FCellBaseCache, n + 1);
  FCellStyleStates[n] := st;
  FCellStyleCache[n] := sty;

  { **每个状态组合只算一次**:字号解析(可能要查主题变量)就在这里落地。 }
  FCellBaseCache[n] := Default(TTyGridCellAppearance);
  FCellBaseCache[n].HasBackground :=
    (tpBackground in sty.Present) and (sty.Background.Kind <> tfkNone);
  FCellBaseCache[n].Background := sty.Background;
  FCellBaseCache[n].HasTextColor := tpTextColor in sty.Present;
  FCellBaseCache[n].TextColor := sty.TextColor;
  FCellBaseCache[n].FontName := sty.FontName;
  FCellBaseCache[n].FontSize := ResolveFontSize(sty);
  FCellBaseCache[n].FontWeight := sty.FontWeight;
  Result := n;
end;

function TTyCustomGrid.ResolveCellStyle(ACol, ARow: Integer): TTyStyleSet;
var
  slot: Integer;
begin
  { **必须先把槽位算出来再索引数组。**
    写成 FCellStyleCache[CellStyleSlot(...)] 是有坑的:编译器可以先取数组的
    基址、再调用那个函数,而函数内部的 SetLength 会重新分配数组 ——
    先取到的基址就成了悬垂指针。表现是随机的内存损坏(我这次看到的是
    后续测试大面积"创建 win32 控件失败"),而不是干脆的越界报错。 }
  slot := CellStyleSlot(ACol, ARow);
  Result := FCellStyleCache[slot];
end;

procedure TTyCustomGrid.UpdateHoverCursor(X, Y: Integer);
var
  want: TCursor;
  hdrH: Integer;
begin
  want := crDefault;

  hdrH := 0;
  if hoVisible in FHeader.Options then
    hdrH := ScaleI(FHeader.Height) + GroupBandHeightPx;

  { 列分隔线:只在列头带里认(与 MouseDown 同一条判定)。 }
  if (hoColumnResize in FHeader.Options) and (hdrH > 0) and (Y < hdrH)
     and (Y >= GroupBandHeightPx) and (DividerAtX(X) >= 0) then
    want := crHSplit
  { 行分隔线:只在行头槽里认(同样与 MouseDown 同源)。 }
  else if (Y >= hdrH) and (RowDividerAtY(X, Y) >= 0) then
    want := crVSplit;

  if Cursor <> want then Cursor := want;
end;

procedure TTyCustomGrid.UpdateHoverCell(X, Y: Integer);
var
  hit: TTyGridHit;
  c, r: Integer;
begin
  hit := CellAt(X, Y);
  if hit.Part = ghpCell then
  begin
    c := hit.Col;
    r := hit.Row;
  end
  else
  begin
    c := -1;
    r := -1;
  end;
  if (c = FHoverCol) and (r = FHoverRow) then Exit;   { 同一格:不重绘 }
  FHoverCol := c;
  FHoverRow := r;
  Invalidate;
end;

procedure TTyCustomGrid.CMMouseLeave(var Msg: TLMessage);
begin
  inherited;
  if (FHoverCol >= 0) or (FHoverRow >= 0) then
  begin
    FHoverCol := -1;
    FHoverRow := -1;
    Invalidate;
  end;
end;

procedure TTyCustomGrid.ClearTextCache;
begin
  if FTextCache <> nil then FTextCache.Clear;
end;

procedure TTyCustomGrid.InvalidateSurface;
begin
  FSurfaceFresh := False;
  FSurfacePendingDy := 0;
end;

{ **默认作废**:任何 Invalidate 都让持久表面失效。
  只有 ScrollVerticallyBy 会在调完 Invalidate 之后把它重新点亮 ——
  这个方向的默认值让"忘了失效"变成不可能,代价只是某些本可复用的帧退回整幅重画。 }
{ 双击。**先看落在哪** —— 从前 TTyStringGrid.DblClick 无条件进编辑,
  于是在行号槽/列头/末行以下空白处双击,光标格都会莫名开始编辑。 }
procedure TTyCustomGrid.DblClick;
begin
  inherited DblClick;
  if (FLastDownHit.Part = ghpCell) and Assigned(FOnDblClickCell) then
    FOnDblClickCell(Self, FLastDownHit.Col, FLastDownHit.Row);
end;

procedure TTyCustomGrid.Invalidate;
begin
  FSurfaceFresh := False;
  FSurfacePendingDy := 0;
  inherited Invalidate;
end;

{ 逐扫描行 memmove。比"整幅拷到临时位图再拷回来"省一半带宽,也不必额外分配。
  方向要选对:上移时从上往下搬,下移时从下往上搬 —— 反了会自己覆盖自己。 }
function TTyCustomGrid.MaxRowSpanHint: Integer;
begin
  Result := 1;
end;

procedure TTyCustomGrid.ShiftSurfaceRows(ATop, ABottom, ADy: Integer);
var
  y, n: Integer;
begin
  if (FSurface = nil) or (ADy = 0) then Exit;
  if ATop < 0 then ATop := 0;
  if ABottom > FSurface.Height then ABottom := FSurface.Height;
  if ABottom - ATop <= Abs(ADy) then Exit;      { 没有可复用的部分 }
  n := FSurface.Width * SizeOf(TBGRAPixel);

  if ADy > 0 then
    for y := ATop to ABottom - 1 - ADy do
      Move(FSurface.ScanLine[y + ADy]^, FSurface.ScanLine[y]^, n)
  else
    for y := ABottom - 1 downto ATop - ADy do
      Move(FSurface.ScanLine[y + ADy]^, FSurface.ScanLine[y]^, n);

  FSurface.InvalidateBitmap;
end;

procedure TTyCustomGrid.ScrollVerticallyBy(ADy: Integer);
begin
  ScrollY := FScrollY + ADy;
end;

procedure TTyCustomGrid.DrawCellText(P: TTyPainter; const ARect: TRect;
  const AText: string; const AFontName: string; AFontSize, AFontWeight: Integer;
  AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout;
  AWordWrap: Boolean);
var
  w, h, idx, sz, weight: Integer;
  key, fname, txt: string;
  bmp: TBGRABitmap;
  st: TTextStyle;
  tsz: TSize;
begin
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) or (AText = '') then Exit;

  fname := AFontName;
  sz := AFontSize;
  weight := AFontWeight;

  { 键 = 这块文字的**全部外观输入**。任何一项变了都是新条目,
    所以换主题/改列宽/切深色都不需要显式失效 —— 旧条目自然不再被命中。 }
  key := AText + #1 + fname + #1 + IntToStr(sz) + #1 + IntToStr(weight) + #1 +
         IntToStr(AColor) + #1 + IntToStr(w) + 'x' + IntToStr(h) + #1 +
         IntToStr(Ord(AHAlign)) + #1 + IntToStr(Ord(AVAlign)) + #1 +
         IntToStr(Ord(AWordWrap)) + #1 + IntToStr(P.PPI);

  idx := FTextCache.IndexOf(key);
  if idx >= 0 then
    bmp := TBGRABitmap(FTextCache.Objects[idx])
  else
  begin
    { 上限只是防失控(滚动久了键会一直增长);视口内的格数远小于它。
      整表清空比 LRU 简单,代价是清空后那一帧要重画 —— 可以接受。 }
    if FTextCache.Count > 8192 then FTextCache.Clear;

    bmp := TBGRABitmap.Create(w, h);      { 全透明 }
    TyConfigureTextFont(bmp, fname, sz, weight, P.PPI);

    txt := AText;
    if not AWordWrap then
    begin
      { 省略号截断:与 TTyPainter.DrawText 用同一套规则,免得两条路径排出来的字不一样。
        换行时**不截断** —— 放不下就往下一行走,这正是换行的意义。 }
      tsz := bmp.TextSize(txt);
      while (Length(txt) > 1) and (tsz.cx > w) do
      begin
        Delete(txt, Length(txt), 1);
        tsz := bmp.TextSize(txt + '...');
      end;
      if txt <> AText then txt := txt + '...';
    end;

    st := Default(TTextStyle);
    st.Alignment := AHAlign;
    st.Layout := AVAlign;
    st.SingleLine := not AWordWrap;
    st.Wordbreak := AWordWrap;
    st.Clipping := True;
    bmp.TextRect(Rect(0, 0, w, h), 0, 0, txt, st, TyColorToBGRA(AColor));

    { 排序表 + dupIgnore:键重复时 AddObject **不会收下这个对象**,
      直接走人就把位图漏了(上面刚 IndexOf 过,理论上碰不到;但漏内存的代价
      是几百 MB,值得这三行)。 }
    idx := FTextCache.AddObject(key, bmp);
    if (idx < 0) or (FTextCache.Objects[idx] <> bmp) then
    begin
      bmp.Free;
      if idx < 0 then Exit;
      bmp := TBGRABitmap(FTextCache.Objects[idx]);
    end;
  end;

  { PutImage 尊重 ClipRect —— 半掩的单元格照样被裁掉一截。 }
  P.Bitmap.PutImage(ARect.Left, ARect.Top, bmp, dmDrawWithTransparency);
end;

function TTyGridEditLink.HandleKey(var AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := False;      { 默认什么都不吃,网格照常处理导航键 }
end;

function TTyCustomGrid.IsActiveCell(ACol, ARow: Integer): Boolean;
begin
  Result := False;
end;

function TTyCustomGrid.FAttrs2Find(ACol, ARow: Integer): TTyGridCellAttr;
begin
  Result := nil;
end;

function TTyCustomGrid.CanClickCell(ACol, ARow: Integer): Boolean;
begin
  Result := True;
  if Assigned(FOnCanClickCell) then FOnCanClickCell(Self, ACol, ARow, Result);
end;

procedure TTyCustomGrid.AutoFitColumnWidth(ACol: Integer);
begin
  { 基类不知道数据从哪来。 }
end;

procedure TTyCustomGrid.SetRatingByPoint(ACol, ARow, X, Y: Integer);
begin
  { 基类没有数据存储;TTyStringGrid 改写。 }
end;

procedure TTyCustomGrid.SetPressedButton(ACol, ARow: Integer);
begin
  FPressedBtnCol := ACol;
  FPressedBtnRow := ARow;
end;

procedure TTyCustomGrid.GetPressedButton(out ACol, ARow: Integer);
begin
  ACol := FPressedBtnCol;
  ARow := FPressedBtnRow;
end;

function TTyCustomGrid.CellDisplayOf(ACol, ARow: Integer): TTyGridCellDisplay;
begin
  Result := gcdText;    { 基类不知道数据从哪来;TTyStringGrid 改写去问宿主 }
end;

function TTyCustomGrid.CellButtonRect(ACol, ARow: Integer): TRect;
var
  cell: TRect;
  pad: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if CellDisplayOf(ACol, ARow) <> gcdButton then Exit;
  cell := CellRect(ACol, ARow);
  if IsRectEmpty(cell) then Exit;
  pad := ScaleI(2);
  Result := Rect(cell.Left + pad, cell.Top + pad,
                 cell.Right - pad, cell.Bottom - pad);
  if (Result.Right <= Result.Left) or (Result.Bottom <= Result.Top) then
    Result := Rect(0, 0, 0, 0);
end;

procedure TTyCustomGrid.RenderButtonCell(P: TTyPainter; ACol, ARow: Integer;
  const AText: string; const AFrame: TTyStyleSet);
var
  r, vis: TRect;
  st: TTyStateSet;
  bS: TTyStyleSet;
  ink: TTyColor;
begin
  r := CellButtonRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  vis := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(vis) then Exit;

  { 状态**只由这个按钮自己**决定 —— 掺进网格的 CurrentStates,鼠标一按下
    满屏按钮会集体变成按下态(勾选框那次就是这么栽的)。 }
  st := [];
  if (ACol = FPressedBtnCol) and (ARow = FPressedBtnRow) then Include(st, tysActive)
  else if (ACol = FHoverCol) and (ARow = FHoverRow) then Include(st, tysHover);

  bS := ActiveController.Model.ResolveStyle('TyGridButton', StyleClass, st);
  if tpBackground in bS.Present then
    P.FillBackground(r, bS.Background, TyEffectiveCorners(bS));
  if TyBorderVisible(bS) then
    P.StrokeBorder(r, TyEffectiveCorners(bS), bS.BorderWidth, bS.BorderColor);

  if tpTextColor in bS.Present then ink := bS.TextColor else ink := AFrame.TextColor;
  DrawCellText(P, r, AText, bS.FontName, ResolveFontSize(bS), bS.FontWeight,
    ink, taCenter, tlCenter);
end;

procedure TTyCustomGrid.InvalidateRowMetrics;
begin
  { 基类全等高,没有可失效的缓存。 }
end;

function TTyCustomGrid.HasExplicitRowHeights: Boolean;
begin
  Result := FRowHeights.Count > 0;
end;

procedure TTyCustomGrid.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  ClearTextCache;
  Invalidate;
end;

procedure TTyCustomGrid.HideColumn(ACol: Integer);
var c: TTyColumn;
begin
  if (ACol < 0) or (ACol >= FHeader.Columns.Count) then Exit;
  c := TTyColumn(FHeader.Columns.Items[ACol]);
  if not (coVisible in c.Options) then Exit;
  c.Options := c.Options - [coVisible];
end;

procedure TTyCustomGrid.ShowColumn(ACol: Integer);
var c: TTyColumn;
begin
  if (ACol < 0) or (ACol >= FHeader.Columns.Count) then Exit;
  c := TTyColumn(FHeader.Columns.Items[ACol]);
  if coVisible in c.Options then Exit;
  c.Options := c.Options + [coVisible];
end;

function TTyCustomGrid.IsHiddenColumn(ACol: Integer): Boolean;
begin
  Result := False;
  if (ACol < 0) or (ACol >= FHeader.Columns.Count) then Exit;
  Result := not (coVisible in TTyColumn(FHeader.Columns.Items[ACol]).Options);
end;

function TTyCustomGrid.NextVisibleCol(AFrom, AStep: Integer): Integer;
var
  c: Integer;
begin
  Result := AFrom;
  if AStep = 0 then Exit;
  c := AFrom;
  while (c >= 0) and (c < FHeader.Columns.Count) do
  begin
    if not IsHiddenColumn(c) then Exit(c);
    Inc(c, AStep);
  end;
end;

function TTyCustomGrid.FirstVisibleCol: Integer;
begin
  Result := NextVisibleCol(0, 1);
end;

function TTyCustomGrid.LastVisibleCol: Integer;
begin
  Result := NextVisibleCol(FHeader.Columns.Count - 1, -1);
end;

function TTyCustomGrid.GetRowHeights(ARow: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  i := FRowHeights.IndexOf(IntToStr(ARow));
  if i >= 0 then Result := PtrInt(FRowHeights.Objects[i]);
end;

procedure TTyCustomGrid.SetRowHeights(ARow, AValue: Integer);
var
  i: Integer;
  k: string;
begin
  if ARow < 0 then Exit;
  { 上下限在**存储入口**钳一次,而不是在每个调用方各钳一次 ——
    拖拽、AutoFitRow、宿主直接赋值走的都是这里。 }
  if AValue > 0 then
  begin
    if (FMinRowHeight > 0) and (AValue < FMinRowHeight) then AValue := FMinRowHeight;
    if (FMaxRowHeight > 0) and (AValue > FMaxRowHeight) then AValue := FMaxRowHeight;
  end;
  k := IntToStr(ARow);
  i := FRowHeights.IndexOf(k);
  if AValue <= 0 then
  begin
    { <= 0 = 清掉这一条,回到回调/默认值。别存 0 —— 那会变成"行高 0"。 }
    if i >= 0 then FRowHeights.Delete(i);
  end
  else if i >= 0 then
    FRowHeights.Objects[i] := TObject(PtrInt(AValue))
  else
    FRowHeights.AddObject(k, TObject(PtrInt(AValue)));
  InvalidateRowMetrics;
  UpdateScrollBars;
  Invalidate;
end;

function TTyCustomGrid.RowDividerAtY(AX, AY: Integer): Integer;
var
  slot: Integer;   { 绘制槽位 }
  M: TTyGridMetrics;
  first, last, pos: Integer;
  r: TRect;
  tol: Integer;
begin
  Result := -1;
  { 只在行头槽里认分隔线 —— 在单元格上认的话会和框选拖拽抢手势。 }
  if not FShowIndicator then Exit;
  if (AX < 0) or (AX >= ScaleI(FIndicatorWidth)) then Exit;

  M := GridMetrics;
  { 走绘制槽位:顶部固定行 + 正文窗口(固定行不在正文窗口里)。 }
  if not TyGridDrawSlots(M, first, last) then Exit;
  tol := ScaleI(3);
  for slot := first to last do
  begin
    pos := TyGridRowAtSlot(slot, M);
    if pos < 0 then Continue;
    r := TyGridRowRect(pos, M);
    if Abs(AY - r.Bottom) <= tol then Exit(pos);
  end;
end;

procedure TTyCustomGrid.HeaderGroupsChanged(Sender: TObject);
begin
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyCustomGrid.SetHeaderGroups(AValue: TTyGridHeaderGroups);
begin
  FHeaderGroups.Assign(AValue);
end;

procedure TTyCustomGrid.SetGroupHeaderHeight(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FGroupHeaderHeight = AValue then Exit;
  FGroupHeaderHeight := AValue;
  UpdateScrollBars;
  Invalidate;
end;

{ 分组带的高度(设备像素)。没有分组时为 0 —— 于是几何完全退回单级表头。 }
function TTyCustomGrid.GroupBandHeightPx: Integer;
begin
  if (FHeaderGroups.Count = 0) or not (hoVisible in FHeader.Options) then Exit(0);
  Result := ScaleI(FGroupHeaderHeight);
end;

function TTyCustomGrid.GetGridLines: Boolean;
begin
  Result := FGridLineStyle <> glsNone;
end;

procedure TTyCustomGrid.SetGridLineStyle(AValue: TTyGridLineStyle);
begin
  if FGridLineStyle = AValue then Exit;
  FGridLineStyle := AValue;
  Invalidate;
end;

procedure TTyCustomGrid.SetAlternateRows(AValue: Boolean);
begin
  if FAlternateRows = AValue then Exit;
  FAlternateRows := AValue;
  Invalidate;
end;

procedure TTyCustomGrid.SetShowRowNumbers(AValue: Boolean);
begin
  if FShowRowNumbers = AValue then Exit;
  FShowRowNumbers := AValue;
  Invalidate;
end;

procedure TTyCustomGrid.RenderRowNumbers(P: TTyPainter; const M: TTyGridMetrics;
  AHeaderH, AIndicatorW: Integer);
var
  slot: Integer;   { 绘制槽位 }
  first, last, pos: Integer;
  r: TRect;
  { 别取名 iS —— Pascal 大小写不敏感,它就是保留字 is。
    (和当初 col↔Col、cellS↔Cells 同一类坑。) }
  indS: TTyStyleSet;
  ink: TTyColor;
  oldClip: TRect;
begin
  if not FShowRowNumbers then Exit;
  if AIndicatorW <= 0 then Exit;
  { 走绘制槽位:顶部固定行 + 正文窗口(固定行不在正文窗口里)。 }
  if not TyGridDrawSlots(M, first, last) then Exit;

  { 复用行头槽自己的 typeKey 取墨色与字体 —— 不硬编码任何视觉值,
    也不借别的控件的键。 }
  indS := ActiveController.Model.ResolveStyle('TyGridIndicator', StyleClass, []);
  if tpTextColor in indS.Present then ink := indS.TextColor
  else ink := CurrentStyle.TextColor;

  { 行号按**显示序**给:排序/筛选之后,屏幕第一行仍然是 1。
    (给数据行号的话,排一次序行号就乱跳,那不是行号该有的样子。) }
  { **必须裁到正文窗格**。只跳过表头是不够的:滚到冻结带(表头 + 固定行)
    底下的那一行,它的行号会画到固定行的槽位上去 —— 单元格内容靠
    CellVisibleRect 与窗格求交挡住了,行号这条路径当初漏了这一步。 }
  oldClip := P.Bitmap.ClipRect;
  P.Bitmap.ClipRect := Rect(0, M.FrozenTop, AIndicatorW, M.ClientH);
  try
  for slot := first to last do
  begin
    pos := TyGridRowAtSlot(slot, M);
    if pos < 0 then Continue;
    r := TyGridRowRect(pos, M);
    if r.Bottom <= M.FrozenTop then Continue;
    DrawCellText(P, Rect(0, r.Top, AIndicatorW - ScaleI(4), r.Bottom),
      IntToStr(pos + 1), indS.FontName, ResolveFontSize(indS), indS.FontWeight,
      ink, taRightJustify, tlCenter);
  end;
  finally
    P.Bitmap.ClipRect := oldClip;
  end;
end;

procedure TTyCustomGrid.DoGetCellStyle(ACol, ARow: Integer;
  var AAppearance: TTyGridCellAppearance);
var
  before: TTyFill;
begin
  if not Assigned(FOnGetCellStyle) then Exit;
  before := AAppearance.Background;
  FOnGetCellStyle(Self, ACol, ARow, AAppearance.Background, AAppearance.TextColor,
    AAppearance.FontName, AAppearance.FontSize, AAppearance.FontWeight,
    AAppearance.HAlign, AAppearance.VAlign);
  { 钩子把底色从 none 改成实色 = 它要画背景。反过来也成立。 }
  AAppearance.HasBackground := AAppearance.Background.Kind <> tfkNone;
  { 钩子**动过**底色才算"用户显式指定"(条件着色是宿主对这一格的明确判断,
    和逐格色一样不该被选区抹掉)。没动过就别抢:斑马纹铺的底色不是显式指定,
    比较前后值才分得清 —— 只看 HasBackground 会把斑马纹一并算进去。 }
  if AAppearance.HasBackground
    and ((before.Kind <> AAppearance.Background.Kind)
         or (before.Color <> AAppearance.Background.Color)) then
    AAppearance.HasExplicitBackground := True;
end;

function TTyCustomGrid.CellAppearance(ACol, ARow, ADisplayPos: Integer;
  const AFrame: TTyStyleSet): TTyGridCellAppearance;
var
  altS, actS: TTyStyleSet;
  col: TTyColumn;
  attr: TTyGridCellAttr;
  slot: Integer;
begin
  { 基础外观按状态组合记忆化 —— 逐格路径上不再做样式解析,也不再查主题变量。 }
  slot := CellStyleSlot(ACol, ARow);   { 先算槽位,再索引 —— 见 ResolveCellStyle 的说明 }
  Result := FCellBaseCache[slot];
  if not Result.HasTextColor then Result.TextColor := AFrame.TextColor;
  Result.VAlign := tlCenter;
  Result.WordWrap := FWordWrap;
  if Assigned(FOnGetCellWordWrap) then
    FOnGetCellWordWrap(Self, ACol, ARow, Result.WordWrap);

  Result.HAlign := taLeftJustify;
  if (ACol >= 0) and (ACol < FHeader.Columns.Count) then
  begin
    col := TTyColumn(FHeader.Columns.Items[ACol]);
    Result.HAlign := col.Alignment;
  end;

  { 斑马纹按**显示行号**取奇偶。用自己的 typeKey 而不是 `TyGridCell:alternate`:
    加一个伪类要动共享的 TTyState 枚举与 CSS 解析器,会波及每一个控件;
    而库里网格的各个部件(TyGridCheckBox / TyGridProgress / TyGridGroupRow…)
    本来就各有各的键,这条更一致、也够得着外观主题层。 }
  if FAlternateRows and Odd(ADisplayPos) then
  begin
    altS := ActiveController.Model.ResolveStyle('TyGridCellAlt', StyleClass, []);
    if (tpBackground in altS.Present) and (altS.Background.Kind <> tfkNone) then
    begin
      Result.HasBackground := True;
      Result.Background := altS.Background;
    end;
    if tpTextColor in altS.Present then Result.TextColor := altS.TextColor;
  end;

  { 逐格**持久**外观(Colors[c,r] / TextColors[c,r] / RowColor[r] 落在属性存储里)。
    优先级:主题 → 斑马纹 → 行色 → 逐格色 → 宿主钩子。
    越靠后越具体,所以越晚覆盖。 }
  attr := FAttrs2Find(ACol, ARow);
  if attr <> nil then
  begin
    if attr.HasBackground then
    begin
      Result.HasBackground := True;
      Result.Background := Default(TTyFill);
      Result.Background.Kind := tfkSolid;
      Result.Background.Color := attr.Background;
      Result.HasExplicitBackground := True;
    end;
    if attr.HasTextColor then Result.TextColor := attr.TextColor;
    if attr.HasAlignment then Result.HAlign := attr.Alignment;
  end;

  { **焦点格**要和选区区分开:gsmRow 模式下整行都是选中底色,不区分的话
    根本看不出光标在哪一格。用自己的 typeKey,主题没定义就什么都不做。 }
  if IsActiveCell(ACol, ARow) then
  begin
    actS := ActiveController.Model.ResolveStyle('TyGridActiveCell', StyleClass, []);
    { 用户给这格指定了底色时**不铺焦点底色** —— 否则光标停在哪一格,
      哪一格的颜色就看不见了(而光标恰恰总停在刚被上色的那一格上)。
      焦点仍靠文字色与选区层区分得出来。 }
    if (not Result.HasExplicitBackground)
      and (tpBackground in actS.Present) and (actS.Background.Kind <> tfkNone) then
    begin
      Result.HasBackground := True;
      Result.Background := actS.Background;
    end;
    if tpTextColor in actS.Present then Result.TextColor := actS.TextColor;
  end;

  { 宿主钩子最后说了算(它自己判断动没动过底色,见 DoGetCellStyle)。 }
  DoGetCellStyle(ACol, ARow, Result);
end;

function TTyCustomGrid.GridLineWidthPx: Integer;
begin
  if FGridLineStyle = glsNone then Exit(0);
  Result := ScaleI(FGridLineWidth);
  if Result < 1 then Result := 1;
end;

procedure TTyCustomGrid.SetGridLineWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FGridLineWidth = AValue then Exit;
  FGridLineWidth := AValue;
  Invalidate;
end;

procedure TTyCustomGrid.SetImages(AValue: TTyVirtualImageList);
begin
  if FImages = AValue then Exit;
  FImages := AValue;
  Invalidate;
end;

procedure TTyCustomGrid.SetFooterHeight(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FFooterHeight = AValue then Exit;
  FFooterHeight := AValue;
  UpdateScrollBars;
  Invalidate;
end;

function TTyCustomGrid.FooterHeightPx: Integer;
begin
  if FShowFooter then Result := ScaleI(FFooterHeight) else Result := 0;
end;

procedure TTyCustomGrid.SetScrollX(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue > MaxScrollX then AValue := MaxScrollX;
  if FScrollX = AValue then Exit;
  FScrollX := AValue;
  SyncScrollBars;
  Invalidate;
end;

{ **所有纵向滚动的唯一入口** —— 滚动条、滚轮、键盘导航、EnsureVisible 都落到这里。
  从前 VScrollChange 直接写 FScrollY,于是脏区重绘那条路在实机上一次都不会触发:
  画面完全正确,只是白做了。 }
procedure TTyCustomGrid.SetScrollY(AValue: Integer);
var
  dy: Integer;
begin
  if AValue < 0 then AValue := 0;
  if AValue > MaxScrollY then AValue := MaxScrollY;
  if FScrollY = AValue then Exit;
  dy := AValue - FScrollY;
  FScrollY := AValue;
  SyncScrollBars;

  { 纯滚动是**唯一**不作废表面的改动:上一帧的像素只是位置变了。
    所以这里刻意绕过 Invalidate 覆盖(它会把新鲜度熄掉),只累加位移量。
    累加而不是赋值 —— 一帧里可能滚不止一次。 }
  Inc(FSurfacePendingDy, dy);
  inherited Invalidate;
end;

procedure TTyCustomGrid.InvalidateColumnCache;
begin
  FColCacheValid := False;
end;

procedure TTyCustomGrid.BuildColumnCache;
var
  i, n, logical: Integer;
  c: TTyColumn;
begin
  n := FHeader.Columns.Count;
  SetLength(FColBasePx, n);
  SetLength(FColWidthPx, n);

  { 行头槽之后,累加本列之前所有可见列的宽度。
    这里刻意按索引顺序累加而不用 TTyColumn.Left —— Left 是按**显示位置**算的,
    拖动重排之后两者会分叉;列冻结与否取决于索引,所以此处必须按索引。 }
  logical := 0;
  if FShowIndicator then Inc(logical, FIndicatorWidth);
  for i := 0 to n - 1 do
  begin
    c := TTyColumn(FHeader.Columns.Items[i]);
    FColBasePx[i] := ScaleI(logical);
    { **隐藏列宽度记 0**。这是整条隐藏链路的收口点:
      CellRect 本来就有 `w <= 0 then Exit` 的空矩形出口,于是渲染那几个
      没有 coVisible 守卫的循环(选区底色、勾选框/进度条/评分/色块)
      会自动变对 —— 不必去每个循环里补守卫,那样迟早漏一个。
      从前这里记的是整宽,于是隐藏列拿到一个**压在下一个可见列位置上**的矩形。 }
    if coVisible in c.Options then
    begin
      FColWidthPx[i] := ScaleI(c.Width);
      Inc(logical, c.Width);
    end
    else
      FColWidthPx[i] := 0;
  end;
  FColCacheValid := True;
end;

function TTyCustomGrid.ColumnLeftPx(ACol: Integer): Integer;
begin
  Result := 0;
  if (ACol < 0) or (ACol >= FHeader.Columns.Count) then Exit;
  if not FColCacheValid then BuildColumnCache;
  if ACol >= Length(FColBasePx) then Exit;

  Result := FColBasePx[ACol];
  { 固定列钉在冻结带里不随横向滚动;正文列才平移 —— 这正是"冻结"的全部含义。
    滚动量在**读取时**才减,所以横向滚动不必让缓存失效。 }
  if ACol >= FFixedCols then
    Dec(Result, FScrollX);
end;

function TTyCustomGrid.ColumnWidthPx(ACol: Integer): Integer;
begin
  Result := 0;
  if (ACol < 0) or (ACol >= FHeader.Columns.Count) then Exit;
  if not FColCacheValid then BuildColumnCache;
  if ACol >= Length(FColWidthPx) then Exit;
  Result := FColWidthPx[ACol];
end;

function TTyCustomGrid.ColumnAtX(AX: Integer): Integer;
var
  i, l, w: Integer;
begin
  Result := -1;
  { 取逆:逐列用 ColumnLeftPx/ColumnWidthPx 判定,而不是另写一套累加。
    列数通常只有几十,线性扫足够;要紧的是它与绘制用的是同一个出处。

    倒序扫:固定列画在正文列**之上**(冻结带会盖住滚过来的正文列),
    所以重叠处必须让固定列赢 —— 与绘制顺序保持一致。 }
  for i := FHeader.Columns.Count - 1 downto 0 do
  begin
    if not (coVisible in TTyColumn(FHeader.Columns.Items[i]).Options) then Continue;
    l := ColumnLeftPx(i);
    w := ColumnWidthPx(i);
    if (w > 0) and (AX >= l) and (AX < l + w) then
    begin
      if (i >= FFixedCols) and (AX < FrozenWidthPx) then Continue;  { 被冻结带盖住 }
      Result := i;
      Exit;
    end;
  end;
end;

function TTyCustomGrid.CellRect(ACol, ARow: Integer): TRect;
var
  rowR: TRect;
  l, w: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ACol < 0) or (ACol >= FHeader.Columns.Count) then Exit;
  if (ARow < 0) or (ARow >= FRowCount) then Exit;

  { 纵轴交给纯几何层(按**显示序**),横轴走列轴唯一出处 —— 两边都不另算。 }
  rowR := TyGridRowRect(DataToDisplay(ARow), GridMetrics);
  l := ColumnLeftPx(ACol);
  w := ColumnWidthPx(ACol);
  if w <= 0 then Exit;

  Result := Rect(l, rowR.Top, l + w, rowR.Bottom);
end;

function TTyCustomGrid.DisplayToData(APos: Integer): Integer;
begin
  Result := APos;      { 未排序:显示序就是数据行 }
end;

function TTyCustomGrid.DataToDisplay(ARow: Integer): Integer;
begin
  Result := ARow;
end;

procedure TTyCustomGrid.InvalidateGridOrder;
begin
  { 基类没有间接层,什么都不用做。 }
end;

function TTyCustomGrid.DisplayRowCount: Integer;
begin
  Result := FRowCount;
end;

procedure TTyCustomGrid.MapToBaseCell(var ACol, ARow: Integer);
begin
  { 基类没有合并。 }
end;

function TTyCustomGrid.CellPane(ACol, ARow: Integer): TTyGridPane;
begin
  { 行也要分窗格,不只是列。固定行的矩形钉在上冻结带里,而正文窗格从冻结带
    **之下**才开始 —— 把它们一律算作正文窗格的话,可见矩形恒为空,
    于是固定行连一个像素都画不出来(占着高度的空白带就是这么来的)。 }
  if ARow < FFixedRows then
  begin
    if ACol < FFixedCols then Result := gpTopLeft else Result := gpTop;
    Exit;
  end;
  if ACol < FFixedCols then Result := gpLeft else Result := gpBody;
end;

function TTyCustomGrid.CellVisibleRect(ACol, ARow: Integer): TRect;
var
  cell, pane: TRect;
begin
  cell := CellRect(ACol, ARow);
  if IsRectEmpty(cell) then
  begin
    Result := Rect(0, 0, 0, 0);
    Exit;
  end;
  pane := TyGridPaneRect(GridMetrics, CellPane(ACol, ARow));
  if not IntersectRect(Result, cell, pane) then
    Result := Rect(0, 0, 0, 0);
end;

function TTyCustomGrid.CellAt(AX, AY: Integer): TTyGridHit;
var
  M: TTyGridMetrics;
begin
  Result.Part := ghpNowhere;
  Result.Col := -1;
  Result.Row := -1;

  M := GridMetrics;
  if (AX < 0) or (AY < 0) or (AX >= M.ClientW) or (AY >= M.ClientH) then Exit;

  { 列头带优先:它横跨整幅宽度,盖在行头槽之上。 }
  { 表头整体(分组带 + 列头带)。**排序/筛选按钮只在叶子级**,所以落在分组带里
    不返回列头命中 —— 否则点一下分组标题会把下面某一列排序掉。 }
  if (hoVisible in FHeader.Options)
     and (AY < ScaleI(FHeader.Height) + GroupBandHeightPx) then
  begin
    if AY < GroupBandHeightPx then Exit;   { 分组带:不是叶子列头 }
    Result.Part := ghpHeader;
    Result.Col := ColumnAtX(AX);
    Exit;
  end;

  { 行头槽:列头之下、冻结带最左那条。 }
  if FShowIndicator and (AX < ScaleI(FIndicatorWidth)) then
  begin
    Result.Part := ghpIndicator;
    Result.Row := TyGridRowAt(AY, M);
    if Result.Row >= 0 then Result.Row := DisplayToData(Result.Row);
    Exit;
  end;

  Result.Row := TyGridRowAt(AY, M);
  if Result.Row < 0 then Exit;      { 末行之后的空白 }
  Result.Row := DisplayToData(Result.Row);   { 对外一律给数据行 }
  if Result.Row < 0 then                     { 分组行:不是单元格 }
  begin
    Result.Part := ghpNowhere;
    Result.Col := -1;
    Exit;
  end;
  Result.Col := ColumnAtX(AX);
  if Result.Col < 0 then Exit;      { 末列之后的空白 }
  MapToBaseCell(Result.Col, Result.Row);   { 合并区里点哪都算基准格 }
  Result.Part := ghpCell;
end;

function TTyCustomGrid.GridLineColor(const AFrame: TTyStyleSet): TBGRAPixel;
var
  lineS: TTyStyleSet;
begin
  lineS := ActiveController.Model.ResolveStyle('TyGridLine', StyleClass, CurrentStates);
  if tpBackground in lineS.Present then
    Result := TyColorToBGRA(lineS.Background.Color)
  else
    Result := TyColorToBGRA(AFrame.BorderColor);
end;

procedure TTyCustomGrid.RenderGridLines(P: TTyPainter; const M: TTyGridMetrics;
  const AFrame: TTyStyleSet);
var
  slot: Integer;   { 绘制槽位 }
  first, last, row, i, x, lw, half: Integer;
  r: TRect;
  line: TBGRAPixel;
  col: TTyColumn;
  merged: Boolean;
begin
  line := GridLineColor(AFrame);

  { 线压在边界上、两侧各占一半:lw=1 时就是从前那条 r.Bottom-1 的发丝线,
    加粗时向两边长而不是把边界推走(列宽/行高不因线粗而改变)。 }
  lw := M.GridLineWidth;
  if lw < 1 then lw := 1;
  half := lw div 2;

  { 有没有合并区决定走哪条路:没有就整条画完(绝大多数表),
    有才逐列/逐行分段、跳过合并区内部的边界。
    分段要多出 列数 x 行数 次 FillRect,不能让没用合并的表白白付这个钱。 }
  merged := HasMergedCells;

  { 横线:每一可见行的下沿。只走 TyGridVisibleRows —— 百万行的表在这里也只画几十条。 }
  if (FGridLineStyle in [glsHorizontal, glsBoth]) and TyGridDrawSlots(M, first, last) then
    for slot := first to last do
    begin
      row := TyGridRowAtSlot(slot, M);
      if row < 0 then Continue;
      r := TyGridRowRect(row, M);
      if not merged then
        P.Bitmap.FillRect(0, r.Bottom - 1 - half, M.ClientW, r.Bottom - 1 - half + lw,
          line, dmSet)
      else
        { 逐列分段:本行与下一行在这一列上属于同一个合并区时,跳过这一段。 }
        for i := 0 to FHeader.Columns.Count - 1 do
        begin
          col := TTyColumn(FHeader.Columns.Items[i]);
          if not (coVisible in col.Options) then Continue;
          if SameMergedCell(i, DisplayToData(row), i, DisplayToData(row + 1)) then Continue;
          x := ColumnLeftPx(i);
          P.Bitmap.FillRect(x, r.Bottom - 1 - half,
            x + ColumnWidthPx(i), r.Bottom - 1 - half + lw, line, dmSet);
        end;
    end;

  { 竖线:每一可见列的右缘。位置走 ColumnLeftPx(列轴唯一出处),
    绝不另算 —— 否则线会和单元格边界差一像素。 }
  if not (FGridLineStyle in [glsVertical, glsBoth]) then Exit;
  for i := 0 to FHeader.Columns.Count - 1 do
  begin
    col := TTyColumn(FHeader.Columns.Items[i]);
    if not (coVisible in col.Options) then Continue;
    x := ColumnLeftPx(i) + ColumnWidthPx(i);
    if (x <= 0) or (x > M.ClientW) then Continue;
    if not merged then
      P.Bitmap.FillRect(x - 1 - half, M.FrozenTop, x - 1 - half + lw, M.ClientH,
        line, dmSet)
    else
      { 逐行分段:本列与右邻列在这一行上属于同一个合并区时,跳过这一段。 }
      if TyGridDrawSlots(M, first, last) then
        for slot := first to last do
        begin
          row := TyGridRowAtSlot(slot, M);
          if row < 0 then Continue;
          if SameMergedCell(i, DisplayToData(row), i + 1, DisplayToData(row)) then Continue;
          r := TyGridRowRect(row, M);
          P.Bitmap.FillRect(x - 1 - half, r.Top, x - 1 - half + lw, r.Bottom,
            line, dmSet);
        end;
  end;
end;

procedure TTyCustomGrid.FillRegion(P: TTyPainter; const ARect: TRect; const AKey: string);
var
  S: TTyStyleSet;
begin
  if IsRectEmpty(ARect) then Exit;
  S := ActiveController.Model.ResolveStyle(AKey, StyleClass, CurrentStates);
  if not (tpBackground in S.Present) then Exit;   { 皮肤没写这块 → 透出表面本色 }
  P.FillBackground(ARect, S.Background, 0);
end;

function TTyCustomGrid.DividerAtX(AX: Integer): Integer;
var
  i, edge, tol: Integer;
begin
  Result := -1;
  if not (hoColumnResize in FHeader.Options) then Exit;
  tol := ScaleI(4);
  for i := 0 to FHeader.Columns.Count - 1 do
  begin
    if not (coVisible in TTyColumn(FHeader.Columns.Items[i]).Options) then Continue;
    edge := ColumnLeftPx(i) + ColumnWidthPx(i);
    if Abs(AX - edge) <= tol then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

procedure TTyCustomGrid.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  hdrH, d: Integer;
  col: TTyColumn;
begin
  inherited MouseDown(Button, Shift, X, Y);
  { 无条件记账 —— 要在所有提前 Exit 之前,否则分隔条/右键那几条路径上
    留下的是上一次的陈旧命中。 }
  FLastDownHit := CellAt(X, Y);
  if Button <> mbLeft then Exit;

  hdrH := 0;
  if hoVisible in FHeader.Options then
    hdrH := ScaleI(FHeader.Height) + GroupBandHeightPx;

  { 行分隔线在**行头槽**里拖 —— 与列分隔线在列头里拖对称。
    放在单元格上会和框选拖拽抢手势。 }
  if Y >= hdrH then
  begin
    d := RowDividerAtY(X, Y);
    if d >= 0 then
    begin
      FResizeRow := d;
      FResizeStartY := Y;
      FResizeStartH := RowHeightOf(DisplayToData(d));
    end;
    Exit;
  end;

  if hdrH <= 0 then Exit;

  { 分隔条优先于列体 —— 边缘那几像素上,用户的意图是改宽而不是排序。 }
  d := DividerAtX(X);
  if d >= 0 then
  begin
    { 双击分隔线 = 按内容自适应列宽,是表格的通用手势。
      LCL 在第二次按下时把 ssDouble 塞进 Shift。 }
    if ssDouble in Shift then
    begin
      AutoFitColumnWidth(d);
      Exit;
    end;
    FResizeCol := d;
    FResizeStartX := X;
    FResizeStartW := TTyColumn(FHeader.Columns.Items[d]).Width;
    Exit;
  end;

  { 否则记下"可能是拖动列"——真正的重排等 MouseMove 越过阈值才算数,
    这样单纯点一下列头仍然是排序。 }
  d := ColumnAtX(X);
  if d >= 0 then
  begin
    if Assigned(FOnHeaderClick) then FOnHeaderClick(Self, d);
    col := TTyColumn(FHeader.Columns.Items[d]);
    if (hoDrag in FHeader.Options) and (coDraggable in col.Options) then
    begin
      FDragCol := d;
      FDragStartX := X;
    end;
  end;
end;

procedure TTyCustomGrid.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  target, delta, newSize: Integer;
  allow: Boolean;
begin
  inherited MouseMove(Shift, X, Y);

  UpdateHoverCell(X, Y);
  { 正在拖的时候别改指针 —— 手上已经在拖了,形状应当保持。 }
  if (FResizeCol < 0) and (FResizeRow < 0) then UpdateHoverCursor(X, Y);

  if FResizeRow >= 0 then
  begin
    delta := UnscaleI(Y - FResizeStartY);
    newSize := FResizeStartH + delta;
    allow := True;
    if Assigned(FOnRowSizing) then
      FOnRowSizing(Self, DisplayToData(FResizeRow), newSize, allow);
    { 上下限的钳制在 SetRowHeights 里统一做 —— 这里不重复。 }
    if allow then RowHeights[DisplayToData(FResizeRow)] := newSize;
    Exit;
  end;

  if FResizeCol >= 0 then
  begin
    delta := UnscaleI(X - FResizeStartX);
    newSize := FResizeStartW + delta;
    { 上下限 + 宿主否决,都在**赋值之前** —— 赋完再回退会闪一下。 }
    if (FMinColWidth > 0) and (newSize < FMinColWidth) then newSize := FMinColWidth;
    if (FMaxColWidth > 0) and (newSize > FMaxColWidth) then newSize := FMaxColWidth;
    allow := True;
    if Assigned(FOnColumnSizing) then FOnColumnSizing(Self, FResizeCol, newSize, allow);
    if allow then
    begin
      TTyColumn(FHeader.Columns.Items[FResizeCol]).Width := newSize;
      UpdateScrollBars;
      Invalidate;
    end;
    Exit;
  end;

  if FDragCol >= 0 then
  begin
    { 越过阈值才算拖动 —— 否则手抖一像素就把列挪了。 }
    if Abs(X - FDragStartX) < ScaleI(8) then Exit;
    target := ColumnAtX(X);
    if (target >= 0) and (target <> FDragCol) then
    begin
      { 复用列模型现成的位置调整(coDraggable/AdjustPosition 早就建好了,
        一直没人接线 —— 这里就是那根线)。 }
      allow := True;
      if Assigned(FOnColumnMove) then FOnColumnMove(Self, FDragCol, target, allow);
      if allow then
      begin
        FHeader.Columns.AdjustPosition(TTyColumn(FHeader.Columns.Items[FDragCol]),
          TTyColumn(FHeader.Columns.Items[target]).Position);
        FDragStartX := X;
        Invalidate;
      end;
    end;
  end;
end;

procedure TTyCustomGrid.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  { 拖完了才发"结束"事件 —— 宿主拿它保存列宽偏好,拖动过程中发是噪音。 }
  if (FResizeCol >= 0) and Assigned(FOnEndColumnSize) then
    FOnEndColumnSize(Self, FResizeCol,
      TTyColumn(FHeader.Columns.Items[FResizeCol]).Width);
  if (FResizeRow >= 0) and Assigned(FOnEndRowSize) then
    FOnEndRowSize(Self, DisplayToData(FResizeRow),
      RowHeightOf(DisplayToData(FResizeRow)));

  FResizeCol := -1;
  FResizeRow := -1;
  FDragCol := -1;
  inherited MouseUp(Button, Shift, X, Y);
end;

function TTyCustomGrid.ShowsFilterButton(ACol: Integer): Boolean;
begin
  Result := False;
end;

function TTyCustomGrid.HasMergedCells: Boolean;
begin
  Result := False;      { 基类没有合并概念 }
end;

function TTyCustomGrid.SameMergedCell(ACol1, ARow1, ACol2, ARow2: Integer): Boolean;
begin
  Result := False;
end;

function TTyCustomGrid.ColumnFilterActive(ACol: Integer): Boolean;
begin
  Result := False;
end;

function TTyCustomGrid.SortRankOf(ACol: Integer): Integer;
begin
  Result := 0;
end;

function TTyCustomGrid.SortColumnCountOf: Integer;
begin
  Result := 0;
end;

function TTyCustomGrid.HeaderFilterRect(ACol, AHeaderH: Integer): TRect;
var
  l, w, cx, cy, gs: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if not ShowsFilterButton(ACol) then Exit;
  l := ColumnLeftPx(ACol);
  w := ColumnWidthPx(ACol);
  if w <= 0 then Exit;
  gs := 0;
  if (hoShowSortGlyphs in FHeader.Options) and (ACol = FHeader.SortColumn) then
    gs := ScaleI(12);
  cx := l + w - ScaleI(10) - gs;
  cy := AHeaderH div 2;
  Result := Rect(cx - ScaleI(7), cy - ScaleI(7), cx + ScaleI(7), cy + ScaleI(7));
end;

procedure TTyCustomGrid.RenderHeaderSections(P: TTyPainter; const M: TTyGridMetrics;
  AHeaderH: Integer);
var
  i, l, w, cx, cy, gs, imgIdx, imgSz, imgPad, bandTop: Integer;
  hdrBg: TTyFill;
  hdrHasBg: Boolean;
  hdrInk, accentInk, funnelInk: TTyColor;
  hdrFontName: string;
  hdrFontSize, hdrFontWeight: Integer;
  col: TTyColumn;
  bmp: TBGRABitmap;
  secS, hdrS, actHdrS: TTyStyleSet;
  ink: TTyColor;
  r, textR: TRect;
  line: TBGRAPixel;
begin
  hdrS := ActiveController.Model.ResolveStyle('TyGridHeader', StyleClass, CurrentStates);
  secS := ActiveController.Model.ResolveStyle('TyGridHeaderSection', StyleClass, CurrentStates);
  if tpTextColor in secS.Present then ink := secS.TextColor
  else if tpTextColor in hdrS.Present then ink := hdrS.TextColor
  else ink := CurrentStyle.TextColor;
  line := TyColorToBGRA(hdrS.BorderColor);
  { 激活态漏斗的颜色走主题(选中态的表头文字色);主题没给就退回普通墨色 ——
    绝不自己发明一个颜色。 }
  actHdrS := ActiveController.Model.ResolveStyle('TyGridHeaderSection',
    StyleClass, [tysSelected]);
  if tpTextColor in actHdrS.Present then accentInk := actHdrS.TextColor
  else accentInk := ink;

  { 列头带**在分组带之下**。没有分组时 bandTop = 0,与从前逐像素一致。 }
  bandTop := GroupBandHeightPx;

  for i := 0 to FHeader.Columns.Count - 1 do
  begin
    col := TTyColumn(FHeader.Columns.Items[i]);
    if not (coVisible in col.Options) then Continue;
    l := ColumnLeftPx(i);
    w := ColumnWidthPx(i);
    if (w <= 0) or (l >= M.ClientW) or (l + w <= 0) then Continue;
    { 正文列滚到冻结带底下的那一截不该露出来 —— 与单元格同一条裁剪规则。 }
    if (i >= FFixedCols) and (l < M.FrozenLeft) then
    begin
      if l + w <= M.FrozenLeft then Continue;
      l := M.FrozenLeft;
      w := ColumnLeftPx(i) + ColumnWidthPx(i) - l;
    end;

    r := Rect(l, bandTop, l + w, bandTop + AHeaderH);

    { 表头格自绘钩子:必填列标红、当前排序列高亮。
      从主题解析出来的值打底,宿主想改哪个改哪个。 }
    hdrBg := secS.Background;
    hdrHasBg := tpBackground in secS.Present;
    hdrInk := ink;
    hdrFontName := hdrS.FontName;
    hdrFontSize := ResolveFontSize(hdrS);
    hdrFontWeight := hdrS.FontWeight;
    if Assigned(FOnGetHeaderStyle) then
    begin
      FOnGetHeaderStyle(Self, i, hdrBg, hdrInk, hdrFontName, hdrFontSize, hdrFontWeight);
      hdrHasBg := hdrBg.Kind <> tfkNone;
    end;

    if hdrHasBg then
      P.FillBackground(r, hdrBg, 0);

    { 排序列留出字形的位置,标题文字缩进一点。 }
    gs := 0;
    if (hoShowSortGlyphs in FHeader.Options) and (i = FHeader.SortColumn) then
      gs := ScaleI(12);
    imgPad := 0;

    { 列头图标必须**先画、先累加 imgPad**,下面算 textR 时标题才让得出位。
      原先这一段在 textR 之后,于是 imgPad 恒为 0、标题不缩进,
      图标直接压在标题左端的字上。
      (当初那条测试只数"表头带里有没有红像素",图标画在字**上面**照样满足 ——
      测试对"压字"是瞎的。现在改成同时看标题墨的左右两端。) }
    imgIdx := col.ImageIndex;
    if (FImages <> nil) and (imgIdx >= 0) then
    begin
      imgSz := ScaleI(16);
      if imgSz > AHeaderH - ScaleI(4) then imgSz := AHeaderH - ScaleI(4);
      if imgSz > 0 then
      begin
        bmp := FImages.CachedIndex(imgIdx, imgSz);
        if bmp <> nil then
        begin
          P.Bitmap.PutImage(r.Left + ScaleI(4), bandTop + (AHeaderH - imgSz) div 2, bmp,
            dmDrawWithTransparency);
          Inc(imgPad, imgSz + ScaleI(4));
        end;
      end;
    end;

    textR := Rect(r.Left + ScaleI(6) + imgPad, r.Top, r.Right - ScaleI(4) - gs, r.Bottom);
    if (col.Text <> '') and (textR.Right > textR.Left) then
      P.DrawText(textR, col.Text, hdrFontName, hdrFontSize,
        hdrFontWeight, hdrInk, col.CaptionAlignment, tlCenter, True);

    { 该列有筛选时,标题右侧留一个漏斗位(用向下箭头示意)。
      **正在过滤的列要点亮** —— 用户得一眼看出哪列在过滤中,
      否则"为什么少了几行"会变成一次排查。 }
    if ShowsFilterButton(i) then
    begin
      cx := r.Right - ScaleI(10) - gs;
      cy := bandTop + AHeaderH div 2;
      if ColumnFilterActive(i) then funnelInk := accentInk else funnelInk := ink;
      TyDrawGlyph(P, ActiveController,
        Rect(cx - ScaleI(5), cy - ScaleI(4), cx + ScaleI(5), cy + ScaleI(4)),
        tgChevronDown, funnelInk, 1, 1);
    end;

    { 多列排序徽标:第几顺位。做完多列排序不配套它,
      用户根本看不出"到底按哪几列排的、谁优先"。单列排序时不显示(没有歧义)。 }
    if (hoShowSortGlyphs in FHeader.Options) and (SortColumnCountOf > 1)
       and (SortRankOf(i) > 0) then
    begin
      textR := Rect(r.Right - ScaleI(24), r.Top, r.Right - ScaleI(14), r.Bottom);
      if textR.Right > textR.Left then
        P.DrawText(textR, IntToStr(SortRankOf(i)), hdrFontName,
          hdrFontSize - 2, hdrFontWeight, hdrInk, taCenter, tlCenter, False);
    end;

    { 排序方向的小三角。 }
    if gs > 0 then
    begin
      cx := r.Right - ScaleI(10);
      cy := bandTop + AHeaderH div 2;
      { 槽位式调用传 pad=1:DrawGlyph 默认每边内缩 4 逻辑像素,小槽里会只剩个糊点。 }
      if FHeader.SortDirection = sdAscending then
        TyDrawGlyph(P, ActiveController,
          Rect(cx - ScaleI(5), cy - ScaleI(4), cx + ScaleI(5), cy + ScaleI(4)),
          tgArrowUp, ink, 1, 1)
      else
        TyDrawGlyph(P, ActiveController,
          Rect(cx - ScaleI(5), cy - ScaleI(4), cx + ScaleI(5), cy + ScaleI(4)),
          tgArrowDown, ink, 1, 1);
    end;

    { 分段之间的竖分隔线。 }
    if r.Right - 1 < M.ClientW then
      P.Bitmap.DrawLine(r.Right - 1, bandTop, r.Right - 1, bandTop + AHeaderH,
        line, False);
  end;
end;

procedure TTyCustomGrid.RenderChrome(P: TTyPainter; const M: TTyGridMetrics);
var
  headerH, indW: Integer;
begin
  headerH := 0;
  if hoVisible in FHeader.Options then
    headerH := ScaleI(FHeader.Height) + GroupBandHeightPx;
  indW := 0;
  if FShowIndicator then indW := ScaleI(FIndicatorWidth);

  { 次序 = 遮挡次序,且必须与 CellAt 的判定次序一致,否则"看到的"和"点到的"会错位。
    先画下层的行头槽与固定列,最后让列头带横跨整幅盖上去(含左上角)。 }

  { 行头槽:列头之下、最左那条。 }
  if indW > 0 then
  begin
    FillRegion(P, Rect(0, headerH, indW, M.ClientH), 'TyGridIndicator');
    RenderRowNumbers(P, M, headerH, indW);
  end;

  { 固定列区:行头槽右侧到冻结带右缘。 }
  if M.FrozenLeft > indW then
    FillRegion(P, Rect(indW, headerH, M.FrozenLeft, M.ClientH), 'TyGridFixed');

  { 列头带:横跨整幅宽度,盖住左上角 —— 与 CellAt 里"列头优先"一致。 }
  if headerH > 0 then
  begin
    FillRegion(P, Rect(0, 0, M.ClientW, headerH), 'TyGridHeader');
    { 分组带先画(在上),列头带画在它下面。 }
    RenderHeaderGroups(P, M);
    RenderHeaderSections(P, M, ScaleI(FHeader.Height));
  end;
end;

procedure TTyCustomGrid.RenderCells(P: TTyPainter; const M: TTyGridMetrics;
  const AFrame: TTyStyleSet);
begin
  { 基类不画内容:它不知道数据从哪来。TTyDrawGrid / TTyStringGrid 改写。 }
end;

procedure TTyCustomGrid.RenderHeaderGroups(P: TTyPainter; const M: TTyGridMetrics);
var
  i, l, r0, h: Integer;
  g: TTyGridHeaderGroup;
  secS, hdrS: TTyStyleSet;
  ink: TTyColor;
  rc: TRect;
  line: TBGRAPixel;
begin
  h := GroupBandHeightPx;
  if h <= 0 then Exit;

  hdrS := ActiveController.Model.ResolveStyle('TyGridHeader', StyleClass, CurrentStates);
  secS := ActiveController.Model.ResolveStyle('TyGridHeaderGroup', StyleClass, CurrentStates);
  if tpTextColor in secS.Present then ink := secS.TextColor
  else if tpTextColor in hdrS.Present then ink := hdrS.TextColor
  else ink := CurrentStyle.TextColor;
  line := TyColorToBGRA(hdrS.BorderColor);

  for i := 0 to FHeaderGroups.Count - 1 do
  begin
    g := TTyGridHeaderGroup(FHeaderGroups.Items[i]);
    if g.Level <> 0 then Continue;
    if (g.FirstCol < 0) or (g.FirstCol >= FHeader.Columns.Count) then Continue;

    { 跨列 = 从首列左缘到末列右缘。列宽/拖动重排都自动跟着走,
      因为两端都取自 ColumnLeftPx —— 列轴的唯一出处。 }
    l := ColumnLeftPx(g.FirstCol);
    if g.LastCol < FHeader.Columns.Count then
      r0 := ColumnLeftPx(g.LastCol) + ColumnWidthPx(g.LastCol)
    else
      r0 := ColumnLeftPx(FHeader.Columns.Count - 1)
            + ColumnWidthPx(FHeader.Columns.Count - 1);
    if r0 <= l then Continue;

    rc := Rect(l, 0, r0, h);
    if tpBackground in secS.Present then
      P.FillBackground(rc, secS.Background, 0);
    if g.Text <> '' then
      P.DrawText(Rect(rc.Left + ScaleI(4), rc.Top, rc.Right - ScaleI(4), rc.Bottom),
        g.Text, hdrS.FontName, ResolveFontSize(hdrS), hdrS.FontWeight, ink,
        g.Alignment, tlCenter, True);
    if rc.Right - 1 < M.ClientW then
      P.Bitmap.DrawLine(rc.Right - 1, 0, rc.Right - 1, h, line, False);
  end;

  { 分组带与列头带之间的横分隔线。 }
  P.Bitmap.DrawLine(0, h - 1, M.ClientW, h - 1, line, False);
end;

procedure TTyCustomGrid.RenderCellBorders(P: TTyPainter; const M: TTyGridMetrics);
var
  slot: Integer;   { 绘制槽位 }
  firstRow, lastRow, row, i, dataRow, w: Integer;
  col: TTyColumn;
  b: TTyGridCellBorders;
  cell: TRect;
  px: TBGRAPixel;
begin
  { 没人接钩子 = 没有逐格边框。整个遍历都省掉。 }
  if not Assigned(FOnGetCellBorder) then Exit;
  { 走绘制槽位:顶部固定行 + 正文窗口(固定行不在正文窗口里)。 }
  if not TyGridDrawSlots(M, firstRow, lastRow) then Exit;

  for slot := firstRow to lastRow do
  begin
    row := TyGridRowAtSlot(slot, M);
    if row < 0 then Continue;
    for i := 0 to FHeader.Columns.Count - 1 do
    begin
      col := TTyColumn(FHeader.Columns.Items[i]);
      if not (coVisible in col.Options) then Continue;
      dataRow := DisplayToData(row);

      b := Default(TTyGridCellBorders);
      b.Width := 1;
      b.Color := CurrentStyle.BorderColor;
      FOnGetCellBorder(Self, i, dataRow, b);
      if not (b.Left or b.Top or b.Right or b.Bottom) then Continue;

      cell := CellVisibleRect(i, dataRow);
      if IsRectEmpty(cell) then Continue;
      w := ScaleI(b.Width);
      if w < 1 then w := 1;
      px := TyColorToBGRA(b.Color);

      { 边框画在单元格**内侧** —— 与 StrokeBorder 同一条约定,
        免得相邻两格的边框互相盖住半个像素。 }
      if b.Top then
        P.Bitmap.FillRect(cell.Left, cell.Top, cell.Right, cell.Top + w, px, dmSet);
      if b.Bottom then
        P.Bitmap.FillRect(cell.Left, cell.Bottom - w, cell.Right, cell.Bottom, px, dmSet);
      if b.Left then
        P.Bitmap.FillRect(cell.Left, cell.Top, cell.Left + w, cell.Bottom, px, dmSet);
      if b.Right then
        P.Bitmap.FillRect(cell.Right - w, cell.Top, cell.Right, cell.Bottom, px, dmSet);
    end;
  end;
end;

procedure TTyCustomGrid.RenderCellBackgrounds(P: TTyPainter; const M: TTyGridMetrics);
var
  slot: Integer;   { 绘制槽位 }
  firstRow, lastRow, row, i, dataRow: Integer;
  col: TTyColumn;
  ap: TTyGridCellAppearance;
  vis: TRect;
  AFrame: TTyStyleSet;
begin
  AFrame := CurrentStyle;
  { 只遍历可视窗口 —— 与 RenderCells 同一条虚拟化路径。 }
  { 走绘制槽位:顶部固定行 + 正文窗口(固定行不在正文窗口里)。 }
  if not TyGridDrawSlots(M, firstRow, lastRow) then Exit;

  for slot := firstRow to lastRow do
  begin
    row := TyGridRowAtSlot(slot, M);
    if row < 0 then Continue;
    for i := 0 to FHeader.Columns.Count - 1 do
    begin
      col := TTyColumn(FHeader.Columns.Items[i]);
      if not (coVisible in col.Options) then Continue;

      dataRow := DisplayToData(row);
      ap := CellAppearance(i, dataRow, row, AFrame);
      { `background: none` 是默认态 —— 一个像素都不画,整帧的开销就只有
        一次 ResolveStyle(缓存命中)加一次判断。 }
      if not ap.HasBackground then Continue;

      vis := CellVisibleRect(i, dataRow);
      if IsRectEmpty(vis) then Continue;
      P.FillBackground(vis, ap.Background, 0);
    end;
  end;
end;

procedure TTyCustomGrid.RenderFooter(P: TTyPainter; const M: TTyGridMetrics;
  const AFooterRect: TRect; const AFrame: TTyStyleSet);
begin
  FillRegion(P, AFooterRect, 'TyGridSummaryRow');
end;

procedure TTyCustomGrid.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, band, oldClip: TRect;
  M: TTyGridMetrics;
  fastDy, bodyTop, seamPos: Integer;
  seamR: TRect;
  canFast: Boolean;
begin
  { 持久表面:滚动时正文那一大块像素可以整体平移复用。尺寸变了就重建。 }
  R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
  if (FSurface = nil) or (FSurface.Width <> R.Right) or (FSurface.Height <> R.Bottom) then
  begin
    FreeAndNil(FSurface);
    FSurface := TBGRABitmap.Create(R.Right, R.Bottom);
    FSurfaceFresh := False;
  end;

  { 取走本帧的快路径许可,并立刻熄灭它 —— 本帧画完了才重新点亮。
    这样中途 Exit(比如主题没给背景)不会留下一个"新鲜"却没画的表面。 }
  fastDy := 0;
  if FSurfaceFresh then fastDy := FSurfacePendingDy;
  FSurfaceFresh := False;
  FSurfacePendingDy := 0;

  P := TTyPainter.Create;
  try
    P.BeginPaintOn(ACanvas, ARect, APPI, FSurface);

    S := CurrentStyle;
    { 主题没给 TyGrid 定义背景 → 一个像素都不画。降级成空白区域,
      既不崩溃也不自己发明外观 —— 与库内其他控件一致。
      (EndPaint 在 finally 里;此时位图全透明,alpha 混合不会碰到画布。) }
    if not (tpBackground in S.Present) then Exit;

    { 每帧清一次逐格样式的记忆化 —— 主题可能在两帧之间换掉了。 }
    ResetCellStyleCache;
    { 列几何缓存按设备像素存,PPI 变了(换屏/缩放)必须重建。 }
    if FColCachePPI <> APPI then
    begin
      FColCachePPI := APPI;
      InvalidateColumnCache;
    end;
    { 整帧只算一次几何(见 FMetricsCached 处的说明)。 }
    M := GridMetrics;
    FMetricsCache := M;
    FMetricsCached := True;

    { --- 滚动快路径 ---
      正文带整体平移,只有露出来的那一条需要重画。
      重画走的是**与整幅重画完全相同的那串调用**,只是:
        ① 位图裁剪到那条带 → 带外一个像素都不会被碰;
        ② 几何里的 ClipTop/ClipBottom 把逐行循环夹到那条带 → 真正省掉 CPU。
      正因为代码路径没有分叉,结果才能与整幅重画逐像素相同(有测试守着)。 }
    bodyTop := M.FrozenTop;
    canFast := (fastDy <> 0) and (M.ClientH - bodyTop > Abs(fastDy));
    if canFast then
    begin
      Inc(FFastScrollFrames);
      ShiftSurfaceRows(bodyTop, M.ClientH, fastDy);
      if fastDy > 0 then
        band := Rect(0, M.ClientH - fastDy, M.ClientW, M.ClientH)
      else
        band := Rect(0, bodyTop, M.ClientW, bodyTop - fastDy);

      { **接缝那一行必须一起重画,不能只复用它。**
        上一帧里,骑在正文窗格边缘上的那一行是被**裁着**画的 —— 只画了露在
        窗格里的那一截。平移之后它整体进入了窗格,复用过来就少了半行文字。
        所以把带的内边沿往外吸附到行边界;跨行合并的格同理,再多让出
        MaxRowSpanHint 行,否则骑在接缝上的合并块也会缺一块。 }
      if fastDy > 0 then seamPos := TyGridRowAt(band.Top, M)
      else seamPos := TyGridRowAt(band.Bottom - 1, M);
      if seamPos >= 0 then
      begin
        if fastDy > 0 then
        begin
          seamPos := seamPos - MaxRowSpanHint;
          if seamPos < 0 then seamPos := 0;
          seamR := TyGridRowRect(seamPos, M);
          if seamR.Top < band.Top then band.Top := seamR.Top;
        end
        else
        begin
          seamPos := seamPos + MaxRowSpanHint;
          if seamPos >= DisplayRowCount then seamPos := DisplayRowCount - 1;
          seamR := TyGridRowRect(seamPos, M);
          if seamR.Bottom > band.Bottom then band.Bottom := seamR.Bottom;
        end;
      end;
      if band.Top < bodyTop then band.Top := bodyTop;
      if band.Bottom > M.ClientH then band.Bottom := M.ClientH;
      M.ClipTop := band.Top;
      M.ClipBottom := band.Bottom;
      FMetricsCache := M;
      oldClip := P.Bitmap.ClipRect;
      P.Bitmap.ClipRect := band;
    end
    else
      FSurface.Fill(BGRAPixelTransparent);

    if not canFast then DrawFrame(P, R, S)
    else FillRegion(P, band, GetStyleTypeKey);   { 露出的带先铺回本体底色 }

    RenderChrome(P, M);
    RenderCellBackgrounds(P, M);
    if FooterHeightPx > 0 then
      RenderFooter(P, M, Rect(0, M.ClientH, M.ClientW, M.ClientH + FooterHeightPx), S);
    RenderCells(P, M, S);
    { 逐格边框压在格线之上、文字之上 —— 它表达的是"分区",应当最显眼。 }
    RenderCellBorders(P, M);
    if FGridLineStyle <> glsNone then
      RenderGridLines(P, M, S);

    if canFast then P.Bitmap.ClipRect := oldClip;
    FSurfaceFresh := True;
  finally
    FMetricsCached := False;
    P.EndPaint;
    P.Free;
  end;
end;

procedure TTyCustomGrid.Paint;
begin
  RenderTo(Canvas, ClientRect, Dpi);
end;

function TTyCustomGrid.RowHeightOf(ARow: Integer): Integer;
begin
  { 优先级:显式存储 > 默认。派生类再插进回调。 }
  Result := GetRowHeights(ARow);
  if Result <= 0 then Result := FDefaultRowHeight;
end;

function TTyCustomGrid.RowTops: TTyIntArray;
begin
  Result := nil;      { 基类全等高 —— 返回空数组让几何层走整除快路径 }
end;

function TTyCustomGrid.GridMetrics: TTyGridMetrics;
begin
  if FMetricsCached then Exit(FMetricsCache);
  Result := Default(TTyGridMetrics);
  Result.ClientW := ViewportW;
  Result.ClientH := ViewportH;
  Result.FrozenLeft := FrozenWidthPx;
  Result.FrozenTop  := FrozenHeightPx;
  { 右/下冻结带的模型层还没建(B2 只先把几何契约拓宽),这里恒 0。 }
  Result.FrozenRight  := 0;
  Result.FrozenBottom := 0;
  Result.GridLineWidth := GridLineWidthPx;
  Result.RowH := ScaleI(FDefaultRowHeight);
  Result.RowCount := DisplayRowCount;
  Result.RowTops := RowTops;
  Result.FixedRows := FFixedRows;
  { 列头带。有分组时是两条(分组带在上、列头带在下),否则一条。
    B2 把 HeaderH 拆成 HeaderBands 数组,就是为了这里。 }
  if hoVisible in FHeader.Options then
  begin
    if GroupBandHeightPx > 0 then
      Result.HeaderBands := TTyIntArray.Create(GroupBandHeightPx, ScaleI(FHeader.Height))
    else
      Result.HeaderBands := TTyIntArray.Create(ScaleI(FHeader.Height));
  end
  else
    SetLength(Result.HeaderBands, 0);
  Result.ScrollX := FScrollX;
  Result.ScrollY := FScrollY;
end;

{ ---- TTyDrawGrid ---------------------------------------------------------- }

function TTyDrawGrid.GetCellText(ACol, ARow: Integer): string;
begin
  Result := '';
  if Assigned(FOnGetCellText) then
    FOnGetCellText(Self, ACol, ARow, Result);
end;

function TTyDrawGrid.ShouldDrawCellText(ACol, ARow: Integer): Boolean;
begin
  Result := True;
end;

function TTyDrawGrid.DoDrawCell(P: TTyPainter; ACol, ARow: Integer): Boolean;
begin
  Result := False;      { 基类不提供自绘钩子;TTyStringGrid 接 OnDrawCell }
end;

procedure TTyDrawGrid.RenderCells(P: TTyPainter; const M: TTyGridMetrics;
  const AFrame: TTyStyleSet);
var
  firstRow, lastRow, row, colIdx, dataRow: Integer;
  slot, firstSlot, lastSlot: Integer;   { 绘制槽位 }
  clipR: TRect;
  cellS: TTyStyleSet;
  col: TTyColumn;
  cell, vis, textR, oldClip: TRect;
  ink: TTyColor;
  txt: string;
  padL, padR: Integer;
  ap: TTyGridCellAppearance;
begin
  { 只遍历可视窗口 —— 一百万行的表在这里也只走几十行。这是虚拟化的全部实现:
    控件从不持有数据,也从不遍历全部行。 }
  { 遍历**绘制槽位**:顶部固定行 + 正文窗口。固定行不在正文窗口里,
    只走 TyGridVisibleRows 的话它们一个字都不会画(从前正是如此)。 }
  if not TyGridDrawSlots(M, firstSlot, lastSlot) then Exit;

  { 同上:内边距也别跟着网格自身的状态变,否则鼠标进出会让文字左右挪一下。 }
  cellS := ActiveController.Model.ResolveStyle('TyGridCell', StyleClass, []);
  if tpTextColor in cellS.Present then ink := cellS.TextColor
  else ink := AFrame.TextColor;
  padL := ScaleI(cellS.Padding.Left);
  padR := ScaleI(cellS.Padding.Right);

  { row 是**显示序**;下面每一步都立刻翻成数据行再去取内容。 }
  for slot := firstSlot to lastSlot do
  begin
    row := TyGridRowAtSlot(slot, M);
    if row < 0 then Continue;
    for colIdx := 0 to Header.Columns.Count - 1 do
    begin
      col := TTyColumn(Header.Columns.Items[colIdx]);
      if not (coVisible in col.Options) then Continue;

      { 可见矩形为空 = 完全被冻结带盖住或滚出视口 → 连问都不必问宿主。 }
      dataRow := DisplayToData(row);
      vis := CellVisibleRect(colIdx, dataRow);
      if IsRectEmpty(vis) then Continue;

      { 宿主完全接管这一格? }
      if DoDrawCell(P, colIdx, dataRow) then Continue;

      { 自己画图形的格(勾选框/进度条/评分)不该再叠一层文字。 }
      if not ShouldDrawCellText(colIdx, dataRow) then Continue;

      txt := GetCellText(colIdx, dataRow);
      if txt = '' then Continue;

      { 先让开格线(线压在边界上、两侧各一半),再上左右内边距。
        线宽 <= 1 时 TyGridCellContentRect 是恒等的,与从前逐像素一致。 }
      ap := CellAppearance(colIdx, dataRow, row, AFrame);
      cell := TyGridCellContentRect(CellRect(colIdx, dataRow), M);
      textR := Rect(cell.Left + padL, cell.Top, cell.Right - padR, cell.Bottom);
      if textR.Right <= textR.Left then Continue;

      { 文字按**完整**单元格排版,再裁到可见部分 —— 半掩的单元格应当被裁掉一截,
        而不是把文字挤进剩余空间里(挤压会让同一列的文字忽宽忽窄)。 }
      oldClip := P.Bitmap.ClipRect;
      { **与外层裁剪求交**,不是覆盖它。外层可能是脏区重绘限定的那条横带;
        直接覆盖的话这一格会画到带外去 —— 那里上一帧的像素还在,
        同一段文字叠画两次,抗锯齿边缘变深,于是"快路径与整幅重画逐像素相同"
        这条守卫就红了。(固定行从前根本不画,所以这个坑一直没露头。) }
      if not IntersectRect(clipR, oldClip, vis) then
      begin
        P.Bitmap.ClipRect := oldClip;
        Continue;
      end;
      P.Bitmap.ClipRect := clipR;
      try
        DrawCellText(P, textR, txt, ap.FontName, ap.FontSize, ap.FontWeight,
          ap.TextColor, ap.HAlign, ap.VAlign, ap.WordWrap);
      finally
        P.Bitmap.ClipRect := oldClip;
      end;
    end;
  end;
end;

{ ---- TTyStringGrid -------------------------------------------------------- }

constructor TTyStringGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCells := TFPStringHashTable.Create;
  FCellKeys := TStringList.Create;
  FCellKeys.Sorted := True;
  FCellKeys.Duplicates := dupIgnore;
  FColFilters := TStringList.Create;
  FValFilters := TStringList.Create;
  FAggregates := TStringList.Create;
  FCollapsed := TStringList.Create;
  FAttrs := TTyGridCellAttrStore.Create;
  FHiddenRows := TStringList.Create;
  FHiddenRows.Sorted := True;
  FHiddenRows.Duplicates := dupIgnore;
  FCol := 0;
  FRow := 0;
  TabStop := True;                      { 要接键盘 }
  FReadOnly := False;
  FDefaultEditorKind := gekText;
  FSelAnchorCol := 0;
  FSelAnchorRow := 0;
  FSelectionMode := gsmCell;
  FHintCol := -1;
  FHintRow := -1;
  FSortCol := -1;
  FSortDir := sdAscending;
  FSortKind := gskText;
  FBlanksPosition := gbpLast;
  FSortIgnoreCase := True;
  { resourcestring 在 FPC 里不可赋值给常量表达式,但可以读 —— 这里当初值用。
    (与 TyFallbackFontName 同一套做法。) }
  FGroupRowFormat := rsGridGroupRow;
  FAutoGrowOnPaste := True;
  FGroupCol := -1;
  FFilterCol := -1;
  FShowFilterButtons := False;
  FShowGroupSubtotals := True;
  FFilterAllValues := TStringList.Create;
  FFilterChecked := TStringList.Create;
  FFilterChecked.Sorted := True;
  FFilterChecked.Duplicates := dupIgnore;
  FDefaultCellDisplay := gcdText;

  { 一个复用的内联编辑器,盖在被编辑的单元格上。 }
  FEditor := TTyEdit.Create(Self);
  FEditor.Parent := Self;
  FEditor.Visible := False;
  FEditor.ControlStyle := FEditor.ControlStyle + [csNoDesignVisible];
  FEditor.OnKeyDown := @EditorKeyDown;
  FEditor.OnExit := @EditorExit;

  { 以下几个都是把库里**现成的控件**接进来当编辑器 —— 网格只负责摆位置、
    灌值、取值,不重造轮子。生命周期规则与文本编辑器一致。 }
  FSpinEditor := TTySpinEdit.Create(Self);
  FSpinEditor.Parent := Self;
  FSpinEditor.Visible := False;
  FSpinEditor.ControlStyle := FSpinEditor.ControlStyle + [csNoDesignVisible];
  FSpinEditor.OnExit := @EditorExit;

  FSliderEditor := TTyTrackBar.Create(Self);
  FSliderEditor.Parent := Self;
  FSliderEditor.Visible := False;
  FSliderEditor.ControlStyle := FSliderEditor.ControlStyle + [csNoDesignVisible];
  FSliderEditor.OnExit := @EditorExit;

  FMemoEditor := TTyMemo.Create(Self);
  FMemoEditor.Parent := Self;
  FMemoEditor.Visible := False;
  FMemoEditor.ControlStyle := FMemoEditor.ControlStyle + [csNoDesignVisible];
  FMemoEditor.OnExit := @EditorExit;

  FCalcEditor := TTyCalcEdit.Create(Self);
  FCalcEditor.Parent := Self;
  FCalcEditor.Visible := False;
  FCalcEditor.ControlStyle := FCalcEditor.ControlStyle + [csNoDesignVisible];
  FCalcEditor.OnExit := @EditorExit;

  FMaskEditor := TTyMaskEdit.Create(Self);
  FMaskEditor.Parent := Self;
  FMaskEditor.Visible := False;
  FMaskEditor.ControlStyle := FMaskEditor.ControlStyle + [csNoDesignVisible];
  FMaskEditor.OnKeyDown := @EditorKeyDown;
  FMaskEditor.OnExit := @EditorExit;

  { 第二个复用编辑器:下拉选取。与文本编辑器同一套生命周期规则。 }
  FPickEditor := TTyComboBox.Create(Self);
  FPickEditor.Parent := Self;
  FPickEditor.Visible := False;
  FPickEditor.ControlStyle := FPickEditor.ControlStyle + [csNoDesignVisible];
  FPickEditor.OnChange := @PickEditorChange;
  FPickEditor.OnExit := @PickEditorExit;

  { 第三个复用编辑器:日期选择器。 }
  FDateEditor := TTyDateTimePicker.Create(Self);
  FDateEditor.Parent := Self;
  FDateEditor.Visible := False;
  FDateEditor.ControlStyle := FDateEditor.ControlStyle + [csNoDesignVisible];
  FDateEditor.OnExit := @DateEditorExit;
end;

destructor TTyStringGrid.Destroy;
begin
  FEditor.OnKeyDown := nil;     { 先摘回调,别在半毁对象上回调 }
  FEditor.OnExit := nil;
  FPickEditor.OnChange := nil;
  FPickEditor.OnExit := nil;
  FDateEditor.OnExit := nil;
  FCells.Free;
  FCellKeys.Free;
  FColFilters.Free;
  FValFilters.Free;
  FAggregates.Free;
  FCollapsed.Free;
  FAttrs.Free;
  FHiddenRows.Free;
  inherited Destroy;
end;

function TTyStringGrid.CellKey(ACol, ARow: Integer): string;
begin
  Result := IntToStr(ACol) + ':' + IntToStr(ARow);
end;

function TTyStringGrid.GetCells(ACol, ARow: Integer): string;
begin
  Result := FCells.Items[CellKey(ACol, ARow)];   { 哈希查找,O(1) }
end;

procedure TTyStringGrid.SetCells(ACol, ARow: Integer; const AValue: string);
var
  k: string;
  i: Integer;
begin
  k := CellKey(ACol, ARow);
  if AValue = '' then
  begin
    FCells.Delete(k);                 { 写空串 = 删除条目,稀疏存储不为空值留位置 }
    i := FCellKeys.IndexOf(k);
    if i >= 0 then FCellKeys.Delete(i);
  end
  else
  begin
    FCells.Items[k] := AValue;        { 已存在则覆写,不存在则新增 }
    FCellKeys.Add(k);                 { 有序表 + dupIgnore,重复添加自动忽略 }
  end;
  Invalidate;
end;

procedure TTyStringGrid.ClearCells;
begin
  FCells.Clear;
  FCellKeys.Clear;
  Invalidate;
end;

function TTyStringGrid.StoredCellCount: Integer;
begin
  Result := FCells.Count;
end;

function TTyStringGrid.GetCellText(ACol, ARow: Integer): string;
begin
  { 先给宿主事件机会(虚拟模式);没接事件就用自带存储。 }
  Result := inherited GetCellText(ACol, ARow);
  if Result = '' then
    Result := GetCells(ACol, ARow);
end;

procedure TTyStringGrid.SetSelectionMode(AValue: TTyGridSelectionMode);
begin
  if FSelectionMode = AValue then Exit;
  FSelectionMode := AValue;
  Invalidate;
end;

procedure TTyStringGrid.SetCol(AValue: Integer);
begin
  MoveCursor(AValue, FRow);
end;

procedure TTyStringGrid.SetRow(AValue: Integer);
begin
  MoveCursor(FCol, AValue);
end;

{ 从 AFrom 起沿 AStep 方向找第一个可编辑的列;找不到就原样返回。 }
function TTyStringGrid.NextEditableCol(AFrom, AStep, ARow: Integer): Integer;
var
  c: Integer;
begin
  Result := AFrom;
  if AStep = 0 then Exit;
  c := AFrom;
  while (c >= 0) and (c < Header.Columns.Count) do
  begin
    if EditorKindFor(c, ARow) <> gekNone then Exit(c);
    Inc(c, AStep);
  end;
end;

procedure TTyStringGrid.MoveCursor(ACol, ARow: Integer);
var
  canSel: Boolean;
begin
  { 钳制到合法范围 —— 越界的光标会让绘制与命中都失去参照。 }
  if ACol < 0 then ACol := 0;
  if ARow < 0 then ARow := 0;
  if ACol > Header.Columns.Count - 1 then ACol := Header.Columns.Count - 1;
  if ARow > RowCount - 1 then ARow := RowCount - 1;
  if (ACol = FCol) and (ARow = FRow) then Exit;

  { **隐藏列上不能停光标** —— 停上去的话编辑器会在一个看不见的地方打开。
    沿本次移动的方向找下一个可见列;方向不明(直接赋值)时先往右找、再往左找。 }
  if IsHiddenColumn(ACol) then
  begin
    if ACol <> FCol then
      ACol := NextVisibleCol(ACol, Sign(ACol - FCol))
    else
      ACol := NextVisibleCol(ACol, 1);
    if IsHiddenColumn(ACol) then ACol := NextVisibleCol(ACol, -1);
  end;

  { 跳过不可编辑的格:沿**本次移动的方向**继续找,而不是原地不动 ——
    原地不动的话方向键会像撞墙,用户以为网格卡了。
    找不到就落回原来的目标(总得有个当前格)。 }
  if FSkipReadOnly and (ARow = FRow) and (ACol <> FCol) then
    ACol := NextEditableCol(ACol, Sign(ACol - FCol), ARow);

  { 光标要动了 —— 先把正在编辑的格提交掉,否则编辑框会悬在旧位置。 }
  EndEdit(True);

  canSel := True;
  if Assigned(FOnSelectCell) then FOnSelectCell(Self, ACol, ARow, canSel);
  if not canSel then Exit;

  FCol := ACol;
  FRow := ARow;
  ScrollIntoView(FCol, FRow);   { 光标走到哪,视口跟到哪 }
  Invalidate;
end;

procedure TTyStringGrid.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  hit: TTyGridHit;
  gPos, gIdx: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if not Enabled then Exit;

  { 右键:只**报告**点在哪,不动光标、不进编辑 —— 与资源管理器一致,
    右键是"问",不是"选"。从前整条右键路径被开头的 `Button <> mbLeft` 全挡掉了。 }
  if Button = mbRight then
  begin
    hit := CellAt(X, Y);
    if (hit.Part = ghpHeader) and (hit.Col >= 0) then
    begin
      if Assigned(OnHeaderRightClick) then OnHeaderRightClick(Self, hit.Col);
    end
    else if hit.Part = ghpCell then
    begin
      if not CanClickCell(hit.Col, hit.Row) then Exit;
      if Assigned(OnRightClickCell) then OnRightClickCell(Self, hit.Col, hit.Row);
    end;
    Exit;
  end;

  if Button <> mbLeft then Exit;

  { 命中走 CellAt —— 与绘制同源,所以点哪格就选哪格,不会错位。 }
  { 分组行整行都可点(不只三角)—— 目标大、好点。 }
  if FGroupCol >= 0 then
  begin
    gPos := TyGridRowAt(Y, GridMetrics);
    if (gPos >= 0) and IsGroupRow(gPos, gIdx) then
    begin
      ToggleGroup(gIdx);
      Exit;
    end;
  end;

  hit := CellAt(X, Y);
  if (hit.Part = ghpHeader) and (hit.Col >= 0)
     and ShowsFilterButton(hit.Col)
     and PtInRect(HeaderFilterRect(hit.Col, ScaleI(Header.Height)), Point(X, Y)) then
  begin
    ShowColumnFilterDropDown(hit.Col);
    Exit;
  end;
  if (hit.Part = ghpHeader) and (hit.Col >= 0)
     and (hoHeaderClickAutoSort in Header.Options) then
  begin
    { Shift+点 = **追加**次级排序列(先按 A 排、A 相同再按 B 排),
      普通点 = 重置成单列排序。与文件管理器/Excel 一致。 }
    if ssShift in Shift then
    begin
      if SortDirectionOf(hit.Col) = sdAscending then
        AddSortColumn(hit.Col, sdDescending)
      else
        AddSortColumn(hit.Col, sdAscending);
    end
    else
      ToggleSortColumn(hit.Col);
    Exit;
  end;
  if hit.Part = ghpCell then
  begin
    { 否决要在**任何副作用之前** —— 只挡住 OnClickCell 而让光标照样跑,
      对宿主来说等于没挡住。 }
    if not CanClickCell(hit.Col, hit.Row) then Exit;

    { 按钮格:点在按钮上就进按下态,松开时才算触发(与真按钮一致)。 }
    if (CellDisplayFor(hit.Col, hit.Row) = gcdButton)
       and PtInRect(CellButtonRect(hit.Col, hit.Row), Point(X, Y)) then
    begin
      SetPressedButton(hit.Col, hit.Row);
      Invalidate;
    end;

    { 无头环境(无窗口句柄)下 SetFocus 会抛异常 —— 句柄没落地就别抢焦点。 }
    if HandleAllocated and CanFocus then SetFocus;

    { Ctrl+点 = 把当前这块**固化**下来,再从新格开一块 —— 这就是离散多选。
      Shift+点 = 从原锚点拉到这里;普通点 = 清掉离散区并把锚点收到当前格。

      固化必须在 **MoveCursor 之前**:光标是活动矩形的另一个角,先挪光标的话
      固化下来的是已经被拉长的那一块(Ctrl+点第 4 行会把 1..4 整段吞进去)。 }
    if ssCtrl in Shift then
      CommitActiveSelection
    else if not (ssShift in Shift) then
      SetLength(FSelRects, 0);

    MoveCursor(hit.Col, hit.Row);
    if not (ssShift in Shift) then AnchorSelection;
    SelectionChanged;
    { 勾选框:点在方块上就切换。命中用的是绘制同一个槽,所以点哪切哪。 }
    if (EditorKindFor(hit.Col, hit.Row) = gekCheckBox)
       and PtInRect(CheckBoxRect(hit.Col, hit.Row), Point(X, Y)) then
      ToggleCellChecked(hit.Col, hit.Row);

    { 星级:点第几颗星就是几分。命中同样走绘制那套矩形。 }
    if EditorKindFor(hit.Col, hit.Row) = gekRating then
      SetRatingByPoint(hit.Col, hit.Row, X, Y);

    { 省略号按钮:点它就把控制权交给宿主(弹什么对话框是宿主的事)。
      点格的其它地方仍然是普通行内编辑。 }
    if (EditorKindFor(hit.Col, hit.Row) = gekEllipsis)
       and PtInRect(EllipsisRect(hit.Col, hit.Row), Point(X, Y)) then
    begin
      InvokeEllipsis(hit.Col, hit.Row);
      Exit;
    end;

    if Assigned(OnClickCell) then OnClickCell(Self, hit.Col, hit.Row);
  end;
end;


procedure TTyStringGrid.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  bc, br: Integer;
  hit: TTyGridHit;
begin
  GetPressedButton(bc, br);
  if (Button = mbLeft) and (bc >= 0) then
  begin
    SetPressedButton(-1, -1);
    Invalidate;
    { 只有"按下与松开落在同一个按钮上"才算一次点击 —— 按下后拖走再松开应当作废。 }
    hit := CellAt(X, Y);
    if (hit.Part = ghpCell) and (hit.Col = bc) and (hit.Row = br)
       and PtInRect(CellButtonRect(bc, br), Point(X, Y)) then
      if Assigned(OnCellButtonClick) then OnCellButtonClick(Self, bc, br);
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

function TTyStringGrid.EditorMinFor(ACol: Integer): Integer;
var c: TTyGridColumn;
begin
  c := GridColumn(ACol);
  if c <> nil then Result := c.MinValue else Result := 0;
end;

function TTyStringGrid.EditorMaxFor(ACol: Integer): Integer;
var c: TTyGridColumn;
begin
  c := GridColumn(ACol);
  if c <> nil then Result := c.MaxValue else Result := 100;
end;

function TTyStringGrid.EditMaskFor(ACol: Integer): string;
var c: TTyGridColumn;
begin
  Result := '';
  c := GridColumn(ACol);
  if c <> nil then Result := c.EditMask;
end;

function TTyStringGrid.CharCaseFor(ACol: Integer): TEditCharCase;
var c: TTyGridColumn;
begin
  Result := ecNormal;
  c := GridColumn(ACol);
  if c <> nil then Result := c.CharCase;
end;

function TTyStringGrid.ValidCharsFor(ACol, ARow: Integer): string;
var
  c: TTyGridColumn;
begin
  Result := '';
  c := GridColumn(ACol);
  if c <> nil then Result := c.ValidChars;
  { 数值列即使没显式配 ValidChars,也不该让人敲进字母。 }
  if (Result = '') and (EditorKindFor(ACol, ARow) = gekNumeric) then
    Result := '0123456789+-.,eE';
end;

function TTyStringGrid.MaxEditLengthFor(ACol, ARow: Integer): Integer;
var
  c: TTyGridColumn;
begin
  Result := 0;
  c := GridColumn(ACol);
  if c <> nil then Result := c.MaxEditLength;
end;

procedure TTyStringGrid.KeyPress(var Key: Char);
var
  vc: string;
begin
  inherited KeyPress(Key);
  if not Enabled then Exit;
  if FEditing then Exit;              { 编辑器自己收键 }
  if Key < #32 then Exit;             { 控制字符不算录入 }
  if EditorKindFor(FCol, FRow) in [gekNone, gekCheckBox] then Exit;

  { 按键级过滤:非法字符连编辑都不进,而不是等提交时再退回 ——
    "敲进去了又被弹回来"比"根本敲不进去"更让人困惑。 }
  vc := ValidCharsFor(FCol, FRow);
  if (vc <> '') and (Pos(Key, vc) = 0) then
  begin
    Key := #0;
    Exit;
  end;

  if not BeginEdit then Exit;
  { 这一笔就是新内容的第一个字符 —— 覆盖原值,与 Excel 一致。 }
  if FEditor.Visible then
  begin
    FEditor.Text := Key;
    FEditor.MaxLength := MaxEditLengthFor(FCol, FRow);
    FEditor.SelStart := 1;
  end;
  Key := #0;
end;

procedure TTyStringGrid.KeyDown(var Key: Word; Shift: TShiftState);
var
  navKey: Word;
begin
  { Key 会在下面被置 0(表示已消费),所以想知道"按的是哪个键"必须先存一份。 }
  navKey := Key;
  inherited KeyDown(Key, Shift);
  if not Enabled then Exit;

  case Key of
    VK_LEFT:  begin MoveCursor(FCol - 1, FRow); Key := 0; end;
    VK_RIGHT: begin MoveCursor(FCol + 1, FRow); Key := 0; end;
    VK_UP:    begin MoveCursor(FCol, FRow - 1); Key := 0; end;
    VK_DOWN:  begin MoveCursor(FCol, FRow + 1); Key := 0; end;
    VK_HOME:  begin MoveCursor(FirstVisibleCol, FRow); Key := 0; end;
    VK_END:   begin MoveCursor(LastVisibleCol, FRow); Key := 0; end;
    VK_PRIOR: begin MoveCursor(FCol, FRow - 10); Key := 0; end;
    VK_NEXT:  begin MoveCursor(FCol, FRow + 10); Key := 0; end;
    VK_F2:    begin BeginEdit; Key := 0; end;
    { Enter = 提交并**向下推进一格**。表格录入是一列一列往下敲的,
      停在原地会让用户每敲一格都得再按一次方向键。 }
    VK_RETURN: begin
                 if FEditing then EndEdit(True);
                 MoveCursor(FCol, FRow + 1);
                 Key := 0;
               end;
    { Tab = 按**格**推进,到行尾折到下一行行首。
      不拦的话 Tab 会把焦点整个弹出网格 —— 表格里这是最让人措手不及的一下。 }
    VK_TAB:   begin
                if FEditing then EndEdit(True);
                { 折行时也要落在**可见**列上,别折到一个隐藏列里去。 }
                if ssShift in Shift then
                begin
                  if FCol > FirstVisibleCol then MoveCursor(FCol - 1, FRow)
                  else if FRow > 0 then MoveCursor(LastVisibleCol, FRow - 1);
                end
                else
                begin
                  if FCol < LastVisibleCol then MoveCursor(FCol + 1, FRow)
                  else if FRow < RowCount - 1 then MoveCursor(FirstVisibleCol, FRow + 1);
                end;
                Key := 0;
              end;
    VK_SPACE: if EditorKindFor(FCol, FRow) = gekCheckBox then
              begin ToggleCellChecked(FCol, FRow); Key := 0; end;
    Ord('C'): if ssCtrl in Shift then begin CopySelectionToClipboard; Key := 0; end;
    Ord('V'): if ssCtrl in Shift then begin PasteFromClipboard; Key := 0; end;
    Ord('A'): if ssCtrl in Shift then
              begin
                { **走 SelectAll,不要在这里内联抄一遍。**
                  从前这里是抄的,于是漏了两件事:不清离散选区(Ctrl+点出来的块
                  会残留)、不发 OnSelectionChanged。同一个动作两条不等价的实现,
                  是最难查的一类不一致。 }
                SelectAll;
                Key := 0;
              end;
  end;
  { 普通**导航键**把锚点收到新位置(选区退化成一格);按住 Shift 则保留锚点,拉出区域。

    只对导航键做这件事。从前是"只要这一键被消费掉就收锚点",于是 Ctrl+A
    刚把选区拉满、立刻又被这句收回成一格 —— 全选表面上完全没反应。
    Ctrl+C/V 同理不该动选区。 }
  if (Key = 0) and not (ssShift in Shift) and (navKey in [VK_LEFT, VK_RIGHT,
     VK_UP, VK_DOWN, VK_HOME, VK_END, VK_PRIOR, VK_NEXT]) then
    AnchorSelection;
end;



{ ---- 行序间接层与排序 ---- }

procedure TTyStringGrid.ResetOrder;
begin
  SetLength(FOrder, 0);
  SetLength(FRank, 0);
  FOrderValid := False;
end;

procedure TTyStringGrid.InvalidateOrder;
begin
  { 批量期间不重建 —— EndUpdateOrder 里统一来一次。 }
  if FUpdatingOrder > 0 then
  begin
    FOrderValid := False;
    FRowTopsValid := False;
    Exit;
  end;
  FOrderValid := False;
  FRowTopsValid := False;    { 显示序变了 → 行高前缀和也失效 }
end;

procedure TTyStringGrid.InvalidateGridOrder;
begin
  InvalidateOrder;
end;

procedure TTyStringGrid.HideRow(ARow: Integer);
begin
  if (ARow < 0) or (ARow >= RowCount) then Exit;
  if FHiddenRows.IndexOf(IntToStr(ARow)) >= 0 then Exit;
  FHiddenRows.Add(IntToStr(ARow));
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.UnHideRow(ARow: Integer);
var
  i: Integer;
begin
  i := FHiddenRows.IndexOf(IntToStr(ARow));
  if i < 0 then Exit;
  FHiddenRows.Delete(i);
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

function TTyStringGrid.IsHiddenRow(ARow: Integer): Boolean;
begin
  Result := FHiddenRows.IndexOf(IntToStr(ARow)) >= 0;
end;

function TTyStringGrid.NumHiddenRows: Integer;
begin
  Result := FHiddenRows.Count;
end;

procedure TTyStringGrid.UnHideAllRows;
begin
  if FHiddenRows.Count = 0 then Exit;
  FHiddenRows.Clear;
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

function TTyStringGrid.RowPassesFilter(ARow: Integer): Boolean;
var
  i, colIdx: Integer;
  flt, vals: string;
begin
  Result := True;
  { 列过滤:所有设了过滤的列都要匹配(AND 关系)。 }
  for i := 0 to FColFilters.Count - 1 do
  begin
    flt := FColFilters.ValueFromIndex[i];
    if flt = '' then Continue;
    colIdx := StrToIntDef(FColFilters.Names[i], -1);
    if colIdx < 0 then Continue;
    if not TyGridFilterMatches(GetCellText(colIdx, ARow), flt) then
    begin
      Result := False;
      Exit;
    end;
  end;
  { 值集合过滤(列头下拉勾的那些)—— 与文本过滤 AND。 }
  for i := 0 to FValFilters.Count - 1 do
  begin
    colIdx := StrToIntDef(FValFilters.Names[i], -1);
    if colIdx < 0 then Continue;
    vals := FValFilters.ValueFromIndex[i];
    if vals = '' then Continue;
    { vals 两头本来就带分隔符,这里不用再补。 }
    if Pos('|^|' + GetCellText(colIdx, ARow) + '|^|', vals) = 0 then
    begin
      Result := False;
      Exit;
    end;
  end;

  if Assigned(FOnFilterRow) then FOnFilterRow(Self, ARow, Result);
  { 显式隐藏压过一切 —— 它是用户的直接动作,不是条件。
    放在最后,连 OnFilterRow 说"要"也盖不过去。 }
  if Result and IsHiddenRow(ARow) then Result := False;
end;

procedure TTyStringGrid.RebuildOrder;
var
  i, n: Integer;
  keys: TTyGridSortKeys;
begin
  SetLength(FOrder, RowCount);
  SetLength(FRank, RowCount);
  for i := 0 to RowCount - 1 do FRank[i] := -1;   { 默认"不显示" }

  n := 0;
  for i := 0 to RowCount - 1 do
    if RowPassesFilter(i) then
    begin
      FOrder[n] := i;
      Inc(n);
    end;
  SetLength(FOrder, n);

  { 一次排完:分组列(如果有)在前,用户的排序键在后。
    从前是"先按 FSortCol 排一遍,BuildGroups 里再按分组列排一遍" ——
    第二遍会把第一遍的结果整个盖掉,用户的排序列就这么没了。 }
  keys := EffectiveSortKeys;
  if Length(keys) > 0 then MergeSortOrderByKeys(keys);

  { 分组:在排好序的显示序上,按分组列的值切段并插入合成分组行。
    必须在排序**之后** —— 否则同组的行不相邻,切不出段。 }
  if FGroupCol >= 0 then
    BuildGroups;

  for i := 0 to High(FOrder) do
    if FOrder[i] >= 0 then FRank[FOrder[i]] := i;

  FOrderValid := True;
end;

procedure TTyStringGrid.BuildGroups;
var
  i, n, g: Integer;
  key, prevKey: string;
  src, dst: array of Integer;
  collapsed: Boolean;
begin
  SetLength(FGroups, 0);
  if Length(FOrder) = 0 then Exit;

  { 这里**不再排序**。分组列已经由 EnsureOrder 通过 EffectiveSortKeys 排在最前面了,
    同值的行必然相邻。从前这里 `FSortCol := FGroupCol` 是个真 bug ——
    它把用户选的排序列永久抹掉,而且是静默的。 }

  src := FOrder;
  SetLength(dst, 0);
  n := 0;
  g := -1;
  prevKey := #1'no-group'#1;      { 不可能与真实值相等 }

  for i := 0 to High(src) do
  begin
    key := GetCellText(FGroupCol, src[i]);
    if key <> prevKey then
    begin
      { 开新组:先插一行合成的分组行。 }
      Inc(g);
      SetLength(FGroups, g + 1);
      FGroups[g].Key := key;
      FGroups[g].Count := 0;
      FGroups[g].Collapsed := FCollapsed.IndexOf(key) >= 0;
      SetLength(dst, n + 1);
      dst[n] := -(g + 1);         { 负数 = 分组行 }
      Inc(n);
      prevKey := key;
    end;
    Inc(FGroups[g].Count);
    SetLength(FGroups[g].Rows, FGroups[g].Count);
    FGroups[g].Rows[FGroups[g].Count - 1] := src[i];
    { 折叠的组只留分组行,组内行不进显示序。 }
    if not FGroups[g].Collapsed then
    begin
      SetLength(dst, n + 1);
      dst[n] := src[i];
      Inc(n);
    end;
  end;

  FOrder := dst;
end;

procedure TTyStringGrid.EnsureOrder;
begin
  if FOrderValid and (Length(FRank) = RowCount) then Exit;
  RebuildOrder;
end;

function TTyStringGrid.DisplayToData(APos: Integer): Integer;
begin
  EnsureOrder;
  if (APos >= 0) and (APos < Length(FOrder)) then
    Result := FOrder[APos]
  else
    Result := -1;
end;

function TTyStringGrid.DataToDisplay(ARow: Integer): Integer;
begin
  EnsureOrder;
  if (ARow >= 0) and (ARow < Length(FRank)) then
    Result := FRank[ARow]      { 被过滤掉的行是 -1 }
  else
    Result := -1;
end;

function TTyStringGrid.DisplayRowCount: Integer;
begin
  EnsureOrder;
  Result := Length(FOrder);
end;

function TTyStringGrid.VisibleRowCount: Integer;
begin
  Result := DisplayRowCount;
end;

procedure TTyStringGrid.SetColumnFilterEx(ACol: Integer; AOp: TTyGridFilterOp;
  const AText: string);
begin
  SetColumnFilter(ACol, TyGridEncodeFilter(AOp, AText));
end;

function TTyStringGrid.ColumnFilterOp(ACol: Integer): TTyGridFilterOp;
var
  txt: string;
begin
  TyGridDecodeFilter(FColFilters.Values[IntToStr(ACol)], Result, txt);
end;

function TTyStringGrid.ColumnIsFiltered(ACol: Integer): Boolean;
var
  op: TTyGridFilterOp;
  txt: string;
begin
  TyGridDecodeFilter(FColFilters.Values[IntToStr(ACol)], op, txt);
  Result := txt <> '';
  if not Result then Result := FValFilters.Values[IntToStr(ACol)] <> '';
end;

function TTyStringGrid.FilteredRowCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to RowCount - 1 do
    if RowPassesFilter(i) then Inc(Result);
end;

procedure TTyStringGrid.SetColumnFilter(ACol: Integer; const AText: string);
var
  k: string;
  i: Integer;
begin
  k := IntToStr(ACol);
  i := FColFilters.IndexOfName(k);
  if i >= 0 then FColFilters.Delete(i);
  if AText <> '' then FColFilters.Add(k + '=' + AText);
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

function TTyStringGrid.ColumnFilter(ACol: Integer): string;
begin
  Result := FColFilters.Values[IntToStr(ACol)];
end;

procedure TTyStringGrid.SetColumnValueFilter(ACol: Integer; AValues: TStrings);
var
  k, joined: string;
  i: Integer;
begin
  k := IntToStr(ACol);
  i := FValFilters.IndexOfName(k);
  if i >= 0 then FValFilters.Delete(i);
  if (AValues <> nil) and (AValues.Count > 0) then
  begin
    { 值里可能带各种字符,用 |^| 当分隔(实际数据里不会出现)。

      **两头也带上分隔符**,而不是 Trim(AValues.Text) 那样只在中间放。
      因为"只勾了空白值"是一个合法的过滤(下拉里就有「(空白)」这一项),
      而它 Trim 完是空串,会被下游当成"这列没有过滤" —— 于是勾了等于没勾。
      两头都带的话,只勾空白得到的是 '|^||^|',非空,语义就保住了。 }
    joined := '|^|';
    for i := 0 to AValues.Count - 1 do
      joined := joined + AValues.Strings[i] + '|^|';
    FValFilters.Add(k + '=' + joined);
  end;
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.ColumnValueFilter(ACol: Integer; AOut: TStrings);
var
  v: string;
  i: Integer;
  parts: TStringList;
begin
  AOut.Clear;
  v := FValFilters.Values[IntToStr(ACol)];
  if v = '' then Exit;
  { 按分隔符切开,丢掉**首尾**那两个片段 —— 它们是两头哨兵造出来的空串。
    不能用"掐掉两头再整体替换":那样"只有一个空值"会塌成空串,读回来变成
    零个条目,而正确答案是一个空条目。
      '|^|a|^|b|^|' -> ['', 'a', 'b', '']  -> ['a','b']
      '|^||^|'      -> ['', '', '']        -> ['']      }
  parts := TStringList.Create;
  try
    parts.Text := StringReplace(v, '|^|', LineEnding, [rfReplaceAll]);
    { TStringList.Text 会吃掉末尾那个空行,所以只丢首片段、末片段按需补。 }
    if parts.Count > 0 then parts.Delete(0);
    for i := 0 to parts.Count - 1 do AOut.Add(parts[i]);
    if (parts.Count = 0) and (v <> '') then AOut.Add('');
  finally
    parts.Free;
  end;
end;

procedure TTyStringGrid.ClearFilters;
begin
  if (FColFilters.Count = 0) and (FValFilters.Count = 0) then Exit;
  FColFilters.Clear;
  FValFilters.Clear;
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

function TTyStringGrid.CompareRows(ACol, ARow1, ARow2: Integer): Integer;
var
  a, b: string;
  fa, fb: Double;
  da, db: TDateTime;
  kind: TTyGridSortKind;
begin
  Result := 0;
  if Assigned(FOnCompareCells) then
  begin
    FOnCompareCells(Self, ACol, ARow1, ARow2, Result);
    if Result <> 0 then Exit;
  end;
  a := GetCellText(ACol, ARow1);
  b := GetCellText(ACol, ARow2);

  { 排序方式**跟着列走**;列没配(gskAuto)才回落到网格的 SortKind。
    混合表里日期列按文本排会得到 '10/1' < '2/1' —— 这本来就该是列的属性,
    而不是全表一个开关。 }
  kind := FSortKind;
  if (GridColumn(ACol) <> nil) and (GridColumn(ACol).SortKind <> gskAuto) then
    kind := GridColumn(ACol).SortKind;

  if kind = gskDate then
  begin
    { 空/非法排最后,且与升降序无关 —— 与数值那条一致。 }
    da := StrToDateTimeDef(a, NoDateSentinel);
    db := StrToDateTimeDef(b, NoDateSentinel);
    if (da = NoDateSentinel) and (db = NoDateSentinel) then Result := 0
    else if da = NoDateSentinel then Result := 1
    else if db = NoDateSentinel then Result := -1
    else if da < db then Result := -1
    else if da > db then Result := 1
    else Result := 0;
    Exit;
  end;

  { 空值的位置**与升降序无关** —— 由 BlanksPosition 单独决定。
    (若参与正常比较,一翻向空行就会整块冒到最上面。) }
  if (a = '') or (b = '') then
  begin
    if (a = '') and (b = '') then Exit(0);
    if FBlanksPosition = gbpLast then
    begin
      if a = '' then Exit(1) else Exit(-1);
    end
    else
    begin
      if a = '' then Exit(-1) else Exit(1);
    end;
  end;

  if kind = gskNumber then
  begin
    { 数值列必须按数值比 —— 按文本比会得到 '10' < '9'。
      空/非法值一律排在最后,且**与升降序无关**(否则一翻向,空行就冒到最上面)。 }
    fa := StrToFloatDef(a, NaN);
    fb := StrToFloatDef(b, NaN);
    if IsNan(fa) and IsNan(fb) then Result := 0
    else if IsNan(fa) then Result := 1
    else if IsNan(fb) then Result := -1
    else if fa < fb then Result := -1
    else if fa > fb then Result := 1
    else Result := 0;
    Exit;
  end;
  { 从前写死 CompareText —— 恒不区分大小写,想按 ASCII 序排根本做不到。 }
  if FSortIgnoreCase then Result := CompareText(a, b)
  else Result := CompareStr(a, b);
end;

{ 按一串键比:前面的相等才看后面的。单键是它的退化情形。 }
{ 空值/非法数值的胜负**与升降序无关** —— 返回 True 表示这一对已经由位置规则定了,
  调用方**不许再翻方向**。

  这件事必须在这一层做:方向翻转发生在 CompareRows **之后**,
  把规则写在 CompareRows 里的话,一翻向空行就整块冒到最上面。 }
function TTyStringGrid.BlankVerdict(ACol, ARow1, ARow2: Integer;
  out ACmp: Integer): Boolean;
var
  a, b: string;
  kind: TTyGridSortKind;
  blankA, blankB: Boolean;
  va, vb: Double;
begin
  ACmp := 0;
  a := GetCellText(ACol, ARow1);
  b := GetCellText(ACol, ARow2);

  kind := FSortKind;
  if (GridColumn(ACol) <> nil) and (GridColumn(ACol).SortKind <> gskAuto) then
    kind := GridColumn(ACol).SortKind;

  blankA := Trim(a) = '';
  blankB := Trim(b) = '';
  { 数值/日期列里"解析不出来"与"空"同等对待 —— 都属于"没有可比的值"。 }
  if kind = gskNumber then
  begin
    va := StrToFloatDef(Trim(a), NaN);
    vb := StrToFloatDef(Trim(b), NaN);
    blankA := blankA or IsNan(va);
    blankB := blankB or IsNan(vb);
  end
  else if kind = gskDate then
  begin
    blankA := blankA or (StrToDateTimeDef(a, NoDateSentinel) = NoDateSentinel);
    blankB := blankB or (StrToDateTimeDef(b, NoDateSentinel) = NoDateSentinel);
  end;

  Result := blankA or blankB;
  if not Result then Exit;
  if blankA and blankB then Exit;      { 都空 → 平手,交给下一个键 }

  if FBlanksPosition = gbpLast then
  begin
    if blankA then ACmp := 1 else ACmp := -1;
  end
  else
  begin
    if blankA then ACmp := -1 else ACmp := 1;
  end;
end;

function TTyStringGrid.CompareRowsByKeys(const AKeys: TTyGridSortKeys;
  ARow1, ARow2: Integer): Integer;
var
  i, cmp: Integer;
begin
  Result := 0;
  for i := 0 to High(AKeys) do
  begin
    if AKeys[i].Col < 0 then Continue;

    { 空值先判,且**不翻方向**。 }

    if BlankVerdict(AKeys[i].Col, ARow1, ARow2, cmp) then
    begin
      if cmp <> 0 then Exit(cmp);
      Continue;                        { 都空 → 这一键分不出,看下一键 }
    end;

    Result := CompareRows(AKeys[i].Col, ARow1, ARow2);
    if AKeys[i].Dir = sdDescending then Result := -Result;
    if Result <> 0 then Exit;
  end;
end;

procedure TTyStringGrid.MergeSortOrder(ACol: Integer; ADirection: TTySortDirection);
var
  keys: TTyGridSortKeys;
begin
  { 单键 = 多键的退化情形。留着这个入口是因为库里已有一堆调用点。 }
  SetLength(keys, 1);
  keys[0].Col := ACol;
  keys[0].Dir := ADirection;
  MergeSortOrderByKeys(keys);
end;

procedure TTyStringGrid.MergeSortOrderByKeys(const AKeys: TTyGridSortKeys);
var
  buf: array of Integer;

  function Less(A, B: Integer): Integer;
  begin
    Result := CompareRowsByKeys(AKeys, A, B);
  end;

  procedure MergeRun(lo, mid, hi: Integer);
  var i, j, k: Integer;
  begin
    for k := lo to hi do buf[k] := FOrder[k];
    i := lo; j := mid + 1;
    for k := lo to hi do
    begin
      if i > mid then          begin FOrder[k] := buf[j]; Inc(j); end
      else if j > hi then      begin FOrder[k] := buf[i]; Inc(i); end
      { <=0 取左边 —— 这一步就是"稳定"的全部来源:等值时左边(原序靠前)先出。 }
      else if Less(buf[i], buf[j]) <= 0 then begin FOrder[k] := buf[i]; Inc(i); end
      else                     begin FOrder[k] := buf[j]; Inc(j); end;
    end;
  end;

  procedure SortRun(lo, hi: Integer);
  var mid: Integer;
  begin
    if lo >= hi then Exit;
    mid := lo + (hi - lo) div 2;
    SortRun(lo, mid);
    SortRun(mid + 1, hi);
    if Less(FOrder[mid], FOrder[mid + 1]) <= 0 then Exit;   { 已有序,省一次归并 }
    MergeRun(lo, mid, hi);
  end;

begin
  if Length(FOrder) < 2 then Exit;
  SetLength(buf, Length(FOrder));
  SortRun(0, High(FOrder));
end;





function TTyStringGrid.RowHeightOf(ARow: Integer): Integer;
begin
  { 优先级:**显式存储 > 回调 > 默认**。
    显式的最高,是因为它来自用户的直接动作(拖分隔线 / AutoFitRow),
    而回调是宿主给的通用规则 —— 直接动作压过通用规则。 }
  Result := RowHeights[ARow];
  if Result > 0 then Exit;

  Result := DefaultRowHeight;
  if Assigned(FOnGetRowHeight) then FOnGetRowHeight(Self, ARow, Result);
  if Result < 1 then Result := 1;
end;

procedure TTyStringGrid.InvalidateRowMetrics;
begin
  FRowTopsValid := False;
end;

function TTyStringGrid.RowTops: TTyIntArray;
var
  pos, n, acc, dataRow: Integer;
begin
  { 既没有回调、也没有任何显式行高 = 全表等高 —— 返回空数组,几何层走整除快路径,
    百万行时省下一个百万项的数组。**显式行高也要算进来**,否则拖出来的行高
    在几何层根本不生效(只改了存储、行还是老样子)。 }
  if not Assigned(FOnGetRowHeight) and not HasExplicitRowHeights then Exit(nil);

  n := DisplayRowCount;
  if FRowTopsValid and (Length(FRowTopsCache) = n + 1) then Exit(FRowTopsCache);

  SetLength(FRowTopsCache, n + 1);
  acc := 0;
  for pos := 0 to n - 1 do
  begin
    FRowTopsCache[pos] := acc;
    dataRow := DisplayToData(pos);
    { 分组行(dataRow < 0)按默认行高;它不是数据行,问宿主要行高没有意义。 }
    if dataRow >= 0 then
      Inc(acc, ScaleI(RowHeightOf(dataRow)))
    else
      Inc(acc, ScaleI(DefaultRowHeight));
  end;
  FRowTopsCache[n] := acc;
  FRowTopsValid := True;
  Result := FRowTopsCache;
end;

{ 色块:把 '#RRGGBB' 画成一小块颜色,而不是把那串字显示出来。
  解析不出颜色时什么都不画(留空格),不要退回去显示原文 ——
  那样一列里会混着色块和乱码,比统一留空更难看懂。 }
procedure TTyStringGrid.RenderColorCell(P: TTyPainter; ACol, ARow: Integer;
  const AFrame: TTyStyleSet);
var
  r, sw: TRect;
  c: TTyColor;
  txt: string;
  pad: Integer;
  fill: TTyFill;
begin
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  txt := Trim(GetCellText(ACol, ARow));
  if txt = '' then Exit;

  { 走与 gekColor 编辑器同一个解析器 —— 显示侧和编辑侧对"什么算颜色"必须同口径。 }
  c := TyParseColor(txt);

  pad := ScaleI(4);
  sw := Rect(r.Left + pad, r.Top + pad, r.Right - pad, r.Bottom - pad);
  if (sw.Right <= sw.Left) or (sw.Bottom <= sw.Top) then Exit;

  fill := Default(TTyFill);
  fill.Kind := tfkSolid;
  fill.Color := c;
  P.FillBackground(sw, fill, ScaleI(2));
  { 描一圈边,免得浅色块在浅色底上看不见边界。 }
  P.StrokeBorder(sw, ScaleI(2), 1, AFrame.BorderColor);
end;

procedure TTyStringGrid.RenderImageCell(P: TTyPainter; ACol, ARow: Integer;
  const AFrame: TTyStyleSet);
var
  r: TRect;
  idx, sz, cx, cy: Integer;
  bmp: TBGRABitmap;
begin
  if FImages = nil then Exit;
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  idx := StrToIntDef(Trim(GetCellText(ACol, ARow)), -1);
  if (idx < 0) or (idx >= FImages.Count) then Exit;

  sz := ScaleI(16);
  if sz > (r.Bottom - r.Top) - 2 then sz := (r.Bottom - r.Top) - 2;
  if sz > (r.Right - r.Left) - 2 then sz := (r.Right - r.Left) - 2;
  if sz <= 0 then Exit;
  cx := (r.Left + r.Right) div 2;
  cy := (r.Top + r.Bottom) div 2;
  { 从图像集的渲染缓存借位图 —— 不为每个图标单独分配与重采样(这是绘制热路径)。
    位图归缓存所有,不能释放。 }
  bmp := FImages.CachedIndex(idx, sz);
  if bmp <> nil then
    P.Bitmap.PutImage(cx - sz div 2, cy - sz div 2, bmp, dmDrawWithTransparency);
end;

{ ---- 单元格图形 ----------------------------------------------------------- }

function TTyStringGrid.CellDisplayOf(ACol, ARow: Integer): TTyGridCellDisplay;
begin
  Result := CellDisplayFor(ACol, ARow);
end;

function TTyStringGrid.IsActiveCell(ACol, ARow: Integer): Boolean;
begin
  Result := (ACol = FCol) and (ARow = FRow);
end;

function TTyStringGrid.FAttrs2Find(ACol, ARow: Integer): TTyGridCellAttr;
begin
  { 同上:逐格属性是稀疏的例外,常态不该为它建字符串。 }
  if FAttrs.IsEmpty then Exit(nil);
  Result := FAttrs.Find(CellKey(ACol, ARow));
end;

function TTyStringGrid.GetCellColor(ACol, ARow: Integer): TTyColor;
var a: TTyGridCellAttr;
begin
  Result := TyColorNone;
  a := FAttrs.Find(CellKey(ACol, ARow));
  if (a <> nil) and a.HasBackground then Result := a.Background;
end;

procedure TTyStringGrid.SetCellColor(ACol, ARow: Integer; AValue: TTyColor);
var
  k: string;
  a: TTyGridCellAttr;
begin
  k := CellKey(ACol, ARow);
  if AValue = TyColorNone then
  begin
    a := FAttrs.Find(k);
    if a = nil then Exit;
    a.HasBackground := False;
    FAttrs.DropIfDefault(k);
  end
  else
  begin
    a := FAttrs.Ensure(k);
    if a = nil then Exit;
    a.HasBackground := True;
    a.Background := AValue;
  end;
  Invalidate;
end;

function TTyStringGrid.GetCellTextColor(ACol, ARow: Integer): TTyColor;
var a: TTyGridCellAttr;
begin
  Result := TyColorNone;
  a := FAttrs.Find(CellKey(ACol, ARow));
  if (a <> nil) and a.HasTextColor then Result := a.TextColor;
end;

procedure TTyStringGrid.SetCellTextColor(ACol, ARow: Integer; AValue: TTyColor);
var
  k: string;
  a: TTyGridCellAttr;
begin
  k := CellKey(ACol, ARow);
  if AValue = TyColorNone then
  begin
    a := FAttrs.Find(k);
    if a = nil then Exit;
    a.HasTextColor := False;
    FAttrs.DropIfDefault(k);
  end
  else
  begin
    a := FAttrs.Ensure(k);
    if a = nil then Exit;
    a.HasTextColor := True;
    a.TextColor := AValue;
  end;
  Invalidate;
end;

procedure TTyStringGrid.SetRowColor(ARow: Integer; AColor: TTyColor);
var
  j: Integer;
begin
  if (ARow < 0) or (ARow >= RowCount) then Exit;
  for j := 0 to Header.Columns.Count - 1 do
    CellColors[j, ARow] := AColor;
end;

function TTyStringGrid.GetCellReadOnly(ACol, ARow: Integer): Boolean;
var a: TTyGridCellAttr;
begin
  Result := False;
  { 没有任何逐格属性时直接走人 —— 连 CellKey 那个临时字符串都别建。
    这条在渲染路径上每格都要走(EditorKindFor → ShouldDrawCellText)。 }
  if FAttrs.IsEmpty then Exit;
  a := FAttrs.Find(CellKey(ACol, ARow));
  if a <> nil then Result := a.ReadOnly;
end;

procedure TTyStringGrid.SetCellReadOnly(ACol, ARow: Integer; AValue: Boolean);
var
  k: string;
  a: TTyGridCellAttr;
begin
  k := CellKey(ACol, ARow);
  if not AValue then
  begin
    a := FAttrs.Find(k);
    if a = nil then Exit;
    a.ReadOnly := False;
    FAttrs.DropIfDefault(k);
  end
  else
  begin
    a := FAttrs.Ensure(k);
    if a = nil then Exit;
    a.ReadOnly := True;
  end;
end;

function TTyStringGrid.CellDisplayFor(ACol, ARow: Integer): TTyGridCellDisplay;
begin
  Result := FDefaultCellDisplay;
  if Assigned(FOnGetCellDisplay) then FOnGetCellDisplay(Self, ACol, ARow, Result);
end;

function TTyStringGrid.DoDrawCell(P: TTyPainter; ACol, ARow: Integer): Boolean;
var
  r: TRect;
begin
  Result := False;
  if not Assigned(FOnDrawCell) then Exit;
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  { 背景与选中底色已由控件铺好,宿主只需画自己那部分。 }
  FOnDrawCell(Self, ACol, ARow, r, P, Result);
end;

procedure TTyStringGrid.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  hit: TTyGridHit;
  txt: string;
begin
  inherited MouseMove(Shift, X, Y);
  if not Enabled then Exit;

  { 按住左键在格上移动 = 拖选。只挪光标、**不动锚点**,
    活动矩形因此从按下那一格一直拉到这里。
    放在 hint 那段之前:拖选期间不该再弹提示。 }
  if ssLeft in Shift then
  begin
    hit := CellAt(X, Y);
    if (hit.Part = ghpCell) and ((hit.Col <> FCol) or (hit.Row <> FRow)) then
    begin
      MoveCursor(hit.Col, hit.Row);
      SelectionChanged;
    end;
    Exit;
  end;

  if not Assigned(FOnGetCellHint) then Exit;

  hit := CellAt(X, Y);
  if hit.Part <> ghpCell then
  begin
    if (FHintCol <> -1) or (FHintRow <> -1) then
    begin
      FHintCol := -1;
      FHintRow := -1;
      Hint := '';
      ShowHint := False;
    end;
    Exit;
  end;

  { 只在**换格**时才问宿主 —— 否则鼠标每动一像素都要回调一次。 }
  if (hit.Col = FHintCol) and (hit.Row = FHintRow) then Exit;
  FHintCol := hit.Col;
  FHintRow := hit.Row;
  txt := '';
  FOnGetCellHint(Self, hit.Col, hit.Row, txt);
  Hint := txt;
  ShowHint := txt <> '';
end;

function TTyStringGrid.ShouldDrawCellText(ACol, ARow: Integer): Boolean;
begin
  Result := (EditorKindFor(ACol, ARow) <> gekCheckBox)
        and (CellDisplayFor(ACol, ARow) = gcdText);
end;

procedure TTyStringGrid.RenderProgressCell(P: TTyPainter; ACol, ARow: Integer;
  const AFrame: TTyStyleSet);
var
  r, bar, fill: TRect;
  pct: Double;
  trackS, fillS: TTyStyleSet;
begin
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  pct := StrToFloatDef(Trim(GetCellText(ACol, ARow)), NaN);
  if IsNan(pct) then Exit;
  if pct < 0 then pct := 0;
  if pct > 100 then pct := 100;

  bar := Rect(r.Left + ScaleI(4), r.Top + ScaleI(5),
              r.Right - ScaleI(4), r.Bottom - ScaleI(5));
  if bar.Right <= bar.Left then Exit;

  { 网格自己的 token。此前误写成 'TyProgressBarFill'(真实的键叫 TyProgressFill),
    于是填充**从来没画过** —— 进度条永远是空槽,改值也没动静。 }
  trackS := ActiveController.Model.ResolveStyle('TyGridProgress', StyleClass, []);
  fillS  := ActiveController.Model.ResolveStyle('TyGridProgressFill', StyleClass, []);
  if tpBackground in trackS.Present then
    P.FillBackground(bar, trackS.Background, TyEffectiveCorners(trackS));

  fill := bar;
  fill.Right := bar.Left + Round((bar.Right - bar.Left) * pct / 100);
  if fill.Right > fill.Left then
  begin
    { 填充色取 TyProgressBarFill;主题没定义就不画填充(优雅退化,不自己发明颜色)。 }
    if tpBackground in fillS.Present then
      P.FillBackground(fill, fillS.Background, TyEffectiveCorners(trackS));
  end;
end;

{ 第 AStar 颗星(1-based)的矩形。**绘制与命中共用它** ——
  两边各算一套的话,"点第 3 颗给出第 2 颗"这种错早晚会出现。 }
procedure TTyStringGrid.InvokeEllipsis(ACol, ARow: Integer);
var
  oldTxt, newTxt: string;
  accept: Boolean;
begin
  if not Assigned(FOnEllipsisClick) then Exit;
  if FReadOnly then Exit;
  EndEdit(True);
  oldTxt := GetCellText(ACol, ARow);
  newTxt := oldTxt;
  accept := True;
  FOnEllipsisClick(Self, ACol, ARow, newTxt, accept);
  if not accept then Exit;
  if newTxt = oldTxt then Exit;
  { 写回照常走 OnCellEdited —— 省略号只是换了个"值从哪来",
    不该绕过宿主已有的校验。 }
  accept := True;
  if Assigned(FOnCellEdited) then
    FOnCellEdited(Self, ACol, ARow, oldTxt, newTxt, accept);
  if accept then Cells[ACol, ARow] := newTxt;
end;

procedure TTyStringGrid.SetRatingByPoint(ACol, ARow, X, Y: Integer);
var
  i: Integer;
  oldTxt, newTxt: string;
  accept: Boolean;
begin
  if FReadOnly then Exit;
  for i := 1 to TyGridRatingMax do
    if PtInRect(RatingStarRect(ACol, ARow, i), Point(X, Y)) then
    begin
      oldTxt := GetCellText(ACol, ARow);
      newTxt := IntToStr(i);
      if newTxt = oldTxt then Exit;
      accept := True;
      if Assigned(FOnCellEdited) then
        FOnCellEdited(Self, ACol, ARow, oldTxt, newTxt, accept);
      if accept then
      begin
        Cells[ACol, ARow] := newTxt;
        if Assigned(FOnRatingChange) then FOnRatingChange(Self, ACol, ARow, i);
      end;
      Exit;
    end;
end;

function TTyStringGrid.RatingStarRect(ACol, ARow, AStar: Integer): TRect;
var
  r: TRect;
  box, cy, x0, i: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (AStar < 1) or (AStar > TyGridRatingMax) then Exit;
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;

  box := ScaleI(12);
  cy := (r.Top + r.Bottom) div 2;
  x0 := r.Left + ScaleI(4);
  i := AStar - 1;
  Result := Rect(x0 + i * (box + ScaleI(2)), cy - box div 2,
                 x0 + i * (box + ScaleI(2)) + box, cy - box div 2 + box);
  if Result.Right > r.Right then Result := Rect(0, 0, 0, 0);
end;

procedure TTyStringGrid.RenderRatingCell(P: TTyPainter; ACol, ARow: Integer;
  const AFrame: TTyStyleSet);
var
  r, star: TRect;
  n, i, box, cy, x0: Integer;
  ink, emptyInk: TTyColor;
  rS, eS: TTyStyleSet;
begin
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  { 空内容 / 非数值 → 0 分,仍然画 5 颗空星(那是可点的位置)。 }
  n := StrToIntDef(Trim(GetCellText(ACol, ARow)), 0);
  if n < 0 then n := 0;
  if n > TyGridRatingMax then n := TyGridRatingMax;

  rS := ActiveController.Model.ResolveStyle('TyGridRating', StyleClass, []);
  if tpTextColor in rS.Present then ink := rS.TextColor else ink := AFrame.TextColor;
  { 未评的那几颗用另一个键,主题里配成淡色 —— 只有把空星也画出来,
    用户才看得出"这里还能点到第 5 颗"。从前只画已评的 n 颗,
    等于把可点的位置藏起来了。 }
  eS := ActiveController.Model.ResolveStyle('TyGridRatingEmpty', StyleClass, []);
  if tpTextColor in eS.Present then emptyInk := eS.TextColor else emptyInk := ink;

  box := ScaleI(12);
  cy := (r.Top + r.Bottom) div 2;
  x0 := r.Left + ScaleI(4);
  for i := 0 to TyGridRatingMax - 1 do
  begin
    star := RatingStarRect(ACol, ARow, i + 1);
    if IsRectEmpty(star) then Break;
    { 实心 = 已评,空心 = 可点但未评。星形与评分控件共用 TTyPainter.StarPath。 }
    P.DrawStar(star, IfThen(i < n, ink, emptyInk), i < n);
  end;
end;

{ ---- 勾选框单元格 --------------------------------------------------------- }

function TTyStringGrid.CellChecked(ACol, ARow: Integer): Boolean;
var
  v: string;
begin
  { 宽松识别:从 CSV/外部系统进来的真值写法五花八门,读的时候都认。 }
  v := LowerCase(Trim(GetCellText(ACol, ARow)));
  Result := (v = '1') or (v = 'true') or (v = 'yes') or (v = 'y');
  { 再认一个本地化的真值写法(中文表里常见 '是')—— 空的本地化词不参与判定。 }
  if (not Result) and (TyGridCheckedWord <> '') then
    Result := v = LowerCase(TyGridCheckedWord);
end;

procedure TTyStringGrid.ToggleCellChecked(ACol, ARow: Integer);
var
  accept: Boolean;
  oldTxt, newTxt: string;
begin
  if FReadOnly then Exit;

  { 宿主可以否决这一次切换("已锁定的行不许改")。 }
  accept := True;
  if Assigned(FOnCanToggleCheck) then FOnCanToggleCheck(Self, ACol, ARow, accept);
  if not accept then Exit;

  oldTxt := GetCellText(ACol, ARow);
  { 写回统一成 '1'/'' —— 读的时候宽松,写的时候收敛。 }
  if CellChecked(ACol, ARow) then newTxt := '' else newTxt := '1';
  accept := True;
  if Assigned(FOnCellEdited) then
    FOnCellEdited(Self, ACol, ARow, oldTxt, newTxt, accept);
  if accept then
  begin
    Cells[ACol, ARow] := newTxt;
    { 切换成功了才通知 —— 让宿主不用自己再判一次有没有真的变。 }
    if Assigned(FOnCheckBoxChange) then
      FOnCheckBoxChange(Self, ACol, ARow, newTxt <> '');
  end;
end;

procedure TTyStringGrid.ToggleCellColor(ACol, ARow: Integer);
var
  c: TTyColor;
  accept: Boolean;
  oldTxt, newTxt: string;
begin
  if FReadOnly then Exit;
  oldTxt := GetCellText(ACol, ARow);
  if oldTxt <> '' then c := TyParseColor(oldTxt) else c := TyRGB(255, 255, 255);
  if not TySelectColor(rsGridPickColor, c) then Exit;
  newTxt := TyColorToHex(c, False);
  accept := True;
  if Assigned(FOnCellEdited) then
    FOnCellEdited(Self, ACol, ARow, oldTxt, newTxt, accept);
  if accept then Cells[ACol, ARow] := newTxt;
end;

{ 省略号按钮:贴在格的右缘,方形。与绘制同源 —— 画在哪就点在哪。 }
function TTyStringGrid.EllipsisRect(ACol, ARow: Integer): TRect;
var
  r: TRect;
  box: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if EditorKindFor(ACol, ARow) <> gekEllipsis then Exit;
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  box := (r.Bottom - r.Top) - ScaleI(4);
  if box > ScaleI(18) then box := ScaleI(18);
  if box <= 0 then Exit;
  if box > (r.Right - r.Left) - ScaleI(2) then Exit;
  Result := Rect(r.Right - box - ScaleI(2), (r.Top + r.Bottom - box) div 2,
                 r.Right - ScaleI(2), (r.Top + r.Bottom - box) div 2 + box);
end;

{ 画省略号按钮。样式走 TyGridButton(与按钮单元格同一个键 —— 它们在视觉上
  本来就该是同一种东西),点在上面的态由 FPressedBtn 记。 }
procedure TTyStringGrid.RenderEllipsisCell(P: TTyPainter; ACol, ARow: Integer;
  const AFrame: TTyStyleSet);
var
  r: TRect;
  st: TTyStateSet;
  bS: TTyStyleSet;
  ink: TTyColor;
  bc, br: Integer;
begin
  r := EllipsisRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;

  st := [];
  GetPressedButton(bc, br);
  if (ACol = bc) and (ARow = br) then Include(st, tysActive);

  bS := ActiveController.Model.ResolveStyle('TyGridButton', StyleClass, st);
  if tpBackground in bS.Present then
    P.FillBackground(r, bS.Background, TyEffectiveCorners(bS));
  if TyBorderVisible(bS) then
    P.StrokeBorder(r, TyEffectiveCorners(bS), bS.BorderWidth, bS.BorderColor);
  if tpTextColor in bS.Present then ink := bS.TextColor else ink := AFrame.TextColor;
  DrawCellText(P, r, '...', bS.FontName, ResolveFontSize(bS), bS.FontWeight,
    ink, taCenter, tlCenter);
end;

function TTyStringGrid.CheckBoxRect(ACol, ARow: Integer): TRect;
var
  r: TRect;
  box, cx, cy: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  box := ScaleI(14);
  if box > (r.Bottom - r.Top) - 2 then box := (r.Bottom - r.Top) - 2;
  if box > (r.Right - r.Left) - 2 then box := (r.Right - r.Left) - 2;
  if box <= 0 then Exit;
  cx := (r.Left + r.Right) div 2;
  cy := (r.Top + r.Bottom) div 2;
  Result := Rect(cx - box div 2, cy - box div 2, cx - box div 2 + box, cy - box div 2 + box);
end;

procedure TTyStringGrid.RenderCheckCell(P: TTyPainter; ACol, ARow: Integer;
  const AFrame: TTyStyleSet);
var
  box: TRect;
  boxS: TTyStyleSet;
  ink: TTyColor;
begin
  box := CheckBoxRect(ACol, ARow);
  if IsRectEmpty(box) then Exit;

  { 状态**只由该格自己勾没勾决定**,绝不掺入网格的 CurrentStates ——
    否则鼠标一按下网格进入 :active,满屏未勾选的框会集体闪成实心再变回去。
    （用自己的 typeKey,不借 TyCheckBox:借来的键在外观层够不着,改它还会波及复选框控件。） }
  if CellChecked(ACol, ARow) then
    boxS := ActiveController.Model.ResolveStyle('TyGridCheckBox', StyleClass, [tysSelected])
  else
    boxS := ActiveController.Model.ResolveStyle('TyGridCheckBox', StyleClass, []);

  if tpBackground in boxS.Present then
    P.FillBackground(box, boxS.Background, TyEffectiveCorners(boxS));
  if TyBorderVisible(boxS) then
    P.StrokeBorder(box, TyEffectiveCorners(boxS), boxS.BorderWidth, boxS.BorderColor);

  if CellChecked(ACol, ARow) then
  begin
    if tpTextColor in boxS.Present then ink := boxS.TextColor
    else ink := AFrame.TextColor;
    { 槽位式调用传 pad=1:默认每边内缩 4 逻辑像素,14px 的槽会只剩个糊点。 }
    TyDrawGlyph(P, ActiveController, box, tgCheck, ink, 1, 1);
  end;
end;




{ ---- 列头筛选下拉 --------------------------------------------------------- }

procedure TTyStringGrid.SetShowGroupSubtotals(AValue: Boolean);
begin
  if FShowGroupSubtotals = AValue then Exit;
  FShowGroupSubtotals := AValue;
  Invalidate;
end;

procedure TTyStringGrid.SetShowFilterButtons(AValue: Boolean);
begin
  if FShowFilterButtons = AValue then Exit;
  FShowFilterButtons := AValue;
  Invalidate;      { 直写字段的话,运行期开关筛选按钮不会重绘 }
end;

function TTyStringGrid.HasMergedCells: Boolean;
begin
  Result := FMergeCount > 0;
end;

function TTyStringGrid.SameMergedCell(ACol1, ARow1, ACol2, ARow2: Integer): Boolean;
var
  b1c, b1r, b2c, b2r, cs, rs: Integer;
begin
  Result := False;
  if FMergeCount = 0 then Exit;
  BaseCellOf(ACol1, ARow1, b1c, b1r);
  BaseCellOf(ACol2, ARow2, b2c, b2r);
  if (b1c <> b2c) or (b1r <> b2r) then Exit;
  { 归到同一个基准格还不够 —— 那个基准格得**真的**是合并的
    (不然两个格各自归到自己身上、坐标相同时会误判)。 }
  Result := CellSpan(b1c, b1r, cs, rs);
end;

function TTyStringGrid.ColumnFilterActive(ACol: Integer): Boolean;
begin
  Result := ColumnIsFiltered(ACol);
end;

function TTyStringGrid.SortRankOf(ACol: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FSortKeys) do
    if FSortKeys[i].Col = ACol then Exit(i + 1);   { 1-based:徽标上显示的就是它 }
end;

function TTyStringGrid.SortColumnCountOf: Integer;
begin
  Result := Length(FSortKeys);
end;

function TTyStringGrid.ShowsFilterButton(ACol: Integer): Boolean;
begin
  { 列头开了 hoColumnResize 之类无关;这里只看网格自己的开关。 }
  Result := FShowFilterButtons and (ACol >= 0) and (ACol < Header.Columns.Count);
end;

{ 候选值 + 每个值有多少行(计数放在 AItems.Objects 里)。

  和候选值一样按**全部数据行**算,不受本列自己的过滤影响 —— 否则勾掉一个值
  之后它的计数就变成 0,用户再也判断不出该不该勾回来。 }
procedure TTyStringGrid.DistinctColumnValueCounts(ACol: Integer; AItems: TStrings);
var
  i, idx: Integer;
  v: string;
  tally: TStringList;
begin
  AItems.Clear;
  tally := TStringList.Create;
  try
    tally.Sorted := True;
    tally.Duplicates := dupIgnore;
    for i := 0 to RowCount - 1 do
    begin
      v := GetCellText(ACol, i);
      idx := tally.IndexOf(v);
      if idx < 0 then tally.AddObject(v, TObject(PtrInt(1)))
      else tally.Objects[idx] := TObject(PtrInt(tally.Objects[idx]) + 1);
    end;
    for i := 0 to tally.Count - 1 do
      AItems.AddObject(tally[i], tally.Objects[i]);
  finally
    tally.Free;
  end;
end;

procedure TTyStringGrid.DistinctColumnValues(ACol: Integer; AItems: TStrings);
var
  i: Integer;
  seen: TStringList;
  v: string;
begin
  AItems.Clear;
  seen := TStringList.Create;
  try
    seen.Sorted := True;
    seen.Duplicates := dupIgnore;
    { 遍历**全部数据行**(不是显示序)—— 否则本列自己的过滤会把候选也筛没了,
      用户就再也选不回来。 }
    for i := 0 to RowCount - 1 do
    begin
      v := GetCellText(ACol, i);
      if seen.IndexOf(v) < 0 then seen.Add(v);
    end;
    AItems.Assign(seen);
  finally
    seen.Free;
  end;
end;

{ 关掉下拉时提交。**只有点了"确定"才算数** —— 取消、点空白处一律丢弃。
  从前是"一关就提交";加了取消按钮之后再那样,取消也会生效。 }
procedure TTyStringGrid.FilterPopupClosed(Sender: TObject);
var
  wasCol: Integer;                { 别叫 col/fcol —— 与 Col / FCol 撞名 }
begin
  wasCol := FFilterCol;
  FFilterCol := -1;               { 先清 —— 免得下面的失效链再绕回来 }
  if wasCol < 0 then Exit;
  if not FFilterAccepted then Exit;

  { 全勾 = 不过滤(而不是"逐值 OR 一遍")—— 语义更干净,也省一次全表扫描。
    注意比的是**全部候选值**,不是列表里当前显示的那几条:搜索把列表 narrow
    之后,"列表里都勾着"完全不等于"没有过滤"。 }
  if (FFilterChecked.Count = 0)
     or (FFilterChecked.Count = FFilterAllValues.Count) then
    SetColumnValueFilter(wasCol, nil)
  else
    SetColumnValueFilter(wasCol, FFilterChecked);
end;

{ 搜索框只 narrow 列表,不动勾选集合 —— 勾选是按**值**记的,
  所以"搜出来、勾上、清空搜索"之后,之前勾的还在。 }
procedure TTyStringGrid.FilterSearchChanged(Sender: TObject);
begin
  RebuildFilterList;
end;

procedure TTyStringGrid.FilterItemChecked(Sender: TObject);
var
  i, idx: Integer;
  v: string;
begin
  for i := 0 to FFilterList.Items.Count - 1 do
  begin
    v := FFilterList.Items.Strings[i];
    if v = rsGridFilterBlank then v := '';
    idx := FFilterChecked.IndexOf(v);
    if FFilterList.Checked[i] then
    begin
      if idx < 0 then FFilterChecked.Add(v);
    end
    else
      if idx >= 0 then FFilterChecked.Delete(idx);
  end;
  SyncFilterSelectAll;
end;

{ 「全选」作用于**当前列表里看得见的那些**(Excel 就是这样:搜出来一批,一键全勾)。
  看不见的值维持原状。 }
procedure TTyStringGrid.FilterSelectAllClick(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to FFilterList.Items.Count - 1 do
    FFilterList.Checked[i] := FFilterSelAll.Checked;
  FilterItemChecked(nil);
end;

procedure TTyStringGrid.FilterOkClick(Sender: TObject);
begin
  FFilterAccepted := True;
  FFilterPopup.Hide;
end;

procedure TTyStringGrid.FilterCancelClick(Sender: TObject);
begin
  FFilterAccepted := False;
  FFilterPopup.Hide;
end;

procedure TTyStringGrid.SyncFilterSelectAll;
var
  i, onCount: Integer;
begin
  onCount := 0;
  for i := 0 to FFilterList.Items.Count - 1 do
    if FFilterList.Checked[i] then Inc(onCount);
  FFilterSelAll.Checked := (FFilterList.Items.Count > 0)
                           and (onCount = FFilterList.Items.Count);
end;

{ 按搜索词重建列表。勾选状态从**值集合**回填,而不是从旧的列表下标 ——
  narrow 之后下标全变了,按下标回填会把勾打到别的值上。 }
procedure TTyStringGrid.RebuildFilterList;
var
  i, n: Integer;
  q, v, disp: string;
  counts: array of Integer;
begin
  q := LowerCase(Trim(FFilterSearch.Text));
  FFilterList.Items.BeginUpdate;
  try
    FFilterList.Items.Clear;
    SetLength(counts, FFilterAllValues.Count);
    n := 0;
    for i := 0 to FFilterAllValues.Count - 1 do
    begin
      v := FFilterAllValues.Strings[i];
      if (q <> '') and (Pos(q, LowerCase(v)) = 0) then Continue;
      { 空白值也得能选 —— 它是一个真实的取值,不是"没有值"。 }
      if v = '' then disp := rsGridFilterBlank else disp := v;
      FFilterList.Items.AddObject(disp,
        TObject(PtrInt(Ord(FFilterChecked.IndexOf(v) >= 0))));
      counts[n] := PtrInt(FFilterAllValues.Objects[i]);
      Inc(n);
    end;
    SetLength(counts, n);
    FFilterList.SetCounts(counts);
  finally
    FFilterList.Items.EndUpdate;
  end;
  SyncFilterSelectAll;
  FFilterList.Invalidate;
end;

procedure TTyStringGrid.ShowColumnFilterDropDown(ACol: Integer);
var
  i, pad, y, bh, sw: Integer;
  allowed: TStringList;
  scr: TRect;
  l, w: Integer;
begin
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  { 下拉开着时点了**别的列**的漏斗:先把上一列结束掉。否则 FFilterCol 会先被
    改成新列,旧列的勾选随后写到新列头上。 }
  if (FFilterCol >= 0) and (FFilterPopup <> nil) and FFilterPopup.Showing then
  begin
    FFilterAccepted := False;
    FFilterPopup.Hide;
  end;

  if FFilterPopup = nil then
  begin
    FFilterPopup := TTyPopover.Create(Self);
    { Popover.Content 只收**一个**控件,而且不按子控件自动定尺寸 ——
      所以自己摆一个固定尺寸的面板。 }
    FFilterPanel := TTyPanel.Create(FFilterPopup);
    FFilterPanel.Width := 232;
    FFilterPanel.Height := 306;

    FFilterSearch := TTyEdit.Create(FFilterPanel);
    FFilterSearch.Parent := FFilterPanel;
    FFilterSearch.TextHint := rsGridFilterSearchHint;
    FFilterSearch.OnChange := @FilterSearchChanged;

    FFilterSelAll := TTyCheckBox.Create(FFilterPanel);
    FFilterSelAll.Parent := FFilterPanel;
    FFilterSelAll.Caption := rsGridFilterSelectAll;
    FFilterSelAll.OnClick := @FilterSelectAllClick;

    FFilterList := TTyGridFilterList.Create(FFilterPanel);
    FFilterList.Parent := FFilterPanel;
    FFilterList.OnClickCheck := @FilterItemChecked;

    FFilterOk := TTyButton.Create(FFilterPanel);
    FFilterOk.Parent := FFilterPanel;
    FFilterOk.Caption := rsGridFilterOk;
    FFilterOk.OnClick := @FilterOkClick;

    FFilterCancel := TTyButton.Create(FFilterPanel);
    FFilterCancel.Parent := FFilterPanel;
    FFilterCancel.Caption := rsGridFilterCancel;
    FFilterCancel.OnClick := @FilterCancelClick;

    pad := 8;
    sw := FFilterPanel.Width - 2 * pad;
    bh := 26;
    y := pad;
    FFilterSearch.SetBounds(pad, y, sw, bh);   Inc(y, bh + 6);
    FFilterSelAll.SetBounds(pad, y, sw, 20);   Inc(y, 24);
    FFilterList.SetBounds(pad, y, sw, 200);    Inc(y, 208);
    FFilterOk.SetBounds(FFilterPanel.Width - pad - 2 * 68 - 6, y, 68, bh);
    FFilterCancel.SetBounds(FFilterPanel.Width - pad - 68, y, 68, bh);

    FFilterPopup.Content := FFilterPanel;
    FFilterPopup.OnHide := @FilterPopupClosed;
  end;
  FFilterPopup.Controller := Self.Controller;
  FFilterPanel.Controller := Self.Controller;
  FFilterSearch.Controller := Self.Controller;
  FFilterSelAll.Controller := Self.Controller;
  FFilterList.Controller := Self.Controller;
  FFilterOk.Controller := Self.Controller;
  FFilterCancel.Controller := Self.Controller;

  FFilterCol := ACol;
  FFilterAccepted := False;
  FFilterSearch.Text := '';
  DistinctColumnValueCounts(ACol, FFilterAllValues);

  { 已生效的值过滤回填成勾选;没有过滤则全勾。 }
  FFilterChecked.Clear;
  allowed := TStringList.Create;
  try
    ColumnValueFilter(ACol, allowed);
    for i := 0 to FFilterAllValues.Count - 1 do
      if (allowed.Count = 0)
         or (allowed.IndexOf(FFilterAllValues.Strings[i]) >= 0) then
        FFilterChecked.Add(FFilterAllValues.Strings[i]);
  finally
    allowed.Free;
  end;
  RebuildFilterList;

  { 锚在该列列头上。 }
  l := ColumnLeftPx(ACol);
  w := ColumnWidthPx(ACol);
  scr.TopLeft := ClientToScreen(Point(l, 0));
  scr.BottomRight := ClientToScreen(Point(l + w, ScaleI(Header.Height)));
  FFilterPopup.ShowAt(scr);
end;

procedure TTyGridFilterList.SetCounts(const ACounts: array of Integer);
var i: Integer;
begin
  SetLength(FCounts, Length(ACounts));
  for i := 0 to High(ACounts) do FCounts[i] := ACounts[i];
end;

procedure TTyGridFilterList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  cw: Integer;
  txt: string;
begin
  if (AIndex < 0) or (AIndex > High(FCounts)) then
  begin
    inherited PaintItemContent(P, ARowRect, AIndex, AStyle);
    Exit;
  end;
  txt := IntToStr(FCounts[AIndex]);
  cw := P.MeasureText(txt, AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight).cx + P.Scale(10);
  { 把行矩形右缘收窄再交给基类 —— 值文字(带省略号)自己就让出了计数那一条,
    勾选框在左缘不受影响。省得把基类那套勾选框绘制抄一遍。 }
  inherited PaintItemContent(P, Rect(ARowRect.Left, ARowRect.Top,
    ARowRect.Right - cw, ARowRect.Bottom), AIndex, AStyle);
  P.DrawText(Rect(ARowRect.Right - cw, ARowRect.Top,
    ARowRect.Right - P.Scale(4), ARowRect.Bottom),
    txt, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
    AStyle.TextColor, taRightJustify, tlCenter, False);
end;

{ ---- 行列增删 ------------------------------------------------------------- }

procedure TTyStringGrid.ShiftCells(AFromIndex, ADelta: Integer; ARows: Boolean);
type
  TCellPos = record C, R: Integer; end;
var
  attrKeys, merged: TStringList;
  order: array of TCellPos;
  n, i, c, r, sep: Integer;
  k: string;

  procedure MoveKey(AOldC, AOldR, ANewC, ANewR: Integer);
  var ov: string;
  begin
    ov := Cells[AOldC, AOldR];
    Cells[AOldC, AOldR] := '';
    Cells[ANewC, ANewR] := ov;
    { 属性(合并跨度等)必须**跟着文字一起搬** —— 从前只搬文字,
      于是在合并块上方插一行,内容跟着走了、合并框留在原地。 }
    FAttrs.MoveEntry(CellKey(AOldC, AOldR), CellKey(ANewC, ANewR));
  end;

  procedure DropCell(AC, AR: Integer);
  begin
    Cells[AC, AR] := '';
    FAttrs.Remove(CellKey(AC, AR));
  end;

  { 取被搬那条轴上的下标(排序键)。 }
  function AxisOf(const AP: TCellPos): Integer;
  begin
    if ARows then Result := AP.R else Result := AP.C;
  end;

  { 按被搬轴的下标**数值升序**排。
    从前这里是 TStringList.Sort —— 字典序。而键是 IntToStr 拼出来的无填充十进制,
    于是 "9" 排在 "10" 之后:增序搬时第 9 行会先搬进还没腾空的第 10 行,
    把第 10 行的数据**直接销毁**,第 10 行随后腾空成一条空行。
    行数 <= 10 的表看不出来 —— 整套增删测试当初就是这么假绿的。 }
  procedure SortByAxis(ALo, AHi: Integer);
  var lo, hi, pivot: Integer; t: TCellPos;
  begin
    if ALo >= AHi then Exit;
    lo := ALo; hi := AHi;
    pivot := AxisOf(order[(ALo + AHi) div 2]);
    repeat
      while AxisOf(order[lo]) < pivot do Inc(lo);
      while AxisOf(order[hi]) > pivot do Dec(hi);
      if lo <= hi then
      begin
        t := order[lo]; order[lo] := order[hi]; order[hi] := t;
        Inc(lo); Dec(hi);
      end;
    until lo > hi;
    SortByAxis(ALo, hi);
    SortByAxis(lo, AHi);
  end;

begin
  { 稀疏存储:只搬**写过的**格。先快照键表再改,避免边遍历边改。
    键取"有文字的格"与"有属性的格"的**并集** —— 只有合并、没有文字的格也得搬。 }
  attrKeys := TStringList.Create;
  try
    attrKeys.Sorted := False;
    attrKeys.Assign(FCellKeys);
    attrKeys.Sorted := True;      { 只为去重,**不**作为搬移顺序 }
    attrKeys.Duplicates := dupIgnore;
    merged := TStringList.Create;
    try
      FAttrs.SnapshotKeys(merged);
      for i := 0 to merged.Count - 1 do
        attrKeys.Add(merged[i]);
    finally
      merged.Free;
    end;

    n := attrKeys.Count;
    SetLength(order, n);
    for i := 0 to n - 1 do
    begin
      k := attrKeys[i];
      sep := Pos(':', k);
      order[i].C := StrToIntDef(Copy(k, 1, sep - 1), 0);
      order[i].R := StrToIntDef(Copy(k, sep + 1, MaxInt), 0);
    end;
  finally
    attrKeys.Free;
  end;

  if n > 1 then SortByAxis(0, n - 1);

  { 增(ADelta>0)时从大到小搬,否则会覆盖尚未搬走的格;删时从小到大。 }
  if ADelta > 0 then
    for i := n - 1 downto 0 do
    begin
      c := order[i].C; r := order[i].R;
      if ARows then
      begin
        if r >= AFromIndex then MoveKey(c, r, c, r + ADelta);
      end
      else
        if c >= AFromIndex then MoveKey(c, r, c + ADelta, r);
    end
  else
    for i := 0 to n - 1 do
    begin
      c := order[i].C; r := order[i].R;
      if ARows then
      begin
        if r = AFromIndex then DropCell(c, r)          { 被删那行的内容与属性 }
        else if r > AFromIndex then MoveKey(c, r, c, r + ADelta);
      end
      else
      begin
        if c = AFromIndex then DropCell(c, r)
        else if c > AFromIndex then MoveKey(c, r, c + ADelta, r);
      end;
    end;

  { 按下标存的**旁挂表**也得跟着数据走 —— 它们键的是行下标,而上面只搬了
    文字与格属性。不搬的话:行高粘在原下标上、落到另一行数据头上;
    隐藏标记同理,原来藏着的行冒出来、另一行凭空消失 —— 用户会读成"又多/少一行"。 }
  if ARows then
  begin
    ShiftRowKeyedTable(FRowHeights, AFromIndex, ADelta);
    ShiftRowKeyedTable(FHiddenRows, AFromIndex, ADelta);
    InvalidateOrder;
  end;
end;

{ 把"以行下标为键"的旁挂表整体平移。ADelta < 0 时,正落在 AFromIndex 上的那条被丢弃。
  就地改键会撞上重复键,所以整表重建。 }
procedure TTyCustomGrid.ShiftRowKeyedTable(AList: TStringList;
  AFromIndex, ADelta: Integer);
var
  i, r: Integer;
  rebuilt: TStringList;
  wasSorted: Boolean;
begin
  if (AList = nil) or (AList.Count = 0) or (ADelta = 0) then Exit;
  rebuilt := TStringList.Create;
  try
    for i := 0 to AList.Count - 1 do
    begin
      r := StrToIntDef(AList[i], -1);
      if r < 0 then Continue;
      if r >= AFromIndex then
      begin
        if (ADelta < 0) and (r = AFromIndex) then Continue;   { 被删的那一行 }
        Inc(r, ADelta);
        if r < 0 then Continue;
      end;
      rebuilt.AddObject(IntToStr(r), AList.Objects[i]);
    end;
    wasSorted := AList.Sorted;
    AList.Sorted := False;
    AList.Clear;
    for i := 0 to rebuilt.Count - 1 do
      AList.AddObject(rebuilt[i], rebuilt.Objects[i]);
    AList.Sorted := wasSorted;
  finally
    rebuilt.Free;
  end;
end;

procedure TTyStringGrid.BeginUpdateOrder;
begin
  Inc(FUpdatingOrder);
end;

procedure TTyStringGrid.EndUpdateOrder;
begin
  if FUpdatingOrder > 0 then Dec(FUpdatingOrder);
  if FUpdatingOrder = 0 then
  begin
    InvalidateOrder;
    UpdateScrollBars;
    Invalidate;
  end;
end;

procedure TTyStringGrid.InsertRows(ARow, ACount: Integer);
var
  i: Integer;
begin
  if ACount <= 0 then Exit;
  if (ARow < 0) or (ARow > RowCount) then Exit;
  EndEdit(True);
  BeginUpdateOrder;
  try
    { 从后往前搬 ACount 次,等价于一次搬 ACount ——
      ShiftCells 本身已经处理了方向,这里只是省掉每次的重排。 }
    for i := 1 to ACount do ShiftCells(ARow, 1, True);
    RowCount := RowCount + ACount;
  finally
    EndUpdateOrder;
  end;
end;

procedure TTyStringGrid.RemoveRows(ARow, ACount: Integer);
var
  i: Integer;
begin
  if ACount <= 0 then Exit;
  if (ARow < 0) or (ARow >= RowCount) then Exit;
  if ARow + ACount > RowCount then ACount := RowCount - ARow;
  EndEdit(True);
  BeginUpdateOrder;
  try
    for i := 1 to ACount do ShiftCells(ARow, -1, True);
    RowCount := RowCount - ACount;
  finally
    EndUpdateOrder;
  end;
end;

procedure TTyStringGrid.InsertCols(ACol, ACount: Integer);
var
  i: Integer;
begin
  if ACount <= 0 then Exit;
  BeginUpdateOrder;
  try
    for i := 1 to ACount do InsertColumn(ACol);
  finally
    EndUpdateOrder;
  end;
end;

procedure TTyStringGrid.RemoveCols(ACol, ACount: Integer);
var
  i: Integer;
begin
  if ACount <= 0 then Exit;
  BeginUpdateOrder;
  try
    for i := 1 to ACount do
    begin
      if ACol >= Header.Columns.Count then Break;
      DeleteColumn(ACol);
    end;
  finally
    EndUpdateOrder;
  end;
end;

procedure TTyStringGrid.SwapRows(ARow1, ARow2: Integer);
var
  j: Integer;
  tmp: string;
  a1, a2: TTyGridCellAttr;
  k1, k2: string;
begin
  if ARow1 = ARow2 then Exit;
  if (ARow1 < 0) or (ARow1 >= RowCount) then Exit;
  if (ARow2 < 0) or (ARow2 >= RowCount) then Exit;
  EndEdit(True);
  BeginUpdateOrder;
  try
    for j := 0 to Header.Columns.Count - 1 do
    begin
      tmp := Cells[j, ARow1];
      Cells[j, ARow1] := Cells[j, ARow2];
      Cells[j, ARow2] := tmp;
      { 属性也要跟着换 —— 只换文字的话合并区/底色会留在原地。 }
      k1 := CellKey(j, ARow1);
      k2 := CellKey(j, ARow2);
      a1 := FAttrs.Find(k1);
      a2 := FAttrs.Find(k2);
      if (a1 <> nil) or (a2 <> nil) then
      begin
        FAttrs.MoveEntry(k1, CellKey(j, -1));       { 借一个不可能的行号当中转 }
        FAttrs.MoveEntry(k2, k1);
        FAttrs.MoveEntry(CellKey(j, -1), k2);
      end;
    end;
    { 行高是行的属性,不是格的 —— 单独换。 }
    j := RowHeights[ARow1];
    RowHeights[ARow1] := RowHeights[ARow2];
    RowHeights[ARow2] := j;
  finally
    EndUpdateOrder;
  end;
end;

procedure TTyStringGrid.MoveRow(AFrom, ATo: Integer);
var
  i: Integer;
begin
  if AFrom = ATo then Exit;
  if (AFrom < 0) or (AFrom >= RowCount) then Exit;
  if (ATo < 0) or (ATo >= RowCount) then Exit;
  { 用相邻交换走过去:比"抽出来再插回去"少一套搬迁逻辑,
    行数级别的移动次数完全够用。 }
  BeginUpdateOrder;
  try
    if ATo > AFrom then
      for i := AFrom to ATo - 1 do SwapRows(i, i + 1)
    else
      for i := AFrom downto ATo + 1 do SwapRows(i, i - 1);
  finally
    EndUpdateOrder;
  end;
end;

procedure TTyStringGrid.MoveColumn(AFrom, ATo: Integer);
begin
  if (AFrom < 0) or (AFrom >= Header.Columns.Count) then Exit;
  if (ATo < 0) or (ATo >= Header.Columns.Count) then Exit;
  { 列的顺序交给列模型自己管(AdjustPosition 早就建好了),
    单元格内容按**索引**存,所以不用搬。 }
  Header.Columns.AdjustPosition(TTyColumn(Header.Columns.Items[AFrom]),
    TTyColumn(Header.Columns.Items[ATo]).Position);
  Invalidate;
end;

procedure TTyStringGrid.CutToClipboard;
var
  pos, dataRow, colIdx: Integer;
begin
  CopySelectionToClipboard;
  for pos := 0 to DisplayRowCount - 1 do
  begin
    dataRow := DisplayToData(pos);
    if dataRow < 0 then Continue;
    for colIdx := 0 to Header.Columns.Count - 1 do
      if IsCellSelected(colIdx, dataRow)
         and (EditorKindFor(colIdx, dataRow) <> gekNone) then    { 只读格不清 }
        Cells[colIdx, dataRow] := '';
  end;
  Invalidate;
end;

procedure TTyStringGrid.InsertRow(ARow: Integer);
begin
  if (ARow < 0) or (ARow > RowCount) then Exit;
  EndEdit(True);
  ShiftCells(ARow, 1, True);
  RowCount := RowCount + 1;
  InvalidateOrder;
  Invalidate;
end;

procedure TTyStringGrid.DeleteRow(ARow: Integer);
begin
  if (ARow < 0) or (ARow >= RowCount) then Exit;
  EndEdit(False);
  ShiftCells(ARow, -1, True);
  RowCount := RowCount - 1;
  if FRow > RowCount - 1 then FRow := RowCount - 1;
  if FRow < 0 then FRow := 0;
  InvalidateOrder;
  Invalidate;
end;

procedure TTyStringGrid.InsertColumn(ACol: Integer);
var
  c: TTyColumn;
begin
  if (ACol < 0) or (ACol > Header.Columns.Count) then Exit;
  EndEdit(True);
  ShiftCells(ACol, 1, False);
  c := Header.Columns.Add as TTyColumn;
  c.Index := ACol;
  Invalidate;
end;

procedure TTyStringGrid.DeleteColumn(ACol: Integer);
begin
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  EndEdit(False);
  ShiftCells(ACol, -1, False);
  Header.Columns.Delete(ACol);
  if FCol > Header.Columns.Count - 1 then FCol := Header.Columns.Count - 1;
  if FCol < 0 then FCol := 0;
  Invalidate;
end;

{ 按内容(含换行)把行高调到刚好放得下。

  测量用的是**和绘制同一套排版** —— 都走 BGRA 的 TTextStyle + Wordbreak,
  所以不会出现"算出来的高度放不下实际画出来的字"。自己另写一套换行算法
  是这里最容易踩的坑。 }
procedure TTyStringGrid.AutoFitRow(ARow: Integer);
var
  bmp: TBGRABitmap;
  cS: TTyStyleSet;
  colIdx, w, need, best, padL, padR, lineH: Integer;
  txt: string;
  wrap: Boolean;
  ap: TTyGridCellAppearance;
  st: TTextStyle;
  r: TRect;
begin
  if (ARow < 0) or (ARow >= RowCount) then Exit;
  cS := ActiveController.Model.ResolveStyle('TyGridCell', StyleClass, []);
  padL := ScaleI(cS.Padding.Left);
  padR := ScaleI(cS.Padding.Right);

  best := ScaleI(DefaultRowHeight);
  bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(bmp, cS.FontName, ResolveFontSize(cS), cS.FontWeight, Dpi);
    lineH := bmp.TextSize('Ag').cy;
    if lineH < 1 then lineH := 1;

    for colIdx := 0 to Header.Columns.Count - 1 do
    begin
      if not (coVisible in TTyColumn(Header.Columns.Items[colIdx]).Options) then Continue;
      txt := GetCellText(colIdx, ARow);
      if txt = '' then Continue;

      w := ColumnWidthPx(colIdx) - padL - padR;
      if w <= 0 then Continue;

      wrap := FWordWrap;
      if Assigned(FOnGetCellWordWrap) then FOnGetCellWordWrap(Self, colIdx, ARow, wrap);
      if not wrap then
      begin
        need := lineH;
      end
      else
      begin
        { 让 BGRA 自己按同样的 TTextStyle 排一遍,量出实际用了几行。
          做法:给一个足够高的框调 TextRect 是量不出高度的,所以按宽度切词 ——
          用同一支字体逐词累加,与 Wordbreak 的断法一致(空格/CJK 处断)。 }
        need := lineH * TyCountWrappedLines(bmp, txt, w);
      end;
      Inc(need, ScaleI(4));      { 上下各留一点气 }
      if need > best then best := need;
    end;
  finally
    bmp.Free;
  end;

  RowHeights[ARow] := UnscaleI(best);
end;

procedure TTyStringGrid.AutoFitRows;
var
  i: Integer;
begin
  for i := 0 to RowCount - 1 do AutoFitRow(i);
end;

procedure TTyStringGrid.AutoFitColumnWidth(ACol: Integer);
begin
  AutoFitColumn(ACol);
end;

procedure TTyStringGrid.AutoFitColumn(ACol: Integer);
var
  bmp: TBGRABitmap;
  cSty, hSty: TTyStyleSet;

  function TextW(const AText: string; const AStyle: TTyStyleSet): Integer;
  begin
    if AText = '' then Exit(0);
    TyConfigureTextFont(bmp, AStyle.FontName, ResolveFontSize(AStyle),
      AStyle.FontWeight, Dpi);
    Result := bmp.TextSize(AText).cx;
  end;

var
  widest, w, i, sep, c, r: Integer;
  k: string;
begin
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  { 1x1 的临时位图只用来量文字 —— 不需要画布,也不需要窗口句柄。 }
  bmp := TBGRABitmap.Create(1, 1);
  try
    cSty := ActiveController.Model.ResolveStyle('TyGridCell', StyleClass, []);
    hSty := ActiveController.Model.ResolveStyle('TyGridHeader', StyleClass, []);

    widest := TextW(TTyColumn(Header.Columns.Items[ACol]).Text, hSty);

    { 只量**写过的**格 —— 稀疏存储让百万行空表也只走几条记录,不必扫全表。 }
    for i := 0 to FCellKeys.Count - 1 do
    begin
      k := FCellKeys[i];
      sep := Pos(':', k);
      c := StrToIntDef(Copy(k, 1, sep - 1), -1);
      if c <> ACol then Continue;
      r := StrToIntDef(Copy(k, sep + 1, MaxInt), -1);
      w := TextW(GetCellText(ACol, r), cSty);
      if w > widest then widest := w;
    end;
  finally
    bmp.Free;
  end;

  { 加上左右内边距与一点余量,再换回逻辑像素。 }
  widest := widest + ScaleI(cSty.Padding.Left + cSty.Padding.Right) + ScaleI(8);
  TTyColumn(Header.Columns.Items[ACol]).Width := UnscaleI(widest);
  UpdateScrollBars;
  Invalidate;
end;

{ ---- 分组 ----------------------------------------------------------------- }

procedure TTyStringGrid.GroupByColumn(ACol: Integer);
begin
  EndEdit(True);
  if (ACol < 0) or (ACol >= Header.Columns.Count) then FGroupCol := -1
  else FGroupCol := ACol;
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.UngroupRows;
begin
  GroupByColumn(-1);
end;

function TTyStringGrid.GroupCount: Integer;
begin
  EnsureOrder;
  Result := Length(FGroups);
end;

function TTyStringGrid.GroupInfo(AIndex: Integer): TTyGridGroupInfo;
begin
  EnsureOrder;
  if (AIndex >= 0) and (AIndex < Length(FGroups)) then
    Result := FGroups[AIndex]
  else
  begin
    Result.Key := '';
    Result.Count := 0;
    Result.Collapsed := False;
  end;
end;

function TTyStringGrid.IsGroupRow(APos: Integer; out AGroupIndex: Integer): Boolean;
begin
  EnsureOrder;
  AGroupIndex := -1;
  Result := (APos >= 0) and (APos < Length(FOrder)) and (FOrder[APos] < 0);
  if Result then AGroupIndex := -FOrder[APos] - 1;
end;

procedure TTyStringGrid.ToggleGroup(AIndex: Integer);
var
  key: string;
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FGroups)) then Exit;
  key := FGroups[AIndex].Key;
  i := FCollapsed.IndexOf(key);
  { 折叠状态按**分组值**记账,而不是按组号 —— 重排/筛选后组号会变,值不会。 }
  if i >= 0 then FCollapsed.Delete(i) else FCollapsed.Add(key);
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

function TTyStringGrid.GroupToggleRect(APos: Integer): TRect;
var
  r: TRect;
  box, cy: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  r := TyGridRowRect(APos, GridMetrics);
  if r.Bottom <= r.Top then Exit;
  box := ScaleI(12);
  cy := (r.Top + r.Bottom) div 2;
  Result := Rect(ScaleI(4), cy - box div 2, ScaleI(4) + box, cy - box div 2 + box);
end;

procedure TTyStringGrid.RenderGroupRow(P: TTyPainter; APos, AGroupIndex: Integer;
  const M: TTyGridMetrics; const AFrame: TTyStyleSet);
var
  r, tr, tg: TRect;
  gS: TTyStyleSet;
  ink: TTyColor;
  info: TTyGridGroupInfo;
  i, l, w, keyRight: Integer;
  cRef: TTyColumn;
  txt: string;
  sub: TRect;
begin
  r := TyGridRowRect(APos, M);
  if (r.Bottom <= M.FrozenTop) or (r.Top >= M.ClientH) then Exit;

  info := GroupInfo(AGroupIndex);
  gS := ActiveController.Model.ResolveStyle('TyGridGroupRow', StyleClass, CurrentStates);
  if tpBackground in gS.Present then
    P.FillBackground(r, gS.Background, 0);
  if tpTextColor in gS.Present then ink := gS.TextColor else ink := AFrame.TextColor;

  { 折叠三角:展开时朝下,折叠时朝右 —— 与树的约定一致。 }
  tg := GroupToggleRect(APos);
  if not IsRectEmpty(tg) then
  begin
    if info.Collapsed then
      TyDrawGlyph(P, ActiveController, tg, tgChevronRight, ink, 1, 1)
    else
      TyDrawGlyph(P, ActiveController, tg, tgChevronDown, ink, 1, 1);
  end;

  { 分组小计:哪些列配了汇总方式,就在分组行的那几列上画出本组的小计。
    复用页脚那套列定位与冻结带裁剪 —— 同一个数在两处该长得一样、也该
    对齐在同一列下面。 }
  keyRight := M.ClientW - ScaleI(4);
  if FShowGroupSubtotals then
    for i := 0 to Header.Columns.Count - 1 do
    begin
      cRef := TTyColumn(Header.Columns.Items[i]);
      if not (coVisible in cRef.Options) then Continue;
      txt := GroupFooterText(AGroupIndex, i);
      if txt = '' then Continue;
      l := ColumnLeftPx(i);
      w := ColumnWidthPx(i);
      if (i >= FixedCols) and (l < M.FrozenLeft) then
      begin
        if l + w <= M.FrozenLeft then Continue;
        w := l + w - M.FrozenLeft;
        l := M.FrozenLeft;
      end;
      if (l >= M.ClientW) or (l + w <= 0) then Continue;
      { 组标题不能压到小计上 —— 让它在最左边那个小计列之前收住。 }
      if l - ScaleI(6) < keyRight then keyRight := l - ScaleI(6);
      sub := Rect(l + ScaleI(4), r.Top, l + w - ScaleI(4), r.Bottom);
      if sub.Right > sub.Left then
        P.DrawText(sub, txt, gS.FontName, ResolveFontSize(gS), gS.FontWeight,
          ink, taRightJustify, tlCenter, True);
    end;

  tr := Rect(tg.Right + ScaleI(6), r.Top, keyRight, r.Bottom);
  if tr.Right > tr.Left then
    P.DrawText(tr, GroupRowText(info.Key, info.Count),
      gS.FontName, ResolveFontSize(gS), gS.FontWeight, ink, taLeftJustify, tlCenter, True);
end;

{ ---- 汇总 ----------------------------------------------------------------- }

procedure TTyStringGrid.SetColumnAggregate(ACol: Integer; AKind: TTyGridAggregate);
var
  k: string;
  i: Integer;
begin
  k := IntToStr(ACol);
  i := FAggregates.IndexOfName(k);
  if i >= 0 then FAggregates.Delete(i);
  if AKind <> gagNone then FAggregates.Add(k + '=' + IntToStr(Ord(AKind)));
  Invalidate;
end;

function TTyStringGrid.ColumnAggregate(ACol: Integer): TTyGridAggregate;
var
  v: string;
  c: TTyGridColumn;
begin
  { 运行期用 SetColumnAggregate 设过的优先(直接动作),否则看列属性(设计期配的)。 }
  v := FAggregates.Values[IntToStr(ACol)];
  if v <> '' then Exit(TTyGridAggregate(StrToIntDef(v, 0)));
  c := GridColumn(ACol);
  if c <> nil then Result := c.Aggregate else Result := gagNone;
end;

{ 把一行并进累加器。整表汇总与分组小计共用它 —— 否则"非数值格跳过"
  这类规则会在两处各写一遍,迟早走样。 }
procedure TTyStringGrid.AccumulateCell(ACol, ADataRow: Integer;
  AKind: TTyGridAggregate; var AAcc: Double; var ACount: Integer;
  var AStarted: Boolean);
var
  v: Double;
  txt: string;
begin
  if ADataRow < 0 then Exit;
  txt := Trim(GetCellText(ACol, ADataRow));
  if txt = '' then Exit;
  v := StrToFloatDef(txt, NaN);
  if IsNan(v) then Exit;            { 非数值格直接跳过,不污染统计 }
  Inc(ACount);
  case AKind of
    gagSum, gagAvg: AAcc := AAcc + v;
    gagMin: if (not AStarted) or (v < AAcc) then AAcc := v;
    gagMax: if (not AStarted) or (v > AAcc) then AAcc := v;
  end;
  AStarted := True;
end;

{ 某一组内、某一列的小计。按组的**成员数据行**统计,所以折叠着也算得出来。 }
function TTyStringGrid.GroupAggregateValue(AGroupIndex, ACol: Integer): Double;
var
  i, n: Integer;
  acc: Double;
  kind: TTyGridAggregate;
  started: Boolean;
begin
  Result := 0;
  if (AGroupIndex < 0) or (AGroupIndex > High(FGroups)) then Exit;
  kind := ColumnAggregate(ACol);
  if kind = gagNone then Exit;
  if kind = gagCount then Exit(FGroups[AGroupIndex].Count);

  acc := 0;
  n := 0;
  started := False;
  for i := 0 to High(FGroups[AGroupIndex].Rows) do
    AccumulateCell(ACol, FGroups[AGroupIndex].Rows[i], kind, acc, n, started);
  if n = 0 then Exit;
  if kind = gagAvg then Result := acc / n else Result := acc;
end;

{ 分组行上某列显示的小计文字。与页脚同一套前缀与格式 —— 同一个数在两处
  长得不一样是最没道理的不一致。 }
function TTyStringGrid.GroupFooterText(AGroupIndex, ACol: Integer): string;
var
  kind: TTyGridAggregate;
begin
  Result := '';
  kind := ColumnAggregate(ACol);
  if kind = gagNone then Exit;
  if kind = gagCount then
    Result := AggregatePrefix(kind) + IntToStr(Round(GroupAggregateValue(AGroupIndex, ACol)))
  else
    Result := AggregatePrefix(kind)
              + FormatFloat('0.##', GroupAggregateValue(AGroupIndex, ACol));
end;

function TTyStringGrid.AggregatePrefix(AKind: TTyGridAggregate): string;
begin
  case AKind of
    gagSum:   Result := rsGridSumPrefix;
    gagAvg:   Result := rsGridAvgPrefix;
    gagMin:   Result := rsGridMinPrefix;
    gagMax:   Result := rsGridMaxPrefix;
    gagCount: Result := rsGridCountPrefix;
  else        Result := '';
  end;
end;

function TTyStringGrid.AggregateValue(ACol: Integer): Double;
var
  pos, dataRow, n: Integer;
  v, acc: Double;
  kind: TTyGridAggregate;
  txt: string;
  started: Boolean;
begin
  Result := 0;
  kind := ColumnAggregate(ACol);
  if kind = gagNone then Exit;

  { 只遍历**显示序** —— 被过滤掉的行不参与统计,筛完总计立刻跟着变。 }
  if kind = gagCount then
  begin
    Result := DisplayRowCount;
    Exit;
  end;

  acc := 0;
  n := 0;
  started := False;
  for pos := 0 to DisplayRowCount - 1 do
  begin
    dataRow := DisplayToData(pos);
    if dataRow < 0 then Continue;
    AccumulateCell(ACol, dataRow, kind, acc, n, started);
    started := True;
  end;

  if n = 0 then Exit;
  if kind = gagAvg then Result := acc / n else Result := acc;
end;

function TTyStringGrid.FooterText(ACol: Integer): string;
var
  kind: TTyGridAggregate;
  prefix: string;
begin
  Result := '';
  kind := ColumnAggregate(ACol);
  if kind <> gagNone then
  begin
    prefix := AggregatePrefix(kind);
    if kind = gagCount then
      Result := prefix + IntToStr(Round(AggregateValue(ACol)))
    else
      Result := prefix + FormatFloat('0.##', AggregateValue(ACol));
  end;
  if Assigned(FOnGetFooterText) then FOnGetFooterText(Self, ACol, Result);
end;

procedure TTyStringGrid.RenderFooter(P: TTyPainter; const M: TTyGridMetrics;
  const AFooterRect: TRect; const AFrame: TTyStyleSet);
var
  i, l, w: Integer;
  cRef: TTyColumn;
  fS: TTyStyleSet;
  ink: TTyColor;
  txt: string;
  r: TRect;
begin
  inherited RenderFooter(P, M, AFooterRect, AFrame);

  fS := ActiveController.Model.ResolveStyle('TyGridSummaryRow', StyleClass, CurrentStates);
  if tpTextColor in fS.Present then ink := fS.TextColor else ink := AFrame.TextColor;

  for i := 0 to Header.Columns.Count - 1 do
  begin
    cRef := TTyColumn(Header.Columns.Items[i]);
    if not (coVisible in cRef.Options) then Continue;
    txt := FooterText(i);
    if txt = '' then Continue;
    l := ColumnLeftPx(i);
    w := ColumnWidthPx(i);
    { 与单元格同一条裁剪规则:滚到冻结带底下的部分不露出来。 }
    if (i >= FixedCols) and (l < M.FrozenLeft) then
    begin
      if l + w <= M.FrozenLeft then Continue;
      w := l + w - M.FrozenLeft;
      l := M.FrozenLeft;
    end;
    if (l >= M.ClientW) or (l + w <= 0) then Continue;
    r := Rect(l + ScaleI(4), AFooterRect.Top, l + w - ScaleI(4), AFooterRect.Bottom);
    if r.Right > r.Left then
      P.DrawText(r, txt, fS.FontName, ResolveFontSize(fS), fS.FontWeight,
        ink, cRef.Alignment, tlCenter, True);
  end;
end;

function TTyStringGrid.CellRect(ACol, ARow: Integer): TRect;
var
  cs, rs, bc, br, lastPos: Integer;
  r2: TRect;
begin
  Result := inherited CellRect(ACol, ARow);
  if IsRectEmpty(Result) then Exit;

  if CellSpan(ACol, ARow, cs, rs) then
  begin
    { 基准格:向右吃 cs 列、向下吃 rs 行(按显示序)。 }
    if cs > 1 then
      Result.Right := ColumnLeftPx(Min(ACol + cs, Header.Columns.Count) - 1)
                      + ColumnWidthPx(Min(ACol + cs, Header.Columns.Count) - 1);
    if rs > 1 then
    begin
      lastPos := DataToDisplay(ARow) + rs - 1;
      if lastPos > DisplayRowCount - 1 then lastPos := DisplayRowCount - 1;
      r2 := TyGridRowRect(lastPos, GridMetrics);
      Result.Bottom := r2.Bottom;
    end;
    Exit;
  end;

  { 被别人覆盖的格没有自己的矩形 —— 否则会在合并区里画出格线与文字。 }
  BaseCellOf(ACol, ARow, bc, br);
  if (bc <> ACol) or (br <> ARow) then
    Result := Rect(0, 0, 0, 0);
end;

procedure TTyStringGrid.MapToBaseCell(var ACol, ARow: Integer);
var
  bc, br: Integer;
begin
  BaseCellOf(ACol, ARow, bc, br);
  ACol := bc;
  ARow := br;
end;

{ ---- 单元格合并 ----------------------------------------------------------- }

function TTyStringGrid.RowsDisplayedConsecutively(ABaseRow, ACount: Integer): Boolean;
var
  i, p0: Integer;
begin
  Result := False;
  p0 := DataToDisplay(ABaseRow);
  if p0 < 0 then Exit;
  for i := 1 to ACount - 1 do
    if DataToDisplay(ABaseRow + i) <> p0 + i then Exit;
  Result := True;
end;

function TTyStringGrid.MergeSelection: Boolean;
var
  r: TRect;
  i, baseRow, prev, dr: Integer;   { 别叫 top —— 与 TRect.Top 撞名 }
begin
  Result := False;
  r := ActiveSelectionRect;            { 显示序空间 }
  if (r.Right <= r.Left) and (r.Bottom <= r.Top) then Exit;

  { 屏幕上连着的一段,必须同时是**数据行上连续升序的一段**。
    排过序/筛过之后,屏幕上挨着的几行在数据里可能天各一方 —— 把它们合成一块
    没有意义:换个排序块就散了。这种时候宁可什么都不做,也不要吞掉别的行。 }
  baseRow := DisplayToData(r.Top);
  if baseRow < 0 then Exit;
  prev := baseRow;
  for i := r.Top + 1 to r.Bottom do
  begin
    dr := DisplayToData(i);
    if dr <> prev + 1 then Exit;
    prev := dr;
  end;

  MergeCells(r.Left, baseRow, r.Right - r.Left + 1, r.Bottom - r.Top + 1);
  Result := True;
end;

procedure TTyStringGrid.MergeCells(ACol, ARow, AColSpan, ARowSpan: Integer);
begin
  if (AColSpan <= 1) and (ARowSpan <= 1) then
  begin
    UnmergeCells(ACol, ARow);
    Exit;
  end;
  if AColSpan < 1 then AColSpan := 1;
  if ARowSpan < 1 then ARowSpan := 1;
  { 越界的跨度直接钳住 —— 让"单位算错了"的调用方拿到一个不吞别人的结果,
    而不是把下面几十行悄悄卷进来。 }
  if ARow + ARowSpan > RowCount then ARowSpan := RowCount - ARow;
  if ACol + AColSpan > FHeader.Columns.Count then
    AColSpan := FHeader.Columns.Count - ACol;
  if (AColSpan <= 1) and (ARowSpan <= 1) then
  begin
    UnmergeCells(ACol, ARow);
    Exit;
  end;
  with FAttrs.Ensure(CellKey(ACol, ARow)) do
  begin
    if (ColSpan <= 1) and (RowSpan <= 1) then Inc(FMergeCount);
    ColSpan := AColSpan;
    RowSpan := ARowSpan;
    { 记住最大跨度 —— BaseCellOf 只需回扫这么远。合并区通常只有 2x2,
      而不收敛的话每格都要扫到 (0,0)。只增不减:拆合并时不缩小,
      顶多让回扫多走几格,不会算错。 }
    if AColSpan > FMaxColSpan then FMaxColSpan := AColSpan;
    if ARowSpan > FMaxRowSpan then FMaxRowSpan := ARowSpan;
  end;
  Invalidate;
end;

procedure TTyStringGrid.UnmergeCells(ACol, ARow: Integer);
var
  k: string;
  a: TTyGridCellAttr;
begin
  k := CellKey(ACol, ARow);
  a := FAttrs.Find(k);
  if a = nil then Exit;
  if (a.ColSpan > 1) or (a.RowSpan > 1) then Dec(FMergeCount);
  a.ColSpan := 1;
  a.RowSpan := 1;
  FAttrs.DropIfDefault(k);      { 只剩默认值就别占着位置 }
  Invalidate;
end;

procedure TTyStringGrid.ClearMerges;
var
  keys: TStringList;
  i: Integer;
  a: TTyGridCellAttr;
begin
  { 只清合并,不能把同一条目上的别的属性(底色/只读)一起清掉。 }
  keys := TStringList.Create;
  try
    FAttrs.SnapshotKeys(keys);
    for i := 0 to keys.Count - 1 do
    begin
      a := FAttrs.Find(keys[i]);
      if a = nil then Continue;
      a.ColSpan := 1;
      a.RowSpan := 1;
      FAttrs.DropIfDefault(keys[i]);
    end;
    FMergeCount := 0;
  finally
    keys.Free;
  end;
  Invalidate;
end;

function TTyStringGrid.MaxRowSpanHint: Integer;
begin
  Result := FMaxRowSpan;
  if Result < 1 then Result := 1;
end;

function TTyStringGrid.CellSpan(ACol, ARow: Integer;
  out AColSpan, ARowSpan: Integer): Boolean;
var
  a: TTyGridCellAttr;
begin
  AColSpan := 1;
  ARowSpan := 1;
  { 全表一个合并都没有时直接走人 —— 连 CellKey 那个临时字符串都别建。
    这条查询在渲染路径上每格要走好几次。 }
  if FMergeCount = 0 then Exit(False);
  a := FAttrs.Find(CellKey(ACol, ARow));
  if a = nil then Exit(False);
  AColSpan := a.ColSpan;
  ARowSpan := a.RowSpan;
  { 合并块记的是一段**数据行**。只有这段数据行此刻正连续升序地显示着,它才成立
    —— 排序/筛选/隐藏行会把它们打散,那时若还照着"从基准格往下数 rs 个
    **显示行**"去画(CellRect / BaseCellOf 就是这么消费它的),盖住的已经是
    另外几行了:合并块会"糊"到别处去。
    失效不等于销毁:排回去它自己就回来了。 }
  if (ARowSpan > 1) and (not RowsDisplayedConsecutively(ARow, ARowSpan)) then
    ARowSpan := 1;
  Result := (AColSpan > 1) or (ARowSpan > 1);
end;

function TTyStringGrid.IsBaseCell(ACol, ARow: Integer): Boolean;
var
  cs, rs: Integer;
begin
  Result := CellSpan(ACol, ARow, cs, rs);
end;

procedure TTyStringGrid.BaseCellOf(ACol, ARow: Integer;
  out ABaseCol, ABaseRow: Integer);
var
  c, r, cs, rs, pos, basePos, minC, minP: Integer;
begin
  ABaseCol := ACol;
  ABaseRow := ARow;
  if ACol < 0 then Exit;
  { **没有任何合并时立刻走人。**

    下面那个双重循环是 O(列 x 显示行) 的,每次迭代还要建一个 CellKey 字符串、
    查一次排序表 —— 而 CellRect 每格都会调到这里。于是"一个合并都没有"的普通表
    也要为合并功能付 O(格数 x 列数 x 行数) 的代价:实测这一条就占了整帧的一半。
    合并本来就是稀疏的例外,不该让常态替它买单。 }
  if FMergeCount = 0 then Exit;
  pos := DataToDisplay(ARow);
  if pos < 0 then Exit;

  { 往左上找覆盖住本格的基准格。**只回扫到最大跨度那么远** ——
    再远的格不可能覆盖到这里。不收敛的话每格都要扫到 (0,0),整体成 O(n^2)。
    纵向按**显示序**判定 —— 合并是屏幕上的一块矩形。 }
  minC := ACol - FMaxColSpan + 1;   if minC < 0 then minC := 0;
  minP := pos - FMaxRowSpan + 1;    if minP < 0 then minP := 0;
  for c := ACol downto minC do
    for basePos := pos downto minP do
    begin
      r := DisplayToData(basePos);
      if r < 0 then Continue;
      if not CellSpan(c, r, cs, rs) then Continue;
      if (ACol < c + cs) and (pos < basePos + rs) then
      begin
        ABaseCol := c;
        ABaseRow := r;
        Exit;
      end;
    end;
end;


{ ---- 查找 / 替换 ----------------------------------------------------------- }

function TyGridMatches(const ACell, AText: string;
  ACaseSensitive, AWholeCell: Boolean): Boolean;
var
  a, b: string;
begin
  if ACaseSensitive then begin a := ACell; b := AText; end
  else begin a := UpperCase(ACell); b := UpperCase(AText); end;
  if AWholeCell then Result := a = b
  else Result := (b <> '') and (Pos(b, a) > 0);
end;

function TTyStringGrid.FindCell(const AText: string;
  ACaseSensitive, AWholeCell: Boolean; out ACol, ARow: Integer): Boolean;
var
  startPos, flat, total, n, pos, c, dataRow, i: Integer;
begin
  Result := False;
  ACol := -1;
  ARow := -1;
  if AText = '' then Exit;
  n := Header.Columns.Count;
  if (n = 0) or (DisplayRowCount = 0) then Exit;

  startPos := DataToDisplay(FRow);
  if startPos < 0 then startPos := 0;

  { 把 (显示行, 列) 压成一维序号,从当前光标的下一格起环绕一圈 ——
    这样连按"查找下一个"能不重不漏地走遍全表。 }
  total := DisplayRowCount * n;
  for i := 1 to total do
  begin
    flat := (startPos * n + FCol + i) mod total;
    pos := flat div n;
    c := flat mod n;
    dataRow := DisplayToData(pos);
    if dataRow < 0 then Continue;                 { 分组行跳过 }
    if TyGridMatches(GetCellText(c, dataRow), AText, ACaseSensitive, AWholeCell) then
    begin
      ACol := c;
      ARow := dataRow;
      Exit(True);
    end;
  end;
end;

function TTyStringGrid.FindNext(const AText: string;
  ACaseSensitive, AWholeCell: Boolean): Boolean;
var
  c, r: Integer;
begin
  Result := FindCell(AText, ACaseSensitive, AWholeCell, c, r);
  if Result then
  begin
    MoveCursor(c, r);
    AnchorSelection;
    ScrollIntoView(c, r);
  end;
end;

function TTyStringGrid.ReplaceCells(const AFind, AReplace: string;
  ACaseSensitive, AWholeCell, AAll: Boolean): Integer;
var
  pos, c, dataRow: Integer;
  cur: string;
  flags: TReplaceFlags;
begin
  Result := 0;
  if AFind = '' then Exit;
  EndEdit(True);
  flags := [rfReplaceAll];
  if not ACaseSensitive then Include(flags, rfIgnoreCase);

  for pos := 0 to DisplayRowCount - 1 do
  begin
    dataRow := DisplayToData(pos);
    if dataRow < 0 then Continue;
    for c := 0 to Header.Columns.Count - 1 do
    begin
      cur := GetCellText(c, dataRow);
      if not TyGridMatches(cur, AFind, ACaseSensitive, AWholeCell) then Continue;
      if EditorKindFor(c, dataRow) = gekNone then Continue;    { 只读格不动 }
      if AWholeCell then Cells[c, dataRow] := AReplace
      else Cells[c, dataRow] := StringReplace(cur, AFind, AReplace, flags);
      Inc(Result);
      if not AAll then Exit;
    end;
  end;
end;

{ ---- HTML 导出 ------------------------------------------------------------- }

function TyHtmlEscape(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function TTyStringGrid.SaveToHTMLText: string;
var
  sb: TStringList;
  pos, cIdx, dataRow: Integer;
  line: string;
begin
  sb := TStringList.Create;
  try
    sb.Add('<table border="1" cellspacing="0" cellpadding="4">');
    line := '<tr>';
    for cIdx := 0 to Header.Columns.Count - 1 do
      line := line + '<th>' + TyHtmlEscape(TTyColumn(Header.Columns.Items[cIdx]).Text) + '</th>';
    sb.Add(line + '</tr>');

    { 与 CSV 一致:走**显示序** —— 筛掉的行不出现、排序后的次序保留。 }
    for pos := 0 to DisplayRowCount - 1 do
    begin
      dataRow := DisplayToData(pos);
      if dataRow < 0 then Continue;             { 分组行不导出 }
      line := '<tr>';
      for cIdx := 0 to Header.Columns.Count - 1 do
        line := line + '<td>' + TyHtmlEscape(GetCellText(cIdx, dataRow)) + '</td>';
      sb.Add(line + '</tr>');
    end;
    sb.Add('</table>');
    Result := sb.Text;
  finally
    sb.Free;
  end;
end;

procedure TTyStringGrid.SaveToHTMLFile(const AFileName: string);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Text := SaveToHTMLText;
    sl.SaveToFile(AFileName);
  finally
    sl.Free;
  end;
end;

{ ---- 剪贴板 / CSV ---------------------------------------------------------- }

function TTyStringGrid.SelectionAsText: string;
var
  c1, c2, r1, r2, pos, cIdx: Integer;
  sb: TStringList;
  line: string;
begin
  c1 := Min(FSelAnchorCol, FCol);  c2 := Max(FSelAnchorCol, FCol);
  r1 := Min(DataToDisplay(FSelAnchorRow), DataToDisplay(FRow));
  r2 := Max(DataToDisplay(FSelAnchorRow), DataToDisplay(FRow));

  sb := TStringList.Create;
  try
    { 按**显示序**导出 —— 用户复制的是他看到的那块,不是底层行号区间。 }
    for pos := r1 to r2 do
    begin
      line := '';
      for cIdx := c1 to c2 do
      begin
        if cIdx > c1 then line := line + #9;
        line := line + GetCellText(cIdx, DisplayToData(pos));
      end;
      sb.Add(line);
    end;
    Result := sb.Text;
  finally
    sb.Free;
  end;
end;

procedure TTyStringGrid.CopySelectionToClipboard;
var
  txt: string;
  allow: Boolean;
begin
  txt := SelectionAsText;
  allow := True;
  if Assigned(FOnClipboardCopy) then FOnClipboardCopy(Self, txt, allow);
  if not allow then Exit;
  Clipboard.AsText := txt;
end;

procedure TTyStringGrid.PasteFromText(const AText: string);
var
  lines: TStringList;
  i, j, targetRow, startPos, needRows, needCols, maxCols: Integer;
  parts: TStringArray;
  txt, cellTxt: string;
  allow: Boolean;
begin
  if AText = '' then Exit;
  EndEdit(True);

  txt := AText;
  allow := True;
  if Assigned(FOnClipboardPaste) then FOnClipboardPaste(Self, txt, allow);
  if not allow then Exit;

  lines := TStringList.Create;
  BeginUpdateOrder;
  try
    lines.Text := txt;
    { 末尾那个空行是 TStringList.Text 的产物,不是真的一行。 }
    while (lines.Count > 0) and (lines[lines.Count - 1] = '') do
      lines.Delete(lines.Count - 1);
    if lines.Count = 0 then Exit;

    startPos := DataToDisplay(FRow);

    { **智能粘贴**:块比网格大就把网格撑大。
      从前这里是 `if targetRow < 0 then Break` —— 粘 100 行进 10 行的网格,
      **静默丢掉 90 行**。丢数据是最不该静默的一类失败。 }
    if FAutoGrowOnPaste then
    begin
      needRows := startPos + lines.Count - DisplayRowCount;
      if needRows > 0 then RowCount := RowCount + needRows;

      maxCols := 0;
      for i := 0 to lines.Count - 1 do
      begin
        j := Length(lines[i].Split(#9));
        if j > maxCols then maxCols := j;
      end;
      needCols := FCol + maxCols - Header.Columns.Count;
      if needCols > 0 then InsertCols(Header.Columns.Count, needCols);
    end;

    for i := 0 to lines.Count - 1 do
    begin
      { 粘贴按**显示序**落位:从光标所在的显示行往下铺,
        这样"看到哪就粘到哪",与复制端对称。 }
      targetRow := DisplayToData(startPos + i);
      if targetRow < 0 then Continue;     { 撑不动(比如分组行)就跳过这一行,不是整体放弃 }
      parts := lines[i].Split(#9);
      for j := 0 to High(parts) do
      begin
        if FCol + j >= Header.Columns.Count then Break;
        if EditorKindFor(FCol + j, targetRow) = gekNone then Continue;  { 只读列跳过 }

        cellTxt := parts[j];
        allow := True;
        if Assigned(FOnBeforePasteCell) then
          FOnBeforePasteCell(Self, FCol + j, targetRow, cellTxt, allow);
        if not allow then Continue;

        Cells[FCol + j, targetRow] := cellTxt;
        if Assigned(FOnAfterPasteCell) then
          FOnAfterPasteCell(Self, FCol + j, targetRow);
      end;
    end;
  finally
    lines.Free;
    EndUpdateOrder;
  end;
  Invalidate;
end;

procedure TTyStringGrid.PasteFromClipboard;
begin
  if Clipboard.HasFormat(CF_TEXT) then PasteFromText(Clipboard.AsText);
end;

function TyCsvQuote(const AValue: string; ADelimiter: Char): string;
begin
  { 含分隔符、引号或换行的字段必须加引号,内部引号翻倍 —— 否则导出的 CSV 读不回来。 }
  if (Pos(ADelimiter, AValue) > 0) or (Pos('"', AValue) > 0)
     or (Pos(#13, AValue) > 0) or (Pos(#10, AValue) > 0) then
    Result := '"' + StringReplace(AValue, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := AValue;
end;

function TTyStringGrid.SaveToCSVText(ADelimiter: Char): string;
var
  sb: TStringList;
  pos, cIdx: Integer;
  line: string;
begin
  sb := TStringList.Create;
  try
    { 表头一行(列标题),然后按显示序导出可见行。 }
    line := '';
    for cIdx := 0 to Header.Columns.Count - 1 do
    begin
      if cIdx > 0 then line := line + ADelimiter;
      line := line + TyCsvQuote(TTyColumn(Header.Columns.Items[cIdx]).Text, ADelimiter);
    end;
    sb.Add(line);

    for pos := 0 to DisplayRowCount - 1 do
    begin
      line := '';
      for cIdx := 0 to Header.Columns.Count - 1 do
      begin
        if cIdx > 0 then line := line + ADelimiter;
        line := line + TyCsvQuote(GetCellText(cIdx, DisplayToData(pos)), ADelimiter);
      end;
      sb.Add(line);
    end;
    Result := sb.Text;
  finally
    sb.Free;
  end;
end;

{ 拆一行 CSV,尊重引号(引号内的分隔符不算分隔)。 }
function TyCsvSplit(const ALine: string; ADelimiter: Char): TStringArray;
var
  i, n: Integer;
  cur: string;
  inQuote: Boolean;
begin
  SetLength(Result, 0);
  n := 0;
  cur := '';
  inQuote := False;
  i := 1;
  while i <= Length(ALine) do
  begin
    if inQuote then
    begin
      if ALine[i] = '"' then
      begin
        if (i < Length(ALine)) and (ALine[i + 1] = '"') then
        begin
          cur := cur + '"';   { 翻倍的引号 = 一个字面引号 }
          Inc(i);
        end
        else
          inQuote := False;
      end
      else
        cur := cur + ALine[i];
    end
    else if ALine[i] = '"' then inQuote := True
    else if ALine[i] = ADelimiter then
    begin
      SetLength(Result, n + 1); Result[n] := cur; Inc(n);
      cur := '';
    end
    else
      cur := cur + ALine[i];
    Inc(i);
  end;
  SetLength(Result, n + 1);
  Result[n] := cur;
end;


{ 字符级流式 CSV 解析:整段文本一次扫完,只有**引号之外**的换行才断行。

  这是为了修一个数据正确性缺陷:早先的做法是先 `TStringList.Text := AText` 按行切、
  再对每行调 TyCsvSplit —— 引号内的换行(Excel 导出很常见)会被当成行分隔符,
  于是行数凭空变多、单元格被拦腰截断,而且**不报任何错**。

  返回:每行一个 TStringArray。 }
type
  TTyCsvRows = array of TStringArray;

function TyCsvParse(const AText: string; ADelimiter: Char): TTyCsvRows;
var
  i, n, rowN, colN: Integer;
  cur: string;
  inQuote: Boolean;
  row: TStringArray;

  procedure PushField;
  begin
    SetLength(row, colN + 1);
    row[colN] := cur;
    Inc(colN);
    cur := '';
  end;

  procedure PushRow;
  begin
    PushField;
    SetLength(Result, rowN + 1);
    Result[rowN] := row;
    Inc(rowN);
    SetLength(row, 0);
    colN := 0;
  end;

begin
  SetLength(Result, 0);
  SetLength(row, 0);
  rowN := 0;
  colN := 0;
  cur := '';
  inQuote := False;
  n := Length(AText);
  i := 1;
  while i <= n do
  begin
    if inQuote then
    begin
      if AText[i] = '"' then
      begin
        if (i < n) and (AText[i + 1] = '"') then
        begin
          cur := cur + '"';      { 翻倍的引号 = 一个字面引号 }
          Inc(i);
        end
        else
          inQuote := False;
      end
      else
        cur := cur + AText[i];   { 引号内:换行也只是普通字符 }
    end
    else if AText[i] = '"' then
      inQuote := True
    else if AText[i] = ADelimiter then
      PushField
    else if AText[i] = #13 then
    begin
      PushRow;
      if (i < n) and (AText[i + 1] = #10) then Inc(i);   { 吃掉 CRLF 的 LF }
    end
    else if AText[i] = #10 then
      PushRow
    else
      cur := cur + AText[i];
    Inc(i);
  end;

  { 收尾:文本末尾没有换行时,最后一行还没入账。
    但要区分"真有最后一行"和"末尾就是个换行" —— 后者不该多出一个空行。 }
  if (cur <> '') or (colN > 0) then PushRow;
end;

procedure TTyStringGrid.LoadFromCSVText(const AText: string; ADelimiter: Char);
var
  rows: TTyCsvRows;
  i, j, dataRow: Integer;
begin
  EndEdit(False);
  { 字符级解析:引号内的换行不断行(见 TyCsvParse 的说明)。 }
  rows := TyCsvParse(AText, ADelimiter);
  if Length(rows) = 0 then Exit;

  { 第一行当表头:按它建列(列数不足就补)。 }
  while Header.Columns.Count < Length(rows[0]) do
    Header.Columns.Add;
  for j := 0 to High(rows[0]) do
    TTyColumn(Header.Columns.Items[j]).Text := rows[0][j];

  ClearCells;
  ClearFilters;
  SortByColumn(-1, sdAscending);       { 导入后回到原始顺序 }
  RowCount := Length(rows) - 1;

  for i := 1 to High(rows) do
  begin
    dataRow := i - 1;
    for j := 0 to High(rows[i]) do
    begin
      if j >= Header.Columns.Count then Break;
      Cells[j, dataRow] := rows[i][j];
    end;
  end;

  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.SaveToCSVFile(const AFileName: string; ADelimiter: Char);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Text := SaveToCSVText(ADelimiter);
    sl.SaveToFile(AFileName);
  finally
    sl.Free;
  end;
end;

procedure TTyStringGrid.LoadFromCSVFile(const AFileName: string; ADelimiter: Char);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(AFileName);
    LoadFromCSVText(sl.Text, ADelimiter);
  finally
    sl.Free;
  end;
end;

procedure TTyStringGrid.SortByColumn(ACol: Integer; ADirection: TTySortDirection);
var
  i, j, cmp, tmp: Integer;
  canSort: Boolean;
begin
  EndEdit(True);        { 行要重排了 —— 先把编辑提交掉 }

  { 宿主可以拦下某一列的排序(比如它要走服务端排序)。 }
  if (ACol >= 0) and Assigned(FOnCanSort) then
  begin
    canSort := True;
    FOnCanSort(Self, ACol, canSort);
    if not canSort then Exit;
  end;

  if (ACol < 0) or (ACol >= Header.Columns.Count) or (RowCount <= 0) then
  begin
    FSortCol := -1;
    SetLength(FSortKeys, 0);
    { 表头也要跟着清 —— 排序小三角看的是 Header.SortColumn。 }
    Header.SortColumn := NoColumn;
    InvalidateOrder;
    UpdateScrollBars;
    Invalidate;
    Exit;
  end;

  { 单列排序 = 把键序列重置成只有这一条。想追加次级列请用 AddSortColumn。 }
  SetLength(FSortKeys, 1);
  FSortKeys[0].Col := ACol;
  FSortKeys[0].Dir := ADirection;
  FSortCol := ACol;
  FSortDir := ADirection;
  { **同步给表头**。此前只写了 FSortCol,而 hoShowSortGlyphs 那个小三角看的是
    Header.SortColumn —— 于是三角永远停在 NoColumn、一次都没画出来过。
    又一个"属性存在却没人写"的洞。 }
  Header.SortColumn := ACol;
  Header.SortDirection := ADirection;
  InvalidateOrder;
  EnsureOrder;      { 重建里已按 FSortCol 排过 }
  if False then
  begin
  { **稳定归并排序** O(n log n)。早先用插入排序 O(n^2),1000 行要几千万次比较,
    再叠上当时线性的单元格查找就彻底卡死 —— 真实规模的测试把这条压出来了。
    稳定 = 等值行保持原有相对次序,用户连点列头来回切方向时不会乱跳。 }
  MergeSortOrder(ACol, ADirection);
  end;

  { 光标按**数据行**记账,所以它仍然盯着排序前那条数据 —— 但**视口原地不动**。
    用户看着第一屏点排序,期望看到"现在排最前的那些行",而不是被拖去追旧的第一条。
    (跟随只在光标**主动移动**时才该发生,见 MoveCursor。) }
  UpdateScrollBars;      { 行的显示位置全变了,滑块范围/位置要重算 }
  Invalidate;
end;

function TTyStringGrid.EffectiveSortKeys: TTyGridSortKeys;
var
  i, n: Integer;
begin
  { 分组列必须排在**最前面** —— 同组的行不相邻就切不出段来。
    但它只是"临时插在前面",绝不写回 FSortKeys:从前 BuildGroups 直接
    `FSortCol := FGroupCol`,一分组就把用户选的排序列**永久**抹掉了。 }
  SetLength(Result, 0);
  if FGroupCol >= 0 then
  begin
    SetLength(Result, 1);
    Result[0].Col := FGroupCol;
    Result[0].Dir := FSortDir;
  end;
  for i := 0 to High(FSortKeys) do
  begin
    if FSortKeys[i].Col < 0 then Continue;
    if (FGroupCol >= 0) and (FSortKeys[i].Col = FGroupCol) then Continue;
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n] := FSortKeys[i];
  end;
end;

procedure TTyStringGrid.AddSortColumn(ACol: Integer; ADirection: TTySortDirection);
var
  i, n: Integer;
begin
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  for i := 0 to High(FSortKeys) do
    if FSortKeys[i].Col = ACol then
    begin
      { 已经是排序键了 —— 再点一次就翻方向,而不是加一条重复的键。 }
      FSortKeys[i].Dir := ADirection;
      if i = 0 then begin FSortCol := ACol; FSortDir := ADirection; end;
      InvalidateOrder;
      UpdateScrollBars;
      Invalidate;
      Exit;
    end;
  n := Length(FSortKeys);
  SetLength(FSortKeys, n + 1);
  FSortKeys[n].Col := ACol;
  FSortKeys[n].Dir := ADirection;
  if n = 0 then
  begin
    FSortCol := ACol;
    FSortDir := ADirection;
    Header.SortColumn := ACol;
    Header.SortDirection := ADirection;
  end;
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.ClearSortColumns;
begin
  SetLength(FSortKeys, 0);
  FSortCol := -1;
  Header.SortColumn := NoColumn;
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

function TTyStringGrid.SortColumnCount: Integer;
begin
  Result := Length(FSortKeys);
end;

function TTyStringGrid.SortColumnAt(AIndex: Integer): TTyGridSortKey;
begin
  Result.Col := -1;
  Result.Dir := sdAscending;
  if (AIndex >= 0) and (AIndex <= High(FSortKeys)) then Result := FSortKeys[AIndex];
end;

function TTyStringGrid.GroupRowText(const AKey: string; ACount: Integer): string;
begin
  Result := Format(FGroupRowFormat, [AKey, ACount]);
end;

function TTyStringGrid.SortDirectionOf(ACol: Integer): TTySortDirection;
var
  i: Integer;
begin
  Result := sdDescending;      { 没排过 → 下一次点给升序 }
  for i := 0 to High(FSortKeys) do
    if FSortKeys[i].Col = ACol then Exit(FSortKeys[i].Dir);
end;

procedure TTyStringGrid.ExpandAllGroups;
begin
  FCollapsed.Clear;
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.CollapseAllGroups;
var
  i: Integer;
begin
  { 先确保分组已经切好,再把每个组的**值**记进折叠表
    (折叠按值记账,重排/筛选后组号会变、值不会)。 }
  EnsureOrder;
  for i := 0 to High(FGroups) do
    if FCollapsed.IndexOf(FGroups[i].Key) < 0 then FCollapsed.Add(FGroups[i].Key);
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.ToggleSortColumn(ACol: Integer);
begin
  if ACol <> FSortCol then
    SortByColumn(ACol, sdAscending)
  else if FSortDir = sdAscending then
    SortByColumn(ACol, sdDescending)
  else
    SortByColumn(-1, sdAscending);   { 第三次点:回到原始顺序 }
end;


function TTyStringGrid.ActiveSelectionRect: TRect;
begin
  Result.Left   := Min(FSelAnchorCol, FCol);
  Result.Right  := Max(FSelAnchorCol, FCol);
  Result.Top    := Min(DataToDisplay(FSelAnchorRow), DataToDisplay(FRow));
  Result.Bottom := Max(DataToDisplay(FSelAnchorRow), DataToDisplay(FRow));
end;

{ 一格在不在某个矩形里。整行/整列模式下另一轴不参与判定 —— 选中就是整条。 }
function TyGridRectHolds(const R: TRect; ACol, ADisplayRow: Integer;
  AMode: TTyGridSelectionMode): Boolean;
begin
  case AMode of
    gsmRow:    Result := (ADisplayRow >= R.Top) and (ADisplayRow <= R.Bottom);
    gsmColumn: Result := (ACol >= R.Left) and (ACol <= R.Right);
  else         Result := (ACol >= R.Left) and (ACol <= R.Right)
                     and (ADisplayRow >= R.Top) and (ADisplayRow <= R.Bottom);
  end;
end;

function TTyStringGrid.IsCellSelected(ACol, ARow: Integer): Boolean;
var
  rp, i: Integer;
begin
  Result := False;
  if (ACol < 0) or (ARow < 0) then Exit;
  rp := DataToDisplay(ARow);
  if rp < 0 then Exit;               { 被筛掉的行不参与 }

  { 活动矩形 + 已提交的离散矩形。FSelRects 为空时就是从前的单矩形行为。 }
  if TyGridRectHolds(ActiveSelectionRect, ACol, rp, FSelectionMode) then Exit(True);
  for i := 0 to High(FSelRects) do
    if TyGridRectHolds(FSelRects[i], ACol, rp, FSelectionMode) then Exit(True);
end;

procedure TTyStringGrid.CommitActiveSelection;
var
  n: Integer;
begin
  n := Length(FSelRects);
  SetLength(FSelRects, n + 1);
  FSelRects[n] := ActiveSelectionRect;
end;

procedure TTyStringGrid.SelectionChanged;
begin
  Invalidate;
  if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
end;

procedure TTyStringGrid.SelectAll;
begin
  SetLength(FSelRects, 0);
  if (Header.Columns.Count = 0) or (RowCount = 0) then Exit;
  FSelAnchorCol := 0;
  FSelAnchorRow := DisplayToData(0);
  FCol := Header.Columns.Count - 1;
  FRow := DisplayToData(DisplayRowCount - 1);
  SelectionChanged;
end;

procedure TTyStringGrid.SelectRange(ACol1, ARow1, ACol2, ARow2: Integer);

  function ClampCol(AValue: Integer): Integer;
  begin
    Result := AValue;
    if Result < 0 then Result := 0;
    if Result > Header.Columns.Count - 1 then Result := Header.Columns.Count - 1;
  end;

  function ClampRow(AValue: Integer): Integer;
  begin
    Result := AValue;
    if Result < 0 then Result := 0;
    if Result > RowCount - 1 then Result := RowCount - 1;
  end;

begin
  if (Header.Columns.Count = 0) or (RowCount = 0) then Exit;
  SetLength(FSelRects, 0);
  FSelAnchorCol := ClampCol(ACol1);
  FSelAnchorRow := ClampRow(ARow1);
  FCol := ClampCol(ACol2);
  FRow := ClampRow(ARow2);
  SelectionChanged;
end;

procedure TTyStringGrid.SelectRows(ARow1, ARow2: Integer);
begin
  if Header.Columns.Count = 0 then Exit;
  SelectRange(0, ARow1, Header.Columns.Count - 1, ARow2);
end;

procedure TTyStringGrid.ClearSelection;
begin
  SetLength(FSelRects, 0);
  { 选区收缩成光标所在的那一格 —— 网格总有一个当前格,"什么都没选"不是它的状态。 }
  AnchorSelection;
  SelectionChanged;
end;

function TTyStringGrid.Selection: TRect;
var
  r: TRect;
begin
  r := ActiveSelectionRect;
  { 对外一律用**数据行**坐标:显示序是内部表示,宿主拿到手要能直接索引 Cells。 }
  Result.Left := r.Left;
  Result.Right := r.Right;
  Result.Top := DisplayToData(r.Top);
  Result.Bottom := DisplayToData(r.Bottom);
end;

{ 选区聚合的公共骨架:走一遍选区,把能解析成数值的格喂给累加器。
  四个入口共用它,免得四份几乎一样的遍历各自跑偏。 }
procedure TTyStringGrid.ForEachSelectedNumber(out ACount: Integer;
  out ASum, AMin, AMax: Double);
var
  pos, colIdx, dataRow: Integer;
  v: Double;
  txt: string;
begin
  ACount := 0;
  ASum := 0;
  AMin := 0;
  AMax := 0;
  for pos := 0 to DisplayRowCount - 1 do
  begin
    dataRow := DisplayToData(pos);
    if dataRow < 0 then Continue;
    for colIdx := 0 to Header.Columns.Count - 1 do
    begin
      if not IsCellSelected(colIdx, dataRow) then Continue;
      txt := Trim(GetCellText(colIdx, dataRow));
      if txt = '' then Continue;
      v := StrToFloatDef(txt, NaN);
      if IsNan(v) then Continue;      { 非数值格跳过,不污染统计 }
      if ACount = 0 then
      begin
        AMin := v;
        AMax := v;
      end
      else
      begin
        if v < AMin then AMin := v;
        if v > AMax then AMax := v;
      end;
      ASum := ASum + v;
      Inc(ACount);
    end;
  end;
end;

function TTyStringGrid.SelectionSum: Double;
var n: Integer; mn, mx: Double;
begin
  ForEachSelectedNumber(n, Result, mn, mx);
end;

function TTyStringGrid.SelectionAvg: Double;
var n: Integer; sum, mn, mx: Double;
begin
  ForEachSelectedNumber(n, sum, mn, mx);
  if n = 0 then Result := 0 else Result := sum / n;
end;

function TTyStringGrid.SelectionMin: Double;
var n: Integer; sum, mx: Double;
begin
  ForEachSelectedNumber(n, sum, Result, mx);
end;

function TTyStringGrid.SelectionMax: Double;
var n: Integer; sum, mn: Double;
begin
  ForEachSelectedNumber(n, sum, mn, Result);
end;

function TTyStringGrid.SelectedCellCount: Integer;
var
  pos, colIdx, dataRow: Integer;
begin
  { 逐格数而不是把矩形面积加起来 —— 离散矩形可能互相重叠,加面积会重复计数。 }
  Result := 0;
  for pos := 0 to DisplayRowCount - 1 do
  begin
    dataRow := DisplayToData(pos);
    if dataRow < 0 then Continue;
    for colIdx := 0 to Header.Columns.Count - 1 do
      if IsCellSelected(colIdx, dataRow) then Inc(Result);
  end;
end;

procedure TTyStringGrid.AnchorSelection;
begin
  FSelAnchorCol := FCol;
  FSelAnchorRow := FRow;
end;


{ 取网格自己的列类。列可能还没建、或(理论上)不是网格列类,此时返回 nil。 }
function TTyCustomGrid.GridColumn(ACol: Integer): TTyGridColumn;
begin
  Result := nil;
  if (ACol < 0) or (ACol >= FHeader.Columns.Count) then Exit;
  if FHeader.Columns.Items[ACol] is TTyGridColumn then
    Result := TTyGridColumn(FHeader.Columns.Items[ACol]);
end;

function TTyStringGrid.EditorKindFor(ACol, ARow: Integer): TTyGridEditorKind;
var
  c: TTyGridColumn;
begin
  { 优先级:**列属性 > OnGetEditorKind > DefaultEditorKind**。
    列属性在下面(先取),事件在最后 —— 事件是逐格的、比列级更具体,所以它最终说了算;
    而列级比网格级的默认值具体,所以压过 DefaultEditorKind。

    "有没有显式设过"用 UseEditorKind 记,不能光看"等于 gekText" ——
    那样分不清"没设"和"显式设成文本"。 }
  { 逐格只读优先于一切 —— 它是最具体的那一层("这一格不能改")。 }
  if GetCellReadOnly(ACol, ARow) then Exit(gekNone);

  Result := FDefaultEditorKind;
  c := GridColumn(ACol);
  if (c <> nil) then
  begin
    if c.ReadOnly then Result := gekNone
    else if c.UseEditorKind then Result := c.EditorKind;
  end;
  if Assigned(FOnGetEditorKind) then FOnGetEditorKind(Self, ACol, ARow, Result);
end;

function TTyStringGrid.BeginEdit: Boolean;
begin
  Result := BeginEdit(FCol, FRow);
end;

function TTyStringGrid.BeginEdit(ACol, ARow: Integer): Boolean;
var
  r: TRect;
begin
  Result := False;
  if FReadOnly or (not Enabled) then Exit;
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  if (ARow < 0) or (ARow >= RowCount) then Exit;
  if EditorKindFor(ACol, ARow) = gekNone then Exit;

  { 先把光标移过去 —— 编辑的永远是当前格,避免"编辑一格、高亮另一格"。 }
  if (ACol <> FCol) or (ARow <> FRow) then
  begin
    MoveCursor(ACol, ARow);
    if (FCol <> ACol) or (FRow <> ARow) then Exit;   { 被 OnSelectCell 否决 }
  end;

  { 勾选框不弹编辑器 —— 点一下直接切换,这才是勾选框该有的手感。 }
  if EditorKindFor(ACol, ARow) = gekCheckBox then
  begin
    ToggleCellChecked(FCol, FRow);
    Result := True;
    Exit;
  end;

  { 星级同理:值直接由"点了第几颗星"决定,弹个数值框让人输数字太别扭。
    真正的赋值在 MouseDown 里(它才知道点在哪颗星上);这里只是不拦着。 }
  if EditorKindFor(ACol, ARow) = gekRating then
  begin
    Result := True;
    Exit;
  end;

  { 编辑器盖在**可见**矩形上:被冻结带盖住的部分本来就不该露出编辑框。 }
  r := CellVisibleRect(FCol, FRow);
  if IsRectEmpty(r) then Exit;

  FEditCol := FCol;
  FEditRow := FRow;

  { 先问宿主要不要用自己的编辑器。给了就整格交给它,内建那几种一概不出场。 }
  FEditLink := nil;
  if Assigned(FOnCreateEditLink) then FOnCreateEditLink(Self, FCol, FRow, FEditLink);
  if FEditLink <> nil then
  begin
    FEditLinkCtl := FEditLink.CreateEditor(Self, FCol, FRow);
    if FEditLinkCtl = nil then
    begin
      FEditLink := nil;      { 宿主临时改主意 —— 当作没编辑 }
      Exit;
    end;
    FEditLink.SetBounds(r);
    FEditLink.SetValue(Cells[FCol, FRow]);
    FEditLink.FocusEditor;
    FEditing := True;
    Result := True;
    Exit;
  end;
  if EditorKindFor(FCol, FRow) = gekColor then
  begin
    { 颜色是模态对话框,不是驻留编辑器 —— 选完直接写回,不进编辑态。 }
    ToggleCellColor(FCol, FRow);
    Result := True;
    Exit;
  end;

  if EditorKindFor(FCol, FRow) = gekDate then
  begin
    FDateEditor.Controller := Self.Controller;
    FDateEditor.Date := StrToDateDef(Cells[FCol, FRow], SysUtils.Date);
    FDateEditor.BoundsRect := r;
    FDateEditor.Visible := True;
    if HandleAllocated and FDateEditor.CanFocus then FDateEditor.SetFocus;
    FEditing := True;
    Result := True;
    Exit;
  end;

  if EditorKindFor(FCol, FRow) = gekPickList then
  begin
    FPickEditor.Controller := Self.Controller;
    FPickEditor.Items.Clear;
    { 列级候选项打底,宿主事件可以再改 —— 不接事件也能在设计期把下拉配好。 }
    if GridColumn(FCol) <> nil then FPickEditor.Items.Assign(GridColumn(FCol).PickList);
    if Assigned(FOnGetPickList) then FOnGetPickList(Self, FCol, FRow, FPickEditor.Items);
    FPickEditor.ItemIndex := FPickEditor.Items.IndexOf(Cells[FCol, FRow]);
    FPickEditor.BoundsRect := r;
    FPickEditor.Visible := True;
    if HandleAllocated and FPickEditor.CanFocus then FPickEditor.SetFocus;
    FEditing := True;
    Result := True;
    Exit;
  end;

  { --- 数值微调 --- }
  if EditorKindFor(FCol, FRow) = gekSpin then
  begin
    FSpinEditor.Controller := Self.Controller;
    FSpinEditor.MinValue := EditorMinFor(FCol);
    FSpinEditor.MaxValue := EditorMaxFor(FCol);
    FSpinEditor.Value := StrToIntDef(Trim(Cells[FCol, FRow]), FSpinEditor.MinValue);
    FSpinEditor.BoundsRect := r;
    FSpinEditor.Visible := True;
    if HandleAllocated and FSpinEditor.CanFocus then FSpinEditor.SetFocus;
    FEditing := True;
    Result := True;
    Exit;
  end;

  { --- 滑动条 --- }
  if EditorKindFor(FCol, FRow) = gekSlider then
  begin
    FSliderEditor.Controller := Self.Controller;
    { 格子里的滑块必须显示数值 —— 只有一个滑块的话,拖到哪儿了根本读不出来。 }
    FSliderEditor.ShowValue := True;
    FSliderEditor.Min := EditorMinFor(FCol);
    FSliderEditor.Max := EditorMaxFor(FCol);
    FSliderEditor.Position := StrToIntDef(Trim(Cells[FCol, FRow]), FSliderEditor.Min);
    FSliderEditor.BoundsRect := r;
    FSliderEditor.Visible := True;
    if HandleAllocated and FSliderEditor.CanFocus then FSliderEditor.SetFocus;
    FEditing := True;
    Result := True;
    Exit;
  end;

  { --- 多行文本 --- }
  if EditorKindFor(FCol, FRow) = gekMemo then
  begin
    FMemoEditor.Controller := Self.Controller;
    FMemoEditor.Text := Cells[FCol, FRow];
    { 多行编辑器往下撑开一些,否则一行高的格里根本看不出是多行。 }
    FMemoEditor.BoundsRect := Rect(r.Left, r.Top, r.Right,
      Max(r.Bottom, r.Top + ScaleI(72)));
    FMemoEditor.Visible := True;
    if HandleAllocated and FMemoEditor.CanFocus then FMemoEditor.SetFocus;
    FEditing := True;
    Result := True;
    Exit;
  end;

  { --- 时间:与日期共用同一个选择器,只是把 Kind 切成 dtkTime --- }
  if EditorKindFor(FCol, FRow) = gekTime then
  begin
    FDateEditor.Controller := Self.Controller;
    FDateEditor.Kind := dtkTime;
    FDateEditor.DateTime := StrToTimeDef(Cells[FCol, FRow], SysUtils.Time);
    FDateEditor.BoundsRect := r;
    FDateEditor.Visible := True;
    if HandleAllocated and FDateEditor.CanFocus then FDateEditor.SetFocus;
    FEditing := True;
    Result := True;
    Exit;
  end;

  { --- 带计算器的数值 --- }
  if EditorKindFor(FCol, FRow) = gekCalculator then
  begin
    FCalcEditor.Controller := Self.Controller;
    FCalcEditor.Text := Cells[FCol, FRow];
    FCalcEditor.BoundsRect := r;
    FCalcEditor.Visible := True;
    if HandleAllocated and FCalcEditor.CanFocus then FCalcEditor.SetFocus;
    FEditing := True;
    Result := True;
    Exit;
  end;

  { --- 掩码 --- }
  if EditorKindFor(FCol, FRow) = gekMask then
  begin
    FMaskEditor.Controller := Self.Controller;
    FMaskEditor.Mask := EditMaskFor(FCol);
    FMaskEditor.Text := Cells[FCol, FRow];
    FMaskEditor.BoundsRect := r;
    FMaskEditor.Visible := True;
    if HandleAllocated and FMaskEditor.CanFocus then FMaskEditor.SetFocus;
    FEditing := True;
    Result := True;
    Exit;
  end;

  FEditor.Controller := Self.Controller;
  { 密码列遮字;其余列不遮(每次都要显式设回去,否则上一格的遮罩会留下来)。 }
  if EditorKindFor(FCol, FRow) = gekPassword then FEditor.PasswordChar := '*'
  else FEditor.PasswordChar := '';
  { 大小写强制来自列(对标 edUpperCase / edLowerCase)。 }
  FEditor.CharCase := CharCaseFor(FCol);
  { 数值列右对齐。按键级的数字过滤要等 ValueListEditor 的 TTyValueEdit 泛化出来后再接;
    在那之前由 EndEdit 在**提交时**校验,非法值直接不写回。 }
  if EditorKindFor(FCol, FRow) = gekNumeric then
    FEditor.Alignment := taRightJustify
  else
    FEditor.Alignment := taLeftJustify;
  FEditor.Text := Cells[FCol, FRow];
  FEditor.MaxLength := MaxEditLengthFor(FCol, FRow);
  FEditor.BoundsRect := r;
  FEditor.Visible := True;
  if HandleAllocated and FEditor.CanFocus then FEditor.SetFocus;
  FEditing := True;
  Result := True;
end;

procedure TTyStringGrid.EndEdit(ACommit: Boolean);
var
  oldTxt, newTxt: string;
  accept: Boolean;
  usePick, useDate, useLink, useSpin, useSlider, useMemo, useMask, useCalc: Boolean;
  linkTxt: string;
begin
  usePick := False;
  useDate := False;
  useSpin := False;
  useSlider := False;
  useMemo := False;
  useMask := False;
  useCalc := False;
  useLink := False;
  linkTxt := '';
  if not FEditing then Exit;
  if FEndingEdit then Exit;          { 重入守卫:提交里若又触发提交会写两次 }
  FEndingEdit := True;
  try
    FEditing := False;

    { 宿主 EditLink:先把值取出来再释放控件 —— 反了就取到已销毁控件上了。 }
    if FEditLink <> nil then
    begin
      useLink := True;
      linkTxt := FEditLink.GetValue;
      FEditLink.ReleaseEditor;
      FEditLink := nil;
      FEditLinkCtl := nil;
    end;
    if FPickEditor.Visible then
    begin
      FPickEditor.Visible := False;
      usePick := True;
    end;
    if FSpinEditor.Visible then
    begin
      FSpinEditor.Visible := False;
      useSpin := True;
    end;
    if FSliderEditor.Visible then
    begin
      FSliderEditor.Visible := False;
      useSlider := True;
    end;
    if FMemoEditor.Visible then
    begin
      FMemoEditor.Visible := False;
      useMemo := True;
    end;
    if FMaskEditor.Visible then
    begin
      FMaskEditor.Visible := False;
      useMask := True;
    end;
    if FCalcEditor.Visible then
    begin
      FCalcEditor.Visible := False;
      useCalc := True;
    end;
    if FDateEditor.Visible then
    begin
      FDateEditor.Visible := False;
      useDate := True;
    end;
    FEditor.Visible := False;
    if ACommit then
    begin
      oldTxt := Cells[FEditCol, FEditRow];
      if useLink then
        newTxt := linkTxt
      else if useSpin then
        newTxt := IntToStr(FSpinEditor.Value)
      else if useSlider then
        newTxt := IntToStr(FSliderEditor.Position)
      else if useMemo then
        newTxt := FMemoEditor.Text
      else if useMask then
        newTxt := FMaskEditor.Text
      else if useCalc then
        newTxt := FCalcEditor.Text
      else if useDate then
        newTxt := DateToStr(FDateEditor.Date)
      else if usePick then
      begin
        if FPickEditor.ItemIndex >= 0 then
          newTxt := FPickEditor.Items[FPickEditor.ItemIndex]
        else
          newTxt := oldTxt;
      end
      else
        newTxt := FEditor.Text;
      if newTxt <> oldTxt then
      begin
        accept := True;
        { 数值列:非法值一律不写回(总比把 'abc' 存进金额列强)。 }
        if (EditorKindFor(FEditCol, FEditRow) = gekNumeric)
           and (newTxt <> '') and (StrToFloatDef(newTxt, MaxDouble) = MaxDouble) then
          accept := False;
        if Assigned(FOnCellEdited) then
          FOnCellEdited(Self, FEditCol, FEditRow, oldTxt, newTxt, accept);
        if accept then Cells[FEditCol, FEditRow] := newTxt;
      end;
    end;
    Invalidate;
  finally
    FEndingEdit := False;
  end;
end;

procedure TTyStringGrid.DateEditorExit(Sender: TObject);
begin
  EndEdit(True);
end;

procedure TTyStringGrid.PickEditorChange(Sender: TObject);
begin
  { 选中即提交 —— 下拉不像文本框那样需要按 Enter 确认。 }
  if FEditing then EndEdit(True);
end;

procedure TTyStringGrid.PickEditorExit(Sender: TObject);
begin
  EndEdit(True);
end;

procedure TTyStringGrid.EditorKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_RETURN: begin EndEdit(True);  Key := 0; if CanFocus then SetFocus; end;
    VK_ESCAPE: begin EndEdit(False); Key := 0; if CanFocus then SetFocus; end;
  end;
end;

procedure TTyStringGrid.EditorExit(Sender: TObject);
begin
  { 焦点离开 = 提交。与库内其他内联编辑一致:凡是会让单元格移动/失焦的动作,先提交。 }
  EndEdit(True);
end;

procedure TTyStringGrid.DblClick;
begin
  inherited DblClick;
  { 只有双击**单元格**才进编辑。行号槽、列头、末行以下的空白都不是格子 ——
    在那些地方双击时用户的手根本没碰当前光标格。 }
  if FLastDownHit.Part = ghpCell then BeginEdit;
end;

procedure TTyStringGrid.RenderCells(P: TTyPainter; const M: TTyGridMetrics;
  const AFrame: TTyStyleSet);
var
  slot: Integer;   { 绘制槽位 }
  selS, markS: TTyStyleSet;
  vis: TRect;
  firstRow, lastRow, pos, dataRow, colIdx, gIdx: Integer;
begin
  { 先铺整个选区的底色,再让基类把文字画上去 —— 次序反了字会被底色盖掉。
    只遍历可视窗口内的行,所以选区再大也不影响绘制开销。 }
  { 选区底色**只由"这一格被选中"决定**,绝不掺入网格自身的 CurrentStates。

    掺进去的后果是肉眼可见的:鼠标从网格上移开的一瞬间,控件的 tysHover 退出
    状态集,选区底色被重新解析成另一个值 —— 选中的格"闪一下"。
    (与当初勾选框闪烁同一个 bug:那次是鼠标按下让整个网格进 :active,
    满屏未勾选的框集体变样。单元格的外观只该由格自己的状态决定。) }
  selS := ActiveController.Model.ResolveStyle('TyGridCell', StyleClass,
    [tysSelected]);
  { 盖在"用户显式指定了底色"的格上时改用半透明层。选区底色是不透明的 accent,
    直接铺上去会把用户自己标的颜色**整块抹掉** —— 而光标总是落在刚上色的那一格上,
    于是"上了色却什么都没变"。半透明层让两者都读得出来。 }
  markS := ActiveController.Model.ResolveStyle('TyGridCellMarked', StyleClass, []);
  if tpBackground in selS.Present then
    if TyGridDrawSlots(M, firstRow, lastRow) then
      for slot := firstRow to lastRow do
      begin
        pos := TyGridRowAtSlot(slot, M);
        if pos < 0 then Continue;
        dataRow := DisplayToData(pos);
        for colIdx := 0 to Header.Columns.Count - 1 do
        begin
          if not IsCellSelected(colIdx, dataRow) then Continue;
          vis := CellVisibleRect(colIdx, dataRow);
          if IsRectEmpty(vis) then Continue;
          if CellAppearance(colIdx, dataRow, pos, AFrame).HasExplicitBackground
            and (tpBackground in markS.Present) then
            P.FillBackground(vis, markS.Background, 0)
          else
            P.FillBackground(vis, selS.Background, 0);
        end;
      end;
  { 分组行:整行一条横带,画"值(计数)"和折叠三角。它不对应任何数据行,
    所以必须在普通单元格之前处理掉,否则基类会拿 -1 去取内容。 }
  if (FGroupCol >= 0) and TyGridDrawSlots(M, firstRow, lastRow) then
    for slot := firstRow to lastRow do
    begin
      pos := TyGridRowAtSlot(slot, M);
      if (pos >= 0) and IsGroupRow(pos, gIdx) then
        RenderGroupRow(P, pos, gIdx, M, AFrame);
    end;

  { 勾选框列自己画方块 —— 基类只会画文字,而 '1'/'' 直接显示出来毫无意义。 }
  if TyGridDrawSlots(M, firstRow, lastRow) then
    for slot := firstRow to lastRow do
    begin
      pos := TyGridRowAtSlot(slot, M);
      if pos < 0 then Continue;
      dataRow := DisplayToData(pos);
      if dataRow < 0 then Continue;
      for colIdx := 0 to Header.Columns.Count - 1 do
      begin
        if EditorKindFor(colIdx, dataRow) = gekCheckBox then
          RenderCheckCell(P, colIdx, dataRow, AFrame);
        { 省略号按钮画在文字**之上**(它贴着右缘,文字该为它让位由列宽决定)。 }
        if EditorKindFor(colIdx, dataRow) = gekEllipsis then
          RenderEllipsisCell(P, colIdx, dataRow, AFrame);
        case CellDisplayFor(colIdx, dataRow) of
          gcdProgress: RenderProgressCell(P, colIdx, dataRow, AFrame);
          gcdRating:   RenderRatingCell(P, colIdx, dataRow, AFrame);
          gcdImage:    RenderImageCell(P, colIdx, dataRow, AFrame);
          gcdButton:   RenderButtonCell(P, colIdx, dataRow,
                         GetCellText(colIdx, dataRow), AFrame);
          gcdColor:    RenderColorCell(P, colIdx, dataRow, AFrame);
        end;
      end;
    end;
  inherited RenderCells(P, M, AFrame);
end;

initialization
  { 设计器与 .lfm 流式化按类名查类,必须登记。 }
  RegisterClasses([TTyCustomGrid, TTyDrawGrid, TTyStringGrid]);
  TyGridCheckedWord := rsGridCheckedWord;

end.
