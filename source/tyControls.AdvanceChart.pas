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
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  BGRABitmap,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.StyleModel,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
  tyControls.AdvChart.Measure, tyControls.AdvChart.Handlers,
  tyControls.SubPixel;

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
  i, k: Integer;
  dims: TTySeriesDimArray;
  st: TTyDataStore;
begin
  DropBuild;
  FBuild := TyBuildGrids(FOption, FLastRect);
  FBindings := TyBindSeries(FOption, FBuild);
  SetLength(FStores, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    st := TTyDataStore.Create;
    FStores[i] := st;
    if not FBindings[i].HasAxes then Continue;
    dims := TySeriesCartesianDims(FBindings[i].Cart, 0);
    for k := 0 to High(dims) do
    begin
      st.AddDimension(dims[k].Name, dims[k].Kind);
      { The axis owns the category list and every series on it borrows the SAME
        one -- that sharing is what makes two series agree about which name
        ordinal 0 is. }
      if dims[k].Axis <> nil then st.UseOrdinalMeta(k, dims[k].Axis.Categories);
    end;
    TyFillSeriesStore(FOption, i, dims, st);
  end;
  TyIndexSeries(FBindings, FIndex);
  TyApplyAxisExtents(FOption, FBuild, FBindings, FStores, FIndex);
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

  { THE BOX IS THE TRANSLATION. The layout layer says "this point, with the
    text hanging off it this way"; the painter aligns text INSIDE a rectangle.
    Building a box that is exactly the text's size around the anchor makes the
    two agree, and makes the alignment argument irrelevant.

    Mapping anchors to LCL alignments instead was the first attempt and it was
    wrong in a way worth remembering: a right-anchored label kept the old
    symmetric box, so right-justifying inside it put the text's right edge a
    whole width PAST the anchor -- straight through the tick marks. }
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

  horiz := AAxis.Horizontal;
  { The axis sits on the edge of the plot its side names. }
  if horiz then at := APlot.Bottom else at := APlot.Left;
  if AAxis.Side = asTop then at := APlot.Top;
  if AAxis.Side = asRight then at := APlot.Right;

  tickLen := APainter.ScaleF(ActiveController.Metric(TyAdvChartTickLenVar,
    TyAdvChartTickLen));
  minorLen := APainter.ScaleF(ActiveController.Metric(TyAdvChartMinorTickLenVar,
    TyAdvChartMinorTickLen));

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
  if (tpBorderColor in minorSplitS.Present) and (step = 1) then
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

  if tpBorderColor in splitS.Present then
  begin
    ticks := AAxis.TickCoords;
    APainter.BeginPath;
    for i := 0 to High(ticks) do
    begin
      { THINNED WITH THE LABELS, on the same step the ticks use. }
      if (step > 1) and (i mod step <> 0) then Continue;
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
  if tpBorderColor in lineS.Present then
  begin
    APainter.BeginPath;
    if horiz then
      BatchLine(APlot.Left, at, APlot.Right, at, LineWidth(lineS))
    else
      BatchLine(at, APlot.Top, at, APlot.Bottom, LineWidth(lineS));
    StrokeBatch(lineS);
  end;

  ticks := AAxis.TickCoords;
  { THE MARKS THIN WITH THE LABELS. Drawing every tick under a thinned set of
    labels reads as an axis that lost its labels rather than one that spaced
    them out, and computing the step by a second route is how the two drift --
    which is why `step` is worked out once, above, and the split lines use the
    same one. }
  if tpBorderColor in tickStyle.Present then
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
  if (tpBorderColor in minorTickS.Present) and (step = 1) then
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
