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
  (the ones it had): TestTheHeldPatternsAsUpstream.

  [R7-AA] The cases named aa-..., recorded and compared as the z- ones (the
  lineJoin too, a gradient stroke as one): an axis' shadow, join and
  miterLimit on every kind of axis, the refused values of the parallel
  axes, a timeline and a dataZoom, the polar's and the single axis' split
  areas in paint order, radar's parts among the axes', a zero width that
  still hands its stroke colour, a transparent background its fill, a
  gradient axis pen, a label's refused colours in a state:
  TestTheR7AACanvasAsUpstream.

  [R7-AC] The cases named ac-..., recorded and compared as the aa- ones and
  more (the alpha of every fill and stroke, the arguments of a gradient a
  series' element is handed): a dataZoom's dashes, phases, caps, joins and
  miterLimits, its style blocks reaching the root's; a richText tooltip's
  shadow and text shadow, its colour markers, its box where upstream puts
  it; several axis pointers and their labels one after another, the
  tooltip after them; the gradient a tick or a split line hands on, over
  the last one's box; a single axis' split lines at 0.2:
  TestTheR7ACCanvasAsUpstream, TestARichTipsBorderIsOutsideItsBox.

  [R7-AE] The cases named ae-..., recorded and compared as the ac- ones and
  more (an axis pointer's handle, a text's boxes and spans one by one, an
  option set notMerge before a sample, a pointer the port draws where
  upstream has none): a dataZoom slider whose group has no place (every
  element in its own frame under the transform the canvas had, nothing of
  it found by the pointer); a polyline of one point, an area of one point,
  an end label after its line's clip; the pointers' handles among their
  lines and labels; a pointer an action showed after a notMerge setOption;
  the gradient a polar's, a single axis' and a parallel axis' line hands
  on; a text box's token backgrounds among its spans; a label's box on a
  translucent host: TestTheR7AECanvasAsUpstream, TestTheR7AEHitsAsUpstream,
  TestAnUnplacedSlidersPointerAsUpstream.

  [R7-AF] The cases named af-..., recorded and compared as the ae- ones and
  more (a text's place and alignment, a clip's path on the canvas): an
  unplaced slider's handle labels in their own frame under the transform the
  canvas had, its shadows' clips turned with it; a label's textBorderWidth
  of 'Infinity' (the width the canvas had) or a string (its number), a box's
  borderWidth as a string; a title's, a legend's and a toolbox's box of an
  infinite pen; a radar's gradient axis lines: TestTheR7AFCanvasAsUpstream,
  TestAnUnplacedSlidersLabelsAsUpstream, TestAnUnplacedSlidersTurnedClip. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes, tyControls.FontUnits,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Render, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart.Lines, tyControls.AdvanceChart.DataZoomAct, tyControls.AdvanceChart;
type
  TLcProbe = class(TTyAdvanceChart)
  public
    { [R7-Z] a component's part of key AKey, upstream's z2 AZ2 and kind (a
      text or a path) as it was drawn -- the one that fills (AOp 'fill'),
      strokes ('stroke'), else the first; False for none. [R7-AA] Of
      several that do, the one in AWant's colour (upstream's for the op):
      the port strokes a piece's lines in one batch, so two pieces of a z2
      (the split and the minor split lines) are told apart by their pen }
    function CompPart(const AKey: string; AZ2: Integer; AText: Boolean; const AOp: string;
      out AEl: TTyChartElement; const AWant: string = ''; const AWant2: string = ''): Boolean;
    { [R7-AC] the ANth part of AKey, AZ2 and kind as drawn (0 the first) }
    function CompPartNth(const AKey: string; AZ2: Integer; AText: Boolean; ANth: Integer;
      out AEl: TTyChartElement): Boolean;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { [R7-W] through the cached (dirty-rect) path }
    procedure Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
    { [R7-AC] the richText box's fill as last drawn }
    function TipFill: TTyRectF;
    { [R7-AE] the pointers' lines and bands as last drawn }
    function PtrShapes: TTyOverlayShapeArray;
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
    function CListOf(const ARec: TJSONObject; AText: Boolean; AZ2: Integer = MaxInt): Integer;
    procedure RunW(AHits: Boolean; const APrefix: string = 'w-');
    procedure KPiece(const AWhere: string; const ARec: TJSONObject; const AKey: string);
    procedure GradMiss(const AWhere: string; const AEl: TTyChartElement; AFill: Boolean;
      AOp: TJSONObject);
    procedure CheckAreas(const AWhere: string; AEls: TJSONArray);
    procedure RunY(const APrefix: string = 'y-');
    procedure RunYHeld(const APrefix: string = 'y-');
    procedure RunYTexelsAt(APPI: Integer);
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
    { [R7-AB] a pattern drawn (its own, one held) at another PPI }
    procedure TestTheHeldPatternsAtAnotherPPIAsUpstream;
    procedure TestTheR7AACanvasAsUpstream;
    procedure TestTheR7ACCanvasAsUpstream;
    procedure TestTheR7AECanvasAsUpstream;
    procedure TestTheR7AEHitsAsUpstream;
    procedure TestTheR7AFCanvasAsUpstream;
    procedure TestTheR7AFHitsAsUpstream;
    procedure TestAnUnplacedSlidersLabelsAsUpstream;
    procedure TestAnUnplacedSlidersTurnedClip;
    procedure TestAnInfiniteHaloHandsItsColourAtOnce;
    procedure TestTheRadarRingsShareTheirGradient;
    procedure TestAnUnplacedSlidersPointerAsUpstream;
    procedure TestALabelBoxOnATranslucentHostAsUpstream;
    procedure TestADzWidthOfNoNumberStrokesNothing;
    procedure TestALonePointDrawsNothing;
    procedure TestAnUnplacedSlidersPixelsAsUpstream;
    procedure TestARichTipsBorderIsOutsideItsBox;
    procedure TestATipsTextShadowIsDrawn;
    procedure TestALabelBoxsRefusedColoursAreTheCanvas;
    procedure TestARichTipsRefusedMarkerIsDrawn;
    procedure TestAnAxisPensShadowIsDrawn;
    procedure TestThePolarViewsInUpstreamsOrder;
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
  const AOp: string; out AEl: TTyChartElement; const AWant, AWant2: string): Boolean;
var
  d: TTyCompPartArray;
  k, first, opAny, opCol, opBoth: Integer;
  wc, wc2, c: TTyChartColor;
  want, want2: Boolean;
begin
  d := CompDrawn;
  first := -1;
  opAny := -1;
  opCol := -1;
  opBoth := -1;
  want := (AWant <> '') and TyTryParseChartColor(AWant, wc);
  { [R7-AA] a fill's stroke colour too (two merged paths of a z2 fill
    alike, '#000') }
  want2 := (AWant2 <> '') and TyTryParseChartColor(AWant2, wc2);
  for k := 0 to High(d) do
    if (d[k].Key = AKey) and (d[k].Z2 = AZ2) and (d[k].IsText = AText) then
    begin
      if first < 0 then first := k;
      if not (((AOp = 'fill') and d[k].El.Style.HasFill)
        or ((AOp = 'stroke') and (d[k].El.Style.StrokeWidthLogical > 0))) then Continue;
      if opAny < 0 then opAny := k;
      if not want then Continue;
      if AOp = 'fill' then c := d[k].El.Style.FillColor else c := d[k].El.Style.StrokeColor;
      if not ((c = wc) or (((c shr 24) = 0) and ((wc shr 24) = 0))) then Continue;
      if opCol < 0 then opCol := k;
      if want2 and (d[k].El.Style.StrokeColor = wc2) and (opBoth < 0) then opBoth := k;
    end;
  if opBoth >= 0 then k := opBoth
  else if opCol >= 0 then k := opCol
  else k := opAny;
  if k >= 0 then
  begin
    AEl := d[k].El;
    Exit(True);
  end;
  Result := first >= 0;
  if Result then AEl := d[first].El else AEl := Default(TTyChartElement);
end;

function TLcProbe.CompPartNth(const AKey: string; AZ2: Integer; AText: Boolean;
  ANth: Integer; out AEl: TTyChartElement): Boolean;
var d: TTyCompPartArray; k, n: Integer;
begin
  d := CompDrawn;
  n := 0;
  for k := 0 to High(d) do
    if (d[k].Key = AKey) and (d[k].Z2 = AZ2) and (d[k].IsText = AText) then
    begin
      if n = ANth then
      begin
        AEl := d[k].El;
        Exit(True);
      end;
      Inc(n);
    end;
  AEl := Default(TTyChartElement);
  Result := False;
end;

function TLcProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
  if Result = nil then Result := SeriesList;
end;

function TLcProbe.TipFill: TTyRectF;
begin
  Result := TooltipFillBox;
end;

function TLcProbe.PtrShapes: TTyOverlayShapeArray;
begin
  Result := PointerShapesDrawn;
end;

procedure FontOfCss(const AFont: string; out APx: Double; out AWeight: Integer;
  out AFamily: string); forward;

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
      or (Copy(id, 1, 2) = 'y-')
      or (Copy(id, 1, 3) = 'aa-') or (Copy(id, 1, 3) = 'ac-') or (Copy(id, 1, 3) = 'ae-')
      or (Copy(id, 1, 3) = 'af-') then Continue;
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

{ the colours a canvas holds alike: the same, or both of no alpha }
function SameInkL(A, B: TTyChartColor): Boolean;
begin
  Result := (A = B) or (((A shr 24) = 0) and ((B shr 24) = 0));
end;

{ [R7-Z] a component's displayable that is in the port's list (a legend's,
  a toolbox's...): a text by its words, a path by its bounds; -2 for a
  background that paints nothing (a fill of no alpha: the port builds none),
  -1 for none }
function TAdvChartLinesCanvasOracleTest.CListOf(const ARec: TJSONObject; AText: Boolean;
  AZ2: Integer): Integer;
var
  L: TTyPaintList;
  best, dist: Double;
  k, q, n: Integer;
  el: TTyChartElement;
  bb: TTyRectF;
  pb, ops: TJSONArray;
  wc: TTyChartColor;
  s: string;
  { [R7-AF] a clip's ring and its box }
  ring: TJSONArray;
  rx0, ry0, rx1, ry1, v: Double;
begin
  Result := -1;
  L := FChart.Frame;
  if AText then
  begin
    if ARec.Find('tx') = nil then Exit;
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      { ([R7-AA] a graphic's or a timeline's text: its pieces, at no caption
        size of its own) }
      if (el.Caption.FontSizeLogical = 0)
        and ((el.Caption.Text = '') or (Length(el.Caption.RtPieces) = 0)) then Continue;
      s := el.Caption.Text;
      if (s = '') and (Length(el.Caption.RtPieces) > 0) then
        for q := 0 to High(el.Caption.RtPieces) do s := s + el.Caption.RtPieces[q].Text;
      if s = ARec.Strings['tx'] then Exit(k);
    end;
    Exit;
  end;
  { ([R7-AA] a plate that only fills with no alpha -- a hit area, a
    transparent background: what it hands on is held by the elements after
    it; the port builds some of them, not all: none matched) }
  ops := ARec.Arrays['ops'];
  n := 0;
  for q := 0 to ops.Count - 1 do
    if (ops.Objects[q].Strings['op'] <> 'fill')
      or not TyTryParseChartColor(ops.Objects[q].Strings['fs'], wc) or ((wc shr 24) <> 0) then
      Inc(n);
  if n = 0 then Exit(-2);
  if ARec.Find('pb').JSONType <> jtNull then
  begin
    pb := ARec.Arrays['pb'];
    { ([R7-AA] the nearest within the tolerance: a frame half a pixel in
      from the background it lies on [was: the first]) }
    best := 1e9;
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      if el.Caption.FontSizeLogical <> 0 then Continue;
      { ([R7-AA] one its clip culls is never brushed: no ops upstream) }
      if el.HasClip and ((el.ClipRect.Right - el.ClipRect.Left = 0)
        or (el.ClipRect.Bottom - el.ClipRect.Top = 0)) then Continue;
      bb := TyShapeBounds(el.Shape);
      if not TyRectFIsValid(bb) then Continue;
      if (Abs(bb.Left - HexD(pb.Strings[0])) < 0.6) and (Abs(bb.Top - HexD(pb.Strings[1])) < 0.6)
        and (Abs(bb.Right - HexD(pb.Strings[2])) < 0.6) and (Abs(bb.Bottom - HexD(pb.Strings[3])) < 0.6) then
      begin
        dist := Abs(bb.Left - HexD(pb.Strings[0])) + Abs(bb.Top - HexD(pb.Strings[1]))
          + Abs(bb.Right - HexD(pb.Strings[2])) + Abs(bb.Bottom - HexD(pb.Strings[3]));
        { (of two at one place, the one of upstream's z2: a dataZoom's
          background and its filler over a full window) }
        if (AZ2 <> MaxInt) and (el.Z2 <> AZ2) then dist := dist + 0.01;
        { ([R7-AC] and of those, the one in the colour of the record's
          first op: a dataZoom's shadow of the window and the ones beside
          it lie over one another) }
        if (ops.Count > 0) and (Copy(ARec.Strings['key'], 1, 4) = 'c.da') then
        begin
          if ops.Objects[0].Strings['op'] = 'fill' then
          begin
            if TyTryParseChartColor(ops.Objects[0].Strings['fs'], wc)
              and not (el.Style.HasFill and SameInkL(el.Style.FillColor, wc)) then dist := dist + 0.005;
          end
          else if TyTryParseChartColor(ops.Objects[0].Strings['ss'], wc)
            and not SameInkL(el.Style.StrokeColor, wc) then dist := dist + 0.005;
          { ([R7-AF] and of those, the one whose clip's box is the box of the
            record's ring: the shadows on either side of the window are
            alike in colour and bounds) }
          if (ARec.Find('clp') <> nil) and (ARec.Find('clp').JSONType = jtArray) then
          begin
            ring := ARec.Arrays['clp'].Arrays[ARec.Arrays['clp'].Count - 1];
            rx0 := 1e300;
            ry0 := 1e300;
            rx1 := -1e300;
            ry1 := -1e300;
            for q := 0 to ring.Count - 1 do
            begin
              v := HexD(ring.Arrays[q].Strings[0]);
              rx0 := Min(rx0, v);
              rx1 := Max(rx1, v);
              v := HexD(ring.Arrays[q].Strings[1]);
              ry0 := Min(ry0, v);
              ry1 := Max(ry1, v);
            end;
            if not el.HasClip or (Abs(el.ClipRect.Left - rx0) > 1e-6) or (Abs(el.ClipRect.Top - ry0) > 1e-6)
              or (Abs(el.ClipRect.Right - rx1) > 1e-6) or (Abs(el.ClipRect.Bottom - ry1) > 1e-6) then
              dist := dist + 0.002;
          end;
        end;
        if dist < best then
        begin
          best := dist;
          Result := k;
        end;
      end;
    end;
    if Result >= 0 then Exit;
  end;
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

{ [R7-AC] a gradient an op is made with (the record's fo / so: k 'linear'
  or 'radial' and the arguments, in the frame of the element that made it)
  against the element's own as the renderer resolves it, its points
  through the op's transform }
procedure TAdvChartLinesCanvasOracleTest.GradMiss(const AWhere: string;
  const AEl: TTyChartElement; AFill: Boolean; AOp: TJSONObject);
var
  ob: TJSONObject;
  a: TJSONArray;
  d: TJSONData;
  grad: TTyChartGradient;
  m: array[0..5] of Double;
  x1, y1, x2, y2, gr, ux1, uy1, ux2, uy2, ur: Double;
  n: Integer;
begin
  if AFill then d := AOp.Find('fo') else d := AOp.Find('so');
  if (d = nil) or (d.JSONType <> jtObject) then Exit;
  ob := TJSONObject(d);
  if (ob.Strings['k'] <> 'linear') and (ob.Strings['k'] <> 'radial') then Exit;
  for n := 0 to 5 do m[n] := HexD(AOp.Arrays['m'].Strings[n]);
  a := ob.Arrays['a'];
  if AFill then grad := AEl.Style.FillGradient else grad := AEl.Style.StrokeGradient;
  Inc(FCompared);
  if grad.Kind = cgkNone then
  begin
    Miss(AWhere + ': no gradient, upstream one');
    Exit;
  end;
  TyResolveGradientXYWH(grad, TyElementGradientBox(AEl, 96), x1, y1, x2, y2, gr);
  if ob.Strings['k'] = 'linear' then
  begin
    ux1 := m[0] * HexD(a.Strings[0]) + m[2] * HexD(a.Strings[1]) + m[4];
    uy1 := m[1] * HexD(a.Strings[0]) + m[3] * HexD(a.Strings[1]) + m[5];
    ux2 := m[0] * HexD(a.Strings[2]) + m[2] * HexD(a.Strings[3]) + m[4];
    uy2 := m[1] * HexD(a.Strings[2]) + m[3] * HexD(a.Strings[3]) + m[5];
    if (grad.Kind <> cgkLinear) or (Abs(x1 - ux1) > 1e-6) or (Abs(y1 - uy1) > 1e-6)
      or (Abs(x2 - ux2) > 1e-6) or (Abs(y2 - uy2) > 1e-6) then
      Miss(Format('%s: linear (%g,%g)-(%g,%g), upstream (%g,%g)-(%g,%g)', [AWhere,
        x1, y1, x2, y2, ux1, uy1, ux2, uy2]));
  end
  else
  begin
    ux1 := m[0] * HexD(a.Strings[3]) + m[2] * HexD(a.Strings[4]) + m[4];
    uy1 := m[1] * HexD(a.Strings[3]) + m[3] * HexD(a.Strings[4]) + m[5];
    ur := HexD(a.Strings[5]) * Sqrt(Abs(m[0] * m[3] - m[1] * m[2]));
    if (grad.Kind <> cgkRadial) or (Abs(x1 - ux1) > 1e-6) or (Abs(y1 - uy1) > 1e-6)
      or (Abs(gr - ur) > 1e-6) then
      Miss(Format('%s: radial (%g,%g) r %g, upstream (%g,%g) r %g', [AWhere,
        x1, y1, gr, ux1, uy1, ur]));
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
  i, j, k, idx, q, n, q2: Integer;
  id, key, where, got, want, op: string;
  t, x, y, ga, sc, lw, plw, ldo, pldo, sb: Double;
  el: TTyChartElement;
  wc, pf, ps: TTyChartColor;
  m: array[0..5] of Double;
  bb, mb: TTyRectF;
  pdash: TTyDoubleArray;
  isCap, dirty: Boolean;
  px: TBGRAPixel;
  { [R7-AA] the z- and aa- cases: the cap, join and miterLimit, a dash
    where upstream strokes solid }
  strict: Boolean;
  { [R7-AC] a component part's count among its kind ('c.<key>.<z2>.<t|p>.<n>') }
  parts3: string;
  { [R7-AE] an option set notMerge; a pointer the port drew }
  nm: Boolean;
  pk: string;
  ptrs: TTyOverlayShapeArray;
  fps: Double;
  { [R7-AF] the af- cases: as the ae- ones, and a text's place, a clip's path }
  ae, af: Boolean;
  fpx, ux, uy: Double;
  fw: Integer;
  ffam: string;
  ring: TJSONArray;
begin
  af := APrefix = 'af-';
  ae := (APrefix = 'ae-') or af;
  strict := APrefix <> 'w-';
  FBad := 0;
  FCompared := 0;
  FReport := '';
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if Copy(id, 1, Length(APrefix)) <> APrefix then Continue;
    { a trail's frames under useDirtyRect: upstream repaints a block round
      each moving symbol and keeps the rest of the last frame's pixels; the
      port draws an animated frame whole (recorded, not held: spec 277) }
    if id = 'w-dirty-effect' then Continue;
    { [R7-AA] radar's component (z 0) among the cartesian axes' parts: the
      port draws the axes before it builds the list radar's elements are in,
      so they come after every axis part (recorded, not held: spec 281) }
    if id = 'aa-radar-order' then Continue;
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
        { ([R7-AE] '=' the case's own option again; `nm` notMerge) }
        nm := (c.Find('nm') <> nil) and (c.Objects['nm'].Find(IntToStr(j)) <> nil)
          and c.Objects['nm'].Booleans[IntToStr(j)];
        if c.Objects['sets'].Find(IntToStr(j)).JSONType = jtString then
          FChart.SetOption(c.Objects['option'].AsJSON, nm)
        else
          FChart.SetOption(c.Objects['sets'].Objects[IntToStr(j)].AsJSON, nm);
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
          { ([R7-AE] a dataZoom's part: the chart's own pointer finds it,
            not the list -- TestAnUnplacedSlidersPointerAsUpstream) }
          if Copy(want, 1, 11) = 'c.dataZoom0' then Continue;
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
      if (APrefix = 'aa-') or (APrefix = 'ac-') or ae then CheckAreas(Format('%s t=%g', [id, t]), els);
      for k := 0 to els.Count - 1 do
      begin
        rec := els.Objects[k];
        key := rec.Strings['key'];
        where := Format('%s t=%g %s', [id, t, key]);
        ops := rec.Arrays['ops'];
        if ops.Count = 0 then Continue;
        { ([R7-AC] a richText tooltip's blank span: see below) }
        if (APrefix = 'ac-') and (Copy(key, 1, 15) = 'c.tooltip0.0.t.') and (Trim(rec.Get('tx', '')) = '') then
          Continue;
        { [R7-AE] a text's box or span of its own }
        if ae and (key[1] = 'k') then
        begin
          KPiece(where, rec, key);
          Continue;
        end;
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
            parts3 := parts[4];
          finally
            parts.Free;
          end;
          if FChart.CompPart(ckey, cz2, ctext, '', el) then idx := 0
          else
          begin
            { (a component in the list) }
            comp := False;
            idx := CListOf(rec, ctext, cz2);
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
          if comp and (op = 'fill') then FChart.CompPart(ckey, cz2, ctext, op, el, o.Strings['fs'], o.Strings['ss'])
          else if comp and (op = 'stroke') then FChart.CompPart(ckey, cz2, ctext, op, el, o.Strings['ss'])
          { ([R7-AC] a richText tooltip's spans in their order: the n-th of
            those upstream brushed, the n-th the port drew -- the blank
            spans upstream brushes after a marker ('{marker|}  ': in the
            Text's own fill, as the span after them) the port's marker gap) }
          else if comp and ctext and (ckey = 'tooltip0') then
          begin
            n := 0;
            for q2 := 0 to els.Count - 1 do
              if (Copy(els.Objects[q2].Strings['key'], 1, Length(key) - Length(parts3)) =
                Copy(key, 1, Length(key) - Length(parts3)))
                and (els.Objects[q2].Arrays['ops'].Count > 0)
                and (Trim(els.Objects[q2].Get('tx', '')) <> '')
                and (StrToIntDef(Copy(els.Objects[q2].Strings['key'], Length(key) - Length(parts3) + 1, MaxInt), -1)
                  < StrToInt(parts3)) then Inc(n);
            FChart.CompPartNth(ckey, cz2, ctext, n, el);
          end
          else if comp then FChart.CompPart(ckey, cz2, ctext, op, el);
          for n := 0 to 5 do m[n] := HexD(o.Arrays['m'].Strings[n]);
          { the line scale of the transform the op is made under }
          sc := Sqrt(Abs(m[0] * m[3] - m[1] * m[2]));
          if isCap then
          begin
            { [R7-AF] A DATAZOOM LABEL'S PLACE (its middle-aligned span is at
              its anchor): the op's transform at the span's (x, y) against
              the caption's anchor -- under a whole map, the map's origin and
              its linear part the op's -- its alignment and font }
            if af and (o.Find('tp') <> nil) and (Copy(key, 1, 11) = 'c.dataZoom0') then
            begin
              ux := m[0] * HexD(o.Arrays['tp'].Strings[0]) + m[2] * HexD(o.Arrays['tp'].Strings[1]) + m[4];
              uy := m[1] * HexD(o.Arrays['tp'].Strings[0]) + m[3] * HexD(o.Arrays['tp'].Strings[1]) + m[5];
              Inc(FCompared);
              if el.Caption.HasAffine then
              begin
                if (Abs(el.Caption.Affine[4] - ux) > 1e-6) or (Abs(el.Caption.Affine[5] - uy) > 1e-6)
                  or (Abs(el.Caption.Affine[0] - m[0]) > 1e-9) or (Abs(el.Caption.Affine[1] - m[1]) > 1e-9)
                  or (Abs(el.Caption.Affine[2] - m[2]) > 1e-9) or (Abs(el.Caption.Affine[3] - m[3]) > 1e-9) then
                  Miss(Format('%s: text under [%g,%g,%g,%g,%g,%g], upstream at (%g,%g) under [%g,%g,%g,%g]',
                    [where, el.Caption.Affine[0], el.Caption.Affine[1], el.Caption.Affine[2], el.Caption.Affine[3],
                    el.Caption.Affine[4], el.Caption.Affine[5], ux, uy, m[0], m[1], m[2], m[3]]));
              end
              else if (Abs(el.Caption.X - ux) > 1e-6) or (Abs(el.Caption.Y - uy) > 1e-6)
                or (Abs(m[0] - 1) > 1e-9) or (Abs(m[3] - 1) > 1e-9) or (m[1] <> 0) or (m[2] <> 0) then
                Miss(Format('%s: text at (%g,%g), upstream (%g,%g) under [%g,%g,%g,%g]', [where,
                  el.Caption.X, el.Caption.Y, ux, uy, m[0], m[1], m[2], m[3]]));
              case el.Caption.AnchorH of
                tahRight: want := 'right';
                tahCentre: want := 'center';
              else
                want := 'left';
              end;
              Inc(FCompared);
              if (want <> o.Strings['al']) or (el.Caption.AnchorV <> tavMiddle) or (o.Strings['bl'] <> 'middle') then
                Miss(Format('%s: text aligned %s, upstream %s / %s', [where, want, o.Strings['al'], o.Strings['bl']]));
              FontOfCss(o.Strings['font'], fpx, fw, ffam);
              Inc(FCompared);
              { (the port's weight nought is the normal one) }
              if (Abs(TyFontPxOf(el.Caption.FontSizeLogical) - fpx) > 1e-9)
                or ((el.Caption.FontWeight <> fw) and not ((el.Caption.FontWeight = 0) and (fw = 400))) then
                Miss(Format('%s: text of %gpx weight %d, upstream %s', [where,
                  TyFontPxOf(el.Caption.FontSizeLogical), el.Caption.FontWeight, o.Strings['font']]));
            end;
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
            { [R7-AA] the text's shadow where it blurs (a refused colour the
              canvas' own) }
            sb := HexD(o.Strings['sb']);
            if ((APrefix = 'aa-') or (APrefix = 'ac-') or ae) and (sb > 0)
              and TyTryParseChartColor(o.Strings['sc'], wc) then
            begin
              Inc(FCompared);
              n := -1;
              for q2 := High(el.Caption.RtPieces) downto 0 do
                if el.Caption.RtPieces[q2].Text <> '' then
                begin
                  n := q2;
                  Break;
                end;
              if (n < 0) or not el.Caption.RtPieces[n].HasShadow
                or not SameInk(el.Caption.RtPieces[n].ShadowColor, wc)
                or (Abs(el.Caption.RtPieces[n].ShadowBlur - sb) > 1e-9) then
                Miss(Format('%s: text shadow (piece %d), upstream %s blur %g', [where, n,
                  o.Strings['sc'], sb]));
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
            { [R7-AA] a gradient the canvas holds (the aa- cases) }
            if ((APrefix = 'aa-') or (APrefix = 'ac-') or ae) and (o.Strings['ss'] = '[grad]') then
            begin
              Inc(FCompared);
              if el.Style.StrokeGradient.Kind = cgkNone then
                Miss(Format('%s: stroke %x, upstream a gradient', [where, el.Style.StrokeColor]));
            end
            else if (o.Strings['ss'] <> '[grad]') and TyTryParseChartColor(o.Strings['ss'], wc) then
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
            { ([R7-AC] a list of an odd length the canvas doubles, as
              setLineDash does: 'dotted' is [w], [w, w] on the canvas) }
            if Odd(Length(pdash)) then pdash := Concat(pdash, pdash);
            { ([R7-AE] an element in its own frame under the transform the
              canvas kept: its dash is the canvas' own, drawn at its pen's
              scale) }
            fps := 1;
            if (Length(el.FrameShape) > 0) and (el.Style.PenScale > 0) then fps := el.Style.PenScale;
            pdash := Copy(pdash, 0, Length(pdash));
            for n := 0 to High(pdash) do pdash[n] := pdash[n] * fps;
            Inc(FCompared);
            { ([R7-Z] the z- cases: a dash where upstream strokes solid too) }
            if strict and (ld.Count = 0) and (Length(pdash) > 0) then
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
              pldo := el.Style.DashOffsetLogical * fps;
              if IsNan(pldo) then pldo := -1e300;
              Inc(FCompared);
              if Abs(pldo - ldo) > 1e-6 then
                Miss(Format('%s: dash phase %g, upstream %g', [where, pldo, ldo]));
            end;
            { [R7-Z] the cap (a word the canvas refuses: the one it had) }
            if strict then
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
              { [R7-AA] and the join (a word the canvas refuses: the one it had) }
              if (APrefix = 'aa-') or (APrefix = 'ac-') or ae then
              begin
                case el.Style.LineJoin of
                  1: want := 'round';
                  2: want := 'bevel';
                else
                  want := 'miter';
                end;
                Inc(FCompared);
                if want <> o.Strings['join'] then
                  Miss(Format('%s: join %s, upstream %s', [where, want, o.Strings['join']]));
              end;
            end;
          end;
          { [R7-AC] the alpha it is made at (a single axis' split lines at
            0.2) and the arguments of a gradient a series' element is
            handed (made over the box of the element that set it, in that
            element's frame) }
          if ((APrefix = 'ac-') or ae) and ((op = 'fill') or (op = 'stroke')) then
          begin
            Inc(FCompared);
            ga := el.Style.Alpha;
            if (op = 'fill') and el.Style.HasFillOpacity then ga := ga * el.Style.FillOpacity;
            if (op = 'stroke') and el.Style.HasStrokeOpacity then ga := ga * el.Style.StrokeOpacity;
            if Abs(ga - HexD(o.Strings['ga'])) > 1e-6 then
              Miss(Format('%s: %s at alpha %g, upstream %g', [where, op, ga, HexD(o.Strings['ga'])]));
            { ([R7-AE] the ae- cases: a component's part too) }
            if (not comp and (Copy(key, 1, 2) <> 'c.')) or ae then
              GradMiss(where + ' ' + op, el, op = 'fill', o);
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
        { [R7-AC] AN AXIS POINTER'S LINE WHERE ITS SLIDE HAS GOT TO (the
          ac- cases): the drawn line's bounds }
        if ((APrefix = 'ac-') or ae) and comp and not ctext and (Pos('Pointer', ckey) > 0) and (cz2 = 0)
          and (rec.Find('pb').JSONType <> jtNull) and FChart.CompPart(ckey, cz2, ctext, 'stroke', el) then
        begin
          bb := TyShapeBounds(el.Shape);
          Inc(FCompared);
          if not TyRectFIsValid(bb) or (Abs(bb.Left - HexD(rec.Arrays['pb'].Strings[0])) > 1e-3)
            or (Abs(bb.Top - HexD(rec.Arrays['pb'].Strings[1])) > 1e-3)
            or (Abs(bb.Right - HexD(rec.Arrays['pb'].Strings[2])) > 1e-3)
            or (Abs(bb.Bottom - HexD(rec.Arrays['pb'].Strings[3])) > 1e-3) then
            Miss(Format('%s: the pointer at (%g,%g)-(%g,%g), upstream (%g,%g)-(%g,%g)', [where,
              bb.Left, bb.Top, bb.Right, bb.Bottom, HexD(rec.Arrays['pb'].Strings[0]),
              HexD(rec.Arrays['pb'].Strings[1]), HexD(rec.Arrays['pb'].Strings[2]),
              HexD(rec.Arrays['pb'].Strings[3])]));
        end;
        { [R7-AC] A RICHTEXT TOOLTIP'S BOX where upstream fills it: the
          place moveTo was given, in by the border's width (TooltipRichContent's
          1) and the shadow's outer size }
        if ((APrefix = 'ac-') or ae) and (key = 'c.tooltip0.0.p.0') and (rec.Find('pb').JSONType <> jtNull) then
        begin
          bb := FChart.TipFill;
          Inc(FCompared);
          if not TyRectFIsValid(bb) or (Abs(bb.Left - HexD(rec.Arrays['pb'].Strings[0])) > 1e-6)
            or (Abs(bb.Top - HexD(rec.Arrays['pb'].Strings[1])) > 1e-6) then
            Miss(Format('%s: the box filled from (%g,%g), upstream (%g,%g)', [where, bb.Left, bb.Top,
              HexD(rec.Arrays['pb'].Strings[0]), HexD(rec.Arrays['pb'].Strings[1])]));
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
        { [R7-AF] A CLIP'S PATH ON THE CANVAS (the af- cases): the element
          whose brush set it -- each corner of upstream's ring a corner of the
          port's clip (its path, else its rect) }
        if af and (rec.Find('clp') <> nil) and (rec.Find('clp').JSONType = jtArray)
          and (Copy(key, 1, 11) = 'c.dataZoom0') and not comp then
        begin
          ring := rec.Arrays['clp'].Arrays[rec.Arrays['clp'].Count - 1];
          Inc(FCompared);
          if Length(el.ClipPaths) > 0 then
          begin
            for n := 0 to ring.Count - 1 do
            begin
              ux := HexD(ring.Arrays[n].Strings[0]);
              uy := HexD(ring.Arrays[n].Strings[1]);
              nm := False;
              for q := 0 to High(el.ClipPaths[0].Points) do
                if (Abs(el.ClipPaths[0].Points[q].X - ux) < 1e-6) and (Abs(el.ClipPaths[0].Points[q].Y - uy) < 1e-6) then
                  nm := True;
              if not nm then
              begin
                Miss(Format('%s: no corner of the clip at (%g,%g)', [where, ux, uy]));
                Break;
              end;
            end;
          end
          else if not el.HasClip then
            Miss(where + ': no clip, upstream one')
          else
            for n := 0 to ring.Count - 1 do
            begin
              ux := HexD(ring.Arrays[n].Strings[0]);
              uy := HexD(ring.Arrays[n].Strings[1]);
              if not (((Abs(ux - el.ClipRect.Left) < 1e-6) or (Abs(ux - el.ClipRect.Right) < 1e-6))
                and ((Abs(uy - el.ClipRect.Top) < 1e-6) or (Abs(uy - el.ClipRect.Bottom) < 1e-6))) then
              begin
                Miss(Format('%s: clip (%g,%g)-(%g,%g), upstream a corner at (%g,%g)', [where,
                  el.ClipRect.Left, el.ClipRect.Top, el.ClipRect.Right, el.ClipRect.Bottom, ux, uy]));
                Break;
              end;
            end;
        end;
        { [R7-AE] A DATAZOOM'S PART WHERE IT IS BRUSHED (the ae- cases, and
          ac-dz-inf): the drawn path's bounds -- an unplaced slider's in its
          own frame under the transform the canvas had }
        if ((ae or (id = 'ac-dz-inf')) and (Copy(key, 1, 11) = 'c.dataZoom0') and not ctext
          and not comp and (rec.Find('pb').JSONType <> jtNull)) then
        begin
          mb := TyRectF(HexD(rec.Arrays['pb'].Strings[0]), HexD(rec.Arrays['pb'].Strings[1]),
            HexD(rec.Arrays['pb'].Strings[2]), HexD(rec.Arrays['pb'].Strings[3]));
          bb := TyShapeBounds(el.Shape);
          Inc(FCompared);
          if not TyRectFIsValid(bb) or (Abs(bb.Left - mb.Left) > 0.05) or (Abs(bb.Right - mb.Right) > 0.05)
            or (Abs(bb.Top - mb.Top) > 0.05) or (Abs(bb.Bottom - mb.Bottom) > 0.05) then
            Miss(Format('%s: drawn at (%g,%g)-(%g,%g), upstream (%g,%g)-(%g,%g)', [where,
              bb.Left, bb.Top, bb.Right, bb.Bottom, mb.Left, mb.Top, mb.Right, mb.Bottom]));
        end;
      end;
      { [R7-AE] a pointer's line or band the port drew: upstream has its
        group's path (one an action showed is gone after a notMerge
        setOption) }
      if ae then
      begin
        ptrs := FChart.PtrShapes;
        for q := 0 to High(ptrs) do
        begin
          pk := ptrs[q].Owner;
          n := Length(pk);
          while (n > 0) and (pk[n] in ['0'..'9']) do Dec(n);
          pk := 'c.' + Copy(pk, 1, n) + 'Pointer' + Copy(pk, n + 1, MaxInt) + '.';
          nm := False;
          for k := 0 to els.Count - 1 do
            if (Copy(els.Objects[k].Strings['key'], 1, Length(pk)) = pk)
              and (els.Objects[k].Arrays['ops'].Count > 0) then nm := True;
          Inc(FCompared);
          if not nm then
            Miss(Format('%s t=%g: a pointer of %s drawn, upstream none', [id, t, ptrs[q].Owner]));
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
  { [R7-AB] a trail's line: points along it and their ink at the first
    sample }
  lineAt: array of TTyPointF;
  lineInk0: array of Double;
  lineKey: array of string;

  function InkOf(AX, AY: Double): Double;
  var p0: TBGRAPixel;
  begin
    p0 := FBmp.GetPixel(Trunc(AX), Trunc(AY));
    Result := Sqrt(Sqr(255 - p0.red) + Sqr(255 - p0.green) + Sqr(255 - p0.blue));
  end;

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

  { [R7-AB] clear of every other tracked symbol drawn over it (a later
    series': a highlighted one in the block) }
  function ClearOfOthers(AX, AY: Double; const AKey: string): Boolean;
  var k2: Integer; o2, op2: TJSONObject; rr2: TTyRectF; a2: TJSONArray; ox2, oy2, or2: Double;
  begin
    Result := True;
    for k2 := 0 to els.Count - 1 do
    begin
      o2 := els.Objects[k2];
      if (o2.Strings['key'] = AKey) or (o2.Strings['key'][1] <> 's') or (o2.Strings['key'] <= AKey) then Continue;
      { the circle it was last brushed as (its op's transform: the unit
        symbol scaled by half its size), else its paint rect }
      a2 := o2.Arrays['yops'];
      if a2.Count > 0 then
      begin
        op2 := a2.Objects[a2.Count - 1];
        ox2 := HexD(op2.Arrays['m'].Strings[4]);
        oy2 := HexD(op2.Arrays['m'].Strings[5]);
        or2 := Sqrt(Abs(HexD(op2.Arrays['m'].Strings[0]) * HexD(op2.Arrays['m'].Strings[3])
          - HexD(op2.Arrays['m'].Strings[1]) * HexD(op2.Arrays['m'].Strings[2])));
        if Sqrt(Sqr(AX - ox2) + Sqr(AY - oy2)) < or2 + 2 then Exit(False);
      end
      else if RectOfHex(o2.Find('pr'), rr2) then
      begin
        if (AX > rr2.Left - 2) and (AX < rr2.Right + 2) and (AY > rr2.Top - 2) and (AY < rr2.Bottom + 2) then
          Exit(False);
      end;
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
    lineAt := nil;
    lineInk0 := nil;
    lineKey := nil;
    for j := 0 to frames.Count - 1 do
    begin
      fr := frames.Objects[j];
      t := fr.Floats['t'];
      { [R7-AB] the actions before the sample (a state's change) }
      if (c.Find('acts') <> nil) and (c.Objects['acts'].Find(IntToStr(j)) <> nil) then
      begin
        FChart.AnimNow := cT0 + t;
        for q := 0 to c.Objects['acts'].Arrays[IntToStr(j)].Count - 1 do
          FChart.DispatchAction(c.Objects['acts'].Arrays[IntToStr(j)].Objects[q].AsJSON);
      end;
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
      { [R7-AB] A TRAIL'S LINE (its layer motion-blurred): at the first
        sample, points along it and their ink; at the last, one away from
        every block repainted so far has faded (the layer faded whole every
        paint, only the blocks brushed again), one in the last paint's
        block away from the effect symbols has its full ink back }
      if Pos('trail', id) > 0 then
      begin
        els := fr.Arrays['els'];
        if j = 0 then
          for k := 0 to els.Count - 1 do
          begin
            rec := els.Objects[k];
            if (rec.Strings['key'][1] <> 'l') or (rec.Find('pb') = nil)
              or (rec.Find('pb').JSONType <> jtArray) then Continue;
            y := (HexD(rec.Arrays['pb'].Strings[1]) + HexD(rec.Arrays['pb'].Strings[3])) / 2;
            x := HexD(rec.Arrays['pb'].Strings[0]) + 6;
            while x < HexD(rec.Arrays['pb'].Strings[2]) - 6 do
            begin
              SetLength(lineAt, Length(lineAt) + 1);
              SetLength(lineInk0, Length(lineInk0) + 1);
              SetLength(lineKey, Length(lineKey) + 1);
              lineAt[High(lineAt)] := TyPointF(x, y);
              lineInk0[High(lineInk0)] := InkOf(x, y);
              lineKey[High(lineKey)] := rec.Strings['key'];
              x := x + 7;
            end;
          end
        else if j = frames.Count - 1 then
        begin
          EffectsOf(els);
          got := 0;
          for q := 0 to High(lineAt) do
          begin
            ok := True;
            for n := 0 to High(ever) do
              if (lineAt[q].X > ever[n].Left - 4) and (lineAt[q].X < ever[n].Right + 4)
                and (lineAt[q].Y > ever[n].Top - 4) and (lineAt[q].Y < ever[n].Bottom + 4) then ok := False;
            Inc(FCompared);
            if ok then
            begin
              { never brushed again: faded by lastFrameAlpha every paint }
              Inc(got);
              if not (InkOf(lineAt[q].X, lineAt[q].Y) <= 0.85 * lineInk0[q]) then
                Miss(Format('%s %s: ink %g at (%g,%g), %g at the first sample, upstream faded', [id,
                  lineKey[q], InkOf(lineAt[q].X, lineAt[q].Y), lineAt[q].X, lineAt[q].Y, lineInk0[q]]));
            end
            else if ClearOfEffects(lineAt[q].X, lineAt[q].Y, 4) then
            begin
              ok := False;
              p := paints.Count - 1;
              for b := 0 to paints.Arrays[p].Count - 1 do
                if RectOfHex(paints.Arrays[p].Items[b], rr) and (lineAt[q].X > rr.Left + 2)
                  and (lineAt[q].X < rr.Right - 2) and (lineAt[q].Y > rr.Top + 2) and (lineAt[q].Y < rr.Bottom - 2) then
                  ok := True;
              if ok and not (InkOf(lineAt[q].X, lineAt[q].Y) >= 0.9 * lineInk0[q]) then
                Miss(Format('%s %s: ink %g at (%g,%g) in a block, %g at the first sample', [id,
                  lineKey[q], InkOf(lineAt[q].X, lineAt[q].Y), lineAt[q].X, lineAt[q].Y, lineInk0[q]]));
            end;
          end;
          AssertTrue(id + ': points away from the blocks', got > 4);
        end;
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
          { [R7-AB] A RING (a symbol's border the canvas refused) in its block:
            the stroke the block's run left there }
          else if (key[1] = 's') and (o.Strings['op'] = 'stroke') and (Pos('stroke', id) > 0)
            and TyTryParseChartColor(o.Strings['ss'], wc) then
          begin
            y := blkR.Top + 1.5;
            while y <= blkR.Bottom - 1.5 do
            begin
              x := blkR.Left + 1.5;
              while x <= blkR.Right - 1.5 do
              begin
                if (Abs(Sqrt(Sqr(x - cx) + Sqr(y - cy)) - r) <= 0.8) and ClearOfEffects(x, y, 2.5)
                  and ClearOfOthers(x, y, key) then
                  Probe(x, y, wc, 40, where + ' ring in its block', 0.998);
                x := x + 1;
              end;
              y := y + 1;
            end;
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
                if (Sqrt(Sqr(x - cx) + Sqr(y - cy)) <= r - 1.5) and ClearOfEffects(x, y, 2.5)
                  and ClearOfOthers(x, y, key) then
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
  gfr: TTyDoubleArray;

  { [R7-AB] AS DRAWN: points of the element's path where upstream's ramp
    (the op's transform AM over the gradient's arguments AA, in the frame
    they were made in) is half way -- a radial one's half radius each way
    from its centre, a linear one's middle and either side of it along the
    stripe -- inside the unit box: one colour at all of them (an ellipse,
    a slanted stripe; a circle or a square stripe in their place puts them
    at different points of the ramp) }
  procedure GradInk(const AWhere: string; const AM: array of Double; AA: TJSONArray; ALinear: Boolean);
  var
    q3, k3, seen, ix, iy: Integer;
    lx, ly, dx, dy, dl, gx, gy, fx, fy: Double;
    want: TBGRAPixel;

    { the bitmap at (AX, AY) between the four pixel centres round it }
    function Bilinear(AX, AY: Double): TBGRAPixel;
    var p00, p10, p01, p11: TBGRAPixel;
    begin
      ix := Floor(AX - 0.5);
      iy := Floor(AY - 0.5);
      fx := AX - 0.5 - ix;
      fy := AY - 0.5 - iy;
      p00 := FBmp.GetPixel(ix, iy);
      p10 := FBmp.GetPixel(ix + 1, iy);
      p01 := FBmp.GetPixel(ix, iy + 1);
      p11 := FBmp.GetPixel(ix + 1, iy + 1);
      Result.red := Round((p00.red * (1 - fx) + p10.red * fx) * (1 - fy) + (p01.red * (1 - fx) + p11.red * fx) * fy);
      Result.green := Round((p00.green * (1 - fx) + p10.green * fx) * (1 - fy) + (p01.green * (1 - fx) + p11.green * fx) * fy);
      Result.blue := Round((p00.blue * (1 - fx) + p10.blue * fx) * (1 - fy) + (p01.blue * (1 - fx) + p11.blue * fx) * fy);
      Result.alpha := 255;
    end;

  begin
    if Copy(id, 1, 8) <> 'ab-grad-' then Exit;
    want := BGRAPixelTransparent;
    seen := 0;
    for q3 := 0 to 3 do
    begin
      if ALinear then
      begin
        dx := -(HexD(AA.Strings[3]) - HexD(AA.Strings[1]));
        dy := HexD(AA.Strings[2]) - HexD(AA.Strings[0]);
        dl := Sqrt(dx * dx + dy * dy);
        if dl = 0 then Exit;
        lx := (HexD(AA.Strings[0]) + HexD(AA.Strings[2])) / 2 + dx / dl * (q3 - 1.5) * 0.4;
        ly := (HexD(AA.Strings[1]) + HexD(AA.Strings[3])) / 2 + dy / dl * (q3 - 1.5) * 0.4;
      end
      else
      begin
        lx := HexD(AA.Strings[3]) + 0.5 * HexD(AA.Strings[5]) * Cos(q3 * Pi / 2);
        ly := HexD(AA.Strings[4]) + 0.5 * HexD(AA.Strings[5]) * Sin(q3 * Pi / 2);
      end;
      if (Abs(lx) > 0.85) or (Abs(ly) > 0.85) then Continue;
      gx := AM[0] * lx + AM[2] * ly + AM[4];
      gy := AM[1] * lx + AM[3] * ly + AM[5];
      px := Bilinear(gx, gy);
      Inc(seen);
      if seen = 1 then
      begin
        want := px;
        Continue;
      end;
      Inc(FCompared);
      k3 := Max(Abs(px.red - want.red), Max(Abs(px.green - want.green), Abs(px.blue - want.blue)));
      if k3 > 6 then
        Miss(Format('%s: half way at (%g,%g) drawn (%d,%d,%d), at the first such point (%d,%d,%d)',
          [AWhere, gx, gy, px.red, px.green, px.blue, want.red, want.green, want.blue]));
    end;
    AssertTrue(AWhere + ': half-way points', seen >= 3);
    { and the ramp is there: a fifth of the way along (a radial one's fifth
      of its radius, a linear one's fifth from its start) is another colour }
    if ALinear then
    begin
      lx := HexD(AA.Strings[0]) + 0.3 * (HexD(AA.Strings[2]) - HexD(AA.Strings[0]));
      ly := HexD(AA.Strings[1]) + 0.3 * (HexD(AA.Strings[3]) - HexD(AA.Strings[1]));
    end
    else
    begin
      lx := HexD(AA.Strings[3]) + 0.15 * HexD(AA.Strings[5]);
      ly := HexD(AA.Strings[4]);
    end;
    if (Abs(lx) <= 0.85) and (Abs(ly) <= 0.85) then
    begin
      gx := AM[0] * lx + AM[2] * ly + AM[4];
      gy := AM[1] * lx + AM[3] * ly + AM[5];
      px := Bilinear(gx, gy);
      Inc(FCompared);
      k3 := Max(Abs(px.red - want.red), Max(Abs(px.green - want.green), Abs(px.blue - want.blue)));
      if k3 <= 20 then
        Miss(Format('%s: near the start at (%g,%g) drawn (%d,%d,%d), as half way (%d,%d,%d): no ramp',
          [AWhere, gx, gy, px.red, px.green, px.blue, want.red, want.green, want.blue]));
    end;
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
          { [R7-AB] an axis' text: the part as it was drawn (CompDrawn) }
          if Copy(key, 1, 2) = 'ax' then
          begin
            if not FChart.CompPart('xAxis0', 10, True, 'fill', el) then
            begin
              Miss(where + ': no label drawn');
              Continue;
            end;
          end
          else
          begin
            idx := WElOf(key, rec);
            if idx < 0 then
            begin
              Miss(where + ': no element');
              Continue;
            end;
            el := FChart.Frame.Element(idx);
            { [R7-AB] a rich text: its last span's font, as settled }
            for q2 := High(el.Caption.RtPieces) downto 0 do
              if (el.Caption.RtPieces[q2].Kind = rpkText) and (el.Caption.RtPieces[q2].Text <> '') then
              begin
                el.Caption.FontName := el.Caption.RtPieces[q2].FontFamily;
                el.Caption.FontSizeLogical := TyFontSizeFromPx(el.Caption.RtPieces[q2].FontSizePx);
                el.Caption.FontWeight := el.Caption.RtPieces[q2].FontWeight;
                Break;
              end;
          end;
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
          { [R7-AB] A LABEL'S TEXT SPAN: the shadow its last span casts once
            the paint order settled it (a refused part the canvas') }
          if key[1] = 'x' then
          begin
            n := -1;
            for q2 := 0 to High(el.Caption.RtPieces) do
              if el.Caption.RtPieces[q2].Text <> '' then n := q2;
            Inc(FCompared);
            { (a plain caption, no span: one that casts none) }
            if (n < 0) or not el.Caption.RtPieces[n].HasShadow then
            begin
              if (HexD(o.Strings['sb']) > 0) and TyTryParseChartColor(o.Strings['sc'], wc)
                and ((wc shr 24) <> 0) then
                Miss(Format('%s: casts none, upstream %s blur %g', [where, o.Strings['sc'],
                  HexD(o.Strings['sb'])]));
              Continue;
            end;
            if (Abs(el.Caption.RtPieces[n].ShadowBlur - HexD(o.Strings['sb'])) > 1e-9)
              or (Abs(el.Caption.RtPieces[n].ShadowOffsetX - HexD(o.Strings['sox'])) > 1e-9)
              or (Abs(el.Caption.RtPieces[n].ShadowOffsetY - HexD(o.Strings['soy'])) > 1e-9)
              or (TyTryParseChartColor(o.Strings['sc'], wc)
                and (el.Caption.RtPieces[n].ShadowColor <> wc)) then
              Miss(Format('%s: span shadow %x blur %g offset (%g,%g), upstream %s blur %g offset (%g,%g)',
                [where, el.Caption.RtPieces[n].ShadowColor, el.Caption.RtPieces[n].ShadowBlur,
                el.Caption.RtPieces[n].ShadowOffsetX, el.Caption.RtPieces[n].ShadowOffsetY,
                o.Strings['sc'], HexD(o.Strings['sb']), HexD(o.Strings['sox']), HexD(o.Strings['soy'])]));
            Continue;
          end;
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
        { [R7-AB] MADE IN A FRAME (a symbol's that is no similarity, or a
          held one under the filling element's): the frame is the op's
          transform and the points are the arguments as made }
        TyElementGradientIn(el, grad, 1, x1, y1, x2, y2, gr, gfr);
        if Length(gfr) = 6 then
        begin
          for n := 0 to 5 do
            if Abs(gfr[n] - m[n]) > 1e-6 then
            begin
              Miss(Format('%s: frame [%g %g %g %g %g %g], upstream [%g %g %g %g %g %g]', [where,
                gfr[0], gfr[1], gfr[2], gfr[3], gfr[4], gfr[5], m[0], m[1], m[2], m[3], m[4], m[5]]));
              Break;
            end;
          if kind = 'linear' then
          begin
            if (Abs(x1 - HexD(a.Strings[0])) > 1e-6) or (Abs(y1 - HexD(a.Strings[1])) > 1e-6)
              or (Abs(x2 - HexD(a.Strings[2])) > 1e-6) or (Abs(y2 - HexD(a.Strings[3])) > 1e-6) then
              Miss(Format('%s: linear in its frame (%g,%g)-(%g,%g), upstream (%g,%g)-(%g,%g)', [where,
                x1, y1, x2, y2, HexD(a.Strings[0]), HexD(a.Strings[1]), HexD(a.Strings[2]),
                HexD(a.Strings[3])]));
          end
          else if (Abs(x1 - HexD(a.Strings[3])) > 1e-6) or (Abs(y1 - HexD(a.Strings[4])) > 1e-6)
            or (Abs(gr - HexD(a.Strings[5])) > 1e-6) then
            Miss(Format('%s: radial in its frame (%g,%g) r %g, upstream (%g,%g) r %g', [where,
              x1, y1, gr, HexD(a.Strings[3]), HexD(a.Strings[4]), HexD(a.Strings[5])]));
          GradInk(where, m, a, kind = 'linear');
          Continue;
        end;
        GradInk(where, m, a, kind = 'linear');
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

{ [R7-AB] A HELD PATTERN AT ANOTHER PPI. The canvas keeps the CanvasPattern
  the element before made (createCanvasPattern: its matrix set, relative to
  the fill's user space); an element whose fill it refuses fills with it
  under its own transform -- exactly what that element draws with the same
  pattern object as its own fill, at any devicePixelRatio. So each y-pat-
  case is drawn at APPI twice, B's refused fill and B's own fill the same
  pattern as A's, and B's pixels must be the same (inside its bounds) }
procedure TAdvChartLinesCanvasOracleTest.RunYTexelsAt(APPI: Integer);
var
  cs: TJSONArray;
  c, opt: TJSONObject;
  i, x, y, k, w, h, diff: Integer;
  id, keyB: string;
  bmp1, bmp2: TBGRABitmap;
  p1, p2: TBGRAPixel;
  bb: TTyRectF;
  pat: TJSONData;

  function Draw(const AOpt: string; ABmp: TBGRABitmap; out ABox: TTyRectF): Boolean;
  var idx: Integer; rec: TJSONObject;
  begin
    FreeAndNil(FChart);
    FChart := TLcProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    { (the control at that PPI: its layout too) }
    FChart.Font.PixelsPerInch := APPI;
    FChart.SetBounds(0, 0, w, h);
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := cT0;
    FChart.SetOption(AOpt, True);
    AssertEquals(id + ' parses', '', FChart.OptionError);
    ABmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(ABmp.Canvas, Rect(0, 0, w, h), APPI);
    rec := TJSONObject.Create;
    try
      idx := WElOf(keyB, rec);
    finally
      rec.Free;
    end;
    Result := idx >= 0;
    if Result then ABox := TyShapeBounds(FChart.Frame.Element(idx).Shape);
  end;

begin
  FBad := 0;
  FCompared := 0;
  FReport := '';
  w := Round(FRoot.FindPath('W').AsInteger * APPI / 96);
  h := Round(FRoot.FindPath('H').AsInteger * APPI / 96);
  bmp1 := TBGRABitmap.Create(w, h);
  bmp2 := TBGRABitmap.Create(w, h);
  try
    cs := TJSONObject(FRoot).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      if (id <> 'y-pat-bar') and (id <> 'y-pat-scatter') then Continue;
      opt := TJSONObject(c.Objects['option'].Clone);
      try
        { B: the bar after A's, the scatter after A's }
        if id = 'y-pat-bar' then
        begin
          keyB := 'b0.1';
          pat := opt.FindPath('series[0].data[0].itemStyle.color').Clone;
          TJSONObject(opt.FindPath('series[0].data[1].itemStyle')).Delete('color');
          TJSONObject(opt.FindPath('series[0].data[1].itemStyle')).Add('color', pat);
        end
        else
        begin
          keyB := 's1.0';
          pat := opt.FindPath('series[0].itemStyle.color').Clone;
          TJSONObject(opt.FindPath('series[1].itemStyle')).Delete('color');
          TJSONObject(opt.FindPath('series[1].itemStyle')).Add('color', pat);
        end;
        if not Draw(c.Objects['option'].AsJSON, bmp1, bb) then
        begin
          Miss(id + ': no B');
          Continue;
        end;
        if not Draw(opt.AsJSON, bmp2, bb) then
        begin
          Miss(id + ': no B of its own');
          Continue;
        end;
      finally
        opt.Free;
      end;
      if GetEnvironmentVariable('TY_LC_SAVE') <> '' then
      begin
        bmp1.SaveToFile(GetEnvironmentVariable('TY_LC_SAVE') + id + '-held' + IntToStr(APPI) + '.png');
        bmp2.SaveToFile(GetEnvironmentVariable('TY_LC_SAVE') + id + '-own' + IntToStr(APPI) + '.png');
      end;
      diff := 0;
      for y := Ceil(bb.Top) + 2 to Floor(bb.Bottom) - 3 do
        for x := Ceil(bb.Left) + 2 to Floor(bb.Right) - 3 do
        begin
          { (a circle's corners are not its) }
          if (keyB[1] = 's') and (Sqr(x + 0.5 - (bb.Left + bb.Right) / 2)
            + Sqr(y + 0.5 - (bb.Top + bb.Bottom) / 2) > Sqr((bb.Right - bb.Left) / 2 - 2)) then Continue;
          p1 := bmp1.GetPixel(x, y);
          p2 := bmp2.GetPixel(x, y);
          Inc(FCompared);
          k := Max(Abs(p1.red - p2.red), Max(Abs(p1.green - p2.green), Abs(p1.blue - p2.blue)));
          if k > 8 then
          begin
            Inc(diff);
            if diff <= 4 then
              Miss(Format('%s @%d: (%d,%d) held (%d,%d,%d), own (%d,%d,%d)', [id, APPI, x, y,
                p1.red, p1.green, p1.blue, p2.red, p2.green, p2.blue]))
            else Inc(FBad);
          end;
        end;
    end;
  finally
    FreeAndNil(FChart);
    bmp1.Free;
    bmp2.Free;
  end;
  if FBad > 0 then
    Fail(Format('%d of %d differ:%s', [FBad, FCompared, FReport]));
  AssertTrue('compared', FCompared > 100);
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheHeldPatternsAtAnotherPPIAsUpstream;
begin
  RunYTexelsAt(96);
  RunYTexelsAt(144);
  RunYTexelsAt(120);
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

{ [R7-AA] AN AXIS' SPLIT AREAS BAND BY BAND: upstream's paths of z2 0 that
  only fill (a band, a merged colour), in their order, against the areas
  the port drew for that axis (CompDrawn, cpkSplitArea) in its order --
  the colour each settled in (a refused band the fill the band before
  left, not the first band of its colour's) }
procedure TAdvChartLinesCanvasOracleTest.CheckAreas(const AWhere: string; AEls: TJSONArray);
var
  keys: TStringList;
  k, q, i, n: Integer;
  rec: TJSONObject;
  ops: TJSONArray;
  key, ck, pre: string;
  fills: TStringList;
  d: TTyCompPartArray;
  wc: TTyChartColor;
  only: Boolean;
begin
  keys := TStringList.Create;
  fills := TStringList.Create;
  try
    for k := 0 to AEls.Count - 1 do
    begin
      key := AEls.Objects[k].Strings['key'];
      if Copy(key, 1, 2) <> 'c.' then Continue;
      ck := Copy(key, 3, MaxInt);
      ck := Copy(ck, 1, Pos('.', ck) - 1);
      if keys.IndexOf(ck) < 0 then keys.Add(ck);
    end;
    d := FChart.CompDrawn;
    for i := 0 to keys.Count - 1 do
    begin
      { upstream's fill-only paths of z2 0, by their count n }
      fills.Clear;
      pre := 'c.' + keys[i] + '.0.p.';
      for n := 0 to 999 do
      begin
        rec := nil;
        for k := 0 to AEls.Count - 1 do
          if AEls.Objects[k].Strings['key'] = pre + IntToStr(n) then rec := AEls.Objects[k];
        if rec = nil then Break;
        ops := rec.Arrays['ops'];
        only := ops.Count > 0;
        for q := 0 to ops.Count - 1 do
          if ops.Objects[q].Strings['op'] <> 'fill' then only := False;
        if only then fills.Add(ops.Objects[0].Strings['fs']);
      end;
      { the port's areas of that axis }
      q := 0;
      for k := 0 to High(d) do
        if (d[k].Key = keys[i]) and (d[k].Kind = cpkSplitArea) then
        begin
          Inc(FCompared);
          if q > fills.Count - 1 then
            Miss(Format('%s %s: area %d drawn, upstream %d', [AWhere, keys[i], q, fills.Count]))
          else if TyTryParseChartColor(fills[q], wc) and not SameInk(d[k].El.Style.FillColor, wc) then
            Miss(Format('%s %s: area %d fill %x, upstream %s', [AWhere, keys[i], q,
              d[k].El.Style.FillColor, fills[q]]));
          Inc(q);
        end;
      if (q > 0) and (q <> fills.Count) then
        Miss(Format('%s %s: %d areas drawn, upstream %d', [AWhere, keys[i], q, fills.Count]));
    end;
  finally
    fills.Free;
    keys.Free;
  end;
end;

{ [R7-AA] THE POLAR'S VIEWS IN UPSTREAM'S ORDER, as drawn: the radius
  axis' line (z2 1, its view first), then the angle axis' circle (z2 1,
  its view after): where the spoke meets the circle the circle is on top.
  A radius line red and 6 wide up from the centre (the angle axis starts
  at 90 degrees), the circle blue and 6 wide: the pixel a step inside the
  circle's top on the spoke is blue. }
procedure TAdvChartLinesCanvasOracleTest.TestThePolarViewsInUpstreamsOrder;
var px: TBGRAPixel;
begin
  FreeAndNil(FChart);
  FChart := TLcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
  FChart.SetOption('{"animation":false,"polar":{"center":[200,150],"radius":100},'
    + '"angleAxis":{"type":"value","min":0,"max":10,"axisLabel":{"show":false},"axisTick":{"show":false},'
    + '"splitLine":{"show":false},"axisLine":{"lineStyle":{"color":"#0000ff","width":6}}},'
    + '"radiusAxis":{"type":"value","min":0,"max":10,"axisLabel":{"show":false},"axisTick":{"show":false},'
    + '"splitLine":{"show":false},"axisLine":{"lineStyle":{"color":"#ff0000","width":6}}},'
    + '"series":[]}', True);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  px := FBmp.GetPixel(200, 51);
  AssertTrue(Format('the circle over the spoke: (%d,%d,%d)', [px.red, px.green, px.blue]),
    (px.blue > 200) and (px.red < 60));
  px := FBmp.GetPixel(200, 100);
  AssertTrue(Format('the spoke itself red: (%d,%d,%d)', [px.red, px.green, px.blue]),
    (px.red > 200) and (px.blue < 60));
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheR7AACanvasAsUpstream;
begin
  RunW(False, 'aa-');
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheR7ACCanvasAsUpstream;
begin
  RunW(False, 'ac-');
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheR7AECanvasAsUpstream;
begin
  RunW(False, 'ae-');
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheR7AEHitsAsUpstream;
begin
  RunW(True, 'ae-');
end;

procedure TAdvChartLinesCanvasOracleTest.TestTheR7AFCanvasAsUpstream;
begin
  RunW(False, 'af-');
end;

{ [R7-AF] a label's words whose rect joined a string width (or 'Infinity'):
  found by nothing, upstream's findHover at their probes }
procedure TAdvChartLinesCanvasOracleTest.TestTheR7AFHitsAsUpstream;
begin
  RunW(True, 'af-');
end;

{ [R7-AE] A TEXT'S DISPLAYABLE OF ITS OWN (k<host>.<n>): the n-th of the
  boxes drawn and the spans with words of the host's caption, in their
  order (zrender's children: the block's Rect, then each token's Rect and
  TSpan) -- each op's fill, a box's stroke, the shadow it casts, the alpha
  it is made at }
procedure TAdvChartLinesCanvasOracleTest.KPiece(const AWhere: string;
  const ARec: TJSONObject; const AKey: string);
var
  host, op: string;
  n, k, cnt, idx, q: Integer;
  el: TTyChartElement;
  pc: TTyRtPiece;
  found: Boolean;
  ops: TJSONArray;
  o: TJSONObject;
  wc: TTyChartColor;
  sb, ga: Double;
begin
  host := Copy(AKey, 2, MaxInt);
  k := LastDelimiter('.', host);
  n := StrToInt(Copy(host, k + 1, MaxInt));
  host := Copy(host, 1, k - 1);
  { (a line's end label: the polyline's text) }
  idx := -1;
  if Copy(host, 1, 2) = 'ln' then
  begin
    q := StrToInt(Copy(host, 3, Pos('.', host) - 3));
    for k := 0 to FChart.Frame.Count - 1 do
      if (FChart.Frame.Element(k).Anim.Role = carEndLabel) and (FChart.Frame.Element(k).Anim.Series = q) then
        idx := k;
  end
  else
    idx := WElOf('x' + host, ARec);
  if idx < 0 then
  begin
    Miss(AWhere + ': no text');
    Exit;
  end;
  el := FChart.Frame.Element(idx);
  { (a text of one run: its caption) }
  if Length(el.Caption.RtPieces) = 0 then
  begin
    if n <> 0 then
    begin
      Miss(Format('%s: a text of one run, upstream piece %d', [AWhere, n]));
      Exit;
    end;
    ops := ARec.Arrays['ops'];
    for q := 0 to ops.Count - 1 do
    begin
      o := ops.Objects[q];
      op := o.Strings['op'];
      if (op = 'fillText') and TyTryParseChartColor(o.Strings['fs'], wc) then
      begin
        Inc(FCompared);
        if not SameInkL(el.Caption.Colour, wc) then
          Miss(Format('%s: text fill %x, upstream %s', [AWhere, el.Caption.Colour, o.Strings['fs']]));
      end;
      if (op = 'strokeText') and TyTryParseChartColor(o.Strings['ss'], wc) then
      begin
        Inc(FCompared);
        if not SameInkL(el.Caption.StrokeColour, wc)
          or (Abs(el.Caption.StrokeWidthLogical - HexD(o.Strings['lw'])) > 1e-6) then
          Miss(Format('%s: text stroke %x width %g, upstream %s width %g', [AWhere,
            el.Caption.StrokeColour, el.Caption.StrokeWidthLogical, o.Strings['ss'], HexD(o.Strings['lw'])]));
      end;
    end;
    Exit;
  end;
  cnt := -1;
  found := False;
  pc := Default(TTyRtPiece);
  for k := 0 to High(el.Caption.RtPieces) do
  begin
    pc := el.Caption.RtPieces[k];
    if ((pc.Kind = rpkRect) and pc.Drawn) or ((pc.Kind = rpkText) and (pc.Text <> '')) then Inc(cnt);
    if cnt = n then
    begin
      found := True;
      Break;
    end;
  end;
  if not found then
  begin
    Miss(Format('%s: no piece %d of %d', [AWhere, n, cnt + 1]));
    Exit;
  end;
  ops := ARec.Arrays['ops'];
  for q := 0 to ops.Count - 1 do
  begin
    o := ops.Objects[q];
    op := o.Strings['op'];
    if ((op = 'fill') or (op = 'fillText')) and TyTryParseChartColor(o.Strings['fs'], wc) then
    begin
      Inc(FCompared);
      if not pc.HasFill or not SameInkL(pc.Fill, wc) then
        Miss(Format('%s: %s %x, upstream %s', [AWhere, op, pc.Fill, o.Strings['fs']]));
    end;
    { ([R7-AF] a span's halo too) }
    if ((op = 'stroke') or (op = 'strokeText')) and TyTryParseChartColor(o.Strings['ss'], wc) then
    begin
      Inc(FCompared);
      if not pc.HasStroke or not SameInkL(pc.Stroke, wc)
        or (Abs(pc.LineWidth - HexD(o.Strings['lw'])) > 1e-6) then
        Miss(Format('%s: %s %x width %g, upstream %s width %g', [AWhere, op, pc.Stroke,
          pc.LineWidth, o.Strings['ss'], HexD(o.Strings['lw'])]));
    end;
    sb := HexD(o.Strings['sb']);
    if (sb > 0) and TyTryParseChartColor(o.Strings['sc'], wc) then
    begin
      Inc(FCompared);
      if not pc.HasShadow or not SameInkL(pc.ShadowColor, wc) or (Abs(pc.ShadowBlur - sb) > 1e-9) then
        Miss(Format('%s: %s shadow %x blur %g, upstream %s blur %g', [AWhere, op, pc.ShadowColor,
          pc.ShadowBlur, o.Strings['sc'], sb]));
    end;
    ga := TyRtPieceDrawnAlpha(pc, el.Style.Alpha);
    Inc(FCompared);
    if Abs(ga - HexD(o.Strings['ga'])) > 1e-6 then
      Miss(Format('%s: %s at alpha %g, upstream %g', [AWhere, op, ga, HexD(o.Strings['ga'])]));
  end;
end;

{ [R7-AE] A LABEL'S BOX ON A HOST OF 0.8 (a scatter's default opacity) is
  drawn at the alpha upstream fills it at (ae-label-alpha-px's box: black on
  white, the record's globalAlpha) -- the same pixel as the same box on a
  host of 1 whose label writes that opacity itself, and not the host's
  opacity twice. (R7-AC read about 0.61 off the pixel: the painter blends
  in its own light, a symbol filled at 0.8 shows the same.) }
procedure TAdvChartLinesCanvasOracleTest.TestALabelBoxOnATranslucentHostAsUpstream;
var
  cs, els: TJSONArray;
  c, rec, opt, s0, lbl: TJSONObject;
  i, k, pass: Integer;
  ga: Double;
  pb: TJSONArray;
  px: array[0..1] of TBGRAPixel;
  x, y: Integer;
begin
  cs := TJSONObject(FRoot).Arrays['charts'];
  rec := nil;
  c := nil;
  for i := 0 to cs.Count - 1 do
    if cs.Objects[i].Strings['id'] = 'ae-label-alpha-px' then c := cs.Objects[i];
  AssertTrue('the case', c <> nil);
  els := c.Arrays['frames'].Objects[0].Arrays['els'];
  for k := 0 to els.Count - 1 do
    if els.Objects[k].Strings['key'] = 'ks0.0.0' then rec := els.Objects[k];
  AssertTrue('the box', rec <> nil);
  ga := HexD(rec.Arrays['ops'].Objects[0].Strings['ga']);
  AssertEquals('upstream fills it at the host''s opacity', 0.8, ga, 1e-9);
  pb := rec.Arrays['pb'];
  { three px in from the box's left edge, at its middle: the padding }
  x := Trunc(HexD(pb.Strings[0])) + 3;
  y := Trunc((HexD(pb.Strings[1]) + HexD(pb.Strings[3])) / 2);
  for pass := 0 to 1 do
  begin
    opt := TJSONObject(c.Objects['option'].Clone);
    try
      if pass = 1 then
      begin
        s0 := opt.Arrays['series'].Objects[0];
        s0.Objects['itemStyle'].Add('opacity', 1);
        lbl := s0.Objects['label'];
        lbl.Add('opacity', ga);
      end;
      FreeAndNil(FChart);
      FChart := TLcProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
      FChart.AnimationMode := camAlways;
      FChart.AnimNow := cT0;
      FChart.SetOption(opt.AsJSON, True);
      FBmp.Fill(BGRA(255, 255, 255, 255));
      FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
      px[pass] := FBmp.GetPixel(x, y);
    finally
      opt.Free;
    end;
  end;
  AssertTrue(Format('the box drawn at all: (%d,%d,%d)', [px[0].red, px[0].green, px[0].blue]),
    px[0].red < 200);
  AssertTrue(Format('the box on a host of 0.8 (%d,%d,%d), the box at an opacity of 0.8 of its own (%d,%d,%d)',
    [px[0].red, px[0].green, px[0].blue, px[1].red, px[1].green, px[1].blue]),
    (Abs(px[0].red - px[1].red) <= 2) and (Abs(px[0].green - px[1].green) <= 2)
    and (Abs(px[0].blue - px[1].blue) <= 2));
end;

{ [R7-AE] A DATAZOOM WIDTH OF NO NUMBER ('abc', ac-dz-nan's handle and
  data shadow line) is not above nought: upstream strokes neither (no
  stroke op for them) -- nothing of the slider strokes in the line's red,
  and the handles stroke nothing [was: the default width stroked] }
procedure TAdvChartLinesCanvasOracleTest.TestADzWidthOfNoNumberStrokesNothing;
var
  cs: TJSONArray;
  c: TJSONObject;
  i, k, nh: Integer;
  el: TTyChartElement;
begin
  cs := TJSONObject(FRoot).Arrays['charts'];
  c := nil;
  for i := 0 to cs.Count - 1 do
    if cs.Objects[i].Strings['id'] = 'ac-dz-nan' then c := cs.Objects[i];
  AssertTrue('the case', c <> nil);
  FreeAndNil(FChart);
  FChart := TLcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := cT0;
  FChart.SetOption(c.Objects['option'].AsJSON, True);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  nh := 0;
  for k := 0 to FChart.Frame.Count - 1 do
  begin
    el := FChart.Frame.Element(k);
    if el.Z <> 4 then Continue;
    AssertFalse(Format('element %d strokes the refused line red', [k]),
      (el.Style.StrokeWidthLogical > 0) and (el.Style.StrokeColor = TTyChartColor($FFFF0000)));
    if el.Style.HasFill and (el.Style.FillColor = TTyChartColor($FFFFFFFF)) and (el.Z2 = 5) then
    begin
      Inc(nh);
      AssertEquals(Format('handle %d strokes', [k]), 0, el.Style.StrokeWidthLogical, 0);
    end;
  end;
  AssertEquals('handles', 2, nh);
end;

{ [R7-AE] A POLYLINE OF ONE POINT (ae-one-point: a pen 3 wide, round caps)
  strokes a move alone: the canvas draws nothing of it -- white about the
  point -- though it holds the pen it hands on }
procedure TAdvChartLinesCanvasOracleTest.TestALonePointDrawsNothing;
var
  cs: TJSONArray;
  c: TJSONObject;
  i, x, y: Integer;
  px: TBGRAPixel;
begin
  cs := TJSONObject(FRoot).Arrays['charts'];
  c := nil;
  for i := 0 to cs.Count - 1 do
    if cs.Objects[i].Strings['id'] = 'ae-one-point' then c := cs.Objects[i];
  AssertTrue('the case', c <> nil);
  FreeAndNil(FChart);
  FChart := TLcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := cT0;
  FChart.SetOption(c.Objects['option'].AsJSON, True);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  for x := 206 to 214 do
    for y := 139 to 146 do
    begin
      px := FBmp.GetPixel(x, y);
      AssertTrue(Format('ink at (%d,%d): (%d,%d,%d)', [x, y, px.red, px.green, px.blue]),
        (px.red >= 250) and (px.green >= 250) and (px.blue >= 250));
    end;
end;

{ [R7-AE] AN UNPLACED SLIDER'S PIXELS: ae-dz-inf-sym's under the
  scatter's transform (4 times, at (210, 142.5)) -- the data shadow's
  area beside the window in the line's green within its group's clip
  (local x 0 .. 64 is device 210 .. 466), the clip taken through the same
  transform; and ac-dz-inf's under the canvas' own frame, the chart drawn
  at (30, 20): the background (local 0 .. 320 x 0 .. 30) from there }
procedure TAdvChartLinesCanvasOracleTest.TestAnUnplacedSlidersPixelsAsUpstream;
var
  cs: TJSONArray;
  c: TJSONObject;
  i, x, y, n, pass: Integer;
  px: TBGRAPixel;
  id: string;
begin
  cs := TJSONObject(FRoot).Arrays['charts'];
  for pass := 0 to 1 do
  begin
    if pass = 0 then id := 'ae-dz-inf-sym' else id := 'ac-dz-inf';
    c := nil;
    for i := 0 to cs.Count - 1 do
      if cs.Objects[i].Strings['id'] = id then c := cs.Objects[i];
    AssertTrue(id, c <> nil);
    FreeAndNil(FChart);
    FChart := TLcProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := cT0;
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    FBmp.Fill(BGRA(255, 255, 255, 255));
    if pass = 0 then
    begin
      FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
      n := 0;
      for x := 212 to FBmp.Width - 2 do
        for y := 144 to 239 do
        begin
          px := FBmp.GetPixel(x, y);
          if (px.green > 200) and (px.red < 60) and (px.blue < 60) then Inc(n);
        end;
      AssertTrue(Format('%s: the area in its clip, %d green px', [id, n]), n > 200);
    end
    else
    begin
      FChart.Render(FBmp.Canvas, Rect(30, 20, 30 + FBmp.Width, 20 + FBmp.Height), 96);
      px := FBmp.GetPixel(345, 45);
      AssertTrue(Format('%s: the background at (345,45): (%d,%d,%d)', [id, px.red, px.green, px.blue]),
        (Abs(px.red - $EE) <= 3) and (Abs(px.green - $EE) <= 3) and (Abs(px.blue - $EE) <= 3));
    end;
  end;
end;

{ [R7-AF] AN UNPLACED SLIDER'S HANDLE LABELS ARE DRAWN (af-dz-label-px):
  each where upstream's fillText puts it -- the record's transform at the
  span's place, right-aligned for the first (its words left of the place,
  none right of it), left for the second (from its place to the canvas'
  edge) -- in the textStyle's red }
procedure TAdvChartLinesCanvasOracleTest.TestAnUnplacedSlidersLabelsAsUpstream;
var
  cs, els, ops: TJSONArray;
  c, o: TJSONObject;
  i, k, x, y, n, nr, lab: Integer;
  px: TBGRAPixel;
  m: array[0..5] of Double;
  ux, uy: Double;
  el: TTyChartElement;
  b: TTyRectF;
begin
  cs := TJSONObject(FRoot).Arrays['charts'];
  c := nil;
  for i := 0 to cs.Count - 1 do
    if cs.Objects[i].Strings['id'] = 'af-dz-label-px' then c := cs.Objects[i];
  AssertTrue('af-dz-label-px', c <> nil);
  FreeAndNil(FChart);
  FChart := TLcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := cT0;
  FChart.SetOption(c.Objects['option'].AsJSON, True);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  els := c.Arrays['frames'].Objects[0].Arrays['els'];
  for lab := 0 to 1 do
  begin
    o := nil;
    for k := 0 to els.Count - 1 do
      if els.Objects[k].Strings['key'] = 'c.dataZoom0.10.t.' + IntToStr(lab) then
      begin
        ops := els.Objects[k].Arrays['ops'];
        AssertTrue('a text drawn upstream', ops.Count > 0);
        o := ops.Objects[0];
      end;
    AssertTrue('the label upstream', o <> nil);
    for k := 0 to 5 do m[k] := HexD(o.Arrays['m'].Strings[k]);
    ux := m[0] * HexD(o.Arrays['tp'].Strings[0]) + m[2] * HexD(o.Arrays['tp'].Strings[1]) + m[4];
    uy := m[1] * HexD(o.Arrays['tp'].Strings[0]) + m[3] * HexD(o.Arrays['tp'].Strings[1]) + m[5];
    n := 0;
    nr := 0;
    for y := Round(uy) - 12 to Round(uy) + 12 do
      for x := 0 to FBmp.Width - 1 do
      begin
        px := FBmp.GetPixel(x, y);
        if not ((px.red > 200) and (px.green < 90) and (px.blue < 90)) then Continue;
        if lab = 0 then
        begin
          if (x <= ux + 1) and (x >= ux - 120) then Inc(n)
          else if (x > ux + 3) and (x < ux + 80) then Inc(nr);
        end
        else if x >= ux - 1 then Inc(n);
      end;
    AssertTrue(Format('label %d: %d red px by its place (%g,%g)', [lab, n, ux, uy]), n > 30);
    AssertEquals(Format('label %d: red px right of its place', [lab]), 0, nr);
    { and its element's bounds are where it is drawn (a dirty block that
      meets the words redraws them) }
    nr := 0;
    for k := 0 to FChart.Frame.Count - 1 do
    begin
      el := FChart.Frame.Element(k);
      if (el.Caption.Text <> 'W2.00W') and (el.Caption.Text <> 'W8.00W') then Continue;
      if (lab = 0) <> (el.Caption.Text = 'W2.00W') then Continue;
      b := TyShapeBounds(el.Shape);
      Inc(nr);
      if lab = 0 then
        AssertTrue(Format('label 0: its bounds (%g,%g)-(%g,%g) hold its words', [b.Left, b.Top, b.Right, b.Bottom]),
          (b.Left <= ux - 10) and (b.Right >= ux - 10) and (b.Top <= uy) and (b.Bottom >= uy))
      else
        AssertTrue(Format('label 1: its bounds (%g,%g)-(%g,%g) hold its words', [b.Left, b.Top, b.Right, b.Bottom]),
          (b.Left <= ux + 10) and (b.Right >= ux + 10) and (b.Top <= uy) and (b.Bottom >= uy));
    end;
    AssertEquals(Format('label %d: its element', [lab]), 1, nr);
  end;
end;

{ [R7-AF] AN UNPLACED SLIDER'S CLIPS TURN WITH THE TRANSFORM (af-dz-turn,
  af-dz-skew): the data shadow's area beside the window and in it, each in
  its group's clip -- the rect in the shadow's own frame under the
  transform the canvas had (the record's), a turned or sheared one, not the
  box round it. Points 3 frame px over the slider's foot, 4 to either side of
  each window end, are the green beside the window and the yellow in it }
procedure TAdvChartLinesCanvasOracleTest.TestAnUnplacedSlidersTurnedClip;
const
  cX: array[0..7] of Double = (58, 60, 68, 70, 250, 252, 260, 262);
var
  cs, els: TJSONArray;
  c, o: TJSONObject;
  i, k, pass: Integer;
  px: TBGRAPixel;
  m: array[0..5] of Double;
  dx, dy: Double;
  id, bad: string;
  yellow: Boolean;
begin
  cs := TJSONObject(FRoot).Arrays['charts'];
  bad := '';
  for pass := 0 to 1 do
  begin
    if pass = 0 then id := 'af-dz-turn' else id := 'af-dz-skew';
    c := nil;
    for i := 0 to cs.Count - 1 do
      if cs.Objects[i].Strings['id'] = id then c := cs.Objects[i];
    AssertTrue(id, c <> nil);
    FreeAndNil(FChart);
    FChart := TLcProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := cT0;
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    FBmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
    els := c.Arrays['frames'].Objects[0].Arrays['els'];
    o := nil;
    for k := 0 to els.Count - 1 do
      if els.Objects[k].Strings['key'] = 'c.dataZoom0.-20.p.0' then o := els.Objects[k].Arrays['ops'].Objects[0];
    AssertTrue('the shadow upstream', o <> nil);
    for k := 0 to 5 do m[k] := HexD(o.Arrays['m'].Strings[k]);
    AssertTrue(id + ': a turned transform upstream', Abs(m[1]) > 0.1);
    { the window's ends: 20% and 80% of 320 }
    for k := 0 to High(cX) do
    begin
      dx := m[0] * cX[k] + m[2] * 3 + m[4];
      dy := m[1] * cX[k] + m[3] * 3 + m[5];
      px := FBmp.GetPixel(Round(dx), Round(dy));
      yellow := (cX[k] > 64) and (cX[k] < 256);
      if (yellow <> (px.red > 200)) or (px.green < 200) or (px.blue > 60) then
        bad := bad + Format(' %s: frame (%g,3) at (%d,%d) is (%d,%d,%d), upstream %s;', [id, cX[k],
          Round(dx), Round(dy), px.red, px.green, px.blue, BoolToStr(yellow, 'yellow', 'green')]);
    end;
  end;
  AssertEquals('the shadows in their turned clips', '', bad);
end;

{ [R7-AF] A HALO OF 'Infinity' HANDS THE CANVAS ITS COLOUR AT THE FIRST PAINT
  (af-label-inf, drawn once): the symbol after it (z 3) whose borderColor no
  parser reads strokes in the label's '#ff00ff' -- before the paint order has
  settled the halo's width once, too }
procedure TAdvChartLinesCanvasOracleTest.TestAnInfiniteHaloHandsItsColourAtOnce;
var
  cs: TJSONArray;
  c: TJSONObject;
  i, k, n: Integer;
  el: TTyChartElement;
begin
  cs := TJSONObject(FRoot).Arrays['charts'];
  c := nil;
  for i := 0 to cs.Count - 1 do
    if cs.Objects[i].Strings['id'] = 'af-label-inf' then c := cs.Objects[i];
  AssertTrue('af-label-inf', c <> nil);
  FreeAndNil(FChart);
  FChart := TLcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := cT0;
  FChart.SetOption(c.Objects['option'].AsJSON, True);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  n := 0;
  for k := 0 to FChart.Frame.Count - 1 do
  begin
    el := FChart.Frame.Element(k);
    if (el.Datum.SeriesIndex <> 2) or (el.Caption.Text <> '') then Continue;
    Inc(n);
    AssertEquals('the symbol after the label strokes in its halo''s colour', Integer($FFFF00FF),
      Integer(el.Style.StrokeColor));
  end;
  AssertTrue('the symbol after the label', n > 0);
end;

{ [R7-AF] A RADAR'S RINGS OF ONE COLOUR ARE ONE PATH upstream (mergePath), its
  gradient over the merged path's box (af-grad-radar-split): every ring the
  port draws with a gradient takes the gradient of one of upstream's two
  merged paths -- the stroke op's arguments through its transform }
procedure TAdvChartLinesCanvasOracleTest.TestTheRadarRingsShareTheirGradient;
var
  cs, els: TJSONArray;
  c, o: TJSONObject;
  i, k, j, n, rings: Integer;
  el: TTyChartElement;
  m: array[0..5] of Double;
  x1, y1, x2, y2, gr: Double;
  ux: array[0..1, 0..3] of Double;
  a: TJSONArray;
  ok: Boolean;
  bad: string;
begin
  cs := TJSONObject(FRoot).Arrays['charts'];
  c := nil;
  for i := 0 to cs.Count - 1 do
    if cs.Objects[i].Strings['id'] = 'af-grad-radar-split' then c := cs.Objects[i];
  AssertTrue('af-grad-radar-split', c <> nil);
  els := c.Arrays['frames'].Objects[0].Arrays['els'];
  n := 0;
  for k := 0 to els.Count - 1 do
    if Copy(els.Objects[k].Strings['key'], 1, 13) = 'c.radar0.0.p.' then
    begin
      AssertTrue('two merged paths upstream', n < 2);
      o := els.Objects[k].Arrays['ops'].Objects[0];
      for j := 0 to 5 do m[j] := HexD(o.Arrays['m'].Strings[j]);
      a := o.Objects['so'].Arrays['a'];
      ux[n, 0] := m[0] * HexD(a.Strings[0]) + m[2] * HexD(a.Strings[1]) + m[4];
      ux[n, 1] := m[1] * HexD(a.Strings[0]) + m[3] * HexD(a.Strings[1]) + m[5];
      ux[n, 2] := m[0] * HexD(a.Strings[2]) + m[2] * HexD(a.Strings[3]) + m[4];
      ux[n, 3] := m[1] * HexD(a.Strings[2]) + m[3] * HexD(a.Strings[3]) + m[5];
      Inc(n);
    end;
  AssertEquals('the merged paths upstream', 2, n);
  FreeAndNil(FChart);
  FChart := TLcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := cT0;
  FChart.SetOption(c.Objects['option'].AsJSON, True);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  rings := 0;
  bad := '';
  for k := 0 to FChart.Frame.Count - 1 do
  begin
    el := FChart.Frame.Element(k);
    if (el.Datum.SeriesIndex >= 0) or (el.Style.StrokeGradient.Kind = cgkNone) then Continue;
    Inc(rings);
    TyResolveGradientXYWH(el.Style.StrokeGradient, TyElementGradientBox(el, 96), x1, y1, x2, y2, gr);
    ok := False;
    for j := 0 to n - 1 do
      if (Abs(x1 - ux[j, 0]) < 1e-6) and (Abs(y1 - ux[j, 1]) < 1e-6) and (Abs(x2 - ux[j, 2]) < 1e-6)
        and (Abs(y2 - ux[j, 3]) < 1e-6) then ok := True;
    if not ok then bad := bad + Format(' ring %d: (%g,%g)-(%g,%g);', [k, x1, y1, x2, y2]);
  end;
  AssertEquals('the radar''s rings with a gradient', 4, rings);
  AssertEquals('each ring in its merged path''s gradient', '', bad);
end;

{ [R7-AE] AN UNPLACED SLIDER IS FOUND BY NOTHING (ae-dz-inf-*, ac-dz-inf):
  every element of it has a transform that is no number, and
  Path.contain takes the point to NaN -- upstream's findHover at each probe
  is the target the chart's own pointer finds (a slider's part, a series'
  element, or nothing), and a press there moves no window }
procedure TAdvChartLinesCanvasOracleTest.TestAnUnplacedSlidersPointerAsUpstream;
var
  cs, hits, h: TJSONArray;
  c: TJSONObject;
  i, k, nCases: Integer;
  id, want, got: string;
  x, y: Double;
  st0, st1: TTyDzSliderState;
begin
  FBad := 0;
  FCompared := 0;
  FReport := '';
  nCases := 0;
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if Copy(id, 1, 10) <> 'ae-dz-inf-' then Continue;
    if c.Arrays['frames'].Objects[0].Find('hits') = nil then Continue;
    Inc(nCases);
    FreeAndNil(FChart);
    FChart := TLcProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := cT0;
    FChart.DataZoomNow := cT0;
    FChart.TooltipNow := cT0;
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    AssertEquals(id + ' parses', '', FChart.OptionError);
    FBmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
    hits := c.Arrays['frames'].Objects[0].Arrays['hits'];
    for k := 0 to hits.Count - 1 do
    begin
      h := hits.Arrays[k];
      x := HexD(h.Strings[0]);
      y := HexD(h.Strings[1]);
      if h.Items[2].JSONType = jtNull then want := ''
      else if Copy(h.Strings[2], 1, 11) = 'c.dataZoom0' then want := 'slider'
      else want := 'other';
      FChart.DataZoomPointer(dpMove, x, y, [], 0);
      got := FChart.DataZoomHoverName;
      if Copy(got, 1, 2) = 'dz' then got := 'slider';
      Inc(FCompared);
      if got <> want then
        Miss(Format('%s (%g,%g): the pointer finds "%s", upstream "%s"', [id, x, y, got, want]));
      { and a press where upstream finds no part of it moves nothing }
      if want = 'slider' then Continue;
      st0 := FChart.DataZoomSliderState(0);
      FChart.DataZoomPointer(dpDown, x, y, [], 0);
      FChart.DataZoomPointer(dpMove, x + 7, y, [], 0);
      FChart.DataZoomPointer(dpUp, x + 7, y, [], 0);
      FChart.DataZoomPointer(dpClick, x + 7, y, [], 0);
      FChart.DataZoomTick(cT0 + 1000);
      st1 := FChart.DataZoomSliderState(0);
      Inc(FCompared);
      if (st0.Ends[0] <> st1.Ends[0]) or (st0.Ends[1] <> st1.Ends[1])
        or (st0.Range[0] <> st1.Range[0]) or (st0.Range[1] <> st1.Range[1]) then
        Miss(Format('%s (%g,%g): a press moved the window', [id, x, y]));
    end;
  end;
  FreeAndNil(FChart);
  AssertTrue('cases', nCases >= 1);
  if FBad > 0 then
    Fail(Format('%d of %d differ:%s', [FBad, FCompared, FReport]));
end;

{ [R7-AC] A TOOLTIP'S TEXT CASTS textStyle's SHADOW, in both modes: black
  text at 20 px on white, its shadow blue, offset 8 px down at a blur of 1
  (html's text-shadow, richText's spans): the box differs from the same box
  with a blur of nought (no shadow), by the shadow's pixels -- bluish ones
  where the text is not (nothing at all differed before: the option had no
  effect). Two renders compared, as the text's own edges are coloured where
  the text is drawn with subpixel coverage }
procedure TAdvChartLinesCanvasOracleTest.TestATipsTextShadowIsDrawn;
var
  mode, pass: Integer;
  px, pa: TBGRAPixel;
  bb: TTyRectF;
  x, y, n: Integer;
  m, blur: string;
  a: TBGRABitmap;
begin
  a := TBGRABitmap.Create(FBmp.Width, FBmp.Height, BGRA(255, 255, 255, 255));
  try
    for mode := 0 to 1 do
    begin
      if mode = 0 then m := 'html' else m := 'richText';
      for pass := 0 to 1 do
      begin
        if pass = 0 then blur := '0' else blur := '1';
        FreeAndNil(FChart);
        FChart := TLcProbe.Create(FForm);
        FChart.Parent := FForm;
        FChart.Controller := FCtl;
        FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
        FChart.SetOption('{"animation":false,"xAxis":{"type":"value","min":0,"max":10,"show":false},'
          + '"yAxis":{"type":"value","min":0,"max":10,"show":false},'
          + '"tooltip":{"renderMode":"' + m + '","showDelay":0,"transitionDuration":0,"position":[60,60],'
          + '"backgroundColor":"#ffffff","borderColor":"#ffffff","shadowBlur":0,"shadowOffsetX":0,"shadowOffsetY":0,'
          + '"padding":[4,10,16,10],"formatter":"MMMM","textStyle":{"color":"#000000","fontSize":20,'
          + '"textShadowColor":"#0000ff","textShadowBlur":' + blur + ',"textShadowOffsetY":8}},'
          + '"series":[{"type":"scatter","symbolSize":4,"data":[[9,9]]}]}', True);
        FBmp.Fill(BGRA(255, 255, 255, 255));
        FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
        FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
        FBmp.Fill(BGRA(255, 255, 255, 255));
        FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
        bb := FChart.TipFill;
        AssertTrue(m + ': a box drawn', TyRectFIsValid(bb));
        if pass = 0 then a.PutImage(0, 0, FBmp, dmSet);
      end;
      n := 0;
      for y := Round(bb.Top) to Round(bb.Bottom) - 1 do
        for x := Round(bb.Left) to Round(bb.Right) - 1 do
        begin
          px := FBmp.GetPixel(x, y);
          pa := a.GetPixel(x, y);
          if not (px = pa) and (px.blue > px.red + 40) and (pa.red > 200) and (pa.blue > 200) then Inc(n);
        end;
      AssertTrue(Format('%s: the text''s blue shadow drawn (%d px)', [m, n]), n > 20);
    end;
  finally
    a.Free;
  end;
end;

{ [R7-AC] A RICHTEXT MARKER IN A COLOUR NO PARSER READS IS DRAWN in the
  fill the canvas had -- the header's span before it, '#333333': the box
  looks as it does for a series in '#333333' itself, pixel for pixel (it
  was not drawn) }
procedure TAdvChartLinesCanvasOracleTest.TestARichTipsRefusedMarkerIsDrawn;
var
  a: TBGRABitmap;
  bb: TTyRectF;
  pass, x, y, n: Integer;
  c: string;
begin
  a := TBGRABitmap.Create(FBmp.Width, FBmp.Height, BGRA(255, 255, 255, 255));
  try
    for pass := 0 to 1 do
    begin
      if pass = 0 then c := 'nope' else c := '#333333';
      FreeAndNil(FChart);
      FChart := TLcProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
      FChart.SetOption('{"animation":false,"xAxis":{"type":"value","min":0,"max":10,"show":false},'
        + '"yAxis":{"type":"value","min":0,"max":10,"show":false},'
        + '"tooltip":{"renderMode":"richText","showDelay":0,"transitionDuration":0,"position":[100,60],'
        + '"backgroundColor":"#ffffff","borderColor":"#0000ff","shadowBlur":0,"shadowOffsetX":0,"shadowOffsetY":0,'
        + '"textStyle":{"color":"#333333"}},'
        + '"series":[{"type":"scatter","name":"S","symbolSize":4,"itemStyle":{"color":"' + c + '"},'
        + '"data":[[9,9]]}]}', True);
      FBmp.Fill(BGRA(255, 255, 255, 255));
      FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
      FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
      FBmp.Fill(BGRA(255, 255, 255, 255));
      FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
      bb := FChart.TipFill;
      AssertTrue(c + ': a box drawn', TyRectFIsValid(bb));
      if pass = 0 then a.PutImage(0, 0, FBmp, dmSet);
    end;
    n := 0;
    for y := Round(bb.Top) to Round(bb.Bottom) - 1 do
      for x := Round(bb.Left) to Round(bb.Right) - 1 do
        if not (a.GetPixel(x, y) = FBmp.GetPixel(x, y)) then Inc(n);
    AssertEquals('the box as for a series in #333333', 0, n);
  finally
    a.Free;
  end;
end;

{ [R7-AC] A LABEL'S BOX IN COLOURS NO PARSER READS: its background Rect
  is filled all the same, in the fill the canvas had (the symbol's red),
  and its shadow cast in the shadowColor the canvas had (the symbol's
  green) -- not left out, not zrender's '#000'. A scatter symbol in red
  with a green shadow; its label to the right, the box's backgroundColor
  and shadowColor 'nope', the shadow 12 px down: the label looks as it does
  with '#ff0000' and '#00ff00' written, pixel for pixel (the box was not
  drawn) }
procedure TAdvChartLinesCanvasOracleTest.TestALabelBoxsRefusedColoursAreTheCanvas;
var
  a: TBGRABitmap;
  pass, x, y, n, red: Integer;
  bg, sh: string;
  px: TBGRAPixel;
begin
  a := TBGRABitmap.Create(FBmp.Width, FBmp.Height, BGRA(255, 255, 255, 255));
  try
    for pass := 0 to 1 do
    begin
      if pass = 0 then
      begin
        bg := 'nope';
        sh := 'nope';
      end
      else
      begin
        bg := '#ff0000';
        sh := '#00ff00';
      end;
      FreeAndNil(FChart);
      FChart := TLcProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
      FChart.SetOption('{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0},'
        + '"xAxis":{"type":"value","min":0,"max":400,"show":false},'
        + '"yAxis":{"type":"value","min":0,"max":300,"show":false,"inverse":true},'
        + '"series":[{"type":"scatter","symbolSize":10,"data":[[100,100]],'
        + '"itemStyle":{"color":"#ff0000","shadowBlur":3,"shadowColor":"#00ff00"},'
        + '"label":{"show":true,"position":"right","distance":30,"formatter":"Ab","color":"#000000","fontSize":16,'
        + '"backgroundColor":"' + bg + '","padding":8,"shadowBlur":2,"shadowColor":"' + sh + '","shadowOffsetY":12}}]}',
        True);
      FBmp.Fill(BGRA(255, 255, 255, 255));
      FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
      if pass = 0 then a.PutImage(0, 0, FBmp, dmSet);
    end;
    n := 0;
    red := 0;
    for y := 70 to 140 do
      for x := 120 to 230 do
      begin
        if not (a.GetPixel(x, y) = FBmp.GetPixel(x, y)) then Inc(n);
        px := FBmp.GetPixel(x, y);
        if (px.red > 200) and (px.red > px.green + 100) then Inc(red);
      end;
    AssertTrue(Format('the written box drawn (%d px)', [red]), red > 40);
    AssertEquals('the box and its shadow as written', 0, n);
  finally
    a.Free;
  end;
end;

{ [R7-AC] A RICHTEXT TOOLTIP'S BORDER IS OUTSIDE ITS BOX: zrender's Text
  background strokes first, at twice TooltipRichContent's width of 1, and
  fills over it -- the inner half under the fill, the outer pixel round
  the box. At position [100, 60] with no shadow the box is filled from
  (101, 61): column 100 is the border's blue, column 101 the white fill,
  row 60 blue and row 61 white (a written borderWidth of 6 changes
  nothing: richText's is 1) }
procedure TAdvChartLinesCanvasOracleTest.TestARichTipsBorderIsOutsideItsBox;
var px: TBGRAPixel; bb: TTyRectF; y, x: Integer;
begin
  FreeAndNil(FChart);
  FChart := TLcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
  FChart.SetOption('{"animation":false,"xAxis":{"type":"value","min":0,"max":10,"show":false},'
    + '"yAxis":{"type":"value","min":0,"max":10,"show":false},'
    + '"tooltip":{"renderMode":"richText","showDelay":0,"transitionDuration":0,"position":[100,60],'
    + '"backgroundColor":"#ffffff","borderColor":"#0000ff","borderWidth":6,"shadowBlur":0,'
    + '"shadowOffsetX":0,"shadowOffsetY":0,"formatter":"Abc"},'
    + '"series":[{"type":"scatter","symbolSize":4,"data":[[9,9]]}]}', True);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  bb := FChart.TipFill;
  AssertTrue('a box drawn', TyRectFIsValid(bb));
  AssertEquals('filled from x 101', 101, bb.Left, 1e-9);
  AssertEquals('filled from y 61', 61, bb.Top, 1e-9);
  y := Round((bb.Top + bb.Bottom) / 2);
  px := FBmp.GetPixel(100, y);
  AssertTrue(Format('column 100 the border: (%d,%d,%d)', [px.red, px.green, px.blue]),
    (px.blue > 200) and (px.red < 60) and (px.green < 60));
  px := FBmp.GetPixel(101, y);
  AssertTrue(Format('column 101 the fill: (%d,%d,%d)', [px.red, px.green, px.blue]),
    (px.red > 230) and (px.green > 230) and (px.blue > 230));
  px := FBmp.GetPixel(99, y);
  AssertTrue(Format('column 99 outside: (%d,%d,%d)', [px.red, px.green, px.blue]),
    (px.red > 230) and (px.green > 230));
  x := Round((bb.Left + bb.Right) / 2);
  px := FBmp.GetPixel(x, 60);
  AssertTrue(Format('row 60 the border: (%d,%d,%d)', [px.red, px.green, px.blue]),
    (px.blue > 200) and (px.red < 60) and (px.green < 60));
  px := FBmp.GetPixel(x, 61);
  AssertTrue(Format('row 61 the fill: (%d,%d,%d)', [px.red, px.green, px.blue]),
    (px.red > 230) and (px.green > 230) and (px.blue > 230));
end;

{ [R7-AA] THE SHADOW IS DRAWN, not only handed on: an x axis line in red,
  2 wide, its lineStyle's shadow blue at an offset of (0, 8) and no blur --
  the canvas draws the line's shape again 8 px under it in the shadow's
  colour. Down the column through the plot's middle: the red row, then,
  eight rows on, the blue one. }
procedure TAdvChartLinesCanvasOracleTest.TestAnAxisPensShadowIsDrawn;
var y, red, blue: Integer; px: TBGRAPixel;
begin
  FreeAndNil(FChart);
  FChart := TLcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
  FChart.SetOption('{"animation":false,"xAxis":{"type":"value","min":0,"max":10,'
    + '"axisLabel":{"show":false},"splitLine":{"show":false},"axisTick":{"show":false},'
    + '"axisLine":{"lineStyle":{"color":"#ff0000","width":2,"shadowColor":"#0000ff",'
    + '"shadowOffsetY":8}}},"yAxis":{"show":false,"type":"value"},"series":[]}', True);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  red := -1;
  blue := -1;
  for y := 0 to FBmp.Height - 1 do
  begin
    px := FBmp.GetPixel(FBmp.Width div 2, y);
    if (red < 0) and (px.red > 200) and (px.green < 60) and (px.blue < 60) then red := y;
    if (blue < 0) and (px.blue > 200) and (px.red < 60) and (px.green < 60) then blue := y;
  end;
  AssertTrue('the line is drawn', red >= 0);
  AssertTrue('its shadow is drawn', blue >= 0);
  AssertEquals('eight rows under it', 8, blue - red);
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
