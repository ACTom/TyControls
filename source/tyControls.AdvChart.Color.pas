unit tyControls.AdvChart.Color;
{$mode objfpc}{$H+}
{ A colour the AUTHOR wrote, and the palette a series gets when it wrote none.

  Until this unit every colour in the chart came from the .tycss theme, and an
  option naming one was read by nobody. That is right for the CHROME -- axis
  lines, grid, labels -- and wrong for the data: `itemStyle: { color: '#c23531' }`
  is the author speaking about their own chart, and no skin should overrule it.
  The rule this unit draws is: what the author wrote wins; what they did not
  write still comes from the theme.

  PURE. No LCL, no painter, no theme -- it is handed JSON and hands back
  numbers, so the palette arithmetic can be tested exactly. }
interface
uses SysUtils, Math, Classes, fpjson,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Paint;

type
  TTyChartColorArray = array of TTyChartColor;

{ ==================== the string grammar ==================== }

{ Upstream's grammar is zrender's `parse()`, and in a browser that is NOT the
  grammar that reaches the canvas -- the string is handed to ctx.fillStyle raw,
  so the BROWSER's CSS parser is what actually renders it and `parse()` only
  gates derived maths (the hover lift, interpolation, the legend swatch).

  THE PORT IS THE RASTERISER, so there is no wider grammar behind it: what this
  function accepts is the whole of what the chart can draw. Hence the 148
  keywords and all four functional forms, and hence NOT CSS Color 4 --
  `hwb()`, `lab()`, `oklch()`, `color-mix()` and the space-separated
  `rgb(255 0 0 / 50%)` syntax are rejected upstream too. }
function TyTryParseChartColor(const AText: string;
  out AColor: TTyChartColor): Boolean;

{ `none` is not a colour and is not in the keyword table: it means DO NOT PAINT.
  Upstream checks it before any parse and distinguishes it from `transparent`,
  which paints nothing but still hit-tests and still contributes a bounding
  rect. Same pixels, different geometry. }
function TyChartColorIsNone(const AText: string): Boolean;

{ ==================== the palette ==================== }

type
  { One name that has already been given a colour. Upstream keys its memo on
    the series NAME, so two series called the same thing share a colour AND
    share one slot. }
  TTyPaletteEntry = record
    Name: string;
    Color: TTyChartColor;
  end;

  { The cursor upstream keeps per scope. Copied by value on purpose: a caller
    that wants the series scope and the per-data scope to be independent keeps
    two of these, which is exactly upstream's arrangement. }
  TTyPaletteCursor = record
    Colors: TTyChartColorArray;
    Idx: Integer;
    Names: array of TTyPaletteEntry;
  end;

{ The author's palette, or nil when they wrote none.

  ONE SCOPE PER CALL: ASeriesIndex >= 0 reads `series[i].color` and nothing
  else; -1 reads the root `color` and nothing else. They are deliberately not
  chained here, because upstream does not chain them either -- a series with
  its own palette runs its own CURSOR over it, starting at nought, and never
  touches the chart-wide one. Chaining would lose that.

  (Upstream reads both with ignoreParent for the same reason: a series model's
  parent IS the global model, so an inherited read would find the root palette
  and the series-level branch would be dead code.)

  ADeclared says the key was PRESENT, which is not the same as the array being
  non-empty: `color: []` is truthy upstream and kills the palette outright, so
  a chart written that way draws in no colour at all rather than falling back. }
function TyChartPaletteOf(AOption: TTyChartOption; ASeriesIndex: Integer;
  out ADeclared: Boolean): TTyChartColorArray;

{ Start a cursor over AColors. }
function TyPaletteStart(const AColors: TTyChartColorArray): TTyPaletteCursor;

{ Take the next colour for AName, or the one AName already has.

  THE EXACT ORDER MATTERS and it is not the obvious one:
    a name already in the memo returns its colour and consumes NOTHING;
    an empty palette returns False and consumes nothing;
    otherwise the colour at Idx is taken, memoised under a NON-EMPTY name,
    and Idx advances MODULO the palette length -- the advance is not guarded
    by the name, so `name: ''` burns a slot without being remembered. }
function TyPaletteTake(var ACursor: TTyPaletteCursor; const AName: string;
  out AColor: TTyChartColor): Boolean;

{ What an unnamed series is called.

  NOT the empty string. Upstream builds `'series' + #0 + index` precisely so
  that two unnamed series cannot collide in the palette memo -- the comment
  beside it says so. A port that leaves the name empty gives every unnamed
  series the FIRST palette colour. }
function TyChartSeriesDefaultName(ASeriesIndex: Integer): string;

{ ==================== a colour that is an object ==================== }

{ Read a gradient, if that is what this value is.

  DETECTION IS STRUCTURAL: `colorStops` present and it is a gradient. The
  `type` field only chooses the shape afterwards, and anything that is not
  exactly `'radial'` -- a missing or misspelt `type` included -- is LINEAR.

  A stop whose colour cannot be read is DROPPED rather than made black: a
  ramp with one unreadable end is better read as the ramp between the ends
  that survive. }
function TyTryReadGradient(AData: TJSONData;
  out AGrad: TTyChartGradient): Boolean;

{ ==================== the style blocks ==================== }

type
  { One colour-valued option key. `Written` is separate from the value because
    an absent key falls through to the palette and an authored one does not --
    and because upstream OMITS an absent key from the style object rather than
    writing nil into it, which is what makes the fallthrough work. }
  TTyOptColor = record
    Written: Boolean;
    IsAuto: Boolean;      // the literal 'auto' -- resolve to the palette colour
    IsNone: Boolean;      // the literal 'none' -- do not paint
    Color: TTyChartColor;
    { A COLOUR CAN BE AN OBJECT. When it is, Color still holds the solid it
      degrades to, so every caller that wants one number keeps working and
      only the painter has to know the difference. }
    Gradient: TTyChartGradient;
  end;

  { `borderType` / `type`. A number or an array is verbatim pixels; the two
    words are multiples of the LINE WIDTH. }
  TTyOptDash = (todNone, todSolid, todDashed, todDotted, todExplicit);

  TTyOptStyle = record
    Color: TTyOptColor;
    { itemStyle only -- lineStyle has no border and areaStyle has no stroke
      at all, not even a colour. }
    BorderColor: TTyOptColor;
    BorderWidthLogical: Double;   // NaN = not written
    Opacity: Double;              // NaN = not written
    Dash: TTyOptDash;
    DashLogical: TTyDoubleArray;  // todExplicit only
  end;

{ Read one style block. AKey is 'itemStyle', 'lineStyle' or 'areaStyle', and
  which keys exist differs between them:
    itemStyle  color borderColor borderWidth borderType opacity
    lineStyle  color width       type        opacity
    areaStyle  color opacity                          -- six keys, no stroke }
function TyReadOptStyle(ANode: TJSONObject; const AKey: string): TTyOptStyle;

{ The dash a style block asked for, as LENGTHS -- which is what a renderer can
  use and what `todDashed` is not.

  THE TWO WORDS ARE MULTIPLES OF THE LINE WIDTH and the numbers are not: a
  `dashed` 2px line dashes in 8s and 4s, a `dashed` 1px line in 4s and 2s, and
  `type: [4, 2]` is four and two whatever the pen. zrender settles this in one
  function (canvas/dashStyle.ts) and so does this, because the alternative --
  which the port had -- is that the enum is read at four call sites, understood
  at none, and every `type: 'dashed'` in every option draws solid.

  A ZERO OR NEGATIVE WIDTH DRAWS SOLID, not a divide-by-nothing: upstream's
  guard is `!(lineWidth > 0)`, which also catches NaN. }
function TyDashPattern(ADash: TTyOptDash; const AExplicit: TTyDoubleArray;
  AWidthLogical: Double): TTyDoubleArray;

{ The style block a series' PALETTE colour lands in, and whether it lands on
  the fill or the stroke.

  A LINE SERIES IS THE TRAP: its access path is `itemStyle`, not `lineStyle`.
  So `lineStyle: { color: ... }` does not stop a line from taking a palette
  slot, and the palette colour it took still reaches its symbols and its area;
  the authored lineStyle colour wins only the polyline's own pixels. }
function TyStyleAccessPath(const ASeriesType: string): string;
function TyStyleDrawsWithStroke(const ASeriesType: string): Boolean;

implementation

type
  TNamedColor = record
    N: string;
    C: TTyChartColor;
  end;

const
  { zrender's kCSSColorTable, transcribed from the source rather than typed:
    148 entries -- 147 CSS Level 3 names plus `transparent`. `rebeccapurple`
    is NOT in it, so it does not parse here either; adding it would be a
    divergence rather than a fix. Sorted, so the lookup is a binary search. }
  cNamedColors: array[0..147] of TNamedColor = (
    (N: 'aliceblue'; C: $FFF0F8FF), (N: 'antiquewhite'; C: $FFFAEBD7),
    (N: 'aqua'; C: $FF00FFFF), (N: 'aquamarine'; C: $FF7FFFD4),
    (N: 'azure'; C: $FFF0FFFF), (N: 'beige'; C: $FFF5F5DC),
    (N: 'bisque'; C: $FFFFE4C4), (N: 'black'; C: $FF000000),
    (N: 'blanchedalmond'; C: $FFFFEBCD), (N: 'blue'; C: $FF0000FF),
    (N: 'blueviolet'; C: $FF8A2BE2), (N: 'brown'; C: $FFA52A2A),
    (N: 'burlywood'; C: $FFDEB887), (N: 'cadetblue'; C: $FF5F9EA0),
    (N: 'chartreuse'; C: $FF7FFF00), (N: 'chocolate'; C: $FFD2691E),
    (N: 'coral'; C: $FFFF7F50), (N: 'cornflowerblue'; C: $FF6495ED),
    (N: 'cornsilk'; C: $FFFFF8DC), (N: 'crimson'; C: $FFDC143C),
    (N: 'cyan'; C: $FF00FFFF), (N: 'darkblue'; C: $FF00008B),
    (N: 'darkcyan'; C: $FF008B8B), (N: 'darkgoldenrod'; C: $FFB8860B),
    (N: 'darkgray'; C: $FFA9A9A9), (N: 'darkgreen'; C: $FF006400),
    (N: 'darkgrey'; C: $FFA9A9A9), (N: 'darkkhaki'; C: $FFBDB76B),
    (N: 'darkmagenta'; C: $FF8B008B), (N: 'darkolivegreen'; C: $FF556B2F),
    (N: 'darkorange'; C: $FFFF8C00), (N: 'darkorchid'; C: $FF9932CC),
    (N: 'darkred'; C: $FF8B0000), (N: 'darksalmon'; C: $FFE9967A),
    (N: 'darkseagreen'; C: $FF8FBC8F), (N: 'darkslateblue'; C: $FF483D8B),
    (N: 'darkslategray'; C: $FF2F4F4F), (N: 'darkslategrey'; C: $FF2F4F4F),
    (N: 'darkturquoise'; C: $FF00CED1), (N: 'darkviolet'; C: $FF9400D3),
    (N: 'deeppink'; C: $FFFF1493), (N: 'deepskyblue'; C: $FF00BFFF),
    (N: 'dimgray'; C: $FF696969), (N: 'dimgrey'; C: $FF696969),
    (N: 'dodgerblue'; C: $FF1E90FF), (N: 'firebrick'; C: $FFB22222),
    (N: 'floralwhite'; C: $FFFFFAF0), (N: 'forestgreen'; C: $FF228B22),
    (N: 'fuchsia'; C: $FFFF00FF), (N: 'gainsboro'; C: $FFDCDCDC),
    (N: 'ghostwhite'; C: $FFF8F8FF), (N: 'gold'; C: $FFFFD700),
    (N: 'goldenrod'; C: $FFDAA520), (N: 'gray'; C: $FF808080),
    (N: 'green'; C: $FF008000), (N: 'greenyellow'; C: $FFADFF2F),
    (N: 'grey'; C: $FF808080), (N: 'honeydew'; C: $FFF0FFF0),
    (N: 'hotpink'; C: $FFFF69B4), (N: 'indianred'; C: $FFCD5C5C),
    (N: 'indigo'; C: $FF4B0082), (N: 'ivory'; C: $FFFFFFF0),
    (N: 'khaki'; C: $FFF0E68C), (N: 'lavender'; C: $FFE6E6FA),
    (N: 'lavenderblush'; C: $FFFFF0F5), (N: 'lawngreen'; C: $FF7CFC00),
    (N: 'lemonchiffon'; C: $FFFFFACD), (N: 'lightblue'; C: $FFADD8E6),
    (N: 'lightcoral'; C: $FFF08080), (N: 'lightcyan'; C: $FFE0FFFF),
    (N: 'lightgoldenrodyellow'; C: $FFFAFAD2), (N: 'lightgray'; C: $FFD3D3D3),
    (N: 'lightgreen'; C: $FF90EE90), (N: 'lightgrey'; C: $FFD3D3D3),
    (N: 'lightpink'; C: $FFFFB6C1), (N: 'lightsalmon'; C: $FFFFA07A),
    (N: 'lightseagreen'; C: $FF20B2AA), (N: 'lightskyblue'; C: $FF87CEFA),
    (N: 'lightslategray'; C: $FF778899), (N: 'lightslategrey'; C: $FF778899),
    (N: 'lightsteelblue'; C: $FFB0C4DE), (N: 'lightyellow'; C: $FFFFFFE0),
    (N: 'lime'; C: $FF00FF00), (N: 'limegreen'; C: $FF32CD32),
    (N: 'linen'; C: $FFFAF0E6), (N: 'magenta'; C: $FFFF00FF),
    (N: 'maroon'; C: $FF800000), (N: 'mediumaquamarine'; C: $FF66CDAA),
    (N: 'mediumblue'; C: $FF0000CD), (N: 'mediumorchid'; C: $FFBA55D3),
    (N: 'mediumpurple'; C: $FF9370DB), (N: 'mediumseagreen'; C: $FF3CB371),
    (N: 'mediumslateblue'; C: $FF7B68EE), (N: 'mediumspringgreen'; C: $FF00FA9A),
    (N: 'mediumturquoise'; C: $FF48D1CC), (N: 'mediumvioletred'; C: $FFC71585),
    (N: 'midnightblue'; C: $FF191970), (N: 'mintcream'; C: $FFF5FFFA),
    (N: 'mistyrose'; C: $FFFFE4E1), (N: 'moccasin'; C: $FFFFE4B5),
    (N: 'navajowhite'; C: $FFFFDEAD), (N: 'navy'; C: $FF000080),
    (N: 'oldlace'; C: $FFFDF5E6), (N: 'olive'; C: $FF808000),
    (N: 'olivedrab'; C: $FF6B8E23), (N: 'orange'; C: $FFFFA500),
    (N: 'orangered'; C: $FFFF4500), (N: 'orchid'; C: $FFDA70D6),
    (N: 'palegoldenrod'; C: $FFEEE8AA), (N: 'palegreen'; C: $FF98FB98),
    (N: 'paleturquoise'; C: $FFAFEEEE), (N: 'palevioletred'; C: $FFDB7093),
    (N: 'papayawhip'; C: $FFFFEFD5), (N: 'peachpuff'; C: $FFFFDAB9),
    (N: 'peru'; C: $FFCD853F), (N: 'pink'; C: $FFFFC0CB),
    (N: 'plum'; C: $FFDDA0DD), (N: 'powderblue'; C: $FFB0E0E6),
    (N: 'purple'; C: $FF800080), (N: 'red'; C: $FFFF0000),
    (N: 'rosybrown'; C: $FFBC8F8F), (N: 'royalblue'; C: $FF4169E1),
    (N: 'saddlebrown'; C: $FF8B4513), (N: 'salmon'; C: $FFFA8072),
    (N: 'sandybrown'; C: $FFF4A460), (N: 'seagreen'; C: $FF2E8B57),
    (N: 'seashell'; C: $FFFFF5EE), (N: 'sienna'; C: $FFA0522D),
    (N: 'silver'; C: $FFC0C0C0), (N: 'skyblue'; C: $FF87CEEB),
    (N: 'slateblue'; C: $FF6A5ACD), (N: 'slategray'; C: $FF708090),
    (N: 'slategrey'; C: $FF708090), (N: 'snow'; C: $FFFFFAFA),
    (N: 'springgreen'; C: $FF00FF7F), (N: 'steelblue'; C: $FF4682B4),
    (N: 'tan'; C: $FFD2B48C), (N: 'teal'; C: $FF008080),
    (N: 'thistle'; C: $FFD8BFD8), (N: 'tomato'; C: $FFFF6347),
    (N: 'transparent'; C: $00000000), (N: 'turquoise'; C: $FF40E0D0),
    (N: 'violet'; C: $FFEE82EE), (N: 'wheat'; C: $FFF5DEB3),
    (N: 'white'; C: $FFFFFFFF), (N: 'whitesmoke'; C: $FFF5F5F5),
    (N: 'yellow'; C: $FFFFFF00), (N: 'yellowgreen'; C: $FF9ACD32)
  );

var
  { A dot decimal separator whatever the locale is: an option is JSON, and a
    JSON number is written with a dot wherever it was authored. }
  Fmt: TFormatSettings;

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData.JSONType = jtObject) then
    Result := TJSONObject(AData)
  else
    Result := nil;
end;

function LookupNamed(const AName: string; out AColor: TTyChartColor): Boolean;
var lo, hi, mid, cmp: Integer;
begin
  lo := 0;
  hi := High(cNamedColors);
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    cmp := CompareStr(cNamedColors[mid].N, AName);
    if cmp = 0 then
    begin
      AColor := cNamedColors[mid].C;
      Exit(True);
    end;
    if cmp < 0 then lo := mid + 1 else hi := mid - 1;
  end;
  AColor := 0;
  Result := False;
end;

{ Every U+0020 removed and the rest lower-cased -- upstream's own
  normalisation, and it is a REPLACE not a trim, which is why
  'rgba(0, 0, 0, 0.2)' and 'Light Sky Blue' both reach the table. Tabs and
  newlines are NOT stripped upstream, and are not stripped here. }
function Normalise(const AText: string): string;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(AText) do
    if AText[i] <> ' ' then Result := Result + LowerCase(AText[i]);
end;

function HexNibble(AChar: Char; out AOK: Boolean): Integer;
begin
  AOK := True;
  case AChar of
    '0'..'9': Result := Ord(AChar) - Ord('0');
    'a'..'f': Result := Ord(AChar) - Ord('a') + 10;
  else
    AOK := False;
    Result := 0;
  end;
end;

function ClampByte(AValue: Double): Cardinal;
begin
  if IsNan(AValue) then Exit(0);
  AValue := Round(AValue);
  if AValue < 0 then AValue := 0;
  if AValue > 255 then AValue := 255;
  Result := Cardinal(Trunc(AValue));
end;

function ClampUnit(AValue: Double): Double;
begin
  if IsNan(AValue) then Exit(0);
  Result := Max(Double(0), Min(Double(1), AValue));
end;

{ A channel argument: a percentage of 255, or a plain number TRUNCATED --
  upstream uses parseInt, so `rgb(1,2,2.9)` really is blue 2. }
function CssInt(const AText: string; out AOK: Boolean): Double;
var v: Double;
begin
  AOK := False;
  Result := 0;
  if AText = '' then Exit;
  if AText[Length(AText)] = '%' then
  begin
    if not TryStrToFloat(Copy(AText, 1, Length(AText) - 1), v, Fmt) then Exit;
    AOK := True;
    Exit(ClampByte(v / 100 * 255));
  end;
  if not TryStrToFloat(AText, v, Fmt) then Exit;
  AOK := True;
  Result := ClampByte(Trunc(v));
end;

{ An alpha or an hsl percentage: a percentage of one, or a plain number,
  clamped to 0..1. }
function CssFloat(const AText: string; out AOK: Boolean): Double;
var v: Double;
begin
  AOK := False;
  Result := 0;
  if AText = '' then Exit;
  if AText[Length(AText)] = '%' then
  begin
    if not TryStrToFloat(Copy(AText, 1, Length(AText) - 1), v, Fmt) then Exit;
    AOK := True;
    Exit(ClampUnit(v / 100));
  end;
  if not TryStrToFloat(AText, v, Fmt) then Exit;
  AOK := True;
  Result := ClampUnit(v);
end;

function HueToRgb(m1, m2, h: Double): Double;
begin
  if h < 0 then h := h + 1 else if h > 1 then h := h - 1;
  if h * 6 < 1 then Exit(m1 + (m2 - m1) * h * 6);
  if h * 2 < 1 then Exit(m2);
  if h * 3 < 2 then Exit(m1 + (m2 - m1) * (2 / 3 - h) * 6);
  Result := m1;
end;

function Pack(AR, AG, AB, AAlpha: Cardinal): TTyChartColor;
begin
  Result := TTyChartColor((AAlpha shl 24) or (AR shl 16) or (AG shl 8) or AB);
end;

function TyChartColorIsNone(const AText: string): Boolean;
begin
  Result := Normalise(AText) = 'none';
end;

function TyTryParseChartColor(const AText: string;
  out AColor: TTyChartColor): Boolean;
var
  s, fname, body2: string;
  op, ep, i, n: Integer;
  parts: TStringList;
  ok, ok2: Boolean;
  iv: Integer;
  nib: array[0..3] of Integer;
  h, sat, lum, m1, m2, alpha: Double;
begin
  AColor := 0;
  Result := False;
  s := Normalise(AText);
  if s = '' then Exit;

  if LookupNamed(s, AColor) then Exit(True);

  if s[1] = '#' then
  begin
    n := Length(s);
    { STRICT ON THE DIGITS, and that is a deliberate divergence. Upstream uses
      parseInt, which stops at the first non-hex character and validates only
      the resulting NUMBER -- so '#12g' becomes #001122, silently, and is
      cached. Both lines carry upstream's own `TODO: Stricter parsing`. Here a
      typo falls through to the theme colour, which is a visible-but-sane
      answer rather than a confidently wrong one. }
    if not (n in [4, 5, 7, 9]) then Exit;
    if n <= 5 then
    begin
      for i := 0 to n - 2 do
      begin
        nib[i] := HexNibble(s[i + 2], ok);
        if not ok then Exit;
      end;
      { Each nibble doubled -- exactly nibble * 17, and for the alpha nibble
        n/15 and (n*17)/255 agree bit for bit, so #abcd and #aabbccdd are the
        same colour. }
      if n = 5 then alpha := nib[3] * 17 else alpha := 255;
      AColor := Pack(Cardinal(nib[0] * 17), Cardinal(nib[1] * 17),
                     Cardinal(nib[2] * 17), Cardinal(Trunc(alpha)));
      Exit(True);
    end;
    for i := 2 to n do
    begin
      HexNibble(s[i], ok);
      if not ok then Exit;
    end;
    iv := StrToInt('$' + Copy(s, 2, 6));
    if n = 9 then
      alpha := StrToInt('$' + Copy(s, 8, 2))
    else
      alpha := 255;
    AColor := Pack(Cardinal((iv shr 16) and $FF), Cardinal((iv shr 8) and $FF),
                   Cardinal(iv and $FF), Cardinal(Trunc(alpha)));
    Exit(True);
  end;

  op := Pos('(', s);
  ep := Pos(')', s);
  { The FIRST ')' must be the last character -- so a nested paren fails the
    gate outright, which is how upstream rejects `linear-gradient(...)`. }
  if (op < 1) or (ep <> Length(s)) then Exit;
  fname := Copy(s, 1, op - 1);
  body2 := Copy(s, op + 1, ep - op - 1);
  parts := TStringList.Create;
  try
    parts.Delimiter := ',';
    parts.StrictDelimiter := True;
    parts.DelimitedText := body2;
    n := parts.Count;

    if (fname = 'rgb') or (fname = 'rgba') then
    begin
      { THE TWO NAMES DISAGREE ON GARBAGE, which is upstream's shape and not an
        accident worth smoothing: a wrong-arity `rgba()` is a SUCCESS returning
        opaque black, while a wrong-arity `rgb()` fails. The one arity that
        matters in practice is `rgba(r,g,b)` with three arguments -- ECharts
        ships one of those in its own parallel defaults, so a parser that
        refuses it fails on a stock chart. }
      if (fname = 'rgba') and (n <> 3) and (n <> 4) then
      begin
        AColor := Pack(0, 0, 0, 255);
        Exit(True);
      end;
      if n < 3 then Exit;
      alpha := 255;
      if n >= 4 then
      begin
        alpha := CssFloat(Trim(parts[3]), ok) * 255;
        if not ok then Exit;
      end;
      AColor := Pack(
        Cardinal(Trunc(CssInt(Trim(parts[0]), ok))),
        Cardinal(Trunc(CssInt(Trim(parts[1]), ok2))),
        Cardinal(Trunc(CssInt(Trim(parts[2]), ok))),
        Cardinal(Round(alpha)));
      { Any unreadable channel and the whole thing is not a colour. Upstream
        lets NaN through here and paints with it; this one falls back. }
      for i := 0 to 2 do
      begin
        CssInt(Trim(parts[i]), ok);
        if not ok then Exit;
      end;
      Exit(True);
    end;

    if (fname = 'hsl') and (n <> 3) then Exit;
    if (fname = 'hsla') and (n <> 4) then Exit;
    if (fname = 'hsl') or (fname = 'hsla') then
    begin
      { The hue WRAPS rather than clamping, through a double modulo, and it is
        read with a bare float parse -- so a unit suffix is swallowed and
        `0.5turn` is half a degree, not half a turn. }
      if not TryStrToFloat(Trim(parts[0]), h, Fmt) then Exit;
      h := h - Trunc(h / 360) * 360;
      if h < 0 then h := h + 360;
      h := h / 360;
      sat := CssFloat(Trim(parts[1]), ok);
      if not ok then Exit;
      lum := CssFloat(Trim(parts[2]), ok);
      if not ok then Exit;
      alpha := 255;
      if n = 4 then
      begin
        alpha := CssFloat(Trim(parts[3]), ok) * 255;
        if not ok then Exit;
      end;
      if lum <= 0.5 then m2 := lum * (sat + 1) else m2 := lum + sat - lum * sat;
      m1 := lum * 2 - m2;
      AColor := Pack(ClampByte(HueToRgb(m1, m2, h + 1 / 3) * 255),
                     ClampByte(HueToRgb(m1, m2, h) * 255),
                     ClampByte(HueToRgb(m1, m2, h - 1 / 3) * 255),
                     Cardinal(Round(alpha)));
      Exit(True);
    end;
  finally
    parts.Free;
  end;
end;

{ ==================== the palette ==================== }

function TyChartSeriesDefaultName(ASeriesIndex: Integer): string;
begin
  Result := 'series' + #0 + IntToStr(ASeriesIndex);
end;

{ One `color` value -- an array of strings, or a bare string, which upstream
  leaves as a string in the resolved option and normalises only at read time. }
function ColorsFrom(AData: TJSONData; out AColors: TTyChartColorArray): Boolean;
var i, n: Integer; c: TTyChartColor; g: TTyChartGradient;
begin
  AColors := nil;
  Result := False;
  if AData = nil then Exit;
  if AData.JSONType = jtString then
  begin
    Result := True;
    if TyTryParseChartColor(AData.AsString, c) then
    begin
      SetLength(AColors, 1);
      AColors[0] := c;
    end;
    Exit;
  end;
  if AData.JSONType <> jtArray then Exit;
  Result := True;
  n := 0;
  SetLength(AColors, TJSONArray(AData).Count);
  for i := 0 to TJSONArray(AData).Count - 1 do
  begin
    { A PALETTE ENTRY MAY BE A GRADIENT. Only the solid it degrades to is
      kept here -- a palette is asked for one colour at a time by a dozen
      callers, and threading the whole object through all of them to serve a
      case nobody writes would cost more than it is worth. An author who
      wants a gradient on a series writes it on that series' itemStyle. }
    if TyTryReadGradient(TJSONArray(AData).Items[i], g) then
    begin
      AColors[n] := TyGradientSolid(g);
      Inc(n);
      Continue;
    end;
    if (TJSONArray(AData).Items[i].JSONType = jtString)
      and TyTryParseChartColor(TJSONArray(AData).Items[i].AsString, c) then
    begin
      AColors[n] := c;
      Inc(n);
    end;
  end;
  SetLength(AColors, n);
end;

function TyChartPaletteOf(AOption: TTyChartOption; ASeriesIndex: Integer;
  out ADeclared: Boolean): TTyChartColorArray;
var node: TJSONObject;
begin
  Result := nil;
  ADeclared := False;
  if AOption = nil then Exit;
  if ASeriesIndex >= 0 then
    node := ObjOf(AOption.ComponentAt('series', ASeriesIndex))
  else
    node := ObjOf(AOption.Root);
  if node = nil then Exit;
  if ColorsFrom(node.Find('color'), Result) then ADeclared := True;
end;

function TyPaletteStart(const AColors: TTyChartColorArray): TTyPaletteCursor;
begin
  Result.Colors := AColors;
  Result.Idx := 0;
  Result.Names := nil;
end;

function TyPaletteTake(var ACursor: TTyPaletteCursor; const AName: string;
  out AColor: TTyChartColor): Boolean;
var i, n: Integer;
begin
  AColor := 0;
  for i := 0 to High(ACursor.Names) do
    if ACursor.Names[i].Name = AName then
    begin
      { A repeated name consumes NOTHING. This is what keeps two series called
        the same thing the same colour, and it is checked before the palette is
        even looked at. }
      AColor := ACursor.Names[i].Color;
      Exit(True);
    end;
  n := Length(ACursor.Colors);
  if n = 0 then Exit(False);
  AColor := ACursor.Colors[ACursor.Idx mod n];
  if AName <> '' then
  begin
    SetLength(ACursor.Names, Length(ACursor.Names) + 1);
    ACursor.Names[High(ACursor.Names)].Name := AName;
    ACursor.Names[High(ACursor.Names)].Color := AColor;
  end;
  { UNGUARDED by the name: an explicitly empty name is never remembered and
    still burns a slot. }
  ACursor.Idx := (ACursor.Idx + 1) mod n;
  Result := True;
end;

{ ==================== the style blocks ==================== }

function NumIn(ANode: TJSONObject; const AKey: string;
  ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

function TyTryReadGradient(AData: TJSONData;
  out AGrad: TTyChartGradient): Boolean;
var
  node, stop: TJSONObject;
  stops: TJSONData;
  i, n: Integer;
  d: TJSONData;
  c: TTyChartColor;
begin
  AGrad := Default(TTyChartGradient);
  Result := False;
  node := ObjOf(AData);
  if node = nil then Exit;
  stops := node.Find('colorStops');
  if (stops = nil) or (stops.JSONType <> jtArray) then Exit;

  d := node.Find('type');
  if (d <> nil) and (d.JSONType = jtString)
    and (Normalise(d.AsString) = 'radial') then
    AGrad.Kind := cgkRadial
  else
    AGrad.Kind := cgkLinear;

  { The defaults differ by shape, and the linear pair is the one a port gets
    wrong: 0,0 -> 1,0 is LEFT TO RIGHT. }
  if AGrad.Kind = cgkRadial then
  begin
    AGrad.X := NumIn(node, 'x', 0.5);
    AGrad.Y := NumIn(node, 'y', 0.5);
    AGrad.R := NumIn(node, 'r', 0.5);
  end
  else
  begin
    AGrad.X := NumIn(node, 'x', 0);
    AGrad.Y := NumIn(node, 'y', 0);
    AGrad.X2 := NumIn(node, 'x2', 1);
    AGrad.Y2 := NumIn(node, 'y2', 0);
  end;
  d := node.Find('global');
  AGrad.Global := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;

  n := 0;
  SetLength(AGrad.Stops, TJSONArray(stops).Count);
  for i := 0 to TJSONArray(stops).Count - 1 do
  begin
    stop := ObjOf(TJSONArray(stops).Items[i]);
    if stop = nil then Continue;
    d := stop.Find('color');
    if (d = nil) or (d.JSONType <> jtString) then Continue;
    if not TyTryParseChartColor(d.AsString, c) then Continue;
    AGrad.Stops[n].Offset := NumIn(stop, 'offset', 0);
    AGrad.Stops[n].Color := c;
    Inc(n);
  end;
  SetLength(AGrad.Stops, n);
  { A gradient with nothing left to ramp between is not a colour. }
  if n = 0 then
  begin
    AGrad.Kind := cgkNone;
    Exit;
  end;
  Result := True;
end;

function ReadOptColor(ANode: TJSONObject; const AKey: string): TTyOptColor;
var d: TJSONData; s: string;
begin
  Result := Default(TTyOptColor);
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  { ABSENT IS NOT THE SAME AS NIL. Upstream omits a missing key from the style
    object entirely, which is exactly what lets the palette fill it in later;
    writing nil in its place would clobber the palette colour. `color: null`
    therefore behaves as though nothing were written. }
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  if TyTryReadGradient(d, Result.Gradient) then
  begin
    Result.Written := True;
    { The solid it degrades to, for every caller that wants one number. }
    Result.Color := TyGradientSolid(Result.Gradient);
    Exit;
  end;
  if d.JSONType <> jtString then Exit;
  Result.Written := True;
  s := Normalise(d.AsString);
  if s = 'auto' then
  begin
    Result.IsAuto := True;
    Exit;
  end;
  if s = 'none' then
  begin
    Result.IsNone := True;
    Exit;
  end;
  if not TyTryParseChartColor(d.AsString, Result.Color) then
    { Unreadable. Upstream would hand the string to the canvas and get the
      PREVIOUS element's colour; there is nothing to copy there. Treated as
      unwritten, so the theme answers. }
    Result.Written := False;
end;

function ReadDash(ANode: TJSONObject; const AKey: string;
  out ADash: TTyDoubleArray): TTyOptDash;
var d: TJSONData; s: string; i: Integer;
begin
  ADash := nil;
  Result := todNone;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  if d.JSONType = jtNumber then
  begin
    { A bare number is verbatim pixels, on and off alike. }
    SetLength(ADash, 1);
    ADash[0] := d.AsFloat;
    Exit(todExplicit);
  end;
  if d.JSONType = jtArray then
  begin
    { EACH ELEMENT TYPE-CHECKED: `AsFloat` COERCES, so `['5px', '10px']`
      does not read as five and ten, it raises. A dash pattern is a list of
      lengths; an entry that is not one contributes nothing rather than
      killing the render. }
    SetLength(ADash, TJSONArray(d).Count);
    for i := 0 to TJSONArray(d).Count - 1 do
      if TJSONArray(d).Items[i].JSONType = jtNumber then
        ADash[i] := TJSONArray(d).Items[i].AsFloat
      else
        ADash[i] := 0;
    { An EMPTY array is truthy upstream and draws solid. }
    if Length(ADash) = 0 then Exit(todSolid);
    Exit(todExplicit);
  end;
  if d.JSONType <> jtString then Exit;
  s := Normalise(d.AsString);
  if s = 'dashed' then Exit(todDashed);
  if s = 'dotted' then Exit(todDotted);
  if s = 'solid' then Exit(todSolid);
end;

function TyDashPattern(ADash: TTyOptDash; const AExplicit: TTyDoubleArray;
  AWidthLogical: Double): TTyDoubleArray;
begin
  Result := nil;
  if ADash in [todNone, todSolid] then Exit;
  { NaN fails every comparison, so this rejects it too. }
  if not (AWidthLogical > 0) then Exit;
  case ADash of
    todDashed:
      begin
        SetLength(Result, 2);
        Result[0] := 4 * AWidthLogical;
        Result[1] := 2 * AWidthLogical;
      end;
    todDotted:
      begin
        { ONE ENTRY, not two. A single length means on and off alike, and
          writing [w, w] here would be the same picture said twice -- until
          somebody scales one of them. }
        SetLength(Result, 1);
        Result[0] := AWidthLogical;
      end;
    todExplicit:
      Result := Copy(AExplicit, 0, Length(AExplicit));
  end;
end;

function NumOr(ANode: TJSONObject; const AKey: string): Double;
var d: TJSONData;
begin
  Result := NaN;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

function TyReadOptStyle(ANode: TJSONObject; const AKey: string): TTyOptStyle;
var sub: TJSONObject; d: TJSONData;
begin
  Result := Default(TTyOptStyle);
  Result.BorderWidthLogical := NaN;
  Result.Opacity := NaN;
  Result.Dash := todNone;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  sub := ObjOf(d);
  if sub = nil then Exit;
  Result.Color := ReadOptColor(sub, 'color');
  Result.Opacity := NumOr(sub, 'opacity');
  if AKey = 'lineStyle' then
  begin
    { A line has a WIDTH, not a border width, and a `type`, not a borderType. }
    Result.BorderWidthLogical := NumOr(sub, 'width');
    Result.Dash := ReadDash(sub, 'type', Result.DashLogical);
    Exit;
  end;
  if AKey = 'areaStyle' then
    { SIX KEYS AND NO STROKE. An areaStyle.borderColor is read by nobody
      upstream, so reading one here would invent a behaviour. }
    Exit;
  Result.BorderColor := ReadOptColor(sub, 'borderColor');
  Result.BorderWidthLogical := NumOr(sub, 'borderWidth');
  Result.Dash := ReadDash(sub, 'borderType', Result.DashLogical);
end;

function TyStyleAccessPath(const ASeriesType: string): string;
begin
  { The prototype default is `itemStyle` for EVERY series, and exactly two
    types override it. A line is not one of them. }
  if (ASeriesType = 'lines') or (ASeriesType = 'parallel') then
    Result := 'lineStyle'
  else
    Result := 'itemStyle';
end;

function TyStyleDrawsWithStroke(const ASeriesType: string): Boolean;
begin
  { boxplot keeps `itemStyle` but draws with the STROKE, so it is
    `itemStyle.borderColor` that suppresses its palette slot, not
    `itemStyle.color`. }
  Result := (ASeriesType = 'lines') or (ASeriesType = 'parallel')
         or (ASeriesType = 'boxplot');
end;


initialization
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';

end.
