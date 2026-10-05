unit tyControls.AdvChart.Jitter;
{$mode objfpc}{$H+}
{ The scatter's jitter (beeswarm) -- upstream's util/jitter.ts and
  chart/scatter/jitterLayout.ts. [Batch 110, C2]

  WHO IS JITTERED. A scatter (not an effectScatter) on a cartesian whose
  base axis is a category axis with `jitter > 0`: every row, in series
  order and then row order, its coordinate ALONG that axis moved and the
  other one fixed -- x on a category x, y on a category y. Every row, the
  ones that will not be drawn too: a row with a gap still has a layout, and
  is jittered (and draws a random number) like the others.

  HOW. `jitterOverlap: true` (the default): the coordinate plus
  (random - 0.5) * min(max(0, jitter), band - 2r). `jitterOverlap: false`:
  placed beside the points already on the axis -- each direction in turn,
  climbing past every circle (r + its r + jitterMargin) it would overlap
  and starting over, giving up past jitter / 2 -- the smaller move of the
  two; and when even that is further than jitter / 2, or than half the band
  less r, a random placement as above, which is not remembered. The radius
  is half the symbol size (the mean of a [w, h] pair). The placed points
  are the AXIS'S, shared by every series on it.

  THE RANDOM NUMBERS. Upstream draws from Math.random, so no two renders
  agree. Here they come from the xorshift32 the force layout uses
  (TyGraphRandom), seeded with TyJitterSeed at the start of every pass: a
  repaint gives the same picture, and tools/advchart-oracle/convert-jitter.js
  hands upstream these same numbers, which is what holds the port to its
  output.

  A PASS STARTS FROM NOTHING. Upstream keeps the placed points on the axis
  object, which a resize keeps -- so its second layout avoids the first
  one's points and the swarm spreads with every resize. Here every pass
  starts with no points.

  PURE: SysUtils and Math. }
interface
uses SysUtils, Math;

const
  { TyGraphForceSeed(0): the oracle's seed }
  TyJitterSeed: LongWord = 2463534242;

type
  TTyJitterItem = record
    Fixed, Float, R: Double;
  end;

  TTyJitterPass = class;

  { One category axis' jitter for one pass: its options, its band, and the
    points placed on it so far. }
  TTyJitterAxis = class
  private
    FPass: TTyJitterPass;
    FItems: array of TTyJitterItem;
    FCount: Integer;
  public
    Key: string;
    Jitter: Double;
    Margin: Double;
    Overlap: Boolean;
    Band: Double;
    { fixJitter: AFloat moved, AFixed where it is }
    function Fix(AFixed, AFloat, ARadius: Double): Double;
    function Count: Integer;
    function Item(AIndex: Integer): TTyJitterItem;
  end;

  { The random state and every axis' points, for one pass. }
  TTyJitterPass = class
  private
    FState: LongWord;
    FAxes: array of TTyJitterAxis;
  public
    constructor Create;
    destructor Destroy; override;
    { a new pass: the seed again, no axes }
    procedure Reset;
    function Random: Double;
    { the axis under AKey, made with these options the first time }
    function AxisFor(const AKey: string; AJitter, AMargin: Double;
      AOverlap: Boolean; ABand: Double): TTyJitterAxis;
    property State: LongWord read FState write FState;
  end;

{ the xorshift32 step: TyGraphRandom's, a new state and x / 2^32 }
function TyJitterRandom(var AState: LongWord): Double;
{ fixJitterIgnoreOverlaps on a category axis }
function TyJitterIgnoreOverlaps(AFloat, AJitter, ABand, ARadius: Double;
  var AState: LongWord): Double;
{ placeJitterOnDirection over the first ACount of AItems }
function TyJitterPlace(const AItems: array of TTyJitterItem; ACount: Integer;
  AFixed, AFloat, ARadius, AJitter, AMargin: Double; ADir: Integer): Double;

implementation

const
  cTwo32: Double = 4294967296.0;
  cMaxValue: Double = 1.7976931348623157e308;

function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  { the SSE flags too: ClearExceptions clears the x87 status word only, and
    a sticky invalid-operation flag would be reported by the next trap }
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

{ JavaScript's < and >: false when either side is not a number }
function Lt(A, B: Double): Boolean; inline;
begin
  Result := not (IsNan(A) or IsNan(B)) and (A < B);
end;

function Gt(A, B: Double): Boolean; inline;
begin
  Result := not (IsNan(A) or IsNan(B)) and (A > B);
end;

function TyJitterRandom(var AState: LongWord): Double;
var x: LongWord;
begin
  {$push}{$R-}{$Q-}
  x := AState;
  x := x xor LongWord(x shl 13);
  x := x xor (x shr 17);
  x := x xor LongWord(x shl 5);
  {$pop}
  AState := x;
  Result := x / cTwo32;
end;

function TyJitterIgnoreOverlaps(AFloat, AJitter, ABand, ARadius: Double;
  var AState: LongWord): Double;
var
  maxJitter, actual: Double;
begin
  { Math.min(Math.max(0, jitter), band - 2r): a not-a-number either side is
    one, as Math.min and Math.max answer }
  maxJitter := ABand - ARadius * 2;
  if IsNan(AJitter) then actual := NaN
  else actual := Max(0, AJitter);
  if IsNan(actual) or IsNan(maxJitter) then actual := NaN
  else if maxJitter < actual then actual := maxJitter;
  Result := AFloat + (TyJitterRandom(AState) - 0.5) * actual;
end;

function TyJitterPlace(const AItems: array of TTyJitterItem; ACount: Integer;
  AFixed, AFloat, ARadius, AJitter, AMargin: Double; ADir: Integer): Double;
var
  i: Integer;
  dx, dy, d2, r, required: Double;
begin
  Result := AFloat;
  i := 0;
  while i < ACount do
  begin
    dx := AFixed - AItems[i].Fixed;
    dy := Result - AItems[i].Float;
    d2 := dx * dx + dy * dy;
    r := ARadius + AItems[i].R + AMargin;
    if Lt(d2, r * r) then
    begin
      required := AItems[i].Float + Sqrt(r * r - dx * dx) * ADir;
      { further than half the jitter: give up }
      if Gt(Abs(required - AFloat), AJitter / 2) then Exit(cMaxValue);
      { only ever further out, and then every item again }
      if ((ADir = 1) and Gt(required, Result))
        or ((ADir = -1) and Lt(required, Result)) then
      begin
        Result := required;
        i := 0;
        Continue;
      end;
    end;
    Inc(i);
  end;
end;

{ ==================== TTyJitterAxis ==================== }

function TTyJitterAxis.Count: Integer;
begin
  Result := FCount;
end;

function TTyJitterAxis.Item(AIndex: Integer): TTyJitterItem;
begin
  Result := FItems[AIndex];
end;

function TTyJitterAxis.Fix(AFixed, AFloat, ARadius: Double): Double;
var
  a, b, minFloat, distance: Double;
  state: LongWord;
  mask: TFPUExceptionMask;
begin
  { jitter > 0, as a number: anything else leaves the point alone }
  if not Gt(Jitter, 0) then Exit(AFloat);
  mask := MaskFP;
  try
    state := FPass.FState;
    try
      if Overlap then
        Exit(TyJitterIgnoreOverlaps(AFloat, Jitter, Band, ARadius, state));
      a := TyJitterPlace(FItems, FCount, AFixed, AFloat, ARadius, Jitter, Margin, 1);
      b := TyJitterPlace(FItems, FCount, AFixed, AFloat, ARadius, Jitter, Margin, -1);
      if Lt(Abs(a - AFloat), Abs(b - AFloat)) then minFloat := a else minFloat := b;
      distance := Abs(minFloat - AFloat);
      { too far: a random placement, not remembered. `bandWidth &&`: a band
        of nought (or not a number) asks nothing }
      if Gt(distance, Jitter / 2)
        or ((Band <> 0) and not IsNan(Band) and Gt(distance, Band / 2 - ARadius)) then
        Exit(TyJitterIgnoreOverlaps(AFloat, Jitter, Band, ARadius, state));
      if FCount >= Length(FItems) then
        SetLength(FItems, Max(16, 2 * Length(FItems)));
      FItems[FCount].Fixed := AFixed;
      FItems[FCount].Float := minFloat;
      FItems[FCount].R := ARadius;
      Inc(FCount);
      Result := minFloat;
    finally
      FPass.FState := state;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

{ ==================== TTyJitterPass ==================== }

constructor TTyJitterPass.Create;
begin
  inherited Create;
  FState := TyJitterSeed;
  FAxes := nil;
end;

destructor TTyJitterPass.Destroy;
begin
  Reset;
  inherited Destroy;
end;

procedure TTyJitterPass.Reset;
var i: Integer;
begin
  for i := 0 to High(FAxes) do FAxes[i].Free;
  FAxes := nil;
  FState := TyJitterSeed;
end;

function TTyJitterPass.Random: Double;
begin
  Result := TyJitterRandom(FState);
end;

function TTyJitterPass.AxisFor(const AKey: string; AJitter, AMargin: Double;
  AOverlap: Boolean; ABand: Double): TTyJitterAxis;
var i: Integer;
begin
  for i := 0 to High(FAxes) do
    if FAxes[i].Key = AKey then Exit(FAxes[i]);
  Result := TTyJitterAxis.Create;
  Result.FPass := Self;
  Result.Key := AKey;
  Result.Jitter := AJitter;
  Result.Margin := AMargin;
  Result.Overlap := AOverlap;
  Result.Band := ABand;
  SetLength(FAxes, Length(FAxes) + 1);
  FAxes[High(FAxes)] := Result;
end;

end.
