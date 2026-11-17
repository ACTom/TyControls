unit test.richedit.edit;

{ TTyRichEdit as an editor by keyboard (Task 10a): typing, Backspace, Delete, Enter, Shift+Enter,
  Tab, undo and redo, cut - every edit a command of the document, the caret placed by the edit,
  one OnChange and one OnSelectionChange per key, ReadOnly a viewer, the engine's refusals
  told and never raised to the user, and what one keystroke costs in a document of two
  million lines.

  Headless, on the probe of test.richedit.control (TRichProbe: the test device, the clipboard
  double, the invalidation and paint counters, the forced device scale), subclassed here for
  what an editor adds (a typed character, EditRefused). No window, no clipboard, no message
  loop. Every bound is a count, never a time. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  LMessages, BGRABitmap, BGRABitmapTypes, BGRAWritePNG,
  tyControls.Controller, tyControls.Painter, tyControls.TextMenu, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.TextIO, tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite,
  tyControls.RichEdit.Layout, tyControls.RichEdit, test.richedit.layoutdevice,
  test.richedit.control;

type
  TLayouterAccess = class(TTyRichLayouter)
  end;

  { The control probe with an editor's seams. }
  TEditProbe = class(TRichProbe)
  protected
    procedure EditRefused(const AReason: string); override;
    function TypingFormat: TTyCharFormatId; override;
    function PlainTextDocument: Boolean; override;
  public
    Refused: Integer;
    LastReason: string;
    { TypingFormat's answer when >= 0 (the seam a pending format will use). }
    ForcedFormat: Integer;
    constructor Create(AOwner: TComponent); override;
    { One character typed (UTF8KeyPress, as LCL delivers it). }
    procedure Key8(const AChar: RawByteString);
    procedure Leave;
  public
    { A document set through Lines.Text taken as a rich one (fix wave W13: R60 makes a plain
      text document paste text only; the paste suite's documents typed in are rich ones). }
    RichDocument: Boolean;
    { RunEdit as a user's edit (fix wave W13: a command of the application's own). }
    function RunUser(ACmd: TTyRichCommand): Boolean;
  end;

  TTyRichEditEditTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TEditProbe;
    FChanges, FSelChanges: Integer;
    FPaintScale: Integer;
    FTemp: string;
    // a save's progress handler that types (TestEveryRefusalThroughAKey)
    FSaveCalls, FSaveRefused, FSaveRaised: Integer;
    FSaveCancelAt: Integer;
    // OnEditRefused (fix wave W11): calls, and what the handler does
    FRefusedEvents: Integer;
    FRefusedEdits: Boolean;
    procedure Changed(Sender: TObject);
    procedure SelChanged(Sender: TObject);
    procedure TypeWhileSaving(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure CountSave(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    function NewProbe: TEditProbe;
    procedure Chars(const S: RawByteString);
    procedure Press(AKey: Word; AShift: TShiftState = []);
    procedure SetText(const S: string);
    procedure SetLinesOf(ACount: Integer);
    procedure LoadRtf(const S: RawByteString);
    procedure LoadBytes(const B: TBytes);
    procedure PaintAll;
    procedure CheckSurface(const AWhat: string);
    procedure ResetEvents;
    function CharFormatAt(APos: TTyRichPos): TTyCharFormat;
    function TempDir: string;
    procedure KeystrokeCase(AScale: Integer);
    // fix wave W11
    procedure ScaledProbe(AScale: Integer);
    procedure SetVariedLines(ACount: Integer; const ALong: string = ''; ALongAt: Integer = -1);
    procedure EdgeCases(AScale: Integer);
    procedure RefusedEdits(Sender: TObject; const AReason: string);
    // fix wave W13: an OnEditRefused that loads a document
    procedure LoadOnRefusal(Sender: TObject; const AReason: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // the brief's
    procedure TestTypingIsOneMergedCommand;
    procedure TestEnterInheritsParagraphFormat;
    procedure TestEnterOnAnEmptyListItemLeavesTheList;
    procedure TestReadOnlyRefusesEveryEdit;
    procedure TestTypingInALargeDocumentTouchesOneParagraph;
    // one per rule
    procedure TestTheRunOfTypingEndsWhereTheMemoEndsIt;
    procedure TestTypingOverASelectionIsOneStep;
    procedure TestTypingTakesTheFormatAtTheCaret;
    procedure TestBackspaceAndDeleteTakeOneCaretPlace;
    procedure TestTheEndsOfTheDocumentDoNothing;
    procedure TestCtrlBackspaceAndCtrlDeleteGoByWord;
    procedure TestShiftEnterInsertsALineBreak;
    procedure TestWantTabsBothWays;
    procedure TestUndoAndRedoPlaceTheCaret;
    procedure TestCutIsOneStepAndPutsBothFlavours;
    procedure TestOneChangeAndOneSelectionChangePerKey;
    procedure TestEveryRefusalThroughAKey;
    procedure TestARefusalOfTheEngineIsToldAndUndone;
    procedure TestASelectionOfAMillionParagraphsTypedOverIsOneCommand;
    procedure TestAKeystrokePaintsOnlyItsParagraph;
    procedure TestADeletionAcrossCellsLeavesAValidDocument;
    procedure TestTypingOverASelectedObjectReplacesIt;
    procedure TestSelTextReplacesTheSelection;
    procedure TestKeysInsideAnUpdateDoNothing;
    // the parked items (rule 11)
    procedure TestTheControlsFontStyleReachesTheText;
    procedure TestANewDocumentIsSavedWithItsFontAndPage;
    procedure TestATextSaveReportsProgressAndCanBeCancelled;
    // fix wave W11
    procedure TestTheSurfaceAfterAnEditAtTheViewsBottomIsAFullRedraw;
    procedure TestUndoPutsTheSelectionBackAsItWas;
    procedure TestATypingMistakeUndoneSavesTheFile;
    procedure TestALineThatCannotBeAssignedStaysAsItWas;
    procedure TestARefusalIsToldInTheControlsWordsAfterTheEdit;
    procedure TestTableEdgesFromTheKeyboard;
    procedure TestAtTheCutOfALongParagraph;
    procedure TestTheMenuReadOnlyAndCtrlTabOfAnEditor;
    procedure TestListItemsAndJoinsByKey;
    procedure TestShiftEnterInATextDocumentMakesAParagraph;
    // fix wave W13
    procedure TestARefusalAcrossCellsIsToldOutsideTheReadScope;
    procedure TestWholeRowsAtTheTextsEndAreRefused;
    procedure TestACutCopiesWhatItRemoves;
    procedure TestARefusedCommandIsToldItsOwnReason;
    // fix wave W14 (V-M9)
    procedure TestPastesAndTheirUndoKeepTheSurfaceRight;
  end;

implementation

const
  BS = '\';
  BigLines = 2000000;
  MillionLines = 1000000;

var
  GBig, GMillion: TBytes;

{ A character as UTF-8, from its number (this file stays ASCII). }
function U(ACode: Cardinal): RawByteString;
begin
  if ACode < $80 then Result := AnsiChar(ACode)
  else if ACode < $800 then
    Result := AnsiChar($C0 or (ACode shr 6)) + AnsiChar($80 or (ACode and $3F))
  else if ACode < $10000 then
    Result := AnsiChar($E0 or (ACode shr 12)) + AnsiChar($80 or ((ACode shr 6) and $3F)) +
      AnsiChar($80 or (ACode and $3F))
  else
    Result := AnsiChar($F0 or (ACode shr 18)) + AnsiChar($80 or ((ACode shr 12) and $3F)) +
      AnsiChar($80 or ((ACode shr 6) and $3F)) + AnsiChar($80 or (ACode and $3F));
  SetCodePage(Result, CP_UTF8, False);
end;

{ 'Line 1' .. 'Line ACount', one a paragraph (LF). }
function MakeLines(ACount: Integer): TBytes;
var
  ms: TMemoryStream;
  i: Integer;
  s: RawByteString;
begin
  ms := TMemoryStream.Create;
  try
    ms.Size := 16 * Int64(ACount);
    ms.Position := 0;
    for i := 1 to ACount do
    begin
      s := 'Line ' + IntToStr(i);
      if i < ACount then s := s + #10;
      ms.WriteBuffer(s[1], Length(s));
    end;
    Result := nil;
    SetLength(Result, ms.Position);
    Move(ms.Memory^, Result[0], ms.Position);
  finally
    ms.Free;
  end;
end;

function BigText: TBytes;
begin
  if GBig = nil then GBig := MakeLines(BigLines);
  Result := GBig;
end;

function MillionText: TBytes;
begin
  if GMillion = nil then GMillion := MakeLines(MillionLines);
  Result := GMillion;
end;

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function FileBytes(const APath: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function FixtureFile(const AName: string): TBytes;
begin
  Result := FileBytes(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName);
end;

function StrOfBytes(const B: TBytes): RawByteString;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

{ An RTF file of AParas paragraphs of words, and how many bytes its first paragraphs take
  (a first slice that indexes them and leaves the rest loading). }
function PlainRtf(AParas: Integer): TBytes;
var
  s: RawByteString;
  i: Integer;
begin
  s := '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}' +
    #13#10;
  for i := 0 to AParas - 1 do
    s := s + BS + 'pard' + BS + 'f0 Paragraph ' + IntToStr(i) + ' of the file.' + BS + 'par' +
      #13#10;
  s := s + '}';
  Result := RawBytes(s);
end;

{ ---- the probe ---- }

constructor TEditProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ForcedFormat := -1;
end;

procedure TEditProbe.EditRefused(const AReason: string);
begin
  Inc(Refused);
  LastReason := AReason;
  inherited EditRefused(AReason);
end;

function TEditProbe.TypingFormat: TTyCharFormatId;
begin
  if ForcedFormat >= 0 then Result := ForcedFormat else Result := inherited TypingFormat;
end;

procedure TEditProbe.Key8(const AChar: RawByteString);
var
  k: TUTF8Char;
begin
  k := '';
  SetLength(k, Length(AChar));
  if AChar <> '' then Move(AChar[1], k[1], Length(AChar));
  UTF8KeyPress(k);
end;

{ The focus leaving as LCL delivers it: the window loses the focus (LM_KILLFOCUS, which
  win32 sends first, while the window still has the input context), then CM_EXIT's DoExit
  from inside the new control's set-focus. }
procedure TEditProbe.Leave;
begin
  Perform(LM_KILLFOCUS, 0, 0);
  DoExit;
end;

function TEditProbe.PlainTextDocument: Boolean;
begin
  Result := inherited PlainTextDocument and not RichDocument;
end;

function TEditProbe.RunUser(ACmd: TTyRichCommand): Boolean;
begin
  Result := RunEdit(ACmd, True);
end;

{ ---- the suite ---- }

procedure TTyRichEditEditTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FPaintScale := 1;
  FTemp := '';
  FRich := NewProbe;
  ResetEvents;
end;

procedure TTyRichEditEditTest.TearDown;
var
  sr: TSearchRec;
begin
  TyForceDeviceScaleForTest(0, False);
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
  if (FTemp <> '') and DirectoryExists(FTemp) then
  begin
    if FindFirst(FTemp + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Attr and faDirectory) = 0 then DeleteFile(FTemp + sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    RemoveDir(FTemp);
  end;
end;

function TTyRichEditEditTest.NewProbe: TEditProbe;
begin
  Result := TEditProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.OnChange := @Changed;
  Result.OnSelectionChange := @SelChanged;
  Result.ResetCounts;
end;

procedure TTyRichEditEditTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyRichEditEditTest.SelChanged(Sender: TObject);
begin
  Inc(FSelChanges);
end;

procedure TTyRichEditEditTest.ResetEvents;
begin
  FChanges := 0;
  FSelChanges := 0;
  if FRich <> nil then
  begin
    FRich.Refused := 0;
    FRich.LastReason := '';
  end;
end;

{ Each character of S typed, as LCL delivers them (one UTF8KeyPress each). }
procedure TTyRichEditEditTest.Chars(const S: RawByteString);
var
  i, n: Integer;
  b: Byte;
begin
  i := 1;
  while i <= Length(S) do
  begin
    b := Byte(S[i]);
    if b < $C0 then n := 1
    else if b < $E0 then n := 2
    else if b < $F0 then n := 3
    else n := 4;
    FRich.Key8(Copy(S, i, n));
    Inc(i, n);
  end;
end;

procedure TTyRichEditEditTest.Press(AKey: Word; AShift: TShiftState);
begin
  FRich.Press(AKey, AShift);
end;

procedure TTyRichEditEditTest.SetText(const S: string);
begin
  FRich.Lines.Text := S;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichEditEditTest.SetLinesOf(ACount: Integer);
var
  sl: TStringList;
  i: Integer;
begin
  sl := TStringList.Create;
  try
    for i := 0 to ACount - 1 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichEditEditTest.LoadRtf(const S: RawByteString);
begin
  LoadBytes(RawBytes(S));
  FRich.FinishLoading;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichEditEditTest.LoadBytes(const B: TBytes);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(B);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
end;

procedure TTyRichEditEditTest.PaintAll;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width * FPaintScale, FRich.Height * FPaintScale);
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), True);
  finally
    bmp.Free;
  end;
end;

{ The kept surface after a paint equals the surface a full redraw makes. }
procedure TTyRichEditEditTest.CheckSurface(const AWhat: string);
var
  kept: TBGRABitmap;
  x, y, diff, fx, fy: Integer;
  a, b: PBGRAPixel;
begin
  PaintAll;
  AssertTrue(AWhat + ': a surface', FRich.Surf <> nil);
  kept := FRich.Surf.Duplicate as TBGRABitmap;
  try
    FRich.RedrawAll;
    PaintAll;
    diff := 0;
    fx := -1;
    fy := -1;
    for y := 0 to FRich.Height * FRich.Scale - 1 do
    begin
      a := kept.ScanLine[y];
      b := FRich.Surf.ScanLine[y];
      for x := 0 to FRich.Width * FRich.Scale - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green) or (a^.blue <> b^.blue) or
          (a^.alpha <> b^.alpha) then
        begin
          if diff = 0 then
          begin
            fx := x;
            fy := y;
          end;
          Inc(diff);
        end;
        Inc(a);
        Inc(b);
      end;
    end;
    AssertEquals(Format('%s: pixels that differ from a full redraw (the first at %d,%d)',
      [AWhat, fx, fy]), 0, diff);
  finally
    kept.Free;
  end;
end;

function TTyRichEditEditTest.CharFormatAt(APos: TTyRichPos): TTyCharFormat;
var
  d: TTyRichDocument;
  p, i, k: Integer;
  runs: TTyRunArray;
  o: TTyRichPos;
begin
  d := FRich.Document;
  p := d.Text.ParaOfPos(APos);
  o := APos - d.Text.ParaStart(p);
  runs := d.RunsOf(p);
  k := 0;
  for i := 0 to High(runs) do
    if runs[i].Start <= o then k := i;
  Result := d.Formats.CharFormat(runs[k].Format);
end;

function TTyRichEditEditTest.TempDir: string;
begin
  if FTemp = '' then
  begin
    FTemp := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyrichedit10a-' +
      IntToStr(GetProcessID) + '-' + IntToHex(Random($7FFFFFFF), 8) + PathDelim;
    ForceDirectories(FTemp);
  end;
  Result := FTemp;
end;

{ ---- the brief's tests ---- }

{ Typing is one command that the engine merges: every character - a space and a Chinese one
  too - in one undo step; undo takes the run back, redo puts it in again, the caret behind it. }
procedure TTyRichEditEditTest.TestTypingIsOneMergedCommand;
var
  typed: RawByteString;
begin
  SetText('');
  typed := 'Hello, world ' + U($4E2D) + U($6587);
  Chars(typed);
  AssertEquals('the text', string(typed), FRich.Lines[0]);
  AssertEquals('one undo step', 1, FRich.Document.UndoDepth);
  AssertEquals('described as typing', rsRichUndoTyping, FRich.Document.UndoDescription);
  AssertEquals('the caret behind it', Int64(15), FRich.CaretPos);
  AssertFalse('nothing selected', FRich.HasSelection);
  FRich.Undo;
  AssertEquals('undone: empty', Int64(0), FRich.Document.Text.Length);
  AssertEquals('undone: the caret where it was', Int64(0), FRich.CaretPos);
  FRich.Redo;
  AssertEquals('redone', string(typed), FRich.Lines[0]);
  AssertEquals('redone: the caret behind it', Int64(15), FRich.CaretPos);
  // control characters are no typing: DEL (Ctrl+Backspace on Windows), a C1 control
  FRich.Key8(#127);
  FRich.Key8(#8);
  FRich.Key8(U($85));
  AssertEquals('control characters typed nothing', string(typed), FRich.Lines[0]);
  AssertEquals('still one step', 1, FRich.Document.UndoDepth);
end;

{ Enter makes a new paragraph with the current paragraph's format (centred, indented: both
  parts, as WordPad splits) and the typing format (bold, what is typed there next); the caret
  at the new paragraph's start. The paragraph it left keeps its own. }
procedure TTyRichEditEditTest.TestEnterInheritsParagraphFormat;
var
  d: TTyRichDocument;
  pf0, pf1: TTyParaFormat;
begin
  LoadRtf('{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}' +
    BS + 'pard' + BS + 'qc' + BS + 'li720' + BS + 'f0' + BS + 'b Title' + BS + 'par' + BS +
    'pard' + BS + 'b0 plain' + BS + 'par}');
  d := FRich.Document;
  AssertEquals('two paragraphs', 2, d.Text.ParaCount);
  FRich.SelStart := 5;
  ResetEvents;
  AssertEquals('Enter is taken', 0, FRich.KeyResult(VK_RETURN, []));
  AssertEquals('a new paragraph', 3, d.Text.ParaCount);
  AssertEquals('empty', '', FRich.Lines[1]);
  AssertEquals('the caret at its start', d.Text.ParaStart(1), FRich.CaretPos);
  pf0 := d.Formats.ParaFormat(d.ParaFormatOf(0));
  pf1 := d.Formats.ParaFormat(d.ParaFormatOf(1));
  AssertTrue('the first kept its own', pf0.Align = paraCenter);
  AssertTrue('centred like it', pf1.Align = paraCenter);
  AssertEquals('indented like it', 720, pf1.LeftIndent);
  Chars('x');
  AssertTrue('typed bold (the typing format)', fsBold in CharFormatAt(FRich.CaretPos - 1).Style);
  // in the middle: both parts centred
  FRich.SelStart := 2;
  Press(VK_RETURN);
  AssertEquals('split', 'Ti', FRich.Lines[0]);
  AssertEquals('split, the rest', 'tle', FRich.Lines[1]);
  AssertTrue('both centred', d.Formats.ParaFormat(d.ParaFormatOf(1)).Align = paraCenter);
  AssertEquals('the caret at the second part''s start', d.Text.ParaStart(1), FRich.CaretPos);
end;

{ Enter on an EMPTY list item leaves the list: the item becomes a plain paragraph where it is,
  no paragraph is added, the caret stays - WordPad's way; on an item with text Enter makes the
  next item. One undo step each. }
procedure TTyRichEditEditTest.TestEnterOnAnEmptyListItemLeavesTheList;
var
  d: TTyRichDocument;
  pf: TTyParaFormat;
  depth: Integer;
begin
  SetText('item one' + LineEnding + 'after');
  d := FRich.Document;
  pf := TyDefaultParaFormat;
  pf.List.Kind := lkBullet;
  AssertTrue('a list item', d.Execute(TTyRichSetParaFormat.Create(0, 0, [pffList], pf)));
  d.ClearUndo;
  FRich.SelStart := 8;
  Press(VK_RETURN);
  AssertEquals('a new item', 3, d.Text.ParaCount);
  AssertTrue('in the list', d.Formats.ParaFormat(d.ParaFormatOf(1)).List.Kind = lkBullet);
  AssertEquals('the caret on it', d.Text.ParaStart(1), FRich.CaretPos);
  depth := d.UndoDepth;
  ResetEvents;
  Press(VK_RETURN);
  AssertEquals('no paragraph added', 3, d.Text.ParaCount);
  AssertTrue('out of the list', d.Formats.ParaFormat(d.ParaFormatOf(1)).List.Kind = lkNone);
  AssertTrue('the first item stays one', d.Formats.ParaFormat(d.ParaFormatOf(0)).List.Kind = lkBullet);
  AssertEquals('the caret stays', d.Text.ParaStart(1), FRich.CaretPos);
  AssertEquals('one undo step', depth + 1, d.UndoDepth);
  AssertEquals('one change', 1, FChanges);
  Chars('x');
  AssertEquals('typed into the plain paragraph', 'x', FRich.Lines[1]);
  AssertTrue('still plain', d.Formats.ParaFormat(d.ParaFormatOf(1)).List.Kind = lkNone);
  FRich.Undo;
  FRich.Undo;
  AssertTrue('undone: the item again', d.Formats.ParaFormat(d.ParaFormatOf(1)).List.Kind = lkBullet);
end;

{ ReadOnly is a viewer: no key of this task and no menu item changes the document (the keys
  are taken, Enter is left to the form), nothing is refused out loud; the caret, the
  selection and copying work; code still edits. }
procedure TTyRichEditEditTest.TestReadOnlyRefusesEveryEdit;
var
  d: TTyRichDocument;
  acts: ITyTextEditActions;
  before: string;
  undo, redo: Integer;

  procedure Check(const AWhat: string);
  begin
    AssertEquals(AWhat + ': the text', before, FRich.Lines.Text);
    AssertEquals(AWhat + ': the undo side', undo, d.UndoDepth);
    AssertEquals(AWhat + ': the redo side', redo, d.RedoDepth);
    AssertEquals(AWhat + ': no change', 0, FChanges);
    AssertEquals(AWhat + ': nothing refused out loud', 0, FRich.Refused);
  end;

begin
  SetText('abc' + LineEnding + 'def');
  d := FRich.Document;
  // a step to undo and one to redo
  d.Execute(TTyRichInsertText.Create(0, 'x'));
  d.BreakMerge;
  d.Execute(TTyRichInsertText.Create(0, 'y'));
  d.Undo;
  FRich.ReadOnly := True;
  FRich.WantTabs := True;
  before := FRich.Lines.Text;
  undo := d.UndoDepth;
  redo := d.RedoDepth;
  FRich.SelStart := 2;
  ResetEvents;
  Chars('qz' + U($4E2D));
  Check('typing');
  AssertEquals('Backspace taken', 0, FRich.KeyResult(VK_BACK, []));
  AssertEquals('Ctrl+Backspace taken', 0, FRich.KeyResult(VK_BACK, [ssCtrl]));
  AssertEquals('Delete taken', 0, FRich.KeyResult(VK_DELETE, []));
  AssertEquals('Ctrl+Delete taken', 0, FRich.KeyResult(VK_DELETE, [ssCtrl]));
  AssertEquals('Tab taken (WantTabs)', 0, FRich.KeyResult(VK_TAB, []));
  AssertEquals('Enter left to the form', VK_RETURN, FRich.KeyResult(VK_RETURN, []));
  AssertEquals('Shift+Enter left to the form', VK_RETURN, FRich.KeyResult(VK_RETURN, [ssShift]));
  Check('keys');
  FRich.SelStart := 1;
  FRich.SelLength := 2;
  ResetEvents;
  AssertEquals('Ctrl+X taken', 0, FRich.KeyResult(VK_X, [ssCtrl]));
  AssertEquals('Shift+Delete taken', 0, FRich.KeyResult(VK_DELETE, [ssShift]));
  AssertEquals('nothing cut to the clipboard', 0, FRich.ClipWrites);
  AssertEquals('Ctrl+Z taken', 0, FRich.KeyResult(VK_Z, [ssCtrl]));
  AssertEquals('Ctrl+Y taken', 0, FRich.KeyResult(VK_Y, [ssCtrl]));
  AssertEquals('Ctrl+Shift+Z taken', 0, FRich.KeyResult(VK_Z, [ssCtrl, ssShift]));
  Check('cut, undo, redo keys');
  acts := FRich as ITyTextEditActions;
  AssertTrue('the menu: read-only', acts.TeIsReadOnly);
  AssertFalse('the menu: no undo', acts.TeCanUndo);
  AssertFalse('the menu: no redo', acts.TeCanRedo);
  acts.TeCut;
  acts.TeUndo;
  acts.TeRedo;
  acts.TePaste;
  Check('the menu');
  AssertEquals('the selection stays', Int64(2), FRich.SelLength);
  AssertEquals('Ctrl+C copies', 0, FRich.KeyResult(VK_C, [ssCtrl]));
  AssertEquals('copied', 1, FRich.ClipWrites);
  // code is not stopped
  FRich.SelText := 'Q';
  AssertEquals('SelText from code', 'xQc', FRich.Lines[0]);
  FRich.Undo;
  AssertEquals('Undo from code', 'xabc', FRich.Lines[0]);
end;

{ The design's hard line, by count: typing in the middle of a 2,000,000-line document lays out
  that paragraph alone, measures only its characters, enters a few tree nodes (log, not the
  document) and paints only its band. Mutation: every input empties the layout cache - red. }
procedure TTyRichEditEditTest.TestTypingInALargeDocumentTouchesOneParagraph;
var
  t: TTyRichText;
  p: Integer;
  visits, n, m, nb: Int64;
begin
  LoadBytes(BigText);
  t := FRich.Document.Text;
  AssertEquals('all the lines', BigLines, t.ParaCount);
  FRich.UpdateView;
  FRich.ScrollY := t.TotalHeight div 2;
  FRich.UpdateView;
  p := FRich.TopParagraph + 3;
  FRich.SelStart := t.ParaStart(p) + 2;
  PaintAll;
  FRich.ResetCounts;
  visits := t.NodeVisits;
  Chars('x');
  AssertEquals('typed', 'Lixne ' + IntToStr(p + 1), FRich.Lines[p]);
  AssertEquals(Format('one paragraph laid out (%d)', [FRich.LaidParas]), 1, FRich.LaidParas);
  AssertEquals('that one', p, FRich.LaidMin);
  n := t.NodeVisits - visits;
  AssertTrue(Format('%d tree nodes entered', [n]), n <= 400);
  AssertTrue(Format('%d characters measured', [FRich.Device.MeasuredChars]),
    FRich.Device.MeasuredChars <= 10 * (t.ParaLength(p) + 1));
  PaintAll;
  AssertTrue(Format('%d blocks painted', [FRich.BlockPaints]), FRich.BlockPaints <= 3);
  AssertEquals('no frame', 0, FRich.FramePaints);
  // Backspace and Enter alike
  m := FRich.Device.MeasuredChars;
  FRich.ResetCounts;
  visits := t.NodeVisits;
  Press(VK_BACK);
  nb := t.NodeVisits - visits;
  AssertEquals('Backspace: one paragraph laid out', 1, FRich.LaidParas);
  AssertTrue(Format('Backspace: %d nodes', [nb]), nb <= 400);
  FRich.ResetCounts;
  visits := t.NodeVisits;
  Press(VK_RETURN);
  AssertEquals('Enter: one more paragraph', BigLines + 1, t.ParaCount);
  AssertTrue(Format('Enter: its two parts laid out (%d)', [FRich.LaidParas]), FRich.LaidParas <= 3);
  AssertTrue(Format('Enter: %d nodes', [t.NodeVisits - visits]), t.NodeVisits - visits <= 800);
  PaintAll;
  AssertTrue(Format('Enter: %d blocks painted', [FRich.BlockPaints]), FRich.BlockPaints <= 4);
  WriteLn(Format('TTyRichEditEditTest: a key in the middle of %d lines: %d tree nodes, %d ' +
    'characters measured; Backspace %d nodes; Enter %d nodes, %d blocks painted', [BigLines, n,
    m, nb, t.NodeVisits - visits, FRich.BlockPaints]));
end;

{ ---- one test per rule ---- }

{ The run of typing ends where the memo's ends: a caret moved by the user (arrows), Enter,
  the focus leaving, another command; a space does not end it. }
procedure TTyRichEditEditTest.TestTheRunOfTypingEndsWhereTheMemoEndsIt;
var
  d: TTyRichDocument;
  f: TTyCharFormat;
begin
  SetText('abc');
  d := FRich.Document;
  FRich.SelStart := 3;
  Chars('de');
  AssertEquals('one step', 1, d.UndoDepth);
  Chars(' f');
  AssertEquals('a space does not end it', 1, d.UndoDepth);
  Press(VK_LEFT);
  Press(VK_RIGHT);
  Chars('g');
  AssertEquals('the caret moved by the user: a new step', 2, d.UndoDepth);
  Chars('h');
  AssertEquals('which goes on', 2, d.UndoDepth);
  Press(VK_RETURN);
  AssertEquals('Enter: a step of its own', 3, d.UndoDepth);
  Chars('i');
  AssertEquals('typing after Enter: a new step', 4, d.UndoDepth);
  FRich.Leave;
  Chars('j');
  AssertEquals('the focus left: a new step', 5, d.UndoDepth);
  f := TyDefaultCharFormat;
  f.Color := clRed;
  d.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 1), [cffColor], f));
  Chars('k');
  AssertEquals('another command between: a new step', 7, d.UndoDepth);
  FRich.SelStart := 0;
  FRich.SelStart := d.Text.Length;
  Chars('l');
  AssertEquals('the caret set by code: a new step', 8, d.UndoDepth);
end;

{ Typing over a selection: the delete and the insert are one undo step, the caret behind the
  character; the typing after it is a step of its own (as the memo's); an undo of the
  replacement selects what it put back. }
procedure TTyRichEditEditTest.TestTypingOverASelectionIsOneStep;
var
  d: TTyRichDocument;
begin
  SetText('abcd');
  d := FRich.Document;
  FRich.SelStart := 1;
  FRich.SelLength := 2;
  Chars('X');
  AssertEquals('replaced', 'aXd', FRich.Lines[0]);
  AssertEquals('one step', 1, d.UndoDepth);
  AssertEquals('the caret behind it', Int64(2), FRich.CaretPos);
  AssertFalse('nothing selected', FRich.HasSelection);
  Chars('Y');
  AssertEquals('typed on', 'aXYd', FRich.Lines[0]);
  AssertEquals('the typing after it: a step of its own', 2, d.UndoDepth);
  FRich.Undo;
  AssertEquals('the typing undone', 'aXd', FRich.Lines[0]);
  FRich.Undo;
  AssertEquals('the replacement undone', 'abcd', FRich.Lines[0]);
  AssertEquals('what came back selected: from', Int64(1), FRich.SelStart);
  AssertEquals('what came back selected: its length', Int64(2), FRich.SelLength);
end;

{ The typed text's format: the character's before the caret, at a paragraph's start the one's
  after it; typed over a selection, the first selected character's; and the seam a pending
  format will use (TypingFormat). }
procedure TTyRichEditEditTest.TestTypingTakesTheFormatAtTheCaret;
var
  d: TTyRichDocument;
  f: TTyCharFormat;
begin
  LoadRtf('{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}' +
    BS + 'pard' + BS + 'f0' + BS + 'b bold' + BS + 'b0  plain' + BS + 'par}');
  d := FRich.Document;
  AssertEquals('the text', 'bold plain', FRich.Lines[0]);
  FRich.SelStart := 4;
  Chars('Z');
  AssertTrue('after bold: bold', fsBold in CharFormatAt(4).Style);
  FRich.SelStart := d.Text.ParaLength(0);
  Chars('Q');
  AssertFalse('after plain: plain', fsBold in CharFormatAt(d.Text.ParaLength(0) - 1).Style);
  FRich.SelStart := 0;
  Chars('S');
  AssertTrue('at the start: the character after', fsBold in CharFormatAt(0).Style);
  // over a selection that starts on plain text: plain
  FRich.SelStart := 6;
  FRich.SelLength := 3;
  Chars('W');
  AssertFalse('over a plain start: plain', fsBold in CharFormatAt(6).Style);
  // the seam
  f := TyDefaultCharFormat;
  f.Color := clRed;
  FRich.ForcedFormat := d.Formats.InternChar(f);
  FRich.SelStart := 2;
  Chars('R');
  AssertEquals('the seam''s format', clRed, CharFormatAt(2).Color);
end;

{ Backspace and Delete take one caret place: a cluster (Delete: the letter and its accent),
  an object, a text file's escaped byte (its two characters), a separator (the paragraphs
  join); Backspace takes only the accent of a letter with one (as Windows' edit controls), and
  an emoji with its variation selector whole. }
procedure TTyRichEditEditTest.TestBackspaceAndDeleteTakeOneCaretPlace;
var
  d: TTyRichDocument;
  st: TBytesStream;
begin
  // a letter and its combining accent
  SetText('e' + U($301) + 'x');
  FRich.SelStart := 2;
  Press(VK_BACK);
  AssertEquals('Backspace: the accent only', 'ex', FRich.Lines[0]);
  AssertEquals('the caret after the letter', Int64(1), FRich.CaretPos);
  SetText('e' + U($301) + 'x');
  FRich.SelStart := 0;
  Press(VK_DELETE);
  AssertEquals('Delete: the letter and its accent', 'x', FRich.Lines[0]);
  // an emoji that is one picture
  SetText(U($2764) + U($FE0F) + 'x');
  FRich.SelStart := 2;
  Press(VK_BACK);
  AssertEquals('Backspace: the emoji whole', 'x', FRich.Lines[0]);
  // an object
  SetText('ab');
  d := FRich.Document;
  d.Execute(TTyRichInsertObject.Create(1, TTyRichOpaque.Create('{' + BS + '*' + BS + 'x}')));
  AssertEquals('an object in', Int64(3), d.Text.Length);
  FRich.SelStart := 2;
  Press(VK_BACK);
  AssertEquals('Backspace: the object', 'ab', FRich.Lines[0]);
  FRich.Undo;
  FRich.SelStart := 1;
  Press(VK_DELETE);
  AssertEquals('Delete: the object', 'ab', FRich.Lines[0]);
  { escaped bytes: UTF-16 with a lone surrogate, whose two bytes are no text - each kept as
    an escape of two characters }
  st := TBytesStream.Create(RawBytes(AnsiChar($FF) + AnsiChar($FE) + 'a' + #0#0 + AnsiChar($D8) +
    'b' + #0));
  try
    FRich.LoadFromStream(st, rfText);
  finally
    st.Free;
  end;
  d := FRich.Document;
  AssertEquals('two escaped bytes, two characters each', Int64(6), d.Text.Length);
  FRich.UpdateView;
  FRich.SelStart := 3;
  Press(VK_BACK);
  AssertEquals('Backspace: both characters of one', Int64(4), d.Text.Length);
  AssertEquals('Backspace: the caret', Int64(1), FRich.CaretPos);
  FRich.Undo;
  FRich.SelStart := 3;
  Press(VK_DELETE);
  AssertEquals('Delete: both characters of the other', Int64(4), d.Text.Length);
  AssertEquals('Delete: the caret stays', Int64(3), FRich.CaretPos);
  // a separator
  SetText('ab' + LineEnding + 'cd');
  d := FRich.Document;
  FRich.SelStart := d.Text.ParaStart(1);
  Press(VK_BACK);
  AssertEquals('Backspace at a start: joined', 'abcd', FRich.Lines[0]);
  AssertEquals('one paragraph', 1, d.Text.ParaCount);
  AssertEquals('the caret at the join', Int64(2), FRich.CaretPos);
  FRich.Undo;
  FRich.SelStart := 2;
  Press(VK_DELETE);
  AssertEquals('Delete at an end: joined', 'abcd', FRich.Lines[0]);
  AssertEquals('the caret at the join', Int64(2), FRich.CaretPos);
end;

{ At the document's ends Backspace and Delete (Ctrl too) do nothing: no change, nothing on the
  history - and they are taken. }
procedure TTyRichEditEditTest.TestTheEndsOfTheDocumentDoNothing;
var
  d: TTyRichDocument;
begin
  SetText('ab');
  d := FRich.Document;
  FRich.SelStart := 0;
  ResetEvents;
  AssertEquals('Backspace taken', 0, FRich.KeyResult(VK_BACK, []));
  AssertEquals('Ctrl+Backspace taken', 0, FRich.KeyResult(VK_BACK, [ssCtrl]));
  FRich.SelStart := 2;
  ResetEvents;
  AssertEquals('Delete taken', 0, FRich.KeyResult(VK_DELETE, []));
  AssertEquals('Ctrl+Delete taken', 0, FRich.KeyResult(VK_DELETE, [ssCtrl]));
  AssertEquals('the text', 'ab', FRich.Lines[0]);
  AssertEquals('nothing on the history', 0, d.UndoDepth);
  AssertEquals('no change', 0, FChanges);
  AssertEquals('nothing refused', 0, FRich.Refused);
  SetText('');
  Press(VK_BACK);
  Press(VK_DELETE);
  AssertEquals('empty: nothing', 0, FRich.Document.UndoDepth);
  AssertEquals('empty: no change', 0, FChanges);
end;

{ Ctrl+Backspace and Ctrl+Delete take a word by the rule the word steps go by (the memo's: a
  word and the space after it); at a paragraph's start / end the separator, as the memo. }
procedure TTyRichEditEditTest.TestCtrlBackspaceAndCtrlDeleteGoByWord;
var
  d: TTyRichDocument;
begin
  SetText('one two three');
  FRich.SelStart := 13;
  Press(VK_BACK, [ssCtrl]);
  AssertEquals('a word back', 'one two ', FRich.Lines[0]);
  AssertEquals('the caret', Int64(8), FRich.CaretPos);
  Press(VK_BACK, [ssCtrl]);
  AssertEquals('and the space before it with the next', 'one ', FRich.Lines[0]);
  SetText('one two three');
  FRich.SelStart := 0;
  Press(VK_DELETE, [ssCtrl]);
  AssertEquals('a word forward, with its space', 'two three', FRich.Lines[0]);
  AssertEquals('the caret stays', Int64(0), FRich.CaretPos);
  SetText('ab' + LineEnding + 'cd');
  d := FRich.Document;
  FRich.SelStart := d.Text.ParaStart(1);
  Press(VK_BACK, [ssCtrl]);
  AssertEquals('at a start: the separator only', 'abcd', FRich.Lines[0]);
  SetText('ab' + LineEnding + 'cd');
  FRich.SelStart := 2;
  Press(VK_DELETE, [ssCtrl]);
  AssertEquals('at an end: the separator only', 'abcd', FRich.Lines[0]);
end;

{ Shift+Enter puts a line break (U+000B) into the paragraph - no paragraph is added - as a step
  of its own that typing after it does not join. }
procedure TTyRichEditEditTest.TestShiftEnterInsertsALineBreak;
var
  d: TTyRichDocument;
begin
  LoadRtf('{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}' +
    BS + 'pard' + BS + 'f0 ab' + BS + 'par}');
  d := FRich.Document;
  FRich.SelStart := 1;
  AssertEquals('taken', 0, FRich.KeyResult(VK_RETURN, [ssShift]));
  AssertEquals('one paragraph', 1, d.Text.ParaCount);
  AssertEquals('a line break in it', 'a' + #11 + 'b', FRich.Lines[0]);
  AssertEquals('the caret behind it', Int64(2), FRich.CaretPos);
  Chars('c');
  AssertEquals('typing after it: its own step', 2, d.UndoDepth);
  AssertEquals('Ctrl+Enter is the form''s', VK_RETURN, FRich.KeyResult(VK_RETURN, [ssCtrl]));
  AssertEquals('Alt+Enter is the form''s', VK_RETURN, FRich.KeyResult(VK_RETURN, [ssAlt]));
end;

{ WantTabs False (the memo's default): Tab goes to the form and nothing is typed. True: Tab
  (Shift+Tab too, as the memo) types a tab, which merges with the typing around it. }
procedure TTyRichEditEditTest.TestWantTabsBothWays;
var
  d: TTyRichDocument;
begin
  SetText('ab');
  d := FRich.Document;
  FRich.SelStart := 1;
  AssertFalse('default False', FRich.WantTabs);
  AssertEquals('Tab goes on', VK_TAB, FRich.KeyResult(VK_TAB, []));
  AssertEquals('nothing typed', 'ab', FRich.Lines[0]);
  FRich.WantTabs := True;
  AssertEquals('Tab taken', 0, FRich.KeyResult(VK_TAB, []));
  AssertEquals('a tab typed', 'a' + #9 + 'b', FRich.Lines[0]);
  AssertEquals('the caret behind it', Int64(2), FRich.CaretPos);
  Chars('c');
  AssertEquals('Shift+Tab taken', 0, FRich.KeyResult(VK_TAB, [ssShift]));
  AssertEquals('typed on', 'a' + #9 + 'c' + #9 + 'b', FRich.Lines[0]);
  AssertEquals('one run of typing', 1, d.UndoDepth);
end;

{ Undo and redo place the caret: an undone insertion at its place, an undone deletion with the
  text it put back selected, a redo at the end of what it changed; scrolled into view, no
  affinity; Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z do the same. }
procedure TTyRichEditEditTest.TestUndoAndRedoPlaceTheCaret;
var
  d: TTyRichDocument;
  r, a: TRect;
  p: Integer;
begin
  SetText('hello world');
  d := FRich.Document;
  FRich.SelStart := 5;
  Chars('XY');
  FRich.SelStart := 0;
  FRich.Undo;
  AssertEquals('undone', 'hello world', FRich.Lines[0]);
  AssertEquals('the caret where it went in', Int64(5), FRich.CaretPos);
  AssertFalse('nothing selected', FRich.HasSelection);
  FRich.Redo;
  AssertEquals('redone', 'helloXY world', FRich.Lines[0]);
  AssertEquals('the caret behind it', Int64(7), FRich.CaretPos);
  SetText('hello world');
  FRich.SelStart := 6;
  FRich.SelLength := 5;
  Press(VK_DELETE);
  AssertEquals('deleted', 'hello ', FRich.Lines[0]);
  AssertEquals('the caret at the join', Int64(6), FRich.CaretPos);
  FRich.SelStart := 0;
  AssertEquals('Ctrl+Z taken', 0, FRich.KeyResult(VK_Z, [ssCtrl]));
  AssertEquals('undone', 'hello world', FRich.Lines[0]);
  AssertEquals('put back and selected: from', Int64(6), FRich.SelStart);
  AssertEquals('put back and selected: all of it', Int64(5), FRich.SelLength);
  AssertEquals('the caret at its end', Int64(11), FRich.CaretPos);
  AssertEquals('Ctrl+Y taken', 0, FRich.KeyResult(VK_Y, [ssCtrl]));
  AssertEquals('redone', 'hello ', FRich.Lines[0]);
  AssertEquals('at the join', Int64(6), FRich.CaretPos);
  AssertFalse('nothing selected', FRich.HasSelection);
  AssertEquals('Ctrl+Z again', 0, FRich.KeyResult(VK_Z, [ssCtrl]));
  AssertEquals('Ctrl+Shift+Z taken', 0, FRich.KeyResult(VK_Z, [ssCtrl, ssShift]));
  AssertEquals('redone by it', 'hello ', FRich.Lines[0]);
  // scrolled into view
  SetLinesOf(200);
  d := FRich.Document;
  p := 150;
  FRich.SelStart := d.Text.ParaStart(p) + 2;
  Chars('Z');
  FRich.ScrollY := 0;
  FRich.UpdateView;
  r := FRich.ParagraphRect(p);
  AssertTrue('scrolled away', (r.Bottom <= r.Top) or (r.Top >= FRich.Area.Bottom));
  FRich.Undo;
  r := FRich.ParagraphRect(p);
  a := FRich.Area;
  AssertTrue('the undone place in view', (r.Bottom > r.Top) and (r.Top >= a.Top) and
    (r.Bottom <= a.Bottom));
  AssertFalse('no affinity', FRich.CaretAtLineEnd);
end;

{ Cut (Ctrl+X, Shift+Delete, the menu) copies both flavours and deletes: one undo step, the
  caret at the join; nothing selected, nothing happens - the clipboard keeps what it had. }
procedure TTyRichEditEditTest.TestCutIsOneStepAndPutsBothFlavours;
var
  d: TTyRichDocument;
begin
  SetText('cut this text');
  d := FRich.Document;
  FRich.SelStart := 4;
  FRich.SelLength := 4;
  AssertEquals('Ctrl+X taken', 0, FRich.KeyResult(VK_X, [ssCtrl]));
  AssertEquals('gone', 'cut  text', FRich.Lines[0]);
  AssertEquals('the text flavour', 'this', FRich.ClipText);
  AssertEquals('the RTF flavour', 1, Pos('{' + BS + 'rtf1', FRich.ClipRtf));
  AssertEquals('one write', 1, FRich.ClipWrites);
  AssertEquals('one step', 1, d.UndoDepth);
  AssertEquals('the caret at the join', Int64(4), FRich.CaretPos);
  FRich.Undo;
  AssertEquals('undone', 'cut this text', FRich.Lines[0]);
  FRich.SelStart := 0;
  AssertEquals('nothing selected: taken', 0, FRich.KeyResult(VK_X, [ssCtrl]));
  AssertEquals('nothing selected: nothing copied', 1, FRich.ClipWrites);
  AssertEquals('nothing selected: nothing changed', 'cut this text', FRich.Lines[0]);
  FRich.SelStart := 9;
  FRich.SelLength := 4;
  AssertEquals('Shift+Delete taken', 0, FRich.KeyResult(VK_DELETE, [ssShift]));
  AssertEquals('Shift+Delete cuts', 'text', FRich.ClipText);
  AssertEquals('gone', 'cut this ', FRich.Lines[0]);
  FRich.SelStart := 0;
  FRich.SelLength := 3;
  (FRich as ITyTextEditActions).TeCut;
  AssertEquals('the menu cuts', 'cut', FRich.ClipText);
  AssertEquals('gone', ' this ', FRich.Lines[0]);
  AssertEquals('a step each (the first undone)', 2, d.UndoDepth);
end;

{ One OnChange and one OnSelectionChange per key that edits and moves the caret; a key that
  changes a format only (Enter leaving a list) moves nothing and reports no move. }
procedure TTyRichEditEditTest.TestOneChangeAndOneSelectionChangePerKey;
var
  d: TTyRichDocument;
  pf: TTyParaFormat;

  procedure Check(const AWhat: string; AChanges, ASelChanges: Integer);
  begin
    AssertEquals(AWhat + ': OnChange', AChanges, FChanges);
    AssertEquals(AWhat + ': OnSelectionChange', ASelChanges, FSelChanges);
    ResetEvents;
  end;

begin
  SetText('abcdef');
  d := FRich.Document;
  FRich.WantTabs := True;
  FRich.SelStart := 3;
  ResetEvents;
  Chars('x');
  Check('a character', 1, 1);
  Press(VK_BACK);
  Check('Backspace', 1, 1);
  Press(VK_DELETE);
  Check('Delete (the caret stays: no move)', 1, 0);
  Press(VK_RETURN);
  Check('Enter', 1, 1);
  Press(VK_RETURN, [ssShift]);
  Check('Shift+Enter', 1, 1);
  Press(VK_TAB);
  Check('Tab', 1, 1);
  FRich.SelStart := 0;
  FRich.SelLength := 2;
  ResetEvents;
  Chars('y');
  Check('a character over a selection', 1, 1);
  FRich.SelStart := 0;
  FRich.SelLength := 1;
  ResetEvents;
  Press(VK_X, [ssCtrl]);
  Check('Ctrl+X', 1, 1);
  Press(VK_Z, [ssCtrl]);
  Check('Ctrl+Z', 1, 1);
  Press(VK_Y, [ssCtrl]);
  Check('Ctrl+Y', 1, 1);
  // a list item left: a format only
  pf := TyDefaultParaFormat;
  pf.List.Kind := lkBullet;
  SetText('');
  d := FRich.Document;
  d.Execute(TTyRichSetParaFormat.Create(0, 0, [pffList], pf));
  ResetEvents;
  Press(VK_RETURN);
  Check('Enter on an empty item', 1, 0);
end;

procedure TTyRichEditEditTest.TypeWhileSaving(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
var
  before: Integer;
begin
  Inc(FSaveCalls);
  if FSaveCalls > 1 then Exit;
  before := FRich.Refused;
  try
    Chars('x');
    Press(VK_BACK);
    Press(VK_RETURN);
    Press(VK_Z, [ssCtrl]);
  except
    Inc(FSaveRaised);
  end;
  FSaveRefused := FRich.Refused - before;
end;

procedure TTyRichEditEditTest.CountSave(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FSaveCalls);
  ACancel := (FSaveCancelAt > 0) and (FSaveCalls >= FSaveCancelAt);
end;

{ Every refusal of the engine through a key: while the document loads, after a cancelled
  load, while it is being saved, in a row that holds a nested table. Nothing raised, nothing
  changed, EditRefused once per key with the reason; from code the same edit raises. }
procedure TTyRichEditEditTest.TestEveryRefusalThroughAKey;
var
  d: TTyRichDocument;
  len: Int64;
  first: string;
  k, n: Integer;
  c: TTyRichCell;
  raised: Boolean;
  st: TMemoryStream;
  sl: TStringList;

  procedure Keys(const AWhat, AReason: string);
  begin
    len := d.Text.Length;
    first := FRich.Lines[0];
    FRich.SelStart := 1;
    ResetEvents;
    Chars('x');
    AssertEquals(AWhat + ': a character refused once', 1, FRich.Refused);
    AssertEquals(AWhat + ': why', AReason, FRich.LastReason);
    AssertEquals(AWhat + ': the caret stays', Int64(1), FRich.CaretPos);
    Press(VK_BACK);
    Press(VK_DELETE);
    Press(VK_RETURN);
    Press(VK_RETURN, [ssShift]);
    FRich.SelStart := 0;
    FRich.SelLength := 2;
    FRich.Refused := 0;
    Press(VK_X, [ssCtrl]);
    AssertEquals(AWhat + ': a cut refused once', 1, FRich.Refused);
    AssertEquals(AWhat + ': the selection stays', Int64(2), FRich.SelLength);
    AssertEquals(AWhat + ': nothing copied', 0, FRich.ClipWrites);
    AssertEquals(AWhat + ': nothing changed', len, d.Text.Length);
    AssertEquals(AWhat + ': the first line', first, FRich.Lines[0]);
    AssertEquals(AWhat + ': no change event', 0, FChanges);
    raised := False;
    try
      FRich.SelText := 'code';
    except
      on E: ETyRichEdit do raised := E.Message = AReason;
    end;
    AssertTrue(AWhat + ': from code it raises', raised);
  end;

begin
  // loading: the first slice in, the rest waiting for the background
  FRich.Slices(2048, 2048);
  LoadBytes(PlainRtf(3000));
  d := FRich.Document;
  AssertTrue('loading', FRich.Loading);
  FRich.UpdateView;
  Keys('loading', rsRichEditRefusedLoading);
  // a cancelled load
  FRich.CancelLoad;
  AssertTrue('incomplete', FRich.Incomplete);
  Keys('incomplete', rsRichEditRefusedIncomplete);
  // saving: the keys come from the save's progress handler
  sl := TStringList.Create;
  try
    for k := 0 to 39999 do sl.Add('A line of text that the save writes out: ' + IntToStr(k));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  d := FRich.Document;
  FRich.UpdateView;
  FRich.SelStart := 5;
  Chars('u');
  len := d.Text.Length;
  FRich.OnSaveProgress := @TypeWhileSaving;
  FSaveCalls := 0;
  FSaveRaised := 0;
  st := TMemoryStream.Create;
  try
    FRich.SaveToStream(st, rfText);
  finally
    st.Free;
  end;
  FRich.OnSaveProgress := nil;
  AssertTrue('the text save reported its progress', FSaveCalls > 0);
  AssertEquals('saving: nothing raised', 0, FSaveRaised);
  AssertEquals('saving: four keys refused, once each', 4, FSaveRefused);
  AssertEquals('saving: why', rsRichEditRefusedSaving, FRich.LastReason);
  AssertEquals('saving: nothing changed', len, d.Text.Length);
  AssertEquals('saving: the undo kept', 1, d.UndoDepth);
  // a row that holds a nested table
  LoadBytes(FixtureFile('word-table-merged.rtf'));
  FRich.FinishLoading;
  FRich.UpdateView;
  d := FRich.Document;
  n := 0;
  for k := 0 to d.Text.ParaCount - 1 do
  begin
    c := d.CellAt(k);
    if (c = nil) or not c.Row.HoldsNestedTable or (d.Text.ParaLength(k) < 2) then Continue;
    Inc(n);
    len := d.Text.Length;
    first := FRich.Lines[k];
    FRich.SelStart := d.Text.ParaStart(k) + 1;
    ResetEvents;
    Chars('x');
    Press(VK_BACK);
    Press(VK_RETURN);
    // typed over a selection in it: refused before the deletion could run
    FRich.SelStart := d.Text.ParaStart(k);
    FRich.SelLength := 2;
    Chars('x');
    AssertEquals(Format('paragraph %d: four keys refused', [k]), 4, FRich.Refused);
    AssertEquals('why', rsRichEditRefusedFixedRow, FRich.LastReason);
    AssertEquals('nothing changed', len, d.Text.Length);
    AssertEquals('its text', first, FRich.Lines[k]);
    AssertEquals('no change event', 0, FChanges);
    AssertFalse('not modified', FRich.Modified);
  end;
  AssertTrue('a nested row was met', n > 0);
end;

{ An edit the engine itself refuses half way (here: a format the document does not have, given
  through the typing format's seam) is reverted by the engine and told: EditRefused once with
  the engine's message, the text, the history, Modified, the caret and the selection as they
  were, no OnChange. From code the same raises ETyRichModel. }
procedure TTyRichEditEditTest.TestARefusalOfTheEngineIsToldAndUndone;
var
  d: TTyRichDocument;
  raised: Boolean;
begin
  SetText('abcdef');
  d := FRich.Document;
  FRich.Modified := False;
  FRich.ForcedFormat := 999999;
  FRich.SelStart := 2;
  ResetEvents;
  Chars('x');
  AssertEquals('at the caret: refused once', 1, FRich.Refused);
  // E-M3: the control's own reason, never the engine's sentence
  AssertEquals('this range cannot be edited', rsRichEditRefusedRange, FRich.LastReason);
  AssertEquals('the caret stays', Int64(2), FRich.CaretPos);
  FRich.SelStart := 1;
  FRich.SelLength := 2;
  ResetEvents;
  Chars('y');
  AssertEquals('over a selection: refused once', 1, FRich.Refused);
  AssertEquals('the deletion that ran was reverted', 'abcdef', FRich.Lines[0]);
  AssertEquals('nothing on the history', 0, d.UndoDepth);
  AssertFalse('not modified', FRich.Modified);
  AssertEquals('the selection stays: from', Int64(1), FRich.SelStart);
  AssertEquals('the selection stays: its length', Int64(2), FRich.SelLength);
  AssertEquals('no change event', 0, FChanges);
  raised := False;
  try
    FRich.SelText := 'z';
  except
    on ETyRichModel do raised := True;
  end;
  AssertTrue('from code it raises', raised);
  FRich.ForcedFormat := -1;
end;

{ Select All and a key over a million paragraphs: one command (one undo step, one change), the
  view laid out once - and the walk is the engine's delete: what the key costs beyond a bare
  delete and insert of the same range is bounded, whatever the document's size. }
procedure TTyRichEditEditTest.TestASelectionOfAMillionParagraphsTypedOverIsOneCommand;
var
  t: TTyRichText;
  bare: TTyRichDocument;
  comp: TTyRichCompositeCommand;
  len, visits, ours, theirs: Int64;
begin
  // what the engine's own delete and insert cost on the same text
  bare := TTyRichDocument.CreateFromUtf8(MillionText);
  try
    len := bare.Text.Length;
    visits := bare.Text.NodeVisits;
    comp := TTyRichCompositeCommand.Create;
    comp.Add(TTyRichDelete.Create(0, len));
    comp.Add(TTyRichInsertText.Create(0, 'x', bare.TypingFormatAt(1), False));
    bare.Execute(comp);
    theirs := bare.Text.NodeVisits - visits;
  finally
    bare.Free;
  end;
  LoadBytes(MillionText);
  t := FRich.Document.Text;
  AssertEquals('a million paragraphs', MillionLines, t.ParaCount);
  FRich.UpdateView;
  FRich.SelectAll;
  ResetEvents;
  FRich.ResetCounts;
  visits := t.NodeVisits;
  Chars('x');
  ours := t.NodeVisits - visits;
  AssertEquals('replaced', 'x', FRich.Lines[0]);
  AssertEquals('one paragraph', 1, t.ParaCount);
  AssertEquals('one undo step', 1, FRich.Document.UndoDepth);
  AssertEquals('one change', 1, FChanges);
  AssertTrue(Format('a screen laid out (%d)', [FRich.LaidParas]), FRich.LaidParas <= 3);
  AssertTrue(Format('the key entered %d tree nodes, the engine''s delete and insert alone %d',
    [ours, theirs]), ours <= theirs + 500);
  WriteLn(Format('TTyRichEditEditTest: Select All of %d paragraphs and a key: %d tree nodes ' +
    '(the engine''s delete and insert alone: %d)', [MillionLines, ours, theirs]));
  FRich.Undo;
  AssertEquals('undone', MillionLines, t.ParaCount);
  AssertEquals('all of it selected again', len, FRich.SelLength);
end;

procedure TTyRichEditEditTest.KeystrokeCase(AScale: Integer);
var
  t: TTyRichText;
  p, i: Integer;
  h0: Integer;
  r: TRect;
  what: string;
begin
  what := Format('scale %d', [AScale]);
  FreeAndNil(FRich);
  if AScale > 1 then TyForceDeviceScaleForTest(AScale, True, False)
  else TyForceDeviceScaleForTest(0, False);
  FPaintScale := AScale;
  FRich := NewProbe;
  SetLinesOf(60);
  t := FRich.Document.Text;
  PaintAll;
  AssertEquals(what + ': the device scale', AScale, FRich.Scale);
  p := 5;
  FRich.SelStart := t.ParaStart(p) + t.ParaLength(p);
  PaintAll;
  FRich.ResetCounts;
  Chars('x');
  PaintAll;
  AssertTrue(Format('%s: a keystroke painted %d blocks', [what, FRich.BlockPaints]),
    FRich.BlockPaints <= 3);
  AssertEquals(what + ': no frame', 0, FRich.FramePaints);
  CheckSurface(what + ': a keystroke');
  // the keystroke that makes the paragraph a line taller: the blocks below are moved, not drawn
  r := FRich.ParagraphRect(p);
  h0 := r.Bottom - r.Top;
  i := 0;
  repeat
    FRich.ResetCounts;
    Chars('w');
    PaintAll;
    r := FRich.ParagraphRect(p);
    Inc(i);
  until (r.Bottom - r.Top > h0) or (i > 400);
  AssertTrue(what + ': the paragraph wrapped', r.Bottom - r.Top > h0);
  AssertTrue(Format('%s: the taller paragraph painted %d blocks', [what, FRich.BlockPaints]),
    FRich.BlockPaints <= 3);
  CheckSurface(what + ': a line taller');
  // and back: the blocks below move up, the band at the bottom comes in
  FRich.ResetCounts;
  Press(VK_BACK);
  PaintAll;
  r := FRich.ParagraphRect(p);
  AssertEquals(what + ': one line again', h0, r.Bottom - r.Top);
  // two bands: the paragraph's and the one at the bottom, each with the blocks next to it
  AssertTrue(Format('%s: a line shorter painted %d blocks', [what, FRich.BlockPaints]),
    FRich.BlockPaints <= 8);
  CheckSurface(what + ': a line shorter');
end;

{ The paint after a keystroke draws its paragraph's band only (and the blocks next to it that
  reach into it); one that makes the paragraph taller or shorter moves the kept surface below
  it and draws the paragraph and what a move up exposes, never every block under it - at
  device scale 1 and 2; the surface equals a full redraw each time. }
procedure TTyRichEditEditTest.TestAKeystrokePaintsOnlyItsParagraph;
begin
  KeystrokeCase(1);
  KeystrokeCase(2);
end;

{ Tables: a key does not cross a cell's edge (Backspace at a cell's start and Delete at its
  end do nothing, as in Word and WordPad); a selection across cells is not deleted or typed
  over by a key (R57: refused and told, until Task 12) - the engine would leave a cell with no
  paragraph. }
procedure TTyRichEditEditTest.TestADeletionAcrossCellsLeavesAValidDocument;
var
  d: TTyRichDocument;
  t: TTyRichText;
  k0, k1, k: Integer;
  before: string;
begin
  LoadBytes(FixtureFile('re-zh-table.rtf'));
  FRich.FinishLoading;
  FRich.UpdateView;
  d := FRich.Document;
  t := d.Text;
  k0 := -1;
  for k := 0 to t.ParaCount - 2 do
    if (d.CellAt(k) <> nil) and (d.CellAt(k + 1) <> nil) and (d.CellAt(k) <> d.CellAt(k + 1)) and
      (t.ParaLength(k) > 1) and (t.ParaLength(k + 1) > 1) then
    begin
      k0 := k;
      Break;
    end;
  AssertTrue('two cells side by side', k0 >= 0);
  k1 := k0 + 1;
  before := FRich.Lines.Text;
  FRich.SelStart := t.ParaStart(k1);
  ResetEvents;
  AssertEquals('Backspace at a cell''s start: taken', 0, FRich.KeyResult(VK_BACK, []));
  FRich.SelStart := t.ParaStart(k0) + t.ParaLength(k0);
  AssertEquals('Delete at a cell''s end: taken', 0, FRich.KeyResult(VK_DELETE, []));
  AssertEquals('nothing changed', before, FRich.Lines.Text);
  AssertEquals('nothing on the history', 0, d.UndoDepth);
  AssertEquals('nothing refused', 0, FRich.Refused);
  // across the cells: refused (R57, until Task 12) - told, nothing changed
  FRich.SelStart := t.ParaStart(k0) + 1;
  FRich.SelLength := t.ParaStart(k1) + 1 - (t.ParaStart(k0) + 1);
  ResetEvents;
  Press(VK_DELETE);
  AssertEquals('Delete across cells: refused once', 1, FRich.Refused);
  AssertEquals('why', rsRichEditRefusedCells, FRich.LastReason);
  Chars('Q');
  AssertEquals('typed over: refused too', 2, FRich.Refused);
  FRich.ClipWrites := 0;
  Press(VK_X, [ssCtrl]);
  AssertEquals('cut: refused too, before copying', 3, FRich.Refused);
  AssertEquals('nothing copied', 0, FRich.ClipWrites);
  AssertEquals('nothing changed', before, FRich.Lines.Text);
  AssertEquals('nothing on the history', 0, d.UndoDepth);
  AssertEquals('no change event', 0, FChanges);
  AssertEquals('the selection stays', t.ParaStart(k1) + 1 - (t.ParaStart(k0) + 1), FRich.SelLength);
end;

{ An object is one character: typed over when it is selected, and back with the undo. }
procedure TTyRichEditEditTest.TestTypingOverASelectedObjectReplacesIt;
var
  d: TTyRichDocument;
begin
  SetText('ab');
  d := FRich.Document;
  d.Execute(TTyRichInsertObject.Create(1, TTyRichOpaque.Create('{' + BS + '*' + BS + 'x}')));
  d.ClearUndo;
  FRich.SelStart := 1;
  FRich.SelLength := 1;
  Chars('Q');
  AssertEquals('replaced', 'aQb', FRich.Lines[0]);
  AssertEquals('one step', 1, d.UndoDepth);
  FRich.Undo;
  AssertEquals('the object back', string(TyRichObjectChar), d.Text.GetText(1, 1));
end;

{ SelText := replaces the selection with text from code - line breaks make paragraphs - one
  undo step that typing does not join, the caret behind it; ReadOnly does not stop it. }
procedure TTyRichEditEditTest.TestSelTextReplacesTheSelection;
var
  d: TTyRichDocument;
begin
  SetText('abc');
  d := FRich.Document;
  FRich.SelStart := 1;
  FRich.SelLength := 1;
  FRich.SelText := 'X' + LineEnding + 'Y';
  AssertEquals('two paragraphs', 2, d.Text.ParaCount);
  AssertEquals('the first', 'aX', FRich.Lines[0]);
  AssertEquals('the second', 'Yc', FRich.Lines[1]);
  AssertEquals('the caret behind it', d.Text.ParaStart(1) + 1, FRich.CaretPos);
  AssertEquals('one step', 1, d.UndoDepth);
  Chars('z');
  AssertEquals('typing does not join it', 2, d.UndoDepth);
  FRich.ReadOnly := True;
  FRich.SelStart := 0;
  FRich.SelText := 'Q';
  AssertEquals('ReadOnly: code still edits', 'QaX', FRich.Lines[0]);
end;

{ Inside the document's update the view does not know the text: an editing key is taken and
  does nothing, a character is not typed. }
procedure TTyRichEditEditTest.TestKeysInsideAnUpdateDoNothing;
var
  d: TTyRichDocument;
begin
  SetText('abc');
  d := FRich.Document;
  FRich.SelStart := 2;
  d.BeginUpdate;
  try
    AssertEquals('Backspace taken', 0, FRich.KeyResult(VK_BACK, []));
    AssertEquals('Enter taken', 0, FRich.KeyResult(VK_RETURN, []));
    AssertEquals('Ctrl+Z taken', 0, FRich.KeyResult(VK_Z, [ssCtrl]));
    Chars('x');
  finally
    d.EndUpdate;
  end;
  AssertEquals('nothing changed', 'abc', FRich.Lines[0]);
  AssertEquals('nothing on the history', 0, d.UndoDepth);
end;

{ ---- the parked items ---- }

{ The control's Font.Style reaches the text with no style of its own (review H1, Minor 12):
  the layouter's base style, the fonts the text is measured in (bold, italic), and what is
  drawn (underline, strike-through). }
procedure TTyRichEditEditTest.TestTheControlsFontStyleReachesTheText;
var
  plain: TBGRABitmap;
  i, found: Integer;
  dev: TTyRichTestDevice;
  x, y, diff: Integer;
  a, b: PBGRAPixel;
begin
  SetText('styled text');
  PaintAll;
  plain := FRich.Surf.Duplicate as TBGRABitmap;
  try
    FRich.Font.Style := [fsBold, fsItalic, fsUnderline, fsStrikeOut];
    FRich.ResetCounts;
    FRich.UpdateView;
    AssertTrue('the base style',
      FRich.Layouter.BaseFontStyle = [fsBold, fsItalic, fsUnderline, fsStrikeOut]);
    AssertTrue('laid out again', FRich.LaidParas > 0);
    dev := FRich.Device;
    // the font the text with no style of its own is measured and drawn in
    found := TLayouterAccess(FRich.Layouter).FormatFont(FRich.Document.DefaultCharFormatId,
      FRich.VisibleBlocks[0].Layout.PPI, 1).Font;
    AssertTrue('measured bold and italic', dev.FontStyle(found) = [fsBold, fsItalic]);
    PaintAll;
    diff := 0;
    for y := 0 to plain.Height - 1 do
    begin
      a := plain.ScanLine[y];
      b := FRich.Surf.ScanLine[y];
      for x := 0 to plain.Width - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green) or (a^.blue <> b^.blue) then Inc(diff);
        Inc(a);
        Inc(b);
      end;
    end;
    AssertTrue('drawn otherwise', diff > 0);
    FRich.Font.Style := [];
    FRich.UpdateView;
    AssertTrue('no base style again', FRich.Layouter.BaseFontStyle = []);
  finally
    plain.Free;
  end;
end;

{ A document of the control's own (a new one, a text file) saved as RTF names its page and
  the control's font as \f0 (the Word check); a document read from RTF goes back as the file
  (byte fidelity untouched). }
procedure TTyRichEditEditTest.TestANewDocumentIsSavedWithItsFontAndPage;
var
  st: TMemoryStream;
  s: RawByteString;
  orig, outb: TBytes;
  name: string;
begin
  // the control's own font, set on it: what the text is shown in and the file must name
  FRich.Font.Name := 'Arial';
  SetText('a new document');
  name := FRich.Layouter.BaseFontName;
  AssertEquals('the control''s font is the base font', 'Arial', name);
  st := TMemoryStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    SetLength(s, st.Size);
    Move(st.Memory^, s[1], st.Size);
  finally
    st.Free;
  end;
  // A4 (R54)
  AssertTrue('the page: ' + s, Pos(BS + 'paperw11906' + BS + 'paperh16838' + BS + 'margl1800' +
    BS + 'margr1800' + BS + 'margt1440' + BS + 'margb1440', s) > 0);
  AssertTrue('the font as f0: ' + s, Pos('{' + BS + 'f0' + BS + 'fnil' + BS + 'fcharset0 ' +
      name + ';}', s) > 0);
  orig := FixtureFile('wp-zh-plain.rtf');
  LoadBytes(orig);
  FRich.FinishLoading;
  st := TMemoryStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    outb := nil;
    SetLength(outb, st.Size);
    Move(st.Memory^, outb[0], st.Size);
  finally
    st.Free;
  end;
  AssertTrue('a file read from RTF goes back as it was',
    (Length(outb) = Length(orig)) and CompareMem(@outb[0], @orig[0], Length(orig)));
end;

{ Saving a big text reports progress through OnSaveProgress (as loading does) and can be
  cancelled - and the file it was to replace stays as it was (the save goes to a temporary
  file first, which goes away). }
procedure TTyRichEditEditTest.TestATextSaveReportsProgressAndCanBeCancelled;
var
  sl: TStringList;
  k: Integer;
  path: string;
  f: TFileStream;
  raised: Boolean;
  sr: TSearchRec;
  files: Integer;
begin
  sl := TStringList.Create;
  try
    for k := 0 to 39999 do sl.Add('A line of text that the save writes out: ' + IntToStr(k));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  path := TempDir + 'saved.txt';
  FRich.OnSaveProgress := @CountSave;
  FSaveCalls := 0;
  FSaveCancelAt := 0;
  FRich.SaveToFile(path, rfText);
  AssertTrue(Format('progress reported %d times', [FSaveCalls]), FSaveCalls >= 3);
  // the file is there: a cancelled save over it leaves it
  f := TFileStream.Create(path, fmCreate);
  try
    f.WriteBuffer(PAnsiChar('old')^, 3);
  finally
    f.Free;
  end;
  FSaveCalls := 0;
  FSaveCancelAt := 2;
  raised := False;
  try
    FRich.SaveToFile(path, rfText);
  except
    on ETyRichTextSaveCancelled do raised := True;
  end;
  AssertTrue('cancelled', raised);
  AssertEquals('asked twice', 2, FSaveCalls);
  AssertEquals('the file as it was', 'old', StrOfBytes(FileBytes(path)));
  files := 0;
  if FindFirst(TempDir + '*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Attr and faDirectory) = 0 then Inc(files);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertEquals('no temporary file left', 1, files);
  FRich.OnSaveProgress := nil;
end;

{ ---- fix wave W11 ---- }

procedure TTyRichEditEditTest.ScaledProbe(AScale: Integer);
begin
  FreeAndNil(FRich);
  if AScale > 1 then TyForceDeviceScaleForTest(AScale, True, False)
  else TyForceDeviceScaleForTest(0, False);
  FPaintScale := AScale;
  FRich := NewProbe;
  ResetEvents;
end;

{ Lines of different lengths ('Line i' and up to twelve x): the test device draws every
  character as the same box, so a line left on the surface where another one belongs differs
  from it only when their lengths do (review C-10a, Important 1). ALong in place of line
  ALongAt. }
procedure TTyRichEditEditTest.SetVariedLines(ACount: Integer; const ALong: string;
  ALongAt: Integer);
var
  sl: TStringList;
  i: Integer;
begin
  sl := TStringList.Create;
  try
    for i := 0 to ACount - 1 do
      if i = ALongAt then sl.Add(ALong)
      else sl.Add('Line ' + IntToStr(i) + StringOfChar('x', (i * 5) mod 13));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichEditEditTest.EdgeCases(AScale: Integer);
var
  t: TTyRichText;
  p, i, h0: Integer;
  r, a: TRect;
  what, long: string;
begin
  what := Format('scale %d', [AScale]);
  // Backspace at the start of the line on the view's bottom (brought there by the least scroll)
  ScaledProbe(AScale);
  SetVariedLines(200);
  t := FRich.Document.Text;
  PaintAll;
  FRich.SelStart := t.ParaStart(60);
  PaintAll;
  r := FRich.ParagraphRect(60);
  AssertEquals(what + ': the bottom line ends at the view''s bottom', FRich.Area.Bottom, r.Bottom);
  AssertTrue(what + ': scrolled', FRich.ScrollY > 0);
  Press(VK_BACK);
  AssertEquals(what + ': joined', 199, t.ParaCount);
  CheckSurface(what + ': Backspace at the start of the bottom line');
  // the same not scrolled: Delete at the end of the line above the one the view's bottom cuts
  ScaledProbe(AScale);
  SetVariedLines(200);
  t := FRich.Document.Text;
  PaintAll;
  a := FRich.Area;
  p := 0;
  repeat
    Inc(p);
    r := FRich.ParagraphRect(p);
  until r.Bottom >= a.Bottom;
  FRich.SelStart := t.ParaStart(p - 1) + t.ParaLength(p - 1);
  PaintAll;
  AssertEquals(what + ': not scrolled', Int64(0), FRich.ScrollY);
  Press(VK_DELETE);
  CheckSurface(what + ': Delete that joins the line the view''s bottom cuts');
  // a wrapped paragraph on the view's bottom: growing a line, then losing it
  ScaledProbe(AScale);
  SetVariedLines(200, 'w', 60);
  t := FRich.Document.Text;
  r := FRich.ParagraphRect(5);
  h0 := r.Bottom - r.Top;
  FRich.SelStart := t.ParaStart(60) + 1;
  PaintAll;
  i := 0;
  repeat
    Chars('w');
    PaintAll;
    r := FRich.ParagraphRect(60);
    Inc(i);
  until (r.Bottom - r.Top > h0) or (i > 400);
  AssertTrue(what + ': it wrapped', r.Bottom - r.Top > h0);
  CheckSurface(what + ': a bottom paragraph a line taller');
  Press(VK_BACK);
  r := FRich.ParagraphRect(60);
  AssertEquals(what + ': one line again', h0, r.Bottom - r.Top);
  CheckSurface(what + ': a bottom paragraph a line shorter');
  // Enter on the bottom line (taller), and its Ctrl+Z (shorter)
  ScaledProbe(AScale);
  SetVariedLines(200);
  t := FRich.Document.Text;
  PaintAll;
  FRich.SelStart := t.ParaStart(60) + 2;
  PaintAll;
  Press(VK_RETURN);
  CheckSurface(what + ': Enter on the bottom line');
  Press(VK_Z, [ssCtrl]);
  AssertEquals(what + ': undone', 200, t.ParaCount);
  CheckSurface(what + ': Ctrl+Z of an Enter on the bottom line');
  // a selection that ends far below what the view holds, deleted
  ScaledProbe(AScale);
  SetVariedLines(400);
  t := FRich.Document.Text;
  PaintAll;
  FRich.SelStart := t.ParaStart(300) + 2;
  PaintAll;
  FRich.SelLength := t.ParaStart(5) + 2 - (t.ParaStart(300) + 2);
  PaintAll;
  FRich.ScrollY := FRich.ScrollY - 36;
  PaintAll;
  Press(VK_DELETE);
  AssertEquals(what + ': deleted to paragraph 300', 105, t.ParaCount);
  CheckSurface(what + ': Delete of a selection that ends below the held blocks');
  // a paragraph taller than the view: shorter by a selection deleted in it, taller by typing
  ScaledProbe(AScale);
  long := '';
  for i := 1 to 600 do long := long + 'word ';
  SetVariedLines(60, long, 10);
  t := FRich.Document.Text;
  FRich.SelStart := t.ParaStart(10) + 1500;
  PaintAll;
  r := FRich.ParagraphRect(10);
  AssertTrue(what + ': taller than the view', r.Bottom - r.Top > FRich.Area.Bottom - FRich.Area.Top);
  FRich.SelStart := t.ParaStart(10) + 1400;
  FRich.SelLength := 200;
  PaintAll;
  Press(VK_DELETE);
  CheckSurface(what + ': a paragraph taller than the view made shorter');
  for i := 1 to 70 do Chars('w');
  CheckSurface(what + ': a paragraph taller than the view made taller');
  // the document's last paragraph, the view at the end
  ScaledProbe(AScale);
  SetVariedLines(200);
  t := FRich.Document.Text;
  PaintAll;
  FRich.SelStart := t.ParaStart(199);
  PaintAll;
  Press(VK_BACK);
  CheckSurface(what + ': Backspace at the start of the last line');
  Press(VK_Z, [ssCtrl]);
  CheckSurface(what + ': and its undo');
  // the scroll range made shorter than the view's position: the view is pulled up
  ScaledProbe(AScale);
  SetVariedLines(200);
  t := FRich.Document.Text;
  PaintAll;
  FRich.SelStart := t.Length;
  PaintAll;
  FRich.SelStart := t.ParaStart(185);
  FRich.SelLength := t.Length - t.ParaStart(185);
  PaintAll;
  i := FRich.TopParagraph;
  Press(VK_DELETE);
  PaintAll;
  AssertTrue(Format('%s: pulled up (top paragraph %d, was %d)', [what, FRich.TopParagraph, i]),
    FRich.TopParagraph < i);
  CheckSurface(what + ': the end deleted, the view pulled up');
  Press(VK_Z, [ssCtrl]);
  CheckSurface(what + ': and its undo');
end;

{ E-I1: whatever an edit's surface move leaves without valid pixels is drawn - nothing below
  the changed blocks is taken for good unless it was moved from valid pixels or drawn again:
  the review's four cases (Backspace at the start of the bottom line; a wrapped bottom
  paragraph losing a line; Ctrl+Z of an Enter on the bottom line; Delete of a selection that
  ends beyond the held blocks), the growing direction at the bottom edge, a paragraph taller
  than the view, the last paragraph, the view pulled up - each the surface of a full redraw,
  at device scale 1 and 2, scrolled and not. }
procedure TTyRichEditEditTest.TestTheSurfaceAfterAnEditAtTheViewsBottomIsAFullRedraw;
begin
  EdgeCases(1);
  EdgeCases(2);
end;

{ E-I2 (R55 a, measured in msftedit): undo puts the caret and the selection back as they were
  before the action, redo leaves a plain caret where the action left it - an undone Backspace
  has the caret after the character, an undone Delete before it, undone typing (a merged run
  too) where it began, an undone deletion or typing over a selection the selection again; an
  edit made by code has no marks, and the change's extent decides. }
procedure TTyRichEditEditTest.TestUndoPutsTheSelectionBackAsItWas;
var
  d: TTyRichDocument;

  procedure CheckSel(const AWhat: string; AStart, ALength, ACaret: TTyRichPos);
  begin
    AssertEquals(AWhat + ': from', AStart, FRich.SelStart);
    AssertEquals(AWhat + ': length', ALength, FRich.SelLength);
    AssertEquals(AWhat + ': the caret', ACaret, FRich.CaretPos);
  end;

begin
  SetText('hello world');
  d := FRich.Document;
  // Backspace
  FRich.SelStart := 5;
  Press(VK_BACK);
  FRich.SelStart := 0;
  FRich.Undo;
  AssertEquals('Backspace undone', 'hello world', FRich.Lines[0]);
  CheckSel('Backspace undone: the caret after the character', 5, 0, 5);
  FRich.SelStart := 0;
  FRich.Redo;
  CheckSel('Backspace redone: a plain caret where it left it', 4, 0, 4);
  FRich.Undo;
  // Delete
  FRich.SelStart := 5;
  Press(VK_DELETE);
  FRich.SelStart := 0;
  FRich.Undo;
  CheckSel('Delete undone: the caret before the character', 5, 0, 5);
  FRich.Redo;
  CheckSel('Delete redone', 5, 0, 5);
  FRich.Undo;
  // a selection deleted
  FRich.SelStart := 6;
  FRich.SelLength := 5;
  Press(VK_BACK);
  AssertEquals('deleted', 'hello ', FRich.Lines[0]);
  FRich.SelStart := 0;
  FRich.Undo;
  CheckSel('a deleted selection undone: selected as it was', 6, 5, 11);
  FRich.Redo;
  CheckSel('redone: a plain caret', 6, 0, 6);
  FRich.Undo;
  // typed over
  FRich.SelStart := 0;
  FRich.SelLength := 5;
  Chars('Q');
  FRich.Undo;
  AssertEquals('typed over, undone', 'hello world', FRich.Lines[0]);
  CheckSel('typed over, undone: selected again', 0, 5, 5);
  FRich.Redo;
  CheckSel('typed over, redone: behind the character', 1, 0, 1);
  FRich.Undo;
  // a merged run of typing
  FRich.SelStart := 5;
  Chars('a');
  Chars('bc');
  AssertEquals('one run', 1, d.UndoDepth);
  FRich.SelStart := 0;
  FRich.Undo;
  CheckSel('a run of typing undone: where it began', 5, 0, 5);
  FRich.Redo;
  CheckSel('redone: behind its last character', 8, 0, 8);
  FRich.Undo;
  // the review's sequence: Enter, Backspace, Ctrl+Z, a character - two paragraphs
  SetText('hello world');
  d := FRich.Document;
  FRich.SelStart := 5;
  Press(VK_RETURN);
  AssertEquals('Enter', 2, d.Text.ParaCount);
  Press(VK_BACK);
  AssertEquals('Backspace joined them', 1, d.Text.ParaCount);
  Press(VK_Z, [ssCtrl]);
  AssertEquals('undone: two paragraphs', 2, d.Text.ParaCount);
  CheckSel('undone: the caret at the second''s start, nothing selected', d.Text.ParaStart(1), 0,
    d.Text.ParaStart(1));
  Chars('Q');
  AssertEquals('still two paragraphs', 2, d.Text.ParaCount);
  AssertEquals('the first', 'hello', FRich.Lines[0]);
  AssertEquals('the second', 'Q world', FRich.Lines[1]);
  // an edit from code: no marks - what it put back is selected, a redo at its end
  SetText('hello world');
  d := FRich.Document;
  FRich.SelStart := 0;
  AssertTrue('deleted by code', d.Execute(TTyRichDelete.Create(2, 3)));
  FRich.Undo;
  CheckSel('code''s deletion undone: what came back selected', 2, 3, 5);
  FRich.Redo;
  CheckSel('redone: at its end', 2, 0, 2);
  AssertTrue('inserted by code', d.Execute(TTyRichInsertText.Create(0, 'ab', TyRichInheritFormat,
    False)));
  FRich.Undo;
  CheckSel('code''s insertion undone: where it was', 0, 0, 0);
  { typing from code that merges into the user's run: the step begins where the user's run
    began; where it ends, the view never saw - a redo goes by the change's extent }
  SetText('hello');
  d := FRich.Document;
  FRich.SelStart := 5;
  Chars('ab');
  AssertTrue('code types on', d.Execute(TTyRichInsertText.Create(7, 'cd')));
  AssertEquals('merged into the run', 1, d.UndoDepth);
  FRich.SelStart := 0;
  FRich.Undo;
  CheckSel('the merged run undone: where the user''s typing began', 5, 0, 5);
  FRich.Redo;
  CheckSel('redone: at the end of all of it', 9, 0, 9);
end;

{ E-M1 (R56) through keys: typed by mistake, Ctrl+Z, saved - the file, byte for byte: a
  character, Enter, Backspace, a run of typing, in a Word file and a WordPad one. }
procedure TTyRichEditEditTest.TestATypingMistakeUndoneSavesTheFile;

  procedure Check(const AName: string);
  var
    orig: TBytes;
    d: TTyRichDocument;
    t: TTyRichText;
    k, p: Integer;
    ps: TTyRichPos;

    procedure Saved(const AWhat: string);
    var
      st: TMemoryStream;
      outb: TBytes;
    begin
      st := TMemoryStream.Create;
      try
        FRich.SaveToStream(st, rfRtf);
        outb := nil;
        SetLength(outb, st.Size);
        if st.Size > 0 then Move(st.Memory^, outb[0], st.Size);
      finally
        st.Free;
      end;
      AssertTrue(Format('%s: %s, Ctrl+Z, saved: the file', [AName, AWhat]),
        (Length(outb) = Length(orig)) and CompareMem(@outb[0], @orig[0], Length(orig)));
    end;

  begin
    orig := FixtureFile(AName);
    LoadBytes(orig);
    FRich.FinishLoading;
    FRich.UpdateView;
    d := FRich.Document;
    t := d.Text;
    p := -1;
    for k := 0 to t.ParaCount - 1 do
      if (t.ParaLength(k) >= 3) and (d.CellAt(k) = nil) then
      begin
        p := k;
        Break;
      end;
    AssertTrue(AName + ': a paragraph to type in', p >= 0);
    ps := t.ParaStart(p);
    FRich.SelStart := ps + 1;
    Chars('x');
    Press(VK_Z, [ssCtrl]);
    Saved('a character');
    FRich.SelStart := ps + 1;
    Press(VK_RETURN);
    Press(VK_Z, [ssCtrl]);
    Saved('Enter');
    FRich.SelStart := ps + 2;
    Press(VK_BACK);
    Press(VK_Z, [ssCtrl]);
    Saved('Backspace');
    FRich.SelStart := ps + 1;
    Chars('abc');
    Press(VK_Z, [ssCtrl]);
    Saved('a run of typing');
  end;

begin
  Check('word-list.rtf');
  Check('wp-zh-plain.rtf');
end;

{ E-M2: Lines[i] := S is never half done - a text the engine refuses (one that ends inside a
  UTF-8 sequence: an ANSI 'cafe' with its accent, assigned by mistake) raises, and the line,
  the history, Modified and OnChange are as they were; a good text replaces the line, one
  step. }
procedure TTyRichEditEditTest.TestALineThatCannotBeAssignedStaysAsItWas;
var
  d: TTyRichDocument;
  r: RawByteString;
  raised: Boolean;
begin
  SetText('one' + LineEnding + 'two' + LineEnding + 'three');
  d := FRich.Document;
  FRich.Modified := False;
  ResetEvents;
  r := 'caf' + #$E9;
  SetCodePage(r, CP_UTF8, False);
  raised := False;
  try
    FRich.Lines[1] := r;
  except
    on ETyRichModel do raised := True;
  end;
  AssertTrue('refused', raised);
  AssertEquals('the line as it was', 'two', FRich.Lines[1]);
  AssertEquals('no undo step', 0, d.UndoDepth);
  AssertEquals('no OnChange', 0, FChanges);
  AssertFalse('not modified', FRich.Modified);
  FRich.Lines[1] := 'zwei';
  AssertEquals('replaced', 'zwei', FRich.Lines[1]);
  AssertEquals('the others stay', 'one', FRich.Lines[0]);
  AssertEquals('one step', 1, d.UndoDepth);
  AssertEquals('one change', 1, FChanges);
  FRich.Lines[1] := '';
  AssertEquals('emptied', '', FRich.Lines[1]);
  AssertEquals('three lines still', 3, d.Text.ParaCount);
end;

procedure TTyRichEditEditTest.RefusedEdits(Sender: TObject; const AReason: string);
begin
  Inc(FRefusedEvents);
  if not FRefusedEdits then Exit;
  FRich.ForcedFormat := -1;
  FRich.Document.Execute(TTyRichInsertText.Create(0, 'h'));
end;

{ E-M3, E-M5, E-M9: what OnEditRefused is told is one of the control's own reasons, never the
  engine's sentence; it is raised once the edit is over - a handler that edits gets its own
  OnChange; and from code the engine's refusal raises with its reason in the package's words. }
procedure TTyRichEditEditTest.TestARefusalIsToldInTheControlsWordsAfterTheEdit;
var
  d: TTyRichDocument;
  t: TTyRichText;
  k, kf: Integer;
  raised: Boolean;
  fixed: Boolean;
  msg: string;
begin
  SetText('abcdef');
  d := FRich.Document;
  FRich.OnEditRefused := @RefusedEdits;
  FRefusedEvents := 0;
  FRefusedEdits := True;
  FRich.ForcedFormat := 999999;
  FRich.SelStart := 2;
  ResetEvents;
  Chars('x');
  AssertEquals('OnEditRefused once', 1, FRefusedEvents);
  AssertEquals('the control''s reason', rsRichEditRefusedRange, FRich.LastReason);
  AssertEquals('the handler''s edit went in', 'habcdef', FRich.Lines[0]);
  AssertEquals('and was heard: its OnChange', 1, FChanges);
  AssertEquals('one undo step: the handler''s', 1, d.UndoDepth);
  FRefusedEdits := False;
  FRich.ForcedFormat := -1;
  // the review's case: a paragraph and its separator typed over where a fixed row follows
  LoadBytes(FixtureFile('word-table-merged.rtf'));
  FRich.FinishLoading;
  FRich.UpdateView;
  d := FRich.Document;
  t := d.Text;
  kf := -1;
  for k := 1 to t.ParaCount - 1 do
    if (d.CellAt(k) <> nil) and d.CellAt(k).Row.HoldsNestedTable and
      ((d.CellAt(k - 1) = nil) or (d.CellAt(k - 1).Row <> d.CellAt(k).Row)) then
    begin
      kf := k;
      Break;
    end;
  AssertTrue('a fixed row after another paragraph', kf > 0);
  FRich.SelStart := t.ParaStart(kf - 1);
  FRich.SelLength := t.ParaStart(kf) - t.ParaStart(kf - 1);
  ResetEvents;
  FRefusedEvents := 0;
  Chars('Q');
  AssertTrue('told in the control''s words: ' + FRich.LastReason,
    (FRich.Refused = 0) or (FRich.LastReason = rsRichEditRefusedFixedRow) or
    (FRich.LastReason = rsRichEditRefusedCells) or (FRich.LastReason = rsRichEditRefusedRange));
  AssertEquals('as often as the event', FRich.Refused, FRefusedEvents);
  // from code the engine refuses the part that lands in the row, in the package's words
  if FRich.Refused = 0 then FRich.Undo;
  FRich.SelStart := t.ParaStart(kf - 1);
  FRich.SelLength := t.ParaStart(kf) - t.ParaStart(kf - 1);
  raised := False;
  fixed := False;
  msg := '';
  try
    FRich.SelText := 'Q';
  except
    on E: ETyRichModel do
    begin
      raised := True;
      fixed := (E is ETyRichRefused) and ETyRichRefused(E).FixedRow;
      msg := E.Message;
    end;
  end;
  AssertTrue('from code: raised', raised);
  AssertTrue('a fixed row in the way', fixed);
  AssertEquals('the package''s sentence', Format(rsRichModelPartRefused, [1, 'TTyRichInsertText']), msg);
  FRich.OnEditRefused := nil;
end;

{ E-M4 (R57), until Task 12: a selection that begins before a table and ends where its first
  row starts keeps its last separator when typed over or deleted (the paragraph before the
  table stays, Word's way); whole rows, from a row's start to a row's end, a key deletes - and
  the engine leaves a document that is whole, lays out, saves and reads back as it is. }
procedure TTyRichEditEditTest.TestTableEdgesFromTheKeyboard;
var
  d, b: TTyRichDocument;
  t: TTyRichText;
  kt, m, k, n: Integer;
  before, cell: string;
  st: TMemoryStream;
begin
  LoadBytes(FixtureFile('re-zh-table.rtf'));
  FRich.FinishLoading;
  FRich.UpdateView;
  d := FRich.Document;
  t := d.Text;
  kt := -1;
  for k := 1 to t.ParaCount - 1 do
    if (d.CellAt(k) <> nil) and (d.CellAt(k - 1) = nil) then
    begin
      kt := k;
      Break;
    end;
  AssertTrue('a paragraph before a table', kt > 0);
  before := FRich.Lines.Text;
  cell := FRich.Lines[kt];
  n := t.ParaCount;
  // typed over with its separator: the text goes, the paragraph before the table stays
  FRich.SelStart := t.ParaStart(kt - 1);
  FRich.SelLength := t.ParaStart(kt) - t.ParaStart(kt - 1);
  ResetEvents;
  Chars('Q');
  AssertEquals('not refused', 0, FRich.Refused);
  AssertEquals('typed in the paragraph before', 'Q', FRich.Lines[kt - 1]);
  AssertTrue('which is before the table still', d.CellAt(kt - 1) = nil);
  AssertEquals('the first cell as it was', cell, FRich.Lines[kt]);
  AssertEquals('as many paragraphs', n, t.ParaCount);
  FRich.Undo;
  AssertEquals('undone', before, FRich.Lines.Text);
  FRich.SelStart := t.ParaStart(kt - 1);
  FRich.SelLength := t.ParaStart(kt) - t.ParaStart(kt - 1);
  Press(VK_DELETE);
  AssertEquals('deleted: empty', '', FRich.Lines[kt - 1]);
  AssertTrue('deleted: before the table still', d.CellAt(kt - 1) = nil);
  AssertEquals('deleted: as many paragraphs', n, t.ParaCount);
  FRich.Undo;
  AssertEquals('undone again', before, FRich.Lines.Text);
  // the first row, whole
  m := kt;
  while (m < t.ParaCount) and (d.CellAt(m) <> nil) and (d.CellAt(m).Row = d.CellAt(kt).Row) do
    Inc(m);
  FRich.SelStart := t.ParaStart(kt);
  FRich.SelLength := t.ParaStart(m) - t.ParaStart(kt);
  ResetEvents;
  Press(VK_DELETE);
  AssertEquals('whole rows: not refused', 0, FRich.Refused);
  AssertEquals('the row''s paragraphs went', n - (m - kt), t.ParaCount);
  AssertEquals('the text is whole', '', t.CheckIntegrity);
  FRich.UpdateView;
  CheckSurface('a row deleted');
  st := TMemoryStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    st.Position := 0;
    b := TTyRichDocument.Create;
    try
      TyRichLoadRtfFull(b, st);
      AssertEquals('read back: the paragraphs', t.ParaCount, b.Text.ParaCount);
      for k := 0 to t.ParaCount - 1 do
      begin
        AssertEquals(Format('read back: paragraph %d', [k]),
          string(t.GetText(t.ParaStart(k), t.ParaLength(k))),
          string(b.Text.GetText(b.Text.ParaStart(k), b.Text.ParaLength(k))));
        AssertEquals(Format('read back: paragraph %d in a cell', [k]), d.CellAt(k) <> nil,
          b.CellAt(k) <> nil);
      end;
    finally
      b.Free;
    end;
  finally
    st.Free;
  end;
  FRich.Undo;
  AssertEquals('the row back', before, FRich.Lines.Text);
end;

{ E-M6 and E-M9: at the cut of a paragraph too long to lay out whole (CRichMaxParaLayoutChars
  - the cap has no seam: a real one) typing is refused and told rather than going in unseen;
  before the cut it goes in; an edit from code there leaves the caret at the cut, never in
  the hidden tail; Delete at the cut and Backspace after a cut paragraph do nothing. }
procedure TTyRichEditEditTest.TestAtTheCutOfALongParagraph;
var
  d: TTyRichDocument;
  t: TTyRichText;
begin
  SetText(StringOfChar('a', CRichMaxParaLayoutChars) + LineEnding + 'b');
  d := FRich.Document;
  t := d.Text;
  FRich.SelStart := CRichMaxParaLayoutChars;
  ResetEvents;
  Chars('x');
  AssertEquals('at the cut: refused once', 1, FRich.Refused);
  AssertEquals('why', rsRichEditRefusedLongPara, FRich.LastReason);
  AssertEquals('nothing went in', Int64(CRichMaxParaLayoutChars), t.ParaLength(0));
  AssertEquals('nothing on the history', 0, d.UndoDepth);
  FRich.SelStart := 50000;
  Chars('y');
  AssertEquals('before the cut it goes in', Int64(CRichMaxParaLayoutChars + 1), t.ParaLength(0));
  AssertEquals('the caret behind it', Int64(50001), FRich.CaretPos);
  // the paragraph is cut now; code inserts in its hidden tail: the caret goes to the cut
  FRich.SelStart := t.ParaLength(0);
  FRich.SelText := 'z';
  AssertEquals('code put it in', Int64(CRichMaxParaLayoutChars + 2), t.ParaLength(0));
  AssertEquals('the caret at the cut, not in the tail', Int64(CRichMaxParaLayoutChars), FRich.CaretPos);
  // Delete at the cut, Backspace after the cut paragraph: nothing, nothing told
  ResetEvents;
  FRich.SelStart := CRichMaxParaLayoutChars;
  Press(VK_DELETE);
  FRich.SelStart := t.ParaStart(1);
  Press(VK_BACK);
  AssertEquals('nothing deleted', Int64(CRichMaxParaLayoutChars + 2), t.ParaLength(0));
  AssertEquals('two paragraphs still', 2, t.ParaCount);
  AssertEquals('nothing told', 0, FRich.Refused);
  AssertEquals('no change', 0, FChanges);
end;

{ E-M9: the menu of an editor - undo, redo and cut offered and acting, none of them with
  ReadOnly; ReadOnly set ends the run of typing; Ctrl+Tab types a tab only with WantTabs (the
  memo's way). }
procedure TTyRichEditEditTest.TestTheMenuReadOnlyAndCtrlTabOfAnEditor;
var
  d: TTyRichDocument;
  acts: ITyTextEditActions;
  depth: Integer;
begin
  SetText('abc');
  d := FRich.Document;
  acts := FRich as ITyTextEditActions;
  AssertFalse('nothing to undo yet', acts.TeCanUndo);
  AssertFalse('the menu: an editor', acts.TeIsReadOnly);
  FRich.SelStart := 3;
  Chars('d');
  AssertTrue('the menu offers undo', acts.TeCanUndo);
  acts.TeUndo;
  AssertEquals('the menu undid it', 'abc', FRich.Lines[0]);
  AssertTrue('the menu offers redo', acts.TeCanRedo);
  acts.TeRedo;
  AssertEquals('the menu redid it', 'abcd', FRich.Lines[0]);
  FRich.SelStart := 0;
  FRich.SelLength := 1;
  acts.TeCut;
  AssertEquals('the menu cut it', 'bcd', FRich.Lines[0]);
  AssertEquals('to the clipboard', 'a', FRich.ClipText);
  FRich.Undo;
  AssertTrue('both sides have a step', d.CanUndo and d.CanRedo);
  FRich.ReadOnly := True;
  AssertFalse('ReadOnly: no undo offered', acts.TeCanUndo);
  AssertFalse('ReadOnly: no redo offered', acts.TeCanRedo);
  acts.TeUndo;
  acts.TeRedo;
  AssertEquals('ReadOnly: the menu does nothing', 'abcd', FRich.Lines[0]);
  FRich.ReadOnly := False;
  // ReadOnly set and cleared between two characters: two steps
  FRich.SelStart := 4;
  depth := d.UndoDepth;
  Chars('x');
  FRich.ReadOnly := True;
  FRich.ReadOnly := False;
  Chars('y');
  AssertEquals('ReadOnly ended the run', depth + 2, d.UndoDepth);
  // Ctrl+Tab
  FRich.WantTabs := False;
  AssertEquals('Ctrl+Tab without WantTabs goes on', VK_TAB, FRich.KeyResult(VK_TAB, [ssCtrl]));
  AssertEquals('nothing typed', 'abcdxy', FRich.Lines[0]);
  FRich.WantTabs := True;
  AssertEquals('Ctrl+Tab with WantTabs taken', 0, FRich.KeyResult(VK_TAB, [ssCtrl]));
  AssertEquals('a tab typed', 'abcdxy' + #9, FRich.Lines[0]);
end;

{ E-M10 (R55 c, d): Enter on an empty list item makes the item itself a plain paragraph -
  nothing added - its start indent and hanging offset 0, its right indent and alignment kept,
  one undo step; Backspace at the start of an item (empty or not) first takes only its
  numbering (the same reset, the caret stays, one step; a redo leaves the caret there), the
  next joins it with the paragraph before, which keeps its own format; joining keeps the
  first paragraph's format, the second's when the first is empty. Bulleted and numbered. }
procedure TTyRichEditEditTest.TestListItemsAndJoinsByKey;
var
  d: TTyRichDocument;
  t: TTyRichText;
  pf, f: TTyParaFormat;
  kind: TTyListKind;
  what: string;

  function FormatOf(AIndex: Integer): TTyParaFormat;
  begin
    Result := d.Formats.ParaFormat(d.ParaFormatOf(AIndex));
  end;

  procedure Aligned(AIndex: Integer; AAlign: TTyParaAlign);
  var
    v: TTyParaFormat;
  begin
    v := TyDefaultParaFormat;
    v.Align := AAlign;
    d.Execute(TTyRichSetParaFormat.Create(AIndex, AIndex, [pffAlign], v));
  end;

begin
  for kind in [lkBullet, lkDecimal] do
  begin
    what := Format('list kind %d', [Ord(kind)]);
    SetText('before' + LineEnding + 'item' + LineEnding);
    d := FRich.Document;
    t := d.Text;
    if t.ParaCount < 3 then d.Execute(TTyRichInsertText.Create(t.Length, #10, TyRichInheritFormat, False));
    AssertEquals(what + ': three paragraphs', 3, t.ParaCount);
    pf := TyDefaultParaFormat;
    pf.List.Kind := kind;
    pf.LeftIndent := 720;
    pf.FirstIndent := -360;
    pf.RightIndent := 144;
    pf.Align := paraCenter;
    d.Execute(TTyRichSetParaFormat.Create(1, 2, [pffList, pffLeftIndent, pffFirstIndent,
      pffRightIndent, pffAlign], pf));
    d.ClearUndo;
    // Enter on the empty item
    FRich.SelStart := t.ParaStart(2);
    Press(VK_RETURN);
    f := FormatOf(2);
    AssertEquals(what + ': Enter added nothing', 3, t.ParaCount);
    AssertTrue(what + ': out of the list', f.List.Kind = lkNone);
    AssertEquals(what + ': no start indent', 0, f.LeftIndent);
    AssertEquals(what + ': no hanging offset', 0, f.FirstIndent);
    AssertEquals(what + ': the right indent kept', 144, f.RightIndent);
    AssertTrue(what + ': the alignment kept', f.Align = paraCenter);
    AssertEquals(what + ': one step', 1, d.UndoDepth);
    FRich.Undo;
    AssertTrue(what + ': undone: an item again', FormatOf(2).List.Kind = kind);
    AssertEquals(what + ': with its indent', 720, FormatOf(2).LeftIndent);
    // Backspace at the start of an item with text: its numbering first
    FRich.SelStart := t.ParaStart(1);
    Press(VK_BACK);
    f := FormatOf(1);
    AssertEquals(what + ': Backspace joined nothing', 3, t.ParaCount);
    AssertEquals(what + ': the text stays', 'item', FRich.Lines[1]);
    AssertTrue(what + ': the numbering went', f.List.Kind = lkNone);
    AssertEquals(what + ': indent reset', 0, f.LeftIndent);
    AssertEquals(what + ': offset reset', 0, f.FirstIndent);
    AssertEquals(what + ': the right indent kept', 144, f.RightIndent);
    AssertEquals(what + ': the caret stays', t.ParaStart(1), FRich.CaretPos);
    FRich.Undo;
    AssertTrue(what + ': undone', FormatOf(1).List.Kind = kind);
    FRich.SelStart := 0;
    FRich.Redo;
    AssertEquals(what + ': redone: the caret where the key left it', t.ParaStart(1), FRich.CaretPos);
    AssertFalse(what + ': nothing selected', FRich.HasSelection);
    // the next Backspace joins; the paragraph before keeps its own format
    Press(VK_BACK);
    AssertEquals(what + ': joined', 2, t.ParaCount);
    AssertEquals(what + ': the text', 'beforeitem', FRich.Lines[0]);
    AssertTrue(what + ': the first''s format', FormatOf(0).Align = paraLeft);
    // an empty item: Backspace takes its numbering too
    FRich.SelStart := t.ParaStart(1);
    Press(VK_BACK);
    AssertEquals(what + ': an empty item stays', 2, t.ParaCount);
    AssertTrue(what + ': without its numbering', FormatOf(1).List.Kind = lkNone);
  end;
  // joining: the first paragraph's format; the second's when the first is empty
  SetText('first' + LineEnding + 'second');
  d := FRich.Document;
  t := d.Text;
  Aligned(0, paraCenter);
  Aligned(1, paraRight);
  FRich.SelStart := t.ParaStart(1);
  Press(VK_BACK);
  AssertTrue('Backspace: the first''s format', FormatOf(0).Align = paraCenter);
  FRich.Undo;
  FRich.SelStart := 5;
  Press(VK_DELETE);
  AssertTrue('Delete: the first''s format', FormatOf(0).Align = paraCenter);
  SetText(' ' + LineEnding + 'second');
  d := FRich.Document;
  t := d.Text;
  d.Execute(TTyRichDelete.Create(0, 1));
  Aligned(0, paraCenter);
  Aligned(1, paraRight);
  AssertEquals('the first empty', Int64(0), t.ParaLength(0));
  FRich.SelStart := t.ParaStart(1);
  Press(VK_BACK);
  AssertEquals('joined', 1, t.ParaCount);
  AssertTrue('the first empty: the second''s format', FormatOf(0).Align = paraRight);
end;

{ E-M11: in a plain text document (set as text, read from a text file) Shift+Enter makes a
  paragraph, as Enter - a text file has no line break inside a line, and a stored U+000B
  would be saved as the byte 0B. }
procedure TTyRichEditEditTest.TestShiftEnterInATextDocumentMakesAParagraph;
var
  d: TTyRichDocument;
  st: TBytesStream;
begin
  SetText('ab');
  d := FRich.Document;
  FRich.SelStart := 1;
  AssertEquals('taken', 0, FRich.KeyResult(VK_RETURN, [ssShift]));
  AssertEquals('a paragraph', 2, d.Text.ParaCount);
  AssertEquals('no line break stored', 0, Pos(#11, FRich.Lines.Text));
  st := TBytesStream.Create(RawBytes('one' + #13#10 + 'two'));
  try
    FRich.LoadFromStream(st, rfText);
  finally
    st.Free;
  end;
  FRich.UpdateView;
  d := FRich.Document;
  FRich.SelStart := 2;
  FRich.KeyResult(VK_RETURN, [ssShift]);
  AssertEquals('a text file: a paragraph too', 3, d.Text.ParaCount);
end;

{ ---- fix wave W13 ---- }

type
  // a command of an application's own whose CanExecute refuses (not a fixed row)
  TRefusingCommand = class(TTyRichCommand)
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    function CanExecute(ADoc: TTyRichDocument): Boolean; override;
  end;

  // MarkTable, which only a command may call otherwise
  TEditDocAccess = class(TTyRichDocument)
  end;

procedure TRefusingCommand.DoExecute(ADoc: TTyRichDocument);
begin
end;

function TRefusingCommand.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := False;
end;

procedure TTyRichEditEditTest.LoadOnRefusal(Sender: TObject; const AReason: string);
begin
  Inc(FRefusedEvents);
  FRich.Lines.Text := 'loaded by the handler';
end;

{ Q-M5: the across-cells refusal is told after the read scope closed: a handler that loads a
  document there loads it (before: ETyRichModel out of the key). }
procedure TTyRichEditEditTest.TestARefusalAcrossCellsIsToldOutsideTheReadScope;
var
  d: TTyRichDocument;
  t: TTyRichText;
  k: Integer;
begin
  LoadBytes(FixtureFile('re-zh-table.rtf'));
  FRich.FinishLoading;
  FRich.UpdateView;
  d := FRich.Document;
  t := d.Text;
  k := -1;
  for k := 0 to t.ParaCount - 2 do
    if (d.CellAt(k) <> nil) and (d.CellAt(k + 1) <> nil) and (d.CellAt(k) <> d.CellAt(k + 1)) and
      (t.ParaLength(k + 1) > 0) then Break;
  AssertTrue('two cells side by side', (k >= 0) and (k < t.ParaCount - 1));
  FRich.SelStart := t.ParaStart(k);
  FRich.SelLength := t.ParaStart(k + 1) + 1 - t.ParaStart(k);
  FRefusedEvents := 0;
  FRich.OnEditRefused := @LoadOnRefusal;
  try
    Press(VK_DELETE);
  finally
    FRich.OnEditRefused := nil;
  end;
  AssertEquals('told once', 1, FRefusedEvents);
  AssertEquals('the handler loaded its document', 'loaded by the handler', Trim(FRich.Lines.Text));
end;

{ Q-M6: whole rows of a table that ends the text (made by code: no RTF file ends inside a
  table) are refused until Task 12 - its last paragraph has no separator to go with it, and the
  engine would leave the row's other cells with none. The first row of the same table is whole
  rows the engine deletes cleanly. }
procedure TTyRichEditEditTest.TestWholeRowsAtTheTextsEndAreRefused;
var
  d: TTyRichDocument;
  t: TTyRichText;
  tb: TTyRichTable;
  i: Integer;
begin
  SetText('a' + LineEnding + 'b' + LineEnding + 'c' + LineEnding + 'd');
  d := FRich.Document;
  t := d.Text;
  tb := TTyRichTable.Create([1440, 2880]);
  tb.AddRow(2, '\trowd\trgaph108\cellx1440\cellx2880');
  tb.AddRow(2, '\trowd\trgaph108\cellx1440\cellx2880');
  TEditDocAccess(d).MarkTable(0, tb, [1, 1, 1, 1]).Free;
  FRich.UpdateView;
  AssertTrue('the last paragraph is in a cell', d.CellAt(3) <> nil);
  // the last row, to the text's end
  FRich.SelStart := t.ParaStart(2);
  FRich.SelLength := t.Length - t.ParaStart(2);
  ResetEvents;
  Press(VK_DELETE);
  AssertEquals('the last row: refused', 1, FRich.Refused);
  AssertEquals('across cells', rsRichEditRefusedCells, FRich.LastReason);
  AssertEquals('nothing deleted', 4, t.ParaCount);
  for i := 0 to 3 do AssertTrue(Format('paragraph %d in its cell', [i]), d.CellAt(i) <> nil);
  // everything
  FRich.SelectAll;
  ResetEvents;
  Press(VK_DELETE);
  AssertEquals('everything: refused', 1, FRich.Refused);
  AssertEquals('everything: nothing deleted', 4, t.ParaCount);
  // the first row: whole rows, deleted
  FRich.SelStart := 0;
  FRich.SelLength := t.ParaStart(2);
  ResetEvents;
  Press(VK_DELETE);
  AssertEquals('the first row: not refused', 0, FRich.Refused);
  AssertEquals('the first row went', 2, t.ParaCount);
  AssertTrue('the second row''s cells keep their paragraphs',
    (d.CellAt(0) <> nil) and (d.CellAt(1) <> nil) and (d.CellAt(0) <> d.CellAt(1)));
  AssertEquals('the text is whole', '', t.CheckIntegrity);
end;

{ Q-M10: when R57 keeps the paragraph end before a table (a selection from the text before it
  to the start of its first row), a cut puts on the clipboard what it removes - without that
  separator; a selection that is only that separator removes nothing and copies nothing. }
procedure TTyRichEditEditTest.TestACutCopiesWhatItRemoves;
var
  d: TTyRichDocument;
  t: TTyRichText;
  kt, k, writes: Integer;
  wanted: string;
begin
  LoadBytes(FixtureFile('re-zh-table.rtf'));
  FRich.FinishLoading;
  FRich.UpdateView;
  d := FRich.Document;
  t := d.Text;
  kt := -1;
  for k := 1 to t.ParaCount - 1 do
    if (d.CellAt(k) <> nil) and (d.CellAt(k - 1) = nil) and (t.ParaLength(k - 1) > 0) then
    begin
      kt := k;
      Break;
    end;
  AssertTrue('a paragraph with text before a table', kt > 0);
  wanted := FRich.Lines[kt - 1];
  FRich.SelStart := t.ParaStart(kt - 1);
  FRich.SelLength := t.ParaStart(kt) - t.ParaStart(kt - 1);
  writes := FRich.ClipWrites;
  Press(VK_X, [ssCtrl]);
  AssertEquals('cut', writes + 1, FRich.ClipWrites);
  AssertEquals('the clipboard has what went: the text, not the end kept', wanted, FRich.ClipText);
  AssertEquals('the paragraph before the table stays, empty', '', FRich.Lines[kt - 1]);
  AssertTrue('before the table still', d.CellAt(kt - 1) = nil);
  // only that separator: nothing removed, nothing copied
  FRich.SelStart := t.ParaStart(kt) - 1;
  FRich.SelLength := 1;
  writes := FRich.ClipWrites;
  Press(VK_X, [ssCtrl]);
  AssertEquals('only the end kept: nothing copied', writes, FRich.ClipWrites);
  AssertTrue('before the table still', d.CellAt(kt - 1) = nil);
end;

{ Q-O2: a command whose CanExecute refuses for a reason of its own (a command of Task 11, of an
  application) is told as a range that cannot be edited - not as a row with a nested table,
  which stays the reason of the engine's own text commands. }
procedure TTyRichEditEditTest.TestARefusedCommandIsToldItsOwnReason;
begin
  SetText('abc');
  ResetEvents;
  AssertFalse('refused', FRich.RunUser(TRefusingCommand.Create));
  AssertEquals('told once', 1, FRich.Refused);
  AssertEquals('as a range that cannot be edited', rsRichEditRefusedRange, FRich.LastReason);
  AssertEquals('nothing changed', 'abc', FRich.Lines[0]);
end;

{ W14 V-M9: pastes that change the heights of the view's paragraphs - several paragraphs of
  other sizes into the view's middle, lines of text, a picture -, their undo and redo: the kept
  surface equals a full redraw after each, at device scale 1 and 2. }
procedure TTyRichEditEditTest.TestPastesAndTheirUndoKeepTheSurfaceRight;
const
  Rtf = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard\qc\f0\fs48 Big one\par\pard\fs16 small\par' +
    '\pard\li720\fs32 indented and somewhat longer so that it wraps in the view\par}';
var
  scale: Integer;
  what: string;
  t: TTyRichText;
  pic: TBGRABitmap;
  st: TBytesStream;
  w: TBGRAWriterPNG;
begin
  for scale := 1 to 2 do
  begin
    what := Format('scale %d', [scale]);
    FreeAndNil(FRich);
    if scale > 1 then TyForceDeviceScaleForTest(scale, True, False)
    else TyForceDeviceScaleForTest(0, False);
    FPaintScale := scale;
    FRich := NewProbe;
    FRich.RichDocument := True;
    SetLinesOf(60);
    t := FRich.Document.Text;
    PaintAll;
    FRich.SelStart := t.ParaStart(4) + 2;
    PaintAll;
    FRich.ClipRtf := Rtf;
    FRich.ClipText := '';
    FRich.PasteFromClipboard;
    CheckSurface(what + ': RTF pasted');
    FRich.Undo;
    CheckSurface(what + ': undone');
    FRich.Redo;
    CheckSurface(what + ': redone');
    FRich.SelStart := t.ParaStart(10);
    FRich.ClipRtf := '';
    FRich.ClipText := 'one' + LineEnding + 'two' + LineEnding + 'three';
    FRich.PasteFromClipboard;
    CheckSurface(what + ': lines pasted');
    FRich.Undo;
    CheckSurface(what + ': undone');
    pic := TBGRABitmap.Create(40, 90, BGRA(10, 120, 200, 255));
    st := TBytesStream.Create;
    w := TBGRAWriterPNG.Create;
    try
      pic.SaveToStream(st, w);
      FRich.ClipText := '';
      FRich.ClipPicture := Copy(st.Bytes, 0, st.Size);
      FRich.ClipPictureKind := rikPng;
    finally
      w.Free;
      st.Free;
      pic.Free;
    end;
    FRich.SelStart := t.ParaStart(6);
    FRich.PasteFromClipboard;
    CheckSurface(what + ': a picture pasted');
    FRich.Undo;
    CheckSurface(what + ': undone');
    FRich.ClipPicture := nil;
  end;
end;

initialization
  RegisterTest(TTyRichEditEditTest);

end.
