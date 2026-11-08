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
  edge's end in a collapsed box) and TestTheHitsAsUpstream.

  [R7-W] The cases named w-..., recorded as the v- ones with the context
  every fill / stroke / text is made with: a fill or stroke colour no
  parser reads (the canvas keeps the one it had, a series that writes one
  takes no palette slot), a width of 'Infinity' and a dash phase no number,
  a legend's refused values, what the axes drawn before the series leave,
  a dirty rect's block starting from the canvas' own state, an option set
  while a trail's transform is no number, a symbol of size nought:
  TestTheRefusedValuesAsUpstream and TestTheR7WHitsAsUpstream.

  [R7-Z] The cases named z-..., recorded as the w- ones, every component's
  displayable keyed c.<mainType><index>.<z2>.<t|p>.<n>: a component's own
  refused values (an axis' colour, width, phase, cap, a label's or a name's
  colour) and what the components drawn before the series hand the canvas
  (the graphic's elements under the axes, the axes in upstream's paint
  order): TestTheComponentsCanvasAsUpstream, against what the port drew
  (CompDrawn) and the series' elements as the w- cases.

  [R7-Y] The cases named y-..., every paint of a sample kept: useDirtyRect
  in motion -- the block round what moved repainted from the canvas' own
  state, every other pixel the last frame's: TestTheDirtyFramesAsUpstream,
  on the pixels the cached path composites. A pattern or a gradient the
  canvas keeps for an element whose fill or stroke it refuses, under that
  element's transform (and an element's own pattern in its frame); a
  shadow offset or blur the canvas refuses, a blend word it does not know
  (the ones it had): TestTheHeldPatternsAsUpstream. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes, tyControls.FontUnits,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Render, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart;
type
  TLcProbe = class(TTyAdvanceChart)
  public
    { [R7-Z] a component's part of key AKey, upstream's z2 AZ2 and kind (a
      text or a path) as it was drawn -- the one that fills (AOp 'fill'),
      strokes ('stroke'), else the first; False for none }
    function CompPart(const AKey: string; AZ2: Integer; AText: Boolean; const AOp: string;
      out AEl: TTyChartElement): Boolean;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { [R7-W] through the cached (dirty-rect) path }
    procedure Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
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
    function WElOf(const AKey: string; const ARec: TJSONObject): Integer;
    function CListOf(const ARec: TJSONObject; AText: Boolean): Integer;
    procedure RunW(AHits: Boolean; const APrefix: string = 'w-');
    procedure RunY(const APrefix: string = 'y-');
    procedure RunYHeld(const APrefix: string = 'y-');
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheEffectShadowAsUpstream;
    procedure TestOneNumberSizesAsUpstream;
    procedure TestTheCanvasStateAsUpstream;
    procedure TestTheHitsAsUpstream;
    procedure TestTheRefusedValuesAsUpstream;
    procedure TestTheR7WHitsAsUpstream;
    procedure TestTheComponentsCanvasAsUpstream;
    procedure TestTheDirtyFramesAsUpstream;
    procedure TestTheHeldPatternsAsUpstream;
    { [R7-AB] the ab- cases, as the y- ones }
    procedure TestTheR7ABDirtyFramesAsUpstream;
    procedure TestTheR7ABCarriesAsUpstream;
  end;

implementation

const
  cT0 = 1700000000000.0;

procedure TLcProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TLcProbe.Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

function TLcProbe.CompPart(const AKey: string; AZ2: Integer; AText: Boolean;
  const AOp: string; out AEl: TTyChartElement): Boolean;
var d: TTyCompPartArray; k, first: Integer;
begin
  d := CompDrawn;
  first := -1;
  for k := 0 to High(d) do
    if (d[k].Key = AKey) and (d[k].Z2 = AZ2) and (d[k].IsText = AText) then
    begin
      if first < 0 then first := k;
      if ((AOp = 'fill') and d[k].El.Style.HasFill)
        or ((AOp = 'stroke') and (d[k].El.Style.StrokeWidthLogical > 0)) then
      begin
        AEl := d[k].El;
        Exit(True);
      end;
    end;
  Result := first >= 0;
  if Result then AEl := d[first].El else AEl := Default(TTyChartElement);
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
  else if pre = 'ln' then role := carLineRun
  else role := carSymbol;
  L := FChart.Frame;
  for k := 0 to L.Count - 1 do
  begin
    el := L.Element(k);
    if (el.Anim.Role = role) and (el.Datum.SeriesIndex = s)
      and ((el.Datum.DataIndex = r) or (role = carLineRun))
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
    { [R7-AB] the ab- cases: RunY, RunYHeld }
    if Copy(id, 1, 3) = 'ab-' then Continue;
    if (AWhich = 0) <> (Copy(id, 1, 5) = 'grad-') then Continue;
    { [R7-V] the v- cases: RunV; [R7-W] the w- cases: RunW }
    if (Copy(id, 1, 2) = 'v-') or (Copy(id, 1, 2) = 'w-') or (Copy(id, 1, 2) = 'z-')
      or (Copy(id, 1, 2) = 'y-') then Continue;
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
          { [R7-V] an element of no ink (no fill, no pen) draws nothing }
          if TyRectFIsValid(bb) and not el.Ignore
            and (el.Style.HasFill or (el.Style.StrokeWidthLogical > 0)) then
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
      { the actions the case dispatches before this sample }
      if (c.Find('acts') <> nil) and (c.Objects['acts'].Find(IntToStr(j)) <> nil) then
        for q := 0 to c.Objects['acts'].Arrays[IntToStr(j)].Count - 1 do
          FChart.DispatchAction(c.Objects['acts'].Arrays[IntToStr(j)].Objects[q].AsJSON);
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
        { THE PEN's cap, join and miterLimit, THE FILL (the v-ex- cases;
          [R7-W] v-ex-fill too: a fill / stroke colour the canvas refuses
          is the one it had [was: recorded, not held]) }
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
          one the canvas had -- the bounds of the path it built there (a
          turned circle's are its circle's, not its box's) }
        if (key[1] = 'e') and (rec.Find('sy').JSONType = jtNull)
          and (rec.Find('pb').JSONType <> jtNull) then
        begin
          mb := TyRectF(HexD(rec.Arrays['pb'].Strings[0]), HexD(rec.Arrays['pb'].Strings[1]),
            HexD(rec.Arrays['pb'].Strings[2]), HexD(rec.Arrays['pb'].Strings[3]));
          bb := TyShapeBounds(el.Shape);
          Inc(FCompared);
          { (the record samples an arc at 256 points: 1e-4 of its radius) }
          if not TyRectFIsValid(bb) or (Abs(bb.Left - mb.Left) > 1e-4) or (Abs(bb.Right - mb.Right) > 1e-4)
            or (Abs(bb.Top - mb.Top) > 1e-4) or (Abs(bb.Bottom - mb.Bottom) > 1e-4) then
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

{ [R7-W] the port's element a w- key names: the v- keys, a bar b, a pie's
  sector p, a line's symbol ls and area la, a label x<key> (its host's
  caption), a legend's displayable lg<i>.<n> (the legend element at the
  recorded path's bounds); -1 for none (an axis' text ax<n> is not in the
  list) }
function TAdvChartLinesCanvasOracleTest.WElOf(const AKey: string; const ARec: TJSONObject): Integer;
var
  L: TTyPaintList;
  k, s, r, p: Integer;
  pre, host: string;
  role: TTyChartAnimRole;
  el: TTyChartElement;
  bb: TTyRectF;
  pb: TJSONArray;
begin
  Result := -1;
  L := FChart.Frame;
  if Copy(AKey, 1, 2) = 'ax' then Exit;
  { [R7-W] another series' item graphic: the one element of its datum, else
    a legend's: at the recorded path's bounds }
  if AKey[1] = 'd' then
  begin
    p := 2;
    s := StrToInt(Copy(AKey, p, Pos('.', AKey) - p));
    host := Copy(AKey, Pos('.', AKey) + 1, MaxInt);
    r := StrToInt(Copy(host, 1, Pos('.', host) - 1));
    p := -1;
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      if (el.Caption.FontSizeLogical = 0) and (el.Datum.Kind = ctkSeries)
        and (el.Datum.SeriesIndex = s) and (el.Datum.DataIndex = r) and not el.Datum.IsEdge then
      begin
        if p >= 0 then
        begin
          p := -2;
          Break;
        end;
        p := k;
      end;
    end;
    if p >= 0 then Exit(p);
  end;
  if (Copy(AKey, 1, 2) = 'lg') or (AKey[1] = 'd') then
  begin
    if ARec.Find('pb').JSONType = jtNull then Exit(-2);
    pb := ARec.Arrays['pb'];
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      { (an icon is its series' datum, the hit rect the legend's) }
      if not (el.Datum.Kind in [ctkLegend, ctkSeries]) then Continue;
      if el.Caption.FontSizeLogical <> 0 then Continue;
      bb := TyShapeBounds(el.Shape);
      if not TyRectFIsValid(bb) then Continue;
      if (Abs(bb.Left - HexD(pb.Strings[0])) < 0.6) and (Abs(bb.Top - HexD(pb.Strings[1])) < 0.6)
        and (Abs(bb.Right - HexD(pb.Strings[2])) < 0.6) and (Abs(bb.Bottom - HexD(pb.Strings[3])) < 0.6) then
        Exit(k);
    end;
    Exit;
  end;
  if AKey[1] = 'x' then
  begin
    host := Copy(AKey, 2, MaxInt);
    p := 1;
    while (p <= Length(host)) and (host[p] in ['a'..'z']) do Inc(p);
    s := StrToInt(Copy(host, p, Pos('.', host) - p));
    r := StrToInt(Copy(host, Pos('.', host) + 1, MaxInt));
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      if (el.Caption.FontSizeLogical <> 0) and (el.Caption.Text <> '')
        and (el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex = s)
        and (el.Datum.DataIndex = r) and not el.Datum.IsEdge then
        Exit(k);
    end;
    Exit;
  end;
  p := 1;
  while (p <= Length(AKey)) and (AKey[p] in ['a'..'z']) do Inc(p);
  pre := Copy(AKey, 1, p - 1);
  if pre = 'b' then role := carBar
  else if pre = 'p' then role := carSector
  else if pre = 'ls' then role := carLineSymbol
  else if pre = 'la' then role := carLineArea
  else Exit(ElOf(AKey));
  s := StrToInt(Copy(AKey, p, Pos('.', AKey) - p));
  r := StrToInt(Copy(AKey, Pos('.', AKey) + 1, MaxInt));
  for k := 0 to L.Count - 1 do
  begin
    el := L.Element(k);
    if (el.Anim.Role = role) and (el.Datum.SeriesIndex = s)
      and ((el.Datum.DataIndex = r) or (role = carLineArea))
      and (el.Caption.FontSizeLogical = 0) then
      Exit(k);
  end;
end;

{ [R7-Z] a component's displayable that is in the port's list (a legend's,
  a toolbox's...): a text by its words, a path by its bounds; -2 for a
  background that paints nothing (a fill of no alpha: the port builds none),
  -1 for none }
function TAdvChartLinesCanvasOracleTest.CListOf(const ARec: TJSONObject; AText: Boolean): Integer;
var
  L: TTyPaintList;
  k, q, n: Integer;
  el: TTyChartElement;
  bb: TTyRectF;
  pb, ops: TJSONArray;
  wc: TTyChartColor;
  s: string;
begin
  Result := -1;
  L := FChart.Frame;
  if AText then
  begin
    if ARec.Find('tx') = nil then Exit;
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      if el.Caption.FontSizeLogical = 0 then Continue;
      s := el.Caption.Text;
      if (s = '') and (Length(el.Caption.RtPieces) > 0) then
        for q := 0 to High(el.Caption.RtPieces) do s := s + el.Caption.RtPieces[q].Text;
      if s = ARec.Strings['tx'] then Exit(k);
    end;
    Exit;
  end;
  if ARec.Find('pb').JSONType <> jtNull then
  begin
    pb := ARec.Arrays['pb'];
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      if el.Caption.FontSizeLogical <> 0 then Continue;
      bb := TyShapeBounds(el.Shape);
      if not TyRectFIsValid(bb) then Continue;
      if (Abs(bb.Left - HexD(pb.Strings[0])) < 0.6) and (Abs(bb.Top - HexD(pb.Strings[1])) < 0.6)
        and (Abs(bb.Right - HexD(pb.Strings[2])) < 0.6) and (Abs(bb.Bottom - HexD(pb.Strings[3])) < 0.6) then
        Exit(k);
    end;
  end;
  ops := ARec.Arrays['ops'];
  n := 0;
  for q := 0 to ops.Count - 1 do
    if (ops.Objects[q].Strings['op'] <> 'fill')
      or not TyTryParseChartColor(ops.Objects[q].Strings['fs'], wc) or ((wc shr 24) <> 0) then
      Inc(n);
  if n = 0 then Result := -2;
end;

{ the colours a canvas holds alike: the same, or both of no alpha }
function SameInk(A, B: TTyChartColor): Boolean;
begin
  Result := (A = B) or (((A shr 24) = 0) and ((B shr 24) = 0));
end;

{ what a caption fills and strokes its last span with: the last text
  piece's, else its own colours }
procedure CaptionInk(const AEl: TTyChartElement; out AFill, AStroke: TTyChartColor;
  out AWidth: Double);
var k: Integer;
begin
  AFill := AEl.Caption.Colour;
  AStroke := AEl.Caption.StrokeColour;
  AWidth := AEl.Caption.StrokeWidthLogical;
  for k := High(AEl.Caption.RtPieces) downto 0 do
    if AEl.Caption.RtPieces[k].Text <> '' then
    begin
      AFill := AEl.Caption.RtPieces[k].Fill;
      AStroke := AEl.Caption.RtPieces[k].Stroke;
      if AEl.Caption.RtPieces[k].HasStroke then AWidth := AEl.Caption.RtPieces[k].LineWidth
      else AWidth := 0;
      Exit;
    end;
end;

{ the first fill a key's element made in a sample, '' for none }
function FirstFill(AFrame: TJSONObject; const AKey: string): string;
var els, ops: TJSONArray; k, q: Integer;
begin
  Result := '';
  els := AFrame.Arrays['els'];
  for k := 0 to els.Count - 1 do
    if els.Objects[k].Strings['key'] = AKey then
    begin
      ops := els.Objects[k].Arrays['ops'];
      for q := 0 to ops.Count - 1 do
        if ops.Objects[q].Strings['op'] = 'fill' then Exit(ops.Objects[q].Strings['fs']);
      Exit;
    end;
end;

{ AHits False: the context each fill / stroke / text is made with; True:
  findHover at the probes }
procedure TAdvChartLinesCanvasOracleTest.RunW(AHits: Boolean; const APrefix: string);
var
  { [R7-Z] a component's part: its key, z2 and kind }
  comp: Boolean;
  ckey: string;
  cz2: Integer;
  ctext: Boolean;
  parts: TStringList;
  cs, frames, els, ops, hits, h, sets, blocks, ld: TJSONArray;
  c, fr, rec, o: TJSONObject;
  i, j, k, idx, q, n: Integer;
  id, key, where, got, want, op: string;
  t, x, y, ga, sc, lw, plw, ldo, pldo, sb: Double;
  el: TTyChartElement;
  wc, pf, ps: TTyChartColor;
  m: array[0..5] of Double;
  bb, mb: TTyRectF;
  pdash: TTyDoubleArray;
  isCap, dirty: Boolean;
  px: TBGRAPixel;
begin
  FBad := 0;
  FCompared := 0;
  FReport := '';
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if Copy(id, 1, 2) <> APrefix then Continue;
    { a trail's frames under useDirtyRect: upstream repaints a block round
      each moving symbol and keeps the rest of the last frame's pixels; the
      port draws an animated frame whole (recorded, not held: spec 277) }
    if id = 'w-dirty-effect' then Continue;
    if GetEnvironmentVariable('TY_LC_TRACE') <> '' then WriteLn('case ', id);
    dirty := c.Find('dirty') <> nil;
    FreeAndNil(FChart);
    FChart := TLcProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := cT0;
    FChart.UseDirtyRect := dirty;
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    AssertEquals(id + ' parses', '', FChart.OptionError);
    FBmp.Fill(BGRA(255, 255, 255, 255));
    try
      if dirty then FChart.Layered(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96)
      else FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
    except
      if GetEnvironmentVariable('TY_LC_TRACE') <> '' then DumpExceptionBackTrace(Output);
      raise;
    end;
    frames := c.Arrays['frames'];
    for j := 0 to frames.Count - 1 do
    begin
      fr := frames.Objects[j];
      t := fr.Floats['t'];
      { the option set and the actions dispatched before this sample }
      if (c.Find('sets') <> nil) and (c.Objects['sets'].Find(IntToStr(j)) <> nil) then
      begin
        FChart.AnimNow := cT0 + t;
        FChart.SetOption(c.Objects['sets'].Objects[IntToStr(j)].AsJSON, False);
      end;
      if (c.Find('acts') <> nil) and (c.Objects['acts'].Find(IntToStr(j)) <> nil) then
        for q := 0 to c.Objects['acts'].Arrays[IntToStr(j)].Count - 1 do
          FChart.DispatchAction(c.Objects['acts'].Arrays[IntToStr(j)].Objects[q].AsJSON);
      if t > 0 then FChart.AnimTick(cT0 + t);
      if dirty then FChart.Layered(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96)
      else FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
      if GetEnvironmentVariable('TY_LC_SAVE') <> '' then
        FBmp.SaveToFile(GetEnvironmentVariable('TY_LC_SAVE') + id + '-' + IntToStr(j) + '.png');
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
          if idx < 0 then got := '-' else got := KeyOfEl(idx, Copy(id, 1, 8) = 'w-zero-g');
          Inc(FCompared);
          if got <> want then
            Miss(Format('%s t=%g (%g,%g): hit %s, upstream %s', [id, t, x, y, got, want]));
        end;
        Continue;
      end;
      blocks := fr.Arrays['blocks'];
      els := fr.Arrays['els'];
      for k := 0 to els.Count - 1 do
      begin
        rec := els.Objects[k];
        key := rec.Strings['key'];
        where := Format('%s t=%g %s', [id, t, key]);
        ops := rec.Arrays['ops'];
        if ops.Count = 0 then Continue;
        { [R7-Z] a component's part: what the port drew of it }
        comp := Copy(key, 1, 2) = 'c.';
        if comp then
        begin
          parts := TStringList.Create;
          try
            parts.Delimiter := '.';
            parts.StrictDelimiter := True;
            parts.DelimitedText := key;
            ckey := parts[1];
            cz2 := StrToInt(parts[2]);
            ctext := parts[3] = 't';
          finally
            parts.Free;
          end;
          if FChart.CompPart(ckey, cz2, ctext, '', el) then idx := 0
          else
          begin
            { (a component in the list) }
            comp := False;
            idx := CListOf(rec, ctext);
            if idx = -2 then Continue;
            if idx < 0 then
            begin
              Miss(where + ': no part drawn');
              Continue;
            end;
          end;
        end
        else
        idx := WElOf(key, rec);
        if idx < 0 then
        begin
          { an axis' text: not in the list; a legend's text: not matched
            (-2); a legend's background that paints nothing (a fill of no
            alpha, no pen): the port builds none }
          if (Copy(key, 1, 2) = 'ax') or (idx = -2) then Continue;
          if Copy(key, 1, 2) = 'lg' then
          begin
            n := 0;
            for q := 0 to ops.Count - 1 do
              if (ops.Objects[q].Strings['op'] <> 'fill')
                or not TyTryParseChartColor(ops.Objects[q].Strings['fs'], wc) or ((wc shr 24) <> 0) then
                Inc(n);
            if n = 0 then Continue;
          end;
          Miss(where + ': no element');
          Continue;
        end;
        if comp then isCap := ctext
        else
        begin
          el := FChart.Frame.Element(idx);
          isCap := (key[1] = 'x') or ((Copy(key, 1, 2) = 'c.') and ctext);
        end;
        { A DIRTY RECT'S BLOCK: what the cached path drew there -- the
          pixel at the middle of the path, the fill the block made it
          with over white (an element whose fill the canvas carried) }
        if dirty and (j > 0) then
        begin
          for q := 0 to ops.Count - 1 do
          begin
            o := ops.Objects[q];
            if (o.Strings['op'] <> 'fill') or (blocks.Items[o.Integers['blk']].JSONType = jtNull) then Continue;
            if rec.Find('pb').JSONType = jtNull then Continue;
            if not TyTryParseChartColor(o.Strings['fs'], wc) then Continue;
            { (where the block's fill is not the whole paint's) }
            if FirstFill(frames.Objects[0], key) = o.Strings['fs'] then Continue;
            x := (HexD(rec.Arrays['pb'].Strings[0]) + HexD(rec.Arrays['pb'].Strings[2])) / 2;
            y := (HexD(rec.Arrays['pb'].Strings[1]) + HexD(rec.Arrays['pb'].Strings[3])) / 2;
            px := FBmp.GetPixel(Trunc(x), Trunc(y));
            { the colour over white at whatever coverage the pixel shows: the
              coverage read off the channel farthest from white }
            ga := 0;
            for n := 0 to 2 do
            begin
              sc := 255 - ((wc shr (16 - 8 * n)) and $FF);
              if sc > 60 then
              begin
                case n of
                  0: ga := (255 - px.red) / sc;
                  1: ga := (255 - px.green) / sc;
                else
                  ga := (255 - px.blue) / sc;
                end;
                Break;
              end;
            end;
            Inc(FCompared);
            if (ga < 0.3) or (Abs(px.red - (((wc shr 16) and $FF) * ga + 255 * (1 - ga))) > 6)
              or (Abs(px.green - (((wc shr 8) and $FF) * ga + 255 * (1 - ga))) > 6)
              or (Abs(px.blue - ((wc and $FF) * ga + 255 * (1 - ga))) > 6) then
              Miss(Format('%s: the block drew (%d,%d,%d) at (%g,%g), upstream %s', [where,
                px.red, px.green, px.blue, x, y, o.Strings['fs']]));
          end;
          Continue;
        end;
        for q := 0 to ops.Count - 1 do
        begin
          o := ops.Objects[q];
          op := o.Strings['op'];
          if comp then FChart.CompPart(ckey, cz2, ctext, op, el);
          for n := 0 to 5 do m[n] := HexD(o.Arrays['m'].Strings[n]);
          { the line scale of the transform the op is made under }
          sc := Sqrt(Abs(m[0] * m[3] - m[1] * m[2]));
          if isCap then
          begin
            CaptionInk(el, pf, ps, plw);
            if (op = 'fillText') and TyTryParseChartColor(o.Strings['fs'], wc) then
            begin
              Inc(FCompared);
              if not SameInk(pf, wc) then
                Miss(Format('%s: text fill %x, upstream %s', [where, pf, o.Strings['fs']]));
            end;
            if (op = 'strokeText') and TyTryParseChartColor(o.Strings['ss'], wc) then
            begin
              Inc(FCompared);
              if not SameInk(ps, wc) or (Abs(plw - HexD(o.Strings['lw']) * sc) > 1e-6) then
                Miss(Format('%s: text stroke %x width %g, upstream %s width %g', [where, ps, plw,
                  o.Strings['ss'], HexD(o.Strings['lw']) * sc]));
            end;
            Continue;
          end;
          if op = 'fill' then
          begin
            Inc(FCompared);
            if o.Strings['fs'] = '[grad]' then
            begin
              if el.Style.FillGradient.Kind = cgkNone then
                Miss(Format('%s: fill %x, upstream a gradient', [where, el.Style.FillColor]));
            end
            else if TyTryParseChartColor(o.Strings['fs'], wc) then
            begin
              { ([R7-Z] a component's background filled with no alpha: the
                port fills none) }
              if (Copy(key, 1, 2) = 'c.') and not el.Style.HasFill and ((wc shr 24) = 0) then
              else if not el.Style.HasFill or (el.Style.FillGradient.Kind <> cgkNone)
                or not SameInk(el.Style.FillColor, wc) then
                Miss(Format('%s: fill %x (has %s), upstream %s', [where, el.Style.FillColor,
                  BoolToStr(el.Style.HasFill, True), o.Strings['fs']]));
            end;
          end
          else if op = 'stroke' then
          begin
            Inc(FCompared);
            lw := HexD(o.Strings['lw']) * sc;
            plw := el.Style.StrokeWidthLogical;
            if (el.Style.PenScale > 0) and (el.Style.PenScale <> 1) then plw := plw * el.Style.PenScale;
            if not (el.Style.StrokeWidthLogical > 0) or (Abs(plw - lw) > 1e-6) then
              Miss(Format('%s: stroke width %g, upstream %g', [where, plw, lw]));
            if (o.Strings['ss'] <> '[grad]') and TyTryParseChartColor(o.Strings['ss'], wc) then
            begin
              Inc(FCompared);
              if (el.Style.StrokeGradient.Kind <> cgkNone) or not SameInk(el.Style.StrokeColor, wc) then
                Miss(Format('%s: stroke %x, upstream %s', [where, el.Style.StrokeColor, o.Strings['ss']]));
            end;
            { the dash and its phase }
            ld := o.Arrays['ld'];
            pdash := el.Style.DashLogical;
            if el.Style.DashWord <> 0 then
              pdash := TyDashOfWord(el.Style.DashWord, el.Style.StrokeWidthLogical);
            Inc(FCompared);
            { ([R7-Z] the z- cases: a dash where upstream strokes solid too) }
            if (APrefix = 'z-') and (ld.Count = 0) and (Length(pdash) > 0) then
              Miss(Format('%s: dash of %d, upstream solid', [where, Length(pdash)]))
            else if Length(pdash) * Ord(ld.Count > 0) <> ld.Count then
              Miss(Format('%s: dash of %d, upstream %s', [where, Length(pdash), ld.AsJSON]))
            else if ld.Count > 0 then
            begin
              for n := 0 to ld.Count - 1 do
                if Abs(pdash[n] - HexD(ld.Strings[n]) * sc) > 1e-6 then
                begin
                  Miss(Format('%s: dash %g at %d, upstream %g', [where, pdash[n], n,
                    HexD(ld.Strings[n]) * sc]));
                  Break;
                end;
              ldo := HexD(o.Strings['ldo']) * sc;
              pldo := el.Style.DashOffsetLogical;
              if IsNan(pldo) then pldo := -1e300;
              Inc(FCompared);
              if Abs(pldo - ldo) > 1e-6 then
                Miss(Format('%s: dash phase %g, upstream %g', [where, pldo, ldo]));
            end;
            { [R7-Z] the cap (a word the canvas refuses: the one it had) }
            if APrefix = 'z-' then
            begin
              Inc(FCompared);
              case el.Style.LineCap of
                1: want := 'round';
                2: want := 'square';
              else
                want := 'butt';
              end;
              if want <> o.Strings['cap'] then
                Miss(Format('%s: cap %s, upstream %s', [where, want, o.Strings['cap']]));
              { and the miterLimit (one the canvas refuses: the one it had) }
              lw := el.Style.MiterLimit;
              if not (lw > 0) then lw := 10;
              Inc(FCompared);
              if Abs(lw - HexD(o.Strings['ml'])) > 1e-9 then
                Miss(Format('%s: miterLimit %g, upstream %g', [where, lw, HexD(o.Strings['ml'])]));
            end;
          end;
          { the shadow it casts (a refused blur or colour kept) }
          sb := HexD(o.Strings['sb']);
          if TyTryParseChartColor(o.Strings['sc'], wc) and (sb > 0) and ((wc shr 24) <> 0) then
          begin
            Inc(FCompared);
            if not TyStyleHasShadow(el.Style) or (el.Style.ShadowColor <> wc)
              or (Abs(el.Style.ShadowBlur - sb) > 1e-9) then
              Miss(Format('%s: shadow %x blur %g, want %s blur %g', [where,
                el.Style.ShadowColor, el.Style.ShadowBlur, o.Strings['sc'], sb]));
          end
          else if (sb = 0) and (HexD(o.Strings['sox']) = 0) and (HexD(o.Strings['soy']) = 0) then
          begin
            Inc(FCompared);
            if TyStyleHasShadow(el.Style) then
              Miss(Format('%s: a shadow in %x blur %g, upstream casts none', [where,
                el.Style.ShadowColor, el.Style.ShadowBlur]));
          end;
        end;
        { AN EFFECT SYMBOL'S TRANSFORM no number: the unit symbol under the
          one the canvas had, at the path's bounds }
        if (key[1] = 'e') and (rec.Find('sy').JSONType = jtNull)
          and (rec.Find('pb').JSONType <> jtNull) then
        begin
          mb := TyRectF(HexD(rec.Arrays['pb'].Strings[0]), HexD(rec.Arrays['pb'].Strings[1]),
            HexD(rec.Arrays['pb'].Strings[2]), HexD(rec.Arrays['pb'].Strings[3]));
          bb := TyShapeBounds(el.Shape);
          Inc(FCompared);
          if not TyRectFIsValid(bb) or (Abs(bb.Left - mb.Left) > 1e-4) or (Abs(bb.Right - mb.Right) > 1e-4)
            or (Abs(bb.Top - mb.Top) > 1e-4) or (Abs(bb.Bottom - mb.Bottom) > 1e-4) then
            Miss(Format('%s: drawn at (%g,%g)-(%g,%g), want (%g,%g)-(%g,%g)', [where,
              bb.Left, bb.Top, bb.Right, bb.Bottom, mb.Left, mb.Top, mb.Right, mb.Bottom]));
        end;
        { A BAR'S BOX (a width of 'Infinity' takes its layout too) }
        if (key[1] = 'b') and (rec.Find('pb').JSONType <> jtNull) then
        begin
          mb := TyRectF(HexD(rec.Arrays['pb'].Strings[0]), HexD(rec.Arrays['pb'].Strings[1]),
            HexD(rec.Arrays['pb'].Strings[2]), HexD(rec.Arrays['pb'].Strings[3]));
          bb := TyShapeBounds(el.Shape);
          Inc(FCompared);
          if not TyRectFIsValid(bb) or (Abs(bb.Left - mb.Left) > 1e-6) or (Abs(bb.Right - mb.Right) > 1e-6)
            or (Abs(bb.Top - mb.Top) > 1e-6) or (Abs(bb.Bottom - mb.Bottom) > 1e-6) then
            Miss(Format('%s: box (%g,%g)-(%g,%g), upstream (%g,%g)-(%g,%g)', [where,
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

{ [R7-Y] whether a pixel is AWant over white: the ink it shows (white less
  the pixel) the wanted ink's direction, at least AMin of it (the painter
  blends in its own light, so the coverage is not one number per channel);
  AWant of no alpha: white }
function InkOver(const APx: TBGRAPixel; AWant: TTyChartColor; AMin: Double;
  ACos: Double = 0.98): Boolean;
var p, w: array[0..2] of Double; n: Integer; dot, pp, ww: Double;
begin
  if (AWant shr 24) = 0 then
    Exit((APx.red >= 247) and (APx.green >= 247) and (APx.blue >= 247));
  p[0] := 255 - APx.red;
  p[1] := 255 - APx.green;
  p[2] := 255 - APx.blue;
  for n := 0 to 2 do w[n] := 255 - ((AWant shr (16 - 8 * n)) and $FF);
  dot := 0;
  pp := 0;
  ww := 0;
  for n := 0 to 2 do
  begin
    dot := dot + p[n] * w[n];
    pp := pp + p[n] * p[n];
    ww := ww + w[n] * w[n];
  end;
  Result := (Sqrt(pp) >= AMin) and (ww > 0) and (dot / Sqrt(pp * ww) >= ACos);
end;

function RectOfHex(AData: TJSONData; out AR: TTyRectF): Boolean;
var a: TJSONArray;
begin
  Result := (AData <> nil) and (AData.JSONType = jtArray);
  if not Result then Exit;
  a := TJSONArray(AData);
  AR := TyRectF(HexD(a.Strings[0]), HexD(a.Strings[1]),
    HexD(a.Strings[0]) + HexD(a.Strings[2]), HexD(a.Strings[1]) + HexD(a.Strings[3]));
end;

procedure TAdvChartLinesCanvasOracleTest.RunY(const APrefix: string);
var
  cs, frames, els, yops, paints: TJSONArray;
  c, fr, rec, o: TJSONObject;
  i, j, k, q, n, p, b, jj, got: Integer;
  id, key, where: string;
  t, cx, cy, r, x, y, d, best, dd, dy: Double;
  wc: TTyChartColor;
  px: TBGRAPixel;
  blkR, rr: TTyRectF;
  ever: array of TTyRectF;
  effs: array of TTyPointF;
  effr: array of Double;
  ok: Boolean;

  procedure EffectsOf(AEls: TJSONArray);
  var k2: Integer; o2: TJSONObject; a: TJSONArray;
  begin
    effs := nil;
    effr := nil;
    for k2 := 0 to AEls.Count - 1 do
    begin
      if AEls.Objects[k2].Strings['key'][1] <> 'e' then Continue;
      a := AEls.Objects[k2].Arrays['yops'];
      if a.Count = 0 then Continue;
      o2 := a.Objects[a.Count - 1];
      SetLength(effs, Length(effs) + 1);
      SetLength(effr, Length(effr) + 1);
      effs[High(effs)] := TyPointF(HexD(o2.Arrays['m'].Strings[4]), HexD(o2.Arrays['m'].Strings[5]));
      effr[High(effr)] := Sqrt(Abs(HexD(o2.Arrays['m'].Strings[0]) * HexD(o2.Arrays['m'].Strings[3])
        - HexD(o2.Arrays['m'].Strings[1]) * HexD(o2.Arrays['m'].Strings[2]))) / 2;
    end;
  end;

  { clear of every effect symbol by AGap }
  function ClearOfEffects(AX, AY, AGap: Double): Boolean;
  var k2: Integer;
  begin
    Result := True;
    for k2 := 0 to High(effs) do
      if Sqrt(Sqr(AX - effs[k2].X) + Sqr(AY - effs[k2].Y)) < effr[k2] + AGap then Exit(False);
  end;

  function Probe(AX, AY: Double; AWant: TTyChartColor; AMin: Double; const AWhat: string;
    ACos: Double = 0.98): Boolean;
  begin
    Inc(FCompared);
    px := FBmp.GetPixel(Trunc(AX), Trunc(AY));
    Result := InkOver(px, AWant, AMin, ACos);
    if not Result then
      Miss(Format('%s: (%d,%d,%d) at (%g,%g), upstream %s', [AWhat, px.red, px.green, px.blue,
        AX, AY, '#' + IntToHex(AWant, 8)]));
  end;

begin
  FBad := 0;
  FCompared := 0;
  FReport := '';
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if (Copy(id, 1, Length(APrefix)) <> APrefix) or (c.Find('dirty') = nil) then Continue;
    if GetEnvironmentVariable('TY_LC_TRACE') <> '' then WriteLn('case ', id);
    FreeAndNil(FChart);
    FChart := TLcProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := cT0;
    FChart.UseDirtyRect := True;
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    AssertEquals(id + ' parses', '', FChart.OptionError);
    FBmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Layered(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
    frames := c.Arrays['frames'];
    ever := nil;
    for j := 0 to frames.Count - 1 do
    begin
      fr := frames.Objects[j];
      t := fr.Floats['t'];
      if t > 0 then FChart.AnimTick(cT0 + t);
      FChart.Layered(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
      if GetEnvironmentVariable('TY_LC_SAVE') <> '' then
        FBmp.SaveToFile(GetEnvironmentVariable('TY_LC_SAVE') + id + '-' + IntToStr(j) + '.png');
      paints := fr.Arrays['paints'];
      { every block repainted so far }
      for p := 0 to paints.Count - 1 do
        for b := 0 to paints.Arrays[p].Count - 1 do
          if RectOfHex(paints.Arrays[p].Items[b], rr) then
          begin
            SetLength(ever, Length(ever) + 1);
            ever[High(ever)] := rr;
          end;
      { (the first sample's last paints are setOption's own flush's leftovers) }
      if j = 0 then Continue;
      els := fr.Arrays['els'];
      EffectsOf(els);
      for k := 0 to els.Count - 1 do
      begin
        rec := els.Objects[k];
        key := rec.Strings['key'];
        yops := rec.Arrays['yops'];
        where := Format('%s t=%g %s', [id, t, key]);
        { WHAT A BLOCK BRUSHED LAST, in it: an effect symbol's shadow just
          off its edge, a scatter's fill inside it }
        if yops.Count > 0 then
        begin
          o := yops.Objects[yops.Count - 1];
          if not RectOfHex(paints.Arrays[o.Integers['p']].Items[o.Integers['b']], blkR) then
            blkR := TyRectF(0, 0, FBmp.Width, FBmp.Height);
          cx := HexD(o.Arrays['m'].Strings[4]);
          cy := HexD(o.Arrays['m'].Strings[5]);
          r := Sqrt(Abs(HexD(o.Arrays['m'].Strings[0]) * HexD(o.Arrays['m'].Strings[3])
            - HexD(o.Arrays['m'].Strings[1]) * HexD(o.Arrays['m'].Strings[2])));
          if key[1] = 'e' then
          begin
            r := r / 2;
            { above or below: away from the other symbols }
            dy := -(r + 1.5);
            best := -1;
            for q := 0 to 1 do
            begin
              d := (r + 1.5) * (2 * q - 1);
              dd := 1e9;
              for n := 0 to High(effs) do
                if (Abs(effs[n].X - cx) > 1e-9) or (Abs(effs[n].Y - cy) > 1e-9) then
                  dd := Min(dd, Sqrt(Sqr(effs[n].X - cx) + Sqr(effs[n].Y - cy - d)));
              if dd > best then
              begin
                best := dd;
                dy := d;
              end;
            end;
            { (no blur, no shadow to look at) }
            if not (HexD(o.Strings['sb']) > 0) then Continue;
            if not TyTryParseChartColor(o.Strings['sc'], wc) then Continue;
            Probe(cx, cy + dy, wc, 10, where + ' shadow');
          end
          else if (key[1] = 's') and (o.Strings['op'] = 'fill')
            and TyTryParseChartColor(o.Strings['fs'], wc) and (rec.Find('pb') <> nil) then
          begin
            { points of the block inside the symbol, clear of the moving ones }
            got := 0;
            y := blkR.Top + 1.5;
            while (y <= blkR.Bottom - 1.5) and (got < 6) do
            begin
              x := blkR.Left + 1.5;
              while (x <= blkR.Right - 1.5) and (got < 6) do
              begin
                if (Sqrt(Sqr(x - cx) + Sqr(y - cy)) <= r - 1.5) and ClearOfEffects(x, y, 2.5) then
                begin
                  { (tighter: an old picture showing through tints it) }
                  Probe(x, y, wc, 40, where + ' fill in its block', 0.998);
                  Inc(got);
                end;
                x := x + 2;
              end;
              y := y + 2;
            end;
            { and away from every block so far: the whole paint's }
            for jj := 0 to frames.Objects[0].Arrays['els'].Count - 1 do
              if frames.Objects[0].Arrays['els'].Objects[jj].Strings['key'] = key then
              begin
                o := frames.Objects[0].Arrays['els'].Objects[jj].Arrays['yops'].Objects[0];
                if not TyTryParseChartColor(o.Strings['fs'], wc) then Break;
                got := 0;
                y := cy - r;
                while (y <= cy + r) and (got < 4) do
                begin
                  x := cx - r;
                  while (x <= cx + r) and (got < 4) do
                  begin
                    ok := (Sqrt(Sqr(x - cx) + Sqr(y - cy)) <= r - 1.5) and ClearOfEffects(x, y, 2.5);
                    for n := 0 to High(ever) do
                      if ok and (x > ever[n].Left - 4) and (x < ever[n].Right + 4)
                        and (y > ever[n].Top - 4) and (y < ever[n].Bottom + 4) then ok := False;
                    if ok then
                    begin
                      Probe(x, y, wc, 40, where + ' fill outside the blocks');
                      Inc(got);
                    end;
                    x := x + 3;
                  end;
                  y := y + 3;
                end;
                Break;
              end;
          end;
        end;
      end;
    end;
  end;
  FreeAndNil(FChart);
  if FBad > 0 then
    Fail(Format('%d of %d differ:%s', [FBad, FCompared, FReport]));
  AssertTrue('compared', FCompared > 10);
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheDirtyFramesAsUpstream;
begin
  RunY;
end;

{ [R7-Y] the y- cases drawn whole: each fill / stroke made with a pattern or
  a gradient, upstream's in device px (the op's transform times the
  CanvasPattern's matrix, or times the CanvasGradient's points) against
  what the port's element holds once the paint order settled it }
{ [R7-Y] a canvas font's size (px), weight (400 for none) and family }
procedure FontOfCss(const AFont: string; out APx: Double; out AWeight: Integer;
  out AFamily: string);
var t: TStringList; k, p: Integer; w: string; v: Double; fs: TFormatSettings;
begin
  APx := 0;
  AWeight := 400;
  AFamily := '';
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  t := TStringList.Create;
  try
    t.Delimiter := ' ';
    t.StrictDelimiter := True;
    t.DelimitedText := Trim(AFont);
    for k := 0 to t.Count - 1 do
    begin
      w := LowerCase(t[k]);
      p := Pos('px', w);
      if (p > 0) and TryStrToFloat(Copy(w, 1, p - 1), v, fs) then
      begin
        APx := v;
        for p := k + 1 to t.Count - 1 do
        begin
          if AFamily <> '' then AFamily := AFamily + ' ';
          AFamily := AFamily + t[p];
        end;
        Exit;
      end;
      if (w = 'bold') or (w = 'bolder') then AWeight := 700
      else if TryStrToFloat(w, v, fs) then AWeight := Round(v);
    end;
  finally
    t.Free;
  end;
end;

procedure TAdvChartLinesCanvasOracleTest.RunYHeld(const APrefix: string);
var
  cs, els, yops, a: TJSONArray;
  c, rec, o, ob: TJSONObject;
  i, k, q, n, idx: Integer;
  id, key, where, kind, tag: string;
  m: array[0..5] of Double;
  u, u2: array[0..5] of Double;
  pm: TTyDoubleArray;
  em: TTyMat2D;
  el: TTyChartElement;
  grad: TTyChartGradient;
  x1, y1, x2, y2, gr, ux1, uy1, ux2, uy2, ur: Double;
  fill: Boolean;
  wc: TTyChartColor;
  j, q2, j2: Integer;
  t: Double;
  bb: TTyRectF;
  px: TBGRAPixel;
begin
  FBad := 0;
  FCompared := 0;
  FReport := '';
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if (Copy(id, 1, Length(APrefix)) <> APrefix) or (c.Find('dirty') <> nil) then Continue;
    { (the case's kind after its prefix: 'y-fill-...' and 'ab-fill-...' alike) }
    tag := 'y-' + Copy(id, Length(APrefix) + 1, MaxInt);
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
    for j := 0 to c.Arrays['frames'].Count - 1 do
    begin
    t := c.Arrays['frames'].Objects[j].Floats['t'];
    if t > 0 then FChart.AnimTick(cT0 + t);
    FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
    { findHover at the probes }
    if c.Arrays['frames'].Objects[j].Find('hits') <> nil then
    begin
      a := c.Arrays['frames'].Objects[j].Arrays['hits'];
      for k := 0 to a.Count - 1 do
      begin
        if a.Arrays[k].Items[2].JSONType = jtNull then kind := '-' else kind := a.Arrays[k].Strings[2];
        idx := FChart.Frame.HitTestElement(HexD(a.Arrays[k].Strings[0]), HexD(a.Arrays[k].Strings[1]), 96, False);
        if idx < 0 then key := '-' else key := KeyOfEl(idx, False);
        Inc(FCompared);
        if key <> kind then
          Miss(Format('%s t=%g (%.17g,%.17g): hit %s, upstream %s', [id, t,
            HexD(a.Arrays[k].Strings[0]), HexD(a.Arrays[k].Strings[1]), key, kind]));
      end;
    end;
    els := c.Arrays['frames'].Objects[j].Arrays['els'];
    for k := 0 to els.Count - 1 do
    begin
      rec := els.Objects[k];
      key := rec.Strings['key'];
      yops := rec.Arrays['yops'];
      { AN EFFECT SYMBOL'S TRANSFORM no number: the unit symbol under the one
        the canvas had (an end symbol's in the line's enter animation), at
        the path's bounds }
      if (key[1] = 'e') and (rec.Find('sy').JSONType = jtNull)
        and (rec.Find('pb').JSONType <> jtNull) then
      begin
        idx := WElOf(key, rec);
        Inc(FCompared);
        if idx < 0 then Miss(Format('%s t=%g %s: no element', [id, t, key]))
        else
        begin
          bb := TyShapeBounds(FChart.Frame.Element(idx).Shape);
          if not TyRectFIsValid(bb) or (Abs(bb.Left - HexD(rec.Arrays['pb'].Strings[0])) > 1e-4)
            or (Abs(bb.Top - HexD(rec.Arrays['pb'].Strings[1])) > 1e-4)
            or (Abs(bb.Right - HexD(rec.Arrays['pb'].Strings[2])) > 1e-4)
            or (Abs(bb.Bottom - HexD(rec.Arrays['pb'].Strings[3])) > 1e-4) then
            Miss(Format('%s t=%g %s: drawn at (%g,%g)-(%g,%g), upstream (%g,%g)-(%g,%g)', [id, t, key,
              bb.Left, bb.Top, bb.Right, bb.Bottom, HexD(rec.Arrays['pb'].Strings[0]),
              HexD(rec.Arrays['pb'].Strings[1]), HexD(rec.Arrays['pb'].Strings[2]),
              HexD(rec.Arrays['pb'].Strings[3])]));
        end;
      end;
      for q := 0 to yops.Count - 1 do
      begin
        o := yops.Objects[q];
        fill := o.Strings['op'] = 'fill';
        { A FILL'S COLOUR (an image before it sets none) }
        if (Copy(tag, 1, 7) = 'y-fill-') and (o.Strings['op'] = 'fill') then
        begin
          where := Format('%s %s fill', [id, key]);
          if Copy(key, 1, 2) = 'gr' then idx := GraphicOf(rec) else idx := WElOf(key, rec);
          if idx < 0 then
          begin
            Miss(where + ': no element');
            Continue;
          end;
          el := FChart.Frame.Element(idx);
          Inc(FCompared);
          if not TyTryParseChartColor(o.Strings['fs'], wc) or not el.Style.HasFill
            or el.Style.FillPattern.Present or (el.Style.FillGradient.Kind <> cgkNone)
            or not SameInk(el.Style.FillColor, wc) then
            Miss(Format('%s: fill %x (pattern %s), upstream %s', [where, el.Style.FillColor,
              BoolToStr(el.Style.FillPattern.Present, True), o.Strings['fs']]));
          Continue;
        end;
        { A LABEL'S FONT: the size, the weight and (where not the default
          family) the family each text is drawn in }
        if (Copy(tag, 1, 6) = 'y-font') and (o.Strings['op'] = 'fillText') then
        begin
          where := Format('%s %s', [id, key]);
          idx := WElOf(key, rec);
          if idx < 0 then
          begin
            Miss(where + ': no element');
            Continue;
          end;
          el := FChart.Frame.Element(idx);
          FontOfCss(o.Strings['font'], ux1, n, kind);
          { (the port's px coding; a weight of nought is the regular one) }
          if TyFontSizeIsPx(el.Caption.FontSizeLogical) then ux2 := TyFontPxOf(el.Caption.FontSizeLogical)
          else ux2 := el.Caption.FontSizeLogical * 96 / 72;
          q2 := el.Caption.FontWeight and TyChartFontWeightMask;
          if q2 = 0 then q2 := 400;
          Inc(FCompared);
          if (Abs(ux2 - ux1) > 1e-6) or (q2 <> n)
            or ((kind <> 'Microsoft YaHei') and (el.Caption.FontName <> kind)) then
            Miss(Format('%s: font %s %gpx %d, upstream %s', [where, el.Caption.FontName,
              ux2, q2, o.Strings['font']]));
          Continue;
        end;
        { A STROKE'S COLOUR, one of no width before it among them }
        if Copy(tag, 1, 9) = 'y-stroke-' then
        begin
          if o.Strings['op'] <> 'stroke' then Continue;
          where := Format('%s %s stroke', [id, key]);
          idx := WElOf(key, rec);
          if idx < 0 then
          begin
            Miss(where + ': no element');
            Continue;
          end;
          el := FChart.Frame.Element(idx);
          Inc(FCompared);
          if not TyTryParseChartColor(o.Strings['ss'], wc) or not SameInk(el.Style.StrokeColor, wc)
            or (Abs(el.Style.StrokeWidthLogical - HexD(o.Strings['lw'])) > 1e-9) then
            Miss(Format('%s: stroke %x width %g, upstream %s width %g', [where, el.Style.StrokeColor,
              el.Style.StrokeWidthLogical, o.Strings['ss'], HexD(o.Strings['lw'])]));
          Continue;
        end;
        { THE SHADOW AND THE COMPOSITE OPERATION each op is made with }
        if (Copy(tag, 1, 5) = 'y-sh-') or (Copy(tag, 1, 7) = 'y-blend') then
        begin
          where := Format('%s %s %s', [id, key, o.Strings['op']]);
          if Copy(key, 1, 2) = 'gr' then idx := GraphicOf(rec) else idx := WElOf(key, rec);
          if idx < 0 then
          begin
            Miss(where + ': no element');
            Continue;
          end;
          el := FChart.Frame.Element(idx);
          Inc(FCompared);
          kind := el.Style.Blend;
          if kind = '' then kind := 'source-over';
          if kind <> o.Strings['gco'] then
            Miss(Format('%s: blend %s, upstream %s', [where, kind, o.Strings['gco']]));
          if (HexD(o.Strings['sb']) > 0) and TyTryParseChartColor(o.Strings['sc'], wc)
            and ((wc shr 24) <> 0) then
          begin
            Inc(FCompared);
            if not TyStyleHasShadow(el.Style) or (el.Style.ShadowColor <> wc)
              or (Abs(el.Style.ShadowBlur - HexD(o.Strings['sb'])) > 1e-9)
              or (Abs(el.Style.ShadowOffsetX - HexD(o.Strings['sox'])) > 1e-9)
              or (Abs(el.Style.ShadowOffsetY - HexD(o.Strings['soy'])) > 1e-9) then
              Miss(Format('%s: shadow %x blur %g offset (%g,%g), upstream %s blur %g offset (%g,%g)',
                [where, el.Style.ShadowColor, el.Style.ShadowBlur, el.Style.ShadowOffsetX,
                el.Style.ShadowOffsetY, o.Strings['sc'], HexD(o.Strings['sb']),
                HexD(o.Strings['sox']), HexD(o.Strings['soy'])]));
          end;
          Continue;
        end;
        if fill then
        begin
          if o.Find('fo').JSONType = jtNull then Continue;
          ob := o.Objects['fo'];
        end
        else
        begin
          if o.Find('so').JSONType = jtNull then Continue;
          ob := o.Objects['so'];
        end;
        where := Format('%s %s %s', [id, key, o.Strings['op']]);
        idx := WElOf(key, rec);
        if idx < 0 then
        begin
          Miss(where + ': no element');
          Continue;
        end;
        el := FChart.Frame.Element(idx);
        for n := 0 to 5 do m[n] := HexD(o.Arrays['m'].Strings[n]);
        kind := ob.Strings['k'];
        Inc(FCompared);
        if kind = 'pattern' then
        begin
          { upstream: the op's transform times the pattern's matrix }
          a := ob.Arrays['m'];
          u[0] := m[0] * HexD(a.Strings[0]) + m[2] * HexD(a.Strings[1]);
          u[1] := m[1] * HexD(a.Strings[0]) + m[3] * HexD(a.Strings[1]);
          u[2] := m[0] * HexD(a.Strings[2]) + m[2] * HexD(a.Strings[3]);
          u[3] := m[1] * HexD(a.Strings[2]) + m[3] * HexD(a.Strings[3]);
          u[4] := m[0] * HexD(a.Strings[4]) + m[2] * HexD(a.Strings[5]) + m[4];
          u[5] := m[1] * HexD(a.Strings[4]) + m[3] * HexD(a.Strings[5]) + m[5];
          if not el.Style.HasFill or not el.Style.FillPattern.Present then
          begin
            Miss(Format('%s: no pattern (fill %x)', [where, el.Style.FillColor]));
            Continue;
          end;
          { the port's, as the renderer takes it (css px, 96 PPI) }
          if el.Style.FillPattern.HasMatrix then
          begin
            SetLength(pm, 6);
            for n := 0 to 5 do pm[n] := el.Style.FillPattern.Matrix[n];
          end
          else
          begin
            TyPatternMatrix(el.Style.FillPattern, pm);
            { in the element's frame: a symbol's (HitM), one handed over }
            if Length(el.CanvasM) = 6 then
              for n := 0 to 5 do em[n] := el.CanvasM[n]
            else if el.Shape.HitSym <> '' then em := el.Shape.HitM
            else
            begin
              em := Default(TTyMat2D);
              em[0] := 1;
              em[3] := 1;
            end;
            for n := 0 to 5 do u2[n] := pm[n];
            pm[0] := em[0] * u2[0] + em[2] * u2[1];
            pm[1] := em[1] * u2[0] + em[3] * u2[1];
            pm[2] := em[0] * u2[2] + em[2] * u2[3];
            pm[3] := em[1] * u2[2] + em[3] * u2[3];
            pm[4] := em[0] * u2[4] + em[2] * u2[5] + em[4];
            pm[5] := em[1] * u2[4] + em[3] * u2[5] + em[5];
          end;
          for n := 0 to 5 do
            if Abs(pm[n] - u[n]) > 1e-6 then
            begin
              Miss(Format('%s: pattern [%g %g %g %g %g %g], upstream [%g %g %g %g %g %g]', [where,
                pm[0], pm[1], pm[2], pm[3], pm[4], pm[5], u[0], u[1], u[2], u[3], u[4], u[5]]));
              Break;
            end;
          { AND AS DRAWN: the middle of each texel of the 2 x 2 checker (red
            where its column and row add up even) under upstream's matrix,
            well inside the element, its colour }
          bb := TyShapeBounds(el.Shape);
          for n := -6 to 6 do
            for j2 := -6 to 6 do
            begin
              x1 := u[0] * (n + 0.5) + u[2] * (j2 + 0.5) + u[4];
              y1 := u[1] * (n + 0.5) + u[3] * (j2 + 0.5) + u[5];
              if (x1 < bb.Left + 3) or (x1 > bb.Right - 3) or (y1 < bb.Top + 3) or (y1 > bb.Bottom - 3) then
                Continue;
              px := FBmp.GetPixel(Trunc(x1), Trunc(y1));
              Inc(FCompared);
              if (((n + j2) and 1) = 0) <> (px.red > px.blue) then
                Miss(Format('%s: texel (%d,%d) at (%g,%g) drawn (%d,%d,%d)', [where, n, j2, x1, y1,
                  px.red, px.green, px.blue]));
            end;
          Continue;
        end;
        { a gradient: its points through the op's transform }
        a := ob.Arrays['a'];
        if fill then grad := el.Style.FillGradient else grad := el.Style.StrokeGradient;
        if grad.Kind = cgkNone then
        begin
          Miss(where + ': no gradient');
          Continue;
        end;
        TyResolveGradientXYWH(grad, TyElementGradientBox(el, 96), x1, y1, x2, y2, gr);
        if kind = 'linear' then
        begin
          ux1 := m[0] * HexD(a.Strings[0]) + m[2] * HexD(a.Strings[1]) + m[4];
          uy1 := m[1] * HexD(a.Strings[0]) + m[3] * HexD(a.Strings[1]) + m[5];
          ux2 := m[0] * HexD(a.Strings[2]) + m[2] * HexD(a.Strings[3]) + m[4];
          uy2 := m[1] * HexD(a.Strings[2]) + m[3] * HexD(a.Strings[3]) + m[5];
          if (grad.Kind <> cgkLinear) or (Abs(x1 - ux1) > 1e-6) or (Abs(y1 - uy1) > 1e-6)
            or (Abs(x2 - ux2) > 1e-6) or (Abs(y2 - uy2) > 1e-6) then
            Miss(Format('%s: linear (%g,%g)-(%g,%g), upstream (%g,%g)-(%g,%g)', [where,
              x1, y1, x2, y2, ux1, uy1, ux2, uy2]));
        end
        else
        begin
          { createRadialGradient(x, y, 0, x, y, r) }
          ux1 := m[0] * HexD(a.Strings[3]) + m[2] * HexD(a.Strings[4]) + m[4];
          uy1 := m[1] * HexD(a.Strings[3]) + m[3] * HexD(a.Strings[4]) + m[5];
          ur := HexD(a.Strings[5]) * Sqrt(Abs(m[0] * m[3] - m[1] * m[2]));
          if (grad.Kind <> cgkRadial) or (Abs(x1 - ux1) > 1e-6) or (Abs(y1 - uy1) > 1e-6)
            or (Abs(gr - ur) > 1e-6) then
            Miss(Format('%s: radial (%g,%g) r %g, upstream (%g,%g) r %g', [where,
              x1, y1, gr, ux1, uy1, ur]));
        end;
      end;
    end;
    end;
  end;
  FreeAndNil(FChart);
  if FBad > 0 then
    Fail(Format('%d of %d differ:%s', [FBad, FCompared, FReport]));
  AssertTrue('compared', FCompared > 8);
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheHeldPatternsAsUpstream;
begin
  RunYHeld;
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheR7ABDirtyFramesAsUpstream;
begin
  RunY('ab-');
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheR7ABCarriesAsUpstream;
begin
  RunYHeld('ab-');
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheRefusedValuesAsUpstream;
begin
  RunW(False);
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheR7WHitsAsUpstream;
begin
  RunW(True);
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheComponentsCanvasAsUpstream;
begin
  RunW(False, 'z-');
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
