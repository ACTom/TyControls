unit test.advchart.effecthover;
{$mode objfpc}{$H+}
{ An effectScatter whose showEffectOn is not 'render' ripples only while its
  symbol is emphasised, held to ECharts 6.1 [R5-C].

  tools/advchart-oracle/effect-hover.js runs the real dist on a controlled
  clock: the chart settles, then at T1 a highlight, frames, a downplay, a
  highlight again, a second symbol highlighted and downplayed; after every
  frame each ripple path (its symbol's data index, its number, scaleX,
  scaleY, opacity). The control replays the same actions and frames
  (camAlways, the clock injected) and each ripple's proxy is compared bit
  for bit -- and a ripple upstream has not must have no proxy and draw
  nothing. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart.AnimView, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TEhProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TAdvChartEffectHoverTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TEhProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FShown: Integer;
    FName, FReport: string;
    procedure Miss(const AWhat: string);
    procedure Draw;
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHoverRipplesAsUpstream;
    procedure TestNoRippleAtRest;
  end;

implementation

const
  cW = 400;
  cH = 300;
  T0 = 1700000000000.0;

function TEhProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TEhProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TEhProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TEhProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

procedure TAdvChartEffectHoverTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 80 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartEffectHoverTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartEffectHoverTest.RunCase(ACase: TJSONObject);
var
  steps, rips: TJSONArray;
  st, rp, act: TJSONObject;
  s, k, d, i, n: Integer;
  t1: Double;
  p: TTyChartAnimProxy;
  frm: TTyPaintList;
  want: array of array of Boolean;

  procedure Num(const AWhat: string; AGot: Double; const AHex: string);
  begin
    Inc(FCompared);
    if Bits(AGot) <> Bits(FromHex(AHex)) then
      Miss(Format('%s: %.17g upstream, %.17g here', [AWhat, FromHex(AHex), AGot]));
  end;

begin
  FreeAndNil(FChart);
  FChart := TEhProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := T0;
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, cW, cH);
  Draw;
  { settled as upstream's harness settles it }
  k := 16;
  while k <= 5000 do
  begin
    FChart.AnimTick(T0 + k);
    Inc(k, 250);
  end;
  Draw;
  t1 := T0 + TJSONObject(FRoot).Integers['T1'];
  steps := ACase.Arrays['steps'];
  for s := 0 to steps.Count - 1 do
  begin
    st := steps.Objects[s];
    FChart.AnimNow := t1 + st.Integers['at'];
    if (st.Find('action') <> nil) and (st.Find('action').JSONType = jtObject) then
    begin
      act := st.Objects['action'];
      AssertTrue('dispatch', FChart.DispatchAction(act.AsJSON));
      Draw;
    end;
    FChart.AnimTick(t1 + st.Integers['at']);
    rips := st.Arrays['ripples'];
    SetLength(want, 3, 4);
    for d := 0 to 2 do for i := 0 to 3 do want[d][i] := False;
    for k := 0 to rips.Count - 1 do
    begin
      rp := rips.Objects[k];
      d := rp.Integers['d'];
      i := rp.Integers['i'];
      want[d][i] := True;
      FName := Format('%s at %d, symbol %d ripple %d', [ACase.Strings['id'], st.Integers['at'], d, i]);
      p := FChart.AnimFindProxy(0, d, 'ripple' + IntToStr(i));
      Inc(FCompared);
      if p = nil then
      begin
        Miss('a ripple upstream, no proxy here');
        Continue;
      end;
      Num('scaleX', p.Num('scaleX'), rp.Strings['scaleX']);
      Num('scaleY', p.Num('scaleY'), rp.Strings['scaleY']);
      Num('opacity', p.Num('style.opacity'), rp.Strings['opacity']);
    end;
    { none where upstream has none, and only those drawn }
    for d := 0 to 2 do
      for i := 0 to 3 do
        if not want[d][i] then
        begin
          FName := Format('%s at %d, symbol %d ripple %d', [ACase.Strings['id'], st.Integers['at'], d, i]);
          Inc(FCompared);
          if FChart.AnimFindProxy(0, d, 'ripple' + IntToStr(i)) <> nil then
            Miss('no ripple upstream, a proxy here');
        end;
    Draw;
    frm := FChart.Frame;
    n := 0;
    if frm <> nil then
      for k := 0 to frm.Count - 1 do
        if (frm.Element(k).Anim.Role = carRipple) and not frm.Element(k).Ignore then Inc(n);
    FName := Format('%s at %d', [ACase.Strings['id'], st.Integers['at']]);
    Inc(FCompared);
    if n <> rips.Count then
      Miss(Format('%d ripples drawn upstream, %d here', [rips.Count, n]));
    Inc(FShown, n);
  end;
end;

procedure TAdvChartEffectHoverTest.TestHoverRipplesAsUpstream;
var
  cs: TJSONArray;
  c: Integer;
begin
  cs := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cs.Count - 1 do RunCase(cs.Objects[c]);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough compared (%d)', [FCompared]), FCompared > 600);
  AssertTrue(Format('ripples drawn (%d)', [FShown]), FShown > 100);
end;

{ AT REST NOTHING LOOPS: a hover chart's settled clips are none, its
  ripples are built and hidden }
procedure TAdvChartEffectHoverTest.TestNoRippleAtRest;
var
  k, n: Integer;
begin
  FChart := TEhProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := T0;
  FChart.Option := '{"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"effectScatter","showEffectOn":"emphasis","symbolSize":10,'
    + '"data":[[1,2],[3,4]]}]}';
  FChart.SetBounds(0, 0, cW, cH);
  Draw;
  FChart.AnimTick(T0 + 3000);
  Draw;
  AssertEquals('no loop at rest', 0, FChart.AnimLoopClipCount);
  n := 0;
  for k := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(k).Anim.Role = carRipple then
    begin
      Inc(n);
      AssertTrue('a hover ripple is hidden at rest', FChart.List.Element(k).Ignore);
    end;
  AssertEquals('three ripples a symbol, built', 6, n);
end;

procedure TAdvChartEffectHoverTest.SetUp;
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
      + 'advchart-effect-hover.json');
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FShown := 0;
  FReport := '';
end;

procedure TAdvChartEffectHoverTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

initialization
  RegisterTest(TAdvChartEffectHoverTest);
end.
