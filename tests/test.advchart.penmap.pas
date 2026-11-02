unit test.advchart.penmap;
{$mode objfpc}{$H+}
{ THE PEN UNDER AN UNEQUAL TRANSFORM, held to upstream. [R7-P]

  tests/fixtures/advchart-pen-map.json, from the real ECharts 6.1 build
  rendered by zrender's canvas painter on a recording context
  (tools/advchart-oracle/pen-map.js): at every stroke of a path, the
  context's transform (its linear part m), lineWidth lw, dash and phase, and
  the element's stroke colour and the centre of its box. The canvas' pen is m
  times a round pen of width lw -- elliptical where m scales unequally -- its
  dash measured along the path taken back through m.

  TestThePensAsUpstream: per stroke whose colour is one the case wrote
  (#aN00xx), the element of the series list stroked in that colour whose
  shape's centre is nearest: the pen the renderer draws (TyStylePenOf, else
  the width times PenScale) as m times lw -- the same ellipse (E E^T,
  rotation of a round pen being nothing), the dash and its phase over the
  width as upstream's over lw.

  TestAnOblongSymbolsPenIsStretched, TestAScaledGraphicsDashIsStretched:
  the renderer really strokes through the map -- the ink of an oblong rect
  symbol's sides, a scaled line's dashes, counted. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Geo,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TPenMapProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TAdvChartPenMapOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FChart: TPenMapProbe;
    procedure Chart(const AOption: string; AW, AH: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePensAsUpstream;
    procedure TestAnOblongSymbolsPenIsStretched;
    procedure TestAScaledGraphicsDashIsStretched;
  end;

implementation

function TPenMapProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TPenMapProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
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

function HexD(const S: string): Double;
var q: QWord;
begin
  q := QWord(StrToQWord('$' + S));
  Move(q, Result, 8);
end;

procedure TAdvChartPenMapOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FMeasure := LoadJson('advchart-text-style.json');
end;

procedure TAdvChartPenMapOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartPenMapOracleTest.Chart(const AOption: string; AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FChart := TPenMapProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Option := AOption;
  AssertEquals('parses', '', FChart.OptionError);
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, AW, AH), 96);
end;

{ #aN00xx (N 0 to b): a colour a case wrote for one of its elements }
function Ours(const S: string): Boolean;
begin
  Result := (Length(S) = 7) and (Copy(S, 1, 2) = '#a') and (S[3] in ['0'..'9', 'a', 'b'])
    and (Copy(S, 4, 2) = '00');
end;

procedure TAdvChartPenMapOracleTest.TestThePensAsUpstream;
var
  fix: TJSONData;
  cs, ss: TJSONArray;
  c, s: TJSONObject;
  i, j, k, best, nBad, nCmp, nStretched: Integer;
  id, bad, col: string;
  want: TTyChartColor;
  el: TTyChartElement;
  b: TTyRectF;
  cx, cy, dd, bd, lw, w, ps, off: Double;
  m, E: TTyMat2D;
  gu, gp: array[0..2] of Double;
  dash, pdash: TTyDoubleArray;
  n: Double;
  reg: TJSONObject;

  procedure Gram(const A: TTyMat2D; AW: Double; var G: array of Double);
  begin
    G[0] := (A[0] * A[0] + A[2] * A[2]) * AW * AW;
    G[1] := (A[0] * A[1] + A[2] * A[3]) * AW * AW;
    G[2] := (A[1] * A[1] + A[3] * A[3]) * AW * AW;
  end;

  procedure Miss(const AWhy: string);
  begin
    Inc(nBad);
    if nBad <= 40 then bad := bad + LineEnding + id + ' ' + col + ': ' + AWhy;
  end;

begin
  fix := LoadJson('advchart-pen-map.json');
  { the SVG maps the cases name }
  for i := 0 to TJSONObject(fix).Arrays['maps'].Count - 1 do
  begin
    reg := TJSONObject.Create(['svg', TJSONObject(fix).Arrays['maps'].Objects[i].Strings['svg']]);
    try
      AssertTrue('the map registers', TyChartRegisterMap(
        TJSONObject(fix).Arrays['maps'].Objects[i].Strings['map'], reg.AsJSON));
    finally
      reg.Free;
    end;
  end;
  nBad := 0;
  nCmp := 0;
  nStretched := 0;
  bad := '';
  try
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      Chart(c.Objects['option'].AsJSON, TJSONObject(fix).Integers['W'], TJSONObject(fix).Integers['H']);
      ss := c.Arrays['strokes'];
      for j := 0 to ss.Count - 1 do
      begin
        s := ss.Objects[j];
        col := s.Strings['col'];
        if not Ours(col) then Continue;
        AssertTrue(id + ' colour ' + col, TyTryParseChartColor(col, want));
        cx := HexD(s.Strings['cx']);
        cy := HexD(s.Strings['cy']);
        best := -1;
        bd := 0;
        for k := 0 to FChart.SeriesList.Count - 1 do
        begin
          el := FChart.SeriesList.Element(k);
          if el.Ignore or not (el.Style.StrokeWidthLogical > 0) then Continue;
          if el.Style.StrokeColor <> want then Continue;
          b := TyShapeBounds(el.Shape);
          dd := Sqr((b.Left + b.Right) / 2 - cx) + Sqr((b.Top + b.Bottom) / 2 - cy);
          if (best < 0) or (dd < bd) then
          begin
            best := k;
            bd := dd;
          end;
        end;
        if best < 0 then
        begin
          Miss(Format('no element stroked so near (%g, %g)', [cx, cy]));
          Continue;
        end;
        Inc(nCmp);
        el := FChart.SeriesList.Element(best);
        m := Default(TTyMat2D);
        for k := 0 to 3 do m[k] := HexD(s.Arrays['m'].Strings[k]);
        lw := HexD(s.Strings['lw']);
        Gram(m, lw, gu);
        { A ROUND PEN STAYS THE ROUND PEN: where upstream's map is a turn and
          a uniform scale (or a mirror of one), the element carries no map
          -- it draws as it did before, to the byte }
        n := Max(Max(Abs(m[0]), Abs(m[1])), Max(Abs(m[2]), Abs(m[3])));
        if (((Abs(m[0] - m[3]) <= 1e-9 * n) and (Abs(m[1] + m[2]) <= 1e-9 * n))
          or ((Abs(m[0] + m[3]) <= 1e-9 * n) and (Abs(m[1] - m[2]) <= 1e-9 * n)))
          and el.Style.HasPenMap then
          Miss(Format('a map on a round pen (at %g, %g)', [cx, cy]));
        if TyStylePenOf(el.Style, E) then
        begin
          Inc(nStretched);
          w := el.Style.StrokeWidthLogical;
        end
        else
        begin
          E := Default(TTyMat2D);
          E[0] := 1;
          E[3] := 1;
          ps := el.Style.PenScale;
          if (ps <= 0) or IsNan(ps) or IsInfinite(ps) then ps := 1;
          w := el.Style.StrokeWidthLogical * ps;
        end;
        Gram(E, w, gp);
        n := Max(Abs(gu[0]), Abs(gu[2]));
        if (Abs(gu[0] - gp[0]) > 1e-9 * n) or (Abs(gu[1] - gp[1]) > 1e-9 * n)
          or (Abs(gu[2] - gp[2]) > 1e-9 * n) then
        begin
          Miss(Format('pen E E^T %.6g %.6g %.6g, upstream %.6g %.6g %.6g (at %g, %g)',
            [gp[0], gp[1], gp[2], gu[0], gu[1], gu[2], cx, cy]));
          Continue;
        end;
        { the dash and its phase over the width }
        SetLength(dash, s.Arrays['dash'].Count);
        for k := 0 to High(dash) do dash[k] := HexD(s.Arrays['dash'].Strings[k]);
        if Length(dash) = 0 then Continue;
        w := el.Style.StrokeWidthLogical;
        if el.Style.DashWord <> 0 then pdash := TyDashOfWord(el.Style.DashWord, w)
        else pdash := el.Style.DashLogical;
        if Length(pdash) <> Length(dash) then
        begin
          Miss(Format('dash of %d, upstream %d', [Length(pdash), Length(dash)]));
          Continue;
        end;
        for k := 0 to High(dash) do
          if Abs(pdash[k] / w - dash[k] / lw) > 1e-9 * Max(1.0, dash[k] / lw) then
            Miss(Format('dash %d: %g of the width, upstream %g', [k, pdash[k] / w, dash[k] / lw]));
        off := HexD(s.Strings['off']);
        if Abs(el.Style.DashOffsetLogical / w - off / lw) > 1e-9 * Max(1.0, Abs(off / lw)) then
          Miss(Format('phase %g of the width, upstream %g', [el.Style.DashOffsetLogical / w, off / lw]));
      end;
    end;
  finally
    for i := 0 to TJSONObject(fix).Arrays['maps'].Count - 1 do
      TyChartUnregisterMap(TJSONObject(fix).Arrays['maps'].Objects[i].Strings['map']);
    fix.Free;
  end;
  AssertEquals('pens as upstream (' + IntToStr(nCmp) + ' compared)' + bad, 0, nBad);
  AssertTrue('strokes compared', nCmp >= 60);
  AssertTrue('pens through a map', nStretched >= 40);
end;

{ the ink of a row or a column of the picture: dark pixels }
function InkRun(ABmp: TBGRABitmap; AX0, AY0, ADX, ADY, AN: Integer): Integer;
var k: Integer; p: TBGRAPixel;
begin
  Result := 0;
  for k := 0 to AN - 1 do
  begin
    p := ABmp.GetPixel(AX0 + ADX * k, AY0 + ADY * k);
    if p.green < 128 then Inc(Result);
  end;
end;

procedure TAdvChartPenMapOracleTest.TestAnOblongSymbolsPenIsStretched;
var across, down: Integer;
begin
  { a rect symbol 80 x 20 at (200, 150), no fill, a border 4 wide: the unit
    path scaled (40, 10), strokeNoScale -- the canvas' pen is diag(40, 10)
    over 20 times a round pen of 4: 8 px across its upright sides, 2 px
    across its level ones [a round pen: 4 and 4] }
  Chart('{"animation":false,"xAxis":{"show":false,"min":0,"max":10},"yAxis":{"show":false,"min":0,"max":10},'
    + '"grid":{"left":0,"right":0,"top":0,"bottom":0},'
    + '"series":[{"type":"scatter","symbol":"rect","symbolSize":[80,20],'
    + '"itemStyle":{"color":"rgba(0,0,0,0)","borderColor":"#000","borderWidth":4},"data":[[5,5]]}]}', 400, 300);
  { along the row through the centre: the two upright sides }
  across := InkRun(FBmp, 140, 150, 1, 0, 120);
  { down the column through the centre: the two level sides }
  down := InkRun(FBmp, 200, 120, 0, 1, 60);
  AssertTrue('the upright sides 8 px thick (' + IntToStr(across) + ' px of ink)', (across >= 14) and (across <= 18));
  AssertTrue('the level sides 2 px thick (' + IntToStr(down) + ' px of ink)', (down >= 3) and (down <= 6));
  { turned a quarter: the long sides upright now and 2 px thick, the short
    ones level and 8 px -- the map's turn goes with the pen }
  Chart('{"animation":false,"xAxis":{"show":false,"min":0,"max":10},"yAxis":{"show":false,"min":0,"max":10},'
    + '"grid":{"left":0,"right":0,"top":0,"bottom":0},'
    + '"series":[{"type":"scatter","symbol":"rect","symbolSize":[80,20],"symbolRotate":90,'
    + '"itemStyle":{"color":"rgba(0,0,0,0)","borderColor":"#000","borderWidth":4},"data":[[5,5]]}]}', 400, 300);
  across := InkRun(FBmp, 170, 150, 1, 0, 60);
  down := InkRun(FBmp, 200, 90, 0, 1, 120);
  AssertTrue('turned: the long sides 2 px thick (' + IntToStr(across) + ' px of ink)', (across >= 3) and (across <= 6));
  AssertTrue('turned: the short sides 8 px thick (' + IntToStr(down) + ' px of ink)', (down >= 14) and (down <= 18));
end;

procedure TAdvChartPenMapOracleTest.TestAScaledGraphicsDashIsStretched;
var
  k, x, y, len, first, nIn, nBad: Integer;
  ink, was: Boolean;
  lens: array of Integer;
  txt: string;
begin
  { a level line 100 long scaled (3, 1) from (20, y), dashed [4, 4], 2
    wide: on the canvas 12 px on, 12 px off, 2 px thick; the second's phase
    2 is 6 px, its first dash 6 px long [a round pen: its width, dash and
    phase times the root of 3 -- 3.5 px thick, dashes of 6.9 px] }
  Chart('{"animation":false,"graphic":[{"type":"line","x":20,"y":100,"scaleX":3,"scaleY":1,'
    + '"shape":{"x1":0,"y1":0,"x2":100,"y2":0},"style":{"stroke":"#000","lineWidth":2,"lineDash":[4,4]}},'
    + '{"type":"line","x":20,"y":200,"scaleX":3,"scaleY":1,'
    + '"shape":{"x1":0,"y1":0,"x2":100,"y2":0},"style":{"stroke":"#000","lineWidth":2,"lineDash":[4,4],'
    + '"lineDashOffset":2}}]}', 400, 300);
  AssertEquals('2 px thick', 2, InkRun(FBmp, 26, 90, 0, 1, 20));
  { [R7-P] the phased dash where the path is: 2 px about y 200, not half a
    pixel up and to the left [was: the path's own pixel offset added again] }
  AssertEquals('the phased line on its place', 2, InkRun(FBmp, 22, 195, 0, 1, 10));
  AssertTrue('the phased line starts at x 20', FBmp.GetPixel(19, 199).green >= 250);
  for k := 0 to 1 do
  begin
    y := 100 + 100 * k;
    lens := nil;
    len := 0;
    was := False;
    for x := 20 to 320 do
    begin
      ink := FBmp.GetPixel(x, y).green < 128;
      if ink = was then Inc(len)
      else
      begin
        if x > 20 then
        begin
          SetLength(lens, Length(lens) + 1);
          lens[High(lens)] := len;
        end;
        len := 1;
        was := ink;
      end;
    end;
    txt := '';
    for x := 0 to High(lens) do txt := txt + ' ' + IntToStr(lens[x]);
    { lens[0] is the first dash (the run before it, x 20, is its start) }
    nIn := 0;
    nBad := 0;
    first := 0;
    if k = 1 then first := 1;
    for x := first to High(lens) - 1 do
    begin
      Inc(nIn);
      if (lens[x] < 11) or (lens[x] > 13) then Inc(nBad);
    end;
    AssertTrue('line ' + IntToStr(k) + ': the dashes and gaps 12 px (' + txt + ')', (nIn >= 20) and (nBad = 0));
    if k = 1 then
      AssertTrue('the phase 6 px: its first dash 6 px (' + txt + ')', (lens[0] >= 5) and (lens[0] <= 7));
  end;
end;

initialization
  RegisterTest(TAdvChartPenMapOracleTest);
end.
