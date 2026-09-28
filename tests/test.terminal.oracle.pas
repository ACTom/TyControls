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
  Classes, SysUtils, Types, fpjson, jsonparser, base64, tyControls.Terminal.Buffer;

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
function TyTermCpUtf8(c: Cardinal): string;
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

{ ---- values and structural equality ---- }

{ lib-term.js digestable() of a string, as JSON: the string, its code points when it
  holds U+0000, or n and h past 256 code points. }
function TyTermDigestableJson(const AUtf8: string): TJSONData;
function TyTermCpsJson(const ACps: array of Cardinal): TJSONData;
{ Same type and value, recursively; numbers as Int64. }
function TyTermJsonEqual(AWant, AGot: TJSONData): Boolean;
function TyTermJsonText(AData: TJSONData): string;

{ ---- buffer layer (Task 9) ---- }

type
  { '' answers null; nil means "only 0 is expected" (the buffer layer never sets one) }
  TTyTermCharsetKeyFunc = function(AId: TTyTermCharsetId): string;

function TyTermExtFromJson(AObj: TJSONObject): TTyTerminalExtAttrs;
function TyTermAttrFromJson(AObj: TJSONObject): TTyTerminalAttrData;
function TyTermCellFromJson(AObj: TJSONObject): TTyTerminalCellData;
function TyTermExtQuadJson(const AExt: TTyTerminalExtAttrs): TJSONArray;
{ A line against one exported line (the run-length cells, combined text, extended
  attributes, wrap flag, length). Every cell counts one comparison. }
procedure TyTermCompareLine(ALine: TTyTerminalLine; AJson: TJSONObject; ACols: Integer;
  const ACaseId, APath: string; AMisses: TTyTermMisses);
{ A line the export left out: exactly cols NULL cells with no attributes, unwrapped. }
procedure TyTermCompareDefaultLine(ALine: TTyTerminalLine; ACols: Integer;
  const ACaseId, APath: string; AMisses: TTyTermMisses);
procedure TyTermCompareBuffer(ABuf: TTyTerminalBuffer; AJson: TJSONObject; ACols: Integer;
  const ACaseId, APath: string; AMisses: TTyTermMisses; AKeyOf: TTyTermCharsetKeyFunc = nil);
function TyTermLinksJson(ALinks: TTyTerminalOscLinks): TJSONArray;
{ Compare two JSON values as one comparison; the texts go into the miss. }
procedure TyTermCompareJson(AWant, AGot: TJSONData; const ACaseId, APath: string; AMisses: TTyTermMisses);

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

function TyTermCpUtf8(c: Cardinal): string;
begin
  if c < $80 then
    Result := Chr(c)
  else if c < $800 then
    Result := Chr($C0 or (c shr 6)) + Chr($80 or (c and $3F))
  else if c < $10000 then
    Result := Chr($E0 or (c shr 12)) + Chr($80 or ((c shr 6) and $3F)) + Chr($80 or (c and $3F))
  else
    Result := Chr($F0 or (c shr 18)) + Chr($80 or ((c shr 12) and $3F))
      + Chr($80 or ((c shr 6) and $3F)) + Chr($80 or (c and $3F));
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

{ ---- values and structural equality ------------------------------------------------ }

function TyTermCpsJson(const ACps: array of Cardinal): TJSONData;
var
  a: TJSONArray;
  o: TJSONObject;
  i: Integer;
begin
  if Length(ACps) > 256 then
  begin
    o := TJSONObject.Create;
    o.Add('n', Int64(Length(ACps)));
    o.Add('h', Int64(TyTermDigest(ACps)));
    Exit(o);
  end;
  a := TJSONArray.Create;
  for i := 0 to High(ACps) do
    a.Add(Int64(ACps[i]));
  Result := a;
end;

function TyTermDigestableJson(const AUtf8: string): TJSONData;
var
  cps: TTyTermCps;
begin
  cps := TyTermUtf8ToCps(AUtf8);
  if (Length(cps) > 256) or (Pos(#0, AUtf8) > 0) then
    Exit(TyTermCpsJson(cps));
  Result := TJSONString.Create(AUtf8);
end;

function TyTermJsonEqual(AWant, AGot: TJSONData): Boolean;
var
  i: Integer;
  ow, og: TJSONObject;
  v: TJSONData;
begin
  if (AWant = nil) or (AGot = nil) then
    Exit((AWant = nil) and (AGot = nil));
  if AWant.JSONType <> AGot.JSONType then
    Exit(False);
  case AWant.JSONType of
    jtNull: Result := True;
    jtBoolean: Result := AWant.AsBoolean = AGot.AsBoolean;
    jtNumber: Result := AWant.AsInt64 = AGot.AsInt64;
    jtString: Result := AWant.AsString = AGot.AsString;
    jtArray:
      begin
        if AWant.Count <> AGot.Count then
          Exit(False);
        for i := 0 to AWant.Count - 1 do
          if not TyTermJsonEqual(AWant.Items[i], AGot.Items[i]) then
            Exit(False);
        Result := True;
      end;
    jtObject:
      begin
        ow := TJSONObject(AWant);
        og := TJSONObject(AGot);
        if ow.Count <> og.Count then
          Exit(False);
        for i := 0 to ow.Count - 1 do
        begin
          v := og.Find(ow.Names[i]);
          if (v = nil) or not TyTermJsonEqual(ow.Items[i], v) then
            Exit(False);
        end;
        Result := True;
      end;
  else
    Result := False;
  end;
end;

function TyTermJsonText(AData: TJSONData): string;
begin
  if AData = nil then
    Result := '(none)'
  else
    Result := AData.AsJSON;
end;

procedure TyTermCompareJson(AWant, AGot: TJSONData; const ACaseId, APath: string; AMisses: TTyTermMisses);
begin
  AMisses.AddCompared;
  if not TyTermJsonEqual(AWant, AGot) then
    AMisses.Add(ACaseId, APath, TyTermJsonText(AWant), TyTermJsonText(AGot));
end;

{ ---- buffer layer ------------------------------------------------------------------- }

function TyTermExtFromJson(AObj: TJSONObject): TTyTerminalExtAttrs;
begin
  Result.RawExt := Cardinal(AObj.Get('raw', Int64(0)));
  Result.UrlId := AObj.Get('urlId', 0);
  if AObj.Find('style') <> nil then
    Result.SetUnderlineStyle(AObj.Integers['style']);
  if AObj.Find('color') <> nil then
    Result.SetUnderlineColor(Integer(AObj.Int64s['color']));
  if AObj.Find('variant') <> nil then
    Result.SetUnderlineVariantOffset(AObj.Integers['variant']);
end;

function TyTermAttrFromJson(AObj: TJSONObject): TTyTerminalAttrData;
begin
  Result := TyTermDefaultAttr;
  Result.Fg := Cardinal(AObj.Int64s['fg']);
  Result.Bg := Cardinal(AObj.Int64s['bg']);
  if AObj.Find('ext') <> nil then
    Result.Extended := TyTermExtFromJson(AObj.Objects['ext']);
end;

function TyTermCellFromJson(AObj: TJSONObject): TTyTerminalCellData;
var
  cps: TTyTermCps;
  i: Integer;
begin
  Result.Content := Cardinal(AObj.Int64s['content']);
  Result.Fg := Cardinal(AObj.Int64s['fg']);
  Result.Bg := Cardinal(AObj.Int64s['bg']);
  Result.Ext.RawExt := 0;
  Result.Ext.UrlId := 0;
  if AObj.Find('ext') <> nil then
    Result.Ext := TyTermExtFromJson(AObj.Objects['ext']);
  Result.Combined := '';
  if AObj.Find('comb') <> nil then
  begin
    cps := TyTermJsonCps(AObj.Arrays['comb']);
    for i := 0 to High(cps) do
      Result.Combined := Result.Combined + TyTermCpUtf8(cps[i]);
  end;
end;

function TyTermExtQuadJson(const AExt: TTyTerminalExtAttrs): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(Int64(AExt.Ext));
  Result.Add(AExt.UrlId);
  Result.Add(Int64(AExt.UnderlineColor));
  Result.Add(AExt.UnderlineVariantOffset);
end;

function LineText(ALine: TTyTerminalLine): string;
begin
  if ALine = nil then
    Result := '(no line)'
  else
    Result := '"' + ALine.TranslateToString(True, 0, ALine.Length) + '"';
end;

procedure TyTermCompareLine(ALine: TTyTerminalLine; AJson: TJSONObject; ACols: Integer;
  const ACaseId, APath: string; AMisses: TTyTermMisses);
var
  wantLen, col, r, k, n: Integer;
  runs, run: TJSONArray;
  content, fg, bg: array of Cardinal;
  missed: Boolean;
  combs, exts: TJSONObject;
  want, got: TJSONData;
  text: string;
  e: TTyTerminalExtAttrs;

  procedure Miss(const AField, AWant, AGot: string);
  begin
    if missed then
      Exit;
    missed := True;
    AMisses.Add(ACaseId, APath + ' / ' + AField, AWant, AGot + '; want text ' + TyTermCanonJson(AJson.Find('t'))
      + ' got text ' + LineText(ALine));
  end;

begin
  missed := False;
  wantLen := AJson.Get('len', ACols);
  AMisses.AddCompared(2);
  if ALine = nil then
  begin
    Miss('line', 'a line', 'nil');
    AMisses.AddCompared(wantLen);
    Exit;
  end;
  if ALine.Length <> wantLen then
    Miss('length', IntToStr(wantLen), IntToStr(ALine.Length));
  if ALine.IsWrapped <> (AJson.Get('w', 0) = 1) then
    Miss('isWrapped', BoolToStr(AJson.Get('w', 0) = 1, True), BoolToStr(ALine.IsWrapped, True));
  content := nil;
  SetLength(content, wantLen);
  SetLength(fg, wantLen);
  SetLength(bg, wantLen);
  runs := AJson.Arrays['c'];
  col := 0;
  for r := 0 to runs.Count - 1 do
  begin
    run := runs.Arrays[r];
    n := run.Integers[3];
    for k := 1 to n do
    begin
      if col < wantLen then
      begin
        content[col] := Cardinal(run.Int64s[0]);
        fg[col] := Cardinal(run.Int64s[1]);
        bg[col] := Cardinal(run.Int64s[2]);
      end;
      Inc(col);
    end;
  end;
  if col <> wantLen then
    Miss('runs', IntToStr(wantLen) + ' cells', IntToStr(col) + ' cells');
  for col := 0 to wantLen - 1 do
  begin
    AMisses.AddCompared;
    if ALine.GetContent(col) <> content[col] then
      Miss(Format('col %d / content', [col]), '$' + IntToHex(content[col], 8), '$' + IntToHex(ALine.GetContent(col), 8))
    else if ALine.GetFg(col) <> fg[col] then
      Miss(Format('col %d / fg', [col]), '$' + IntToHex(fg[col], 8), '$' + IntToHex(ALine.GetFg(col), 8))
    else if ALine.GetBg(col) <> bg[col] then
      Miss(Format('col %d / bg', [col]), '$' + IntToHex(bg[col], 8), '$' + IntToHex(ALine.GetBg(col), 8));
  end;
  combs := nil;
  if AJson.Find('comb') <> nil then
    combs := AJson.Objects['comb'];
  exts := nil;
  if AJson.Find('ext') <> nil then
    exts := AJson.Objects['ext'];
  for col := 0 to wantLen - 1 do
  begin
    if content[col] and TyTermContentIsCombinedMask <> 0 then
    begin
      AMisses.AddCompared;
      want := nil;
      if combs <> nil then
        want := combs.Find(IntToStr(col));
      if ALine.CombinedEntry(col, text) then
        got := TyTermCpsJson(TyTermUtf8ToCps(text))
      else
        got := TJSONNull.Create;
      try
        if (want = nil) or not TyTermJsonEqual(want, got) then
          Miss(Format('col %d / combined', [col]), TyTermJsonText(want), TyTermJsonText(got));
      finally
        got.Free;
      end;
    end;
    if bg[col] and TyTermBgHasExtended <> 0 then
    begin
      AMisses.AddCompared;
      want := nil;
      if exts <> nil then
        want := exts.Find(IntToStr(col));
      if ALine.ExtendedEntry(col, e) then
        got := TyTermExtQuadJson(e)
      else
        got := TJSONNull.Create;
      try
        if (want = nil) or not TyTermJsonEqual(want, got) then
          Miss(Format('col %d / ext [ext, urlId, ulColor, ulVariant]', [col]), TyTermJsonText(want), TyTermJsonText(got));
      finally
        got.Free;
      end;
    end;
  end;
end;

procedure TyTermCompareDefaultLine(ALine: TTyTerminalLine; ACols: Integer;
  const ACaseId, APath: string; AMisses: TTyTermMisses);
var
  col: Integer;
begin
  AMisses.AddCompared(2);
  if ALine = nil then
  begin
    AMisses.Add(ACaseId, APath, 'a default line', 'nil');
    AMisses.AddCompared(ACols);
    Exit;
  end;
  if (ALine.Length <> ACols) or ALine.IsWrapped then
  begin
    AMisses.Add(ACaseId, APath + ' / default line', Format('%d cells, unwrapped', [ACols]),
      Format('%d cells, wrapped %s; text %s', [ALine.Length, BoolToStr(ALine.IsWrapped, True), LineText(ALine)]));
    AMisses.AddCompared(ACols);
    Exit;
  end;
  for col := 0 to ACols - 1 do
  begin
    AMisses.AddCompared;
    if (ALine.GetContent(col) <> Cardinal(1) shl TyTermContentWidthShift) or (ALine.GetFg(col) <> 0)
      or (ALine.GetBg(col) <> 0) then
    begin
      AMisses.Add(ACaseId, Format('%s / col %d / default cell', [APath, col]), '$00400000 0 0',
        Format('$%.8x $%.8x $%.8x; text %s', [ALine.GetContent(col), ALine.GetFg(col), ALine.GetBg(col), LineText(ALine)]));
      AMisses.AddCompared(ACols - col - 1);
      Exit;
    end;
  end;
end;

procedure CompareInt(const ACaseId, APath: string; AWant, AGot: Int64; AMisses: TTyTermMisses);
begin
  AMisses.AddCompared;
  if AWant <> AGot then
    AMisses.Add(ACaseId, APath, IntToStr(AWant), IntToStr(AGot));
end;

procedure CompareBool(const ACaseId, APath: string; AWant, AGot: Boolean; AMisses: TTyTermMisses);
begin
  AMisses.AddCompared;
  if AWant <> AGot then
    AMisses.Add(ACaseId, APath, BoolToStr(AWant, True), BoolToStr(AGot, True));
end;

function KeyJson(AId: TTyTermCharsetId; AKeyOf: TTyTermCharsetKeyFunc): TJSONData;
var
  k: string;
begin
  if AId = 0 then
    Exit(TJSONNull.Create);
  if Assigned(AKeyOf) then
    k := AKeyOf(AId)
  else
    k := '?' + IntToStr(AId);
  if k = '' then
    Result := TJSONNull.Create
  else
    Result := TJSONString.Create(k);
end;

procedure TyTermCompareBuffer(ABuf: TTyTerminalBuffer; AJson: TJSONObject; ACols: Integer;
  const ACaseId, APath: string; AMisses: TTyTermMisses; AKeyOf: TTyTermCharsetKeyFunc);
var
  saved, lineJson: TJSONObject;
  lines: TJSONArray;
  got: TJSONArray;
  tabs: TIntegerDynArray;
  i, next, row: Integer;
  path: string;
  gotData: TJSONData;
begin
  CompareInt(ACaseId, APath + ' / x', AJson.Integers['x'], ABuf.X, AMisses);
  CompareInt(ACaseId, APath + ' / y', AJson.Integers['y'], ABuf.Y, AMisses);
  CompareInt(ACaseId, APath + ' / ybase', AJson.Integers['ybase'], ABuf.YBase, AMisses);
  CompareInt(ACaseId, APath + ' / ydisp', AJson.Integers['ydisp'], ABuf.YDisp, AMisses);
  CompareInt(ACaseId, APath + ' / length', AJson.Integers['length'], ABuf.Lines.Length, AMisses);
  CompareInt(ACaseId, APath + ' / maxLength', AJson.Int64s['maxLength'], ABuf.Lines.MaxLength, AMisses);
  CompareBool(ACaseId, APath + ' / hasScrollback', AJson.Booleans['hasScrollback'], ABuf.HasScrollback, AMisses);
  CompareInt(ACaseId, APath + ' / scrollTop', AJson.Integers['scrollTop'], ABuf.ScrollTop, AMisses);
  CompareInt(ACaseId, APath + ' / scrollBottom', AJson.Integers['scrollBottom'], ABuf.ScrollBottom, AMisses);
  got := TJSONArray.Create;
  try
    tabs := ABuf.TabStops;
    for i := 0 to High(tabs) do
      got.Add(tabs[i]);
    TyTermCompareJson(AJson.Arrays['tabs'], got, ACaseId, APath + ' / tabs', AMisses);
  finally
    got.Free;
  end;
  saved := AJson.Objects['saved'];
  CompareInt(ACaseId, APath + ' / saved.x', saved.Integers['x'], ABuf.SavedX, AMisses);
  CompareInt(ACaseId, APath + ' / saved.y', saved.Integers['y'], ABuf.SavedY, AMisses);
  CompareInt(ACaseId, APath + ' / saved.fg', saved.Int64s['fg'], ABuf.SavedAttr.Fg, AMisses);
  CompareInt(ACaseId, APath + ' / saved.bg', saved.Int64s['bg'], ABuf.SavedAttr.Bg, AMisses);
  CompareInt(ACaseId, APath + ' / saved.glevel', saved.Integers['glevel'], ABuf.SavedGLevel, AMisses);
  CompareBool(ACaseId, APath + ' / saved.origin', saved.Booleans['origin'], ABuf.SavedOriginMode, AMisses);
  CompareBool(ACaseId, APath + ' / saved.wrap', saved.Booleans['wrap'], ABuf.SavedWraparoundMode, AMisses);
  gotData := KeyJson(ABuf.SavedCharset, AKeyOf);
  try
    TyTermCompareJson(saved.Find('charset'), gotData, ACaseId, APath + ' / saved.charset', AMisses);
  finally
    gotData.Free;
  end;
  got := TJSONArray.Create;
  try
    for i := 0 to High(ABuf.SavedCharsets) do
      got.Add(KeyJson(ABuf.SavedCharsets[i], AKeyOf));
    TyTermCompareJson(saved.Arrays['charsets'], got, ACaseId, APath + ' / saved.charsets', AMisses);
  finally
    got.Free;
  end;
  got := TJSONArray.Create;
  try
    for i := 0 to ABuf.MarkerCount - 1 do
      if not ABuf.Markers[i].IsDisposed then
        got.Add(ABuf.Markers[i].Line);
    TyTermCompareJson(AJson.Arrays['markers'], got, ACaseId, APath + ' / markers', AMisses);
  finally
    got.Free;
  end;
  { lines: the exported ones in row order, every other row a default line }
  lines := AJson.Arrays['lines'];
  next := 0;
  for row := 0 to ABuf.Lines.Length - 1 do
  begin
    path := Format('%s / abs row %d (viewport row %d)', [APath, row, row - ABuf.YBase]);
    if (next < lines.Count) and (lines.Objects[next].Integers['i'] = row) then
    begin
      lineJson := lines.Objects[next];
      Inc(next);
      if lineJson.Find('missing') <> nil then
      begin
        AMisses.AddCompared;
        if ABuf.Lines.Get(row) <> nil then
          AMisses.Add(ACaseId, path, 'no line', LineText(ABuf.Lines.Get(row)));
      end
      else
        TyTermCompareLine(ABuf.Lines.Get(row), lineJson, ACols, ACaseId, path, AMisses);
    end
    else
      TyTermCompareDefaultLine(ABuf.Lines.Get(row), ACols, ACaseId, path, AMisses);
  end;
  AMisses.AddCompared;
  if next <> lines.Count then
    AMisses.Add(ACaseId, APath + ' / lines', Format('%d exported lines within the length', [lines.Count]),
      Format('%d reached', [next]));
end;

function TyTermLinksJson(ALinks: TTyTerminalOscLinks): TJSONArray;
var
  ids, lns: TIntegerDynArray;
  i, k: Integer;
  o: TJSONObject;
  a: TJSONArray;
  d: TTyTerminalLinkData;
begin
  Result := TJSONArray.Create;
  ids := ALinks.LinkIds;
  for i := 0 to High(ids) do
  begin
    ALinks.GetLinkData(ids[i], d);
    o := TJSONObject.Create;
    o.Add('linkId', ids[i]);
    if d.HasId then o.Add('id', d.Id) else o.Add('id', TJSONNull.Create);
    o.Add('uri', d.Uri);
    a := TJSONArray.Create;
    lns := ALinks.LinkLines(ids[i]);
    for k := 0 to High(lns) do
      a.Add(lns[k]);
    o.Add('lines', a);
    Result.Add(o);
  end;
end;

end.
