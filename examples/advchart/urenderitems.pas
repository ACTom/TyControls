unit urenderitems;

{$mode objfpc}{$H+}

{ THE GALLERY'S renderItem FUNCTIONS, IN PASCAL.

  An ECharts custom series draws each data item with a JavaScript function,
  renderItem. TTyAdvanceChart takes a named handler instead: the option says
  `renderItem: '@name'` and the host registers a method under that name with
  TyChartRegisterRenderItem. The gallery harvest writes the name of every
  function it meets there: the example's id, and `<id>#2`, `<id>#3` for a
  second and third function of the same page (tools/advchart-gallery/
  harvest.js). This unit is the other half: each handler below is the page's
  function, line for line, and RegisterGalleryRenderItems registers them all.

  WHAT A TRANSCRIPTION KEEPS. The arithmetic in the page's order (a different
  order is a different double), JavaScript's own rounding and trigonometry
  (TyJsRound, TyJsCos, TyJsSin), its number-to-text (TyJsNumberToString), and
  the page's own reading of an api answer -- `api.value(dim)` is the number
  when the cell holds one and the cell's text when it holds text, so a text
  dimension is read with OrdinalRawValue. tests/test.advchart.galleryrenderitem
  holds every one of them to what upstream draws for the same option
  (tools/advchart-oracle/gallery-renderitem.js).

  TWO THINGS A PAGE HAS THAT A HANDLER DOES NOT: the page's own variables
  (pie-parliament-transition's angles, custom-cartesian-polygon's data) are
  read back from the series' data through the api, which the page wrote
  them into; and geo-svg-custom-effect's Math.random is the demo's own
  xorshift32 (it only staggers an animation).

  WHAT IS NOT DRAWN, AND WHY. wind-barb's weather pictures are image URLs of
  the ECharts examples site; the chart loads no URL (a data: URL or an image
  list, see tyControls.AdvChart.Images), so the images are drawn empty,
  exactly where upstream would put them. }

interface

uses
  Classes, SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Custom;

{ Register every handler of this unit under its gallery name. }
procedure RegisterGalleryRenderItems;

{ The names RegisterGalleryRenderItems registers, for a host that lists them. }
procedure GalleryRenderItemNames(AList: TStrings);

implementation

uses
  tyControls.AdvChart.JsMath, tyControls.AdvChart.Scale,
  tyControls.AdvChart.Data, tyControls.AdvChart.Time,
  tyControls.AdvChart.Color;

type
  TGalleryRenderItems = class
  private
    FRandom: LongWord;
    function JsRandom: Double;
  public
    constructor Create;
    function BarTrend(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function CalendarIcon(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function CartesianPolygon(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function ErrorBar(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function ErrorScatter(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Ohlc(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function PolarHeatmap(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Profit(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function FlameGraph(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function GeoSvgEffect(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function MatrixConfusion(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function MiniBar(AApi: TTyCustomApi; AXDim, AYDim, AValDim: Integer): TJSONData;
    function MiniBar1(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function MiniBar2(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function MiniBar3(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function PeriodicTable(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Parliament(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function WindArrow(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function WindWeather(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

var
  GItems: TGalleryRenderItems = nil;

const
  cNames: array[0..17] of string = (
    'custom-bar-trend', 'custom-calendar-icon', 'custom-cartesian-polygon',
    'custom-error-bar', 'custom-error-scatter', 'custom-ohlc',
    'custom-polar-heatmap', 'custom-profit', 'flame-graph',
    'geo-svg-custom-effect', 'matrix-confusion',
    'matrix-mini-bar-data-collection', 'matrix-mini-bar-data-collection#2',
    'matrix-mini-bar-data-collection#3', 'matrix-periodic-table',
    'pie-parliament-transition', 'wind-barb', 'wind-barb#2');

{ ==================== helpers ==================== }

function N(A: Double): TJSONFloatNumber;
begin
  Result := TJSONFloatNumber.Create(A);
end;

{ a value an api call answered, or JavaScript's undefined (null here) }
function OrNull(A: TJSONData): TJSONData;
begin
  if A = nil then Result := TJSONNull.Create else Result := A;
end;

{ api.style(extra): the extra is read, not kept }
function StyleWith(AApi: TTyCustomApi; AExtra: TJSONObject): TJSONObject;
begin
  try
    Result := AApi.Style(AExtra);
  finally
    AExtra.Free;
  end;
end;

{ api.font(opt) }
function FontOf(AApi: TTyCustomApi; AOpt: TJSONObject): string;
begin
  try
    Result := AApi.Font(AOpt);
  finally
    AOpt.Free;
  end;
end;

{ api.value(dim) of a dimension that holds text: the text }
function TextOf(AApi: TTyCustomApi; ADim: Integer): string;
begin
  Result := AApi.OrdinalRawValue(ADim);
end;

{ isNaN(api.value(dim)): a null cell is Number(null), 0 -- not NaN }
function JsIsNaNValue(AApi: TTyCustomApi; ADim: Integer): Boolean;
var t: string;
begin
  t := AApi.ValueText(ADim);
  if t = 'null' then Exit(False);
  if not IsNan(AApi.Value(ADim)) then Exit(False);
  Result := IsNan(TyJsToNumber(t));
end;

{ echarts.number.linearMap(val, domain, range) without clamp }
function LinearMap(AVal, AD0, AD1, AR0, AR1: Double): Double;
var subDomain, subRange: Double;
begin
  subDomain := AD1 - AD0;
  subRange := AR1 - AR0;
  if subDomain = 0 then
  begin
    if subRange = 0 then Exit(AR0);
    Exit((AR0 + AR1) / 2);
  end;
  if AVal = AD0 then Exit(AR0);
  if AVal = AD1 then Exit(AR1);
  Result := (AVal - AD0) / subDomain * subRange + AR0;
end;

{ zrender's color.lift(color, level): each channel moved toward white
  (level > 0) and cut to an integer, as rgba() text }
function JsLift(const AColor: string; ALevel: Double): string;
var
  c: array[0..3] of Double;
  i: Integer;
  v: Double;
begin
  if not TyTryParseCssRgba(AColor, c[0], c[1], c[2], c[3]) then Exit('');
  for i := 0 to 2 do
  begin
    if ALevel < 0 then v := c[i] * (1 - ALevel)
    else v := (255 - c[i]) * ALevel + c[i];
    { `| 0`: toward zero }
    v := Trunc(v);
    if v > 255 then v := 255
    else if v < 0 then v := 0;
    c[i] := v;
  end;
  Result := 'rgba(' + TyJsNumberToString(c[0]) + ',' + TyJsNumberToString(c[1])
    + ',' + TyJsNumberToString(c[2]) + ',' + TyJsNumberToString(c[3]) + ')';
end;

function Pair(AX, AY: Double): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(N(AX));
  Result.Add(N(AY));
end;

{ ==================== the handlers ==================== }

constructor TGalleryRenderItems.Create;
begin
  inherited Create;
  FRandom := 2463534242;
end;

{ Math.random as the oracles hand it: xorshift32 }
function TGalleryRenderItems.JsRandom: Double;
var x: LongWord;
begin
  x := FRandom;
  x := x xor (x shl 13);
  x := x xor (x shr 17);
  x := x xor (x shl 5);
  FRandom := x;
  Result := x / 4294967296;
end;

{ custom-bar-trend: a polyline through the tops of the year bars of one
  category, each point lifted 20 px over the centre of its bar }
function TGalleryRenderItems.BarTrend(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  xValue, v: Double;
  cur: TTyIntegerArray;
  opt, extra: TJSONObject;
  bars: TTyCustomBarLayout;
  points: TJSONArray;
  i, si: Integer;
  point: TTyDoubleArray;
begin
  xValue := AApi.Value(0);
  cur := AApi.CurrentSeriesIndices;
  opt := TJSONObject.Create(['barGap', '30%', 'barCategoryGap', '20%',
    'count', Length(cur) - 1]);
  try
    bars := AApi.BarLayout(opt);
  finally
    opt.Free;
  end;
  points := TJSONArray.Create;
  for i := 0 to High(cur) do
  begin
    si := cur[i];
    if si = AParams.SeriesIndex then Continue;
    v := AApi.Value(si);
    point := AApi.Coord([xValue, v]);
    { barLayout[i - 1]: the bar of the i-th shown series, the trend itself
      being the first }
    if (i - 1 < 0) or (i - 1 > High(bars)) or (Length(point) < 2) then
    begin
      points.Free;
      raise Exception.Create('barLayout has no column ' + IntToStr(i - 1));
    end;
    point[0] := point[0] + bars[i - 1].OffsetCenter;
    point[1] := point[1] - 20;
    points.Add(Pair(point[0], point[1]));
  end;
  extra := TJSONObject.Create;
  extra.Add('stroke', OrNull(AApi.Visual('color')));
  extra.Add('fill', 'none');
  Result := TJSONObject.Create(['type', 'polyline',
    'shape', TJSONObject.Create(['points', points]),
    'style', StyleWith(AApi, extra)]);
end;

const
  { custom-calendar-icon's four icons and their colours }
  cIconPaths: array[0..3] of string = (
    'M936.857805 523.431322c0 0-42.065715-68.89513-88.786739-68.89513-46.68416 0-95.732122 71.223091-95.732122 71.223091s-44.28544-72.503296-93.440922-71.152538c-35.565466 0.977306-62.89705 30.882406-79.124275 64.06615L579.773747 790.800797c-3.253248 37.391565-5.677568 50.904371-12.002816 69.63497-6.651802 19.698688-19.544883 35.227341-31.650099 45.909606-14.30231 12.621414-29.59831 22.066586-45.854208 27.424563-16.28969 5.362074-30.098739 6.496973-51.536794 6.496973-19.498906 0-36.95104-2.963456-52.395418-8.850534-15.410586-5.887078-28.420403-14.313984-39.034573-25.246003-10.613146-10.930995-18.757939-24.08151-24.435507-39.525171-5.676544-15.443763-8.532685-40.195482-8.532685-59.270963l0-26.232454 74.435273 0c0 24.644301-0.17705 64.452915 8.81408 77.006848 9.02697 12.515021 22.756147 18.092032 41.148826 18.791014 16.728678 0.636518 30.032179-8.061645 30.032179-8.061645s11.922022-10.5472 14.992077-19.756954c2.674995-8.025805 3.565363-22.180147 3.565363-22.180147s2.080461-21.789286 2.080461-34.234675L489.399906 514.299369c-16.678502-18.827776-43.801395-61.938688-82.756096-60.927693-54.699008 1.419366-100.422144 70.059622-100.422144 70.059622s-56.065126-70.059622-93.440922-70.059622c-37.376717 0-91.077939 70.059622-91.077939 70.059622S105.343488 156.737741 476.742042 119.363584l53.70327-74.714624 51.373056 74.714624C964.889395 142.740992 936.857805 523.431322 936.857805 523.431322z',
    'M533.504 268.288q33.792-41.984 71.68-75.776 32.768-27.648 74.24-50.176t86.528-19.456q63.488 5.12 105.984 30.208t67.584 63.488 34.304 87.04 6.144 99.84-17.92 97.792-36.864 87.04-48.64 74.752-53.248 61.952q-40.96 41.984-85.504 78.336t-84.992 62.464-73.728 41.472-51.712 15.36q-20.48 1.024-52.224-14.336t-69.632-41.472-79.872-61.952-82.944-75.776q-26.624-25.6-57.344-59.392t-57.856-74.24-46.592-87.552-21.504-100.352 11.264-99.84 39.936-83.456 65.536-61.952 88.064-35.328q24.576-5.12 49.152-1.536t48.128 12.288 45.056 22.016 40.96 27.648q45.056 33.792 86.016 80.896z',
    'M741.06368 733.310464c8.075264-29.262438 20.615373-40.632422 14.64105-162.810061C966.089728 361.789952 967.93897 72.37847 967.855002 54.693683c0.279347-0.279347 0.418509-0.419533 0.418509-0.419533s-0.17705-0.00512-0.428749-0.00512c0-0.251699 0-0.428749 0-0.428749s-0.139162 0.14633-0.418509 0.425677c-17.695744-0.083866-307.10784 1.760051-515.833958 212.142592-122.181632-5.984256-133.55305 6.563533-162.815693 14.644531C235.35063 295.798886 103.552614 436.975309 90.630758 486.076621c-12.921856 49.105408 39.634227 56.859034 58.579558 58.581197 18.953421 1.724314 121.471386-9.475789 130.09111 4.309094 0 0 16.367411 11.200102 17.226035 41.346662 0.850432 29.796659 15.173222 71.354163 37.123994 97.267302-0.028672 0.027648-0.05632 0.054272-0.083866 0.074752 0.158618 0.13097 0.316211 0.261939 0.474829 0.390861 0.129946 0.149402 0.261939 0.319283 0.393011 0.468685 0.019456-0.019456 0.04608-0.049152 0.075776-0.075674 25.918362 21.961216 67.477504 36.272128 97.269248 37.122458 30.149837 0.859546 41.354547 17.234534 41.354547 17.234534 13.779354 8.608051 2.583962 111.122842 4.302131 130.075546 1.727386 18.95168 9.477222 71.498445 58.579558 58.576077C585.12896 918.526771 726.311117 786.734182 741.06368 733.310464zM595.893555 426.206003c-39.961702-39.965184-39.961702-104.75991 0-144.720077 39.970918-39.96928 104.768307-39.96928 144.730112 0 39.970918 39.960064 39.970918 104.75479 0 144.720077C700.661862 466.171187 635.864474 466.171187 595.893555 426.206003zM358.53312 769.516032c-31.923302-4.573184-54.890394-18.410291-71.41847-35.402342-16.984474-16.526438-30.830387-39.495475-35.405824-71.420621-4.649062-28.082586-20.856832-41.167565-38.76649-38.763827-17.906586 2.40681-77.046886 66.714419-80.857805 89.475891-3.80887 22.752154 29.271859 12.081152 46.424166 27.654861 17.151283 15.590093-2.139853 61.93664-14.733107 86.845952-6.441984 12.735078-10.289766 26.42176-4.22953 33.76087 7.346586 6.070272 21.03593 2.222592 33.769472-4.220109 24.912384-12.585677 71.258829-31.872922 86.842368-14.731469 15.583539 17.160806 4.911002 50.229965 27.674419 46.419251 22.754099-3.807744 87.065395-62.946611 89.466163-80.85248C399.70857 790.374093 386.627072 774.166938 358.53312 769.516032z',
    'M848.794624 939.156685 571.780416 939.156685 571.780416 653.17123l341.897539 0 0 221.100654C913.677926 909.960704 884.482867 939.156685 848.794624 939.156685zM571.780403 318.743552c-11.861606-3.210138-31.443354-8.36864-39.829709-16.176435-0.596582-0.561766-1.016218-1.246413-1.613824-1.841971-0.560845 0.596582-1.016218 1.280205-1.613824 1.841971-8.386355 7.807795-15.96631 12.965274-27.827917 16.176435l0 263.544325L141.030675 582.287877 141.030675 355.202884c0-35.687834 29.195059-64.882688 64.883302-64.882688l150.649125 0c-16.984474-9.525965-32.846438-20.56233-46.111027-32.932045-60.250624-56.144691-71.129907-137.062605-24.283034-180.767027 19.615539-18.264986 46.252237-27.124736 75.026739-27.124736 39.933133 0 83.972915 17.070797 118.995968 49.706086 20.353331 18.983322 37.722624 43.405619 50.145075 69.056819 12.457267-25.6512 29.791744-50.074419 50.180915-69.056819 35.022029-32.63529 79.062835-49.706086 118.994944-49.706086 28.74071 0 55.410176 8.860774 75.025715 27.124736 46.882611 43.704422 35.96759 124.622336-24.283034 180.767027-13.264589 12.368691-29.127578 23.40608-46.111027 32.932045l144.649234 0c35.688243 0 64.882278 29.195981 64.882278 64.882688l0 227.084948L571.780416 582.287833 571.780416 318.743508zM435.064218 147.625267c-21.476966-19.965747-49.094144-31.913882-73.868288-31.913882-7.404954 0-21.125018 1.211597-29.863322 9.386803-2.000691 1.824563-8.070144 7.439462-8.070144 21.369754 0 15.650406 8.492749 40.24873 32.319386 62.477926 29.124506 27.12576 77.202432 47.601152 111.76704 47.601152 12.176794 0 16.492237-2.666701 16.527053-2.702541C489.524736 242.54505 475.664486 185.453773 435.064218 147.625267zM577.78135 254.790963c0 0 0.034816-0.034816 0.069632-0.034816 0.807424 0 5.50871 1.790771 15.509914 1.790771 34.564608 0 82.64151-20.47529 111.76704-47.601152 23.826637-22.229299 32.283546-46.810112 32.283546-62.442189 0-13.930291-6.033613-19.562496-8.035328-21.404467-8.77312-8.17623-22.457344-9.386803-29.864346-9.386803-24.808038 0-52.390298 11.948134-73.867264 31.913882C585.325466 185.208218 571.358822 241.73865 577.78135 254.790963zM500.89513 939.156685 205.914017 939.156685c-35.688243 0-64.883302-29.195981-64.883302-64.883712L141.030714 653.17123l359.864462 0L500.895177 939.15666z');
  cIconColours: array[0..3] of string = ('#c4332b', '#16B644', '#6862FD', '#FDC763');

{ custom-calendar-icon: up to four icons in a day's cell, laid out by how
  many there are, and the day of the month above them }
function TGalleryRenderItems.CalendarIcon(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
const
  { layouts[n - 1]: where n icons go in the cell, -0.5 .. 0.5 }
  cLayouts: array[0..3, 0..3, 0..1] of Double = (
    ((0, 0), (0, 0), (0, 0), (0, 0)),
    ((-0.25, 0), (0.25, 0), (0, 0), (0, 0)),
    ((0, -0.2), (-0.2, 0.2), (0.2, 0.2), (0, 0)),
    ((-0.25, -0.25), (-0.25, 0.25), (0.25, -0.25), (0.25, 0.25)));
var
  day, cellWidth, cellHeight, px, py: Double;
  cellPoint: TTyDoubleArray;
  value: string;
  events: TStringArray;
  children: TJSONArray;
  extra: TJSONObject;
  index, ev, count: Integer;
begin
  Result := nil;
  day := AApi.Value(0);
  cellPoint := AApi.Coord([day]);
  cellWidth := AParams.CoordSys.CellWidth;
  cellHeight := AParams.CoordSys.CellHeight;
  value := TextOf(AApi, 1);
  { `value && value.split('|')`: '' is no events at all }
  if value = '' then events := nil
  else events := value.Split(['|']);
  if (Length(cellPoint) < 2) or IsNan(cellPoint[0]) or IsNan(cellPoint[1]) then Exit;
  children := TJSONArray.Create;
  count := Length(events);
  { (layouts[events.length - 1] || []): five or more events draw no icon }
  if (count >= 1) and (count <= 4) then
    for index := 0 to count - 1 do
    begin
      ev := Trunc(TyJsToNumber(events[index]));
      px := cellPoint[0] + LinearMap(cLayouts[count - 1, index, 0], -0.5, 0.5,
        -cellWidth / 2, cellWidth / 2);
      py := cellPoint[1] + LinearMap(cLayouts[count - 1, index, 1], -0.5, 0.5,
        -cellHeight / 2 + 20, cellHeight / 2);
      extra := TJSONObject.Create(['fill', cIconColours[ev]]);
      children.Add(TJSONObject.Create(['type', 'path',
        'shape', TJSONObject.Create(['pathData', cIconPaths[ev], 'x', -8, 'y', -8,
          'width', 16, 'height', 16]),
        'position', Pair(px, py),
        'style', StyleWith(AApi, extra)]));
    end;
  children.Add(TJSONObject.Create(['type', 'text',
    'style', TJSONObject.Create(['x', N(cellPoint[0]),
      'y', N(cellPoint[1] - cellHeight / 2 + 15),
      'text', TyFormatTime(AApi.Value(0), '{dd}', False),
      'fill', '#777',
      'textFont', FontOf(AApi, TJSONObject.Create(['fontSize', 14]))])]));
  Result := TJSONObject.Create(['type', 'group', 'children', children]);
end;

{ custom-cartesian-polygon: one polygon through every point, drawn by the
  first call of a render (params.context.rendered) }
function TGalleryRenderItems.CartesianPolygon(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  points: TJSONArray;
  i: Integer;
  p: TTyDoubleArray;
  x, y: Double;
  colour: TJSONData;
  text: string;
  extra: TJSONObject;
begin
  Result := nil;
  if (AParams.Context.Find('rendered') <> nil)
    and (AParams.Context.Find('rendered').JSONType = jtBoolean)
    and AParams.Context.Booleans['rendered'] then Exit;
  if AParams.Context.IndexOfName('rendered') >= 0 then
    AParams.Context.Delete('rendered');
  AParams.Context.Add('rendered', True);
  { the page's own `data`: the series' data, every item shown (filterMode
    'none') }
  points := TJSONArray.Create;
  for i := 0 to AParams.DataInsideLength - 1 do
  begin
    x := AApi.Value(0, i);
    y := AApi.Value(1, i);
    p := AApi.Coord([x, y]);
    points.Add(Pair(p[0], p[1]));
  end;
  colour := AApi.Visual('color');
  if colour is TJSONString then text := colour.AsString else text := '';
  extra := TJSONObject.Create;
  extra.Add('fill', OrNull(colour));
  if text <> '' then extra.Add('stroke', JsLift(text, 0.1))
  else extra.Add('stroke', TJSONNull.Create);
  Result := TJSONObject.Create(['type', 'polygon',
    'transition', TJSONArray.Create(['shape']),
    'shape', TJSONObject.Create(['points', points]),
    'style', StyleWith(AApi, extra)]);
end;

{ the three lines of an error bar }
function Line(AX1, AY1, AX2, AY2: Double; AStyle: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create(['type', 'line',
    'transition', TJSONArray.Create(['shape']),
    'shape', TJSONObject.Create(['x1', N(AX1), 'y1', N(AY1), 'x2', N(AX2), 'y2', N(AY2)]),
    'style', AStyle]);
end;

{ custom-error-bar: the high and low marks of an item and the line between }
function TGalleryRenderItems.ErrorBar(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  xValue, v1, v2, halfWidth: Double;
  highPoint, lowPoint, sz: TTyDoubleArray;
  extra, style: TJSONObject;
begin
  xValue := AApi.Value(0);
  v1 := AApi.Value(1);
  highPoint := AApi.Coord([xValue, v1]);
  v2 := AApi.Value(2);
  lowPoint := AApi.Coord([xValue, v2]);
  sz := AApi.Size([1, 0]);
  halfWidth := sz[0] * 0.1;
  extra := TJSONObject.Create;
  extra.Add('stroke', OrNull(AApi.Visual('color')));
  extra.Add('fill', TJSONNull.Create);
  style := StyleWith(AApi, extra);
  try
    Result := TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([
      Line(highPoint[0] - halfWidth, highPoint[1], highPoint[0] + halfWidth,
        highPoint[1], TJSONObject(style.Clone)),
      Line(highPoint[0], highPoint[1], lowPoint[0], lowPoint[1],
        TJSONObject(style.Clone)),
      Line(lowPoint[0] - halfWidth, lowPoint[1], lowPoint[0] + halfWidth,
        lowPoint[1], TJSONObject(style.Clone))])]);
  finally
    style.Free;
  end;
end;

{ custom-error-scatter: error bars along both axes, each from the series'
  encode }
function TGalleryRenderItems.ErrorScatter(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
const
  cDims: array[0..1] of string = ('x', 'y');
  cHalf = 5;
var
  baseDimIdx, otherDimIdx: Integer;
  baseValue: Double;
  param: array[0..1] of Double;
  highPoint, lowPoint: TTyDoubleArray;
  children: TJSONArray;
  extra, style: TJSONObject;

  function EncodeDim(const AName: string; AK: Integer): Integer;
  var d: TJSONData;
  begin
    d := AParams.Encode.Find(AName);
    Result := -1;
    if (d is TJSONArray) and (AK < d.Count) then Result := d.Items[AK].AsInteger;
  end;

  { makeShape: the base dimension's key first, as the page writes them }
  function MakeShape(ABase1, AValue1, ABase2, AValue2: Double): TJSONObject;
  begin
    Result := TJSONObject.Create;
    Result.Add(cDims[baseDimIdx] + '1', N(ABase1));
    Result.Add(cDims[1 - baseDimIdx] + '1', N(AValue1));
    Result.Add(cDims[baseDimIdx] + '2', N(ABase2));
    Result.Add(cDims[1 - baseDimIdx] + '2', N(AValue2));
  end;

  function LineOf(AShape: TJSONObject): TJSONObject;
  begin
    Result := TJSONObject.Create(['type', 'line',
      'transition', TJSONArray.Create(['shape']),
      'shape', AShape, 'style', style.Clone]);
  end;

begin
  children := TJSONArray.Create;
  for baseDimIdx := 0 to 1 do
  begin
    otherDimIdx := 1 - baseDimIdx;
    baseValue := AApi.Value(EncodeDim(cDims[baseDimIdx], 0));
    param[baseDimIdx] := baseValue;
    param[otherDimIdx] := AApi.Value(EncodeDim(cDims[otherDimIdx], 1));
    highPoint := AApi.Coord([param[0], param[1]]);
    param[otherDimIdx] := AApi.Value(EncodeDim(cDims[otherDimIdx], 2));
    lowPoint := AApi.Coord([param[0], param[1]]);
    extra := TJSONObject.Create;
    extra.Add('stroke', OrNull(AApi.Visual('color')));
    extra.Add('fill', TJSONNull.Create);
    style := StyleWith(AApi, extra);
    try
      children.Add(LineOf(MakeShape(highPoint[baseDimIdx] - cHalf,
        highPoint[otherDimIdx], highPoint[baseDimIdx] + cHalf, highPoint[otherDimIdx])));
      children.Add(LineOf(MakeShape(highPoint[baseDimIdx], highPoint[otherDimIdx],
        lowPoint[baseDimIdx], lowPoint[otherDimIdx])));
      children.Add(LineOf(MakeShape(lowPoint[baseDimIdx] - cHalf,
        lowPoint[otherDimIdx], lowPoint[baseDimIdx] + cHalf, lowPoint[otherDimIdx])));
    finally
      style.Free;
    end;
  end;
  Result := TJSONObject.Create(['type', 'group', 'children', children]);
end;

{ custom-ohlc: the high-low line, the open tick to the left, the close tick
  to the right }
function TGalleryRenderItems.Ohlc(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  xValue, v, halfWidth: Double;
  openPoint, closePoint, lowPoint, highPoint, sz: TTyDoubleArray;
  extra, style: TJSONObject;

  function L(AX1, AY1, AX2, AY2: Double): TJSONObject;
  begin
    Result := TJSONObject.Create(['type', 'line',
      'shape', TJSONObject.Create(['x1', N(AX1), 'y1', N(AY1), 'x2', N(AX2), 'y2', N(AY2)]),
      'style', style.Clone]);
  end;

begin
  xValue := AApi.Value(0);
  v := AApi.Value(1);
  openPoint := AApi.Coord([xValue, v]);
  v := AApi.Value(2);
  closePoint := AApi.Coord([xValue, v]);
  v := AApi.Value(3);
  lowPoint := AApi.Coord([xValue, v]);
  v := AApi.Value(4);
  highPoint := AApi.Coord([xValue, v]);
  sz := AApi.Size([1, 0]);
  halfWidth := sz[0] * 0.35;
  extra := TJSONObject.Create;
  extra.Add('stroke', OrNull(AApi.Visual('color')));
  style := StyleWith(AApi, extra);
  try
    Result := TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([
      L(lowPoint[0], lowPoint[1], highPoint[0], highPoint[1]),
      L(openPoint[0], openPoint[1], openPoint[0] - halfWidth, openPoint[1]),
      L(closePoint[0], closePoint[1], closePoint[0] + halfWidth, closePoint[1])])]);
  finally
    style.Free;
  end;
end;

{ custom-polar-heatmap: a ring sector a band wide and a band deep around the
  item's cell }
function TGalleryRenderItems.PolarHeatmap(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  v0, v1: Double;
  coord, sz: TTyDoubleArray;
  extra: TJSONObject;
begin
  v0 := AApi.Value(0);
  v1 := AApi.Value(1);
  coord := AApi.Coord([v0, v1]);
  sz := AApi.Size([1, 1], [v0, v1]);
  extra := TJSONObject.Create;
  extra.Add('fill', OrNull(AApi.Visual('color')));
  Result := TJSONObject.Create(['type', 'sector',
    'shape', TJSONObject.Create(['cx', N(AParams.CoordSys.Cx),
      'cy', N(AParams.CoordSys.Cy),
      'r0', N(coord[2] - sz[0] / 2),
      'r', N(coord[2] + sz[0] / 2),
      'startAngle', N(-(coord[3] + sz[1] / 2)),
      'endAngle', N(-(coord[3] - sz[1] / 2))]),
    'style', StyleWith(AApi, extra)]);
end;

{ custom-profit: a bar from `from` to `to` on a value x axis }
function TGalleryRenderItems.Profit(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  yValue, v0, v1: Double;
  start, sz: TTyDoubleArray;
begin
  yValue := AApi.Value(2);
  v0 := AApi.Value(0);
  start := AApi.Coord([v0, yValue]);
  v1 := AApi.Value(1);
  v0 := AApi.Value(0);
  sz := AApi.Size([v1 - v0, yValue]);
  Result := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', N(start[0]), 'y', N(start[1]),
      'width', N(sz[0]), 'height', N(sz[1])]),
    'style', AApi.Style]);
end;

{ flame-graph: a frame of the stack from its start to its end sample, its
  name inside, cut with '..' to the frame }
function TGalleryRenderItems.FlameGraph(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  level, v, height, width: Double;
  start, stop, sz: TTyDoubleArray;
begin
  level := AApi.Value(0);
  v := AApi.Value(1);
  start := AApi.Coord([v, level]);
  v := AApi.Value(2);
  stop := AApi.Coord([v, level]);
  { (api.size && api.size([0, 1])) || [0, 20] }
  sz := AApi.Size([0, 1]);
  if Length(sz) >= 2 then height := sz[1] else height := 20;
  width := stop[0] - start[0];
  Result := TJSONObject.Create(['type', 'rect',
    'transition', TJSONArray.Create(['shape']),
    'shape', TJSONObject.Create(['x', N(start[0]), 'y', N(start[1] - height / 2),
      'width', N(width), 'height', N(height - 2), 'r', 2]),
    'style', TJSONObject.Create(['fill', OrNull(AApi.Visual('color'))]),
    'emphasis', TJSONObject.Create(['style', TJSONObject.Create(['stroke', '#000'])]),
    'textConfig', TJSONObject.Create(['position', 'insideLeft']),
    'textContent', TJSONObject.Create([
      'style', TJSONObject.Create(['text', TextOf(AApi, 3),
        'fontFamily', 'Verdana', 'fill', '#000', 'width', N(width - 4),
        'overflow', 'truncate', 'ellipsis', '..', 'truncateMinChar', 1]),
      'emphasis', TJSONObject.Create(['style', TJSONObject.Create([
        'stroke', '#000', 'lineWidth', 0.5])])])]);
end;

{ geo-svg-custom-effect: five rings rippling out of a point and a pin
  bouncing on it }
function TGalleryRenderItems.GeoSvgEffect(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
const
  cPin = 'M16 0c-5.523 0-10 4.477-10 10 0 10 10 22 10 22s10-12 10-22c0-5.523-4.477-10-10-10zM16 16c-3.314 0-6-2.686-6-6s2.686-6 6-6 6 2.686 6 6-2.686 6-6 6z';
var
  x, y: Double;
  coord: TTyDoubleArray;
  children: TJSONArray;
  i: Integer;
begin
  x := AApi.Value(0, AParams.DataIndex);
  y := AApi.Value(1, AParams.DataIndex);
  coord := AApi.Coord([x, y]);
  children := TJSONArray.Create;
  for i := 0 to 4 do
    children.Add(TJSONObject.Create(['type', 'circle',
      'shape', TJSONObject.Create(['cx', 0, 'cy', 0, 'r', 30]),
      'style', TJSONObject.Create(['stroke', 'red', 'fill', 'none', 'lineWidth', 2]),
      { the ripple }
      'keyframeAnimation', TJSONObject.Create(['duration', 4000, 'loop', True,
        'delay', N((-i / 4) * 4000),
        'keyframes', TJSONArray.Create([
          TJSONObject.Create(['percent', 0, 'scaleX', 0, 'scaleY', 0,
            'style', TJSONObject.Create(['opacity', 1])]),
          TJSONObject.Create(['percent', 1, 'scaleX', 1, 'scaleY', 0.4,
            'style', TJSONObject.Create(['opacity', 0])])])])]));
  children.Add(TJSONObject.Create(['type', 'path',
    'shape', TJSONObject.Create(['d', cPin, 'x', -10, 'y', -35, 'width', 20, 'height', 40]),
    'style', TJSONObject.Create(['fill', 'red']),
    { the jump }
    'keyframeAnimation', TJSONObject.Create(['duration', 1000, 'loop', True,
      'delay', N(JsRandom * 1000),
      'keyframes', TJSONArray.Create([
        TJSONObject.Create(['y', -10, 'percent', 0.5, 'easing', 'cubicOut']),
        TJSONObject.Create(['y', 0, 'percent', 1, 'easing', 'bounceOut'])])])]));
  Result := TJSONObject.Create(['type', 'group', 'x', N(coord[0]), 'y', N(coord[1]),
    'children', children]);
end;

{ matrix-confusion: a cell's rect, green on the diagonal }
function TGalleryRenderItems.MatrixConfusion(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  x, y: Double;
  lay: TTyCustomLayout;
  fill: string;
begin
  x := AApi.Value(0);
  y := AApi.Value(1);
  lay := AApi.Layout([x, y]);
  if x = y then fill := '#8f8' else fill := '#f88';
  Result := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', N(lay.Rect.X), 'y', N(lay.Rect.Y),
      'width', N(lay.Rect.Width), 'height', N(lay.Rect.Height)]),
    'style', StyleWith(AApi, TJSONObject.Create(['fill', fill]))]);
end;

{ matrix-mini-bar-data-collection's makeRenderItem(xDim, yDim, valDim,
  [0, 10000]): a bar as long as the value and the value above it }
function TGalleryRenderItems.MiniBar(AApi: TTyCustomApi; AXDim, AYDim,
  AValDim: Integer): TJSONData;
var
  xval, yval, labelVal, height, barY, barX, widthMax, width: Double;
  lay: TTyCustomLayout;
begin
  Result := nil;
  xval := AApi.Value(AXDim);
  yval := AApi.Value(AYDim);
  labelVal := AApi.Value(AValDim);
  lay := AApi.Layout([xval, yval]);
  if not lay.Valid then Exit;
  height := lay.Rect.Height * 0.2;
  barY := lay.Rect.Y + (lay.Rect.Height - height) / 4 * 3;
  barX := lay.Rect.X + lay.Rect.Width * 0.15;
  widthMax := lay.Rect.Width * 0.5;
  width := LinearMap(labelVal, 0, 10000, 0, widthMax);
  Result := TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([
    TJSONObject.Create(['type', 'rect',
      'shape', TJSONObject.Create(['x', N(barX), 'y', N(barY), 'width', N(width),
        'height', N(height)]),
      'style', StyleWith(AApi, TJSONObject.Create(['fill', '#0ca8df']))]),
    TJSONObject.Create(['type', 'text', 'x', N(barX),
      'y', N(lay.Rect.Y + lay.Rect.Height / 4 * 1.5),
      'style', TJSONObject.Create(['text', TyJsNumberToString(labelVal),
        'fill', '#333', 'align', 'left', 'verticalAlign', 'middle'])])])]);
end;

function TGalleryRenderItems.MiniBar1(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
begin
  Result := MiniBar(AApi, 1, 0, 2);
end;

function TGalleryRenderItems.MiniBar2(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
begin
  Result := MiniBar(AApi, 3, 0, 4);
end;

function TGalleryRenderItems.MiniBar3(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
begin
  Result := MiniBar(AApi, 5, 0, 6);
end;

{ matrix-periodic-table: an element's cell, two pixels in from the cell, in
  its group's colour; a placeholder cell (no atomic number) half see-through
  -- except that isNaN(null) is false, so the page's two placeholders are
  drawn as elements, as upstream draws them }
function TGalleryRenderItems.PeriodicTable(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
const
  cMargin = 2;
var
  x, y: Double;
  lay: TTyCustomLayout;
  isElement: Boolean;
  extra: TJSONObject;
begin
  x := AApi.Value(0);
  y := AApi.Value(1);
  lay := AApi.Layout([x, y]);
  isElement := not JsIsNaNValue(AApi, 2);
  extra := TJSONObject.Create;
  extra.Add('fill', TextOf(AApi, 4));
  extra.Add('stroke', '#aaa');
  if isElement then extra.Add('lineWidth', 1) else extra.Add('lineWidth', 0);
  if isElement then extra.Add('opacity', 1) else extra.Add('opacity', 0.5);
  Result := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', N(lay.Rect.X + cMargin),
      'y', N(lay.Rect.Y + cMargin),
      'width', N(lay.Rect.Width - cMargin * 2),
      'height', N(lay.Rect.Height - cMargin * 2)]),
    'style', StyleWith(AApi, extra)]);
end;

{ pie-parliament-transition's parliament: an item's share of the ring as
  rows of seats }
function TGalleryRenderItems.Parliament(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
const
  cPalette: array[0..8] of string = ('#5070dd', '#b6d634', '#505372',
    '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95');
var
  angles: array of Double;
  sum, startAngle, curAngle, viewSize, r0, r1, cx, cy, size: Double;
  pct0, pct1: Double;
  idx, i: Integer;
  children: TJSONArray;

  { the page's parliamentLayout: seat centres row by row, outward }
  procedure Layout(AStart, AEnd, ATotal, AR0, AR1, ASize: Double);
  var
    rowsCount, row: Integer;
    r, seats, newSize, k, kEnd, angle: Double;
  begin
    rowsCount := Ceil((AR1 - AR0) / ASize);
    r := AR0;
    for row := 0 to rowsCount - 1 do
    begin
      seats := TyJsRound((ATotal * r) / ASize);
      newSize := (ATotal * r) / seats;
      k := Floor((AStart * r) / newSize) * newSize;
      kEnd := Floor((AEnd * r) / newSize) * newSize - 1e-6;
      while k < kEnd do
      begin
        angle := k / r;
        children.Add(TJSONObject.Create(['type', 'circle', 'autoBatch', True,
          'shape', TJSONObject.Create(['cx', N(cx + TyJsCos(angle) * r),
            'cy', N(cy + TyJsSin(angle) * r), 'r', N(size / 2)]),
          'style', TJSONObject.Create(['fill', cPalette[idx mod 9]])]));
        k := k + newSize;
      end;
      r := r + ASize;
    end;
  end;

begin
  { the page's angles, from its data: the start of each share and a full
    turn after the first }
  sum := 0;
  for i := 0 to AParams.DataInsideLength - 1 do sum := sum + AApi.Value(0, i);
  SetLength(angles, AParams.DataInsideLength + 1);
  startAngle := -Pi / 2;
  curAngle := startAngle;
  for i := 0 to AParams.DataInsideLength - 1 do
  begin
    angles[i] := curAngle;
    curAngle := curAngle + (AApi.Value(0, i) / sum) * Pi * 2;
  end;
  angles[AParams.DataInsideLength] := startAngle + Pi * 2;
  idx := AParams.DataIndex;
  viewSize := Math.Min(AApi.GetWidth, AApi.GetHeight);
  { parseFloat('30%') and parseFloat('80%'), as doubles: a literal 30 / 100
    is folded by the compiler, at a precision of its choosing }
  pct0 := 30;
  pct1 := 80;
  r0 := ((pct0 / 100) * viewSize) / 2;
  r1 := ((pct1 / 100) * viewSize) / 2;
  cx := AApi.GetWidth * 0.5;
  cy := AApi.GetHeight * 0.5;
  size := viewSize / 50;
  children := TJSONArray.Create;
  Layout(angles[idx], angles[idx + 1], Pi * 2, r0, r1, size + 3);
  Result := TJSONObject.Create(['type', 'group', 'children', children]);
end;

const
  { wind-barb's compass points, a sixteenth of a turn apart from the west }
  cDirections: array[0..15] of string = ('W', 'WSW', 'SW', 'SSW', 'S', 'SSE',
    'SE', 'ESE', 'E', 'ENE', 'NE', 'NNE', 'N', 'NNW', 'NW', 'WNW');

{ wind-barb: an arrow at the wind speed, turned to the wind's direction }
function TGalleryRenderItems.WindArrow(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
const
  cArrowSize = 18;
var
  t, speed: Double;
  point: TTyDoubleArray;
  dir: string;
  i: Integer;
  o, extra: TJSONObject;
begin
  t := AApi.Value(0);
  speed := AApi.Value(1);
  point := AApi.Coord([t, speed]);
  o := TJSONObject.Create(['type', 'path',
    'shape', TJSONObject.Create(['pathData', 'M31 16l-15-15v9h-26v12h26v9z',
      'x', N(-cArrowSize / 2), 'y', N(-cArrowSize / 2),
      'width', cArrowSize, 'height', cArrowSize])]);
  { directionMap[api.value(R)]: undefined for a name it does not have }
  dir := TextOf(AApi, 2);
  for i := 0 to High(cDirections) do
    if cDirections[i] = dir then
    begin
      o.Add('rotation', N(Pi / 8 * i));
      Break;
    end;
  o.Add('position', Pair(point[0], point[1]));
  extra := TJSONObject.Create(['stroke', '#555', 'lineWidth', 1]);
  o.Add('style', StyleWith(AApi, extra));
  Result := o;
end;

{ wind-barb: a day's weather picture and its temperatures, at noon }
function TGalleryRenderItems.WindWeather(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
const
  cIconSize = 45;
  cDegree = #$C2#$B0;
var
  t: Double;
  point: TTyDoubleArray;
begin
  t := AApi.Value(0);
  point := AApi.Coord([t + (3600 * 24 * 1000) / 2, 0]);
  Result := TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([
    TJSONObject.Create(['type', 'image',
      'style', TJSONObject.Create(['image', TextOf(AApi, 2),
        'x', N(-cIconSize / 2), 'y', N(-cIconSize / 2),
        'width', cIconSize, 'height', cIconSize]),
      'position', Pair(point[0], 110)]),
    TJSONObject.Create(['type', 'text',
      'style', TJSONObject.Create([
        'text', TextOf(AApi, 3) + ' - ' + TextOf(AApi, 4) + cDegree,
        'textFont', FontOf(AApi, TJSONObject.Create(['fontSize', 14])),
        'textAlign', 'center', 'textVerticalAlign', 'bottom']),
      'position', Pair(point[0], 80)])])]);
end;

{ ==================== the registry ==================== }

procedure RegisterGalleryRenderItems;
begin
  if GItems = nil then GItems := TGalleryRenderItems.Create;
  TyChartRegisterRenderItem('custom-bar-trend', @GItems.BarTrend);
  TyChartRegisterRenderItem('custom-calendar-icon', @GItems.CalendarIcon);
  TyChartRegisterRenderItem('custom-cartesian-polygon', @GItems.CartesianPolygon);
  TyChartRegisterRenderItem('custom-error-bar', @GItems.ErrorBar);
  TyChartRegisterRenderItem('custom-error-scatter', @GItems.ErrorScatter);
  TyChartRegisterRenderItem('custom-ohlc', @GItems.Ohlc);
  TyChartRegisterRenderItem('custom-polar-heatmap', @GItems.PolarHeatmap);
  TyChartRegisterRenderItem('custom-profit', @GItems.Profit);
  TyChartRegisterRenderItem('flame-graph', @GItems.FlameGraph);
  TyChartRegisterRenderItem('geo-svg-custom-effect', @GItems.GeoSvgEffect);
  TyChartRegisterRenderItem('matrix-confusion', @GItems.MatrixConfusion);
  TyChartRegisterRenderItem('matrix-mini-bar-data-collection', @GItems.MiniBar1);
  TyChartRegisterRenderItem('matrix-mini-bar-data-collection#2', @GItems.MiniBar2);
  TyChartRegisterRenderItem('matrix-mini-bar-data-collection#3', @GItems.MiniBar3);
  TyChartRegisterRenderItem('matrix-periodic-table', @GItems.PeriodicTable);
  TyChartRegisterRenderItem('pie-parliament-transition', @GItems.Parliament);
  TyChartRegisterRenderItem('wind-barb', @GItems.WindArrow);
  TyChartRegisterRenderItem('wind-barb#2', @GItems.WindWeather);
end;

procedure GalleryRenderItemNames(AList: TStrings);
var i: Integer;
begin
  if AList = nil then Exit;
  AList.Clear;
  for i := 0 to High(cNames) do AList.Add(cNames[i]);
end;

finalization
  FreeAndNil(GItems);
end.
