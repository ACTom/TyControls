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
  BGRABitmap, BGRABitmapTypes,
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
    procedure FillPaintStyle(var AStyle: TTyRichPaintStyle); override;
  public
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
    function Msg(AMsg: Cardinal; ALParam: PtrInt; AWParam: PtrInt = 0): PtrInt;
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
  Result := Answer;
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
    GCS_CURSORPOS: Exit(CursorPos);
  end;
  Result := Length(AData);
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
    // the control freed while composing, with its window
    FRich.HandleNeeded;
    FRich.UpdateView;
    FRich.SelStart := 1;
    FRich.UpdateComposition('zz');
    AssertTrue('composing again', FRich.Composing);
    TImeProbe.AllEnds := 0;
    FreeAndNil(FRich);
    AssertEquals('the control''s end told nobody', 0, TImeProbe.AllEnds);
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

initialization
  RegisterTest(TTyRichEditImeTest);
finalization
  GBig := nil;
end.
