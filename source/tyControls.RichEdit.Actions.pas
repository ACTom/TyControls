unit tyControls.RichEdit.Actions;

{ Ready-made actions for a TTyRichEdit's menus and toolbars - Delphi's TRichEditBold family and
  more: the character styles, the paragraph's alignment, lists and indent, a picture and a
  table, find and replace, undo and redo, zoom. Put them in a TActionList (the IDE's action
  list editor offers them under 'TyControls Rich Edit') and link menu items, TTySpeedButtons or
  any other control to them.

  Which rich edit: the one the RichEdit property names when it is set (another form's too),
  else the focused control when it is a TTyCustomRichEdit - LCL's way for edit actions
  (HandlesTarget / UpdateTarget / ExecuteTarget) -, else none, and then the action is disabled
  (DisableIfNoHandler).

  What they show is the rich edit's own answer, never a rule of theirs: Enabled is the
  control's Can... query (CanFormatCharacters, CanFormatParagraphs, CanUndo, CanInsertTable,
  CanInsertPicture - False also in a field's result or a row that holds a nested table where
  the change would be refused); Checked is the format API's reading (SelAttributes,
  Paragraph) - a style, an alignment or a list shared by the whole selection
  (ConsistentAttributes), never a mixed one. What they do goes through the control's doors for
  the user: ApplyCharacterFormat, ApplyParagraphFormat, InsertTable, InsertPictureFromFile,
  Undo, Redo - each one undo step named as the control names it (a character style with
  nothing selected: the format the next typed text gets), a refusal told by the control
  (OnEditRefused) as for a key.

  What an update costs: the application's idle updates every action, several times when a
  menu item and a button share one. The actions do not ask the rich edit each time: one
  record per rich edit (TTyRichEditActionState) asks it once after each change of its
  selection, content, format, view, ReadOnly or Enabled - the notification the ruler hears
  (AddHandlerOnParagraphView), not the application's events -, and every action reads that
  record. The format queries it asks (SelAttributes.ConsistentAttributes and Paragraph's) are
  bounded by the control (about 30 ms of a walk over a selection, the answer remembered for
  the selection and the content); an idle round reads none of them.

  Shortcuts are the common editors' (Ctrl+B, I, U; Ctrl+L, E, R, J; Ctrl+Z, Y; Ctrl+F, H;
  Ctrl+plus, minus, 0), each the action's default, changeable. A key the rich edit takes
  itself is never the action's too: LCL asks the focused control first, so Ctrl+Z and Ctrl+Y
  in a focused rich edit are its own undo and redo, and the actions' shortcuts serve the
  others and the keys it leaves (Ctrl+B ...).

  Find and Replace show the package's own dialogs (TTyFindDialog, TTyReplaceDialog; Dialog
  publishes each as a subcomponent): Find Next runs the rich edit's FindNext, Replace replaces
  the match selected and finds the next, Replace All its ReplaceAll (one undo step). Insert
  picture asks for a file with the package's open dialog (a filter of the formats the rich
  edit reads: TyRichPictureFilter); Insert table inserts Rows x Columns, OnChooseSize asking
  first. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, Controls, ActnList, Dialogs, LCLType, LCLProc,
  tyControls.StrConsts, tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Attrs,
  tyControls.RichEdit.RowFormat, tyControls.RichEdit.TableProps,
  tyControls.RichEdit.Find, tyControls.RichEdit, tyControls.Dialogs, tyControls.Dialogs.Find,
  tyControls.Dialogs.FileDialog;

const
  { The shortcuts given as the actions' defaults (TShortCut values: Ctrl is $4000, Shift
    $2000), so a form file stores only a changed one. }
  CTyRichKeyBold = $4000 + VK_B;
  CTyRichKeyItalic = $4000 + VK_I;
  CTyRichKeyUnderline = $4000 + VK_U;
  CTyRichKeyAlignLeft = $4000 + VK_L;
  CTyRichKeyAlignCenter = $4000 + VK_E;
  CTyRichKeyAlignRight = $4000 + VK_R;
  CTyRichKeyJustify = $4000 + VK_J;
  CTyRichKeyBullets = $4000 + $2000 + VK_L;
  CTyRichKeyFind = $4000 + VK_F;
  CTyRichKeyReplace = $4000 + VK_H;
  CTyRichKeyUndo = $4000 + VK_Z;
  CTyRichKeyRedo = $4000 + VK_Y;
  CTyRichKeyZoomIn = $4000 + VK_OEM_PLUS;
  CTyRichKeyZoomOut = $4000 + VK_OEM_MINUS;
  CTyRichKeyZoomReset = $4000 + VK_0;
  CTyRichKeyCut = $4000 + VK_X;
  CTyRichKeyCopy = $4000 + VK_C;
  CTyRichKeyPaste = $4000 + VK_V;
  CTyRichKeySelectAll = $4000 + VK_A;
  CTyRichKeyFontGrow = $4000 + $2000 + VK_OEM_PERIOD;
  CTyRichKeyFontShrink = $4000 + $2000 + VK_OEM_COMMA;
  CTyRichKeyClearFormat = $4000 + VK_SPACE;
  { The text colour and the highlight Color actions are made with. }
  CTyRichDefaultTextColor = clRed;
  CTyRichDefaultHighlight = clYellow;
  { The size a font size action is made with (points). }
  CTyRichDefaultFontSize = 11;
  { How far Increase / Decrease Indent move a paragraph: to the next multiple of half an inch
    (Word's default tab stops), twips. }
  CTyRichIndentStep = 720;
  { The default size of the table Insert table makes. }
  CTyRichDefaultTableSize = 3;

type
  { What the actions show of one rich edit, asked of it once per change (see the unit's
    header). Owned by the rich edit, made by the first action that looks at it; an
    application does not make one. }
  TTyRichEditActionState = class(TComponent)
  private
    FRich: TTyCustomRichEdit;
    FDirty: Boolean;
    FRefreshes, FQueries: Integer;
    FReadable, FCanChars, FCanParas: Boolean;
    FCaretPara: TTyParaFormat;
    FStyle: TFontStyles;
    FCharSame: TTyRichConsistentAttributes;
    FSubscript: TTySubscriptType;
    FAlign: TTyParaAlign;
    FList: TTyListKind;
    FParaSame: TTyRichConsistentParaAttributes;
    FCanTable, FCanPicture: Boolean;
    FFontName: string;
    FFontSize: Integer;
    FSpacing: TTyLineSpacing;
    FMultiple: Double;
    FSpaceBefore, FSpaceAfter: Double;
    FCanRowIns, FCanColIns, FCanRowDel, FCanColDel, FCanTableDel: Boolean;
    FCanLink, FCanEditLink: Boolean;
    FCanCells, FCanColSize, FCanRowSize: Boolean;
    procedure ViewChanged(Sender: TObject);
    procedure Refresh;
  public
    constructor CreateFor(ARich: TTyCustomRichEdit);
    destructor Destroy; override;
    { The record of ARich (made the first time). }
    class function Find(ARich: TTyCustomRichEdit): TTyRichEditActionState;
    { What it shows is to be asked again before it is read next. }
    procedure Changed;
    { Asks the rich edit again when something changed since it last asked. }
    procedure Check;
    property RichEdit: TTyCustomRichEdit read FRich;
    { How many times it asked the rich edit, and how many of the rich edit's queries that took
      (for a test that holds an idle round to no query). }
    property Refreshes: Integer read FRefreshes;
    property Queries: Integer read FQueries;
    { The formats could be read (the document outside its update). }
    property Readable: Boolean read FReadable;
    { The control's CanFormatCharacters / CanFormatParagraphs. }
    property CanFormatCharacters: Boolean read FCanChars;
    property CanFormatParagraphs: Boolean read FCanParas;
    { The caret's paragraph's format (meaningful with Readable). }
    property CaretParagraph: TTyParaFormat read FCaretPara;
    { SelAttributes.Style / ConsistentAttributes / Subscript; Paragraph.ParaAlign / Numbering
      / ConsistentAttributes (meaningful with Readable). }
    property Style: TFontStyles read FStyle;
    property CharConsistent: TTyRichConsistentAttributes read FCharSame;
    property Subscript: TTySubscriptType read FSubscript;
    property ParaAlign: TTyParaAlign read FAlign;
    property Numbering: TTyListKind read FList;
    property ParaConsistent: TTyRichConsistentParaAttributes read FParaSame;
    property CanInsertTable: Boolean read FCanTable;
    property CanInsertPicture: Boolean read FCanPicture;
    { SelAttributes.Name / Size (points) and Paragraph.LineSpacingRule (meaningful with
      Readable); the table queries CanInsertRow .. CanDeleteTable. }
    property FontName: string read FFontName;
    property FontSize: Integer read FFontSize;
    property LineSpacing: TTyLineSpacing read FSpacing;
    { Paragraph.LineSpacingMultiple (0 for an exact or an at-least spacing), the space before
      and after (points, to the twip, as GetParaMetric reports them) - the first paragraph the
      selection touches (meaningful with
      Readable). }
    property LineMultiple: Double read FMultiple;
    property SpaceBefore: Double read FSpaceBefore;
    property SpaceAfter: Double read FSpaceAfter;
    property CanInsertRow: Boolean read FCanRowIns;
    property CanInsertColumn: Boolean read FCanColIns;
    property CanDeleteRow: Boolean read FCanRowDel;
    property CanDeleteColumn: Boolean read FCanColDel;
    property CanDeleteTable: Boolean read FCanTableDel;
    // the link queries CanInsertLink and CanEditLink
    property CanInsertLink: Boolean read FCanLink;
    property CanEditLink: Boolean read FCanEditLink;
    // the table format and size queries CanFormatCells, CanResizeColumns, CanResizeRows
    property CanFormatCells: Boolean read FCanCells;
    property CanResizeColumns: Boolean read FCanColSize;
    property CanResizeRows: Boolean read FCanRowSize;
  end;

  { The base of the rich edit's actions: the target (RichEdit, else the focused rich edit) and
    LCL's three calls. A descendant overrides UpdateOn / ExecuteOn. }
  TTyRichEditAction = class(TAction)
  private
    FRichEdit: TTyCustomRichEdit;
    procedure SetRichEdit(AValue: TTyCustomRichEdit);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { The rich edit Target is, or nil. }
    function RichOf(Target: TObject): TTyCustomRichEdit;
    function StateOf(ARich: TTyCustomRichEdit): TTyRichEditActionState;
    { Enabled and Checked from ARich's record (checked already). }
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); virtual;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function HandlesTarget(Target: TObject): Boolean; override;
    procedure UpdateTarget(Target: TObject); override;
    procedure ExecuteTarget(Target: TObject); override;
    { With RichEdit set the action needs no form to find its target: it updates and runs on
      that rich edit (after the action list's and its own OnUpdate / OnExecute, as LCL's). }
    function Update: Boolean; override;
    function Execute: Boolean; override;
  published
    property RichEdit: TTyCustomRichEdit read FRichEdit write SetRichEdit;
  end;

  { A character style switched on or off over the selection (or for the next typed text):
    Checked when the whole selection has it. }
  TTyRichEditStyleAction = class(TTyRichEditAction)
  protected
    function StyleOf: TFontStyle; virtual; abstract;
    { The selection (the paragraphs) has it now, as the update shows it: what a run decides
      by (never Checked, which AutoCheck turns before the run). }
    function IsOn(AState: TTyRichEditActionState): Boolean;
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  end;

  TTyRichEditBold = class(TTyRichEditStyleAction)
  protected
    function StyleOf: TFontStyle; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyBold;
  end;

  TTyRichEditItalic = class(TTyRichEditStyleAction)
  protected
    function StyleOf: TFontStyle; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyItalic;
  end;

  TTyRichEditUnderline = class(TTyRichEditStyleAction)
  protected
    function StyleOf: TFontStyle; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyUnderline;
  end;

  TTyRichEditStrikeOut = class(TTyRichEditStyleAction)
  protected
    function StyleOf: TFontStyle; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { Superscript or subscript switched on (the other one off) or off. }
  TTyRichEditScriptAction = class(TTyRichEditAction)
  protected
    function ScriptOf: TTySubscriptType; virtual; abstract;
    { The selection (the paragraphs) has it now, as the update shows it: what a run decides
      by (never Checked, which AutoCheck turns before the run). }
    function IsOn(AState: TTyRichEditActionState): Boolean;
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  end;

  TTyRichEditSuperscript = class(TTyRichEditScriptAction)
  protected
    function ScriptOf: TTySubscriptType; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditSubscript = class(TTyRichEditScriptAction)
  protected
    function ScriptOf: TTySubscriptType; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { The paragraphs' alignment: Checked when every paragraph the selection touches has it. }
  TTyRichEditAlignAction = class(TTyRichEditAction)
  protected
    function AlignOf: TTyParaAlign; virtual; abstract;
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  end;

  TTyRichEditAlignLeft = class(TTyRichEditAlignAction)
  protected
    function AlignOf: TTyParaAlign; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyAlignLeft;
  end;

  TTyRichEditAlignCenter = class(TTyRichEditAlignAction)
  protected
    function AlignOf: TTyParaAlign; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyAlignCenter;
  end;

  TTyRichEditAlignRight = class(TTyRichEditAlignAction)
  protected
    function AlignOf: TTyParaAlign; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyAlignRight;
  end;

  TTyRichEditAlignJustify = class(TTyRichEditAlignAction)
  protected
    function AlignOf: TTyParaAlign; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyJustify;
  end;

  { A list kind switched on (the paragraphs become its items, with the default hanging indent
    where they have none) or off (plain paragraphs again) - the format API's Numbering. }
  TTyRichEditListAction = class(TTyRichEditAction)
  protected
    function KindOf: TTyListKind; virtual; abstract;
    { The selection (the paragraphs) has it now, as the update shows it: what a run decides
      by (never Checked, which AutoCheck turns before the run). }
    function IsOn(AState: TTyRichEditActionState): Boolean;
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  end;

  TTyRichEditBullets = class(TTyRichEditListAction)
  protected
    function KindOf: TTyListKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyBullets;
  end;

  TTyRichEditNumbering = class(TTyRichEditListAction)
  protected
    function KindOf: TTyListKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { The paragraphs moved right or left: the caret paragraph's first line to the next (the
    previous) multiple of CTyRichIndentStep, not left of the margin, and every paragraph the
    selection touches to that place, each keeping its own hanging offset (Delphi's
    FirstIndent; the ruler's rule for several paragraphs). When every paragraph the selection
    touches is a list item: each a list level deeper (shallower) instead, within 0 .. 8 - at
    level 0 Decrease leaves an item where it is, as Word does (ChangeListLevel). }
  TTyRichEditIndentAction = class(TTyRichEditAction)
  protected
    function Direction: Integer; virtual; abstract;
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  end;

  TTyRichEditIndentIncrease = class(TTyRichEditIndentAction)
  protected
    function Direction: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditIndentDecrease = class(TTyRichEditIndentAction)
  protected
    function Direction: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { A picture from a file, chosen in the package's open dialog (Dialog; its Filter, when
    empty, is TyRichPictureFilter), through InsertPictureFromFile. Enabled: CanInsertPicture. }
  TTyRichEditInsertPicture = class(TTyRichEditAction)
  private
    FDialog: TTyOpenPictureDialog;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    { Asks for the file (the dialog; a test stands in for it). }
    function AskFileName(var AFileName: string): Boolean; virtual;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Dialog: TTyOpenPictureDialog read FDialog;
  end;

  { Before a table goes in: the size it will have; AInsert False inserts nothing. }
  TTyRichTableSizeEvent = procedure(Sender: TObject; var ARows, AColumns: Integer;
    var AInsert: Boolean) of object;

  { A Rows x Columns table at the caret (InsertTable); OnChooseSize first, where an
    application asks the user. Enabled: CanInsertTable. }
  TTyRichEditInsertTable = class(TTyRichEditAction)
  private
    FRows, FColumns: Integer;
    FOnChooseSize: TTyRichTableSizeEvent;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Rows: Integer read FRows write FRows default CTyRichDefaultTableSize;
    property Columns: Integer read FColumns write FColumns default CTyRichDefaultTableSize;
    property OnChooseSize: TTyRichTableSizeEvent read FOnChooseSize write FOnChooseSize;
  end;

  { Before a link is made or changed: its address and text, which the handler may change;
    AAllow False (or an empty address) does nothing. }
  TTyRichLinkEvent = procedure(Sender: TObject; var AURL, AText: string;
    var AAllow: Boolean) of object;

  { A link at the caret: the link the caret or the selection is in changed (SetLink), else a
    new one over the selection (InsertLink). OnGetLink asks for the address and the text
    first - the link's own, or '' and the selected text, given to it; a text left as it was
    given keeps the text as it is (its formats too). With no handler nothing happens: the
    application asks the user. Enabled: CanInsertLink or CanEditLink. }
  TTyRichEditInsertLink = class(TTyRichEditAction)
  private
    FOnGetLink: TTyRichLinkEvent;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property OnGetLink: TTyRichLinkEvent read FOnGetLink write FOnGetLink;
  end;

  { The link at the caret stops being one, its text kept (RemoveLink). Enabled: CanEditLink. }
  TTyRichEditRemoveLink = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { A search found nothing. }
  TTyRichNotFoundEvent = procedure(Sender: TObject; const AText: string) of object;
  { Replace All replaced ACount matches. }
  TTyRichReplacedEvent = procedure(Sender: TObject; ACount: Integer) of object;

  { The package's find dialog (Dialog), shown for the rich edit the action ran on; its Find
    Next is the rich edit's FindNext (the case and whole-word boxes; up or down; round the
    document's end). Nothing found: OnNotFound, else the package's message box. The dialog's
    OnFind is the action's. Enabled: a rich edit to search (it is enabled). }
  TTyRichEditFind = class(TTyRichEditAction)
  private
    FOnNotFound: TTyRichNotFoundEvent;
    procedure DialogFind(Sender: TObject);
    procedure SetSearched(AValue: TTyCustomRichEdit);
  protected
    FSearched: TTyCustomRichEdit;
    FDialog: TTyFindDialog;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function MakeDialog: TTyFindDialog; virtual;
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    { Shows the dialog (a test builds it without showing it). }
    procedure ShowDialog; virtual;
    { Nothing found: OnNotFound, else ShowNotFound. }
    procedure NotFound(const AText: string);
    procedure ShowNotFound(const AText: string); virtual;
    function SearchOptions: TTyRichFindOptions;
    { Find Next on the rich edit searched; False when nothing was found (told). }
    function FindAgain: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    { The rich edit the dialog searches (the last one the action ran on). }
    property Searched: TTyCustomRichEdit read FSearched;
  published
    property ShortCut default CTyRichKeyFind;
    { The dialog the action shows (a TTyReplaceDialog for the replace action). Its OnFind and
      OnReplace are the action's. }
    property Dialog: TTyFindDialog read FDialog;
    property OnNotFound: TTyRichNotFoundEvent read FOnNotFound write FOnNotFound;
  end;

  { The package's replace dialog: Find Next as Find's, Replace the selected match (then the
    next found), Replace All every match as one undo step (the rich edit's ReplaceAll;
    OnReplaced says how many). It replaces only where the user may edit (not ReadOnly, the
    document taking edits): the replace methods are the document API and do not stop there
    by themselves. Enabled: as the formats'. }
  TTyRichEditReplace = class(TTyRichEditFind)
  private
    FOnReplaced: TTyRichReplacedEvent;
    procedure DialogReplace(Sender: TObject);
    function GetReplaceDialog: TTyReplaceDialog;
  protected
    function MakeDialog: TTyFindDialog; override;
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Dialog as what it is. }
    property ReplaceDialog: TTyReplaceDialog read GetReplaceDialog;
  published
    property ShortCut default CTyRichKeyReplace;
    property OnReplaced: TTyRichReplacedEvent read FOnReplaced write FOnReplaced;
  end;

  TTyRichEditUndo = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyUndo;
  end;

  TTyRichEditRedo = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyRedo;
  end;

  { Zoom by CRichZoomStep (Ctrl+wheel's step) within CRichZoomMin .. CRichZoomMax, or back
    to 100 %. }
  TTyRichEditZoomIn = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyZoomIn;
  end;

  TTyRichEditZoomOut = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyZoomOut;
  end;

  TTyRichEditZoomReset = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyZoomReset;
  end;

  { ---- the clipboard and the selection: the control's own commands, as its text menu runs
    them (ITyTextEditActions answers what they may do) ---- }

  TTyRichEditCut = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyCut;
  end;

  TTyRichEditCopy = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyCopy;
  end;

  { Enabled: CanPaste, asked at each update (the clipboard tells the control nothing when it
    changes; the question lists its formats, it reads no content). }
  TTyRichEditPaste = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyPaste;
  end;

  TTyRichEditSelectAll = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeySelectAll;
  end;

  { The selection deleted (ClearSelection, the user's Delete). No shortcut of its own: the
    Delete key is the focused control's. }
  TTyRichEditDelete = class(TTyRichEditAction)
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { ---- colours ---- }

  { Before a colour goes in: the colour it will be (a dialog may change it); AApply False
    applies nothing. }
  TTyRichColorEvent = procedure(Sender: TObject; var AColor: TColor; var AApply: Boolean) of object;

  { Color to the selection (with nothing selected, to the text typed next), through
    ApplyCharacterFormat; OnChooseColor first. Enabled: CanFormatCharacters. }
  TTyRichEditColorAction = class(TTyRichEditAction)
  private
    FColor: TColor;
    FOnChooseColor: TTyRichColorEvent;
  protected
    { The field and the value Color gives it. }
    procedure FormatOf(AColor: TColor; out AMask: TTyCharFormatMask; out AValue: TTyCharFormat);
      virtual; abstract;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  published
    property OnChooseColor: TTyRichColorEvent read FOnChooseColor write FOnChooseColor;
  end;

  { The text colour: Color (clDefault or clWindowText: automatic - the theme's text colour,
    the text keeping no colour of its own). }
  TTyRichEditTextColor = class(TTyRichEditColorAction)
  protected
    procedure FormatOf(AColor: TColor; out AMask: TTyCharFormatMask; out AValue: TTyCharFormat);
      override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Color: TColor read FColor write FColor default CTyRichDefaultTextColor;
  end;

  { The highlight (the text's background): Color (clNone, clDefault or clWindow: none). }
  TTyRichEditHighlightColor = class(TTyRichEditColorAction)
  protected
    procedure FormatOf(AColor: TColor; out AMask: TTyCharFormatMask; out AValue: TTyCharFormat);
      override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Color: TColor read FColor write FColor default CTyRichDefaultHighlight;
  end;

  { ---- the font ---- }

  { FontName to the selection (or the text typed next). Checked: the whole selection has that
    font (SelAttributes.Name, caFace). A name LCL takes for its default ('default', '') makes
    the text follow the control's font again. }
  TTyRichEditFontName = class(TTyRichEditAction)
  private
    FFontName: string;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property FontName: string read FFontName write FFontName;
  end;

  { Size (points) to the selection. Checked: the whole selection has that size (caSize). The
    control keeps half points; this action writes whole ones (ApplyCharacterFormat takes a
    half point, SizeHalfPt, for a program that needs one). }
  TTyRichEditFontSize = class(TTyRichEditAction)
  private
    FSize: Integer;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Size: Integer read FSize write FSize default CTyRichDefaultFontSize;
  end;

  { The font one step larger / smaller on the usual scale (8, 9, 10, 11, 12, 14, 16, 18, 20,
    22, 24, 26, 28, 36, 48, 72), from the selection's first character's size, given to the
    whole selection. Enabled: CanFormatCharacters, short of the scale's end. }
  TTyRichEditFontStepAction = class(TTyRichEditAction)
  protected
    function Direction: Integer; virtual; abstract;
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  end;

  TTyRichEditFontGrow = class(TTyRichEditFontStepAction)
  protected
    function Direction: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyFontGrow;
  end;

  TTyRichEditFontShrink = class(TTyRichEditFontStepAction)
  protected
    function Direction: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyFontShrink;
  end;

  { Every character attribute of the selection back to none of its own (the document's
    default: the control's font and the theme's colour, no style, no highlight, no script),
    one undo step. Attributes the control keeps but does not show (a file's opaque ones) stay. }
  TTyRichEditClearFormat = class(TTyRichEditAction)
  protected
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ShortCut default CTyRichKeyClearFormat;
  end;

  { The paragraphs' line spacing: Multiple times the line's own height when it is above 0 (1.08,
    3 - any multiple, to a 240th as a file holds it), else the rule Spacing (single, 1.15,
    1.5, double; an exact or an at-least spacing keeps its height, a paragraph with none takes
    the line's own). Checked: the first paragraph the selection touches has that spacing (the
    format API reads no consistency for spacing). Enabled: CanFormatParagraphs. }
  TTyRichEditLineSpacing = class(TTyRichEditAction)
  private
    FSpacing: TTyLineSpacing;
    FMultiple: Double;
    function IsMultipleStored: Boolean;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Spacing: TTyLineSpacing read FSpacing write FSpacing default lsSingle;
    property Multiple: Double read FMultiple write FMultiple stored IsMultipleStored;
  end;

  { The space before and after the paragraphs the selection touches: Before and After in
    points (to the twip, 7.5 as well), each -1 (the default) to leave that side as it is -
    0, 6, 12 as Word's menu has them, or both at once. Checked: the first paragraph the
    selection touches has the sides given, to the twip (GetParaMetric's points). Enabled:
    CanFormatParagraphs, and a side given. }
  TTyRichEditParagraphSpacing = class(TTyRichEditAction)
  private
    FBefore, FAfter: Double;
    function IsBeforeStored: Boolean;
    function IsAfterStored: Boolean;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Before: Double read FBefore write FBefore stored IsBeforeStored;
    property After: Double read FAfter write FAfter stored IsAfterStored;
  end;

  { ---- table operations: the control's own, Enabled by its own Can... at the caret ---- }

  TTyRichEditTableKind = (rtkRowAbove, rtkRowBelow, rtkColumnLeft, rtkColumnRight,
    rtkDeleteRow, rtkDeleteColumn, rtkDeleteTable);

  TTyRichEditTableAction = class(TTyRichEditAction)
  protected
    function KindOf: TTyRichEditTableKind; virtual; abstract;
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  end;

  TTyRichEditInsertRowAbove = class(TTyRichEditTableAction)
  protected
    function KindOf: TTyRichEditTableKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditInsertRowBelow = class(TTyRichEditTableAction)
  protected
    function KindOf: TTyRichEditTableKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditInsertColumnLeft = class(TTyRichEditTableAction)
  protected
    function KindOf: TTyRichEditTableKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditInsertColumnRight = class(TTyRichEditTableAction)
  protected
    function KindOf: TTyRichEditTableKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditDeleteRow = class(TTyRichEditTableAction)
  protected
    function KindOf: TTyRichEditTableKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditDeleteColumn = class(TTyRichEditTableAction)
  protected
    function KindOf: TTyRichEditTableKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditDeleteTable = class(TTyRichEditTableAction)
  protected
    function KindOf: TTyRichEditTableKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;


  { ---- a table's formats and sizes: Enabled by the control's CanFormatCells / CanResize... ---- }

  { The selected cells' (else the caret cell's) shading: Color (clNone: none). }
  TTyRichEditCellShading = class(TTyRichEditAction)
  private
    FColor: TColor;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Color: TColor read FColor write FColor default clYellow;
  end;

  { Before the borders go on: the preset and the line, which a handler may change (its own
    form), AAllow False: nothing happens. }
  TTyRichCellBordersEvent = procedure(Sender: TObject; var APreset: TTyRichBorderPreset;
    var ABorder: TTyRichBorder; var AAllow: Boolean) of object;

  { A border preset on the selected cells (SetCellBorders): Preset, the line's LineStyle,
    LineWidth (twips; Word's ½ pt is 10) and LineColor (clDefault: automatic);
    OnBeforeExecute first. }
  TTyRichEditCellBorders = class(TTyRichEditAction)
  private
    FPreset: TTyRichBorderPreset;
    FLineStyle: TTyRichBorderStyle;
    FLineWidth: Integer;
    FLineColor: TColor;
    FOnBeforeExecute: TTyRichCellBordersEvent;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Preset: TTyRichBorderPreset read FPreset write FPreset default rbpAll;
    property LineStyle: TTyRichBorderStyle read FLineStyle write FLineStyle default rbsSingle;
    property LineWidth: Integer read FLineWidth write FLineWidth default 10;
    property LineColor: TColor read FLineColor write FLineColor default clDefault;
    property OnBeforeExecute: TTyRichCellBordersEvent read FOnBeforeExecute write FOnBeforeExecute;
  end;

  { The selected cells' padding (SetCellPadding), twips; -1 a side as it is. }
  TTyRichEditCellPadding = class(TTyRichEditAction)
  private
    FPadLeft, FPadTop, FPadRight, FPadBottom: Integer;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property PadLeft: Integer read FPadLeft write FPadLeft default 108;
    property PadTop: Integer read FPadTop write FPadTop default 0;
    property PadRight: Integer read FPadRight write FPadRight default 108;
    property PadBottom: Integer read FPadBottom write FPadBottom default 0;
  end;

  { Where the selected cells' content sits (SetCellVAlign). }
  TTyRichEditCellVAlign = class(TTyRichEditAction)
  private
    FAlign: TTyRowCellVAlign;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Align: TTyRowCellVAlign read FAlign write FAlign default rcvTop;
  end;

  { The caret's table aligned (SetTableAlign): Align, Indent (twips from the margin). }
  TTyRichEditTableAlign = class(TTyRichEditAction)
  private
    FAlign: TTyRowAlign;
    FIndent: Integer;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Align: TTyRowAlign read FAlign write FAlign default rraCenter;
    property Indent: Integer read FIndent write FIndent default 0;
  end;

  { Before the table properties go on: AProps holds what the caret's cell, row and table have
    now (Valid: every field); a handler shows its own form, changes them and says which to set
    (Valid), or AAllow False: nothing. }
  TTyRichTablePropertiesEvent = procedure(Sender: TObject; var AProps: TTyRichTableProperties;
    var AAllow: Boolean) of object;

  { Table properties: OnBeforeExecute (no handler: nothing to ask, nothing happens), then each
    field Valid names through its door - the whole as one undo step. }
  TTyRichEditTableProperties = class(TTyRichEditAction)
  private
    FOnBeforeExecute: TTyRichTablePropertiesEvent;
  protected
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property OnBeforeExecute: TTyRichTablePropertiesEvent read FOnBeforeExecute write FOnBeforeExecute;
  end;

  TTyRichEditSizeKind = (rskAutoFit, rskDistributeColumns, rskDistributeRows, rskFitWindow);

  TTyRichEditTableSizeAction = class(TTyRichEditAction)
  protected
    function KindOf: TTyRichEditSizeKind; virtual; abstract;
    procedure UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
    procedure ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState); override;
  end;

  TTyRichEditAutoFitColumn = class(TTyRichEditTableSizeAction)
  protected
    function KindOf: TTyRichEditSizeKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditDistributeColumns = class(TTyRichEditTableSizeAction)
  protected
    function KindOf: TTyRichEditSizeKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditDistributeRows = class(TTyRichEditTableSizeAction)
  protected
    function KindOf: TTyRichEditSizeKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditFitTableToWindow = class(TTyRichEditTableSizeAction)
  protected
    function KindOf: TTyRichEditSizeKind; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TTyRichEditActionClass = class of TTyRichEditAction;

const
  { Every action of this unit, in the order the IDE lists them. }
  CTyRichEditActions: array[0..55] of TTyRichEditActionClass = (
    TTyRichEditBold, TTyRichEditItalic, TTyRichEditUnderline, TTyRichEditStrikeOut,
    TTyRichEditSuperscript, TTyRichEditSubscript,
    TTyRichEditAlignLeft, TTyRichEditAlignCenter, TTyRichEditAlignRight,
    TTyRichEditAlignJustify, TTyRichEditBullets, TTyRichEditNumbering,
    TTyRichEditIndentIncrease, TTyRichEditIndentDecrease,
    TTyRichEditInsertPicture, TTyRichEditInsertTable,
    TTyRichEditFind, TTyRichEditReplace, TTyRichEditUndo, TTyRichEditRedo,
    TTyRichEditZoomIn, TTyRichEditZoomOut, TTyRichEditZoomReset,
    TTyRichEditCut, TTyRichEditCopy, TTyRichEditPaste, TTyRichEditSelectAll, TTyRichEditDelete,
    TTyRichEditTextColor, TTyRichEditHighlightColor, TTyRichEditFontName, TTyRichEditFontSize,
    TTyRichEditFontGrow, TTyRichEditFontShrink, TTyRichEditClearFormat, TTyRichEditLineSpacing,
    TTyRichEditInsertRowAbove, TTyRichEditInsertRowBelow, TTyRichEditInsertColumnLeft,
    TTyRichEditInsertColumnRight, TTyRichEditDeleteRow, TTyRichEditDeleteColumn,
    TTyRichEditDeleteTable, TTyRichEditInsertLink, TTyRichEditRemoveLink,
    TTyRichEditParagraphSpacing, TTyRichEditCellShading, TTyRichEditCellBorders,
    TTyRichEditCellPadding, TTyRichEditCellVAlign, TTyRichEditTableAlign,
    TTyRichEditTableProperties, TTyRichEditAutoFitColumn, TTyRichEditDistributeColumns,
    TTyRichEditDistributeRows, TTyRichEditFitTableToWindow);

  { The font sizes the grow and shrink actions step through (points). }
  CTyRichFontSizes: array[0..15] of Integer = (8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28,
    36, 48, 72);

{ An open dialog's filter of the picture files a rich edit reads (InsertPictureFromFile):
  every format the LCL reads (the formats registered with TPicture - PNG and JPEG are kept
  with their own bytes, the others decoded), without the metafiles it refuses; then all
  files. }
function TyRichPictureFilter: string;

implementation

function TyRichPictureFilter: string;
var
  masks: TStringList;
  i: Integer;
  m, e: string;
begin
  masks := TStringList.Create;
  try
    masks.Delimiter := ';';
    masks.StrictDelimiter := True;
    masks.DelimitedText := GraphicFileMask(TGraphic);
    m := '';
    for i := 0 to masks.Count - 1 do
    begin
      e := LowerCase(Trim(masks[i]));
      // (refused by the rich edit: a metafile is no picture it can hold)
      if (e = '') or (e = '*.wmf') or (e = '*.emf') then Continue;
      if m <> '' then m := m + ';';
      m := m + e;
    end;
  finally
    masks.Free;
  end;
  Result := Format(rsRichActPictureFiles, [m]) + '|' + m + '|' + rsRichActAllFiles + '|*';
end;

{ TTyRichEditActionState }

constructor TTyRichEditActionState.CreateFor(ARich: TTyCustomRichEdit);
begin
  // owned by the rich edit: it goes with it, and nothing of it outlives it
  inherited Create(ARich);
  FRich := ARich;
  FDirty := True;
  FRich.AddHandlerOnParagraphView(@ViewChanged);
end;

destructor TTyRichEditActionState.Destroy;
begin
  // (freed with its rich edit, whose handlers are gone by then)
  if (FRich <> nil) and not (csDestroying in FRich.ComponentState) then
    FRich.RemoveHandlerOnParagraphView(@ViewChanged);
  inherited Destroy;
end;

class function TTyRichEditActionState.Find(ARich: TTyCustomRichEdit): TTyRichEditActionState;
var
  i: Integer;
begin
  for i := 0 to ARich.ComponentCount - 1 do
    if ARich.Components[i] is TTyRichEditActionState then
      Exit(TTyRichEditActionState(ARich.Components[i]));
  Result := TTyRichEditActionState.CreateFor(ARich);
end;

procedure TTyRichEditActionState.ViewChanged(Sender: TObject);
begin
  // only noted: the hearer of this notification must not change the document
  FDirty := True;
end;

procedure TTyRichEditActionState.Changed;
begin
  FDirty := True;
end;

procedure TTyRichEditActionState.Check;
begin
  // (asked inside the document's update, which may end with nothing to report: asked again)
  if FDirty or (not FReadable and not FRich.Document.Updating) then Refresh;
end;

procedure TTyRichEditActionState.Refresh;
var
  d: TTyRichDocument;
  metric: TTyParaMetric;
begin
  FDirty := False;
  Inc(FRefreshes);
  FCanChars := FRich.CanFormatCharacters;
  FCanParas := FRich.CanFormatParagraphs;
  Inc(FQueries, 2);
  d := FRich.Document;
  // (inside the document's update its formats are not read: the user's actions are off then)
  FReadable := not d.Updating;
  if FReadable then
  begin
    FCaretPara := d.Formats.ParaFormat(d.ParaFormatOf(d.Text.ParaOfPos(
      Max(0, Min(FRich.CaretIndex, d.Text.Length)))));
    // the format API's readings: the selection's first character / paragraph, and what the
    // whole selection shares (bounded and remembered by the control)
    FStyle := FRich.SelAttributes.Style;
    FCharSame := FRich.SelAttributes.ConsistentAttributes;
    FSubscript := FRich.SelAttributes.Subscript;
    FAlign := FRich.Paragraph.ParaAlign;
    FList := FRich.Paragraph.Numbering;
    FParaSame := FRich.Paragraph.ConsistentAttributes;
    FFontName := FRich.SelAttributes.Name;
    FFontSize := FRich.SelAttributes.Size;
    FSpacing := FRich.Paragraph.LineSpacingRule;
    FMultiple := FRich.Paragraph.LineSpacingMultiple;
    // the paragraph door's points, to the twip (Paragraph.SpaceBefore is whole points)
    metric := Default(TTyParaMetric);
    FRich.GetParaMetric(Min(FRich.SelStart, d.Text.Length), metric);
    FSpaceBefore := metric.SpaceBefore;
    FSpaceAfter := metric.SpaceAfter;
    Inc(FQueries, 13);
  end
  else
  begin
    FCaretPara := TyDefaultParaFormat;
    FStyle := [];
    FCharSame := [];
    FSubscript := sstNone;
    FAlign := paraLeft;
    FList := lkNone;
    FParaSame := [];
    FFontName := '';
    FFontSize := 0;
    FSpacing := lsSingle;
    FMultiple := 1;
    FSpaceBefore := 0;
    FSpaceAfter := 0;
  end;
  FCanTable := FRich.CanInsertTable;
  FCanPicture := FRich.CanInsertPicture;
  FCanRowIns := FRich.CanInsertRow;
  FCanColIns := FRich.CanInsertColumn;
  FCanRowDel := FRich.CanDeleteRow;
  FCanColDel := FRich.CanDeleteColumn;
  FCanTableDel := FRich.CanDeleteTable;
  FCanLink := FRich.CanInsertLink;
  FCanEditLink := FRich.CanEditLink;
  FCanCells := FRich.CanFormatCells;
  FCanColSize := FRich.CanResizeColumns;
  FCanRowSize := FRich.CanResizeRows;
  Inc(FQueries, 12);
end;

{ TTyRichEditAction }

constructor TTyRichEditAction.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DisableIfNoHandler := True;
end;

destructor TTyRichEditAction.Destroy;
begin
  SetRichEdit(nil);
  inherited Destroy;
end;

procedure TTyRichEditAction.SetRichEdit(AValue: TTyCustomRichEdit);
begin
  if FRichEdit = AValue then Exit;
  if FRichEdit <> nil then FRichEdit.RemoveFreeNotification(Self);
  FRichEdit := AValue;
  if FRichEdit <> nil then FRichEdit.FreeNotification(Self);
end;

procedure TTyRichEditAction.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FRichEdit) then FRichEdit := nil;
end;

function TTyRichEditAction.RichOf(Target: TObject): TTyCustomRichEdit;
begin
  if Target is TTyCustomRichEdit then Result := TTyCustomRichEdit(Target)
  else Result := nil;
end;

function TTyRichEditAction.StateOf(ARich: TTyCustomRichEdit): TTyRichEditActionState;
begin
  Result := TTyRichEditActionState.Find(ARich);
end;

function TTyRichEditAction.HandlesTarget(Target: TObject): Boolean;
begin
  if FRichEdit <> nil then Result := Target = FRichEdit
  else Result := (Target is TTyCustomRichEdit) and TTyCustomRichEdit(Target).Focused;
end;

procedure TTyRichEditAction.UpdateTarget(Target: TObject);
var
  r: TTyCustomRichEdit;
  st: TTyRichEditActionState;
begin
  r := RichOf(Target);
  if (r = nil) or (csDesigning in r.ComponentState) or (csDestroying in r.ComponentState) then
  begin
    Enabled := False;
    Checked := False;
    Exit;
  end;
  st := StateOf(r);
  st.Check;
  UpdateOn(r, st);
end;

procedure TTyRichEditAction.ExecuteTarget(Target: TObject);
var
  r: TTyCustomRichEdit;
  st: TTyRichEditActionState;
begin
  r := RichOf(Target);
  if (r = nil) or (csDesigning in r.ComponentState) or (csDestroying in r.ComponentState) then
    Exit;
  st := StateOf(r);
  st.Check;
  ExecuteOn(r, st);
end;

function TTyRichEditAction.Update: Boolean;
begin
  if FRichEdit = nil then Exit(inherited Update);
  if (ActionList <> nil) and ActionList.UpdateAction(Self) then Exit(True);
  if Assigned(OnUpdate) then
  begin
    OnUpdate(Self);
    Exit(True);
  end;
  UpdateTarget(FRichEdit);
  Result := True;
end;

function TTyRichEditAction.Execute: Boolean;
begin
  if FRichEdit = nil then Exit(inherited Execute);
  Result := False;
  if (ActionList <> nil) and (ActionList.State <> asNormal) then Exit;
  Update;
  if AutoCheck then Checked := not Checked;
  if not Enabled then Exit;
  if (ActionList <> nil) and ActionList.ExecuteAction(Self) then Exit(True);
  if Assigned(OnExecute) then
  begin
    OnExecute(Self);
    Exit(True);
  end;
  // (the target may be gone by now: a handler of the update)
  if FRichEdit = nil then Exit;
  ExecuteTarget(FRichEdit);
  Result := True;
end;

procedure TTyRichEditAction.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCharacters;
  Checked := False;
end;

procedure TTyRichEditAction.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
end;

{ TTyRichEditStyleAction }

function TTyRichEditStyleAction.IsOn(AState: TTyRichEditActionState): Boolean;
const
  Same: array[TFontStyle] of TTyRichConsistentAttribute = (caBold, caItalic, caUnderline,
    caStrikeOut);
begin
  Result := AState.Readable and (StyleOf in AState.Style) and
    (Same[StyleOf] in AState.CharConsistent);
end;

procedure TTyRichEditStyleAction.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCharacters;
  Checked := IsOn(AState);
end;

procedure TTyRichEditStyleAction.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
const
  Fields: array[TFontStyle] of TTyCharFormatField = (cffBold, cffItalic, cffUnderline, cffStrike);
var
  f: TTyCharFormat;
begin
  // SelAttributes' one-style write, through the user's door; on or off by what the selection
  // has now - never by Checked, which AutoCheck (LCL's Execute) may have turned already
  f := TyDefaultCharFormat;
  if not IsOn(AState) then
    if StyleOf = fsStrikeOut then f.Strike := True
    else Include(f.Style, StyleOf);
  // asked again after this (a write with nothing selected tells no one)
  AState.Changed;
  ARich.ApplyCharacterFormat([Fields[StyleOf]], f);
end;

function TTyRichEditBold.StyleOf: TFontStyle;
begin
  Result := fsBold;
end;

constructor TTyRichEditBold.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActBold;
  Hint := rsRichActBoldHint;
  ShortCut := CTyRichKeyBold;
end;

function TTyRichEditItalic.StyleOf: TFontStyle;
begin
  Result := fsItalic;
end;

constructor TTyRichEditItalic.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActItalic;
  Hint := rsRichActItalicHint;
  ShortCut := CTyRichKeyItalic;
end;

function TTyRichEditUnderline.StyleOf: TFontStyle;
begin
  Result := fsUnderline;
end;

constructor TTyRichEditUnderline.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActUnderline;
  Hint := rsRichActUnderlineHint;
  ShortCut := CTyRichKeyUnderline;
end;

function TTyRichEditStrikeOut.StyleOf: TFontStyle;
begin
  Result := fsStrikeOut;
end;

constructor TTyRichEditStrikeOut.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActStrikeOut;
  Hint := rsRichActStrikeOutHint;
end;

{ TTyRichEditScriptAction }

function TTyRichEditScriptAction.IsOn(AState: TTyRichEditActionState): Boolean;
begin
  Result := AState.Readable and (AState.Subscript = ScriptOf) and
    (caSubscript in AState.CharConsistent);
end;

procedure TTyRichEditScriptAction.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCharacters;
  Checked := IsOn(AState);
end;

procedure TTyRichEditScriptAction.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  if IsOn(AState) then f.VertAlign := vaNone
  else if ScriptOf = sstSuperscript then f.VertAlign := vaSuper
  else f.VertAlign := vaSub;
  AState.Changed;
  ARich.ApplyCharacterFormat([cffVertAlign], f);
end;

function TTyRichEditSuperscript.ScriptOf: TTySubscriptType;
begin
  Result := sstSuperscript;
end;

constructor TTyRichEditSuperscript.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActSuperscript;
  Hint := rsRichActSuperscriptHint;
end;

function TTyRichEditSubscript.ScriptOf: TTySubscriptType;
begin
  Result := sstSubscript;
end;

constructor TTyRichEditSubscript.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActSubscript;
  Hint := rsRichActSubscriptHint;
end;

{ TTyRichEditAlignAction }

procedure TTyRichEditAlignAction.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatParagraphs;
  Checked := AState.Readable and (AState.ParaAlign = AlignOf) and
    (cpaAlignment in AState.ParaConsistent);
end;

procedure TTyRichEditAlignAction.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.Align := AlignOf;
  ARich.ApplyParagraphFormat([pffAlign], f);
end;

function TTyRichEditAlignLeft.AlignOf: TTyParaAlign;
begin
  Result := paraLeft;
end;

constructor TTyRichEditAlignLeft.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActAlignLeft;
  Hint := rsRichActAlignLeftHint;
  ShortCut := CTyRichKeyAlignLeft;
end;

function TTyRichEditAlignCenter.AlignOf: TTyParaAlign;
begin
  Result := paraCenter;
end;

constructor TTyRichEditAlignCenter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActAlignCenter;
  Hint := rsRichActAlignCenterHint;
  ShortCut := CTyRichKeyAlignCenter;
end;

function TTyRichEditAlignRight.AlignOf: TTyParaAlign;
begin
  Result := paraRight;
end;

constructor TTyRichEditAlignRight.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActAlignRight;
  Hint := rsRichActAlignRightHint;
  ShortCut := CTyRichKeyAlignRight;
end;

function TTyRichEditAlignJustify.AlignOf: TTyParaAlign;
begin
  Result := paraJustify;
end;

constructor TTyRichEditAlignJustify.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActJustify;
  Hint := rsRichActJustifyHint;
  ShortCut := CTyRichKeyJustify;
end;

{ TTyRichEditListAction }

function TTyRichEditListAction.IsOn(AState: TTyRichEditActionState): Boolean;
begin
  Result := AState.Readable and (AState.Numbering = KindOf) and
    (cpaNumbering in AState.ParaConsistent);
end;

procedure TTyRichEditListAction.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatParagraphs;
  Checked := IsOn(AState);
end;

procedure TTyRichEditListAction.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  l: TTyListFormat;
begin
  // Paragraph.Numbering's write: the kind only, the indents a list item gets or gives back
  l := TyDefaultParaFormat.List;
  if IsOn(AState) then l.Kind := lkNone else l.Kind := KindOf;
  ARich.ApplyParagraphFormat([pffListKind, pffListIndents], TyRichListValue(l));
end;

function TTyRichEditBullets.KindOf: TTyListKind;
begin
  Result := lkBullet;
end;

constructor TTyRichEditBullets.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActBullets;
  Hint := rsRichActBulletsHint;
  ShortCut := CTyRichKeyBullets;
end;

function TTyRichEditNumbering.KindOf: TTyListKind;
begin
  Result := lkDecimal;
end;

constructor TTyRichEditNumbering.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActNumbering;
  Hint := rsRichActNumberingHint;
end;

{ TTyRichEditIndentAction }

procedure TTyRichEditIndentAction.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatParagraphs;
  Checked := False;
end;

procedure TTyRichEditIndentAction.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  f: TTyParaFormat;
  place, q: Integer;
begin
  if not AState.Readable then Exit;
  // list items all: a level deeper or shallower (Word's indent buttons on a list)
  if ARich.ChangeListLevel(Direction) then Exit;
  // where the caret paragraph's first line starts, and the step's place beyond it
  place := AState.CaretParagraph.LeftIndent + AState.CaretParagraph.FirstIndent;
  if Direction > 0 then
  begin
    if place < 0 then q := 0
    else q := (place div CTyRichIndentStep + 1) * CTyRichIndentStep;
  end
  else if place <= 0 then
    q := 0
  else
    q := ((place - 1) div CTyRichIndentStep) * CTyRichIndentStep;
  f := TyDefaultParaFormat;
  f.LeftIndent := q;
  f.FirstIndent := 0;
  ARich.ApplyParagraphFormat([pffStartIndent], f);
end;

function TTyRichEditIndentIncrease.Direction: Integer;
begin
  Result := 1;
end;

constructor TTyRichEditIndentIncrease.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActIndentIncrease;
  Hint := rsRichActIndentIncreaseHint;
end;

function TTyRichEditIndentDecrease.Direction: Integer;
begin
  Result := -1;
end;

constructor TTyRichEditIndentDecrease.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActIndentDecrease;
  Hint := rsRichActIndentDecreaseHint;
end;

{ TTyRichEditInsertPicture }

constructor TTyRichEditInsertPicture.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActInsertPicture;
  Hint := rsRichActInsertPictureHint;
  FDialog := TTyOpenPictureDialog.Create(Self);
  FDialog.Name := 'Dialog';
  FDialog.SetSubComponent(True);
  FDialog.Options := [ofFileMustExist];
end;

procedure TTyRichEditInsertPicture.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanInsertPicture;
  Checked := False;
end;

function TTyRichEditInsertPicture.AskFileName(var AFileName: string): Boolean;
begin
  if FDialog.Filter = '' then FDialog.Filter := TyRichPictureFilter;
  Result := FDialog.Execute;
  if Result then AFileName := FDialog.FileName;
end;

procedure TTyRichEditInsertPicture.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  picName: string;
begin
  // (no file is asked for where none can go: run by LCL, the action is disabled then)
  if not AState.CanInsertPicture then Exit;
  picName := '';
  if not AskFileName(picName) or (picName = '') then Exit;
  // (the dialog's own handlers ran: the rich edit may be gone)
  if (csDestroying in ARich.ComponentState) then Exit;
  ARich.InsertPictureFromFile(picName);
end;

{ TTyRichEditInsertTable }

constructor TTyRichEditInsertTable.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActInsertTable;
  Hint := rsRichActInsertTableHint;
  FRows := CTyRichDefaultTableSize;
  FColumns := CTyRichDefaultTableSize;
end;

procedure TTyRichEditInsertTable.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanInsertTable;
  Checked := False;
end;

procedure TTyRichEditInsertTable.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  nRows, nCols: Integer;
  go: Boolean;
begin
  if not AState.CanInsertTable then Exit;
  nRows := FRows;
  nCols := FColumns;
  go := True;
  if Assigned(FOnChooseSize) then FOnChooseSize(Self, nRows, nCols, go);
  if not go or (csDestroying in ARich.ComponentState) then Exit;
  ARich.InsertTable(nRows, nCols);
end;

{ ---- a table's formats and sizes ---- }

constructor TTyRichEditCellShading.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColor := clYellow;
  Caption := rsRichActCellShading;
  Hint := rsRichActCellShadingHint;
end;

procedure TTyRichEditCellShading.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCells;
  Checked := False;
end;

procedure TTyRichEditCellShading.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  if AState.CanFormatCells then ARich.SetCellShading(FColor);
end;

constructor TTyRichEditCellBorders.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := rbpAll;
  FLineStyle := rbsSingle;
  FLineWidth := 10;
  FLineColor := clDefault;
  Caption := rsRichActCellBorders;
  Hint := rsRichActCellBordersHint;
end;

procedure TTyRichEditCellBorders.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCells;
  Checked := False;
end;

procedure TTyRichEditCellBorders.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
var
  pr: TTyRichBorderPreset;
  b: TTyRichBorder;
  go: Boolean;
begin
  if not AState.CanFormatCells then Exit;
  pr := FPreset;
  b := TyRichBorder(FLineStyle, FLineWidth, FLineColor);
  go := True;
  if Assigned(FOnBeforeExecute) then FOnBeforeExecute(Self, pr, b, go);
  if not go or (csDestroying in ARich.ComponentState) then Exit;
  ARich.SetCellBorders(pr, b);
end;

constructor TTyRichEditCellPadding.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPadLeft := 108;
  FPadTop := 0;
  FPadRight := 108;
  FPadBottom := 0;
  Caption := rsRichActCellPadding;
  Hint := rsRichActCellPaddingHint;
end;

procedure TTyRichEditCellPadding.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCells;
  Checked := False;
end;

procedure TTyRichEditCellPadding.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  if AState.CanFormatCells then ARich.SetCellPadding(FPadLeft, FPadTop, FPadRight, FPadBottom);
end;

constructor TTyRichEditCellVAlign.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAlign := rcvTop;
  Caption := rsRichActCellVAlign;
  Hint := rsRichActCellVAlignHint;
end;

procedure TTyRichEditCellVAlign.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCells;
  Checked := False;
end;

procedure TTyRichEditCellVAlign.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  if AState.CanFormatCells then ARich.SetCellVAlign(FAlign);
end;

constructor TTyRichEditTableAlign.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAlign := rraCenter;
  Caption := rsRichActTableAlign;
  Hint := rsRichActTableAlignHint;
end;

procedure TTyRichEditTableAlign.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCells;
  Checked := False;
end;

procedure TTyRichEditTableAlign.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  if AState.CanFormatCells then ARich.SetTableAlign(FAlign, FIndent);
end;

constructor TTyRichEditTableProperties.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActTableProperties;
  Hint := rsRichActTablePropertiesHint;
end;

procedure TTyRichEditTableProperties.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCells;
  Checked := False;
end;

procedure TTyRichEditTableProperties.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
var
  v: TTyRichTableProperties;
  go: Boolean;
  pos: TTyRichPos;
  r, c: Integer;
  cp: TTyRichCellProps;
  rp: TTyRichRowProps;
  sd: TTyRowCellSide;
begin
  if not AState.CanFormatCells or not Assigned(FOnBeforeExecute) then Exit;
  if not ARich.CaretCell(pos, r, c) then Exit;
  // what the caret's cell, row and table have now
  cp := ARich.Document.CellProps(pos, r, c);
  rp := ARich.Document.RowProps(pos, r);
  v := Default(TTyRichTableProperties);
  v.Valid := [tpfRowHeight, tpfColumnWidth, tpfAlign, tpfPadding, tpfVAlign, tpfShading];
  v.RowHeight := Abs(rp.HeightTwips);
  v.RowExact := rp.HeightTwips < 0;
  v.ColumnWidth := cp.WidthTwips;
  v.Align := rp.Align;
  v.Indent := rp.LeftTwips;
  for sd := Low(TTyRowCellSide) to High(TTyRowCellSide) do v.Pad[sd] := cp.Pad[sd];
  v.VAlign := cp.VAlign;
  v.Shading := cp.Shading;
  go := True;
  FOnBeforeExecute(Self, v, go);
  if not go or (csDestroying in ARich.ComponentState) or (v.Valid = []) then Exit;
  // one undo step
  ARich.ApplyTableProperties(v);
end;

procedure TTyRichEditTableSizeAction.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  if KindOf = rskDistributeRows then Enabled := AState.CanResizeRows
  else Enabled := AState.CanResizeColumns;
  Checked := False;
end;

procedure TTyRichEditTableSizeAction.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  case KindOf of
    rskAutoFit: ARich.AutoFitColumn;
    rskDistributeColumns: ARich.DistributeColumns;
    rskDistributeRows: ARich.DistributeRows;
  else
    ARich.FitTableToWindow;
  end;
end;

function TTyRichEditAutoFitColumn.KindOf: TTyRichEditSizeKind;
begin
  Result := rskAutoFit;
end;

constructor TTyRichEditAutoFitColumn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActAutoFitColumn;
  Hint := rsRichActAutoFitColumnHint;
end;

function TTyRichEditDistributeColumns.KindOf: TTyRichEditSizeKind;
begin
  Result := rskDistributeColumns;
end;

constructor TTyRichEditDistributeColumns.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActDistributeColumns;
  Hint := rsRichActDistributeColumnsHint;
end;

function TTyRichEditDistributeRows.KindOf: TTyRichEditSizeKind;
begin
  Result := rskDistributeRows;
end;

constructor TTyRichEditDistributeRows.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActDistributeRows;
  Hint := rsRichActDistributeRowsHint;
end;

function TTyRichEditFitTableToWindow.KindOf: TTyRichEditSizeKind;
begin
  Result := rskFitWindow;
end;

constructor TTyRichEditFitTableToWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActFitTableToWindow;
  Hint := rsRichActFitTableToWindowHint;
end;

{ TTyRichEditInsertLink }

constructor TTyRichEditInsertLink.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActInsertLink;
  Hint := rsRichActInsertLinkHint;
end;

procedure TTyRichEditInsertLink.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanInsertLink or AState.CanEditLink;
  Checked := False;
end;

procedure TTyRichEditInsertLink.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  editing, go: Boolean;
  o, l: TTyRichPos;
  url, txt, given: string;
begin
  editing := AState.CanEditLink;
  if not editing and not AState.CanInsertLink then Exit;
  if not Assigned(FOnGetLink) then Exit;
  o := -1;
  l := 0;
  url := '';
  if editing then
  begin
    ARich.LinkAtSelection(o, l, url);
    // its text without its two marks
    given := ARich.RangeText(o + 1, l - 2);
  end
  else
    given := ARich.SelText;
  txt := given;
  go := True;
  FOnGetLink(Self, url, txt, go);
  // (the handler's own dialog ran: the rich edit may be gone)
  if not go or (url = '') or (csDestroying in ARich.ComponentState) then Exit;
  // a text left as it was: the text stays as it is, formats and all
  if txt = given then txt := '';
  if editing then ARich.SetLink(url, txt) else ARich.InsertLink(url, txt);
end;

{ TTyRichEditRemoveLink }

constructor TTyRichEditRemoveLink.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActRemoveLink;
  Hint := rsRichActRemoveLinkHint;
end;

procedure TTyRichEditRemoveLink.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanEditLink;
  Checked := False;
end;

procedure TTyRichEditRemoveLink.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  if not AState.CanEditLink then Exit;
  ARich.RemoveLink;
end;

{ TTyRichEditFind }

constructor TTyRichEditFind.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActFind;
  Hint := rsRichActFindHint;
  ShortCut := CTyRichKeyFind;
  FDialog := MakeDialog;
  FDialog.Name := 'Dialog';
  FDialog.SetSubComponent(True);
  // the search goes round the document's end: no scope to choose
  FDialog.Options := FDialog.Options + [frHideEntireScope];
  FDialog.OnFind := @DialogFind;
end;

function TTyRichEditFind.MakeDialog: TTyFindDialog;
begin
  Result := TTyFindDialog.Create(Self);
end;

procedure TTyRichEditFind.SetSearched(AValue: TTyCustomRichEdit);
begin
  if FSearched = AValue then Exit;
  if (FSearched <> nil) and (FSearched <> RichEdit) then FSearched.RemoveFreeNotification(Self);
  FSearched := AValue;
  if FSearched <> nil then FSearched.FreeNotification(Self);
end;

procedure TTyRichEditFind.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FSearched) then FSearched := nil;
end;

procedure TTyRichEditFind.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  // finding edits nothing: ReadOnly does not stop it (FindNext's rule)
  Enabled := ARich.IsEnabled;
  Checked := False;
end;

procedure TTyRichEditFind.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
var
  s: string;
begin
  SetSearched(ARich);
  // a short selection on one line is what the user looks for, as in Notepad
  if (ARich.SelLength > 0) and (ARich.SelLength <= 128) then
  begin
    s := ARich.SelText;
    if (s <> '') and (Pos(#13, s) = 0) and (Pos(#10, s) = 0) and (Pos(#11, s) = 0) then
      FDialog.FindText := s;
  end;
  ShowDialog;
end;

procedure TTyRichEditFind.ShowDialog;
begin
  FDialog.Execute;
end;

function TTyRichEditFind.SearchOptions: TTyRichFindOptions;
begin
  Result := [rfoWrap];
  if frMatchCase in FDialog.Options then Include(Result, rfoMatchCase);
  if frWholeWord in FDialog.Options then Include(Result, rfoWholeWord);
  if not (frDown in FDialog.Options) then Include(Result, rfoBackward);
end;

procedure TTyRichEditFind.NotFound(const AText: string);
begin
  if Assigned(FOnNotFound) then FOnNotFound(Self, AText)
  else ShowNotFound(AText);
end;

procedure TTyRichEditFind.ShowNotFound(const AText: string);
begin
  TyShowMessage(Format(rsRichActNotFound, [AText]));
end;

function TTyRichEditFind.FindAgain: Boolean;
var
  s: string;
begin
  Result := False;
  s := FDialog.FindText;
  if (FSearched = nil) or (s = '') or (csDestroying in FSearched.ComponentState) then Exit;
  Result := FSearched.FindNext(s, SearchOptions);
  if not Result then NotFound(s);
end;

procedure TTyRichEditFind.DialogFind(Sender: TObject);
begin
  FindAgain;
end;

{ TTyRichEditReplace }

constructor TTyRichEditReplace.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActReplace;
  Hint := rsRichActReplaceHint;
  ShortCut := CTyRichKeyReplace;
  TTyReplaceDialog(FDialog).OnReplace := @DialogReplace;
end;

function TTyRichEditReplace.MakeDialog: TTyFindDialog;
begin
  Result := TTyReplaceDialog.Create(Self);
end;

function TTyRichEditReplace.GetReplaceDialog: TTyReplaceDialog;
begin
  Result := TTyReplaceDialog(FDialog);
end;

{ The user may edit the text: what the control's door asks before any edit of the user's
  (not ReadOnly, enabled, the document taking edits) - the replace methods are the document
  API and do not ask it themselves. }
function UserMayEdit(ARich: TTyCustomRichEdit): Boolean;
begin
  Result := not ARich.ReadOnly and ARich.IsEnabled and not ARich.Document.Updating and
    not ARich.Document.Loading and not ARich.Document.Incomplete and not ARich.Document.Saving;
end;

procedure TTyRichEditReplace.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := UserMayEdit(ARich);
  Checked := False;
end;

procedure TTyRichEditReplace.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  if not UserMayEdit(ARich) then Exit;
  inherited ExecuteOn(ARich, AState);
end;

procedure TTyRichEditReplace.DialogReplace(Sender: TObject);
var
  r: TTyCustomRichEdit;
  s, w: string;
  start, len: TTyRichPos;
  n: Integer;
  so: TTySearchOptions;
  done: TTyRichReplaceResult;
begin
  r := FSearched;
  s := FDialog.FindText;
  if (r = nil) or (s = '') or (csDestroying in r.ComponentState) then Exit;
  w := ReplaceDialog.ReplaceText;
  // the replace methods are the document API: they replace only where the user may edit
  if not UserMayEdit(r) then Exit;
  if frReplaceAll in FDialog.Options then
  begin
    n := r.ReplaceAll(s, w, SearchOptions - [rfoWrap, rfoBackward]);
    if Assigned(FOnReplaced) then FOnReplaced(Self, n);
    if n = 0 then NotFound(s);
    Exit;
  end;
  // the selection a match of the search: it is replaced, then the next one found
  start := 0;
  len := 0;
  so := [];
  if frMatchCase in FDialog.Options then Include(so, soMatchCase);
  if frWholeWord in FDialog.Options then Include(so, soWholeWord);
  if r.HasSelection and r.Search(s, r.SelStart, r.SelLength, so, start, len) and
    (start = r.SelStart) and (len = r.SelLength) then
  begin
    // the one match as ReplaceAll replaces it: one step, a match it may not change kept as it is
    r.ReplaceAll(s, w, SearchOptions - [rfoWrap, rfoBackward], start, len, done);
  end;
  FindAgain;
end;

{ TTyRichEditUndo / TTyRichEditRedo }

constructor TTyRichEditUndo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActUndo;
  Hint := rsRichActUndoHint;
  ShortCut := CTyRichKeyUndo;
end;

procedure TTyRichEditUndo.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := ARich.CanUndo;
  Checked := False;
end;

procedure TTyRichEditUndo.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  ARich.Undo;
end;

constructor TTyRichEditRedo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActRedo;
  Hint := rsRichActRedoHint;
  ShortCut := CTyRichKeyRedo;
end;

procedure TTyRichEditRedo.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := ARich.CanRedo;
  Checked := False;
end;

procedure TTyRichEditRedo.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  ARich.Redo;
end;

{ Zoom }

constructor TTyRichEditZoomIn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActZoomIn;
  Hint := rsRichActZoomInHint;
  ShortCut := CTyRichKeyZoomIn;
  SecondaryShortCuts.Add(ShortCutToText($4000 + VK_ADD));
end;

procedure TTyRichEditZoomIn.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := ARich.Zoom < CRichZoomMax;
  Checked := False;
end;

procedure TTyRichEditZoomIn.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  ARich.Zoom := ARich.Zoom + CRichZoomStep;
end;

constructor TTyRichEditZoomOut.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActZoomOut;
  Hint := rsRichActZoomOutHint;
  ShortCut := CTyRichKeyZoomOut;
  SecondaryShortCuts.Add(ShortCutToText($4000 + VK_SUBTRACT));
end;

procedure TTyRichEditZoomOut.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := ARich.Zoom > CRichZoomMin;
  Checked := False;
end;

procedure TTyRichEditZoomOut.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  ARich.Zoom := ARich.Zoom - CRichZoomStep;
end;

constructor TTyRichEditZoomReset.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActZoomReset;
  Hint := rsRichActZoomResetHint;
  ShortCut := CTyRichKeyZoomReset;
  SecondaryShortCuts.Add(ShortCutToText($4000 + VK_NUMPAD0));
end;

procedure TTyRichEditZoomReset.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := True;
  Checked := ARich.Zoom = 100;
end;

procedure TTyRichEditZoomReset.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  ARich.Zoom := 100;
end;

{ ---- the clipboard and the selection ---- }

constructor TTyRichEditCut.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActCut;
  Hint := rsRichActCutHint;
  ShortCut := CTyRichKeyCut;
end;

procedure TTyRichEditCut.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  // the text menu's answer for Cut
  Enabled := ARich.TeHasSelection and not ARich.TeIsReadOnly;
  Checked := False;
end;

procedure TTyRichEditCut.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  ARich.CutToClipboard;
end;

constructor TTyRichEditCopy.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActCopy;
  Hint := rsRichActCopyHint;
  ShortCut := CTyRichKeyCopy;
end;

procedure TTyRichEditCopy.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := ARich.TeHasSelection;
  Checked := False;
end;

procedure TTyRichEditCopy.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  ARich.CopyToClipboard;
end;

constructor TTyRichEditPaste.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActPaste;
  Hint := rsRichActPasteHint;
  ShortCut := CTyRichKeyPaste;
end;

procedure TTyRichEditPaste.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := ARich.CanPaste;
  Checked := False;
end;

procedure TTyRichEditPaste.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  ARich.PasteFromClipboard;
end;

constructor TTyRichEditSelectAll.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActSelectAll;
  Hint := rsRichActSelectAllHint;
  ShortCut := CTyRichKeySelectAll;
end;

procedure TTyRichEditSelectAll.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := ARich.TeHasText;
  Checked := False;
end;

procedure TTyRichEditSelectAll.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  ARich.SelectAll;
end;

constructor TTyRichEditDelete.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActDelete;
  Hint := rsRichActDeleteHint;
end;

procedure TTyRichEditDelete.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := ARich.TeHasSelection and not ARich.TeIsReadOnly;
  Checked := False;
end;

procedure TTyRichEditDelete.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  ARich.ClearSelection;
end;

{ ---- colours ---- }

procedure TTyRichEditColorAction.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  c: TColor;
  go: Boolean;
  m: TTyCharFormatMask;
  f: TTyCharFormat;
begin
  if not AState.CanFormatCharacters then Exit;
  c := FColor;
  go := True;
  if Assigned(FOnChooseColor) then FOnChooseColor(Self, c, go);
  if not go or (csDestroying in ARich.ComponentState) then Exit;
  // the chosen colour is the action's from now on (a button shows it, the next click applies it)
  FColor := c;
  FormatOf(c, m, f);
  AState.Changed;
  ARich.ApplyCharacterFormat(m, f);
end;

constructor TTyRichEditTextColor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActTextColor;
  Hint := rsRichActTextColorHint;
  FColor := CTyRichDefaultTextColor;
end;

procedure TTyRichEditTextColor.FormatOf(AColor: TColor; out AMask: TTyCharFormatMask;
  out AValue: TTyCharFormat);
begin
  AMask := [cffColor];
  AValue := TyDefaultCharFormat;
  AValue.Color := TyRichTextColorIn(AColor);
end;

constructor TTyRichEditHighlightColor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActHighlightColor;
  Hint := rsRichActHighlightColorHint;
  FColor := CTyRichDefaultHighlight;
end;

procedure TTyRichEditHighlightColor.FormatOf(AColor: TColor; out AMask: TTyCharFormatMask;
  out AValue: TTyCharFormat);
begin
  AMask := [cffHighlight];
  AValue := TyDefaultCharFormat;
  AValue.HighlightColor := TyRichBackColorIn(AColor);
end;

{ ---- the font ---- }

constructor TTyRichEditFontName.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActFontName;
  Hint := rsRichActFontNameHint;
end;

procedure TTyRichEditFontName.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCharacters;
  Checked := AState.Readable and (caFace in AState.CharConsistent) and (FFontName <> '') and
    SameText(AState.FontName, FFontName);
end;

procedure TTyRichEditFontName.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  f.FontName := TyRichFontNameIn(FFontName);
  AState.Changed;
  ARich.ApplyCharacterFormat([cffFontName], f);
end;

constructor TTyRichEditFontSize.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActFontSize;
  Hint := rsRichActFontSizeHint;
  FSize := CTyRichDefaultFontSize;
end;

procedure TTyRichEditFontSize.UpdateOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCharacters and (FSize > 0);
  Checked := AState.Readable and (caSize in AState.CharConsistent) and (AState.FontSize = FSize);
end;

procedure TTyRichEditFontSize.ExecuteOn(ARich: TTyCustomRichEdit; AState: TTyRichEditActionState);
var
  f: TTyCharFormat;
begin
  if FSize <= 0 then Exit;
  f := TyDefaultCharFormat;
  f.SizeHalfPt := FSize * 2;
  AState.Changed;
  ARich.ApplyCharacterFormat([cffSize], f);
end;

{ The next size on the scale beyond APoints in ADirection; 0 past its end. }
function NextFontSize(APoints, ADirection: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  if ADirection > 0 then
  begin
    for i := 0 to High(CTyRichFontSizes) do
      if CTyRichFontSizes[i] > APoints then Exit(CTyRichFontSizes[i]);
  end
  else
    for i := High(CTyRichFontSizes) downto 0 do
      if CTyRichFontSizes[i] < APoints then Exit(CTyRichFontSizes[i]);
end;

procedure TTyRichEditFontStepAction.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatCharacters and AState.Readable and
    (NextFontSize(AState.FontSize, Direction) > 0);
  Checked := False;
end;

procedure TTyRichEditFontStepAction.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  f: TTyCharFormat;
  n: Integer;
begin
  if not AState.Readable then Exit;
  n := NextFontSize(AState.FontSize, Direction);
  if n <= 0 then Exit;
  f := TyDefaultCharFormat;
  f.SizeHalfPt := n * 2;
  AState.Changed;
  ARich.ApplyCharacterFormat([cffSize], f);
end;

function TTyRichEditFontGrow.Direction: Integer;
begin
  Result := 1;
end;

constructor TTyRichEditFontGrow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActFontGrow;
  Hint := rsRichActFontGrowHint;
  ShortCut := CTyRichKeyFontGrow;
end;

function TTyRichEditFontShrink.Direction: Integer;
begin
  Result := -1;
end;

constructor TTyRichEditFontShrink.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActFontShrink;
  Hint := rsRichActFontShrinkHint;
  ShortCut := CTyRichKeyFontShrink;
end;

constructor TTyRichEditClearFormat.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActClearFormat;
  Hint := rsRichActClearFormatHint;
  ShortCut := CTyRichKeyClearFormat;
end;

procedure TTyRichEditClearFormat.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  // the default character format: no name, no size, no style, automatic colour, no highlight
  AState.Changed;
  ARich.ApplyCharacterFormat([cffFontName, cffCharset, cffSize, cffBold, cffItalic,
    cffUnderline, cffStrike, cffVertAlign, cffColor, cffHighlight], TyDefaultCharFormat);
end;

constructor TTyRichEditLineSpacing.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActLineSpacing;
  Hint := rsRichActLineSpacingHint;
  FSpacing := lsSingle;
end;

function TTyRichEditLineSpacing.IsMultipleStored: Boolean;
begin
  Result := FMultiple <> 0;
end;

procedure TTyRichEditLineSpacing.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatParagraphs;
  // a multiple: the same to a 240th, as the document keeps it
  if FMultiple > 0 then
    Checked := AState.Readable and (AState.LineMultiple > 0) and
      (Round(AState.LineMultiple * 240) = Round(FMultiple * 240))
  else
    Checked := AState.Readable and (AState.LineSpacing = FSpacing);
end;

procedure TTyRichEditLineSpacing.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  if FMultiple > 0 then TyRichSetLineMultiple(f, FMultiple)
  else f.LineSpacing := FSpacing;
  ARich.ApplyParagraphFormat([pffSpacingRule], f);
end;

{ TTyRichEditParagraphSpacing }

constructor TTyRichEditParagraphSpacing.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActParaSpacing;
  Hint := rsRichActParaSpacingHint;
  FBefore := -1;
  FAfter := -1;
end;

function TTyRichEditParagraphSpacing.IsBeforeStored: Boolean;
begin
  Result := FBefore <> -1;
end;

function TTyRichEditParagraphSpacing.IsAfterStored: Boolean;
begin
  Result := FAfter <> -1;
end;

procedure TTyRichEditParagraphSpacing.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  Enabled := AState.CanFormatParagraphs and ((FBefore >= 0) or (FAfter >= 0));
  // to the twip, as the action writes it and the paragraph reports it
  Checked := AState.Readable and ((FBefore >= 0) or (FAfter >= 0)) and
    ((FBefore < 0) or (TyRichPtToTwips(AState.SpaceBefore) = TyRichPtToTwips(FBefore))) and
    ((FAfter < 0) or (TyRichPtToTwips(AState.SpaceAfter) = TyRichPtToTwips(FAfter)));
end;

procedure TTyRichEditParagraphSpacing.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
var
  f: TTyParaFormat;
  m: TTyParaFormatMask;
begin
  f := TyDefaultParaFormat;
  m := [];
  if FBefore >= 0 then
  begin
    Include(m, pffSpaceBefore);
    f.SpaceBefore := TyRichPtToTwips(FBefore);
  end;
  if FAfter >= 0 then
  begin
    Include(m, pffSpaceAfter);
    f.SpaceAfter := TyRichPtToTwips(FAfter);
  end;
  if m <> [] then ARich.ApplyParagraphFormat(m, f);
end;

{ ---- tables ---- }

procedure TTyRichEditTableAction.UpdateOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  case KindOf of
    rtkRowAbove, rtkRowBelow: Enabled := AState.CanInsertRow;
    rtkColumnLeft, rtkColumnRight: Enabled := AState.CanInsertColumn;
    rtkDeleteRow: Enabled := AState.CanDeleteRow;
    rtkDeleteColumn: Enabled := AState.CanDeleteColumn;
  else
    Enabled := AState.CanDeleteTable;
  end;
  Checked := False;
end;

procedure TTyRichEditTableAction.ExecuteOn(ARich: TTyCustomRichEdit;
  AState: TTyRichEditActionState);
begin
  case KindOf of
    rtkRowAbove: ARich.InsertRow(False);
    rtkRowBelow: ARich.InsertRow(True);
    rtkColumnLeft: ARich.InsertColumn(False);
    rtkColumnRight: ARich.InsertColumn(True);
    rtkDeleteRow: ARich.DeleteRow;
    rtkDeleteColumn: ARich.DeleteColumn;
  else
    ARich.DeleteTable;
  end;
end;

function TTyRichEditInsertRowAbove.KindOf: TTyRichEditTableKind;
begin
  Result := rtkRowAbove;
end;

constructor TTyRichEditInsertRowAbove.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActRowAbove;
  Hint := rsRichActRowAboveHint;
end;

function TTyRichEditInsertRowBelow.KindOf: TTyRichEditTableKind;
begin
  Result := rtkRowBelow;
end;

constructor TTyRichEditInsertRowBelow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActRowBelow;
  Hint := rsRichActRowBelowHint;
end;

function TTyRichEditInsertColumnLeft.KindOf: TTyRichEditTableKind;
begin
  Result := rtkColumnLeft;
end;

constructor TTyRichEditInsertColumnLeft.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActColumnLeft;
  Hint := rsRichActColumnLeftHint;
end;

function TTyRichEditInsertColumnRight.KindOf: TTyRichEditTableKind;
begin
  Result := rtkColumnRight;
end;

constructor TTyRichEditInsertColumnRight.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActColumnRight;
  Hint := rsRichActColumnRightHint;
end;

function TTyRichEditDeleteRow.KindOf: TTyRichEditTableKind;
begin
  Result := rtkDeleteRow;
end;

constructor TTyRichEditDeleteRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActDeleteRow;
  Hint := rsRichActDeleteRowHint;
end;

function TTyRichEditDeleteColumn.KindOf: TTyRichEditTableKind;
begin
  Result := rtkDeleteColumn;
end;

constructor TTyRichEditDeleteColumn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActDeleteColumn;
  Hint := rsRichActDeleteColumnHint;
end;

function TTyRichEditDeleteTable.KindOf: TTyRichEditTableKind;
begin
  Result := rtkDeleteTable;
end;

constructor TTyRichEditDeleteTable.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := rsRichActDeleteTable;
  Hint := rsRichActDeleteTableHint;
end;

end.
