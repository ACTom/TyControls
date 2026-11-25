unit umain;

{ TTyRichEdit as a small word processor (a self-drawn TTyForm with its title bar and menu bar):
  - two tool bars and the menus are made of tyControls.RichEdit.Actions - the clipboard, undo
    and redo, find and replace, a picture and a table, zoom; the font, its size and its
    colours, the character styles, clearing them; alignment, lists, indent, line spacing; the
    table's rows and columns - each action's Enabled and Checked are the rich edit's own
    answers, its run one undo step through the rich edit's door for the user;
  - the font box and the size box show the selection's font and size (empty when it has
    several) and apply what is chosen or typed; they are refreshed when the application is
    idle after the rich edit changed (the record the actions read), never per key;
  - the colour buttons apply their colour with a click; the swatch beside each opens the
    package's colour dialog;
  - a TTyRichEditRuler above the text shows the paragraph's indents and tab stops, and
    dragging them formats the paragraphs;
  - the Table menu, grouped as Word groups it: Insert (a table, rows, columns), Delete (the
    table, columns, rows, the cells' contents), Select (the table, a column, a row, a cell),
    Merge Cells and Split Cells... (usplitform asks the columns and rows: 2 x 1, or what a
    merged cell covers, to split it back),
    AutoFit (a column to its contents, the table to the window, rows and columns evenly), the
    cells' vertical alignment, the table's alignment, the ten border presets, the shading and
    Table Properties (utableform: a form of the example's own that the action asks through its
    OnBeforeExecute); the tool bar's second row has a borders drop-down that keeps the preset
    used last and a shading button with its colour swatch, like the highlight's;
  - the editor's context menu: cut, copy, paste, select all, and in a table the table's
    commands (select, insert, delete, cell alignment, autofit, table properties) - each enabled
    as the tool bar's are, by the control's own answers;
  - the status bar shows what the rich edit refused (OnEditRefused: never a dialog), what was
    not found, what is selected in a table ("2 × 3 cells", "Row 4"), the line and column of the
    caret, the zoom, and a large file's load;
  - File opens and saves RTF and plain text through the package's file dialogs; Samples opens
    a few documents kept in samples/ (Chinese text and its formats, pictures, Word's table of
    contents with its links) - read from a stream, so Save asks for a new name - and a table
    built from code (utablesample, the documentation's example);
  - a click on a link (Word's table of contents has many) shows its address in the status bar;
    a place in the document (#name) is gone to by the rich edit itself, a web or mail address
    opens in the system's handler, any other target is only shown;
  - Insert > Link and Edit > Edit Link ask in a small form (ulinkform: the address, the text,
    or one of the document's bookmarks); Insert > Bookmark lists, adds, deletes, renames and
    goes to the bookmarks (ubookmarkform); a double click on a picture shows it at its own
    size (uviewerform);
  - Format > Line Spacing takes any multiple (1.08, 3), Paragraph Spacing the space before
    and after (0, 6, 12 pt);
  - Samples > A Page Built from Code opens upageform: a page made entirely with the builder
    (upagesample), shown as a help page and as a home page;
  - View: zoom, wrap mode, read only, plain text, the ruler, the skins and their dark mode.
  The window, the menus, the tool bars and the actions are in umain.lfm; the code here is the
  application's part: files, the boxes and swatches, the status bar, the skin menu. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, LCLIntf, LCLType, Forms, Controls, Graphics, Dialogs, Menus,
  ActnList, tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Menu,
  tyControls.ToolBar, tyControls.GlyphButtons, tyControls.IconFont, tyControls.Icons.Lucide,
  tyControls.ComboBox, tyControls.FontComboBox, tyControls.FontSizeComboBox,
  tyControls.ColorButton, tyControls.StatusBar, tyControls.Dialogs, tyControls.Dialogs.Color,
  tyControls.Dialogs.FileDialog, tyControls.RichEdit.Model, tyControls.RichEdit.Attrs,
  tyControls.RichEdit.Text, tyControls.RichEdit.Layout, tyControls.RichEdit.Grid,
  tyControls.ImageCollection,
  tyControls.RichEdit, tyControls.RichEdit.Ruler, tyControls.RichEdit.Actions,
  ulinkform, ubookmarkform, uviewerform, upageform, utableform, utablesample, usplitform;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    MainMenuBar: TTyMenuBar;
    ToolsStd: TTyToolBar;
    BtnNew: TTySpeedButton;
    BtnOpen: TTySpeedButton;
    BtnSave: TTySpeedButton;
    Sep1: TTyToolSeparator;
    BtnCut: TTySpeedButton;
    BtnCopy: TTySpeedButton;
    BtnPaste: TTySpeedButton;
    Sep2: TTyToolSeparator;
    BtnUndo: TTySpeedButton;
    BtnRedo: TTySpeedButton;
    Sep3: TTyToolSeparator;
    BtnFind: TTySpeedButton;
    BtnReplace: TTySpeedButton;
    Sep4: TTyToolSeparator;
    BtnInsertPicture: TTySpeedButton;
    BtnInsertTable: TTySpeedButton;
    Sep5: TTyToolSeparator;
    BtnZoomOut: TTySpeedButton;
    BtnZoomIn: TTySpeedButton;
    ToolsFmt: TTyToolBar;
    FontBox: TTyFontComboBox;
    SizeBox: TTyFontSizeComboBox;
    Sep6: TTyToolSeparator;
    BtnBold: TTySpeedButton;
    BtnItalic: TTySpeedButton;
    BtnUnderline: TTySpeedButton;
    BtnStrikeOut: TTySpeedButton;
    BtnSuperscript: TTySpeedButton;
    BtnSubscript: TTySpeedButton;
    Sep7: TTyToolSeparator;
    BtnTextColor: TTySpeedButton;
    TextSwatch: TTyColorButton;
    BtnHighlight: TTySpeedButton;
    HighlightSwatch: TTyColorButton;
    Sep8: TTyToolSeparator;
    BtnAlignLeft: TTySpeedButton;
    BtnAlignCenter: TTySpeedButton;
    BtnAlignRight: TTySpeedButton;
    BtnJustify: TTySpeedButton;
    Sep9: TTyToolSeparator;
    BtnBullets: TTySpeedButton;
    BtnNumbering: TTySpeedButton;
    BtnIndentDecrease: TTySpeedButton;
    BtnIndentIncrease: TTySpeedButton;
    Sep10: TTyToolSeparator;
    Sep11: TTyToolSeparator;
    BtnSpacing: TTyToolButton;
    BtnClearFormat: TTySpeedButton;
    Ruler: TTyRichEditRuler;
    Status: TTyStatusBar;
    Editor: TTyRichEdit;
    LucideFont: TTyLucideIconFont;
    DlgOpen: TTyOpenDialog;
    DlgSave: TTySaveDialog;
    Actions: TActionList;
    ActNew: TAction;
    ActOpen: TAction;
    ActSave: TAction;
    ActSaveAs: TAction;
    ActExit: TAction;
    ActTextAuto: TAction;
    ActTextChoose: TAction;
    ActHighlightNone: TAction;
    ActHighlightChoose: TAction;
    ActReadOnly: TAction;
    ActPlainText: TAction;
    ActShowRuler: TAction;
    ActCut: TTyRichEditCut;
    ActCopy: TTyRichEditCopy;
    ActPaste: TTyRichEditPaste;
    ActSelectAll: TTyRichEditSelectAll;
    ActDelete: TTyRichEditDelete;
    ActUndo: TTyRichEditUndo;
    ActRedo: TTyRichEditRedo;
    ActFind: TTyRichEditFind;
    ActReplace: TTyRichEditReplace;
    ActInsertPicture: TTyRichEditInsertPicture;
    ActInsertTable: TTyRichEditInsertTable;
    ActZoomIn: TTyRichEditZoomIn;
    ActZoomOut: TTyRichEditZoomOut;
    ActZoomReset: TTyRichEditZoomReset;
    ActBold: TTyRichEditBold;
    ActItalic: TTyRichEditItalic;
    ActUnderline: TTyRichEditUnderline;
    ActStrikeOut: TTyRichEditStrikeOut;
    ActSuperscript: TTyRichEditSuperscript;
    ActSubscript: TTyRichEditSubscript;
    ActTextColor: TTyRichEditTextColor;
    ActHighlight: TTyRichEditHighlightColor;
    ActFontGrow: TTyRichEditFontGrow;
    ActFontShrink: TTyRichEditFontShrink;
    ActClearFormat: TTyRichEditClearFormat;
    ActAlignLeft: TTyRichEditAlignLeft;
    ActAlignCenter: TTyRichEditAlignCenter;
    ActAlignRight: TTyRichEditAlignRight;
    ActJustify: TTyRichEditAlignJustify;
    ActBullets: TTyRichEditBullets;
    ActNumbering: TTyRichEditNumbering;
    ActIndentIncrease: TTyRichEditIndentIncrease;
    ActIndentDecrease: TTyRichEditIndentDecrease;
    ActSpacing1: TTyRichEditLineSpacing;
    ActSpacing15: TTyRichEditLineSpacing;
    ActSpacing2: TTyRichEditLineSpacing;
    ActSize8: TTyRichEditFontSize;
    ActSize10: TTyRichEditFontSize;
    ActSize12: TTyRichEditFontSize;
    ActSize14: TTyRichEditFontSize;
    ActSize18: TTyRichEditFontSize;
    ActSize24: TTyRichEditFontSize;
    ActSize36: TTyRichEditFontSize;
    ActRowAbove: TTyRichEditInsertRowAbove;
    ActRowBelow: TTyRichEditInsertRowBelow;
    ActColumnLeft: TTyRichEditInsertColumnLeft;
    ActColumnRight: TTyRichEditInsertColumnRight;
    ActDeleteRow: TTyRichEditDeleteRow;
    ActDeleteColumn: TTyRichEditDeleteColumn;
    ActDeleteTable: TTyRichEditDeleteTable;
    MainMenu1: TMainMenu;
    MnuFile: TMenuItem;
    MnuNew: TMenuItem;
    MnuOpen: TMenuItem;
    MnuSave: TMenuItem;
    MnuSaveAs: TMenuItem;
    MnuSep1: TMenuItem;
    MnuSamples: TMenuItem;
    MnuSampleFormats: TMenuItem;
    MnuSampleTable: TMenuItem;
    MnuSamplePictures: TMenuItem;
    MnuSampleToc: TMenuItem;
    MnuSep2: TMenuItem;
    MnuExit: TMenuItem;
    MnuEdit: TMenuItem;
    MnuUndo: TMenuItem;
    MnuRedo: TMenuItem;
    MnuSep3: TMenuItem;
    MnuCut: TMenuItem;
    MnuCopy: TMenuItem;
    MnuPaste: TMenuItem;
    MnuDelete: TMenuItem;
    MnuSep4: TMenuItem;
    MnuSelectAll: TMenuItem;
    MnuSep5: TMenuItem;
    MnuFind: TMenuItem;
    MnuReplace: TMenuItem;
    MnuFormat: TMenuItem;
    MnuFontSize: TMenuItem;
    MnuSize8: TMenuItem;
    MnuSize10: TMenuItem;
    MnuSize12: TMenuItem;
    MnuSize14: TMenuItem;
    MnuSize18: TMenuItem;
    MnuSize24: TMenuItem;
    MnuSize36: TMenuItem;
    MnuFontGrow: TMenuItem;
    MnuFontShrink: TMenuItem;
    MnuSep6: TMenuItem;
    MnuBold: TMenuItem;
    MnuItalic: TMenuItem;
    MnuUnderline: TMenuItem;
    MnuStrikeOut: TMenuItem;
    MnuSuperscript: TMenuItem;
    MnuSubscript: TMenuItem;
    MnuSep7: TMenuItem;
    MnuTextColorMenu: TMenuItem;
    MnuTextColor: TMenuItem;
    MnuTextAuto: TMenuItem;
    MnuTextChoose: TMenuItem;
    MnuHighlightMenu: TMenuItem;
    MnuHighlight: TMenuItem;
    MnuHighlightNone: TMenuItem;
    MnuHighlightChoose: TMenuItem;
    MnuClearFormat: TMenuItem;
    MnuSep8: TMenuItem;
    MnuAlignLeft: TMenuItem;
    MnuAlignCenter: TMenuItem;
    MnuAlignRight: TMenuItem;
    MnuJustify: TMenuItem;
    MnuSep9: TMenuItem;
    MnuBullets: TMenuItem;
    MnuNumbering: TMenuItem;
    MnuIndentIncrease: TMenuItem;
    MnuIndentDecrease: TMenuItem;
    MnuSep10: TMenuItem;
    MnuLineSpacing: TMenuItem;
    MnuSpacing1: TMenuItem;
    MnuSpacing15: TMenuItem;
    MnuSpacing2: TMenuItem;
    MnuInsert: TMenuItem;
    MnuInsertPicture: TMenuItem;
    MnuInsertTable: TMenuItem;
    MnuTable: TMenuItem;
    MnuRowAbove: TMenuItem;
    MnuRowBelow: TMenuItem;
    MnuColumnLeft: TMenuItem;
    MnuColumnRight: TMenuItem;
    MnuDeleteRow: TMenuItem;
    MnuDeleteColumn: TMenuItem;
    MnuDeleteTable: TMenuItem;
    MnuView: TMenuItem;
    MnuZoomIn: TMenuItem;
    MnuZoomOut: TMenuItem;
    MnuZoomReset: TMenuItem;
    MnuSep12: TMenuItem;
    MnuWrap: TMenuItem;
    MnuWrapWindow: TMenuItem;
    MnuWrapPage: TMenuItem;
    MnuWrapNone: TMenuItem;
    MnuReadOnly: TMenuItem;
    MnuPlainText: TMenuItem;
    MnuShowRuler: TMenuItem;
    MnuSep13: TMenuItem;
    MnuSkin: TMenuItem;
    MnuDark: TMenuItem;
    PopSpacing: TTyPopupMenu;
    PopItemSpacing1: TMenuItem;
    PopItemSpacing15: TMenuItem;
    PopItemSpacing2: TMenuItem;
    PopEditor: TTyPopupMenu;
    PopCut: TMenuItem;
    PopCopy: TMenuItem;
    PopPaste: TMenuItem;
    MnuSep14: TMenuItem;
    PopSelectAll: TMenuItem;
    PopSepTable: TMenuItem;
    PopRowAbove: TMenuItem;
    PopRowBelow: TMenuItem;
    PopColumnLeft: TMenuItem;
    PopColumnRight: TMenuItem;
    PopDeleteRow: TMenuItem;
    PopDeleteColumn: TMenuItem;
    PopDeleteTable: TMenuItem;
    MnuSepSamples: TMenuItem;
    MnuSamplePage: TMenuItem;
    BtnInsertLink: TTySpeedButton;
    ActSpacing108: TTyRichEditLineSpacing;
    ActSpacing115: TTyRichEditLineSpacing;
    ActSpacing3: TTyRichEditLineSpacing;
    ActBefore0: TTyRichEditParagraphSpacing;
    ActBefore6: TTyRichEditParagraphSpacing;
    ActBefore12: TTyRichEditParagraphSpacing;
    ActAfter0: TTyRichEditParagraphSpacing;
    ActAfter6: TTyRichEditParagraphSpacing;
    ActAfter12: TTyRichEditParagraphSpacing;
    ActInsertLink: TTyRichEditInsertLink;
    ActEditLink: TAction;
    ActRemoveLink: TTyRichEditRemoveLink;
    ActBookmarks: TAction;
    MnuSepLink: TMenuItem;
    MnuEditLink: TMenuItem;
    MnuRemoveLink: TMenuItem;
    MnuSpacing108: TMenuItem;
    MnuSpacing115: TMenuItem;
    MnuSpacing3: TMenuItem;
    MnuParaSpacing: TMenuItem;
    MnuBefore0: TMenuItem;
    MnuBefore6: TMenuItem;
    MnuBefore12: TMenuItem;
    MnuSepSpace: TMenuItem;
    MnuAfter0: TMenuItem;
    MnuAfter6: TMenuItem;
    MnuAfter12: TMenuItem;
    MnuSepInsert: TMenuItem;
    MnuInsertLink: TMenuItem;
    MnuInsertBookmark: TMenuItem;
    PopItemSpacing108: TMenuItem;
    PopItemSpacing115: TMenuItem;
    PopItemSpacing3: TMenuItem;
    PopSepSpace: TMenuItem;
    PopItemBefore0: TMenuItem;
    PopItemBefore12: TMenuItem;
    PopItemAfter0: TMenuItem;
    PopItemAfter12: TMenuItem;
    PopSepLink: TMenuItem;
    PopInsertLink: TMenuItem;
    PopEditLink: TMenuItem;
    PopRemoveLink: TMenuItem;
    Sep12: TTyToolSeparator;
    BtnBorders: TTyToolButton;
    BtnShading: TTySpeedButton;
    ShadingSwatch: TTyColorButton;
    BtnMergeCells: TTySpeedButton;
    BtnSplitCell: TTySpeedButton;
    ActMergeCells: TTyRichEditMergeCells;
    ActSplitCell: TTyRichEditSplitCell;
    MnuSepMerge: TMenuItem;
    MnuMergeCells: TMenuItem;
    MnuSplitCell: TMenuItem;
    PopMergeCells: TMenuItem;
    PopSplitCell: TMenuItem;
    ActSelectCell: TTyRichEditSelectCell;
    ActSelectRow: TTyRichEditSelectRow;
    ActSelectColumn: TTyRichEditSelectColumn;
    ActSelectTable: TTyRichEditSelectTable;
    ActClearCells: TTyRichEditClearCells;
    ActAutoFit: TTyRichEditAutoFitColumn;
    ActFitWindow: TTyRichEditFitTableToWindow;
    ActDistributeRows: TTyRichEditDistributeRows;
    ActDistributeColumns: TTyRichEditDistributeColumns;
    ActAlignTop: TTyRichEditCellVAlign;
    ActAlignMiddle: TTyRichEditCellVAlign;
    ActAlignBottom: TTyRichEditCellVAlign;
    ActTableLeft: TTyRichEditTableAlign;
    ActTableCenter: TTyRichEditTableAlign;
    ActTableRight: TTyRichEditTableAlign;
    ActBorderAll: TTyRichEditCellBorders;
    ActBorderOutside: TTyRichEditCellBorders;
    ActBorderInside: TTyRichEditCellBorders;
    ActBorderNone: TTyRichEditCellBorders;
    ActBorderTop: TTyRichEditCellBorders;
    ActBorderBottom: TTyRichEditCellBorders;
    ActBorderLeft: TTyRichEditCellBorders;
    ActBorderRight: TTyRichEditCellBorders;
    ActBorderInsideH: TTyRichEditCellBorders;
    ActBorderInsideV: TTyRichEditCellBorders;
    ActShading: TTyRichEditCellShading;
    ActShadingNone: TAction;
    ActShadingChoose: TAction;
    ActTableProperties: TTyRichEditTableProperties;
    MnuTblInsert: TMenuItem;
    MnuInsTable: TMenuItem;
    MnuSepIns1: TMenuItem;
    MnuSepIns2: TMenuItem;
    MnuTblDelete: TMenuItem;
    MnuClearCells: TMenuItem;
    MnuTblSelect: TMenuItem;
    MnuSelectTable: TMenuItem;
    MnuSelectColumn: TMenuItem;
    MnuSelectRow: TMenuItem;
    MnuSelectCell: TMenuItem;
    MnuSepTbl1: TMenuItem;
    MnuTblAutoFit: TMenuItem;
    MnuAutoFit: TMenuItem;
    MnuFitWindow: TMenuItem;
    MnuSepFit: TMenuItem;
    MnuDistributeRows: TMenuItem;
    MnuDistributeColumns: TMenuItem;
    MnuTblCellAlign: TMenuItem;
    MnuAlignTop: TMenuItem;
    MnuAlignMiddle: TMenuItem;
    MnuAlignBottom: TMenuItem;
    MnuTblAlign: TMenuItem;
    MnuTableLeft: TMenuItem;
    MnuTableCenter: TMenuItem;
    MnuTableRight: TMenuItem;
    MnuTblBorders: TMenuItem;
    MnuBorderAll: TMenuItem;
    MnuBorderOutside: TMenuItem;
    MnuBorderInside: TMenuItem;
    MnuBorderNone: TMenuItem;
    MnuBorderTop: TMenuItem;
    MnuBorderBottom: TMenuItem;
    MnuBorderLeft: TMenuItem;
    MnuBorderRight: TMenuItem;
    MnuBorderInsideH: TMenuItem;
    MnuBorderInsideV: TMenuItem;
    MnuTblShading: TMenuItem;
    MnuShading: TMenuItem;
    MnuShadingNone: TMenuItem;
    MnuShadingChoose: TMenuItem;
    MnuSepTbl2: TMenuItem;
    MnuTableProperties: TMenuItem;
    PopTblSelect: TMenuItem;
    PopSelectTable: TMenuItem;
    PopSelectColumn: TMenuItem;
    PopSelectRow: TMenuItem;
    PopSelectCell: TMenuItem;
    PopTblInsert: TMenuItem;
    PopSepIns: TMenuItem;
    PopTblDelete: TMenuItem;
    PopClearCells: TMenuItem;
    PopTblCellAlign: TMenuItem;
    PopAlignTop: TMenuItem;
    PopAlignMiddle: TMenuItem;
    PopAlignBottom: TMenuItem;
    PopTblAutoFit: TMenuItem;
    PopAutoFit: TMenuItem;
    PopFitWindow: TMenuItem;
    PopSepFit: TMenuItem;
    PopDistributeRows: TMenuItem;
    PopDistributeColumns: TMenuItem;
    PopTableProperties: TMenuItem;
    PopBorders: TTyImagesMenu;
    PopBBorderAll: TMenuItem;
    PopBBorderOutside: TMenuItem;
    PopBBorderInside: TMenuItem;
    PopBBorderNone: TMenuItem;
    PopBBorderTop: TMenuItem;
    PopBBorderBottom: TMenuItem;
    PopBBorderLeft: TMenuItem;
    PopBBorderRight: TMenuItem;
    PopBBorderInsideH: TMenuItem;
    PopBBorderInsideV: TMenuItem;
    BorderGlyphs: TTyVirtualImageList;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ActNewExecute(Sender: TObject);
    procedure ActOpenExecute(Sender: TObject);
    procedure ActSaveExecute(Sender: TObject);
    procedure ActSaveAsExecute(Sender: TObject);
    procedure ActExitExecute(Sender: TObject);
    procedure ActTextAutoExecute(Sender: TObject);
    procedure ActTextChooseExecute(Sender: TObject);
    procedure ActHighlightNoneExecute(Sender: TObject);
    procedure ActHighlightChooseExecute(Sender: TObject);
    procedure ActReadOnlyExecute(Sender: TObject);
    procedure ActReadOnlyUpdate(Sender: TObject);
    procedure ActPlainTextExecute(Sender: TObject);
    procedure ActPlainTextUpdate(Sender: TObject);
    procedure ActShowRulerExecute(Sender: TObject);
    procedure ActShowRulerUpdate(Sender: TObject);
    procedure SampleClick(Sender: TObject);
    procedure PageSampleClick(Sender: TObject);
    procedure WrapClick(Sender: TObject);
    procedure DarkClick(Sender: TObject);
    procedure SkinClick(Sender: TObject);
    procedure FontBoxSelect(Sender: TObject);
    procedure FontBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SizeBoxSelect(Sender: TObject);
    procedure SizeBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SwatchColorChanged(Sender: TObject);
    procedure PopEditorPopup(Sender: TObject);
    procedure ActInsertLinkGetLink(Sender: TObject; var AURL, AText: string; var AAllow: Boolean);
    procedure ActEditLinkExecute(Sender: TObject);
    procedure ActEditLinkUpdate(Sender: TObject);
    procedure ActBookmarksExecute(Sender: TObject);
    procedure EditorObjectDblClick(Sender: TObject; const AClick: TTyRichObjectClick;
      var AHandled: Boolean);
    procedure EditorEditRefused(Sender: TObject; const AReason: string);
    procedure EditorLinkClick(Sender: TObject; const AURL: string; AButton: TMouseButton);
    procedure EditorLoadProgress(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure EditorModifiedChange(Sender: TObject);
    procedure EditorSelectionChange(Sender: TObject);
    procedure EditorZoomChange(Sender: TObject);
    procedure FindNotFound(Sender: TObject; const AText: string);
    procedure ReplaceReplaced(Sender: TObject; ACount: Integer);
    procedure TableChooseSize(Sender: TObject; var ARows, AColumns: Integer;
      var AInsert: Boolean);
    procedure SplitChooseSize(Sender: TObject; ACellColumns, ACellRows: Integer;
      var AColumns, ARows: Integer; var ASplit: Boolean);
    procedure BorderBeforeExecute(Sender: TObject; var APreset: TTyRichBorderPreset;
      var ABorder: TTyRichBorder; var AAllow: Boolean);
    procedure ActShadingNoneExecute(Sender: TObject);
    procedure ActShadingNoneUpdate(Sender: TObject);
    procedure ActShadingChooseExecute(Sender: TObject);
    procedure TablePropertiesBeforeExecute(Sender: TObject; var AProps: TTyRichTableProperties;
      var AAllow: Boolean);
  private
    { The actions' record of the rich edit, and how many times it had asked when the boxes
      were last filled from it. }
    FBoxesAt: Integer;
    { The same for the table's state: the caret is in a table (what the status bar shows). }
    FTableAt: Integer;
    FInTable: Boolean;
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure ShowTableState;
    procedure ShowFormatInBoxes;
    procedure ApplyFontName(const AName: string);
    procedure ApplyFontSize(const AText: string);
    procedure ShowSwatches;
    procedure Tell(const AText: string);
    procedure ShowCaret;
    procedure ShowZoom;
    procedure ShowTitle;
    procedure SetSkin(const AName: string);
    { The theme's chrome on every window of the example (the page form is not modal). }
    procedure ApplyThemeEverywhere;
    { Asks to save a changed document first; False: the user cancelled. }
    function MaySetAside: Boolean;
    function SaveAs: Boolean;
    function SamplesDir: string;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsLineColumn   = 'Line %d, column %d';
  rsZoomPercent  = '%d %%';
  rsNotFound     = 'Cannot find "%s".';
  rsReplaced     = '%d replaced.';
  rsLoading      = 'Loading: %d %%';
  rsLoaded       = 'Loaded.';
  rsSaved        = 'Saved: %s';
  rsUntitled     = 'Untitled';
  rsSaveChanges  = 'The document has changed. Save it first?';
  rsOpenFailed   = 'The file cannot be opened: %s';
  rsSaveFailed   = 'The file cannot be saved: %s';
  rsTableTitle   = 'Insert table';
  rsTablePrompt  = 'Rows x columns:';
  rsTableBadSize = 'Give the size as rows x columns, for example 3 x 4.';
  rsOpenFilter   = 'Documents (*.rtf;*.txt)|*.rtf;*.txt|Rich text (*.rtf)|*.rtf|Text (*.txt)|*.txt|All files|*';
  rsSaveFilter   = 'Rich text (*.rtf)|*.rtf|Text (*.txt)|*.txt';
  rsTextColorTitle = 'Text color';
  rsHighlightTitle = 'Highlight color';
  rsShadingTitle = 'Shading color';
  rsBadSize      = 'Give the size in points, for example 11 or 10.5.';
  rsPicture      = 'Picture';

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  item: TMenuItem;
begin
  // the skins are compiled in: the menu lists them without a themes/ folder
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
  begin
    item := TMenuItem.Create(Self);
    item.Caption := names[i];
    item.RadioItem := True;
    item.GroupIndex := 1;
    item.OnClick := @SkinClick;
    MnuSkin.Add(item);
  end;
  DlgOpen.Filter := rsOpenFilter;
  DlgSave.Filter := rsSaveFilter;
  TextSwatch.DialogCaption := rsTextColorTitle;
  HighlightSwatch.DialogCaption := rsHighlightTitle;
  ShadingSwatch.DialogCaption := rsShadingTitle;
  SetSkin('default');
  MnuWrapWindow.Checked := True;
  FBoxesAt := -1;
  FTableAt := -1;
  ShowSwatches;
  Application.AddOnIdleHandler(@AppIdle);
  ShowCaret;
  ShowZoom;
  ShowTitle;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  Application.RemoveOnIdleHandler(@AppIdle);
end;

{ ---- the font box and the size box ---- }

procedure TMainForm.AppIdle(Sender: TObject; var Done: Boolean);
begin
  ShowFormatInBoxes;
  ShowTableState;
end;

{ The table's state, asked of the rich edit when the actions' record asked it again (after a
  move of the selection or a change), never per idle round: the caret in a table, cells
  selected, and what the status bar says about them. }
procedure TMainForm.ShowTableState;
var
  st: TTyRichEditActionState;
begin
  st := TTyRichEditActionState.Find(Editor);
  st.Check;
  if st.Refreshes = FTableAt then Exit;
  FTableAt := st.Refreshes;
  FInTable := Editor.InTable;
  if FInTable then Status.Panels[1].Text := TableSelectionText(Editor)
  else Status.Panels[1].Text := '';
end;

{ Filled from the record the actions read (asked of the rich edit once per change of its
  selection or content, never per idle), and only when it asked again since the last time; not
  while the user types in a box. }
procedure TMainForm.ShowFormatInBoxes;
var
  st: TTyRichEditActionState;
begin
  if FontBox.Focused or SizeBox.Focused then Exit;
  st := TTyRichEditActionState.Find(Editor);
  st.Check;
  if st.Refreshes = FBoxesAt then Exit;
  FBoxesAt := st.Refreshes;
  FontBox.Enabled := st.CanFormatCharacters;
  SizeBox.Enabled := st.CanFormatCharacters;
  // several fonts (sizes) in the selection: an empty box
  if st.Readable and (caFace in st.CharConsistent) then FontBox.Text := st.FontName
  else FontBox.Text := '';
  if st.Readable and (caSize in st.CharConsistent) and (st.FontSize > 0) then
    SizeBox.Text := IntToStr(st.FontSize)
  else
    SizeBox.Text := '';
end;

procedure TMainForm.ApplyFontName(const AName: string);
var
  f: TTyCharFormat;
begin
  if Trim(AName) = '' then Exit;
  f := TyDefaultCharFormat;
  f.FontName := Trim(AName);
  Editor.ApplyCharacterFormat([cffFontName], f);
  if Editor.CanFocus then Editor.SetFocus;
end;

procedure TMainForm.ApplyFontSize(const AText: string);
var
  f: TTyCharFormat;
  v: Double;
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  // half points: the rich edit keeps sizes in half points (10.5 is 21)
  if not TryStrToFloat(Trim(StringReplace(AText, ',', '.', [])), v, fs) or (v < 1) or (v > 1638) then
  begin
    Tell(rsBadSize);
    Exit;
  end;
  f := TyDefaultCharFormat;
  f.SizeHalfPt := Round(v * 2);
  Editor.ApplyCharacterFormat([cffSize], f);
  if Editor.CanFocus then Editor.SetFocus;
end;

procedure TMainForm.FontBoxSelect(Sender: TObject);
begin
  ApplyFontName(FontBox.Text);
end;

procedure TMainForm.FontBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    ApplyFontName(FontBox.Text);
  end
  else if Key = VK_ESCAPE then
  begin
    Key := 0;
    FBoxesAt := -1;
    if Editor.CanFocus then Editor.SetFocus;
  end;
end;

procedure TMainForm.SizeBoxSelect(Sender: TObject);
begin
  ApplyFontSize(SizeBox.Text);
end;

procedure TMainForm.SizeBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    ApplyFontSize(SizeBox.Text);
  end
  else if Key = VK_ESCAPE then
  begin
    Key := 0;
    FBoxesAt := -1;
    if Editor.CanFocus then Editor.SetFocus;
  end;
end;

{ ---- the colours ---- }

{ Each swatch shows the colour its button applies (automatic shown as the text's colour, no
  highlight as the window's). }
procedure TMainForm.ShowSwatches;
begin
  if ActTextColor.Color = clDefault then TextSwatch.ButtonColor := clWindowText
  else TextSwatch.ButtonColor := ActTextColor.Color;
  if ActHighlight.Color = clNone then HighlightSwatch.ButtonColor := clWindow
  else HighlightSwatch.ButtonColor := ActHighlight.Color;
  if ActShading.Color = clNone then ShadingSwatch.ButtonColor := clWindow
  else ShadingSwatch.ButtonColor := ActShading.Color;
end;

{ The swatch's own dialog chose a colour: it is its button's colour now, and applied. }
procedure TMainForm.SwatchColorChanged(Sender: TObject);
begin
  if Sender = TextSwatch then
  begin
    ActTextColor.Color := TextSwatch.ButtonColor;
    ActTextColor.Execute;
  end
  else if Sender = ShadingSwatch then
  begin
    ActShading.Color := ShadingSwatch.ButtonColor;
    ActShading.Execute;
  end
  else
  begin
    ActHighlight.Color := HighlightSwatch.ButtonColor;
    ActHighlight.Execute;
  end;
end;

procedure TMainForm.ActTextAutoExecute(Sender: TObject);
begin
  ActTextColor.Color := clDefault;
  ActTextColor.Execute;
  ShowSwatches;
end;

procedure TMainForm.ActTextChooseExecute(Sender: TObject);
var
  c: TColor;
  alpha: Byte;
begin
  c := TextSwatch.ButtonColor;
  alpha := 255;
  if not TySelectColor(rsTextColorTitle, c, alpha) then Exit;
  ActTextColor.Color := c;
  ActTextColor.Execute;
  ShowSwatches;
end;

procedure TMainForm.ActHighlightNoneExecute(Sender: TObject);
begin
  ActHighlight.Color := clNone;
  ActHighlight.Execute;
  ShowSwatches;
end;

procedure TMainForm.ActHighlightChooseExecute(Sender: TObject);
var
  c: TColor;
  alpha: Byte;
begin
  c := HighlightSwatch.ButtonColor;
  alpha := 255;
  if not TySelectColor(rsHighlightTitle, c, alpha) then Exit;
  ActHighlight.Color := c;
  ActHighlight.Execute;
  ShowSwatches;
end;

{ ---- View ---- }

procedure TMainForm.ActReadOnlyExecute(Sender: TObject);
begin
  Editor.ReadOnly := not Editor.ReadOnly;
end;

procedure TMainForm.ActReadOnlyUpdate(Sender: TObject);
begin
  ActReadOnly.Checked := Editor.ReadOnly;
end;

procedure TMainForm.ActPlainTextExecute(Sender: TObject);
begin
  // the document's state: a plain text document is saved as text, a paste takes text only
  Editor.PlainText := not Editor.PlainText;
end;

procedure TMainForm.ActPlainTextUpdate(Sender: TObject);
begin
  ActPlainText.Checked := Editor.PlainText;
end;

procedure TMainForm.ActShowRulerExecute(Sender: TObject);
begin
  Ruler.Visible := not Ruler.Visible;
end;

procedure TMainForm.ActShowRulerUpdate(Sender: TObject);
begin
  ActShowRuler.Checked := Ruler.Visible;
end;

{ The context menu: a new link where one may be made, the link's own items in a link, the
  table's commands only when the caret is in a table (each enabled by its action, as on the
  tool bar). }
procedure TMainForm.PopEditorPopup(Sender: TObject);
var
  t, inLink, newLink: Boolean;
begin
  inLink := Editor.CanEditLink;
  newLink := not inLink and Editor.CanInsertLink;
  PopSepLink.Visible := inLink or newLink;
  PopInsertLink.Visible := newLink;
  PopEditLink.Visible := inLink;
  PopRemoveLink.Visible := inLink;
  t := Editor.InTable;
  PopSepTable.Visible := t;
  PopTblSelect.Visible := t;
  PopTblInsert.Visible := t;
  PopTblDelete.Visible := t;
  PopTblCellAlign.Visible := t;
  PopTblAutoFit.Visible := t;
  PopMergeCells.Visible := t;
  PopSplitCell.Visible := t;
  PopTableProperties.Visible := t;
end;

{ ---- the table ---- }

{ A preset from the borders drop-down or the Borders menu: the drop-down's button keeps it, so
  a click on the button gives the same lines again (as Word's). }
procedure TMainForm.BorderBeforeExecute(Sender: TObject; var APreset: TTyRichBorderPreset;
  var ABorder: TTyRichBorder; var AAllow: Boolean);
begin
  if BtnBorders.Action <> Sender then
  begin
    BtnBorders.Action := TBasicAction(Sender);
    BtnBorders.GlyphName := BorderGlyphs.Names[Ord(APreset)];
  end;
end;

procedure TMainForm.ActShadingNoneExecute(Sender: TObject);
begin
  ActShading.Color := clNone;
  ActShading.Execute;
  ShowSwatches;
end;

procedure TMainForm.ActShadingNoneUpdate(Sender: TObject);
var
  st: TTyRichEditActionState;
begin
  st := TTyRichEditActionState.Find(Editor);
  st.Check;
  TAction(Sender).Enabled := st.CanFormatCells;
end;

procedure TMainForm.ActShadingChooseExecute(Sender: TObject);
var
  c: TColor;
  alpha: Byte;
begin
  c := ShadingSwatch.ButtonColor;
  alpha := 255;
  if not TySelectColor(rsShadingTitle, c, alpha) then Exit;
  ActShading.Color := c;
  ActShading.Execute;
  ShowSwatches;
end;

{ Table Properties: the example's form (utableform) asks; what it names as changed - the lines
  too - is applied by the action as one undo step (nothing changed: nothing). }
procedure TMainForm.TablePropertiesBeforeExecute(Sender: TObject;
  var AProps: TTyRichTableProperties; var AAllow: Boolean);
begin
  AAllow := AskTableProperties(Editor, AProps);
end;

{ ---- links, bookmarks, pictures ---- }

{ The link action asks here (a new link, or the one at the caret to change): the link form. }
procedure TMainForm.ActInsertLinkGetLink(Sender: TObject; var AURL, AText: string;
  var AAllow: Boolean);
begin
  AAllow := AskLink(Editor, AURL, AText);
end;

{ Edit Link: the link action on the link at the caret (it changes the one it stands in). }
procedure TMainForm.ActEditLinkExecute(Sender: TObject);
begin
  ActInsertLink.Execute;
end;

{ From the record the rich edit's actions read: no query of the control per idle round. }
procedure TMainForm.ActEditLinkUpdate(Sender: TObject);
var
  st: TTyRichEditActionState;
begin
  st := TTyRichEditActionState.Find(Editor);
  st.Check;
  ActEditLink.Enabled := st.CanEditLink;
end;

procedure TMainForm.ActBookmarksExecute(Sender: TObject);
begin
  ManageBookmarks(Editor);
end;

{ A double click on a picture, or on a block that shows one (an equation): the viewer. Any
  other object, or a picture the control draws as a frame: what a double click does. }
procedure TMainForm.EditorObjectDblClick(Sender: TObject; const AClick: TTyRichObjectClick;
  var AHandled: Boolean);
begin
  if AClick.Button <> mbLeft then Exit;
  AHandled := ViewPicture(AClick.RichObject, rsPicture);
end;

procedure TMainForm.SetSkin(const AName: string);
var
  i: Integer;
begin
  TyDefaultController.ThemeName := AName;
  ApplyThemeEverywhere;
  for i := 0 to MnuSkin.Count - 1 do
    MnuSkin.Items[i].Checked := SameText(MnuSkin.Items[i].Caption, AName);
end;

procedure TMainForm.SkinClick(Sender: TObject);
begin
  SetSkin(TMenuItem(Sender).Caption);
end;

procedure TMainForm.DarkClick(Sender: TObject);
begin
  MnuDark.Checked := not MnuDark.Checked;
  if MnuDark.Checked then TyDefaultController.Mode := 'dark'
  else TyDefaultController.Mode := 'light';
  ApplyThemeEverywhere;
end;

procedure TMainForm.ApplyThemeEverywhere;
var
  i: Integer;
begin
  for i := 0 to Screen.CustomFormCount - 1 do
    if Screen.CustomForms[i] is TTyForm then
    begin
      TTyForm(Screen.CustomForms[i]).ApplyChromeTheme(TyDefaultController);
      // the page's picture is drawn in the accent: the page is built again
      if Screen.CustomForms[i] is TPageForm then TPageForm(Screen.CustomForms[i]).ThemeChanged;
    end;
end;

{ The page made from code (upagesample), shown as a help page and as a home page. }
procedure TMainForm.PageSampleClick(Sender: TObject);
begin
  ShowPageForm;
end;

procedure TMainForm.Tell(const AText: string);
begin
  Status.Panels[0].Text := AText;
end;

procedure TMainForm.ShowCaret;
var
  p: TPoint;
begin
  p := Editor.CaretPos;
  Status.Panels[2].Text := Format(rsLineColumn, [p.Y + 1, p.X + 1]);
end;

procedure TMainForm.ShowZoom;
begin
  Status.Panels[3].Text := Format(rsZoomPercent, [Editor.Zoom]);
end;

procedure TMainForm.ShowTitle;
var
  s: string;
begin
  if Editor.SourceFile <> '' then s := ExtractFileName(Editor.SourceFile) else s := rsUntitled;
  if Editor.Modified then s := '* ' + s;
  Bar.Caption := s + '  · TyControls';
end;

procedure TMainForm.EditorEditRefused(Sender: TObject; const AReason: string);
begin
  // a refusal is the status bar's, never a dialog: the user goes on typing
  Tell(AReason);
end;

procedure TMainForm.EditorLinkClick(Sender: TObject; const AURL: string; AButton: TMouseButton);
begin
  // the address is shown; a place in this document (#name - Word's contents point at its
  // headings) the rich edit goes to itself after this (FollowBookmarkLinks)
  Tell(AURL);
  if AButton <> mbLeft then Exit;
  // a web or mail address: the system's handler; anything else (a file, "file#name") is
  // only shown - the control never opens one, and the example does not either
  if StartsText('http://', AURL) or StartsText('https://', AURL) or StartsText('mailto:', AURL) then
    OpenURL(AURL);
end;

procedure TMainForm.EditorLoadProgress(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  if (ATotal > 0) and (ADone < ATotal) then Tell(Format(rsLoading, [ADone * 100 div ATotal]))
  else Tell(rsLoaded);
end;

procedure TMainForm.EditorModifiedChange(Sender: TObject);
begin
  ShowTitle;
end;

procedure TMainForm.EditorSelectionChange(Sender: TObject);
begin
  ShowCaret;
end;

procedure TMainForm.EditorZoomChange(Sender: TObject);
begin
  ShowZoom;
end;

procedure TMainForm.FindNotFound(Sender: TObject; const AText: string);
begin
  Tell(Format(rsNotFound, [AText]));
end;

procedure TMainForm.ReplaceReplaced(Sender: TObject; ACount: Integer);
begin
  Tell(Format(rsReplaced, [ACount]));
end;

procedure TMainForm.TableChooseSize(Sender: TObject; var ARows, AColumns: Integer;
  var AInsert: Boolean);
var
  s: string;
  p, r, c: Integer;
begin
  s := Format('%d x %d', [ARows, AColumns]);
  AInsert := TyInputQuery(rsTableTitle, rsTablePrompt, s);
  if not AInsert then Exit;
  s := LowerCase(StringReplace(s, ' ', '', [rfReplaceAll]));
  p := Pos('x', s);
  if (p > 0) and TryStrToInt(Copy(s, 1, p - 1), r) and TryStrToInt(Copy(s, p + 1, MaxInt), c) then
  begin
    ARows := r;
    AColumns := c;
  end
  else
  begin
    AInsert := False;
    Tell(rsTableBadSize);
  end;
end;

{ Split Cells asks here: the split form, starting from 2 x 1 - or, for a merged cell, from the
  columns and rows it covers (the table's grid says), so OK splits it back. }
procedure TMainForm.SplitChooseSize(Sender: TObject; ACellColumns, ACellRows: Integer;
  var AColumns, ARows: Integer; var ASplit: Boolean);
begin
  // (the action starts from what the cell covers when it is merged, else from 2 x 1)
  ASplit := AskSplit(AColumns, ARows);
end;

function TMainForm.MaySetAside: Boolean;
begin
  Result := True;
  if not Editor.Modified then Exit;
  case TyMessageDlg(rsSaveChanges, mtConfirmation, [mbYes, mbNo, mbCancel]) of
    mrYes:
      begin
        ActSaveExecute(nil);
        Result := not Editor.Modified;
      end;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := MaySetAside;
end;

procedure TMainForm.ActNewExecute(Sender: TObject);
begin
  if not MaySetAside then Exit;
  Editor.Clear;
  Editor.PlainText := False;
  Tell('');
  ShowTitle;
end;

procedure TMainForm.ActOpenExecute(Sender: TObject);
begin
  if not MaySetAside then Exit;
  if not DlgOpen.Execute then Exit;
  try
    // the format from the file itself (an RTF file is read as RTF whatever its name)
    Editor.LoadFromFile(DlgOpen.FileName);
    Tell('');
  except
    on E: Exception do Tell(Format(rsOpenFailed, [E.Message]));
  end;
  ShowTitle;
end;

procedure TMainForm.ActSaveExecute(Sender: TObject);
begin
  if Editor.SourceFile = '' then
  begin
    SaveAs;
    Exit;
  end;
  try
    // in the format it was opened in (a text file stays text, an RTF file RTF)
    Editor.SaveToFile(Editor.SourceFile, Editor.SourceFormat);
    Tell(Format(rsSaved, [Editor.SourceFile]));
  except
    on E: Exception do Tell(Format(rsSaveFailed, [E.Message]));
  end;
  ShowTitle;
end;

procedure TMainForm.ActSaveAsExecute(Sender: TObject);
begin
  SaveAs;
end;

function TMainForm.SaveAs: Boolean;
var
  fmt: TTyRichFormat;
begin
  Result := False;
  if Editor.PlainText then DlgSave.FilterIndex := 2 else DlgSave.FilterIndex := 1;
  if not DlgSave.Execute then Exit;
  if DlgSave.FilterIndex = 2 then fmt := rfText else fmt := rfRtf;
  try
    Editor.SaveToFile(DlgSave.FileName, fmt);
    Tell(Format(rsSaved, [DlgSave.FileName]));
    Result := True;
  except
    on E: Exception do Tell(Format(rsSaveFailed, [E.Message]));
  end;
  ShowTitle;
end;

procedure TMainForm.ActExitExecute(Sender: TObject);
begin
  Close;
end;

function TMainForm.SamplesDir: string;
var
  dir: string;
  i: Integer;
begin
  // beside the program, or up from it (the build may put it in a folder of its own)
  dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(dir + 'samples') then Exit(dir + 'samples' + PathDelim);
    dir := ExtractFilePath(ExcludeTrailingPathDelimiter(dir));
    if dir = '' then Break;
  end;
  Result := 'samples' + PathDelim;
end;

procedure TMainForm.SampleClick(Sender: TObject);
var
  sample: string;
  f: TFileStream;
begin
  if not MaySetAside then Exit;
  if Sender = MnuSampleTable then
  begin
    // made with the builder (utablesample): a new document, no file behind it
    ShowTableSample(Editor);
    Tell('');
    ShowTitle;
    Exit;
  end;
  if Sender = MnuSampleFormats then sample := 'wp-styles.rtf'
  else if Sender = MnuSamplePictures then sample := 're-zh-picture.rtf'
  else sample := 'word-toc.rtf';
  try
    // read from a stream: the sample is not the document's file, so Save asks for a name
    f := TFileStream.Create(SamplesDir + sample, fmOpenRead or fmShareDenyWrite);
    try
      Editor.LoadFromStream(f, rfRtf);
    finally
      f.Free;
    end;
    Tell(sample);
  except
    on E: Exception do Tell(Format(rsOpenFailed, [E.Message]));
  end;
  ShowTitle;
end;

procedure TMainForm.WrapClick(Sender: TObject);
begin
  TMenuItem(Sender).Checked := True;
  if Sender = MnuWrapPage then Editor.WrapMode := rwmPage
  else if Sender = MnuWrapNone then Editor.WrapMode := rwmNone
  else Editor.WrapMode := rwmWindow;
end;

end.
