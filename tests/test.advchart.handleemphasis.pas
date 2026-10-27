unit test.advchart.handleemphasis;
{$mode objfpc}{$H+}
{ THE HOVER STATES OF A SLIDER'S HANDLES AND OF A visualMap'S THUMBS, HELD
  TO UPSTREAM [R5-D].

  tools/advchart-oracle/handle-emphasis.js runs the real ECharts 6.1 build in
  node: a slider dataZoom with handleStyle / moveHandleStyle and their
  emphasis states written (and one with none), a calculable continuous
  visualMap with emphasis.handleStyle; the pointer over a handle, off it,
  over the move handle, off it. Per step it records each handle's (thumb's)
  states, fill, stroke, line width and opacity, its global centre, and the
  move handle's states, fill and opacity.

  This replays the hovers through TTyAdvanceChart and reads the elements the
  paint list holds at each handle's centre: a handle is the topmost filled
  and stroked element there, the move handle the topmost filled one at its
  centre. A colour is compared with the opacity applied to it (the port
  folds an element's opacity into its inks). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart;
type
  THeProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Hover(AX, AY: Integer);
    { the topmost element at (AX, AY) with a fill (and a stroke when
      AStroked), outside the series }
    function TopAt(AX, AY: Double; AStroked, ARect: Boolean; out AEl: TTyChartElement): Boolean;
  end;

  TAdvChartHandleEmphasisOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure SameInk(const AWhat: string; AGot: TTyChartColor; AWant: TJSONData; AOpacity: Double);
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestWrittenSliderStatesAsUpstream;
    procedure TestDefaultSliderStatesAsUpstream;
    procedure TestAVisualMapThumbAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function WithOpacity(AColour: TTyChartColor; AOpacity: Double): TTyChartColor;
begin
  if AOpacity >= 1 then Exit(AColour);
  if AOpacity <= 0 then Exit(AColour and $00FFFFFF);
  Result := (AColour and $00FFFFFF)
    or (Cardinal(Round((AColour shr 24) * AOpacity)) shl 24);
end;

procedure THeProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure THeProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function THeProbe.TopAt(AX, AY: Double; AStroked, ARect: Boolean; out AEl: TTyChartElement): Boolean;
var
  i: Integer;
  el: TTyChartElement;
  b: TTyRectF;
  bestZ, bestZ2: Integer;
  area, bestArea: Double;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  bestZ := Low(Integer);
  bestZ2 := Low(Integer);
  bestArea := 0;
  if SeriesList = nil then Exit;
  for i := 0 to SeriesList.Count - 1 do
  begin
    el := SeriesList.Element(i);
    if el.Datum.SeriesIndex >= 0 then Continue;
    if not el.Style.HasFill then Continue;
    if AStroked and (el.Style.StrokeWidthLogical <= 0) then Continue;
    b := TyShapeBounds(el.Shape);
    if not TyRectFIsValid(b) then Continue;
    if (AX < b.Left) or (AX > b.Right) or (AY < b.Top) or (AY > b.Bottom) then Continue;
    { a visualMap's hover indicator is a circle over the thumb }
    if AStroked and (el.Shape.Kind = cskCircle) then Continue;
    { the move handle: the widest thing there (its icon over it is small) }
    if ARect then
    begin
      area := (b.Right - b.Left) * (b.Bottom - b.Top);
      if (not Result) or (area > bestArea) then
      begin
        bestArea := area;
        AEl := el;
        Result := True;
      end;
      Continue;
    end;
    if (el.Z > bestZ) or ((el.Z = bestZ) and (el.Z2 >= bestZ2)) then
    begin
      bestZ := el.Z;
      bestZ2 := el.Z2;
      AEl := el;
      Result := True;
    end;
  end;
end;

procedure TAdvChartHandleEmphasisOracleTest.SetUp;
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
    sl.LoadFromFile(FixturePath('advchart-handle-emphasis.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartHandleEmphasisOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartHandleEmphasisOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

{ an upstream colour the author wrote (or one derived from it): compared;
  a theme token (the port's skin) is not }
procedure TAdvChartHandleEmphasisOracleTest.SameInk(const AWhat: string;
  AGot: TTyChartColor; AWant: TJSONData; AOpacity: Double);
var c: TTyChartColor;
begin
  if (AWant = nil) or (AWant.JSONType <> jtString) then Exit;
  if not TyTryParseChartColor(AWant.AsString, c) then Exit;
  c := WithOpacity(c, AOpacity);
  Inc(FCompared);
  if c <> AGot then
    Bad(Format('%s %.8x, upstream %.8x (%s at %g)', [AWhat, AGot, c, AWant.AsString, AOpacity]));
end;

procedure TAdvChartHandleEmphasisOracleTest.RunCase(const AId: string);
const
  { the colours the oracle's options wrote; a handle ink not among them (or
    lifted from them) is a theme token }
  cAuthor: array[0..7] of string = ('#00ff00', '#0000ff', '#00ffff', '#ff0000',
    '#ffff00', '#ff00ff', 'rgba(0,255,0,1)', 'xx');
var
  cases, steps, hs: TJSONArray;
  cs, st, rec, h, mv: TJSONObject;
  probe: THeProbe;
  i, j, k: Integer;
  el: TTyChartElement;
  op: Double;
  authored: Boolean;
  want: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  probe := THeProbe.Create(FForm);
  try
    probe.Parent := FForm;
    probe.Controller := FCtl;
    probe.AnimationMode := camOff;
    probe.SetBounds(0, 0, cW, cH);
    probe.Option := cs.Objects['option'].AsJSON;
    probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    steps := cs.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      FWhere := Format('%s step %d (%s)', [AId, j, st.Strings['op']]);
      if st.Find('at').JSONType = jtArray then
        probe.Hover(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1]);
      probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      rec := st.Objects['record'];
      hs := rec.Arrays['handles'];
      for k := 0 to hs.Count - 1 do
      begin
        h := hs.Objects[k];
        Inc(FCompared);
        if not probe.TopAt(h.Arrays['centre'].Integers[0], h.Arrays['centre'].Integers[1],
          True, False, el) then
        begin
          Bad(Format('handle %d: nothing at its centre', [k]));
          Continue;
        end;
        op := 1;
        if h.Find('opacity').JSONType = jtNumber then op := h.Floats['opacity'];
        authored := False;
        want := h.Strings['fill'];
        for i := 0 to High(cAuthor) do if want = cAuthor[i] then authored := True;
        if authored then SameInk(Format('handle %d fill', [k]), el.Style.FillColor, h.Find('fill'), op);
        authored := False;
        want := h.Strings['stroke'];
        for i := 0 to High(cAuthor) do if want = cAuthor[i] then authored := True;
        if authored then SameInk(Format('handle %d stroke', [k]), el.Style.StrokeColor, h.Find('stroke'), op);
        Inc(FCompared);
        if el.Style.StrokeWidthLogical <> h.Floats['lineWidth'] then
          Bad(Format('handle %d width %g, upstream %g', [k, el.Style.StrokeWidthLogical,
            h.Floats['lineWidth']]));
      end;
      if rec.Find('move').JSONType = jtObject then
      begin
        mv := rec.Objects['move'];
        Inc(FCompared);
        if not probe.TopAt(mv.Arrays['centre'].Integers[0], mv.Arrays['centre'].Integers[1],
          False, True, el) then
          Bad('the move handle: nothing at its centre')
        else
          SameInk('the move handle', el.Style.FillColor, mv.Find('fill'), mv.Floats['opacity']);
      end;
    end;
  finally
    probe.Free;
  end;
  AssertTrue(AId + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AId, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartHandleEmphasisOracleTest.TestWrittenSliderStatesAsUpstream;
begin
  RunCase('dz-written');
end;

procedure TAdvChartHandleEmphasisOracleTest.TestDefaultSliderStatesAsUpstream;
begin
  RunCase('dz-default');
end;

procedure TAdvChartHandleEmphasisOracleTest.TestAVisualMapThumbAsUpstream;
begin
  RunCase('vm-written');
end;

initialization
  RegisterTest(TAdvChartHandleEmphasisOracleTest);
end.
