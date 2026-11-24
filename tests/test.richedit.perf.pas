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
    procedure TestAContentsPastedIntoAnotherDocument;
    procedure TestA100MBRtfOfEquations;
    procedure TestAKeyWithARulerLinked;
    procedure TestTheActionsOverAWhole100MBSelection;
    procedure TestARtfOf200PicturesAPlaceNeverShownAndAgain;
    procedure TestAutoHeightOfAThousandParagraphsAfterAWidthChange;
    procedure TestABuilderOfTenThousandFormattedParagraphs;
    procedure TestABookmarkAmong200000In100MB;
    procedure TestListItemsMadeInA100MBRtfSaveAsAKeyDoes;
    procedure TestATableCellPropertyAndARowInALongTable;
    procedure TestAScreenOfALongStyledTable;
    procedure TestAColumnEdgeOfALongTable;
  private
    procedure SaveBesideFields(ABytes: Int64; ANest: Integer);
  end;

implementation

uses
  Math, LCLType, Controls, BGRABitmap, BGRABitmapTypes, tyControls.RichEdit.Text,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands, tyControls.RichEdit.Find, tyControls.RichEdit.Ruler,
  tyControls.RichEdit.Actions, tyControls.RichEdit.Builder, tyControls.RichEdit.TableProps
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
    { The pointer moved with no button held. }
    procedure Hover(X, Y: Integer);
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

procedure TPerfRich.Hover(X, Y: Integer);
begin
  MouseMove([], X, Y);
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

{ About ABytes of RTF of MakeRtf's paragraphs with AEquations of Word's equations among them,
  one every so many paragraphs: each its own words and the picture Word keeps beside them (a
  PNG in \*\shppict, a metafile in \nonshppict). AParas: the paragraphs that hold one. }
procedure MakeEquationsRtf(const APath: string; ABytes: Int64; AEquations: Integer;
  out AParas: TIntegerDynArray);
var
  f: TFileStream;
  buf: TMemoryStream;
  n, para, every: Integer;
  png, eq: RawByteString;
  data: TBytes;
  b: TBGRABitmap;
  st: TBytesStream;
  i, x: Integer;
const
  D: array[0..15] of AnsiChar = '0123456789abcdef';
begin
  // a picture of an equation's size: dark strokes on white, as Word renders one
  b := TBGRABitmap.Create(112, 48, BGRAWhite);
  st := TBytesStream.Create;
  try
    x := 4;
    while x < 108 do
    begin
      b.FillRect(x, 10, x + 3, 38, BGRABlack, dmSet);
      Inc(x, 9);
    end;
    b.SaveToStreamAs(st, ifPng);
    data := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
  png := '';
  for i := 0 to High(data) do
  begin
    if (i > 0) and (i mod 64 = 0) then png := png + #13#10;
    png := png + D[data[i] shr 4] + D[data[i] and 15];
  end;
  eq := Bar('{|mmath{|*|moMath{|mr|i E=m}{|msSup{|me{|mr c}}{|msup{|mr 2}}}}' +
    '{|mmathPict{|*|shppict{|pict{|*|picprop|shplid1025{|sp{|sn shapeType}{|sv 75}}}' +
    '|picscalex100|picscaley100|picw112|pich48|picwgoal840|pichgoal360|pngblip ') + #13#10 + png +
    Bar('}}{|nonshppict{|pict|picscalex100|picscaley100|picw1482|pich635|picwgoal840|pichgoal360' +
    '|wmetafile8 010009000003220000000000050000000000040000000301080005000000130200000000' +
    '030000000000}}}}');
  SetLength(AParas, AEquations);
  // (paragraphs are about 120 bytes: the equations are spread over the first 85 MB or so)
  every := Max(1, (ABytes div 150) div (AEquations + 1));
  f := TFileStream.Create(APath, fmCreate);
  buf := TMemoryStream.Create;
  try
    WriteRaw(buf, '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fswiss\fcharset0 Arial;}' +
      '{\f1\fnil\fcharset134 SimSun;}{\f34\froman\fcharset0 Cambria Math;}}' + #13#10 +
      '{\colortbl ;\red200\green0\blue0;}' + #13#10 + '\viewkind4\uc1\pard\f0\fs20 ');
    n := 0;
    para := 0;
    while f.Size + buf.Size < ABytes do
    begin
      if (para mod every = every div 2) and (n < AEquations) then
      begin
        WriteRaw(buf, 'Paragraph ' + IntToStr(para) + ' holds an equation: ' + eq +
          ' and more text after it.\par' + #13#10);
        AParas[n] := para;
        Inc(n);
      end
      else
        WriteRaw(buf, 'Paragraph ' + IntToStr(para) + ' with \b bold\b0  and \cf1 coloured\cf0  words, ' +
          '\f1 3?▙1?➗9?㕹7?\f0  and more text.\par' + #13#10);
      Inc(para);
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
  SetLength(AParas, n);
end;

{ A JPEG of a photograph's kind: smooth colour with grain. }
function GrainJpeg(AW, AH: Integer; ASeed: Cardinal): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
  p: PBGRAPixel;
  x, y, g: Integer;
begin
  b := TBGRABitmap.Create(AW, AH);
  st := TBytesStream.Create;
  try
    for y := 0 to AH - 1 do
    begin
      p := b.ScanLine[y];
      for x := 0 to AW - 1 do
      begin
        ASeed := ASeed xor (ASeed shl 13);
        ASeed := ASeed xor (ASeed shr 17);
        ASeed := ASeed xor (ASeed shl 5);
        g := Integer(ASeed and 7) - 4;
        p^.red := EnsureRange(x * 255 div AW + g, 0, 255);
        p^.green := EnsureRange(y * 255 div AH + g, 0, 255);
        p^.blue := EnsureRange(128 + ((x + y) mod 97) + g, 0, 255);
        p^.alpha := 255;
        Inc(p);
      end;
    end;
    b.InvalidateBitmap;
    b.SaveToStreamAs(st, ifJpeg);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

{ An RTF of APictures pictures as the bench makes its file: PNG and JPEG by turns in eight
  sizes from 200 x 150 to 2400 x 1600 (about 0.1 to 2 MB each), each after fifteen of
  MakeRtf's paragraphs, shown at most 600 pixels wide; hex digits, 64 bytes a line.
  APicBytes: the pictures' bytes. }
procedure MakePicturesRtf(const APath: string; APictures: Integer; out APicBytes: Int64);
const
  W: array[0..7] of Integer = (320, 1600, 640, 800, 200, 2400, 640, 1024);
  H: array[0..7] of Integer = (240, 1200, 480, 600, 150, 1600, 360, 768);
  Jpg: array[0..7] of Boolean = (False, True, False, True, False, True, False, True);
  D: array[0..15] of AnsiChar = '0123456789abcdef';
var
  f: TFileStream;
  buf: TMemoryStream;
  hex: array[0..7] of RawByteString;
  lens: array[0..7] of Integer;
  data: TBytes;
  i, k, n, kind, gw, gh, o: Integer;
begin
  for kind := 0 to 7 do
  begin
    if Jpg[kind] then data := GrainJpeg(W[kind], H[kind], 2463534242 + Cardinal(kind))
    else data := NoisePng(W[kind], H[kind]);
    lens[kind] := Length(data);
    SetLength(hex[kind], Length(data) * 2 + (Length(data) div 64 + 1) * 2);
    o := 1;
    for i := 0 to High(data) do
    begin
      if (i > 0) and (i mod 64 = 0) then
      begin
        hex[kind][o] := #13;
        hex[kind][o + 1] := #10;
        Inc(o, 2);
      end;
      hex[kind][o] := D[data[i] shr 4];
      hex[kind][o + 1] := D[data[i] and 15];
      Inc(o, 2);
    end;
    SetLength(hex[kind], o - 1);
  end;
  APicBytes := 0;
  f := TFileStream.Create(APath, fmCreate);
  buf := TMemoryStream.Create;
  try
    WriteRaw(buf, '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fswiss\fcharset0 Arial;}' +
      '{\f1\fnil\fcharset134 SimSun;}}' + #13#10 + '{\colortbl ;\red200\green0\blue0;}' +
      #13#10 + '\viewkind4\uc1\pard\f0\fs20 ');
    n := 0;
    for i := 0 to APictures - 1 do
    begin
      for k := 1 to 15 do
      begin
        Inc(n);
        WriteRaw(buf, 'Paragraph ' + IntToStr(n) + ' with \b bold\b0  and \cf1 coloured\cf0  ' +
          'words, \f1 3?▙1?➗9?㕹7?\f0  and more text.\par' + #13#10);
      end;
      kind := i mod 8;
      Inc(APicBytes, lens[kind]);
      gw := Min(W[kind], 600);
      gh := H[kind] * gw div W[kind];
      WriteRaw(buf, Bar('|pard Picture ' + IntToStr(i + 1) + ': {|pict|picw' + IntToStr(W[kind]) +
        '|pich' + IntToStr(H[kind]) + '|picwgoal' + IntToStr(gw * 15) + '|pichgoal' +
        IntToStr(gh * 15) + BoolToStr(Jpg[kind], '|jpegblip', '|pngblip') + ' ') + #13#10);
      WriteRaw(buf, hex[kind]);
      WriteRaw(buf, Bar('}|par') + #13#10);
      if buf.Size > 1024 * 1024 then
      begin
        f.WriteBuffer(buf.Memory^, buf.Size);
        buf.Clear;
      end;
    end;
    for k := 1 to 15 do
    begin
      Inc(n);
      WriteRaw(buf, 'Paragraph ' + IntToStr(n) + ' after the last picture.\par' + #13#10);
    end;
    WriteRaw(buf, '}' + #13#10);
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
  t0, first, mid, last, keyLink, keyAfter, stepToc, moveNew, moveSame, findAll: Double;
  tocFirst, tocLast, linkAfter, p, depth, i, found: Integer;
  at: TTyRichPos;
  t: TTyRichText;
  r: TRect;
  f: TTyRichFinder;
  needle: UTF8String;
  raw: RawByteString;
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
    // a caret step in the contents' middle, across an entry's link and its page number's marks
    p := (tocFirst + tocLast) div 2;
    FRich.SelStart := t.ParaStart(p) + 3;
    FRich.ScrollCaretIntoView;
    TPerfRich(FRich).PaintInto(bmp);
    t0 := Clock;
    for i := 1 to 20 do TPerfRich(FRich).Key(VK_RIGHT, []);
    TPerfRich(FRich).PaintInto(bmp);
    stepToc := (Clock - t0) / 20;
    Report('rtf of fields: a caret step in the contents'' middle (the average of 20, painted once)', stepToc);
    { The pointer over an entry of the contents, read-only (where a plain click is a link's, so
      every move asks for the link under it): the first move over the entry, then moves over it
      again. }
    FRich.ReadOnly := True;
    r := FRich.PositionRect(t.ParaStart(p) + 4);
    t0 := Clock;
    TPerfRich(FRich).Hover(r.Left + 1, (r.Top + r.Bottom) div 2);
    moveNew := Clock - t0;
    Report('rtf of fields: the pointer onto an entry of the contents', moveNew);
    r := FRich.PositionRect(t.ParaStart(p + 1) + 4);
    t0 := Clock;
    for i := 1 to 20 do TPerfRich(FRich).Hover(r.Left + 1 + i mod 2, (r.Top + r.Bottom) div 2);
    moveSame := (Clock - t0) / 20;
    Report('rtf of fields: the pointer moving over the next entry (the average of 20)', moveSame);
    FRich.ReadOnly := False;
    // find all: a needle across every link's open mark, in the whole file
    t0 := Clock;
    // ("to " and the two characters every link's result begins with, U+94FE U+63A5)
    raw := 'to ' + #$E9#$93#$BE#$E6#$8E#$A5;
    SetCodePage(raw, CP_UTF8, False);
    needle := raw;
    f := TTyRichFinder.Create(FRich.Document, needle, [], 0, -1);
    try
      f.Collect := True;
      f.Run;
      found := f.MatchCount;
    finally
      f.Free;
    end;
    findAll := Clock - t0;
    Report(Format('rtf of fields: find all of a needle across the links'' marks (%d found; not asserted)',
      [found]), findAll);
    WriteLn('TTyRichEditPerfTest: rtf of fields: peak working set: ' + PeakWorkingSet);
    AssertTrue(Format('the first screen in %.0f ms', [first]), first <= CFirstScreenMs);
    AssertTrue(Format('the contents'' middle in %.0f ms', [mid]), mid <= CScrollMs);
    AssertTrue(Format('the end in %.0f ms', [last]), last <= CScrollMs);
    AssertTrue(Format('a key before a link in %.1f ms', [keyLink]), keyLink <= CKeystrokeMs);
    AssertTrue(Format('a key after the contents in %.1f ms', [keyAfter]), keyAfter <= CKeystrokeMs);
    AssertTrue(Format('a caret step in the contents in %.1f ms', [stepToc]), stepToc <= CKeystrokeMs);
    AssertTrue(Format('the pointer onto an entry in %.1f ms', [moveNew]), moveNew <= CKeystrokeMs);
    AssertTrue(Format('the pointer over an entry in %.1f ms', [moveSame]), moveSame <= CKeystrokeMs);
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
  path, plain: string;
  bmp: TBitmap;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  t0, first, again: Double;
  n, parses: Integer;
begin
  CheckRoom;
  path := NewFile('.rtf');
  MakeWrappedRtf(path, CFileBytes, 1);
  plain := NewFile('.rtf');
  MakeWrappedRtf(plain, CFileBytes, 0);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    // the same paragraphs with no field, first: what the field adds (not asserted)
    t0 := Clock;
    FRich.LoadFromFile(plain);
    TPerfRich(FRich).PaintInto(bmp);
    Report(Format('the same %d MB with no field: load (first slice) and first paint (not asserted)',
      [SizeOfFile(plain) div (1024 * 1024)]), Clock - t0);
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

{ A 100 MB RTF with 2,000 of Word's equations, each shown as the picture the file keeps
  beside it: the first screen within 3 s, a jump to the middle equation within 300 ms, a key
  typed right before an equation to the end of its paint within 90 ms. Then the view put on
  every equation in turn and back to the start: the working set then against what it was
  after the first screen (printed with the picture cache's bound; asserted: within three
  times the file). }
procedure TTyRichEditPerfTest.TestA100MBRtfOfEquations;
var
  path: string;
  bmp: TBitmap;
  paras: TIntegerDynArray;
  t0, first, mid, key: Double;
  t: TTyRichText;
  at: TTyRichPos;
  i, p, depth: Integer;
  w0, w1: Double;
  look0: Int64;
begin
  CheckRoom;
  path := NewFile('.rtf');
  MakeEquationsRtf(path, CFileBytes, 2000, paras);
  AssertEquals('2000 equations written', 2000, Length(paras));
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    look0 := TyRichKeptPictureLookups;
    t0 := Clock;
    FRich.LoadFromFile(path);
    TPerfRich(FRich).PaintInto(bmp);
    first := Clock - t0;
    Report(Format('rtf of equations %d MB: load (first slice) and first paint',
      [SizeOfFile(path) div (1024 * 1024)]), first);
    t0 := Clock;
    FRich.FinishLoading;
    Report(Format('rtf of equations: the rest indexed (%d paragraphs; not asserted)',
      [FRich.Document.Text.ParaCount]), Clock - t0);
    TPerfRich(FRich).PaintInto(bmp);
    while TPerfRich(FRich).Step do ;
    w0 := WorkingSetMB;
    t := FRich.Document.Text;
    // the middle equation: the view put there and painted
    p := paras[Length(paras) div 2];
    t0 := Clock;
    FRich.SelStart := t.ParaStart(p) + 3;
    FRich.ScrollCaretIntoView;
    TPerfRich(FRich).PaintInto(bmp);
    mid := Clock - t0;
    Report(Format('rtf of equations: a jump to the middle equation (paragraph %d)', [p]), mid);
    AssertTrue(Format('the view at it (paragraph %d)', [FRich.TopParagraph]),
      Abs(FRich.TopParagraph - p) < 100);
    // a key right before the equation
    at := t.ParaStart(p);
    while FRich.Document.ObjectAt(at) = nil do Inc(at);
    FRich.SelStart := at;
    FRich.ScrollCaretIntoView;
    TPerfRich(FRich).PaintInto(bmp);
    while TPerfRich(FRich).Step do ;
    TPerfRich(FRich).PaintInto(bmp);
    depth := FRich.Document.UndoDepth;
    t0 := Clock;
    TPerfRich(FRich).TypeChar('x');
    TPerfRich(FRich).PaintInto(bmp);
    key := Clock - t0;
    AssertEquals('typed before the equation', depth + 1, FRich.Document.UndoDepth);
    Report('rtf of equations: a character typed right before an equation, to the end of its paint',
      key);
    // every equation in turn, its picture made ready, and back to the start
    t0 := Clock;
    for i := 0 to High(paras) do
    begin
      FRich.SelStart := t.ParaStart(paras[i]);
      FRich.ScrollCaretIntoView;
      TPerfRich(FRich).PaintInto(bmp);
      while TPerfRich(FRich).Step do ;
    end;
    TPerfRich(FRich).Key(VK_HOME, [ssCtrl]);
    TPerfRich(FRich).PaintInto(bmp);
    while TPerfRich(FRich).Step do ;
    Report('rtf of equations: the view put on each of the 2000 equations and back (not asserted)',
      Clock - t0);
    w1 := WorkingSetMB;
    WriteLn(Format('TTyRichEditPerfTest: rtf of equations: working set %.0f MB after the first ' +
      'screen, %.0f MB after every equation and back (%.0f MB more; the picture cache''s bound ' +
      '%d MB, held now %.1f MB in %d entries); pictures looked for: %d', [w0, w1, w1 - w0,
      FRich.Layouter.PictureCacheLimit div (1024 * 1024),
      FRich.Layouter.PictureCacheBytes / (1024 * 1024), FRich.Layouter.PictureCacheCount,
      TyRichKeptPictureLookups - look0]));
    WriteLn('TTyRichEditPerfTest: rtf of equations: peak working set: ' + PeakWorkingSet);
    AssertTrue(Format('the first screen in %.0f ms', [first]), first <= CFirstScreenMs);
    AssertTrue(Format('the middle equation in %.0f ms', [mid]), mid <= CScrollMs);
    AssertTrue(Format('a key before an equation in %.1f ms', [key]), key <= CKeystrokeMs);
    {$IFDEF MSWINDOWS}
    AssertTrue(Format('the working set %.0f MB within three times the file', [w1]),
      w1 <= 3 * SizeOfFile(path) / (1024 * 1024));
    {$ENDIF}
  finally
    bmp.Free;
  end;
end;

{ A 100 MB txt, the view in its middle: a character typed there and the paint after it, the best
  of three without a ruler and the best of three with a TTyRichEditRuler linked (what it hears
  and asks inside the key is in the figure; its own paint, a window of its own, is timed apart).
  Held to the keystroke's line, both; printed, the three figures. }
procedure TTyRichEditPerfTest.TestAKeyWithARulerLinked;
var
  path: string;
  bmp, rb: TBitmap;
  ruler: TTyRichEditRuler;
  i: Integer;
  without, withRuler, rulerPaint, t0: Double;
begin
  CheckRoom;
  path := NewFile('.txt');
  MakeText(path, CFileBytes);
  bmp := TBitmap.Create;
  rb := TBitmap.Create;
  ruler := nil;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.LoadFromFile(path);
    TPerfRich(FRich).PaintInto(bmp);
    FRich.ScrollY := FRich.Document.Text.TotalHeight div 2;
    TPerfRich(FRich).PaintInto(bmp);
    without := MaxDouble;
    for i := 1 to 3 do without := Min(without, Keystroke(bmp, False));
    ruler := TTyRichEditRuler.Create(nil);
    ruler.Controller := FCtl;
    ruler.Font.PixelsPerInch := 96;
    ruler.SetBounds(0, 0, FRich.Width, 40);
    ruler.RichEdit := FRich;
    rb.PixelFormat := pf32bit;
    rb.SetSize(ruler.Width, ruler.Height);
    withRuler := MaxDouble;
    for i := 1 to 3 do withRuler := Min(withRuler, Keystroke(bmp, False));
    rulerPaint := MaxDouble;
    for i := 1 to 3 do
    begin
      t0 := Clock;
      ruler.RenderTo(rb.Canvas, Rect(0, 0, ruler.Width, ruler.Height), 96);
      rulerPaint := Min(rulerPaint, Clock - t0);
    end;
    Report('txt: a key in the middle and its paint, no ruler (best of 3)', without);
    Report('txt: a key in the middle and its paint, a ruler linked (best of 3)', withRuler);
    Report('the ruler''s own paint (best of 3)', rulerPaint);
    AssertTrue(Format('a key with a ruler linked in %.1f ms', [withRuler]),
      withRuler <= CKeystrokeMs);
    AssertTrue(Format('the ruler painted in %.1f ms', [rulerPaint]), rulerPaint <= CKeystrokeMs);
  finally
    ruler.Free;
    rb.Free;
    bmp.Free;
  end;
end;

{ A table of contents of 500 and of 5,000 entries (each a link holding its text, a tab and a
  page number field) copied from its file and pasted into another document - where it is the
  model's own field -, then that document saved: the times of each, printed; the 5,000 within
  ten times the 500 and a bit (linear), not asserted against a line of its own. }
procedure TTyRichEditPerfTest.TestAContentsPastedIntoAnotherDocument;
const
  counts: array[0..1] of Integer = (500, 5000);
var
  pasteMs, saveMs: array[0..1] of Double;
  k, i: Integer;
  s, rtf: RawByteString;
  src: TTyRichDocument;
  st, ss: TBytesStream;
  b: RawByteString;
  t0: Double;
  os: TMemoryStream;
begin
  for k := 0 to 1 do
  begin
    s := '{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fswiss Arial;}{|f1|fnil|fcharset134 SimSun;}}' +
      '{|colortbl;|red0|green0|blue255;}|pard|f0 Contents: {|field|fldedit{|*|fldinst TOC ||o "1-3" ||h}{|fldrslt ';
    for i := 1 to counts[k] do
    begin
      s := s + '{|field{|*|fldinst HYPERLINK ||l "_Toc' + IntToStr(i) + '"}{|fldrslt {|cs15|ul|cf1|f1 ' +
        '|u31532?' + IntToStr(i) + '|u31456? Chapter ' + IntToStr(i) + '|tab {|field{|*|fldinst PAGEREF _Toc' +
        IntToStr(i) + ' ||h}{|fldrslt ' + IntToStr(3 * i) + '}}}}}';
      if i < counts[k] then s := s + '|par ';
    end;
    s := s + '}} after|par}';
    src := TTyRichDocument.Create;
    try
      b := Bar(s);
      st := TBytesStream.Create;
      st.WriteBuffer(b[1], Length(b));
      st.Position := 0;
      try
        TyRichLoadRtfFull(src, st);
      finally
        st.Free;
      end;
      ss := TBytesStream.Create;
      try
        TyRichSaveRtfRange(src, ss, 0, src.Text.Length);
        rtf := '';
        SetLength(rtf, ss.Size);
        Move(ss.Bytes[0], rtf[1], ss.Size);
        SetCodePage(rtf, CP_NONE, False);
      finally
        ss.Free;
      end;
    finally
      src.Free;
    end;
    FRich.Lines.Text := 'another document';
    FRich.SelStart := 0;
    TPerfRich(FRich).ClipRtf := rtf;
    t0 := Clock;
    FRich.PasteFromClipboard;
    pasteMs[k] := Clock - t0;
    TPerfRich(FRich).ClipRtf := '';
    AssertTrue('pasted', FRich.Document.Text.ParaCount >= counts[k]);
    os := TMemoryStream.Create;
    try
      t0 := Clock;
      FRich.SaveToStream(os, rfRtf);
      saveMs[k] := Clock - t0;
      AssertTrue('saved', os.Size > 0);
    finally
      os.Free;
    end;
    Report(Format('a contents of %d entries pasted into another document', [counts[k]]), pasteMs[k]);
    Report(Format('... that document saved', [counts[k]]), saveMs[k]);
  end;
  WriteLn(Format('TTyRichEditPerfTest: 5000 / 500: the paste %.1f times, the save %.1f times',
    [pasteMs[1] / Max(0.1, pasteMs[0]), saveMs[1] / Max(0.1, saveMs[0])]));
end;

{ Every action of tyControls.RichEdit.Actions linked to a 100 MB document (a txt, then an RTF
  read to its end) with all of it selected: the first round of updates after the selection
  asks the rich edit once - the format queries over the whole selection, bounded by the
  control - and a round after it, as the application's idle makes them, asks nothing. Both
  printed; the first held to the keystroke's line, an idle round to a tenth of it. }
procedure TTyRichEditPerfTest.TestTheActionsOverAWhole100MBSelection;
var
  path: string;
  bmp: TBitmap;
  acts: array of TTyRichEditAction;
  i, k, f: Integer;
  t0, first, idle: Double;
const
  Exts: array[0..1] of string = ('.txt', '.rtf');
begin
  CheckRoom;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    SetLength(acts, Length(CTyRichEditActions));
    for i := 0 to High(acts) do
    begin
      acts[i] := CTyRichEditActions[i].Create(nil);
      acts[i].RichEdit := FRich;
    end;
    try
      for f := 0 to High(Exts) do
      begin
        path := NewFile(Exts[f]);
        if f = 0 then MakeText(path, CFileBytes) else MakeRtf(path, CFileBytes);
        FRich.LoadFromFile(path);
        FRich.FinishLoading;
        TPerfRich(FRich).PaintInto(bmp);
        for i := 0 to High(acts) do acts[i].Update;
        FRich.SelectAll;
        TPerfRich(FRich).PaintInto(bmp);
        t0 := Clock;
        for i := 0 to High(acts) do acts[i].Update;
        first := Clock - t0;
        idle := MaxDouble;
        for k := 1 to 5 do
        begin
          t0 := Clock;
          for i := 0 to High(acts) do acts[i].Update;
          idle := Min(idle, Clock - t0);
        end;
        Report(Format('%s: %d actions, all of it selected: the first round (the queries)',
          [Exts[f], Length(acts)]), first);
        Report(Format('%s: %d actions, all of it selected: an idle round (best of 5)',
          [Exts[f], Length(acts)]), idle);
        AssertTrue(Format('%s: the first round in %.1f ms', [Exts[f], first]),
          first <= CKeystrokeMs);
        AssertTrue(Format('%s: an idle round in %.2f ms', [Exts[f], idle]),
          idle <= CKeystrokeMs / 10);
        FRich.Clear;
      end;
    finally
      for i := 0 to High(acts) do acts[i].Free;
    end;
  finally
    bmp.Free;
  end;
end;

{ An RTF of 200 pictures (PNG and JPEG, about 0.1 to 2 MB each; the bench's file of
  pictures): a place never shown (70 % of the height: never parsed since the index) set and
  painted within 300 ms, and that place again after two dozen others evicted its layouts and
  its parse, within 300 ms - the pictures there parsed without their bytes being converted
  (asserted: none made from hex digits, none copied), decoded later in the idle steps. }
procedure TTyRichEditPerfTest.TestARtfOf200PicturesAPlaceNeverShownAndAgain;
var
  path: string;
  bmp: TBitmap;
  t0, rand, again: Double;
  load: TTyRtfLoad;
  total: Int64;
  pics, parsed, conv, copied: Int64;
  i, top, parses: Integer;
  misses: Int64;
begin
  CheckRoom;
  path := NewFile('.rtf');
  MakePicturesRtf(path, 200, pics);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.LoadFromFile(path);
    TPerfRich(FRich).PaintInto(bmp);
    FRich.FinishLoading;
    load := TyRichRtfLoadOf(FRich.Document);
    AssertTrue('a lazy load', (load <> nil) and not load.Whole);
    total := FRich.Document.Text.TotalHeight;
    // the middle, and its pictures made ready in the idle steps (not timed)
    FRich.ScrollY := total div 2;
    TPerfRich(FRich).PaintInto(bmp);
    while TPerfRich(FRich).Step do ;
    TPerfRich(FRich).PaintInto(bmp);
    // a place never shown
    misses := FRich.Layouter.CacheMisses;
    parses := load.ParseCount;
    parsed := load.ParsedBytes;
    conv := load.PictureBytesConverted;
    copied := load.PictureBytesCopied;
    // (the heights laid out so far are real ones now: the place by the document's height now)
    total := FRich.Document.Text.TotalHeight;
    t0 := Clock;
    FRich.ScrollY := Round(total * 0.7371);
    TPerfRich(FRich).PaintInto(bmp);
    rand := Clock - t0;
    Report(Format('pictures %d MB (%d MB of pictures): a place never shown set and painted ' +
      '(%d KB of the file parsed for it)', [SizeOfFile(path) div (1024 * 1024),
      pics div (1024 * 1024), (load.ParsedBytes - parsed) div 1024]), rand);
    AssertTrue('the place was laid out for the paint', FRich.Layouter.CacheMisses > misses);
    AssertTrue('the place was parsed for the paint', load.ParseCount > parses);
    AssertEquals('no picture byte made from hex digits', conv, load.PictureBytesConverted);
    AssertEquals('no picture byte copied', copied, load.PictureBytesCopied);
    top := FRich.TopParagraph;
    // other places until that place's layouts left the cache, two dozen at least
    i := 0;
    repeat
      FRich.ScrollY := Round(FRich.Document.Text.TotalHeight * Frac(0.1 + i * 0.6180339887));
      TPerfRich(FRich).PaintInto(bmp);
      Inc(i);
    until ((i >= 24) and (FRich.Layouter.CachedLayout(top) = nil)) or (i >= 400);
    misses := FRich.Layouter.CacheMisses;
    parses := load.ParseCount;
    t0 := Clock;
    FRich.ScrollY := FRich.Document.Text.ParaTop(top);
    TPerfRich(FRich).PaintInto(bmp);
    again := Clock - t0;
    Report(Format('pictures: that place again after %d others evicted it', [i]), again);
    WriteLn('TTyRichEditPerfTest: pictures: peak working set: ' + PeakWorkingSet);
    AssertTrue('the place''s layouts were evicted', FRich.Layouter.CacheMisses > misses);
    AssertTrue('the place''s parse was evicted', load.ParseCount > parses);
    AssertEquals('the same place', top, FRich.TopParagraph);
    AssertTrue(Format('a place never shown in %.0f ms', [rand]), rand <= CScrollMs);
    AssertTrue(Format('that place again in %.0f ms', [again]), again <= CScrollMs);
  finally
    bmp.Free;
  end;
end;

{ A page as tall as its content (AutoHeight) of 1,000 paragraphs made narrower: every
  paragraph laid out again and the height set, in one UpdateView - within the keystroke's
  line (the design's 30 ms, three times). }
procedure TTyRichEditPerfTest.TestAutoHeightOfAThousandParagraphsAfterAWidthChange;
var
  s: string;
  i, h0: Integer;
  t0, t: Double;
begin
  s := '';
  for i := 1 to 1000 do
    s := s + 'Paragraph ' + IntToStr(i) + ': a sentence or two of ordinary words that wrap.' +
      LineEnding;
  FRich.Lines.Text := s;
  FRich.AutoHeight := True;
  FRich.UpdateView;
  h0 := FRich.Height;
  AssertEquals('as tall as its content', FRich.ContentHeight, h0);
  t := MaxDouble;
  for i := 1 to 3 do
  begin
    t0 := Clock;
    if Odd(i) then FRich.Width := FRich.Width - 120 else FRich.Width := FRich.Width + 120;
    FRich.UpdateView;
    t := Min(t, Clock - t0);
    AssertEquals('as tall as its content again', FRich.ContentHeight, FRich.Height);
  end;
  Report('AutoHeight: 1,000 paragraphs after a width change (best of 3)', t);
  AssertTrue(Format('AutoHeight after a width change in %.1f ms', [t]), t <= CKeystrokeMs);
end;

{ Three paragraphs in the middle of a 100 MB RTF made a list of two levels: the save writes
  their list table and their numbers from the paragraph before them on - it costs what a key
  typed there costs (within 1.5 times and 100 ms, and two parses more at most), not a walk of
  the file's paragraphs. }
procedure TTyRichEditPerfTest.TestListItemsMadeInA100MBRtfSaveAsAKeyDoes;
var
  path: string;
  times: array[0..1] of Double;
  parses: array[0..1] of Int64;
  w, mid: Integer;
  d: TTyRichDocument;
  s: TFileStream;
  o: TMemoryStream;
  p: TTyParaFormat;
  load: TTyRtfLoad;
  head: RawByteString;
  t0: Double;
  n0: Int64;
begin
  CheckRoom;
  path := NewFile('.rtf');
  MakeRtf(path, CFileBytes);
  for w := 0 to 1 do
  begin
    d := TTyRichDocument.Create;
    o := TMemoryStream.Create;
    try
      s := TFileStream.Create(path, fmOpenRead or fmShareDenyWrite);
      try
        TyRichLoadRtf(d, s);
      finally
        s.Free;
      end;
      load := TyRichRtfLoadOf(d);
      mid := d.Text.ParaCount div 2;
      if w = 0 then
        AssertTrue('the key', d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(mid), 'Z')))
      else
      begin
        p := TyDefaultParaFormat;
        p.List.Kind := lkDecimal;
        AssertTrue('the list', d.Execute(TTyRichSetParaFormat.Create(mid, mid + 2, [pffList], p)));
        p.List.Level := 1;
        AssertTrue('its inner item', d.Execute(TTyRichSetParaFormat.Create(mid + 1, mid + 1,
          [pffList], p)));
      end;
      n0 := load.ParseCount;
      t0 := Clock;
      TyRichSaveRtf(d, o);
      times[w] := Clock - t0;
      parses[w] := load.ParseCount - n0;
      if w = 1 then
      begin
        SetLength(head, 4096);
        Move(o.Memory^, head[1], 4096);
        AssertTrue('its list table in the header', Pos('{\*\listtable', head) > 0);
      end;
    finally
      o.Free;
      d.Free;
    end;
  end;
  Report(Format('%d MB: three paragraphs made a list of two levels, the save (a key there: ' +
    '%.1f ms, %d parses; the list: %d parses)', [CFileBytes div (1024 * 1024), times[0],
    parses[0], parses[1]]), times[1]);
  AssertTrue(Format('the save in %.0f ms, %.0f ms with a key', [times[1], times[0]]),
    times[1] <= 1.5 * times[0] + 100);
  AssertTrue(Format('%d parses, %d with a key', [parses[1], parses[0]]),
    parses[1] <= parses[0] + 2);
end;

{ 100 MB of paragraphs, each with a bookmark of its own around a few words (200,000): the jump
  to one far into the file and its paint within the line of any place (100 ms); what the
  load's index of them holds, and a name that is not there (every entry and every changed
  paragraph looked at), reported. BookmarkCount: the first call counts the index (no name
  read), the one after a character typed in a bookmark's paragraph keeps what it counted - a
  small part of the first; asked again with CanEditBookmarks, as an idle handler does, it
  walks nothing (no parse). A key over a selection of everything, to its paint, within the
  key's line: the deletion decides the bookmarks from the index (nothing parsed). }
procedure TTyRichEditPerfTest.TestABookmarkAmong200000In100MB;
const
  CMarks = 200000;
var
  path: string;
  f: TFileStream;
  line, pad: RawByteString;
  i: Integer;
  bmp: TBitmap;
  t0, go, miss, count1, count2, idle, all: Double;
  s, e: TTyRichPos;
  ld: TTyRichParaLoader;
  n, parses, k: Integer;
  rl: TTyRtfLoad;
begin
  CheckRoom;
  path := NewFile('.rtf');
  pad := '';
  while Length(pad) < CFileBytes div CMarks - 80 do pad := pad + 'more words of the paragraph ';
  f := TFileStream.Create(path, fmCreate);
  try
    line := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 ';
    f.WriteBuffer(line[1], Length(line));
    for i := 1 to CMarks do
    begin
      line := 'Paragraph ' + IntToStr(i) + ' {\*\bkmkstart bm' + IntToStr(i) + '}its text{\*\bkmkend bm' +
        IntToStr(i) + '} ' + pad + '\par' + #13#10;
      f.WriteBuffer(line[1], Length(line));
    end;
    line := '}';
    f.WriteBuffer(line[1], 1);
  finally
    f.Free;
  end;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.LoadFromFile(path);
    FRich.FinishLoading;
    TPerfRich(FRich).PaintInto(bmp);
    t0 := Clock;
    AssertTrue('gone to', FRich.GoToBookmark('BM150000'));
    TPerfRich(FRich).PaintInto(bmp);
    go := Clock - t0;
    Report(Format('bookmarks: a jump to one of %d in %d MB and its paint', [CMarks,
      SizeOfFile(path) div (1024 * 1024)]), go);
    AssertTrue('its place', FRich.FindBookmark('bm150000', s, e));
    AssertEquals('the caret there (after the start mark: in the bookmark)', s + 1, FRich.SelStart);
    AssertTrue(Format('within the line of any place (%.1f ms)', [go]), go <= 100);
    t0 := Clock;
    AssertFalse('a name that is not there', FRich.FindBookmark('nothere', s, e));
    miss := Clock - t0;
    Report('bookmarks: a name that is not there (not asserted)', miss);
    ld := FRich.Document.Loader;
    AssertTrue('an index', (ld <> nil) and (ld.BookmarkIndexCount = 2 * CMarks));
    WriteLn(Format('TTyRichEditPerfTest: bookmarks: the index holds %d ends, %d bytes ' +
      '(%d a bookmark)', [ld.BookmarkIndexCount, ld.BookmarkIndexCount * 21, 42]));
    // the count: the first call, then after a character typed in a bookmark's paragraph
    rl := TyRichRtfLoadOf(FRich.Document);
    AssertTrue('read on demand', rl <> nil);
    parses := rl.ParseCount;
    t0 := Clock;
    n := FRich.BookmarkCount;
    count1 := Clock - t0;
    Report(Format('bookmarks: BookmarkCount of %d, the first call', [n]), count1);
    AssertEquals('every one counted', CMarks, n);
    AssertEquals('counted with nothing parsed', parses, rl.ParseCount);
    FRich.SelStart := e + 1;
    TPerfRich(FRich).TypeChar('x');
    t0 := Clock;
    n := FRich.BookmarkCount;
    count2 := Clock - t0;
    Report('bookmarks: BookmarkCount after a character typed in a bookmark''s paragraph', count2);
    AssertEquals('still every one', CMarks, n);
    AssertTrue(Format('kept: %.3f ms against %.3f ms', [count2, count1]), count2 <= count1 / 20);
    // as an idle handler asks, a thousand times
    parses := rl.ParseCount;
    t0 := Clock;
    for k := 1 to 1000 do
      if FRich.CanEditBookmarks and (FRich.BookmarkCount < 0) then Break;
    idle := Clock - t0;
    Report('bookmarks: CanEditBookmarks and BookmarkCount asked 1,000 times (an idle handler)', idle);
    AssertEquals('asked with nothing parsed', parses, rl.ParseCount);
    AssertTrue(Format('the idle asks walk nothing (%.3f ms)', [idle]), idle <= count1 / 20);
    AssertEquals('a name read when asked for', 'bm150000', FRich.BookmarkName(149999));
    // a key over a selection of everything
    FRich.SelectAll;
    TPerfRich(FRich).PaintInto(bmp);
    parses := rl.ParseCount;
    t0 := Clock;
    TPerfRich(FRich).TypeChar('x');
    TPerfRich(FRich).PaintInto(bmp);
    all := Clock - t0;
    Report('bookmarks: a character typed over a selection of everything, to its paint', all);
    AssertEquals('the whole text replaced', 1, FRich.Document.Text.ParaCount);
    AssertEquals('no bookmark left', 0, FRich.BookmarkCount(True));
    // (the load stays while the history holds its paragraphs)
    AssertTrue('the load still there', TyRichRtfLoadOf(FRich.Document) = rl);
    AssertTrue(Format('nothing parsed by the deletion (%d intervals)', [rl.ParseCount - parses]),
      rl.ParseCount - parses <= 1);
    AssertTrue(Format('within the key''s line (%.1f ms)', [all]), all <= CKeystrokeMs);
  finally
    bmp.Free;
  end;
end;

{ 10,000 paragraphs in formats - a bold word, plain text, every tenth a link - built and put in
  with SetContent: the design's 200 ms, three times (the suite's line). }
procedure TTyRichEditPerfTest.TestABuilderOfTenThousandFormattedParagraphs;
var
  B: TTyRichBuilder;
  i, k: Integer;
  t0, t, best: Double;
begin
  best := MaxDouble;
  for k := 1 to 3 do
  begin
    t0 := Clock;
    B := FRich.NewBuilder;
    try
      for i := 1 to 10000 do
      begin
        B.Bold.Text('Item ' + IntToStr(i)).Bold(False).Text(': some ordinary words of a line.');
        if i mod 10 = 0 then B.Text(' ').Link('more', 'https://example.com/' + IntToStr(i));
        if i mod 7 = 0 then B.Color(clNavy) else B.Color(clDefault);
        B.Paragraph;
      end;
      FRich.SetContent(B);
    finally
      B.Free;
    end;
    t := Clock - t0;
    if t < best then best := t;
  end;
  AssertEquals('the paragraphs', 10001, FRich.Document.Text.ParaCount);
  Report('a builder: 10,000 formatted paragraphs built and set (best of 3)', best);
  AssertTrue(Format('built and set in %.1f ms', [best]), best <= 600);
end;

{ A table of 10,000 rows: one cell's property set (shading, through its command), from the
  command to the end of the paint; Tab in the last cell, which adds a row, through the
  user's door to the end of its paint; and the property again in a table a file gave. }
procedure TTyRichEditPerfTest.TestATableCellPropertyAndARowInALongTable;
const
  Rows = 10000;
var
  bmp: TBitmap;
  d: TTyRichDocument;
  t: TTyRichText;
  k: Integer;
  t0, prop, add, again: Double;
  info: TTyRichTableInfo;
  p: TTyRichCellProps;
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
    p := Default(TTyRichCellProps);
    p.Valid := [rcpShading];
    p.Shading := clYellow;
    t0 := Clock;
    AssertTrue('a shading', d.Execute(TTyRichSetCellProps.Create(t.ParaStart(k), Rows div 2, 0,
      Rows div 2, 0, p)));
    TPerfRich(FRich).PaintInto(bmp);
    prop := Clock - t0;
    Report(Format('table of %d rows: one cell''s shading, to the end of its paint', [Rows]), prop);
    // the last cell: a row below
    FRich.SelStart := t.ParaStart(2 * Rows);
    TPerfRich(FRich).PaintInto(bmp);
    t0 := Clock;
    TPerfRich(FRich).Key(VK_TAB, []);
    TPerfRich(FRich).PaintInto(bmp);
    add := Clock - t0;
    AssertTrue('a row added', d.TableInfoAt(1, info) and (info.RowCount = Rows + 1));
    Report('table: Tab in the last cell adds a row, to the end of its paint', add);
    // again, the next row after it
    t0 := Clock;
    p.Shading := clAqua;
    AssertTrue('a shading again', d.Execute(TTyRichSetCellProps.Create(t.ParaStart(k), Rows div 2,
      1, Rows div 2, 1, p)));
    TPerfRich(FRich).PaintInto(bmp);
    again := Clock - t0;
    Report('table: another cell''s shading, to the end of its paint', again);
    AssertTrue(Format('a cell''s shading in %.1f ms', [prop]), prop <= CKeystrokeMs);
    AssertTrue(Format('Tab adding a row in %.1f ms', [add]), add <= CKeystrokeMs);
    AssertTrue(Format('a cell''s shading again in %.1f ms', [again]), again <= CKeystrokeMs);
  finally
    bmp.Free;
  end;
end;

{ A table of 10,000 rows whose every cell has a shading and lines of four styles and two
  colours: a screen of it in the middle painted the first time (its rows laid out) and again. }
procedure TTyRichEditPerfTest.TestAScreenOfALongStyledTable;
const
  Rows = 10000;
var
  bmp: TBitmap;
  d: TTyRichDocument;
  t0, first, again: Double;
  p: TTyRichCellProps;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.Lines.Text := 'before' + LineEnding + 'after';
    d := FRich.Document;
    AssertTrue('a long table', d.Execute(TTyRichInsertTable.Create(d.Text.ParaStart(1), Rows, 3)));
    p := Default(TTyRichCellProps);
    p.Valid := [rcpShading, rcpBorderLeft, rcpBorderTop, rcpBorderRight, rcpBorderBottom];
    p.Shading := clYellow;
    // (sides: left, top, right, bottom)
    p.Borders[TTyRichCellSide(0)] := TyRichBorder(rbsDouble, 30, clRed);
    p.Borders[TTyRichCellSide(2)] := TyRichBorder(rbsDouble, 30, clRed);
    p.Borders[TTyRichCellSide(1)] := TyRichBorder(rbsDotted, 10, clBlue);
    p.Borders[TTyRichCellSide(3)] := TyRichBorder(rbsDashed, 30, clGreen);
    AssertTrue('styled', d.Execute(TTyRichSetCellProps.Create(d.Text.ParaStart(1), 0, 0, Rows - 1,
      2, p)));
    TPerfRich(FRich).PaintInto(bmp);
    FRich.ScrollY := d.Text.TotalHeight div 2;
    t0 := Clock;
    TPerfRich(FRich).PaintInto(bmp);
    first := Clock - t0;
    t0 := Clock;
    TPerfRich(FRich).PaintInto(bmp);
    again := Clock - t0;
    Report(Format('styled table of %d rows: a screen in the middle, the first time', [Rows]), first);
    Report('styled table: the same screen again', again);
    AssertTrue(Format('the first time in %.1f ms', [first]), first <= CScrollMs);
    AssertTrue(Format('again in %.1f ms', [again]), again <= CKeystrokeMs);
  finally
    bmp.Free;
  end;
end;

function ShadingProps(AColor: TColor): TTyRichCellProps;
begin
  Result := Default(TTyRichCellProps);
  Result.Valid := [rcpShading];
  Result.Shading := AColor;
end;

{ A table of 10,000 rows: a column's edge moved in every row (the rich edit's own door, what a
  drag's release runs - one command), to the end of the paint after it; and a row's height. }
procedure TTyRichEditPerfTest.TestAColumnEdgeOfALongTable;
const
  Rows = 10000;
  // the suite's line for a whole column's change
  CColumnMs = 150;
var
  held, left, i: Integer;
  tbytes, lbytes: Int64;
  bmp: TBitmap;
  d: TTyRichDocument;
  t: TTyRichText;
  k: Integer;
  t0, col, again, row, dist: Double;
  e: TTyRichColumnEdges;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.Lines.Text := 'before' + LineEnding + 'after';
    d := FRich.Document;
    t := d.Text;
    AssertTrue('a long table', d.Execute(TTyRichInsertTable.Create(t.ParaStart(1), Rows, 3)));
    k := 1 + 3 * (Rows div 2);
    FRich.SelStart := t.ParaStart(k);
    TPerfRich(FRich).PaintInto(bmp);
    AssertTrue('the edges', FRich.CaretRowEdges(e) and (Length(e) = 4));
    t0 := Clock;
    AssertTrue('a column''s edge', FRich.MoveCaretRowEdge(e[1].Index, e[1].Offset + 300, False));
    TPerfRich(FRich).PaintInto(bmp);
    col := Clock - t0;
    Report(Format('table of %d rows: a column''s edge in every row, to the end of its paint', [Rows]), col);
    AssertEquals('every row', d.CellAt(1).Row.CellEdges[0], d.CellAt(3 * (Rows - 1) + 1).Row.CellEdges[0]);
    // again, the next edge with the rest following
    t0 := Clock;
    AssertTrue('again', FRich.MoveCaretRowEdge(e[2].Index, e[2].Offset - 200, True));
    TPerfRich(FRich).PaintInto(bmp);
    again := Clock - t0;
    Report('table: another edge with the rest following, to the end of its paint', again);
    // one row's height
    t0 := Clock;
    AssertTrue('a height', FRich.SetRowHeight(600, False));
    TPerfRich(FRich).PaintInto(bmp);
    row := Clock - t0;
    Report('table: one row''s height, to the end of its paint', row);
    // every row as high as their average (each row laid out to read its height): reported
    t0 := Clock;
    AssertTrue('rows alike', FRich.DistributeRows);
    TPerfRich(FRich).PaintInto(bmp);
    dist := Clock - t0;
    Report('table: the rows made alike (DistributeRows), to the end of its paint', dist);
    { memory: 30 whole-column edits keep their row versions for their undo steps; the steps
      cleared, they go - the rows of now and the reader's are left }
    for i := 1 to 30 do
      d.Execute(TTyRichSetCellProps.Create(t.ParaStart(1), 0, 1, Rows - 1, 1,
        ShadingProps(RGBToColor(i * 8, 200, 120))));
    d.BeginRead;
    try
      held := d.CellAt(1).Row.Table.LiveRowCount;
      tbytes := d.CellAt(1).Row.Table.MemSize;
    finally
      d.EndRead;
    end;
    d.ClearUndo;
    d.BeginRead;
    try
      left := d.CellAt(1).Row.Table.LiveRowCount;
      lbytes := d.CellAt(1).Row.Table.MemSize;
    finally
      d.EndRead;
    end;
    WriteLn(Format('TTyRichEditPerfTest: table: 30 whole-column edits hold %d row objects ' +
      '(%.1f MB); ClearUndo leaves %d (%.1f MB)', [held, tbytes / 1048576, left, lbytes / 1048576]));
    AssertEquals('the steps gone: the rows of now and the reader''s', 2 * Rows, left);
    AssertTrue(Format('a column in %.1f ms', [col]), col <= CColumnMs);
    AssertTrue(Format('again in %.1f ms', [again]), again <= CColumnMs);
    AssertTrue(Format('a row in %.1f ms', [row]), row <= CKeystrokeMs);
  finally
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TTyRichEditPerfTest);

end.
