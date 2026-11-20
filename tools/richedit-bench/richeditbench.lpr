program richeditbench;
{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}
{ The rich edit's large-file bench: measures the figures of the design's section 3.9 on the
  machine it runs on, each one in a fresh process per run, and prints them against the
  design's own lines (the performance suite holds them to three times those; this does not).

  The parent makes the input files (deterministic, no clock, no random source but a fixed
  seed), then for each file runs itself as a child once per run: the child loads the file
  into a TTyRichEdit with no window, paints it into an off-screen bitmap the way a window
  paint does (TTyCustomRichEdit.PaintArea, pictures deferred - the very path Paint takes),
  measures, and writes what it found to a result file. No window is shown, nothing takes the
  foreground, the clipboard is never touched. Before each run the processor's load is
  sampled; a run that starts above 15 % is waited for and tried again, and marked busy when
  the machine stays busy. See README.md for the switches and the figures. }

uses
  Interfaces, Classes, SysUtils, Math, Types, Forms, Controls, Graphics, LCLType,
  Process, LConvEncoding, FPImage, FPWriteJPEG,
  BGRABitmap, BGRABitmapTypes,
  {$IFDEF MSWINDOWS}Registry,{$ENDIF}
  tyControls.Controller, tyControls.RichEdit, tyControls.RichEdit.Text,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.Model, tyControls.RichEdit.Find;

const
  MB = 1024 * 1024;
  CSeed = 20261108;
  CBusyPercent = 15.0;
  CBusyTries = 6;
  CBusyWaitMs = 10000;
  CKinds: array[0..5] of string = ('utf8', 'gbk', 'rtf', 'pictures', 'fields', 'equations');
  // the plan's four; the others are reported apart
  CAcceptance: array[0..5] of Boolean = (True, True, True, True, False, False);
  CKindTitle: array[0..5] of string = (
    'txt, UTF-8',
    'txt, GBK',
    'RTF: Chinese and Latin text, formats, lists, tables',
    'RTF with 200 pictures (PNG and JPEG)',
    'RTF with 200,000 links and a 5,000-entry table of contents',
    'RTF with 2,000 equations');

var
  // the result files' numbers, whatever the locale
  FS: TFormatSettings;

{ ---- the platform ---------------------------------------------------------------- }

{$IFDEF MSWINDOWS}
type
  TMemCountersEx = record
    cb: LongWord;
    PageFaultCount: LongWord;
    PeakWorkingSetSize, WorkingSetSize: PtrUInt;
    QuotaPeakPagedPoolUsage, QuotaPagedPoolUsage: PtrUInt;
    QuotaPeakNonPagedPoolUsage, QuotaNonPagedPoolUsage: PtrUInt;
    PagefileUsage, PeakPagefileUsage: PtrUInt;
    PrivateUsage: PtrUInt;
  end;
  TMemStatusEx = record
    dwLength, dwMemoryLoad: LongWord;
    ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile: QWord;
    ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual: QWord;
  end;
  TOsVersionInfoW = record
    dwOSVersionInfoSize, dwMajorVersion, dwMinorVersion, dwBuildNumber, dwPlatformId: LongWord;
    szCSDVersion: array[0..127] of WideChar;
  end;
  TLogicalProcInfo = record
    ProcessorMask: PtrUInt;
    Relationship: LongWord;
    {$IFDEF CPU64}Pad: LongWord;{$ENDIF}
    Union: array[0..1] of QWord;
  end;

function QueryPerformanceCounter(out ACount: Int64): LongBool; stdcall;
  external 'kernel32' name 'QueryPerformanceCounter';
function QueryPerformanceFrequency(out AFreq: Int64): LongBool; stdcall;
  external 'kernel32' name 'QueryPerformanceFrequency';
function GetCurrentProcess: THandle; stdcall; external 'kernel32' name 'GetCurrentProcess';
function GetProcessMemoryInfo(AProcess: THandle; var ACounters: TMemCountersEx;
  ASize: LongWord): LongBool; stdcall; external 'psapi' name 'GetProcessMemoryInfo';
function GetSystemTimes(out AIdle, AKernel, AUser: QWord): LongBool; stdcall;
  external 'kernel32' name 'GetSystemTimes';
function GlobalMemoryStatusEx(var AStatus: TMemStatusEx): LongBool; stdcall;
  external 'kernel32' name 'GlobalMemoryStatusEx';
function RtlGetVersion(var AInfo: TOsVersionInfoW): LongInt; stdcall;
  external 'ntdll' name 'RtlGetVersion';
function GetLogicalProcessorInformation(ABuffer: Pointer; var ALength: LongWord): LongBool;
  stdcall; external 'kernel32' name 'GetLogicalProcessorInformation';
function GetDiskFreeSpaceExW(ADir: PWideChar; out AAvail, ATotal, AFree: QWord): LongBool;
  stdcall; external 'kernel32' name 'GetDiskFreeSpaceExW';
{$ENDIF}

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

{ Working set, private bytes and their peaks, in MB (0 where the platform does not say). }
procedure Memory(out AWs, APriv, APeakWs, APeakPriv: Double);
{$IFDEF MSWINDOWS}
var
  m: TMemCountersEx;
begin
  FillChar(m, SizeOf(m), 0);
  m.cb := SizeOf(m);
  if GetProcessMemoryInfo(GetCurrentProcess, m, SizeOf(m)) then
  begin
    AWs := m.WorkingSetSize / MB;
    APriv := m.PrivateUsage / MB;
    APeakWs := m.PeakWorkingSetSize / MB;
    APeakPriv := m.PeakPagefileUsage / MB;
  end
  else
  begin
    AWs := 0; APriv := 0; APeakWs := 0; APeakPriv := 0;
  end;
end;
{$ELSE}
begin
  AWs := 0; APriv := 0; APeakWs := 0; APeakPriv := 0;
end;
{$ENDIF}

{ The whole machine's processor load over AMs milliseconds, in percent (-1: not known). }
function CpuLoad(AMs: Integer): Double;
{$IFDEF MSWINDOWS}
var
  i0, k0, u0, i1, k1, u1: QWord;
  busy, total: Double;
begin
  Result := -1;
  if not GetSystemTimes(i0, k0, u0) then Exit;
  Sleep(AMs);
  if not GetSystemTimes(i1, k1, u1) then Exit;
  // kernel time includes idle time
  total := (k1 - k0) + (u1 - u0);
  busy := total - (i1 - i0);
  if total > 0 then Result := 100 * busy / total else Result := 0;
end;
{$ELSE}
begin
  Sleep(AMs);
  Result := -1;
end;
{$ENDIF}

function FreeRoom(const ADir: string): Int64;
{$IFDEF MSWINDOWS}
var
  a, t, f: QWord;
begin
  if GetDiskFreeSpaceExW(PWideChar(UnicodeString(ADir)), a, t, f) then Result := a
  else Result := -1;
end;
{$ELSE}
begin
  Result := -1;
end;
{$ENDIF}

function MachineLines: TStringList;
{$IFDEF MSWINDOWS}
var
  r: TRegistry;
  cpu, prod, disp: string;
  ubr: Integer;
  ms: TMemStatusEx;
  v: TOsVersionInfoW;
  len: LongWord;
  buf: array of TLogicalProcInfo;
  i, cores: Integer;
{$ENDIF}
begin
  Result := TStringList.Create;
  {$IFDEF MSWINDOWS}
  cpu := 'not known'; prod := ''; disp := ''; ubr := -1;
  r := TRegistry.Create(KEY_READ);
  try
    r.RootKey := HKEY_LOCAL_MACHINE;
    if r.OpenKeyReadOnly('HARDWARE\DESCRIPTION\System\CentralProcessor\0') then
    begin
      if r.ValueExists('ProcessorNameString') then cpu := Trim(r.ReadString('ProcessorNameString'));
      r.CloseKey;
    end;
    if r.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows NT\CurrentVersion') then
    begin
      if r.ValueExists('ProductName') then prod := r.ReadString('ProductName');
      if r.ValueExists('DisplayVersion') then disp := r.ReadString('DisplayVersion')
      else if r.ValueExists('ReleaseId') then disp := r.ReadString('ReleaseId');
      if r.ValueExists('UBR') then ubr := r.ReadInteger('UBR');
      r.CloseKey;
    end;
  finally
    r.Free;
  end;
  cores := 0;
  len := 0;
  GetLogicalProcessorInformation(nil, len);
  if len > 0 then
  begin
    SetLength(buf, len div SizeOf(TLogicalProcInfo) + 1);
    if GetLogicalProcessorInformation(@buf[0], len) then
      for i := 0 to Integer(len div SizeOf(TLogicalProcInfo)) - 1 do
        // RelationProcessorCore
        if buf[i].Relationship = 0 then Inc(cores);
  end;
  FillChar(ms, SizeOf(ms), 0);
  ms.dwLength := SizeOf(ms);
  GlobalMemoryStatusEx(ms);
  FillChar(v, SizeOf(v), 0);
  v.dwOSVersionInfoSize := SizeOf(v);
  RtlGetVersion(v);
  Result.Add('CPU: ' + cpu);
  Result.Add(Format('Cores: %d physical, %d logical', [cores, TThread.ProcessorCount]));
  Result.Add(Format('Memory: %.1f GB, %.1f GB free at the start', [ms.ullTotalPhys / (1024.0 * MB),
    ms.ullAvailPhys / (1024.0 * MB)]));
  Result.Add(Format('Windows: %s %s, %d.%d.%d.%d', [prod, disp, v.dwMajorVersion, v.dwMinorVersion,
    v.dwBuildNumber, ubr]));
  {$ELSE}
  Result.Add('CPU: not known on this platform');
  Result.Add(Format('Cores: %d logical', [TThread.ProcessorCount]));
  {$ENDIF}
  Result.Add('Built: FPC ' + {$I %FPCVERSION%} + ', ' + {$I %FPCTARGETCPU%} + '-' +
    {$I %FPCTARGETOS%} + ', optimisation ' +
    {$IF DEFINED(TY_BENCH_O1)}'-O1'{$ELSEIF DEFINED(TY_BENCH_O2)}'-O2'
    {$ELSEIF DEFINED(TY_BENCH_O3)}'-O3'{$ELSE}'not known (the project file names it)'{$ENDIF} +
    ', on ' + {$I %DATE%});
end;

{ ---- the input files ------------------------------------------------------------- }

type
  TSeed = record
    X: Cardinal;
  end;

function NextRand(var S: TSeed): Cardinal;
begin
  // xorshift32
  S.X := S.X xor (S.X shl 13);
  S.X := S.X xor (S.X shr 17);
  S.X := S.X xor (S.X shl 5);
  Result := S.X;
end;

function U8(ACode: Cardinal): RawByteString;
begin
  if ACode < $80 then Result := AnsiChar(ACode)
  else if ACode < $800 then
    Result := AnsiChar($C0 or (ACode shr 6)) + AnsiChar($80 or (ACode and $3F))
  else
    Result := AnsiChar($E0 or (ACode shr 12)) + AnsiChar($80 or ((ACode shr 6) and $3F)) +
      AnsiChar($80 or (ACode and $3F));
end;

procedure WriteRaw(AStream: TStream; const S: RawByteString);
begin
  if S <> '' then AStream.WriteBuffer(S[1], Length(S));
end;

{ RTF written with | for each backslash (this file keeps its RTF readable that way). }
function Bar(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  Result := S;
  UniqueString(Result);
  for i := 1 to Length(Result) do
    if Result[i] = '|' then Result[i] := #92;
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

{ A buffer spilled to the file at every megabyte. }
type
  TSpill = class
    F: TFileStream;
    Buf: TMemoryStream;
    constructor Create(const APath: string);
    destructor Destroy; override;
    procedure Add(const S: RawByteString);
    function Size: Int64;
  end;

constructor TSpill.Create(const APath: string);
begin
  F := TFileStream.Create(APath, fmCreate);
  Buf := TMemoryStream.Create;
end;

destructor TSpill.Destroy;
begin
  if Buf.Size > 0 then F.WriteBuffer(Buf.Memory^, Buf.Size);
  Buf.Free;
  F.Free;
  inherited Destroy;
end;

procedure TSpill.Add(const S: RawByteString);
begin
  WriteRaw(Buf, S);
  if Buf.Size > MB then
  begin
    F.WriteBuffer(Buf.Memory^, Buf.Size);
    Buf.Clear;
  end;
end;

function TSpill.Size: Int64;
begin
  Result := F.Size + Buf.Size;
end;

{ The performance suite's lines (Chinese and Latin mixed, CRLF, about 50 bytes on average:
  two million lines in 100 MB), to ABytes in UTF-8 or, AGbk, the same lines in GBK to ABytes
  of GBK. }
procedure MakeText(const APath: string; ABytes: Int64; AGbk: Boolean);
var
  sp: TSpill;
  zh, line, chunk: RawByteString;
  n: Integer;
begin
  zh := U8($4E2D) + U8($6587) + U8($6587) + U8($672C) + U8($6D4B) + U8($8BD5) + U8($7684) +
    U8($4E00) + U8($884C);
  sp := TSpill.Create(APath);
  try
    n := 0;
    chunk := '';
    while sp.Size + Length(chunk) < ABytes do
    begin
      Inc(n);
      // the suite's three kinds and two short ones: 50 bytes a line on average
      case n mod 5 of
        0: line := 'Line ' + IntToStr(n) + ' of the generated file: some ordinary words, ' + zh +
             ' and a few more words to end it.';
        1: line := zh + zh + ' ' + IntToStr(n) + ' ' + zh;
        2: line := 'A shorter Latin line ' + IntToStr(n) + '.';
        3: line := U8($7B2C) + ' ' + IntToStr(n) + ' ' + U8($884C);
      else
        line := IntToStr(n) + '.';
      end;
      if AGbk then line := UTF8ToCP936(line);
      chunk := chunk + line + #13#10;
      if Length(chunk) > 256 * 1024 then
      begin
        sp.Add(chunk);
        chunk := '';
      end;
    end;
    sp.Add(chunk);
  finally
    sp.Free;
  end;
end;

const
  CRtfHead = '{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fswiss|fcharset0 Arial;}' +
    '{|f1|fnil|fcharset134 SimSun;}{|f2|fnil|fcharset2 Symbol;}}' + #13#10 +
    '{|colortbl ;|red200|green0|blue0;|red0|green0|blue255;}' + #13#10;
  // a bullet list (ls1) and a numbered one (ls2), as Word writes them
  CRtfLists = '{|*|listtable{|list|listtemplateid1|listhybrid{|listlevel|levelnfc23|levelnfcn23' +
    '|leveljc0|leveljcn0|levelfollow0|levelstartat1|levelspace0|levelindent0{|leveltext' +
    '|leveltemplateid2|''01|u-3913 ?;}{|levelnumbers;}|f2|fbias0 |fi-420|li420|lin420 }{|listname ;}' +
    '|listid100}{|list|listtemplateid3|listhybrid{|listlevel|levelnfc0|levelnfcn0|leveljc0|leveljcn0' +
    '|levelfollow0|levelstartat1|levelspace0|levelindent0{|leveltext|leveltemplateid4|''02|''00.;}' +
    '{|levelnumbers|''01;}|fi-420|li420|lin420 }{|listname ;}|listid200}}' +
    '{|*|listoverridetable{|listoverride|listid100|listoverridecount0|ls1}' +
    '{|listoverride|listid200|listoverridecount0|ls2}}' + #13#10;

function PlainPara(N: Integer): RawByteString;
begin
  Result := Bar('Paragraph ' + IntToStr(N) + ' with |b bold|b0  and |cf1 coloured|cf0  words, ' +
    '|f1|u20013?|u25991?|u27979?|u35797?|f0  and more text.|par') + #13#10;
end;

{ About ABytes of RTF: in every hundred paragraphs, 84 of the performance suite's formatted
  paragraphs (Latin, Chinese as \uN in SimSun, bold, colour), a bullet list of five items, a
  numbered list of five, and a table of two rows of three cells. }
procedure MakeRtf(const APath: string; ABytes: Int64);
var
  sp: TSpill;
  n, k, r, c: Integer;
begin
  sp := TSpill.Create(APath);
  try
    sp.Add(Bar(CRtfHead + CRtfLists + '|viewkind4|uc1|pard|f0|fs20 '));
    n := 0;
    while sp.Size < ABytes do
    begin
      for k := 1 to 84 do
      begin
        Inc(n);
        sp.Add(PlainPara(n));
      end;
      for k := 1 to 5 do
      begin
        Inc(n);
        sp.Add(Bar('|pard{|listtext|f2 |u-3913 ?|tab}|fi-420|li420|ls1 Item ' + IntToStr(n) +
          ' of a bullet list, |i italic|i0  and |f1|u21015?|u34920?|f0 .|par') + #13#10);
      end;
      for k := 1 to 5 do
      begin
        Inc(n);
        sp.Add(Bar('|pard{|listtext ' + IntToStr(k) + '.|tab}|fi-420|li420|ls2 Step ' +
          IntToStr(n) + ' of a numbered list, |ul underlined|ulnone  |f1|u32534?|u21495?|f0 .|par') +
          #13#10);
      end;
      for r := 1 to 2 do
      begin
        sp.Add(Bar('|trowd|trgaph108|trleft0|cellx3000|cellx6000|cellx9000') + #13#10);
        for c := 1 to 3 do
        begin
          Inc(n);
          sp.Add(Bar('|pard|intbl Cell ' + IntToStr(n) + ' |f1|u34920?|u26684?|f0 |cell') + #13#10);
        end;
        sp.Add(Bar('|row') + #13#10);
      end;
      sp.Add(Bar('|pard|f0|fs20 '));
    end;
    sp.Add('}' + #13#10);
  finally
    sp.Free;
  end;
end;

function HexOf(const AData: TBytes): RawByteString;
const
  D: array[0..15] of AnsiChar = '0123456789abcdef';
var
  i, o: Integer;
begin
  // 64 bytes (128 digits) a line, CRLF
  SetLength(Result, Length(AData) * 2 + (Length(AData) div 64 + 1) * 2);
  o := 1;
  for i := 0 to High(AData) do
  begin
    if (i > 0) and (i mod 64 = 0) then
    begin
      Result[o] := #13; Result[o + 1] := #10; Inc(o, 2);
    end;
    Result[o] := D[AData[i] shr 4];
    Result[o + 1] := D[AData[i] and 15];
    Inc(o, 2);
  end;
  SetLength(Result, o - 1);
end;

{ A PNG whose pixels do not compress (about AW x AH x 3 bytes), or a JPEG of a photograph's
  kind (smooth colour with grain, quality 90). }
function MakePicture(AW, AH: Integer; AJpeg: Boolean; ASeed: Cardinal): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
  p: PBGRAPixel;
  x, y, g: Integer;
  s: TSeed;
  w: TFPWriterJPEG;
begin
  s.X := ASeed or 1;
  b := TBGRABitmap.Create(AW, AH);
  st := TBytesStream.Create;
  try
    for y := 0 to AH - 1 do
    begin
      p := b.ScanLine[y];
      for x := 0 to AW - 1 do
      begin
        if AJpeg then
        begin
          g := Integer(NextRand(s) and 7) - 4;
          p^.red := EnsureRange(x * 255 div AW + g, 0, 255);
          p^.green := EnsureRange(y * 255 div AH + g, 0, 255);
          p^.blue := EnsureRange(128 + ((x + y) mod 97) + g, 0, 255);
        end
        else
        begin
          NextRand(s);
          p^.red := s.X and $FF;
          p^.green := (s.X shr 8) and $FF;
          p^.blue := (s.X shr 16) and $FF;
        end;
        p^.alpha := 255;
        Inc(p);
      end;
    end;
    b.InvalidateBitmap;
    if AJpeg then
    begin
      w := TFPWriterJPEG.Create;
      try
        w.CompressionQuality := 90;
        b.SaveToStream(st, w);
      finally
        w.Free;
      end;
    end
    else
      b.SaveToStreamAs(st, ifPng);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

{ An RTF of APictures pictures, PNG and JPEG by turns, of eight sizes from 200 x 150 to
  2400 x 1600 (from about 0.1 MB to a few MB each), each after fifteen of the suite's
  paragraphs, shown at most 600 pixels wide. AQuick: the small four sizes only.
  APicBytes: the total of the pictures' bytes. }
procedure MakePicturesRtf(const APath: string; APictures: Integer; AQuick: Boolean;
  out APicBytes: Int64);
const
  W: array[0..7] of Integer = (320, 1600, 640, 800, 200, 2400, 640, 1024);
  H: array[0..7] of Integer = (240, 1200, 480, 600, 150, 1600, 360, 768);
  Jpg: array[0..7] of Boolean = (False, True, False, True, False, True, False, True);
  Small: array[0..3] of Integer = (0, 3, 4, 7);
var
  sp: TSpill;
  i, k, n, kind, gw, gh: Integer;
  data: TBytes;
begin
  APicBytes := 0;
  sp := TSpill.Create(APath);
  try
    sp.Add(Bar(CRtfHead + '|viewkind4|uc1|pard|f0|fs20 '));
    n := 0;
    for i := 0 to APictures - 1 do
    begin
      for k := 1 to 15 do
      begin
        Inc(n);
        sp.Add(PlainPara(n));
      end;
      if AQuick then kind := Small[i mod 4] else kind := i mod 8;
      data := MakePicture(W[kind], H[kind], Jpg[kind], CSeed + Cardinal(i) * 7919);
      Inc(APicBytes, Length(data));
      gw := Min(W[kind], 600);
      gh := H[kind] * gw div W[kind];
      sp.Add(Bar('|pard Picture ' + IntToStr(i + 1) + ': {|pict|picw' + IntToStr(W[kind]) + '|pich' +
        IntToStr(H[kind]) + '|picwgoal' + IntToStr(gw * 15) + '|pichgoal' + IntToStr(gh * 15) +
        BoolToStr(Jpg[kind], '|jpegblip', '|pngblip') + ' ') + #13#10);
      sp.Add(HexOf(data));
      sp.Add(Bar('}|par') + #13#10);
      Inc(n);
    end;
    for k := 1 to 15 do
    begin
      Inc(n);
      sp.Add(PlainPara(n));
    end;
    sp.Add('}' + #13#10);
  finally
    sp.Free;
  end;
end;

{ The performance suite's file of fields: ALinks hyperlinks (two a paragraph, their results
  Chinese, underlined, coloured), a table of contents of AEntries entries after the first half
  of them, then plain paragraphs to ABytes. }
procedure MakeFieldsRtf(const APath: string; ABytes: Int64; ALinks, AEntries: Integer);
var
  sp: TSpill;
  n, i, para: Integer;

  function Link(AN: Integer): RawByteString;
  begin
    Result := Bar('{|field{|*|fldinst HYPERLINK "http://example.com/page' + IntToStr(AN) +
      '"}{|fldrslt {|cs15|ul|cf2|f1 |u38142?|u25509?' + IntToStr(AN) + '}}}');
  end;

  procedure Links(ACount: Integer);
  var
    k: Integer;
  begin
    for k := 1 to ACount div 2 do
    begin
      Inc(n, 2);
      sp.Add(Bar('|pard|f0 Paragraph ' + IntToStr(para) + ' links to ') + Link(n - 1) +
        Bar(' and to ') + Link(n) + Bar(' with more words after them.|par') + #13#10);
      Inc(para);
    end;
  end;

begin
  sp := TSpill.Create(APath);
  try
    sp.Add(Bar(CRtfHead + '|viewkind4|uc1|pard|f0|fs20 '));
    n := 0;
    para := 0;
    Links(ALinks div 2);
    sp.Add(Bar('|pard|tqr|tldot|tx8000 Contents: {|field|fldedit{|*|fldinst TOC ||o "1-3" ||h}{|fldrslt '));
    for i := 1 to AEntries do
    begin
      sp.Add(Bar('{|field{|*|fldinst HYPERLINK ||l "_Toc' + IntToStr(i) + '"}{|fldrslt ' +
        '{|cs15|ul|cf2|f1 |u31532?' + IntToStr(i) + '|u31456? Chapter ' + IntToStr(i) + '|tab ' +
        '{|field{|*|fldinst PAGEREF _Toc' + IntToStr(i) + ' ||h}{|fldrslt ' + IntToStr(3 * i) + '}}}}}'));
      if i < AEntries then sp.Add(Bar('|par |pard|tqr|tldot|tx8000 ') + #13#10);
      Inc(para);
    end;
    sp.Add(Bar('}} and the text after it.|par') + #13#10);
    sp.Add(Bar('|pard|f0 The paragraph after the contents.|par') + #13#10);
    Inc(para);
    Links(ALinks - ALinks div 2);
    while sp.Size < ABytes do
    begin
      sp.Add(Bar('|pard ') + PlainPara(para));
      Inc(para);
    end;
    sp.Add('}' + #13#10);
  finally
    sp.Free;
  end;
end;

{ The performance suite's file of equations: AEquations of Word's equations spread over the
  suite's paragraphs, each its words and the picture Word keeps beside them. }
procedure MakeEquationsRtf(const APath: string; ABytes: Int64; AEquations: Integer);
var
  sp: TSpill;
  n, para, every, x: Integer;
  eq: RawByteString;
  b: TBGRABitmap;
  st: TBytesStream;
begin
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
    eq := Bar('{|mmath{|*|moMath{|mr|i E=m}{|msSup{|me{|mr c}}{|msup{|mr 2}}}}' +
      '{|mmathPict{|*|shppict{|pict{|*|picprop|shplid1025{|sp{|sn shapeType}{|sv 75}}}' +
      '|picscalex100|picscaley100|picw112|pich48|picwgoal840|pichgoal360|pngblip ') + #13#10 +
      HexOf(Copy(st.Bytes, 0, st.Size)) +
      Bar('}}{|nonshppict{|pict|picscalex100|picscaley100|picw1482|pich635|picwgoal840|pichgoal360' +
      '|wmetafile8 010009000003220000000000050000000000040000000301080005000000130200000000' +
      '030000000000}}}}');
  finally
    st.Free;
    b.Free;
  end;
  every := Max(1, (ABytes div 150) div (AEquations + 1));
  sp := TSpill.Create(APath);
  try
    sp.Add(Bar('{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fswiss|fcharset0 Arial;}' +
      '{|f1|fnil|fcharset134 SimSun;}{|f34|froman|fcharset0 Cambria Math;}}' + #13#10 +
      '{|colortbl ;|red200|green0|blue0;}' + #13#10 + '|viewkind4|uc1|pard|f0|fs20 '));
    n := 0;
    para := 0;
    while sp.Size < ABytes do
    begin
      if (para mod every = every div 2) and (n < AEquations) then
      begin
        sp.Add('Paragraph ' + IntToStr(para) + ' holds an equation: ' + eq +
          ' and more text after it.' + Bar('|par') + #13#10);
        Inc(n);
      end
      else
        sp.Add(PlainPara(para));
      Inc(para);
    end;
    sp.Add('}' + #13#10);
  finally
    sp.Free;
  end;
end;

{ ---- the child: one run of one file ---------------------------------------------- }

type
  TBenchRich = class(TTyRichEdit)
  public
    procedure PaintInto(ABitmap: TBitmap);
    procedure TypeChar(AChar: Char);
    procedure Key(AKey: Word; AShift: TShiftState);
    function Step: Boolean;
  end;

procedure TBenchRich.PaintInto(ABitmap: TBitmap);
begin
  // a window's paint: deferred pictures, the kept surface brought up to date and blitted
  PaintArea(ABitmap.Canvas, Rect(0, 0, Width, Height), Rect(0, 0, Width, Height), 96, True);
end;

procedure TBenchRich.TypeChar(AChar: Char);
var
  k: TUTF8Char;
begin
  k := AChar;
  UTF8KeyPress(k);
end;

procedure TBenchRich.Key(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

function TBenchRich.Step: Boolean;
begin
  Result := StepBackground;
end;

type
  TChild = class
    Kind: string;
    Path, ResultPath: string;
    W, H: Integer;
    Res: TStringList;
    Ctl: TTyStyleController;
    Rich: TBenchRich;
    Bmp: TBitmap;
    procedure Put(const AKey: string; AValue: Double);
    procedure PutText(const AKey, AValue: string);
    function Shot: QWord;
    function Text: TTyRichText;
    { The view at height AY painted (timed); 1 in APainted when the pixels changed. Put
      beside it as AKey_layout: the part until the view was laid out (UpdateView, what the
      paint would do first); AKey_parsed: the RTF bytes parsed for it. }
    function ViewAt(const AKey: string; AY: Int64; out APainted: Boolean): Double;
    { The caret put at paragraph APara (+3 characters), painted (not timed); then AChar typed
      (#8: Backspace) and the paint after it, timed. AKeyOnly: to the end of the key alone. }
    function Keystroke(APara: Integer; AChar: Char; out AKeyOnly: Double;
      out APainted, AChanged: Boolean): Double;
    procedure Mem(const ATag: string);
    procedure Run;
  end;

procedure TChild.Put(const AKey: string; AValue: Double);
begin
  Res.Values[AKey] := FloatToStr(AValue, FS);
  Res.SaveToFile(ResultPath);
end;

procedure TChild.PutText(const AKey, AValue: string);
begin
  Res.Values[AKey] := AValue;
  Res.SaveToFile(ResultPath);
end;

function TChild.Shot: QWord;
var
  b: TBGRABitmap;
  p: PCardinal;
  i: Integer;
begin
  // FNV-1a over the painted pixels: did the paint change them
  Result := QWord($CBF29CE484222325);
  // read through the canvas each time (a copy made from the TBitmap's own image would be the
  // one it took at the first read)
  b := TBGRABitmap.Create(W, H);
  try
    b.GetImageFromCanvas(Bmp.Canvas, 0, 0);
    p := PCardinal(b.Data);
    for i := 0 to b.NbPixels - 1 do
    begin
      Result := (Result xor p^) * QWord($100000001B3);
      Inc(p);
    end;
  finally
    b.Free;
  end;
end;

function TChild.Text: TTyRichText;
begin
  Result := Rich.Document.Text;
end;

function TChild.ViewAt(const AKey: string; AY: Int64; out APainted: Boolean): Double;
var
  before: QWord;
  t0, lay: Double;
  load: TTyRtfLoad;
  parsed: Int64;
begin
  before := Shot;
  load := TyRichRtfLoadOf(Rich.Document);
  if load <> nil then parsed := load.ParsedBytes else parsed := 0;
  t0 := Clock;
  Rich.ScrollY := AY;
  Rich.UpdateView;
  lay := Clock - t0;
  Rich.PaintInto(Bmp);
  Result := Clock - t0;
  APainted := Shot <> before;
  Put(AKey + '_layout', lay);
  if load <> nil then Put(AKey + '_parsed', load.ParsedBytes - parsed);
end;

function TChild.Keystroke(APara: Integer; AChar: Char; out AKeyOnly: Double;
  out APainted, AChanged: Boolean): Double;
var
  t0: Double;
  at: TTyRichPos;
  depth: Integer;
  before: QWord;
begin
  if APara >= Text.ParaCount then APara := Text.ParaCount - 1;
  if APara < 0 then APara := 0;
  at := Text.ParaStart(APara) + Min(Int64(3), Text.ParaLength(APara));
  Rich.SelStart := at;
  Rich.ScrollCaretIntoView;
  Rich.PaintInto(Bmp);
  depth := Rich.Document.UndoDepth;
  before := Shot;
  t0 := Clock;
  if AChar = #8 then Rich.Key(VK_BACK, []) else Rich.TypeChar(AChar);
  AKeyOnly := Clock - t0;
  Rich.PaintInto(Bmp);
  Result := Clock - t0;
  APainted := Shot <> before;
  AChanged := Rich.Document.UndoDepth = depth + 1;
end;

procedure TChild.Mem(const ATag: string);
var
  ws, pv, pws, ppv: Double;
begin
  Memory(ws, pv, pws, ppv);
  Put('ws_' + ATag, ws);
  Put('priv_' + ATag, pv);
  if ATag = 'end' then
  begin
    Put('ws_peak', pws);
    Put('priv_peak', ppv);
  end;
end;

function SameFiles(const A, B: string): Boolean;
var
  fa, fb: TFileStream;
  ba, bb: array of Byte;
  na, nb: Integer;
begin
  Result := False;
  fa := TFileStream.Create(A, fmOpenRead or fmShareDenyWrite);
  fb := TFileStream.Create(B, fmOpenRead or fmShareDenyWrite);
  try
    if fa.Size <> fb.Size then Exit;
    SetLength(ba, MB);
    SetLength(bb, MB);
    repeat
      na := fa.Read(ba[0], MB);
      nb := fb.Read(bb[0], MB);
      if (na <> nb) or ((na > 0) and not CompareMem(@ba[0], @bb[0], na)) then Exit;
    until na = 0;
    Result := True;
  finally
    fb.Free;
    fa.Free;
  end;
end;

procedure TChild.Run;
var
  t0, d, keyOnly, stepMax: Double;
  painted, changed, rtf: Boolean;
  load: TTyRtfLoad;
  y, total: Int64;
  i, parses, top: Integer;
  misses: Int64;
  f: TTyRichFinder;
  r: TTyRichFindResult;
  outPath: string;
  s: UTF8String;
  raw, expect: RawByteString;
  checks: string;

  procedure Check(AOk: Boolean; const AWhat: string);
  begin
    if not AOk then
    begin
      if checks <> '' then checks := checks + '; ';
      checks := checks + AWhat;
      PutText('checks', checks);
    end;
  end;

begin
  checks := '';
  rtf := (Kind <> 'utf8') and (Kind <> 'gbk');
  Put('file_mb', SizeOfFile(Path) / MB);
  Bmp := TBitmap.Create;
  Bmp.PixelFormat := pf32bit;
  Bmp.SetSize(W, H);
  Ctl := TTyStyleController.Create(nil);
  Rich := TBenchRich.Create(nil);
  try
    Rich.Controller := Ctl;
    Rich.Font.PixelsPerInch := 96;
    Rich.SetBounds(0, 0, W, H);
    Mem('start');

    // the first screen: from the call to the end of the first paint
    t0 := Clock;
    Rich.LoadFromFile(Path);
    Rich.PaintInto(Bmp);
    Put('first', Clock - t0);
    Mem('load');
    Put('paras_first', Text.ParaCount);
    Put('decodes_first', Rich.Layouter.PictureDecodes);
    if not rtf then
    begin
      // the text was decoded as its encoding: the first line begins with two Chinese characters
      // (compared as bytes: U8 builds its strings untagged)
      raw := Text.GetText(Text.ParaStart(0), 2);
      expect := U8($4E2D) + U8($6587);
      SetCodePage(raw, CP_UTF8, False);
      SetCodePage(expect, CP_UTF8, False);
      Check(raw = expect, 'the text''s first characters are not what was written');
    end;
    load := TyRichRtfLoadOf(Rich.Document);
    if rtf then
    begin
      // (a file within the first slice, 4 MB, is read whole by the load)
      if SizeOfFile(Path) > 8 * MB then
        Check(Rich.Loading, 'the load was over at the first paint');
      // the load going on: the middle of what is indexed
      d := ViewAt('mid_loading', Text.TotalHeight div 2, painted);
      Put('mid_loading', d);
      Check(painted, 'the middle during the load painted nothing new');
      t0 := Clock;
      Rich.FinishLoading;
      Put('index_rest', Clock - t0);
    end;
    Put('paras', Text.ParaCount);

    // the middle of the whole document
    total := Text.TotalHeight;
    d := ViewAt('mid', total div 2, painted);
    Put('mid', d);
    Check(painted, 'the middle painted nothing new');
    Check(Rich.TopParagraph > Text.ParaCount div 4, 'the middle is not in the middle');
    // the pictures there made ready by the background work, and the paint that shows them
    i := Rich.Layouter.PictureDecodes;
    t0 := Clock;
    while Rich.Step do ;
    Rich.PaintInto(Bmp);
    Put('pics_ready', Clock - t0);
    Put('pics_ready_count', Rich.Layouter.PictureDecodes - i);

    // a place never shown before (cold: for an RTF, not parsed since the index)
    y := Round(total * 0.7371);
    misses := Rich.Layouter.CacheMisses;
    if load <> nil then parses := load.ParseCount else parses := 0;
    d := ViewAt('rand', y, painted);
    Put('rand', d);
    Check(painted, 'the random place painted nothing new');
    Check(Rich.Layouter.CacheMisses > misses, 'the random place was laid out before');
    if load <> nil then Check(load.ParseCount > parses, 'the random place was parsed before');
    top := Rich.TopParagraph;
    Put('rand_para', top);

    // Ctrl+End, to the end of its paint
    t0 := Clock;
    Rich.Key(VK_END, [ssCtrl]);
    Rich.PaintInto(Bmp);
    Put('end', Clock - t0);
    Check(Rich.TopParagraph > Text.ParaCount - 200, 'Ctrl+End did not reach the end');

    // other places shown (spread by the golden ratio) until the random place's layout has
    // left the cache (2,048 paragraphs kept), 24 at least - more than the RTF reader's 16
    // parsed intervals - and 400 at most (a small document keeps it all); then the random
    // place again
    i := 0;
    repeat
      Rich.ScrollY := Round(total * Frac(0.1 + i * 0.6180339887));
      Rich.PaintInto(Bmp);
      Inc(i);
    until ((i >= 24) and (Rich.Layouter.CachedLayout(top) = nil)) or (i >= 400);
    Put('evict_tour', i);
    misses := Rich.Layouter.CacheMisses;
    if load <> nil then parses := load.ParseCount;
    // (by its paragraph's top: the tour made estimated heights real, so the same height may be
    // another paragraph now)
    d := ViewAt('evict', Text.ParaTop(top), painted);
    Put('evict', d);
    Check(painted, 'the random place again painted nothing new');
    Check(Rich.Layouter.CacheMisses > misses, 'the random place''s layouts were not evicted');
    if load <> nil then Check(load.ParseCount > parses, 'the random place''s parse was not evicted');
    Check(Rich.TopParagraph = top, 'the random place again is not the same place');

    // a find of a string that is not there, in the background find's pieces
    s := 'qzxv-not-in-the-file';
    stepMax := 0;
    t0 := Clock;
    f := TTyRichFinder.Create(Rich.Document, s, [], 0, -1);
    try
      repeat
        d := Clock;
        r := f.Step(CRichFindStepChars);
        d := Clock - d;
        if d > stepMax then stepMax := d;
      until r <> rfrMore;
      Check(r = rfrNotFound, 'the find found the string that is not there');
    finally
      f.Free;
    end;
    Put('find', Clock - t0);
    Put('find_step', stepMax);

    // saved unchanged: byte for byte the file
    outPath := ChangeFileExt(ResultPath, '') + '-save' + ExtractFileExt(Path);
    t0 := Clock;
    Rich.SaveToFile(outPath);
    Put('save_same', Clock - t0);
    Check(SameFiles(Path, outPath), 'the unchanged save is not the file byte for byte');
    DeleteFile(outPath);
    Mem('all');

    // keystrokes: at the start (then the save after that one edit), in the middle (a
    // character and a Backspace), at the end
    Rich.Key(VK_HOME, [ssCtrl]);
    Rich.PaintInto(Bmp);
    d := Keystroke(2, 'x', keyOnly, painted, changed);
    Put('key_start', d);
    Put('key_start_keyonly', keyOnly);
    Check(painted and changed, 'the key at the start');
    t0 := Clock;
    Rich.SaveToFile(outPath);
    Put('save_edit', Clock - t0);
    Check(SizeOfFile(outPath) > 0, 'the save after the edit wrote nothing');
    DeleteFile(outPath);
    Rich.ScrollY := Text.TotalHeight div 2;
    Rich.PaintInto(Bmp);
    d := Keystroke(Rich.TopParagraph + 2, 'x', keyOnly, painted, changed);
    Put('key_mid', d);
    Put('key_mid_keyonly', keyOnly);
    Check(painted and changed, 'the key in the middle');
    d := Keystroke(Rich.TopParagraph + 6, #8, keyOnly, painted, changed);
    Put('del_mid', d);
    Put('del_mid_keyonly', keyOnly);
    Check(painted and changed, 'the Backspace in the middle');
    Rich.Key(VK_END, [ssCtrl]);
    Rich.PaintInto(Bmp);
    d := Keystroke(Text.ParaCount - 1, 'x', keyOnly, painted, changed);
    Put('key_end', d);
    Put('key_end_keyonly', keyOnly);
    Check(painted and changed, 'the key at the end');
    Put('decodes_end', Rich.Layouter.PictureDecodes);
    Mem('end');
    PutText('done', '1');
  finally
    Rich.Free;
    Ctl.Free;
    Bmp.Free;
  end;
end;

function ChildMain(const AKind, APath, AResult: string; AW, AH: Integer): Integer;
var
  c: TChild;
begin
  Result := 0;
  c := TChild.Create;
  c.Res := TStringList.Create;
  try
    c.Kind := AKind;
    c.Path := APath;
    c.ResultPath := AResult;
    c.W := AW;
    c.H := AH;
    try
      c.Run;
    except
      on E: Exception do
      begin
        c.PutText('error', E.ClassName + ': ' + StringReplace(E.Message, LineEnding, ' ', [rfReplaceAll]));
        Result := 1;
      end;
    end;
  finally
    c.Res.Free;
    c.Free;
  end;
end;

{ ---- the parent: files, runs, the table ------------------------------------------ }

type
  TFigure = record
    Key, Title, Units: string;
    Line: Double;          // <= Line passes; < 0: no line (reported)
    MemLine: Boolean;      // the line is three times the file's size
  end;

const
  CFigures: array[0..26] of TFigure = (
    (Key: 'first'; Title: 'first screen: load to the end of the first paint'; Units: 'ms'; Line: 1000; MemLine: False),
    (Key: 'mid_loading'; Title: 'the middle of what is indexed, the load going on'; Units: 'ms'; Line: 100; MemLine: False),
    (Key: 'index_rest'; Title: 'the rest of the index (FinishLoading; in the background normally)'; Units: 'ms'; Line: -1; MemLine: False),
    (Key: 'mid'; Title: 'the middle set and painted'; Units: 'ms'; Line: 100; MemLine: False),
    (Key: 'rand'; Title: 'a place never shown (70 %) set and painted'; Units: 'ms'; Line: 100; MemLine: False),
    (Key: 'end'; Title: 'Ctrl+End to the end of its paint'; Units: 'ms'; Line: 100; MemLine: False),
    (Key: 'evict'; Title: 'that place again after 24 others evicted it'; Units: 'ms'; Line: 100; MemLine: False),
    (Key: 'key_start'; Title: 'a key at the start, to the end of its paint'; Units: 'ms'; Line: 30; MemLine: False),
    (Key: 'key_mid'; Title: 'a key in the middle, to the end of its paint'; Units: 'ms'; Line: 30; MemLine: False),
    (Key: 'del_mid'; Title: 'a Backspace in the middle, to the end of its paint'; Units: 'ms'; Line: 30; MemLine: False),
    (Key: 'key_end'; Title: 'a key at the end, to the end of its paint'; Units: 'ms'; Line: 30; MemLine: False),
    (Key: 'ws_load'; Title: 'working set after the load'; Units: 'MB'; Line: 3; MemLine: True),
    (Key: 'priv_load'; Title: 'private bytes after the load'; Units: 'MB'; Line: 3; MemLine: True),
    (Key: 'ws_all'; Title: 'working set after everything was read (index, find, save)'; Units: 'MB'; Line: 3; MemLine: True),
    (Key: 'priv_all'; Title: 'private bytes after everything was read'; Units: 'MB'; Line: 3; MemLine: True),
    (Key: 'ws_peak'; Title: 'peak working set'; Units: 'MB'; Line: 3; MemLine: True),
    (Key: 'priv_peak'; Title: 'peak private bytes'; Units: 'MB'; Line: 3; MemLine: True),
    (Key: 'ws_start'; Title: 'working set before the load (the program itself)'; Units: 'MB'; Line: -1; MemLine: False),
    (Key: 'save_same'; Title: 'save unchanged (byte-identical checked)'; Units: 'ms'; Line: -1; MemLine: False),
    (Key: 'save_edit'; Title: 'save after one edit'; Units: 'ms'; Line: -1; MemLine: False),
    (Key: 'find'; Title: 'find of a string not there, the whole document'; Units: 'ms'; Line: -1; MemLine: False),
    (Key: 'find_step'; Title: 'find: its longest piece (1 MB budget)'; Units: 'ms'; Line: -1; MemLine: False),
    (Key: 'pics_ready'; Title: 'the middle''s pictures decoded (background work) and painted'; Units: 'ms'; Line: -1; MemLine: False),
    (Key: 'pics_ready_count'; Title: 'pictures decoded for the middle'; Units: 'count'; Line: -1; MemLine: False),
    (Key: 'decodes_first'; Title: 'pictures decoded for the first screen'; Units: 'count'; Line: -1; MemLine: False),
    (Key: 'decodes_end'; Title: 'pictures decoded by the end of the run'; Units: 'count'; Line: -1; MemLine: False),
    (Key: 'paras'; Title: 'paragraphs'; Units: 'count'; Line: -1; MemLine: False));

type
  TRunResult = record
    Values: TStringList;
    Busy: Boolean;
    Load: Double;
  end;

var
  GDir, GOut: string;
  GRuns, GW, GH: Integer;
  GQuick, GKeep: Boolean;
  GMB: Int64;
  GOnly: string;
  GRaw: TStringList;

function Fmt(V: Double): string;
begin
  if Abs(V) >= 100 then Result := Format('%.0f', [V])
  else Result := Format('%.1f', [V]);
end;

function Median(var A: array of Double): Double;
var
  i, j, n: Integer;
  t: Double;
begin
  n := Length(A);
  for i := 1 to n - 1 do
  begin
    t := A[i];
    j := i - 1;
    while (j >= 0) and (A[j] > t) do
    begin
      A[j + 1] := A[j];
      Dec(j);
    end;
    A[j + 1] := t;
  end;
  if n = 0 then Exit(NaN);
  if Odd(n) then Result := A[n div 2] else Result := (A[n div 2 - 1] + A[n div 2]) / 2;
end;

function MakeInput(AKind: Integer; const APath: string): string;
var
  bytes, pics: Int64;
  scale: Double;
begin
  bytes := GMB * MB;
  scale := GMB / 100;
  Result := '';
  case AKind of
    0: MakeText(APath, bytes, False);
    1: MakeText(APath, bytes, True);
    2: MakeRtf(APath, bytes);
    3:
      begin
        if GQuick then MakePicturesRtf(APath, 8, True, pics)
        else MakePicturesRtf(APath, 200, False, pics);
        Result := Format('%d pictures, %.1f MB of picture bytes', [IfThen(GQuick, 8, 200),
          pics / MB]);
      end;
    4: MakeFieldsRtf(APath, bytes, Max(2, Round(200000 * scale)), Max(1, Round(5000 * scale)));
    5: MakeEquationsRtf(APath, bytes, Max(1, Round(2000 * scale)));
  end;
end;

function RunChild(AKind: Integer; const APath: string; ARun: Integer; out AR: TRunResult): Boolean;
var
  p: TProcess;
  resPath: string;
  tries: Integer;
begin
  AR.Values := TStringList.Create;
  // the machine's load before the run: wait while it is above the line, then mark it busy
  tries := 0;
  repeat
    AR.Load := CpuLoad(1000);
    AR.Busy := AR.Load > CBusyPercent;
    if not AR.Busy then Break;
    Inc(tries);
    WriteLn(Format('  the machine is busy (%.0f %%), waiting', [AR.Load]));
    if tries >= CBusyTries then Break;
    Sleep(CBusyWaitMs);
  until False;
  resPath := IncludeTrailingPathDelimiter(GDir) + Format('result-%s-%d', [CKinds[AKind], ARun]);
  DeleteFile(resPath);
  p := TProcess.Create(nil);
  try
    p.Executable := ParamStr(0);
    p.Parameters.Add('--child');
    p.Parameters.Add(CKinds[AKind]);
    p.Parameters.Add(APath);
    p.Parameters.Add(resPath);
    p.Parameters.Add('--size');
    p.Parameters.Add(Format('%dx%d', [GW, GH]));
    p.Options := [poWaitOnExit, poNoConsole];
    p.ShowWindow := swoHIDE;
    p.Execute;
    if FileExists(resPath) then AR.Values.LoadFromFile(resPath);
    if p.ExitStatus <> 0 then
      AR.Values.Values['error'] := AR.Values.Values['error'] + Format(' (exit %d)', [p.ExitStatus]);
  finally
    p.Free;
  end;
  DeleteFile(resPath);
  Result := AR.Values.Values['done'] = '1';
  if not Result and (AR.Values.Values['error'] = '') then AR.Values.Values['error'] := 'the run ended early';
end;

procedure Emit(AConsole, AMd, ACsv: TStringList; AKind: Integer; const ARuns: array of TRunResult;
  const AGen: string; var AFigures, AMisses: Integer; var AMissList: string);
var
  fi, r, n, busyN: Integer;
  vals: array of Double;
  v, med, mn, mx, line, fileMb: Double;
  lineS, verdict, s, notes: string;
  useBusy: Boolean;
begin
  fileMb := 0;
  for r := 0 to High(ARuns) do
    if ARuns[r].Values.Values['file_mb'] <> '' then
      fileMb := StrToFloat(ARuns[r].Values.Values['file_mb'], FS);
  s := Format('%s - %.1f MB%s', [CKindTitle[AKind], fileMb, BoolToStr(AGen <> '', '; ' + AGen, '')]);
  if not CAcceptance[AKind] then s := s + ' (beyond the plan''s four: not an acceptance line)';
  AConsole.Add('');
  AConsole.Add(s);
  AConsole.Add(Format('  %-62s %10s %9s %9s %9s  %-7s %s', ['figure', 'line', 'median', 'min',
    'max', 'verdict', 'runs']));
  AMd.Add('');
  AMd.Add('### ' + s);
  AMd.Add('');
  AMd.Add('| figure | line | median | min | max | verdict | runs |');
  AMd.Add('|---|---:|---:|---:|---:|---|---|');
  for fi := 0 to High(CFigures) do
  begin
    // the runs that measured it; busy ones only when there is nothing else
    busyN := 0;
    useBusy := True;
    for r := 0 to High(ARuns) do
      if (ARuns[r].Values.Values[CFigures[fi].Key] <> '') and not ARuns[r].Busy then useBusy := False;
    SetLength(vals, 0);
    for r := 0 to High(ARuns) do
    begin
      s := ARuns[r].Values.Values[CFigures[fi].Key];
      if s = '' then Continue;
      if ARuns[r].Busy then
      begin
        Inc(busyN);
        if not useBusy then Continue;
      end;
      v := StrToFloat(s, FS);
      SetLength(vals, Length(vals) + 1);
      vals[High(vals)] := v;
    end;
    n := Length(vals);
    if n = 0 then Continue;
    mn := MinValue(vals);
    mx := MaxValue(vals);
    med := Median(vals);
    if CFigures[fi].MemLine then line := CFigures[fi].Line * fileMb else line := CFigures[fi].Line;
    if line < 0 then
    begin
      lineS := '-';
      verdict := '-';
    end
    else
    begin
      if CFigures[fi].MemLine then lineS := Format('<= %s MB', [Fmt(line)])
      else lineS := Format('<= %s %s', [Fmt(line), CFigures[fi].Units]);
      Inc(AFigures);
      if useBusy then verdict := 'busy'
      else if med <= line then verdict := 'pass'
      else
      begin
        verdict := 'MISS';
        Inc(AMisses);
        if AMissList <> '' then AMissList := AMissList + '; ';
        AMissList := AMissList + Format('%s: %s (%s %s, line %s)', [CKinds[AKind], CFigures[fi].Key,
          Fmt(med), CFigures[fi].Units, Fmt(line)]);
      end;
    end;
    notes := Format('%d', [n]);
    if busyN > 0 then notes := notes + Format(', %d busy', [busyN]);
    AConsole.Add(Format('  %-62s %10s %9s %9s %9s  %-7s %s', [CFigures[fi].Title, lineS,
      Fmt(med), Fmt(mn), Fmt(mx), verdict, notes]));
    AMd.Add(Format('| %s (%s) | %s | %s | %s | %s | %s | %s |', [CFigures[fi].Title,
      CFigures[fi].Units, lineS, Fmt(med), Fmt(mn), Fmt(mx), verdict, notes]));
    ACsv.Add(Format('%s,"%s",%s,"%s",%s,%s,%s,%s,%d,%d', [CKinds[AKind], CFigures[fi].Title,
      CFigures[fi].Units, lineS, Fmt(med), Fmt(mn), Fmt(mx), verdict, n, busyN]));
  end;
  // what a run's own checks found
  for r := 0 to High(ARuns) do
  begin
    s := ARuns[r].Values.Values['checks'];
    if ARuns[r].Values.Values['error'] <> '' then s := s + ' ERROR ' + ARuns[r].Values.Values['error'];
    if s <> '' then
    begin
      AConsole.Add(Format('  run %d: %s', [r + 1, s]));
      AMd.Add('');
      AMd.Add(Format('Run %d: %s', [r + 1, s]));
    end;
  end;
end;

function ParentMain: Integer;
var
  k, r, i, figures, misses: Integer;
  path, gen, missList, ext, s: string;
  runs: array of TRunResult;
  con, md, csv, mach: TStringList;
  t0, room: Double;
  need: Int64;
begin
  Result := 0;
  ForceDirectories(GDir);
  ForceDirectories(GOut);
  con := TStringList.Create;
  md := TStringList.Create;
  csv := TStringList.Create;
  GRaw := TStringList.Create;
  mach := MachineLines;
  try
    mach.Add(Format('Processor load before the runs: %.1f %%', [CpuLoad(2000)]));
    mach.Add(Format('View: %d x %d at 96 PPI, the default theme; %d run(s) each, each in its own process%s',
      [GW, GH, GRuns, BoolToStr(GQuick, '; QUICK MODE (1 MB files): a demonstration, not the acceptance', '')]));
    for s in mach do WriteLn(s);
    md.Add('# TTyRichEdit large-file bench');
    md.Add('');
    for s in mach do md.Add('- ' + s);
    md.Add('');
    md.Add('Lines are the design''s (section 3.9): first screen 1 s, any place 100 ms, a key 30 ms, ' +
      'memory three times the file. The median of the runs is judged.');
    csv.Add('file,figure,unit,line,median,min,max,verdict,runs,busy');
    GRaw.Add('file,run,load_percent,busy,key,value');
    figures := 0;
    misses := 0;
    missList := '';
    for k := 0 to High(CKinds) do
    begin
      if (GOnly <> '') and (Pos(',' + CKinds[k] + ',', ',' + GOnly + ',') = 0) then Continue;
      if k < 2 then ext := '.txt' else ext := '.rtf';
      path := IncludeTrailingPathDelimiter(GDir) + 'bench-' + CKinds[k] + ext;
      // the file and one save of it, with room to spare (the picture file is the largest)
      if k = 3 then need := IfThen(GQuick, 20, 800) * Int64(MB) else need := 3 * GMB * MB;
      room := FreeRoom(GDir);
      if (room >= 0) and (room < need) then
      begin
        WriteLn(Format('%s: needs %d MB free in %s, %.0f MB there: skipped', [CKinds[k],
          need div MB, GDir, room / MB]));
        Result := 2;
        Continue;
      end;
      Write(Format('%s: making %s ... ', [CKinds[k], path]));
      t0 := Clock;
      gen := MakeInput(k, path);
      WriteLn(Format('%.1f MB in %.1f s', [SizeOfFile(path) / MB, (Clock - t0) / 1000]));
      SetLength(runs, GRuns);
      for r := 0 to GRuns - 1 do
      begin
        Write(Format('  run %d of %d ... ', [r + 1, GRuns]));
        t0 := Clock;
        RunChild(k, path, r + 1, runs[r]);
        WriteLn(Format('%.1f s (load before it %.1f %%%s)%s', [(Clock - t0) / 1000, runs[r].Load,
          BoolToStr(runs[r].Busy, ', BUSY', ''), BoolToStr(runs[r].Values.Values['error'] <> '',
          ' ERROR ' + runs[r].Values.Values['error'], '')]));
        for i := 0 to runs[r].Values.Count - 1 do
          GRaw.Add(Format('%s,%d,%.1f,%d,%s,"%s"', [CKinds[k], r + 1, runs[r].Load, Ord(runs[r].Busy),
            runs[r].Values.Names[i], runs[r].Values.ValueFromIndex[i]]));
      end;
      Emit(con, md, csv, k, runs, gen, figures, misses, missList);
      for r := 0 to GRuns - 1 do runs[r].Values.Free;
      if not GKeep then DeleteFile(path);
      for s in con do WriteLn(s);
      con.Clear;
    end;
    s := Format('Verdict: %d figures with a line, %d MISS%s', [figures, misses,
      BoolToStr(missList <> '', ': ' + missList, '')]);
    // (1 MB files: the memory lines, three times the file, are below what the program itself
    // takes before it loads anything)
    if GQuick then s := 'Quick mode - a demonstration, not the acceptance. ' + s;
    WriteLn;
    WriteLn(s);
    md.Add('');
    md.Add(s);
    md.SaveToFile(IncludeTrailingPathDelimiter(GOut) + 'richedit-bench.md');
    csv.SaveToFile(IncludeTrailingPathDelimiter(GOut) + 'richedit-bench.csv');
    GRaw.SaveToFile(IncludeTrailingPathDelimiter(GOut) + 'richedit-bench-runs.csv');
    WriteLn('Written: ' + IncludeTrailingPathDelimiter(GOut) + 'richedit-bench.md, .csv, -runs.csv');
    if (misses > 0) and not GQuick then Result := 1;
  finally
    mach.Free;
    GRaw.Free;
    csv.Free;
    md.Free;
    con.Free;
  end;
end;

procedure Usage;
begin
  WriteLn('richeditbench [--dir <folder>] [--out <folder>] [--runs N] [--quick] [--keep]');
  WriteLn('              [--only utf8,gbk,rtf,pictures,fields,equations] [--size WxH] [--mb N]');
  WriteLn('  --dir   where the input files are made (default: <temp>/tyrichbench; never the repository)');
  WriteLn('  --out   where the table goes as Markdown and CSV (default: --dir)');
  WriteLn('  --runs  runs per file, each in a fresh process (default 5; --quick: 1)');
  WriteLn('  --quick 1 MB files, one run: a demonstration in seconds, not the acceptance');
  WriteLn('  --keep  the input files are kept');
  WriteLn('  --mb    the size of the files (default 100; --quick: 1)');
end;

function ParseSize(const S: string; out AW, AH: Integer): Boolean;
var
  p: Integer;
begin
  p := Pos('x', LowerCase(S));
  Result := (p > 0) and TryStrToInt(Copy(S, 1, p - 1), AW) and TryStrToInt(Copy(S, p + 1, MaxInt), AH);
end;

var
  i: Integer;
  a, childKind, childPath, childRes: string;
  runsSet, mbSet: Boolean;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;
  Application.Initialize;
  GDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyrichbench';
  GOut := '';
  GRuns := 5;
  GW := 1200;
  GH := 900;
  GMB := 100;
  runsSet := False;
  mbSet := False;
  childKind := '';
  i := 1;
  while i <= ParamCount do
  begin
    a := ParamStr(i);
    if a = '--child' then
    begin
      childKind := ParamStr(i + 1);
      childPath := ParamStr(i + 2);
      childRes := ParamStr(i + 3);
      Inc(i, 3);
    end
    else if a = '--dir' then begin GDir := ParamStr(i + 1); Inc(i); end
    else if a = '--out' then begin GOut := ParamStr(i + 1); Inc(i); end
    else if a = '--runs' then begin GRuns := StrToIntDef(ParamStr(i + 1), 5); runsSet := True; Inc(i); end
    else if a = '--mb' then begin GMB := StrToIntDef(ParamStr(i + 1), 100); mbSet := True; Inc(i); end
    else if a = '--only' then begin GOnly := ParamStr(i + 1); Inc(i); end
    else if a = '--size' then
    begin
      if not ParseSize(ParamStr(i + 1), GW, GH) then begin Usage; Halt(2); end;
      Inc(i);
    end
    else if a = '--quick' then GQuick := True
    else if a = '--keep' then GKeep := True
    else begin Usage; Halt(2); end;
    Inc(i);
  end;
  if childKind <> '' then Halt(ChildMain(childKind, childPath, childRes, GW, GH));
  if GQuick then
  begin
    if not runsSet then GRuns := 1;
    if not mbSet then GMB := 1;
  end;
  if GRuns < 1 then GRuns := 1;
  if GOut = '' then GOut := GDir;
  Halt(ParentMain);
end.
