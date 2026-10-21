unit ugenerated;

{$mode objfpc}{$H+}

{ THE GALLERY'S GENERATED DATA, MADE HERE.

  Five gallery examples compute between one and sixty-four megabytes of data
  with a few lines of code: a random walk of half a million bars, two hundred
  thousand candlesticks, a noise field, a million scattered points. The
  harvest does not ship that data. It keeps each option with those arrays
  empty and says, in gallery/index.json, which paths this unit fills
  (`generated.fill`: the path, how many items, and a hash of them); the demo
  fills them before it hands the option to the chart.

  EACH GENERATOR IS THE PAGE'S OWN CODE, in Pascal, on the same random
  numbers the harvest gave it (--seeded: the oracles' xorshift32, seeded
  2463534242, fresh for every example), with JavaScript's arithmetic where it
  differs from Pascal's: Math.round, Math.sin, a Float32Array's rounding,
  toFixed, and a default sort, which compares numbers as text. The test suite
  (TAdvChartGalleryGeneratedTest) holds every array to the harvest's hash, so
  the data drawn is the data upstream's page would have made.

  THE HASH is the harvest's: FNV-1a (32 bit) over a walk of the value -- 'n'
  and the sixteen hex digits of a number's IEEE bits, 's' a string and a NUL,
  '[' ... ']' around an array.

  [R2-J2] custom-wind is the sixth: its 65,160 wind vectors come from
  data-gl's winds.json, which this demo ships gzipped in data/ (176 KB in
  place of 5.3 MB of option), through the page's loop and its shuffle.

  A filled option is text, as every option is: GalleryFillGenerated writes
  each array straight into the option text where the empty one was (the rest
  of the text untouched), each number as the seventeen significant digits
  that read back as the same double. }

interface

uses
  Classes, SysUtils;

type
  { What a generator writes into: one sink per path it fills. }
  TGenSink = class
  public
    procedure BeginArr; virtual; abstract;
    procedure EndArr; virtual; abstract;
    procedure Num(A: Double); virtual; abstract;
    procedure Str(const A: string); virtual; abstract;
  end;

{ [R2-J2] The folder the data files are read from (data/ beside gallery/):
  winds.json.gz, scatter-painter-choice-marker.json. The demo and the tests
  set it before a chart draws. }
var
  GalleryDataDir: string = '';

{ Whether AId is a generated example of the gallery. }
function GalleryIsGenerated(const AId: string): Boolean;

{ [R2-J3] a gzipped data file's text ('' when it cannot be read) }
function GalleryReadGz(const AFile: string): string;

{ The paths AId's generator fills, in its order ('xAxis.data',
  'series.0.data'). }
function GalleryGeneratedPaths(const AId: string): TStringArray;

{ Run AId's generator into ASinks, one per path; False for an id that is
  not generated or a sink count that is not its paths'. }
function GalleryGenerate(const AId: string; const ASinks: array of TGenSink): Boolean;

{ ASkeleton (the gallery file) with its generated arrays filled; False, and
  AText the skeleton, when AId is not generated or the skeleton does not
  parse. }
function GalleryFillGenerated(const AId, ASkeleton: string; out AText: string): Boolean;

{ The harvest's hash of one path's array, and its length. }
function GalleryGeneratedHash(const AId: string; out AHashes: TStringArray;
  out ACounts: array of Integer): Boolean;

implementation

uses
  Math, zstream,
  tyControls.AdvanceChart.JsMath, tyControls.AdvanceChart.Scale,
  tyControls.AdvanceChart.Time, tyControls.AdvanceChart.Data;

{ ==================== Math.random ==================== }

type
  TJsRandom = record
    State: LongWord;
  end;

procedure RandomInit(var R: TJsRandom);
begin
  R.State := 2463534242;
end;

function JsRandom(var R: TJsRandom): Double;
var x: LongWord;
begin
  x := R.State;
  x := x xor (x shl 13);
  x := x xor (x shr 17);
  x := x xor (x shl 5);
  R.State := x;
  Result := x / 4294967296;
end;

{ ==================== the sinks ==================== }

type
  { JSON text, numbers in seventeen significant digits }
  TTextSink = class(TGenSink)
  private
    FBuf: string;
    FLen: Integer;
    FFirst: array of Boolean;
    FFmt: TFormatSettings;
    procedure Put(const S: string);
    procedure Sep;
  public
    constructor Create;
    procedure BeginArr; override;
    procedure EndArr; override;
    procedure Num(A: Double); override;
    procedure Str(const A: string); override;
    function Text: string;
  end;

  { the harvest's FNV-1a walk }
  THashSink = class(TGenSink)
  private
    FHash: LongWord;
    FDepth: Integer;
    procedure Feed(const S: string);
  public
    Count: Integer;
    constructor Create;
    procedure BeginArr; override;
    procedure EndArr; override;
    procedure Num(A: Double); override;
    procedure Str(const A: string); override;
    function HashText: string;
  end;

constructor TTextSink.Create;
begin
  inherited Create;
  FFmt := DefaultFormatSettings;
  FFmt.DecimalSeparator := '.';
  SetLength(FBuf, 1 shl 16);
  FLen := 0;
end;

procedure TTextSink.Put(const S: string);
var n: Integer;
begin
  n := Length(S);
  if n = 0 then Exit;
  while FLen + n > Length(FBuf) do SetLength(FBuf, Length(FBuf) * 2);
  Move(S[1], FBuf[FLen + 1], n);
  Inc(FLen, n);
end;

procedure TTextSink.Sep;
begin
  if Length(FFirst) = 0 then Exit;
  if FFirst[High(FFirst)] then FFirst[High(FFirst)] := False
  else Put(',');
end;

procedure TTextSink.BeginArr;
begin
  Sep;
  Put('[');
  SetLength(FFirst, Length(FFirst) + 1);
  FFirst[High(FFirst)] := True;
end;

procedure TTextSink.EndArr;
begin
  Put(']');
  SetLength(FFirst, Length(FFirst) - 1);
end;

procedure TTextSink.Num(A: Double);
begin
  Sep;
  if IsNan(A) or IsInfinite(A) then Put('null')
  else if (Frac(A) = 0) and (Abs(A) < 1e15) then Put(IntToStr(Trunc(A)))
  else Put(FloatToStrF(A, ffGeneral, 17, 0, FFmt));
end;

procedure TTextSink.Str(const A: string);
var
  i: Integer;
  s: string;
begin
  Sep;
  s := '"';
  for i := 1 to Length(A) do
    case A[i] of
      '"': s := s + '\"';
      '\': s := s + '\\';
      #10: s := s + '\n';
      #13: s := s + '\r';
      #9: s := s + '\t';
    else
      if A[i] < ' ' then s := s + '\u' + IntToHex(Ord(A[i]), 4)
      else s := s + A[i];
    end;
  Put(s + '"');
end;

function TTextSink.Text: string;
begin
  Result := Copy(FBuf, 1, FLen);
end;

constructor THashSink.Create;
begin
  inherited Create;
  FHash := $811C9DC5;
end;

procedure THashSink.Feed(const S: string);
var i: Integer;
begin
  for i := 1 to Length(S) do
  begin
    FHash := FHash xor Ord(S[i]);
    FHash := LongWord(QWord(FHash) * $01000193);
  end;
end;

{ the top array's items are counted }
procedure THashSink.BeginArr;
begin
  if FDepth = 1 then Inc(Count);
  Inc(FDepth);
  Feed('[');
end;

procedure THashSink.EndArr;
begin
  Dec(FDepth);
  Feed(']');
end;

procedure THashSink.Num(A: Double);
var q: QWord;
begin
  if FDepth = 1 then Inc(Count);
  if IsNan(A) then q := $7FF8000000000000
  else Move(A, q, SizeOf(q));
  Feed('n' + LowerCase(IntToHex(q, 16)));
end;

procedure THashSink.Str(const A: string);
begin
  if FDepth = 1 then Inc(Count);
  Feed('s' + A + #0);
end;

function THashSink.HashText: string;
begin
  Result := LowerCase(IntToHex(FHash, 8));
end;

{ ==================== the generators ==================== }

const
  { +new Date(2011, 0, 1) where the harvest ran: at UTC }
  cJan2011 = 1293840000000;

{ formatTime('yyyy-MM-dd\nhh:mm:ss', t) at UTC for a whole millisecond
  count -- the stamp TyFormatTime(t, cStamp, True) gives, made directly:
  half a million of them are made for bar-large }
function Stamp(AMs: Double): string;
var
  days, msDay, z, era, doe, yoe, y, doy, mp, d, m: Int64;

  function Two(AN: Int64): string;
  begin
    if AN < 10 then Result := '0' + IntToStr(AN) else Result := IntToStr(AN);
  end;

begin
  { in Int64: a literal 86400000.0 is a Single to the compiler, and a day
    count times it lost the seconds }
  msDay := Trunc(AMs);
  days := msDay div 86400000;
  if msDay mod 86400000 < 0 then Dec(days);
  msDay := msDay - days * 86400000;
  { civil_from_days }
  z := days + 719468;
  if z >= 0 then era := z div 146097 else era := (z - 146096) div 146097;
  doe := z - era * 146097;
  yoe := (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365;
  y := yoe + era * 400;
  doy := doe - (365 * yoe + yoe div 4 - yoe div 100);
  mp := (5 * doy + 2) div 153;
  d := doy - (153 * mp + 2) div 5 + 1;
  if mp < 10 then m := mp + 3 else m := mp - 9;
  if m <= 2 then Inc(y);
  Result := IntToStr(y) + '-' + Two(m) + '-' + Two(d) + #10
    + Two(msDay div 3600000) + ':' + Two((msDay div 60000) mod 60) + ':'
    + Two((msDay div 1000) mod 60);
end;

{ x.toFixed(2): a whole number below 1e21 is its digits and '.00' }
function ToFixed2(AV: Double): string;
begin
  if (Frac(AV) = 0) and (Abs(AV) < 1e15) then
  begin
    if AV = 0 then Exit('0.00');
    Exit(IntToStr(Trunc(AV)) + '.00');
  end;
  Result := TyJsToFixedStr(AV, 2);
end;

{ bar-large's generateData(5e5): a category per second and a random walk
  on two scales, written as toFixed(2) }
procedure GenBarLarge(ACat, AVal: TGenSink);
var
  r: TJsRandom;
  baseValue, smallBaseValue, time, v: Double;
  i: Integer;
begin
  RandomInit(r);
  baseValue := JsRandom(r) * 1000;
  time := cJan2011;
  smallBaseValue := 0;
  ACat.BeginArr;
  AVal.BeginArr;
  for i := 0 to 500000 - 1 do
  begin
    ACat.Str(Stamp(time));
    { next(i) }
    if i mod 30 = 0 then smallBaseValue := JsRandom(r) * 700
    else smallBaseValue := smallBaseValue + JsRandom(r) * 500 - 250;
    baseValue := baseValue + JsRandom(r) * 20 - 10;
    v := TyJsRound(baseValue + smallBaseValue) + 3000;
    if not (v > 0) then v := 0;
    AVal.Str(ToFixed2(v));
    time := time + 1000;
  end;
  ACat.EndArr;
  AVal.EndArr;
end;

{ the digits of the whole part of |A| (1 below one) }
function IntDigits(A: Double): Integer;
begin
  A := Abs(A);
  Result := 1;
  while A >= 10 do
  begin
    A := A / 10;
    Inc(Result);
  end;
end;

{ String(A) against String(B), as the sort compares them. Two numbers of one
  sign, the same count of whole digits and written without an exponent
  (1e-6 up to 1e21) compare as text the way they compare as numbers -- their
  shortest digits keep their order, a shorter one that is the other's start
  is the smaller -- by their magnitude; anything else is turned into text. }
function CompareAsText(A, B: Double): Integer;
begin
  if A = B then Exit(0);
  if (Sign(A) = Sign(B)) and (A <> 0) and (B <> 0)
    and (Abs(A) >= 1e-6) and (Abs(A) < 1e21) and (Abs(B) >= 1e-6) and (Abs(B) < 1e21)
    and (IntDigits(A) = IntDigits(B)) then
  begin
    if Abs(A) < Abs(B) then Result := -1 else Result := 1;
    Exit;
  end;
  Result := CompareStr(TyJsNumberToString(A), TyJsNumberToString(B));
end;

{ Array.prototype.sort with no comparator: by String(v), stable }
procedure JsSortAsText(var A: array of Double);
var
  i, j: Integer;
  t: Double;
begin
  for i := 1 to High(A) do
  begin
    t := A[i];
    j := i - 1;
    while (j >= 0) and (CompareAsText(A[j], t) > 0) do
    begin
      A[j + 1] := A[j];
      Dec(j);
    end;
    A[j + 1] := t;
  end;
end;

{ candlestick-large's generateOHLC(2e5): a minute per row; the four box
  values sorted the way the page sorts them -- as text }
procedure GenCandlestickLarge(ARows: TGenSink);
var
  r: TJsRandom;
  xValue, baseValue, volumn, openV, closeV, prevClose: Double;
  box: array[0..3] of Double;
  i, j, openIdx, closeIdx, sign: Integer;
begin
  RandomInit(r);
  xValue := cJan2011;
  baseValue := JsRandom(r) * 12000;
  prevClose := 0;
  ARows.BeginArr;
  for i := 0 to 200000 - 1 do
  begin
    baseValue := baseValue + JsRandom(r) * 20 - 10;
    for j := 0 to 3 do box[j] := (JsRandom(r) - 0.5) * 12 + baseValue;
    JsSortAsText(box);
    openIdx := Trunc(TyJsRound(JsRandom(r) * 3));
    closeIdx := Trunc(TyJsRound(JsRandom(r) * 2));
    if closeIdx = openIdx then Inc(closeIdx);
    volumn := box[3] * (1000 + JsRandom(r) * 500);
    xValue := xValue + 60 * 1000;
    { getSign(data, i, +open, +close, 4): the unrounded values; a tie looks
      at the previous row's (rounded) close }
    openV := box[openIdx];
    closeV := box[closeIdx];
    if openV > closeV then sign := -1
    else if openV < closeV then sign := 1
    else if i > 0 then
    begin
      if prevClose <= closeV then sign := 1 else sign := -1;
    end
    else sign := 1;
    ARows.BeginArr;
    ARows.Str(Stamp(xValue));
    ARows.Num(TyJsToFixed(box[openIdx], 2));
    ARows.Num(TyJsToFixed(box[3], 2));
    ARows.Num(TyJsToFixed(box[0], 2));
    prevClose := TyJsToFixed(box[closeIdx], 2);
    ARows.Num(prevClose);
    ARows.Num(TyJsToFixed(volumn, 0));
    ARows.Num(sign);
    ARows.EndArr;
  end;
  ARows.EndArr;
end;

{ heatmap-large's noise helper (josephg/noisejs' perlin2) }
type
  TGrad = record
    X, Y: Double;
  end;

const
  cGrad3: array[0..11] of TGrad = (
    (X: 1; Y: 1), (X: -1; Y: 1), (X: 1; Y: -1), (X: -1; Y: -1),
    (X: 1; Y: 0), (X: -1; Y: 0), (X: 1; Y: 0), (X: -1; Y: 0),
    (X: 0; Y: 1), (X: 0; Y: -1), (X: 0; Y: 1), (X: 0; Y: -1));
  cP: array[0..255] of Byte = (
    151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140,
    36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120,
    234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33,
    88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71,
    134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133,
    230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161,
    1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130,
    116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250,
    124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227,
    47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44,
    154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98,
    108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34,
    242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14,
    239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121,
    50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243,
    141, 128, 195, 78, 66, 215, 61, 156, 180);

type
  TNoise = record
    Perm: array[0..511] of Integer;
    GradP: array[0..511] of TGrad;
  end;

procedure NoiseSeed(var N: TNoise; ASeed: Double);
var
  s, i, v: Integer;
begin
  if (ASeed > 0) and (ASeed < 1) then ASeed := ASeed * 65536;
  s := Floor(ASeed);
  if s < 256 then s := s or (s shl 8);
  for i := 0 to 255 do
  begin
    if (i and 1) <> 0 then v := cP[i] xor (s and 255)
    else v := cP[i] xor ((s shr 8) and 255);
    N.Perm[i] := v;
    N.Perm[i + 256] := v;
    N.GradP[i] := cGrad3[v mod 12];
    N.GradP[i + 256] := cGrad3[v mod 12];
  end;
end;

function Fade(T: Double): Double;
begin
  Result := T * T * T * (T * (T * 6 - 15) + 10);
end;

function Lerp(A, B, T: Double): Double;
begin
  Result := (1 - T) * A + T * B;
end;

function Dot2(const G: TGrad; X, Y: Double): Double;
begin
  Result := G.X * X + G.Y * Y;
end;

function Perlin2(const N: TNoise; X, Y: Double): Double;
var
  ix, iy: Integer;
  n00, n01, n10, n11, u: Double;
begin
  ix := Floor(X);
  iy := Floor(Y);
  X := X - ix;
  Y := Y - iy;
  ix := ix and 255;
  iy := iy and 255;
  n00 := Dot2(N.GradP[ix + N.Perm[iy]], X, Y);
  n01 := Dot2(N.GradP[ix + N.Perm[iy + 1]], X, Y - 1);
  n10 := Dot2(N.GradP[ix + 1 + N.Perm[iy]], X - 1, Y);
  n11 := Dot2(N.GradP[ix + 1 + N.Perm[iy + 1]], X - 1, Y - 1);
  u := Fade(X);
  Result := Lerp(Lerp(n00, n10, u), Lerp(n01, n11, u), Fade(Y));
end;

{ heatmap-large's generateData: perlin noise on a 201 x 101 grid }
procedure GenHeatmapLarge(AX, AY, AData: TGenSink);
var
  r: TJsRandom;
  noise: TNoise;
  i, j: Integer;
  x40, y20: Double;
begin
  RandomInit(r);
  { getNoiseHelper() seeds 0; then the page seeds Math.random() }
  NoiseSeed(noise, 0);
  NoiseSeed(noise, JsRandom(r));
  AX.BeginArr;
  AData.BeginArr;
  for i := 0 to 200 do
  begin
    for j := 0 to 100 do
    begin
      x40 := i;
      x40 := x40 / 40;
      y20 := j;
      y20 := y20 / 20;
      AData.BeginArr;
      AData.Num(i);
      AData.Num(j);
      AData.Num(Perlin2(noise, x40, y20) + 0.5);
      AData.EndArr;
    end;
    AX.Num(i);
  end;
  AX.EndArr;
  AData.EndArr;
  AY.BeginArr;
  for j := 0 to 99 do AY.Num(j);
  AY.EndArr;
end;

{ scatter-large's genData(len, offset): x random in [0, 10), y around sin x,
  both stored in a Float32Array }
procedure GenScatter(var R: TJsRandom; ALen: Integer; AOffset: Double; ASink: TGenSink);
var
  i: Integer;
  x, y, c: Double;
begin
  { len % 2 ? 0.1 : -0.1, each the double nearest a tenth }
  c := 1;
  c := c / 10;
  if ALen mod 2 = 0 then c := -c;
  ASink.BeginArr;
  for i := 0 to ALen - 1 do
  begin
    x := JsRandom(R) * 10;
    y := TyJsSin(x) - x * c * JsRandom(R) + AOffset / 10;
    ASink.BeginArr;
    ASink.Num(TyJsFround(x));
    ASink.Num(TyJsFround(y));
    ASink.EndArr;
  end;
  ASink.EndArr;
end;

procedure GenScatterLarge(A, B: TGenSink);
var r: TJsRandom;
begin
  RandomInit(r);
  GenScatter(r, 500000, 0, A);
  GenScatter(r, 500000, 10, B);
end;

{ ==================== custom-wind [R2-J2] ==================== }

{ a gzipped file's bytes, '' when it is not there }
function ReadGz(const AFile: string): string; forward;

function GalleryReadGz(const AFile: string): string;
begin
  Result := '';
  if not FileExists(AFile) then Exit;
  Result := ReadGz(AFile);
end;

function ReadGz(const AFile: string): string;
var
  gz: TGZFileStream;
  buf: array[0..65535] of Byte;
  n: Integer;
  ss: TStringStream;
begin
  Result := '';
  if not FileExists(AFile) then Exit;
  ss := TStringStream.Create('');
  try
    gz := TGZFileStream.Create(AFile, gzOpenRead);
    try
      repeat
        n := gz.Read(buf, SizeOf(buf));
        if n > 0 then ss.WriteBuffer(buf, n);
      until n <= 0;
    finally
      gz.Free;
    end;
    Result := ss.DataString;
  finally
    ss.Free;
  end;
end;

{ the number after `"AKey":` in AText (NaN when there is none) }
function KeyNum(const AText, AKey: string): Double;
var p, q: Integer;
begin
  Result := NaN;
  p := Pos('"' + AKey + '":', AText);
  if p <= 0 then Exit;
  p := p + Length(AKey) + 3;
  q := p;
  while (q <= Length(AText)) and (AText[q] in ['0'..'9', '-', '+', '.', 'e', 'E']) do Inc(q);
  Result := TyJsToNumber(Copy(AText, p, q - p));
end;

{ the page's loop over winds.json: for every grid point j (rows), i
  (columns), [i / nx * 360 - 180, j / ny * 180 - 90, vx, vy, |v|]; then
  its shuffle on Math.random. The numbers of the file are read as
  JavaScript reads them (TyJsToNumber), token by token. }
procedure GenCustomWind(ARows: TGenSink);
type
  TRow = array[0..4] of Double;
var
  text: string;
  nx, ny, p, i, j, k, q, n, cur, ri: Integer;
  vals: array of Double;
  rows: array of TRow;
  tmp: TRow;
  vx, vy: Double;
  r: TJsRandom;
begin
  text := ReadGz(GalleryDataDir + 'winds.json.gz');
  if text = '' then Exit;
  nx := Trunc(KeyNum(text, 'nx'));
  ny := Trunc(KeyNum(text, 'ny'));
  { every number of `data`, in order }
  p := Pos('"data":', text);
  if p <= 0 then Exit;
  SetLength(vals, nx * ny * 2);
  n := 0;
  k := p + 7;
  while (k <= Length(text)) and (n < Length(vals)) do
  begin
    if text[k] in ['0'..'9', '-', '.'] then
    begin
      q := k;
      while (q <= Length(text)) and (text[q] in ['0'..'9', '-', '+', '.', 'e', 'E']) do Inc(q);
      vals[n] := TyJsToNumber(Copy(text, k, q - k));
      Inc(n);
      k := q;
    end
    else Inc(k);
  end;
  SetLength(rows, nx * ny);
  p := 0;
  for j := 0 to ny - 1 do
    for i := 0 to nx - 1 do
    begin
      vx := vals[p * 2];
      vy := vals[p * 2 + 1];
      rows[p][0] := (i / nx) * 360 - 180;
      rows[p][1] := (j / ny) * 180 - 90;
      rows[p][2] := vx;
      rows[p][3] := vy;
      rows[p][4] := Sqrt(vx * vx + vy * vy);
      Inc(p);
    end;
  { shuffle(data): Fisher-Yates from the end, Math.floor(Math.random() *
    currentIndex) }
  RandomInit(r);
  cur := Length(rows);
  while cur <> 0 do
  begin
    ri := Floor(JsRandom(r) * cur);
    Dec(cur);
    tmp := rows[cur];
    rows[cur] := rows[ri];
    rows[ri] := tmp;
  end;
  ARows.BeginArr;
  for p := 0 to High(rows) do
  begin
    ARows.BeginArr;
    for k := 0 to 4 do ARows.Num(rows[p][k]);
    ARows.EndArr;
  end;
  ARows.EndArr;
end;

{ ==================== the table ==================== }

function GalleryIsGenerated(const AId: string): Boolean;
begin
  Result := Length(GalleryGeneratedPaths(AId)) > 0;
end;

function GalleryGeneratedPaths(const AId: string): TStringArray;
begin
  Result := nil;
  if AId = 'bar-large' then Result := ['xAxis.data', 'series.0.data']
  else if AId = 'candlestick-large' then Result := ['dataset.source']
  else if (AId = 'heatmap-large') or (AId = 'heatmap-large-piecewise') then
    Result := ['xAxis.data', 'yAxis.data', 'series.0.data']
  else if AId = 'scatter-large' then Result := ['series.0.data', 'series.1.data']
  else if AId = 'custom-wind' then Result := ['series.data'];
end;

function GalleryGenerate(const AId: string; const ASinks: array of TGenSink): Boolean;
begin
  Result := Length(ASinks) = Length(GalleryGeneratedPaths(AId));
  if not Result or (Length(ASinks) = 0) then Exit(False);
  if AId = 'bar-large' then GenBarLarge(ASinks[0], ASinks[1])
  else if AId = 'candlestick-large' then GenCandlestickLarge(ASinks[0])
  else if (AId = 'heatmap-large') or (AId = 'heatmap-large-piecewise') then
    GenHeatmapLarge(ASinks[0], ASinks[1], ASinks[2])
  else if AId = 'scatter-large' then GenScatterLarge(ASinks[0], ASinks[1])
  else if AId = 'custom-wind' then GenCustomWind(ASinks[0])
  else Result := False;
end;

{ Where, in the JSON text AText, the value at each dotted path of APaths
  starts and ends (1-based, inclusive; 0 where the path is not there).
  A scan of the text, not a parse: the skeleton stays byte for byte as the
  harvest wrote it, every number in it the token upstream read. }
procedure FindValues(const AText: string; const APaths: TStringArray;
  var AStart, AStop: array of Integer);
type
  TFrame = record
    IsArray: Boolean;
    Key: string;
    Index: Integer;
  end;
var
  stack: array of TFrame;
  i, n, k: Integer;
  c: Char;
  pendingKey: string;
  expectKey: Boolean;

  function PathHere: string;
  var j: Integer;
  begin
    Result := '';
    for j := 0 to High(stack) do
    begin
      if j > 0 then Result := Result + '.';
      if stack[j].IsArray then Result := Result + IntToStr(stack[j].Index)
      else Result := Result + stack[j].Key;
    end;
  end;

  function ReadString: string;
  begin
    Result := '';
    Inc(i);
    while (i <= n) and (AText[i] <> '"') do
    begin
      if AText[i] = '\' then
      begin
        Result := Result + AText[i];
        Inc(i);
      end;
      if i <= n then Result := Result + AText[i];
      Inc(i);
    end;
  end;

  { the end of the value starting at AAt }
  function ValueEnd(AAt: Integer): Integer;
  var d: Integer; inStr: Boolean;
  begin
    Result := AAt;
    if not (AText[AAt] in ['[', '{']) then Exit;
    d := 0;
    inStr := False;
    Result := AAt;
    while Result <= n do
    begin
      if inStr then
      begin
        if AText[Result] = '\' then Inc(Result)
        else if AText[Result] = '"' then inStr := False;
      end
      else
        case AText[Result] of
          '"': inStr := True;
          '[', '{': Inc(d);
          ']', '}':
            begin
              Dec(d);
              if d = 0 then Exit;
            end;
        end;
      Inc(Result);
    end;
  end;

  procedure AtValue;
  var p: string; j: Integer;
  begin
    p := PathHere;
    for j := 0 to High(APaths) do
      if (APaths[j] = p) and (AStart[j] = 0) then
      begin
        AStart[j] := i;
        AStop[j] := ValueEnd(i);
      end;
  end;

begin
  for k := 0 to High(AStart) do
  begin
    AStart[k] := 0;
    AStop[k] := 0;
  end;
  n := Length(AText);
  stack := nil;
  expectKey := False;
  pendingKey := '';
  i := 1;
  while i <= n do
  begin
    c := AText[i];
    case c of
      ' ', #9, #10, #13, ':': ;
      ',':
        if (Length(stack) > 0) then
        begin
          if stack[High(stack)].IsArray then Inc(stack[High(stack)].Index)
          else expectKey := True;
        end;
      '{', '[':
        begin
          if Length(stack) > 0 then AtValue;
          SetLength(stack, Length(stack) + 1);
          stack[High(stack)].IsArray := c = '[';
          stack[High(stack)].Index := 0;
          stack[High(stack)].Key := '';
          expectKey := c = '{';
        end;
      '}', ']':
        begin
          SetLength(stack, Length(stack) - 1);
          expectKey := False;
        end;
      '"':
        if expectKey then
        begin
          pendingKey := ReadString;
          stack[High(stack)].Key := pendingKey;
          expectKey := False;
        end
        else
        begin
          if Length(stack) > 0 then AtValue;
          ReadString;
        end;
    else
      { a number, true, false, null }
      if Length(stack) > 0 then AtValue;
      while (i < n) and not (AText[i + 1] in [',', ']', '}', ' ', #9, #10, #13]) do Inc(i);
    end;
    Inc(i);
  end;
end;

function GalleryFillGenerated(const AId, ASkeleton: string; out AText: string): Boolean;
var
  paths: TStringArray;
  starts, stops: array of Integer;
  sinks: array of TGenSink;
  i, j, k: Integer;
  order: array of Integer;
begin
  AText := ASkeleton;
  Result := False;
  paths := GalleryGeneratedPaths(AId);
  if Length(paths) = 0 then Exit;
  SetLength(starts, Length(paths));
  SetLength(stops, Length(paths));
  FindValues(ASkeleton, paths, starts, stops);
  for i := 0 to High(paths) do
    if (starts[i] = 0) or (ASkeleton[starts[i]] <> '[') then Exit;
  sinks := nil;
  SetLength(sinks, Length(paths));
  for i := 0 to High(sinks) do sinks[i] := TTextSink.Create;
  try
    if not GalleryGenerate(AId, sinks) then Exit;
    { spliced from the last place in the text to the first, so the places
      before stay where they were found }
    SetLength(order, Length(paths));
    for i := 0 to High(order) do order[i] := i;
    for i := 0 to High(order) do
      for j := i + 1 to High(order) do
        if starts[order[j]] > starts[order[i]] then
        begin
          k := order[i];
          order[i] := order[j];
          order[j] := k;
        end;
    for i := 0 to High(order) do
      AText := Copy(AText, 1, starts[order[i]] - 1) + TTextSink(sinks[order[i]]).Text
        + Copy(AText, stops[order[i]] + 1, MaxInt);
    Result := True;
  finally
    for i := 0 to High(sinks) do sinks[i].Free;
  end;
end;

function GalleryGeneratedHash(const AId: string; out AHashes: TStringArray;
  out ACounts: array of Integer): Boolean;
var
  paths: TStringArray;
  sinks: array of TGenSink;
  i: Integer;
begin
  AHashes := nil;
  paths := GalleryGeneratedPaths(AId);
  Result := (Length(paths) > 0) and (Length(ACounts) >= Length(paths));
  if not Result then Exit;
  SetLength(sinks, Length(paths));
  for i := 0 to High(sinks) do sinks[i] := THashSink.Create;
  try
    Result := GalleryGenerate(AId, sinks);
    SetLength(AHashes, Length(paths));
    for i := 0 to High(paths) do
    begin
      AHashes[i] := THashSink(sinks[i]).HashText;
      ACounts[i] := THashSink(sinks[i]).Count;
    end;
  finally
    for i := 0 to High(sinks) do sinks[i].Free;
  end;
end;

end.
