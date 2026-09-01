unit tyControls.AdvChart.Scale;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the scale layer.

  CONTRACT 2 (see docs/superpowers/specs/2026-09-01-advancechart-tier0.md §2).
  A scale's value->[0,1] mapping may be piecewise discontinuous. Rather than
  special-case that in every scale subclass, the mapping is delegated to an
  ITyScaleMapper whose ONLY virtual pair is

      TransformIn  : own value space -> an inner (ultimately linear) space
      TransformOut : the inverse

  Normalize/Denormalize are implemented ONCE on the base in terms of that pair.
  The consequence is that a logarithmic axis and a broken axis are the SAME
  mechanism — ECharts reaches the same conclusion in scale/scaleMapper.ts:198-201
  ("some features (such as LogScale, axis breaks) transform values from their own
  spaces into linear space"). A scale subclass never mentions breaks, and the
  break decorator never mentions Interval or Log.

  TWO EXTENTS, not one (ECharts scale/scaleMapper.ts:33-68, new in 6.1):
    sekEffective — always present. Ticks, labels, splitLine, Contain, hit-test.
    sekMapping   — present only when set. Widened outward from the effective ends
                   so a shape drawn AT an end (a bar's half width, a candlestick
                   body) stays inside the plot band. Only Normalize/Denormalize
                   and axisPointer read it.
  Getting this wrong is not a missing option, it is a different extent model:
  axis.containShape and axis.dataMin/dataMax both rest on it.

  PURE: SysUtils, Math and AdvChart.Types only. No Controls, no Graphics, no
  handle. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types;

type
  { Which extent. See the unit header. }
  TTyScaleExtentKind = (sekEffective, sekMapping);

  ITyScaleMapper = interface
    ['{6A0E4C21-7B3D-4E58-9F12-0C4A6D8B1E37}']
    { False lets a large-data traversal skip the transform calls entirely. }
    function NeedTransform: Boolean;
    function TransformIn(AValue: Double): Double;
    function TransformOut(AValue: Double): Double;
    { Value -> [0,1] over the mapping extent (or the effective one when no
      mapping extent is set). Returns 0.5 on a degenerate span — never divides. }
    function Normalize(AValue: Double): Double;
    function Denormalize(ANorm: Double): Double;
    { Against the EFFECTIVE extent, always — see the unit header. }
    function Contain(AValue: Double): Boolean;
    function GetExtent(AKind: TTyScaleExtentKind): TTyRange;
    procedure SetExtent(AKind: TTyScaleExtentKind; const ARange: TTyRange);
    function HasExtent(AKind: TTyScaleExtentKind): Boolean;
  end;

  { Holds the two extents and implements Normalize/Denormalize once. Subclasses
    override only TransformIn/TransformOut. }
  TTyScaleMapperBase = class(TInterfacedObject, ITyScaleMapper)
  private
    FExtent: array[TTyScaleExtentKind] of TTyRange;
    FHasExtent: array[TTyScaleExtentKind] of Boolean;
  protected
    { The extent Normalize works over: the mapping one when set, else effective. }
    function MappingExtent: TTyRange;
  public
    constructor Create;
    function NeedTransform: Boolean; virtual;
    function TransformIn(AValue: Double): Double; virtual;
    function TransformOut(AValue: Double): Double; virtual;
    function Normalize(AValue: Double): Double; virtual;
    function Denormalize(ANorm: Double): Double; virtual;
    function Contain(AValue: Double): Boolean; virtual;
    function GetExtent(AKind: TTyScaleExtentKind): TTyRange; virtual;
    procedure SetExtent(AKind: TTyScaleExtentKind; const ARange: TTyRange); virtual;
    function HasExtent(AKind: TTyScaleExtentKind): Boolean; virtual;
  end;

  { Identity. NeedTransform is False so the large-data fast path skips the calls. }
  TTyLinearScaleMapper = class(TTyScaleMapperBase)
  public
    function NeedTransform: Boolean; override;
  end;

  { Logarithmic. Non-positive values have no image and map to NaN — excluding
    them is the data layer's job, which is exactly what ECharts 6.1 started doing
    automatically ("automatically exclude non-positive series data values on log
    axis", changelog v6.1.0). }
  TTyLogScaleMapper = class(TTyScaleMapperBase)
  private
    FBase: Double;
    FLnBase: Double;
  public
    constructor Create(ABase: Double);
    function NeedTransform: Boolean; override;
    function TransformIn(AValue: Double): Double; override;
    function TransformOut(AValue: Double): Double; override;
    property Base: Double read FBase;
  end;

  { One axis break: a value range collapsed to a small visual gap.
    Gap is a FRACTION of the visual span (0..1), not px — so a break survives a
    resize without re-solving, and two breaks cannot together exceed the axis. }
  TTyAxisBreak = record
    Range: TTyRange;
    Gap: Double;
    Expanded: Boolean;
  end;
  TTyAxisBreakArray = array of TTyAxisBreak;

  { Breaks, as a DECORATOR over any other mapper.

    Because the base implements Normalize/Denormalize in terms of
    TransformIn/TransformOut, breaks need to override only that pair: collapse in
    the INNER (already linearised) space, then delegate. That is why this composes
    with the log mapper for free, and why no scale subclass mentions breaks.

    Extents are delegated to the inner mapper — the decorator has no extent of its
    own, so wrapping one around a live scale cannot move its axis. }
  TTyBreakScaleMapper = class(TInterfacedObject, ITyScaleMapper)
  private
    FInner: ITyScaleMapper;
    FBreaks: TTyAxisBreakArray;
    function ActiveCount: Integer;
    { Inner-space span the active breaks would otherwise have occupied. }
    function CollapsedInnerSpan: Double;
    { Inner-space span the active breaks keep between them, all breaks together. }
    function GapInnerSpan: Double;
    { Sum of the active breaks' gap fractions; never 0, so the per-break share
      below cannot divide by zero. }
    function ActiveGapFractionSum: Double;
    { This break's own share of GapInnerSpan. }
    function GapFor(AIndex: Integer; AGapTotal: Double): Double;
  public
    constructor Create(const AInner: ITyScaleMapper);
    procedure AddBreak(const ARange: TTyRange; AGap: Double);
    procedure SetBreakExpanded(AIndex: Integer; AExpanded: Boolean);
    function BreakCount: Integer;

    function NeedTransform: Boolean;
    function TransformIn(AValue: Double): Double;
    function TransformOut(AValue: Double): Double;
    function Normalize(AValue: Double): Double;
    function Denormalize(ANorm: Double): Double;
    function Contain(AValue: Double): Boolean;
    function GetExtent(AKind: TTyScaleExtentKind): TTyRange;
    procedure SetExtent(AKind: TTyScaleExtentKind; const ARange: TTyRange);
    function HasExtent(AKind: TTyScaleExtentKind): Boolean;
  end;

  { One axis tick. Level 0 = major (labelled, splitLine), 1 = minor. }
  TTyScaleTick = record
    Value: Double;
    Level: Integer;
  end;
  TTyScaleTickArray = array of TTyScaleTick;

  { Base for every scale. Owns a mapper and delegates ALL mapping to it — a scale
    subclass must never compute a normalisation itself, because that is precisely
    what would make the break decorator invisible to it. }
  TTyScale = class
  private
    FMapper: ITyScaleMapper;
    FStartValue: Double;
    FHasStartValue: Boolean;
    procedure SetStartValue(AValue: Double);
  protected
    function DefaultMapper: ITyScaleMapper; virtual;
  public
    constructor Create;
    function Normalize(AValue: Double): Double;
    function Denormalize(ANorm: Double): Double;
    function Contain(AValue: Double): Boolean;
    function GetExtent: TTyRange;
    procedure SetExtent(const ARange: TTyRange);
    procedure SetExtent2(AKind: TTyScaleExtentKind; const ARange: TTyRange);
    function GetTicks: TTyScaleTickArray; virtual; abstract;
    { Swappable so a decorator (breaks) can be wrapped around it without the
      scale subclass knowing. NOTE a replacement mapper brings its OWN extents;
      set the extent again after swapping unless the new mapper wraps the old. }
    property Mapper: ITyScaleMapper read FMapper write FMapper;
    { ECharts 6.1 break B7: startValue is NOT min. It is a viewport hint that
      dataZoom and axisPointer read; it never moves the extent. Built in from day
      one because retrofitting it means reworking the extent model. }
    property StartValue: Double read FStartValue write SetStartValue;
    property HasStartValue: Boolean read FHasStartValue;
  end;

  { A linear/interval scale with nice 1-2-2.5-5 tick generation. }
  TTyIntervalScale = class(TTyScale)
  private
    FInterval: Double;
    FFixMin: Boolean;
    FFixMax: Boolean;
  public
    constructor Create;
    { Expand the extent to round boundaries so the tick count lands near
      ASplitNumber. Honours FixMin/FixMax: a pinned end is never rounded away. }
    procedure Niceify(ASplitNumber: Integer);
    function GetTicks: TTyScaleTickArray; override;
    property Interval: Double read FInterval;
    property FixMin: Boolean read FFixMin write FFixMin;
    property FixMax: Boolean read FFixMax write FFixMax;
  end;

implementation

{ ============================ TTyScaleMapperBase ============================ }

constructor TTyScaleMapperBase.Create;
begin
  inherited Create;
  FExtent[sekEffective] := TyRange(0, 1);
  FHasExtent[sekEffective] := True;
  FHasExtent[sekMapping] := False;
end;

function TTyScaleMapperBase.MappingExtent: TTyRange;
begin
  if FHasExtent[sekMapping] then
    Result := FExtent[sekMapping]
  else
    Result := FExtent[sekEffective];
end;

function TTyScaleMapperBase.NeedTransform: Boolean;
begin
  Result := True;
end;

function TTyScaleMapperBase.TransformIn(AValue: Double): Double;
begin
  Result := AValue;
end;

function TTyScaleMapperBase.TransformOut(AValue: Double): Double;
begin
  Result := AValue;
end;

function TTyScaleMapperBase.Normalize(AValue: Double): Double;
var
  r: TTyRange;
  a, b: Double;
begin
  r := MappingExtent;
  a := TransformIn(r.Start);
  b := TransformIn(r.Stop);
  if (b = a) or IsNan(a) or IsNan(b) then
    Exit(0.5);
  Result := (TransformIn(AValue) - a) / (b - a);
end;

function TTyScaleMapperBase.Denormalize(ANorm: Double): Double;
var
  r: TTyRange;
  a, b: Double;
begin
  r := MappingExtent;
  a := TransformIn(r.Start);
  b := TransformIn(r.Stop);
  if IsNan(a) or IsNan(b) then
    Exit(NaN);
  Result := TransformOut(a + ANorm * (b - a));
end;

function TTyScaleMapperBase.Contain(AValue: Double): Boolean;
begin
  Result := TyRangeContains(FExtent[sekEffective], AValue);
end;

function TTyScaleMapperBase.GetExtent(AKind: TTyScaleExtentKind): TTyRange;
begin
  if (AKind = sekMapping) and (not FHasExtent[sekMapping]) then
    Result := FExtent[sekEffective]
  else
    Result := FExtent[AKind];
end;

procedure TTyScaleMapperBase.SetExtent(AKind: TTyScaleExtentKind; const ARange: TTyRange);
begin
  FExtent[AKind] := ARange;
  FHasExtent[AKind] := True;
end;

function TTyScaleMapperBase.HasExtent(AKind: TTyScaleExtentKind): Boolean;
begin
  Result := FHasExtent[AKind];
end;

{ ============================ TTyLinearScaleMapper ============================ }

function TTyLinearScaleMapper.NeedTransform: Boolean;
begin
  Result := False;
end;

{ ============================ TTyLogScaleMapper ============================ }

constructor TTyLogScaleMapper.Create(ABase: Double);
begin
  inherited Create;
  if (ABase <= 0) or (ABase = 1) then
    ABase := 10;
  FBase := ABase;
  FLnBase := Ln(ABase);
end;

function TTyLogScaleMapper.NeedTransform: Boolean;
begin
  Result := True;
end;

function TTyLogScaleMapper.TransformIn(AValue: Double): Double;
begin
  if AValue <= 0 then
    Exit(NaN);
  Result := Ln(AValue) / FLnBase;
end;

function TTyLogScaleMapper.TransformOut(AValue: Double): Double;
begin
  Result := Power(FBase, AValue);
end;

{ ============================ TTyBreakScaleMapper ============================ }

constructor TTyBreakScaleMapper.Create(const AInner: ITyScaleMapper);
begin
  inherited Create;
  FInner := AInner;
  FBreaks := nil;
end;

procedure TTyBreakScaleMapper.AddBreak(const ARange: TTyRange; AGap: Double);
var
  n, i, j: Integer;
  tmp: TTyAxisBreak;
begin
  if AGap < 0 then AGap := 0;
  if AGap > 1 then AGap := 1;
  n := Length(FBreaks);
  SetLength(FBreaks, n + 1);
  FBreaks[n].Range := ARange;
  FBreaks[n].Gap := AGap;
  FBreaks[n].Expanded := False;
  { Keep ascending by range start — the accumulation walks below assume it.
    Bubble sort: a chart has a handful of breaks, never enough to matter. }
  for i := n downto 1 do
    for j := 0 to i - 1 do
      if FBreaks[j].Range.Start > FBreaks[j + 1].Range.Start then
      begin
        tmp := FBreaks[j];
        FBreaks[j] := FBreaks[j + 1];
        FBreaks[j + 1] := tmp;
      end;
end;

procedure TTyBreakScaleMapper.SetBreakExpanded(AIndex: Integer; AExpanded: Boolean);
begin
  if (AIndex >= 0) and (AIndex <= High(FBreaks)) then
    FBreaks[AIndex].Expanded := AExpanded;
end;

function TTyBreakScaleMapper.BreakCount: Integer;
begin
  Result := Length(FBreaks);
end;

function TTyBreakScaleMapper.ActiveCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(FBreaks) do
    if not FBreaks[i].Expanded then
      Inc(Result);
end;

function TTyBreakScaleMapper.CollapsedInnerSpan: Double;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(FBreaks) do
    if not FBreaks[i].Expanded then
      Result := Result + Abs(FInner.TransformIn(FBreaks[i].Range.Stop)
                           - FInner.TransformIn(FBreaks[i].Range.Start));
end;

function TTyBreakScaleMapper.ActiveGapFractionSum: Double;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(FBreaks) do
    if not FBreaks[i].Expanded then
      Result := Result + FBreaks[i].Gap;
  if Result <= 0 then
    Result := 1;
end;

function TTyBreakScaleMapper.GapInnerSpan: Double;
var
  e: TTyRange;
  full, kept: Double;
  i: Integer;
begin
  { A gap is a fraction of the VISUAL span. The visual span in inner units is
    (full - collapsed + gaps), which is circular — so solve it: with G the sum of
    the gap fractions, visual = (full - collapsed) / (1 - G), and the gaps
    together take G of that. }
  e := GetExtent(sekMapping);
  full := Abs(FInner.TransformIn(e.Stop) - FInner.TransformIn(e.Start));
  kept := 0;
  for i := 0 to High(FBreaks) do
    if not FBreaks[i].Expanded then
      kept := kept + FBreaks[i].Gap;
  if kept >= 1 then
    kept := 0.99;   // a break cannot eat the whole axis
  Result := (full - CollapsedInnerSpan) / (1 - kept) * kept;
end;

function TTyBreakScaleMapper.GapFor(AIndex: Integer; AGapTotal: Double): Double;
begin
  if AGapTotal <= 0 then
    Exit(0);
  Result := AGapTotal * FBreaks[AIndex].Gap / ActiveGapFractionSum;
end;

function TTyBreakScaleMapper.NeedTransform: Boolean;
begin
  Result := True;
end;

function TTyBreakScaleMapper.TransformIn(AValue: Double): Double;
var
  t, bs, be, swap, shift, gapTotal, gapEach: Double;
  i: Integer;
begin
  t := FInner.TransformIn(AValue);
  if (ActiveCount = 0) or IsNan(t) then
    Exit(t);
  gapTotal := GapInnerSpan;
  shift := 0;
  for i := 0 to High(FBreaks) do
  begin
    if FBreaks[i].Expanded then
      Continue;
    bs := FInner.TransformIn(FBreaks[i].Range.Start);
    be := FInner.TransformIn(FBreaks[i].Range.Stop);
    if be < bs then
    begin
      { A decreasing inner transform would reverse the pair. Use a dedicated
        temp — reusing `shift` here would silently discard the accumulation. }
      swap := bs; bs := be; be := swap;
    end;
    gapEach := GapFor(i, gapTotal);
    if t >= be then
      { Wholly past this break: lose its span, keep its gap. }
      shift := shift - (be - bs) + gapEach
    else if t > bs then
    begin
      { Inside: land proportionally within this break's own gap. }
      Result := bs + shift + (t - bs) / (be - bs) * gapEach;
      Exit;
    end
    else
      { Before this break, and breaks are ascending, so before all the rest. }
      Break;
  end;
  Result := t + shift;
end;

function TTyBreakScaleMapper.TransformOut(AValue: Double): Double;
var
  bs, be, swap, shift, gapTotal, gapEach, lo, hi: Double;
  i: Integer;
begin
  if ActiveCount = 0 then
    Exit(FInner.TransformOut(AValue));
  gapTotal := GapInnerSpan;
  shift := 0;
  for i := 0 to High(FBreaks) do
  begin
    if FBreaks[i].Expanded then
      Continue;
    bs := FInner.TransformIn(FBreaks[i].Range.Start);
    be := FInner.TransformIn(FBreaks[i].Range.Stop);
    if be < bs then
    begin
      swap := bs; bs := be; be := swap;
    end;
    gapEach := GapFor(i, gapTotal);
    lo := bs + shift;
    hi := lo + gapEach;
    if AValue > hi then
      shift := shift - (be - bs) + gapEach
    else if AValue >= lo then
    begin
      { Inside the gap: invert the proportional placement. A zero-width gap has
        no interior, so every point in it is the break's start. }
      if gapEach = 0 then
        Exit(FInner.TransformOut(bs));
      Exit(FInner.TransformOut(bs + (AValue - lo) / gapEach * (be - bs)));
    end
    else
      Break;
  end;
  Result := FInner.TransformOut(AValue - shift);
end;

function TTyBreakScaleMapper.Normalize(AValue: Double): Double;
var
  e: TTyRange;
  a, b: Double;
begin
  e := GetExtent(sekMapping);
  a := TransformIn(e.Start);
  b := TransformIn(e.Stop);
  if (b = a) or IsNan(a) or IsNan(b) then
    Exit(0.5);
  Result := (TransformIn(AValue) - a) / (b - a);
end;

function TTyBreakScaleMapper.Denormalize(ANorm: Double): Double;
var
  e: TTyRange;
  a, b: Double;
begin
  e := GetExtent(sekMapping);
  a := TransformIn(e.Start);
  b := TransformIn(e.Stop);
  if IsNan(a) or IsNan(b) then
    Exit(NaN);
  Result := TransformOut(a + ANorm * (b - a));
end;

function TTyBreakScaleMapper.Contain(AValue: Double): Boolean;
begin
  Result := FInner.Contain(AValue);
end;

function TTyBreakScaleMapper.GetExtent(AKind: TTyScaleExtentKind): TTyRange;
begin
  Result := FInner.GetExtent(AKind);
end;

procedure TTyBreakScaleMapper.SetExtent(AKind: TTyScaleExtentKind; const ARange: TTyRange);
begin
  FInner.SetExtent(AKind, ARange);
end;

function TTyBreakScaleMapper.HasExtent(AKind: TTyScaleExtentKind): Boolean;
begin
  Result := FInner.HasExtent(AKind);
end;

{ ============================ TTyScale ============================ }

constructor TTyScale.Create;
begin
  inherited Create;
  FMapper := DefaultMapper;
  FHasStartValue := False;
  FStartValue := NaN;
end;

function TTyScale.DefaultMapper: ITyScaleMapper;
begin
  Result := TTyLinearScaleMapper.Create;
end;

procedure TTyScale.SetStartValue(AValue: Double);
begin
  FStartValue := AValue;
  FHasStartValue := not IsNan(AValue);
end;

function TTyScale.Normalize(AValue: Double): Double;
begin
  Result := FMapper.Normalize(AValue);
end;

function TTyScale.Denormalize(ANorm: Double): Double;
begin
  Result := FMapper.Denormalize(ANorm);
end;

function TTyScale.Contain(AValue: Double): Boolean;
begin
  Result := FMapper.Contain(AValue);
end;

function TTyScale.GetExtent: TTyRange;
begin
  Result := FMapper.GetExtent(sekEffective);
end;

procedure TTyScale.SetExtent(const ARange: TTyRange);
begin
  FMapper.SetExtent(sekEffective, ARange);
end;

procedure TTyScale.SetExtent2(AKind: TTyScaleExtentKind; const ARange: TTyRange);
begin
  FMapper.SetExtent(AKind, ARange);
end;

{ ============================ TTyIntervalScale ============================ }

{ Round AValue to a 1/2/2.5/5 x 10^k mantissa. ARound picks the nearest such
  value; otherwise the next one up. Heckbert's nice numbers with 2.5 added — it
  is what makes a 0..250 axis step by 50 instead of 100. }
function NiceNum(AValue: Double; ARound: Boolean): Double;
var
  expo: Integer;
  frac, nice: Double;
begin
  if AValue <= 0 then
    Exit(1);
  expo := Floor(Log10(AValue));
  frac := AValue / Power(10, expo);
  if ARound then
  begin
    if frac < 1.5 then nice := 1
    else if frac < 3 then nice := 2
    else if frac < 7 then nice := 5
    else nice := 10;
  end
  else
  begin
    if frac <= 1 then nice := 1
    else if frac <= 2 then nice := 2
    else if frac <= 2.5 then nice := 2.5
    else if frac <= 5 then nice := 5
    else nice := 10;
  end;
  Result := nice * Power(10, expo);
end;

constructor TTyIntervalScale.Create;
begin
  inherited Create;
  FInterval := 1;
  FFixMin := False;
  FFixMax := False;
end;

procedure TTyIntervalScale.Niceify(ASplitNumber: Integer);
var
  e: TTyRange;
  span, lo, hi: Double;
begin
  if ASplitNumber < 1 then
    ASplitNumber := 5;
  e := GetExtent;
  span := TyRangeSpan(e);
  if span <= 0 then
  begin
    { A flat extent has no scale of its own. Borrow one from the value's own
      magnitude, so a chart of a single 42 does not get a 0..1 axis. }
    if e.Start = 0 then
      span := 1
    else
      span := Abs(e.Start);
    e := TyRange(e.Start - span / 2, e.Start + span / 2);
    span := TyRangeSpan(e);
  end;
  FInterval := NiceNum(span / ASplitNumber, False);
  if FFixMin then
    lo := e.Start
  else
    lo := Floor(e.Start / FInterval) * FInterval;
  if FFixMax then
    hi := e.Stop
  else
    hi := Ceil(e.Stop / FInterval) * FInterval;
  if hi <= lo then
    hi := lo + FInterval;
  SetExtent(TyRange(lo, hi));
end;

function TTyIntervalScale.GetTicks: TTyScaleTickArray;
var
  e: TTyRange;
  v: Double;
  n, i: Integer;
begin
  Result := nil;
  e := GetExtent;
  if (FInterval <= 0) or (TyRangeSpan(e) <= 0) then
    Exit;
  { Count first, then fill from the INDEX: a float accumulator would drift. }
  n := Floor(TyRangeSpan(e) / FInterval + 1e-9) + 1;
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    v := e.Start + i * FInterval;
    { Snap away the last binary ulp so a 0.1 step does not label 0.30000000000000004. }
    if Abs(v) < FInterval * 1e-9 then
      v := 0;
    Result[i].Value := v;
    Result[i].Level := 0;
  end;
end;

end.
