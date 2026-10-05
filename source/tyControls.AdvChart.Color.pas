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

{ The same grammar, answering zrender's own four numbers rather than a packed
  colour: what `parse()` hands a visual mapping. The ALPHA STAYS A DOUBLE --
  `rgba(0,0,180,0.4)` packed is 102/255, and a ramp between two such colours
  interpolates 0.4, not the byte -- and a three-argument `rgba()` is Number()
  of each argument, unclamped, which is upstream's own shape for it.
  TyTryParseChartColor is this, packed: channels and alpha rounded the way
  Math.round rounds. }
function TyTryParseCssRgba(const AText: string;
  out AR, AG, AB, AA: Double): Boolean;

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

{ ==================== palettes, layers and scopes [Batch 105] ====================

  model/mixin/palette.ts as it is, rather than the one-cursor reading above.
  Three things that reading could not say:

  COLORLAYER. With `colorLayer` written and a requested count given, the
  palette is the first layer LONGER than the count, else the last one -- so
  three series take their colours from a three-colour layer only when a longer
  one does not come first. The series pass asks with the number of series
  models, the per-datum pass with the series' raw data count.

  AN INDEX PAST THE END. The cursor belongs to the SCOPE, not to a palette, and
  is advanced modulo whichever palette answered; the next ask may choose a
  shorter layer, and `palette[idx]` past its end is undefined. That undefined is
  remembered under the name like any colour, and the shape it lands on is
  painted with no fill at all.

  THE THEME AS THE DEFAULT PALETTE. Where upstream's default palette stands --
  no `color` at the root -- the theme's nine ramp slots stand here, taken
  through the same cursor and the same memo, and answered as a SLOT rather
  than a colour so a re-skin repaints without a rebuild. }
const
  cTyThemePaletteLength = 9;

type
  TTyPalette = record
    { the theme's nine slots, in place of Colors }
    Theme: Boolean;
    Colors: TTyChartColorArray;
  end;
  TTyPaletteArray = array of TTyPalette;

  { `colorLayer`: Present when the key holds an array (an empty one included:
    it is truthy, and its last layer is undefined, which sends the ask back to
    the default palette). }
  TTyPaletteLayers = record
    Present: Boolean;
    Layers: TTyPaletteArray;
  end;

  TTyPalettePickKind = (
    ppkNone,     // undefined: an empty palette, or an index past the end
    ppkColor,    // the author's colour
    ppkTheme);   // the theme ramp's Slot
  TTyPalettePick = record
    Kind: TTyPalettePickKind;
    Color: TTyChartColor;
    Slot: Integer;
  end;

  TTyPaletteMemo = record
    Name: string;
    Pick: TTyPalettePick;
  end;

  { upstream's inner(scope): paletteIdx and paletteNameMap }
  TTyPaletteScope = record
    Idx: Integer;
    Names: array of TTyPaletteMemo;
  end;

function TyPaletteLength(const APalette: TTyPalette): Integer;
function TyThemePalette: TTyPalette;

{ The chart's default palette: the root `color` when the key is there (an
  empty list kills the palette, as upstream's truthy `[]` keeps the theme's
  out), else the theme's nine. }
function TyChartRootPalette(AOption: TTyChartOption): TTyPalette;

{ A series' own `color` (get('color', true)): empty when it wrote none. }
function TySeriesOwnPalette(AOption: TTyChartOption;
  ASeriesIndex: Integer): TTyPalette;

{ `colorLayer` at the root (ASeriesIndex -1) or on one series, own key only.
  A layer that is not a list counts as an empty one. }
function TyChartPaletteLayersOf(AOption: TTyChartOption;
  ASeriesIndex: Integer): TTyPaletteLayers;

{ getFromPalette, verbatim. ARequest < 0 is `requestNum == null`. }
function TyPaletteFrom(const ADefault: TTyPalette;
  const ALayers: TTyPaletteLayers; const AName: string;
  var AScope: TTyPaletteScope; ARequest: Integer): TTyPalettePick;

{ SeriesModel.getColorFromPalette: the series' own palette over AOwnScope,
  and when that answers undefined the chart's over AChartScope. The per-datum
  pass hands the SAME scope twice -- upstream's shared scope object. }
function TySeriesPaletteFrom(const AOwn: TTyPalette;
  const AOwnLayers: TTyPaletteLayers; const AChart: TTyPalette;
  const AChartLayers: TTyPaletteLayers; const AName: string;
  var AOwnScope, AChartScope: TTyPaletteScope; ARequest: Integer): TTyPalettePick;

{ getColorBy(): the series' own `colorBy`, else its type's default ('data'
  for pie, funnel, gauge, radar, chord and themeRiver), else the root's, else
  'series'. A falsy value is 'series'. }
function TyChartColorByOf(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ASeriesType: string): string;

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

{ Read an image pattern, if that is what this value is: an object with an
  `image` that is not null and no `colorStops` (a gradient wins, as it does
  in brushPath). Only a string image can be held; anything else reads as a
  pattern with no image, which paints nothing. [Batch 105] }
function TyTryReadPattern(AData: TJSONData;
  out APat: TTyChartPattern): Boolean;

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
    { or an image [Batch 105]: Color is then transparent, upstream's
      convertToColorString of an object without stops }
    Pattern: TTyChartPattern;
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

uses tyControls.AdvChart.Scale, tyControls.AdvChart.Data;

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

{ zrender's clampCssByte, which is Math.round -- half UP, not FPC's banker's
  Round: `rgb(30%,0,0)` is 76.5 and comes out 77, and so does the green of
  `hsl(30,100%,30%)`.
  [Batch 54: this was Round, which gave 76 for both.] }
function ClampByte(AValue: Double): Cardinal;
begin
  if IsNan(AValue) then Exit(0);
  AValue := TyJsRound(AValue);
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

function TyTryParseCssRgba(const AText: string;
  out AR, AG, AB, AA: Double): Boolean;
var
  s, fname, body2: string;
  op, ep, i, n: Integer;
  parts: TStringList;
  ok: Boolean;
  iv: Integer;
  nib: array[0..3] of Integer;
  h, sat, lum, m1, m2: Double;
  named: TTyChartColor;
begin
  AR := 0;
  AG := 0;
  AB := 0;
  AA := 1;
  Result := False;
  s := Normalise(AText);
  if s = '' then Exit;

  if LookupNamed(s, named) then
  begin
    AR := (named shr 16) and $FF;
    AG := (named shr 8) and $FF;
    AB := named and $FF;
    AA := ((named shr 24) and $FF) / 255;
    Exit(True);
  end;

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
      { Each nibble doubled -- exactly nibble * 17. The alpha nibble is n/15,
        as upstream divides it, and packs to the same byte as #aabbccdd. }
      AR := nib[0] * 17;
      AG := nib[1] * 17;
      AB := nib[2] * 17;
      if n = 5 then AA := nib[3] / 15 else AA := 1;
      Exit(True);
    end;
    for i := 2 to n do
    begin
      HexNibble(s[i], ok);
      if not ok then Exit;
    end;
    iv := StrToInt('$' + Copy(s, 2, 6));
    AR := (iv shr 16) and $FF;
    AG := (iv shr 8) and $FF;
    AB := iv and $FF;
    if n = 9 then
      AA := StrToInt('$' + Copy(s, 8, 2)) / 255
    else
      AA := 1;
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
        Exit(True);
      { `rgba(r,g,b)` IS NOT `rgb(r,g,b)` upstream: it is Number() of each
        argument, unrounded and unclamped, and the alpha is 1. }
      if (fname = 'rgba') and (n = 3) then
      begin
        AR := TyJsToNumber(parts[0]);
        AG := TyJsToNumber(parts[1]);
        AB := TyJsToNumber(parts[2]);
        { Upstream lets NaN through here and paints with it; this one falls
          back. }
        if IsNan(AR) or IsNan(AG) or IsNan(AB) then Exit;
        Exit(True);
      end;
      if n < 3 then Exit;
      if n >= 4 then
      begin
        AA := CssFloat(Trim(parts[3]), ok);
        if not ok then Exit;
      end;
      { Any unreadable channel and the whole thing is not a colour. Upstream
        lets NaN through here and paints with it; this one falls back. }
      AR := CssInt(Trim(parts[0]), ok);
      if not ok then Exit;
      AG := CssInt(Trim(parts[1]), ok);
      if not ok then Exit;
      AB := CssInt(Trim(parts[2]), ok);
      if not ok then Exit;
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
      if n = 4 then
      begin
        AA := CssFloat(Trim(parts[3]), ok);
        if not ok then Exit;
      end;
      if lum <= 0.5 then m2 := lum * (sat + 1) else m2 := lum + sat - lum * sat;
      m1 := lum * 2 - m2;
      AR := ClampByte(HueToRgb(m1, m2, h + 1 / 3) * 255);
      AG := ClampByte(HueToRgb(m1, m2, h) * 255);
      AB := ClampByte(HueToRgb(m1, m2, h - 1 / 3) * 255);
      Exit(True);
    end;
  finally
    parts.Free;
  end;
end;

function TyTryParseChartColor(const AText: string;
  out AColor: TTyChartColor): Boolean;
var r, g, b, a: Double;
begin
  AColor := 0;
  Result := TyTryParseCssRgba(AText, r, g, b, a);
  if not Result then Exit;
  { The alpha packed the way the channels are: Math.round, not banker's --
    0.3 is 76.5 of a byte, and that is 77. }
  AColor := Pack(ClampByte(r), ClampByte(g), ClampByte(b), ClampByte(a * 255));
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

{ ==================== palettes, layers and scopes ==================== }

function TyPaletteLength(const APalette: TTyPalette): Integer;
begin
  if APalette.Theme then Result := cTyThemePaletteLength
  else Result := Length(APalette.Colors);
end;

function TyThemePalette: TTyPalette;
begin
  Result.Theme := True;
  Result.Colors := nil;
end;

function TyChartRootPalette(AOption: TTyChartOption): TTyPalette;
var declared: Boolean;
begin
  Result.Theme := False;
  Result.Colors := TyChartPaletteOf(AOption, -1, declared);
  if not declared then Result := TyThemePalette;
end;

function TySeriesOwnPalette(AOption: TTyChartOption;
  ASeriesIndex: Integer): TTyPalette;
var declared: Boolean;
begin
  Result.Theme := False;
  Result.Colors := TyChartPaletteOf(AOption, ASeriesIndex, declared);
end;

function TyChartPaletteLayersOf(AOption: TTyChartOption;
  ASeriesIndex: Integer): TTyPaletteLayers;
var
  node: TJSONObject;
  d: TJSONData;
  i: Integer;
begin
  Result := Default(TTyPaletteLayers);
  if AOption = nil then Exit;
  if ASeriesIndex >= 0 then
    node := ObjOf(AOption.ComponentAt('series', ASeriesIndex))
  else
    node := ObjOf(AOption.Root);
  if node = nil then Exit;
  d := node.Find('colorLayer');
  { only a list reaches getNearestPalette as a list; null and the rest of the
    falsy values are `!layeredPalette` }
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  Result.Present := True;
  SetLength(Result.Layers, TJSONArray(d).Count);
  for i := 0 to TJSONArray(d).Count - 1 do
  begin
    Result.Layers[i].Theme := False;
    if TJSONArray(d).Items[i].JSONType = jtArray then
      ColorsFrom(TJSONArray(d).Items[i], Result.Layers[i].Colors)
    else
      Result.Layers[i].Colors := nil;
  end;
end;

function TyPaletteFrom(const ADefault: TTyPalette;
  const ALayers: TTyPaletteLayers; const AName: string;
  var AScope: TTyPaletteScope; ARequest: Integer): TTyPalettePick;
var
  i, n: Integer;
  pal: TTyPalette;
begin
  Result := Default(TTyPalettePick);
  Result.Kind := ppkNone;
  { THE NAME FIRST, an undefined answer included -- hasOwnProperty }
  for i := 0 to High(AScope.Names) do
    if AScope.Names[i].Name = AName then
      Exit(AScope.Names[i].Pick);
  if (ARequest < 0) or not ALayers.Present then
    pal := ADefault
  else if Length(ALayers.Layers) = 0 then
    { palettes[-1] is undefined, and `palette || defaultPalette` takes over }
    pal := ADefault
  else
  begin
    { getNearestPalette: the first layer LONGER than the count, else the last }
    pal := ALayers.Layers[High(ALayers.Layers)];
    for i := 0 to High(ALayers.Layers) do
      if TyPaletteLength(ALayers.Layers[i]) > ARequest then
      begin
        pal := ALayers.Layers[i];
        Break;
      end;
  end;
  n := TyPaletteLength(pal);
  { an empty palette answers undefined and is neither remembered nor
    advanced }
  if n = 0 then Exit;
  { palette[paletteIdx], NOT modulo: the index may have been advanced by a
    longer palette on the same scope }
  if AScope.Idx < n then
  begin
    if pal.Theme then
    begin
      Result.Kind := ppkTheme;
      Result.Slot := AScope.Idx;
    end
    else
    begin
      Result.Kind := ppkColor;
      Result.Color := pal.Colors[AScope.Idx];
    end;
  end;
  if AName <> '' then
  begin
    SetLength(AScope.Names, Length(AScope.Names) + 1);
    AScope.Names[High(AScope.Names)].Name := AName;
    AScope.Names[High(AScope.Names)].Pick := Result;
  end;
  AScope.Idx := (AScope.Idx + 1) mod n;
end;

function TySeriesPaletteFrom(const AOwn: TTyPalette;
  const AOwnLayers: TTyPaletteLayers; const AChart: TTyPalette;
  const AChartLayers: TTyPaletteLayers; const AName: string;
  var AOwnScope, AChartScope: TTyPaletteScope; ARequest: Integer): TTyPalettePick;
begin
  Result := TyPaletteFrom(AOwn, AOwnLayers, AName, AOwnScope, ARequest);
  { `if (!color)`: undefined, however it came about }
  if Result.Kind = ppkNone then
    Result := TyPaletteFrom(AChart, AChartLayers, AName, AChartScope, ARequest);
end;

function ColorByText(AData: TJSONData; out AText: string): Boolean;
begin
  AText := '';
  Result := (AData <> nil) and (AData.JSONType <> jtNull);
  if not Result then Exit;
  case AData.JSONType of
    jtString: AText := AData.AsString;
    jtBoolean: if AData.AsBoolean then AText := 'true';
    jtNumber: if AData.AsFloat <> 0 then AText := AData.AsJSON;
  else
    AText := AData.AsJSON;
  end;
end;

function TyChartColorByOf(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ASeriesType: string): string;
var node: TJSONObject; s: string;
begin
  Result := 'series';
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('series', ASeriesIndex));
  if (node <> nil) and ColorByText(node.Find('colorBy'), s) then
  begin
    if s <> '' then Result := s;
    Exit;
  end;
  { the type's defaultOption is merged into the series option, so it stands
    before the root }
  if (ASeriesType = 'pie') or (ASeriesType = 'funnel') or (ASeriesType = 'gauge')
    or (ASeriesType = 'radar') or (ASeriesType = 'chord')
    or (ASeriesType = 'themeRiver') then
    Exit('data');
  node := ObjOf(AOption.Root);
  if (node <> nil) and ColorByText(node.Find('colorBy'), s) and (s <> '') then
    Result := s;
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

function TyTryReadPattern(AData: TJSONData;
  out APat: TTyChartPattern): Boolean;
var node: TJSONObject; d: TJSONData;
begin
  APat := Default(TTyChartPattern);
  Result := False;
  node := ObjOf(AData);
  if node = nil then Exit;
  if node.Find('colorStops') <> nil then Exit;
  d := node.Find('image');
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  APat.Present := True;
  if d.JSONType = jtString then APat.Image := d.AsString;
  { `pattern.repeat || 'repeat'` }
  d := node.Find('repeat');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
    APat.Repetition := d.AsString
  else
    APat.Repetition := 'repeat';
  { NaN for what is not a number: TyPatternMatrix's `|| 0` / `|| 1` }
  APat.X := NumIn(node, 'x', NaN);
  APat.Y := NumIn(node, 'y', NaN);
  APat.Rotation := NumIn(node, 'rotation', NaN);
  APat.ScaleX := NumIn(node, 'scaleX', NaN);
  APat.ScaleY := NumIn(node, 'scaleY', NaN);
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
  if TyTryReadPattern(d, Result.Pattern) then
  begin
    { an object: truthy, so it takes no palette slot; transparent where one
      colour is wanted }
    Result.Written := True;
    Result.Color := 0;
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
