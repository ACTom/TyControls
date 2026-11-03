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
    element before it left: TestOneNumberSizesAsUpstream.

  [R7-V] The cases named v-..., on a recording context that refuses what a
  browser's refuses setter by setter; per tracked element the context once it
  was brushed, its fills and strokes with the alpha then, the bounds of its
  path, and findHover at probes: TestTheCanvasStateAsUpstream (an effect
  symbol's carried transform and shadow, a pen's carried cap / join /
  miterLimit, a refused fill, the alpha of an opacity outside 0..1, a graph
  edge's end in a collapsed box) and TestTheHitsAsUpstream. }
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
    function KeyOfEl(AIdx: Integer; AGraph: Boolean): string;
    function GraphicOf(const ARec: TJSONObject): Integer;
    procedure RunV(AHits: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheEffectShadowAsUpstream;
    procedure TestOneNumberSizesAsUpstream;
    procedure TestTheCanvasStateAsUpstream;
    procedure TestTheHitsAsUpstream;
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
  if GetEnvironmentVariable('TY_LC_TRACE') <> '' then WriteLn('MISS ', AWhat);
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
  { [R7-V] a lines row's line, a graph edge's line and node }
  else if pre = 'l' then role := carLinesLine
  else if pre = 'ge' then begin role := carGraphEdge; edge := True; end
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
    { [R7-V] the v- cases: RunV }
    if Copy(id, 1, 2) = 'v-' then Continue;
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

{ [R7-V] the key a port element answers to: the oracle's prefixes, 'other'
  for anything it does not track }
function TAdvChartLinesCanvasOracleTest.KeyOfEl(AIdx: Integer; AGraph: Boolean): string;
var el: TTyChartElement; pre: string;
begin
  el := FChart.Frame.Element(AIdx);
  if el.Caption.FontSizeLogical <> 0 then Exit('other');
  case el.Anim.Role of
    carLinesEffect: pre := 'e';
    carLinesFrom: pre := 'f';
    carLinesTo: pre := 't';
    carLinesLine: pre := 'l';
    carGraphEdgeFrom: pre := 'gf';
    carGraphEdgeTo: pre := 'gt';
    carGraphEdge: pre := 'ge';
    carSymbol:
      if el.Datum.IsEdge then Exit('other')
      else if AGraph then pre := 'gn'
      else pre := 's';
  else
    Exit('other');
  end;
  if el.Datum.SeriesIndex < 0 then Exit('other');
  Result := Format('%s%d.%d', [pre, el.Datum.SeriesIndex, el.Datum.DataIndex]);
end;

{ a graphic element: the frame's element whose bounds are the recorded path's }
function TAdvChartLinesCanvasOracleTest.GraphicOf(const ARec: TJSONObject): Integer;
var
  L: TTyPaintList;
  k: Integer;
  bb: TTyRectF;
  pb: TJSONArray;
begin
  Result := -1;
  if ARec.Find('pb').JSONType = jtNull then Exit;
  pb := ARec.Arrays['pb'];
  L := FChart.Frame;
  for k := 0 to L.Count - 1 do
  begin
    if L.Element(k).Caption.FontSizeLogical <> 0 then Continue;
    bb := TyShapeBounds(L.Element(k).Shape);
    if not TyRectFIsValid(bb) then Continue;
    if (Abs(bb.Left - HexD(pb.Strings[0])) < 0.01) and (Abs(bb.Top - HexD(pb.Strings[1])) < 0.01)
      and (Abs(bb.Right - HexD(pb.Strings[2])) < 0.01) and (Abs(bb.Bottom - HexD(pb.Strings[3])) < 0.01) then
      Exit(k);
  end;
end;

{ AHits False: the canvas state and the paths; True: findHover at the probes }
procedure TAdvChartLinesCanvasOracleTest.RunV(AHits: Boolean);
const
  cCap: array[0..2] of string = ('butt', 'round', 'square');
  cJoin: array[0..2] of string = ('miter', 'round', 'bevel');
var
  cs, frames, els, ops, hits, h: TJSONArray;
  c, fr, rec, st, o: TJSONObject;
  i, j, k, idx, q, at: Integer;
  id, key, where, sc, got, want: string;
  t, sb, sox, soy, x, y, ga, pa, ml: Double;
  el: TTyChartElement;
  wc: TTyChartColor;
  m: array[0..5] of Double;
  bb, mb, pbr: TTyRectF;
  graph, isFill, upVisible, portVisible: Boolean;
begin
  FBad := 0;
  FCompared := 0;
  FReport := '';
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if Copy(id, 1, 2) <> 'v-' then Continue;
    if GetEnvironmentVariable('TY_LC_TRACE') <> '' then WriteLn('case ', id);
    graph := Copy(id, 1, 7) = 'v-graph';
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
    FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
    frames := c.Arrays['frames'];
    for j := 0 to frames.Count - 1 do
    begin
      fr := frames.Objects[j];
      t := fr.Floats['t'];
      { the case's action: a highlight before its second sample }
      if (id = 'v-op-scatter') and (j = 1) then
        FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":0}');
      if t > 0 then FChart.AnimTick(cT0 + t);
      FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
      if AHits then
      begin
        if fr.Find('hits') = nil then Continue;
        hits := fr.Arrays['hits'];
        for k := 0 to hits.Count - 1 do
        begin
          h := hits.Arrays[k];
          x := HexD(h.Strings[0]);
          y := HexD(h.Strings[1]);
          if h.Items[2].JSONType = jtNull then want := '-' else want := h.Strings[2];
          idx := FChart.Frame.HitTestElement(x, y, 96, False);
          if idx < 0 then got := '-' else got := KeyOfEl(idx, graph);
          Inc(FCompared);
          if got <> want then
            Miss(Format('%s t=%g (%g,%g): hit %s, upstream %s', [id, t, x, y, got, want]));
        end;
        Continue;
      end;
      els := fr.Arrays['els'];
      for k := 0 to els.Count - 1 do
      begin
        rec := els.Objects[k];
        key := rec.Strings['key'];
        where := Format('%s t=%g %s', [id, t, key]);
        if rec.Find('st').JSONType = jtNull then Continue;
        st := rec.Objects['st'];
        ops := rec.Arrays['ops'];
        if Copy(key, 1, 2) = 'gr' then idx := GraphicOf(rec) else idx := ElOf(key);
        if idx >= 0 then el := FChart.Frame.Element(idx)
        else el := Default(TTyChartElement);
        { A GRAPH EDGE'S END: drawn where upstream's path shows (a pen on a
          path of some length, a fill of some area), at its bounds }
        if (Copy(key, 1, 2) = 'gf') or (Copy(key, 1, 2) = 'gt') then
        begin
          upVisible := False;
          pbr := TyInvalidRectF;
          if rec.Find('pb').JSONType <> jtNull then
          begin
            pbr := TyRectF(HexD(rec.Arrays['pb'].Strings[0]), HexD(rec.Arrays['pb'].Strings[1]),
              HexD(rec.Arrays['pb'].Strings[2]), HexD(rec.Arrays['pb'].Strings[3]));
            if not IsNan(pbr.Left) then
              for q := 0 to ops.Count - 1 do
              begin
                o := ops.Objects[q];
                if (o.Strings['op'] = 'stroke') and (HexD(st.Strings['lw']) > 0)
                  and ((pbr.Right - pbr.Left > 1e-9) or (pbr.Bottom - pbr.Top > 1e-9)) then
                  upVisible := True;
                if (o.Strings['op'] = 'fill') and (rec.Find('pa').JSONType <> jtNull)
                  and (HexD(rec.Strings['pa']) > 1e-6) then
                  upVisible := True;
              end;
          end;
          portVisible := False;
          bb := TyInvalidRectF;
          if (idx >= 0) and not el.Ignore then
          begin
            bb := TyShapeBounds(el.Shape);
            if TyRectFIsValid(bb) and not IsNan(bb.Left) then
            begin
              { the area a fill covers: the shoelace over a polygon's points,
                the box of anything else }
              if (el.Shape.Kind = cskPolygon) and (Length(el.Shape.Points) > 2) then
              begin
                x := 0;
                for q := 0 to High(el.Shape.Points) do
                begin
                  at := (q + 1) mod Length(el.Shape.Points);
                  x := x + el.Shape.Points[q].X * el.Shape.Points[at].Y
                    - el.Shape.Points[at].X * el.Shape.Points[q].Y;
                end;
                x := Abs(x / 2);
              end
              else x := (bb.Right - bb.Left) * (bb.Bottom - bb.Top);
              portVisible := ((el.Style.StrokeWidthLogical > 0)
                  and ((bb.Right - bb.Left > 1e-9) or (bb.Bottom - bb.Top > 1e-9)))
                or (el.Style.HasFill and (x > 1e-6));
            end;
          end;
          Inc(FCompared);
          if upVisible <> portVisible then
            Miss(Format('%s: upstream draws %s at (%g,%g)-(%g,%g), the port %s at (%g,%g)-(%g,%g)',
              [where, BoolToStr(upVisible, True), pbr.Left, pbr.Top, pbr.Right, pbr.Bottom,
               BoolToStr(portVisible, True), bb.Left, bb.Top, bb.Right, bb.Bottom]))
          else if upVisible and ((Abs(bb.Left - pbr.Left) > 0.25) or (Abs(bb.Top - pbr.Top) > 0.25)
            or (Abs(bb.Right - pbr.Right) > 0.25) or (Abs(bb.Bottom - pbr.Bottom) > 0.25)) then
            Miss(Format('%s: drawn at (%g,%g)-(%g,%g), upstream (%g,%g)-(%g,%g)', [where,
              bb.Left, bb.Top, bb.Right, bb.Bottom, pbr.Left, pbr.Top, pbr.Right, pbr.Bottom]));
          Continue;
        end;
        if (idx < 0) or (ops.Count = 0) then Continue;
        { THE ALPHA of each fill and stroke (the opacity cases) }
        if Copy(id, 1, 5) = 'v-op-' then
          for q := 0 to ops.Count - 1 do
          begin
            o := ops.Objects[q];
            isFill := o.Strings['op'] = 'fill';
            ga := HexD(o.Strings['ga']);
            pa := TyCanvasPartAlpha(el.Style, isFill);
            Inc(FCompared);
            if Abs(pa - ga) > 1e-9 then
              Miss(Format('%s %s: alpha %g, upstream %g (opacity %g)', [where, o.Strings['op'], pa, ga,
                el.Style.Alpha]));
          end;
        { THE SHADOW it casts }
        sb := HexD(st.Strings['sb']);
        sox := HexD(st.Strings['sox']);
        soy := HexD(st.Strings['soy']);
        sc := st.Strings['sc'];
        if not TyTryParseChartColor(sc, wc) then wc := 0;
        Inc(FCompared);
        if ((wc shr 24) = 0) or not ((sb > 0) or (sox <> 0) or (soy <> 0)) then
        begin
          if TyStyleHasShadow(el.Style) then
            Miss(Format('%s: a shadow in %x blur %g, upstream casts none (%s blur %g)', [where,
              el.Style.ShadowColor, el.Style.ShadowBlur, sc, sb]));
        end
        else if not TyStyleHasShadow(el.Style) or (el.Style.ShadowColor <> wc)
          or (el.Style.ShadowBlur <> sb) then
          Miss(Format('%s: shadow %x blur %g (has %s), want %s blur %g', [where,
            el.Style.ShadowColor, el.Style.ShadowBlur, BoolToStr(TyStyleHasShadow(el.Style), True), sc, sb]));
        { THE PEN's cap, join and miterLimit, THE FILL (the v-ex- cases) }
        if Copy(id, 1, 5) = 'v-ex-' then
          for q := 0 to ops.Count - 1 do
          begin
            o := ops.Objects[q];
            if (o.Strings['op'] = 'stroke') and (el.Style.StrokeWidthLogical > 0) then
            begin
              ml := el.Style.MiterLimit;
              if ml = 0 then ml := 10;
              Inc(FCompared);
              if (cCap[el.Style.LineCap mod 3] <> st.Strings['cap'])
                or (cJoin[el.Style.LineJoin mod 3] <> st.Strings['join'])
                or (ml <> HexD(st.Strings['ml'])) then
                Miss(Format('%s: cap %s join %s miterLimit %g, upstream %s %s %g', [where,
                  cCap[el.Style.LineCap mod 3], cJoin[el.Style.LineJoin mod 3], ml,
                  st.Strings['cap'], st.Strings['join'], HexD(st.Strings['ml'])]));
              if TyTryParseChartColor(st.Strings['ss'], wc) then
              begin
                Inc(FCompared);
                if el.Style.StrokeColor <> wc then
                  Miss(Format('%s: stroke %x, upstream %s', [where, el.Style.StrokeColor, st.Strings['ss']]));
              end;
            end;
            if (o.Strings['op'] = 'fill') and el.Style.HasFill and (el.Style.FillGradient.Kind = cgkNone)
              and TyTryParseChartColor(st.Strings['fs'], wc) then
            begin
              Inc(FCompared);
              if el.Style.FillColor <> wc then
                Miss(Format('%s: fill %x, upstream %s', [where, el.Style.FillColor, st.Strings['fs']]));
            end;
          end;
        { AN EFFECT SYMBOL'S TRANSFORM no number: the unit symbol under the
          one the canvas had }
        if (key[1] = 'e') and (rec.Find('sy').JSONType = jtNull) then
        begin
          for q := 0 to 5 do m[q] := HexD(st.Arrays['m'].Strings[q]);
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
          Inc(FCompared);
          if not TyRectFIsValid(bb) or (Abs(bb.Left - mb.Left) > 1e-6) or (Abs(bb.Right - mb.Right) > 1e-6)
            or (Abs(bb.Top - mb.Top) > 1e-6) or (Abs(bb.Bottom - mb.Bottom) > 1e-6) then
            Miss(Format('%s: drawn at (%g,%g)-(%g,%g), want (%g,%g)-(%g,%g)', [where,
              bb.Left, bb.Top, bb.Right, bb.Bottom, mb.Left, mb.Top, mb.Right, mb.Bottom]));
        end;
      end;
    end;
  end;
  FreeAndNil(FChart);
  if FBad > 0 then
    Fail(Format('%d of %d differ:%s', [FBad, FCompared, FReport]));
  AssertTrue('compared', FCompared > 10);
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheCanvasStateAsUpstream;
begin
  RunV(False);
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheHitsAsUpstream;
begin
  RunV(True);
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
