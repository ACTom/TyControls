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
  Classes, SysUtils, Graphics, ImgList, tyControls.RichEdit.Text, tyControls.RichEdit.Model;

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
  private
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
    the source. }
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
    move puts the very objects at the new place.
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
    first text of the old result (the look the link had). One undo step. Refused (CanExecute
    False): no field's open mark at AFieldPos; AURL empty or '#'; a paragraph separator in
    AURL or AText; a field inside another field's result, or where the text cannot change. }
  TTyRichSetLink = class(TTyRichCommand)
  private
    FPos: TTyRichPos;
    FURL, FText: UTF8String;
    FOpen, FClose: TTyRichFieldMark;
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

const
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
  tyControls.StrConsts;

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
begin
  ApplyParaFormat(ADoc, FFirst, FLast, FMask, FValue);
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
  FPlaced := TyRichRange(FAt, FFragment.CharCount);
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

end.
