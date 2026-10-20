unit ucallbacks;

{$mode objfpc}{$H+}

{ THE GALLERY'S OTHER FUNCTIONS, IN PASCAL.

  An ECharts option holds functions in many places besides a custom series'
  renderItem: label and axis label formatters, tooltip formatters and
  positions, symbolSize, a series' itemStyle.color, labelLayout,
  animationDelay, universalTransition.delay, a graphic's onclick, a
  transform's itemNameFormatter. TTyAdvanceChart takes each as a named
  handler: the option says `formatter: '@name'` and the host registers a
  method under that name in the registry for its kind (TyChartRegister*).
  The gallery harvest writes the name of every function it meets as
  `<example id>.<key>` -- `<id>.<key>#2` for a second distinct function
  under the same key (tools/advchart-gallery/harvest.js). This unit is the
  other half: each handler below is the page's function, line for line, and
  RegisterGalleryCallbacks registers them all. (The renderItems are in
  urenderitems.pas, the geo projection in ualbersusa.pas.)

  WHAT A TRANSCRIPTION KEEPS. JavaScript's arithmetic in the page's order,
  its rounding and number-to-text (TyJsRound, TyJsNumberToString,
  TyJsToFixedStr), String() of whatever the page concatenates (undefined,
  null, an array joined by commas), and the page's own constants -- the
  tables a function closes over (a city list, a colour table, the days of
  the week) are copied from the page.

  WHAT IS NOT TRANSCRIBED, AND WHY: GalleryUntranscribed lists the names
  and the reason. The library then says what it says for a handler nobody
  registered. [R2-J3: nothing is left out now -- lines-airline's tooltip
  reads the airport and route tables the harvest carries into
  data/lines-airline-tables.json.gz; scatter-nutrients-matrix's colours its
  fields by the table GalleryPrepare computes from the option, as the page
  computes it from the axes it makes; pictorialBar-hill's delay is handed
  its glyph's place.]

  TWO PLACES THE DEMO DIFFERS FROM THE PAGE, both said where they are:
  bar-race-country's flags come from a CDN the demo has no copy of (the
  emoji is left out, where the harvest's empty table would print
  'undefined'), and scatter-painter-choice's marker sizes and colours are
  read from data/scatter-painter-choice-marker.json, the part of the page's
  data file its two functions read. }

interface

uses
  Classes, SysUtils, Math, fpjson,
  tyControls.AdvChart.Handlers;

{ Register every handler of this unit under its gallery name. }
procedure RegisterGalleryCallbacks;

{ The names RegisterGalleryCallbacks registers. }
procedure GalleryCallbackNames(AList: TStrings);

{ The gallery's function names that are NOT transcribed, as
  'name=reason' lines. [R2-J3: none] }
procedure GalleryUntranscribed(AList: TStrings);

{ [R2-J3] What an example's functions compute from the chart before it is
  set: call it with the example's id and the option text the chart is
  given (scatter-nutrients-matrix's colour per axis name; parsed only for
  an example that needs it). }
procedure GalleryPrepare(const AId, AOptionText: string);

implementation

uses
  ugenerated,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape, tyControls.AdvChart.JsMath, tyControls.AdvChart.Scale,
  tyControls.AdvChart.Data, tyControls.AdvChart.Time,
  tyControls.AdvChart.AnimOpt, tyControls.AdvChart.Events,
  jsonparser;


const
  { the full-width colon, U+FF1A }
  cColonW = #$EF#$BC#$9A;
  { the degree sign }
  cDegree = #$C2#$B0;

type
  TGalleryCallbacks = class
  private
    FRandom: LongWord;
    FMarkerLoaded: Boolean;
    FMarkerSize, FMarkerColor: TJSONArray;
    FMarkerRef: Double;
    FMarkerRoot: TJSONData;
    { [R2-J3] lines-airline's tables; scatter-nutrients-matrix's colours }
    FAirLoaded: Boolean;
    FAirRoot: TJSONData;
    FAirports, FRoutes: TJSONArray;
    FNutColours: TStringList;
    function JsRandom: Double;
    procedure LoadMarker;
    procedure LoadAirline;
  public
    constructor Create;
    destructor Destroy; override;
    { formatters }
    function StackPercent(const AParams: TTyChartParams): string;
    function RaceRound(const AParams: TTyChartParams): string;
    function RaceFlag(const AParams: TTyChartParams): string;
    function RichWeather(const AParams: TTyChartParams): string;
    function Waterfall(const AParams: TTyChartParams): string;
    function Waterfall2(const AParams: TTyChartParams): string;
    function ExprName(const AParams: TTyChartParams): string;
    function DataThird(const AParams: TTyChartParams): string;
    function LunarTip(const AParams: TTyChartParams): string;
    function LunarDay(const AParams: TTyChartParams): string;
    function LunarName(const AParams: TTyChartParams): string;
    function CalendarPieDay(const AParams: TTyChartParams): string;
    function CalendarVerticalTip(const AParams: TTyChartParams): string;
    function CandleMarkRound(const AParams: TTyChartParams): string;
    function CandleMarkTip(const AParams: TTyChartParams): string;
    function MonthDay(const AParams: TTyChartParams): string;
    function BandTip(const AParams: TTyChartParams): string;
    function BandDate(const AParams: TTyChartParams): string;
    function BandAxis(const AParams: TTyChartParams): string;
    function BandPointer(const AParams: TTyChartParams): string;
    function DynamicTip(const AParams: TTyChartParams): string;
    function FlameTip(const AParams: TTyChartParams): string;
    function CarQuarter(const AParams: TTyChartParams): string;
    function CarNegate(const AParams: TTyChartParams): string;
    function ClockHour(const AParams: TTyChartParams): string;
    function Grade(const AParams: TTyChartParams): string;
    function GradeDetail(const AParams: TTyChartParams): string;
    function Speed(const AParams: TTyChartParams): string;
    function SvgMapTip(const AParams: TTyChartParams): string;
    function SvgGeoTip(const AParams: TTyChartParams): string;
    function BreakTime1(const AParams: TTyChartParams): string;
    function BreakTime2(const AParams: TTyChartParams): string;
    function DraggableTip(const AParams: TTyChartParams): string;
    function PenTip(const AParams: TTyChartParams): string;
    function RaceEnd(const AParams: TTyChartParams): string;
    function TouchDate(const AParams: TTyChartParams): string;
    function Confusion(const AParams: TTyChartParams): string;
    function Fixed2Third(const AParams: TTyChartParams): string;
    function RoundValue(const AParams: TTyChartParams): string;
    function MbtiTip(const AParams: TTyChartParams): string;
    function MbtiPercent(const AParams: TTyChartParams): string;
    function Periodic(const AParams: TTyChartParams): string;
    function Ml(const AParams: TTyChartParams): string;
    function Celsius(const AParams: TTyChartParams): string;
    function Thousands(const AParams: TTyChartParams): string;
    function Precipitation(const AParams: TTyChartParams): string;
    function BodyFill(const AParams: TTyChartParams): string;
    function Spirit(const AParams: TTyChartParams): string;
    function NameValueTip(const AParams: TTyChartParams): string;
    function RadarValue(const AParams: TTyChartParams): string;
    function AqiTip(const AParams: TTyChartParams): string;
    function Seconds(const AParams: TTyChartParams): string;
    function PolarPunchTip(const AParams: TTyChartParams): string;
    function PunchTip(const AParams: TTyChartParams): string;
    function WeightTip(const AParams: TTyChartParams): string;
    function SunburstRotate(const AParams: TTyChartParams): string;
    function DiskTip(const AParams: TTyChartParams): string;
    function ObamaTip0(const AParams: TTyChartParams): string;
    function ObamaTip1(const AParams: TTyChartParams): string;
    function ObamaTip2(const AParams: TTyChartParams): string;
    function ObamaLabel0(const AParams: TTyChartParams): string;
    function ObamaLabel1(const AParams: TTyChartParams): string;
    function ObamaLabel2(const AParams: TTyChartParams): string;
    function VisualTip(const AParams: TTyChartParams): string;
    function WindTip(const AParams: TTyChartParams): string;
    function WindWeatherTip(const AParams: TTyChartParams): string;
    function PolarRentTip(const AParams: TTyChartParams): string;
    { visual callbacks }
    function RaceColor(const AParams: TTyChartCallbackParams): TJSONData;
    function SqrtThird(const AParams: TTyChartCallbackParams): TJSONData;
    function Second40(const AParams: TTyChartCallbackParams): TJSONData;
    function Second60(const AParams: TTyChartCallbackParams): TJSONData;
    function Second500(const AParams: TTyChartCallbackParams): TJSONData;
    function Third10(const AParams: TTyChartCallbackParams): TJSONData;
    function SvgScatterSize(const AParams: TTyChartCallbackParams): TJSONData;
    function ThirdMax8(const AParams: TTyChartCallbackParams): TJSONData;
    function PainterSize(const AParams: TTyChartCallbackParams): TJSONData;
    function PainterColor(const AParams: TTyChartCallbackParams): TJSONData;
    function ThirdTwice(const AParams: TTyChartCallbackParams): TJSONData;
    function SecondFour(const AParams: TTyChartCallbackParams): TJSONData;
    { tooltip positions }
    function TenPercentTop(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    function SideTop10(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    function SideTop60(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    function TouchTop(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    function Quadrant(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    { label layouts }
    function PieLineEnd(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function AlignRight(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    { animation timings }
    function Delay10(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function Delay10Plus100(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function Delay5(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function Delay100(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function DelayRandom200(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function HillDelay(ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams): Double;
    function AirlineTip(const AParams: TTyChartParams): string;
    function NutrientsTip(const AParams: TTyChartParams): string;
    procedure PrepareNutrients(AOption: TJSONData);
    function UtShare(AIndex, ACount: Integer): Double;
    function UtRandom400(AIndex, ACount: Integer): Double;
    { a graphic's onclick }
    function GoBack(Sender: TObject; const AEvent: TTyChartElementEvent): Boolean;
  end;

var
  GCallbacks: TGalleryCallbacks = nil;

{ ==================== JavaScript's view of the params ==================== }

function IsUtc: Boolean;
begin
  Result := False;
end;

{ value[k] of the item as written: False where JavaScript reads undefined
  (no such element, or the value is no array) }
function Cell(const P: TTyChartCallbackParams; K: Integer; out C: TTyDataValue): Boolean;
begin
  C := Default(TTyDataValue);
  Result := (P.Raw.Shape in [rshArray, rshObject]) and (K >= 0)
    and (K <= High(P.Raw.Cells));
  if Result then C := P.Raw.Cells[K];
end;

function JsBool(B: Boolean): string;
begin
  if B then Result := 'true' else Result := 'false';
end;

{ String(x) of a cell }
function CellText(const C: TTyDataValue): string;
begin
  case C.Kind of
    dvkNumber: Result := TyJsNumberToString(C.Num);
    dvkText: Result := C.Text;
    dvkBool: Result := JsBool(C.Num <> 0);
  else
    Result := 'null';
  end;
end;

{ String(params.value[k]) }
function S(const P: TTyChartCallbackParams; K: Integer): string;
var c: TTyDataValue;
begin
  if Cell(P, K, c) then Result := CellText(c) else Result := 'undefined';
end;

{ Number(params.value[k]): undefined NaN, null 0 }
function N(const P: TTyChartCallbackParams; K: Integer): Double;
var c: TTyDataValue;
begin
  if not Cell(P, K, c) then Exit(NaN);
  case c.Kind of
    dvkNumber, dvkBool: Result := c.Num;
    dvkText: Result := TyJsToNumber(c.Text);
  else
    Result := 0;
  end;
end;

{ value[k] == null }
function IsNullish(const P: TTyChartCallbackParams; K: Integer): Boolean;
var c: TTyDataValue;
begin
  Result := not Cell(P, K, c) or (c.Kind = dvkNone);
end;

{ value[k] truthy }
function Truthy(const P: TTyChartCallbackParams; K: Integer): Boolean;
var c: TTyDataValue;
begin
  if not Cell(P, K, c) then Exit(False);
  case c.Kind of
    dvkNumber, dvkBool: Result := (c.Num <> 0) and not IsNan(c.Num);
    dvkText: Result := c.Text <> '';
  else
    Result := False;
  end;
end;

{ String(params.value): the item as written, else the number(s) the site
  handed over }
function VS(const P: TTyChartCallbackParams): string;
var i: Integer;
begin
  case P.Raw.Shape of
    rshAbsent: Exit('undefined');
    rshNull: Exit('null');
    rshNone: ;
  else
    Exit(TyRawItemText(P.Raw));
  end;
  if P.ValueText <> '' then Exit(P.ValueText);
  Result := '';
  for i := 0 to High(P.Values) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + TyJsNumberToString(P.Values[i]);
  end;
  if Length(P.Values) = 0 then Result := 'undefined';
end;

{ Number(params.value) of a single value }
function VN(const P: TTyChartCallbackParams): Double;
begin
  if P.Raw.Shape = rshScalar then
  begin
    case P.Raw.Scalar.Kind of
      dvkNumber, dvkBool: Exit(P.Raw.Scalar.Num);
      dvkText: Exit(TyJsToNumber(P.Raw.Scalar.Text));
    else
      Exit(0);
    end;
  end;
  if Length(P.Values) > 0 then Exit(P.Values[0]);
  if P.ValueText <> '' then Exit(TyJsToNumber(P.ValueText));
  Result := NaN;
end;

{ x.toFixed(d) }
function Fx(AValue: Double; ADigits: Integer): string;
begin
  Result := TyJsToFixedStr(AValue, ADigits);
end;

function NS(AValue: Double): string;
begin
  Result := TyJsNumberToString(AValue);
end;

{ echarts.format.addCommas(x) of a number }
function AddCommas(AValue: Double): string;
begin
  if IsNan(AValue) then Exit('-');
  Result := TyJsAddCommas(NS(AValue));
end;

{ echarts.format.encodeHTML }
function EncodeHtml(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&#39;', [rfReplaceAll]);
end;

{ echarts.number.parseDate of a cell: a number as milliseconds, a string as
  parseDate reads it (a bare date is local) }
function CellMs(const P: TTyChartCallbackParams; K: Integer): Double;
var c: TTyDataValue;
begin
  Result := NaN;
  if not Cell(P, K, c) then Exit;
  case c.Kind of
    dvkNumber: Result := c.Num;
    dvkText: if not TyParseDateMs(c.Text, Result) then Result := NaN;
  end;
end;

function TextMs(const AText: string): Double;
begin
  if not TyParseDateMs(AText, Result) then Result := NaN;
end;

{ one field of a date, local or UTC: the time template's own token }
function Part(AMs: Double; const AToken: string; AUTC: Boolean): Integer;
begin
  Result := StrToIntDef(TyFormatTime(AMs, '{' + AToken + '}', AUTC), 0);
end;

function Pad2(AValue: Integer): string;
begin
  Result := IntToStr(AValue);
  if Length(Result) < 2 then Result := '0' + Result;
end;

{ the old echarts.format.formatTime(tpl, value, isUTC): each token's FIRST
  occurrence replaced, in its order (MM, M, yyyy, yy, dd, d, hh, h, mm, m,
  ss, s, SSS) }
function LegacyFormatTime(const ATpl: string; AMs: Double; AUTC: Boolean): string;
var
  y, mo, d, h, mi, sec, ms: Integer;

  procedure R(const AToken, AWith: string);
  var p: Integer;
  begin
    p := Pos(AToken, Result);
    if p > 0 then
      Result := Copy(Result, 1, p - 1) + AWith + Copy(Result, p + Length(AToken), MaxInt);
  end;

begin
  Result := ATpl;
  if (Result = 'week') or (Result = 'month') or (Result = 'quarter')
    or (Result = 'half-year') or (Result = 'year') then Result := 'MM-dd'#10'yyyy';
  if IsNan(AMs) then
  begin
    { an invalid date: every getter NaN }
    R('MM', 'NaN'); R('M', 'NaN'); R('yyyy', 'NaN'); R('yy', 'NaN');
    R('dd', 'NaN'); R('d', 'NaN'); R('hh', 'NaN'); R('h', 'NaN');
    R('mm', 'NaN'); R('m', 'NaN'); R('ss', 'NaN'); R('s', 'NaN');
    R('SSS', 'NaN');
    Exit;
  end;
  y := Part(AMs, 'yyyy', AUTC);
  mo := Part(AMs, 'M', AUTC);
  d := Part(AMs, 'd', AUTC);
  h := Part(AMs, 'H', AUTC);
  mi := Part(AMs, 'm', AUTC);
  sec := Part(AMs, 's', AUTC);
  ms := Part(AMs, 'S', AUTC);
  R('MM', Pad2(mo));
  R('M', IntToStr(mo));
  R('yyyy', IntToStr(y));
  R('yy', Pad2(y mod 100));
  R('dd', Pad2(d));
  R('d', IntToStr(d));
  R('hh', Pad2(h));
  R('h', IntToStr(h));
  R('mm', Pad2(mi));
  R('m', IntToStr(mi));
  R('ss', Pad2(sec));
  R('s', IntToStr(sec));
  if ms < 10 then R('SSS', '00' + IntToStr(ms))
  else if ms < 100 then R('SSS', '0' + IntToStr(ms))
  else R('SSS', IntToStr(ms));
end;

function P0(const AParams: TTyChartParams): TTyChartCallbackParams;
begin
  if Length(AParams) > 0 then Result := AParams[0] else Result := TyChartBlankParams;
end;

function NumJson(AValue: Double): TJSONData;
begin
  Result := TJSONFloatNumber.Create(AValue);
end;

{ ==================== the class ==================== }

constructor TGalleryCallbacks.Create;
begin
  inherited Create;
  FRandom := 2463534242;
end;

destructor TGalleryCallbacks.Destroy;
begin
  FMarkerRoot.Free;
  FAirRoot.Free;
  FNutColours.Free;
  inherited Destroy;
end;

function TGalleryCallbacks.JsRandom: Double;
var x: LongWord;
begin
  x := FRandom;
  x := x xor (x shl 13);
  x := x xor (x shr 17);
  x := x xor (x shl 5);
  FRandom := x;
  Result := x / 4294967296;
end;

{ ---- the stacks, the races ---- }

{ bar-stack-normalization(-and-variation), every series:
  Math.round(params.value * 1000) / 10 + '%' }
function TGalleryCallbacks.StackPercent(const AParams: TTyChartParams): string;
begin
  Result := NS(TyJsRound(VN(P0(AParams)) * 1000) / 10) + '%';
end;

{ bar-race-country, the value axis: Math.round(n) + '' }
function TGalleryCallbacks.RaceRound(const AParams: TTyChartParams): string;
begin
  Result := NS(TyJsRound(VN(P0(AParams))));
end;

{ bar-race-country, the country axis: value + '{flag|' + getFlag(value) +
  '}'. getFlag looks the country up in an emoji table the page fetches from
  a CDN; the demo has no copy of it, so the flag is left empty (the page
  run on the harvest's empty table would print 'undefined'). }
function TGalleryCallbacks.RaceFlag(const AParams: TTyChartParams): string;
var v: string;
begin
  v := VS(P0(AParams));
  Result := v + '{flag|}';
end;

{ bar-race-country: countryColors[param.value[3]] || '#5470c6' }
function TGalleryCallbacks.RaceColor(const AParams: TTyChartCallbackParams): TJSONData;
const
  cCountries: array[0..18] of string = ('Australia', 'Canada', 'China', 'Cuba',
    'Finland', 'France', 'Germany', 'Iceland', 'India', 'Japan', 'North Korea',
    'South Korea', 'New Zealand', 'Norway', 'Poland', 'Russia', 'Turkey',
    'United Kingdom', 'United States');
  cColors: array[0..18] of string = ('#00008b', '#f00', '#ffde00', '#002a8f',
    '#003580', '#ed2939', '#000', '#003897', '#f93', '#bc002d', '#024fa2',
    '#000', '#00247d', '#ef2b2d', '#dc143c', '#d52b1e', '#e30a17', '#00247d',
    '#b22234');
var
  k: string;
  i: Integer;
begin
  k := S(AParams, 3);
  for i := 0 to High(cCountries) do
    if cCountries[i] = k then Exit(TJSONString.Create(cColors[i]));
  Result := TJSONString.Create('#5470c6');
end;

{ bar-rich-text: '{' + value + '| }\n{value|' + value + '}' }
function TGalleryCallbacks.RichWeather(const AParams: TTyChartParams): string;
var v: string;
begin
  v := VS(P0(AParams));
  Result := '{' + v + '| }'#10'{value|' + v + '}';
end;

{ bar-waterfall: params[1].name + '<br/>' + params[1].seriesName + ' : ' +
  params[1].value }
function TGalleryCallbacks.Waterfall(const AParams: TTyChartParams): string;
begin
  if Length(AParams) < 2 then Exit('');
  Result := AParams[1].Name + '<br/>' + AParams[1].SeriesName + ' : ' + VS(AParams[1]);
end;

{ bar-waterfall2: params[1] unless its value is '-', else params[2] }
function TGalleryCallbacks.Waterfall2(const AParams: TTyChartParams): string;
var t: Integer;
begin
  if (Length(AParams) > 1) and (VS(AParams[1]) <> '-') then t := 1 else t := 2;
  if t > High(AParams) then Exit('');
  Result := AParams[t].Name + '<br/>' + AParams[t].SeriesName + ' : ' + VS(AParams[t]);
end;

{ boxplot-light-velocity2's transform: 'expr ' + params.value }
function TGalleryCallbacks.ExprName(const AParams: TTyChartParams): string;
begin
  Result := 'expr ' + VS(P0(AParams));
end;

{ bubble-gradient's emphasis label, scatter-label-align-*, matrix-graph:
  param.data[3] }
function TGalleryCallbacks.DataThird(const AParams: TTyChartParams): string;
begin
  Result := S(P0(AParams), 3);
end;

{ bubble-gradient, scatter-label-align-*: Math.sqrt(data[2]) / 5e2 }
function TGalleryCallbacks.SqrtThird(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Result := NumJson(Sqrt(N(AParams, 2)) / 5e2);
end;

{ ---- calendars ---- }

function TGalleryCallbacks.Second40(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Result := NumJson(N(AParams, 1) / 40);
end;

function TGalleryCallbacks.Second60(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Result := NumJson(N(AParams, 1) / 60);
end;

function TGalleryCallbacks.Second500(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Result := NumJson(N(AParams, 1) / 500);
end;

{ calendar-lunar's tooltip: rainfall: value[1].toFixed(2) }
function TGalleryCallbacks.LunarTip(const AParams: TTyChartParams): string;
begin
  { U+964D U+96E8 U+91CF: rainfall }
  Result := #$E9#$99#$8D#$E9#$9B#$A8#$E9#$87#$8F': ' + Fx(N(P0(AParams), 1), 2);
end;

{ calendar-lunar: parseDate(value[0]).getDate() + '\n\n' + value[2] +
  '\n\n' }
function TGalleryCallbacks.LunarDay(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams; ms: Double;
begin
  p := P0(AParams);
  ms := CellMs(p, 0);
  if IsNan(ms) then Result := 'NaN' else Result := IntToStr(Part(ms, 'd', IsUtc));
  Result := Result + #10#10 + S(p, 2) + #10#10;
end;

{ calendar-lunar: '\n\n\n' + (value[3] || '') }
function TGalleryCallbacks.LunarName(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  Result := #10#10#10;
  if Truthy(p, 3) then Result := Result + S(p, 3);
end;

{ calendar-pie: echarts.time.format(value[0], '{dd}', false) }
function TGalleryCallbacks.CalendarPieDay(const AParams: TTyChartParams): string;
begin
  Result := TyFormatTime(CellMs(P0(AParams), 0), '{dd}', False);
end;

{ calendar-vertical's tooltip }
function TGalleryCallbacks.CalendarVerticalTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  Result := TyFormatTime(CellMs(p, 0), '{yyyy}-{MM}-{dd}', False) + ': ' + S(p, 1);
end;

{ ---- candlesticks ---- }

{ candlestick-sh's marker label: param != null ? Math.round(param.value) + ''
  : '' }
function TGalleryCallbacks.CandleMarkRound(const AParams: TTyChartParams): string;
begin
  if Length(AParams) = 0 then Exit('');
  Result := NS(TyJsRound(VN(AParams[0])));
end;

{ candlestick-sh's marker tooltip: param.name + '<br>' + (param.data.coord
  || ''). The coord is the page's own literal on its first marker, which the
  params do not carry: read from there. }
function TGalleryCallbacks.CandleMarkTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  Result := p.Name + '<br>';
  if p.DataIndex = 0 then Result := Result + '2013/5/31,2300';
end;

{ candlestick-touch's date axis: echarts.format.formatTime('MM-dd', value) }
function TGalleryCallbacks.MonthDay(const AParams: TTyChartParams): string;
begin
  Result := LegacyFormatTime('MM-dd', TextMs(VS(P0(AParams))), False);
end;

{ ---- confidence-band: base is -Math.floor(min of the lows), 3 ---- }

const
  cBandBase = 3;

function TGalleryCallbacks.BandTip(const AParams: TTyChartParams): string;
begin
  if Length(AParams) < 3 then Exit('');
  Result := AParams[2].Name + '<br />' + Fx((VN(AParams[2]) - cBandBase) * 100, 1) + '%';
end;

{ idx === 0 ? value : [date.getMonth() + 1, date.getDate()].join('-') of
  new Date(value) -- a bare ISO date is UTC to the Date constructor }
function TGalleryCallbacks.BandDate(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams; ms: Double;
begin
  p := P0(AParams);
  if p.DataIndex = 0 then Exit(VS(p));
  if not TyParseDateMs(VS(p), ms, True) then Exit('NaN-NaN');
  Result := IntToStr(Part(ms, 'M', False)) + '-' + IntToStr(Part(ms, 'd', False));
end;

{ (val - base) * 100 + '%' }
function TGalleryCallbacks.BandAxis(const AParams: TTyChartParams): string;
begin
  Result := NS((VN(P0(AParams)) - cBandBase) * 100) + '%';
end;

{ the pointer's: ((params.value - base) * 100).toFixed(1) + '%' }
function TGalleryCallbacks.BandPointer(const AParams: TTyChartParams): string;
begin
  Result := Fx((VN(P0(AParams)) - cBandBase) * 100, 1) + '%';
end;

{ dynamic-data2's tooltip: the date of new Date(params.name) -- the name is
  a Date's toString(), 'Sat Oct 04 1997 00:00:00 GMT+0000 (...)' -- as
  d/m/yyyy, then ' : ' + value[1] }
function TGalleryCallbacks.DynamicTip(const AParams: TTyChartParams): string;
const
  cMonths: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  p: TTyChartCallbackParams;
  parts: TStringArray;
  m, k, sign, off: Integer;
  ms: Double;
  t: string;
begin
  p := P0(AParams);
  parts := p.Name.Split([' ']);
  ms := NaN;
  m := 0;
  if Length(parts) >= 6 then
    for k := 1 to 12 do
      if cMonths[k] = parts[1] then m := k;
  if (m > 0) and TyParseDateMs(parts[3] + '-' + Pad2(m) + '-' + parts[2] + 'T'
    + parts[4] + 'Z', ms, True) then
  begin
    { the zone written after GMT }
    t := Copy(parts[5], 4, MaxInt);
    if Length(t) = 5 then
    begin
      if t[1] = '-' then sign := -1 else sign := 1;
      off := StrToIntDef(Copy(t, 2, 2), 0) * 60 + StrToIntDef(Copy(t, 4, 2), 0);
      ms := ms - sign * off * 60000.0;
    end;
  end;
  if IsNan(ms) then t := 'NaN/NaN/NaN'
  else
    t := IntToStr(Part(ms, 'd', False)) + '/' + IntToStr(Part(ms, 'M', False))
      + '/' + IntToStr(Part(ms, 'yyyy', False));
  Result := t + ' : ' + S(p, 1);
end;

{ flame-graph's tooltip: `${params.marker} ${value[3]}: (${addCommas(samples)}
  samples, ${+value[4].toFixed(2)}%)` -- the marker the box draws as a dot
  (richText's '{name|}', params.Marker) }
function TGalleryCallbacks.FlameTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams; samples: Double;
begin
  p := P0(AParams);
  samples := N(p, 2) - N(p, 1);
  Result := p.Marker + ' ' + S(p, 3) + ': (' + AddCommas(samples) + ' samples, '
    + NS(TyJsToNumber(Fx(N(p, 4), 2))) + '%)';
end;

{ ---- gauges ---- }

function TGalleryCallbacks.CarQuarter(const AParams: TTyChartParams): string;
var v: Double;
begin
  v := VN(P0(AParams));
  if v = 0.5 then Exit('2/4');
  if v = 1 then Exit('4/4');
  Result := NS(v);
end;

function TGalleryCallbacks.CarNegate(const AParams: TTyChartParams): string;
begin
  Result := NS(-VN(P0(AParams)));
end;

function TGalleryCallbacks.ClockHour(const AParams: TTyChartParams): string;
var v: Double;
begin
  v := VN(P0(AParams));
  if v = 0 then Exit('');
  Result := NS(v);
end;

function TGalleryCallbacks.Grade(const AParams: TTyChartParams): string;
var v: Double;
begin
  v := VN(P0(AParams));
  if v = 0.875 then Exit('Grade A');
  if v = 0.625 then Exit('Grade B');
  if v = 0.375 then Exit('Grade C');
  if v = 0.125 then Exit('Grade D');
  Result := '';
end;

function TGalleryCallbacks.GradeDetail(const AParams: TTyChartParams): string;
begin
  Result := NS(TyJsRound(VN(P0(AParams)) * 100));
end;

function TGalleryCallbacks.Speed(const AParams: TTyChartParams): string;
begin
  Result := '{value|' + Fx(VN(P0(AParams)), 0) + '}{unit|km/h}';
end;

{ ---- geo-svg-map ---- }

function TGalleryCallbacks.SvgMapTip(const AParams: TTyChartParams): string;
begin
  Result := P0(AParams).Name + ':<br>xxxxxxxxxxxxxxxx<br>xxxxxxxxxxxxxxxx<br>xxxxxxxxxxxxxxxx';
end;

function TGalleryCallbacks.SvgGeoTip(const AParams: TTyChartParams): string;
var i: Integer;
begin
  Result := 'This is the introduction:';
  for i := 1 to 10 do Result := Result + '<br>xxxxxxxxxxxxxxxxxxxxx';
end;

{ geo-svg-scatter-simple: (params[2] / 100) * 15 + 5 }
function TGalleryCallbacks.SvgScatterSize(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Result := NumJson((N(AParams, 2) / 100) * 15 + 5);
end;

{ effectScatter-map, effectScatter-bmap: val[2] / 10 }
function TGalleryCallbacks.Third10(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Result := NumJson(N(AParams, 2) / 10);
end;

{ scatter-map-brush: Math.max(val[2] / 10, 8) }
function TGalleryCallbacks.ThirdMax8(const AParams: TTyChartCallbackParams): TJSONData;
var v: Double;
begin
  v := N(AParams, 2) / 10;
  if IsNan(v) then Exit(NumJson(NaN));
  Result := NumJson(Math.Max(v, Double(8)));
end;

{ ---- intraday breaks: echarts.time.format at UTC ---- }

{ intraday-breaks-1: formatter(timestamp, _, opt) }
function TGalleryCallbacks.BreakTime1(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  if p.BreakType <> '' then
    Result := TyFormatTime(VN(p), '{HH}:{mm}'#10'{weak|{dd}d}', True)
  else
    Result := TyFormatTime(VN(p), '{HH}:{mm}', True);
end;

{ intraday-breaks-2: (value, index, extra) }
function TGalleryCallbacks.BreakTime2(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  if p.BreakType = '' then Exit(TyFormatTime(VN(p), '{HH}:{mm}', True));
  if p.BreakType = 'start' then
    Exit(TyFormatTime(p.BreakStart, '{HH}:{mm}', True) + '/'
      + TyFormatTime(p.BreakEnd, '{HH}:{mm}', True));
  Result := '';
end;

{ ---- lines ---- }

function TGalleryCallbacks.DraggableTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  Result := 'X: ' + Fx(N(p, 0), 2) + '<br>Y: ' + Fx(N(p, 1), 2);
end;

{ line-pen: data = params.data || [0, 0] }
function TGalleryCallbacks.PenTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  if p.Raw.Shape in [rshArray, rshObject] then
    Result := Fx(N(p, 0), 2) + ', ' + Fx(N(p, 1), 2)
  else
    Result := '0.00, 0.00';
end;

{ line-race's end labels: value[3] + ': ' + value[0] }
function TGalleryCallbacks.RaceEnd(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  Result := S(p, 3) + ': ' + S(p, 0);
end;

{ line-tooltip-touch's pointer: formatTime('yyyy-MM-dd', params.value) }
function TGalleryCallbacks.TouchDate(const AParams: TTyChartParams): string;
begin
  Result := LegacyFormatTime('yyyy-MM-dd', VN(P0(AParams)), False);
end;

{ ---- matrices ---- }

{ matrix-confusion: '{name|' + (v0 === v1 ? 'True ' : 'False ') + v1 +
  '}\n{value|' + value[2] + '}' }
function TGalleryCallbacks.Confusion(const AParams: TTyChartParams): string;
var
  p: TTyChartCallbackParams;
  a, b: TTyDataValue;
  same: Boolean;
begin
  p := P0(AParams);
  same := Cell(p, 0, a) = Cell(p, 1, b);
  if same and (a.Kind = b.Kind) then
    case a.Kind of
      dvkNumber, dvkBool: same := a.Num = b.Num;
      dvkText: same := a.Text = b.Text;
    end
  else
    same := same and (a.Kind = b.Kind);
  if same then Result := '{name|True ' else Result := '{name|False ';
  Result := Result + S(p, 1) + '}'#10'{value|' + S(p, 2) + '}';
end;

{ matrix-correlation-*: params.value[2].toFixed(2) }
function TGalleryCallbacks.Fixed2Third(const AParams: TTyChartParams): string;
begin
  Result := Fx(N(P0(AParams), 2), 2);
end;

{ matrix-covariance's value formatter: Math.round(value) -- the value a
  value formatter is handed is the cell's (ValueText) }
function TGalleryCallbacks.RoundValue(const AParams: TTyChartParams): string;
begin
  Result := NS(TyJsRound(TyJsToNumber(P0(AParams).ValueText)));
end;

{ matrix-mbti: getColor(mbti) }
function MbtiColor(const AMbti: string): string;
begin
  if Pos('NF', AMbti) > 0 then Exit('#2D9A69');
  if Pos('NT', AMbti) > 0 then Exit('#7D568F');
  if (Pos('S', AMbti) > 0) and (Pos('J', AMbti) > 0) then Exit('#3A8DAB');
  if (Pos('S', AMbti) > 0) and (Pos('P', AMbti) > 0) then Exit('#E0A433');
  Result := 'undefined';
end;

function TGalleryCallbacks.MbtiTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  Result := '<span style="color:' + MbtiColor(S(p, 1)) + ';font-weight:bold">'
    + S(p, 1) + '</span> /'#10'                            <span style="color:'
    + MbtiColor(S(p, 0)) + ';font-weight:bold">' + S(p, 0) + '</span> :'#10
    + '                            ' + NS(TyJsRound(N(p, 2) * 100)) + '%';
end;

function TGalleryCallbacks.MbtiPercent(const AParams: TTyChartParams): string;
begin
  Result := NS(TyJsRound(N(P0(AParams), 2) * 100)) + '%';
end;

{ matrix-periodic-table: value[2] == null ? '{small|' + value[3] + '}' :
  value[2] + '\n' + value[3] }
function TGalleryCallbacks.Periodic(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  if IsNullish(p, 2) then Exit('{small|' + S(p, 3) + '}');
  Result := S(p, 2) + #10 + S(p, 3);
end;

{ ---- the rest of the formatters ---- }

{ mix-line-bar's value formatters }
function TGalleryCallbacks.Ml(const AParams: TTyChartParams): string;
begin
  Result := P0(AParams).ValueText + ' ml';
end;

function TGalleryCallbacks.Celsius(const AParams: TTyChartParams): string;
begin
  Result := P0(AParams).ValueText + ' ' + cDegree + 'C';
end;

{ mix-zoom-on-value: isFinite(+a) ? addCommas(+a / 1000) : '' }
function TGalleryCallbacks.Thousands(const AParams: TTyChartParams): string;
var a: Double;
begin
  a := VN(P0(AParams));
  if IsNan(a) or IsInfinite(a) then Exit('');
  Result := AddCommas(a / 1000);
end;

{ multiple-x-axis's pointers: 'Precipitation  ' + params.value +
  (params.seriesData.length ? fullwidth colon + seriesData[0].data : '') }
function TGalleryCallbacks.Precipitation(const AParams: TTyChartParams): string;
begin
  Result := 'Precipitation  ' + VS(P0(AParams));
  if Length(AParams) > 1 then Result := Result + cColonW + VS(AParams[1]);
end;

{ pictorialBar-body-fill: ((param.value / bodyMax) * 100).toFixed(0) + '%',
  bodyMax 150 }
function TGalleryCallbacks.BodyFill(const AParams: TTyChartParams): string;
begin
  Result := Fx((VN(P0(AParams)) / 150) * 100, 0) + '%';
end;

{ pictorialBar-spirit: ((params.value / maxData) * 100).toFixed(1) + ' %',
  maxData 2000 }
function TGalleryCallbacks.Spirit(const AParams: TTyChartParams): string;
begin
  Result := Fx((VN(P0(AParams)) / 2000) * 100, 1) + ' %';
end;

{ pictorialBar-velocity: params[0].name + ': ' + params[0].value }
function TGalleryCallbacks.NameValueTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  Result := p.Name + ': ' + VS(p);
end;

{ radar-custom's label: params.value -- a radar label's params hold the
  one indicator's value (getFormattedLabel's labelDimIndex) }
function TGalleryCallbacks.RadarValue(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  if Length(p.Values) > 0 then Result := NS(p.Values[0]) else Result := VS(p);
end;

{ scatter-aqi-color's tooltip, the page's schema texts }
function TGalleryCallbacks.AqiTip(const AParams: TTyChartParams): string;
const
  { AQI index; PM2.5; PM10; carbon monoxide (CO); nitrogen dioxide (NO2);
    sulphur dioxide (SO2) }
  cText: array[1..6] of string = ('AQI'#$E6#$8C#$87#$E6#$95#$B0, 'PM2.5', 'PM10',
    #$E4#$B8#$80#$E6#$B0#$A7#$E5#$8C#$96#$E7#$A2#$B3#$EF#$BC#$88'CO'#$EF#$BC#$89,
    #$E4#$BA#$8C#$E6#$B0#$A7#$E5#$8C#$96#$E6#$B0#$AE#$EF#$BC#$88'NO2'#$EF#$BC#$89,
    #$E4#$BA#$8C#$E6#$B0#$A7#$E5#$8C#$96#$E7#$A1#$AB#$EF#$BC#$88'SO2'#$EF#$BC#$89);
var
  p: TTyChartCallbackParams;
  i: Integer;
begin
  p := P0(AParams);
  { value[0] + day + colon }
  Result := '<div style="border-bottom: 1px solid rgba(255,255,255,.3); '
    + 'font-size: 18px;padding-bottom: 7px;margin-bottom: 7px">'
    + p.SeriesName + ' ' + S(p, 0) + #$E6#$97#$A5 + cColonW + S(p, 7) + '</div>';
  for i := 1 to 6 do
    Result := Result + cText[i] + cColonW + S(p, i) + '<br>';
end;

{ scatter-painter-choice's axis: val + 's' }
function TGalleryCallbacks.Seconds(const AParams: TTyChartParams): string;
begin
  Result := VS(P0(AParams)) + 's';
end;

{ data/scatter-painter-choice-marker.json: json[0].marker's size, color and
  sizeref, as the page's data file has them }
procedure TGalleryCallbacks.LoadMarker;
var
  sl: TStringList;
  d: TJSONData;
begin
  if FMarkerLoaded then Exit;
  FMarkerLoaded := True;
  if not FileExists(GalleryDataDir + 'scatter-painter-choice-marker.json') then Exit;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(GalleryDataDir + 'scatter-painter-choice-marker.json');
    FMarkerRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  if not (FMarkerRoot is TJSONObject) then Exit;
  d := TJSONObject(FMarkerRoot).Find('size');
  if d is TJSONArray then FMarkerSize := TJSONArray(d);
  d := TJSONObject(FMarkerRoot).Find('color');
  if d is TJSONArray then FMarkerColor := TJSONArray(d);
  FMarkerRef := TJSONObject(FMarkerRoot).Get('sizeref', NaN);
end;

{ [R2-J3] data/lines-airline-tables.json.gz, what the harvest carried
  out of flights.json: airports[i] the airport's name (data.airports[i][1]),
  routes[i] the route's two airports (data.routes[i][1] and [2]) }
procedure TGalleryCallbacks.LoadAirline;
var
  text: string;
  d: TJSONData;
begin
  if FAirLoaded then Exit;
  FAirLoaded := True;
  text := GalleryReadGz(GalleryDataDir + 'lines-airline-tables.json.gz');
  if text = '' then Exit;
  FAirRoot := GetJSON(text);
  if not (FAirRoot is TJSONObject) then Exit;
  d := TJSONObject(FAirRoot).Find('airports');
  if d is TJSONArray then FAirports := TJSONArray(d);
  d := TJSONObject(FAirRoot).Find('routes');
  if d is TJSONArray then FRoutes := TJSONArray(d);
end;

{ lines-airline's tooltip: var route = data.routes[param.dataIndex];
  data.airports[route[1]][1] + ' > ' + data.airports[route[2]][1] }
function TGalleryCallbacks.AirlineTip(const AParams: TTyChartParams): string;
var
  p: TTyChartCallbackParams;
  k, a, b: Integer;
  route: TJSONArray;

  function NameOf(AIdx: Integer): string;
  begin
    if (AIdx >= 0) and (AIdx < FAirports.Count) and (FAirports.Items[AIdx].JSONType = jtString) then
      Result := FAirports.Strings[AIdx]
    else
      Result := 'undefined';
  end;

begin
  Result := '';
  LoadAirline;
  if (FRoutes = nil) or (FAirports = nil) then Exit;
  p := P0(AParams);
  k := p.RawDataIndex;
  if k < 0 then k := p.DataIndex;
  if (k < 0) or (k >= FRoutes.Count) or not (FRoutes.Items[k] is TJSONArray) then Exit;
  route := TJSONArray(FRoutes.Items[k]);
  a := route.Integers[0];
  b := route.Integers[1];
  Result := NameOf(a) + ' > ' + NameOf(b);
end;

{ [R2-J3] scatter-nutrients-matrix's colorBySchema, as its makeAxis fills it
  while getOption builds the axes: every x and then every y axis, its name
  to its axisLine.lineStyle.color (axisColors of its own id) -- a later axis
  of the same name over an earlier one }
procedure TGalleryCallbacks.PrepareNutrients(AOption: TJSONData);
const
  cKeys: array[0..1] of string = ('xAxis', 'yAxis');
var
  k, i, at: Integer;
  axes, d: TJSONData;
  nm, col: string;
begin
  if FNutColours = nil then
  begin
    FNutColours := TStringList.Create;
    FNutColours.CaseSensitive := True;
  end;
  FNutColours.Clear;
  if not (AOption is TJSONObject) then Exit;
  for k := 0 to 1 do
  begin
    axes := TJSONObject(AOption).Find(cKeys[k]);
    if not (axes is TJSONArray) then Continue;
    for i := 0 to axes.Count - 1 do
    begin
      if not (TJSONArray(axes).Items[i] is TJSONObject) then Continue;
      d := TJSONObject(TJSONArray(axes).Items[i]).Find('name');
      if (d = nil) or (d.JSONType <> jtString) then Continue;
      nm := d.AsString;
      col := 'undefined';
      d := TJSONObject(TJSONArray(axes).Items[i]).FindPath('axisLine.lineStyle.color');
      if (d <> nil) and (d.JSONType = jtString) then col := d.AsString;
      at := FNutColours.IndexOfName(nm);
      if at >= 0 then FNutColours.ValueFromIndex[at] := col
      else FNutColours.Add(nm + '=' + col);
    end;
  end;
end;

{ An object's keys in JavaScript's order: the array indices ('0', '12' --
  canonical, below 2^32 - 1) ascending, then the rest as they were added }
procedure JsKeyOrder(AKeys: TStrings; AOut: TStrings);
var
  i, j: Integer;
  n: Int64;
  idx: TStringList;

  function IsIndex(const S: string; out V: Int64): Boolean;
  begin
    Result := (S <> '') and (Length(S) <= 10) and ((S = '0') or (S[1] in ['1'..'9']))
      and TryStrToInt64(S, V) and (IntToStr(V) = S) and (V < 4294967295);
  end;

begin
  AOut.Clear;
  idx := TStringList.Create;
  try
    for i := 0 to AKeys.Count - 1 do
      if IsIndex(AKeys[i], n) then idx.AddObject(Format('%.10d', [n]), TObject(PtrInt(i)));
    idx.Sort;
    for j := 0 to idx.Count - 1 do AOut.Add(AKeys[PtrInt(idx.Objects[j])]);
    for i := 0 to AKeys.Count - 1 do
      if not IsIndex(AKeys[i], n) then AOut.Add(AKeys[i]);
  finally
    idx.Free;
  end;
end;

{ scatter-nutrients-matrix's tooltipFormatter: the points the pointer's
  axes found, one entry per data name (data[3]) holding its two fields
  (data[4]: data[0], data[5]: data[1]), filed by the axis that found it --
  'xy' when both did -- then three blocks, CROSS, V LINE, H LINE, each a
  div per name with a coloured line per field (colorBySchema) }
function TGalleryCallbacks.NutrientsTip(const AParams: TTyChartParams): string;
var
  names: TStringList;
  items: array of TStringList;
  onDim: array[0..2] of TStringList;  // xy, x, y: name -> item index
  i, j, k, d, at: Integer;
  p: TTyChartCallbackParams;
  nm, key, html, part, vals: string;
  ordered, keys, fields, forder: TStringList;
  cDim: array[0..2] of string;
  cTitle: array[0..2] of string;

  function ItemOf(const AName: string): Integer;
  var q: Integer;
  begin
    q := names.IndexOf(AName);
    if q < 0 then
    begin
      q := names.Add(AName);
      SetLength(items, names.Count);
      items[q] := TStringList.Create;
      items[q].CaseSensitive := True;
    end;
    Result := q;
  end;

  procedure SetField(AItem: Integer; const AKey, AValue: string);
  var q: Integer;
  begin
    q := items[AItem].IndexOfName(AKey);
    if q >= 0 then items[AItem].ValueFromIndex[q] := AValue
    else items[AItem].Add(AKey + '=' + AValue);
  end;

  procedure Put(ADim: Integer; const AName: string; AItem: Integer);
  var q: Integer;
  begin
    q := onDim[ADim].IndexOfName(AName);
    if q >= 0 then onDim[ADim].ValueFromIndex[q] := IntToStr(AItem)
    else onDim[ADim].Add(AName + '=' + IntToStr(AItem));
  end;

  function NamesOf(ADim: Integer): TStringList;
  var q: Integer;
  begin
    Result := TStringList.Create;
    for q := 0 to onDim[ADim].Count - 1 do Result.Add(onDim[ADim].Names[q]);
  end;

  function Colour(const AField: string): string;
  var q: Integer;
  begin
    Result := 'undefined';
    if FNutColours = nil then Exit;
    q := FNutColours.IndexOfName(AField);
    if q >= 0 then Result := FNutColours.ValueFromIndex[q];
  end;

begin
  Result := '';
  cDim[0] := 'xy'; cDim[1] := 'x'; cDim[2] := 'y';
  cTitle[0] := 'CROSS'; cTitle[1] := 'V LINE'; cTitle[2] := 'H LINE';
  names := TStringList.Create;
  names.CaseSensitive := True;
  for d := 0 to 2 do
  begin
    onDim[d] := TStringList.Create;
    onDim[d].CaseSensitive := True;
  end;
  ordered := TStringList.Create;
  keys := TStringList.Create;
  fields := TStringList.Create;
  forder := TStringList.Create;
  try
    for i := 0 to High(AParams) do
    begin
      p := AParams[i];
      nm := S(p, 3);
      at := ItemOf(nm);
      SetField(at, S(p, 4), S(p, 0));
      SetField(at, S(p, 5), S(p, 1));
      if p.AxisDimension = 'x' then Put(1, nm, at)
      else if p.AxisDimension = 'y' then Put(2, nm, at);
    end;
    { a name both axes found goes to xy, in mapByDataName's key order }
    JsKeyOrder(names, ordered);
    for i := 0 to ordered.Count - 1 do
    begin
      nm := ordered[i];
      if (onDim[1].IndexOfName(nm) >= 0) and (onDim[2].IndexOfName(nm) >= 0) then
      begin
        Put(0, nm, names.IndexOf(nm));
        onDim[1].Delete(onDim[1].IndexOfName(nm));
        onDim[2].Delete(onDim[2].IndexOfName(nm));
      end;
    end;
    for d := 0 to 2 do
    begin
      html := '';
      keys.Free;
      keys := NamesOf(d);
      JsKeyOrder(keys, ordered);
      for j := 0 to ordered.Count - 1 do
      begin
        nm := ordered[j];
        at := StrToInt(onDim[d].Values[nm]);
        vals := '';
        fields.Clear;
        for k := 0 to items[at].Count - 1 do fields.Add(items[at].Names[k]);
        JsKeyOrder(fields, forder);
        for k := 0 to forder.Count - 1 do
        begin
          key := forder[k];
          part := '<span style="color:' + Colour(key) + '">' + key + '</span>: '
            + items[at].Values[key];
          if vals <> '' then vals := vals + '<br/>';
          vals := vals + part;
        end;
        html := html + '<div style="margin: 10px 0">' + nm + '<br/>' + vals + '</div>';
      end;
      if html <> '' then
        Result := Result + '<div style="margin: 10px 0">'
          + '<div style="font-size: 16px; color: #aaa">POINTS ON ' + cTitle[d]
          + '</div>' + html + '</div>';
    end;
  finally
    forder.Free;
    fields.Free;
    keys.Free;
    ordered.Free;
    for d := 0 to 2 do onDim[d].Free;
    for i := 0 to High(items) do items[i].Free;
    names.Free;
  end;
end;

{ json[0].marker.size[param.dataIndex] / json[0].marker.sizeref }
function TGalleryCallbacks.PainterSize(const AParams: TTyChartCallbackParams): TJSONData;
begin
  LoadMarker;
  if (FMarkerSize = nil) or (AParams.DataIndex < 0)
    or (AParams.DataIndex >= FMarkerSize.Count) then Exit(NumJson(NaN));
  Result := NumJson(FMarkerSize.Floats[AParams.DataIndex] / FMarkerRef);
end;

{ json[0].marker.color[param.dataIndex] }
function TGalleryCallbacks.PainterColor(const AParams: TTyChartCallbackParams): TJSONData;
begin
  LoadMarker;
  if (FMarkerColor = nil) or (AParams.DataIndex < 0)
    or (AParams.DataIndex >= FMarkerColor.Count) then Exit(nil);
  Result := TJSONString.Create(FMarkerColor.Strings[AParams.DataIndex]);
end;

const
  cHours: array[0..23] of string = ('12a', '1a', '2a', '3a', '4a', '5a', '6a',
    '7a', '8a', '9a', '10a', '11a', '12p', '1p', '2p', '3p', '4p', '5p', '6p',
    '7p', '8p', '9p', '10p', '11p');
  cDays: array[0..6] of string = ('Saturday', 'Friday', 'Thursday',
    'Wednesday', 'Tuesday', 'Monday', 'Sunday');

{ hours[x] / days[x]: an index the tables do not have is undefined }
function Hour(AIndex: Double): string;
begin
  if (AIndex >= 0) and (AIndex <= 23) and (Frac(AIndex) = 0) then
    Result := cHours[Trunc(AIndex)]
  else
    Result := 'undefined';
end;

function Day(AIndex: Double): string;
begin
  if (AIndex >= 0) and (AIndex <= 6) and (Frac(AIndex) = 0) then
    Result := cDays[Trunc(AIndex)]
  else
    Result := 'undefined';
end;

{ scatter-polar-punchCard: value[2] + ' commits in ' + hours[value[1]] +
  ' of ' + days[value[0]] }
function TGalleryCallbacks.PolarPunchTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  Result := S(p, 2) + ' commits in ' + Hour(N(p, 1)) + ' of ' + Day(N(p, 0));
end;

{ scatter-punchCard: the same, x and y the other way round }
function TGalleryCallbacks.PunchTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  Result := S(p, 2) + ' commits in ' + Hour(N(p, 0)) + ' of ' + Day(N(p, 1));
end;

{ the punch cards: val[2] * 2 }
function TGalleryCallbacks.ThirdTwice(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Result := NumJson(N(AParams, 2) * 2);
end;

{ scatter-single-axis: dataItem[1] * 4 }
function TGalleryCallbacks.SecondFour(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Result := NumJson(N(AParams, 1) * 4);
end;

{ scatter-weight's tooltip: an array value, cm and kg; else the name }
function TGalleryCallbacks.WeightTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  if (p.Raw.Shape in [rshArray, rshObject]) and (Length(p.Raw.Cells) > 1) then
    Result := p.SeriesName + ' :<br/>' + S(p, 0) + 'cm ' + S(p, 1) + 'kg '
  else
    Result := p.SeriesName + ' :<br/>' + p.Name + ' : ' + VS(p) + 'kg ';
end;

{ the entries of a treePathInfo (JSON text): their names, in order }
function TreePathNames(const AJson: string): TStringArray;
var
  d: TJSONData;
  i: Integer;
begin
  Result := nil;
  if AJson = '' then Exit;
  d := GetJSON(AJson);
  try
    if not (d is TJSONArray) then Exit;
    SetLength(Result, TJSONArray(d).Count);
    for i := 0 to TJSONArray(d).Count - 1 do
      if TJSONArray(d).Items[i] is TJSONObject then
        Result[i] := TJSONObject(TJSONArray(d).Items[i]).Get('name', '');
  finally
    d.Free;
  end;
end;

{ sunburst-label-rotate: by param.treePathInfo.length }
function TGalleryCallbacks.SunburstRotate(const AParams: TTyChartParams): string;
var depth: Integer;
begin
  depth := Length(TreePathNames(P0(AParams).TreePathInfo));
  case depth of
    2: Result := 'radial';
    3: Result := 'tangential';
    4: Result := '0';
  else
    Result := '';
  end;
end;

{ treemap-disk, treemap-show-parent: the path below the root, encoded, and
  the size }
function TGalleryCallbacks.DiskTip(const AParams: TTyChartParams): string;
var
  p: TTyChartCallbackParams;
  names: TStringArray;
  path: string;
  i: Integer;
begin
  p := P0(AParams);
  names := TreePathNames(p.TreePathInfo);
  path := '';
  for i := 1 to High(names) do
  begin
    if i > 1 then path := path + '/';
    path := path + names[i];
  end;
  Result := '<div class="tooltip-title">' + EncodeHtml(path) + '</div>'
    + 'Disk Usage: ' + AddCommas(VN(p)) + ' KB';
end;

{ isValidNumber: != null and isFinite }
function Valid(const P: TTyChartCallbackParams; K: Integer; out V: Double): Boolean;
var c: TTyDataValue;
begin
  V := NaN;
  if not Cell(P, K, c) or (c.Kind = dvkNone) then Exit(False);
  V := N(P, K);
  Result := not IsNan(V) and not IsInfinite(V);
end;

{ treemap-obama's getTooltipFormatter(mode) }
function ObamaTip(const P: TTyChartCallbackParams; AMode: Integer): string;
var
  ai, ai11: Integer;
  v: Double;
  amount, amount11, house, change: string;
begin
  if AMode = 1 then ai := 1 else ai := 0;
  if AMode = 1 then ai11 := 0 else ai11 := 1;
  if Valid(P, ai, v) then amount := AddCommas(v * 1000) + '$' else amount := '-';
  if Valid(P, ai11, v) then amount11 := AddCommas(v * 1000) + '$' else amount11 := '-';
  if Valid(P, 3, v) then house := AddCommas(TyJsToNumber(Fx(v, 4)) * 1000) + '$'
  else house := '-';
  if Valid(P, 2, v) then change := Fx(v, 2) + '%' else change := '-';
  Result := '<div class="tooltip-title">' + EncodeHtml(P.Name) + '</div>'
    + '2012 Amount: &nbsp;&nbsp;' + amount + '<br>'
    + 'Per Household: &nbsp;&nbsp;' + house + '<br>'
    + '2011 Amount: &nbsp;&nbsp;' + amount11 + '<br>'
    + 'Change From 2011: &nbsp;&nbsp;' + change;
end;

{ treemap-obama's label for a mode: the name, a rule, the budget and --
  except in mode 1 -- the amount per household }
function ObamaLabel(const P: TTyChartCallbackParams; AMode: Integer): string;
begin
  Result := '{name|' + P.Name + '}'#10'{hr|}'#10'{budget|$ ' + AddCommas(N(P, 0))
    + '} {label|budget}';
  if AMode <> 1 then
    Result := Result + #10'{household|$ '
      + AddCommas(TyJsToNumber(Fx(N(P, 3), 4)) * 1000) + '} {label|per household}';
end;

function TGalleryCallbacks.ObamaTip0(const AParams: TTyChartParams): string;
begin
  Result := ObamaTip(P0(AParams), 0);
end;

function TGalleryCallbacks.ObamaTip1(const AParams: TTyChartParams): string;
begin
  Result := ObamaTip(P0(AParams), 1);
end;

function TGalleryCallbacks.ObamaTip2(const AParams: TTyChartParams): string;
begin
  Result := ObamaTip(P0(AParams), 2);
end;

function TGalleryCallbacks.ObamaLabel0(const AParams: TTyChartParams): string;
begin
  Result := ObamaLabel(P0(AParams), 0);
end;

function TGalleryCallbacks.ObamaLabel1(const AParams: TTyChartParams): string;
begin
  Result := ObamaLabel(P0(AParams), 1);
end;

function TGalleryCallbacks.ObamaLabel2(const AParams: TTyChartParams): string;
begin
  Result := ObamaLabel(P0(AParams), 2);
end;

{ treemap-visual's tooltip }
function TGalleryCallbacks.VisualTip(const AParams: TTyChartParams): string;
var
  p: TTyChartCallbackParams;
  v: Double;
  amount, amount11, change: string;
begin
  p := P0(AParams);
  if Valid(p, 0, v) then amount := AddCommas(v * 1000) + '$' else amount := '-';
  if Valid(p, 1, v) then amount11 := AddCommas(v * 1000) + '$' else amount11 := '-';
  if Valid(p, 2, v) then change := Fx(v, 2) + '%' else change := '-';
  Result := '<div class="tooltip-title">' + EncodeHtml(p.Name) + '</div>'
    + '2012 Amount: &nbsp;&nbsp;' + amount + '<br>'
    + '2011 Amount: &nbsp;&nbsp;' + amount11 + '<br>'
    + 'Change From 2011: &nbsp;&nbsp;' + change;
end;

{ wind-barb's axis tooltip: the time (local), wind speed, direction and
  wave height }
function TGalleryCallbacks.WindTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams; ms: Double;
begin
  p := P0(AParams);
  ms := CellMs(p, 0);
  { wind speed, wind direction, wave height }
  Result := LegacyFormatTime('yyyy-MM-dd', ms, False) + ' '
    + LegacyFormatTime('hh:mm', ms, False)
    + '<br>'#$E9#$A3#$8E#$E9#$80#$9F + cColonW + S(p, 1)
    + '<br>'#$E9#$A3#$8E#$E5#$90#$91 + cColonW + S(p, 2)
    + '<br>'#$E6#$B5#$AA#$E9#$AB#$98 + cColonW + S(p, 3);
end;

{ wind-barb's weather tooltip: value[0] + ': ' + min + ' - ' + max + degree }
function TGalleryCallbacks.WindWeatherTip(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := P0(AParams);
  Result := S(p, 0) + ': ' + S(p, 3) + ' - ' + S(p, 4) + cDegree;
end;

{ bar-polar-real-estate's tooltip: the page's cities and its data table }
function TGalleryCallbacks.PolarRentTip(const AParams: TTyChartParams): string;
const
  cCities: array[0..18] of string = (
    #$E5#$8C#$97#$E4#$BA#$AC, #$E4#$B8#$8A#$E6#$B5#$B7, #$E6#$B7#$B1#$E5#$9C#$B3,
    #$E5#$B9#$BF#$E5#$B7#$9E, #$E8#$8B#$8F#$E5#$B7#$9E, #$E6#$9D#$AD#$E5#$B7#$9E,
    #$E5#$8D#$97#$E4#$BA#$AC, #$E7#$A6#$8F#$E5#$B7#$9E, #$E9#$9D#$92#$E5#$B2#$9B,
    #$E6#$B5#$8E#$E5#$8D#$97, #$E9#$95#$BF#$E6#$98#$A5, #$E5#$A4#$A7#$E8#$BF#$9E,
    #$E6#$B8#$A9#$E5#$B7#$9E, #$E9#$83#$91#$E5#$B7#$9E, #$E6#$AD#$A6#$E6#$B1#$89,
    #$E6#$88#$90#$E9#$83#$BD, #$E4#$B8#$9C#$E8#$8E#$9E, #$E6#$B2#$88#$E9#$98#$B3,
    #$E7#$83#$9F#$E5#$8F#$B0);
  cData: array[0..18, 0..2] of Double = (
    (5000, 10000, 6785.71), (4000, 10000, 6825), (3000, 6500, 4463.33),
    (2500, 5600, 3793.83), (2000, 4000, 3060), (2000, 4000, 3222.33),
    (2500, 4000, 3133.33), (1800, 4000, 3100), (2000, 3500, 2750),
    (2000, 3000, 2500), (1800, 3000, 2433.33), (2000, 2700, 2375),
    (1500, 2800, 2150), (1500, 2300, 2100), (1600, 3500, 2057.14),
    (1500, 2600, 2037.5), (1500, 2417.54, 1905.85), (1500, 2000, 1775),
    (1500, 1800, 1650));
var id: Integer;
begin
  id := P0(AParams).DataIndex;
  if (id < 0) or (id > 18) then Exit('undefined<br>Lowest' + cColonW);
  Result := cCities[id] + '<br>Lowest' + cColonW + NS(cData[id, 0])
    + '<br>Highest' + cColonW + NS(cData[id, 1])
    + '<br>Average' + cColonW + NS(cData[id, 2]);
end;

{ ---- tooltip positions ---- }

{ area-simple, area-time-axis: [pt[0], '10%'] }
function TGalleryCallbacks.TenPercentTop(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpPoint;
  Result.X := TyChartPosNum(AArgs.PointX);
  Result.Y := TyChartPosText('10%');
end;

{ {top: ATop}, and AGap on the side away from the pointer }
function SideAway(const AArgs: TTyChartTooltipPosArgs; ATop, AGap: Double): TTyChartTooltipPos;
begin
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpBox;
  Result.Top := TyChartPosNum(ATop);
  { obj[['left', 'right'][+(pos[0] < viewSize[0] / 2)]] }
  if AArgs.PointX < AArgs.ViewW / 2 then Result.Right := TyChartPosNum(AGap)
  else Result.Left := TyChartPosNum(AGap);
end;

function TGalleryCallbacks.SideTop10(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  Result := SideAway(AArgs, 10, 30);
end;

function TGalleryCallbacks.SideTop60(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  Result := SideAway(AArgs, 60, 5);
end;

{ line-tooltip-touch: [pt[0], 130] }
function TGalleryCallbacks.TouchTop(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpPoint;
  Result.X := TyChartPosNum(AArgs.PointX);
  Result.Y := TyChartPosNum(130);
end;

{ scatter-nutrients-matrix: 60 from the far side, 20 from the far end }
function TGalleryCallbacks.Quadrant(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpBox;
  if AArgs.PointX < AArgs.ViewW / 2 then Result.Right := TyChartPosNum(60)
  else Result.Left := TyChartPosNum(60);
  if AArgs.PointY < AArgs.ViewH / 2 then Result.Bottom := TyChartPosNum(20)
  else Result.Top := TyChartPosNum(20);
end;

{ ---- label layouts ---- }

{ pie-labelLine-adjust: the line's end moved to the label's near edge --
  left of the chart's middle its left side, else its right }
function TGalleryCallbacks.PieLineEnd(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
var
  isLeft: Boolean;
  pts: TTyPointFArray;
  sc: Double;
begin
  Result := Default(TTyChartLabelLayout);
  sc := AArgs.Scale;
  if sc <= 0 then sc := 1;
  { the rects are device px; myChart.getWidth() is CSS px }
  isLeft := AArgs.LabelRectX / sc < AArgs.ChartWidth / 2;
  pts := Copy(AArgs.LabelLinePoints);
  if Length(pts) < 3 then Exit;
  if isLeft then pts[2].X := AArgs.LabelRectX
  else pts[2].X := AArgs.LabelRectX + AArgs.LabelRectW;
  Result.HasLabelLinePoints := True;
  Result.LabelLinePoints := pts;
end;

{ scatter-label-align-right: {x: myChart.getWidth() - 100, moveOverlap:
  'shiftY'} }
function TGalleryCallbacks.AlignRight(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Result := Default(TTyChartLabelLayout);
  Result.X := TyChartPosNum(AArgs.ChartWidth - 100);
  Result.MoveOverlap := 'shiftY';
end;

{ ---- animation ---- }

function TGalleryCallbacks.Delay10(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  if not AHasIndex then Exit(NaN);
  Result := ADataIndex * 10;
end;

function TGalleryCallbacks.Delay10Plus100(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  if not AHasIndex then Exit(NaN);
  Result := ADataIndex * 10 + 100;
end;

function TGalleryCallbacks.Delay5(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  if not AHasIndex then Exit(NaN);
  Result := ADataIndex * 5;
end;

function TGalleryCallbacks.Delay100(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  if not AHasIndex then Exit(NaN);
  Result := ADataIndex * 100;
end;

{ pie-custom: Math.random() * 200 }
function TGalleryCallbacks.DelayRandom200(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  Result := JsRandom * 200;
end;

{ pictorialBar-hill: params.index * 30 -- the repeated paper's place in its
  column, which a pictorial bar's item model hands every delay function
  ({index, count}; undefined on an element that is not a repeated glyph:
  NaN, no delay) }
function TGalleryCallbacks.HillDelay(ADataIndex: Integer; AHasIndex: Boolean;
  const AParams: TTyAnimDelayParams): Double;
begin
  if not (AParams.Present and AParams.HasIndex) then Exit(NaN);
  Result := AParams.Index * 30;
end;

{ pictorialBar-bar-transition: (idx / total) * 1000 }
function TGalleryCallbacks.UtShare(AIndex, ACount: Integer): Double;
begin
  Result := (AIndex / ACount) * 1000;
end;

{ scatter-aggregate-bar: Math.random() * 400 }
function TGalleryCallbacks.UtRandom400(AIndex, ACount: Integer): Double;
begin
  Result := JsRandom * 400;
end;

{ bar-multi-drilldown's back button: goBack() pops the page's stack of
  levels -- filled by its click handler on a bar, which is the page's own
  myChart.on('click'), not part of the option -- and with the stack empty it
  logs 'Already in root level!' and does nothing. }
function TGalleryCallbacks.GoBack(Sender: TObject; const AEvent: TTyChartElementEvent): Boolean;
begin
  Result := False;
end;

{ ==================== the registry ==================== }

procedure Fmt(const AName: string; AH: TTyChartFormatter; AList: TStrings);
begin
  if AList <> nil then AList.Add(AName) else TyChartRegisterFormatter(AName, AH);
end;

procedure Vis(const AName: string; AH: TTyChartVisualHandler; AList: TStrings);
begin
  if AList <> nil then AList.Add(AName) else TyChartRegisterVisualHandler(AName, AH);
end;

procedure Pos_(const AName: string; AH: TTyChartPositionHandler; AList: TStrings);
begin
  if AList <> nil then AList.Add(AName) else TyChartRegisterPositionHandler(AName, AH);
end;

procedure Lay(const AName: string; AH: TTyChartLabelLayoutHandler; AList: TStrings);
begin
  if AList <> nil then AList.Add(AName) else TyChartRegisterLabelLayoutHandler(AName, AH);
end;

procedure Tim(const AName: string; AH: TTyAnimTimingHandler; AList: TStrings);
begin
  if AList <> nil then AList.Add(AName) else TyChartRegisterAnimTiming(AName, AH);
end;

procedure Dly(const AName: string; AH: TTyAnimDelayHandler; AList: TStrings);
begin
  if AList <> nil then AList.Add(AName) else TyChartRegisterAnimDelay(AName, AH);
end;

procedure Utd(const AName: string; AH: TTyUtDelayHandler; AList: TStrings);
begin
  if AList <> nil then AList.Add(AName) else TyChartRegisterUtDelay(AName, AH);
end;

procedure Elh(const AName: string; AH: TTyChartElementHandler; AList: TStrings);
begin
  if AList <> nil then AList.Add(AName) else TyChartRegisterElementHandler(AName, AH);
end;

{ every name with its handler: registered (AList nil) or listed }
procedure Walk(AList: TStrings);
var
  c: TGalleryCallbacks;
  i: Integer;
begin
  if GCallbacks = nil then GCallbacks := TGalleryCallbacks.Create;
  c := GCallbacks;
  Pos_('area-simple.position', @c.TenPercentTop, AList);
  Pos_('area-time-axis.position', @c.TenPercentTop, AList);
  Tim('bar-animation-delay.animationDelay', @c.Delay10, AList);
  Tim('bar-animation-delay.animationDelay#2', @c.Delay10Plus100, AList);
  Tim('bar-animation-delay.animationDelayUpdate', @c.Delay5, AList);
  Elh('bar-multi-drilldown.onclick', @c.GoBack, AList);
  Fmt('bar-polar-real-estate.formatter', @c.PolarRentTip, AList);
  Fmt('bar-race-country.formatter', @c.RaceRound, AList);
  Fmt('bar-race-country.formatter#2', @c.RaceFlag, AList);
  Vis('bar-race-country.color', @c.RaceColor, AList);
  Fmt('bar-rich-text.formatter', @c.RichWeather, AList);
  for i := 1 to 5 do
  begin
    if i = 1 then
    begin
      Fmt('bar-stack-normalization-and-variation.formatter', @c.StackPercent, AList);
      Fmt('bar-stack-normalization.formatter', @c.StackPercent, AList);
    end
    else
    begin
      Fmt('bar-stack-normalization-and-variation.formatter#' + IntToStr(i), @c.StackPercent, AList);
      Fmt('bar-stack-normalization.formatter#' + IntToStr(i), @c.StackPercent, AList);
    end;
  end;
  Fmt('bar-waterfall.formatter', @c.Waterfall, AList);
  Fmt('bar-waterfall2.formatter', @c.Waterfall2, AList);
  Fmt('boxplot-light-velocity2.itemNameFormatter', @c.ExprName, AList);
  Vis('bubble-gradient.symbolSize', @c.SqrtThird, AList);
  Vis('bubble-gradient.symbolSize#2', @c.SqrtThird, AList);
  Fmt('bubble-gradient.formatter', @c.DataThird, AList);
  Fmt('bubble-gradient.formatter#2', @c.DataThird, AList);
  Vis('calendar-charts.symbolSize', @c.Second40, AList);
  Vis('calendar-charts.symbolSize#2', @c.Second60, AList);
  Vis('calendar-effectscatter.symbolSize', @c.Second500, AList);
  for i := 2 to 4 do
    Vis('calendar-effectscatter.symbolSize#' + IntToStr(i), @c.Second500, AList);
  Fmt('calendar-lunar.formatter', @c.LunarTip, AList);
  Fmt('calendar-lunar.formatter#2', @c.LunarDay, AList);
  Fmt('calendar-lunar.formatter#3', @c.LunarName, AList);
  Fmt('calendar-pie.formatter', @c.CalendarPieDay, AList);
  Fmt('calendar-vertical.formatter', @c.CalendarVerticalTip, AList);
  Pos_('candlestick-brush.position', @c.SideTop10, AList);
  Fmt('candlestick-sh.formatter', @c.CandleMarkRound, AList);
  Fmt('candlestick-sh.formatter#2', @c.CandleMarkTip, AList);
  Pos_('candlestick-touch.position', @c.SideTop60, AList);
  Fmt('candlestick-touch.formatter', @c.MonthDay, AList);
  Fmt('confidence-band.formatter', @c.BandTip, AList);
  Fmt('confidence-band.formatter#2', @c.BandDate, AList);
  Fmt('confidence-band.formatter#3', @c.BandAxis, AList);
  Fmt('confidence-band.formatter#4', @c.BandPointer, AList);
  Pos_('custom-ohlc.position', @c.SideTop10, AList);
  Fmt('dynamic-data2.formatter', @c.DynamicTip, AList);
  Vis('effectScatter-bmap.symbolSize', @c.Third10, AList);
  Vis('effectScatter-bmap.symbolSize#2', @c.Third10, AList);
  Vis('effectScatter-map.symbolSize', @c.Third10, AList);
  Vis('effectScatter-map.symbolSize#2', @c.Third10, AList);
  Fmt('flame-graph.formatter', @c.FlameTip, AList);
  Fmt('gauge-car.formatter', @c.CarQuarter, AList);
  Fmt('gauge-car.formatter#2', @c.CarNegate, AList);
  Fmt('gauge-clock.formatter', @c.ClockHour, AList);
  Fmt('gauge-grade.formatter', @c.Grade, AList);
  Fmt('gauge-grade.formatter#2', @c.GradeDetail, AList);
  Fmt('gauge-speed.formatter', @c.Speed, AList);
  Fmt('geo-svg-map.formatter', @c.SvgMapTip, AList);
  Fmt('geo-svg-map.formatter#2', @c.SvgGeoTip, AList);
  Vis('geo-svg-scatter-simple.symbolSize', @c.SvgScatterSize, AList);
  Tim('graph-life-expectancy.animationDelay', @c.Delay100, AList);
  for i := 2 to 19 do
    Tim('graph-life-expectancy.animationDelay#' + IntToStr(i), @c.Delay100, AList);
  Fmt('intraday-breaks-1.formatter', @c.BreakTime1, AList);
  Fmt('intraday-breaks-2.formatter', @c.BreakTime2, AList);
  Fmt('line-draggable.formatter', @c.DraggableTip, AList);
  Fmt('line-pen.formatter', @c.PenTip, AList);
  Fmt('line-race.formatter', @c.RaceEnd, AList);
  for i := 2 to 8 do
    Fmt('line-race.formatter#' + IntToStr(i), @c.RaceEnd, AList);
  Pos_('line-tooltip-touch.position', @c.TouchTop, AList);
  Fmt('line-tooltip-touch.formatter', @c.TouchDate, AList);
  Fmt('lines-airline.formatter', @c.AirlineTip, AList);
  Fmt('matrix-confusion.formatter', @c.Confusion, AList);
  Fmt('matrix-correlation-heatmap.formatter', @c.Fixed2Third, AList);
  Fmt('matrix-correlation-scatter.formatter', @c.Fixed2Third, AList);
  Fmt('matrix-covariance.valueFormatter', @c.RoundValue, AList);
  Fmt('matrix-graph.formatter', @c.DataThird, AList);
  Fmt('matrix-mbti.formatter', @c.MbtiTip, AList);
  Fmt('matrix-mbti.formatter#2', @c.MbtiPercent, AList);
  Fmt('matrix-periodic-table.formatter', @c.Periodic, AList);
  Fmt('mix-line-bar.valueFormatter', @c.Ml, AList);
  Fmt('mix-line-bar.valueFormatter#2', @c.Ml, AList);
  Fmt('mix-line-bar.valueFormatter#3', @c.Celsius, AList);
  Fmt('mix-zoom-on-value.formatter', @c.Thousands, AList);
  Fmt('multiple-x-axis.formatter', @c.Precipitation, AList);
  Fmt('multiple-x-axis.formatter#2', @c.Precipitation, AList);
  { every step of the sequence makes its options afresh: six functions, one
    body }
  Utd('pictorialBar-bar-transition.delay', @c.UtShare, AList);
  for i := 2 to 6 do
    Utd('pictorialBar-bar-transition.delay#' + IntToStr(i), @c.UtShare, AList);
  Dly('pictorialBar-hill.animationDelay', @c.HillDelay, AList);
  Fmt('pictorialBar-body-fill.formatter', @c.BodyFill, AList);
  Fmt('pictorialBar-spirit.formatter', @c.Spirit, AList);
  Fmt('pictorialBar-velocity.formatter', @c.NameValueTip, AList);
  Tim('pie-custom.animationDelay', @c.DelayRandom200, AList);
  Lay('pie-labelLine-adjust.labelLayout', @c.PieLineEnd, AList);
  Lay('pie-labelLine-adjust.labelLayout#2', @c.PieLineEnd, AList);
  Lay('pie-labelLine-adjust.labelLayout#3', @c.PieLineEnd, AList);
  Fmt('radar-custom.formatter', @c.RadarValue, AList);
  Utd('scatter-aggregate-bar.delay', @c.UtRandom400, AList);
  Utd('scatter-aggregate-bar.delay#2', @c.UtRandom400, AList);
  Utd('scatter-aggregate-bar.delay#3', @c.UtRandom400, AList);
  Fmt('scatter-aqi-color.formatter', @c.AqiTip, AList);
  Vis('scatter-label-align-right.symbolSize', @c.SqrtThird, AList);
  Lay('scatter-label-align-right.labelLayout', @c.AlignRight, AList);
  Fmt('scatter-label-align-right.formatter', @c.DataThird, AList);
  Vis('scatter-label-align-top.symbolSize', @c.SqrtThird, AList);
  Fmt('scatter-label-align-top.formatter', @c.DataThird, AList);
  Vis('scatter-map-brush.symbolSize', @c.ThirdMax8, AList);
  Vis('scatter-map-brush.symbolSize#2', @c.ThirdMax8, AList);
  Pos_('scatter-nutrients-matrix.position', @c.Quadrant, AList);
  Fmt('scatter-nutrients-matrix.formatter', @c.NutrientsTip, AList);
  Fmt('scatter-painter-choice.formatter', @c.Seconds, AList);
  Vis('scatter-painter-choice.symbolSize', @c.PainterSize, AList);
  Vis('scatter-painter-choice.color', @c.PainterColor, AList);
  Fmt('scatter-polar-punchCard.formatter', @c.PolarPunchTip, AList);
  Vis('scatter-polar-punchCard.symbolSize', @c.ThirdTwice, AList);
  Tim('scatter-polar-punchCard.animationDelay', @c.Delay5, AList);
  Fmt('scatter-punchCard.formatter', @c.PunchTip, AList);
  Vis('scatter-punchCard.symbolSize', @c.ThirdTwice, AList);
  Tim('scatter-punchCard.animationDelay', @c.Delay5, AList);
  Vis('scatter-single-axis.symbolSize', @c.SecondFour, AList);
  for i := 2 to 7 do
    Vis('scatter-single-axis.symbolSize#' + IntToStr(i), @c.SecondFour, AList);
  Fmt('scatter-weight.formatter', @c.WeightTip, AList);
  Fmt('sunburst-label-rotate.formatter', @c.SunburstRotate, AList);
  Fmt('treemap-disk.formatter', @c.DiskTip, AList);
  Fmt('treemap-obama.formatter', @c.ObamaTip0, AList);
  Fmt('treemap-obama.formatter#2', @c.ObamaLabel0, AList);
  Fmt('treemap-obama.formatter#3', @c.ObamaTip1, AList);
  Fmt('treemap-obama.formatter#4', @c.ObamaLabel1, AList);
  Fmt('treemap-obama.formatter#5', @c.ObamaTip2, AList);
  Fmt('treemap-obama.formatter#6', @c.ObamaLabel2, AList);
  Fmt('treemap-show-parent.formatter', @c.DiskTip, AList);
  Fmt('treemap-visual.formatter', @c.VisualTip, AList);
  Fmt('wind-barb.formatter', @c.WindTip, AList);
  Fmt('wind-barb.formatter#2', @c.WindWeatherTip, AList);
end;

procedure RegisterGalleryCallbacks;
begin
  Walk(nil);
end;

procedure GalleryCallbackNames(AList: TStrings);
begin
  AList.Clear;
  Walk(AList);
end;

procedure GalleryUntranscribed(AList: TStrings);
begin
  AList.Clear;
end;

procedure GalleryPrepare(const AId, AOptionText: string);
var d: TJSONData;
begin
  if AId <> 'scatter-nutrients-matrix' then Exit;
  if GCallbacks = nil then GCallbacks := TGalleryCallbacks.Create;
  d := nil;
  try
    try
      d := GetJSON(AOptionText);
    except
      d := nil;
    end;
    GCallbacks.PrepareNutrients(d);
  finally
    d.Free;
  end;
end;

finalization
  FreeAndNil(GCallbacks);

end.
