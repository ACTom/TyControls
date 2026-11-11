unit test.richedit.commands;

{ Commands and the undo history of TTyRichEdit's document: every built-in command undoes and
  redoes exactly, typing merges as TTyMemo's undo stack merges it, an update block is one
  step and one change, a command a program writes itself gets the same undo for nothing, and
  the history keeps references, not text. This unit uses only what a program sees: the
  public document, the built-in commands, and TTyRichCommand's protected methods from a
  subclass - nothing reaches the document's primitives directly. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Graphics, fpcunit, testregistry,
  tyControls.StrConsts, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands;

type
  TCmdCountedOpaque = class(TTyRichOpaque)
  public
    class var Live: Integer;
    constructor Create(const ABytes: RawByteString);
    destructor Destroy; override;
  end;

  // the loading path: sets paragraphs up as a reader would
  TCmdTestBuilder = class(TTyRichDocBuilder)
  public
    class procedure Put(ADoc: TTyRichDocument; AIndex: Integer; AParaFormat: TTyParaFormatId;
      const ARuns: TTyRunArray);
  end;

  { A program's own command, written the way spec 5.2 means: it inserts a signature block
    and sets it in italics through the protected methods, and has no undo code at all. }
  TSignatureCommand = class(TTyRichCommand)
  private
    FPos: TTyRichPos;
    FName: UTF8String;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(APos: TTyRichPos; const AName: UTF8String);
    function Description: string; override;
    // tries the protected methods from outside a run: must raise
    procedure Sneak(ADoc: TTyRichDocument);
  end;

  TRefusingCommand = class(TTyRichCommand)
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    class var Freed: Integer;
    destructor Destroy; override;
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
  end;

  TTyRichCommandsTest = class(TTestCase)
  private
    FChanges: array of TTyRichChange;
    procedure DocChanged(Sender: TObject; const AChange: TTyRichChange);
    function NewDoc(const AText: UTF8String): TTyRichDocument;
    function NewSample: TTyRichDocument;
    function ColorId(ADoc: TTyRichDocument; AColor: TColor): TTyCharFormatId;
    function AlignId(ADoc: TTyRichDocument; AAlign: TTyParaAlign): TTyParaFormatId;
    function RunsStr(ADoc: TTyRichDocument; AIndex: Integer): string;
    function ParaText(ADoc: TTyRichDocument; AIndex: Integer): UTF8String;
    function AllText(ADoc: TTyRichDocument): UTF8String;
    function Dump(ADoc: TTyRichDocument): string;
    function BuiltIn(ADoc: TTyRichDocument; AIndex: Integer): TTyRichCommand;
    procedure Type_(ADoc: TTyRichDocument; const AChar: UTF8String);
    procedure CheckChange(const AWhat: string; AIndex: Integer; AKinds: TTyRichChangeKinds;
      APos, AOldLen, ANewLen: TTyRichPos; AFirstPara, AOldCount, ANewCount: Integer);
    procedure HistoryScenario;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryBuiltInCommandUndoesExactly;
    procedure TestTypingMergesUntilTheCaretMoves;
    procedure TestUpdateBlockIsOneUndoStep;
    procedure TestCustomCommandSubclassUndoes;
    procedure TestDeletingEverythingStoresPiecesNotText;
    procedure TestRefusedCommandChangesNothing;
    procedure TestEveryStepReportsOneChange;
    procedure TestHistoryGoesBeforeTheValues;
    procedure TestMaxUndoBytesDropsTheOldest;
    procedure TestFormatOverTheWholeDocumentWalksLeaves;
  end;

implementation

function Bytes(const S: UTF8String): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if Length(S) > 0 then Move(S[1], Result[0], Length(S));
end;

function MkRun(AStart: Integer; AFormat: TTyCharFormatId; AObj: TTyRichObject = nil): TTyRichRun;
begin
  Result.Start := AStart;
  Result.Format := AFormat;
  Result.Obj := AObj;
end;

function Runs(const R: array of TTyRichRun): TTyRunArray;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, Length(R));
  for i := 0 to High(R) do Result[i] := R[i];
end;

{ ---- helpers ---- }

constructor TCmdCountedOpaque.Create(const ABytes: RawByteString);
begin
  inherited Create(ABytes);
  Inc(Live);
end;

destructor TCmdCountedOpaque.Destroy;
begin
  Dec(Live);
  inherited Destroy;
end;

class procedure TCmdTestBuilder.Put(ADoc: TTyRichDocument; AIndex: Integer;
  AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray);
begin
  if not SetParagraph(ADoc, AIndex, AParaFormat, ARuns) then
    raise Exception.CreateFmt('paragraph %d was set already', [AIndex]);
end;

constructor TSignatureCommand.Create(APos: TTyRichPos; const AName: UTF8String);
begin
  inherited Create;
  FPos := APos;
  FName := AName;
end;

procedure TSignatureCommand.DoExecute(ADoc: TTyRichDocument);
var
  c: TTyRichChange;
  f: TTyCharFormat;
begin
  c := InsertText(ADoc, FPos, '-- '#13#10 + FName);
  f := TyDefaultCharFormat;
  f.Style := [fsItalic];
  ApplyCharFormat(ADoc, FPos, c.NewLen, [cffItalic], f);
end;

function TSignatureCommand.Description: string;
begin
  Result := 'Insert signature';
end;

procedure TSignatureCommand.Sneak(ADoc: TTyRichDocument);
begin
  InsertText(ADoc, 0, 'sneaked in');
end;

procedure TRefusingCommand.DoExecute(ADoc: TTyRichDocument);
begin
  InsertText(ADoc, 0, 'refused');
end;

destructor TRefusingCommand.Destroy;
begin
  Inc(Freed);
  inherited Destroy;
end;

function TRefusingCommand.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := False;
end;

procedure TTyRichCommandsTest.SetUp;
begin
  FChanges := nil;
  TCmdCountedOpaque.Live := 0;
  TRefusingCommand.Freed := 0;
end;

procedure TTyRichCommandsTest.TearDown;
begin
  FChanges := nil;
end;

procedure TTyRichCommandsTest.DocChanged(Sender: TObject; const AChange: TTyRichChange);
begin
  SetLength(FChanges, Length(FChanges) + 1);
  FChanges[High(FChanges)] := AChange;
end;

function TTyRichCommandsTest.NewDoc(const AText: UTF8String): TTyRichDocument;
begin
  Result := TTyRichDocument.CreateFromUtf8(Bytes(AText));
end;

function TTyRichCommandsTest.ColorId(ADoc: TTyRichDocument; AColor: TColor): TTyCharFormatId;
var
  f: TTyCharFormat;
begin
  f := ADoc.DefaultCharFormat;
  f.Color := AColor;
  Result := ADoc.Formats.InternChar(f);
end;

function TTyRichCommandsTest.AlignId(ADoc: TTyRichDocument;
  AAlign: TTyParaAlign): TTyParaFormatId;
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.Align := AAlign;
  Result := ADoc.Formats.InternPara(f);
end;

{ Four paragraphs: 'aaabbbccc' red/green/blue centred (0..8, separator 9); 'dd'+object+'ee'
  blue/object/yellow right-aligned (10..14, separator 15); 'fff' plain justified (16..18,
  separator 19); 'ggg' untouched (20..22). }
function TTyRichCommandsTest.NewSample: TTyRichDocument;
var
  obj: TCmdCountedOpaque;
begin
  Result := NewDoc('aaabbbccc'#13#10'dd' + TyRichObjectChar + 'ee'#13#10'fff'#13#10'ggg');
  obj := TCmdCountedOpaque.Create('{\object one}');
  TCmdTestBuilder.Put(Result, 0, AlignId(Result, paraCenter),
    Runs([MkRun(0, ColorId(Result, clRed)), MkRun(3, ColorId(Result, clGreen)),
      MkRun(6, ColorId(Result, clBlue))]));
  TCmdTestBuilder.Put(Result, 1, AlignId(Result, paraRight),
    Runs([MkRun(0, ColorId(Result, clBlue)), MkRun(2, Result.DefaultCharFormatId, obj),
      MkRun(3, ColorId(Result, clYellow))]));
  TCmdTestBuilder.Put(Result, 2, AlignId(Result, paraJustify),
    Runs([MkRun(0, Result.DefaultCharFormatId)]));
end;

function TTyRichCommandsTest.RunsStr(ADoc: TTyRichDocument; AIndex: Integer): string;
var
  r: TTyRunArray;
  i: Integer;
begin
  r := ADoc.RunsOf(AIndex);
  Result := '';
  for i := 0 to High(r) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + IntToStr(r[i].Start) + ':' + IntToStr(r[i].Format);
    if r[i].Obj <> nil then Result := Result + '@' + IntToHex(PtrUInt(r[i].Obj), 1);
  end;
end;

function TTyRichCommandsTest.ParaText(ADoc: TTyRichDocument; AIndex: Integer): UTF8String;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
end;

function TTyRichCommandsTest.AllText(ADoc: TTyRichDocument): UTF8String;
begin
  Result := ADoc.Text.GetText(0, ADoc.Text.Length);
end;

function TTyRichCommandsTest.Dump(ADoc: TTyRichDocument): string;
var
  i: Integer;
  t: TTyRichTable;
begin
  Result := '';
  for i := 0 to ADoc.Text.ParaCount - 1 do
  begin
    t := ADoc.TableAt(i);
    Result := Result + Format('[%s] P%d {%s}', [ParaText(ADoc, i), ADoc.ParaFormatOf(i),
      RunsStr(ADoc, i)]);
    if t <> nil then Result := Result + ' T' + IntToHex(PtrUInt(t), 1);
    Result := Result + LineEnding;
  end;
end;

procedure TTyRichCommandsTest.Type_(ADoc: TTyRichDocument; const AChar: UTF8String);
begin
  ADoc.Execute(TTyRichInsertText.Create(ADoc.Text.Length, AChar));
end;

procedure TTyRichCommandsTest.CheckChange(const AWhat: string; AIndex: Integer;
  AKinds: TTyRichChangeKinds; APos, AOldLen, ANewLen: TTyRichPos; AFirstPara, AOldCount,
  ANewCount: Integer);
var
  c: TTyRichChange;
begin
  AssertTrue(AWhat + ': change reported', AIndex <= High(FChanges));
  c := FChanges[AIndex];
  AssertTrue(AWhat + ': kinds', c.Kinds = AKinds);
  AssertEquals(AWhat + ': pos', APos, c.Pos);
  AssertEquals(AWhat + ': old length', AOldLen, c.OldLen);
  AssertEquals(AWhat + ': new length', ANewLen, c.NewLen);
  AssertEquals(AWhat + ': first paragraph', AFirstPara, c.FirstPara);
  AssertEquals(AWhat + ': old paragraphs', AOldCount, c.OldParaCount);
  AssertEquals(AWhat + ': new paragraphs', ANewCount, c.NewParaCount);
end;

const
  BuiltInCount = 9;

function TTyRichCommandsTest.BuiltIn(ADoc: TTyRichDocument; AIndex: Integer): TTyRichCommand;
var
  f: TTyCharFormat;
  p: TTyParaFormat;
begin
  f := TyDefaultCharFormat;
  f.Style := [fsBold];
  p := TyDefaultParaFormat;
  p.LeftIndent := 720;
  case AIndex of
    0: Result := TTyRichInsertText.Create(4, 'XY');
    1: Result := TTyRichInsertText.Create(4, 'X'#13#10'Y'#13#10'Z', ColorId(ADoc, clLime));
    // middle of p0 to the middle of p1, over the object: p1's format, both ends' runs
    2: Result := TTyRichDelete.Create(5, 9);
    // the separator after p0 and nothing else: p0's format
    3: Result := TTyRichDelete.Create(9, 1);
    4: Result := TTyRichDelete.Create(0, ADoc.Text.Length);
    5: Result := TTyRichSetCharFormat.Create(TyRichRange(1, 12), [cffBold], f);
    6: Result := TTyRichSetParaFormat.Create(0, 2, [pffLeftIndent], p);
    7: Result := TTyRichInsertObject.Create(17, TCmdCountedOpaque.Create('{\object two}'));
  else
    Result := TTyRichInsertText.Create(23, 'tail', TyRichInheritFormat, False);
  end;
end;

{ ---- the brief's tests ---- }

procedure TTyRichCommandsTest.TestEveryBuiltInCommandUndoesExactly;
var
  d: TTyRichDocument;
  i, cycle: Integer;
  before, after: string;
  live: Integer;
  cmd: TTyRichCommand;
begin
  for i := 0 to BuiltInCount - 1 do
  begin
    d := NewSample;
    try
      cmd := BuiltIn(d, i);
      live := TCmdCountedOpaque.Live;
      before := Dump(d);
      AssertTrue(Format('command %d executes', [i]), d.Execute(cmd));
      after := Dump(d);
      AssertTrue(Format('command %d changed the document', [i]), after <> before);
      AssertEquals(Format('command %d: one undo step', [i]), 1, d.UndoDepth);
      for cycle := 1 to 3 do
      begin
        d.Undo;
        AssertEquals(Format('command %d, cycle %d: undo gives back everything', [i, cycle]),
          before, Dump(d));
        AssertEquals(Format('command %d, cycle %d: the integrity of the text', [i, cycle]),
          '', d.Text.CheckIntegrity);
        AssertTrue(Format('command %d, cycle %d: can redo', [i, cycle]), d.CanRedo);
        d.Redo;
        AssertEquals(Format('command %d, cycle %d: redo gives the result again', [i, cycle]),
          after, Dump(d));
      end;
      d.Undo;
      AssertEquals(Format('command %d: objects after the undo', [i]), live,
        TCmdCountedOpaque.Live);
    finally
      d.Free;
    end;
    AssertEquals(Format('command %d: no object outlives the document', [i]), 0,
      TCmdCountedOpaque.Live);
  end;
end;

procedure TTyRichCommandsTest.TestTypingMergesUntilTheCaretMoves;
var
  d: TTyRichDocument;
  i: Integer;
  f: TTyCharFormat;
begin
  d := NewDoc('Hello');
  try
    for i := 1 to 5 do
      d.Execute(TTyRichInsertText.Create(d.Text.Length, Copy('abcde', i, 1)));
    AssertEquals('five characters typed', 'Helloabcde', AllText(d));
    AssertEquals('one undo step', 1, d.UndoDepth);
    AssertEquals('it is typing', rsRichUndoTyping, d.UndoDescription);
    d.Undo;
    AssertEquals('one undo takes all five', 'Hello', AllText(d));
    d.Redo;
    AssertEquals('one redo gives all five back', 'Helloabcde', AllText(d));
  finally
    d.Free;
  end;

  d := NewDoc('');
  try
    Type_(d, 'a');
    Type_(d, 'b');
    Type_(d, 'c');
    d.BreakMerge;
    Type_(d, 'd');
    Type_(d, 'e');
    AssertEquals('BreakMerge in the middle: two steps', 2, d.UndoDepth);
    d.Undo;
    AssertEquals('the second run of typing', 'abc', AllText(d));
    d.Undo;
    AssertEquals('the first run of typing', '', AllText(d));
  finally
    d.Free;
  end;

  // the rest of TTyMemo's rule (tyControls.UndoStack.Push): a space does not break a run,
  // a line break, a paste, another kind of command and an undo do
  d := NewDoc('');
  try
    Type_(d, 'a');
    Type_(d, ' ');
    Type_(d, 'b');
    AssertEquals('a space stays in the run', 1, d.UndoDepth);
    Type_(d, #13#10);
    Type_(d, 'c');
    AssertEquals('Enter is a step of its own, and typing after it starts a new one', 3,
      d.UndoDepth);
    d.Execute(TTyRichInsertText.Create(d.Text.Length, 'pasted', TyRichInheritFormat, False));
    Type_(d, 'd');
    AssertEquals('a paste is a step of its own', 5, d.UndoDepth);
    f := TyDefaultCharFormat;
    f.Style := [fsBold];
    d.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 1), [cffBold], f));
    Type_(d, 'e');
    AssertEquals('another command breaks the run', 7, d.UndoDepth);
    d.Undo;
    Type_(d, 'x');
    Type_(d, 'y');
    AssertEquals('typing after an undo starts a new step', 7, d.UndoDepth);
    AssertEquals('the redo side went', 0, d.RedoDepth);
    d.Undo;
    AssertEquals('the run after the undo', 'a b'#13#10'cpastedd', AllText(d));
  finally
    d.Free;
  end;
end;

procedure TTyRichCommandsTest.TestUpdateBlockIsOneUndoStep;
var
  d: TTyRichDocument;
  f: TTyCharFormat;
  before, after: string;
begin
  d := NewDoc('abcdef');
  try
    d.OnChange := @DocChanged;
    before := Dump(d);
    f := TyDefaultCharFormat;
    f.Style := [fsBold];
    d.BeginUpdate;
    d.Execute(TTyRichInsertText.Create(1, 'XY'));
    d.Execute(TTyRichDelete.Create(5, 2));
    d.BeginUpdate;   // nested: still the same block
    d.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 1), [cffBold], f));
    d.EndUpdate;
    AssertEquals('nothing is reported inside the block', 0, Length(FChanges));
    AssertFalse('no undo inside the block', d.CanUndo);
    d.EndUpdate;
    after := Dump(d);
    AssertEquals('the block ran', 'aXYbcf', AllText(d));
    AssertEquals('one undo step', 1, d.UndoDepth);
    AssertEquals('one change', 1, Length(FChanges));
    // [1,5) 'bcde' became 'XYbc', and the bold 'a' before it: [0,5) both ways
    CheckChange('block', 0, [rckText, rckFormat], 0, 5, 5, 0, 1, 1);
    d.Undo;
    AssertEquals('one undo takes the block back', before, Dump(d));
    AssertEquals('undoing the block is one change', 2, Length(FChanges));
    CheckChange('block undone', 1, [rckText, rckFormat], 0, 5, 5, 0, 1, 1);
    d.Redo;
    AssertEquals('one redo puts it back', after, Dump(d));
    AssertEquals('redoing the block is one change', 3, Length(FChanges));
    AssertEquals('the block is named after its parts', rsRichUndoEdit, d.UndoDescription);
  finally
    d.Free;
  end;
end;

procedure TTyRichCommandsTest.TestCustomCommandSubclassUndoes;
var
  d: TTyRichDocument;
  before, after: string;
  sneak: TSignatureCommand;
  r: TTyRichRange;
  italic: TTyCharFormatId;
  f: TTyCharFormat;
begin
  d := NewSample;
  try
    before := Dump(d);
    AssertTrue('executes', d.Execute(TSignatureCommand.Create(20, 'Tom')));
    AssertEquals('the signature is in', '-- '#13#10'Tomggg', ParaText(d, 3) + #13#10 +
      ParaText(d, 4));
    f := TyDefaultCharFormat;
    f.Style := [fsItalic];
    italic := d.Formats.InternChar(f);
    AssertEquals('the first line is italic', '0:' + IntToStr(italic), RunsStr(d, 3));
    AssertEquals('so is the name, not what follows it',
      '0:' + IntToStr(italic) + ' 3:' + IntToStr(d.DefaultCharFormatId), RunsStr(d, 4));
    AssertEquals('its own description', 'Insert signature', d.UndoDescription);
    AssertEquals('one step for two changes', 1, d.UndoDepth);
    after := Dump(d);
    d.Undo;
    AssertEquals('undone without undo code of its own', before, Dump(d));
    AssertEquals('redo is offered', 'Insert signature', d.RedoDescription);
    d.Redo;
    AssertEquals('redone', after, Dump(d));
    d.Undo;
    d.Redo;
    AssertEquals('redone again', after, Dump(d));

    sneak := TSignatureCommand.Create(0, 'x');
    try
      try
        sneak.Sneak(d);
        Fail('a command changed the document outside Execute');
      except
        on E: ETyRichModel do ;
      end;
    finally
      sneak.Free;
    end;
    AssertEquals('nothing sneaked in', after, Dump(d));
  finally
    d.Free;
  end;

  // the range the command reports is the one it changed, in the document it left
  d := NewDoc('abc');
  try
    sneak := TSignatureCommand.Create(1, 'Tom');
    d.Execute(sneak);
    r := sneak.ChangedRange;
    AssertEquals('range start', 1, r.Pos);
    AssertEquals('range length: the seven characters inserted (a separator is one)', 7, r.Len);
    AssertTrue('the text', AllText(d) = 'a-- '#13#10'Tombc');
  finally
    d.Free;
  end;
end;

procedure TTyRichCommandsTest.TestDeletingEverythingStoresPiecesNotText;
const
  Sentence: UTF8String = 'A line of 中文 and English text. ';
var
  d: TTyRichDocument;
  buf, line, expected: UTF8String;
  i: Integer;
  h0, h1, added, kept, pieces: Int64;
begin
  line := '';
  for i := 1 to 10 do line := line + Sentence;
  line := line + #13#10;
  buf := '';
  for i := 1 to 20000 do buf := buf + line;
  d := NewDoc(buf);
  try
    d.Execute(TTyRichInsertText.Create(5, 'edit'));
    d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(100), 'new'#13#10));
    d.Execute(TTyRichDelete.Create(d.Text.ParaStart(200) + 3, 400));
    expected := AllText(d);
    added := d.Text.AddedBytes;
    pieces := d.Text.PieceCount;
    kept := d.HistoryBytes;
    h0 := GetFPCHeapStatus.CurrHeapUsed;
    d.Execute(TTyRichDelete.Create(0, d.Text.Length));
    h1 := GetFPCHeapStatus.CurrHeapUsed;
    AssertEquals('empty', 0, d.Text.Length);
    AssertEquals('one empty paragraph', 1, d.Text.ParaCount);
    AssertTrue(Format('the history keeps %d bytes for %d pieces', [d.HistoryBytes - kept,
      pieces]), d.HistoryBytes - kept <= pieces * SizeOf(TTyRichPiece) + 64 * 1024);
    AssertTrue(Format('deleting %d bytes of text took %d bytes of heap', [Length(buf),
      h1 - h0]), h1 - h0 < Length(buf) div 4);
    for i := 1 to 2 do
    begin
      d.Undo;
      AssertEquals('no text was copied into the add buffer', added, d.Text.AddedBytes);
      AssertTrue('every byte back', AllText(d) = expected);
      AssertEquals('integrity', '', d.Text.CheckIntegrity);
      d.Redo;
      AssertEquals('redo deleted it all again', 0, d.Text.Length);
      AssertEquals('redo copied no text either', added, d.Text.AddedBytes);
    end;
  finally
    d.Free;
  end;
end;

{ ---- the rulings' tests ---- }

procedure TTyRichCommandsTest.TestRefusedCommandChangesNothing;
var
  d: TTyRichDocument;
  comp: TTyRichCompositeCommand;
  before: string;
  raised: Boolean;
begin
  d := NewSample;
  try
    d.Execute(TTyRichInsertText.Create(0, 'x'));
    d.Undo;
    d.Modified := False;
    d.OnChange := @DocChanged;
    before := Dump(d);
    AssertFalse('a command that cannot execute says so', d.Execute(TRefusingCommand.Create));
    AssertEquals('it is freed', 1, TRefusingCommand.Freed);
    AssertEquals('the document is as it was', before, Dump(d));
    AssertEquals('no undo step', 0, d.UndoDepth);
    AssertEquals('the redo side is kept', 1, d.RedoDepth);
    AssertEquals('no change reported', 0, Length(FChanges));
    AssertFalse('not modified', d.Modified);

    // a part that cannot execute stops the whole, and the parts before it go back
    comp := TTyRichCompositeCommand.Create;
    comp.Add(TTyRichInsertText.Create(0, 'first'));
    comp.Add(TRefusingCommand.Create);
    raised := False;
    try
      d.Execute(comp);
    except
      on E: ETyRichModel do raised := True;
    end;
    AssertTrue('the composite raised', raised);
    AssertEquals('the composite and its parts are freed', 2, TRefusingCommand.Freed);
    AssertEquals('the first part was reverted', before, Dump(d));
    AssertEquals('still no undo step', 0, d.UndoDepth);
  finally
    d.Free;
  end;
end;

procedure TTyRichCommandsTest.TestEveryStepReportsOneChange;
var
  d: TTyRichDocument;
begin
  d := NewDoc('abc'#13#10'def');
  try
    d.OnChange := @DocChanged;
    // an insert with a split and a format change: two primitives, one change
    d.Execute(TSignatureCommand.Create(4, 'Tom'));
    AssertEquals('execute: one change', 1, Length(FChanges));
    CheckChange('execute', 0, [rckText, rckStructure, rckFormat], 4, 0, 7, 1, 1, 2);
    d.Undo;
    AssertEquals('undo: one change', 2, Length(FChanges));
    CheckChange('undo', 1, [rckText, rckStructure, rckFormat], 4, 7, 0, 1, 2, 1);
    d.Redo;
    AssertEquals('redo: one change', 3, Length(FChanges));
    CheckChange('redo', 2, [rckText, rckStructure, rckFormat], 4, 0, 7, 1, 1, 2);

    // a command that changes nothing is not kept and not reported
    d.Undo;
    SetLength(FChanges, 0);
    d.Execute(TTyRichDelete.Create(2, 0));
    AssertEquals('a no-op: no change', 0, Length(FChanges));
    AssertEquals('a no-op: no step', 0, d.UndoDepth);
    AssertEquals('a no-op: the redo side is kept', 1, d.RedoDepth);

    // nor is an empty block, or one of no-ops
    d.BeginUpdate;
    d.EndUpdate;
    d.BeginUpdate('nothing');
    d.Execute(TTyRichInsertText.Create(1, ''));
    d.EndUpdate;
    AssertEquals('empty blocks: no change', 0, Length(FChanges));
    AssertEquals('empty blocks: no step', 0, d.UndoDepth);
    AssertEquals('empty blocks: the redo side is kept', 1, d.RedoDepth);

    // a block of one command is named after it unless the block has a name
    d.BeginUpdate;
    d.Execute(TTyRichDelete.Create(0, 1));
    d.EndUpdate;
    AssertEquals('one command in the block', rsRichUndoDelete, d.UndoDescription);
    AssertEquals('a new step drops the redo side', 0, d.RedoDepth);
    d.BeginUpdate('Replace');
    d.Execute(TTyRichDelete.Create(0, 1));
    d.EndUpdate;
    AssertEquals('the block''s own name', 'Replace', d.UndoDescription);
    AssertEquals('two blocks, two changes', 2, Length(FChanges));
  finally
    d.Free;
  end;
end;

procedure TTyRichCommandsTest.HistoryScenario;
var
  d: TTyRichDocument;
  f: TTyCharFormat;
begin
  d := NewSample;
  f := TyDefaultCharFormat;
  f.Style := [fsBold];
  // a delete that takes the object's paragraph value into its record, an object insert,
  // a format change, a block, an undo (so the redo side holds a step too), then an open
  // block - all of it still in the history when the document goes
  d.Execute(TTyRichDelete.Create(5, 9));
  d.Execute(TTyRichInsertObject.Create(2, TCmdCountedOpaque.Create('{\object three}')));
  d.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 8), [cffBold], f));
  d.BeginUpdate;
  d.Execute(TTyRichInsertText.Create(0, 'x'#13#10'y'));
  d.Execute(TTyRichDelete.Create(1, 2));
  d.EndUpdate;
  d.Undo;
  d.Undo;
  d.BeginUpdate;
  d.Execute(TTyRichInsertText.Create(0, 'open'));
  d.Free;
end;

procedure TTyRichCommandsTest.TestHistoryGoesBeforeTheValues;
var
  h0: Int64;
begin
  HistoryScenario;   // the first run warms up whatever allocates once
  AssertEquals('no object outlives the document', 0, TCmdCountedOpaque.Live);
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  HistoryScenario;
  AssertEquals('no object outlives the document, second run', 0, TCmdCountedOpaque.Live);
  AssertEquals('the document and its history leave no heap behind', h0,
    Int64(GetFPCHeapStatus.CurrHeapUsed));
end;

procedure TTyRichCommandsTest.TestMaxUndoBytesDropsTheOldest;
var
  d: TTyRichDocument;
  states: array[0..10] of UTF8String;
  i, depth: Integer;
begin
  d := NewDoc('');
  try
    states[0] := '';
    for i := 1 to 10 do
    begin
      // each a step of its own: a line break never merges
      d.Execute(TTyRichInsertText.Create(d.Text.Length, Format('line %d'#13#10, [i])));
      states[i] := AllText(d);
    end;
    AssertEquals('ten steps', 10, d.UndoDepth);
    d.MaxUndoBytes := d.HistoryBytes div 2;
    depth := d.UndoDepth;
    AssertTrue(Format('the limit dropped steps (%d left)', [depth]), (depth > 1) and (depth < 10));
    AssertTrue('within the limit', d.HistoryBytes <= d.MaxUndoBytes);
    for i := 1 to depth do d.Undo;
    AssertFalse('nothing more to undo', d.CanUndo);
    AssertTrue('the oldest steps went: undo stops after the dropped ones',
      AllText(d) = states[10 - depth]);
    for i := 1 to depth do d.Redo;
    AssertTrue('redo goes all the way', AllText(d) = states[10]);

    d.MaxUndoBytes := 1;
    AssertEquals('a limit below every step keeps the newest', 1, d.UndoDepth);
    d.Execute(TTyRichInsertText.Create(0, 'big step'#13#10));
    AssertEquals('the step just executed stays', 1, d.UndoDepth);
    d.Undo;
    AssertTrue('and undoes', AllText(d) = states[10]);
    d.Redo;
    AssertEquals('the step just redone stays too', 1, d.UndoDepth);
    d.MaxUndoBytes := 0;
    for i := 1 to 3 do d.Execute(TTyRichInsertText.Create(0, 'z'#13#10));
    AssertEquals('0 is no limit', 4, d.UndoDepth);
  finally
    d.Free;
  end;
end;

procedure TTyRichCommandsTest.TestFormatOverTheWholeDocumentWalksLeaves;
const
  Count = 2000000;
  Line: UTF8String = 'abc'#10;
var
  buf: TBytes;
  d: TTyRichDocument;
  i, n, bold, center, red, green, blue, paras, limit: Integer;
  f: TTyCharFormat;
  p: TTyParaFormat;
  nv: Int64;
  formatted, plain: string;
  r: TTyRunArray;

  procedure CheckBold(AIndex: Integer; const AWhen: string);
  var
    j: Integer;
    rr: TTyRunArray;
  begin
    rr := d.RunsOf(AIndex);
    for j := 0 to High(rr) do
      AssertTrue(Format('%s: paragraph %d run %d is bold', [AWhen, AIndex, j]),
        fsBold in d.Formats.CharFormat(rr[j].Format).Style);
  end;

  procedure CheckOne(AIndex: Integer; const AWhen: string);
  begin
    if (AIndex mod 100000 = 7) and (AIndex < Count) then
      AssertEquals(Format('%s: formatted paragraph %d', [AWhen, AIndex]), formatted,
        RunsStr(d, AIndex))
    else
      AssertEquals(Format('%s: plain paragraph %d', [AWhen, AIndex]), plain, RunsStr(d, AIndex));
    AssertEquals(Format('%s: paragraph format %d', [AWhen, AIndex]), d.DefaultParaFormatId,
      d.ParaFormatOf(AIndex));
  end;

  procedure CheckRestored(const AWhen: string);
  var
    j: Integer;
  begin
    for j := 0 to 20 do CheckOne(j * 99991, AWhen);
    j := 7;
    while j < Count do
    begin
      // every formatted paragraph and the plain one after it
      CheckOne(j, AWhen);
      CheckOne(j + 1, AWhen);
      Inc(j, 100000);
    end;
    CheckOne(paras - 1, AWhen);
  end;

begin
  buf := nil;
  SetLength(buf, Count * Length(Line));
  for i := 0 to Count - 1 do Move(Line[1], buf[i * Length(Line)], Length(Line));
  d := TTyRichDocument.CreateFromUtf8(buf);
  try
    paras := d.Text.ParaCount;
    AssertEquals('paragraphs', Count + 1, paras);
    red := ColorId(d, clRed);
    green := ColorId(d, clGreen);
    blue := ColorId(d, clBlue);
    // three-run paragraphs mixed in, as a reader leaves them
    i := 7;
    while i < Count do
    begin
      TCmdTestBuilder.Put(d, i, d.DefaultParaFormatId, Runs([MkRun(0, red), MkRun(1, green),
        MkRun(2, blue)]));
      Inc(i, 100000);
    end;
    formatted := Format('0:%d 1:%d 2:%d', [red, green, blue]);
    plain := '0:' + IntToStr(d.DefaultCharFormatId);
    limit := paras div 64;

    f := TyDefaultCharFormat;
    f.Style := [fsBold];
    nv := d.Text.NodeVisits;
    d.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, d.Text.Length), [cffBold], f));
    n := d.Text.NodeVisits - nv;
    AssertTrue(Format('bold over %d paragraphs entered %d nodes, limit %d', [paras, n, limit]),
      n <= limit);
    AssertTrue(Format('the undo record keeps %d bytes', [d.HistoryBytes]),
      d.HistoryBytes < 64 * 1024);
    for i := 0 to 20 do CheckBold(i * 99991, 'bold');
    CheckBold(7, 'bold');
    CheckBold(100007, 'bold');
    CheckBold(Count - 1, 'bold');
    bold := d.RunsOf(1)[0].Format;
    r := d.RunsOf(7);
    AssertEquals('the formatted paragraph keeps three runs', 3, Length(r));

    nv := d.Text.NodeVisits;
    d.Undo;
    n := d.Text.NodeVisits - nv;
    AssertTrue(Format('its undo entered %d nodes, limit %d', [n, limit]), n <= limit);
    CheckRestored('undo');

    nv := d.Text.NodeVisits;
    d.Redo;
    n := d.Text.NodeVisits - nv;
    AssertTrue(Format('its redo entered %d nodes, limit %d', [n, limit]), n <= limit);
    AssertEquals('redo: bold again', bold, d.RunsOf(Count div 2)[0].Format);
    d.Undo;

    p := TyDefaultParaFormat;
    p.Align := paraCenter;
    center := d.Formats.InternPara(p);
    nv := d.Text.NodeVisits;
    d.Execute(TTyRichSetParaFormat.Create(0, paras - 1, [pffAlign], p));
    n := d.Text.NodeVisits - nv;
    AssertTrue(Format('centring %d paragraphs entered %d nodes, limit %d', [paras, n, limit]),
      n <= limit);
    AssertTrue(Format('its undo record keeps %d bytes', [d.HistoryBytes]),
      d.HistoryBytes < 64 * 1024);
    AssertEquals('centred: first', center, d.ParaFormatOf(0));
    AssertEquals('centred: formatted', center, d.ParaFormatOf(100007));
    AssertEquals('centred: last', center, d.ParaFormatOf(paras - 1));
    AssertEquals('centring keeps the runs', formatted, RunsStr(d, 100007));
    nv := d.Text.NodeVisits;
    d.Undo;
    n := d.Text.NodeVisits - nv;
    AssertTrue(Format('its undo entered %d nodes, limit %d', [n, limit]), n <= limit);
    CheckRestored('para undo');
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyRichCommandsTest);

end.
