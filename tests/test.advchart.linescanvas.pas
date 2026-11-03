unit test.advchart.linescanvas;
{$mode objfpc}{$H+}
{ WHAT THE CANVAS IS LEFT WITH, held to upstream. [R7-S]

  tests/fixtures/advchart-lines-canvas.json, from the real ECharts 6.1 build
  (tools/advchart-oracle/lines-canvas.js): zrender's canvas painter on a
  recording context whose shadowColor setter takes only a string and whose
  setTransform refuses a value that is not finite, as a browser's do; per
  case and sample (the clock stepped, the canvas refreshed) a lines series'
  effect symbols, the end symbols, a graph edge's ends and a scatter's
  symbols:

  - a GRADIENT-COLOURED EFFECT SYMBOL with no shadowColor of its own is
    shadowed in what the canvas had (zrender's '#000' after an element with
    none, the colour of a solid effect symbol before it, a line's written
    shadowColor; the canvas' own transparent default after a clip's
    restore): TestTheEffectShadowAsUpstream;
  - A SIZE WRITTEN AS A ONE-NUMBER PAIR: an end symbol's `[12]` is a box of
    no height (normalizeSymbolSize), a scatter's `[12]` scaleY 0 -- nothing
    drawn; an effect's `[12]` leaves scaleY undefined, the transform not a
    number, and the canvas draws the unit symbol under the transform the
    element before it left: TestOneNumberSizesAsUpstream. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart;
type
  TLcProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartLinesCanvasOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLcProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Miss(const AWhat: string);
    function ElOf(const AKey: string): Integer;
    procedure Run(AWhich: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheEffectShadowAsUpstream;
    procedure TestOneNumberSizesAsUpstream;
  end;

implementation

const
  cT0 = 1700000000000.0;

procedure TLcProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLcProbe.Frame: TTyPaintList;
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

procedure TAdvChartLinesCanvasOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'advchart-lines-canvas.json');
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBmp := TBGRABitmap.Create(FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger,
    BGRA(255, 255, 255, 255));
end;

procedure TAdvChartLinesCanvasOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartLinesCanvasOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 6000 then FReport := FReport + LineEnding + AWhat;
end;

{ the frame's element a key names: e<s>.<r> a lines effect symbol, f / t its
  end symbols, gf / gt a graph edge's, s a scatter's symbol }
function TAdvChartLinesCanvasOracleTest.ElOf(const AKey: string): Integer;
var
  L: TTyPaintList;
  k, s, r, p: Integer;
  pre: string;
  role: TTyChartAnimRole;
  edge: Boolean;
  el: TTyChartElement;
begin
  Result := -1;
  p := 1;
  while (p <= Length(AKey)) and (AKey[p] in ['a'..'z']) do Inc(p);
  pre := Copy(AKey, 1, p - 1);
  s := StrToInt(Copy(AKey, p, Pos('.', AKey) - p));
  r := StrToInt(Copy(AKey, Pos('.', AKey) + 1, MaxInt));
  edge := False;
  if pre = 'e' then role := carLinesEffect
  else if pre = 'f' then role := carLinesFrom
  else if pre = 't' then role := carLinesTo
  else if pre = 'gf' then begin role := carGraphEdgeFrom; edge := True; end
  else if pre = 'gt' then begin role := carGraphEdgeTo; edge := True; end
  else role := carSymbol;
  L := FChart.Frame;
  for k := 0 to L.Count - 1 do
  begin
    el := L.Element(k);
    if (el.Anim.Role = role) and (el.Datum.SeriesIndex = s) and (el.Datum.DataIndex = r)
      and (el.Datum.IsEdge = edge) and (el.Caption.FontSizeLogical = 0) then
      Exit(k);
  end;
end;

{ AWhich 0: the shadow cases (grad-*), 1: the one-number sizes (one-*) }
procedure TAdvChartLinesCanvasOracleTest.Run(AWhich: Integer);
var
  cs, frames, els, br: TJSONArray;
  c, fr, rec, b: TJSONObject;
  i, j, k, idx, q: Integer;
  id, key, where, sc: string;
  t, sb, x, y, area: Double;
  el: TTyChartElement;
  want: TTyChartColor;
  m: array[0..5] of Double;
  bb, mb: TTyRectF;
  noBox: Boolean;
begin
  FBad := 0;
  FCompared := 0;
  FReport := '';
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if (AWhich = 0) <> (Copy(id, 1, 5) = 'grad-') then Continue;
    if GetEnvironmentVariable('TY_LC_TRACE') <> '' then WriteLn('case ', id);
    FreeAndNil(FChart);
    FChart := TLcProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := cT0;
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    AssertEquals(id + ' parses', '', FChart.OptionError);
    FBmp.Fill(BGRA(255, 255, 255, 255));
    try
      FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
    except
      if GetEnvironmentVariable('TY_LC_TRACE') <> '' then DumpExceptionBackTrace(Output);
      raise;
    end;
    frames := c.Arrays['frames'];
    for j := 0 to frames.Count - 1 do
    begin
      fr := frames.Objects[j];
      t := fr.Floats['t'];
      if t > 0 then
      begin
        FChart.AnimTick(cT0 + t);
        FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
      end;
      els := fr.Arrays['els'];
      for k := 0 to els.Count - 1 do
      begin
        rec := els.Objects[k];
        key := rec.Strings['key'];
        where := Format('%s t=%g %s', [id, t, key]);
        idx := ElOf(key);
        { an end symbol the port does not make draws nothing }
        if (idx < 0) and (key[1] = 'e') then
        begin
          Miss(where + ': no element');
          Continue;
        end;
        if idx >= 0 then el := FChart.Frame.Element(idx)
        else el := Default(TTyChartElement);
        Inc(FCompared);
        if key[1] = 'e' then
        begin
          br := rec.Arrays['brushes'];
          if (br.Count > 0) = el.Ignore then
          begin
            Miss(Format('%s: brushed %s, the port''s ignore %s', [where,
              BoolToStr(br.Count > 0, True), BoolToStr(el.Ignore, True)]));
            Continue;
          end;
          if br.Count = 0 then Continue;
          b := br.Objects[0];
          { the shadow the canvas casts it with }
          sb := HexD(b.Strings['sb']);
          sc := b.Strings['sc'];
          if sb > 0 then
          begin
            if not TyTryParseChartColor(sc, want) then want := 0;
            if (want shr 24) = 0 then
            begin
              if TyStyleHasShadow(el.Style) then
                Miss(Format('%s: a shadow in %x, the canvas casts none (%s)', [where,
                  el.Style.ShadowColor, sc]));
            end
            else if not TyStyleHasShadow(el.Style) or (el.Style.ShadowColor <> want)
              or (el.Style.ShadowBlur <> sb) then
              Miss(Format('%s: shadow %x blur %g, want %s blur %g', [where,
                el.Style.ShadowColor, el.Style.ShadowBlur, sc, sb]));
          end;
          { a transform that is no number: the unit symbol under the one the
            canvas had }
          if rec.Find('sy').JSONType = jtNull then
          begin
            for q := 0 to 5 do m[q] := HexD(b.Arrays['m'].Strings[q]);
            mb := TyRectF(Infinity, Infinity, -Infinity, -Infinity);
            for q := 0 to 3 do
            begin
              if q in [0, 3] then x := -0.5 else x := 0.5;
              if q in [0, 1] then y := -0.5 else y := 0.5;
              mb.Left := Min(mb.Left, m[0] * x + m[2] * y + m[4]);
              mb.Right := Max(mb.Right, m[0] * x + m[2] * y + m[4]);
              mb.Top := Min(mb.Top, m[1] * x + m[3] * y + m[5]);
              mb.Bottom := Max(mb.Bottom, m[1] * x + m[3] * y + m[5]);
            end;
            bb := TyShapeBounds(el.Shape);
            if not TyRectFIsValid(bb) or (Abs(bb.Left - mb.Left) > 1e-6) or (Abs(bb.Right - mb.Right) > 1e-6)
              or (Abs(bb.Top - mb.Top) > 1e-6) or (Abs(bb.Bottom - mb.Bottom) > 1e-6) then
              Miss(Format('%s: drawn at (%g,%g)-(%g,%g), want (%g,%g)-(%g,%g)', [where,
                bb.Left, bb.Top, bb.Right, bb.Bottom, mb.Left, mb.Top, mb.Right, mb.Bottom]));
          end;
        end
        else
        begin
          { a box of no height (or no scale) draws nothing; the rest draw }
          noBox := (rec.Arrays['box'].Items[2].JSONType = jtNull)
            or (HexD(rec.Arrays['box'].Strings[2]) = 0)
            or (HexD(rec.Arrays['box'].Strings[3]) = 0)
            or ((rec.Find('sy').JSONType <> jtNull) and (HexD(rec.Strings['sy']) = 0))
            or ((rec.Find('sx').JSONType <> jtNull) and (HexD(rec.Strings['sx']) = 0));
          if idx >= 0 then bb := TyShapeBounds(el.Shape) else bb := TyInvalidRectF;
          if TyRectFIsValid(bb) and not el.Ignore then
            area := (bb.Right - bb.Left) * (bb.Bottom - bb.Top)
          else area := 0;
          if IsNan(area) then area := 0;
          if noBox <> (area = 0) then
            Miss(Format('%s: upstream''s box %s, the port''s bounds (%g,%g)-(%g,%g)%s', [where,
              rec.Arrays['box'].AsJSON, bb.Left, bb.Top, bb.Right, bb.Bottom,
              BoolToStr(el.Ignore, ' ignored', '')]));
        end;
      end;
    end;
  end;
  FreeAndNil(FChart);
  if FBad > 0 then
    Fail(Format('%d of %d differ:%s', [FBad, FCompared, FReport]));
  AssertTrue('compared', FCompared > 10);
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheEffectShadowAsUpstream;
begin
  Run(0);
end;

procedure TAdvChartLinesCanvasOracleTest.TestOneNumberSizesAsUpstream;
begin
  Run(1);
end;

initialization
  RegisterTest(TAdvChartLinesCanvasOracleTest);
end.
