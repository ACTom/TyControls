unit tyControls.RichEdit.Commands;

{ The built-in commands of TTyRichEdit's document: insert text, delete, set character and
  paragraph formats, insert an object, and a command made of commands (what an update block
  becomes). Each is run by TTyRichDocument.Execute, and each changes the document only
  through the primitives TTyRichCommand hands on, so the inherited undo (the records
  reverted, newest first) and redo (run again) are exact - none of them keeps text or a
  snapshot of its own. A program adds its own commands the same way (spec 5.2). Table
  commands come with the table editing. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, tyControls.RichEdit.Text, tyControls.RichEdit.Model;

type
  { Inserts text (paragraph separators allowed) at APos; AFormat as TTyRichDocument's
    InsertText. Typing - mergeable text without a separator - merges with the typing right
    before it into one undo step, as TTyMemo's undo stack does: a paste passes
    AMergeable = False, and Enter (a separator) never merges. }
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
    function Description: string; override;
  end;

  { Sets the AMask fields of the characters in ARange (the others keep theirs). }
  TTyRichSetCharFormat = class(TTyRichCommand)
  private
    FRange: TTyRichRange;
    FMask: TTyCharFormatMask;
    FValue: TTyCharFormat;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(const ARange: TTyRichRange; AMask: TTyCharFormatMask;
      const AValue: TTyCharFormat);
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
    function Description: string; override;
    property RichObject: TTyRichObject read FObject;
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
    property Items[AIndex: Integer]: TTyRichCommand read GetItem;
  end;

function TyRichRange(APos, ALen: TTyRichPos): TTyRichRange;

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
  const AValue: TTyCharFormat);
begin
  inherited Create;
  FRange := ARange;
  FMask := AMask;
  FValue := AValue;
end;

procedure TTyRichSetCharFormat.DoExecute(ADoc: TTyRichDocument);
begin
  ApplyCharFormat(ADoc, FRange.Pos, FRange.Len, FMask, FValue);
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

procedure TTyRichInsertObject.DoExecute(ADoc: TTyRichDocument);
begin
  InsertObject(ADoc, FPos, FObject, FFormat);
end;

function TTyRichInsertObject.Description: string;
begin
  Result := rsRichUndoInsertObject;
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
begin
  FDone := 0;
  while FDone < FItems.Count do
  begin
    c := TTyRichCommand(FItems[FDone]);
    // asked at its turn: the parts before it have changed the document
    if not c.CanExecute(ADoc) then
      raise ETyRichModel.CreateFmt('Part %d of the command (%s) cannot be carried out',
        [FDone, c.ClassName]);
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

end.
