unit tyControls.RichEdit.Commands;

{ The built-in commands of TTyRichEdit's document: insert text, delete, set character and
  paragraph formats, insert an object, resize one, copy or move a range to another place, and
  a command made of commands (what an update block becomes). Each is run by TTyRichDocument.Execute, and each changes the document only
  through the primitives TTyRichCommand hands on, so the inherited undo (the records
  reverted, newest first) and redo (run again) are exact - none of them keeps text or a
  snapshot of its own. A program adds its own commands the same way. The table commands
  insert a table and insert and delete its rows and columns (TTyRichDocument.EditTable). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, ImgList, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.TableProps;

type
  { Inserts text (paragraph separators allowed) at APos; AFormat as TTyRichDocument's
    InsertText. Typing - mergeable text without a separator - merges with the typing right
    before it into one undo step, as TTyMemo's undo stack does: a paste passes
    AMergeable = False, and Enter (a separator) never merges.
    The insert and delete commands do not run where the document keeps the text as the
    file has it (TTyRichDocument.CanChange): Execute returns False and nothing changes. }
  TTyRichInsertText = class(TTyRichCommand)
  private
    FPos: array of TTyRichPos;      // one entry per merged insert, in order
    FTexts: array of UTF8String;
    FFormats: array of TTyCharFormatId;
    FTyping: Boolean;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(APos: TTyRichPos; const AText: UTF8String;
      AFormat: TTyCharFormatId = TyRichInheritFormat; AMergeable: Boolean = True);
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function TryMerge(ANext: TTyRichCommand): Boolean; override;
    function Description: string; override;
    function MemSize: Int64; override;
    property Typing: Boolean read FTyping;
  end;

  { Deletes ALen characters at APos. What goes - the pieces, and with them the runs,
    paragraph formats and objects of the deleted range - is kept by the primitive's record,
    as references. }
  TTyRichDelete = class(TTyRichCommand)
  private
    FPos, FLen: TTyRichPos;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(APos, ALen: TTyRichPos);
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
  end;

  { Sets the AMask fields of the characters in ARange (the others keep theirs). AKeepNone:
    of the name and the size, those a character with none of its own keeps none of
    (TTyRichDocument.ApplyCharFormat). The marks and the results of fields in the range keep
    their look (a result is read-only); a range of nothing else - one wholly inside a
    result - is refused (CanExecute False: TTyRichDocument.FieldOnly). }
  TTyRichSetCharFormat = class(TTyRichCommand)
  private
    FRange: TTyRichRange;
    FMask: TTyCharFormatMask;
    FValue: TTyCharFormat;
    FKeepNone: TTyCharFormatMask;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(const ARange: TTyRichRange; AMask: TTyCharFormatMask;
      const AValue: TTyCharFormat; AKeepNone: TTyCharFormatMask = []);
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
  end;

  { Sets the AMask fields of paragraphs AFirstPara..ALastPara. A paragraph whose paragraph
    mark is a field's result's keeps its format (TTyRichDocument.ParaEndsInField); a range
    of only such paragraphs is refused (CanExecute False). }
  TTyRichSetParaFormat = class(TTyRichCommand)
  private
    FFirst, FLast: Integer;
    FMask: TTyParaFormatMask;
    FValue: TTyParaFormat;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(AFirstPara, ALastPara: Integer; AMask: TTyParaFormatMask;
      const AValue: TTyParaFormat);
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
  end;

  { The list items among paragraphs AFirstPara .. ALastPara a level deeper (ADelta 1) or
    shallower (-1), Word's Tab and Shift+Tab at an item: each item's level moved by ADelta
    within 0 .. 8 (an item already at the end stays where it is) and its left indent by
    CTyRichListLevelIndent a level, its hanging offset kept; paragraphs that are no item, and
    those ending inside a field's result, are passed over. One step; none when no item moved. }
  TTyRichChangeListLevel = class(TTyRichCommand)
  private
    FFirst, FLast, FDelta: Integer;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(AFirstPara, ALastPara, ADelta: Integer);
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
  end;

  { Inserts AObject's character at APos. The command holds a reference to the object (so
    redo puts the same object back); one that is never executed takes it along when it is
    freed. }
  TTyRichInsertObject = class(TTyRichCommand)
  private
    FPos: TTyRichPos;
    FObject: TTyRichObject;
    FFormat: TTyCharFormatId;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(APos: TTyRichPos; AObject: TTyRichObject;
      AFormat: TTyCharFormatId = TyRichInheritFormat);
    destructor Destroy; override;
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
    { The step keeps the object alive: GatherObjects names it (the history counts its data
      once). }
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); override;
    property RichObject: TTyRichObject read FObject;
  end;

  { The object at APos shown AWidthTwips x AHeightTwips: objects are immutable, so the object
    there is replaced by a new one of its class (TTyRichObject.Resized - a picture shares its
    image's bytes with the old one, so a step costs the history the objects' own small parts,
    not the image again), made at the first run and held here, so a redo puts that very one
    back; an undo puts the very object back that was there (a file's picture: the file's
    bytes again). The character, its run's format and everything around it stay. Refused
    (CanExecute) when there is no object at APos, it cannot be resized (CanResize), a size is
    not positive, or the paragraph cannot change there (TTyRichDocument.CanChange: a row that
    holds a nested table). The size it has already: nothing changes and no step is kept. }
  TTyRichResizeObject = class(TTyRichCommand)
  private
    FPos: TTyRichPos;
    FWidth, FHeight: Integer;
    FNew: TTyRichObject;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(APos: TTyRichPos; AWidthTwips, AHeightTwips: Integer);
    destructor Destroy; override;
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
    { The new object is kept alive by the step (the history counts its own part once; the
      data it shares, once for all). }
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); override;
    property Pos: TTyRichPos read FPos;
    property WidthTwips: Integer read FWidth;
    property HeightTwips: Integer read FHeight;
    { After the first run that changed something: the object it put in (nil before). }
    property NewObject: TTyRichObject read FNew;
  end;

  { A picture of AGraphic - or of image AIndex of AImages, at the list's own size - at APos,
    as TTyRichInsertObject inserts one: a PNG and a JPEG keep their bytes, any other graphic
    becomes PNG. Shown AWidthTwips x AHeightTwips; 0 for both: its pixels at 96 dpi; one of
    them 0: the other side kept to the picture's shape. The picture is made here, once (the
    graphic or the list is not kept: a redo puts the same picture back). Raises ETyRichModel
    for an empty graphic, an index not in the list, or a size below 0. }
  TTyRichInsertPicture = class(TTyRichInsertObject)
  public
    { The picture this command would insert, made alone (not held: the caller's, with no
      reference taken) - for whoever builds content of its own (TTyRichBuilder). }
    class function PictureOf(AGraphic: TGraphic; AWidthTwips,
      AHeightTwips: Integer): TTyRichPicture;
    class function PictureOfList(AImages: TCustomImageList; AIndex, AWidthTwips,
      AHeightTwips: Integer): TTyRichPicture;
  public
    constructor Create(APos: TTyRichPos; AGraphic: TGraphic; AWidthTwips: Integer = 0;
      AHeightTwips: Integer = 0; AFormat: TTyCharFormatId = TyRichInheritFormat); overload;
    constructor Create(APos: TTyRichPos; AImages: TCustomImageList; AIndex: Integer;
      AWidthTwips: Integer = 0; AHeightTwips: Integer = 0;
      AFormat: TTyCharFormatId = TyRichInheritFormat); overload;
    function Description: string; override;
  end;

  { The document's settings (TTyRichDocument.ChangeSettings: the page, the defaults, the
    ground) become ASettings, one step. Settings equal to the document's: no step. }
  TTyRichChangeSettings = class(TTyRichCommand)
  private
    FSettings: TTyRichDocSettings;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(const ASettings: TTyRichDocSettings);
    function Description: string; override;
    property Settings: TTyRichDocSettings read FSettings;
  end;

  { Inserts the content of ASource - a document of its own, what a reader made of a
    clipboard's RTF (TyRichReadRtfFragment) - at APos, as one command: its text with its
    characters' formats and objects, its paragraphs with their formats, its tables as rows
    (TTyRichFragment says how it meets the paragraph at APos, how tables go in and what does
    not come along; AEndsWithParagraph and AFlatten are its). The command takes ASource over:
    at its first run it makes the fragment (values of the target, held here, so redo puts the
    same ones back) and frees ASource; one never run frees ASource with itself. Undo is one
    insert's record (the characters inserted go, the paragraph at APos gets its value back);
    what the history keeps is the fragment - its text and its paragraph values (MemSize).
    Not mergeable. Refused (CanExecute) where the text cannot change (CanChange: a row that
    holds a nested table). Nothing to insert (an empty source that does not end with a
    paragraph mark): it changes nothing and is not kept. AFilter (nil: none) is the
    fragment's (TTyRichFragment): what of the source's kept bytes may go into this target -
    what means the same in the target's file (RtfRead's TyRichFragmentFilterFor says
    which). The command takes it over too, and frees it with
    the source. A bookmark of the source goes in as Word pastes one: left out (its text
    goes in) when the document has a bookmark of its name already, or when only one of its
    two ends is in the source. }
  TTyRichInsertFragment = class(TTyRichCommand)
  private
    FPos: TTyRichPos;
    FSource: TTyRichDocument;
    FFilter: TTyRichFragmentFilter;
    FFragment: TTyRichFragment;
    FEnds, FFlatten: Boolean;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(APos: TTyRichPos; ASource: TTyRichDocument; AEndsWithParagraph: Boolean;
      AFlatten: Boolean = False; AFilter: TTyRichFragmentFilter = nil);
    destructor Destroy; override;
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
    function MemSize: Int64; override;
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); override;
    { After the first run: what went in (nil before). }
    property Fragment: TTyRichFragment read FFragment;
  end;

  { Copies (TTyRichCopy) or moves (TTyRichMove) the characters [AFrom, AFrom + ALen) to ATo,
    inside the same document, as one command and one undo step - the positions as they are
    before it runs. What goes in at ATo is what the control's own clipboard round trip of
    the range pastes there (TTyRichRangeContent says what is taken, TTyRichFragment how it
    goes in): a copy takes every row a range that crosses a cell's or a row's edge meets,
    whole, as copying it does; a range inside one cell goes as paragraphs; the document's
    last paragraph taken to its end goes as a paragraph; rows go in as rows where ATo is in
    no table, as the cell's text where it is in a cell; the paragraph marks a last row, or the
    content's end, needs are this document's. The paragraphs keep their own formats; tables
    go in as tables of their own (never the source's). The text is not copied - its pieces
    go in, the same bytes - unless a paragraph of the range is still a lazy load's (then its
    decoded text, once). A copy of an object is its clone (a picture's shares its bytes); a
    move puts the very objects at the new place. A bookmark goes as a paste takes one
    (TTyRichInsertFragment): a copy's are left out, the document having them already (and a
    bookmark of which the range holds one end only); a move's go with the text.
    Refused (CanExecute False, nothing changes): the range (not empty) or ATo out of the
    text; ATo where the content cannot go in (TTyRichDocument.CanChange: a row that holds a
    nested table); for a copy ATo strictly inside the range (its ends are places: the copy
    goes beside the content); for a move ATo inside the range or at either end (nothing would
    move), a range the document cannot delete there (CanChange), one that crosses a cell's or
    a row's edge without being whole rows, and one that is only the separator a user's cut
    keeps (TTyRichDocument.UserRangeAllowed: a range that begins outside a table and ends
    where its first row starts keeps that separator - so does the move).
    A move deletes the range, then inserts it at ATo (less the range when ATo was after it).
    Undo puts everything back as it was - the text's very pieces, the values, the objects,
    the cells; redo does the same again with the values the first run made. What a step
    holds: a move's delete record (the range's pieces and values, as references) and the
    fragment (one value per paragraph that went in, the inserted pieces) - no copy of the
    text. A huge range takes as long as a paste of it does. }
  TTyRichRangeTransfer = class(TTyRichCommand)
  private
    FFrom, FLen, FTo: TTyRichPos;
    FCut: TTyRichPos;
    FAt: TTyRichPos;
    FFragment: TTyRichFragment;
    FPlaced: TTyRichRange;
  protected
    { True: the range goes (a move); False: it stays (a copy). }
    function Moves: Boolean; virtual; abstract;
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(AFrom, ALen, ATo: TTyRichPos);
    destructor Destroy; override;
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function MemSize: Int64; override;
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); override;
    property FromPos: TTyRichPos read FFrom;
    property RangeLength: TTyRichPos read FLen;
    property ToPos: TTyRichPos read FTo;
    { After a run: where the content went (its characters, in the document as the run left
      it). Empty before. }
    property Placed: TTyRichRange read FPlaced;
    { After the first run: what went in (nil before). }
    property Fragment: TTyRichFragment read FFragment;
  end;

  TTyRichCopy = class(TTyRichRangeTransfer)
  protected
    function Moves: Boolean; override;
  public
    function Description: string; override;
  end;

  TTyRichMove = class(TTyRichRangeTransfer)
  protected
    function Moves: Boolean; override;
  public
    function Description: string; override;
  end;

  { Commands run as one: executed in order, undone newest first, one undo step. A part that
    cannot execute (CanExecute False) at its turn makes the whole raise, and what the parts
    before it did is reverted. The document builds one from an update block. }
  TTyRichCompositeCommand = class(TTyRichCommand)
  private
    FItems: TFPList;
    FDone: Integer;           // parts that have run (and are not undone)
    FDescription: string;
    function GetItem(AIndex: Integer): TTyRichCommand;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
    procedure DoUndo(ADoc: TTyRichDocument); override;
    procedure DoRedo(ADoc: TTyRichDocument); override;
  public
    constructor Create(const ADescription: string = '');
    { For TTyRichDocument.EndUpdate: parts that have run already, taken over. }
    constructor CreateExecuted(const ADescription: string;
      const ACommands: array of TTyRichCommand);
    destructor Destroy; override;
    { Takes ACmd over; only before the composite is executed. }
    procedure Add(ACmd: TTyRichCommand);
    function Count: Integer;
    { ADescription, else the only part's, else a generic one. }
    function Description: string; override;
    function MemSize: Int64; override;
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); override;
    property Items[AIndex: Integer]: TTyRichCommand read GetItem;
  end;

  { A change of a table's structure (TTyRichDocument.EditTable says what each does). The
    table is named by a position inside it, rows and cells by their index (rows counted over
    those that have paragraphs: TTyRichDocument.TableInfoAt). CanExecute is False - Execute
    changes nothing - when Refusal is not rtrNone (TTyRichDocument.TableEditRefusal: a table
    with merged cells or a nested table, one a loader cannot give whole, irregular rows for a
    column, an index out of range, a position in no table). One undo step; an undo gives
    every paragraph its value and its cell in its very table back; a redo puts the table
    object of the first run back in (the command holds it: MemSize counts it). Not
    mergeable. }
  TTyRichTableCommand = class(TTyRichCommand)
  private
    FEdit: TTyRichTableEdit;
    FTables: TTyRichTables;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    destructor Destroy; override;
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Refusal(ADoc: TTyRichDocument): TTyRichTableRefusal;
    function MemSize: Int64; override;
    property Edit: TTyRichTableEdit read FEdit;
  end;

  { An ARows x ACols table at APos, AWidth twips wide (0: the document's text width,
    TTyRichDocument.TextWidthTwips), at most CRichMaxTableRows x CRichMaxTableCols. }
  TTyRichInsertTable = class(TTyRichTableCommand)
  public
    constructor Create(APos: TTyRichPos; ARows, ACols: Integer; AWidth: Integer = 0);
    function Description: string; override;
  end;

  { A row at AIndex (0 .. the row count) of the table ATablePos is in; CRichRowAbove /
    CRichRowBelow: right above / below the row ATablePos is in. }
  TTyRichInsertRow = class(TTyRichTableCommand)
  public
    constructor Create(ATablePos: TTyRichPos; AIndex: Integer);
    function Description: string; override;
  end;

  { Row AIndex of the table ATablePos is in. }
  TTyRichDeleteRow = class(TTyRichTableCommand)
  public
    constructor Create(ATablePos: TTyRichPos; AIndex: Integer);
    function Description: string; override;
  end;

  { A column at cell index AIndex (0 .. the cell count) of the table ATablePos is in. }
  TTyRichInsertColumn = class(TTyRichTableCommand)
  public
    constructor Create(ATablePos: TTyRichPos; AIndex: Integer);
    function Description: string; override;
  end;

  { The column at cell index AIndex of the table ATablePos is in. }
  TTyRichDeleteColumn = class(TTyRichTableCommand)
  public
    constructor Create(ATablePos: TTyRichPos; AIndex: Integer);
    function Description: string; override;
  end;

  { A column of the grid AWidth twips wide at AX (twips, an edge of the grid) of the table
    ATablePos is in: a new cell in a row with an edge there, the cell that reaches over it
    wider in another (TTyRichTableEdit says what it does). For any table without a nested
    one: merged cells, rows of different cells. }
  TTyRichInsertGridColumn = class(TTyRichTableCommand)
  public
    constructor Create(ATablePos: TTyRichPos; AX, AWidth: Integer);
    function Description: string; override;
  end;

  { The grid's columns from AX0 to AX1 (twips) of the table ATablePos is in: the cells wholly
    inside go, a cell reaching out of them keeps its content, narrower. }
  TTyRichDeleteGridColumns = class(TTyRichTableCommand)
  public
    constructor Create(ATablePos: TTyRichPos; AX0, AX1: Integer);
    function Description: string; override;
  end;

  { Cells merged: in rows ARow0 .. ARow1 of the table ATablePos is in (counted as the table
    edits count them), the cells that meet AX0 .. AX1 (twips) become one - the first of them
    in each row, as wide as they were; over more than one row the first row's begins a
    vertical merge and the others' continue it. The cell has the top-left cell's look and the
    lines that were on the rectangle's outline. The cells that go, and those the merge
    covers, must be empty (rtrNotEmpty otherwise): the control's MergeCells moves their
    content into the top-left cell first, in the same step. Refused on a table with a nested
    table. }
  TTyRichMergeCells = class(TTyRichTableCommand)
  public
    constructor Create(ATablePos: TTyRichPos; ARow0, ARow1, AX0, AX1: Integer);
    function Description: string; override;
  end;

  { Cell ACell of row ARow (which covers ASpanRows rows, 1: none below it) split into ACols
    cells across, at AEdges (twips inside the cell, rising: ACols - 1 of them), and ARows
    down (TTyRichTableEdit.SplitEdges says what it does). The content stays in the first
    cell. }
  TTyRichSplitCell = class(TTyRichTableCommand)
  public
    constructor Create(ATablePos: TTyRichPos; ARow, ACell, ASpanRows, ACols, ARows: Integer;
      const AEdges: array of Integer);
    function Description: string; override;
  end;

  { A change of table properties (TTyRichDocument.EditTableProps says what it does): only
    the fields the properties' Valid names change. The table is named by a position inside
    it, rows by their index as the table edits count them. CanExecute is False - Execute
    changes nothing - when Refusal is not rtrNone (TTyRichDocument.TablePropsRefusal). One
    undo step: an undo gives every paragraph of the rows it changed its value back, the
    rows their places; nothing else of the table is touched. Not mergeable. }
  TTyRichTablePropsCommand = class(TTyRichCommand)
  private
    FEdit: TTyRichPropEdit;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Refusal(ADoc: TTyRichDocument): TTyRichTableRefusal;
    property Edit: TTyRichPropEdit read FEdit;
  end;

  { Cells ACol0 .. ACol1 of rows ARow0 .. ARow1 of the table ATablePos is in get the fields
    of AProps that AProps.Valid names: a border, the shading, the cell's own padding (-1: none
    of its own, the row's then), the alignment of its content, its width (its right edge and
    the edges after it move; not in a table with merged cells). }
  TTyRichSetCellProps = class(TTyRichTablePropsCommand)
  public
    constructor Create(ATablePos: TTyRichPos; ARow0, ACol0, ARow1, ACol1: Integer;
      const AProps: TTyRichCellProps);
    function Description: string; override;
  end;

  { Rows ARow0 .. ARow1 of the table ATablePos is in get the fields of AProps that
    AProps.Valid names: the height, the left (its cells move with it; not in a table with
    merged cells), the alignment, the padding of the cells that set none (a side -1: as it
    is). }
  TTyRichSetRowProps = class(TTyRichTablePropsCommand)
  public
    constructor Create(ATablePos: TTyRichPos; ARow0, ARow1: Integer; const AProps: TTyRichRowProps);
    function Description: string; override;
  end;

  { A column's edge dragged: in rows ARow0 .. ARow1 of the table ATablePos is in, the edge at
    AEdgeTwips (a row's left, or a cell's right edge; rows whose edges differ by at most
    CRichSharedEdgeTwips share one, a row with none there is left as it is) goes to
    ANewTwips. The cells on either side trade width and the table keeps its width; the last
    edge changes the last cell and the table's width; the left edge moves the row's start and
    its first cell's width follows. AShiftRest: the cell to its left changes and everything
    to its right moves with the edge (the left edge: the whole row moves). }
  TTyRichSetColumnEdge = class(TTyRichTablePropsCommand)
  public
    constructor Create(ATablePos: TTyRichPos; AEdgeTwips, ANewTwips: Integer; ARow0, ARow1: Integer;
      AShiftRest: Boolean);
    function Description: string; override;
  end;

  { TTyRichSetRowProps named as a row height's change (a drag of a row's bottom, SetRowHeight). }
  TTyRichSetRowHeight = class(TTyRichSetRowProps)
  public
    function Description: string; override;
  end;

  { Rows ARow0 .. ARow1: every cell of a row as wide as its others (CreateDistribute; not in a
    table with merged cells), or each row's cells widened or narrowed in proportion to make the
    row AWidthTwips wide (CreateFit). The row's start stays. }
  TTyRichSetRowWidths = class(TTyRichTablePropsCommand)
  public
    constructor CreateDistribute(ATablePos: TTyRichPos; ARow0, ARow1: Integer);
    constructor CreateFit(ATablePos: TTyRichPos; ARow0, ARow1, AWidthTwips: Integer);
    function Description: string; override;
  end;

  { How a new link's text looks: underlined, and coloured - rllTheme in the automatic colour,
    which the control paints in its theme's link colour (a file keeps no colour for it: in
    Word such a link is the text's own colour); rllWordBlue in Word's link blue
    (CTyRichLinkWordBlue), a colour of the text's own that every program shows. Text that has
    a colour of its own keeps it with either look, as in Word. }
  TTyRichLinkLook = (rllTheme, rllWordBlue);

  { A link (a HYPERLINK field the model owns: TTyRichFieldMark.CreateOwned) made at APos.
    ALen > 0 and AText '': the ALen characters there become the link's text, as they are,
    given the look ALook (a colour of the text's own stays). AText given: it goes in place of those characters (none for ALen
    0), in the format typed at APos with the look. Neither: AURL itself is the text. The
    instruction is TyRichLinkInstruction(AURL); the marks take the format typed at APos (so
    text typed beside the link is not the link's). One undo step; an undo puts back exactly
    what was there. Refused (CanExecute False, nothing changes): AURL empty or '#'; a paragraph
    separator in AURL or AText; a range that reaches past its paragraph's end, holds a
    field's mark (a link is never made around another field), or has an end inside a field's
    result; a place where the text cannot change (TTyRichDocument.CanChange). }
  TTyRichInsertLink = class(TTyRichCommand)
  private
    FPos, FLen: TTyRichPos;
    FURL, FText: UTF8String;
    FLook: TTyRichLinkLook;
    FOpen, FClose: TTyRichFieldMark;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(APos, ALen: TTyRichPos; const AURL, AText: string;
      ALook: TTyRichLinkLook);
    destructor Destroy; override;
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); override;
  end;

  { The field whose open mark is at AFieldPos becomes a link to AURL: with AText '' its
    content stays as it is (its formats, pictures, the fields in it) and only its marks are
    new; with AText the whole field is replaced by a link holding AText, in the format of the
    first text of the old result (the look the link had). The new instruction is the old one
    with its target and its place (\l) those of AURL (TyRichReplaceLinkAddress): its other
    switches (\o "tip", \t "_blank", ...) stay as they were. One undo step. Refused (CanExecute
    False): no field's open mark at AFieldPos; AURL empty or '#'; a paragraph separator in
    AURL or AText; a field inside another field's result, or where the text cannot change. }
  TTyRichSetLink = class(TTyRichCommand)
  private
    FPos: TTyRichPos;
    FURL, FText: UTF8String;
    FOpen, FClose: TTyRichFieldMark;
    FMade: Boolean;
    procedure MakeInstruction(ADoc: TTyRichDocument);
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(AFieldPos: TTyRichPos; const AURL, AText: string);
    destructor Destroy; override;
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); override;
  end;

  { The field whose open mark is at AFieldPos stops being one: its two marks go, its content
    stays - text, pictures, the fields in it, its formats but the look a link is given, which
    goes with the link as in Word: the underline, a link colour (TyRichIsLinkColor) back to
    automatic, a character style (\csN, Word's Hyperlink style); any other colour and every
    other format stay. One undo step. Refused (CanExecute False): no field's open mark at AFieldPos; a field
    inside another field's result, or where the text cannot change. }
  TTyRichRemoveLink = class(TTyRichCommand)
  private
    FPos: TTyRichPos;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(AFieldPos: TTyRichPos);
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
  end;

  { A bookmark named AName over the ALen characters at APos (0: a place): its start mark
    before them, its end mark after them (TTyRichBookmarkMark.CreateNew, Word's syntax). A
    bookmark of that name already in the document (case does not matter) goes first, as in
    Word. One undo step. Refused (CanExecute False): an empty name, the range out of the text,
    either end of it in a field's result or where the text cannot change (CanChange). }
  TTyRichAddBookmark = class(TTyRichCommand)
  private
    FPos, FLen: TTyRichPos;
    FName: UTF8String;
    FStart, FEnd: TTyRichBookmarkMark;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(APos, ALen: TTyRichPos; const AName: string);
    destructor Destroy; override;
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); override;
  end;

  { The bookmark named AName goes: its two marks, nothing of its text. One undo step. Refused
    (CanExecute False): no such bookmark, a mark of it where the text cannot change. }
  TTyRichDeleteBookmark = class(TTyRichCommand)
  private
    FName: UTF8String;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(const AName: string);
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
  end;

  { The bookmark named AOld is named ANew: its two marks made again with the new name, in
    their places. One undo step. Refused (CanExecute False): no bookmark AOld, another
    bookmark named ANew already, an empty ANew, a mark where the text cannot change. }
  TTyRichRenameBookmark = class(TTyRichCommand)
  private
    FOld, FNew: UTF8String;
    FStart, FEnd: TTyRichBookmarkMark;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(const AOld, ANew: string);
    destructor Destroy; override;
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
    function Description: string; override;
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); override;
  end;

const
  // how much deeper a list level's indent is than the one above it (a half inch, Word's)
  CTyRichListLevelIndent = 360;
  { Word's link blue (RGB 05 63 C1), the colour rllWordBlue gives a link's text. }
  CTyRichLinkWordBlue = TColor($C16305);
  { The other colours a link's text has in files: the classic link blue (RGB 00 00 FF) and the
    Hyperlink colour of Word's current theme (RGB 46 78 86). }
  CTyRichLinkClassicBlue = TColor($FF0000);
  CTyRichLinkThemeBlue = TColor($867846);

{ AColor is a link's colour (one of the three above): what TTyRichRemoveLink takes back to the
  automatic colour with the link. }
function TyRichIsLinkColor(AColor: TColor): Boolean;

{ A HYPERLINK field's instruction for AURL, as Word writes one: "#name" is a place in the
  document (HYPERLINK \l "name"), "target#name" a place in a target (HYPERLINK "target"
  \l "name"), anything else a target (HYPERLINK "target"); \ and " in an argument written
  \\ and \" (the field code's own escapes). }
function TyRichLinkInstruction(const AURL: UTF8String): UTF8String;
{ AOld, a HYPERLINK field's instruction, with its target and its place (\l and its argument)
  those of AURL (as TyRichLinkInstruction reads AURL): every other switch and argument and
  the spaces between them kept byte for byte, in their places; a target or a \l AURL has and
  AOld has not put in where Word writes them (the target after HYPERLINK, \l after the
  target), one AOld has and AURL has not taken out. '' when AOld is no HYPERLINK instruction
  this can read (a quote not closed). }
function TyRichReplaceLinkAddress(const AOld, AURL: UTF8String): UTF8String;

function TyRichRange(APos, ALen: TTyRichPos): TTyRichRange;
{ Why ACmd, a built-in command whose CanExecute said no, was refused by ADoc's rules: the
  insert and delete commands by their place (TTyRichDocument.ChangeRefusal: a row that holds
  a nested table, a field's result), an insert of a field's mark alone and the format
  commands by fields (rcrField: a range of field results only). rcrNone for any other
  command: its own reasons. }
function TyRichCommandRefusal(ADoc: TTyRichDocument; ACmd: TTyRichCommand): TTyRichChangeRefusal;
function TyRichTableEdit(AKind: TTyRichTableEditKind; APos: TTyRichPos; AIndex: Integer;
  ARows: Integer = 0; ACols: Integer = 0; AWidth: Integer = 0): TTyRichTableEdit;

implementation

uses
  Generics.Collections, LazUTF8, tyControls.StrConsts, tyControls.RichEdit.Bookmarks,
  tyControls.RichEdit.RtfRead;

function TyRichRange(APos, ALen: TTyRichPos): TTyRichRange;
begin
  Result.Pos := APos;
  Result.Len := ALen;
end;

function HasSeparator(const S: UTF8String): Boolean;
var
  i: Integer;
begin
  for i := 1 to Length(S) do
    if S[i] in [#10, #13] then Exit(True);
  Result := False;
end;

{ ---- TTyRichInsertText ---- }

constructor TTyRichInsertText.Create(APos: TTyRichPos; const AText: UTF8String;
  AFormat: TTyCharFormatId; AMergeable: Boolean);
begin
  inherited Create;
  SetLength(FPos, 1);
  SetLength(FTexts, 1);
  SetLength(FFormats, 1);
  FPos[0] := APos;
  FTexts[0] := AText;
  FFormats[0] := AFormat;
  FTyping := AMergeable and (AText <> '') and not HasSeparator(AText);
end;

function TTyRichInsertText.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  // (asked before the first run, when there is one insert; a redo replays what ran)
  Result := ADoc.CanChange(FPos[0], 0);
end;

procedure TTyRichInsertText.DoExecute(ADoc: TTyRichDocument);
var
  i: Integer;
begin
  // a merged run of typing is replayed insert by insert, as it was typed
  for i := 0 to High(FPos) do InsertText(ADoc, FPos[i], FTexts[i], FFormats[i]);
end;

function TTyRichInsertText.TryMerge(ANext: TTyRichCommand): Boolean;
var
  n: TTyRichInsertText;
  i, k: Integer;
begin
  Result := FTyping and (ANext is TTyRichInsertText) and TTyRichInsertText(ANext).FTyping;
  if not Result then Exit;
  n := TTyRichInsertText(ANext);
  k := Length(FPos);
  SetLength(FPos, k + Length(n.FPos));
  SetLength(FTexts, k + Length(n.FPos));
  SetLength(FFormats, k + Length(n.FPos));
  for i := 0 to High(n.FPos) do
  begin
    FPos[k + i] := n.FPos[i];
    FTexts[k + i] := n.FTexts[i];
    FFormats[k + i] := n.FFormats[i];
  end;
  TakeOver(ANext);
end;

function TTyRichInsertText.Description: string;
begin
  if FTyping then Result := rsRichUndoTyping else Result := rsRichUndoInsertText;
end;

function TTyRichInsertText.MemSize: Int64;
var
  i: Integer;
begin
  Result := inherited MemSize + Length(FPos) * (SizeOf(TTyRichPos) + SizeOf(Pointer) +
    SizeOf(TTyCharFormatId));
  for i := 0 to High(FTexts) do Inc(Result, Length(FTexts[i]));
end;

{ ---- TTyRichDelete ---- }

constructor TTyRichDelete.Create(APos, ALen: TTyRichPos);
begin
  inherited Create;
  FPos := APos;
  FLen := ALen;
end;

function TTyRichDelete.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := ADoc.CanChange(FPos, FLen);
end;

procedure TTyRichDelete.DoExecute(ADoc: TTyRichDocument);
begin
  DeleteRange(ADoc, FPos, FLen);
end;

function TTyRichDelete.Description: string;
begin
  Result := rsRichUndoDelete;
end;

{ ---- TTyRichSetCharFormat ---- }

constructor TTyRichSetCharFormat.Create(const ARange: TTyRichRange; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat; AKeepNone: TTyCharFormatMask);
begin
  inherited Create;
  FRange := ARange;
  FMask := AMask;
  FValue := AValue;
  FKeepNone := AKeepNone;
end;

procedure TTyRichSetCharFormat.DoExecute(ADoc: TTyRichDocument);
begin
  ApplyCharFormat(ADoc, FRange.Pos, FRange.Len, FMask, FValue, FKeepNone);
end;

function TTyRichSetCharFormat.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := not ADoc.FieldOnly(FRange.Pos, FRange.Len);
end;

function TTyRichSetCharFormat.Description: string;
begin
  Result := rsRichUndoCharFormat;
end;

{ ---- TTyRichSetParaFormat ---- }

constructor TTyRichSetParaFormat.Create(AFirstPara, ALastPara: Integer;
  AMask: TTyParaFormatMask; const AValue: TTyParaFormat);
begin
  inherited Create;
  FFirst := AFirstPara;
  FLast := ALastPara;
  FMask := AMask;
  FValue := AValue;
  // a copy: the caller's tab array must not change what redo sets
  FValue.Tabs := Copy(AValue.Tabs);
end;

procedure TTyRichSetParaFormat.DoExecute(ADoc: TTyRichDocument);
var
  rest: TTyParaFormatMask;
  goOn: TTyParaFormat;
  k, i: Integer;
begin
  if not (pffListRestart in FMask) then
  begin
    ApplyParaFormat(ADoc, FFirst, FLast, FMask, FValue);
    Exit;
  end;
  { A start given to the paragraphs: the first list item among them begins its list there,
    the others go on - each part with the rest of the mask. The first item: the first
    paragraph where the mask makes every paragraph an item, else the first that is one. }
  rest := FMask - [pffListRestart] + [pffListStart];
  goOn := FValue;
  goOn.List.StartAt := 0;
  k := -1;
  if ((pffList in FMask) or (pffListKind in FMask)) and (FValue.List.Kind <> lkNone) then
    k := FFirst
  else if not (((pffList in FMask) or (pffListKind in FMask)) and (FValue.List.Kind = lkNone)) then
    for i := FFirst to FLast do
      if ADoc.Formats.ParaFormat(ADoc.ParaFormatOf(i)).List.Kind <> lkNone then
      begin
        k := i;
        Break;
      end;
  if (k < 0) or (FValue.List.StartAt <= 0) then
  begin
    ApplyParaFormat(ADoc, FFirst, FLast, rest, goOn);
    Exit;
  end;
  if k > FFirst then ApplyParaFormat(ADoc, FFirst, k - 1, rest, goOn);
  ApplyParaFormat(ADoc, k, k, rest, FValue);
  if k < FLast then ApplyParaFormat(ADoc, k + 1, FLast, rest, goOn);
end;

function TTyRichSetParaFormat.CanExecute(ADoc: TTyRichDocument): Boolean;
var
  i: Integer;
begin
  Result := True;
  // (out of range: the primitive's error)
  if (FFirst < 0) or (FLast >= ADoc.Text.ParaCount) or (FFirst > FLast) then Exit;
  // one paragraph that ends outside every field is enough: it is read first
  for i := FFirst to FLast do
    if not ADoc.ParaEndsInField(i) then Exit;
  Result := False;
end;

function TTyRichSetParaFormat.Description: string;
begin
  Result := rsRichUndoParaFormat;
end;

{ ---- TTyRichChangeListLevel ---- }

constructor TTyRichChangeListLevel.Create(AFirstPara, ALastPara, ADelta: Integer);
begin
  inherited Create;
  FFirst := AFirstPara;
  FLast := ALastPara;
  FDelta := ADelta;
end;

procedure TTyRichChangeListLevel.DoExecute(ADoc: TTyRichDocument);
var
  k, e, lvl: Integer;
  id: TTyParaFormatId;
  f: TTyParaFormat;
begin
  k := FFirst;
  while k <= FLast do
  begin
    // a run of paragraphs of one format: one value for them all
    id := ADoc.ParaFormatOf(k);
    e := k;
    while (e < FLast) and (ADoc.ParaFormatOf(e + 1) = id) do Inc(e);
    f := ADoc.Formats.ParaFormat(id);
    if f.List.Kind <> lkNone then
    begin
      lvl := f.List.Level + FDelta;
      if lvl < 0 then lvl := 0;
      if lvl > 8 then lvl := 8;
      if lvl <> f.List.Level then
      begin
        f.LeftIndent := f.LeftIndent + (lvl - f.List.Level) * CTyRichListLevelIndent;
        if f.LeftIndent < 0 then f.LeftIndent := 0;
        f.List.Level := lvl;
        ApplyParaFormat(ADoc, k, e, [pffListLevel, pffLeftIndent], f);
      end;
    end;
    k := e + 1;
  end;
end;

function TTyRichChangeListLevel.CanExecute(ADoc: TTyRichDocument): Boolean;
var
  i: Integer;
begin
  Result := True;
  if (FFirst < 0) or (FLast >= ADoc.Text.ParaCount) or (FFirst > FLast) then Exit;
  for i := FFirst to FLast do
    if not ADoc.ParaEndsInField(i) then Exit;
  Result := False;
end;

function TTyRichChangeListLevel.Description: string;
begin
  Result := rsRichUndoParaFormat;
end;

{ ---- TTyRichInsertObject ---- }

constructor TTyRichInsertObject.Create(APos: TTyRichPos; AObject: TTyRichObject;
  AFormat: TTyCharFormatId);
begin
  inherited Create;
  if AObject = nil then
    raise ETyRichModel.Create('TTyRichInsertObject needs an object');
  FPos := APos;
  FObject := AObject;
  FFormat := AFormat;
  FObject.AddRef;
end;

destructor TTyRichInsertObject.Destroy;
begin
  // the paragraph values that use the object hold their own references
  if FObject <> nil then FObject.Release;
  inherited Destroy;
end;

function TTyRichInsertObject.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  // (a field's mark goes in only with its field: InsertObject raises for one)
  Result := not (FObject is TTyRichFieldMark) and ADoc.CanChange(FPos, 0);
end;

procedure TTyRichInsertObject.DoExecute(ADoc: TTyRichDocument);
begin
  InsertObject(ADoc, FPos, FObject, FFormat);
end;

function TTyRichInsertObject.Description: string;
begin
  Result := rsRichUndoInsertObject;
end;

procedure TTyRichInsertObject.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
begin
  inherited GatherObjects(AList, ACount);
  if ACount = Length(AList) then SetLength(AList, ACount * 2 + 4);
  AList[ACount] := FObject;
  Inc(ACount);
end;

{ ---- TTyRichInsertPicture ---- }

class function TTyRichInsertPicture.PictureOf(AGraphic: TGraphic; AWidthTwips,
  AHeightTwips: Integer): TTyRichPicture;
var
  st: TBytesStream;
  png: TPortableNetworkGraphic;
  fmt: TTyRichPictureFormat;
  bytes: TBytes;
  w, h: Integer;
begin
  if (AGraphic = nil) or AGraphic.Empty or (AGraphic.Width <= 0) or (AGraphic.Height <= 0) then
    raise ETyRichModel.Create('TTyRichInsertPicture needs a picture');
  if (AWidthTwips < 0) or (AHeightTwips < 0) then
    raise ETyRichModel.CreateFmt('A picture cannot be shown %d x %d twips',
      [AWidthTwips, AHeightTwips]);
  st := TBytesStream.Create;
  try
    // a PNG and a JPEG as their SaveToStream gives them; anything else as PNG
    if AGraphic is TPortableNetworkGraphic then
    begin
      AGraphic.SaveToStream(st);
      fmt := rpfPng;
    end
    else if AGraphic is TJPEGImage then
    begin
      AGraphic.SaveToStream(st);
      fmt := rpfJpeg;
    end
    else
    begin
      png := TPortableNetworkGraphic.Create;
      try
        png.Assign(AGraphic);
        png.SaveToStream(st);
      finally
        png.Free;
      end;
      fmt := rpfPng;
    end;
    bytes := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
  end;
  // its pixels at 96 dpi (15 twips a pixel); one side given: the other in proportion
  w := AWidthTwips;
  h := AHeightTwips;
  if (w = 0) and (h = 0) then
  begin
    w := AGraphic.Width * 15;
    h := AGraphic.Height * 15;
  end
  else if w = 0 then
    w := Round(h * AGraphic.Width / AGraphic.Height)
  else if h = 0 then
    h := Round(w * AGraphic.Height / AGraphic.Width);
  if w < 1 then w := 1;
  if h < 1 then h := 1;
  Result := TTyRichPicture.Create(fmt, bytes, w, h);
end;

class function TTyRichInsertPicture.PictureOfList(AImages: TCustomImageList; AIndex,
  AWidthTwips, AHeightTwips: Integer): TTyRichPicture;
var
  bmp: TBitmap;
begin
  if (AImages = nil) or (AIndex < 0) or (AIndex >= AImages.Count) then
    raise ETyRichModel.CreateFmt('No image %d in the image list', [AIndex]);
  bmp := TBitmap.Create;
  try
    // its alpha with it (an image list's bitmaps are 32-bit)
    AImages.GetBitmap(AIndex, bmp);
    Result := PictureOf(bmp, AWidthTwips, AHeightTwips);
  finally
    bmp.Free;
  end;
end;

constructor TTyRichInsertPicture.Create(APos: TTyRichPos; AGraphic: TGraphic; AWidthTwips,
  AHeightTwips: Integer; AFormat: TTyCharFormatId);
begin
  inherited Create(APos, PictureOf(AGraphic, AWidthTwips, AHeightTwips), AFormat);
end;

constructor TTyRichInsertPicture.Create(APos: TTyRichPos; AImages: TCustomImageList;
  AIndex: Integer; AWidthTwips, AHeightTwips: Integer; AFormat: TTyCharFormatId);
begin
  inherited Create(APos, PictureOfList(AImages, AIndex, AWidthTwips, AHeightTwips), AFormat);
end;

function TTyRichInsertPicture.Description: string;
begin
  Result := rsRichUndoInsertPicture;
end;

{ ---- TTyRichChangeSettings ---- }

constructor TTyRichChangeSettings.Create(const ASettings: TTyRichDocSettings);
begin
  inherited Create;
  FSettings := ASettings;
end;

procedure TTyRichChangeSettings.DoExecute(ADoc: TTyRichDocument);
begin
  ChangeSettings(ADoc, FSettings);
end;

function TTyRichChangeSettings.Description: string;
begin
  Result := rsRichUndoSettings;
end;

{ ---- TTyRichResizeObject ---- }

constructor TTyRichResizeObject.Create(APos: TTyRichPos; AWidthTwips, AHeightTwips: Integer);
begin
  inherited Create;
  FPos := APos;
  FWidth := AWidthTwips;
  FHeight := AHeightTwips;
end;

destructor TTyRichResizeObject.Destroy;
begin
  // the paragraph values that use it hold their own references
  if FNew <> nil then FNew.Release;
  inherited Destroy;
end;

function TTyRichResizeObject.CanExecute(ADoc: TTyRichDocument): Boolean;
var
  o: TTyRichObject;
begin
  Result := False;
  if (FWidth <= 0) or (FHeight <= 0) then Exit;
  // (asked outside a command's run: the object is read and used in one scope)
  ADoc.BeginRead;
  try
    o := ADoc.ObjectAt(FPos);
    Result := (o <> nil) and o.CanResize and ADoc.CanChange(FPos, 0);
  finally
    ADoc.EndRead;
  end;
end;

procedure TTyRichResizeObject.DoExecute(ADoc: TTyRichDocument);
var
  o: TTyRichObject;
  w, h: Integer;
begin
  if FNew = nil then
  begin
    o := ADoc.ObjectAt(FPos);
    if (o = nil) or not o.CanResize then
      raise ETyRichModel.CreateFmt('No object that can be resized at %d', [FPos]);
    // already that size: nothing to do, and no step
    if o.DisplaySize(w, h) and (w = FWidth) and (h = FHeight) then Exit;
    FNew := o.Resized(FWidth, FHeight);
    if FNew = nil then
      raise ETyRichModel.CreateFmt('%s made no resized object', [o.ClassName]);
    FNew.AddRef;
  end;
  ReplaceObject(ADoc, FPos, FNew);
end;

function TTyRichResizeObject.Description: string;
begin
  Result := rsRichUndoResizeObject;
end;

procedure TTyRichResizeObject.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
begin
  inherited GatherObjects(AList, ACount);
  if FNew = nil then Exit;
  if ACount = Length(AList) then SetLength(AList, ACount * 2 + 4);
  AList[ACount] := FNew;
  Inc(ACount);
end;

type
  // (the primitives, for the helpers of the commands below)
  TTyRichCommandAccess = class(TTyRichCommand);

{ A bookmark that came in with [APos, APos + ALen) - a paste's, a copy's - goes again (its
  marks; its text stays) when the document has its name outside that range already, or when
  only one of its ends came in: Word's way with a pasted bookmark, which leaves no name twice
  and no lone end. A moved one (its name nowhere else now) stays. ACmd's records. How many
  marks went. }
function DropCopiedBookmarks(ACmd: TTyRichCommand; ADoc: TTyRichDocument;
  APos, ALen: TTyRichPos): Integer;
type
  TFound = record
    Pos: TTyRichPos;
    Kind: TTyRichBookmarkKind;
    Key, Name: UTF8String;
  end;
var
  found: array of TFound;
  n, i, j, k, last: Integer;
  ps, p, q: TTyRichPos;
  runs: TTyRunArray;
  m: TTyRichBookmarkMark;
  counts: specialize TDictionary<UTF8String, Int64>;
  drop: specialize TDictionary<UTF8String, Boolean>;
  v: Int64;
  gone: Boolean;
begin
  Result := 0;
  if (ALen <= 0) or (APos < 0) or (APos + ALen > ADoc.Text.Length) then Exit;
  found := nil;
  n := 0;
  k := ADoc.Text.ParaOfPos(APos);
  last := ADoc.Text.ParaOfPos(APos + ALen - 1);
  for i := k to last do
  begin
    ps := ADoc.Text.ParaStart(i);
    runs := ADoc.RunsOf(i);
    for j := 0 to High(runs) do
      if runs[j].Obj is TTyRichBookmarkMark then
      begin
        p := ps + runs[j].Start;
        if (p < APos) or (p >= APos + ALen) then Continue;
        m := TTyRichBookmarkMark(runs[j].Obj);
        if n = Length(found) then SetLength(found, n * 2 + 4);
        found[n].Pos := p;
        found[n].Kind := m.Kind;
        found[n].Name := m.Name;
        found[n].Key := UTF8UpperCase(m.Name);
        Inc(n);
      end;
  end;
  if n = 0 then Exit;
  counts := specialize TDictionary<UTF8String, Int64>.Create;
  drop := specialize TDictionary<UTF8String, Boolean>.Create;
  try
    for i := 0 to n - 1 do
    begin
      if not counts.TryGetValue(found[i].Key, v) then v := 0;
      if found[i].Kind = rbmStart then Inc(v, Int64(1) shl 32) else Inc(v);
      counts.AddOrSetValue(found[i].Key, v);
    end;
    for i := 0 to n - 1 do
    begin
      if drop.ContainsKey(found[i].Key) then Continue;
      v := counts[found[i].Key];
      // one end alone came in
      gone := (v shr 32) <> (v and $FFFFFFFF);
      if not gone then
      begin
        // the name elsewhere in the document: an end of it before the range, or after it
        p := TyRichFindBookmarkMark(ADoc, rbmStart, found[i].Name, 0);
        if (p >= 0) and (p >= APos) and (p < APos + ALen) then
          p := TyRichFindBookmarkMark(ADoc, rbmStart, found[i].Name, APos + ALen);
        q := TyRichFindBookmarkMark(ADoc, rbmEnd, found[i].Name, 0);
        if (q >= 0) and (q >= APos) and (q < APos + ALen) then
          q := TyRichFindBookmarkMark(ADoc, rbmEnd, found[i].Name, APos + ALen);
        gone := (p >= 0) or (q >= 0);
      end;
      if gone then drop.Add(found[i].Key, True);
    end;
    // the last first: the places before stay where they are
    for i := n - 1 downto 0 do
      if drop.ContainsKey(found[i].Key) then
      begin
        TTyRichCommandAccess(ACmd).DeleteObjectAt(ADoc, found[i].Pos);
        Inc(Result);
      end;
  finally
    drop.Free;
    counts.Free;
  end;
end;

{ ---- TTyRichInsertFragment ---- }

constructor TTyRichInsertFragment.Create(APos: TTyRichPos; ASource: TTyRichDocument;
  AEndsWithParagraph: Boolean; AFlatten: Boolean; AFilter: TTyRichFragmentFilter);
begin
  inherited Create;
  if ASource = nil then
  begin
    AFilter.Free;
    raise ETyRichModel.Create('TTyRichInsertFragment needs a source');
  end;
  FPos := APos;
  FSource := ASource;
  FFilter := AFilter;
  FEnds := AEndsWithParagraph;
  FFlatten := AFlatten;
end;

destructor TTyRichInsertFragment.Destroy;
begin
  // the fragment's values are the target's: the history frees this before its document
  FFragment.Free;
  FSource.Free;
  FFilter.Free;
  inherited Destroy;
end;

function TTyRichInsertFragment.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := ADoc.CanChange(FPos, 0);
end;

procedure TTyRichInsertFragment.DoExecute(ADoc: TTyRichDocument);
begin
  if FFragment = nil then
  begin
    FFragment := TTyRichFragment.Create(ADoc, FPos, FSource, FEnds, FFlatten, FFilter);
    // what was read is in the fragment now: the source (and the bytes it was read from) go
    FreeAndNil(FSource);
    FreeAndNil(FFilter);
  end;
  InsertFragment(ADoc, FPos, FFragment);
  DropCopiedBookmarks(Self, ADoc, FPos, FFragment.CharCount);
end;

function TTyRichInsertFragment.Description: string;
begin
  Result := rsRichUndoPaste;
end;

function TTyRichInsertFragment.MemSize: Int64;
begin
  Result := inherited MemSize;
  if FFragment <> nil then Inc(Result, FFragment.MemSize);
end;

procedure TTyRichInsertFragment.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
begin
  inherited GatherObjects(AList, ACount);
  if FFragment <> nil then FFragment.GatherObjects(AList, ACount);
end;

{ ---- TTyRichRangeTransfer ---- }

constructor TTyRichRangeTransfer.Create(AFrom, ALen, ATo: TTyRichPos);
begin
  inherited Create;
  FFrom := AFrom;
  FLen := ALen;
  FTo := ATo;
  FCut := ALen;
end;

destructor TTyRichRangeTransfer.Destroy;
begin
  // the fragment's values are the document's: the history frees this before its document
  FFragment.Free;
  inherited Destroy;
end;

function TTyRichRangeTransfer.CanExecute(ADoc: TTyRichDocument): Boolean;
var
  s, n, len: TTyRichPos;
begin
  Result := False;
  len := ADoc.Text.Length;
  if (FLen <= 0) or (FFrom < 0) or (FFrom > len - FLen) or (FTo < 0) or (FTo > len) then Exit;
  if Moves then
  begin
    if (FTo >= FFrom) and (FTo <= FFrom + FLen) then Exit;
  end
  else if (FTo > FFrom) and (FTo < FFrom + FLen) then
    Exit;
  // (asked outside a command's run: what is read is used in one scope)
  ADoc.BeginRead;
  try
    if not ADoc.CanChange(FTo, 0) then Exit;
    if Moves then
    begin
      s := FFrom;
      n := FLen;
      if not ADoc.UserRangeAllowed(s, n) or (n <= 0) or not ADoc.CanChange(s, n) then Exit;
    end;
    Result := True;
  finally
    ADoc.EndRead;
  end;
end;

procedure TTyRichRangeTransfer.DoExecute(ADoc: TTyRichDocument);
var
  content: TTyRichRangeContent;
  s, n, at: TTyRichPos;
begin
  if FFragment = nil then
  begin
    if Moves then
    begin
      // what a user's cut of the range deletes (the separator before a table kept)
      s := FFrom;
      n := FLen;
      ADoc.BeginRead;
      try
        if not ADoc.UserRangeAllowed(s, n) or (n <= 0) then
          raise ETyRichModel.CreateFmt('The range %d+%d cannot be moved', [FFrom, FLen]);
      finally
        ADoc.EndRead;
      end;
      FCut := n;
    end;
    // read before anything changes: a move deletes what it takes
    // (into a cell, a field over a paragraph's end loses its marks: the fragment needs the text)
    content := TTyRichRangeContent.Create(ADoc, FFrom, FCut, not Moves,
      ADoc.CellAt(ADoc.Text.ParaOfPos(FTo)) <> nil);
    try
      at := FTo;
      if Moves then
      begin
        // (the delete keeps the content's own array of the pieces: the pieces are kept once)
        DeleteRange(ADoc, FFrom, FCut, content.TextPieces);
        if at > FFrom then Dec(at, FCut);
      end;
      FFragment := TTyRichFragment.CreateOfContent(ADoc, at, content, Moves);
      FAt := at;
    finally
      content.Free;
    end;
  end
  else if Moves then
    // again (a redo), on the same text: the same pieces, the fragment's array
    DeleteRange(ADoc, FFrom, FCut, FFragment.BodyPieces);
  InsertFragment(ADoc, FAt, FFragment);
  // (a bookmark's marks left out: what is there of the content now)
  FPlaced := TyRichRange(FAt, FFragment.CharCount -
    DropCopiedBookmarks(Self, ADoc, FAt, FFragment.CharCount));
end;

function TTyRichRangeTransfer.MemSize: Int64;
begin
  Result := inherited MemSize;
  if FFragment = nil then Exit;
  Inc(Result, FFragment.MemSize);
  { A move that ran: its delete's record and its fragment hold one array of the pieces
    between them, counted once. }
  if Moves and (RecordCount > 0) then
    Dec(Result, Int64(Length(FFragment.BodyPieces.Pieces)) * SizeOf(TTyRichPiece));
end;

procedure TTyRichRangeTransfer.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
begin
  inherited GatherObjects(AList, ACount);
  if FFragment <> nil then FFragment.GatherObjects(AList, ACount);
end;

function TTyRichCopy.Moves: Boolean;
begin
  Result := False;
end;

function TTyRichCopy.Description: string;
begin
  Result := rsRichUndoCopy;
end;

function TTyRichMove.Moves: Boolean;
begin
  Result := True;
end;

function TTyRichMove.Description: string;
begin
  Result := rsRichUndoMove;
end;

{ ---- TTyRichCompositeCommand ---- }

constructor TTyRichCompositeCommand.Create(const ADescription: string);
begin
  inherited Create;
  FItems := TFPList.Create;
  FDescription := ADescription;
end;

constructor TTyRichCompositeCommand.CreateExecuted(const ADescription: string;
  const ACommands: array of TTyRichCommand);
var
  i: Integer;
begin
  Create(ADescription);
  for i := 0 to High(ACommands) do
  begin
    FItems.Add(ACommands[i]);
    AdoptChange(ACommands[i]);
  end;
  FDone := FItems.Count;
end;

destructor TTyRichCompositeCommand.Destroy;
var
  i: Integer;
begin
  if FItems <> nil then
    for i := FItems.Count - 1 downto 0 do TTyRichCommand(FItems[i]).Free;
  FItems.Free;
  inherited Destroy;
end;

function TTyRichCompositeCommand.GetItem(AIndex: Integer): TTyRichCommand;
begin
  Result := TTyRichCommand(FItems[AIndex]);
end;

procedure TTyRichCompositeCommand.Add(ACmd: TTyRichCommand);
begin
  if ACmd = nil then
    raise ETyRichModel.Create('A composite command needs its parts');
  if FDone > 0 then
  begin
    ACmd.Free;
    raise ETyRichModel.Create('A composite command cannot grow once it has run');
  end;
  FItems.Add(ACmd);
end;

function TTyRichCompositeCommand.Count: Integer;
begin
  Result := FItems.Count;
end;

{ Why a built-in command that asked CanExecute was refused - the document's rule its place
  meets; rcrNone for any other command (its own reason). }
function PartRefusal(ADoc: TTyRichDocument; C: TTyRichCommand): TTyRichChangeRefusal;
begin
  Result := rcrNone;
  if C is TTyRichInsertText then
    Result := ADoc.ChangeRefusal(TTyRichInsertText(C).FPos[0], 0)
  else if C is TTyRichDelete then
    Result := ADoc.ChangeRefusal(TTyRichDelete(C).FPos, TTyRichDelete(C).FLen)
  else if C is TTyRichInsertObject then
  begin
    if TTyRichInsertObject(C).FObject is TTyRichFieldMark then Result := rcrField
    else Result := ADoc.ChangeRefusal(TTyRichInsertObject(C).FPos, 0);
  end
  else if C is TTyRichInsertFragment then
    Result := ADoc.ChangeRefusal(TTyRichInsertFragment(C).FPos, 0)
  else if (C is TTyRichSetCharFormat) or (C is TTyRichSetParaFormat) then
    Result := rcrField;
  // (a row's refusal of an insert that is not told by its place: as before, the row's)
  if (Result = rcrNone) and ((C is TTyRichInsertText) or (C is TTyRichDelete) or
     (C is TTyRichInsertObject) or (C is TTyRichInsertFragment)) then
    Result := rcrFixedRow;
end;

function TyRichCommandRefusal(ADoc: TTyRichDocument; ACmd: TTyRichCommand): TTyRichChangeRefusal;
begin
  Result := PartRefusal(ADoc, ACmd);
end;

procedure TTyRichCompositeCommand.DoExecute(ADoc: TTyRichDocument);
var
  c: TTyRichCommand;
  e: ETyRichRefused;
begin
  FDone := 0;
  while FDone < FItems.Count do
  begin
    c := TTyRichCommand(FItems[FDone]);
    // asked at its turn: the parts before it have changed the document
    if not c.CanExecute(ADoc) then
    begin
      e := ETyRichRefused.CreateFmt(rsRichModelPartRefused, [FDone, c.ClassName]);
      { The built-in text commands ask only CanChange: a row that holds a nested table, or a
        field's result (ChangeRefusal says which); the format commands refuse only a range
        of field results. }
      case PartRefusal(ADoc, c) of
        rcrFixedRow: e.FixedRow := True;
        rcrField: e.Field := True;
      end;
      raise e;
    end;
    ExecuteChild(ADoc, c);
    Inc(FDone);
  end;
end;

procedure TTyRichCompositeCommand.DoUndo(ADoc: TTyRichDocument);
begin
  while FDone > 0 do
  begin
    Dec(FDone);
    UndoChild(ADoc, TTyRichCommand(FItems[FDone]));
  end;
end;

procedure TTyRichCompositeCommand.DoRedo(ADoc: TTyRichDocument);
begin
  FDone := 0;
  while FDone < FItems.Count do
  begin
    RedoChild(ADoc, TTyRichCommand(FItems[FDone]));
    Inc(FDone);
  end;
end;

function TTyRichCompositeCommand.Description: string;
begin
  if FDescription <> '' then
    Result := FDescription
  else if FItems.Count = 1 then
    Result := TTyRichCommand(FItems[0]).Description
  else
    Result := rsRichUndoEdit;
end;

function TTyRichCompositeCommand.MemSize: Int64;
var
  i: Integer;
begin
  Result := inherited MemSize + FItems.Count * SizeOf(Pointer);
  for i := 0 to FItems.Count - 1 do Inc(Result, TTyRichCommand(FItems[i]).MemSize);
end;

procedure TTyRichCompositeCommand.GatherObjects(var AList: TTyRichObjectList;
  var ACount: Integer);
var
  i: Integer;
begin
  inherited GatherObjects(AList, ACount);
  for i := 0 to FItems.Count - 1 do TTyRichCommand(FItems[i]).GatherObjects(AList, ACount);
end;

{ ---- the table commands ---- }

function TyRichTableEdit(AKind: TTyRichTableEditKind; APos: TTyRichPos; AIndex: Integer;
  ARows: Integer; ACols: Integer; AWidth: Integer): TTyRichTableEdit;
begin
  Result := Default(TTyRichTableEdit);
  Result.Kind := AKind;
  Result.Pos := APos;
  Result.Index := AIndex;
  Result.Rows := ARows;
  Result.Cols := ACols;
  Result.Width := AWidth;
end;

destructor TTyRichTableCommand.Destroy;
var
  i: Integer;
begin
  // the paragraph values that use them hold their own references
  for i := 0 to High(FTables) do FTables[i].Release;
  FTables := nil;
  inherited Destroy;
end;

function TTyRichTableCommand.Refusal(ADoc: TTyRichDocument): TTyRichTableRefusal;
begin
  Result := ADoc.TableEditRefusal(FEdit);
end;

function TTyRichTableCommand.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := Refusal(ADoc) = rtrNone;
end;

procedure TTyRichTableCommand.DoExecute(ADoc: TTyRichDocument);
begin
  EditTable(ADoc, FEdit, FTables);
end;

function TTyRichTableCommand.MemSize: Int64;
var
  i: Integer;
begin
  // its records (the old values and tables they keep), and the table it keeps for a redo
  Result := inherited MemSize + Length(FTables) * SizeOf(Pointer);
  for i := 0 to High(FTables) do Inc(Result, FTables[i].MemSize);
end;

constructor TTyRichInsertTable.Create(APos: TTyRichPos; ARows, ACols: Integer; AWidth: Integer);
begin
  inherited Create;
  FEdit := TyRichTableEdit(rtkInsertTable, APos, 0, ARows, ACols, AWidth);
end;

function TTyRichInsertTable.Description: string;
begin
  Result := rsRichUndoInsertTable;
end;

constructor TTyRichInsertRow.Create(ATablePos: TTyRichPos; AIndex: Integer);
begin
  inherited Create;
  FEdit := TyRichTableEdit(rtkInsertRow, ATablePos, AIndex);
end;

function TTyRichInsertRow.Description: string;
begin
  Result := rsRichUndoInsertRow;
end;

constructor TTyRichDeleteRow.Create(ATablePos: TTyRichPos; AIndex: Integer);
begin
  inherited Create;
  FEdit := TyRichTableEdit(rtkDeleteRow, ATablePos, AIndex);
end;

function TTyRichDeleteRow.Description: string;
begin
  Result := rsRichUndoDeleteRow;
end;

constructor TTyRichInsertColumn.Create(ATablePos: TTyRichPos; AIndex: Integer);
begin
  inherited Create;
  FEdit := TyRichTableEdit(rtkInsertColumn, ATablePos, AIndex);
end;

function TTyRichInsertColumn.Description: string;
begin
  Result := rsRichUndoInsertColumn;
end;

constructor TTyRichDeleteColumn.Create(ATablePos: TTyRichPos; AIndex: Integer);
begin
  inherited Create;
  FEdit := TyRichTableEdit(rtkDeleteColumn, ATablePos, AIndex);
end;

function TTyRichDeleteColumn.Description: string;
begin
  Result := rsRichUndoDeleteColumn;
end;

constructor TTyRichInsertGridColumn.Create(ATablePos: TTyRichPos; AX, AWidth: Integer);
begin
  inherited Create;
  FEdit := TyRichTableEdit(rtkInsertGridColumn, ATablePos, 0);
  FEdit.X0 := AX;
  FEdit.X1 := AX;
  FEdit.Width := AWidth;
end;

function TTyRichInsertGridColumn.Description: string;
begin
  Result := rsRichUndoInsertColumn;
end;

constructor TTyRichDeleteGridColumns.Create(ATablePos: TTyRichPos; AX0, AX1: Integer);
begin
  inherited Create;
  FEdit := TyRichTableEdit(rtkDeleteGridColumns, ATablePos, 0);
  FEdit.X0 := AX0;
  FEdit.X1 := AX1;
end;

function TTyRichDeleteGridColumns.Description: string;
begin
  Result := rsRichUndoDeleteColumn;
end;

constructor TTyRichMergeCells.Create(ATablePos: TTyRichPos; ARow0, ARow1, AX0, AX1: Integer);
begin
  inherited Create;
  FEdit := TyRichTableEdit(rtkMergeCells, ATablePos, ARow0);
  FEdit.Row0 := ARow0;
  FEdit.Row1 := ARow1;
  FEdit.X0 := AX0;
  FEdit.X1 := AX1;
end;

function TTyRichMergeCells.Description: string;
begin
  Result := rsRichUndoMergeCells;
end;

constructor TTyRichSplitCell.Create(ATablePos: TTyRichPos; ARow, ACell, ASpanRows, ACols,
  ARows: Integer; const AEdges: array of Integer);
var
  i: Integer;
begin
  inherited Create;
  FEdit := TyRichTableEdit(rtkSplitCell, ATablePos, ACell, ARows, ACols);
  FEdit.Row0 := ARow;
  FEdit.Row1 := ARow + ASpanRows - 1;
  FEdit.SpanRows := ASpanRows;
  SetLength(FEdit.SplitEdges, Length(AEdges));
  for i := 0 to High(AEdges) do FEdit.SplitEdges[i] := AEdges[i];
end;

function TTyRichSplitCell.Description: string;
begin
  Result := rsRichUndoSplitCell;
end;

{ ---- links ---- }

function LinkArgument(const S: UTF8String): UTF8String;
var
  i: Integer;
begin
  Result := '"';
  for i := 1 to Length(S) do
  begin
    if S[i] in ['\', '"'] then Result := Result + '\';
    Result := Result + S[i];
  end;
  Result := Result + '"';
end;

function TyRichLinkInstruction(const AURL: UTF8String): UTF8String;
var
  p: Integer;
begin
  p := Pos('#', AURL);
  if p = 1 then
    Result := 'HYPERLINK \l ' + LinkArgument(Copy(AURL, 2, MaxInt))
  else if (p > 1) and (p < Length(AURL)) then
    Result := 'HYPERLINK ' + LinkArgument(Copy(AURL, 1, p - 1)) + ' \l ' +
      LinkArgument(Copy(AURL, p + 1, MaxInt))
  else
    Result := 'HYPERLINK ' + LinkArgument(AURL);
end;

function TyRichReplaceLinkAddress(const AOld, AURL: UTF8String): UTF8String;
type
  TEdit = record
    A, B: Integer;      // [A, B) of AOld replaced by S
    S: UTF8String;
  end;
var
  i, n, kwEnd, gA, gB, lA, lB, lArgA, lArgB, p, k, j: Integer;
  ta, tb: Integer;
  quoted, bad: Boolean;
  sw: Char;
  target, name: UTF8String;
  edits: array of TEdit;
  e: TEdit;
  extraL: array of TEdit;   // the \l after the first: they go

  function IsSpace(C: Char): Boolean;
  begin
    Result := C in [' ', #9, #10, #13];
  end;

  // the next token's span [ta, tb), as the control's LinkTarget reads one
  function NextToken: Boolean;
  begin
    while (i <= n) and IsSpace(AOld[i]) do Inc(i);
    if i > n then Exit(False);
    ta := i;
    quoted := AOld[i] = '"';
    if quoted then
    begin
      Inc(i);
      while (i <= n) and (AOld[i] <> '"') do
      begin
        if (AOld[i] = '\') and (i < n) and (AOld[i + 1] in ['\', '"']) then Inc(i);
        Inc(i);
      end;
      if i > n then bad := True;
      Inc(i);
    end
    else
      while (i <= n) and not IsSpace(AOld[i]) do Inc(i);
    tb := i;
    if tb > n + 1 then tb := n + 1;
    Result := True;
  end;

  // the span [A, B) with the spaces before it
  function WithSpaces(A, B: Integer): TEdit;
  begin
    while (A > kwEnd) and IsSpace(AOld[A - 1]) do Dec(A);
    Result.A := A;
    Result.B := B;
    Result.S := '';
  end;

  procedure AddEdit(A, B: Integer; const S: UTF8String);
  begin
    SetLength(edits, Length(edits) + 1);
    edits[High(edits)].A := A;
    edits[High(edits)].B := B;
    edits[High(edits)].S := S;
  end;

begin
  Result := '';
  n := Length(AOld);
  i := 1;
  bad := False;
  if not NextToken or quoted or not SameText(Copy(AOld, ta, tb - ta), 'HYPERLINK') then Exit;
  kwEnd := tb;
  gA := -1;
  gB := -1;
  lA := -1;
  lB := -1;
  lArgA := -1;
  lArgB := -1;
  extraL := nil;
  while NextToken do
  begin
    if bad then Exit;
    if not quoted and (tb - ta >= 2) and (AOld[ta] = '\') then
    begin
      sw := LowerCase(AOld[ta + 1]);
      if sw in ['l', 'o', 't'] then
      begin
        p := ta;
        if not NextToken or bad then Exit;
        if sw = 'l' then
          if lA < 0 then
          begin
            lA := p;
            lB := tb;
            lArgA := ta;
            lArgB := tb;
          end
          else
          begin
            SetLength(extraL, Length(extraL) + 1);
            extraL[High(extraL)] := WithSpaces(p, tb);
          end;
      end;
      Continue;
    end;
    if gA < 0 then
    begin
      gA := ta;
      gB := tb;
    end;
  end;
  if bad then Exit;
  // AURL's target and place, as TyRichLinkInstruction reads them
  target := AURL;
  name := '';
  p := Pos('#', AURL);
  if p = 1 then
  begin
    target := '';
    name := Copy(AURL, 2, MaxInt);
  end
  else if (p > 1) and (p < Length(AURL)) then
  begin
    target := Copy(AURL, 1, p - 1);
    name := Copy(AURL, p + 1, MaxInt);
  end;
  edits := nil;
  // the target
  if target <> '' then
  begin
    if gA >= 0 then AddEdit(gA, gB, LinkArgument(target))
    else AddEdit(kwEnd, kwEnd, ' ' + LinkArgument(target));
  end
  else if gA >= 0 then
  begin
    e := WithSpaces(gA, gB);
    AddEdit(e.A, e.B, '');
  end;
  // the place
  if name <> '' then
  begin
    if lA >= 0 then AddEdit(lArgA, lArgB, LinkArgument(name))
    else if (gA >= 0) and (target <> '') then AddEdit(gB, gB, ' \l ' + LinkArgument(name))
    else if target <> '' then
      // (after the target put in after HYPERLINK: one edit with it)
      edits[High(edits)].S := edits[High(edits)].S + ' \l ' + LinkArgument(name)
    else AddEdit(kwEnd, kwEnd, ' \l ' + LinkArgument(name));
  end
  else if lA >= 0 then
  begin
    e := WithSpaces(lA, lB);
    AddEdit(e.A, e.B, '');
  end;
  for k := 0 to High(extraL) do AddEdit(extraL[k].A, extraL[k].B, '');
  { the last first: the places before an edit stay where they are (at one place, what is taken
    out before what is put in: the removal's span is of AOld) }
  for k := 1 to High(edits) do
  begin
    e := edits[k];
    j := k - 1;
    while (j >= 0) and ((edits[j].A < e.A) or ((edits[j].A = e.A) and
      (edits[j].B = edits[j].A) and (e.B > e.A))) do
    begin
      edits[j + 1] := edits[j];
      Dec(j);
    end;
    edits[j + 1] := e;
  end;
  Result := AOld;
  for k := 0 to High(edits) do
    Result := Copy(Result, 1, edits[k].A - 1) + edits[k].S + Copy(Result, edits[k].B, MaxInt);
end;

function LinkAddressOk(const AURL: UTF8String): Boolean;
begin
  Result := (AURL <> '') and (AURL <> '#') and not HasSeparator(AURL);
end;

{ A fresh pair of marks of a link the model owns. }
procedure MakeLinkMarks(const AURL: UTF8String; out AOpen, AClose: TTyRichFieldMark);
var
  id: Int64;
begin
  id := TTyRichFieldMark.NewId;
  AOpen := TTyRichFieldMark.CreateOwned(rfmOpen, id, TyRichLinkInstruction(AURL));
  AClose := TTyRichFieldMark.CreateOwned(rfmClose, id);
  AOpen.AddRef;
  AClose.AddRef;
end;

procedure GatherMarks(AOpen, AClose: TTyRichFieldMark; var AList: TTyRichObjectList;
  var ACount: Integer);
begin
  if ACount + 2 > Length(AList) then SetLength(AList, ACount * 2 + 4);
  AList[ACount] := AOpen;
  AList[ACount + 1] := AClose;
  Inc(ACount, 2);
end;

{ F with a link's look: underlined; with rllWordBlue, Word's link blue where its colour is
  automatic - a colour of the text's own stays (as Word's Hyperlink style under direct
  formatting); rllTheme leaves the colour as it is (automatic is painted the link colour). }
procedure AddLinkLook(var F: TTyCharFormat; ALook: TTyRichLinkLook);
begin
  Include(F.Style, fsUnderline);
  if (ALook = rllWordBlue) and ((F.Color = clDefault) or (F.Color = clNone)) then
    F.Color := CTyRichLinkWordBlue;
end;

{ The format AFormat with a link's look. }
function LookFormat(ADoc: TTyRichDocument; AFormat: TTyCharFormatId;
  ALook: TTyRichLinkLook): TTyCharFormatId;
var
  f: TTyCharFormat;
begin
  f := ADoc.Formats.CharFormat(AFormat);
  AddLinkLook(f, ALook);
  Result := ADoc.Formats.InternChar(f);
end;

{ [APos, APos + ALen) lies in one paragraph and holds no field mark. }
function PlainStretch(ADoc: TTyRichDocument; APos, ALen: TTyRichPos): Boolean;
var
  k, i: Integer;
  ps: Int64;
  runs: TTyRunArray;
begin
  Result := False;
  k := ADoc.Text.ParaOfPos(APos);
  ps := ADoc.Text.ParaStart(k);
  if APos + ALen > ps + ADoc.Text.ParaLength(k) then Exit;
  runs := ADoc.RunsOf(k);
  for i := 0 to High(runs) do
    if (runs[i].Obj is TTyRichFieldMark) and (ps + runs[i].Start >= APos) and
      (ps + runs[i].Start < APos + ALen) then
      Exit;
  Result := True;
end;

{ A whole field at AOpenPos - its open mark there, its close mark found - that may be
  changed as a whole (outside every other field's result, the text changeable). Its close
  mark's position, -1 when not. }
function ChangeableField(ADoc: TTyRichDocument; AOpenPos: TTyRichPos): TTyRichPos;
var
  o: TTyRichObject;
  c: TTyRichPos;
begin
  Result := -1;
  if (AOpenPos < 0) or (AOpenPos >= ADoc.Text.Length) then Exit;
  ADoc.BeginRead;
  try
    o := ADoc.ObjectAt(AOpenPos);
    if not (o is TTyRichFieldMark) or (TTyRichFieldMark(o).Kind <> rfmOpen) then Exit;
    c := ADoc.FieldPartner(AOpenPos);
    if (c < 0) or not ADoc.CanChange(AOpenPos, c + 1 - AOpenPos) then Exit;
    Result := c;
  finally
    ADoc.EndRead;
  end;
end;

constructor TTyRichInsertLink.Create(APos, ALen: TTyRichPos; const AURL, AText: string;
  ALook: TTyRichLinkLook);
begin
  inherited Create;
  FPos := APos;
  FLen := ALen;
  FURL := AURL;
  FText := AText;
  FLook := ALook;
  MakeLinkMarks(FURL, FOpen, FClose);
end;

destructor TTyRichInsertLink.Destroy;
begin
  // the paragraph values that use them hold their own references
  FOpen.Release;
  FClose.Release;
  inherited Destroy;
end;

function TTyRichInsertLink.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := False;
  if not LinkAddressOk(FURL) or HasSeparator(FText) then Exit;
  if (FPos < 0) or (FLen < 0) or (FPos + FLen > ADoc.Text.Length) then Exit;
  ADoc.BeginRead;
  try
    Result := ADoc.CanChange(FPos, 0) and ((FLen = 0) or ADoc.CanChange(FPos, FLen)) and
      PlainStretch(ADoc, FPos, FLen);
  finally
    ADoc.EndRead;
  end;
end;

procedure TTyRichInsertLink.DoExecute(ADoc: TTyRichDocument);
var
  outside: TTyCharFormatId;
  v: TTyCharFormat;
  s: UTF8String;
  n, a, b, ps: TTyRichPos;
  k, i: Integer;
  runs: TTyRunArray;
begin
  // (a redo runs this again on the text an undo put back: the same ids, the same marks)
  s := FText;
  if (s = '') and (FLen = 0) then s := FURL;
  if s <> '' then
  begin
    if FLen > 0 then DeleteRange(ADoc, FPos, FLen);
    outside := ADoc.TypingFormatAt(FPos);
    n := InsertText(ADoc, FPos, s, LookFormat(ADoc, outside, FLook)).NewLen;
  end
  else
  begin
    outside := ADoc.TypingFormatAt(FPos);
    // run by run: each keeps a colour of its own
    k := ADoc.Text.ParaOfPos(FPos);
    ps := ADoc.Text.ParaStart(k);
    runs := ADoc.RunsOf(k);
    for i := 0 to High(runs) do
    begin
      a := ps + runs[i].Start;
      if i < High(runs) then b := ps + runs[i + 1].Start else b := ps + ADoc.Text.ParaLength(k);
      if a < FPos then a := FPos;
      if b > FPos + FLen then b := FPos + FLen;
      if b <= a then Continue;
      v := ADoc.Formats.CharFormat(runs[i].Format);
      AddLinkLook(v, FLook);
      ApplyCharFormat(ADoc, a, b - a, [cffUnderline, cffColor], v);
    end;
    n := FLen;
  end;
  WrapInField(ADoc, FPos, n, FOpen, FClose, outside);
end;

function TTyRichInsertLink.Description: string;
begin
  Result := rsRichUndoInsertLink;
end;

procedure TTyRichInsertLink.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
begin
  inherited GatherObjects(AList, ACount);
  GatherMarks(FOpen, FClose, AList, ACount);
end;

constructor TTyRichSetLink.Create(AFieldPos: TTyRichPos; const AURL, AText: string);
begin
  inherited Create;
  FPos := AFieldPos;
  FURL := AURL;
  FText := AText;
  MakeLinkMarks(FURL, FOpen, FClose);
end;

destructor TTyRichSetLink.Destroy;
begin
  FOpen.Release;
  FClose.Release;
  inherited Destroy;
end;

{ The new open mark's instruction from the old one's (its other switches kept): the first time
  the command runs (a redo runs on the field an undo put back, with the marks made then). }
procedure TTyRichSetLink.MakeInstruction(ADoc: TTyRichDocument);
var
  o: TTyRichObject;
  inst: UTF8String;
  id: Int64;
begin
  if FMade then Exit;
  FMade := True;
  o := ADoc.ObjectAt(FPos);
  if not (o is TTyRichFieldMark) then Exit;
  inst := TyRichReplaceLinkAddress(TyRichFieldInstruction(ADoc, TTyRichFieldMark(o)), FURL);
  if (inst = '') or (inst = FOpen.Instruction) then Exit;
  id := FOpen.Id;
  FOpen.Release;
  FOpen := TTyRichFieldMark.CreateOwned(rfmOpen, id, inst);
  FOpen.AddRef;
end;

function TTyRichSetLink.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := LinkAddressOk(FURL) and not HasSeparator(FText) and
    (ChangeableField(ADoc, FPos) >= 0);
end;

procedure TTyRichSetLink.DoExecute(ADoc: TTyRichDocument);
var
  c, ps: TTyRichPos;
  k, i: Integer;
  runs: TTyRunArray;
  markFmt, textFmt: TTyCharFormatId;
  found: Boolean;
begin
  MakeInstruction(ADoc);
  if FText = '' then
  begin
    ReplaceFieldMarks(ADoc, FPos, FOpen, FClose);
    Exit;
  end;
  c := ChangeableField(ADoc, FPos);
  if c < 0 then raise ETyRichModel.CreateFmt('No field to change at %d', [FPos]);
  // the marks' format and the first text's of the old result (in the open mark's paragraph)
  k := ADoc.Text.ParaOfPos(FPos);
  ps := ADoc.Text.ParaStart(k);
  runs := ADoc.RunsOf(k);
  markFmt := ADoc.TypingFormatAt(FPos);
  textFmt := markFmt;
  found := False;
  for i := 0 to High(runs) do
    if ps + runs[i].Start = FPos then
      markFmt := runs[i].Format    // the open mark's own run
    else if (ps + runs[i].Start > FPos) and (ps + runs[i].Start < c) and
      (runs[i].Obj = nil) then
    begin
      textFmt := runs[i].Format;
      found := True;
      Break;
    end;
  // (a result with no text of its own: the editor's look)
  if not found then textFmt := LookFormat(ADoc, markFmt, rllWordBlue);
  DeleteRange(ADoc, FPos, c + 1 - FPos);
  c := InsertText(ADoc, FPos, FText, textFmt).NewLen;
  WrapInField(ADoc, FPos, c, FOpen, FClose, markFmt);
end;

function TTyRichSetLink.Description: string;
begin
  Result := rsRichUndoEditLink;
end;

procedure TTyRichSetLink.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
begin
  inherited GatherObjects(AList, ACount);
  GatherMarks(FOpen, FClose, AList, ACount);
end;

constructor TTyRichRemoveLink.Create(AFieldPos: TTyRichPos);
begin
  inherited Create;
  FPos := AFieldPos;
end;

function TTyRichRemoveLink.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := ChangeableField(ADoc, FPos) >= 0;
end;

function TyRichIsLinkColor(AColor: TColor): Boolean;
begin
  Result := (AColor = CTyRichLinkWordBlue) or (AColor = CTyRichLinkClassicBlue) or
    (AColor = CTyRichLinkThemeBlue);
end;

{ F without a link's look: no underline, a link colour back to automatic, no character style
  (\csN: a link's text in Word's files carries its Hyperlink style, which brings the look
  back in Word). False: F has none of it. }
function WithoutLinkLook(var F: TTyCharFormat): Boolean;
var
  x: TTyOpaqueAttrs;
  i: Integer;
  s: RawByteString;
begin
  Result := False;
  if fsUnderline in F.Style then
  begin
    Exclude(F.Style, fsUnderline);
    Result := True;
  end;
  if TyRichIsLinkColor(F.Color) then
  begin
    F.Color := clDefault;
    Result := True;
  end;
  x := Default(TTyOpaqueAttrs);
  for i := 0 to F.Extra.Count - 1 do
  begin
    s := F.Extra.Item(i);
    if (Length(s) > 3) and (Copy(s, 1, 3) = '\cs') and (s[4] in ['0'..'9']) then
      Result := True
    else
      x.Add(s);
  end;
  F.Extra := x;
end;

procedure TTyRichRemoveLink.DoExecute(ADoc: TTyRichDocument);
var
  c, e, ps, s, n: TTyRichPos;
  k, last, i: Integer;
  runs: TTyRunArray;
  f: TTyCharFormat;
begin
  c := ChangeableField(ADoc, FPos);
  if c < 0 then raise ETyRichModel.CreateFmt('No field to remove at %d', [FPos]);
  UnwrapField(ADoc, FPos);
  // its text [FPos, c - 1) now: the look a link is given goes with the link, and only that
  e := c - 1;
  if e <= FPos then Exit;
  k := ADoc.Text.ParaOfPos(FPos);
  last := ADoc.Text.ParaOfPos(e);
  while k <= last do
  begin
    ps := ADoc.Text.ParaStart(k);
    runs := ADoc.RunsOf(k);
    for i := 0 to High(runs) do
    begin
      if runs[i].Obj <> nil then Continue;
      s := ps + runs[i].Start;
      if i < High(runs) then n := ps + runs[i + 1].Start else n := ps + ADoc.Text.ParaLength(k);
      if s < FPos then s := FPos;
      if n > e then n := e;
      if n <= s then Continue;
      f := ADoc.Formats.CharFormat(runs[i].Format);
      if WithoutLinkLook(f) then
        ApplyCharFormat(ADoc, s, n - s, [cffUnderline, cffColor, cffExtra], f);
    end;
    Inc(k);
  end;
end;

function TTyRichRemoveLink.Description: string;
begin
  Result := rsRichUndoRemoveLink;
end;

{ ---- bookmarks ---- }

{ The bookmark named AName's two ends, ARight to change: its start's position and its end's
  (-1: none; a bookmark with no end mark). False: none. }
function BookmarkEnds(ADoc: TTyRichDocument; const AName: UTF8String;
  out AStart, AEnd: TTyRichPos): Boolean;
var
  o: TTyRichObject;
begin
  Result := TyRichFindBookmark(ADoc, AName, AStart, AEnd);
  if not Result then Exit;
  if AEnd = AStart then
  begin
    ADoc.BeginRead;
    try
      o := ADoc.ObjectAt(AEnd);
      if not ((o is TTyRichBookmarkMark) and (TTyRichBookmarkMark(o).Kind = rbmEnd)) then
        AEnd := -1;
    finally
      ADoc.EndRead;
    end;
  end;
end;

function BookmarkChangeable(ADoc: TTyRichDocument; AStart, AEnd: TTyRichPos): Boolean;
begin
  Result := ADoc.CanChange(AStart, 1) and ((AEnd < 0) or ADoc.CanChange(AEnd, 1));
end;

constructor TTyRichAddBookmark.Create(APos, ALen: TTyRichPos; const AName: string);
begin
  inherited Create;
  FPos := APos;
  FLen := ALen;
  FName := AName;
  FStart := TTyRichBookmarkMark.CreateNew(rbmStart, FName);
  FEnd := TTyRichBookmarkMark.CreateNew(rbmEnd, FName);
  FStart.AddRef;
  FEnd.AddRef;
end;

destructor TTyRichAddBookmark.Destroy;
begin
  FStart.Release;
  FEnd.Release;
  inherited Destroy;
end;

function TTyRichAddBookmark.CanExecute(ADoc: TTyRichDocument): Boolean;
var
  s, e: TTyRichPos;
begin
  Result := False;
  if (FName = '') or HasSeparator(FName) then Exit;
  if (FPos < 0) or (FLen < 0) or (FPos + FLen > ADoc.Text.Length) then Exit;
  if not ADoc.CanChange(FPos, 0) or not ADoc.CanChange(FPos + FLen, 0) then Exit;
  if BookmarkEnds(ADoc, FName, s, e) and not BookmarkChangeable(ADoc, s, e) then Exit;
  Result := True;
end;

procedure TTyRichAddBookmark.DoExecute(ADoc: TTyRichDocument);
var
  s, e, p, n: TTyRichPos;
begin
  p := FPos;
  n := FLen;
  // the one of that name first (the end, then the start: the start's place stays)
  if BookmarkEnds(ADoc, FName, s, e) then
  begin
    if e >= 0 then
    begin
      DeleteObjectAt(ADoc, e);
      if e < p then Dec(p) else if e < p + n then Dec(n);
    end;
    DeleteObjectAt(ADoc, s);
    if s < p then Dec(p) else if s < p + n then Dec(n);
  end;
  InsertObject(ADoc, p + n, FEnd);
  InsertObject(ADoc, p, FStart);
end;

function TTyRichAddBookmark.Description: string;
begin
  Result := rsRichUndoAddBookmark;
end;

procedure TTyRichAddBookmark.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
begin
  inherited GatherObjects(AList, ACount);
  if ACount + 2 > Length(AList) then SetLength(AList, ACount * 2 + 4);
  AList[ACount] := FStart;
  AList[ACount + 1] := FEnd;
  Inc(ACount, 2);
end;

constructor TTyRichDeleteBookmark.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

function TTyRichDeleteBookmark.CanExecute(ADoc: TTyRichDocument): Boolean;
var
  s, e: TTyRichPos;
begin
  Result := BookmarkEnds(ADoc, FName, s, e) and BookmarkChangeable(ADoc, s, e);
end;

procedure TTyRichDeleteBookmark.DoExecute(ADoc: TTyRichDocument);
var
  s, e: TTyRichPos;
begin
  if not BookmarkEnds(ADoc, FName, s, e) then
    raise ETyRichModel.CreateFmt('No bookmark %s', [FName]);
  if e >= 0 then DeleteObjectAt(ADoc, e);
  DeleteObjectAt(ADoc, s);
end;

function TTyRichDeleteBookmark.Description: string;
begin
  Result := rsRichUndoDeleteBookmark;
end;

constructor TTyRichRenameBookmark.Create(const AOld, ANew: string);
begin
  inherited Create;
  FOld := AOld;
  FNew := ANew;
  FStart := TTyRichBookmarkMark.CreateNew(rbmStart, FNew);
  FEnd := TTyRichBookmarkMark.CreateNew(rbmEnd, FNew);
  FStart.AddRef;
  FEnd.AddRef;
end;

destructor TTyRichRenameBookmark.Destroy;
begin
  FStart.Release;
  FEnd.Release;
  inherited Destroy;
end;

function TTyRichRenameBookmark.CanExecute(ADoc: TTyRichDocument): Boolean;
var
  s, e, s2, e2: TTyRichPos;
begin
  Result := False;
  if (FNew = '') or HasSeparator(FNew) then Exit;
  if not BookmarkEnds(ADoc, FOld, s, e) or not BookmarkChangeable(ADoc, s, e) then Exit;
  // (only its own case changed: the same bookmark)
  if not TyRichSameBookmarkName(FOld, FNew) and TyRichFindBookmark(ADoc, FNew, s2, e2) then Exit;
  Result := True;
end;

procedure TTyRichRenameBookmark.DoExecute(ADoc: TTyRichDocument);
var
  s, e: TTyRichPos;
begin
  if not BookmarkEnds(ADoc, FOld, s, e) then
    raise ETyRichModel.CreateFmt('No bookmark %s', [FOld]);
  ReplaceObject(ADoc, s, FStart);
  if e >= 0 then ReplaceObject(ADoc, e, FEnd);
end;

function TTyRichRenameBookmark.Description: string;
begin
  Result := rsRichUndoRenameBookmark;
end;

procedure TTyRichRenameBookmark.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
begin
  inherited GatherObjects(AList, ACount);
  if ACount + 2 > Length(AList) then SetLength(AList, ACount * 2 + 4);
  AList[ACount] := FStart;
  AList[ACount + 1] := FEnd;
  Inc(ACount, 2);
end;

{ ---- the table property commands ---- }

function TTyRichTablePropsCommand.Refusal(ADoc: TTyRichDocument): TTyRichTableRefusal;
begin
  Result := ADoc.TablePropsRefusal(FEdit);
end;

function TTyRichTablePropsCommand.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := Refusal(ADoc) = rtrNone;
end;

procedure TTyRichTablePropsCommand.DoExecute(ADoc: TTyRichDocument);
begin
  EditTableProps(ADoc, FEdit);
end;

constructor TTyRichSetCellProps.Create(ATablePos: TTyRichPos; ARow0, ACol0, ARow1, ACol1: Integer;
  const AProps: TTyRichCellProps);
begin
  inherited Create;
  FEdit := Default(TTyRichPropEdit);
  FEdit.Pos := ATablePos;
  FEdit.Row0 := ARow0;
  FEdit.Row1 := ARow1;
  FEdit.Col0 := ACol0;
  FEdit.Col1 := ACol1;
  FEdit.OfRows := False;
  FEdit.Cell := AProps;
end;

function TTyRichSetCellProps.Description: string;
begin
  Result := rsRichUndoCellProps;
end;

constructor TTyRichSetRowProps.Create(ATablePos: TTyRichPos; ARow0, ARow1: Integer;
  const AProps: TTyRichRowProps);
begin
  inherited Create;
  FEdit := Default(TTyRichPropEdit);
  FEdit.Pos := ATablePos;
  FEdit.Row0 := ARow0;
  FEdit.Row1 := ARow1;
  FEdit.OfRows := True;
  FEdit.Row := AProps;
end;

function TTyRichSetRowProps.Description: string;
begin
  Result := rsRichUndoRowProps;
end;

constructor TTyRichSetColumnEdge.Create(ATablePos: TTyRichPos; AEdgeTwips, ANewTwips: Integer;
  ARow0, ARow1: Integer; AShiftRest: Boolean);
begin
  inherited Create;
  FEdit := Default(TTyRichPropEdit);
  FEdit.Pos := ATablePos;
  FEdit.Row0 := ARow0;
  FEdit.Row1 := ARow1;
  FEdit.OfRows := True;
  FEdit.EdgeKind := rekMove;
  FEdit.EdgeFrom := AEdgeTwips;
  FEdit.EdgeTo := ANewTwips;
  FEdit.EdgeShift := AShiftRest;
end;

function TTyRichSetColumnEdge.Description: string;
begin
  Result := rsRichUndoColumnWidth;
end;

function TTyRichSetRowHeight.Description: string;
begin
  Result := rsRichUndoRowHeight;
end;

constructor TTyRichSetRowWidths.CreateDistribute(ATablePos: TTyRichPos; ARow0, ARow1: Integer);
begin
  inherited Create;
  FEdit := Default(TTyRichPropEdit);
  FEdit.Pos := ATablePos;
  FEdit.Row0 := ARow0;
  FEdit.Row1 := ARow1;
  FEdit.OfRows := True;
  FEdit.EdgeKind := rekDistribute;
end;

constructor TTyRichSetRowWidths.CreateFit(ATablePos: TTyRichPos; ARow0, ARow1, AWidthTwips: Integer);
begin
  inherited Create;
  FEdit := Default(TTyRichPropEdit);
  FEdit.Pos := ATablePos;
  FEdit.Row0 := ARow0;
  FEdit.Row1 := ARow1;
  FEdit.OfRows := True;
  FEdit.EdgeKind := rekFit;
  FEdit.FitWidth := AWidthTwips;
end;

function TTyRichSetRowWidths.Description: string;
begin
  Result := rsRichUndoColumnWidth;
end;

end.
