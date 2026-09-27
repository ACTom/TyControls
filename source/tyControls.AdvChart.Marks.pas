unit tyControls.AdvChart.Marks;
{$mode objfpc}{$H+}
{ A bound series plus its store, turned into paint-list elements.

  THIS IS WHERE THE TIER 0 SUBSTRATE FINALLY HAS A CONSUMER. Every piece it
  uses was built and tested with nothing calling it: the columnar store holds
  the rows, the coordinate system turns a datum into a point or a cell, the
  shape record is the one description that paint and hit-test share, and the
  paint list orders and hit-tests them. Until now the control drew axes and
  nothing else, and its own diagnostics said so in as many words.

  PURE, like everything upstream of AdvChart.Measure: SysUtils, Math and the
  AdvChart units. No painter, no LCL. A colour arrives as a number because
  resolving a theme is the control's job -- the same reason the layout layer
  takes an ITyTextMeasurer instead of reaching for the painter.

  ONE RECT PER BAR, FROM DataToLayout. That function is contract (1) of the
  spec, and a bar is the shape it was designed to return: one band wide, from
  the value axis' start value (TyValueAxisStart -- zero, not the axis' min) to
  the datum. A renderer that computed the rect
  itself would be the second producer of a number the coordinate system already
  owns -- and would get horizontal bars wrong, which is exactly the defect
  DataToLayout carried until it was made to ask which axis is the spine.

  THE WIDTH IS NOT DECIDED HERE. It cannot be: how wide a bar is depends on
  every OTHER bar series sharing the base axis, which one series cannot see.
  AdvChart.BarLayout solves that per axis and the answer arrives in the visual.
  This unit's job is to put the rect where the answer says.

  VALUES THAT STACK ARRIVE ALREADY ACCUMULATED. AdvChart.Stack writes two
  calculated columns per participating series, and this unit is told which:
  the cumulative one is what gets plotted, and the one below it is where a
  stacked bar's floor is. Working out what a value adds up to is not a
  rendering question, which is why it is not answered here.

  WHAT IS STILL NOT HERE: symbols on a line, the filled area under one, and the
  four-corner form of borderRadius. Each is its own Tier 1 row. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
  tyControls.AdvChart.Data, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Color, tyControls.AdvChart.VisualMap,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Series,
  tyControls.AdvChart.BarLayout, tyControls.AdvChart.Symbol,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Pictorial,
  tyControls.AdvChart.Labels, tyControls.AdvChart.LabelOpt;

type
  { Where a stepped line turns. ECharts spells `step: true` as 'start'. }
  TTyLineStep = (lstNone, lstStart, lstMiddle, lstEnd);

  { showAllSymbol: 'auto' | true | false. 'auto' is the default and means
    "all of them unless they would crowd", which upstream decides from the
    symbol's size against the space one category gets. }
  TTyShowAllSymbol = (sasAuto, sasYes, sasNo);

  { How the area under a line finds its lower edge when nothing is stacked
    beneath it. ECharts' areaStyle.origin. }
  TTyAreaOrigin = (laoAuto, laoStart, laoEnd, laoValue);

  { The line-shaped options of one series, read off its option node.

    Read here rather than resolved by the control because none of them needs
    the theme or the other series -- unlike a bar's width, which cannot be
    known without its neighbours. }
  TTyLineSpec = record
    HasArea: Boolean;
    AreaOrigin: TTyAreaOrigin;
    AreaOriginValue: Double;
    { 0..1, and the default is 0.7 -- NOT 1. The view puts the area in with
      `defaults(getAreaStyle(), {fill: visualColor, opacity: 0.7})`, so an
      `areaStyle: {}` is a SEVENTY PER CENT wash of the series colour and
      not a solid block of it. Radar does the same. An opaque area hides
      whatever is stacked behind it, which is the visible half of getting
      this wrong. }
    AreaOpacity: Double;
    { `areaStyle.color`, when the author named one. Separate from the
      series colour because an area named its own colour does not make the
      LINE that colour -- they are two keys on two blocks. }
    HasAreaFill: Boolean;
    AreaFill: TTyChartColor;
    { The classic fading area is a gradient on `areaStyle.color`, so this is
      the one place a chart gradient is written more often than not. }
    AreaGradient: TTyChartGradient;
    Step: TTyLineStep;
    ConnectNulls: Boolean;
    { showSymbol, default TRUE: an ECharts line has a marker on every point. }
    ShowSymbol: Boolean;
    ShowAllSymbol: TTyShowAllSymbol;
    { The thinning the AXIS settled on -- 1 when it draws every label. When the
      markers would crowd, upstream falls back to "follow the label interval
      strategy on the category axis", and this is that interval, computed once
      by the layout pass rather than guessed at again here. }
    LabelStep: Integer;
    { `clip`, default TRUE: a line is cut at the plot, widened by half its
      width, and a marker -- a line's or a scatter's -- outside the plot is
      not drawn at all. FALSE lets the line run past the plot along the
      value axis only. }
    Clip: Boolean;
  end;

  { Everything about ONE series that was decided somewhere else.

    It began as "how it looks, resolved from the theme", and it is no longer
    only that: a bar's column comes from a solver that had to see every other
    bar on the axis, and the line spec is read straight off the option. What
    they have in common is that this unit does not work any of them out -- it
    draws what it is handed. }
  { A candle's colours. UP is close above open; DOWN is open above close; the
    two are not "positive and negative" however they are usually described,
    because both compare a datum against ITSELF.

    THE THIRD CASE IS A DOJI -- open exactly equal to close, which is a real
    and frequent reading and not a rounding accident. Upstream resolves it by
    looking at the PREVIOUS row's close, so a flat bar takes the direction of
    the move that led into it; only when `borderColorDoji` is written does it
    get a colour of its own. The first row of all has no previous and is
    treated as up. }
  TTyCandleSpec = record
    Up, Down: TTyChartColor;
    UpBorder, DownBorder: TTyChartColor;
    HasDojiBorder: Boolean;
    DojiBorder: TTyChartColor;
    BorderWidthLogical: Double;
  end;

  TTySeriesVisual = record
    Fill: TTyChartColor;
    Stroke: TTyChartColor;
    { 0..1, whole-element. 1 unless the author wrote an opacity. }
    Alpha: Double;
    { A RAMP INSTEAD OF THE FLAT COLOUR, when the author wrote one. Fill and
      Stroke keep their solids either way -- the ramp's first stop -- because
      a legend swatch wants one colour and upstream's own rule for getting
      one is exactly that. }
    FillGradient: TTyChartGradient;
    StrokeGradient: TTyChartGradient;
    { <= 0 means no stroke, the same rule the element style and
      TTyPainter.StrokePath both follow. }
    StrokeWidthLogical: Double;
    { The pen's dash AS THE OPTION SAID IT, not as lengths. The two words mean
      multiples of the line width, and the width is not settled until the shape
      that carries it is built -- a line whose option gave no width takes the
      default 2 inside its own builder -- so resolving here would dash every
      unwidthed line in 1px steps. MarkElement turns the pair into lengths at
      the moment both are known. }
    Dash: TTyOptDash;
    DashExplicit: TTyDoubleArray;
    { The four colours a candle needs, and the pen. A block of its own rather
      than four more fields on the visual: a candlestick is the only series
      whose colour depends on the DATUM's own two numbers, and putting `Up` and
      `Down` beside `Fill` would invite every other builder to wonder which of
      the three it should be reading. }
    Candle: TTyCandleSpec;
    { Where this bar sits in its band, solved across every bar series sharing
      the base axis -- which is why it arrives rather than being computed here.
      Unsolved means no solver ran (a pure-unit caller with one series), and
      the default for exactly that case is asked of the solver too, so there is
      no second definition of what a lone bar's width is. }
    Bar: TTyBarColumn;
    { A PICTORIAL BAR'S OWN OPTIONS. Here for the same reason the bar column
      is: a mark builder is handed no option node, so anything option-shaped
      has to arrive on this record. }
    Pictorial: TTyPictorialSpec;
    { Painted front-to-back by (Z, Z2, insertion). Marks sit above the grid;
      Z2 keeps two series in a stable order relative to each other. }
    Z, Z2: Integer;
    { The line-shaped options, ignored by every other renderer. }
    Line: TTyLineSpec;
    { The symbol a datum is drawn as. Scatter draws nothing else; a line will
      draw these on top of itself once showSymbol lands. }
    Symbol: TTySymbolSpec;
    { What an `empty` symbol is filled with -- the theme's own background,
      resolved by the control, because this unit never asks what colour
      anything is. Upstream fills them with a token too. }
    EmptyFill: TTyChartColor;
    { showBackground's strip. Upstream writes rgba(180,180,180,0.2) into the
      series default; here it is a theme key, so a dark skin does not get a
      pale grey band across it. }
    BackgroundFill: TTyChartColor;
    { The words on each mark, and how they are chosen. Carried here for the
      same reason the bar column is: it was decided somewhere else. }
    Label_: TTyLabelSpec;
    { Which store column `{c}` and the default text read. -1 means neither
      has a value to show. }
    LabelValueDim: Integer;
    { `{a}`. The option's own series name, resolved by the control. }
    SeriesName: string;
    { WHAT A visualMap WROTE ON EACH DATUM, by raw index; nil when none
      targets this series. Applied before the datum's own itemStyle.color,
      which still wins, and its opacity REPLACES the series' Alpha. }
    VisualRows: TTyVisualRowArray;
    { A LINE'S PEN AND AREA when a visualMap gave it a visualMeta on x or y:
      one colour or a global gradient in device px, instead of the series
      colour. The two flags say which of them take it -- an authored
      lineStyle.color keeps the pen, an authored areaStyle.color the area. }
    VisualLine: TTyVisualLineFill;
    VisualLineStroke, VisualLineArea: Boolean;
  end;

{ A visual with the defaults: a filled mark, no stroke, upstream's bar gap. }
function TySeriesVisual(AFill: TTyChartColor): TTySeriesVisual;

{ The line-shaped options of the series in slot ASlot.

  Every default is upstream's: `step: false`, `connectNulls: false`, and no
  areaStyle at all -- its mere PRESENCE turns the area on, which is why an
  empty `areaStyle: {}` is a real instruction and not a no-op. }
{ `itemStyle.color` / `color0` / `borderColor` / `borderColor0` /
  `borderColorDoji` / `borderWidth`, over whatever the theme supplied.

  ADefaults arrives already resolved, because the two colours a candle falls
  back on are the theme's and this unit cannot see a theme. }
function TyCandleSpecOf(AOption: TTyChartOption; ASlot: Integer;
  const ADefaults: TTyCandleSpec): TTyCandleSpec;

function TyLineSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyLineSpec;

{ The fill ONE ROW was drawn with: the series' colour, unless that row wrote an
  `itemStyle.color` of its own. 0 for a row that asked for none.

  Exported because a tooltip's marker is the same question a mark's fill was,
  and answering it a second time somewhere else is how a dot ends up a
  different colour from the thing it names. Note it is the FILL and not the ink
  on screen: an `emptyCircle` marker is drawn as a RING, with the series colour
  as its pen and the chart's own ground as its fill, and upstream's tooltip
  marker still takes the series colour -- because the visual pipeline writes
  that colour once, and which of the two slots a SYMBOL then paints it into is
  the symbol's business. }
function TyRowFill(const AVisual: TTySeriesVisual; AStore: TTyDataStore;
  ARow: Integer): TTyChartColor;

{ Whether this series type draws anything yet.

  EXPORTED SO THE EDITOR CAN STOP GUESSING. Its all-clear row has to tell the
  author which of their series will appear, and a second list of type names
  kept over there would be wrong the day a renderer lands here. Asking the
  renderer is the same rule that keeps the bar rect coming from DataToLayout
  instead of from arithmetic repeated at the call site.

  Case-sensitive, like TySeriesFindType: ECharts' type names are, so a series
  typed 'Bar' does not resolve and never draws. }
function TySeriesTypeHasRenderer(const AType: string): Boolean;

{ Append this series' marks to AList and answer how many were added.

  Zero is a legitimate answer and not a failure: a series whose type has no
  renderer yet, an empty store, a series bound to no axes. The control's
  diagnostics are what tell the reader why nothing was drawn -- returning a
  count rather than a boolean is so a caller can say "nothing at all was
  drawn" without inspecting the list. }
function TyBuildSeriesMarks(const ABinding: TTySeriesBinding;
  AStore: TTyDataStore; const AStack: TTySeriesStack;
  const AVisual: TTySeriesVisual; AList: TTyPaintList): Integer;

implementation

uses tyControls.AdvChart.JsMath, tyControls.AdvChart.AxisLabels;

function TyCandleSpecOf(AOption: TTyChartOption; ASlot: Integer;
  const ADefaults: TTyCandleSpec): TTyCandleSpec;
var
  node, item: TJSONObject;
  d: TJSONData;
  c: TTyChartColor;

  function ColourAt(const AKey: string; var ATarget: TTyChartColor): Boolean;
  var v: TJSONData;
  begin
    Result := False;
    v := item.Find(AKey);
    if (v = nil) or (v.JSONType <> jtString) then Exit;
    if TyChartColorIsNone(v.AsString) then
    begin
      ATarget := 0;
      Exit(True);
    end;
    if not TyTryParseChartColor(v.AsString, c) then Exit;
    ATarget := c;
    Result := True;
  end;

begin
  Result := ADefaults;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('series', ASlot);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('itemStyle');
  if not (d is TJSONObject) then Exit;
  item := TJSONObject(d);

  { `color` IS THE UP BODY AND `color0` THE DOWN ONE -- and the border keys
    follow the same suffix. Upstream's own comment beside them reads
    "positive" and "negative", which is a description of a price move and not
    of a number: both sides compare a datum against itself. }
  ColourAt('color', Result.Up);
  ColourAt('color0', Result.Down);
  if not ColourAt('borderColor', Result.UpBorder) then
    if item.Find('color') <> nil then Result.UpBorder := Result.Up;
  if not ColourAt('borderColor0', Result.DownBorder) then
    if item.Find('color0') <> nil then Result.DownBorder := Result.Down;
  Result.HasDojiBorder := ColourAt('borderColorDoji', Result.DojiBorder);

  d := item.Find('borderWidth');
  if (d <> nil) and (d.JSONType = jtNumber) then
    Result.BorderWidthLogical := Max(Double(0), Min(Double(64), d.AsFloat));
end;

function TyLineSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyLineSpec;
var
  node, area: TJSONObject;
  d: TJSONData;
  sv: string;
  ast: TTyOptStyle;
begin
  Result.HasArea := False;
  Result.AreaOrigin := laoAuto;
  Result.AreaOriginValue := 0;
  Result.AreaOpacity := 0.7;
  Result.HasAreaFill := False;
  Result.AreaFill := 0;
  Result.AreaGradient := Default(TTyChartGradient);
  Result.Step := lstNone;
  Result.ConnectNulls := False;
  Result.ShowSymbol := True;
  Result.ShowAllSymbol := sasAuto;
  Result.LabelStep := 1;
  Result.Clip := True;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('series', ASlot);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);

  { `step` is false | true | 'start' | 'middle' | 'end', and true means
    'start' -- upstream's own comment says so beside the default. }
  d := node.Find('step');
  if d <> nil then
  begin
    if (d.JSONType = jtBoolean) and d.AsBoolean then Result.Step := lstStart
    else if d.JSONType = jtString then
    begin
      sv := d.AsString;
      if sv = 'start' then Result.Step := lstStart
      else if sv = 'middle' then Result.Step := lstMiddle
      else if sv = 'end' then Result.Step := lstEnd;
    end;
  end;

  d := node.Find('connectNulls');
  if (d <> nil) and (d.JSONType = jtBoolean) then
    Result.ConnectNulls := d.AsBoolean;

  { get('clip', true), then read as a truth: absent or null is the default }
  d := node.Find('clip');
  if (d <> nil) and (d.JSONType <> jtNull) then
    case d.JSONType of
      jtBoolean: Result.Clip := d.AsBoolean;
      jtNumber: Result.Clip := (not IsNan(d.AsFloat)) and (d.AsFloat <> 0);
      jtString: Result.Clip := d.AsString <> '';
    else
      Result.Clip := True;
    end;

  d := node.Find('showSymbol');
  if (d <> nil) and (d.JSONType = jtBoolean) then
    Result.ShowSymbol := d.AsBoolean;

  d := node.Find('showAllSymbol');
  if d <> nil then
  begin
    if d.JSONType = jtBoolean then
    begin
      if d.AsBoolean then Result.ShowAllSymbol := sasYes
      else Result.ShowAllSymbol := sasNo;
    end
    else if (d.JSONType = jtString) and (d.AsString = 'auto') then
      Result.ShowAllSymbol := sasAuto;
  end;

  { PRESENCE IS THE SWITCH. `areaStyle: {}` fills the area; there is no
    `show` and no default block to inherit. }
  d := node.Find('areaStyle');
  if (d = nil) or not (d is TJSONObject) then Exit;
  Result.HasArea := True;
  area := TJSONObject(d);

  { `areaStyle.color`. Read here rather than by the control because the
    whole line block is read here, and one reader per block is the rule
    that keeps the two from disagreeing about defaults. }
  ast := TyReadOptStyle(node, 'areaStyle');
  Result.HasAreaFill := ast.Color.Written and not ast.Color.IsAuto
                        and not ast.Color.IsNone;
  if Result.HasAreaFill then Result.AreaFill := ast.Color.Color;
  Result.AreaGradient := ast.Color.Gradient;

  d := area.Find('opacity');
  if (d <> nil) and (d.JSONType = jtNumber) then
    { Double(0)/Double(1), NOT 0/1: an integer beside a Double picks Math's
      SINGLE overload and quietly rounds the result to a 24-bit mantissa. It
      would not matter for an alpha; the shape is what matters, because the
      next thing clamped this way might be a coordinate. }
    Result.AreaOpacity := Min(Double(1), Max(Double(0), d.AsFloat));

  d := area.Find('origin');
  if d = nil then Exit;
  if d.JSONType = jtNumber then
  begin
    Result.AreaOrigin := laoValue;
    Result.AreaOriginValue := d.AsFloat;
  end
  else if d.JSONType = jtString then
  begin
    sv := d.AsString;
    if sv = 'start' then Result.AreaOrigin := laoStart
    else if sv = 'end' then Result.AreaOrigin := laoEnd;
  end;
end;

function TySeriesVisual(AFill: TTyChartColor): TTySeriesVisual;
begin
  Result.Fill := AFill;
  Result.Stroke := 0;
  Result.StrokeWidthLogical := 0;
  Result.Alpha := 1;
  Result.FillGradient := Default(TTyChartGradient);
  Result.StrokeGradient := Default(TTyChartGradient);
  Result.Bar := Default(TTyBarColumn);
  { NO Clip := True HERE, though it was written and then taken out again.
    Default() leaves Solved False, and ColumnFor ignores an unsolved column
    entirely -- it asks TyBarColumnForOneSeries instead, which sets Clip
    itself. So the line read like a safeguard and was never once read; a
    mutant that flipped it changed nothing, which is how it was found. }
  Result.BackgroundFill := AFill;
  Result.Z := 0;
  Result.Z2 := 0;
  Result.Line.HasArea := False;
  Result.Line.AreaOrigin := laoAuto;
  Result.Line.AreaOriginValue := 0;
  Result.Line.AreaOpacity := 0.7;
  Result.Line.HasAreaFill := False;
  Result.Line.AreaFill := 0;
  Result.Line.AreaGradient := Default(TTyChartGradient);
  Result.Line.Step := lstNone;
  Result.Line.ConnectNulls := False;
  { TRUE, because that is upstream's default and this record is "the
    defaults".

    It was tempting to make a hand-built visual quiet so the existing polyline
    tests would not have to change -- but two different defaults for one field
    is precisely the invisible-wrong-default this port keeps being bitten by,
    and the surprise here is visible (extra elements) rather than silent
    (missing ones). The geometry tests turn it off and say why. }
  Result.Line.ShowSymbol := True;
  Result.Line.ShowAllSymbol := sasAuto;
  Result.Line.LabelStep := 1;
  Result.Symbol := TySymbolDefault('');
  { THE PICTORIAL DEFAULTS, from the one place they are written down.
    Default() would leave every box value zero, which is not "no size" but
    a size of nothing -- so a hand-built visual would draw no glyph at all
    and the renderer would look absent rather than unconfigured. }
  Result.Pictorial := TyPictorialSpecDefault;
  Result.EmptyFill := 0;
  Result.VisualRows := nil;
  Result.VisualLine := Default(TTyVisualLineFill);
  Result.VisualLineStroke := False;
  Result.VisualLineArea := False;
end;

{ The value the area falls back to where nothing is stacked underneath.

  ECharts' getValueStart. 'auto' is NOT simply zero: an axis whose whole range
  is above zero starts the area at the bottom of the range, and one entirely
  below zero starts it at the top -- otherwise the fill would reach off the
  plot towards a zero that is not on the axis. }
function AreaStartValue(AValueAxis: TTyAxis;
  const ASpec: TTyLineSpec): Double;
var e: TTyRange;
begin
  if AValueAxis = nil then Exit(0);
  e := AValueAxis.Scale.GetExtent;
  case ASpec.AreaOrigin of
    laoStart: Result := e.Start;
    laoEnd:   Result := e.Stop;
    laoValue: Result := ASpec.AreaOriginValue;
  else
    if e.Start > 0 then Result := e.Start
    else if e.Stop < 0 then Result := e.Stop
    else Result := 0;
  end;
end;

{ Upstream's turnPointsIntoStep, transcribed.

  For every consecutive pair it emits the current point and then ONE corner
  ('start' and 'end') or TWO ('middle'), and finally the last point. Which
  coordinate the corner keeps is decided by the BASE axis, not by x: turned
  sideways, a step turns vertically. }
function StepPoints(const APts: array of TTyPointF; ABaseHoriz: Boolean;
  AStep: TTyLineStep): TTyPointFArray;
var
  i, n: Integer;
  pt, nextPt, a, b: TTyPointF;
  mid: Double;

  procedure Push(const AP: TTyPointF);
  begin
    if n > High(Result) then SetLength(Result, Max(8, n * 2));
    Result[n] := AP;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  if (AStep = lstNone) or (Length(APts) < 2) then
  begin
    SetLength(Result, Length(APts));
    for i := 0 to High(APts) do Result[i] := APts[i];
    Exit;
  end;
  SetLength(Result, Length(APts) * 3);
  for i := 0 to Length(APts) - 2 do
  begin
    pt := APts[i];
    nextPt := APts[i + 1];
    Push(pt);
    case AStep of
      lstEnd:
        begin
          { Along the base to the next station, still at this value. }
          if ABaseHoriz then a := TyPointF(nextPt.X, pt.Y)
                        else a := TyPointF(pt.X, nextPt.Y);
          Push(a);
        end;
      lstMiddle:
        begin
          if ABaseHoriz then
          begin
            mid := (pt.X + nextPt.X) / 2;
            a := TyPointF(mid, pt.Y);
            b := TyPointF(mid, nextPt.Y);
          end
          else
          begin
            mid := (pt.Y + nextPt.Y) / 2;
            a := TyPointF(pt.X, mid);
            b := TyPointF(nextPt.X, mid);
          end;
          Push(a);
          Push(b);
        end;
    else
      { lstStart: change value first, then move along the base. }
      if ABaseHoriz then a := TyPointF(pt.X, nextPt.Y)
                    else a := TyPointF(nextPt.X, pt.Y);
      Push(a);
    end;
  end;
  Push(APts[High(APts)]);
  SetLength(Result, n);
end;

{ The element every mark starts from: this series' colours, and a datum
  reference so the hit test can answer with the row the pointer is over. }
{ The words one mark says, or '' when its series draws no labels.

  AStore is the series' own store, so `{c}` and `{@dim}` read the row that is
  being drawn rather than a row somebody passed separately. }
function CaptionFor(const AVisual: TTySeriesVisual; AStore: TTyDataStore;
  ARow: Integer): string;
begin
  Result := '';
  if not AVisual.Label_.Show then Exit;
  if AVisual.Label_.Position = tlpNone then Exit;
  Result := TyLabelText(AVisual.Label_.Formatter, AVisual.Label_.HasFormatter,
    AVisual.Label_.DefaultText, AStore, ARow, AVisual.SeriesName,
    AVisual.LabelValueDim, 0, False);
end;

{ THIS ROW'S OWN COLOUR AND OPACITY, when the author gave them.

  `data: [1, 2, { value: 3, itemStyle: { color: 'red' } }]` is how a single
  bar or a single slice is picked out, and it is the commonest reason a
  chart has a colour the palette never chose. The builder has already
  parked the leaf under its dotted path, so this is a lookup and not a
  second reader of the option.

  A row that names an unreadable colour keeps the series' -- the same rule
  the series level follows. }
function RowVisual(const AVisual: TTySeriesVisual; AStore: TTyDataStore;
  ARow: Integer): TTySeriesVisual;
var v: TTyDataValue; c: TTyChartColor; raw: Integer; vr: TTyVisualRow;
begin
  Result := AVisual;
  if AStore = nil then Exit;
  { THE VISUAL PIPELINE FIRST, then the datum's own style over it: upstream's
    visualMap encoding is stage 4000 and the item style 4500. A colour the
    mapping left undefined paints nothing, and an opacity it wrote replaces
    the series' rather than multiplying it. }
  if AVisual.VisualRows <> nil then
  begin
    raw := AStore.GetRawIndex(ARow);
    if (raw >= 0) and (raw <= High(AVisual.VisualRows)) then
    begin
      vr := AVisual.VisualRows[raw];
      if vr.ColorSet then
      begin
        Result.Fill := TyVisualToChart(vr.Color);
        Result.FillGradient := Default(TTyChartGradient);
      end;
      if vr.OpacitySet and not IsNan(vr.Opacity) then
        Result.Alpha := Min(Double(1), Max(Double(0), vr.Opacity));
    end;
  end;
  { THE ITEM'S OWN OPACITY REPLACES the series' and the visualMap's alike --
    upstream extends the item style over both. [Batch 54: it was not read.] }
  if AStore.HasOverride(ARow, TyOverrideKey('itemStyle.opacity')) then
  begin
    v := AStore.GetOverride(ARow, TyOverrideKey('itemStyle.opacity'));
    if (v.Kind = dvkNumber) and not IsNan(v.Num) then
      Result.Alpha := Min(Double(1), Max(Double(0), v.Num));
  end;
  if not AStore.HasOverride(ARow, TyOverrideKey('itemStyle.color')) then Exit;
  v := AStore.GetOverride(ARow, TyOverrideKey('itemStyle.color'));
  if v.Kind <> dvkText then Exit;
  if TyChartColorIsNone(v.Text) then
  begin
    Result.Fill := 0;
    Exit;
  end;
  if TyTryParseChartColor(v.Text, c) then Result.Fill := c;
end;

{ HOW FAR OUTSIDE A MARK STILL COUNTS, in LOGICAL px -- the hit test scales it
  by PPI, the shapes are already device px.

  NOTHING WITH AREA GETS ANY. A bar, a wedge and a filled band are the size of
  the thing they mean; slop on a bar would reach across the category gap into
  its neighbour's, and upstream gives them none either.

  A MARKER IS NOT THE SIZE OF THE THING IT MEANS. A line's default symbol is a
  four-pixel emptyCircle standing for one whole row, and a target that small is
  one the pointer keeps missing. Four logical px makes it something a hand can
  hit while leaving two markers ten px apart still separate -- the hit test
  answers with the TOPMOST element it contains, not the nearest, so overlapping
  slop would quietly hand every tie to the later row.

  A LINE IS A RIBBON. PolylineNear measures to the mathematical segment and the
  shape record carries no stroke width, so half the pen has to arrive as slop
  or a three-pixel line is hittable only along its centre line. }
const
  cHitSlopSymbolLogical = 4;
  cHitSlopLineLogical = 4;

function MarkElement(const AShape: TTyChartShape; const AVisual: TTySeriesVisual;
  ASeries, ARow: Integer): TTyChartElement;
begin
  Result := TyChartElement(AShape);
  Result.Style.HasFill := AVisual.Fill <> 0;
  Result.Style.FillColor := AVisual.Fill;
  Result.Style.StrokeColor := AVisual.Stroke;
  Result.Style.StrokeWidthLogical := AVisual.StrokeWidthLogical;
  Result.Style.DashLogical := TyDashPattern(AVisual.Dash, AVisual.DashExplicit,
    AVisual.StrokeWidthLogical);
  { `itemStyle.opacity` is a whole-element alpha and MULTIPLIES the
    colour's own -- upstream writes it to globalAlpha, so an 80% opacity
    over a half-transparent colour is 40%, not 80%. Set on every mark from
    one place, because there is one place every mark is built. }
  Result.Style.Alpha := AVisual.Alpha;
  Result.Style.FillGradient := AVisual.FillGradient;
  Result.Style.StrokeGradient := AVisual.StrokeGradient;
  Result.Z := AVisual.Z;
  Result.Z2 := AVisual.Z2;
  Result.Silent := False;
  Result.Datum := TyChartDatum(ASeries, ARow);
end;

{ UPSTREAM'S clip.cartesian2d (BarView.ts), on the layout as upstream holds
  it -- x, y and a signed width and height -- against the coordinate
  system's area. True when the bar was clipped past itself: it is then not
  drawn. The far edge is x + width, never an edge taken over as it is. }
function ClipBarLayout(const AArea: TTyXYWH; var AX, AY, AW, AH: Double): Boolean;
var
  signW, signH: Integer;
  x2c, y2c, x, x2, y, y2: Double;
  xClipped, yClipped: Boolean;
begin
  if AW < 0 then signW := -1 else signW := 1;
  if AH < 0 then signH := -1 else signH := 1;
  if signW < 0 then
  begin
    AX := AX + AW;
    AW := -AW;
  end;
  if signH < 0 then
  begin
    AY := AY + AH;
    AH := -AH;
  end;
  x2c := AArea.X + AArea.W;
  y2c := AArea.Y + AArea.H;
  x := Max(AX, AArea.X);
  x2 := Min(AX + AW, x2c);
  y := Max(AY, AArea.Y);
  y2 := Min(AY + AH, y2c);
  xClipped := x2 < x;
  yClipped := y2 < y;
  if xClipped and (x > x2c) then AX := x2 else AX := x;
  if yClipped and (y > y2c) then AY := y2 else AY := y;
  if xClipped then AW := 0 else AW := x2 - x;
  if yClipped then AH := 0 else AH := y2 - y;
  if signW < 0 then
  begin
    AX := AX + AW;
    AW := -AW;
  end;
  if signH < 0 then
  begin
    AY := AY + AH;
    AH := -AH;
  end;
  Result := xClipped or yClipped;
end;

{ The rect of a layout whose width and height may be negative. }
function LayoutBox(AX, AY, AW, AH: Double): TTyRectF;
begin
  Result := TyRectF(Min(AX, AX + AW), Min(AY, AY + AH),
    Max(AX, AX + AW), Max(AY, AY + AH));
end;

{ Which side `outside` is for a bar: past the end it grows to, decided on its
  signed length (upstream's getLabelPositionFor*). One CLIPPED TO NOTHING --
  or of no length at all -- has no end of its own, and takes the side the
  value axis runs towards: up, or down on an inverse axis; right, or left.

  THE LENGTH BEFORE barMinHeight WILL DO: the minimum never turns a bar
  round -- a zero it lengthens goes up, or right, which is what a zero here
  already answers. }
function BarOutside(ALen: Double; AZero, ABaseHorizontal,
  AInverse: Boolean): TTyCaptionOutside;
begin
  if ABaseHorizontal then
  begin
    if AZero then
    begin
      if AInverse then Exit(coBottom) else Exit(coTop);
    end;
    if ALen > 0 then Result := coBottom else Result := coTop;
  end
  else
  begin
    if AZero then
    begin
      if AInverse then Exit(coLeft) else Exit(coRight);
    end;
    if ALen >= 0 then Result := coRight else Result := coLeft;
  end;
end;

{ The column this series draws with. Solved by the layout pass in production;
  for a caller that has not run one, the SAME solver answers for a single
  default series, so a lone bar is 0.69 of its band either way and the number
  is written down in exactly one place. }
function ColumnFor(const AVisual: TTySeriesVisual; const ABounds: TTyRectF;
  ABaseHorizontal: Boolean): TTyBarColumn;
var
  band: Double;
begin
  if AVisual.Bar.Solved then Exit(AVisual.Bar);
  if ABaseHorizontal then
    band := ABounds.Right - ABounds.Left
  else
    band := ABounds.Bottom - ABounds.Top;
  Result := TyBarColumnForOneSeries(band);
end;

type
  { What every mark builder looks like. Named so the table below can hold them,
    which is what makes the table the only list of renderers there is. }
  TTyMarkBuilder = function(const ABinding: TTySeriesBinding;
    AStore: TTyDataStore; const AStack: TTySeriesStack;
    const AVisual: TTySeriesVisual; AList: TTyPaintList;
    AColX, AColY: Integer): Integer;

function BuildBars(const ABinding: TTySeriesBinding; AStore: TTyDataStore;
  const AStack: TTySeriesStack; const AVisual: TTySeriesVisual;
  AList: TTyPaintList; AColX, AColY: Integer): Integer;
var
  i, valCol: Integer;
  x, y, baseline, own, floorV, floorPx, len: Double;
  lx, ly, lw, lh: Double;
  zero, inverse: Boolean;
  lay: TTyCoordLayout;
  r, bg, plot: TTyRectF;
  p, loPt: TTyPointF;
  col: TTyBarColumn;
  baseHoriz, haveCol, stacked: Boolean;
  shape: TTyChartShape;
  bgEl, el: TTyChartElement;
begin
  Result := 0;
  baseHoriz := (ABinding.BaseAxis = nil) or ABinding.BaseAxis.Horizontal;
  { THE VALUE IS ON WHICHEVER AXIS IS NOT THE BASE. On a horizontal bar chart
    that is X, so substituting the cumulative into y would stack the wrong axis
    and leave horizontal stacked bars looking unstacked. }
  stacked := AStack.Stacked and (AStack.ResultCol >= 0);
  if baseHoriz then valCol := AColY else valCol := AColX;
  haveCol := False;
  col := Default(TTyBarColumn);
  { THE LINE A BAR STANDS ON -- the value axis' start value, the same one
    DataToLayout built the cell from, asked again because the cell's Min/Max
    lost which end it was. A bar's length, its minimum and its outside side
    are all measured from it (or, stacked, from the bar below). }
  baseline := 0;
  inverse := False;
  if ABinding.ValueAxis <> nil then
  begin
    baseline := ABinding.ValueAxis.DataToCoord(
      TyValueAxisStart(ABinding.ValueAxis));
    inverse := ABinding.ValueAxis.Inverse;
  end;
  for i := 0 to AStore.Count - 1 do
  begin
    x := AStore.Get(AColX, i);
    y := AStore.Get(AColY, i);
    own := AStore.Get(valCol, i);
    { A stacked series plots its cumulative total. That is the whole of
      stacking as far as drawing is concerned. }
    if stacked then
    begin
      if baseHoriz then y := AStore.Get(AStack.ResultCol, i)
                   else x := AStore.Get(AStack.ResultCol, i);
    end;
    { NaN IS THE SINGLE SPELLING OF NO DATA, which the store's header says for
      all four dimension types. A gap draws no bar; it does not draw a bar of
      height zero, which would read as a real measurement of nothing.

      A MUTANT OF THIS LINE SURVIVES, and it is worth writing down why rather
      than inventing a test to hide it: the rect that comes back for a NaN
      datum fails TyRectFIsValid two lines down, so the gap is caught either
      way. The check stays because it states the rule at the point the rule
      applies -- but it is not, today, the thing enforcing it. }
    if IsNan(x) or IsNan(y) then Continue;
    { THE COLUMN: solved for the axis, or -- for a series nobody solved --
      one lone column in the datum's own band }
    if not haveCol then
    begin
      lay := ABinding.Cart.DataToLayout([x, y]);
      if not TyRectFIsValid(lay.Rect) then Continue;
      col := ColumnFor(AVisual, lay.Rect, baseHoriz);
      haveCol := True;
    end;
    { A STACKED BAR STANDS ON THE ONE BELOW IT, not on the axis' start.

      Its floor is recomputed as (cumulative - own) rather than read out of the
      stacked-over column, which is what upstream does and for a stated reason:
      barMinHeight can move the drawn END, so the value a bar was stacked over
      is not necessarily where its own segment begins. A member with nothing
      of its own sign below it gets (cumulative - own) = 0: it stands on zero,
      not on the start value -- upstream's own, and documented as such.

      THE BOTTOM MEMBER stacks on nothing (upstream gives it no stackedOn
      series) and stands where an unstacked bar does, on the start value.
      [Revised in batch 36: the bottom member was said to keep "the axis' own
      baseline", the extent start, so as not to move on an axis that does not
      start at zero. Upstream stands it on the start value like any bar; the
      two only looked the same because clip cut both at the plot's edge.] }
    floorPx := baseline;
    if stacked and AStack.HasBelow and not IsNan(own) then
    begin
      { Infinity stacked on Infinity: JavaScript's Inf - Inf, not-a-number,
        where FPC would raise -- and a floor that is not a number is no bar. }
      if baseHoriz then
      begin
        if IsInfinite(y) and IsInfinite(own) then floorV := NaN else floorV := y - own;
      end
      else
      begin
        if IsInfinite(x) and IsInfinite(own) then floorV := NaN else floorV := x - own;
      end;
      if baseHoriz then loPt := ABinding.Cart.DataToPoint([x, floorV])
      else loPt := ABinding.Cart.DataToPoint([floorV, y]);
      if baseHoriz then floorPx := loPt.Y else floorPx := loPt.X;
    end;
    { A FLOOR THE AXIS CANNOT PLACE is no bar: on a log axis a start of 0, or
      a member with nothing of its sign below it, stands on zero, which is
      nowhere, and upstream draws nothing. }
    if IsNan(floorPx) or IsInfinite(floorPx) then Continue;

    { UPSTREAM'S LAYOUT, barGrid.ts: the datum through the coordinate
      system -- its matrix, where there is one -- the column's offset from
      there along the base axis, the floor across it, and a SIGNED length
      from the floor to the datum. }
    p := ABinding.Cart.DataToPoint([x, y]);
    if baseHoriz then
    begin
      lx := p.X + col.Offset;
      ly := floorPx;
      lw := col.Width;
      lh := p.Y - floorPx;
      len := lh;
      { barMinHeight: a zero points up the screen -- `<= 0` }
      if Abs(lh) < col.MinHeightPx then
        if lh <= 0 then lh := -col.MinHeightPx else lh := col.MinHeightPx;
    end
    else
    begin
      lx := floorPx;
      ly := p.Y + col.Offset;
      lw := p.X - floorPx;
      lh := col.Width;
      len := lw;
      { and on a horizontal bar a zero points right -- `< 0` }
      if Abs(lw) < col.MinHeightPx then
        if lw < 0 then lw := -col.MinHeightPx else lw := col.MinHeightPx;
    end;
    if IsNan(lx) or IsNan(ly) or IsNan(lw) or IsNan(lh) then Continue;
    { AN INFINITE LAYOUT -- a value of 'Infinity', which the store now keeps
      as upstream's does -- clips to a not-a-number rect upstream (x + w is
      -Inf + Inf) and draws nothing. Here that sum would raise. }
    if IsInfinite(lx) or IsInfinite(ly) or IsInfinite(lw) or IsInfinite(lh) then
      Continue;

    { showBackground: the bar's own band, stretched over the WHOLE plot along
      the value axis -- BarView.ts:1237-1246. Emitted BEFORE the bar, because
      upstream gives it z2 0 like the bar itself and the two are then ordered
      by insertion; this list ties the same way.

      SILENT. Upstream sets silent:true on it, and it is the right answer for
      the same reason a gridline is silent: a strip the height of the plot
      would take every hover the bar under the pointer was meant to get.

      WHERE THIS AND UPSTREAM PART: a gap in the data gets no strip here --
      upstream reads the band from the layout stage, which keeps it. So a bar
      chart with holes shows a gap in the backing strips too. }
    if col.ShowBackground then
    begin
      bg := LayoutBox(lx, ly, lw, lh);
      plot := ABinding.Cart.GetRect;
      if baseHoriz then
      begin
        bg.Top := plot.Top;
        bg.Bottom := plot.Bottom;
      end
      else
      begin
        bg.Left := plot.Left;
        bg.Right := plot.Right;
      end;
      bgEl := TyChartElement(TyShapeRoundRect(bg, col.BackgroundRadii));
      bgEl.Style.HasFill := True;
      bgEl.Style.FillColor := AVisual.BackgroundFill;
      bgEl.Style.Alpha := 1;
      bgEl.Z := AVisual.Z;
      bgEl.Z2 := AVisual.Z2;
      bgEl.Silent := True;
      AList.Add(bgEl);
      Inc(Result);
    end;

    { clip, default TRUE: a bar whose value runs past the axis' own min or max
      is CUT at the plot edge rather than drawn over the labels. Upstream does
      it by intersecting the layout -- clip.cartesian2d, BarView.ts:684 -- not
      by setting a clip path, so the bar keeps a real rect and the hit test
      keeps agreeing with the ink. Transcribed that way for the same reason.

      AFTER barMinHeight, because that can push the drawn end outward and a
      clip applied first would then be undone.

      A bar clipped past itself -- wholly outside the plot -- is not drawn;
      one of NO LENGTH is: a 0, a value equal to the start or to a pinned
      min, a bar clipped to the plot's very edge. It is a flat rect that
      paints nothing, and it still carries its label.
      [Revised in batch 36: every bar of no length was dropped, and its label
      with it.] }
    if col.Clip and ClipBarLayout(ABinding.Cart.GetArea, lx, ly, lw, lh) then
      Continue;
    r := LayoutBox(lx, ly, lw, lh);

    { A zero-width column draws nothing rather than an invisible rect that is
      still hit-testable -- which is what a bar on a value axis used to be. }
    if baseHoriz then
    begin
      if r.Right - r.Left <= 0 then Continue;
      zero := lh = 0;
    end
    else
    begin
      if r.Bottom - r.Top <= 0 then Continue;
      zero := lw = 0;
    end;
    if TyHasCorner(col.Radii) then
      shape := TyShapeRoundRect(r, col.Radii)
    else
      shape := TyShapeRect(r);
    el := MarkElement(shape, RowVisual(AVisual, AStore, i),
                      ABinding.SeriesIndex, i);
    el.Caption.Text := CaptionFor(AVisual, AStore, i);
    el.Caption.Outside := BarOutside(len, zero, baseHoriz, inverse);
    AList.Add(el);
    Inc(Result);
  end;
end;

function BuildLine(const ABinding: TTySeriesBinding; AStore: TTyDataStore;
  const AStack: TTySeriesStack; const AVisual: TTySeriesVisual;
  AList: TTyPaintList; AColX, AColY: Integer): Integer;
var
  i, n, thinStart: Integer;
  thin: Boolean;
  thinKeep: TTyBoolArray;
  lineClip: TTyRectF;
  symbolArea: TTyXYWH;
  x, y, lowV, startV: Double;
  p, q: TTyPointF;
  pts, lows: TTyPointFArray;
  rows: array of Integer;
  baseHoriz, stacked, gap: Boolean;
  spec: TTyLineSpec;

  { One marker, answering for its own row. False when the symbol draws
    nothing. }
  function EmitSymbol(const AP: TTyPointF; ARow: Integer): Boolean;
  var
    sh: TTyChartShape;
    sv: TTySeriesVisual;
    el: TTyChartElement;
  begin
    Result := False;
    sh := TyBuildSymbol(AVisual.Symbol, AP.X, AP.Y);
    if (sh.Kind = cskRect) and not TyRectFIsValid(sh.Bounds) then Exit;
    sv := AVisual;
    { An `empty` marker is a RING: the series colour becomes the pen and the
      hole is the theme's own ground. A line's default symbol is emptyCircle,
      so this is the ordinary case rather than the exception. }
    if AVisual.Symbol.Empty or (AVisual.Symbol.Kind = tsyLine) then
    begin
      sv.Stroke := AVisual.Fill;
      if sv.StrokeWidthLogical <= 0 then sv.StrokeWidthLogical := 2;
      if AVisual.Symbol.Kind = tsyLine then sv.Fill := 0
      else sv.Fill := AVisual.EmptyFill;
    end;
    el := MarkElement(sh, sv, ABinding.SeriesIndex, ARow);
    el.HitSlopLogical := cHitSlopSymbolLogical;
    el.Caption.Text := CaptionFor(AVisual, AStore, ARow);
    AList.Add(el);
    Result := True;
  end;

  { showAllSymbol. Upstream: 'auto' shows every marker unless one would crowd
    its neighbour -- it compares the symbol's size against the space a single
    category gets, with an empirical 1.5 margin -- and when they would crowd it
    "follows the label interval strategy on the category axis": a marker is
    drawn on a category that has a label, and on no other.
    WHICH CATEGORY, not which point: the row's own value on the category
    axis against the labels' list, from the axis' first category with the
    step the layout worked out, its two off-interval ends left out.
    [Revised in batch 44: this kept every step-th point of the run, which is
    the same thing only while the points start at the axis' first category
    and are one per category -- a min, a max or name-keyed data broke it.] }
  procedure PrepareThinning;
  var
    avail, sz: Double;
    cats, k: Integer;
    e: TTyRange;
    vals: TTyIntegerArray;
    offs: TTyBoolArray;
  begin
    thin := False;
    if AVisual.Line.ShowAllSymbol = sasYes then Exit;
    if ABinding.BaseAxis = nil then Exit;
    if not (ABinding.BaseAxis.Scale is TTyOrdinalScale) then Exit;
    cats := TTyOrdinalScale(ABinding.BaseAxis.Scale).Count;
    if cats <= 0 then Exit;
    if AVisual.Line.ShowAllSymbol = sasAuto then
    begin
      avail := ABinding.BaseAxis.PxLength / cats;
      { The ACROSS size, which is upstream's own index choice: it reads
        symbolSize[1] for a horizontal category axis. Only visible with an
        oblong symbolSize, and transcribed rather than corrected. }
      if baseHoriz then sz := AVisual.Symbol.HeightPx
                   else sz := AVisual.Symbol.WidthPx;
      if sz * 1.5 <= avail then Exit;
    end;
    e := ABinding.BaseAxis.Scale.GetExtent;
    thinStart := Trunc(e.Start);
    TyCategoryBuiltList(thinStart, cats, Max(1, AVisual.Line.LabelStep) - 1,
      vals, offs);
    SetLength(thinKeep, cats);
    for k := 0 to cats - 1 do thinKeep[k] := False;
    for k := 0 to High(vals) do
      if (not offs[k]) and (vals[k] - thinStart >= 0)
        and (vals[k] - thinStart < cats) then
        thinKeep[vals[k] - thinStart] := True;
    thin := True;
  end;

  { UPSTREAM'S createGridClipPath: the plot widened by half the pen each
    way -- so the stroke along an edge is not cut thin -- its width rounded
    up, and a fractional left edge rounded down with a pixel given back on
    the width. The top is left as it falls. With clip off the rect runs
    past the plot along the value axis by its own greater side each way. }
  procedure PrepareClip;
  var
    area: TTyXYWH;
    lw, x, y, w, h, ex: Double;
  begin
    area := ABinding.Cart.GetArea;
    lw := AVisual.StrokeWidthLogical;
    if lw <= 0 then lw := 2;
    x := area.X - lw / 2;
    y := area.Y - lw / 2;
    w := area.W + lw;
    h := area.H + lw;
    w := JsCeil(w);
    if x <> JsFloor(x) then
    begin
      x := JsFloor(x);
      w := w + 1;
    end;
    if not spec.Clip then
    begin
      ex := Max(w, h);
      if baseHoriz then
      begin
        y := y - ex;
        h := h + ex * 2;
      end
      else
      begin
        x := x - ex;
        w := w + ex * 2;
      end;
    end;
    lineClip := TyRectF(x, y, x + w, y + h);
    { and where a marker may be: the plot and a tenth of a pixel, with clip
      on; anywhere with it off }
    symbolArea := area;
    symbolArea.X := symbolArea.X - 0.1;
    symbolArea.Y := symbolArea.Y - 0.1;
    symbolArea.W := symbolArea.W + 0.2;
    symbolArea.H := symbolArea.H + 0.2;
  end;

  function InSymbolArea(const AP: TTyPointF): Boolean;
  begin
    if not spec.Clip then Exit(True);
    Result := (AP.X >= symbolArea.X) and (AP.X <= symbolArea.X + symbolArea.W)
      and (AP.Y >= symbolArea.Y) and (AP.Y <= symbolArea.Y + symbolArea.H);
  end;

  function SymbolKept(ARow: Integer): Boolean;
  var
    v: Double;
    k: Int64;
  begin
    if not thin then Exit(True);
    if baseHoriz then v := AStore.Get(AColX, ARow) else v := AStore.Get(AColY, ARow);
    if IsNan(v) or IsInfinite(v) then Exit(False);
    k := Round(v) - thinStart;
    Result := (k >= 0) and (k <= High(thinKeep)) and thinKeep[k];
  end;

  { Upstream's isPointIllegal: NOT only NaN. Any non-finite coordinate is a
    hole, and an Infinity that reached the paint list would stretch a polyline
    across the whole surface.

    THE IsInfinite HALF IS UNREACHABLE TODAY, and its mutant survives -- worth
    recording rather than hiding behind a contrived test. Upstream needs it
    because ITS log scale answers -Infinity for a non-positive value; ours
    answers NaN (TTyLogScaleMapper.TransformIn exits NaN for AValue <= 0), so
    the NaN half already catches the one case that reaches here. The check
    stays because "a hole is any coordinate that is not finite" is the rule,
    and the next mapper to divide by a zero span will produce one. }
  function Illegal(const AP: TTyPointF): Boolean;
  begin
    Result := IsNan(AP.X) or IsNan(AP.Y)
           or IsInfinite(AP.X) or IsInfinite(AP.Y);
  end;

  { LineView's visualColor in place of the series colour: one colour, or the
    gradient with its first stop as the solid. }
  procedure ApplyVisualLine(var V: TTySeriesVisual; AFill: Boolean);
  var c: TTyChartColor; g: TTyChartGradient;
  begin
    case AVisual.VisualLine.Kind of
      vlfSolid:
        begin
          c := TyVisualToChart(AVisual.VisualLine.Solid);
          g := Default(TTyChartGradient);
        end;
      vlfGradient:
        begin
          g := TyVisualLineGradient(AVisual.VisualLine);
          c := 0;
          if Length(g.Stops) > 0 then c := g.Stops[0].Color;
        end;
    else
      Exit;
    end;
    if AFill then
    begin
      V.Fill := c;
      V.FillGradient := g;
    end
    else
    begin
      V.Stroke := c;
      V.StrokeGradient := g;
    end;
  end;

  { One run, from the points gathered so far. The AREA goes in FIRST so the
    line is drawn over its own fill rather than under it -- the paint list
    breaks ties by insertion order, so first in is furthest back. }
  procedure Flush;
  var
    k, m: Integer;
    up, dn: TTyPointFArray;
    poly: TTyPointFArray;
    v: TTySeriesVisual;
    el: TTyChartElement;
  begin
    if n < 1 then Exit;
    { A RUN OF ONE POINT HAS NO LINE AND NO AREA, but it still has its
      marker -- and so its label. Upstream draws every point's symbol
      whatever the polyline makes of it. [Revised in batch 47: a lone
      point drew nothing at all.] }
    if n >= 2 then
    begin
      SetLength(up, n);
      for k := 0 to n - 1 do up[k] := pts[k];
      up := StepPoints(up, baseHoriz, spec.Step);

      if spec.HasArea then
      begin
        SetLength(dn, n);
        for k := 0 to n - 1 do dn[k] := lows[k];
        { The lower edge is stepped the same way, or the belt would not follow
          the line it belongs to. }
        dn := StepPoints(dn, baseHoriz, spec.Step);
        SetLength(poly, Length(up) + Length(dn));
        for k := 0 to High(up) do poly[k] := up[k];
        { Backwards, so the ring closes along the bottom instead of crossing. }
        m := Length(up);
        for k := High(dn) downto 0 do
        begin
          poly[m] := dn[k];
          Inc(m);
        end;
        v := AVisual;
        v.Stroke := 0;
        v.StrokeWidthLogical := 0;
        { The area's OWN colour when it named one; the series' otherwise. }
        if spec.HasAreaFill then v.Fill := spec.AreaFill;
        { AND ITS OWN RAMP, which REPLACES the series' rather than adding to
          it: an area that named a gradient is that gradient, whatever the
          bars beside it are doing. }
        v.FillGradient := spec.AreaGradient;
        v.StrokeGradient := Default(TTyChartGradient);
        { A visualMap's gradient, unless the area named its own colour. }
        if AVisual.VisualLineArea then ApplyVisualLine(v, True);
        el := MarkElement(TyShapePolygon(poly), v, ABinding.SeriesIndex, -1);
        { The area's opacity REPLACES the series' -- it is a key on its own
          block, not a second multiplier on the item's. }
        el.Style.Alpha := spec.AreaOpacity;
        { SILENT: the fill is decoration behind the line, and a pointer landing
          on it should find the line, not the shading. }
        el.Silent := True;
        el.HasClip := True;
        el.ClipRect := lineClip;
        AList.Add(el);
        Inc(Result);
      end;

      { A LINE IS A STROKE, not a fill. The series colour arrives in Fill because
        that is what a mark's colour is called; for this shape it is the pen. }
      v := AVisual;
      v.Fill := 0;
      { A LINE IS A STROKE, so the ramp moves across with the colour. }
      v.FillGradient := Default(TTyChartGradient);
      if v.StrokeWidthLogical <= 0 then v.StrokeWidthLogical := 2;
      if v.Stroke = 0 then v.Stroke := AVisual.Fill;
      if (v.StrokeGradient.Kind = cgkNone)
        and (AVisual.FillGradient.Kind <> cgkNone) then
        v.StrokeGradient := AVisual.FillGradient;
      { A visualMap's gradient, unless lineStyle named the pen's colour. }
      if AVisual.VisualLineStroke then ApplyVisualLine(v, False);
      el := MarkElement(TyShapePolyline(up), v, ABinding.SeriesIndex, -1);
      { HALF THE PEN PLUS THE RIBBON. `v.StrokeWidthLogical` is already the
        resolved width -- the default 2 was filled in a few lines up. }
      el.HitSlopLogical := v.StrokeWidthLogical / 2 + cHitSlopLineLogical;
      el.HasClip := True;
      el.ClipRect := lineClip;
      AList.Add(el);
      Inc(Result);

    end;

    { THE MARKERS GO ON LAST, so they sit over the line they belong to -- and
      they carry the DATUM, which the polyline cannot: one polyline is a whole
      run, so a pointer over a marker can name its row and a pointer over the
      line between two markers cannot. }
    if spec.ShowSymbol then
      for k := 0 to n - 1 do
        if SymbolKept(rows[k]) and InSymbolArea(pts[k])
          and EmitSymbol(pts[k], rows[k]) then
          Inc(Result);
  end;

begin
  Result := 0;
  baseHoriz := (ABinding.BaseAxis = nil) or ABinding.BaseAxis.Horizontal;
  stacked := AStack.Stacked and (AStack.ResultCol >= 0);
  spec := AVisual.Line;
  startV := AreaStartValue(ABinding.ValueAxis, spec);
  PrepareThinning;
  PrepareClip;
  SetLength(pts, AStore.Count);
  SetLength(lows, AStore.Count);
  SetLength(rows, AStore.Count);
  n := 0;
  for i := 0 to AStore.Count - 1 do
  begin
    x := AStore.Get(AColX, i);
    y := AStore.Get(AColY, i);
    if stacked then
    begin
      if baseHoriz then y := AStore.Get(AStack.ResultCol, i)
                   else x := AStore.Get(AStack.ResultCol, i);
    end;
    { ONE GAP RULE, NOT THREE. A datum that is NaN, a point that will not map,
      and an area baseline that will not map are the same thing to the reader
      of the chart: a hole. The first version broke the run for the first and
      silently DROPPED the other two -- which closes the line straight over the
      hole, the very join that connectNulls being false exists to prevent. }
    gap := IsNan(x) or IsNan(y);
    p := TyPointF(NaN, NaN);
    q := TyPointF(NaN, NaN);
    { AS A SINGLE, both the vertex and the area's lower edge: upstream keeps
      them in a Float32Array, and draws, hovers and puts the symbols where
      that array says }
    if not gap then
    begin
      p := ABinding.Cart.DataToPoint([x, y]);
      p := TyPointF(TyJsFround(p.X), TyJsFround(p.Y));
      gap := Illegal(p);
    end;

    if (not gap) and spec.HasArea then
    begin
      { WHERE THE BELT'S LOWER EDGE IS: the value stacked underneath, and where
        there is none, the origin. Upstream's getStackedOnPoint reads exactly
        this way round, and the NaN test is what makes an unstacked area fall
        to the axis rather than to nothing. }
      lowV := NaN;
      if AStack.Stacked and (AStack.OverCol >= 0) then
        lowV := AStore.Get(AStack.OverCol, i);
      if IsNan(lowV) then lowV := startV;
      if baseHoriz then q := ABinding.Cart.DataToPoint([x, lowV])
                   else q := ABinding.Cart.DataToPoint([lowV, y]);
      q := TyPointF(TyJsFround(q.X), TyJsFround(q.Y));
      gap := Illegal(q);
    end;

    { A GAP BREAKS THE LINE unless connectNulls says otherwise. ECharts
      defaults it to false, because joining by default draws a segment through
      data that does not exist; with it on, the missing points are dropped and
      the run simply continues. }
    if gap then
    begin
      if spec.ConnectNulls then Continue;
      Flush;
      n := 0;
      Continue;
    end;

    if spec.HasArea then lows[n] := q;
    pts[n] := p;
    rows[n] := i;
    Inc(n);
  end;
  Flush;
end;

{ One symbol per datum, and nothing else -- which is the whole of a scatter.

  THE SIZE CAN COME FROM THE DATA. ECharts lets symbolSize be a callback over
  the datum, and a callback cannot survive the trip to JSON; what CAN is a
  third number on the point, which is how a bubble chart is written when the
  option is static. So a row with more columns than the two axes need has its
  next value read as the diameter. }
function BuildScatter(const ABinding: TTySeriesBinding; AStore: TTyDataStore;
  const AStack: TTySeriesStack; const AVisual: TTySeriesVisual;
  AList: TTyPaintList; AColX, AColY: Integer): Integer;
var
  i, sizeCol, valCol: Integer;
  x, y, sz: Double;
  p: TTyPointF;
  spec: TTySymbolSpec;
  shape: TTyChartShape;
  v: TTySeriesVisual;
  el: TTyChartElement;
  baseHoriz, stacked: Boolean;
  area: TTyXYWH;
begin
  Result := 0;
  spec := AVisual.Symbol;
  if spec.Kind = tsyNone then Exit;
  area := ABinding.Cart.GetAreaTol(0.1);
  baseHoriz := (ABinding.BaseAxis = nil) or ABinding.BaseAxis.Horizontal;
  stacked := AStack.Stacked and (AStack.ResultCol >= 0);

  { A third column is a size only when it is not one of the two the axes use.
    Asking the store rather than assuming index 2 keeps this right for a series
    bound to the second y axis. }
  sizeCol := -1;
  for i := 0 to AStore.DimCount - 1 do
    if (i <> AColX) and (i <> AColY) and (AStore.DimType(i) = ddtFloat) then
    begin
      sizeCol := i;
      Break;
    end;

  for i := 0 to AStore.Count - 1 do
  begin
    x := AStore.Get(AColX, i);
    y := AStore.Get(AColY, i);
    if stacked then
    begin
      if baseHoriz then y := AStore.Get(AStack.ResultCol, i)
                   else x := AStore.Get(AStack.ResultCol, i);
    end;
    if IsNan(x) or IsNan(y) then Continue;
    p := ABinding.Cart.DataToPoint([x, y]);
    if IsNan(p.X) or IsNan(p.Y)
      or IsInfinite(p.X) or IsInfinite(p.Y) then Continue;
    { OUTSIDE THE PLOT, WITH CLIP ON, NO MARKER: upstream's getArea(0.1) }
    if AVisual.Line.Clip and not ((p.X >= area.X) and (p.X <= area.X + area.W)
      and (p.Y >= area.Y) and (p.Y <= area.Y + area.H)) then Continue;

    if sizeCol >= 0 then
    begin
      sz := AStore.Get(sizeCol, i);
      if not IsNan(sz) and (sz > 0) then
      begin
        spec.WidthPx := sz;
        spec.HeightPx := sz;
      end;
    end;

    shape := TyBuildSymbol(spec, p.X, p.Y);
    if (shape.Kind = cskRect) and not TyRectFIsValid(shape.Bounds) then Continue;

    { AN `empty` SYMBOL IS STROKED, NOT FILLED -- upstream strokes it in the
      series colour and fills it with the theme's background, and a line symbol
      is stroked too. Both are the same rule: the colour is the pen.
      [Batch 54: the whole row, not only its fill -- a visualMap's opacity is
      the row's too.] }
    v := RowVisual(AVisual, AStore, i);
    if spec.Empty or (spec.Kind = tsyLine) then
    begin
      v.Stroke := v.Fill;
      if v.StrokeWidthLogical <= 0 then v.StrokeWidthLogical := 2;
      if spec.Kind = tsyLine then v.Fill := 0
      else v.Fill := AVisual.EmptyFill;
    end;
    el := MarkElement(shape, v, ABinding.SeriesIndex, i);
    el.HitSlopLogical := cHitSlopSymbolLogical;
    el.Caption.Text := CaptionFor(AVisual, AStore, i);
    AList.Add(el);
    Inc(Result);
  end;
  { The unused local keeps the compiler quiet about valCol in a future edit. }
  valCol := 0;
  if valCol > 0 then ;
end;

function BuildCandlestick(const ABinding: TTySeriesBinding; AStore: TTyDataStore;
  const AStack: TTySeriesStack; const AVisual: TTySeriesVisual;
  AList: TTyPaintList; AColX, AColY: Integer): Integer;
var
  i, colBase, colOpen, colClose, colLow, colHigh: Integer;
  baseHoriz, simple: Boolean;
  band, width, at, openV, closeV, lowV, highV, bodyLo, bodyHi, prevClose: Double;
  sign: Integer;
  fill, border: TTyChartColor;
  v: TTySeriesVisual;
  r: TTyRectF;
  el: TTyChartElement;

  { Where one of the four values lands, along the value axis. }
  function ValueCoord(AValue: Double): Double;
  begin
    Result := NaN;
    if ABinding.ValueAxis = nil then Exit;
    Result := ABinding.ValueAxis.DataToCoord(AValue);
  end;

  procedure Wick(AFrom, ATo: Double);
  var w: TTySeriesVisual; wel: TTyChartElement;
  begin
    if IsNan(AFrom) or IsNan(ATo) or (AFrom = ATo) then Exit;
    w := v;
    w.Fill := 0;
    w.Stroke := border;
    w.StrokeWidthLogical := AVisual.Candle.BorderWidthLogical;
    if w.StrokeWidthLogical <= 0 then w.StrokeWidthLogical := 1;
    if baseHoriz then
      wel := MarkElement(TyShapePolyline([TyPointF(at, AFrom),
        TyPointF(at, ATo)]), w, ABinding.SeriesIndex, i)
    else
      wel := MarkElement(TyShapePolyline([TyPointF(AFrom, at),
        TyPointF(ATo, at)]), w, ABinding.SeriesIndex, i);
    AList.Add(wel);
    Inc(Result);
  end;

begin
  Result := 0;
  if (AStore = nil) or (ABinding.BaseAxis = nil) then Exit;
  baseHoriz := ABinding.BaseAxis.Horizontal;
  colBase := AColX;
  if not baseHoriz then colBase := AColY;
  colOpen := AStore.DimIndexOf('open');
  colClose := AStore.DimIndexOf('close');
  colLow := AStore.DimIndexOf('lowest');
  colHigh := AStore.DimIndexOf('highest');
  if (colOpen < 0) or (colClose < 0) or (colLow < 0) or (colHigh < 0) then Exit;

  { THE BODY IS HALF A BAND WIDE, and that is the candlestick's own rule --
    not the bar layouter's. Upstream solves it as `max(min(band/2, barMaxWidth),
    barMinWidth)` with the two limits defaulting to the band and to one pixel,
    which collapses to half a band and a floor of one. It does NOT share the
    band with bar series: a candlestick beside a bar overlaps it deliberately,
    because the two are reading the same thing. }
  band := ABinding.BaseAxis.BandWidth;
  if band <= 0 then band := 8;
  width := Max(Double(1), band / 2);
  { A CANDLE NARROWER THAN A PEN IS A LINE. Upstream calls it a simple box and
    switches at 1.3 px -- below that the body has no inside to fill and the
    wick and the body are the same stroke. }
  simple := width <= 1.3;

  prevClose := NaN;
  for i := 0 to AStore.Count - 1 do
  begin
    openV := AStore.Get(colOpen, i);
    closeV := AStore.Get(colClose, i);
    lowV := AStore.Get(colLow, i);
    highV := AStore.Get(colHigh, i);
    at := ABinding.BaseAxis.DataToCoord(AStore.Get(colBase, i));
    if IsNan(at) or IsNan(openV) or IsNan(closeV) then
    begin
      prevClose := closeV;
      Continue;
    end;

    { THE SIGN, and the third case is the one a port forgets. Open above close
      is down, close above open is up -- and EQUAL is a doji, which upstream
      resolves against the PREVIOUS row's close so a flat bar takes the
      direction of the move that led into it. The first row has no previous
      and is up. Only a written `borderColorDoji` gives it a colour of its
      own. }
    if openV > closeV then sign := -1
    else if openV < closeV then sign := 1
    else if AVisual.Candle.HasDojiBorder then sign := 0
    else if IsNan(prevClose) then sign := 1
    else if prevClose <= closeV then sign := 1
    else sign := -1;
    prevClose := closeV;

    if sign >= 0 then
    begin
      fill := AVisual.Candle.Up;
      border := AVisual.Candle.UpBorder;
    end
    else
    begin
      fill := AVisual.Candle.Down;
      border := AVisual.Candle.DownBorder;
    end;
    if (sign = 0) and AVisual.Candle.HasDojiBorder then
      border := AVisual.Candle.DojiBorder;

    v := AVisual;
    v.Fill := fill;
    v.Stroke := border;
    v.StrokeWidthLogical := AVisual.Candle.BorderWidthLogical;

    bodyLo := ValueCoord(Min(openV, closeV));
    bodyHi := ValueCoord(Max(openV, closeV));
    if IsNan(bodyLo) or IsNan(bodyHi) then Continue;

    if simple then
      { No body to speak of: one stroke from lowest to highest. }
      Wick(ValueCoord(lowV), ValueCoord(highV))
    else
    begin
      { THE WICK IS TWO SEGMENTS, not one line behind the body. They look the
        same under an opaque candle and not at all the same under a hollow
        one -- and a hollow candle is how half the world draws a rising bar. }
      Wick(ValueCoord(highV), bodyHi);
      Wick(ValueCoord(lowV), bodyLo);
      if baseHoriz then
        r := TyRectF(at - width / 2, Min(bodyLo, bodyHi),
                     at + width / 2, Max(bodyLo, bodyHi))
      else
        r := TyRectF(Min(bodyLo, bodyHi), at - width / 2,
                     Max(bodyLo, bodyHi), at + width / 2);
      { A DOJI HAS NO BODY AT ALL -- open equals close, so the rect is a line.
        Given a whole pixel so the stroke has something to sit on, which is
        what upstream's own sub-pixel pass does for the same case. }
      if baseHoriz and (r.Bottom - r.Top < 1) then r.Bottom := r.Top + 1;
      if (not baseHoriz) and (r.Right - r.Left < 1) then r.Right := r.Left + 1;
      el := MarkElement(TyShapeRect(r), v, ABinding.SeriesIndex, i);
      { NO CAPTION. Upstream's candlestick view never builds a label, whatever
        label.show says -- the option is accepted and draws nothing. }
      AList.Add(el);
      Inc(Result);
    end;
  end;
  { AStack and AColY are read only on the paths above; naming them keeps the
    builder's signature the one the table holds. }
  if AStack.Stacked and (AColY < -1) then ;
end;

{ ==================== the pictorial bar ==================== }

{ A bar whose rectangle is never drawn.

  IT SHARES THE WHOLE BAR LAYOUT -- the same band, the same column, the same
  offset, the same stack -- and then replaces the rectangle with a glyph, or
  with a column of glyphs. FOUR RECTANGLES where a bar has one, and the
  arithmetic relating them lives next door in AdvChart.Pictorial where it can
  be asserted without a chart; what is left here is which pixel each lands on.

  ALONG AND ACROSS, NEVER X AND Y. The base axis is the spine: a horizontal
  bar chart counts its glyphs along x and its band along y, and writing the
  two orientations out twice is how one of them comes out mirrored. }
function BuildPictorialBar(const ABinding: TTySeriesBinding;
  AStore: TTyDataStore; const AStack: TTySeriesStack;
  const AVisual: TTySeriesVisual; AList: TTyPaintList;
  AColX, AColY: Integer): Integer;
const
  { WIDER THAN ANY CANVAS. Upstream's clip spans the whole drawing surface
    across the bar -- only the value axis is meant to cut -- and this builder
    has no way to ask how big that surface is. A number larger than all of
    them draws the same picture without pretending to one it cannot have. }
  cUnclippedHalf = 1000000;
var
  spec: TTyPictorialSpec;
  i, k, idx, valCol, n: Integer;
  baseHoriz, stacked, haveCol, mirror, pxUp, empty: Boolean;
  x, y, own, baseline, zeroPx, floorPx, valuePx: Double;
  cutLen, boundLen, pxSign, categorySize, acrossCentre: Double;
  glyphW, glyphH, glyphLen, valueBase, anchor, sizeFix, along: Double;
  offX, offY, offAlong, offAcross, e0, e1, barLen: Double;
  lay: TTyCoordLayout;
  plot, barRect, clipRect: TTyRectF;
  col: TTyBarColumn;
  run: TTyPictorialRun;
  sym: TTySymbolSpec;
  v: TTySeriesVisual;
  el: TTyChartElement;
  shape: TTyChartShape;
  pt: TTyPointF;
  body: string;

  { One of the four rectangles, from a centre and a half-extent on each of the
    two axes. Written once because the pair is the same rule with the roles
    swapped, and writing it twice is how a horizontal chart ends up mirrored. }
  function BandRect(AAlong, AAlongHalf, AAcross, AAcrossHalf: Double): TTyRectF;
  begin
    if baseHoriz then
      Result := TyRectF(AAcross - AAcrossHalf, AAlong - AAlongHalf,
                        AAcross + AAcrossHalf, AAlong + AAlongHalf)
    else
      Result := TyRectF(AAlong - AAlongHalf, AAcross - AAcrossHalf,
                        AAlong + AAlongHalf, AAcross + AAcrossHalf);
  end;

begin
  Result := 0;
  if (AList = nil) or (AStore = nil) then Exit;
  if (ABinding.Cart = nil) or (ABinding.ValueAxis = nil) then Exit;
  baseHoriz := (ABinding.BaseAxis = nil) or ABinding.BaseAxis.Horizontal;
  stacked := AStack.Stacked and (AStack.ResultCol >= 0);
  if baseHoriz then valCol := AColY else valCol := AColX;
  plot := ABinding.Cart.GetRect;
  haveCol := False;
  col := Default(TTyBarColumn);

  { THE LINE A BAR STANDS ON -- the axis' start value, the same one
    DataToLayout built its cell from: zero, 1 on a log axis, or what
    startValue says, and not the axis' min. Asked again here because the
    cell's Min/Max threw away which of its two ends it was. }
  baseline := ABinding.ValueAxis.DataToCoord(
    TyValueAxisStart(ABinding.ValueAxis));
  if IsNan(baseline) or IsInfinite(baseline) then Exit;
  { AND THE ZERO LINE, which is a DIFFERENT question: it is the only thing
    symbolBoundingData is measured from, and on a stacked bar or an axis that
    never reaches zero the two are not the same place. Upstream asks the axis
    for data value zero unconditionally; on a log axis that is minus infinity,
    so a value the axis cannot place falls back to the baseline rather than
    poisoning every coordinate downstream. }
  zeroPx := ABinding.ValueAxis.DataToCoord(0);
  if IsNan(zeroPx) or IsInfinite(zeroPx) then zeroPx := baseline;
  { WHETHER PIXELS GROW WITH THE VALUE. It settles one thing only -- the tie
    at a bounding length of exactly zero -- and upstream splits that tie so a
    glyph on an empty bar still faces the way positive values go. }
  pxUp := (not baseHoriz) <> ABinding.ValueAxis.Inverse;

  for i := 0 to AStore.Count - 1 do
  begin
    x := AStore.Get(AColX, i);
    y := AStore.Get(AColY, i);
    own := AStore.Get(valCol, i);
    if stacked then
    begin
      if baseHoriz then y := AStore.Get(AStack.ResultCol, i)
                   else x := AStore.Get(AStack.ResultCol, i);
    end;
    { A GAP DRAWS NOTHING -- not a bar of no length, which would read as a real
      measurement of nothing.

      A MUTANT OF THIS LINE SURVIVES, and it is recorded here rather than
      chased, exactly as BuildBars records the identical one: the rect that
      comes back for a NaN datum fails TyRectFIsValid four lines down, so the
      gap is dropped either way. The check states the rule where the rule
      applies; it is not, today, the thing enforcing it. }
    if IsNan(x) or IsNan(y) then Continue;
    { THE ROW'S OWN OPTIONS FIRST, because every one of them is per-datum
      upstream -- and one of them decides the glyph's size, so reading them
      after the size was solved would read them for nothing. }
    spec := TyPictorialRowSpec(AVisual.Pictorial, AStore, i);
    lay := ABinding.Cart.DataToLayout([x, y]);
    if not TyRectFIsValid(lay.Rect) then Continue;
    if not haveCol then
    begin
      col := ColumnFor(AVisual, lay.Rect, baseHoriz);
      { AN UNSOLVED COLUMN IS A BAR'S, AND THIS TYPE'S CLIP IS THE OPPOSITE
        ONE. ColumnFor falls back to what a lone DEFAULT BAR gets, which is
        the right width and the wrong clip: `clip` is false for a pictorial
        bar and true for a bar. A caller that ran no solver should get this
        type's own default rather than its neighbour's. }
      if not AVisual.Bar.Solved then col.Clip := False;
      haveCol := True;
    end;
    pt := ABinding.Cart.DataToPoint([x, y]);
    if baseHoriz then valuePx := pt.Y else valuePx := pt.X;
    if IsNan(valuePx) or IsInfinite(valuePx) then Continue;

    { A STACKED GLYPH COLUMN STANDS ON THE ONE BELOW IT, and its floor is
      recomputed as (cumulative - own) for the reason BuildBars states beside
      the same expression: barMinHeight can move a segment's DRAWN end, so the
      value it was stacked over is not where the one below it finished. }
    floorPx := baseline;
    if stacked and AStack.HasBelow and not IsNan(own) then
    begin
      { through the coordinate system, as a bar's stacked floor is -- its
        matrix, where there is one }
      if baseHoriz then floorPx := ABinding.Cart.DataToPoint([x, y - own]).Y
      else floorPx := ABinding.Cart.DataToPoint([x - own, y]).X;
      if IsNan(floorPx) or IsInfinite(floorPx) then Continue;
    end;
    cutLen := valuePx - floorPx;

    { THE COLUMN ACROSS THE BAR, as barGrid lays it: the datum's point on the
      base axis plus the column's offset, the column's width, and the glyphs
      on its middle -- upstream's layout[xy] + layout[wh] / 2 }
    categorySize := Abs(col.Width);
    if baseHoriz then acrossCentre := pt.X + col.Offset + col.Width / 2
    else acrossCentre := pt.Y + col.Offset + col.Width / 2;
    { A COLLAPSED COLUMN DRAWS NOTHING, the same answer a bar gives: every
      percentage across the bar would be a percentage of nothing. }
    if categorySize <= 0 then Continue;

    { THE BOUNDING LENGTH, four branches in upstream's own order. Written
      bounding data wins; failing that a repeat fills the plot; failing that
      it is the bar's own length. }
    if spec.BoundHas = 2 then
    begin
      e0 := ABinding.ValueAxis.DataToCoord(spec.BoundA) - zeroPx;
      e1 := ABinding.ValueAxis.DataToCoord(spec.BoundB) - zeroPx;
      if IsNan(e0) or IsNan(e1) or IsInfinite(e0) or IsInfinite(e1) then Continue;
      { SORTED IN PIXELS, not in values. The pair was sorted as numbers when it
        was read, but the axis may run either way, so which of the two is the
        far end is a question only the coordinates can answer. }
      if e1 < e0 then
      begin
        boundLen := e0;
        e0 := e1;
        e1 := boundLen;
      end;
      if cutLen > 0 then boundLen := e1 else boundLen := e0;
    end
    else if spec.BoundHas = 1 then
    begin
      boundLen := ABinding.ValueAxis.DataToCoord(spec.BoundA) - zeroPx;
      if IsNan(boundLen) or IsInfinite(boundLen) then Continue;
    end
    else if spec.Repeat_ <> prNone then
    begin
      { A REPEAT WITH NO BOUNDING DATA FILLS THE PLOT, and is then cut back by
        the count pass or shown through the clip. The edge taken is the far one
        in the bar's own direction. }
      if baseHoriz then
      begin
        if cutLen > 0 then boundLen := plot.Bottom - zeroPx
        else boundLen := plot.Top - zeroPx;
      end
      else
      begin
        if cutLen > 0 then boundLen := plot.Right - zeroPx
        else boundLen := plot.Left - zeroPx;
      end;
    end
    else
      boundLen := cutLen;

    { NEVER ZERO, and upstream says why beside it: a zero sign makes the
      glyph's scale zero, and a zero scale makes an unscaled stroke width not
      a number. A bar of no length still points the way positive values go. }
    if pxUp then
    begin
      if boundLen >= 0 then pxSign := 1 else pxSign := -1;
    end
    else
    begin
      if boundLen > 0 then pxSign := 1 else pxSign := -1;
    end;

    { WHAT A PERCENTAGE IS A PERCENTAGE OF, and the two axes do not agree.
      ACROSS the bar it is always the column's own width. ALONG it, the
      bounding length -- unless the glyph repeats, in which case it is the
      column width again, which is what makes a repeating glyph come out
      roughly square and march along the bar instead of stretching down it. }
    if spec.Repeat_ <> prNone then valueBase := categorySize
    else valueBase := Abs(boundLen);
    if baseHoriz then
    begin
      glyphW := TyBoxResolve(spec.SizeW, categorySize);
      glyphH := TyBoxResolve(spec.SizeH, valueBase);
      glyphLen := glyphH;
    end
    else
    begin
      glyphW := TyBoxResolve(spec.SizeW, valueBase);
      glyphH := TyBoxResolve(spec.SizeH, categorySize);
      glyphLen := glyphW;
    end;
    if IsNan(glyphW) or IsNan(glyphH) then Continue;
    if IsInfinite(glyphW) or IsInfinite(glyphH) then Continue;
    if (glyphW <= 0) or (glyphH <= 0) then Continue;

    { UPSTREAM ADDS THE GLYPH'S OWN STROKE to the unit length, so a bordered
      symbol takes its border's worth of room in a repeating column. NOT done
      here, and the reason is written down rather than hidden: a stroke width
      is LOGICAL until the renderer scales it by the screen's PPI, and this
      builder works in device pixels. Folding a logical number in would draw
      the right count at 96 dpi and the wrong one on every other screen. }
    run := TyPictorialRunOf(spec, glyphLen, boundLen, cutLen, glyphLen);
    if run.Count <= 0 then Continue;
    if IsNan(run.PathLen) or IsInfinite(run.PathLen) then Continue;
    if IsNan(run.Unit_) or IsInfinite(run.Unit_) then Continue;

    { WHERE THE RUN SITS ALONG THE BAR, measured from the bar's own floor.
      `start` puts the glyph's near edge on that floor, `end` puts its far
      edge on the far end of the bounding region, `center` centres it there --
      and sizeFix carries the sign, so none of the three means left or right. }
    sizeFix := pxSign * run.PathLen / 2;
    case spec.Position of
      pspEnd: anchor := boundLen - sizeFix;
      pspCentre: anchor := boundLen / 2;
    else
      anchor := sizeFix;
    end;

    { THE OFFSET IS IN SCREEN X AND Y AND IS NOT REMAPPED, upstream, so on a
      horizontal bar chart `symbolOffset` still moves the glyph the way the
      author's own x and y point rather than along the bar. Each component is
      a percentage of the glyph's size on the SAME screen axis. }
    offX := 0;
    offY := 0;
    if spec.HasOffset then
    begin
      offX := TyBoxResolve(spec.OffsetX, glyphW);
      offY := TyBoxResolve(spec.OffsetY, glyphH);
      if IsNan(offX) or IsInfinite(offX) then offX := 0;
      if IsNan(offY) or IsInfinite(offY) then offY := 0;
    end;
    if baseHoriz then
    begin
      offAlong := offY;
      offAcross := offX;
    end
    else
    begin
      offAlong := offX;
      offAcross := offY;
    end;
    anchor := anchor + offAlong;

    { THE BAR RECT: the union of the data's own length and the far end of the
      glyph run, and the ONLY thing here a pointer can land on. Upstream keeps
      the same rectangle for the same two reasons -- an outside label has to
      clear the icon rather than the value, and what a reader points at should
      be the bar rather than whichever half of a glyph survived the clip. }
    barLen := pxSign * Max(Abs(cutLen), Abs(anchor + sizeFix));
    if IsNan(barLen) or IsInfinite(barLen) then Continue;
    barRect := BandRect(floorPx + barLen / 2, Abs(barLen) / 2,
                        acrossCentre, categorySize / 2);
    el := TyChartElement(TyShapeRect(barRect));
    { NO INK AT ALL. It is a target and a label anchor, not a picture -- and
      the tooltip's swatch skips inkless elements for exactly this reason, so
      the dot still takes the glyph's colour rather than this rect's nothing. }
    el.Style.HasFill := False;
    el.Style.FillColor := 0;
    el.Style.StrokeColor := 0;
    el.Style.StrokeWidthLogical := 0;
    el.Style.Alpha := AVisual.Alpha;
    el.Z := AVisual.Z;
    el.Z2 := AVisual.Z2;
    el.Silent := False;
    el.Datum := TyChartDatum(ABinding.SeriesIndex, i);
    el.Caption.Text := CaptionFor(AVisual, AStore, i);
    { FILLED BUT TRANSPARENT, for its label: upstream's target rect has a
      `transparent` fill, which counts as a fill. }
    el.Caption.HostTransparent := True;
    AList.Add(el);
    Inc(Result);

    { TWO CLIPS, AND THEY MEET IN ONE RECTANGLE.

      symbolClip IS ALONG THE VALUE AXIS AND NOWHERE ELSE: from the bar's floor
      to the value the data actually paid for. A repeat draws its whole column
      at bounding size and this is what reveals the part that was earned.

      `clip` IS THE PLOT, and it is a different question with a different
      default -- false for this type, true for a bar, because a pictorial chart
      usually hides its axes and a glyph taller than its value is meant to
      stand proud. A bar answers it by SHRINKING its rectangle; a glyph cannot,
      because half a glyph is not a smaller glyph.

      The intersection is taken here rather than in two passes so the element
      carries one rectangle, which is all the renderer's state stack wants. }
    clipRect := TyRectF(-cUnclippedHalf, -cUnclippedHalf,
                        cUnclippedHalf, cUnclippedHalf);
    if spec.Clip then
      clipRect := BandRect(floorPx + cutLen / 2, Abs(cutLen) / 2,
                           acrossCentre, cUnclippedHalf);
    if col.Clip then
      clipRect := TyRectF(Max(clipRect.Left, plot.Left),
                          Max(clipRect.Top, plot.Top),
                          Min(clipRect.Right, plot.Right),
                          Min(clipRect.Bottom, plot.Bottom));

    sym := AVisual.Symbol;
    { THE SERIES' OWN `symbol`, resolved here rather than taken from the shared
      symbol spec, because a pictorialBar's default is a SOLID circle while
      every other series' is the line's hollow one. A glyph that came out as a
      ring would read as a missing fill rather than as a choice. }
    if spec.SymbolName <> '' then
    begin
      sym.Kind := TySymbolKindOf(spec.SymbolName, empty, body);
      sym.Empty := empty;
      sym.PathData := body;
    end
    else
    begin
      sym.Kind := tsyCircle;
      sym.Empty := False;
      sym.PathData := '';
    end;
    if sym.Kind = tsyNone then Continue;
    sym.WidthPx := glyphW;
    sym.HeightPx := glyphH;
    sym.KeepAspect := spec.KeepAspect;
    { THE OFFSET IS ALREADY IN THE ANCHOR and in acrossCentre. Leaving it on
      the spec as well would move every glyph twice. }
    sym.OffsetX := 0;
    sym.OffsetY := 0;

    { THE GLYPH IS MIRRORED, not turned end for end, when the bar points the
      other way: upstream multiplies the scale along the value axis by
      (isHorizontal ? -1 : 1) * pxSign, and a negative scale is a reflection.
      It happens on negative values and on an inverted axis, and it is why an
      arrow below the line points down.

      A MIRROR AND A ROTATION DO NOT COMMUTE, so the angle is negated and the
      reflection applied afterwards. That is the same transform, not an
      approximation: reflecting about a coordinate axis turns a rotation into
      its opposite, so M(R(-a)) and R(a)(M) are one and the same. }
    mirror := baseHoriz = (pxSign > 0);
    if mirror then sym.RotateDeg := -spec.RotateDeg
    else sym.RotateDeg := spec.RotateDeg;

    v := RowVisual(AVisual, AStore, i);
    { AN `empty` SYMBOL IS STROKED, NOT FILLED, and a line symbol is stroked
      too -- the same rule the scatter follows, because the colour is the pen
      in both. }
    if sym.Empty or (sym.Kind = tsyLine) then
    begin
      v.Stroke := v.Fill;
      if v.StrokeWidthLogical <= 0 then v.StrokeWidthLogical := 2;
      if sym.Kind = tsyLine then v.Fill := 0
      else v.Fill := AVisual.EmptyFill;
    end;

    n := run.Count;
    for k := 0 to n - 1 do
    begin
      { A SLOT IS GEOMETRY; THE INDEX IS ORDER. Reversing the direction changes
        only which glyph is created first and therefore which is on top --
        upstream says as much beside the same expression, because the
        positions it produces are symmetric. }
      if spec.RepeatFromStart = (pxSign > 0) then idx := n - 1 - k
      else idx := k;
      along := TyPictorialSlot(run, idx, anchor);
      if IsNan(along) or IsInfinite(along) then Continue;
      if baseHoriz then
        pt := TyPointF(acrossCentre + offAcross, floorPx + along)
      else
        pt := TyPointF(floorPx + along, acrossCentre + offAcross);
      shape := TyBuildSymbol(sym, pt.X, pt.Y);
      if (shape.Kind = cskRect) and not TyRectFIsValid(shape.Bounds) then Continue;
      if mirror then
        shape := TyMirrorShape(shape, pt.X, pt.Y, not baseHoriz, baseHoriz);
      el := MarkElement(shape, v, ABinding.SeriesIndex, i);
      el.HasClip := spec.Clip or col.Clip;
      el.ClipRect := clipRect;
      { SILENT, and the bar rect above is why: two hittable things for one
        datum would report it twice, and a glyph cut in half is the worse of
        the two targets. }
      el.Silent := True;
      AList.Add(el);
      Inc(Result);
    end;
  end;
end;

const
  { THE ONE LIST. Five of the twenty-three types draw; a renderer arrives as
    a row here and both the drawing and the published answer follow from it.

    Type names are compared EXACTLY, the way TySeriesFindType compares them --
    ECharts' names are case-sensitive, so a series typed 'Bar' never resolves
    and never reaches this unit. A lenient match here would answer yes for a
    chart that draws nothing. }
  cRenderers: array[0..4] of record
    Name: string;
    Build: TTyMarkBuilder;
  end = (
    (Name: 'bar';                       Build: @BuildBars),
    (Name: 'line';                      Build: @BuildLine),
    (Name: 'scatter';                   Build: @BuildScatter),
    (Name: 'candlestick';               Build: @BuildCandlestick),
    (Name: TyPictorialSeriesTypeName;   Build: @BuildPictorialBar));

  { AND THE ONES DRAWN SOMEWHERE ELSE. A pie is not on a coordinate system,
    so its geometry is solved in AdvChart.Pie and never reaches this unit --
    but the question the editor asks is `will this series appear`, and an
    answer that covered only one of the two passes would tell the author a
    pie chart paints nothing while the pie sits there on the canvas.

    A SECOND LIST IS A SECOND THING THAT CAN DRIFT, and the loop in
    TestThePublishedAnswerMatchesTheDrawing cannot check this half -- it
    drives TyBuildSeriesMarks, which a pie deliberately never enters. What
    guards it is TestAPieIsDrawnOffItsOwnCentreWithAColourPerSector, which
    counts the control's own pixels. }
  cElsewhere: array[0..4] of string = ('pie', 'funnel', 'gauge', 'radar',
                                       'graph');

function RendererFor(const AType: string): TTyMarkBuilder;
var i: Integer;
begin
  for i := 0 to High(cRenderers) do
    if cRenderers[i].Name = AType then Exit(cRenderers[i].Build);
  Result := nil;
end;

function TyRowFill(const AVisual: TTySeriesVisual; AStore: TTyDataStore;
  ARow: Integer): TTyChartColor;
begin
  Result := RowVisual(AVisual, AStore, ARow).Fill;
end;

function TySeriesTypeHasRenderer(const AType: string): Boolean;
var i: Integer;
begin
  if RendererFor(AType) <> nil then Exit(True);
  for i := 0 to High(cElsewhere) do
    if cElsewhere[i] = AType then Exit(True);
  Result := False;
end;

{ The first store column feeding one axis, or -1. }
function FirstColumnOn(AStore: TTyDataStore; AAxis: TTyAxis): Integer;
var cols: TTyIntegerArray;
begin
  Result := -1;
  if (AStore = nil) or (AAxis = nil) then Exit;
  cols := AStore.DimsOfCoord(AAxis.Dim);
  if Length(cols) > 0 then Result := cols[0];
end;

function TyBuildSeriesMarks(const ABinding: TTySeriesBinding;
  AStore: TTyDataStore; const AStack: TTySeriesStack;
  const AVisual: TTySeriesVisual; AList: TTyPaintList): Integer;
var
  colX, colY: Integer;
  build: TTyMarkBuilder;
begin
  Result := 0;
  if (AList = nil) or (AStore = nil) then Exit;
  if not ABinding.Resolved then Exit;
  { No axes is a legitimate resolved state -- a pie is not on any -- and this
    unit only knows how to draw on a cartesian. }
  if (not ABinding.HasAxes) or (ABinding.Cart = nil) then Exit;
  if (ABinding.XAxis = nil) or (ABinding.YAxis = nil) then Exit;

  { The store's columns are the coordinate dimensions in axis order, so an axis
    names its own column. Asking the store rather than assuming 0 and 1 is what
    keeps this correct for a series on the second y axis.

    THE FIRST of however many. A candlestick puts four columns on its value
    axis and none of them is called `y`, so a lookup by name alone answered
    -1 and the series left through the guard below without ever reaching its
    own renderer -- which drew nothing, said nothing, and looked exactly like
    a type with no renderer at all. }
  colX := FirstColumnOn(AStore, ABinding.XAxis);
  colY := FirstColumnOn(AStore, ABinding.YAxis);
  if (colX < 0) or (colY < 0) then Exit;

  { Anything not in the table draws nothing, on purpose: twenty-one of the
    twenty-three series types have no renderer yet, and the control's
    diagnostics are what say so. Drawing an approximation would be worse than
    drawing nothing. }
  build := RendererFor(ABinding.SeriesType);
  if build <> nil then
    Result := build(ABinding, AStore, AStack, AVisual, AList, colX, colY);
end;

end.
