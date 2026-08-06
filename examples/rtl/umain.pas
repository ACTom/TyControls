unit umain;

{ Right-to-left mirroring and bidirectional text -- the LOOK-AT-IT example.

  Everything this window shows was built and verified headlessly, by pixel probes and pure
  geometry assertions (tests/test.rtl.pas, test.rtl.bars.pas, test.bidi.pas, test.grid.bidi.pas,
  test.edit.bidi.pas, test.memo.bidi.pas). A specific list of questions is structurally
  unreachable from a test here, and this example exists to make each of them answerable by a
  human with a mouse:

    - do Arabic letters actually SHAPE (join into their contextual forms) on GTK and Cocoa?
      The Windows answer was measured and pinned; the other two are the platform text engine's
      and only running there answers them;
    - does the status bar's size grip really resize from the BOTTOM-LEFT? It hands the OS
      HTBOTTOMLEFT and no headless test can confirm the OS obeys;
    - which way do submenus actually cascade? DoOpenSubmenu needs a live window handle;
    - anything involving LCL's align engine, which never runs for a form that was never shown;
    - and the whole class of "mirrored control that answers clicks on the old side" that no
      guard anticipated, which is found by clicking around.

  TWO SWITCHES, DELIBERATELY NOT ONE. Direction and language are independent, because a bug
  report needs to say WHICH of the two is wrong:

    English + right-to-left  -- pure geometry. Every box, gutter, indicator and tab moves; the
                                text inside them is still ordinary left-to-right English, so
                                anything that looks wrong here is the MIRROR.
    Arabic  + left-to-right  -- pure text. Nothing moves; the shaping and the reordering
                                inside each string are all that changed, so anything wrong
                                here is the TEXT ENGINE, not the layout.
    Arabic  + right-to-left  -- a genuine Arabic application, which is the only state in which
                                the question "does this look right to a native reader?" can
                                actually be asked.

  Fusing them into one switch would make every defect ambiguous, which is why there are two.

  WHY THE STRINGS ARE HERE AND THE LAYOUT IS NOT. umain.lfm holds every control, bound and
  relationship; this unit holds the string TABLE, because which language is showing is
  behaviour, not design. The .lfm's own captions are the English ones and stay the startup
  view (see FormCreate for why the table is not applied there).

  WHY THE DIRECTION SWITCH IS CODE. BiDiMode is deliberately NOT published on any control --
  tests/test.parity.pas (LyingPropertiesStayUnpublished) pins that, because mirroring is
  implemented for a MINORITY of the library and the Object Inspector must not offer a property
  most controls ignore. It works perfectly well from code, which is what DirSwitchChange does.

  WHY ARABIC IS WORTH THE TROUBLE, and it is not decoration. Every control draws text through
  a different path, and only ONE of them had ever had Arabic in it. The sharpest case is the
  grid: TTyCustomGrid.DrawCellText does not call TTyPainter.DrawText at all -- it lays text
  into its own cached bitmap, because that cache is what makes a large table scroll. Putting
  Arabic through it found a real defect (a cell starting in Arabic and ending in Latin came
  out with its two halves swapped, while the same string in the label beside it came out
  right); the fix is in tyControls.Grid.pas and is pinned by tests/test.grid.bidi.pas. Cell
  text, the row-number gutter, footer totals, filter text and wrapped header captions all go
  through that one function, and menu rows, status-bar panels, tab captions and tree nodes are
  each their own path again.

  Non-ASCII strings are written as Lazarus numeric escapes ('...'#1575#1604...) rather than as
  raw UTF-8 bytes, in the .lfm and in Pascal alike. That keeps the source pure ASCII and
  immune to a toolchain that has mangled non-ASCII source literals before; the compiler turns
  #NNNN into the right UTF-8 at build time, and CheckStringTableEncoding below reads the bytes
  back at run time and says so on the status bar, so a mangled build cannot look like a
  working one.

  PAGE 4 EXISTS FOR THE OPPOSITE REASON TO PAGES 1-3. Those show what moves; page 4 shows
  three controls that deliberately do NOT, so a viewer can satisfy themselves the exclusions
  were decided rather than forgotten -- a judgement no guard can make for them.
  TTyDropDownButton's arrow zone, TTyButtonGroup's segments and TTyValueListEditor's two
  columns all share one reason: each hit-tests from a SECOND, independent computation of x
  (TyDropArrowHit, TySegmentAt, SplitXDp) rather than from the rectangle it paints. Mirroring
  the paint alone gives "drawn right, answers wrong", which this library has already shipped
  three times. tests/test.rtl.pas pins all three exclusions; this page is where you press
  them and check for yourself.

  The other half of page 4 is how a HOST turns any of this on, because none of it is
  discoverable from the Object Inspector: BiDiMode is not published, TTyScrollBar's
  MirrorHorizontal is opt-in and deliberately not wired to BiDiMode (a bar must never mirror
  before the content it scrolls), TTyStringGrid sets that for its own bar so you do not, and
  Arabic literals in Pascal need {$codepage UTF8}. Every one of those is something this
  example had to work out, which is the definition of something a reader will have to too.

  Two more things about umain.lfm, both learned the hard way. It is NOT Pascal and takes no
  brace comments -- one makes the build fail in the resource step with "Wrong token type:
  Symbol expected", which is why the geometry note that belongs beside the title bar is here
  instead: the skin switcher's Left values stop 3 * TyTitleButtonWidth (= 138 px) short of
  the right edge, because the minimise / maximise / close buttons are painted there and a
  windowed control dropped on top of them wins. }

{$mode objfpc}{$H+}
{ REQUIRED, and its absence is silent. A '#1575' escape in PASCAL source is a UnicodeString
  constant that the compiler converts to this unit's string codepage -- which without this
  directive is the system ANSI page, where no Arabic letter exists, so every one of them
  becomes a literal '?'. The build succeeds and the window fills with question marks.
  (The same escapes in umain.lfm are fine without it: those go through the LFM parser, which
  writes UTF-8 itself. The two mechanisms look identical in the source and are not.)
  CheckStringTableEncoding below re-checks this at run time rather than trusting the comment. }
{$codepage UTF8}

interface

uses
  Classes, SysUtils, Forms, Controls, Menus,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.Divider, tyControls.Panel,
  tyControls.CheckBox, tyControls.GroupBox, tyControls.CheckGroup, tyControls.RadioGroup,
  tyControls.Button, tyControls.GlyphButtons, tyControls.ColorButton,
  tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.Edit, tyControls.Memo,
  tyControls.IconFont, tyControls.Menu, tyControls.StatusBar,
  tyControls.PageControl, tyControls.TabSheet, tyControls.ScrollBox,
  tyControls.Columns, tyControls.Grid, tyControls.ListView, tyControls.TreeView,
  { Page 4 only: the three controls that deliberately do NOT mirror. }
  tyControls.DropButtons, tyControls.ButtonGroup, tyControls.ValueListEditor;

type
  { The two axes this window exists to separate. }
  TUiLang = (ulEnglish, ulArabic);

  TStrId = (
    sidFormCaption, sidTitleBar, sidDark,
    sidLangSwitch, sidLangState, sidDirSwitch,
    sidDirLtr, sidDirRtl, sidLegend,
    sidTry, sidTabForm, sidTabData,
    sidTabText, sidDivFormAll, sidAlignLeft,
    sidAlignRight, sidAlignCenter, sidChkPlain,
    sidChkFlipped, sidChkGrayed, sidRadOne,
    sidRadTwo, sidDivIndent, sidPanelCap,
    sidContainerNote, sidRadGrp, sidChkGrp,
    sidGrpBox, sidGrpField, sidGrpEdit,
    sidGrpNote, sidGrpAfter, sidBtnPlain,
    sidBtnCapLeft, sidBtnGlyphL, sidBtnGlyphR,
    sidBtnBadge, sidColorDlg, sidDivGlyphNote,
    sidFormNote, sidDivGrid, sidColName,
    sidColRegion, sidColQty, sidColSettled,
    sidColAction, sidCellOpen, sidGridNote,
    sidDivLv, sidColSize, sidColKind,
    sidDivTv, sidColNode, sidKindFolder,
    sidKindPlaylist, sidKindWorkspace, sidKindFile,
    sidChildFmt, sidDataNote, sidDivText,
    sidLblArabic, sidLblHebrew, sidLblMixed,
    sidLblChinese, sidDivChrome, sidTextNote,
    sidDivScroll, sidSbChildFmt, sidScrollNote,
    sidDivMini, sidMpOne, sidMpTwo,
    sidMpThree, sidMpFour, sidMpNoteOne,
    sidMpNoteTwo, sidMpNoteThree, sidMpNoteFour,
    sidMiniNote, sidMnuFile, sidMnuNew,
    sidMnuOpen, sidMnuRecent, sidMnuRecent1,
    sidMnuRecent2, sidMnuOlder, sidMnuOld1,
    sidMnuOld2, sidMnuExit, sidMnuEdit,
    sidMnuCut, sidMnuCopy, sidMnuPaste,
    sidMnuDirection, sidMnuDirLtr, sidMnuDirRtl,
    sidMnuLanguage, sidMnuLangEn, sidMnuLangAr,
    sidMnuHelp, sidMnuAbout, sidPopBanner,
    sidPopHdr, sidPopFirst, sidPopSub,
    sidPopSub1, sidPopSub2, sidPopDeep,
    sidPopDeep1, sidPopShortcut, sidReady,
    sidStatusLtr, sidStatusRtl, sidGripLtr,
    sidGripRtl, sidSayDirLtr, sidSayDirRtl,
    sidSayLangEn, sidSayLangAr, sidSayMenuFmt,
    sidSayCellFmt, sidTabFenced, sidDivFenced,
    sidFencedIntro, sidDivDrop, sidDropBtn,
    sidDropNote, sidDivGroup, sidGroupNote,
    sidDivVList, sidVListNote, sidVlKey1,
    sidVlVal1, sidVlKey2, sidVlVal2,
    sidVlKey3, sidVlVal3, sidDivHow,
    sidHow1, sidHow1Code, sidHow2,
    sidHow3, sidHow3Code, sidHow4,
    sidHow5);

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;

    MenuBar1: TTyMenuBar;
    MainMenu1: TMainMenu;
    MnuFile: TMenuItem;
    MnuFileNew: TMenuItem;
    MnuFileOpen: TMenuItem;
    MnuFileSep: TMenuItem;
    MnuFileRecent: TMenuItem;
    MnuRecent1: TMenuItem;
    MnuRecent2: TMenuItem;
    MnuRecentMore: TMenuItem;
    MnuRecentOld1: TMenuItem;
    MnuRecentOld2: TMenuItem;
    MnuFileSep2: TMenuItem;
    MnuFileExit: TMenuItem;
    MnuEdit: TMenuItem;
    MnuEditCut: TMenuItem;
    MnuEditCopy: TMenuItem;
    MnuEditDisabled: TMenuItem;
    MnuDirection: TMenuItem;
    MnuDirLtr: TMenuItem;
    MnuDirRtl: TMenuItem;
    MnuLanguage: TMenuItem;
    MnuLangEn: TMenuItem;
    MnuLangAr: TMenuItem;
    MnuHelpRight: TMenuItem;
    MnuHelpAbout: TMenuItem;

    Popup1: TTyMenuEx;
    PopHdr: TMenuItem;
    PopFirst: TMenuItem;
    PopSub: TMenuItem;
    PopSub1: TMenuItem;
    PopSub2: TMenuItem;
    PopSubDeep: TMenuItem;
    PopSubDeep1: TMenuItem;
    PopSep: TMenuItem;
    PopShortcut: TMenuItem;

    Icons: TTyIconFont;

    HeadPanel: TTyPanel;
    DirSwitch: TTyToggleSwitch;
    LblDirState: TTyLabel;
    LangSwitch: TTyToggleSwitch;
    LblLangState: TTyLabel;
    LblLegend: TTyLabel;
    LblTry: TTyLabel;

    Pages: TTyPageControl;

    PgForm: TTyTabSheet;
    DivFormAll: TTyDivider;
    LblAlignLeft: TTyLabel;
    LblAlignRight: TTyLabel;
    LblAlignCenter: TTyLabel;
    ChkPlain: TTyCheckBox;
    ChkFlipped: TTyCheckBox;
    ChkGrayed: TTyCheckBox;
    RadOne: TTyRadioButton;
    RadTwo: TTyRadioButton;
    DivIndent: TTyDivider;
    PanelCap: TTyPanel;
    LblContainerNote: TTyLabel;
    RadGrp: TTyRadioGroup;
    ChkGrp: TTyCheckGroup;
    GrpBox: TTyGroupBox;
    LblGrpField: TTyLabel;
    EdGrp: TTyEdit;
    LblGrpNote: TTyLabel;
    LblGrpAfter: TTyLabel;
    BtnPlain: TTyButton;
    BtnCapLeft: TTyButton;
    BtnGlyphLeft: TTyGlyphButton;
    BtnGlyphRight: TTyGlyphButton;
    BtnColor: TTyColorButton;
    BtnBadge: TTyButton;
    DivGlyphNote: TTyDivider;
    LblFormNote: TTyLabel;

    PgData: TTyTabSheet;
    DivGrid: TTyDivider;
    Grid: TTyStringGrid;
    LblGridNote: TTyLabel;
    DivLv: TTyDivider;
    LV: TTyListView;
    DivTv: TTyDivider;
    Tree: TTyTreeView;
    LblDataNote: TTyLabel;

    PgText: TTyTabSheet;
    DivText: TTyDivider;
    LblArabic: TTyLabel;
    EdArabic: TTyEdit;
    MeArabic: TTyMemo;
    LblHebrew: TTyLabel;
    EdHebrew: TTyEdit;
    MeHebrew: TTyMemo;
    LblMixed: TTyLabel;
    EdMixed: TTyEdit;
    MeMixed: TTyMemo;
    LblChinese: TTyLabel;
    EdChinese: TTyEdit;
    MeChinese: TTyMemo;
    DivChrome: TTyDivider;
    LblTextNote: TTyLabel;
    DivScroll: TTyDivider;
    ScrollDemo: TTyScrollBox;
    SbBtn1: TTyButton;
    SbBtn2: TTyButton;
    SbBtn3: TTyButton;
    SbBtn4: TTyButton;
    SbBtn5: TTyButton;
    SbBtn6: TTyButton;
    LblScrollNote: TTyLabel;
    DivMini: TTyDivider;
    MiniPager: TTyPageControl;
    MpOne: TTyTabSheet;
    LblMpOne: TTyLabel;
    MpTwo: TTyTabSheet;
    LblMpTwo: TTyLabel;
    MpThree: TTyTabSheet;
    LblMpThree: TTyLabel;
    MpFour: TTyTabSheet;
    LblMpFour: TTyLabel;
    LblMiniNote: TTyLabel;

    PgFenced: TTyTabSheet;
    DivFenced: TTyDivider;
    LblFencedIntro: TTyLabel;
    DivDrop: TTyDivider;
    DropBtn: TTyDropDownButton;
    LblDropNote: TTyLabel;
    DivGroup: TTyDivider;
    BtnGroup: TTyButtonGroup;
    LblGroupNote: TTyLabel;
    DivVList: TTyDivider;
    VList: TTyValueListEditor;
    LblVListNote: TTyLabel;
    DivHow: TTyDivider;
    LblHow1: TTyLabel;
    EdHow1: TTyEdit;
    LblHow2: TTyLabel;
    LblHow3: TTyLabel;
    EdHow3: TTyEdit;
    LblHow4: TTyLabel;
    LblHow5: TTyLabel;

    StatusBar1: TTyStatusBar;

    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure DirSwitchChange(Sender: TObject);
    procedure LangSwitchChange(Sender: TObject);
    procedure MenuItemClicked(Sender: TObject);
    procedure MenuFileExitClick(Sender: TObject);
    procedure MenuDirectionClick(Sender: TObject);
    procedure MenuLanguageClick(Sender: TObject);
    procedure GridCellButtonClick(Sender: TObject; ACol, ARow: Integer);
    procedure GridGetNodeLevel(Sender: TObject; ARow: Integer; var ALevel: Integer);
    procedure GridGetHasChildren(Sender: TObject; ARow: Integer; var AHas: Boolean);
    procedure TreeInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure TreeInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
      var ChildCount: Cardinal);
    procedure TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; Column: Integer;
      TextType: TTyVSTTextType; var CellText: string);
  private
    FApplying: Boolean;                 { re-entry guard: the menu and the switch drive each other }
    FLang: TUiLang;                     { which column of UiText is showing }
    FRtl: Boolean;                      { which way the form currently reads }
    function  S(AId: TStrId): string;   { the active language's copy of one string }
    procedure FillGrid;
    procedure FillListView;
    procedure FillValueList;
    procedure ApplyLanguage(ALang: TUiLang);
    procedure RefreshDirectionText;
    procedure ApplyDirection(ARightToLeft: Boolean);
    procedure SetBiDiDeep(AControl: TControl; AMode: TBiDiMode);
    procedure Say(const AText: string);
    function  CheckStringTableEncoding: string;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ ------------------------------------------------------------------ the strings --

  ONE table, two columns, every visible string in the window. Keeping English and Arabic side
  by side is the point: a missing translation is a hole you can see while reading, and the
  array being indexed by TStrId means adding an id without a row does not compile.

  The Arabic is deliberately PLAIN -- "Name", "Quantity", "Open", "Ready". Short factual
  labels are what an Arabic business application actually says, and a word this author was
  sure of beats a more elegant one guessed at, because these strings get read by people who
  would notice. Numbers are the ASCII digits an Arabic UI normally shows (123), not Eastern
  Arabic-Indic numerals; there is exactly ONE cell using the latter and it labels itself. }

const
  UiText: array[TStrId, TUiLang] of string = (
    { sidFormCaption }
    ('TyControls - right-to-left mirroring and bidirectional text',
     #1575#1604#1575#1606#1593#1603#1575#1587' '#1608#1575#1604#1606#1589' '#1579#1606#1575#1574#1610' '#1575#1604#1575#1578#1580#1575#1607' - TyControls'),
    { sidTitleBar }
    ('RTL / BiDi  -  TyControls',
     #1575#1604#1606#1589' '#1579#1606#1575#1574#1610' '#1575#1604#1575#1578#1580#1575#1607' - TyControls'),
    { sidDark }
    ('Dark',
     #1583#1575#1603#1606),
    { sidLangSwitch }
    ('Arabic interface',
     #1608#1575#1580#1607#1577' '#1593#1585#1576#1610#1577),
    { sidLangState }
    ('Language: English',
     #1575#1604#1604#1594#1577': '#1575#1604#1593#1585#1576#1610#1577),
    { sidDirSwitch }
    ('Right-to-left (BiDiMode)',
     #1605#1606' '#1575#1604#1610#1605#1610#1606' '#1573#1604#1609' '#1575#1604#1610#1587#1575#1585' (BiDiMode)'),
    { sidDirLtr }
    ('Direction: left-to-right (bdLeftToRight)',
     #1575#1604#1575#1578#1580#1575#1607': '#1605#1606' '#1575#1604#1610#1587#1575#1585' '#1573#1604#1609' '#1575#1604#1610#1605#1610#1606),
    { sidDirRtl }
    ('Direction: RIGHT-TO-LEFT (bdRightToLeft)',
     #1575#1604#1575#1578#1580#1575#1607': '#1605#1606' '#1575#1604#1610#1605#1610#1606' '#1573#1604#1609' '#1575#1604#1610#1587#1575#1585),
    { sidLegend }
    ('Mirroring is PARTIAL and that is the point. Each area below states what moves and what does not - anything unlabelled has not been built yet, it is not broken.',
     #1575#1604#1575#1606#1593#1603#1575#1587' '#1580#1586#1574#1610' '#1593#1606' '#1602#1589#1583'. '#1603#1604' '#1602#1587#1605' '#1610#1608#1590#1581' '#1605#1575' '#1610#1606#1593#1603#1587' '#1608#1605#1575' '#1604#1575' '#1610#1606#1593#1603#1587'.'),
    { sidTry }
    ('Try to break it: click the exact pixel a glyph was drawn on (check box, sort triangle, filter funnel, tree chevron, tab close x); drag the status bars bottom-LEFT corner; open a menu and then its submenu; drag a grid column edge; right-click this strip for a popup with a submenu.',
     #1575#1590#1594#1591' '#1593#1604#1609' '#1575#1604#1571#1610#1602#1608#1606#1575#1578' '#1575#1604#1589#1594#1610#1585#1577'. '#1575#1587#1581#1576' '#1586#1575#1608#1610#1577' '#1575#1604#1581#1580#1605'. '#1575#1601#1578#1581' '#1575#1604#1602#1608#1575#1574#1605' '#1575#1604#1601#1585#1593#1610#1577'.'),
    { sidTabForm }
    ('1  Form controls',
     '1  '#1571#1583#1608#1575#1578' '#1575#1604#1606#1605#1608#1584#1580),
    { sidTabData }
    ('2  Data views',
     '2  '#1593#1585#1590' '#1575#1604#1576#1610#1575#1606#1575#1578),
    { sidTabText }
    ('3  Text and chrome',
     '3  '#1575#1604#1606#1589' '#1608#1575#1604#1573#1591#1575#1585),
    { sidDivFormAll }
    ('ALL of these MIRROR - indicators, glyph slots, swatches, badges and captions change ends',
     #1603#1604' '#1607#1584#1607' '#1575#1604#1571#1583#1608#1575#1578' '#1578#1606#1593#1603#1587),
    { sidAlignLeft }
    ('TTyLabel Alignment=taLeftJustify -> right edge',
     'TTyLabel taLeftJustify'),
    { sidAlignRight }
    ('TTyLabel Alignment=taRightJustify -> left edge',
     'TTyLabel taRightJustify'),
    { sidAlignCenter }
    ('TTyLabel taCenter - stays put',
     'TTyLabel taCenter'),
    { sidChkPlain }
    ('TTyCheckBox - the indicator swaps sides',
     #1582#1575#1606#1577' '#1575#1604#1575#1582#1578#1610#1575#1585': '#1575#1604#1605#1572#1588#1585' '#1610#1578#1581#1585#1603),
    { sidChkFlipped }
    ('Alignment=taLeftJustify - explicitly set, still flips',
     'taLeftJustify - '#1610#1606#1593#1603#1587),
    { sidChkGrayed }
    ('Tri-state (cbGrayed)',
     #1579#1604#1575#1579' '#1581#1575#1604#1575#1578),
    { sidRadOne }
    ('TTyRadioButton - first',
     #1575#1604#1582#1610#1575#1585' '#1575#1604#1571#1608#1604),
    { sidRadTwo }
    ('TTyRadioButton - second',
     #1575#1604#1582#1610#1575#1585' '#1575#1604#1579#1575#1606#1610),
    { sidDivIndent }
    ('LeftIndent=40 counts from the other end',
     'LeftIndent=40'),
    { sidPanelCap }
    ('TTyPanel caption (taLeftJustify) - right-click me',
     'TTyPanel - '#1575#1590#1594#1591' '#1607#1606#1575),
    { sidContainerNote }
    ('DOES NOT MIRROR, on purpose: containers never mirror their childrens Align/Anchors layout, so these three columns keep their order. LCLs own align engine has no BiDi branch, and diverging from it would misplace every ported .lfm.',
     #1604#1575' '#1610#1606#1593#1603#1587': '#1578#1585#1578#1610#1576' '#1575#1604#1571#1593#1605#1583#1577' '#1575#1604#1579#1604#1575#1579#1577' '#1610#1576#1602#1609' '#1603#1605#1575' '#1607#1608'.'),
    { sidRadGrp }
    ('TTyRadioGroup (Columns=2) - columns fill from the right',
     'TTyRadioGroup (Columns=2)'),
    { sidChkGrp }
    ('TTyCheckGroup (Columns=2) - each box flips its own indicator',
     'TTyCheckGroup (Columns=2)'),
    { sidGrpBox }
    ('TTyGroupBox - the caption band changes ends',
     'TTyGroupBox - '#1575#1604#1593#1606#1608#1575#1606' '#1610#1578#1581#1585#1603),
    { sidGrpField }
    ('Field:',
     #1575#1604#1581#1602#1604':'),
    { sidGrpEdit }
    ('edit inside a group box',
     #1606#1589' '#1583#1575#1582#1604' '#1575#1604#1573#1591#1575#1585),
    { sidGrpNote }
    ('The band moves; the children inside do not.',
     #1575#1604#1593#1606#1608#1575#1606' '#1610#1578#1581#1585#1603'. '#1575#1604#1605#1581#1578#1608#1609' '#1604#1575' '#1610#1578#1581#1585#1603'.'),
    { sidGrpAfter }
    ('Arrow keys in the two groups follow the columns.',
     #1605#1601#1575#1578#1610#1581' '#1575#1604#1571#1587#1607#1605' '#1578#1578#1576#1593' '#1575#1604#1571#1593#1605#1583#1577'.'),
    { sidBtnPlain }
    ('TTyButton (taCenter)',
     'TTyButton (taCenter)'),
    { sidBtnCapLeft }
    ('taLeftJustify',
     'taLeftJustify'),
    { sidBtnGlyphL }
    ('Glyph glLeft',
     'glLeft'),
    { sidBtnGlyphR }
    ('Glyph glRight',
     'glRight'),
    { sidBtnBadge }
    ('Badge -> bottom-left',
     #1588#1575#1585#1577' '#1573#1580#1585#1575#1569),
    { sidColorDlg }
    ('Pick a colour',
     #1575#1582#1578#1585' '#1604#1608#1606#1575),
    { sidDivGlyphNote }
    ('What to press here',
     #1575#1590#1594#1591' '#1607#1606#1575),
    { sidFormNote }
    ('These controls answer clicks over their whole face, so paint and hit test cannot come apart - which is why they shipped first. The group boxes are the exception worth pressing: they hold real child check boxes and radio buttons, each flipping its own indicator, so click the exact pixel an indicator was drawn on after switching direction. The colour swatch and the badge corner are the other two small targets; a taCenter button caption is expected NOT to move. The glyph buttons take their star from the system symbol font, whose family name differs per platform - an empty slot is a missing font, not a mirroring fault, and the SLOT still changes sides.',
     #1603#1604' '#1607#1584#1607' '#1575#1604#1571#1583#1608#1575#1578' '#1578#1606#1593#1603#1587'. '#1575#1590#1594#1591' '#1593#1604#1609' '#1575#1604#1605#1572#1588#1585' '#1576#1593#1583' '#1578#1594#1610#1610#1585' '#1575#1604#1575#1578#1580#1575#1607'. '#1575#1604#1606#1580#1605#1577' '#1605#1606' '#1582#1591' '#1575#1604#1606#1592#1575#1605': '#1582#1575#1606#1577' '#1601#1575#1585#1594#1577' = '#1582#1591' '#1606#1575#1602#1589'.'),
    { sidDivGrid }
    ('TTyStringGrid - MIRRORS, and every hit test follows the paint',
     'TTyStringGrid - '#1610#1606#1593#1603#1587),
    { sidColName }
    ('Name',
     #1575#1604#1575#1587#1605),
    { sidColRegion }
    ('Region',
     #1575#1604#1576#1604#1583),
    { sidColQty }
    ('Qty',
     #1575#1604#1603#1605#1610#1577),
    { sidColSettled }
    ('Settled',
     #1578#1605),
    { sidColAction }
    ('Action',
     #1573#1580#1585#1575#1569),
    { sidCellOpen }
    ('Open',
     #1601#1578#1581),
    { sidGridNote }
    ('MIRRORS: column order, the row-number gutter, the two frozen columns, header captions, the sort triangle, the filter funnel, the tree chevron and its indent, the check-box cell and the button cell. DELIBERATELY DOES NOT: the vertical scroll bar stays on the right, and the filter drop-down does not mirror its own rows - both are pinned by tests, not accidents. Note a resize grip is a columns LEFT edge under RTL, and dragging it left widens the column.',
     #1610#1606#1593#1603#1587': '#1578#1585#1578#1610#1576' '#1575#1604#1571#1593#1605#1583#1577', '#1575#1604#1593#1606#1608#1575#1606', '#1575#1604#1571#1585#1602#1575#1605' '#1575#1604#1580#1575#1606#1576#1610#1577', '#1582#1575#1606#1577' '#1575#1604#1575#1582#1578#1610#1575#1585', '#1586#1585' '#1573#1580#1585#1575#1569'. '#1604#1575' '#1610#1606#1593#1603#1587': '#1588#1585#1610#1591' '#1575#1604#1578#1605#1585#1610#1585' '#1575#1604#1585#1571#1587#1610'. '#1575#1604#1571#1585#1602#1575#1605' '#1578#1576#1602#1609' '#1605#1606' '#1575#1604#1610#1587#1575#1585' '#1573#1604#1609' '#1575#1604#1610#1605#1610#1606'.'),
    { sidDivLv }
    ('TTyListView - DOES NOT MIRROR yet',
     'TTyListView - '#1604#1575' '#1610#1606#1593#1603#1587),
    { sidColSize }
    ('Size',
     #1575#1604#1581#1580#1605),
    { sidColKind }
    ('Kind',
     #1575#1604#1606#1608#1593),
    { sidDivTv }
    ('TTyTreeView - DOES NOT MIRROR yet',
     'TTyTreeView - '#1604#1575' '#1610#1606#1593#1603#1587),
    { sidColNode }
    ('Node',
     #1593#1602#1583#1577),
    { sidKindFolder }
    ('Folder',
     #1605#1580#1604#1583),
    { sidKindPlaylist }
    ('Playlist',
     #1602#1575#1574#1605#1577' '#1605#1608#1587#1610#1602#1610#1577),
    { sidKindWorkspace }
    ('Workspace',
     #1605#1587#1575#1581#1577' '#1593#1605#1604),
    { sidKindFile }
    ('File',
     #1605#1604#1601),
    { sidChildFmt }
    ('child %d',
     #1593#1606#1589#1585' %d'),
    { sidDataNote }
    ('Side by side on purpose - the contrast is the documentation. Flip the switch: the grid turns round whole, these two do not move at all. That is a stated gap. Their column model writes a per-column left field that nine separate expressions independently turn into a screen x, so mirroring the paint alone would leave every click behind.',
     #1575#1604#1580#1583#1608#1604' '#1610#1606#1593#1603#1587'. '#1575#1604#1602#1575#1574#1605#1577' '#1608#1575#1604#1588#1580#1585#1577' '#1604#1575' '#1578#1606#1593#1603#1587'. '#1607#1584#1575' '#1601#1585#1602' '#1605#1593#1585#1608#1601'.'),
    { sidDivText }
    ('Text - word order, shaping and the caret are bidirectional. The BLOCK does not mirror.',
     #1575#1604#1606#1589' '#1579#1606#1575#1574#1610' '#1575#1604#1575#1578#1580#1575#1607'. '#1575#1604#1603#1578#1604#1577' '#1604#1575' '#1578#1606#1593#1603#1587'.'),
    { sidLblArabic }
    ('Arabic',
     #1575#1604#1593#1585#1576#1610#1577),
    { sidLblHebrew }
    ('Hebrew',
     #1575#1604#1593#1576#1585#1610#1577),
    { sidLblMixed }
    ('Mixed',
     #1605#1582#1578#1604#1591),
    { sidLblChinese }
    ('Chinese',
     #1575#1604#1589#1610#1606#1610#1577),
    { sidDivChrome }
    ('What to press in this area',
     #1575#1590#1594#1591' '#1607#1606#1575),
    { sidTextNote }
    ('MIRRORS here: nothing in the four rows above. An edit and a memo keep their text block, margins and scroll bar on the left in either direction - only the reordering INSIDE a line is bidirectional, and that half is always on and needs no switch. What IS bidirectional: click a glyph and the caret lands on THAT glyph, including at the far side of an embedded run; Left/Right move one glyph the way the key points, crossing runs in screen order; Home/End stay logical, so on a right-to-left line Home puts the caret at the right of the ink. Drag across the Mixed memo line: a selection crossing a direction boundary paints one band PER RUN, so it can highlight glyphs the pointer never passed over - that is the range between the two endpoints, and it is what every other editor does. The Arabic rows are also the shaping test: the letters must JOIN into their contextual forms, not stand isolated. That was measured and pinned on Windows only; on GTK and Cocoa it is the platform text engines answer and this window is the only way to see it.',
     #1604#1575' '#1610#1606#1593#1603#1587': '#1575#1604#1581#1602#1608#1604' '#1575#1604#1571#1585#1576#1593#1577' '#1571#1593#1604#1575#1607'. '#1575#1604#1578#1585#1578#1610#1576' '#1583#1575#1582#1604' '#1575#1604#1587#1591#1585' '#1579#1606#1575#1574#1610' '#1575#1604#1575#1578#1580#1575#1607' '#1601#1602#1591'. '#1575#1604#1581#1585#1608#1601' '#1575#1604#1593#1585#1576#1610#1577' '#1610#1580#1576' '#1571#1606' '#1578#1578#1589#1604'.'),
    { sidDivScroll }
    ('TTyScrollBox - MIRRORS',
     'TTyScrollBox - '#1610#1606#1593#1603#1587),
    { sidSbChildFmt }
    ('Oversized child %d',
     #1593#1606#1589#1585' '#1603#1576#1610#1585' %d'),
    { sidScrollNote }
    ('The vertical bar docks LEFT and the viewport starts after it - the loudest signal a window gives that it reads right-to-left.',
     #1588#1585#1610#1591' '#1575#1604#1578#1605#1585#1610#1585' '#1610#1606#1578#1602#1604' '#1573#1604#1609' '#1575#1604#1610#1587#1575#1585'.'),
    { sidDivMini }
    ('TTyPageControl - MIRRORS',
     'TTyPageControl - '#1610#1606#1593#1603#1587),
    { sidMpOne }
    ('One',
     #1571#1608#1604),
    { sidMpTwo }
    ('Two',
     #1579#1575#1606#1610),
    { sidMpThree }
    ('Three',
     #1579#1575#1604#1579),
    { sidMpFour }
    ('Four',
     #1585#1575#1576#1593),
    { sidMpNoteOne }
    ('Tab 0 becomes the RIGHTMOST tab and the strip packs leftwards. The close x moves to each headers left edge.',
     #1575#1604#1578#1576#1608#1610#1576' '#1575#1604#1571#1608#1604' '#1610#1606#1578#1602#1604' '#1573#1604#1609' '#1575#1604#1610#1605#1610#1606'.'),
    { sidMpNoteTwo }
    ('The page BODY does not move, and a pages own children are not mirrored.',
     #1605#1581#1578#1608#1609' '#1575#1604#1589#1601#1581#1577' '#1604#1575' '#1610#1578#1581#1585#1603'.'),
    { sidMpNoteThree }
    ('Left/Right arrows follow the eye. Drag a header to reorder it and the drop slot must match what you see.',
     #1605#1601#1575#1578#1610#1581' '#1575#1604#1571#1587#1607#1605' '#1578#1578#1576#1593' '#1575#1604#1593#1610#1606'.'),
    { sidMpNoteFour }
    ('Narrow the window until the overflow arrows appear: they swap ends and turn round.',
     #1589#1594#1585' '#1575#1604#1606#1575#1601#1584#1577' '#1581#1578#1609' '#1578#1592#1607#1585' '#1571#1587#1607#1605' '#1575#1604#1578#1605#1585#1610#1585'.'),
    { sidMiniNote }
    ('The outer pager at the top of this window mirrors too - watch tab 1 jump to the right.',
     #1575#1604#1578#1576#1608#1610#1576' '#1575#1604#1582#1575#1585#1580#1610' '#1610#1606#1593#1603#1587' '#1571#1610#1590#1575'.'),
    { sidMnuFile }
    ('&File',
     #1605#1604#1601),
    { sidMnuNew }
    ('&New',
     #1580#1583#1610#1583),
    { sidMnuOpen }
    ('&Open',
     #1601#1578#1581),
    { sidMnuRecent }
    ('Recent files',
     #1605#1604#1601#1575#1578' '#1581#1583#1610#1579#1577),
    { sidMnuRecent1 }
    ('first.txt',
     'first.txt'),
    { sidMnuRecent2 }
    ('second.txt',
     'second.txt'),
    { sidMnuOlder }
    ('Older still',
     #1571#1602#1583#1605),
    { sidMnuOld1 }
    ('third.txt',
     'third.txt'),
    { sidMnuOld2 }
    ('fourth.txt',
     'fourth.txt'),
    { sidMnuExit }
    ('E&xit',
     #1582#1585#1608#1580),
    { sidMnuEdit }
    ('&Edit',
     #1578#1581#1585#1610#1585),
    { sidMnuCut }
    ('Cu&t',
     #1602#1589),
    { sidMnuCopy }
    ('&Copy',
     #1606#1587#1582),
    { sidMnuPaste }
    ('Paste (disabled)',
     #1604#1589#1602),
    { sidMnuDirection }
    ('&Direction',
     #1575#1604#1575#1578#1580#1575#1607),
    { sidMnuDirLtr }
    ('&Left to right',
     #1605#1606' '#1575#1604#1610#1587#1575#1585' '#1573#1604#1609' '#1575#1604#1610#1605#1610#1606),
    { sidMnuDirRtl }
    ('&Right to left',
     #1605#1606' '#1575#1604#1610#1605#1610#1606' '#1573#1604#1609' '#1575#1604#1610#1587#1575#1585),
    { sidMnuLanguage }
    ('&Language',
     #1575#1604#1604#1594#1577),
    { sidMnuLangEn }
    ('&English',
     #1575#1604#1573#1606#1580#1604#1610#1586#1610#1577),
    { sidMnuLangAr }
    ('&Arabic',
     #1575#1604#1593#1585#1576#1610#1577),
    { sidMnuHelp }
    ('&Help',
     #1605#1587#1575#1593#1583#1577),
    { sidMnuAbout }
    ('&About this example',
     #1581#1608#1604' TyControls 3.0'),
    { sidPopBanner }
    ('TyControls',
     'TyControls'),
    { sidPopHdr }
    ('-Popup',
     '-'#1575#1604#1602#1575#1574#1605#1577),
    { sidPopFirst }
    ('A popup takes its direction from its host',
     #1575#1604#1602#1575#1574#1605#1577' '#1578#1578#1576#1593' '#1575#1578#1580#1575#1607' '#1605#1590#1610#1601#1607#1575),
    { sidPopSub }
    ('Cascade a submenu',
     #1575#1604#1602#1575#1574#1605#1577' '#1575#1604#1601#1585#1593#1610#1577),
    { sidPopSub1 }
    ('Submenus hang the other way',
     #1575#1604#1602#1608#1575#1574#1605' '#1575#1604#1601#1585#1593#1610#1577' '#1578#1601#1578#1581' '#1605#1606' '#1575#1604#1580#1607#1577' '#1575#1604#1571#1582#1585#1609),
    { sidPopSub2 }
    ('and the arrow turns round',
     #1575#1604#1587#1607#1605' '#1610#1606#1593#1603#1587),
    { sidPopDeep }
    ('Deeper still',
     #1605#1587#1578#1608#1609' '#1579#1575#1604#1579),
    { sidPopDeep1 }
    ('third level',
     #1605#1587#1578#1608#1609' '#1579#1575#1604#1579),
    { sidPopShortcut }
    ('Shortcut moves to the left',
     #1575#1604#1575#1582#1578#1589#1575#1585' '#1610#1606#1578#1602#1604' '#1573#1604#1609' '#1575#1604#1610#1587#1575#1585),
    { sidReady }
    ('Ready - flip "Right-to-left" and start clicking.',
     #1580#1575#1607#1586'. '#1594#1610#1585' '#1575#1604#1575#1578#1580#1575#1607' '#1608#1575#1576#1583#1571' '#1575#1604#1590#1594#1591'.'),
    { sidStatusLtr }
    ('left-to-right',
     #1605#1606' '#1575#1604#1610#1587#1575#1585' '#1573#1604#1609' '#1575#1604#1610#1605#1610#1606),
    { sidStatusRtl }
    ('right-to-left',
     #1605#1606' '#1575#1604#1610#1605#1610#1606' '#1573#1604#1609' '#1575#1604#1610#1587#1575#1585),
    { sidGripLtr }
    ('drag the grip ->',
     #1575#1587#1581#1576' '#1586#1575#1608#1610#1577' '#1575#1604#1581#1580#1605' ->'),
    { sidGripRtl }
    ('<- drag the grip',
     '<- '#1575#1587#1581#1576' '#1586#1575#1608#1610#1577' '#1575#1604#1581#1580#1605),
    { sidSayDirLtr }
    ('Left-to-right.',
     #1575#1604#1575#1578#1580#1575#1607' '#1605#1606' '#1575#1604#1610#1587#1575#1585' '#1573#1604#1609' '#1575#1604#1610#1605#1610#1606'.'),
    { sidSayDirRtl }
    ('Right-to-left. The grip is now at the BOTTOM-LEFT corner - drag it.',
     #1575#1604#1575#1578#1580#1575#1607' '#1605#1606' '#1575#1604#1610#1605#1610#1606' '#1573#1604#1609' '#1575#1604#1610#1587#1575#1585'. '#1586#1575#1608#1610#1577' '#1575#1604#1581#1580#1605' '#1575#1604#1570#1606' '#1593#1604#1609' '#1575#1604#1610#1587#1575#1585'.'),
    { sidSayLangEn }
    ('Language: English.',
     'Language: English.'),
    { sidSayLangAr }
    ('Language: Arabic.',
     #1575#1604#1604#1594#1577': '#1575#1604#1593#1585#1576#1610#1577'.'),
    { sidSayMenuFmt }
    ('Menu: %s',
     #1575#1604#1602#1575#1574#1605#1577': %s'),
    { sidSayCellFmt }
    ('Grid button cell: column %d, row %d',
     #1586#1585' '#1575#1604#1580#1583#1608#1604': '#1593#1605#1608#1583' %d, '#1587#1591#1585' %d'),
    { sidTabFenced }
    ('4  Fenced',
     '4  '#1604#1575' '#1578#1606#1593#1603#1587),
    { sidDivFenced }
    ('These three deliberately DO NOT mirror - press them and satisfy yourself',
     #1607#1584#1607' '#1575#1604#1571#1583#1608#1575#1578' '#1604#1575' '#1578#1606#1593#1603#1587' '#1593#1606' '#1602#1589#1583),
    { sidFencedIntro }
    ('All three share ONE reason: the click position is computed a SECOND time, separately from the paint. Mirroring the paint alone would draw the target in one place and answer clicks in another, which this library has already shipped three times. So each stays put until its two computations become one. Press them after flipping direction: what you hit must be what you see.',
     #1575#1604#1587#1576#1576' '#1608#1575#1581#1583' '#1601#1610' '#1575#1604#1579#1604#1575#1579#1577': '#1605#1608#1590#1593' '#1575#1604#1606#1602#1585' '#1610#1581#1587#1576' '#1605#1585#1577' '#1579#1575#1606#1610#1577', '#1605#1606#1601#1589#1604#1575' '#1593#1606' '#1575#1604#1585#1587#1605'. '#1604#1584#1604#1603' '#1578#1576#1602#1609' '#1603#1605#1575' '#1607#1610' '#1581#1578#1609' '#1610#1589#1610#1585' '#1575#1604#1581#1587#1575#1576#1575#1606' '#1608#1575#1581#1583#1575'.'),
    { sidDivDrop }
    ('TTyDropDownButton - a split face',
     'TTyDropDownButton'),
    { sidDropBtn }
    ('Save',
     #1581#1601#1592),
    { sidDropNote }
    ('The arrow zone stays on the RIGHT. TyDropArrowHit reads the click back off the same x axis, so an arrow drawn on the left would still open the menu from the other half.',
     #1575#1604#1587#1607#1605' '#1610#1576#1602#1609' '#1593#1604#1609' '#1575#1604#1610#1605#1610#1606' '#1593#1606' '#1602#1589#1583'. '#1605#1606#1591#1602#1577' '#1575#1604#1587#1607#1605' '#1578#1581#1587#1576' '#1605#1606' '#1605#1608#1590#1593' '#1575#1604#1606#1602#1585'.'),
    { sidDivGroup }
    ('TTyButtonGroup - segments',
     'TTyButtonGroup'),
    { sidGroupNote }
    ('The segments keep their order. TySegmentAt maps a raw x straight onto an index, so reversing the paint would select the mirror-image segment - silently, on a control whose entire job is choosing.',
     #1575#1604#1605#1602#1575#1591#1593' '#1578#1576#1602#1609' '#1576#1578#1585#1578#1610#1576#1607#1575'. '#1575#1604#1575#1582#1578#1610#1575#1585' '#1610#1581#1587#1576' '#1605#1606' '#1605#1608#1590#1593' '#1575#1604#1606#1602#1585' '#1605#1576#1575#1588#1585#1577'. '#1601#1593#1603#1587' '#1575#1604#1585#1587#1605' '#1608#1581#1583#1607' '#1610#1582#1578#1575#1585' '#1575#1604#1605#1602#1575#1576#1604'.'),
    { sidDivVList }
    ('TTyValueListEditor - two columns',
     'TTyValueListEditor'),
    { sidVListNote }
    ('The key and value columns keep their sides. The splitter is grabbed through SplitXDp, a SECOND computation of the geometry the row paints from - mirror one and the divider sits a scroll bar away from where you drag it.',
     #1575#1604#1593#1605#1608#1583#1575#1606' '#1610#1576#1602#1610#1575#1606' '#1601#1610' '#1605#1603#1575#1606#1607#1605#1575'. '#1575#1604#1601#1575#1589#1604' '#1610#1587#1581#1576' '#1605#1606' '#1581#1587#1575#1576' '#1579#1575#1606' '#1594#1610#1585' '#1575#1604#1584#1610' '#1610#1585#1587#1605' '#1605#1606#1607' '#1575#1604#1589#1601'.'),
    { sidVlKey1 }
    ('Direction',
     #1575#1604#1575#1578#1580#1575#1607),
    { sidVlVal1 }
    ('right-to-left',
     #1605#1606' '#1575#1604#1610#1605#1610#1606' '#1573#1604#1609' '#1575#1604#1610#1587#1575#1585),
    { sidVlKey2 }
    ('Language',
     #1575#1604#1604#1594#1577),
    { sidVlVal2 }
    ('Arabic',
     #1575#1604#1593#1585#1576#1610#1577),
    { sidVlKey3 }
    ('Mirrors',
     #1610#1606#1593#1603#1587),
    { sidVlVal3 }
    ('no',
     #1604#1575),
    { sidDivHow }
    ('How you switch a real application over',
     #1603#1610#1601' '#1578#1601#1593#1604' '#1607#1584#1575' '#1601#1610' '#1578#1591#1576#1610#1602#1603),
    { sidHow1 }
    ('1. BiDiMode is NOT published - the Object Inspector will not offer it, because most of the library ignores it. Set it from code:',
     '1. BiDiMode '#1594#1610#1585' '#1605#1606#1588#1608#1585#1577'. '#1575#1590#1576#1591#1607#1575' '#1605#1606' '#1575#1604#1603#1608#1583':'),
    { sidHow1Code }
    ('Form.BiDiMode := bdRightToLeft;',
     'Form.BiDiMode := bdRightToLeft;'),
    { sidHow2 }
    ('2. Children inherit it through ParentBiDiMode. Walking the tree (as SetBiDiDeep does in umain.pas) also reaches any control that turned that flag off.',
     '2. '#1610#1606#1578#1602#1604' '#1573#1604#1609' '#1575#1604#1571#1576#1606#1575#1569' '#1593#1576#1585' ParentBiDiMode.'),
    { sidHow3 }
    ('3. A horizontal TTyScrollBar does NOT read BiDiMode. It is opt-in, so a bar can never mirror before the content it scrolls. Its host turns it on:',
     '3. '#1588#1585#1610#1591' '#1575#1604#1578#1605#1585#1610#1585' '#1575#1604#1571#1601#1602#1610' '#1604#1575' '#1610#1602#1585#1571' BiDiMode. '#1575#1604#1605#1590#1610#1601' '#1610#1588#1594#1604#1607' '#1576#1606#1601#1587#1607':'),
    { sidHow3Code }
    ('ScrollBar.MirrorHorizontal := True;',
     'ScrollBar.MirrorHorizontal := True;'),
    { sidHow4 }
    ('4. TTyStringGrid already does that for its own bar, so a host embedding a grid does not have to.',
     '4. '#1575#1604#1580#1583#1608#1604' '#1610#1601#1593#1604' '#1584#1604#1603' '#1604#1588#1585#1610#1591#1607' '#1576#1606#1601#1587#1607'.'),
    { sidHow5 }
    ('5. Arabic literals in PASCAL need {$codepage UTF8} at the top of the unit, or every letter silently becomes a question mark. The same #NNNN escapes in a .lfm do not - that file goes through the LFM parser instead. See the top of umain.pas.',
     '5. '#1575#1604#1581#1585#1608#1601' '#1575#1604#1593#1585#1576#1610#1577' '#1601#1610' '#1576#1575#1587#1603#1575#1604' '#1578#1581#1578#1575#1580' {$codepage UTF8}.'));

{ ---------------------------------------------------------------- grid data --

  A flat row list with an explicit level column. The grid does NOT own a tree: it asks the
  host for each row's level and whether it has children, and owns only the collapsed set --
  which is why a million-row tree costs nothing to show. Levels here are hand-written so the
  chevron has something to draw and something to indent.

  The Arabic rows carry Latin airport codes ON PURPOSE. "<arabic city> RUH" is an Arabic
  paragraph with a Latin tail, which is the case that exercises paragraph DIRECTION rather
  than merely the script -- and it is exactly the case the grid used to get backwards. The
  Europe row goes further and carries a product name and version number for the same reason.
  The Qty column stays ASCII digits in both languages: digits read left-to-right even inside
  a right-to-left row, and seeing that hold is the whole point of having a numeric column. }

type
  TDemoRow = record
    Level:  Integer;
    Name:   string;
    Region: string;
    Qty:    string;
    Done:   Boolean;
  end;

const
  GridData: array[TUiLang] of array[0..10] of TDemoRow = (
    (
      (Level: 0; Name: 'Middle East';
       Region: 'MEA'; Qty: '640'; Done: True),
      (Level: 1; Name: 'Riyadh RUH';
       Region: 'SA'; Qty: '270'; Done: True),
      (Level: 1; Name: 'Cairo CAI';
       Region: 'EG'; Qty: '215'; Done: False),
      (Level: 1; Name: 'Dubai DXB';
       Region: 'AE'; Qty: '155'; Done: True),
      (Level: 0; Name: 'Europe';
       Region: 'EU'; Qty: '430'; Done: False),
      (Level: 1; Name: 'Madrid MAD';
       Region: 'ES'; Qty: '245'; Done: True),
      (Level: 1; Name: 'Lisbon LIS';
       Region: 'PT'; Qty: '185'; Done: False),
      (Level: 0; Name: 'Asia';
       Region: 'APAC'; Qty: '905'; Done: True),
      (Level: 1; Name: 'Tokyo NRT';
       Region: 'JP'; Qty: '480'; Done: True),
      (Level: 1; Name: 'Seoul ICN';
       Region: 'KR'; Qty: '300'; Done: False),
      (Level: 1; Name: 'Taipei TPE';
       Region: 'TW'; Qty: '125'; Done: False)
    ),
    (
      (Level: 0; Name: #1575#1604#1588#1585#1602' '#1575#1604#1571#1608#1587#1591;
       Region: 'MEA'; Qty: '640'; Done: True),
      (Level: 1; Name: #1575#1604#1585#1610#1575#1590' RUH';
       Region: #1575#1604#1587#1593#1608#1583#1610#1577; Qty: '270'; Done: True),
      (Level: 1; Name: #1575#1604#1602#1575#1607#1585#1577' CAI';
       Region: #1605#1589#1585; Qty: '215'; Done: False),
      (Level: 1; Name: #1583#1576#1610' DXB';
       Region: #1575#1604#1573#1605#1575#1585#1575#1578; Qty: '155'; Done: True),
      (Level: 0; Name: #1571#1608#1585#1608#1576#1575' - '#1578#1602#1585#1610#1585' Acme 3.0';
       Region: 'EU'; Qty: '430'; Done: False),
      (Level: 1; Name: #1605#1583#1585#1610#1583' MAD';
       Region: #1573#1587#1576#1575#1606#1610#1575; Qty: '245'; Done: True),
      (Level: 1; Name: #1604#1588#1576#1608#1606#1577' LIS';
       Region: #1575#1604#1576#1585#1578#1594#1575#1604; Qty: '185'; Done: False),
      (Level: 0; Name: #1570#1587#1610#1575;
       Region: 'APAC'; Qty: '905'; Done: True),
      (Level: 1; Name: #1591#1608#1603#1610#1608' NRT';
       Region: #1575#1604#1610#1575#1576#1575#1606; Qty: '480'; Done: True),
      (Level: 1; Name: #1587#1610#1608#1604' ICN';
       Region: #1603#1608#1585#1610#1575; Qty: '300'; Done: False),
      (Level: 1; Name: #1578#1575#1610#1576#1610#1607' TPE ('#1571#1585#1602#1575#1605' '#1588#1585#1602#1610#1577' '#1633#1634#1637')';
       Region: #1578#1575#1610#1608#1575#1606; Qty: '125'; Done: False)
    ));

  TreeRoots: array[TUiLang] of array[0..4] of string = (
    ('Documents', 'Pictures', 'Music', 'Downloads', 'Projects'),
    (#1605#1587#1578#1606#1583#1575#1578, #1589#1608#1585, #1605#1608#1587#1610#1602#1609, #1578#1606#1586#1610#1604#1575#1578, #1605#1588#1575#1585#1610#1593));

  TreeKinds: array[TUiLang] of array[0..4] of string = (
    ('Folder', 'Folder', 'Playlist', 'Folder', 'Workspace'),
    (#1605#1580#1604#1583, #1605#1580#1604#1583, #1602#1575#1574#1605#1577' '#1605#1608#1587#1610#1602#1610#1577, #1605#1580#1604#1583, #1605#1587#1575#1581#1577' '#1593#1605#1604));

  RadGrpItems: array[TUiLang] of array[0..3] of string = (
    ('Riyadh', 'Cairo', 'Tel Aviv', 'Dubai'),
    (#1575#1604#1585#1610#1575#1590, #1575#1604#1602#1575#1607#1585#1577, #1578#1604' '#1571#1576#1610#1576, #1583#1576#1610));

  ChkGrpItems: array[TUiLang] of array[0..5] of string = (
    ('Shaping', 'Word order', 'Caret', 'Selection', 'Mirroring', 'Hit test'),
    (#1578#1589#1604, #1575#1604#1578#1585#1578#1610#1576, #1605#1572#1588#1585, #1578#1581#1583#1610#1583, #1575#1604#1575#1606#1593#1603#1575#1587, #1603#1588#1601' '#1575#1604#1606#1602#1585));

  LvRows: array[TUiLang] of array[0..4] of array[0..2] of string = (
    (
      ('readme.txt', '2 KB', 'Text document'),
      ('report.pdf', '184 KB', 'PDF document'),
      ('archive.zip', '9 MB', 'Compressed folder'),
      ('notes.md', '7 KB', 'Markdown'),
      ('photo.png', '1 MB', 'Image')
    ),
    (
      ('readme.txt', '2 KB', #1605#1604#1601' '#1606#1589#1610),
      ('report.pdf', '184 KB', #1605#1587#1578#1606#1583' PDF'),
      ('archive.zip', '9 MB', #1605#1580#1604#1583' '#1605#1590#1594#1608#1591),
      ('notes.md', '7 KB', #1605#1604#1575#1581#1592#1575#1578),
      ('photo.png', '1 MB', #1589#1608#1585#1577)
    ));

function TMainForm.S(AId: TStrId): string;
begin
  Result := UiText[AId, FLang];
end;

{ Read the bytes back and say what they are.

  The table is written as #NNNN escapes precisely because this toolchain has mangled non-ASCII
  literals before, and the failure mode is quiet: the build succeeds and the window shows
  mojibake, which a reader who cannot read Arabic will not recognise as damage. So one string
  with a known answer is decoded at run time and reported. The first Arabic letter of "Name"
  (alef, U+0627) must arrive as the two bytes D8 A7; anything else means the escapes did not
  survive, and the status bar says so instead of pretending. }
function TMainForm.CheckStringTableEncoding: string;
var
  ar: string;
begin
  ar := UiText[sidColName, ulArabic];      { the Arabic for "Name", which starts with alef }
  if (Length(ar) >= 2) and (Ord(ar[1]) = $D8) and (Ord(ar[2]) = $A7) then
    Result := Format('string table UTF-8 OK (%d bytes)', [Length(ar)])
  else
    Result := 'STRING TABLE IS MANGLED - is {$codepage UTF8} still at the top of this unit?';
end;

procedure TMainForm.FillGrid;
var
  r: Integer;
begin
  Grid.BeginUpdate;
  try
    Grid.RowCount := Length(GridData[FLang]);
    for r := 0 to High(GridData[FLang]) do
    begin
      Grid.Cells[0, r] := GridData[FLang][r].Name;
      Grid.Cells[1, r] := GridData[FLang][r].Region;
      Grid.Cells[2, r] := GridData[FLang][r].Qty;
      { A gekCheckBox column stores its state as the column's ValueChecked /
        ValueUnchecked words -- '1' and '' by default. }
      if GridData[FLang][r].Done then Grid.Cells[3, r] := '1' else Grid.Cells[3, r] := '';
      Grid.Cells[4, r] := S(sidCellOpen);
    end;
  finally
    Grid.EndUpdate;
  end;
end;

procedure TMainForm.FillListView;
var
  i: Integer;
begin
  LV.Items.BeginUpdate;
  try
    for i := 0 to LV.Items.Count - 1 do
      if i <= High(LvRows[FLang]) then
      begin
        LV.Items[i].Caption := LvRows[FLang][i][0];
        if LV.Items[i].SubItems.Count > 0 then
          LV.Items[i].SubItems[0] := LvRows[FLang][i][1];
        if LV.Items[i].SubItems.Count > 1 then
          LV.Items[i].SubItems[1] := LvRows[FLang][i][2];
      end;
  finally
    LV.Items.EndUpdate;
  end;
end;

{ TTyValueListEditor holds key/value ROWS rather than captions, so it cannot be filled from
  the .lfm the way the list view is -- InsertRow is how you actually put content in one, and
  showing that is half the reason this control is on the page. Clear() first, because
  switching language refills rather than appends. }
procedure TMainForm.FillValueList;
begin
  VList.Clear;
  VList.InsertRow(S(sidVlKey1), S(sidVlVal1));
  VList.InsertRow(S(sidVlKey2), S(sidVlVal2));
  VList.InsertRow(S(sidVlKey3), S(sidVlVal3));
end;

procedure TMainForm.GridGetNodeLevel(Sender: TObject; ARow: Integer; var ALevel: Integer);
begin
  if (ARow >= 0) and (ARow <= High(GridData[FLang])) then
    ALevel := GridData[FLang][ARow].Level;
end;

procedure TMainForm.GridGetHasChildren(Sender: TObject; ARow: Integer; var AHas: Boolean);
begin
  AHas := (ARow >= 0) and (ARow <= High(GridData[FLang])) and
          (GridData[FLang][ARow].Level = 0);
end;

procedure TMainForm.GridCellButtonClick(Sender: TObject; ACol, ARow: Integer);
begin
  { A button CELL. Under RTL it is drawn at the other end of the row -- this handler firing
    for the row you actually pressed is the half a headless test cannot ask about. }
  Say(Format(S(sidSayCellFmt), [ACol, ARow]));
end;

{ ------------------------------------------------------------ tree view data --

  A virtual tree: nodes are never in the .lfm. Two roots' worth of children are synthesised
  on demand. This control does NOT mirror -- its expander stays on the left and its indent
  still grows rightwards -- and that is the point of putting it beside the grid. }

procedure TMainForm.TreeInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
  var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) = 0 then
    Include(InitStates, ivsHasChildren);
end;

procedure TMainForm.TreeInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
  var ChildCount: Cardinal);
begin
  if Sender.GetNodeLevel(Node) = 0 then ChildCount := 3 else ChildCount := 0;
end;

procedure TMainForm.TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; Column: Integer;
  TextType: TTyVSTTextType; var CellText: string);
var
  lvl, idx: Integer;
begin
  if TextType <> ttNormal then begin CellText := ''; Exit; end;
  lvl := Sender.GetNodeLevel(Node);
  idx := Integer(Node^.Index);
  if lvl = 0 then
  begin
    if (idx >= 0) and (idx <= High(TreeRoots[FLang])) then
      case Column of
        0: CellText := TreeRoots[FLang][idx];
        1: CellText := TreeKinds[FLang][idx];
      end;
  end
  else
    case Column of
      0: CellText := Format(S(sidChildFmt), [idx + 1]);
      1: CellText := S(sidKindFile);
    end;
end;

{ ------------------------------------------------------------------ chrome ---- }

procedure TMainForm.Say(const AText: string);
begin
  if StatusBar1.Panels.Count > 0 then
    TTyStatusPanel(StatusBar1.Panels.Items[0]).Text := AText;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  { Built-in themes are compiled in, so the switcher works without locating a themes/ folder. }
  TyRegisterBuiltinThemes;
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);      { title bar + window rounded corners/shadow }
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');

  FRtl  := False;
  FLang := ulEnglish;

  { The string table is deliberately NOT applied here.

    umain.lfm's captions are the English ones and languages/rtl_example.zh_CN.po translates
    them at startup, so a Chinese user still gets a Chinese window on the first frame.
    Applying the table now would overwrite every one of those with English and quietly retire
    a translation that already exists. The switch takes over from the first time it is used --
    and yes, that means a Chinese user who visits Arabic and comes back lands in English,
    which is the honest cost of having a two-column table rather than a third .po. }
  FillGrid;
  FillValueList;      { rows, not captions -- a .lfm cannot carry them (see FillValueList) }

  { Read the bytes back rather than trusting the escapes. Appended to whatever the panel
    already says, so the translated 'Ready' survives. (Say guards the panel count itself, but
    its ARGUMENT is evaluated first, so the read needs its own guard.) }
  if StatusBar1.Panels.Count > 0 then
    Say(TTyStatusPanel(StatusBar1.Panels.Items[0]).Text +
        '  [' + CheckStringTableEncoding + ']');
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);      { re-theme the shell on every skin change }
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

{ ---------------------------------------------------------------- language ---- }

{ Replace EVERY visible string in the window.

  One click has to reach every text-drawing path at once, because that is the only way to find
  out which of them is wrong: cell text and the row-number gutter and the footer go through
  TTyCustomGrid.DrawCellText, menu rows through the menu's own renderer, status panels through
  the bar's, tab captions through the pager's, tree nodes through the tree's, and every label,
  button and check box through TTyPainter.DrawText. They do NOT share code, so a translation
  that stopped at the text tab would prove nothing about the other five. }
procedure TMainForm.ApplyLanguage(ALang: TUiLang);
var
  i: Integer;
begin
  if FApplying then Exit;
  FApplying := True;
  try
    FLang := ALang;

    { --- window chrome --- }
    Caption            := S(sidFormCaption);
    TitleBar1.Caption  := S(sidTitleBar);
    DarkSwitch.Caption := S(sidDark);

    { --- head panel --- }
    DirSwitch.Caption    := S(sidDirSwitch);
    LangSwitch.Caption   := S(sidLangSwitch);
    LblLangState.Caption := S(sidLangState);
    LblLegend.Caption    := S(sidLegend);
    LblTry.Caption       := S(sidTry);

    { --- tabs --- }
    PgForm.Caption   := S(sidTabForm);
    PgData.Caption   := S(sidTabData);
    PgText.Caption   := S(sidTabText);
    PgFenced.Caption := S(sidTabFenced);

    { --- page 1: form controls --- }
    DivFormAll.Caption       := S(sidDivFormAll);
    LblAlignLeft.Caption     := S(sidAlignLeft);
    LblAlignRight.Caption    := S(sidAlignRight);
    LblAlignCenter.Caption   := S(sidAlignCenter);
    ChkPlain.Caption         := S(sidChkPlain);
    ChkFlipped.Caption       := S(sidChkFlipped);
    ChkGrayed.Caption        := S(sidChkGrayed);
    RadOne.Caption           := S(sidRadOne);
    RadTwo.Caption           := S(sidRadTwo);
    DivIndent.Caption        := S(sidDivIndent);
    PanelCap.Caption         := S(sidPanelCap);
    LblContainerNote.Caption := S(sidContainerNote);
    RadGrp.Caption           := S(sidRadGrp);
    ChkGrp.Caption           := S(sidChkGrp);
    GrpBox.Caption           := S(sidGrpBox);
    LblGrpField.Caption      := S(sidGrpField);
    EdGrp.Text               := S(sidGrpEdit);
    LblGrpNote.Caption       := S(sidGrpNote);
    LblGrpAfter.Caption      := S(sidGrpAfter);
    BtnPlain.Caption         := S(sidBtnPlain);
    BtnCapLeft.Caption       := S(sidBtnCapLeft);
    BtnGlyphLeft.Caption     := S(sidBtnGlyphL);
    BtnGlyphRight.Caption    := S(sidBtnGlyphR);
    BtnBadge.Caption         := S(sidBtnBadge);
    BtnColor.DialogCaption   := S(sidColorDlg);
    DivGlyphNote.Caption     := S(sidDivGlyphNote);
    LblFormNote.Caption      := S(sidFormNote);

    { The two group boxes own their item strings, so they are rebuilt rather than poked. }
    RadGrp.Items.BeginUpdate;
    try
      RadGrp.Items.Clear;
      for i := 0 to High(RadGrpItems[FLang]) do RadGrp.Items.Add(RadGrpItems[FLang][i]);
    finally
      RadGrp.Items.EndUpdate;
    end;
    RadGrp.ItemIndex := 0;
    ChkGrp.Items.BeginUpdate;
    try
      ChkGrp.Items.Clear;
      for i := 0 to High(ChkGrpItems[FLang]) do ChkGrp.Items.Add(ChkGrpItems[FLang][i]);
    finally
      ChkGrp.Items.EndUpdate;
    end;

    { --- page 2: data views. Header captions and cell data are separate paths. --- }
    DivGrid.Caption := S(sidDivGrid);
    if Grid.Header.Columns.Count >= 5 then
    begin
      Grid.Header.Columns[0].Text := S(sidColName);
      Grid.Header.Columns[1].Text := S(sidColRegion);
      Grid.Header.Columns[2].Text := S(sidColQty);
      Grid.Header.Columns[3].Text := S(sidColSettled);
      Grid.Header.Columns[4].Text := S(sidColAction);
    end;
    FillGrid;
    LblGridNote.Caption := S(sidGridNote);

    DivLv.Caption := S(sidDivLv);
    if LV.Header.Columns.Count >= 3 then
    begin
      LV.Header.Columns[0].Text := S(sidColName);
      LV.Header.Columns[1].Text := S(sidColSize);
      LV.Header.Columns[2].Text := S(sidColKind);
    end;
    FillListView;

    DivTv.Caption := S(sidDivTv);
    if Tree.Header.Columns.Count >= 2 then
    begin
      Tree.Header.Columns[0].Text := S(sidColNode);
      Tree.Header.Columns[1].Text := S(sidColKind);
    end;
    Tree.Invalidate;                { node text is answered by TreeGetText, per paint }
    LblDataNote.Caption := S(sidDataNote);

    { --- page 3: text and chrome ---
      The four sample edits and memos are NOT translated: they are fixed script specimens
      (Arabic, Hebrew, mixed, Chinese) and the whole point of that area is that they stay put
      while everything around them changes. Their row LABELS do change. }
    DivText.Caption       := S(sidDivText);
    LblArabic.Caption     := S(sidLblArabic);
    LblHebrew.Caption     := S(sidLblHebrew);
    LblMixed.Caption      := S(sidLblMixed);
    LblChinese.Caption    := S(sidLblChinese);
    DivChrome.Caption     := S(sidDivChrome);
    LblTextNote.Caption   := S(sidTextNote);
    DivScroll.Caption     := S(sidDivScroll);
    SbBtn1.Caption        := Format(S(sidSbChildFmt), [1]);
    SbBtn2.Caption        := Format(S(sidSbChildFmt), [2]);
    SbBtn3.Caption        := Format(S(sidSbChildFmt), [3]);
    SbBtn4.Caption        := Format(S(sidSbChildFmt), [4]);
    SbBtn5.Caption        := Format(S(sidSbChildFmt), [5]);
    SbBtn6.Caption        := Format(S(sidSbChildFmt), [6]);
    LblScrollNote.Caption := S(sidScrollNote);
    DivMini.Caption       := S(sidDivMini);
    MpOne.Caption         := S(sidMpOne);
    MpTwo.Caption         := S(sidMpTwo);
    MpThree.Caption       := S(sidMpThree);
    MpFour.Caption        := S(sidMpFour);
    LblMpOne.Caption      := S(sidMpNoteOne);
    LblMpTwo.Caption      := S(sidMpNoteTwo);
    LblMpThree.Caption    := S(sidMpNoteThree);
    LblMpFour.Caption     := S(sidMpNoteFour);
    LblMiniNote.Caption   := S(sidMiniNote);

    { --- page 4: the fenced non-mirrors, and the how-to ---
      These three are here so the exclusions can be SEEN to be decisions. Each keeps its
      geometry under either direction because its hit test is a second, independent
      computation of x from its paint; mirroring the paint alone is the "drawn right, answers
      wrong" defect this library has shipped three times. Flip direction and press them: the
      arrow zone, the segment you chose and the splitter must all still be where you aimed. }
    DivFenced.Caption      := S(sidDivFenced);
    LblFencedIntro.Caption := S(sidFencedIntro);
    DivDrop.Caption        := S(sidDivDrop);
    DropBtn.Caption        := S(sidDropBtn);
    LblDropNote.Caption    := S(sidDropNote);
    DivGroup.Caption       := S(sidDivGroup);
    LblGroupNote.Caption   := S(sidGroupNote);
    DivVList.Caption       := S(sidDivVList);
    LblVListNote.Caption   := S(sidVListNote);
    BtnGroup.Items.BeginUpdate;
    try
      BtnGroup.Items.Clear;
      BtnGroup.Items.Add(S(sidMpOne));
      BtnGroup.Items.Add(S(sidMpTwo));
      BtnGroup.Items.Add(S(sidMpThree));
    finally
      BtnGroup.Items.EndUpdate;
    end;
    BtnGroup.ItemIndex := 0;
    FillValueList;

    DivHow.Caption   := S(sidDivHow);
    LblHow1.Caption  := S(sidHow1);
    EdHow1.Text      := S(sidHow1Code);
    LblHow2.Caption  := S(sidHow2);
    LblHow3.Caption  := S(sidHow3);
    EdHow3.Text      := S(sidHow3Code);
    LblHow4.Caption  := S(sidHow4);
    LblHow5.Caption  := S(sidHow5);

    { --- menus: their own renderer again, and the one place a mnemonic '&' lives ---
      The Arabic captions carry NO '&'. A Latin access key under an Arabic label is not what
      an Arabic application does, and inventing one would be a worse lie than not having it. }
    MnuFile.Caption         := S(sidMnuFile);
    MnuFileNew.Caption      := S(sidMnuNew);
    MnuFileOpen.Caption     := S(sidMnuOpen);
    MnuFileRecent.Caption   := S(sidMnuRecent);
    MnuRecent1.Caption      := S(sidMnuRecent1);
    MnuRecent2.Caption      := S(sidMnuRecent2);
    MnuRecentMore.Caption   := S(sidMnuOlder);
    MnuRecentOld1.Caption   := S(sidMnuOld1);
    MnuRecentOld2.Caption   := S(sidMnuOld2);
    MnuFileExit.Caption     := S(sidMnuExit);
    MnuEdit.Caption         := S(sidMnuEdit);
    MnuEditCut.Caption      := S(sidMnuCut);
    MnuEditCopy.Caption     := S(sidMnuCopy);
    MnuEditDisabled.Caption := S(sidMnuPaste);
    MnuDirection.Caption    := S(sidMnuDirection);
    MnuDirLtr.Caption       := S(sidMnuDirLtr);
    MnuDirRtl.Caption       := S(sidMnuDirRtl);
    MnuLanguage.Caption     := S(sidMnuLanguage);
    MnuLangEn.Caption       := S(sidMnuLangEn);
    MnuLangAr.Caption       := S(sidMnuLangAr);
    MnuHelpRight.Caption    := S(sidMnuHelp);
    MnuHelpAbout.Caption    := S(sidMnuAbout);

    Popup1.BannerCaption := S(sidPopBanner);
    PopHdr.Caption       := S(sidPopHdr);
    PopFirst.Caption     := S(sidPopFirst);
    PopSub.Caption       := S(sidPopSub);
    PopSub1.Caption      := S(sidPopSub1);
    PopSub2.Caption      := S(sidPopSub2);
    PopSubDeep.Caption   := S(sidPopDeep);
    PopSubDeep1.Caption  := S(sidPopDeep1);
    PopShortcut.Caption  := S(sidPopShortcut);

    { Keep the two ways of asking for the same thing in step. }
    LangSwitch.Checked := ALang = ulArabic;
    MnuLangEn.Checked  := ALang = ulEnglish;
    MnuLangAr.Checked  := ALang = ulArabic;

    { The direction-dependent strings have to be re-stated in the new language. }
    RefreshDirectionText;

    MenuBar1.Invalidate;
    Invalidate;
  finally
    FApplying := False;
  end;
end;

procedure TMainForm.LangSwitchChange(Sender: TObject);
begin
  if LangSwitch.Checked then ApplyLanguage(ulArabic) else ApplyLanguage(ulEnglish);
  if FLang = ulArabic then Say(S(sidSayLangAr)) else Say(S(sidSayLangEn));
end;

procedure TMainForm.MenuLanguageClick(Sender: TObject);
begin
  if Sender = MnuLangAr then ApplyLanguage(ulArabic) else ApplyLanguage(ulEnglish);
  if FLang = ulArabic then Say(S(sidSayLangAr)) else Say(S(sidSayLangEn));
end;

{ --------------------------------------------------------------- direction ---- }

{ Force BiDiMode on every control in the tree.

  Setting it on the form alone would be ENOUGH for a form whose controls all still have
  ParentBiDiMode = True: LCL propagates through CM_PARENTBIDIMODECHANGED. Walking is
  belt-and-braces -- it also reaches anything that has turned that flag off, and it makes the
  mechanism visible in a file whose whole job is to be read. Note that assigning BiDiMode
  clears ParentBiDiMode on each control, which is exactly what we want here. }
procedure TMainForm.SetBiDiDeep(AControl: TControl; AMode: TBiDiMode);
var
  i: Integer;
  wc: TWinControl;
begin
  if AControl = nil then Exit;
  AControl.BiDiMode := AMode;
  if AControl is TWinControl then
  begin
    wc := TWinControl(AControl);
    for i := 0 to wc.ControlCount - 1 do
      SetBiDiDeep(wc.Controls[i], AMode);
  end;
end;

{ The strings that depend on BOTH switches. Split out of ApplyDirection so that changing the
  LANGUAGE can restate them without re-running the BiDi walk, and so neither path can drift
  into saying "right-to-left" in English on an Arabic window. }
procedure TMainForm.RefreshDirectionText;
begin
  DirSwitch.Checked := FRtl;
  MnuDirLtr.Checked := not FRtl;
  MnuDirRtl.Checked := FRtl;

  if FRtl then
  begin
    LblDirState.Caption := S(sidDirRtl);
    if StatusBar1.Panels.Count > 1 then
      TTyStatusPanel(StatusBar1.Panels.Items[1]).Text := S(sidStatusRtl);
    if StatusBar1.Panels.Count > 2 then
      TTyStatusPanel(StatusBar1.Panels.Items[2]).Text := S(sidGripRtl);
  end
  else
  begin
    LblDirState.Caption := S(sidDirLtr);
    if StatusBar1.Panels.Count > 1 then
      TTyStatusPanel(StatusBar1.Panels.Items[1]).Text := S(sidStatusLtr);
    if StatusBar1.Panels.Count > 2 then
      TTyStatusPanel(StatusBar1.Panels.Items[2]).Text := S(sidGripLtr);
  end;
end;

procedure TMainForm.ApplyDirection(ARightToLeft: Boolean);
var
  m: TBiDiMode;
begin
  if FApplying then Exit;
  FApplying := True;
  try
    FRtl := ARightToLeft;
    if ARightToLeft then m := bdRightToLeft else m := bdLeftToRight;

    { The form first: a TTyPopupMenu has no BiDiMode of its own and reads the control it was
      raised on, so the hosts have to be right before any popup opens. }
    BiDiMode := m;
    SetBiDiDeep(Surface, m);

    RefreshDirectionText;

    if ARightToLeft then Say(S(sidSayDirRtl)) else Say(S(sidSayDirLtr));

    Invalidate;
  finally
    FApplying := False;
  end;
end;

procedure TMainForm.DirSwitchChange(Sender: TObject);
begin
  ApplyDirection(DirSwitch.Checked);
end;

procedure TMainForm.MenuDirectionClick(Sender: TObject);
begin
  ApplyDirection(Sender = MnuDirRtl);
end;

procedure TMainForm.MenuItemClicked(Sender: TObject);
begin
  { Reporting WHICH item was chosen is the point: a mirrored menu that highlights one row and
    activates another is exactly the defect this window exists to expose. }
  if Sender is TMenuItem then
    Say(Format(S(sidSayMenuFmt), [StripHotkey(TMenuItem(Sender).Caption)]));
end;

procedure TMainForm.MenuFileExitClick(Sender: TObject);
begin
  Close;
end;

end.
