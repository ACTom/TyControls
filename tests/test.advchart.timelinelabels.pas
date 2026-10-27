unit test.advchart.timelinelabels;
{$mode objfpc}{$H+}
{ A timeline's tick labels beyond timeline.js, held to ECharts 6.1 [R5-C]:
  a named formatter (the port's '@Name' for a function: the category name
  or the value, and the index), `rich` text, `overflow` at a width.

  tools/advchart-oracle/timeline-labels.js records the label group's texts
  after a render: the text, the lines (tokens) drawn, the rect through the
  transform. The control renders the same option (zrender's SSR width table
  measures the words); each label of the view is compared. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Handlers, tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart.GfxEl, tyControls.AdvanceChart.RichText,
     tyControls.AdvanceChart.Timeline, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TTllProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TTllHandlers = class
  public
    function Fmt(const AParams: TTyChartParams): string;
  end;

  TAdvChartTimelineLabelsTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTllProbe;
    FH: TTllHandlers;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FLabels: Integer;
    FName, FReport: string;
    procedure Miss(const AWhat: string);
    procedure Near(const AWhat: string; AGot, AWant: Double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLabelsAsUpstream;
  end;

implementation

function TTllProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TTllProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

{ timeline-labels.js' @TL_FMT: '#' + index + ' ' + value }
function TTllHandlers.Fmt(const AParams: TTyChartParams): string;
var v: string;
begin
  Result := '';
  if Length(AParams) = 0 then Exit;
  v := AParams[0].ValueText;
  Result := '#' + IntToStr(AParams[0].DataIndex) + ' ' + v;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

procedure TAdvChartTimelineLabelsTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 100 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartTimelineLabelsTest.Near(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not (Abs(AGot - AWant) <= 1e-9) then
    Miss(Format('%s: %.17g upstream, %.17g here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartTimelineLabelsTest.TestTheLabelsAsUpstream;
var
  cs, labs: TJSONArray;
  c, i, k, n: Integer;
  cse, lb: TJSONObject;
  v: TTyTimelineView;
  idx: array of Integer;
  el: TTyGfxEl;
  lay: TTyRtResult;
  r: TTyXYWH;
  got, want: string;
  x0, y0, x1, y1, px, py: Double;
  q: Integer;
begin
  cs := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cs.Count - 1 do
  begin
    cse := cs.Objects[c];
    FChart.Option := '{}';
    FChart.Option := cse.Objects['option'].AsJSON;
    FChart.SetBounds(0, 0, cse.Integers['W'], cse.Integers['H']);
    FBmp.SetSize(cse.Integers['W'], cse.Integers['H']);
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cse.Integers['W'], cse.Integers['H']), 96);
    v := FChart.TimelineView;
    FName := cse.Strings['id'];
    AssertNotNull(FName + ': a view', v);
    v.UpdateTransforms;
    idx := nil;
    for i := 0 to High(v.Els) do
      if v.RoleOf(i).Kind = tlrLabel then
      begin
        n := Length(idx);
        SetLength(idx, n + 1);
        idx[n] := i;
      end;
    labs := cse.Arrays['labels'];
    Inc(FCompared);
    if Length(idx) <> labs.Count then
    begin
      Miss(Format('%d labels upstream, %d here', [labs.Count, Length(idx)]));
      Continue;
    end;
    for i := 0 to labs.Count - 1 do
    begin
      lb := labs.Objects[i];
      el := v.Els[idx[i]];
      FName := Format('%s label %d', [cse.Strings['id'], i]);
      Inc(FLabels);
      Inc(FCompared);
      if el.Style.Get('text', '') <> lb.Strings['text'] then
        Miss('text ' + lb.Strings['text'] + ' upstream, ' + el.Style.Get('text', '') + ' here');
      lay := TyGfxTextLayout(el, FChart.Measurer);
      got := '';
      for k := 0 to High(lay.Pieces) do
        if lay.Pieces[k].Kind = rpkText then got := got + '|' + lay.Pieces[k].Text;
      want := '';
      for k := 0 to lb.Arrays['texts'].Count - 1 do want := want + '|' + lb.Arrays['texts'].Strings[k];
      Inc(FCompared);
      if got <> want then Miss('texts ' + want + ' upstream, ' + got + ' here');
      { the rect through the transform: the corners' box (nothing turns
        here) }
      r := TyGfxRect(el, FChart.Measurer);
      x0 := r.X;
      y0 := r.Y;
      x1 := r.X + r.W;
      y1 := r.Y + r.H;
      if el.HasTransform then
      begin
        for q := 0 to 1 do
        begin
          if q = 0 then begin px := r.X; py := r.Y; end
          else begin px := r.X + r.W; py := r.Y + r.H; end;
          if q = 0 then
          begin
            x0 := el.Transform[0] * px + el.Transform[2] * py + el.Transform[4];
            y0 := el.Transform[1] * px + el.Transform[3] * py + el.Transform[5];
          end
          else
          begin
            x1 := el.Transform[0] * px + el.Transform[2] * py + el.Transform[4];
            y1 := el.Transform[1] * px + el.Transform[3] * py + el.Transform[5];
          end;
        end;
      end;
      Near('left', Min(x0, x1), FromHex(lb.Arrays['rect'].Strings[0]));
      Near('top', Min(y0, y1), FromHex(lb.Arrays['rect'].Strings[1]));
      Near('width', Abs(x1 - x0), FromHex(lb.Arrays['rect'].Strings[2]));
      Near('height', Abs(y1 - y0), FromHex(lb.Arrays['rect'].Strings[3]));
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('labels compared (%d)', [FLabels]), FLabels >= 18);
end;

procedure TAdvChartTimelineLabelsTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TTllProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FH := TTllHandlers.Create;
  TyChartRegisterFormatter('TL_FMT', @FH.Fmt);
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-timeline-labels.json');
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FLabels := 0;
  FReport := '';
end;

procedure TAdvChartTimelineLabelsTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FH);
  inherited TearDown;
end;

initialization
  RegisterTest(TAdvChartTimelineLabelsTest);
end.
