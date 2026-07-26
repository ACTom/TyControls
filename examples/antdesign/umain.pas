unit umain;

{ TyControls Pro —— 仿 Ant Design Pro 的后台示例系统(不是控件陈列柜)。

  骨架:TTyTitleBar(自绘窗框)+ 左侧 Sider(TTyListGroupPanel:分组可展开的折叠
  菜单,和 Ant Design Pro 的 Sider 是同一种东西 —— 树是"层级数据浏览器",导航菜单
  不是树)+ TTySplitter + 内容区(TTyPageControl,页签条隐藏,由 Sider 的选中项切页)。
  默认皮肤 antdesign,标题栏内置皮肤下拉 + 暗色开关。

  它同时是 AntD-gap 批次程序的**集成验收面**:批 1/2/3 新落地的 14 个控件在这里
  和老控件并排跑同一套主题 —— 风格不一致会一眼看出来。曾经留在界面上的 11 个占位
  标签已经全部换成了真控件(2026-07-17)。

  界面全部在 umain.lfm 里设计;本单元只放事件处理 + 主题装配 + 放不进 .lfm 的
  数据(树节点、列表行、迷你趋势图的采样)。

  规划出处:docs/design/2026-07-17-antdesign-pro-example.md
            docs/design/2026-07-16-antd-gap-controls.md }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, Dialogs, Menus,
  BGRABitmap, BGRABitmapTypes, BGRAGradientScanner, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Base, tyControls.Panel, tyControls.ExPanel, tyControls.TyLabel,
  tyControls.Button, tyControls.DropButtons, tyControls.ColorButton, tyControls.ComboBox,
  tyControls.ToggleSwitch, tyControls.Splitter, tyControls.TreeView,
  tyControls.ListGroupPanel, tyControls.ImageCollection,
  tyControls.PageControl, tyControls.TabSheet, tyControls.TabSet,
  tyControls.Card, tyControls.Tag, tyControls.Badge,
  tyControls.GridPanel, tyControls.GridCell,
  tyControls.Sparkline, tyControls.Chart, tyControls.CircularProgress,
  tyControls.Meter, tyControls.ListView, tyControls.Columns, tyControls.Grid,
  tyControls.Edit, tyControls.NumericEdit, tyControls.DateTimePicker,
  tyControls.TrackBar, tyControls.Rating, tyControls.CheckBox,
  tyControls.RadioGroup, tyControls.ProgressBar, tyControls.ActivityIndicator,
  tyControls.ImageView, tyControls.Menu, tyControls.ToolBar,
  tyControls.Dialogs,
  { AntD-gap 批 1 / 2 / 3 —— 这一页页的空位就是为它们留的。 }
  tyControls.Alert, tyControls.Notification, tyControls.Empty,
  tyControls.Segmented, tyControls.Pagination, tyControls.Steps,
  tyControls.Breadcrumb, tyControls.TreeSelect, tyControls.Cascader,
  tyControls.Transfer, tyControls.Popover;

type

  { The org-tree (数据展示 page) payload: an index into OrgCaptions.
    A plain Integer keeps the node data free of managed types. }
  TOrgRec = record
    Id: Integer;
  end;
  POrgRec = ^TOrgRec;

  { Node handles while the org tree is being built, indexed like OrgCaptions. }
  TOrgNodes = array[0..8] of PTyTreeNode;

  { TMainForm }

  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    BtnUser: TTyMenuButton;
    Crumb: TTyBreadcrumb;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    Surface: TTyFormSurface;
    { 标题栏右上角的用户菜单(对标 Ant Design Pro 头像下拉):菜单与菜单项都在 .lfm 里。 }
    UserMenu: TTyPopupMenu;
    MnuUserProfile: TMenuItem;
    MnuUserTheme: TMenuItem;
    MnuUserSep: TMenuItem;
    MnuUserLogout: TMenuItem;
    Sider: TTyListGroupPanel;
    SiderSplit: TTySplitter;
    Content: TTyPanel;
    PageHost: TTyPageControl;
    MainMenu1: TMainMenu;
    { 非可视组件:toast 和浮层都是"由代码弹出来"的,不占版面(项目铁律:
      非可视组件留在窗体上,可视控件一律进 Surface)。 }
    Toast: TTyNotification;
    ToastErr: TTyNotification;
    Pop: TTyPopover;
    MnuFile: TMenuItem;
    MnuFileNew: TMenuItem;
    MnuFileOpen: TMenuItem;
    MnuFileSep1: TMenuItem;
    MnuFileExit: TMenuItem;
    MnuView: TMenuItem;
    MnuViewSider: TMenuItem;
    MnuViewRefresh: TMenuItem;
    MnuHelp: TMenuItem;
    MnuHelpAbout: TMenuItem;
    { 仪表盘 }
    PgDashboard: TTyTabSheet;
    GridKPI: TTyGridPanel;
    KpiCell0: TTyGridCell;
    KpiCell1: TTyGridCell;
    KpiCell2: TTyGridCell;
    KpiCell3: TTyGridCell;
    GridMain: TTyGridPanel;
    MainCell0: TTyGridCell;
    MainCell1: TTyGridCell;
    CardVisits: TTyCard;
    SparkVisits: TTySparkline;
    CardOrders: TTyCard;
    SparkOrders: TTySparkline;
    CardCpu: TTyCard;
    CircCpu: TTyCircularProgress;
    CardHealth: TTyCard;
    MeterHealth: TTyMeter;
    CardChart: TTyCard;
    ChartSales: TTyChart;
    CardStatus: TTyCard;
    TagOnline: TTyTag;
    TagBeta: TTyTag;
    TagRisk: TTyTag;
    LblQueue: TTyLabel;
    BtnQueue: TTyButton;
    BadgeQueue: TTyBadge;
    LblStatusNote: TTyLabel;
    BtnStatusDetail: TTyButton;
    LblDashNote: TTyLabel;
    { 列表 / 表格 }
    PgList: TTyTabSheet;
    GridOrders: TTyStringGrid;
    TagFilterAll: TTyTag;
    TagFilterPub: TTyTag;
    TagFilterDraft: TTyTag;
    BtnSelCount: TTyButton;
    BadgeSel: TTyBadge;
    BtnToggleEmpty: TTyButton;
    EmptyOrders: TTyEmpty;
    BtnEmptyNew: TTyButton;
    PagOrders: TTyPagination;
    LblPageInfo: TTyLabel;
    LblListNote: TTyLabel;
    { 表单 / 录入 }
    PgForm: TTyTabSheet;
    CardForm: TTyCard;
    LblName: TTyLabel;
    EdName: TTyEdit;
    LblAmount: TTyLabel;
    EdAmount: TTyNumericEdit;
    LblKind: TTyLabel;
    CbKind: TTyComboBox;
    LblDue: TTyLabel;
    DtDue: TTyDateTimePicker;
    LblUrgent: TTyLabel;
    SwUrgent: TTyToggleSwitch;
    LblWeight: TTyLabel;
    TopBar: TTyPanel;
    TrkWeight: TTyTrackBar;
    LblScore: TTyLabel;
    RateScore: TTyRating;
    ChkNotify: TTyCheckBox;
    RgChannel: TTyRadioGroup;
    LblColor: TTyLabel;
    BtnColor: TTyColorButton;
    BtnSubmit: TTyButton;
    BtnReset: TTyButton;
    CardFormTodo: TTyCard;
    LblDept: TTyLabel;
    TsDept: TTyTreeSelect;
    LblRegion: TTyLabel;
    CasRegion: TTyCascader;
    LblMembers: TTyLabel;
    TrfMembers: TTyTransfer;
    LblAdvPick: TTyLabel;
    LblFormTodoNote: TTyLabel;
    { 反馈 }
    PgFeedback: TTyTabSheet;
    CardModal: TTyCard;
    BtnMsg: TTyButton;
    BtnConfirm: TTyButton;
    BtnInput: TTyButton;
    LblFeedback: TTyLabel;
    CardProgress: TTyCard;
    LblProgress: TTyLabel;
    PbTask: TTyProgressBar;
    BtnStep: TTyButton;
    Spinner: TTyActivityIndicator;
    LblSpinner: TTyLabel;
    CardInline: TTyCard;
    AlertInfo: TTyAlert;
    AlertSuccess: TTyAlert;
    AlertWarning: TTyAlert;
    AlertError: TTyAlert;
    LblAlertNote: TTyLabel;
    CardFloat: TTyCard;
    BtnToast: TTyButton;
    BtnToastErr: TTyButton;
    BtnPopover: TTyButton;
    LblFloatNote: TTyLabel;
    { 浮层的内容容器:在设计器里摆好,平时 Visible = False 待在卡片里,
      Show 的时候被 TTyPopover 收编进弹窗、Hide 的时候原样还回来。 }
    PopBox: TTyPanel;
    LblPopBody: TTyLabel;
    BtnPopOk: TTyButton;
    BtnPopCancel: TTyButton;
    { 导航 }
    PgNav: TTyTabSheet;
    NavMenuBar: TTyMenuBar;
    NavToolBar: TTyToolBar;
    BtnNavNew: TTyButton;
    BtnNavOpen: TTyButton;
    SepNav: TTyToolSeparator;
    BtnNavSave: TTyButton;
    CardTabs: TTyCard;
    CardSeg: TTyCard;
    CardSteps: TTyCard;
    CardCrumb: TTyCard;
    TabsDemo: TTyTabSet;
    TabsBody: TTyPanel;
    LblTabsBody: TTyLabel;
    LblSegTitle: TTyLabel;
    SegRange: TTySegmented;
    LblSegValue: TTyLabel;
    LblStepsTitle: TTyLabel;
    StepsFlow: TTySteps;
    LblCrumbTitle: TTyLabel;
    NavCrumb: TTyBreadcrumb;
    LblNavNote: TTyLabel;
    { 数据展示 }
    PgData: TTyTabSheet;
    CardTree: TTyCard;
    DataTree: TTyTreeView;
    CardTags: TTyCard;
    TagPublished: TTyTag;
    TagDraft: TTyTag;
    TagBroken: TTyTag;
    TagRegion: TTyTag;
    TagOwner: TTyTag;
    LblBadgeHint: TTyLabel;
    BdgStandalone: TTyBadge;
    BdgDot: TTyBadge;
    BtnInbox: TTyButton;
    BdgInbox: TTyBadge;
    LblTagsNote: TTyLabel;
    CardImage: TTyCard;
    ImgView: TTyImageView;
    ExpData: TTyExPanel;
    LblExpBody: TTyLabel;

    procedure FormCreate(Sender: TObject);
    { Assign the code-set / string-typed captions from resourcestrings, which SetDefaultLang
      DOES translate — LCL's LFM translator only touches TCaption/TTranslateString properties,
      so TTyCard.Title, TTyToggleSwitch.Caption, and every caption built in code stay English
      unless we push a translated resourcestring into them here. }
    procedure LocalizeTexts;
    procedure FormResize(Sender: TObject);
    { 换肤 }
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    { Sider 切页 + 顶部面包屑 }
    procedure SiderItemClick(Sender: TObject; AGroupIndex, AItemIndex: Integer);
    procedure CrumbClick(Sender: TObject; AIndex: Integer);
    { 各页 }
    procedure DataTreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; var AText: string);
    procedure TagClosed(Sender: TObject; var AllowClose: Boolean);
    procedure GridSelectionChanged(Sender: TObject);
    procedure OrdersGetCellStyle(Sender: TObject; ACol, ARow: Integer;
      var ABackground: TTyFill; var ATextColor: TTyColor;
      var AFontName: string; var AFontSize, AFontWeight: Integer;
      var AHAlign: TAlignment; var AVAlign: TTextLayout);
    procedure ToggleEmptyClick(Sender: TObject);
    procedure EmptyNewClick(Sender: TObject);
    procedure PageChange(Sender: TObject);
    procedure UserProfileClick(Sender: TObject);
    procedure UserThemeClick(Sender: TObject);
    procedure UserLogoutClick(Sender: TObject);
    procedure QueueClick(Sender: TObject);
    procedure StatusDetailClick(Sender: TObject);
    procedure SubmitClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure AdvancedPickChange(Sender: TObject);
    procedure MsgClick(Sender: TObject);
    procedure ConfirmClick(Sender: TObject);
    procedure InputClick(Sender: TObject);
    procedure StepClick(Sender: TObject);
    procedure AlertClosed(Sender: TObject; var AllowClose: Boolean);
    procedure ToastClick(Sender: TObject);
    procedure ToastErrClick(Sender: TObject);
    procedure PopoverClick(Sender: TObject);
    procedure PopOkClick(Sender: TObject);
    procedure PopCancelClick(Sender: TObject);
    procedure TabsDemoChange(Sender: TObject);
    procedure SegRangeChange(Sender: TObject);
    procedure StepsFlowChange(Sender: TObject);
    procedure NavCrumbClick(Sender: TObject; AIndex: Integer);
    procedure NavToolClick(Sender: TObject);
    procedure MenuItemClick(Sender: TObject);
  private
    { 手风琴 Sider 的图标集:无外部资源 —— 每个字形用 BGRA 现画进位图集(见
      examples/listview 的同一手法),再由虚拟图片列表按名暴露给 Sider.Images。
      颜色取自主题,换肤时整批重画。 }
    FSiderIcons: TTyImageCollection;
    FSiderImages: TTyVirtualImageList;
    procedure BuildSider;
    procedure BuildSiderIcons;
    procedure BuildList;
    procedure BuildOrgTree;
    procedure BuildOrgTreeInto(ATree: TTyTreeView);
    procedure FeedSparklines;
    procedure BuildSampleImage;
    procedure ShowPage(AGroup, AItem: Integer);
    procedure ShowEmptyState(AEmpty: Boolean);
    procedure PlaceEmptyAction;
  end;

const
  { The TTyPageControl page each item opens. Same index pair as NavItems. }
  NavItemPage: array[0..2, 0..1] of Integer = (
    (0, 5),
    (1, 2),
    (3, 4));

  { 每个分组 / 条目的图标槽,索引进 FSiderImages.Names(建表顺序见 BuildSiderIcons)。
    分组头和条目行一样,一行一个图标 —— 这正是 Ant Design Pro 的 Sider 读起来更清楚的
    原因之一。索引对应的字形:0 工作台格 · 1 文件夹 · 2 交互双箭头 · 3 仪表盘 · 4 柱状图 ·
    5 列表 · 6 表单 · 7 铃铛 · 8 指南针。 }
  SiderGroupIcon: array[0..2] of Integer = (0, 1, 2);   // 工作台 / 内容管理 / 交互
  SiderItemIcon: array[0..2, 0..1] of Integer = (
    (3, 4),    // 仪表盘 · 数据展示
    (5, 6),    // 列表 / 表格 · 表单 / 录入
    (7, 8));   // 反馈 · 导航

  { The org tree, used TWICE: spread across a panel (数据展示) and folded into a form
    row's drop (表单页 · TTyTreeSelect) — same data, two ways of spending screen. }
  OrgParent: array[0..8] of Integer = (
    -1,
    0, 1, 1,
    0, 4, 4,
    0, 7);

var
  MainForm: TMainForm;
  { The Sider's nav model (group -> items), addressed by the (group, item) pair OnItemClick
    hands back. VAR, not const: LocalizeTexts fills them from resourcestrings so the Sider and
    breadcrumb read translated text (they are code-built, not TCaption LFM properties). }
  NavGroups: array[0..2] of string;
  NavItems: array[0..2, 0..1] of string;
  { The org tree's node captions — VAR for the same reason: LocalizeTexts fills them from
    resourcestrings (OrgParent stays a const; only the text is translatable). }
  OrgCaptions: array[0..8] of string;

implementation

{$R *.lfm}

{ ============================ 主题装配 / 换肤 ============================== }

resourcestring
  { Values match the .po msgids exactly, so SetDefaultLang translates them at startup and the
    assignments below push the translated text into the string-typed / code-built captions. }
  rsCardVisits   = 'Visits today';
  rsCardOrders   = 'Order volume';
  rsCardCpu      = 'CPU usage';
  rsCardHealth   = 'Service health';
  rsCardChart    = 'Turnover / refunds, last six months';
  rsCardStatus   = 'System status';
  rsCardForm     = 'New work order';
  rsCardFormTodo = 'Advanced entry';
  rsCardModal    = 'Modal feedback (existing)';
  rsCardProgress = 'Progress & busy';
  rsCardInline   = 'Inline alert bar (TTyAlert)';
  rsCardFloat    = 'Popover feedback';
  rsCardTabs     = 'Tab strip (TTyTabSet)';
  rsCardSeg      = 'Segmented control (TTySegmented)';
  rsCardSteps    = 'Step bar (TTySteps)';
  rsCardCrumb    = 'Breadcrumb (TTyBreadcrumb)';
  rsCardTree     = 'Org tree';
  rsCardTags     = 'Tags & badges';
  rsCardImage    = 'Picture';
  rsDark         = 'Dark';
  rsNavWorkbench   = 'Workbench';
  rsNavContent     = 'Content';
  rsNavInteraction = 'Interaction';
  rsNavDashboard   = 'Dashboard';
  rsNavDataDisplay = 'Data display';
  rsNavListGrid    = 'List / grid';
  rsNavFormEntry   = 'Form / entry';
  rsNavFeedback    = 'Feedback';
  rsNavNavigation  = 'Navigation';
  rsCrumbHome  = 'Home';
  rsColNo      = 'No.';
  rsColTitle   = 'Title';
  rsColOwner   = 'Owner';
  rsColStatus  = 'Status';
  rsColUpdated = 'Updated time';
  { Interaction text — toasts, dialogs, feedback. Multi-line messages are split into one
    resourcestring per line and rejoined with LineEnding, so every .po entry stays single-line. }
  rsMsgSysStatus1 = 'System status: all services running.';
  rsMsgSysStatus2 = '(this card turned on ShowActions, so the buttons sit in the action bar)';
  rsMsgPersonal1  = 'Personal settings';
  rsMsgPersonal2  = 'Current user: Administrator · role: Super Admin';
  rsToastTheme    = 'Theme settings';
  rsToastThemeMsg = 'The skin dropdown and the "Dark" toggle are on the right of the title bar; the skin dropdown is focused.';
  rsDlgSignOut    = 'Sign out?';
  rsTagRemoved    = 'Removed tag: ';
  rsToastEmpty    = 'The empty state''s action button';
  rsToastEmptyMsg = 'It is a real control in TTyEmpty''s action bar, not painted on.';
  rsMsgShow1      = 'This is TyShowMessage — a custom-drawn modal prompt; it blocks you and asks for an answer.';
  rsMsgShow2      = 'The alert bar that stays on the page is TTyAlert in the bottom-left; the one that walks off on its own in the corner is TTyNotification — three different things, not three sizes.';
  rsDlgSubmit     = 'Submit this work order?';
  rsFbConfirmYes  = 'Confirmation dialog: chose "Yes".';
  rsFbConfirmNo   = 'Confirmation dialog: chose "No".';
  rsDlgInputTitle = 'Input dialog';
  rsDlgInputPrompt= 'Enter a group name:';
  rsFbInputGot    = 'Input dialog: got "%s".';
  rsFbInputCancel = 'Input dialog: cancelled.';
  rsFbTaskProgress= 'Task progress: %d%%';
  rsToast3Orders  = '3 new work orders';
  rsToast3OrdersMsg1 = 'from the "Channel" group.';
  rsToast3OrdersMsg2 = 'This one dismisses itself after 4.5s; hovering pauses the countdown.';
  rsToastPublished = 'Published';
  rsToastPublishedMsg = 'The buttons inside the popover are real controls — after clicking, one returns to the card and stays.';
  { Interaction/Navigation demo echoes (the footnote labels) + segmented metric readouts.
    Echoes take a runtime widget caption, so they are Format strings with %s/%d. }
  rsSegDay   = '1,330 transactions today · MoM +4.2%';
  rsSegWeek  = '8,214 transactions this week · MoM +9.7%';
  rsSegMonth = '33,908 transactions this month · MoM +12.4%';
  rsEchoTab  = 'Tab strip: switched to "%s" — TTyTabSet only reports the selected item; the content below is swapped by the host (it hosts no page).';
  rsEchoSeg  = 'Segmented control: switched to "%s" — it switches a value (the view range), not a page: the numbers on the right just changed their basis.';
  rsEchoStepOut = 'Step bar: moved outside the list (-1 = not started / Count = finished, both are real states).';
  rsEchoStep = 'Step bar: moved to step %d "%s" — everything before is done, everything after is waiting.';
  rsEchoCrumb = 'Breadcrumb: clicked "%s" — the last segment is the current location, not a link; it does not fire this event at all.';
  rsEchoTool = 'Toolbar: clicked "%s".';
  rsEchoMenu = 'Menu: clicked "%s".';
  { Item lists shown by the Navigation-page demos. These live in the .lfm as TStrings
    collections, which the LFM translator cannot reach at all (it only walks TCaption
    string properties), so LocalizeTexts refills them from resourcestrings. }
  rsTabOverview = 'Overview';
  rsTabDetail   = 'Detail';
  rsTabLog      = 'Log';
  rsSegDayItem   = 'Day';
  rsSegWeekItem  = 'Week';
  rsSegMonthItem = 'Month';
  rsStepFill    = 'Fill in the details';
  rsStepConfirm = 'Confirm information';
  rsStepDone    = 'Done';
  rsCrumbInteraction = 'Interaction';
  rsCrumbNavigation  = 'Navigation';
  { The tab bodies the host swaps in — one resourcestring per line. }
  rsTabBodyOverview1 = '1,330 transactions this month · 230 refunds · fulfilment rate 82.7%';
  rsTabBodyOverview2 = 'vs last month +12.4%, mainly from the "Channel" group.';
  rsTabBodyDetail1   = 'Work order TY-2041 "Card container TTyCard landed"';
  rsTabBodyDetail2   = 'Owner Zhang San · published · 2026-07-16 10:12';
  rsTabBodyLog1      = '10:12 TY-2041 published';
  rsTabBodyLog2      = '11:03 TY-2042 published';
  rsTabBodyLog3      = '15:47 TY-2043 badge split into its own control';
  rsTabBodyNone      = '(no tab selected)';
  { Work-order states. These are UI vocabulary, not sample data: they are also the KEY the
    cell-style callback matches on, so both the rows and the matcher use these constants —
    translate one and the colouring follows. }
  rsStatePublished = 'Published';
  rsStateDraft     = 'Draft';
  rsStateAwaiting  = 'Awaiting scheduling';
  { TTyExPanel.Caption is another string-typed (untranslatable) property. }
  rsExpDataCaption = 'Collapse panel (≈ Ant Design''s Collapse)';
  { The org tree's node captions — a const array built in code. }
  rsOrgRoot      = 'TyControls Inc.';
  rsOrgRnd       = 'R&D center';
  rsOrgCtlGroup  = 'Control group';
  rsOrgThemeTeam = 'Theme group';
  rsOrgMarketing = 'Marketing dept.';
  rsOrgChannel   = 'Channel';
  rsOrgContent   = 'Content';
  rsOrgSupport   = 'Support dept.';
  rsOrgFrontline = 'front-line support';
  { Form page. TextHint / GroupBox.Caption / ToggleSwitch.Caption are string-typed, and the
    combo + check-group items are TStrings collections — none of them translate from the .lfm. }
  rsHintTitle      = 'Enter the work order title';
  rsHintDept       = 'Please choose an owning department';
  rsUrgentOn       = 'On';
  rsGrpNotifyChan  = 'Notification channel';
  rsChanEmail      = 'Email';
  rsChanSms        = 'SMS';
  rsChanInternal   = 'Internal message';
  rsTypeFeature    = 'Feature request';
  rsTypeDefect     = 'Defect';
  rsTypeConsulting = 'Consulting';
  rsTypeOther      = 'Other';
  rsTrfLeftTitle   = 'candidate';
  rsTrfRightTitle  = 'Selected';
  rsAdvPick        = 'Current selection: dept %s · region %s · %d notified';
  rsNoneSelected   = '(none selected)';

procedure TMainForm.LocalizeTexts;
begin
  // Card titles (TTyCard.Title is a plain string, so LCL never translates it — do it here).
  CardVisits.Title   := rsCardVisits;
  CardOrders.Title   := rsCardOrders;
  CardCpu.Title      := rsCardCpu;
  CardHealth.Title   := rsCardHealth;
  CardChart.Title    := rsCardChart;
  CardStatus.Title   := rsCardStatus;
  CardForm.Title     := rsCardForm;
  CardFormTodo.Title := rsCardFormTodo;
  CardModal.Title    := rsCardModal;
  CardProgress.Title := rsCardProgress;
  CardInline.Title   := rsCardInline;
  CardFloat.Title    := rsCardFloat;
  CardTabs.Title     := rsCardTabs;
  CardSeg.Title      := rsCardSeg;
  CardSteps.Title    := rsCardSteps;
  CardCrumb.Title    := rsCardCrumb;
  CardTree.Title     := rsCardTree;
  CardTags.Title     := rsCardTags;
  CardImage.Title    := rsCardImage;
  DarkSwitch.Caption := rsDark;
  // Nav groups + items are consts built into the Sider + breadcrumb; fill the (now var) arrays
  // from resourcestrings BEFORE BuildSider runs.
  NavGroups[0] := rsNavWorkbench;  NavGroups[1] := rsNavContent;    NavGroups[2] := rsNavInteraction;
  NavItems[0, 0] := rsNavDashboard; NavItems[0, 1] := rsNavDataDisplay;
  NavItems[1, 0] := rsNavListGrid;  NavItems[1, 1] := rsNavFormEntry;
  NavItems[2, 0] := rsNavFeedback;  NavItems[2, 1] := rsNavNavigation;
  { The Navigation demos' item LISTS: TStrings in the .lfm, which the translator never
    walks. Refill them (same order) so the strips read translated. }
  TabsDemo.Tabs.BeginUpdate;
  try
    TabsDemo.Tabs.Clear;
    TabsDemo.Tabs.Add(rsTabOverview);
    TabsDemo.Tabs.Add(rsTabDetail);
    TabsDemo.Tabs.Add(rsTabLog);
  finally
    TabsDemo.Tabs.EndUpdate;
  end;
  SegRange.Items.BeginUpdate;
  try
    SegRange.Items.Clear;
    SegRange.Items.Add(rsSegDayItem);
    SegRange.Items.Add(rsSegWeekItem);
    SegRange.Items.Add(rsSegMonthItem);
  finally
    SegRange.Items.EndUpdate;
  end;
  StepsFlow.Items.BeginUpdate;
  try
    StepsFlow.Items.Clear;
    StepsFlow.Items.Add(rsStepFill);
    StepsFlow.Items.Add(rsStepConfirm);
    StepsFlow.Items.Add(rsStepDone);
  finally
    StepsFlow.Items.EndUpdate;
  end;
  NavCrumb.Items.BeginUpdate;
  try
    NavCrumb.Items.Clear;
    NavCrumb.Items.Add(rsCrumbHome);
    NavCrumb.Items.Add(rsCrumbInteraction);
    NavCrumb.Items.Add(rsCrumbNavigation);
  finally
    NavCrumb.Items.EndUpdate;
  end;
  ExpData.Caption := rsExpDataCaption;
  { Form page: string-typed hints/captions + TStrings item lists. }
  EdName.TextHint := rsHintTitle;
  TsDept.TextHint := rsHintDept;
  SwUrgent.Caption := rsUrgentOn;
  RgChannel.Caption := rsGrpNotifyChan;
  RgChannel.Items.BeginUpdate;
  try
    RgChannel.Items.Clear;
    RgChannel.Items.Add(rsChanEmail);
    RgChannel.Items.Add(rsChanSms);
    RgChannel.Items.Add(rsChanInternal);
  finally
    RgChannel.Items.EndUpdate;
  end;
  RgChannel.ItemIndex := 0;
  CbKind.Items.BeginUpdate;
  try
    CbKind.Items.Clear;
    CbKind.Items.Add(rsTypeFeature);
    CbKind.Items.Add(rsTypeDefect);
    CbKind.Items.Add(rsTypeConsulting);
    CbKind.Items.Add(rsTypeOther);
  finally
    CbKind.Items.EndUpdate;
  end;
  CbKind.ItemIndex := 0;
  TrfMembers.LeftTitle := rsTrfLeftTitle;
  TrfMembers.RightTitle := rsTrfRightTitle;
  // Org tree node captions (same order as OrgParent) — filled before BuildOrgTree runs.
  OrgCaptions[0] := rsOrgRoot;
  OrgCaptions[1] := rsOrgRnd;       OrgCaptions[2] := rsOrgCtlGroup; OrgCaptions[3] := rsOrgThemeTeam;
  OrgCaptions[4] := rsOrgMarketing; OrgCaptions[5] := rsOrgChannel;  OrgCaptions[6] := rsOrgContent;
  OrgCaptions[7] := rsOrgSupport;   OrgCaptions[8] := rsOrgFrontline;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  LocalizeTexts;
  { Built-in themes are compiled in, so the switcher works without locating a
    themes/ folder. This example's home skin is 'antdesign' (not 'default'). }
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('antdesign');
  TyDefaultController.ThemeName := 'antdesign';
  { 这个示例默认跑**现代密度**(Web 尺度)—— 它是密度轴的视觉验收面。
    密度与皮肤正交:antdesign 皮肤 + 现代密度 = AntD 的观感 + Web 的疏密。 }
  TyDefaultController.Density := tdModern;
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // 标题栏用户菜单走同一套主题(全局默认控制器) —— 弹出体的背景/边框/高亮从主题解析。
  UserMenu.Controller := TyDefaultController;

  BuildSiderIcons;    // 先把图标集接上 Sider.Images,BuildSider 再按名给每行指定图标
  BuildSider;
  BuildList;
  BuildOrgTree;
  FeedSparklines;
  BuildSampleImage;   // 主题化的示例图:换肤会重画(见 ThemeComboChange)

  { 这两个平时是收起来的。Visible 只能在这里设:TTyEmpty / TTyPanel 都**没有 published
    Visible**,写进 .lfm 会在流式加载时炸(编译期看不出来 —— 这就是为什么要跑一次)。
      · 空态盖在列表那块矩形上,两者只有一个露面;
      · PopBox 是浮层的内容容器,平时躲着,Show 的时候被收编进弹窗。 }
  EmptyOrders.Visible := False;
  PopBox.Visible := False;

  PlaceEmptyAction;
  AdvancedPickChange(nil);
end;

{ 空态里那个按钮是 TTyEmpty 的子控件,但 alNone 的子控件用的是**原始**客户区坐标
  (LCL 的 AdjustClientRect 只作用于对齐的子控件),Top = 0 会压在插画上 —— 所以
  它必须自己对着 public 的 ActionRect 定位。带宽随窗口变,故每次 Resize 重摆。 }
procedure TMainForm.PlaceEmptyAction;
var
  r: TRect;
begin
  r := EmptyOrders.ActionRect;
  BtnEmptyNew.SetBounds(r.Left + (r.Right - r.Left - BtnEmptyNew.Width) div 2,
    r.Top, BtnEmptyNew.Width, BtnEmptyNew.Height);
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  PlaceEmptyAction;
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
  BuildSiderIcons;    // Sider 图标的颜色取自主题 —— 换肤重画
  BuildSampleImage;   // 示例图的颜色取自主题 —— 换肤就得重画
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // The light/dark @mode axis is independent of which theme ThemeCombo picked.
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
  BuildSiderIcons;   // 明暗切换也是主题变化 —— 图标跟着重画
  BuildSampleImage;
end;

{ =============================== Sider(导航) ============================== }

{ The Sider IS the pager: TTyPageControl's own header is hidden (TabHeight = 1 in
  the .lfm), so the only way to change page is an item here.

  为什么是 TTyListGroupPanel 而不是 TTyTreeView:Ant Design Pro 的 Sider 是**折叠
  菜单**,不是树。树表达的是"任意深度的层级数据,你来浏览它"(缩进、连线、展开箭头、
  逐节点数据);导航菜单表达的是"固定两层:一组一组的去处,点一个就去"。用树做导航,
  用户得到的是一个数据浏览器的外观(根节点、缩进、树线)和一堆用不上的能力,而真正
  需要的语义(分组标题栏可点开合、条目是目的地)反而得自己拼。手风琴控件把这两层
  直接做成了模型(AddGroup / AddItem)与事件(OnGroupToggle / OnItemClick)。

  分组与条目是**方法**建的(AddGroup / AddItem),.lfm 里存不下,所以和树节点一样
  留在代码里 —— 控件本身仍然在 .lfm 里设计。 }
procedure TMainForm.BuildSider;
var
  g, i, gi: Integer;
begin
  for g := Low(NavGroups) to High(NavGroups) do
  begin
    gi := Sider.AddGroup(NavGroups[g], SiderGroupIcon[g]);
    for i := Low(NavItems[g]) to High(NavItems[g]) do
      Sider.AddItem(gi, NavItems[g, i], SiderItemIcon[g, i]);
    // Expand AFTER the items exist — an accordion group with no rows has nothing to show.
    Sider.Expanded[gi] := True;
  end;
  // Open the dashboard: SelectItem fires OnItemClick, which does the actual paging.
  Sider.SelectItem(0, 0);
end;

{ 给 Sider 每一行画一个图标 —— Ant Design Pro 的 Sider 一行一个图标,这是它读起来更清楚
  的一大原因。图标集**没有任何外部资源**:每个字形当场用 BGRA 画进一个位图,交给
  TTyImageCollection(和 examples/listview 一模一样的手法 —— 这样就不会踩"exe 跑在
  lib/<target>/ 下、相对路径找不到图"的坑)。位图集是"放不进 .lfm 的运行时数据",和
  树节点、迷你趋势图的采样同类,所以留在代码里(这是允许的)。

  字形是**线描**风格(和 Ant Design 的 outlined 图标一致),用 BGRA 的 Canvas2D 描边 / 填充。
  颜色**取自主题**:用 Sider 条目的正文色(TyListGroupItem 的 TextColor)整批染色 —— 没有
  一处硬编码。为什么用正文色而不是强调色:强调色(primary 按钮底色)在某些皮肤上会和侧栏
  面色糊到一起(classic 的 primary 就是块灰,和 BuildSampleImage 里记的坑同一个),而正文色
  按定义就是"这个面上看得清的字色",在 15 套内置皮肤上都保证有对比;一套侧栏用一种图标色,
  也更像一个整体。换肤 / 切明暗时,ThemeComboChange / DarkSwitchChange 会再调一次本函数,
  用新主题色重画全部字形(AddBitmap 同名即替换,位图集版本号一变,缩放缓存自动失效)。 }
procedure TMainForm.BuildSiderIcons;
const
  G  = 64;     // 母版边长(px)。比任何一行会要的尺寸都大(16 逻辑 px,200% 下 32 px),
               // 于是每次取用都是清晰的 DOWNSAMPLE —— 见 examples/listview 的说明。
  SW = 5.5;    // 线描字形的描边宽度(母版尺度;downsample 后约 1.4 px @16、2.75 px @32)
var
  itemStyle: TTyStyleSet;
  tint: TBGRAPixel;

  { 把一段屏幕坐标的圆弧(deg:0=东,90=南,180=西,270=北)以折线追加到当前路径 ——
    不依赖 arc() 的扫掠方向,省去 y 向下带来的方向纠结。AMove=True 时以 moveTo 起头。 }
  procedure ArcTo(ctx: TBGRACanvas2D; cx, cy, r, deg0, deg1: Double; AMove: Boolean);
  var
    i: Integer;
    a: Double;
  begin
    for i := 0 to 24 do
    begin
      a := (deg0 + (deg1 - deg0) * i / 24) * Pi / 180;
      if (i = 0) and AMove then ctx.moveTo(cx + r * Cos(a), cy + r * Sin(a))
      else ctx.lineTo(cx + r * Cos(a), cy + r * Sin(a));
    end;
  end;

  { 把第 AKind 号字形用 tint 画进一张全新的 GxG 母版,按 AName 存进位图集(同名替换)。 }
  procedure Emit(const AName: string; AKind: Integer);
  var
    bmp: TBGRABitmap;
    ctx: TBGRACanvas2D;
    y: Integer;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      ctx := bmp.Canvas2D;
      ctx.lineCap := 'round';
      ctx.lineJoin := 'round';
      ctx.lineWidth := SW;
      ctx.strokeStyle(tint);
      ctx.fillStyle(tint);
      case AKind of
        0:  // 工作台 —— 2x2 应用格(四个填充圆角方块)
          begin
            bmp.FillRoundRectAntialias(12, 12, 28, 28, 3, 3, tint);
            bmp.FillRoundRectAntialias(36, 12, 52, 28, 3, 3, tint);
            bmp.FillRoundRectAntialias(12, 36, 28, 52, 3, 3, tint);
            bmp.FillRoundRectAntialias(36, 36, 52, 52, 3, 3, tint);
          end;
        1:  // 内容管理 —— 文件夹轮廓
          begin
            ctx.beginPath;
            ctx.moveTo(11, 23); ctx.lineTo(11, 18); ctx.lineTo(25, 18);
            ctx.lineTo(29, 23); ctx.lineTo(53, 23); ctx.lineTo(53, 49);
            ctx.lineTo(11, 49); ctx.closePath; ctx.stroke;
          end;
        2:  // 交互 —— 上下反向双箭头(交换)
          begin
            ctx.beginPath; ctx.moveTo(14, 25); ctx.lineTo(48, 25); ctx.stroke;
            ctx.beginPath; ctx.moveTo(42, 19); ctx.lineTo(48, 25); ctx.lineTo(42, 31); ctx.stroke;
            ctx.beginPath; ctx.moveTo(50, 39); ctx.lineTo(16, 39); ctx.stroke;
            ctx.beginPath; ctx.moveTo(22, 33); ctx.lineTo(16, 39); ctx.lineTo(22, 45); ctx.stroke;
          end;
        3:  // 仪表盘 —— 表盘弧 + 指针 + 轴心
          begin
            ctx.beginPath; ArcTo(ctx, 32, 42, 20, 180, 360, True); ctx.stroke;
            ctx.beginPath; ctx.moveTo(32, 42);
            ctx.lineTo(32 + 17 * Cos(300 * Pi / 180), 42 + 17 * Sin(300 * Pi / 180));
            ctx.stroke;
            bmp.FillEllipseAntialias(32, 42, 3.2, 3.2, tint);
          end;
        4:  // 数据展示 —— 柱状图(三根柱 + 基线)
          begin
            bmp.FillRectAntialias(15, 34, 23, 52, tint);
            bmp.FillRectAntialias(28, 22, 36, 52, tint);
            bmp.FillRectAntialias(41, 40, 49, 52, tint);
            ctx.beginPath; ctx.moveTo(12, 52.5); ctx.lineTo(52, 52.5); ctx.stroke;
          end;
        5:  // 列表 / 表格 —— 圆点 + 行线
          begin
            for y := 0 to 2 do
            begin
              bmp.FillEllipseAntialias(16, 20 + y * 12, 2.6, 2.6, tint);
              ctx.beginPath; ctx.moveTo(25, 20 + y * 12); ctx.lineTo(50, 20 + y * 12); ctx.stroke;
            end;
          end;
        6:  // 表单 / 录入 —— 卡片外框 + 字段行
          begin
            bmp.RectangleAntialias(12, 12, 52, 52, tint, SW * 0.85);
            ctx.lineWidth := SW * 0.85;
            ctx.beginPath; ctx.moveTo(19, 25); ctx.lineTo(45, 25); ctx.stroke;
            ctx.beginPath; ctx.moveTo(19, 33); ctx.lineTo(45, 33); ctx.stroke;
            ctx.beginPath; ctx.moveTo(19, 41); ctx.lineTo(37, 41); ctx.stroke;
          end;
        7:  // 反馈 —— 铃铛
          begin
            bmp.FillEllipseAntialias(32, 18, 2.6, 2.6, tint);         // 顶钮
            ctx.beginPath;                                            // 铃身:左壁 → 顶弧 → 右壁
            ctx.moveTo(20, 44); ctx.lineTo(20, 33);
            ArcTo(ctx, 32, 33, 12, 180, 360, False);
            ctx.lineTo(44, 44);
            ctx.stroke;
            ctx.beginPath; ctx.moveTo(15, 44); ctx.lineTo(49, 44); ctx.stroke;   // 铃口
            bmp.FillEllipseAntialias(32, 50, 3, 3, tint);            // 铃舌
          end;
      else  // 8:导航 —— 指南针(圆环 + 指针菱形)
        begin
          ctx.beginPath; ctx.arc(32, 32, 20, 0, 2 * Pi, False); ctx.stroke;
          ctx.beginPath;
          ctx.moveTo(32, 15); ctx.lineTo(35, 32); ctx.lineTo(32, 49); ctx.lineTo(29, 32);
          ctx.closePath; ctx.fill;
        end;
      end;
      FSiderIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

begin
  { 首次调用:建位图集 + 虚拟列表,建表(名字顺序 == SiderGroupIcon/SiderItemIcon 里的索引),
    并把列表挂到 Sider.Images。之后的调用只重画母版(换肤重染色)。 }
  if FSiderIcons = nil then
  begin
    FSiderIcons := TTyImageCollection.Create(Self);
    FSiderImages := TTyVirtualImageList.Create(Self);
    FSiderImages.Collection := FSiderIcons;
    FSiderImages.Names.Text :=
      'workbench' + LineEnding + 'content'  + LineEnding + 'interact'  + LineEnding +
      'dashboard' + LineEnding + 'data'     + LineEnding + 'list'      + LineEnding +
      'form'      + LineEnding + 'feedback' + LineEnding + 'nav';
    Sider.Images := FSiderImages;
  end;

  { 染色 = Sider 条目的正文色(主题解析,绝不硬编码;理由见上面的函数注释)。 }
  itemStyle := TyDefaultController.Model.ResolveStyle('TyListGroupItem', '', [tysNormal]);
  tint := TyColorToBGRA(itemStyle.TextColor);
  tint.alpha := 255;

  Emit('workbench', 0);
  Emit('content',   1);
  Emit('interact',  2);
  Emit('dashboard', 3);
  Emit('data',      4);
  Emit('list',      5);
  Emit('form',      6);
  Emit('feedback',  7);
  Emit('nav',       8);

  Sider.Invalidate;
end;

procedure TMainForm.SiderItemClick(Sender: TObject; AGroupIndex, AItemIndex: Integer);
begin
  ShowPage(AGroupIndex, AItemIndex);
end;

{ Switch the content area + rebuild the trail. Only ITEMS get here — a group's header
  band merely expands/collapses (OnGroupToggle), it is not a destination. }
procedure TMainForm.ShowPage(AGroup, AItem: Integer);
begin
  if (AGroup < Low(NavGroups)) or (AGroup > High(NavGroups)) then Exit;
  if (AItem < Low(NavItems[AGroup])) or (AItem > High(NavItems[AGroup])) then Exit;

  PageHost.ActivePageIndex := NavItemPage[AGroup, AItem];

  { The trail is just its Items, root first and CURRENT LOCATION LAST — the control owns
    the separators, the "last crumb is not a link" grammar and the elide-the-middle rule
    that the old string concatenation had no answer for. 末节就是页面标题:顶部条不再
    另画一个同名大标题(那是把同一个词写两遍)。 }
  Crumb.Items.BeginUpdate;
  try
    Crumb.Items.Clear;
    Crumb.Items.Add(rsCrumbHome);
    Crumb.Items.Add(NavGroups[AGroup]);
    Crumb.Items.Add(NavItems[AGroup, AItem]);
  finally
    Crumb.Items.EndUpdate;
  end;
end;

{ Only '首页' leads anywhere: the middle crumb is a Sider GROUP, which has no page of
  its own, and the last one is where you already are (the control never fires for it). }
procedure TMainForm.CrumbClick(Sender: TObject; AIndex: Integer);
begin
  if AIndex = 0 then
    Sider.SelectItem(0, 0);   // 首页 -> 工作台 / 仪表盘
end;

{ ================================ 仪表盘 =================================== }

{ Sparkline data cannot live in the .lfm (SetValues is a method, not a property),
  so the samples are seeded here. Everything visual about them is theme-driven. }
procedure TMainForm.FeedSparklines;
begin
  SparkVisits.SetValues([12, 18, 15, 24, 22, 31, 28, 36, 33, 41, 38, 47]);
  SparkOrders.SetValues([5, 9, 7, 12, 10, 15, 11, 18, 14, 21, 17, 24]);
end;

procedure TMainForm.QueueClick(Sender: TObject);
begin
  // The badge is a control of its own (Target = BtnQueue), so the count is ours to move.
  if BadgeQueue.Value > 0 then
    BadgeQueue.Value := BadgeQueue.Value - 1;
end;

procedure TMainForm.StatusDetailClick(Sender: TObject);
begin
  TyShowMessage(rsMsgSysStatus1 + LineEnding + rsMsgSysStatus2);
end;

{ 标题栏右上角的用户菜单(TTyMenuButton + TTyPopupMenu):对标 Ant Design Pro 头像下拉的
  个人设置 / 主题设置 / 退出登录。菜单组件与菜单项都在 .lfm 里,这里只放三条命令的响应,
  让下拉在示例里真的做点事。 }
procedure TMainForm.UserProfileClick(Sender: TObject);
begin
  TyShowMessage(rsMsgPersonal1 + LineEnding + rsMsgPersonal2);
end;

procedure TMainForm.UserThemeClick(Sender: TObject);
begin
  { 主题设置就在标题栏右侧(皮肤下拉 + 暗色开关)—— 直接把焦点交给皮肤下拉。 }
  if ThemeCombo.CanFocus then ThemeCombo.SetFocus;
  Toast.NotificationType := atInfo;
  Toast.Title := rsToastTheme;
  Toast.Message := rsToastThemeMsg;
  Toast.Show;
end;

procedure TMainForm.UserLogoutClick(Sender: TObject);
begin
  if TyMessageDlg(rsDlgSignOut, mtConfirmation, [mbYes, mbNo]) = mrYes then
    Close;
end;

{ 点标签的 x:控件先发 OnClose,未被否决才执行默认动作(Visible := False)。
  这里不否决 —— 标签消失本身就是反馈;宿主想自己管生命周期(Free / 从列表摘掉 /
  退场动画),把 AllowClose 置 False 即可。就近报告:每页有自己的说明标签。 }
procedure TMainForm.TagClosed(Sender: TObject; var AllowClose: Boolean);
var
  t: TTyTag;
  msg: string;
begin
  AllowClose := True;
  t := Sender as TTyTag;
  msg := rsTagRemoved + t.Caption;
  if t.Parent = CardStatus then
    LblStatusNote.Caption := msg
  else if t.Parent = PgList then
    LblListNote.Caption := msg
  else if t.Parent = CardTags then
    LblTagsNote.Caption := msg;
end;

{ ============================== 列表 / 表格 ================================ }

procedure TMainForm.BuildList;

  function AddCol(const ACaption: string; AWidth: Integer;
    AAlign: TAlignment): TTyGridColumn;
  begin
    Result := GridOrders.Header.Columns.Add as TTyGridColumn;
    Result.Text := ACaption;
    Result.Width := AWidth;
    Result.Alignment := AAlign;
  end;

  procedure Row(ARow: Integer; const ANo, ATitle, AOwner, AState, AWhen: string);
  begin
    GridOrders.Cells[0, ARow] := ANo;
    GridOrders.Cells[1, ARow] := ATitle;
    GridOrders.Cells[2, ARow] := AOwner;
    GridOrders.Cells[3, ARow] := AState;
    GridOrders.Cells[4, ARow] := AWhen;
  end;

begin
  GridOrders.Header.Columns.BeginUpdate;
  try
    AddCol(rsColNo,      140, taLeftJustify);
    AddCol(rsColTitle,   400, taLeftJustify);
    AddCol(rsColOwner,   120, taLeftJustify);
    AddCol(rsColStatus,  170, taLeftJustify);   // wide enough for 'Awaiting scheduling' in English
    AddCol(rsColUpdated, 230, taLeftJustify);
  finally
    GridOrders.Header.Columns.EndUpdate;
  end;
  { 状态列按语义上色 —— 数据是文字,颜色是呈现,走单元格样式回调。 }
  GridOrders.OnGetCellStyle := @OrdersGetCellStyle;
  { 整行选中的只读数据表:不要单元格焦点框(选区框 / 填充柄已由 gsmRow 抑制),
    整行高亮就是选中线索 —— 这才是 Web 表格的读法。 }
  GridOrders.ShowFocusCell := False;

  GridOrders.BeginUpdate;
  try
    GridOrders.RowCount := 14;
    Row( 0, 'TY-2041', 'Card container TTyCard landed',        'Zhang San', rsStatePublished, '2026-07-16 10:12');
    Row( 1, 'TY-2042', 'Tag TTyTag landed',             'Li Si', rsStatePublished, '2026-07-16 11:03');
    Row( 2, 'TY-2043', 'Badge TTyBadge split into its own control',     'Wang Wu', rsStatePublished, '2026-07-16 15:47');
    Row( 3, 'TY-2044', 'Inline alert bar TTyAlert',          'Zhang San', rsStateDraft,   '2026-07-17 09:20');
    Row( 4, 'TY-2045', 'Corner toast TTyNotification',   'Zhao Liu', rsStateDraft,   '2026-07-17 09:22');
    Row( 5, 'TY-2046', 'Empty state TTyEmpty',                'Li Si', rsStateDraft,   '2026-07-17 09:25');
    Row( 6, 'TY-2047', 'Segmented control TTySegmented',      'Wang Wu', rsStateDraft,   '2026-07-17 09:31');
    Row( 7, 'TY-2048', 'Pager TTyPagination',         'Zhao Liu', rsStateAwaiting, '2026-07-17 09:40');
    Row( 8, 'TY-2049', 'Step bar TTySteps',              'Zhang San', rsStateAwaiting, '2026-07-17 09:41');
    Row( 9, 'TY-2050', 'Breadcrumb TTyBreadcrumb',         'Li Si', rsStateAwaiting, '2026-07-17 09:42');
    Row(10, 'TY-2051', 'Transfer box TTyTransfer',           'Wang Wu', rsStateAwaiting, '2026-07-17 09:50');
    Row(11, 'TY-2052', 'Tree dropdown TTyTreeSelect',       'Zhao Liu', rsStateAwaiting, '2026-07-17 09:51');
    Row(12, 'TY-2053', 'Cascading select TTyCascader',         'Zhang San', rsStateAwaiting, '2026-07-17 09:52');
    Row(13, 'TY-2054', 'Popover TTyPopover',              'Li Si', rsStateAwaiting, '2026-07-17 09:53');
  finally
    GridOrders.EndUpdate;
  end;
  GridSelectionChanged(nil);
end;

{ 状态列的语义色 —— 数据里存的是"已发布/草稿/待排期"文字,这里只决定它画成什么颜色。
  换成真·数据表 TTyStringGrid 后能逐格着色(以前没有 Grid 控件才用 TTyListView 顶着)。 }
procedure TMainForm.OrdersGetCellStyle(Sender: TObject; ACol, ARow: Integer;
  var ABackground: TTyFill; var ATextColor: TTyColor;
  var AFontName: string; var AFontSize, AFontWeight: Integer;
  var AHAlign: TAlignment; var AVAlign: TTextLayout);
var
  s: string;
begin
  if ACol <> 3 then Exit;             { 只染状态列 }
  s := GridOrders.Cells[3, ARow];
  if s = rsStatePublished then ATextColor := TyRGB(22, 163, 74)       { 绿 }
  else if s = rsStateDraft then ATextColor := TyRGB(217, 119, 6)    { 橙 }
  else if s = rsStateAwaiting then ATextColor := TyRGB(37, 99, 235); { 蓝 }
end;

{ 整行选中(gsmRow):徽标显示当前选中的是第几行。选中态走 TTyBadge,数据仍归宿主。 }
procedure TMainForm.GridSelectionChanged(Sender: TObject);
begin
  if (GridOrders.Row >= 0) and (GridOrders.Row < GridOrders.RowCount) then
    BadgeSel.Value := GridOrders.Row + 1
  else
    BadgeSel.Value := 0;
end;

{ The empty state is not a MODE the list has — it is a second control on the same rect, and
  exactly one of the two is up (docs/controls/empty.md's own rule). }
procedure TMainForm.ShowEmptyState(AEmpty: Boolean);
begin
  GridOrders.Visible := not AEmpty;
  EmptyOrders.Visible := AEmpty;
  if AEmpty then PlaceEmptyAction;
end;

procedure TMainForm.ToggleEmptyClick(Sender: TObject);
begin
  ShowEmptyState(GridOrders.Visible);
end;

procedure TMainForm.EmptyNewClick(Sender: TObject);
begin
  // The action band's button is a REAL control parented into the placeholder.
  ShowEmptyState(False);
  Toast.NotificationType := atInfo;
  Toast.Title := rsToastEmpty;
  Toast.Message := rsToastEmptyMsg;
  Toast.Show;
end;

{ The pagination drives NOTHING itself: it owns no list and no query — it reports a page and
  the host re-fills from here. This showcase has 14 static rows, so all it re-fills is the
  counter beside it. }
procedure TMainForm.PageChange(Sender: TObject);
begin
  LblPageInfo.Caption := Format('Page %d / %d · %d total',
    [PagOrders.PageIndex + 1, PagOrders.PageCount, PagOrders.PageCount * 20]);
end;

{ ================================ 反馈 ===================================== }

procedure TMainForm.MsgClick(Sender: TObject);
begin
  TyShowMessage(rsMsgShow1 + LineEnding + rsMsgShow2);
end;

procedure TMainForm.ConfirmClick(Sender: TObject);
begin
  if TyMessageDlg(rsDlgSubmit, mtConfirmation, [mbYes, mbNo]) = mrYes then
    LblFeedback.Caption := rsFbConfirmYes
  else
    LblFeedback.Caption := rsFbConfirmNo;
end;

procedure TMainForm.InputClick(Sender: TObject);
var
  s: string;
begin
  s := 'Ops on-call';
  if TyInputQuery(rsDlgInputTitle, rsDlgInputPrompt, s) then
    LblFeedback.Caption := Format(rsFbInputGot, [s])
  else
    LblFeedback.Caption := rsFbInputCancel;
end;

procedure TMainForm.StepClick(Sender: TObject);
begin
  if PbTask.Position >= PbTask.Max then
    PbTask.Position := PbTask.Min
  else
    PbTask.Position := PbTask.Position + 10;
  LblProgress.Caption := Format(rsFbTaskProgress, [PbTask.Position]);
end;

{ 点警告条的 x:控件先发 OnClose,未被否决才执行默认动作(Visible := False)——
  和 TTyTag 的 x 是同一套契约。这里不否决:条子消失本身就是反馈。 }
procedure TMainForm.AlertClosed(Sender: TObject; var AllowClose: Boolean);
begin
  AllowClose := True;
  LblAlertNote.Caption := 'Alert bar closed: "' + (Sender as TTyAlert).Message + '」' +
    LineEnding + '(without vetoing AllowClose, the control just hides itself)';
end;

procedure TMainForm.ToastClick(Sender: TObject);
begin
  Toast.NotificationType := atInfo;
  Toast.Title := rsToast3Orders;
  Toast.Message := rsToast3OrdersMsg1 + LineEnding + rsToast3OrdersMsg2;
  Toast.Show;
end;

procedure TMainForm.ToastErrClick(Sender: TObject);
begin
  // Duration = 0 的那条留到你关它为止;两条共用右上角,会自己堆叠起来。
  ToastErr.Show;
end;

procedure TMainForm.PopoverClick(Sender: TObject);
begin
  Pop.Show;
end;

procedure TMainForm.PopOkClick(Sender: TObject);
begin
  Pop.Hide;
  Toast.NotificationType := atSuccess;
  Toast.Title := rsToastPublished;
  Toast.Message := rsToastPublishedMsg;
  Toast.Show;
end;

procedure TMainForm.PopCancelClick(Sender: TObject);
begin
  Pop.Hide;
end;

{ ================================ 导航 ===================================== }

{ 「标签切换,你好歹切换有个内容的变化啊,空白能展示啥?」—— 说得对:TTyTabSet 是**纯页签条**
  (它不承载页面,见 docs/controls/tabset.md),所以内容天生该由宿主来换;而这里以前既没
  接 OnChange、条下面也只是控件自绘的一块空白面板 —— 点了当然什么都不动。
  现在页签条只留页签(Height = TabHeight + 2,与 examples/tabset 同一写法),下面配一块
  真正的内容面板 TabsBody,由这里按 TabIndex 换内容 —— 这正是"条选中、宿主渲染"的语义。 }
procedure TMainForm.TabsDemoChange(Sender: TObject);
begin
  case TabsDemo.TabIndex of
    0: LblTabsBody.Caption := rsTabOverview + LineEnding +
         rsTabBodyOverview1 + LineEnding + rsTabBodyOverview2;
    1: LblTabsBody.Caption := rsTabDetail + LineEnding +
         rsTabBodyDetail1 + LineEnding + rsTabBodyDetail2;
    2: LblTabsBody.Caption := rsTabLog + LineEnding +
         rsTabBodyLog1 + LineEnding + rsTabBodyLog2 + LineEnding + rsTabBodyLog3;
  else
    LblTabsBody.Caption := rsTabBodyNone;
  end;
  LblNavNote.Caption := Format(rsEchoTab, [TabsDemo.Tabs[TabsDemo.TabIndex]]);
end;

procedure TMainForm.SegRangeChange(Sender: TObject);
begin
  if SegRange.ItemIndex < 0 then Exit;
  { 分段控制器切的是一个**值**(视图范围),所以它换的是同一个指标的口径 —— 就地给出
    那个值,而不是只在页尾写一句"你点了周"。 }
  case SegRange.ItemIndex of
    0: LblSegValue.Caption := rsSegDay;
    1: LblSegValue.Caption := rsSegWeek;
    2: LblSegValue.Caption := rsSegMonth;
  end;
  LblNavNote.Caption := Format(rsEchoSeg, [SegRange.Items[SegRange.ItemIndex]]);
end;

procedure TMainForm.StepsFlowChange(Sender: TObject);
begin
  if (StepsFlow.StepIndex < 0) or (StepsFlow.StepIndex >= StepsFlow.Count) then
  begin
    LblNavNote.Caption := rsEchoStepOut;
    Exit;
  end;
  LblNavNote.Caption := Format(rsEchoStep,
    [StepsFlow.StepIndex + 1, StepsFlow.Items[StepsFlow.StepIndex]]);
end;

procedure TMainForm.NavCrumbClick(Sender: TObject; AIndex: Integer);
begin
  LblNavNote.Caption := Format(rsEchoCrumb, [NavCrumb.Items[AIndex]]);
end;

procedure TMainForm.NavToolClick(Sender: TObject);
begin
  LblNavNote.Caption := Format(rsEchoTool, [(Sender as TTyButton).Caption]);
end;

procedure TMainForm.MenuItemClick(Sender: TObject);
begin
  if Sender = MnuFileExit then
    Close
  else if Sender = MnuViewSider then
  begin
    // Ant Design Pro 的 Sider 是可折叠的;这里整条(树 + 分隔条)一起收起,
    // 平时也可以直接拖 TTySplitter 把它拉窄。
    Sider.Visible := not Sider.Visible;
    SiderSplit.Visible := Sider.Visible;
  end
  else
    LblNavNote.Caption := Format(rsEchoMenu,
      [StringReplace((Sender as TMenuItem).Caption, '&', '', [rfReplaceAll])]);
end;

{ ============================== 数据展示 =================================== }

procedure TMainForm.BuildOrgTreeInto(ATree: TTyTreeView);
var
  nodes: TOrgNodes;
  data: POrgRec;
  par: PTyTreeNode;
  i: Integer;
begin
  nodes := Default(TOrgNodes);
  ATree.NodeDataSize := SizeOf(TOrgRec);
  for i := 0 to High(OrgCaptions) do
  begin
    if OrgParent[i] < 0 then
      par := nil
    else
      par := nodes[OrgParent[i]];
    nodes[i] := ATree.AddChild(par);
    data := POrgRec(ATree.GetNodeData(nodes[i]));
    if data <> nil then data^.Id := i;
  end;
  ATree.FullExpand;
end;

procedure TMainForm.BuildOrgTree;
begin
  BuildOrgTreeInto(DataTree);
  { The SAME org tree, twice: once spread across a panel (数据展示), once folded into a
    form row's drop (表单页). TTyTreeSelect.Tree is not published — a virtual tree's nodes
    are pointers, so there is nothing for the .lfm to stream and both the structure and the
    text event are wired here. }
  TsDept.Tree.OnGetText := @DataTreeGetText;
  BuildOrgTreeInto(TsDept.Tree);
end;

procedure TMainForm.DataTreeGetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var AText: string);
var
  data: POrgRec;
begin
  data := POrgRec(Sender.GetNodeData(Node));
  if (data <> nil) and (data^.Id >= Low(OrgCaptions)) and (data^.Id <= High(OrgCaptions)) then
    AText := OrgCaptions[data^.Id]
  else
    AText := '';
end;

{ 「数据展示的图片没有显示」的真因:原来这里猜三条相对路径去找 themes/assets/background.jpg,
  但 exe 跑在 examples/antdesign/lib/<target>/ 下,那张图在仓库根的 themes/assets/ ——
  三条候选( ../../ 、 ../ 、 ./ )**没有一条**指得到它(真实相对路径是 ../../../../)。
  LoadFromFile miss 时按契约静默清空、不报错,于是 ImgView 永远是一个空的主题化画框。

  与其继续赌一个"运行时不一定在"的文件,不如在代码里画一张:BGRABitmap 画一幅抽象
  风景(天空渐变 + 太阳 + 两重山脊 + 水面 + 倒影)。颜色**全部从当前主题解析**——
  accent 取 primary 按钮的底色,画布与墨色取卡片的底色 / 文字色 —— 所以换肤、切明暗
  时这张图跟着变,和这个 example 里其它一切一样是主题令牌驱动的,没有硬编码颜色。
  位图是"放不进 .lfm 的数据",和树节点、迷你趋势图的采样同类,故留在代码里。 }
procedure TMainForm.BuildSampleImage;

  { 从一个 fill 里取一个有代表性的实色:实色取 Color,渐变取起点色,其余回落。 }
  function FillInk(const AFill: TTyFill; ADefault: TTyColor): TTyColor;
  begin
    case AFill.Kind of
      tfkSolid:          Result := AFill.Color;
      tfkLinearGradient: Result := AFill.GradFrom;
    else
      Result := ADefault;
    end;
  end;

  { 线性插值两个颜色(t = 0 -> a,t = 1 -> b),结果不透明。 }
  function Mix(const a, b: TBGRAPixel; t: Single): TBGRAPixel;
  begin
    Result := BGRA(
      Round(a.red   + (Integer(b.red)   - a.red)   * t),
      Round(a.green + (Integer(b.green) - a.green) * t),
      Round(a.blue  + (Integer(b.blue)  - a.blue)  * t),
      255);
  end;

  { 同色但换透明度 —— 山脊 / 倒影靠它压出层次。 }
  function Fade(const c: TBGRAPixel; AAlpha: Byte): TBGRAPixel;
  begin
    Result := c;
    Result.alpha := AAlpha;
  end;

  { 两色是否近到画上去看不出来(曼哈顿距离,够用)。 }
  function TooClose(const a, b: TBGRAPixel): Boolean;
  begin
    Result := (Abs(Integer(a.red) - b.red) + Abs(Integer(a.green) - b.green) +
               Abs(Integer(a.blue) - b.blue)) < 60;
  end;

const
  ImgW = 480;
  ImgH = 320;
var
  cardStyle, accentStyle: TTyStyleSet;
  accent, canvasCol, ink: TBGRAPixel;
  bmp: TBGRABitmap;
  grad: TBGRAGradientScanner;
  horizon: Integer;
begin
  { 主题解析:accent = primary 按钮的底色(这就是"这套皮肤的强调色"),
    画布 / 墨色 = 卡片自己的底色与文字色(图就摆在卡片里)。 }
  accentStyle := TyDefaultController.Model.ResolveStyle('TyButton', 'primary', []);
  cardStyle   := TyDefaultController.Model.ResolveStyle('TyCard', '', []);
  accent    := TyColorToBGRA(FillInk(accentStyle.Background, cardStyle.TextColor));
  canvasCol := TyColorToBGRA(FillInk(cardStyle.Background, cardStyle.TextColor));
  ink       := TyColorToBGRA(cardStyle.TextColor);
  accent.alpha := 255; canvasCol.alpha := 255; ink.alpha := 255;

  { 有的皮肤压根没有"彩色强调色":classic 的 primary 按钮就是块 #C0C0C0 的灰按钮面,
    和卡片底色一模一样 —— 照着画,天空和太阳会糊成一整片灰,等于又白给。这时改用墨色
    调出强调色:仍然全程主题驱动(只是换一个"这张皮肤里看得见"的令牌),灰皮肤就得到
    一张灰阶风景,而不是一张空画布。 }
  if TooClose(accent, canvasCol) then
    accent := Mix(ink, canvasCol, 0.35);

  horizon := Round(ImgH * 0.62);

  bmp := TBGRABitmap.Create(ImgW, ImgH, canvasCol);
  try
    { 天空:强调色 -> 画布色的竖向渐变。 }
    grad := TBGRAGradientScanner.Create(Mix(accent, canvasCol, 0.35),
      Mix(accent, canvasCol, 0.92), gtLinear, PointF(0, 0), PointF(0, horizon));
    try
      bmp.FillRect(0, 0, ImgW, horizon, grad, dmSet);
    finally
      grad.Free;
    end;

    { 太阳。 }
    bmp.FillEllipseAntialias(ImgW * 0.74, horizon * 0.42, 34, 34, Fade(accent, 235));

    { 远山:淡一层的强调色。 }
    bmp.FillPolyAntialias([PointF(-10, horizon), PointF(120, horizon - 96),
      PointF(232, horizon), PointF(-10, horizon)], Fade(accent, 120));
    bmp.FillPolyAntialias([PointF(150, horizon), PointF(300, horizon - 128),
      PointF(452, horizon), PointF(150, horizon)], Fade(accent, 150));

    { 近山:墨色压暗,拉开前后。 }
    bmp.FillPolyAntialias([PointF(-10, horizon), PointF(96, horizon - 54),
      PointF(210, horizon - 8), PointF(340, horizon - 66), PointF(490, horizon),
      PointF(-10, horizon)], Fade(ink, 60));

    { 水面:比天空更暗、更饱和的一段。 }
    grad := TBGRAGradientScanner.Create(Mix(accent, ink, 0.45),
      Mix(accent, canvasCol, 0.55), gtLinear, PointF(0, horizon), PointF(0, ImgH));
    try
      bmp.FillRect(0, horizon, ImgW, ImgH, grad, dmSet);
    finally
      grad.Free;
    end;

    { 太阳在水面的倒影 + 两道波纹。 }
    bmp.FillEllipseAntialias(ImgW * 0.74, horizon + 16, 30, 7, Fade(accent, 130));
    bmp.FillEllipseAntialias(ImgW * 0.74, horizon + 34, 20, 4, Fade(accent, 90));
    bmp.FillEllipseAntialias(ImgW * 0.30, horizon + 52, 54, 4, Fade(canvasCol, 70));

    { 这张插画按主题色(accent/ink/canvas)运行时生成,不是静态资源。直接把 BGRA 交给
      视图:早先经 TPicture(MakeBitmapCopy)往返,不透明图会被丢成全黑 —— 那才是"图片"
      一直是黑框的真因,不是路径找不到文件。AssignBitmap 走 LoadFromFile 同一条 FSource 路。 }
    ImgView.AssignBitmap(bmp);
  finally
    bmp.Free;
  end;
end;

{ ================================ 表单 ===================================== }

{ 提交成功是一条 toast,不是模态框:它不拦人、自己会走。模态框留给真正要答案的事
  (见反馈页的确认对话框)。 }
procedure TMainForm.SubmitClick(Sender: TObject);
begin
  Toast.NotificationType := atSuccess;
  Toast.Title := 'Work order submitted';
  Toast.Message :=
    Format('%s · amount %.2f · %s', [EdName.Text, EdAmount.Value, CbKind.Text]) + LineEnding +
    Format('Weight %d · satisfaction %.1f', [TrkWeight.Position, RateScore.Value]) + LineEnding +
    Format('Dept %s · region %s · notify %d people',
      [TsDept.Text, CasRegion.Text, TrfMembers.Selected.Count]);
  Toast.Show;
end;

procedure TMainForm.ResetClick(Sender: TObject);
begin
  EdName.Text := '';
  EdAmount.Value := 0;
  CbKind.ItemIndex := 0;
  SwUrgent.Checked := False;
  TrkWeight.Position := 60;
  RateScore.Value := 0;
  ChkNotify.Checked := True;
  RgChannel.ItemIndex := 0;
  TsDept.ClearSelection;
  CasRegion.Clear;
end;

{ 树形下拉 / 级联 / 穿梭框共用一个回声:三个控件报告的都是"选了什么",不是"点了哪"。 }
procedure TMainForm.AdvancedPickChange(Sender: TObject);

  function Pick(const AText: string): string;
  begin
    if AText = '' then Result := rsNoneSelected else Result := AText;
  end;

begin
  LblAdvPick.Caption := Format(rsAdvPick,
    [Pick(TsDept.Text), Pick(CasRegion.Text), TrfMembers.Selected.Count]);
end;

end.
