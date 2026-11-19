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
  Classes, SysUtils, tyControls.RichEdit.Text, tyControls.RichEdit.Model;

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
    (TTyRichDocument.ApplyCharFormat). }
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
    function Description: string; override;
  end;

  { Sets the AMask fields of paragraphs AFirstPara..ALastPara. }
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

function TyRichRange(APos, ALen: TTyRichPos): TTyRichRange;
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
  Result := ADoc.CanChange(FPos, 0);
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
    content := TTyRichRangeContent.Create(ADoc, FFrom, FCut, not Moves);
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
      // the built-in text commands ask only CanChange: a row that holds a nested table
      e.FixedRow := (c is TTyRichInsertText) or (c is TTyRichDelete) or
        (c is TTyRichInsertObject) or (c is TTyRichInsertFragment);
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

end.
