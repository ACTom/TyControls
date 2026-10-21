program advchart_bench;
{$mode objfpc}{$H+}

{ Q7 needs one number the research never measured: what ONE frame of the
  windowed chart costs today, split into the parts a repaint model can choose
  between. The ~14.9 ms in the research is the OLD graphic TTyChart repainting
  its parent's whole client area -- a different control and a different path.

  Three costs, each timed alone:
    parse    Option := text            (fcl-json, once per edit)
    build    Rebuild + Relayout        (stores, extents, label measurement)
    paint    RenderTo with FDirty=False (frame + axes, the raster work)
  and the fourth is what an animation tick costs TODAY, because the control's
  Invalidate override marks it dirty -- so every tick is build + paint. }

uses
  Interfaces, Forms, Controls, Classes, SysUtils, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Painter, tyControls.AdvanceChart,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.DirtyRect;

type
  TChartProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { The LAYERED path -- the one Paint takes. Exposed because Paint needs a
      handle and a message loop and this bench has neither, and measuring
      RenderTo instead would measure the path the static layer bypasses. }
    procedure RenderLayered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { the pointer, as a window's mouse moves it [Batch 142] }
    procedure Hover(AX, AY: Integer);
    { what the last frame repainted: everything, or this many px }
    function RepaintArea: Double;
    { a point inside the bar of ARow, 3 px above its foot }
    function BarPoint(ARow: Integer; out AX, AY: Integer): Boolean;
  end;

procedure TChartProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TChartProbe.RenderLayered(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

procedure TChartProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TChartProbe.BarPoint(ARow: Integer; out AX, AY: Integer): Boolean;
var idx: Integer; b: TTyRectF;
begin
  AX := 0;
  AY := 0;
  idx := SeriesList.IndexOfDatum(0, ARow);
  Result := idx >= 0;
  if not Result then Exit;
  b := SeriesList.Element(idx).Shape.Bounds;
  AX := Round((b.Left + b.Right) / 2);
  AY := Round(b.Bottom) - 3;
end;

function TChartProbe.RepaintArea: Double;
var r: TTyZrRectArray; i: Integer;
begin
  if LastRepaintFull then Exit(Width * Height);
  r := LastRepaintRects;
  Result := 0;
  for i := 0 to High(r) do Result := Result + r[i].W * r[i].H;
end;

var GSameLabel: Boolean = False;

function MakeOption(APoints: Integer; AWithBars: Boolean): string;
var
  i: Integer;
  xs, ys: string;
begin
  xs := '';
  ys := '';
  for i := 0 to APoints - 1 do
  begin
    if i > 0 then begin xs := xs + ','; ys := ys + ','; end;
    if GSameLabel then
      xs := xs + '''c'''
    else
      xs := xs + '''c' + IntToStr(i) + '''';
    ys := ys + IntToStr((i * 37) mod 100 + 1);
  end;
  Result := '{ xAxis: { data: [' + xs + '] }, yAxis: {}, series: [';
  if AWithBars then
    Result := Result + '{ type: ''bar'', data: [' + ys + '] },';
  Result := Result + '{ type: ''line'', data: [' + ys + '] } ] }';
end;

var
  form: TForm;
  ctl: TTyStyleController;
  chart: TChartProbe;
  bmp: TBGRABitmap;
  W, H: Integer;

function MsPer(AIters: Integer; const AWhat: string; ARun: TProcedure): Double;
var t: QWord; i: Integer;
begin
  t := GetTickCount64;
  for i := 1 to AIters do ARun;
  Result := (GetTickCount64 - t) / AIters;
  WriteLn(Format('  %-42s %8.2f ms', [AWhat, Result]));
end;

var
  GText: string;
  GIters: Integer = 40;

procedure DoParse; begin chart.Option := ''; chart.Option := GText; end;
procedure DoPaint; begin chart.Render(bmp.Canvas, Rect(0, 0, W, H), 96); end;
procedure DoTick;  begin chart.Invalidate; chart.Render(bmp.Canvas, Rect(0, 0, W, H), 96); end;
{ A frame with the static layer standing: what an animation tick costs once
  InvalidateFrame is what a tick calls. }
procedure DoFrame; begin chart.RenderLayered(bmp.Canvas, Rect(0, 0, W, H), 96); end;

procedure Bench(const AName: string; APoints: Integer; AWithBars: Boolean;
  ANoAxes: Boolean = False);
var parse, tick, paint: Double;
begin
  WriteLn;
  WriteLn(AName, ' -- ', APoints, ' points, ', W, 'x', H);
  GText := MakeOption(APoints, AWithBars);
  if ANoAxes then
    GText := StringReplace(StringReplace(GText, 'xAxis: {', 'xAxis: { show: false,', []),
                           'yAxis: {}', 'yAxis: { show: false }', []);
  chart.Option := GText;
  DoPaint;                      { warm: first build, memoised measurements }
  parse := MsPer(10, 'parse (Option := text)', @DoParse);
  DoPaint;                      { leave it built and clean }
  paint := MsPer(GIters, 'paint only (clean, FDirty = False)', @DoPaint);
  tick  := MsPer(GIters, 'animation tick, model rebuilt (Invalidate+paint)', @DoTick);
  DoFrame;   { warm the static layer }
  MsPer(GIters, 'animation tick, static layer standing', @DoFrame);
  WriteLn(Format('  %-42s %8.2f ms', ['=> build alone (tick - paint)', tick - paint]));
  WriteLn(Format('  %-42s %8.1f fps', ['=> if a tick cost only the paint', 1000 / paint]));
  WriteLn(Format('  %-42s %8.1f fps', ['=> at today''s tick cost', 1000 / tick]));
  if parse < 0 then Exit;
end;

{ D9, DIRTY RECTANGLES [Batch 142]: a frame where only part of the chart
  changed, on the layered path, with UseDirtyRect off (today's) and on.
    sweep   the pointer steps to the next mark every frame: the hovered
            bar's emphasis changes (a static-layer restyle) and the
            tooltip moves
    drift   the pointer moves 1 px inside one bar: only the tooltip moves
    idle    nothing changed at all
  The canvas keeps the last frame, as a window's does. }
procedure BenchDirty(const AName: string; APoints: Integer; AWithBars: Boolean);
const
  cN = 40;
var
  dirty: Boolean;
  i, x, y: Integer;
  t: QWord;
  ms, area: array[Boolean, 0..2] of Double;
  hits: Integer;
begin
  WriteLn;
  WriteLn(AName, ' -- ', APoints, ' points, ', W, 'x', H, ', tooltip on, hover per frame');
  GText := StringReplace(MakeOption(APoints, AWithBars), '{ xAxis',
    '{ animation: false, tooltip: {}, xAxis', []);
  { the tooltip's clock held: the box shows at once, with no timer }
  chart.TooltipNow := 0;
  hits := 0;
  for dirty := False to True do
  begin
    chart.UseDirtyRect := dirty;
    chart.Option := GText;
    DoFrame;
    DoFrame;
    area[dirty, 0] := 0;
    t := GetTickCount64;
    for i := 1 to cN do
    begin
      chart.BarPoint((i * 7) mod APoints, x, y);
      chart.Hover(x, y);
      if not dirty and TyChartDatumValid(chart.HitTestAt(x, y)) then Inc(hits);
      DoFrame;
      area[dirty, 0] := area[dirty, 0] + chart.RepaintArea;
    end;
    ms[dirty, 0] := (GetTickCount64 - t) / cN;
    chart.BarPoint(APoints div 2, x, y);
    chart.Hover(x, y);
    DoFrame;
    area[dirty, 1] := 0;
    t := GetTickCount64;
    for i := 1 to cN do
    begin
      chart.Hover(x + (i mod 2), y);
      DoFrame;
      area[dirty, 1] := area[dirty, 1] + chart.RepaintArea;
    end;
    ms[dirty, 1] := (GetTickCount64 - t) / cN;
    chart.Hover(5, 5);
    DoFrame;
    area[dirty, 2] := 0;
    t := GetTickCount64;
    for i := 1 to cN do
    begin
      DoFrame;
      area[dirty, 2] := area[dirty, 2] + chart.RepaintArea;
    end;
    ms[dirty, 2] := (GetTickCount64 - t) / cN;
  end;
  WriteLn(Format('  sweep frames over a mark: %d of %d; dirty px per frame: sweep %.0f, drift %.0f, idle %.0f (of %d)',
    [hits, cN, area[True, 0] / cN, area[True, 1] / cN, area[True, 2] / cN, W * H]));
  chart.UseDirtyRect := False;
  WriteLn(Format('  %-42s %9s %9s', ['', 'full', 'dirty']));
  WriteLn(Format('  %-42s %6.2f ms %6.2f ms', ['sweep: emphasis + tooltip every frame', ms[False, 0], ms[True, 0]]));
  WriteLn(Format('  %-42s %6.2f ms %6.2f ms', ['drift: the tooltip moves 1 px', ms[False, 1], ms[True, 1]]));
  WriteLn(Format('  %-42s %6.2f ms %6.2f ms', ['idle: nothing changed', ms[False, 2], ms[True, 2]]));
end;

{ WHAT ONE LABEL COSTS. Batching the strokes moved 600 points from 110 ms to
  66, but 60 points barely moved and the axes-hidden floor is 16 -- so most of
  the axis cost does not scale with the number of lines. Labels are the only
  other thing an axis draws, and there are roughly as many of them at 60 points
  as at 600, because thinning targets a pixel spacing rather than a count. This
  times the painter's text path directly instead of inferring it. }
procedure BenchText;
var
  P: TTyPainter;
  b: TBGRABitmap;
  t: QWord;
  i: Integer;
begin
  WriteLn;
  WriteLn('the text path itself, on a 900x700 surface');
  b := TBGRABitmap.Create(900, 700, BGRA(255, 255, 255, 255));
  P := TTyPainter.Create;
  try
    P.BeginPaint(b.Canvas, Rect(0, 0, 900, 700), 96);
    P.DrawText(Rect(10, 10, 200, 30), 'c123', '', 13, 400, $FF000000,
               taCenter, tlCenter, False);
    t := GetTickCount64;
    for i := 1 to 200 do
      P.DrawText(Rect(10, 10, 200, 30), 'c123', '', 13, 400, $FF000000,
                 taCenter, tlCenter, False);
    WriteLn(Format('  %-42s %8.3f ms', ['DrawText, 4 characters',
      (GetTickCount64 - t) / 200]));
    t := GetTickCount64;
    for i := 1 to 200 do
      P.MeasureText('c123', '', 13, 400);
    WriteLn(Format('  %-42s %8.3f ms', ['MeasureText, 4 characters',
      (GetTickCount64 - t) / 200]));
    P.EndPaint;
  finally
    P.Free;
    b.Free;
  end;
end;

begin
  Application.Initialize;
  W := 900; H := 700;
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  ctl.Mode := 'light';
  ctl.ThemeName := 'default';
  chart := TChartProbe.Create(form);
  chart.Parent := form;
  chart.Controller := ctl;
  chart.SetBounds(0, 0, W, H);
  bmp := TBGRABitmap.Create(W, H, BGRA(255, 255, 255, 255));
  try
    WriteLn('TTyAdvanceChart frame cost, windowed, headless RenderTo');
    { ADVCHART_BENCH_D9=1: the dirty-rect cases only [Batch 142] }
    if GetEnvironmentVariable('ADVCHART_BENCH_D9') <> '1' then
    begin
    Bench('small', 60, True);
    Bench('medium', 600, True);
    Bench('medium, axes hidden (frame + series only)', 600, True, True);
    W := 300; H := 200;
    bmp.SetSize(W, H);
    chart.SetBounds(0, 0, W, H);
    Bench('medium at a quarter of the pixels', 600, True);
    W := 900; H := 700;
    bmp.SetSize(W, H);
    chart.SetBounds(0, 0, W, H);
    GIters := 4;
    Bench('large -- the case that cost ten seconds', 5000, False);
    GSameLabel := True;
    Bench('large, ONE repeated label (memo hits every time)', 5000, False);
    GSameLabel := False;
    GIters := 40;
    BenchText;
    end;
    BenchDirty('D9 small', 60, True);
    BenchDirty('D9 medium', 600, True);
    W := 300; H := 200;
    bmp.SetSize(W, H);
    chart.SetBounds(0, 0, W, H);
    BenchDirty('D9 medium at a quarter of the pixels', 600, True);
    W := 900; H := 700;
    bmp.SetSize(W, H);
    chart.SetBounds(0, 0, W, H);
  finally
    bmp.Free;
    chart.Free;
    ctl.Free;
    form.Free;
  end;
end.
