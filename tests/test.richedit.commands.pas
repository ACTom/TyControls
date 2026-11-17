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
  tyControls.RichEdit.Commands, tyControls.RichEdit.RtfRead;

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
    // Task 10a
    procedure TestAnInsertThatCutsASequenceIsRefused;
    procedure TestClearUndoDropsTheHistory;
    // Task 10c: a fragment of another document
    procedure TestAFragmentMeetsTheParagraphAtItsPlace;
    procedure TestAFragmentsRowsAreRowsOutsideATableAndTextInOne;
    procedure TestAFragmentBringsNoDocumentLevelThing;
    procedure TestAFragmentSharesItsObjectsAndKeepsOneStep;
    procedure TestAFragmentIsRefusedInARowWithANestedTable;
    procedure TestReadingAFragmentOfUntrustedBytes;
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

{ The bytes an inserted line break is stored as in ADoc: its majority kind, which for a
  document without any break is the platform's. }
function BreakOf(ADoc: TTyRichDocument): UTF8String;
begin
  case ADoc.DominantLineBreak of
    rsCR: Result := #13;
    rsLF: Result := #10;
  else
    Result := #13#10;
  end;
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
    AssertEquals('the run after the undo', 'a b' + BreakOf(d) + 'cpastedd', AllText(d));
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
    AssertTrue('the text', AllText(d) = 'a-- ' + BreakOf(d) + 'Tombc');
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

{ Bytes as they are, in a string (no code page conversion). }
function Raw(const ABytes: array of Byte): RawByteString;
var
  i: Integer;
begin
  Result := '';
  SetLength(Result, Length(ABytes));
  for i := 0 to High(ABytes) do Result[i + 1] := AnsiChar(ABytes[i]);
  SetCodePage(Result, CP_UTF8, False);
end;

{ Task 10a (rereviewB-W45, out of scope 3): the storage counts characters per piece, a reader
  of a paragraph per paragraph; an insert that ends inside a UTF-8 sequence, or starts with a
  byte that continues one, would be counted two ways once the next insert joins it. The
  insert command raises before anything changes; whole characters (an invalid byte inside
  the text included) go in. }
procedure TTyRichCommandsTest.TestAnInsertThatCutsASequenceIsRefused;
var
  d: TTyRichDocument;

  procedure Refused(const AWhat: UTF8String; const AText: RawByteString);
  var
    raised: Boolean;
  begin
    raised := False;
    try
      d.Execute(TTyRichInsertText.Create(1, AText));
    except
      on ETyRichModel do raised := True;
    end;
    AssertTrue(AWhat + ': refused', raised);
    AssertEquals(AWhat + ': nothing changed', 'ab', AllText(d));
    AssertEquals(AWhat + ': nothing kept', 0, d.UndoDepth);
    AssertFalse(AWhat + ': not modified', d.Modified);
  end;

begin
  d := NewDoc('ab');
  try
    Refused('a lead byte alone', Raw([$C3]));
    Refused('a three-byte lead and one more', Raw([$E4, $B8]));
    Refused('a four-byte lead and two more', Raw([Ord('x'), $F0, $9F, $98]));
    Refused('a continuation first', Raw([$A9, Ord('x')]));
    Refused('an escape''s first byte at the end', Raw([Ord('x'), $F8]));
    AssertTrue('whole characters', d.Execute(TTyRichInsertText.Create(1,
      Raw([$C3, $A9, $E4, $B8, $AD]))));
    AssertTrue('in', Raw([Ord('a'), $C3, $A9, $E4, $B8, $AD, Ord('b')]) = RawByteString(AllText(d)));
    AssertEquals('as the storage counts them', 4, d.Text.Length);
    AssertTrue('a stray byte inside is a character', d.Execute(TTyRichInsertText.Create(0,
      Raw([Ord('x'), $80, Ord('y')]))));
    AssertEquals('three more', 7, d.Text.Length);
  finally
    d.Free;
  end;
end;

{ ClearUndo lets every step go - undo and redo - and the text stays; inside an update or a
  running command it raises. }
procedure TTyRichCommandsTest.TestClearUndoDropsTheHistory;
var
  d: TTyRichDocument;
  raised: Boolean;
begin
  d := NewDoc('abc');
  try
    Type_(d, 'x');
    d.BreakMerge;
    Type_(d, 'y');
    d.Undo;
    AssertEquals('one to undo', 1, d.UndoDepth);
    AssertEquals('one to redo', 1, d.RedoDepth);
    AssertTrue('the history holds bytes', d.HistoryBytes > 0);
    d.Modified := False;
    d.ClearUndo;
    AssertEquals('none to undo', 0, d.UndoDepth);
    AssertEquals('none to redo', 0, d.RedoDepth);
    AssertFalse('cannot undo', d.CanUndo);
    AssertEquals('no bytes', 0, d.HistoryBytes);
    AssertEquals('the text stays', 'abcx', AllText(d));
    AssertFalse('not a change', d.Modified);
    raised := False;
    d.BeginUpdate;
    try
      try
        d.ClearUndo;
      except
        on ETyRichModel do raised := True;
      end;
    finally
      d.EndUpdate;
    end;
    AssertTrue('refused inside an update', raised);
  finally
    d.Free;
  end;
end;

{ ---- Task 10c: a fragment of another document ---- }

function RtfDoc(const S: UTF8String): TTyRichDocument;
var
  st: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  st := TBytesStream.Create(Bytes(S));
  try
    TyRichLoadRtfFull(Result, st);
  finally
    st.Free;
  end;
end;

{ S read as a clipboard's RTF and inserted at APos: what Execute answered. }
function PasteRtf(ADoc: TTyRichDocument; APos: TTyRichPos; const S: UTF8String;
  AFlatten: Boolean = False): Boolean;
var
  src: TTyRichDocument;
  ends: Boolean;
begin
  src := TyRichReadRtfFragment(Bytes(S), ends);
  if src = nil then raise Exception.Create('no fragment read');
  Result := ADoc.Execute(TTyRichInsertFragment.Create(APos, src, ends, AFlatten));
end;

function AlignOf(ADoc: TTyRichDocument; AIndex: Integer): TTyParaAlign;
begin
  Result := ADoc.Formats.ParaFormat(ADoc.ParaFormatOf(AIndex)).Align;
end;

function CharAt(ADoc: TTyRichDocument; APos: TTyRichPos): TTyCharFormat;
var
  p, i, k: Integer;
  runs: TTyRunArray;
begin
  p := ADoc.Text.ParaOfPos(APos);
  runs := ADoc.RunsOf(p);
  k := 0;
  for i := 0 to High(runs) do
    if runs[i].Start <= APos - ADoc.Text.ParaStart(p) then k := i;
  Result := ADoc.Formats.CharFormat(runs[k].Format);
end;

const
  // a right-aligned paragraph in Arial, then a justified one
  FragTarget = '{\rtf1\ansi{\fonttbl{\f0 Arial;}{\f1 Times;}}\pard\qr\f0 abcd\par\pard\qj efgh\par}';
  // one part: inline, bold Times
  FragInline = '{\rtf1\ansi{\fonttbl{\f0 Times;}}\f0\b XY}';
  // two paragraphs, centred then left; the last without its paragraph mark
  FragOpen = '{\rtf1\ansi{\fonttbl{\f0 Times;}}\pard\qc\f0 A\par\pard\ql B}';
  // the same with its mark
  FragEnded = '{\rtf1\ansi{\fonttbl{\f0 Times;}}\pard\qc\f0 A\par\pard\ql B\par}';

{ How the pasted paragraphs meet the one they land in (Word's rule: a paragraph's format goes
  with its mark): inline - the paragraph keeps its own format, the text after the place follows;
  several - the first joins the text before (and takes the first pasted paragraph's format,
  whose mark ends it), the last joins the text after (and keeps the paragraph's own); ending
  with a mark - the text after stays a paragraph of its own. At a paragraph's start, middle and
  end, in an empty paragraph, in an empty document; one undo step each, undone and redone. }
procedure TTyRichCommandsTest.TestAFragmentMeetsTheParagraphAtItsPlace;
var
  d: TTyRichDocument;
  before: string;

  procedure Paras(const AWhat: string; const ATexts: array of UTF8String;
    const AAligns: array of TTyParaAlign);
  var
    i: Integer;
  begin
    AssertEquals(AWhat + ': paragraphs', Length(ATexts), d.Text.ParaCount);
    for i := 0 to High(ATexts) do
    begin
      AssertEquals(Format('%s: paragraph %d', [AWhat, i]), ATexts[i], ParaText(d, i));
      AssertTrue(Format('%s: paragraph %d format', [AWhat, i]), AlignOf(d, i) = AAligns[i]);
    end;
  end;

  procedure Round(const AWhat: string);
  var
    after: string;
  begin
    AssertEquals(AWhat + ': one undo step', 1, d.UndoDepth);
    AssertEquals(AWhat + ': its name', rsRichUndoPaste, d.UndoDescription);
    after := Dump(d);
    d.Undo;
    AssertEquals(AWhat + ': undone', before, Dump(d));
    d.Redo;
    AssertEquals(AWhat + ': redone', after, Dump(d));
    AssertEquals(AWhat + ': redo leaves it one step', 1, d.UndoDepth);
  end;

begin
  // inline, in the middle
  d := RtfDoc(FragTarget);
  try
    before := Dump(d);
    SetLength(FChanges, 0);
    d.OnChange := @DocChanged;
    AssertTrue('inline: ran', PasteRtf(d, 2, FragInline));
    AssertEquals('inline: one change', 1, Length(FChanges));
    Paras('inline', ['abXYcd', 'efgh'], [paraRight, paraJustify]);
    AssertTrue('inline: bold', fsBold in CharAt(d, 2).Style);
    AssertEquals('inline: its font', 'Times', CharAt(d, 3).FontName);
    AssertFalse('inline: the text after keeps its own', fsBold in CharAt(d, 4).Style);
    AssertEquals('inline: in its own font', 'Arial', CharAt(d, 4).FontName);
    Round('inline');
  finally
    d.Free;
  end;
  // several, the last without its mark, in the middle
  d := RtfDoc(FragTarget);
  try
    before := Dump(d);
    PasteRtf(d, 2, FragOpen);
    Paras('several', ['abA', 'Bcd', 'efgh'], [paraCenter, paraRight, paraJustify]);
    AssertEquals('several: the text before keeps its font', 'Arial', CharAt(d, 0).FontName);
    AssertEquals('several: the pasted keeps its', 'Times', CharAt(d, 2).FontName);
    AssertEquals('several: the text after keeps its', 'Arial', CharAt(d, d.Text.ParaStart(1) + 1).FontName);
    Round('several');
  finally
    d.Free;
  end;
  // ending with a mark: middle, start, end
  d := RtfDoc(FragTarget);
  try
    before := Dump(d);
    PasteRtf(d, 2, FragEnded);
    Paras('ended, middle', ['abA', 'B', 'cd', 'efgh'], [paraCenter, paraLeft, paraRight, paraJustify]);
    Round('ended, middle');
  finally
    d.Free;
  end;
  d := RtfDoc(FragTarget);
  try
    before := Dump(d);
    PasteRtf(d, 0, FragEnded);
    Paras('ended, at the start', ['A', 'B', 'abcd', 'efgh'], [paraCenter, paraLeft, paraRight,
      paraJustify]);
    Round('ended, at the start');
  finally
    d.Free;
  end;
  d := RtfDoc(FragTarget);
  try
    before := Dump(d);
    PasteRtf(d, 4, FragOpen);
    Paras('several, at the end', ['abcdA', 'B', 'efgh'], [paraCenter, paraRight, paraJustify]);
    Round('several, at the end');
  finally
    d.Free;
  end;
  // an empty paragraph
  d := RtfDoc('{\rtf1\ansi\pard\qr\par\pard x}');
  try
    before := Dump(d);
    PasteRtf(d, 0, FragEnded);
    Paras('an empty paragraph', ['A', 'B', '', 'x'], [paraCenter, paraLeft, paraRight, paraLeft]);
    Round('an empty paragraph');
  finally
    d.Free;
  end;
  // an empty document: ended, and inline
  d := TTyRichDocument.Create;
  try
    before := Dump(d);
    PasteRtf(d, 0, FragEnded);
    Paras('an empty document', ['A', 'B', ''], [paraCenter, paraLeft, paraLeft]);
    Round('an empty document');
  finally
    d.Free;
  end;
  d := TTyRichDocument.Create;
  try
    before := Dump(d);
    PasteRtf(d, 0, FragInline);
    Paras('inline into an empty document', ['XY'], [paraLeft]);
    AssertTrue('bold', fsBold in CharAt(d, 1).Style);
    Round('inline into an empty document');
  finally
    d.Free;
  end;
end;

{ Rows go in as rows outside a table - the paragraph split before them when text stands before
  the place, never a row joined with text - and as the text of the cell the place is in (or
  of no table, flattened on request): never a nested table. }
procedure TTyRichCommandsTest.TestAFragmentsRowsAreRowsOutsideATableAndTextInOne;
const
  Rows = '{\rtf1\ansi\trowd\cellx1000\cellx2000\pard\intbl a\cell b\cell\row}';
var
  d: TTyRichDocument;
  c: TTyRichCell;
  before: string;
  i: Integer;
begin
  d := RtfDoc(FragTarget);
  try
    before := Dump(d);
    PasteRtf(d, 2, Rows);
    AssertEquals('split around the row', 'ab|a|b|cd|efgh', ParaText(d, 0) + '|' + ParaText(d, 1) +
      '|' + ParaText(d, 2) + '|' + ParaText(d, 3) + '|' + ParaText(d, 4));
    AssertTrue('the text before: no cell', d.CellAt(0) = nil);
    AssertTrue('and its own format', AlignOf(d, 0) = paraRight);
    c := d.CellAt(1);
    AssertTrue('a row', (c <> nil) and (c.Index = 0) and (c.Row.CellCount = 2));
    AssertTrue('its second cell', (d.CellAt(2) <> nil) and (d.CellAt(2).Row = c.Row) and
      (d.CellAt(2).Index = 1));
    AssertTrue('the text after: no cell', d.CellAt(3) = nil);
    AssertTrue('and its own format', AlignOf(d, 3) = paraRight);
    d.Undo;
    AssertEquals('undone', before, Dump(d));
    d.Redo;
    AssertTrue('redone: the row', (d.CellAt(1) <> nil) and (d.CellAt(2).Index = 1));
  finally
    d.Free;
  end;
  // at a paragraph's start: nothing to split before
  d := RtfDoc(FragTarget);
  try
    PasteRtf(d, 0, Rows);
    AssertEquals('at the start: paragraphs', 4, d.Text.ParaCount);
    AssertEquals('the row first', 'a', ParaText(d, 0));
    AssertTrue('a cell', d.CellAt(0) <> nil);
    AssertEquals('then the paragraph', 'abcd', ParaText(d, 2));
    AssertTrue('in no table', d.CellAt(2) = nil);
  finally
    d.Free;
  end;
  // inside a cell: the cells' paragraphs as paragraphs of that cell
  d := RtfDoc('{\rtf1\ansi\trowd\cellx1000\pard\intbl xy\cell\row\pard z\par}');
  try
    c := d.CellAt(0);
    PasteRtf(d, 1, Rows);
    AssertEquals('in a cell: paragraphs', 4, d.Text.ParaCount);
    AssertEquals('flattened', 'xa|b|y|z', ParaText(d, 0) + '|' + ParaText(d, 1) + '|' +
      ParaText(d, 2) + '|' + ParaText(d, 3));
    for i := 0 to 2 do
      AssertTrue(Format('paragraph %d in the cell it went in', [i]), d.CellAt(i) = c);
    AssertEquals('the table keeps its row', 1, c.Table.RowCount);
    AssertTrue('after it, none', d.CellAt(3) = nil);
  finally
    d.Free;
  end;
  // flattened on request outside a table
  d := RtfDoc(FragTarget);
  try
    PasteRtf(d, 2, Rows, True);
    AssertEquals('flat: paragraphs', 4, d.Text.ParaCount);
    for i := 0 to d.Text.ParaCount - 1 do
      AssertTrue(Format('flat: paragraph %d in no table', [i]), d.CellAt(i) = nil);
    AssertEquals('flat: text', 'aba|b|cd|efgh', ParaText(d, 0) + '|' + ParaText(d, 1) + '|' +
      ParaText(d, 2) + '|' + ParaText(d, 3));
  finally
    d.Free;
  end;
end;

{ The source's page, margins, default tab, \info and default font do not come along; a run
  that had no font of its own in the source gets the source's default font by name (and its
  size), so it looks as it looked there. }
procedure TTyRichCommandsTest.TestAFragmentBringsNoDocumentLevelThing;
var
  d, src: TTyRichDocument;
  pw, ml: Integer;
  def: TTyCharFormat;
  f: TTyCharFormat;
begin
  d := RtfDoc(FragTarget);
  try
    pw := d.PaperWidth;
    ml := d.MarginLeft;
    def := d.DefaultCharFormat;
    PasteRtf(d, 2, '{\rtf1\ansi\deff0{\fonttbl{\f0 Courier New;}}\paperw5000\margl100' +
      '\deftab100{\info{\title T}}\fs40 xy}');
    AssertEquals('the text', 'abxycd', ParaText(d, 0));
    AssertEquals('the page stays', pw, d.PaperWidth);
    AssertEquals('the margin stays', ml, d.MarginLeft);
    AssertTrue('the default font stays', def.Equals(d.DefaultCharFormat));
    AssertEquals('the run in the source''s default font, named', 'Courier New', CharAt(d, 2).FontName);
    AssertEquals('its size', 40, CharAt(d, 2).SizeHalfPt);
  finally
    d.Free;
  end;
  // a source whose runs name no font: the source's default is named on them
  src := TTyRichDocument.Create;
  d := TTyRichDocument.Create;
  try
    f := TyDefaultCharFormat;
    f.FontName := 'SimSun';
    f.SizeHalfPt := 21;
    TCmdTestBuilder.SetDefaultCharFormat(src, f);
    src.Execute(TTyRichInsertText.Create(0, 'xy'));
    src.ClearUndo;
    f := TyDefaultCharFormat;
    f.Style := [fsBold];
    // (a run as a reader leaves one with no font word: no name, no size)
    src.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 2), [cffFontName, cffCharset, cffSize,
      cffBold], f));
    AssertEquals('(the source''s run names no font)', '', src.Formats.CharFormat(src.RunsOf(0)[0].Format).FontName);
    AssertTrue(d.Execute(TTyRichInsertFragment.Create(0, src, False)));
    src := nil;
    f := CharAt(d, 0);
    AssertEquals('named', 'SimSun', f.FontName);
    AssertEquals('sized', 21, f.SizeHalfPt);
    AssertTrue('and its own', fsBold in f.Style);
    AssertEquals('the target''s default untouched', '', d.DefaultCharFormat.FontName);
  finally
    src.Free;
    d.Free;
  end;
end;

{ An object goes in as the same object (shared, counted: it lives while the target or its
  history holds it, and goes with them); the history keeps one step that holds the fragment -
  its text and its paragraphs - and nothing of the source. }
procedure TTyRichCommandsTest.TestAFragmentSharesItsObjectsAndKeepsOneStep;
var
  d, src: TTyRichDocument;
  obj: TCmdCountedOpaque;
  i: Integer;
  big: UTF8String;
  runs: TTyRunArray;
begin
  src := TTyRichDocument.Create;
  d := NewDoc('ab');
  try
    obj := TCmdCountedOpaque.Create('{\*\x}');
    src.Execute(TTyRichInsertText.Create(0, 'p q'));
    src.Execute(TTyRichInsertObject.Create(1, obj));
    AssertEquals('one object', 1, TCmdCountedOpaque.Live);
    AssertTrue(d.Execute(TTyRichInsertFragment.Create(1, src, False)));
    src := nil;
    AssertEquals('the source went, the object stays', 1, TCmdCountedOpaque.Live);
    runs := d.RunsOf(0);
    AssertTrue('the same object', (Length(runs) >= 2) and (runs[1].Obj = obj));
    d.Undo;
    AssertEquals('undone: the history holds it', 1, TCmdCountedOpaque.Live);
    d.Redo;
    AssertTrue('redone: the same object', d.RunsOf(0)[1].Obj = obj);
    d.Execute(TTyRichDelete.Create(0, d.Text.Length));
    d.ClearUndo;
    AssertEquals('gone with the last holder', 0, TCmdCountedOpaque.Live);
  finally
    src.Free;
    d.Free;
  end;
  // a fragment of 2000 paragraphs: one step, holding about its text and its paragraphs
  big := '{\rtf1\ansi ';
  for i := 1 to 2000 do big := big + '\b para ' + IntToStr(i) + '\b0  plain\par ';
  big := big + '}';
  d := NewDoc('xy');
  try
    PasteRtf(d, 1, big);
    AssertEquals('paragraphs', 2001, d.Text.ParaCount);
    AssertEquals('one step', 1, d.UndoDepth);
    AssertTrue(Format('what the step keeps (%d bytes)', [d.HistoryBytes]),
      (d.HistoryBytes >= d.Text.Length - 2) and (d.HistoryBytes < d.Text.Length + 2001 * 160));
    d.Undo;
    AssertEquals('undone', 'xy', AllText(d));
    AssertEquals('one paragraph', 1, d.Text.ParaCount);
  finally
    d.Free;
  end;
end;

{ Where the text cannot change (a row that holds a nested table), the command does not run
  (CanExecute), and inside a composite the refusal says FixedRow. }
procedure TTyRichCommandsTest.TestAFragmentIsRefusedInARowWithANestedTable;
const
  Nested = '{\rtf1 \trowd\cellx1000\cellx2000\pard\intbl a\cell \pard\intbl\itap2 x' +
    '\nestcell{\*\nesttableprops\trowd\cellx500\nestrow}{\nonesttables\par}\pard\intbl\cell' +
    '\row\pard b\par}';
var
  d, src: TTyRichDocument;
  ends, raised: Boolean;
  comp: TTyRichCompositeCommand;
  before: UTF8String;
begin
  d := RtfDoc(Nested);
  try
    AssertTrue('(a row with a nested table)', d.CellAt(0).Row.HoldsNestedTable);
    before := AllText(d);
    src := TyRichReadRtfFragment(Bytes(FragEnded), ends);
    AssertFalse('refused', d.Execute(TTyRichInsertFragment.Create(1, src, ends)));
    AssertEquals('nothing changed', before, AllText(d));
    AssertEquals('nothing kept', 0, d.UndoDepth);
    comp := TTyRichCompositeCommand.Create;
    comp.Add(TTyRichInsertText.Create(d.Text.Length, 'z'));
    src := TyRichReadRtfFragment(Bytes(FragEnded), ends);
    comp.Add(TTyRichInsertFragment.Create(1, src, ends));
    raised := False;
    try
      d.Execute(comp);
    except
      on E: ETyRichRefused do raised := E.FixedRow;
    end;
    AssertTrue('a composite: refused for the row', raised);
    AssertEquals('reverted', before, AllText(d));
  finally
    d.Free;
  end;
end;

{ What another program may put there: no signature - nothing; only a header, an empty body -
  no character and no paragraph mark (nothing to insert: the command changes nothing and is
  not kept); a paragraph mark alone - one paragraph break; an unterminated group - what was
  read; megabytes of one paragraph - one paragraph. }
procedure TTyRichCommandsTest.TestReadingAFragmentOfUntrustedBytes;
var
  src, d: TTyRichDocument;
  ends: Boolean;
  s: UTF8String;
begin
  AssertTrue('no RTF', TyRichReadRtfFragment(Bytes('hello'), ends) = nil);
  AssertTrue('nothing', TyRichReadRtfFragment(nil, ends) = nil);
  src := TyRichReadRtfFragment(Bytes('{\rtf1\ansi{\fonttbl{\f0 Arial;}}}'), ends);
  try
    AssertTrue('a header: read', src <> nil);
    AssertEquals('a header: no character', 0, src.Text.Length);
    AssertFalse('a header: no paragraph mark', ends);
  finally
    src.Free;
  end;
  src := TyRichReadRtfFragment(Bytes('{\rtf1}'), ends);
  try
    AssertFalse('an empty body: no paragraph mark', ends);
  finally
    src.Free;
  end;
  src := TyRichReadRtfFragment(Bytes('{\rtf1\par}'), ends);
  try
    AssertTrue('a mark alone: a mark', ends);
  finally
    src.Free;
  end;
  src := TyRichReadRtfFragment(Bytes('{\rtf1 abc{\b def'), ends);
  try
    AssertTrue('unterminated: read', src <> nil);
    AssertEquals('unterminated: the text', 'abcdef', AllText(src));
  finally
    src.Free;
  end;
  d := NewDoc('xy');
  try
    src := TyRichReadRtfFragment(Bytes('{\rtf1\ansi{\fonttbl{\f0 Arial;}}}'), ends);
    d.Execute(TTyRichInsertFragment.Create(1, src, ends));
    AssertEquals('nothing inserted', 'xy', AllText(d));
    AssertEquals('nothing kept', 0, d.UndoDepth);
    src := TyRichReadRtfFragment(Bytes('{\rtf1\par}'), ends);
    d.Execute(TTyRichInsertFragment.Create(1, src, ends));
    AssertEquals('a mark: a paragraph break', 2, d.Text.ParaCount);
    SetLength(s, 3 * 1024 * 1024);
    FillChar(s[1], Length(s), 'w');
    d.Undo;
    PasteRtf(d, 1, '{\rtf1 ' + s + '}');
    AssertEquals('megabytes of one paragraph', 1, d.Text.ParaCount);
    AssertEquals('all of it', Int64(2 + Length(s)), d.Text.Length);
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyRichCommandsTest);

end.
