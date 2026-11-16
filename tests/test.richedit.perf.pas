unit test.richedit.perf;

{ TTyRichEditPerfTest: the one suite that asserts the wall clock (the gate runs it alone, in its
  serial list). The acceptance lines are the design's - a 100 MB txt and a 100 MB RTF show
  their first screen in 1 s and any scroll position in 100 ms; Task 16's bench measures them on
  the user's machine - and the thresholds here are three times them: 3 s and 300 ms.

  How it paints: the control with no window, painted by PaintArea into an off-screen bitmap
  as a window paint (deferred pictures, the kept surface brought up to date and blitted) - the
  very path Paint takes, with the real text device (the package's fonts and renderer), not the
  layout tests' device. What a window adds - the system's own copy to the screen - is left
  out. No window is shown, nothing takes the foreground.

  The files (about 100 MB each) are made by the test under the system's temporary folder with
  names of their own, and deleted in TearDown whatever happened; making them is not timed.
  With less free room than they need the test is skipped with a message. The times and the
  process's peak working set are printed (the gate's log keeps them); memory is not asserted
  here. }

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
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestA100MBTextFileFirstScreenAndMiddle;
    procedure TestA100MBRtfFileFirstScreenAndMiddle;
  end;

implementation

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

type
  TPerfRich = class(TTyRichEdit)
  public
    procedure PaintInto(ABitmap: TBitmap);
  end;

procedure TPerfRich.PaintInto(ABitmap: TBitmap);
begin
  PaintArea(ABitmap.Canvas, Rect(0, 0, Width, Height), Rect(0, 0, Width, Height), 96, True);
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

{ A 100 MB txt: LoadFromFile to the end of the first paint within 3 s; then the scroll position
  set to the middle of the document and painted within 300 ms. }
procedure TTyRichEditPerfTest.TestA100MBTextFileFirstScreenAndMiddle;
var
  path: string;
  bmp: TBitmap;
  t0, first, middle: Double;
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
    AssertTrue(Format('the first screen in %.0f ms', [first]), first <= CFirstScreenMs);
    AssertTrue(Format('the middle in %.0f ms', [middle]), middle <= CScrollMs);
    AssertTrue('the view is in the middle', FRich.TopParagraph > FRich.Document.Text.ParaCount div 4);
  finally
    bmp.Free;
  end;
end;

{ A 100 MB RTF, the lazy path: LoadFromFile (the first slice indexed) to the end of the first
  paint within 3 s. Then, the load still going on, the scroll position set to the middle of what
  is indexed so far - half the height of the paragraphs the load has appended until then - and
  painted within 300 ms. Last (printed, and held to the same 300 ms), the rest of the file
  indexed (not timed) and the middle of the whole document. }
procedure TTyRichEditPerfTest.TestA100MBRtfFileFirstScreenAndMiddle;
var
  path: string;
  bmp: TBitmap;
  t0, first, middle, whole: Double;
  loading: Boolean;
  indexed, midTop: Integer;
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

initialization
  RegisterTest(TTyRichEditPerfTest);

end.
