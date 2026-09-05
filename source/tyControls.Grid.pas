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
{ 嵌套过程可以当值传 —— DrawInRowBand 靠它把"绘制动作"收进一个统一的裁剪入口,
  而绘制动作要读绘制循环里的局部变量。 }
{$modeswitch nestedprocvars}

interface

uses
  Classes, SysUtils, ImgList, Types, Math, contnrs, Clipbrd, Controls, Graphics, LCLType, LMessages, StdCtrls,
  ExtCtrls, LazUTF8,
  BGRABitmap, BGRABitmapTypes, BGRATextBidi,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Columns,
  tyControls.ScrollBar, tyControls.Edit, tyControls.ComboBox, tyControls.DateTimePicker, tyControls.Popover, tyControls.CheckListBox, tyControls.ColorMath,
  tyControls.SpinEdit, tyControls.TrackBar, tyControls.Memo, tyControls.MaskEdit,
  tyControls.CalcEdit, tyControls.Panel, tyControls.Button, tyControls.CheckBox,
  tyControls.Css.Values, tyControls.ImageCollection, tyControls.ImageDraw, tyControls.Dialogs.Color,
  tyControls.StrConsts, tyControls.Controller,
  tyControls.Grid.Layout, tyControls.Grid.Csv;

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
    { **这个下拉不镜像。** 它下面那行 PaintItemContent 把计数列钉在 ARowRect.Right,
      而基类的勾选框槽是 TyCheckBoxSlotRect 从行的**起点**那一侧算的 —— 镜像之后
      两者会挤到同一边:计数压在勾选框上。收口成一个来源之前不该动它,
      而这一句就是那个决定(与 TTyValueListEditor 同样的围栏,见 5c2ceca)。 }
    function RtlRowLayout: Boolean; override;
  public
    procedure SetCounts(const ACounts: array of Integer);
  end;

  { 滚动条三态。"隐藏"只管**显示**,不管能不能滚 ——
    把"不显示"做成"不能滚"是这类开关最常见的错。 }
  TTyGridScrollBarMode = (gsbAuto, gsbAlways, gsbNever);

  { 背景图怎么铺 / 铺到哪。 }
  TTyGridBackgroundMode  = (gbmTile, gbmStretch, gbmCenter);
  TTyGridBackgroundScope = (gbsWholeGrid, gbsBodyOnly);

  TTyGridCellDisplay = (
    gcdText,      { 默认:文字 }
    gcdProgress,  { 进度条,值取 0..100 }
    gcdRating,    { 评分星,值取 0..5 }
    gcdImage,     { 图片:值是 Images 里的索引 }
    gcdButton,    { 按钮:文字是按钮标题,点击走 OnCellButtonClick }
    gcdHyperlink, { 超链接:带下划线的强调色,悬停手型,点击走 OnCellLinkClick。
                    视觉全走 TyGridHyperlink 这个 typeKey —— 不硬编码蓝色。 }
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

  { 选区能不能有**好几块**。对标 LCL 的 TRangeSelectMode(grids.pas:150)。
    与 TTyGridSelectionMode 正交:那个说的是"一块选区的粒度是格/行/列",
    这个说的是"能不能同时有好几块"。 }
  TTyGridRangeSelectMode = (rsmSingle, rsmMulti);

  { 行为开关的集合,对标 LCL 的 TGridOption(grids.pas:86)。

    **只收我们真的照办的标志。** LCL 有 32 个;这里 21 个。少掉的 11 个不是
    漏了 —— 是"发布了却不照办"这一类缺陷的唯一防法:一个存在于类型里、
    IDE 里勾得动、控件却当没看见的标志,比根本没有它更坏,因为用户会
    以为自己已经关掉了某个行为。逐条的去留理由与 seam 在
    docs/controls/grid.md 的对照表里。

    **一半的标志在别处已经有名字了。** goColSizing 就是
    `Header.Options` 里的 hoColumnResize,goEditing 就是 `ReadOnly` 取反,
    goRowSelect 就是 `SelectionMode = gsmRow`。这些位在这里**不另存一份** ——
    Options 读它们、写它们,但真相始终只有一处(见 TyGridDerivedOptions
    与 GetOptions/SetOptions)。两处存储一个行为,结果必然是设计器说一套、
    控件做另一套。

    **只增不改序。** 集合成员在 .lfm 里是按**名字**写的(TWriter.WriteSet 走
    GetEnumName),所以插一个成员不会让老窗体读错;但**改名或删名**会让老
    窗体在加载时抛 "Invalid property value",而序号仍然被编译期的 default
    子句和一切 Integer() 强转吃进去。所以:只在末尾追加,不改名、不删除。
    test.grid.options 里的 OptionOrdinalsAreAppendOnly 钉着这条。 }
  TTyGridOption = (
    goVertLine,            { 纵向格线 —— GridLineStyle 的视图 }
    goHorzLine,            { 横向格线 —— GridLineStyle 的视图 }
    goRangeSelect,         { 鼠标/Shift 能拉出一块矩形选区;关掉只剩当前格 }
    goDrawFocusSelected,   { 焦点格在选区里也照画 —— ShowFocusCell 的视图 }
    goRowSizing,           { 在行头槽里拖分隔线改行高(仍需 ShowIndicator) }
    goColSizing,           { 在列头里拖分隔线改列宽 —— hoColumnResize 的视图 }
    goRowMoving,           { 在行头槽里拖动整行重排(仍需 ShowIndicator) }
    goColMoving,           { 拖动列头重排列 —— hoDrag 的视图 }
    goEditing,             { 用户手势能改数据(编辑器 + 粘贴/剪切/填充柄)——
                             ReadOnly 的**反**视图,范围见 ReadOnly 声明处 }
    goTabs,                { Tab 在格之间走;关掉则 Tab 把焦点交给下一个控件 }
    goRowSelect,           { 整行选择 —— SelectionMode = gsmRow 的视图 }
    goDblClickAutoSize,    { 双击列分隔线按内容适宽 }
    goFixedRowNumbering,   { 行头槽里画行号 —— ShowRowNumbers 的视图 }
    goScrollKeepVisible,   { 滚动时把光标格拖进新视口 }
    goHeaderHotTracking,   { 鼠标下的列头段点亮 —— hoHotTrack 的视图 }
    goFixedColSizing,      { 冻结列也能改宽 }
    goDontScrollPartCell,  { 点一个半露的格时**不**把它滚进来 }
    goCellHints,           { 逐格提示(批注 + OnGetCellHint) }
    goTruncCellHints,      { 文字放不下时用完整文本当提示 }
    goCellEllipsis,        { 放不下的单行文字末尾加"…";关掉则硬裁 }
    goRowHighlight,        { 高亮光标所在的整行 }
    { 按住的列头段画成"按下去"的样子。**追加在末尾**(见上面的序号约定)。
      自有位,不是视图:按下态的观感在别处没有第二个开关,FDragCol 也不是它 ——
      那个字段只有在 hoDrag 且该列 coDraggable 时才置位,而"按住了"与"能不能拖"
      是两件事。出厂**关**:这个观感以前根本不存在,默认开会改掉每一张现有窗体,
      而这个属性是来描述现状的,不是来偷偷改现状的。 }
    goHeaderPushedLook,
    { 拖滑块时是不是**边拖边滚**。**追加在末尾**(见上面的序号约定)。

      派生位,真相在两条内嵌滚动条的 `LiveTracking` 上 —— 见 TyGridDerivedOptions。
      关掉之后滑块照样跟手、`OnScroll(scTrack)` 照样发,但 `Position`/`OnChange`
      推迟到松手;方向键、翻页、滚轮不受影响(它们是离散步,原生滚动条也不推迟)。
      出厂**开**:滚动条一直就是实时滚的,出厂值描述现状,不改现状。 }
    goThumbTracking
  );
  TTyGridOptions = set of TTyGridOption;

const
  { **别处已经有名字**的那些位。Options 对它们只是一个视图:
    读的时候现算,写的时候推回它们真正的属性去,`FOptions` 里**从不**留副本。

    这条边界是整个设计的支点。留副本的话,`GridLineStyle := glsNone` 之后
    `Options` 里还挂着 goVertLine,设计器于是显示"纵线开着"而屏幕上一根没有
    —— 一个行为两处存储,永远会走岔。

    **无类型常量**(不是 `: TTyGridOptions = ...`):published 属性的 default
    子句只吃编译期常量,加了类型标注在 FPC 里就成了**变量**,那一行编译不过
    ("The default value of a property must be constant")。LCL 的
    DefaultGridOptions(grids.pas:189)是同一个写法。
    也因此这两个常量必须声明在 TTyCustomGrid **之前** —— Pascal 先声明后使用。 }
  TyGridDerivedOptions =
    [goVertLine, goHorzLine, goDrawFocusSelected, goColSizing, goColMoving,
     goEditing, goRowSelect, goFixedRowNumbering, goHeaderHotTracking,
     goThumbTracking];

  { 出厂值。**逐位复刻加这个属性之前的行为** —— 不是复刻 LCL 的
    DefaultGridOptions(grids.pas:189)。三处刻意与 LCL 不同,原因写在
    docs/controls/grid.md 的对照表里:

      goDblClickAutoSize —— LCL 默认关,我们从来就是开的;
      goFixedColSizing   —— LCL 默认关,我们从来没挡过冻结列改宽;
      goCellEllipsis     —— LCL 默认关(硬裁),我们从来就加"…"。

    把这三位改成 LCL 的默认值等于给每一张现有窗体换行为,而这个属性
    本来是要**描述**现状的,不是要偷偷改现状。

    goVertLine/goHorzLine 跟着 GridLineStyle 的 glsBoth 走;
    goColSizing/goColMoving 跟着 TTyHeader 出厂的 [hoColumnResize, hoDrag] 走;
    goHeaderHotTracking 不在里面,因为 hoHotTrack 也不在列头的出厂集合里;
    goThumbTracking **在**里面,因为 TTyScrollBar 出厂 LiveTracking=True。
    这几位是**算出来的**,写在这里只是为了让 default 子句与新控件的实际读数
    一致 —— 不一致的话 TWriter 会漏写或多写。DefaultsMatchAFreshGrid 钉着它。 }
  TyDefaultGridOptions =
    [goVertLine, goHorzLine, goRangeSelect, goDrawFocusSelected, goRowSizing,
     goColSizing, goRowMoving, goColMoving, goEditing, goTabs,
     goDblClickAutoSize, goFixedColSizing, goCellHints, goCellEllipsis,
     goThumbTracking];

type
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
    FText:      TCaption;
    FFirstCol:  Integer;
    FLastCol:   Integer;
    FLevel:     Integer;
    FAlignment: TAlignment;
    procedure Changed;
    procedure SetText(const AValue: TCaption);
    procedure SetFirstCol(AValue: Integer);
    procedure SetLastCol(AValue: Integer);
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(ASource: TPersistent); override;
  published
    property Text: TCaption read FText write SetText;
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
    gfoLessEqual,
    { 闭区间(两端都算),按数值比。值里用 TyFilterRangeSep 分隔两个边界。
      为什么是一个独立的比较方式而不是拆成两条 >=/<= :同列多条件之间是 **OR**,
      拆开就变成 OR 了,区间的语义正好相反。 }
    gfoBetween);

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
    FValidChars: string;
    FMaxEditLength: Integer;
    FSortKind: TTyGridSortKind;
    FMinValue: Integer;
    FMaxValue: Integer;
    FEditMask: string;
    FCharCase: TEditCharCase;
    FDropDownWidth: Integer;
    FUseEditorKind: Boolean;
    FCellDisplay: TTyGridCellDisplay;
    FUseCellDisplay: Boolean;
    FColor:      TTyColor;
    FLayout:     TTextLayout;
    FValueChecked:   string;
    FValueUnchecked: string;
    procedure SetPickList(AValue: TStrings);
    procedure SetEditorKind(AValue: TTyGridEditorKind);
    procedure SetCellDisplay(AValue: TTyGridCellDisplay);
    procedure SetColor(AValue: TTyColor);
    procedure SetLayout(AValue: TTextLayout);
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
    { gekPickList 下拉的宽度(逻辑像素)。0 = 跟列宽走。
      窄列上的下拉按列宽显示会把候选项截成一小截,这时单独放宽它就够了 ——
      不必为了看清候选去改列宽。 }
    property DropDownWidth: Integer read FDropDownWidth write FDropDownWidth
      default 0;
    { 输入时强制大小写(对标 AdvGrid 的 edUpperCase / edLowerCase)。 }
    property CharCase: TEditCharCase read FCharCase write FCharCase default ecNormal;
    { 只允许输入这些字符(空 = 不限)。按键级过滤,非法键直接不进编辑框。 }
    property ValidChars: string read FValidChars write FValidChars;
    { 编辑框最多输入几个字符(0 = 不限)。 }
    property MaxEditLength: Integer read FMaxEditLength write FMaxEditLength default 0;
    { 这一列的单元格怎么显示。设过之后压过 DefaultCellDisplay,低于逐格与事件。
      "有没有显式设过"用 UseCellDisplay 记 —— 光看"等于 gcdText"分不清
      "没设"和"显式设成文本"(与 UseEditorKind 一模一样的教训)。 }
    property CellDisplay: TTyGridCellDisplay
      read FCellDisplay write SetCellDisplay default gcdText;
    property UseCellDisplay: Boolean
      read FUseCellDisplay write FUseCellDisplay default False;
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
    { 整列的单元格底色。TyColorNone(0,默认)= 不指定,走主题。
      对标 LCL TGridColumn.Color (grids.pas:613)。

      为什么这不违反"视觉值必须走主题令牌":令牌管的是**控件自己**画成什么样,
      而这是宿主给自己的数据上色 —— 与 CellColors[c,r] / SetRowColor 完全同一类,
      那两个早就在了。缺的只是"整列"这一档,而它偏偏是唯一能在设计器里设的一档
      (从前只能写 OnGetCellStyle 事件代码)。

      优先级夹在斑马纹与逐格色之间:主题 → 斑马纹 → **列色** → 行色/格色 → 宿主钩子。
      越靠后越具体。列色不算 HasExplicitBackground —— 它是一整列的背景基调,
      不该像用户手工标黄的那一格那样去压住焦点格底色。 }
    property Color: TTyColor read FColor write SetColor default 0;
    { 整列的**垂直**对齐(Alignment 管水平)。对标 LCL TGridColumn.Layout
      (grids.pas:617)。从前 VAlign 在 CellAppearance 里写死 tlCenter,
      要改只能接 OnGetCellStyle —— 而 WordWrap 的长文本列想顶端对齐是常事。 }
    property Layout: TTextLayout read FLayout write SetLayout default tlCenter;
    { 这一列的勾选框在数据里写成什么。对标 LCL TGridColumn.ValueChecked /
      ValueUnchecked (grids.pas:627-630)。

      两个都留空(默认)时行为与从前**逐字节相同**:读认 1/true/yes/y 加一个全局的
      TyGridCheckedWord,写 '1' / ''。

      非空时这一列改说宿主的话。修的是写那一侧:ToggleCellChecked 从前不管这一列
      装的是 'Y'/'N' 还是 'true'/'false',一律写 '1' —— 也就是说用户点一下勾选框,
      宿主的数据词汇就被换掉了,而 OnCellEdited 的 ANewText 是 const,连改回来的
      口子都没有。读那一侧是**叠加**:先按本列词汇认,认不出再走内建宽松词表,
      所以已经能读对的表不会因为设了这一对而读错。

      三态的灰显仍写 '2':LCL 的这一对本来就只有两个词,给灰显再加第三个属性
      是本库自己的三态功能的事,不是这条对标的事。 }
    property ValueChecked: string read FValueChecked write FValueChecked;
    property ValueUnchecked: string read FValueUnchecked write FValueUnchecked;
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
  { --- 撤销栈 ---
    一条记录只记**逆操作需要的最小信息**:哪一格、改之前是什么。
    结构性操作(增删行)也落到这里 —— 它们搬单元格时走的就是 Cells[],
    于是自动被记下来;额外再记一条行数即可。 }
  { 排序怎么排。
      gsmDisplay —— 只置换**显示序**,数据一动不动(默认,今天的行为)。
      gsmData    —— 像 Excel 那样**真的把数据换位置**。排完显示序 == 数据序,
                    于是"排过序就不让合并/不让拖行"那几条限制自动失效。
    gsmData 只在**能安全做到**时才真的物理排:有筛选(会把筛掉的行一起搬)、
    有分组、或数据由回调提供(控件根本不持有数据)时一律退回 gsmDisplay 的行为。
    物理排序是可撤销的 —— 这也是它必须排在撤销功能之后做的原因。 }
  TTyGridSortMode = (gsmDisplay, gsmData);

  TTyGridUndoKind = (gukCell, gukRowCount, gukCellAttr, gukRowHeight,
                     gukRowHidden,
                     { 列结构。删列记 gukColDelete(带整列的快照,撤销 = 插回去),
                       插列记 gukColInsert(只需下标,撤销 = 删掉),
                       换位记 gukColMove。三者互为对方的反记录,所以重做也成立。 }
                     gukColDelete, gukColInsert, gukColMove);

  { 逐格属性的**值快照**。撤销栈不能存 TTyGridCellAttr 的引用 ——
    那个对象会被后来的 MoveEntry 就地改写、被 Remove 释放。

    **Obj 故意不在这里。** 这个栈是值语义的(上面那句就是它的立身之本),
    而 Obj 是宿主的指针、网格不拥有它:把它记进来,就等于允许一次 Ctrl+Z
    交还一个宿主在删掉那一行时已经释放掉的地址 —— 撤销变成 use-after-free,
    而且是网格无从察觉的那一种。代价是撤销**不**把对象槽搬回原位;
    那顶多是"槽位需要宿主照自己的数据重挂一遍",比崩溃便宜得多。
    RestoreAttr 因此也不许**销毁**对象槽,见那里。 }
  TTyGridAttrSnapshot = record
    Present:          Boolean;      { False = 当时这一格根本没有属性条目 }
    ColSpan, RowSpan: Integer;
    HasBackground:    Boolean;
    Background:       TTyColor;
    HasTextColor:     Boolean;
    TextColor:        TTyColor;
    HasAlignment:     Boolean;
    Alignment:        TAlignment;
    HasFontStyle:     Boolean;
    FontStyle:        TFontStyles;
    ReadOnly:         Boolean;
    HasCellDisplay:   Boolean;
    CellDisplay:      TTyGridCellDisplay;
    Comment:          string;
  end;

  { 一整列的**值快照**。撤销栈是值语义的(见 TTyGridAttrSnapshot 的说明),
    所以列也按值存,而不是往栈里塞一个 TTyGridColumn 引用 ——
    那会把对象所有权引进一个纯值的栈,而栈会被裁剪、会被清空。

    新增列属性时**这里要跟着加**,否则删了列再撤销,那个属性会悄悄回到默认值。
    (与 SaveLayoutToString 是同一类约定,但那边只需要"版式"三项,这边要的是
    列的全部身份 —— 两者刻意不共用,免得一边的需求改动牵连另一边。) }
  TTyGridColumnSnapshot = record
    Index:            Integer;      { 原来在第几列 }
    Width:            Integer;
    MinWidth:         Integer;
    MaxWidth:         Integer;
    Position:         Cardinal;
    Alignment:        TAlignment;
    CaptionAlignment: TAlignment;
    Text:             string;
    ImageIndex:       Integer;
    Options:          TTyColumnOptions;
    Tag:              NativeInt;
    { --- TTyGridColumn 自己的 --- }
    EditorKind:       TTyGridEditorKind;
    UseEditorKind:    Boolean;
    ReadOnly:         Boolean;
    PickList:         string;       { 换行分隔 }
    Aggregate:        TTyGridAggregate;
    ValidChars:       string;
    MaxEditLength:    Integer;
    SortKind:         TTyGridSortKind;
    MinValue:         Integer;
    MaxValue:         Integer;
    EditMask:         string;
    CharCase:         TEditCharCase;
    DropDownWidth:    Integer;
    { --- 那一列上的旁挂状态(按列记账的三张表) --- }
    FilterExpr:       string;
    ColFilter:        string;
    ValFilter:        string;
  end;

  TTyGridUndoEntry = record
    Kind:      TTyGridUndoKind;
    Col, Row:  Integer;
    OldText:   string;
    OldCount:  Integer;
    OldHeight: Integer;
    OldHidden: Boolean;
    AttrKey:   string;
    Attr:      TTyGridAttrSnapshot;
    { 列结构:gukColDelete 用 Col(插回哪儿)+ ColSnap(整列的身份);
      gukColInsert 只用 Col;gukColMove 用 Col(从)与 OldCount(到)。 }
    ColSnap:   TTyGridColumnSnapshot;
  end;

  { 属性存储"某一条即将被改动"的通知 —— 撤销记录点挂在它上面。 }
  TTyGridAttrChangingEvent = procedure(const AKey: string) of object;

  { 交给 DrawInRowBand 的绘制动作。用**嵌套过程**类型是因为它要读绘制循环里的
    局部变量(当前行、当前矩形),而这些东西没必要为了传参再抽一个记录出来。 }
  TTyGridBandDraw = procedure is nested;

  { 一次可撤销的操作 = 一串条目。批量操作(粘贴、填充、删行)天然是一条,
    因为它们本来就被 BeginUpdate/EndUpdate 包着。 }
  TTyGridUndoStep = array of TTyGridUndoEntry;

  { 编辑器**显示之前**交给宿主微调一下(改字体、限长、加自定义提示…)。
    拿到的是真正要用的那个控件。比"要么用内建、要么自己写一整个 EditLink"细一档。 }
  TTyGridEditorPropEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    AEditor: TControl) of object;

  { 用鼠标把某一行拖到别处之前问一句。置 AAllow := False 可否决。
    AFrom / ATo 都是**数据行**。 }
  TTyGridRowMoveEvent = procedure(Sender: TObject; AFrom, ATo: Integer;
    var AAllow: Boolean) of object;

  { --- 树形单元格(P8)---
    **控件不持有树**:层级与"有没有孩子"都由宿主回答,与虚拟数据源同一条道理。
    这样百万行的树也不需要控件先把整棵树建起来。 }
  TTyGridNodeLevelEvent = procedure(Sender: TObject; ARow: Integer;
    var ALevel: Integer) of object;
  TTyGridHasChildrenEvent = procedure(Sender: TObject; ARow: Integer;
    var AHas: Boolean) of object;

  { 拖填充柄产生的一次填充。宿主可以接管(自定义序列、跨列规则等):
    置 AHandled := True 之后控件就不再动数据了。 }
  TTyGridFillEvent = procedure(Sender: TObject; const ASource, ATarget: TRect;
    var AHandled: Boolean) of object;

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

  { --- B 组:编辑与否决钩子(T6-T10)--- }

  { 这一格能不能编辑。置 AAllow := False 拦下。
    刻意**不复用** OnGetEditorKind 返回 gekNone:那样连显示也一起改掉了
    (勾选框会退化成文本)。"不能改"和"没有编辑器"是两件事。 }
  TTyGridCanEditEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var AAllow: Boolean) of object;
  { 编辑器内容每变一次发一次(不是提交时)。宿主用它做即时校验/联动。 }
  TTyGridEditChangeEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    const AText: string) of object;
  { 插入 / 删除某一行之前问一句。置 AAllow := False 可否决。 }
  TTyGridCanRowEvent = procedure(Sender: TObject; ARow: Integer;
    var AAllow: Boolean) of object;
  { 非编辑态的回车 / Ctrl+回车。常见诉求:回车 = 打开明细。 }
  TTyGridCellKeyEvent = procedure(Sender: TObject; ACol, ARow: Integer) of object;
  { 拖纵向滚动条时的提示文字。返回空串 = 不显示提示。 }
  TTyGridScrollHintEvent = procedure(Sender: TObject; ARow: Integer;
    var AHint: string) of object;

  { 宿主接管某列的汇总值(中位数、加权平均、来自服务端的数……)。
    置 AHandled := True 之后控件就不再自己算了。 }
  TTyGridColumnCalcEvent = procedure(Sender: TObject; ACol: Integer;
    var AValue: Double; var AHandled: Boolean) of object;

  { 逐格显示格式化(T21)。只改**显示** —— 数据、编辑器里的值、导出
    一律用原值,否则一进编辑就看到格式化后的串,一提交就套两层。 }
  TTyGridGetFormatEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    var AText: string) of object;
  { 宿主接管筛选下拉的候选值(虚拟表 / 只列服务端已知取值)。 }
  TTyGridGetFilterValuesEvent = procedure(Sender: TObject; ACol: Integer;
    AItems: TStrings; var AHandled: Boolean) of object;

  { 超链接单元格被点(T12)。 }
  TTyGridCellLinkEvent = procedure(Sender: TObject; ACol, ARow: Integer) of object;

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
    { 逐格的显示类型(T14)与批注(T13)。放在这里而不是各自开一张表:
      属性存储已经会跟着行置换搬家、会进撤销快照,新开一张表这两件事都得重做。 }
    HasCellDisplay:   Boolean;
    CellDisplay:      TTyGridCellDisplay;
    Comment:          string;
    { 宿主挂在这一格上的任意对象(Objects[ACol,ARow])。放这里而不是另开一张表:
      属性存储已经会跟着行置换搬家 —— 排序、插删行、换行、拖行全都经过
      MoveEntry/Assign,所以对象**不用再写一遍搬家逻辑**就跟着走了。
      另开一张表得把那几条路径逐条重做,而漏搬一条的症状是"排完序拿到别人的记录"
      且一声不响(合并区当年就是这么漏的,见本类开头那段)。

      代价:每条**已有属性**的记录多一个指针(64 位 8 字节)。没有属性的格子
      一分钱不花 —— 稀疏存储里它根本没有条目。

      **网格不拥有它**:不释放、不复制。也正因为它是别人的指针,它不进撤销栈
      (见 TTyGridAttrSnapshot 的说明)。 }
    Obj:              TObject;
    constructor Create;
    { 全是默认值 = 这条可以丢掉,别让稀疏存储攒垃圾。 }
    function IsDefault: Boolean;
    procedure Assign(ASrc: TTyGridCellAttr);
    { 把**可撤销的那些字段**清回默认值,保留 Obj。撤销要还原"当时没有这一条"
      时用它 —— 整条删掉会连宿主挂的对象一起删,而对象不在撤销模型里。 }
    procedure ResetKeepingObject;
  end;

  { 逐格属性的稀疏存储,键空间与单元格文本一致('col:row')。 }
  TTyGridCellAttrStore = class
  private
    FItems: TStringList;      { Sorted + OwnsObjects → 二分查找、自动释放 }
    FOnChanging: TTyGridAttrChangingEvent;
    procedure Changing(const AKey: string);
  public
    constructor Create;
    destructor Destroy; override;
    { 没有条目时返回 nil —— **查询不要凭空建条目**,否则遍历一遍表就把稀疏性毁了。
      Find 拿到的对象**只读**:要改字段就得走 Mutate/Ensure,那两个会先发
      Changing 通知(撤销记录点挂在那里)。绕过它们就地改 = 那次改动撤销不了。 }
    function  Find(const AKey: string): TTyGridCellAttr;
    { 已有条目 → 通知一次并交出对象;没有则 nil。"我要改这条现成的"。 }
    function  Mutate(const AKey: string): TTyGridCellAttr;
    function  Ensure(const AKey: string): TTyGridCellAttr;
    { 与 Ensure 一样建/取条目,但**不发 Changing**。只给撤销模型之外的槽位用
      —— 目前只有 Obj。发通知就等于往撤销栈压一条记录,而那条记录会带着
      一个网格不拥有的指针(见 TTyGridAttrSnapshot)。 }
    function  EnsureQuiet(const AKey: string): TTyGridCellAttr;
    property OnChanging: TTyGridAttrChangingEvent read FOnChanging write FOnChanging;
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
    FDefaultRowHeightExplicit: Boolean;   { True once set; False = follow --row-height (density) }
    FFixedCols:        Integer;
    FFixedRows:        Integer;
    FFixedRowsBottom:  Integer;
    FFixedColsRight:   Integer;
    FIndicatorWidth:   Integer;
    FShowIndicator:    Boolean;
    FGridLineStyle:    TTyGridLineStyle;
    { 分组表头。空 = 只有一条列头带,与从前完全一致。 }
    FHeaderGroups:     TTyGridHeaderGroups;
    FGroupHeaderHeight:Integer;
    { 内嵌筛选行:列头下面一条带,每列一个输入位。它**不是数据行** ——
      占的是表头那一侧的高度,与分组带同族。 }
    FShowFilterRow:    Boolean;
    FFilterRowHeight:  Integer;   { 0 = 跟列头同高 }
    { 树形列:哪一列画成树(-1 = 不画)。缩进与三角只出现在这一列。 }
    FTreeColumn:       Integer;
    FTreeIndent:       Integer;   { 每一级缩进多少逻辑像素 }
    FOnGetNodeLevel:   TTyGridNodeLevelEvent;
    FOnGetHasChildren: TTyGridHasChildrenEvent;
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
    { 鼠标底下的**列头段**(-1 = 不在任何列头上)。与 FHoverCol 分开记:
      那个只在正文格上有值,而列头带上根本不是格 —— 合成一个的话,
      鼠标移到列头会把正文里的 hover 一起点亮。 }
    FHoverHeaderCol:   Integer;
    { 正被**按住**的列头段(-1 = 没有)。goHeaderPushedLook 的状态源。
      与 FHoverHeaderCol 分开:鼠标停在一段上和把它按下去是两回事,按下的那段
      要压过 hover 的观感。也与 FDragCol 分开:后者只在 hoDrag + coDraggable
      时才置位,是"这一列可能要被拖走"的候选,不是"这一段被按住了"。 }
    FPressedHeaderCol: Integer;
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
    FBidiLayouts:      Integer;       { 建过几次 TBidiTextLayout —— 只给测试,见 BidiLayoutCount }
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
    { 批量更新锁。宿主往表里灌数据时,每写一格都 Invalidate 一次:
      没有窗口句柄时几乎免费(headless 测试量不到它),真实窗口上却是一次
      失效调用 —— 灌 90 万格就是 90 万次,界面像死了一样。
      锁住期间只记一笔"欠一次重画",解锁时补上。 }
    FUpdateCount: Integer;
    FPendingInvalidate: Boolean;
    { 真正送到 LCL 的重画次数。批量更新从画面上看不出效果,
      只表现为快慢 —— 给测试一个能直接观测的口子。 }
    FRealInvalidates: Integer;
    { 走过快路径的帧数。脏区重绘从画面上完全看不出来 —— 它要是被
      静默关掉,只会变慢。给测试一个能直接观测"这一帧到底走没走快路径"的口子。 }
    FFastScrollFrames: Integer;
    { 上一次鼠标按下命中的是哪儿。DblClick 拿不到坐标(LCL 的签名里没有),
      而"双击落在哪"决定了它该做什么 —— 双击总是紧跟在一次按下之后,
      所以在按下时记账是**准确**的,比在 DblClick 里回读光标位置可靠。 }
    FLastDownHit: TTyGridHit;
    FShowFooter:       Boolean;
    { 列头图标与 gcdImage 单元格共用的图像源。
      当初自带一份是因为共享单元里的 TTyHeader.Images 声明成了 LCL 的
      TCustomImageList,而 TTyVirtualImageList 并非它的后代 —— 那个属性根本赋不进去。
      该属性现已改成 TTyVirtualImageList,那条理由不再成立;网格仍自带一份,是因为
      这份列表**同时**喂 gcdImage 单元格,不只是列头,两个角色合并要另算一次破坏性变更。
      索引仍走共享的 TTyColumn.ImageIndex。 }
    FImages:           TCustomImageList;
    FFooterHeight:     Integer;
    FScrollX:          Integer;
    FScrollY:          Integer;
    FDragCol:          Integer;   { 正在拖动的列索引;-1 = 没在拖 }
    FDragStartX:       Integer;
    { 行拖动。与列拖动对称:在**行头槽**里按下并越过阈值才算数。
      放在行头槽而不是单元格上 —— 单元格上是框选,不能抢那个手势。 }
    FDragRow:          Integer;   { 正在拖动的**数据行**;-1 = 没在拖 }
    FDragStartY:       Integer;
    FOnRowMove:        TTyGridRowMoveEvent;
    { 编辑器的最小宽度(逻辑像素)。0 = 完全跟着格走(老行为)。
      设大于 0 之后,窄列上的编辑器会自己向右加宽到这个宽度 —— 加宽的是**编辑器**,
      列宽一点没变。加宽不会越过网格右缘。 }
    FMinEditorWidth:   Integer;
    { --- 撤销/重做 ---
      记录点收口在 SetCells 与 SetRowCount 两处:所有改数据的路径最终都经过它们
      (增删行搬格子、粘贴、填充、编辑提交都一样),所以不必去每个功能里各记一遍
      —— 那正是本控件反复漏东西的方式。 }
    FUndoStack, FRedoStack: array of TTyGridUndoStep;
    FUndoOpen:      TTyGridUndoStep;   { 正在攒的这一条 }
    FUndoDepth:     Integer;           { >0 = 在事务里 }
    FUndoBusy:      Boolean;           { 正在撤销/重做 —— 此时不再记录,否则自噬 }
    FUndoLimit:     Integer;
    FUndoOverflow:  Boolean;           { 这一条大到记不下,整条作废 }
    FSortMode:      TTyGridSortMode;
    { 显示序此刻是不是恒等。RebuildOrder 顺手算出来 ——
      比"没排序 and 没分组 and 没筛选"那种启发式判断**更准**:
      按一个本来就有序的列排,结果同样是恒等,启发式却会当成"排过序了"。 }
    FOrderIsIdentity: Boolean;
    FOnGetEditorProp:  TTyGridEditorPropEvent;
    FResizeCol:        Integer;   { 正在拖宽的列;-1 = 没在拖 }
    FResizeStartX:     Integer;
    FResizeStartW:     Integer;
    FVertScrollBarMode: TTyGridScrollBarMode;
    FHorzScrollBarMode: TTyGridScrollBarMode;
    FBackgroundBitmap: TBGRABitmap;
    FBackgroundMode:   TTyGridBackgroundMode;
    FBackgroundScope:  TTyGridBackgroundScope;
    FHeaderWordWrap:   Boolean;
    FHeaderAutoHeight: Boolean;
    FShowFocusCell:    Boolean;
    { goDontScrollPartCell:MouseDown 期间把 MoveCursor 尾巴上那次
      ScrollIntoView 摁住。做成一个瞬时闸而不是在 MoveCursor 里读标志,
      是因为 LCL 的这个标志只管**点击**,键盘导航照样要把光标滚进视口。 }
    FSuppressScrollIntoView: Boolean;
    FHideSelectionWhenInactive: Boolean;
    FVScroll:          TTyScrollBar;
    FHScroll:          TTyScrollBar;
    FSyncingScroll:    Boolean;      { 防止程序改 Position 反弹回来 }
    FAutoFillColumns:  Boolean;
    FDefaultColWidth:  Integer;
    FDefaultColWidthExplicit: Boolean;  { True once a host/.lfm pins it; False = follow --column-width }
    FOnTopLeftChanged: TNotifyEvent;
    { 上一次通知过的左上角(列下标 / 显示行位置)。OnTopLeftChanged 按**格**而不是
      按像素触发,所以必须记住上一次是哪一格 —— 我们的滚动是平滑的像素滚动,
      滚三个像素并不换行,那种时候 LCL 里根本不会有事件。 }
    FLastLeftCol:      Integer;
    FLastTopRow:       Integer;
    function  GetColWidths(ACol: Integer): Integer;
    procedure SetColWidths(ACol, AValue: Integer);
    function  GetDefaultColWidth: Integer;
    procedure SetDefaultColWidth(AValue: Integer);
    function  GetLeftCol: Integer;
    procedure SetLeftCol(AValue: Integer);
    function  GetTopRow: Integer;
    procedure SetTopRow(AValue: Integer);
    function  GetScrollBars: TScrollStyle;
    procedure SetScrollBars(AValue: TScrollStyle);
    procedure SetAutoFillColumns(AValue: Boolean);
    { GridWidth/GridHeight 的取值器。**必须**是这里的私有方法而不是直接
      `read ContentWidthPx` —— 那两个虚方法声明在下面的 protected 段里,
      属性子句在解析时还看不见它们(FPC 报 "Unknown class field or method")。 }
    function  GetGridWidth: Integer;
    function  GetGridHeight: Integer;
    { 左上角换格了就通知宿主。每一条改变滚动量的路径都要经过它 ——
      少接一条就是"用滚轮滚不发、拖滑块才发"这种最难查的半吊子事件。 }
    procedure NotifyTopLeftChanged;
    procedure SetOnTopLeftChanged(AValue: TNotifyEvent);
    procedure SetHeaderWordWrap(AValue: Boolean);
    procedure SetHeaderAutoHeight(AValue: Boolean);
    procedure SetShowFocusCell(AValue: Boolean);
    function  GetOptions: TTyGridOptions;
    procedure SetOptions(AValue: TTyGridOptions);
    procedure SetHideSelectionWhenInactive(AValue: Boolean);
    procedure SetVertScrollBarMode(AValue: TTyGridScrollBarMode);
    procedure SetHorzScrollBarMode(AValue: TTyGridScrollBarMode);
    procedure SetBackgroundBitmap(AValue: TBGRABitmap);
    procedure SetBackgroundMode(AValue: TTyGridBackgroundMode);
    procedure SetBackgroundScope(AValue: TTyGridBackgroundScope);
    procedure VScrollChange(Sender: TObject);
    procedure HScrollChange(Sender: TObject);
    procedure HeaderChanged(Sender: TObject);
    procedure SetHeader(AValue: TTyHeader);
    procedure SetRowCount(AValue: Integer);
    function  GetDefaultRowHeight: Integer;
    procedure SetDefaultRowHeight(AValue: Integer);
    procedure SetFixedCols(AValue: Integer);
    procedure SetFixedRows(AValue: Integer);
    procedure SetFixedRowsBottom(AValue: Integer);
    procedure SetFixedColsRight(AValue: Integer);
    { 右侧冻结带的像素宽度(末尾 FixedColsRight 个**可见**列的宽度和)。 }
    function  FrozenRightPx: Integer;
    { 实际生效的右冻结列数(不与左固定列重叠)。 }
    function  EffectiveFixedColsRight: Integer;
    { 底部冻结带的像素高度(末尾 FixedRowsBottom 个显示行的高度和)。 }
    function  FrozenBottomPx: Integer;
    procedure SetIndicatorWidth(AValue: Integer);
    procedure SetShowIndicator(AValue: Boolean);
    procedure SetShowGridLines(AValue: Boolean);
    procedure SetShowFooter(AValue: Boolean);
    procedure SetImages(AValue: TCustomImageList);
    procedure SetGridLineWidth(AValue: Integer);
    procedure SetGridLineStyle(AValue: TTyGridLineStyle);
    procedure HeaderGroupsChanged(Sender: TObject);
    procedure SetHeaderGroups(AValue: TTyGridHeaderGroups);
    procedure SetGroupHeaderHeight(AValue: Integer);
    procedure SetAlternateRows(AValue: Boolean);
    procedure SetShowRowNumbers(AValue: Boolean);
    { 把"以行下标为键"的旁挂表整体平移(行高、隐藏行)。 }
    { 行数缩小时,把落在新行数之外的**按行记账的状态**清掉。走各自的记录点,
      所以这一步跟着 RowCount 一起可撤销。

      不清的话:换一个更小的数据集再换回大的,行高与隐藏标记会**复活**到
      不相干的行上,而用户没有任何操作产生过它们。
      基类只知道行高;隐藏标记在 TTyStringGrid,由它覆写补上。 }
    procedure TrimRowStateTo(ANewCount: Integer); virtual;
    procedure ShiftRowKeyedTable(AList: TStringList; AFromIndex, ADelta: Integer);
    { 上一个的**列轴对偶**:把"列下标 = 值"的 Name=Value 表整体平移。
      ADelta < 0 时,正落在 AFromIndex 上的那条丢弃(那一列没了)。

      为什么要单独一个:行那边的键是整条字符串(或带 Objects),
      这边是 Name=Value 的 Name —— 存法不同,但规则是同一条。
      **新增一张按列记账的旁挂表时,这里和 ShiftCells 的列分支都要加。** }
    procedure ShiftColKeyedTable(AList: TStringList; AFromIndex, ADelta: Integer);
    { 把行号画进行头槽。ShowRowNumbers 关着时整段跳过。 }
    { 行号画在**调用方给的那条屏幕槽**里(ASlotLeft..ASlotRight),不自己再算一遍 ——
      那条槽与铺底色用的是同一个 IndicatorBandX。 }
    procedure RenderRowNumbers(P: TTyPainter; const M: TTyGridMetrics;
      AHeaderH, ASlotLeft, ASlotRight: Integer); virtual;
    procedure SetWordWrap(AValue: Boolean);
    function  GetRowHeights(ARow: Integer): Integer;
    procedure SetRowHeights(ARow, AValue: Integer); virtual;
    function  GetGridLines: Boolean;
    procedure SetFooterHeight(AValue: Integer);
  protected
    { Options 里没有别处安身的那几位。**protected 而不是 private**:
      派生类与测试都要能看见"自有存储里究竟躺着什么" —— 那条
      "派生位一份副本都不许留" 的不变量,从外面只看 Options 是验不出来的
      (读数是现算的,副本躺在里面也照样对)。 }
    FOptions: TTyGridOptions;
    { Y 落在哪一行的下边界附近(行头槽内才算)。不在分隔线上返回 -1。
      与列那边的 DividerAtX 对称,所以可见性也跟它一样是 protected ——
      行高拖拽的闸(goRowSizing)收口在这里,派生类要能问、测试要能钉。 }
    function  RowDividerAtY(AX, AY: Integer): Integer;
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
    function  HoverIsHyperlink(X, Y: Integer): Boolean; virtual;
    procedure UpdateHoverCursor(X, Y: Integer);
    { 把一格文字画出来,尽量走缓存。语义与 P.DrawText 一致(含省略号截断)。 }
    procedure DrawCellText(P: TTyPainter; const ARect: TRect; const AText: string;
      const AFontName: string; AFontSize, AFontWeight: Integer; AColor: TTyColor;
      AHAlign: TAlignment; AVAlign: TTextLayout; AWordWrap: Boolean = False);
    { 含右到左码点的那一份格子文本,走 BGRA 的双向布局排。 }
    procedure DrawCellTextBidi(ABmp: TBGRABitmap; AW, AH: Integer;
      const AText: string; AColor: TTyColor; AHAlign: TAlignment;
      AVAlign: TTextLayout; AWordWrap: Boolean);
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
    { 两个**只给测试用**的探针:批量更新与脏区重绘从画面上都看不出效果,
      失效只表现为变慢或留下陈旧像素,必须有能直接观测的口子。
      放 protected —— 测试经访问子类够得着,而它们不该成为对外支持的 API。 }
    property RealInvalidateCount: Integer read FRealInvalidates;
    property SurfaceFresh: Boolean read FSurfaceFresh;
    { 第三个探针,同样只给测试用:文字缓存里有几条。
      双向文字要建 TBidiTextLayout,那是**每串一次**还是**每帧每格一次**,
      画面上看不出任何差别(缓存的位图和刚排好的位图一模一样),
      只表现为变慢 —— TTyMemo 那次每键半秒就是这个形状。
      所以"排版发生在缓存未命中的分支里"这条契约,只能在这里断言。 }
    function TextCacheCount: Integer;
    { 第四个探针,同样只给测试用:一共建过几次 TBidiTextLayout。
      **像素证明不了这件事**。双向布局对只有一个 run 的文字(纯拉丁、纯 CJK、
      纯阿拉伯)排出来的结果与裸 TextRect 逐像素相同 —— 把闸门改成恒真,
      "拉丁输出没变"那条断言依旧全绿(实测如此,与 test.bidi.pas 记的
      是同一个陷阱)。所以"拉丁文根本走不到这条路"只能数出来,不能看出来。 }
    property BidiLayoutCount: Integer read FBidiLayouts;
    procedure ResetBidiLayoutCount;
    { 把数据行 AFrom 移到 ATo。基类不持有单元格,什么都不做;
      TTyStringGrid 覆盖成真正的 MoveRow(它会把底色/行高/合并跨度一起搬)。 }
    { 撤销事务的开合。批量更新与撤销事务是**同一对边界** ——
      凡是值得"一次重画"的批量操作,也正是值得"一次撤销"的操作。
      栈住在 TTyStringGrid(基类不持有单元格),所以这里是空钩子。 }
    { 记一笔"行数原来是多少"。栈住在 TTyStringGrid,基类是空钩子。 }
    procedure RecordRowCountUndo(AOldCount: Integer); virtual;
    procedure OpenUndoGroup; virtual;
    procedure CloseUndoGroup; virtual;
    procedure DoRowDragMove(AFrom, ATo: Integer); virtual;
    { 显示序此刻是不是就是数据序(没排序、没分组、没筛选、没隐藏行)。
      不是的话**不允许拖行** —— 把行拖到某个屏幕位置在排过序的表上没有意义:
      松手之后排序会立刻把它放回去,用户只会觉得"拖了没反应"。
      与 MergeSelection 拒绝非数据连续的选区是同一条道理。 }
    function DisplayOrderIsDataOrder: Boolean; virtual;
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
    { 这一**行**是不是光标所在的行(goRowHighlight 用)。基类恒 False。
      与 IsActiveCell 分开而不是拿 `IsActiveCell(FCol, ARow)` 凑:基类根本没有
      FCol 这个东西,凑出来的写法在 TTyDrawGrid 上会答错。 }
    function  IsActiveRow(ARow: Integer): Boolean; virtual;
    function  SelectionIsActive: Boolean; virtual;

    { ---- Options 里落在派生类属性上的那几位 ----

      goEditing 的真身是 TTyStringGrid.ReadOnly,goRowSelect 的真身是
      TTyStringGrid.SelectionMode —— 两个都不在基类上。Options 却必须发布在
      TTyCustomGrid 上(TTyDrawGrid 也要有),所以中间隔一对可改写的钩子。

      基类的实现描述**基类的事实**:没有 ReadOnly 概念 = 永远"可编辑"、
      永远按格选。这不是占位,是真话 —— 所以基类上这两位读出来是常量,
      写进去是空操作,而不是假装存下来了。 }
    function  GetOptEditing: Boolean; virtual;
    procedure SetOptEditing(AValue: Boolean); virtual;
    function  GetOptRowSelect: Boolean; virtual;
    procedure SetOptRowSelect(AValue: Boolean); virtual;
    { goScrollKeepVisible:滚动落定之后把光标拖进新视口。基类没有光标,空实现。 }
    procedure KeepCursorVisible; virtual;
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
    { 列宽,逻辑像素 —— RowHeights 的**列轴对偶**,对标 LCL 的 ColWidths[aCol]
      (grids.pas:1236,与 RowHeights[aRow] 并排声明)。

      从前只有行那一半:改一列的宽度得写
      `TTyColumn(Grid.Header.Columns.Items[i]).Width := 40`,而同一段代码里改行高
      只要 `Grid.RowHeights[r] := 20`。ColumnWidthPx 不算数 —— 它只读、吃的是
      设备像素,而且在 protected 段里,宿主够不着。

      写入走的钳制与拖动改宽**完全一样**:先网格级的 MinColWidth/MaxColWidth,
      再列自己的 MinWidth/MaxWidth(在 TTyColumn.SetWidth 里)。两条路一致,
      不会出现"手拖到 60 是下限、代码写 10 却进去了"。列下标越界不抛异常,
      读回 0、写则忽略(与本单元其余钳制同一条纪律)。 }
    property ColWidths[ACol: Integer]: Integer read GetColWidths write SetColWidths;
    { 视口里现在装得下几列 —— VisibleRowCount 的列轴对偶(LCL grids.pas:1300)。
      按**看得见的像素**算:横向滚到一半的那一列也算在内,与行那边一致。
      冻结列恒可见,一律计入。 }
    function VisibleColCount: Integer;
    { 全部列 / 全部行加起来有多大(设备像素,与 ClientWidth/ClientHeight 同一坐标空间)。
      对标 LCL 的 GridWidth / GridHeight(grids.pas:1264/:1268)。

      内部一直叫 ContentWidthPx / ContentHeightPx,但那两个在 protected 段里 ——
      宿主想问"内容溢出了没有""把面板收到刚好包住表格"只能自己把列宽再加一遍,
      而那份加法要处理隐藏列和行头槽,正是最容易加错的地方。 }
    property GridWidth: Integer read GetGridWidth;
    property GridHeight: Integer read GetGridHeight;
    { 视口左上角那一格。LeftCol 是**列下标**,TopRow 是**显示位置**(不是数据行:
      排序筛选之后"屏幕最上面那一行"本来就是显示序里的概念,而滚动条也按显示序走)。
      对标 LCL grids.pas:1278/:1297。

      读:第一个不在左冻结带里、且有像素落在正文区的列 / 行。
      写:滚到让那一格贴着正文区左上角;越界钳制,不改光标、不改选区
      —— "把视野挪过去但别动光标"正是它相对 ScrollIntoView 的价值。
      固定列/固定行钉在冻结带里,永远不是滚动窗口的一部分,写进去等于写第一个可滚的。 }
    property LeftCol: Integer read GetLeftCol write SetLeftCol;
    property TopRow: Integer read GetTopRow write SetTopRow;
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
    { 列头带的高度(设备像素)。**唯一出处** —— 从前 HeaderHeightPx
      在 13 处内联,自适应高度这种"要在每处都成立"的规则没处加。
      (与列轴收口到 ColumnLeftPx、行带收口到 TyGridRowBandRect 同一条纪律。) }
    function HeaderHeightPx: Integer; virtual;
    function GroupLevelCount: Integer;
    function GroupBandHeightPx: Integer; virtual;
    { 内嵌筛选行那条带的高度(设备像素);关着时 0。 }
    function FilterRowHeightPx: Integer; virtual;
    procedure SetShowFilterRow(AValue: Boolean);
    procedure SetFilterRowHeight(AValue: Integer);
    { 重建列几何缓存。列增删/改宽、行头槽变化、PPI 变化都要让它失效。 }
    procedure BuildColumnCache;
    procedure InvalidateColumnCache;
    function GridLineWidthPx: Integer; virtual;
    procedure Invalidate; override;
    procedure DblClick; override;
    procedure CMMouseLeave(var Msg: TLMessage); message CM_MOUSELEAVE;
    { 阅读方向变了,整幅几何都换了边 —— 列缓存按**逻辑**像素存(那一份不变),
      但横向滚动条的镜像开关、以及所有画出来的东西都得重来一遍。
      LCL 自己只 Invalidate + AdjustSize,不会回头重跑我们手写的滚动条装配;
      与 TTyListBox.CMBiDiModeChanged 同一个缺口、同一个补法。 }
    procedure CMBiDiModeChanged(var Msg: TLMessage); message CM_BIDIMODECHANGED;
    function FrozenWidthPx: Integer; virtual;
    { 冻结带高度(设备像素)= 列头带 + 固定行 * 行高。 }
    function FrozenHeightPx: Integer; virtual;
    { 页脚汇总带高度(设备像素)。它钉在视口底部、不参与滚动。 }
    function FooterHeightPx: Integer; virtual;
    { 逐行行高(逻辑像素)。基类恒为 DefaultRowHeight;派生类可按行覆盖。
      **吃数据行** —— 显式行高与 OnGetRowHeight 都按数据行记账。 }
    function RowHeightOf(ARow: Integer): Integer; virtual;
    { 同上,但吃**显示位置**。冻结带的厚度是按"显示在带子里的那几行"算的,
      直接把显示位置喂给 RowHeightOf 就会取到另外几行的高度(排序后必然错)。
      分组行没有数据行,按默认行高 —— 与 RowTops 同一条规则。 }
    function RowHeightOfDisplay(APos: Integer): Integer;
    { 行高前缀和(设备像素),喂给几何层。全等高时返回空数组 = 走统一行高快路径。 }
    function RowTops: TTyIntArray; virtual;

    { 把控件当前状态装配成纯几何层要的度量。所有几何都必须经由它,
      不允许任何地方另算一套 —— 那正是绘制/命中漂移的源头。 }
    function GridMetrics: TTyGridMetrics; virtual;

    { **在第 APos 行所属的那条横向带里**画点什么。裁剪与外层求交(脏区重画
      限定的那条带),完全不相交时**根本不调用** ADraw。

      为什么要包一层而不是"记得先设 ClipRect":这条规则此前在四处各写一遍
      (行号 / 横格线 / 选区外框 / 填充柄),每一处都是漏了才发现的。
      把绘制动作交进来之后,"忘了裁剪"这件事在结构上不再可能发生 ——
      不经过这里就压根画不出来。 }
    procedure DrawInRowBand(P: TTyPainter; APos: Integer;
      const M: TTyGridMetrics; ADraw: TTyGridBandDraw);
    { 同上,但裁到某个**九宫格窗格**(行轴 + 列轴都管)。跨满整幅宽度的 chrome
      走 DrawInRowBand,而有列归属的(选区外框、填充柄)走这个 ——
      用行带的话,冻结列那一侧就漏掉了。 }
    procedure DrawInPane(P: TTyPainter; APane: TTyGridPane;
      const M: TTyGridMetrics; ADraw: TTyGridBandDraw);

    { --- 横轴镜像(RTL)-------------------------------------------------------

      本控件这一帧的横轴要不要镜像。**按类回答,不按实例**:默认跟着窗体的阅读方向
      (TControl.IsRightToLeft),后代在自己的 x 命中还没和绘制收口成一个来源之前
      覆写成 False。与 TTyListBox.RtlRowLayout 同一条约定,
      `grep -n "RtlLayout"` 就是"谁镜像了"的诚实清单。

      **BiDiMode 不 published** —— 见 tests/test.parity.pas 的
      LyingPropertiesStayUnpublished。阅读方向从窗体继承,不在网格上单独摆一个开关。 }
    function RtlLayout: Boolean; virtual;

    { 逻辑 x(恒从左往右累加)→ **屏幕 x** 的唯一变换,以及它的精确逆。

      做的是"把已经排好的一份平铺整体反射一次",而不是"倒着再累加一遍":
      反射一份无缝平铺仍然无缝,两列之间不可能长出一道 1px 的缝;凡是由列矩形
      派生出来的东西(单元格、格线、表头段、筛选位)自动落在对的地方,不必各写
      第二个公式。反射用 LCL 的 BidiFlipRect(controls.pp:2966)—— 那五行算术
      别人已经写对了,重抄一遍只是多一个可能写错的减号。

      逆走 1px 宽矩形的同一个 BidiFlipRect,不是手写 `VW-1-X`:
      "X 落在 ToScreenRect(R) 里"与"ToReadingX(X) 落在 R 里"必须是**同一个谓词**,
      手写的那一版差半格就是"画在右边、点在左边"。

      LTR 下两者都是恒等 —— 所以 LTR 的每一个像素与本次改动之前逐字节相同。 }
    function ToScreenRect(const ARect: TRect): TRect;
    function ToReadingX(AX: Integer): Integer;
    { 屏幕矩形 → 阅读空间。反射是**对合**(反射两次回到原处),所以它的实现就是
      ToScreenRect —— 单独起个名字是为了让调用点读得出方向,免得下一个人以为
      那里少了一个逆函数。凡是判据里带方向性比较符(`>` / `<`)的地方都先经过它,
      比较符本身就一个字都不用改。 }
    function ToReadingRect(const ARect: TRect): TRect;

    { 行头/行号槽在**屏幕**上的 x 区间(半开)。返回 False = 不显示。

      从前这条边界在四处各写一遍 `x < ScaleI(FIndicatorWidth)`:绘制底色
      (RenderChrome)、行号槽(RenderRowNumbers)、命中(CellAt)、行高拖拽
      (RowDividerAtY)、拖行手势(MouseDown)。LTR 下四份都从 x=0 起算,
      写几遍都一样;RTL 下这条槽整条换到右边,**漏掉任何一份就是一处画在一边、
      答在另一边**。收口在这里之后,换边只写一次。 }
    function IndicatorBandX(out ALeft, ARight: Integer): Boolean;

    { **前导**冻结带(行头槽 + 左固定列)在屏幕上的 x 区间。LTR 下 = [0, FrozenWidthPx),
      RTL 下整条钉在视口右沿。返回 False = 没有冻结带。
      它与 IndicatorBandX 是同一条带的两截,反射的是同一次。 }
    function LeadFrozenBandX(out ALeft, ARight: Integer): Boolean;

    { 正文(可滚动列)那条横带的 x 区间。等价于 gpBody 窗格的横向范围。
      冻结带盖住滚过来的正文列这条规则原先在四处各写一遍
      (ColumnAtX 的守卫、GetLeftCol、列头段裁剪、页脚/分组小计裁剪),
      RTL 下"被盖住的是哪一侧"跟着换边 —— 同样只该写一次。 }
    procedure BodyBandX(const M: TTyGridMetrics; out ALeft, ARight: Integer);
    { 把第 ACol 列(可滚动列)的可见段裁进正文带。返回 False = 整列都被冻结带盖住。
      ALeft/AWidth 传入的是完整列矩形,传出的是裁过的那一段。 }
    function ClipColToBody(const M: TTyGridMetrics; ACol: Integer;
      var ALeft, AWidth: Integer): Boolean;

    { 从第 AFirst 列到第 ALast 列(含)的横向跨度,屏幕像素。
      RTL 下首列在右、末列在左,直接 `Left(first) .. Left(last)+Width(last)`
      会写出一个**反向矩形**(分组表头整条消失、跨列合并格画成空)。
      两个调用方(表头分组带、跨列合并)都走这里,方向无关。 }
    function ColumnSpanX(AFirst, ALast: Integer; out ALeft, ARight: Integer): Boolean;

    { 第 ACol 列的**尾缘** —— 拖它改的就是这一列的宽度。
      LTR 下是右缘,RTL 下是左缘。DividerAtX 与拖动位移都走它,
      于是"看得见的那条分隔线"和"拖起来变宽的那一列"不可能是两列。 }
    function ColumnResizeEdgeX(ACol: Integer): Integer;

    { 方向键在列上走一步的**下标增量**。ADelta 是"往屏幕右边走 +1 / 左边走 -1",
      返回的是列下标该加多少 —— RTL 下取反。抽成一个函数而不是在 KeyDown 里
      写两个 `if RtlLayout`:方向键漏翻是本程序记在案的第三号静默故障,
      而每一处都只是一个减号,review 时几乎看不出来。 }
    function ArrowColStep(ADelta: Integer): Integer;

    { 第 ACol 列左边界的客户区横坐标(设备像素)——**列轴几何的唯一出处**。
      固定列钉在冻结带里不随横向滚动;正文列随 ScrollX 平移。
      CellRect 与 ColumnAtX 都必须走它,否则绘制与命中会分叉。
      RTL 下它在出口反射一次,于是十六个消费者一起换边。 }
    { ColumnLeftPx 的出口反射。抽出来只为一件事:两条 return 路径
      (右冻结列 / 其余列)必须反射同一次 —— 只反射一条就是右冻结带留在原地。 }
    function MirrorColX(ALogicalLeft, ACol: Integer): Integer;
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
    { 排序三角在这一段里占掉的宽度(没有排序时为 0)。绘制端与漏斗定位端
      从前各算一遍 —— 同一个式子的两份拷贝。 }
    function HeaderSortGlyphW(ACol: Integer): Integer;
    { 表头漏斗(筛选按钮)的圆心横坐标,屏幕像素。**绘制与命中的唯一出处**。 }
    function HeaderFunnelCenterX(ACol: Integer): Integer;
    function HeaderFilterRect(ACol, AHeaderH: Integer): TRect;

    { 列头图标从哪份图像列表取。Header.Images 有货就用它,否则用网格自己的 Images。

      从前列头图标只认 FImages,而 TTyHeader.Images 是**published** 的 ——
      设计器里给它赋一份列表,什么都不会发生,也没有任何提示。那不是"没实现",
      是一个骗人的属性。回落到 Images 是因为 gcdImage 单元格与列头共用一份列表
      是这里的常态(声明处有说明),一份接好就够用;Header.Images 是**覆盖**,
      与 TTyListView.HeaderImageList 同一套规则。

      一旦设了 Header.Images 就它说了算,哪怕那个下标它画不出来 ——
      会静默回落的覆盖不叫覆盖。 }
    function HeaderImageList: TCustomImageList; virtual;
    { 列头里每一列的分段:底色、标题文字、排序字形。 }
    procedure RenderHeaderSections(P: TTyPainter; const M: TTyGridMetrics;
      AHeaderH: Integer); virtual;

    { 列头带 / 行头槽 / 固定列区的填充。绘制次序即遮挡次序,必须与 CellAt 的判定次序一致:
      列头横跨整幅并盖住左上角 → 行头槽 → 固定列。 }
    procedure RenderBackgroundBitmap(P: TTyPainter; const M: TTyGridMetrics;
      const R: TRect); virtual;
    procedure RenderChrome(P: TTyPainter; const M: TTyGridMetrics); virtual;
    { 逐格背景。与文字分成两趟:文字那趟在派生类里(基类不知道数据从哪来),
      而背景只取决于格的**状态**,基类就能画完 —— hover/选中/斑马纹/逐格底色
      因此对三层都自动生效。 }
    procedure RenderCellBackgrounds(P: TTyPainter; const M: TTyGridMetrics); virtual;
    { 分组表头带。没有分组时什么都不画。 }
    procedure RenderHeaderGroups(P: TTyPainter; const M: TTyGridMetrics); virtual;
    { 内嵌筛选行:每列一个输入位,显示该列当前的过滤表达式。
      ATop = 它的顶边(列头带之下)。基类不知道过滤条件是什么,
      文字由 FilterRowText 提供 —— TTyStringGrid 改写它。 }
    procedure RenderFilterRow(P: TTyPainter; const M: TTyGridMetrics;
      ATop: Integer); virtual;
    { 某列筛选位里要显示的文字。基类恒空。 }
    function  FilterRowText(ACol: Integer): string; virtual;

    { 这一行折起来没有。基类没有折叠状态,恒 False;TTyStringGrid 改写。
      绘制在 TTyDrawGrid 这一层,而状态在派生类 —— 靠它把两边接起来。 }
    function  NodeCollapsedOf(ARow: Integer): Boolean; virtual;
    procedure SetTreeColumn(AValue: Integer);
    procedure SetTreeIndent(AValue: Integer);

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
      ScrollIntoView 改的都只是 FScrollX/Y,不同步的话内容滚了滑块还停在原处。

      virtual 的理由和旁边的 UpdateScrollBars 一样,而且是被这一条逼出来的:
      这两个方法头上原本各有一句 `if (FVScroll = nil) or (FHScroll = nil) then Exit`,
      而"那扇窗到底开不开"只能拿探针去数,数不到就没法判它是守卫还是死码
      (测量记录在实现处)。没有这个座,SyncScrollBars 那一条就只能靠读代码猜。 }
    procedure SyncScrollBars; virtual;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { 整表背景图。控件**不持有**这张位图的所有权 —— 宿主给什么用什么,
      宿主负责释放(与 Images 同一约定,免得两边都以为对方会 Free)。 }
    property BackgroundBitmap: TBGRABitmap
      read FBackgroundBitmap write SetBackgroundBitmap;
    property BackgroundMode: TTyGridBackgroundMode
      read FBackgroundMode write SetBackgroundMode default gbmStretch;
    property BackgroundScope: TTyGridBackgroundScope
      read FBackgroundScope write SetBackgroundScope default gbsWholeGrid;
    { 列头标题换行显示。 }
    property HeaderWordWrap: Boolean
      read FHeaderWordWrap write SetHeaderWordWrap default False;
    { 列头带高度按最高的那个标题自适应(Header.Height 当作下限)。 }
    property HeaderAutoHeight: Boolean
      read FHeaderAutoHeight write SetHeaderAutoHeight default False;
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

    { How many rows the VIEWPORT currently holds -- a viewport metric, the same thing
      LCL's TCustomGrid.VisibleRowCount means (grids.pas:1301, body at 2274). This is
      the number PageUp/PageDown maths is written against.

      It is NOT "how many rows survived the filter". That is DisplayRowCount (or its
      alias FilteredRowCount), and it used to be what this name returned on
      TTyStringGrid -- so paging maths ported from LCL compiled and computed garbage:
      with 10000 filtered-in rows it paged 10000 rows at a time. Both metrics are
      Integer, so nothing warned anybody. Hence the split, and hence the guard in
      test.parity.grid.

      Faithful to LCL down to the off-by-one: LCL answers
      `VisibleGrid.Bottom - VisibleGrid.Top`, i.e. one LESS than the number of rows
      touching the viewport, so a page leaves one row of overlap -- that is why the
      last row of a screen is still the first row of the next one after PageDown. The
      overlap is dropped when the whole grid fits, exactly as LCL's
      `if GridHeight<=ClientHeight then inc(Result)` does. }
    function VisibleRowCount: Integer;

    { 单元格所属窗格。**吃的是显示位置 APos,不是数据行** —— 这里的两个判据
      (`< FixedRows` / `>= DisplayRowCount - FixedRowsBottom`)本来就只在显示序里
      成立;从前喂数据行,没排序时两者相等所以看不出来,一排序就把格子判进错的窗格,
      求交后成空矩形、行静默变空白。空间写进签名,别再靠约定。
      被筛掉的行(APos < 0)没有显示位置,只按列分窗格。
      RTL 下答案在出口整体换边 —— 见 CellPaneLtr。 }
    function CellPane(ACol, APos: Integer): TTyGridPane;
    { 上面那一个按**列的角色**(左固定 / 右固定 / 正文)选带的那一半,
      不带镜像。拆开是为了让"换边"只有一处。 }
    function CellPaneLtr(ACol, APos: Integer): TTyGridPane;

    { 单元格的几何矩形,客户区坐标 —— **未裁剪**。派生类可覆写(合并区)。绘制时要先裁到所属窗格;
      正文列横向滚到冻结带底下的那一段就在这里被裁掉。 }
    function CellRect(ACol, ARow: Integer): TRect; virtual;

    { 单元格**实际可见**的矩形 = CellRect ∩ 所属窗格。CellAt 正是它的逆:
      被冻结带盖住的部分本来就点不到,所以不变量必须以可见矩形表述,而非几何矩形。 }
    function CellVisibleRect(ACol, ARow: Integer): TRect;

    { --- 树形单元格的几何与查询 ---
      层级由宿主给(OnGetNodeLevel);控件只负责缩进、三角的几何、
      以及把折叠翻译成显示序。**public**:宿主要自绘树形列、或者自己做命中,
      拿到的必须是控件正在用的那一份几何。 }
    function  NodeLevelOf(ARow: Integer): Integer;
    function  NodeHasChildren(ARow: Integer): Boolean;
    { 这一格的内容左边界(树形列上要为缩进和三角让位)。 }
    function  TreeContentLeft(ACol, ARow: Integer): Integer;
    { 展开/折叠三角的矩形。**命中与绘制共用它** —— 分成两份迟早对不上
      (本库在填充柄、分组三角上都是这么守的)。没孩子时返回空矩形。 }
    function  TreeToggleRect(ARow: Integer): TRect;
    { 展开/折叠三角**那一笔**。树形列与分组行各画一次,所以方向判断只写在这里 ——
      两处各写一遍,正是分组行的三角上次被漏掉的原因。

      折叠态朝**阅读前进的方向**(LTR 朝右、RTL 朝左),展开态一律朝下:向下是
      "已经展开在下面"这条竖轴上的事实,与从哪一头读无关。 }
    procedure DrawToggleGlyph(P: TTyPainter; const ARect: TRect; ACollapsed: Boolean;
      AColor: TTyColor);
    { 落在合并区内的坐标归到基准格。基类无合并,原样返回。 }
    procedure MapToBaseCell(var ACol, ARow: Integer); virtual;

    { 点命中,客户区坐标 —— **CellVisibleRect 的逆**(见上:被冻结带盖住的部分点不到)。 }
    { 批量改数据时把重画锁住,结束后只重画一次。可嵌套。
      任何要连续写很多格/很多行的宿主都该用它。 }
    procedure BeginUpdate;
    procedure EndUpdate;
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
    { Left unset it follows the theme's --row-height (22 classic / 32 modern); set it and that
      value wins and is streamed (a dense report grid can still pin its own). See TTyListView. }
    property DefaultRowHeight: Integer read GetDefaultRowHeight write SetDefaultRowHeight stored FDefaultRowHeightExplicit;
    { 新建列的宽度 —— DefaultRowHeight 的列轴对偶,对标 LCL 的 DefaultColWidth
      (grids.pas:1237)。InsertColumn / InsertCols 建出来的列按它起宽。

      与 DefaultRowHeight 同一套规则:没被显式写过时跟着主题的 `--column-width`
      走(密度轴因此也能管列宽),写过之后那个值说了算并被写进 .lfm。
      主题没定义这个变量就是 100 —— 与从前 TTyColumn.Width 的 `default 100` 一致,
      所以什么都不设时行为逐字节不变。

      **不追溯改已有列**:LCL 的 SetDefColWidth 会把所有没被显式设过宽的列一起改,
      而我们的列没有"这一列的宽度是不是显式设过"这一位可查 —— 追溯就得靠猜,
      猜错的代价是用户调好的列宽被抹掉。要统一改宽请遍历 ColWidths[]。 }
    property DefaultColWidth: Integer read GetDefaultColWidth write SetDefaultColWidth
      stored FDefaultColWidthExplicit;
    { 让**每一列**分掉多余的宽度,按各自的 TTyColumn.SizePriority 加权。
      对标 LCL 的 AutoFillColumns(grids.pas:1224,默认 False)。

      与 hoAutoResize / Header.AutoSizeIndex 的区别:那一对只让**指定的一列**
      吸收剩余宽度,别的列纹丝不动。真要"表格随窗口一起变宽、各列按比例跟着变",
      从前只能宿主自己在 OnResize 里遍历改列宽 —— 而多列分配的算法
      (TTyColumns.DistributeSpring)其实早就在库里,只是**零调用点**,
      从来没有任何控件够得着它。

      两个开关都开时 AutoFillColumns 先跑、AutoSizeIndex 后跑,后者压前者
      —— "整体铺满,再让某一列吃掉最后的零头"是能讲通的组合,反过来不是。 }
    property AutoFillColumns: Boolean read FAutoFillColumns write SetAutoFillColumns
      default False;
    { 滚动条三态,横纵各一。gsbNever 只是不显示 —— 键盘/滚轮照样能滚到底。
      **published** 而不是 public:从前它们在 public 段里,于是设计器上根本
      看不到这两个属性 —— 一个只用设计器的用户压根没法关掉网格的滚动条。 }
    property VertScrollBarMode: TTyGridScrollBarMode
      read FVertScrollBarMode write SetVertScrollBarMode default gsbAuto;
    property HorzScrollBarMode: TTyGridScrollBarMode
      read FHorzScrollBarMode write SetHorzScrollBarMode default gsbAuto;
    { LCL 用一个 TScrollStyle 表达上面那两个(grids.pas:1293,默认 ssAutoBoth)。
      同名同类型地补上,于是 `ScrollBars := ssNone` 与 .lfm 里的 ScrollBars=ssNone
      都能用。存储仍是上面那一对,所以 `stored False` —— 两处都写进 .lfm 的话,
      后读到的那一行会静默推翻先读到的(与 GridLines/GridLineStyle 同一条纪律)。

      映射:ssNone=两条都 Never;ssHorizontal/ssVertical=那一条 Always、另一条 Never;
      ssBoth=两条 Always;ssAuto* 同理但用 Auto。读回时找不到对应组合
      (比如横 Auto 纵 Always)就答最接近的 ssAutoBoth —— 这是 LCL 表达不了的状态,
      而我们的两个属性才是真相。 }
    property ScrollBars: TScrollStyle read GetScrollBars write SetScrollBars
      stored False default ssAutoBoth;
    { 行为开关的总入口,对标 LCL 的 TCustomGrid.Options(grids.pas:1280)。

      **这是设计器里唯一一处能把网格的交互行为一次看全的地方。** 在此之前
      这些开关散在四个不同的对象上:格线在 GridLineStyle,改列宽/拖列/列头
      点亮在 `Header.Options` 里(要展开子对象才看得到),只读在 ReadOnly,
      整行选择在 SelectionMode,行号在 ShowRowNumbers —— 而改行高、拖行、
      双击适宽、"…"截断这几条**根本没有开关**,想关掉只能改库。

      **它不是第二份存储。** 一半的位没有别的家,存在 FOptions 里;另一半
      (TyGridDerivedOptions)现读现算、写回原主。所以
      `GridLineStyle := glsNone` 之后 `goVertLine in Options` 立刻是 False,
      `Options := Options - [goColSizing]` 之后 `Header.Options` 里的
      hoColumnResize 立刻没了 —— 两个方向都真的通,各有一条测试钉着。

      **.lfm 会同时写 Options 和那几个具名属性**,这是有意的,不是遗漏:
      两边都由 TWriter 从**同一份状态**算出来,不可能互相矛盾,谁后读到都
      收敛到同一个值(SetOptions 只在某一位**真的翻了**时才写回原主,所以
      重复赋值是幂等的)。手改 .lfm 把两边写拧了才会有歧义,那时后读到的赢。

      与 GridLines/ScrollBars 那几个**别名**不同:那些是同一个概念的另一个
      名字,所以 `stored False`;Options 里有一半是它自己的存储,`stored False`
      会让 goRangeSelect 之类整个流不出去。 }
    property Options: TTyGridOptions read GetOptions write SetOptions
      default TyDefaultGridOptions;
    { 焦点格要不要画外框。gsmRow 模式下整行都是选中底色,不画外框就
      看不出光标在哪一格 —— 所以默认开着。
      **published**:从前在 public 段,设计器里看不见。 }
    property ShowFocusCell: Boolean
      read FShowFocusCell write SetShowFocusCell default True;
    { LCL 管这件事叫 FocusRectVisible(grids.pas:1261,同样 default true)。
      别名,存储是 ShowFocusCell。 }
    property FocusRectVisible: Boolean
      read FShowFocusCell write SetShowFocusCell stored False default True;
    { 控件失去焦点时选区要不要变淡。**published**:同上。 }
    property HideSelectionWhenInactive: Boolean
      read FHideSelectionWhenInactive write SetHideSelectionWhenInactive
      default False;
    { LCL 管这件事叫 FadeUnfocusedSelection(grids.pas:1290,同样 default false)。
      别名,存储是 HideSelectionWhenInactive。 }
    property FadeUnfocusedSelection: Boolean
      read FHideSelectionWhenInactive write SetHideSelectionWhenInactive
      stored False default False;
    { 冻结在左侧、不随横向滚动的列数。 }
    property FixedCols: Integer read FFixedCols write SetFixedCols default 0;
    { 冻结在顶部、不随纵向滚动的数据行数(列头带另计)。 }
    property FixedRows: Integer read FFixedRows write SetFixedRows default 0;
    { 钉在底部、不随纵向滚动的显示行数(与 FixedRows 对称)。
      常见用途是把一条"合计行"钉在视口下沿 —— 若只是要整表汇总,
      现成的汇总带(ShowFooter + SetColumnAggregate)更省事。 }
    property FixedRowsBottom: Integer read FFixedRowsBottom write SetFixedRowsBottom
      default 0;
    { 钉在右侧、不随横向滚动的列数(与 FixedCols 对称)。 }
    property FixedColsRight: Integer read FFixedColsRight write SetFixedColsRight
      default 0;
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
    { 格线画哪几轴。

      **NOT LCL's GridLineStyle.** LCL's TCustomGrid.GridLineStyle (grids.pas:1266) is
      a TPenStyle -- psSolid / psDash / psDot, i.e. HOW the line is drawn. Ours says
      WHICH AXES get a line at all. Same name, unrelated meaning, and this one is kept
      rather than renamed:

        - the enum types are different, so every ported use (`:= psDash`,
          `= psSolid`) is a COMPILE ERROR. Unlike the other collisions in this unit
          this one cannot bite silently, so renaming buys no safety;
        - the property is published and already streamed into .lfm files, so a rename
          breaks every form that carries it, for that same zero safety;
        - and taking the name over for a real TPenStyle would mean teaching the
          painter to rasterise dashes -- grid lines are FillRect calls on a BGRA
          bitmap (RenderGridLines), there is no pen involved anywhere.

      So it is documented instead, here and in docs/controls/grid.md -- and a guard in
      test.parity.grid keeps that note from quietly disappearing. Want dashed grid
      lines? That is a feature request, not a rename. }
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
    property Images: TCustomImageList read FImages write SetImages;
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
    { 行被鼠标从行头槽拖动重排之前问一句;置 AAllow := False 可否决。 }
    property OnRowMove: TTyGridRowMoveEvent read FOnRowMove write FOnRowMove;
    { 编辑器显示之前交给宿主微调。 }
    property OnGetEditorProp: TTyGridEditorPropEvent
      read FOnGetEditorProp write FOnGetEditorProp;
    { 编辑器最小宽度(逻辑像素);0 = 跟着格走。 }
    property MinEditorWidth: Integer read FMinEditorWidth write FMinEditorWidth
      default 0;
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
    { 视口的左上角换格了。对标 LCL 的 OnTopLeftChanged(grids.pas:1315)。

      在此之前网格**没有任何**滚动通知:唯一沾边的 OnScrollHint 只是在拖纵向滑块
      时问宿主要一句提示文字,滚轮、键盘、ScrollIntoView 一概不发。于是"两个表格
      同步滚动""按可视窗口去后台取数""退出时记住滚到哪儿"都只能轮询。

      按**格**触发,不按像素:我们是平滑的像素滚动,滚三个像素并不换行,而 LCL 按
      整格滚动所以每次滚动必然换格 —— 照名字办事,LeftCol/TopRow 真的变了才发。 }
    property OnTopLeftChanged: TNotifyEvent
      read FOnTopLeftChanged write SetOnTopLeftChanged;
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
    { **画出来的**那串文字。与 GetCellText(原始值)分开:格式化只作用于显示,
      编辑器/导出/排序一律走原始值。绘制路径只能走这个。
      基类没有格式化钩子,原样返回;TTyStringGrid 改写去问 OnGetFormat。 }
    function DisplayCellText(ACol, ARow: Integer): string; virtual;
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
      组一折叠,成员行就不在显示序里了,小计会变成 0。
      多级分组时,一行会同时算进它**所有祖先**组里,于是每一级的小计各自成立。 }
    Rows:     array of Integer;
    { 第几级(0 = 最外层)。分组行按它缩进。 }
    Level:    Integer;
    { 从最外层到本级的键拼起来。折叠状态按**路径**记账 ——
      按单个键记的话,不同地区下的同名城市会被一起折叠。 }
    Path:     string;
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
  { 在编辑**被允许关闭之前**触发,带着编辑器此刻的文本。置 AValid := False 就是拒绝:
    编辑器留在原格、光标不动、不抢焦点,用户要么改对要么按 Esc 放弃。
    只在文本确实改过时才问(没动过的格永远可以离开);只对**用户驱动**的关闭生效
    (回车/Tab/方向键/点别的格/编辑器失焦)。结构性关闭(排序、插删行列、CSV 载入、
    EditorMode := False)挡不住,但校验没过的值会被**丢弃**而不是写回 ——
    所以非法值不管走哪条路都进不了单元格。本事件管"能不能离开";OnCellEdited 仍管"写不写"。 }
  TTyGridValidateCellEvent = procedure(Sender: TObject; ACol, ARow: Integer;
    const AOldText, ANewText: string; var AValid: Boolean) of object;

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
    { 枚举"写过的格"的键时用的临时目标(SnapshotCellKeys 的接收方)。
      从前这里挂着一份**有序的** FCellKeys 平行表,每写一格 Add 一次:
      有序 TStringList 的插入要 memmove 半个表,于是填表整体是 O(n²) ——
      10 万行填到一半就像卡死。稀疏存储本身(FCells 哈希表)就知道写过哪些格,
      那份平行表是多余的。 }
    FKeySink: TStrings;
    FCol: Integer;                { 当前单元格(光标) }
    FRow: Integer;
    FOnSelectCell: TTyGridSelectCellEvent;
    FEditor: TTyEdit;
    FEditing: Boolean;
    { 筛选行的编辑器 —— 与单元格编辑器**分开**。
      A4 的教训:让一个控件服务两种语义(那次是日期/时间共用一个选择器),
      开的时候按种类分派、关的时候按可见性分派,迟早对不上。
      这里两种编辑的提交去向完全不同(一个写单元格,一个改过滤条件),
      分开两个控件是最便宜的隔离。 }
    FFilterEditor: TTyEdit;
    FFilterEditCol: Integer;
    { 输入即筛要防抖:百万行的表每敲一个键就重建一次显示序会卡死。 }
    FFilterTimer: TTimer;
    FEditCol: Integer;
    FEditRow: Integer;
    FEndingEdit: Boolean;         { 防重入:提交过程里又触发提交 }
    FReadOnly: Boolean;
    FDefaultEditorKind: TTyGridEditorKind;
    FOnGetEditorKind: TTyGridGetEditorKindEvent;
    FOnCellEdited: TTyGridCellEditedEvent;
    FOnValidateCell: TTyGridValidateCellEvent;
    FValidatedPending: Boolean;   { TryEndEdit 刚问过宿主 —— EndEdit 别再问第二遍(宿主可能在弹框) }
    FOnCanEditCell:  TTyGridCanEditEvent;
    FOnEditChange:   TTyGridEditChangeEvent;
    FOnCanInsertRow: TTyGridCanRowEvent;
    FOnCanDeleteRow: TTyGridCanRowEvent;
    FOnReturn:       TTyGridCellKeyEvent;
    FOnCtrlReturn:   TTyGridCellKeyEvent;
    FOnScrollHint:   TTyGridScrollHintEvent;
    FOnCellLinkClick: TTyGridCellLinkEvent;
    FOnColumnCalc:    TTyGridColumnCalcEvent;
    FOnGetFormat:     TTyGridGetFormatEvent;
    FOnGetFilterValues: TTyGridGetFilterValuesEvent;
    FAllowGrayed:    Boolean;
    { 全表有没有批注。渲染与悬停路径都要问一次"这格有批注吗",
      没有批注的表不该为此每格建一个临时键(与 FAttrs.IsEmpty 同一条理由)。 }
    FHasComments:    Boolean;
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
    { 逐列的汇总缓存。页脚每帧都要问一次,而算一次要遍历全部显示行。
      长度 <> 列数 = 整体失效(见 InvalidateAggregates)。 }
    FAggCache: array of Double;
    FAggValid: array of Boolean;
    { 逐格附加属性(合并跨度、以及留给后面几批的底色/字体/只读)。
      与 FCells 同一套键。**合并信息从前是自己一张表**,增删行时漏搬,已并进来。 }
    FAttrs: TTyGridCellAttrStore;
    { Cols[]/Rows[] 交出去的活视图,按下标缓存(键是 IntToStr(下标),
      **只用来查,从不按这个顺序遍历** —— 字典序下 "9" 排在 "10" 后面,
      拿它当次序用就会踩到那个老坑)。缓存是必须的:视图对象归网格所有,
      每次取都新建一个等于每次调用泄漏一个。惰性建,随网格释放。 }
    FColViews: TStringList;
    FRowViews: TStringList;
    FOnGetFooterText: TTyGridGetFooterTextEvent;
    { 分组列,从外到内。空 = 不分组。
      单列分组是它只有一项的退化情形,所以老的 GroupByColumn / GroupColumn
      原样还能用 —— 不必让既有代码跟着改。 }
    FGroupCols: array of Integer;
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
    { Shift 扩选期间置位:此时 MoveCursor **不**重锚,选区才拉得长。
      默认(不置位)是重锚 —— 见 MoveCursor 里的说明。 }
    FExtendingSelection: Boolean;
    { 正在拖填充柄;FFillToRow/Col 是当前拖到的格。 }
    { 这次编辑**实际打开**的是哪一种编辑器。
      关编辑时按它分派 —— 不能从"哪个控件可见"反推:日期与时间共用一个控件,
      可见性根本区分不出它们(时间格因此被当日期提交,写坏了数据)。 }
    FEditKind: TTyGridEditorKind;
    FFillDragging: Boolean;
    FFillToCol, FFillToRow: Integer;
    FOnFillCells: TTyGridFillEvent;
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
    { 用户在筛选行里**打的原文**(列索引 -> 表达式)。与 FColFilters 分开存:
      那边是编码后的条件,回显给用户看的必须是他自己打的那一串。 }
    { 树形:折叠了哪些**数据行**(存行号)。与分组的折叠分开 ——
      那边按层级路径记,这边按行,两者可以同时开着。 }
    FTreeCollapsed: TStringList;
    FFilterText: TStringList;
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
    FRangeSelectMode: TTyGridRangeSelectMode;
    FOnSelectionChanged: TNotifyEvent;
    { 有没有被编辑过(自建表/装载以来)。见 Modified 属性的说明。 }
    FModified: Boolean;
    { 排序指示器被 HideSortArrow 熄掉了。排序键**没有**被清 —— 见 HideSortArrow。 }
    FSortArrowHidden: Boolean;
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
    { Cols[] 与 Rows[] 只差"哪条轴",取视图的那一段一模一样 —— 合成一处,
      免得将来只改一边(缓存的两份逻辑走散是这类代码最常见的坏法)。 }
    function  ColsRowsView(var ACache: TStringList; AIsCol: Boolean;
      AIndex: Integer): TStrings;
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
    function WidenEditorRect(ACol, ARow: Integer; const ARect: TRect): TRect;
    function DoBeginEdit(ACol, ARow: Integer): Boolean;
    procedure RecordRowCountUndo(AOldCount: Integer); override;
    procedure OpenUndoGroup; override;
    procedure CloseUndoGroup; override;
    procedure DoRowDragMove(AFrom, ATo: Integer); override;
    function DisplayOrderIsDataOrder: Boolean; override;
    function CanSortPhysically: Boolean;
    procedure ApplyOrderToData;
    function SelectionBoundsRect: TRect;
    function ArithmeticStep(ACol, AFrom, ATo: Integer;
      out AFirst, AStep: Integer): Boolean;
  private
    FSkipReadOnly: Boolean;
    FGroupRowFormat: string;
    FSortDir: TTySortDirection;
    FSortKind: TTyGridSortKind;
    FOnCompareCells: TTyGridCompareEvent;
    procedure CollectKey(Item: string; const Key: string; var AContinue: Boolean);
    procedure SnapshotCellKeys(ADest: TStrings);
    procedure ShiftCells(AFromIndex, ADelta: Integer; ARows: Boolean);
    procedure FilterPopupClosed(Sender: TObject);
    procedure InvalidateOrder;
    procedure RebuildOrder;
    procedure BuildGroups;
    function  AnyAncestorCollapsed(const AOpen: array of Integer;
      ALevel: Integer): Boolean;
    function  GetGroupCol: Integer;
    function  IsGroupColumn(ACol: Integer): Boolean;
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
    { Esc ONLY, for the editors that cannot share EditorKeyDown because they spend Enter on
      their own content: the memo (Enter is a newline), the spin/slider/calc/date pickers
      (Enter and the arrows drive their value). Abandoning an edit is the one gesture every
      editor owes the user, and it was reaching only two of them. }
    procedure EditorCancelKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    { The combo's Esc: an OPEN dropdown eats it to close itself, which is what the user meant;
      only a closed one abandons the edit. }
    procedure PickEditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);

    procedure FilterEditorChange(Sender: TObject);
    procedure FilterEditorExit(Sender: TObject);
    procedure FilterDebounceTick(Sender: TObject);
    procedure EditorExit(Sender: TObject);
    { 当前打开的编辑器此刻持有的文本,**不关闭任何东西**地读出来。EndEdit 也经它取值,
      于是宿主校验时看到的字符串和最终写回的是同一个,不可能漂成两个。 }
    function PendingEditText: string;
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
    function  GetSelectedRange(AIndex: Integer): TRect;
    function  GetSelectedRangeCount: Integer;
    function  GetEditorMode: Boolean;
    procedure SetEditorMode(AValue: Boolean);
    function  GetSelectedColumn: TTyGridColumn;
    function  GetModified: Boolean;
    procedure SetModified(AValue: Boolean);
    { Backing pair for the read/write Selection property (declared further down --
      Object Pascal wants the accessors first). }
    function  GetSelection: TRect;
    procedure SetSelection(const AValue: TRect);
    { 全状态流的内容段(数据行序)。见实现处的说明。 }
    function  StateContentText: string;
    procedure SetRow(AValue: Integer);
  protected
    function  GetCellText(ACol, ARow: Integer): string; override;
    procedure RenderCells(P: TTyPainter; const M: TTyGridMetrics;
      const AFrame: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { 焦点离开了**整个网格**才会到这里 —— 移到网格里的另一格时 LCL 的 CM_EXIT 只送到
      编辑器为止。被校验拦下的编辑到这里就算放弃:走开和按 Esc 是同一种表态。 }
    procedure DoExit; override;
    { 直接敲可打印字符就进编辑并把这个字符当作第一笔 —— 表格录入的基本手感。
      从前只有 KeyDown、没有 KeyPress 覆写,必须先按 F2 或双击才能输入。 }
    procedure KeyPress(var Key: Char); override;
    { 多字节按键(中日韩输入法提交的字)**只能**从这里进来。LCL 递给 KeyPress 的是
      Char(Message.CharCode),而 CharCode 是一个 UTF-16 码元:'中'(U+4E2D)在这一步
      被压成单字节,按系统代码页转不出来就成了 '?' —— 敲中文开编辑,格子里躺着的就是
      那个 '?'。UTF8KeyPress 拿到的才是完整的 UTF-8 字。
      单字节仍旧走 KeyPress(那边 Key := #0 的吞键语义原封不动),这里只补它接不住的
      那一半;接住之后 FEditing 已经是 True,随后到达的 KeyPress 第一句就退出去了。 }
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    { 用 AChar 作为第一笔开编辑。KeyPress 与 UTF8KeyPress 共用,免得"覆盖原值"
      这条与 Excel 对齐的规则写两遍、走两样。 }
    function  TypeIntoCell(const AChar: string): Boolean; virtual;
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
    { 筛选行的编辑器。与上面那个是**两个**控件 —— 见字段处的说明。 }
    property FilterEditor: TTyEdit read FFilterEditor;
    { protected 暴露给测试 —— 回车/Esc 的分派是筛选行唯一的键盘契约。 }
    procedure FilterEditorKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    { 编辑器里的按键级过滤。**必须挂在编辑器上** —— 网格自己的 KeyPress
      开头就 `if FEditing then Exit`,所以它只管得到开编辑的第一个字符;
      F2/双击进来之后的每一次敲击都到不了那里。
      protected:测试要从编辑器这一侧敲键。 }
    procedure EditorKeyPress(Sender: TObject; var Key: Char);
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
    { 这一格能不能编辑(T6)。与 EditorKindFor 分开:那个管**长什么样**,
      这个管**能不能动**。 }
    function CanEditCell(ACol, ARow: Integer): Boolean; virtual;
    { 拖纵向滚动条时的提示文字(T10)。没挂钩子返回空串。 }
    function ScrollHintFor(ATopRow: Integer): string; virtual;
    procedure EditorTextChanged(Sender: TObject);
    { 勾选框语义:'1'/'true'/'是'/'y' 都算勾上。写回时统一成 '1'/''。 }
    function  CellDisplayFor(ACol, ARow: Integer): TTyGridCellDisplay; virtual;
    { 基类的问法(按钮矩形/命中要用),转给上面这个。 }
    function  CellDisplayOf(ACol, ARow: Integer): TTyGridCellDisplay; override;
    function  IsActiveCell(ACol, ARow: Integer): Boolean; override;
    function  IsActiveRow(ARow: Integer): Boolean; override;
    { Options 的 goEditing / goRowSelect 两位在这里才有真身。
      goEditing 是 ReadOnly 的**反**面 —— 名字反过来是 LCL 的选择,不是我们的,
      同名同义比"我们觉得哪个更顺"重要。 }
    function  GetOptEditing: Boolean; override;
    procedure SetOptEditing(AValue: Boolean); override;
    function  GetOptRowSelect: Boolean; override;
    procedure SetOptRowSelect(AValue: Boolean); override;
    procedure KeepCursorVisible; override;
    function  FAttrs2Find(ACol, ARow: Integer): TTyGridCellAttr; override;
    function  ShouldDrawCellText(ACol, ARow: Integer): Boolean; override;
    { **画出来的**那串文字。与 GetCellText(原始值)分开:
      格式化只作用于显示,编辑器/导出/排序一律走原始值。
      绘制路径**只能**走这个,否则"哪些地方算显示"会散成一堆判断。 }
    function  DisplayCellText(ACol, ARow: Integer): string; override;
    { goTruncCellHints 用:这一格的文字放不下就答全文,放得下答空串。
      protected 而不是 private —— 派生类改写了 DisplayCellText / 列宽的话
      也该能改写"什么算放不下"。 }
    function  TruncatedCellHint(ACol, ARow: Integer): string; virtual;
    function  CellAppearance(ACol, ARow, ADisplayPos: Integer;
      const AFrame: TTyStyleSet): TTyGridCellAppearance; override;
    function  HoverIsHyperlink(X, Y: Integer): Boolean; override;
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
    function  HyperlinkTextColor(const AFallback: TTyColor): TTyColor;
    { 超链接单元格的下划线 + 批注标记。文字本身仍走通用的文字层
      (链接色由 CellAppearance 从 TyGridHyperlink 取)。 }
    procedure RenderHyperlinkCell(P: TTyPainter; ACol, ARow: Integer;
      const AFrame: TTyStyleSet);
    procedure RenderCommentMark(P: TTyPainter; ACol, ARow: Integer;
      const AFrame: TTyStyleSet);
    procedure RenderPickListArrow(P: TTyPainter; ACol, ARow: Integer;
      const AFrame: TTyStyleSet);
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
    { 把一格喂进累加器。virtual:派生类可以换聚合口径,
      测试也靠它数"一帧扫了多少格"(汇总缓存的守卫)。 }
    procedure AccumulateCell(ACol, ADataRow: Integer; AKind: TTyGridAggregate;
      var AAcc: Double; var ACount: Integer; var AStarted: Boolean); virtual;
    function  AggregatePrefix(AKind: TTyGridAggregate): string;
    procedure RenderSelectionFrame(P: TTyPainter; const M: TTyGridMetrics;
      const AFrame: TTyStyleSet); virtual;
    procedure RenderGroupRow(P: TTyPainter; APos, AGroupIndex: Integer;
      const M: TTyGridMetrics; const AFrame: TTyStyleSet); virtual;
    { 分组行上的折叠三角槽。命中与绘制共用。 }
    function  GroupToggleRect(APos: Integer): TRect;
    function DisplayToData(APos: Integer): Integer; override;
    function DataToDisplay(ARow: Integer): Integer; override;
    function DisplayRowCount: Integer; override;
    procedure SetShowGroupSubtotals(AValue: Boolean);
    procedure SetUndoLimit(AValue: Integer);
    { 记一笔。不在事务里时自成一条(单格编辑就是这种)。 }
    procedure RecordUndo(const AEntry: TTyGridUndoEntry);
    { **所有按行下标记账的旁挂状态**在纯置换时的收口。AMap[旧行] = 新行,
      AMap[i] < 0 表示那一行没了(条目丢弃)。

      为什么要收口:两条纯置换路径(SwapRows / ApplyOrderToData)此前各搬各的,
      各漏了不同的东西 —— 交换漏了隐藏标记(藏着的行换个位置就冒出来),
      物理排序漏过格属性(A3)。**新增一种按行记账的存储时,改这里一处。**

      没做成"登记表 + 回调"的原因:这类存储只有两张,而它们的写回路径本就不同 ——
      行高必须走 SetRowHeights(撤销的记录点在那儿),隐藏标记直接进表。
      为两张表建一套注册框架,读起来比它替掉的重复更难。
      增删行是另一类(行数会变),收口在 ShiftRowKeyedTable —— 加表时那里也要加。 }
    procedure PermuteRowState(const AMap: array of Integer);
    { 上一个的**增删版**:行数会变,所以不是置换而是平移。
      从 AFromIndex 起整体挪 ADelta;ADelta < 0 时正落在 AFromIndex 上的那条丢弃。

      为什么不直接用 `ShiftRowKeyedTable` 重建两张表:那样绕过了
      `SetRowHeights` / `SetRowHidden` 两个记录点 —— 撤销一次增/删行之后,
      文字回来了而行高和隐藏标记**永久错位一格**,被删那一条更是无处可还。 }
    procedure ShiftRowStateWithUndo(AFromIndex, ADelta: Integer);
    { 增删行**穿过**某个合并块时,把它的行跨度跟着改掉。

      搬迁本身早就对了(基准格与属性一起走),漏的是跨度:在块内部插一行,
      块还是原来那么高 —— 插进来的空行被吞进块里,块尾那一行反被挤出块外。
      删除是反过来:块该缩小,却把块外的一行吸进来。 }
    procedure GrowMergesSpanningRow(AFromIndex, ADelta: Integer);
    { 增删列之后把撤销栈整个丢掉。

      **列结构本身进不了撤销栈**:记录点是 SetCells 与 SetRowCount,
      而列的增删改的是 Header.Columns —— 两个口子都够不着。于是格子内容
      被记下了、承载它们的那一列没有,撤销会把内容还原到一张列数不同的表上,
      得到一个从未存在过的状态。

      与其还原出一张四不像的表,不如明说这一步撤不了 ——
      与"超大记录整条作废"是同一条原则。
      (让列结构真正可撤销是独立的一件事,记在 grid-remaining 计划里。) }
    { 把一列的全部身份取成值快照 / 按快照把一列还原成那个样子。 }
    function  SnapshotColumn(ACol: Integer): TTyGridColumnSnapshot;
    procedure ApplyColumnSnapshot(ACol: Integer;
      const ASnap: TTyGridColumnSnapshot);
    { 记一笔列结构的改动。三种用法见 TTyGridUndoKind 的说明。 }
    procedure RecordColumnUndo(AKind: TTyGridUndoKind; ACol: Integer;
      ATo: Integer; const ASnap: TTyGridColumnSnapshot); overload;
    procedure RecordColumnUndo(AKind: TTyGridUndoKind; ACol: Integer;
      ATo: Integer = -1); overload;
    { 汇总缓存整体失效。三处汇过来:数据改(SetCells)、显示序变(InvalidateOrder,
      筛选/隐藏/分组/行数都归它)、换聚合口径(SetColumnAggregate)。 }
    procedure InvalidateAggregates;
    { 属性存储的记录点。挂在 TTyGridCellAttrStore.OnChanging 上 ——
      于是改底色/文字色/只读/合并跨度、以及三条行置换路径搬属性,
      **一律**自动进撤销栈,不必每个功能各写一段(那正是本控件反复漏东西的方式)。 }
    { 隐藏标记的记录点。`PermuteRowState` 搬四样东西,前三样都有记录点、
      这一样从前没有 —— 拖完行按 Ctrl+Z,文字回来了而藏着的还是换过去那一行。
      HideRow / UnHideRow / 行置换全部经由它。 }
    { 基类只清行高;隐藏标记在这里,补上。 }
    procedure TrimRowStateTo(ANewCount: Integer); override;
    procedure SetRowHidden(ARow: Integer; AHidden: Boolean);
    procedure HandleAttrChanging(const AKey: string);
    function  SnapshotAttr(const AKey: string): TTyGridAttrSnapshot;
    procedure RestoreAttr(const AKey: string; const ASnap: TTyGridAttrSnapshot);
    { 行高的记录点。行高是**行**的属性,不经过 Cells[],所以 SetCells 那个
      收口点够不着它 —— 拖完行 Ctrl+Z 只回来文字就是这么来的。 }
    procedure SetRowHeights(ARow, AValue: Integer); override;
    procedure PushUndoStep(const AStep: TTyGridUndoStep);
    { 把一条记录逆着放回去,并返回它的"反记录"(供重做用)。 }
    function  ApplyUndoStep(const AStep: TTyGridUndoStep): TTyGridUndoStep;
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
    { 插入 / 删除某一行的否决闸(T8)。复数版的 InsertRows / DeleteRows
      也走它们 —— 逐行问,任何一行被否决就整批不做。 }
    function  CanInsertRow(ARow: Integer): Boolean; virtual;
    function  CanDeleteRow(ARow: Integer): Boolean; virtual;
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
    { 剪切 = 复制 + 清空(只读格不清)。键盘手势 Ctrl+X(KeyDown 里与 C/V 一排)。 }
    procedure CutToClipboard;

    { 把某列宽度自动适配到内容(取表头与**已写入**单元格里最宽的那个)。
      只量已写过的格,所以百万行空表也不会扫全表。 }
    procedure AutoFitColumn(ACol: Integer);
    procedure AutoFitColumnWidth(ACol: Integer); override;

    { 清空全部单元格内容(不动行列结构)。 }
    procedure ClearCells;
    { 只清一段行 / 一段列(T5)。此前只有整表的 ClearCells,
      想清一片只能宿主逐格写空串 —— 而那样撤销是一格一格退的。
      走 SetCells 收口点 → 自动可撤销;整批算**一条**记录。
      范围越界一律钳到表内,不抛异常(与列宽/跨度的钳制同一条纪律)。 }
    { --- 逐格能力与汇总重算:**必须在 public**,这些是给宿主用的。
      它们一度被插在 protected 段的 CellChecked 旁边,于是测试(走子类)
      全绿而宿主一行都调不到。TestNewApiIsReachableByHost 用裸
      TTyStringGrid 变量守着这条。 }
    function  CellChecked(ACol, ARow: Integer): Boolean;
    { 这一列的勾选词汇(见 TTyGridColumn.ValueChecked)。列没设时两个都是空串。
      **public** 是因为宿主接了 OnGetCellText 的虚拟表也要按同一套词汇写回去 ——
      让它去猜控件此刻用的是哪两个词,就是下一次数据被换掉的写法。 }
    procedure CheckWordsOf(ACol: Integer; out AChecked, AUnchecked: string);
    { 三态读值(T11)。语义**复用 TTyCheckBox** 的 TCheckBoxState,
      不在网格里另定义一套。 }
    function  CellCheckState(ACol, ARow: Integer): TCheckBoxState;
    procedure ToggleCellChecked(ACol, ARow: Integer);
    { 逐格批注(T13)。存进逐格属性存储 → 自动可撤销、自动跟着行置换走。 }
    function  GetCellComment(ACol, ARow: Integer): string;
    procedure SetCellComment(ACol, ARow: Integer; const AValue: string);
    property  CellComment[ACol, ARow: Integer]: string
      read GetCellComment write SetCellComment;
    { 逐格显示类型(T14)。同上,存属性存储。 }
    { 逐格字体样式(T20)。存储槽(HasFontStyle / FontStyle)早就在属性
      存储和撤销快照里了 —— 缺的只是公开属性和"在 CellAppearance 里读它"。 }
    function  GetCellFontStyles(ACol, ARow: Integer): TFontStyles;
    procedure SetCellFontStyles(ACol, ARow: Integer; AValue: TFontStyles);
    property  CellFontStyles[ACol, ARow: Integer]: TFontStyles
      read GetCellFontStyles write SetCellFontStyles;
    function  GetCellDisplay(ACol, ARow: Integer): TTyGridCellDisplay;
    procedure SetCellDisplay(ACol, ARow: Integer; AValue: TTyGridCellDisplay);
    property  CellDisplays[ACol, ARow: Integer]: TTyGridCellDisplay
      read GetCellDisplay write SetCellDisplay;
    { 宿主挂在某一格上的任意对象 —— LCL 的 TCustomStringGrid.Objects[ACol,ARow]
      (grids.pas:1795)。"这一行是哪一条记录"的标准落点。

      **网格不拥有它**:不释放、不复制、不流式化。设成 nil 即取下。

      它与这一格的其他属性住同一条稀疏记录里,所以物理排序(SortMode = gsmData)、
      插行、删行、换行、拖行**都会带着它一起搬** —— 宿主不必再维护一张按行下标
      记账的平行表并在每次结构变动后重新对齐,那张表正是这个属性要消灭的东西。

      **不进撤销栈**:撤销栈是值语义的,而这是别人的指针 —— 记进去就等于允许
      Ctrl+Z 交还一个宿主可能已经释放的地址。因此撤销既不把对象槽搬回原位,
      也绝不销毁它;结构性编辑撤销之后,槽位停在正向操作把它放下的地方,
      需要精确还原的宿主请照自己的数据重挂一遍。 }
    function  GetObjects(ACol, ARow: Integer): TObject;
    procedure SetObjects(ACol, ARow: Integer; AValue: TObject);
    property  Objects[ACol, ARow: Integer]: TObject
      read GetObjects write SetObjects;
    { 批注标记的矩形(格子右上角的小三角)。没有批注时是空矩形。 }
    function  CommentMarkRect(ACol, ARow: Integer): TRect;
    { 强制重算**某一列**的汇总。宿主改了外部数据源时需要一个明确的入口 ——
      InvalidateAggregates 是整表失效,拿来做这件事太钝。
      ACol < 0 = 整表(等价于 InvalidateAggregates)。 }
    procedure CalcFooter(ACol: Integer);

    { --- 清空:内容 vs 结构 ---
      These two pairs do OPPOSITE KINDS of thing and the naming has to say so.

      ClearRowContents / ClearColContents blank the cell CONTENT over a band; the rows
      and columns stay. They were called ClearRows / ClearCols, which are LCL's names
      for the structural DELETE (grids.pas:10285-10316, `function ClearRows: Boolean`).
      Same name, opposite kind: any host wrapper forwarding ClearRows silently changed
      meaning, and adding the LCL member as a zero-argument overload would have made
      "delete every row" and "blank two rows" differ only by argument count. So the band
      blanking was renamed instead -- ClearRows can no longer be reached by accident. }
    procedure ClearRowContents(AFrom, ACount: Integer);
    procedure ClearColContents(AFrom, ACount: Integer);

    { Structural clear, LCL semantics: drop every row / every column and answer whether
      anything actually changed (False = it was already empty), as LCL does.

      Content goes with the structure. Our cell store is sparse and keyed by (col,row),
      so leaving the strings behind would resurrect the old contents the moment RowCount
      grew again -- LCL has no such hazard because its rows OWN their cells. }
    function  ClearRows: Boolean;
    function  ClearCols: Boolean;
    { 整表清空:行、列、内容一起没。LCL grids.pas:1342,body at :10302 = ClearRows +
      ClearCols,这里逐字照做。

      别与 ClearCells 混:那个只清内容、行列结构原封不动。把 LCL 的 Clear 映射到
      ClearCells 是最自然的误译,而它会把列留在原地 —— 于是"清空后重新装载"的表
      每装载一次就多一批旧列。 }
    procedure Clear;
    { 写过的单元格个数 —— 稀疏性的可观测证据。 }
    function StoredCellCount: Integer;
    { 逐格属性记录的条数 —— 上一条在属性侧的对偶。合并、底色、批注、
      对象槽…… 每一格顶多占一条,而"设了又清"必须把条目还回来。 }
    function StoredCellAttrCount: Integer;

    { 开始编辑当前(或指定)单元格。只读、或该格编辑器为 gekNone 时不开。 }
    function BeginEdit: Boolean; overload;
    function BeginEdit(ACol, ARow: Integer): Boolean; overload;
    { 结束编辑。ACommit=True 写回存储(经 OnCellEdited 可否决)。 }
    procedure EndEdit(ACommit: Boolean);
    { 可被否决的结束编辑:先问 OnValidateCell,不过就返回 False 并**什么都不动**
      (编辑器留着、光标不动、不抢焦点);过了才真的 EndEdit。ACommit=False(放弃)
      从不被否决。用户驱动的关闭走这里;结构性关闭仍走 EndEdit,那条路挡不住。 }
    function TryEndEdit(ACommit: Boolean): Boolean;
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
    { LCL 拼的是复数(grids.pas:1343 `procedure ClearSelections`)。同义,
      单数那个是本库的原名并保留 —— 一个字母的差别不值得让老代码全改一遍,
      但也不值得让移植过来的代码编不过。 }
    procedure ClearSelections;
    { 活动选区(数据行坐标)。离散多选时只代表最后那一块。

      READ/WRITE, like LCL's TCustomGrid.Selection (grids.pas:1292). It used to be a
      read-only `function Selection: TRect`, with SelectRange/SelectRows as the only way
      in -- so the most ordinary thing a host does with a selection, save it and put it
      back later, was a rewrite rather than an assignment. Reading is unchanged
      (`R := Grid.Selection` still compiles), so this only adds the missing half.

      Writing takes DATA-ROW coordinates, symmetric with what reading gives back;
      out-of-range values are clamped and a reversed rect is normalised, so
      `Grid.Selection := Grid.Selection` is a no-op. An all-negative rect cancels the
      selection (LCL's SetSelection -> CancelSelection) -- which matters because that is
      exactly the shape an empty selection reads back as. }
    property  Selection: TRect read GetSelection write SetSelection;
    { --- 离散多选的枚举 ---
      对标 LCL 的 SelectedRange[] / SelectedRangeCount / HasMultiSelection
      (grids.pas:1377/:1378/:1356)。

      Ctrl+点可以选出好几块,这一直是成立的 —— 但对外唯一的读口子是 Selection,
      而它只给**最后**那一块。于是宿主遍历"选区"时,前面几块被静默丢掉:
      用户明明选了三片、复制出来只有一片,而控件不觉得有什么不对。

      索引 0 恒为**活动**矩形(锚点<->光标的那一块),之后才是已固化的那些,
      顺序与用户 Ctrl+点的先后一致。坐标与 Selection 一样是**数据行**。
      Count 至少为 1:网格总有一个当前格,"一块都没有"不是它的状态。 }
    property  SelectedRange[AIndex: Integer]: TRect read GetSelectedRange;
    property  SelectedRangeCount: Integer read GetSelectedRangeCount;
    function  HasMultiSelection: Boolean;
    { 选中的单元格总数(0 表示只有光标那一格)。 }
    function SelectedCellCount: Integer;
    { 选区聚合 —— 状态栏那句"已选 12 项,合计 3400"。
      只统计**数值可解析**的格,非数值格直接跳过(与列聚合同一条规则)。 }
    function SelectionSum: Double;
    function SelectionAvg: Double;
    function SelectionMin: Double;
    function SelectionMax: Double;

    { 给**整个选区**设底色 / 文字色。传 0(TyColorNone)= 清除。返回改了几格。

      为什么要有这一对而不是让宿主自己写循环:遍历选区这件事有讲究 ——
      要走显示序、要跳过分组行、寻址要用数据行(排序筛选之后颜色才跟着数据走)。
      只读那半边早就收口在 `ForEachSelectedNumber` 了(四个聚合入口共用,
      注释写着"免得四份几乎一样的遍历各自跑偏"),写这半边却一直空着,
      于是每个宿主各写一遍 —— 而**没有人会记得包事务**,结果就是
      涂了一片、撤销时一格一格退。这一对内部走 BeginUpdate,一次涂色一次撤销。 }
    function SetSelectionColor(AColor: TTyColor): Integer;
    function SetSelectionTextColor(AColor: TTyColor): Integer;
  private
    procedure ForEachSelectedNumber(out ACount: Integer;
      out ASum, AMin, AMax: Double);
    { 写侧的选区遍历骨架。ATextColor = False 时设底色,True 时设文字色。 }
    function  ApplySelectionColor(AColor: TTyColor; ATextColor: Boolean): Integer;
  public

    { 该列出现过的**去重值**(按显示序的原始数据,不受本列自身过滤影响)——
      列头筛选下拉就是拿它当候选。 }
    procedure DistinctColumnValues(ACol: Integer; AItems: TStrings);
    { 打开某列的列头筛选下拉。 }
    procedure ShowColumnFilterDropDown(ACol: Integer);

    { 给某列设"包含"过滤(不区分大小写)。传空串即清掉该列的过滤。 }
    { --- 树形单元格 ---
      折叠/展开某一行(它必须是有孩子的那种)。折叠 = 它的子孙从显示序里消失。 }
    procedure ToggleNode(ARow: Integer);
    function  NodeCollapsed(ARow: Integer): Boolean;
    function  NodeCollapsedOf(ARow: Integer): Boolean; override;
    procedure ExpandAllNodes;
    procedure CollapseAllNodes;

    { --- 内嵌筛选行 ---
      在筛选行里打的**表达式**(`>100`、`a..b`、`x;y`……见 TyGridParseFilterExpr)。
      设进去就立刻按它筛;传空串清掉这一列。
      与 SetColumnFilter 的区别:那个吃的是已经定好比较方式的单条条件,
      这个吃的是用户打的一串,自己解析。 }
    { 在某列的筛选位里开编辑器(点筛选行就走它)。 }
    { 这一行是不是被某个**祖先**折叠了(它自己折没折不影响它显不显示)。 }
    function  RowCollapsedByTree(ARow: Integer): Boolean;
    procedure BeginFilterEdit(ACol: Integer);
    { 收掉筛选行编辑器;AApply=True 时把当前输入立刻生效。 }
    procedure EndFilterEdit(AApply: Boolean);
    procedure SetFilterText(ACol: Integer; const AExpr: string);
    { 那一列筛选行里显示的原文(用户打的那一串,不是编码后的条件)。 }
    function  FilterText(ACol: Integer): string;
    function  FilterRowText(ACol: Integer): string; override;
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
    { There used to be a `VisibleRowCount` here returning DisplayRowCount -- a third
      spelling of a metric that already had two (DisplayRowCount, FilteredRowCount)
      while squatting on LCL's name for a viewport metric. It is gone; the name now
      means what LCL means by it, on TTyCustomGrid. }

    { --- 分组 ---
      按某列分组:显示序里插入**合成的分组行**(它不对应任何数据行)。
      FOrder 里 >=0 是数据行,<0 是分组行(编码为 -(组号+1))。 }
    procedure GroupByColumn(ACol: Integer);
    procedure UngroupRows;
    { 第一级分组列(没分组时 -1)。多级请用 GroupByColumns / GroupColumns。 }
    property  GroupColumn: Integer read GetGroupCol;
    { 全部分组列,从外到内。 }
    function  GroupColumns: TTyIntArray;
    { 按多列分组(从外到内)。传空数组等于取消分组。 }
    procedure GroupByColumns(const ACols: array of Integer);
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
    { 填充柄的矩形(客户区坐标)。没有可填充的选区时返回空矩形。
      **命中与绘制同源** —— 绘制也用它,所以点得到的就是看得见的那一块。 }
    function  FillHandleRect: TRect;
    { 把当前选区的内容填充到 (ACol, ARow) 为止。
      语义:源区单格 = 复制;源区构成等差数列 = 外推;其余 = 按源区循环重复。 }
    procedure FillFromSelectionTo(ACol, ARow: Integer);
    { --- 版式持久化 ---
      把"用户把表调成什么样"存成一个字符串:列宽、列序、可见性、排序键、冻结数。
      存到哪由宿主决定(注册表 / ini / 数据库都行)—— 控件不该替宿主选存储介质。

      **不包含行高**:行高可以有 RowCount 那么多条,把一百万行的表存成一个字符串
      不是"版式",那是数据。行高更贴近数据而不是版式,宿主要存自己存。

      读回来是**全有或全无**:版本认不出、或串坏了,直接返回 False 且**一点不改**
      现状 —— 半套版式(列宽还原了、列序没还原)比完全不还原更难排查。 }
    function  SaveLayoutToString: string;
    function  LoadLayoutFromString(const AText: string): Boolean;

    { --- 撤销 / 重做 ---
      一次批量操作(粘贴、填充、删行)算**一条**,因为它们都在 BeginUpdate 里跑。 }
    procedure Undo;
    procedure Redo;
    function  CanUndo: Boolean;
    function  CanRedo: Boolean;
    procedure ClearUndo;
    { 栈里现有多少条(给宿主的状态栏/按钮可用性用)。 }
    function  UndoCount: Integer;
    { 当前正在用的编辑器控件(没在编辑时为 nil)。 }
    function  EditorControl: TControl;
    { 测试缝。当前打开的这个编辑器有没有接键盘处理 —— 也就是 Esc 能不能放弃这次编辑。
      这个缺口从外面看不见:OnKeyDown 在 TWinControl 上是 protected,测试问不到控件本身,
      所以九个编辑器里有七个压根没有放弃路径这件事一直没人发现。宿主自带的 EditLink
      编辑器不算在内 —— 那是宿主自己的键盘。 }
    function  EditorCanCancelForTest: Boolean;
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
    { CSV 导出。范围参数(T2)缺省 = 全表 —— 加参数不能改变既有调用的行为。
      越界一律钳到表内。范围走**显示序**,与不带范围时一致。

      AWriteTitles is LCL's WriteTitles (SaveToCSVStream, grids.pas:1815): the column
      captions were an unconditional line 0 here, so a headerless CSV -- an appendable
      log, a chunk of a larger file -- simply could not be produced. Defaults to True,
      which is both the old behaviour and LCL's default.

      AVisibleColumnsOnly is LCL's VisibleColumnsOnly (SaveToCSVStream, grids.pas:1815):
      the exporter walked every column index in range with no coVisible test, so a grid
      whose user hid two columns still dumped their contents -- a surprise at best and,
      for a column hidden BECAUSE it holds something private, a leak. Defaults to False,
      which is both the old behaviour and LCL's default. }
    function  SaveToCSVText(ADelimiter: Char = ',';
      AFromRow: Integer = -1; ARowCount: Integer = -1;
      AFromCol: Integer = -1; AColCount: Integer = -1;
      AWriteTitles: Boolean = True;
      AVisibleColumnsOnly: Boolean = False): string;
    { 导出 HTML 表格(含表头)。与 CSV 一致走显示序:所见即所得。 }
    function  SaveToHTMLText: string;
    procedure SaveToHTMLFile(const AFileName: string);
    { JSON 导出(T4)。每行一个对象,键取列标题;标题为空时退回 `colN`。
      **只做导出不做导入**:导入要面对任意 JSON 结构(嵌套、类型、数组),
      那是文件格式库的范畴 —— 与当初 SKIP 掉 XLS 是同一条理由。
      宿主要导入自己解析成二维文本再喂给 LoadFromCSVText。 }
    function  SaveToJSONText: string;
    { CSV 导入。默认是**替换式**(先清空)—— 那是既有行为,不能改。
      AAppend=True 时接在现有数据后面;AMaxRows 限制读多少条(-1 = 不限);
      AIgnoreRows 跳过表头之后的前几条(说明行)。

      AUseTitles is LCL's UseTitles (LoadFromCSVStream, grids.pas:1811): line 0 was
      always eaten as column captions, so a headerless file silently lost its first
      RECORD. Off, every line is data and the captions are left alone.

      ASkipEmptyLines is LCL's SkipEmptyLines (LoadFromCSVStream, grids.pas:1811):
      blank separator lines used to import as phantom empty ROWS. Defaults to False
      rather than LCL's True -- keeping every line is what this method has always done,
      and a blank line is a legitimate record in some tables. }
    procedure LoadFromCSVText(const AText: string; ADelimiter: Char = ',';
      AAppend: Boolean = False; AMaxRows: Integer = -1;
      AIgnoreRows: Integer = 0; AUseTitles: Boolean = True;
      ASkipEmptyLines: Boolean = False);
    procedure SaveToCSVFile(const AFileName: string; ADelimiter: Char = ',';
      AWriteTitles: Boolean = True; AVisibleColumnsOnly: Boolean = False);
    procedure LoadFromCSVFile(const AFileName: string; ADelimiter: Char = ',';
      AUseTitles: Boolean = True; ASkipEmptyLines: Boolean = False);

    { CSV 的流式读写。内部走的就是上面那套 CSV 文本 —— 只多一层流封装,
      **刻意不新造第二套序列化**:两套转义规则迟早走样,而含逗号/换行/引号
      的字段正是最容易走样的地方。
      编码固定 UTF-8 无 BOM,显式声明,别让宿主猜。

      These carry LCL's names for exactly this operation (grids.pas:1811/1815). They
      used to be called SaveToStream / LoadFromStream, which in LCL mean something
      else entirely -- and because ADelimiter had a DEFAULT, a ported one-argument
      `Grid.SaveToStream(ms)` compiled and quietly produced bare CSV: no column widths,
      no visibility, no frozen counts, no cursor, no selection. A signature that
      accepts a ported call and does something else is worse than one that will not
      compile, so the CSV pair moved to the name that describes it and SaveToStream /
      LoadFromStream below became the full-state pair LCL says they are. }
    procedure SaveToCSVStream(AStream: TStream; ADelimiter: Char = ',';
      AWriteTitles: Boolean = True; AVisibleColumnsOnly: Boolean = False);
    procedure LoadFromCSVStream(AStream: TStream; ADelimiter: Char = ',';
      AUseTitles: Boolean = True; ASkipEmptyLines: Boolean = False);

    { 全状态流式读写 —— 与 LCL TCustomGrid.SaveToStream / LoadFromStream 同义
      (grids.pas:1365/1372):存的是**整张表**,而不只是文字。

      Carried: structure (row count, columns with widths / visibility / order, frozen
      counts), content (every cell), and position (cursor, scroll offset, selection).
      NOT carried: per-cell colours, comments, read-only flags and merges -- LCL puts
      those behind soAttributes, which is not in the default SaveOptions either.

      Format is a small versioned text container: a few `key=value` header lines, a
      line reading `csv`, then the content. LCL uses XMLConfig; the files are not
      interchangeable across the two libraries in any case, so this reuses the CSV
      escaper already in the unit rather than growing a second set of quoting rules
      for the fields (comma / quote / newline) that are hardest to get right.

      A stream that is not in this format RAISES rather than falling back to CSV:
      guessing would put us straight back to "one call, two formats, no way to know
      which one you got". An EMPTY stream raises too -- it is not a saved grid, it is
      a caller who lost one. (LoadFromCSVStream keeps the old "empty stream = empty
      table" reading, where it is a sensible answer.) }
    procedure SaveToStream(AStream: TStream);
    procedure LoadFromStream(AStream: TStream);
    { 同一份东西写进/读出一个文件。对标 LCL 的 SaveToFile / LoadFromFile
      (grids.pas:1371/:1364,同样是 SaveToStream/LoadFromStream 的薄封装)。
      参数带 const —— LCL 那边是传值的 `FileName: string`,而按值传字符串在这里
      没有任何理由。格式与 SaveToStream 完全相同,不是 XMLConfig(见上)。 }
    procedure SaveToFile(const AFileName: string);
    procedure LoadFromFile(const AFileName: string);

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
    { **内建文本编辑器**这一个具体控件。注意它与 LCL 的 Editor 同名而窄得多:
      LCL 的 TCustomGrid.Editor (grids.pas:1243) 是可读可写的 TWinControl,指的是
      "此刻在用的编辑器";这个恒指那一个 TTyEdit,哪怕当前编辑的是下拉列表格。
      要"此刻在用的那一个"请用 InplaceEditor / EditorControl。 }
    property Editor: TTyEdit read FEditor;
    { 此刻真正在用的编辑器,没在编辑时 nil —— LCL 的 InplaceEditor
      (grids.pas:1276)就是这个意思,只读。
      与 EditorControl 同一个答案,类型是 TWinControl 而非 TControl:LCL 那边的
      类型是 TWinControl,而编辑器一定是窗口化控件,收窄不会丢东西。 }
    function  InplaceEditor: TWinControl;
    { 开/关编辑器的**一个布尔**,对标 LCL 的 EditorMode(grids.pas:1245)。
      读 = Editing;写 True = BeginEdit,写 False = EndEdit(True)(提交)。
      工具栏按钮 / Action 要绑的正是这么一个可写属性 —— 从前只有一读一双方法。 }
    property  EditorMode: Boolean read GetEditorMode write SetEditorMode;
    { 光标所在那一列的列对象(没有列时 nil)。LCL grids.pas:1291。
      从前得写 TTyGridColumn(Grid.Header.Columns.Items[Grid.Col]),而干这件事的
      现成助手 GridColumn 在 protected 段里,宿主够不着。 }
    property  SelectedColumn: TTyGridColumn read GetSelectedColumn;
    property PickEditor: TTyComboBox read FPickEditor;
    property Cells[ACol, ARow: Integer]: string read GetCells write SetCells;
    { 一整列 / 一整行,当成 TStrings 交出去 —— LCL 的 Cols[]/Rows[]
      (grids.pas:1794/1798)。`Memo.Lines := Grid.Cols[2]` 与
      `Grid.Rows[3] := MyList` 这两条几乎每个移植程序都有的写法就靠它们。

      交出来的是**活视图**,不是副本:读写都直接落到格子上,长度跟着网格走。
      对象也通过它可达(视图的 Objects[i] 就是那一格的 Objects[])。

      **赋值不改网格的结构**,逐字照 LCL(grids.pas:10882):只覆盖
      min(源长度, 视图长度) 项 —— 源短了,尾巴上那几格**原样留着**(不清空);
      源长了,多出来的项丢掉(不加行、不加列)。要"整行换掉"请先
      `Rows[r].Clear` 再赋值。整次赋值算**一条**撤销记录。

      视图对象归网格所有,按下标缓存 —— 同一个下标每次交出同一个对象,
      随网格一起释放。代价是"碰过多少个不同下标就留下多少个空壳视图",
      所以**别拿它遍历百万行的表**:那条路是 CSV / 剪贴板。
      缓存按下标而不是按列对象记账(与 LCL 同),删列/移列之后旧视图指的是
      那个**位置**,不是原来那一列。 }
    function  GetCols(AIndex: Integer): TStrings;
    procedure SetCols(AIndex: Integer; AValue: TStrings);
    function  GetRows(AIndex: Integer): TStrings;
    procedure SetRows(AIndex: Integer; AValue: TStrings);
    property Cols[AIndex: Integer]: TStrings read GetCols write SetCols;
    property Rows[AIndex: Integer]: TStrings read GetRows write SetRows;
    { 自建表 / 上一次装载或清零以来,有没有格子被改过。对标 LCL 的
      TCustomStringGrid.Modified(grids.pas:1797,在 TStringGrid 上 published)。

      收口在 SetCells 与结构性增删行,所以粘贴、填充柄、撤销/重做、勾选框、CSV
      装载——凡是改数据的路径——都算数,宿主不必逐个功能去接事件记账。
      **不是** CanUndo:撤销栈会被 ClearUndo 清、UndoLimit=0 时压根不记,而且撤到
      底也不代表"回到存盘时的样子"。宿主存过盘之后自己写 False 复位。
      LoadFromStream / LoadFromCSVText 装载完置 False:刚读进来的表不叫"改过"。 }
    property  Modified: Boolean read GetModified write SetModified;
    { 只熄掉表头的排序指示器,**一行都不重排**。LCL grids.pas:1357(body 3359:
      `FSortColumn := -1; InvalidateGrid`)。

      服务端排序的表要的正是这个:顺序由服务器定,控件只管画不画那个三角。
      ClearSortColumns 与 SortByColumn(-1) 都会把显示序退回原始数据顺序,
      所以都不能拿来做这件事。下一次真的排序时指示器自己回来。 }
    procedure HideSortArrow;
  published
    { 当前单元格。 }
    property Col: Integer read FCol write SetCol default 0;
    property Row: Integer read FRow write SetRow default 0;
    property OnSelectCell: TTyGridSelectCellEvent read FOnSelectCell write FOnSelectCell;
    { 整表只读:**用户手势写不进数据**。编辑器七条路都问它(双击 / F2 / 直接打字 /
      勾选框 / 评分 / 颜色 / "…"),三条非编辑器的写入手势也问它 —— 粘贴整体被拒
      (PasteFromText,含 Ctrl+V)、剪切退化为复制(CutToClipboard,与 TTyEdit 同规)、
      填充柄消失且 API 直调被拒(FillHandleRect / FillFromSelectionTo)。
      程序化写入(Cells[..] :=、LoadFromCSVText、Undo/Redo)**不受它管** ——
      ReadOnly 管用户,不管宿主,与本库每个编辑控件的含义一致。
      `Options` 里的 goEditing 是它的反视图。 }
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    { 选择粒度:单元格矩形 / 整行 / 整列。 }
    { 分组行的格式串:%s = 分组值,%d = 组内行数。 }
    property GroupRowFormat: string read FGroupRowFormat write FGroupRowFormat;
    property SelectionMode: TTyGridSelectionMode
      read FSelectionMode write SetSelectionMode default gsmCell;
    { 能不能 Ctrl+点选出好几块。对标 LCL 的 RangeSelectMode(grids.pas:1282)。

      **默认与 LCL 不同**,而且是有意的:LCL 默认 rsmSingle,本库一直无条件支持
      离散多选,把默认改成 rsmSingle 会从每一个既有窗体上悄悄拿掉一个功能。
      所以默认 rsmMulti(= 从前的行为),要单块的表显式设 rsmSingle。
      rsmSingle 下 Ctrl+点只是把选区挪过去,不再叠加。 }
    property RangeSelectMode: TTyGridRangeSelectMode
      read FRangeSelectMode write FRangeSelectMode default rsmMulti;
    property OnSelectionChanged: TNotifyEvent
      read FOnSelectionChanged write FOnSelectionChanged;
    property DefaultEditorKind: TTyGridEditorKind
      read FDefaultEditorKind write FDefaultEditorKind default gekText;
    property OnGetEditorKind: TTyGridGetEditorKindEvent
      read FOnGetEditorKind write FOnGetEditorKind;
    property OnCellEdited: TTyGridCellEditedEvent read FOnCellEdited write FOnCellEdited;
    property OnValidateCell: TTyGridValidateCellEvent read FOnValidateCell write FOnValidateCell;
    property OnCanEditCell: TTyGridCanEditEvent
      read FOnCanEditCell write FOnCanEditCell;
    property OnEditChange: TTyGridEditChangeEvent
      read FOnEditChange write FOnEditChange;
    property OnCanInsertRow: TTyGridCanRowEvent
      read FOnCanInsertRow write FOnCanInsertRow;
    property OnCanDeleteRow: TTyGridCanRowEvent
      read FOnCanDeleteRow write FOnCanDeleteRow;
    property OnReturn: TTyGridCellKeyEvent read FOnReturn write FOnReturn;
    property OnCtrlReturn: TTyGridCellKeyEvent read FOnCtrlReturn write FOnCtrlReturn;
    property OnScrollHint: TTyGridScrollHintEvent
      read FOnScrollHint write FOnScrollHint;
    property OnCellLinkClick: TTyGridCellLinkEvent
      read FOnCellLinkClick write FOnCellLinkClick;
    property OnColumnCalc: TTyGridColumnCalcEvent
      read FOnColumnCalc write FOnColumnCalc;
    property OnGetFormat: TTyGridGetFormatEvent
      read FOnGetFormat write FOnGetFormat;
    property OnGetFilterValues: TTyGridGetFilterValuesEvent
      read FOnGetFilterValues write FOnGetFilterValues;
    { 勾选框单元格允许第三态(灰显)。关着时切换只在两态间走 ——
      灰显不能凭空冒出来。 }
    property AllowGrayed: Boolean read FAllowGrayed write FAllowGrayed default False;
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
    { 哪一列画成树:缩进 + 展开三角。-1 = 不画(默认)。
      层级与"有没有孩子"由 OnGetNodeLevel / OnGetHasChildren 回答 ——
      **控件不持有树**,所以百万行的树也不必先在控件里建起来。 }
    property TreeColumn: Integer read FTreeColumn write SetTreeColumn default -1;
    { 每一级缩进多少(逻辑像素)。三角画在它自己那一级的缩进槽里。 }
    property TreeIndent: Integer read FTreeIndent write SetTreeIndent default 16;
    property OnGetNodeLevel: TTyGridNodeLevelEvent
      read FOnGetNodeLevel write FOnGetNodeLevel;
    property OnGetHasChildren: TTyGridHasChildrenEvent
      read FOnGetHasChildren write FOnGetHasChildren;
    { 列头下面一条**内嵌筛选行**:每列一个输入位,打进去就按那一列筛。
      支持 `>100` `<=5` `<>x` `a..b`,`;` 分隔的多个条件之间是 OR。
      它是自己一条带,不是数据行 —— 行数、寻址、导出都不受影响。 }
    property ShowFilterRow: Boolean
      read FShowFilterRow write SetShowFilterRow default False;
    { 筛选行的高度(逻辑像素)。0 = 跟列头同高。 }
    property FilterRowHeight: Integer
      read FFilterRowHeight write SetFilterRowHeight default 0;
    { 分组行上按列显示小计。哪些列有小计,由 SetColumnAggregate 决定 ——
      与页脚汇总用的是同一份配置,不必再配一遍。 }
    property ShowGroupSubtotals: Boolean
      read FShowGroupSubtotals write SetShowGroupSubtotals default True;
    { 撤销栈最多留多少条;超出丢最老的。0 = 不记录(彻底关掉撤销)。 }
    property UndoLimit: Integer read FUndoLimit write SetUndoLimit default 100;
    { 排序是只换显示序,还是像 Excel 那样真的换数据。见 TTyGridSortMode。 }
    property SortMode: TTyGridSortMode read FSortMode write FSortMode
      default gsmDisplay;
    { 拖填充柄产生的一次填充;置 AHandled 可接管(自定义序列)。 }
    property OnFillCells: TTyGridFillEvent read FOnFillCells write FOnFillCells;
  end;

  { 一整列 / 一整行的 TStrings **活视图** —— 对标 LCL 的 TStringGridStrings
    (grids.pas:1724)。Cols[] / Rows[] 交出来的就是它。

    它自己**一个字符串都不存**:Get/Put 直接落到网格的格子上,GetObject/PutObject
    直接落到 Objects[]。所以它永远看得见网格此刻的样子,而不是取的那一刻。

    长度 = 网格在那条轴上的尺寸(列视图 = RowCount,行视图 = 列数),**不可改**:
    Insert / Delete 一律抛 EListError(LCL 同样,grids.pas:10902/10907)——
    视图的长度是网格的**结构**,不该被一次数据操作悄悄改掉。
    要加行加列请走 InsertRow / Header.Columns.Add。

    Add 是个例外,而且是必须的:CommaText / DelimitedText 的赋值走的是
    Clear + Add,所以 Add 必须"往下一个还没被 Add 写过的槽里写",写满了返回 -1
    而不抛异常(逐字照 LCL 的 FAddedCount,grids.pas:10791)。 }
  TTyGridStrings = class(TStrings)
  private
    FGrid:   TTyStringGrid;
    FIsCol:  Boolean;
    FIndex:  Integer;
    { Add 写到哪儿了。Clear 归零 —— 这就是 CommaText 赋值能从头填的原因。
      Put 不动它:直接按下标写与"顺序追加"是两回事。 }
    FAdded:  Integer;
    { 把视图下标翻成格坐标;越界返回 False(调用方各自决定是给空值还是抛)。 }
    function Locate(AIndex: Integer; out ACol, ARow: Integer): Boolean;
  protected
    function  Get(AIndex: Integer): string; override;
    function  GetCount: Integer; override;
    function  GetObject(AIndex: Integer): TObject; override;
    procedure Put(AIndex: Integer; const S: string); override;
    procedure PutObject(AIndex: Integer; AObject: TObject); override;
  public
    constructor Create(AGrid: TTyStringGrid; AIsCol: Boolean; AIndex: Integer);
    function  Add(const S: string): Integer; override;
    procedure Clear; override;
    procedure Delete(AIndex: Integer); override;
    procedure Insert(AIndex: Integer; const S: string); override;
    procedure Assign(ASource: TPersistent); override;
    { 这个视图看的是哪条轴的第几根。删列 / 移列之后它指的是那个**位置**,
      不是原来那一列 —— 与 LCL 一样按下标记账。 }
    property IsColumn: Boolean read FIsCol;
    property Index: Integer read FIndex;
  end;

const
  { TyGridCheckedWord 的出厂值:哨兵,含义是"跟随 resourcestring"(判定时**实时**读
    rsGridCheckedWord,随语言目录走)。控制字符不可能是用户的真值词 ——
    与下面 TyFilterOrSep 用 #1 是同一个论证。 }
  TyGridCheckedWordFollowRs = #1;

var
  { 勾选框额外认作"真"的**本地化**词(中文表里常见 '是')。

    这是一个 OVERRIDE 槽:出厂是上面的哨兵 = 判定时实时读 rsGridCheckedWord;
    宿主运行时赋任何别的值就改说宿主的话,**空串 = 明确禁用**本地化词
    (三态都有测试钉着)。通用真值 1/true/yes/y 永远认,不受它影响。
    运行时可改这一点与本库 TyFallbackFontName 同一惯例。

    它**不能**在 initialization 里 `:= rsGridCheckedWord` 播种(从前正是这么写的):
    语言目录装载在单元初始化**之后**(SetDefaultLang 跑在 .lpr 主体里),那份拷贝
    抓到的永远是未翻译的英文 'yes',zh_CN 目录里的 '是' 就此永远生效不了 ——
    "从 resourcestring 播种、可运行时改"的契约被初始化顺序整个废掉。钉住这条的
    守卫:test.grid.pas 的 TestCheckedWordFollowsACatalogueLoadedAfterUnitInit,
    它模拟"目录晚于单元初始化才装载"并要求判定仍然跟上。 }
  TyGridCheckedWord: string = TyGridCheckedWordFollowRs;

const
  { 同列多条件之间的分隔(编码里用,不是用户打的那个分号)。
    用控制字符是因为它不可能出现在用户输入的过滤文本里。 }
  TyFilterOrSep = #1;
  { gfoBetween 的两个边界之间的分隔。 }
  TyFilterRangeSep = #2;
  { 批注标记的边长(逻辑像素)。视觉尺寸本该走主题,但主题里没有
    "标记大小"这一层 token;这里退而求其次用一个具名常量,
    至少不是散落在绘制代码里的裸数字。颜色仍然走 token。 }
  TyGridCommentMarkSize = 7;

{ 把一条过滤表达式编码成过滤条件。语法刻意小,见 grid.md:
    >100  >=100  <5  <=5  <>x  =x   前缀比较
    a..b                            闭区间(两端都算)
    其余                            包含(默认,不区分大小写)
    ;                               同列多条件,之间是 **OR**
  只有运算符没有值(`>`、`..`、`10..`)一律当**不过滤** ——
  用户正打到一半时不该把整列筛没。 }
function TyGridParseFilterExpr(const AExpr: string): string;

{ 一个格值符不符合一条(可能含多个 OR 子条件的)过滤条件。 }
function TyGridFilterMatches(const ACellText, AEncoded: string): Boolean;

function TyGridEncodeFilter(AOp: TTyGridFilterOp; const AText: string): string;
procedure TyGridDecodeFilter(const AEncoded: string; out AOp: TTyGridFilterOp;
  out AText: string);

{ 把 AText 砍到在 ABmp 当前字体下画得进 AMaxWidthPx,砍过就在末尾补 '...';
  放得下就原样还回去。ABmp 必须已经配好目标字体(TyConfigureTextFont),
  否则量的不是要画的那支字。

  砍的单位是**字符**不是字节:一个汉字占三个字节,按字节砍必然留下半截 UTF-8
  序列,真机把它画成一个 '?'。列宽窄、中文格几乎必被截,所以这是网格上最常撞见的
  那个 '?'。

  独立成一个函数、放进 interface,是为了能直接断言**字符串**:headless 的 BGRA
  会把半截序列悄悄吞掉,像素比不出来。 }
function TyGridEllipsisFit(ABmp: TBGRABitmap; const AText: string;
  AMaxWidthPx: Integer): string;

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
{ 单条子条件的求值(不含 OR)。 }
function TyGridFilterMatchesOne(const ACellText, AEncoded: string): Boolean;
var
  op: TTyGridFilterOp;
  pat, a, b, lo, hi: string;
  va, vb, vlo, vhi: Double;
  sep: Integer;
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
    gfoBetween:
      begin
        sep := Pos(TyFilterRangeSep, pat);
        if sep <= 0 then Exit(True);          { 残缺区间 = 不过滤 }
        lo := Copy(pat, 1, sep - 1);
        hi := Copy(pat, sep + 1, MaxInt);
        vlo := StrToFloatDef(Trim(lo), NaN);
        vhi := StrToFloatDef(Trim(hi), NaN);
        if IsNan(vlo) or IsNan(vhi) then Exit(True);
        va := StrToFloatDef(Trim(ACellText), NaN);
        if IsNan(va) then Exit(False);        { 非数值格进不了数值区间 }
        { 边界写反了就当写对了 —— 用户打 "20..10" 的意思显然还是那一段。 }
        if vlo > vhi then
        begin
          vb := vlo; vlo := vhi; vhi := vb;
        end;
        Exit((va >= vlo) and (va <= vhi));    { 闭区间,两端都算 }
      end;
    gfoGreater, gfoGreaterEqual, gfoLess, gfoLessEqual:
      begin
        { 数值比较:格里不是数就一律不通过 —— 把 'abc' 算作 0 会让
          "筛 >-1"把整列文本都放进来,那不是用户要的。 }
        va := StrToFloatDef(Trim(ACellText), NaN);
        vb := StrToFloatDef(Trim(pat), NaN);
        if IsNan(vb) then Exit(True);         { 只有运算符没有值 = 不过滤 }
        if IsNan(va) then Exit(False);
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

function TyGridFilterMatches(const ACellText, AEncoded: string): Boolean;
var
  parts: TStringArray;
  i: Integer;
begin
  if AEncoded = '' then Exit(True);
  { 多个子条件之间是 **OR** —— 任意一条成立就放行。
    (列与列之间仍是 AND,那在 RowPassesFilter 里。) }
  if Pos(TyFilterOrSep, AEncoded) <= 0 then
    Exit(TyGridFilterMatchesOne(ACellText, AEncoded));
  parts := AEncoded.Split(TyFilterOrSep);
  Result := False;
  for i := 0 to High(parts) do
    if TyGridFilterMatchesOne(ACellText, parts[i]) then Exit(True);
end;

function TyGridParseFilterExpr(const AExpr: string): string;

  { 一个子条件(不含分号)。 }
  function One(const ASrc: string): string;
  var
    s, lo, hi: string;
    dots: Integer;
  begin
    s := Trim(ASrc);
    if s = '' then Exit('');

    { 区间要先认 —— 否则 "10..20" 会被当成包含 "10..20" 的文本。 }
    dots := Pos('..', s);
    if dots > 0 then
    begin
      lo := Trim(Copy(s, 1, dots - 1));
      hi := Trim(Copy(s, dots + 2, MaxInt));
      { 半个区间(缺一端)当不过滤 —— 用户正打到一半。 }
      if (lo = '') or (hi = '') then Exit('');
      Exit(TyGridEncodeFilter(gfoBetween, lo + TyFilterRangeSep + hi));
    end;

    { 前缀比较。两字符的要先判,否则 ">=" 会被 ">" 抢走。 }
    if Copy(s, 1, 2) = '>=' then Exit(TyGridEncodeFilter(gfoGreaterEqual, Trim(Copy(s, 3, MaxInt))));
    if Copy(s, 1, 2) = '<=' then Exit(TyGridEncodeFilter(gfoLessEqual, Trim(Copy(s, 3, MaxInt))));
    if Copy(s, 1, 2) = '<>' then Exit(TyGridEncodeFilter(gfoNotEquals, Trim(Copy(s, 3, MaxInt))));
    if Copy(s, 1, 1) = '>'  then Exit(TyGridEncodeFilter(gfoGreater, Trim(Copy(s, 2, MaxInt))));
    if Copy(s, 1, 1) = '<'  then Exit(TyGridEncodeFilter(gfoLess, Trim(Copy(s, 2, MaxInt))));
    if Copy(s, 1, 1) = '='  then Exit(TyGridEncodeFilter(gfoEquals, Trim(Copy(s, 2, MaxInt))));

    Result := TyGridEncodeFilter(gfoContains, s);
  end;

var
  parts: TStringArray;
  i: Integer;
  one1: string;
begin
  Result := '';
  if Trim(AExpr) = '' then Exit;
  parts := AExpr.Split(';');
  for i := 0 to High(parts) do
  begin
    one1 := One(parts[i]);
    { 空子条件(比如 "华东;")直接丢掉,别让它变成一条"匹配一切"的 OR 分支
      —— 那会让整个表达式失效。 }
    if one1 = '' then Continue;
    if Result <> '' then Result := Result + TyFilterOrSep;
    Result := Result + one1;
  end;
end;

function TyGridEllipsisFit(ABmp: TBGRABitmap; const AText: string;
  AMaxWidthPx: Integer): string;
{ 与 TTyPainter.DrawText 用同一套规则 —— 连"砍到几个字"这一步都调它那支
  TyEllipsisPrefix,免得两条路径排出来的字不一样。
  从前这里是 Delete(txt, Length(txt), 1):砍掉的是一个**字节**。 }
var
  cpN: Integer;
  tsz: TSize;
begin
  Result := AText;
  if (ABmp = nil) or (AText = '') then Exit;
  cpN := UTF8Length(Result);
  tsz := ABmp.TextSize(Result);
  while (cpN > 1) and (tsz.cx > AMaxWidthPx) do
  begin
    Dec(cpN);
    Result := TyEllipsisPrefix(AText, cpN);
    tsz := ABmp.TextSize(Result + '...');
  end;
  if Result <> AText then Result := Result + '...';
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

procedure TTyGridHeaderGroup.SetText(const AValue: TCaption);
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
  FLayout := tlCenter;      { 与从前写死在 CellAppearance 里的那个值一致 }
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

procedure TTyGridColumn.SetCellDisplay(AValue: TTyGridCellDisplay);
begin
  FCellDisplay := AValue;
  FUseCellDisplay := True;    { 见 SetEditorKind:写过就算设过 }
end;

procedure TTyGridColumn.SetColor(AValue: TTyColor);
begin
  if FColor = AValue then Exit;
  FColor := AValue;
  { 列色改了整列都要重画。TTyColumn 的 NotifyOwner 是 private,走 Changed(False)
    —— TCollectionItem 的标准通知,最终落到 TTyColumns.Notify 再到 header 的
    OnChange,与改列宽走的是同一条链。 }
  Changed(False);
end;

procedure TTyGridColumn.SetLayout(AValue: TTextLayout);
begin
  if FLayout = AValue then Exit;
  FLayout := AValue;
  Changed(False);
end;

procedure TTyGridColumn.Assign(ASource: TPersistent);
begin
  inherited Assign(ASource);
  if ASource is TTyGridColumn then
  begin
    FColor := TTyGridColumn(ASource).Color;
    FLayout := TTyGridColumn(ASource).Layout;
    FValueChecked := TTyGridColumn(ASource).ValueChecked;
    FValueUnchecked := TTyGridColumn(ASource).ValueUnchecked;
    FEditorKind := TTyGridColumn(ASource).EditorKind;
    FUseEditorKind := TTyGridColumn(ASource).UseEditorKind;
    FReadOnly := TTyGridColumn(ASource).ReadOnly;
    FPickList.Assign(TTyGridColumn(ASource).PickList);
    FAggregate := TTyGridColumn(ASource).Aggregate;
    FValidChars := TTyGridColumn(ASource).ValidChars;
    FMaxEditLength := TTyGridColumn(ASource).MaxEditLength;
    FSortKind := TTyGridColumn(ASource).SortKind;
    FMinValue := TTyGridColumn(ASource).MinValue;
    FMaxValue := TTyGridColumn(ASource).MaxValue;
    FEditMask := TTyGridColumn(ASource).EditMask;
    FCharCase := TTyGridColumn(ASource).CharCase;
    FDropDownWidth := TTyGridColumn(ASource).DropDownWidth;
    FCellDisplay := TTyGridColumn(ASource).CellDisplay;
    FUseCellDisplay := TTyGridColumn(ASource).UseCellDisplay;
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
    and not ReadOnly
    and not HasCellDisplay and (Comment = '')
    { 挂着对象的条目**不是**可回收的默认条目 —— 漏了这一条,
      "涂个底色再清掉"就会连宿主的指针一起被 DropIfDefault 抹了。 }
    and (Obj = nil);
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
  HasCellDisplay := ASrc.HasCellDisplay; CellDisplay := ASrc.CellDisplay;
  Comment := ASrc.Comment;
  { 搬家走的就是这一句(MoveEntry / 物理排序 / SwapRows 都调它)——
    漏抄 Obj 的症状是排完序文字换了位置、对象留在原地。 }
  Obj := ASrc.Obj;
end;

procedure TTyGridCellAttr.ResetKeepingObject;
var
  keep: TObject;
begin
  keep := Obj;
  ColSpan := 1;               RowSpan := 1;
  HasBackground := False;     Background := 0;
  HasTextColor := False;      TextColor := 0;
  HasAlignment := False;      Alignment := taLeftJustify;
  HasFontStyle := False;      FontStyle := [];
  ReadOnly := False;
  HasCellDisplay := False;    CellDisplay := gcdText;
  Comment := '';
  Obj := keep;
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

procedure TTyGridCellAttrStore.Changing(const AKey: string);
begin
  if Assigned(FOnChanging) then FOnChanging(AKey);
end;

function TTyGridCellAttrStore.Mutate(const AKey: string): TTyGridCellAttr;
begin
  Result := Find(AKey);
  if Result <> nil then Changing(AKey);
end;

function TTyGridCellAttrStore.Ensure(const AKey: string): TTyGridCellAttr;
begin
  { 已存在也要通知 —— 调用方接着就要改它的字段。
    不存在时同样通知:"原本没有这一条"本身就是要恢复的状态。 }
  Changing(AKey);
  Result := EnsureQuiet(AKey);
end;

function TTyGridCellAttrStore.EnsureQuiet(const AKey: string): TTyGridCellAttr;
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
  if i < 0 then Exit;                  { 没这一条 —— 没有状态变化,别记 }
  Changing(AKey);
  i := FItems.IndexOf(AKey);           { 通知之后重新定位,别拿着可能过期的下标删 }
  if i >= 0 then FItems.Delete(i);     { OwnsObjects → 顺带释放 }
end;

procedure TTyGridCellAttrStore.DropIfDefault(const AKey: string);
var
  a: TTyGridCellAttr;
  i: Integer;
begin
  a := Find(AKey);
  if (a = nil) or (not a.IsDefault) then Exit;
  { 只是把退化成全默认值的条目回收掉 —— 语义上"全默认值"和"没有这一条"
    是同一个状态,所以**不**发 Changing:调用方在动字段之前已经发过一次了。
    再发一次会把一次操作拆成两条撤销记录,用户按一次 Ctrl+Z 只退回一半。 }
  i := FItems.IndexOf(AKey);
  if i >= 0 then FItems.Delete(i);
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
  { 网格要接键盘。这行以前只在 TTyStringGrid 里写,于是 TTyDrawGrid 明明 published 了
    `TabStop default True`,构造出来却是 False —— 声明的默认值和实际值对不上,设计器
    还会把 TabStop=False 写进每个 .lfm。焦点也一样收不到:TTyCustomControl.MouseDown
    的点击取焦点是拿 TabStop 当闸门的。放到基类,两个派生网格一起对。 }
  TabStop := True;
  { 让表头造网格自己的列类。 }
  FHeader := TTyHeader.Create(TTyGridColumn);
  FHeader.OnChange := @HeaderChanged;
  FRowCount := 0;
  FDefaultRowHeight := 22;              { fallback; unused while FDefaultRowHeightExplicit=False }
  FDefaultRowHeightExplicit := False;   { follow --row-height (density-aware) until set }
  FDefaultColWidth := 100;              { same shape on the column axis; see GetDefaultColWidth }
  FDefaultColWidthExplicit := False;
  FLastLeftCol := -1;                   { -1 = 还没通知过任何位置 }
  FLastTopRow := -1;
  FFixedCols := 0;
  FFixedRows := 0;
  FFixedRowsBottom := 0;
  FUndoLimit := 100;
  FFixedColsRight := 0;
  FIndicatorWidth := 30;
  FShowIndicator := False;
  FGridLineStyle := glsBoth;
  { **构造函数从来没设过它**,而 ShowFocusCell 与它的 LCL 别名 FocusRectVisible
    都写着 `default True`。于是出厂的网格里焦点格底色是熄的 —— 属性文档说
    "默认开着"、LCL 的 FocusRectVisible 也确实默认 true,只有代码不是。

    两个后果:一是 gsmRow 下看不出光标停在哪一格(那正是这块底色存在的理由);
    二是每一张窗体都会被 TWriter 多写一行 `ShowFocusCell = False` ——
    实际值与 default 子句不符时它必写。
    是 Options 那条 default 断言把它照出来的:goDrawFocusSelected 是它的视图。 }
  FShowFocusCell := True;
  { 只留自己那一半 —— 派生位由 GridLineStyle / Header.Options / ReadOnly /
    SelectionMode / ShowRowNumbers 各自的出厂值现算出来。
    这里若把整个 TyDefaultGridOptions 存进去,FOptions 就多了一份会发霉的副本。 }
  FOptions := TyDefaultGridOptions - TyGridDerivedOptions;
  FHeaderGroups := TTyGridHeaderGroups.Create;
  FHeaderGroups.OnChange := @HeaderGroupsChanged;
  FGroupHeaderHeight := 22;
  FGridLineWidth := 1;
  FHoverCol := -1;
  FHoverRow := -1;
  FHoverHeaderCol := -1;
  FPressedHeaderCol := -1;
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
  FDragRow := -1;
  FResizeCol := -1;

  { 两条内嵌滚动条。csNoDesignVisible:内部子控件不该出现在设计器的对象树里。
    TabStop:=False:独立摆放的 TTyScrollBar 是可聚焦的(它自己有方向键/翻页键),但
    嵌在网格里的这两条不能是 —— 否则拖滚动条会把焦点从网格身上抢走,网格随即失去
    焦点环和方向键导航,Tab 也会在一个网格里停三次。 }
  FVScroll := TTyScrollBar.Create(Self);
  FVScroll.Parent := Self;
  FVScroll.Kind := sbVertical;
  FVScroll.TabStop := False;
  FVScroll.AnimationsEnabled := False;
  FVScroll.OnChange := @VScrollChange;
  FVScroll.ControlStyle := FVScroll.ControlStyle + [csNoDesignVisible];
  FVScroll.Visible := False;

  FHScroll := TTyScrollBar.Create(Self);
  FHScroll.Parent := Self;
  FHScroll.Kind := sbHorizontal;
  FHScroll.TabStop := False;
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
  { 行数变化也是可撤销的一步 —— 删行时单元格的搬移会自己被记下来(它们走 Cells[]),
    但行数不走那条路,得单独记一笔,否则撤销完剩一张缺了一行的表。 }
  BeginUpdate;      { 行数 + 越界状态的清理算**一条** }
  try
    RecordRowCountUndo(FRowCount);
    { 缩小时先把越界的按行状态清掉(在 FRowCount 变小**之前**,那时它们还在范围内)。 }
    if AValue < FRowCount then TrimRowStateTo(AValue);
    FRowCount := AValue;
  finally
    EndUpdate;
  end;
  InvalidateGridOrder;
  UpdateScrollBars;
  Invalidate;
end;

{ Effective default row height: an explicit set wins; otherwise follow the theme's
  --row-height token (density pack raises it for modern). Resolved live so toggling
  Controller.Density re-heights every row on the next layout. }
function TTyCustomGrid.GetDefaultRowHeight: Integer;
begin
  if FDefaultRowHeightExplicit then
    Result := FDefaultRowHeight
  else
    Result := ActiveController.Metric('--row-height', 22);
end;

procedure TTyCustomGrid.SetDefaultRowHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  FDefaultRowHeightExplicit := True;   { the host meant to pin it, even at the fallback value }
  if FDefaultRowHeight = AValue then Exit;
  FDefaultRowHeight := AValue;
  UpdateScrollBars;
  Invalidate;
end;

function TTyCustomGrid.GetGridWidth: Integer;
begin
  Result := ContentWidthPx;
end;

function TTyCustomGrid.GetGridHeight: Integer;
begin
  Result := ContentHeightPx;
end;

procedure TTyCustomGrid.SetAutoFillColumns(AValue: Boolean);
begin
  if FAutoFillColumns = AValue then Exit;
  FAutoFillColumns := AValue;
  { 立刻铺一次 —— 不然打开这个开关之后要等到下一次 Resize 才看得出效果,
    在设计器里就表现为"勾了没反应"。 }
  UpdateScrollBars;
  Invalidate;
end;

function TTyCustomGrid.GetDefaultColWidth: Integer;
begin
  { 与 GetDefaultRowHeight 一模一样的形状:没被钉住就跟着主题走。
    主题里没有 --column-width 时答 100 —— 正是 TTyColumn.Width 的 default。 }
  if FDefaultColWidthExplicit then
    Result := FDefaultColWidth
  else
    Result := ActiveController.Metric('--column-width', 100);
end;

procedure TTyCustomGrid.SetDefaultColWidth(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  FDefaultColWidthExplicit := True;   { 写过就算钉住,哪怕写的正好是回落值 }
  if FDefaultColWidth = AValue then Exit;
  FDefaultColWidth := AValue;
end;

function TTyCustomGrid.GetColWidths(ACol: Integer): Integer;
begin
  if (ACol < 0) or (ACol >= FHeader.Columns.Count) then Exit(0);
  Result := FHeader.Columns.Items[ACol].Width;
end;

procedure TTyCustomGrid.SetColWidths(ACol, AValue: Integer);
begin
  if (ACol < 0) or (ACol >= FHeader.Columns.Count) then Exit;
  { 网格级的上下限先钳 —— 与拖动改宽那条路(MouseMove 的 FResizeCol 分支)用的是
    同两行,列自己的 MinWidth/MaxWidth 随后在 TTyColumn.SetWidth 里再钳一次。
    两条路必须同规则,否则"手拖到 60 是下限、代码写 10 却进去了"。 }
  if (FMinColWidth > 0) and (AValue < FMinColWidth) then AValue := FMinColWidth;
  if (FMaxColWidth > 0) and (AValue > FMaxColWidth) then AValue := FMaxColWidth;
  if FHeader.Columns.Items[ACol].Width = AValue then Exit;
  FHeader.Columns.Items[ACol].Width := AValue;
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

function TTyCustomGrid.FrozenBottomPx: Integer;
var
  i, n: Integer;
begin
  Result := 0;
  n := FFixedRowsBottom;
  if n <= 0 then Exit;
  if n > DisplayRowCount - FFixedRows then n := DisplayRowCount - FFixedRows;
  if n <= 0 then Exit;
  { i 是**显示位置** —— 带子里装的是哪几行数据由显示序说了算。 }
  for i := DisplayRowCount - n to DisplayRowCount - 1 do
    Inc(Result, ScaleI(RowHeightOfDisplay(i)));
end;

function TTyCustomGrid.EffectiveFixedColsRight: Integer;
begin
  Result := FFixedColsRight;
  if Result < 0 then Result := 0;
  { 左固定列优先 —— 同一列不能既钉左又钉右。 }
  if Result > FHeader.Columns.Count - FFixedCols then
    Result := FHeader.Columns.Count - FFixedCols;
  if Result < 0 then Result := 0;
end;

function TTyCustomGrid.FrozenRightPx: Integer;
var
  i, n: Integer;
begin
  Result := 0;
  n := EffectiveFixedColsRight;
  if n <= 0 then Exit;
  if not FColCacheValid then BuildColumnCache;
  for i := FHeader.Columns.Count - n to FHeader.Columns.Count - 1 do
    if i < Length(FColWidthPx) then Inc(Result, FColWidthPx[i]);
end;

procedure TTyCustomGrid.SetFixedColsRight(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FFixedColsRight = AValue then Exit;
  FFixedColsRight := AValue;
  InvalidateColumnCache;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyCustomGrid.SetFixedRowsBottom(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FFixedRowsBottom = AValue then Exit;
  FFixedRowsBottom := AValue;
  UpdateScrollBars;
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
  if hoVisible in FHeader.Options then Inc(px, HeaderHeightPx);
  { 分组带也在上冻结带里 —— 漏了它固定行和正文都会往上顶,压住分组标题。 }
  Inc(px, GroupBandHeightPx);
  { 内嵌筛选行同理:它钉在列头之下、不随滚动。 }
  Inc(px, FilterRowHeightPx);
  { 逐行累加真实高度(而非 行数×默认行高)—— 可变行高时固定行也可能各不相同。
    i 是**显示位置**:冻结带里钉的是显示序最前的那几行,不是数据行 0..n。 }
  for i := 0 to FFixedRows - 1 do
    Inc(px, ScaleI(RowHeightOfDisplay(i)));
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
  { 走收口点 SetScrollX,不再直接写 FScrollX —— 直接写会绕过钳制,也绕过
    OnTopLeftChanged,于是"用滚轮滚会发事件、拖横向滑块不发"。纵向那一侧的
    同一个 bug 在 SetScrollY 的注释里记着。
    回弹不用担心:SetScrollX -> SyncScrollBars 期间 FSyncingScroll 为真,
    再进到这里第一行就退出去了。 }
  ScrollX := FHScroll.Position;
end;

procedure TTyCustomGrid.Resize;
begin
  inherited Resize;
  UpdateScrollBars;
end;

procedure TTyCustomGrid.SyncScrollBars;
begin
  { **这里原来有一句 `if (FVScroll = nil) or (FHScroll = nil) then Exit`,量过之后删的。**

    两个字段能是 nil 的窗口只有一个:构造函数里,两条条是**最末尾**才建的,而在它们
    之前构造函数已经跑了一大段(FHeader.OnChange、FRowCount、各种默认值)。除此之外
    再无窗口 —— 网格没有为这两条写 Notification,析构里也不置 nil。所以析构之后它们是
    **野指针而不是 nil**,判空在那边一点忙都帮不上;那一侧真正的护栏是
    UpdateScrollBars 头上的 csDestroying(而 SyncScrollBars 够不着析构:它只有
    SetScrollX / SetScrollY 两个调用者,TTyScrollBar 的析构不发 OnChange)。

    实测(tests/test.grid.pas 的 TTyGridScrollBarNilWindowTest):拿一个把两个方法都
    覆写掉的探针网格去数,**整个构造过程中这两个方法各进了 0 次** —— 挂 Parent 那一下
    LCL 因为网格自己还没有 Parent 和句柄而把对齐整个推迟了(AutoSizeDelayed)。同一个
    探针在随后的完整生命周期里数到 UpdateScrollBars 27 次、SyncScrollBars 3 次,
    带 nil 的 0 次。留着就是一条永远走不到、也没法让它变红的分支。

    真要有人在 `FHeader.OnChange := @HeaderChanged` 与
    `FVScroll := TTyScrollBar.Create(Self)` 之间插一句会碰表头/行数的代码
    (HeaderChanged / SetRowCount 都通向 UpdateScrollBars),窗口就活了 —— 那时探针
    那条测试先红,而修法是把两条滚动条挪到构造函数**前面**去,不是在这里补 nil。
    同一段推理见 GetOptions 里 goThumbTracking 那一行(30da2e0)。 }
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

{ 选区"活跃"= 控件有焦点。抽成一个可覆写的方法而不是直接读 Focused:
  无头测试里控件永远拿不到真焦点,不留这个座就没法测。 }
function TTyCustomGrid.SelectionIsActive: Boolean;
begin
  Result := Focused;
end;

procedure TTyCustomGrid.SetHeaderWordWrap(AValue: Boolean);
begin
  if FHeaderWordWrap = AValue then Exit;
  FHeaderWordWrap := AValue;
  InvalidateSurface;
  Realign;
  Invalidate;
end;

procedure TTyCustomGrid.SetHeaderAutoHeight(AValue: Boolean);
begin
  if FHeaderAutoHeight = AValue then Exit;
  FHeaderAutoHeight := AValue;
  InvalidateSurface;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyCustomGrid.SetShowFocusCell(AValue: Boolean);
begin
  if FShowFocusCell = AValue then Exit;
  FShowFocusCell := AValue;
  ResetCellStyleCache;      { 外观缓存里有焦点格那一格 }
  InvalidateSurface;
  Invalidate;
end;

{ ---- Options:一半是存储,一半是别处状态的视图 ---- }

{ 派生位现读现算,**永远不从 FOptions 取** —— 那是这个属性不会说谎的全部原因。 }
function TTyCustomGrid.GetOptions: TTyGridOptions;
begin
  Result := FOptions - TyGridDerivedOptions;   { 防御:存储侧不该沾派生位 }
  if FGridLineStyle in [glsVertical, glsBoth]   then Include(Result, goVertLine);
  if FGridLineStyle in [glsHorizontal, glsBoth] then Include(Result, goHorzLine);
  if FShowFocusCell                             then Include(Result, goDrawFocusSelected);
  if FShowRowNumbers                            then Include(Result, goFixedRowNumbering);
  if hoColumnResize in FHeader.Options          then Include(Result, goColSizing);
  if hoDrag         in FHeader.Options          then Include(Result, goColMoving);
  if hoHotTrack     in FHeader.Options          then Include(Result, goHeaderHotTracking);
  if GetOptEditing                              then Include(Result, goEditing);
  if GetOptRowSelect                            then Include(Result, goRowSelect);
  { **这里不加 nil 判断,是量过的,不是忘了。** 两条滚动条确实是构造函数
    **最末尾**才建的(其余派生位读的 FHeader/FGridLineStyle/FShowFocusCell 都在
    开头),所以"构造到一半有人读 Options"这个窗口理论上存在;而 SyncScrollBars
    与 UpdateScrollBars 里那两句 `if (FVScroll = nil) ... then Exit` 看着像证据。
    实测**不成立**:拿一个覆写 UpdateScrollBars 的探针网格去数,构造全程一次
    都没有在 nil 状态下进去过 —— 挂 Parent 那一下 LCL 因为网格自己还没有 Parent
    和句柄而把对齐整个推迟了(AutoSizeDelayed)。加了判断就是一条永远走不到、
    也没法让它变红的分支。
    后话:那两句"看着像证据"的判空后来也各自量过,同样进不去,已经删掉 ——
    完整测量记在 SyncScrollBars 的实现处。所以现在这三处是一条推理,不是三条。
    真要有人在构造函数里 `FHeader.OnChange := @HeaderChanged` 与
    `FVScroll := TTyScrollBar.Create(Self)` 之间插一句会碰表头/行数的代码
    (HeaderChanged / SetRowCount 都通向 UpdateScrollBars),这个窗口才会活过来
    —— 那时这一行会 AV,而修法是把两条滚动条挪到构造函数前面去,不是在这里补 nil。 }
  if FVScroll.LiveTracking                      then Include(Result, goThumbTracking);
end;

procedure TTyCustomGrid.SetOptions(AValue: TTyGridOptions);
var
  cur: TTyGridOptions;
  ls: TTyGridLineStyle;
  ho: TTyHeaderOptions;
begin
  cur := GetOptions;
  if cur = AValue then Exit;

  { 自己那一半直接换。 }
  FOptions := AValue - TyGridDerivedOptions;

  { 派生那一半:**只在这一位真的翻了的时候才写回去**。

    这个 `if` 不是省一次赋值那么简单,它是三态属性的救命绳:
    SelectionMode 有 gsmCell/gsmRow/gsmColumn 三态,而 goRowSelect 只有两态。
    无条件写回的话,一次 `Options := Options`(设计器每次流式化都会做的事)
    就会把 gsmColumn 压成 gsmCell —— 用户设的"按列选"莫名其妙变回按格选。
    改成"翻位才写"之后,goRowSelect 那一位在 gsmColumn 下读出来是 False、
    写进去也是 False,没翻,于是 gsmColumn 原封不动。 }
  if ((goVertLine in cur) <> (goVertLine in AValue))
     or ((goHorzLine in cur) <> (goHorzLine in AValue)) then
  begin
    { 两位 → 四态,双射,不丢信息。 }
    if (goVertLine in AValue) and (goHorzLine in AValue) then ls := glsBoth
    else if goVertLine in AValue then ls := glsVertical
    else if goHorzLine in AValue then ls := glsHorizontal
    else ls := glsNone;
    SetGridLineStyle(ls);
  end;

  if (goDrawFocusSelected in cur) <> (goDrawFocusSelected in AValue) then
    SetShowFocusCell(goDrawFocusSelected in AValue);

  if (goFixedRowNumbering in cur) <> (goFixedRowNumbering in AValue) then
    SetShowRowNumbers(goFixedRowNumbering in AValue);

  ho := FHeader.Options;
  if (goColSizing in cur) <> (goColSizing in AValue) then
    if goColSizing in AValue then Include(ho, hoColumnResize)
    else Exclude(ho, hoColumnResize);
  if (goColMoving in cur) <> (goColMoving in AValue) then
    if goColMoving in AValue then Include(ho, hoDrag) else Exclude(ho, hoDrag);
  if (goHeaderHotTracking in cur) <> (goHeaderHotTracking in AValue) then
    if goHeaderHotTracking in AValue then Include(ho, hoHotTrack)
    else Exclude(ho, hoHotTrack);
  { 一次写回去,不是三次 —— TTyHeader.SetOptions 每次都会重排/重画。 }
  if ho <> FHeader.Options then FHeader.Options := ho;

  if (goEditing in cur) <> (goEditing in AValue) then
    SetOptEditing(goEditing in AValue);
  if (goRowSelect in cur) <> (goRowSelect in AValue) then
    SetOptRowSelect(goRowSelect in AValue);

  { **两条都要写。** 只写纵向的那条,横向拖动照样实时提交 —— 一个属性只生效
    一半,比根本没有它更坏,因为用户会以为自己已经关掉了。
    这一位同样只在**真的翻了**的时候才写(与上面那些派生位同一条规矩):
    无条件写回会让每一次流式化的 `Options := Options` 都去碰两条滚动条,
    而宿主完全可以绕过 Options 直接设 `VScrollBar.LiveTracking` —— 那份设置
    会被下一次空写抹掉。 }
  if (goThumbTracking in cur) <> (goThumbTracking in AValue) then
  begin
    FVScroll.LiveTracking := goThumbTracking in AValue;
    FHScroll.LiveTracking := goThumbTracking in AValue;
  end;

  { 自己存的那一半里有影响外观的(goCellEllipsis / goRowHighlight),
    而上面那些具名 setter 只在自己翻位时才重画 —— 所以这里补一次。

    **两级缓存都要掀,少掀一级就是一个只在换肤时才现形的 bug**:
    整行高亮进的是外观缓存(ResetCellStyleCache),而省略号进的是**文字位图**
    缓存 —— 那个缓存的键里只有文字、宽高、颜色,没有"当时截没截断"。
    只掀外观缓存的话,关掉 goCellEllipsis 之后每一格还是从缓存里取出那张
    带"…"的旧位图,属性看着生效了、屏幕上一个字没变。 }
  ResetCellStyleCache;
  ClearTextCache;
  InvalidateSurface;
  Invalidate;
end;

{ 基类没有 ReadOnly / SelectionMode 这两个概念,答的是**基类的事实**:
  永远可编辑、永远按格选。写进去是空操作 —— 假装存下来才是说谎。 }
function TTyCustomGrid.GetOptEditing: Boolean;
begin
  Result := True;
end;

procedure TTyCustomGrid.SetOptEditing(AValue: Boolean);
begin
  { 基类无处安放。 }
end;

function TTyCustomGrid.GetOptRowSelect: Boolean;
begin
  Result := False;
end;

procedure TTyCustomGrid.SetOptRowSelect(AValue: Boolean);
begin
  { 基类无处安放。 }
end;

procedure TTyCustomGrid.KeepCursorVisible;
begin
  { 基类没有光标。 }
end;

procedure TTyCustomGrid.SetHideSelectionWhenInactive(AValue: Boolean);
begin
  if FHideSelectionWhenInactive = AValue then Exit;
  FHideSelectionWhenInactive := AValue;
  ResetCellStyleCache;
  InvalidateSurface;
  Invalidate;
end;

procedure TTyCustomGrid.SetVertScrollBarMode(AValue: TTyGridScrollBarMode);
begin
  if FVertScrollBarMode = AValue then Exit;
  FVertScrollBarMode := AValue;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyCustomGrid.SetHorzScrollBarMode(AValue: TTyGridScrollBarMode);
begin
  if FHorzScrollBarMode = AValue then Exit;
  FHorzScrollBarMode := AValue;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyCustomGrid.SetBackgroundBitmap(AValue: TBGRABitmap);
begin
  if FBackgroundBitmap = AValue then Exit;
  FBackgroundBitmap := AValue;
  InvalidateSurface;      { 背景变了,持久表面上那一帧作废 }
  Invalidate;
end;

procedure TTyCustomGrid.SetBackgroundMode(AValue: TTyGridBackgroundMode);
begin
  if FBackgroundMode = AValue then Exit;
  FBackgroundMode := AValue;
  InvalidateSurface;
  Invalidate;
end;

procedure TTyCustomGrid.SetBackgroundScope(AValue: TTyGridBackgroundScope);
begin
  if FBackgroundScope = AValue then Exit;
  FBackgroundScope := AValue;
  InvalidateSurface;
  Invalidate;
end;

procedure TTyCustomGrid.UpdateScrollBars;
var
  sb, vw, vh, pass, bodyH, bodyW, maxV, maxH: Integer;
  needV, needH: Boolean;
begin
  { csDestroying 留着,判空删了 —— 两句看着像一对,实际管的是**两件事**。
    析构那一侧:两个字段那时是野指针而不是 nil,判空救不了,csDestroying 才是护栏。
    构造那一侧:那扇窗量过,一次都没开过 —— 完整的测量与"窗口真活了要怎么修"
    记在 SyncScrollBars 的实现处,一处,别再抄一份。 }
  if csDestroying in ComponentState then Exit;

  sb := ScaleI(ActiveController.Metric('--scrollbar-size', TyScrollbarSize));
  needV := False;
  needH := False;

  { 自动列宽。两条都放在两趟收敛**之前**:列宽变了会影响横向内容量,
    进而影响横条是否出现。

    先整体铺满(AutoFillColumns),再让 AutoSizeIndex 那一列吃掉零头 ——
    见 AutoFillColumns 的声明处。ApplyAutoSize 此前是**零调用**,
    DistributeFill 那条更是连入口都没有。

    喂给 DistributeFill 的是**列可用的**宽度,即视口宽减去行头槽 ——
    ContentWidthPx 正是 `行头槽 + 各可见列宽之和`,两边必须按同一个式子算,
    否则铺完仍差一条槽那么宽。冻结列也是列,一起参与。
    用 ViewportW 而不是 ClientWidth:纵向滚动条占掉的那一条不能算进去,
    否则最后一列会钻到它底下。不会来回震荡 —— 纵条出不出现取决于内容
    **高度**,与列宽无关。 }
  if FAutoFillColumns and not FSyncingScroll then
    FHeader.Columns.DistributeFill(UnscaleI(ViewportW)
      - IfThen(FShowIndicator, FIndicatorWidth, 0));
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
    { 三态在**最后**落到 Visible 上 —— 上面那两趟"互夺"收敛仍按真实需要算,
      否则常显模式下的空间预留会算错。 }
    case FVertScrollBarMode of
      gsbAlways: FVScroll.Visible := True;
      gsbNever:  FVScroll.Visible := False;
      else       FVScroll.Visible := needV;
    end;
    { 常显时即便内容装得下也要摆好位置,否则它出现在 (0,0) 上。 }
    if FVScroll.Visible and (not needV) and (not FVScroll.Dragging) then
    begin
      FVScroll.Controller := Self.Controller;
      FVScroll.Width := sb;
      FVScroll.SetBounds(ClientWidth - sb, 0, sb, vh);
      FVScroll.Min := 0;
      FVScroll.Max := maxV;
      FVScroll.PageSize := bodyH;
    end;

    { **横向条的原点跟着阅读方向走。** FScrollX 的语义一个字没变 ——
      它恒是"正文列离开阅读起点多远",FScrollX = 0 就是"第 0 列贴着冻结带"。
      变的只是这个位置画在条的哪一头:Position = Min 必须落在阅读起点,
      RTL 下那是条的右端。TTyScrollBar 刻意**不读** BiDiMode(见 5c2ceca),
      正是把这个判断留给宿主 —— 网格在这里替它做,一处。
      每次装配都设,不是只在创建时设:BiDiMode 运行时可写,
      CMBiDiModeChanged 直接回到这里。 }
    FHScroll.MirrorHorizontal := RtlLayout;

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
    case FHorzScrollBarMode of
      gsbAlways: FHScroll.Visible := True;
      gsbNever:  FHScroll.Visible := False;
      else       FHScroll.Visible := needH;
    end;
    if FHScroll.Visible and (not needH) and (not FHScroll.Dragging) then
    begin
      FHScroll.Controller := Self.Controller;
      FHScroll.Height := sb;
      FHScroll.SetBounds(0, ClientHeight - sb, vw, sb);
      FHScroll.Min := 0;
      FHScroll.Max := maxH;
      FHScroll.PageSize := bodyW;
    end;
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
  pos: Integer;
begin
  { 被筛掉/藏起来的行**没有可滚到的位置**。不挡的话 -1 会被几何层钳到内容顶端,
    于是视口"跳回表格最上面",而用户根本没要求滚动。 }
  pos := DataToDisplay(ARow);
  if pos < 0 then Exit;

  M := GridMetrics;
  body := TyGridPaneRect(M, gpBody);

  { 纵向:用行矩形判断,最小移动量把它拉进正文区。 }
  r := TyGridRowRect(pos, M);
  if r.Top < body.Top then
    SetScrollY(FScrollY - (body.Top - r.Top))
  else if r.Bottom > body.Bottom then
    SetScrollY(FScrollY + (r.Bottom - body.Bottom));

  { 横向:固定列本来就在冻结带里,不需要也不能滚。
    两个矩形一起反射回阅读空间再比 —— 判据与滚动量的符号一个字没改,
    LTR 逐字节等价;RTL 下"探出去的是哪一头"自动跟着换,
    不必写第二组 `if rtl then` 分支(那正是滚动原点最常漏的地方)。 }
  if ACol >= FFixedCols then
  begin
    cell := ToReadingRect(CellRect(ACol, ARow));
    body := ToReadingRect(body);
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
  step := 3 * ScaleI(GetDefaultRowHeight);
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

{ 基类不知道显示类型;TTyStringGrid 改写去问 CellDisplayFor。 }
function TTyCustomGrid.HoverIsHyperlink(X, Y: Integer): Boolean;
begin
  Result := False;
end;

procedure TTyCustomGrid.UpdateHoverCursor(X, Y: Integer);
var
  want: TCursor;
  hdrH: Integer;
begin
  want := crDefault;

  hdrH := 0;
  if hoVisible in FHeader.Options then
    hdrH := HeaderHeightPx + GroupBandHeightPx;

  { 列分隔线:只在列头带里认(与 MouseDown 同一条判定)。 }
  if (hoColumnResize in FHeader.Options) and (hdrH > 0) and (Y < hdrH)
     and (Y >= GroupBandHeightPx) and (DividerAtX(X) >= 0) then
    want := crHSplit
  { 行分隔线:只在行头槽里认(同样与 MouseDown 同源)。 }
  else if (Y >= hdrH) and (RowDividerAtY(X, Y) >= 0) then
    want := crVSplit
  { 链接格:手型。放在分隔线之后 —— 骑在分隔线上时该优先给调整光标,
    那是个更"贵"的操作(点错了列宽就变了)。 }
  else if HoverIsHyperlink(X, Y) then
    want := crHandPoint;

  if Cursor <> want then Cursor := want;
end;

procedure TTyCustomGrid.UpdateHoverCell(X, Y: Integer);
var
  hit: TTyGridHit;
  c, r, hc: Integer;
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
  { 列头段的 hover 与格的 hover 一起在这里算 —— 两处各算一遍迟早对不上,
    而它们本来就是同一次命中判定的两个答案。 }
  if hit.Part = ghpHeader then hc := hit.Col else hc := -1;
  if (c = FHoverCol) and (r = FHoverRow) and (hc = FHoverHeaderCol) then
    Exit;   { 同一格:不重绘 }
  FHoverCol := c;
  FHoverRow := r;
  FHoverHeaderCol := hc;
  Invalidate;
end;

procedure TTyCustomGrid.CMMouseLeave(var Msg: TLMessage);
begin
  inherited;
  if (FHoverCol >= 0) or (FHoverRow >= 0) or (FHoverHeaderCol >= 0) then
  begin
    FHoverCol := -1;
    FHoverRow := -1;
    FHoverHeaderCol := -1;    { 漏了这一句,鼠标离开控件时列头会一直亮着 }
    Invalidate;
  end;
end;

procedure TTyCustomGrid.CMBiDiModeChanged(var Msg: TLMessage);
begin
  inherited;
  { 列缓存存的是**逻辑**像素(BuildColumnCache 按索引累加),换向不影响它 ——
    反射发生在 ColumnLeftPx 的出口。要重来的是横向条的镜像开关(它由
    UpdateScrollBars 装配,LCL 换向时不会回头重跑)和整幅像素。 }
  UpdateScrollBars;
  Invalidate;
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
  { 表面新鲜度**照常**熄灭 —— 即使被锁住也不能留下"还新鲜"的错觉,
    否则解锁后那一次重画会走脏区快路径,复用上一帧的陈旧像素。 }
  FSurfaceFresh := False;
  FSurfacePendingDy := 0;
  if FUpdateCount > 0 then
  begin
    FPendingInvalidate := True;
    Exit;
  end;
  Inc(FRealInvalidates);
  inherited Invalidate;
end;

procedure TTyCustomGrid.BeginUpdate;
begin
  Inc(FUpdateCount);
  OpenUndoGroup;
end;

procedure TTyCustomGrid.EndUpdate;
begin
  if FUpdateCount = 0 then Exit;
  Dec(FUpdateCount);
  CloseUndoGroup;
  if FUpdateCount > 0 then Exit;
  if not FPendingInvalidate then Exit;
  FPendingInvalidate := False;
  Invalidate;
end;

{ 逐扫描行 memmove。比"整幅拷到临时位图再拷回来"省一半带宽,也不必额外分配。
  方向要选对:上移时从上往下搬,下移时从下往上搬 —— 反了会自己覆盖自己。 }
function TTyCustomGrid.MaxRowSpanHint: Integer;
begin
  Result := 1;
end;

procedure TTyCustomGrid.DoRowDragMove(AFrom, ATo: Integer);
begin
  { 基类不持有数据,拖不动任何东西。 }
end;

procedure TTyCustomGrid.RecordRowCountUndo(AOldCount: Integer);
begin
end;

procedure TTyCustomGrid.OpenUndoGroup;
begin
end;

procedure TTyCustomGrid.CloseUndoGroup;
begin
end;

function TTyCustomGrid.DisplayOrderIsDataOrder: Boolean;
begin
  Result := True;   { 基类没有行序间接层 }
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

{ 一行(或一块换行)**含右到左文字**的格子文本,走 BGRA 的 TBidiTextLayout 排,
  而不是一次 TextRect。

  为什么必须另开一条路:裸 TextRect 永远按**隐含的左到右段落基准**排版。调用里
  widgetset 的引擎确实会重排 run、也会把阿拉伯字母连写(这半边从来没坏过),
  但它**不问这一段到底是谁的段落**。于是 "<阿拉伯短语> Acme 3.0" —— 一个本地化
  报表里再普通不过的单元格 —— 两半被调了个个儿:阿拉伯文跑到左边,拉丁文尾巴
  跑到右边,正好是母语读者预期的反面。而**同一个字符串**放在旁边的标签里却是对的,
  因为 TTyPainter.DrawText 早就这么修过了(见 tyControls.Painter.pas 的
  DrawTextLineBidi,以及 tests/test.bidi.pas)。网格是唯一漏网的那条路径,
  因为 DrawCellText 为了那份文字缓存(十万行能滚起来全靠它)自己排字。

  TBidiTextLayout 用 fbmAuto:段落方向取自**第一个强方向字符**,也就是"用户写的是
  一句阿拉伯话"的意思。注意这**不是**控件的 BiDiMode —— 那个问的是"这个窗体朝哪边读",
  已由 RtlLayout 经 BidiFlipAlignment 折进 AHAlign 了,是另一个问题;
  把两者混为一谈会把右到左窗体上一个拉丁标题的两半也调过来。

  换行时才设 AvailableWidth:设了它布局自己就会按段落对齐,所以必须同时把
  ParagraphAlignment 钉死成调用方的 AHAlign,否则"块往哪边靠"这个决定会从
  控件手里偷偷跑到布局引擎手里(painter 那边留了同样的告诫)。
  不换行时**故意不设**,BGRA 读作"无限宽",块宽正好等于文字宽,由下面自己摆位 ——
  与 TTyPainter.BuildLineLayout 逐字同构。

  裁剪不用管:ABmp 就是这一格的大小,画出界的部分自然被位图边界切掉。 }
procedure TTyCustomGrid.DrawCellTextBidi(ABmp: TBGRABitmap; AW, AH: Integer;
  const AText: string; AColor: TTyColor; AHAlign: TAlignment;
  AVAlign: TTextLayout; AWordWrap: Boolean);
var
  lay: TBidiTextLayout;
  x, y, i: Integer;
  bta: TBidiTextAlignment;
begin
  Inc(FBidiLayouts);      { 只给测试的计数器,见 BidiLayoutCount }
  lay := TBidiTextLayout.Create(ABmp.FontRenderer, AText);
  try
    if AWordWrap then
    begin
      lay.AvailableWidth := AW;
      case AHAlign of
        taCenter:       bta := btaCenter;
        taRightJustify: bta := btaRightJustify;
      else
        bta := btaLeftJustify;
      end;
      for i := 0 to lay.ParagraphCount - 1 do
        lay.ParagraphAlignment[i] := bta;
      x := 0;
    end
    else
      case AHAlign of
        taCenter:       x := (AW - Ceil(lay.UsedWidth)) div 2;
        taRightJustify: x := AW - Ceil(lay.UsedWidth);
      else
        x := 0;
      end;
    case AVAlign of
      tlCenter: y := (AH - Ceil(lay.TotalTextHeight)) div 2;
      tlBottom: y := AH - Ceil(lay.TotalTextHeight);
    else
      y := 0;
    end;
    lay.TopLeft := PointF(x, y);
    lay.DrawText(ABmp, TyColorToBGRA(AColor));
  finally
    lay.Free;
  end;
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
begin
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) or (AText = '') then Exit;

  { **本函数不走 TTyPainter.DrawText**,所以画笔那一层的 RTL 对齐翻转够不着它 ——
    文字是画进自己的缓存位图、用 bmp.TextRect 排的(见下面)。于是这一句必须在这里
    自己翻一次,否则网格里几乎所有文字(单元格、行号、页脚、筛选位、换行表头)
    都会贴在镜像后单元格的**错误**一侧:列的位置全对,只有字靠错了边。
    翻在 key 之前:缓存键含 Ord(AHAlign),翻过再算键,运行时换向自然不会命中旧条目。
    LTR 下 BidiFlipAlignment 是恒等,像素逐一不变。 }
  AHAlign := BidiFlipAlignment(AHAlign, RtlLayout);

  fname := AFontName;
  sz := AFontSize;
  weight := AFontWeight;

  { 键 = 这块文字的**全部外观输入**。任何一项变了都是新条目,
    所以换主题/改列宽/切深色都不需要显式失效 —— 旧条目自然不再被命中。

    goCellEllipsis 也是一项外观输入 —— 同一串文字"加省略号"和"硬裁"画出来
    是两张不同的位图 —— 所以也进键。

    今天 SetOptions 里那句 ClearTextCache 已经够用了,这一项是**把失效变成
    结构性的**:不进键的话,正确性就挂在"每一条会改这个标志的路径都记得清缓存"
    上,而那是一条随时会被下一个人漏掉的口头约定。代价是每次缓存未命中多拼
    一个字符。 }
  key := AText + #1 + fname + #1 + IntToStr(sz) + #1 + IntToStr(weight) + #1 +
         IntToStr(AColor) + #1 + IntToStr(w) + 'x' + IntToStr(h) + #1 +
         IntToStr(Ord(AHAlign)) + #1 + IntToStr(Ord(AVAlign)) + #1 +
         IntToStr(Ord(AWordWrap)) + #1 + IntToStr(P.PPI) + #1 +
         IntToStr(Ord(goCellEllipsis in Options));

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
    if (not AWordWrap) and (goCellEllipsis in Options) then
    begin
      { 省略号截断走 TyGridEllipsisFit —— 那里连"砍到几个字"都用 TTyPainter 的
        TyEllipsisPrefix,两条路径排出来的字因此一模一样,而且砍的是字不是字节。
        换行时**不截断** —— 放不下就往下一行走,这正是换行的意义。
        goCellEllipsis 关掉时不截断,靠下面 st.Clipping 硬裁 —— 于是最后一个字
        会被切成半个,这正是 LCL 关掉 goCellEllipsis 时的样子。 }
      txt := TyGridEllipsisFit(bmp, txt, w);
    end;

    { 双向文字的闸门,和 TTyPainter.DrawTextLine 用的是同一个:一次字节扫描,
      ASCII 一比就否,CJK / 西里尔 / 希腊看首字节就否。问的是"这串**文字本身**
      有没有右到左的码点",与上面那次 BidiFlipAlignment(问的是"这个**窗体**朝哪边读")
      是两个独立的问题 —— 右到左窗体上的拉丁文照样不重排,左到右窗体上的阿拉伯文
      照样重排。
      排版发生在**缓存未命中的分支里**,这是有意的:TBidiTextLayout 建一次约 3.3ms,
      每帧每格建一次正是当年 TTyMemo 每键半秒的那个形状,而网格一帧要画几百格。
      键里含 AText,所以同一串文字全程只排一次。 }
    if TyTextHasRTL(txt) then
      DrawCellTextBidi(bmp, w, h, txt, AColor, AHAlign, AVAlign, AWordWrap)
    else
    begin
      st := Default(TTextStyle);
      st.Alignment := AHAlign;
      st.Layout := AVAlign;
      st.SingleLine := not AWordWrap;
      st.Wordbreak := AWordWrap;
      st.Clipping := True;
      bmp.TextRect(Rect(0, 0, w, h), 0, 0, txt, st, TyColorToBGRA(AColor));
    end;

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

function TTyCustomGrid.TextCacheCount: Integer;
begin
  if FTextCache = nil then Result := 0 else Result := FTextCache.Count;
end;

procedure TTyCustomGrid.ResetBidiLayoutCount;
begin
  FBidiLayouts := 0;
end;

function TTyCustomGrid.IsActiveCell(ACol, ARow: Integer): Boolean;
begin
  Result := False;
end;

function TTyCustomGrid.IsActiveRow(ARow: Integer): Boolean;
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
  tol, ib0, ib1: Integer;
begin
  Result := -1;
  { goRowSizing。收口在这里而不是在 MouseDown 里,是因为**光标形状**
    (UpdateHoverCursor)问的也是这个函数 —— 分两处写的话会出现
    "指针变成了上下箭头,按下去却不动"的那种最招人烦的假动作。
    列那边(DividerAtX)的 hoColumnResize 也是同一个位置、同一条理由。 }
  if not (goRowSizing in Options) then Exit;
  { 只在行头槽里认分隔线 —— 在单元格上认的话会和框选拖拽抢手势。
    槽的位置走 IndicatorBandX(唯一出处),不再自己写一遍 `AX < IndicatorWidth`。 }
  if not IndicatorBandX(ib0, ib1) then Exit;
  if (AX < ib0) or (AX >= ib1) then Exit;

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
function TTyCustomGrid.HeaderHeightPx: Integer;
var
  i, need, w, lines: Integer;
  hdrS: TTyStyleSet;
  col: TTyColumn;
  sz: TSize;
  bmp: TBGRABitmap;
begin
  { The band's floor follows the density axis when the host did not pin Header.Height:
    classic 22 / modern --header-height (36). An explicit pin is honoured verbatim. }
  if FHeader.HeightIsExplicit then
    Result := ScaleI(FHeader.Height)
  else
    Result := ScaleI(TyDensityMetric(ActiveController, FHeader.Height, '--header-height'));
  if not FHeaderAutoHeight then Exit;
  if not (hoVisible in FHeader.Options) then Exit;
  if FHeader.Columns.Count = 0 then Exit;

  { 量最高的那个标题。Header.Height 当**下限** —— 自适应只往上撑,
    不会把一条正常高度的列头压扁。 }
  hdrS := ActiveController.Model.ResolveStyle('TyGridHeader', StyleClass, []);
  bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(bmp, hdrS.FontName, ResolveFontSize(hdrS),
      hdrS.FontWeight, Dpi);
    for i := 0 to FHeader.Columns.Count - 1 do
    begin
      col := TTyColumn(FHeader.Columns.Items[i]);
      if not (coVisible in col.Options) then Continue;
      if col.Text = '' then Continue;
      sz := bmp.TextSize(col.Text);
      if sz.cy <= 0 then Continue;
      lines := 1;
      if FHeaderWordWrap then
      begin
        w := ColumnWidthPx(i) - ScaleI(10);
        if w <= 0 then Continue;
        { 行数按"整条文字宽 / 可用宽"上取整估。真正的断行由绘制层做,
          这里只需要一个**随标题变长而变高**的下界;估多了会留白,
          估少了才会截断,所以宁可向上取整。 }
        lines := (sz.cx + w - 1) div w;
        if lines < 1 then lines := 1;
      end;
      need := sz.cy * lines + ScaleI(8);
      if need > Result then Result := need;
    end;
  finally
    bmp.Free;
  end;
end;

{ 分组带一共多少级(用到的最大 Level + 1)。0 = 没有分组。 }
function TTyCustomGrid.GroupLevelCount: Integer;
var
  i, lv: Integer;
begin
  Result := 0;
  for i := 0 to FHeaderGroups.Count - 1 do
  begin
    lv := TTyGridHeaderGroup(FHeaderGroups.Items[i]).Level;
    if lv < 0 then Continue;
    if lv + 1 > Result then Result := lv + 1;
  end;
end;

function TTyCustomGrid.GroupBandHeightPx: Integer;
begin
  if (FHeaderGroups.Count = 0) or not (hoVisible in FHeader.Options) then Exit(0);
  { 每一级占一条 —— 从前这里只乘 1,于是 Level>0 的组没有地方画,
    渲染循环索性把它们整个跳过:Level 是 published 却设了等于没设。 }
  Result := ScaleI(FGroupHeaderHeight) * GroupLevelCount;
end;

function TTyCustomGrid.FilterRowHeightPx: Integer;
begin
  { 跟着列头一起藏 —— 没有列头的时候一条孤零零的筛选行没有依托。 }
  if (not FShowFilterRow) or not (hoVisible in FHeader.Options) then Exit(0);
  if FFilterRowHeight > 0 then Result := ScaleI(FFilterRowHeight)
  else Result := HeaderHeightPx;      { 0 = 跟列头同高 }
end;

procedure TTyCustomGrid.SetShowFilterRow(AValue: Boolean);
begin
  if FShowFilterRow = AValue then Exit;
  FShowFilterRow := AValue;
  UpdateScrollBars;      { 冻结带厚度变了 → 可滚范围跟着变 }
  Invalidate;
end;

procedure TTyCustomGrid.SetFilterRowHeight(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FFilterRowHeight = AValue then Exit;
  FFilterRowHeight := AValue;
  if FShowFilterRow then
  begin
    UpdateScrollBars;
    Invalidate;
  end;
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
  AHeaderH, ASlotLeft, ASlotRight: Integer);
var
  slot: Integer;   { 绘制槽位 }
  first, last, pos: Integer;
  r: TRect;
  { 别取名 iS —— Pascal 大小写不敏感,它就是保留字 is。
    (和当初 col↔Col、cellS↔Cells 同一类坑。) }
  indS: TTyStyleSet;
  ink: TTyColor;

  { 交给 DrawInRowBand 执行 —— 裁剪由它负责,这里只管画。 }
  procedure DrawOneNumber;
  var
    slot: TRect;
  begin
    { 槽是**调用方给的那一条**(RenderChrome 用同一条铺底色),这里只在它的
      尾缘让出 4px 气口 —— 回到阅读空间做那一次内缩,再送回屏幕。
      写成第二份 `Rect(0, .., IndicatorWidth - 4, ..)` 就又是两个表达式了,
      而这条槽的位置正是本次改动收口掉的那四份之一。
      taRightJustify 由画笔那一层(BeginPaintOn 收到的 RTL 标志)翻成
      taLeftJustify —— 槽换了边而对齐没换,号码会贴到槽外那一侧去。 }
    slot := ToReadingRect(Rect(ASlotLeft, r.Top, ASlotRight, r.Bottom));
    Dec(slot.Right, ScaleI(4));
    DrawCellText(P, ToScreenRect(slot),
      IntToStr(pos + 1), indS.FontName, ResolveFontSize(indS), indS.FontWeight,
      ink, taRightJustify, tlCenter);
  end;

begin
  if not FShowRowNumbers then Exit;
  if ASlotRight <= ASlotLeft then Exit;
  { 走绘制槽位:顶部固定行 + 正文窗口(固定行不在正文窗口里)。 }
  if not TyGridDrawSlots(M, first, last) then Exit;

  { 复用行头槽自己的 typeKey 取墨色与字体 —— 不硬编码任何视觉值,
    也不借别的控件的键。 }
  indS := ActiveController.Model.ResolveStyle('TyGridIndicator', StyleClass, []);
  if tpTextColor in indS.Present then ink := indS.TextColor
  else ink := CurrentStyle.TextColor;

  { 行号按**显示序**给:排序/筛选之后,屏幕第一行仍然是 1。
    (给数据行号的话,排一次序行号就乱跳,那不是行号该有的样子。) }
  for slot := first to last do
  begin
    pos := TyGridRowAtSlot(slot, M);
    if pos < 0 then Continue;
    r := TyGridRowRect(pos, M);
    { 裁到这一行**所属的那条带**。一把大裁剪会让正文行的行号漏进冻结带:
      滚到上冻结带底下的行会把号码画到固定行的槽位上,滚到下冻结带底下的
      画到底部固定行的槽位上。 }
    DrawInRowBand(P, pos, M, @DrawOneNumber);
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
    col := FHeader.Columns.Items[ACol];
    Result.HAlign := col.Alignment;
    { 垂直对齐同样跟着列走(TTyGridColumn.Layout);别的控件共用的 TTyColumn
      没有这个成员,所以要判类型 —— 不是网格的列就仍是 tlCenter。 }
    if col is TTyGridColumn then Result.VAlign := TTyGridColumn(col).Layout;
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

  { 整列底色(TTyGridColumn.Color)。排在斑马纹**之后** —— 列色是宿主对这一列
    数据的判断("只读列灰底"),比装饰性的隔行条纹具体;排在逐格/行色**之前** ——
    那两个更具体。刻意不置 HasExplicitBackground:那面旗子的意思是"用户手工标了
    这一格",焦点格底色因此避让;整列的基调不该让焦点框在这一列上消失。 }
  if (ACol >= 0) and (ACol < FHeader.Columns.Count) then
  begin
    col := FHeader.Columns.Items[ACol];
    if (col is TTyGridColumn) and (TTyGridColumn(col).Color <> 0) then
    begin
      Result.HasBackground := True;
      Result.Background := Default(TTyFill);
      Result.Background.Kind := tfkSolid;
      Result.Background.Color := TTyGridColumn(col).Color;
    end;
  end;

  { 逐格**持久**外观(Colors[c,r] / TextColors[c,r] / RowColor[r] 落在属性存储里)。
    优先级:主题 → 斑马纹 → 列色 → 行色 → 逐格色 → 宿主钩子。
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
    { 逐格字体样式:粗体走字重(本库的文字层按字重画,没有独立的 bold 开关),
      斜体/下划线本库的文字层暂不支持 —— 存得住、但只有粗体画得出来。
      这一条写在这里而不是悄悄丢掉:存了却不画是最容易的假完成。 }
    if attr.HasFontStyle and (fsBold in attr.FontStyle) then
      Result.FontWeight := 700;
  end;

  { **焦点格**要和选区区分开:gsmRow 模式下整行都是选中底色,不区分的话
    根本看不出光标在哪一格。用自己的 typeKey,主题没定义就什么都不做。

    goRowHighlight 把这块底色从"光标那一格"摊到"光标那一行"。共用
    TyGridActiveCell 这个键是有意的:它已经是**本控件自己的**键(不是借来的),
    语义也正是"光标落点的底色"。代价是主题分不开"焦点格"和"高亮行"两档 ——
    真要分开得加一个 TyGridRowHighlight 键,那要动 themes/,记在 grid.md 里。 }
  if FShowFocusCell
     and (IsActiveCell(ACol, ARow)
          or ((goRowHighlight in Options) and IsActiveRow(ARow))) then
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

procedure TTyCustomGrid.SetImages(AValue: TCustomImageList);
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
  { goScrollKeepVisible:视口已经落定(FScrollX 先赋值)才去拖光标 ——
    反过来的话 KeepCursorVisible 算的是**旧**视口,永远拖不对。 }
  if goScrollKeepVisible in Options then KeepCursorVisible;
  Invalidate;
  NotifyTopLeftChanged;
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
  { 同 SetScrollX:FScrollY 先落定再问"光标该去哪",否则算的是旧视口。

    光标真的动了的时候,KeepCursorVisible 里的 SelectionChanged 会走一次
    **普通** Invalidate,于是上面那份平移复用的许可被熄掉、这一帧整幅重画。
    那是对的:换了当前格,焦点底色和选区都变了,平移旧像素本来就不成立。
    没开这个标志时一行都不多跑。 }
  if goScrollKeepVisible in Options then KeepCursorVisible;
  NotifyTopLeftChanged;
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

function TTyCustomGrid.RtlLayout: Boolean;
begin
  Result := IsRightToLeft;
end;

function TTyCustomGrid.ToScreenRect(const ARect: TRect): TRect;
begin
  Result := ARect;
  if RtlLayout then
    Result := BidiFlipRect(Result, Rect(0, 0, ViewportW, 0), True);
end;

function TTyCustomGrid.ToReadingX(AX: Integer): Integer;
begin
  Result := AX;
  if RtlLayout then
    Result := BidiFlipRect(Rect(AX, 0, AX + 1, 0), Rect(0, 0, ViewportW, 0), True).Left;
end;

function TTyCustomGrid.ToReadingRect(const ARect: TRect): TRect;
begin
  Result := ToScreenRect(ARect);   { 反射自逆 —— 见声明处 }
end;

function TTyCustomGrid.IndicatorBandX(out ALeft, ARight: Integer): Boolean;
var
  r: TRect;
begin
  ALeft := 0;
  ARight := 0;
  Result := False;
  if not FShowIndicator then Exit;
  if FIndicatorWidth <= 0 then Exit;
  { 逻辑上恒是"最前面那条槽" —— 从阅读起点起算。反射交给唯一那个变换。 }
  r := ToScreenRect(Rect(0, 0, ScaleI(FIndicatorWidth), 0));
  ALeft := r.Left;
  ARight := r.Right;
  Result := ARight > ALeft;
end;

function TTyCustomGrid.LeadFrozenBandX(out ALeft, ARight: Integer): Boolean;
var
  r: TRect;
begin
  r := ToScreenRect(Rect(0, 0, FrozenWidthPx, 0));
  ALeft := r.Left;
  ARight := r.Right;
  Result := ARight > ALeft;
end;

procedure TTyCustomGrid.BodyBandX(const M: TTyGridMetrics;
  out ALeft, ARight: Integer);
var
  r: TRect;
begin
  { 直接问窗格函数。它已经把两条冻结带钳到视口内、且保证九格无缝铺满 ——
    在这里另写一遍 `FrozenLeft .. ClientW - FrozenRight` 就是第二份钳制规则。 }
  r := TyGridPaneRect(M, gpBody);
  ALeft := r.Left;
  ARight := r.Right;
end;

function TTyCustomGrid.ClipColToBody(const M: TTyGridMetrics; ACol: Integer;
  var ALeft, AWidth: Integer): Boolean;
var
  bl, br, right: Integer;
begin
  Result := AWidth > 0;
  if not Result then Exit;
  right := ALeft + AWidth;
  { 固定列本来就画在冻结带里,不裁。 }
  if (ACol < FFixedCols)
     or (ACol >= FHeader.Columns.Count - EffectiveFixedColsRight) then Exit;
  BodyBandX(M, bl, br);
  if ALeft < bl then ALeft := bl;
  if right > br then right := br;
  AWidth := right - ALeft;
  Result := AWidth > 0;
end;

function TTyCustomGrid.ColumnSpanX(AFirst, ALast: Integer;
  out ALeft, ARight: Integer): Boolean;
var
  a0, a1, b0, b1: Integer;
begin
  ALeft := 0;
  ARight := 0;
  Result := False;
  if (AFirst < 0) or (AFirst >= FHeader.Columns.Count) then Exit;
  if ALast < AFirst then ALast := AFirst;
  if ALast >= FHeader.Columns.Count then ALast := FHeader.Columns.Count - 1;
  a0 := ColumnLeftPx(AFirst);  a1 := a0 + ColumnWidthPx(AFirst);
  b0 := ColumnLeftPx(ALast);   b1 := b0 + ColumnWidthPx(ALast);
  { 取两端的并集而不是 `a0 .. b1` —— 后者在 RTL 下是反向矩形。 }
  ALeft  := a0; if b0 < ALeft  then ALeft  := b0;
  ARight := a1; if b1 > ARight then ARight := b1;
  Result := ARight > ALeft;
end;

function TTyCustomGrid.ColumnResizeEdgeX(ACol: Integer): Integer;
begin
  if RtlLayout then Result := ColumnLeftPx(ACol)
  else Result := ColumnLeftPx(ACol) + ColumnWidthPx(ACol);
end;

function TTyCustomGrid.MirrorColX(ALogicalLeft, ACol: Integer): Integer;
var
  w: Integer;
begin
  Result := ALogicalLeft;
  if not RtlLayout then Exit;      { LTR:恒等,一个像素都不动 }
  w := 0;
  if (ACol >= 0) and (ACol < Length(FColWidthPx)) then w := FColWidthPx[ACol];
  Result := ToScreenRect(Rect(ALogicalLeft, 0, ALogicalLeft + w, 0)).Left;
end;

function TTyCustomGrid.ArrowColStep(ADelta: Integer): Integer;
begin
  if RtlLayout then Result := -ADelta else Result := ADelta;
end;

function TTyCustomGrid.ColumnLeftPx(ACol: Integer): Integer;
var
  i, n: Integer;
begin
  Result := 0;
  if (ACol < 0) or (ACol >= FHeader.Columns.Count) then Exit;
  if not FColCacheValid then BuildColumnCache;
  if ACol >= Length(FColBasePx) then Exit;

  { 右侧冻结列:钉在视口右沿,自右往左排。与左固定列对称。 }
  n := EffectiveFixedColsRight;
  if (n > 0) and (ACol >= FHeader.Columns.Count - n) then
  begin
    { 锚在**视口**右沿,不是控件右沿 —— 纵向滚动条占掉的那十几像素不属于视口。
      用 ClientWidth 的话整条右冻结带右移一个滚动条宽,最右那一列被裁掉一截
      (窗格矩形走的是 M.ClientW = ViewportW,两边必须同源)。 }
    Result := ViewportW;
    for i := FHeader.Columns.Count - 1 downto ACol do
      if i < Length(FColWidthPx) then Dec(Result, FColWidthPx[i]);
    Result := MirrorColX(Result, ACol);
    Exit;
  end;

  Result := FColBasePx[ACol];
  { 固定列钉在冻结带里不随横向滚动;正文列才平移 —— 这正是"冻结"的全部含义。
    滚动量在**读取时**才减,所以横向滚动不必让缓存失效。 }
  if ACol >= FFixedCols then
    Dec(Result, FScrollX);
  Result := MirrorColX(Result, ACol);
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
  i, l, w, lb0, lb1: Integer;
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
      { 被**前导**冻结带(行头槽 + 左固定列)盖住。RTL 下这条带整条挪到视口右沿,
        于是判据不能再写成 `AX < FrozenWidthPx`;走 LeadFrozenBandX 之后
        LTR 下它逐字节还原成那一句,RTL 下自动变成"落在右沿那条带里"。
        右冻结带仍然**不需要**对称的守卫 —— 见下方说明,那条规则也镜像了。 }
      if (i >= FFixedCols) and LeadFrozenBandX(lb0, lb1)
         and (AX >= lb0) and (AX < lb1) then Continue;
      { 右冻结带**不需要**对称的守卫:这里是倒序扫,而右冻结列就是最后那几列,
        落在右带里的点必然先命中它们。加过一条,变异测试证明它无法被区分
        (删掉没有任何测试变红)—— 够不着的代码不留。 }
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

function TTyCustomGrid.VisibleRowCount: Integer;
var
  M: TTyGridMetrics;
  first, last: Integer;
begin
  Result := 0;
  M := GridMetrics;
  if not TyGridVisibleRows(M, first, last) then Exit;
  { `last - first`, not `last - first + 1`: see the declaration -- LCL keeps one row
    of overlap so a page turn does not skip the seam row. }
  Result := last - first;
  { The whole grid on screen means there is nothing to page, so no overlap is kept.
    HeaderH + content, not FrozenTop + content: FrozenTop already contains the header
    bands AND the fixed rows, and the fixed rows are part of the content height too --
    adding both would count them twice and hide the "it fits" case on every grid that
    has a frozen row. }
  if TyGridHeaderH(M) + TyGridContentHeight(M) <= M.ClientH then Inc(Result);
  if Result < 0 then Result := 0;
end;

function TTyCustomGrid.GetLeftCol: Integer;
var
  i, l, w, frozen: Integer;
begin
  { 第一个"有像素落在正文区里"的可滚动列。倒序扫不行 —— 要的是最靠阅读起点的那个,
    而 ColumnAtX(冻结带边缘) 也不行:那一点归属谁,取决于 ColumnAtX 里
    "被冻结带盖住的正文列跳过"那条规则,答出来会是冻结列本身。

    判据本身一个字没改(`列的尾缘 > 正文带的首缘`),改的只是**先把列反射回
    阅读空间再比** —— 比较符号里写死一个方向,是 RTL 下最难看出来的一类错。
    在阅读空间里,正文带的首缘恒是 FrozenWidthPx(两个方向同一个数),
    所以这一句在 LTR 下逐字节等价于从前的 `右缘 > FrozenWidthPx`。
    (不走 GridMetrics:本函数在每次滚动时都被调,而那个记录要装配行高前缀和。) }
  frozen := FrozenWidthPx;
  for i := FFixedCols to FHeader.Columns.Count - 1 do
  begin
    if not (coVisible in FHeader.Columns.Items[i].Options) then Continue;
    l := ColumnLeftPx(i);
    w := ColumnWidthPx(i);
    if ToReadingRect(Rect(l, 0, l + w, 0)).Right > frozen then Exit(i);
  end;
  { 一列都没有(或全滚过去了):答第一个可滚列,别答 -1 —— 这是个"视口在哪"的
    坐标,不是命中判定,给个界外值只会让宿主拿去当下标。 }
  Result := NextVisibleCol(FFixedCols, 1);
end;

procedure TTyCustomGrid.SetLeftCol(AValue: Integer);
begin
  if AValue < FFixedCols then AValue := FFixedCols;
  if AValue > FHeader.Columns.Count - 1 then AValue := FHeader.Columns.Count - 1;
  if AValue < 0 then Exit;
  if not FColCacheValid then BuildColumnCache;
  if AValue >= Length(FColBasePx) then Exit;
  { FColBasePx 是**未减滚动量**的左缘;让它正好落在冻结带右缘,
    那一列就贴着正文区左边了。SetScrollX 负责钳到 [0, MaxScrollX]。 }
  SetScrollX(FColBasePx[AValue] - FrozenWidthPx);
end;

function TTyCustomGrid.GetTopRow: Integer;
var
  M: TTyGridMetrics;
  first, last: Integer;
begin
  M := GridMetrics;
  if TyGridVisibleRows(M, first, last) then Exit(first);
  { 滚动窗口是空的(整表都在冻结带里、或者没有行):第一个可滚的显示位置。 }
  Result := FFixedRows;
  if Result > DisplayRowCount - 1 then Result := DisplayRowCount - 1;
  if Result < 0 then Result := 0;
end;

procedure TTyCustomGrid.SetTopRow(AValue: Integer);
var
  M: TTyGridMetrics;
  fixedTop, fixedH, rowTop, dummy: Integer;
begin
  if AValue < FFixedRows then AValue := FFixedRows;
  if AValue > DisplayRowCount - 1 then AValue := DisplayRowCount - 1;
  if AValue < 0 then Exit;

  M := GridMetrics;
  { 目标行在**内容坐标**里的顶边,减掉固定行占掉的那一段 —— 那一段不参与滚动,
    ScrollY=0 时正文区显示的就是第 FixedRows 行,不是第 0 行。
    (局部变量不叫 top:TControl 已经有 Top 属性,同名会被判重。) }
  TyGridRowExtent(AValue, M, rowTop, dummy);
  fixedTop := 0;
  if FFixedRows > 0 then TyGridRowExtent(FFixedRows, M, fixedTop, fixedH);
  SetScrollY(rowTop - fixedTop);
end;

function TTyCustomGrid.VisibleColCount: Integer;
var
  i, frozen, right: Integer;
  l, w: Integer;
  colR: TRect;
begin
  { 与 VisibleRowCount 同一条口径:有像素落在视口里就算看得见(半列也算)。
    冻结列恒可见,所以从 0 数起而不是从 FixedCols。

    两条判据都带方向性比较符,所以列与视口一起反射回阅读空间再比 ——
    式子一个字不改,LTR 逐字节等价。 }
  Result := 0;
  frozen := FrozenWidthPx;
  right := ViewportW;
  for i := 0 to FHeader.Columns.Count - 1 do
  begin
    if not (coVisible in FHeader.Columns.Items[i].Options) then Continue;
    l := ColumnLeftPx(i);
    w := ColumnWidthPx(i);
    if w <= 0 then Continue;
    colR := ToReadingRect(Rect(l, 0, l + w, 0));
    if i >= FFixedCols then
    begin
      { 滚到冻结带底下的那一段看不见 —— 整列都在下面就不算。 }
      if colR.Right <= frozen then Continue;
    end;
    if colR.Left >= right then Continue;
    Inc(Result);
  end;
end;

function TTyCustomGrid.GetScrollBars: TScrollStyle;
begin
  { 两个三态属性有九种组合,TScrollStyle 只表达得了其中六种。表达不了的组合
    答 ssAutoBoth(它的默认值)—— 别拿一个错的具体值糊弄宿主。 }
  if (FVertScrollBarMode = gsbNever) and (FHorzScrollBarMode = gsbNever) then
    Exit(ssNone);
  if FHorzScrollBarMode = gsbNever then
  begin
    if FVertScrollBarMode = gsbAlways then Exit(ssVertical);
    Exit(ssAutoVertical);
  end;
  if FVertScrollBarMode = gsbNever then
  begin
    if FHorzScrollBarMode = gsbAlways then Exit(ssHorizontal);
    Exit(ssAutoHorizontal);
  end;
  if (FVertScrollBarMode = gsbAlways) and (FHorzScrollBarMode = gsbAlways) then
    Exit(ssBoth);
  Result := ssAutoBoth;
end;

procedure TTyCustomGrid.SetScrollBars(AValue: TScrollStyle);
begin
  case AValue of
    ssNone:
      begin
        SetVertScrollBarMode(gsbNever);
        SetHorzScrollBarMode(gsbNever);
      end;
    ssHorizontal:
      begin
        SetVertScrollBarMode(gsbNever);
        SetHorzScrollBarMode(gsbAlways);
      end;
    ssVertical:
      begin
        SetVertScrollBarMode(gsbAlways);
        SetHorzScrollBarMode(gsbNever);
      end;
    ssBoth:
      begin
        SetVertScrollBarMode(gsbAlways);
        SetHorzScrollBarMode(gsbAlways);
      end;
    ssAutoHorizontal:
      begin
        SetVertScrollBarMode(gsbNever);
        SetHorzScrollBarMode(gsbAuto);
      end;
    ssAutoVertical:
      begin
        SetVertScrollBarMode(gsbAuto);
        SetHorzScrollBarMode(gsbNever);
      end;
    else   { ssAutoBoth }
      begin
        SetVertScrollBarMode(gsbAuto);
        SetHorzScrollBarMode(gsbAuto);
      end;
  end;
end;

procedure TTyCustomGrid.SetOnTopLeftChanged(AValue: TNotifyEvent);
begin
  FOnTopLeftChanged := AValue;
  { 挂上钩子时把"上一次的左上角"播种成**现在**的位置。不播的话缓存还停在 -1
    (构造时的哨兵,因为没挂钩子时 NotifyTopLeftChanged 一步都不走),于是挂完
    之后的第一次滚动必然与 -1 不等 —— 哪怕那次滚动根本没换行,事件照发。 }
  if Assigned(AValue) then
  begin
    FLastLeftCol := GetLeftCol;
    FLastTopRow := GetTopRow;
  end;
end;

procedure TTyCustomGrid.NotifyTopLeftChanged;
var
  l, t: Integer;
begin
  { 没接钩子就一步也别走 —— GetTopRow 要算一次 GridMetrics,而这里是滚动路径。 }
  if not Assigned(FOnTopLeftChanged) then Exit;
  l := GetLeftCol;
  t := GetTopRow;
  if (l = FLastLeftCol) and (t = FLastTopRow) then Exit;
  FLastLeftCol := l;
  FLastTopRow := t;
  FOnTopLeftChanged(Self);
end;

procedure TTyCustomGrid.MapToBaseCell(var ACol, ARow: Integer);
begin
  { 基类没有合并。 }
end;

{ 屏幕左带 <-> 屏幕右带。CellPane 按**列的角色**(左固定 / 右固定)选带,
  而带的名字说的是屏幕位置 —— RTL 下两者对不上,在出口换一次。
  与 GridMetrics 里换 FrozenLeft/FrozenRight 是同一次换边的两半:
  只换一半,格子就会被裁到对面那条带上,结果是一个空矩形(整列消失)。 }
function TyMirrorPane(APane: TTyGridPane): TTyGridPane;
begin
  case APane of
    gpTopLeft:     Result := gpTopRight;
    gpTopRight:    Result := gpTopLeft;
    gpLeft:        Result := gpRight;
    gpRight:       Result := gpLeft;
    gpBottomLeft:  Result := gpBottomRight;
    gpBottomRight: Result := gpBottomLeft;
  else             Result := APane;    { 中间那一列(gpTop/gpBody/gpBottom)自镜像 }
  end;
end;

function TTyCustomGrid.CellPane(ACol, APos: Integer): TTyGridPane;
begin
  Result := CellPaneLtr(ACol, APos);
  if RtlLayout then Result := TyMirrorPane(Result);
end;

function TTyCustomGrid.CellPaneLtr(ACol, APos: Integer): TTyGridPane;
begin
  { 行也要分窗格,不只是列。固定行的矩形钉在上冻结带里,而正文窗格从冻结带
    **之下**才开始 —— 把它们一律算作正文窗格的话,可见矩形恒为空,
    于是固定行连一个像素都画不出来(占着高度的空白带就是这么来的)。

    APos 是**显示位置**。被筛掉的行没有显示位置(-1),不该被 `-1 < FixedRows`
    误判进顶部冻结带 —— 只按列分。 }
  if (APos >= 0) and (APos < FFixedRows) then
  begin
    { 三路,与底部带对称。原先只分左/中,于是同时开右冻结列时,
      右上角那一格被判成 gpTop,与**不含**右冻结列的顶部带求交后成了空矩形 ——
      那一格凭空消失。`gpTopRight` 在枚举里躺着,一直没有生产者。 }
    if ACol < FFixedCols then Result := gpTopLeft
    else if ACol >= FHeader.Columns.Count - EffectiveFixedColsRight then
      Result := gpTopRight
    else Result := gpTop;
    Exit;
  end;
  if (FFixedRowsBottom > 0) and (APos >= 0)
     and (APos >= DisplayRowCount - FFixedRowsBottom) then
  begin
    if ACol < FFixedCols then Result := gpBottomLeft
    else if ACol >= FHeader.Columns.Count - EffectiveFixedColsRight then
      Result := gpBottomRight
    else Result := gpBottom;
    Exit;
  end;
  if ACol >= FHeader.Columns.Count - EffectiveFixedColsRight then
  begin
    Result := gpRight;
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
  { 数据行 → 显示位置的转换**只在这里做一次**。CellPane 收显示位置。 }
  pane := TyGridPaneRect(GridMetrics, CellPane(ACol, DataToDisplay(ARow)));
  if not IntersectRect(Result, cell, pane) then
    Result := Rect(0, 0, 0, 0);
end;

function TTyCustomGrid.CellAt(AX, AY: Integer): TTyGridHit;
var
  M: TTyGridMetrics;
  ib0, ib1: Integer;
begin
  Result.Part := ghpNowhere;
  Result.Col := -1;
  Result.Row := -1;

  M := GridMetrics;
  if (AX < 0) or (AY < 0) or (AX >= M.ClientW) or (AY >= M.ClientH) then Exit;

  { 列头带优先:它横跨整幅宽度,盖在行头槽之上。 }
  { 表头整体(分组带 + 列头带)。**排序/筛选按钮只在叶子级**,所以落在分组带里
    不返回列头命中 —— 否则点一下分组标题会把下面某一列排序掉。 }
  { 内嵌筛选行:紧贴在列头之下、还在冻结带里。**先于**单元格判定,
    否则它下面那条判断会把它当成正文的第一行。 }
  if (FilterRowHeightPx > 0)
     and (AY >= HeaderHeightPx + GroupBandHeightPx)
     and (AY < HeaderHeightPx + GroupBandHeightPx + FilterRowHeightPx) then
  begin
    Result.Part := ghpFilterRow;
    Result.Col := ColumnAtX(AX);
    Exit;
  end;

  if (hoVisible in FHeader.Options)
     and (AY < HeaderHeightPx + GroupBandHeightPx) then
  begin
    if AY < GroupBandHeightPx then Exit;   { 分组带:不是叶子列头 }
    Result.Part := ghpHeader;
    Result.Col := ColumnAtX(AX);
    Exit;
  end;

  { 行头槽:列头之下、冻结带最前那条(RTL 下在右)。走 IndicatorBandX ——
    这一条判断从前在四处各写一遍。 }
  if IndicatorBandX(ib0, ib1) and (AX >= ib0) and (AX < ib1) then
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

  { 一条横线。交给 DrawInRowBand 执行 —— 裁剪由它负责。 }
  procedure DrawOneRowLine;
  var
    j, cx: Integer;
    c: TTyColumn;
  begin
    if not merged then
    begin
      P.Bitmap.FillRect(0, r.Bottom - 1 - half, M.ClientW, r.Bottom - 1 - half + lw,
        line, dmSet);
      Exit;
    end;
    { 逐列分段:本行与下一行在这一列上属于同一个合并区时,跳过这一段。 }
    for j := 0 to FHeader.Columns.Count - 1 do
    begin
      c := TTyColumn(FHeader.Columns.Items[j]);
      if not (coVisible in c.Options) then Continue;
      if SameMergedCell(j, DisplayToData(row), j, DisplayToData(row + 1)) then Continue;
      cx := ColumnLeftPx(j);
      P.Bitmap.FillRect(cx, r.Bottom - 1 - half,
        cx + ColumnWidthPx(j), r.Bottom - 1 - half + lw, line, dmSet);
    end;
  end;

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

  { 横线:每一可见行的下沿。只走绘制槽位 —— 百万行的表在这里也只画几十条。
    每条线都裁到它那一行所属的带,否则滚到冻结带底下的行会把线画进冻结带里
    (单元格内容靠 CellVisibleRect 挡住了,线这条路径没有)。 }
  if (FGridLineStyle in [glsHorizontal, glsBoth]) and TyGridDrawSlots(M, first, last) then
    for slot := first to last do
    begin
      row := TyGridRowAtSlot(slot, M);
      if row < 0 then Continue;
      r := TyGridRowRect(row, M);
      DrawInRowBand(P, row, M, @DrawOneRowLine);
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
    { goFixedColSizing:关掉时冻结列的分隔线不认。判据与 ClipColToBody
      用的是同一对(前导 FixedCols + 尾部 FixedColsRight),两边不同步的话
      会出现"能拖的列"和"画在冻结带里的列"对不上。 }
    if not (goFixedColSizing in Options) then
      if (i < FFixedCols)
         or (i >= FHeader.Columns.Count - EffectiveFixedColsRight) then Continue;
    { 抓的是这一列的**尾缘** —— LTR 右缘、RTL 左缘。走 ColumnResizeEdgeX,
      拖动的位移(MouseMove)读的也是同一个定义,所以"抓住的线"与
      "变宽的列"不可能是两列。 }
    edge := ColumnResizeEdgeX(i);
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
  hdrH, d, ib0, ib1: Integer;
  col: TTyColumn;
begin
  inherited MouseDown(Button, Shift, X, Y);
  { 无条件记账 —— 要在所有提前 Exit 之前,否则分隔条/右键那几条路径上
    留下的是上一次的陈旧命中。 }
  FLastDownHit := CellAt(X, Y);
  if Button <> mbLeft then Exit;

  hdrH := 0;
  if hoVisible in FHeader.Options then
    hdrH := HeaderHeightPx + GroupBandHeightPx;

  { 行分隔线在**行头槽**里拖 —— 与列分隔线在列头里拖对称。
    放在单元格上会和框选拖拽抢手势。 }
  if Y >= hdrH then
  begin
    d := RowDividerAtY(X, Y);
    { 分组行没有"行高"可拖(它的数据行号是负的,写回去会被存储挡掉)。
      不在这里挡住的话:手势看着是启动了(指针变了、能拖),实际一动不动,
      而 `OnRowSizing` 每次鼠标移动都会被喂一个**负行号**。 }
    if (d >= 0) and (DisplayToData(d) >= 0) then
    begin
      FResizeRow := d;
      FResizeStartY := Y;
      FResizeStartH := RowHeightOf(DisplayToData(d));
      Exit;
    end;

    { 行头槽里按下(且不在分隔线上)= 准备拖行。
      分隔线优先:边缘那几像素上用户的意图是改行高,不是搬行。
      槽位走 IndicatorBandX —— 第四处、也是最后一处 `X < IndicatorWidth`。 }
    if (Button = mbLeft) and (goRowMoving in Options)
       and IndicatorBandX(ib0, ib1)
       and (X >= ib0) and (X < ib1)
       and DisplayOrderIsDataOrder then
    begin
      d := TyGridRowAt(Y, GridMetrics);
      if d >= 0 then
      begin
        FDragRow := DisplayToData(d);
        FDragStartY := Y;
      end;
    end;
    Exit;
  end;

  if hdrH <= 0 then Exit;

  { 分隔条优先于列体 —— 边缘那几像素上,用户的意图是改宽而不是排序。 }
  d := DividerAtX(X);
  if d >= 0 then
  begin
    { 双击分隔线 = 按内容自适应列宽,是表格的通用手势。
      LCL 在第二次按下时把 ssDouble 塞进 Shift。
      goDblClickAutoSize 关掉时**不是什么都不做**,而是落到下面那条普通的
      拖拽改宽上去 —— 双击的第二下本来就是一次按下,吞掉它会让用户觉得
      "双击之后列头就卡住了"。 }
    if (ssDouble in Shift) and (goDblClickAutoSize in Options) then
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
    { 记下被按住的那一段。**状态总是记**、重绘只在 goHeaderPushedLook 开着时做:
      标志关掉时这条路径与从前逐位一致(连重绘次数都一样),不给现有窗体添一帧。 }
    FPressedHeaderCol := d;
    if goHeaderPushedLook in Options then Invalidate;
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
    { **位移也要反射**。RTL 下往左拖是变宽,而这里从前是一个裸减号 ——
      静态截图完全正确、一拖列宽就朝反方向变,任何绘制测试都红不了。
      两端各过一次 ToReadingX(而不是加一个 `if rtl then -delta`):
      它与 ColumnResizeEdgeX 用的是同一个反射,不可能差半格。 }
    delta := UnscaleI(ToReadingX(X) - ToReadingX(FResizeStartX));
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

  if FDragRow >= 0 then
  begin
    { 越过阈值才算拖动 —— 否则手抖一像素就把行挪了。 }
    if Abs(Y - FDragStartY) < ScaleI(8) then Exit;
    target := TyGridRowAt(Y, GridMetrics);
    if target >= 0 then target := DisplayToData(target);
    if (target >= 0) and (target <> FDragRow) then
    begin
      allow := True;
      if Assigned(FOnRowMove) then FOnRowMove(Self, FDragRow, target, allow);
      if allow then
      begin
        DoRowDragMove(FDragRow, target);
        FDragRow := target;
        FDragStartY := Y;
        Invalidate;
      end;
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
  FDragRow := -1;
  { 松手 = 不再按住。同样只在标志开着时重绘(见 MouseDown)。 }
  if FPressedHeaderCol >= 0 then
  begin
    FPressedHeaderCol := -1;
    if goHeaderPushedLook in Options then Invalidate;
  end;
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

function TTyCustomGrid.HeaderSortGlyphW(ACol: Integer): Integer;
begin
  Result := 0;
  if (hoShowSortGlyphs in FHeader.Options) and (ACol = FHeader.SortColumn) then
    Result := ScaleI(12);
end;

function TTyCustomGrid.HeaderFunnelCenterX(ACol: Integer): Integer;
var
  l, w: Integer;
  sec: TRect;
begin
  l := ColumnLeftPx(ACol);
  w := ColumnWidthPx(ACol);
  { 漏斗贴在这一段的**尾缘**,排序三角占掉的那一格之前。写在段自己的
    阅读空间里再反射回来 —— 于是"尾缘在哪一边"只回答一次。 }
  sec := ToReadingRect(Rect(l, 0, l + w, 0));
  { ToReadingX 在这里当"阅读 -> 屏幕"用:反射是对合,两个方向是同一个函数。
    绘制盒(±5x±4)与命中盒(±7)围绕的是**同一个** cx,所以无论反射差不差
    半个像素,两者恒同心 —— 这正是把它收口成一个函数要保证的东西。 }
  Result := ToReadingX(sec.Right - ScaleI(10) - HeaderSortGlyphW(ACol));
end;

function TTyCustomGrid.HeaderFilterRect(ACol, AHeaderH: Integer): TRect;
var
  w, cx, cy: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if not ShowsFilterButton(ACol) then Exit;
  w := ColumnWidthPx(ACol);
  if w <= 0 then Exit;
  { 圆心走 HeaderFunnelCenterX —— **绘制端读的是同一个函数**。
    从前这里写 `l + w - 10 - gs`,而 RenderHeaderSections 写 `r.Right - 10 - gs`:
    两条独立的表达式,靠 `r.Right = l + w` 恰好相等。LTR 下永远看不出来,
    换边时只要有一处漏改就是"漏斗画在一头、点在另一头"。 }
  cx := HeaderFunnelCenterX(ACol);
  cy := AHeaderH div 2;
  Result := Rect(cx - ScaleI(7), cy - ScaleI(7), cx + ScaleI(7), cy + ScaleI(7));
end;

function TTyCustomGrid.HeaderImageList: TCustomImageList;
begin
  Result := FHeader.Images;
  if Result = nil then Result := FImages;
end;

procedure TTyCustomGrid.RenderHeaderSections(P: TTyPainter; const M: TTyGridMetrics;
  AHeaderH: Integer);
var
  i, l, w, cx, cy, gs, imgIdx, imgSz, imgPad, bandTop: Integer;
  rr, imgR: TRect;   { rr = 本段在阅读空间里的矩形;见循环体开头 }
  hdrBg: TTyFill;
  hdrHasBg: Boolean;
  hdrInk, accentInk, funnelInk: TTyColor;
  hdrFontName: string;
  hdrFontSize, hdrFontWeight: Integer;
  col: TTyColumn;
  imgList: TCustomImageList;
  secS, hdrS, actHdrS, hotS, pushS: TTyStyleSet;
  hotTrack, pushed: Boolean;
  ink: TTyColor;
  r, textR: TRect;
  line: TBGRAPixel;
begin
  { **`tysActive` 必须从这两趟里剔掉。** CurrentStates 是**整个控件**的状态:鼠标在
    表格里任何地方按下去,控件就带上 tysActive。列头带和列头段是 chrome,不是按钮 ——
    "用户正在这张表上按着鼠标"不等于"这一段被按下去了"。

    不剔的话,新加的 TyGridHeaderSection:active 规则会从这里漏进来:随便点一下正文,
    整条列头带的每一段都换底,而且 goHeaderPushedLook 关着也照样发生。按下去的观感
    **只有一个来源** —— 下面那趟按 FPressedHeaderCol 逐段判定、且由标志把门的解析。
    (加这条规则之前 :active 不存在,所以剔掉它对既有主题逐像素无影响。) }
  hdrS := ActiveController.Model.ResolveStyle('TyGridHeader', StyleClass,
    CurrentStates - [tysActive]);
  secS := ActiveController.Model.ResolveStyle('TyGridHeaderSection', StyleClass,
    CurrentStates - [tysActive]);
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

  { 鼠标底下那一段要不要点亮 —— hoHotTrack。这个标志一直是 published 的
    (TTyHeader.Options),而网格从来没读过它:用户在对象查看器里勾上它,
    列头一点反应都没有,于是整条列头看起来根本不像能点。
    (TTyTreeView 早就认这个标志了,网格一直漏着。)

    悬停样式**在循环外解析一次**:每段各解析一遍会把逐格样式那套记忆化带来的
    好处在列头上全赔掉。没在 hot-track 或者鼠标不在列头上时一次都不解析。 }
  hotTrack := (hoHotTrack in FHeader.Options) and (FHoverHeaderCol >= 0);
  if hotTrack then
    hotS := ActiveController.Model.ResolveStyle('TyGridHeaderSection',
      StyleClass, [tysHover]);

  { 按下去的那一段 —— goHeaderPushedLook。这个标志从前**没有进枚举**,理由写在
    docs/controls/grid.md 的对照表里:主题当时没有 TyGridHeaderSection:active,
    按下态解析出来会退回 base 的 `background: none`,与静止态一模一样 ——
    发布一个控件不照办的标志正是这一轮要清掉的缺陷类。规则补上了(themes/light.tycss),
    这里才是接线的地方。
    与 hotS 同样**在循环外解析一次**:每段各解析一遍会把逐格记忆化的好处全赔掉。 }
  pushed := (goHeaderPushedLook in Options) and (FPressedHeaderCol >= 0);
  if pushed then
    pushS := ActiveController.Model.ResolveStyle('TyGridHeaderSection',
      StyleClass, [tysActive]);

  imgList := HeaderImageList;

  { 列头带**在分组带之下**。没有分组时 bandTop = 0,与从前逐像素一致。 }
  bandTop := GroupBandHeightPx;

  for i := 0 to FHeader.Columns.Count - 1 do
  begin
    col := FHeader.Columns.Items[i];
    if not (coVisible in col.Options) then Continue;
    l := ColumnLeftPx(i);
    w := ColumnWidthPx(i);
    if (w <= 0) or (l >= M.ClientW) or (l + w <= 0) then Continue;
    { 正文列滚到冻结带底下的那一截不该露出来 —— 与单元格同一条裁剪规则。
      三个渲染器(这里、分组小计、页脚)从前各写一遍;RTL 下"被盖住的是哪一侧"
      跟着换边,三份里漏一份就是一条画反的裁剪。收口在 ClipColToBody。 }
    if not ClipColToBody(M, i, l, w) then Continue;

    r := Rect(l, bandTop, l + w, bandTop + AHeaderH);

    { 表头格自绘钩子:必填列标红、当前排序列高亮。
      从主题解析出来的值打底,宿主想改哪个改哪个。 }
    hdrBg := secS.Background;
    hdrHasBg := tpBackground in secS.Present;
    hdrInk := ink;
    { 鼠标底下那一段用 :hover 的那份。主题没给 hover 背景就退回普通那份 ——
      与本单元其余"皮肤没写就优雅退化"的地方同一条规矩。宿主钩子在后面,
      仍然压得过它。 }
    if hotTrack and (i = FHoverHeaderCol) then
    begin
      if (tpBackground in hotS.Present) and (hotS.Background.Kind <> tfkNone) then
      begin
        hdrBg := hotS.Background;
        hdrHasBg := True;
      end;
      if tpTextColor in hotS.Present then hdrInk := hotS.TextColor;
    end;
    { 按住的那一段压过 hover:鼠标当然还停在它上面,但"按下去"是更强的状态。
      顺序即优先级 —— 这一段必须在 hover 之后、宿主钩子之前。 }
    if pushed and (i = FPressedHeaderCol) then
    begin
      if (tpBackground in pushS.Present) and (pushS.Background.Kind <> tfkNone) then
      begin
        hdrBg := pushS.Background;
        hdrHasBg := True;
      end;
      if tpTextColor in pushS.Present then hdrInk := pushS.TextColor;
    end;
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

    { 这一段自己的**阅读空间**矩形。图标 / 标题 / 漏斗 / 排序徽标 / 排序三角
      五个槽位全部在它里面算,最后各自反射回屏幕 —— 一处定方向,五个槽一起换边。 }
    rr := ToReadingRect(r);

    { 排序列留出字形的位置,标题文字缩进一点。走 HeaderSortGlyphW ——
      HeaderFunnelCenterX 读的是同一个函数,不再各算一遍。 }
    gs := HeaderSortGlyphW(i);
    imgPad := 0;

    { 列头图标必须**先画、先累加 imgPad**,下面算 textR 时标题才让得出位。
      原先这一段在 textR 之后,于是 imgPad 恒为 0、标题不缩进,
      图标直接压在标题左端的字上。
      (当初那条测试只数"表头带里有没有红像素",图标画在字**上面**照样满足 ——
      测试对"压字"是瞎的。现在改成同时看标题墨的左右两端。) }
    imgIdx := col.ImageIndex;
    if (imgList <> nil) and (imgIdx >= 0) then
    begin
      imgSz := ScaleI(16);
      if imgSz > AHeaderH - ScaleI(4) then imgSz := AHeaderH - ScaleI(4);
      if imgSz > 0 then
      begin
        if imgIdx < TyImageCount(imgList) then
        begin
          { 图标贴在段的**起点**那一侧,与标题同侧。两分支同一条路。 }
          imgR := ToScreenRect(Rect(rr.Left + ScaleI(4), 0,
            rr.Left + ScaleI(4) + imgSz, 0));
          TyBlitImage(P.Bitmap, imgList, imgIdx,
            imgR.Left, bandTop + (AHeaderH - imgSz) div 2, imgSz, P.Scale(96), False);
          Inc(imgPad, imgSz + ScaleI(4));
        end;
      end;
    end;

    textR := ToScreenRect(Rect(rr.Left + ScaleI(6) + imgPad, r.Top,
      rr.Right - ScaleI(4) - gs, r.Bottom));
    if (col.Text <> '') and (textR.Right > textR.Left) then
      { 换行时不省略号截断 —— 两者一起开的话第二行永远画不出来。
        (B6 勾了"换行绘制(表头格同享)",但表头走的 P.DrawText
         没有 wordwrap 参数,于是那半句一直没落地。) }
      if FHeaderWordWrap then
        { 走网格自己的 DrawCellText —— 它已经支持换行且带文字缓存,
          在画笔上另造一个 wrapped 变体是重复第二条实现。 }
        DrawCellText(P, textR, col.Text, hdrFontName, hdrFontSize,
          hdrFontWeight, hdrInk, col.CaptionAlignment, tlCenter, True)
      else
        P.DrawText(textR, col.Text, hdrFontName, hdrFontSize,
          hdrFontWeight, hdrInk, col.CaptionAlignment, tlCenter, True);

    { 该列有筛选时,标题右侧留一个漏斗位(用向下箭头示意)。
      **正在过滤的列要点亮** —— 用户得一眼看出哪列在过滤中,
      否则"为什么少了几行"会变成一次排查。 }
    if ShowsFilterButton(i) then
    begin
      { **命中读的是同一个 HeaderFunnelCenterX**(HeaderFilterRect)。
        从前这里和那里各写一个式子,靠 `r.Right = l + w` 恰好相等。 }
      cx := HeaderFunnelCenterX(i);
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
      textR := ToScreenRect(Rect(rr.Right - ScaleI(24), r.Top,
        rr.Right - ScaleI(14), r.Bottom));
      if textR.Right > textR.Left then
        P.DrawText(textR, IntToStr(SortRankOf(i)), hdrFontName,
          hdrFontSize - 2, hdrFontWeight, hdrInk, taCenter, tlCenter, False);
    end;

    { 排序方向的小三角。 }
    if gs > 0 then
    begin
      cx := ToReadingX(rr.Right - ScaleI(10));   { 反射自逆,见 HeaderFunnelCenterX }
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

{ 整表背景图。范围只影响**铺到哪个矩形**,不影响铺法 ——
  两件事分开,免得 3 种铺法 x 2 种范围写成 6 个分支。 }
procedure TTyCustomGrid.RenderBackgroundBitmap(P: TTyPainter;
  const M: TTyGridMetrics; const R: TRect);
var
  area, dst, oldClip: TRect;
  x, y, bw, bh: Integer;
begin
  if FBackgroundBitmap = nil then Exit;
  bw := FBackgroundBitmap.Width;
  bh := FBackgroundBitmap.Height;
  if (bw <= 0) or (bh <= 0) then Exit;

  area := R;
  if FBackgroundScope = gbsBodyOnly then
  begin
    { 正文窗格 = 除去列头/分组带/筛选行(上)与底部冻结带(下)。
      左边的行号槽/冻结列不减 —— 那些仍是"正文"的一部分。 }
    area.Top := M.FrozenTop;
    area.Bottom := M.ClientH - M.FrozenBottom;
  end;
  if (area.Right <= area.Left) or (area.Bottom <= area.Top) then Exit;

  oldClip := P.Bitmap.ClipRect;
  { 与外层裁剪**求交**,不覆盖 —— 快路径下外层夹着那条露出来的带。 }
  if not IntersectRect(dst, oldClip, area) then Exit;
  P.Bitmap.ClipRect := dst;
  try
    case FBackgroundMode of
      gbmStretch:
        P.Bitmap.StretchPutImage(area, FBackgroundBitmap, dmDrawWithTransparency);
      gbmCenter:
        begin
          dst := Rect(0, 0, bw, bh);
          OffsetRect(dst, (area.Left + area.Right - bw) div 2,
                          (area.Top + area.Bottom - bh) div 2);
          P.Bitmap.PutImage(dst.Left, dst.Top, FBackgroundBitmap,
            dmDrawWithTransparency);
        end;
      else
        begin
          y := area.Top;
          while y < area.Bottom do
          begin
            x := area.Left;
            while x < area.Right do
            begin
              P.Bitmap.PutImage(x, y, FBackgroundBitmap, dmDrawWithTransparency);
              Inc(x, bw);
            end;
            Inc(y, bh);
          end;
        end;
    end;
  finally
    P.Bitmap.ClipRect := oldClip;
  end;
end;

procedure TTyCustomGrid.RenderChrome(P: TTyPainter; const M: TTyGridMetrics);
var
  headerH, indW, bandH, ind0, ind1: Integer;
  fixR: TRect;
begin
  headerH := 0;
  if hoVisible in FHeader.Options then
    headerH := HeaderHeightPx + GroupBandHeightPx;
  { 行头槽与固定列区要从**整条表头区之下**开始 —— 筛选行也在表头这一侧,
    不减掉它的话行头槽会从筛选行底下钻上来。 }
  bandH := headerH + FilterRowHeightPx;

  { 次序 = 遮挡次序,且必须与 CellAt 的判定次序一致,否则"看到的"和"点到的"会错位。
    先画下层的行头槽与固定列,最后让列头带横跨整幅盖上去(含左上角)。 }

  { 行头槽:列头之下、阅读起点那一条(RTL 下在右)。位置走 IndicatorBandX ——
    与 CellAt / RowDividerAtY / MouseDown 的拖行手势读的是同一个来源。 }
  indW := 0;
  if FShowIndicator then indW := ScaleI(FIndicatorWidth);
  if IndicatorBandX(ind0, ind1) then
  begin
    FillRegion(P, Rect(ind0, bandH, ind1, M.ClientH), 'TyGridIndicator');
    RenderRowNumbers(P, M, bandH, ind0, ind1);
  end;

  { 固定列区:行头槽之后到冻结带尾缘。这一句写在**阅读空间**里
    (`[行头槽宽, 冻结带宽)` 与方向无关)再整条反射 —— 于是它必定与行头槽同侧,
    不会一块在左一块在右。写成 `Rect(indW, .., M.FrozenLeft, ..)` 就做不到:
    M.FrozenLeft 在 RTL 下装的是**右**冻结列。 }
  fixR := ToScreenRect(Rect(indW, bandH, FrozenWidthPx, M.ClientH));
  if fixR.Right > fixR.Left then FillRegion(P, fixR, 'TyGridFixed');

  { 列头带:横跨整幅宽度,盖住左上角 —— 与 CellAt 里"列头优先"一致。 }
  if headerH > 0 then
  begin
    FillRegion(P, Rect(0, 0, M.ClientW, headerH), 'TyGridHeader');
    { 分组带先画(在上),列头带画在它下面。 }
    RenderHeaderGroups(P, M);
    RenderHeaderSections(P, M, HeaderHeightPx);
  end;

  { 内嵌筛选行:紧贴列头之下,同样横跨整幅宽度。 }
  if FilterRowHeightPx > 0 then
    RenderFilterRow(P, M, headerH);
end;

procedure TTyCustomGrid.RenderCells(P: TTyPainter; const M: TTyGridMetrics;
  const AFrame: TTyStyleSet);
begin
  { 基类不画内容:它不知道数据从哪来。TTyDrawGrid / TTyStringGrid 改写。 }
end;

function TTyCustomGrid.FilterRowText(ACol: Integer): string;
begin
  Result := '';      { 基类没有过滤模型 }
end;

function TTyCustomGrid.NodeLevelOf(ARow: Integer): Integer;
begin
  Result := 0;
  if (FTreeColumn < 0) or (ARow < 0) then Exit;
  if Assigned(FOnGetNodeLevel) then FOnGetNodeLevel(Self, ARow, Result);
  if Result < 0 then Result := 0;
end;

function TTyCustomGrid.NodeHasChildren(ARow: Integer): Boolean;
begin
  Result := False;
  if (FTreeColumn < 0) or (ARow < 0) then Exit;
  if Assigned(FOnGetHasChildren) then FOnGetHasChildren(Self, ARow, Result);
end;

function TTyCustomGrid.NodeCollapsedOf(ARow: Integer): Boolean;
begin
  Result := False;
end;

function TTyCustomGrid.TreeContentLeft(ACol, ARow: Integer): Integer;
begin
  Result := 0;
  if (FTreeColumn < 0) or (ACol <> FTreeColumn) then Exit;
  { 每一级缩进一格,再给三角留出一格宽 —— 有没有孩子都留,
    否则同级的兄弟会因为"有没有孩子"而左右错开。 }
  Result := (NodeLevelOf(ARow) + 1) * ScaleI(FTreeIndent);
end;

function TTyCustomGrid.TreeToggleRect(ARow: Integer): TRect;
var
  cell, cellR: TRect;
  ind, sz, cx, cy: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if FTreeColumn < 0 then Exit;
  if not NodeHasChildren(ARow) then Exit;      { 没孩子就没有三角可点 }

  cell := CellVisibleRect(FTreeColumn, ARow);
  if IsRectEmpty(cell) then Exit;

  ind := ScaleI(FTreeIndent);
  sz := ind;
  if sz > cell.Bottom - cell.Top then sz := cell.Bottom - cell.Top;
  { 三角落在**它这一级的缩进槽**里 —— 也就是内容起点往回那一格。
    格子内部先在**格子自己的阅读空间**里算(cellR),最后整块反射回屏幕:
    缩进方向、三角、以及 RenderCells 里 `Inc(textR.Left, TreeContentLeft)`
    那一步于是同时换向,不会出现"缩进往右、三角在左"。
    绘制与命中读的都是这一个矩形,所以换边时点击面一定跟着。 }
  cellR := ToReadingRect(cell);
  cx := cellR.Left + NodeLevelOf(ARow) * ind;
  cy := cell.Top + ((cell.Bottom - cell.Top) - sz) div 2;
  Result := Rect(cx, cy, cx + sz, cy + sz);
  if Result.Right > cellR.Right then Result.Right := cellR.Right;
  if Result.Right <= Result.Left then Exit(Rect(0, 0, 0, 0));
  Result := ToScreenRect(Result);
end;

procedure TTyCustomGrid.DrawToggleGlyph(P: TTyPainter; const ARect: TRect;
  ACollapsed: Boolean; AColor: TTyColor);
begin
  { pad=1:小槽里 DrawGlyph 默认每边内缩 4 逻辑像素会只剩个糊点。 }
  if not ACollapsed then
    TyDrawGlyph(P, ActiveController, ARect, tgChevronDown, AColor, 1, 1)
  else if RtlLayout then
    { 令牌显式写出 —— 与 CheckBox/CheckComboBox 的勾选框同一种写法。皮肤要能替换
      这一向,和它能替换其余每一个 glyph 一样;而 tyControls.Base 里那张
      kind→token 派生表还没有收录它,这里就不去赌它收录了没有。 }
    TyDrawGlyph(P, ActiveController, ARect, '--glyph-chevron-left', tgChevronLeft, AColor, 1, 1)
  else
    TyDrawGlyph(P, ActiveController, ARect, tgChevronRight, AColor, 1, 1);
end;

procedure TTyCustomGrid.SetTreeColumn(AValue: Integer);
begin
  if AValue < -1 then AValue := -1;
  if FTreeColumn = AValue then Exit;
  FTreeColumn := AValue;
  InvalidateGridOrder;      { 折叠会改变显示序 }
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyCustomGrid.SetTreeIndent(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FTreeIndent = AValue then Exit;
  FTreeIndent := AValue;
  Invalidate;
end;

procedure TTyCustomGrid.RenderFilterRow(P: TTyPainter; const M: TTyGridMetrics;
  ATop: Integer);
var
  fs: TTyStyleSet;
  i, l, w, h: Integer;
  col: TTyColumn;
  r, inner: TRect;
  txt: string;
  ink: TTyColor;
begin
  h := FilterRowHeightPx;
  if h <= 0 then Exit;

  fs := ActiveController.Model.ResolveStyle('TyGridFilterRow', StyleClass, []);

  { 整条带先铺底 —— 与列头带一样横跨整幅宽度(含行头槽上方那一块)。 }
  r := Rect(0, ATop, M.ClientW, ATop + h);
  if (tpBackground in fs.Present) and (fs.Background.Kind <> tfkNone) then
    P.FillBackground(r, fs.Background, 0);

  if tpTextColor in fs.Present then ink := fs.TextColor
  else ink := CurrentStyle.TextColor;

  for i := 0 to FHeader.Columns.Count - 1 do
  begin
    col := TTyColumn(FHeader.Columns.Items[i]);
    if not (coVisible in col.Options) then Continue;
    l := ColumnLeftPx(i);
    w := ColumnWidthPx(i);
    if w <= 0 then Continue;
    if (l >= M.ClientW) or (l + w <= 0) then Continue;

    { 每列一个输入位。内缩一点,让它看起来是个可以打字的框而不是一格表头。 }
    inner := Rect(l + 2, ATop + 2, l + w - 2, ATop + h - 2);
    if inner.Right <= inner.Left then Continue;
    if tpBorderColor in fs.Present then
      P.StrokeBorder(inner, 0, 1, fs.BorderColor);

    txt := FilterRowText(i);
    if txt = '' then Continue;
    DrawCellText(P, Rect(inner.Left + 4, inner.Top, inner.Right - 4, inner.Bottom),
      txt, fs.FontName, ResolveFontSize(fs), fs.FontWeight,
      ink, taLeftJustify, tlCenter);
  end;
end;

procedure TTyCustomGrid.RenderHeaderGroups(P: TTyPainter; const M: TTyGridMetrics);
var
  i, l, r0, h, lvlH, lastCol: Integer;
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

  lvlH := ScaleI(FGroupHeaderHeight);
  for i := 0 to FHeaderGroups.Count - 1 do
  begin
    g := TTyGridHeaderGroup(FHeaderGroups.Items[i]);
    { 每一级画在自己那一条里(0 级最上)。从前这里是
      `if g.Level <> 0 then Continue` —— 非零级直接被丢掉。 }
    if (g.Level < 0) or (g.Level >= GroupLevelCount) then Continue;
    if (g.FirstCol < 0) or (g.FirstCol >= FHeader.Columns.Count) then Continue;

    { 跨列 = 首列与末列的并集。列宽/拖动重排都自动跟着走,
      因为两端都取自 ColumnLeftPx —— 列轴的唯一出处。
      走 ColumnSpanX 而不是 `首列左缘 .. 末列右缘`:RTL 下首列在右,
      后者是一个反向矩形,整条分组带一个像素都画不出来。 }
    if g.LastCol < FHeader.Columns.Count then
      lastCol := g.LastCol
    else
      lastCol := FHeader.Columns.Count - 1;
    if not ColumnSpanX(g.FirstCol, lastCol, l, r0) then Continue;

    rc := Rect(l, g.Level * lvlH, r0, (g.Level + 1) * lvlH);
    if tpBackground in secS.Present then
      P.FillBackground(rc, secS.Background, 0);
    if g.Text <> '' then
      P.DrawText(Rect(rc.Left + ScaleI(4), rc.Top, rc.Right - ScaleI(4), rc.Bottom),
        g.Text, hdrS.FontName, ResolveFontSize(hdrS), hdrS.FontWeight, ink,
        g.Alignment, tlCenter, True);
    if rc.Right - 1 < M.ClientW then
      P.Bitmap.DrawLine(rc.Right - 1, rc.Top, rc.Right - 1, rc.Bottom, line, False);
    { 级与级之间也要有分隔,否则两级看起来是一整块。 }
    if rc.Bottom < h then
      P.Bitmap.DrawLine(rc.Left, rc.Bottom - 1, rc.Right, rc.Bottom - 1, line, False);
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
      { 分组行不是数据行(它的"数据行号"是负数),它有自己的渲染路径。
        不挡的话宿主的钩子每帧都会收到 ARow = -1, -2 …,
        而按行号索引自己的数据正是这个钩子最正常的用法 —— 于是在**绘制里**崩。 }
      if dataRow < 0 then Continue;

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
      if dataRow < 0 then Continue;     { 分组行:见 RenderCellBorders 里的说明 }
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
    { 最后一个参数是这一帧的镜像开关(phase 0 的约定)。它只做一件事:
      把每一次 DrawText 的水平对齐过一遍 BidiFlipAlignment。
      网格的每一个文字矩形都是由已经镜像过的列/单元格矩形派生出来的,
      所以在这里翻对齐是对的 —— 反过来,凡是自己切好槽位又不镜像槽位的调用方
      都不能这么翻(那正是 phase 0 否掉"无条件翻"的理由)。 }
    P.BeginPaintOn(ACanvas, ARect, APPI, FSurface, RtlLayout);

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
    canFast := (fastDy <> 0)
               and (M.ClientH - M.FrozenBottom - bodyTop > Abs(fastDy));
    if canFast then
    begin
      Inc(FFastScrollFrames);
      { 平移带的下沿是**正文窗格**的下沿,不是视口下沿 ——
        底部冻结带不随滚动,搬了它就会跟着一起跑。 }
      ShiftSurfaceRows(bodyTop, M.ClientH - M.FrozenBottom, fastDy);
      if fastDy > 0 then
        band := Rect(0, M.ClientH - M.FrozenBottom - fastDy, M.ClientW,
                     M.ClientH - M.FrozenBottom)
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
      if band.Bottom > M.ClientH - M.FrozenBottom then
        band.Bottom := M.ClientH - M.FrozenBottom;
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

    { 背景图铺在本体底色**之上**、任何内容之下。 }
    RenderBackgroundBitmap(P, M, R);

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
  if Result <= 0 then Result := GetDefaultRowHeight;
end;

procedure TTyCustomGrid.DrawInRowBand(P: TTyPainter; APos: Integer;
  const M: TTyGridMetrics; ADraw: TTyGridBandDraw);
var
  oldClip, clip: TRect;
begin
  if not Assigned(ADraw) then Exit;
  oldClip := P.Bitmap.ClipRect;
  { **求交**而不是覆盖 —— 外层可能是脏区重画限定的那条横带,覆盖掉它就会
    在带外重画一遍:同一段文字叠两次、抗锯齿变深。 }
  if not IntersectRect(clip, oldClip, TyGridRowBandRect(APos, M)) then Exit;
  P.Bitmap.ClipRect := clip;
  try
    ADraw();
  finally
    P.Bitmap.ClipRect := oldClip;
  end;
end;

procedure TTyCustomGrid.DrawInPane(P: TTyPainter; APane: TTyGridPane;
  const M: TTyGridMetrics; ADraw: TTyGridBandDraw);
var
  oldClip, clip: TRect;
begin
  if not Assigned(ADraw) then Exit;
  oldClip := P.Bitmap.ClipRect;
  if not IntersectRect(clip, oldClip, TyGridPaneRect(M, APane)) then Exit;
  P.Bitmap.ClipRect := clip;
  try
    ADraw();
  finally
    P.Bitmap.ClipRect := oldClip;
  end;
end;

function TTyCustomGrid.RowHeightOfDisplay(APos: Integer): Integer;
var
  d: Integer;
begin
  d := DisplayToData(APos);
  if d < 0 then Result := GetDefaultRowHeight    { 分组行 / 越界 }
  else Result := RowHeightOf(d);
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
  Result.FrozenTop  := FrozenHeightPx;
  Result.FrozenBottom := FrozenBottomPx;
  { **两条竖冻结带在 RTL 下换边。** 几何层的字段名说的是"屏幕的左/右",而
    FrozenWidthPx 说的是"阅读起点那一侧"(行头槽 + 左固定列)—— 镜像之后
    那一侧是屏幕的右。在这里换一次,九宫格、窗格裁剪、正文带边界全部跟着走;
    唯一还要一起换的是 CellPane 答的窗格名(gpLeft <-> gpRight),
    只换一处就会出现"格子画在右带、裁剪按左带"的空矩形。 }
  if RtlLayout then
  begin
    Result.FrozenLeft  := FrozenRightPx;
    Result.FrozenRight := FrozenWidthPx;
  end
  else
  begin
    Result.FrozenLeft  := FrozenWidthPx;
    Result.FrozenRight := FrozenRightPx;
  end;
  Result.GridLineWidth := GridLineWidthPx;
  Result.RowH := ScaleI(GetDefaultRowHeight);
  Result.RowCount := DisplayRowCount;
  Result.RowTops := RowTops;
  Result.FixedRows := FFixedRows;
  Result.FixedRowsBottom := FFixedRowsBottom;
  { 列头带。有分组时是两条(分组带在上、列头带在下),否则一条。
    B2 把 HeaderH 拆成 HeaderBands 数组,就是为了这里。 }
  if hoVisible in FHeader.Options then
  begin
    { 自上而下堆:分组带 → 列头带 → 筛选行。三者都在上冻结带里,
      都不随滚动。HeaderBands 是数组正是为了这个 —— 加一条带就是多一项。 }
    if (GroupBandHeightPx > 0) and (FilterRowHeightPx > 0) then
      Result.HeaderBands := TTyIntArray.Create(
        GroupBandHeightPx, HeaderHeightPx, FilterRowHeightPx)
    else if GroupBandHeightPx > 0 then
      Result.HeaderBands := TTyIntArray.Create(GroupBandHeightPx, HeaderHeightPx)
    else if FilterRowHeightPx > 0 then
      Result.HeaderBands := TTyIntArray.Create(HeaderHeightPx, FilterRowHeightPx)
    else
      Result.HeaderBands := TTyIntArray.Create(HeaderHeightPx);
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

function TTyDrawGrid.DisplayCellText(ACol, ARow: Integer): string;
begin
  Result := GetCellText(ACol, ARow);
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
  cell, vis, textR, oldClip, treeTg: TRect;
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

      txt := DisplayCellText(colIdx, dataRow);
      if txt = '' then Continue;

      { 先让开格线(线压在边界上、两侧各一半),再上左右内边距。
        线宽 <= 1 时 TyGridCellContentRect 是恒等的,与从前逐像素一致。 }
      ap := CellAppearance(colIdx, dataRow, row, AFrame);
      cell := TyGridCellContentRect(CellRect(colIdx, dataRow), M);
      { 内边距与缩进都在**格子的阅读空间**里加,最后整块反射回屏幕。
        padL/padR 是主题给的左右内边距,RTL 下"起点那一侧"是右 ——
        直接写 `cell.Left + padL` 会让非对称内边距翻个个儿。 }
      textR := ToReadingRect(cell);
      textR := Rect(textR.Left + padL, cell.Top, textR.Right - padR, cell.Bottom);
      { 树形列:文字为缩进和三角让位。缩进只推**起点**边界,不改另一端 ——
        深层节点的文字该被截断就截断,不该反过来把列撑宽。 }
      if (FTreeColumn >= 0) and (colIdx = FTreeColumn) then
        Inc(textR.Left, TreeContentLeft(colIdx, dataRow));
      textR := ToScreenRect(textR);
      if (FTreeColumn >= 0) and (colIdx = FTreeColumn) then
      begin
        treeTg := TreeToggleRect(dataRow);
        if not IsRectEmpty(treeTg) then
        begin
          { 展开时朝下、折叠时朝阅读前进的方向 —— 与分组行的三角同一个约定,
            也确实是同一个函数(见 DrawToggleGlyph)。 }
          DrawToggleGlyph(P, treeTg, NodeCollapsedOf(dataRow), ap.TextColor);
        end;
      end;
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
  FTreeCollapsed := TStringList.Create;
  FFilterText := TStringList.Create;
  FColFilters := TStringList.Create;
  FValFilters := TStringList.Create;
  FAggregates := TStringList.Create;
  FCollapsed := TStringList.Create;
  FAttrs := TTyGridCellAttrStore.Create;
  { 撤销的记录点。挂在存储上而不是挂在每个功能上 —— 收口一处、漏不掉。 }
  FAttrs.OnChanging := @HandleAttrChanging;
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
  { 默认 rsmMulti = 从前的行为(离散多选一直无条件开着)。见属性声明处
    为什么这里刻意不跟 LCL 的 rsmSingle 默认值。 }
  FRangeSelectMode := rsmMulti;
  FModified := False;
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
  SetLength(FGroupCols, 0);
  FFilterCol := -1;
  FShowFilterButtons := False;
  FShowGroupSubtotals := True;
  FFilterAllValues := TStringList.Create;
  FFilterChecked := TStringList.Create;
  FFilterChecked.Sorted := True;
  FFilterChecked.Duplicates := dupIgnore;
  FTreeColumn := -1;        { 默认不画树 }
  FTreeIndent := 16;
  FDefaultCellDisplay := gcdText;

  { 一个复用的内联编辑器,盖在被编辑的单元格上。 }
  FEditor := TTyEdit.Create(Self);
  FEditor.Parent := Self;
  FEditor.Visible := False;
  FEditor.ControlStyle := FEditor.ControlStyle + [csNoDesignVisible];
  FEditor.OnKeyDown := @EditorKeyDown;
  FEditor.OnChange := @EditorTextChanged;
  FEditor.OnKeyPress := @EditorKeyPress;
  FEditor.OnExit := @EditorExit;

  { 筛选行的编辑器。独立于上面那个 —— 见字段处的说明。
    csNoDesignVisible:内部子控件不能泄漏进 IDE 设计器(v2.1.1 踩过)。 }
  FFilterEditCol := -1;
  FFilterEditor := TTyEdit.Create(Self);
  FFilterEditor.Parent := Self;
  FFilterEditor.Visible := False;
  FFilterEditor.ControlStyle := FFilterEditor.ControlStyle + [csNoDesignVisible];
  FFilterEditor.OnChange := @FilterEditorChange;
  FFilterEditor.OnKeyDown := @FilterEditorKeyDown;
  FFilterEditor.OnExit := @FilterEditorExit;

  FFilterTimer := TTimer.Create(Self);
  FFilterTimer.Enabled := False;
  FFilterTimer.Interval := 300;      { 防抖:停手约三百毫秒才真的去筛 }
  FFilterTimer.OnTimer := @FilterDebounceTick;

  { 以下几个都是把库里**现成的控件**接进来当编辑器 —— 网格只负责摆位置、
    灌值、取值,不重造轮子。生命周期规则与文本编辑器一致。 }
  FSpinEditor := TTySpinEdit.Create(Self);
  FSpinEditor.Parent := Self;
  FSpinEditor.Visible := False;
  FSpinEditor.ControlStyle := FSpinEditor.ControlStyle + [csNoDesignVisible];
  FSpinEditor.OnKeyDown := @EditorCancelKeyDown;
  FSpinEditor.OnExit := @EditorExit;

  FSliderEditor := TTyTrackBar.Create(Self);
  FSliderEditor.Parent := Self;
  FSliderEditor.Visible := False;
  FSliderEditor.ControlStyle := FSliderEditor.ControlStyle + [csNoDesignVisible];
  FSliderEditor.OnKeyDown := @EditorCancelKeyDown;
  FSliderEditor.OnExit := @EditorExit;

  FMemoEditor := TTyMemo.Create(Self);
  FMemoEditor.Parent := Self;
  FMemoEditor.Visible := False;
  FMemoEditor.ControlStyle := FMemoEditor.ControlStyle + [csNoDesignVisible];
  FMemoEditor.OnKeyDown := @EditorCancelKeyDown;
  FMemoEditor.OnExit := @EditorExit;

  FCalcEditor := TTyCalcEdit.Create(Self);
  FCalcEditor.Parent := Self;
  FCalcEditor.Visible := False;
  FCalcEditor.ControlStyle := FCalcEditor.ControlStyle + [csNoDesignVisible];
  FCalcEditor.OnKeyDown := @EditorCancelKeyDown;
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
  FPickEditor.OnKeyDown := @PickEditorKeyDown;
  FPickEditor.OnChange := @PickEditorChange;
  FPickEditor.OnExit := @PickEditorExit;

  { 第三个复用编辑器:日期选择器。 }
  FDateEditor := TTyDateTimePicker.Create(Self);
  FDateEditor.Parent := Self;
  FDateEditor.Visible := False;
  FDateEditor.ControlStyle := FDateEditor.ControlStyle + [csNoDesignVisible];
  FDateEditor.OnKeyDown := @EditorCancelKeyDown;
  FDateEditor.OnExit := @DateEditorExit;
end;

destructor TTyStringGrid.Destroy;
begin
  { 先摘回调,别在半毁对象上回调。**每一个**编辑器都要摘:漏掉的那几个
    (spin/slider/memo/calc/mask)的 OnExit 仍指着 EditorExit,焦点恰好在它们
    身上时会把 EndEdit(True) 打进一个已经拆了一半的网格。 }
  FEditor.OnKeyDown := nil;
  FEditor.OnChange := nil;
  FEditor.OnKeyPress := nil;
  FEditor.OnExit := nil;
  FSpinEditor.OnKeyDown := nil;   FSpinEditor.OnExit := nil;
  FSliderEditor.OnKeyDown := nil; FSliderEditor.OnExit := nil;
  FMemoEditor.OnKeyDown := nil;   FMemoEditor.OnExit := nil;
  FCalcEditor.OnKeyDown := nil;   FCalcEditor.OnExit := nil;
  FMaskEditor.OnKeyDown := nil;   FMaskEditor.OnExit := nil;
  FPickEditor.OnKeyDown := nil;
  FPickEditor.OnChange := nil;
  FPickEditor.OnExit := nil;
  FDateEditor.OnKeyDown := nil;
  FDateEditor.OnExit := nil;
  FFilterEditor.OnKeyDown := nil;
  FFilterEditor.OnChange := nil;
  FFilterEditor.OnExit := nil;
  FCells.Free;
  FTreeCollapsed.Free;
  FFilterText.Free;
  FColFilters.Free;
  FValFilters.Free;
  FAggregates.Free;
  FCollapsed.Free;
  FAttrs.Free;
  { 视图对象归网格所有(OwnsObjects),交给宿主的引用随网格一起失效 ——
    与 LCL 的 MapFree 同一条所有权(grids.pas:11324)。 }
  FColViews.Free;
  FRowViews.Free;
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

procedure TTyStringGrid.SetUndoLimit(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FUndoLimit = AValue then Exit;
  FUndoLimit := AValue;
  if FUndoLimit = 0 then ClearUndo;
end;

function TTyStringGrid.UndoCount: Integer;
begin
  Result := Length(FUndoStack);
end;

function TTyStringGrid.CanUndo: Boolean;
begin
  Result := Length(FUndoStack) > 0;
end;

function TTyStringGrid.CanRedo: Boolean;
begin
  Result := Length(FRedoStack) > 0;
end;

procedure TTyStringGrid.ClearUndo;
begin
  SetLength(FUndoStack, 0);
  SetLength(FRedoStack, 0);
  SetLength(FUndoOpen, 0);
  FUndoOverflow := False;
end;

procedure TTyStringGrid.PushUndoStep(const AStep: TTyGridUndoStep);
var
  i, n: Integer;
begin
  if Length(AStep) = 0 then Exit;
  n := Length(FUndoStack);
  SetLength(FUndoStack, n + 1);
  FUndoStack[n] := AStep;
  { 超过上限丢**最老**的那条 —— 丢最新的等于用户刚做的操作撤不了,更违反直觉。 }
  if (FUndoLimit > 0) and (Length(FUndoStack) > FUndoLimit) then
  begin
    for i := 0 to Length(FUndoStack) - 2 do
      FUndoStack[i] := FUndoStack[i + 1];
    SetLength(FUndoStack, Length(FUndoStack) - 1);
  end;
end;

procedure TTyStringGrid.PermuteRowState(const AMap: array of Integer);
var
  heights: array of record R, H: Integer; end;
  hidden: array of Integer;
  i, n, dst: Integer;
begin
  { 先把两张表都快照下来再动手 —— 边搬边写会覆盖尚未搬走的条目
    (与 ShiftCells 里那条"增时从大到小搬"是同一个道理)。 }
  SetLength(heights, 0);
  n := 0;
  for i := 0 to High(AMap) do
    if GetRowHeights(i) > 0 then
    begin
      SetLength(heights, n + 1);
      heights[n].R := i;
      heights[n].H := GetRowHeights(i);
      Inc(n);
    end;

  SetLength(hidden, 0);
  n := 0;
  for i := 0 to High(AMap) do
    if IsHiddenRow(i) then
    begin
      SetLength(hidden, n + 1);
      hidden[n] := i;
      Inc(n);
    end;

  { 行高走 SetRowHeights,不直接改表 —— 撤销的记录点在那儿。 }
  for i := 0 to High(heights) do
    SetRowHeights(heights[i].R, 0);
  for i := 0 to High(heights) do
  begin
    dst := AMap[heights[i].R];
    if dst >= 0 then SetRowHeights(dst, heights[i].H);
  end;

  if Length(hidden) > 0 then
  begin
    { 走 SetRowHidden 而不是直接改表 —— 记录点在那儿。
      直接 Clear 再 Add 的话,拖完行按 Ctrl+Z 文字回来了、
      藏着的还是换过去那一行(A7 的同一个缺陷换个位置)。 }
    for i := 0 to High(hidden) do
      SetRowHidden(hidden[i], False);
    for i := 0 to High(hidden) do
    begin
      dst := AMap[hidden[i]];
      if dst >= 0 then SetRowHidden(dst, True);
    end;
    InvalidateOrder;      { 显示序变了 }
  end;
end;

function TTyStringGrid.SnapshotColumn(ACol: Integer): TTyGridColumnSnapshot;
var
  c: TTyGridColumn;
  b: TTyColumn;
  k: string;
begin
  Result := Default(TTyGridColumnSnapshot);
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  b := TTyColumn(Header.Columns.Items[ACol]);

  Result.Index := ACol;
  Result.Width := b.Width;
  Result.MinWidth := b.MinWidth;
  Result.MaxWidth := b.MaxWidth;
  Result.Position := b.Position;
  Result.Alignment := b.Alignment;
  Result.CaptionAlignment := b.CaptionAlignment;
  Result.Text := b.Text;
  Result.ImageIndex := b.ImageIndex;
  Result.Options := b.Options;
  Result.Tag := b.Tag;

  if b is TTyGridColumn then
  begin
    c := TTyGridColumn(b);
    Result.EditorKind := c.EditorKind;
    Result.UseEditorKind := c.UseEditorKind;
    Result.ReadOnly := c.ReadOnly;
    if c.PickList <> nil then Result.PickList := c.PickList.Text;
    Result.Aggregate := c.Aggregate;
    Result.ValidChars := c.ValidChars;
    Result.MaxEditLength := c.MaxEditLength;
    Result.SortKind := c.SortKind;
    Result.MinValue := c.MinValue;
    Result.MaxValue := c.MaxValue;
    Result.EditMask := c.EditMask;
    Result.CharCase := c.CharCase;
    Result.DropDownWidth := c.DropDownWidth;
  end;

  { 那一列上的旁挂状态也是它身份的一部分 —— 列回来了而筛选没回来,
    等于回到一个从未存在过的状态。 }
  k := IntToStr(ACol);
  Result.FilterExpr := FFilterText.Values[k];
  Result.ColFilter := FColFilters.Values[k];
  Result.ValFilter := FValFilters.Values[k];
end;

procedure TTyStringGrid.ApplyColumnSnapshot(ACol: Integer;
  const ASnap: TTyGridColumnSnapshot);
var
  c: TTyGridColumn;
  b: TTyColumn;
  k: string;

  procedure PutKeyed(AList: TStringList; const AValue: string);
  var
    i: Integer;
  begin
    i := AList.IndexOfName(k);
    if i >= 0 then AList.Delete(i);
    if AValue <> '' then AList.Add(k + '=' + AValue);
  end;

begin
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  b := TTyColumn(Header.Columns.Items[ACol]);

  b.Width := ASnap.Width;
  b.MinWidth := ASnap.MinWidth;
  b.MaxWidth := ASnap.MaxWidth;
  b.Alignment := ASnap.Alignment;
  b.CaptionAlignment := ASnap.CaptionAlignment;
  b.Text := ASnap.Text;
  b.ImageIndex := ASnap.ImageIndex;
  b.Options := ASnap.Options;
  b.Tag := ASnap.Tag;

  if b is TTyGridColumn then
  begin
    c := TTyGridColumn(b);
    c.EditorKind := ASnap.EditorKind;
    c.UseEditorKind := ASnap.UseEditorKind;
    c.ReadOnly := ASnap.ReadOnly;
    if c.PickList <> nil then c.PickList.Text := ASnap.PickList;
    c.Aggregate := ASnap.Aggregate;
    c.ValidChars := ASnap.ValidChars;
    c.MaxEditLength := ASnap.MaxEditLength;
    c.SortKind := ASnap.SortKind;
    c.MinValue := ASnap.MinValue;
    c.MaxValue := ASnap.MaxValue;
    c.EditMask := ASnap.EditMask;
    c.CharCase := ASnap.CharCase;
    c.DropDownWidth := ASnap.DropDownWidth;
  end;

  k := IntToStr(ACol);
  PutKeyed(FFilterText, ASnap.FilterExpr);
  PutKeyed(FColFilters, ASnap.ColFilter);
  PutKeyed(FValFilters, ASnap.ValFilter);
  InvalidateOrder;
end;

procedure TTyStringGrid.RecordColumnUndo(AKind: TTyGridUndoKind; ACol: Integer;
  ATo: Integer);
var
  empty: TTyGridColumnSnapshot;
begin
  empty := Default(TTyGridColumnSnapshot);
  RecordColumnUndo(AKind, ACol, ATo, empty);
end;

procedure TTyStringGrid.RecordColumnUndo(AKind: TTyGridUndoKind; ACol: Integer;
  ATo: Integer; const ASnap: TTyGridColumnSnapshot);
var
  e: TTyGridUndoEntry;
begin
  if FUndoBusy or (FUndoLimit = 0) then Exit;
  e := Default(TTyGridUndoEntry);
  e.Kind := AKind;
  e.Col := ACol;
  e.OldCount := ATo;                    { gukColMove 用它当"到哪儿" }
  e.ColSnap := ASnap;
  RecordUndo(e);
end;

procedure TTyStringGrid.GrowMergesSpanningRow(AFromIndex, ADelta: Integer);
var
  keys: TStringList;
  i, sep, r: Integer;
  a: TTyGridCellAttr;
begin
  if (ADelta = 0) or FAttrs.IsEmpty then Exit;
  keys := TStringList.Create;
  try
    FAttrs.SnapshotKeys(keys);
    for i := 0 to keys.Count - 1 do
    begin
      a := FAttrs.Find(keys[i]);
      if (a = nil) or (a.RowSpan <= 1) then Continue;

      sep := Pos(':', keys[i]);
      r := StrToIntDef(Copy(keys[i], sep + 1, MaxInt), -1);
      if r < 0 then Continue;

      { 这里读到的 r 已经是**搬迁之后**的基准行:插入点在基准行之前时
        基准格自己被搬走了,块整体平移、跨度不变;只有插入点落在
        基准行**之后、块尾之内**时,块才被穿过。 }
      if AFromIndex <= r then Continue;
      if AFromIndex > r + a.RowSpan - 1 then Continue;

      a := FAttrs.Mutate(keys[i]);        { 走记录点 }
      Inc(a.RowSpan, ADelta);
      if a.RowSpan < 1 then a.RowSpan := 1;
      if a.RowSpan > FMaxRowSpan then FMaxRowSpan := a.RowSpan;
      if (a.ColSpan <= 1) and (a.RowSpan <= 1) then
      begin
        Dec(FMergeCount);                 { 缩没了就不再是合并区 }
        if FMergeCount < 0 then FMergeCount := 0;
      end;
      FAttrs.DropIfDefault(keys[i]);
    end;
  finally
    keys.Free;
  end;
end;

procedure TTyStringGrid.ShiftRowStateWithUndo(AFromIndex, ADelta: Integer);
var
  heights: array of record R, H: Integer; end;
  hidden: array of Integer;
  i, n, dst, hi: Integer;

  { 平移后的新下标;-1 = 这一条随着被删的行一起没了。 }
  function Shifted(ARow: Integer): Integer;
  begin
    Result := ARow;
    if ARow < AFromIndex then Exit;
    if (ADelta < 0) and (ARow = AFromIndex) then Exit(-1);
    Inc(Result, ADelta);
    if Result < 0 then Result := -1;
  end;

begin
  if ADelta = 0 then Exit;

  { 先全部快照再动手 —— 边搬边写会覆盖尚未搬走的条目。
    上界取**旧的** RowCount 那一段:ShiftCells 跑在 RowCount 改变之前。 }
  hi := RowCount;
  if ADelta < 0 then Inc(hi, -ADelta);      { 删除时旧表可能还有更靠后的条目 }

  SetLength(heights, 0);
  n := 0;
  for i := 0 to hi do
    if GetRowHeights(i) > 0 then
    begin
      SetLength(heights, n + 1);
      heights[n].R := i;
      heights[n].H := GetRowHeights(i);
      Inc(n);
    end;

  SetLength(hidden, 0);
  n := 0;
  for i := 0 to hi do
    if IsHiddenRow(i) then
    begin
      SetLength(hidden, n + 1);
      hidden[n] := i;
      Inc(n);
    end;

  { 清掉再按新位置写回 —— 两趟都走记录点。 }
  for i := 0 to High(heights) do
    SetRowHeights(heights[i].R, 0);
  for i := 0 to High(heights) do
  begin
    dst := Shifted(heights[i].R);
    if dst >= 0 then SetRowHeights(dst, heights[i].H);
  end;

  for i := 0 to High(hidden) do
    SetRowHidden(hidden[i], False);
  for i := 0 to High(hidden) do
  begin
    dst := Shifted(hidden[i]);
    if dst >= 0 then SetRowHidden(dst, True);
  end;
end;

function TTyStringGrid.SnapshotAttr(const AKey: string): TTyGridAttrSnapshot;
var
  a: TTyGridCellAttr;
begin
  Result := Default(TTyGridAttrSnapshot);
  a := FAttrs.Find(AKey);
  if a = nil then Exit;              { Present 留 False = "当时没有这一条" }
  Result.Present := True;
  Result.ColSpan := a.ColSpan;
  Result.RowSpan := a.RowSpan;
  Result.HasBackground := a.HasBackground;
  Result.Background := a.Background;
  Result.HasTextColor := a.HasTextColor;
  Result.TextColor := a.TextColor;
  Result.HasAlignment := a.HasAlignment;
  Result.Alignment := a.Alignment;
  Result.HasFontStyle := a.HasFontStyle;
  Result.FontStyle := a.FontStyle;
  Result.ReadOnly := a.ReadOnly;
  Result.HasCellDisplay := a.HasCellDisplay;
  Result.CellDisplay := a.CellDisplay;
  Result.Comment := a.Comment;
end;

procedure TTyStringGrid.RestoreAttr(const AKey: string;
  const ASnap: TTyGridAttrSnapshot);
var
  a: TTyGridCellAttr;
  wasMerged, nowMerged: Boolean;
begin
  a := FAttrs.Find(AKey);
  wasMerged := (a <> nil) and ((a.ColSpan > 1) or (a.RowSpan > 1));
  nowMerged := ASnap.Present and ((ASnap.ColSpan > 1) or (ASnap.RowSpan > 1));

  if not ASnap.Present then
  begin
    { "当时根本没有这一条"从前是整条删掉来还原的 —— 而那会把**后来**挂上去的
      Obj 一起删掉,而 Obj 不在撤销模型里(见 TTyGridAttrSnapshot):撤销既不
      恢复它,就更不该销毁它。留一个只剩 Obj 的空壳条目,语义上与"没有这一条"
      等价 —— IsDefault 只多认一个 Obj,其余查询读到的都是默认值。 }
    a := FAttrs.Find(AKey);
    if (a <> nil) and (a.Obj <> nil) then
      a.ResetKeepingObject
    else
      FAttrs.Remove(AKey);
  end
  else
  begin
    a := FAttrs.Ensure(AKey);
    if a = nil then Exit;
    a.ColSpan := ASnap.ColSpan;
    a.RowSpan := ASnap.RowSpan;
    a.HasBackground := ASnap.HasBackground;
    a.Background := ASnap.Background;
    a.HasTextColor := ASnap.HasTextColor;
    a.TextColor := ASnap.TextColor;
    a.HasAlignment := ASnap.HasAlignment;
    a.Alignment := ASnap.Alignment;
    a.HasFontStyle := ASnap.HasFontStyle;
    a.FontStyle := ASnap.FontStyle;
    a.ReadOnly := ASnap.ReadOnly;
    a.HasCellDisplay := ASnap.HasCellDisplay;
    a.CellDisplay := ASnap.CellDisplay;
    a.Comment := ASnap.Comment;
    { 跨度提示只增不减 —— 恢复出一个更大的跨度时得让回扫够得着它,
      否则 BaseCellOf 扫不到基准格,合并区就散了。 }
    if ASnap.ColSpan > FMaxColSpan then FMaxColSpan := ASnap.ColSpan;
    if ASnap.RowSpan > FMaxRowSpan then FMaxRowSpan := ASnap.RowSpan;
  end;

  { 合并计数是旁挂的汇总,不在属性对象里 —— 恢复属性时得跟着对账,
    否则 HasMergedCells 会与实际的跨度对不上。 }
  if nowMerged and not wasMerged then Inc(FMergeCount)
  else if wasMerged and not nowMerged then Dec(FMergeCount);
  if FMergeCount < 0 then FMergeCount := 0;
end;

procedure TTyStringGrid.TrimRowStateTo(ANewCount: Integer);
var
  i, r: Integer;
  doomed: array of Integer;
begin
  inherited TrimRowStateTo(ANewCount);    { 行高 }

  SetLength(doomed, 0);
  for i := 0 to FHiddenRows.Count - 1 do
  begin
    r := StrToIntDef(FHiddenRows[i], -1);
    if r >= ANewCount then
    begin
      SetLength(doomed, Length(doomed) + 1);
      doomed[High(doomed)] := r;
    end;
  end;
  for i := 0 to High(doomed) do
    SetRowHidden(doomed[i], False);       { 走记录点 → 可撤销 }
end;

procedure TTyStringGrid.SetRowHidden(ARow: Integer; AHidden: Boolean);
var
  i: Integer;
  e: TTyGridUndoEntry;
  k: string;
begin
  { 只挡负数。**不挡上界** —— 增删行时这里会短暂地写到"即将存在"的那一行
    (ShiftCells 跑在 RowCount 改变之前),按当时的 RowCount 挡掉的话
    标记就丢了。公开入口 HideRow 自己有边界检查。 }
  if ARow < 0 then Exit;
  k := IntToStr(ARow);
  i := FHiddenRows.IndexOf(k);
  if (i >= 0) = AHidden then Exit;      { 已经是这个状态 —— 不是一次改动 }

  if (not FUndoBusy) and (FUndoLimit <> 0) then
  begin
    e := Default(TTyGridUndoEntry);
    e.Kind := gukRowHidden;
    e.Row := ARow;
    e.OldHidden := i >= 0;
    RecordUndo(e);
  end;

  if AHidden then FHiddenRows.Add(k) else FHiddenRows.Delete(i);
  { 藏/放一行就改变了参与显示的行集合 —— 显示序、行高前缀和、汇总统统失效。
    **放在这里**而不是放在调用方:撤销走的是 ApplyUndoStep,它够不着
    HideRow/UnHideRow 里那一句。(批量期间只置标志,EndUpdateOrder 统一重建。) }
  InvalidateOrder;
end;

procedure TTyStringGrid.HandleAttrChanging(const AKey: string);
var
  e: TTyGridUndoEntry;
begin
  if FUndoBusy or (FUndoLimit = 0) then Exit;
  e := Default(TTyGridUndoEntry);
  e.Kind := gukCellAttr;
  e.AttrKey := AKey;
  e.Attr := SnapshotAttr(AKey);
  RecordUndo(e);
end;

procedure TTyStringGrid.SetRowHeights(ARow, AValue: Integer);
var
  old: Integer;
  e: TTyGridUndoEntry;
begin
  old := GetRowHeights(ARow);
  inherited SetRowHeights(ARow, AValue);
  if FUndoBusy or (FUndoLimit = 0) then Exit;
  { 拿**钳制之后**的实际值比 —— 撞上 MinRowHeight/MaxRowHeight 时
    什么都没变,别往栈里塞一条按下去没反应的记录。 }
  if GetRowHeights(ARow) = old then Exit;
  e := Default(TTyGridUndoEntry);
  e.Kind := gukRowHeight;
  e.Row := ARow;
  e.OldHeight := old;
  RecordUndo(e);
end;

procedure TTyStringGrid.RecordUndo(const AEntry: TTyGridUndoEntry);
var
  n: Integer;
  step: TTyGridUndoStep;
begin
  if FUndoBusy or (FUndoLimit = 0) then Exit;

  { 一条记录攒得过大(比如往十万行里灌数据)—— 与其留一条**残缺**的记录,
    不如整条作废并清空栈:半条撤销记录还原出来的是一张四不像的表,
    比"这一步撤销不了"危险得多。 }
  if FUndoDepth > 0 then
  begin
    if FUndoOverflow then Exit;
    if Length(FUndoOpen) >= 200000 then
    begin
      { **别调 ClearUndo** —— 它顺手把 FUndoOverflow 清成 False,于是这条
        "本条作废"的标志自己把自己抹掉:后面的条目继续往 FUndoOpen 里攒,
        CloseUndoGroup 时 `if not FUndoOverflow` 成立,**正好把那半条残缺记录
        推进了栈**,设计要防的事照样发生。清栈的三行在这里内联。 }
      SetLength(FUndoOpen, 0);
      SetLength(FUndoStack, 0);
      SetLength(FRedoStack, 0);
      FUndoOverflow := True;      { 必须在清栈**之后**置位 }
      Exit;
    end;
    n := Length(FUndoOpen);
    SetLength(FUndoOpen, n + 1);
    FUndoOpen[n] := AEntry;
    Exit;
  end;

  { 不在事务里:自成一条(单格编辑走的就是这条路)。 }
  SetLength(step, 1);
  step[0] := AEntry;
  PushUndoStep(step);
  SetLength(FRedoStack, 0);     { 新操作让重做链作废 —— 与所有编辑器一致 }
end;

{ 逆着放回去。返回的是"反记录":把当前值记下来,于是重做就是再逆一次。
  条目要**倒着**走 —— 同一格被改过多次时,最早那次才是真正的原值。 }
function TTyStringGrid.ApplyUndoStep(const AStep: TTyGridUndoStep): TTyGridUndoStep;
var
  i, n: Integer;
  e: TTyGridUndoEntry;
begin
  SetLength(Result, Length(AStep));
  n := 0;
  for i := Length(AStep) - 1 downto 0 do
  begin
    e := AStep[i];
    case e.Kind of
      gukCell:
        begin
          Result[n].Kind := gukCell;
          Result[n].Col := e.Col;
          Result[n].Row := e.Row;
          Result[n].OldText := GetCells(e.Col, e.Row);
          Cells[e.Col, e.Row] := e.OldText;
        end;
      gukRowCount:
        begin
          Result[n].Kind := gukRowCount;
          Result[n].OldCount := RowCount;
          RowCount := e.OldCount;
        end;
      gukCellAttr:
        begin
          Result[n].Kind := gukCellAttr;
          Result[n].AttrKey := e.AttrKey;
          Result[n].Attr := SnapshotAttr(e.AttrKey);
          RestoreAttr(e.AttrKey, e.Attr);
        end;
      gukRowHeight:
        begin
          Result[n].Kind := gukRowHeight;
          Result[n].Row := e.Row;
          Result[n].OldHeight := GetRowHeights(e.Row);
          SetRowHeights(e.Row, e.OldHeight);
        end;
      gukRowHidden:
        begin
          Result[n].Kind := gukRowHidden;
          Result[n].Row := e.Row;
          Result[n].OldHidden := IsHiddenRow(e.Row);
          SetRowHidden(e.Row, e.OldHidden);
        end;
      { --- 列结构。三种互为对方的反记录,所以重做自然成立。 --- }
      gukColDelete:
        begin
          { 撤销"删列" = 把它插回去并还原它的全部身份。
            反记录是"插列",于是重做会把它再删掉。 }
          Result[n].Kind := gukColInsert;
          Result[n].Col := e.Col;
          InsertColumn(e.Col);
          ApplyColumnSnapshot(e.Col, e.ColSnap);
        end;
      gukColInsert:
        begin
          { 撤销"插列" = 删掉它。反记录带上它此刻的样子,重做才插得回来。 }
          Result[n].Kind := gukColDelete;
          Result[n].Col := e.Col;
          Result[n].ColSnap := SnapshotColumn(e.Col);
          DeleteColumn(e.Col);
        end;
      gukColMove:
        begin
          { 撤销"换位" = 反着换回来。 }
          Result[n].Kind := gukColMove;
          Result[n].Col := e.OldCount;
          Result[n].OldCount := e.Col;
          MoveColumn(e.OldCount, e.Col);
        end;
    end;
    Inc(n);
  end;
  { 反记录也要倒着存,这样重做时再倒一次就回到原顺序。 }
end;

procedure TTyStringGrid.Undo;
var
  n: Integer;
  inv: TTyGridUndoStep;
begin
  if not CanUndo then Exit;
  FUndoBusy := True;
  BeginUpdate;
  try
    n := Length(FUndoStack) - 1;
    inv := ApplyUndoStep(FUndoStack[n]);
    SetLength(FUndoStack, n);
    n := Length(FRedoStack);
    SetLength(FRedoStack, n + 1);
    FRedoStack[n] := inv;
  finally
    EndUpdate;
    FUndoBusy := False;
  end;
end;

procedure TTyStringGrid.Redo;
var
  n: Integer;
  inv: TTyGridUndoStep;
begin
  if not CanRedo then Exit;
  FUndoBusy := True;
  BeginUpdate;
  try
    n := Length(FRedoStack) - 1;
    inv := ApplyUndoStep(FRedoStack[n]);
    SetLength(FRedoStack, n);
    PushUndoStep(inv);
  finally
    EndUpdate;
    FUndoBusy := False;
  end;
end;

procedure TTyStringGrid.SetCells(ACol, ARow: Integer; const AValue: string);
var
  k: string;
  e: TTyGridUndoEntry;
begin
  k := CellKey(ACol, ARow);
  { 脏标记挂在这个收口点上 —— 编辑提交、粘贴、填充柄、勾选框、撤销/重做、
    行列增删搬格子,统统经过这里(与撤销的记录点是同一处口子)。
    只在值**真的**变了时置位:重复写同一个值不算改过。 }
  if GetCells(ACol, ARow) <> AValue then FModified := True;
  if not FUndoBusy then
  begin
    e.Kind := gukCell;
    e.Col := ACol;
    e.Row := ARow;
    e.OldText := GetCells(ACol, ARow);
    e.OldCount := 0;
    if e.OldText <> AValue then RecordUndo(e);
  end;
  if AValue = '' then
  begin
    FCells.Delete(k)                  { 写空串 = 删除条目,稀疏存储不为空值留位置 }
  end
  else
    FCells.Items[k] := AValue;        { 已存在则覆写,不存在则新增 }
  { 数据变了 → 汇总要重算。挂在这个收口点上,于是编辑、粘贴、填充、
    行置换、撤销全都自动失效 —— 与撤销的记录点是同一处口子。 }
  InvalidateAggregates;
  Invalidate;
end;

procedure TTyStringGrid.ClearRowContents(AFrom, ACount: Integer);
var
  r, c: Integer;
begin
  if ACount <= 0 then Exit;
  if AFrom < 0 then AFrom := 0;
  if AFrom >= RowCount then Exit;
  if AFrom + ACount > RowCount then ACount := RowCount - AFrom;

  BeginUpdate;                { 整批一条撤销记录 }
  try
    for r := AFrom to AFrom + ACount - 1 do
      for c := 0 to Header.Columns.Count - 1 do
        Cells[c, r] := '';
  finally
    EndUpdate;
  end;
end;

procedure TTyStringGrid.ClearColContents(AFrom, ACount: Integer);
var
  r, c: Integer;
begin
  if ACount <= 0 then Exit;
  if AFrom < 0 then AFrom := 0;
  if AFrom >= Header.Columns.Count then Exit;
  if AFrom + ACount > Header.Columns.Count then
    ACount := Header.Columns.Count - AFrom;

  BeginUpdate;
  try
    for c := AFrom to AFrom + ACount - 1 do
      for r := 0 to RowCount - 1 do
        Cells[c, r] := '';
  finally
    EndUpdate;
  end;
end;

function TTyStringGrid.ClearRows: Boolean;
begin
  Result := RowCount > 0;
  if not Result then Exit;          { already empty -- LCL answers False here too }
  EndEdit(False);                   { an editor open over a row that is about to vanish }
  BeginUpdate;                      { structure + content = ONE undo record }
  try
    ClearCells;                     { see the declaration: sparse storage would resurrect }
    FixedRows := 0;                 { frozen counts describe rows that no longer exist }
    FixedRowsBottom := 0;
    RowCount := 0;
  finally
    EndUpdate;
  end;
  { The cursor and the selection addressed rows that are gone. Park them at the origin
    rather than leaving Row pointing past the end -- MoveCursor is not used because it
    would ask OnSelectCell about a cell that does not exist. }
  FRow := 0;
  ClearSelection;
end;

function TTyStringGrid.ClearCols: Boolean;
begin
  Result := Header.Columns.Count > 0;
  if not Result then Exit;
  EndEdit(False);
  BeginUpdate;
  try
    ClearCells;
    { Sort keys and filters name columns by index; with no columns left every one of
      them dangles, and the display order would be rebuilt against them on the next
      paint. Drop them with the columns they refer to. }
    ClearSortColumns;
    ClearFilters;
    FixedCols := 0;
    FixedColsRight := 0;
    Header.Columns.Clear;
  finally
    EndUpdate;
  end;
  FCol := 0;
  ClearSelection;
  InvalidateColumnCache;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.Clear;
begin
  { LCL 的 body(grids.pas:10302)就是这两句。包一层 BeginUpdate,于是整表清空
    算**一条**撤销记录而不是两条 —— 与本单元其余批量操作同一条纪律。 }
  BeginUpdate;
  try
    ClearRows;
    ClearCols;
  finally
    EndUpdate;
  end;
end;

procedure TTyStringGrid.ClearCells;
var
  keys: TStringList;
  i, sep, c, r: Integer;
  e: TTyGridUndoEntry;
begin
  { 从前这里直接 `FCells.Clear` —— 绕过 SetCells 那个记录点,于是清空不可撤销,
    连带**导入 CSV**整件事也撤不回来(导入的第一步就是清空)。
    收口点保证的只是**经过它的**改动:绕过去就什么都不剩。

    做法是"先逐条记原值,再整表清掉",而不是逐格走 Cells[] ——
    记下的东西一模一样,但省掉了逐格拆字典的开销。
    条数超上限时 RecordUndo 自己会整条作废并清栈(既有的溢出保护)。 }
  if (not FUndoBusy) and (FUndoLimit <> 0) then
  begin
    BeginUpdate;                { 整个清空 = 一条记录 }
    try
      keys := TStringList.Create;
      try
        SnapshotCellKeys(keys);
        for i := 0 to keys.Count - 1 do
        begin
          sep := Pos(':', keys[i]);
          c := StrToIntDef(Copy(keys[i], 1, sep - 1), -1);
          r := StrToIntDef(Copy(keys[i], sep + 1, MaxInt), -1);
          if (c < 0) or (r < 0) then Continue;
          e := Default(TTyGridUndoEntry);
          e.Kind := gukCell;
          e.Col := c;
          e.Row := r;
          e.OldText := GetCells(c, r);
          RecordUndo(e);
        end;
      finally
        keys.Free;
      end;
      FCells.Clear;
    finally
      EndUpdate;
    end;
  end
  else
    FCells.Clear;

  { 数据没了 → 汇总也得重算。SetCells 上挂的那处失效同样够不着这里。 }
  InvalidateAggregates;
  Invalidate;
end;

{ 把"写过的格"的键快照到 ADest。顺序不定 —— 两个调用方都不关心顺序
  (ShiftCells 自己按数值重排,AutoFitColumnWidth 只是扫一遍)。 }
procedure TTyStringGrid.CollectKey(Item: string; const Key: string;
  var AContinue: Boolean);
begin
  if FKeySink <> nil then FKeySink.Add(Key);
  AContinue := True;
end;

procedure TTyStringGrid.SnapshotCellKeys(ADest: TStrings);
begin
  FKeySink := ADest;
  try
    FCells.Iterate(@CollectKey);
  finally
    FKeySink := nil;
  end;
end;

function TTyStringGrid.StoredCellCount: Integer;
begin
  Result := FCells.Count;
end;

function TTyStringGrid.StoredCellAttrCount: Integer;
begin
  Result := FAttrs.Count;
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

  { 光标要动了 —— 先把正在编辑的格提交掉,否则编辑框会悬在旧位置。
    提交被校验拦下就**不动**:FCol/FRow 保持原样,这正是 OnSelectCell 否决时
    调用方早已在读的那个"没动"信号(BeginEdit 靠它退出)。 }
  if FEditing and not TryEndEdit(True) then Exit;

  canSel := True;
  if Assigned(FOnSelectCell) then FOnSelectCell(Self, ACol, ARow, canSel);
  if not canSel then Exit;

  FCol := ACol;
  FRow := ARow;

  { **光标一动,选区锚点就跟着走** —— 除非正在 Shift 扩选。

    从前重锚这件事散落在 MouseDown / KeyDown / FindAndSelect / ClearSelection
    四个调用点上各写一遍,MoveCursor 自己不管。于是任何**没走这四条路**的移动
    (上移/下移、跳转、直接赋 Row/Col)都留下一个陈旧锚点,选区从旧位置一路
    拉到新位置 —— 用户看到的是"上移一下,莫名多选了一格"。
    收口在这里之后,漏掉是不可能的:要拉长必须显式声明在扩选。 }
  if not FExtendingSelection then AnchorSelection;

  { 光标走到哪,视口跟到哪 —— 除非这一次是被 goDontScrollPartCell 摁住的点击。 }
  if not FSuppressScrollIntoView then ScrollIntoView(FCol, FRow);
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

  { 填充柄优先于一切:它压在选区右下角那一格上,不先判它就会被当成
    "在那一格上按下"而重置选区。 }
  if (Button = mbLeft) and PtInRect(FillHandleRect, Point(X, Y)) then
  begin
    FFillDragging := True;
    FFillToCol := FCol;
    FFillToRow := FRow;
    Exit;
  end;

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
  if GetGroupCol >= 0 then
  begin
    gPos := TyGridRowAt(Y, GridMetrics);
    if (gPos >= 0) and IsGroupRow(gPos, gIdx) then
    begin
      ToggleGroup(gIdx);
      Exit;
    end;
  end;

  hit := CellAt(X, Y);
  { 树形三角优先于单元格 —— 它压在树形列那一格的左侧,
    不先判就会被当成"在那一格上按下"而只是移动光标。
    命中用的就是绘制用的那个矩形(TreeToggleRect),两者不可能分叉。 }
  if (Button = mbLeft) and (TreeColumn >= 0) and (hit.Part = ghpCell)
     and PtInRect(TreeToggleRect(hit.Row), Point(X, Y)) then
  begin
    ToggleNode(hit.Row);
    Exit;
  end;
  { 点筛选行 = 在那一列的筛选位里开编辑器。 }
  if (hit.Part = ghpFilterRow) and (hit.Col >= 0) then
  begin
    BeginFilterEdit(hit.Col);
    Exit;
  end;
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

    { 链接:点一下发事件,然后**照常往下走** —— 链接格也是格子,
      点了该选中、该拿到焦点。Exit 掉的话点链接会让选区停在别处。 }
    if (CellDisplayFor(hit.Col, hit.Row) = gcdHyperlink)
       and Assigned(FOnCellLinkClick) then
      FOnCellLinkClick(Self, hit.Col, hit.Row);

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

    FExtendingSelection := (ssShift in Shift) and (goRangeSelect in Options);
    { goDontScrollPartCell:半露的格被点中时不把它滚进来。
      闸只罩住**这一次** MoveCursor —— 键盘导航仍然要滚,LCL 的这个标志
      管的也只是点击。 }
    FSuppressScrollIntoView := goDontScrollPartCell in Options;
    try
      MoveCursor(hit.Col, hit.Row);
    finally
      FExtendingSelection := False;
      FSuppressScrollIntoView := False;
    end;
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
  { 松开才真正填 —— 拖的过程里只记目标。 }
  if FFillDragging then
  begin
    FFillDragging := False;
    FillFromSelectionTo(FFillToCol, FFillToRow);
    Exit;
  end;

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

  if not TypeIntoCell(Key) then Exit;
  Key := #0;
end;

function TTyStringGrid.TypeIntoCell(const AChar: string): Boolean;
begin
  Result := BeginEdit;
  if not Result then Exit;
  { 这一笔就是新内容的第一个字符 —— 覆盖原值,与 Excel 一致。 }
  if FEditor.Visible then
  begin
    FEditor.Text := AChar;
    FEditor.MaxLength := MaxEditLengthFor(FCol, FRow);
    { AChar 按约定就是**一个**字符,所以光标位置是 1 —— TTyEdit 的 SelStart 数的是
      码点不是字节,一个汉字在这里同样只算 1。 }
    FEditor.SelStart := 1;
  end;
end;

procedure TTyStringGrid.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  vc: string;
begin
  inherited UTF8KeyPress(UTF8Key);
  { 单字节留给 KeyPress —— 那条路上的吞键语义(Key := #0)这里给不出来,
    而且两条都跑一遍会开两次编辑。 }
  if Length(UTF8Key) <= 1 then Exit;
  if not Enabled then Exit;
  if FEditing then Exit;              { 编辑器自己收键 }
  if EditorKindFor(FCol, FRow) in [gekNone, gekCheckBox] then Exit;
  { ValidChars 是一串**字符**,所以用整字去找:一个汉字要么整个在里面,要么不在。
    逐字节找会把汉字的某个字节当成 ASCII 命中。 }
  vc := ValidCharsFor(FCol, FRow);
  if (vc <> '') and (Pos(string(UTF8Key), vc) = 0) then Exit;
  TypeIntoCell(UTF8Key);
end;

{ 按住 Shift 的导航键是**扩选**:锚点不动,选区从锚点拉到新光标。
  其余情况一律由 MoveCursor 自己重锚(选区退化成一格)——
  从前这里在末尾补一句 AnchorSelection,而它只覆盖导航键这一小撮;
  程序化移动光标压根走不到这儿,锚点就陈旧了。收口到 MoveCursor 之后,
  这里只需要声明"这一次是扩选"。 }
procedure TTyStringGrid.KeyDown(var Key: Word; Shift: TShiftState);
var
  navKey: Word;
begin
  { Key 会在下面被置 0(表示已消费),所以想知道"按的是哪个键"必须先存一份。 }
  navKey := Key;
  inherited KeyDown(Key, Shift);
  if not Enabled then Exit;

  { 只有**导航键 + Shift** 才算扩选。Ctrl+A / Ctrl+C / Ctrl+V 都不该动锚点
    (Ctrl+A 尤其:从前末尾那句无差别的 AnchorSelection 会把刚拉满的选区
     立刻收回成一格,全选看上去完全没反应)。 }
  FExtendingSelection := (ssShift in Shift) and (goRangeSelect in Options)
    and (navKey in [VK_LEFT, VK_RIGHT,
    VK_UP, VK_DOWN, VK_HOME, VK_END, VK_PRIOR, VK_NEXT]);
  try

  case Key of
    { 左/右在这里是**布局方向**,不是文字方向 —— 网格里方向键跟着眼睛走,
      所以 RTL 下它们对调(镜像范围文档 §6.3 第 4 条画的正是这条线:
      文本编辑里的左右归 BiDi 层管,列表/网格/标签页/菜单里的归镜像层管)。
      Home/End 不翻:它们是**逻辑**首尾,答的恒是第一/最后一列
      (RTL 下第一列在屏幕右边,Home 仍然去那里)。
      选区锚点与角落也不翻:它们存的是列**下标**,和像素无关。 }
    { The backstop for abandoning an edit. Every editor now cancels on Esc itself, but a
      HOST editor supplied through OnCreateEditLink is the grid's guest and carries no such
      wiring -- when focus is on the grid rather than inside that guest, this is the way out. }
    VK_ESCAPE: if FEditing then begin EndEdit(False); Key := 0; end;
    VK_LEFT:  begin MoveCursor(FCol + ArrowColStep(-1), FRow); Key := 0; end;
    VK_RIGHT: begin MoveCursor(FCol + ArrowColStep(1), FRow); Key := 0; end;
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
                 { **非编辑态**才把回车交给宿主。编辑态的回车仍旧是
                   "提交并下移" —— 那条手感不能被这个钩子改掉。 }
                 if not FEditing then
                 begin
                   if (ssCtrl in Shift) and Assigned(FOnCtrlReturn) then
                   begin
                     FOnCtrlReturn(Self, FCol, FRow);
                     Key := 0;
                     Exit;
                   end;
                   if (not (ssCtrl in Shift)) and Assigned(FOnReturn) then
                   begin
                     FOnReturn(Self, FCol, FRow);
                     Key := 0;
                     Exit;
                   end;
                 end;
                 if FEditing and not TryEndEdit(True) then begin Key := 0; Exit; end;
                 MoveCursor(FCol, FRow + 1);
                 Key := 0;
               end;
    { Tab = 按**格**推进,到行尾折到下一行行首。
      不拦的话 Tab 会把焦点整个弹出网格 —— 表格里这是最让人措手不及的一下。 }
    VK_TAB:   begin
                { goTabs 关掉 = 把 Tab 还给对话框。**不置 Key := 0** 才是关键:
                  LCL 靠 Key 还在不在来决定要不要换焦点,吞掉它就等于
                  "关了也还是不放行"。外面是 try..finally,直接 Exit 安全。 }
                if not (goTabs in Options) then Exit;
                if FEditing and not TryEndEdit(True) then begin Key := 0; Exit; end;
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
    { 手势层从前接了 C/V/Z/Y/A,唯独漏了 X —— CutToClipboard 方法早就在
      (ReadOnly 退化为复制),但键盘上按 Ctrl+X 一直无声。修饰键跟自己库的
      C/V 同规(Ctrl);LCL 的网格绑的是 Shift+X(grids.pas:7815-7817,
      它家 C/V 都用 ssModifier,X 却写成 ssShift),不跟。 }
    Ord('X'): if ssCtrl in Shift then begin CutToClipboard; Key := 0; end;
    Ord('V'): if ssCtrl in Shift then begin PasteFromClipboard; Key := 0; end;
    Ord('Z'): if ssCtrl in Shift then begin Undo; Key := 0; end;
    Ord('Y'): if ssCtrl in Shift then begin Redo; Key := 0; end;
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

  finally
    FExtendingSelection := False;
  end;
end;



{ ---- 行序间接层与排序 ---- }

procedure TTyStringGrid.ResetOrder;
begin
  SetLength(FOrder, 0);
  SetLength(FRank, 0);
  FOrderValid := False;
end;

procedure TTyStringGrid.CalcFooter(ACol: Integer);
begin
  if ACol < 0 then
  begin
    InvalidateAggregates;
    Exit;
  end;
  { 只掀掉这一列的有效位。数组长度不对(还没建过缓存)就什么都不用做。 }
  if (ACol <= High(FAggValid)) then FAggValid[ACol] := False;
  Invalidate;
end;

procedure TTyStringGrid.InvalidateAggregates;
begin
  { 长度归零 = 全部失效。下次用到时按当时的列数重建 ——
    列增删之后也就不必单独再失效一次。 }
  SetLength(FAggValid, 0);
  SetLength(FAggCache, 0);
end;

procedure TTyStringGrid.InvalidateOrder;
begin
  { 显示序变了 → 参与统计的行集合就变了。筛选、隐藏行、分组、行数增删
    最终都汇到这里,所以汇总的失效也挂在这一处。 }
  InvalidateAggregates;
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
  if (ARow < 0) or (ARow >= RowCount) then Exit;   { 公开入口的边界 }
  SetRowHidden(ARow, True);      { 记录点在那儿 }
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.UnHideRow(ARow: Integer);
begin
  SetRowHidden(ARow, False);
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
var
  i: Integer;
  hidden: array of Integer;   { 别叫 rows —— 与 Rows[] 属性撞名 }
begin
  if FHiddenRows.Count = 0 then Exit;
  { 逐行走记录点,而不是把表 Clear 掉 —— 直接清表的话这一步撤销不了
    (栈里那些 HideRow 的记录还原的是"本来就没藏"的行,按下去毫无动静)。
    整批算一条。 }
  SetLength(hidden, FHiddenRows.Count);
  for i := 0 to FHiddenRows.Count - 1 do
    hidden[i] := StrToIntDef(FHiddenRows[i], -1);
  BeginUpdate;
  try
    for i := 0 to High(hidden) do
      if hidden[i] >= 0 then SetRowHidden(hidden[i], False);
  finally
    EndUpdate;
  end;
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
    { 折叠只是**多一条准入判断** —— 复用现成的行序间接层,
      不给树另建一套显示序。 }
    if RowPassesFilter(i) and not RowCollapsedByTree(i) then
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
  if GetGroupCol >= 0 then
    BuildGroups;

  { 顺手记下"显示序是不是恒等"。合并、拖行都要问这件事,
    而每次现算是 O(n) —— 在这里算是顺路的。 }
  FOrderIsIdentity := True;
  for i := 0 to High(FOrder) do
    if FOrder[i] <> i then
    begin
      FOrderIsIdentity := False;
      Break;
    end;

  for i := 0 to High(FOrder) do
    if FOrder[i] >= 0 then FRank[FOrder[i]] := i;

  FOrderValid := True;
end;

procedure TTyStringGrid.BuildGroups;
var
  i, lvl, n, depth: Integer;
  src, dst: array of Integer;
  { 当前这一串祖先组的下标(每级一个),以及它们的键。 }
  openIdx: array of Integer;
  prevKey: array of string;
  key, path: string;
  same, anyCollapsed: Boolean;

  procedure OpenGroup(ALevel: Integer; const AKey, APath: string);
  var g: Integer;
  begin
    g := Length(FGroups);
    SetLength(FGroups, g + 1);
    FGroups[g].Key := AKey;
    FGroups[g].Count := 0;
    FGroups[g].Level := ALevel;
    FGroups[g].Path := APath;
    FGroups[g].Collapsed := FCollapsed.IndexOf(APath) >= 0;
    SetLength(FGroups[g].Rows, 0);
    openIdx[ALevel] := g;
    { 分组行进显示序 —— 但只有在**所有祖先都展开**时才看得见。 }
    if not AnyAncestorCollapsed(openIdx, ALevel) then
    begin
      SetLength(dst, n + 1);
      dst[n] := -(g + 1);
      Inc(n);
    end;
  end;

begin
  SetLength(FGroups, 0);
  depth := Length(FGroupCols);
  if (Length(FOrder) = 0) or (depth = 0) then Exit;

  { 这里**不再排序**。分组列已经由 EnsureOrder 通过 EffectiveSortKeys 排在最前面了,
    同值的行必然相邻。从前这里 `FSortCol := FGroupCol` 是个真 bug ——
    它把用户选的排序列永久抹掉,而且是静默的。 }

  src := FOrder;
  SetLength(dst, 0);
  SetLength(openIdx, depth);
  SetLength(prevKey, depth);
  for lvl := 0 to depth - 1 do
  begin
    openIdx[lvl] := -1;
    prevKey[lvl] := #1'no-group'#1;   { 不可能与真实值相等 }
  end;
  n := 0;

  for i := 0 to High(src) do
  begin
    { 从最外层往里比:第一处不同的那一级起,后面每一级都要开新组。
      (只比本级的话,"华东/上海"换成"华北/上海"时上海那一级不会重开。) }
    same := True;
    path := '';
    for lvl := 0 to depth - 1 do
    begin
      key := GetCellText(FGroupCols[lvl], src[i]);
      if path = '' then path := key else path := path + #1 + key;
      if same and (key <> prevKey[lvl]) then same := False;
      if not same then
      begin
        OpenGroup(lvl, key, path);
        prevKey[lvl] := key;
      end;
    end;

    { 这一行算进**所有**祖先组 —— 于是每一级的小计各自成立。 }
    anyCollapsed := False;
    for lvl := 0 to depth - 1 do
    begin
      Inc(FGroups[openIdx[lvl]].Count);
      SetLength(FGroups[openIdx[lvl]].Rows, FGroups[openIdx[lvl]].Count);
      FGroups[openIdx[lvl]].Rows[FGroups[openIdx[lvl]].Count - 1] := src[i];
      if FGroups[openIdx[lvl]].Collapsed then anyCollapsed := True;
    end;

    { 任何一级折叠着,这一行就不进显示序。 }
    if not anyCollapsed then
    begin
      SetLength(dst, n + 1);
      dst[n] := src[i];
      Inc(n);
    end;
  end;

  FOrder := dst;
end;

{ 这一级的**祖先**里有没有折叠着的(不含自己)。折叠的组下面连子分组行都不该露出来。 }
function TTyStringGrid.AnyAncestorCollapsed(const AOpen: array of Integer;
  ALevel: Integer): Boolean;
var lvl: Integer;
begin
  Result := False;
  for lvl := 0 to ALevel - 1 do
    if (AOpen[lvl] >= 0) and FGroups[AOpen[lvl]].Collapsed then Exit(True);
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

function TTyStringGrid.RowCollapsedByTree(ARow: Integer): Boolean;
var
  i, lv, mine: Integer;
begin
  Result := False;
  if (TreeColumn < 0) or (FTreeCollapsed.Count = 0) or (ARow <= 0) then Exit;

  mine := NodeLevelOf(ARow);
  if mine <= 0 then Exit;              { 根节点没有祖先,永远显示 }

  { 往上找最近的**每一级**祖先:上一个层级更浅的行就是父,再往上是祖父……
    只要链条上有任何一个是折叠的,这一行就不显示。
    (逐行往上扫,不建树 —— 与"控件不持有树"是同一个决定。) }
  for i := ARow - 1 downto 0 do
  begin
    lv := NodeLevelOf(i);
    if lv >= mine then Continue;       { 同级或更深:不是祖先 }
    if FTreeCollapsed.IndexOf(IntToStr(i)) >= 0 then Exit(True);
    mine := lv;                        { 继续找更浅的那一级 }
    if mine = 0 then Exit;             { 到根了 }
  end;
end;

function TTyStringGrid.NodeCollapsed(ARow: Integer): Boolean;
begin
  Result := FTreeCollapsed.IndexOf(IntToStr(ARow)) >= 0;
end;

function TTyStringGrid.NodeCollapsedOf(ARow: Integer): Boolean;
begin
  Result := NodeCollapsed(ARow);
end;

procedure TTyStringGrid.ToggleNode(ARow: Integer);
var
  i: Integer;
begin
  if (TreeColumn < 0) or (ARow < 0) or (ARow >= RowCount) then Exit;
  if not NodeHasChildren(ARow) then Exit;     { 没孩子的行没有折叠状态 }
  i := FTreeCollapsed.IndexOf(IntToStr(ARow));
  if i >= 0 then FTreeCollapsed.Delete(i)
  else FTreeCollapsed.Add(IntToStr(ARow));
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.ExpandAllNodes;
begin
  if FTreeCollapsed.Count = 0 then Exit;
  FTreeCollapsed.Clear;
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.CollapseAllNodes;
var
  i: Integer;
begin
  if TreeColumn < 0 then Exit;
  FTreeCollapsed.Clear;
  for i := 0 to RowCount - 1 do
    if NodeHasChildren(i) then FTreeCollapsed.Add(IntToStr(i));
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.BeginFilterEdit(ACol: Integer);
var
  l, w, bandTop, h: Integer;
begin
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  if FilterRowHeightPx <= 0 then Exit;

  { 换列时先把上一列的输入落地,别让它随着控件移动而丢掉。 }
  if FEditing and not TryEndEdit(True) then Exit;   { 拦下的编辑上面不开筛选框 }
  if FFilterEditCol >= 0 then EndFilterEdit(True);

  bandTop := ScaleI(Header.Height) + GroupBandHeightPx;
  h := FilterRowHeightPx;
  l := ColumnLeftPx(ACol);
  w := ColumnWidthPx(ACol);
  if w <= 0 then Exit;

  FFilterEditCol := ACol;
  FFilterEditor.SetBounds(l + 2, bandTop + 2, w - 4, h - 4);
  { 先摆好位置再灌值 —— 灌值会触发 OnChange,而它要用到 FFilterEditCol。 }
  FFilterEditor.Text := FilterText(ACol);
  FFilterEditor.Visible := True;
  FFilterEditor.BringToFront;
  if HandleAllocated and FFilterEditor.CanFocus then FFilterEditor.SetFocus;
end;

procedure TTyStringGrid.EndFilterEdit(AApply: Boolean);
var
  which: Integer;
begin
  if FFilterEditCol < 0 then Exit;
  FFilterTimer.Enabled := False;
  which := FFilterEditCol;
  FFilterEditCol := -1;              { 先清,免得 OnExit 递归回来 }
  FFilterEditor.Visible := False;
  if AApply then SetFilterText(which, FFilterEditor.Text);
  Invalidate;
end;

procedure TTyStringGrid.FilterEditorChange(Sender: TObject);
begin
  if FFilterEditCol < 0 then Exit;
  { 输入即筛,但要防抖 —— 每敲一个键就重建一次显示序,百万行的表会卡死。
    重启计时器:手停下来才真的去筛。 }
  FFilterTimer.Enabled := False;
  FFilterTimer.Enabled := True;
end;

procedure TTyStringGrid.FilterDebounceTick(Sender: TObject);
begin
  FFilterTimer.Enabled := False;
  if FFilterEditCol < 0 then Exit;
  SetFilterText(FFilterEditCol, FFilterEditor.Text);
end;

procedure TTyStringGrid.FilterEditorKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        { 立刻生效并收工 —— 不等防抖。 }
        EndFilterEdit(True);
        Key := 0;
        if HandleAllocated and CanFocus then SetFocus;
      end;
    VK_ESCAPE:
      begin
        { 放弃这一次的输入,回到打开编辑器之前的那条过滤条件。 }
        EndFilterEdit(False);
        Key := 0;
        if HandleAllocated and CanFocus then SetFocus;
      end;
  end;
end;

procedure TTyStringGrid.FilterEditorExit(Sender: TObject);
begin
  EndFilterEdit(True);      { 焦点离开 = 提交,与单元格编辑器一致 }
end;

procedure TTyStringGrid.SetFilterText(ACol: Integer; const AExpr: string);
var
  k: string;
  i: Integer;
begin
  if ACol < 0 then Exit;
  k := IntToStr(ACol);

  { 原文与条件分开存:回显给用户的必须是他打的那一串,
    而求值用的是解析后的编码。 }
  i := FFilterText.IndexOfName(k);
  if i >= 0 then FFilterText.Delete(i);
  if Trim(AExpr) <> '' then FFilterText.Add(k + '=' + AExpr);

  SetColumnFilter(ACol, TyGridParseFilterExpr(AExpr));
end;

function TTyStringGrid.FilterText(ACol: Integer): string;
begin
  Result := FFilterText.Values[IntToStr(ACol)];
end;

function TTyStringGrid.FilterRowText(ACol: Integer): string;
begin
  Result := FilterText(ACol);      { 显示用户打的原文,不是编码后的条件 }
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
  if (FColFilters.Count = 0) and (FValFilters.Count = 0)
     and (FFilterText.Count = 0) then Exit;
  FColFilters.Clear;
  FValFilters.Clear;
  FFilterText.Clear;      { 筛选行里的原文也要跟着清,否则框里还留着字 }
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
{ 一块纯色填充。本单元里"画一根线/一个色块"要的都是这个,
  从前每处各自 Default(TTyFill) + 两行赋值 —— 抄三遍就该收成函数。 }
function TySolidFill(AColor: TTyColor): TTyFill;
begin
  Result := Default(TTyFill);
  Result.Kind := tfkSolid;
  Result.Color := AColor;
end;

procedure TTyStringGrid.RenderHyperlinkCell(P: TTyPainter; ACol, ARow: Integer;
  const AFrame: TTyStyleSet);
var
  r, rr, line: TRect;
  ap: TTyGridCellAppearance;
  txt: string;
  tw: TSize;
  pos: Integer;
begin
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  txt := GetCellText(ACol, ARow);
  if Trim(txt) = '' then Exit;

  pos := DataToDisplay(ARow);
  if pos < 0 then Exit;              { 被筛掉/折起来的行没有显示位置 }
  ap := CellAppearance(ACol, ARow, pos, AFrame);
  tw := P.MeasureText(txt, ap.FontName, ap.FontSize, ap.FontWeight);
  if tw.cx <= 0 then Exit;

  { 下划线画在文字底下一点点,宽度按**量出来的文字宽**,不是整个格宽 ——
    整格宽的下划线看起来像一条分隔线,不像链接。 }
  rr := ToReadingRect(r);
  line := Rect(rr.Left + ScaleI(4), 0, rr.Left + ScaleI(4) + tw.cx, 0);
  if line.Right > rr.Right then line.Right := rr.Right;
  line := ToScreenRect(line);
  line.Top := (r.Top + r.Bottom) div 2 + tw.cy div 2;
  line.Bottom := line.Top + ScaleI(1);
  if (line.Right <= line.Left) or (line.Bottom > r.Bottom) then Exit;
  P.FillBackground(line, TySolidFill(ap.TextColor), 0);
end;

procedure TTyStringGrid.RenderCommentMark(P: TTyPainter; ACol, ARow: Integer;
  const AFrame: TTyStyleSet);
var
  mark, vis: TRect;
  st: TTyStyleSet;
  ink: TTyColor;
  i: Integer;
  bar: TRect;
begin
  mark := CommentMarkRect(ACol, ARow);
  if IsRectEmpty(mark) then Exit;
  { 标记也得受可见矩形约束 —— 否则冻结带边上会画到别人身上。 }
  vis := CellVisibleRect(ACol, ARow);
  if not IntersectRect(mark, mark, vis) then Exit;

  st := ActiveController.Model.ResolveStyle('TyGridCommentMark', StyleClass, []);
  if tpTextColor in st.Present then ink := st.TextColor
  else ink := AFrame.TextColor;

  { 右上角的小三角:一行比一行短的横杠堆出来。
    (画布没有多边形填充原语,用横杠堆是本库里画三角的既有做法。) }
  for i := 0 to (mark.Bottom - mark.Top) - 1 do
  begin
    bar := Rect(mark.Left + i, mark.Top + i, mark.Right, mark.Top + i + 1);
    if bar.Right <= bar.Left then Break;
    P.FillBackground(bar, TySolidFill(ink), 0);
  end;
end;

procedure TTyStringGrid.RenderPickListArrow(P: TTyPainter; ACol, ARow: Integer;
  const AFrame: TTyStyleSet);
var
  r, rr, tg: TRect;
  sz: Integer;
begin
  { 正在编辑这一格时不画 —— 编辑器自己带箭头,两个叠着难看。 }
  if FEditing and (ACol = FEditCol) and (ARow = FEditRow) then Exit;
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;

  sz := ScaleI(8);
  if sz > (r.Bottom - r.Top) then sz := r.Bottom - r.Top;
  if (sz <= 0) or (r.Right - r.Left < sz + ScaleI(4)) then Exit;
  { 箭头贴在格子的**尾缘**。格内槽位一律"在格子的阅读空间里算好再整块反射",
    这一条在本单元里出现十来次,写法相同才不会漏掉其中一处。 }
  rr := ToReadingRect(r);
  tg := ToScreenRect(Rect(rr.Right - sz - ScaleI(3), (r.Top + r.Bottom - sz) div 2,
             rr.Right - ScaleI(3), (r.Top + r.Bottom + sz) div 2));
  { pad=1:小槽里 DrawGlyph 默认每边内缩 4 逻辑像素会只剩个糊点。 }
  TyDrawGlyph(P, ActiveController, tg, tgChevronDown, AFrame.TextColor, 1, 1);
end;

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
begin
  if FImages = nil then Exit;
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  idx := StrToIntDef(Trim(GetCellText(ACol, ARow)), -1);
  if (idx < 0) or (idx >= TyImageCount(FImages)) then Exit;

  sz := ScaleI(16);
  if sz > (r.Bottom - r.Top) - 2 then sz := (r.Bottom - r.Top) - 2;
  if sz > (r.Right - r.Left) - 2 then sz := (r.Right - r.Left) - 2;
  if sz <= 0 then Exit;
  cx := (r.Left + r.Right) div 2;
  cy := (r.Top + r.Bottom) div 2;
  TyBlitImage(P.Bitmap, FImages, idx, cx - sz div 2, cy - sz div 2, sz, P.Scale(96), False);
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

function TTyStringGrid.IsActiveRow(ARow: Integer): Boolean;
begin
  Result := ARow = FRow;
end;

{ goEditing = not ReadOnly。**直接读写 FReadOnly** 而不是走属性:
  ReadOnly 的 setter 就是字段(声明处 `write FReadOnly`),绕一圈没有区别,
  而写成 `ReadOnly := ...` 会让人以为那边还有别的动作。 }
function TTyStringGrid.GetOptEditing: Boolean;
begin
  Result := not FReadOnly;
end;

procedure TTyStringGrid.SetOptEditing(AValue: Boolean);
begin
  FReadOnly := not AValue;
end;

function TTyStringGrid.GetOptRowSelect: Boolean;
begin
  Result := FSelectionMode = gsmRow;
end;

{ 三态压两态的那一半。**只在 SetOptions 判定"这一位真的翻了"之后才会被调到** ——
  所以 gsmColumn 走不到这里,不会被压成 gsmCell。要是哪天有人直接调这个方法,
  行为仍然是明确的:开 = gsmRow,关 = gsmCell。 }
procedure TTyStringGrid.SetOptRowSelect(AValue: Boolean);
begin
  if AValue then SetSelectionMode(gsmRow) else SetSelectionMode(gsmCell);
end;

{ goScrollKeepVisible:视口刚挪完,把光标拖回可见范围里。

  **不能走 MoveCursor** —— 它尾巴上那句 ScrollIntoView 会立刻把视口拽回光标
  原来的位置,于是滚动条一放手画面就弹回去,看起来像滚不动。所以这里直接
  改 FCol/FRow 再重锚,跳过滚动那一步。 }
procedure TTyStringGrid.KeepCursorVisible;
var
  M: TTyGridMetrics;
  firstRow, lastRow, pos, d, lc, vc, newCol, newRow: Integer;
begin
  if (Header.Columns.Count = 0) or (RowCount = 0) then Exit;
  newCol := FCol;
  newRow := FRow;

  M := GridMetrics;
  { 纵向:可见的**显示位置**区间。用显示序而不是数据行 —— 排序/过滤之后
    数据行号与屏幕位置根本不是一回事。 }
  if TyGridVisibleRows(M, firstRow, lastRow) then
  begin
    pos := DataToDisplay(FRow);
    { pos < 0 = 光标那一行被筛掉了。这时候没有"把它拉进视口"这回事,别动。 }
    if pos >= 0 then
    begin
      if pos < firstRow then pos := firstRow
      else if pos > lastRow then pos := lastRow;
      d := DisplayToData(pos);
      if d >= 0 then newRow := d;    { 组标题行的 DisplayToData 是负的,跳过 }
    end;
  end;

  { 横向:冻结列永远可见,所以只在光标落在可滚动区时才管。 }
  if FCol >= FFixedCols then
  begin
    lc := GetLeftCol;
    vc := VisibleColCount;
    if vc < 1 then vc := 1;
    if FCol < lc then newCol := lc
    else if FCol > lc + vc - 1 then newCol := lc + vc - 1;
    if newCol > Header.Columns.Count - 1 then newCol := Header.Columns.Count - 1;
    if newCol < FFixedCols then newCol := FFixedCols;
  end;

  if (newCol = FCol) and (newRow = FRow) then Exit;
  FCol := newCol;
  FRow := newRow;
  if not FExtendingSelection then AnchorSelection;
  SelectionChanged;
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
    if (a = nil) or (not a.HasBackground) then Exit;   { 本来就没有 —— 不是一次改动 }
    a := FAttrs.Mutate(k);
    a.HasBackground := False;
    FAttrs.DropIfDefault(k);
  end
  else
  begin
    { **设成它已经是的那个值 = 不是一次改动。**
      Ensure 会发"即将改动"通知,而记录点在那儿 —— 不先挡一下的话
      同色再设一次也压一条空记录:Ctrl+Z 按下去没反应,
      更糟的是那条空记录把重做链清掉了。`SetCells` 一直有这道保护。 }
    if GetCellColor(ACol, ARow) = AValue then Exit;
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
    if (a = nil) or (not a.HasTextColor) then Exit;
    a := FAttrs.Mutate(k);
    a.HasTextColor := False;
    FAttrs.DropIfDefault(k);
  end
  else
  begin
    if GetCellTextColor(ACol, ARow) = AValue then Exit;   { 见 SetCellColor }
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
  { 整行上色 = 一条撤销记录(与 SetSelectionColor 同一条规矩)。 }
  BeginUpdate;
  try
    for j := 0 to Header.Columns.Count - 1 do
      CellColors[j, ARow] := AColor;
  finally
    EndUpdate;
  end;
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
    if (a = nil) or (not a.ReadOnly) then Exit;
    a := FAttrs.Mutate(k);
    a.ReadOnly := False;
    FAttrs.DropIfDefault(k);
  end
  else
  begin
    if GetCellReadOnly(ACol, ARow) then Exit;             { 见 SetCellColor }
    a := FAttrs.Ensure(k);
    if a = nil then Exit;
    a.ReadOnly := True;
  end;
end;

function TTyStringGrid.CellDisplayFor(ACol, ARow: Integer): TTyGridCellDisplay;
var
  c: TTyGridColumn;
  a: TTyGridCellAttr;
begin
  { 优先级:**逐格 > 事件 > 列 > 网格默认** —— 与 EditorKindFor 同一条链,
    越具体的越晚被覆盖。逐格排在事件之上:显式为某一格设过的东西
    不该被一个逐格回调无差别地抹掉。 }
  Result := FDefaultCellDisplay;
  c := GridColumn(ACol);
  if (c <> nil) and c.UseCellDisplay then Result := c.CellDisplay;
  if Assigned(FOnGetCellDisplay) then FOnGetCellDisplay(Self, ACol, ARow, Result);
  if not FAttrs.IsEmpty then          { 见 GetCellReadOnly:空存储别建临时键 }
  begin
    a := FAttrs.Find(CellKey(ACol, ARow));
    if (a <> nil) and a.HasCellDisplay then Result := a.CellDisplay;
  end;
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
  txt, cmt: string;
begin
  inherited MouseMove(Shift, X, Y);
  if not Enabled then Exit;

  { 正在拖填充柄:只记目标行,松开才真正填 ——
    拖过程中就写数据的话,往回拖一格就再也退不回来了。 }
  if FFillDragging then
  begin
    hit := CellAt(X, Y);
    if hit.Part = ghpCell then
    begin
      FFillToCol := hit.Col;
      FFillToRow := hit.Row;
      Invalidate;
    end;
    Exit;
  end;

  { 按住左键在格上移动 = 拖选,这是**扩选**手势:只挪光标、不动锚点,
    活动矩形因此从按下那一格一直拉到这里。
    (MoveCursor 默认会重锚 —— 见它那里的说明 —— 所以这里要显式声明在扩选。)
    放在 hint 那段之前:拖选期间不该再弹提示。 }
  if ssLeft in Shift then
  begin
    hit := CellAt(X, Y);
    if (hit.Part = ghpCell) and ((hit.Col <> FCol) or (hit.Row <> FRow)) then
    begin
      { goRangeSelect 关掉时拖动仍然移动光标(那是"点着走"的手感,
        LCL 也如此),只是不再把选区拉长 —— 选区始终收在当前格。 }
      FExtendingSelection := goRangeSelect in Options;
      try
        MoveCursor(hit.Col, hit.Row);
      finally
        FExtendingSelection := False;
      end;
      SelectionChanged;
    end;
    Exit;
  end;

  { goCellHints 是总闸。关掉时还要把**已经挂上**的那条提示摘掉,
    否则鼠标停在某格上时关掉开关,那条提示会一直悬在那儿。 }
  if not (goCellHints in Options) then
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

  { 批注也要出提示,所以**不能**因为没挂 OnGetCellHint 就走人 ——
    那样批注在没挂钩子的表上永远显示不出来(存了却看不见 = 等于没存)。
    goTruncCellHints 是第三个来源(放不下的文字用全文当提示),
    所以它也算"有理由继续往下走"。 }
  if (not Assigned(FOnGetCellHint)) and (not FHasComments)
     and not (goTruncCellHints in Options) then Exit;

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
  { 三层,由弱到强:截断全文 → 批注 → 宿主钩子。宿主永远是最具体的那一层
    (与别处的优先级同向),截断全文最弱 —— 它只是"没有别的可说时"的兜底。 }
  txt := '';
  if goTruncCellHints in Options then txt := TruncatedCellHint(hit.Col, hit.Row);
  cmt := GetCellComment(hit.Col, hit.Row);
  if cmt <> '' then txt := cmt;
  if Assigned(FOnGetCellHint) then FOnGetCellHint(Self, hit.Col, hit.Row, txt);
  Hint := txt;
  ShowHint := txt <> '';
end;

{ goTruncCellHints:这一格的文字放得下就答空串,放不下就答**全文**。

  **现量,不在绘制时记账。** 绘制那条路一帧要走几百格,给每格记一位
  "截没截断"要么多一张随时可能与实际不同步的表,要么把这一位塞进文字位图
  缓存的键里(那会让缓存命中率掉一半)。而这里一次只问一格、只在**换格**时问
  (上面那道 FHintCol/FHintRow 闸),量一次的代价可以忽略。

  量的口径与绘制**同一个函数**(TyGridEllipsisFit),所以"提示说放不下"
  与"屏幕上真的加了…"不可能对不上 —— 这正是自己另写一遍宽度比较会踩的坑。 }
function TTyStringGrid.TruncatedCellHint(ACol, ARow: Integer): string;
var
  bmp: TBGRABitmap;
  { 不叫 cellS —— Pascal 不分大小写,那个名字与 TTyStringGrid.Cells 属性同名,
    编译器直接报 "Duplicate identifier Cells"。 }
  cellSty: TTyStyleSet;
  ap: TTyGridCellAppearance;
  M: TTyGridMetrics;
  cell, textR: TRect;
  w, pos: Integer;
  full: string;
begin
  Result := '';
  full := DisplayCellText(ACol, ARow);
  if full = '' then Exit;

  { WordWrap 逐格可被 OnGetCellWordWrap 改写,所以必须问 CellAppearance,
    不能只看网格的 FWordWrap。换行的格放不下就往下一行走,没有"截断"这回事。 }
  pos := DataToDisplay(ARow);
  if pos < 0 then Exit;                     { 被筛掉的行不在屏幕上 }
  { 传 CurrentStyle 而不是自己现解析一次 'TyGrid' —— 绘制那条路
    (RenderTo:`AFrame := CurrentStyle`)喂给 CellAppearance 的就是它。
    换一个来源就等于换一套字体,量出来的宽度会与屏幕上的不是一回事。 }
  ap := CellAppearance(ACol, ARow, pos, CurrentStyle);
  if ap.WordWrap then Exit;

  { **宽度预算与 RenderCells 逐字算同一份**:让开格线 → 减主题左右内边距 →
    树形列再减缩进。少减一项就会出现"提示说放得下、屏幕上却带着…"。 }
  M := GridMetrics;
  cell := TyGridCellContentRect(CellRect(ACol, ARow), M);
  cellSty := ActiveController.Model.ResolveStyle('TyGridCell', StyleClass, []);
  textR := ToReadingRect(cell);
  textR := Rect(textR.Left + ScaleI(cellSty.Padding.Left), cell.Top,
                textR.Right - ScaleI(cellSty.Padding.Right), cell.Bottom);
  if (FTreeColumn >= 0) and (ACol = FTreeColumn) then
    Inc(textR.Left, TreeContentLeft(ACol, ARow));
  w := textR.Right - textR.Left;
  if w <= 0 then Exit;

  { 1x1 的临时位图只用来量文字 —— 与 AutoFitColumn 同一个手法。 }
  bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(bmp, ap.FontName, ap.FontSize, ap.FontWeight, Dpi);
    if TyGridEllipsisFit(bmp, full, w) <> full then Result := full;
  finally
    bmp.Free;
  end;
end;

{ 链接格的文字色从 TyGridHyperlink 取 —— 不硬编码蓝色。
  主题没定义这个键时退回强调色的常规解析(base 层会垫底,见主题回退机制)。 }
{ 链接格换文字色。放在 CellAppearance 而不是绘制处:那样连宿主的
  OnGetCellStyle 都还能再压过它 —— 优先级链就一条,不另开分支。 }
function TTyStringGrid.CellAppearance(ACol, ARow, ADisplayPos: Integer;
  const AFrame: TTyStyleSet): TTyGridCellAppearance;
begin
  Result := inherited CellAppearance(ACol, ARow, ADisplayPos, AFrame);
  if CellDisplayFor(ACol, ARow) = gcdHyperlink then
    Result.TextColor := HyperlinkTextColor(Result.TextColor);
end;

function TTyStringGrid.HoverIsHyperlink(X, Y: Integer): Boolean;
var hit: TTyGridHit;
begin
  hit := CellAt(X, Y);
  Result := (hit.Part = ghpCell) and (hit.Col >= 0) and (hit.Row >= 0)
        and (CellDisplayFor(hit.Col, hit.Row) = gcdHyperlink);
end;

function TTyStringGrid.HyperlinkTextColor(const AFallback: TTyColor): TTyColor;
var st: TTyStyleSet;
begin
  st := ActiveController.Model.ResolveStyle('TyGridHyperlink', StyleClass, []);
  if tpTextColor in st.Present then Result := st.TextColor
  else Result := AFallback;
end;

function TTyStringGrid.DisplayCellText(ACol, ARow: Integer): string;
begin
  Result := GetCellText(ACol, ARow);
  if Assigned(FOnGetFormat) then FOnGetFormat(Self, ACol, ARow, Result);
end;

function TTyStringGrid.ShouldDrawCellText(ACol, ARow: Integer): Boolean;
begin
  { 链接格的文字仍走通用文字层(只有颜色和下划线是它自己的),
    所以它和 gcdText 一样要画字 —— 漏掉它就是一格空白。 }
  Result := (EditorKindFor(ACol, ARow) <> gekCheckBox)
        and (CellDisplayFor(ACol, ARow) in [gcdText, gcdHyperlink]);
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

  { 填充从**阅读起点**长出去,不是从左边长。在阅读空间里算完再反射回来 ——
    RTL 下 30% 的进度条应当是右边那 30% 被填满。 }
  fill := ToReadingRect(bar);
  fill.Right := fill.Left + Round((bar.Right - bar.Left) * pct / 100);
  fill := ToScreenRect(fill);
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
  if FEditing and not TryEndEdit(True) then Exit;   { 先把拦下的值改对,再谈省略号 }
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
  r, rr: TRect;
  box, cy, x0, i: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (AStar < 1) or (AStar > TyGridRatingMax) then Exit;
  r := CellVisibleRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;

  box := ScaleI(12);
  cy := (r.Top + r.Bottom) div 2;
  { 星星从阅读起点排起。RenderRatingCell 画的就是本函数的返回值,
    SetRatingByPoint 命中的也是它 —— 一个来源,三个消费者。 }
  rr := ToReadingRect(r);
  x0 := rr.Left + ScaleI(4);
  i := AStar - 1;
  Result := Rect(x0 + i * (box + ScaleI(2)), cy - box div 2,
                 x0 + i * (box + ScaleI(2)) + box, cy - box div 2 + box);
  if Result.Right > rr.Right then Exit(Rect(0, 0, 0, 0));
  Result := ToScreenRect(Result);
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

{ 这一列的勾选词汇。列没设(或根本不是网格自己的列类)时两个都回空串,
  于是所有调用点自动退回内建的那套 —— 判空一次,别在四处各判一次。 }
procedure TTyStringGrid.CheckWordsOf(ACol: Integer;
  out AChecked, AUnchecked: string);
var
  gc: TTyGridColumn;
begin
  AChecked := '';
  AUnchecked := '';
  { 局部变量刻意不叫 col —— TTyStringGrid 发布了 Col 属性,同名局部会遮蔽它。 }
  gc := GridColumn(ACol);
  if gc = nil then Exit;
  AChecked := gc.ValueChecked;
  AUnchecked := gc.ValueUnchecked;
end;

function TTyStringGrid.CellChecked(ACol, ARow: Integer): Boolean;
var
  v, wc, wu, w: string;
begin
  v := LowerCase(Trim(GetCellText(ACol, ARow)));
  { 本列自己的词汇先说话 —— 'Y'/'N' 那种表里 'n' 落不进内建词表算是碰巧对了,
    而 ValueChecked='N' 这种(合法但少见的)配置只有问过列才答得对。 }
  CheckWordsOf(ACol, wc, wu);
  if (wc <> '') and (v = LowerCase(Trim(wc))) then Exit(True);
  if (wu <> '') and (v = LowerCase(Trim(wu))) then Exit(False);

  { 宽松识别:从 CSV/外部系统进来的真值写法五花八门,读的时候都认。 }
  Result := (v = '1') or (v = 'true') or (v = 'yes') or (v = 'y');
  { 再认一个本地化的真值写法(中文表里常见 '是')。哨兵 = **实时**读 resourcestring
    —— 不能读初始化时抓的拷贝,语言目录装载晚于单元初始化(见 TyGridCheckedWord
    声明处)。空的本地化词(显式 override 成空)不参与判定。 }
  if not Result then
  begin
    w := TyGridCheckedWord;
    if w = TyGridCheckedWordFollowRs then w := rsGridCheckedWord;
    if w <> '' then Result := v = LowerCase(w);
  end;
end;

function TTyStringGrid.CellCheckState(ACol, ARow: Integer): TCheckBoxState;
var
  v, wc, wu: string;
begin
  { 读值宽松(与 CellChecked 同一条纪律:进来的写法五花八门,都认)。
    灰显认 '2' / 'grayed' / 'null' —— 三态最常见的三种外部表示。 }
  v := LowerCase(Trim(GetCellText(ACol, ARow)));
  { 本列词汇里的那两个词优先于灰显词表:一列真值写成 '2' 的表(评分/等级导出来的
    很常见)如果先撞上灰显判定,就永远读不出"勾上"。 }
  CheckWordsOf(ACol, wc, wu);
  if (wc <> '') and (v = LowerCase(Trim(wc))) then Exit(cbChecked);
  if (wu <> '') and (v = LowerCase(Trim(wu))) then Exit(cbUnchecked);
  if (v = '2') or (v = 'grayed') or (v = 'null') then Exit(cbGrayed);
  if CellChecked(ACol, ARow) then Exit(cbChecked);
  Result := cbUnchecked;
end;

procedure TTyStringGrid.ToggleCellChecked(ACol, ARow: Integer);
var
  accept: Boolean;
  oldTxt, newTxt, wordC, wordU: string;
begin
  if FReadOnly then Exit;

  { 宿主可以否决这一次切换("已锁定的行不许改")。 }
  accept := True;
  if Assigned(FOnCanToggleCheck) then FOnCanToggleCheck(Self, ACol, ARow, accept);
  if not accept then Exit;

  oldTxt := GetCellText(ACol, ARow);
  { 写回收敛成本列的词汇;列没定义就还是从前那套 '1'/'2'/''。
    从前这里**无条件**写 '1'/'',于是一张 'Y'/'N' 的表被点一下就多出个 '1' ——
    宿主的数据词汇被控件换掉了,而 OnCellEdited 的 ANewText 是 const,拦不住也改不回。
    循环顺序**照抄 TTyCheckBox.Click**(空→勾→灰→空),不另定义一套:
    同一个视觉部件在两处走不同的顺序是最容易被当成 bug 的那种不一致。 }
  CheckWordsOf(ACol, wordC, wordU);
  if wordC = '' then wordC := '1';
  if FAllowGrayed then
    case CellCheckState(ACol, ARow) of
      cbUnchecked: newTxt := wordC;
      { 灰显没有列词汇可用(LCL 那一对本来就只有两个词),仍写 '2'。 }
      cbChecked:   newTxt := '2';
      else         newTxt := wordU;
    end
  else
    if CellChecked(ACol, ARow) then newTxt := wordU else newTxt := wordC;
  accept := True;
  if Assigned(FOnCellEdited) then
    FOnCellEdited(Self, ACol, ARow, oldTxt, newTxt, accept);
  if accept then
  begin
    Cells[ACol, ARow] := newTxt;
    { 切换成功了才通知 —— 让宿主不用自己再判一次有没有真的变。
      判据是"不等于**未勾的那个词**",不是"不等于空串":列词汇里未勾写成 'N' 时
      空串判法会把 'N' 当成勾上了。词汇没设时 wordU 就是 '',与从前一模一样
      (灰显的 '2' 仍报 True)。 }
    if Assigned(FOnCheckBoxChange) then
      FOnCheckBoxChange(Self, ACol, ARow, newTxt <> wordU);
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
  r, rr: TRect;
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
  rr := ToReadingRect(r);
  Result := ToScreenRect(Rect(rr.Right - box - ScaleI(2), (r.Top + r.Bottom - box) div 2,
                 rr.Right - ScaleI(2), (r.Top + r.Bottom - box) div 2 + box));
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

function TTyStringGrid.GetCellComment(ACol, ARow: Integer): string;
var a: TTyGridCellAttr;
begin
  Result := '';
  if FAttrs.IsEmpty then Exit;      { 见 GetCellReadOnly }
  a := FAttrs.Find(CellKey(ACol, ARow));
  if a <> nil then Result := a.Comment;
end;

procedure TTyStringGrid.SetCellComment(ACol, ARow: Integer; const AValue: string);
var
  k: string;
  a: TTyGridCellAttr;
begin
  if GetCellComment(ACol, ARow) = AValue then Exit;
  k := CellKey(ACol, ARow);
  if AValue = '' then
  begin
    a := FAttrs.Mutate(k);          { Mutate 先发 Changing → 撤销记得住 }
    if a = nil then Exit;
    a.Comment := '';
    FAttrs.DropIfDefault(k);
  end
  else
  begin
    a := FAttrs.Ensure(k);
    if a = nil then Exit;
    a.Comment := AValue;
    FHasComments := True;   { 只增不减:删光批注后多问几次而已,不会画错 }
  end;
  Invalidate;
end;

function TTyStringGrid.GetCellFontStyles(ACol, ARow: Integer): TFontStyles;
var a: TTyGridCellAttr;
begin
  Result := [];
  if FAttrs.IsEmpty then Exit;
  a := FAttrs.Find(CellKey(ACol, ARow));
  if (a <> nil) and a.HasFontStyle then Result := a.FontStyle;
end;

procedure TTyStringGrid.SetCellFontStyles(ACol, ARow: Integer; AValue: TFontStyles);
var
  k: string;
  a: TTyGridCellAttr;
begin
  if GetCellFontStyles(ACol, ARow) = AValue then Exit;
  k := CellKey(ACol, ARow);
  if AValue = [] then
  begin
    a := FAttrs.Mutate(k);          { Mutate 先发 Changing → 撤销记得住 }
    if a = nil then Exit;
    a.HasFontStyle := False;
    a.FontStyle := [];
    FAttrs.DropIfDefault(k);
  end
  else
  begin
    a := FAttrs.Ensure(k);
    if a = nil then Exit;
    a.HasFontStyle := True;
    a.FontStyle := AValue;
  end;
  ResetCellStyleCache;
  InvalidateSurface;
  Invalidate;
end;

function TTyStringGrid.GetCellDisplay(ACol, ARow: Integer): TTyGridCellDisplay;
var a: TTyGridCellAttr;
begin
  Result := gcdText;
  if FAttrs.IsEmpty then Exit;
  a := FAttrs.Find(CellKey(ACol, ARow));
  if (a <> nil) and a.HasCellDisplay then Result := a.CellDisplay;
end;

function TTyStringGrid.GetObjects(ACol, ARow: Integer): TObject;
var a: TTyGridCellAttr;
begin
  Result := nil;
  if FAttrs.IsEmpty then Exit;      { 见 GetCellReadOnly:空存储别建临时键 }
  a := FAttrs.Find(CellKey(ACol, ARow));
  if a <> nil then Result := a.Obj;
end;

procedure TTyStringGrid.SetObjects(ACol, ARow: Integer; AValue: TObject);
var
  k: string;
  a: TTyGridCellAttr;
begin
  if GetObjects(ACol, ARow) = AValue then Exit;   { 见 SetCellColor }
  k := CellKey(ACol, ARow);
  if AValue = nil then
  begin
    a := FAttrs.Find(k);
    if a = nil then Exit;
    a.Obj := nil;
    FAttrs.DropIfDefault(k);        { 只剩空壳就还回去,别让稀疏存储攒垃圾 }
  end
  else
  begin
    { **EnsureQuiet,不是 Ensure。** 挂一个对象不是一次可撤销的改动
      (见 Objects[] 属性的说明),走 Ensure 就会在撤销栈上压一条带着
      宿主指针的记录。 }
    a := FAttrs.EnsureQuiet(k);
    if a = nil then Exit;
    a.Obj := AValue;
  end;
  { 对象槽不参与任何绘制 —— **不要** Invalidate:给十万行逐行挂对象
    就会变成十万次重画请求。 }
end;

{ ---- Cols[] / Rows[] ------------------------------------------------------- }

function TTyStringGrid.ColsRowsView(var ACache: TStringList; AIsCol: Boolean;
  AIndex: Integer): TStrings;
var
  i: Integer;
  k: string;
begin
  if ACache = nil then
  begin
    ACache := TStringList.Create;
    ACache.Sorted := True;          { 二分查找;这里**只查不遍历**,见字段处说明 }
    ACache.Duplicates := dupIgnore;
    ACache.OwnsObjects := True;
  end;
  k := IntToStr(AIndex);
  i := ACache.IndexOf(k);
  if i >= 0 then Exit(TStrings(ACache.Objects[i]));

  Result := TTyGridStrings.Create(Self, AIsCol, AIndex);
  i := ACache.AddObject(k, Result);
  { dupIgnore 时重复键不会收下对象 —— 不管的话就是内存泄漏(与 Ensure 同坑)。 }
  if (i < 0) or (ACache.Objects[i] <> Result) then
  begin
    Result.Free;
    if i < 0 then Exit(nil);
    Result := TStrings(ACache.Objects[i]);
  end;
end;

function TTyStringGrid.GetCols(AIndex: Integer): TStrings;
begin
  Result := ColsRowsView(FColViews, True, AIndex);
end;

function TTyStringGrid.GetRows(AIndex: Integer): TStrings;
begin
  Result := ColsRowsView(FRowViews, False, AIndex);
end;

procedure TTyStringGrid.SetCols(AIndex: Integer; AValue: TStrings);
begin
  GetCols(AIndex).Assign(AValue);
end;

procedure TTyStringGrid.SetRows(AIndex: Integer; AValue: TStrings);
begin
  GetRows(AIndex).Assign(AValue);
end;

procedure TTyStringGrid.SetCellDisplay(ACol, ARow: Integer;
  AValue: TTyGridCellDisplay);
var
  k: string;
  a: TTyGridCellAttr;
begin
  k := CellKey(ACol, ARow);
  a := FAttrs.Ensure(k);
  if a = nil then Exit;
  a.HasCellDisplay := True;
  a.CellDisplay := AValue;
  Invalidate;
end;

{ 批注标记:格子右上角一个小三角。尺寸走主题(标记也是视觉),
  没有批注就返回空矩形 —— 调用方靠"空不空"判断要不要画。 }
function TTyStringGrid.CommentMarkRect(ACol, ARow: Integer): TRect;
var
  r, rr: TRect;
  sz: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if not FHasComments then Exit;      { 无批注的表:渲染路径每格都走这里 }
  if GetCellComment(ACol, ARow) = '' then Exit;
  r := CellRect(ACol, ARow);
  if IsRectEmpty(r) then Exit;
  sz := ScaleI(ActiveController.Metric('--grid-comment-mark-size', TyGridCommentMarkSize));
  if sz > (r.Bottom - r.Top) then sz := r.Bottom - r.Top;
  if sz > (r.Right - r.Left) then sz := r.Right - r.Left;
  if sz <= 0 then Exit;
  { 批注角标钉在格子的**尾上角**。绘制(RenderCommentMark)与提示命中读的
    都是这一个矩形,所以换边时两者一起换。 }
  rr := ToReadingRect(r);
  Result := ToScreenRect(Rect(rr.Right - sz, r.Top, rr.Right, r.Top + sz));
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
  dash: TRect;
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

  if CellCheckState(ACol, ARow) <> cbUnchecked then
  begin
    if tpTextColor in boxS.Present then ink := boxS.TextColor
    else ink := AFrame.TextColor;
    { 灰显画一根横杠(与 TTyCheckBox 的三态一个样子),勾上才画对勾 ——
      两个态如果画得一样,用户根本分不出来。 }
    if CellCheckState(ACol, ARow) = cbGrayed then
    begin
      dash := box;
      InflateRect(dash, -(box.Right - box.Left) div 4, 0);
      dash.Top := (box.Top + box.Bottom) div 2 - ScaleI(1);
      dash.Bottom := dash.Top + ScaleI(2);
      if dash.Bottom > dash.Top then
        P.FillBackground(dash, TySolidFill(ink), 0);
    end
    else
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
  { HideSortArrow 熄的是**整个指示器**,不只是那个三角:多列排序时列头上还有
    "1/2/3" 的顺位徽标,只清 Header.SortColumn 的话三角没了、徽标还在,
    看起来像画坏了。 }
  if FSortArrowHidden then Exit;
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
  handled: Boolean;
begin
  AItems.Clear;
  { 宿主接管?百万行的虚拟表遍历全表取候选是走不通的,
    而且服务端往往知道一份权威的取值集合。 }
  if Assigned(FOnGetFilterValues) then
  begin
    handled := False;
    FOnGetFilterValues(Self, ACol, AItems, handled);
    if handled then Exit;
    AItems.Clear;     { 没接管就当没动过 —— 宿主可能已经往里塞了东西 }
  end;
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

function TTyGridFilterList.RtlRowLayout: Boolean;
begin
  Result := False;      { 见声明处 —— 这是一处刻意的不镜像,不是漏掉的 }
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
  var
    a: TTyGridCellAttr;
  begin
    Cells[AC, AR] := '';
    { 合并计数是旁挂的汇总,不在属性对象里 —— 丢掉一个合并基准格必须跟着减。
      不减的话 `HasMergedCells` 会一直答"有合并区"而实际一个都没有,
      于是格线绘制永远走那条慢的逐列分段路径,取消合并也清不掉这个状态。 }
    a := FAttrs.Find(CellKey(AC, AR));
    if (a <> nil) and ((a.ColSpan > 1) or (a.RowSpan > 1)) then
    begin
      Dec(FMergeCount);
      if FMergeCount < 0 then FMergeCount := 0;
    end;
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
    SnapshotCellKeys(attrKeys);
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
    ShiftRowStateWithUndo(AFromIndex, ADelta);
    GrowMergesSpanningRow(AFromIndex, ADelta);
    InvalidateOrder;
  end
  else
  begin
    { **列轴同理** —— 这三张表键的是列下标,上面只搬了格子。
      不搬的话:筛选留在旧列号上,取出来的文字是空 → 每一行都不匹配 →
      **整张表变空**,而漏斗图标已经跟着列走了,用户在界面上找不到地方去清它。
      (做 B2 的行置换收口时只想了行,漏了这一半。) }
    ShiftColKeyedTable(FFilterText, AFromIndex, ADelta);
    ShiftColKeyedTable(FColFilters, AFromIndex, ADelta);
    ShiftColKeyedTable(FValFilters, AFromIndex, ADelta);
    ShiftColKeyedTable(FAggregates, AFromIndex, ADelta);
    InvalidateOrder;          { 筛选变了 → 显示序与汇总都要重算 }
  end;
end;

{ 把"以行下标为键"的旁挂表整体平移。ADelta < 0 时,正落在 AFromIndex 上的那条被丢弃。
  就地改键会撞上重复键,所以整表重建。 }
procedure TTyCustomGrid.TrimRowStateTo(ANewCount: Integer);
var
  i, r: Integer;
  doomed: array of Integer;
begin
  { 先收集再删 —— 边遍历边删会跳过条目。 }
  SetLength(doomed, 0);
  for i := 0 to FRowHeights.Count - 1 do
  begin
    r := StrToIntDef(FRowHeights[i], -1);
    if r >= ANewCount then
    begin
      SetLength(doomed, Length(doomed) + 1);
      doomed[High(doomed)] := r;
    end;
  end;
  for i := 0 to High(doomed) do
    SetRowHeights(doomed[i], 0);        { 走记录点 → 可撤销 }
end;

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

procedure TTyCustomGrid.ShiftColKeyedTable(AList: TStringList;
  AFromIndex, ADelta: Integer);
var
  i, c: Integer;
  rebuilt: TStringList;
  v: string;
begin
  if (AList = nil) or (AList.Count = 0) or (ADelta = 0) then Exit;
  rebuilt := TStringList.Create;
  try
    for i := 0 to AList.Count - 1 do
    begin
      c := StrToIntDef(AList.Names[i], -1);
      if c < 0 then Continue;
      v := AList.ValueFromIndex[i];
      if c >= AFromIndex then
      begin
        if (ADelta < 0) and (c = AFromIndex) then Continue;   { 被删的那一列 }
        Inc(c, ADelta);
        if c < 0 then Continue;
      end;
      rebuilt.Add(IntToStr(c) + '=' + v);
    end;
    AList.Assign(rebuilt);
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
  { 逐行问,任何一行被否决就整批不做 —— 插一半比一行不插更难收拾。 }
  for i := 0 to ACount - 1 do
    if not CanInsertRow(ARow + i) then Exit;
  EndEdit(True);
  { **两层都要**:BeginUpdateOrder 压重排,BeginUpdate 才开撤销事务。
    单数的 InsertRow 早就这么做了,复数这个漏了 —— 插 3 行压了 25 条记录。 }
  BeginUpdate;
  BeginUpdateOrder;
  try
    { 从后往前搬 ACount 次,等价于一次搬 ACount ——
      ShiftCells 本身已经处理了方向,这里只是省掉每次的重排。 }
    for i := 1 to ACount do ShiftCells(ARow, 1, True);
    RowCount := RowCount + ACount;
  finally
    EndUpdateOrder;
    EndUpdate;
  end;
end;

procedure TTyStringGrid.RemoveRows(ARow, ACount: Integer);
var
  i: Integer;
begin
  if ACount <= 0 then Exit;
  if (ARow < 0) or (ARow >= RowCount) then Exit;
  if ARow + ACount > RowCount then ACount := RowCount - ARow;
  for i := 0 to ACount - 1 do
    if not CanDeleteRow(ARow + i) then Exit;   { 见 InsertRows:整批否决 }
  EndEdit(True);
  BeginUpdate;                { 见 InsertRows:撤销事务与重排是两层 }
  BeginUpdateOrder;
  try
    for i := 1 to ACount do ShiftCells(ARow, -1, True);
    RowCount := RowCount - ACount;
  finally
    EndUpdateOrder;
    EndUpdate;
  end;
end;

procedure TTyStringGrid.InsertCols(ACol, ACount: Integer);
var
  i: Integer;
begin
  if ACount <= 0 then Exit;
  { **两层都要** —— 与 InsertRows 一模一样的道理:BeginUpdateOrder 压重排,
    BeginUpdate 才开撤销事务。行那边本轮修过了,列这边是它逐字的孪生兄弟。 }
  BeginUpdate;
  BeginUpdateOrder;
  try
    for i := 1 to ACount do InsertColumn(ACol);
  finally
    EndUpdateOrder;
    EndUpdate;
  end;
end;

procedure TTyStringGrid.RemoveCols(ACol, ACount: Integer);
var
  i: Integer;
begin
  if ACount <= 0 then Exit;
  BeginUpdate;                { 见 InsertCols:撤销事务与重排是两层 }
  BeginUpdateOrder;
  try
    for i := 1 to ACount do
    begin
      if ACol >= Header.Columns.Count then Break;
      DeleteColumn(ACol);
    end;
  finally
    EndUpdateOrder;
    EndUpdate;
  end;
end;

procedure TTyStringGrid.SwapRows(ARow1, ARow2: Integer);
var
  j: Integer;
  tmp: string;
  a1, a2: TTyGridCellAttr;
  k1, k2: string;
  map: array of Integer;
begin
  { 整个操作算**一条**撤销记录:它内部搬很多格子,逐格记的话
    用户得按几十次 Ctrl+Z 才退得回来。批量重画的边界与撤销事务的边界
    本来就该是同一个。 }
  BeginUpdate;
  try
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
    { 行高、隐藏标记这些**按行**记账的东西不是格属性,上面那个循环够不着它们。
      走统一的置换收口 —— 从前这里只手搬了行高,隐藏标记留在旧下标上,
      于是换过去的那一行凭空消失、藏着的那一行冒了出来。 }
    SetLength(map, RowCount);
    for j := 0 to RowCount - 1 do map[j] := j;
    map[ARow1] := ARow2;
    map[ARow2] := ARow1;
    PermuteRowState(map);
  finally
    EndUpdateOrder;
  end;
  finally
    EndUpdate;
  end;
end;

procedure TTyStringGrid.MoveRow(AFrom, ATo: Integer);
var
  i: Integer;
begin
  { 整个操作算**一条**撤销记录:它内部搬很多格子,逐格记的话
    用户得按几十次 Ctrl+Z 才退得回来。批量重画的边界与撤销事务的边界
    本来就该是同一个。 }
  BeginUpdate;
  try
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
  finally
    EndUpdate;
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
  RecordColumnUndo(gukColMove, AFrom, ATo);
  Invalidate;
end;

procedure TTyStringGrid.CutToClipboard;
var
  pos, dataRow, colIdx: Integer;
begin
  CopySelectionToClipboard;
  { ReadOnly 下剪切**退化为复制**:剪贴板照拿选区(上一行已经拿了),表里一格不清。
    与 TTyEdit.CutToClipboard 完全同规(Edit.pas:1684 `if FReadOnly then begin
    CopyToClipboard; Exit end`)——"只读=能看能拷、不能改"是本库每个编辑控件的含义。
    LCL 的网格在 EditingAllowed=False 时剪切干脆什么都不做(grids.pas:11753),
    这里保住复制那一半,跟自己库里的编辑控件对齐,不跟 LCL 的网格。
    放在 BeginUpdate 之前:被拒的手势不该开事务(空事务虽被 PushUndoStep 丢弃,
    但"否决在开事务之前"是 InsertRow 起就立下的规矩)。 }
  if FReadOnly then Exit;
  { 剪掉一片 = **一条**撤销记录。逐格记的话,剪 20 格要按 20 次 Ctrl+Z。 }
  BeginUpdate;
  try
    for pos := 0 to DisplayRowCount - 1 do
    begin
      dataRow := DisplayToData(pos);
      if dataRow < 0 then Continue;
      for colIdx := 0 to Header.Columns.Count - 1 do
        if IsCellSelected(colIdx, dataRow)
           and (EditorKindFor(colIdx, dataRow) <> gekNone) then    { 只读格不清 }
          Cells[colIdx, dataRow] := '';
    end;
  finally
    EndUpdate;
  end;
  Invalidate;
end;

function TTyStringGrid.CanInsertRow(ARow: Integer): Boolean;
begin
  Result := True;
  if Assigned(FOnCanInsertRow) then FOnCanInsertRow(Self, ARow, Result);
end;

function TTyStringGrid.CanDeleteRow(ARow: Integer): Boolean;
begin
  Result := True;
  if Assigned(FOnCanDeleteRow) then FOnCanDeleteRow(Self, ARow, Result);
end;

procedure TTyStringGrid.InsertRow(ARow: Integer);
begin
  { 整个操作算**一条**撤销记录:它内部搬很多格子,逐格记的话
    用户得按几十次 Ctrl+Z 才退得回来。批量重画的边界与撤销事务的边界
    本来就该是同一个。 }
  if (ARow < 0) or (ARow > RowCount) then Exit;
  if not CanInsertRow(ARow) then Exit;   { 否决要在开事务**之前**,别留个空事务 }
  BeginUpdate;
  try
  EndEdit(True);
  ShiftCells(ARow, 1, True);
  RowCount := RowCount + 1;
  InvalidateOrder;
  Invalidate;
  finally
    EndUpdate;
  end;
end;

procedure TTyStringGrid.DeleteRow(ARow: Integer);
begin
  { 整个操作算**一条**撤销记录:它内部搬很多格子,逐格记的话
    用户得按几十次 Ctrl+Z 才退得回来。批量重画的边界与撤销事务的边界
    本来就该是同一个。 }
  if (ARow < 0) or (ARow >= RowCount) then Exit;
  if not CanDeleteRow(ARow) then Exit;
  BeginUpdate;
  try
  EndEdit(False);
  ShiftCells(ARow, -1, True);
  RowCount := RowCount - 1;
  if FRow > RowCount - 1 then FRow := RowCount - 1;
  if FRow < 0 then FRow := 0;
  InvalidateOrder;
  Invalidate;
  finally
    EndUpdate;
  end;
end;

procedure TTyStringGrid.InsertColumn(ACol: Integer);
var
  c: TTyColumn;
begin
  { 整个操作算**一条**撤销记录:它内部搬很多格子,逐格记的话
    用户得按几十次 Ctrl+Z 才退得回来。批量重画的边界与撤销事务的边界
    本来就该是同一个。 }
  BeginUpdate;
  try
  if (ACol < 0) or (ACol > Header.Columns.Count) then Exit;
  EndEdit(True);
  ShiftCells(ACol, 1, False);
  c := Header.Columns.Add;
  { 新列按 DefaultColWidth 起宽(LCL 的 DefaultColWidth 就管这件事)。
    TTyColumn.Create 里那个 100 仍在,但那是"没人管的时候的宽度";
    网格有意见时该由网格说了算,否则这个属性只在设计器里好看。 }
  c.Width := GetDefaultColWidth;
  c.Index := ACol;
  { **在格子搬移之后**记 —— 撤销是倒序应用的,这一条要最先跑
    (先把列去掉,后面的 gukCell 条目才有正确的落点)。 }
  RecordColumnUndo(gukColInsert, ACol);
  Invalidate;
  finally
    EndUpdate;
  end;
end;

procedure TTyStringGrid.DeleteColumn(ACol: Integer);
var
  snap: TTyGridColumnSnapshot;
begin
  { 整个操作算**一条**撤销记录:它内部搬很多格子,逐格记的话
    用户得按几十次 Ctrl+Z 才退得回来。批量重画的边界与撤销事务的边界
    本来就该是同一个。 }
  BeginUpdate;
  try
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  EndEdit(False);
  { 快照要在**删之前**取(那时列还在),条目要在**删之后**入栈
    (撤销倒序应用,列得先回来,后面的 gukCell 才有地方放)。 }
  snap := SnapshotColumn(ACol);
  ShiftCells(ACol, -1, False);
  Header.Columns.Delete(ACol);
  if FCol > Header.Columns.Count - 1 then FCol := Header.Columns.Count - 1;
  if FCol < 0 then FCol := 0;
  RecordColumnUndo(gukColDelete, ACol, -1, snap);
  Invalidate;
  finally
    EndUpdate;
  end;
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
  { 全表一次自适应 = **一条**撤销记录。行高有记录点,逐行调的话
    十万行的表就是十万条 —— 与涂色/粘贴/批量增删行同一族。 }
  BeginUpdate;
  try
    for i := 0 to RowCount - 1 do AutoFitRow(i);
  finally
    EndUpdate;
  end;
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
  keys: TStringList;
begin
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  { 1x1 的临时位图只用来量文字 —— 不需要画布,也不需要窗口句柄。 }
  bmp := TBGRABitmap.Create(1, 1);
  try
    cSty := ActiveController.Model.ResolveStyle('TyGridCell', StyleClass, []);
    hSty := ActiveController.Model.ResolveStyle('TyGridHeader', StyleClass, []);

    widest := TextW(TTyColumn(Header.Columns.Items[ACol]).Text, hSty);

    { 只量**写过的**格 —— 稀疏存储让百万行空表也只走几条记录,不必扫全表。 }
    keys := TStringList.Create;
    try
      SnapshotCellKeys(keys);
      for i := 0 to keys.Count - 1 do
      begin
        k := keys[i];
        sep := Pos(':', k);
        c := StrToIntDef(Copy(k, 1, sep - 1), -1);
        if c <> ACol then Continue;
        r := StrToIntDef(Copy(k, sep + 1, MaxInt), -1);
        w := TextW(GetCellText(ACol, r), cSty);
        if w > widest then widest := w;
      end;
    finally
      keys.Free;
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
  { 单列分组就是多列的退化情形 —— 只留一条路径,免得两套实现日后走样。 }
  if (ACol < 0) or (ACol >= Header.Columns.Count) then GroupByColumns([])
  else GroupByColumns([ACol]);
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
  { 折叠状态按**层级路径**记账,而不是按组号(重排/筛选后组号会变),
    也不是按单个键 —— 按单个键的话,"华东/上海"和"华北/上海"会被一起折叠。 }
  key := FGroups[AIndex].Path;
  i := FCollapsed.IndexOf(key);
  if i >= 0 then FCollapsed.Delete(i) else FCollapsed.Add(key);
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

function TTyStringGrid.GroupToggleRect(APos: Integer): TRect;
var
  r: TRect;
  box, cy, ind, gi: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  r := TyGridRowRect(APos, GridMetrics);
  if r.Bottom <= r.Top then Exit;
  box := ScaleI(12);
  cy := (r.Top + r.Bottom) div 2;
  { 按层级缩进 —— 多级分组时不缩进的话,两级分组行长得一模一样,
    根本看不出谁包着谁。命中走的也是这个矩形,所以点得到的就是看得见的那一个。 }
  ind := ScaleI(4);
  if IsGroupRow(APos, gi) and (gi >= 0) and (gi <= High(FGroups)) then
    Inc(ind, FGroups[gi].Level * ScaleI(14));
  { 缩进从**阅读起点**起算,反射一次落到屏幕上。绘制与命中读的都是这一个矩形,
    所以三角换边时点击面一起换 —— 它们本来就不可能是两处。 }
  Result := ToScreenRect(Rect(ind, cy - box div 2, ind + box, cy - box div 2 + box));
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
  sub, colR: TRect;
begin
  r := TyGridRowRect(APos, M);
  if (r.Bottom <= M.FrozenTop) or (r.Top >= M.ClientH) then Exit;

  info := GroupInfo(AGroupIndex);
  gS := ActiveController.Model.ResolveStyle('TyGridGroupRow', StyleClass, CurrentStates);
  if tpBackground in gS.Present then
    P.FillBackground(r, gS.Background, 0);
  if tpTextColor in gS.Present then ink := gS.TextColor else ink := AFrame.TextColor;

  { 折叠三角:展开时朝下,折叠时朝阅读前进的方向 —— 与树的约定一致,同一个函数。 }
  tg := GroupToggleRect(APos);
  if not IsRectEmpty(tg) then
    DrawToggleGlyph(P, tg, info.Collapsed, ink);

  { 分组小计:哪些列配了汇总方式,就在分组行的那几列上画出本组的小计。
    复用页脚那套列定位与冻结带裁剪 —— 同一个数在两处该长得一样、也该
    对齐在同一列下面。 }
  { keyRight 与后面那条标题矩形整段都写在**阅读空间**里 —— 它是一条
    "标题从三角之后一直铺到第一个小计之前"的规则,与方向无关;
    最后整条反射一次落到屏幕上。分开在两个空间里写就会出现
    "三角在右、标题往左量、小计在左"这种各说各话。 }
  keyRight := ToReadingRect(Rect(0, 0, M.ClientW, 0)).Right - ScaleI(4);
  if FShowGroupSubtotals then
    for i := 0 to Header.Columns.Count - 1 do
    begin
      cRef := TTyColumn(Header.Columns.Items[i]);
      if not (coVisible in cRef.Options) then Continue;
      txt := GroupFooterText(AGroupIndex, i);
      if txt = '' then Continue;
      l := ColumnLeftPx(i);
      w := ColumnWidthPx(i);
      if not ClipColToBody(M, i, l, w) then Continue;
      if (l >= M.ClientW) or (l + w <= 0) then Continue;
      { 组标题不能压到小计上 —— 让它在**阅读序上最靠前**的那个小计列之前收住。 }
      colR := ToReadingRect(Rect(l, 0, l + w, 0));
      if colR.Left - ScaleI(6) < keyRight then keyRight := colR.Left - ScaleI(6);
      sub := Rect(l + ScaleI(4), r.Top, l + w - ScaleI(4), r.Bottom);
      if sub.Right > sub.Left then
        P.DrawText(sub, txt, gS.FontName, ResolveFontSize(gS), gS.FontWeight,
          ink, taRightJustify, tlCenter, True);
    end;

  tr := ToScreenRect(Rect(ToReadingRect(tg).Right + ScaleI(6), r.Top, keyRight, r.Bottom));
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
  InvalidateAggregates;      { 换了口径,缓存里那个数已经不是要的那个了 }
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
  started, cacheable, handled: Boolean;
begin
  Result := 0;

  { 宿主接管这一列?接管了就**直接返回**,连 gagNone 的判断都不做 ——
    宿主可能想给一个根本没配聚合口径的列显示合计。
    而且**不进缓存**:值由宿主随时给,控件收不到"外部数据变了"的通知,
    缓存住就是把一个陈旧的数钉在页脚上(与虚拟数据源同一条理由)。 }
  if Assigned(FOnColumnCalc) then
  begin
    handled := False;
    FOnColumnCalc(Self, ACol, Result, handled);
    if handled then Exit;
  end;

  kind := ColumnAggregate(ACol);
  if kind = gagNone then Exit;

  { 只遍历**显示序** —— 被过滤掉的行不参与统计,筛完总计立刻跟着变。 }
  if kind = gagCount then
  begin
    Result := DisplayRowCount;      { O(1),不必缓存 }
    Exit;
  end;

  { 页脚**每帧**都要问一次,而下面那一趟遍历的是全部显示行 ——
    百万行的表滚动时就是每帧一次 O(n)。缓存按列存,失效收口在
    InvalidateAggregates(数据改 / 显示序变 / 换聚合口径三处汇过去)。

    挂了 OnGetCellText 的表**不缓存**:值由宿主随时给,控件收不到"变了"的
    通知,缓存住就等于把一个陈旧的合计钉在页脚上 —— 那比慢糟得多。
    (与 CanSortPhysically 拒绝虚拟源同一条道理。) }
  cacheable := (ACol >= 0) and (not Assigned(FOnGetCellText));
  if cacheable then
  begin
    if Length(FAggValid) <> Header.Columns.Count then
    begin
      SetLength(FAggValid, Header.Columns.Count);
      SetLength(FAggCache, Header.Columns.Count);
      for n := 0 to High(FAggValid) do FAggValid[n] := False;
    end;
    if (ACol <= High(FAggValid)) and FAggValid[ACol] then
      Exit(FAggCache[ACol]);
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

  { n = 0(整列一格数值都没有)也要记进缓存,否则空列每帧照样白扫一遍全表。 }
  if n > 0 then
    if kind = gagAvg then Result := acc / n else Result := acc;

  if cacheable and (ACol <= High(FAggValid)) then
  begin
    FAggCache[ACol] := Result;
    FAggValid[ACol] := True;
  end;
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
    { 与单元格同一条裁剪规则:滚到冻结带底下的部分不露出来。收口在 ClipColToBody。 }
    if not ClipColToBody(M, i, l, w) then Continue;
    if (l >= M.ClientW) or (l + w <= 0) then Continue;
    r := Rect(l + ScaleI(4), AFooterRect.Top, l + w - ScaleI(4), AFooterRect.Bottom);
    if r.Right > r.Left then
      P.DrawText(r, txt, fS.FontName, ResolveFontSize(fS), fS.FontWeight,
        ink, cRef.Alignment, tlCenter, True);
  end;
end;

function TTyStringGrid.CellRect(ACol, ARow: Integer): TRect;
var
  cs, rs, bc, br, lastPos, sl, sr: Integer;
  r2: TRect;
begin
  Result := inherited CellRect(ACol, ARow);
  if IsRectEmpty(Result) then Exit;

  if CellSpan(ACol, ARow, cs, rs) then
  begin
    { 基准格:向**阅读方向**吃 cs 列、向下吃 rs 行(按显示序)。
      走 ColumnSpanX:RTL 下末列在左,写 `Result.Right := 末列右缘`
      会得到一个反向矩形 —— 合并格于是整块消失。 }
    if cs > 1 then
      if ColumnSpanX(ACol, Min(ACol + cs, Header.Columns.Count) - 1, sl, sr) then
      begin
        Result.Left := sl;
        Result.Right := sr;
      end;
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

procedure TTyStringGrid.RecordRowCountUndo(AOldCount: Integer);
var
  e: TTyGridUndoEntry;
begin
  { 行数变了也算"改过"。SetCells 那个收口点接不到这一条:往空表里插一行
    一个格子都没搬,可表确实不一样了。撤销/重做也走这里,与 SetCells 同样对待
    (Ctrl+Z 之后仍算改过 —— 它未必回到了存盘时的样子)。 }
  FModified := True;
  if FUndoBusy then Exit;
  e.Kind := gukRowCount;
  e.Col := -1;
  e.Row := -1;
  e.OldText := '';
  e.OldCount := AOldCount;
  RecordUndo(e);
end;

procedure TTyStringGrid.OpenUndoGroup;
begin
  if FUndoBusy or (FUndoLimit = 0) then Exit;
  Inc(FUndoDepth);
  if FUndoDepth = 1 then
  begin
    SetLength(FUndoOpen, 0);
    FUndoOverflow := False;
  end;
end;

procedure TTyStringGrid.CloseUndoGroup;
begin
  if FUndoBusy or (FUndoLimit = 0) then Exit;
  if FUndoDepth = 0 then Exit;
  Dec(FUndoDepth);
  if FUndoDepth > 0 then Exit;          { 嵌套内层不结算 }
  if not FUndoOverflow then
  begin
    PushUndoStep(FUndoOpen);
    if Length(FUndoOpen) > 0 then SetLength(FRedoStack, 0);
  end;
  SetLength(FUndoOpen, 0);
  FUndoOverflow := False;
end;

procedure TTyStringGrid.DoRowDragMove(AFrom, ATo: Integer);
begin
  MoveRow(AFrom, ATo);
end;

{ 直接看**实际的显示序**是不是恒等,而不是猜"有没有排序/分组/筛选"。
  更准:按一个本来就有序的列排出来仍然是恒等,这时没有任何理由拒绝合并或拖行;
  物理排序之后更是必然恒等 —— 那几条限制就此自动解除,不必再逐处去改。 }
function TTyStringGrid.DisplayOrderIsDataOrder: Boolean;
begin
  EnsureOrder;
  Result := FOrderIsIdentity and (Length(FGroupCols) = 0);
end;

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

{ 选区在客户区里的外接矩形(显示序 → 像素)。 }
function TTyStringGrid.SelectionBoundsRect: TRect;
var
  r: TRect;
  tl, br: TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if Header.Columns.Count = 0 then Exit;
  r := ActiveSelectionRect;                 { 显示序空间 }
  tl := CellRect(r.Left, DisplayToData(r.Top));
  br := CellRect(r.Right, DisplayToData(r.Bottom));
  if IsRectEmpty(tl) or IsRectEmpty(br) then Exit;
  { 横轴取两端的并集,不是 `tl.Left .. br.Right`:r.Left / r.Right 是**列下标**
    (锚点与角落,与像素无关,所以它们不镜像),而 RTL 下下标小的那一列在屏幕右边
    —— 直接拼两端会得到一个反向矩形,选区外框与填充柄一起消失。 }
  Result := Rect(tl.Left, tl.Top, br.Right, br.Bottom);
  if br.Left < Result.Left then Result.Left := br.Left;
  if tl.Right > Result.Right then Result.Right := tl.Right;
end;

function TTyStringGrid.FillHandleRect: TRect;
var
  b, bb: TRect;
  sz: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  { 只读表**没有柄**:空矩形让绘制(RenderSelectionFrame)与命中(MouseDown)同时
    消失 —— 两处读的都是这一个矩形。画一个拖了没反应的柄,是"published 却不照办"
    的像素版;数据侧另有 FillFromSelectionTo 自己的守卫接住 API 直调。 }
  if FReadOnly then Exit;
  { No fill handle outside cell-selection mode — keep "what's drawn" == "what's hit". }
  if FSelectionMode <> gsmCell then Exit;
  b := SelectionBoundsRect;
  if IsRectEmpty(b) then Exit;
  sz := ScaleI(6);
  { 贴在选区的**尾下角**、略微外探一点 —— 与 Excel 的手感一致,也更好点中。
    绘制(RenderSelectionFrame)与命中(MouseDown)读的都是这一个矩形。 }
  bb := ToReadingRect(b);
  Result := ToScreenRect(Rect(bb.Right - sz, b.Bottom - sz, bb.Right + 1, b.Bottom + 1));
end;

{ 源区里某一列是不是等差数列;是则给出首项与公差。
  只认整数:'10','20' 这种。浮点的等差在表格里少见,而误判的代价是把
  用户的数据算错 —— 宁可退回"循环重复"。 }
function TTyStringGrid.ArithmeticStep(ACol, AFrom, ATo: Integer;
  out AFirst, AStep: Integer): Boolean;
var
  r, v, prev, d: Integer;
  started: Boolean;
begin
  Result := False;
  AFirst := 0;
  AStep := 0;
  if ATo <= AFrom then Exit;                 { 单格不算数列 }
  started := False;
  prev := 0;
  d := 0;
  for r := AFrom to ATo do
  begin
    if not TryStrToInt(Trim(GetCellText(ACol, r)), v) then Exit;
    if r = AFrom then AFirst := v
    else
    begin
      if not started then
      begin
        d := v - prev;
        started := True;
      end
      else if v - prev <> d then Exit;       { 不是等差 }
    end;
    prev := v;
  end;
  if not started then Exit;
  AStep := d;
  Result := True;
end;

procedure TTyStringGrid.FillFromSelectionTo(ACol, ARow: Integer);
var
  src: TRect;
  tgt: TRect;
  handled: Boolean;
  c, r, n, srcH, idx, first, step: Integer;
begin
  { ReadOnly 下填充被拒。柄本身在 FillHandleRect 里已经变空(不画、点不中),
    这一句守的是 API 直调 —— 宿主自己的"向下填充"菜单项也改不了只读表。
    放在 OnFillCells 之前,与粘贴那头同一个理由:不请宿主否决一个不会发生的操作。 }
  if FReadOnly then Exit;
  src := Selection;                          { 数据行坐标 }
  if (src.Right < src.Left) or (src.Bottom < src.Top) then Exit;
  if ARow < 0 then ARow := 0;
  if ARow > RowCount - 1 then ARow := RowCount - 1;

  { 只支持**纵向**填充 —— 横向拖柄在表格里远没那么常用,而做一半的
    可供性比没有更糟。柄拖到源区之内(往回缩)也不做。 }
  if ARow <= src.Bottom then Exit;
  tgt := Rect(src.Left, src.Bottom + 1, src.Right, ARow);

  handled := False;
  if Assigned(FOnFillCells) then FOnFillCells(Self, src, tgt, handled);
  if handled then Exit;

  srcH := src.Bottom - src.Top + 1;
  BeginUpdate;
  try
    for c := src.Left to src.Right do
    begin
      { 逐格/逐列只读走 EditorKindFor 这同一道门 —— 粘贴(PasteFromText)与剪切
        (CutToClipboard)一直这么问,填充从前**不问**,于是同一格"不能改"对三条
        路径答两种话。跳过的是**写入**,计数器照走:位置阶梯保持一致,10,20 铺过
        一格锁定的第 3 行得到 30,_,50,而不是 30,_,40(等差的值由**位置**定,
        不由"跳过了几个"定;循环重复分支同理)。 }
      if ArithmeticStep(c, src.Top, src.Bottom, first, step) then
      begin
        { 等差:接着往下推。 }
        n := 1;
        for r := tgt.Top to tgt.Bottom do
        begin
          if EditorKindFor(c, r) <> gekNone then
            Cells[c, r] := IntToStr(first + (srcH - 1 + n) * step);
          Inc(n);
        end;
      end
      else
      begin
        { 其余:按源区循环重复(单格时退化成复制)。 }
        idx := 0;
        for r := tgt.Top to tgt.Bottom do
        begin
          if EditorKindFor(c, r) <> gekNone then
            Cells[c, r] := GetCellText(c, src.Top + (idx mod srcH));
          Inc(idx);
        end;
      end;
    end;
  finally
    EndUpdate;
  end;

  { 与 Excel 一致:填完之后选区覆盖到新范围。 }
  SelectRange(src.Left, src.Top, src.Right, tgt.Bottom);
end;

const
  { 版式串的头。版本号独立于控件版本 —— 只有**格式**变了才动它。 }
  TyGridLayoutTag = 'TYGRIDLAYOUT/1';
  { 全状态流(SaveToStream / LoadFromStream)的头。同一条纪律:版本号跟格式走。
    读的时候第一行不等于它就直接抛 —— 有头才分得清"这是我们的流"和
    "这是别人喂来的一段 CSV"。 }
  TyGridStateTag = 'TYGRIDSTATE/1';
  { 头部字段与内容之间的分界行。内容段可以含换行(引号内的),所以它只能是
    "这一行之后全是内容",不能再按行找边界。 }
  TyGridStateContentMark = 'csv';
  { 全状态流内容段的分隔符。固定成逗号(不给调用方选):文件是我们自己读回来的,
    分隔符可配只会多出一个"存的时候用了什么"必须一起存下来的状态。 }
  TyGridStateDelim = ',';

function TTyStringGrid.SaveLayoutToString: string;
var
  i: Integer;
  c: TTyColumn;          { 别叫 col —— 与网格的 Col 属性撞名 }
  colTxt, sorts: string; { 别叫 cols —— 同理,与 Cols[] 属性撞名 }
begin
  colTxt := '';
  for i := 0 to Header.Columns.Count - 1 do
  begin
    c := TTyColumn(Header.Columns.Items[i]);
    if colTxt <> '' then colTxt := colTxt + ',';
    colTxt := colTxt + Format('%d:%d:%d',
      [c.Width, Ord(coVisible in c.Options), c.Position]);
  end;

  sorts := '';
  for i := 0 to High(FSortKeys) do
  begin
    if sorts <> '' then sorts := sorts + ',';
    sorts := sorts + Format('%d:%d', [FSortKeys[i].Col, Ord(FSortKeys[i].Dir)]);
  end;

  Result := Format('%s|cols=%s|sort=%s|frozen=%d,%d,%d,%d',
    [TyGridLayoutTag, colTxt, sorts,
     FFixedCols, EffectiveFixedColsRight, FFixedRows, FFixedRowsBottom]);
end;

function TTyStringGrid.LoadLayoutFromString(const AText: string): Boolean;
var
  parts, one, fields: TStringList;
  i, n: Integer;
  colsTxt, sortTxt, frozenTxt: string;
  w, vis, pos: Integer;
  { 先全解析到这里,全部合法了再往控件上写 —— 半套版式比不还原更难查。 }
  newW, newVis, newPos: array of Integer;
  newSortCol, newSortDir: array of Integer;
  fl, fr, ft, fb: Integer;

  function Field(const ASrc, AName: string): string;
  var j: Integer;
  begin
    Result := '';
    for j := 0 to parts.Count - 1 do
      if Copy(parts[j], 1, Length(AName) + 1) = AName + '=' then
        Exit(Copy(parts[j], Length(AName) + 2, MaxInt));
  end;

  function ParseIntStrict(const ATxt: string; out AValue: Integer): Boolean;
  begin
    Result := TryStrToInt(Trim(ATxt), AValue);
  end;

begin
  Result := False;
  if AText = '' then Exit;

  parts := TStringList.Create;
  one := TStringList.Create;
  fields := TStringList.Create;
  try
    parts.Delimiter := '|';
    parts.StrictDelimiter := True;
    parts.DelimitedText := AText;
    if parts.Count = 0 then Exit;
    { 版本对不上就**什么都不做** —— 猜着读一个不认识的格式只会读出垃圾。 }
    if parts[0] <> TyGridLayoutTag then Exit;

    colsTxt := Field(AText, 'cols');
    sortTxt := Field(AText, 'sort');
    frozenTxt := Field(AText, 'frozen');

    { --- 列 --- }
    one.Delimiter := ',';
    one.StrictDelimiter := True;
    one.DelimitedText := colsTxt;
    if one.Count <> Header.Columns.Count then Exit;   { 列数对不上,整串作废 }
    SetLength(newW, one.Count);
    SetLength(newVis, one.Count);
    SetLength(newPos, one.Count);
    for i := 0 to one.Count - 1 do
    begin
      fields.Delimiter := ':';
      fields.StrictDelimiter := True;
      fields.DelimitedText := one[i];
      if fields.Count <> 3 then Exit;
      if not ParseIntStrict(fields[0], w) then Exit;
      if not ParseIntStrict(fields[1], vis) then Exit;
      if not ParseIntStrict(fields[2], pos) then Exit;
      if w < 0 then Exit;
      newW[i] := w;
      newVis[i] := vis;
      newPos[i] := pos;
    end;

    { --- 排序键 --- }
    SetLength(newSortCol, 0);
    SetLength(newSortDir, 0);
    if Trim(sortTxt) <> '' then
    begin
      one.DelimitedText := sortTxt;
      SetLength(newSortCol, one.Count);
      SetLength(newSortDir, one.Count);
      for i := 0 to one.Count - 1 do
      begin
        fields.DelimitedText := one[i];
        if fields.Count <> 2 then Exit;
        if not ParseIntStrict(fields[0], w) then Exit;
        if not ParseIntStrict(fields[1], vis) then Exit;
        if (w < 0) or (w >= Header.Columns.Count) then Exit;
        newSortCol[i] := w;
        newSortDir[i] := vis;
      end;
    end;

    { --- 冻结数 --- }
    one.DelimitedText := frozenTxt;
    if one.Count <> 4 then Exit;
    if not ParseIntStrict(one[0], fl) then Exit;
    if not ParseIntStrict(one[1], fr) then Exit;
    if not ParseIntStrict(one[2], ft) then Exit;
    if not ParseIntStrict(one[3], fb) then Exit;
    if (fl < 0) or (fr < 0) or (ft < 0) or (fb < 0) then Exit;

    { --- 全部合法,现在才动控件 --- }
    BeginUpdate;
    try
      for i := 0 to High(newW) do
      begin
        TTyColumn(Header.Columns.Items[i]).Width := newW[i];
        if newVis[i] <> 0 then ShowColumn(i) else HideColumn(i);
        TTyColumn(Header.Columns.Items[i]).Position := newPos[i];
      end;
      FixedCols := fl;
      FixedColsRight := fr;
      FixedRows := ft;
      FixedRowsBottom := fb;

      SetLength(FSortKeys, Length(newSortCol));
      for i := 0 to High(newSortCol) do
      begin
        FSortKeys[i].Col := newSortCol[i];
        FSortKeys[i].Dir := TTySortDirection(newSortDir[i]);
      end;
      if Length(FSortKeys) > 0 then
      begin
        FSortCol := FSortKeys[0].Col;
        FSortDir := FSortKeys[0].Dir;
        Header.SortColumn := FSortCol;
        Header.SortDirection := FSortDir;
      end
      else
      begin
        FSortCol := -1;
        Header.SortColumn := NoColumn;
      end;
      InvalidateOrder;
      InvalidateColumnCache;
    finally
      EndUpdate;
    end;
    UpdateScrollBars;
    Invalidate;
    Result := True;
  finally
    fields.Free;
    one.Free;
    parts.Free;
  end;
end;

{ 这一列是不是某一级的分组列。去重要按"属于分组列集合"判,
  而不是"等于最外层那个" —— 后者正是上一版漏掉内层的原因。 }
function TTyStringGrid.IsGroupColumn(ACol: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to High(FGroupCols) do
    if FGroupCols[i] = ACol then Exit(True);
end;

function TTyStringGrid.GetGroupCol: Integer;
begin
  if Length(FGroupCols) = 0 then Result := -1 else Result := FGroupCols[0];
end;

function TTyStringGrid.GroupColumns: TTyIntArray;
var i: Integer;
begin
  SetLength(Result, Length(FGroupCols));
  for i := 0 to High(FGroupCols) do Result[i] := FGroupCols[i];
end;

procedure TTyStringGrid.GroupByColumns(const ACols: array of Integer);
var
  i, n: Integer;
begin
  SetLength(FGroupCols, 0);
  n := 0;
  for i := 0 to High(ACols) do
    if (ACols[i] >= 0) and (ACols[i] < Header.Columns.Count) then
    begin
      SetLength(FGroupCols, n + 1);
      FGroupCols[n] := ACols[i];
      Inc(n);
    end;
  FCollapsed.Clear;        { 层级变了,旧的折叠路径不再有意义 }
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
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
var
  cs, rs: Integer;
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
  { 合并成它已经是的那个跨度 = 不是一次改动(见 SetCellColor 里那段说明)。 }
  if CellSpan(ACol, ARow, cs, rs) and (cs = AColSpan) and (rs = ARowSpan) then Exit;
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
  if (a.ColSpan <= 1) and (a.RowSpan <= 1) then Exit;   { 本来就没合并 }
  a := FAttrs.Mutate(k);
  Dec(FMergeCount);
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
  { 一次清掉所有合并 = **一条**撤销记录。逐格记的话,清 20 处合并
    要按 20 次 Ctrl+Z —— 与粘贴/剪切/批量增删行同一族。 }
  BeginUpdate;
  keys := TStringList.Create;
  try
    FAttrs.SnapshotKeys(keys);
    for i := 0 to keys.Count - 1 do
    begin
      a := FAttrs.Find(keys[i]);
      if a = nil then Continue;
      { 本来就没合并的条目跳过 —— 否则每一条都发一次"即将改动",
        撤销栈里攒一堆什么都没变的条目(Ctrl+Z 一次看不出动静)。 }
      if (a.ColSpan <= 1) and (a.RowSpan <= 1) then Continue;
      a := FAttrs.Mutate(keys[i]);
      a.ColSpan := 1;
      a.RowSpan := 1;
      FAttrs.DropIfDefault(keys[i]);
    end;
    FMergeCount := 0;
  finally
    keys.Free;
    EndUpdate;
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

  { 全部替换 = **一条**撤销记录。逐格记的话,替换 30 处要按 30 次 Ctrl+Z,
    而且每一条都会清一次重做链;记录数还会把 UndoLimit(默认 100)撑爆,
    把用户之前的操作从栈底挤掉。
    单个替换(AAll = False)一格就结束,包不包都是一条 —— 一起包了更省事。 }
  BeginUpdate;
  try
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
  finally
    EndUpdate;
  end;
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
  sel: TRect;
  pos, cIdx, dataRow: Integer;
  sb: TStringList;
  line: string;
begin
  { **用** ActiveSelectionRect,不自己再算一遍 Min/Max ——
    从前这里有第二份同样的算式,而"锚点被筛掉时返回 -1"那个坑只在那一份里修了:
    屏幕上高亮的是一行(绘制走 IsCellSelected → ActiveSelectionRect),
    剪贴板里却是从表顶一路到光标的所有行,还多一行空的。
    粘回去会覆盖用户从没选过的行。 }
  sel := ActiveSelectionRect;         { 显示序空间,-1 已在那里处理过 }

  sb := TStringList.Create;
  try
    { 按**显示序**导出 —— 用户复制的是他看到的那块,不是底层行号区间。 }
    for pos := sel.Top to sel.Bottom do
    begin
      dataRow := DisplayToData(pos);
      if dataRow < 0 then Continue;   { 分组行不是数据,别导成一行空格子 }
      line := '';
      for cIdx := sel.Left to sel.Right do
      begin
        if cIdx > sel.Left then line := line + #9;
        line := line + GetCellText(cIdx, dataRow);
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
  { ReadOnly 拒绝**整个**粘贴 —— Ctrl+V 手势(PasteFromClipboard)与这个文本入口
    一视同仁:宿主把自己的"粘贴"菜单接到这里,接出来的必须还是只读表。
    与本库编辑控件同规(TTyEdit.PasteFromClipboard 开头就是 `if FReadOnly then
    Exit`,Edit.pas:1704),也与 LCL 网格一致(DoPasteFromClipboard 由
    EditingAllowed 把门,grids.pas:11768)。放在 OnClipboardPaste **之前**:
    不给宿主否决一个本就不会发生的操作的机会。程序化写入(Cells[..] :=、
    LoadFromCSVText)不受影响 —— ReadOnly 管用户,不管宿主。 }
  if FReadOnly then Exit;
  if AText = '' then Exit;
  EndEdit(True);

  txt := AText;
  allow := True;
  if Assigned(FOnClipboardPaste) then FOnClipboardPaste(Self, txt, allow);
  if not allow then Exit;

  lines := TStringList.Create;
  { **两层都要**:BeginUpdateOrder 压的是重排,BeginUpdate 开的才是撤销事务。
    只开前者的话,粘 4 格就压 4 条撤销记录 —— 用户得按 4 次 Ctrl+Z 才退得回去,
    而头文件里一直写着"一次批量操作算一条"。 }
  BeginUpdate;
  BeginUpdateOrder;
  try
    lines.Text := txt;
    { 末尾那个空行是 TStringList.Text 的产物,不是真的一行。 }
    while (lines.Count > 0) and (lines[lines.Count - 1] = '') do
      lines.Delete(lines.Count - 1);
    if lines.Count = 0 then Exit;

    startPos := DataToDisplay(FRow);
    { 光标那一行被筛掉/藏起来时它没有显示位置(-1)。不挡一下的话:
      第一行 `DisplayToData(-1)` = -1 被 Continue **静默丢掉**,其余每行往上错一位。
      退回显示位置 0 —— 与选区那处(SelectionAsText 的 startPos)同一个答案。 }
    if startPos < 0 then startPos := 0;

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
    EndUpdate;
  end;
  Invalidate;
end;

procedure TTyStringGrid.PasteFromClipboard;
begin
  if Clipboard.HasFormat(CF_TEXT) then PasteFromText(Clipboard.AsText);
end;

{ 一个 JSON 字符串字面量的转义。 }
function TyJsonQuote(const AValue: string): string;
var
  i: Integer;
  ch: Char;
begin
  Result := '"';
  for i := 1 to Length(AValue) do
  begin
    ch := AValue[i];
    case ch of
      '"':  Result := Result + '\"';
      '\': Result := Result + '\\';
      #8:   Result := Result + '\b';
      #9:   Result := Result + '\t';
      #10:  Result := Result + '\n';
      #12:  Result := Result + '\f';
      #13:  Result := Result + '\r';
    else
      { 其余控制字符走 \u 转义;可见字符(含 UTF-8 多字节)原样输出。 }
      if ch < #32 then Result := Result + Format('\u%.4x', [Ord(ch)])
      else Result := Result + ch;
    end;
  end;
  Result := Result + '"';
end;

function TTyStringGrid.SaveToJSONText: string;
var
  sb: TStringList;
  pos, cIdx, dataRow: Integer;
  line, key: string;
begin
  sb := TStringList.Create;
  try
    for pos := 0 to DisplayRowCount - 1 do
    begin
      dataRow := DisplayToData(pos);
      if dataRow < 0 then Continue;      { 分组行不是数据 —— 与 CSV/HTML 同规矩 }
      line := '  {';
      for cIdx := 0 to Header.Columns.Count - 1 do
      begin
        if cIdx > 0 then line := line + ', ';
        { 键取列标题;空标题退回 colN,否则会导出一个没有键的对象。
          标题重复时也会重复 —— JSON 允许,而"猜哪个是用户要的"更糟。 }
        key := TTyColumn(Header.Columns.Items[cIdx]).Text;
        if Trim(key) = '' then key := 'col' + IntToStr(cIdx);
        line := line + TyJsonQuote(key) + ': ' +
                TyJsonQuote(GetCellText(cIdx, dataRow));
      end;
      line := line + '}';
      if pos < DisplayRowCount - 1 then line := line + ',';
      sb.Add(line);
    end;

    if sb.Count = 0 then Exit('[]');
    Result := '[' + LineEnding + sb.Text + ']';
  finally
    sb.Free;
  end;
end;

function TTyStringGrid.SaveToCSVText(ADelimiter: Char;
  AFromRow, ARowCount, AFromCol, AColCount: Integer;
  AWriteTitles, AVisibleColumnsOnly: Boolean): string;
var
  sb: TStringList;
  pos, cIdx, dataRow, lastPos, lastCol: Integer;
  line: string;
  firstCol: Boolean;

  { 这一列要不要导。AVisibleColumnsOnly 关着时一律导(既有行为)。 }
  function Wanted(AIdx: Integer): Boolean;
  begin
    Result := (not AVisibleColumnsOnly)
              or (coVisible in Header.Columns.Items[AIdx].Options);
  end;

begin
  { 范围钳制。-1 = 全表 —— 缺省调用与从前逐字节一致。 }
  if AFromCol < 0 then AFromCol := 0;
  if AFromCol > Header.Columns.Count - 1 then AFromCol := Header.Columns.Count - 1;
  if AColCount < 0 then lastCol := Header.Columns.Count - 1
  else lastCol := AFromCol + AColCount - 1;
  if lastCol > Header.Columns.Count - 1 then lastCol := Header.Columns.Count - 1;

  if AFromRow < 0 then AFromRow := 0;
  if ARowCount < 0 then lastPos := DisplayRowCount - 1
  else lastPos := AFromRow + ARowCount - 1;
  if lastPos > DisplayRowCount - 1 then lastPos := DisplayRowCount - 1;

  sb := TStringList.Create;
  try
    { 表头一行(列标题),然后按显示序导出可见行。
      AWriteTitles=False 时**整行不写**(而不是写一行空的):headerless CSV 的
      第 0 行就该是第一条记录,占位空行会在下游变成一条全空的假记录。 }
    if AWriteTitles then
    begin
      line := '';
      firstCol := True;
      for cIdx := AFromCol to lastCol do
      begin
        if not Wanted(cIdx) then Continue;
        if not firstCol then line := line + ADelimiter;
        firstCol := False;
        line := line + TyCsvQuote(Header.Columns.Items[cIdx].Text, ADelimiter);
      end;
      sb.Add(line);
    end;

    for pos := AFromRow to lastPos do
    begin
      dataRow := DisplayToData(pos);
      { 分组行不导出 —— 与 HTML 导出同一条规矩。不跳的话每个组标题都变成
        一条全空的记录(`,,,`),导回来或用 Excel 打开就是凭空多出的空行。 }
      if dataRow < 0 then Continue;
      line := '';
      firstCol := True;
      for cIdx := AFromCol to lastCol do
      begin
        if not Wanted(cIdx) then Continue;
        { 分隔符跟着"写过第一列没有"走,而不是跟着 cIdx = AFromCol 走 ——
          跳过隐藏列之后,那个判据会在第一个导出的列前面多写一个分隔符,
          于是整行右移一格、与表头对不上。 }
        if not firstCol then line := line + ADelimiter;
        firstCol := False;
        line := line + TyCsvQuote(GetCellText(cIdx, dataRow), ADelimiter);
      end;
      sb.Add(line);
    end;
    Result := sb.Text;
  finally
    sb.Free;
  end;
end;




procedure TTyStringGrid.LoadFromCSVText(const AText: string; ADelimiter: Char;
  AAppend: Boolean; AMaxRows, AIgnoreRows: Integer; AUseTitles: Boolean;
  ASkipEmptyLines: Boolean);
var
  csvRows: TTyCsvRows;   { 别叫 rows —— 与 Rows[] 属性撞名 }
  i, j, dataRow, first, titleRows, taken, base, keep: Integer;

  { 这一条是不是"空行":没有字段,或者所有字段都是空串。
    `a,,b` 不是空行 —— 那是三个字段,中间那个恰好为空。 }
  function RowIsBlank(const ARow: TStringArray): Boolean;
  var
    k: Integer;
  begin
    for k := 0 to High(ARow) do
      if ARow[k] <> '' then Exit(False);
    Result := True;
  end;

begin
  EndEdit(False);
  { 字符级解析:引号内的换行不断行(见 TyCsvParse 的说明)。 }
  csvRows := TyCsvParse(AText, ADelimiter);

  { 空行剔除**在数到表头/AIgnoreRows 之前**做,否则"跳过前 2 条说明行"会把
    分隔用的空行数进去,而用户数的是看得见的那几条。
    对标 LCL LoadFromCSVStream 的 SkipEmptyLines(grids.pas:1811,默认 True)——
    这里默认 False,因为无条件保留空行是本库既有的行为,而空行在某些表里
    (定长块之间的分隔)是有意义的记录。 }
  if ASkipEmptyLines then
  begin
    keep := 0;
    for i := 0 to High(csvRows) do
      if not RowIsBlank(csvRows[i]) then
      begin
        csvRows[keep] := csvRows[i];
        Inc(keep);
      end;
    SetLength(csvRows, keep);
  end;

  if Length(csvRows) = 0 then Exit;

  { 第一行当表头:按它建列(列数不足就补)。
    追加模式下不动列标题 —— 追加的是数据,不是重新定义这张表。

    列的**补建**照做,AUseTitles 与否都一样:没有表头行时 csvRows[0] 是数据,但它
    有几个字段仍然就是这张表有几列 —— 不补的话第一条记录会被截掉右半边。 }
  while Header.Columns.Count < Length(csvRows[0]) do
    Header.Columns.Add;
  if AUseTitles and (not AAppend) then
    for j := 0 to High(csvRows[0]) do
      TTyColumn(Header.Columns.Items[j]).Text := csvRows[0][j];

  { 数据从第 1 行起(第 0 行是表头),再跳过 AIgnoreRows 条说明行。
    没有表头行时从第 0 行起 —— 不减这一行就会把第一条**记录**当标题吃掉。 }
  if AUseTitles then titleRows := 1 else titleRows := 0;
  first := titleRows + AIgnoreRows;
  if first < titleRows then first := titleRows;
  taken := Length(csvRows) - first;
  if taken < 0 then taken := 0;
  if (AMaxRows >= 0) and (taken > AMaxRows) then taken := AMaxRows;

  { 清空 + 改行数 + 逐格重填 = **一条**撤销记录。
    不包事务的话撤销一次只退回半张表 —— 那比"撤不回来"更难排查。
    (排序与筛选的重置不进撤销栈:那是"我此刻想怎么看",不是数据。) }
  BeginUpdate;
  try
    if AAppend then
      base := RowCount                   { 接在现有数据后面 }
    else
    begin
      ClearCells;
      ClearFilters;
      SortByColumn(-1, sdAscending);     { 导入后回到原始顺序 }
      base := 0;
    end;
    RowCount := base + taken;

    for i := 0 to taken - 1 do
    begin
      dataRow := base + i;
      for j := 0 to High(csvRows[first + i]) do
      begin
        if j >= Header.Columns.Count then Break;
        Cells[j, dataRow] := csvRows[first + i][j];
      end;
    end;
  finally
    EndUpdate;
  end;

  { 刚装载进来的表不算"改过"。装载途中每写一格都会把 FModified 置位,
    所以复位必须在最后 —— 与 LCL 在 LoadContent 末尾清 FModified 同一处。 }
  FModified := False;

  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

{ --- 流封装 ---
  两条一模一样的 UTF-8 无 BOM 读写,收口在这里,免得四个入口各写一遍。 }
procedure TyGridWriteUtf8(AStream: TStream; const AText: string);
var
  txt: UTF8String;
begin
  txt := UTF8String(AText);
  if Length(txt) > 0 then
    AStream.WriteBuffer(txt[1], Length(txt));
end;

function TyGridReadUtf8(AStream: TStream): string;
var
  txt: UTF8String;
  n: Int64;
begin
  n := AStream.Size - AStream.Position;
  if n <= 0 then Exit('');
  SetLength(txt, n);
  AStream.ReadBuffer(txt[1], n);
  Result := string(txt);
end;

procedure TTyStringGrid.SaveToCSVStream(AStream: TStream; ADelimiter: Char;
  AWriteTitles, AVisibleColumnsOnly: Boolean);
begin
  if AStream = nil then Exit;
  TyGridWriteUtf8(AStream, SaveToCSVText(ADelimiter, -1, -1, -1, -1,
    AWriteTitles, AVisibleColumnsOnly));
end;

procedure TTyStringGrid.LoadFromCSVStream(AStream: TStream; ADelimiter: Char;
  AUseTitles, ASkipEmptyLines: Boolean);
var
  txt: string;
begin
  if AStream = nil then Exit;
  txt := TyGridReadUtf8(AStream);
  if txt = '' then
  begin
    { 空流 = 空表。别把它当成"什么都不做" —— 那样调用方分不清
      "读了一张空表"和"根本没读"。 }
    ClearCells;
    RowCount := 0;
    Exit;
  end;
  { 位置参数一路数到底:LoadFromCSVText(文本, 分隔符, 追加, 上限, 跳过, 用表头)。
    AUseTitles 是**第六个**参数,别让它落到 AAppend/AMaxRows 上去。 }
  LoadFromCSVText(txt, ADelimiter, False, -1, 0, AUseTitles, ASkipEmptyLines);
end;

{ 全状态流的内容段:按**数据行序**导出,而 CSV 导出走的是显示序。

  这不是风格之争,是正确性:显示序里没有被筛掉的行(存下来就少数据),
  排过序的表读回来行号还会整体换一位,于是同一份文件里存着的光标、选区、
  冻结行数会全部指到别的行上去。全状态存的是"这张表",不是"这一屏"。 }
function TTyStringGrid.StateContentText: string;
var
  sb: TStringList;
  r, c: Integer;
  line: string;
begin
  sb := TStringList.Create;
  try
    line := '';
    for c := 0 to Header.Columns.Count - 1 do
    begin
      if c > 0 then line := line + TyGridStateDelim;
      line := line + TyCsvQuote(TTyColumn(Header.Columns.Items[c]).Text, TyGridStateDelim);
    end;
    sb.Add(line);

    for r := 0 to RowCount - 1 do
    begin
      line := '';
      for c := 0 to Header.Columns.Count - 1 do
      begin
        if c > 0 then line := line + TyGridStateDelim;
        line := line + TyCsvQuote(GetCellText(c, r), TyGridStateDelim);
      end;
      sb.Add(line);
    end;
    Result := sb.Text;
  finally
    sb.Free;
  end;
end;

procedure TTyStringGrid.SaveToStream(AStream: TStream);
var
  sb: TStringList;
begin
  if AStream = nil then Exit;
  sb := TStringList.Create;
  try
    sb.Add(TyGridStateTag);
    sb.Add('layout=' + SaveLayoutToString);
    sb.Add(Format('rows=%d', [RowCount]));
    { 位置存的是**锚点 + 光标**,而不是 Selection 给的那个规范化矩形。
      选区在本控件里就是"锚点到光标"这一对,矩形是它的投影 —— 光标可能落在
      矩形的任意一角。只存矩形的话读回来光标必定落在右下角,于是
      「从下往上选」的表 Shift+↑ 会往反方向走。两个坐标存两次,不多。
      (离散多选的 FSelRects 不存 —— 与逐格颜色同一条理由:见声明处。) }
    sb.Add(Format('anchor=%d,%d', [FSelAnchorCol, FSelAnchorRow]));
    sb.Add(Format('cursor=%d,%d', [FCol, FRow]));
    sb.Add(Format('scroll=%d,%d', [ScrollX, ScrollY]));
    { 内容**最后**写,而且用一行光杆标记开头:字段里可以合法地含换行
      (引号内的),所以内容必须是"从这行之后一直到流尾",不能再指望按行切。 }
    sb.Add(TyGridStateContentMark);
    TyGridWriteUtf8(AStream, sb.Text + StateContentText);
  finally
    sb.Free;
  end;
end;

procedure TTyStringGrid.LoadFromStream(AStream: TStream);
var
  lines, one: TStringList;
  i, mark, savedRows, anchorCol, anchorRow, savedCol, savedRow, sx, sy: Integer;
  layout, content: string;

  function Field(const AName: string): string;
  var
    j: Integer;
  begin
    Result := '';
    for j := 1 to mark - 1 do
      if Copy(lines[j], 1, Length(AName) + 1) = AName + '=' then
        Exit(Copy(lines[j], Length(AName) + 2, MaxInt));
  end;

  function IntField(const AName: string; ADefault: Integer): Integer;
  begin
    if not TryStrToInt(Trim(Field(AName)), Result) then Result := ADefault;
  end;

  { `a,b,c,d` 里的第 AIndex 个整数。缺项/坏项一律退回 ADefault。 }
  function IntAt(const ACsv: string; AIndex, ADefault: Integer): Integer;
  begin
    one.DelimitedText := ACsv;
    if (AIndex < 0) or (AIndex >= one.Count) then Exit(ADefault);
    if not TryStrToInt(Trim(one[AIndex]), Result) then Result := ADefault;
  end;

begin
  if AStream = nil then Exit;
  lines := TStringList.Create;
  one := TStringList.Create;
  try
    one.Delimiter := ',';
    one.StrictDelimiter := True;
    lines.Text := TyGridReadUtf8(AStream);

    { 认不出格式就**抛**,不猜。回退去读 CSV 的话就又回到了
      "同一个调用两种格式,而且分不出拿到的是哪一种"。
      喂 CSV 的调用方要的是 LoadFromCSVStream,消息里直接说。 }
    mark := -1;
    if (lines.Count > 0) and (lines[0] = TyGridStateTag) then
      for i := 1 to lines.Count - 1 do
        if lines[i] = TyGridStateContentMark then
        begin
          mark := i;
          Break;
        end;
    if mark < 0 then
      raise EReadError.Create('TTyStringGrid.LoadFromStream: not a ' + TyGridStateTag
        + ' stream. Plain CSV goes through LoadFromCSVStream.');

    layout := Field('layout');
    savedRows := IntField('rows', -1);
    anchorCol := IntAt(Field('anchor'), 0, 0);
    anchorRow := IntAt(Field('anchor'), 1, 0);
    savedCol := IntAt(Field('cursor'), 0, 0);
    savedRow := IntAt(Field('cursor'), 1, 0);
    sx := IntAt(Field('scroll'), 0, 0);
    sy := IntAt(Field('scroll'), 1, 0);

    content := '';
    for i := mark + 1 to lines.Count - 1 do
      content := content + lines[i] + LineEnding;

    { 顺序是有讲究的:先读内容(它按标题行把列建出来并填满数据),
      版式才有列可落 —— LoadLayoutFromString 要求列数完全对得上,
      先落版式的话它会因为列还没建出来而整串作废。 }
    LoadFromCSVText(content, TyGridStateDelim, False, -1, 0, True);
    { 存的行数说了算:全空的尾行在 CSV 里长得跟"没有这一行"一样。 }
    if (savedRows >= 0) and (savedRows <> RowCount) then RowCount := savedRows;
    if layout <> '' then LoadLayoutFromString(layout);

    { 锚点与光标一次落位。**用 SelectRange 而不是 MoveCursor**:MoveCursor 会
      重锚(选区塌成一格)并且顺手 ScrollIntoView —— 把刚要还原的滚动位置冲掉。 }
    SelectRange(anchorCol, anchorRow, savedCol, savedRow);
    { 滚动**最后**还原,前面几步都可能动它。 }
    ScrollX := sx;
    ScrollY := sy;
    { 刚读进来的表不算改过 —— 见 Modified 与 LoadFromCSVText 里的同一句。 }
    FModified := False;
  finally
    one.Free;
    lines.Free;
  end;
end;

procedure TTyStringGrid.SaveToCSVFile(const AFileName: string; ADelimiter: Char;
  AWriteTitles, AVisibleColumnsOnly: Boolean);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Text := SaveToCSVText(ADelimiter, -1, -1, -1, -1,
      AWriteTitles, AVisibleColumnsOnly);
    sl.SaveToFile(AFileName);
  finally
    sl.Free;
  end;
end;

procedure TTyStringGrid.LoadFromCSVFile(const AFileName: string; ADelimiter: Char;
  AUseTitles, ASkipEmptyLines: Boolean);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(AFileName);
    LoadFromCSVText(sl.Text, ADelimiter, False, -1, 0, AUseTitles, ASkipEmptyLines);
  finally
    sl.Free;
  end;
end;

procedure TTyStringGrid.SaveToFile(const AFileName: string);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    SaveToStream(fs);
  finally
    fs.Free;
  end;
end;

procedure TTyStringGrid.LoadFromFile(const AFileName: string);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadFromStream(fs);
  finally
    fs.Free;
  end;
end;

{ 现在能不能安全地物理排序。 }
function TTyStringGrid.CanSortPhysically: Boolean;
begin
  Result := (FSortMode = gsmData)
            { 有筛选就不行:被筛掉的行也在数据里,一起搬会把它们搬乱。 }
            and (FColFilters.Count = 0) and (FValFilters.Count = 0)
            and (FHiddenRows.Count = 0)
            and (Length(FGroupCols) = 0)
            { 数据由回调提供时控件根本不持有它,没什么可搬的。 }
            { 数据由回调提供时控件根本不持有它,物理搬只会搬存储的那一半、
              让两边错位。**这一条目前测不出来**:排序的比较读的是存储而不是
              GetCellText,所以虚拟表根本排不出非恒等的序(见计划文件里记的那条
              缺口)。留着是因为它在"排序开始认回调"的那一天会立刻变成必需的 ——
              删掉等于给那次改动埋一颗雷。 }
            and (not Assigned(OnGetCellText));
end;

{ 按当前显示序把**数据**重排一遍,让数据行顺序与显示顺序一致。

  搬的是文字、逐格属性(底色/合并跨度/只读…)与显式行高 —— 凡是按行下标记账的
  都得跟着走,否则排完序底色会留在原地(这个坑在增删行那边踩过一次)。
  先整体快照再写回:边遍历边改会自己覆盖自己。
  写回走 Cells[] / 属性存储,所以整次排序**自动进撤销栈**;外面包了事务,
  因此是**一条**记录 —— 一次 Ctrl+Z 就退回排序前。 }
procedure TTyStringGrid.ApplyOrderToData;
type
  TCellSnap = record C, R: Integer; V: string; end;
var
  keys: TStringList;
  snap: array of TCellSnap;
  { 格属性按值快照。**不能存 TTyGridCellAttr 引用** —— 那是 FAttrs 持有的对象,
    先删后写会指向已释放的内存。 }
  attrSnap: array of record C, R: Integer; A: TTyGridCellAttr; end;
  attrKeys: TStringList;
  i, sep, c, r: Integer;
  k: string;
begin
  EnsureOrder;
  if Length(FRank) <> RowCount then Exit;

  { --- 快照 --- }
  keys := TStringList.Create;
  try
    SnapshotCellKeys(keys);
    SetLength(snap, keys.Count);
    for i := 0 to keys.Count - 1 do
    begin
      k := keys[i];
      sep := Pos(':', k);
      c := StrToIntDef(Copy(k, 1, sep - 1), -1);
      r := StrToIntDef(Copy(k, sep + 1, MaxInt), -1);
      snap[i].C := c;
      snap[i].R := r;
      snap[i].V := GetCells(c, r);
    end;
  finally
    keys.Free;
  end;

  { 属性快照:先把每条按值拷出来(FAttrs.Find 给的是它自己持有的对象)。 }
  attrKeys := TStringList.Create;
  try
    FAttrs.SnapshotKeys(attrKeys);
    SetLength(attrSnap, attrKeys.Count);
    for i := 0 to attrKeys.Count - 1 do
    begin
      k := attrKeys[i];
      sep := Pos(':', k);
      attrSnap[i].C := StrToIntDef(Copy(k, 1, sep - 1), -1);
      attrSnap[i].R := StrToIntDef(Copy(k, sep + 1, MaxInt), -1);
      attrSnap[i].A := TTyGridCellAttr.Create;
      attrSnap[i].A.Assign(FAttrs.Find(k));
    end;
  finally
    attrKeys.Free;
  end;

  { --- 写回 --- }
  BeginUpdate;
  try
    for i := 0 to High(snap) do
      Cells[snap[i].C, snap[i].R] := '';
    for i := 0 to High(snap) do
      if (snap[i].R >= 0) and (snap[i].R < RowCount) then
        Cells[snap[i].C, FRank[snap[i].R]] := snap[i].V;

    { 行高、隐藏标记等按行记账的旁挂状态 —— FRank 本身就是"旧行 → 新行"的映射。 }
    PermuteRowState(FRank);

    { 格属性:先全清再按新位置写回。分两遍 —— 边删边写会覆盖还没搬走的条目
      (与 ShiftCells 那边同一条道理)。 }
    for i := 0 to High(attrSnap) do
      if (attrSnap[i].R >= 0) and (attrSnap[i].R < RowCount) then
        FAttrs.Remove(CellKey(attrSnap[i].C, attrSnap[i].R));
    for i := 0 to High(attrSnap) do
      if (attrSnap[i].R >= 0) and (attrSnap[i].R < RowCount) then
        FAttrs.Ensure(CellKey(attrSnap[i].C, FRank[attrSnap[i].R]))
          .Assign(attrSnap[i].A);
  finally
    for i := 0 to High(attrSnap) do attrSnap[i].A.Free;
    EndUpdate;
  end;

  InvalidateOrder;    { 数据已经有序,重建出来就是恒等 }
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

  { 真的排一次序,指示器就该回来 —— HideSortArrow 说的是"这一次别画",
    不是"从此不画"(LCL 里 Sort 重新写 FSortColumn,效果一样)。 }
  FSortArrowHidden := False;
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

  { gsmData:把数据按刚排出来的显示序**真的搬一遍**(Excel 的做法)。
    搬完之后重建出来的显示序必然是恒等,于是"排过序就不让合并/不让拖行"
    那几条限制自动解除 —— 不需要去每一处逐个放行。 }
  if CanSortPhysically then
  begin
    ApplyOrderToData;
    EnsureOrder;
  end;
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
  { **每一个**分组列都要按序排在最前面,不能只排最外层。
    BuildGroups 完全靠相邻性切段(见它自己的注释),只排第一列的话第二级的键
    不连续 —— 同一个子组标题会在列表里反复出现,还各带一份错的计数与小计。
    (上一版只 prepend 了 FGroupCols[0];测试数据恰好本来就聚簇,于是全绿。) }
  SetLength(Result, Length(FGroupCols));
  for i := 0 to High(FGroupCols) do
  begin
    Result[i].Col := FGroupCols[i];
    Result[i].Dir := FSortDir;
  end;
  for i := 0 to High(FSortKeys) do
  begin
    if FSortKeys[i].Col < 0 then Continue;
    if IsGroupColumn(FSortKeys[i].Col) then Continue;
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
  FSortArrowHidden := False;   { 见 SortByColumn }
  for i := 0 to High(FSortKeys) do
    if FSortKeys[i].Col = ACol then
    begin
      { 已经是排序键了 —— 再点一次就翻方向,而不是加一条重复的键。 }
      FSortKeys[i].Dir := ADirection;
      if i = 0 then
      begin
        FSortCol := ACol;
        FSortDir := ADirection;
        { 表头也要同步。从前这一支没写,于是翻方向时小三角的朝向不跟着变
          (三角画的是 Header.SortDirection);HideSortArrow 之后再走到这一支
          还会让三角回不来。 }
        Header.SortColumn := ACol;
        Header.SortDirection := ADirection;
      end;
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
  FSortArrowHidden := False;   { 没有排序键了,"熄掉指示器"这个状态也就无从谈起 }
  Header.SortColumn := NoColumn;
  InvalidateOrder;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyStringGrid.HideSortArrow;
begin
  { 排序键**刻意不动**:显示序是由它们算出来的,清掉就等于把行顺序也退回去了,
    而这个方法的全部意义正是"顺序留着、只是别画那个三角"。
    (LCL 的排序是物理的,顺序留在数据里,所以它只需要清 FSortColumn。) }
  FSortArrowHidden := True;
  Header.SortColumn := NoColumn;
  Invalidate;
end;

function TTyStringGrid.GetModified: Boolean;
begin
  Result := FModified;
end;

procedure TTyStringGrid.SetModified(AValue: Boolean);
begin
  FModified := AValue;
end;

function TTyStringGrid.InplaceEditor: TWinControl;
var
  c: TControl;
begin
  { 与 EditorControl 同一个答案,只是收窄成 TWinControl(LCL 那边的类型)。
    两处不许各算一遍 —— 那正是"两个属性对不上"的做法。 }
  Result := nil;
  c := EditorControl;
  if c is TWinControl then Result := TWinControl(c);
end;

function TTyStringGrid.GetEditorMode: Boolean;
begin
  Result := FEditing;
end;

procedure TTyStringGrid.SetEditorMode(AValue: Boolean);
begin
  if AValue = FEditing then Exit;
  if AValue then BeginEdit
  else EndEdit(True);      { LCL 的 EditorMode := False 是提交,不是丢弃 }
end;

function TTyStringGrid.GetSelectedColumn: TTyGridColumn;
begin
  Result := GridColumn(FCol);
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
    if FCollapsed.IndexOf(FGroups[i].Path) < 0 then FCollapsed.Add(FGroups[i].Path);
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
var
  a, c: Integer;
begin
  a := DataToDisplay(FSelAnchorRow);
  c := DataToDisplay(FRow);
  { 被筛掉的行没有显示位置(-1)。把 -1 直接喂给 Min 的话选区就从 -1 起算,
    一路吃到显示位置 0 —— 筛掉锚点之后,选中范围反而**扩到表头**那边去了。
    锚点没了就退化成"只有光标那一行"。
    两端都没了则两个都还是 -1,行区间 [-1,-1] 里不可能有真实的显示位置
    (调用方喂的 rp 恒 >= 0)—— 那种情况本来就该什么都不选中,不必另开一路。 }
  if a < 0 then a := c;
  if c < 0 then c := a;

  Result.Left   := Min(FSelAnchorCol, FCol);
  Result.Right  := Max(FSelAnchorCol, FCol);
  Result.Top    := Min(a, c);
  Result.Bottom := Max(a, c);
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
  { rsmSingle = 只许有一块:固化就是这个功能的入口,在这里挡住比在 MouseDown 里
    判要牢靠 —— 键盘上将来若也有 Ctrl+空格,不必再挡一次。

    goRangeSelect 关掉时更彻底:一块都不许多出来。只挡拖选而放过 Ctrl+点 的话,
    "选区永远只有当前格"这句话就不成立了 —— 用户仍能攒出一把离散的单格。 }
  if FRangeSelectMode = rsmSingle then Exit;
  if not (goRangeSelect in Options) then Exit;
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
var
  pos, d, firstData, lastData: Integer;
begin
  SetLength(FSelRects, 0);
  if (Header.Columns.Count = 0) or (RowCount = 0) then Exit;

  { 显示序的两端**未必是数据行**:有分组时首行必是组标题,最后一组折叠着的话
    末行也是。组行的 DisplayToData 是负数,直接拿它当锚点的话
    `ActiveSelectionRect` 会把整个选区塌成光标那一格 —— Ctrl+A 只选中一行,
    接着的 Ctrl+C / 删除 / 涂色全都只作用于那一行。
    所以从两头各找**第一个真数据行**。 }
  firstData := -1;
  for pos := 0 to DisplayRowCount - 1 do
  begin
    d := DisplayToData(pos);
    if d >= 0 then begin firstData := d; Break; end;
  end;
  if firstData < 0 then Exit;        { 一行数据都没露出来(全折叠) }

  lastData := firstData;
  for pos := DisplayRowCount - 1 downto 0 do
  begin
    d := DisplayToData(pos);
    if d >= 0 then begin lastData := d; Break; end;
  end;

  FSelAnchorCol := 0;
  FSelAnchorRow := firstData;
  FCol := Header.Columns.Count - 1;
  FRow := lastData;
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

procedure TTyStringGrid.ClearSelections;
begin
  ClearSelection;
end;

function TTyStringGrid.GetSelectedRangeCount: Integer;
begin
  { 活动矩形恒算一块 —— 见属性声明处。 }
  Result := Length(FSelRects) + 1;
end;

function TTyStringGrid.GetSelectedRange(AIndex: Integer): TRect;
var
  r: TRect;
begin
  Result := Rect(-1, -1, -1, -1);
  if (AIndex < 0) or (AIndex >= GetSelectedRangeCount) then Exit;
  if AIndex = 0 then r := ActiveSelectionRect
  else r := FSelRects[AIndex - 1];
  { 内部按显示序存,对外一律数据行 —— 与 GetSelection 同一条纪律,
    否则宿主拿到的 Top/Bottom 没法直接索引 Cells。 }
  Result.Left := r.Left;
  Result.Right := r.Right;
  Result.Top := DisplayToData(r.Top);
  Result.Bottom := DisplayToData(r.Bottom);
end;

function TTyStringGrid.HasMultiSelection: Boolean;
begin
  Result := Length(FSelRects) > 0;
end;

function TTyStringGrid.GetSelection: TRect;
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

procedure TTyStringGrid.SetSelection(const AValue: TRect);
begin
  { All four negative = cancel, as in LCL (SetSelection -> CancelSelection). This is
    not a curiosity: an empty grid reads its selection back as (-1,-1,-1,-1), so
    without this branch `Grid.Selection := Saved` after saving "nothing selected"
    would clamp to (0,0,0,0) and select the top-left cell instead. }
  if (AValue.Left < 0) and (AValue.Top < 0)
     and (AValue.Right < 0) and (AValue.Bottom < 0) then
  begin
    ClearSelection;
    Exit;
  end;
  { SelectRange takes (col1, row1, col2, row2) -- NOT a rect -- and does the clamping
    and the OnSelectionChanged notification. Reading normalises via Min/Max, so a
    reversed rect written here comes back normalised. }
  SelectRange(AValue.Left, AValue.Top, AValue.Right, AValue.Bottom);
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

function TTyStringGrid.ApplySelectionColor(AColor: TTyColor;
  ATextColor: Boolean): Integer;
var
  pos, colIdx, dataRow: Integer;
begin
  Result := 0;
  { 整片 = **一条**撤销记录。逐格记的话,涂 20 格要按 20 次 Ctrl+Z ——
    与粘贴/剪切/批量增删行/ClearMerges 同一族。 }
  BeginUpdate;
  try
    { 遍历走显示序、寻址用数据行 —— 排序/筛选之后颜色仍跟着那一行数据走。
      分组行不是数据行,跳过。(与 ForEachSelectedNumber 同一套规矩。) }
    for pos := 0 to DisplayRowCount - 1 do
    begin
      dataRow := DisplayToData(pos);
      if dataRow < 0 then Continue;
      for colIdx := 0 to Header.Columns.Count - 1 do
      begin
        if not IsCellSelected(colIdx, dataRow) then Continue;
        if ATextColor then SetCellTextColor(colIdx, dataRow, AColor)
        else SetCellColor(colIdx, dataRow, AColor);
        Inc(Result);
      end;
    end;
  finally
    EndUpdate;
  end;
end;

function TTyStringGrid.SetSelectionColor(AColor: TTyColor): Integer;
begin
  Result := ApplySelectionColor(AColor, False);
end;

function TTyStringGrid.SetSelectionTextColor(AColor: TTyColor): Integer;
begin
  Result := ApplySelectionColor(AColor, True);
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

function TTyStringGrid.CanEditCell(ACol, ARow: Integer): Boolean;
begin
  { 先看有没有编辑器 —— 连编辑器都没有就不必打扰宿主。 }
  Result := EditorKindFor(ACol, ARow) <> gekNone;
  if Result and Assigned(FOnCanEditCell) then
    FOnCanEditCell(Self, ACol, ARow, Result);
end;

function TTyStringGrid.ScrollHintFor(ATopRow: Integer): string;
begin
  { 不挂钩子就不编一句出来 —— 控件并不知道哪一列对用户有意义。 }
  Result := '';
  if Assigned(FOnScrollHint) then FOnScrollHint(Self, ATopRow, Result);
end;

procedure TTyStringGrid.EditorTextChanged(Sender: TObject);
begin
  if FEditing and Assigned(FOnEditChange) then
    FOnEditChange(Self, FEditCol, FEditRow, FEditor.Text);
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

{ 窄列上把编辑器向右加宽,好让人看清自己在输入什么。
  加宽的是编辑器,列宽一点没动;也绝不越过网格右缘(越出去的部分点不到、也画不出)。
  下拉另算:列上配了 DropDownWidth 就按它走。 }
function TTyStringGrid.WidenEditorRect(ACol, ARow: Integer;
  const ARect: TRect): TRect;
var
  want, limit: Integer;
  rd: TRect;
  gcol: TTyGridColumn;   { 别叫 col —— 与网格的 Col 属性撞名 }
begin
  Result := ARect;
  want := FMinEditorWidth;

  if (ACol >= 0) and (ACol < Header.Columns.Count)
     and (Header.Columns.Items[ACol] is TTyGridColumn) then
  begin
    gcol := TTyGridColumn(Header.Columns.Items[ACol]);
    if (EditorKindFor(ACol, ARow) = gekPickList) and (gcol.DropDownWidth > 0) then
      want := gcol.DropDownWidth;
  end;

  if want <= 0 then Exit;
  want := ScaleI(want);
  if Result.Right - Result.Left >= want then Exit;   { 本来就够宽 }

  { 往**阅读方向**长,不是往右长:反射进阅读空间加宽、钳到视口尾缘、再反射回来。
    RTL 下这一句原样保留就会让编辑器往右长,从格子的起点跑出去。 }
  rd := ToReadingRect(Result);
  limit := ToReadingRect(Rect(0, 0, ViewportW, 0)).Right;
  rd.Right := rd.Left + want;
  if rd.Right > limit then rd.Right := limit;
  Result := ToScreenRect(rd);
end;

{ 当前正在用的编辑器控件。宿主给的 EditLink 优先,其次看内建那几个谁在显示。
  单独一个函数而不是十几处各记一个字段 —— 记账点越多越容易漏。 }
function TTyStringGrid.EditorControl: TControl;
begin
  Result := nil;
  if not FEditing then Exit;
  if FEditLinkCtl <> nil then Exit(FEditLinkCtl);
  if FEditor.Visible then Exit(FEditor);
  if FPickEditor.Visible then Exit(FPickEditor);
  if FDateEditor.Visible then Exit(FDateEditor);
  if FSpinEditor.Visible then Exit(FSpinEditor);
  if FSliderEditor.Visible then Exit(FSliderEditor);
  if FMemoEditor.Visible then Exit(FMemoEditor);
  if FMaskEditor.Visible then Exit(FMaskEditor);
  if FCalcEditor.Visible then Exit(FCalcEditor);
end;

{ 包一层:内建编辑器有十来种分支,每种都自己 SetBounds/Visible/SetFocus 然后 Exit。
  与其去十几个分支里各插一次事件(那正是本控件反复漏掉东西的方式),
  不如在这里统一发一次 —— 收口一处,不可能漏。

  **时机**:编辑器已经建好、摆好、拿到焦点,但还没把控制权交回调用方。
  宿主在这里改属性(字体、限长、宽度)都来得及生效;想在"显示之前"插手的话
  已经晚一步 —— 换来的是这十几种编辑器不可能有一种忘了通知。 }
function TTyStringGrid.BeginEdit(ACol, ARow: Integer): Boolean;
begin
  Result := DoBeginEdit(ACol, ARow);
  if Result and Assigned(FOnGetEditorProp) and (EditorControl <> nil) then
    FOnGetEditorProp(Self, FEditCol, FEditRow, EditorControl);
end;

function TTyStringGrid.DoBeginEdit(ACol, ARow: Integer): Boolean;
var
  r: TRect;
begin
  Result := False;
  if FReadOnly or (not Enabled) then Exit;
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  if (ARow < 0) or (ARow >= RowCount) then Exit;
  { 这里问 CanEditCell(不是 EditorKindFor):宿主可能只想禁用编辑、
    不想改变这一格的显示样子。 }
  if not CanEditCell(ACol, ARow) then Exit;

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
  r := WidenEditorRect(FCol, FRow, r);

  FEditCol := FCol;
  FEditRow := FRow;
  FEditKind := EditorKindFor(FCol, FRow);

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
    { 共享控件:每次都要显式设回去,否则编辑过一次时间格之后,
      日期列会永远弹出时间选择器(dtkDate 从前全文件一次都没被赋过)。
      与 PasswordChar 那处是同一条教训。 }
    FDateEditor.Kind := dtkDate;
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

function TTyStringGrid.PendingEditText: string;
begin
  { 一次只会有一个编辑器可见,所以按可见性挑;日期与时间共用一个控件,得看开编辑时记下的种类
    (从前一律当日期提交,时间格被写成 1899-12-30 —— 见旧 EndEdit 里的注释)。 }
  if FEditLink <> nil then Exit(FEditLink.GetValue);
  if FSpinEditor.Visible   then Exit(IntToStr(FSpinEditor.Value));
  if FSliderEditor.Visible then Exit(IntToStr(FSliderEditor.Position));
  if FMemoEditor.Visible   then Exit(FMemoEditor.Text);
  if FMaskEditor.Visible   then Exit(FMaskEditor.Text);
  if FCalcEditor.Visible   then Exit(FCalcEditor.Text);
  if FDateEditor.Visible then
  begin
    { 用 hh:nn 而不是 TimeToStr —— 后者会补出秒,把用户原样的 '13:45' 改写成 '13:45:00'。
      用户没改值就不该重写它(提交只比文本,格式一变就会当成"改过了"而落盘)。 }
    if FEditKind = gekTime then Exit(FormatDateTime('hh:nn', FDateEditor.DateTime));
    Exit(DateToStr(FDateEditor.Date));
  end;
  if FPickEditor.Visible then
  begin
    if FPickEditor.ItemIndex >= 0 then Exit(FPickEditor.Items[FPickEditor.ItemIndex]);
    Exit(Cells[FEditCol, FEditRow]);   { 没选 = 没改 }
  end;
  Result := FEditor.Text;
end;

function TTyStringGrid.TryEndEdit(ACommit: Boolean): Boolean;
var
  oldTxt, newTxt: string;
  valid: Boolean;
begin
  Result := True;
  if not FEditing then Exit;
  if FEndingEdit then Exit;
  if not ACommit then begin EndEdit(False); Exit; end;   { 放弃从不被否决 }
  if Assigned(FOnValidateCell) then
  begin
    oldTxt := Cells[FEditCol, FEditRow];
    newTxt := PendingEditText;
    if newTxt <> oldTxt then          { 没改过的格永远可以离开 —— 不为文件里带来的旧脏值困住用户 }
    begin
      valid := True;
      FOnValidateCell(Self, FEditCol, FEditRow, oldTxt, newTxt, valid);
      if not valid then Exit(False);  { 什么都不动:编辑器留着、光标不动、不抢焦点 }
      FValidatedPending := True;      { 下面的 EndEdit 别再问一遍 }
    end;
  end;
  EndEdit(True);
end;

procedure TTyStringGrid.EndEdit(ACommit: Boolean);
var
  oldTxt, newTxt: string;
  accept, valid, preValidated: Boolean;
begin
  { 先收旗子再过守卫:TryEndEdit 举了旗又被守卫弹回来的话,旗不能留到下一次。 }
  preValidated := FValidatedPending;
  FValidatedPending := False;
  if not FEditing then Exit;
  if FEndingEdit then Exit;          { 重入守卫:提交里若又触发提交会写两次 }
  FEndingEdit := True;
  try
    { **先取值,再拆**。宿主 EditLink 的控件一释放值就没了;其它编辑器也没理由等隐藏之后才读。
      取值走 PendingEditText —— 校验时宿主看到的字符串和这里写回的是同一个。 }
    oldTxt := Cells[FEditCol, FEditRow];
    if ACommit then newTxt := PendingEditText else newTxt := oldTxt;
    FEditing := False;
    if FEditLink <> nil then
    begin
      FEditLink.ReleaseEditor;
      FEditLink := nil;
      FEditLinkCtl := nil;
    end;
    FPickEditor.Visible := False;
    FSpinEditor.Visible := False;
    FSliderEditor.Visible := False;
    FMemoEditor.Visible := False;
    FMaskEditor.Visible := False;
    FCalcEditor.Visible := False;
    FDateEditor.Visible := False;
    FEditor.Visible := False;
    if ACommit and (newTxt <> oldTxt) then
    begin
      accept := True;
      { 数值列:非法值一律不写回(总比把 'abc' 存进金额列强)。 }
      if (EditorKindFor(FEditCol, FEditRow) = gekNumeric)
         and (newTxt <> '') and (StrToFloatDef(newTxt, MaxDouble) = MaxDouble) then
        accept := False;
      { 结构性关闭挡不住,但校验没过的值同样不能落盘:这里也问宿主(TryEndEdit 刚问过的
        不重复问 —— 宿主的 handler 可能在弹框),不过就按拒绝写回处理。 }
      if accept and (not preValidated) and Assigned(FOnValidateCell) then
      begin
        valid := True;
        FOnValidateCell(Self, FEditCol, FEditRow, oldTxt, newTxt, valid);
        if not valid then accept := False;
      end;
      if Assigned(FOnCellEdited) then
        FOnCellEdited(Self, FEditCol, FEditRow, oldTxt, newTxt, accept);
      if accept then Cells[FEditCol, FEditRow] := newTxt;
    end;
    Invalidate;
  finally
    FEndingEdit := False;
  end;
end;

procedure TTyStringGrid.DoExit;
begin
  { 焦点离开了整个网格。被校验拦下的编辑到这里就作废:走开与 Esc 是同一种表态。
    留着它会得到一个趴在失焦网格上的编辑器 —— Editing 为 True 却没人在编辑,
    宿主拿它控制工具栏时会被骗,格子显示的也不是真实值。 }
  if FEditing then EndEdit(False);
  inherited DoExit;
end;

procedure TTyStringGrid.DateEditorExit(Sender: TObject);
begin
  TryEndEdit(True);
end;

procedure TTyStringGrid.PickEditorChange(Sender: TObject);
begin
  { 选中即提交 —— 下拉不像文本框那样需要按 Enter 确认。被拦下就留在下拉里。 }
  if FEditing then TryEndEdit(True);
end;

procedure TTyStringGrid.PickEditorExit(Sender: TObject);
begin
  TryEndEdit(True);
end;

procedure TTyStringGrid.EditorKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    { HandleAllocated 这道守卫别省:句柄没落地时 SetFocus 会抛异常。
      本文件其余十来处 SetFocus 都带着它,只有这两处漏了。 }
    VK_RETURN: begin Key := 0;
                 { 被拦下就把焦点留给编辑器 —— 不然用户看着编辑器还在,键却敲进了网格。 }
                 if TryEndEdit(True) and HandleAllocated and CanFocus then SetFocus; end;
    VK_ESCAPE: begin EndEdit(False); Key := 0;
                 if HandleAllocated and CanFocus then SetFocus; end;
  end;
end;

function TTyStringGrid.EditorCanCancelForTest: Boolean;
begin
  Result := False;
  if not FEditing then Exit;
  if FEditLink <> nil then Exit;             { 宿主的编辑器,宿主自己管键 }
  if FPickEditor.Visible   then Exit(Assigned(FPickEditor.OnKeyDown));
  if FDateEditor.Visible   then Exit(Assigned(FDateEditor.OnKeyDown));
  if FSpinEditor.Visible   then Exit(Assigned(FSpinEditor.OnKeyDown));
  if FSliderEditor.Visible then Exit(Assigned(FSliderEditor.OnKeyDown));
  if FMemoEditor.Visible   then Exit(Assigned(FMemoEditor.OnKeyDown));
  if FCalcEditor.Visible   then Exit(Assigned(FCalcEditor.OnKeyDown));
  if FMaskEditor.Visible   then Exit(Assigned(FMaskEditor.OnKeyDown));
  Result := Assigned(FEditor.OnKeyDown);
end;

procedure TTyStringGrid.EditorCancelKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key <> VK_ESCAPE then Exit;
  EndEdit(False);
  Key := 0;
  if HandleAllocated and CanFocus then SetFocus;
end;

procedure TTyStringGrid.PickEditorKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key <> VK_ESCAPE then Exit;
  { An open dropdown owns the key -- Esc there means "close the list", not "abandon the cell",
    and swallowing it would make the two gestures indistinguishable. }
  if FPickEditor.DroppedDown then Exit;
  EndEdit(False);
  Key := 0;
  if HandleAllocated and CanFocus then SetFocus;
end;

procedure TTyStringGrid.EditorKeyPress(Sender: TObject; var Key: Char);
var
  vc: string;
begin
  if Key < #32 then Exit;             { 控制字符(退格/回车)不算录入 }
  if not FEditing then Exit;
  vc := ValidCharsFor(FEditCol, FEditRow);
  if (vc <> '') and (Pos(Key, vc) = 0) then Key := #0;   { 吃掉这一击 }
end;

procedure TTyStringGrid.EditorExit(Sender: TObject);
begin
  { 焦点离开 = 提交。与库内其他内联编辑一致:凡是会让单元格移动/失焦的动作,先提交。
    被校验拦下就留着 —— **不把焦点抢回来**(在失焦回调里 SetFocus 是 widgetset 层的
    递归陷阱,LCL 自家的网格也从不这么干)。焦点若是去了网格里的另一格,用户还在网格里,
    点回来接着改;若是离开了整个网格,DoExit 会把这次编辑作废。 }
  TryEndEdit(True);
end;

procedure TTyStringGrid.DblClick;
begin
  inherited DblClick;
  { 只有双击**单元格**才进编辑。行号槽、列头、末行以下的空白都不是格子 ——
    在那些地方双击时用户的手根本没碰当前光标格。 }
  if FLastDownHit.Part = ghpCell then BeginEdit;
end;

procedure TTyStringGrid.RenderSelectionFrame(P: TTyPainter;
  const M: TTyGridMetrics; const AFrame: TTyStyleSet);
var
  b, r: TRect;
  fS: TTyStyleSet;

  procedure DrawFrameAndHandle;
  var
    h: TRect;
    lw: Integer;
    solid: TTyFill;
  begin
    lw := fS.BorderWidth;
    if lw < 1 then lw := 1;
    P.StrokeBorder(b, 0, lw, fS.BorderColor);

    { 填充柄。用同一个 FillHandleRect —— 命中走的也是它,所以
      "看得见的那一块"和"点得到的那一块"不可能分叉。 }
    h := FillHandleRect;
    if IsRectEmpty(h) then Exit;
    if (tpBackground in fS.Present) and (fS.Background.Kind <> tfkNone) then
      P.FillBackground(h, fS.Background, 0)
    else
    begin
      solid := Default(TTyFill);
      solid.Kind := tfkSolid;
      solid.Color := fS.BorderColor;
      P.FillBackground(h, solid, 0);
    end;
    { 柄要描一圈对比色。不描的话它和选区底色同色 —— 画了等于没画
      (token 里 background 与 border-color 通常都是 accent)。
      对比色走 token 的 color:,不硬编码。 }
    if tpTextColor in fS.Present then
      P.StrokeBorder(h, 0, 1, fS.TextColor);
  end;

begin
  { The cell selection frame + fill handle are a spreadsheet affordance: only the
    default cell-selection mode gets them. Row/column selection reads as a highlighted
    band, not a framed cell. }
  if FSelectionMode <> gsmCell then Exit;
  b := SelectionBoundsRect;
  if IsRectEmpty(b) then Exit;
  r := ActiveSelectionRect;

  fS := ActiveController.Model.ResolveStyle('TyGridSelectionFrame', StyleClass, []);
  if not (tpBorderColor in fS.Present) then Exit;   { 主题没定义就不画 }

  { 裁到选区**所属的那个窗格**,而不是笼统裁到正文窗格。
    光标停在固定行上时,柄会探进正文窗格一个像素 —— 而正文窗格是会被
    滚动平移的,那一个像素于是跟着跑,脏区快路径与整幅重画就对不上了。 }
  DrawInPane(P, CellPane(r.Right, r.Bottom), M, @DrawFrameAndHandle);
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
  { 失焦时换一个 typeKey 解析选区底色 —— 控件不自己去调淡一个颜色
    (那就成了硬编码的视觉值)。用独立的键而不是 :selected:disabled:
    .tycss 每个选择器只认一个 :state。 }
  if FHideSelectionWhenInactive and (not SelectionIsActive) then
    selS := ActiveController.Model.ResolveStyle('TyGridCellSelectedInactive',
      StyleClass, [])
  else
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
  { 选区外框 + 填充柄。画在选区底色之上、单元格文字之前 ——
    外框是"这块是选中的"的边界线索,底色只给面。 }
  RenderSelectionFrame(P, M, AFrame);

  { 分组行:整行一条横带,画"值(计数)"和折叠三角。它不对应任何数据行,
    所以必须在普通单元格之前处理掉,否则基类会拿 -1 去取内容。 }
  if (GetGroupCol >= 0) and TyGridDrawSlots(M, firstRow, lastRow) then
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
        { 候选列在**非编辑态**也要露一个箭头 —— 否则用户看不出哪一格有候选项
          (M19 的第三项;P5 只做了 MinEditorWidth / DropDownWidth 两项)。 }
        if EditorKindFor(colIdx, dataRow) = gekPickList then
          RenderPickListArrow(P, colIdx, dataRow, AFrame);
        case CellDisplayFor(colIdx, dataRow) of
          gcdProgress: RenderProgressCell(P, colIdx, dataRow, AFrame);
          gcdRating:   RenderRatingCell(P, colIdx, dataRow, AFrame);
          gcdImage:    RenderImageCell(P, colIdx, dataRow, AFrame);
          gcdButton:   RenderButtonCell(P, colIdx, dataRow,
                         GetCellText(colIdx, dataRow), AFrame);
          gcdColor:    RenderColorCell(P, colIdx, dataRow, AFrame);
          gcdHyperlink: RenderHyperlinkCell(P, colIdx, dataRow, AFrame);
        end;
        { 批注标记与显示类型正交 —— 任何一种格子都可能带批注,
          所以它在 case **之外**画。 }
        RenderCommentMark(P, colIdx, dataRow, AFrame);
      end;
    end;
  inherited RenderCells(P, M, AFrame);
end;

{ ---- TTyGridStrings -------------------------------------------------------- }

constructor TTyGridStrings.Create(AGrid: TTyStringGrid; AIsCol: Boolean;
  AIndex: Integer);
begin
  inherited Create;
  FGrid := AGrid;
  FIsCol := AIsCol;
  FIndex := AIndex;
  FAdded := 0;
end;

function TTyGridStrings.Locate(AIndex: Integer; out ACol, ARow: Integer): Boolean;
begin
  ACol := 0; ARow := 0;
  if AIndex < 0 then Exit(False);
  if AIndex >= GetCount then Exit(False);
  if FIsCol then
  begin
    ACol := FIndex;                 { 列视图:视图下标就是行号 }
    ARow := AIndex;
  end
  else
  begin
    ACol := AIndex;                 { 行视图:视图下标就是列号 }
    ARow := FIndex;
  end;
  Result := True;
end;

function TTyGridStrings.GetCount: Integer;
begin
  { 长度**永远现问网格**,不缓存 —— 缓存下来的那一刻它就可能过期
    (行数、列数都可以在视图被人拿着的时候变)。 }
  if FIsCol then Result := FGrid.RowCount
  else Result := FGrid.Header.Columns.Count;
end;

function TTyGridStrings.Get(AIndex: Integer): string;
var c, r: Integer;
begin
  { 越界给空串而不是抛 —— 读一个不存在的槽在 LCL 那边也是空串
    (grids.pas:10803),而 TStrings 的通用代码会去读 Count 之外的位置。 }
  if Locate(AIndex, c, r) then Result := FGrid.Cells[c, r] else Result := '';
end;

function TTyGridStrings.GetObject(AIndex: Integer): TObject;
var c, r: Integer;
begin
  if Locate(AIndex, c, r) then Result := FGrid.Objects[c, r] else Result := nil;
end;

procedure TTyGridStrings.Put(AIndex: Integer; const S: string);
var c, r: Integer;
begin
  { 写越界要吭声:静静丢掉一次写入是最难查的那种 bug(LCL 同样抛,
    grids.pas:10831)。 }
  if not Locate(AIndex, c, r) then
    raise EListError.CreateFmt(
      'TTyGridStrings: index %d is outside the grid (count = %d)',
      [AIndex, GetCount]);
  FGrid.Cells[c, r] := S;
end;

procedure TTyGridStrings.PutObject(AIndex: Integer; AObject: TObject);
var c, r: Integer;
begin
  if not Locate(AIndex, c, r) then
    raise EListError.CreateFmt(
      'TTyGridStrings: index %d is outside the grid (count = %d)',
      [AIndex, GetCount]);
  FGrid.Objects[c, r] := AObject;
end;

function TTyGridStrings.Add(const S: string): Integer;
begin
  { 往"下一个还没被 Add 写过的槽"里写,写满返回 -1 而**不**抛 ——
    CommaText / DelimitedText 的赋值走的正是 Clear + Add,少了这条计数器
    它们一个字都写不进去。逐字照 LCL 的 FAddedCount(grids.pas:10791)。 }
  if (FAdded < 0) or (FAdded >= GetCount) then Exit(-1);
  Put(FAdded, S);
  Result := FAdded;
  Inc(FAdded);
end;

procedure TTyGridStrings.Clear;
var
  i: Integer;
begin
  { 清的是**内容**,不是结构:长度不变(那是网格的行数/列数)。
    整批一条撤销记录 —— 与 SetRowColor / ClearRowContents 同一条规矩。 }
  FGrid.BeginUpdate;
  try
    for i := 0 to GetCount - 1 do
    begin
      Put(i, '');
      PutObject(i, nil);
    end;
  finally
    FGrid.EndUpdate;
  end;
  FAdded := 0;
end;

procedure TTyGridStrings.Delete(AIndex: Integer);
begin
  raise EListError.Create('TTyGridStrings: a row/column view has a fixed length; '
    + 'use TTyStringGrid.DeleteRow / DeleteColumn to change the structure');
end;

procedure TTyGridStrings.Insert(AIndex: Integer; const S: string);
begin
  raise EListError.Create('TTyGridStrings: a row/column view has a fixed length; '
    + 'use TTyStringGrid.InsertRow / InsertColumn to change the structure');
end;

procedure TTyGridStrings.Assign(ASource: TPersistent);
var
  i, n: Integer;
begin
  if ASource is TStrings then
  begin
    { **网格的尺寸说了算**,逐字照 LCL(grids.pas:10882):只覆盖
      min(源长度, 视图长度) 项。源短了,尾巴上那几格**原样留着**;
      源长了,多出来的项丢掉。

      两条都容易吓一跳,但它们是移植代码依赖的行为:`Rows[r] := 短列表`
      在 LCL 那边从来就不是"整行换掉"。真要换掉整行,先 Clear 再赋值。
      更要紧的是**绝不在这里改行数/列数** —— 一次数据赋值偷偷做结构变更,
      而结构变更在撤销栈里是另一种记录,两者混在一起撤不干净。 }
    n := TStrings(ASource).Count;
    if n > GetCount then n := GetCount;
    FGrid.BeginUpdate;              { 整次赋值算一条撤销记录、只重画一次 }
    BeginUpdate;
    try
      for i := 0 to n - 1 do
      begin
        Put(i, TStrings(ASource)[i]);
        PutObject(i, TStrings(ASource).Objects[i]);
      end;
    finally
      EndUpdate;
      FGrid.EndUpdate;
    end;
    Exit;
  end;
  inherited Assign(ASource);
end;

initialization
  { 设计器与 .lfm 流式化按类名查类,必须登记。 }
  RegisterClasses([TTyCustomGrid, TTyDrawGrid, TTyStringGrid]);
  { 这里**没有** `TyGridCheckedWord := rsGridCheckedWord;`,并且不能加回来:
    语言目录装载晚于单元初始化,那份拷贝抓到的永远是英文 —— 判定在 CellChecked
    里实时读 resourcestring(见 TyGridCheckedWord 声明处)。 }

end.
