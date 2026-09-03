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
  tyControls.AdvChart.Measure, tyControls.AdvChart.Handlers;

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
    procedure Relayout(APainter: TTyPainter; const ARect: TTyRectF; APPI: Integer);
    procedure PaintAxis(APainter: TTyPainter; AAxis: TTyAxis;
      const APlot: TTyRectF; APPI: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure Resize; override;
    { Protected and non-virtual, exactly as every other control in the library:
      a headless test renders through it onto an offscreen bitmap, and it
      bypasses the on-screen paint path entirely. }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate; override;
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
      looks like. A rejected option keeps the previous one -- a half-typed
      config in a design-time editor must not blank the chart. }
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

{ WHAT WAS WRITTEN, not what parsed. The option tree keeps the last text it
  understood, deliberately -- a rejected option leaves the previous chart
  standing rather than blanking it. But the PROPERTY has to read back what the
  host set, or a half-typed option in the Object Inspector reverts on every
  keystroke that does not yet parse, and a .lfm cannot round-trip work in
  progress. So the control remembers the text and the tree remembers the last
  good one; OptionError says which is which. }
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
  APPI: Integer);
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
  TyLayoutGrids(FBuild, FOption, TTyPainterTextMeasurer.Create(APPI), APPI, txt);
  FDirty := False;
end;

{ ==================== paint ==================== }

procedure TTyAdvanceChart.PaintAxis(APainter: TTyPainter; AAxis: TTyAxis;
  const APlot: TTyRectF; APPI: Integer);
var
  model: TTyStyleModel;
  lineS, tickStyle, labelS, splitS: TTyStyleSet;
  ticks: TTyDoubleArray;
  i: Integer;
  tickLen, at, along, x1, y1, x2, y2: Double;
  horiz: Boolean;
  txt: string;
  lblH, lblW: Integer;
  scaleTicks: TTyScaleTickArray;

  { One hairline. ScaleF rather than Scale on purpose: a 1 px axis line at 150
    per cent is 1.5 px, and rounding it to 2 is how a chart's grid comes out
    heavier than the control chrome around it. }
  procedure Hairline(AX1, AY1, AX2, AY2: Double; AColor: TTyColor);
  begin
    APainter.BeginPath;
    APainter.MoveTo(AX1, AY1);
    APainter.LineTo(AX2, AY2);
    APainter.StrokePath(AColor, 1);
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

  { Split lines first, so the domain and the ticks sit on top of them.

    TickCoords' default, NOT AAlignWithLabel: a split line divides the bands, it
    does not point at a label. On a banded category axis the two differ by half
    a band, which is exactly the width the whole parameter exists to express. }
  if tpBorderColor in splitS.Present then
  begin
    ticks := AAxis.TickCoords;
    for i := 0 to High(ticks) do
    begin
      along := ticks[i];
      if horiz then
        Hairline(along, APlot.Top, along, APlot.Bottom, splitS.BorderColor)
      else
        Hairline(APlot.Left, along, APlot.Right, along, splitS.BorderColor);
    end;
  end;

  { The domain line. Present, not colour: an undeclared colour resolves to
    alpha zero, so testing the colour would draw an invisible line and call it
    drawn. }
  if tpBorderColor in lineS.Present then
  begin
    if horiz then
      Hairline(APlot.Left, at, APlot.Right, at, lineS.BorderColor)
    else
      Hairline(at, APlot.Top, at, APlot.Bottom, lineS.BorderColor);
  end;

  ticks := AAxis.TickCoords;
  if tpBorderColor in tickStyle.Present then
    for i := 0 to High(ticks) do
    begin
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
      Hairline(x1, y1, x2, y2, tickStyle.BorderColor);
    end;

  if not (tpTextColor in labelS.Present) then Exit;
  { A CATEGORY axis labels its categories; a VALUE axis labels its tick values.
    Handling only the first leaves a value axis with ticks and no numbers -- and
    a pixel count cannot see that, because the ticks and grid lines are hundreds
    of pixels on their own. It took a render on a real machine to notice. }
  lblH := APainter.MeasureText('Wg', labelS.FontName, ResolveFontSize(labelS),
    labelS.FontWeight).cy;
  scaleTicks := AAxis.Scale.GetTicks;
  for i := 0 to High(scaleTicks) do
  begin
    if AAxis.Scale is TTyOrdinalScale then
      txt := TTyOrdinalScale(AAxis.Scale).GetLabel(scaleTicks[i].Value)
    else
      txt := TyChartNumToStr(scaleTicks[i].Value);
    if txt = '' then Continue;
    along := AAxis.DataToCoord(scaleTicks[i].Value);
    lblW := APainter.MeasureText(txt, labelS.FontName, ResolveFontSize(labelS),
      labelS.FontWeight).cx;
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
begin
  P := TTyPainter.Create;
  try
    { LOCAL space. EndPaint blits at ARect's origin, so everything below is
      measured from zero. }
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    { Resolved at REST on purpose. The plot rect is measured from the label
      font, and a geometry that read the focused style would move the whole
      chart the moment it took focus. }
    boxStyle := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass,
      [tysNormal]);
    { Mandatory first draw, and it does more than a fill: parent backdrop,
      opacity, shadow, background, border, and the corner gaps a windowed
      control cannot get from a shadow it is not allowed to cast. }
    DrawFrame(P, R, boxStyle);

    plotF := TyRectF(R.Left, R.Top, R.Right, R.Bottom);
    if FDirty or (plotF.Right <> FLastRect.Right) or (plotF.Bottom <> FLastRect.Bottom) then
      Relayout(P, plotF, APPI);

    if FBuild <> nil then
      for g := 0 to FBuild.GridCount - 1 do
      begin
        gb := FBuild.Grid(g);
        for a := 0 to gb.XAxisCount - 1 do
          PaintAxis(P, gb.XAxis(a), gb.PlotRect, APPI);
        for a := 0 to gb.YAxisCount - 1 do
          PaintAxis(P, gb.YAxis(a), gb.PlotRect, APPI);
      end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyAdvanceChart.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
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
