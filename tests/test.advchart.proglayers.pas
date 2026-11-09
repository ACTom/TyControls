unit test.advchart.proglayers;

{ Round 7 R7-AJ (spec section 290, item 1): A PROGRESSIVE RUN'S OWN LEVEL,
  AN INCREMENTAL LAYER PER ZLEVEL.

  ECharts 6.1's allocateZlevels gives a scatter of more rows than its
  getProgressiveThreshold, and any lines series of more rows than its own,
  a zlevel of their own (getZLevelKey: the series id), as it gives a trail
  one: the components before it in (zlevel, z) under it, what follows one
  level up. zrender 6.1 then splits every zlevel with incremental elements
  into the normal elements before the first of them, one incremental layer
  for every run of that zlevel, and the normal elements after it.

  The fixture (tools/advchart-oracle/view-layers.js, the zl-prog- and
  zl-big cases) holds, per case and step, every model's zlevel, the
  painter's layers and the display list as runs (with their incremental
  flag): the port's incremental layers stand on the zlevels upstream's do,
  and a series' elements are incremental where upstream's are.

  Beside it, in pixels: a progressive scatter of z -1 stays under the
  axes' split line; two progressive runs on user zlevels 0 and 2 with an
  opaque rect on zlevel 1 between them are each pasted once, on their own
  level [was: the one layer of both pasted on each run's level]; and the
  fast progress frames across levels draw what the full paint does. }

{$mode objfpc}{$H+}

interface
uses Classes, SysUtils, Math, Types, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Geo,
     tyControls.AdvanceChart;
type
  TPlProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Cached(ACanvas: TCanvas; const ARect: TRect);
    procedure Move(AX, AY: Integer);
    function Levels: TTyIntegerArray;
    function LastPos(AIndex: Integer): Integer;
    function List: TTyPaintList;
  end;

  TAdvChartProgLayersTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot: TJSONData;
    function NewChart(AW, AH: Integer; const AOption: string): TPlProbe;
    procedure LoadFixture;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheIncrementalLayersAsUpstream;
    procedure TestARunUnderTheAxesStaysUnderThem;
    procedure TestRunsOnTwoUserLevelsArePastedOnce;
    procedure TestFastFramesAcrossLevelsAreTheFullPaint;
    procedure TestTwoRunsOfOneLevelOutOfOrder;
    procedure TestALevelWhoseFirstChunkDrawsNothing;
    procedure TestRowsSelectedDuringTheRun;
    procedure TestALiftedRowPastARunNotYetDrawn;
    procedure TestAPatchedRowKeepsItsZLevel;
    procedure TestAPreventedRunIsDrawnAtOnce;
  end;

implementation

procedure TPlProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TPlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TPlProbe.Cached(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderCached(ACanvas, ARect, 96);
end;

function TPlProbe.LastPos(AIndex: Integer): Integer;
begin
  Result := ProgLayerLastPos(AIndex);
end;

function TPlProbe.Levels: TTyIntegerArray;
begin
  Result := ProgLayerLevels;
end;

function TPlProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TAdvChartProgLayersTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  TyAdvChartProgFastForTest(True);
  FRoot := nil;
end;

procedure TAdvChartProgLayersTest.TearDown;
begin
  TyAdvChartProgFastForTest(True);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartProgLayersTest.LoadFixture;
var sl: TStringList; mp: TJSONArray; k: Integer;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'advchart-view-layers.json');
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  mp := TJSONObject(FRoot).Arrays['maps'];
  for k := 0 to mp.Count - 1 do
    TyChartRegisterMap(mp.Objects[k].Strings['name'], mp.Objects[k].Strings['text']);
end;

function TAdvChartProgLayersTest.NewChart(AW, AH: Integer; const AOption: string): TPlProbe;
begin
  Result := TPlProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.AnimationMode := camOff;
  Result.AnimNow := 0;
  Result.ProgressiveStepCostMs := 1;
  Result.SetBounds(0, 0, AW, AH);
  if AOption <> '' then Result.Option := AOption;
end;

function HasInt(const A: TTyIntegerArray; V: Integer): Boolean;
var i: Integer;
begin
  for i := 0 to High(A) do
    if A[i] = V then Exit(True);
  Result := False;
end;

function IntsText(const A: TTyIntegerArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(A[i]);
  end;
  Result := '[' + Result + ']';
end;

{ EVERY STEP'S INCREMENTAL LAYERS on upstream's zlevels (its layers of
  zlevel2 1), and a series' elements incremental (a run's chunk) where
  upstream's display list has them so }
procedure TAdvChartProgLayersTest.TestTheIncrementalLayersAsUpstream;
var
  cs, steps, recs, lay, dl: TJSONArray;
  c, s, rec: TJSONObject;
  i, j, k, q, cmp: Integer;
  id, bad, v: string;
  chart: TPlProbe;
  bmp: TBGRABitmap;
  up, mine: TTyIntegerArray;
  L: TTyPaintList;
  pe: PTyChartElement;
  upInc, myInc, seen: Boolean;
begin
  LoadFixture;
  cs := TJSONObject(FRoot).Arrays['charts'];
  bad := '';
  cmp := 0;
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      if (Copy(id, 1, 8) <> 'zl-prog-') and (Copy(id, 1, 6) <> 'zl-big') then Continue;
      chart := NewChart(c.Get('w', 400), c.Get('h', 300), '');
      try
        chart.SetOption(c.Objects['option'].AsJSON, True);
        AssertEquals(id + ' parses', '', chart.OptionError);
        chart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
        steps := c.Arrays['steps'];
        recs := c.Arrays['recs'];
        for j := 0 to recs.Count - 1 do
        begin
          if j > 0 then
          begin
            s := steps.Objects[j - 1];
            if s.Find('set') <> nil then chart.SetOption(s.Objects['set'].AsJSON, '{}');
            if s.Find('act') <> nil then chart.DispatchAction(s.Objects['act'].AsJSON);
            chart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
          end;
          rec := recs.Objects[j];
          { the incremental layers' zlevels }
          lay := rec.Arrays['layers'];
          up := nil;
          for k := 0 to lay.Count - 1 do
            if (lay.Arrays[k].Integers[1] = 1) and not HasInt(up, lay.Arrays[k].Integers[0]) then
            begin
              SetLength(up, Length(up) + 1);
              up[High(up)] := lay.Arrays[k].Integers[0];
            end;
          mine := chart.Levels;
          Inc(cmp);
          if Length(up) <> Length(mine) then
            bad := bad + LineEnding + Format('%s %d: incremental layers on %s, upstream %s',
              [id, j, IntsText(mine), IntsText(up)])
          else
            for k := 0 to High(up) do
              if not HasInt(mine, up[k]) then
              begin
                bad := bad + LineEnding + Format('%s %d: incremental layers on %s, upstream %s',
                  [id, j, IntsText(mine), IntsText(up)]);
                Break;
              end;
          { each series: incremental here where upstream's elements are }
          dl := rec.Arrays['dl'];
          L := chart.List;
          for q := 0 to 9 do
          begin
            v := 'S' + IntToStr(q);
            seen := False;
            upInc := False;
            for k := 0 to dl.Count - 1 do
              if dl.Arrays[k].Strings[0] = v then
              begin
                seen := True;
                if dl.Arrays[k].Booleans[4] then upInc := True;
              end;
            if not seen then Continue;
            myInc := False;
            if L <> nil then
              for k := 0 to L.Count - 1 do
              begin
                pe := L.Ref(k);
                if (pe^.Datum.Kind = ctkSeries) and (pe^.Datum.SeriesIndex = q) and (pe^.ProgChunk > 0) then
                  myInc := True;
              end;
            Inc(cmp);
            if myInc <> upInc then
              bad := bad + LineEnding + Format('%s %d: %s incremental %s, upstream %s',
                [id, j, v, BoolToStr(myInc, True), BoolToStr(upInc, True)]);
          end;
        end;
      finally
        chart.Free;
      end;
    end;
  finally
    bmp.Free;
  end;
  AssertTrue(Format('compared %d', [cmp]), cmp >= 20);
  AssertEquals('as upstream:' + bad, '', bad);
end;

const
  { big symbols along y 5, a split line there (interval 5) }
  cUnder = '{"animation":false,"grid":{"left":40,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10,"show":false},'
    + '"yAxis":{"type":"value","min":0,"max":10,"interval":5,"axisLabel":{"show":false},'
    + '"axisLine":{"show":false},"axisTick":{"show":false},"splitLine":{"lineStyle":{"color":"#0000ff","width":3}}},'
    + '"series":[{"type":"scatter","z":-1,"symbolSize":24,"progressive":4,"progressiveThreshold":10,'
    + '"itemStyle":{"color":"#ff0000","opacity":1},'
    + '"data":[[1,5],[2,5],[3,5],[4,5],[5,5],[6,5],[7,5],[8,5],[9,5],[1.5,6],[2.5,6],[3.5,6]]}]}';

{ A SCATTER OF MORE ROWS THAN ITS THRESHOLD, z -1: on zlevel 0, the axes on
  1 -- the split line over its symbols [was: the run's layer over the
  axes] }
procedure TAdvChartProgLayersTest.TestARunUnderTheAxesStaysUnderThem;
var
  chart: TPlProbe;
  bmp: TBitmap;
  n: Integer;
  px: TColor;
  fast: Boolean;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(400, 300);
    for fast := False to True do
    begin
      TyAdvChartProgFastForTest(fast);
      chart := NewChart(400, 300, cUnder);
      try
        chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
        n := 0;
        while chart.ProgressiveUnfinished and (n < 20) do
        begin
          chart.ProgressTick;
          chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
          Inc(n);
        end;
        AssertFalse('drawn to the end', chart.ProgressiveUnfinished);
        AssertTrue('a progressive run', n > 0);
        { the symbol at x 5 (200 px), y 5 (150 px): the split line over it }
        px := bmp.Canvas.Pixels[200, 150];
        AssertTrue(Format('fast %s: the split line over the symbol: %.6x', [BoolToStr(fast, True), px]),
          (Blue(px) > 200) and (Red(px) < 60));
        { and the symbol beside it }
        px := bmp.Canvas.Pixels[200, 150 - 8];
        AssertTrue(Format('fast %s: the symbol beside it: %.6x', [BoolToStr(fast, True), px]),
          (Red(px) > 200) and (Blue(px) < 60));
      finally
        chart.Free;
      end;
    end;
  finally
    bmp.Free;
    TyAdvChartProgFastForTest(True);
  end;
end;

function TwoLevelsOption: string;
var sb: TStringBuilder; i: Integer;
begin
  sb := TStringBuilder.Create;
  try
    { (a title and the y axis' break over the left half's bars: what the
      static paint draws after the first layer, drawn again where the
      chunks land) }
    sb.Append('{"animation":false,"grid":{"left":40,"right":40,"top":40,"bottom":40},');
    sb.Append('"title":{"text":"Two","left":40,"top":70,"textStyle":{"fontSize":40}},');
    sb.Append('"xAxis":{"type":"category","show":false},"yAxis":{"type":"value","min":0,"max":10,');
    sb.Append('"axisLine":{"show":false},"axisTick":{"show":false},"axisLabel":{"show":false},"splitLine":{"show":false},');
    sb.Append('"breakArea":{"itemStyle":{"color":"#ffff00","opacity":1}},');
    sb.Append('"breaks":[{"start":6,"end":7,"gap":"8%"}]},');
    sb.Append('"graphic":[{"type":"rect","zlevel":1,"shape":{"x":200,"y":0,"width":200,"height":300},');
    sb.Append('"style":{"fill":"#0000ff"}}],');
    sb.Append('"series":[{"type":"bar","large":true,"largeThreshold":5,"progressive":4,"progressiveThreshold":10,');
    sb.Append('"itemStyle":{"color":"#ff0000"},"data":[');
    for i := 0 to 19 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append('9');
    end;
    sb.Append(']},{"type":"line","z":1,"symbol":"none","lineStyle":{"width":4,"color":"#000000"},"data":[');
    for i := 0 to 19 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append('5');
    end;
    sb.Append(']},{"type":"bar","zlevel":2,"large":true,"largeThreshold":5,"progressive":4,"progressiveThreshold":10,');
    sb.Append('"itemStyle":{"color":"#00ff00"},"data":[');
    for i := 0 to 19 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append('3');
    end;
    sb.Append(']}]}');
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

{ TWO RUNS ON USER ZLEVELS 0 AND 2, an opaque rect on 1 between: the red
  run under the rect, the green one over it -- each layer pasted once, on
  its own level [was: the one layer of both pasted on each run's level,
  the red bars over the rect] -- and the fast frames the full paint }
procedure TAdvChartProgLayersTest.TestRunsOnTwoUserLevelsArePastedOnce;
var
  chart: TPlProbe;
  bmp: TBitmap;
  n, k, f0, used: Integer;
  px: TColor;
  fast: Boolean;
  frames: array[Boolean] of TStringList;

  function Frame: RawByteString;
  var y, w: Integer;
  begin
    w := bmp.Width * 3;
    SetLength(Result, w * bmp.Height);
    for y := 0 to bmp.Height - 1 do Move(bmp.ScanLine[y]^, Result[1 + y * w], w);
  end;

begin
  frames[False] := TStringList.Create;
  frames[True] := TStringList.Create;
  bmp := TBitmap.Create;
  used := 0;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(400, 300);
    for fast := False to True do
    begin
      TyAdvChartProgFastForTest(fast);
      f0 := TyAdvChartProgFastFramesForTest;
      chart := NewChart(400, 300, TwoLevelsOption);
      try
        chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
        frames[fast].Add(Frame);
        n := 0;
        while chart.ProgressiveUnfinished and (n < 30) do
        begin
          chart.ProgressTick;
          chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
          frames[fast].Add(Frame);
          Inc(n);
        end;
        AssertFalse('drawn to the end', chart.ProgressiveUnfinished);
        if fast then used := TyAdvChartProgFastFramesForTest - f0;
        AssertEquals('two layers', 2, Length(chart.Levels));
        { the 13th category's red bar (x 233.6 to 239.2 px, to 9 of 10) where
          no green one is, under the rect: its blue there }
        px := bmp.Canvas.Pixels[236, 40 + 44];
        AssertTrue(Format('fast %s: the zlevel 0 run under the rect: %.6x', [BoolToStr(fast, True), px]),
          (Blue(px) > 200) and (Red(px) < 60) and (Green(px) < 60));
        { and the green bars over it near the bottom }
        k := 0;
        for n := 200 to 360 do
          if (Green(bmp.Canvas.Pixels[n, 300 - 40 - 20]) > 200) and (Blue(bmp.Canvas.Pixels[n, 300 - 40 - 20]) < 60) then
            Inc(k);
        AssertTrue(Format('fast %s: the zlevel 2 run over the rect (%d px)', [BoolToStr(fast, True), k]), k > 20);
        { and the left half's red bars out of it }
        px := bmp.Canvas.Pixels[44, 40 + 44];
        AssertTrue(Format('fast %s: the zlevel 0 run beside the rect: %.6x', [BoolToStr(fast, True), px]),
          (Red(px) > 200) and (Blue(px) < 60));
        { the y axis' break area (yellow) over the red bar there }
        k := 0;
        for n := 40 to 260 do
          if (Red(bmp.Canvas.Pixels[44, n]) > 200) and (Green(bmp.Canvas.Pixels[44, n]) > 200)
            and (Blue(bmp.Canvas.Pixels[44, n]) < 60) then Inc(k);
        AssertTrue(Format('fast %s: the break area over the bar (%d px)', [BoolToStr(fast, True), k]), k > 3);
      finally
        chart.Free;
      end;
    end;
    AssertTrue('several frames', frames[False].Count > 4);
    AssertEquals('as many frames', frames[False].Count, frames[True].Count);
    for k := 0 to frames[False].Count - 1 do
      AssertTrue(Format('frame %d the same pixels', [k]), frames[False][k] = frames[True][k]);
    AssertTrue(Format('the progress frames kept the static layer (%d of %d)', [used, frames[False].Count]),
      used >= frames[False].Count - 2);
  finally
    bmp.Free;
    frames[False].Free;
    frames[True].Free;
    TyAdvChartProgFastForTest(True);
  end;
end;

function AcrossOption(AKind: Integer): string;
var sb: TStringBuilder; i, j: Integer;
begin
  sb := TStringBuilder.Create;
  try
    if AKind = 1 then
    begin
      { a progressive parallel run under its axes (z 10, drawn after the
        list) and a title over it }
      sb.Append('{"animation":false,"title":{"text":"Parallel","left":"center","top":150,"textStyle":{"fontSize":40}},');
      sb.Append('"parallelAxis":[{"dim":0},{"dim":1},{"dim":2},{"dim":3}],');
      sb.Append('"series":[{"type":"parallel","progressive":20,"progressiveThreshold":30,');
      sb.Append('"lineStyle":{"width":2,"opacity":0.6},"data":[');
      for i := 0 to 99 do
      begin
        if i > 0 then sb.Append(',');
        sb.Append(Format('[%d,%d,%d,%d]', [(i * 37) mod 100, (i * 53) mod 100, (i * 71) mod 100, (i * 29) mod 100]));
      end;
      sb.Append(']}]}');
      Exit(sb.ToString);
    end;
    { two scatter runs of their own levels (their keys), a line between on
      the level over the first, a title and a legend over them all }
    sb.Append('{"animation":false,"title":{"text":"Across","left":"center","top":120,"textStyle":{"fontSize":40}},');
    sb.Append('"legend":{},"xAxis":{"type":"value","min":0,"max":100},"yAxis":{"type":"value","min":0,"max":100},"series":[');
    for j := 0 to 2 do
    begin
      if j > 0 then sb.Append(',');
      if j = 1 then
      begin
        sb.Append('{"type":"line","showSymbol":false,"lineStyle":{"width":6},"data":[[0,10],[100,90]]}');
        Continue;
      end;
      sb.Append('{"type":"scatter","progressive":13,"progressiveThreshold":20,"symbolSize":14,');
      sb.Append('"itemStyle":{"opacity":0.7},"data":[');
      for i := 0 to 59 do
      begin
        if i > 0 then sb.Append(',');
        sb.Append(Format('[%d,%d]', [(i * 37 + j * 11) mod 100, (i * 53 + j * 7) mod 100]));
      end;
      sb.Append(']}');
    end;
    sb.Append(']}');
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

{ THE FAST PROGRESS FRAMES ACROSS LEVELS: two runs on levels of their own, a
  line on the level between and a title and a legend over them -- every
  frame the full paint's pixels, and the frames kept the static layer
  [was: the full paint every frame when the levels were apart] }
procedure TAdvChartProgLayersTest.TestFastFramesAcrossLevelsAreTheFullPaint;
var
  chart: TPlProbe;
  bmp: TBitmap;
  n, k, f0, used, kind: Integer;
  fast: Boolean;
  frames: array[Boolean] of TStringList;

  function Frame: RawByteString;
  var y, w: Integer;
  begin
    w := bmp.Width * 3;
    SetLength(Result, w * bmp.Height);
    for y := 0 to bmp.Height - 1 do Move(bmp.ScanLine[y]^, Result[1 + y * w], w);
  end;

begin
  frames[False] := TStringList.Create;
  frames[True] := TStringList.Create;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(480, 360);
    for kind := 0 to 1 do
    begin
    frames[False].Clear;
    frames[True].Clear;
    used := 0;
    for fast := False to True do
    begin
      TyAdvChartProgFastForTest(fast);
      f0 := TyAdvChartProgFastFramesForTest;
      chart := NewChart(480, 360, AcrossOption(kind));
      try
        chart.Cached(bmp.Canvas, Rect(0, 0, 480, 360));
        frames[fast].Add(Frame);
        n := 0;
        while chart.ProgressiveUnfinished and (n < 30) do
        begin
          chart.ProgressTick;
          chart.Cached(bmp.Canvas, Rect(0, 0, 480, 360));
          frames[fast].Add(Frame);
          Inc(n);
        end;
        AssertFalse('drawn to the end', chart.ProgressiveUnfinished);
        if fast then used := TyAdvChartProgFastFramesForTest - f0;
        AssertEquals('a layer per zlevel of a run', 2 - kind, Length(chart.Levels));
      finally
        chart.Free;
      end;
    end;
    AssertTrue('several frames', frames[False].Count > 4);
    AssertEquals('as many frames', frames[False].Count, frames[True].Count);
    for k := 0 to frames[False].Count - 1 do
      AssertTrue(Format('kind %d frame %d the same pixels', [kind, k]), frames[False][k] = frames[True][k]);
    AssertTrue(Format('kind %d: the progress frames kept the static layer (%d of %d)', [kind, used, frames[False].Count]),
      used >= frames[False].Count - 2);
    end;
  finally
    bmp.Free;
    frames[False].Free;
    frames[True].Free;
    TyAdvChartProgFastForTest(True);
  end;
end;

{ TWO RUNS OF ONE ZLEVEL, their chunks in turn (no key: rows no more than
  the threshold) under a continuous visual map: one layer, not what a
  drawing in paint order gives -- the indicator's tail rebuild right after
  the run draws it again, as the whole rebuild does (the per-zlevel layers
  keep LargeSpeed's TestTheTailRedrawsALayerOutOfOrder, whose runs now each
  have a level of their own) }
procedure TAdvChartProgLayersTest.TestTwoRunsOfOneLevelOutOfOrder;
var
  frames: array[Boolean] of TStringList;
  tail: Boolean;
  chart: TPlProbe;
  bmp: TBitmap;
  sb: TStringBuilder;
  i, j, k, t0, used: Integer;
  opt: string;

  function Frame: RawByteString;
  var y, w: Integer;
  begin
    w := bmp.Width * 3;
    SetLength(Result, w * bmp.Height);
    for y := 0 to bmp.Height - 1 do Move(bmp.ScanLine[y]^, Result[1 + y * w], w);
  end;

begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"animation": false, "xAxis": {}, "yAxis": {},');
    sb.Append(' "visualMap": {"min": 0, "max": 40, "dimension": 1, "calculable": true, "orient": "horizontal", "left": "center", "top": 0},');
    sb.Append(' "series": [');
    for j := 0 to 1 do
    begin
      if j > 0 then sb.Append(',');
      sb.Append('{"type": "scatter", "progressive": 25, "progressiveThreshold": 100, "symbolSize": 16,');
      sb.Append(' "itemStyle": {"opacity": 0.7}, "data": [');
      for i := 0 to 99 do
      begin
        if i > 0 then sb.Append(',');
        sb.Append(Format('[%d,%d]', [(i * 37 + j * 17) mod 60, (i * 53 + j * 11) mod 40]));
      end;
      sb.Append(']}');
    end;
    sb.Append(']}');
    opt := sb.ToString;
  finally
    sb.Free;
  end;
  frames[False] := TStringList.Create;
  frames[True] := TStringList.Create;
  bmp := TBitmap.Create;
  used := 0;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(480, 400);
    for tail := False to True do
    begin
      TyAdvChartListTailForTest(tail);
      chart := NewChart(480, 400, opt);
      try
        chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
        while chart.ProgressiveUnfinished do
        begin
          chart.ProgressTick;
          chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
        end;
        AssertEquals('one layer', 1, Length(chart.Levels));
        t0 := TyAdvChartListTailsForTest;
        for k := 0 to 13 do
        begin
          chart.Move(90 + k * 23, 120 + (k mod 4) * 41);
          chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
          frames[tail].Add(Frame);
        end;
        if tail then used := TyAdvChartListTailsForTest - t0;
      finally
        chart.Free;
      end;
    end;
    AssertEquals('as many frames', frames[False].Count, frames[True].Count);
    for k := 0 to frames[False].Count - 1 do
      AssertTrue(Format('hover frame %d the same pixels', [k]), frames[False][k] = frames[True][k]);
    AssertTrue('the indicator moved by its tail', used >= 1);
  finally
    bmp.Free;
    frames[False].Free;
    frames[True].Free;
    TyAdvChartListTailForTest(True);
  end;
end;

function FrameOf(B: TBitmap): RawByteString;
var y, w: Integer;
begin
  w := B.Width * 3;
  SetLength(Result, w * B.Height);
  for y := 0 to B.Height - 1 do Move(B.ScanLine[y]^, Result[1 + y * w], w);
end;

{ A ZLEVEL WHOSE FIRST CHUNK DRAWS NOTHING (the second run's first rows
  empty): no layer of it at the first paint, its later chunks' layer made
  when they come -- the picture at the end the one a whole drawing gives }
procedure TAdvChartProgLayersTest.TestALevelWhoseFirstChunkDrawsNothing;
var
  chart: TPlProbe;
  bmp: TBitmap;
  sb: TStringBuilder;
  i, j, n: Integer;
  last: RawByteString;
begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"animation":false,"xAxis":{"min":0,"max":60},"yAxis":{"min":0,"max":40},"series":[');
    for j := 0 to 1 do
    begin
      if j > 0 then sb.Append(',');
      sb.Append('{"type":"scatter","progressive":10,"progressiveThreshold":20,"symbolSize":12,"data":[');
      for i := 0 to 39 do
      begin
        if i > 0 then sb.Append(',');
        if (j = 1) and (i < 10) then sb.Append('[null,null]')
        else sb.Append(Format('[%d,%d]', [(i * 37 + j * 17) mod 60, (i * 53 + j * 11) mod 40]));
      end;
      sb.Append(']}');
    end;
    sb.Append(']}');
    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf24bit;
      bmp.SetSize(400, 300);
      chart := NewChart(400, 300, sb.ToString);
      try
        chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
        AssertEquals('the first paint: the first run''s layer alone', 1, Length(chart.Levels));
        n := 0;
        while chart.ProgressiveUnfinished and (n < 20) do
        begin
          chart.ProgressTick;
          chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
          Inc(n);
        end;
        AssertFalse('drawn to the end', chart.ProgressiveUnfinished);
        AssertEquals('a layer per run', 2, Length(chart.Levels));
        last := FrameOf(bmp);
        { the layers dropped (another rendering and back): drawn again whole }
        chart.ExactRendering := not chart.ExactRendering;
        chart.ExactRendering := not chart.ExactRendering;
        chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
        AssertTrue('the progress frames drew every row', last = FrameOf(bmp));
      finally
        chart.Free;
      end;
    finally
      bmp.Free;
    end;
  finally
    sb.Free;
  end;
end;

{ ROWS SELECTED WHILE THE RUN DRAWS: a selection lifts a symbol's z2 (9), so
  it goes after the later chunks' rows in the order -- the chunks drawn
  after it are under it on the layer, not what a drawing in paint order
  gives, and the next selection draws the layer whole, as with the layer
  regions off }
procedure TAdvChartProgLayersTest.TestRowsSelectedDuringTheRun;
var
  frames: array[Boolean] of TStringList;
  on_: Boolean;
  chart: TPlProbe;
  bmp: TBitmap;
  sb: TStringBuilder;
  i, k: Integer;
  opt: string;

  procedure Step(AAct: string);
  begin
    if AAct <> '' then chart.DispatchAction(AAct)
    else chart.ProgressTick;
    chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
    frames[on_].Add(FrameOf(bmp));
  end;

begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"animation": false, "xAxis": {}, "yAxis": {}, "series": [');
    sb.Append('{"type": "scatter", "progressive": 10, "progressiveThreshold": 40, "symbolSize": 22, "selectedMode": "multiple",');
    sb.Append(' "itemStyle": {"opacity": 0.7}, "select": {"itemStyle": {"color": "#000000"}}, "data": [');
    for i := 0 to 99 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append(Format('[%d,%d]', [(i * 7) mod 20, (i * 3) mod 12]));
    end;
    sb.Append(']}]}');
    opt := sb.ToString;
  finally
    sb.Free;
  end;
  frames[False] := TStringList.Create;
  frames[True] := TStringList.Create;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(480, 400);
    for on_ := False to True do
    begin
      TyAdvChartLayerRegionForTest(on_);
      chart := NewChart(480, 400, opt);
      try
        chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
        Step('');
        Step('{"type": "select", "seriesIndex": 0, "dataIndex": 2}');
        Step('');
        Step('{"type": "select", "seriesIndex": 0, "dataIndex": 3}');
        Step('');
        Step('');
        Step('{"type": "select", "seriesIndex": 0, "dataIndex": 4}');
        Step('{"type": "unselect", "seriesIndex": 0, "dataIndex": 3}');
        Step('');
        Step('{"type": "select", "seriesIndex": 0, "dataIndex": 5}');
        while chart.ProgressiveUnfinished do Step('');
        Step('{"type": "select", "seriesIndex": 0, "dataIndex": 6}');
      finally
        chart.Free;
      end;
    end;
    AssertEquals('as many frames', frames[False].Count, frames[True].Count);
    for k := 0 to frames[False].Count - 1 do
      AssertTrue(Format('frame %d the same pixels', [k]), frames[False][k] = frames[True][k]);
  finally
    bmp.Free;
    frames[False].Free;
    frames[True].Free;
    TyAdvChartLayerRegionForTest(True);
  end;
end;

{ THE LAYER'S LAST POSITION AFTER A REGION DRAWN AGAIN (290p-14): rows
  selected (z2 + 9: past every row of the run, drawn or not) and unselected
  while the run draws, each patch drawing the layer again in part. The last
  position a layer keeps -- what the next chunk's rows are held against to
  tell a drawing in paint order -- is its last drawn row's place in the
  order as it stands after the region, not the one before the patch
  [was: by the mutant 290p-14, the lifted rows' place kept after they
  dropped] }
procedure TAdvChartProgLayersTest.TestALiftedRowPastARunNotYetDrawn;
var
  chart: TPlProbe;
  bmp: TBitmap;
  sb: TStringBuilder;
  i, r0: Integer;
  bad: string;

  procedure Step(const AAct: string);
  var q, want, lv: Integer; pe: PTyChartElement;
  begin
    chart.DispatchAction(AAct);
    chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
    if Length(chart.Levels) <> 1 then
    begin
      bad := bad + AAct + ': layers ' + IntToStr(Length(chart.Levels)) + '; ';
      Exit;
    end;
    lv := chart.Levels[0];
    want := -1;
    for q := 0 to chart.List.Count - 1 do
    begin
      pe := chart.List.Ref(chart.List.PaintOrder(q));
      if (pe^.ProgChunk > 0) and not pe^.ProgHidden and not pe^.Ignore and (pe^.ZLevel = lv) then
        want := q;
    end;
    if chart.LastPos(0) <> want then
      bad := bad + Format('%s: last position %d, the order''s %d; ', [AAct, chart.LastPos(0), want]);
  end;

begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"animation": false, "xAxis": {}, "yAxis": {}, "series": [');
    sb.Append('{"type": "scatter", "progressive": 10, "progressiveThreshold": 40, "symbolSize": 22, "selectedMode": "multiple",');
    sb.Append(' "itemStyle": {"opacity": 0.7}, "select": {"itemStyle": {"color": "#000000"}}, "data": [');
    for i := 0 to 99 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append(Format('[%d,%d]', [(i * 7) mod 20, (i * 3) mod 12]));
    end;
    sb.Append(']}]}');
    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf24bit;
      bmp.SetSize(480, 400);
      TyAdvChartLayerRegionForTest(True);
      chart := NewChart(480, 400, sb.ToString);
      try
        bad := '';
        chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
        chart.ProgressTick;
        chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
        { (the first state change after a build: the list built again) }
        Step('{"type": "select", "seriesIndex": 0, "dataIndex": 2}');
        r0 := TyAdvChartLayerRegionsForTest;
        Step('{"type": "select", "seriesIndex": 0, "dataIndex": 3}');
        Step('{"type": "unselect", "seriesIndex": 0, "dataIndex": 2}');
        Step('{"type": "unselect", "seriesIndex": 0, "dataIndex": 3}');
        AssertTrue('the patches drew the layer in part', TyAdvChartLayerRegionsForTest - r0 >= 2);
        AssertEquals('the last positions as the order stands', '', bad);
      finally
        chart.Free;
      end;
    finally
      bmp.Free;
    end;
  finally
    sb.Free;
  end;
end;

{ A ROW A STATE PATCH WROTE KEEPS THE ZLEVEL THE BUILD GAVE IT: a scatter of
  more rows than its threshold on its own zlevel (allocateZlevels), one of
  a zlevel written into the series; a selection, a hover, and their undoing
  patched into the list -- each row on its series' zlevel, as zrender's
  states never touch it [was: the journal's copy from before the build
  wrote the levels put back, the row on zlevel 0] }
procedure TAdvChartProgLayersTest.TestAPatchedRowKeepsItsZLevel;
var
  chart: TPlProbe;
  bmp: TBitmap;
  sb: TStringBuilder;
  i, k, want: Integer;
  el: TTyChartElement;
  bad: string;

  procedure Check(const AWhen: string);
  var q: Integer;
  begin
    for q := 0 to chart.List.Count - 1 do
    begin
      el := chart.List.Element(q);
      if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex < 0) then Continue;
      if el.Datum.SeriesIndex = 0 then want := 1 else want := 4;
      if el.ZLevel <> want then
        bad := bad + Format('%s: series %d row %d on zlevel %d, not %d; ', [AWhen,
          el.Datum.SeriesIndex, el.Datum.DataIndex, el.ZLevel, want]);
    end;
  end;

begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"animation": false, "xAxis": {}, "yAxis": {}, "series": [');
    sb.Append('{"type": "scatter", "progressive": 10, "progressiveThreshold": 40, "symbolSize": 12, "selectedMode": "multiple",');
    sb.Append(' "select": {"itemStyle": {"color": "#000000"}}, "data": [');
    for i := 0 to 59 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append(Format('[%d,%d]', [(i * 7) mod 20, (i * 3) mod 12]));
    end;
    sb.Append(']}, {"type": "scatter", "zlevel": 4, "symbolSize": 12, "selectedMode": "multiple",');
    sb.Append(' "select": {"itemStyle": {"color": "#000000"}}, "data": [[1, 1], [2, 2], [3, 3]]}]}');
    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf24bit;
      bmp.SetSize(400, 300);
      chart := NewChart(400, 300, sb.ToString);
      try
        bad := '';
        chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
        chart.ProgressTick;
        chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
        Check('built');
        for k := 0 to 2 do
        begin
          chart.DispatchAction(Format('{"type": "select", "seriesIndex": 0, "dataIndex": %d}', [k]));
          chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
          chart.DispatchAction(Format('{"type": "select", "seriesIndex": 1, "dataIndex": %d}', [k]));
          chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
          Check(Format('select %d', [k]));
        end;
        chart.DispatchAction('{"type": "unselect", "seriesIndex": 0, "dataIndex": 1}');
        chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
        chart.DispatchAction('{"type": "highlight", "seriesIndex": 1, "dataIndex": 2}');
        chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
        Check('unselect, highlight');
        AssertEquals('every row on its series'' zlevel', '', bad);
      finally
        chart.Free;
      end;
    finally
      bmp.Free;
    end;
  finally
    sb.Free;
  end;
end;

{ PREVENTINCREMENTAL: a heatmap on a geo (lng / lat), a lines series whose
  effect shows -- no progressive pipeline, drawn at once; a heatmap on a
  grid of as many rows comes in chunks [was: every one in chunks] }
procedure TAdvChartProgLayersTest.TestAPreventedRunIsDrawnAtOnce;
const
  cSq = '{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"name":"A"},'
    + '"geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}}]}';
var
  chart: TPlProbe;
  bmp: TBitmap;
  k: Integer;
  opt, rows, cells: string;
begin
  TyChartRegisterMap('pl-sq', cSq);
  rows := '';
  cells := '';
  for k := 0 to 29 do
  begin
    if k > 0 then
    begin
      rows := rows + ',';
      cells := cells + ',';
    end;
    rows := rows + Format('[%d,%d,0.5]', [(k * 37) mod 10, (k * 53) mod 10]);
    cells := cells + Format('[%d,%d,0.5]', [k mod 6, k div 6]);
  end;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(400, 300);
    for k := 0 to 2 do
    begin
      case k of
        0: opt := '{"animation":false,"geo":{"map":"pl-sq"},"visualMap":{"min":0,"max":1,"show":false},'
          + '"series":[{"type":"heatmap","coordinateSystem":"geo","progressive":10,"progressiveThreshold":20,'
          + '"data":[' + rows + ']}]}';
        1: opt := '{"animation":false,"xAxis":{"min":0,"max":10},"yAxis":{"min":0,"max":10},'
          + '"series":[{"type":"lines","coordinateSystem":"cartesian2d","progressive":10,"progressiveThreshold":20,'
          + '"effect":{"show":true},"data":[' + StringReplace(StringReplace(rows, '[', '{"coords":[[', [rfReplaceAll]),
            ',0.5]', '],[5,5]]}', [rfReplaceAll]) + ']}]}';
      else
        opt := '{"animation":false,"visualMap":{"min":0,"max":1,"show":false},'
          + '"xAxis":{"type":"category","data":["a","b","c","d","e","f"]},"yAxis":{"type":"category","data":["a","b","c","d","e"]},'
          + '"series":[{"type":"heatmap","progressive":10,"progressiveThreshold":20,"data":[' + cells + ']}]}';
      end;
      chart := NewChart(400, 300, opt);
      try
        AssertEquals(Format('case %d parses', [k]), '', chart.OptionError);
        chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
        AssertEquals(Format('case %d: in chunks', [k]), k = 2, chart.ProgressiveUnfinished);
      finally
        chart.Free;
      end;
    end;
  finally
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartProgLayersTest);
end.
