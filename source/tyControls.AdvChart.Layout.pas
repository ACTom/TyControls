unit tyControls.AdvChart.Layout;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the box layout solver.

  CONTRACT 1, second half (see the Tier 0 spec §2). The solver takes an
  ITyBoxContainer, never a rect. Two implementations ship here:

    TyFixedContainer     — a literal rect (the control's client area, top level)
    TyCoordCellContainer — one datum's cell in another coordinate system, which
                           is coordinateSystemUsage:'box' in its smallest form

  Both go through the SAME TySolveBox. Had a component been written against "the
  control's client rect", nesting it later would be a rewrite; written against a
  provider, nesting is a different argument.

  The provider is an INTERFACE rather than a rect parameter because when nesting,
  the container is not known until the HOST has been laid out — the value has to
  be fetched late, not passed early.

  PURE: SysUtils, Math and the AdvChart units. No Controls, no Graphics, no
  handle. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Coord;

type
  { How one edge or size is expressed. }
  TTyBoxUnit = (buAuto, buPx, buPercent, buCentre);

  TTyBoxValue = record
    Kind: TTyBoxUnit;
    Value: Double;
  end;

  { left/top/right/bottom/width/height, each optional. Redundant constraints are
    resolved by PRECEDENCE, never by an error: on each axis (start, size) wins
    over (start, end) wins over (end, size). ECharts resolves the same way. }
  TTyBoxSpec = record
    Left, Top, Right, Bottom, Width, Height: TTyBoxValue;
  end;

  ITyBoxContainer = interface
    ['{8D31C60F-4A72-4B95-BE28-3F7A05D6C914}']
    function ContainerRect: TTyRectF;
  end;

function TyBoxSpec: TTyBoxSpec;              { every field buAuto }
function TyBoxPx(AValue: Double): TTyBoxValue;
function TyBoxPercent(AValue: Double): TTyBoxValue;
function TyBoxCentre: TTyBoxValue;
function TyBoxAuto: TTyBoxValue;

function TyFixedContainer(const ARect: TTyRectF): ITyBoxContainer;
function TyCoordCellContainer(const ACoordSys: ITyCoordSys;
  const AData: array of Double): ITyBoxContainer;

{ The one solver. Every component's rect comes from here. }
function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer): TTyRectF;

implementation

type
  TTyFixedContainer = class(TInterfacedObject, ITyBoxContainer)
  private
    FRect: TTyRectF;
  public
    constructor Create(const ARect: TTyRectF);
    function ContainerRect: TTyRectF;
  end;

  TTyCoordCellContainer = class(TInterfacedObject, ITyBoxContainer)
  private
    FCoordSys: ITyCoordSys;
    FData: TTyDoubleArray;
  public
    constructor Create(const ACoordSys: ITyCoordSys; const AData: array of Double);
    function ContainerRect: TTyRectF;
  end;

function TyBoxAuto: TTyBoxValue;
begin
  Result.Kind := buAuto;
  Result.Value := 0;
end;

function TyBoxSpec: TTyBoxSpec;
begin
  Result.Left := TyBoxAuto;
  Result.Top := TyBoxAuto;
  Result.Right := TyBoxAuto;
  Result.Bottom := TyBoxAuto;
  Result.Width := TyBoxAuto;
  Result.Height := TyBoxAuto;
end;

function TyBoxPx(AValue: Double): TTyBoxValue;
begin
  Result.Kind := buPx;
  Result.Value := AValue;
end;

function TyBoxPercent(AValue: Double): TTyBoxValue;
begin
  Result.Kind := buPercent;
  Result.Value := AValue;
end;

function TyBoxCentre: TTyBoxValue;
begin
  Result.Kind := buCentre;
  Result.Value := 0;
end;

{ Resolve one value against a container extent. Returns NaN for buAuto (and for
  buCentre, which the caller handles first) so "not specified" stays
  distinguishable from "specified as zero" — the distinction the whole
  precedence table below rests on. }
function ResolveValue(const AV: TTyBoxValue; AExtent: Double): Double;
begin
  case AV.Kind of
    buPx: Result := AV.Value;
    buPercent: Result := AV.Value / 100 * AExtent;
  else
    Result := NaN;
  end;
end;

{ Solve one axis. AStartV/AEndV are the near/far insets, ASizeV the extent. }
procedure SolveAxis(const AStartV, AEndV, ASizeV: TTyBoxValue;
  AContainerStart, AContainerExtent: Double; out AStart, AStop: Double);
var
  s, e, sz: Double;
begin
  s := ResolveValue(AStartV, AContainerExtent);
  e := ResolveValue(AEndV, AContainerExtent);
  sz := ResolveValue(ASizeV, AContainerExtent);

  if AStartV.Kind = buCentre then
  begin
    { Centre needs a size to centre. Without one it degenerates to the whole
      container, which is the only answer that is not a guess. }
    if IsNan(sz) then
    begin
      AStart := AContainerStart;
      AStop := AContainerStart + AContainerExtent;
      Exit;
    end;
    AStart := AContainerStart + (AContainerExtent - sz) / 2;
    AStop := AStart + sz;
    Exit;
  end;

  if (not IsNan(s)) and (not IsNan(sz)) then          { start + size }
  begin
    AStart := AContainerStart + s;
    AStop := AStart + sz;
  end
  else if (not IsNan(s)) and (not IsNan(e)) then      { start + end }
  begin
    AStart := AContainerStart + s;
    AStop := AContainerStart + AContainerExtent - e;
  end
  else if (not IsNan(e)) and (not IsNan(sz)) then     { end + size }
  begin
    AStop := AContainerStart + AContainerExtent - e;
    AStart := AStop - sz;
  end
  else if not IsNan(s) then                           { start only -> to the far edge }
  begin
    AStart := AContainerStart + s;
    AStop := AContainerStart + AContainerExtent;
  end
  else if not IsNan(e) then                           { end only -> from the near edge }
  begin
    AStart := AContainerStart;
    AStop := AContainerStart + AContainerExtent - e;
  end
  else if not IsNan(sz) then                          { size only -> at the near edge }
  begin
    AStart := AContainerStart;
    AStop := AStart + sz;
  end
  else                                                { nothing -> fill }
  begin
    AStart := AContainerStart;
    AStop := AContainerStart + AContainerExtent;
  end;

  { Over-constrained: collapse to zero at the near edge rather than invert. An
    inverted rect survives a later Min/Max swap and reappears as a phantom band
    somewhere else on screen, which is far harder to find than an empty one. }
  if AStop < AStart then
    AStop := AStart;
end;

function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer): TTyRectF;
var
  c: TTyRectF;
  l, r, t, b: Double;
begin
  if AContainer = nil then
    Exit(TyInvalidRectF);
  c := AContainer.ContainerRect;
  if not TyRectFIsValid(c) then
    Exit(TyInvalidRectF);
  SolveAxis(ASpec.Left, ASpec.Right, ASpec.Width, c.Left, TyRectFWidth(c), l, r);
  SolveAxis(ASpec.Top, ASpec.Bottom, ASpec.Height, c.Top, TyRectFHeight(c), t, b);
  Result := TyRectF(l, t, r, b);
end;

{ ============================ containers ============================ }

constructor TTyFixedContainer.Create(const ARect: TTyRectF);
begin
  inherited Create;
  FRect := ARect;
end;

function TTyFixedContainer.ContainerRect: TTyRectF;
begin
  Result := FRect;
end;

constructor TTyCoordCellContainer.Create(const ACoordSys: ITyCoordSys;
  const AData: array of Double);
var i: Integer;
begin
  inherited Create;
  FCoordSys := ACoordSys;
  SetLength(FData, Length(AData));
  for i := 0 to High(AData) do
    FData[i] := AData[i];
end;

function TTyCoordCellContainer.ContainerRect: TTyRectF;
var l: TTyCoordLayout;
begin
  if FCoordSys = nil then
    Exit(TyInvalidRectF);
  l := FCoordSys.DataToLayout(FData);
  { ContentRect, not Rect — a nested thing must not paint over the host's
    divider. Same choice HeatmapView.ts:279 makes. }
  Result := l.ContentRect;
end;

function TyFixedContainer(const ARect: TTyRectF): ITyBoxContainer;
begin
  Result := TTyFixedContainer.Create(ARect);
end;

function TyCoordCellContainer(const ACoordSys: ITyCoordSys;
  const AData: array of Double): ITyBoxContainer;
begin
  Result := TTyCoordCellContainer.Create(ACoordSys, AData);
end;

end.
