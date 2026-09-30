unit tbdocument;
{ The document being edited: its text as read, where it lives, and how to write it back
  byte for byte the way it came in -- the line ending of its first line break, a UTF-8 BOM
  if it had one, a final line break if it had one. A file that is not valid UTF-8 is read in
  the system's code page (GuessEncoding) and will be saved as UTF-8; ConvertedFrom names the
  code page so the window can say so.

  The file on disk is watched by stamp (age and size), not by the style controller's hot
  reload: that one loads a changed file straight into the model, and here the editor's text
  is what matters. DiskChanged takes the stamp again before it answers True, so one change
  is reported once. A file that has gone away is not reported (saving writes it back). }
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
    FStampAge: LongInt;
    FStampSize: Int64;
    function GetBaseDir: string;
    function GetUntitled: Boolean;
    procedure CaptureStamp;
  public
    constructor Create;
    procedure NewUntitled(const AText, ABasedOn: string);
    { raises on a read error; the document is unchanged then }
    procedure LoadFromFile(const AFileName: string);
    { ALines joined with the document's line ending, BOM and final line break as read }
    procedure SaveToFile(const AFileName: string; ALines: TStrings);
    function EditorText: string;
    { the file on disk changed since it was opened / saved (age or size). The stamp is
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

implementation

uses
  LazUTF8, LConvEncoding;

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

procedure TTbDocument.CaptureStamp;
var
  sr: TSearchRec;
begin
  FStampAge := -1;
  FStampSize := -1;
  if FFileName = '' then Exit;
  FStampAge := FileAge(FFileName);
  if FindFirst(FFileName, faAnyFile, sr) = 0 then
  begin
    FStampSize := sr.Size;
    FindClose(sr);
  end;
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
  FStampAge := -1;
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

procedure TTbDocument.SaveToFile(const AFileName: string; ALines: TStrings);
var
  s: string;
  fs: TFileStream;
begin
  s := TbJoinLines(ALines, FLineEnding, FTrailingEol);
  if FHasBom then
    s := cBom + s;
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    if s <> '' then
      fs.WriteBuffer(s[1], Length(s));
  finally
    fs.Free;
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
  age: LongInt;
  size: Int64;
  sr: TSearchRec;
begin
  Result := False;
  if Untitled or not FileExists(FFileName) then Exit;
  age := FileAge(FFileName);
  size := -1;
  if FindFirst(FFileName, faAnyFile, sr) = 0 then
  begin
    size := sr.Size;
    FindClose(sr);
  end;
  if (age <> FStampAge) or (size <> FStampSize) then
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
