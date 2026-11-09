unit test.advchart.canvasborders;
{$mode objfpc}{$H+}
{ A PEN WRITTEN WHERE ONLY THE SERIES' WAS READ, AND A BORDER NEVER DRAWN,
  held to upstream. [R7-Y]

  tests/fixtures/advchart-canvas-borders.json, from the real ECharts 6.1
  build (tools/advchart-oracle/canvas-borders.js): zrender's canvas painter
  on a recording context that refuses what a browser's refuses; per case
  every fill / stroke of the tracked elements with the context then, and
  findHover at probes:

  - a radar data item's own lineStyle.width 'Infinity' (the item's over the
    series'), a radar symbol's itemStyle.borderWidth 'Infinity': stroked at
    the width the canvas had, never hit;
  - a themeRiver layer's itemStyle border: borderColor, borderWidth (1 where
    only the colour is written), the dash and its phase, the ends, the
    shadow, the opacity;
  - the same pattern elsewhere: a graph link's, a parallel line's, a funnel's,
    a boxplot's, a candlestick's and a heatmap's item pen of 'Infinity'.

  TestThePensAsUpstream, TestTheHitsAsUpstream. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart;
type
  TCbProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartCanvasBordersOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCbProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Miss(const AWhat: string);
    function ElOf(const AKey: string): Integer;
    function KeyOf(AIdx: Integer): string;
    procedure Load(const ACase: TJSONObject);
    procedure RunPens;
    procedure RunHits;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePensAsUpstream;
    procedure TestTheHitsAsUpstream;
  end;

implementation

procedure TCbProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TCbProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
  if Result = nil then Result := SeriesList;
end;

function HexD(const S: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + S);
  Move(q, Result, SizeOf(Result));
end;

procedure TAdvChartCanvasBordersOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'advchart-canvas-borders.json');
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBmp := TBGRABitmap.Create(FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger,
    BGRA(255, 255, 255, 255));
end;

procedure TAdvChartCanvasBordersOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartCanvasBordersOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if GetEnvironmentVariable('TY_CB_TRACE') <> '' then WriteLn('MISS ', AWhat);
  if Length(FReport) < 6000 then FReport := FReport + LineEnding + AWhat;
end;

procedure SplitKey(const AKey: string; out APre: string; out A, B, C: Integer);
var p, q: Integer; rest: string;
begin
  p := 1;
  while (p <= Length(AKey)) and (AKey[p] in ['a'..'z']) do Inc(p);
  APre := Copy(AKey, 1, p - 1);
  rest := Copy(AKey, p, MaxInt);
  q := Pos('.', rest);
  A := StrToInt(Copy(rest, 1, q - 1));
  rest := Copy(rest, q + 1, MaxInt);
  q := Pos('.', rest);
  C := -1;
  if q > 0 then
  begin
    B := StrToInt(Copy(rest, 1, q - 1));
    C := StrToInt(Copy(rest, q + 1, MaxInt));
  end
  else B := StrToInt(rest);
end;

{ the port's element a key names: r a radar ring, ra its area, rs its
  symbol on spoke j (Anim.Sub j + 1), tr a themeRiver layer, ge a graph
  link's line, d the one element of a datum; -1 for none }
function TAdvChartCanvasBordersOracleTest.ElOf(const AKey: string): Integer;
var
  L: TTyPaintList;
  k, s, r, j, n: Integer;
  pre: string;
  el: TTyChartElement;
  ok: Boolean;
begin
  Result := -1;
  SplitKey(AKey, pre, s, r, j);
  L := FChart.Frame;
  n := 0;
  for k := 0 to L.Count - 1 do
  begin
    el := L.Element(k);
    if el.Caption.FontSizeLogical <> 0 then Continue;
    if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> s) then Continue;
    if pre = 'ge' then ok := el.Datum.IsEdge and (el.Datum.DataIndex = r)
      and (el.Anim.Role = carGraphEdge)
    else if el.Datum.IsEdge or (el.Datum.DataIndex <> r) then ok := False
    else if pre = 'r' then ok := el.Anim.Role = carRadarLine
    else if pre = 'ra' then ok := el.Anim.Role = carRadarArea
    else if pre = 'rs' then ok := not (el.Anim.Role in [carRadarLine, carRadarArea])
      and (el.Anim.Sub = j + 1)
    else if pre = 'tr' then ok := el.Anim.Role = carRiver
    else
    begin
      { d<s>.<i>.<n>: the n-th element of the datum (a pictorial bar's
        bar rect, which upstream adds after its glyphs and the port before
        them, not counted) }
      ok := False;
      if el.Anim.Role = carPictorialRect then Continue;
      if n = j then Exit(k);
      Inc(n);
    end;
    if ok then Exit(k);
  end;
end;

function TAdvChartCanvasBordersOracleTest.KeyOf(AIdx: Integer): string;
var el: TTyChartElement;
begin
  el := FChart.Frame.Element(AIdx);
  if el.Datum.IsEdge then Exit(Format('ge%d.%d', [el.Datum.SeriesIndex, el.Datum.DataIndex]));
  case el.Anim.Role of
    carRadarLine: Result := Format('r%d.%d', [el.Datum.SeriesIndex, el.Datum.DataIndex]);
    carRadarArea: Result := Format('ra%d.%d', [el.Datum.SeriesIndex, el.Datum.DataIndex]);
    carRiver: Result := Format('tr%d.%d', [el.Datum.SeriesIndex, el.Datum.DataIndex]);
  else
    if el.Anim.Sub > 0 then
      Result := Format('rs%d.%d.%d', [el.Datum.SeriesIndex, el.Datum.DataIndex, el.Anim.Sub - 1])
    else
      Result := Format('d%d.%d', [el.Datum.SeriesIndex, el.Datum.DataIndex]);
  end;
end;

procedure TAdvChartCanvasBordersOracleTest.Load(const ACase: TJSONObject);
var id: string;
begin
  id := ACase.Strings['id'];
  FreeAndNil(FChart);
  FChart := TCbProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  AssertEquals(id + ' parses', '', FChart.OptionError);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
end;

function SameInk(A, B: TTyChartColor): Boolean;
begin
  Result := (A = B) or (((A shr 24) = 0) and ((B shr 24) = 0));
end;

function CapWord(ACap: Byte): string;
begin
  case ACap of
    cTyCapRound: Result := 'round';
    cTyCapSquare: Result := 'square';
  else
    Result := 'butt';
  end;
end;

function JoinWord(AJoin: Byte): string;
begin
  case AJoin of
    cTyJoinRound: Result := 'round';
    cTyJoinBevel: Result := 'bevel';
  else
    Result := 'miter';
  end;
end;

{ the pen each stroke is made with -- its colour, its width in the canvas'
  css px (the op's lineWidth under its transform's line scale), the dash
  and its phase, the ends -- and whether the port strokes at all; the
  shadow and the alpha a themeRiver layer is filled with }
procedure TAdvChartCanvasBordersOracleTest.RunPens;
var
  cs, els, ops, ld: TJSONArray;
  c, rec, o: TJSONObject;
  i, k, q, n, idx: Integer;
  id, key, where: string;
  el: TTyChartElement;
  stroke: TJSONObject;
  m: array[0..5] of Double;
  sc, lw, plw, ldo, pldo, ml: Double;
  wc: TTyChartColor;
  pdash: TTyDoubleArray;
  portStrokes: Boolean;
begin
  FBad := 0;
  FCompared := 0;
  FReport := '';
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    Load(c);
    els := c.Arrays['els'];
    for k := 0 to els.Count - 1 do
    begin
      rec := els.Objects[k];
      key := rec.Strings['key'];
      where := id + ' ' + key;
      ops := rec.Arrays['ops'];
      stroke := nil;
      for q := 0 to ops.Count - 1 do
        if ops.Objects[q].Strings['op'] = 'stroke' then stroke := ops.Objects[q];
      { (an area that fills nothing has no op upstream; the port builds none
        or one of no ink) }
      if (ops.Count = 0) and ((Copy(key, 1, 2) = 'ra') or (Copy(key, 1, 1) = 'r')) then
      begin
        idx := ElOf(key);
        if (Copy(key, 1, 2) = 'ra') or (idx < 0) then Continue;
      end;
      idx := ElOf(key);
      { (an element upstream strokes nothing with that the port does not
        build: a pictorial bar's transparent bar rect) }
      if (idx < 0) and (stroke = nil) and (key[1] = 'd') then Continue;
      if idx < 0 then
      begin
        Miss(where + ': no element');
        Continue;
      end;
      el := FChart.Frame.Element(idx);
      portStrokes := (el.Style.StrokeWidthLogical > 0)
        and (((el.Style.StrokeColor shr 24) <> 0) or (el.Style.StrokeGradient.Kind <> cgkNone));
      Inc(FCompared);
      if stroke = nil then
      begin
        if portStrokes then
          Miss(Format('%s: strokes %x at %g, upstream none', [where, el.Style.StrokeColor,
            el.Style.StrokeWidthLogical]));
        Continue;
      end;
      for n := 0 to 5 do m[n] := HexD(stroke.Arrays['m'].Strings[n]);
      sc := Sqrt(Abs(m[0] * m[3] - m[1] * m[2]));
      lw := HexD(stroke.Strings['lw']) * sc;
      plw := el.Style.StrokeWidthLogical;
      if (el.Style.PenScale > 0) and (el.Style.PenScale <> 1) then plw := plw * el.Style.PenScale;
      { a clear stroke strokes upstream; it inks nothing either way }
      if (stroke.Strings['ss'] <> '[grad]') and TyTryParseChartColor(stroke.Strings['ss'], wc)
        and ((wc shr 24) = 0) then
      begin
        if portStrokes then
          Miss(Format('%s: strokes %x, upstream a clear one', [where, el.Style.StrokeColor]));
        Continue;
      end;
      if not portStrokes or (Abs(plw - lw) > 1e-6) then
      begin
        Miss(Format('%s: stroke width %g (strokes %s), upstream %g', [where, plw,
          BoolToStr(portStrokes, True), lw]));
        Continue;
      end;
      Inc(FCompared);
      if stroke.Strings['ss'] = '[grad]' then
      begin
        if el.Style.StrokeGradient.Kind = cgkNone then
          Miss(Format('%s: stroke %x, upstream a gradient', [where, el.Style.StrokeColor]));
      end
      else if TyTryParseChartColor(stroke.Strings['ss'], wc) then
      begin
        if (el.Style.StrokeGradient.Kind <> cgkNone) or not SameInk(el.Style.StrokeColor, wc) then
          Miss(Format('%s: stroke %x, upstream %s', [where, el.Style.StrokeColor, stroke.Strings['ss']]));
      end;
      { the dash and its phase }
      ld := stroke.Arrays['ld'];
      pdash := el.Style.DashLogical;
      if el.Style.DashWord <> 0 then
        pdash := TyDashOfWord(el.Style.DashWord, el.Style.StrokeWidthLogical);
      Inc(FCompared);
      if Length(pdash) * Ord(ld.Count > 0) <> ld.Count then
        Miss(Format('%s: dash of %d, upstream %s', [where, Length(pdash), ld.AsJSON]))
      else if ld.Count > 0 then
      begin
        for n := 0 to ld.Count - 1 do
          if Abs(pdash[n] - HexD(ld.Strings[n]) * sc) > 1e-6 then
          begin
            Miss(Format('%s: dash %g at %d, upstream %g', [where, pdash[n], n, HexD(ld.Strings[n]) * sc]));
            Break;
          end;
        ldo := HexD(stroke.Strings['ldo']) * sc;
        pldo := el.Style.DashOffsetLogical;
        if IsNan(pldo) then pldo := -1e300;
        if Abs(pldo - ldo) > 1e-6 then
          Miss(Format('%s: dash phase %g, upstream %g', [where, pldo, ldo]));
      end;
      { the ends }
      Inc(FCompared);
      ml := el.Style.MiterLimit;
      if not (ml > 0) then ml := 10;
      if (CapWord(el.Style.LineCap) <> stroke.Strings['cap'])
        or (JoinWord(el.Style.LineJoin) <> stroke.Strings['join'])
        or (Abs(ml - HexD(stroke.Strings['ml'])) > 1e-9) then
        Miss(Format('%s: ends %s/%s/%g, upstream %s/%s/%g', [where, CapWord(el.Style.LineCap),
          JoinWord(el.Style.LineJoin), ml, stroke.Strings['cap'], stroke.Strings['join'],
          HexD(stroke.Strings['ml'])]));
      { a themeRiver layer's shadow and alpha }
      if Copy(key, 1, 2) = 'tr' then
      begin
        Inc(FCompared);
        if Abs(el.Style.Alpha - HexD(stroke.Strings['ga'])) > 1e-9 then
          Miss(Format('%s: alpha %g, upstream %g', [where, el.Style.Alpha, HexD(stroke.Strings['ga'])]));
        if HexD(stroke.Strings['sb']) > 0 then
        begin
          Inc(FCompared);
          if not TyTryParseChartColor(stroke.Strings['sc'], wc) or not TyStyleHasShadow(el.Style)
            or (el.Style.ShadowColor <> wc) or (Abs(el.Style.ShadowBlur - HexD(stroke.Strings['sb'])) > 1e-9)
            or (Abs(el.Style.ShadowOffsetX - HexD(stroke.Strings['sox'])) > 1e-9)
            or (Abs(el.Style.ShadowOffsetY - HexD(stroke.Strings['soy'])) > 1e-9) then
            Miss(Format('%s: shadow %x blur %g at (%g,%g), upstream %s blur %s', [where,
              el.Style.ShadowColor, el.Style.ShadowBlur, el.Style.ShadowOffsetX, el.Style.ShadowOffsetY,
              stroke.Strings['sc'], stroke.Strings['sb']]));
        end
        else
        begin
          Inc(FCompared);
          if TyStyleHasShadow(el.Style) then
            Miss(Format('%s: a shadow, upstream none', [where]));
        end;
      end;
    end;
  end;
  FreeAndNil(FChart);
  if FBad > 0 then
    Fail(Format('%d of %d differ:%s', [FBad, FCompared, FReport]));
  AssertTrue('compared', FCompared > 40);
end;

procedure TAdvChartCanvasBordersOracleTest.RunHits;
var
  cs, hits, h: TJSONArray;
  c: TJSONObject;
  i, k, idx: Integer;
  id, want, got: string;
  x, y: Double;
begin
  FBad := 0;
  FCompared := 0;
  FReport := '';
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    if c.Find('hits') = nil then Continue;
    id := c.Strings['id'];
    Load(c);
    hits := c.Arrays['hits'];
    for k := 0 to hits.Count - 1 do
    begin
      h := hits.Arrays[k];
      x := HexD(h.Strings[0]);
      y := HexD(h.Strings[1]);
      if h.Items[2].JSONType = jtNull then want := '-' else want := h.Strings[2];
      idx := FChart.Frame.HitTestElement(x, y, 96, False);
      if idx < 0 then got := '-' else got := KeyOf(idx);
      Inc(FCompared);
      if got <> want then
        Miss(Format('%s (%g,%g): hit %s, upstream %s', [id, x, y, got, want]));
    end;
  end;
  FreeAndNil(FChart);
  if FBad > 0 then
    Fail(Format('%d of %d differ:%s', [FBad, FCompared, FReport]));
  AssertTrue('compared', FCompared > 100);
end;

procedure TAdvChartCanvasBordersOracleTest.TestThePensAsUpstream;
begin
  RunPens;
end;

procedure TAdvChartCanvasBordersOracleTest.TestTheHitsAsUpstream;
begin
  RunHits;
end;

initialization
  RegisterTest(TAdvChartCanvasBordersOracleTest);
end.
