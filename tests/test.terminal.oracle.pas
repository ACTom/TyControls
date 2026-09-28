unit test.terminal.oracle;
{$mode objfpc}{$H+}
{ Shared reading and comparing for the terminal fixtures that tools/terminal-oracle
  writes (parser, buffer, core). Registers no test of its own.

  Everything here serves one rule: a comparison that did not happen must not pass.
  TTyTermMisses counts every comparison next to every miss, and each test asserts
  that count against a number worked out from the fixture itself, so a fixture that
  reads empty, a split part that went missing, or a loop that stops early is red.

  The long-string digest (32-bit FNV-1a over code points) and the canonical text of
  a payload are written once here and once in tools/terminal-oracle/lib-term.js. }

interface

uses
  Classes, SysUtils, fpjson, jsonparser, base64;

const
  TyTermPinnedCommitPrefix = 'c58ea36';
  TyTermPinnedVersion = '6.0.0';
  TyTermMaxMissText = 30;

type
  TTyTermCps = array of Cardinal;
  TTyTermFixtures = array of TJSONObject;

  { Counts comparisons and misses, keeps the first TyTermMaxMissText misses. }
  TTyTermMisses = class
  private
    FCount: Integer;
    FCompared: Int64;
    FLines: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const ACaseId, APath, AWant, AGot: string);
    procedure AddCompared(AN: Int64 = 1);
    function Text: string;
    property Count: Integer read FCount;
    property Compared: Int64 read FCompared;
  end;

function TyTermFixturePath(const AName: string): string;
{ terminal-<kind>.json, or all of terminal-<kind>-<n>.json in part order. Both
  shapes present, a gap in the numbering, or parts that disagree on "parts" are
  one miss each (a stale part would otherwise be read silently). The caller frees
  the objects (TyTermFreeFixtures). }
function TyTermLoadFixtures(const AKind: string; AMisses: TTyTermMisses): TTyTermFixtures;
procedure TyTermFreeFixtures(var AFixtures: TTyTermFixtures);
{ Every case of every part, in order (borrowed from the fixtures). }
function TyTermAllCases(const AFixtures: TTyTermFixtures): TFPList;
procedure TyTermCheckUpstream(AFixture: TJSONObject; const AWhat: string; AMisses: TTyTermMisses);

function TyTermDigest(const ACps: array of Cardinal): Cardinal;
function TyTermUtf8ToCps(const S: string): TTyTermCps;
function TyTermDigestUtf8(const S: string): Cardinal;
{ The canonical text of a payload: up to 256 code points, the code points with
  everything outside printable ASCII (and the backslash and quote) written as a
  backslash, x and the hex number in braces; more, "n=<count> h=<digest>". }
function TyTermCanonCps(const ACps: array of Cardinal): string;
function TyTermCanonUtf8(const S: string): string;
{ The same canonical text for a fixture value: a string, an array of code points,
  or an object with "n" and "h"; numbers, booleans and null as their JSON text. }
function TyTermCanonJson(ANode: TJSONData): string;
function TyTermBase64Bytes(const S: string): RawByteString;
function TyTermJsonCps(AArr: TJSONArray): TTyTermCps;

implementation

{ ---- TTyTermMisses ------------------------------------------------------------ }

constructor TTyTermMisses.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
end;

destructor TTyTermMisses.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TTyTermMisses.Add(const ACaseId, APath, AWant, AGot: string);
begin
  Inc(FCount);
  if FLines.Count < TyTermMaxMissText then
    FLines.Add(Format('case %s %s: want %s got %s', [ACaseId, APath, AWant, AGot]));
end;

procedure TTyTermMisses.AddCompared(AN: Int64);
begin
  Inc(FCompared, AN);
end;

function TTyTermMisses.Text: string;
begin
  Result := Format('%d misses in %d comparisons', [FCount, FCompared]);
  if FLines.Count > 0 then
    Result := Result + LineEnding + FLines.Text;
end;

{ ---- fixtures ------------------------------------------------------------------- }

function TyTermFixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function LoadJsonFile(const APath: string): TJSONObject;
var
  fs: TFileStream;
  d: TJSONData;
begin
  fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    d := GetJSON(fs);
  finally
    fs.Free;
  end;
  if not (d is TJSONObject) then
  begin
    d.Free;
    raise Exception.Create(APath + ': not a JSON object');
  end;
  Result := TJSONObject(d);
end;

function TyTermLoadFixtures(const AKind: string; AMisses: TTyTermMisses): TTyTermFixtures;
var
  single: string;
  n, parts: Integer;
  o: TJSONObject;
begin
  Result := nil;
  single := TyTermFixturePath('terminal-' + AKind + '.json');
  if FileExists(single) then
  begin
    o := LoadJsonFile(single);
    SetLength(Result, 1);
    Result[0] := o;
    if (o.Get('part', 1) <> 1) or (o.Get('parts', 1) <> 1) then
      AMisses.Add(AKind, 'parts', '1 of 1', Format('%d of %d', [o.Get('part', 0), o.Get('parts', 0)]));
    if FileExists(TyTermFixturePath('terminal-' + AKind + '-1.json')) then
      AMisses.Add(AKind, 'shape', 'one file', 'also terminal-' + AKind + '-1.json');
    Exit;
  end;
  n := 1;
  parts := -1;
  while FileExists(TyTermFixturePath(Format('terminal-%s-%d.json', [AKind, n]))) do
  begin
    o := LoadJsonFile(TyTermFixturePath(Format('terminal-%s-%d.json', [AKind, n])));
    SetLength(Result, n);
    Result[n - 1] := o;
    if parts = -1 then
      parts := o.Get('parts', 0);
    if o.Get('parts', 0) <> parts then
      AMisses.Add(AKind, Format('part %d', [n]), Format('parts %d', [parts]), Format('parts %d', [o.Get('parts', 0)]));
    if o.Get('part', 0) <> n then
      AMisses.Add(AKind, Format('part %d', [n]), IntToStr(n), IntToStr(o.Get('part', 0)));
    Inc(n);
  end;
  if n = 1 then
    AMisses.Add(AKind, 'file', 'terminal-' + AKind + '.json or -1.json', 'none')
  else if n - 1 <> parts then
    AMisses.Add(AKind, 'parts', IntToStr(parts), IntToStr(n - 1));
end;

procedure TyTermFreeFixtures(var AFixtures: TTyTermFixtures);
var
  i: Integer;
begin
  for i := 0 to High(AFixtures) do
    AFixtures[i].Free;
  AFixtures := nil;
end;

function TyTermAllCases(const AFixtures: TTyTermFixtures): TFPList;
var
  i, k: Integer;
  arr: TJSONArray;
begin
  Result := TFPList.Create;
  for i := 0 to High(AFixtures) do
  begin
    arr := AFixtures[i].Arrays['cases'];
    for k := 0 to arr.Count - 1 do
      Result.Add(arr.Objects[k]);
  end;
end;

procedure TyTermCheckUpstream(AFixture: TJSONObject; const AWhat: string; AMisses: TTyTermMisses);
var
  up: TJSONObject;
begin
  up := AFixture.Objects['upstream'];
  AMisses.AddCompared(2);
  if Copy(up.Strings['commit'], 1, Length(TyTermPinnedCommitPrefix)) <> TyTermPinnedCommitPrefix then
    AMisses.Add(AWhat, 'upstream.commit', TyTermPinnedCommitPrefix + '...', up.Strings['commit']);
  if up.Strings['version'] <> TyTermPinnedVersion then
    AMisses.Add(AWhat, 'upstream.version', TyTermPinnedVersion, up.Strings['version']);
end;

{ ---- digests and canonical text ------------------------------------------------- }

{$push}{$Q-}{$R-}
function TyTermDigest(const ACps: array of Cardinal): Cardinal;
var
  i: Integer;
begin
  Result := $811C9DC5;
  for i := 0 to High(ACps) do
    Result := (Result xor ACps[i]) * $01000193;
end;
{$pop}

function TyTermUtf8ToCps(const S: string): TTyTermCps;
var
  i, n, len, k: Integer;
  b: Byte;
  c: Cardinal;
begin
  Result := nil;
  SetLength(Result, Length(S));
  n := 0;
  i := 1;
  len := Length(S);
  while i <= len do
  begin
    b := Ord(S[i]);
    if b < $80 then
    begin
      c := b;
      k := 0;
    end
    else if b and $E0 = $C0 then
    begin
      c := b and $1F;
      k := 1;
    end
    else if b and $F0 = $E0 then
    begin
      c := b and $0F;
      k := 2;
    end
    else
    begin
      c := b and $07;
      k := 3;
    end;
    Inc(i);
    while (k > 0) and (i <= len) do
    begin
      c := (c shl 6) or (Ord(S[i]) and $3F);
      Inc(i);
      Dec(k);
    end;
    Result[n] := c;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function TyTermDigestUtf8(const S: string): Cardinal;
begin
  Result := TyTermDigest(TyTermUtf8ToCps(S));
end;

function TyTermCanonCps(const ACps: array of Cardinal): string;
var
  i: Integer;
  c: Cardinal;
begin
  if Length(ACps) > 256 then
    Exit(Format('n=%d h=%d', [Length(ACps), Int64(TyTermDigest(ACps))]));
  Result := '''';
  for i := 0 to High(ACps) do
  begin
    c := ACps[i];
    if (c >= $20) and (c <= $7E) and (c <> Ord('\')) and (c <> Ord('''')) then
      Result := Result + Chr(c)
    else
      Result := Result + '\x{' + IntToHex(c, 1) + '}';
  end;
  Result := Result + '''';
end;

function TyTermCanonUtf8(const S: string): string;
begin
  Result := TyTermCanonCps(TyTermUtf8ToCps(S));
end;

function TyTermJsonCps(AArr: TJSONArray): TTyTermCps;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, AArr.Count);
  for i := 0 to AArr.Count - 1 do
    Result[i] := Cardinal(AArr.Items[i].AsInt64);
end;

function TyTermCanonJson(ANode: TJSONData): string;
var
  o: TJSONObject;
begin
  case ANode.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if ANode.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := IntToStr(ANode.AsInt64);
    jtString: Result := TyTermCanonUtf8(ANode.AsString);
    jtArray: Result := TyTermCanonCps(TyTermJsonCps(TJSONArray(ANode)));
    jtObject:
      begin
        o := TJSONObject(ANode);
        Result := Format('n=%d h=%d', [o.Int64s['n'], o.Int64s['h']]);
      end;
  else
    Result := '?';
  end;
end;

function TyTermBase64Bytes(const S: string): RawByteString;
begin
  Result := DecodeStringBase64(S);
end;

end.
