unit test.advchart.shadows;
{$mode objfpc}{$H+}
{ SHADOWS [R5-A].

  tools/advchart-oracle/shadows.js records, on ECharts 6.1, the canvas shadow
  every element of a set of charts carries in its style -- shadowBlur,
  shadowOffsetX / Y and shadowColor as zrender's bindCommonProps hands them
  to the canvas -- at rest and, where a case says, after a highlight: bars,
  a line's polyline, area and symbols, scatter and effectScatter symbols (and
  the ripples, which carry none), pie slices and their label lines, funnel
  trapezoids, a gauge's bands, split lines, ticks, anchor, pointers and
  progress arcs, radar items, candlesticks, boxplots (their emphasis
  default), heatmap cells, graph nodes and edges, tree nodes and edges,
  treemap rects, sunburst pieces, sankey nodes and links, themeRiver layers,
  parallel lines, lines, pictorial glyphs, polar bars and rich-text TSpans.
  The replay holds the control's elements to them bit for bit.

  The picture is the painter's: TAdvChartShadowsTest holds what a shadow
  draws -- a Gaussian of deviation blur / 2 under the shape, moved by the
  offset, through the clip, each fill and each stroke its own, nothing for a
  decal, a text's from its glyphs -- and that nothing else draws any
  differently. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes, BGRACanvas2D, BGRAPen,
     tyControls.Types, tyControls.Controller, tyControls.Painter,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Render,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Large,
     tyControls.AdvanceChart.VisualMap, tyControls.AdvanceChart.VisualMapView,
     tyControls.AdvanceChart.Geo,
     tyControls.AdvanceChart,
     test.advchart.graphic;
type
  { a chart whose animation frame the test reads }
  TShProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TAdvChartShadowsOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxProbe;
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    procedure CheckOne(const AWhat: string; const AStyle: TTyChartElementStyle;
      AItem: TJSONObject);
    procedure CheckItems(AItems: TJSONArray; const APhase: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheShadowsAreUpstreams;
    procedure TestTheComponentsShadowsAreUpstreams;
    procedure TestTheLayersAreUpstreams;
    procedure TestAStatesShadowTweensAsUpstreams;
  end;

  { what a shadow draws }
  TAdvChartShadowsTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TShProbe;
    procedure NewChart(AW, AH: Integer; AMode: TTyChartAnimationMode = camOff);
    function Draw: TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheBlurIsAGaussianOfHalfTheBlur;
    procedure TestAShortBlurIsTheGaussianItself;
    procedure TestTheBoxesAreTheSvgSpecifications;
    procedure TestAWideBlurIsStillTheGaussian;
    procedure TestTheOffsetIsInDeviceSpace;
    procedure TestTheShapeDrawsAsWithoutOne;
    procedure TestTheShapeIsPinnedAfterItsShadow;
    procedure TestEachFillAndEachStrokeCastsItsOwn;
    procedure TestTheShadowKeepsToTheClip;
    procedure TestThePaintsAlphaCastsIt;
    procedure TestNoShadowDrawsNothing;
    procedure TestAMaskCastsItsShadow;
    procedure TestABarCastsItsShadowUnderIt;
    procedure TestADecalCastsNone;
    procedure TestAHoverBringsTheEmphasisShadow;
    procedure TestATextShadowIsBlurred;
    procedure TestALargeBatchCastsOneShadow;
    procedure TestTheShadowFollowsTheDeviceScale;
    procedure TestLighterAddsAndABlendModeMixes;
    procedure TestAHigherZLevelIsDrawnAndHitOnTop;
    procedure TestTheIndicatorCastsItsDefaultShadow;
    procedure TestATitlesFrameCastsItsShadow;
  end;

implementation

procedure TShProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TShProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TShProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TShProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-shadows.json';
end;

function LoadText(const APath: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := CompareMem(@A, @B, SizeOf(Double));
end;

{ ==================== the oracle ==================== }

procedure TAdvChartShadowsOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := GetJSON(LoadText(FixturePath));
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartShadowsOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartShadowsOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 60 then FReport := FReport + LineEnding + '  ' + FWhere + ': ' + AWhat;
end;

procedure TAdvChartShadowsOracleTest.NewChart(AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FChart := TGfxProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartShadowsOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ upstream's style as the canvas draws it against the element's: a shadow or
  none -- a colour of no alpha, or nought for the blur and both offsets, is
  none (a negative blur the canvas does not take: nought) -- and where there
  is one, the blur, the offsets bit for bit and the colour }
procedure TAdvChartShadowsOracleTest.CheckOne(const AWhat: string;
  const AStyle: TTyChartElementStyle; AItem: TJSONObject);
var
  b, ox, oy: Double;
  col: string;
  c: TTyChartColor;
  up, here: Boolean;
begin
  b := FromHex(AItem.Strings['blur']);
  ox := FromHex(AItem.Strings['ox']);
  oy := FromHex(AItem.Strings['oy']);
  if IsNan(b) or (b < 0) then b := 0;
  if AItem.Find('color').JSONType = jtString then col := AItem.Strings['color'] else col := '#000';
  if not TyTryParseChartColor(col, c) then c := $FF000000;
  up := ((c shr 24) <> 0) and ((b > 0) or (ox <> 0) or (oy <> 0));
  here := TyStyleHasShadow(AStyle);
  Inc(FCompared);
  if up <> here then
  begin
    Bad(Format('%s: upstream %s a shadow (%g, %g, %g, %s), here %s (%g, %g, %g, %s)',
      [AWhat, BoolToStr(up, 'casts', 'casts no'), b, ox, oy, col,
       BoolToStr(here, 'one', 'none'), AStyle.ShadowBlur, AStyle.ShadowOffsetX,
       AStyle.ShadowOffsetY, IntToHex(AStyle.ShadowColor, 8)]));
    Exit;
  end;
  if not up then Exit;
  Inc(FCompared, 4);
  if not SameBits(AStyle.ShadowBlur, b) then
    Bad(Format('%s: blur %g, upstream %g', [AWhat, AStyle.ShadowBlur, b]));
  if not SameBits(AStyle.ShadowOffsetX, ox) then
    Bad(Format('%s: offsetX %g, upstream %g', [AWhat, AStyle.ShadowOffsetX, ox]));
  if not SameBits(AStyle.ShadowOffsetY, oy) then
    Bad(Format('%s: offsetY %g, upstream %g', [AWhat, AStyle.ShadowOffsetY, oy]));
  if AStyle.ShadowColor <> c then
    Bad(Format('%s: colour %s, upstream %s', [AWhat, IntToHex(AStyle.ShadowColor, 8), col]));
end;

procedure TAdvChartShadowsOracleTest.CheckItems(AItems: TJSONArray; const APhase: string);
var
  k, j, s, i, sub, n, m: Integer;
  it: TJSONObject;
  role, what, txt: string;
  el: TTyChartElement;
  list: TTyPaintList;
  found: Boolean;
  st: TTyChartElementStyle;
  pc: TTyRtPiece;

  function Plain(const AE: TTyChartElement): Boolean;
  begin
    Result := (AE.Caption.FontSizeLogical <= 0) and not AE.IsGuide;
  end;

  { each element of the list that answers the record (none must be missing) }
  procedure Each(AMatch: Boolean);
  begin
    if not AMatch then Exit;
    found := True;
    Inc(m);
    CheckOne(what, el.Style, it);
  end;

begin
  list := FChart.List;
  for k := 0 to AItems.Count - 1 do
  begin
    it := AItems.Objects[k];
    role := it.Strings['role'];
    s := it.Integers['s'];
    i := it.Integers['i'];
    if it.Find('sub') <> nil then sub := it.Integers['sub'] else sub := -1;
    what := Format('%s %s s%d i%d', [APhase, role, s, i]);
    if sub >= 0 then what := what + ' sub' + IntToStr(sub);
    found := False;
    m := 0;
    { a label's box rects: its rect pieces, the block's first }
    if role = 'box' then
    begin
      for j := 0 to list.Count - 1 do
      begin
        el := list.Element(j);
        if (el.Anim.Role <> carLabel) or (el.Datum.SeriesIndex <> s)
          or (el.Datum.DataIndex <> i) then Continue;
        m := 0;
        for n := 0 to High(el.Caption.RtPieces) do
        begin
          pc := el.Caption.RtPieces[n];
          if pc.Kind <> rpkRect then Continue;
          if m = sub then
          begin
            found := True;
            st := Default(TTyChartElementStyle);
            if pc.HasShadow then
            begin
              st.ShadowBlur := pc.ShadowBlur;
              st.ShadowOffsetX := pc.ShadowOffsetX;
              st.ShadowOffsetY := pc.ShadowOffsetY;
              st.ShadowColor := pc.ShadowColor;
            end;
            CheckOne(what, st, it);
          end;
          Inc(m);
        end;
      end;
      if not found then Bad(what + ': no such box');
      Continue;
    end;
    { a rich label's TSpans: its pieces of that text }
    if role = 'span' then
    begin
      txt := it.Strings['text'];
      for j := 0 to list.Count - 1 do
      begin
        el := list.Element(j);
        if (el.Anim.Role <> carLabel) or (el.Datum.SeriesIndex <> s)
          or (el.Datum.DataIndex <> i) then Continue;
        for n := 0 to High(el.Caption.RtPieces) do
        begin
          pc := el.Caption.RtPieces[n];
          if (pc.Kind <> rpkText) or (pc.Text <> txt) then Continue;
          found := True;
          st := Default(TTyChartElementStyle);
          if pc.HasShadow then
          begin
            st.ShadowBlur := pc.ShadowBlur;
            st.ShadowOffsetX := pc.ShadowOffsetX;
            st.ShadowOffsetY := pc.ShadowOffsetY;
            st.ShadowColor := pc.ShadowColor;
          end;
          CheckOne(what, st, it);
        end;
        { a plain label (no rich block): no piece -- its words carry no
          shadow then }
        if (Length(el.Caption.RtPieces) = 0) and (el.Caption.Text = txt) then
        begin
          found := True;
          CheckOne(what, Default(TTyChartElementStyle), it);
        end;
      end;
      if not found then Bad(what + ': no such text');
      Continue;
    end;
    for j := 0 to list.Count - 1 do
    begin
      el := list.Element(j);
      if role = 'bar' then Each((el.Anim.Role = carBar) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'lineRun' then Each((el.Anim.Role = carLineRun) and (el.Anim.Series = s))
      else if role = 'lineArea' then Each((el.Anim.Role = carLineArea) and (el.Anim.Series = s))
      else if role = 'lineSymbol' then Each((el.Anim.Role = carLineSymbol) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'symbol' then Each((el.Anim.Role = carSymbol) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'effectSymbol' then Each((el.Anim.Role = carEffectSymbol) and (el.Anim.Series = s) and (el.Anim.Index = i))
      { every ripple of the symbol }
      else if role = 'ripple' then Each((el.Anim.Role = carRipple) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'sector' then Each((el.Anim.Role = carSector) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'guide' then Each(el.IsGuide and (el.Datum.SeriesIndex = s) and (el.Datum.DataIndex = i))
      else if role = 'funnel' then Each((el.Anim.Role = carFunnel) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'gaugePointer' then Each((el.Anim.Role = carGaugePointer) and (el.Anim.Series = s) and (el.Anim.Index = i))
      { the arc and its round ends }
      else if role = 'gaugeProgress' then Each((el.Anim.Role in [carGaugeProgress, carGaugeCap]) and (el.Anim.Series = s) and (el.Anim.Index = i))
      { the dial's parts: every one of the kind, against the first record of it }
      else if role = 'gaugeBand' then Each((i = 0) and Plain(el) and (el.Datum.SeriesIndex < 0)
        and (el.Shape.Kind = cskSector) and el.Silent)
      else if role = 'gaugeSplit' then Each((i = 0) and Plain(el) and (el.Datum.SeriesIndex < 0)
        and (el.Shape.Kind = cskPolyline) and (el.Style.StrokeWidthLogical = 3))
      else if role = 'gaugeTick' then Each((i = 0) and Plain(el) and (el.Datum.SeriesIndex < 0)
        and (el.Shape.Kind = cskPolyline) and (el.Style.StrokeWidthLogical = 1))
      else if role = 'gaugeAnchor' then Each(Plain(el) and (el.Datum.SeriesIndex < 0)
        and el.Silent and el.Style.HasFill and not (el.Shape.Kind in [cskSector, cskPolyline])
        and (el.Anim.Role = carNone))
      else if role = 'radarLine' then Each((el.Anim.Role = carRadarLine) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'radarArea' then Each((el.Anim.Role = carRadarArea) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'radarSymbol' then Each(Plain(el) and (el.Datum.SeriesIndex = s) and (el.Datum.DataIndex = i)
        and (el.Anim.Sub = sub + 1) and not (el.Anim.Role in [carRadarLine, carRadarArea]))
      { the body and both wicks }
      else if role = 'candle' then Each((el.Anim.Role in [carCandleBody, carCandleWickHigh, carCandleWickLow])
        and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'boxplot' then Each((el.Anim.Role = carBoxplot) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'heat' then Each(Plain(el) and (el.Datum.SeriesIndex = s) and (el.Datum.DataIndex = i))
      else if role = 'node' then Each(Plain(el) and (el.Anim.Role = carSymbol) and (el.Datum.SeriesIndex = s)
        and not el.Datum.IsEdge and (el.Datum.DataIndex = i))
      else if role = 'edge' then Each(Plain(el) and el.Datum.IsEdge and (el.Datum.SeriesIndex = s)
        and (el.Datum.DataIndex = i) and not el.Silent)
      else if role = 'treeNode' then Each((el.Anim.Role = carTreeNode) and (el.Anim.Series = s) and (el.Datum.DataIndex = i))
      else if role = 'treeEdge' then Each((el.Anim.Role = carTreeEdge) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'tmBack' then Each((el.Anim.Role = carTmRect) and (el.Anim.Series = s) and (el.Anim.Sub = 0)
        and (el.Datum.DataIndex = i))
      else if role = 'tmContent' then Each((el.Anim.Role = carTmRect) and (el.Anim.Series = s) and (el.Anim.Sub = 1)
        and (el.Datum.DataIndex = i))
      else if role = 'sun' then Each((el.Anim.Role = carSunPiece) and (el.Datum.SeriesIndex = s) and (el.Datum.DataIndex = i))
      else if role = 'sankeyNode' then Each(Plain(el) and not el.Datum.IsEdge and (el.Datum.SeriesIndex = s)
        and (el.Datum.DataIndex = i) and not el.Silent)
      else if role = 'sankeyEdge' then Each(Plain(el) and el.Datum.IsEdge and (el.Datum.SeriesIndex = s)
        and (el.Datum.DataIndex = i))
      { a chord's sectors and ribbons }
      else if role = 'chordNode' then Each(Plain(el) and not el.Datum.IsEdge and (el.Anim.Role = carChord)
        and (el.Datum.SeriesIndex = s) and (el.Datum.DataIndex = i))
      else if role = 'chordEdge' then Each(Plain(el) and el.Datum.IsEdge and (el.Datum.SeriesIndex = s)
        and (el.Datum.DataIndex = i))
      else if role = 'river' then Each((el.Anim.Role = carRiver) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'parallel' then Each((el.Anim.Role = carParallelLine) and (el.Anim.Series = s) and (el.Datum.DataIndex = i))
      else if role = 'lines' then Each((el.Anim.Role = carLinesLine) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'glyph' then Each((el.Anim.Role = carPictorialGlyph) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else if role = 'polarBar' then Each((el.Anim.Role = carPolarBar) and (el.Anim.Series = s) and (el.Anim.Index = i))
      else
      begin
        Bad(what + ': a role the test does not know');
        Break;
      end;
    end;
    if not found then
    begin
      { the dial's parts are checked by their first record }
      if (Copy(role, 1, 5) = 'gauge') and (i > 0) and (role <> 'gaugePointer')
        and (role <> 'gaugeProgress') then Continue;
      Bad(what + ': no such element');
    end;
  end;
end;

procedure TAdvChartShadowsOracleTest.TestTheShadowsAreUpstreams;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FWhere := cs.Strings['id'];
    NewChart(600, 400);
    FChart.SetOption('{"animation":false,' + Copy(cs.Objects['option'].AsJSON, 2, MaxInt), True);
    RenderNow;
    CheckItems(cs.Arrays['items'], 'rest');
    if cs.Find('highlight') <> nil then
    begin
      FChart.DispatchAction('{"type":"highlight",' + Copy(cs.Objects['highlight'].AsJSON, 2, MaxInt));
      RenderNow;
      CheckItems(cs.Arrays['highlighted'], 'highlighted');
    end;
  end;
  AssertTrue(Format('shadows compared (%d)', [FCompared]), FCompared >= 300);
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s', [FBad, FCompared, FReport]));
end;

{ the distinct shadows a whole chart casts -- every element of the list but the
  words, as the painter draws it -- against upstream's }
procedure TAdvChartShadowsOracleTest.TestTheComponentsShadowsAreUpstreams;
var
  cases, want: TJSONArray;
  cs, w: TJSONObject;
  c, j, k: Integer;
  el: TTyChartElement;
  got, exp: TStringList;
  col: TTyChartColor;

  function Key(ABlur, AOx, AOy: Double; AColour: TTyChartColor): string;
  begin
    Result := IntToHex(PInt64(@ABlur)^, 16) + ',' + IntToHex(PInt64(@AOx)^, 16) + ','
      + IntToHex(PInt64(@AOy)^, 16) + ',' + IntToHex(AColour, 8);
  end;

  procedure Compare(const APhase: string; AWant: TJSONArray);
  var jj, kk: Integer;
  begin
    got.Clear;
    exp.Clear;
    for jj := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(jj);
      if el.Ignore or (el.Caption.FontSizeLogical > 0) then Continue;
      if TyStyleHasShadow(el.Style) then
        got.Add(Key(el.Style.ShadowBlur, el.Style.ShadowOffsetX, el.Style.ShadowOffsetY,
          el.Style.ShadowColor));
    end;
    for kk := 0 to AWant.Count - 1 do
    begin
      w := AWant.Objects[kk];
      if not TyTryParseChartColor(w.Strings['color'], col) then col := $FF000000;
      exp.Add(Key(FromHex(w.Strings['blur']), FromHex(w.Strings['ox']), FromHex(w.Strings['oy']), col));
    end;
    Inc(FCompared);
    if got.Text <> exp.Text then
      Bad(Format('%s: shadows here [%s], upstream [%s]', [APhase, StringReplace(got.CommaText, '"', '', [rfReplaceAll]),
        StringReplace(exp.CommaText, '"', '', [rfReplaceAll])]));
  end;

var maps: TJSONArray;
begin
  cases := TJSONObject(FRoot).Arrays['whole'];
  maps := TJSONObject(FRoot).Arrays['maps'];
  for k := 0 to maps.Count - 1 do
    AssertTrue('the map registers', TyChartRegisterMap(maps.Objects[k].Strings['name'],
      maps.Objects[k].Strings['text']));
  got := TStringList.Create;
  exp := TStringList.Create;
  try
    got.Sorted := True;
    got.Duplicates := dupIgnore;
    exp.Sorted := True;
    exp.Duplicates := dupIgnore;
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      FWhere := cs.Strings['id'];
      NewChart(600, 400);
      FChart.SetOption('{"animation":false,' + Copy(cs.Objects['option'].AsJSON, 2, MaxInt), True);
      RenderNow;
      Compare('rest', cs.Arrays['shadows']);
      if cs.Find('highlight') <> nil then
      begin
        FChart.DispatchAction('{"type":"highlight",' + Copy(cs.Objects['highlight'].AsJSON, 2, MaxInt));
        RenderNow;
        Compare('highlighted', cs.Arrays['highlighted']);
      end;
    end;
  finally
    got.Free;
    exp.Free;
    for k := 0 to maps.Count - 1 do TyChartUnregisterMap(maps.Objects[k].Strings['name']);
  end;
  AssertTrue(Format('charts compared (%d)', [FCompared]), FCompared >= 7);
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s', [FBad, FCompared, FReport]));
end;

{ a series' zlevel on its bars and their labels, its bars' blend, and the
  order: a higher zlevel over every lower one whatever the z; a markPoint's
  own zlevel }
procedure TAdvChartShadowsOracleTest.TestTheLayersAreUpstreams;
var
  cases, items, marks: TJSONArray;
  cs, it: TJSONObject;
  c, k, j, s, i, pos: Integer;
  role, blend: string;
  el: TTyChartElement;
  list: TTyPaintList;
  at: array of Integer;
  found: Boolean;
  maxLower, minUpper, mkMin, restMax: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['layers'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FWhere := cs.Strings['id'];
    NewChart(600, 400);
    FChart.SetOption('{"animation":false,' + Copy(cs.Objects['option'].AsJSON, 2, MaxInt), True);
    RenderNow;
    list := FChart.List;
    SetLength(at, list.Count);
    for pos := 0 to list.Count - 1 do at[list.PaintOrder(pos)] := pos;
    items := cs.Arrays['items'];
    for k := 0 to items.Count - 1 do
    begin
      it := items.Objects[k];
      role := it.Strings['role'];
      s := it.Integers['s'];
      i := it.Integers['i'];
      if it.Find('blend').JSONType = jtString then blend := it.Strings['blend'] else blend := '';
      found := False;
      for j := 0 to list.Count - 1 do
      begin
        el := list.Element(j);
        if (role = 'bar') and not ((el.Anim.Role = carBar) and (el.Anim.Series = s) and (el.Anim.Index = i)) then Continue;
        if (role = 'label') and not ((el.Anim.Role = carLabel) and (el.Datum.SeriesIndex = s)
          and (el.Datum.DataIndex = i)) then Continue;
        found := True;
        Inc(FCompared, 2);
        if el.ZLevel <> it.Integers['zlevel'] then
          Bad(Format('%s s%d i%d: zlevel %d, upstream %d', [role, s, i, el.ZLevel, it.Integers['zlevel']]));
        { what upstream composites by 'lighter' is the element, its label not }
        if (blend = 'lighter') <> (el.Style.Blend = 'lighter') then
          Bad(Format('%s s%d i%d: blend ''%s'', upstream ''%s''', [role, s, i, el.Style.Blend, blend]));
      end;
      if not found then Bad(Format('%s s%d i%d: no such element', [role, s, i]));
    end;
    { the order: series 0 at zlevel 1 over series 1 at z 10 }
    if FWhere = 'zlevel' then
    begin
      maxLower := -1;
      minUpper := MaxInt;
      mkMin := MaxInt;
      restMax := -1;
      for j := 0 to list.Count - 1 do
      begin
        el := list.Element(j);
        if el.Datum.Kind = ctkMarkPoint then
          mkMin := Min(mkMin, at[j])
        else
          restMax := Max(restMax, at[j]);
        if el.Anim.Role <> carBar then Continue;
        if el.Anim.Series = 1 then maxLower := Max(maxLower, at[j])
        else if el.Anim.Series = 0 then minUpper := Min(minUpper, at[j]);
      end;
      Inc(FCompared, 2);
      if not (minUpper > maxLower) then
        Bad(Format('series 0 (zlevel 1) is not over series 1 (z 10): %d, %d', [minUpper, maxLower]));
      marks := cs.Arrays['marks'];
      if (marks.Count > 0) and not (mkMin > restMax) then
        Bad(Format('the markPoint (zlevel 2) is not over everything: %d, %d', [mkMin, restMax]));
      for j := 0 to list.Count - 1 do
      begin
        el := list.Element(j);
        if el.Datum.Kind <> ctkMarkPoint then Continue;
        Inc(FCompared);
        if el.ZLevel <> marks.Objects[0].Integers['zlevel'] then
          Bad(Format('a markPoint element: zlevel %d, upstream %d', [el.ZLevel, marks.Objects[0].Integers['zlevel']]));
      end;
    end;
  end;
  AssertTrue(Format('layers compared (%d)', [FCompared]), FCompared >= 30);
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s', [FBad, FCompared, FReport]));
end;

{ the bar's shadow keys in the drawn frame against upstream's style at every
  sample: the oracle's clock -- settled at T0, then at T1 + t the events of t
  and one frame }
procedure TAdvChartShadowsOracleTest.TestAStatesShadowTweensAsUpstreams;
const
  cT0 = 1700000000000;
var
  cases, samples, events: TJSONArray;
  cs, sm: TJSONObject;
  c, k, e, j: Integer;
  ch: TShProbe;
  bmp: TBGRABitmap;
  t, t1: Double;
  el: TTyChartElement;
  fr: TTyPaintList;
  found: Boolean;
  col: TTyChartColor;
begin
  cases := TJSONObject(FRoot).Arrays['anim'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FWhere := cs.Strings['id'];
    ch := TShProbe.Create(FForm);
    bmp := TBGRABitmap.Create(600, 400);
    try
      ch.Parent := FForm;
      ch.Controller := FCtl;
      ch.AnimationMode := camAlways;
      ch.AnimNow := cT0;
      ch.SetBounds(0, 0, 600, 400);
      ch.Option := cs.Objects['option'].AsJSON;
      ch.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
      t := 16;
      while t <= 5000 do
      begin
        ch.AnimNow := cT0 + t;
        ch.AnimTick(cT0 + t);
        t := t + 250;
      end;
      ch.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
      t1 := cT0 + 10000;
      samples := cs.Arrays['samples'];
      events := cs.Arrays['events'];
      for k := 0 to samples.Count - 1 do
      begin
        sm := samples.Objects[k];
        t := sm.Floats['t'];
        ch.AnimNow := t1 + t;
        for e := 0 to events.Count - 1 do
          if events.Objects[e].Floats['at'] = t then
            ch.DispatchAction(events.Objects[e].Objects['payload'].AsJSON);
        ch.AnimTick(t1 + t);
        ch.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
        fr := ch.Frame;
        found := False;
        for j := 0 to fr.Count - 1 do
        begin
          el := fr.Element(j);
          if (el.Anim.Role <> carBar) or (el.Anim.Series <> 0) or (el.Anim.Index <> 1) then Continue;
          found := True;
          Inc(FCompared, 4);
          if not SameBits(el.Style.ShadowBlur, FromHex(sm.Strings['blur'])) then
            Bad(Format('t %g: blur %g, upstream %g', [t, el.Style.ShadowBlur, FromHex(sm.Strings['blur'])]));
          if not SameBits(el.Style.ShadowOffsetY, FromHex(sm.Strings['oy'])) then
            Bad(Format('t %g: offsetY %g, upstream %g', [t, el.Style.ShadowOffsetY, FromHex(sm.Strings['oy'])]));
          if not SameBits(el.Style.ShadowOffsetX, FromHex(sm.Strings['ox'])) then
            Bad(Format('t %g: offsetX %g, upstream %g', [t, el.Style.ShadowOffsetX, FromHex(sm.Strings['ox'])]));
          { a rest of no shadow is none whatever its colour: compared where
            a blur or an offset draws one }
          if (FromHex(sm.Strings['blur']) > 0) or (FromHex(sm.Strings['oy']) <> 0) then
          begin
            if not TyTryParseChartColor(sm.Strings['color'], col) then col := $FF000000;
            if el.Style.ShadowColor <> col then
              Bad(Format('t %g: colour %s, upstream %s', [t, IntToHex(el.Style.ShadowColor, 8),
                sm.Strings['color']]));
          end;
          Break;
        end;
        if not found then Bad(Format('t %g: no bar in the frame', [t]));
      end;
    finally
      bmp.Free;
      ch.Free;
    end;
  end;
  AssertTrue(Format('samples compared (%d)', [FCompared]), FCompared >= 80);
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s', [FBad, FCompared, FReport]));
end;

{ ==================== the picture ==================== }

procedure TAdvChartShadowsTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
end;

procedure TAdvChartShadowsTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartShadowsTest.NewChart(AW, AH: Integer; AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TShProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := AMode;
  FChart.SetBounds(0, 0, AW, AH);
end;

{ the chart on white; the caller frees }
function TAdvChartShadowsTest.Draw: TBGRABitmap;
begin
  Result := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  FChart.Render(Result.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
end;

{ a painter on a transparent AW x AH bitmap at 96 PPI }
function NewLayer(AW, AH: Integer; out ABmp: TBGRABitmap): TTyPainter;
var sc: TTyCanvasScale;
begin
  ABmp := TBGRABitmap.Create(AW, AH, BGRAPixelTransparent);
  sc.Scale := 1;
  sc.DeviceUnits := False;
  Result := TTyPainter.Create;
  Result.BeginPaintOnScaled(nil, Rect(0, 0, AW, AH), 96, ABmp, sc);
end;

function AlphaAt(B: TBGRABitmap; X, Y: Integer): Integer;
begin
  Result := B.GetPixel(X, Y).alpha;
end;

{ the normal distribution's cumulative }
function Phi(X: Double): Double;
var t, y: Double;
begin
  { Abramowitz-Stegun 7.1.26 through erf, to 1.5e-7 }
  t := 1 / (1 + 0.3275911 * Abs(X) / Sqrt(2));
  y := 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t
    + 0.254829592) * t * Exp(-Sqr(X) / 2);
  if X >= 0 then Result := 0.5 * (1 + y) else Result := 0.5 * (1 - y);
end;

{ A TALL RECT'S SHADOW across its right edge: an edge blurred by a Gaussian of
  deviation blur / 2 is 1 - Phi(d / sigma) at distance d -- the three boxes of
  the SVG specification within a few levels of it }
procedure TAdvChartShadowsTest.TestTheBlurIsAGaussianOfHalfTheBlur;
var
  p: TTyPainter;
  bmp: TBGRABitmap;
  d, a, want, worst: Double;
  x: Integer;
begin
  p := NewLayer(300, 300, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 20, 0, 0);
    p.BeginPath;
    p.RectPath(0, -100, 150, 400);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.EndPaint;
    worst := 0;
    for x := 151 to 190 do
    begin
      d := x + 0.5 - 150;
      a := AlphaAt(bmp, x, 150) / 255;
      want := 1 - Phi(d / 10);
      worst := Max(worst, Abs(a - want));
    end;
    AssertTrue(Format('the edge falls off as a Gaussian of deviation 10 (worst %.4f)', [worst]),
      worst < 0.03);
    AssertTrue('and reaches past 2 sigma', AlphaAt(bmp, 170, 150) > 0);
    AssertEquals('nothing past 4 sigma', 0, AlphaAt(bmp, 200, 150));
  finally
    p.Free;
    bmp.Free;
  end;
end;

{ BELOW A DEVIATION OF 2 the boxes are too coarse: the Gaussian itself }
procedure TAdvChartShadowsTest.TestAShortBlurIsTheGaussianItself;
var
  p: TTyPainter;
  bmp: TBGRABitmap;
  d, a, want, worst: Double;
  x: Integer;
begin
  p := NewLayer(100, 100, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 2, 0, 0);
    p.BeginPath;
    p.RectPath(0, -100, 50, 200);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.EndPaint;
    worst := 0;
    for x := 51 to 55 do
    begin
      d := x + 0.5 - 50;
      a := AlphaAt(bmp, x, 50) / 255;
      want := 1 - Phi(d / 1);
      worst := Max(worst, Abs(a - want));
    end;
    AssertTrue(Format('a deviation of 1, the Gaussian (worst %.4f)', [worst]), worst < 0.02);
    AssertTrue('half a pixel out is blurred, not a hard edge', (AlphaAt(bmp, 50, 50) > 40)
      and (AlphaAt(bmp, 50, 50) < 200));
  finally
    p.Free;
    bmp.Free;
  end;
  { a blur of 1 (a deviation of 0.5): the SVG boxes would be one pixel wide -- no blur at
    all -- the Gaussian puts about a tenth half a pixel out }
  p := NewLayer(100, 100, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 1, 0, 0);
    p.BeginPath;
    p.RectPath(0, -100, 50, 200);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.EndPaint;
    a := AlphaAt(bmp, 50, 50) / 255;
    { the kernel sampled at the pixels: 0.106 (the continuous one 0.159) }
    AssertTrue(Format('a deviation of 0.5 half a pixel out: %.4f', [a]), (a > 0.08) and (a < 0.2));
  finally
    p.Free;
    bmp.Free;
  end;
end;

{ THE SHAPE PINNED AGAIN AFTER ITS SHADOW: BGRA's polygon filler takes its pivots from the
  global Random (spec 211), and the shadow's own fill of the path drew from the pinned
  stream -- the shape's fill after it must start from the pinned seed again, or a polygon
  whose edges tie on a row (a stroke's outline, test.bgrarandompin's) is covered
  differently with a shadow than without. The shadow is cast 500 px down, clear of the
  shape. }
procedure TAdvChartShadowsTest.TestTheShapeIsPinnedAfterItsShadow;

  function Lcg(var AState: LongWord): Double;
  begin
    {$push}{$R-}{$Q-}
    AState := AState * 1664525 + 1013904223;
    {$pop}
    Result := (AState shr 8) / 16777216;
  end;

  procedure Outline(ACtx: TBGRACanvas2D; ASeed: LongWord);
  var
    s: LongWord;
    i: Integer;
    line, wide: ArrayOfTPointF;
    fresh: Boolean;
    stroker: TBGRAPenStroker;
  begin
    s := ASeed;
    SetLength(line, 300);
    for i := 0 to 299 do
      line[i] := PointF(10 + i * 780 / 299, 40 + Lcg(s) * 420);
    stroker := TBGRAPenStroker.Create;
    try
      stroker.JoinStyle := pjsBevel;
      stroker.LineCap := pecFlat;
      wide := stroker.ComputePolylineAutocycle(line, 2);
    finally
      stroker.Free;
    end;
    ACtx.beginPath;
    fresh := True;
    for i := 0 to High(wide) do
      if isEmptyPointF(wide[i]) then fresh := True
      else if fresh then
      begin
        ACtx.moveTo(wide[i]);
        fresh := False;
      end
      else ACtx.lineTo(wide[i]);
    ACtx.closePath;
  end;

  function Paint(AShadow: Boolean): TBGRABitmap;
  var
    ctx: TBGRACanvas2D;
    k: Integer;
  begin
    Result := TBGRABitmap.Create(800, 1000, BGRA(255, 255, 255, 255));
    ctx := Result.Canvas2D;
    if AShadow then
    begin
      ctx.shadowColor(BGRA(0, 0, 0, 255));
      ctx.shadowBlur := 2;
      ctx.shadowOffsetX := 0;
      ctx.shadowOffsetY := 500;
    end;
    ctx.fillStyle(BGRA(40, 40, 160, 140));
    for k := 0 to 1 do
    begin
      Outline(ctx, 1 + 2 * k);
      TyCtxFill(ctx);
    end;
  end;

var
  a, b: TBGRABitmap;
  x, y, diff: Integer;
begin
  a := Paint(False);
  b := Paint(True);
  try
    diff := 0;
    for y := 0 to 499 do
      for x := 0 to 799 do
        if LongWord(a.ScanLine[y][x]) <> LongWord(b.ScanLine[y][x]) then Inc(diff);
    AssertEquals('the outlines over their shadow are the outlines alone', 0, diff);
    diff := 0;
    for y := 540 to 960 do
      for x := 0 to 799 do
        if b.ScanLine[y][x].red < 200 then Inc(diff);
    AssertTrue(Format('and the shadow is there (%d dark pixels)', [diff]), diff > 1000);
  finally
    a.Free;
    b.Free;
  end;
end;

{ THE BOXES ARE THE SVG SPECIFICATION'S: d = floor(sigma * 3 * sqrt(2 pi) / 4 + 0.5) -- a
  blur of 6 (a deviation of 3) is d = 6, where a floor without the half would make it 5 --
  an even d two boxes of d, one centred left of the pixel and one right, and one of d + 1.
  The edge of a tall rect, blurred along x only, against those three boxes run here. }
procedure TAdvChartShadowsTest.TestTheBoxesAreTheSvgSpecifications;

  procedure Box(var A: array of Double; ALeft, ARight: Integer);
  var
    b: array of Double;
    i, j: Integer;
    s: Double;
  begin
    SetLength(b, Length(A));
    for i := 0 to High(A) do
    begin
      s := 0;
      for j := i - ALeft to i + ARight do
        if (j >= 0) and (j <= High(A)) then s := s + A[j];
      b[i] := s / (ALeft + ARight + 1);
    end;
    for i := 0 to High(A) do A[i] := b[i];
  end;

var
  p: TTyPainter;
  bmp: TBGRABitmap;
  want: array of Double;
  x, worst: Integer;
begin
  SetLength(want, 300);
  for x := 0 to 299 do
    if x < 150 then want[x] := 1 else want[x] := 0;
  Box(want, 3, 2);
  Box(want, 2, 3);
  Box(want, 3, 3);
  p := NewLayer(300, 300, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 6, 0, 0);
    p.BeginPath;
    p.RectPath(0, -100, 150, 500);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.EndPaint;
    worst := 0;
    for x := 150 to 165 do
      worst := Max(worst, Abs(AlphaAt(bmp, x, 150) - Round(want[x] * 255)));
    AssertTrue(Format('the three boxes of 6, 6 and 7 (worst %d of 255)', [worst]), worst <= 3);
    AssertTrue('the edge is blurred', AlphaAt(bmp, 150, 150) > 90);
  finally
    p.Free;
    bmp.Free;
  end;
end;

{ A WIDE BLUR (a deviation of 16 and more) is blurred on cells of s x s and read back
  bilinearly: still the Gaussian -- a blur of 64 (deviation 32, cells of 4) along a tall
  edge, and around a small square, whose shadow is a 2-D Gaussian bump, all its ink kept }
procedure TAdvChartShadowsTest.TestAWideBlurIsStillTheGaussian;
var
  p: TTyPainter;
  bmp, mask: TBGRABitmap;
  d, a, want, worst, sum: Double;
  x, y: Integer;
begin
  p := NewLayer(500, 300, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 64, 0, 0);
    p.BeginPath;
    p.RectPath(0, -200, 150, 700);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.EndPaint;
    worst := 0;
    for x := 150 to 260 do
    begin
      d := x + 0.5 - 150;
      a := AlphaAt(bmp, x, 150) / 255;
      want := 1 - Phi(d / 32);
      worst := Max(worst, Abs(a - want));
    end;
    AssertTrue(Format('the edge falls off as a Gaussian of deviation 32 (worst %.4f)', [worst]),
      worst < 0.02);
    { smooth: no step of the cells shows between neighbours }
    worst := 0;
    for x := 151 to 260 do
      worst := Max(worst, Abs(AlphaAt(bmp, x, 150) - AlphaAt(bmp, x - 1, 150)));
    AssertTrue(Format('no step between neighbours (largest %.0f of 255)', [worst]), worst <= 5);
  finally
    p.Free;
    bmp.Free;
  end;
  { a 10 x 10 square under a blur of 40 (deviation 20, cells of 2): its ink spread, not lost }
  p := NewLayer(400, 400, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 40, 0, 120);
    p.BeginPath;
    p.RectPath(195, 75, 205, 85);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.EndPaint;
    sum := 0;
    for y := 100 to 399 do
      for x := 0 to 399 do
        sum := sum + AlphaAt(bmp, x, y) / 255;
    { the tail below half a level rounds away: about 5 % }
    AssertTrue(Format('the ink of the square kept: %.1f of 100', [sum]), (sum > 90) and (sum < 103));
    want := 100 / (2 * Pi * 20 * 20);
    a := AlphaAt(bmp, 200, 200) / 255;
    AssertTrue(Format('the peak a 2-D Gaussian''s: %.4f, want %.4f', [a, want]),
      Abs(a - want) < 0.006);
  finally
    p.Free;
    bmp.Free;
  end;
  { a 40 x 40 square under a blur of 64 (cells of 4), its shadow 220 px down: the bump
    centred where the square's shadow is -- the cells laid on the pixels' centres -- and
    smooth down a column as along a row }
  p := NewLayer(400, 600, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 64, 0, 220);
    p.BeginPath;
    p.RectPath(180, 80, 220, 120);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.EndPaint;
    sum := 0;
    d := 0;
    want := 0;
    for y := 160 to 599 do
      for x := 0 to 399 do
      begin
        a := AlphaAt(bmp, x, y);
        sum := sum + a;
        d := d + a * x;
        want := want + a * y;
      end;
    AssertTrue(Format('the bump''s centre (%.2f, %.2f), the shadow''s (199.5, 319.5)',
      [d / sum, want / sum]), (Abs(d / sum - 199.5) < 0.4) and (Abs(want / sum - 319.5) < 0.4));
    worst := 0;
    for y := 201 to 440 do
      worst := Max(worst, Abs(AlphaAt(bmp, 200, y) - AlphaAt(bmp, 200, y - 1)));
    AssertTrue(Format('no step down a column (largest %.0f of 255)', [worst]), worst <= 3);
  finally
    p.Free;
    bmp.Free;
  end;
  { the same square as a picture's alpha (a text's glyphs): averaged onto the cells here }
  mask := TBGRABitmap.Create(20, 20, BGRAPixelTransparent);
  p := NewLayer(400, 400, bmp);
  try
    mask.FillRect(5, 5, 15, 15, BGRA(255, 255, 255, 255), dmSet);
    p.CastShadowOf(mask, 190, 190, TyRGBA(0, 0, 0, 255), 40, 0, 0);
    p.EndPaint;
    sum := 0;
    for y := 0 to 399 do
      for x := 0 to 399 do
        sum := sum + AlphaAt(bmp, x, y) / 255;
    AssertTrue(Format('a mask''s ink kept: %.1f of 100', [sum]), (sum > 90) and (sum < 103));
    a := AlphaAt(bmp, 200, 200) / 255;
    want := 100 / (2 * Pi * 20 * 20);
    AssertTrue(Format('a mask''s peak: %.4f, want %.4f', [a, want]), Abs(a - want) < 0.006);
  finally
    p.Free;
    bmp.Free;
    mask.Free;
  end;
end;

{ THE OFFSET IN DEVICE SPACE: the canvas does not transform a shadow -- a
  scaled path casts its shadow at the same offset and blur }
procedure TAdvChartShadowsTest.TestTheOffsetIsInDeviceSpace;
var
  p: TTyPainter;
  bmp: TBGRABitmap;
begin
  p := NewLayer(300, 200, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 255, 255), 0, 30, 10);
    p.SaveState;
    p.ScaleBy(2, 2);
    p.BeginPath;
    p.RectPath(50, 50, 60, 60);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.RestoreState;
    p.EndPaint;
    AssertEquals('the shape at twice its path', 255, bmp.GetPixel(110, 110).red);
    AssertEquals('the shadow 30 right, 10 down of it: in device px', 255, bmp.GetPixel(145, 125).blue);
    AssertEquals('...its colour', 0, bmp.GetPixel(145, 125).red);
    AssertEquals('not at twice the offset', 0, AlphaAt(bmp, 165, 135));
    AssertEquals('nothing above the shadow', 0, AlphaAt(bmp, 145, 105));
  finally
    p.Free;
    bmp.Free;
  end;
end;

{ THE SHAPE OVER ITS SHADOW is the shape as it draws without one }
procedure TAdvChartShadowsTest.TestTheShapeDrawsAsWithoutOne;
var
  p: TTyPainter;
  a, b: TBGRABitmap;
  x, y, diff: Integer;
  pa, pb: TBGRAPixel;

  procedure Star(AP: TTyPainter);
  begin
    AP.BeginPath;
    AP.StarPath(60, 60, 50, 20);
    AP.FillPath(TyRGBA(200, 30, 30, 200));
    AP.StrokePath(TyRGBA(30, 30, 200, 255), 3);
  end;

begin
  p := NewLayer(240, 240, a);
  try
    Star(p);
    p.EndPaint;
  finally
    p.Free;
  end;
  p := NewLayer(240, 240, b);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 4, 120, 120);
    Star(p);
    p.EndPaint;
    diff := 0;
    for y := 0 to 115 do
      for x := 0 to 115 do
      begin
        pa := a.GetPixel(x, y);
        pb := b.GetPixel(x, y);
        if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue)
          or (pa.alpha <> pb.alpha) then Inc(diff);
      end;
    AssertEquals('the star over a shadow far off is the star alone', 0, diff);
    AssertTrue('and the shadow is there', AlphaAt(b, 180, 180) > 150);
  finally
    p.Free;
    a.Free;
    b.Free;
  end;
end;

{ EACH FILL AND EACH STROKE CASTS ITS OWN: a ring stroked alone casts a ring }
procedure TAdvChartShadowsTest.TestEachFillAndEachStrokeCastsItsOwn;
var
  p: TTyPainter;
  bmp: TBGRABitmap;
  n: Integer;
begin
  p := NewLayer(200, 200, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 0, 0, 100);
    n := TyPainterShadowsCastForTest;
    p.BeginPath;
    p.CirclePath(50, 50, 30);
    p.StrokePath(TyRGBA(255, 0, 0, 255), 4);
    AssertEquals('a stroke casts one', n + 1, TyPainterShadowsCastForTest);
    p.EndPaint;
    AssertEquals('the ring''s shadow: on the ring', 255, AlphaAt(bmp, 80, 150));
    AssertEquals('...not inside it', 0, AlphaAt(bmp, 50, 150));
  finally
    p.Free;
    bmp.Free;
  end;
  p := NewLayer(200, 200, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 0, 0, 100);
    n := TyPainterShadowsCastForTest;
    p.BeginPath;
    p.CirclePath(50, 50, 30);
    p.FillPath(TyRGBA(0, 255, 0, 255));
    p.StrokePath(TyRGBA(255, 0, 0, 255), 4);
    AssertEquals('a fill and a stroke cast two', n + 2, TyPainterShadowsCastForTest);
    p.EndPaint;
    AssertEquals('the fill''s shadow inside the ring', 255, AlphaAt(bmp, 50, 150));
  finally
    p.Free;
    bmp.Free;
  end;
end;

{ THROUGH THE CLIP: a shadow cast outside the clip is not drawn }
procedure TAdvChartShadowsTest.TestTheShadowKeepsToTheClip;
var
  p: TTyPainter;
  bmp: TBGRABitmap;
begin
  p := NewLayer(200, 100, bmp);
  try
    p.ClipRect(Rect(0, 0, 100, 100));
    p.SetShadow(TyRGBA(0, 0, 0, 255), 0, 60, 0);
    p.BeginPath;
    p.RectPath(20, 20, 60, 60);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.EndPaint;
    AssertEquals('inside the clip', 255, AlphaAt(bmp, 90, 40));
    AssertEquals('outside it nothing', 0, AlphaAt(bmp, 110, 40));
  finally
    p.Free;
    bmp.Free;
  end;
end;

{ THE INK CASTS IT: a translucent fill, the element's alpha, a ramp to
  transparent -- the shadow as strong as the ink over it }
procedure TAdvChartShadowsTest.TestThePaintsAlphaCastsIt;
var
  p: TTyPainter;
  bmp: TBGRABitmap;
  stops: array of TTyGradStop;
begin
  p := NewLayer(300, 300, bmp);
  try
    p.SetShadow(TyRGBA(0, 0, 0, 255), 0, 0, 100);
    p.BeginPath;
    p.RectPath(10, 10, 50, 50);
    p.FillPath(TyRGBA(255, 0, 0, 128));
    AssertTrue('a half-transparent fill casts half', Abs(AlphaAt(bmp, 30, 130) - 128) <= 2);
    p.SaveState;
    p.SetElementAlpha(0.5);
    p.BeginPath;
    p.RectPath(60, 10, 100, 50);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.RestoreState;
    AssertTrue('the element''s alpha halves it', Abs(AlphaAt(bmp, 80, 130) - 128) <= 2);
    SetLength(stops, 2);
    stops[0].Pos := 0;
    stops[0].Color := TyRGBA(0, 0, 255, 255);
    stops[1].Pos := 1;
    stops[1].Color := TyRGBA(0, 0, 255, 0);
    p.BeginPath;
    p.RectPath(110, 10, 290, 50);
    p.FillPathGradient(stops, 110, 0, 290, 0, 0);
    p.EndPaint;
    AssertTrue('under the opaque end, strong', AlphaAt(bmp, 115, 130) > 230);
    AssertTrue('under the clear end, faint', AlphaAt(bmp, 285, 130) < 25);
  finally
    p.Free;
    bmp.Free;
  end;
end;

{ NO SHADOW: a colour of no alpha, all nought, cleared -- the bytes of none }
procedure TAdvChartShadowsTest.TestNoShadowDrawsNothing;
var
  bmps: array[0..3] of TBGRABitmap;
  p: TTyPainter;
  k, n: Integer;
begin
  n := TyPainterShadowsCastForTest;
  for k := 0 to 3 do
  begin
    p := NewLayer(120, 120, bmps[k]);
    try
      case k of
        1: p.SetShadow(TyRGBA(0, 0, 0, 0), 10, 5, 5);
        2: p.SetShadow(TyRGBA(0, 0, 0, 255), 0, 0, 0);
        3:
          begin
            p.SetShadow(TyRGBA(0, 0, 0, 255), 10, 5, 5);
            p.ClearShadow;
          end;
      end;
      p.BeginPath;
      p.StarPath(60, 60, 40, 15);
      p.FillPath(TyRGBA(200, 30, 30, 200));
      p.StrokePath(TyRGBA(30, 30, 200, 255), 2);
      p.EndPaint;
    finally
      p.Free;
    end;
  end;
  try
    AssertEquals('none cast', n, TyPainterShadowsCastForTest);
    for k := 1 to 3 do
      AssertTrue(Format('case %d draws the bytes of none', [k]),
        CompareMem(bmps[0].Data, bmps[k].Data, bmps[0].NbPixels * SizeOf(TBGRAPixel)));
  finally
    for k := 0 to 3 do bmps[k].Free;
  end;
end;

{ A PICTURE'S ALPHA casts the same shadow (a text's glyphs) }
procedure TAdvChartShadowsTest.TestAMaskCastsItsShadow;
var
  p: TTyPainter;
  bmp, mask: TBGRABitmap;
begin
  mask := TBGRABitmap.Create(20, 20, BGRAPixelTransparent);
  p := NewLayer(100, 100, bmp);
  try
    mask.FillRect(5, 5, 15, 15, BGRA(255, 255, 255, 255), dmSet);
    p.CastShadowOf(mask, 10, 10, TyRGBA(0, 128, 0, 255), 0, 30, 0);
    p.EndPaint;
    AssertEquals('the square moved 30 right', 255, AlphaAt(bmp, 50, 20));
    AssertEquals('in the colour', 128, bmp.GetPixel(50, 20).green);
    AssertEquals('not where the mask is', 0, AlphaAt(bmp, 20, 20));
  finally
    p.Free;
    bmp.Free;
    mask.Free;
  end;
end;

function DarkerThan(A, B: TBGRAPixel): Boolean;
begin
  Result := Integer(A.red) + A.green + A.blue < Integer(B.red) + B.green + B.blue - 30;
end;

{ A BAR'S itemStyle SHADOW, its offset to the right: dark beside the bar
  where there is white without it }
procedure TAdvChartShadowsTest.TestABarCastsItsShadowUnderIt;
const
  cOpt = '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value","max":10},"series":[{"type":"bar","barWidth":20,%s"data":[5,7]}]}';
var
  plain, shaded: TBGRABitmap;
  el: TTyChartElement;
  j, x, y: Integer;
  b: TTyRectF;
begin
  NewChart(400, 300);
  FChart.Option := Format(cOpt, ['']);
  plain := Draw;
  NewChart(400, 300);
  FChart.Option := Format(cOpt, ['"itemStyle":{"shadowColor":"#000","shadowOffsetX":8},']);
  shaded := Draw;
  try
    for j := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(j);
      if (el.Anim.Role <> carBar) or (el.Anim.Index <> 0) then Continue;
      AssertTrue('the bar carries the shadow', TyStyleHasShadow(el.Style));
      b := TyShapeBounds(el.Shape);
      x := Round(b.Right) + 4;
      y := Round((b.Top + b.Bottom) / 2);
      AssertTrue('beside the bar dark', DarkerThan(shaded.GetPixel(x, y), plain.GetPixel(x, y)));
      AssertTrue('beyond the offset as before', (shaded.GetPixel(Round(b.Right) + 12, y).red
        = plain.GetPixel(Round(b.Right) + 12, y).red));
      Exit;
    end;
    Fail('no bar');
  finally
    plain.Free;
    shaded.Free;
  end;
end;

{ A DECAL OVER THE FILL CASTS NONE: zrender's decal element nulls it }
procedure TAdvChartShadowsTest.TestADecalCastsNone;
const
  cOpt = '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","itemStyle":{"shadowBlur":4,'
    + '"shadowColor":"#000","borderColor":"#333","borderWidth":1%s},"data":[5,7]}]}';
var
  bmp: TBGRABitmap;
  n, plain, decal: Integer;
begin
  NewChart(400, 300);
  FChart.Option := Format(cOpt, ['']);
  n := TyPainterShadowsCastForTest;
  bmp := Draw;
  bmp.Free;
  plain := TyPainterShadowsCastForTest - n;
  NewChart(400, 300);
  FChart.Option := Format(cOpt, [',"decal":{"symbol":"rect"}']);
  n := TyPainterShadowsCastForTest;
  bmp := Draw;
  bmp.Free;
  decal := TyPainterShadowsCastForTest - n;
  AssertEquals('two bars, a fill and a stroke each', 4, plain);
  AssertEquals('the decal and its pen cast none', plain, decal);
end;

{ THE EMPHASIS SHADOW COMES WITH THE HOVER and goes with it }
procedure TAdvChartShadowsTest.TestAHoverBringsTheEmphasisShadow;
const
  cOpt = '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value","max":10},"series":[{"type":"bar","barWidth":20,'
    + '"emphasis":{"itemStyle":{"shadowColor":"#000","shadowOffsetX":8}},"data":[5,7]}]}';
var
  rest, hover, after: TBGRABitmap;
  el: TTyChartElement;
  j, x, y: Integer;
  b: TTyRectF;
  found: Boolean;
begin
  NewChart(400, 300);
  FChart.Option := cOpt;
  rest := Draw;
  found := False;
  b := Default(TTyRectF);
  for j := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(j);
    if (el.Anim.Role = carBar) and (el.Anim.Index = 0) then
    begin
      b := TyShapeBounds(el.Shape);
      found := True;
    end;
  end;
  AssertTrue('a bar', found);
  x := Round(b.Right) + 4;
  y := Round((b.Top + b.Bottom) / 2);
  FChart.Move(Round((b.Left + b.Right) / 2), y);
  hover := Draw;
  FChart.Move(2, 2);
  after := Draw;
  try
    AssertFalse('at rest no shadow', DarkerThan(rest.GetPixel(x, y), BGRA(250, 250, 250)));
    AssertTrue('hovered, the emphasis shadow', DarkerThan(hover.GetPixel(x, y), rest.GetPixel(x, y)));
    AssertEquals('left, as at rest', rest.GetPixel(x, y).red, after.GetPixel(x, y).red);
  finally
    rest.Free;
    hover.Free;
    after.Free;
  end;
end;

{ A TEXT'S SHADOW IS BLURRED: around a rich token's glyphs a soft fall-off,
  cast once; a blur of 0 casts none whatever its offsets (zrender sets no
  TSpan shadow without a blur) }
procedure TAdvChartShadowsTest.TestATextShadowIsBlurred;
const
  cOpt = '{"animation":false,"graphic":[{"type":"text","left":20,"top":20,"style":'
    + '{"text":"MMM","fontSize":30,"fill":"#ffffff","textShadowColor":"#000",%s}}]}';
var
  bmp, none: TBGRABitmap;
  n, x, y, soft: Integer;
  px: TBGRAPixel;
begin
  NewChart(300, 120);
  FChart.Option := Format(cOpt, ['"textShadowBlur":0,"textShadowOffsetX":3']);
  n := TyPainterShadowsCastForTest;
  none := Draw;
  AssertEquals('no blur, no shadow', n, TyPainterShadowsCastForTest);
  NewChart(300, 120);
  FChart.Option := Format(cOpt, ['"textShadowBlur":6']);
  n := TyPainterShadowsCastForTest;
  bmp := Draw;
  try
    AssertTrue('a blur casts', TyPainterShadowsCastForTest > n);
    { the white glyphs on white: anything grey is the shadow, in levels }
    soft := 0;
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        px := bmp.GetPixel(x, y);
        if (px.red > 60) and (px.red < 230) and (none.GetPixel(x, y).red > 250) then Inc(soft);
      end;
    AssertTrue(Format('a soft shadow round the words (%d grey pixels)', [soft]), soft > 300);
  finally
    bmp.Free;
    none.Free;
  end;
end;

{ A LARGE BATCH WITH A SHADOW is its one path: one cast for its fill }
procedure TAdvChartShadowsTest.TestALargeBatchCastsOneShadow;
var
  bmp: TBGRABitmap;
  n, i: Integer;
  data: string;
begin
  data := '';
  for i := 0 to 399 do
  begin
    if i > 0 then data := data + ',';
    data := data + Format('[%d,%d]', [i mod 20, i div 20]);
  end;
  NewChart(400, 300);
  FChart.Option := '{"animation":false,"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"scatter","large":true,"largeThreshold":100,"symbolSize":4,'
    + '"itemStyle":{"shadowBlur":3,"shadowColor":"#f00"},"data":[' + data + ']}]}';
  n := TyPainterShadowsCastForTest;
  bmp := Draw;
  bmp.Free;
  AssertTrue('the batch large', FChart.SeriesLargeKind(0) <> lgkNone);
  AssertTrue('its path casts (a fill, maybe a pen)', (TyPainterShadowsCastForTest - n >= 1)
    and (TyPainterShadowsCastForTest - n <= 2));
end;

{ AT TWICE THE DEVICE SCALE the blur and the offset are twice the raster px }
procedure TAdvChartShadowsTest.TestTheShadowFollowsTheDeviceScale;
var
  p: TTyPainter;
  bmp: TBGRABitmap;
  sc: TTyCanvasScale;
begin
  bmp := TBGRABitmap.Create(200, 200, BGRAPixelTransparent);
  sc.Scale := 2;
  sc.DeviceUnits := False;
  p := TTyPainter.Create;
  try
    p.BeginPaintOnScaled(nil, Rect(0, 0, 100, 100), 96, bmp, sc);
    p.SetShadow(TyRGBA(0, 0, 0, 255), 0, 20, 0);
    p.BeginPath;
    p.RectPath(10, 10, 30, 30);
    p.FillPath(TyRGBA(255, 0, 0, 255));
    p.EndPaint;
    AssertEquals('the shape at 20..60 raster px', 255, bmp.GetPixel(40, 40).red);
    AssertEquals('its shadow 40 raster px right', 255, AlphaAt(bmp, 95, 40));
    AssertEquals('...ending there', 0, AlphaAt(bmp, 105, 40));
  finally
    p.Free;
    bmp.Free;
  end;
end;

{ 'lighter' ADDS, ONCE PER OP: two overlapping squares of one path add up
  once; a blend mode mixes source over }
procedure TAdvChartShadowsTest.TestLighterAddsAndABlendModeMixes;
var
  p: TTyPainter;
  bmp: TBGRABitmap;
  px: TBGRAPixel;
  n: Integer;
begin
  p := NewLayer(200, 100, bmp);
  try
    bmp.FillRect(0, 0, 200, 100, BGRA(100, 0, 0, 255), dmSet);
    n := TyPainterBlendsForTest;
    p.SetBlendMode('lighter');
    p.BeginPath;
    p.RectPath(10, 10, 60, 60);
    p.RectPath(40, 10, 90, 60);
    p.FillPath(TyRGBA(0, 120, 0, 255));
    p.SetBlendMode('multiply');
    p.BeginPath;
    p.RectPath(110, 10, 190, 60);
    p.FillPath(TyRGBA(255, 128, 0, 255));
    p.SetBlendMode('');
    p.EndPaint;
    AssertEquals('two ops composited', n + 2, TyPainterBlendsForTest);
    px := bmp.GetPixel(20, 30);
    AssertEquals('lighter: red kept', 100, px.red);
    AssertEquals('lighter: green added', 120, px.green);
    px := bmp.GetPixel(50, 30);
    AssertEquals('where the one path overlaps itself: added once', 120, px.green);
    px := bmp.GetPixel(150, 30);
    AssertEquals('multiply: 100 * 255 / 255', 100, px.red);
    AssertEquals('multiply: 0 * 128', 0, px.green);
    AssertEquals('outside the ops as it was', 100, bmp.GetPixel(100, 80).red);
  finally
    p.Free;
    bmp.Free;
  end;
end;

{ A HIGHER zlevel OVER A HIGHER z: drawn on top and hit on top }
procedure TAdvChartShadowsTest.TestAHigherZLevelIsDrawnAndHitOnTop;
const
  cOpt = '{"animation":false,"color":["#ff0000","#0000ff"],"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"type":"value","max":10},"series":[{"type":"bar","barWidth":40,%s"data":[8]},'
    + '{"type":"bar","barWidth":40,"barGap":"-100%%","z":10,"data":[8]}]}';
var
  bmp: TBGRABitmap;
  el: TTyChartElement;
  j, x, y: Integer;
  b: TTyRectF;
begin
  NewChart(300, 300);
  FChart.Option := Format(cOpt, ['']);
  bmp := Draw;
  try
    for j := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(j);
      if (el.Anim.Role = carBar) and (el.Anim.Series = 0) then b := TyShapeBounds(el.Shape);
    end;
    x := Round((b.Left + b.Right) / 2);
    y := Round((b.Top + b.Bottom) / 2);
    AssertEquals('z 10 over: blue', 255, bmp.GetPixel(x, y).blue);
    AssertEquals('...and hit', 1, FChart.HitTestAt(x, y).SeriesIndex);
  finally
    bmp.Free;
  end;
  NewChart(300, 300);
  FChart.Option := Format(cOpt, ['"zlevel":1,']);
  bmp := Draw;
  try
    AssertEquals('zlevel 1 over z 10: red', 255, bmp.GetPixel(x, y).red);
    AssertEquals('...not blue', 0, bmp.GetPixel(x, y).blue);
    AssertEquals('...and hit', 0, FChart.HitTestAt(x, y).SeriesIndex);
  finally
    bmp.Free;
  end;
end;

{ A CONTINUOUS visualMap's INDICATOR casts indicatorStyle's default shadow:
  a blur of 2 at (1, 1) in tokens.color.shadow (the skin's TyAdvChartShadow) }
procedure TAdvChartShadowsTest.TestTheIndicatorCastsItsDefaultShadow;
var
  bmp: TBGRABitmap;
  L: TTyVisualMapLayout;
  bx, by: Double;
  j, n: Integer;
  el: TTyChartElement;
begin
  NewChart(500, 400);
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value"},"visualMap":{"type":"continuous","min":0,"max":100,'
    + '"right":20,"top":"middle"},"series":[{"type":"bar","data":[20,80]}]}';
  bmp := Draw;
  bmp.Free;
  L := FChart.VisualMapLayout(0);
  bx := L.GroupX + L.Bar[0] * (L.ItemW / 2) + L.Bar[2] * (L.ItemH / 2) + L.Bar[4];
  by := L.GroupY + L.Bar[1] * (L.ItemW / 2) + L.Bar[3] * (L.ItemH / 2) + L.Bar[5];
  FChart.Move(Round(bx), Round(by));
  bmp := Draw;
  bmp.Free;
  AssertTrue('the indicator shows', FChart.VisualMapLive(0).IndVisible);
  n := 0;
  for j := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(j);
    if (el.Shape.Kind <> cskCircle) or (el.Style.StrokeWidthLogical <> 2) then Continue;
    Inc(n);
    AssertEquals('blur 2', 2.0, el.Style.ShadowBlur);
    AssertEquals('offset x 1', 1.0, el.Style.ShadowOffsetX);
    AssertEquals('offset y 1', 1.0, el.Style.ShadowOffsetY);
    AssertEquals('rgba(0, 0, 0, 0.2)', IntToHex($33000000, 8), IntToHex(el.Style.ShadowColor, 8));
  end;
  AssertEquals('one indicator', 1, n);
end;

{ A TITLE'S FRAME casts the title's own shadow keys }
procedure TAdvChartShadowsTest.TestATitlesFrameCastsItsShadow;
const
  cOpt = '{"animation":false,"title":{"text":"Title","left":20,"top":20,'
    + '"backgroundColor":"#ffffff","padding":10%s}}';
var
  plain, shaded: TBGRABitmap;
  y, hits, first, bottom: Integer;
begin
  NewChart(300, 200);
  FChart.Option := Format(cOpt, ['']);
  plain := Draw;
  NewChart(300, 200);
  FChart.Option := Format(cOpt, [',"shadowColor":"#000000","shadowOffsetY":12']);
  shaded := Draw;
  try
    hits := 0;
    first := -1;
    for y := 0 to 120 do
      if DarkerThan(shaded.GetPixel(40, y), plain.GetPixel(40, y)) then
      begin
        Inc(hits);
        if first < 0 then first := y;
      end;
    { [R5-G] the white frame (the author's backgroundColor, no longer the
      skin's surface) covers its own shadow: what shows is the offset's 12
      rows below it [was: >= 20, the shadow seen through a frame painted
      in another colour] }
    AssertTrue(Format('the frame''s shadow (%d rows)', [hits]), (hits >= 11) and (hits <= 13));
    { the frame's top at 20, its shadow 12 below it: what shows of it starts
      at the frame's bottom [R5-G: the frame is opaque now] }
    bottom := Round(FChart.TitleLayoutOf(0).Frame.Bottom);
    AssertTrue(Format('moved down by its offset (from row %d, the frame''s bottom %d)', [first, bottom]),
      (first >= bottom - 1) and (first <= bottom + 1));
  finally
    plain.Free;
    shaded.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartShadowsOracleTest);
  RegisterTest(TAdvChartShadowsTest);
end.
