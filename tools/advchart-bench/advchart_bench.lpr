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
  tyControls.Controller, tyControls.AdvanceChart;

type
  TChartProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

procedure TChartProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

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

var GText: string;

procedure DoParse; begin chart.Option := ''; chart.Option := GText; end;
procedure DoPaint; begin chart.Render(bmp.Canvas, Rect(0, 0, W, H), 96); end;
procedure DoTick;  begin chart.Invalidate; chart.Render(bmp.Canvas, Rect(0, 0, W, H), 96); end;

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
  paint := MsPer(40, 'paint only (clean, FDirty = False)', @DoPaint);
  tick  := MsPer(40, 'animation tick TODAY (Invalidate+paint)', @DoTick);
  WriteLn(Format('  %-42s %8.2f ms', ['=> build alone (tick - paint)', tick - paint]));
  WriteLn(Format('  %-42s %8.1f fps', ['=> if a tick cost only the paint', 1000 / paint]));
  WriteLn(Format('  %-42s %8.1f fps', ['=> at today''s tick cost', 1000 / tick]));
  if parse < 0 then Exit;
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
    Bench('small', 60, True);
    Bench('medium', 600, True);
    Bench('medium, axes hidden (frame + series only)', 600, True, True);
    W := 300; H := 200;
    bmp.SetSize(W, H);
    chart.SetBounds(0, 0, W, H);
    Bench('medium at a quarter of the pixels', 600, True);
  finally
    bmp.Free;
    chart.Free;
    ctl.Free;
    form.Free;
  end;
end.
