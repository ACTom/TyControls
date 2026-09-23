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

  { How an axis' own pixel coordinate becomes the canvas': upstream's
    toGlobalCoord. A grid's x axis adds its left edge; its y axis runs the
    other way, (extent sum - c) + top. apmIdentity is a pixel extent written
    as canvas coordinates already -- a radar spoke, or a test. }
  TTyAxisPxMap = (apmIdentity, apmX, apmY);

  { One axis: a scale plus where it lives in pixels. }
  TTyAxis = class
  private
    FDim: string;
    FScale: TTyScale;
    FHorizontal: Boolean;
    FPxMap: TTyAxisPxMap;
    { apmX / apmY: the grid's width or height and its left or top edge, as
      upstream holds them. apmIdentity: the two ends as written. }
    FPxLen: Double;
    FPxBase: Double;
    FIdent0, FIdent1: Double;
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
    FZeroDiscouraged: Boolean;
    FCategories: TTyOrdinalMeta;
    procedure SetOnBand(AValue: Boolean);
    procedure SetAxisType(AValue: TTyAxisType);
    function GetPxStart: Double;
    function GetPxStop: Double;
    function GetPxLength: Double;
  public
    { Takes ownership of AScale. }
    constructor Create(const ADim: string; AScale: TTyScale; AHorizontal: Boolean);
    destructor Destroy; override;
    { A pixel extent in canvas coordinates, mapped as it is: a radar spoke. }
    procedure SetPxExtent(AStart, AStop: Double);
    { UPSTREAM'S GRID AXIS: the local extent is [0, ALength] -- [ALength, 0]
      when inverse -- and ABase is the grid's left (x) or top (y) edge.
      ALength is the grid's width or height as upstream holds it, never an
      edge minus an edge: (x + w) - x is not always w. }
    procedure SetLayoutExtent(ABase, ALength: Double; AVertical: Boolean);
    { The local extent, inverse applied: upstream's axis.getExtent(). }
    procedure LocalExtent(out AStart, AStop: Double);
    { The same pulled in by half a band each end on a banded axis, so an
      ordinal value lands on its band's CENTRE: makeExtentWithBands. }
    procedure BandExtent(out AStart, AStop: Double);
    function ToGlobal(ALocal: Double): Double;
    function ToLocal(AGlobal: Double): Double;
    { Value -> the axis' own coordinate: normalise over the mapping extent,
      then linearMap onto the band extent, which hands back an end verbatim
      at 0 and 1 -- and with AClamp, at and beyond them. }
    function DataToLocal(AValue: Double; AClamp: Boolean = False): Double;
    { Value -> px along this axis. Extrapolates outside the extent ON PURPOSE
      unless clamped: clipping is the renderer's decision, not the coordinate
      system's, and a clipped line still has to be drawn towards a real
      off-band point. }
    function DataToCoord(AValue: Double; AClamp: Boolean = False): Double;
    function CoordToData(ACoord: Double): Double;
    property Dim: string read FDim;
    property Scale: TTyScale read FScale;
    property Horizontal: Boolean read FHorizontal;
    { Where the extent's start and stop land on the canvas with inverse NOT
      applied: left and right on x, bottom and top on y. }
    property PxStart: Double read GetPxStart;
    property PxStop: Double read GetPxStop;
    { The pixel length -- the grid's width or height itself. What a band is
      measured against. }
    property PxLength: Double read GetPxLength;
    property PxMap: TTyAxisPxMap read FPxMap;
    property PxBase: Double read FPxBase;
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
    { UPSTREAM'S discourageOnAxisZero. Set in phase B when a bar's half width
      was added to this axis' mapping extent: its zero is no longer where the
      eye expects the other axis to stand, so an axis whose onZero is `auto`
      no longer sits on it. One that wrote `onZero: true` still does. Set even
      when the widening moved no end. Never cleared: every build makes its
      axes afresh. }
    property ZeroDiscouraged: Boolean read FZeroDiscouraged write FZeroDiscouraged;
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

    { Where a value sits along this axis as a fraction of its WHOLE pixel
      extent, 0 at the start and 1 at the stop -- with the half-band inset
      and Inverse already applied, because it is DataToCoord's own answer.

      Exists so the layout layer and the renderer cannot drift: the layout
      layer wants fractions of the plot it is laying out on, and a caller
      computing its own fraction would silently disagree with where the
      datum is actually drawn.
      [Revised in batch 37: this was a fraction of the band-INSET extent,
      which the layout then spread over the whole plot -- so the first of
      seven category labels stood at the plot's edge and the last at the
      other, a band's half-width wide of the bars they named.] }
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
    FXYWH: TTyXYWH;
    FHasTransform, FHasInvTransform: Boolean;
    FTransform, FInvTransform: TTyMat2D;
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
    { The plot, as edges -- taken back into x, y, width and height. }
    procedure SetRect(const ARect: TTyRectF);
    { The plot as upstream holds it. Every axis is laid over it, and the
      affine matrix is dropped: it belongs to a final rect only. }
    procedure SetRectXYWH(const ARect: TTyXYWH);
    function GetXYWH: TTyXYWH;
    { UPSTREAM'S calcAffineTransform, run once the rect is final and the
      scales are: when both master axes are value or time, a matrix from the
      per-axis answers at the ends of the two mapping extents, which every
      finite datum is then placed through. Not a shortcut with the same
      answer -- the last bits differ from the per-axis ones, and upstream
      draws what the matrix gives. Its inverse too, when it has one. }
    procedure CalcAffineTransform;
    function Transform(out AM: TTyMat2D): Boolean;
    function InvTransform(out AM: TTyMat2D): Boolean;
    { upstream's getArea: the x axis' two ends on the canvas, the lesser one
      and the distance to the other, and the same for y. What a bar is
      clipped to. }
    function GetArea: TTyXYWH;
    { getArea(tolerance): the same widened by ATol on every side, in
      upstream's order -- the lesser end less it, and the distance to the
      greater end plus it }
    function GetAreaTol(ATol: Double): TTyXYWH;
    { With AClamp, a value past an end lands on it -- on the per-axis path
      only, as upstream's: the matrix does not clamp. }
    function DataToPointClamped(const AData: array of Double;
      AClamp: Boolean): TTyPointF;

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

{ THE VALUE A BAR STANDS ON, upstream's getValueAxisStart: the axis' resolved
  startValue, or where it has none 1 on a log axis and 0 on any other -- NOT
  the extent's start. The two agree only while the extent starts there: a
  chart with a negative bar in it grows every bar from zero, up or down. }
function TyValueAxisStart(AAxis: TTyAxis): Double;

implementation

function TyValueAxisStart(AAxis: TTyAxis): Double;
begin
  if AAxis.Scale.HasStartValue then Exit(AAxis.Scale.StartValue);
  if AAxis.AxisType = atLog then Result := 1 else Result := 0;
end;

{ ============================ TTyAxis ============================ }

constructor TTyAxis.Create(const ADim: string; AScale: TTyScale; AHorizontal: Boolean);
begin
  inherited Create;
  FDim := ADim;
  FScale := AScale;
  FHorizontal := AHorizontal;
  FPxMap := apmIdentity;
  FIdent0 := 0;
  FIdent1 := 1;
  FPxLen := 1;
  FPxBase := 0;
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
  FPxMap := apmIdentity;
  FIdent0 := AStart;
  FIdent1 := AStop;
  FPxLen := Abs(AStop - AStart);
  FPxBase := 0;
end;

procedure TTyAxis.SetLayoutExtent(ABase, ALength: Double; AVertical: Boolean);
begin
  if AVertical then FPxMap := apmY else FPxMap := apmX;
  FPxLen := ALength;
  FPxBase := ABase;
  FIdent0 := 0;
  FIdent1 := ALength;
end;

procedure TTyAxis.LocalExtent(out AStart, AStop: Double);
begin
  { upstream's updateAxisExtentTransByGridRect: inverse SWAPS the ends of
    the extent -- it is not 1 - n, which rounds differently -- and the
    extent's sum, which the y flip uses, is the same either way. }
  if FInverse then
  begin
    AStart := FIdent1;
    AStop := FIdent0;
  end
  else
  begin
    AStart := FIdent0;
    AStop := FIdent1;
  end;
end;

procedure TTyAxis.BandExtent(out AStart, AStop: Double);
var
  size, m: Double;
  n: Integer;
begin
  LocalExtent(AStart, AStop);
  if not FOnBand then Exit;
  n := 0;
  if FScale is TTyOrdinalScale then n := TTyOrdinalScale(FScale).Count;
  if n <= 0 then Exit;
  { SIGNED: an inverse axis runs [w, 0], the margin comes out negative, and
    both ends still move inward. }
  size := AStop - AStart;
  m := size / n / 2;
  AStart := AStart + m;
  AStop := AStop - m;
end;

function TTyAxis.ToGlobal(ALocal: Double): Double;
begin
  case FPxMap of
    apmX: Result := ALocal + FPxBase;
    { (e0 + e1) - c + base, in that order: upstream's toGlobalCoord }
    apmY: Result := (FIdent0 + FIdent1) - ALocal + FPxBase;
  else
    Result := ALocal;
  end;
end;

function TTyAxis.ToLocal(AGlobal: Double): Double;
begin
  case FPxMap of
    apmX: Result := AGlobal - FPxBase;
    { upstream's toLocalCoord on y is the same expression as toGlobalCoord }
    apmY: Result := (FIdent0 + FIdent1) - AGlobal + FPxBase;
  else
    Result := AGlobal;
  end;
end;

function TTyAxis.GetPxStart: Double;
begin
  if FPxMap = apmIdentity then Result := FIdent0
  else Result := ToGlobal(FIdent0);
end;

function TTyAxis.GetPxStop: Double;
begin
  if FPxMap = apmIdentity then Result := FIdent1
  else Result := ToGlobal(FIdent1);
end;

function TTyAxis.GetPxLength: Double;
begin
  Result := FPxLen;
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
  pxSpan := FPxLen;
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
begin
  if PxStop = PxStart then Exit(0.5);
  Result := (DataToCoord(AValue) - PxStart) / (PxStop - PxStart);
end;

{ The Level-0 members of a tick array, in order. }
function TyMajorTicks(const ATicks: TTyScaleTickArray): TTyScaleTickArray;
var i, n: Integer;
begin
  SetLength(Result, Length(ATicks));
  n := 0;
  for i := 0 to High(ATicks) do
    if ATicks[i].Level = 0 then
    begin
      Result[n] := ATicks[i];
      Inc(n);
    end;
  SetLength(Result, n);
end;

function TTyAxis.TickCoords(AAlignWithLabel: Boolean): TTyDoubleArray;
var
  ticks: TTyScaleTickArray;
  i, n: Integer;
  bw, dir: Double;
begin
  { MAJORS ONLY. GetTicks hands majors and minors back in ONE array with Level
    saying which is which, and everything that reads this function -- the tick
    marks, the split lines, the split-area band edges -- is asking about
    majors. Taking the array whole meant `minorTick: { show: true }` drew the
    minor grid a second time in the MAJOR style, and put a full-length tick
    mark at every subdivision. The minor painters ask FScale.GetTicks
    themselves and test Level the other way round. }
  ticks := TyMajorTicks(TyDrawnTicks(FScale));
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
  if PxStop >= PxStart then dir := 1 else dir := -1;
  if FInverse then dir := -dir;
  SetLength(Result, n + 1);
  for i := 0 to n - 1 do
    Result[i] := DataToCoord(ticks[i].Value) - dir * bw / 2;
  Result[n] := Result[n - 1] + dir * bw;
end;

function TTyAxis.DataToLocal(AValue: Double; AClamp: Boolean): Double;
var
  n, r0, r1: Double;
  e: TTyRange;
begin
  if IsNan(AValue) then
  begin
    { A GAP ON AN AXIS OF NO LENGTH lands in its middle: upstream's normalize
      answers 0.5 for a flat extent before it looks at the value }
    e := FScale.GetExtent2(sekMapping);
    if not (IsNan(e.Start) or IsNan(e.Stop)) and (e.Start = e.Stop) then
      n := 0.5
    else
      Exit(NaN);
    BandExtent(r0, r1);
    Exit((n - 0) / 1 * (r1 - r0) + r0);
  end;
  { THE SCALE'S parse FIRST: a time scale rounds to the millisecond, the way
    Math.round does. It matters at the ends of a mapping extent, which half a
    bar can leave fractional. }
  if FScale is TTyTimeScale then AValue := TyJsRound(AValue)
  { an ordinal one to a whole category, as Ordinal.parse rounds a number }
  else if FScale is TTyOrdinalScale then AValue := TyJsRound(AValue);
  n := FScale.Normalize(AValue);
  if IsNan(n) then
    Exit(NaN);
  BandExtent(r0, r1);
  { linearMap(n, [0, 1], [r0, r1]): an end comes back as itself, not as the
    arithmetic that would nearly reach it }
  if AClamp then
  begin
    if n <= 0 then Exit(r0);
    if n >= 1 then Exit(r1);
  end
  else
  begin
    if n = 0 then Exit(r0);
    if n = 1 then Exit(r1);
  end;
  { AN INFINITY ONTO NO LENGTH is not-a-number, as JavaScript's
    Infinity * 0 is; FPC raises on it instead }
  if IsInfinite(n) and (r1 - r0 = 0) then Exit(NaN);
  Result := (n - 0) / 1 * (r1 - r0) + r0;
end;

function TTyAxis.DataToCoord(AValue: Double; AClamp: Boolean): Double;
begin
  Result := ToGlobal(DataToLocal(AValue, AClamp));
end;

function TTyAxis.CoordToData(ACoord: Double): Double;
var c, r0, r1, sub, t: Double;
begin
  if IsNan(ACoord) then
    Exit(NaN);
  c := ToLocal(ACoord);
  BandExtent(r0, r1);
  { linearMap(c, [r0, r1], [0, 1]): no length is the middle, and an end
    comes back as itself }
  sub := r1 - r0;
  if sub = 0 then
    t := (0 + 1) / 2
  else if c = r0 then t := 0
  else if c = r1 then t := 1
  else
    t := (c - r0) / sub * 1 + 0;
  Result := FScale.Denormalize(t);
end;

{ ============================ TTyCartesian2D ============================ }

constructor TTyCartesian2D.Create;
begin
  inherited Create;
  FAxes := nil;
  FXYWH := TyXYWH(0, 0, 1, 1);
  FRect := TyRectOfXYWH(FXYWH);
  FHasTransform := False;
  FHasInvTransform := False;
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
  SetRectXYWH(TyXYWHOfRect(ARect));
end;

procedure TTyCartesian2D.SetRectXYWH(const ARect: TTyXYWH);
begin
  FXYWH := ARect;
  FRect := TyRectOfXYWH(ARect);
  FHasTransform := False;
  FHasInvTransform := False;
  ReflowAxes;
end;

function TTyCartesian2D.GetXYWH: TTyXYWH;
begin
  Result := FXYWH;
end;

function CanAffine(AAxis: TTyAxis): Boolean;
begin
  { upstream's canCalculateAffineTransform: an interval or a time scale --
    not log, not ordinal. (Breaks too, which nothing here builds yet.) }
  Result := (AAxis <> nil) and (AAxis.AxisType in [atValue, atTime])
    and (AAxis.Scale is TTyIntervalScale);
end;

procedure TTyCartesian2D.CalcAffineTransform;
var
  ax, ay: TTyAxis;
  xe, ye: TTyRange;
  s0x, s0y, e1x, e1y, xSpan, ySpan, scaleX, scaleY, det: Double;
  m: TTyMat2D;
begin
  FHasTransform := False;
  FHasInvTransform := False;
  ax := MasterX;
  ay := MasterY;
  if not (CanAffine(ax) and CanAffine(ay)) then Exit;
  xe := ax.Scale.GetExtent2(sekMapping);
  ye := ay.Scale.GetExtent2(sekMapping);
  { per axis, with the matrix not yet there -- so a time end is rounded to
    the millisecond first, as upstream's dataToPoint rounds it }
  s0x := ax.DataToCoord(xe.Start);
  s0y := ay.DataToCoord(ye.Start);
  e1x := ax.DataToCoord(xe.Stop);
  e1y := ay.DataToCoord(ye.Stop);
  xSpan := xe.Stop - xe.Start;
  ySpan := ye.Stop - ye.Start;
  { `!span`: nought and not-a-number alike }
  if IsNan(xSpan) or IsNan(ySpan) or (xSpan = 0) or (ySpan = 0) then Exit;
  scaleX := (e1x - s0x) / xSpan;
  scaleY := (e1y - s0y) / ySpan;
  m[0] := scaleX;
  m[1] := 0;
  m[2] := 0;
  m[3] := scaleY;
  m[4] := s0x - xe.Start * scaleX;
  m[5] := s0y - ye.Start * scaleY;
  FTransform := m;
  FHasTransform := True;
  { zrender's invert, term for term }
  det := m[0] * m[3] - m[1] * m[2];
  if IsNan(det) or (det = 0) then Exit;
  det := 1.0 / det;
  FInvTransform[0] := m[3] * det;
  FInvTransform[1] := -m[1] * det;
  FInvTransform[2] := -m[2] * det;
  FInvTransform[3] := m[0] * det;
  FInvTransform[4] := (m[2] * m[5] - m[3] * m[4]) * det;
  FInvTransform[5] := (m[1] * m[4] - m[0] * m[5]) * det;
  FHasInvTransform := True;
end;

function TTyCartesian2D.Transform(out AM: TTyMat2D): Boolean;
begin
  AM := FTransform;
  Result := FHasTransform;
end;

function TTyCartesian2D.InvTransform(out AM: TTyMat2D): Boolean;
begin
  AM := FInvTransform;
  Result := FHasInvTransform;
end;

function TTyCartesian2D.GetAreaTol(ATol: Double): TTyXYWH;
var
  ax, ay: TTyAxis;
  a, b, g0, g1: Double;
begin
  Result := FXYWH;
  ax := MasterX;
  ay := MasterY;
  if (ax = nil) or (ay = nil) then Exit;
  ax.LocalExtent(a, b);
  g0 := ax.ToGlobal(a);
  g1 := ax.ToGlobal(b);
  Result.X := Min(g0, g1) - ATol;
  Result.W := Max(g0, g1) - Result.X + ATol;
  ay.LocalExtent(a, b);
  g0 := ay.ToGlobal(a);
  g1 := ay.ToGlobal(b);
  Result.Y := Min(g0, g1) - ATol;
  Result.H := Max(g0, g1) - Result.Y + ATol;
end;

function TTyCartesian2D.GetArea: TTyXYWH;
var
  ax, ay: TTyAxis;
  a, b, g0, g1: Double;
begin
  Result := FXYWH;
  ax := MasterX;
  ay := MasterY;
  if (ax = nil) or (ay = nil) then Exit;
  { Cartesian2D.getArea: min of the two global ends, and max - min }
  ax.LocalExtent(a, b);
  g0 := ax.ToGlobal(a);
  g1 := ax.ToGlobal(b);
  Result.X := Min(g0, g1);
  Result.W := Max(g0, g1) - Result.X;
  ay.LocalExtent(a, b);
  g0 := ay.ToGlobal(a);
  g1 := ay.ToGlobal(b);
  Result.Y := Min(g0, g1);
  Result.H := Max(g0, g1) - Result.Y;
end;

procedure TTyCartesian2D.ReflowAxes;
var i: Integer;
begin
  { Every axis spans the whole band on its own orientation. A y axis runs from
    the BOTTOM up — this is the single place screen-vs-value direction is
    decided, and it is why nothing downstream needs to remember to flip. }
  for i := 0 to High(FAxes) do
    if FAxes[i].Horizontal then
      FAxes[i].SetLayoutExtent(FXYWH.X, FXYWH.W, False)
    else
      FAxes[i].SetLayoutExtent(FXYWH.Y, FXYWH.H, True);
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
begin
  Result := DataToPointClamped(AData, False);
end;

function TTyCartesian2D.DataToPointClamped(const AData: array of Double;
  AClamp: Boolean): TTyPointF;
var
  ax, ay: TTyAxis;
  x, y: Double;
begin
  ax := MasterX;
  ay := MasterY;
  if (ax = nil) or (ay = nil) or (Length(AData) < 2) then
    Exit(TyInvalidPointF);
  x := AData[0];
  y := AData[1];
  { THE MATRIX when there is one and both values are finite; one infinity
    or gap sends BOTH down the per-axis path, as upstream's gate does }
  if FHasTransform and not (IsNan(x) or IsInfinite(x) or IsNan(y)
    or IsInfinite(y)) then
  begin
    Result.X := FTransform[0] * x + FTransform[2] * y + FTransform[4];
    Result.Y := FTransform[1] * x + FTransform[3] * y + FTransform[5];
    Exit;
  end;
  Result.X := ax.DataToCoord(x, AClamp);
  Result.Y := ay.DataToCoord(y, AClamp);
end;

function TTyCartesian2D.DataToLayout(const AData: array of Double): TTyCoordLayout;
var
  ax, ay, spine, across, b: TTyAxis;
  p: TTyPointF;
  halfSpine, baseline, half: Double;
  sAnchor, aAnchor, sMin, sMax, aMin, aMax: Double;
  spineIsX: Boolean;
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

  { WHICH AXIS IS THE SPINE IS A QUESTION THIS CLASS ALREADY ANSWERS.
    GetBaseAxis is "the axis a series is laid out ALONG"; the other carries the
    value. This used to assume the spine was x, so a horizontal bar got a cell
    of zero width and a heatmap with categories on both axes got one running
    from the first category's centre to the datum's.

    Only the ORIENTATION comes from GetBaseAxis; the masters are then used --
    the same two axes DataToPoint just used for the anchor. Taking the axis
    object itself could hand back a sub-axis and put the cell somewhere other
    than around the point at its centre. }
  b := GetBaseAxis;
  spineIsX := (b = nil) or b.Horizontal;
  if spineIsX then
  begin
    spine := ax;
    across := ay;
    sAnchor := p.X;
    aAnchor := p.Y;
  end
  else
  begin
    spine := ay;
    across := ax;
    sAnchor := p.Y;
    aAnchor := p.X;
  end;

  { ALONG the spine: half a band either side. A continuous axis has no band, so
    the cell collapses onto the anchor rather than inventing a width. }
  if spine.BandWidth > 0 then
    halfSpine := spine.BandWidth / 2
  else
    halfSpine := 0;
  sMin := sAnchor - halfSpine;
  sMax := sAnchor + halfSpine;

  { ACROSS it, two shapes for two charts. A banded axis makes the cell one band
    there too -- that is a heatmap cell. An unbanded one runs the cell from its
    baseline to the datum -- that is a bar. }
  if across.BandWidth > 0 then
  begin
    aMin := aAnchor - across.BandWidth / 2;
    aMax := aAnchor + across.BandWidth / 2;
  end
  else
  begin
    { FROM WHERE A BAR STANDS, which is the value axis' start value and not
      its min: a -3 on an axis from -4 to 6 runs down from 0, not up from -4.
      A start the axis cannot place -- a log axis told to start at 0 -- is no
      cell at all, as upstream draws no bar there. }
    baseline := across.DataToCoord(TyValueAxisStart(across));
    if IsNan(baseline) or IsInfinite(baseline) then Exit;
    aMin := Min(aAnchor, baseline);
    aMax := Max(aAnchor, baseline);
  end;

  if spineIsX then
    Result.Rect := TyRectF(sMin, aMin, sMax, aMax)
  else
    Result.Rect := TyRectF(aMin, sMin, aMax, sMax);
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
  if FHasInvTransform then
  begin
    AData[0] := FInvTransform[0] * APoint.X + FInvTransform[2] * APoint.Y
      + FInvTransform[4];
    AData[1] := FInvTransform[1] * APoint.X + FInvTransform[3] * APoint.Y
      + FInvTransform[5];
    Exit(True);
  end;
  AData[0] := ax.CoordToData(APoint.X);
  AData[1] := ay.CoordToData(APoint.Y);
  Result := True;
end;

function TTyCartesian2D.ContainPoint(const APoint: TTyPointF): Boolean;
var
  ax, ay: TTyAxis;
  a, b, l: Double;
begin
  ax := MasterX;
  ay := MasterY;
  if (ax = nil) or (ay = nil) then
    Exit((APoint.X >= FRect.Left) and (APoint.X <= FRect.Right)
      and (APoint.Y >= FRect.Top) and (APoint.Y <= FRect.Bottom));
  { upstream's containPoint: each axis takes the point into its own frame
    and asks whether it falls in [0, w], both ends included }
  ax.LocalExtent(a, b);
  l := ax.ToLocal(APoint.X);
  Result := (l >= Min(a, b)) and (l <= Max(a, b));
  if not Result then Exit;
  ay.LocalExtent(a, b);
  l := ay.ToLocal(APoint.Y);
  Result := (l >= Min(a, b)) and (l <= Max(a, b));
end;

end.
