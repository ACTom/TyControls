unit tyControls.AdvChart.Progressive;
{$mode objfpc}{$H+}
{ PROGRESSIVE RENDERING: a series drawn a chunk a frame [Batch 119, C9].

  Upstream's scheduler (core/Scheduler.ts, core/task.ts) runs every series
  as a pipeline of tasks. When the painter is a canvas, `getProgressive()`
  is truthy, the view has `incrementalPrepareRender` (scatter, bar,
  candlestick, heatmap here) and the data count after the filters reaches
  `getProgressiveThreshold()`, the visual and render tasks run a STEP --
  Math.round(progressive) rows -- per frame instead of the whole series:
  setOption draws the first chunk, every animation frame
  (echarts.ts _onframe) draws more while TEST_FRAME_REMAIN_TIME, 1 ms, is
  left of its budget, and `finished` fires with the last one.

  THE CHUNK'S ROWS. 'sequential' walks positions start..end; 'mod' (the
  default of a bar and a candlestick) walks task.ts's modNext:
    winCount = ceil(modDataCount / modBy), modBy = ceil(modDataCount / step)
    row(current) = (current % winCount) * modBy + ceil(current / winCount),
                   or current itself where that is not under modDataCount.
  It is not a permutation -- with 10 rows by 4 row 7 comes twice and row 9
  never -- and only the layouts that call params.next() follow it: a bar's
  large layout and a candlestick's. A scatter's points layout and a
  heatmap's walk start..end whatever the mode says.

  THE RESTARTS. A task resets -- and every task downstream with it, down to
  the render, which clears the view and draws from row 0 again -- when the
  (modBy, modDataCount) it is performed with differ from the last ones. The
  visual stage's change when appendData moves a 'mod' count; the BLOCKED
  data stage's change at the first frame after a setOption (the new
  pipeline has no context yet, so setOption performs it with (1, 0), the
  frame with (Infinity, count)) -- and only a series with a task of its own
  in that stage feels it: a bar (dataSample('bar')) and a line, nothing
  else that renders progressively. A large or progressive switch resets the
  render too (createRenderPlanner).

  PURE: SysUtils, Math, fpjson and AdvChart.Types (and the platform's
  fine clock). }
interface
uses
  SysUtils, Math, fpjson, tyControls.AdvChart.Types;

const
  { echarts.ts TEST_FRAME_REMAIN_TIME: the ms a frame spends on chunks }
  TyProgFrameBudgetMs = 1;

type
  { What the series' model answers. }
  TTyProgSpec = record
    { pipeline.progressiveEnabled: getProgressive() truthy (a canvas
      painter, which this port always is) }
    Enabled: Boolean;
    { pipeline.step: Math.round(progressive || 700) }
    Step: Integer;
    { getProgressiveThreshold(), as `dataLen >= threshold` compares it:
      not-a-number never passes }
    Threshold: Double;
    { progressiveChunkMode === 'mod' }
    ModMode: Boolean;
  end;

  { The (modBy, modDataCount) a task was last performed with, normalized as
    Task.perform normalizes them. }
  TTyProgArgs = record
    ModBy: Double;
    ModCount: Integer;
  end;

  { One series' pipeline, as the control keeps it from update to frame. }
  TTyProgRun = record
    { the series the slot held when the run was made }
    Series: Integer;
    SeriesType: string;
    Spec: TTyProgSpec;
    { the pipeline context: progressiveRender, large, modDataCount (-1 for
      null) and the data count it was made for }
    On, Large: Boolean;
    ModCount: Integer;
    Count: Integer;
    { the chunks: chunk k covers positions Starts[k] up to Ends[k]; the first
      Done are drawn. A chunk drawn before appendData keeps its end. }
    Starts, Ends: TTyIntegerArray;
    Done: Integer;
    { the args the blocked data stage and the visual stage ran with last }
    Block, Visual: TTyProgArgs;
  end;
  TTyProgRunArray = array of TTyProgRun;

{ The types whose view has incrementalPrepareRender: scatter, bar,
  candlestick, heatmap. }
function TyProgViewIncremental(const AType: string): Boolean;
{ The types with a series task in the blocked data stage (dataSample):
  bar and line. }
function TyProgHasBlockTask(const AType: string): Boolean;
{ The types whose layout walks params.next(): bar and candlestick. }
function TyProgWalksNext(const AType: string): Boolean;

{ getProgressive / getProgressiveThreshold / progressiveChunkMode of a
  series of type AType written as ANode (nil: every default). }
function TyProgSpecOf(const AType: string; ANode: TJSONObject;
  ARoot: TJSONObject = nil): TTyProgSpec;
{ progressiveRender: enabled, an incremental view, and ACount at least the
  threshold }
function TyProgRenderOn(const ASpec: TTyProgSpec; const AType: string;
  ACount: Integer): Boolean;

{ getPerformArgs' modBy for a modDataCount (-1 null) and a step (not-a-number
  for a task that is not incremental), normalized: under 1 (or not a
  number) is 1. }
function TyProgModBy(AModCount: Integer; AStep: Double): Double;
{ The args a task of the blocked stage runs with under ARun's context (none
  yet when AFresh). }
function TyProgBlockArgs(const ARun: TTyProgRun; AFresh: Boolean): TTyProgArgs;
{ The args the visual and render tasks run with. }
function TyProgVisualArgs(const ARun: TTyProgRun): TTyProgArgs;
function TyProgArgsSame(const A, B: TTyProgArgs): Boolean;

{ The rows positions AStart..AEnd - 1 visit: modNext when AModBy > 1 and
  AModCount > 0, else the positions. }
function TyProgChunkRows(AStart, AEnd: Integer; AModBy: Double;
  AModCount: Integer): TTyIntegerArray;

{ The chunks again: the first AKeep stay, the rest are planned by Step from
  where they end to Count. }
procedure TyProgReplan(var ARun: TTyProgRun; AKeep: Integer);
{ the end of chunk K }
function TyProgChunkEnd(const ARun: TTyProgRun; K: Integer): Integer;
{ the rows chunk K visits (the walk for a type that follows next()) }
function TyProgRowsOf(const ARun: TTyProgRun; K: Integer): TTyIntegerArray;
{ chunks still to draw }
function TyProgUnfinished(const ARun: TTyProgRun): Boolean;
{ For every view row, the chunk that first visits it, -1 for a row no chunk
  visits. }
function TyProgRowChunks(const ARun: TTyProgRun): TTyIntegerArray;

{ A clock fine enough to measure a 1 ms budget, ms from an arbitrary
  origin: platformApi.getTime is Date.now, but a frame here paints its chunk
  inside the step, and a 16 ms tick would let one frame draw everything. }
function TyProgNowMs: Double;

implementation

{$IFDEF WINDOWS}
uses Windows;
{$ELSE}
{ BaseUnix has TTimeVal; fpgettimeofday is declared in Unix }
uses BaseUnix, Unix;
{$ENDIF}

function TyProgNowMs: Double;
{$IFDEF WINDOWS}
var c, fq: Int64;
begin
  c := 0;
  fq := 0;
  if QueryPerformanceFrequency(fq) and (fq > 0) and QueryPerformanceCounter(c) then
    Result := c / fq * 1000
  else
    Result := GetTickCount64;
end;
{$ELSE}
var tv: TTimeVal;
begin
  if fpgettimeofday(@tv, nil) = 0 then
    Result := tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0
  else
    Result := GetTickCount64;
end;
{$ENDIF}

function TyProgViewIncremental(const AType: string): Boolean;
begin
  { [Batch 128] and a parallel series' (ParallelView.incrementalRender) }
  Result := (AType = 'scatter') or (AType = 'bar') or (AType = 'candlestick')
    or (AType = 'heatmap') or (AType = 'parallel');
end;

function TyProgHasBlockTask(const AType: string): Boolean;
begin
  Result := (AType = 'bar') or (AType = 'line');
end;

function TyProgWalksNext(const AType: string): Boolean;
begin
  Result := (AType = 'bar') or (AType = 'candlestick');
end;

{ JavaScript's ToNumber for the shapes an option value takes }
function JsNum(AData: TJSONData): Double;
var s: string; v: Double; code: Integer;
begin
  if AData = nil then Exit(NaN);
  case AData.JSONType of
    jtNull: Result := 0;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtNumber: Result := AData.AsFloat;
    jtString:
      begin
        s := Trim(AData.AsString);
        if s = '' then Exit(0);
        Val(s, v, code);
        if code = 0 then Result := v else Result := NaN;
      end;
  else
    Result := NaN;
  end;
end;

function JsTruthy(AData: TJSONData): Boolean;
begin
  if AData = nil then Exit(False);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (not IsNan(AData.AsFloat)) and (AData.AsFloat <> 0);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

{ Math.round }
function JsRound(A: Double): Double;
begin
  if IsNan(A) or IsInfinite(A) then Exit(A);
  Result := Floor(A + 0.5);
end;

function TyProgSpecOf(const AType: string; ANode: TJSONObject;
  ARoot: TJSONObject): TTyProgSpec;
var
  prog, th, d: TJSONData;
  ownProg, ownTh, n, thV: Double;
  hasOwnProg, hasOwnTh, progOn, rootOn: Boolean;

  { model.get(AKey) past the series' own option and its type's defaults:
    the option root, where the global defaults (progressive 400,
    progressiveThreshold 3000) sit under what the author wrote [F4c] }
  procedure RootOf(const AKey: string; ADefault: Double; out AOn: Boolean;
    out AN: Double);
  var r: TJSONData;
  begin
    r := nil;
    if ARoot <> nil then r := ARoot.Find(AKey);
    if r = nil then
    begin
      AOn := ADefault <> 0;
      AN := ADefault;
    end
    else
    begin
      AOn := JsTruthy(r);
      AN := JsNum(r);
    end;
  end;

begin
  Result := Default(TTyProgSpec);
  { the defaultOption chain: a type's own progressive (0 for the series that
    switch it off, 3000 for a bar's (BaseBarSeries) and a candlestick's, in
    'mod'; 300 for parallel) and a candlestick's threshold 1e4; every other
    series has none, and get() climbs to the option root }
  hasOwnProg := True;
  if (AType = 'line') or (AType = 'effectScatter') or (AType = 'pictorialBar')
    or (AType = 'treemap') then ownProg := 0
  else if (AType = 'bar') or (AType = 'candlestick') then ownProg := 3000
  else if AType = 'parallel' then ownProg := 300
  else
  begin
    hasOwnProg := False;
    ownProg := 0;
  end;
  hasOwnTh := AType = 'candlestick';
  if hasOwnTh then ownTh := 1e4 else ownTh := 0;
  prog := nil;
  th := nil;
  if ANode <> nil then
  begin
    prog := ANode.Find('progressive');
    th := ANode.Find('progressiveThreshold');
  end;
  { getProgressive: the option's own value; unwritten, the type's default;
    null, or no default, the root's }
  if (prog <> nil) and (prog.JSONType <> jtNull) then
  begin
    progOn := JsTruthy(prog);
    n := JsNum(prog);
  end
  else if (prog = nil) and hasOwnProg then
  begin
    progOn := ownProg <> 0;
    n := ownProg;
  end
  else
    RootOf('progressive', 400, progOn, n);
  { getProgressiveThreshold, the same chain }
  if (th <> nil) and (th.JSONType <> jtNull) then thV := JsNum(th)
  else if (th = nil) and hasOwnTh then thV := ownTh
  else RootOf('progressiveThreshold', 3000, rootOn, thV);
  if AType = 'scatter' then
  begin
    { `this.option.progressive == null`: the large default 5000, else
      get('progressive') -- which, a scatter having no default, is the
      root's }
    if (prog = nil) or (prog.JSONType = jtNull) then
    begin
      d := nil;
      if ANode <> nil then d := ANode.Find('large');
      if JsTruthy(d) then
      begin
        n := 5000;
        progOn := True;
      end
      else
        RootOf('progressive', 400, progOn, n);
    end;
    if (th = nil) or (th.JSONType = jtNull) then
    begin
      d := nil;
      if ANode <> nil then d := ANode.Find('large');
      if JsTruthy(d) then thV := 1e4
      else RootOf('progressiveThreshold', 3000, rootOn, thV);
    end;
  end
  else if AType = 'bar' then
  begin
    { `get('large') ? get('progressive') : false` }
    d := nil;
    if ANode <> nil then d := ANode.Find('large');
    if not JsTruthy(d) then progOn := False;
  end;
  Result.Threshold := thV;
  Result.Enabled := progOn;
  { Math.round(progressive || 700): a step that is no positive number would
    never end a chunk -- the port leaves such a series unchunked }
  if progOn then
  begin
    n := JsRound(n);
    if IsNan(n) or (n < 1) or (n > MaxInt) then Result.Enabled := False
    else Result.Step := Trunc(n);
  end;
  { progressiveChunkMode: the option's own, else a type's default 'mod',
    else the root's }
  d := nil;
  if ANode <> nil then d := ANode.Find('progressiveChunkMode');
  if (d <> nil) and (d.JSONType <> jtNull) then
    Result.ModMode := (d.JSONType = jtString) and (d.AsString = 'mod')
  else if (d = nil) and ((AType = 'bar') or (AType = 'candlestick')
    or (AType = 'pictorialBar')) then
    Result.ModMode := True
  else
  begin
    d := nil;
    if ARoot <> nil then d := ARoot.Find('progressiveChunkMode');
    Result.ModMode := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'mod');
  end;
end;

function TyProgRenderOn(const ASpec: TTyProgSpec; const AType: string;
  ACount: Integer): Boolean;
begin
  Result := ASpec.Enabled and TyProgViewIncremental(AType)
    and (not IsNan(ASpec.Threshold)) and (ACount >= ASpec.Threshold);
end;

function TyProgModBy(AModCount: Integer; AStep: Double): Double;
begin
  if AModCount < 0 then Exit(1);
  { Math.ceil(modDataCount / step): a null step is a zero divisor }
  if IsNan(AStep) or (AStep = 0) then
  begin
    if AModCount > 0 then Result := Infinity else Result := NaN;
  end
  else
    Result := Ceil(AModCount / AStep);
  { normalizeModBy: `!(val >= 1) && (val = 1)` }
  if IsNan(Result) or (Result < 1) then Result := 1;
end;

function TyProgBlockArgs(const ARun: TTyProgRun; AFresh: Boolean): TTyProgArgs;
begin
  if AFresh then
  begin
    Result.ModBy := 1;
    Result.ModCount := 0;
    Exit;
  end;
  { getPerformArgs(task, isBlock): no step }
  Result.ModBy := TyProgModBy(ARun.ModCount, NaN);
  Result.ModCount := Max(ARun.ModCount, 0);
end;

function TyProgVisualArgs(const ARun: TTyProgRun): TTyProgArgs;
var step: Double;
begin
  if ARun.Spec.Enabled and ARun.On then step := ARun.Spec.Step else step := NaN;
  Result.ModBy := TyProgModBy(ARun.ModCount, step);
  Result.ModCount := Max(ARun.ModCount, 0);
end;

function TyProgArgsSame(const A, B: TTyProgArgs): Boolean;
begin
  Result := (A.ModCount = B.ModCount)
    and ((A.ModBy = B.ModBy) or (IsInfinite(A.ModBy) and IsInfinite(B.ModBy)));
end;

function TyProgChunkRows(AStart, AEnd: Integer; AModBy: Double;
  AModCount: Integer): TTyIntegerArray;
var
  cur: Integer;
  win, di: Double;
  walk: Boolean;
begin
  Result := nil;
  if AEnd <= AStart then Exit;
  SetLength(Result, AEnd - AStart);
  walk := (AModBy > 1) and (AModCount > 0);
  win := 0;
  if walk then
  begin
    { winCount: 0 for an infinite modBy, and then every row is `current` }
    if IsInfinite(AModBy) then win := 0
    else win := Ceil(AModCount / AModBy);
  end;
  for cur := AStart to AEnd - 1 do
  begin
    if walk and (win > 0) then
    begin
      di := (cur mod Trunc(win)) * AModBy + Ceil(cur / win);
      if di < AModCount then Result[cur - AStart] := Trunc(di)
      else Result[cur - AStart] := cur;
    end
    else
      Result[cur - AStart] := cur;
  end;
end;

procedure TyProgReplan(var ARun: TTyProgRun; AKeep: Integer);
var s, e, n: Integer;
begin
  if AKeep < 0 then AKeep := 0;
  if AKeep > Length(ARun.Starts) then AKeep := Length(ARun.Starts);
  if AKeep = 0 then s := 0
  else s := ARun.Ends[AKeep - 1];
  SetLength(ARun.Starts, AKeep);
  SetLength(ARun.Ends, AKeep);
  if (not ARun.On) or (ARun.Spec.Step < 1) then Exit;
  n := AKeep;
  { Task.perform: end = min(dueIndex + step, dueEnd) }
  while s < ARun.Count do
  begin
    e := s + ARun.Spec.Step;
    if e > ARun.Count then e := ARun.Count;
    SetLength(ARun.Starts, n + 1);
    SetLength(ARun.Ends, n + 1);
    ARun.Starts[n] := s;
    ARun.Ends[n] := e;
    Inc(n);
    s := e;
  end;
end;

function TyProgChunkEnd(const ARun: TTyProgRun; K: Integer): Integer;
begin
  Result := ARun.Ends[K];
end;

function TyProgRowsOf(const ARun: TTyProgRun; K: Integer): TTyIntegerArray;
var modBy: Double;
begin
  Result := nil;
  if (K < 0) or (K > High(ARun.Starts)) then Exit;
  if TyProgWalksNext(ARun.SeriesType) then
    modBy := TyProgVisualArgs(ARun).ModBy
  else
    modBy := 1;
  Result := TyProgChunkRows(ARun.Starts[K], TyProgChunkEnd(ARun, K), modBy,
    ARun.ModCount);
end;

function TyProgUnfinished(const ARun: TTyProgRun): Boolean;
begin
  Result := ARun.On and (ARun.Done < Length(ARun.Starts));
end;

function TyProgRowChunks(const ARun: TTyProgRun): TTyIntegerArray;
var k, j: Integer; rows: TTyIntegerArray;
begin
  Result := nil;
  SetLength(Result, ARun.Count);
  for j := 0 to High(Result) do Result[j] := -1;
  for k := 0 to High(ARun.Starts) do
  begin
    rows := TyProgRowsOf(ARun, k);
    for j := 0 to High(rows) do
      if (rows[j] >= 0) and (rows[j] < ARun.Count) and (Result[rows[j]] < 0) then
        Result[rows[j]] := k;
  end;
end;

end.
