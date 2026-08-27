unit tyControls.Chart;
{$mode objfpc}{$H+}
{ TTyChart — a themed line / bar / pie chart (a custom-drawn re-imagining of the
  BusinessSkinForm chart controls).

  TTyChart is a TTyGraphicControl. Its panel chrome (background / axis text / grid
  lines) comes entirely from the resolved TyPanel style, so it follows the active
  theme — no colour is hard-coded there. The DATA series use a fixed, tasteful
  palette (TyChartPalette, the Tableau-10 hues); an app may override any single
  series colour via TTyChartSeriesItem.Color.

  The chart's SCALE / LAYOUT / HIT-TEST arithmetic is factored into PURE interface
  functions (TyChartNiceRange / TyChartValueToY / TyChartBarXRange / TyChartPieSweeps /
  TyChartLayoutFor / TyChartBarRect / TyChartPointCenter / the three hit-tests /
  TyChartTooltipRect / TyChartDefaultTooltip / TyChartDonutHoleRadius) so the whole
  geometry can be unit-tested headless. RenderTo is the real-machine paint path: it
  calls the pure functions, then fills / strokes via the BGRA antialiased Canvas2D.

  The paint and the hit-test call the SAME pure functions (TyChartBarRect for a bar,
  TyChartPointCenter for a line marker, TyChartPieSweeps + TyChartPieHitTest for a
  slice), so the datum the pointer reports can never drift from the datum that was
  drawn there — the TTySegmented rule.

  Still NOT included: zoom / mixed chart types / secondary axes. }
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType,   // LCLType: MulDiv
  BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  BGRAWriteTiff,   // registers the TIFF writer so SaveToFile('.tif') has a backend
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel;

type
  { A named dynamic Double array (FPC cannot return an anonymous `array of Double`).
    Not present in tyControls.Types, and that unit is off-limits this batch, so it is
    declared here. }
  TDoubleArray = array of Double;
  { One TDoubleArray per series — what the axes hit-tests take instead of the live
    collection, so they stay pure (plain values in, an index out). }
  TDoubleArrayArray = array of TDoubleArray;

  { Which chart TTyChart draws. Line/bar are multi-series (axes + grid); pie/donut use the
    first series' values as slice sizes. ctDonut is APPENDED (not slotted next to ctPie) so
    every already-streamed .lfm keeps its ordinal. }
  TTyChartType = (ctLine, ctBar, ctPie, ctDonut);

  { One pie slice as an angular span, degrees. StartDeg is measured clockwise; the
    control offsets by -90 so slice 0 starts at the top. }
  TTyChartPieSlice = record
    StartDeg, SweepDeg: Double;
  end;
  TTyChartPieSliceArray = array of TTyChartPieSlice;

  { One datum: which series, which point in it. Both are -1 together for "nothing"
    (TyChartHitValid is the single place that decides), never one of the two. }
  TTyChartHit = record
    SeriesIndex: Integer;
    PointIndex: Integer;
  end;

  { The chart's bands, DEVICE px relative to the control rect's top-left. Exactly one of
    Plot / PieArea is non-empty (an axes chart has no pie area and vice versa); Legend is
    empty when the legend is off or does not fit. }
  TTyChartLayout = record
    Plot: TRect;      // the axes plot band (line/bar)
    PieArea: TRect;   // the pie/donut disc's bounding band
    Legend: TRect;    // the legend strip
  end;

const
  { Built-in logical-px defaults (96-PPI baseline) for the chart's own metrics. A skin
    retunes each through the named theme metric beside it (the v3/C convention); these are
    only what a theme that sets neither falls back to. Every call site scales them to device
    px via MulDiv(..., APPI, 96) / TTyPainter.Scale.
    TyChartDonutHolePercent is the ODD ONE OUT: theme metrics are integers, and a hole is
    only meaningful RELATIVE to the outer radius (the disc is sized by the control, not by
    the theme), so it is a PERCENT of that radius, not a length. 55% is Ant Design's ring. }
  TyChartDonutHolePercent  = 55;   // donut hole radius, PERCENT of the outer radius
  TyChartHitRadius         = 12;   // how near a line marker the pointer must come to hit it
  TyChartTooltipGap        = 10;   // gap between the hovered datum and the tooltip box
  TyChartTooltipSwatch     = 8;    // the series-colour chip in the tooltip, square
  TyChartTooltipSwatchGap  = 5;    // gap between that chip and the tooltip text

  { The metric tokens those fallbacks back. Named constants rather than literals so a typo
    cannot silently strand one call site on the default (the tyControls.Types convention). }
  TyChartDonutHoleVar        = '--chart-donut-hole';
  TyChartHitRadiusVar        = '--chart-hit-radius';
  TyChartTooltipGapVar       = '--chart-tooltip-gap';
  TyChartTooltipSwatchVar    = '--chart-tooltip-swatch';
  TyChartTooltipSwatchGapVar = '--chart-tooltip-swatch-gap';

  { A hole wider than this leaves a hairline ring that reads as nothing at all, and 100%
    would erase the chart — so the token is clamped here however a skin sets it. }
  TyChartDonutHoleMaxPercent = 90;

{ ---- Pure geometry (headless-testable; no control / painter / handle state) ---- }

{ Nice range: expand [AMin,AMax] to round boundaries so the tick count is ~ATarget.
  AStep is snapped to 1/2/5 x 10^k. Guarantees ANiceMin<=AMin, ANiceMax>=AMax,
  AStep>0. Degenerate input (AMax<=AMin) is expanded to a unit span first. }
procedure TyChartNiceRange(AMin, AMax: Double; ATarget: Integer;
  out ANiceMin, ANiceMax, AStep: Double);

{ Value -> pixel Y (linear). ATop is the pixel row for ANiceMax, ABottom the pixel
  row for ANiceMin. Returns ABottom when the range is degenerate. }
function TyChartValueToY(AValue, ANiceMin, ANiceMax: Double; ATop, ABottom: Integer): Integer;

{ The pixel X span [AX0,AX1] of the AIndex-th of ACount equally-spaced bars laid out
  in [ALeft,ARight], with a group gap so adjacent bars never overlap and every bar
  stays within [ALeft,ARight]. Degenerate (ACount<=0 or out-of-range AIndex) -> an
  empty span anchored at ALeft. }
procedure TyChartBarXRange(AIndex, ACount, ALeft, ARight: Integer; out AX0, AX1: Integer);

{ Pie sweep angles: each value's (StartDeg, SweepDeg) so the sweeps sum to 360 in
  proportion to the positive values. Negatives are clamped to 0. If the positive
  total is 0 (empty / all-zero / all-negative) every sweep is 0 (safe, no divide). }
function TyChartPieSweeps(const AValues: array of Double): TTyChartPieSliceArray;

{ The chart's bands for a AWidth x AHeight control, all DEVICE px:
    ARadial       — pie/donut (one disc) rather than line/bar (axes + plot band).
    AShowLegend   — reserve the bottom legend strip.
    AMargin       — the outer margin, all four sides.
    ATitleHeight  — the title band's height (0 when there is no title).
    ALegendHeight — the legend strip's height (ignored when AShowLegend is False).
    AYAxisWidth   — the tick-label gutter left of the plot (axes charts only).
    AXAxisHeight  — the category-label band under the plot (axes charts only).
  Any band that would come out empty or inverted (a control too small for its own margins,
  a legend wider than the chart) comes back as an EMPTY rect, so a caller can test one rect
  instead of re-deriving the arithmetic. Both the paint and the hit-test call this, which is
  what keeps the pointer and the pixels talking about the same rectangle. }
function TyChartLayoutFor(AWidth, AHeight: Integer; ARadial, AShowLegend: Boolean;
  AMargin, ATitleHeight, ALegendHeight, AYAxisWidth, AXAxisHeight: Integer): TTyChartLayout;

{ The DEVICE-px rect of ONE bar: category APointIndex of ACatCount, series ASeriesIndex of
  ASeriesCount, inside plot APlot, for AValue on the [ANiceMin,ANiceMax] scale. The plot is
  split into ACatCount category slots and each slot into ASeriesCount bars — that nesting IS
  the grouped-bar (side-by-side multi-series) layout, and TyChartBarXRange's inset guarantees
  the groups and the bars inside them never overlap.
  The bar spans the zero baseline to the value, so a negative value's rect hangs BELOW the
  baseline. A zero value gives a ZERO-HEIGHT (empty) rect: it draws nothing, so nothing can
  be hovered there either. Degenerate requests give an empty rect, never an inverted one. }
function TyChartBarRect(APointIndex, ACatCount, ASeriesIndex, ASeriesCount: Integer;
  const APlot: TRect; AValue, ANiceMin, ANiceMax: Double): TRect;

{ The DEVICE-px centre of one line marker: category APointIndex of ACatCount in plot APlot,
  for AValue on the [ANiceMin,ANiceMax] scale. Markers sit at the CENTRE of the category
  slot, which is where the polyline's vertices are. }
function TyChartPointCenter(APointIndex, ACatCount: Integer; const APlot: TRect;
  AValue, ANiceMin, ANiceMax: Double): TPoint;

{ A "nothing under the pointer" hit, and the single test for one. }
function TyChartNoHit: TTyChartHit;
function TyChartHitValid(const AHit: TTyChartHit): Boolean;

{ The (series, point) whose BAR contains device-px (X,Y) — the exact inverse of
  TyChartBarRect (it scans that function's own rects), so the bar the pointer reports is the
  bar that was painted there. Bars never overlap, so the first containing rect wins.
  ASeriesValues is one array per series; a series shorter than ACatCount simply has fewer
  bars. A none-hit for a point over the plot's empty space. }
function TyChartBarHitTest(X, Y: Integer; const ASeriesValues: TDoubleArrayArray;
  ACatCount: Integer; const APlot: TRect; ANiceMin, ANiceMax: Double): TTyChartHit;

{ The (series, point) whose line MARKER is NEAREST device-px (X,Y), within ATolerance px
  (Euclidean). Unlike a bar, a marker is a few px across and cannot be hit reliably by
  containment, so the pointer gets a grab radius — the marker nearest the pointer wins, and
  ties go to the LOWER series index (stable: the same pixel always answers the same datum).
  A zero/negative tolerance grabs nothing. }
function TyChartLineHitTest(X, Y: Integer; const ASeriesValues: TDoubleArrayArray;
  ACatCount: Integer; const APlot: TRect; ANiceMin, ANiceMax: Double;
  ATolerance: Integer): TTyChartHit;

{ The slice index at device-px (X,Y) of a pie/donut centred (ACX,ACY) with outer radius
  AOuterRadius and hole radius AHoleRadius (0 = a solid pie), or -1 for none. The inverse of
  the DrawPie path: same -90 degree offset, same screen-space (Y grows downward) angles. -1
  for a point outside the disc, INSIDE the donut hole (the hole is not the chart), or in a
  zero-sweep slice (nothing was drawn for it). }
function TyChartPieHitTest(X, Y: Integer; ACX, ACY, AOuterRadius, AHoleRadius: Double;
  const ASlices: TTyChartPieSliceArray): Integer;

{ The donut's hole radius: APercent of AOuterRadius, clamped to
  [0, TyChartDonutHoleMaxPercent]. A non-positive outer radius has no hole (0). }
function TyChartDonutHoleRadius(AOuterRadius: Double; APercent: Integer): Double;

{ Where the tooltip box goes, all DEVICE px. Preferred: up and to the RIGHT of the hovered
  datum, AGap away — so the box never covers the datum being read and never sits under the
  cursor. It FLIPS to the other side of the anchor when the preferred side would leave
  ABounds, and is CLAMPED inside ABounds after that. Flip first, clamp second: a datum near
  the right edge gets the box on its left rather than shoved on top of itself. A box larger
  than ABounds is pinned inside it, not hidden — a clipped tooltip still says more than none. }
function TyChartTooltipRect(AAnchorX, AAnchorY, AWidth, AHeight, AGap: Integer;
  const ABounds: TRect): TRect;

{ The default tooltip text for one datum, as the lines the overlay paints (separated by #10):
    line 0 = ACategory        — omitted entirely when empty
    line 1 = '<series>: <value>'  — the prefix omitted when ASeriesName is empty
  APercent >= 0 appends ' (NN.N%)'; pass a negative to omit it (an axes chart has no share
  to quote, a pie does). Values format '0.###' with a '.' decimal separator and no thousands
  grouping — the SAME format as the axis tick labels, because a tooltip that disagreed with
  the axis it is read against would be worse than no tooltip. }
function TyChartDefaultTooltip(const ACategory, ASeriesName: string;
  AValue, APercent: Double): string;

const
  { Fixed, tasteful series palette (Tableau-10). TColor is $00BBGGRR. Series without
    an explicit Color cycle through these by index. }
  TyChartPalette: array[0..7] of TColor = (
    $00A7794E,   // blue    #4E79A7
    $002B8EF2,   // orange  #F28E2B
    $005957E1,   // red     #E15759
    $00B2B776,   // teal    #76B7B2
    $004FA159,   // green   #59A14F
    $0048C9ED,   // yellow  #EDC948
    $00A17AB0,   // purple  #B07AA1
    $00A79DFF);  // pink    #FF9DA7

type
  TTyChart = class;

  { One data series. Values is a comma-separated list of numbers (stream-friendly,
    designer-editable); ValueArray parses it. Color = clDefault -> the palette. }
  TTyChartSeriesItem = class(TCollectionItem)
  private
    FName: string;
    FColor: TColor;
    FValues: string;
    procedure SetName(const AValue: string);
    procedure SetColor(AValue: TColor);
    procedure SetValues(const AValue: string);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(ASource: TPersistent); override;
    { The parsed numeric values ('.' decimal, comma-separated; blanks skipped). }
    function ValueArray: TDoubleArray;
  published
    property Name: string read FName write SetName;
    property Color: TColor read FColor write SetColor default clDefault;
    property Values: string read FValues write SetValues;
  end;

  { The series collection, owned by a TTyChart. }
  TTyChartSeries = class(TCollection)
  private
    FOwner: TPersistent;
    FOnChange: TNotifyEvent;
    function GetItem(AIndex: Integer): TTyChartSeriesItem;
    procedure SetItem(AIndex: Integer; AValue: TTyChartSeriesItem);
  protected
    function GetOwner: TPersistent; override;
    procedure Notify(Item: TCollectionItem; Action: TCollectionNotification); override;
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TPersistent);
    function Add: TTyChartSeriesItem;
    property Items[AIndex: Integer]: TTyChartSeriesItem read GetItem write SetItem; default;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { Fired before the chart paints a tooltip, so the app can put its own words in the box.
    AText arrives holding TyChartDefaultTooltip's result (lines separated by #10) — append
    to it, replace it, or clear it to suppress THIS point's tooltip while leaving the rest
    of the chart's live. ASeries/APoint index Series[] / that series' parsed values. }
  TTyChartTooltipEvent = procedure(Sender: TObject; ASeries, APoint: Integer;
    var AText: string) of object;

  TTyChart = class(TTyGraphicControl)
  private
    FChartType: TTyChartType;
    FSeries: TTyChartSeries;
    FCategories: TStrings;
    FTitle: TCaption;
    FShowLegend: Boolean;
    FShowGrid: Boolean;
    FShowValues: Boolean;
    FShowTooltip: Boolean;
    { The datum under the pointer, or a none-hit. Only ever set from MouseMove/MouseLeave;
      the paint path RE-VALIDATES it against the live data before drawing, because a series
      can shrink out from under a parked hit without the mouse moving. }
    FHoverHit: TTyChartHit;
    FOnGetTooltip: TTyChartTooltipEvent;
    procedure SetChartType(AValue: TTyChartType);
    procedure SetSeries(AValue: TTyChartSeries);
    procedure SetCategories(AValue: TStrings);
    procedure SetTitle(const AValue: TCaption);
    procedure SetShowLegend(AValue: Boolean);
    procedure SetShowGrid(AValue: Boolean);
    procedure SetShowValues(AValue: Boolean);
    procedure SetShowTooltip(AValue: Boolean);
    procedure SeriesChanged(Sender: TObject);
    procedure CategoriesChanged(Sender: TObject);
    { Drop a parked hover hit (and repaint if one was showing). Called whenever the data or
      the chart type changes under the pointer: the old hit indexes data that may be gone. }
    procedure ClearHover;
    { The themed colour of palette slot (AIndex mod 8): the 'TyChartSeries1'..'8' keys, so a
      skin can retint the DATA. Falls back to the built-in TyChartPalette hue. }
    function PaletteColor(AIndex: Integer): TColor;
    { Palette-resolved colour for series AIndex (its own Color, or the cycled palette). }
    function SeriesColor(AItem: TTyChartSeriesItem; AIndex: Integer): TColor;
    { The colour of one pie/donut SLICE (slices are palette-cycled by slice, not by series —
      a pie has one series). One place, so the legend, the disc and the tooltip agree. }
    function SliceColor(AIndex: Integer): TColor;
    { The legend/tooltip name for series AIndex: its Name, or 'Series N'. Shared so the
      legend and the tooltip cannot call the same series two different things. }
    function SeriesDisplayName(AIndex: Integer): string;
    { The X-axis / slice label for point AIndex: its category, or its 1-based number. }
    function CategoryLabel(AIndex: Integer): string;
    { Data extent across every series (or the first series for pie/donut); false if no data. }
    function DataExtent(out AMin, AMax: Double; out AMaxLen: Integer): Boolean;
    { The chart's bands at APPI: TyChartLayoutFor fed from this control's scaled metrics.
      AWidth/AHeight are device px (RenderTo passes its own rect, the hit-test the client
      size), so nothing here reads Width behind the caller's back. }
    function LayoutFor(AWidth, AHeight, APPI: Integer): TTyChartLayout;
    { Everything BOTH the axes paint and the axes hit-test need — the parsed series values,
      the category count and the resolved [niceMin,niceMax] scale — so the two cannot drift.
      False when there is no data to plot. }
    function AxesData(out ASeriesValues: TDoubleArrayArray; out ACatCount: Integer;
      out ANiceMin, ANiceMax, AStep: Double): Boolean;
    { The same contract for a pie/donut: the first series' values, their sweeps, and the
      disc's centre/radii (AHole is 0 for a pie). False when there is nothing to draw. }
    function PieGeometry(const AArea: TRect; APPI: Integer; out AValues: TDoubleArray;
      out ASlices: TTyChartPieSliceArray; out ACX, ACY, ARadius, AHole: Double): Boolean;
    { Re-derive FHoverHit's anchor / swatch / text from the LIVE data, running OnGetTooltip
      last. False when the parked hit no longer indexes anything, or the handler cleared the
      text — either way the overlay is simply not drawn. }
    function HoverTooltip(const ALayout: TTyChartLayout; APPI: Integer;
      out AX, AY: Integer; out ASwatch: TColor; out AText: string): Boolean;
    procedure DrawTitle(P: TTyPainter; const S: TTyStyleSet; var ATop: Integer);
    procedure DrawAxesChart(P: TTyPainter; const S: TTyStyleSet; const APlot: TRect);
    procedure DrawPie(P: TTyPainter; const S: TTyStyleSet; const AArea: TRect; APPI: Integer);
    procedure DrawLegend(P: TTyPainter; const S: TTyStyleSet; const ARect: TRect; ARadial: Boolean);
    procedure DrawTooltip(P: TTyPainter; const S: TTyStyleSet; const ABounds: TRect;
      AAnchorX, AAnchorY: Integer; const AText: string; ASwatch: TColor);
  protected
    function GetStyleTypeKey: string; override;   // 'TyPanel' (the tooltip is 'TyChartTooltip')
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The datum at client device-px (X,Y), or a none-hit (test it with TyChartHitValid).
      Public because it is the same answer the tooltip uses: an app that wants click-to-drill
      reads it from OnClick/OnMouseDown instead of re-deriving the geometry. }
    function HitTestAt(X, Y: Integer): TTyChartHit;
    { Export the chart as an image file. The format follows the extension — .png, .bmp,
      .jpg/.jpeg and .tif are covered (whatever BGRABitmap writes; the TIFF writer is
      linked by this unit). The parameterless form renders at the control's current size;
      the sized form lays the chart out for AWidth x AHeight instead, so a small on-screen
      chart can be exported large. Text keeps the control's PPI in both. }
    procedure SaveToFile(const AFileName: string); overload;
    procedure SaveToFile(const AFileName: string; AWidth, AHeight: Integer); overload;
  published
    property ChartType: TTyChartType read FChartType write SetChartType default ctLine;
    property Series: TTyChartSeries read FSeries write SetSeries;
    property Categories: TStrings read FCategories write SetCategories;
    property Title: TCaption read FTitle write SetTitle;
    property ShowLegend: Boolean read FShowLegend write SetShowLegend default True;
    property ShowGrid: Boolean read FShowGrid write SetShowGrid default True;
    property ShowValues: Boolean read FShowValues write SetShowValues default False;
    { Paint a value tooltip for the datum under the pointer.
      NOT named ShowHint: TControl already publishes ShowHint/Hint (the OS hint window for
      the control as a whole) and this control inherits them — the name is taken, and the
      two are different features anyway. This one is per-DATUM and painted inside the chart. }
    property ShowTooltip: Boolean read FShowTooltip write SetShowTooltip default True;
    { Override the tooltip text. Named for its property (ShowTooltip), not OnGetHint, so the
      pair reads as one feature and neither collides with TControl's OnShowHint. }
    property OnGetTooltip: TTyChartTooltipEvent read FOnGetTooltip write FOnGetTooltip;
    property Align;
    property Anchors;
    property Font;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

implementation

{ ============================ pure geometry ============================ }

{ The 1/2/5-x-10^k "nice number" nearest (round) or not-below (ceil) AValue. }
function NiceNum(AValue: Double; ARound: Boolean): Double;
var
  expo, frac: Double;
begin
  if AValue <= 0 then Exit(1);
  expo := Floor(Log10(AValue));
  frac := AValue / Power(10, expo);
  if ARound then
  begin
    if frac < 1.5 then frac := 1
    else if frac < 3 then frac := 2
    else if frac < 7 then frac := 5
    else frac := 10;
  end
  else
  begin
    if frac <= 1 then frac := 1
    else if frac <= 2 then frac := 2
    else if frac <= 5 then frac := 5
    else frac := 10;
  end;
  Result := frac * Power(10, expo);
end;

procedure TyChartNiceRange(AMin, AMax: Double; ATarget: Integer;
  out ANiceMin, ANiceMax, AStep: Double);
var
  span, tmp: Double;
begin
  if ATarget < 2 then ATarget := 2;
  if AMax < AMin then
  begin
    tmp := AMin; AMin := AMax; AMax := tmp;
  end;
  if AMax <= AMin then AMax := AMin + 1;         // degenerate -> unit span
  span := NiceNum(AMax - AMin, False);
  AStep := NiceNum(span / (ATarget - 1), True);
  if AStep <= 0 then AStep := 1;
  ANiceMin := Floor(AMin / AStep) * AStep;
  ANiceMax := Ceil(AMax / AStep) * AStep;
end;

function TyChartValueToY(AValue, ANiceMin, ANiceMax: Double; ATop, ABottom: Integer): Integer;
var
  frac: Double;
begin
  if ANiceMax <= ANiceMin then Exit(ABottom);
  frac := (AValue - ANiceMin) / (ANiceMax - ANiceMin);
  Result := ABottom - Round(frac * (ABottom - ATop));
end;

procedure TyChartBarXRange(AIndex, ACount, ALeft, ARight: Integer; out AX0, AX1: Integer);
var
  slotW: Double;
  e0, e1, ipad: Integer;
begin
  AX0 := ALeft;
  AX1 := ALeft;
  if (ACount <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  slotW := (ARight - ALeft) / ACount;
  e0 := ALeft + Round(AIndex * slotW);
  e1 := ALeft + Round((AIndex + 1) * slotW);
  ipad := Round(slotW * 0.15);
  if ipad < 1 then ipad := 1;
  AX0 := e0 + ipad;
  AX1 := e1 - ipad;
  if AX1 < AX0 then AX1 := AX0;                  // never invert on a tiny slot
end;

function TyChartPieSweeps(const AValues: array of Double): TTyChartPieSliceArray;
var
  i, n: Integer;
  total, v, start, acc: Double;
begin
  Result := nil;
  n := Length(AValues);
  if n = 0 then Exit;
  SetLength(Result, n);
  total := 0;
  for i := 0 to n - 1 do
    if AValues[i] > 0 then total := total + AValues[i];
  start := 0;
  if total <= 0 then
  begin
    // all-zero / all-negative: every span 0 (safe; no divide by zero)
    for i := 0 to n - 1 do
    begin
      Result[i].StartDeg := 0;
      Result[i].SweepDeg := 0;
    end;
    Exit;
  end;
  acc := 0;
  for i := 0 to n - 1 do
  begin
    if AValues[i] > 0 then v := AValues[i] else v := 0;
    Result[i].StartDeg := start;
    if i = n - 1 then
      Result[i].SweepDeg := 360 - acc          // absorb float remainder -> exact 360
    else
      Result[i].SweepDeg := (v / total) * 360;
    acc := acc + Result[i].SweepDeg;
    start := start + Result[i].SweepDeg;
  end;
end;

function TyChartLayoutFor(AWidth, AHeight: Integer; ARadial, AShowLegend: Boolean;
  AMargin, ATitleHeight, ALegendHeight, AYAxisWidth, AXAxisHeight: Integer): TTyChartLayout;
var
  topY, botY, legendH, contentR: Integer;
begin
  Result.Plot := Rect(0, 0, 0, 0);
  Result.PieArea := Rect(0, 0, 0, 0);
  Result.Legend := Rect(0, 0, 0, 0);
  if (AWidth <= 0) or (AHeight <= 0) then Exit;
  if AMargin < 0 then AMargin := 0;
  if ATitleHeight < 0 then ATitleHeight := 0;
  if ALegendHeight < 0 then ALegendHeight := 0;
  if AYAxisWidth < 0 then AYAxisWidth := 0;
  if AXAxisHeight < 0 then AXAxisHeight := 0;

  if AShowLegend then legendH := ALegendHeight else legendH := 0;
  topY := AMargin + ATitleHeight;          // the title band eats the top of the content
  botY := AHeight - AMargin - legendH;     // the legend strip eats the bottom of it
  contentR := AWidth - AMargin;

  if legendH > 0 then
  begin
    // A radial legend spans the whole content width; an axes legend starts at the plot's
    // left edge, because it labels the series and the series start at the axis.
    if ARadial then
      Result.Legend := Rect(AMargin, botY, contentR, AHeight - AMargin)
    else
      Result.Legend := Rect(AMargin + AYAxisWidth, botY, contentR, AHeight - AMargin);
    if (Result.Legend.Right <= Result.Legend.Left) or
       (Result.Legend.Bottom <= Result.Legend.Top) then
      Result.Legend := Rect(0, 0, 0, 0);
  end;

  if ARadial then
  begin
    // The disc gets the whole content band (DrawPie insets it to a square itself).
    if (contentR > AMargin) and (botY > topY) then
      Result.PieArea := Rect(AMargin, topY, contentR, botY);
  end
  else
  begin
    // A second margin under the title: the plot's top gridline needs air, and the topmost
    // tick label is centred ON that line and would otherwise ride the title's baseline.
    if (contentR > AMargin + AYAxisWidth) and (botY - AXAxisHeight > topY + AMargin) then
      Result.Plot := Rect(AMargin + AYAxisWidth, topY + AMargin, contentR, botY - AXAxisHeight);
  end;
end;

function TyChartBarRect(APointIndex, ACatCount, ASeriesIndex, ASeriesCount: Integer;
  const APlot: TRect; AValue, ANiceMin, ANiceMax: Double): TRect;
var
  cx0, cx1, x0, x1, yv, y0: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ACatCount <= 0) or (ASeriesCount <= 0) then Exit;
  if (APointIndex < 0) or (APointIndex >= ACatCount) then Exit;
  if (ASeriesIndex < 0) or (ASeriesIndex >= ASeriesCount) then Exit;
  // Two nested splits = grouped bars: the plot into category slots, each slot into one bar
  // per series. TyChartBarXRange insets both levels, so neither groups nor bars can overlap.
  TyChartBarXRange(APointIndex, ACatCount, APlot.Left, APlot.Right, cx0, cx1);
  TyChartBarXRange(ASeriesIndex, ASeriesCount, cx0, cx1, x0, x1);
  yv := TyChartValueToY(AValue, ANiceMin, ANiceMax, APlot.Top, APlot.Bottom);
  y0 := TyChartValueToY(0, ANiceMin, ANiceMax, APlot.Top, APlot.Bottom);
  if yv <= y0 then
    Result := Rect(x0, yv, x1, y0)      // at or above the baseline
  else
    Result := Rect(x0, y0, x1, yv);     // below it: a negative value hangs down
end;

function TyChartPointCenter(APointIndex, ACatCount: Integer; const APlot: TRect;
  AValue, ANiceMin, ANiceMax: Double): TPoint;
var
  cx0, cx1: Integer;
begin
  Result := Point(APlot.Left, APlot.Bottom);
  if (ACatCount <= 0) or (APointIndex < 0) or (APointIndex >= ACatCount) then Exit;
  TyChartBarXRange(APointIndex, ACatCount, APlot.Left, APlot.Right, cx0, cx1);
  Result.X := (cx0 + cx1) div 2;
  Result.Y := TyChartValueToY(AValue, ANiceMin, ANiceMax, APlot.Top, APlot.Bottom);
end;

function TyChartNoHit: TTyChartHit;
begin
  Result.SeriesIndex := -1;
  Result.PointIndex := -1;
end;

function TyChartHitValid(const AHit: TTyChartHit): Boolean;
begin
  Result := (AHit.SeriesIndex >= 0) and (AHit.PointIndex >= 0);
end;

function TyChartBarHitTest(X, Y: Integer; const ASeriesValues: TDoubleArrayArray;
  ACatCount: Integer; const APlot: TRect; ANiceMin, ANiceMax: Double): TTyChartHit;
var
  seriesIdx, ptIdx: Integer;
  barR: TRect;
begin
  Result := TyChartNoHit;
  if ACatCount <= 0 then Exit;
  for seriesIdx := 0 to High(ASeriesValues) do
    for ptIdx := 0 to High(ASeriesValues[seriesIdx]) do
    begin
      if ptIdx >= ACatCount then Break;   // past the axis: TyChartBarRect drew nothing
      barR := TyChartBarRect(ptIdx, ACatCount, seriesIdx, Length(ASeriesValues),
        APlot, ASeriesValues[seriesIdx][ptIdx], ANiceMin, ANiceMax);
      // Half-open on both axes, like every hit-test here: adjacent bars share an edge pixel
      // at most once, and a zero-height bar (drawn as nothing) contains nothing.
      if (X >= barR.Left) and (X < barR.Right) and
         (Y >= barR.Top) and (Y < barR.Bottom) then
      begin
        Result.SeriesIndex := seriesIdx;
        Result.PointIndex := ptIdx;
        Exit;
      end;
    end;
end;

function TyChartLineHitTest(X, Y: Integer; const ASeriesValues: TDoubleArrayArray;
  ACatCount: Integer; const APlot: TRect; ANiceMin, ANiceMax: Double;
  ATolerance: Integer): TTyChartHit;
var
  seriesIdx, ptIdx: Integer;
  ctr: TPoint;
  dist2, best, tol2: Double;
begin
  Result := TyChartNoHit;
  if (ACatCount <= 0) or (ATolerance <= 0) then Exit;
  // Compare SQUARED distances: same ordering, no Sqrt per marker.
  tol2 := Double(ATolerance) * ATolerance;
  best := tol2 + 1;
  for seriesIdx := 0 to High(ASeriesValues) do
    for ptIdx := 0 to High(ASeriesValues[seriesIdx]) do
    begin
      if ptIdx >= ACatCount then Break;
      ctr := TyChartPointCenter(ptIdx, ACatCount, APlot,
        ASeriesValues[seriesIdx][ptIdx], ANiceMin, ANiceMax);
      dist2 := Sqr(Double(X - ctr.X)) + Sqr(Double(Y - ctr.Y));
      // Strict '<' against the running best: a tie keeps the FIRST (lowest) series, so the
      // same pixel always answers the same datum.
      if (dist2 <= tol2) and (dist2 < best) then
      begin
        best := dist2;
        Result.SeriesIndex := seriesIdx;
        Result.PointIndex := ptIdx;
      end;
    end;
end;

function TyChartPieHitTest(X, Y: Integer; ACX, ACY, AOuterRadius, AHoleRadius: Double;
  const ASlices: TTyChartPieSliceArray): Integer;
var
  dx, dy, dist, ang: Double;
  i: Integer;
begin
  Result := -1;
  if AOuterRadius <= 0 then Exit;
  if AHoleRadius < 0 then AHoleRadius := 0;
  dx := X - ACX;
  dy := Y - ACY;
  dist := Sqrt(dx * dx + dy * dy);
  if (dist > AOuterRadius) or (dist < AHoleRadius) then Exit;
  // DrawPie places a slice's angle A at (cx + cos(A)*r, cy + sin(A)*r) with A = StartDeg-90,
  // in SCREEN space (Y grows downward). ArcTan2 runs in that same space, so undoing the one
  // -90 offset is the whole inverse.
  ang := RadToDeg(ArcTan2(dy, dx)) + 90;
  while ang < 0 do ang := ang + 360;
  while ang >= 360 do ang := ang - 360;
  for i := 0 to High(ASlices) do
    if (ASlices[i].SweepDeg > 0) and (ang >= ASlices[i].StartDeg) and
       (ang < ASlices[i].StartDeg + ASlices[i].SweepDeg) then
      Exit(i);
end;

function TyChartDonutHoleRadius(AOuterRadius: Double; APercent: Integer): Double;
begin
  if AOuterRadius <= 0 then Exit(0);
  if APercent < 0 then APercent := 0;
  if APercent > TyChartDonutHoleMaxPercent then APercent := TyChartDonutHoleMaxPercent;
  Result := AOuterRadius * APercent / 100;
end;

function TyChartTooltipRect(AAnchorX, AAnchorY, AWidth, AHeight, AGap: Integer;
  const ABounds: TRect): TRect;
var
  boxL, boxT: Integer;
begin
  if AWidth < 0 then AWidth := 0;
  if AHeight < 0 then AHeight := 0;
  if AGap < 0 then AGap := 0;
  // Preferred: up-right of the datum.
  boxL := AAnchorX + AGap;
  boxT := AAnchorY - AGap - AHeight;
  // Flip BEFORE clamping: near the right edge the box belongs on the datum's left, not
  // squashed against the edge on top of it.
  if boxL + AWidth > ABounds.Right then boxL := AAnchorX - AGap - AWidth;
  if boxT < ABounds.Top then boxT := AAnchorY + AGap;
  // Clamp: a box that still does not fit is pinned inside the chart rather than hidden.
  if boxL + AWidth > ABounds.Right then boxL := ABounds.Right - AWidth;
  if boxL < ABounds.Left then boxL := ABounds.Left;
  if boxT + AHeight > ABounds.Bottom then boxT := ABounds.Bottom - AHeight;
  if boxT < ABounds.Top then boxT := ABounds.Top;
  Result := Rect(boxL, boxT, boxL + AWidth, boxT + AHeight);
end;

function TyChartDefaultTooltip(const ACategory, ASeriesName: string;
  AValue, APercent: Double): string;
var
  fmt: TFormatSettings;
  valueLine: string;
begin
  fmt := DefaultFormatSettings;
  fmt.DecimalSeparator := '.';
  fmt.ThousandSeparator := #0;
  valueLine := FormatFloat('0.###', AValue, fmt);
  if APercent >= 0 then
    valueLine := valueLine + ' (' + FormatFloat('0.#', APercent, fmt) + '%)';
  if ASeriesName <> '' then
    valueLine := ASeriesName + ': ' + valueLine;
  Result := valueLine;
  if ACategory <> '' then
    Result := ACategory + #10 + Result;
end;

{ Parse a comma-separated numeric list with a '.' decimal separator. }
function ParseValues(const AText: string): TDoubleArray;
var
  parts: TStringList;
  fs: TFormatSettings;
  i, n: Integer;
  v: Double;
begin
  Result := nil;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  parts := TStringList.Create;
  try
    parts.StrictDelimiter := True;
    parts.Delimiter := ',';
    parts.DelimitedText := AText;
    SetLength(Result, parts.Count);
    n := 0;
    for i := 0 to parts.Count - 1 do
      if Trim(parts[i]) <> '' then
      begin
        v := StrToFloatDef(Trim(parts[i]), 0, fs);
        Result[n] := v;
        Inc(n);
      end;
    SetLength(Result, n);
  finally
    parts.Free;
  end;
end;

{ ============================ TTyChartSeriesItem ============================ }

constructor TTyChartSeriesItem.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FColor := clDefault;
end;

procedure TTyChartSeriesItem.Assign(ASource: TPersistent);
var
  src: TTyChartSeriesItem;
begin
  if ASource is TTyChartSeriesItem then
  begin
    src := TTyChartSeriesItem(ASource);
    FName := src.FName;
    FColor := src.FColor;
    FValues := src.FValues;
    Changed(False);
  end
  else
    inherited Assign(ASource);
end;

function TTyChartSeriesItem.GetDisplayName: string;
begin
  if FName <> '' then Result := FName
  else Result := inherited GetDisplayName;
end;

procedure TTyChartSeriesItem.SetName(const AValue: string);
begin
  if FName = AValue then Exit;
  FName := AValue;
  Changed(False);
end;

procedure TTyChartSeriesItem.SetColor(AValue: TColor);
begin
  if FColor = AValue then Exit;
  FColor := AValue;
  Changed(False);
end;

procedure TTyChartSeriesItem.SetValues(const AValue: string);
begin
  if FValues = AValue then Exit;
  FValues := AValue;
  Changed(False);
end;

function TTyChartSeriesItem.ValueArray: TDoubleArray;
begin
  Result := ParseValues(FValues);
end;

{ ============================ TTyChartSeries ============================ }

constructor TTyChartSeries.Create(AOwner: TPersistent);
begin
  inherited Create(TTyChartSeriesItem);
  FOwner := AOwner;
end;

function TTyChartSeries.GetOwner: TPersistent;
begin
  Result := FOwner;
end;

function TTyChartSeries.Add: TTyChartSeriesItem;
begin
  Result := TTyChartSeriesItem(inherited Add);
end;

function TTyChartSeries.GetItem(AIndex: Integer): TTyChartSeriesItem;
begin
  Result := TTyChartSeriesItem(inherited Items[AIndex]);
end;

procedure TTyChartSeries.SetItem(AIndex: Integer; AValue: TTyChartSeriesItem);
begin
  inherited Items[AIndex] := AValue;
end;

procedure TTyChartSeries.Notify(Item: TCollectionItem; Action: TCollectionNotification);
begin
  inherited Notify(Item, Action);
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyChartSeries.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if Assigned(FOnChange) then FOnChange(Self);
end;

{ ============================ TTyChart ============================ }

constructor TTyChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChartType := ctLine;
  FSeries := TTyChartSeries.Create(Self);
  FSeries.OnChange := @SeriesChanged;
  FCategories := TStringList.Create;
  TStringList(FCategories).OnChange := @CategoriesChanged;
  FShowLegend := True;
  FShowGrid := True;
  FShowValues := False;
  FShowTooltip := True;
  FHoverHit := TyChartNoHit;
  Width := 260;
  Height := 180;
end;

destructor TTyChart.Destroy;
begin
  FSeries.Free;
  FCategories.Free;
  inherited Destroy;
end;

function TTyChart.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': a chart is not a panel: it draws a title, axes, gridlines, a legend and series over the surface, none of which a panel has any concept of.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyChart';
end;

procedure TTyChart.SetChartType(AValue: TTyChartType);
begin
  if FChartType = AValue then Exit;
  FChartType := AValue;
  // A hit means "series S, point P of a BAR chart"; the same indices mean a different
  // pixel (or nothing) once the type changes under the pointer.
  ClearHover;
  Invalidate;
end;

procedure TTyChart.SetSeries(AValue: TTyChartSeries);
begin
  FSeries.Assign(AValue);
  ClearHover;
  Invalidate;
end;

procedure TTyChart.SetCategories(AValue: TStrings);
begin
  FCategories.Assign(AValue);
  ClearHover;
  Invalidate;
end;

procedure TTyChart.SetTitle(const AValue: TCaption);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  Invalidate;
end;

procedure TTyChart.SetShowLegend(AValue: Boolean);
begin
  if FShowLegend = AValue then Exit;
  FShowLegend := AValue;
  Invalidate;
end;

procedure TTyChart.SetShowGrid(AValue: Boolean);
begin
  if FShowGrid = AValue then Exit;
  FShowGrid := AValue;
  Invalidate;
end;

procedure TTyChart.SetShowValues(AValue: Boolean);
begin
  if FShowValues = AValue then Exit;
  FShowValues := AValue;
  Invalidate;
end;

procedure TTyChart.SetShowTooltip(AValue: Boolean);
begin
  if FShowTooltip = AValue then Exit;
  FShowTooltip := AValue;
  // Turning it off must take a tooltip that is ON SCREEN off it, not wait for the next move.
  if not FShowTooltip then FHoverHit := TyChartNoHit;
  Invalidate;
end;

procedure TTyChart.ClearHover;
begin
  if not TyChartHitValid(FHoverHit) then Exit;
  FHoverHit := TyChartNoHit;
  Invalidate;
end;

procedure TTyChart.SeriesChanged(Sender: TObject);
begin
  ClearHover;   // the parked hit may index a value/series that no longer exists
  Invalidate;
end;

procedure TTyChart.CategoriesChanged(Sender: TObject);
begin
  ClearHover;
  Invalidate;
end;

function TTyChart.PaletteColor(AIndex: Integer): TColor;
var
  slot: Integer;
  S: TTyStyleSet;
begin
  slot := AIndex mod Length(TyChartPalette);
  // Each slot is a theme key ('TyChartSeries1'..'TyChartSeries8'), so a skin can retint the
  // DATA and not just the chrome. The base layer defines all eight with the palette's own
  // hues, so this normally resolves; the const stays as the last-resort fallback for a theme
  // that somehow reaches here with no background at all.
  S := ActiveController.Model.ResolveStyle(
    GetStyleTypeKey + 'Series' + IntToStr(slot + 1), StyleClass, []);
  if (tpBackground in S.Present) and (TyAlphaOf(S.Background.Color) > 0) then
    Result := TyColorToLCL(S.Background.Color)
  else
    Result := TyChartPalette[slot];
end;

function TTyChart.SeriesColor(AItem: TTyChartSeriesItem; AIndex: Integer): TColor;
begin
  if AItem.Color = clDefault then
    Result := PaletteColor(AIndex)
  else
    Result := AItem.Color;
end;

function TTyChart.SliceColor(AIndex: Integer): TColor;
begin
  Result := PaletteColor(AIndex);
end;

function TTyChart.SeriesDisplayName(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= FSeries.Count) then Exit;
  Result := FSeries.Items[AIndex].Name;
  // Not a resourcestring: it is a stand-in for missing DATA, and it is what the legend has
  // always drawn — the two must say the same thing.
  if Result = '' then Result := 'Series ' + IntToStr(AIndex + 1);
end;

function TTyChart.CategoryLabel(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FCategories.Count) then
    Result := FCategories[AIndex]
  else
    Result := IntToStr(AIndex + 1);   // the same fallback the X axis draws
end;

function TTyChart.DataExtent(out AMin, AMax: Double; out AMaxLen: Integer): Boolean;
var
  si, vi: Integer;
  vals: TDoubleArray;
  seen: Boolean;
begin
  AMin := 0;
  AMax := 0;
  AMaxLen := 0;
  seen := False;
  for si := 0 to FSeries.Count - 1 do
  begin
    vals := FSeries.Items[si].ValueArray;
    if Length(vals) > AMaxLen then AMaxLen := Length(vals);
    for vi := 0 to High(vals) do
    begin
      if not seen then
      begin
        AMin := vals[vi];
        AMax := vals[vi];
        seen := True;
      end
      else
      begin
        if vals[vi] < AMin then AMin := vals[vi];
        if vals[vi] > AMax then AMax := vals[vi];
      end;
    end;
    if FChartType in [ctPie, ctDonut] then Break;   // radial charts only use the first series
  end;
  Result := seen;
end;

function TTyChart.LayoutFor(AWidth, AHeight, APPI: Integer): TTyChartLayout;
var
  titleH: Integer;
begin
  if APPI <= 0 then APPI := 96;
  if FTitle <> '' then titleH := MulDiv(20, APPI, 96) else titleH := 0;
  // MulDiv(...,APPI,96) is the same logical->device conversion TTyPainter.Scale applies, so
  // the bands the hit-test measures are the bands the paint drew.
  Result := TyChartLayoutFor(AWidth, AHeight, FChartType in [ctPie, ctDonut], FShowLegend,
    MulDiv(8, APPI, 96),    // margin
    titleH,
    MulDiv(18, APPI, 96),   // legend strip
    MulDiv(38, APPI, 96),   // Y tick-label gutter
    MulDiv(16, APPI, 96));  // X category-label band
end;

function TTyChart.AxesData(out ASeriesValues: TDoubleArrayArray; out ACatCount: Integer;
  out ANiceMin, ANiceMax, AStep: Double): Boolean;
var
  dMin, dMax: Double;
  maxLen, i: Integer;
begin
  ASeriesValues := nil;
  ACatCount := 0;
  ANiceMin := 0;
  ANiceMax := 0;
  AStep := 1;
  Result := DataExtent(dMin, dMax, maxLen);
  if not Result then Exit;
  // bars/lines share a zero baseline so heights read honestly
  if dMin > 0 then dMin := 0;
  if dMax < 0 then dMax := 0;
  TyChartNiceRange(dMin, dMax, 5, ANiceMin, ANiceMax, AStep);
  ACatCount := maxLen;
  if FCategories.Count > ACatCount then ACatCount := FCategories.Count;
  if ACatCount < 1 then ACatCount := 1;
  SetLength(ASeriesValues, FSeries.Count);
  for i := 0 to FSeries.Count - 1 do
    ASeriesValues[i] := FSeries.Items[i].ValueArray;
end;

function TTyChart.PieGeometry(const AArea: TRect; APPI: Integer; out AValues: TDoubleArray;
  out ASlices: TTyChartPieSliceArray; out ACX, ACY, ARadius, AHole: Double): Boolean;
begin
  Result := False;
  AValues := nil;
  ASlices := nil;
  ACX := 0;
  ACY := 0;
  ARadius := 0;
  AHole := 0;
  if APPI <= 0 then APPI := 96;
  if FSeries.Count = 0 then Exit;
  AValues := FSeries.Items[0].ValueArray;
  if Length(AValues) = 0 then Exit;
  ASlices := TyChartPieSweeps(AValues);
  ACX := (AArea.Left + AArea.Right) / 2;
  ACY := (AArea.Top + AArea.Bottom) / 2;
  ARadius := Min(AArea.Right - AArea.Left, AArea.Bottom - AArea.Top) / 2 - MulDiv(2, APPI, 96);
  if ARadius < 1 then Exit;
  // A pie is just a donut whose hole is 0 — one geometry, one paint path, one hit-test.
  if FChartType = ctDonut then
    AHole := TyChartDonutHoleRadius(ARadius,
      ActiveController.Metric(TyChartDonutHoleVar, TyChartDonutHolePercent));
  Result := True;
end;

function TTyChart.HitTestAt(X, Y: Integer): TTyChartHit;
var
  lay: TTyChartLayout;
  allVals: TDoubleArrayArray;
  catCount, ppi, sliceIdx: Integer;
  niceMin, niceMax, step: Double;
  pieVals: TDoubleArray;
  slices: TTyChartPieSliceArray;
  pcx, pcy, radius, hole: Double;
begin
  Result := TyChartNoHit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  lay := LayoutFor(ClientWidth, ClientHeight, ppi);
  if FChartType in [ctPie, ctDonut] then
  begin
    if not PieGeometry(lay.PieArea, ppi, pieVals, slices, pcx, pcy, radius, hole) then Exit;
    sliceIdx := TyChartPieHitTest(X, Y, pcx, pcy, radius, hole, slices);
    if sliceIdx >= 0 then
    begin
      // A radial chart plots ONE series, so the slice is the point and the series is 0.
      Result.SeriesIndex := 0;
      Result.PointIndex := sliceIdx;
    end;
  end
  else
  begin
    if (lay.Plot.Right <= lay.Plot.Left) or (lay.Plot.Bottom <= lay.Plot.Top) then Exit;
    if not AxesData(allVals, catCount, niceMin, niceMax, step) then Exit;
    if FChartType = ctBar then
      Result := TyChartBarHitTest(X, Y, allVals, catCount, lay.Plot, niceMin, niceMax)
    else
      Result := TyChartLineHitTest(X, Y, allVals, catCount, lay.Plot, niceMin, niceMax,
        MulDiv(ActiveController.Metric(TyChartHitRadiusVar, TyChartHitRadius), ppi, 96));
  end;
end;

procedure TTyChart.SaveToFile(const AFileName: string);
begin
  SaveToFile(AFileName, Width, Height);
end;

procedure TTyChart.SaveToFile(const AFileName: string; AWidth, AHeight: Integer);
var
  Tmp: TBitmap;
  Bmp: TBGRABitmap;
begin
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EArgumentException.CreateFmt('TTyChart.SaveToFile: invalid size %dx%d',
      [AWidth, AHeight]);
  Tmp := TBitmap.Create;
  try
    Tmp.PixelFormat := pf32bit;
    Tmp.SetSize(AWidth, AHeight);
    RenderTo(Tmp.Canvas, Rect(0, 0, AWidth, AHeight), Font.PixelsPerInch);
    Bmp := TBGRABitmap.Create(Tmp);
    try
      { A GDI-drawn 32-bit surface reads back with alpha 0 (GDI never writes the alpha
        plane), which would export a fully transparent PNG. The chart paints its themed
        background over the whole rect, so the picture IS opaque — say so. }
      Bmp.AlphaFill(255);
      Bmp.SaveToFile(AFileName);
    finally
      Bmp.Free;
    end;
  finally
    Tmp.Free;
  end;
end;

procedure TTyChart.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  hit: TTyChartHit;
begin
  inherited MouseMove(Shift, X, Y);
  if not FShowTooltip then Exit;
  hit := HitTestAt(X, Y);
  // Repaint only when the DATUM changes, not on every pixel of travel: the whole chart is
  // re-rendered from scratch each paint, so a per-pixel invalidate would be visible work.
  if (hit.SeriesIndex <> FHoverHit.SeriesIndex) or (hit.PointIndex <> FHoverHit.PointIndex) then
  begin
    FHoverHit := hit;
    Invalidate;
  end;
end;

procedure TTyChart.MouseLeave;
begin
  inherited MouseLeave;
  ClearHover;
end;

function TTyChart.HoverTooltip(const ALayout: TTyChartLayout; APPI: Integer;
  out AX, AY: Integer; out ASwatch: TColor; out AText: string): Boolean;
var
  allVals: TDoubleArrayArray;
  catCount, seriesIdx, ptIdx, i: Integer;
  niceMin, niceMax, step: Double;
  pieVals: TDoubleArray;
  slices: TTyChartPieSliceArray;
  pcx, pcy, radius, hole, total, pct, mid, anchorR: Double;
  barR: TRect;
  ctr: TPoint;
begin
  Result := False;
  AX := 0;
  AY := 0;
  ASwatch := clDefault;
  AText := '';
  seriesIdx := FHoverHit.SeriesIndex;
  ptIdx := FHoverHit.PointIndex;
  // Re-validate against the LIVE data: the hit was parked on a mouse move, and the series
  // can have shrunk since without the pointer moving.
  if (seriesIdx < 0) or (seriesIdx >= FSeries.Count) or (ptIdx < 0) then Exit;

  if FChartType in [ctPie, ctDonut] then
  begin
    if not PieGeometry(ALayout.PieArea, APPI, pieVals, slices, pcx, pcy, radius, hole) then Exit;
    if ptIdx > High(pieVals) then Exit;
    if slices[ptIdx].SweepDeg <= 0 then Exit;   // nothing was drawn there
    total := 0;
    for i := 0 to High(pieVals) do
      if pieVals[i] > 0 then total := total + pieVals[i];
    if (total > 0) and (pieVals[ptIdx] > 0) then
      pct := (pieVals[ptIdx] / total) * 100
    else
      pct := -1;   // a clamped (zero/negative) slice has no share to quote
    // Anchor on the slice's own mid-arc, in the middle of the RING (which is the middle of
    // the radius for a pie, hole = 0) — the tooltip should point at the wedge, not the centre.
    mid := DegToRad(slices[ptIdx].StartDeg + slices[ptIdx].SweepDeg / 2 - 90);
    anchorR := hole + (radius - hole) / 2;
    AX := Round(pcx + Cos(mid) * anchorR);
    AY := Round(pcy + Sin(mid) * anchorR);
    ASwatch := SliceColor(ptIdx);
    // The slice's identity IS its category (that is what the pie legend lists), so no
    // 'Series 1' prefix is forced here — only a series the app actually named shows up.
    AText := TyChartDefaultTooltip(CategoryLabel(ptIdx), FSeries.Items[seriesIdx].Name,
      pieVals[ptIdx], pct);
  end
  else
  begin
    if (ALayout.Plot.Right <= ALayout.Plot.Left) or
       (ALayout.Plot.Bottom <= ALayout.Plot.Top) then Exit;
    if not AxesData(allVals, catCount, niceMin, niceMax, step) then Exit;
    if seriesIdx > High(allVals) then Exit;
    if ptIdx > High(allVals[seriesIdx]) then Exit;
    if FChartType = ctBar then
    begin
      barR := TyChartBarRect(ptIdx, catCount, seriesIdx, Length(allVals), ALayout.Plot,
        allVals[seriesIdx][ptIdx], niceMin, niceMax);
      if barR.Right <= barR.Left then Exit;
      // The top-centre of the bar: the end the eye reads the value off.
      AX := (barR.Left + barR.Right) div 2;
      AY := barR.Top;
    end
    else
    begin
      ctr := TyChartPointCenter(ptIdx, catCount, ALayout.Plot,
        allVals[seriesIdx][ptIdx], niceMin, niceMax);
      AX := ctr.X;
      AY := ctr.Y;
    end;
    ASwatch := SeriesColor(FSeries.Items[seriesIdx], seriesIdx);
    // -1 percent: an axes chart's bars are read against the axis, not against each other,
    // so a share of the total would be a number the chart never claims.
    AText := TyChartDefaultTooltip(CategoryLabel(ptIdx), SeriesDisplayName(seriesIdx),
      allVals[seriesIdx][ptIdx], -1);
  end;

  // The app gets the last word, including 'no tooltip for THIS point' (clear AText).
  if Assigned(FOnGetTooltip) then FOnGetTooltip(Self, seriesIdx, ptIdx, AText);
  Result := AText <> '';
end;

procedure TTyChart.DrawTitle(P: TTyPainter; const S: TTyStyleSet; var ATop: Integer);
var
  h: Integer;
begin
  if FTitle = '' then Exit;
  h := P.Scale(20);
  { Left is the horizontal margin, NOT ATop (the running Y cursor) -- they coincide only
    when the title is the first thing drawn. }
  P.DrawText(Rect(P.Scale(8), ATop, P.Bitmap.Width - P.Scale(8), ATop + h),
    FTitle, Font.Name, 11, 700, S.TextColor, taCenter, tlCenter, True);
  Inc(ATop, h);
end;

procedure TTyChart.DrawLegend(P: TTyPainter; const S: TTyStyleSet; const ARect: TRect; ARadial: Boolean);
var
  i, x, sw, gap, tw, cnt, boxSz: Integer;
  nm: string;
  cy: Integer;
  swatch: TColor;
begin
  boxSz := P.Scale(10);
  gap := P.Scale(6);
  sw := P.Scale(14);
  x := ARect.Left;
  cy := (ARect.Top + ARect.Bottom) div 2;
  if ARadial then
    cnt := FCategories.Count   // a radial legend lists the SLICES, which are the categories
  else
    cnt := FSeries.Count;
  for i := 0 to cnt - 1 do
  begin
    if ARadial then
    begin
      nm := FCategories[i];
      swatch := SliceColor(i);
    end
    else
    begin
      nm := SeriesDisplayName(i);
      swatch := SeriesColor(FSeries.Items[i], i);
    end;
    P.Bitmap.FillRect(x, cy - boxSz div 2, x + boxSz, cy + boxSz div 2,
      ColorToBGRA(swatch), dmSet);
    Inc(x, boxSz + P.Scale(4));
    tw := P.MeasureText(nm, Font.Name, 9, 400).cx;
    P.DrawText(Rect(x, ARect.Top, x + tw + P.Scale(2), ARect.Bottom),
      nm, Font.Name, 9, 400, S.TextColor, taLeftJustify, tlCenter, False);
    Inc(x, tw + sw + gap);
    if x > ARect.Right then Break;
  end;
end;

procedure TTyChart.DrawAxesChart(P: TTyPainter; const S: TTyStyleSet; const APlot: TRect);
var
  niceMin, niceMax, step, v: Double;
  catCount, seriesCount, si, ci: Integer;
  allVals: TDoubleArrayArray;
  ctx: TBGRACanvas2D;
  gridPx, axisPx: TBGRAPixel;
  y, cx0, cx1, px, py: Integer;
  vals: TDoubleArray;
  fs: TFormatSettings;
  lbl: string;
  seriesItem: TTyChartSeriesItem;
  seriesPx: TBGRAPixel;
  first: Boolean;
  barR: TRect;
  ctr: TPoint;
begin
  // One seam with the hit-test: same values, same category count, same [niceMin,niceMax].
  if not AxesData(allVals, catCount, niceMin, niceMax, step) then Exit;
  seriesCount := FSeries.Count;

  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';

  ctx := P.Bitmap.Canvas2D;
  gridPx := TyColorToBGRA(S.BorderColor);
  gridPx.alpha := 70;
  axisPx := TyColorToBGRA(S.BorderColor);

  // horizontal grid + Y tick labels
  v := niceMin;
  while v <= niceMax + step / 2 do
  begin
    y := TyChartValueToY(v, niceMin, niceMax, APlot.Top, APlot.Bottom);
    if FShowGrid then
    begin
      ctx.beginPath;
      ctx.moveTo(APlot.Left, y + 0.5);
      ctx.lineTo(APlot.Right, y + 0.5);
      ctx.lineWidth := 1;
      ctx.strokeStyle(gridPx);
      ctx.stroke;
    end;
    if Abs(v) < 1e9 then lbl := FormatFloat('0.###', v, fs) else lbl := '';
    P.DrawText(Rect(APlot.Left - P.Scale(34), y - P.Scale(8), APlot.Left - P.Scale(3), y + P.Scale(8)),
      lbl, Font.Name, 8, 400, S.TextColor, taRightJustify, tlCenter, False);
    v := v + step;
  end;

  // axes (left + bottom)
  ctx.beginPath;
  ctx.moveTo(APlot.Left + 0.5, APlot.Top);
  ctx.lineTo(APlot.Left + 0.5, APlot.Bottom + 0.5);
  ctx.lineTo(APlot.Right, APlot.Bottom + 0.5);
  ctx.lineWidth := 1;
  ctx.strokeStyle(axisPx);
  ctx.stroke;

  // X category labels
  for ci := 0 to catCount - 1 do
  begin
    TyChartBarXRange(ci, catCount, APlot.Left, APlot.Right, cx0, cx1);
    lbl := CategoryLabel(ci);   // the same label the tooltip quotes
    P.DrawText(Rect(cx0 - P.Scale(4), APlot.Bottom + P.Scale(2), cx1 + P.Scale(4), APlot.Bottom + P.Scale(16)),
      lbl, Font.Name, 8, 400, S.TextColor, taCenter, tlCenter, False);
  end;

  // series. Each is drawn in full before the next, so a later series overlaps an earlier
  // one's line -- but NOT its bars: TyChartBarRect gives every (series, category) its own
  // x-slot, which is what makes multi-series bars read as a GROUP per category.
  for si := 0 to seriesCount - 1 do
  begin
    seriesItem := FSeries.Items[si];
    vals := allVals[si];
    seriesPx := ColorToBGRA(SeriesColor(seriesItem, si));
    if FChartType = ctBar then
    begin
      for ci := 0 to High(vals) do
      begin
        // The SAME rect the hit-test scans -- neither can drift from the other.
        barR := TyChartBarRect(ci, catCount, si, seriesCount, APlot, vals[ci], niceMin, niceMax);
        P.Bitmap.FillRect(barR.Left, barR.Top, barR.Right, barR.Bottom, seriesPx, dmSet);
        if FShowValues then
        begin
          // Anchored on the VALUE's y, not the bar's top: for a negative bar those differ,
          // and the label belongs by the value line either way.
          y := TyChartValueToY(vals[ci], niceMin, niceMax, APlot.Top, APlot.Bottom);
          P.DrawText(Rect(barR.Left - P.Scale(6), y - P.Scale(14), barR.Right + P.Scale(6), y - P.Scale(1)),
            FormatFloat('0.###', vals[ci], fs), Font.Name, 8, 400, S.TextColor,
            taCenter, tlBottom, False);
        end;
      end;
    end
    else  // ctLine
    begin
      first := True;
      ctx.beginPath;
      ctx.lineWidth := P.Scale(2);
      ctx.lineJoin := 'round';
      ctx.strokeStyle(seriesPx);
      for ci := 0 to High(vals) do
      begin
        ctr := TyChartPointCenter(ci, catCount, APlot, vals[ci], niceMin, niceMax);
        if first then begin ctx.moveTo(ctr.X, ctr.Y); first := False; end
        else ctx.lineTo(ctr.X, ctr.Y);
      end;
      ctx.stroke;
      // point markers + optional values
      for ci := 0 to High(vals) do
      begin
        // The SAME centre the hit-test measures its grab radius from.
        ctr := TyChartPointCenter(ci, catCount, APlot, vals[ci], niceMin, niceMax);
        px := ctr.X;
        py := ctr.Y;
        ctx.beginPath;
        ctx.arc(px, py, P.Scale(3), 0, 2 * Pi, False);
        ctx.fillStyle(seriesPx);
        ctx.fill;
        if FShowValues then
          P.DrawText(Rect(px - P.Scale(16), py - P.Scale(15), px + P.Scale(16), py - P.Scale(2)),
            FormatFloat('0.###', vals[ci], fs), Font.Name, 8, 400, S.TextColor,
            taCenter, tlBottom, False);
      end;
    end;
  end;
end;

procedure TTyChart.DrawPie(P: TTyPainter; const S: TTyStyleSet; const AArea: TRect; APPI: Integer);
var
  vals: TDoubleArray;
  slices: TTyChartPieSliceArray;
  ctx: TBGRACanvas2D;
  cx, cy, radius, hole, a0, a1, mid, total, labelR: Double;
  i, lx, ly: Integer;
  sepPx: TBGRAPixel;
  fs: TFormatSettings;
begin
  // One seam with the hit-test: same centre, same radii, same sweeps.
  if not PieGeometry(AArea, APPI, vals, slices, cx, cy, radius, hole) then Exit;

  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  total := 0;
  for i := 0 to High(vals) do
    if vals[i] > 0 then total := total + vals[i];

  ctx := P.Bitmap.Canvas2D;
  sepPx := TyColorToBGRA(S.Background.Color);
  for i := 0 to High(slices) do
  begin
    if slices[i].SweepDeg <= 0 then Continue;
    a0 := DegToRad(slices[i].StartDeg - 90);
    a1 := DegToRad(slices[i].StartDeg + slices[i].SweepDeg - 90);
    // ONE path for both types: a wedge is the hole=0 case of a ring. Out along the start
    // edge, round the outer arc, back in along the end edge, and back along the inner arc
    // (reversed, so the two arcs wind opposite and the hole is a hole under either fill
    // rule). At hole=0 both radial segments collapse onto the centre and this is exactly
    // the old moveTo(centre)/arc/closePath wedge -- same pixels for ctPie.
    ctx.beginPath;
    ctx.moveTo(cx + Cos(a0) * hole, cy + Sin(a0) * hole);
    ctx.lineTo(cx + Cos(a0) * radius, cy + Sin(a0) * radius);
    ctx.arc(cx, cy, radius, a0, a1, False);
    ctx.lineTo(cx + Cos(a1) * hole, cy + Sin(a1) * hole);
    if hole > 0 then
      ctx.arc(cx, cy, hole, a1, a0, True);
    ctx.closePath;
    ctx.fillStyle(ColorToBGRA(SliceColor(i)));
    ctx.fill;
    // Thin separator in the surface colour. It traces the ring's inner edge too, so the
    // donut's hole gets a clean rim for free.
    ctx.lineWidth := P.Scale(1);
    ctx.strokeStyle(sepPx);
    ctx.stroke;
    if FShowValues and (total > 0) then
    begin
      mid := DegToRad(slices[i].StartDeg + slices[i].SweepDeg / 2 - 90);
      // 60% along the RING's thickness. At hole=0 that is 0.6*radius -- the pie's old spot.
      labelR := hole + (radius - hole) * 0.6;
      lx := Round(cx + Cos(mid) * labelR);
      ly := Round(cy + Sin(mid) * labelR);
      P.DrawText(Rect(lx - P.Scale(20), ly - P.Scale(8), lx + P.Scale(20), ly + P.Scale(8)),
        FormatFloat('0.#', (vals[i] / total) * 100, fs) + '%', Font.Name, 8, 700,
        S.TextColor, taCenter, tlCenter, False);
    end;
  end;
end;

procedure TTyChart.DrawTooltip(P: TTyPainter; const S: TTyStyleSet; const ABounds: TRect;
  AAnchorX, AAnchorY: Integer; const AText: string; ASwatch: TColor);
var
  tipS: TTyStyleSet;
  tipLines: TStringList;
  i, fontSz, lineH, maxW, tw, boxW, boxH: Integer;
  padL, padR, padT, padB, swSz, swGap, gap, textX, lineTop: Integer;
  box, swR: TRect;
  fname: string;
  ink: TTyColor;
begin
  tipLines := TStringList.Create;
  try
    tipLines.Text := AText;   // the #10-separated lines TyChartDefaultTooltip built
    if tipLines.Count = 0 then Exit;

    // Its OWN typeKey, resolved with the CHART's StyleClass so 'TyChartTooltip.compact' can
    // follow a 'TyChart.compact'. No :hover/:focus -- the box only exists while hovering.
    tipS := ActiveController.Model.ResolveStyle('TyChartTooltip', StyleClass, [tysNormal]);
    fname := tipS.FontName;
    fontSz := TyResolveFontSize(tipS, ParentFont, Font.Size, ActiveController);
    // A stable reference glyph, so every line gets the same height whatever it contains.
    lineH := P.MeasureText('Ag', fname, fontSz, tipS.FontWeight).cy;
    if lineH < 1 then lineH := 1;
    maxW := 0;
    for i := 0 to tipLines.Count - 1 do
    begin
      tw := P.MeasureText(tipLines[i], fname, fontSz, tipS.FontWeight).cx;
      if tw > maxW then maxW := tw;
    end;

    padL := P.Scale(tipS.Padding.Left);
    padR := P.Scale(tipS.Padding.Right);
    padT := P.Scale(tipS.Padding.Top);
    padB := P.Scale(tipS.Padding.Bottom);
    swSz := P.Scale(ActiveController.Metric(TyChartTooltipSwatchVar, TyChartTooltipSwatch));
    swGap := P.Scale(ActiveController.Metric(TyChartTooltipSwatchGapVar, TyChartTooltipSwatchGap));
    gap := P.Scale(ActiveController.Metric(TyChartTooltipGapVar, TyChartTooltipGap));
    if swSz < 0 then swSz := 0;
    if swGap < 0 then swGap := 0;

    // Every line is indented past the swatch column, so the block reads as one paragraph
    // rather than a chip with a ragged label beside it.
    textX := padL + swSz + swGap;
    boxW := textX + maxW + padR;
    boxH := padT + tipLines.Count * lineH + padB;
    box := TyChartTooltipRect(AAnchorX, AAnchorY, boxW, boxH, gap, ABounds);

    // NOT DrawFrame: that is the CONTROL's frame path and it pushes tpOpacity onto the
    // painter, which EndPaint then applies to the WHOLE bitmap -- a tooltip style with an
    // opacity would fade the entire chart. A sub-element paints its own surface (the
    // TTyTag close-chip pattern). Absent tokens simply draw nothing, never a hard-coded
    // colour: a theme that defines no TyChartTooltip background gets no box.
    if (tpShadow in tipS.Present) and (TyAlphaOf(tipS.ShadowColor) > 0) then
      P.DropShadow(box, tipS.BorderRadius, tipS.ShadowColor, tipS.ShadowBlur, tipS.ShadowOffset);
    if tpBackground in tipS.Present then
      P.FillBackground(box, tipS.Background, TyEffectiveCorners(tipS));
    if TyBorderVisible(tipS) then
      P.StrokeBorder(box, TyEffectiveCorners(tipS), tipS.BorderWidth, tipS.BorderColor);

    // No TyChartTooltip colour -> the panel's own ink; never a hard-coded colour.
    if tpTextColor in tipS.Present then ink := tipS.TextColor else ink := S.TextColor;

    if swSz > 0 then
    begin
      // Centred on the LAST line -- the value line, which is the one the swatch identifies.
      // A square chip, matching the legend's swatches exactly (same idea, same shape).
      swR.Left := box.Left + padL;
      swR.Right := swR.Left + swSz;
      swR.Top := box.Top + padT + (tipLines.Count - 1) * lineH + (lineH - swSz) div 2;
      if swR.Top < box.Top then swR.Top := box.Top;
      swR.Bottom := swR.Top + swSz;
      P.Bitmap.FillRect(swR.Left, swR.Top, swR.Right, swR.Bottom, ColorToBGRA(ASwatch), dmSet);
    end;

    for i := 0 to tipLines.Count - 1 do
    begin
      lineTop := box.Top + padT + i * lineH;
      // No ellipsis: the box was measured to fit these exact lines.
      P.DrawText(Rect(box.Left + textX, lineTop, box.Right - padR, lineTop + lineH),
        tipLines[i], fname, fontSz, tipS.FontWeight, ink, taLeftJustify, tlCenter, False);
    end;
  finally
    tipLines.Free;
  end;
end;

procedure TTyChart.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
  lay: TTyChartLayout;
  topY, tipX, tipY: Integer;
  radial: Boolean;
  tipText: string;
  tipSwatch: TColor;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
    begin
      P.EndPaint;
      Exit;
    end;

    DrawFrame(P, R, S);   // panel background + border (themed)

    topY := P.Scale(8);
    DrawTitle(P, S, topY);   // still the running cursor: the title owns the top band

    // The SAME bands the hit-test measured against; empty rects are already degenerate-safe.
    lay := LayoutFor(R.Right - R.Left, R.Bottom - R.Top, APPI);
    radial := FChartType in [ctPie, ctDonut];

    if radial then
    begin
      if (lay.PieArea.Right > lay.PieArea.Left) and (lay.PieArea.Bottom > lay.PieArea.Top) then
        DrawPie(P, S, lay.PieArea, APPI);
    end
    else
    begin
      if (lay.Plot.Right > lay.Plot.Left) and (lay.Plot.Bottom > lay.Plot.Top) then
        DrawAxesChart(P, S, lay.Plot);
    end;
    if (lay.Legend.Right > lay.Legend.Left) then
      DrawLegend(P, S, lay.Legend, radial);

    // LAST: the tooltip is an overlay and must sit above every series, the legend and the
    // axes. Bounded by the whole control rect, so it may hang over the chrome -- that is
    // what an overlay is for, and TyChartTooltipRect keeps it inside the control.
    if FShowTooltip and TyChartHitValid(FHoverHit) and
       HoverTooltip(lay, APPI, tipX, tipY, tipSwatch, tipText) then
      DrawTooltip(P, S, R, tipX, tipY, tipText, tipSwatch);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyChart.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

initialization
  RegisterClass(TTyChart);
end.
