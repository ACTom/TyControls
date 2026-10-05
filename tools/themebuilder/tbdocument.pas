unit tbdocument;
{ The document being edited: its text as read, where it lives, and how to write it back
  byte for byte the way it came in -- the line ending of its first line break, a UTF-8 BOM
  if it had one, a final line break if it had one. A file that is not valid UTF-8 is read in
  the system's code page (GuessEncoding) and will be saved as UTF-8; ConvertedFrom names the
  code page so the window can say so.

  The file on disk is watched by stamp (last-write time and size), not by the style
  controller's hot reload: that one loads a changed file straight into the model, and here
  the editor's text is what matters. The time is the file system's own, to the 100 ns on
  NTFS and the nanosecond where stat gives it (TbFileStamp) -- FileAge is a DOS time, two
  seconds wide, and a program that rewrote the file at the same size within those two
  seconds went unseen. DiskChanged takes the stamp again before it answers True, so one
  change is reported once. A file that has gone away is not reported (saving writes it
  back). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils;

type
  TTbLineEnding = (tleLF, tleCRLF, tleCR);

  TTbDocument = class
  private
    FFileName: string;
    FText: string;
    FBasedOn: string;
    FLineEnding: TTbLineEnding;
    FHasBom: Boolean;
    FTrailingEol: Boolean;
    FConvertedFrom: string;
    FStampTime: Int64;
    FStampSize: Int64;
    function GetBaseDir: string;
    function GetUntitled: Boolean;
    procedure CaptureStamp;
  public
    constructor Create;
    procedure NewUntitled(const AText, ABasedOn: string);
    { raises on a read error; the document is unchanged then }
    procedure LoadFromFile(const AFileName: string);
    { FOR THE TESTS: SaveToFile raises half-way through writing }
    class var FailWriteForTest: Boolean;
    { ALines joined with the document's line ending, BOM and final line break as read;
      written to a file beside AFileName and moved over it, so a failure (it raises) leaves
      AFileName and the document as they were }
    procedure SaveToFile(const AFileName: string; ALines: TStrings);
    function EditorText: string;
    { the file on disk changed since it was opened / saved (time or size). The stamp is
      taken again, so one change answers True once. A missing file answers False. }
    function DiskChanged: Boolean;
    { '' or the script(s) to run after saving a theme the library compiles in }
    function RegenerateHint: string;
    property FileName: string read FFileName;
    property BaseDir: string read GetBaseDir;          { '' when untitled }
    property Untitled: Boolean read GetUntitled;
    property BasedOn: string read FBasedOn;
    property LineEnding: TTbLineEnding read FLineEnding;
    property HasBom: Boolean read FHasBom;
    property TrailingEol: Boolean read FTrailingEol;
    property ConvertedFrom: string read FConvertedFrom;  { '' = it was UTF-8 }
  end;

{ the first break; none -> the platform's }
function TbDetectLineEnding(const S: string): TTbLineEnding;
function TbJoinLines(ALines: TStrings; AEol: TTbLineEnding; ATrailing: Boolean): string;
{ 'LF' / 'CRLF' / 'CR' }
function TbLineEndingName(AEol: TTbLineEnding): string;
{ AFileName's last-write time at the file system's precision (Windows: FILETIME, 100 ns
  ticks; elsewhere: nanoseconds since the epoch) and its size. False (-1, -1) when it
  cannot be read -- it is not there. }
function TbFileStamp(const AFileName: string; out ATime, ASize: Int64): Boolean;

implementation

uses
  {$IFDEF MSWINDOWS}Windows,{$ELSE}BaseUnix,{$ENDIF} LazUTF8, LConvEncoding;

const
  cBom = #$EF#$BB#$BF;

function TbDetectLineEnding(const S: string): TTbLineEnding;
var
  i: Integer;
begin
  for i := 1 to Length(S) do
    if S[i] = #10 then
      Exit(tleLF)
    else if S[i] = #13 then
    begin
      if (i < Length(S)) and (S[i + 1] = #10) then
        Exit(tleCRLF);
      Exit(tleCR);
    end;
  {$IFDEF MSWINDOWS}
  Result := tleCRLF;
  {$ELSE}
  Result := tleLF;
  {$ENDIF}
end;

function EolText(AEol: TTbLineEnding): string;
begin
  case AEol of
    tleCRLF: Result := #13#10;
    tleCR: Result := #13;
  else
    Result := #10;
  end;
end;

function TbJoinLines(ALines: TStrings; AEol: TTbLineEnding; ATrailing: Boolean): string;
var
  i: Integer;
  eol: string;
begin
  Result := '';
  eol := EolText(AEol);
  for i := 0 to ALines.Count - 1 do
  begin
    if i > 0 then
      Result := Result + eol;
    Result := Result + ALines[i];
  end;
  if ATrailing and (ALines.Count > 0) then
    Result := Result + eol;
end;

function TbLineEndingName(AEol: TTbLineEnding): string;
begin
  case AEol of
    tleCRLF: Result := 'CRLF';
    tleCR: Result := 'CR';
  else
    Result := 'LF';
  end;
end;

{ ---- TTbDocument ---- }

constructor TTbDocument.Create;
begin
  inherited Create;
  FLineEnding := TbDetectLineEnding('');
  FTrailingEol := True;
end;

function TTbDocument.GetBaseDir: string;
begin
  if FFileName = '' then
    Result := ''
  else
    Result := ExtractFilePath(FFileName);
end;

function TTbDocument.GetUntitled: Boolean;
begin
  Result := FFileName = '';
end;

function TbFileStamp(const AFileName: string; out ATime, ASize: Int64): Boolean;
{$IFDEF MSWINDOWS}
var
  d: WIN32_FILE_ATTRIBUTE_DATA;
begin
  ATime := -1;
  ASize := -1;
  Result := GetFileAttributesExW(PWideChar(UnicodeString(AFileName)), GetFileExInfoStandard, @d);
  if not Result then Exit;
  ATime := Int64(d.ftLastWriteTime.dwHighDateTime) shl 32 or d.ftLastWriteTime.dwLowDateTime;
  ASize := Int64(d.nFileSizeHigh) shl 32 or d.nFileSizeLow;
end;
{$ELSE}
var
  st: TStat;
begin
  ATime := -1;
  ASize := -1;
  Result := FpStat(AFileName, st) = 0;
  if not Result then Exit;
  {$IFDEF DARWIN}
  ATime := Int64(st.st_mtime) * 1000000000 + st.st_mtimensec;
  {$ELSE}
  ATime := Int64(st.st_mtime) * 1000000000 + Int64(st.st_mtime_nsec);
  {$ENDIF}
  ASize := st.st_size;
end;
{$ENDIF}

procedure TTbDocument.CaptureStamp;
begin
  FStampTime := -1;
  FStampSize := -1;
  if FFileName = '' then Exit;
  TbFileStamp(FFileName, FStampTime, FStampSize);
end;

procedure TTbDocument.NewUntitled(const AText, ABasedOn: string);
begin
  FFileName := '';
  FText := AText;
  FBasedOn := ABasedOn;
  FLineEnding := TbDetectLineEnding(AText);
  FHasBom := False;
  FTrailingEol := True;
  FConvertedFrom := '';
  FStampTime := -1;
  FStampSize := -1;
end;

procedure TTbDocument.LoadFromFile(const AFileName: string);
var
  fs: TFileStream;
  s, enc, name: string;
  bom: Boolean;
begin
  { read into locals first: a failure leaves the document as it was }
  name := ExpandFileName(AFileName);
  s := '';
  fs := TFileStream.Create(name, fmOpenRead or fmShareDenyNone);
  try
    SetLength(s, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(s[1], fs.Size);
  finally
    fs.Free;
  end;
  bom := Copy(s, 1, 3) = cBom;
  if bom then
    Delete(s, 1, 3);
  enc := '';
  if FindInvalidUTF8Codepoint(PChar(s), Length(s)) >= 0 then
  begin
    enc := GuessEncoding(s);
    s := ConvertEncoding(s, enc, EncodingUTF8);
  end;
  FFileName := name;
  FText := s;
  FHasBom := bom;
  FConvertedFrom := enc;
  FLineEnding := TbDetectLineEnding(s);
  FTrailingEol := (s <> '') and (s[Length(s)] in [#10, #13]);
  FBasedOn := '';
  CaptureStamp;
end;

{ A name next to ATarget that nothing has: the same folder, so the final rename stays on
  one volume (and is atomic there). }
function TempNameFor(const ATarget: string): string;
var
  n: Integer;
begin
  n := 0;
  repeat
    Result := ATarget + Format('.%d-%d.tbsave', [GetProcessID, n]);
    Inc(n);
  until not FileExists(Result);
end;

{ ATemp takes ATarget's place in one step, or raises with ATarget as it was. Windows:
  MoveFileExW replacing, written through; elsewhere rename(2), with the old file's
  permission bits carried over (a new file gets the umask's). }
procedure ReplaceWith(const ATemp, ATarget: string);
{$IFDEF MSWINDOWS}
const
  cMoveFileWriteThrough = 8;   { MOVEFILE_WRITE_THROUGH: FPC's Windows unit lacks it }
begin
  if not MoveFileExW(PWideChar(UnicodeString(ATemp)), PWideChar(UnicodeString(ATarget)),
    MOVEFILE_REPLACE_EXISTING or cMoveFileWriteThrough) then
    RaiseLastOSError;
end;
{$ELSE}
var
  st: TStat;
begin
  if FpStat(ATarget, st) = 0 then
    FpChmod(ATemp, st.st_mode and &7777);
  if FpRename(ATemp, ATarget) <> 0 then
    RaiseLastOSError;
end;
{$ENDIF}

procedure TTbDocument.SaveToFile(const AFileName: string; ALines: TStrings);
var
  s, tmp: string;
  fs: TFileStream;
  half: Integer;
begin
  s := TbJoinLines(ALines, FLineEnding, FTrailingEol);
  if FHasBom then
    s := cBom + s;
  { Written beside the file and then moved over it: a write that fails half-way (a full
    disk, a pulled drive) leaves the file as it was, never cut short. }
  tmp := TempNameFor(AFileName);
  try
    fs := TFileStream.Create(tmp, fmCreate);
    try
      half := Length(s) div 2;
      if half > 0 then
        fs.WriteBuffer(s[1], half);
      if FailWriteForTest then
        raise EWriteError.Create('FailWriteForTest');
      if Length(s) > half then
        fs.WriteBuffer(s[half + 1], Length(s) - half);
    finally
      fs.Free;
    end;
    ReplaceWith(tmp, AFileName);
  except
    SysUtils.DeleteFile(tmp);
    raise;   { the document keeps its name and its stamp: the file on disk did not change }
  end;
  FFileName := ExpandFileName(AFileName);
  FConvertedFrom := '';
  CaptureStamp;
end;

function TTbDocument.EditorText: string;
begin
  Result := FText;
end;

function TTbDocument.DiskChanged: Boolean;
var
  time, size: Int64;
begin
  Result := False;
  if Untitled or not TbFileStamp(FFileName, time, size) then Exit;
  if (time <> FStampTime) or (size <> FStampSize) then
  begin
    CaptureStamp;
    Result := True;
  end;
end;

function TTbDocument.RegenerateHint: string;
var
  dir, dirName, parent, name, root: string;
begin
  Result := '';
  if Untitled then Exit;
  dir := ExcludeTrailingPathDelimiter(ExtractFileDir(FFileName));
  dirName := ExtractFileName(dir);
  parent := ExcludeTrailingPathDelimiter(ExtractFileDir(dir));
  name := LowerCase(ExtractFileName(FFileName));
  { themes/builtin/x.tycss: the checkout root is two folders up }
  if SameText(dirName, 'builtin') and SameText(ExtractFileName(parent), 'themes') then
  begin
    root := IncludeTrailingPathDelimiter(ExtractFileDir(parent));
    if FileExists(root + 'scripts' + PathDelim + 'gen-builtinthemes.ps1') then
      Result := 'gen-builtinthemes.ps1';
    Exit;
  end;
  { themes/x.tycss: one folder up }
  if SameText(dirName, 'themes') then
  begin
    root := IncludeTrailingPathDelimiter(parent);
    if not FileExists(root + 'scripts' + PathDelim + 'gen-builtinthemes.ps1') then
      Exit;
    if (name = 'auto.tycss') or (name = 'system.tycss') then
      Result := 'gen-builtinthemes.ps1'
    else if name = 'light.tycss' then
      Result := 'gen-defaulttheme.ps1, gen-tycss-catalog.ps1';
  end;
end;

end.
