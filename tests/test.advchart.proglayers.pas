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
    function Levels: TTyIntegerArray;
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
  end;

implementation

procedure TPlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TPlProbe.Cached(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderCached(ACanvas, ARect, 96);
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
    sb.Append('{"animation":false,"grid":{"left":40,"right":40,"top":40,"bottom":40},');
    sb.Append('"xAxis":{"type":"category","show":false},"yAxis":{"type":"value","min":0,"max":10,"show":false},');
    sb.Append('"graphic":[{"type":"rect","zlevel":1,"shape":{"x":0,"y":0,"width":400,"height":300},');
    sb.Append('"style":{"fill":"#0000ff"}}],');
    sb.Append('"series":[{"type":"bar","large":true,"largeThreshold":5,"progressive":4,"progressiveThreshold":10,');
    sb.Append('"itemStyle":{"color":"#ff0000"},"data":[');
    for i := 0 to 19 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append('9');
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
        { the first category's red bar (x 41.6 to 47.2 px, to 9 of 10) where
          no green one is: the rect's blue there }
        px := bmp.Canvas.Pixels[44, 40 + 44];
        AssertTrue(Format('fast %s: the zlevel 0 run under the rect: %.6x', [BoolToStr(fast, True), px]),
          (Blue(px) > 200) and (Red(px) < 60) and (Green(px) < 60));
        { and the green bars over it near the bottom }
        k := 0;
        for n := 40 to 360 do
          if (Green(bmp.Canvas.Pixels[n, 300 - 40 - 20]) > 200) and (Blue(bmp.Canvas.Pixels[n, 300 - 40 - 20]) < 60) then
            Inc(k);
        AssertTrue(Format('fast %s: the zlevel 2 run over the rect (%d px)', [BoolToStr(fast, True), k]), k > 40);
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

function AcrossOption: string;
var sb: TStringBuilder; i, j: Integer;
begin
  sb := TStringBuilder.Create;
  try
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
  n, k, f0, used: Integer;
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
    bmp.SetSize(480, 360);
    for fast := False to True do
    begin
      TyAdvChartProgFastForTest(fast);
      f0 := TyAdvChartProgFastFramesForTest;
      chart := NewChart(480, 360, AcrossOption);
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
        AssertEquals('a layer per run', 2, Length(chart.Levels));
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

initialization
  RegisterTest(TAdvChartProgLayersTest);
end.
