unit test.richedit.ime;

{ TTyRichEdit and an input method (Task 10b): a composition is shown in the text where it goes
  in - laid out with its paragraph, underlined, its caret where the input method says - and is
  not the document's until it is committed, as one insert through the typing path; what ends a
  composition; the rectangle the input method is told; read-only and the engine's refusals;
  what one composition update costs in a document of two million lines.

  Headless, on the editor's probe (test.richedit.edit's TEditProbe, itself test.richedit.
  control's TRichProbe), with the input method's three seams stood in for: what the platform
  input method is told when the control ends a composition, where the candidate window is put,
  and what win32's ImmGetCompositionStringW answers - so win32's messages run through the
  control's real handlers, Cocoa's bridge calls run as tyControls.CocoaWS makes them, and no
  real input method is ever started. No window is shown. Every bound is a count, never a
  time. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  LMessages, BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Painter, tyControls.TextMenu, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.TextIO, tyControls.RichEdit.Layout, tyControls.RichEdit,
  test.richedit.layoutdevice, test.richedit.control, test.richedit.edit;

type
  { The editor's probe with the input method's seams stood in for. }
  TImeProbe = class(TEditProbe)
  protected
    function ImeEndOnWidgetset(ACommit: Boolean): Boolean; override;
    procedure ImePlaceCandidates(const ARect: TRect); override;
    function ImeReadComposition(AIndex: LongWord; out AData: RawByteString): LongInt; override;
    function ImeSetContextDefault(AWParam, ALParam: PtrInt): PtrInt; override;
    procedure FillPaintStyle(var AStyle: TTyRichPaintStyle); override;
    procedure DestroyWnd; override;
  public
    { Fix wave W12. Late: the input method is told (ImeEndOnWidgetset True) and answers later
      - nothing while it is told. SetContexts / SetContextL: the default handling of
      WM_IME_SETCONTEXT, how often and the lParam handed on. TearDownTalk: the window's
      destruction (DestroyWnd, from LCL's destructor after the control's own body) first gets
      what can still reach a window that is going - the input method's messages, the focus
      messages, CM_EXIT, Cocoa's bridge, the composition's methods; TearDownTalks counts the
      runs that got through all of them. AllCommits: ImeEndOnWidgetset(True) by any probe. }
    Late: Boolean;
    SetContexts: Integer;
    SetContextL: PtrInt;
    TearDownTalk: Boolean;
    { ImeEndOnWidgetset: how often, with what; Answer: the input method answers a commit the
      way win32's does (its result through WM_IME_COMPOSITION, then WM_IME_ENDCOMPOSITION). }
    Ends, EndCommits: Integer;
    Answer: Boolean;
    { ImePlaceCandidates: how often, the last rectangle. }
    Places: Integer;
    LastPlace: TRect;
    { What ImmGetCompositionStringW answers: the composition, the result, the caret (UTF-16
      units), the attributes (a byte per UTF-16 unit). }
    CompStr, ResultStr: UnicodeString;
    CursorPos: Integer;
    Attrs: RawByteString;
    { The underline in a colour of its own (the pixels tell it from the text's). }
    ForceLine: Boolean;
    { Calls of ImeEndOnWidgetset made by any probe (a freed one's too). }
    class var AllEnds: Integer;
    class var TearDownTalks: Integer;
    class var AllCommits: Integer;
    function Msg(AMsg: Cardinal; ALParam: PtrInt; AWParam: PtrInt = 0): PtrInt;
    { DoExit alone (CM_EXIT without the window's kill-focus before it). }
    procedure ExitOnly;
  end;

  TTyRichEditImeTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TImeProbe;
    FChanges, FSelChanges: Integer;
    FPaintScale: Integer;
    FSaveCalls, FSaveRefusedAt: Integer;
    procedure Changed(Sender: TObject);
    procedure SelChanged(Sender: TObject);
    // fix wave W11: key-press handlers that clear characters
    procedure ClearUtf8(Sender: TObject; var UTF8Key: TUTF8Char);
    procedure ClearKey(Sender: TObject; var Key: Char);
    procedure CommitWhileSaving(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    function NewProbe: TImeProbe;
    procedure SetText(const S: string);
    procedure SetLinesOf(ACount: Integer);
    procedure LoadBytes(const B: TBytes);
    procedure PaintAll;
    procedure ResetEvents;
    function SaveBytes(AFormat: TTyRichFormat): RawByteString;
    function Copy1: TBGRABitmap;
    function Diff(A, B: TBGRABitmap): Integer;
    function RedCount(const AClient: TRect): Integer;
    function RedInColumn(AClientX: Integer): Integer;
    function ParaLayoutOf(APara: Integer): TTyParaLayout;
    procedure CaretCase(AScale: Integer);
    procedure RefusedCase(const AWhat, AReason: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // the brief's
    procedure TestImeCompositionIsNotInHistory;
    // one per requirement
    procedure TestTheCompositionIsLaidOutInlineAndUnderlined;
    procedure TestTheCompositionIsInTheTypingFormat;
    procedure TestTheClauseIsMarkedAndTheUnderlineIsTheThemes;
    procedure TestTheTextAfterItMovesAndACompositionWraps;
    procedure TestTextSelTextCopyAndSaveDoNotHaveIt;
    procedure TestModifiedAndOnChangeWaitForTheCommit;
    procedure TestACommitOverASelectionIsOneUndoStep;
    procedure TestACancelLeavesNoTrace;
    procedure TestTheFocusLeavingCommits;
    procedure TestAPressCommitsThenPlacesTheCaret;
    procedure TestAContentResetAndReadOnlyCancel;
    procedure TestTheHandlesAndTheControlsEnd;
    procedure TestTheCaretToldToTheImeAtScaleOneAndTwo;
    procedure TestTheCaretToldAfterAScrollAndAtAWrappedLinesEnd;
    procedure TestReadOnlyTakesNoComposition;
    procedure TestEachRefusalIsToldOnce;
    procedure TestChineseEmojiAndLineBreakCommits;
    procedure TestTheWin32MessagesDriveIt;
    procedure TestCocoasBridgeDrivesIt;
    procedure TestACodeEditMovesTheComposition;
    procedure TestAnUpdateInALargeDocumentTouchesOneParagraph;
    // fix wave W11
    procedure TestAWin32CommitPassesTheKeyPressEvents;
    procedure TestACompositionPastTheRightEdgeIsScrolledTo;
    // fix wave W12
    procedure TestTheWindowLosingTheFocusEndsIt;
    procedure TestTheCaretOrTheClauseAloneMoves;
    procedure TestTheSystemsCompositionWindowIsKeptAway;
    procedure TestDisablingCancelsAndTheEndAlwaysDrops;
    procedure TestAUsersEditCommitsTheCompositionFirst;
    procedure TestACommitIsTypingAtEveryRule;
    procedure TestCocoasSessionAfterTheControlEndedIt;
    procedure TestCocoasBaseIsTakenAfterTheSnap;
    procedure TestALateResultGoesWhereTheCompositionWas;
    procedure TestACommitTakesNoControlCharacter;
    procedure TestTheMarkerAndTheCapIgnoreTheComposition;
    procedure TestTheOrdersAndPlacesOfACommit;
    procedure TestTheCaretToldFollowsAZoomAndAWrapChange;
    procedure TestACompositionBelowTheBottomEdgeIsScrolledTo;
    procedure TestACompositionInATableCell;
  end;

implementation

const
  BS = '\';
  BigLines = 2000000;
  // win32's (imm.h / winuser.h)
  WM_IME_STARTCOMPOSITION = $010D;
  WM_IME_ENDCOMPOSITION = $010E;
  WM_IME_COMPOSITION = $010F;
  GCS_COMPSTR = $0008;
  GCS_COMPATTR = $0010;
  GCS_CURSORPOS = $0080;
  GCS_RESULTSTR = $0800;
  WM_IME_SETCONTEXT = $0281;
  WM_IME_REQUEST = $0288;
  IMR_QUERYCHARPOSITION = $0006;
  ISC_SHOWUIALL = PtrInt($C000000F);
  ISC_SHOWUICOMPOSITIONWINDOW = PtrInt($80000000);

var
  GBig: TBytes;

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

{ The same character as UTF-16. }
function W(ACode: Cardinal): UnicodeString;
begin
  if ACode < $10000 then Result := WideChar(ACode)
  else
    Result := WideChar($D800 + ((ACode - $10000) shr 10)) +
      WideChar($DC00 + ((ACode - $10000) and $3FF));
end;

{ ACount Chinese characters, from U+4E00 on. }
function Han(ACount: Integer; AFrom: Cardinal = $4E00): RawByteString;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to ACount - 1 do Result := Result + U(AFrom + Cardinal(i));
end;

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

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

function FixtureFile(const AName: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function IsRed(const P: TBGRAPixel): Boolean; inline;
begin
  Result := (P.red = 255) and (P.green = 0) and (P.blue = 0) and (P.alpha = 255);
end;

var
  GWidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if GWidgetSetReady then Exit;
  Forms.Application.Initialize;
  GWidgetSetReady := True;
end;

{ ---- the probe ---- }

function TImeProbe.ImeEndOnWidgetset(ACommit: Boolean): Boolean;
begin
  Inc(Ends);
  Inc(AllEnds);
  if ACommit then Inc(EndCommits);
  if ACommit then Inc(AllCommits);
  Result := Answer or Late;
  if Answer and ACommit and Composing then
  begin
    // what win32's input method does on CPS_COMPLETE: its result, then its end
    ResultStr := UTF8Decode(CompositionText);
    CompStr := '';
    Msg(WM_IME_COMPOSITION, GCS_RESULTSTR or GCS_COMPSTR);
    Msg(WM_IME_ENDCOMPOSITION, 0);
  end;
end;

procedure TImeProbe.ImePlaceCandidates(const ARect: TRect);
begin
  Inc(Places);
  LastPlace := ARect;
end;

function TImeProbe.ImeReadComposition(AIndex: LongWord; out AData: RawByteString): LongInt;

  function Bytes(const S: UnicodeString): RawByteString;
  begin
    Result := '';
    SetLength(Result, Length(S) * 2);
    if S <> '' then Move(S[1], Result[1], Length(S) * 2);
  end;

begin
  AData := '';
  case AIndex of
    GCS_COMPSTR: AData := Bytes(CompStr);
    GCS_RESULTSTR: AData := Bytes(ResultStr);
    GCS_COMPATTR: AData := Attrs;
    // (-1: at the composition's end, where an input method keeps it while one types)
    GCS_CURSORPOS: if CursorPos < 0 then Exit(Length(CompStr)) else Exit(CursorPos);
  end;
  Result := Length(AData);
end;

function TImeProbe.ImeSetContextDefault(AWParam, ALParam: PtrInt): PtrInt;
begin
  Inc(SetContexts);
  SetContextL := ALParam;
  Result := 0;
end;

procedure TImeProbe.DestroyWnd;
var
  buf: array[0..15] of Int64;
begin
  if TearDownTalk then
  begin
    TearDownTalk := False;
    CompStr := 'abc';
    ResultStr := 'zz';
    Msg(WM_IME_STARTCOMPOSITION, 0);
    Msg(WM_IME_COMPOSITION, GCS_COMPSTR or GCS_CURSORPOS or GCS_COMPATTR);
    Msg(WM_IME_COMPOSITION, GCS_RESULTSTR or GCS_COMPSTR);
    Msg(WM_IME_COMPOSITION, 0);
    Msg(WM_IME_ENDCOMPOSITION, 0);
    Msg(WM_IME_SETCONTEXT, ISC_SHOWUIALL, 1);
    FillChar(buf, SizeOf(buf), 0);
    Msg(WM_IME_REQUEST, PtrInt(@buf[0]), IMR_QUERYCHARPOSITION);
    Perform(LM_KILLFOCUS, 0, 0);
    Perform(LM_SETFOCUS, 0, 0);
    Perform(CM_EXIT, 0, 0);
    ImeSessionBegin;
    ImeReplace(0, 0, 'q');
    ImeReplace(0, 1, 'qq');
    ImeSessionEnd;
    BeginComposition;
    UpdateComposition('x');
    CommitComposition('y');
    CancelComposition;
    Inc(TearDownTalks);
  end;
  inherited DestroyWnd;
end;

procedure TImeProbe.ExitOnly;
begin
  DoExit;
end;

procedure TImeProbe.FillPaintStyle(var AStyle: TTyRichPaintStyle);
begin
  inherited FillPaintStyle(AStyle);
  if ForceLine then AStyle.CompositionLine := BGRA(255, 0, 0, 255);
end;

function TImeProbe.Msg(AMsg: Cardinal; ALParam: PtrInt; AWParam: PtrInt): PtrInt;
begin
  Result := Perform(AMsg, AWParam, ALParam);
end;

{ ---- the suite ---- }

procedure TTyRichEditImeTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FPaintScale := 1;
  FRich := NewProbe;
  ResetEvents;
end;

procedure TTyRichEditImeTest.TearDown;
begin
  TyForceDeviceScaleForTest(0, False);
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

function TTyRichEditImeTest.NewProbe: TImeProbe;
begin
  Result := TImeProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.OnChange := @Changed;
  Result.OnSelectionChange := @SelChanged;
  Result.ForceFocus := True;
  Result.CursorPos := -1;
  Result.ResetCounts;
end;

procedure TTyRichEditImeTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyRichEditImeTest.SelChanged(Sender: TObject);
begin
  Inc(FSelChanges);
end;

procedure TTyRichEditImeTest.ResetEvents;
begin
  FChanges := 0;
  FSelChanges := 0;
  if FRich <> nil then
  begin
    FRich.Refused := 0;
    FRich.LastReason := '';
    FRich.Ends := 0;
    FRich.EndCommits := 0;
    FRich.Places := 0;
  end;
end;

procedure TTyRichEditImeTest.SetText(const S: string);
begin
  FRich.Lines.Text := S;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichEditImeTest.SetLinesOf(ACount: Integer);
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

procedure TTyRichEditImeTest.LoadBytes(const B: TBytes);
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

procedure TTyRichEditImeTest.PaintAll;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width * FPaintScale, FRich.Height * FPaintScale);
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), True);
    // the caret over the blit, as Paint draws it (where the candidate window is put)
    FRich.CaretOn(bmp.Canvas);
  finally
    bmp.Free;
  end;
end;

function TTyRichEditImeTest.SaveBytes(AFormat: TTyRichFormat): RawByteString;
var
  st: TMemoryStream;
begin
  st := TMemoryStream.Create;
  try
    FRich.SaveToStream(st, AFormat);
    Result := '';
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Memory^, Result[1], st.Size);
  finally
    st.Free;
  end;
end;

function TTyRichEditImeTest.Copy1: TBGRABitmap;
begin
  PaintAll;
  Result := FRich.Surf.Duplicate as TBGRABitmap;
end;

function TTyRichEditImeTest.Diff(A, B: TBGRABitmap): Integer;
var
  x, y: Integer;
  p, q: PBGRAPixel;
begin
  Result := 0;
  if (A.Width <> B.Width) or (A.Height <> B.Height) then Exit(MaxInt);
  for y := 0 to A.Height - 1 do
  begin
    p := A.ScanLine[y];
    q := B.ScanLine[y];
    for x := 0 to A.Width - 1 do
    begin
      if (p^.red <> q^.red) or (p^.green <> q^.green) or (p^.blue <> q^.blue) or
        (p^.alpha <> q^.alpha) then
        Inc(Result);
      Inc(p);
      Inc(q);
    end;
  end;
end;

{ Red pixels of the surface inside AClient (client pixels; the whole surface when empty). }
function TTyRichEditImeTest.RedCount(const AClient: TRect): Integer;
var
  x, y, s: Integer;
  r: TRect;
  p: PBGRAPixel;
begin
  Result := 0;
  s := FRich.Scale;
  if IsRectEmpty(AClient) then r := Rect(0, 0, FRich.Surf.Width, FRich.Surf.Height)
  else r := Rect(AClient.Left * s, AClient.Top * s, AClient.Right * s, AClient.Bottom * s);
  for y := Math.Max(0, r.Top) to Math.Min(FRich.Surf.Height, r.Bottom) - 1 do
  begin
    p := FRich.Surf.ScanLine[y];
    Inc(p, Math.Max(0, r.Left));
    for x := Math.Max(0, r.Left) to Math.Min(FRich.Surf.Width, r.Right) - 1 do
    begin
      if IsRed(p^) then Inc(Result);
      Inc(p);
    end;
  end;
end;

{ Red pixels in the surface's column under client x AClientX. }
function TTyRichEditImeTest.RedInColumn(AClientX: Integer): Integer;
var
  y, x: Integer;
begin
  Result := 0;
  x := AClientX * FRich.Scale;
  for y := 0 to FRich.Surf.Height - 1 do
    if IsRed(FRich.Surf.ScanLine[y][x]) then Inc(Result);
end;

function TTyRichEditImeTest.ParaLayoutOf(APara: Integer): TTyParaLayout;
var
  k: Integer;
  b: TTyRichViewBlock;
begin
  Result := nil;
  for k := 0 to FRich.VisibleBlockCount - 1 do
  begin
    b := FRich.VisibleBlocks[k];
    if (b.FirstPara = APara) and (b.Layout is TTyParaLayout) then Exit(TTyParaLayout(b.Layout));
  end;
end;

{ ---- the brief's test ---- }

{ The history does not change while composing - no command, no undo step, nothing to undo
  that was not there - and the commit is one step more, which undo takes back whole. A commit
  merges with the typing before it, as the memo's (its commit is typing); one with a line
  break is a step of its own. }
procedure TTyRichEditImeTest.TestImeCompositionIsNotInHistory;
var
  d: TTyRichDocument;
  depth: Integer;
begin
  SetText('ab');
  d := FRich.Document;
  FRich.SelStart := 1;
  d.BreakMerge;
  depth := d.UndoDepth;
  AssertTrue('begins', FRich.BeginComposition);
  FRich.UpdateComposition('n');
  FRich.UpdateComposition('ni');
  FRich.UpdateComposition(U($4F60));
  AssertTrue('composing', FRich.Composing);
  AssertEquals('composing: no undo step', depth, d.UndoDepth);
  AssertEquals('composing: no redo step', 0, d.RedoDepth);
  AssertEquals('composing: the text as it was', 'ab', FRich.Lines[0]);
  FRich.CommitComposition(U($4F60) + U($597D));
  AssertFalse('no longer composing', FRich.Composing);
  AssertEquals('committed: one step more', depth + 1, d.UndoDepth);
  AssertEquals('committed: as typing', rsRichUndoTyping, d.UndoDescription);
  AssertEquals('the text', 'a' + U($4F60) + U($597D) + 'b', FRich.Lines[0]);
  AssertEquals('the caret behind it', Int64(3), FRich.CaretPos);
  FRich.Undo;
  AssertEquals('undone whole', 'ab', FRich.Lines[0]);
  FRich.Redo;
  // typing, then a commit: one step, as the memo's typing and commit are
  FRich.SelStart := 4;
  d.BreakMerge;
  depth := d.UndoDepth;
  FRich.Key8('x');
  FRich.UpdateComposition('zh');
  FRich.CommitComposition(U($4E2D));
  AssertEquals('typing and a commit merge', depth + 1, d.UndoDepth);
  // and a character typed after the commit: the same step - one undo takes all three
  FRich.Key8('y');
  AssertEquals('typing after the commit merges too', depth + 1, d.UndoDepth);
  AssertEquals('before the undo', 'a' + U($4F60) + U($597D) + 'bx' + U($4E2D) + 'y',
    FRich.Lines[0]);
  FRich.Undo;
  AssertEquals('one undo: the typing, the commit and the typing after it',
    'a' + U($4F60) + U($597D) + 'b', FRich.Lines[0]);
  FRich.Redo;
  FRich.SelStart := 7;
  // a commit with a line break: its own step
  d.BreakMerge;
  depth := d.UndoDepth;
  FRich.UpdateComposition('a');
  FRich.CommitComposition('c' + #13#10 + 'd');
  AssertEquals('a line break makes a step of its own', depth + 1, d.UndoDepth);
  FRich.Key8('z');
  AssertEquals('typing after it is another', depth + 2, d.UndoDepth);
end;

{ ---- one test per requirement ---- }

{ The composition is laid out in the paragraph, at the caret, as the same text typed there
  would be (the layout's text has it spliced in; the surface differs from that typed text's
  only by the underline), in the typing format; the underline is under it and nowhere else. }
procedure TTyRichEditImeTest.TestTheCompositionIsLaidOutInlineAndUnderlined;
var
  L: TTyParaLayout;
  composed, typed: TBGRABitmap;
  x0, x1, k, red: Integer;
  r: TRect;
begin
  FRich.ForceLine := True;
  SetText('Hello world');
  FRich.SelStart := 5;
  PaintAll;
  AssertEquals('no underline before', 0, RedCount(Rect(0, 0, 0, 0)));
  FRich.UpdateComposition(U($4F60) + U($597D));
  L := ParaLayoutOf(0);
  AssertTrue('a paragraph layout', L <> nil);
  AssertEquals('laid out with the paragraph', 'Hello' + U($4F60) + U($597D) + ' world', L.Text);
  AssertEquals('its place', 5, L.CompositionStart);
  AssertEquals('its length', 2, L.CompositionLength);
  AssertEquals('the document''s length', 11, L.Length);
  AssertEquals('the layouter shows it there', 0, FRich.Layouter.Composition.Para);
  composed := Copy1;
  try
    r := FRich.ImeRect;
    x0 := FRich.PositionRect(5).Left;
    x1 := r.Left;
    AssertTrue('it has a width', x1 > x0);
    red := RedCount(Rect(0, 0, 0, 0));
    AssertTrue('underlined', red > 0);
    AssertEquals('all of the underline under it', red,
      RedCount(Rect(x0, 0, x1 + 1, FRich.Height)));
    // the same text typed: the same surface but the underline
    FRich.ForceLine := False;
    FRich.CancelComposition;
    FRich.SelStart := 5;
    FRich.Key8(U($4F60));
    FRich.Key8(U($597D));
    FRich.ForceLine := True;
    typed := Copy1;
    try
      k := Diff(composed, typed);
      AssertEquals('only the underline differs from the text typed', red, k);
    finally
      typed.Free;
    end;
  finally
    composed.Free;
  end;
end;

{ The composition is in the typing format (TypingFormat, the seam a pending format will use),
  not in the format of the text around it. }
procedure TTyRichEditImeTest.TestTheCompositionIsInTheTypingFormat;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  st: TBytesStream;
  i, plain: Integer;
  found: Boolean;
begin
  st := TBytesStream.Create(RawBytes('{' + BS + 'rtf1' + BS + 'ansi{' + BS + 'fonttbl{' + BS +
    'f0 Arial;}}' + BS + 'f0 ab' + BS + 'b cd' + BS + 'b0' + BS + 'par}'));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
  d := FRich.Document;
  plain := d.RunsOf(0)[0].Format;
  AssertFalse('the first run is plain', fsBold in d.Formats.CharFormat(plain).Style);
  // inside the bold text, a plain typing format
  FRich.ForcedFormat := plain;
  FRich.SelStart := 3;
  FRich.UpdateComposition('X');
  L := ParaLayoutOf(0);
  found := False;
  for i := 0 to L.FragmentCount - 1 do
    if (L.Fragments[i].First <= L.CompositionStart) and
      (L.Fragments[i].First + L.Fragments[i].Count > L.CompositionStart) then
    begin
      found := True;
      AssertEquals('in the typing format', plain, L.Fragments[i].Format);
    end;
  AssertTrue('a fragment of it', found);
  // the text after it keeps its own
  for i := 0 to L.FragmentCount - 1 do
    if L.Fragments[i].First = L.CompositionStart + 1 then
      AssertTrue('the text after it bold still',
        fsBold in d.Formats.CharFormat(L.Fragments[i].Format).Style);
  FRich.ForcedFormat := -1;
end;

{ The clause the input method works on is underlined twice as thick (win32's target
  attribute; the memo marks none: the system's window does it there); the underline's colour
  is the theme's TyRichEditComposition border-color (--on-surface, the text's). }
procedure TTyRichEditImeTest.TestTheClauseIsMarkedAndTheUnderlineIsTheThemes;
var
  x0, w, a, b: Integer;
begin
  AssertTrue('the theme gives the underline a colour', FRich.Style.CompositionLine.alpha <> 0);
  AssertTrue('the text''s', FRich.Style.CompositionLine = FRich.Style.TextColor);
  FRich.ForceLine := True;
  SetText('ab');
  FRich.SelStart := 1;
  FRich.UpdateComposition(Han(3), 3, 1, 1);
  AssertEquals('the clause', 1, FRich.Layouter.Composition.ClauseFrom);
  AssertEquals('its end', 2, FRich.Layouter.Composition.ClauseTo);
  PaintAll;
  x0 := FRich.PositionRect(1).Left;
  w := (FRich.ImeRect.Left - x0) div 3;
  a := RedInColumn(x0 + w div 2);
  b := RedInColumn(x0 + w + w div 2);
  AssertTrue(Format('underlined (%d)', [a]), a > 0);
  AssertEquals('the clause twice as thick', 2 * a, b);
  AssertEquals('after the clause as before', a, RedInColumn(x0 + 2 * w + w div 2));
end;

{ The text after the composition moves by its width; a composition too long for the line
  wraps (the paragraph a line taller, the next one lower); its cancel puts all back. }
procedure TTyRichEditImeTest.TestTheTextAfterItMovesAndACompositionWraps;
var
  xb, top1, h0: Integer;
  L: TTyParaLayout;
begin
  FRich.ForceLine := True;
  SetText('abc def' + LineEnding + 'second');
  FRich.SelStart := 3;
  xb := FRich.PositionRect(4).Left;
  top1 := FRich.ParagraphRect(1).Top;
  h0 := ParaLayoutOf(0).LineCount;
  FRich.UpdateComposition('XY');
  AssertTrue('the text after it moved right', FRich.PositionRect(4).Left > xb);
  AssertEquals('by the composition''s width',
    FRich.ImeRect.Left - FRich.PositionRect(3).Left, FRich.PositionRect(4).Left - xb);
  AssertEquals('one line still', h0, ParaLayoutOf(0).LineCount);
  FRich.UpdateComposition(Han(60));
  L := ParaLayoutOf(0);
  AssertTrue(Format('wrapped (%d lines)', [L.LineCount]), L.LineCount > h0);
  AssertTrue('the next paragraph lower', FRich.ParagraphRect(1).Top > top1);
  PaintAll;
  AssertTrue('underlined on its first line',
    RedCount(Rect(0, 0, FRich.Width, FRich.ParagraphRect(0).Top + L.Lines[0].Height)) > 0);
  AssertTrue('and on its last',
    RedCount(Rect(0, FRich.ParagraphRect(0).Top + L.Lines[L.LineCount - 1].Top, FRich.Width,
      FRich.ParagraphRect(1).Top)) > 0);
  FRich.CancelComposition;
  AssertEquals('cancelled: its line count', h0, ParaLayoutOf(0).LineCount);
  AssertEquals('the next paragraph back', top1, FRich.ParagraphRect(1).Top);
  AssertEquals('the text after it back', xb, FRich.PositionRect(4).Left);
end;

{ Not the document's: the text, Lines, SelText, a copy and a save (txt and RTF) are as without
  it. A save does not end it (the memo's composition is never in its text either); a load does
  (the content it would go into is gone), and the input method is told to drop it. }
procedure TTyRichEditImeTest.TestTextSelTextCopyAndSaveDoNotHaveIt;
var
  txt, rtf, clipT: string;
  clipR: RawByteString;
  comp: RawByteString;
begin
  SetText('one two' + LineEnding + 'three');
  FRich.SelectAll;
  FRich.CopyToClipboard;
  clipT := FRich.ClipText;
  clipR := FRich.ClipRtf;
  txt := SaveBytes(rfText);
  rtf := SaveBytes(rfRtf);
  FRich.SelStart := 4;
  comp := U($4E2D) + U($6587);
  FRich.UpdateComposition(comp);
  AssertTrue('composing', FRich.Composing);
  AssertEquals('Lines', 'one two', FRich.Lines[0]);
  AssertEquals('the text''s length', Int64(13), FRich.Document.Text.Length);
  AssertEquals('RangeText', 'one two', FRich.RangeText(0, 7));
  AssertEquals('a text save', txt, SaveBytes(rfText));
  AssertEquals('an RTF save', rtf, SaveBytes(rfRtf));
  AssertTrue('a save leaves it composing', FRich.Composing);
  FRich.SelectAll;
  AssertEquals('SelText', 'one two' + LineEnding + 'three', FRich.SelText);
  FRich.CopyToClipboard;
  AssertEquals('a copy''s text', clipT, FRich.ClipText);
  AssertEquals('a copy''s RTF', clipR, FRich.ClipRtf);
  AssertTrue('still composing', FRich.Composing);
  // the commit still goes where it was shown (the selection code made goes)
  FRich.CommitComposition(comp);
  AssertEquals('committed where it was shown', 'one ' + comp + 'two', FRich.Lines[0]);
  // a load ends one
  FRich.SelStart := 0;
  FRich.UpdateComposition('x');
  ResetEvents;
  LoadBytes(RawBytes('loaded'));
  AssertFalse('a load ended it', FRich.Composing);
  AssertEquals('the input method told to drop it', 1, FRich.Ends);
  AssertEquals('not to commit it', 0, FRich.EndCommits);
  AssertEquals('the loaded text', 'loaded', FRich.Lines[0]);
  AssertEquals('nothing shown any more', -1, FRich.Layouter.Composition.Para);
end;

{ While composing, nothing is reported or marked: no OnChange, no OnSelectionChange, not
  Modified. The commit: one of each, Modified. }
procedure TTyRichEditImeTest.TestModifiedAndOnChangeWaitForTheCommit;
begin
  SetText('text');
  FRich.SelStart := 2;
  FRich.Modified := False;
  ResetEvents;
  FRich.BeginComposition;
  FRich.UpdateComposition('a');
  FRich.UpdateComposition('ab');
  FRich.UpdateComposition('abc', 1);
  AssertEquals('no OnChange', 0, FChanges);
  AssertEquals('no OnSelectionChange', 0, FSelChanges);
  AssertFalse('not Modified', FRich.Modified);
  FRich.CommitComposition('abc');
  AssertEquals('one OnChange', 1, FChanges);
  AssertEquals('one OnSelectionChange', 1, FSelChanges);
  AssertTrue('Modified', FRich.Modified);
  AssertEquals('the text', 'teabcxt', FRich.Lines[0]);
end;

{ A composition begun over a selection: the selection stays (shown, not deleted) while
  composing, and the commit replaces it - one undo step, which undo takes back whole (the
  selection selected again). }
procedure TTyRichEditImeTest.TestACommitOverASelectionIsOneUndoStep;
var
  d: TTyRichDocument;
  depth: Integer;
  rs: TRectArray;
begin
  SetText('Hello world');
  d := FRich.Document;
  FRich.SelStart := 6;
  FRich.SelLength := 5;
  depth := d.UndoDepth;
  FRich.UpdateComposition(U($4E16) + U($754C));
  AssertEquals('the selection stays', 'world', FRich.SelText);
  AssertEquals('in the text', 'Hello world', FRich.Lines[0]);
  // shown selected, the composition after it not
  rs := ParaLayoutOf(0).SelectionRects(6, 11);
  AssertEquals('one selected stretch', 1, Length(rs));
  AssertTrue('it ends where the composition begins',
    rs[0].Right <= FRich.PositionRect(11).Left - FRich.ParagraphRect(0).Left + 1);
  AssertEquals('no step', depth, d.UndoDepth);
  FRich.CommitComposition(U($4E16) + U($754C));
  AssertEquals('replaced', 'Hello ' + U($4E16) + U($754C), FRich.Lines[0]);
  AssertEquals('one undo step', depth + 1, d.UndoDepth);
  AssertEquals('the caret behind it', Int64(8), FRich.CaretPos);
  FRich.Undo;
  AssertEquals('undone whole', 'Hello world', FRich.Lines[0]);
  AssertEquals('the selection back', 'world', FRich.SelText);
end;

{ A cancel - CancelComposition, an empty commit, win32's emptied composition and end - leaves
  the document byte for byte and the surface pixel for pixel as before the composition, and no
  undo step, no event, not Modified. }
procedure TTyRichEditImeTest.TestACancelLeavesNoTrace;
var
  before, after: TBGRABitmap;
  rtf: RawByteString;
  d: TTyRichDocument;
  depth, way: Integer;
begin
  SetText('One paragraph' + LineEnding + 'and another one below it');
  d := FRich.Document;
  FRich.SelStart := 3;
  FRich.Modified := False;
  rtf := SaveBytes(rfRtf);
  depth := d.UndoDepth;
  before := Copy1;
  try
    for way := 0 to 2 do
    begin
      ResetEvents;
      FRich.UpdateComposition(Han(40));
      PaintAll;
      case way of
        0: FRich.CancelComposition;
        1: FRich.CommitComposition('');
        2:
          begin
            FRich.CompStr := '';
            FRich.Msg(WM_IME_COMPOSITION, GCS_COMPSTR);
            FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
          end;
      end;
      AssertFalse(Format('way %d: not composing', [way]), FRich.Composing);
      after := Copy1;
      try
        AssertEquals(Format('way %d: the surface as before', [way]), 0, Diff(before, after));
      finally
        after.Free;
      end;
      AssertEquals(Format('way %d: the document as before', [way]), rtf, SaveBytes(rfRtf));
      AssertEquals(Format('way %d: no step', [way]), depth, d.UndoDepth);
      AssertEquals(Format('way %d: no OnChange', [way]), 0, FChanges);
      AssertFalse(Format('way %d: not Modified', [way]), FRich.Modified);
      AssertEquals(Format('way %d: nothing shown', [way]), -1, FRich.Layouter.Composition.Para);
    end;
  finally
    before.Free;
  end;
end;

{ The focus leaving ends a composition by committing it: the input method is told to commit
  (win32: it answers with its result, here before the exit's end); with none to tell, the text
  shown goes in. Either way once, and nothing drawn after. }
procedure TTyRichEditImeTest.TestTheFocusLeavingCommits;
begin
  SetText('ab');
  FRich.SelStart := 1;
  FRich.UpdateComposition('xy');
  FRich.Leave;
  AssertFalse('ended', FRich.Composing);
  AssertEquals('the input method told to commit', 1, FRich.EndCommits);
  AssertEquals('none answered: what was shown went in', 'axyb', FRich.Lines[0]);
  // an input method that answers (win32's)
  FRich.Answer := True;
  FRich.SelStart := 4;
  FRich.UpdateComposition(U($4E2D));
  FRich.Leave;
  AssertFalse('ended', FRich.Composing);
  AssertEquals('its result went in, once', 'axyb' + U($4E2D), FRich.Lines[0]);
  AssertEquals('nothing shown', -1, FRich.Layouter.Composition.Para);
  // no composition: nothing told
  ResetEvents;
  FRich.Leave;
  AssertEquals('no composition: nothing told', 0, FRich.Ends);
end;

{ A press in the text ends the composition first (it goes in where it was shown), then the
  press places the caret. }
procedure TTyRichEditImeTest.TestAPressCommitsThenPlacesTheCaret;
var
  r: TRect;
begin
  SetText('abcdef');
  FRich.SelStart := 2;
  FRich.UpdateComposition('XY');
  r := FRich.PositionRect(0);
  FRich.PressAt(r.Left, (r.Top + r.Bottom) div 2);
  FRich.ReleaseAt(r.Left, (r.Top + r.Bottom) div 2);
  AssertFalse('ended', FRich.Composing);
  AssertEquals('committed where it was', 'abXYcdef', FRich.Lines[0]);
  AssertEquals('then the press placed the caret', Int64(0), FRich.CaretPos);
end;

{ A content reset (Lines.Text, a load) and ReadOnly set cancel a composition: nothing goes in,
  nothing is left drawn, the input method is told to drop it. }
procedure TTyRichEditImeTest.TestAContentResetAndReadOnlyCancel;
begin
  SetText('abc');
  FRich.SelStart := 1;
  FRich.UpdateComposition('zz');
  FRich.Lines.Text := 'new';
  AssertFalse('a content reset ended it', FRich.Composing);
  AssertEquals('dropped', 'new', FRich.Lines[0]);
  AssertEquals('told to drop it', 1, FRich.Ends);
  AssertEquals('not to commit it', 0, FRich.EndCommits);
  AssertEquals('nothing shown', -1, FRich.Layouter.Composition.Para);
  FRich.UpdateView;
  ResetEvents;
  FRich.SelStart := 1;
  FRich.UpdateComposition('zz');
  FRich.ReadOnly := True;
  AssertFalse('ReadOnly ended it', FRich.Composing);
  AssertEquals('nothing went in', 'new', FRich.Lines[0]);
  AssertEquals('told to drop it', 1, FRich.Ends);
  AssertEquals('not to commit it', 0, FRich.EndCommits);
  AssertEquals('nothing shown', -1, FRich.Layouter.Composition.Para);
end;

{ The window's destruction cancels a composition (and the hook goes); the control's
  destruction with a composition and a window frees nothing twice and tells nobody (the
  composition goes with it before its window). }
procedure TTyRichEditImeTest.TestTheHandlesAndTheControlsEnd;
var
  F: TForm;
begin
  NeedWidgetSet;
  F := TForm.CreateNew(nil);
  try
    FRich.Parent := F;
    F.HandleNeeded;
    FRich.HandleNeeded;
    AssertTrue('a handle', FRich.HandleAllocated);
    AssertFalse('the form is not shown', F.Visible);
    SetText('abc');
    FRich.SelStart := 1;
    FRich.UpdateComposition('zz');
    FRich.DropHandle;
    AssertFalse('the handle went', FRich.HandleAllocated);
    AssertFalse('it ended the composition', FRich.Composing);
    AssertEquals('told to drop it', 1, FRich.Ends);
    AssertEquals('nothing went in', 'abc', FRich.Lines[0]);
    AssertEquals('nothing shown', -1, FRich.Layouter.Composition.Para);
    { The control freed while composing, with its window (fix wave W12, J-I2): the input
      method is told to drop the composition once, while the document is there; what LCL's
      destructor still delivers to the window after the control's own body freed the document
      (the input method's messages, the focus taken away, CM_EXIT, Cocoa's bridge) does
      nothing - no access violation, nothing told again. }
    FRich.HandleNeeded;
    FRich.UpdateView;
    FRich.SelStart := 1;
    FRich.UpdateComposition('zz');
    AssertTrue('composing again', FRich.Composing);
    TImeProbe.AllEnds := 0;
    TImeProbe.AllCommits := 0;
    TImeProbe.TearDownTalks := 0;
    FRich.TearDownTalk := True;
    FreeAndNil(FRich);
    AssertEquals('the control''s end: the input method told to drop it, once', 1,
      TImeProbe.AllEnds);
    AssertEquals('not to commit it', 0, TImeProbe.AllCommits);
    AssertEquals('what the window got while it went reached nothing', 1, TImeProbe.TearDownTalks);
  finally
    if FRich <> nil then FRich.Parent := nil;
    F.Free;
  end;
  FRich := NewProbe;
end;

{ What the input method is told (ImeCaretBoundClient, the candidate window's place): the
  composition's caret, where the caret of the same text typed there would be - in client
  pixels at device scale 1 and 2 - and nothing while unfocused. }
procedure TTyRichEditImeTest.CaretCase(AScale: Integer);
var
  r, want: TRect;
  what: string;
  other: TImeProbe;
  keep: TImeProbe;
begin
  what := Format('scale %d', [AScale]);
  FreeAndNil(FRich);
  if AScale > 1 then TyForceDeviceScaleForTest(AScale, True, False)
  else TyForceDeviceScaleForTest(0, False);
  FPaintScale := AScale;
  FRich := NewProbe;
  SetText('Hello world');
  PaintAll;
  AssertEquals(what + ': the device scale', AScale, FRich.Scale);
  FRich.SelStart := 5;
  FRich.UpdateComposition('abc', 2);
  PaintAll;
  r := FRich.ImeRect;
  AssertFalse(what + ': a rectangle', IsRectEmpty(r));
  AssertTrue(what + ': the candidate window put there', EqualRect(r, FRich.LastPlace));
  // the same text typed, the caret two characters into it
  keep := FRich;
  other := NewProbe;
  try
    FRich := other;
    SetText('Helloabc world');
    PaintAll;
    other.SelStart := 7;
    want := other.CaretClientRect;
  finally
    FRich := keep;
    other.Free;
  end;
  AssertTrue(Format('%s: (%d,%d,%d,%d) where the typed text''s caret is (%d,%d,%d,%d)',
    [what, r.Left, r.Top, r.Right, r.Bottom, want.Left, want.Top, want.Right, want.Bottom]),
    EqualRect(r, want));
  FRich.ForceFocus := False;
  AssertTrue(what + ': unfocused, nothing', IsRectEmpty(FRich.ImeRect));
  FRich.ForceFocus := True;
end;

procedure TTyRichEditImeTest.TestTheCaretToldToTheImeAtScaleOneAndTwo;
begin
  CaretCase(1);
  CaretCase(2);
end;

{ After a scroll the composition's caret is told where it is now (and the candidate window
  goes there at the next paint); at the end of a composition that ends where its line wraps,
  the caret is at that line's end, not at the next line's start. }
procedure TTyRichEditImeTest.TestTheCaretToldAfterAScrollAndAtAWrappedLinesEnd;
var
  r0, r1, line0: TRect;
  t: TTyRichText;
  p, n: Integer;
  L: TTyParaLayout;
begin
  SetLinesOf(200);
  t := FRich.Document.Text;
  FRich.ScrollY := FRich.ParagraphRect(100).Top + FRich.ScrollY - 100;
  FRich.UpdateView;
  p := 100;
  FRich.SelStart := t.ParaStart(p) + 2;
  FRich.UpdateComposition('abc');
  PaintAll;
  r0 := FRich.ImeRect;
  AssertFalse('a rectangle', IsRectEmpty(r0));
  FRich.ScrollViewBy(-20);
  PaintAll;
  r1 := FRich.ImeRect;
  AssertEquals('scrolled: 20 pixels lower', r0.Top + 20, r1.Top);
  AssertEquals('the same x', r0.Left, r1.Left);
  AssertTrue('the candidate window followed', EqualRect(r1, FRich.LastPlace));
  FRich.CancelComposition;
  // a composition that fills its line exactly, the text going on on the next
  SetText(Han(40, $5000));
  L := ParaLayoutOf(0);
  AssertTrue('wrapped', L.LineCount > 1);
  n := L.Lines[0].Count;
  FRich.SelStart := 0;
  line0 := FRich.PositionRect(0);
  FRich.UpdateComposition(Han(n));
  L := ParaLayoutOf(0);
  AssertEquals('it fills the first line', n, L.Lines[0].Count);
  r0 := FRich.ImeRect;
  AssertEquals('at the first line''s end: its line', line0.Top, r0.Top);
  AssertTrue('at its end', r0.Left > line0.Left);
  AssertEquals('the document''s text starts the next line', n, L.Lines[1].First);
end;

{ ReadOnly: the input method is told so (ImeIsReadOnly); no composition begins, nothing is
  refused (as for a key), nothing goes in; win32's start is left to the system's window. }
procedure TTyRichEditImeTest.TestReadOnlyTakesNoComposition;
var
  ime: ITyImeEditable;
begin
  SetText('abc');
  FRich.ReadOnly := True;
  ime := FRich as ITyImeEditable;
  AssertTrue('read-only to the input method', ime.ImeIsReadOnly);
  AssertFalse('no composition begins', FRich.BeginComposition);
  FRich.UpdateComposition('x');
  AssertFalse('none', FRich.Composing);
  FRich.CommitComposition('x');
  AssertEquals('nothing went in', 'abc', FRich.Lines[0]);
  AssertEquals('nothing refused', 0, FRich.Refused);
  AssertEquals('win32: the system''s window', 0, FRich.Msg(WM_IME_STARTCOMPOSITION, 0));
  AssertFalse('still none', FRich.Composing);
  FRich.ReadOnly := False;
  AssertFalse('editable: not read-only', ime.ImeIsReadOnly);
  AssertEquals('win32: taken', 1, FRich.Msg(WM_IME_STARTCOMPOSITION, 0));
  AssertTrue('a composition', FRich.Composing);
end;

procedure TTyRichEditImeTest.RefusedCase(const AWhat, AReason: string);
var
  len: Int64;
begin
  len := FRich.Document.Text.Length;
  ResetEvents;
  // through win32's messages, as the input method sends them
  AssertEquals(AWhat + ': the start taken', 1, FRich.Msg(WM_IME_STARTCOMPOSITION, 0));
  AssertFalse(AWhat + ': no composition', FRich.Composing);
  AssertEquals(AWhat + ': refused once', 1, FRich.Refused);
  AssertEquals(AWhat + ': why', AReason, FRich.LastReason);
  AssertEquals(AWhat + ': the input method told to drop it', 1, FRich.Ends);
  FRich.CompStr := 'abc';
  FRich.Msg(WM_IME_COMPOSITION, GCS_COMPSTR);
  FRich.Msg(WM_IME_COMPOSITION, GCS_COMPSTR);
  AssertEquals(AWhat + ': nothing drawn', -1, FRich.Layouter.Composition.Para);
  FRich.ResultStr := 'abc';
  FRich.Msg(WM_IME_COMPOSITION, GCS_RESULTSTR);
  FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
  AssertEquals(AWhat + ': still told once', 1, FRich.Refused);
  AssertEquals(AWhat + ': nothing went in', len, FRich.Document.Text.Length);
  AssertEquals(AWhat + ': no OnChange', 0, FChanges);
  // and by hand
  ResetEvents;
  AssertFalse(AWhat + ': BeginComposition', FRich.BeginComposition);
  FRich.UpdateComposition('x');
  FRich.CommitComposition('x');
  AssertEquals(AWhat + ': by hand, told once', 1, FRich.Refused);
  AssertEquals(AWhat + ': nothing drawn', -1, FRich.Layouter.Composition.Para);
end;

procedure TTyRichEditImeTest.CommitWhileSaving(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FSaveCalls);
  if FSaveCalls <> 1 then Exit;
  FRich.Refused := 0;
  FRich.CommitComposition('zz');
  FSaveRefusedAt := FRich.Refused;
end;

{ When the document takes no edit - loading, incomplete, saving, a row that holds a nested
  table - a composition does not begin (refused once, what the input method sends goes
  nowhere, nothing drawn); one begun before a save is refused at its commit, once, and is not
  drawn afterwards. }
procedure TTyRichEditImeTest.TestEachRefusalIsToldOnce;
var
  d: TTyRichDocument;
  sl: TStringList;
  k, n: Integer;
  c: TTyRichCell;
  len: Int64;
begin
  FRich.Slices(2048, 2048);
  LoadBytes(PlainRtf(3000));
  AssertTrue('loading', FRich.Loading);
  FRich.UpdateView;
  FRich.SelStart := 1;
  RefusedCase('loading', rsRichEditRefusedLoading);
  FRich.CancelLoad;
  AssertTrue('incomplete', FRich.Incomplete);
  RefusedCase('incomplete', rsRichEditRefusedIncomplete);
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
    FRich.SelStart := d.Text.ParaStart(k) + 1;
    RefusedCase(Format('nested row %d', [k]), rsRichEditRefusedFixedRow);
    Break;
  end;
  AssertTrue('a nested row was met', n > 0);
  // a save: a composition begun before it is refused at its commit from the save's handler
  sl := TStringList.Create;
  try
    for k := 0 to 39999 do sl.Add('A line of text that the save writes out: ' + IntToStr(k));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  FRich.SelStart := 5;
  FRich.UpdateComposition('zz');
  len := FRich.Document.Text.Length;
  FRich.OnSaveProgress := @CommitWhileSaving;
  FSaveCalls := 0;
  FSaveRefusedAt := -1;
  SaveBytes(rfText);
  FRich.OnSaveProgress := nil;
  AssertTrue('the save reported its progress', FSaveCalls > 0);
  AssertEquals('saving: the commit refused once', 1, FSaveRefusedAt);
  AssertEquals('why', rsRichEditRefusedSaving, FRich.LastReason);
  AssertFalse('no longer composing', FRich.Composing);
  AssertEquals('nothing went in', len, FRich.Document.Text.Length);
  AssertEquals('nothing drawn after', -1, FRich.Layouter.Composition.Para);
end;

{ Several Chinese characters, an emoji (a surrogate pair in win32's UTF-16), and a commit with
  a line break (CR LF: one paragraph; the input methods that send one) go in as they are. }
procedure TTyRichEditImeTest.TestChineseEmojiAndLineBreakCommits;
var
  d: TTyRichDocument;
begin
  SetText('');
  d := FRich.Document;
  FRich.UpdateComposition('zhong wen zi');
  FRich.CommitComposition(U($4E2D) + U($6587) + U($5B57));
  AssertEquals('three Chinese characters', U($4E2D) + U($6587) + U($5B57), FRich.Lines[0]);
  AssertEquals('three positions', Int64(3), d.Text.Length);
  // through win32: UTF-16
  FRich.Msg(WM_IME_STARTCOMPOSITION, 0);
  FRich.CompStr := W($1F600) + 'a';
  FRich.CursorPos := 2;
  FRich.Msg(WM_IME_COMPOSITION, GCS_COMPSTR or GCS_CURSORPOS);
  AssertEquals('the emoji composed', string(U($1F600)) + 'a', string(FRich.CompositionText));
  AssertEquals('the caret behind it (two UTF-16 units): one character', 1,
    FRich.Layouter.Composition.Caret);
  FRich.ResultStr := W($1F600);
  FRich.Msg(WM_IME_COMPOSITION, GCS_RESULTSTR);
  FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
  AssertEquals('the emoji', U($4E2D) + U($6587) + U($5B57) + U($1F600), FRich.Lines[0]);
  AssertEquals('one position', Int64(4), d.Text.Length);
  AssertEquals('the caret behind it', Int64(4), FRich.CaretPos);
  FRich.CommitComposition('a' + #13#10 + 'b');
  AssertEquals('two paragraphs', 2, d.Text.ParaCount);
  AssertEquals('the second', 'b', FRich.Lines[1]);
  AssertEquals('the caret behind it', d.Text.ParaStart(1) + 1, FRich.CaretPos);
end;

{ win32's messages run the composition: the start (taken: no system window), the composition
  string with its caret (UTF-16 units) and its clause (the target attributes), the result
  (one commit), the end; Esc's emptied composition and end leave nothing. }
procedure TTyRichEditImeTest.TestTheWin32MessagesDriveIt;
var
  d: TTyRichDocument;
  depth: Integer;
begin
  SetText('ab');
  d := FRich.Document;
  FRich.SelStart := 1;
  d.BreakMerge;
  depth := d.UndoDepth;
  AssertEquals('the start taken', 1, FRich.Msg(WM_IME_STARTCOMPOSITION, 0));
  AssertTrue('composing', FRich.Composing);
  FRich.CompStr := 'ni';
  FRich.CursorPos := 2;
  FRich.Attrs := #0#0;
  AssertEquals('the composition taken', 1,
    FRich.Msg(WM_IME_COMPOSITION, GCS_COMPSTR or GCS_CURSORPOS or GCS_COMPATTR));
  AssertEquals('composed', 'ni', string(FRich.CompositionText));
  AssertEquals('no clause', 0, FRich.Layouter.Composition.ClauseTo -
    FRich.Layouter.Composition.ClauseFrom);
  FRich.CompStr := W($4F60) + W($597D) + W($5417);
  FRich.CursorPos := 1;
  FRich.Attrs := #0#1#1;
  FRich.Msg(WM_IME_COMPOSITION, GCS_COMPSTR or GCS_CURSORPOS or GCS_COMPATTR);
  AssertEquals('the converted text', string(U($4F60) + U($597D) + U($5417)),
    string(FRich.CompositionText));
  AssertEquals('its caret', 1, FRich.Layouter.Composition.Caret);
  AssertEquals('the clause''s start', 1, FRich.Layouter.Composition.ClauseFrom);
  AssertEquals('the clause''s end', 3, FRich.Layouter.Composition.ClauseTo);
  AssertEquals('not in the text', 'ab', FRich.Lines[0]);
  FRich.ResultStr := W($4F60) + W($597D);
  FRich.CompStr := '';
  AssertEquals('the result taken', 1,
    FRich.Msg(WM_IME_COMPOSITION, GCS_RESULTSTR or GCS_COMPSTR));
  AssertEquals('the end taken', 1, FRich.Msg(WM_IME_ENDCOMPOSITION, 0));
  AssertEquals('committed', 'a' + U($4F60) + U($597D) + 'b', FRich.Lines[0]);
  AssertEquals('one step', depth + 1, d.UndoDepth);
  AssertFalse('ended', FRich.Composing);
  // Esc
  FRich.Msg(WM_IME_STARTCOMPOSITION, 0);
  FRich.CompStr := 'abc';
  FRich.Msg(WM_IME_COMPOSITION, GCS_COMPSTR);
  FRich.CompStr := '';
  FRich.Msg(WM_IME_COMPOSITION, GCS_COMPSTR);
  FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
  AssertFalse('Esc: ended', FRich.Composing);
  AssertEquals('Esc: nothing went in', 'a' + U($4F60) + U($597D) + 'b', FRich.Lines[0]);
  AssertEquals('Esc: no step', depth + 1, d.UndoDepth);
end;

{ Cocoa's bridge (tyControls.CocoaWS) as it calls the control: a session begins, its marked
  text replaced each time (counted from the caret's index), its end commits the final text; a
  cancel (empty marked text, then the end) leaves nothing; a dead key's text with no session
  goes in at once. }
procedure TTyRichEditImeTest.TestCocoasBridgeDrivesIt;
var
  ime: ITyImeEditable;
  base: Integer;
begin
  SetText('ab');
  FRich.SelStart := 1;
  ime := FRich as ITyImeEditable;
  AssertFalse('editable', ime.ImeIsReadOnly);
  ime.ImeSessionBegin;
  base := ime.ImeCaretIndex;
  ime.ImeReplace(base, 0, 'n');
  ime.ImeReplace(base, 1, 'ni');
  AssertEquals('marked', 'ni', string(FRich.CompositionText));
  ime.ImeReplace(base, 2, U($4F60));
  AssertEquals('not in the text', 'ab', FRich.Lines[0]);
  AssertTrue('the caret told is the composition''s',
    EqualRect(ime.ImeCaretBoundClient, FRich.CaretClientRect));
  ime.ImeSessionEnd;
  AssertEquals('the session''s end committed it', 'a' + U($4F60) + 'b', FRich.Lines[0]);
  AssertFalse('ended', FRich.Composing);
  // a cancel
  ime.ImeSessionBegin;
  base := ime.ImeCaretIndex;
  ime.ImeReplace(base, 0, 'x');
  ime.ImeReplace(base, 1, '');
  ime.ImeSessionEnd;
  AssertEquals('cancelled: nothing', 'a' + U($4F60) + 'b', FRich.Lines[0]);
  AssertEquals('nothing shown', -1, FRich.Layouter.Composition.Para);
  // a dead key
  ime.ImeReplace(ime.ImeCaretIndex, 0, U($E9));
  AssertEquals('a dead key''s text at once', 'a' + U($4F60) + U($E9) + 'b', FRich.Lines[0]);
  AssertFalse('no composition left', FRich.Composing);
end;

{ A change from code while composing (a line inserted above) moves the composition with the
  text, as the caret is moved; it is shown and committed where it belongs. }
procedure TTyRichEditImeTest.TestACodeEditMovesTheComposition;
begin
  SetText('one' + LineEnding + 'two' + LineEnding + 'three');
  FRich.SelStart := FRich.Document.Text.ParaStart(2) + 2;
  FRich.UpdateComposition('XY');
  AssertEquals('shown in its paragraph', 2, FRich.Layouter.Composition.Para);
  FRich.Lines.Insert(0, 'zero');
  AssertTrue('still composing', FRich.Composing);
  AssertEquals('moved with its paragraph', 3, FRich.Layouter.Composition.Para);
  AssertEquals('its place', FRich.Document.Text.ParaStart(3) + 2, FRich.CompositionPos);
  FRich.UpdateView;
  AssertEquals('laid out there', 'thXYree', string(ParaLayoutOf(3).Text));
  FRich.CommitComposition('XY');
  AssertEquals('committed there', 'thXYree', FRich.Lines[3]);
  AssertEquals('the other lines as they are', 'two', FRich.Lines[2]);
end;

{ A composition update in the middle of two million lines lays out and paints its paragraph
  (and what reaches into its band): the counts of a keystroke (10a), nothing proportional to
  the document. }
procedure TTyRichEditImeTest.TestAnUpdateInALargeDocumentTouchesOneParagraph;
var
  t: TTyRichText;
  p, i: Integer;
  visits, n: Int64;
  texts: array[0..3] of RawByteString;
begin
  if GBig = nil then GBig := MakeLines(BigLines);
  LoadBytes(GBig);
  t := FRich.Document.Text;
  AssertEquals('all the lines', BigLines, t.ParaCount);
  FRich.UpdateView;
  FRich.ScrollY := t.TotalHeight div 2;
  FRich.UpdateView;
  p := FRich.TopParagraph + 3;
  FRich.SelStart := t.ParaStart(p) + 2;
  PaintAll;
  texts[0] := 'n';
  texts[1] := 'ni';
  texts[2] := U($4F60);
  texts[3] := U($4F60) + U($597D);
  for i := 0 to High(texts) do
  begin
    FRich.ResetCounts;
    visits := t.NodeVisits;
    FRich.UpdateComposition(texts[i]);
    n := t.NodeVisits - visits;
    AssertEquals(Format('update %d: one paragraph laid out (%d)', [i, FRich.LaidParas]), 1,
      FRich.LaidParas);
    AssertEquals(Format('update %d: that one', [i]), p, FRich.LaidMin);
    AssertTrue(Format('update %d: %d tree nodes entered', [i, n]), n <= 400);
    AssertTrue(Format('update %d: %d characters measured', [i, FRich.Device.MeasuredChars]),
      FRich.Device.MeasuredChars <= 10 * (t.ParaLength(p) + 3));
    PaintAll;
    AssertTrue(Format('update %d: %d blocks painted', [i, FRich.BlockPaints]),
      FRich.BlockPaints <= 3);
    AssertEquals(Format('update %d: no frame', [i]), 0, FRich.FramePaints);
  end;
  FRich.ResetCounts;
  FRich.CancelComposition;
  AssertEquals('the cancel: one paragraph laid out', 1, FRich.LaidParas);
  PaintAll;
  AssertTrue(Format('the cancel: %d blocks painted', [FRich.BlockPaints]), FRich.BlockPaints <= 3);
  WriteLn(Format('TTyRichEditImeTest: a composition update in the middle of %d lines: %d ' +
    'tree nodes, %d characters measured', [BigLines, n, FRich.Device.MeasuredChars]));
end;

{ ---- fix wave W11 ---- }

var
  GCleared: UTF8String;   // what the key-press handlers clear ('' none, '*' every character)

procedure TTyRichEditImeTest.ClearUtf8(Sender: TObject; var UTF8Key: TUTF8Char);
begin
  if (GCleared = '*') or (UTF8Key = GCleared) then UTF8Key := '';
end;

procedure TTyRichEditImeTest.ClearKey(Sender: TObject; var Key: Char);
begin
  if Key = 'q' then Key := #0;
end;

{ E-X2: on win32 a committed composition passes the key-press events a typed character passes,
  character by character, as the memo's commits do there: a handler that clears a character
  keeps it out of the one insert (one undo step); one that clears them all leaves nothing - no
  insert, no undo step, no OnChange. }
procedure TTyRichEditImeTest.TestAWin32CommitPassesTheKeyPressEvents;
var
  d: TTyRichDocument;
  depth: Integer;

  procedure Commit(const AText: UnicodeString);
  begin
    FRich.Msg(WM_IME_STARTCOMPOSITION, 0);
    FRich.CompStr := AText;
    FRich.Msg(WM_IME_COMPOSITION, GCS_COMPSTR);
    FRich.ResultStr := AText;
    FRich.CompStr := '';
    FRich.Msg(WM_IME_COMPOSITION, GCS_RESULTSTR or GCS_COMPSTR);
    FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
  end;

begin
  SetText('ab');
  d := FRich.Document;
  FRich.OnUTF8KeyPress := @ClearUtf8;
  FRich.OnKeyPress := @ClearKey;
  FRich.SelStart := 1;
  d.BreakMerge;
  depth := d.UndoDepth;
  // OnUTF8KeyPress clears the middle one of three
  GCleared := U($597D);
  ResetEvents;
  Commit(W($4F60) + W($597D) + W($5417));
  AssertEquals('the cleared one kept out', 'a' + U($4F60) + U($5417) + 'b', FRich.Lines[0]);
  AssertEquals('one insert, one undo step', depth + 1, d.UndoDepth);
  AssertEquals('one change', 1, FChanges);
  // OnKeyPress clears an ASCII one
  GCleared := '';
  FRich.SelStart := 0;
  d.BreakMerge;
  depth := d.UndoDepth;
  Commit('pqr');
  AssertEquals('OnKeyPress cleared q', 'pr', Copy(FRich.Lines[0], 1, 2));
  AssertEquals('one step', depth + 1, d.UndoDepth);
  // every character cleared: nothing at all
  GCleared := '*';
  FRich.SelStart := 0;
  depth := d.UndoDepth;
  ResetEvents;
  Commit(W($4F60) + W($597D));
  AssertEquals('nothing inserted', 'pr' + 'a' + U($4F60) + U($5417) + 'b', FRich.Lines[0]);
  AssertEquals('no undo step', depth, d.UndoDepth);
  AssertEquals('no OnChange', 0, FChanges);
  AssertFalse('the composition ended', FRich.Composing);
  GCleared := '';
  FRich.OnUTF8KeyPress := nil;
  FRich.OnKeyPress := nil;
end;

{ E-X3: with no wrapping, a composition that grows past the right edge is followed as the caret
  is (the least scroll across): its caret stays in the text, and so does the rectangle the
  input method is told. }
procedure TTyRichEditImeTest.TestACompositionPastTheRightEdgeIsScrolledTo;
var
  r, a: TRect;
  x0: Integer;
begin
  FRich.WrapMode := rwmNone;
  SetText(StringOfChar('a', 55) + LineEnding + 'b');
  FRich.SelStart := 55;
  PaintAll;
  x0 := FRich.PositionRect(0).Left;
  a := FRich.Area;
  FRich.UpdateComposition(StringOfChar('w', 40));
  PaintAll;
  r := FRich.ImeRect;
  AssertFalse('a rectangle', IsRectEmpty(r));
  AssertTrue(Format('scrolled across (the text from %d to %d)', [x0, FRich.PositionRect(0).Left]),
    FRich.PositionRect(0).Left < x0);
  AssertTrue(Format('the composition''s caret in the text (%d..%d of %d..%d)', [r.Left, r.Right,
    a.Left, a.Right]), (r.Left >= a.Left) and (r.Right <= a.Right));
  AssertTrue('the candidate window there', EqualRect(r, FRich.LastPlace));
  FRich.CancelComposition;
end;

{ ---- fix wave W12 ---- }

const
  TableRtf = '{' + BS + 'rtf1' + BS + 'ansi{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}' + BS + 'f0' +
    BS + 'trowd' + BS + 'cellx2400' + BS + 'cellx4800' + BS + 'intbl abcd efgh' + BS + 'cell ' +
    'wxyz' + BS + 'cell' + BS + 'row' + BS + 'pard after' + BS + 'par}';

{ The run character AOffset of paragraph APara is in. }
function RunAt(ADoc: TTyRichDocument; APara, AOffset: Integer): TTyRichRun;
var
  runs: TTyRunArray;
  i: Integer;
begin
  runs := ADoc.RunsOf(APara);
  Result := runs[0];
  for i := 0 to High(runs) do
    if runs[i].Start <= AOffset then Result := runs[i];
end;

{ A composition through win32's messages: the start and its string (the caret at its end). }
procedure ComposeByMessages(AProbe: TImeProbe; const AText: UnicodeString);
begin
  AProbe.Msg(WM_IME_STARTCOMPOSITION, 0);
  AProbe.CompStr := AText;
  AProbe.Msg(WM_IME_COMPOSITION, GCS_COMPSTR or GCS_CURSORPOS or GCS_COMPATTR);
end;

{ J-I1: on win32 the composition ends where the window loses the focus (LM_KILLFOCUS), before
  the input context serves another window: the input method is told to commit and its result
  comes here, before anything later; CM_EXIT's DoExit ends nothing a second time - and on win32
  ends nothing at all (it comes too late, and never for another form or program). }
procedure TTyRichEditImeTest.TestTheWindowLosingTheFocusEndsIt;
begin
  SetText('ab');
  FRich.SelStart := 1;
  FRich.Answer := True;
  ComposeByMessages(FRich, 'xy');
  ResetEvents;
  FRich.Perform(LM_KILLFOCUS, 0, 0);
  AssertFalse('the window lost the focus: ended', FRich.Composing);
  AssertEquals('the input method told to commit, once', 1, FRich.EndCommits);
  AssertEquals('its result went in here', 'axyb', FRich.Lines[0]);
  AssertEquals('one change', 1, FChanges);
  FRich.ExitOnly;
  AssertEquals('DoExit after it: nothing told again', 1, FRich.Ends);
  AssertEquals('nothing more went in', 'axyb', FRich.Lines[0]);
  // DoExit alone (no kill-focus before it): win32 ends nothing there
  FRich.SelStart := 4;
  ComposeByMessages(FRich, 'zz');
  ResetEvents;
  FRich.ExitOnly;
  AssertTrue('win32: DoExit alone ends nothing', FRich.Composing);
  AssertEquals('nothing told', 0, FRich.Ends);
  FRich.Perform(LM_KILLFOCUS, 0, 0);
  AssertEquals('the kill-focus does', 'axybzz', FRich.Lines[0]);
  // the focus back from another window: the candidate window is put again at the next paint
  FRich.SelStart := 0;
  PaintAll;
  ComposeByMessages(FRich, 'q');
  PaintAll;
  FRich.Places := 0;
  PaintAll;
  AssertEquals('not moved: not put again', 0, FRich.Places);
  FRich.Perform(LM_SETFOCUS, 0, 0);
  PaintAll;
  AssertEquals('the focus came back: put again', 1, FRich.Places);
  FRich.CancelComposition;
end;

{ J-M1: the input method's caret and its clause are read from a message that says only they
  changed - the drawn caret and the thick underline follow. lParam 0: what the context holds
  is read (an emptied composition: nothing drawn, still composing). }
procedure TTyRichEditImeTest.TestTheCaretOrTheClauseAloneMoves;
begin
  SetText('ab');
  FRich.SelStart := 1;
  FRich.Msg(WM_IME_STARTCOMPOSITION, 0);
  FRich.CompStr := W($4F60) + W($597D) + W($5417);
  FRich.CursorPos := 3;
  FRich.Attrs := #0#0#0;
  FRich.Msg(WM_IME_COMPOSITION, GCS_COMPSTR or GCS_CURSORPOS or GCS_COMPATTR);
  AssertEquals('the caret at the end', 3, FRich.Layouter.Composition.Caret);
  AssertEquals('no clause', 0, FRich.Layouter.Composition.ClauseTo);
  // the caret alone
  FRich.CursorPos := 1;
  FRich.Msg(WM_IME_COMPOSITION, GCS_CURSORPOS);
  AssertEquals('only the cursor flag: the caret moved', 1, FRich.Layouter.Composition.Caret);
  // the clause alone
  FRich.Attrs := #0#1#1;
  FRich.Msg(WM_IME_COMPOSITION, GCS_COMPATTR);
  AssertEquals('only the attribute flag: the clause''s start', 1,
    FRich.Layouter.Composition.ClauseFrom);
  AssertEquals('its end', 3, FRich.Layouter.Composition.ClauseTo);
  AssertEquals('the text as it was', string(U($4F60) + U($597D) + U($5417)),
    string(FRich.CompositionText));
  // lParam 0, the context as it was: nothing changes
  FRich.Msg(WM_IME_COMPOSITION, 0);
  AssertEquals('lParam 0, unchanged: the text', string(U($4F60) + U($597D) + U($5417)),
    string(FRich.CompositionText));
  // lParam 0, the context emptied
  FRich.CompStr := '';
  FRich.Msg(WM_IME_COMPOSITION, 0);
  AssertTrue('lParam 0, emptied: still composing', FRich.Composing);
  AssertEquals('nothing drawn', -1, FRich.Layouter.Composition.Para);
  FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
  AssertEquals('nothing went in', 'ab', FRich.Lines[0]);
end;

{ J-M2: WM_IME_SETCONTEXT when the window gets the context - the default handling is handed
  the flags without ISC_SHOWUICOMPOSITIONWINDOW (the composition is the control's), the rest
  as they came; read-only, or the context going: as it came (LCL's own way). }
procedure TTyRichEditImeTest.TestTheSystemsCompositionWindowIsKeptAway;
begin
  SetText('ab');
  AssertEquals('taken', 1, FRich.Msg(WM_IME_SETCONTEXT, ISC_SHOWUIALL, 1));
  AssertEquals('handed on once', 1, FRich.SetContexts);
  AssertEquals('without the composition window''s bit',
    ISC_SHOWUIALL and not ISC_SHOWUICOMPOSITIONWINDOW, FRich.SetContextL);
  FRich.SetContexts := 0;
  AssertEquals('the context going: as it came', 0, FRich.Msg(WM_IME_SETCONTEXT, ISC_SHOWUIALL, 0));
  AssertEquals('not handed on here', 0, FRich.SetContexts);
  FRich.ReadOnly := True;
  AssertEquals('read-only: as it came', 0, FRich.Msg(WM_IME_SETCONTEXT, ISC_SHOWUIALL, 1));
  AssertEquals('read-only: not handed on here', 0, FRich.SetContexts);
end;

{ J-M3: disabled while composing cancels it, as ReadOnly does (the input method told to drop
  it, nothing goes in, nothing drawn); the end message always drops what the control shows -
  also when the control answers as read-only (a parent disabled: IsEnabled False). }
procedure TTyRichEditImeTest.TestDisablingCancelsAndTheEndAlwaysDrops;
var
  F: TForm;
begin
  SetText('abc');
  FRich.SelStart := 1;
  FRich.UpdateComposition('zz');
  ResetEvents;
  FRich.Enabled := False;
  AssertFalse('disabled: ended', FRich.Composing);
  AssertEquals('told to drop it', 1, FRich.Ends);
  AssertEquals('not to commit it', 0, FRich.EndCommits);
  AssertEquals('nothing went in', 'abc', FRich.Lines[0]);
  AssertEquals('nothing shown', -1, FRich.Layouter.Composition.Para);
  FRich.Enabled := True;
  // a parent disabled: the control is not told (no EnabledChanged), it answers as read-only
  F := TForm.CreateNew(nil);
  try
    FRich.Parent := F;
    FRich.UpdateView;
    FRich.SelStart := 1;
    ComposeByMessages(FRich, 'zz');
    AssertTrue('composing', FRich.Composing);
    F.Enabled := False;
    AssertTrue('read-only to the input method', (FRich as ITyImeEditable).ImeIsReadOnly);
    FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
    AssertFalse('the end dropped it all the same', FRich.Composing);
    AssertEquals('nothing shown', -1, FRich.Layouter.Composition.Para);
    AssertEquals('nothing went in', 'abc', FRich.Lines[0]);
    F.Enabled := True;
  finally
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ J-M4: a user's edit or action while composing ends the composition first (committed where it
  was shown, as a press does) and then acts on the document the user sees - Ctrl+A, Ctrl+Z,
  Ctrl+X, the menu's Cut; the review's case: with the composition at the document's end,
  Ctrl+A then the input method's (late) result does not replace the document. }
procedure TTyRichEditImeTest.TestAUsersEditCommitsTheCompositionFirst;
var
  d: TTyRichDocument;
  acts: ITyTextEditActions;
begin
  SetText('Hello');
  d := FRich.Document;
  // Ctrl+A
  FRich.SelStart := 5;
  FRich.UpdateComposition('XY');
  FRich.Press(VK_A, [ssCtrl]);
  AssertFalse('Ctrl+A: ended', FRich.Composing);
  AssertEquals('Ctrl+A: committed first', 'HelloXY', FRich.Lines[0]);
  AssertEquals('then all selected', Int64(7), FRich.SelLength);
  // the review's case: an input method that answers later
  FRich.SelStart := 7;
  FRich.Late := True;
  ComposeByMessages(FRich, 'QQ');
  FRich.Press(VK_A, [ssCtrl]);
  AssertFalse('late: ended', FRich.Composing);
  AssertEquals('late: nothing in yet', 'HelloXY', FRich.Lines[0]);
  AssertEquals('late: all selected', Int64(7), FRich.SelLength);
  FRich.ResultStr := 'QQ';
  FRich.CompStr := '';
  FRich.Msg(WM_IME_COMPOSITION, GCS_RESULTSTR or GCS_COMPSTR);
  FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
  AssertEquals('the late result went where it was shown, nothing replaced', 'HelloXYQQ',
    FRich.Lines[0]);
  AssertEquals('Select All stays, with it', Int64(9), FRich.SelLength);
  FRich.Late := False;
  // Ctrl+Z: the commit first, then the undo takes it (with the typing it merged into)
  SetText('ab');
  d := FRich.Document;
  FRich.SelStart := 1;
  d.BreakMerge;
  FRich.Key8('x');
  FRich.UpdateComposition('YZ');
  FRich.Press(VK_Z, [ssCtrl]);
  AssertFalse('Ctrl+Z: ended', FRich.Composing);
  AssertEquals('Ctrl+Z: the typing and the commit undone', 'ab', FRich.Lines[0]);
  AssertEquals('nothing shown', -1, FRich.Layouter.Composition.Para);
  FRich.Redo;
  AssertEquals('redone', 'axYZb', FRich.Lines[0]);
  // Ctrl+X over a selection: the commit replaces it first, nothing is left selected to cut
  SetText('Hello world');
  FRich.SelStart := 6;
  FRich.SelLength := 5;
  FRich.UpdateComposition('QQ');
  FRich.Press(VK_X, [ssCtrl]);
  AssertFalse('Ctrl+X: ended', FRich.Composing);
  AssertEquals('Ctrl+X: the commit replaced the selection', 'Hello QQ', FRich.Lines[0]);
  // the menu's Cut, likewise
  FRich.SelStart := 0;
  FRich.SelLength := 5;
  FRich.UpdateComposition('W');
  acts := FRich as ITyTextEditActions;
  acts.TeCut;
  AssertFalse('the menu''s Cut: ended', FRich.Composing);
  AssertEquals('the menu''s Cut: the commit first', 'W QQ', FRich.Lines[0]);
  // code changing the selection meanwhile: the commit takes the one there was when it began
  SetText('Hello world');
  FRich.SelStart := 6;
  FRich.SelLength := 5;
  FRich.UpdateComposition('QQ');
  FRich.SelectAll;
  FRich.CommitComposition('QQ');
  AssertEquals('the selection when it began replaced, not all', 'Hello QQ', FRich.Lines[0]);
end;

{ J-M5: the commit is typing - the one routine: it is refused where a typed character is (a
  selection across cells; the cut of a long paragraph), keeps the paragraph end before a table
  as typing does, and goes in in the format its composition was shown in; a composition does
  not begin where a typed character would be refused. }
procedure TTyRichEditImeTest.TestACommitIsTypingAtEveryRule;
var
  d: TTyRichDocument;
  t: TTyRichText;
  k, kt, n: Integer;
  typed, committed, cell: string;
  plain, bold: Integer;
  st: TBytesStream;
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
  cell := FRich.Lines[kt];
  n := t.ParaCount;
  // the paragraph end kept before a table: typed over, then committed over
  FRich.SelStart := t.ParaStart(kt - 1);
  FRich.SelLength := t.ParaStart(kt) - t.ParaStart(kt - 1);
  FRich.Key8('Q');
  typed := FRich.Lines.Text;
  FRich.Undo;
  FRich.SelStart := t.ParaStart(kt - 1);
  FRich.SelLength := t.ParaStart(kt) - t.ParaStart(kt - 1);
  ResetEvents;
  FRich.UpdateComposition('Q');
  FRich.CommitComposition('Q');
  committed := FRich.Lines.Text;
  AssertEquals('the commit as the typed character: not refused', 0, FRich.Refused);
  AssertEquals('the commit as the typed character', typed, committed);
  AssertTrue('the paragraph before the table stays', d.CellAt(kt - 1) = nil);
  AssertEquals('the first cell as it was', cell, FRich.Lines[kt]);
  AssertEquals('as many paragraphs', n, t.ParaCount);
  FRich.Undo;
  // across two cells: neither begins, nor goes in
  k := kt + 1;
  while (k < t.ParaCount) and (d.CellAt(k) = d.CellAt(kt)) do Inc(k);
  AssertTrue('a paragraph of another cell', (k < t.ParaCount) and (d.CellAt(k) <> nil));
  FRich.SelStart := t.ParaStart(kt) + 1;
  FRich.SelLength := t.ParaStart(k) + 1 - FRich.SelStart;
  ResetEvents;
  FRich.Key8('Q');
  AssertEquals('typing across cells: refused once', 1, FRich.Refused);
  AssertEquals('why', rsRichEditRefusedCells, FRich.LastReason);
  ResetEvents;
  AssertFalse('a composition across cells does not begin', FRich.BeginComposition);
  AssertEquals('refused once, as typing', 1, FRich.Refused);
  AssertEquals('why: the same', rsRichEditRefusedCells, FRich.LastReason);
  FRich.UpdateComposition('Q');
  FRich.CommitComposition('Q');
  AssertEquals('what the input method sends after goes nowhere, told once', 1, FRich.Refused);
  ResetEvents;
  FRich.CancelComposition;
  FRich.CommitComposition('Q');
  AssertEquals('a commit with no composition across cells: refused once', 1, FRich.Refused);
  AssertEquals('nothing went in', cell, FRich.Lines[kt]);
  // the cut of a long paragraph
  SetText(StringOfChar('a', CRichMaxParaLayoutChars) + LineEnding + 'b');
  FRich.SelStart := CRichMaxParaLayoutChars;
  ResetEvents;
  AssertFalse('at the cut: no composition', FRich.BeginComposition);
  AssertEquals('refused once', 1, FRich.Refused);
  AssertEquals('as typing is', rsRichEditRefusedLongPara, FRich.LastReason);
  ResetEvents;
  FRich.CancelComposition;
  FRich.CommitComposition('x');
  AssertEquals('a commit there: refused once', 1, FRich.Refused);
  AssertEquals('nothing went in', Int64(CRichMaxParaLayoutChars), FRich.Document.Text.ParaLength(0));
  // the format it was shown in, not the one asked at the commit
  st := TBytesStream.Create(RawBytes('{' + BS + 'rtf1' + BS + 'ansi{' + BS + 'fonttbl{' + BS +
    'f0 Arial;}}' + BS + 'f0 ab' + BS + 'b cd' + BS + 'b0' + BS + 'par}'));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
  d := FRich.Document;
  plain := d.RunsOf(0)[0].Format;
  bold := d.RunsOf(0)[1].Format;
  FRich.ForcedFormat := plain;
  FRich.SelStart := 3;
  FRich.UpdateComposition('X');
  FRich.ForcedFormat := bold;
  FRich.CommitComposition('X');
  FRich.ForcedFormat := -1;
  AssertEquals('committed in the format it was shown in', plain, RunAt(d, 0, 3).Format);
end;

{ J-M6: Cocoa - the control ends the bridge's composition itself (the window losing the focus
  by code, a cancel from code) while Cocoa's session goes on: the marked text that session
  still sends, and its end, go nowhere - the text is in the document once. }
procedure TTyRichEditImeTest.TestCocoasSessionAfterTheControlEndedIt;
var
  ime: ITyImeEditable;
  base: Integer;
begin
  SetText('ab');
  FRich.SelStart := 1;
  ime := FRich as ITyImeEditable;
  ime.ImeSessionBegin;
  base := ime.ImeCaretIndex;
  ime.ImeReplace(base, 0, 'n');
  ime.ImeReplace(base, 1, 'ni');
  // the control commits it itself (the focus taken by code)
  FRich.Perform(LM_KILLFOCUS, 0, 0);
  AssertFalse('ended by the control', FRich.Composing);
  AssertEquals('what was shown went in', 'anib', FRich.Lines[0]);
  // Cocoa still has its marked text: its next updates and its end
  ime.ImeReplace(base, 2, U($4F60));
  AssertFalse('the session''s update starts nothing', FRich.Composing);
  AssertEquals('nothing drawn', -1, FRich.Layouter.Composition.Para);
  ime.ImeSessionEnd;
  AssertEquals('the session''s end commits nothing more', 'anib', FRich.Lines[0]);
  // a cancel from code, likewise
  ime.ImeSessionBegin;
  base := ime.ImeCaretIndex;
  ime.ImeReplace(base, 0, 'x');
  FRich.CancelComposition;
  ime.ImeReplace(base, 1, 'xy');
  ime.ImeSessionEnd;
  AssertEquals('after a cancel: nothing', 'anib', FRich.Lines[0]);
  // and a session after it works again
  ime.ImeSessionBegin;
  base := ime.ImeCaretIndex;
  ime.ImeReplace(base, 0, 'z');
  ime.ImeSessionEnd;
  AssertEquals('the next session commits', 'aniz' + 'b', FRich.Lines[0]);
end;

{ J-M7: Cocoa's base is taken after the composition began - its settle puts a caret a change
  left inside a cluster on a caret place, and the bridge then asks the caret's index. }
procedure TTyRichEditImeTest.TestCocoasBaseIsTakenAfterTheSnap;
var
  ime: ITyImeEditable;
  base: Integer;
begin
  SetText('ab' + U($301) + 'c');
  FRich.SelStart := 1;
  // code takes the b: the caret is left before the combining mark, to be snapped
  AssertTrue('deleted', FRich.Document.Execute(TTyRichDelete.Create(1, 1)));
  ime := FRich as ITyImeEditable;
  ime.ImeSessionBegin;
  base := ime.ImeCaretIndex;
  AssertTrue('the caret was snapped', base <> 1);
  ime.ImeReplace(base, 0, 'n');
  ime.ImeReplace(base, 1, 'ni');
  // (the snap may go back, where a clamp hides the difference: one more past it shows it)
  ime.ImeReplace(base + 2, 0, 'h');
  AssertEquals('counted from the snapped caret', 'nih', string(FRich.CompositionText));
  ime.ImeSessionEnd;
end;

{ J-M8: a press when the input method answers its commit later: the late result goes in where
  the composition was shown, and the caret stays where the press put it (moved with the
  text). The memo's win32 composition is the system's: its commit, typed as WM_CHAR, goes in
  at the caret wherever it is then - here the composition was shown in the text, and its text
  goes there. A result after the input method's next start is that composition's. }
procedure TTyRichEditImeTest.TestALateResultGoesWhereTheCompositionWas;
var
  r: TRect;
  d: TTyRichDocument;
  depth: Integer;
begin
  SetText('abcdef');
  d := FRich.Document;
  d.BreakMerge;
  depth := d.UndoDepth;
  // (where the press goes, measured before the composition moves the text after it)
  r := FRich.PositionRect(5);
  FRich.SelStart := 2;
  FRich.Late := True;
  ComposeByMessages(FRich, 'XY');
  FRich.PressAt(r.Left, (r.Top + r.Bottom) div 2);
  FRich.ReleaseAt(r.Left, (r.Top + r.Bottom) div 2);
  AssertFalse('the press ended it', FRich.Composing);
  AssertEquals('told to commit', 1, FRich.EndCommits);
  AssertEquals('nothing in yet', 'abcdef', FRich.Lines[0]);
  AssertEquals('the caret where the press put it', Int64(5), FRich.CaretPos);
  FRich.ResultStr := 'XY';
  FRich.CompStr := '';
  FRich.Msg(WM_IME_COMPOSITION, GCS_RESULTSTR or GCS_COMPSTR);
  FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
  AssertEquals('the late result where the composition was', 'abXYcdef', FRich.Lines[0]);
  AssertEquals('the caret where the press put it, moved with the text', Int64(7), FRich.CaretPos);
  AssertEquals('one step', depth + 1, d.UndoDepth);
  // a result after the next start belongs to that composition
  r := FRich.PositionRect(6);
  FRich.SelStart := 1;
  ComposeByMessages(FRich, 'Q');
  FRich.PressAt(r.Left, (r.Top + r.Bottom) div 2);
  FRich.ReleaseAt(r.Left, (r.Top + r.Bottom) div 2);
  FRich.Late := False;
  FRich.Msg(WM_IME_STARTCOMPOSITION, 0);
  FRich.ResultStr := 'R';
  FRich.CompStr := '';
  FRich.Msg(WM_IME_COMPOSITION, GCS_RESULTSTR or GCS_COMPSTR);
  FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
  AssertEquals('after the next start: at the caret', 'abXYcdRef', FRich.Lines[0]);
end;

{ J-M9: a commit keeps out what typing keeps out - DEL and the C1 controls too (tab, LF and
  U+000B are an input method's). }
procedure TTyRichEditImeTest.TestACommitTakesNoControlCharacter;
begin
  SetText('ab');
  FRich.SelStart := 1;
  FRich.CommitComposition('x' + #127 + 'y' + U($85) + U($9F) + 'z' + #1 + U($A0));
  AssertEquals('only the printable', 'axyz' + U($A0) + 'b', FRich.Lines[0]);
  FRich.Key8(#127);
  FRich.Key8(U($85));
  AssertEquals('typing takes neither either', 'axyz' + U($A0) + 'b', FRich.Lines[0]);
  FRich.UpdateComposition('p' + #127 + U($90) + 'q');
  AssertEquals('nor a composition', 'pq', string(FRich.CompositionText));
  FRich.CancelComposition;
end;

{ J-M10: a composition at a list paragraph's start leaves the marker in the paragraph's own
  format; one in a paragraph near the length cap does not count toward it (no cut notice
  while composing). }
procedure TTyRichEditImeTest.TestTheMarkerAndTheCapIgnoreTheComposition;
var
  d: TTyRichDocument;
  st: TBytesStream;
  plain, bold: Integer;
  pf: TTyParaFormat;
  L: TTyParaLayout;
begin
  st := TBytesStream.Create(RawBytes('{' + BS + 'rtf1' + BS + 'ansi{' + BS + 'fonttbl{' + BS +
    'f0 Arial;}}' + BS + 'f0 ab' + BS + 'b cd' + BS + 'b0' + BS + 'par}'));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  d := FRich.Document;
  plain := d.RunsOf(0)[0].Format;
  bold := d.RunsOf(0)[1].Format;
  pf := TyDefaultParaFormat;
  pf.List.Kind := lkBullet;
  AssertTrue('a list item', d.Execute(TTyRichSetParaFormat.Create(0, 0, [pffList], pf)));
  FRich.UpdateView;
  L := ParaLayoutOf(0);
  AssertTrue('a marker', L.HasMarker);
  AssertEquals('in the paragraph''s first format', plain, L.Marker.Format);
  FRich.ForcedFormat := bold;
  FRich.SelStart := 0;
  FRich.UpdateComposition('XY');
  L := ParaLayoutOf(0);
  AssertEquals('composing at its start', 0, L.CompositionStart);
  AssertEquals('the marker keeps the paragraph''s format', plain, L.Marker.Format);
  FRich.CancelComposition;
  FRich.ForcedFormat := -1;
  // near the cap
  SetText(StringOfChar('a', CRichMaxParaLayoutChars - 1) + LineEnding + 'b');
  FRich.SelStart := CRichMaxParaLayoutChars - 1;
  ResetEvents;
  FRich.UpdateComposition('abcde');
  AssertEquals('it began', 0, FRich.Refused);
  L := ParaLayoutOf(0);
  AssertTrue('a layout', L <> nil);
  AssertFalse('no cut notice while composing', L.Truncated);
  AssertEquals('all of it laid out', 5, L.CompositionLength);
  AssertEquals('the paragraph''s own length', Int64(CRichMaxParaLayoutChars - 1), L.Length);
  FRich.CancelComposition;
  // a paragraph past the cap, composing before its cut: the cut stays where it was
  SetText(StringOfChar('a', CRichMaxParaLayoutChars + 10) + LineEnding + 'b');
  L := ParaLayoutOf(0);
  AssertTrue('cut', L.Truncated);
  AssertEquals('at the cap', Int64(CRichMaxParaLayoutChars), L.LastCaretPos);
  FRich.SelStart := 50000;
  FRich.UpdateComposition('abc');
  L := ParaLayoutOf(0);
  AssertTrue('cut while composing', L.Truncated);
  AssertEquals('the cut where it was: the composition counts toward none of it',
    Int64(CRichMaxParaLayoutChars), L.LastCaretPos);
  FRich.CancelComposition;
end;

{ J-M11: a message with a result AND a new composition (what Microsoft Pinyin sends when one
  types on after a commit): the result once, the new composition after it; the end before the
  result (the order some input methods use); a composition at a paragraph's start, in an empty
  paragraph and before an object. }
procedure TTyRichEditImeTest.TestTheOrdersAndPlacesOfACommit;
var
  d: TTyRichDocument;
  depth: Integer;
  L: TTyParaLayout;
  t: TTyRichText;
begin
  SetText('ab');
  d := FRich.Document;
  t := d.Text;
  FRich.SelStart := 1;
  d.BreakMerge;
  depth := d.UndoDepth;
  ComposeByMessages(FRich, 'nihao');
  FRich.ResultStr := W($4F60) + W($597D);
  FRich.CompStr := 'sh';
  FRich.Msg(WM_IME_COMPOSITION, GCS_RESULTSTR or GCS_COMPSTR or GCS_CURSORPOS);
  AssertEquals('the result in once', 'a' + U($4F60) + U($597D) + 'b', FRich.Lines[0]);
  AssertEquals('one step', depth + 1, d.UndoDepth);
  AssertTrue('composing on', FRich.Composing);
  AssertEquals('the new composition', 'sh', string(FRich.CompositionText));
  AssertEquals('behind the result', Int64(3), FRich.CompositionPos);
  AssertEquals('laid out there', 'a' + U($4F60) + U($597D) + 'shb', string(ParaLayoutOf(0).Text));
  FRich.ResultStr := W($4E16);
  FRich.CompStr := '';
  FRich.Msg(WM_IME_COMPOSITION, GCS_RESULTSTR or GCS_COMPSTR);
  FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
  AssertEquals('the second result behind the first', 'a' + U($4F60) + U($597D) + U($4E16) + 'b',
    FRich.Lines[0]);
  // the end before the result
  SetText('ab');
  d := FRich.Document;
  t := d.Text;
  FRich.SelStart := 1;
  ComposeByMessages(FRich, 'ni');
  FRich.Msg(WM_IME_ENDCOMPOSITION, 0);
  AssertFalse('the end first: ended', FRich.Composing);
  FRich.ResultStr := W($4F60);
  FRich.Msg(WM_IME_COMPOSITION, GCS_RESULTSTR);
  AssertEquals('then the result: where it was', 'a' + U($4F60) + 'b', FRich.Lines[0]);
  AssertEquals('the caret behind it', Int64(2), FRich.CaretPos);
  // at a paragraph's start
  SetText('one' + LineEnding + 'two');
  t := FRich.Document.Text;
  FRich.SelStart := t.ParaStart(1);
  FRich.UpdateComposition('XY', 1);
  L := ParaLayoutOf(1);
  AssertEquals('at the start: laid out', 'XYtwo', string(L.Text));
  AssertEquals('the document''s length', Int64(3), L.Length);
  AssertTrue('the text after it behind it', FRich.PositionRect(t.ParaStart(1)).Left <
    FRich.PositionRect(t.ParaStart(1) + 1).Left);
  FRich.CommitComposition('XY');
  AssertEquals('committed at the start', 'XYtwo', FRich.Lines[1]);
  // in an empty paragraph
  SetText('one' + LineEnding + LineEnding + 'three');
  t := FRich.Document.Text;
  FRich.SelStart := t.ParaStart(1);
  FRich.UpdateComposition(Han(2));
  L := ParaLayoutOf(1);
  AssertEquals('an empty paragraph shows it', string(Han(2)), string(L.Text));
  AssertEquals('its length still 0', Int64(0), L.Length);
  AssertFalse('a caret rectangle', IsRectEmpty(FRich.ImeRect));
  FRich.CommitComposition(Han(2));
  AssertEquals('committed there', string(Han(2)), FRich.Lines[1]);
  AssertEquals('three paragraphs', 3, t.ParaCount);
  // before an object
  SetText('ab');
  d := FRich.Document;
  t := d.Text;
  AssertTrue('an object', d.Execute(TTyRichInsertObject.Create(1, TTyRichOpaque.Create('{' + BS +
    '*' + BS + 'x}'))));
  FRich.UpdateView;
  FRich.SelStart := 1;
  FRich.UpdateComposition('XY');
  L := ParaLayoutOf(0);
  AssertEquals('before the object: the document''s length', Int64(3), L.Length);
  AssertTrue('the object behind it', FRich.PositionRect(2).Left >= FRich.ImeRect.Left);
  FRich.CommitComposition('XY');
  AssertEquals('committed before it', 'aXY', string(t.GetText(0, 3)));
  AssertTrue('the object after it', RunAt(d, 0, 3).Obj <> nil);
end;

{ J-M11: a zoom and a change of the wrap mode while composing - the rectangle the input
  method is told follows: where the caret of the same text typed there is. }
procedure TTyRichEditImeTest.TestTheCaretToldFollowsAZoomAndAWrapChange;

  function TypedCaret(const AText: string; ACaret: Integer; AZoom: Integer;
    AWrap: TTyRichWrapMode): TRect;
  var
    keep, other: TImeProbe;
  begin
    keep := FRich;
    other := NewProbe;
    try
      FRich := other;
      other.WrapMode := AWrap;
      other.Zoom := AZoom;
      SetText(AText);
      PaintAll;
      other.SelStart := ACaret;
      Result := other.CaretClientRect;
    finally
      FRich := keep;
      other.Free;
    end;
  end;

var
  r, want: TRect;
  line: string;
begin
  SetText('Hello world');
  FRich.SelStart := 5;
  FRich.UpdateComposition('abc', 2);
  PaintAll;
  FRich.Zoom := 200;
  PaintAll;
  r := FRich.ImeRect;
  want := TypedCaret('Helloabc world', 7, 200, rwmWindow);
  AssertTrue(Format('zoomed: (%d,%d,%d,%d) where the typed text''s caret is (%d,%d,%d,%d)',
    [r.Left, r.Top, r.Right, r.Bottom, want.Left, want.Top, want.Right, want.Bottom]),
    EqualRect(r, want));
  AssertTrue('the candidate window there', EqualRect(r, FRich.LastPlace));
  FRich.CancelComposition;
  FRich.Zoom := 100;
  // a line that wraps: no wrapping, then wrapping, while composing in its second line
  line := 'one two three four five six seven eight nine ten eleven twelve thirteen';
  line := line + ' ' + line + ' ' + line;
  FRich.WrapMode := rwmNone;
  SetText(line);
  FRich.SelStart := 150;
  FRich.UpdateComposition('XY');
  PaintAll;
  FRich.WrapMode := rwmWindow;
  PaintAll;
  r := FRich.ImeRect;
  want := TypedCaret(Copy(line, 1, 150) + 'XY' + Copy(line, 151, MaxInt), 152, 100, rwmWindow);
  AssertTrue(Format('wrapped: (%d,%d,%d,%d) where the typed text''s caret is (%d,%d,%d,%d)',
    [r.Left, r.Top, r.Right, r.Bottom, want.Left, want.Top, want.Right, want.Bottom]),
    EqualRect(r, want));
  AssertTrue('on a line below the first', r.Top > FRich.PositionRect(0).Top);
  AssertTrue('the candidate window there', EqualRect(r, FRich.LastPlace));
  FRich.CancelComposition;
end;

{ J-M12: a composition that wraps below the view's bottom edge is scrolled to as the caret
  is: its caret, and the rectangle the input method is told, stay in the text. }
procedure TTyRichEditImeTest.TestACompositionBelowTheBottomEdgeIsScrolledTo;
var
  t: TTyRichText;
  p: Integer;
  a, r: TRect;
begin
  SetLinesOf(200);
  t := FRich.Document.Text;
  a := FRich.Area;
  // the last paragraph whose line is whole in the view
  p := 0;
  while FRich.ParagraphRect(p + 1).Bottom <= a.Bottom do Inc(p);
  FRich.SelStart := t.ParaStart(p) + 3;
  PaintAll;
  AssertEquals('not scrolled', Int64(0), FRich.ScrollY);
  FRich.UpdateComposition(Han(80));
  PaintAll;
  r := FRich.ImeRect;
  AssertFalse('a rectangle', IsRectEmpty(r));
  AssertTrue('scrolled down', FRich.ScrollY > 0);
  AssertTrue(Format('the composition''s caret in the text (%d..%d of %d..%d)', [r.Top, r.Bottom,
    a.Top, a.Bottom]), (r.Top >= a.Top) and (r.Bottom <= a.Bottom));
  AssertTrue('the candidate window there', EqualRect(r, FRich.LastPlace));
  FRich.CancelComposition;
  { The view scrolled away from the composition (the wheel), then an update: the view goes
    to the composition's caret, not to where it began - lines below that. }
  FRich.SelStart := t.ParaStart(100) + 2;
  FRich.UpdateComposition('x');
  FRich.ScrollY := 0;
  FRich.UpdateView;
  PaintAll;
  FRich.UpdateComposition(Han(600));
  PaintAll;
  r := FRich.ImeRect;
  AssertTrue(Format('from far away: the composition''s caret in the text (%d..%d of %d..%d)',
    [r.Top, r.Bottom, a.Top, a.Bottom]), (r.Top >= a.Top) and (r.Bottom <= a.Bottom));
  FRich.CancelComposition;
end;

{ J-I3: a composition in a table cell - the cell's text after it moves, a composition that
  wraps makes the row taller (and its cancel puts it back), the other cell answers as before,
  and the rectangle the input method is told is in the composing cell. }
procedure TTyRichEditImeTest.TestACompositionInATableCell;
var
  d: TTyRichDocument;
  t: TTyRichText;
  c2, after: TTyRichPos;
  xe, top0, i: Integer;
  r, cell0, cell1: TRect;
  before: array of TRect;
begin
  LoadBytes(RawBytes(TableRtf));
  FRich.FinishLoading;
  FRich.UpdateView;
  d := FRich.Document;
  t := d.Text;
  AssertTrue('a cell', d.CellAt(0) <> nil);
  AssertTrue('two cells in the row', (d.CellAt(1) <> nil) and (d.CellAt(1) <> d.CellAt(0)));
  AssertTrue('a paragraph after the table', d.CellAt(2) = nil);
  c2 := t.ParaStart(1);
  after := t.ParaStart(2);
  xe := FRich.PositionRect(5).Left;
  top0 := FRich.ParagraphRect(2).Top;
  SetLength(before, t.ParaLength(1) + 1);
  for i := 0 to High(before) do before[i] := FRich.PositionRect(c2 + i);
  cell0 := FRich.PositionRect(0);
  cell1 := FRich.PositionRect(c2);
  FRich.SelStart := 4;
  FRich.UpdateComposition('XY');
  AssertTrue('the cell''s text after it moved', FRich.PositionRect(5).Left > xe);
  r := FRich.ImeRect;
  AssertTrue(Format('the caret told in the first cell (%d, from %d, before %d)',
    [r.Left, cell0.Left, cell1.Left]), (r.Left > cell0.Left) and (r.Right <= cell1.Left));
  AssertEquals('in its line', cell0.Top, r.Top);
  for i := 0 to High(before) do
  begin
    AssertTrue(Format('the second cell''s position %d as before', [i]),
      EqualRect(before[i], FRich.PositionRect(c2 + i)));
    AssertEquals(Format('and its point', [i]), c2 + i,
      FRich.PositionAtPoint((before[i].Left + before[i].Right) div 2 + 1,
      (before[i].Top + before[i].Bottom) div 2));
  end;
  AssertEquals('the paragraph after the table where it was', top0, FRich.ParagraphRect(2).Top);
  // one that wraps: the row taller
  FRich.UpdateComposition(Han(30));
  AssertTrue('the row taller', FRich.ParagraphRect(2).Top > top0);
  r := FRich.ImeRect;
  AssertTrue('the caret told in the first cell still', (r.Left > cell0.Left) and
    (r.Right <= cell1.Left));
  AssertTrue('below its first line', r.Top > cell0.Top);
  FRich.CancelComposition;
  AssertEquals('cancelled: the row as it was', top0, FRich.ParagraphRect(2).Top);
  AssertEquals('the text after it back', xe, FRich.PositionRect(5).Left);
  FRich.UpdateComposition('XY');
  FRich.CommitComposition('XY');
  AssertEquals('committed in the cell', 'abcdXY efgh', FRich.Lines[0]);
  AssertTrue('still in it', d.CellAt(0) <> nil);
  AssertEquals('the caret behind it', Int64(6), FRich.CaretPos);
  // in the second cell: the rectangle told is that cell's (its offset in the row applied)
  c2 := t.ParaStart(1);
  cell1 := FRich.PositionRect(c2 + 2);
  FRich.SelStart := c2 + 2;
  FRich.UpdateComposition('XY');
  r := FRich.ImeRect;
  AssertTrue(Format('the caret told in the second cell (%d, behind %d)', [r.Left, cell1.Left]),
    r.Left > cell1.Left);
  AssertEquals('in its line', cell1.Top, r.Top);
  FRich.CancelComposition;
end;

initialization
  RegisterTest(TTyRichEditImeTest);
finalization
  GBig := nil;
end.
