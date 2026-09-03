unit tyControls.AdvChart.Coord;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the coordinate-system layer.

  CONTRACT 1 (see docs/superpowers/specs/2026-09-01-advancechart-tier0.md §2).
  Every coordinate system answers a datum TWO ways:

    DataToPoint  -> the datum's ANCHOR (a line vertex, a scatter centre)
    DataToLayout -> the datum's CELL, as a Rect plus a ContentRect

  DataToLayout is what nesting rests on: a nested coordinate system, or a
  component laid out with coordinateSystemUsage:'box', is placed into the
  ContentRect its host returns for one datum. In ECharts this method is OPTIONAL
  and Cartesian2D does not implement it, which is why HeatmapView.ts:250-285 has
  to branch three ways (cartesian computes its own width/height, matrix reads
  .rect, calendar reads .contentRect). Here it is REQUIRED and cartesian
  implements it, so that branch collapses to one path.

  N AXES, not two. A secondary y axis is the commonest real-world request; making
  it a special case later is how a coordinate system ends up rewritten.

  PURE: SysUtils, Classes, Math and the AdvChart units. No Controls, no
  Graphics, no handle. Data is on that list because a category axis OWNS its
  category list, and that list is the same object a data store interns
  against -- the sharing IS the point, so it cannot be duplicated here. }
interface
uses SysUtils, Classes, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Data;

type
  { What an axis MEANS, which is not the same question as what scale object it
    holds: the builder picks the scale from this, then stamps it back so the
    option editor and the series binder can both ask without downcasting. }
  TTyAxisType = (atValue, atCategory, atTime, atLog);

  { Rect plus the divider-inset area a nested thing is laid out into. The two are
    not redundant: Rect is the whole cell (including the half of the divider that
    belongs to it), ContentRect is what may be painted into. ECharts'
    Calendar.dataToLayout (Calendar.ts:302-321) returns exactly this pair, and
    heatmap consumes `layout.contentRect || layout.rect`. }
  TTyCoordLayout = record
    Rect: TTyRectF;
    ContentRect: TTyRectF;
  end;

  { One axis: a scale plus where it lives in pixels. }
  TTyAxis = class
  private
    FDim: string;
    FScale: TTyScale;
    FHorizontal: Boolean;
    FPxStart: Double;
    FPxStop: Double;
    FInverse: Boolean;
    FMainType: string;
    FComponentIndex: Integer;
    FId: string;
    FName: string;
    FAxisType: TTyAxisType;
    FGridIndex: Integer;
    FSide: TTyAxisSide;
    FVisible: Boolean;
    FOnBand: Boolean;
    FCategories: TTyOrdinalMeta;
    procedure SetOnBand(AValue: Boolean);
    procedure SetAxisType(AValue: TTyAxisType);
    { The pixel extent a BANDED axis maps over: half a band in from each end,
      so an ordinal value lands on its band's CENTRE rather than its edge. }
    procedure BandPxExtent(out AStart, AStop: Double);
  public
    { Takes ownership of AScale. }
    constructor Create(const ADim: string; AScale: TTyScale; AHorizontal: Boolean);
    destructor Destroy; override;
    procedure SetPxExtent(AStart, AStop: Double);
    { Value -> px along this axis. Extrapolates outside the extent ON PURPOSE:
      clipping is the renderer's decision, not the coordinate system's, and a
      clipped line still has to be drawn towards a real off-band point. }
    function DataToCoord(AValue: Double): Double;
    function CoordToData(ACoord: Double): Double;
    property Dim: string read FDim;
    property Scale: TTyScale read FScale;
    property Horizontal: Boolean read FHorizontal;
    property PxStart: Double read FPxStart;
    property PxStop: Double read FPxStop;
    { The width of one datum's band, DEVICE px. DERIVED, not stored: the pixel
      extent is written more than once per layout pass -- an approximate one off
      the raw grid rect, then the final one off the shrunk plot rect -- and a
      width cached at construction is stale by the second write.

      0 means NOT BANDED: a continuous axis, and a cell collapses onto its
      anchor rather than inventing a width. That is a deliberate divergence.
      ECharts floors band width at 1px on every axis type, but that floor exists
      for its bar layouter, not as a claim that a value axis has bands -- its
      own internal call passes no floor at all. The floor belongs to the bar
      layouter when we write one. }
    function BandWidth: Double;
    property Inverse: Boolean read FInverse write FInverse;

    { ---- identity ----
      Which option array this axis came out of, and where in it.

      ComponentIndex is the GLOBAL index in that array and is never renumbered
      per grid: it is what a series' xAxisIndex names, and grid 1's first x axis
      is legitimately component 2. Renumbering per grid is the shortest path to
      bindings that silently resolve to the wrong plot. }
    property MainType: string read FMainType write FMainType;
    property ComponentIndex: Integer read FComponentIndex write FComponentIndex;
    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property AxisType: TTyAxisType read FAxisType write SetAxisType;
    { -1 = this axis names no grid, and so belongs to no plot rect. It is still
      built, so the option editor can report on it; it is simply never put into
      a coordinate system. }
    property GridIndex: Integer read FGridIndex write FGridIndex;
    property Side: TTyAxisSide read FSide write FSide;
    { The option's `show`. An axis that is switched off still takes part in the
      build -- series bound to it keep their extents and their coordinates --
      it is only not DRAWN. Defaults True, matching upstream. }
    property Visible: Boolean read FVisible write FVisible;
    { Category axes band by default; value axes never do. The setter GATES on
      the scale being ordinal, because a value axis' boundaryGap is a PAIR of
      percentages rather than a boolean, and an ungated setter would band every
      value axis in the chart. }
    property OnBand: Boolean read FOnBand write SetOnBand;
    { A stable name for this axis across the whole chart, for keying a map by.

      MainType plus ComponentIndex, because that pair is unique and never
      renumbered. NOT the object pointer: an index that outlives a rebuild would
      then key on an address the allocator has since handed to something else,
      and this library has already been bitten once by an identity assertion
      that went green on a reused address. }
    function Uid: string;

    { ---- categories ----
      OWNED BY THE AXIS, and handed to the scale and to every series' data store
      by REFERENCE. That sharing is the whole mechanism: a category collected
      off one series' data has to reach the axis and every other series on it,
      and two series with private lists disagree about which name ordinal 0 is.

      nil unless the scale is ordinal. }
    property Categories: TTyOrdinalMeta read FCategories;
    { Set a FIXED category list -- an axis that declares its own `data`. Also
      re-derives the scale's extent, because the two are one fact: leaving the
      caller to remember the second step is how an axis ends up with categories
      and an empty extent. }
    procedure SetCategories(const A: array of string);

    { Where a value sits along this axis as a fraction of its BAND-ADJUSTED
      pixel extent, 0 at the start and 1 at the stop.

      Exists so the layout layer and the renderer cannot drift: the layout layer
      wants fractions, DataToCoord applies Inverse and the half-band inset
      internally, and a caller computing its own fraction from the raw extent
      would silently disagree with where the datum is actually drawn. }
    function NormalizedCoord(AValue: Double): Double;

    { Where the TICK MARKS go, in device px.

      Ticks and labels do NOT share a position on a banded axis, and that is
      the default rather than an option: a label belongs to a category so it
      sits on the band's CENTRE, while a tick separates two categories so it
      sits on the EDGE. So a three-category axis has three labels and FOUR
      ticks out of the box, and a test asserting one tick per category is
      asserting the wrong thing.

      AAlignWithLabel moves them onto the centres and gives N of them, which is
      ECharts' axisTick.alignWithLabel. A non-banded axis ignores it: its
      categories already sit on the ends. }
    function TickCoords(AAlignWithLabel: Boolean = False): TTyDoubleArray;
  end;

  ITyCoordSys = interface
    ['{2F5B71A4-9C68-4D0E-8A73-15E9C2B4770D}']
    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;
    function DataToPoint(const AData: array of Double): TTyPointF;
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    function PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): TTyAxis;
  end;

  { A 2D cartesian coordinate system over N axes. The first horizontal axis and
    the first vertical one are the MASTER pair the 2-argument DataToPoint uses;
    the rest are addressed explicitly through a series' axis binding.

    Non-refcounted (see TTyNonRefCountedObject): the chart owns its coordinate
    systems, while box containers holding ITyCoordSys are temporaries. }
  TTyCartesian2D = class(TTyNonRefCountedObject, ITyCoordSys)
  private
    FAxes: array of TTyAxis;
    FRect: TTyRectF;
    FDividerWidth: Double;
    FOwnsAxes: Boolean;
    function MasterX: TTyAxis;
    function MasterY: TTyAxis;
    procedure ReflowAxes;
  public
    constructor Create;
    destructor Destroy; override;
    { Takes ownership BY DEFAULT -- see OwnsAxes. }
    procedure AddAxis(AAxis: TTyAxis);
    procedure SetRect(const ARect: TTyRectF);

    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;
    function DataToPoint(const AData: array of Double): TTyPointF;
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    function PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
    { Closed on ALL four edges — "is this point in the plot area" is a different
      question from "which datum cell owns this pixel". A point on the right
      border is still in the chart; TyRectFContains, which the cell rule uses, is
      half-open so two adjacent bands cannot both claim a column. }
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): TTyAxis;
    { The axis for a coordinate dimension -- 'x', 'y' -- rather than for a slot.

      Positional access happens to work today only because the builder adds x
      before y, and nothing enforces that: AddAxis takes any order and the
      reflow is orientation-general. Asking by name cannot drift. }
    function AxisByDim(const ADim: string): TTyAxis;
    { The axis a series is laid out ALONG: the categorical or temporal spine.
      The other one carries the value.

      Order of preference, and the order of the candidates is itself part of the
      rule: an ordinal x, then an ordinal y, then a time x, then a time y, then
      x regardless. Branching on AxisType rather than on the scale's CLASS is
      deliberate -- a time axis is an interval scale here, so a class test would
      silently skip the two time rules and hand back x for every time chart.

      Upstream carries a note that a series ought to be able to name its own
      base axis when neither is categorical, and cannot. Boxplot and candlestick
      work around it by overriding the answer entirely, which is where that
      belongs when they arrive. }
    function GetBaseAxis: TTyAxis;
    function GetOtherAxis(AAxis: TTyAxis): TTyAxis;
    { Half of this comes off each side of a cell to give its ContentRect. }
    property DividerWidth: Double read FDividerWidth write FDividerWidth;
    { True by default, so a coordinate system built and freed on its own frees
      what it was given.

      A grid with N x axes and M y axes holds N*M coordinate systems over N+M
      axes, so the SAME axis object is in several of them and would be freed
      several times. The builder therefore sets this False and frees the axes
      once itself. Sharing is otherwise safe: every coordinate system of one
      grid is given the same rect, so the repeated pixel-extent write each of
      them performs is idempotent. }
    property OwnsAxes: Boolean read FOwnsAxes write FOwnsAxes;
  end;

implementation

{ ============================ TTyAxis ============================ }

constructor TTyAxis.Create(const ADim: string; AScale: TTyScale; AHorizontal: Boolean);
begin
  inherited Create;
  FDim := ADim;
  FScale := AScale;
  FHorizontal := AHorizontal;
  FPxStart := 0;
  FPxStop := 1;
  FInverse := False;
  FMainType := '';
  FComponentIndex := -1;
  FId := '';
  FName := '';
  FAxisType := atValue;
  FGridIndex := -1;
  FSide := asBottom;
  FVisible := True;
  FOnBand := False;
  FCategories := nil;
  if FScale is TTyOrdinalScale then
  begin
    FCategories := TTyOrdinalMeta.Create;
    TTyOrdinalScale(FScale).SetMeta(FCategories);
  end;
end;

procedure TTyAxis.SetCategories(const A: array of string);
begin
  if FCategories = nil then
    raise EInvalidOperation.CreateFmt(
      'SetCategories: axis "%s" is not categorical', [FDim]);
  FCategories.SetCategories(A);
  TTyOrdinalScale(FScale).SetExtentFromCategories;
end;

destructor TTyAxis.Destroy;
begin
  { Order matters: the scale BORROWS the list, so the scale goes first. }
  FScale.Free;
  FCategories.Free;
  inherited Destroy;
end;

procedure TTyAxis.SetPxExtent(AStart, AStop: Double);
begin
  FPxStart := AStart;
  FPxStop := AStop;
end;

procedure TTyAxis.SetOnBand(AValue: Boolean);
begin
  FOnBand := AValue and (FScale is TTyOrdinalScale);
end;

procedure TTyAxis.SetAxisType(AValue: TTyAxisType);
begin
  FAxisType := AValue;
  { Re-gate: a type change can invalidate banding. }
  SetOnBand(FOnBand);
end;

procedure TTyAxis.BandPxExtent(out AStart, AStop: Double);
var
  m: Double;
  n: Integer;
begin
  AStart := FPxStart;
  AStop := FPxStop;
  if not FOnBand then Exit;
  n := 0;
  if FScale is TTyOrdinalScale then n := TTyOrdinalScale(FScale).Count;
  if n <= 0 then Exit;
  { SIGNED, deliberately not Abs. On a vertical axis PxStop is above PxStart, so
    the margin comes out negative and both ends still move INWARD -- which is
    what makes a bottom-up or an inverse axis work. An Abs here would look right
    on every horizontal test and be wrong on every vertical one. }
  m := (AStop - AStart) / n / 2;
  AStart := AStart + m;
  AStop := AStop - m;
end;

function TTyAxis.BandWidth: Double;
var
  span, pxSpan, len: Double;
begin
  Result := 0;
  if not (FScale is TTyOrdinalScale) then Exit;
  if TTyOrdinalScale(FScale).Blank then Exit;
  { The mapping extent when one is set, else the effective one. For N categories
    this span is N-1, while Count is N -- two routes to the same N, which is
    exactly why they are computed in one place. }
  span := TyRangeSpan(FScale.GetExtent2(sekMapping));
  if IsNan(span) or IsInfinite(span) then Exit;
  pxSpan := Abs(FPxStop - FPxStart);
  len := span;
  if FOnBand then len := len + 1;
  { One category: span is 0 and the axis is one band wide. }
  if len = 0 then len := 1;
  Result := pxSpan / len;
end;

function TTyAxis.Uid: string;
begin
  Result := FMainType + ':' + IntToStr(FComponentIndex);
end;

function TTyAxis.NormalizedCoord(AValue: Double): Double;
var a, b: Double;
begin
  BandPxExtent(a, b);
  if b = a then Exit(0.5);
  Result := (DataToCoord(AValue) - a) / (b - a);
end;

function TTyAxis.TickCoords(AAlignWithLabel: Boolean): TTyDoubleArray;
var
  ticks: TTyScaleTickArray;
  i, n: Integer;
  bw, dir: Double;
begin
  ticks := FScale.GetTicks;
  n := Length(ticks);
  if n = 0 then Exit(nil);

  if (not FOnBand) or AAlignWithLabel then
  begin
    { One per tick, on the anchor the label uses. }
    SetLength(Result, n);
    for i := 0 to n - 1 do
      Result[i] := DataToCoord(ticks[i].Value);
    Exit;
  end;

  { Banded and not aligned: shift every tick back half a band onto the leading
    edge, then add one more for the trailing edge of the last band. N+1 for N
    categories. The shift follows the axis' DIRECTION, not its magnitude -- a
    vertical or inverse axis runs the other way and a bare subtraction would
    push the ticks off the wrong end. }
  bw := BandWidth;
  if FPxStop >= FPxStart then dir := 1 else dir := -1;
  if FInverse then dir := -dir;
  SetLength(Result, n + 1);
  for i := 0 to n - 1 do
    Result[i] := DataToCoord(ticks[i].Value) - dir * bw / 2;
  Result[n] := Result[n - 1] + dir * bw;
end;

function TTyAxis.DataToCoord(AValue: Double): Double;
var n, a, b: Double;
begin
  if IsNan(AValue) then
    Exit(NaN);
  n := FScale.Normalize(AValue);
  if FInverse then
    n := 1 - n;
  { The half-band inset is applied to the PIXEL extent, never to the value --
    an ordinal 0 is still ordinal 0, it just lands on its band's centre. }
  BandPxExtent(a, b);
  Result := a + n * (b - a);
end;

function TTyAxis.CoordToData(ACoord: Double): Double;
var n, span, a, b: Double;
begin
  BandPxExtent(a, b);
  span := b - a;
  if span = 0 then
    Exit(FScale.GetExtent.Start);
  n := (ACoord - a) / span;
  if FInverse then
    n := 1 - n;
  Result := FScale.Denormalize(n);
end;

{ ============================ TTyCartesian2D ============================ }

constructor TTyCartesian2D.Create;
begin
  inherited Create;
  FAxes := nil;
  FRect := TyRectF(0, 0, 1, 1);
  FDividerWidth := 0;
  FOwnsAxes := True;
end;

destructor TTyCartesian2D.Destroy;
var i: Integer;
begin
  if FOwnsAxes then
    for i := 0 to High(FAxes) do
      FAxes[i].Free;
  FAxes := nil;
  inherited Destroy;
end;

procedure TTyCartesian2D.AddAxis(AAxis: TTyAxis);
var n: Integer;
begin
  n := Length(FAxes);
  SetLength(FAxes, n + 1);
  FAxes[n] := AAxis;
  ReflowAxes;
end;

procedure TTyCartesian2D.SetRect(const ARect: TTyRectF);
begin
  FRect := ARect;
  ReflowAxes;
end;

procedure TTyCartesian2D.ReflowAxes;
var i: Integer;
begin
  { Every axis spans the whole band on its own orientation. A y axis runs from
    the BOTTOM up — this is the single place screen-vs-value direction is
    decided, and it is why nothing downstream needs to remember to flip. }
  for i := 0 to High(FAxes) do
    if FAxes[i].Horizontal then
      FAxes[i].SetPxExtent(FRect.Left, FRect.Right)
    else
      FAxes[i].SetPxExtent(FRect.Bottom, FRect.Top);
end;

function TTyCartesian2D.MasterX: TTyAxis;
var i: Integer;
begin
  Result := nil;
  for i := 0 to High(FAxes) do
    if FAxes[i].Horizontal then
      Exit(FAxes[i]);
end;

function TTyCartesian2D.MasterY: TTyAxis;
var i: Integer;
begin
  Result := nil;
  for i := 0 to High(FAxes) do
    if not FAxes[i].Horizontal then
      Exit(FAxes[i]);
end;

function TTyCartesian2D.CoordSysName: string;
begin
  Result := 'cartesian2d';
end;

function TTyCartesian2D.DimCount: Integer;
begin
  Result := 2;
end;

function TTyCartesian2D.GetRect: TTyRectF;
begin
  Result := FRect;
end;

function TTyCartesian2D.AxisByDim(const ADim: string): TTyAxis;
var i: Integer;
begin
  for i := 0 to High(FAxes) do
    if FAxes[i].Dim = ADim then Exit(FAxes[i]);
  Result := nil;
end;

function TTyCartesian2D.GetBaseAxis: TTyAxis;
const
  BasePreference: array[0..1] of TTyAxisType = (atCategory, atTime);
var
  i, k: Integer;
  t: TTyAxisType;
begin
  Result := nil;
  if Length(FAxes) = 0 then Exit;
  { Two passes over the axes in their own order -- every ordinal axis first,
    then every time one -- because "the first ordinal, else the first time" is
    what the rule says. A single pass scoring each axis would answer differently
    when x is time and y is categorical, and that chart is not rare.

    The preference list is spelled out rather than written as a range over the
    enum: a range would quietly change meaning if anyone reordered the type. }
  for k := Low(BasePreference) to High(BasePreference) do
  begin
    t := BasePreference[k];
    for i := 0 to High(FAxes) do
      if FAxes[i].AxisType = t then Exit(FAxes[i]);
  end;
  { Neither: the horizontal one, which is x. }
  for i := 0 to High(FAxes) do
    if FAxes[i].Horizontal then Exit(FAxes[i]);
  Result := FAxes[0];
end;

function TTyCartesian2D.GetOtherAxis(AAxis: TTyAxis): TTyAxis;
var i: Integer;
begin
  Result := nil;
  if AAxis = nil then Exit;
  for i := 0 to High(FAxes) do
    if FAxes[i].Horizontal <> AAxis.Horizontal then Exit(FAxes[i]);
end;

function TTyCartesian2D.AxisCount: Integer;
begin
  Result := Length(FAxes);
end;

function TTyCartesian2D.GetAxis(AIndex: Integer): TTyAxis;
begin
  if (AIndex < 0) or (AIndex > High(FAxes)) then
    Exit(nil);
  Result := FAxes[AIndex];
end;

function TTyCartesian2D.DataToPoint(const AData: array of Double): TTyPointF;
var ax, ay: TTyAxis;
begin
  ax := MasterX;
  ay := MasterY;
  if (ax = nil) or (ay = nil) or (Length(AData) < 2) then
    Exit(TyInvalidPointF);
  Result.X := ax.DataToCoord(AData[0]);
  Result.Y := ay.DataToCoord(AData[1]);
end;

function TTyCartesian2D.DataToLayout(const AData: array of Double): TTyCoordLayout;
var
  ax, ay: TTyAxis;
  p: TTyPointF;
  hw, baseY, half: Double;
begin
  Result.Rect := TyInvalidRectF;
  Result.ContentRect := TyInvalidRectF;
  ax := MasterX;
  ay := MasterY;
  if (ax = nil) or (ay = nil) or (Length(AData) < 2) then
    Exit;
  p := DataToPoint(AData);
  if IsNan(p.X) or IsNan(p.Y) then
    Exit;
  { The cell is one band wide and runs from the value axis' baseline to the
    datum — which is exactly a bar, and exactly the rect a nested chart would be
    given. A continuous axis has no band, so the cell collapses onto the anchor
    rather than inventing a width. }
  if ax.BandWidth > 0 then
    hw := ax.BandWidth / 2
  else
    hw := 0;
  baseY := ay.DataToCoord(ay.Scale.GetExtent.Start);
  Result.Rect := TyRectF(p.X - hw, Min(p.Y, baseY), p.X + hw, Max(p.Y, baseY));
  half := FDividerWidth / 2;
  Result.ContentRect := TyRectF(Result.Rect.Left + half, Result.Rect.Top + half,
                                Result.Rect.Right - half, Result.Rect.Bottom - half);
  { A divider wider than the cell would invert it, and an inverted rect survives
    a later Min/Max swap to reappear as a phantom band somewhere else. Collapse
    to a zero-area rect at the centre instead: still valid, contains nothing. }
  if Result.ContentRect.Right < Result.ContentRect.Left then
  begin
    Result.ContentRect.Left := (Result.Rect.Left + Result.Rect.Right) / 2;
    Result.ContentRect.Right := Result.ContentRect.Left;
  end;
  if Result.ContentRect.Bottom < Result.ContentRect.Top then
  begin
    Result.ContentRect.Top := (Result.Rect.Top + Result.Rect.Bottom) / 2;
    Result.ContentRect.Bottom := Result.ContentRect.Top;
  end;
end;

function TTyCartesian2D.PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
var ax, ay: TTyAxis;
begin
  AData := nil;
  ax := MasterX;
  ay := MasterY;
  if (ax = nil) or (ay = nil) then
    Exit(False);
  SetLength(AData, 2);
  AData[0] := ax.CoordToData(APoint.X);
  AData[1] := ay.CoordToData(APoint.Y);
  Result := True;
end;

function TTyCartesian2D.ContainPoint(const APoint: TTyPointF): Boolean;
begin
  Result := (APoint.X >= FRect.Left) and (APoint.X <= FRect.Right)
        and (APoint.Y >= FRect.Top) and (APoint.Y <= FRect.Bottom);
end;

end.
