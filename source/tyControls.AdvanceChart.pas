unit tyControls.AdvanceChart;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the control the whole AdvChart layer exists under.

  WINDOWED, not graphic, and that decision was made on day one: focus, keyboard,
  an in-chart scrollbar, a dataZoom slider and a toolbox all need a handle, and
  retrofitting one onto a graphic control means rewriting every interaction it
  already had.

  CONFIGURED BY AN OPTION TREE, not by published properties. Roughly 1,950
  option paths do not fit in an Object Inspector, and an ECharts-shaped option
  makes ECharts' documentation, its gallery and a decade of answers on the
  internet usable as they are. Option is a string; everything else is derived.

  WHAT IT DRAWS TODAY. The pipeline runs end to end -- option to axes and
  coordinate systems, series bound to their axes, data read into columnar
  stores, value ranges unioned, labels measured and the plot rect shrunk to fit
  them -- and the AXIS DOMAIN is painted from the theme. Series marks are
  deliberately not here: twenty-three renderers are Tier 1, and the point of
  this control is that when they arrive they have a coordinate system, a style
  resolver and a paint list waiting rather than a blank file.

  EVERY VISUAL VALUE COMES FROM THE THEME. Eight typeKeys and four metrics, none
  of them a literal in this file. That is the library's hard rule and it is why
  the chart follows a skin instead of looking pasted onto one. }
interface
uses
  Classes, SysUtils, Math, Types, Controls, Graphics, LCLType,
  BGRABitmap,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.StyleModel,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
  tyControls.AdvChart.Measure, tyControls.AdvChart.Handlers,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Render,
  tyControls.AdvChart.Marks, tyControls.AdvChart.BarLayout,
  tyControls.AdvChart.Stack, tyControls.AdvChart.Symbol,
  tyControls.AdvChart.Color,
  tyControls.AdvChart.Pie, tyControls.AdvChart.Title,
  tyControls.AdvChart.Labels, tyControls.AdvChart.LabelOpt,
  tyControls.AdvChart.PieLabel, tyControls.AdvChart.Legend,
  tyControls.AdvChart.Dataset,
  fpjson, tyControls.SubPixel;

const
  { The four axis metrics, and the defaults to fall back on when a theme has not
    been loaded at all. The names are the theme's; the numbers match what the
    option model documents so a chart looks the same before and after a skin. }
  TyAdvChartTickLenVar = '--advchart-tick-length';
  TyAdvChartTickLen = 5;
  TyAdvChartMinorTickLenVar = '--advchart-minor-tick-length';
  TyAdvChartMinorTickLen = 3;
  TyAdvChartLabelMarginVar = '--advchart-label-margin';
  TyAdvChartLabelMargin = 8;
  TyAdvChartNameGapVar = '--advchart-name-gap';
  TyAdvChartNameGap = 15;

type
  TTyAdvanceChart = class(TTyCustomControl)
  private
    FOption: TTyChartOption;
    FBuild: TTyChartBuild;
    FIndex: TTyAxisSeriesIndex;
    FBindings: TTySeriesBindingArray;
    FStores: array of TTyDataStore;
    { Every bar's width and offset, index-parallel to FBindings. Solved in
      Relayout rather than Rebuild because it needs the FINAL pixel extents:
      the plot rect is shrunk to fit the labels in phase C, and a band measured
      before that is the wrong width -- silently, since nothing raises and the
      bars merely come out slightly off. }
    FBarCols: TTyBarColumnArray;
    { Which series accumulate onto which, and into which columns. Solved in
      Rebuild, between filling the stores and sizing the axes: the totals have
      to exist before the value axis is asked how far it must reach. }
    FStacks: TTySeriesStackArray;
    { One entry per binding, meaningful only where the series is a pie.
      Solved in Relayout for the same reason FBarCols is: a pie centred on
      a percentage of its box needs the box in final pixels. }
    FPies: array of TTyPieLayout;
    { Index-parallel to FPies. The paint pass needs showEmptyCircle, and the
      mark builder is a pure unit that cannot re-read the option. }
    FPieSpecs: array of TTyPieSpec;
    { Every title the option carries, laid out. A title floats over the
      container and shrinks nothing, so this is solved beside the grids
      rather than before them. }
    FTitles: array of TTyTitleLayout;
    FTitleSpecs: array of TTyTitleSpec;
    { Every legend the option carries, in two halves. The ENTRIES and the
      SELECTION need nothing but the option and the stores, so they settle in
      Rebuild; the LAYOUT has to measure the words, so it waits for Relayout
      like the axes and the title. }
    FLegendSpecs: array of TTyLegendSpec;
    FLegendEntries: array of TTyLegendEntryArray;
    FLegendFlags: array of TTyLegendFlags;
    FLegends: array of TTyLegendLayout;
    { Whose rows KeepSlice is deciding about, for the length of one
      FilterSelf call and no longer. }
    FFilterStore: TTyDataStore;
    { The table each series reads, AS THAT SERIES READS IT -- so this is one
      per series and not one per dataset. Two series may read one table in
      two directions, and upstream builds two sources for exactly that
      reason. Index-parallel to FBindings. }
    FSources: array of TTyChartSource;
    { Which dataset each series reads, -1 for none, and what its columns
      mean. Both index-parallel to FBindings. }
    FSeriesDataset: array of Integer;
    FEncodes: array of TTySeriesEncode;
    { WHAT THE AUTHOR'S PALETTE GAVE EACH SERIES, resolved once per rebuild.
      Empty where they gave it nothing, and the theme's ramp answers instead
      -- so a chart with no `color` written is still the skin's chart, and one
      with `color` written is the author's. Index-parallel to the option's
      series SLOTS, not to FBindings: a series that did not resolve still
      takes its colour, because upstream's palette pass runs over the raw
      series and that is what keeps colours still across a legend click. }
    FSeriesColors: array of TTyChartColor;
    FSeriesColorKnown: array of Boolean;
    { AND THE PALETTE PICK ITSELF, kept apart from the resolved colour
      because `auto` resolves to the PICK and not to the fill. A series that
      writes `itemStyle: { color: '#fff', borderColor: 'auto' }` is white
      with a border in the palette colour -- so both numbers exist at once
      and one field could not hold them. }
    FSeriesPalette: array of TTyChartColor;
    FSeriesPaletteKnown: array of Boolean;
    FDirty: Boolean;
    FLastRect: TTyRectF;
    FOptionText: string;
    { THE STATIC LAYER. Everything whose appearance is decided by the model --
      frame, axes, grid, labels -- rendered once and blitted per frame.

      FStaticPPI is part of the key and TTyPaintCache is not: NeedsRender only
      notices a SIZE change, and a per-monitor DPI move can hand the same size
      at a different PPI. }
    FStatic: TTyPaintCache;
    FStaticPPI: Integer;
    procedure SetOptionText(const AValue: string);
    function GetOptionText: string;
    function GetErrorText: string;
    procedure FreeStores;
    procedure DropBuild;
    { Option to axes, series and stores. Cheap enough to redo on a resize; the
      expensive half is the label measuring in Relayout. }
    procedure Rebuild;
    { The half that needs a painter, because it has to MEASURE the labels before
      it can know how much room the plot has left. }
    procedure Relayout(APainter: TTyPainter; const ARect: TTyRectF;
      APPI: Integer; const AMeasurer: ITyTextMeasurer);
    procedure PaintAxis(APainter: TTyPainter; AAxis: TTyAxis;
      const APlot: TTyRectF; APPI: Integer; AGrid: TTyGridBuild;
      const AMeasurer: ITyTextMeasurer);
    { THE TWO LAYERS, split by what makes them change rather than by what they
      look like. Static is everything the model decides; dynamic is what moves
      while the model stands still. }
    procedure PaintStatic(APainter: TTyPainter; const ARect: TRect;
      APPI: Integer; const AMeasurer: ITyTextMeasurer);
    { Every series' marks, in one list, ordered once. }
    procedure PaintSeries(APainter: TTyPainter;
      const AMeasurer: ITyTextMeasurer; APPI: Integer);
    { The theme colour for series ASeriesIndex, from the DERIVED ramp item 18
      landed: TyAdvChartSeries1..8, all of them computed from --accent so a skin
      that restyles the accent gets a matching chart for nothing. }
    procedure SolveSeriesColors;
    { The THEME's ramp at ASlot, with nothing of the option in it. Split out
      because a pie's slices and a chart's series both cycle it, and they
      index it by different things. }
    function ThemeRampColor(ASlot: Integer): TTyColor;
    { What `auto` means on this series: the palette's pick for it. }
    function SeriesPaletteColor(ASeriesIndex: Integer): TTyColor;
    { What the author wrote on this series' style blocks, laid over the
      palette colour the visual already carries. }
    procedure ApplyOptStyle(var AVisual: TTySeriesVisual; ASlot: Integer);
    function SeriesColor(ASeriesIndex: Integer): TTyColor;
    { The stack record for a series slot, or an unstacked one. }
    function StackFor(ASlot: Integer): TTySeriesStack;
    { The symbol spec for a series slot, over its type's own default. }
    function SymbolFor(ASlot: Integer): TTySymbolSpec;
    { The label interval the layout gave this axis, or 1 when it draws them
      all. }
    function LabelStepFor(AAxis: TTyAxis): Integer;
    { Every pie series laid out. Runs in Relayout, after phase C, for the
      same reason the bar solver does: a percentage of a box needs the box
      in final pixels. }
    procedure SolvePies;
    { Every title, measured and placed. Needs the measurer, so it runs in
      Relayout beside the axis pass rather than in Rebuild. }
    procedure SolveTitles(const AMeasurer: ITyTextMeasurer; APPI: Integer);
    { The two title fonts, resolved from the theme. }
    function TitleFont(const AKey: string): TTyTitleFont;
    procedure PaintTitles(APainter: TTyPainter);
    { One colour per SECTOR, not one per series: a pie is colorBy:data. }
    function PieVisual(ASlot: Integer): TTyPieVisual;
    { The label spec for one series, resolved from the theme and the option. }
    function LabelSpecFor(ASlot: Integer): TTyLabelSpec;
    { The fonts and the four inks a pie label is drawn with. }
    function PieLabelInk: TTyPieLabelInk;
    { `series.name`, which is what `{a}` in a label formatter means -- and,
      for a series that named itself nothing and reads a dataset, the name
      of the dimension it took its values from. }
    function SeriesNameOf(ASlot: Integer): string;
    { The two name lists a legend needs: what it falls back to when the
      option lists no `data`, and what it is allowed to match. They are not
      the same list -- see the body. }
    procedure LegendNames(out APotential, AAvailable: TTyLegendNames);
    { `series.symbol` as written, '' when the option did not name one. What
      the legend makes of it is the legend's business. }
    function SeriesSymbolWord(ASlot: Integer): string;
    { What the chart can say about each of a legend's names. }
    function LegendSources(const AEntries: TTyLegendEntryArray):
      TTyLegendSourceArray;
    { Specs, entries and selection. Runs in Rebuild. }
    procedure SolveLegendData;
    { What the selection MEANS: the series a legend has switched off stop
      being counted, and the pie slices it has switched off leave the
      store. Runs in Rebuild, immediately after SolveLegendData. }
    procedure ApplyLegendFilter;
    { True when ANY legend has switched this name off. }
    function LegendHides(const AName: string): Boolean;
    { The predicate FilterSelf calls, against FFilterStore. A method
      pointer cannot carry an argument, so the store it is filtering rides
      on the field -- which is why the field exists and why it is cleared
      the moment the call returns. }
    function KeepSlice(ARawIndex: Integer): Boolean;
    { Every legend, measured and placed. Runs in Relayout. }
    procedure SolveLegends(const AMeasurer: ITyTextMeasurer; APPI: Integer);
    function LegendFont: TTyLegendFont;
    function LegendInk: TTyLegendInk;
    { The legend's elements, into the chart's own paint list. }
    function BuildLegends(APPI: Integer; AList: TTyPaintList): Integer;
    procedure PaintDynamic(APainter: TTyPainter; const ARect: TRect;
      APPI: Integer; const AMeasurer: ITyTextMeasurer);
    { Whether the dynamic layer would draw anything. False skips a whole
      painter -- a BGRA bitmap the size of the control, filled, blitted and
      freed -- which is most of a frame when there is nothing moving. }
    function HasDynamicContent: Boolean;
    procedure DropStatic;
  protected
    function GetStyleTypeKey: string; override;
    procedure Resize; override;
    { Protected and non-virtual, exactly as every other control in the library:
      a headless test renders through it onto an offscreen bitmap, and it
      bypasses the on-screen paint path entirely. }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { The layered path: the static cache blitted, then the dynamic layer over
      it. Separate from RenderTo because RenderTo is what an export and a
      headless test want -- everything, unconditionally, onto the canvas they
      named. This one is what a WINDOW wants, and works in client space:
      TTyPaintCache.Blit draws at the canvas origin. }
    procedure RenderCached(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate; override;
    { REPAINT WITHOUT REBUILDING. Invalidate means "the model may have moved":
      it rebuilds, re-measures and re-renders the static layer, because a theme
      change arrives as a bare Invalidate and there is no StyleChanged hook to
      tell the two apart. This one means "the same model, one frame on" -- the
      static layer is kept and only the dynamic layer is redrawn.

      An animation tick calls this. Calling Invalidate instead would rebuild the
      stores and re-measure every label sixty times a second, which is the
      difference between a frame costing a blit and a frame costing 51 ms. }
    procedure InvalidateFrame;
    { Everything the option said that could not be honoured -- a misspelled axis
      type, a series naming an axis that does not exist. A chart that silently
      drops what it cannot draw is a chart that lies, so these are readable
      rather than logged and forgotten. }
    function DiagnosticCount: Integer;
    function Diagnostic(AIndex: Integer): string;
    { Draw the chart to a PNG at its current size.

      A chart is a thing people put in reports, so exporting one is an ordinary
      feature rather than test scaffolding -- and it renders through the same
      RenderTo the screen uses, so what is saved is what was shown. Deliberately
      NOT a form-image grab: capturing a windowed control that way returns black
      on some widgetsets, which this library has already been caught by. }
    procedure SaveToPng(const AFileName: string);
    { For a test or a designer to look inside. nil until the first build. }
    property Build: TTyChartBuild read FBuild;
  published
    { THE API. Relaxed JSON: unquoted keys, single quotes, trailing commas and
      comments all parse, because that is what an ECharts config in the wild
      looks like.

      A REJECTED OPTION LEAVES NO CHART. The earlier rule kept the last one
      that parsed, reasoning that a half-typed config in a design-time editor
      must not blank the chart -- but the editor that got built is a modal
      dialog writing back on OK, and the Object Inspector commits once too, so
      half-typed text never arrives here. What that rule left instead was a
      control that lies: the property says A, the picture shows B, and nothing
      on screen says why. OptionError carries the reason. }
    property Option: string read GetOptionText write SetOptionText;
    { Empty when the last option parsed. }
    property OptionError: string read GetErrorText;
    property Align;
    property Anchors;
    property BorderSpacing;
    property Color;
    property Font;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ShowHint;
    property TabOrder;
    { NOT a tab stop today, and the declaration has to say so or a .lfm cannot
      stream the choice: the streamer omits a value that equals the declared
      default, so a mismatched pair silently loses whatever the host wrote.
      A chart with no keyboard behaviour that took focus on click would pull it
      off whatever the user was editing and then do nothing with it. Being
      WINDOWED is what makes focus possible later; it is not a reason to take it
      now. When dataZoom, brush or a keyboard tooltip land, this flips to True
      and the class moves to the focusable table -- which the tables in
      test.focus.tabstop.pas will force somebody to decide rather than drift. }
    property TabStop default False;
    property Visible;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;
  end;

implementation

uses tyControls.Controller;

{ ==================== construction ==================== }

constructor TTyAdvanceChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOption := TTyChartOption.Create;
  FIndex := TTyAxisSeriesIndex.Create;
  FDirty := True;
  Width := 320;
  Height := 200;
  TabStop := False;   { see the published declaration }
end;

destructor TTyAdvanceChart.Destroy;
begin
  { Order is a contract, not a habit: a store BORROWS its category list from an
    axis the build owns, so every store goes first. }
  DropBuild;
  FreeAndNil(FIndex);
  FreeAndNil(FOption);
  { The static layer owns a TBitmap. TTyPaintCache.Drop only marks it stale --
    it keeps the surface deliberately, for reuse -- so dropping is not freeing. }
  FreeAndNil(FStatic);
  inherited Destroy;
end;

procedure TTyAdvanceChart.FreeStores;
var i: Integer;
begin
  for i := 0 to High(FStores) do
    FStores[i].Free;
  FStores := nil;
  FBarCols := nil;
  FStacks := nil;
end;

procedure TTyAdvanceChart.DropBuild;
begin
  FreeStores;
  FBindings := nil;
  if FIndex <> nil then FIndex.Clear;
  FreeAndNil(FBuild);
end;

{ ==================== the option ==================== }

{ WHAT WAS WRITTEN, not what parsed. The PROPERTY has to read back what the
  host set, or a half-typed option in the Object Inspector reverts on every
  keystroke that does not yet parse, and a .lfm cannot round-trip work in
  progress.

  The TREE is emptied when the text does not parse -- there is no last-good-one
  kept, deliberately: a control whose property says A while the picture shows B
  has no way to tell anyone which is which. OptionError says what went wrong. }
function TTyAdvanceChart.GetOptionText: string;
begin
  Result := FOptionText;
end;

procedure TTyAdvanceChart.SetOptionText(const AValue: string);
begin
  if FOptionText = AValue then Exit;
  FOptionText := AValue;
  FOption.SetOptionText(AValue);
  FDirty := True;
  Invalidate;
end;

function TTyAdvanceChart.GetErrorText: string;
begin
  Result := FOption.Error.Message;
end;

function TTyAdvanceChart.DiagnosticCount: Integer;
begin
  if FBuild = nil then Exit(0);
  Result := FBuild.DiagnosticCount;
end;

function TTyAdvanceChart.Diagnostic(AIndex: Integer): string;
begin
  if FBuild = nil then Exit('');
  Result := FBuild.Diagnostic(AIndex);
end;

{ ==================== style ==================== }

function TTyAdvanceChart.GetStyleTypeKey: string;
begin
  { Its own key, never borrowed. A control that answers another control's key
    can never be reached by a theme that wants to restyle only this one. }
  Result := 'TyAdvChart';
end;

procedure TTyAdvanceChart.Invalidate;
begin
  { A theme change arrives as a plain Invalidate broadcast and nothing else --
    the controller says so in as many words, and there is no StyleChanged hook
    to override. So every invalidate is treated as a relayout: the axis extents
    would not move, but the label FONT may have, and the plot rect is measured
    from the labels. Cheaper to redo than to be wrong about, and a chart is not
    invalidated on mouse movement. }
  FDirty := True;
  { AND THE STATIC LAYER GOES. It holds a picture drawn in the theme's font at
    the theme's colours; the whole reason this method treats every invalidate
    as a relayout is that a theme change arrives as a bare Invalidate, and a
    kept cache would blit the old theme over the new one. }
  DropStatic;
  inherited Invalidate;
end;

procedure TTyAdvanceChart.InvalidateFrame;
begin
  { The static layer is KEPT -- see the declaration. This is the repaint an
    animation tick asks for: same model, same layout, same axes, one frame on. }
  inherited Invalidate;
end;

procedure TTyAdvanceChart.Resize;
begin
  inherited Resize;
  FDirty := True;
end;

{ ==================== the pipeline ==================== }

procedure TTyAdvanceChart.Rebuild;
var
  i, k, ds, cur: Integer;
  dims: TTySeriesDimArray;
  st: TTyDataStore;
  coord: TTyCoordDimArray;
  cursors: TTyEncodeCursorArray;
  enc: TTySeriesEncode;
begin
  DropBuild;
  FBuild := TyBuildGrids(FOption, FLastRect);
  FBindings := TyBindSeries(FOption, FBuild);
  SetLength(FStores, Length(FBindings));
  SetLength(FSources, Length(FBindings));
  SetLength(FSeriesDataset, Length(FBindings));
  SetLength(FEncodes, Length(FBindings));
  cursors := nil;
  for i := 0 to High(FBindings) do
  begin
    st := TTyDataStore.Create;
    FStores[i] := st;
    { WHICH TABLE, IF ANY. A series with its own `data` reads that and nothing
      else -- the table is there for the series that did not bring any. }
    FSeriesDataset[i] := TySeriesDatasetIndex(FOption, FBindings[i].SeriesIndex);
    if FSeriesDataset[i] >= 0 then
    begin
      FSources[i] := TySourceOf(FOption, FSeriesDataset[i],
        FBindings[i].SeriesIndex);
      if not FSources[i].Valid then FSeriesDataset[i] := -1;
    end;
    if not FBindings[i].HasAxes then
    begin
      { A PIE HAS DATA TOO, and until now it did not get any: the columns
        below are the coordinate systems dimensions, and a series without
        a coordinate system has none, so the store stayed empty and the
        `data` array was never read. One float column, named the way
        ECharts names the dimension, and TyFillSeriesStore does the rest --
        it already unwraps `{ value, name }`, records the name and collects
        the per-item overrides. }
      if FBindings[i].SeriesType = TyPieSeriesTypeName then
      begin
        st.AddDimension(TyPieValueDim, ddtFloat);
        SetLength(dims, 1);
        dims[0].Name := TyPieValueDim;
        dims[0].Kind := ddtFloat;
        dims[0].Axis := nil;
        ds := FSeriesDataset[i];
        if ds >= 0 then
        begin
          { A PIE NAMES ITS DATA RATHER THAN PLOTTING IT, so its default
            encode is the other one: a NAME dimension and a VALUE dimension,
            guessed from the table rather than counted off it. }
          SetLength(coord, 1);
          coord[0].Name := TyPieValueDim;
          coord[0].Ordinal := False;
          enc := TyEncodeOf(FOption, FBindings[i].SeriesIndex,
            FSources[i], coord);
          if not enc.Given then
            enc := TyDefaultEncodeNameBased(FSources[i],
              FSources[i].DimCount);
          FEncodes[i] := enc;
          TyFillStoreFromSource(FSources[i], enc, dims, st);
        end
        else
          TyFillSeriesStore(FOption, i, dims, st);
      end;
      Continue;
    end;
    dims := TySeriesCartesianDims(FBindings[i].Cart, 0);
    for k := 0 to High(dims) do
    begin
      st.AddDimension(dims[k].Name, dims[k].Kind);
      { The axis owns the category list and every series on it borrows the SAME
        one -- that sharing is what makes two series agree about which name
        ordinal 0 is. }
      if dims[k].Axis <> nil then st.UseOrdinalMeta(k, dims[k].Axis.Categories);
    end;
    ds := FSeriesDataset[i];
    if ds < 0 then
    begin
      TyFillSeriesStore(FOption, i, dims, st);
      Continue;
    end;
    { THE COORDINATES, AS THE ENCODE RULES SEE THEM: a name and whether the
      axis under it is a category one. The second is what chooses between the
      two ways of handing a table out, and it is not the same question as
      which axis is horizontal. }
    SetLength(coord, Length(dims));
    for k := 0 to High(dims) do
    begin
      coord[k].Name := dims[k].Name;
      coord[k].Ordinal := dims[k].Kind = ddtOrdinal;
    end;
    enc := TyEncodeOf(FOption, FBindings[i].SeriesIndex, FSources[i], coord);
    { THE CURSOR IS SHARED AND IT ADVANCES, which is why this has to happen
      inside the one loop that walks the series in order. Three bars on one
      table take columns 1, 2 and 3 because the second and third ask the same
      counter the first one moved. A series that brought its own encode --
      even a partial one -- does not ask, and so does not move it. }
    if not enc.Given then
    begin
      { THE INDEX FIRST, THEN THE SUBSCRIPT. `cursors[F(cursors)]` where F may
        SetLength is the repository's own recorded footgun: FPC takes the
        array's address before it evaluates the index, so a reallocation
        inside F leaves the write going to freed memory. }
      cur := TyEncodeCursorFor(cursors, ds, FSources[i].LayoutBy);
      enc := TyDefaultEncodeAxis(cursors[cur], coord);
    end;
    FEncodes[i] := enc;
    TyFillStoreFromSource(FSources[i], enc, dims, st);
    Continue;
  end;
  { AFTER THE STORES AND BEFORE EVERYTHING THAT COUNTS. A pie legend names
    DATA ITEMS, so the names have to be in the store before the legend can
    list them; and the filter the legend implies has to be in place before
    the index, the stacks and the extents, or a switched-off series would go
    on widening the axis it is not drawn on.

    This is upstream's order too, by its priorities: legendFilter is
    SERIES_FILTER (800), the stack pass is 900 and the axis statistics are
    920, with a comment at echarts.ts:163-165 saying the statistics must come
    after the filter for exactly this reason. Nothing here measures text, so
    none of it has to wait for Relayout. }
  SolveLegendData;
  ApplyLegendFilter;
  { AFTER the filter but over EVERY series slot, hidden ones included --
    see SolveSeriesColors. The two are not in tension: the filter decides
    what is drawn, the palette decides what colour each series IS, and the
    second must not depend on the first or a legend click would repaint
    the whole chart. }
  SolveSeriesColors;
  TyIndexSeries(FBindings, FIndex);
  { BEFORE THE EXTENTS, and that order is the whole point: a stacked chart
    whose axis was sized from the raw values draws off the top of its plot. }
  FStacks := TySolveStacks(FOption, FBindings, FStores);
  TyApplyAxisExtents(FOption, FBuild, FBindings, FStores, FStacks, FIndex);
end;

procedure TTyAdvanceChart.Relayout(APainter: TTyPainter; const ARect: TTyRectF;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  txt: TTyAxisTextStyle;
  labelS: TTyStyleSet;
begin
  FLastRect := ARect;
  Rebuild;
  { The layout pass measures the labels the PAINT pass will draw, so it has to
    be handed the same font and the same gaps. Resolving them here rather than
    inside the builder keeps that unit free of the controller, which is the
    whole reason the measurer is injected too. }
  labelS := ActiveController.Model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  txt := Default(TTyAxisTextStyle);
  txt.FontName := labelS.FontName;
  txt.FontSizeLogical := ResolveFontSize(labelS);
  txt.FontWeight := labelS.FontWeight;
  txt.LabelMarginLogical := ActiveController.Metric(TyAdvChartLabelMarginVar,
    TyAdvChartLabelMargin);
  txt.TickLengthLogical := ActiveController.Metric(TyAdvChartTickLenVar,
    TyAdvChartTickLen);
  txt.NameGapLogical := ActiveController.Metric(TyAdvChartNameGapVar,
    TyAdvChartNameGap);
  { Measuring goes through the painter behind an interface rather than being
    called directly, so the layout layer stays free of the painter and a test
    can hand it a deterministic measurer instead of this machine's fonts. }
  TyLayoutGrids(FBuild, FOption, AMeasurer, APPI, txt);
  { AFTER phase C, for the reason on FBarCols. }
  FBarCols := TySolveBarLayout(FOption, FBuild, FBindings, FStores, FIndex);
  SolvePies;
  SolveTitles(AMeasurer, APPI);
  SolveLegends(AMeasurer, APPI);
  FDirty := False;
end;

{ ==================== paint ==================== }

procedure TTyAdvanceChart.PaintAxis(APainter: TTyPainter; AAxis: TTyAxis;
  const APlot: TTyRectF; APPI: Integer; AGrid: TTyGridBuild;
  const AMeasurer: ITyTextMeasurer);
var
  model: TTyStyleModel;
  lineS, tickStyle, labelS, splitS: TTyStyleSet;
  minorTickS, minorSplitS, nameS: TTyStyleSet;
  ticks: TTyDoubleArray;
  i: Integer;
  tickLen, minorLen, at, along, x1, y1, x2, y2: Double;
  nameOff, nx, ny, nameAngle: Double;
  maxW, batched: Integer;
  horiz: Boolean;
  txt: string;
  lblH, lblW, step: Integer;
  scaleTicks: TTyScaleTickArray;
  spec: PTyAxisLayoutSpec;
  places: TTyAxisLabelPlacementArray;
  furn: TTyAxisFurniture;
  areaS: TTyStyleSet;
  bandLo, bandHi: Double;

  { THE BOX IS THE TRANSLATION. The layout layer says "this point, with the
    text hanging off it this way"; the painter aligns text INSIDE a rectangle.
    Building a box that is exactly the text's size around the anchor makes the
    two agree, and makes the alignment argument irrelevant.

    Mapping anchors to LCL alignments instead was the first attempt and it was
    wrong in a way worth remembering: a right-anchored label kept the old
    symmetric box, so right-justifying inside it put the text's right edge a
    whole width PAST the anchor -- straight through the tick marks. }
  { The same two anchors DrawTextRotated wants, which takes the point and the
    alignments rather than a rectangle. }
  function AnchorAlign(AH2: TTyTextAnchorH): TAlignment;
  begin
    case AH2 of
      tahLeft: Result := taLeftJustify;
      tahRight: Result := taRightJustify;
    else Result := taCenter;
    end;
  end;

  function AnchorLayout(AV: TTyTextAnchorV): TTextLayout;
  begin
    case AV of
      tavTop: Result := tlTop;
      tavBottom: Result := tlBottom;
    else Result := tlCenter;
    end;
  end;

  function AnchorBox(AX, AY: Double; AW, AH: Integer;
    AH2: TTyTextAnchorH; AV: TTyTextAnchorV): TRect;
  begin
    case AH2 of
      tahLeft: begin Result.Left := Round(AX); Result.Right := Round(AX) + AW; end;
      tahRight: begin Result.Left := Round(AX) - AW; Result.Right := Round(AX); end;
    else
      begin
        Result.Left := Round(AX - AW / 2);
        Result.Right := Result.Left + AW;
      end;
    end;
    case AV of
      tavTop: begin Result.Top := Round(AY); Result.Bottom := Round(AY) + AH; end;
      tavBottom: begin Result.Top := Round(AY) - AH; Result.Bottom := Round(AY); end;
    else
      begin
        Result.Top := Round(AY - AH / 2);
        Result.Bottom := Result.Top + AH;
      end;
    end;
  end;

  { The width the theme asked for, LOGICAL -- StrokePath scales it itself.

    An undeclared width falls back to one logical pixel rather than to zero: a
    theme that names a colour and no width means "draw it", not "draw nothing",
    and StrokePath treats a width of zero as "no border". }
  function LineWidth(const AStyle: TTyStyleSet): Double;
  begin
    if tpBorderWidth in AStyle.Present then
      Result := AStyle.BorderWidth
    else
      Result := 1;
    if Result < 0.05 then Result := 0.05;
  end;

  { THE LAYOUT'S OWN MEASURER, not the painter's TextSize. They are two
    different rasterisers -- Measure.pas' header says they disagree by about a
    pixel and that a size floor feeding a clip must take the LARGER, which is
    what the layout does -- so measuring here with the other one made the
    reserved gutter and the drawn box two different numbers. It is also the one
    path that misses the painter's measurement memo. }
  procedure TextSizeOf(const AText: string; const AStyle: TTyStyleSet;
    out AW, AH: Integer);
  var w, h: Double;
  begin
    if AMeasurer = nil then
    begin
      AW := APainter.MeasureText(AText, AStyle.FontName,
        ResolveFontSize(AStyle), AStyle.FontWeight).cx;
      AH := APainter.MeasureText('Wg', AStyle.FontName,
        ResolveFontSize(AStyle), AStyle.FontWeight).cy;
      Exit;
    end;
    AMeasurer.MeasureLine(AText, AStyle.FontName, ResolveFontSize(AStyle),
                          AStyle.FontWeight, w, h);
    AW := Round(w);
    AH := Round(h);
  end;

  { ONE SUBPATH PER LINE, ONE STROKE PER STYLE.

    Every line an axis draws shares a style with its neighbours by
    construction, and a path can hold as many subpaths as it likes -- each
    MoveTo starts a new one -- so a whole set of split lines is one BeginPath, N
    MoveTo/LineTo pairs and one StrokePath. Stroking them one at a time is what
    made a 600-point frame cost 110 ms when the same frame without axes costs
    13: the bill was never pixels, it was the per-call setup, and quartering the
    area did not quarter the time. ECharts survives 100k elements on the same
    trick (canPathBatch: consecutive same-style elements accumulate into one
    beginPath and one fill/stroke).

    SNAPPED as it is added. A stroke whose outer edge falls between two pixel
    rows lights both at half alpha, which is what makes a 1 px grid read grey
    and soft next to the crisp control chrome around it.

    TWO UNITS, DELIBERATELY. The snap works in DEVICE px -- the pixel grid the
    ink lands on is the device one, so snapping a logical coordinate would mean
    nothing -- while StrokePath wants the LOGICAL width and scales it itself.
    Handing the scaled width to both is a double scale that 96 DPI hides
    completely, which is how the first version of this passed. }
  procedure BatchLine(AX1, AY1, AX2, AY2: Double; AWidthLogical: Double);
  begin
    TySubPixelLine(AX1, AY1, AX2, AY2, APainter.ScaleF(AWidthLogical));
    APainter.MoveTo(AX1, AY1);
    APainter.LineTo(AX2, AY2);
    Inc(batched);
  end;

  { Stroke what BatchLine collected, if anything. The count guards a stroke of
    an empty path, which a fully thinned-away set of minor ticks produces. }
  procedure StrokeBatch(const AStyle: TTyStyleSet);
  begin
    if batched > 0 then
      APainter.StrokePath(AStyle.BorderColor, LineWidth(AStyle));
    batched := 0;
  end;

begin
  if AAxis = nil then Exit;
  { `show: false` means "do not draw me". The axis still exists and its series
    still map to pixels; only the domain, ticks, labels and split lines go. }
  if not AAxis.Visible then Exit;
  model := ActiveController.Model;
  { A foreign typeKey is resolved by asking the model directly -- there is no
    per-part helper in this library and inventing one here would be a second
    idiom for the same thing. }
  lineS := model.ResolveStyle('TyAdvChartAxisLine', '', []);
  minorTickS := model.ResolveStyle('TyAdvChartMinorTick', '', []);
  minorSplitS := model.ResolveStyle('TyAdvChartMinorSplitLine', '', []);
  tickStyle := model.ResolveStyle('TyAdvChartAxisTick', '', []);
  labelS := model.ResolveStyle('TyAdvChartAxisLabel', '', []);
  splitS := model.ResolveStyle('TyAdvChartSplitLine', '', []);
  areaS := model.ResolveStyle('TyAdvChartSplitArea', '', []);

  horiz := AAxis.Horizontal;
  { The axis sits on the edge of the plot its side names. }
  if horiz then at := APlot.Bottom else at := APlot.Left;
  if AAxis.Side = asTop then at := APlot.Top;
  if AAxis.Side = asRight then at := APlot.Right;


  { THE THINNING STEP, READ FROM THE LAYOUT. It used to be computed halfway
    down this procedure, after the split lines had already been drawn -- so the
    ticks thinned with the labels and the lines behind them did not, which is an
    axis wearing a grid and a set of numbers that disagree about how many
    divisions it has.

    And it used to be computed AT ALL here: TyAxisLabelStep measures every
    label, so a frame spent ten thousand measurements at 5,000 categories to
    choose the twenty it would draw. Phase C already measured them to shrink the
    plot rect; it records what it decided and this reads it. }
  spec := nil;
  if AGrid <> nil then spec := AGrid.SpecFor(AAxis);
  { WHAT THIS AXIS ACTUALLY DRAWS. Resolved once by the builder, from the
    option AND from upstream's per-type defaults -- which is where most of
    the answers come from: on a chart with no axis option written at all, the
    category axis draws its domain line and nothing else, and the value axis
    draws its split lines and nothing else. }
  furn := Default(TTyAxisFurniture);
  furn.ShowLine := True;
  furn.ShowTicks := True;
  furn.ShowLabels := True;
  if AGrid <> nil then furn := AGrid.FurnitureFor(AAxis);

  { THE TICK'S LENGTH, and it has to be asked AFTER the two lines above. It
    used to be asked first -- reading `spec` and `furn` before either was
    resolved, so an authored `axisTick.length` and `axisTick.inside` were both
    decided by whatever was on the stack. The layout half was right and the
    paint half was reading uninitialised memory, which is a difference no
    assertion about the plot rectangle could ever see. }
  { THE SPEC'S LENGTH, not the theme metric over again: FillSpec has already
    laid the option over the theme, and the layout reserved the gutter from
    exactly that number. Asking the theme a second time here is how the
    reserved band and the drawn mark come to disagree. }
  tickLen := APainter.ScaleF(ActiveController.Metric(TyAdvChartTickLenVar,
    TyAdvChartTickLen));
  if spec <> nil then tickLen := APainter.ScaleF(spec^.TickLengthLogical);
  minorLen := APainter.ScaleF(ActiveController.Metric(TyAdvChartMinorTickLenVar,
    TyAdvChartMinorTickLen));
  if not IsNan(furn.MinorTickLengthLogical) then
    minorLen := APainter.ScaleF(furn.MinorTickLengthLogical);
  { INSIDE TURNS THEM ROUND -- BOTH OF THEM. A negative length points the mark
    into the plot, which is the whole of what the option does, and the layout
    has already stopped reserving room outside for it. There is no
    `minorTick.inside`: upstream flips one tickDirection and every mark on the
    axis follows it, so majors pointing in with minors still pointing out is
    not a state upstream can reach. }
  if furn.TickInside then
  begin
    tickLen := -tickLen;
    minorLen := -minorLen;
  end;
  step := 1;
  if (spec <> nil) and (spec^.LabelStep > 0) then step := spec^.LabelStep;
  batched := 0;

  { Split lines first, so the domain and the ticks sit on top of them.

    TickCoords' default, NOT AAlignWithLabel: a split line divides the bands, it
    does not point at a label. On a banded category axis the two differ by half
    a band, which is exactly the width the whole parameter exists to express. }
  { MINOR FIRST, so a major line drawn at the same place wins. The two theme
    keys have been in light.tycss since item 18 with nothing that could ever be
    drawn with them: every generator wrote Level 0. }
  { MINORS ONLY WHILE THE MAJORS ARE ALL THERE. A minor tick subdivides the
    interval between two majors, so once the majors are being hidden the
    subdivisions of an interval nobody can see are noise -- and they are the
    densest thing on the axis, which makes them the worst noise to keep. }
  { SPLIT AREAS FIRST, because everything else is drawn ON them. Alternating
    bands between consecutive divisions -- so N divisions give N-1 bands, and
    the ones the theme paints are every other one. The key has been in
    light.tycss since item 18 with nothing that could draw with it.

    THE BANDS RUN BETWEEN THE SPLIT LINES, which on a banded category axis
    means between the band EDGES: one shaded band per category, which is what
    makes the alternating stripe line up with the bars rather than straddle
    them. }
  if furn.ShowSplitArea and (tpBackground in areaS.Present) then
  begin
    ticks := AAxis.TickCoords;
    for i := 0 to High(ticks) - 1 do
    begin
      if i mod 2 <> 0 then Continue;
      bandLo := ticks[i];
      bandHi := ticks[i + 1];
      if horiz then
        APainter.FillBackground(
          Rect(Round(bandLo), Round(APlot.Top),
               Round(bandHi), Round(APlot.Bottom)), areaS.Background, 0)
      else
        APainter.FillBackground(
          Rect(Round(APlot.Left), Round(bandLo),
               Round(APlot.Right), Round(bandHi)), areaS.Background, 0);
    end;
  end;

  if furn.ShowMinorSplitLine
    and (tpBorderColor in minorSplitS.Present) and (step = 1) then
  begin
    scaleTicks := AAxis.Scale.GetTicks;
    APainter.BeginPath;
    for i := 0 to High(scaleTicks) do
    begin
      if scaleTicks[i].Level = 0 then Continue;
      along := AAxis.DataToCoord(scaleTicks[i].Value);
      if horiz then
        BatchLine(along, APlot.Top, along, APlot.Bottom, LineWidth(minorSplitS))
      else
        BatchLine(APlot.Left, along, APlot.Right, along, LineWidth(minorSplitS));
    end;
    StrokeBatch(minorSplitS);
  end;

  if furn.ShowSplitLine and (tpBorderColor in splitS.Present) then
  begin
    ticks := AAxis.TickCoords;
    APainter.BeginPath;
    for i := 0 to High(ticks) do
    begin
      { THINNED WITH THE LABELS, on the same step the ticks use. }
      if (step > 1) and (i mod step <> 0) then Continue;
      { THE TWO ON THE ENDS ARE SEPARATELY DENIABLE. A grid line on the axis'
        own extreme sits exactly on the plot's edge, doubling whatever border
        is already there, and these are the keys that turn it off. }
      if (i = 0) and (not furn.ShowMinLine) then Continue;
      if (i = High(ticks)) and (not furn.ShowMaxLine) then Continue;
      along := ticks[i];
      if horiz then
        BatchLine(along, APlot.Top, along, APlot.Bottom, LineWidth(splitS))
      else
        BatchLine(APlot.Left, along, APlot.Right, along, LineWidth(splitS));
    end;
    StrokeBatch(splitS);
  end;

  { The domain line. Present, not colour: an undeclared colour resolves to
    alpha zero, so testing the colour would draw an invisible line and call it
    drawn. }
  if furn.ShowLine and (tpBorderColor in lineS.Present) then
  begin
    APainter.BeginPath;
    if horiz then
      BatchLine(APlot.Left, at, APlot.Right, at, LineWidth(lineS))
    else
      BatchLine(at, APlot.Top, at, APlot.Bottom, LineWidth(lineS));
    StrokeBatch(lineS);
  end;

  { ALIGNED WITH THE LABELS OR WITH THE BAND EDGES. On a banded category axis
    the two are half a band apart, and which one a tick means is exactly what
    the option exists to say -- the split lines above keep the edges either
    way, because a divider that pointed at a label would not divide anything. }
  ticks := AAxis.TickCoords(furn.AlignWithLabel);
  { THE MARKS THIN WITH THE LABELS. Drawing every tick under a thinned set of
    labels reads as an axis that lost its labels rather than one that spaced
    them out, and computing the step by a second route is how the two drift --
    which is why `step` is worked out once, above, and the split lines use the
    same one. }
  if furn.ShowTicks and (tpBorderColor in tickStyle.Present) then
  begin
    APainter.BeginPath;
    for i := 0 to High(ticks) do
    begin
      if (step > 1) and (i mod step <> 0) then Continue;
      along := ticks[i];
      if horiz then
      begin
        x1 := along; x2 := along;
        y1 := at;
        if AAxis.Side = asTop then y2 := at - tickLen else y2 := at + tickLen;
      end
      else
      begin
        y1 := along; y2 := along;
        x1 := at;
        if AAxis.Side = asRight then x2 := at + tickLen else x2 := at - tickLen;
      end;
      BatchLine(x1, y1, x2, y2, LineWidth(tickStyle));
    end;
    StrokeBatch(tickStyle);
  end;

  { Minor MARKS. The difference in LENGTH is what says which is which when both
    are the same colour family -- and how much shorter is the theme's call, not
    a fraction hardcoded here. --advchart-minor-tick-length, its constant and
    its default have all been in place since item 18 with nothing reading them,
    so a skin that set it changed nothing. }
  if furn.ShowMinorTick and (tpBorderColor in minorTickS.Present)
    and (step = 1) then
  begin
    scaleTicks := AAxis.Scale.GetTicks;
    APainter.BeginPath;
    for i := 0 to High(scaleTicks) do
    begin
      if scaleTicks[i].Level = 0 then Continue;
      along := AAxis.DataToCoord(scaleTicks[i].Value);
      if horiz then
      begin
        x1 := along; x2 := along;
        y1 := at;
        if AAxis.Side = asTop then y2 := at - minorLen
        else y2 := at + minorLen;
      end
      else
      begin
        y1 := along; y2 := along;
        x1 := at;
        if AAxis.Side = asRight then x2 := at + minorLen
        else x2 := at - minorLen;
      end;
      BatchLine(x1, y1, x2, y2, LineWidth(minorTickS));
    end;
    StrokeBatch(minorTickS);
  end;

  { THE AXIS NAME. Builder solves the grid with obcAll, so TyAxisThickness has
    been charging every named axis' side for NameGap plus the name's turned
    extent since item 12 -- and nothing ever drew into it. Setting xAxis.name
    shrank the plot by the width of a string that was not there.

    Placed by asking TyAxisThickness twice: once counting the name and once not.
    The difference IS the band reserved for it, so the name lands in the space
    the layout set aside rather than at an offset reassembled here out of the
    same parts -- which is the mistake this file warns about two hundred lines
    up, about computing a step by a second route.

    Centred in that band with taCenter/tlCenter, which also makes the placement
    independent of the rotation: a quarter turn about a centred anchor moves
    nothing. }
  nameS := model.ResolveStyle('TyAdvChartAxisName', '', []);
  if (AAxis.Name <> '') and (spec <> nil) and (AMeasurer <> nil)
    and (tpTextColor in nameS.Present) then
  begin
    nameOff := (TyAxisThickness(spec^, AMeasurer, APPI, obcAxisLabel)
              + TyAxisThickness(spec^, AMeasurer, APPI, obcAll)) / 2;
    if horiz then
    begin
      nx := (APlot.Left + APlot.Right) / 2;
      if AAxis.Side = asTop then ny := at - nameOff else ny := at + nameOff;
      nameAngle := 0;
    end
    else
    begin
      ny := (APlot.Top + APlot.Bottom) / 2;
      if AAxis.Side = asRight then nx := at + nameOff else nx := at - nameOff;
      { A quarter turn so it reads up the side -- and the same quarter turn
        TyAxisThickness applied when it charged the name's HEIGHT against this
        axis' width rather than its length. }
      nameAngle := Pi / 2;
    end;
    APainter.DrawTextRotated(AAxis.Name, nameS.FontName,
      ResolveFontSize(nameS), nameS.FontWeight, nameS.TextColor,
      nx, ny, nameAngle, taCenter, tlCenter);
  end;

  if not (tpTextColor in labelS.Present) then Exit;

  { PHASE 3 PLACES THEM. It was written with item 12 and never called, so every
    label was drawn at a position worked out here and none was ever thinned --
    a crowded axis simply overlapped. The placement carries the anchor too, so
    layout and paint cannot disagree about where a label went. }
  if (spec <> nil) and (Length(spec^.Placements) > 0) then
  begin
    places := spec^.Placements;
    for i := 0 to High(places) do
    begin
      if not places[i].Shown then Continue;
      if places[i].Text = '' then Continue;
      TextSizeOf(places[i].Text, labelS, lblW, lblH);
      { BOUNDED BY axisLabel.width WHEN TRUNCATING, and only then: with no
        bound the box is exactly the text's size, so the ellipsis fitter has
        nothing to bite on and `overflow` would silently do nothing.

        The other two modes need no bound here. `break` arrives already broken
        -- the builder wrapped it, so the box is the wrapped block's size and
        the multi-line flag lays it out -- and `none` is the old behaviour. }
      if (spec^.LabelOverflow = loTruncate)
        and (spec^.LabelWidthLogical > 0) then
      begin
        maxW := Round(APainter.ScaleF(spec^.LabelWidthLogical));
        if maxW < lblW then lblW := maxW;
      end;
      { TURNED, WHEN THE AUTHOR ASKED FOR IT. The layout has measured the
        turned extent since item 12 and nothing ever drew the turn, so an
        `axisLabel: { rotate: 45 }` bought a deeper gutter and put flat text in
        it. Counter-clockwise positive on both sides -- upstream's and the
        painter's -- so the angle passes straight through.

        DrawTextRotated takes the anchor as a POINT plus the alignments that
        say where in the text box it sits, which is what the placement already
        carries; AnchorBox exists only because the flat path needs a rect. }
      if spec^.RotationRad <> 0 then
      begin
        APainter.DrawTextRotated(places[i].Text, labelS.FontName,
          ResolveFontSize(labelS), labelS.FontWeight, labelS.TextColor,
          places[i].X, places[i].Y, spec^.RotationRad,
          AnchorAlign(places[i].AnchorH), AnchorLayout(places[i].AnchorV));
        Continue;
      end;
      APainter.DrawText(
        AnchorBox(places[i].X, places[i].Y, lblW, lblH,
                  places[i].AnchorH, places[i].AnchorV),
        places[i].Text, labelS.FontName, ResolveFontSize(labelS),
        labelS.FontWeight, labelS.TextColor, taCenter, tlCenter,
        { ELLIPSIS AND MULTI-LINE, both of which the painter has always had and
          this never asked for: a label was drawn as one clipped line whatever
          it contained, so a wrapped one lost every row after the first. }
        spec^.LabelOverflow = loTruncate, 0, False,
        Pos(#10, places[i].Text) > 0);
    end;
    Exit;
  end;

  { A CATEGORY axis labels its categories; a VALUE axis labels its tick values.
    Handling only the first leaves a value axis with ticks and no numbers -- and
    a pixel count cannot see that, because the ticks and grid lines are hundreds
    of pixels on their own. It took a render on a real machine to notice. }
  TextSizeOf('Wg', labelS, lblW, lblH);
  scaleTicks := AAxis.Scale.GetTicks;
  for i := 0 to High(scaleTicks) do
  begin
    if AAxis.Scale is TTyOrdinalScale then
      txt := TTyOrdinalScale(AAxis.Scale).GetLabel(scaleTicks[i].Value)
    else
      txt := TyChartNumToStr(scaleTicks[i].Value);
    if txt = '' then Continue;
    along := AAxis.DataToCoord(scaleTicks[i].Value);
    TextSizeOf(txt, labelS, lblW, lblH);
    { A label belongs to its band, so it is CENTRED on the band's anchor while
      the tick above sits on the band's edge. Those are different places by
      design and the gap between them is what boundaryGap means. }
    if horiz then
      APainter.DrawText(
        Rect(Round(along - lblW), Round(at + tickLen + 2),
             Round(along + lblW), Round(at + tickLen + 2 + lblH)),
        txt, labelS.FontName, ResolveFontSize(labelS), labelS.FontWeight,
        labelS.TextColor, taCenter, tlTop, False)
    else
      APainter.DrawText(
        Rect(Round(at - tickLen - 2 - lblW), Round(along - lblH / 2),
             Round(at - tickLen - 2), Round(along + lblH / 2)),
        txt, labelS.FontName, ResolveFontSize(labelS), labelS.FontWeight,
        labelS.TextColor, taRightJustify, tlCenter, False);
  end;
end;

procedure TTyAdvanceChart.RenderTo(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
var
  P: TTyPainter;
  R: TRect;
  boxStyle: TTyStyleSet;
  plotF: TTyRectF;
  g, a: Integer;
  gb: TTyGridBuild;
  measurer: ITyTextMeasurer;
begin
  { ONE measurer, held in an interface variable, for the whole render.

    Not `TTyPainterTextMeasurer.Create(APPI)` at each call site: the parameter
    is declared `const ITyTextMeasurer`, and a const interface parameter does
    not get the reference-counting temporary -- so an object passed straight in
    stays at a refcount of zero and is never freed. Two axes times two calls
    times every repaint is a leak the heap test found within thirty renders.

    Holding it here also means the layout pass and the paint pass measure with
    the same instance, which is what they are supposed to agree about. }
  measurer := TTyPainterTextMeasurer.Create(APPI);
  P := TTyPainter.Create;
  try
    { LOCAL space. EndPaint blits at ARect's origin, so everything below is
      measured from zero. }
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    PaintStatic(P, R, APPI, measurer);
    PaintDynamic(P, R, APPI, measurer);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyAdvanceChart.PaintStatic(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  boxStyle: TTyStyleSet;
  plotF: TTyRectF;
  g, a: Integer;
  gb: TTyGridBuild;
begin
  { Resolved at REST on purpose. The plot rect is measured from the label
    font, and a geometry that read the focused style would move the whole
    chart the moment it took focus. }
  boxStyle := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
    [tysNormal]);
  { Mandatory first draw, and it does more than a fill: parent backdrop,
    opacity, shadow, background, border, and the corner gaps a windowed
    control cannot get from a shadow it is not allowed to cast. }
  DrawFrame(APainter, ARect, boxStyle);

  plotF := TyRectF(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  if FDirty or (plotF.Right <> FLastRect.Right)
    or (plotF.Bottom <> FLastRect.Bottom) then
    Relayout(APainter, plotF, APPI, AMeasurer);

  if FBuild <> nil then
    for g := 0 to FBuild.GridCount - 1 do
    begin
      gb := FBuild.Grid(g);
      for a := 0 to gb.XAxisCount - 1 do
        PaintAxis(APainter, gb.XAxis(a), gb.PlotRect, APPI, gb, AMeasurer);
      for a := 0 to gb.YAxisCount - 1 do
        PaintAxis(APainter, gb.YAxis(a), gb.PlotRect, APPI, gb, AMeasurer);
    end;

  { AFTER THE AXES, so a bar sits on the grid rather than under it. Within the
    series, the paint list decides the order. }
  PaintSeries(APainter, AMeasurer, APPI);
  { AND THE TITLE LAST. It floats over the container rather than reserving
    room, so anything it overlaps it is meant to overlap. }
  PaintTitles(APainter);
end;

function TTyAdvanceChart.StackFor(ASlot: Integer): TTySeriesStack;
begin
  if (ASlot >= 0) and (ASlot <= High(FStacks)) then
    Result := FStacks[ASlot]
  else
  begin
    Result := Default(TTySeriesStack);
    Result.ResultCol := -1;
    Result.OverCol := -1;
  end;
end;

function TTyAdvanceChart.LabelStepFor(AAxis: TTyAxis): Integer;
var
  g: Integer;
  spec: PTyAxisLayoutSpec;
begin
  Result := 1;
  if (AAxis = nil) or (FBuild = nil) then Exit;
  for g := 0 to FBuild.GridCount - 1 do
  begin
    spec := FBuild.Grid(g).SpecFor(AAxis);
    if spec <> nil then
    begin
      if spec^.LabelStep > 1 then Result := spec^.LabelStep;
      Exit;
    end;
  end;
end;

function TTyAdvanceChart.SymbolFor(ASlot: Integer): TTySymbolSpec;
var
  d: TJSONData;
  node: TJSONObject;
begin
  Result := TySymbolDefault('');
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  Result := TySymbolDefault(FBindings[ASlot].SeriesType);
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  Result := TySymbolSpecOf(node, Result);
end;

procedure TTyAdvanceChart.SolveSeriesColors;

  { An unnamed series is NOT nameless as far as the palette is concerned.
    Upstream builds `series` + NUL + index precisely so two unnamed series
    cannot collide in the memo, and its comment says so. Leaving it empty
    would give every unnamed series the first colour. }
  function NameFor(ASlot: Integer): string;
  begin
    Result := SeriesNameOf(ASlot);
    if Result = '' then Result := TyChartSeriesDefaultName(ASlot);
  end;

var
  i, n: Integer;
  declared: Boolean;
  cur, own: TTyPaletteCursor;
  ownPal: TTyChartColorArray;
  node: TJSONObject;
  d: TJSONData;
  st: string;
  style: TTyOptStyle;
  key, other: TTyOptColor;
  hasAuto: Boolean;
  c: TTyChartColor;
begin
  FSeriesColors := nil;
  FSeriesColorKnown := nil;
  FSeriesPalette := nil;
  FSeriesPaletteKnown := nil;
  if FOption = nil then Exit;
  n := FOption.ComponentCount('series');
  SetLength(FSeriesColors, n);
  SetLength(FSeriesColorKnown, n);
  SetLength(FSeriesPalette, n);
  SetLength(FSeriesPaletteKnown, n);
  cur := TyPaletteStart(TyChartPaletteOf(FOption, -1, declared));

  { DECLARATION ORDER, AND EVERY SLOT. A series the legend switched off still
    takes its colour, and so does one whose type has no renderer -- that is the
    entire mechanism by which colours stay put across a legend click. Skipping
    the hidden ones would re-shuffle every colour after them. }
  for i := 0 to n - 1 do
  begin
    d := FOption.ComponentAt('series', i);
    node := nil;
    if (d <> nil) and (d.JSONType = jtObject) then node := TJSONObject(d);
    st := '';
    if node <> nil then
    begin
      d := node.Find('type');
      if (d <> nil) and (d.JSONType = jtString) then st := d.AsString;
    end;

    { WHICH KEY SUPPRESSES THE PALETTE depends on what the series draws with.
      Nearly everything fills, so it is `itemStyle.color`; a boxplot draws with
      its stroke, so it is `itemStyle.borderColor`; `lines` and `parallel` read
      a different block entirely. A line is NOT one of the exceptions -- writing
      `lineStyle.color` on a line does not stop it taking a palette slot. }
    style := TyReadOptStyle(node, TyStyleAccessPath(st));
    if TyStyleDrawsWithStroke(st) and (TyStyleAccessPath(st) = 'itemStyle') then
    begin
      key := style.BorderColor;
      other := style.Color;
    end
    else
    begin
      key := style.Color;
      other := style.BorderColor;
    end;
    { `auto` ON EITHER HALF OF THE PAIR sends this series to the palette,
      even when the other half names a colour -- upstream tests `fill` AND
      `stroke` for the word and consults the palette if either carries it.
      So `{ color: '#fff', borderColor: 'auto' }` is a white bar with a
      border in the palette colour, and it costs a slot. }
    hasAuto := key.IsAuto or other.IsAuto;

    if key.Written and not hasAuto then
    begin
      { AN AUTHORED COLOUR CONSUMES NO SLOT, and upstream says why in a comment:
        an author who paints one series transparent, or as a backdrop, did not
        mean to shift every other series' colour. `series: [{}, {color}, {}]` is
        palette[0], the authored one, palette[1]. }
      if not key.IsNone then
      begin
        FSeriesColors[i] := key.Color;
        FSeriesColorKnown[i] := True;
      end;
      Continue;
    end;

    { A SERIES WITH ITS OWN `color` ARRAY runs its own cursor over it from
      nought, and never touches the chart-wide one. }
    ownPal := TyChartPaletteOf(FOption, i, declared);
    if Length(ownPal) > 0 then
    begin
      own := TyPaletteStart(ownPal);
      if TyPaletteTake(own, NameFor(i), c) then
      begin
        FSeriesPalette[i] := c;
        FSeriesPaletteKnown[i] := True;
        if (not key.Written) or key.IsAuto then
        begin
          FSeriesColors[i] := c;
          FSeriesColorKnown[i] := True;
        end
        else if not key.IsNone then
        begin
          FSeriesColors[i] := key.Color;
          FSeriesColorKnown[i] := True;
        end;
      end;
      Continue;
    end;

    { `auto` takes a slot as surely as writing nothing does -- it means `the
      palette colour`, so it has to have one. }
    if TyPaletteTake(cur, NameFor(i), c) then
    begin
      FSeriesPalette[i] := c;
      FSeriesPaletteKnown[i] := True;
      { THE PICK IS NOT ALWAYS THE FILL. It becomes the fill only when the
        fill was left unwritten, or was written as `auto`; a series that
        named its fill and asked for `auto` somewhere else keeps the name
        it gave. }
      if (not key.Written) or key.IsAuto then
      begin
        FSeriesColors[i] := c;
        FSeriesColorKnown[i] := True;
      end
      else if not key.IsNone then
      begin
        FSeriesColors[i] := key.Color;
        FSeriesColorKnown[i] := True;
      end;
    end;
  end;
end;

procedure TTyAdvanceChart.ApplyOptStyle(var AVisual: TTySeriesVisual;
  ASlot: Integer);
var
  node: TJSONObject;
  d: TJSONData;
  st: string;
  item, line: TTyOptStyle;
begin
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASlot);
  if (d = nil) or (d.JSONType <> jtObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('type');
  st := '';
  if (d <> nil) and (d.JSONType = jtString) then st := d.AsString;

  { THE FILL IS ALREADY DECIDED. SolveSeriesColors read the same key to
    settle whether this series took a palette slot, and SeriesColor handed
    the answer over -- reading it a second time here would be a second
    place that has to agree about `auto`. }
  item := TyReadOptStyle(node, 'itemStyle');
  line := TyReadOptStyle(node, 'lineStyle');

  { `itemStyle.borderColor` / `borderWidth`. `auto` on a border means the
    palette colour, the same as it does on a fill. }
  if item.BorderColor.Written and not item.BorderColor.IsNone then
  begin
    if item.BorderColor.IsAuto then
      AVisual.Stroke := TTyChartColor(SeriesPaletteColor(ASlot))
    else
      AVisual.Stroke := item.BorderColor.Color;
  end;
  if not IsNan(item.BorderWidthLogical) then
    AVisual.StrokeWidthLogical := item.BorderWidthLogical;
  if not IsNan(item.Opacity) then
    AVisual.Alpha := Min(Double(1), Max(Double(0), item.Opacity));

  { A LINE READS ITS OWN BLOCK FOR THE PEN, and only for the pen. Its
    palette colour came from `itemStyle` -- that is the trap in this whole
    row -- and that colour still goes to its symbols and its area; the
    authored `lineStyle.color` wins the polyline's pixels and nothing else. }
  if (st = 'line') or TyStyleDrawsWithStroke(st) then
  begin
    if line.Color.Written and not line.Color.IsNone then
    begin
      if line.Color.IsAuto then
        AVisual.Stroke := TTyChartColor(SeriesPaletteColor(ASlot))
      else
        AVisual.Stroke := line.Color.Color;
    end;
    if not IsNan(line.BorderWidthLogical) then
      AVisual.StrokeWidthLogical := line.BorderWidthLogical;
    if not IsNan(line.Opacity) then
      AVisual.Alpha := Min(Double(1), Max(Double(0), line.Opacity));
  end;
end;

function TTyAdvanceChart.ThemeRampColor(ASlot: Integer): TTyColor;
var
  st: TTyStyleSet;
begin
  { NINE SLOTS, CYCLED -- nine because upstream's own default palette is nine
    colours and the CYCLE LENGTH is observable: it decides which series comes
    round to share a colour with the first. Derived from --accent rather than
    written out, which is what makes a re-skinned chart come out in the skin's
    own colours; slot 1 IS the accent, so a single-series chart is drawn in
    the theme's own colour. }
  st := ActiveController.Model.ResolveStyle(
    'TyAdvChartSeries' + IntToStr((Abs(ASlot) mod 9) + 1), '', []);
  if tpBackground in st.Present then
    Exit(st.Background.Color);
  { The nine keys are in the BASE layer, so a theme cannot remove them -- it
    can only restyle them, and a skin that defines none of them inherits all
    nine. Reaching here means something is wrong with the theme rather than
    with the option, so the answer is the control's own foreground: visible
    against its own surface by construction, which is the one thing a fallback
    colour has to be. }
  st := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
    [tysNormal]);
  Result := st.TextColor;
end;

function TTyAdvanceChart.SeriesPaletteColor(ASeriesIndex: Integer): TTyColor;
begin
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSeriesPaletteKnown))
    and FSeriesPaletteKnown[ASeriesIndex] then
    Exit(TTyColor(FSeriesPalette[ASeriesIndex]));
  Result := ThemeRampColor(ASeriesIndex);
end;

function TTyAdvanceChart.SeriesColor(ASeriesIndex: Integer): TTyColor;
begin
  { THE AUTHOR'S PALETTE FIRST. `color: [...]` or an authored
    `itemStyle.color` is the author speaking about their own chart, and a
    skin has no business overruling it. }
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FSeriesColorKnown))
    and FSeriesColorKnown[ASeriesIndex] then
    Exit(TTyColor(FSeriesColors[ASeriesIndex]));

  Result := ThemeRampColor(ASeriesIndex);
end;

function TTyAdvanceChart.TitleFont(const AKey: string): TTyTitleFont;
var st: TTyStyleSet;
begin
  st := ActiveController.Model.ResolveStyle(AKey, '', []);
  Result.Name := st.FontName;
  Result.SizeLogical := ResolveFontSize(st);
  Result.Weight := st.FontWeight;
end;

procedure TTyAdvanceChart.SolveTitles(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i, n: Integer;
begin
  n := TyTitleCount(FOption);
  SetLength(FTitles, n);
  SetLength(FTitleSpecs, n);
  for i := 0 to n - 1 do
  begin
    FTitleSpecs[i] := TyTitleSpecOf(FOption, i);
    FTitles[i] := TyLayoutTitle(FTitleSpecs[i], FLastRect, AMeasurer,
      TitleFont('TyAdvChartTitle'), TitleFont('TyAdvChartSubtitle'), APPI);
  end;
end;

procedure TTyAdvanceChart.SolvePies;
var
  i, dim: Integer;
begin
  SetLength(FPies, Length(FBindings));
  SetLength(FPieSpecs, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    FPies[i] := Default(TTyPieLayout);
    FPieSpecs[i] := TyPieSpecDefault;
    if i > High(FStores) then Break;
    if not FBindings[i].Resolved then Continue;
    if FBindings[i].SeriesType <> TyPieSeriesTypeName then Continue;
    FPieSpecs[i] := TyPieSpecOf(FOption, FBindings[i].SeriesIndex);
    dim := FStores[i].DimIndexOf(TyPieValueDim);
    { FLastRect, not a grid: a pie is laid out against the CONTROL, and its
      own left/top/right/bottom shrink that. Handing it a grid rect would
      centre it on the plot instead of on the chart, which is not where
      ECharts puts it. }
    FPies[i] := TyPieLayoutOf(FPieSpecs[i], FLastRect, FStores[i], dim);
  end;
end;

function TTyAdvanceChart.PieVisual(ASlot: Integer): TTyPieVisual;
var
  k, n, raw, rawN: Integer;
  ov: TTyDataValue;
  c: TTyChartColor;
  pal: TTyChartColorArray;
  perRaw: TTyChartColorArray;
  cur: TTyPaletteCursor;
  declared: Boolean;
  nm: string;
begin
  Result := TyPieVisual(0);
  { colorBy:''data''. Each SECTOR takes the next slot of the same nine-colour
    ramp a bar series cycles across series -- which is what makes a pie read
    at all, and what makes it re-skin with the accent like everything else.

    A SLICE THAT NAMED ITS OWN COLOUR KEEPS IT. `data: [{ value: 5,
    itemStyle: { color: ''#c23531'' } }]` is the commonest thing anybody
    writes on a pie, and it beats the ramp -- the same rule a bar follows,
    reached through the same parked override. }
  { ONE COLOUR PER RAW ROW, TAKEN IN RAW ORDER, before a single sector is
    looked at. A slice that was filtered out -- a negative value, a legend
    click -- still consumes its slot, which is the only way the surviving
    slices keep the colours they had. Upstream iterates its raw data here for
    the same reason and says so in a comment.

    Keyed on the slice's NAME, so two pies over the same categories agree
    about which category is which colour -- and so a repeated name inside one
    pie shares a colour rather than taking a second slot. }
  pal := TyChartPaletteOf(FOption, ASlot, declared);
  if Length(pal) = 0 then pal := TyChartPaletteOf(FOption, -1, declared);
  cur := TyPaletteStart(pal);
  rawN := 0;
  if (ASlot <= High(FStores)) and (FStores[ASlot] <> nil) then
    rawN := FStores[ASlot].RawCount;
  SetLength(perRaw, rawN);
  for k := 0 to rawN - 1 do
  begin
    perRaw[k] := TTyChartColor(ThemeRampColor(k));
    if Length(pal) = 0 then Continue;
    nm := FStores[ASlot].GetNameByRaw(k);
    if nm = '' then nm := IntToStr(k);
    if TyPaletteTake(cur, nm, c) then perRaw[k] := c;
  end;

  n := Length(FPies[ASlot].Sectors);
  if n < 1 then n := 1;
  SetLength(Result.Fills, n);
  for k := 0 to n - 1 do
  begin
    { KEYED ON THE RAW ROW, NOT THE SECTOR. The two are the same number only
      while nothing has been dropped -- and something already is: a negative
      value is filtered out before the layout runs, and now a legend can
      filter more. Key the ramp on the sector's position and every surviving
      slice changes colour the moment a neighbour leaves, which is the one
      failure of this commit a reader would notice immediately.

      Upstream says the same thing in a comment written for the same reason:
      `Iterate on data before filtered. To make sure color from palette can
      be consistent when toggling legend.` (visual/style.ts:207-208). }
    if k <= High(FPies[ASlot].Sectors) then
    begin
      raw := FPies[ASlot].Sectors[k].RawIndex;
      if (raw >= 0) and (raw <= High(perRaw)) then
        Result.Fills[k] := perRaw[raw]
      else
        Result.Fills[k] := TTyChartColor(ThemeRampColor(raw));
      if (ASlot <= High(FStores)) and (FStores[ASlot] <> nil)
        and FStores[ASlot].HasOverrideByRaw(raw,
              TyOverrideKey('itemStyle.color')) then
      begin
        ov := FStores[ASlot].GetOverrideByRaw(raw,
                TyOverrideKey('itemStyle.color'));
        if (ov.Kind = dvkText) and TyTryParseChartColor(ov.Text, c) then
          Result.Fills[k] := c;
      end;
    end
    else
      Result.Fills[k] := TTyChartColor(ThemeRampColor(k));
  end;
  { The empty ring has its own token rather than borrowing the split area''s:
    they are faint for different reasons and a theme has to be able to move
    one without the other. }
  Result.EmptyFill := TTyChartColor(
    ActiveController.Model.ResolveStyle('TyAdvChartEmptyCircle', '',
      []).Background.Color);
end;

procedure TTyAdvanceChart.PaintTitles(APainter: TTyPainter);
var
  i: Integer;
  st, subSt: TTyStyleSet;
  lay: TTyTitleLayout;

  { The box DrawText wants, hung off an anchor with the title's alignment.
    The same job AnchorBox does for an axis label; kept local because the two
    take their alignment from different enums and one shared helper would take
    an argument nobody could read at the call site. }
  function Hang(AX, AY, AW, AH: Double; AAlign: TTyTitleAlign;
    AVAlign: TTyTitleVAlign): TRect;
  begin
    case AAlign of
      ttaCentre: Result.Left := Round(AX - AW / 2);
      ttaRight: Result.Left := Round(AX - AW);
    else
      Result.Left := Round(AX);
    end;
    Result.Right := Result.Left + Round(AW);
    case AVAlign of
      ttvMiddle: Result.Top := Round(AY - AH / 2);
      ttvBottom: Result.Top := Round(AY - AH);
    else
      Result.Top := Round(AY);
    end;
    Result.Bottom := Result.Top + Round(AH);
  end;

  function LclAlign(AAlign: TTyTitleAlign): TAlignment;
  begin
    case AAlign of
      ttaCentre: Result := taCenter;
      ttaRight: Result := taRightJustify;
    else
      Result := taLeftJustify;
    end;
  end;

begin
  if Length(FTitles) = 0 then Exit;
  st := ActiveController.Model.ResolveStyle('TyAdvChartTitle', '', []);
  subSt := ActiveController.Model.ResolveStyle('TyAdvChartSubtitle', '',
    []);
  for i := 0 to High(FTitles) do
  begin
    lay := FTitles[i];
    if not lay.Valid then Continue;
    { The frame first, and only when the option asked for one: ECharts gives
      the title a transparent background by default, and painting the surface
      colour instead would put a visible plate behind every title on an image
      theme. }
    if FTitleSpecs[i].HasBackground then
      APainter.FillBackground(
        Rect(Round(lay.Frame.Left), Round(lay.Frame.Top),
             Round(lay.Frame.Right), Round(lay.Frame.Bottom)),
        st.Background, Round(FTitleSpecs[i].BorderRadii[0]));
    if FTitleSpecs[i].Text <> '' then
      APainter.DrawText(
        Hang(lay.TextX, lay.TextY, lay.TextW, lay.TextH, lay.Align, lay.VAlign),
        FTitleSpecs[i].Text, st.FontName, ResolveFontSize(st), st.FontWeight,
        st.TextColor, LclAlign(lay.Align), tlTop, False, 0, False,
        Pos(#10, FTitleSpecs[i].Text) > 0);
    if lay.HasSub then
      APainter.DrawText(
        Hang(lay.SubX, lay.SubY, lay.SubW, lay.SubH, lay.Align, lay.VAlign),
        FTitleSpecs[i].Subtext, subSt.FontName, ResolveFontSize(subSt),
        subSt.FontWeight, subSt.TextColor, LclAlign(lay.Align), tlTop, False,
        0, False, Pos(#10, FTitleSpecs[i].Subtext) > 0);
  end;
end;


function TTyAdvanceChart.SeriesNameOf(ASlot: Integer): string;
var
  d: TJSONData;
  node: TJSONObject;
  i, ds: Integer;
begin
  Result := '';
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', ASlot);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('name');
  if (d <> nil) and (d.JSONType = jtString) then Exit(d.AsString);

  { A SERIES READING A TABLE NAMES ITSELF AFTER THE COLUMN IT TOOK. That is
    how three bars on one dataset end up called 2015, 2016 and 2017 in a
    legend nobody wrote entries for -- and without it those three legends
    have nothing to list. The column is the one the encode put the series'
    own name on, which the default encode sets to whichever column is not
    the shared category. }
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].SeriesIndex <> ASlot then Continue;
    if i > High(FEncodes) then Exit;
    ds := -1;
    if i <= High(FSeriesDataset) then ds := FSeriesDataset[i];
    if (ds < 0) or (i > High(FSources)) then Exit;
    if FEncodes[i].SeriesName < 0 then Exit;
    Exit(TySourceDimName(FSources[i], FEncodes[i].SeriesName));
  end;
end;

{ ==================== legend ==================== }

{ TWO LISTS, and they are deliberately different.

  POTENTIAL is what a legend with no `data` of its own falls back to: a pie
  contributes its SLICE names and everything else contributes its own, and an
  unnamed series contributes NOTHING -- upstream gives it a private dummy name
  that no legend entry can be written to match, so the effect is the same and
  an empty string is the honest way to say it here.

  AVAILABLE is what a name is allowed to match. Every name the chart can
  produce is in it, and an entry that is NOT in it reads as switched off
  however `legend.selected` is written -- which is what greys out a
  `legend.data` entry naming a series nobody declared. }
procedure TTyAdvanceChart.LegendNames(out APotential, AAvailable: TTyLegendNames);
var
  i, k, np, na: Integer;
  nm: string;

  procedure PushP(const AName: string);
  begin
    if AName = '' then Exit;
    if np >= Length(APotential) then SetLength(APotential, np * 2 + 8);
    APotential[np] := AName;
    Inc(np);
  end;

  procedure PushA(const AName: string);
  begin
    if AName = '' then Exit;
    if na >= Length(AAvailable) then SetLength(AAvailable, na * 2 + 8);
    AAvailable[na] := AName;
    Inc(na);
  end;

begin
  APotential := nil;
  AAvailable := nil;
  np := 0;
  na := 0;
  for i := 0 to High(FBindings) do
  begin
    if (FBindings[i].SeriesType = TyPieSeriesTypeName)
      and (i <= High(FStores)) and (FStores[i] <> nil) then
    begin
      { ITS SLICE NAMES ARE WHAT THE LEGEND OFFERS, but its own name is still
        AVAILABLE -- upstream pushes every raw series' name into that list
        unconditionally, before it ever looks at a provider. The difference
        shows when an author writes the pie's own name into `legend.data`:
        with the name available the entry is live, and without it the entry
        would grey out for a reason that has nothing to do with the option. }
      PushA(SeriesNameOf(FBindings[i].SeriesIndex));
      for k := 0 to FStores[i].Count - 1 do
      begin
        nm := FStores[i].GetName(k);
        PushP(nm);
        PushA(nm);
      end;
      Continue;
    end;
    nm := SeriesNameOf(FBindings[i].SeriesIndex);
    PushP(nm);
    PushA(nm);
  end;
  SetLength(APotential, np);
  SetLength(AAvailable, na);
end;

function TTyAdvanceChart.SeriesSymbolWord(ASlot: Integer): string;
var
  d: TJSONData;
  node: TJSONObject;
begin
  Result := '';
  if (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if (d = nil) or not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  d := node.Find('symbol');
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

function TTyAdvanceChart.LegendSources(const AEntries: TTyLegendEntryArray):
  TTyLegendSourceArray;
var
  i, j, k: Integer;
  found: Boolean;
begin
  SetLength(Result, Length(AEntries));
  for i := 0 to High(AEntries) do
  begin
    Result[i] := Default(TTyLegendSource);
    if AEntries[i].Newline then Continue;
    found := False;
    { A SERIES NAME WINS OVER A SLICE NAME, because upstream asks
      getSeriesByName first and only falls to the per-datum providers when
      nothing answered. }
    for j := 0 to High(FBindings) do
    begin
      if FBindings[j].SeriesType = TyPieSeriesTypeName then Continue;
      if SeriesNameOf(FBindings[j].SeriesIndex) <> AEntries[i].Name then
        Continue;
      Result[i].Found := True;
      Result[i].SeriesType := FBindings[j].SeriesType;
      Result[i].Colour := TTyChartColor(SeriesColor(FBindings[j].SeriesIndex));
      Result[i].DefaultIcon := TyLegendDefaultIcon(FBindings[j].SeriesType,
        SeriesSymbolWord(j));
      Result[i].OwnIcon := TyLegendDrawsOwnIcon(FBindings[j].SeriesType);
      Result[i].LineColour := Result[i].Colour;
      { THE SAME 2 THE LINE ITSELF FALLS BACK TO in BuildLine, which is also
        what `lineStyle.width: 'auto'` resolves to upstream. When series line
        widths become an option the two will read it from one place; until
        then they agree by saying the same thing. }
      if Result[i].OwnIcon then
        Result[i].LineWidthLogical := 2;
      found := True;
      Break;
    end;
    if found then Continue;
    for j := 0 to High(FBindings) do
    begin
      if FBindings[j].SeriesType <> TyPieSeriesTypeName then Continue;
      if (j > High(FStores)) or (FStores[j] = nil) then Continue;
      { THE RAW ROWS, NOT THE VIEW. This runs in Relayout, which is to say
        AFTER the filter has already taken the switched-off slices out of
        the store -- and those are exactly the slices whose legend items we
        are here to describe. Walking the view would find every item except
        the ones that were switched off.

        AN EQUIVALENT MUTANT LIVES HERE and is recorded rather than chased:
        walking the view instead draws the same picture TODAY, because the
        only items it would fail to find are the switched-off ones, and a
        switched-off item takes the inactive ink and the roundRect floor --
        neither of which comes from here. It stops being equivalent the
        moment a greyed item keeps anything of its own, and being wrong for
        an invisible reason is still being wrong.

        colorBy: 'data' -- a slice's colour is the same eight-slot ramp,
        keyed on the same RAW row PieVisual keys on, so the swatch and the
        wedge cannot disagree. }
      for k := 0 to FStores[j].RawCount - 1 do
        if FStores[j].GetNameByRaw(k) = AEntries[i].Name then
        begin
          Result[i].Found := True;
          Result[i].SeriesType := TyPieSeriesTypeName;
          Result[i].Colour := TTyChartColor(SeriesColor(k));
          Result[i].LineColour := Result[i].Colour;
          found := True;
          Break;
        end;
      if found then Break;
    end;
  end;
end;

procedure TTyAdvanceChart.SolveLegendData;
var
  i, n: Integer;
  potential, available: TTyLegendNames;
begin
  n := TyLegendCount(FOption);
  SetLength(FLegendSpecs, n);
  SetLength(FLegendEntries, n);
  SetLength(FLegendFlags, n);
  SetLength(FLegends, n);
  if n = 0 then Exit;
  LegendNames(potential, available);
  for i := 0 to n - 1 do
  begin
    FLegendSpecs[i] := TyLegendSpecOf(FOption, i);
    FLegendEntries[i] := TyLegendEntries(FOption, i, potential);
    FLegendFlags[i] := TyLegendSelected(FOption, i, FLegendEntries[i],
      available, FLegendSpecs[i].SelectedMode);
    FLegends[i] := Default(TTyLegendLayout);
  end;
end;

{ A name is switched off when ANY legend says so -- legendFilter.ts:36-41.
  Nothing is switched off when there is no legend at all, which is why a
  chart without one is untouched by any of this. }
function TTyAdvanceChart.LegendHides(const AName: string): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to High(FLegendSpecs) do
    if TyLegendHides(FLegendEntries[i], FLegendFlags[i], AName) then
      Exit(True);
end;

function TTyAdvanceChart.KeepSlice(ARawIndex: Integer): Boolean;
begin
  Result := True;
  if FFilterStore = nil then Exit;
  Result := not LegendHides(FFilterStore.GetNameByRaw(ARawIndex));
end;

procedure TTyAdvanceChart.ApplyLegendFilter;
var
  i, k: Integer;
  st: TTyDataStore;
  any: Boolean;
begin
  if Length(FLegendSpecs) = 0 then Exit;
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].SeriesType <> TyPieSeriesTypeName then
    begin
      FBindings[i].Hidden :=
        LegendHides(SeriesNameOf(FBindings[i].SeriesIndex));
      Continue;
    end;
    { A PIE IS FILTERED ONE ROW AT A TIME, because its legend names slices
      rather than series -- upstream's processor/dataFilter against this
      port's own TTyDataStore.FilterSelf, which is the same mechanism and
      has been sitting here unused since the store was written.

      It COMPOSES with the negative-value filter the pie layout applies
      later, and in upstream's order: the legend's filter is registered
      first and negativeDataFilter second (chart/pie/install.ts:35-37). }
    if (i > High(FStores)) or (FStores[i] = nil) then Continue;
    st := FStores[i];
    { ASKED BEFORE IT IS DONE, so a pie nobody switched anything off on
      keeps an UNFILTERED store -- which is not only cheaper but visible:
      a filtered store takes the slow path through its index vector in
      every extent and every read. }
    any := False;
    for k := 0 to st.RawCount - 1 do
      if LegendHides(st.GetNameByRaw(k)) then
      begin
        any := True;
        Break;
      end;
    if not any then Continue;
    FFilterStore := st;
    try
      st.FilterSelf(@KeepSlice);
    finally
      FFilterStore := nil;
    end;
  end;
end;

function TTyAdvanceChart.LegendFont: TTyLegendFont;
var st: TTyStyleSet;
begin
  st := ActiveController.Model.ResolveStyle('TyAdvChartLegend', '', []);
  Result.Name := st.FontName;
  Result.SizeLogical := ResolveFontSize(st);
  Result.Weight := st.FontWeight;
end;

function TTyAdvanceChart.LegendInk: TTyLegendInk;
var model: TTyStyleModel;
begin
  model := ActiveController.Model;
  Result.Text := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegend', '', []).TextColor);
  Result.Inactive := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendInactive', '', []).TextColor);
  Result.Border := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendBorder', '', []).BorderColor);
  Result.Background := TTyChartColor(
    model.ResolveStyle('TyAdvChartLegendBackground', '', []).Background.Color);
  { The hole in a ring is the chart's own ground, the same substitution the
    mark builders make for a datum's `empty` marker. }
  Result.EmptyFill := TTyChartColor(
    model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]).Background.Color);
end;

procedure TTyAdvanceChart.SolveLegends(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  i: Integer;
  fnt: TTyLegendFont;
begin
  if Length(FLegendSpecs) = 0 then Exit;
  fnt := LegendFont;
  for i := 0 to High(FLegendSpecs) do
    FLegends[i] := TyLayoutLegend(FLegendSpecs[i], FLegendEntries[i],
      FLegendFlags[i], LegendSources(FLegendEntries[i]), FLastRect,
      AMeasurer, fnt, APPI);
end;

function TTyAdvanceChart.BuildLegends(APPI: Integer;
  AList: TTyPaintList): Integer;
var
  i: Integer;
  ink: TTyLegendInk;
  fnt: TTyLegendFont;
begin
  Result := 0;
  if Length(FLegends) = 0 then Exit;
  ink := LegendInk;
  fnt := LegendFont;
  for i := 0 to High(FLegends) do
    Inc(Result, TyBuildLegendMarks(FLegendSpecs[i], FLegends[i], ink, fnt,
      APPI, AList));
end;

function TTyAdvanceChart.LabelSpecFor(ASlot: Integer): TTyLabelSpec;
var
  base: TTyLabelSpec;
  outS, lightS, midS, darkS: TTyStyleSet;
begin
  base := TyLabelSpecNone;
  outS := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  lightS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight',
    '', []);
  midS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []);
  darkS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '',
    []);
  base.FontName := outS.FontName;
  base.FontSizeLogical := ResolveFontSize(outS);
  base.FontWeight := outS.FontWeight;
  base.OutsideColour := TTyChartColor(outS.TextColor);
  base.InsideColour[0] := TTyChartColor(lightS.TextColor);
  base.InsideColour[1] := TTyChartColor(midS.TextColor);
  base.InsideColour[2] := TTyChartColor(darkS.TextColor);
  if ASlot > High(FBindings) then Exit(base);
  Result := TyLabelSpecOf(FOption, FBindings[ASlot].SeriesIndex, base);
end;

function TTyAdvanceChart.PieLabelInk: TTyPieLabelInk;
var
  outS, lightS, midS, darkS: TTyStyleSet;
begin
  outS := ActiveController.Model.ResolveStyle('TyAdvChartLabel', '', []);
  lightS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnLight',
    '', []);
  midS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnMid', '', []);
  darkS := ActiveController.Model.ResolveStyle('TyAdvChartLabelOnDark', '',
    []);
  Result.FontName := outS.FontName;
  Result.FontSizeLogical := ResolveFontSize(outS);
  Result.FontWeight := outS.FontWeight;
  Result.InsideColour[0] := TTyChartColor(lightS.TextColor);
  Result.InsideColour[1] := TTyChartColor(midS.TextColor);
  Result.InsideColour[2] := TTyChartColor(darkS.TextColor);
  Result.OutsideColour := TTyChartColor(outS.TextColor);
  { labelLine.lineStyle.width, PieSeries.ts:299 -- one logical pixel. }
  Result.LineWidthLogical := 1;
end;

procedure TTyAdvanceChart.PaintSeries(APainter: TTyPainter;
  const AMeasurer: ITyTextMeasurer; APPI: Integer);
var
  list: TTyPaintList;
  i, drawn: Integer;
  v: TTySeriesVisual;
  pv: TTyPieVisual;
  specs: TTyLabelSpecArray;
begin
  if Length(FBindings) = 0 then Exit;
  { ONE LIST FOR EVERY SERIES, not one per series: the ordering rule is (Z, Z2,
    insertion) ACROSS the chart, and a list per series would order each one
    against itself and leave the between-series order to the loop. }
  list := TTyPaintList.Create;
  try
    drawn := 0;
    for i := 0 to High(FBindings) do
    begin
      if i > High(FStores) then Break;
      { SWITCHED OFF, so nothing of it is drawn -- not its marks, not its
        labels (the expansion below only sees what reached the list), and
        not its wedges. The pie branch is inside this guard for the sake of
        the one case that can reach it: a `legend.data` entry naming the pie
        series itself. }
      if FBindings[i].Hidden then Continue;
      { A pie is not on a coordinate system, so it takes the other pass. It
        goes into the SAME list: the ordering rule is chart-wide, and a pie
        beside a bar has to sort against it like anything else. }
      if FBindings[i].SeriesType = TyPieSeriesTypeName then
      begin
        if i <= High(FPies) then
        begin
          pv := PieVisual(i);
          Inc(drawn, TyBuildPieMarks(FBindings[i], FPies[i], FPieSpecs[i],
            pv, list));
          { ITS OWN PASS, not TyExpandLabels. A pie label is placed from the
            slice's ANGLES and the series radius, none of which survive into
            the sector's bounding box -- the box of a wedge is the whole
            outer disc, so a label placed from it would sit at the disc's
            centre for every slice. }
          Inc(drawn, TyBuildPieLabels(FBindings[i], FPies[i],
            TyPieLabelSpecOf(FOption, FBindings[i].SeriesIndex,
              TyPieLabelSpecDefault),
            PieLabelInk, pv.Fills, FStores[i], AMeasurer, APPI, list));
        end;
        Continue;
      end;
      v := TySeriesVisual(TTyChartColor(SeriesColor(FBindings[i].SeriesIndex)));
      ApplyOptStyle(v, FBindings[i].SeriesIndex);
      if i <= High(FBarCols) then v.Bar := FBarCols[i];
      v.Line := TyLineSpecOf(FOption, FBindings[i].SeriesIndex);
      { The thinning the AXIS settled on. When markers would crowd, upstream
        falls back to the category axis' own label interval -- which the layout
        pass already computed, so it is fetched rather than re-derived. }
      v.Line.LabelStep := LabelStepFor(FBindings[i].BaseAxis);
      v.Symbol := SymbolFor(i);
      { An `empty` symbol is filled with the chart's own surface, so it reads as
        a hole rather than as a white dot on a dark skin. Upstream fills it from
        a token too, so parity and this library's own rule agree. }
      v.EmptyFill := TTyChartColor(
        ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
          [tysNormal]).Background.Color);

      { showBackground's strip. Its own key rather than the split area's: the
        two are faint for different reasons and a theme has to be able to move
        one without the other. }
      v.BackgroundFill := TTyChartColor(
        ActiveController.Model.ResolveStyle('TyAdvChartBarBackground', '',
          []).Background.Color);
      { NO Z2 HERE. It was set to i, and a mutant that set it to 0 survived
        every test -- because the paint list's documented tiebreaker is the
        INSERTION INDEX, and these are inserted in series order already. Two
        ways of saying the same thing, one of them inert. When series z and
        zlevel arrive they will set Z, and Z2 will have something to do. }
      v.Label_ := LabelSpecFor(i);
      { `{c}` and the default text read the VALUE column -- whichever axis is
        not the base one. A label that read x on a bar chart would show the
        category ordinal, which is a number and looks like an answer. }
      v.LabelValueDim := -1;
      if (FBindings[i].ValueAxis <> nil) and (FStores[i] <> nil) then
        v.LabelValueDim := FStores[i].DimIndexOf(FBindings[i].ValueAxis.Dim);
      v.SeriesName := SeriesNameOf(FBindings[i].SeriesIndex);
      if Length(specs) <= FBindings[i].SeriesIndex then
        SetLength(specs, FBindings[i].SeriesIndex + 1);
      specs[FBindings[i].SeriesIndex] := v.Label_;
      Inc(drawn, TyBuildSeriesMarks(FBindings[i], FStores[i],
        StackFor(i), v, list));
    end;
    { THE EXPANSION RUNS ONCE, HERE, AND NOTHING IS APPENDED AFTER IT. Each
      caption's geometry is frozen from its host at this moment and the list
      has no update path, so a mark added later would have no label and a mark
      moved later would leave its label behind. }
    if drawn > 0 then
      TyExpandLabels(list, specs, AMeasurer, APPI);
    { THE LEGEND GOES IN AFTER THE EXPANSION, and it is allowed to because
      its captions are ANSWERS rather than requests -- they arrive with a
      font and an anchor already on them, which is what the expansion exists
      to supply. A MARK appended here would silently lose its label. }
    Inc(drawn, BuildLegends(APPI, list));
    if drawn > 0 then
      TyRenderPaintList(APainter, list);
  finally
    list.Free;
  end;
end;

procedure TTyAdvanceChart.PaintDynamic(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
begin
  { NOTHING YET, and the empty body is the point of this commit rather than an
    omission: series marks, entry animation and the four-state highlight are
    Tier 1, and the layer they will draw into has to exist before the first of
    them is written or the first one written will draw into the static cache
    and freeze there.

    WHEN THIS STOPS BEING EMPTY, HasDynamicContent must start answering True,
    or RenderCached will skip the pass entirely. And what is drawn here is
    composited OVER the blitted static layer -- BeginPaint fills its bitmap
    transparent and EndPaint blends it (TBGRABitmap.Draw with AOpaque = False),
    so an overlay painter adds ink without erasing what is underneath. That is
    what makes two painters onto one canvas correct. }
end;

function TTyAdvanceChart.HasDynamicContent: Boolean;
begin
  { False until Tier 1 puts something in PaintDynamic. It is a function rather
    than a constant so the answer can become a real question -- "is anything
    animating, is anything hovered" -- without every caller changing. }
  Result := False;
end;

procedure TTyAdvanceChart.DropStatic;
begin
  if FStatic <> nil then FStatic.Drop;
end;

procedure TTyAdvanceChart.RenderCached(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
var
  P: TTyPainter;
  R: TRect;
  w, h: Integer;
  measurer: ITyTextMeasurer;
begin
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then Exit;
  R := Rect(0, 0, w, h);

  if FStatic = nil then FStatic := TTyPaintCache.Create;
  { PPI IS PART OF THE KEY and TTyPaintCache does not know it: NeedsRender only
    notices a size change, and a per-monitor DPI move can hand back the same
    size at a different PPI -- a chart drawn for 96 blitted onto a 192 window. }
  if APPI <> FStaticPPI then
  begin
    FStatic.Drop;
    FStaticPPI := APPI;
  end;

  if FStatic.NeedsRender(w, h) then
  begin
    measurer := TTyPainterTextMeasurer.Create(APPI);
    P := TTyPainter.Create;
    try
      P.BeginPaint(FStatic.Canvas, R, APPI);
      PaintStatic(P, R, APPI, measurer);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;
  FStatic.Blit(ACanvas);

  { A SECOND PAINTER ONLY WHEN THERE IS SOMETHING TO PUT IN IT. Creating one
    means allocating a BGRA bitmap the size of the control, filling it,
    blending it and freeing it -- roughly the 13 ms floor a frame has even with
    no axes, so paying it to draw nothing would give back most of what the
    cache just saved. }
  if not HasDynamicContent then Exit;
  measurer := TTyPainterTextMeasurer.Create(APPI);
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    PaintDynamic(P, R, APPI, measurer);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyAdvanceChart.Paint;
begin
  { THE DESIGNER RENDERS STRAIGHT THROUGH, as TTyPanel's does: it repaints
    rarely and streams while it does, so a cache buys nothing there and is one
    more thing that can be holding a frame from before the last property
    change. }
  if csDesigning in ComponentState then
  begin
    RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
    Exit;
  end;
  RenderCached(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyAdvanceChart.SaveToPng(const AFileName: string);
var bmp: TBGRABitmap;
begin
  if (Width <= 0) or (Height <= 0) then Exit;
  bmp := TBGRABitmap.Create(Width, Height);
  try
    RenderTo(bmp.Canvas, Rect(0, 0, Width, Height), Font.PixelsPerInch);
    bmp.SaveToFile(AFileName);
  finally
    bmp.Free;
  end;
end;

end.
