unit tyControls.AdvChart.Coord;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the coordinate-system layer.

  CONTRACT 1 (see docs/superpowers/specs/2026-09-01-advancechart-tier0.md §2).
  Every coordinate system answers a datum TWO ways:

    DataToPoint  -> the datum's ANCHOR (a line vertex, a scatter centre)
    DataToLayout -> the datum's CELL, as {Rect, ContentRect}

  DataToLayout is what nesting rests on: a nested coordinate system, or a
  component laid out with coordinateSystemUsage:'box', is placed into the
  ContentRect its host returns for one datum. In ECharts this method is OPTIONAL
  and Cartesian2D does not implement it, which is why HeatmapView.ts:250-285 has
  to branch three ways (cartesian computes its own width/height, matrix reads
  .rect, calendar reads .contentRect). Here it is REQUIRED and cartesian
  implements it, so that branch collapses to one path.

  N AXES, not two. A secondary y axis is the commonest real-world request; making
  it a special case later is how a coordinate system ends up rewritten.

  PURE: SysUtils, Math and the two AdvChart units. No Controls, no Graphics, no
  handle. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Scale;

type
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
    FBandWidth: Double;
    FInverse: Boolean;
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
    { The width of one datum's band, px. 0 means "not banded" (a continuous
      axis), and a cell then collapses to a hairline on the anchor rather than
      inventing a width. }
    property BandWidth: Double read FBandWidth write FBandWidth;
    property Inverse: Boolean read FInverse write FInverse;
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
    function MasterX: TTyAxis;
    function MasterY: TTyAxis;
    procedure ReflowAxes;
  public
    constructor Create;
    destructor Destroy; override;
    { Takes ownership. }
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
    { Half of this comes off each side of a cell to give its ContentRect. }
    property DividerWidth: Double read FDividerWidth write FDividerWidth;
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
  FBandWidth := 0;
  FInverse := False;
end;

destructor TTyAxis.Destroy;
begin
  FScale.Free;
  inherited Destroy;
end;

procedure TTyAxis.SetPxExtent(AStart, AStop: Double);
begin
  FPxStart := AStart;
  FPxStop := AStop;
end;

function TTyAxis.DataToCoord(AValue: Double): Double;
var n: Double;
begin
  if IsNan(AValue) then
    Exit(NaN);
  n := FScale.Normalize(AValue);
  if FInverse then
    n := 1 - n;
  Result := FPxStart + n * (FPxStop - FPxStart);
end;

function TTyAxis.CoordToData(ACoord: Double): Double;
var n, span: Double;
begin
  span := FPxStop - FPxStart;
  if span = 0 then
    Exit(FScale.GetExtent.Start);
  n := (ACoord - FPxStart) / span;
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
end;

destructor TTyCartesian2D.Destroy;
var i: Integer;
begin
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
