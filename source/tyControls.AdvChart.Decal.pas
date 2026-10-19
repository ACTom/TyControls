unit tyControls.AdvChart.Decal;
{$mode objfpc}{$H+}
{ DECALS [Batch 131]: the patterns ECharts GENERATES from a decal object and
  lays over a filled shape -- what `aria.decal.show` hands every series so a
  chart can be read without its colours, and what any itemStyle.decal asks
  for.

  A PORT OF src/util/decal.ts (createOrUpdatePatternFromDecal: the defaults,
  normalizeDashArrayX / Y, normalizeSymbolArray, getLineBlockLengthX / Y,
  getPatternSize's least common multiple and brushDecal's loop) and of the
  decal half of model/mixin/palette.ts (getDecalFromPalette over
  globalDefault's six decals), read off the ECharts 6.1 source and held to
  the dist by tools/advchart-oracle/decal-aria.js.

  THE TILE IS GEOMETRY HERE, NOT PIXELS. TyDecalTile answers the tile's size
  and every symbol's box in CSS px, exactly as brushDecal hands them to
  createSymbol; the renderer draws them into a bitmap at the device's scale
  and repeats it (AdvChart.Render). Upstream does the same in that order:
  its canvas is the tile's size times the pixel ratio and the pattern is
  scaled back by its inverse.

  A DECAL OBJECT IS MERGED BEFORE IT IS NORMALISED. The aria palette's decal
  goes UNDER the author's (extend of a fresh object with the palette's,
  then the author's, key by key)
  and only then are the defaults filled in -- so TTyDecalRaw keeps each
  key's node as written, and TyDecalResolve is the one place that reads them.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface

uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Paint;

type
  { decalKeys, and the rotation }
  TTyDecalKey = (dkSymbol, dkSymbolSize, dkKeepAspect, dkColor, dkBackground,
    dkDashX, dkDashY, dkRotation, dkMaxTileW, dkMaxTileH);

  { A DECAL OBJECT AS WRITTEN: each key's node, nil where the object has no
    such key (a key written as null is a TJSONNull -- `extend` copies it, and
    the defaults then fill it). The nodes are not owned. Present is False
    for no decal at all. }
  TTyDecalRaw = record
    Present: Boolean;
    Keys: array[TTyDecalKey] of TJSONData;
  end;

  { One symbol of a tile, as brushSymbol hands it to createSymbol: its name
    and its box, CSS px in the tile. }
  TTyDecalSymbol = record
    Kind: string;
    X, Y, W, H: Double;
  end;
  TTyDecalSymbolArray = array of TTyDecalSymbol;

  { getPatternSize and brushDecal's answer: the tile's size (CSS px; a NaN
    or a 0 when the dashes make no tile) and its symbols in brush order. }
  TTyDecalTile = record
    W, H: Double;
    Symbols: TTyDecalSymbolArray;
  end;

  { getFromPalette's scope: the cursor and the names memo (the index each
    name was given, -1 for an undefined pick). }
  TTyDecalScope = record
    Idx: Integer;
    Names: TTyStringArray;
    Picks: TTyIntegerArray;
  end;

const
  TyDecalKeyNames: array[TTyDecalKey] of string = ('symbol', 'symbolSize',
    'symbolKeepAspect', 'color', 'backgroundColor', 'dashArrayX', 'dashArrayY',
    'rotation', 'maxTileWidth', 'maxTileHeight');
  { the skin key of a decal's colour where none was written: upstream's
    rgba(0, 0, 0, 0.2), for globalDefault's six and for the default alike }
  TyDecalSkin = 'TyAdvChartDecal';
  { brushDecal has no limit; a tile past this many symbols is cut short
    rather than holding the paint for minutes }
  TyDecalMaxSymbols = 1000000;

{ A decal as written: an OBJECT is one (an array too -- `[]` is an object to
  upstream, whose keys are none of these); anything else is none. AString
  says the value was a string, a number or a boolean -- what
  seriesStyleTask throws on (`decal.dirty = true` on a primitive), which the
  port takes as no decal. }
function TyDecalRawOf(AData: TJSONData): TTyDecalRaw;
function TyDecalIsPrimitive(AData: TJSONData): Boolean;

{ mergeDecal: the specified decal's keys over the palette's. With nothing
  specified, the palette's; with no palette decal, the specified one. }
function TyDecalMerge(const APalette, ASpecified: TTyDecalRaw): TTyDecalRaw;

{ createOrUpdatePatternFromDecal's defaults and normalisation. ASkin is the
  colour of a decal that wrote none; AEmptyFill the ground of its `empty*`
  symbols (upstream's neutral00, #fff, where none is given) [R2-F]. }
function TyDecalResolve(const ARaw: TTyDecalRaw; ASkin: TTyChartColor): TTyChartDecal; overload;
function TyDecalResolve(const ARaw: TTyDecalRaw; ASkin, AEmptyFill: TTyChartColor): TTyChartDecal; overload;

{ getPatternSize and brushDecal, verbatim. }
function TyDecalTile(const ADecal: TTyChartDecal): TTyDecalTile;

{ A string that names the tile a decal draws at AScale device px per CSS
  px: equal strings, equal bitmaps. }
function TyDecalCacheKey(const ADecal: TTyChartDecal; AScale: Double): string;

{ The default palette: aria.decal.decals as written (normalizeToArray: a
  list, one object, or none for null), else globalDefault's six. The nodes
  of the built-in six are this unit's. }
function TyDecalPaletteOf(AAria: TJSONData): TJSONData;
function TyDecalPaletteCount(APalette: TJSONData): Integer;
function TyDecalPaletteItem(APalette: TJSONData; AIndex: Integer): TJSONData;

{ getFromPalette with no layers: the index of the pick, -1 for undefined (an
  empty palette, which is not memoised, or a memo of one). }
function TyDecalFromPalette(var AScope: TTyDecalScope; ACount: Integer;
  const AName: string): Integer;

{ globalDefault's six, as option nodes (colour left out: the skin's) }
function TyDecalBuiltins: TJSONArray;

{ JavaScript's truthiness of a JSON value; nil is undefined }
function TyDecalTruthy(AData: TJSONData): Boolean;

implementation

uses tyControls.AdvChart.Color, tyControls.AdvChart.Convert,
  tyControls.AdvChart.JsMath;

var
  GBuiltins: TJSONArray = nil;

function TyDecalTruthy(AData: TJSONData): Boolean;
begin
  if AData = nil then Exit(False);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (not IsNan(AData.AsFloat)) and (AData.AsFloat <> 0);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

function TyDecalIsPrimitive(AData: TJSONData): Boolean;
begin
  Result := (AData <> nil) and TyDecalTruthy(AData)
    and (AData.JSONType in [jtString, jtNumber, jtBoolean]);
end;

function TyDecalRawOf(AData: TJSONData): TTyDecalRaw;
var k: TTyDecalKey;
begin
  Result := Default(TTyDecalRaw);
  if not (AData is TJSONObject) then
  begin
    { an array is an object with none of the keys }
    Result.Present := AData is TJSONArray;
    Exit;
  end;
  Result.Present := True;
  for k := Low(TTyDecalKey) to High(TTyDecalKey) do
    Result.Keys[k] := TJSONObject(AData).Find(TyDecalKeyNames[k]);
end;

function TyDecalMerge(const APalette, ASpecified: TTyDecalRaw): TTyDecalRaw;
var k: TTyDecalKey;
begin
  if not ASpecified.Present then Exit(APalette);
  if not APalette.Present then Exit(ASpecified);
  Result := APalette;
  for k := Low(TTyDecalKey) to High(TTyDecalKey) do
    if ASpecified.Keys[k] <> nil then Result.Keys[k] := ASpecified.Keys[k];
end;

{ ---- the normalisation ---- }

{ Math.ceil, NaN and the infinities through, -0 kept }
function JsCeil(A: Double): Double;
begin
  if IsNan(A) or IsInfinite(A) then Exit(A);
  Result := Int(A);
  if Result < A then Result := Result + 1
  else if (Result = 0) and (A < 0) then Result := -0.0;
end;

{ a key that defaults fills: absent or null }
function Nullish(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function NumOr(AData: TJSONData; ADefault: Double): Double;
begin
  if Nullish(AData) then Exit(ADefault);
  Result := TyJsonToNumber(AData);
end;

{ a value Math.ceil is handed, made a number as JavaScript makes it }
function CeilOf(AData: TJSONData): Double;
begin
  Result := JsCeil(TyJsonToNumber(AData));
end;

function AllNumbers(A: TJSONArray): Boolean;
var i: Integer;
begin
  for i := 0 to A.Count - 1 do
    if A.Items[i].JSONType <> jtNumber then Exit(False);
  Result := True;
end;

function Pair(A: Double): TTyDoubleArray;
begin
  SetLength(Result, 2);
  Result[0] := A;
  Result[1] := A;
end;

{ map(line, ceil), an odd length doubled }
function CeilLine(A: TJSONArray; ADouble: Boolean): TTyDoubleArray;
var i, n: Integer;
begin
  n := A.Count;
  if ADouble and Odd(n) then SetLength(Result, n * 2) else SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := CeilOf(A.Items[i]);
  if ADouble and Odd(n) then
    for i := 0 to n - 1 do Result[n + i] := Result[i];
end;

{ normalizeDashArrayX }
procedure NormaliseX(AData: TJSONData; var ADecal: TTyChartDecal);
var
  a: TJSONArray;
  i: Integer;
begin
  ADecal.DashX := nil;
  if (not TyDecalTruthy(AData)) or ((AData is TJSONArray) and (AData.Count = 0)) then
  begin
    SetLength(ADecal.DashX, 1);
    ADecal.DashX[0] := Pair(0);
    Exit;
  end;
  if AData.JSONType = jtNumber then
  begin
    SetLength(ADecal.DashX, 1);
    ADecal.DashX[0] := Pair(JsCeil(AData.AsFloat));
    Exit;
  end;
  if not (AData is TJSONArray) then
  begin
    { a string or an object: none of upstream's three shapes }
    SetLength(ADecal.DashX, 1);
    ADecal.DashX[0] := Pair(0);
    Exit;
  end;
  a := TJSONArray(AData);
  { [20, 5] is [[20, 5]] }
  if AllNumbers(a) then
  begin
    SetLength(ADecal.DashX, 1);
    ADecal.DashX[0] := CeilLine(a, True);
    Exit;
  end;
  SetLength(ADecal.DashX, a.Count);
  for i := 0 to a.Count - 1 do
    if a.Items[i].JSONType = jtNumber then
      ADecal.DashX[i] := Pair(JsCeil(a.Items[i].AsFloat))
    else if a.Items[i] is TJSONArray then
      ADecal.DashX[i] := CeilLine(TJSONArray(a.Items[i]), True)
    else
      ADecal.DashX[i] := nil;
end;

{ normalizeDashArrayY }
procedure NormaliseY(AData: TJSONData; var ADecal: TTyChartDecal);
begin
  ADecal.DashY := nil;
  if (not TyDecalTruthy(AData)) or ((AData is TJSONArray) and (AData.Count = 0))
    or not ((AData is TJSONArray) or (AData.JSONType = jtNumber)) then
  begin
    ADecal.DashY := Pair(0);
    Exit;
  end;
  if AData.JSONType = jtNumber then
  begin
    ADecal.DashY := Pair(JsCeil(AData.AsFloat));
    Exit;
  end;
  ADecal.DashY := CeilLine(TJSONArray(AData), True);
end;

function SymbolName(AData: TJSONData): string;
begin
  if AData.JSONType = jtString then Result := AData.AsString
  else Result := '';
end;

{ normalizeSymbolArray }
procedure NormaliseSymbols(AData: TJSONData; var ADecal: TTyChartDecal);
var
  a, inner: TJSONArray;
  i, j: Integer;
  allStr: Boolean;
begin
  ADecal.Symbols := nil;
  if (not TyDecalTruthy(AData)) or ((AData is TJSONArray) and (AData.Count = 0))
    or not ((AData is TJSONArray) or (AData.JSONType = jtString)) then
  begin
    SetLength(ADecal.Symbols, 1);
    SetLength(ADecal.Symbols[0], 1);
    ADecal.Symbols[0][0] := 'rect';
    Exit;
  end;
  if AData.JSONType = jtString then
  begin
    SetLength(ADecal.Symbols, 1);
    SetLength(ADecal.Symbols[0], 1);
    ADecal.Symbols[0][0] := AData.AsString;
    Exit;
  end;
  a := TJSONArray(AData);
  allStr := True;
  for i := 0 to a.Count - 1 do
    if a.Items[i].JSONType <> jtString then allStr := False;
  if allStr then
  begin
    SetLength(ADecal.Symbols, 1);
    SetLength(ADecal.Symbols[0], a.Count);
    for i := 0 to a.Count - 1 do ADecal.Symbols[0][i] := a.Items[i].AsString;
    Exit;
  end;
  SetLength(ADecal.Symbols, a.Count);
  for i := 0 to a.Count - 1 do
    if a.Items[i] is TJSONArray then
    begin
      inner := TJSONArray(a.Items[i]);
      SetLength(ADecal.Symbols[i], inner.Count);
      for j := 0 to inner.Count - 1 do ADecal.Symbols[i][j] := SymbolName(inner.Items[j]);
    end
    else
    begin
      SetLength(ADecal.Symbols[i], 1);
      ADecal.Symbols[i][0] := SymbolName(a.Items[i]);
    end;
end;

{ A COLOUR THE CANVAS CANNOT READ leaves its fillStyle as it was: a fresh
  context's #000000. So does a colour that is no string. }
function ColourOf(AData: TJSONData): TTyChartColor;
begin
  Result := TTyChartColor($FF000000);
  if (AData <> nil) and (AData.JSONType = jtString) then
    if not TyTryParseChartColor(AData.AsString, Result) then
      Result := TTyChartColor($FF000000);
end;

function TyDecalResolve(const ARaw: TTyDecalRaw; ASkin: TTyChartColor): TTyChartDecal;
begin
  Result := TyDecalResolve(ARaw, ASkin, TTyChartColor($FFFFFFFF));
end;

function TyDecalResolve(const ARaw: TTyDecalRaw; ASkin, AEmptyFill: TTyChartColor): TTyChartDecal;
var d: TJSONData;
begin
  Result := Default(TTyChartDecal);
  if not ARaw.Present then Exit;
  Result.Present := True;
  Result.EmptyFill := AEmptyFill;
  { defaults(decalObject, the defaults): a key that is absent or null takes the
    default; anything else stays as written }
  d := ARaw.Keys[dkSymbol];
  if Nullish(d) then
  begin
    SetLength(Result.Symbols, 1);
    SetLength(Result.Symbols[0], 1);
    Result.Symbols[0][0] := 'rect';
  end
  else
    NormaliseSymbols(d, Result);
  Result.SymbolSize := NumOr(ARaw.Keys[dkSymbolSize], 1);
  d := ARaw.Keys[dkKeepAspect];
  Result.KeepAspect := Nullish(d) or TyDecalTruthy(d);
  { the colour: the skin's where none was written; a written one that is
    falsy sets no fill on the symbol, which zrender's Path then fills black }
  d := ARaw.Keys[dkColor];
  if Nullish(d) then Result.Color := ASkin
  else if not TyDecalTruthy(d) then Result.Color := TTyChartColor($FF000000)
  else Result.Color := ColourOf(d);
  { the background: 'none' is null; a falsy one is none }
  d := ARaw.Keys[dkBackground];
  Result.HasBackground := (not Nullish(d)) and TyDecalTruthy(d)
    and not ((d.JSONType = jtString) and (d.AsString = 'none'));
  if Result.HasBackground then Result.Background := ColourOf(d);
  d := ARaw.Keys[dkDashX];
  if Nullish(d) then
  begin
    SetLength(Result.DashX, 1);
    Result.DashX[0] := Pair(5);
  end
  else
    NormaliseX(d, Result);
  d := ARaw.Keys[dkDashY];
  if Nullish(d) then Result.DashY := Pair(5)
  else NormaliseY(d, Result);
  Result.Rotation := NumOr(ARaw.Keys[dkRotation], 0);
  Result.MaxTileW := NumOr(ARaw.Keys[dkMaxTileW], 512);
  Result.MaxTileH := NumOr(ARaw.Keys[dkMaxTileH], 512);
end;

{ ---- the tile ---- }

{ getLineBlockLengthY }
function BlockLength(const A: TTyDoubleArray): Double;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(A) do Result := Result + A[i];
  if Odd(Length(A)) then Result := Result * 2;
end;

{ getGreatestCommonDividor, recursion unrolled; JavaScript's own recursion
  never ends on a NaN (it throws a RangeError) -- this gives up with NaN }
function Gcd(A, B: Double): Double;
var t: Double; n: Integer;
begin
  n := 0;
  while not ((B = 0) and not IsNan(B)) do
  begin
    Inc(n);
    if (n > 100000) or IsNan(B) then Exit(NaN);
    t := TyJsFMod(A, B);
    A := B;
    B := t;
  end;
  Result := A;
end;

function Lcm(A, B: Double): Double;
begin
  Result := A * B / Gcd(A, B);
end;

{ Math.min / Math.max: NaN wins }
function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if B < A then Result := B else Result := A;
end;

function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if B > A then Result := B else Result := A;
end;

{ `a < b` as JavaScript answers it: false where either is NaN }
function Less(A, B: Double): Boolean;
begin
  Result := (not IsNan(A)) and (not IsNan(B)) and (A < B);
end;

{ `a <= 0`, false for NaN }
function AtMostZero(A: Double): Boolean;
begin
  Result := (not IsNan(A)) and (A <= 0);
end;

function TyDecalTile(const ADecal: TTyChartDecal): TTyDecalTile;
var
  blocksX: TTyDoubleArray;
  blockY, width, height, repeats, ySum, xSum, y, x, size: Double;
  i, yId, yIdTotal, xId0, xId1, xId1Total, symY, symX, n: Integer;
  row: TTyStringArray;
begin
  Result := Default(TTyDecalTile);
  if (Length(ADecal.DashX) = 0) or (Length(ADecal.DashY) = 0)
    or (Length(ADecal.Symbols) = 0) then Exit;
  SetLength(blocksX, Length(ADecal.DashX));
  for i := 0 to High(ADecal.DashX) do blocksX[i] := BlockLength(ADecal.DashX[i]);
  blockY := BlockLength(ADecal.DashY);
  { getPatternSize: the x blocks' least common multiple, times the symbols'
    own; the y block times the lines times the symbol rows }
  width := 1;
  for i := 0 to High(blocksX) do width := Lcm(width, blocksX[i]);
  repeats := 1;
  for i := 0 to High(ADecal.Symbols) do
    repeats := Lcm(repeats, Length(ADecal.Symbols[i]));
  width := width * repeats;
  height := blockY * Length(blocksX) * Length(ADecal.Symbols);
  Result.W := JsMax(1, JsMin(width, ADecal.MaxTileW));
  Result.H := JsMax(1, JsMin(height, ADecal.MaxTileH));

  { brushDecal }
  ySum := 0;
  for i := 0 to High(ADecal.DashY) do ySum := ySum + ADecal.DashY[i];
  if AtMostZero(ySum) then Exit;
  n := 0;
  y := -blockY;
  yId := 0;
  yIdTotal := 0;
  xId0 := 0;
  while Less(y, Result.H) do
  begin
    if not Odd(yId) then
    begin
      symY := (yIdTotal div 2) mod Length(ADecal.Symbols);
      row := ADecal.Symbols[symY];
      x := 0;
      xId1 := 0;
      xId1Total := 0;
      while Less(x, Result.W * 2) do
      begin
        xSum := 0;
        for i := 0 to High(ADecal.DashX[xId0]) do xSum := xSum + ADecal.DashX[xId0][i];
        { an empty line: skip it }
        if AtMostZero(xSum) or (Length(ADecal.DashX[xId0]) = 0) then Break;
        { [15, 5, 20, 5] draws for the 15 and the 20 only }
        if not Odd(xId1) then
        begin
          if n >= TyDecalMaxSymbols then Exit;
          if Length(Result.Symbols) <= n then
            SetLength(Result.Symbols, Max(16, n * 2));
          size := (1 - ADecal.SymbolSize) * 0.5;
          Result.Symbols[n].X := x + ADecal.DashX[xId0][xId1] * size;
          Result.Symbols[n].Y := y + ADecal.DashY[yId] * size;
          Result.Symbols[n].W := ADecal.DashX[xId0][xId1] * ADecal.SymbolSize;
          Result.Symbols[n].H := ADecal.DashY[yId] * ADecal.SymbolSize;
          if Length(row) > 0 then
          begin
            symX := (xId1Total div 2) mod Length(row);
            Result.Symbols[n].Kind := row[symX];
          end
          else
            Result.Symbols[n].Kind := '';
          Inc(n);
        end;
        x := x + ADecal.DashX[xId0][xId1];
        Inc(xId1Total);
        Inc(xId1);
        if xId1 = Length(ADecal.DashX[xId0]) then xId1 := 0;
      end;
      Inc(xId0);
      if xId0 = Length(ADecal.DashX) then xId0 := 0;
    end;
    y := y + ADecal.DashY[yId];
    Inc(yIdTotal);
    Inc(yId);
    if yId = Length(ADecal.DashY) then yId := 0;
  end;
  SetLength(Result.Symbols, n);
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := IntToHex(q, 16);
end;

function TyDecalCacheKey(const ADecal: TTyChartDecal; AScale: Double): string;
var i, j: Integer;
begin
  Result := HexOf(AScale) + '|' + HexOf(ADecal.SymbolSize) + '|'
    + IntToHex(ADecal.Color, 8) + '|';
  if ADecal.HasBackground then Result := Result + IntToHex(ADecal.Background, 8);
  Result := Result + '|' + HexOf(ADecal.MaxTileW) + HexOf(ADecal.MaxTileH) + '|'
    + IntToHex(ADecal.EmptyFill, 8) + '|';
  for i := 0 to High(ADecal.Symbols) do
  begin
    for j := 0 to High(ADecal.Symbols[i]) do
      Result := Result + ADecal.Symbols[i][j] + ',';
    Result := Result + ';';
  end;
  Result := Result + '|';
  for i := 0 to High(ADecal.DashX) do
  begin
    for j := 0 to High(ADecal.DashX[i]) do
      Result := Result + HexOf(ADecal.DashX[i][j]);
    Result := Result + ';';
  end;
  Result := Result + '|';
  for i := 0 to High(ADecal.DashY) do Result := Result + HexOf(ADecal.DashY[i]);
end;

{ ---- the palette ---- }

function TyDecalBuiltins: TJSONArray;
var o: TJSONObject;

  function Arr(const A: array of Double): TJSONArray;
  var i: Integer;
  begin
    Result := TJSONArray.Create;
    for i := 0 to High(A) do Result.Add(A[i]);
  end;

  function Arr2(const A, B: array of Double): TJSONArray;
  begin
    Result := TJSONArray.Create;
    Result.Add(Arr(A));
    Result.Add(Arr(B));
  end;

const
  { Math.PI, a double whatever the platform's extended is }
  cPi: Double = 3.141592653589793;
begin
  if GBuiltins <> nil then Exit(GBuiltins);
  { globalDefault.aria.decal.decals, colour left to the skin }
  GBuiltins := TJSONArray.Create;
  o := TJSONObject.Create;
  o.Add('dashArrayX', Arr([1, 0]));
  o.Add('dashArrayY', Arr([2, 5]));
  o.Add('symbolSize', 1);
  o.Add('rotation', TJSONFloatNumber.Create(cPi / 6));
  GBuiltins.Add(o);
  o := TJSONObject.Create;
  o.Add('symbol', 'circle');
  o.Add('dashArrayX', Arr2([8, 8], [0, 8, 8, 0]));
  o.Add('dashArrayY', Arr([6, 0]));
  o.Add('symbolSize', TJSONFloatNumber.Create(0.8));
  GBuiltins.Add(o);
  o := TJSONObject.Create;
  o.Add('dashArrayX', Arr([1, 0]));
  o.Add('dashArrayY', Arr([4, 3]));
  o.Add('rotation', TJSONFloatNumber.Create(-cPi / 4));
  GBuiltins.Add(o);
  o := TJSONObject.Create;
  o.Add('dashArrayX', Arr2([6, 6], [0, 6, 6, 0]));
  o.Add('dashArrayY', Arr([6, 0]));
  GBuiltins.Add(o);
  o := TJSONObject.Create;
  o.Add('dashArrayX', Arr2([1, 0], [1, 6]));
  o.Add('dashArrayY', Arr([1, 0, 6, 0]));
  o.Add('rotation', TJSONFloatNumber.Create(cPi / 4));
  GBuiltins.Add(o);
  o := TJSONObject.Create;
  o.Add('symbol', 'triangle');
  o.Add('dashArrayX', Arr2([9, 9], [0, 9, 9, 0]));
  o.Add('dashArrayY', Arr([7, 2]));
  o.Add('symbolSize', TJSONFloatNumber.Create(0.75));
  GBuiltins.Add(o);
  Result := GBuiltins;
end;

function TyDecalPaletteOf(AAria: TJSONData): TJSONData;
var d: TJSONData;
begin
  if AAria is TJSONObject then
  begin
    d := TJSONObject(AAria).Find('decal');
    if d is TJSONObject then
    begin
      { THE AUTHOR'S, whole: merging globalDefault in keeps a written key, so
        a list replaces the six and one object is a list of one }
      d := TJSONObject(d).Find('decals');
      if d <> nil then Exit(d);
    end;
  end;
  Result := TyDecalBuiltins;
end;

function TyDecalPaletteCount(APalette: TJSONData): Integer;
begin
  if APalette = nil then Exit(0);
  if APalette is TJSONArray then Exit(APalette.Count);
  { normalizeToArray: null is [], anything else a list of one }
  if APalette.JSONType = jtNull then Result := 0 else Result := 1;
end;

function TyDecalPaletteItem(APalette: TJSONData; AIndex: Integer): TJSONData;
begin
  Result := nil;
  if (APalette = nil) or (AIndex < 0) then Exit;
  if APalette is TJSONArray then
  begin
    if AIndex < APalette.Count then Result := TJSONArray(APalette).Items[AIndex];
  end
  else if (AIndex = 0) and (APalette.JSONType <> jtNull) then
    Result := APalette;
end;

function TyDecalFromPalette(var AScope: TTyDecalScope; ACount: Integer;
  const AName: string): Integer;
var i, k: Integer;
begin
  { the memo first: hasOwnProperty, an undefined pick included }
  for i := 0 to High(AScope.Names) do
    if AScope.Names[i] = AName then Exit(AScope.Picks[i]);
  if ACount <= 0 then Exit(-1);
  { palette[paletteIdx] -- no modulo: a cursor a longer palette left behind
    reads past this one's end }
  if AScope.Idx < ACount then Result := AScope.Idx else Result := -1;
  if AName <> '' then
  begin
    k := Length(AScope.Names);
    SetLength(AScope.Names, k + 1);
    SetLength(AScope.Picks, k + 1);
    AScope.Names[k] := AName;
    AScope.Picks[k] := Result;
  end;
  AScope.Idx := (AScope.Idx + 1) mod ACount;
end;

finalization
  FreeAndNil(GBuiltins);

end.
