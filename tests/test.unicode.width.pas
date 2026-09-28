unit test.unicode.width;
{$mode objfpc}{$H+}
{ Character width, join state and string width -- held to xterm.js 6.0.0 itself.

  tools/terminal-oracle/unicode-cases.js runs the real upstream build and asks its own
  UnicodeService, under six variants ('6', '11', '15' and '15-graphemes', the last two
  with ambiguous characters narrow and wide), for: wcwidth of every code point
  (terminal-unicode-width.json); charProperties of every code point after nine
  preceding states (terminal-unicode-join.json); hand-written sequences, every pair of
  representative code points and every triple under '15-graphemes', and
  getStringCellWidth, lone surrogates included (terminal-unicode-cases.json).

  THE RULE IT HOLDS THE PORT TO: every answer equal to upstream's, bit for bit -- the
  packed charProperties value is compared as an integer, not field by field. Each
  oracle test counts its comparisons and asserts the count, so a fixture that reads
  empty or a loop that stops early is red, not green.

  The anchors in TTyUnicodeWidthTests do NOT come from the fixtures: the .inc tables
  and the fixtures leave the same node process, so if the Buffer-pool fix in
  tools/terminal-oracle/lib-dump.js were ever lost, both would go wrong together. The
  anchors were measured apart, against a clean decode of the '15' trie. }
interface
uses Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.Unicode.Width;
type
  TTyUnicodeWidthOracleTests = class(TTestCase)
  private
    FBad: Integer;
    FCompared: Int64;
    FReport: string;
    procedure Miss(const AVariant: string; ACp, APreceding: Cardinal; AWant, AGot: Int64);
    procedure MissText(const AWhat: string);
    procedure AssertNoMiss(const AWhat: string);
    procedure CheckRunShape(const AWhat: string; ARuns: TJSONArray);
  protected
    procedure SetUp; override;
  published
    procedure TestFixturesComeFromThePinnedUpstream;
    procedure TestWcWidthOfEveryCodepoint;
    procedure TestWcWidthBeyondTheLastCodepoint;
    procedure TestCharPropertiesAfterEveryPreceding;
    procedure TestHandSequences;
    procedure TestRepresentativePairsAndTriples;
    procedure TestStringCellWidth;
  end;

  TTyUnicodeWidthTests = class(TTestCase)
  published
    procedure TestPropsFieldsUnpack;
    procedure TestVersionNames;
    procedure TestAnchorsIndependentOfTheFixtures;
    procedure TestMalformedUtf8;
  end;

implementation

uses
  test.designregistry;

const
  PinnedCommitPrefix = 'c58ea36';
  PinnedVersion = '6.0.0';
  CodepointCount = $110000;

type
  TVariant = record
    Id: string;
    Version: TTyUnicodeVersion;
    Amb: Boolean;
  end;
  TVariants = array of TVariant;

const
  { The six variants in the fixtures' order, for the tests that do not read them. }
  FixedVariants: array[0..5] of record
    Id: string;
    Version: TTyUnicodeVersion;
    Amb: Boolean;
  end = (
    (Id: '6'; Version: tuv6; Amb: False),
    (Id: '11'; Version: tuv11; Amb: False),
    (Id: '15'; Version: tuv15; Amb: False),
    (Id: '15+amb'; Version: tuv15; Amb: True),
    (Id: '15-graphemes'; Version: tuv15Graphemes; Amb: False),
    (Id: '15-graphemes+amb'; Version: tuv15Graphemes; Amb: True));

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'terminal-unicode-' + AName + '.json';
end;

function LoadText(const APath: string): string;
var
  sl: TStringList;
begin
  if not FileExists(APath) then
    raise Exception.Create('not found: ' + APath);
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function LoadFixture(const AName: string): TJSONObject;
var
  d: TJSONData;
begin
  d := GetJSON(LoadText(FixturePath(AName)));
  if not (d is TJSONObject) then
  begin
    d.Free;
    raise Exception.Create(AName + ': not a JSON object');
  end;
  Result := TJSONObject(d);
end;

{ The version whose upstream name is AName -- through TyUnicodeVersionName, so a
  swapped name misreads every variant. }
function VersionOf(const AName: string): TTyUnicodeVersion;
var
  v: TTyUnicodeVersion;
begin
  for v := Low(TTyUnicodeVersion) to High(TTyUnicodeVersion) do
    if TyUnicodeVersionName(v) = AName then
      Exit(v);
  raise Exception.Create('no TTyUnicodeVersion is named ''' + AName + '''');
end;

function ReadVariants(ARoot: TJSONObject): TVariants;
var
  arr: TJSONArray;
  o: TJSONObject;
  i: Integer;
begin
  Result := nil;
  arr := ARoot.Arrays['variants'];
  SetLength(Result, arr.Count);
  for i := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[i];
    Result[i].Id := o.Strings['id'];
    Result[i].Version := VersionOf(o.Strings['version']);
    Result[i].Amb := o.Booleans['ambiguousWide'];
  end;
end;

function Hex(AValue: Int64): string;
begin
  Result := '$' + IntToHex(AValue, 1);
end;

{ UTF-8, except that a surrogate code point is written as its three-byte form
  (WTF-8) -- how TyUnicodeStringCellWidth takes a lone surrogate. }
function Wtf8Of(const ACps: array of Cardinal): string;
var
  i: Integer;
  c: Cardinal;
begin
  Result := '';
  for i := 0 to High(ACps) do
  begin
    c := ACps[i];
    if c < $80 then
      Result := Result + Chr(c)
    else if c < $800 then
      Result := Result + Chr($C0 or (c shr 6)) + Chr($80 or (c and $3F))
    else if c < $10000 then
      Result := Result + Chr($E0 or (c shr 12)) + Chr($80 or ((c shr 6) and $3F))
        + Chr($80 or (c and $3F))
    else
      Result := Result + Chr($F0 or (c shr 18)) + Chr($80 or ((c shr 12) and $3F))
        + Chr($80 or ((c shr 6) and $3F)) + Chr($80 or (c and $3F));
  end;
end;

{ UTF-16 units from a fixture -> WTF-8: a valid pair becomes one four-byte sequence,
  every other unit (a lone surrogate included) its own sequence. }
function UnitsToWtf8(AUnits: TJSONArray): string;
var
  cps: array of Cardinal;
  i, n: Integer;
  u, v: Cardinal;
begin
  SetLength(cps, AUnits.Count);
  n := 0;
  i := 0;
  while i < AUnits.Count do
  begin
    u := Cardinal(AUnits.Integers[i]);
    if (u >= $D800) and (u <= $DBFF) and (i + 1 < AUnits.Count) then
    begin
      v := Cardinal(AUnits.Integers[i + 1]);
      if (v >= $DC00) and (v <= $DFFF) then
      begin
        cps[n] := (u - $D800) * $400 + (v - $DC00) + $10000;
        Inc(n);
        Inc(i, 2);
        Continue;
      end;
    end;
    cps[n] := u;
    Inc(n);
    Inc(i);
  end;
  SetLength(cps, n);
  Result := Wtf8Of(cps);
end;

{ ---------------------------------------------------------------- oracle ------------------ }

procedure TTyUnicodeWidthOracleTests.SetUp;
begin
  inherited SetUp;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

{ Formats only the first 30 -- a broken port misses millions of times. }
procedure TTyUnicodeWidthOracleTests.Miss(const AVariant: string; ACp, APreceding: Cardinal;
  AWant, AGot: Int64);
begin
  Inc(FBad);
  if FBad <= 30 then
    FReport := FReport + LineEnding + Format('  %s U+%.4x after %s: want %s, got %s',
      [AVariant, ACp, Hex(APreceding), Hex(AWant), Hex(AGot)]);
end;

procedure TTyUnicodeWidthOracleTests.MissText(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 30 then
    FReport := FReport + LineEnding + '  ' + AWhat;
end;

procedure TTyUnicodeWidthOracleTests.AssertNoMiss(const AWhat: string);
begin
  AssertTrue(Format('%s: %d of %d differ from upstream (first 30):%s',
    [AWhat, FBad, FCompared, FReport]), FBad = 0);
end;

procedure TTyUnicodeWidthOracleTests.CheckRunShape(const AWhat: string; ARuns: TJSONArray);
var
  i: Integer;
begin
  AssertTrue(AWhat + ': a run list has an even length', (ARuns.Count > 0) and (ARuns.Count mod 2 = 0));
  AssertEquals(AWhat + ': the first run starts at 0', 0, ARuns.Integers[0]);
  for i := 1 to ARuns.Count div 2 - 1 do
    AssertTrue(AWhat + ': run starts strictly increase at run ' + IntToStr(i),
      ARuns.Integers[2 * i] > ARuns.Integers[2 * i - 2]);
  AssertTrue(AWhat + ': the last run starts at or below U+10FFFF',
    ARuns.Integers[ARuns.Count - 2] <= $10FFFF);
end;

procedure TTyUnicodeWidthOracleTests.TestFixturesComeFromThePinnedUpstream;
const
  Names: array[0..2] of string = ('width', 'join', 'cases');
var
  root: TJSONObject;
  up: TJSONObject;
  commit, first, incText: string;
  i: Integer;
begin
  first := '';
  for i := 0 to High(Names) do
  begin
    root := LoadFixture(Names[i]);
    try
      up := root.Objects['upstream'];
      AssertEquals(Names[i] + ': upstream name', 'xterm.js', up.Strings['name']);
      AssertEquals(Names[i] + ': upstream version', PinnedVersion, up.Strings['version']);
      commit := up.Strings['commit'];
      AssertEquals(Names[i] + ': a full 40-digit commit', 40, Length(commit));
      AssertEquals(Names[i] + ': the pinned commit', PinnedCommitPrefix, Copy(commit, 1, Length(PinnedCommitPrefix)));
      if i = 0 then
        first := commit
      else
        AssertEquals(Names[i] + ': the same commit as the width fixture', first, commit);
      AssertEquals(Names[i] + ': six variants', 6, root.Arrays['variants'].Count);
    finally
      root.Free;
    end;
  end;
  incText := LoadText(RepoRoot + 'source' + PathDelim + 'tyControls.Unicode.Width.Data.inc');
  AssertTrue('the .inc was generated from the same commit', Pos(first, incText) > 0);
end;

procedure TTyUnicodeWidthOracleTests.TestWcWidthOfEveryCodepoint;
var
  root, tables: TJSONObject;
  runs: TJSONArray;
  vs: TVariants;
  vi, r, n, pass: Integer;
  cp, stop: Cardinal;
  want, got: Integer;
  amb: Boolean;
begin
  root := LoadFixture('width');
  try
    vs := ReadVariants(root);
    tables := root.Objects['wcwidth'];
    for vi := 0 to High(vs) do
    begin
      runs := tables.Arrays[vs[vi].Id];
      CheckRunShape('wcwidth ' + vs[vi].Id, runs);
      n := runs.Count div 2;
      { 6 and 11 have no ambiguous data: both settings must give the same answer (spec 4.3). }
      for pass := 0 to Ord(vs[vi].Version in [tuv6, tuv11]) do
      begin
        if pass = 0 then amb := vs[vi].Amb else amb := not vs[vi].Amb;
        for r := 0 to n - 1 do
        begin
          want := runs.Integers[2 * r + 1];
          if r < n - 1 then stop := Cardinal(runs.Integers[2 * r + 2]) else stop := CodepointCount;
          for cp := Cardinal(runs.Integers[2 * r]) to stop - 1 do
          begin
            got := TyUnicodeWcWidth(cp, vs[vi].Version, amb);
            Inc(FCompared);
            if got <> want then
              Miss(vs[vi].Id + BoolToStr(pass = 1, ' (ambiguous flipped)', ''), cp, 0, want, got);
          end;
        end;
      end;
    end;
  finally
    root.Free;
  end;
  AssertNoMiss('wcwidth');
  AssertEquals('every code point, 6 variants plus the flipped setting under 6 and 11',
    Int64(CodepointCount) * 8, FCompared);
end;

procedure TTyUnicodeWidthOracleTests.TestWcWidthBeyondTheLastCodepoint;
var
  root, oor: TJSONObject;
  cps, ws, ps: TJSONArray;
  vs: TVariants;
  vi, k: Integer;
  cp: Cardinal;
  got: Int64;
begin
  root := LoadFixture('width');
  try
    vs := ReadVariants(root);
    oor := root.Objects['outOfRange'];
    cps := oor.Arrays['codepoints'];
    AssertEquals('three probes beyond U+10FFFF', 3, cps.Count);
    for vi := 0 to High(vs) do
    begin
      ws := oor.Objects['wcwidth'].Arrays[vs[vi].Id];
      ps := oor.Objects['props0'].Arrays[vs[vi].Id];
      for k := 0 to cps.Count - 1 do
      begin
        cp := Cardinal(cps.Integers[k]);
        AssertTrue('probe ' + Hex(cp) + ' is beyond U+10FFFF', cp > $10FFFF);
        got := TyUnicodeWcWidth(cp, vs[vi].Version, vs[vi].Amb);
        Inc(FCompared);
        if got <> ws.Integers[k] then Miss(vs[vi].Id + ' wcwidth', cp, 0, ws.Integers[k], got);
        got := TyUnicodeCharProperties(cp, 0, vs[vi].Version, vs[vi].Amb);
        Inc(FCompared);
        if got <> ps.Integers[k] then Miss(vs[vi].Id + ' charProperties', cp, 0, ps.Integers[k], got);
      end;
    end;
  finally
    root.Free;
  end;
  AssertNoMiss('beyond U+10FFFF');
  AssertEquals('3 probes x 6 variants x 2 functions', 3 * 6 * 2, FCompared);
end;

procedure TTyUnicodeWidthOracleTests.TestCharPropertiesAfterEveryPreceding;
var
  root, props: TJSONObject;
  pre, perVariant, runs: TJSONArray;
  vs: TVariants;
  vi, pk, r, n: Integer;
  cp, stop: Cardinal;
  preceding, want, got: TTyUnicodeCharProps;
  t0: QWord;
begin
  t0 := GetTickCount64;
  root := LoadFixture('join');
  try
    vs := ReadVariants(root);
    pre := root.Arrays['preceding'];
    AssertEquals('nine preceding states', 9, pre.Count);
    props := root.Objects['props'];
    for vi := 0 to High(vs) do
    begin
      perVariant := props.Arrays[vs[vi].Id];
      AssertEquals(vs[vi].Id + ': one run list per preceding state', pre.Count, perVariant.Count);
      for pk := 0 to pre.Count - 1 do
      begin
        preceding := TTyUnicodeCharProps(pre.Integers[pk]);
        runs := perVariant.Arrays[pk];
        CheckRunShape(Format('charProperties %s after %s', [vs[vi].Id, Hex(preceding)]), runs);
        n := runs.Count div 2;
        for r := 0 to n - 1 do
        begin
          want := TTyUnicodeCharProps(runs.Integers[2 * r + 1]);
          if r < n - 1 then stop := Cardinal(runs.Integers[2 * r + 2]) else stop := CodepointCount;
          for cp := Cardinal(runs.Integers[2 * r]) to stop - 1 do
          begin
            got := TyUnicodeCharProperties(cp, preceding, vs[vi].Version, vs[vi].Amb);
            Inc(FCompared);
            if got <> want then
              Miss(vs[vi].Id, cp, preceding, want, got);
          end;
        end;
      end;
    end;
  finally
    root.Free;
  end;
  WriteLn(Format('TestCharPropertiesAfterEveryPreceding: %d comparisons in %d ms',
    [FCompared, GetTickCount64 - t0]));
  AssertNoMiss('charProperties');
  AssertEquals('every code point x 9 preceding states x 6 variants',
    Int64(CodepointCount) * 54, FCompared);
end;

procedure TTyUnicodeWidthOracleTests.TestHandSequences;
var
  root, seq, props: TJSONObject;
  seqs, cps, want: TJSONArray;
  vs: TVariants;
  si, vi, k: Integer;
  total: Int64;
  prev, got: TTyUnicodeCharProps;
begin
  root := LoadFixture('cases');
  total := 0;
  try
    vs := ReadVariants(root);
    seqs := root.Arrays['sequences'];
    AssertTrue('there are hand sequences', seqs.Count > 0);
    for si := 0 to seqs.Count - 1 do
    begin
      seq := seqs.Objects[si];
      AssertEquals(seq.Strings['id'] + ': source', 'hand', seq.Strings['source']);
      cps := seq.Arrays['codepoints'];
      props := seq.Objects['props'];
      Inc(total, cps.Count);
      for vi := 0 to High(vs) do
      begin
        want := props.Arrays[vs[vi].Id];
        AssertEquals(seq.Strings['id'] + ' ' + vs[vi].Id + ': one value per step', cps.Count, want.Count);
        prev := 0;
        for k := 0 to cps.Count - 1 do
        begin
          got := TyUnicodeCharProperties(Cardinal(cps.Integers[k]), prev, vs[vi].Version, vs[vi].Amb);
          Inc(FCompared);
          if got <> TTyUnicodeCharProps(want.Integers[k]) then
            Miss(seq.Strings['id'] + ' ' + vs[vi].Id + ' step ' + IntToStr(k),
              Cardinal(cps.Integers[k]), prev, want.Integers[k], got);
          prev := got;
        end;
      end;
    end;
  finally
    root.Free;
  end;
  AssertNoMiss('hand sequences');
  AssertEquals('every step of every sequence x 6 variants', total * 6, FCompared);
end;

procedure TTyUnicodeWidthOracleTests.TestRepresentativePairsAndTriples;
var
  root, pairs, triples: TJSONObject;
  repsArr, want: TJSONArray;
  reps: array of Cardinal;
  vs: TVariants;
  vi, i, j, k, n, p, s, tripleVariants: Integer;
  seq: array[0..2] of Cardinal;
  prev, got: TTyUnicodeCharProps;

  procedure Walk(const AVariant: TVariant; ALen: Integer);
  var
    st: Integer;
  begin
    prev := 0;
    for st := 0 to ALen - 1 do
    begin
      got := TyUnicodeCharProperties(seq[st], prev, AVariant.Version, AVariant.Amb);
      Inc(FCompared);
      if (p >= want.Count) or (got <> TTyUnicodeCharProps(want.Integers[p])) then
      begin
        if p < want.Count then
          Miss(Format('%s (%s %s %s) step %d', [AVariant.Id, Hex(seq[0]), Hex(seq[1]),
            Hex(seq[2]), st]), seq[st], prev, want.Integers[p], got)
        else
          MissText(AVariant.Id + ': the fixture ran out of values');
      end;
      Inc(p);
      prev := got;
    end;
  end;

begin
  root := LoadFixture('cases');
  try
    vs := ReadVariants(root);
    repsArr := root.Arrays['reps'];
    n := repsArr.Count;
    AssertTrue('there are representative code points', n > 1);
    SetLength(reps, n);
    for i := 0 to n - 1 do
      reps[i] := Cardinal(repsArr.Integers[i]);
    pairs := root.Objects['pairs'];
    triples := root.Objects['triples'];
    tripleVariants := 0;
    for vi := 0 to High(vs) do
    begin
      want := pairs.Arrays[vs[vi].Id];
      AssertEquals(vs[vi].Id + ': pair values', n * n * 2, want.Count);
      p := 0;
      seq[2] := 0;
      for i := 0 to n - 1 do
        for j := 0 to n - 1 do
        begin
          seq[0] := reps[i];
          seq[1] := reps[j];
          Walk(vs[vi], 2);
        end;
      if vs[vi].Version = tuv15Graphemes then
      begin
        Inc(tripleVariants);
        want := triples.Arrays[vs[vi].Id];
        AssertEquals(vs[vi].Id + ': triple values', n * n * n * 3, want.Count);
        p := 0;
        for i := 0 to n - 1 do
          for j := 0 to n - 1 do
            for s := 0 to n - 1 do
            begin
              seq[0] := reps[i];
              seq[1] := reps[j];
              seq[2] := reps[s];
              Walk(vs[vi], 3);
            end;
      end;
    end;
    AssertEquals('triples are given for the two 15-graphemes variants', 2, tripleVariants);
    AssertEquals('and only for them', 2, triples.Count);
  finally
    root.Free;
  end;
  AssertNoMiss('pairs and triples');
  k := n;
  AssertEquals('n^2 x 2 x 6 + n^3 x 3 x 2', Int64(k) * k * 2 * 6 + Int64(k) * k * k * 3 * 2, FCompared);
end;

procedure TTyUnicodeWidthOracleTests.TestStringCellWidth;
var
  root, str, widths: TJSONObject;
  strs: TJSONArray;
  vs: TVariants;
  si, vi, want, got: Integer;
  bytes: string;
begin
  root := LoadFixture('cases');
  try
    vs := ReadVariants(root);
    strs := root.Arrays['strings'];
    AssertTrue('there are strings', strs.Count > 0);
    for si := 0 to strs.Count - 1 do
    begin
      str := strs.Objects[si];
      AssertEquals(str.Strings['id'] + ': source', 'hand', str.Strings['source']);
      bytes := UnitsToWtf8(str.Arrays['units']);
      widths := str.Objects['width'];
      for vi := 0 to High(vs) do
      begin
        want := widths.Integers[vs[vi].Id];
        got := TyUnicodeStringCellWidth(bytes, vs[vi].Version, vs[vi].Amb);
        Inc(FCompared);
        if got <> want then
          MissText(Format('%s %s: want %d, got %d', [str.Strings['id'], vs[vi].Id, want, got]));
      end;
    end;
    AssertNoMiss('getStringCellWidth');
    AssertEquals('every string x 6 variants', Int64(strs.Count) * 6, FCompared);
  finally
    root.Free;
  end;
end;

{ ---------------------------------------------------------------- pure -------------------- }

procedure TTyUnicodeWidthTests.TestPropsFieldsUnpack;
const
  Rows: array[0..4] of record
    Props: Cardinal;
    Width: Integer;
    Join: Boolean;
    Kind: Cardinal;
  end = (
    (Props: 0; Width: 0; Join: False; Kind: 0),
    (Props: $3; Width: 1; Join: True; Kind: 0),
    (Props: $95; Width: 2; Join: True; Kind: $12),
    (Props: $7FFFF9A; Width: 1; Join: False; Kind: $FFFFF3),
    (Props: $7FFFFFF; Width: 3; Join: True; Kind: $FFFFFF));
var
  i: Integer;
  p: TTyUnicodeCharProps;
begin
  for i := 0 to High(Rows) do
  begin
    p := TTyUnicodeCharProps(Rows[i].Props);
    AssertEquals(Hex(Rows[i].Props) + ' width', Rows[i].Width, TyUnicodePropsWidth(p));
    AssertEquals(Hex(Rows[i].Props) + ' shouldJoin', Rows[i].Join, TyUnicodePropsShouldJoin(p));
    AssertEquals(Hex(Rows[i].Props) + ' kind', Int64(Rows[i].Kind), Int64(TyUnicodePropsKind(p)));
  end;
end;

procedure TTyUnicodeWidthTests.TestVersionNames;
begin
  AssertEquals('6', TyUnicodeVersionName(tuv6));
  AssertEquals('11', TyUnicodeVersionName(tuv11));
  AssertEquals('15', TyUnicodeVersionName(tuv15));
  AssertEquals('15-graphemes', TyUnicodeVersionName(tuv15Graphemes));
  AssertEquals('a new version needs its fixtures too -- see tools/terminal-oracle/lib-dump.js VARIANTS',
    3, Ord(High(TTyUnicodeVersion)));
end;

procedure TTyUnicodeWidthTests.TestAnchorsIndependentOfTheFixtures;
type
  TWidthRow = record
    Cp: Cardinal;
    W: array[0..5] of Integer;
  end;
  TPropsRow = record
    V: Integer;                        { index into FixedVariants }
    Cps: array[0..2] of Cardinal;
    Props: array[0..2] of Cardinal;
    Len: Integer;
  end;
const
  Widths: array[0..9] of TWidthRow = (
    (Cp: $7;      W: (0, 0, 1, 1, 1, 1)),
    (Cp: $301;    W: (0, 0, 0, 0, 0, 0)),
    (Cp: $200D;   W: (0, 0, 1, 1, 1, 1)),
    (Cp: $FE0F;   W: (0, 0, 0, 0, 0, 0)),
    (Cp: $2026;   W: (1, 1, 1, 2, 1, 2)),
    (Cp: $1F600;  W: (1, 2, 2, 2, 2, 2)),
    (Cp: $20000;  W: (2, 2, 2, 2, 2, 2)),
    (Cp: $1F1E6;  W: (1, 1, 1, 1, 1, 1)),
    (Cp: $E000;   W: (1, 1, 1, 2, 1, 2)),
    (Cp: $110000; W: (1, 1, 1, 1, 1, 1)));
  Seqs: array[0..6] of TPropsRow = (
    (V: 4; Cps: ($1F1E8, $1F1F3, $1F1FA); Props: ($9A, $105, $7FFFF9A); Len: 3),
    (V: 4; Cps: ($1F468, $200D, $1F469);  Props: ($1DC, $D5, $DD);      Len: 3),
    (V: 4; Cps: ($263A, $FE0F, 0);        Props: ($5A, $95, 0);         Len: 2),
    (V: 4; Cps: ($600, $61, 0);           Props: ($A, $83, 0);          Len: 2),
    (V: 2; Cps: ($61, $301, 0);           Props: ($2, $2, 0);           Len: 2),
    (V: 1; Cps: ($1F468, $200D, $1F469);  Props: ($4, $5, $4);          Len: 3),
    (V: 0; Cps: ($4E00, $301, 0);         Props: ($4, $5, 0);           Len: 2));
  StrWidths: array[0..8] of array[0..5] of Integer = (
    (1, 1, 2, 3, 1, 2),   { e U+0301 }
    (3, 6, 8, 8, 2, 2),   { man ZWJ woman ZWJ girl }
    (3, 3, 3, 3, 3, 3),   { three regional indicators }
    (1, 1, 3, 3, 2, 2),   { U+263A U+FE0F }
    (1, 1, 2, 3, 1, 2),   { U+263A U+FE0E }
    (2, 2, 4, 4, 2, 2),   { Hangul L V T }
    (1, 1, 2, 2, 1, 1),   { U+0600 a }
    (2, 2, 2, 2, 2, 2),   { a, lone high surrogate D83D }
    (3, 3, 3, 3, 3, 3));  { D83D, then the pair D83D DE00 }
var
  strs: array[0..8] of string;
  i, v, k: Integer;
  prev: TTyUnicodeCharProps;
begin
  for i := 0 to High(Widths) do
    for v := 0 to 5 do
      AssertEquals(Format('wcwidth %s under %s', [Hex(Widths[i].Cp), FixedVariants[v].Id]),
        Widths[i].W[v], TyUnicodeWcWidth(Widths[i].Cp, FixedVariants[v].Version, FixedVariants[v].Amb));

  strs[0] := Wtf8Of([$65, $301]);
  strs[1] := Wtf8Of([$1F468, $200D, $1F469, $200D, $1F467]);
  strs[2] := Wtf8Of([$1F1E8, $1F1F3, $1F1FA]);
  strs[3] := Wtf8Of([$263A, $FE0F]);
  strs[4] := Wtf8Of([$263A, $FE0E]);
  strs[5] := Wtf8Of([$1100, $1161, $11A8]);
  strs[6] := Wtf8Of([$600, $61]);
  strs[7] := 'a'#$ED#$A0#$BD;
  strs[8] := #$ED#$A0#$BD + Wtf8Of([$1F600]);
  for i := 0 to High(strs) do
    for v := 0 to 5 do
      AssertEquals(Format('string width #%d under %s', [i, FixedVariants[v].Id]),
        StrWidths[i][v], TyUnicodeStringCellWidth(strs[i], FixedVariants[v].Version, FixedVariants[v].Amb));

  for i := 0 to High(Seqs) do
  begin
    v := Seqs[i].V;
    prev := 0;
    for k := 0 to Seqs[i].Len - 1 do
    begin
      prev := TyUnicodeCharProperties(Seqs[i].Cps[k], prev, FixedVariants[v].Version, FixedVariants[v].Amb);
      AssertEquals(Format('sequence #%d under %s, step %d', [i, FixedVariants[v].Id, k]),
        Int64(Seqs[i].Props[k]), Int64(prev));
    end;
  end;
end;

procedure TTyUnicodeWidthTests.TestMalformedUtf8;
var
  root, str: TJSONObject;
  strs: TJSONArray;
  loneLow: TJSONObject;
  v, i: Integer;
  fffd: string;
  ver: TTyUnicodeVersion;
  amb: Boolean;

  function W(const S: string): Integer;
  begin
    Result := TyUnicodeStringCellWidth(S, ver, amb);
  end;

begin
  loneLow := nil;
  root := TJSONObject(GetJSON(LoadText(FixturePath('cases'))));
  try
    strs := root.Arrays['strings'];
    for i := 0 to strs.Count - 1 do
    begin
      str := strs.Objects[i];
      if str.Strings['id'] = 'lone-low' then
        loneLow := str.Objects['width'];
    end;
    AssertNotNull('the cases fixture has lone-low', loneLow);
    fffd := #$EF#$BF#$BD;
    for v := 0 to 5 do
    begin
      ver := FixedVariants[v].Version;
      amb := FixedVariants[v].Amb;
      AssertEquals(FixedVariants[v].Id + ': empty', 0, W(''));
      AssertEquals(FixedVariants[v].Id + ': a stray FF', W(fffd), W(#$FF));
      AssertEquals(FixedVariants[v].Id + ': a truncated sequence', W(fffd + fffd), W(#$E4#$B8));
      AssertEquals(FixedVariants[v].Id + ': an overlong encoding', W(fffd + fffd), W(#$C0#$80));
      AssertEquals(FixedVariants[v].Id + ': a lone continuation byte', W(fffd + 'a'), W(#$80'a'));
      AssertEquals(FixedVariants[v].Id + ': beyond U+10FFFF', W(fffd + fffd + fffd + fffd), W(#$F4#$90#$80#$80));
      AssertEquals(FixedVariants[v].Id + ': WTF-8 lone low surrogate, as upstream',
        loneLow.Integers[FixedVariants[v].Id], W(#$ED#$B8#$80'a'));
    end;
  finally
    root.Free;
  end;
end;

initialization
  RegisterTest(TTyUnicodeWidthOracleTests);
  RegisterTest(TTyUnicodeWidthTests);
end.
