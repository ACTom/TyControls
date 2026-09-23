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
    sekEffective — always present. Ticks, labels, splitLine, hit-test.
    sekMapping   — present only when set. Widened outward from the effective ends
                   so a shape drawn AT an end (a bar's half width, a candlestick
                   body) stays inside the plot band. Normalize/Denormalize, the
                   band width, Contain and the axisPointer read it.
                   [Revised in batch 41: this put Contain with the effective
                   extent. Upstream's contain reads the mapping one
                   (scaleMapper.ts:446-451): a pointer in a bar's margin is on
                   the axis.]
  Getting this wrong is not a missing option, it is a different extent model:
  axis.containShape and axis.dataMin/dataMax both rest on it.

  PURE: SysUtils, Math and AdvChart.Types only. No Controls, no Graphics, no
  handle. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Data,
     tyControls.AdvChart.Time;

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
    { Against the MAPPING extent when one is set — see the unit header. }
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
    { An extent boundary that the stride skipped and that was forced back in.
      A THIRD concept, not a Level: it says "this tick is here because the
      extent ends here, not because the interval landed on it", and the on-band
      tick placement reads it to decide whether the last tick belongs to a band
      or to the edge (ECharts helper.ts:317-328, Axis.ts:345-347). }
    OffInterval: Boolean;

    { ---- and three more that only a time scale ever fills in ---- }

    { HOW COARSE this tick is, 0 being the finest and the largest number the
      coarsest. A SEPARATE FIELD from Level on purpose: Level means major or
      minor everywhere else in the port, and writing a time tick's coarseness
      into it would turn every year marker into a minor tick -- drawn short,
      unlabelled, and on the wrong style. }
    TimeLevel: Integer;
    { The unit this timestamp is round to, which decides its label. }
    TimeUnit: TTyTimeUnit;
    { An extent endpoint that no interval landed on. Unlike OffInterval --
      which is about a BAND -- this is about a number line whose ends were
      never rounded outwards, and it is read to HIDE the label. }
    NotNice: Boolean;
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
    FMarkedBlank: Boolean;
    procedure SetStartValue(AValue: Double);
  protected
    function DefaultMapper: ITyScaleMapper; virtual;
  public
    constructor Create;
    { VIRTUAL, all three. The base bodies stay one-line mapper forwarders -- a
      scale must never compute a normalisation itself -- but an ordinal scale
      has to convert an ordinal number into the TICK number its extent is
      measured in before the mapper ever sees it. That conversion cannot be a
      TransformIn: the base pushes the extent ENDS through TransformIn
      (see SetExtent), and an ordinal extent is already in tick space. }
    function Normalize(AValue: Double): Double; virtual;
    function Denormalize(ANorm: Double): Double; virtual;
    function Contain(AValue: Double): Boolean; virtual;
    function GetExtent: TTyRange;
    { The mapping extent when one is set, else the effective one. Band width
      needs that preference and reaching through the public Mapper to get it
      would put the fallback rule in the caller. }
    function GetExtent2(AKind: TTyScaleExtentKind): TTyRange;
    { The same extent in the mapper's LINEAR space -- decades on a log
      axis. Upstream keeps it rather than taking the logarithm of the ends
      again: a log axis nices to -1 and 3, not -0.9999999999999998. A span,
      a band, a half bar are all measured in it. Unsorted: the ends as the
      extent has them. }
    function LinearExtent2(AKind: TTyScaleExtentKind): TTyRange; virtual;
    procedure SetExtent(const ARange: TTyRange);
    procedure SetExtent2(AKind: TTyScaleExtentKind; const ARange: TTyRange);
    function GetTicks: TTyScaleTickArray; virtual; abstract;
    { "This scale has nothing to show." A value axis with no data is blank too,
      so it belongs on the base rather than on the ordinal subclass: GetTicks,
      band width and the axis builder all want ONE predicate. }
    function Blank: Boolean; virtual;
    { UPSTREAM'S setBlank. The raw extent knows when an axis had nothing to
      go on -- no data and no usable min or max -- and says so here; the nice
      step still gives such an axis [0, 1] and ticks on it, and it is this
      flag, not the extent, that keeps them from being drawn. }
    property MarkedBlank: Boolean read FMarkedBlank write FMarkedBlank;
    { Swappable so a decorator (breaks) can be wrapped around it without the
      scale subclass knowing. NOTE a replacement mapper brings its OWN extents;
      set the extent again after swapping unless the new mapper wraps the old. }
    property Mapper: ITyScaleMapper read FMapper write FMapper;
    { upstream's startValue, as the raw extent resolved it: the value a bar on
      this axis stands on (getValueAxisStart). Not min -- setting it moves no
      extent. The raw extent has already joined it to the extent where
      upstream does, and pinned the end it moved; this only carries the value
      on to the bars. Not-a-number (HasStartValue False) where no bar asked
      and none was written.
      [Revised in batch 36: this said startValue was a viewport hint that
      "never moves the extent". Upstream's scaleRawExtentInfo unions it into
      the extent when it was written, on a log axis, or where zero is
      included -- which the raw extent here has done since batch 33.] }
    property StartValue: Double read FStartValue write SetStartValue;
    property HasStartValue: Boolean read FHasStartValue;
  end;

  { The category scale.

    ITS EXTENT IS A PAIR OF TICK NUMBERS, INCLUSIVE AT BOTH ENDS. [0, 5] is six
    categories on screen, not five, and not a count. Count = Stop - Start + 1.
    Same off-by-one as TTyScrollBar.Max, which this library has already been
    bitten by once, so a test pins it.

    THREE NUMBER SPACES, kept apart on purpose:
      raw category    a string, living in the meta
      ordinal number  0..CategoryCount-1 -- what a data column holds and what
                      DataToCoord takes
      tick number     what GetTicks yields, and what the EXTENT is measured in
    The last two are the same number today. They stop being the same the moment
    a bar race reorders categories, and ECharts' own source carries a complaint
    about not having separated them early. Separating them now costs a rename.

    THE META IS BORROWED, NEVER OWNED. The axis owns it and hands the SAME
    instance to this scale and to every series dimension bound to that axis.
    That sharing IS the mechanism by which a category collected off one series'
    data reaches the axis and every other series on it.

    NO NICEING. An ordinal extent is not rounded: splitNumber, interval,
    minInterval and maxInterval do not apply to it. }
  TTyOrdinalScale = class(TTyScale)
  private
    FMeta: TTyOrdinalMeta;              // BORROWED -- never freed here
  public
    constructor Create;
    { The one place the extent comes from: [0, CategoryCount-1]. NEVER from the
      data's own min or max. Zero categories leaves [0,0] and Blank True rather
      than writing a reversed [0,-1], which TyRange would normalise to [-1,0]
      and Count would then answer 2. }
    procedure SetExtentFromCategories;
    procedure SetMeta(AMeta: TTyOrdinalMeta);

    { A name to its ordinal number, NaN when unknown. The string branch NEVER
      falls back to numeric: '3' against ['a','b','c','d'] is NaN, not 3. }
    function ParseText(const AText: string): Double;
    { A number is already an ordinal number, snapped the way JavaScript rounds. }
    function ParseNumber(AValue: Double): Double;

    { Categories currently in the EXTENT, inclusive. Zero when blank. }
    function Count: Integer;
    { Categories the meta holds. Differs from Count as soon as min/max or a
      dataZoom narrows the extent, and the two are not interchangeable: Contain
      tests against this one, band width divides by the other. }
    function CategoryCount: Integer;
    { Takes a TICK value and converts inside, so a caller never has to know
      which space it is holding. '' out of range and '' when blank. }
    function GetLabel(ATickValue: Double): string;

    function GetTicks: TTyScaleTickArray; override;
    function Blank: Boolean; override;

    { Identity today. The indirection stays because it is the API shape that a
      reordering feature needs, not the feature itself. }
    function OrdinalToTick(AOrdinal: Double): Double;
    function TickToOrdinal(ATick: Double): Double;

    function Normalize(AValue: Double): Double; override;
    function Denormalize(ANorm: Double): Double; override;
    function Contain(AValue: Double): Boolean; override;

    property Meta: TTyOrdinalMeta read FMeta;
  end;

  { A linear/interval scale with upstream's nice ticks: a step of 1, 2, 3, 5
    or 10 of a power of ten, and on a log axis a whole number of decades. }
  TTyIntervalScale = class(TTyScale)
  private
    FInterval: Double;
    FIntervalPrecision: Integer;
    { upstream's niceExtent: the first and last multiples of the step INSIDE
      the extent -- in the stepping space, decades on a log axis. }
    FNiceStart, FNiceStop: Double;
    { The extent in the stepping space as Niceify left it, and the extent it
      left in value space: while the two still match, the ticks walk the
      former rather than a logarithm of the latter. }
    FStubStart, FStubStop: Double;
    FNiced: Boolean;
    FNicedExtent: TTyRange;
    FLogRule: Boolean;
    FMinorSplit: Integer;
    FFixMin: Boolean;
    FFixMax: Boolean;
    FMinInterval: Double;
    FMaxInterval: Double;
    FContainShape: Boolean;
    function StillNiced: Boolean;
    function StubExtent: TTyRange;
    function StubToValue(AValue: Double): Double;
    function StubTicks(AExpand: Boolean): TTyDoubleArray;
    function LogWarped: Boolean;
    procedure NiceifyJs(ASplitNumber: Double; AUserInterval: Double);
  public
    constructor Create;
    { upstream's calcNiceForIntervalOrLogScale. The extent is validated
      (a flat one opened, a broken one replaced by [0, 1]), the step chosen
      from ASplitNumber -- `raw || default`, rounded, at least one -- and each
      end the author did not pin rounded OUT to a multiple of it. A pinned end
      stays where it is and becomes a tick of its own.

      AUserInterval is `interval` as written, not-a-number when there is none:
      it replaces the tick STEP only. The extent is still rounded to the step
      upstream would have picked. }
    procedure Niceify(ASplitNumber: Double; AUserInterval: Double); overload;
    procedure Niceify(ASplitNumber: Double); overload;
    { ON A LOG AXIS, OVER THE DECADES NICEIFY LEFT: upstream's intervalStub
      holds the extent in log space as the nice step wrote it -- -1 and 3,
      not the logarithms of 0.1 and 1000, which come back as
      -0.9999999999999998 and 2.9999999999999996 -- and normalises over that.
      A mapping extent, when one is set, is still taken back through the
      logarithm, as upstream's setExtent2 takes it. }
    function Normalize(AValue: Double): Double; override;
    function Denormalize(ANorm: Double): Double; override;
    function LinearExtent2(AKind: TTyScaleExtentKind): TTyRange; override;
    { Interval.ts' getTicks: the extent's own start when the step did not
      land on it, every multiple inside, the extent's own end likewise --
      rounded to the step's precision one by one, and none at all past three
      thousand. Minor ticks, when asked for, merged in value order. }
    function GetTicks: TTyScaleTickArray; override;
    property Interval: Double read FInterval;
    { Decimals every tick is rounded to: the step's own plus two. }
    property IntervalPrecision: Integer read FIntervalPrecision;
    property NiceStart: Double read FNiceStart;
    property NiceStop: Double read FNiceStop;
    { THE LOG AXIS' STEP RULE: whole decades, no nice(). Set by whoever gives
      the scale a log mapper -- the mapper alone cannot say, because an axis
      break transforms too and nices like a linear axis. }
    property LogRule: Boolean read FLogRule write FLogRule;
    { How many pieces each major interval is cut into, matching ECharts'
      minorTick.splitNumber. 0 (the default) means no minor ticks at all --
      they are opt-in, because an axis that grows a second set of lines the
      moment it is drawn is not what anybody asked for.

      The ticks come back in ONE array, ordered by value, with Level saying
      which is which. A caller that only wants the major ones tests Level; a
      caller that draws both walks it once. Two arrays would let the two drift
      out of order, and the order is what a renderer walks. }
    property MinorSplitNumber: Integer read FMinorSplit write FMinorSplit;
    property FixMin: Boolean read FFixMin write FFixMin;
    property FixMax: Boolean read FFixMax write FFixMax;
    { FLOOR AND CEILING ON THE STEP, ECharts' minInterval / maxInterval. 0 means
      unset for both, which is why they are Doubles rather than an optional
      record: a step of zero is meaningless anyway.

      minInterval is the one anybody notices. An axis counting whole things --
      orders, people, errors -- nices 0..1 to a step of 0.2 and labels 0, 0.2,
      0.4 for values no fraction of which can exist; minInterval: 1 is how
      ECharts says "this axis counts". }
    property MinInterval: Double read FMinInterval write FMinInterval;
    property MaxInterval: Double read FMaxInterval write FMaxInterval;
    { UPSTREAM'S ctnShp: a bar stands on this axis and asked to be contained.
      It touches the effective extent in one place only -- a flat extent at
      zero opens to [-1, 1] rather than [0, 1], pins or no pins, so the bar
      standing at zero has room on both sides. Everything else it does is the
      mapping extent, which whoever set this writes after Niceify. }
    property ContainShape: Boolean read FContainShape write FContainShape;
  end;

  { An axis whose ticks are DATES.

    A descendant of the interval scale because the MAPPING really is the
    interval scale's -- epoch milliseconds are numbers and a linear mapper
    places them perfectly -- and only the question of where a tick belongs is
    different. Before this, a time axis was exactly that and nothing else:
    correctly placed ticks every 200,000,000 ms, labelled 1709251200000.

    WHAT IT MUST NOT INHERIT IS THE NICEING. An interval scale opens its
    extent out to round numbers before choosing a step, and the nearest round
    number to a week in March 2024 is somewhere in 1973. A time extent is kept
    exactly as the data left it, which is also why its end ticks need the
    NotNice flag. }
  TTyTimeScale = class(TTyIntervalScale)
  private
    FSplitNumber: Integer;
    FUTC: Boolean;
  public
    constructor Create;
    function GetTicks: TTyScaleTickArray; override;
    { Roughly how many ticks to aim for. Upstream defaults a time axis to SIX
      where every other axis gets five -- dates are wider than numbers. }
    property SplitNumber: Integer read FSplitNumber write FSplitNumber;
    { ECharts' useUTC: ONE option at the root of the tree, false by default,
      and it switches which calendar the ticks are snapped to rather than
      shifting any timestamp. Data kept in UTC on a server is still meant to
      be read on the reader's own clock. }
    property UTC: Boolean read FUTC write FUTC;
  end;

{ JavaScript's rounding, which is NOT FPC's -- Round is banker's here. Exported
  because the ordinal scale is not the only place that has to snap the way the
  option text's author expects. }
function TyJsRound(AValue: Double): Double;

{ ---- upstream's util/number.ts, as the ticks need it ---- }

{ Math.pow(10, k) exactly as the JavaScript engine answers it, which for some
  negative k is not the correctly rounded power. }
function TyJsPow10(AExp: Integer): Double;
{ `+(+x).toFixed(p)`, p clamped to 0..20, rounded on the BINARY value as the
  specification says: (1.005).toFixed(2) is 1.00, because 1.005 is a hair
  under it. Not through FPC's Str, which rounds its own seventeen-digit
  decimal and answered 1.01. }
function TyJsToFixed(AValue: Double; APrecision: Integer): Double;
{ The power of ten below AValue, corrected where the logarithm falls short. }
function TyQuantityExponent(AValue: Double): Integer;
{ nice(val, round): 1/2/3/5/10 of a power of ten, at 1.5/2.5/4/7 when
  rounding and 1/2/3/5 otherwise, snapped to the decimal it means. }
function TyNice(AValue: Double; ARound: Boolean): Double;
{ getPrecision: how many decimals AValue carries. }
function TyGetPrecision(AValue: Double): Integer;
{ getIntervalPrecision: the step's decimals plus two. }
function TyIntervalPrecision(AInterval: Double): Integer;
{ ensureValidSplitNumber: `raw || default`, rounded, at least one. }
function TyValidSplitNumber(ARaw: Double; ADefault: Integer): Integer;
{ The ticks an axis DRAWS: none at all on a blank scale -- no labels, tick
  marks, minor ticks, split lines or split areas, which is where upstream
  checks isBlank -- and GetTicks otherwise. GetTicks itself still answers on
  a blank scale, as upstream's does. }
function TyDrawnTicks(AScale: TTyScale): TTyScaleTickArray;

{ ---- upstream's text for a number ---- }

{ Number::toString(10): the SHORTEST digits that read back as AValue, laid
  out as JavaScript lays them out -- positionally from 1e-7 up to 1e21,
  '1.5e-7' and '1e+21' outside that. 'NaN', 'Infinity', and '0' for either
  zero. Exact: digits are found and checked with integer arithmetic, never
  through FPC's Str or Val. }
function TyJsNumberToString(AValue: Double): string;
{ (x).toFixed(p) as the STRING it returns. p is clamped to 0..20, as
  upstream's round clamps it; the sign comes from x < 0, so -0.001 to two
  places is '-0.00' and -0 is '0.00'; and from 1e21 up it is ToString. }
function TyJsToFixedStr(AValue: Double; APrecision: Integer): string;
{ addCommas: the integer part's digits grouped in threes -- only the part
  before the first '.', and only runs of digits, so '1e+21', '-0.00' and
  'NaN' come through as they are. }
function TyJsAddCommas(const AText: string): string;

type
  { How a label's precision was written. lpNone: the value's own decimals,
    as every tick label gets. lpAuto: the scale's interval precision, which is
    the pointer's default. lpDigits: a number, clamped to 0..20 and truncated
    where it is used (upstream's round, then toFixed). lpNotANumber: something
    Number() cannot read, which makes upstream print the value's ToString.
    The zero value is lpNone, a tick label's precision. }
  TTyLabelPrecisionKind = (lpNone, lpAuto, lpDigits, lpNotANumber);
  TTyLabelPrecision = record
    Kind: TTyLabelPrecisionKind;
    Digits: Double;
  end;

function TyLabelPrecision(AKind: TTyLabelPrecisionKind;
  ADigits: Double = 0): TTyLabelPrecision;
{ IntervalScale.getLabel: the value rounded to the precision asked for, as
  toFixed prints it, grouped by addCommas. A log axis is labelled by the same
  routine -- its 'auto' precision is the decade step's, which is two. }
function TyScaleValueLabel(AScale: TTyScale; AValue: Double;
  const APrecision: TTyLabelPrecision): string;

implementation

uses tyControls.AdvChart.JsMath;

function TyJsRound(AValue: Double): Double;
begin
  { JavaScript's Math.round is half-toward-plus-infinity. FPC's Round is
    BANKER'S -- Round(2.5) is 2 and Round(1.5) is 2 -- which would snap every
    other band boundary to the wrong category. Floor(x + 0.5) matches JS on
    both signs: -0.5 gives 0, -1.5 gives -1. }
  if IsNan(AValue) or IsInfinite(AValue) then Exit(AValue);
  { NOT Floor(x + 0.5). Math.Floor answers a 32-bit Integer and wraps past two
    thousand million, and the sum rounds: 0.49999999999999994 + 0.5 is 1. }
  Result := Int(AValue);
  if Result > AValue then Result := Result - 1;
  if AValue - Result >= 0.5 then Result := Result + 1;
end;

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
  Result := TyRangeContains(MappingExtent, AValue);
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
  FLnBase := TyJsLog(ABase);
end;

function TTyLogScaleMapper.NeedTransform: Boolean;
begin
  Result := True;
end;

function TTyLogScaleMapper.TransformIn(AValue: Double): Double;
begin
  if AValue <= 0 then
    Exit(NaN);
  Result := TyJsLog(AValue) / FLnBase;
end;

function TTyLogScaleMapper.TransformOut(AValue: Double): Double;
begin
  { MATH.POW AS V8 ANSWERS IT for a whole power of ten -- every decade a log
    axis draws, and both ends of its extent. FPC's Power walks a negative
    exponent by repeated multiplication and lands up to eight units in the
    last place away: 1e-10 came back as 1.0000000000000006e-10. Another
    base, or a fraction of a power, goes through V8's own pow.
    [Revised in batch 43: those went through FPC's Power, up to a dozen
    units in the last place off V8's at a fractional exponent -- every
    containShape end on a log axis.] }
  if (FBase = 10) and not (IsNan(AValue) or IsInfinite(AValue))
    and (Frac(AValue) = 0) and (Abs(AValue) <= 400) then
    Exit(TyJsPow10(Trunc(AValue)));
  Result := TyJsPow(FBase, AValue);
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

function TTyScale.GetExtent2(AKind: TTyScaleExtentKind): TTyRange;
begin
  Result := FMapper.GetExtent(AKind);
end;

function TTyScale.LinearExtent2(AKind: TTyScaleExtentKind): TTyRange;
var e: TTyRange;
begin
  e := GetExtent2(AKind);
  Result.Start := FMapper.TransformIn(e.Start);
  Result.Stop := FMapper.TransformIn(e.Stop);
end;

function TTyScale.Blank: Boolean;
begin
  { A scale is blank when its extent says nothing can be drawn. The base can
    answer that from the extent alone; the ordinal scale overrides because an
    empty category list is blank whatever the extent happens to hold. }
  Result := FMarkedBlank or IsNan(GetExtent.Start) or IsNan(GetExtent.Stop);
end;

{ ============================ TTyOrdinalScale ============================ }

constructor TTyOrdinalScale.Create;
begin
  inherited Create;
  FMeta := nil;
end;

procedure TTyOrdinalScale.SetMeta(AMeta: TTyOrdinalMeta);
begin
  { Borrowed. The axis owns it; see the class comment. }
  FMeta := AMeta;
  SetExtentFromCategories;
end;

procedure TTyOrdinalScale.SetExtentFromCategories;
var n: Integer;
begin
  n := CategoryCount;
  if n <= 0 then
  begin
    { NOT TyRange(0, -1): TyRange normalises a reversed pair, so that would
      become [-1, 0] and Count would answer two categories where there are
      none. Blank is what callers test; the extent is left harmless. }
    SetExtent(TyRange(0, 0));
    Exit;
  end;
  SetExtent(TyRange(0, n - 1));
end;

function TTyOrdinalScale.ParseText(const AText: string): Double;
var o: Integer;
begin
  if FMeta = nil then Exit(NaN);
  o := FMeta.GetOrdinal(AText);
  { No numeric fallback, on purpose: '3' against ['a','b','c','d'] names no
    category, and answering 3 would silently plot a point on a category the
    user never wrote. }
  if o < 0 then Exit(NaN);
  Result := o;
end;

function TTyOrdinalScale.ParseNumber(AValue: Double): Double;
begin
  Result := TyJsRound(AValue);
end;

function TTyOrdinalScale.CategoryCount: Integer;
begin
  if FMeta = nil then Exit(0);
  Result := FMeta.Count;
end;

function TTyOrdinalScale.Blank: Boolean;
begin
  Result := CategoryCount <= 0;
end;

function TTyOrdinalScale.Count: Integer;
var e: TTyRange;
begin
  if Blank then Exit(0);
  e := GetExtent;
  if IsNan(e.Start) or IsNan(e.Stop) then Exit(0);
  { INCLUSIVE at both ends -- [0,5] is six categories. }
  Result := Trunc(e.Stop) - Trunc(e.Start) + 1;
  if Result < 0 then Result := 0;
end;

function TTyOrdinalScale.OrdinalToTick(AOrdinal: Double): Double;
begin
  Result := AOrdinal;
end;

function TTyOrdinalScale.TickToOrdinal(ATick: Double): Double;
begin
  Result := ATick;
end;

function TTyOrdinalScale.GetLabel(ATickValue: Double): string;
var o: Double;
begin
  Result := '';
  { The meta, not Blank. A scale that was never given a category list at all is
    what would crash here; a blank-but-present list already answers '' from
    CategoryAt. Mutation testing found the guard was aimed at the wrong case. }
  if FMeta = nil then Exit;
  o := TickToOrdinal(ATickValue);
  if IsNan(o) or IsInfinite(o) then Exit;
  { CategoryAt already answers '' out of range. }
  Result := FMeta.CategoryAt(Trunc(o));
end;

function TTyOrdinalScale.GetTicks: TTyScaleTickArray;
var
  e: TTyRange;
  i, n: Integer;
begin
  Result := nil;
  e := GetExtent;
  { No guards. There were two -- one on Blank, one on a zero count -- and
    mutation testing removed each in turn without anything going red: Count
    already answers 0 for a blank scale, and SetLength(Result, 0) is already an
    empty array. The empty case falls out; a guard would only be a claim that
    it does not. }
  n := Count;
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    Result[i].Value := Trunc(e.Start) + i;   { contiguous, step 1 }
    Result[i].Level := 0;
    Result[i].OffInterval := False;
  end;
end;

function TTyOrdinalScale.Normalize(AValue: Double): Double;
begin
  { Ordinal to TICK first: the extent is measured in tick numbers, and the
    mapper only ever sees that space. }
  Result := Mapper.Normalize(OrdinalToTick(AValue));
end;

function TTyOrdinalScale.Denormalize(ANorm: Double): Double;
begin
  { Snap to a whole tick, THEN back to an ordinal. The rounding is the reason
    dragging a window over a category axis lands on whole categories. }
  Result := TickToOrdinal(TyJsRound(Mapper.Denormalize(ANorm)));
end;

function TTyOrdinalScale.Contain(AValue: Double): Boolean;
begin
  { Note the asymmetry and keep it: the extent test takes the TICK number, the
    range test takes the RAW ordinal. Zero categories therefore contains
    nothing, which is what Blank needs. }
  Result := Mapper.Contain(OrdinalToTick(AValue))
        and (AValue >= 0) and (AValue < CategoryCount);
end;

{ ============================ TTyIntervalScale ============================ }

{ ---- upstream's util/number.ts, the parts a tick is made of ---- }

const
  { Math.pow(10, k) AS V8 ANSWERS IT, bit for bit. It is not the correctly
    rounded power -- 10^-4 comes back as 0.00009999999999999999 -- and FPC's
    Power is not either, in different places. A tick step is nice(x) and
    nice(x) divides by this, so a mantissa read on the wrong side of 1.5 picks
    another step; taken from the engine upstream runs in, it cannot. The
    whole range a Double holds, because a log axis' extent is read back
    through the same power. }
  cJsPow10: array[-323..308] of QWord = (
    $0000000000000002, $0000000000000014, $00000000000000CA, $00000000000007E8,
    $0000000000004F10, $00000000000316A2, $00000000001EE257, $000000000134D761,
    $000000000C1069CD, $0000000078A42205, $00000004B6695433, $0000002F201D49FB,
    $000001D74124E3D1, $000012688B70E62B, $0000B8157268FDAF, $000730D67819E8D2,
    $0031FA182C40C60E, $0066789E3750F790, $009C16C5C5253575, $00D18E3B9B374169,
    $0105F1CA820511C4, $013B6E3D22865634, $017124E63593F5E1, $01A56E1FC2F8F359,
    $01DAC9A7B3B7302F, $0210BE08D0527E1D, $0244ED8B04671DA5, $027A28EDC580E50E,
    $02B059949B708F29, $02E46FF9C24CB2F3, $03198BF832DFDFB0, $034FEEF63F97D79C,
    $0383F559E7BEE6C1, $03B8F2B061AEA072, $03EF2F5C7A1A488E, $04237D99CC506D59,
    $04585D003F6488AF, $048E74404F3DAADB, $04C308A831868AC9, $04F7CAD23DE82D7B,
    $052DBD86CD6238D9, $05629674405D6388, $05973C115074BC6A, $05CD0B15A491EB84,
    $060226ED86DB3333, $0636B0A8E8920000, $066C5CD322B67FFF, $06A1BA03F5B21000,
    $06D62884F31E93FF, $070BB2A62FE638FF, $07414FA7DDEFE3A0, $0775A391D56BDC87,
    $07AB0C764AC6D3A9, $07E0E7C9EEBC444A, $081521BC6A6B555C, $084A6A2B85062AB4,
    $0880825B3323DAB0, $08B4A2F1FFECD15C, $08E9CBAE7FE805B3, $09201F4D0FF10390,
    $0954272053ED4474, $098930E868E89591, $09BF7D228322BAF5, $09F3AE3591F5B4D9,
    $0A2899C2F6732210, $0A5EC033B40FEA93, $0A9338205089F29C, $0AC8062864AC6F43,
    $0AFE07B27DD78B14, $0B32C4CF8EA6B6EC, $0B677603725064A8, $0B9D53844EE47DD1,
    $0BD25432B14ECEA3, $0C06E93F5DA2824C, $0C3CA38F350B22DF, $0C71E6398126F5CB,
    $0CA65FC7E170B33E, $0CDBF7B9D9CCE00E, $0D117AD428200C08, $0D45D98932280F0A,
    $0D7B4FEB7EB212CD, $0DB111F32F2F4BC0, $0DE5566FFAFB1EB0, $0E1AAC0BF9B9E65C,
    $0E50AB877C142FFA, $0E84D6695B193BF8, $0EBA0C03B1DF8AF6, $0EF047824F2BB6DA,
    $0F245962E2F6A490, $0F596FBB9BB44DB4, $0F8FCBAA82A16121, $0FC3DF4A91A4DCB5,
    $0FF8D71D360E13E2, $102F0CE4839198DB, $1063680ED23AFF89, $1098421286C9BF6B,
    $10CE5297287C2F45, $1102F39E794D9D8B, $1137B08617A104EE, $116D9CA79D89462A,
    $11A281E8C275CBDA, $11D72262F3133ED0, $120CEAFBAFD80E85, $124212DD4DE70913,
    $12769794A160CB58, $12AC3D79C9B8FE2E, $12E1A66C1E139EDD, $1316100725988694,
    $134B9408EEFEA839, $13813C85955F2923, $13B58BA6FAB6F36C, $13EAEE90B964B047,
    $1420D51A73DEEE2D, $14550A6110D6A9B8, $148A4CF9550C5426, $14C0701BD527B498,
    $14F48C22CA71A1BE, $1529AF2B7D0E0A2D, $15600D7B2E28C65C, $159410D9F9B2F7F3,
    $15C91510781FB5F0, $15FF5A549627A36C, $16339874DDD8C623, $16687E92154EF7AC,
    $169E9E369AA2B597, $16D322E220A5B17E, $1707EB9AA8CF1DDE, $173DE6815302E556,
    $1772B010D3E1CF56, $17A75C1508DA432B, $17DD331A4B10D3F6, $18123FF06EEA847A,
    $1846CFEC8AA52598, $187C83E7AD4E6EFE, $18B1D270CC51055F, $18E6470CFF6546B6,
    $191BD8D03F3E9864, $1951678227871F3E, $1985C162B168E70E, $19BB31BB5DC320D2,
    $19F0FF151A99F483, $1A253EDA614071A4, $1A5A8E90F9908E0D, $1A90991A9BFA58C8,
    $1AC4BF6142F8EEFA, $1AF9EF3993B72AB8, $1B303583FC527AB3, $1B6442E4FB671960,
    $1B99539E3A40DFB8, $1BCFA885C8D117A6, $1C03C9539D82AEC8, $1C38BBA884E35A7A,
    $1C6EEA92A61C3118, $1CA3529BA7D19EAF, $1CD8274291C6065B, $1D0E3113363787F2,
    $1D42DEAC01E2B4F7, $1D779657025B6234, $1DAD7BECC2F23AC2, $1DE26D73F9D764B9,
    $1E1708D0F84D3DE8, $1E4CCB0536608D61, $1E81FEE341FC585D, $1EB67E9C127B6E74,
    $1EEC1E43171A4A11, $1F2192E9EE706E4B, $1F55F7A46A0C89DD, $1F8B758D848FAC55,
    $1FC1297872D9CBB5, $1FF573D68F903EA2, $202AD0CC33744E4B, $2060C27FA028B0EF,
    $2094F31F8832DD2A, $20CA2FE76A3F9475, $21005DF0A267BCC9, $2134756CCB01ABFC,
    $216992C7FDC216FA, $219FF779FD329CB9, $21D3FAAC3E3FA1F4, $2208F9574DCF8A70,
    $223F37AD21436D0C, $227382CC34CA2428, $22A8637F41FCAD32, $22DE7C5F127BD87E,
    $23130DBB6B8D674F, $2347D12A4670C122, $237DC574D80CF16B, $23B29B69070816E3,
    $23E7424348CA1C9C, $241D12D41AFCA3C3, $24522BC490DDE65A, $2486B6B5B5155FF0,
    $24BC6463225AB7EC, $24F1BEBDF578B2F4, $25262E6D72D6DFB0, $255BBA08CF8C979C,
    $2591544581B7DEC2, $25C5A956E225D672, $25FB13AC9AAF4C0F, $2630EC4BE0AD8F89,
    $2665275ED8D8F36C, $269A71368F0F3046, $26D086C219697E2C, $2704A8729FC3DDB7,
    $2739D28F47B4D525, $277023998CD10537, $27A42C7FF0054685, $27D9379FEC069826,
    $280F8587E7083E30, $2843B374F06526DE, $2878A0522C7E7095, $28AEC866B79E0CBA,
    $28E33D4032C2C7F4, $29180C903F7379F2, $294E0FB44F50586E, $2982C9D0B1923745,
    $29B77C44DDF6C516, $29ED5B561574765C, $2A225915CD68C9F9, $2A56EF5B40C2FC78,
    $2A8CAB3210F3BB95, $2AC1EAFF4A98553D, $2AF665BF1D3E6A8C, $2B2BFF2EE48E0530,
    $2B617F7D4ED8C33E, $2B95DF5CA28EF40D, $2BCB5733CB32B111, $2C0116805EFFAEAA,
    $2C355C2076BF9A55, $2C6AB328946F80EA, $2CA0AFF95CC5B092, $2CD4DBF7B3F71CB7,
    $2D0A12F5A0F4E3E5, $2D404BD984990E6F, $2D745ECFE5BF520B, $2DA97683DF2F268E,
    $2DDFD424D6FAF031, $2E13E497065CD61F, $2E48DDBCC7F40BA6, $2E7F152BF9F10E90,
    $2EB36D3B7C36A91A, $2EE8488A5B445360, $2F1E5AACF2156838, $2F52F8AC174D6123,
    $2F87B6D71D20B96C, $2FBDA48CE468E7C7, $2FF286D80EC190DC, $3027288E1271F514,
    $305CF2B1970E7258, $309217AEFE690777, $30C69D9ABE034955, $30FC45016D841BAA,
    $3131AB20E472914A, $316615E91D8F359D, $319B9B6364F30304, $31D1411E1F17E1E3,
    $32059165A6DDDA5B, $323AF5BF109550F2, $3270D9976A5D5297, $32A50FFD44F4A73D,
    $32DA53FC9631D10C, $3310747DDDDF22A8, $3344919D5556EB52, $3379B604AAACA626,
    $33B011C2EAABE7D8, $33E41633A556E1CE, $34191BC08EAC9A42, $344F62B0B257C0D2,
    $34839DAE6F76D883, $34B8851A0B548EA4, $34EEA6608E29B24D, $352327FC58DA0F70,
    $3557F1FB6F10934C, $358DEE7A4AD4B81F, $35C2B50C6EC4F313, $35F7624F8A762FD8,
    $362D3AE36D13BBCE, $366244CE242C5561, $3696D601AD376AB9, $36CC8B8218854567,
    $3701D7314F534B61, $37364CFDA3281E39, $376BE03D0BF225C7, $37A16C262777579C,
    $37D5C72FB1552D84, $380B38FB9DAA78E4, $3841039D428A8B8F, $38754484932D2E72,
    $38AA95A5B7F87A0F, $38E09D8792FB4C49, $3914C4E977BA1F5C, $3949F623D5A8A732,
    $398039D665896880, $39B4484BFEEBC2A0, $39E95A5EFEA6B348, $3A1FB0F6BE506019,
    $3A53CE9A36F23C10, $3A88C240C4AECB14, $3ABEF2D0F5DA7DD9, $3AF357C299A88EA8,
    $3B282DB34012B252, $3B5E392010175EE6, $3B92E3B40A0E9B50, $3BC79CA10C924224,
    $3BFD83C94FB6D2AC, $3C32725DD1D243AC, $3C670EF54646D496, $3C9CD2B297D889BC,
    $3CD203AF9EE75616, $3D06849B86A12B9B, $3D3C25C268497682, $3D719799812DEA11,
    $3DA5FD7FE1796495, $3DDB7CDFD9D7BDBB, $3E112E0BE826D695, $3E45798EE2308C3A,
    $3E7AD7F29ABCAF48, $3EB0C6F7A0B5ED8D, $3EE4F8B588E368F0, $3F1A36E2EB1C432C,
    $3F50624DD2F1A9FC, $3F847AE147AE147B, $3FB999999999999A, $3FF0000000000000,
    $4024000000000000, $4059000000000000, $408F400000000000, $40C3880000000000,
    $40F86A0000000000, $412E848000000000, $416312D000000000, $4197D78400000000,
    $41CDCD6500000000, $4202A05F20000000, $42374876E8000000, $426D1A94A2000000,
    $42A2309CE5400000, $42D6BCC41E900000, $430C6BF526340000, $4341C37937E08000,
    $4376345785D8A000, $43ABC16D674EC800, $43E158E460913D00, $4415AF1D78B58C40,
    $444B1AE4D6E2EF50, $4480F0CF064DD592, $44B52D02C7E14AF6, $44EA784379D99DB4,
    $45208B2A2C280291, $4554ADF4B7320334, $4589D971E4FE8402, $45C027E72F1F1281,
    $45F431E0FAE6D722, $46293E5939A08CEA, $465F8DEF8808B024, $4693B8B5B5056E17,
    $46C8A6E32246C99C, $46FED09BEAD87C04, $4733426172C74D82, $476812F9CF7920E2,
    $479E17B84357691B, $47D2CED32A16A1B1, $48078287F49C4A1E, $483D6329F1C35CA5,
    $48725DFA371A19E7, $48A6F578C4E0A060, $48DCB2D6F618C879, $4911EFC659CF7D4C,
    $49466BB7F0435C9E, $497C06A5EC5433C6, $49B18427B3B4A05C, $49E5E531A0A1C873,
    $4A1B5E7E08CA3A90, $4A511B0EC57E649A, $4A8561D276DDFDC0, $4ABABA4714957D30,
    $4AF0B46C6CDD6E3E, $4B24E1878814C9CE, $4B5A19E96A19FC41, $4B905031E2503DA9,
    $4BC4643E5AE44D13, $4BF97D4DF19D6058, $4C2FDCA16E04B86D, $4C63E9E4E4C2F344,
    $4C98E45E1DF3B016, $4CCF1D75A5709C1B, $4D03726987666191, $4D384F03E93FF9F5,
    $4D6E62C4E38FF872, $4DA2FDBB0E39FB47, $4DD7BD29D1C87A19, $4E0DAC74463A989F,
    $4E428BC8ABE49F64, $4E772EBAD6DDC73C, $4EACFA698C95390C, $4EE21C81F7DD43A7,
    $4F16A3A275D49491, $4F4C4C8B1349B9B5, $4F81AFD6EC0E1411, $4FB61BCCA7119916,
    $4FEBA2BFD0D5FF5B, $502145B7E285BF99, $50559725DB272F7F, $508AFCEF51F0FB5F,
    $50C0DE1593369D1B, $50F5159AF8044462, $512A5B01B605557B, $516078E111C3556D,
    $5194971956342AC8, $51C9BCDFABC1357A, $5200160BCB58C16C, $52341B8EBE2EF1C7,
    $526922726DBAAE39, $529F6B0F092959C7, $52D3A2E965B9D81D, $53088BA3BF284E24,
    $533EAE8CAEF261AD, $53732D17ED577D0C, $53A7F85DE8AD5C4E, $53DDF67562D8B362,
    $5412BA095DC7701E, $5447688BB5394C25, $547D42AEA2879F2E, $54B249AD2594C37D,
    $54E6DC186EF9F45C, $551C931E8AB87173, $5551DBF316B346E8, $558652EFDC6018A2,
    $55BBE7ABD3781ECA, $55F170CB642B133F, $5625CCFE3D35D80E, $565B403DCC834E12,
    $569108269FD210CB, $56C54A3047C694FE, $56FA9CBC59B83A3E, $5730A1F5B8132466,
    $5764CA732617ED80, $5799FD0FEF9DE8E0, $57D03E29F5C2B18C, $58044DB473335DEF,
    $583961219000356B, $586FB969F40042C5, $58A3D3E2388029BB, $58D8C8DAC6A0342A,
    $590EFB1178484135, $59435CEAEB2D28C1, $59783425A5F872F1, $59AE412F0F768FAD,
    $59E2E8BD69AA19CC, $5A17A2ECC414A040, $5A4D8BA7F519C84F, $5A827748F9301D32,
    $5AB7151B377C247E, $5AECDA62055B2D9E, $5B22087D4358FC82, $5B568A9C942F3BA3,
    $5B8C2D43B93B0A8C, $5BC19C4A53C4E697, $5BF6035CE8B6203D, $5C2B843422E3A84C,
    $5C6132A095CE4930, $5C957F48BB41DB7C, $5CCADF1AEA12525B, $5D00CB70D24B7379,
    $5D34FE4D06DE5057, $5D6A3DE04895E46C, $5DA066AC2D5DAEC4, $5DD4805738B51A75,
    $5E09A06D06E26112, $5E400444244D7CAB, $5E7405552D60DBD6, $5EA906AA78B912CC,
    $5EDF485516E7577F, $5F138D352E5096AF, $5F48708279E4BC5B, $5F7E8CA3185DEB72,
    $5FB317E5EF3AB327, $5FE7DDDF6B095FF1, $601DD55745CBB7ED, $6052A5568B9F52F4,
    $60874EAC2E8727B1, $60BD22573A28F19D, $60F2357684599702, $6126C2D4256FFCC3,
    $615C73892ECBFBF4, $6191C835BD3F7D78, $61C63A432C8F5CD6, $61FBC8D3F7B3340C,
    $62315D847AD00088, $6265B4E5998400AA, $629B221EFFE500D4, $62D0F5535FEF2084,
    $630532A837EAE8A6, $633A7F5245E5A2CF, $63708F936BAF85C1, $63A4B378469B6732,
    $63D9E056584240FE, $64102C35F729689F, $6444374374F3C2C6, $647945145230B378,
    $64AF965966BCE056, $64E3BDF7E0360C36, $6518AD75D8438F43, $654ED8D34E547314,
    $6583478410F4C7EC, $65B819651531F9E8, $65EE1FBE5A7E7861, $6622D3D6F88F0B3D,
    $665788CCB6B2CE0C, $668D6AFFE45F818F, $66C262DFEEBBB0FA, $66F6FB97EA6A9D38,
    $672CBA7DE5054486, $6761F48EAF234AD4, $679671B25AEC1D88, $67CC0E1EF1A724EB,
    $680188D357087713, $6835EB082CCA94D7, $686B65CA37FD3A0D, $68A11F9E62FE4448,
    $68D56785FBBDD55A, $690AC1677AAD4AB1, $6940B8E0ACAC4EAF, $6974E718D7D7625A,
    $69AA20DF0DCD3AF1, $69E0548B68A044D6, $6A1469AE42C8560C, $6A498419D37A6B8F,
    $6A7FE52048590673, $6AB3EF342D37A408, $6AE8EB0138858D0A, $6B1F25C186A6F04C,
    $6B537798F4285630, $6B88557F31326BBC, $6BBE6ADEFD7F06AA, $6BF302CB5E6F642A,
    $6C27C37E360B3D35, $6C5DB45DC38E0C82, $6C9290BA9A38C7D2, $6CC734E940C6F9C6,
    $6CFD022390F8B837, $6D3221563A9B7322, $6D66A9ABC9424FEB, $6D9C5416BB92E3E6,
    $6DD1B48E353BCE70, $6E0621B1C28AC20C, $6E3BAA1E332D728F, $6E714A52DFFC6799,
    $6EA59CE797FB8180, $6EDB04217DFA61DF, $6F10E294EEBC7D2C, $6F451B3A2A6B9C76,
    $6F7A6208B5068394, $6FB07D457124123D, $6FE49C96CD6D16CC, $7019C3BC80C85C7E,
    $70501A55D07D39CF, $708420EB449C8843, $70B9292615C3AA54, $70EF736F9B3494E9,
    $7123A825C100DD11, $7158922F31411456, $718EB6BAFD91596B, $71C33234DE7AD7E3,
    $71F7FEC216198DDC, $722DFE729B9FF152, $7262BF07A143F6D4, $72976EC98994F488,
    $72CD4A7BEBFA31AB, $73024E8D737C5F0B, $7336E230D05B76CD, $736C9ABD04725481,
    $73A1E0B622C774D0, $73D658E3AB795204, $740BEF1C9657A686, $74417571DDF6C814,
    $7475D2CE55747A18, $74AB4781EAD1989E, $74E10CB132C2FF63, $75154FDD7F73BF3C,
    $754AA3D4DF50AF0B, $7580A6650B926D67, $75B4CFFE4E7708C0, $75EA03FDE214CAF0,
    $7620427EAD4CFED6, $7654531E58A03E8C, $768967E5EEC84E2F, $76BFC1DF6A7A61BB,
    $76F3D92BA28C7D15, $7728CF768B2F9C5A, $775F03542DFB8370, $779362149CBD3226,
    $77C83A99C3EC7EB0, $77FE494034E79E5C, $7832EDC82110C2F9, $7867A93A2954F3B8,
    $789D9388B3AA30A6, $78D27C35704A5E68, $79071B42CC5CF602, $793CE2137F743382,
    $79720D4C2FA8A031, $79A6909F3B92C83D, $79DC34C70A777A4C, $7A11A0FC668AAC70,
    $7A46093B802D578C, $7A7B8B8A6038AD6F, $7AB137367C236C65, $7AE585041B2C477E,
    $7B1AE64521F7595E, $7B50CFEB353A97DB, $7B8503E602893DD2, $7BBA44DF832B8D46,
    $7BF06B0BB1FB384C, $7C2485CE9E7A065E, $7C59A742461887F6, $7C9008896BCF54FA,
    $7CC40AABC6C32A38, $7CF90D56B873F4C6, $7D2F50AC6690F1F8, $7D63926BC01A973B,
    $7D987706B0213D0A, $7DCE94C85C298C4C, $7E031CFD3999F7B0, $7E37E43C8800759C,
    $7E6DDD4BAA009303, $7EA2AA4F4A405BE2, $7ED754E31CD072DA, $7F0D2A1BE4048F90,
    $7F423A516E82D9BA, $7F76C8E5CA239029, $7FAC7B1F3CAC7433, $7FE1CCF385EBC8A0
  );
  cJsLn10: Double = 2.302585092994046;
  { Interval.ts' safeLimit: more ticks than this and there are none. }
  cSafeTickLimit = 3000;

function TyJsPow10(AExp: Integer): Double;
var q: QWord;
begin
  if (AExp >= Low(cJsPow10)) and (AExp <= High(cJsPow10)) then
  begin
    q := cJsPow10[AExp];
    Move(q, Result, SizeOf(Result));
  end
  else if AExp > 0 then
    Result := Infinity
  else
    Result := 0;
end;

{ Math.floor and Math.ceil. Math.Floor answers a 32-bit Integer here and wraps
  above two thousand million; these stay in the Double the value came in. }
function JsFloor(AValue: Double): Double;
begin
  if IsNan(AValue) or IsInfinite(AValue) then Exit(AValue);
  Result := Int(AValue);
  if Result > AValue then Result := Result - 1;
end;

function JsCeil(AValue: Double): Double;
begin
  if IsNan(AValue) or IsInfinite(AValue) then Exit(AValue);
  Result := Int(AValue);
  if Result < AValue then Result := Result + 1;
end;

{ One 256-bit unsigned integer, least significant word first: the mantissa
  times ten to the twentieth, shifted far enough left to divide into a
  64-bit quotient. }
type
  TJsWide = array[0..7] of LongWord;

procedure WideMulSmall(var AN: TJsWide; AFactor: LongWord);
var i: Integer; t, carry: QWord;
begin
  carry := 0;
  for i := 0 to High(AN) do
  begin
    t := QWord(AN[i]) * AFactor + carry;
    AN[i] := LongWord(t and $FFFFFFFF);
    carry := t shr 32;
  end;
end;

function WideBit(const AN: TJsWide; ABit: Integer): Boolean;
begin
  if (ABit < 0) or (ABit >= 32 * Length(AN)) then Exit(False);
  Result := (AN[ABit div 32] shr (ABit mod 32)) and 1 <> 0;
end;

procedure WideSetBit(var AN: TJsWide; ABit: Integer);
begin
  if (ABit < 0) or (ABit >= 32 * Length(AN)) then Exit;
  AN[ABit div 32] := AN[ABit div 32] or (LongWord(1) shl (ABit mod 32));
end;

function WideBitLen(const AN: TJsWide): Integer;
var i: Integer;
begin
  for i := 32 * Length(AN) - 1 downto 0 do
    if WideBit(AN, i) then Exit(i + 1);
  Result := 0;
end;

{ Adds 2^ABit, which is where the half-up of a right shift by ABit + 1 comes from. }
procedure WideAddBit(var AN: TJsWide; ABit: Integer);
var i: Integer; t, carry: QWord;
begin
  if (ABit < 0) or (ABit >= 32 * Length(AN)) then Exit;
  i := ABit div 32;
  carry := QWord(1) shl (ABit mod 32);
  while (carry <> 0) and (i <= High(AN)) do
  begin
    t := QWord(AN[i]) + carry;
    AN[i] := LongWord(t and $FFFFFFFF);
    carry := t shr 32;
    Inc(i);
  end;
end;

procedure WideShr(var AN: TJsWide; ACount: Integer);
var i, w, b: Integer; lo, hi: QWord;
begin
  if ACount >= 32 * Length(AN) then
  begin
    FillChar(AN, SizeOf(AN), 0);
    Exit;
  end;
  w := ACount div 32;
  b := ACount mod 32;
  for i := 0 to High(AN) do
  begin
    if i + w <= High(AN) then lo := AN[i + w] else lo := 0;
    if i + w + 1 <= High(AN) then hi := AN[i + w + 1] else hi := 0;
    if b = 0 then AN[i] := LongWord(lo)
    else AN[i] := LongWord(((lo shr b) or (hi shl (32 - b))) and $FFFFFFFF);
  end;
end;

function WideCmp(const A, B: TJsWide): Integer;
var i: Integer;
begin
  for i := High(A) downto 0 do
    if A[i] <> B[i] then
    begin
      if A[i] > B[i] then Exit(1) else Exit(-1);
    end;
  Result := 0;
end;

procedure WideSub(var A: TJsWide; const B: TJsWide);
var i: Integer; t: Int64; borrow: Int64;
begin
  borrow := 0;
  for i := 0 to High(A) do
  begin
    t := Int64(A[i]) - Int64(B[i]) - borrow;
    if t < 0 then
    begin
      t := t + (Int64(1) shl 32);
      borrow := 1;
    end
    else
      borrow := 0;
    A[i] := LongWord(t);
  end;
end;

procedure WideShl1(var AN: TJsWide);
var i: Integer;
begin
  for i := High(AN) downto 1 do
    AN[i] := (AN[i] shl 1) or (AN[i - 1] shr 31);
  AN[0] := AN[0] shl 1;
end;

{ ANum / ADen as the nearest Double, a tie going to the even mantissa -- what
  Number() gives the decimal text of the quotient, without reading any text.
  The quotient is taken to 64 bits or more by long division, and whether
  anything was left over decides the ties. }
function WideDivToDouble(const ANum, ADen: TJsWide): Double;
var
  q, r, top: TJsWide;
  ln, ld, s, i, lq, sh, k: Integer;
  mant: QWord;
  lower, up: Boolean;
begin
  ln := WideBitLen(ANum);
  ld := WideBitLen(ADen);
  if ln = 0 then Exit(0);
  s := 64 + ld - ln;
  if s < 0 then s := 0;
  FillChar(q, SizeOf(q), 0);
  FillChar(r, SizeOf(r), 0);
  { ANum shifted left by s, one bit at a time into the remainder }
  for i := ln - 1 + s downto 0 do
  begin
    WideShl1(r);
    if (i >= s) and WideBit(ANum, i - s) then r[0] := r[0] or 1;
    if WideCmp(r, ADen) >= 0 then
    begin
      WideSub(r, ADen);
      WideSetBit(q, i);
    end;
  end;
  lq := WideBitLen(q);
  sh := lq - 53;
  top := q;
  WideShr(top, sh);
  mant := (QWord(top[1]) shl 32) or top[0];
  lower := False;
  for k := 0 to sh - 2 do
    if WideBit(q, k) then
    begin
      lower := True;
      Break;
    end;
  for k := 0 to High(r) do
    if r[k] <> 0 then lower := True;
  { Past half, or on it with an odd mantissa. (A carry to 2^53 needs no
    renormalising: 2^53 is an exact Double, and so is its power of two.) }
  up := WideBit(q, sh - 1) and (lower or Odd(mant));
  if up then Inc(mant);
  Result := Ldexp(Double(mant), sh - s);
end;

{ x = m * 2^e for a finite, non-negative x: m under 2^53, e from -1074. }
procedure SplitDouble(AValue: Double; out AMant: QWord; out AExp: Integer);
var bits: QWord;
begin
  bits := 0;
  Move(AValue, bits, SizeOf(bits));
  AExp := Integer((bits shr 52) and $7FF);
  AMant := bits and QWord($000FFFFFFFFFFFFF);
  if AExp = 0 then AExp := -1074
  else
  begin
    AMant := AMant or (QWord(1) shl 52);
    AExp := AExp - 1075;
  end;
end;

{ n = the integer nearest x * 10^p, a tie going up, exactly, for x from 0 to
  under 1e21. A fraction: (m*10^p + 2^(k-1)) shifted right by k. A whole
  number: m shifted left by e, times 10^p -- under 2^70 times 10^20. }
procedure FixedDigits(AAbs: Double; APrecision: Integer; out AN: TJsWide);
var m: QWord; e, i: Integer;
begin
  SplitDouble(AAbs, m, e);
  FillChar(AN, SizeOf(AN), 0);
  AN[0] := LongWord(m and $FFFFFFFF);
  AN[1] := LongWord(m shr 32);
  if e >= 0 then
  begin
    for i := 1 to e do WideShl1(AN);
    for i := 1 to APrecision do WideMulSmall(AN, 10);
  end
  else
  begin
    for i := 1 to APrecision do WideMulSmall(AN, 10);
    WideAddBit(AN, -e - 1);
    WideShr(AN, -e);
  end;
end;

function WideIsZero(const AN: TJsWide): Boolean;
var i: Integer;
begin
  for i := 0 to High(AN) do
    if AN[i] <> 0 then Exit(False);
  Result := True;
end;

{ The decimal digits, most significant first; '0' for zero. }
function WideToDecimal(AN: TJsWide): string;
var i: Integer; rem, t: QWord;
begin
  Result := '';
  repeat
    rem := 0;
    for i := High(AN) downto 0 do
    begin
      t := (rem shl 32) or AN[i];
      AN[i] := LongWord(t div 10);
      rem := t mod 10;
    end;
    Result := Char(Ord('0') + rem) + Result;
  until WideIsZero(AN);
end;

function TyJsToFixed(AValue: Double; APrecision: Integer): Double;
var
  x: Double;
  m: QWord;
  e, i: Integer;
  neg: Boolean;
  n, den: TJsWide;
begin
  if IsNan(AValue) or IsInfinite(AValue) then Exit(AValue);
  if APrecision < 0 then APrecision := 0;
  if APrecision > 20 then APrecision := 20;
  { A NEGATIVE IS ROUNDED AS ITS MAGNITUDE, the sign put back afterwards --
    the specification's order, and why a half goes away from zero. }
  neg := AValue < 0;
  x := Abs(AValue);
  SplitDouble(x, m, e);
  { With e at or above zero x is a whole number, and a whole number is its
    own toFixed. That covers toFixed's own give-up too -- anything from 1e21
    up comes back as the number itself -- which is why there is no separate
    test for it: every Double that large is whole. }
  if (e >= 0) or (m = 0) then Exit(AValue);
  FixedDigits(x, APrecision, n);
  { BACK TO A DOUBLE, correctly rounded, and never through FPC's Val, which
    is not: read that way, 22 of 276,712 answers came back a unit in the last
    place out. Under 2^53 both n and 10^p are exact Doubles and one IEEE
    division rounds once -- the long division below gives the same answer
    there, only slower. Longer answers go through it. }
  if (n[7] = 0) and (n[6] = 0) and (n[5] = 0) and (n[4] = 0) and (n[3] = 0)
    and (n[2] = 0) and (n[1] < $200000) then
    Result := ((QWord(n[1]) shl 32) or n[0]) / TyJsPow10(APrecision)
  else
  begin
    FillChar(den, SizeOf(den), 0);
    den[0] := 1;
    for i := 1 to APrecision do WideMulSmall(den, 10);
    Result := WideDivToDouble(n, den);
  end;
  if neg then Result := -Result;
end;

function TyJsToFixedStr(AValue: Double; APrecision: Integer): string;
var n: TJsWide;
begin
  if IsNan(AValue) then Exit('NaN');
  if APrecision < 0 then APrecision := 0;
  if APrecision > 20 then APrecision := 20;
  { toFixed hands anything this large to ToString -- 'Infinity' included. }
  if Abs(AValue) >= 1e21 then Exit(TyJsNumberToString(AValue));
  FixedDigits(Abs(AValue), APrecision, n);
  Result := WideToDecimal(n);
  while Length(Result) <= APrecision do Result := '0' + Result;
  if APrecision > 0 then
    Insert('.', Result, Length(Result) - APrecision + 1);
  { THE SIGN FROM x < 0, which -0 is not and -0.001 is, whatever the
    digits came to. }
  if AValue < 0 then Result := '-' + Result;
end;

{ ---- Number::toString, exactly ---- }

type
  { An unsigned integer of any size, least significant word first, no
    leading zero words. For a Double's decimal digits: a denormal is a
    thousand bits below one, and 10^17 more on top. }
  TJsBig = array of LongWord;

procedure BigTrim(var A: TJsBig);
var n: Integer;
begin
  n := Length(A);
  while (n > 0) and (A[n - 1] = 0) do Dec(n);
  SetLength(A, n);
end;

function BigOf(AValue: QWord): TJsBig;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := LongWord(AValue and $FFFFFFFF);
  Result[1] := LongWord(AValue shr 32);
  BigTrim(Result);
end;

procedure BigMulSmall(var A: TJsBig; AFactor: LongWord);
var i: Integer; t, carry: QWord;
begin
  carry := 0;
  for i := 0 to High(A) do
  begin
    t := QWord(A[i]) * AFactor + carry;
    A[i] := LongWord(t and $FFFFFFFF);
    carry := t shr 32;
  end;
  if carry <> 0 then
  begin
    SetLength(A, Length(A) + 1);
    A[High(A)] := LongWord(carry);
  end;
end;

procedure BigMulPow10(var A: TJsBig; AExp: Integer);
begin
  while AExp >= 9 do
  begin
    BigMulSmall(A, 1000000000);
    Dec(AExp, 9);
  end;
  while AExp > 0 do
  begin
    BigMulSmall(A, 10);
    Dec(AExp);
  end;
end;

procedure BigShl(var A: TJsBig; ACount: Integer);
var w, b, i: Integer; r: TJsBig;
begin
  if (ACount <= 0) or (Length(A) = 0) then Exit;
  w := ACount div 32;
  b := ACount mod 32;
  r := nil;
  SetLength(r, Length(A) + w + 1);
  for i := 0 to High(r) do r[i] := 0;
  for i := 0 to High(A) do
  begin
    r[i + w] := r[i + w] or LongWord((QWord(A[i]) shl b) and $FFFFFFFF);
    if b > 0 then r[i + w + 1] := LongWord(QWord(A[i]) shr (32 - b));
  end;
  BigTrim(r);
  A := r;
end;

function BigCmp(const A, B: TJsBig): Integer;
var i: Integer;
begin
  if Length(A) <> Length(B) then
  begin
    if Length(A) > Length(B) then Exit(1) else Exit(-1);
  end;
  for i := High(A) downto 0 do
    if A[i] <> B[i] then
    begin
      if A[i] > B[i] then Exit(1) else Exit(-1);
    end;
  Result := 0;
end;

{ A := A - B, with A >= B. }
procedure BigSub(var A: TJsBig; const B: TJsBig);
var i: Integer; t, borrow: Int64;
begin
  borrow := 0;
  for i := 0 to High(A) do
  begin
    t := Int64(A[i]) - borrow;
    if i <= High(B) then t := t - Int64(B[i]);
    if t < 0 then
    begin
      t := t + (Int64(1) shl 32);
      borrow := 1;
    end
    else
      borrow := 0;
    A[i] := LongWord(t);
  end;
  BigTrim(A);
end;

function BigBitLen(const A: TJsBig): Integer;
var top: LongWord;
begin
  if Length(A) = 0 then Exit(0);
  Result := 32 * (Length(A) - 1);
  top := A[High(A)];
  while top <> 0 do
  begin
    Inc(Result);
    top := top shr 1;
  end;
end;

{ ANum div ADen for a quotient under 2^62; ANum is left holding the
  remainder. }
function BigDivSmall(var ANum: TJsBig; const ADen: TJsBig): QWord;
var j: Integer; t: TJsBig;
begin
  Result := 0;
  j := BigBitLen(ANum) - BigBitLen(ADen);
  if j > 61 then j := 61;
  while j >= 0 do
  begin
    t := Copy(ADen);
    BigShl(t, j);
    if BigCmp(t, ANum) <= 0 then
    begin
      BigSub(ANum, t);
      Result := Result or (QWord(1) shl j);
    end;
    Dec(j);
  end;
end;

{ Is m * 2^e at least 10^t? }
function AtLeastPow10(AMant: QWord; AExp, ATen: Integer): Boolean;
var a, b: TJsBig;
begin
  a := BigOf(AMant);
  if AExp > 0 then BigShl(a, AExp);
  if ATen < 0 then BigMulPow10(a, -ATen);
  b := BigOf(1);
  if AExp < 0 then BigShl(b, -AExp);
  if ATen > 0 then BigMulPow10(b, ATen);
  Result := BigCmp(a, b) >= 0;
end;

function TyJsNumberToString(AValue: Double): string;
var
  m, lowBound, qf, qc, q: QWord;
  e, n, k, t, c, nnf, nnc, nn: Integer;
  num, den, rem2: TJsBig;
  okF, okC: Boolean;
  digits: string;

  { Does q * 10^(ANn-k) read back as x? A candidate that rounded up to 10^k
    is one digit of the next power instead -- 10 at one digit is 1 at the
    next place -- and ANn moves with it. The check is against the two bounds,
    in units of 2^(e-2): x is 4m, the upper bound 4m + 2, the lower one 4m - 2,
    or 4m - 1 at the bottom of a binade, where the spacing below halves. A
    bound itself reads back as x only when m is even. }
  function ReadsBack(var AQ: QWord; var ANn: Integer): Boolean;
  var
    a, bh, bl: TJsBig;
    lim: QWord;
    i, tt, ch, cl: Integer;
  begin
    lim := 1;
    for i := 1 to k do lim := lim * 10;
    if AQ = lim then
    begin
      AQ := lim div 10;
      Inc(ANn);
    end;
    tt := ANn - k;
    a := BigOf(AQ);
    if tt > 0 then BigMulPow10(a, tt);
    if 2 - e > 0 then BigShl(a, 2 - e);
    bh := BigOf(4 * m + 2);
    bl := BigOf(lowBound);
    if tt < 0 then
    begin
      BigMulPow10(bh, -tt);
      BigMulPow10(bl, -tt);
    end;
    if e - 2 > 0 then
    begin
      BigShl(bh, e - 2);
      BigShl(bl, e - 2);
    end;
    ch := BigCmp(a, bh);
    cl := BigCmp(a, bl);
    Result := ((ch < 0) or ((ch = 0) and not Odd(m)))
      and ((cl > 0) or ((cl = 0) and not Odd(m)));
  end;

begin
  if IsNan(AValue) then Exit('NaN');
  if AValue = 0 then Exit('0');
  if AValue < 0 then Exit('-' + TyJsNumberToString(-AValue));
  if IsInfinite(AValue) then Exit('Infinity');
  SplitDouble(AValue, m, e);
  { n, the decimal exponent: 10^(n-1) <= x < 10^n. The logarithm is a
    guess; the integers settle it. }
  n := Floor(Log10(AValue)) + 1;
  while not AtLeastPow10(m, e, n - 1) do Dec(n);
  while AtLeastPow10(m, e, n) do Inc(n);
  if (m = QWord(1) shl 52) and (e > -1074) then lowBound := 4 * m - 1
  else lowBound := 4 * m - 2;
  for k := 1 to 17 do
  begin
    { THE TWO k-DIGIT DECIMALS EITHER SIDE OF x, not only the nearer one.
      At the bottom of a binade the interval that reads back as x is lopsided
      -- a quarter of a spacing below, a half above -- and the nearer decimal
      can fall outside it while the farther one, above, is inside:
      2^-1015 is 7.120236347223045e-307, not the seventeen digits the nearer
      one forces. The shortest length wins; at that length, the one nearer
      x, a tie to the even one. }
    t := k - n;
    num := BigOf(m);
    if e > 0 then BigShl(num, e);
    if t > 0 then BigMulPow10(num, t);
    den := BigOf(1);
    if e < 0 then BigShl(den, -e);
    if t < 0 then BigMulPow10(den, -t);
    qf := BigDivSmall(num, den);
    rem2 := Copy(num);
    BigShl(rem2, 1);
    c := BigCmp(rem2, den);
    nnf := n;
    okF := ReadsBack(qf, nnf);
    okC := False;
    qc := qf;
    nnc := n;
    if Length(num) > 0 then
    begin
      qc := qf + 1;
      okC := ReadsBack(qc, nnc);
    end;
    if not (okF or okC) then Continue;
    if okF and okC then
    begin
      if (c < 0) or ((c = 0) and not Odd(qf)) then okC := False
      else okF := False;
    end;
    if okF then
    begin
      q := qf;
      nn := nnf;
    end
    else
    begin
      q := qc;
      nn := nnc;
    end;
    digits := IntToStr(q);
    { Number::toString's layout, by where the point falls. }
    if (Length(digits) <= nn) and (nn <= 21) then
      Result := digits + StringOfChar('0', nn - Length(digits))
    else if (0 < nn) and (nn <= 21) then
      Result := Copy(digits, 1, nn) + '.' + Copy(digits, nn + 1, MaxInt)
    else if (-6 < nn) and (nn <= 0) then
      Result := '0.' + StringOfChar('0', -nn) + digits
    else
    begin
      if Length(digits) = 1 then Result := digits
      else Result := digits[1] + '.' + Copy(digits, 2, MaxInt);
      if nn - 1 >= 0 then Result := Result + 'e+' + IntToStr(nn - 1)
      else Result := Result + 'e-' + IntToStr(1 - nn);
    end;
    Exit;
  end;
  { Seventeen digits always read back; this is not reached. }
  Result := FloatToStr(AValue);
end;

function TyJsAddCommas(const AText: string): string;
var
  dot, i, j, runStart, runLen: Integer;
  head: string;
begin
  dot := Pos('.', AText);
  if dot > 0 then head := Copy(AText, 1, dot - 1) else head := AText;
  Result := '';
  i := 1;
  while i <= Length(head) do
  begin
    if head[i] in ['0'..'9'] then
    begin
      runStart := i;
      while (i <= Length(head)) and (head[i] in ['0'..'9']) do Inc(i);
      runLen := i - runStart;
      for j := 0 to runLen - 1 do
      begin
        if (j > 0) and ((runLen - j) mod 3 = 0) then Result := Result + ',';
        Result := Result + head[runStart + j];
      end;
    end
    else
    begin
      Result := Result + head[i];
      Inc(i);
    end;
  end;
  if dot > 0 then Result := Result + Copy(AText, dot, MaxInt);
end;

function TyQuantityExponent(AValue: Double): Integer;
var e: Double;
begin
  if IsNan(AValue) or IsInfinite(AValue) or (AValue <= 0) then Exit(0);
  e := JsFloor(TyJsLog(AValue) / cJsLn10);
  if IsNan(e) or IsInfinite(e) then Exit(0);
  Result := Trunc(e);
  { The logarithm lands a hair under an exact power often enough that
    upstream checks: log(1000)/LN10 is 2.9999999999999996. }
  if AValue / TyJsPow10(Result) >= 10 then Inc(Result);
end;

function TyNice(AValue: Double; ARound: Boolean): Double;
var
  expo: Integer;
  exp10, f, nf: Double;
begin
  expo := TyQuantityExponent(AValue);
  exp10 := TyJsPow10(expo);
  f := AValue / exp10;
  if ARound then
  begin
    if f < 1.5 then nf := 1
    else if f < 2.5 then nf := 2
    else if f < 4 then nf := 3
    else if f < 7 then nf := 5
    else nf := 10;
  end
  else
  begin
    if f < 1 then nf := 1
    else if f < 2 then nf := 2
    else if f < 3 then nf := 3
    else if f < 5 then nf := 5
    else nf := 10;
  end;
  { And snapped to the decimal it means: 3 x 0.1 is 0.30000000000000004. }
  Result := TyJsToFixed(nf * exp10, -expo);
end;

{ getPrecisionSafe: the decimals of the value's own ToString, less its
  exponent -- '1.5e-7' has one decimal and an exponent of -7, so eight. Only
  reached for a value the counting loop cannot settle: a negative one, or one
  under 1e-14. It went through FPC's Str and Val before, and disagreed with
  upstream on 28 of 60,011 random Doubles. }
function GetPrecisionSafe(AValue: Double): Integer;
var
  s: string;
  ePos, dot, sigLen, ex, code: Integer;
begin
  s := LowerCase(TyJsNumberToString(AValue));
  ePos := Pos('e', s);
  ex := 0;
  if ePos > 0 then
  begin
    Val(Copy(s, ePos + 1, MaxInt), ex, code);
    if code <> 0 then ex := 0;
    sigLen := ePos - 1;
  end
  else
    sigLen := Length(s);
  dot := Pos('.', s);
  if (dot = 0) or (dot > sigLen) then Result := 0
  else Result := sigLen - dot;
  Result := Max(0, Result - ex);
end;

function TyGetPrecision(AValue: Double): Integer;
var
  e: Double;
  i: Integer;
begin
  if IsNan(AValue) then Exit(0);
  if AValue > 1e-14 then
  begin
    e := 1;
    for i := 0 to 14 do
    begin
      if TyJsRound(AValue * e) / e = AValue then Exit(i);
      e := e * 10;
    end;
  end;
  Result := GetPrecisionSafe(AValue);
end;

function TyIntervalPrecision(AInterval: Double): Integer;
begin
  { "Two more digits for tick", upstream's own words and nothing more. }
  Result := TyGetPrecision(AInterval) + 2;
end;

function TyDrawnTicks(AScale: TTyScale): TTyScaleTickArray;
begin
  if (AScale = nil) or AScale.Blank then Exit(nil);
  Result := AScale.GetTicks;
end;

function TyLabelPrecision(AKind: TTyLabelPrecisionKind;
  ADigits: Double): TTyLabelPrecision;
begin
  Result.Kind := AKind;
  Result.Digits := ADigits;
end;

function TyScaleValueLabel(AScale: TTyScale; AValue: Double;
  const APrecision: TTyLabelPrecision): string;
var p: Integer; d: Double;
begin
  case APrecision.Kind of
    lpAuto:
      if AScale is TTyIntervalScale then
        p := TTyIntervalScale(AScale).IntervalPrecision
      else
        p := TyGetPrecision(AValue);
    lpDigits:
      begin
        d := APrecision.Digits;
        { upstream's round: not a number prints the value's ToString;
          otherwise clamped to 0..20, and toFixed drops the fraction. }
        if IsNan(d) then Exit(TyJsAddCommas(TyJsNumberToString(AValue)));
        if d < 0 then d := 0;
        if d > 20 then d := 20;
        p := Trunc(d);
      end;
    lpNotANumber:
      Exit(TyJsAddCommas(TyJsNumberToString(AValue)));
  else
    { a tick's own decimals -- getPrecision(value) || 0. Not-a-number and
      the infinities come out of it as nought, and toFixed prints them as
      ToString does whatever the precision. }
    p := TyGetPrecision(AValue);
  end;
  Result := TyJsAddCommas(TyJsToFixedStr(AValue, p));
end;

function TyValidSplitNumber(ARaw: Double; ADefault: Integer): Integer;
begin
  { `raw || default`, then round(max(it, 1)). Zero and not-a-number are the
    default; 2.5 is three. }
  if IsNan(ARaw) or (ARaw = 0) then ARaw := ADefault;
  if IsInfinite(ARaw) then ARaw := ADefault;
  ARaw := TyJsRound(Math.Max(ARaw, Double(1)));
  if ARaw > High(Integer) then Exit(High(Integer));
  Result := Trunc(ARaw);
end;

constructor TTyIntervalScale.Create;
begin
  inherited Create;
  FInterval := 1;
  FIntervalPrecision := 2;
  FNiceStart := 0;
  FNiceStop := 1;
  FStubStart := 0;
  FStubStop := 1;
  FNiced := False;
  FNicedExtent := TyRange(0, 1);
  FFixMin := False;
  FFixMax := False;
end;

function TTyIntervalScale.StillNiced: Boolean;
var e: TTyRange;
begin
  { Niceify's answer holds only while nobody has set another extent since. }
  if not FNiced then Exit(False);
  e := GetExtent;
  Result := (e.Start = FNicedExtent.Start) and (e.Stop = FNicedExtent.Stop);
end;

{ THE STEP WALKS IN LOG SPACE ON A LOG AXIS ONLY. A break decorator
  transforms too, but upstream nices a broken axis in value space -- on the
  span with the breaks taken out, which this port does not do yet -- and
  treating its collapsed space as decades put ticks past the extent and out
  of order. }
function TTyIntervalScale.LogWarped: Boolean;
begin
  Result := FLogRule and (FMapper <> nil) and FMapper.NeedTransform;
end;

function TTyIntervalScale.StubExtent: TTyRange;
var
  e: TTyRange;
  a, b: Double;
begin
  { THE SPACE THE STEP WALKS IN. The same as the extent on a linear axis;
    decades on a log one, and there the values Niceify left are kept rather
    than recomputed, because the logarithm of a power is not always the
    exponent it came from. }
  if StillNiced then Exit(TyRange(FStubStart, FStubStop));
  e := GetExtent;
  if LogWarped then
  begin
    a := FMapper.TransformIn(e.Start);
    b := FMapper.TransformIn(e.Stop);
    Exit(TyRange(a, b));
  end;
  Result := e;
end;

procedure TTyIntervalScale.Niceify(ASplitNumber: Double;
  AUserInterval: Double);
var mask: TFPUExceptionMask;
begin
  { JavaScript's arithmetic, not-a-number and all: a step that toFixed
    rounded to nothing divides by zero, and upstream carries the result on
    rather than stopping. }
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide]);
  try
    NiceifyJs(ASplitNumber, AUserInterval);
  finally
    ClearExceptions(False);
    {$IFDEF CPUX86_64}
    { And the SSE flags, which ClearExceptions leaves standing on this CPU. }
    SetMXCSR(GetMXCSR and not LongWord($3F));
    {$ENDIF}
    SetExceptionMask(mask);
  end;
end;

procedure TTyIntervalScale.NiceifyJs(ASplitNumber: Double;
  AUserInterval: Double);
var
  e, oldE: TTyRange;
  warped, hasUser: Boolean;
  lo, hi, span, iv, autoIv, h, a, b, err, powLo, powHi, vLo, vHi: Double;
  prec, autoPrec, split: Integer;
begin
  hasUser := not IsNan(AUserInterval);
  oldE := GetExtent;
  e := oldE;

  { IN THE MAPPER'S OWN SPACE. A log axis nices its decades, and nicing it in
    raw value space put the step above the low end, floored that end to 0,
    and made TransformIn(0) NaN -- after which every value landed mid-plot. }
  warped := LogWarped;
  if warped then
  begin
    { NOT through TyRange: a log of zero is not-a-number, and TyRange orders
      its pair by comparing it. The validation below sorts what it keeps. }
    a := FMapper.TransformIn(e.Start);
    b := FMapper.TransformIn(e.Stop);
    lo := a;
    hi := b;
  end
  else
  begin
    lo := e.Start;
    hi := e.Stop;
  end;
  a := lo;
  b := hi;

  { intervalScaleEnsureValidExtent, verbatim. A FLAT extent opens by half its
    own size -- on the low side only when the top is pinned, which keeps a
    written max where it was written. Zero opens to [0, 1]. An end that is not
    a number, or not finite, gives up on both: [0, 1]. }
  { (Tested for a number FIRST: comparing a not-a-number raises here, and a
    broken end can never have been equal to anything, so the order changes
    nothing upstream would see.) }
  if IsNan(lo) or IsNan(hi) or IsInfinite(lo) or IsInfinite(hi) then
  begin
    lo := 0;
    hi := 1;
  end
  else if lo = hi then
  begin
    if lo <> 0 then
    begin
      h := Abs(lo);
      if not FFixMax then
      begin
        hi := hi + h / 2;
        lo := lo - h / 2;
      end
      else
        lo := lo - h / 2;
    end
    { Upstream's helper asks ctnShp here and nothing else -- not min, not
      max: `min: 0, max: 0` still opens both ways. }
    else if FContainShape then
    begin
      lo := -1;
      hi := 1;
    end
    else
      hi := 1;
  end;
  if hi < lo then
  begin
    h := lo;
    lo := hi;
    hi := h;
  end;
  vLo := lo;
  vHi := hi;
  span := hi - lo;

  if FLogRule then
  begin
    { A LOG AXIS DOES NOT NICE. Its step is a whole number of decades --
      quantity(span), and ten of those when that would leave half the ticks
      asked for -- and minInterval / maxInterval are not read. The fallback
      split is ten here, upstream's, though the option's own default of five
      almost always arrives first. }
    split := TyValidSplitNumber(ASplitNumber, 10);
    iv := Math.Max(TyJsPow10(TyQuantityExponent(span)), Double(1));
    err := split / span * iv;
    if err <= 0.5 then iv := iv * 10;
  end
  else
  begin
    split := TyValidSplitNumber(ASplitNumber, 5);
    { nice(span / splitNumber, round): 1, 2, 3, 5 or 10 of a power of ten. }
    iv := TyNice(span / split, True);
    if (FMinInterval > 0) and (iv < FMinInterval) then iv := FMinInterval;
    if (FMaxInterval > 0) and (iv > FMaxInterval) then iv := FMaxInterval;
  end;
  prec := TyIntervalPrecision(iv);
  { THE NICE TICKS LIE INSIDE THE EXTENT, from the extent as validated and
    before it is rounded outwards -- which is why a pinned end that is no
    multiple of the step becomes a tick of its own, first or last. }
  FNiceStart := TyJsToFixed(JsCeil(lo / iv) * iv, prec);
  FNiceStop := TyJsToFixed(JsFloor(hi / iv) * iv, prec);
  autoIv := iv;
  autoPrec := prec;

  { AN EXPLICIT `interval` STEPS THE TICKS AND NOTHING ELSE. The extent is
    still rounded to the step upstream would have picked -- its own comment
    calls it historical -- and the ticks walk the whole of it. }
  if hasUser then
  begin
    iv := AUserInterval;
    prec := TyIntervalPrecision(iv);
  end;
  if not FFixMin then lo := TyJsToFixed(JsFloor(lo / autoIv) * autoIv, autoPrec);
  if not FFixMax then hi := TyJsToFixed(JsCeil(hi / autoIv) * autoIv, autoPrec);
  { A STEP OF NOTHING ROUNDS AN END TO NOT-A-NUMBER, and upstream's setExtent
    skips a not-a-number end -- the extent stays as validated. Values under
    1e-20 or so get here: toFixed stops at twenty places, and the step they
    would need is finer than that. }
  if IsNan(lo) then lo := vLo;
  if IsNan(hi) then hi := vHi;
  if hasUser then
  begin
    FNiceStart := lo;
    FNiceStop := hi;
  end;
  FInterval := iv;
  FIntervalPrecision := prec;
  FStubStart := lo;
  FStubStop := hi;
  FNiced := True;

  if warped then
  begin
    { AN END NICING DID NOT MOVE KEEPS THE VALUE IT CAME IN AS: 10^log10(3)
      is 2.9999999999999996 here, and a written min shown that way is a bug
      report. Upstream's lookup, which holds for any end and not only a
      pinned one: data from 10.000000000000002 keeps that as its first tick
      and does not become a round 10. }
    powLo := FMapper.TransformOut(lo);
    powHi := FMapper.TransformOut(hi);
    if (not IsNan(a)) and (lo = a) then powLo := oldE.Start;
    if (not IsNan(b)) and (hi = b) then powHi := oldE.Stop;
    SetExtent(TyRange(powLo, powHi));
  end
  else
    SetExtent(TyRange(lo, hi));
  FNicedExtent := GetExtent;
end;

procedure TTyIntervalScale.Niceify(ASplitNumber: Double);
begin
  Niceify(ASplitNumber, NaN);
end;

function TTyIntervalScale.Normalize(AValue: Double): Double;
var t: Double;
begin
  if not (LogWarped and StillNiced and not FMapper.HasExtent(sekMapping)) then
    Exit(inherited Normalize(AValue));
  if FStubStop = FStubStart then Exit(0.5);
  t := FMapper.TransformIn(AValue);
  Result := (t - FStubStart) / (FStubStop - FStubStart);
end;

function TTyIntervalScale.LinearExtent2(AKind: TTyScaleExtentKind): TTyRange;
begin
  { THE DECADES THE NICE STEP LEFT, while nothing has set another extent and
    no mapping extent was asked for -- a mapping one upstream takes through
    the logarithm, as setExtent2 does }
  if LogWarped and StillNiced
    and ((AKind = sekEffective) or not FMapper.HasExtent(sekMapping)) then
  begin
    Result.Start := FStubStart;
    Result.Stop := FStubStop;
    Exit;
  end;
  Result := inherited LinearExtent2(AKind);
end;

function TTyIntervalScale.Denormalize(ANorm: Double): Double;
begin
  if not (LogWarped and StillNiced and not FMapper.HasExtent(sekMapping)) then
    Exit(inherited Denormalize(ANorm));
  Result := FMapper.TransformOut(FStubStart + ANorm * (FStubStop - FStubStart));
end;

{ One tick value back in value space: a log axis' decades go out as powers,
  and the two ends as the extent itself (upstream's lookup), so a pinned end
  reads back as written. }
function TTyIntervalScale.StubToValue(AValue: Double): Double;
var e: TTyRange;
begin
  if not LogWarped then Exit(AValue);
  e := GetExtent;
  if StillNiced then
  begin
    if AValue = FStubStart then Exit(e.Start);
    if AValue = FStubStop then Exit(e.Stop);
  end;
  Result := FMapper.TransformOut(AValue);
end;

function TTyIntervalScale.StubTicks(AExpand: Boolean): TTyDoubleArray;
var
  e: TTyRange;
  n: Integer;
  tick, iv, last: Double;
  prec: Integer;

  procedure Push(AValue: Double);
  begin
    if n > High(Result) then SetLength(Result, n * 2 + 8);
    Result[n] := AValue;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  iv := FInterval;
  prec := FIntervalPrecision;
  { An interval of nothing is no ticks -- upstream's first line. }
  if IsNan(iv) or (iv = 0) then Exit;
  e := StubExtent;
  if IsNan(e.Start) or IsNan(e.Stop) or IsInfinite(e.Start)
    or IsInfinite(e.Stop) then Exit;
  if not StillNiced then
  begin
    FNiceStart := TyJsToFixed(JsCeil(e.Start / iv) * iv, prec);
    FNiceStop := TyJsToFixed(JsFloor(e.Stop / iv) * iv, prec);
  end;
  if e.Start < FNiceStart then
  begin
    if AExpand then Push(TyJsToFixed(FNiceStart - iv, prec))
    else Push(e.Start);
  end;
  tick := FNiceStart;
  while True do
  begin
    if IsNan(tick) or IsInfinite(tick) or IsNan(FNiceStop)
      or IsInfinite(FNiceStop) or (tick > FNiceStop) then Break;
    Push(tick);
    tick := TyJsToFixed(tick + iv, prec);
    { Past the precision a Double can carry the step adds nothing. }
    if tick = Result[n - 1] then Break;
    if n > cSafeTickLimit then
    begin
      Result := nil;
      Exit;
    end;
  end;
  if n > 0 then last := Result[n - 1] else last := FNiceStop;
  if e.Stop > last then
  begin
    if AExpand then Push(TyJsToFixed(last + iv, prec))
    else Push(e.Stop);
  end;
  SetLength(Result, n);
end;

function TTyIntervalScale.GetTicks: TTyScaleTickArray;
var
  majors, wide: TTyDoubleArray;
  minors: TTyDoubleArray;
  e: TTyRange;
  i, k, n, m, split, mprec: Integer;
  prev, next, miv, v: Double;
  nm: Integer;

  procedure AddMinor(AValue: Double);
  begin
    if nm > High(minors) then SetLength(minors, nm * 2 + 8);
    minors[nm] := AValue;
    Inc(nm);
  end;

begin
  Result := nil;
  majors := StubTicks(False);
  n := Length(majors);
  if n = 0 then Exit;

  { MINOR TICKS SPLIT EACH GAP OF THE WIDENED LIST -- the first and last
    majors pushed out to the multiples beyond a pinned end -- and keep only
    what falls strictly inside the extent. A pinned min of 3 still gets the
    minors at 4, 8, 12, 16 before the first multiple of twenty. In VALUE
    space, on a log axis too: upstream spaces them linearly between powers. }
  nm := 0;
  minors := nil;
  split := FMinorSplit;
  if split >= 2 then
  begin
    wide := StubTicks(True);
    e := GetExtent;
    for i := 1 to High(wide) do
    begin
      prev := StubToValue(wide[i - 1]);
      next := StubToValue(wide[i]);
      miv := (next - prev) / split;
      mprec := TyIntervalPrecision(miv);
      for k := 0 to split - 2 do
      begin
        v := TyJsToFixed(prev + (k + 1) * miv, mprec);
        if (v > e.Start) and (v < e.Stop) then AddMinor(v);
      end;
    end;
  end;

  SetLength(Result, n + nm);
  i := 0;
  k := 0;
  m := 0;
  { ONE ARRAY IN VALUE ORDER, majors and minors merged. They never meet:
    minors sit strictly between two widened majors. }
  while (i < n) or (k < nm) do
  begin
    if (k >= nm) or ((i < n) and (StubToValue(majors[i]) <= minors[k])) then
    begin
      Result[m] := Default(TTyScaleTick);
      Result[m].Value := StubToValue(majors[i]);
      Result[m].Level := 0;
      Inc(i);
    end
    else
    begin
      Result[m] := Default(TTyScaleTick);
      Result[m].Value := minors[k];
      Result[m].Level := 1;
      Inc(k);
    end;
    Inc(m);
  end;
  SetLength(Result, m);
end;

{ ============================ TTyTimeScale ============================ }

constructor TTyTimeScale.Create;
begin
  inherited Create;
  FSplitNumber := 6;
  FUTC := False;
end;

function TTyTimeScale.GetTicks: TTyScaleTickArray;
var
  e: TTyRange;
  t: TTyTimeTickArray;
  i: Integer;
begin
  Result := nil;
  e := GetExtent;
  t := TyTimeTicks(e.Start, e.Stop, FSplitNumber, FUTC, MinInterval, MaxInterval);
  SetLength(Result, Length(t));
  for i := 0 to High(t) do
  begin
    Result[i].Value := t[i].Value;
    { EVERY TIME TICK IS A MAJOR. There is no such thing as a minor tick on a
      time axis: a year marker among days is not a subdivision of anything,
      it is the coarsest tick there is. }
    Result[i].Level := 0;
    Result[i].OffInterval := False;
    Result[i].TimeLevel := t[i].Level;
    Result[i].TimeUnit := t[i].Unit_;
    Result[i].NotNice := t[i].NotNice;
  end;
end;

end.
