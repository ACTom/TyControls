unit test.advchart.hitstroke;
{$mode objfpc}{$H+}
{ WHAT THE POINTER FINDS AROUND A STROKED ELEMENT, held to upstream. [R7-C]

  tests/fixtures/advchart-hit-stroke.json, from the real ECharts 6.1 build
  (tools/advchart-oracle/hit-stroke.js): per case, rays from each aim's
  centre in eight directions, a pixel a step, and at every step what
  zrender's findHover finds -- Path.contain: the stroked bounding rect, the
  stroke within half its width of the outline (at least
  strokeContainThreshold, 5, where there is no fill), the fill -- as the
  series and data index of the target's ECData (sS/D, sS/eD an edge, sS/-
  none), x a target with none, - nothing; run-length encoded.

  TestTheRaysAsUpstream: the same off the series list's HitTestElement
  without the port's pad, the element's own datum (a run element, a line's
  polyline, is sS/-; a tree's edge, which names none, x). A case with `tol`
  -- a curve the port holds as points: a graph's or a lines' curved edge
  sampled into a polyline, the pin symbol's outline -- has the same runs in
  the same order, each ending no more than tol steps off upstream's. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  THitStrokeProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TAdvChartHitStrokeTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FChart: THitStrokeProbe;
    function CodeAt(AX, AY: Double): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRaysAsUpstream;
  end;

implementation

const
  cW = 400;
  cH = 300;

function THitStrokeProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure THitStrokeProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function LoadJson(const AName: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartHitStrokeTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FMeasure := LoadJson('advchart-text-style.json');
end;

procedure TAdvChartHitStrokeTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

function TAdvChartHitStrokeTest.CodeAt(AX, AY: Double): string;
var
  el: Integer;
  d: TTyChartDatumRef;
  L: TTyPaintList;
begin
  { the list's own test without the port's pad (a symbol's target grown for
    a mouse), as upstream answers; a combining host's child is its host, a
    tree's edge names no datum (HitTestAt) }
  L := FChart.SeriesList;
  el := L.HitTestElement(AX, AY, 96, False);
  if el < 0 then Exit('-');
  if L.Element(el).Anim.PieceOf > 0 then el := L.Element(el).Anim.PieceOf - 1;
  if L.Element(el).Anim.Role = carTreeEdge then Exit('x');
  d := L.Element(el).Datum;
  if (d.Kind <> ctkSeries) or (d.SeriesIndex < 0) then Exit('x');
  Result := 's' + IntToStr(d.SeriesIndex) + '/';
  if d.DataIndex < 0 then Result := Result + '-'
  else if d.IsEdge then Result := Result + 'e' + IntToStr(d.DataIndex)
  else Result := Result + IntToStr(d.DataIndex);
end;

function PointsText(const APts: TTyPointFArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to Min(High(APts), 5) do Result := Result + Format(' (%g,%g)', [APts[i].X, APts[i].Y]);
end;

{ the same runs in the same order, every run's end within ATol steps }
function RunsAlike(const AWant, AHave: string; ATol: Integer): Boolean;
var
  w, h: TStringList;
  i, p, ew, eh: Integer;
begin
  w := TStringList.Create;
  h := TStringList.Create;
  try
    w.Delimiter := ' ';
    w.StrictDelimiter := True;
    w.DelimitedText := AWant;
    h.Delimiter := ' ';
    h.StrictDelimiter := True;
    h.DelimitedText := AHave;
    Result := w.Count = h.Count;
    ew := 0;
    eh := 0;
    i := 0;
    while Result and (i < w.Count) do
    begin
      p := Pos('*', w[i]);
      Result := (p > 0) and (Copy(w[i], 1, p) = Copy(h[i], 1, p));
      if not Result then Break;
      Inc(ew, StrToInt(Copy(w[i], p + 1, MaxInt)));
      Inc(eh, StrToInt(Copy(h[i], p + 1, MaxInt)));
      Result := Abs(ew - eh) <= ATol;
      Inc(i);
    end;
  finally
    w.Free;
    h.Free;
  end;
end;

procedure TAdvChartHitStrokeTest.TestTheRaysAsUpstream;
var
  fix: TJSONData;
  cs, rays: TJSONArray;
  c, r: TJSONObject;
  i, j, k, n, dx, dy, cnt, nBad, nRays, tol, nTol: Integer;
  ox, oy: Double;
  id, code, last, seq, bad: string;
begin
  fix := LoadJson('advchart-hit-stroke.json');
  nBad := 0;
  nRays := 0;
  nTol := 0;
  bad := '';
  try
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      tol := c.Get('tol', 0);
      FreeAndNil(FChart);
      FChart := THitStrokeProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
        TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
        TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
      FChart.SetBounds(0, 0, cW, cH);
      FChart.Option := c.Objects['option'].AsJSON;
      AssertEquals(id + ' parses', '', FChart.OptionError);
      FBmp.Fill(BGRA(255, 255, 255, 255));
      FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      if GetEnvironmentVariable('TY_HS_EL') = id then
        for k := 0 to FChart.SeriesList.Count - 1 do
          with FChart.SeriesList.Element(k) do
            WriteLn(Format('%d kind %d role %d s %d d %d edge %s silent %s ign %s fill %s w %g col %x ps %g slop %g pad %g b %g,%g,%g,%g c %g,%g r %g,%g a %g,%g n %d cmds %d zr %s ph %s',
              [k, Ord(Shape.Kind), Ord(Anim.Role), Datum.SeriesIndex, Datum.DataIndex, BoolToStr(Datum.IsEdge, True),
               BoolToStr(Silent, True), BoolToStr(Ignore, True), BoolToStr(Style.HasFill, True), Style.StrokeWidthLogical,
               Style.StrokeColor, Style.PenScale, HitSlopLogical, HitPadLogical, Shape.Bounds.Left, Shape.Bounds.Top,
               Shape.Bounds.Right, Shape.Bounds.Bottom, Shape.CX, Shape.CY, Shape.R0, Shape.R1, Shape.StartRad, Shape.EndRad,
               Length(Shape.Points), Length(Shape.Cmds), BoolToStr(ZrHit.Active, True), BoolToStr(PathHit.Active, True)])
              + PointsText(Shape.Points) + Format(' fillcol %x', [Style.FillColor]));
      rays := c.Arrays['rays'];
      for j := 0 to rays.Count - 1 do
      begin
        r := rays.Objects[j];
        Inc(nRays);
        ox := r.Arrays['o'].Floats[0];
        oy := r.Arrays['o'].Floats[1];
        dx := r.Arrays['d'].Integers[0];
        dy := r.Arrays['d'].Integers[1];
        n := r.Integers['n'];
        seq := '';
        last := '';
        cnt := 0;
        for k := 0 to n - 1 do
        begin
          code := CodeAt(ox + dx * k, oy + dy * k);
          if (cnt > 0) and (code = last) then Inc(cnt)
          else
          begin
            if cnt > 0 then
            begin
              if seq <> '' then seq := seq + ' ';
              seq := seq + last + '*' + IntToStr(cnt);
            end;
            last := code;
            cnt := 1;
          end;
        end;
        if cnt > 0 then
        begin
          if seq <> '' then seq := seq + ' ';
          seq := seq + last + '*' + IntToStr(cnt);
        end;
        if (tol > 0) and (seq <> r.Strings['seq']) and RunsAlike(r.Strings['seq'], seq, tol) then
          Inc(nTol)
        else if seq <> r.Strings['seq'] then
        begin
          Inc(nBad);
          if (Length(bad) < 6000) or (GetEnvironmentVariable('TY_HS_ALL') <> '') then
            bad := bad + LineEnding + Format('%s (%g,%g) d(%d,%d): want %s have %s',
              [id, ox, oy, dx, dy, r.Strings['seq'], seq]);
        end;
      end;
    end;
  finally
    fix.Free;
  end;
  AssertEquals(IntToStr(nBad) + ' of ' + IntToStr(nRays) + ' rays differ:' + bad, 0, nBad);
  { the tolerance is the sampled curves' only: it is used, and not by much }
  AssertTrue('the sampled curves come within their tolerance on some rays', nTol > 0);
  AssertTrue('and on few: ' + IntToStr(nTol), nTol <= 12);
end;

initialization
  RegisterTest(TAdvChartHitStrokeTest);
end.
