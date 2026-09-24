unit test.advchart.scalealign;
{$mode objfpc}{$H+}
{ One axis' ticks aligned to another's -- held to upstream to the bit.

  tools/advchart-oracle/scale-align.js runs the real ECharts 6.1 build and
  records, for every axis upstream aligns -- each radar indicator against the
  radar's dummy scale of splitNumber segments, and each `alignTicks` axis
  against its reference -- what scaleCalcAlign was given (the reference's
  ticks and step, the target's extent, which ends were fixed, whether it
  includes zero, its pixel span) and what it answered: the fractional ends,
  the whole segments, the validated extent, the aligned extent, the step and
  its precision, the nice extent, the ticks and their labels, and on a radar
  where each tick lands.

  THE RULES IT HOLDS THE PORT TO: a step that starts at niceMin(span /
  segments) and climbs 1, 2, 3, 5, 10, at most fifty times -- with one more
  climb after the last miss; two fixed ends divide instead, and round the
  step only after the nice ends were made from it; a precision from the
  pixel span that may be not-a-number and is not clamped when stored; the
  previous pass's min and max deciding which way an odd spare segment goes;
  the ticks walking exactly the count of segments and landing the last on
  the nice end.

  Everything is compared to the bit. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     fpjson, jsonparser, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale,
     tyControls.AdvChart.JsMath, tyControls.AdvChart.Radar,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder,
     tyControls.AdvanceChart;
type
  TScaleAlignProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function RadarAt(AIndex: Integer): TTyRadar;
  end;

  TAdvChartScaleAlignOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameArr(const AWhat: string; const AGot: TTyDoubleArray;
      AWant: TJSONArray);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryAlignmentIsUpstreams;
    procedure TestEveryRadarSpokeIsAlignedSo;
    procedure TestEveryAlignedAxisIsAlignedSo;
    procedure TestTheHelpersAtTheirEdges;
    procedure TestARadarAtAnotherPPIAlignsInLogicalPixels;
  end;

implementation

procedure TScaleAlignProbe.Render(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TScaleAlignProbe.RadarAt(AIndex: Integer): TTyRadar;
begin
  Result := RadarLayout(AIndex);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-scale-align.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  Move(q, Result, SizeOf(Result));
end;

function HexArr(AData: TJSONData): TTyDoubleArray;
var i: Integer; a: TJSONArray;
begin
  Result := nil;
  if not (AData is TJSONArray) then Exit;
  a := TJSONArray(AData);
  SetLength(Result, a.Count);
  for i := 0 to a.Count - 1 do Result[i] := HexNum(a.Items[i]);
end;

function Fmt(A: Double): string;
begin
  Result := TyJsNumberToString(A);
end;

procedure TAdvChartScaleAlignOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartScaleAlignOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartScaleAlignOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

{ To the bit, -0 as 0, not-a-number as itself. }
procedure TAdvChartScaleAlignOracleTest.Same(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  want := HexNum(AWant);
  if IsNan(want) and IsNan(AGot) then Exit;
  if IsNan(want) or IsNan(AGot) or (want <> AGot) then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartScaleAlignOracleTest.SameArr(const AWhat: string;
  const AGot: TTyDoubleArray; AWant: TJSONArray);
var i: Integer;
begin
  Inc(FCompared);
  if Length(AGot) <> AWant.Count then
  begin
    Miss(Format('%s: %d upstream, %d here', [AWhat, AWant.Count, Length(AGot)]));
    Exit;
  end;
  for i := 0 to AWant.Count - 1 do
    Same(Format('%s[%d]', [AWhat, i]), AGot[i], AWant.Items[i]);
end;

{ The step a log target searches is in its own decades. }
function LogOf(AValue, ABase: Double): Double;
begin
  Result := TyJsLog(AValue) / TyJsLog(ABase);
end;

procedure TAdvChartScaleAlignOracleTest.TestEveryAlignmentIsUpstreams;
var
  cases, axes: TJSONArray;
  cs, ax, inp, outp: TJSONObject;
  c, k, i: Integer;
  ai: TTyAlignInput;
  r: TTyAlignResult;
  sc: TTyIntervalScale;
  ticks: TTyDoubleArray;
  labels: TJSONArray;
  words: string;
  mask: TFPUExceptionMask;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := TJSONObject(cases.Items[c]);
    if cs.Get('deferred', False) then Continue;
    axes := cs.Arrays['axes'];
    for k := 0 to axes.Count - 1 do
    begin
      ax := TJSONObject(axes.Items[k]);
      FName := cs.Strings['name'] + ' ' + ax.Strings['path'];
      inp := ax.Objects['input'];
      outp := ax.Objects['out'];
      ai := Default(TTyAlignInput);
      ai.RefTicks := HexArr(inp.Find('refTicks'));
      ai.RefExpTicks := HexArr(inp.Find('refExpTicks'));
      ai.RefInterval := HexNum(inp.Find('refInterval'));
      ai.FixLo := TJSONArray(inp.Find('fix')).Booleans[0];
      ai.FixHi := TJSONArray(inp.Find('fix')).Booleans[1];
      ai.Incl0 := inp.Booleans['incl0'];
      ai.IsLog := inp.Booleans['isLog'];
      ai.Base := HexNum(inp.Find('base'));
      ai.PxSpan := HexNum(inp.Find('px'));
      ai.Lo := HexNum(TJSONArray(inp.Find('effMM')).Items[0]);
      ai.Hi := HexNum(TJSONArray(inp.Find('effMM')).Items[1]);
      if ai.IsLog then
      begin
        mask := GetExceptionMask;
        SetExceptionMask(mask + [exInvalidOp, exZeroDivide, exOverflow]);
        try
          ai.Lo := LogOf(ai.Lo, ai.Base);
          ai.Hi := LogOf(ai.Hi, ai.Base);
        finally
          ClearExceptions(False);
          SetExceptionMask(mask);
        end;
      end;
      r := TyScaleCalcAlign(ai);
      Same('t0', r.T0, outp.Find('t0'));
      Same('t1', r.T1, outp.Find('t1'));
      Inc(FCompared);
      if r.Seg <> outp.Integers['seg'] then
        Miss(Format('%d segments upstream, %d here', [outp.Integers['seg'], r.Seg]));
      Same('valid lo', r.ValidLo, TJSONArray(outp.Find('validExt')).Items[0]);
      Same('valid hi', r.ValidHi, TJSONArray(outp.Find('validExt')).Items[1]);
      Same('lo', r.Lo, TJSONArray(outp.Find('extent')).Items[0]);
      Same('hi', r.Hi, TJSONArray(outp.Find('extent')).Items[1]);
      Same('interval', r.Interval, outp.Find('interval'));
      Same('precision', r.Precision, outp.Find('intervalPrecision'));
      Same('nice lo', r.NiceLo, TJSONArray(outp.Find('niceExtent')).Items[0]);
      Same('nice hi', r.NiceHi, TJSONArray(outp.Find('niceExtent')).Items[1]);
      if outp.Find('passes') <> nil then
      begin
        Inc(FCompared);
        if (r.Passes <> outp.Integers['passes'])
          or (r.Exhausted <> outp.Get('exhausted', False)) then
          Miss(Format('%d passes (exhausted %s) upstream, %d (%s) here',
            [outp.Integers['passes'], BoolToStr(outp.Get('exhausted', False), True),
             r.Passes, BoolToStr(r.Exhausted, True)]));
      end;

      { AND THE TICKS THE ANSWER WALKS, in its own stepping space. }
      sc := TTyIntervalScale.Create;
      try
        sc.SetAligned(r.Lo, r.Hi, r.Interval, r.Precision, r.Seg, r.NiceLo,
          r.NiceHi);
        ticks := nil;
        SetLength(ticks, 0);
        for i := 0 to High(sc.GetTicks) do
        begin
          SetLength(ticks, Length(ticks) + 1);
          ticks[High(ticks)] := sc.GetTicks[i].Value;
        end;
        SameArr('ticks', ticks, TJSONArray(outp.Find('ticks')));
        if not ai.IsLog then
        begin
          labels := TJSONArray(outp.Find('labels'));
          if Length(ticks) = labels.Count then
            for i := 0 to labels.Count - 1 do
            begin
              Inc(FCompared);
              words := TyScaleValueLabel(sc, ticks[i], Default(TTyLabelPrecision));
              if words <> labels.Strings[i] then
                Miss(Format('label %d is %s upstream, %s here',
                  [i, labels.Strings[i], words]));
            end;
        end;
      finally
        sc.Free;
      end;
    end;
  end;
  AssertTrue(Format('a great deal was compared (%d)', [FCompared]),
    FCompared > 2000);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

procedure TAdvChartScaleAlignOracleTest.TestEveryRadarSpokeIsAlignedSo;
var
  form: TForm;
  ctl: TTyStyleController;
  chart: TScaleAlignProbe;
  bmp: TBGRABitmap;
  cases, axes: TJSONArray;
  cs, ax, outp, rad: TJSONObject;
  c, k, i, spoke, w, h, ran: Integer;
  radar: TTyRadar;
  sc: TTyIntervalScale;
  path: string;
  got: TTyDoubleArray;
  want: TJSONArray;
begin
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  ran := 0;
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    chart := TScaleAlignProbe.Create(form);
    chart.Parent := form;
    chart.Controller := ctl;
    cases := TJSONObject(FRoot).Arrays['cases'];
    for c := 0 to cases.Count - 1 do
    begin
      cs := TJSONObject(cases.Items[c]);
      if (cs.Strings['kind'] <> 'radar') or cs.Get('deferred', False)
        or cs.Get('documentary', False) then Continue;
      FName := cs.Strings['name'];
      w := cs.Objects['canvas'].Integers['w'];
      h := cs.Objects['canvas'].Integers['h'];
      chart.SetBounds(0, 0, w, h);
      chart.Option := '';
      chart.Option := cs.Objects['option'].AsJSON;
      bmp := TBGRABitmap.Create(w, h, BGRA(255, 255, 255, 255));
      try
        chart.Render(bmp.Canvas, Rect(0, 0, w, h), 96);
      finally
        bmp.Free;
      end;
      Inc(ran);
      radar := chart.RadarAt(0);
      Inc(FCompared);
      if radar = nil then
      begin
        Miss('no radar here');
        Continue;
      end;
      rad := cs.Objects['radar'];
      Inc(FCompared);
      if Math.Max(-1, radar.RingCount) <> rad.Integers['ringCount'] then
        Miss(Format('%d rings upstream, %d here', [rad.Integers['ringCount'],
          radar.RingCount]));
      axes := cs.Arrays['axes'];
      for k := 0 to axes.Count - 1 do
      begin
        ax := TJSONObject(axes.Items[k]);
        path := ax.Strings['path'];
        { "radar0.iN" }
        spoke := StrToIntDef(Copy(path, Pos('.i', path) + 2, MaxInt), -1);
        if (spoke < 0) or (spoke >= radar.AxisCount) then
        begin
          Miss(path + ' has no spoke here');
          Continue;
        end;
        outp := ax.Objects['out'];
        sc := TTyIntervalScale(radar.GetAxis(spoke).Scale);
        Same(path + ' lo', sc.GetExtent.Start, TJSONArray(outp.Find('extent')).Items[0]);
        Same(path + ' hi', sc.GetExtent.Stop, TJSONArray(outp.Find('extent')).Items[1]);
        Same(path + ' interval', sc.Interval, outp.Find('interval'));
        Same(path + ' nice lo', sc.NiceStart, TJSONArray(outp.Find('niceExtent')).Items[0]);
        Same(path + ' nice hi', sc.NiceStop, TJSONArray(outp.Find('niceExtent')).Items[1]);
        want := TJSONArray(outp.Find('ticks'));
        SetLength(got, want.Count);
        for i := 0 to want.Count - 1 do got[i] := radar.RingValue(spoke, i);
        SameArr(path + ' ring value', got, want);
        if outp.Find('tickCoords') is TJSONArray then
        begin
          want := TJSONArray(outp.Find('tickCoords'));
          SetLength(got, want.Count);
          for i := 0 to want.Count - 1 do got[i] := radar.RingRadiusOf(spoke, i);
          SameArr(path + ' ring radius', got, want);
        end;
      end;
    end;
  finally
    form.Free;
    ctl.Free;
  end;
  AssertTrue(Format('the radars ran (%d)', [ran]), ran >= 40);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

procedure TAdvChartScaleAlignOracleTest.TestTheHelpersAtTheirEdges;
begin
  { `round(x, NaN)` is x itself, not x to no places. }
  AssertTrue('a precision that is not a number rounds nothing',
    TyRoundP(1.25, NaN) = 1.25);
  AssertTrue('and past twenty is twenty',
    TyRoundP(1 / 3, 28) = TyJsToFixed(1 / 3, 20));
  { `!f`: a leading digit of nothing climbs to one. }
  AssertTrue('a step of nothing climbs to one', TyIncreaseInterval(0) = 1);
  AssertTrue('two is three', TyIncreaseInterval(20) = 30);
  AssertTrue('three is five', TyIncreaseInterval(0.3) = 0.5);
  AssertTrue('five is ten', TyIncreaseInterval(5) = 10);
end;

procedure TAdvChartScaleAlignOracleTest.TestARadarAtAnotherPPIAlignsInLogicalPixels;
var
  form: TForm;
  ctl: TTyStyleController;
  chart: TScaleAlignProbe;
  bmp: TBGRABitmap;
  cases, axes: TJSONArray;
  cs, ax, outp: TJSONObject;
  c, k, w, h, spoke, ran: Integer;
  radar: TTyRadar;
  sc: TTyIntervalScale;
  path: string;
begin
  { THE SAME RADAR AT ONE AND A HALF TIMES THE PIXELS: the radius is half as
    big again in device px, the same in logical px -- and upstream rounds a
    both-fixed step by the logical span. }
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  ran := 0;
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    chart := TScaleAlignProbe.Create(form);
    chart.Parent := form;
    chart.Controller := ctl;
    cases := TJSONObject(FRoot).Arrays['cases'];
    for c := 0 to cases.Count - 1 do
    begin
      cs := TJSONObject(cases.Items[c]);
      if (cs.Strings['name'] <> 'R2-a-sn7') and (cs.Strings['name'] <> 'LOG10-BOUNDARY') then
        Continue;
      FName := cs.Strings['name'] + ' @144';
      w := cs.Objects['canvas'].Integers['w'] * 3 div 2;
      h := cs.Objects['canvas'].Integers['h'] * 3 div 2;
      chart.SetBounds(0, 0, w, h);
      chart.Option := '';
      chart.Option := cs.Objects['option'].AsJSON;
      bmp := TBGRABitmap.Create(w, h, BGRA(255, 255, 255, 255));
      try
        chart.Render(bmp.Canvas, Rect(0, 0, w, h), 144);
      finally
        bmp.Free;
      end;
      Inc(ran);
      radar := chart.RadarAt(0);
      axes := cs.Arrays['axes'];
      for k := 0 to axes.Count - 1 do
      begin
        ax := TJSONObject(axes.Items[k]);
        path := ax.Strings['path'];
        spoke := StrToIntDef(Copy(path, Pos('.i', path) + 2, MaxInt), -1);
        outp := ax.Objects['out'];
        sc := TTyIntervalScale(radar.GetAxis(spoke).Scale);
        Same(path + ' interval', sc.Interval, outp.Find('interval'));
        Same(path + ' hi', sc.GetExtent.Stop, TJSONArray(outp.Find('extent')).Items[1]);
      end;
    end;
  finally
    form.Free;
    ctl.Free;
  end;
  AssertEquals('both cases ran', 2, ran);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

{ The axis a path names -- "y1" is y axis component 1 -- on any grid. }
function AxisAt(ABuild: TTyChartBuild; const APath: string): TTyAxis;
var g, k, idx: Integer; gb: TTyGridBuild;
begin
  Result := nil;
  if ABuild = nil then Exit;
  idx := StrToIntDef(Copy(APath, 2, MaxInt), -1);
  for g := 0 to ABuild.GridCount - 1 do
  begin
    gb := ABuild.Grid(g);
    if APath[1] = 'x' then
    begin
      for k := 0 to gb.XAxisCount - 1 do
        if gb.XAxis(k).ComponentIndex = idx then Exit(gb.XAxis(k));
    end
    else
      for k := 0 to gb.YAxisCount - 1 do
        if gb.YAxis(k).ComponentIndex = idx then Exit(gb.YAxis(k));
  end;
end;

procedure TAdvChartScaleAlignOracleTest.TestEveryAlignedAxisIsAlignedSo;
var
  form: TForm;
  ctl: TTyStyleController;
  chart: TScaleAlignProbe;
  bmp: TBGRABitmap;
  cases, axes: TJSONArray;
  cs, ax, outp: TJSONObject;
  c, k, w, h, ran: Integer;
  axis: TTyAxis;
  sc: TTyIntervalScale;
  path: string;
  outer: TJSONData;
begin
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  ran := 0;
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    chart := TScaleAlignProbe.Create(form);
    chart.Parent := form;
    chart.Controller := ctl;
    cases := TJSONObject(FRoot).Arrays['cases'];
    for c := 0 to cases.Count - 1 do
    begin
      cs := TJSONObject(cases.Items[c]);
      if (cs.Strings['kind'] <> 'cartesian') or (cs.Strings['scope'] <> 'C')
        or cs.Get('deferred', False) or cs.Get('documentary', False) then Continue;
      FName := cs.Strings['name'];
      w := cs.Objects['canvas'].Integers['w'];
      h := cs.Objects['canvas'].Integers['h'];
      chart.SetBounds(0, 0, w, h);
      chart.Option := '';
      chart.Option := cs.Objects['option'].AsJSON;
      bmp := TBGRABitmap.Create(w, h, BGRA(255, 255, 255, 255));
      try
        chart.Render(bmp.Canvas, Rect(0, 0, w, h), 96);
      finally
        bmp.Free;
      end;
      Inc(ran);
      axes := cs.Arrays['axes'];
      for k := 0 to axes.Count - 1 do
      begin
        ax := TJSONObject(axes.Items[k]);
        path := ax.Strings['path'];
        axis := AxisAt(chart.Build, path);
        Inc(FCompared);
        if (axis = nil) or not (axis.Scale is TTyIntervalScale) then
        begin
          Miss(path + ' is no number axis here');
          Continue;
        end;
        sc := TTyIntervalScale(axis.Scale);
        outp := ax.Objects['out'];
        outer := outp.Find('outerExtent');
        if outer is TJSONArray then
        begin
          Same(path + ' lo', sc.GetExtent.Start, TJSONArray(outer).Items[0]);
          Same(path + ' hi', sc.GetExtent.Stop, TJSONArray(outer).Items[1]);
        end
        else
        begin
          Same(path + ' lo', sc.GetExtent.Start, TJSONArray(outp.Find('extent')).Items[0]);
          Same(path + ' hi', sc.GetExtent.Stop, TJSONArray(outp.Find('extent')).Items[1]);
        end;
        Same(path + ' interval', sc.Interval, outp.Find('interval'));
        Same(path + ' nice lo', sc.NiceStart, TJSONArray(outp.Find('niceExtent')).Items[0]);
        Same(path + ' nice hi', sc.NiceStop, TJSONArray(outp.Find('niceExtent')).Items[1]);
        SameArr(path + ' ticks', sc.StepTicks(False), TJSONArray(outp.Find('ticks')));
      end;
    end;
  finally
    form.Free;
    ctl.Free;
  end;
  AssertTrue(Format('the charts ran (%d)', [ran]), ran >= 40);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

initialization
  RegisterTest(TAdvChartScaleAlignOracleTest);
end.
