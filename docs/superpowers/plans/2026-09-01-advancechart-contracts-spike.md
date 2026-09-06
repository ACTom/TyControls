# TTyAdvanceChart 契约验证 spike —— 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用可编译、可测的代码验证 `docs/superpowers/specs/2026-09-01-advancechart-tier0.md` §2 的两个契约成立且不贵——若这一趟超过一个 L，对标 ECharts 6.1 的经济账翻转，应改回对标 v5。

**Architecture:** 四个纯单元，无句柄、不引用 `Controls`、可 headless 测。
契约 ① 落在 `ITyCoordSys.DataToLayout` + `ITyBoxContainer`；
契约 ② 落在 `ITyScaleMapper` 的 `TransformIn`/`TransformOut` 链 + 两种 extent，断轴做成**装饰器**。
判据是 spec §8 的第 3、4、5、6 条——尤其第 5 条：**断轴装上之后，Interval/Log 的既有测试一条都不用改。**

**Tech Stack:** Free Pascal 3.2.2 / Lazarus / fpcunit。分支 `feat/advancechart`。
测试跑法：`cd tests && /d/lazarus/lazbuild.exe tytests.lpi && ./tytests.exe --all --format=plain --sparse`。
基线：**6331 个测试，0 错 0 败**。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `source/tyControls.AdvChart.Types.pas` | 双精度点/矩形/区间 + NaN 语义。不依赖 Types/Math 以外任何东西 |
| `source/tyControls.AdvChart.Scale.pas` | `ITyScaleMapper`（Linear / Log / Break 三个同构实现）+ `TTyScale` 抽象 + `TTyIntervalScale` |
| `source/tyControls.AdvChart.Coord.pas` | `ITyAxis` + `ITyCoordSys` + `TTyCartesian2D` |
| `source/tyControls.AdvChart.Layout.pas` | `ITyBoxContainer` + 盒布局求解器 |
| `tests/test.advchart.types.pas` | Types 的不变量 |
| `tests/test.advchart.scale.pas` | mapper 链、两种 extent、nice 刻度 |
| `tests/test.advchart.scale.break.pas` | **契约 ② 的判据**：断轴装饰器装上后原有断言全成立 |
| `tests/test.advchart.coord.pas` | **契约 ① 的判据**：DataToPoint/PointToData 往返、DataToLayout 与锚点一致 |
| `tests/test.advchart.layout.pas` | **契约 ① 另一半的判据**：两种容器来源走同一条路径 |

四个单元只加进 `tests/tytests.lpr`，**本 spike 不碰 `tycontrols.lpk`**——包注册是机器级全局的（仓库记忆 `parallel-agent-worktree-hazards`），等 Tier 0 全部落地再一次性入包。

---

## Task 1: AdvChart.Types —— 双精度几何基元

**Files:**
- Create: `source/tyControls.AdvChart.Types.pas`
- Create: `tests/test.advchart.types.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test.advchart.types.pas`：

```pascal
unit test.advchart.types;
{$mode objfpc}{$H+}
{ Headless tests for the AdvChart geometry primitives. Everything here is pure
  arithmetic on records -- no control, no handle, no painter. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, tyControls.AdvChart.Types;
type
  TAdvChartTypesTest = class(TTestCase)
  published
    procedure TestRangeNormalisesReversedInput;
    procedure TestRangeSpanIsNonNegative;
    procedure TestRangeContainsBothEnds;
    procedure TestRectFWidthHeight;
    procedure TestRectFContainsIsHalfOpen;
    procedure TestInvalidPointIsNaN;
    procedure TestInvalidRectIsNotValid;
    procedure TestValidRectIsValid;
    procedure TestRectWithNaNIsNotValid;
  end;
implementation

procedure TAdvChartTypesTest.TestRangeNormalisesReversedInput;
var r: TTyRange;
begin
  r := TyRange(10, 2);
  AssertEquals('start', 2.0, r.Start, 1e-12);
  AssertEquals('stop', 10.0, r.Stop, 1e-12);
end;

procedure TAdvChartTypesTest.TestRangeSpanIsNonNegative;
begin
  AssertEquals('reversed span', 8.0, TyRangeSpan(TyRange(10, 2)), 1e-12);
  AssertEquals('degenerate span', 0.0, TyRangeSpan(TyRange(5, 5)), 1e-12);
end;

procedure TAdvChartTypesTest.TestRangeContainsBothEnds;
var r: TTyRange;
begin
  r := TyRange(2, 10);
  AssertTrue('low end', TyRangeContains(r, 2));
  AssertTrue('high end', TyRangeContains(r, 10));
  AssertTrue('middle', TyRangeContains(r, 6));
  AssertFalse('below', TyRangeContains(r, 1.999));
  AssertFalse('above', TyRangeContains(r, 10.001));
end;

procedure TAdvChartTypesTest.TestRectFWidthHeight;
var r: TTyRectF;
begin
  r := TyRectF(10, 20, 110, 70);
  AssertEquals('width', 100.0, TyRectFWidth(r), 1e-12);
  AssertEquals('height', 50.0, TyRectFHeight(r), 1e-12);
end;

procedure TAdvChartTypesTest.TestRectFContainsIsHalfOpen;
var r: TTyRectF;
begin
  r := TyRectF(0, 0, 10, 10);
  AssertTrue('top-left corner is in', TyRectFContains(r, TyPointF(0, 0)));
  AssertTrue('inside', TyRectFContains(r, TyPointF(5, 5)));
  { Half-open on the far edges so adjacent bands never both claim a pixel --
    the same rule the hit-test will rely on when bars sit shoulder to shoulder. }
  AssertFalse('right edge is out', TyRectFContains(r, TyPointF(10, 5)));
  AssertFalse('bottom edge is out', TyRectFContains(r, TyPointF(5, 10)));
end;

procedure TAdvChartTypesTest.TestInvalidPointIsNaN;
var p: TTyPointF;
begin
  p := TyInvalidPointF;
  AssertTrue('x is NaN', IsNan(p.X));
  AssertTrue('y is NaN', IsNan(p.Y));
end;

procedure TAdvChartTypesTest.TestInvalidRectIsNotValid;
begin
  AssertFalse('invalid rect', TyRectFIsValid(TyInvalidRectF));
end;

procedure TAdvChartTypesTest.TestValidRectIsValid;
begin
  AssertTrue('ordinary rect', TyRectFIsValid(TyRectF(0, 0, 10, 10)));
  AssertTrue('zero-area rect is still valid', TyRectFIsValid(TyRectF(5, 5, 5, 5)));
  AssertFalse('reversed rect is not valid', TyRectFIsValid(TyRectF(10, 0, 0, 10)));
end;

procedure TAdvChartTypesTest.TestRectWithNaNIsNotValid;
var r: TTyRectF;
begin
  r := TyRectF(0, 0, 10, 10);
  r.Right := NaN;
  AssertFalse('NaN edge', TyRectFIsValid(r));
end;

initialization
  RegisterTest(TAdvChartTypesTest);
end.
```

- [ ] **Step 2: 把测试单元挂进 runner，跑一次确认它编译失败**

在 `tests/tytests.lpr` 的 uses 里，`test.chart,` 那一行之后加上：

```pascal
  test.advchart.types,
```

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -5`
Expected: FAIL —— `Can't find unit tyControls.AdvChart.Types`

- [ ] **Step 3: 写最小实现**

创建 `source/tyControls.AdvChart.Types.pas`：

```pascal
unit tyControls.AdvChart.Types;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- shared geometry primitives.

  DOUBLE, not Single. The whole geometry layer is double precision because a
  coordinate round trip (value -> px -> value) has to survive data ranges that
  span many decades; Single loses that at about seven digits, and the round-trip
  tolerance this layer promises is 0.5 px on any extent. Rounding to device
  integers is the PAINTER's job, at the last moment.

  This unit is PURE: Types and Math only. No Controls, no Graphics, no handle.
  Everything below is headless-testable by construction. }
interface
uses SysUtils, Math;

type
  TTyDoubleArray = array of Double;

  { A point in device px, relative to the control's top-left. }
  TTyPointF = record X, Y: Double; end;

  { A rect in device px. Left<=Right and Top<=Bottom is an INVARIANT that
    TyRectFIsValid checks -- it is not enforced by the constructor, because a
    reversed rect is a real signal (an axis whose band collapsed) that callers
    must be able to see rather than have silently normalised away. }
  TTyRectF = record Left, Top, Right, Bottom: Double; end;

  { A closed value range. TyRange DOES normalise, because a reversed VALUE range
    is always a caller mistake -- an inverse axis is expressed by the pixel
    extent being reversed, never by the value extent. }
  TTyRange = record Start, Stop: Double; end;

function TyPointF(AX, AY: Double): TTyPointF;
function TyRectF(ALeft, ATop, ARight, ABottom: Double): TTyRectF;
function TyRange(AStart, AStop: Double): TTyRange;

function TyRectFWidth(const AR: TTyRectF): Double;
function TyRectFHeight(const AR: TTyRectF): Double;
{ Valid = no NaN on any edge AND non-reversed. A zero-area rect IS valid. }
function TyRectFIsValid(const AR: TTyRectF): Boolean;
{ Half-open on Right/Bottom so two adjacent bands never both claim a pixel. }
function TyRectFContains(const AR: TTyRectF; const AP: TTyPointF): Boolean;

function TyRangeSpan(const AR: TTyRange): Double;
{ Closed on both ends -- an axis extent's endpoints belong to the axis. }
function TyRangeContains(const AR: TTyRange; AValue: Double): Boolean;

{ The single spelling of "no answer". Never return an empty/zero rect for this:
  a zero rect at the origin is indistinguishable from a legitimately collapsed
  band, and that ambiguity is what TyChartNoHit had to exist to avoid. }
function TyInvalidPointF: TTyPointF;
function TyInvalidRectF: TTyRectF;

implementation

function TyPointF(AX, AY: Double): TTyPointF;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function TyRectF(ALeft, ATop, ARight, ABottom: Double): TTyRectF;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

function TyRange(AStart, AStop: Double): TTyRange;
begin
  if AStop < AStart then
  begin
    Result.Start := AStop;
    Result.Stop := AStart;
  end
  else
  begin
    Result.Start := AStart;
    Result.Stop := AStop;
  end;
end;

function TyRectFWidth(const AR: TTyRectF): Double;
begin
  Result := AR.Right - AR.Left;
end;

function TyRectFHeight(const AR: TTyRectF): Double;
begin
  Result := AR.Bottom - AR.Top;
end;

function TyRectFIsValid(const AR: TTyRectF): Boolean;
begin
  Result := (not IsNan(AR.Left)) and (not IsNan(AR.Top))
        and (not IsNan(AR.Right)) and (not IsNan(AR.Bottom))
        and (AR.Right >= AR.Left) and (AR.Bottom >= AR.Top);
end;

function TyRectFContains(const AR: TTyRectF; const AP: TTyPointF): Boolean;
begin
  Result := (AP.X >= AR.Left) and (AP.X < AR.Right)
        and (AP.Y >= AR.Top) and (AP.Y < AR.Bottom);
end;

function TyRangeSpan(const AR: TTyRange): Double;
begin
  Result := Abs(AR.Stop - AR.Start);
end;

function TyRangeContains(const AR: TTyRange; AValue: Double): Boolean;
begin
  Result := (AValue >= AR.Start) and (AValue <= AR.Stop);
end;

function TyInvalidPointF: TTyPointF;
begin
  Result.X := NaN;
  Result.Y := NaN;
end;

function TyInvalidRectF: TTyRectF;
begin
  Result.Left := NaN;
  Result.Top := NaN;
  Result.Right := NaN;
  Result.Bottom := NaN;
end;

end.
```

- [ ] **Step 4: 编译并跑，确认通过**

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -4 && ./tytests.exe --suite=TAdvChartTypesTest --format=plain`
Expected: `N:9 E:0 F:0`

- [ ] **Step 5: 提交**

```bash
git add source/tyControls.AdvChart.Types.pas tests/test.advchart.types.pas tests/tytests.lpr && git commit -m "feat(advchart): double-precision geometry primitives"
```

---

## Task 2: ScaleMapper —— TransformIn/Out 链与两种 extent

契约 ② 的一半。`Normalize`/`Denormalize` **在基类上实现一次**，只有 `TransformIn`/`TransformOut` 是虚的——这是 Log 与 Break 能同构的原因，也是 scale 子类永远不需要知道 break 的原因。

**Files:**
- Create: `source/tyControls.AdvChart.Scale.pas`
- Create: `tests/test.advchart.scale.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test.advchart.scale.pas`：

```pascal
unit test.advchart.scale;
{$mode objfpc}{$H+}
{ Headless tests for the scale mapper chain and the two-kind extent.
  These tests must keep passing UNCHANGED after the break decorator lands in
  test.advchart.scale.break -- that is the acceptance criterion for contract 2
  (spec section 8 item 5). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale;
type
  TAdvChartMapperTest = class(TTestCase)
  published
    procedure TestLinearNormalizeEnds;
    procedure TestLinearNormalizeMidpoint;
    procedure TestLinearRoundTrip;
    procedure TestLinearDegenerateExtentIsHalf;
    procedure TestLinearNeedsNoTransform;
    procedure TestLogNormalizeEnds;
    procedure TestLogNormalizeIsLogarithmic;
    procedure TestLogRoundTrip;
    procedure TestLogNeedsTransform;
    procedure TestContainRespectsEffectiveExtent;
    procedure TestMappingExtentAbsentByDefault;
    procedure TestMappingExtentDrivesNormalize;
    procedure TestEffectiveExtentStillDrivesContain;
  end;
implementation

const
  Eps = 1e-9;

procedure TAdvChartMapperTest.TestLinearNormalizeEnds;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(0, 100));
  AssertEquals('start', 0.0, m.Normalize(0), Eps);
  AssertEquals('stop', 1.0, m.Normalize(100), Eps);
end;

procedure TAdvChartMapperTest.TestLinearNormalizeMidpoint;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(-50, 50));
  AssertEquals('midpoint', 0.5, m.Normalize(0), Eps);
end;

procedure TAdvChartMapperTest.TestLinearRoundTrip;
var m: ITyScaleMapper; i: Integer; v: Double;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(-13.5, 987.25));
  for i := 0 to 20 do
  begin
    v := -13.5 + (987.25 + 13.5) * i / 20;
    AssertEquals('round trip', v, m.Denormalize(m.Normalize(v)), 1e-9);
  end;
end;

procedure TAdvChartMapperTest.TestLinearDegenerateExtentIsHalf;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(7, 7));
  { A zero span must not divide. 0.5 (the band centre) is the only answer that
    keeps a single-datum chart drawing in the middle instead of at an edge. }
  AssertEquals('degenerate', 0.5, m.Normalize(7), Eps);
  AssertEquals('degenerate off-value', 0.5, m.Normalize(99), Eps);
end;

procedure TAdvChartMapperTest.TestLinearNeedsNoTransform;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  AssertFalse('linear is identity', m.NeedTransform);
end;

procedure TAdvChartMapperTest.TestLogNormalizeEnds;
var m: ITyScaleMapper;
begin
  m := TTyLogScaleMapper.Create(10);
  m.SetExtent(sekEffective, TyRange(1, 1000));
  AssertEquals('start', 0.0, m.Normalize(1), Eps);
  AssertEquals('stop', 1.0, m.Normalize(1000), Eps);
end;

procedure TAdvChartMapperTest.TestLogNormalizeIsLogarithmic;
var m: ITyScaleMapper;
begin
  m := TTyLogScaleMapper.Create(10);
  m.SetExtent(sekEffective, TyRange(1, 1000));
  { 10 is one decade of three -> exactly a third of the way along. }
  AssertEquals('one decade', 1/3, m.Normalize(10), 1e-9);
  AssertEquals('two decades', 2/3, m.Normalize(100), 1e-9);
end;

procedure TAdvChartMapperTest.TestLogRoundTrip;
var m: ITyScaleMapper; i: Integer; v: Double;
begin
  m := TTyLogScaleMapper.Create(10);
  m.SetExtent(sekEffective, TyRange(0.5, 5000));
  for i := 0 to 20 do
  begin
    v := 0.5 * Power(10000, i / 20);
    AssertEquals('round trip', v, m.Denormalize(m.Normalize(v)), Abs(v) * 1e-9 + 1e-12);
  end;
end;

procedure TAdvChartMapperTest.TestLogNeedsTransform;
var m: ITyScaleMapper;
begin
  m := TTyLogScaleMapper.Create(10);
  AssertTrue('log is not identity', m.NeedTransform);
end;

procedure TAdvChartMapperTest.TestContainRespectsEffectiveExtent;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(0, 10));
  AssertTrue('inside', m.Contain(5));
  AssertTrue('on the low end', m.Contain(0));
  AssertTrue('on the high end', m.Contain(10));
  AssertFalse('outside', m.Contain(10.5));
end;

procedure TAdvChartMapperTest.TestMappingExtentAbsentByDefault;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(0, 10));
  AssertFalse('no mapping extent yet', m.HasExtent(sekMapping));
end;

procedure TAdvChartMapperTest.TestMappingExtentDrivesNormalize;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(0, 10));
  { containShape: widen the MAPPING extent so a bar at value 10 keeps its half
    width inside the plot band. Normalize must follow the wider one... }
  m.SetExtent(sekMapping, TyRange(-1, 11));
  AssertTrue('mapping extent present', m.HasExtent(sekMapping));
  AssertEquals('0 is no longer at the start', 1/12, m.Normalize(0), Eps);
  AssertEquals('10 is no longer at the stop', 11/12, m.Normalize(10), Eps);
end;

procedure TAdvChartMapperTest.TestEffectiveExtentStillDrivesContain;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(0, 10));
  m.SetExtent(sekMapping, TyRange(-1, 11));
  { ...but ticks, labels, splitLines and hit-testing must stay on the EFFECTIVE
    extent, or a widened axis grows phantom ticks at -1 and 11. }
  AssertFalse('below effective', m.Contain(-0.5));
  AssertFalse('above effective', m.Contain(10.5));
  AssertTrue('effective end', m.Contain(10));
end;

initialization
  RegisterTest(TAdvChartMapperTest);
end.
```

- [ ] **Step 2: 挂进 runner，跑一次确认编译失败**

在 `tests/tytests.lpr` 的 `test.advchart.types,` 之后加：

```pascal
  test.advchart.scale,
```

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -5`
Expected: FAIL —— `Can't find unit tyControls.AdvChart.Scale`

- [ ] **Step 3: 写最小实现**

创建 `source/tyControls.AdvChart.Scale.pas`（本 Task 只到 mapper 为止，`TTyScale` 在 Task 3 加）：

```pascal
unit tyControls.AdvChart.Scale;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the scale layer.

  CONTRACT 2 (spec section 2). A scale's value->[0,1] mapping may be piecewise
  discontinuous. Rather than special-case that in every scale subclass, the
  mapping is delegated to an ITyScaleMapper whose ONLY virtual pair is

      TransformIn  : own value space -> an inner (ultimately linear) space
      TransformOut : the inverse

  Normalize/Denormalize are implemented ONCE on the base in terms of that pair.
  The consequence is that a logarithmic axis and a broken axis are the SAME
  mechanism -- ECharts reaches the same conclusion in scale/scaleMapper.ts:198-201
  ("some features (such as LogScale, axis breaks) transform values from their own
  spaces into linear space"). A scale subclass never mentions breaks, and the
  break decorator never mentions Interval or Log.

  TWO EXTENTS, not one (ECharts scale/scaleMapper.ts:33-68, new in 6.1):
    sekEffective -- always present. Ticks, labels, splitLine, contain, hit-test.
    sekMapping   -- present only when set. Widened from the effective ends so a
                    shape drawn AT an end (a bar's half width, a candlestick's
                    body) stays inside the plot band. Only Normalize/Denormalize
                    and axisPointer use it.
  Getting this wrong is not a missing option, it is a different extent model:
  axis.containShape and axis.dataMin/dataMax both rest on it.

  PURE: no Controls, no Graphics, no handle. }
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
      mapping extent is set). Returns 0.5 on a degenerate span -- never divides. }
    function Normalize(AValue: Double): Double;
    function Denormalize(ANorm: Double): Double;
    { Against the EFFECTIVE extent, always -- see the unit header. }
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

  { Identity. NeedTransform is False so the fast path skips the calls. }
  TTyLinearScaleMapper = class(TTyScaleMapperBase)
  public
    function NeedTransform: Boolean; override;
  end;

  { Logarithmic. Non-positive values have no image and map to NaN -- the caller
    (the data layer) is responsible for excluding them, which is exactly what
    ECharts 6.1 started doing automatically ("automatically exclude non-positive
    series data values on log axis"). }
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

end.
```

- [ ] **Step 4: 编译并跑，确认通过**

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -4 && ./tytests.exe --suite=TAdvChartMapperTest --format=plain`
Expected: `N:13 E:0 F:0`

- [ ] **Step 5: 提交**

```bash
git add source/tyControls.AdvChart.Scale.pas tests/test.advchart.scale.pas tests/tytests.lpr && git commit -m "feat(advchart): scale mapper chain with a two-kind extent"
```

---

## Task 3: TTyIntervalScale —— nice 刻度

**Files:**
- Modify: `source/tyControls.AdvChart.Scale.pas`
- Modify: `tests/test.advchart.scale.pas`

- [ ] **Step 1: 写失败的测试**

在 `tests/test.advchart.scale.pas` 里，`TAdvChartMapperTest` 的 `end;` 之后、`implementation` 之前，加一个新类：

```pascal
  TAdvChartIntervalScaleTest = class(TTestCase)
  private
    function StepMantissaIsNice(AStep: Double): Boolean;
  published
    procedure TestNiceContainsData;
    procedure TestNiceStepMantissa;
    procedure TestNiceTickCountNearSplitNumber;
    procedure TestNiceFlatExtentDoesNotDivide;
    procedure TestTicksAreAscendingAndUnique;
    procedure TestFixedMinIsRespected;
    procedure TestStartValueIsIndependentOfMin;
    procedure TestScaleUsesItsMapper;
  end;
```

并在 implementation 段末尾（`initialization` 之前）加实现：

```pascal
{ ---------------------- TAdvChartIntervalScaleTest ---------------------- }

function TAdvChartIntervalScaleTest.StepMantissaIsNice(AStep: Double): Boolean;
var m: Double;
begin
  if AStep <= 0 then Exit(False);
  m := AStep / Power(10, Floor(Log10(AStep)));
  Result := (Abs(m - 1) < 1e-9) or (Abs(m - 2) < 1e-9)
         or (Abs(m - 2.5) < 1e-9) or (Abs(m - 5) < 1e-9);
end;

procedure TAdvChartIntervalScaleTest.TestNiceContainsData;
var s: TTyIntervalScale; e: TTyRange;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(3.7, 91.2));
    s.Niceify(5);
    e := s.GetExtent;
    AssertTrue('nice min <= data min', e.Start <= 3.7 + 1e-9);
    AssertTrue('nice max >= data max', e.Stop >= 91.2 - 1e-9);
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestNiceStepMantissa;
var s: TTyIntervalScale; i: Integer;
begin
  for i := 1 to 40 do
  begin
    s := TTyIntervalScale.Create;
    try
      s.SetExtent(TyRange(0, i * 3.3));
      s.Niceify(5);
      AssertTrue('step mantissa for i=' + IntToStr(i) + ' step=' + FloatToStr(s.Interval),
                 StepMantissaIsNice(s.Interval));
    finally
      s.Free;
    end;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestNiceTickCountNearSplitNumber;
var s: TTyIntervalScale; n: Integer;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(0, 100));
    s.Niceify(5);
    n := Length(s.GetTicks);
    { A "nice" range trades exactness for round numbers, so the count is
      approximate by design -- but it must stay in a band a reader would call
      five-ish, not collapse to 2 or explode to 20. }
    AssertTrue('tick count ' + IntToStr(n) + ' is in [3,9]', (n >= 3) and (n <= 9));
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestNiceFlatExtentDoesNotDivide;
var s: TTyIntervalScale; e: TTyRange;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(42, 42));
    s.Niceify(5);
    e := s.GetExtent;
    AssertTrue('flat extent was expanded', TyRangeSpan(e) > 0);
    AssertTrue('interval is positive', s.Interval > 0);
    AssertTrue('the value is still inside', TyRangeContains(e, 42));
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestTicksAreAscendingAndUnique;
var s: TTyIntervalScale; t: TTyScaleTickArray; i: Integer;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(-17.3, 4.9));
    s.Niceify(6);
    t := s.GetTicks;
    AssertTrue('at least two ticks', Length(t) >= 2);
    for i := 1 to High(t) do
      AssertTrue('strictly ascending at ' + IntToStr(i), t[i].Value > t[i - 1].Value);
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestFixedMinIsRespected;
var s: TTyIntervalScale;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(3.7, 91.2));
    s.FixMin := True;
    s.Niceify(5);
    AssertEquals('a pinned min is not rounded away', 3.7, s.GetExtent.Start, 1e-9);
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestStartValueIsIndependentOfMin;
var s: TTyIntervalScale;
begin
  { ECharts 6.1 decoupled startValue from min (break B7). Build the extent model
    with them independent from day one, or the scale gets reworked later. }
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(0, 100));
    s.StartValue := 20;
    AssertEquals('extent start is untouched', 0.0, s.GetExtent.Start, 1e-12);
    AssertEquals('startValue stands on its own', 20.0, s.StartValue, 1e-12);
    AssertTrue('and it is flagged as set', s.HasStartValue);
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestScaleUsesItsMapper;
var s: TTyIntervalScale;
begin
  { The scale must go THROUGH its mapper, never compute normalisation itself --
    this is what lets Task 4 swap a break decorator in without touching it. }
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(0, 100));
    AssertEquals('midpoint via mapper', 0.5, s.Normalize(50), 1e-12);
    s.Mapper := TTyLogScaleMapper.Create(10);
    s.SetExtent(TyRange(1, 1000));
    AssertEquals('one decade after the swap', 1/3, s.Normalize(10), 1e-9);
  finally
    s.Free;
  end;
end;
```

并在 `initialization` 段加上：

```pascal
  RegisterTest(TAdvChartIntervalScaleTest);
```

- [ ] **Step 2: 跑一次确认失败**

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -5`
Expected: FAIL —— `Identifier not found "TTyIntervalScale"`

- [ ] **Step 3: 写实现**

在 `source/tyControls.AdvChart.Scale.pas` 的 interface 段，`TTyLogScaleMapper` 声明之后加：

```pascal
  { One axis tick. Level 0 = major (labelled, splitLine), 1 = minor. }
  TTyScaleTick = record
    Value: Double;
    Level: Integer;
  end;
  TTyScaleTickArray = array of TTyScaleTick;

  { Base for every scale. Owns a mapper and delegates all mapping to it -- a
    scale subclass must NEVER compute a normalisation itself, because that is
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
      scale subclass knowing. Assigning carries the extents across. }
    property Mapper: ITyScaleMapper read FMapper write FMapper;
    { ECharts 6.1 break B7: startValue is NOT min. It is a viewport hint that
      dataZoom and axisPointer read; it never moves the extent. }
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
```

在 implementation 段末尾（`end.` 之前）加：

```pascal
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
  value; otherwise the next one up. Heckbert's nice numbers, with 2.5 added --
  it is what makes a 0..250 axis step by 50 instead of 100. }
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
      magnitude so a chart of a single 42 does not get a 0..1 axis. }
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
  { Count first, then fill: a float accumulator would drift, so every tick is
    computed from the index. }
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
```

- [ ] **Step 4: 编译并跑，确认通过**

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -4 && ./tytests.exe --suite=TAdvChartIntervalScaleTest --format=plain`
Expected: `N:8 E:0 F:0`

- [ ] **Step 5: 提交**

```bash
git add source/tyControls.AdvChart.Scale.pas tests/test.advchart.scale.pas && git commit -m "feat(advchart): interval scale with nice ticks, startValue independent of min"
```

---

## Task 4: 断轴装饰器 —— 契约 ② 的判据

这一 Task 的**成败判据不是新测试变绿，而是 Task 2/3 的 21 个测试一个字都不用改**。

**Files:**
- Modify: `source/tyControls.AdvChart.Scale.pas`
- Create: `tests/test.advchart.scale.break.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test.advchart.scale.break.pas`：

```pascal
unit test.advchart.scale.break;
{$mode objfpc}{$H+}
{ CONTRACT 2 ACCEPTANCE (spec section 8 item 5).

  The point of these tests is not that breaks work -- it is that they were added
  WITHOUT touching TTyIntervalScale, TTyLinearScaleMapper or TTyLogScaleMapper,
  and without changing a single assertion in test.advchart.scale. If a future
  change to breaks forces an edit in those files, the decorator design has
  failed and the retrofit cost this spike was run to avoid has arrived anyway. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale;
type
  TAdvChartBreakTest = class(TTestCase)
  private
    function LinearWithBreak: ITyScaleMapper;
  published
    procedure TestNoBreaksIsIdenticalToInner;
    procedure TestBreakCollapsesItsRange;
    procedure TestOutsideBreakIsStillMonotonic;
    procedure TestEndsStillNormalizeToZeroAndOne;
    procedure TestRoundTripOutsideBreak;
    procedure TestValueInsideBreakLandsInTheGap;
    procedure TestTwoBreaksAccumulate;
    procedure TestBreakOnLogInnerMapper;
    procedure TestScaleAcceptsBreakDecoratorWithoutKnowingIt;
    procedure TestExpandedBreakBehavesLikeNoBreak;
  end;
implementation

const
  Eps = 1e-9;

function TAdvChartBreakTest.LinearWithBreak: ITyScaleMapper;
var
  inner: ITyScaleMapper;
  brk: TTyBreakScaleMapper;
begin
  inner := TTyLinearScaleMapper.Create;
  inner.SetExtent(sekEffective, TyRange(0, 100));
  brk := TTyBreakScaleMapper.Create(inner);
  { Collapse 20..80 -- 60 % of the axis -- down to 5 % of the visual span. }
  brk.AddBreak(TyRange(20, 80), 0.05);
  Result := brk;
end;

procedure TAdvChartBreakTest.TestNoBreaksIsIdenticalToInner;
var inner, brk: ITyScaleMapper; i: Integer; v: Double;
begin
  inner := TTyLinearScaleMapper.Create;
  inner.SetExtent(sekEffective, TyRange(0, 100));
  brk := TTyBreakScaleMapper.Create(TTyLinearScaleMapper.Create);
  brk.SetExtent(sekEffective, TyRange(0, 100));
  for i := 0 to 20 do
  begin
    v := i * 5;
    AssertEquals('a break-free decorator is transparent at ' + FloatToStr(v),
                 inner.Normalize(v), brk.Normalize(v), Eps);
  end;
end;

procedure TAdvChartBreakTest.TestBreakCollapsesItsRange;
var m: ITyScaleMapper; before, after: Double;
begin
  m := LinearWithBreak;
  before := m.Normalize(20);
  after := m.Normalize(80);
  { 60 real units now occupy 5 % of the axis. }
  AssertEquals('collapsed span', 0.05, after - before, Eps);
end;

procedure TAdvChartBreakTest.TestOutsideBreakIsStillMonotonic;
var m: ITyScaleMapper; i: Integer; prev, cur: Double;
begin
  m := LinearWithBreak;
  prev := -1;
  for i := 0 to 100 do
  begin
    cur := m.Normalize(i);
    AssertTrue('monotonic at ' + IntToStr(i), cur >= prev - Eps);
    prev := cur;
  end;
end;

procedure TAdvChartBreakTest.TestEndsStillNormalizeToZeroAndOne;
var m: ITyScaleMapper;
begin
  m := LinearWithBreak;
  AssertEquals('start', 0.0, m.Normalize(0), Eps);
  AssertEquals('stop', 1.0, m.Normalize(100), Eps);
end;

procedure TAdvChartBreakTest.TestRoundTripOutsideBreak;
var m: ITyScaleMapper; i: Integer; v: Double;
begin
  m := LinearWithBreak;
  for i := 0 to 19 do
  begin
    v := i;
    AssertEquals('low side round trip', v, m.Denormalize(m.Normalize(v)), 1e-7);
  end;
  for i := 81 to 100 do
  begin
    v := i;
    AssertEquals('high side round trip', v, m.Denormalize(m.Normalize(v)), 1e-7);
  end;
end;

procedure TAdvChartBreakTest.TestValueInsideBreakLandsInTheGap;
var m: ITyScaleMapper; n: Double;
begin
  m := LinearWithBreak;
  n := m.Normalize(50);
  AssertTrue('inside the gap, above its start', n >= m.Normalize(20) - Eps);
  AssertTrue('inside the gap, below its end', n <= m.Normalize(80) + Eps);
end;

procedure TAdvChartBreakTest.TestTwoBreaksAccumulate;
var inner: ITyScaleMapper; brk: TTyBreakScaleMapper; m: ITyScaleMapper;
begin
  inner := TTyLinearScaleMapper.Create;
  inner.SetExtent(sekEffective, TyRange(0, 100));
  brk := TTyBreakScaleMapper.Create(inner);
  brk.AddBreak(TyRange(10, 30), 0.02);
  brk.AddBreak(TyRange(60, 90), 0.02);
  m := brk;
  AssertEquals('start', 0.0, m.Normalize(0), Eps);
  AssertEquals('stop', 1.0, m.Normalize(100), Eps);
  AssertEquals('first gap', 0.02, m.Normalize(30) - m.Normalize(10), Eps);
  AssertEquals('second gap', 0.02, m.Normalize(90) - m.Normalize(60), Eps);
end;

procedure TAdvChartBreakTest.TestBreakOnLogInnerMapper;
var inner: ITyScaleMapper; brk: TTyBreakScaleMapper; m: ITyScaleMapper;
begin
  { Breaks compose with ANY inner mapper -- that is the whole point of the
    TransformIn/TransformOut chain. On a log axis the break collapses a decade. }
  inner := TTyLogScaleMapper.Create(10);
  inner.SetExtent(sekEffective, TyRange(1, 10000));
  brk := TTyBreakScaleMapper.Create(inner);
  brk.AddBreak(TyRange(10, 100), 0.05);
  m := brk;
  AssertEquals('start', 0.0, m.Normalize(1), Eps);
  AssertEquals('stop', 1.0, m.Normalize(10000), Eps);
  AssertEquals('one collapsed decade', 0.05, m.Normalize(100) - m.Normalize(10), Eps);
end;

procedure TAdvChartBreakTest.TestScaleAcceptsBreakDecoratorWithoutKnowingIt;
var s: TTyIntervalScale; brk: TTyBreakScaleMapper;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(0, 100));
    s.Niceify(5);
    brk := TTyBreakScaleMapper.Create(s.Mapper);
    brk.AddBreak(TyRange(20, 80), 0.05);
    s.Mapper := brk;
    { TTyIntervalScale contains no reference to breaks whatsoever, yet: }
    AssertEquals('collapsed', 0.05, s.Normalize(80) - s.Normalize(20), Eps);
    AssertTrue('ticks still generate', Length(s.GetTicks) >= 3);
  finally
    s.Free;
  end;
end;

procedure TAdvChartBreakTest.TestExpandedBreakBehavesLikeNoBreak;
var inner: ITyScaleMapper; brk: TTyBreakScaleMapper; m: ITyScaleMapper;
begin
  { A break the user clicked open must map exactly as if it were absent --
    otherwise the expand animation would not land where the expanded axis draws. }
  inner := TTyLinearScaleMapper.Create;
  inner.SetExtent(sekEffective, TyRange(0, 100));
  brk := TTyBreakScaleMapper.Create(inner);
  brk.AddBreak(TyRange(20, 80), 0.05);
  brk.SetBreakExpanded(0, True);
  m := brk;
  AssertEquals('expanded midpoint', 0.5, m.Normalize(50), Eps);
  AssertEquals('expanded quarter', 0.2, m.Normalize(20), Eps);
end;

initialization
  RegisterTest(TAdvChartBreakTest);
end.
```

- [ ] **Step 2: 挂进 runner，跑一次确认失败**

在 `tests/tytests.lpr` 的 `test.advchart.scale,` 之后加：

```pascal
  test.advchart.scale.break,
```

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -5`
Expected: FAIL —— `Identifier not found "TTyBreakScaleMapper"`

- [ ] **Step 3: 写实现**

在 `source/tyControls.AdvChart.Scale.pas` 的 interface 段，`TTyLogScaleMapper` 之后、`TTyScaleTick` 之前加：

```pascal
  { One axis break: a value range collapsed to a small visual gap.
    Gap is a FRACTION of the visual span (0..1), not px -- so a break survives a
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

    Extents are delegated to the inner mapper -- the decorator has no extent of
    its own, so wrapping one around a live scale cannot move its axis. }
  TTyBreakScaleMapper = class(TInterfacedObject, ITyScaleMapper)
  private
    FInner: ITyScaleMapper;
    FBreaks: TTyAxisBreakArray;
    { Break bounds in inner space, ascending, active (non-expanded) only. }
    function ActiveCount: Integer;
    { Total inner-space span the active breaks would have occupied. }
    function CollapsedInnerSpan: Double;
    { Total gap fraction the active breaks keep, in inner-space units. }
    function GapInnerSpan: Double;
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
```

在 implementation 段的 `TTyLogScaleMapper` 之后加：

```pascal
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
  { Keep ascending by range start -- the accumulation walk below assumes it.
    Insertion sort: a chart has a handful of breaks, never enough to matter. }
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

function TTyBreakScaleMapper.GapInnerSpan: Double;
var
  e: TTyRange;
  full, kept: Double;
  i: Integer;
begin
  { A gap is a fraction of the VISUAL span. The visual span in inner units is
    (full - collapsed + gaps), which is circular -- so solve it: with G the sum
    of gap fractions, visual = (full - collapsed) / (1 - G). }
  e := GetExtent(sekMapping);
  full := Abs(FInner.TransformIn(e.Stop) - FInner.TransformIn(e.Start));
  kept := 0;
  for i := 0 to High(FBreaks) do
    if not FBreaks[i].Expanded then
      kept := kept + FBreaks[i].Gap;
  if kept >= 1 then
    kept := 0.99;
  Result := (full - CollapsedInnerSpan) / (1 - kept) * kept;
end;

function TTyBreakScaleMapper.NeedTransform: Boolean;
begin
  Result := True;
end;

function TTyBreakScaleMapper.TransformIn(AValue: Double): Double;
var
  t, bs, be, shift, gapTotal, gapEach: Double;
  i, n: Integer;
begin
  t := FInner.TransformIn(AValue);
  n := ActiveCount;
  if n = 0 then
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
      shift := bs; bs := be; be := shift; shift := 0;
    end;
    { Each active break keeps its own share of the total gap, in proportion to
      the gap fraction it asked for. }
    gapEach := 0;
    if gapTotal > 0 then
      gapEach := gapTotal * FBreaks[i].Gap / SumGapFractions(FBreaks);
    if t >= be then
      shift := shift - (be - bs) + gapEach
    else if t > bs then
    begin
      { Inside: land proportionally within this break's own gap. }
      Result := t - (t - bs) + shift + (t - bs) / (be - bs) * gapEach;
      Exit;
    end;
  end;
  Result := t + shift;
end;

function TTyBreakScaleMapper.TransformOut(AValue: Double): Double;
var
  bs, be, shift, gapTotal, gapEach, lo, hi: Double;
  i, n: Integer;
begin
  n := ActiveCount;
  if n = 0 then
    Exit(FInner.TransformOut(AValue));
  gapTotal := GapInnerSpan;
  shift := 0;
  for i := 0 to High(FBreaks) do
  begin
    if FBreaks[i].Expanded then
      Continue;
    bs := FInner.TransformIn(FBreaks[i].Range.Start);
    be := FInner.TransformIn(FBreaks[i].Range.Stop);
    gapEach := 0;
    if gapTotal > 0 then
      gapEach := gapTotal * FBreaks[i].Gap / SumGapFractions(FBreaks);
    lo := bs + shift;
    hi := lo + gapEach;
    if AValue > hi then
      shift := shift - (be - bs) + gapEach
    else if AValue >= lo then
    begin
      { Inside the gap: invert the proportional placement. }
      if gapEach = 0 then
        Exit(FInner.TransformOut(bs));
      Exit(FInner.TransformOut(bs + (AValue - lo) / gapEach * (be - bs)));
    end;
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
```

并在 implementation 段的 `TTyBreakScaleMapper` 之前加这个辅助函数：

```pascal
{ Sum of the gap fractions of the ACTIVE breaks. Guarded against 0 so the
  per-break share below never divides by zero when every break is expanded. }
function SumGapFractions(const ABreaks: TTyAxisBreakArray): Double;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(ABreaks) do
    if not ABreaks[i].Expanded then
      Result := Result + ABreaks[i].Gap;
  if Result <= 0 then
    Result := 1;
end;
```

- [ ] **Step 4: 编译并跑，确认通过——并确认 Task 2/3 一条都没改**

Run:
```bash
cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -4 && ./tytests.exe --suite=TAdvChartBreakTest --format=plain && ./tytests.exe --suite=TAdvChartMapperTest --format=plain && ./tytests.exe --suite=TAdvChartIntervalScaleTest --format=plain
```
Expected: `N:10 E:0 F:0`，`N:13 E:0 F:0`，`N:8 E:0 F:0`

再确认判据本身：

Run: `cd /d/Projects/ty-controls && git diff --stat HEAD -- tests/test.advchart.scale.pas`
Expected: **无输出**（Task 2/3 的测试文件未被本 Task 修改）。有输出就是契约 ② 的设计没成立，停下来重新想。

- [ ] **Step 5: 提交**

```bash
git add source/tyControls.AdvChart.Scale.pas tests/test.advchart.scale.break.pas tests/tytests.lpr && git commit -m "feat(advchart): axis breaks as a mapper decorator, composing with log"
```

---

## Task 5: TTyCartesian2D —— 契约 ①

**Files:**
- Create: `source/tyControls.AdvChart.Coord.pas`
- Create: `tests/test.advchart.coord.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test.advchart.coord.pas`：

```pascal
unit test.advchart.coord;
{$mode objfpc}{$H+}
{ CONTRACT 1 ACCEPTANCE (spec section 8 items 3 and 4).
  DataToPoint / PointToData must round trip within half a pixel, and the rect
  DataToLayout returns must contain the point DataToPoint returns -- if those two
  can disagree, the pointer and the pixels can disagree, which is the single rule
  TTySegmented exists to enforce. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale, tyControls.AdvChart.Coord;
type
  TAdvChartCartesianTest = class(TTestCase)
  private
    function MakeCartesian(const ARect: TTyRectF): TTyCartesian2D;
  published
    procedure TestDataToPointCorners;
    procedure TestYAxisIsInverted;
    procedure TestRoundTripWithinHalfPixel;
    procedure TestContainPointMatchesRect;
    procedure TestOutOfExtentIsStillMapped;
    procedure TestDataToLayoutContainsItsAnchor;
    procedure TestDataToLayoutIsBandWide;
    procedure TestContentRectIsInsideRect;
    procedure TestInvalidDataGivesInvalidPointAndRect;
    procedure TestThirdAxisIsAddressable;
  end;
implementation

const
  Eps = 1e-6;

function TAdvChartCartesianTest.MakeCartesian(const ARect: TTyRectF): TTyCartesian2D;
var sx, sy: TTyIntervalScale;
begin
  Result := TTyCartesian2D.Create;
  sx := TTyIntervalScale.Create;
  sx.SetExtent(TyRange(0, 10));
  sy := TTyIntervalScale.Create;
  sy.SetExtent(TyRange(0, 100));
  Result.AddAxis(TTyAxis.Create('x', sx, True));
  Result.AddAxis(TTyAxis.Create('y', sy, False));
  Result.SetRect(ARect);
end;

procedure TAdvChartCartesianTest.TestDataToPointCorners;
var c: TTyCartesian2D; p: TTyPointF;
begin
  c := MakeCartesian(TyRectF(50, 20, 450, 320));
  try
    p := c.DataToPoint([0, 0]);
    AssertEquals('origin x', 50.0, p.X, Eps);
    AssertEquals('origin y is the BOTTOM', 320.0, p.Y, Eps);
    p := c.DataToPoint([10, 100]);
    AssertEquals('far x', 450.0, p.X, Eps);
    AssertEquals('far y is the TOP', 20.0, p.Y, Eps);
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestYAxisIsInverted;
var c: TTyCartesian2D;
begin
  c := MakeCartesian(TyRectF(0, 0, 100, 200));
  try
    { Screen y grows downward, values grow upward. A y axis that is not
      inverted is the single most common chart bug there is. }
    AssertTrue('larger value is higher on screen',
               c.DataToPoint([5, 90]).Y < c.DataToPoint([5, 10]).Y);
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestRoundTripWithinHalfPixel;
var
  c: TTyCartesian2D; i, j: Integer; dx, dy: Double;
  p: TTyPointF; back: TTyDoubleArray;
begin
  c := MakeCartesian(TyRectF(37.5, 11.25, 613.75, 402.5));
  try
    for i := 0 to 10 do
      for j := 0 to 10 do
      begin
        dx := i;
        dy := j * 10;
        p := c.DataToPoint([dx, dy]);
        AssertTrue('pointToData succeeded', c.PointToData(p, back));
        AssertEquals('x round trip', dx, back[0], 0.5 * 10 / (613.75 - 37.5));
        AssertEquals('y round trip', dy, back[1], 0.5 * 100 / (402.5 - 11.25));
      end;
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestContainPointMatchesRect;
var c: TTyCartesian2D;
begin
  c := MakeCartesian(TyRectF(50, 20, 450, 320));
  try
    AssertTrue('inside', c.ContainPoint(TyPointF(200, 200)));
    AssertTrue('top-left corner', c.ContainPoint(TyPointF(50, 20)));
    AssertFalse('left of the band', c.ContainPoint(TyPointF(49.9, 200)));
    AssertFalse('below the band', c.ContainPoint(TyPointF(200, 320.1)));
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestOutOfExtentIsStillMapped;
var c: TTyCartesian2D; p: TTyPointF;
begin
  c := MakeCartesian(TyRectF(0, 0, 100, 100));
  try
    { Clipping is the renderer's decision, not the coordinate system's -- a datum
      outside the extent must still get a real point so a clipped line can be
      drawn to it and cut at the boundary. }
    p := c.DataToPoint([20, 0]);
    AssertFalse('not NaN', IsNan(p.X));
    AssertEquals('extrapolated linearly', 200.0, p.X, Eps);
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestDataToLayoutContainsItsAnchor;
var c: TTyCartesian2D; i: Integer; p: TTyPointF; l: TTyCoordLayout;
begin
  c := MakeCartesian(TyRectF(50, 20, 450, 320));
  try
    for i := 0 to 10 do
    begin
      p := c.DataToPoint([i, 50]);
      l := c.DataToLayout([i, 50]);
      AssertTrue('layout rect is valid at ' + IntToStr(i), TyRectFIsValid(l.Rect));
      AssertTrue('anchor x is inside its own cell at ' + IntToStr(i),
                 (p.X >= l.Rect.Left - Eps) and (p.X <= l.Rect.Right + Eps));
      AssertTrue('anchor y is inside its own cell at ' + IntToStr(i),
                 (p.Y >= l.Rect.Top - Eps) and (p.Y <= l.Rect.Bottom + Eps));
    end;
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestDataToLayoutIsBandWide;
var c: TTyCartesian2D; l: TTyCoordLayout;
begin
  c := MakeCartesian(TyRectF(0, 0, 400, 300));
  try
    c.GetAxis(0).BandWidth := 40;
    l := c.DataToLayout([5, 50]);
    AssertEquals('cell is one band wide', 40.0, TyRectFWidth(l.Rect), Eps);
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestContentRectIsInsideRect;
var c: TTyCartesian2D; l: TTyCoordLayout;
begin
  c := MakeCartesian(TyRectF(0, 0, 400, 300));
  try
    c.GetAxis(0).BandWidth := 40;
    c.DividerWidth := 2;
    l := c.DataToLayout([5, 50]);
    AssertTrue('content rect is valid', TyRectFIsValid(l.ContentRect));
    AssertTrue('content is inset from the left', l.ContentRect.Left >= l.Rect.Left);
    AssertTrue('content is inset from the right', l.ContentRect.Right <= l.Rect.Right);
    AssertEquals('inset by half the divider on each side',
                 TyRectFWidth(l.Rect) - 2, TyRectFWidth(l.ContentRect), Eps);
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestInvalidDataGivesInvalidPointAndRect;
var c: TTyCartesian2D; p: TTyPointF; l: TTyCoordLayout;
begin
  c := MakeCartesian(TyRectF(0, 0, 400, 300));
  try
    p := c.DataToPoint([NaN, 50]);
    AssertTrue('NaN in, NaN out', IsNan(p.X));
    l := c.DataToLayout([NaN, 50]);
    AssertFalse('and an invalid rect, never an empty one', TyRectFIsValid(l.Rect));
  finally
    c.Free;
  end;
end;

procedure TAdvChartCartesianTest.TestThirdAxisIsAddressable;
var c: TTyCartesian2D; s: TTyIntervalScale;
begin
  { N axes, not two. A secondary y axis is the commonest real-world request and
    it must not be a special case bolted on later. }
  c := MakeCartesian(TyRectF(0, 0, 400, 300));
  try
    s := TTyIntervalScale.Create;
    s.SetExtent(TyRange(0, 1));
    c.AddAxis(TTyAxis.Create('y', s, False));
    AssertEquals('three axes', 3, c.AxisCount);
    AssertEquals('the third is a y axis', 'y', c.GetAxis(2).Dim);
    AssertTrue('and it has its own scale',
               c.GetAxis(2).Scale.GetExtent.Stop = 1);
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartCartesianTest);
end.
```

- [ ] **Step 2: 挂进 runner，跑一次确认失败**

在 `tests/tytests.lpr` 的 `test.advchart.scale.break,` 之后加：

```pascal
  test.advchart.coord,
```

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -5`
Expected: FAIL —— `Can't find unit tyControls.AdvChart.Coord`

- [ ] **Step 3: 写实现**

创建 `source/tyControls.AdvChart.Coord.pas`：

```pascal
unit tyControls.AdvChart.Coord;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the coordinate-system layer.

  CONTRACT 1 (spec section 2). Every coordinate system answers a datum TWO ways:

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

  PURE: no Controls, no Graphics, no handle. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Scale;

type
  { Rect plus the divider-inset area a nested thing is laid out into. See the
    unit header; ECharts' Calendar.dataToLayout returns the same pair. }
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
    { Value -> px along this axis. Extrapolates outside the extent on purpose:
      clipping is the renderer's decision, not the coordinate system's. }
    function DataToCoord(AValue: Double): Double;
    function CoordToData(ACoord: Double): Double;
    property Dim: string read FDim;
    property Scale: TTyScale read FScale;
    property Horizontal: Boolean read FHorizontal;
    property PxStart: Double read FPxStart;
    property PxStop: Double read FPxStop;
    { The width of one datum's band, px. 0 means "not banded" (a continuous
      axis), and DataToLayout then falls back to the gap between neighbours. }
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
    the rest are addressed explicitly by a series' axis binding. }
  TTyCartesian2D = class(TInterfacedObject, ITyCoordSys)
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
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): TTyAxis;
    { Half of this is taken off each side of a cell to give its ContentRect. }
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
    the BOTTOM up, which is the one place screen-vs-value direction is decided. }
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
  { The cell is one band wide, and runs from the axis baseline to the datum --
    which is exactly a bar. A continuous axis has no band, so fall back to a
    hairline centred on the anchor rather than inventing a width. }
  if ax.BandWidth > 0 then
    hw := ax.BandWidth / 2
  else
    hw := 0;
  baseY := ay.DataToCoord(ay.Scale.GetExtent.Start);
  Result.Rect := TyRectF(p.X - hw, Min(p.Y, baseY), p.X + hw, Max(p.Y, baseY));
  half := FDividerWidth / 2;
  Result.ContentRect := TyRectF(Result.Rect.Left + half, Result.Rect.Top + half,
                                Result.Rect.Right - half, Result.Rect.Bottom - half);
  { A divider wider than the cell would invert it. Collapse to a zero-area rect
    at the centre instead -- still valid, still contains nothing. }
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
  Result := TyRectFContains(FRect, APoint)
         or ((APoint.X = FRect.Right) and (APoint.Y >= FRect.Top) and (APoint.Y <= FRect.Bottom))
         or ((APoint.Y = FRect.Bottom) and (APoint.X >= FRect.Left) and (APoint.X <= FRect.Right));
end;

end.
```

> **注意** `TestContainPointMatchesRect` 断言 `(50,20)` 在内、`(200,320.1)` 在外，而 `TyRectFContains`
> 是右下半开的——所以 `ContainPoint` 上面那两个补丁分支把**闭合的右/下边界**加了回来。坐标系的
> 「点在图里吗」要闭合（贴着右边框的点仍属于这张图），而**相邻数据格之间**要半开（否则两个柱抢同一列
> 像素）。这两条规则不同，是有意的。

- [ ] **Step 4: 编译并跑，确认通过**

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -4 && ./tytests.exe --suite=TAdvChartCartesianTest --format=plain`
Expected: `N:10 E:0 F:0`

- [ ] **Step 5: 提交**

```bash
git add source/tyControls.AdvChart.Coord.pas tests/test.advchart.coord.pas tests/tytests.lpr && git commit -m "feat(advchart): cartesian2d with N axes, DataToPoint and DataToLayout"
```

---

## Task 6: 盒布局求解器 —— 契约 ① 的另一半

**Files:**
- Create: `source/tyControls.AdvChart.Layout.pas`
- Create: `tests/test.advchart.layout.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test.advchart.layout.pas`：

```pascal
unit test.advchart.layout;
{$mode objfpc}{$H+}
{ CONTRACT 1 ACCEPTANCE, second half (spec section 8 item 6).
  The box solver must take a CONTAINER PROVIDER, not a rect, and the same code
  path must serve both "the container is the control's client area" and "the
  container is another coordinate system's DataToLayout". If those are two paths,
  coordinateSystemUsage:'box' is a rewrite instead of a parameter. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Layout;
type
  TAdvChartLayoutTest = class(TTestCase)
  published
    procedure TestPixelInsets;
    procedure TestPercentInsets;
    procedure TestWidthWinsOverRight;
    procedure TestHeightAndBottomAgree;
    procedure TestCentreKeyword;
    procedure TestOverConstrainedCollapsesNotInverts;
    procedure TestFixedContainerProvider;
    procedure TestCoordCellContainerProvider;
    procedure TestBothProvidersTakeTheSamePath;
  end;
implementation

const
  Eps = 1e-9;

procedure TAdvChartLayoutTest.TestPixelInsets;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Left := TyBoxPx(10);
  b.Top := TyBoxPx(20);
  b.Right := TyBoxPx(30);
  b.Bottom := TyBoxPx(40);
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertEquals('left', 10.0, r.Left, Eps);
  AssertEquals('top', 20.0, r.Top, Eps);
  AssertEquals('right', 170.0, r.Right, Eps);
  AssertEquals('bottom', 60.0, r.Bottom, Eps);
end;

procedure TAdvChartLayoutTest.TestPercentInsets;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Left := TyBoxPercent(10);
  b.Right := TyBoxPercent(10);
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertEquals('left', 20.0, r.Left, Eps);
  AssertEquals('right', 180.0, r.Right, Eps);
end;

procedure TAdvChartLayoutTest.TestWidthWinsOverRight;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Left := TyBoxPx(10);
  b.Width := TyBoxPx(50);
  b.Right := TyBoxPx(999);
  { Left+Width is fully determined; Right is redundant and must be ignored
    rather than fought over -- ECharts resolves the same way. }
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertEquals('left', 10.0, r.Left, Eps);
  AssertEquals('right', 60.0, r.Right, Eps);
end;

procedure TAdvChartLayoutTest.TestHeightAndBottomAgree;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Bottom := TyBoxPx(10);
  b.Height := TyBoxPx(40);
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertEquals('bottom', 90.0, r.Bottom, Eps);
  AssertEquals('top', 50.0, r.Top, Eps);
end;

procedure TAdvChartLayoutTest.TestCentreKeyword;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Left := TyBoxCentre;
  b.Width := TyBoxPx(50);
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertEquals('centred left', 75.0, r.Left, Eps);
  AssertEquals('centred right', 125.0, r.Right, Eps);
end;

procedure TAdvChartLayoutTest.TestOverConstrainedCollapsesNotInverts;
var b: TTyBoxSpec; r: TTyRectF;
begin
  b := TyBoxSpec;
  b.Left := TyBoxPx(150);
  b.Right := TyBoxPx(150);
  { 150+150 > 200. A negative-width rect would let a later Min/Max silently
    swap the edges; collapse to zero width at the left instead, which stays
    a VALID rect and draws nothing. }
  r := TySolveBox(b, TyFixedContainer(TyRectF(0, 0, 200, 100)));
  AssertTrue('still a valid rect', TyRectFIsValid(r));
  AssertEquals('collapsed to zero width', 0.0, TyRectFWidth(r), Eps);
end;

procedure TAdvChartLayoutTest.TestFixedContainerProvider;
var c: ITyBoxContainer;
begin
  c := TyFixedContainer(TyRectF(5, 6, 105, 106));
  AssertEquals('left', 5.0, c.ContainerRect.Left, Eps);
  AssertEquals('width', 100.0, TyRectFWidth(c.ContainerRect), Eps);
end;

procedure TAdvChartLayoutTest.TestCoordCellContainerProvider;
var
  cs: TTyCartesian2D; sx, sy: TTyIntervalScale;
  c: ITyBoxContainer; cell: TTyRectF;
begin
  cs := TTyCartesian2D.Create;
  sx := TTyIntervalScale.Create;
  sx.SetExtent(TyRange(0, 10));
  sy := TTyIntervalScale.Create;
  sy.SetExtent(TyRange(0, 100));
  cs.AddAxis(TTyAxis.Create('x', sx, True));
  cs.AddAxis(TTyAxis.Create('y', sy, False));
  cs.SetRect(TyRectF(0, 0, 400, 300));
  cs.GetAxis(0).BandWidth := 40;
  { The container is one datum's cell in another coordinate system -- this is
    coordinateSystemUsage:'box' in its smallest form. }
  c := TyCoordCellContainer(cs, [5, 100]);
  cell := c.ContainerRect;
  AssertTrue('the cell is a valid rect', TyRectFIsValid(cell));
  AssertEquals('one band wide', 40.0, TyRectFWidth(cell), 1e-6);
end;

procedure TAdvChartLayoutTest.TestBothProvidersTakeTheSamePath;
var
  cs: TTyCartesian2D; sx, sy: TTyIntervalScale;
  b: TTyBoxSpec; viaCell, viaFixed, cell: TTyRectF;
begin
  cs := TTyCartesian2D.Create;
  sx := TTyIntervalScale.Create;
  sx.SetExtent(TyRange(0, 10));
  sy := TTyIntervalScale.Create;
  sy.SetExtent(TyRange(0, 100));
  cs.AddAxis(TTyAxis.Create('x', sx, True));
  cs.AddAxis(TTyAxis.Create('y', sy, False));
  cs.SetRect(TyRectF(0, 0, 400, 300));
  cs.GetAxis(0).BandWidth := 40;

  b := TyBoxSpec;
  b.Left := TyBoxPercent(10);
  b.Right := TyBoxPercent(10);
  b.Top := TyBoxPx(2);
  b.Bottom := TyBoxPx(2);

  cell := TyCoordCellContainer(cs, [5, 100]).ContainerRect;
  viaCell := TySolveBox(b, TyCoordCellContainer(cs, [5, 100]));
  viaFixed := TySolveBox(b, TyFixedContainer(cell));

  { THE ACCEPTANCE ASSERTION. Solving into a coordinate cell and solving into
    the identical rect handed over as a literal must produce the same answer --
    that is what "one code path" means, and it is the whole of contract 1's
    second half. }
  AssertEquals('left', viaFixed.Left, viaCell.Left, Eps);
  AssertEquals('top', viaFixed.Top, viaCell.Top, Eps);
  AssertEquals('right', viaFixed.Right, viaCell.Right, Eps);
  AssertEquals('bottom', viaFixed.Bottom, viaCell.Bottom, Eps);
  cs.Free;
end;

initialization
  RegisterTest(TAdvChartLayoutTest);
end.
```

- [ ] **Step 2: 挂进 runner，跑一次确认失败**

在 `tests/tytests.lpr` 的 `test.advchart.coord,` 之后加：

```pascal
  test.advchart.layout,
```

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -5`
Expected: FAIL —— `Can't find unit tyControls.AdvChart.Layout`

- [ ] **Step 3: 写实现**

创建 `source/tyControls.AdvChart.Layout.pas`：

```pascal
unit tyControls.AdvChart.Layout;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the box layout solver.

  CONTRACT 1, second half (spec section 2). The solver takes an ITyBoxContainer,
  never a rect. Two implementations ship here:

    TyFixedContainer     -- a literal rect (the control's client area, top level)
    TyCoordCellContainer -- one datum's cell in another coordinate system
                            (coordinateSystemUsage:'box', in its smallest form)

  Both go through the SAME TySolveBox. If a component were written against "the
  control's client rect", nesting it later would be a rewrite; written against a
  provider, nesting is a different argument.

  The provider is an interface rather than a rect parameter because when nesting,
  the container is not known until the HOST has been laid out -- the value has to
  be fetched late, not passed early.

  PURE: no Controls, no Graphics, no handle. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Coord;

type
  { How one edge/size is expressed. }
  TTyBoxUnit = (buAuto, buPx, buPercent, buCentre);

  TTyBoxValue = record
    Kind: TTyBoxUnit;
    Value: Double;
  end;

  { left/top/right/bottom/width/height, each optional. Redundant constraints are
    resolved by precedence, never by error: on each axis, the pair
    (start, size) wins over (start, end) wins over (end, size). }
  TTyBoxSpec = record
    Left, Top, Right, Bottom, Width, Height: TTyBoxValue;
  end;

  ITyBoxContainer = interface
    ['{8D31C60F-4A72-4B95-BE28-3F7A05D6C914}']
    function ContainerRect: TTyRectF;
  end;

function TyBoxSpec: TTyBoxSpec;              { all buAuto }
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

{ Resolve one value against a container extent. Returns NaN for buAuto so the
  caller can tell "not specified" from "specified as zero" -- the distinction
  the whole precedence table below rests on. }
function ResolveValue(const AV: TTyBoxValue; AExtent: Double): Double;
begin
  case AV.Kind of
    buPx: Result := AV.Value;
    buPercent: Result := AV.Value / 100 * AExtent;
    buCentre: Result := NaN;
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
  else if not IsNan(s) then                            { start only }
  begin
    AStart := AContainerStart + s;
    AStop := AContainerStart + AContainerExtent;
  end
  else if not IsNan(e) then                            { end only }
  begin
    AStart := AContainerStart;
    AStop := AContainerStart + AContainerExtent - e;
  end
  else if not IsNan(sz) then                           { size only -> at the near edge }
  begin
    AStart := AContainerStart;
    AStop := AStart + sz;
  end
  else                                                 { nothing -> fill }
  begin
    AStart := AContainerStart;
    AStop := AContainerStart + AContainerExtent;
  end;

  { Over-constrained: collapse to zero at the near edge rather than invert. An
    inverted rect survives a later Min/Max swap and reappears as a phantom
    band somewhere else. }
  if AStop < AStart then
    AStop := AStart;
end;

function TySolveBox(const ASpec: TTyBoxSpec; const AContainer: ITyBoxContainer): TTyRectF;
var
  c: TTyRectF;
  l, r, t, b: Double;
begin
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
  { ContentRect, not Rect -- a nested thing must not paint over the host's
    divider. This is the same choice HeatmapView.ts:279 makes. }
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
```

- [ ] **Step 4: 编译并跑，确认通过**

Run: `cd /d/Projects/ty-controls/tests && /d/lazarus/lazbuild.exe tytests.lpi 2>&1 | tail -4 && ./tytests.exe --suite=TAdvChartLayoutTest --format=plain`
Expected: `N:9 E:0 F:0`

- [ ] **Step 5: 提交**

```bash
git add source/tyControls.AdvChart.Layout.pas tests/test.advchart.layout.pas tests/tytests.lpr && git commit -m "feat(advchart): box layout solver over a container provider"
```

---

## Task 7: 全量回归与经济账结算

- [ ] **Step 1: 跑全量套件**

Run: `cd /d/Projects/ty-controls/tests && ./tytests.exe --all --format=plain --sparse 2>&1 | tail -5`
Expected: `Number of errors: 0`、`Number of failures: 0`，且 `Number of run tests` **≥ 6331 + 50**

- [ ] **Step 2: 确认纯度**

前四个单元不许引用 `Controls` / `Graphics` / `Forms` / `LCL*` / `BGRA*`。

Run:
```bash
cd /d/Projects/ty-controls && grep -n "^uses\|^ *Classes, \|Controls\|Graphics\|Forms\|LCL\|BGRA" source/tyControls.AdvChart.*.pas | grep -v "^\S*: *{"
```
Expected: 只出现 `SysUtils`、`Math`、`tyControls.AdvChart.*`。任何一条 LCL/BGRA 引用都说明纯度破了。

- [ ] **Step 3: 量代价，写进 spec**

Run:
```bash
cd /d/Projects/ty-controls && wc -l source/tyControls.AdvChart.*.pas tests/test.advchart*.pas && git log --oneline feat/advancechart ^main | wc -l
```

把行数、测试数、以及**契约有没有打架**的结论追加到
`docs/superpowers/specs/2026-09-01-advancechart-tier0.md` 新的一节 §9「spike 结算」，
并明确回答：**这一趟是否 ≤ 一个 L？** 若否，按 memo §5「什么会推翻这个建议」改回对标 v5。

- [ ] **Step 4: 提交**

```bash
git add docs/superpowers/specs/2026-09-01-advancechart-tier0.md && git commit -m "docs(advchart): spike settlement -- the two contracts, measured"
```

---

## 自查

**范围覆盖**：spec §8 的判据 3（往返 <0.5px，Task 5）、4（Layout 含锚点，Task 5）、
5（断轴不改既有测试，Task 4 Step 4 的 `git diff --stat` 断言）、6（两种容器同一路径，Task 6 最后一个测试）
全部有对应任务。判据 1（全量绿）在 Task 7。判据 2（纯度）在 Task 7 Step 2。
判据 7（17 套主题 golden）属于 Tier 0 第 18 项，**不在本 spike 范围**。

**占位符扫描**：无 TBD / TODO / "类似 Task N"。每个改代码的步骤都给了完整代码。

**类型一致性**：`TTyRange`/`TTyRectF`/`TTyPointF`/`TTyDoubleArray` 在 Task 1 定义，后续沿用；
`ITyScaleMapper` 的九个方法在 Task 2 定义，Task 4 的装饰器逐个实现；
`TTyCoordLayout` 在 Task 5 定义（**不是** Task 1），Task 6 消费其 `ContentRect`；
`TTyScale.Mapper` 在 Task 3 声明为可写，Task 4 依赖这一点。
`SumGapFractions` 在 Task 4 Step 3 的辅助函数块里定义，供 `TransformIn`/`TransformOut` 调用——
**它必须写在 `TTyBreakScaleMapper` 的实现之前**，否则 FPC 单趟编译找不到它。
