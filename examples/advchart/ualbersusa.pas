unit ualbersusa;

{$mode objfpc}{$H+}

{ D3'S geoAlbersUsa, IN PASCAL -- the projection map-usa-projection draws its
  map with.

  The gallery page loads d3-geo 2.0.1 from a CDN and hands ECharts
  `projection: {project: p => projection(p), unproject: p =>
  projection.invert(p)}` over `d3.geoAlbersUsa()`. The harvest names the two
  functions '@map-usa-projection.project' / '.unproject'; this unit is a
  transcription of the d3-geo code they run, registered under those names
  with TyChartRegisterGeoProjection (RegisterAlbersUsa).

  WHAT IS TRANSCRIBED. The composite with its defaults (scale 1070,
  translate [480, 250]): the lower 48 states (albers: conicEqualArea,
  parallels 29.5 / 45.5, rotate [96, 0], center [-0.6, 38.7]), Alaska
  (scale x 0.35, rotate [154, 0], center [-2, 58.5], parallels 55 / 65) and
  Hawaii (rotate [157, 0], center [-3, 19.9], parallels 8 / 18), each with
  its clip extent around its inset; a point goes to the first whose extent
  takes it, and none is null. The point path of a d3 projection stream --
  degrees to radians, the rotation, the antimeridian pre-clip (which passes
  a lone point), the projection with the scale and translate (projectResample
  projects a lone point once), the rectangle post-clip -- and invert by the
  same regions albersUsa.invert picks by. Operation for operation, with
  JavaScript's own trigonometry (TyJsSin, TyJsCos, TyJsAtan2, TyJsAsin), so
  the points come out as d3's to the bit (tools/advchart-oracle/
  gallery-projection.js holds them to it).

  NOT TRANSCRIBED: the stream for lines and polygons (resampling, clipping),
  the fit* methods and the setters -- the page uses none of them; ECharts
  projects a map point by point when a projection has no `stream`.

  Copyright 2010-2016 Mike Bostock; d3-geo is under the BSD 3-Clause licence
  (THIRD-PARTY-NOTICES.md). }

interface

uses
  SysUtils, Math;

type
  { one conicEqualArea projection with its settings, as d3's
    projectionMutator holds them }
  TConicEqualArea = class
  private
    { conicEqualAreaRaw(phi0, phi1) }
    FN, FC, FR0: Double;
    { scale, translate, the transform's offsets, the rotation }
    FK, FX, FY, FDx, FDy, FDLambda: Double;
    FHasClip: Boolean;
    FX0, FY0, FX1, FY1: Double;
    procedure Raw(AX, AY: Double; out ARX, ARY: Double);
    procedure RawInvert(AX, AY: Double; out ARX, ARY: Double);
  public
    { rotate [ARotate, 0], center [ACenterLon, ACenterLat], parallels,
      scale, translate -- recentred once, with every value final }
    constructor Create(ARotate, ACenterLon, ACenterLat, APar0, APar1,
      AScale, ATX, ATY: Double);
    procedure SetClip(AX0, AY0, AX1, AY1: Double);
    { the point stream: False where the post-clip drops the point }
    function Project(ALon, ALat: Double; out AX, AY: Double): Boolean;
    function Invert(AX, AY: Double; out ALon, ALat: Double): Boolean;
    property Scale: Double read FK;
  end;

  TAlbersUsa = class
  private
    FLower48, FAlaska, FHawaii: TConicEqualArea;
  public
    constructor Create;
    destructor Destroy; override;
    { albersUsa(coordinates): null as False }
    function Project(AX, AY: Double; out ARX, ARY: Double): Boolean;
    { albersUsa.invert(coordinates) }
    function Unproject(AX, AY: Double; out ARX, ARY: Double): Boolean;
  end;

{ Register the page's two handlers: '@map-usa-projection.project' and
  '@map-usa-projection.unproject'. }
procedure RegisterAlbersUsa;
{ the projection itself, for a test }
function AlbersUsa: TAlbersUsa;

implementation

uses
  tyControls.AdvanceChart.JsMath, tyControls.AdvanceChart.Scale, tyControls.AdvanceChart.Geo;

const
  cPi: Double = Pi;
  { d3's math.js }
  cEpsilon: Double = 1e-6;
  c455: Double = 0.455;
  c238: Double = 0.238;
  c307: Double = 0.307;
  c201: Double = 0.201;
  c425: Double = 0.425;
  c120: Double = 0.120;
  c214: Double = 0.214;
  c234: Double = 0.234;
  c205: Double = 0.205;
  c212: Double = 0.212;
  c166: Double = 0.166;
  c115: Double = 0.115;
  c035: Double = 0.35;

var
  GRadians, GDegrees, GTau: Double;
  GAlbers: TAlbersUsa = nil;

{ Math.sign }
function JsSign(A: Double): Double;
begin
  if A > 0 then Result := 1
  else if A < 0 then Result := -1
  else Result := A;
end;

{ d3's asin: clamped to the half circle }
function D3Asin(A: Double): Double;
begin
  if A > 1 then Result := cPi / 2
  else if A < -1 then Result := -(cPi / 2)
  else Result := TyJsAsin(A);
end;

{ ==================== conicEqualArea ==================== }

constructor TConicEqualArea.Create(ARotate, ACenterLon, ACenterLat, APar0,
  APar1, AScale, ATX, ATY: Double);
var
  sy0, phi0, phi1, lambda, phi, cx, cy: Double;
begin
  inherited Create;
  { parallels: _[i] * radians }
  phi0 := APar0 * GRadians;
  phi1 := APar1 * GRadians;
  sy0 := TyJsSin(phi0);
  FN := (sy0 + TyJsSin(phi1)) / 2;
  FC := 1 + sy0 * (2 * FN - sy0);
  FR0 := Sqrt(FC) / FN;
  FK := AScale;
  FX := ATX;
  FY := ATY;
  { center: _[i] % 360 * radians }
  lambda := TyJsFMod(ACenterLon, 360) * GRadians;
  phi := TyJsFMod(ACenterLat, 360) * GRadians;
  { rotate: _[0] % 360 * radians, then rotateRadians' `deltaLambda %= tau` }
  FDLambda := TyJsFMod(TyJsFMod(ARotate, 360) * GRadians, GTau);
  { recenter: center = scaleTranslate(k, 0, 0)(project(lambda, phi)) }
  Raw(lambda, phi, cx, cy);
  cx := 0 + FK * cx;
  cy := 0 - FK * cy;
  FDx := FX - cx;
  FDy := FY - cy;
end;

procedure TConicEqualArea.SetClip(AX0, AY0, AX1, AY1: Double);
begin
  FHasClip := True;
  FX0 := AX0;
  FY0 := AY0;
  FX1 := AX1;
  FY1 := AY1;
end;

{ project(x, y): r = sqrt(c - 2n sin y) / n; [r sin(x n), r0 - r cos(x n)] }
procedure TConicEqualArea.Raw(AX, AY: Double; out ARX, ARY: Double);
var r, xn: Double;
begin
  r := Sqrt(FC - 2 * FN * TyJsSin(AY)) / FN;
  xn := AX * FN;
  ARX := r * TyJsSin(xn);
  ARY := FR0 - r * TyJsCos(xn);
end;

procedure TConicEqualArea.RawInvert(AX, AY: Double; out ARX, ARY: Double);
var r0y, l: Double;
begin
  r0y := FR0 - AY;
  l := TyJsAtan2(AX, Abs(r0y)) * JsSign(r0y);
  if r0y * FN < 0 then
    l := l - cPi * JsSign(AX) * JsSign(r0y);
  ARX := l / FN;
  ARY := D3Asin((FC - (AX * AX + r0y * r0y) * FN * FN) / (2 * FN));
end;

function TConicEqualArea.Project(ALon, ALat: Double; out AX, AY: Double): Boolean;
var lambda, phi, x, y: Double;
begin
  { transformRadians }
  lambda := ALon * GRadians;
  phi := ALat * GRadians;
  { the rotation: rotationLambda(deltaLambda) }
  if FDLambda <> 0 then
  begin
    lambda := lambda + FDLambda;
    if lambda > cPi then lambda := lambda - GTau
    else if lambda < -cPi then lambda := lambda + GTau;
  end
  else if Abs(lambda) > cPi then
    { rotationIdentity }
    lambda := lambda + TyJsRound(-lambda / GTau) * GTau;
  { the antimeridian pre-clip passes a lone point; the projection and the
    transform: [dx + k x, dy - k y] }
  Raw(lambda, phi, x, y);
  AX := FDx + FK * x;
  AY := FDy - FK * y;
  { the post-clip }
  Result := not FHasClip or ((FX0 <= AX) and (AX <= FX1) and (FY0 <= AY) and (AY <= FY1));
end;

function TConicEqualArea.Invert(AX, AY: Double; out ALon, ALat: Double): Boolean;
var x, y, lambda, phi: Double;
begin
  { transform.invert: [(x - dx) / k * sx, (dy - y) / k * sy] }
  x := (AX - FDx) / FK * 1;
  y := (FDy - AY) / FK * 1;
  RawInvert(x, y, lambda, phi);
  { the rotation's invert: forwardRotationLambda(-deltaLambda) }
  if FDLambda <> 0 then
  begin
    lambda := lambda + -FDLambda;
    if lambda > cPi then lambda := lambda - GTau
    else if lambda < -cPi then lambda := lambda + GTau;
  end
  else if Abs(lambda) > cPi then
    lambda := lambda + TyJsRound(-lambda / GTau) * GTau;
  ALon := lambda * GDegrees;
  ALat := phi * GDegrees;
  Result := True;
end;

{ ==================== the composite ==================== }

constructor TAlbersUsa.Create;
var k, x, y: Double;
begin
  inherited Create;
  k := 1070;
  x := 480;
  y := 250;
  { albers(): parallels 29.5 / 45.5, scale 1070, translate [480, 250],
    rotate [96, 0], center [-0.6, 38.7] }
  FLower48 := TConicEqualArea.Create(96, -0.6, 38.7, 29.5, 45.5, k, x, y);
  FLower48.SetClip(x - c455 * k, y - c238 * k, x + c455 * k, y + c238 * k);
  FAlaska := TConicEqualArea.Create(154, -2, 58.5, 55, 65, k * c035,
    x - c307 * k, y + c201 * k);
  FAlaska.SetClip(x - c425 * k + cEpsilon, y + c120 * k + cEpsilon,
    x - c214 * k - cEpsilon, y + c234 * k - cEpsilon);
  FHawaii := TConicEqualArea.Create(157, -3, 19.9, 8, 18, k,
    x - c205 * k, y + c212 * k);
  FHawaii.SetClip(x - c214 * k + cEpsilon, y + c166 * k + cEpsilon,
    x - c115 * k - cEpsilon, y + c234 * k - cEpsilon);
end;

destructor TAlbersUsa.Destroy;
begin
  FLower48.Free;
  FAlaska.Free;
  FHawaii.Free;
  inherited Destroy;
end;

function TAlbersUsa.Project(AX, AY: Double; out ARX, ARY: Double): Boolean;
begin
  Result := FLower48.Project(AX, AY, ARX, ARY)
    or FAlaska.Project(AX, AY, ARX, ARY)
    or FHawaii.Project(AX, AY, ARX, ARY);
end;

function TAlbersUsa.Unproject(AX, AY: Double; out ARX, ARY: Double): Boolean;
var k, x, y: Double;
begin
  k := FLower48.Scale;
  x := (AX - 480) / k;
  y := (AY - 250) / k;
  if (y >= c120) and (y < c234) and (x >= -c425) and (x < -c214) then
    Result := FAlaska.Invert(AX, AY, ARX, ARY)
  else if (y >= c166) and (y < c234) and (x >= -c214) and (x < -c115) then
    Result := FHawaii.Invert(AX, AY, ARX, ARY)
  else
    Result := FLower48.Invert(AX, AY, ARX, ARY);
end;

function AlbersUsa: TAlbersUsa;
begin
  if GAlbers = nil then GAlbers := TAlbersUsa.Create;
  Result := GAlbers;
end;

procedure RegisterAlbersUsa;
begin
  TyChartRegisterGeoProjection('map-usa-projection.project', @AlbersUsa.Project);
  TyChartRegisterGeoProjection('map-usa-projection.unproject', @AlbersUsa.Unproject);
end;

initialization
  GRadians := cPi / 180;
  GDegrees := 180 / cPi;
  GTau := cPi * 2;

finalization
  FreeAndNil(GAlbers);

end.
