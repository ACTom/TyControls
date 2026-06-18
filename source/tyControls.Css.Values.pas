unit tyControls.Css.Values;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tyControls.Types;

function TyParseColor(const S: string): TTyColor;        // #rgb #rrggbb #rrggbbaa
function TyLighten(c: TTyColor; Pct: Single): TTyColor;  // Pct 0..100
function TyDarken(c: TTyColor; Pct: Single): TTyColor;   // Pct 0..100
function TyAlpha(c: TTyColor; A: Single): TTyColor;       // A 0..1
function TyMix(c1, c2: TTyColor; Pct: Single): TTyColor;  // Pct 0..100 of c2

function TyEvalColor(const Expr: string; Vars: TStrings): TTyColor;  // resolves var()/funcs
function TyEvalLength(const Expr: string; Vars: TStrings): Integer;  // '6px'->6, var() ok
function TyEvalFloat(const Expr: string; Vars: TStrings): Single;    // '0.5'
// Exported so tyControls.StyleModel can split gradient/function arg lists with
// nested parens (e.g. 'lighten(--accent, 16%)') without mis-splitting commas.
procedure SplitArgs(const ArgStr: string; Args: TStrings);

implementation

// Clamp a real channel value into the 0..255 Byte range.
function ClampByte(V: Single): Byte;
var I: Integer;
begin
  I := Round(V);
  if I < 0 then I := 0;
  if I > 255 then I := 255;
  Result := Byte(I);
end;

// Parse one hex digit; raises ETyCssError-equivalent by returning via Valid flag.
function HexDigit(Ch: Char; out OK: Boolean): Integer;
begin
  OK := True;
  case Ch of
    '0'..'9': Result := Ord(Ch) - Ord('0');
    'a'..'f': Result := Ord(Ch) - Ord('a') + 10;
    'A'..'F': Result := Ord(Ch) - Ord('A') + 10;
  else
    Result := 0; OK := False;
  end;
end;

function HexByte(Hi, Lo: Char; out OK: Boolean): Integer;
var ho, lo2: Boolean;
begin
  Result := HexDigit(Hi, ho) * 16 + HexDigit(Lo, lo2);
  OK := ho and lo2;
end;

function TyParseColor(const S: string): TTyColor;
var
  T: string;
  R, G, B, A, n: Integer;
  ok1, ok2, ok3, ok4: Boolean;
begin
  T := Trim(S);
  if (T = '') or (T[1] <> '#') then
    raise Exception.CreateFmt('Invalid color literal: %s', [S]);
  T := Copy(T, 2, Length(T) - 1);
  n := Length(T);
  ok4 := True;
  A := 255;
  case n of
    3:
      begin
        // #rgb -> each digit doubled
        R := HexDigit(T[1], ok1) * 17;
        G := HexDigit(T[2], ok2) * 17;
        B := HexDigit(T[3], ok3) * 17;
      end;
    6:
      begin
        R := HexByte(T[1], T[2], ok1);
        G := HexByte(T[3], T[4], ok2);
        B := HexByte(T[5], T[6], ok3);
      end;
    8:
      begin
        R := HexByte(T[1], T[2], ok1);
        G := HexByte(T[3], T[4], ok2);
        B := HexByte(T[5], T[6], ok3);
        A := HexByte(T[7], T[8], ok4);
      end;
  else
    raise Exception.CreateFmt('Invalid color length: %s', [S]);
  end;
  if not (ok1 and ok2 and ok3 and ok4) then
    raise Exception.CreateFmt('Invalid hex in color: %s', [S]);
  Result := TyRGBA(Byte(R), Byte(G), Byte(B), Byte(A));
end;

function TyLighten(c: TTyColor; Pct: Single): TTyColor;
var f: Single;
begin
  // each channel = ch + (255 - ch) * (Pct/100); alpha preserved
  f := Pct / 100;
  Result := TyRGBA(
    ClampByte(TyRedOf(c)   + (255 - TyRedOf(c))   * f),
    ClampByte(TyGreenOf(c) + (255 - TyGreenOf(c)) * f),
    ClampByte(TyBlueOf(c)  + (255 - TyBlueOf(c))  * f),
    TyAlphaOf(c));
end;

function TyDarken(c: TTyColor; Pct: Single): TTyColor;
var f: Single;
begin
  // each channel = ch * (1 - Pct/100); alpha preserved
  f := 1 - (Pct / 100);
  Result := TyRGBA(
    ClampByte(TyRedOf(c)   * f),
    ClampByte(TyGreenOf(c) * f),
    ClampByte(TyBlueOf(c)  * f),
    TyAlphaOf(c));
end;

function TyAlpha(c: TTyColor; A: Single): TTyColor;
begin
  // replace alpha with A (0..1 -> 0..255); rgb preserved
  Result := TyRGBA(TyRedOf(c), TyGreenOf(c), TyBlueOf(c), ClampByte(A * 255));
end;

function TyMix(c1, c2: TTyColor; Pct: Single): TTyColor;
var f: Single;
begin
  // result = c1*(1-f) + c2*f where f = Pct/100 (Pct is amount of c2)
  f := Pct / 100;
  Result := TyRGBA(
    ClampByte(TyRedOf(c1)   * (1 - f) + TyRedOf(c2)   * f),
    ClampByte(TyGreenOf(c1) * (1 - f) + TyGreenOf(c2) * f),
    ClampByte(TyBlueOf(c1)  * (1 - f) + TyBlueOf(c2)  * f),
    ClampByte(TyAlphaOf(c1) * (1 - f) + TyAlphaOf(c2) * f));
end;

// --- expression evaluation -------------------------------------------------

// Resolve var(--name) -> the raw string from Vars (name without leading --).
// Vars holds entries 'name=value'; var(--accent) looks up 'accent'.
function ResolveVarRef(const Expr: string; Vars: TStrings): string;
var
  inner, key: string;
begin
  inner := Trim(Copy(Expr, 5, Length(Expr) - 5)); // strip 'var(' .. ')'
  if (Length(inner) >= 2) and (inner[1] = '-') and (inner[2] = '-') then
    key := Copy(inner, 3, Length(inner) - 2)
  else
    key := inner;
  if Vars = nil then
    raise Exception.CreateFmt('var(%s) but no vars provided', [inner]);
  if Vars.IndexOfName(key) < 0 then
    raise Exception.CreateFmt('Undefined variable: --%s', [key]);
  Result := Vars.Values[key];
end;

// Split the comma-separated argument list of a function call, honoring nested parens.
procedure SplitArgs(const ArgStr: string; Args: TStrings);
var
  i, depth, start: Integer;
begin
  Args.Clear;
  depth := 0;
  start := 1;
  for i := 1 to Length(ArgStr) do
  begin
    case ArgStr[i] of
      '(': Inc(depth);
      ')': Dec(depth);
      ',':
        if depth = 0 then
        begin
          Args.Add(Trim(Copy(ArgStr, start, i - start)));
          start := i + 1;
        end;
    end;
  end;
  if start <= Length(ArgStr) then
    Args.Add(Trim(Copy(ArgStr, start, Length(ArgStr) - start + 1)));
end;

// Parse a percentage/number token like '8%' or '50' into a Single.
function ParsePctOrNum(const S: string): Single;
var
  T: string;
  fmt: TFormatSettings;
begin
  T := Trim(S);
  if (T <> '') and (T[Length(T)] = '%') then
    T := Trim(Copy(T, 1, Length(T) - 1));
  fmt := DefaultFormatSettings;
  fmt.DecimalSeparator := '.';
  Result := StrToFloat(T, fmt);
end;

function TyEvalColor(const Expr: string; Vars: TStrings): TTyColor;
var
  E, fn, body: string;
  p: Integer;
  args: TStringList;
  a: string;
  aF: Single;
begin
  E := Trim(Expr);
  if E = '' then
    raise Exception.Create('Empty color expression');
  // transparent keyword -> fully transparent (alpha 0); usable anywhere a color is
  if LowerCase(E) = 'transparent' then
    Exit(tyTransparent);
  // direct hex
  if E[1] = '#' then
    Exit(TyParseColor(E));
  // var(...)
  if (Length(E) >= 4) and (LowerCase(Copy(E, 1, 4)) = 'var(') and (E[Length(E)] = ')') then
    Exit(TyEvalColor(ResolveVarRef(E, Vars), Vars));
  // function call: name( args )
  p := Pos('(', E);
  if (p > 0) and (E[Length(E)] = ')') then
  begin
    fn := LowerCase(Trim(Copy(E, 1, p - 1)));
    body := Copy(E, p + 1, Length(E) - p - 1);
    args := TStringList.Create;
    try
      SplitArgs(body, args);
      if (fn = 'lighten') and (args.Count = 2) then
        Exit(TyLighten(TyEvalColor(args[0], Vars), ParsePctOrNum(args[1])));
      if (fn = 'darken') and (args.Count = 2) then
        Exit(TyDarken(TyEvalColor(args[0], Vars), ParsePctOrNum(args[1])));
      if (fn = 'alpha') and (args.Count = 2) then
      begin
        a := Trim(args[1]);
        if (a <> '') and (a[Length(a)] = '%') then
          Exit(TyAlpha(TyEvalColor(args[0], Vars), ParsePctOrNum(a) / 100.0))
        else
          Exit(TyAlpha(TyEvalColor(args[0], Vars), ParsePctOrNum(a)));
      end;
      if (fn = 'mix') and (args.Count = 3) then
        Exit(TyMix(TyEvalColor(args[0], Vars), TyEvalColor(args[1], Vars), ParsePctOrNum(args[2])));
      if (fn = 'rgb') and (args.Count = 3) then
        Exit(TyRGB(ClampByte(ParsePctOrNum(args[0])),
                   ClampByte(ParsePctOrNum(args[1])),
                   ClampByte(ParsePctOrNum(args[2]))));
      if (fn = 'rgba') and (args.Count = 4) then
      begin
        a := Trim(args[3]);
        if (a <> '') and (a[Length(a)] = '%') then
          aF := ParsePctOrNum(a) / 100.0
        else
          aF := ParsePctOrNum(a);
        Exit(TyRGBA(ClampByte(ParsePctOrNum(args[0])),
                    ClampByte(ParsePctOrNum(args[1])),
                    ClampByte(ParsePctOrNum(args[2])),
                    ClampByte(aF * 255)));
      end;
      raise Exception.CreateFmt('Unknown color function: %s/%d', [fn, args.Count]);
    finally
      args.Free;
    end;
  end;
  // bare '--name' leaf: look up in Vars and recurse
  if (Length(E) >= 2) and (E[1] = '-') and (E[2] = '-') then
    Exit(TyEvalColor(Vars.Values[Copy(E, 3, MaxInt)], Vars));
  raise Exception.CreateFmt('Cannot evaluate color: %s', [Expr]);
end;

function TyEvalLength(const Expr: string; Vars: TStrings): Integer;
var
  E: string;
begin
  E := Trim(Expr);
  if (Length(E) >= 4) and (LowerCase(Copy(E, 1, 4)) = 'var(') and (E[Length(E)] = ')') then
    E := Trim(ResolveVarRef(E, Vars));
  // bare '--name' leaf: look up in Vars and recurse
  if (Length(E) >= 2) and (E[1] = '-') and (E[2] = '-') then
    Exit(TyEvalLength(Vars.Values[Copy(E, 3, MaxInt)], Vars));
  if (Length(E) >= 2) and (LowerCase(Copy(E, Length(E) - 1, 2)) = 'px') then
    E := Trim(Copy(E, 1, Length(E) - 2));
  Result := Round(ParsePctOrNum(E));
end;

function TyEvalFloat(const Expr: string; Vars: TStrings): Single;
var
  E: string;
begin
  E := Trim(Expr);
  if (Length(E) >= 4) and (LowerCase(Copy(E, 1, 4)) = 'var(') and (E[Length(E)] = ')') then
    E := Trim(ResolveVarRef(E, Vars));
  // bare '--name' leaf: look up in Vars and recurse
  if (Length(E) >= 2) and (E[1] = '-') and (E[2] = '-') then
    Exit(TyEvalFloat(Vars.Values[Copy(E, 3, MaxInt)], Vars));
  Result := ParsePctOrNum(E);
end;

end.
