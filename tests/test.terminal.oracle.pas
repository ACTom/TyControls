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
  Classes, SysUtils, Types, fpjson, jsonparser, base64, tyControls.Unicode.Width,
  tyControls.Terminal.Parser, tyControls.Terminal.Buffer, tyControls.Terminal.Core;

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

{ ---- core layer (Task 18) ---- }

type
  { A core built from a fixture case, with recorders on its events and the palette
    answering OnQueryBaseColor -- what lib-term.js's makeCaseTerminal,
    attachRecorders and attachSynth are on the node side. }
  TTyTermHarness = class
  private
    FPalette: array of Cardinal;
    procedure OnData(Sender: TObject; const AData: RawByteString);
    procedure OnBell(Sender: TObject);
    procedure OnLineFeed(Sender: TObject);
    procedure OnCursorMove(Sender: TObject);
    procedure OnTitle(Sender: TObject; const AText: string);
    procedure OnRender(Sender: TObject; AFirst, ALast: Integer);
    procedure OnScrolled(Sender: TObject; AYDisp: Integer);
    procedure OnQueryColor(Sender: TObject; AIndex: Integer; out ARgb: Cardinal);
    procedure SetPalette(AArr: TJSONArray);
  public
    Core: TTyTerminalCore;
    Data: RawByteString;
    Bells, LineFeeds, CursorMoves: Integer;
    Titles: TStringList;
    Renders: array of TPoint;
    Scrolls: array of Integer;
    constructor Create(ACase: TJSONObject; AFilePalette: TJSONArray);
    destructor Destroy; override;
    procedure ClearRecord;
    procedure SetOption(const AName: string; AValue: TJSONData);
    { AVariant nil: the steps as they are; otherwise the single write cut up }
    procedure Run(ASteps: TJSONArray; AVariant: TJSONObject = nil);
  end;

{ Every field of the plan's state against AExpect. AVariant skips renders and
  cursorMoves, which follow the number of parse calls. }
procedure TyTermCompareState(AHarness: TTyTermHarness; AExpect: TJSONObject; const ACaseId: string;
  AVariant: Boolean; AMisses: TTyTermMisses);
{ New core, run, compare; Reset on the same core, run again, compare with afterReset;
  then each variant on a new core. Returns the comparisons it made. }
function TyTermRunCase(ACase: TJSONObject; AFilePalette: TJSONArray; AMisses: TTyTermMisses): Int64;
{ The UTF-8 bytes of the reply stream with our XTVERSION name swapped for the
  placeholder the node side uses (spec 13.5 #3). }
function TyTermNormalizeData(const AData: RawByteString): RawByteString;
function TyTermUnicodeVersionOf(const AName: string): TTyUnicodeVersion;

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

{ ---- core layer ------------------------------------------------------------------------ }

function TyTermUnicodeVersionOf(const AName: string): TTyUnicodeVersion;
var
  v: TTyUnicodeVersion;
begin
  for v := Low(TTyUnicodeVersion) to High(TTyUnicodeVersion) do
    if TyUnicodeVersionName(v) = AName then
      Exit(v);
  raise Exception.Create('unknown Unicode version ' + AName);
end;

function TyTermNormalizeData(const AData: RawByteString): RawByteString;
const
  Ours = 'TyControls(' + TyTermLibraryVersion + ')';
begin
  Result := StringReplace(AData, Ours, #0'VERSION'#0, [rfReplaceAll]);
end;

constructor TTyTermHarness.Create(ACase: TJSONObject; AFilePalette: TJSONArray);
var
  opts, synth: TJSONObject;
  i: Integer;
begin
  inherited Create;
  Titles := TStringList.Create;
  Core := TTyTerminalCore.Create(ACase.Get('cols', 20), ACase.Get('rows', 6));
  synth := nil;
  if ACase.Find('synth') <> nil then
    synth := ACase.Objects['synth'];
  if (synth <> nil) and (synth.Find('palette') <> nil) then
    SetPalette(synth.Arrays['palette'])
  else
    SetPalette(AFilePalette);
  if ACase.Find('options') <> nil then
  begin
    opts := ACase.Objects['options'];
    for i := 0 to opts.Count - 1 do
      SetOption(opts.Names[i], opts.Items[i]);
  end;
  Core.OnData := @OnData;
  Core.OnBell := @OnBell;
  Core.OnLineFeed := @OnLineFeed;
  Core.OnCursorMove := @OnCursorMove;
  Core.OnTitleChange := @OnTitle;
  Core.OnRefreshRows := @OnRender;
  Core.OnScroll := @OnScrolled;
  Core.OnQueryBaseColor := @OnQueryColor;
  { 1004 is off: nothing is sent }
  Core.ReportFocus((synth = nil) or synth.Get('focused', True));
end;

destructor TTyTermHarness.Destroy;
begin
  Core.Free;
  Titles.Free;
  inherited Destroy;
end;

procedure TTyTermHarness.SetPalette(AArr: TJSONArray);
var
  i: Integer;
begin
  FPalette := nil;
  SetLength(FPalette, AArr.Count);
  for i := 0 to AArr.Count - 1 do
    FPalette[i] := Cardinal(AArr.Int64s[i]);
end;

procedure TTyTermHarness.ClearRecord;
begin
  Data := '';
  Bells := 0;
  LineFeeds := 0;
  CursorMoves := 0;
  Titles.Clear;
  Renders := nil;
  Scrolls := nil;
end;

procedure TTyTermHarness.OnData(Sender: TObject; const AData: RawByteString);
begin
  Data := Data + AData;
end;

procedure TTyTermHarness.OnBell(Sender: TObject);
begin
  Inc(Bells);
end;

procedure TTyTermHarness.OnLineFeed(Sender: TObject);
begin
  Inc(LineFeeds);
end;

procedure TTyTermHarness.OnCursorMove(Sender: TObject);
begin
  Inc(CursorMoves);
end;

procedure TTyTermHarness.OnTitle(Sender: TObject; const AText: string);
begin
  Titles.Add(AText);
end;

procedure TTyTermHarness.OnRender(Sender: TObject; AFirst, ALast: Integer);
begin
  SetLength(Renders, Length(Renders) + 1);
  Renders[High(Renders)] := Point(AFirst, ALast);
end;

procedure TTyTermHarness.OnScrolled(Sender: TObject; AYDisp: Integer);
begin
  SetLength(Scrolls, Length(Scrolls) + 1);
  Scrolls[High(Scrolls)] := AYDisp;
end;

procedure TTyTermHarness.OnQueryColor(Sender: TObject; AIndex: Integer; out ARgb: Cardinal);
begin
  if (AIndex >= 0) and (AIndex <= High(FPalette)) then
    ARgb := FPalette[AIndex]
  else
    ARgb := 0;
end;

{ the plan's option names -> core properties }
procedure TTyTermHarness.SetOption(const AName: string; AValue: TJSONData);
var
  o: TJSONObject;
  i: Integer;
  wp: TTyTerminalWindowsPty;
  wo: TTyTerminalWindowOptions;
  ve: TTyTerminalVtExtensions;
  n: string;
  opt: TTyTermWindowOption;
const
  WindowOptionNames: array[TTyTermWindowOption] of string = ('restoreWin', 'minimizeWin', 'setWinPosition',
    'setWinSizePixels', 'raiseWin', 'lowerWin', 'refreshWin', 'setWinSizeChars', 'maximizeWin',
    'fullscreenWin', 'getWinState', 'getWinPosition', 'getWinSizePixels', 'getScreenSizePixels',
    'getCellSizePixels', 'getWinSizeChars', 'getScreenSizeChars', 'getIconTitle', 'getWinTitle',
    'pushTitle', 'popTitle', 'setWinLines');
begin
  if AName = 'scrollback' then Core.Scrollback := AValue.AsInteger
  else if AName = 'tabStopWidth' then Core.TabStopWidth := AValue.AsInteger
  else if AName = 'convertEol' then Core.ConvertEol := AValue.AsBoolean
  else if AName = 'scrollOnUserInput' then Core.ScrollOnUserInput := AValue.AsBoolean
  else if AName = 'disableStdin' then Core.ReadOnly := AValue.AsBoolean
  else if AName = 'scrollOnEraseInDisplay' then Core.ScrollOnEraseInDisplay := AValue.AsBoolean
  else if AName = 'cursorBlink' then Core.CursorBlink := AValue.AsBoolean
  else if AName = 'allowSetCursorBlink' then Core.AllowSetCursorBlink := AValue.AsBoolean
  else if AName = 'ambiguousWide' then Core.AmbiguousWide := AValue.AsBoolean
  else if AName = 'unicodeVersion' then Core.UnicodeVersion := TyTermUnicodeVersionOf(AValue.AsString)
  else if AName = 'cursorStyle' then
  begin
    n := AValue.AsString;
    if n = 'underline' then Core.CursorStyle := tcoUnderline
    else if n = 'bar' then Core.CursorStyle := tcoBar
    else Core.CursorStyle := tcoBlock;
  end
  else if AName = 'windowsPty' then
  begin
    wp.Backend := twpNone;
    wp.BuildNumber := 0;
    if AValue.JSONType = jtObject then
    begin
      o := TJSONObject(AValue);
      if o.Get('backend', '') = 'conpty' then wp.Backend := twpConPty
      else if o.Get('backend', '') = 'winpty' then wp.Backend := twpWinPty;
      wp.BuildNumber := o.Get('buildNumber', 0);
    end;
    Core.WindowsPty := wp;
  end
  else if AName = 'windowOptions' then
  begin
    wo := [];
    for i := 0 to AValue.Count - 1 do
      for opt := Low(TTyTermWindowOption) to High(TTyTermWindowOption) do
        if WindowOptionNames[opt] = AValue.Items[i].AsString then
          Include(wo, opt);
    Core.WindowOptions := wo;
  end
  else if AName = 'vtExtensions' then
  begin
    o := TJSONObject(AValue);
    ve := Core.VtExtensions;
    for i := 0 to o.Count - 1 do
    begin
      n := o.Names[i];
      if n = 'kittyKeyboard' then
      begin
        if o.Items[i].AsBoolean then Include(ve, tveKittyKeyboard) else Exclude(ve, tveKittyKeyboard);
      end
      else if n = 'win32InputMode' then
      begin
        if o.Items[i].AsBoolean then Include(ve, tveWin32InputMode) else Exclude(ve, tveWin32InputMode);
      end
      else if n = 'kittySgrBoldFaintControl' then
      begin
        if o.Items[i].AsBoolean then Include(ve, tveKittySgrBoldFaint) else Exclude(ve, tveKittySgrBoldFaint);
      end
      else if n = 'colorSchemeQuery' then
      begin
        if o.Items[i].AsBoolean then Include(ve, tveColorSchemeQuery) else Exclude(ve, tveColorSchemeQuery);
      end;
    end;
    Core.VtExtensions := ve;
  end
  else
    raise Exception.Create('unknown option ' + AName);
end;

procedure TTyTermHarness.Run(ASteps: TJSONArray; AVariant: TJSONObject);
var
  k, t, prev, cut: Integer;
  s: TJSONObject;
  bytes: RawByteString;
  cuts: TJSONData;
  o: TJSONObject;
begin
  if AVariant <> nil then
  begin
    { one write, cut up: every piece its own parse call }
    bytes := TyTermBase64Bytes(ASteps.Objects[0].Strings['write']);
    cuts := AVariant.Find('cuts');
    if cuts.JSONType = jtString then
    begin
      for k := 1 to Length(bytes) do
        Core.WriteSync(bytes[k]);
    end
    else
    begin
      prev := 0;
      for k := 0 to cuts.Count - 1 do
      begin
        cut := cuts.Items[k].AsInteger;
        Core.WriteSync(Copy(bytes, prev + 1, cut - prev));
        prev := cut;
      end;
      Core.WriteSync(Copy(bytes, prev + 1, MaxInt));
    end;
    Exit;
  end;
  for k := 0 to ASteps.Count - 1 do
  begin
    s := ASteps.Objects[k];
    if s.Find('write') <> nil then
      Core.WriteSync(TyTermBase64Bytes(s.Strings['write']))
    else if s.Find('writeRepeat') <> nil then
    begin
      o := s.Objects['writeRepeat'];
      bytes := TyTermBase64Bytes(o.Strings['b64']);
      for t := 1 to o.Integers['times'] do
        Core.WriteSync(bytes);
    end
    else if s.Find('resize') <> nil then
      Core.Resize(s.Arrays['resize'].Integers[0], s.Arrays['resize'].Integers[1])
    else if s.Find('input') <> nil then
      Core.Input(TyTermBase64Bytes(s.Strings['input']), s.Booleans['user'])
    else if s.Find('reset') <> nil then
      Core.Reset
    else if s.Find('clear') <> nil then
      Core.ClearScrollback
    else if s.Find('scrollLines') <> nil then
      Core.ScrollLines(s.Integers['scrollLines'])
    else if s.Find('scrollToTop') <> nil then
      Core.ScrollToTop
    else if s.Find('scrollToBottom') <> nil then
      Core.ScrollToBottom
    else if s.Find('setOption') <> nil then
    begin
      o := s.Objects['setOption'];
      for t := 0 to o.Count - 1 do
        SetOption(o.Names[t], o.Items[t]);
    end
    else if s.Find('focus') <> nil then
      Core.ReportFocus(s.Booleans['focus'])
    else if s.Find('theme') <> nil then
    begin
      SetPalette(s.Arrays['theme']);
      Core.NotifyColorSchemeChanged;
    end
    else
      raise Exception.Create('unknown step ' + s.AsJSON);
  end;
end;

var
  GKeyCore: TTyTerminalCore;

function HarnessCharsetKey(AId: TTyTermCharsetId): string;
begin
  Result := GKeyCore.CharsetKey(AId);
end;

function KeyOrNull(ACore: TTyTerminalCore; AId: TTyTermCharsetId): TJSONData;
begin
  if AId = 0 then
    Result := TJSONNull.Create
  else
    Result := TJSONString.Create(ACore.CharsetKey(AId));
end;

procedure TyTermCompareState(AHarness: TTyTermHarness; AExpect: TJSONObject; const ACaseId: string;
  AVariant: Boolean; AMisses: TTyTermMisses);
var
  core: TTyTerminalCore;
  got: TJSONObject;
  modes, charset, opts: TJSONObject;
  arr, a2: TJSONArray;
  m: TTyTerminalModes;
  i, k: Integer;
  want: TJSONData;
  s: string;
  stacks: TStringDynArray;
  ints: TIntegerDynArray;
const
  Protocols: array[TTyTerminalMouseProtocol] of string = ('NONE', 'X10', 'VT200', 'DRAG', 'ANY');
  Encodings: array[TTyTerminalMouseEncoding] of string = ('DEFAULT', 'SGR', 'SGR_PIXELS');
  Styles: array[TTyTermCursorRequest] of string = ('', 'block', 'underline', 'bar');
begin
  core := AHarness.Core;
  GKeyCore := core;
  got := TJSONObject.Create;
  try
    if core.Buffers.IsAlt then s := 'alt' else s := 'normal';
    got.Add('active', s);
    got.Add('isUserScrolling', core.BufferService.IsUserScrolling);
    m := core.Modes;
    modes := TJSONObject.Create;
    modes.Add('applicationCursorKeys', m.ApplicationCursorKeys);
    modes.Add('applicationKeypad', m.ApplicationKeypad);
    modes.Add('bracketedPaste', m.BracketedPaste);
    modes.Add('insert', m.Insert);
    modes.Add('origin', m.Origin);
    modes.Add('reverseWraparound', m.ReverseWraparound);
    modes.Add('sendFocus', m.SendFocus);
    modes.Add('showCursor', m.ShowCursor);
    modes.Add('synchronizedOutput', m.SynchronizedOutput);
    modes.Add('win32Input', m.Win32Input);
    modes.Add('wraparound', m.Wraparound);
    modes.Add('colorSchemeUpdates', m.ColorSchemeUpdates);
    modes.Add('mouseProtocol', Protocols[m.MouseProtocol]);
    modes.Add('mouseEncoding', Encodings[m.MouseEncoding]);
    if m.CursorRequest = tcrDefault then modes.Add('cursorStyle', TJSONNull.Create)
    else modes.Add('cursorStyle', Styles[m.CursorRequest]);
    case m.BlinkRequest of
      tbrDefault: modes.Add('cursorBlink', TJSONNull.Create);
      tbrOn: modes.Add('cursorBlink', True);
    else
      modes.Add('cursorBlink', False);
    end;
    modes.Add('kittyFlags', core.KittyFlags);
    arr := TJSONArray.Create;
    arr.Add(core.KittyMainFlags);
    arr.Add(core.KittyAltFlags);
    for k := 0 to 1 do
    begin
      a2 := TJSONArray.Create;
      ints := core.KittyStacks(k = 1);
      for i := 0 to High(ints) do
        a2.Add(ints[i]);
      arr.Add(a2);
    end;
    modes.Add('kittyStacks', arr);
    modes.Add('cursorInitialized', core.IsCursorInitialized);
    got.Add('modes', modes);
    opts := TJSONObject.Create;
    opts.Add('convertEol', core.ConvertEol);
    opts.Add('cursorBlink', core.CursorBlink);
    got.Add('options', opts);
    charset := TJSONObject.Create;
    charset.Add('glevel', core.GLevel);
    arr := TJSONArray.Create;
    for k := 0 to 3 do
      arr.Add(KeyOrNull(core, core.CharsetOfG(k)));
    charset.Add('g', arr);
    got.Add('charset', charset);
    got.Add('title', TyTermDigestableJson(core.Title));
    got.Add('iconName', TyTermDigestableJson(core.IconName));
    arr := TJSONArray.Create;
    a2 := TJSONArray.Create;
    stacks := core.WindowTitleStack;
    for i := 0 to High(stacks) do
      a2.Add(TyTermDigestableJson(stacks[i]));
    arr.Add(a2);
    a2 := TJSONArray.Create;
    stacks := core.IconNameStack;
    for i := 0 to High(stacks) do
      a2.Add(TyTermDigestableJson(stacks[i]));
    arr.Add(a2);
    got.Add('titleStacks', arr);
    got.Add('bells', AHarness.Bells);
    got.Add('lineFeeds', AHarness.LineFeeds);
    got.Add('cursorMoves', AHarness.CursorMoves);
    arr := TJSONArray.Create;
    for i := 0 to AHarness.Titles.Count - 1 do
      arr.Add(TyTermDigestableJson(AHarness.Titles[i]));
    got.Add('titles', arr);
    arr := TJSONArray.Create;
    for i := 0 to High(AHarness.Renders) do
      arr.Add(TJSONArray.Create([AHarness.Renders[i].X, AHarness.Renders[i].Y]));
    got.Add('renders', arr);
    arr := TJSONArray.Create;
    for i := 0 to High(AHarness.Scrolls) do
      arr.Add(AHarness.Scrolls[i]);
    got.Add('scrolls', arr);
    got.Add('links', TyTermLinksJson(core.Links));
    got.Add('parserState', Ord(core.Parser.CurrentState));
    got.Add('joinState', Int64(core.Parser.PrecedingJoinState));

    for i := 0 to got.Count - 1 do
    begin
      if AVariant and ((got.Names[i] = 'renders') or (got.Names[i] = 'cursorMoves')) then
        Continue;
      want := AExpect.Find(got.Names[i]);
      TyTermCompareJson(want, got.Items[i], ACaseId, got.Names[i], AMisses);
    end;
    { the reply bytes, normalised }
    AMisses.AddCompared;
    if TyTermBase64Bytes(AExpect.Strings['data']) <> TyTermNormalizeData(AHarness.Data) then
      AMisses.Add(ACaseId, 'data', EncodeStringBase64(TyTermBase64Bytes(AExpect.Strings['data'])),
        EncodeStringBase64(TyTermNormalizeData(AHarness.Data)) + ' (base64)');
    TyTermCompareBuffer(core.Buffers.Normal, AExpect.Objects['buffers'].Objects['normal'], core.Cols,
      ACaseId, 'normal', AMisses, @HarnessCharsetKey);
    TyTermCompareBuffer(core.Buffers.Alt, AExpect.Objects['buffers'].Objects['alt'], core.Cols,
      ACaseId, 'alt', AMisses, @HarnessCharsetKey);
  finally
    got.Free;
  end;
end;

function TyTermRunCase(ACase: TJSONObject; AFilePalette: TJSONArray; AMisses: TTyTermMisses): Int64;
var
  h: TTyTermHarness;
  id: string;
  before: Int64;
  after: TJSONData;
  variants: TJSONArray;
  k: Integer;
begin
  before := AMisses.Compared;
  id := ACase.Strings['id'];
  h := TTyTermHarness.Create(ACase, AFilePalette);
  try
    h.Run(ACase.Arrays['steps']);
    TyTermCompareState(h, ACase.Objects['expect'], id, False, AMisses);
    { the same core again after Reset (spec 13.5 #5) }
    h.Core.Reset;
    h.ClearRecord;
    h.Run(ACase.Arrays['steps']);
    after := ACase.Find('afterReset');
    if (after = nil) or (after.JSONType = jtString) then
      TyTermCompareState(h, ACase.Objects['expect'], id + ' after Reset', False, AMisses)
    else
      TyTermCompareState(h, TJSONObject(after), id + ' after Reset', False, AMisses);
  finally
    h.Free;
  end;
  if ACase.Find('variants') <> nil then
  begin
    variants := ACase.Arrays['variants'];
    for k := 0 to variants.Count - 1 do
    begin
      h := TTyTermHarness.Create(ACase, AFilePalette);
      try
        h.Run(ACase.Arrays['steps'], variants.Objects[k]);
        TyTermCompareState(h, ACase.Objects['expect'], Format('%s variant %d', [id, k]), True, AMisses);
      finally
        h.Free;
      end;
    end;
  end;
  Result := AMisses.Compared - before;
end;

end.
