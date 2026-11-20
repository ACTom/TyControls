unit test.richedit.perf;

{ TTyRichEditPerfTest: the one suite that asserts the wall clock (the gate runs it alone, in its
  serial list). The acceptance lines are the design's - a 100 MB txt and a 100 MB RTF show
  their first screen in 1 s and any scroll position in 100 ms, a keystroke paints in 30 ms;
  a bench run measures them on the user's machine - and the thresholds here are three
  times them: 3 s, 300 ms and 90 ms. A table of 10,000 rows is held to the keystroke's line
  for Tab and for the answers a table action's Update asks.

  How it paints: the control with no window, painted by PaintArea into an off-screen bitmap
  as a window paint (deferred pictures, the kept surface brought up to date and blitted) - the
  very path Paint takes, with the real text device (the package's fonts and renderer), not the
  layout tests' device. What a window adds - the system's own copy to the screen - is left
  out. No window is shown, nothing takes the foreground.

  The files (about 100 MB each) are made by the test under the system's temporary folder with
  names of their own, and deleted in TearDown whatever happened; making them is not timed.
  With less free room than they need the test is skipped with a message. The times and the
  process's peak working set are printed (the gate's log keeps them). Memory is asserted once:
  what reading the first screen of a file of deeply nested fields adds to the working set.

  Large fields are held to the design's lines themselves, not three times them: the first
  screen of one field around 100 MB, or of fields nested eight deep around 30 MB, within 1 s,
  the first paragraphs read again after their interval went within 100 ms - what a field costs
  is paid once, at the index, whatever its size and nesting. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  tyControls.Controller, tyControls.RichEdit;

type
  TTyRichEditPerfTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TTyRichEdit;
    FFiles: TStringList;
    function NewFile(const AExt: string): string;
    procedure CheckRoom;
    procedure Report(const AWhat: string; AMs: Double);
    { The caret put on the line at the view's top (plus two), the view painted (not timed);
      then one character typed and the paint after it, timed. }
    function Keystroke(ABitmap: TBitmap; AAtEnd: Boolean): Double;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestA100MBTextFileFirstScreenAndMiddle;
    procedure TestA100MBRtfFileFirstScreenAndMiddle;
    procedure TestA100MBRtfOfFieldsFirstScreenContentsAndKeys;
    procedure TestTabAndTheTableAnswersInALongTable;
    procedure TestAPictureResizedInALargeDocument;
    procedure TestDraggingTheSelectionInALargeDocument;
    procedure TestDroppingALargeRtfFromAnotherProgram;
    procedure TestOneFieldAroundA100MBRtf;
    procedure TestFieldsEightDeepAround30MB;
    procedure TestTheWholeParseOfFieldsEightDeepIsLinear;
    procedure TestASaveBesideOneFieldAround100MB;
    procedure TestASaveBesideFieldsEightDeepAround30MB;
  private
    procedure SaveBesideFields(ABytes: Int64; ANest: Integer);
  end;

implementation

uses
  Math, LCLType, Controls, BGRABitmap, BGRABitmapTypes, tyControls.RichEdit.Text,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands
  {$IFDEF LCLWin32}, test.richedit.dropacross{$ENDIF};

{$IFDEF MSWINDOWS}
type
  TTyPerfMemCounters = record
    cb: LongWord;
    PageFaultCount: LongWord;
    PeakWorkingSetSize, WorkingSetSize: PtrUInt;
    QuotaPeakPagedPoolUsage, QuotaPagedPoolUsage: PtrUInt;
    QuotaPeakNonPagedPoolUsage, QuotaNonPagedPoolUsage: PtrUInt;
    PagefileUsage, PeakPagefileUsage: PtrUInt;
  end;

function QueryPerformanceCounter(out ACount: Int64): LongBool; stdcall;
  external 'kernel32' name 'QueryPerformanceCounter';
function QueryPerformanceFrequency(out AFreq: Int64): LongBool; stdcall;
  external 'kernel32' name 'QueryPerformanceFrequency';
function GetCurrentProcess: THandle; stdcall; external 'kernel32' name 'GetCurrentProcess';
function GetProcessMemoryInfo(AProcess: THandle; var ACounters: TTyPerfMemCounters;
  ASize: LongWord): LongBool; stdcall; external 'psapi' name 'GetProcessMemoryInfo';
function GetDiskFreeSpaceExW(ADir: PWideChar; out AAvail, ATotal, AFree: QWord): LongBool;
  stdcall; external 'kernel32' name 'GetDiskFreeSpaceExW';
{$ENDIF}

const
  CFileBytes = 100 * 1024 * 1024;
  // room for both files and some to spare
  CRoomNeeded = Int64(600) * 1024 * 1024;
  CFirstScreenMs = 3000;
  CScrollMs = 300;
  // the design's 30 ms from a key to its paint, three times
  CKeystrokeMs = 90;

type
  TPerfRich = class(TTyRichEdit)
  public
    procedure PaintInto(ABitmap: TBitmap);
    { A character typed, as LCL delivers it; a key pressed. }
    procedure TypeChar(AChar: Char);
    procedure Key(AKey: Word; AShift: TShiftState);
    function HandleCentre(AHandle: TTyRichHandle; out APoint: TPoint): Boolean;
    procedure Press(X, Y: Integer);
    procedure MoveTo(X, Y: Integer);
    procedure Release(X, Y: Integer);
    function Step: Boolean;
    procedure DragTick;
  protected
    function DropPointOf(const AScreen: TPoint): TPoint; override;
    procedure FocusAfterDrop; override;
    function ClipboardFlavours: TTyRichClipFlavours; override;
    function ReadClipboardRtf: RawByteString; override;
  public
    { what a paste reads as the clipboard's RTF when not '' (never the system's clipboard) }
    ClipRtf: RawByteString;
    {$IFDEF LCLWin32}
    function DropTarget: IUnknown;
    {$ENDIF}
  end;

procedure TPerfRich.PaintInto(ABitmap: TBitmap);
begin
  PaintArea(ABitmap.Canvas, Rect(0, 0, Width, Height), Rect(0, 0, Width, Height), 96, True);
end;

procedure TPerfRich.TypeChar(AChar: Char);
var
  k: TUTF8Char;
begin
  k := AChar;
  UTF8KeyPress(k);
end;

procedure TPerfRich.Key(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

function TPerfRich.HandleCentre(AHandle: TTyRichHandle; out APoint: TPoint): Boolean;
var
  rs: TTyRichHandleRects;
begin
  Result := ObjectHandleRects(rs);
  APoint := Point((rs[AHandle].Left + rs[AHandle].Right) div 2,
    (rs[AHandle].Top + rs[AHandle].Bottom) div 2);
end;

procedure TPerfRich.Press(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

procedure TPerfRich.MoveTo(X, Y: Integer);
begin
  MouseMove([ssLeft], X, Y);
end;

procedure TPerfRich.Release(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

function TPerfRich.Step: Boolean;
begin
  Result := StepBackground;
end;

procedure TPerfRich.DragTick;
begin
  DragScrollTick(nil);
end;

function TPerfRich.DropPointOf(const AScreen: TPoint): TPoint;
begin
  // (no window: the screen is the client's pixels)
  Result := AScreen;
end;

procedure TPerfRich.FocusAfterDrop;
begin
  // (never the focus or the foreground in a test)
end;

function TPerfRich.ClipboardFlavours: TTyRichClipFlavours;
begin
  if ClipRtf <> '' then Result := [rcfRtf] else Result := inherited ClipboardFlavours;
end;

function TPerfRich.ReadClipboardRtf: RawByteString;
begin
  if ClipRtf <> '' then Result := ClipRtf else Result := inherited ReadClipboardRtf;
end;

{$IFDEF LCLWin32}
function TPerfRich.DropTarget: IUnknown;
begin
  Result := OleDropTarget;
end;
{$ENDIF}

{ A PNG whose pixels do not compress: about AW x AH x 4 bytes. }
function NoisePng(AW, AH: Integer): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
  p: PBGRAPixel;
  i: Integer;
  seed: Cardinal;
begin
  b := TBGRABitmap.Create(AW, AH);
  st := TBytesStream.Create;
  try
    seed := 2463534242;
    p := b.Data;
    for i := 0 to AW * AH - 1 do
    begin
      // xorshift: no pattern a deflate could take away
      seed := seed xor (seed shl 13);
      seed := seed xor (seed shr 17);
      seed := seed xor (seed shl 5);
      p^.red := seed and $FF;
      p^.green := (seed shr 8) and $FF;
      p^.blue := (seed shr 16) and $FF;
      p^.alpha := 255;
      Inc(p);
    end;
    b.InvalidateBitmap;
    b.SaveToStreamAs(st, ifPng);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

function Clock: Double;
{$IFDEF MSWINDOWS}
var
  c, f: Int64;
begin
  QueryPerformanceCounter(c);
  QueryPerformanceFrequency(f);
  Result := c / f * 1000;
end;
{$ELSE}
begin
  Result := GetTickCount64;
end;
{$ENDIF}

function PeakWorkingSet: string;
{$IFDEF MSWINDOWS}
var
  m: TTyPerfMemCounters;
begin
  FillChar(m, SizeOf(m), 0);
  m.cb := SizeOf(m);
  if GetProcessMemoryInfo(GetCurrentProcess, m, SizeOf(m)) then
    Result := Format('%d MB', [m.PeakWorkingSetSize div (1024 * 1024)])
  else
    Result := 'not known';
end;
{$ELSE}
begin
  Result := 'not measured on this platform';
end;
{$ENDIF}

{ A character as UTF-8, from its number (this file stays ASCII). }
function U8(ACode: Cardinal): RawByteString;
begin
  if ACode < $80 then Result := AnsiChar(ACode)
  else if ACode < $800 then
    Result := AnsiChar($C0 or (ACode shr 6)) + AnsiChar($80 or (ACode and $3F))
  else
    Result := AnsiChar($E0 or (ACode shr 12)) + AnsiChar($80 or ((ACode shr 6) and $3F)) +
      AnsiChar($80 or (ACode and $3F));
end;

function SizeOfFile(const APath: string): Int64;
var
  sr: TSearchRec;
begin
  Result := 0;
  if FindFirst(APath, faAnyFile, sr) = 0 then
  begin
    Result := sr.Size;
    FindClose(sr);
  end;
end;

procedure WriteRaw(AStream: TStream; const S: RawByteString);
begin
  if S <> '' then AStream.WriteBuffer(S[1], Length(S));
end;

{ About ABytes of text: lines of ordinary length, Chinese and Latin mixed, CRLF. }
procedure MakeText(const APath: string; ABytes: Int64);
var
  f: TFileStream;
  buf: TMemoryStream;
  zh, line: RawByteString;
  i, n: Integer;
begin
  zh := U8($4E2D) + U8($6587) + U8($6587) + U8($672C) + U8($6D4B) + U8($8BD5) + U8($7684) +
    U8($4E00) + U8($884C);
  f := TFileStream.Create(APath, fmCreate);
  buf := TMemoryStream.Create;
  try
    n := 0;
    while f.Size + buf.Size < ABytes do
    begin
      Inc(n);
      case n mod 3 of
        0: line := 'Line ' + IntToStr(n) + ' of the generated file: some ordinary words, ' + zh +
             ' and a few more words to end it.';
        1: line := zh + zh + ' ' + IntToStr(n) + ' ' + zh;
      else
        line := 'A shorter Latin line ' + IntToStr(n) + '.';
      end;
      WriteRaw(buf, line + #13#10);
      if buf.Size > 1024 * 1024 then
      begin
        f.WriteBuffer(buf.Memory^, buf.Size);
        buf.Clear;
      end;
    end;
    f.WriteBuffer(buf.Memory^, buf.Size);
  finally
    buf.Free;
    f.Free;
  end;
end;

{ About ABytes of RTF: a header with a Latin and a Chinese font, paragraphs of formatted words
  and Chinese as \uN, as Word and WordPad write them. }
procedure MakeRtf(const APath: string; ABytes: Int64);
var
  f: TFileStream;
  buf: TMemoryStream;
  n: Integer;
begin
  f := TFileStream.Create(APath, fmCreate);
  buf := TMemoryStream.Create;
  try
    WriteRaw(buf, '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fswiss\fcharset0 Arial;}' +
      '{\f1\fnil\fcharset134 SimSun;}}' + #13#10 + '{\colortbl ;\red200\green0\blue0;}' +
      #13#10 + '\viewkind4\uc1\pard\f0\fs20 ');
    n := 0;
    while f.Size + buf.Size < ABytes do
    begin
      Inc(n);
      WriteRaw(buf, 'Paragraph ' + IntToStr(n) + ' with \b bold\b0  and \cf1 coloured\cf0  words, ' +
        '\f1\u20013?\u25991?\u27979?\u35797?\f0  and more text.\par' + #13#10);
      if buf.Size > 1024 * 1024 then
      begin
        f.WriteBuffer(buf.Memory^, buf.Size);
        buf.Clear;
      end;
    end;
    WriteRaw(buf, '}' + #13#10);
    f.WriteBuffer(buf.Memory^, buf.Size);
  finally
    buf.Free;
    f.Free;
  end;
end;

{ RTF written with | for each backslash. }
function Bar(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  Result := S;
  UniqueString(Result);
  for i := 1 to Length(Result) do
    if Result[i] = '|' then Result[i] := #92;
end;

{ About ABytes of RTF with fields, as Word writes them: ALinks hyperlinks (two a paragraph, their
  results Chinese, underlined, coloured), a table of contents of AEntries entries (each a
  hyperlink holding its text, a tab with a dot leader and a page number field) after the first
  half of them, then plain paragraphs as MakeRtf's to the size. AFirstLinkPara: the first
  paragraph of links after the contents; ATocParas: where the contents' paragraphs are. }
procedure MakeFieldsRtf(const APath: string; ABytes: Int64; ALinks, AEntries: Integer;
  out ATocFirst, ATocLast, ALinkAfter: Integer);
var
  f: TFileStream;
  buf: TMemoryStream;
  n, i, para: Integer;

  procedure Spill;
  begin
    if buf.Size > 1024 * 1024 then
    begin
      f.WriteBuffer(buf.Memory^, buf.Size);
      buf.Clear;
    end;
  end;

  function Link(AN: Integer): RawByteString;
  begin
    Result := Bar('{|field{|*|fldinst HYPERLINK "http://example.com/page' + IntToStr(AN) +
      '"}{|fldrslt {|cs15|ul|cf1|f1 |u38142?|u25509?' + IntToStr(AN) + '}}}');
  end;

  procedure Links(ACount: Integer);
  var
    k: Integer;
  begin
    for k := 1 to ACount div 2 do
    begin
      Inc(n, 2);
      WriteRaw(buf, Bar('|pard|f0 Paragraph ' + IntToStr(para) + ' links to ') + Link(n - 1) +
        Bar(' and to ') + Link(n) + Bar(' with more words after them.|par') + #13#10);
      Inc(para);
      Spill;
    end;
  end;

begin
  f := TFileStream.Create(APath, fmCreate);
  buf := TMemoryStream.Create;
  try
    WriteRaw(buf, Bar('{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fswiss|fcharset0 Arial;}' +
      '{|f1|fnil|fcharset134 SimSun;}}' + #13#10 + '{|colortbl ;|red0|green0|blue255;}' +
      #13#10 + '|viewkind4|uc1|pard|f0|fs20 '));
    n := 0;
    para := 0;
    Links(ALinks div 2);
    // the contents: opened after text, closed before text
    ATocFirst := para;
    WriteRaw(buf, Bar('|pard|tqr|tldot|tx8000 Contents: {|field|fldedit{|*|fldinst TOC ||o "1-3" ||h}{|fldrslt '));
    for i := 1 to AEntries do
    begin
      WriteRaw(buf, Bar('{|field{|*|fldinst HYPERLINK ||l "_Toc' + IntToStr(i) + '"}{|fldrslt ' +
        '{|cs15|ul|cf1|f1 |u31532?' + IntToStr(i) + '|u31456? Chapter ' + IntToStr(i) + '|tab ' +
        '{|field{|*|fldinst PAGEREF _Toc' + IntToStr(i) + ' ||h}{|fldrslt ' + IntToStr(3 * i) + '}}}}}'));
      if i < AEntries then WriteRaw(buf, Bar('|par |pard|tqr|tldot|tx8000 ') + #13#10);
      Inc(para);
      Spill;
    end;
    WriteRaw(buf, Bar('}} and the text after it.|par') + #13#10);
    ATocLast := para - 1;
    ALinkAfter := para + 1;
    WriteRaw(buf, Bar('|pard|f0 The paragraph after the contents.|par') + #13#10);
    Inc(para);
    Links(ALinks - ALinks div 2);
    while f.Size + buf.Size < ABytes do
    begin
      WriteRaw(buf, Bar('|pard Paragraph ' + IntToStr(para) + ' with |b bold|b0  and |cf1 coloured|cf0  ' +
        'words, |f1|u20013?|u25991?|u27979?|u35797?|f0  and more text.|par') + #13#10);
      Inc(para);
      Spill;
    end;
    WriteRaw(buf, '}' + #13#10);
    f.WriteBuffer(buf.Memory^, buf.Size);
  finally
    buf.Free;
    f.Free;
  end;
end;

{ About ABytes of RTF whose body is ANest fields, one in the other's result (INCLUDETEXT, as
  Word writes a document included in another), around plain paragraphs; a paragraph before
  them and one after. ANest 0: the same paragraphs without a field. }
procedure MakeWrappedRtf(const APath: string; ABytes: Int64; ANest: Integer);
var
  f: TFileStream;
  buf: TMemoryStream;
  n, k: Integer;
begin
  f := TFileStream.Create(APath, fmCreate);
  buf := TMemoryStream.Create;
  try
    WriteRaw(buf, '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fnil\fcharset134 SimSun;}}' + #13#10 +
      '\pard intro\par' + #13#10);
    for k := 1 to ANest do
      WriteRaw(buf, '{\field{\*\fldinst INCLUDETEXT "part' + IntToStr(k) + '.rtf"}{\fldrslt ');
    n := 0;
    while f.Size + buf.Size < ABytes do
    begin
      Inc(n);
      WriteRaw(buf, '\pard line ' + IntToStr(n) + ' of the included text, written to have some ' +
        'length to it\par' + #13#10);
      if buf.Size > 1024 * 1024 then
      begin
        f.WriteBuffer(buf.Memory^, buf.Size);
        buf.Clear;
      end;
    end;
    for k := 1 to ANest do WriteRaw(buf, '}}');
    WriteRaw(buf, '\pard tail\par}' + #13#10);
    f.WriteBuffer(buf.Memory^, buf.Size);
  finally
    buf.Free;
    f.Free;
  end;
end;

function WorkingSetMB: Double;
{$IFDEF MSWINDOWS}
var
  m: TTyPerfMemCounters;
begin
  FillChar(m, SizeOf(m), 0);
  m.cb := SizeOf(m);
  if GetProcessMemoryInfo(GetCurrentProcess, m, SizeOf(m)) then
    Result := m.WorkingSetSize / (1024 * 1024)
  else
    Result := 0;
end;
{$ELSE}
begin
  Result := 0;
end;
{$ENDIF}

{ The files of a run that was killed (the gate's time limit) are left behind; a run sweeps
  those older than a day at its start (a run going on at the same time keeps its own). }
procedure SweepOldFiles;
var
  dir: string;
  sr: TSearchRec;
begin
  dir := IncludeTrailingPathDelimiter(GetTempDir(False));
  if FindFirst(dir + 'tyrichperf-*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Attr and faDirectory = 0) and (FileDateToDateTime(sr.Time) < Now - 1) then
        DeleteFile(dir + sr.Name);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;

procedure TTyRichEditPerfTest.SetUp;
begin
  SweepOldFiles;
  FFiles := TStringList.Create;
  FCtl := TTyStyleController.Create(nil);
  FRich := TPerfRich.Create(nil);
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 1200, 900);
end;

procedure TTyRichEditPerfTest.TearDown;
var
  i: Integer;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
  // the big files go whatever happened
  for i := 0 to FFiles.Count - 1 do
    if FileExists(FFiles[i]) then DeleteFile(FFiles[i]);
  FreeAndNil(FFiles);
end;

function TTyRichEditPerfTest.NewFile(const AExt: string): string;
var
  g: TGUID;
begin
  CreateGUID(g);
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyrichperf-' +
    IntToStr(GetProcessID) + '-' + Copy(GUIDToString(g), 2, 8) + AExt;
  FFiles.Add(Result);
end;

procedure TTyRichEditPerfTest.CheckRoom;
var
  avail: Int64;
{$IFDEF MSWINDOWS}
  total, freeBytes, room: QWord;
{$ENDIF}
begin
  avail := -1;
  {$IFDEF MSWINDOWS}
  if GetDiskFreeSpaceExW(PWideChar(UnicodeString(GetTempDir(False))), room, total, freeBytes) then
    avail := room;
  {$ELSE}
  {$IFDEF UNIX}
  // the RTL's DiskFree takes a "drive" number: AddDisk gives the temporary folder one
  avail := DiskFree(AddDisk(GetTempDir(False)));
  {$ENDIF}
  {$ENDIF}
  // (-1: not known - the file's own write then fails without the room)
  if (avail >= 0) and (avail < CRoomNeeded) then
    Ignore(Format('needs %d MB free in the temporary folder, %d MB there',
      [CRoomNeeded div (1024 * 1024), avail div (1024 * 1024)]));
end;

procedure TTyRichEditPerfTest.Report(const AWhat: string; AMs: Double);
begin
  WriteLn(Format('TTyRichEditPerfTest: %s: %.1f ms', [AWhat, AMs]));
end;

function TTyRichEditPerfTest.Keystroke(ABitmap: TBitmap; AAtEnd: Boolean): Double;
var
  t0: Double;
  p, depth: Integer;
  at: TTyRichPos;
  t: TTyRichText;
begin
  t := FRich.Document.Text;
  // in the middle: a line of the screen; at the end: the document's last line
  if AAtEnd then p := t.ParaCount - 1 else p := FRich.TopParagraph + 2;
  if p >= t.ParaCount then p := t.ParaCount - 1;
  at := t.ParaStart(p) + Math.Min(Int64(3), t.ParaLength(p));
  FRich.SelStart := at;
  TPerfRich(FRich).PaintInto(ABitmap);
  depth := FRich.Document.UndoDepth;
  t0 := Clock;
  TPerfRich(FRich).TypeChar('x');
  TPerfRich(FRich).PaintInto(ABitmap);
  Result := Clock - t0;
  // the key changed the document (a refused or filtered one would time a blit)
  AssertEquals('the key typed its character', 'x', string(t.GetText(at, 1)));
  AssertEquals('one more undo step', depth + 1, FRich.Document.UndoDepth);
end;

{ A 100 MB txt: LoadFromFile to the end of the first paint within 3 s; then the scroll position
  set to the middle of the document and painted within 300 ms; then a character typed there,
  and one at the end (after Ctrl+End), each from the key to the end of its paint within 90 ms. }
procedure TTyRichEditPerfTest.TestA100MBTextFileFirstScreenAndMiddle;
var
  path: string;
  bmp: TBitmap;
  t0, first, middle, keyMid, keyEnd: Double;
begin
  CheckRoom;
  path := NewFile('.txt');
  MakeText(path, CFileBytes);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    t0 := Clock;
    FRich.LoadFromFile(path);
    TPerfRich(FRich).PaintInto(bmp);
    first := Clock - t0;
    Report(Format('txt %d MB, %d paragraphs: load and first paint - a warm read: the file was ' +
      'just written and is in the system''s cache', [SizeOfFile(path) div (1024 * 1024),
      FRich.Document.Text.ParaCount]), first);
    WriteLn('TTyRichEditPerfTest: txt: peak working set after the load: ' + PeakWorkingSet);
    t0 := Clock;
    FRich.ScrollY := FRich.Document.Text.TotalHeight div 2;
    TPerfRich(FRich).PaintInto(bmp);
    middle := Clock - t0;
    Report('txt: the middle set and painted', middle);
    AssertTrue('the view is in the middle', FRich.TopParagraph > FRich.Document.Text.ParaCount div 4);
    // a key in the middle, and at the end (Ctrl+End and its paint not timed)
    keyMid := Keystroke(bmp, False);
    Report('txt: a character typed in the middle, to the end of its paint', keyMid);
    TPerfRich(FRich).Key(VK_END, [ssCtrl]);
    keyEnd := Keystroke(bmp, True);
    Report('txt: a character typed at the end, to the end of its paint', keyEnd);
    AssertTrue(Format('the first screen in %.0f ms', [first]), first <= CFirstScreenMs);
    AssertTrue(Format('the middle in %.0f ms', [middle]), middle <= CScrollMs);
    AssertTrue(Format('a key in the middle in %.1f ms', [keyMid]), keyMid <= CKeystrokeMs);
    AssertTrue(Format('a key at the end in %.1f ms', [keyEnd]), keyEnd <= CKeystrokeMs);
    AssertTrue('typed at the end', FRich.TopParagraph > FRich.Document.Text.ParaCount - 200);
  finally
    bmp.Free;
  end;
end;

{ A 100 MB RTF, the lazy path: LoadFromFile (the first slice indexed) to the end of the first
  paint within 3 s. Then, the load still going on, the scroll position set to the middle of what
  is indexed so far - half the height of the paragraphs the load has appended until then - and
  painted within 300 ms. Last (printed, and held to the same 300 ms), the rest of the file
  indexed (not timed) and the middle of the whole document. Then a character typed in that
  middle and one at the end (after Ctrl+End), each within 90 ms from the key to the end of its
  paint, the one at the end parsing no more than a megabyte of the file. }
procedure TTyRichEditPerfTest.TestA100MBRtfFileFirstScreenAndMiddle;
var
  path: string;
  bmp: TBitmap;
  t0, first, middle, whole, keyMid, keyEnd: Double;
  loading: Boolean;
  indexed, midTop: Integer;
  parsed: Int64;
begin
  CheckRoom;
  path := NewFile('.rtf');
  MakeRtf(path, CFileBytes);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    t0 := Clock;
    FRich.LoadFromFile(path);
    TPerfRich(FRich).PaintInto(bmp);
    first := Clock - t0;
    loading := FRich.Loading;
    Report(Format('rtf %d MB: load (first slice, %d paragraphs) and first paint - a warm read: ' +
      'the file was just written and is in the system''s cache',
      [SizeOfFile(path) div (1024 * 1024), FRich.Document.Text.ParaCount]), first);
    WriteLn('TTyRichEditPerfTest: rtf: peak working set after the first slice: ' + PeakWorkingSet);
    t0 := Clock;
    FRich.ScrollY := FRich.Document.Text.TotalHeight div 2;
    TPerfRich(FRich).PaintInto(bmp);
    middle := Clock - t0;
    // (asked before the load goes on: the paragraphs indexed when the view was set)
    indexed := FRich.Document.Text.ParaCount;
    midTop := FRich.TopParagraph;
    Report('rtf: the middle of what is indexed set and painted, the load going on', middle);
    t0 := Clock;
    FRich.FinishLoading;
    Report(Format('rtf: the rest indexed (%d paragraphs; not asserted)',
      [FRich.Document.Text.ParaCount]), Clock - t0);
    WriteLn('TTyRichEditPerfTest: rtf: peak working set after the whole load: ' + PeakWorkingSet);
    t0 := Clock;
    FRich.ScrollY := FRich.Document.Text.TotalHeight div 2;
    TPerfRich(FRich).PaintInto(bmp);
    whole := Clock - t0;
    Report('rtf: the middle of the whole document set and painted', whole);
    // a key in the middle and at the end of the loaded file (parsed on demand)
    keyMid := Keystroke(bmp, False);
    Report('rtf: a character typed in the middle, to the end of its paint', keyMid);
    TPerfRich(FRich).Key(VK_END, [ssCtrl]);
    TPerfRich(FRich).PaintInto(bmp);
    parsed := TyRichRtfLoadOf(FRich.Document).ParsedBytes;
    keyEnd := Keystroke(bmp, True);
    parsed := TyRichRtfLoadOf(FRich.Document).ParsedBytes - parsed;
    Report(Format('rtf: a character typed at the end, to the end of its paint (%d bytes of ' +
      'the file parsed for it)', [parsed]), keyEnd);
    AssertTrue(Format('a key in the middle in %.1f ms', [keyMid]), keyMid <= CKeystrokeMs);
    AssertTrue(Format('a key at the end in %.1f ms', [keyEnd]), keyEnd <= CKeystrokeMs);
    AssertTrue(Format('the key at the end parsed %d bytes', [parsed]), parsed <= 1024 * 1024);
    AssertTrue('typed at the end', FRich.TopParagraph > FRich.Document.Text.ParaCount - 200);
    AssertTrue('the load was still going on at the first paint', loading);
    AssertTrue(Format('the first screen in %.0f ms', [first]), first <= CFirstScreenMs);
    AssertTrue(Format('the middle in %.0f ms', [middle]), middle <= CScrollMs);
    AssertTrue(Format('the middle of the whole in %.0f ms', [whole]), whole <= CScrollMs);
    AssertTrue(Format('the view in the middle of what was indexed (paragraph %d of %d)',
      [midTop, indexed]), midTop > indexed div 4);
    AssertTrue('the view in the middle of the whole',
      FRich.TopParagraph > FRich.Document.Text.ParaCount div 4);
  finally
    bmp.Free;
  end;
end;

{ A 100 MB RTF of fields - 200,000 hyperlinks with Chinese results and a table of contents of
  5,000 entries among plain paragraphs: LoadFromFile to the end of the first paint within 3 s;
  once loaded, a jump to the middle of the contents and one to the end, each set and painted
  within 300 ms; a character typed right before a link, and one in the paragraph after the
  contents, each from the key to the end of its paint within 90 ms. Printed: those, the rest
  of the index, the peak working set. }
procedure TTyRichEditPerfTest.TestA100MBRtfOfFieldsFirstScreenContentsAndKeys;
var
  path: string;
  bmp: TBitmap;
  t0, first, mid, last, keyLink, keyAfter: Double;
  tocFirst, tocLast, linkAfter, p, depth: Integer;
  at: TTyRichPos;
  t: TTyRichText;
begin
  CheckRoom;
  path := NewFile('.rtf');
  MakeFieldsRtf(path, CFileBytes, 200000, 5000, tocFirst, tocLast, linkAfter);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    t0 := Clock;
    FRich.LoadFromFile(path);
    TPerfRich(FRich).PaintInto(bmp);
    first := Clock - t0;
    Report(Format('rtf of fields %d MB: load (first slice, %d paragraphs) and first paint',
      [SizeOfFile(path) div (1024 * 1024), FRich.Document.Text.ParaCount]), first);
    t0 := Clock;
    FRich.FinishLoading;
    Report(Format('rtf of fields: the rest indexed (%d paragraphs; not asserted)',
      [FRich.Document.Text.ParaCount]), Clock - t0);
    t := FRich.Document.Text;
    // the middle of the contents: the view put there and painted
    p := (tocFirst + tocLast) div 2;
    t0 := Clock;
    FRich.SelStart := t.ParaStart(p) + 3;
    FRich.ScrollCaretIntoView;
    TPerfRich(FRich).PaintInto(bmp);
    mid := Clock - t0;
    Report(Format('rtf of fields: a jump to the middle of the contents (paragraph %d)', [p]), mid);
    AssertTrue(Format('the view at the contents'' middle (paragraph %d)', [FRich.TopParagraph]),
      Abs(FRich.TopParagraph - p) < 100);
    t0 := Clock;
    TPerfRich(FRich).Key(VK_END, [ssCtrl]);
    TPerfRich(FRich).PaintInto(bmp);
    last := Clock - t0;
    Report('rtf of fields: a jump to the end', last);
    AssertTrue('the view at the end', FRich.TopParagraph > t.ParaCount - 200);
    // a key right before a link: the link's open mark is the first object of its paragraph
    p := linkAfter + 10;
    at := t.ParaStart(p);
    while FRich.Document.ObjectAt(at) = nil do Inc(at);
    FRich.SelStart := at;
    FRich.ScrollCaretIntoView;
    TPerfRich(FRich).PaintInto(bmp);
    depth := FRich.Document.UndoDepth;
    t0 := Clock;
    TPerfRich(FRich).TypeChar('x');
    TPerfRich(FRich).PaintInto(bmp);
    keyLink := Clock - t0;
    AssertEquals('typed before the link', depth + 1, FRich.Document.UndoDepth);
    Report('rtf of fields: a character typed right before a link, to the end of its paint', keyLink);
    // in the paragraph after the contents
    at := t.ParaStart(tocLast + 1) + 3;
    FRich.SelStart := at;
    FRich.ScrollCaretIntoView;
    TPerfRich(FRich).PaintInto(bmp);
    depth := FRich.Document.UndoDepth;
    t0 := Clock;
    TPerfRich(FRich).TypeChar('y');
    TPerfRich(FRich).PaintInto(bmp);
    keyAfter := Clock - t0;
    AssertEquals('typed after the contents', depth + 1, FRich.Document.UndoDepth);
    Report('rtf of fields: a character typed in the paragraph after the contents, to the end of its paint',
      keyAfter);
    WriteLn('TTyRichEditPerfTest: rtf of fields: peak working set: ' + PeakWorkingSet);
    AssertTrue(Format('the first screen in %.0f ms', [first]), first <= CFirstScreenMs);
    AssertTrue(Format('the contents'' middle in %.0f ms', [mid]), mid <= CScrollMs);
    AssertTrue(Format('the end in %.0f ms', [last]), last <= CScrollMs);
    AssertTrue(Format('a key before a link in %.1f ms', [keyLink]), keyLink <= CKeystrokeMs);
    AssertTrue(Format('a key after the contents in %.1f ms', [keyAfter]), keyAfter <= CKeystrokeMs);
  finally
    bmp.Free;
  end;
end;

{ A table of 10,000 rows of two cells: Tab in its middle, from the key to the end of its
  paint, within 90 ms (a move: no table is walked); the first answer of the table actions'
  Can... functions after that move within 90 ms too (each walks the caret's table once), and
  a second one (from what the first found); Down and the six answers, twenty times (a move
  inside the table reads it no more), each within 90 ms. Printed: those, and a row added by
  Tab in the table's last cell (the engine's row edit reads the table: not asserted). }
{ A picture of 20 MB in the middle of a 100 MB document, shown reduced, selected and resized
  by a drag of a handle: from the release to the end of its paint within 90 ms, nothing decoded
  for it (the pixels at hand stand in) and one undo step more; then the background work makes
  its image at the new size - one decode - and ends (printed, not asserted: its time). }
procedure TTyRichEditPerfTest.TestAPictureResizedInALargeDocument;
var
  path: string;
  bmp: TBitmap;
  data: TBytes;
  pic: TTyRichPicture;
  at: TTyRichPos;
  c: TPoint;
  t0, release, sharp: Double;
  decodes: Int64;
  depth, steps: Integer;
begin
  CheckRoom;
  path := NewFile('.txt');
  MakeText(path, CFileBytes);
  data := NoisePng(2800, 2500);
  AssertTrue(Format('a picture of 20 MB (%d bytes)', [Length(data)]), Length(data) >= 20 * 1000 * 1000);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.LoadFromFile(path);
    FRich.PlainText := False;
    FRich.ScrollY := FRich.Document.Text.TotalHeight div 2;
    TPerfRich(FRich).PaintInto(bmp);
    // in the paragraph at the view's top, shown at 480 x 429 pixels (reduced)
    at := FRich.Document.Text.ParaStart(FRich.TopParagraph + 1);
    pic := TTyRichPicture.Create(rpfPng, data, 7200, 6430);
    AssertTrue('the picture goes in', FRich.Document.Execute(TTyRichInsertObject.Create(at, pic)));
    TPerfRich(FRich).PaintInto(bmp);
    steps := 0;
    while TPerfRich(FRich).Step and (steps < 20) do Inc(steps);
    FRich.SelStart := at;
    FRich.SelLength := 1;
    TPerfRich(FRich).PaintInto(bmp);
    AssertTrue('the picture shows its handles', TPerfRich(FRich).HandleCentre(rhBottomRight, c));
    decodes := FRich.Layouter.PictureDecodes;
    AssertTrue('decoded before the resize', decodes >= 1);
    depth := FRich.Document.UndoDepth;
    TPerfRich(FRich).Press(c.X, c.Y);
    TPerfRich(FRich).MoveTo(c.X - 60, c.Y - 40);
    TPerfRich(FRich).PaintInto(bmp);
    t0 := Clock;
    TPerfRich(FRich).Release(c.X - 60, c.Y - 40);
    TPerfRich(FRich).PaintInto(bmp);
    release := Clock - t0;
    Report(Format('a %d MB picture in a 100 MB document resized: the release to the end of its ' +
      'paint', [Length(data) div (1024 * 1024)]), release);
    AssertEquals('one undo step more', depth + 1, FRich.Document.UndoDepth);
    AssertEquals('nothing decoded for the release', decodes, FRich.Layouter.PictureDecodes);
    // its own image at the new size: decoded once in the background, and the work ends
    steps := 0;
    t0 := Clock;
    while TPerfRich(FRich).Step and (steps < 20) do Inc(steps);
    TPerfRich(FRich).PaintInto(bmp);
    sharp := Clock - t0;
    Report('the background work that makes its image at the new size, and the paint after it ' +
      '(not asserted)', sharp);
    AssertEquals('decoded once in the background', decodes + 1, FRich.Layouter.PictureDecodes);
    AssertTrue('the background work ended', steps < 20);
    AssertFalse('nothing left to do', TPerfRich(FRich).Step);
    AssertTrue(Format('the release in %.1f ms', [release]), release <= CKeystrokeMs);
  finally
    bmp.Free;
  end;
end;

{ The selection dragged in a 100 MB txt: every move of the pointer (the place, the drop mark,
  the cursor) to the end of its paint within 90 ms - forty moves across the view and twenty
  ticks of the edge scrolling past its bottom -, then the release (a move of a line, to the
  end of its paint). Then, through the commands, a move and a copy of 1 MB and of 50 MB of the
  text inside the document, each with its undo (printed, not asserted: a huge drop may take
  long, as a paste of that much does): no text copied (the add buffer grows by a few bytes at
  most, asserted). }
procedure TTyRichEditPerfTest.TestDraggingTheSelectionInALargeDocument;
var
  path: string;
  bmp: TBitmap;
  t: TTyRichText;
  d: TTyRichDocument;
  k, i, y: Integer;
  a, at: TTyRichPos;
  r, r2: TRect;
  t0, one, worst, total, release: Double;
  added: Int64;
  sizes: array[0..1] of Int64;

  procedure Transfer(const AWhat: string; ACmd: TTyRichCommand; ASize: Int64);
  var
    t1, run, back: Double;
    add0: Int64;
  begin
    add0 := t.AddedBytes;
    t1 := Clock;
    AssertTrue(AWhat + ' runs', d.Execute(ACmd));
    TPerfRich(FRich).PaintInto(bmp);
    run := Clock - t1;
    AssertTrue(AWhat + ': no text copied', t.AddedBytes - add0 <= 8);
    t1 := Clock;
    d.Undo;
    TPerfRich(FRich).PaintInto(bmp);
    back := Clock - t1;
    Report(Format('%s of %d Mi characters of a 100 MB txt, to the end of its paint (not asserted)',
      [AWhat, ASize div (1024 * 1024)]), run);
    Report(Format('its undo (not asserted)', []), back);
  end;

begin
  CheckRoom;
  path := NewFile('.txt');
  MakeText(path, CFileBytes);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.LoadFromFile(path);
    d := FRich.Document;
    t := d.Text;
    FRich.ScrollY := t.TotalHeight div 2;
    TPerfRich(FRich).PaintInto(bmp);
    // the third line of the view, its first ten characters selected
    k := FRich.TopParagraph + 2;
    a := t.ParaStart(k);
    FRich.SelStart := a;
    FRich.SelLength := 10;
    TPerfRich(FRich).PaintInto(bmp);
    r := FRich.PositionRect(a + 2);
    r2 := FRich.PositionRect(a + 3);
    TPerfRich(FRich).Press((r.Left + r2.Left) div 2, (r.Top + r.Bottom) div 2);
    TPerfRich(FRich).MoveTo((r.Left + r2.Left) div 2, r.Bottom + 20);
    AssertTrue('the drag began', FRich.DropActive);
    worst := 0;
    total := 0;
    for i := 0 to 39 do
    begin
      y := 60 + i * 15;
      t0 := Clock;
      TPerfRich(FRich).MoveTo(200 + (i mod 7) * 40, y);
      TPerfRich(FRich).PaintInto(bmp);
      one := Clock - t0;
      total := total + one;
      if one > worst then worst := one;
    end;
    Report('a drag across the view: a move to the end of its paint, the average of 40', total / 40);
    Report('a drag across the view: the slowest move of 40', worst);
    // past the bottom edge: the view scrolls at every tick
    TPerfRich(FRich).MoveTo(300, FRich.Height + 30);
    total := 0;
    for i := 0 to 19 do
    begin
      t0 := Clock;
      TPerfRich(FRich).DragTick;
      TPerfRich(FRich).PaintInto(bmp);
      one := Clock - t0;
      total := total + one;
      if one > worst then worst := one;
    end;
    Report('the edge scrolling: a tick to the end of its paint, the average of 20', total / 20);
    TPerfRich(FRich).MoveTo(300, FRich.Height - 100);
    TPerfRich(FRich).PaintInto(bmp);
    added := t.AddedBytes;
    t0 := Clock;
    TPerfRich(FRich).Release(300, FRich.Height - 100);
    TPerfRich(FRich).PaintInto(bmp);
    release := Clock - t0;
    Report('the release: ten characters moved, to the end of its paint', release);
    AssertEquals('one step', 1, d.UndoDepth);
    AssertTrue('the drop copied no text', t.AddedBytes - added <= 8);
    d.Undo;
    d.ClearUndo;
    AssertTrue(Format('every move within %.1f ms', [worst]), worst <= CKeystrokeMs);
    AssertTrue(Format('the release in %.1f ms', [release]), release <= CKeystrokeMs);
    // 1 MB and 50 MB of the text moved and copied, from a quarter of the document to its
    // three quarters
    sizes[0] := 1024 * 1024;
    sizes[1] := 50 * 1024 * 1024;
    for i := 0 to 1 do
    begin
      a := t.ParaStart(t.ParaOfPos(t.Length div 8));
      at := t.ParaStart(t.ParaOfPos(a + sizes[i] + t.Length div 8));
      Transfer('a move', TTyRichMove.Create(a, sizes[i], at), sizes[i]);
      Transfer('a copy', TTyRichCopy.Create(a, sizes[i], at), sizes[i]);
    end;
    WriteLn('TTyRichEditPerfTest: drag: peak working set: ' + PeakWorkingSet);
  finally
    bmp.Free;
  end;
end;

procedure TTyRichEditPerfTest.TestTabAndTheTableAnswersInALongTable;
const
  Rows = 10000;
var
  bmp: TBitmap;
  d: TTyRichDocument;
  t: TTyRichText;
  k: Integer;
  t0, tab, first, again, add, move, total, worst: Double;
  i: Integer;
  info: TTyRichTableInfo;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.WantTabs := True;
    FRich.Lines.Text := 'before' + LineEnding + 'after';
    d := FRich.Document;
    t := d.Text;
    AssertTrue('a long table', d.Execute(TTyRichInsertTable.Create(t.ParaStart(1), Rows, 2)));
    k := 1 + 2 * (Rows div 2);
    FRich.SelStart := t.ParaStart(k);
    TPerfRich(FRich).PaintInto(bmp);
    t0 := Clock;
    TPerfRich(FRich).Key(VK_TAB, []);
    TPerfRich(FRich).PaintInto(bmp);
    tab := Clock - t0;
    AssertEquals('Tab went to the next cell', t.ParaStart(k + 1), FRich.SelStart);
    Report(Format('table of %d rows: Tab in the middle, to the end of its paint', [Rows]), tab);
    t0 := Clock;
    AssertTrue('a row, a column', FRich.CanInsertRow and FRich.CanInsertColumn and
      FRich.CanDeleteRow and FRich.CanDeleteColumn and FRich.CanDeleteTable and
      not FRich.CanInsertTable);
    first := Clock - t0;
    Report('table: the Can... answers after a move, the first time', first);
    t0 := Clock;
    AssertTrue('again', FRich.CanInsertRow and FRich.CanInsertColumn and
      FRich.CanDeleteRow and FRich.CanDeleteColumn and FRich.CanDeleteTable);
    again := Clock - t0;
    Report('table: the Can... answers asked again', again);
    // Down, then the six answers an action list's idle asks: a move inside the table
    total := 0;
    worst := 0;
    for i := 1 to 20 do
    begin
      t0 := Clock;
      TPerfRich(FRich).Key(VK_DOWN, []);
      FRich.CanInsertRow;
      FRich.CanInsertColumn;
      FRich.CanDeleteRow;
      FRich.CanDeleteColumn;
      FRich.CanDeleteTable;
      FRich.CanInsertTable;
      move := Clock - t0;
      total := total + move;
      if move > worst then worst := move;
    end;
    Report('table: Down and the six answers, the average of 20', total / 20);
    Report('table: Down and the six answers, the slowest of 20', worst);
    // the last cell: a row below, through the user's door
    FRich.SelStart := t.ParaStart(2 * Rows);
    TPerfRich(FRich).PaintInto(bmp);
    t0 := Clock;
    TPerfRich(FRich).Key(VK_TAB, []);
    TPerfRich(FRich).PaintInto(bmp);
    add := Clock - t0;
    AssertTrue('a row added', d.TableInfoAt(1, info) and (info.RowCount = Rows + 1));
    Report('table: Tab in the last cell adds a row, to the end of its paint (not asserted)', add);
    AssertTrue(Format('Tab in %.1f ms', [tab]), tab <= CKeystrokeMs);
    AssertTrue(Format('the first answers in %.1f ms', [first]), first <= CKeystrokeMs);
    AssertTrue(Format('the answers again in %.1f ms', [again]), again <= CKeystrokeMs);
    AssertTrue(Format('Down and the answers in %.1f ms at most', [worst]), worst <= CKeystrokeMs);
  finally
    bmp.Free;
  end;
end;

{ Another program's drop of a large RTF (the Windows widgetset's drop target, fed a data object
  of the test's in this process): 10 MB and 100 MB, from the drop to the end of its paint - a
  paste of it, read the paste's way (the data object's block copied once into a string, as
  the clipboard's is). Printed, not asserted: a paste of that much has no line of its own; the
  10 MB one is pasted too (from a stand-in clipboard), as the yardstick. The peak working set
  includes the data object's own copies (its string and the block it hands over: what the
  other program holds). The 100 MB drop (half a minute, more than a gigabyte at its peak)
  runs only when the environment variable TY_PERF_LARGE_DROP is 1. }
procedure TTyRichEditPerfTest.TestDroppingALargeRtfFromAnotherProgram;
{$IFDEF LCLWin32}
const
  Sizes: array[0..1] of Int64 = (10 * 1024 * 1024, 100 * 1024 * 1024);
var
  bmp: TBitmap;
  data: TTestData;
  keep: IUnknown;
  rtf: RawByteString;
  ms: TMemoryStream;
  s: RawByteString;
  k, n: Integer;
  len0: Int64;
  t0: Double;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    for k := 0 to High(Sizes) do
    begin
      if (k > 0) and (GetEnvironmentVariable('TY_PERF_LARGE_DROP') <> '1') then Break;
      FRich.Lines.Text := 'start';
      TPerfRich(FRich).PaintInto(bmp);
      ms := TMemoryStream.Create;
      try
        s := '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Arial;}}' + #13#10 + '\pard\f0\fs20 ';
        ms.WriteBuffer(s[1], Length(s));
        n := 0;
        while ms.Size < Sizes[k] do
        begin
          s := 'Paragraph ' + IntToStr(n) + ' of the dropped text, with \b some\b0  words.\par' + #13#10;
          ms.WriteBuffer(s[1], Length(s));
          Inc(n);
        end;
        s := '}';
        ms.WriteBuffer(s[1], 1);
        SetLength(rtf, ms.Size);
        Move(ms.Memory^, rtf[1], ms.Size);
      finally
        ms.Free;
      end;
      // (the smaller one pasted too, from a stand-in clipboard: what the drop is held against)
      if k = 0 then
      begin
        TPerfRich(FRich).ClipRtf := rtf;
        FRich.SelStart := FRich.Document.Text.Length;
        t0 := Clock;
        FRich.PasteFromClipboard;
        TPerfRich(FRich).PaintInto(bmp);
        Report(Format('a paste of the same %d MB of RTF, to the end of its paint (not asserted)',
          [Sizes[k] div (1024 * 1024)]), Clock - t0);
        TPerfRich(FRich).ClipRtf := '';
        AssertTrue('pasted', FRich.Document.Text.Length > n);
        FRich.Lines.Text := 'start';
        TPerfRich(FRich).PaintInto(bmp);
      end;
      data := NewRtfData(rtf);
      keep := data as IUnknown;
      rtf := '';
      len0 := FRich.Document.Text.Length;
      AssertEquals('a copy', 1, OleEnterWith(TPerfRich(FRich).DropTarget, data, Point(10, 10)));
      t0 := Clock;
      AssertEquals('dropped: a copy', 1, OleDropWith(TPerfRich(FRich).DropTarget, data,
        Point(10, 10)));
      TPerfRich(FRich).PaintInto(bmp);
      Report(Format('a drop of %d MB of RTF from another program (%d paragraphs), to the end ' +
        'of its paint (not asserted)', [Sizes[k] div (1024 * 1024), n]), Clock - t0);
      WriteLn('TTyRichEditPerfTest: drop: peak working set after ' + IntToStr(Sizes[k] div
        (1024 * 1024)) + ' MB: ' + PeakWorkingSet);
      AssertTrue('it went in', FRich.Document.Text.Length > len0 + n);
      AssertEquals('one step', 1, FRich.Document.UndoDepth);
      AssertEquals('read once', 1, data.RtfGets);
      keep := nil;
      FRich.Document.ClearUndo;
    end;
  finally
    bmp.Free;
  end;
end;
{$ELSE}
begin
  Ignore('drops from other programs are the Windows widgetset''s');
end;
{$ENDIF}

{ One field (INCLUDETEXT) around a 100 MB file: LoadFromFile to the end of the first paint
  within 1 s; once the whole file is indexed and the first paragraphs' interval sent back to
  unparsed (two intervals kept, two others read), the first paragraphs read again within
  100 ms - the field's verdict and its bytes are not paid for again. }
procedure TTyRichEditPerfTest.TestOneFieldAroundA100MBRtf;
var
  path: string;
  bmp: TBitmap;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  t0, first, again: Double;
  n, parses: Integer;
begin
  CheckRoom;
  path := NewFile('.rtf');
  MakeWrappedRtf(path, CFileBytes, 1);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    t0 := Clock;
    FRich.LoadFromFile(path);
    TPerfRich(FRich).PaintInto(bmp);
    first := Clock - t0;
    Report(Format('one field around %d MB: load (first slice) and first paint',
      [SizeOfFile(path) div (1024 * 1024)]), first);
    t0 := Clock;
    FRich.FinishLoading;
    Report(Format('one field: the rest indexed (%d paragraphs; not asserted)',
      [FRich.Document.Text.ParaCount]), Clock - t0);
    d := FRich.Document;
    load := TyRichRtfLoadOf(d);
    load.MaxResidentIntervals := 2;
    n := d.Text.ParaCount;
    d.RunsOf(n div 2);
    d.RunsOf(n div 2 + 5000);
    d.RunsOf(n div 2 + 10000);
    parses := load.ParseCount;
    t0 := Clock;
    d.RunsOf(0);
    d.RunsOf(1);
    again := Clock - t0;
    Report('one field: the first paragraphs read again, their interval parsed again', again);
    AssertTrue('their interval was parsed again', load.ParseCount > parses);
    AssertEquals('the next paragraph inside the field', 1, d.ParaFieldDepth(2));
    AssertTrue(Format('the first screen in %.0f ms', [first]), first <= 1000);
    AssertTrue(Format('the first paragraphs again in %.0f ms', [again]), again <= 100);
  finally
    bmp.Free;
  end;
end;

{ Fields nested eight deep around 30 MB: LoadFromFile to the end of the first paint within
  1 s, and what reading the first screen's paragraphs adds to the working set after the load's
  first slice is a few MB (16 at most) - not a copy of each field's group. }
procedure TTyRichEditPerfTest.TestFieldsEightDeepAround30MB;
var
  path: string;
  bmp: TBitmap;
  t0, first, before, after: Double;
  k: Integer;
begin
  CheckRoom;
  path := NewFile('.rtf');
  MakeWrappedRtf(path, 30 * 1024 * 1024, 8);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    t0 := Clock;
    FRich.LoadFromFile(path);
    // (what the first screen's paragraphs take, apart from what a paint takes whatever the
    // file: they are read first)
    before := WorkingSetMB;
    for k := 0 to 59 do FRich.Document.RunsOf(k);
    after := WorkingSetMB;
    TPerfRich(FRich).PaintInto(bmp);
    first := Clock - t0;
    Report(Format('eight fields deep around %d MB: load (first slice) and first paint',
      [SizeOfFile(path) div (1024 * 1024)]), first);
    WriteLn(Format('TTyRichEditPerfTest: eight deep: working set %.0f MB after the first slice, ' +
      '%.0f MB after the first screen''s paragraphs were read', [before, after]));
    AssertEquals('eight fields open on the first screen', 8, FRich.Document.ParaFieldDepth(2));
    // (memory first: a machine too slow for the time line still checks it)
    AssertTrue(Format('the first screen''s paragraphs added %.0f MB', [after - before]),
      after - before <= 16);
    AssertTrue(Format('the first screen in %.0f ms', [first]), first <= 1000);
  finally
    bmp.Free;
  end;
end;

{ The whole parse of 8 MB of paragraphs inside fields nested eight deep, against the same
  paragraphs with no field: in time linear in the file, close to the other's - a quarter more
  and 100 ms at most (each field's group is read once more, by the one pass that decides them
  all). }
procedure TTyRichEditPerfTest.TestTheWholeParseOfFieldsEightDeepIsLinear;
var
  paths: array[0..1] of string;
  times: array[0..1] of Double;
  i, k: Integer;
  d: TTyRichDocument;
  s: TFileStream;
  t0, best: Double;
begin
  CheckRoom;
  for i := 0 to 1 do
  begin
    paths[i] := NewFile('.rtf');
    MakeWrappedRtf(paths[i], 8 * 1024 * 1024, 8 * i);
    best := 1e12;
    for k := 1 to 2 do
    begin
      d := TTyRichDocument.Create;
      s := TFileStream.Create(paths[i], fmOpenRead or fmShareDenyWrite);
      try
        t0 := Clock;
        TyRichLoadRtfFull(d, s);
        if Clock - t0 < best then best := Clock - t0;
      finally
        s.Free;
        d.Free;
      end;
    end;
    times[i] := best;
  end;
  Report('8 MB of paragraphs, no field: the whole parse', times[0]);
  Report('8 MB of paragraphs in fields eight deep: the whole parse', times[1]);
  AssertTrue(Format('eight deep in %.0f ms, none in %.0f ms', [times[1], times[0]]),
    times[1] <= 1.25 * times[0] + 100);
end;

{ A file of ANest fields around ABytes and the same paragraphs with no field, each read on
  demand: a key typed before the first paragraph of the paragraphs (before the fields' open
  marks) and one after the last (after their close marks), and the save after each - within
  1.5 times the field-less file's save after the same key, and 100 ms: the fields' groups go
  out as blocks of the file, their paragraphs neither parsed nor walked. }
procedure TTyRichEditPerfTest.SaveBesideFields(ABytes: Int64; ANest: Integer);
var
  paths: array[0..1] of string;
  times: array[0..1, 0..1] of Double;
  i, w: Integer;
  d: TTyRichDocument;
  s: TFileStream;
  o: TMemoryStream;
  at: TTyRichPos;
  t0: Double;
begin
  CheckRoom;
  for i := 0 to 1 do
  begin
    paths[i] := NewFile('.rtf');
    MakeWrappedRtf(paths[i], ABytes, ANest * i);
    for w := 0 to 1 do
    begin
      d := TTyRichDocument.Create;
      o := TMemoryStream.Create;
      try
        s := TFileStream.Create(paths[i], fmOpenRead or fmShareDenyWrite);
        try
          TyRichLoadRtf(d, s);
        finally
          s.Free;
        end;
        // paragraph 1: the fields' open marks first; the last one ("tail"): their close marks
        if w = 0 then at := d.Text.ParaStart(1)
        else at := d.Text.ParaStart(d.Text.ParaCount - 1) + ANest * i;
        AssertEquals('outside every field', 0, d.FieldDepthAt(at));
        AssertTrue('the key', d.Execute(TTyRichInsertText.Create(at, 'Z')));
        t0 := Clock;
        TyRichSaveRtf(d, o);
        times[i, w] := Clock - t0;
      finally
        o.Free;
        d.Free;
      end;
    end;
  end;
  for w := 0 to 1 do
  begin
    Report(Format('%d MB of paragraphs, %d fields deep, a key %s them: the save (no field: %.1f ms)',
      [ABytes div (1024 * 1024), ANest, BoolToStr(w = 0, 'before', 'after'), times[0, w]]),
      times[1, w]);
    AssertTrue(Format('a key %s the fields: the save in %.0f ms, %.0f ms with no field',
      [BoolToStr(w = 0, 'before', 'after'), times[1, w], times[0, w]]),
      times[1, w] <= 1.5 * times[0, w] + 100);
  end;
end;

procedure TTyRichEditPerfTest.TestASaveBesideOneFieldAround100MB;
begin
  SaveBesideFields(CFileBytes, 1);
end;

procedure TTyRichEditPerfTest.TestASaveBesideFieldsEightDeepAround30MB;
begin
  SaveBesideFields(30 * 1024 * 1024, 8);
end;

initialization
  RegisterTest(TTyRichEditPerfTest);

end.
