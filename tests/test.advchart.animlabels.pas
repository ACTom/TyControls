unit test.advchart.animlabels;
{$mode objfpc}{$H+}
{ LABELS, MARKERS, WHAT NEVER STOPS AND THE AXIS POINTER, held to upstream.
  [Batch 92, AN4]

  The fixture timelines of the counts, the markers, the ripples and the end
  label run in test.advchart.animenter (the enter cases of both fixtures)
  and test.advchart.animupdate (the update cases); this unit holds what
  those two do not:

    - the axis pointer's slide, against tests/fixtures/advchart-
      animation-an4.json's `pointer` cases (tools/advchart-oracle/
      animation-an4.js): the option at T0 settled on the oracle's frames, a
      first move at T0 + 6000 (direct) settled, then the moves from T1 =
      T0 + 10000 through the control's own mouse, and at every sample the
      pointer proxy's moving key BIT FOR BIT, its animators and the
      pointer's clips against the pointer element's (upstream tweens the
      label beside it with the same timing; the port draws the label off
      the pointer);
    - interpolateRawValues' precision rule, by hand;
    - _endLabelOnDuring's choice of point and value, by hand;
    - the end label in the frame, the ripples' phase over many loops, the
      layers once only loops are left, a scatter's labels fading whatever
      valueAnimation says, the pointer sliding from where it was hidden. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimOpt,
     tyControls.AdvChart.AnimView, tyControls.AdvChart.LinePath,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TAlProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Hover(AX, AY: Integer);
    procedure Leave;
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TAdvChartAnimLabelsTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAlProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    FSeen: TStringList;
    procedure Miss(const AWhere: string; const AOnce: string = '');
    procedure NewChart(AMode: TTyChartAnimationMode);
    procedure Load(const AOption: string);
    function Draw: TBGRABitmap;
    procedure RunPointerCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPointerTimelinesAsUpstream;
    procedure TestInterpolatedValuePrecision;
    procedure TestEndLabelStepChoices;
    procedure TestEndLabelRidesTheClipInTheFrame;
    procedure TestACountSkipsAnUnchangedValue;
    procedure TestRippleLoopKeepsItsPhase;
    procedure TestOnlyLoopsLeftSplitTheLayers;
    procedure TestOtherSeriesLabelsFadeWhateverValueAnimationSays;
    procedure TestThePointerSlidesFromWhereItWasHidden;
    procedure TestPointerOffModeJumps;
  end;

implementation

const
  cW = 400;
  cH = 300;

var
  GAn4: TJSONData = nil;

function An4: TJSONObject;
var sl: TStringList;
begin
  if GAn4 = nil then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
        + 'advchart-animation-an4.json');
      GAn4 := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GAn4);
end;

function T0: Double;
begin
  Result := An4.Objects['clock'].Floats['T0'];
end;

function T1: Double;
begin
  Result := T0 + An4.Objects['clock'].Floats['T1Offset'];
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Hex(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := Hex(A) = Hex(B);
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

{ ==================== the probe ==================== }

function TAlProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TAlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TAlProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TAlProbe.Leave;
begin
  MouseLeave;
end;

function TAlProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TAlProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== plumbing ==================== }

procedure TAdvChartAnimLabelsTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FSeen := TStringList.Create;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartAnimLabelsTest.TearDown;
begin
  FreeAndNil(FSeen);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartAnimLabelsTest.Miss(const AWhere: string; const AOnce: string);
begin
  Inc(FBad);
  if AOnce <> '' then
  begin
    if FSeen.IndexOf(AOnce) >= 0 then Exit;
    FSeen.Add(AOnce);
  end;
  if FSeen.Count + Ord(AOnce = '') <= 40 then
    FReport := FReport + LineEnding + '  ' + AWhere;
end;

procedure TAdvChartAnimLabelsTest.NewChart(AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TAlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
end;

function TAdvChartAnimLabelsTest.Draw: TBGRABitmap;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  Result := FBmp;
end;

procedure TAdvChartAnimLabelsTest.Load(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  FChart.SetBounds(0, 0, cW, cH);
  Draw;
end;

{ ==================== the pointer's timelines ==================== }

procedure TAdvChartAnimLabelsTest.RunPointerCase(ACase: TJSONObject);
var
  name, key: string;
  samples, moves, els, anim: TJSONArray;
  ptrEl, track: TJSONObject;
  done: array of Boolean;
  s, k, at, upAnim: Integer;
  t: Double;
  p: TTyChartAnimProxy;
  v: TTyAnimValue;
  upTrack: TJSONArray;
  up: Double;
begin
  name := ACase.Strings['id'];
  NewChart(camAlways);
  Load(ACase.Elements['option'].AsJSON);
  { the oracle's settle, then the first move, direct, and its frames }
  t := 16;
  while t <= 5000 do
  begin
    FChart.AnimTick(T0 + t);
    t := t + 250;
  end;
  FChart.AnimNow := T0 + 6000;
  FChart.Hover(ACase.Objects['first'].Integers['x'], ACase.Objects['first'].Integers['y']);
  t := 16;
  while t <= 2000 do
  begin
    FChart.AnimTick(T0 + 6000 + t);
    t := t + 250;
  end;
  if FChart.AnimPointerClipCount <> 0 then Miss(name + ': the first show moved');
  { the pointer element: the first root's first child }
  els := ACase.Arrays['elements'];
  ptrEl := nil;
  for k := 0 to els.Count - 1 do
    if els.Objects[k].Strings['id'] = 'axisPointer/0.0' then ptrEl := els.Objects[k];
  if ptrEl = nil then
  begin
    Miss(name + ': no pointer element upstream');
    Exit;
  end;
  if ptrEl.Strings['type'] = 'Rect' then key := 'shape.x' else key := 'shape.x1';
  track := nil;
  if ptrEl.Find('track') is TJSONObject then track := ptrEl.Objects['track'];
  anim := nil;
  if ptrEl.Find('animators') is TJSONArray then anim := ptrEl.Arrays['animators'];
  { the moves from T1 }
  moves := ACase.Arrays['moves'];
  SetLength(done, moves.Count);
  FChart.AnimNow := T1;
  for k := 0 to moves.Count - 1 do
  begin
    done[k] := moves.Objects[k].Integers['at'] = 0;
    if done[k] then
      FChart.Hover(moves.Objects[k].Integers['x'], moves.Objects[k].Integers['y']);
  end;
  samples := An4.Arrays['samplesMs'];
  for s := 0 to samples.Count - 1 do
  begin
    for k := 0 to moves.Count - 1 do
    begin
      at := moves.Objects[k].Integers['at'];
      if (not done[k]) and (at > 0) and (at <= samples.Items[s].AsInteger) then
      begin
        FChart.AnimTick(T1 + at);
        FChart.AnimNow := T1 + at;
        FChart.Hover(moves.Objects[k].Integers['x'], moves.Objects[k].Integers['y']);
        done[k] := True;
      end;
    end;
    if s > 0 then FChart.AnimTick(T1 + samples.Items[s].AsFloat);
    p := FChart.AnimPointerProxy('xAxis0');
    if p = nil then
    begin
      Miss(name + ': no pointer proxy', name + 'none');
      Continue;
    end;
    Inc(FCompared);
    upAnim := 0;
    if anim <> nil then upAnim := anim.Items[s].AsInteger;
    if p.AnimatorCount <> upAnim then
      Miss(Format('%s t=%s: %d animators here, %d upstream', [name,
        samples.Items[s].AsString, p.AnimatorCount, upAnim]), name + 'anim');
    if FChart.AnimPointerClipCount <> upAnim then
      Miss(Format('%s t=%s: %d pointer clips here, %d upstream', [name,
        samples.Items[s].AsString, FChart.AnimPointerClipCount, upAnim]), name + 'clips');
    v := p.GetAnimProp(key);
    if v.Kind <> avkNumber then
    begin
      Miss(Format('%s: %s is not modelled', [name, key]), name + key + 'mod');
      Continue;
    end;
    if (track <> nil) and (track.Find(key) is TJSONArray) then
    begin
      upTrack := track.Arrays[key];
      up := FromHex(upTrack.Items[s].AsString);
    end
    else
      up := FromHex(ptrEl.Objects['final'].Strings[key]);
    if not SameBits(v.Num, up) then
      Miss(Format('%s t=%s: %s %s here, %s upstream', [name, samples.Items[s].AsString,
        key, Fmt(v.Num), Fmt(up)]), name + key);
  end;
end;

{ THE POINTER SLIDES (or jumps) AS UPSTREAM'S: a category band of 60 slides
  200 ms exponentialOut from where it is; the shadow's band with it; a
  second move in flight from the current place; the tooltip's own
  duration and easing; animation false, a band under 15 px: a jump; a
  value axis under a tooltip snaps and slides; the root's animation false
  does not reach the tooltip's pointer. }
procedure TAdvChartAnimLabelsTest.TestPointerTimelinesAsUpstream;
var
  cases: TJSONArray;
  c, ran: Integer;
begin
  cases := An4.Arrays['cases'];
  ran := 0;
  for c := 0 to cases.Count - 1 do
  begin
    if cases.Objects[c].Strings['kind'] <> 'pointer' then Continue;
    RunPointerCase(cases.Objects[c]);
    Inc(ran);
  end;
  AssertTrue(Format('%d mismatches over %d pointer samples:%s', [FBad, FCompared, FReport]),
    FBad = 0);
  AssertTrue(Format('only %d cases ran', [ran]), ran >= 9);
  AssertTrue(Format('only %d pointer samples', [FCompared]), FCompared >= 90);
end;

{ ==================== by hand ==================== }

{ interpolateRawValues on a number: from `source || 0`, rounded to the
  larger getPrecision of the two -- or the precision given; toFixed's
  half away from zero; a precision that is not a number leaves the value
  as it is. }
procedure TAdvChartAnimLabelsTest.TestInterpolatedValuePrecision;
begin
  AssertEquals('auto: 0 to 1.5 at 0.25 is 0.375, one decimal', 0.4,
    TyAnimInterpolateValue(NaN, 1.5, 0.25, False, 0), 0);
  AssertEquals('auto: the larger of the two precisions (3.125)', 0.391,
    TyAnimInterpolateValue(0, 3.125, 0.125, False, 0), 0);
  AssertEquals('auto: whole numbers stay whole', 4,
    TyAnimInterpolateValue(0, 60, 0.0625, False, 0), 0);
  AssertEquals('auto: half way to an odd whole rounds up', 118,
    TyAnimInterpolateValue(101, 134, 0.5, False, 0), 0);
  AssertEquals('given precision 1 over whole numbers', 12.3,
    TyAnimInterpolateValue(0, 12.34, 1, True, 1), 0);
  AssertEquals('given precision 0 over decimals', 2,
    TyAnimInterpolateValue(0, 2.25, 0.75, True, 0), 0);
  AssertEquals('from not a number is from nought', 5,
    TyAnimInterpolateValue(NaN, 10, 0.5, False, 0), 0);
  AssertEquals('a precision that is not a number does not round', 1 / 3,
    TyAnimInterpolateValue(0, 1, 1 / 3, True, NaN), 0);
  AssertTrue('the from value of a count in flight is its own precision',
    SameBits(TyAnimInterpolateValue(10.5, 20, 0, False, 0), 10.5));
end;

{ _endLabelOnDuring: before the clip reaches the first point, the first
  point; between two, getPointOn and the values between them at t; across a
  gap with connectNulls off, the point before it; past the last, the last --
  once a range was found, or at percent 1. }
procedure TAdvChartAnimLabelsTest.TestEndLabelStepChoices;
var
  pts: TTyDoubleArray;
  cmds: TTyPathCmdArray;
  st: TTyEndLabelStep;
  lfi: Integer;
  p: TTyPointFArray;
  i: Integer;
begin
  pts := TTyDoubleArray.Create(10, 100, 20, 80, 30, 60, 40, 40);
  SetLength(p, 4);
  for i := 0 to 3 do p[i] := TyPointF(pts[i * 2], pts[i * 2 + 1]);
  cmds := TyPolylinePath(p, 0, '', False);
  lfi := 0;
  st := TyEndLabelStep(pts, cmds, 5, True, False, False, lfi);
  AssertTrue('before the first point: a point', st.HasPoint);
  AssertEquals('the first one, x', 10, st.X, 0);
  AssertEquals('its value row', 0, st.Row0);
  AssertFalse('no interpolation', st.Interp);
  st := TyEndLabelStep(pts, cmds, 25, True, False, False, lfi);
  AssertTrue('between 20 and 30', st.Interp);
  AssertEquals('from row 1', 1, st.Row0);
  AssertEquals('to row 2', 2, st.Row1);
  AssertEquals('half way', 0.5, st.T, 0);
  AssertEquals('on the line, x', 25, st.X, 0);
  AssertEquals('on the line, y', 70, st.Y, 0);
  AssertEquals('the record keeps the row', 1, lfi);
  st := TyEndLabelStep(pts, cmds, 99, True, False, False, lfi);
  AssertEquals('past the last, the last', 3, st.Row0);
  AssertEquals('its x', 40, st.X, 0);
  lfi := 0;
  st := TyEndLabelStep(pts, cmds, 99, True, False, False, lfi);
  AssertEquals('never inside: still the first', 0, st.Row0);
  st := TyEndLabelStep(pts, cmds, 99, True, False, True, lfi);
  AssertEquals('at percent 1: the last', 3, st.Row0);
  { a gap at row 1, connectNulls off }
  pts := TTyDoubleArray.Create(10, 100, NaN, NaN, 30, 60, 40, 40);
  lfi := 0;
  st := TyEndLabelStep(pts, cmds, 25, True, False, False, lfi);
  AssertFalse('across a gap: no interpolation', st.Interp);
  AssertEquals('the point before the gap', 0, st.Row0);
  AssertEquals('its x', 10, st.X, 0);
  AssertEquals('getLastIndexNotNull', 3, TyLastLegalRow(pts));
  AssertEquals('none legal', -1, TyLastLegalRow(TTyDoubleArray.Create(NaN, 1)));
end;

{ THE END LABEL IN THE FRAME: while the clip runs the label stands where the
  clip's during put it, saying what it counted; at rest, the static one. }
procedure TAdvChartAnimLabelsTest.TestEndLabelRidesTheClipInTheFrame;
var
  lst, frm: TTyPaintList;
  i: Integer;
  p: TTyChartAnimProxy;
  found: Boolean;
begin
  NewChart(camAlways);
  Load('{"xAxis":{"type":"category","data":["A","B","C","D","E","F"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"line","showSymbol":false,"endLabel":{"show":true},'
    + '"data":[120,132,101,134,90,230]}]}');
  FChart.AnimTick(T0 + 500);
  p := FChart.AnimFindProxy(0, -1, 'lineClip');
  AssertNotNull('the clip', p);
  AssertTrue('it drives the end label', p.EndLabel.Active);
  AssertEquals('half way it reads 118', '118', p.EndLabel.Text);
  lst := FChart.List;
  frm := FChart.Frame;
  found := False;
  for i := 0 to lst.Count - 1 do
    if lst.Element(i).Anim.Role = carEndLabel then
    begin
      found := True;
      AssertEquals('the list says the last value', '230', lst.Element(i).Caption.Text);
      AssertEquals('the frame says the counted one', '118', frm.Element(i).Caption.Text);
      AssertEquals('the frame stands where the clip put it, x', p.EndLabel.X,
        frm.Element(i).Caption.X, 0);
      AssertEquals('and y', p.EndLabel.Y, frm.Element(i).Caption.Y, 0);
      AssertTrue('away from its rest', frm.Element(i).Caption.X < lst.Element(i).Caption.X - 50);
      AssertTrue('an end label is no host the expansion takes',
        lst.Element(i).Datum.SeriesIndex < 0);
    end;
  AssertTrue('an end label element', found);
  FChart.AnimTick(T0 + 1500);
  AssertEquals('at rest: no clip', 0, FChart.AnimClipCount);
  frm := FChart.Frame;
  lst := FChart.List;
  for i := 0 to lst.Count - 1 do
    if lst.Element(i).Anim.Role = carEndLabel then
    begin
      AssertEquals('at rest the frame is the list', lst.Element(i).Caption.X,
        frm.Element(i).Caption.X, 0);
      AssertEquals('and says the same', lst.Element(i).Caption.Text, frm.Element(i).Caption.Text);
    end;
end;

{ animateLabelValue: `prevValue === value` starts nothing. A bar whose value
  stays has no count running; the one that changed counts at update timing. }
procedure TAdvChartAnimLabelsTest.TestACountSkipsAnUnchangedValue;
var p0, p1: TTyChartAnimProxy;
begin
  NewChart(camAlways);
  Load('{"xAxis":{"type":"category","data":["A","B"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","label":{"show":true,"valueAnimation":true},"data":[10,20]}]}');
  FChart.AnimTick(T0 + 5000);
  FChart.AnimNow := T1;
  FChart.Option := '{"xAxis":{"type":"category","data":["A","B"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","label":{"show":true,"valueAnimation":true},"data":[10,40]}]}';
  Draw;
  p0 := FChart.AnimFindProxy(0, 0, 'label');
  p1 := FChart.AnimFindProxy(0, 1, 'label');
  AssertNotNull('the labels are carried', p0);
  AssertNotNull('both', p1);
  AssertEquals('the same value: no count', 0, p0.AnimatorCount);
  AssertEquals('the new value counts', 1, p1.AnimatorCount);
  AssertEquals('from the old value, at t = 0', '20', p1.Text);
  FChart.AnimTick(T1 + 250);
  AssertEquals('half the update time: cubicInOut(0.5) = 0.5', '30', p1.Text);
end;

{ THE RIPPLES LOOP AND KEEP THEIR PHASE: a period later each ripple is where
  it was, the twelve clips never end, and the third ripple of a symbol is
  two thirds of a period ahead of the first. }
procedure TAdvChartAnimLabelsTest.TestRippleLoopKeepsItsPhase;
var
  r0, r2: TTyChartAnimProxy;
  a, b: Double;
  k: Integer;
begin
  NewChart(camAlways);
  Load('{"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"effectScatter","symbolSize":10,"data":[[1,2],[3,4]]}]}');
  FChart.AnimTick(T0 + 700);
  r0 := FChart.AnimFindProxy(0, 0, 'ripple0');
  r2 := FChart.AnimFindProxy(0, 0, 'ripple2');
  AssertNotNull('ripple 0', r0);
  AssertNotNull('ripple 2', r2);
  a := r0.Num('scaleX');
  AssertEquals('ripple 0 at 700 ms of 4000: 0.5 + 0.75 * 0.175', 0.63125, a, 1e-12);
  { the start is the epoch plus a fractional delay, rounded at the epoch's
    ulp (2^-12 ms near 1.7e12) -- upstream's own 0.7499999847... }
  AssertEquals('ripple 2 started two thirds early', 0.5 + 0.75 * (0.175 + 2 / 3),
    r2.Num('scaleX'), 1e-7);
  { frames every 100 ms: a frame that passes the period's end writes the
    final keyframe and restarts at now - elapsed mod life (upstream's
    Clip.step) -- the phase is kept, the frame that restarts shows the end }
  for k := 1 to 120 do FChart.AnimTick(T0 + 700 + k * 100);
  b := r0.Num('scaleX');
  AssertEquals('three periods on, where it was', a, b, 1e-9);
  { one frame after a long gap: the end, then the phase again }
  FChart.AnimTick(T0 + 700 + 12000 + 9000);
  AssertEquals('a frame across a gap writes the end', 1.25, r0.Num('scaleX'), 0);
  FChart.AnimTick(T0 + 700 + 12000 + 9000 + 100);
  { 21800 ms from its start: 1800 into a period }
  AssertEquals('and runs on in phase', 0.5 + 0.75 * (1800 / 4000),
    r0.Num('scaleX'), 1e-9);
  AssertEquals('twelve clips loop on', 12, FChart.AnimLoopClipCount);
  AssertEquals('and nothing else', 12, FChart.AnimClipCount);
  AssertTrue('still live', FChart.AnimLive);
end;

{ ONCE ONLY LOOPS ARE LEFT the static layer takes everything but the ripples
  and their symbols: the frame's two parts split there, and a ripple is
  never in the static part. }
procedure TAdvChartAnimLabelsTest.TestOnlyLoopsLeftSplitTheLayers;
var
  frm: TTyPaintList;
  i, ripples: Integer;
begin
  NewChart(camAlways);
  Load('{"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"effectScatter","symbolSize":10,"data":[[1,2],[3,4]]},'
    + '{"type":"line","data":[[0,1],[4,3]]}]}');
  AssertFalse('entering: not only loops', FChart.AnimContinuous);
  FChart.AnimTick(T0 + 2000);
  AssertTrue('the enter is over, the ripples loop on', FChart.AnimContinuous);
  AssertTrue('live', FChart.AnimLive);
  frm := FChart.Frame;
  ripples := 0;
  for i := 0 to frm.Count - 1 do
    if frm.Element(i).Anim.Role = carRipple then Inc(ripples);
  AssertEquals('three ripples a symbol', 6, ripples);
  Draw;
  { off: nothing loops }
  FChart.AnimationMode := camOff;
  AssertFalse('off: not live', FChart.AnimLive);
  AssertFalse('off: no loops', FChart.AnimContinuous);
  AssertEquals('off: no clip', 0, FChart.AnimClipCount);
end;

{ ONLY A BAR COUNTS (BarView's setLabelValueAnimation): a scatter's labels
  fade in whatever label.valueAnimation says. }
procedure TAdvChartAnimLabelsTest.TestOtherSeriesLabelsFadeWhateverValueAnimationSays;
var p: TTyChartAnimProxy;
begin
  NewChart(camAlways);
  Load('{"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"scatter","label":{"show":true,"valueAnimation":true},'
    + '"data":[[1,2],[3,4]]}]}');
  p := FChart.AnimFindProxy(0, 0, 'label');
  AssertNotNull('the label fades', p);
  AssertEquals('from nought', 0, p.Num('style.opacity'), 0);
  AssertFalse('no words counted', p.HasText);
end;

{ A HIDDEN POINTER KEEPS ITS PLACE (BaseAxisPointer hides its group): the
  next show slides from where it was, not from nowhere. }
procedure TAdvChartAnimLabelsTest.TestThePointerSlidesFromWhereItWasHidden;
var p: TTyChartAnimProxy;
begin
  NewChart(camAlways);
  Load('{"tooltip":{"trigger":"axis"},"xAxis":{"type":"category","data":["A","B","C","D","E"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","emphasis":{"disabled":true},'
    + '"data":[5,20,36,10,-8]}]}');
  FChart.AnimTick(T0 + 5000);
  FChart.Hover(150, 150);
  p := FChart.AnimPointerProxy('xAxis0');
  AssertNotNull('shown', p);
  AssertEquals('the first show is direct', 0, FChart.AnimPointerClipCount);
  AssertEquals('at B', 150, p.Num('shape.x1'), 0);
  FChart.Leave;
  FChart.AnimNow := T0 + 6000;
  FChart.Hover(270, 150);
  AssertEquals('shown again: it slides', 1, FChart.AnimPointerClipCount);
  FChart.AnimTick(T0 + 6001);
  AssertEquals('from B', 150, p.Num('shape.x1'), 0);
  FChart.AnimTick(T0 + 6300);
  AssertEquals('to D', 270, p.Num('shape.x1'), 0);
  AssertEquals('done', 0, FChart.AnimPointerClipCount);
  AssertFalse('the series never left the static layer', FChart.AnimLive);
end;

{ camOff: the pointer jumps -- no proxy, drawn where the hover is. }
procedure TAdvChartAnimLabelsTest.TestPointerOffModeJumps;
begin
  NewChart(camOff);
  Load('{"tooltip":{"trigger":"axis"},"xAxis":{"type":"category","data":["A","B","C","D","E"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[5,20,36,10,-8]}]}');
  FChart.Hover(150, 150);
  FChart.Hover(270, 150);
  AssertNull('no proxy', FChart.AnimPointerProxy('xAxis0'));
  AssertEquals('no clip', 0, FChart.AnimPointerClipCount);
end;

initialization
  RegisterTest(TAdvChartAnimLabelsTest);
finalization
  FreeAndNil(GAn4);
end.
