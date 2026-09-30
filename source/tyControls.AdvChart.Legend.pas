unit tyControls.AdvChart.Legend;
{$mode objfpc}{$H+}
{ The legend -- the component that names the series and, once it can be
  clicked, decides which of them are drawn.

  103 of the 244 converted examples carry one, which is more than any other
  optional component; 21 of them write nothing but `legend: {}`, so the
  DEFAULTS are most of the feature. They are `left: 'center'`, `bottom: 15`,
  `itemGap: 8`, `itemWidth: 25`, `itemHeight: 14`, `padding: 5` -- and the
  generated option catalog is wrong about four of those (it says `left: auto`,
  `bottom: auto`, `itemGap: 10`, `borderWidth: 1`), so a legend seeded from the
  catalog would sit in the top-left corner instead of centred on the bottom
  edge. Read from src/component/legend/LegendModel.ts, ECharts 6.1.0.

  IT DOES NOT SHRINK THE GRID, for the same reason the title does not: upstream
  gives every component the same container and lets sensible defaults keep them
  apart. The grid's own default bottom gap is what leaves room for a legend.

  WHAT IS NOT HERE, and none of it is an oversight:

    THE CLICK. Drawing a legend and toggling one are two different jobs and the
    second needs machinery this control does not have yet -- a mouse path, a hit
    test, and a full re-layout on every toggle. NOTHING HIT-TESTS ANYTHING in
    this control yet: the paint list's HitTest has no production caller and the
    list is freed at the end of the frame that built it. When the click lands it
    must also set the control's dirty flag and drop the static layer, because a
    plain repaint runs neither Rebuild nor Relayout and the filter below would
    never re-run.
    [Stale since the tooltip batches: the paint list IS hit-tested now --
    HitTestAt serves the tooltip and the hover. The click itself is still not
    here, and the rest of this paragraph stands.]

    What IS here is everything decided before anyone clicks: `legend.selected`,
    the `selectedMode: 'single'` resolution that upstream performs AT LOAD, the
    inactive styling, and the FILTER those imply. Those are static option state,
    and a legend that ignored them would draw the wrong picture on the FIRST
    frame, which is a different kind of wrong from being inert.

    THE SELECTOR BUTTONS and the SCROLLING (`type: 'scroll'`) LEGEND. Both are
    controls -- an All/Inverse pair and a pager -- and an inert control is worse
    than an absent one. They land with the click. Two corpus examples ask for
    `type: 'scroll'` and get a plain legend that overflows instead.

    A `line` ICON WITH A VISIBLE PEN. Upstream draws `legend.icon: 'line'`
    on a bar or a pie as NOTHING AT ALL, and by a route worth naming:
    `itemStyle.borderWidth: 'auto'` resolves to 0 unless the SERIES has a
    border, `itemStyle.stroke: 'inherit'` resolves to the series' own stroke
    which is absent, and a path with neither pen nor width draws no line. The
    rule is a consequence of reading `series.itemStyle`, which this port does
    not do yet -- so transcribing the invisible half of it now would hide the
    icon for a reason that does not exist here. A line icon draws a line; when
    series item styles land, this becomes a real question.

    THE OPTION'S OWN COLOURS. `textStyle.color`, `inactiveColor`,
    `backgroundColor` and the `itemStyle`/`lineStyle` colour sentinels are not
    read, because nothing in this port reads a colour out of an option yet --
    not `color`, not `series.itemStyle.color` either. Every colour comes from
    the theme. When the palette row lands it brings a colour parser and serves
    all of them at once; reading one block early would mean a legend that obeys
    `legend.textStyle.color` while the series beside it ignores
    `series.itemStyle.color`.
    [Stale: the palette row landed (AdvChart.Color) and the series' colours,
    a visualMap's included, are read from the option now; the legend reads
    whether it has a `backgroundColor`. Its own text, inactive and swatch
    colours are still the theme's.]

  THE FILTER, and where it lives. `TyLegendHides` is the whole rule this unit
  contributes; the control applies it, because what a switched-off name MEANS
  depends on what kind of series wears it:

    A SERIES is flagged and every solver downstream skips it, so the axis
    extents, the stack groups and the bar widths all come from the survivors.
    A legend that stopped drawing a series but left the axis sized for it
    would leave the survivor a sliver -- which a reader would call broken.

    A PIE is filtered ONE ROW AT A TIME, because its legend names slices and
    not the series. That is upstream's split too: legendFilter removes whole
    series, processor/dataFilter removes rows.

  Both run BEFORE anything is counted -- upstream puts legendFilter at
  priority 800 with the stack pass at 900 and the axis statistics at 920, and
  says in a comment why that order and no other.

  PURE: SysUtils, Math, fpjson and the AdvChart units. Text is MEASURED through
  the injected measurer; ink and fonts arrive resolved from the theme. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Shape, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Symbol, tyControls.AdvChart.Paint;

type
  TTyLegendOrient = (tloHorizontal, tloVertical);
  { Resolved, never tlaAuto by the time a caller sees a layout. }
  TTyLegendAlign = (tlaAuto, tlaLeft, tlaRight);
  { `false`, `true`, `'single'`, `'multiple'`. Upstream tests for `'single'` and
    for nothing else, so `'multiple'` and `true` are the same value; `false`
    only silences the item, which is why it is indistinguishable from
    tlsMultiple until the click exists. }
  TTyLegendSelectedMode = (tlsMultiple, tlsSingle, tlsOff);

  TTyLegendFont = record
    Name: string;
    SizeLogical: Integer;
    Weight: Integer;
  end;

  { One row of `legend.data`, or one name the chart offered when there is no
    `legend.data`. }
  TTyLegendEntry = record
    Name: string;
    { `legend.data[i].icon`; '' when the row did not name one. The ABSENCE
      matters: an absent icon and `icon: 'roundRect'` take different branches,
      because only the absent one lets a line series draw its own. }
    Icon: string;
    { `''` and a lone newline are not items at all -- they are line breaks. }
    Newline: Boolean;
  end;
  TTyLegendEntryArray = array of TTyLegendEntry;
  TTyLegendFlags = array of Boolean;
  { The names a chart offers a legend. Named because the two lists that
    matter -- what a legend falls back to and what it is allowed to match --
    cross a procedure boundary. }
  TTyLegendNames = array of string;

  { What the chart can say about one name. Filled in by the control, because
    this unit asks the theme and the data nothing.

    Found = False is a real answer and not a failure: a `legend.data` entry
    naming a series that does not exist is drawn, greyed, and upstream logs a
    warning. }
  TTyLegendSource = record
    Found: Boolean;
    { 'bar' | 'line' | 'scatter' | 'pie' | '' }
    SeriesType: string;
    { The series' colour, or -- for a pie -- the DATUM's, because a pie legend
      names slices rather than series. }
    Colour: TTyChartColor;
    { The `legendIcon` visual: the series' own symbol where it has one, and ''
      where it has none. A bar and a pie have none, which is the whole reason
      the default legend icon is a rounded rectangle. A line's is 'emptyCircle'
      -- NOT 'circle': LineSeries.defaultOption names it, so the base class'
      'circle' is never reached. }
    DefaultIcon: string;
    { The series draws its OWN legend icon -- a rule with a marker sitting on
      it. Only a line does, upstream and here. }
    OwnIcon: Boolean;
    { The rule's colour and its width, LOGICAL px. `lineStyle.width: 'auto'`
      resolves to 2 for a series that draws a line and 0 for one that does
      not, and 2 is also the width this port's line mark builder falls back
      to -- so the legend's rule is the same thickness as the line it stands
      for, which is the whole point of the rule. Zero means no rule: the
      marker sits alone. }
    LineColour: TTyChartColor;
    LineWidthLogical: Double;
    { DRAWN INACTIVE WHATEVER THE LEGEND SAYS. The one case is a graph's
      category whose graph the legend switched off by its SERIES name:
      upstream never colours those categories and then throws dereferencing
      the colour it did not make. Its own comment says a name that cannot be
      found in the filtered data "will display as gray", so that is what this
      does. }
    Greyed: Boolean;
    { THE DATUM'S OWN OPACITY, for a swatch standing for a datum: a
      visualMap's. HasOpacity False is opaque. }
    HasOpacity: Boolean;
    Opacity: Double;
  end;
  TTyLegendSourceArray = array of TTyLegendSource;

  TTyLegendSpec = record
    Show: Boolean;
    { THE BOX AS UPSTREAM'S MODEL HOLDS IT: the raw option values over the
      defaults (left 'center', bottom 15), merged by mergeLayoutParam's
      ignoreSize rule. `width` and `height` are wrap limits, not sizes. }
    Box: TTyRawBox;
    { CSS order: top, right, bottom, left. }
    Padding: array[0..3] of Double;
    Orient: TTyLegendOrient;
    Align: TTyLegendAlign;
    ItemGap: Double;
    ItemWidth, ItemHeight: Double;
    { `legend.icon`; '' when absent. }
    Icon: string;
    { A `{name}` template. Replaced ONCE, because upstream calls
      String.replace with a string pattern rather than a global regexp. }
    Formatter: string;
    SelectedMode: TTyLegendSelectedMode;
    HasBackground: Boolean;
    BorderWidth: Double;
    BorderRadii: TTyCornerRadii;
    { `legend.z`, so the legend sorts against the series in the one paint
      list. Default 4. }
    Z: Integer;
  end;

  { One placed item. Everything is DEVICE px and absolute. }
  TTyLegendItem = record
    Entry: Integer;
    Name: string;
    { After the formatter. }
    Text: string;
    Selected: Boolean;
    { The resolved icon word -- after `legend.data[i].icon`, `legend.icon`, the
      series' own symbol and the 'roundRect' floor have all had their turn. }
    Icon: string;
    OwnIcon: Boolean;
    Colour: TTyChartColor;
    LineColour: TTyChartColor;
    LineWidthLogical: Double;
    { The box createSymbol is handed: itemWidth x itemHeight, scaled. }
    IconBox: TTyRectF;
    TextX, TextY: Double;
    TextW, TextH: Double;
    AnchorH: TTyTextAnchorH;
    { The item's own rectangle -- icon and words together, ink overhang
      included. This is what the wrap measured and what a click will hit. }
    Bounds: TTyRectF;
    { the datum's opacity on its swatch }
    HasOpacity: Boolean;
    Opacity: Double;
  end;
  TTyLegendItemArray = array of TTyLegendItem;

  TTyLegendLayout = record
    Valid: Boolean;
    { The background box, padding included. }
    Frame: TTyRectF;
    { The items' own extent, padding excluded. }
    Content: TTyRectF;
    Align: TTyLegendAlign;
    Items: TTyLegendItemArray;
  end;

  { Resolved from the theme by the control, like every other visual value in
    this layer. }
  TTyLegendInk = record
    Text: TTyChartColor;
    Inactive: TTyChartColor;
    Border: TTyChartColor;
    Background: TTyChartColor;
    { The hole in an `empty` icon: the chart's own ground, so the ring reads as
      a hole rather than as a white dot on a dark skin. }
    EmptyFill: TTyChartColor;
  end;

{ How many legends the option carries. An object counts as one. }
function TyLegendCount(AOption: TTyChartOption): Integer;
function TyLegendSpecDefault: TTyLegendSpec;
function TyLegendSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyLegendSpec;

{ THE TWO BOX SOLVES of LegendView.layout, both getLayoutRect on the merged
  option with the padding as margin: the room the items may wrap in -- the
  option's own box, keywords and all -- and the place of the block they
  made, the measured size winning over any width or height written. In
  device px. }
function TyLegendWrapRect(const ASpec: TTyLegendSpec;
  const AContainer: TTyRectF; APPI: Integer): TTyXYWH;
function TyLegendPlaceRect(const ASpec: TTyLegendSpec;
  const AContainer: TTyRectF; AMainW, AMainH: Double;
  APPI: Integer): TTyXYWH;

{ The entries, in order. `legend.data` when it is an array -- INCLUDING an
  empty one, which is upstream's way of asking for no items at all -- and
  APotential otherwise. Duplicate names are dropped, first one wins, and that
  applies to the line-break markers too: a legend can carry one '' and one
  newline and no more. }
function TyLegendEntries(AOption: TTyChartOption; AIndex: Integer;
  const APotential: array of string): TTyLegendEntryArray;

{ Which entries are switched on, `legend.selected` and `selectedMode` resolved
  the way upstream resolves them at LOAD.

  AAvailable is every name the chart can offer -- series names plus the data
  names of the series whose legend names their data. A name that is not in it
  reads as NOT selected however the map is written, which is what greys out a
  `legend.data` entry that names nothing. }
function TyLegendSelected(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AAvailable: array of string;
  AMode: TTyLegendSelectedMode): TTyLegendFlags;

{ Whether THIS legend switches AName off -- the question the filter asks of
  every series and of every pie slice.

  IT IS NOT `not selected`, and the difference is a chart going blank. A name
  the legend does not list at all is not switched off; it is simply not the
  legend's business. `TyLegendSelected` answers False for such a name too --
  because it also answers False for a name the CHART cannot produce, which is
  how a `legend.data` entry naming nothing gets greyed -- and a filter that
  read that answer directly would hide every series the legend never
  mentioned, starting with every series that has no `name` at all.

  Upstream is immune to this by accident of naming: every series gets a
  generated unique name and every one of them goes into `_availableNames`, so
  `isSelected` finds it and the `selected` map has no key for it. This port
  has no such names, so the rule is stated rather than inherited.

  ONE LEGEND SAYING NO IS ENOUGH, so a caller with several ORs the answers --
  legendFilter.ts:36-41 says exactly that.

  [Overturned in part, batch 31: "not the legend's business" holds only for a
  name `selected` does not mention either. See the overload below, which is
  the one the control asks.] }
function TyLegendHides(const AEntries: TTyLegendEntryArray;
  const AFlags: TTyLegendFlags; const AName: string): Boolean; overload;

{ THE WHOLE RULE: the listed answer above, plus A NAME `selected` SWITCHES
  OFF BY NAME, listed or not. Upstream's isSelected reads the map before it
  reads the list, and every series name is available, so a `selected` map
  writing `"a": false` hides series `a` whether `legend.data` names it or
  not -- which matters most for a graph with categories, whose legend lists
  the categories and never the series.

  Only the availability half is left out, and that is what keeps the old
  rule's point: a series name is always available upstream, and a name this
  port could not prove available must not blank a series. The empty name is
  still never hidden. }
function TyLegendHides(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const AName: string): Boolean; overload;

{ UPSTREAM'S `isSelected(name)`, FOR ANY NAME -- listed or not.

  TyLegendHides leaves out the availability half, deliberately, for series.
  The graph's category filter is upstream's categoryFilter, which asks
  isSelected for every node's category, listed or not: a name switched off in
  `selected` is off whether `legend.data` names it or not, and a name the
  chart does not offer at all -- a category index out of range, a name nobody
  declared -- is NEVER selected, so its nodes go.

  A listed name answers with its flag, which already carries single mode's
  rewrite; an unlisted one asks the `selected` map and the available names,
  which single mode never touched. }
function TyLegendNameSelected(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const AAvailable: array of string; const AName: string): Boolean;

{ `{name}`, replaced once. An empty formatter answers the name unchanged. }
function TyLegendText(const AFormatter, AName: string): string;

{ The `legendIcon` visual a series of this type publishes: ITS OWN SYMBOL
  where it has one, and '' where it has none.

  Only a series with a symbol visual publishes anything, and '' is what sends
  the icon chain on to `roundRect` -- which is the whole reason a bar and a
  pie get rounded rectangles. ASymbolWord is `series.symbol` as written, ''
  when the option did not name one.

  THE TWO DEFAULTS ARE NOT THE SAME WORD. A scatter reaches the base class'
  'circle'; a line names 'emptyCircle' in its own defaultOption and so never
  reaches it, which is why an ECharts line legend shows a RING and not a dot
  (LineSeries.ts:201, Series.ts:218). }
function TyLegendDefaultIcon(const ASeriesType, ASymbolWord: string): string;

{ Whether a series of this type draws its own legend icon -- a rule with a
  marker sitting on it -- rather than taking the shared one. Only a line does,
  upstream and here; `map` is the other one upstream and this port has no map. }
function TyLegendDrawsOwnIcon(const ASeriesType: string): Boolean;

{ Lay one out against AContainer. AFont is the words' font, resolved from the
  theme; APPI scales the LOGICAL gaps and the item box.

  Answers Valid = False when there is nothing to draw. }
function TyLayoutLegend(const ASpec: TTyLegendSpec;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const ASources: TTyLegendSourceArray; const AContainer: TTyRectF;
  const AMeasurer: ITyTextMeasurer; const AFont: TTyLegendFont;
  APPI: Integer): TTyLegendLayout;

{ The elements, appended to AList. Answers how many were added.

  SILENT, every one of them: the legend is not a datum and a legend icon
  swallowing the hover meant for the bar underneath it would be a bug. The
  click, when it comes, will walk the LAYOUT -- which knows which item is
  which -- rather than this list, which does not. }
function TyBuildLegendMarks(const ASpec: TTyLegendSpec;
  const ALayout: TTyLegendLayout; const AInk: TTyLegendInk;
  const AFont: TTyLegendFont; APPI: Integer; AList: TTyPaintList;
  ALegendIndex: Integer = -1): Integer;

implementation

uses tyControls.AdvChart.Handlers;

const
  { LegendModel.defaultOption, LegendModel.ts:450-539. `bottom` is
    tokens.size.m. `itemGap` is 8 and the JSDoc two lines above it says 10 --
    upstream disagrees with itself and the source wins. }
  cDefaultBottom = 15.0;
  cDefaultPadding = 5.0;
  cDefaultItemGap = 8.0;
  cDefaultItemWidth = 25.0;
  cDefaultItemHeight = 14.0;
  cDefaultZ = 4;
  { The gap between an icon and its words. A HARD 5 in LegendView.ts:455, and
    not itemGap -- itemGap separates whole entries. }
  cTextGap = 5.0;
  { A line series' marker is four fifths of the box's HEIGHT, LineSeries.ts:256.
    Named because the measurer and the drawer both need it and a number written
    twice is a number that drifts. }
  cOwnIconMarker = 0.8;
  { zrender grows a stroked path's bounding rect by half the pen -- and by
    half of strokeContainThreshold (5) INSTEAD, when the path has no fill at
    all, so that a hairline still has something to hit. Path.ts:373-383,
    :676.

    THAT SECOND RULE NEVER FIRES ON A LEGEND ICON, which is why there is no
    constant for it here: zrender's default path style carries fill '#000'
    and setStyle only ever writes over it, so every legend icon has a fill
    whether or not anyone chose one -- including the bare `line` icon, whose
    fill paints nothing because the path is degenerate. Half the pen, always. }

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData is TJSONObject) then
    Result := TJSONObject(AData)
  else
    Result := nil;
end;

function StrIn(ANode: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  if d.JSONType = jtString then Exit(d.AsString);
  if d.JSONType = jtNumber then Exit(d.AsString);
end;

function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  Result := d.AsFloat;
end;

function RectUnion(const A, B: TTyRectF): TTyRectF;
begin
  if not TyRectFIsValid(A) then Exit(B);
  if not TyRectFIsValid(B) then Exit(A);
  Result := TyRectF(Min(A.Left, B.Left), Min(A.Top, B.Top),
                    Max(A.Right, B.Right), Max(A.Bottom, B.Bottom));
end;

{ ==================== the spec ==================== }

function TyLegendCount(AOption: TTyChartOption): Integer;
begin
  Result := 0;
  if AOption = nil then Exit;
  Result := AOption.ComponentCount('legend');
end;

{ legend's defaultOption's box: `left: 'center'`, `bottom: 15`. }
function DefaultBox: TTyRawBox;
begin
  Result := Default(TTyRawBox);
  Result.Left := TyBoxRawStr('center');
  Result.Bottom := TyBoxRawNum(cDefaultBottom);
end;

function TyLegendSpecDefault: TTyLegendSpec;
var i: Integer;
begin
  Result.Show := True;
  Result.Box := DefaultBox;
  for i := 0 to 3 do Result.Padding[i] := cDefaultPadding;
  Result.Orient := tloHorizontal;
  Result.Align := tlaAuto;
  Result.ItemGap := cDefaultItemGap;
  Result.ItemWidth := cDefaultItemWidth;
  Result.ItemHeight := cDefaultItemHeight;
  Result.Icon := '';
  Result.Formatter := '';
  Result.SelectedMode := tlsMultiple;
  Result.HasBackground := False;
  Result.BorderWidth := 0;
  Result.BorderRadii := TyCornerRadii([]);
  Result.Z := cDefaultZ;
end;

procedure ReadPadding(ANode: TJSONObject; var APadding: array of Double);
var
  d: TJSONData;
  arr: TJSONArray;
  i, n: Integer;
  v: array[0..3] of Double;
begin
  if ANode = nil then Exit;
  d := ANode.Find('padding');
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  if d.JSONType = jtNumber then
  begin
    for i := 0 to 3 do APadding[i] := d.AsFloat;
    Exit;
  end;
  if not (d is TJSONArray) then Exit;
  arr := TJSONArray(d);
  n := arr.Count;
  if n = 0 then Exit;
  for i := 0 to 3 do v[i] := 0;
  for i := 0 to Min(3, n - 1) do
    if arr.Items[i].JSONType = jtNumber then v[i] := arr.Items[i].AsFloat;
  case n of
    1: for i := 0 to 3 do APadding[i] := v[0];
    2: begin
         APadding[0] := v[0]; APadding[2] := v[0];
         APadding[1] := v[1]; APadding[3] := v[1];
       end;
    3: begin
         APadding[0] := v[0];
         APadding[1] := v[1]; APadding[3] := v[1];
         APadding[2] := v[2];
       end;
  else
    for i := 0 to 3 do APadding[i] := v[i];
  end;
end;

function SelectedModeOf(ANode: TJSONObject): TTyLegendSelectedMode;
var d: TJSONData;
begin
  Result := tlsMultiple;
  if ANode = nil then Exit;
  d := ANode.Find('selectedMode');
  if d = nil then Exit;
  if d.JSONType = jtBoolean then
  begin
    if d.AsBoolean then Exit(tlsMultiple) else Exit(tlsOff);
  end;
  if (d.JSONType = jtString) and (d.AsString = 'single') then Exit(tlsSingle);
end;

function TyLegendSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyLegendSpec;
var
  node: TJSONObject;
  d: TJSONData;
  w: string;
  given: Boolean;
begin
  Result := TyLegendSpecDefault;
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('legend', AIndex));
  if node = nil then Exit;

  d := node.Find('show');
  if (d <> nil) and (d.JSONType = jtBoolean) then Result.Show := d.AsBoolean;

  { `legend.width` and `legend.height` are the WRAP LIMITS, not the drawn size:
    the second layout pass overwrites both with what the items measured. The
    comment saying so is at LegendModel.ts:251-254. }
  Result.Box := TyMergeBoxIgnoreSize(node, DefaultBox);

  ReadPadding(node, Result.Padding);
  if StrIn(node, 'orient') = 'vertical' then
    Result.Orient := tloVertical
  else
    Result.Orient := tloHorizontal;
  w := StrIn(node, 'align');
  if w = 'left' then Result.Align := tlaLeft
  else if w = 'right' then Result.Align := tlaRight
  else Result.Align := tlaAuto;
  Result.ItemGap := NumIn(node, 'itemGap', Result.ItemGap);
  Result.ItemWidth := NumIn(node, 'itemWidth', Result.ItemWidth);
  Result.ItemHeight := NumIn(node, 'itemHeight', Result.ItemHeight);
  Result.Icon := StrIn(node, 'icon');
  { A FUNCTION FORMATTER CANNOT SURVIVE JSON, so only the string form exists
    here and a non-string leaves the name alone. }
  d := node.Find('formatter');
  if (d <> nil) and (d.JSONType = jtString) then Result.Formatter := d.AsString;
  Result.SelectedMode := SelectedModeOf(node);

  d := node.Find('backgroundColor');
  Result.HasBackground := (d <> nil) and (d.JSONType = jtString)
    and (d.AsString <> '') and (d.AsString <> 'transparent');
  Result.BorderWidth := NumIn(node, 'borderWidth', 0);
  d := node.Find('borderRadius');
  if (d <> nil) and (d.JSONType = jtNumber) then
    Result.BorderRadii := TyCornerRadii([d.AsFloat]);
  Result.Z := TyRoundOpt(NumIn(node, 'z', cDefaultZ), cDefaultZ);
end;

{ ==================== entries ==================== }

function TyLegendEntries(AOption: TTyChartOption; AIndex: Integer;
  const APotential: array of string): TTyLegendEntryArray;
var
  node: TJSONObject;
  d: TJSONData;
  arr: TJSONArray;
  item: TJSONObject;
  raw: TTyLegendEntryArray;
  i, j, n: Integer;
  dup: Boolean;

  procedure PushRaw(const AName, AIcon: string);
  begin
    SetLength(raw, Length(raw) + 1);
    raw[High(raw)].Name := AName;
    raw[High(raw)].Icon := AIcon;
    raw[High(raw)].Newline := (AName = '') or (AName = #10);
  end;

begin
  Result := nil;
  raw := nil;
  node := nil;
  if AOption <> nil then node := ObjOf(AOption.ComponentAt('legend', AIndex));
  d := nil;
  if node <> nil then d := node.Find('data');

  if (d <> nil) and (d is TJSONArray) then
  begin
    { AN EMPTY ARRAY IS AN ANSWER. `this.get('data') || potentialData` falls
      back only on a MISSING data, and [] is truthy in JavaScript -- so
      `legend: {data: []}` asks for a legend with no items in it. }
    arr := TJSONArray(d);
    for i := 0 to arr.Count - 1 do
    begin
      case arr.Items[i].JSONType of
        jtString, jtNumber: PushRaw(arr.Items[i].AsString, '');
        jtObject:
          begin
            item := TJSONObject(arr.Items[i]);
            PushRaw(StrIn(item, 'name'), StrIn(item, 'icon'));
          end;
      end;
    end;
  end
  else
    for i := 0 to High(APotential) do PushRaw(APotential[i], '');

  { DEDUPLICATED BY NAME, first one wins -- and the line-break markers go
    through the same sieve, so a legend can hold one '' and one newline and no
    more however many the option lists. }
  n := 0;
  SetLength(Result, Length(raw));
  for i := 0 to High(raw) do
  begin
    dup := False;
    for j := 0 to n - 1 do
      if Result[j].Name = raw[i].Name then
      begin
        dup := True;
        Break;
      end;
    if dup then Continue;
    Result[n] := raw[i];
    Inc(n);
  end;
  SetLength(Result, n);
end;

{ ==================== selection ==================== }

type
  TSelMap = record
    Names: array of string;
    On_: array of Boolean;
  end;

function MapFind(const AMap: TSelMap; const AName: string): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to High(AMap.Names) do
    if AMap.Names[i] = AName then Exit(i);
end;

procedure MapSet(var AMap: TSelMap; const AName: string; AOn: Boolean);
var i: Integer;
begin
  i := MapFind(AMap, AName);
  if i < 0 then
  begin
    i := Length(AMap.Names);
    SetLength(AMap.Names, i + 1);
    SetLength(AMap.On_, i + 1);
    AMap.Names[i] := AName;
  end;
  AMap.On_[i] := AOn;
end;

{ `legend.selected`. ANY FALSY VALUE IS OFF, not just `false`:
  `!(has(name) && !selected[name])` is JavaScript, so null, 0 and '' switch an
  item off exactly as `false` does. }
function ReadSelectedMap(ANode: TJSONObject): TSelMap;
var
  d: TJSONData;
  obj: TJSONObject;
  i: Integer;
  v: TJSONData;
  on_: Boolean;
begin
  Result.Names := nil;
  Result.On_ := nil;
  if ANode = nil then Exit;
  d := ANode.Find('selected');
  if (d = nil) or not (d is TJSONObject) then Exit;
  obj := TJSONObject(d);
  for i := 0 to obj.Count - 1 do
  begin
    v := obj.Items[i];
    case v.JSONType of
      jtBoolean: on_ := v.AsBoolean;
      jtNumber: on_ := v.AsFloat <> 0;
      jtString: on_ := v.AsString <> '';
      jtNull: on_ := False;
    else
      on_ := True;
    end;
    MapSet(Result, obj.Names[i], on_);
  end;
end;

function TyLegendSelected(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AAvailable: array of string;
  AMode: TTyLegendSelectedMode): TTyLegendFlags;
var
  node: TJSONObject;
  map: TSelMap;
  i, k: Integer;
  hasOne: Boolean;

  function Available(const AName: string): Boolean;
  var j: Integer;
  begin
    Result := False;
    for j := 0 to High(AAvailable) do
      if AAvailable[j] = AName then Exit(True);
  end;

  function IsSel(const AName: string): Boolean;
  var j: Integer;
  begin
    j := MapFind(map, AName);
    Result := ((j < 0) or map.On_[j]) and Available(AName);
  end;

  { Single mode's `select`: every other item is switched off FIRST, and the
    loop is over the entries rather than over the map, so a name the map
    carries but the legend does not list is left alone. }
  procedure SelectOnly(const AName: string);
  var j: Integer;
  begin
    for j := 0 to High(AEntries) do MapSet(map, AEntries[j].Name, False);
    MapSet(map, AName, True);
  end;

begin
  node := nil;
  if AOption <> nil then node := ObjOf(AOption.ComponentAt('legend', AIndex));
  map := ReadSelectedMap(node);

  { SINGLE MODE IS RESOLVED AT LOAD, not on the first click -- optionUpdated
    forces exactly one item on. It takes the first item that is already
    selected, and the first item of all when none is. This is why a
    `selectedMode: 'single'` chart shows ONE series before anyone touches it,
    and why a legend that only drew would be wrong on the first frame. }
  if (AMode = tlsSingle) and (Length(AEntries) > 0) then
  begin
    hasOne := False;
    { AN EQUIVALENT MUTANT LIVES ON THE `Break` and is recorded rather than
      chased: SelectOnly has just switched every entry OFF, so every later
      IsSel answers False and the loop would finish without doing anything
      more. The Break is upstream's and it is kept for that reason -- it says
      `the FIRST selected item wins` out loud, which is the rule, rather than
      leaving it to be inferred from a side effect two lines up. }
    for i := 0 to High(AEntries) do
      if IsSel(AEntries[i].Name) then
      begin
        SelectOnly(AEntries[i].Name);
        hasOne := True;
        Break;
      end;
    if not hasOne then SelectOnly(AEntries[0].Name);
  end;

  SetLength(Result, Length(AEntries));
  for k := 0 to High(AEntries) do Result[k] := IsSel(AEntries[k].Name);
end;

function TyLegendDefaultIcon(const ASeriesType, ASymbolWord: string): string;
begin
  { A GRAPH HAS A SYMBOL VISUAL -- `hasSymbolVisual = true` -- so a graph the
    legend names by its SERIES name is drawn as its node symbol, a circle by
    default. (Its CATEGORIES are drawn as rounded rectangles: the category
    provider publishes no icon.) }
  if ASeriesType = 'graph' then
  begin
    if ASymbolWord <> '' then Exit(ASymbolWord);
    Exit('circle');
  end;
  { A bar, a pie, a funnel: no symbol visual, so nothing is published and the
    chain falls through to roundRect. }
  if (ASeriesType <> 'line') and (ASeriesType <> 'scatter') then Exit('');
  if ASymbolWord <> '' then Exit(ASymbolWord);
  if ASeriesType = 'scatter' then Result := 'circle'
  else Result := 'emptyCircle';
end;

function TyLegendDrawsOwnIcon(const ASeriesType: string): Boolean;
begin
  Result := ASeriesType = 'line';
end;

function TyLegendHides(const AEntries: TTyLegendEntryArray;
  const AFlags: TTyLegendFlags; const AName: string): Boolean;
var i: Integer;
begin
  Result := False;
  if AName = '' then Exit;
  for i := 0 to High(AEntries) do
  begin
    if AEntries[i].Newline then Continue;
    if AEntries[i].Name <> AName then Continue;
    { The entry exists, so the legend does have an opinion. }
    Exit((i > High(AFlags)) or (not AFlags[i]));
  end;
end;

function TyLegendHides(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const AName: string): Boolean;
var
  node: TJSONObject;
  map: TSelMap;
  i, j: Integer;
begin
  Result := False;
  if AName = '' then Exit;
  for i := 0 to High(AEntries) do
    if (not AEntries[i].Newline) and (AEntries[i].Name = AName) then
      Exit(TyLegendHides(AEntries, AFlags, AName));
  node := nil;
  if AOption <> nil then node := ObjOf(AOption.ComponentAt('legend', AIndex));
  map := ReadSelectedMap(node);
  j := MapFind(map, AName);
  Result := (j >= 0) and not map.On_[j];
end;

function TyLegendNameSelected(AOption: TTyChartOption; AIndex: Integer;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const AAvailable: array of string; const AName: string): Boolean;
var
  node: TJSONObject;
  map: TSelMap;
  i, j: Integer;
begin
  { A LINE BREAK IS LISTED TOO: `''` is an item upstream, and single mode can
    even pick it. }
  for i := 0 to High(AEntries) do
    if AEntries[i].Name = AName then
      Exit((i <= High(AFlags)) and AFlags[i]);
  node := nil;
  if AOption <> nil then node := ObjOf(AOption.ComponentAt('legend', AIndex));
  map := ReadSelectedMap(node);
  j := MapFind(map, AName);
  if (j >= 0) and not map.On_[j] then Exit(False);
  Result := False;
  for i := 0 to High(AAvailable) do
    if AAvailable[i] = AName then Exit(True);
end;

function TyLegendText(const AFormatter, AName: string): string;
var
  p: Integer;
  prm: TTyChartCallbackParams;
begin
  Result := AName;
  if AFormatter = '' then Exit;
  { a named handler is given the name, upstream's formatter(name) }
  if TyChartIsHandlerRef(AFormatter) then
  begin
    prm := TyChartBlankParams;
    prm.ComponentType := 'legend';
    prm.Name := AName;
    prm.DefaultText := AName;
    Exit(TyChartRunHandler(AFormatter, TyChartOneParams(prm)));
  end;
  Result := AFormatter;
  p := Pos('{name}', Result);
  if p <= 0 then Exit;
  Result := Copy(Result, 1, p - 1) + AName +
            Copy(Result, p + Length('{name}'), MaxInt);
end;

{ ==================== the layout ==================== }

{ How far a stroked shape's ink reaches past its own geometry. }
function StrokeGrow(AWidth: Double): Double;
begin
  if AWidth <= 0 then Exit(0);
  Result := AWidth / 2;
end;

{ The resolved icon word, and whether the series gets to draw its own.

  THREE TERMS, in this order: the row's own icon, then `legend.icon`, then the
  series' symbol, then 'roundRect'. The series only draws its OWN icon when the
  first two are silent or say 'inherit' -- which is why `icon: 'inherit'` on a
  bar is not a no-op but a SHARP rect: 'inherit' survives as a literal, matches
  no symbol name, and an unrecognised name is a rect. }
procedure ResolveIcon(const ASpec: TTyLegendSpec; const AEntry: TTyLegendEntry;
  const ASource: TTyLegendSource; out AIcon: string; out AOwn: Boolean);
var word_: string;
begin
  word_ := AEntry.Icon;
  if word_ = '' then word_ := ASpec.Icon;
  AOwn := ASource.OwnIcon and ((word_ = '') or (word_ = 'inherit'));
  if AOwn then
  begin
    { THE SERIES' OWN ICON IGNORES THE WORD. It does not read `legend.icon`
      at all -- it reads the series' symbol straight off the data, and maps
      `symbol: 'none'` to a circle so that a line with no markers still gets
      one in its legend. LineSeries.ts:251-253. }
    AIcon := ASource.DefaultIcon;
    if (AIcon = '') or (AIcon = 'none') then AIcon := 'circle';
    Exit;
  end;
  AIcon := word_;
  if AIcon = '' then AIcon := ASource.DefaultIcon;
  if AIcon = '' then AIcon := 'roundRect';
end;

{ The pen an `empty` icon is ringed with: the line's own width where it has
  one, and 2 where it has not. The same fallback the datum mark builders
  make, so a legend's marker and the markers on the line it stands for are
  drawn with the same pen. }
function RingPen(ALineWidthLogical: Double): Double;
begin
  Result := ALineWidthLogical;
  if Result <= 0 then Result := 2;
end;

{ The icon's ink extent in a box at the origin, which is what the wrap
  measures. It builds the same shapes TyBuildLegendMarks draws and grows them
  by the same pens, so the box measured here and the ink drawn there cannot
  disagree.

  ARulePx is the line series' rule, 0 when there is none; APenPx is the pen a
  ring or a bare stroke is drawn with, which is never 0. Both DEVICE px. }
function IconExtent(const AIcon: string; AOwn: Boolean;
  AIconW, AIconH, ARulePx, APenPx: Double): TTyRectF;
var
  spec: TTySymbolSpec;
  empty: Boolean;
  path: string;
  kind: TTySymbolKind;
  sh: TTyChartShape;
  box, r: TTyRectF;
  size, grow: Double;
begin
  box := TyRectF(0, 0, AIconW, AIconH);
  kind := TySymbolKindOf(AIcon, empty, path);

  if AOwn then
  begin
    { A LINE SERIES DRAWS A RULE WITH A MARKER ON IT, LineSeries.ts:236-282.
      The rule spans the whole box at its middle; the marker is 80% of the
      box's HEIGHT and centred, so the 25 x 14 really is a padded slot here
      and not the edge-to-edge fill every other icon makes of it. }
    Result := TyInvalidRectF;
    if ARulePx > 0 then
    begin
      grow := StrokeGrow(ARulePx);
      Result := TyRectF(-grow, AIconH / 2 - grow, AIconW + grow,
                        AIconH / 2 + grow);
    end;
    size := AIconH * cOwnIconMarker;
    if kind <> tsyNone then
    begin
      grow := 0;
      if empty or (kind = tsyLine) then
        grow := StrokeGrow(APenPx);
      r := TyRectF((AIconW - size) / 2 - grow, (AIconH - size) / 2 - grow,
                   (AIconW + size) / 2 + grow, (AIconH + size) / 2 + grow);
      Result := RectUnion(Result, r);
    end;
    Exit;
  end;

  if kind = tsyNone then Exit(TyInvalidRectF);
  spec := Default(TTySymbolSpec);
  spec.Kind := kind;
  spec.Empty := empty;
  spec.PathData := path;
  sh := TyBuildSymbolInBox(spec, box);
  Result := TyShapeBounds(sh);
  if not TyRectFIsValid(Result) then Exit;
  { A filled icon carries no pen at all -- `itemStyle.borderWidth: 'auto'`
    resolves to 0 unless the series itself has a border -- so only the ring and
    the bare rule reach past their geometry. }
  if empty or (kind = tsyLine) then
  begin
    grow := StrokeGrow(APenPx);
    Result := TyRectF(Result.Left - grow, Result.Top - grow,
                      Result.Right + grow, Result.Bottom + grow);
  end;
end;

{ boxLayout, layout.ts:74-142 -- the wrap, transcribed including the parts that
  read oddly.

  THE COMPARISON EXCLUDES THE GAP, and upstream's own FIXME beside it says so:
  an item that lands exactly on the limit does not wrap, and the gap that
  follows it pushes the NEXT one over instead.

  THE (-next.x + this.x) TERM is what makes the gap mean the same thing for
  every item. `x` is where an item's ORIGIN goes, not where its ink starts; the
  correction converts one into the other so that consecutive bounding rects end
  up exactly `gap` apart however far either one hangs off its own origin.

  THE ROW PITCH IS THE TALLEST ITEM IN THE ROW BEING CLOSED, not itemHeight --
  which is why a row of line-series items sits fractionally tighter than a row
  of bars: the rule-and-marker icon is a shade shorter than the box. }
procedure BoxLayout(AHorizontal: Boolean; const ARects: array of TTyRectF;
  const ANewline: array of Boolean; AGap, AMaxW, AMaxH: Double;
  var AX, AY: array of Double);
var
  i, n: Integer;
  x, y, lineMax, moveX, moveY, nextX, nextY: Double;
  r, nr: TTyRectF;
  hasNext, wrap: Boolean;
begin
  n := Length(ARects);
  x := 0;
  y := 0;
  nextX := 0;
  nextY := 0;
  lineMax := 0;
  for i := 0 to n - 1 do
  begin
    r := ARects[i];
    hasNext := i + 1 < n;
    if hasNext then nr := ARects[i + 1];
    if AHorizontal then
    begin
      moveX := TyRectFWidth(r);
      if hasNext then moveX := moveX + (r.Left - nr.Left);
      nextX := x + moveX;
      wrap := (nextX > AMaxW) or ANewline[i];
      if wrap then
      begin
        x := 0;
        nextX := moveX;
        y := y + lineMax + AGap;
        lineMax := TyRectFHeight(r);
      end
      else
        lineMax := Max(lineMax, TyRectFHeight(r));
    end
    else
    begin
      moveY := TyRectFHeight(r);
      if hasNext then moveY := moveY + (r.Top - nr.Top);
      nextY := y + moveY;
      wrap := (nextY > AMaxH) or ANewline[i];
      if wrap then
      begin
        y := 0;
        nextY := moveY;
        x := x + lineMax + AGap;
        lineMax := TyRectFWidth(r);
      end
      else
        lineMax := Max(lineMax, TyRectFWidth(r));
    end;
    { A LINE BREAK TAKES NO PLACE AND EATS NO GAP. It has already advanced the
      row above; giving it a position too would leave a hole at the start of
      the new one. }
    if ANewline[i] then Continue;
    AX[i] := x;
    AY[i] := y;
    if AHorizontal then
      x := nextX + AGap
    else
      y := nextY + AGap;
  end;
end;

{ The padding in device px, CSS order. }
procedure PadOf(const ASpec: TTyLegendSpec; APPI: Integer; out APad: array of Double);
var i: Integer; scale: Double;
begin
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  for i := 0 to 3 do APad[i] := ASpec.Padding[i] * scale;
end;

function TyLegendWrapRect(const ASpec: TTyLegendSpec;
  const AContainer: TTyRectF; APPI: Integer): TTyXYWH;
var pad: array[0..3] of Double;
begin
  { THE OPTION'S OWN BOX, keywords and all: upstream solves the wrap room
    with no size given, so `bottom: 'bottom'` on a vertical legend leaves the
    height the switch computes from a not-a-number -- not the full height. }
  PadOf(ASpec, APPI, pad);
  Result := TyGetLayoutRect(ASpec.Box, AContainer.Left, AContainer.Top,
    AContainer.Right - AContainer.Left, AContainer.Bottom - AContainer.Top, pad);
end;

function TyLegendPlaceRect(const ASpec: TTyLegendSpec;
  const AContainer: TTyRectF; AMainW, AMainH: Double;
  APPI: Integer): TTyXYWH;
var
  pad: array[0..3] of Double;
  box: TTyRawBox;
begin
  { defaults({width, height}, params): the measured pair never goes missing,
    so it wins over anything written. }
  PadOf(ASpec, APPI, pad);
  box := ASpec.Box;
  box.Width := TyBoxRawNum(AMainW);
  box.Height := TyBoxRawNum(AMainH);
  Result := TyGetLayoutRect(box, AContainer.Left, AContainer.Top,
    AContainer.Right - AContainer.Left, AContainer.Bottom - AContainer.Top, pad);
end;

function TyLayoutLegend(const ASpec: TTyLegendSpec;
  const AEntries: TTyLegendEntryArray; const AFlags: TTyLegendFlags;
  const ASources: TTyLegendSourceArray; const AContainer: TTyRectF;
  const AMeasurer: ITyTextMeasurer; const AFont: TTyLegendFont;
  APPI: Integer): TTyLegendLayout;
var
  n, i: Integer;
  scale, iw, ih, gap, tgap: Double;
  pad: array[0..3] of Double;
  maxBox, layoutBox: TTyXYWH;
  content: TTyRectF;
  spec2: TTyBoxSpec;
  rects: array of TTyRectF;
  newline: array of Boolean;
  px, py: array of Double;
  src: TTyLegendSource;
  it: TTyLegendItem;
  iconR, textR: TTyRectF;
  textX, ox, oy, mainW, mainH: Double;
  drawn: Integer;
begin
  Result := Default(TTyLegendLayout);
  if not ASpec.Show then Exit;
  if AMeasurer = nil then Exit;
  if not TyRectFIsValid(AContainer) then Exit;
  n := Length(AEntries);
  if n = 0 then Exit;

  if APPI > 0 then scale := APPI / 96 else scale := 1;
  for i := 0 to 3 do pad[i] := ASpec.Padding[i] * scale;
  gap := ASpec.ItemGap * scale;
  iw := ASpec.ItemWidth * scale;
  ih := ASpec.ItemHeight * scale;
  tgap := cTextGap * scale;

  { ALIGN IS DERIVED FROM THE WORD, not from the solved edge, and only a
    VERTICAL legend pinned by the literal `left: 'right'` gets the right-hand
    form. LegendView.ts:118-125. }
  Result.Align := ASpec.Align;
  if Result.Align = tlaAuto then
  begin
    if (ASpec.Box.Left.Kind = brString) and (ASpec.Box.Left.Str = 'right')
      and (ASpec.Orient = tloVertical) then
      Result.Align := tlaRight
    else
      Result.Align := tlaLeft;
  end;

  { THE FIRST OF TWO BOX SOLVES. This one answers "how much room is there",
    and only its SIZE is used -- as the wrap limit. The second one, further
    down, places the block that the wrap produced. }
  maxBox := TyLegendWrapRect(ASpec, AContainer, APPI);

  SetLength(Result.Items, n);
  SetLength(rects, n);
  SetLength(newline, n);
  SetLength(px, n);
  SetLength(py, n);

  for i := 0 to n - 1 do
  begin
    it := Default(TTyLegendItem);
    it.Entry := i;
    it.Name := AEntries[i].Name;
    it.Selected := (i <= High(AFlags)) and AFlags[i];
    newline[i] := AEntries[i].Newline;
    px[i] := 0;
    py[i] := 0;
    if newline[i] then
    begin
      { An empty group measures (0, 0, 0, 0) and that zero is load-bearing: it
        is what resets the row pitch.

        ITS OWN BOUNDS ARE INVALID, not zero. A break is never placed, and an
        all-zero rectangle is a perfectly valid rectangle at the origin -- so
        saying `not placed` with one would leave every consumer testing a
        degenerate box instead of asking the question it means to ask. }
      rects[i] := TyRectF(0, 0, 0, 0);
      it.Bounds := TyInvalidRectF;
      it.IconBox := TyInvalidRectF;
      Result.Items[i] := it;
      Continue;
    end;

    src := Default(TTyLegendSource);
    if i <= High(ASources) then src := ASources[i];
    if src.Greyed then it.Selected := False;
    ResolveIcon(ASpec, AEntries[i], src, it.Icon, it.OwnIcon);
    it.Colour := src.Colour;
    it.LineColour := src.LineColour;
    it.HasOpacity := src.HasOpacity;
    it.Opacity := src.Opacity;
    { `lineStyle.width: 'auto'` is resolved by whoever filled the source in --
      it is the one rule here that needs to know whether the SERIES draws a
      line, and this unit does not. Zero means no rule. }
    it.LineWidthLogical := src.LineWidthLogical;
    it.Text := TyLegendText(ASpec.Formatter, it.Name);

    AMeasurer.MeasureLine(it.Text, AFont.Name, AFont.SizeLogical,
      AFont.Weight, it.TextW, it.TextH);

    iconR := IconExtent(it.Icon, it.OwnIcon, iw, ih,
      it.LineWidthLogical * scale, RingPen(it.LineWidthLogical) * scale);

    { THE WORDS HANG OFF THE ICON'S FAR EDGE, and off its NEAR edge when the
      legend is right-aligned -- where the anchor goes NEGATIVE and the item's
      whole rectangle starts to the left of its own origin. That is the case
      the wrap's correction term exists for. }
    if Result.Align = tlaLeft then
    begin
      textX := iw + tgap;
      it.AnchorH := tahLeft;
      textR := TyRectF(textX, ih / 2 - it.TextH / 2,
                       textX + it.TextW, ih / 2 + it.TextH / 2);
    end
    else
    begin
      textX := -tgap;
      it.AnchorH := tahRight;
      textR := TyRectF(textX - it.TextW, ih / 2 - it.TextH / 2,
                       textX, ih / 2 + it.TextH / 2);
    end;
    it.TextX := textX;
    it.TextY := ih / 2;

    rects[i] := RectUnion(iconR, textR);
    if not TyRectFIsValid(rects[i]) then rects[i] := TyRectF(0, 0, 0, 0);
    Result.Items[i] := it;
  end;

  BoxLayout(ASpec.Orient = tloHorizontal, rects, newline, gap,
    maxBox.W, maxBox.H, px, py);

  content := TyInvalidRectF;
  drawn := 0;
  for i := 0 to n - 1 do
  begin
    if newline[i] then Continue;
    content := RectUnion(content,
      TyRectF(px[i] + rects[i].Left, py[i] + rects[i].Top,
              px[i] + rects[i].Right, py[i] + rects[i].Bottom));
    Inc(drawn);
  end;
  if (drawn = 0) or not TyRectFIsValid(content) then Exit;

  mainW := TyRectFWidth(content);
  mainH := TyRectFHeight(content);

  { THE SECOND SOLVE, and the measured size WINS over `legend.width`: upstream
    merges {width, height} with defaults(), which only fills in what is
    missing, and the measured pair is never missing. }
  layoutBox := TyLegendPlaceRect(ASpec, AContainer, mainW, mainH, APPI);

  { The content group is shifted so that its own top-left lands on the solved
    corner, whatever negative overhang the items have. }
  ox := layoutBox.X - content.Left;
  oy := layoutBox.Y - content.Top;

  for i := 0 to n - 1 do
  begin
    if newline[i] then Continue;
    it := Result.Items[i];
    it.IconBox := TyRectF(ox + px[i], oy + py[i],
                          ox + px[i] + iw, oy + py[i] + ih);
    it.TextX := it.TextX + ox + px[i];
    it.TextY := it.TextY + oy + py[i];
    it.Bounds := TyRectF(ox + px[i] + rects[i].Left, oy + py[i] + rects[i].Top,
                         ox + px[i] + rects[i].Right,
                         oy + py[i] + rects[i].Bottom);
    Result.Items[i] := it;
  end;

  Result.Content := TyRectF(layoutBox.X, layoutBox.Y,
                            layoutBox.X + mainW, layoutBox.Y + mainH);
  Result.Frame := TyRectF(Result.Content.Left - pad[3],
                          Result.Content.Top - pad[0],
                          Result.Content.Right + pad[1],
                          Result.Content.Bottom + pad[2]);
  Result.Valid := True;
end;

{ ==================== the marks ==================== }

function TyBuildLegendMarks(const ASpec: TTyLegendSpec;
  const ALayout: TTyLegendLayout; const AInk: TTyLegendInk;
  const AFont: TTyLegendFont; APPI: Integer; AList: TTyPaintList;
  ALegendIndex: Integer): Integer;
var
  i: Integer;
  scale: Double;
  el: TTyChartElement;
  it: TTyLegendItem;
  empty: Boolean;
  path: string;
  kind: TTySymbolKind;
  pts: array[0..1] of TTyPointF;
  size, pen: Double;
  colour: TTyChartColor;

  function Blank: TTyChartElement;
  begin
    Result := Default(TTyChartElement);
    Result.Z := ASpec.Z;
    Result.Silent := True;
    Result.Datum := TyChartNoDatum;
    Result.Style.Alpha := 1;
  end;

  { ONE ICON IN A GIVEN BOX. The marker on a line's own icon and the shared
    icon are the same shape styled the same way in two different boxes; the
    two used to be written out twice, which is how they would have drifted.

    An `empty` icon is a RING -- the series colour becomes the pen and the
    hole is the chart's own ground, so it reads as a hole rather than as a
    white dot on a dark skin. A bare `line` is the one shape that is stroked
    and not filled at all. Everything else is a solid fill. }
  function Icon(AKind: TTySymbolKind; AEmpty: Boolean;
    const APath: string; const ABox: TTyRectF): TTyChartElement;
  var sp: TTySymbolSpec;
  begin
    sp := Default(TTySymbolSpec);
    sp.Kind := AKind;
    sp.Empty := AEmpty;
    sp.PathData := APath;
    Result := Blank;
    Result.Shape := TyBuildSymbolInBox(sp, ABox);
    if AEmpty or (AKind = tsyLine) then
    begin
      Result.Style.StrokeColor := colour;
      Result.Style.StrokeWidthLogical := RingPen(it.LineWidthLogical);
      if AKind <> tsyLine then
      begin
        Result.Style.HasFill := True;
        Result.Style.FillColor := AInk.EmptyFill;
      end;
    end
    else
    begin
      Result.Style.HasFill := True;
      Result.Style.FillColor := colour;
    end;
  end;

begin
  Result := 0;
  if AList = nil then Exit;
  if not ALayout.Valid then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;

  { The frame first and UNDER everything, and only when the option asked for
    one: upstream gives a legend a transparent background and a zero border, so
    painting a plate behind every legend would put a visible box on every
    chart in the gallery. }
  if ASpec.HasBackground or (ASpec.BorderWidth > 0) then
  begin
    el := Blank;
    el.Z2 := -1;
    el.Shape := TyShapeRoundRect(ALayout.Frame,
      ASpec.BorderRadii[0] * scale);
    el.Style.HasFill := ASpec.HasBackground;
    el.Style.FillColor := AInk.Background;
    if ASpec.BorderWidth > 0 then
    begin
      el.Style.StrokeWidthLogical := ASpec.BorderWidth;
      el.Style.StrokeColor := AInk.Border;
    end;
    AList.Add(el);
    Inc(Result);
  end;

  for i := 0 to High(ALayout.Items) do
  begin
    it := ALayout.Items[i];
    if not TyRectFIsValid(it.Bounds) then Continue;
    { THE ITEM'S ONE HIT TARGET: an unpainted rect over its bounds, under
      which the icon and the words stay silent -- upstream's legend item is a
      single target too, so moving from its icon to its words is no
      out-and-over [Batch 84] }
    if ALegendIndex >= 0 then
    begin
      el := Blank;
      el.Shape := TyShapeRect(it.Bounds);
      el.Silent := False;
      el.Datum := TyChartComponentDatum(ctkLegend, ALegendIndex, i);
      AList.Add(el);
      Inc(Result);
    end;

    { DESELECTED IS ONE COLOUR FOR EVERYTHING -- icon, ring, rule and words.
      Upstream reaches it through four separate options that all default to
      the same disabled token. }
    if it.Selected then colour := it.Colour else colour := AInk.Inactive;

    kind := TySymbolKindOf(it.Icon, empty, path);
    if it.OwnIcon then
    begin
      { THE RULE FIRST AND THE MARKER OVER IT, which is the order upstream
        adds them in and it shows: an `empty` marker is FILLED with the
        chart's own ground, so the ring's hole covers the middle of the rule
        and what reaches the eye is two stubs with a ring between them. }
      pen := it.LineWidthLogical;
      if pen > 0 then
      begin
        pts[0] := TyPointF(it.IconBox.Left,
                           (it.IconBox.Top + it.IconBox.Bottom) / 2);
        pts[1] := TyPointF(it.IconBox.Right,
                           (it.IconBox.Top + it.IconBox.Bottom) / 2);
        el := Blank;
        el.Shape := TyShapePolyline(pts);
        el.Style.StrokeWidthLogical := pen;
        if it.Selected then
          el.Style.StrokeColor := it.LineColour
        else
          el.Style.StrokeColor := AInk.Inactive;
        AList.Add(el);
        Inc(Result);
      end;
      { The marker, four fifths of the box's height and centred in it. }
      size := TyRectFHeight(it.IconBox) * cOwnIconMarker;
      if (kind <> tsyNone) and (size > 0) then
      begin
        el := Icon(kind, empty, path,
          TyRectF((it.IconBox.Left + it.IconBox.Right - size) / 2,
                  (it.IconBox.Top + it.IconBox.Bottom - size) / 2,
                  (it.IconBox.Left + it.IconBox.Right + size) / 2,
                  (it.IconBox.Top + it.IconBox.Bottom + size) / 2));
        AList.Add(el);
        Inc(Result);
      end;
    end
    else if kind <> tsyNone then
    begin
      el := Icon(kind, empty, path, it.IconBox);
      if it.HasOpacity then
        el.Style.Alpha := Min(Double(1), Max(Double(0), it.Opacity));
      AList.Add(el);
      Inc(Result);
    end;

    if it.Text <> '' then
    begin
      el := Blank;
      { A PLAIN RECT UNDER THE WORDS, never painted -- it is what gives the
        caption a place in a list whose every other member is a shape. }
      el.Shape := TyShapeRect(TyRectF(
        it.TextX - it.TextW * Ord(it.AnchorH = tahRight), it.TextY - it.TextH / 2,
        it.TextX + it.TextW * Ord(it.AnchorH = tahLeft), it.TextY + it.TextH / 2));
      el.Caption.Text := it.Text;
      el.Caption.FontName := AFont.Name;
      el.Caption.FontSizeLogical := AFont.SizeLogical;
      el.Caption.FontWeight := AFont.Weight;
      if it.Selected then
        el.Caption.Colour := AInk.Text
      else
        el.Caption.Colour := AInk.Inactive;
      el.Caption.X := it.TextX;
      el.Caption.Y := it.TextY;
      el.Caption.AnchorH := it.AnchorH;
      el.Caption.AnchorV := tavMiddle;
      AList.Add(el);
      Inc(Result);
    end;
  end;
end;

end.
