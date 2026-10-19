unit test.advchart.multiline;
{$mode objfpc}{$H+}
{ A LABEL OF SEVERAL LINES, TURNED OR NOT, DRAWS EVERY LINE where zrender
  puts it. [R2-A a1, spec 218]

  tools/advchart-oracle/multiline-label.js runs the real dist and records
  every text of several lines -- series labels turned and level, a category
  and a value axis' turned labels -- with its computed transform and every
  TSpan's (x, y) in its own frame: the lines one line height apart, the
  block aligned vertically as a whole, each line centred on its middle.

    - THE RULE: TyRotatedLineCentres, fed the anchor, the turn, the
      vertical alignment, the line height and the line count upstream had,
      answers every TSpan's centre through the transform (to 1e-9: the
      port's sine is not V8's);
    - THE DRAWING: a turned caption of several lines paints exactly what
      DrawTextRotated paints line by line at those centres, and a level one
      paints a line in each half of its box;
    - THE WIRING: the control renders the turned cases (text measured with
      zrender's SSR width table, so its anchors are upstream's) and there
      is ink across the middle of every line upstream drew. }
interface
uses Classes, SysUtils, Math, Types, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.Painter, tyControls.Types,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Render, tyControls.AdvChart.Labels, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TMlProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TAdvChartMultilineLabelTest = class(TTestCase)
  private
    FRoot, FMeasure: TJSONData;
    function Cases: TJSONArray;
    function InkAlong(ABmp, ARef: TBGRABitmap; const AMat: array of Double;
      ATy, ATx0, ATx1: Double): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLineCentresAsUpstream;
    procedure TestATurnedCaptionDrawsEveryLine;
    procedure TestALevelCaptionDrawsEveryLine;
    procedure TestTheChartDrawsEveryLine;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TMlProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TMlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function VAlignOf(const S: string): TTextLayout;
begin
  if S = 'middle' then Result := tlCenter
  else if S = 'bottom' then Result := tlBottom
  else Result := tlTop;
end;

function FixtureDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim;
end;

procedure TAdvChartMultilineLabelTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixtureDir + 'advchart-multiline-label.json');
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixtureDir + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartMultilineLabelTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

function TAdvChartMultilineLabelTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

{ the words' pixels -- ABmp's that ARef, the chart without them, has not --
  in a 3 x 3 window at every whole step from (ATx0, ATy) to (ATx1, ATy) in
  the text's frame, through AMat }
function TAdvChartMultilineLabelTest.InkAlong(ABmp, ARef: TBGRABitmap;
  const AMat: array of Double; ATy, ATx0, ATx1: Double): Integer;
var
  tx, gx, gy: Double;
  px, py, dx, dy: Integer;
  c: TBGRAPixel;
begin
  Result := 0;
  tx := ATx0;
  while tx <= ATx1 do
  begin
    gx := AMat[0] * tx + AMat[2] * ATy + AMat[4];
    gy := AMat[1] * tx + AMat[3] * ATy + AMat[5];
    for dy := -1 to 1 do
      for dx := -1 to 1 do
      begin
        px := Round(gx) + dx;
        py := Round(gy) + dy;
        if (px < 0) or (py < 0) or (px >= ABmp.Width) or (py >= ABmp.Height) then Continue;
        c := ABmp.GetPixel(px, py);
        if c <> ARef.GetPixel(px, py) then Inc(Result);
      end;
    tx := tx + 1;
  end;
end;

{ ---------------- the rule ---------------- }

procedure TAdvChartMultilineLabelTest.TestTheLineCentresAsUpstream;
var
  c, t, k, n: Integer;
  tx: TJSONObject;
  spans, mat: TJSONArray;
  m: array[0..5] of Double;
  got: TTyPointFArray;
  wantX, wantY, sx, sy: Double;
  name: string;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
    for t := 0 to Cases.Objects[c].Arrays['texts'].Count - 1 do
    begin
      tx := Cases.Objects[c].Arrays['texts'].Objects[t];
      name := Format('%s text %d "%s"', [Cases.Objects[c].Strings['id'], t, tx.Strings['text']]);
      mat := tx.Arrays['mat'];
      for k := 0 to 5 do m[k] := FromHex(mat.Strings[k]);
      spans := tx.Arrays['spans'];
      got := TyRotatedLineCentres(m[4], m[5], FromHex(tx.Strings['rotation']),
        VAlignOf(tx.Strings['verticalAlign']), FromHex(tx.Strings['lineHeight']),
        spans.Count);
      AssertEquals(name + ': a centre per line', spans.Count, Length(got));
      for k := 0 to spans.Count - 1 do
      begin
        sx := FromHex(spans.Objects[k].Strings['x']);
        sy := FromHex(spans.Objects[k].Strings['y']);
        wantX := m[0] * sx + m[2] * sy + m[4];
        wantY := m[1] * sx + m[3] * sy + m[5];
        AssertEquals(name + Format(' line %d x', [k]), wantX, got[k].X, 1e-9);
        AssertEquals(name + Format(' line %d y', [k]), wantY, got[k].Y, 1e-9);
        Inc(n);
      end;
    end;
  AssertTrue(Format('lines compared (%d)', [n]), n >= 40);
end;

{ ---------------- the drawing ---------------- }

function CaptionEl(const AText: string; AX, AY, ARot: Double; AH: TTyTextAnchorH;
  AV: TTyTextAnchorV; AW, ABlockH: Double): TTyChartElement;
begin
  Result := TyChartElement(TyShapeRect(TyAnchorBox(AX, AY, AW, ABlockH, AH, AV)));
  Result.Caption.Text := AText;
  Result.Caption.FontName := '';
  Result.Caption.FontSizeLogical := 9;
  Result.Caption.FontWeight := 400;
  Result.Caption.Colour := $FF000000;
  Result.Caption.X := AX;
  Result.Caption.Y := AY;
  Result.Caption.AnchorH := AH;
  Result.Caption.AnchorV := AV;
  Result.Caption.RotationRad := ARot;
  Result.Style.Alpha := 1;
end;

function SamePixels(A, B: TBGRABitmap): Boolean;
var x, y: Integer;
begin
  Result := False;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y) <> B.GetPixel(x, y) then Exit;
  Result := True;
end;

procedure TAdvChartMultilineLabelTest.TestATurnedCaptionDrawsEveryLine;
const
  cRot = 0.7853981633974483;
var
  a, b, old: TBGRABitmap;
  p: TTyPainter;
  el: TTyChartElement;
  bw, bh, k: Integer;
  cs: TTyPointFArray;
  lines: TStringArray;
begin
  TyMeasureTextBlock('Mon' + #10 + '120' + #10 + 'x', '', 9, 400, 96, 0, 0, bw, bh);
  el := CaptionEl('Mon' + #10 + '120' + #10 + 'x', 100, 100, cRot, tahCentre, tavBottom, bw, bh);
  a := TBGRABitmap.Create(200, 200, BGRA(255, 255, 255, 255));
  b := TBGRABitmap.Create(200, 200, BGRA(255, 255, 255, 255));
  old := TBGRABitmap.Create(200, 200, BGRA(255, 255, 255, 255));
  p := TTyPainter.Create;
  try
    p.BeginPaintOn(nil, Rect(0, 0, 200, 200), 96, a);
    TyRenderElement(p, el);
    p.EndPaint;
    { the same lines, one call each, centred on upstream's places }
    lines := ('Mon' + #10 + '120' + #10 + 'x').Split([#10]);
    cs := TyRotatedLineCentres(100, 100, cRot, tlBottom, bh / 3, 3);
    p.BeginPaintOn(nil, Rect(0, 0, 200, 200), 96, b);
    for k := 0 to 2 do
      p.DrawTextRotated(lines[k], '', 9, 400, TTyColor($FF000000), cs[k].X, cs[k].Y,
        cRot, taCenter, tlCenter);
    p.EndPaint;
    { what one call with the break in it paints }
    p.BeginPaintOn(nil, Rect(0, 0, 200, 200), 96, old);
    p.DrawTextRotated('Mon' + #10 + '120' + #10 + 'x', '', 9, 400, TTyColor($FF000000),
      100, 100, cRot, taCenter, tlBottom);
    p.EndPaint;
    AssertTrue('every line, where upstream puts it', SamePixels(a, b));
    AssertFalse('which one call with the breaks in it is not', SamePixels(a, old));
  finally
    p.Free;
    a.Free;
    b.Free;
    old.Free;
  end;
end;

procedure TAdvChartMultilineLabelTest.TestALevelCaptionDrawsEveryLine;
var
  a: TBGRABitmap;
  p: TTyPainter;
  el: TTyChartElement;
  bw, bh, x, y, top, bottom: Integer;
  r: TTyRectF;
  c: TBGRAPixel;
begin
  TyMeasureTextBlock('Mon' + #10 + 'Tue', '', 9, 400, 96, 0, 0, bw, bh);
  el := CaptionEl('Mon' + #10 + 'Tue', 100, 100, 0, tahCentre, tavBottom, bw, bh);
  r := el.Shape.Bounds;
  a := TBGRABitmap.Create(200, 200, BGRA(255, 255, 255, 255));
  p := TTyPainter.Create;
  try
    p.BeginPaintOn(nil, Rect(0, 0, 200, 200), 96, a);
    TyRenderElement(p, el);
    p.EndPaint;
    { ink in the box's top half (the first line) and its bottom half }
    top := 0;
    bottom := 0;
    for y := Floor(r.Top) to Ceil(r.Bottom) - 1 do
      for x := Floor(r.Left) to Ceil(r.Right) - 1 do
      begin
        c := a.GetPixel(x, y);
        if (c.red + c.green + c.blue) div 3 >= 170 then Continue;
        if y < (r.Top + r.Bottom) / 2 then Inc(top) else Inc(bottom);
      end;
    AssertTrue(Format('the first line (%d dark px)', [top]), top > 10);
    AssertTrue(Format('the second line (%d dark px)', [bottom]), bottom > 10);
  finally
    p.Free;
    a.Free;
  end;
end;

{ ---------------- the wiring ---------------- }

procedure TAdvChartMultilineLabelTest.TestTheChartDrawsEveryLine;
var
  form: TForm;
  ctl: TTyStyleController;
  chart: TMlProbe;
  bmp, ref: TBGRABitmap;
  c, t, k, n: Integer;
  cs, tx: TJSONObject;
  spans, mat: TJSONArray;
  m: array[0..5] of Double;
  x0, x1, ty: Double;
begin
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  ref := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    chart := TMlProbe.Create(form);
    chart.Parent := form;
    chart.Controller := ctl;
    chart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
      TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
      TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
    chart.AnimationMode := camOff;
    chart.SetBounds(0, 0, cW, cH);
    n := 0;
    for c := 0 to Cases.Count - 1 do
    begin
      cs := Cases.Objects[c];
      { the turned ones whose lines lie clear of a one-line drawing: the
        first line of a block hung from its bottom, and the outer lines of
        three }
      if (cs.Strings['id'] <> 'bar.turned.two') and (cs.Strings['id'] <> 'axis.turned') then
        Continue;
      { the same chart with its words in no ink (the layout the same): what
        is under them }
      chart.Option := '{}';
      chart.Option := cs.Objects['option'].AsJSON;
      chart.SetOption('{"xAxis":{"axisLabel":{"color":"rgba(0,0,0,0)"}},'
        + '"yAxis":{"axisLabel":{"color":"rgba(0,0,0,0)"}},'
        + '"series":[{"label":{"color":"rgba(0,0,0,0)","textBorderColor":"transparent"}}]}');
      ref.Fill(BGRA(255, 255, 255, 255));
      chart.Render(ref.Canvas, Classes.Rect(0, 0, cW, cH), 96);
      chart.Option := '{}';
      chart.Option := cs.Objects['option'].AsJSON;
      AssertEquals(cs.Strings['id'] + ': the option parses', '', chart.OptionError);
      bmp.Fill(BGRA(255, 255, 255, 255));
      chart.Render(bmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
      for t := 0 to cs.Arrays['texts'].Count - 1 do
      begin
        tx := cs.Arrays['texts'].Objects[t];
        mat := tx.Arrays['mat'];
        for k := 0 to 5 do m[k] := FromHex(mat.Strings[k]);
        spans := tx.Arrays['spans'];
        { along each line's middle, within its words }
        if tx.Strings['align'] = 'right' then
        begin
          x0 := -16;
          x1 := -2;
        end
        else
        begin
          x0 := -6;
          x1 := 6;
        end;
        for k := 0 to spans.Count - 1 do
        begin
          if (spans.Count = 3) and (k = 1) then Continue;
          if (spans.Count = 2) and (k = 1) then Continue;
          ty := FromHex(spans.Objects[k].Strings['y']);
          AssertTrue(Format('%s "%s" line %d has ink', [cs.Strings['id'],
            tx.Strings['text'], k]), InkAlong(bmp, ref, m, ty, x0, x1) > 0);
          Inc(n);
        end;
      end;
    end;
    AssertTrue(Format('lines looked at (%d)', [n]), n >= 12);
  finally
    bmp.Free;
    ref.Free;
    FreeAndNil(form);
    ctl.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartMultilineLabelTest);
end.
