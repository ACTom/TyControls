unit test.advchart.edgesseries;
{$mode objfpc}{$H+}
{ R5-G, THE SERIES' EDGE CASES (spec section 244).

  tools/advchart-oracle/edges-series.js records, on ECharts 6.1: a
  pictorialBar's `outside` label past the end its bounding length runs to; a
  path:// glyph reflected on a bar that points the other way (each glyph's
  centroid); a radar ring's pen from lineStyle.color, an item's own over the
  series'; a graph node's own symbolOffset; the boxplot transform's asc() and
  a themeRiver layer's index sort, both V8's TimSort over comparisons that are
  not numbers; the legend icon's pen of a candlestick and a boxplot (their
  borderWidth 1 makes the 'auto' pen 2); and the indices a pie's
  animationDelay is called with when negative values are filtered out. The
  replay holds the control to each. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller, tyControls.Painter,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Render,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Data,
     tyControls.AdvanceChart.Dataset, tyControls.AdvanceChart.ThemeRiver,
     tyControls.AdvanceChart.AnimOpt, tyControls.AdvanceChart.AnimView,
     tyControls.AdvanceChart,
     test.advchart.graphic;
type
  TAdvChartEdgesSeriesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxProbe;
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FDelays: array of Integer;
    procedure Bad(const AWhat: string);
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    procedure Load(ACase: TJSONObject; AAnimate: Boolean = False);
    procedure Finish(const AWhat: string);
    function Cases(const AGroup: string): TJSONArray;
    function DelayLog(ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams): Double;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAPictorialOutsideLabelIsPastItsBound;
    procedure TestAPathGlyphIsReflectedOnABarThatPointsBack;
    procedure TestARadarRingTakesItsLineColour;
    procedure TestAGraphNodeTakesItsOwnSymbolOffset;
    procedure TestTheBoxplotAscIsV8s;
    procedure TestARiverLayerIsSortedAsV8;
    procedure TestACandlestickAndABoxplotIconHaveTheirPen;
    procedure TestAPieDelayGetsTheFilteredIndices;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-edges-series.json';
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

function Txt(V: Double): string;
begin
  Result := FloatToStr(V, DefaultFormatSettings);
end;

function SameNum(A, B, ATol: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Abs(A - B) <= ATol;
end;

function ColourOf(const AText: string): TTyChartColor;
begin
  if not TyTryParseChartColor(AText, Result) then Result := 0;
end;

{ what the item built, for a report: each element's shape kind, ink and words }
function MarksOf(AList: TTyPaintList; ASeries, ARaw: Integer): string;
var j: Integer; e: TTyChartElement;
begin
  Result := '';
  for j := 0 to AList.Count - 1 do
  begin
    e := AList.Element(j);
    if e.Datum.IsEdge or (e.Datum.SeriesIndex <> ASeries) or (e.Datum.RawDataIndex <> ARaw) then Continue;
    Result := Result + Format('[kind %d fill %s text "%s" size %d] ', [Ord(e.Shape.Kind),
      BoolToStr(e.Style.HasFill, True), e.Caption.Text, e.Caption.FontSizeLogical]);
  end;
end;

{ ==================== the harness ==================== }

procedure TAdvChartEdgesSeriesOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := GetJSON(LoadText(FixturePath));
  TyChartRegisterAnimDelay('delayLog', @DelayLog);
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartEdgesSeriesOracleTest.TearDown;
begin
  TyChartUnregisterAnimDelay('delayLog');
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TAdvChartEdgesSeriesOracleTest.DelayLog(ADataIndex: Integer;
  AHasIndex: Boolean; const AParams: TTyAnimDelayParams): Double;
begin
  SetLength(FDelays, Length(FDelays) + 1);
  if AHasIndex then FDelays[High(FDelays)] := ADataIndex
  else FDelays[High(FDelays)] := -1;
  Result := 0;
end;

procedure TAdvChartEdgesSeriesOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 60 then FReport := FReport + LineEnding + '  ' + FWhere + ': ' + AWhat;
end;

procedure TAdvChartEdgesSeriesOracleTest.Finish(const AWhat: string);
begin
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(AWhat + ' (' + IntToStr(FCompared) + ' compared)' + FReport, 0, FBad);
end;

procedure TAdvChartEdgesSeriesOracleTest.NewChart(AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FChart := TGfxProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartEdgesSeriesOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartEdgesSeriesOracleTest.Load(ACase: TJSONObject; AAnimate: Boolean);
begin
  FWhere := ACase.Strings['id'];
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  if AAnimate then
  begin
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := 1700000000000;
  end;
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  AssertEquals(FWhere + ' parses', '', FChart.OptionError);
  RenderNow;
end;

function TAdvChartEdgesSeriesOracleTest.Cases(const AGroup: string): TJSONArray;
var all: TJSONArray; i: Integer;
begin
  Result := TJSONArray.Create;
  all := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to all.Count - 1 do
    if all.Objects[i].Strings['group'] = AGroup then
      Result.Add(all.Objects[i].Clone);
end;

{ ==================== the cases ==================== }

{ the pictorial rect's label -- the expanded caption of the item's inkless
  rect: upstream's anchor (innerTransformable) and the alignment its inner
  text style was given }
procedure TAdvChartEdgesSeriesOracleTest.TestAPictorialOutsideLabelIsPastItsBound;
var
  cs, items: TJSONArray;
  c, it: TJSONObject;
  i, k, j, n: Integer;
  lst: TTyPaintList;
  e, cap: TTyChartElement;
  want, got: string;
begin
  cs := Cases('pictorial-outside');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      Load(c);
      lst := FChart.List;
      items := c.Arrays['items'];
      for k := 0 to items.Count - 1 do
      begin
        it := items.Objects[k];
        if not it.Booleans['drawn'] then Continue;
        n := 0;
        cap := Default(TTyChartElement);
        for j := 0 to lst.Count - 1 do
        begin
          e := lst.Element(j);
          if e.Datum.IsEdge or (e.Datum.SeriesIndex <> it.Integers['s'])
            or (e.Datum.RawDataIndex <> it.Integers['raw']) then Continue;
          if e.Caption.FontSizeLogical <= 0 then Continue;
          Inc(n);
          cap := e;
        end;
        Inc(FCompared);
        if n <> 1 then
        begin
          Bad(Format('item %d: %d labels (%s)', [it.Integers['raw'], n, MarksOf(lst, it.Integers['s'], it.Integers['raw'])]));
          Continue;
        end;
        want := it.Strings['align'] + '/' + it.Strings['verticalAlign'];
        case cap.Caption.AnchorH of
          tahLeft: got := 'left';
          tahRight: got := 'right';
        else
          got := 'center';
        end;
        case cap.Caption.AnchorV of
          tavTop: got := got + '/top';
          tavBottom: got := got + '/bottom';
        else
          got := got + '/middle';
        end;
        if want <> got then
          Bad(Format('item %d: %s (%s) upstream, %s here', [it.Integers['raw'], want,
            it.Strings['word'], got]))
        else if not (SameNum(cap.Caption.X, FromHex(it.Strings['x']), 1e-9)
          and SameNum(cap.Caption.Y, FromHex(it.Strings['y']), 1e-9)) then
          Bad(Format('item %d: at %s,%s upstream, %s,%s here', [it.Integers['raw'],
            it.Strings['xText'], it.Strings['yText'], Txt(cap.Caption.X), Txt(cap.Caption.Y)]));
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('the pictorial labels');
end;

{ each glyph drawn alone: the centroid of its ink against upstream's
  triangle's, within a pixel's AA and the box's rounding; every upstream
  glyph has its own here }
procedure TAdvChartEdgesSeriesOracleTest.TestAPathGlyphIsReflectedOnABarThatPointsBack;
type
  TCen = record X, Y: Double; Used: Boolean; end;
var
  cs, gl: TJSONArray;
  c, g: TJSONObject;
  i, k, j, best, x, y: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  cens: array of TCen;
  b: TBGRABitmap;
  p: TTyPainter;
  px: PBGRAPixel;
  sx, sy, sw, wgt, d, bd, ux, uy: Double;
begin
  cs := Cases('pictorial-mirror');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      Load(c);
      lst := FChart.List;
      cens := nil;
      for j := 0 to lst.Count - 1 do
      begin
        e := lst.Element(j);
        if e.Shape.Kind <> cskPath then Continue;
        if e.Datum.IsEdge or (e.Datum.SeriesIndex < 0) then Continue;
        e.HasClip := False;
        e.Style.Alpha := 1;
        e.Style.FillColor := $FF000000;
        e.Style.HasFill := True;
        e.Style.StrokeWidthLogical := 0;
        e.Caption := Default(TTyElementCaption);
        b := TBGRABitmap.Create(c.Integers['W'], c.Integers['H'], BGRA(255, 255, 255, 255));
        try
          p := TTyPainter.Create;
          try
            p.BeginPaintOn(nil, Rect(0, 0, b.Width, b.Height), 96, b);
            TyRenderElement(p, e);
            p.EndPaint;
          finally
            p.Free;
          end;
          sx := 0;
          sy := 0;
          sw := 0;
          for y := 0 to b.Height - 1 do
          begin
            px := b.ScanLine[y];
            for x := 0 to b.Width - 1 do
            begin
              wgt := (255 - px^.green) / 255;
              if wgt > 0 then
              begin
                sx := sx + wgt * (x + 0.5);
                sy := sy + wgt * (y + 0.5);
                sw := sw + wgt;
              end;
              Inc(px);
            end;
          end;
        finally
          b.Free;
        end;
        if sw <= 0 then Continue;
        SetLength(cens, Length(cens) + 1);
        cens[High(cens)].X := sx / sw;
        cens[High(cens)].Y := sy / sw;
        cens[High(cens)].Used := False;
      end;
      gl := c.Arrays['glyphs'];
      Inc(FCompared);
      if Length(cens) <> gl.Count then
        Bad(Format('%d glyphs upstream, %d here', [gl.Count, Length(cens)]));
      for k := 0 to gl.Count - 1 do
      begin
        g := gl.Objects[k];
        ux := FromHex(g.Strings['cx']);
        uy := FromHex(g.Strings['cy']);
        best := -1;
        bd := 1e9;
        for j := 0 to High(cens) do
        begin
          if cens[j].Used then Continue;
          d := Hypot(cens[j].X - ux, cens[j].Y - uy);
          if d < bd then
          begin
            bd := d;
            best := j;
          end;
        end;
        Inc(FCompared);
        if (best < 0) or (bd > 0.75) then
          Bad(Format('glyph %d/%d: centroid %s,%s upstream, nearest here %s px off',
            [g.Integers['raw'], g.Integers['k'], g.Strings['cxText'], g.Strings['cyText'],
             Txt(bd)]))
        else cens[best].Used := True;
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('the glyphs');
end;

procedure TAdvChartEdgesSeriesOracleTest.TestARadarRingTakesItsLineColour;
var
  cs, rows: TJSONArray;
  c, r: TJSONObject;
  i, k, j: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  ring, area: Boolean;
  want: TTyChartColor;
begin
  cs := Cases('radar-line-colour');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      Load(c);
      lst := FChart.List;
      rows := c.Arrays['rows'];
      for k := 0 to rows.Count - 1 do
      begin
        r := rows.Objects[k];
        ring := False;
        area := False;
        for j := 0 to lst.Count - 1 do
        begin
          e := lst.Element(j);
          if (e.Datum.SeriesIndex <> r.Integers['s']) or (e.Datum.RawDataIndex <> r.Integers['raw']) then
            Continue;
          if e.Shape.Kind = cskPolyline then
          begin
            ring := True;
            Inc(FCompared);
            if r.Strings['stroke'] = 'none' then
            begin
              if (e.Style.StrokeColor shr 24) <> 0 then
                Bad(Format('row %d: no pen upstream, %s here', [k, IntToHex(e.Style.StrokeColor, 8)]));
            end
            else
            begin
              want := ColourOf(r.Strings['stroke']);
              if e.Style.StrokeColor <> want then
                Bad(Format('row %d: pen %s upstream, %s here', [k, r.Strings['stroke'],
                  IntToHex(e.Style.StrokeColor, 8)]));
            end;
          end
          else if (e.Shape.Kind = cskPolygon) and not e.Ignore then
          begin
            area := True;
            Inc(FCompared);
            if r.Find('area').JSONType <> jtString then Bad(Format('row %d: an area here, none upstream', [k]))
            else if e.Style.FillColor <> ColourOf(r.Strings['area']) then
              Bad(Format('row %d: area %s upstream, %s here', [k, r.Strings['area'],
                IntToHex(e.Style.FillColor, 8)]));
          end;
        end;
        if not ring then Bad(Format('row %d: no ring', [k]));
        if (not area) and (r.Find('area').JSONType = jtString) then
          Bad(Format('row %d: no area', [k]));
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('the rings');
end;

procedure TAdvChartEdgesSeriesOracleTest.TestAGraphNodeTakesItsOwnSymbolOffset;
var
  cs, nodes: TJSONArray;
  c, nd: TJSONObject;
  i, k, j, n: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  b: TTyRectF;
  cx, cy: Double;
begin
  cs := Cases('graph-item-offset');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      Load(c);
      lst := FChart.List;
      nodes := c.Arrays['nodes'];
      for k := 0 to nodes.Count - 1 do
      begin
        nd := nodes.Objects[k];
        n := 0;
        cx := NaN;
        cy := NaN;
        for j := 0 to lst.Count - 1 do
        begin
          e := lst.Element(j);
          if e.Datum.IsEdge or (e.Datum.SeriesIndex <> nd.Integers['s'])
            or (e.Datum.RawDataIndex <> nd.Integers['raw']) then Continue;
          if e.Caption.FontSizeLogical > 0 then Continue;
          b := TyShapeBounds(e.Shape);
          cx := (b.Left + b.Right) / 2;
          cy := (b.Top + b.Bottom) / 2;
          Inc(n);
        end;
        Inc(FCompared);
        if n <> 1 then
          Bad(Format('node %d: %d symbols', [k, n]))
        else if not (SameNum(cx, FromHex(nd.Strings['x']), 1e-6)
          and SameNum(cy, FromHex(nd.Strings['y']), 1e-6)) then
          Bad(Format('node %d (offset %s): at %s,%s upstream, %s,%s here', [k,
            nd.Strings['offset'], nd.Strings['xText'], nd.Strings['yText'], Txt(cx), Txt(cy)]));
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('the nodes');
end;

{ each row through TyPrepareBoxplotData against upstream's transform: the
  five numbers (a value upstream made a string of -- 'x' + NaN -- is not
  compared: the port does no string arithmetic) }
procedure TAdvChartEdgesSeriesOracleTest.TestTheBoxplotAscIsV8s;
var
  cs, rows, boxes, ub, pb: TJSONArray;
  c: TJSONObject;
  i, r, k, off: Integer;
  outl: TJSONArray;
  u, h: Double;
  raw: TJSONArray;
begin
  cs := Cases('boxplot-sort');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      FWhere := c.Strings['id'];
      rows := c.Arrays['rows'];
      raw := TJSONArray(rows.Clone);
      try
        AssertTrue('the boxes', TyPrepareBoxplotData(raw, nil, boxes, outl));
        try
          ub := c.Arrays['boxes'];
          AssertEquals(FWhere + ' rows', ub.Count, boxes.Count);
          for r := 0 to ub.Count - 1 do
          begin
            pb := boxes.Arrays[r];
            off := ub.Arrays[r].Count - pb.Count;
            for k := 0 to pb.Count - 1 do
            begin
              if ub.Arrays[r].Objects[k + off].Find('v') = nil then Continue;
              u := FromHex(ub.Arrays[r].Objects[k + off].Strings['v']);
              if pb.Items[k].JSONType = jtNumber then h := pb.Items[k].AsFloat else h := NaN;
              Inc(FCompared);
              if not SameNum(h, u, 0) then
                Bad(Format('row %d box %d: %s upstream, %s here', [r, k,
                  ub.Arrays[r].Objects[k + off].Strings['vText'], Txt(h)]));
            end;
          end;
        finally
          boxes.Free;
          outl.Free;
        end;
      finally
        raw.Free;
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('the boxes');
end;

procedure TAdvChartEdgesSeriesOracleTest.TestARiverLayerIsSortedAsV8;
var
  cs, ul, idx: TJSONArray;
  c: TJSONObject;
  i, k, j: Integer;
  layers: TTyRiverLayerArray;
  st: TTyDataStore;
  got, want: string;
begin
  cs := Cases('river-sort');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      Load(c);
      st := FChart.SeriesStore(0);
      AssertNotNull('the store', st);
      layers := TyThemeRiverLayers(st);
      ul := c.Arrays['layers'];
      AssertEquals(FWhere + ' layers', ul.Count, Length(layers));
      for k := 0 to ul.Count - 1 do
      begin
        idx := ul.Objects[k].Arrays['indices'];
        want := '';
        for j := 0 to idx.Count - 1 do want := want + IntToStr(idx.Integers[j]) + ' ';
        got := '';
        for j := 0 to High(layers[k].Rows) do got := got + IntToStr(layers[k].Rows[j]) + ' ';
        Inc(FCompared);
        if got <> want then Bad(Format('layer %d: %s upstream, %s here', [k, want, got]));
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('the layers');
end;

{ each icon path upstream pens (a string stroke, a width above nought) has an
  element of the item's with that width -- in that colour where the option
  wrote one; one upstream does not pen has none here }
procedure TAdvChartEdgesSeriesOracleTest.TestACandlestickAndABoxplotIconHaveTheirPen;
var
  cs, items, icons: TJSONArray;
  c, it, ic: TJSONObject;
  i, k, q, j, first, last: Integer;
  lst: TTyPaintList;
  pe: PTyChartElement;
  found, written: Boolean;
  w: Double;
  want: TTyChartColor;
begin
  cs := Cases('legend-icons');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      Load(c);
      lst := FChart.List;
      items := c.Arrays['items'];
      for k := 0 to items.Count - 1 do
      begin
        it := items.Objects[k];
        first := -1;
        last := lst.Count - 1;
        for j := 0 to lst.Count - 1 do
        begin
          pe := lst.Ref(j);
          if pe^.Datum.Kind <> ctkLegend then Continue;
          if first >= 0 then
          begin
            last := j - 1;
            Break;
          end;
          if pe^.Datum.DataIndex = k then first := j + 1;
        end;
        if first < 0 then
        begin
          Bad('no legend item ' + it.Strings['name']);
          Continue;
        end;
        icons := it.Arrays['icons'];
        for q := 0 to icons.Count - 1 do
        begin
          ic := icons.Objects[q];
          { a line's own icon: its rule and marker are matched elsewhere }
          if icons.Count > 1 then Continue;
          w := ic.Floats['lineWidth'];
          written := Pos('"borderColor"', c.Objects['option'].AsJSON) > 0;
          Inc(FCompared);
          if (ic.Find('stroke').JSONType = jtString) and (w > 0) then
          begin
            want := ColourOf(ic.Strings['stroke']);
            found := False;
            for j := first to last do
            begin
              pe := lst.Ref(j);
              if (pe^.Caption.Text = '') and (pe^.Style.StrokeWidthLogical = w)
                and ((not written) or (pe^.Style.StrokeColor = want)) then found := True;
            end;
            if not found then
              Bad(Format('%s: no pen %s at %s', [it.Strings['name'], ic.Strings['stroke'], Txt(w)]));
          end
          else
            for j := first to last do
            begin
              pe := lst.Ref(j);
              if (pe^.Caption.Text = '') and (pe^.Style.StrokeWidthLogical > 0)
                and ((pe^.Style.StrokeColor shr 24) <> 0) then
                Bad(Format('%s: a pen here (%s), none upstream', [it.Strings['name'],
                  Txt(pe^.Style.StrokeWidthLogical)]));
            end;
        end;
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('the legend icons');
end;

{ the indices the delay is called with, those that are indices, as a sorted
  set -- the filtered data's (0..2 for three positive slices), never a raw
  index past a dropped one }
procedure TAdvChartEdgesSeriesOracleTest.TestAPieDelayGetsTheFilteredIndices;
var
  cs, calls: TJSONArray;
  c: TJSONObject;
  i, j: Integer;
  up, here: array of Integer;
  a, b: string;

  procedure SortInts(var A: array of Integer);
  var x, y, tt: Integer;
  begin
    for x := 1 to High(A) do
    begin
      tt := A[x];
      y := x - 1;
      while (y >= 0) and (A[y] > tt) do
      begin
        A[y + 1] := A[y];
        Dec(y);
      end;
      A[y + 1] := tt;
    end;
  end;

begin
  cs := Cases('pie-delay');
  try
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      FDelays := nil;
      Load(c, True);
      calls := c.Arrays['calls'];
      up := nil;
      for j := 0 to calls.Count - 1 do
        if calls.Items[j].JSONType = jtNumber then
        begin
          SetLength(up, Length(up) + 1);
          up[High(up)] := calls.Integers[j];
        end;
      here := nil;
      for j := 0 to High(FDelays) do
        if FDelays[j] >= 0 then
        begin
          SetLength(here, Length(here) + 1);
          here[High(here)] := FDelays[j];
        end;
      SortInts(up);
      SortInts(here);
      { distinct: upstream asks again for the label's fade (R5-F's
        animation), the indices are the point here }
      a := '';
      for j := 0 to High(up) do
        if (j = 0) or (up[j] <> up[j - 1]) then a := a + IntToStr(up[j]) + ' ';
      b := '';
      for j := 0 to High(here) do
        if (j = 0) or (here[j] <> here[j - 1]) then b := b + IntToStr(here[j]) + ' ';
      Inc(FCompared);
      if a <> b then Bad('indices ' + a + 'upstream, ' + b + 'here');
    end;
  finally
    cs.Free;
  end;
  Finish('the delays');
end;

initialization
  RegisterTest(TAdvChartEdgesSeriesOracleTest);
end.
