unit test.advchart.candleboxplot;
{$mode objfpc}{$H+}
{ THE CANDLESTICK'S FINISH AND THE BOXPLOT, HELD TO UPSTREAM [Batch 108, C1].

  tools/advchart-oracle/candle-boxplot.js runs the real ECharts 6.1 build in
  node (animation off, a live TooltipView) over 58 charts and records, per
  chart: the plot's area, each axis' effective and mapping extents, and per
  candlestick or boxplot item whether it has a value, whether it is drawn,
  whether it is clipped, its layout points, its style and z2 (a candle's
  sign too); a scatter's points; every dataset's results (the boxplot
  transform's tables); the tooltip over one item; the styles after a
  highlight.

  This replays all of it through the control, bit for bit:

    layout    the area; the extents (a mapping where upstream has one, none
              where it has none); per item drawn / clipped (the clip rect is
              upstream's clip path, as recorded); a candle's body the bounds
              of its four body points, its wicks the two spine segments, a
              simple box one stroke from highest to lowest; a box's path its
              fourteen points, in order; the style where the option wrote
              the colour, the skin's candle, surface and palette colours
              where upstream used its own defaults;
    tables    every dataset's results as TTyDatasetCache answers them, cell
              by cell -- a number to the bit, a string as it is;
    tooltip   the pointer at the fixture's point, the box for the same
              target, its rows;
    states    the highlight's style (width, opacity, the fill's lift where it
              is a colour the option wrote), z2's lift, the blur. The shadow
              is not drawn here and is not compared. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Color, tyControls.AdvChart.Option,
     tyControls.AdvChart.Dataset, tyControls.AdvChart.Tooltip,
     tyControls.AdvChart.WhiskerBox, tyControls.AdvanceChart;
type
  TCbProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Move(AX, AY: Integer);
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    function AxisContentAt(AX, AY: Integer; const ASpec: TTyTooltipSpec): TTyTooltipBlock;
  end;

  TAdvChartCandleBoxplotTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCbProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure NewChart(AOption: TJSONObject);
    procedure Frame;
    function Cases: TJSONArray;
    function CaseById(const AId: string): TJSONObject;
    procedure Finish(const AWhat: string);
    function Theme(const AKey: string): TTyChartColor;
    function ColourOf(ACase: TJSONObject; const AUp: string; ASeries: Integer;
      AFill: Boolean; out AWant: TTyChartColor): Boolean;
    procedure CheckLayout(ACase: TJSONObject);
    procedure CheckItems(ACase, ASeries: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryChartIsLaidOutAsUpstreamLaysItOut;
    procedure TestTheTransformMakesUpstreamsTables;
    procedure TestTheTooltipSaysWhatUpstreamSays;
    procedure TestAHighlightedBoxLooksAsUpstreamsDoes;
    { beyond the fixture }
    procedure TestTheQuantileIsUpstreamsInterpolation;
    procedure TestANaNSampleIsNeverAnOutlier;
    procedure TestATransformNobodyRegisteredHasNoTable;
    procedure TestADatasetReadingItselfHasNoTable;
    procedure TestTheCandleWidthRules;
  end;

implementation

const
  cW = 600;
  cH = 400;

{ ==================== the probe ==================== }

procedure TCbProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TCbProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TCbProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TCbProbe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

function TCbProbe.AxisContentAt(AX, AY: Integer;
  const ASpec: TTyTooltipSpec): TTyTooltipBlock;
begin
  Result := AxisTooltipContent(ResolveAxisPointers(AX, AY), ASpec);
end;

{ ==================== helpers ==================== }

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Txt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

{ to the bit -- and a not-a-number is one, whatever its payload: JavaScript
  has a single NaN, and DataView writes it canonically }
function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B));
end;

procedure TAdvChartCandleBoxplotTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-candle-boxplot.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartCandleBoxplotTest.TearDown;
begin
  FChart.Free;
  FChart := nil;
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartCandleBoxplotTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartCandleBoxplotTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameBits(AGot, FromHex(AHex)) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex))]));
end;

procedure TAdvChartCandleBoxplotTest.Finish(const AWhat: string);
begin
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartCandleBoxplotTest.NewChart(AOption: TJSONObject);
begin
  FChart.Free;
  FChart := TCbProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.TooltipNow := 0;
  FChart.Option := AOption.AsJSON;
  FChart.SetBounds(0, 0, cW, cH);
  Frame;
end;

procedure TAdvChartCandleBoxplotTest.Frame;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartCandleBoxplotTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function TAdvChartCandleBoxplotTest.CaseById(const AId: string): TJSONObject;
var i: Integer;
begin
  Result := nil;
  for i := 0 to Cases.Count - 1 do
    if Cases.Objects[i].Strings['id'] = AId then Exit(Cases.Objects[i]);
end;

function TAdvChartCandleBoxplotTest.Theme(const AKey: string): TTyChartColor;
begin
  Result := TTyChartColor(FCtl.Model.ResolveStyle(AKey, '', [tysNormal]).Background.Color);
end;

{ The colour the port should have where upstream has AUp: the option's own
  when it wrote it, else the skin's for upstream's defaults -- a candle's
  two, the boxplot's surface fill, the palette's series colour. False when
  the colour is not one a rule maps. }
function TAdvChartCandleBoxplotTest.ColourOf(ACase: TJSONObject;
  const AUp: string; ASeries: Integer; AFill: Boolean;
  out AWant: TTyChartColor): Boolean;
var lower: string;
begin
  Result := False;
  AWant := 0;
  lower := LowerCase(AUp);
  if (Length(lower) >= 4) and (lower[1] = '#')
    and (Pos('"' + lower + '"', LowerCase(ACase.Objects['option'].AsJSON)) > 0) then
  begin
    Result := TyTryParseChartColor(AUp, AWant);
    Exit;
  end;
  if lower = '#eb5454' then begin AWant := Theme('TyAdvChartCandleUp'); Exit(True); end;
  if lower = '#47b262' then begin AWant := Theme('TyAdvChartCandleDown'); Exit(True); end;
  if lower = '#fff' then begin AWant := Theme('TyAdvChart'); Exit(True); end;
  { the palette: a stroke not written is the series colour }
  if not AFill then
  begin
    AWant := FChart.PaletteSeriesColour(ASeries);
    Exit(True);
  end;
end;

{ ==================== the layout ==================== }

procedure TAdvChartCandleBoxplotTest.CheckLayout(ACase: TJSONObject);
var
  grid: TTyGridBuild;
  cart: TTyCartesian2D;
  area: TTyXYWH;
  arr: TJSONArray;
  ax: TTyAxis;
  e, m: TTyRange;
  i: Integer;
  a: TJSONObject;
  mapper: ITyScaleMapper;
begin
  grid := FChart.Build.Grid(0);
  cart := FChart.Build.CartesianAt(0, 0);
  if (grid = nil) or (cart = nil) then
  begin
    Bad('no grid');
    Exit;
  end;
  area := cart.GetArea;
  arr := ACase.Arrays['grid'];
  Same('area x', area.X, arr.Strings[0]);
  Same('area y', area.Y, arr.Strings[1]);
  Same('area w', area.W, arr.Strings[2]);
  Same('area h', area.H, arr.Strings[3]);
  arr := ACase.Arrays['axes'];
  for i := 0 to arr.Count - 1 do
  begin
    a := arr.Objects[i];
    if a.Strings['dim'] = 'x' then ax := grid.XAxis(0) else ax := grid.YAxis(0);
    e := ax.Scale.GetExtent;
    Same(a.Strings['dim'] + ' effective lo', e.Start, a.Arrays['effective'].Strings[0]);
    Same(a.Strings['dim'] + ' effective hi', e.Stop, a.Arrays['effective'].Strings[1]);
    mapper := ax.Scale.Mapper;
    Inc(FCompared);
    if a.Find('mapping').JSONType = jtNull then
    begin
      if mapper.HasExtent(sekMapping) then
      begin
        m := ax.Scale.GetExtent2(sekMapping);
        Bad(Format('%s: a mapping [%s, %s] here, none upstream',
          [a.Strings['dim'], Txt(m.Start), Txt(m.Stop)]));
      end;
    end
    else if not mapper.HasExtent(sekMapping) then
      Bad(a.Strings['dim'] + ': no mapping here')
    else
    begin
      m := ax.Scale.GetExtent2(sekMapping);
      Same(a.Strings['dim'] + ' mapping lo', m.Start, a.Arrays['mapping'].Strings[0]);
      Same(a.Strings['dim'] + ' mapping hi', m.Stop, a.Arrays['mapping'].Strings[1]);
    end;
  end;
end;

function PtHex(const AEnds: TJSONArray; AIdx: Integer; out X, Y: Double): Boolean;
begin
  X := FromHex(AEnds.Strings[AIdx * 2]);
  Y := FromHex(AEnds.Strings[AIdx * 2 + 1]);
  Result := True;
end;

procedure TAdvChartCandleBoxplotTest.CheckItems(ACase, ASeries: TJSONObject);
var
  lst: TTyPaintList;
  items, ends: TJSONArray;
  item, st: TJSONObject;
  si, k, i, j, nBody, nWick, nOther: Integer;
  el, body: TTyChartElement;
  wicks: array of TTyChartElement;
  typ, tag: string;
  drawn, clipped, simple: Boolean;
  x, y, x2, y2, mnx, mny, mxx, mxy: Double;
  want: TTyChartColor;
  arr: TJSONArray;

  procedure SamePt(const AWhat: string; const P: TTyPointF; AIdx: Integer);
  var px, py: Double;
  begin
    PtHex(ends, AIdx, px, py);
    Same(AWhat + '.x', P.X, HexOf(px));
    Same(AWhat + '.y', P.Y, HexOf(py));
  end;

begin
  typ := ASeries.Strings['type'];
  si := ASeries.Integers['seriesIndex'];
  lst := FChart.List;
  items := ASeries.Arrays['items'];
  for k := 0 to items.Count - 1 do
  begin
    item := items.Objects[k];
    tag := Format('%s%d/%d', [typ, si, k]);
    nBody := 0;
    nWick := 0;
    nOther := 0;
    body := Default(TTyChartElement);
    wicks := nil;
    for i := 0 to lst.Count - 1 do
    begin
      el := lst.Element(i);
      if (el.Datum.Kind <> ctkSeries) or el.Datum.IsEdge
        or (el.Datum.SeriesIndex <> si) or (el.Datum.RawDataIndex <> k) then Continue;
      if el.Caption.FontSizeLogical > 0 then Continue;
      if (typ = 'candlestick') and (el.Shape.Kind = cskPolyline) then
      begin
        SetLength(wicks, Length(wicks) + 1);
        wicks[High(wicks)] := el;
        Inc(nWick);
      end
      else if (typ = 'candlestick') and (el.Shape.Kind = cskRect) then
      begin
        body := el;
        Inc(nBody);
      end
      else if (typ = 'boxplot') and (el.Shape.Kind = cskPolygon) then
      begin
        body := el;
        Inc(nBody);
      end
      else if typ = 'scatter' then
      begin
        body := el;
        Inc(nBody);
      end
      else
        Inc(nOther);
    end;
    drawn := item.Booleans['drawn'];
    Inc(FCompared);
    if typ = 'scatter' then
    begin
      if drawn <> (nBody > 0) then
        Bad(Format('%s: drawn %s upstream, %d here', [tag, BoolToStr(drawn, True), nBody]))
      else if drawn then
      begin
        x := (body.Shape.Bounds.Left + body.Shape.Bounds.Right) / 2;
        y := (body.Shape.Bounds.Top + body.Shape.Bounds.Bottom) / 2;
        if body.Shape.Kind in [cskCircle, cskEllipse, cskSector] then
        begin
          x := body.Shape.CX;
          y := body.Shape.CY;
        end;
        { a symbol's centre: compared to a hair, the path's box is its own }
        Inc(FCompared);
        if (Abs(x - FromHex(item.Arrays['xy'].Strings[0])) > 1e-9)
          or (Abs(y - FromHex(item.Arrays['xy'].Strings[1])) > 1e-9) then
          Bad(Format('%s: at (%s, %s) here, (%s, %s) upstream', [tag, Txt(x), Txt(y),
            Txt(FromHex(item.Arrays['xy'].Strings[0])), Txt(FromHex(item.Arrays['xy'].Strings[1]))]));
      end;
      Continue;
    end;
    if nOther > 0 then Bad(Format('%s: %d unexpected elements', [tag, nOther]));
    if not drawn then
    begin
      if (nBody > 0) or (nWick > 0) then
        Bad(Format('%s: not drawn upstream, %d + %d elements here', [tag, nBody, nWick]));
      Continue;
    end;
    ends := item.Arrays['ends'];
    clipped := item.Booleans['clipped'];
    if typ = 'candlestick' then
    begin
      simple := item.Booleans['simpleBox'];
      if simple then
      begin
        if (nBody <> 0) or (nWick <> 1) then
        begin
          Bad(Format('%s: a simple box upstream, %d bodies and %d strokes here', [tag, nBody, nWick]));
          Continue;
        end;
        SamePt(tag + ' simple from', wicks[0].Shape.Points[0], 4);
        SamePt(tag + ' simple to', wicks[0].Shape.Points[1], 6);
        body := wicks[0];
      end
      else
      begin
        if nBody <> 1 then
        begin
          Bad(Format('%s: drawn upstream, %d bodies here', [tag, nBody]));
          Continue;
        end;
        { the body: the bounds of the four body points }
        mnx := Infinity; mny := Infinity; mxx := -Infinity; mxy := -Infinity;
        for j := 0 to 3 do
        begin
          PtHex(ends, j, x, y);
          mnx := Min(mnx, x); mny := Min(mny, y);
          mxx := Max(mxx, x); mxy := Max(mxy, y);
        end;
        Same(tag + ' body left', body.Shape.Bounds.Left, HexOf(mnx));
        Same(tag + ' body top', body.Shape.Bounds.Top, HexOf(mny));
        Same(tag + ' body right', body.Shape.Bounds.Right, HexOf(mxx));
        Same(tag + ' body bottom', body.Shape.Bounds.Bottom, HexOf(mxy));
        { the wicks: highest to the body, lowest to the body -- a segment of
          no length is not drawn }
        j := 0;
        PtHex(ends, 4, x, y);
        PtHex(ends, 5, x2, y2);
        if (x <> x2) or (y <> y2) then
        begin
          Inc(FCompared);
          if j > High(wicks) then Bad(tag + ': no high wick here')
          else
          begin
            SamePt(tag + ' high wick from', wicks[j].Shape.Points[0], 4);
            SamePt(tag + ' high wick to', wicks[j].Shape.Points[1], 5);
          end;
          Inc(j);
        end;
        PtHex(ends, 6, x, y);
        PtHex(ends, 7, x2, y2);
        if (x <> x2) or (y <> y2) then
        begin
          Inc(FCompared);
          if j > High(wicks) then Bad(tag + ': no low wick here')
          else
          begin
            SamePt(tag + ' low wick from', wicks[j].Shape.Points[0], 6);
            SamePt(tag + ' low wick to', wicks[j].Shape.Points[1], 7);
          end;
          Inc(j);
        end;
        Inc(FCompared);
        if j <> nWick then Bad(Format('%s: %d wicks upstream, %d here', [tag, j, nWick]));
        { the enter animation's numbers are the snapped ones }
        Same(tag + ' anim spine', body.Anim.G[5], HexOf(IfThen(ASeries.Strings['baseDim'] = 'x',
          FromHex(ends.Strings[8]), FromHex(ends.Strings[9]))));
      end;
    end
    else
    begin
      { a box: its fourteen points, in order, and the path made of them }
      if nBody <> 1 then
      begin
        Bad(Format('%s: drawn upstream, %d paths here', [tag, nBody]));
        Continue;
      end;
      Inc(FCompared);
      if Length(body.Anim.Pts) <> 28 then
      begin
        Bad(Format('%s: %d numbers here', [tag, Length(body.Anim.Pts)]));
        Continue;
      end;
      for j := 0 to 27 do
        Same(Format('%s point %d', [tag, j]), body.Anim.Pts[j], ends.Strings[j]);
      Inc(FCompared);
      if Length(body.Shape.Cmds) <> 15 then
        Bad(Format('%s: %d path commands here', [tag, Length(body.Shape.Cmds)]))
      else
      begin
        SamePt(tag + ' cmd 0', TyPointF(body.Shape.Cmds[0].X, body.Shape.Cmds[0].Y), 0);
        SamePt(tag + ' cmd 3', TyPointF(body.Shape.Cmds[3].X, body.Shape.Cmds[3].Y), 3);
        SamePt(tag + ' cmd 14', TyPointF(body.Shape.Cmds[14].X, body.Shape.Cmds[14].Y), 13);
        Inc(FCompared);
        if (body.Shape.Cmds[4].Kind <> pckClose) or (body.Shape.Cmds[5].Kind <> pckMove)
          or (body.Shape.Cmds[6].Kind <> pckLine) then
          Bad(tag + ': the path is not closed box, then segments');
      end;
    end;
    { the clip }
    Inc(FCompared);
    if body.HasClip <> clipped then
      Bad(Format('%s: clipped %s upstream, %s here', [tag, BoolToStr(clipped, True),
        BoolToStr(body.HasClip, True)]))
    else if clipped then
    begin
      { upstream's clip path, as recorded: x, y, width, height }
      arr := item.Arrays['clip'];
      Same(tag + ' clip left', body.ClipRect.Left, arr.Strings[0]);
      Same(tag + ' clip top', body.ClipRect.Top, arr.Strings[1]);
      Same(tag + ' clip width', body.ClipRect.Right - body.ClipRect.Left, arr.Strings[2]);
      Same(tag + ' clip height', body.ClipRect.Bottom - body.ClipRect.Top, arr.Strings[3]);
    end;
    { the style }
    st := item.Objects['style'];
    if st <> nil then
    begin
      if (typ = 'candlestick') and item.Booleans['simpleBox'] then
      begin
        { a stroke: its pen is the border }
        if ColourOf(ACase, st.Strings['stroke'], si, False, want) then
        begin
          Inc(FCompared);
          if body.Style.StrokeColor <> want then
            Bad(Format('%s: stroke %s here, %s upstream', [tag,
              IntToHex(body.Style.StrokeColor, 8), st.Strings['stroke']]));
        end;
      end
      else
      begin
        if ColourOf(ACase, st.Strings['fill'], si, True, want) then
        begin
          Inc(FCompared);
          if (not body.Style.HasFill) or (body.Style.FillColor <> want) then
            Bad(Format('%s: fill %s here, %s upstream', [tag,
              IntToHex(body.Style.FillColor, 8), st.Strings['fill']]));
        end;
        if ColourOf(ACase, st.Strings['stroke'], si, False, want) then
        begin
          Inc(FCompared);
          if body.Style.StrokeColor <> want then
            Bad(Format('%s: stroke %s here, %s upstream', [tag,
              IntToHex(body.Style.StrokeColor, 8), st.Strings['stroke']]));
        end;
        Same(tag + ' line width', body.Style.StrokeWidthLogical, st.Strings['lineWidth']);
        Same(tag + ' opacity', body.Style.Alpha, st.Strings['opacity']);
        { a candle's wicks are its body's pen }
        for j := 0 to High(wicks) do
        begin
          Inc(FCompared);
          if wicks[j].Style.StrokeColor <> body.Style.StrokeColor then
            Bad(tag + ': a wick in another pen');
        end;
      end;
    end;
  end;
end;

procedure TAdvChartCandleBoxplotTest.TestEveryChartIsLaidOutAsUpstreamLaysItOut;
var
  i, k: Integer;
  c: TJSONObject;
  ser: TJSONArray;
begin
  for i := 0 to Cases.Count - 1 do
  begin
    c := Cases.Objects[i];
    FWhere := c.Strings['id'];
    NewChart(c.Objects['option']);
    CheckLayout(c);
    ser := c.Arrays['series'];
    for k := 0 to ser.Count - 1 do CheckItems(c, ser.Objects[k]);
  end;
  Finish('layout');
end;

{ ==================== the tables ==================== }

procedure TAdvChartCandleBoxplotTest.TestTheTransformMakesUpstreamsTables;
var
  i, s, r, k: Integer;
  c, rec: TJSONObject;
  srcs, rows, want, got: TJSONArray;
  opt: TTyChartOption;
  cache: TTyDatasetCache;
  node: TJSONObject;
  d, cell: TJSONData;
  w: string;
  nCases: Integer;
  src: TTyChartSource;
begin
  nCases := 0;
  for i := 0 to Cases.Count - 1 do
  begin
    c := Cases.Objects[i];
    if c.Find('sources') = nil then Continue;
    Inc(nCases);
    FWhere := c.Strings['id'];
    opt := TTyChartOption.Create;
    cache := TTyDatasetCache.Create;
    try
      AssertTrue(FWhere + ': the option parses', opt.SetOptionText(c.Objects['option'].AsJSON));
      srcs := c.Arrays['sources'];
      for s := 0 to srcs.Count - 1 do
      begin
        rec := srcs.Objects[s];
        node := cache.ResultNode(opt, rec.Integers['dataset'], rec.Integers['result']);
        Inc(FCompared);
        if node = nil then
        begin
          Bad(Format('dataset %d result %d: none here', [rec.Integers['dataset'], rec.Integers['result']]));
          Continue;
        end;
        { the dimensions }
        d := node.Find('dimensions');
        Inc(FCompared);
        if rec.Find('dims').JSONType = jtNull then
        begin
          if (d <> nil) and (rec.Integers['dataset'] > 0) then
            Bad(Format('dataset %d result %d: dimensions here', [rec.Integers['dataset'], rec.Integers['result']]));
        end
        else if (d = nil) or (d.AsJSON <> rec.Arrays['dims'].AsJSON) then
          Bad(Format('dataset %d result %d: dimensions %s upstream', [rec.Integers['dataset'],
            rec.Integers['result'], rec.Arrays['dims'].AsJSON]));
        { the start index of result 0, as a series would read it }
        if rec.Integers['result'] = 0 then
        begin
          src := TySourceOf(opt, rec.Integers['dataset'], -1, cache);
          Inc(FCompared);
          if (not src.Valid) or (src.StartIndex <> rec.Integers['startIndex']) then
            Bad(Format('dataset %d: start %d here, %d upstream', [rec.Integers['dataset'],
              src.StartIndex, rec.Integers['startIndex']]));
        end;
        { the rows, cell by cell }
        rows := TJSONArray(node.Find('source'));
        want := rec.Arrays['rows'];
        Inc(FCompared);
        if (rows = nil) or (rows.Count <> want.Count) then
        begin
          Bad(Format('dataset %d result %d: rows differ in number', [rec.Integers['dataset'], rec.Integers['result']]));
          Continue;
        end;
        for r := 0 to want.Count - 1 do
        begin
          got := TJSONArray(rows.Items[r]);
          Inc(FCompared);
          if (got.Count <> want.Arrays[r].Count) then
          begin
            Bad(Format('row %d: %d cells here, %d upstream', [r, got.Count, want.Arrays[r].Count]));
            Continue;
          end;
          for k := 0 to got.Count - 1 do
          begin
            cell := got.Items[k];
            Inc(FCompared);
            if want.Arrays[r].Items[k].JSONType = jtNull then
            begin
              if cell.JSONType <> jtNull then Bad(Format('row %d cell %d: not null', [r, k]));
              Continue;
            end;
            w := want.Arrays[r].Strings[k];
            if Copy(w, 1, 2) = 's:' then
            begin
              if (cell.JSONType <> jtString) or (cell.AsString <> Copy(w, 3, MaxInt)) then
                Bad(Format('row %d cell %d: %s here, %s upstream', [r, k, cell.AsJSON, w]));
            end
            else if (cell.JSONType <> jtNumber) or not SameBits(cell.AsFloat, FromHex(w)) then
              Bad(Format('row %d cell %d: %s here, %s upstream', [r, k, cell.AsJSON,
                Txt(FromHex(w))]));
          end;
        end;
      end;
    finally
      cache.Free;
      opt.Free;
    end;
  end;
  AssertTrue('the transform cases', nCases >= 8);
  Finish('tables');
end;

{ ==================== the tooltip ==================== }

type
  TCbRow = record
    Marker, Name, Value: string;
    HasMarker, HasName, HasValue: Boolean;
  end;
  TCbRows = array of TCbRow;

function RowsOf(ABlock: TTyTooltipBlock): TCbRows;
var
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  i, j, k, n: Integer;
  row: TCbRow;
begin
  Result := nil;
  ink := Default(TTyTooltipInk);
  ink.NameWeight := 400;
  ink.ValueWeight := 900;
  ink.MarkerSizeLogical := 10;
  lines := TyTooltipFlatten(ABlock, ink);
  n := 0;
  for i := 0 to High(lines) do
  begin
    for k := 1 to lines[i].BlankLinesBefore do
    begin
      SetLength(Result, n + 1);
      Result[n] := Default(TCbRow);
      Inc(n);
    end;
    row := Default(TCbRow);
    for j := 0 to High(lines[i].Runs) do
      if lines[i].Runs[j].Kind = ttrMarker then
      begin
        row.HasMarker := True;
        if lines[i].Runs[j].MarkerSizeLogical = 10 then row.Marker := 'item'
        else row.Marker := 'subItem';
      end
      else if lines[i].Runs[j].FontWeight = 900 then
      begin
        row.HasValue := True;
        row.Value := lines[i].Runs[j].Text;
      end
      else
      begin
        row.HasName := True;
        row.Name := lines[i].Runs[j].Text;
      end;
    SetLength(Result, n + 1);
    Result[n] := row;
    Inc(n);
  end;
end;

function RowText(const R: TCbRow): string;
  function Q(AHas: Boolean; const S: string): string;
  begin
    if AHas then Result := '"' + S + '"' else Result := 'null';
  end;
begin
  Result := '{' + Q(R.HasMarker, R.Marker) + ' ' + Q(R.HasName, R.Name) + ' '
    + Q(R.HasValue, R.Value) + '}';
end;

function WantRowText(ARow: TJSONObject): string;
  function Q(const AKey: string): string;
  var d: TJSONData;
  begin
    d := ARow.Find(AKey);
    if (d = nil) or (d.JSONType = jtNull) then Result := 'null'
    else Result := '"' + d.AsString + '"';
  end;
begin
  Result := '{' + Q('marker') + ' ' + Q('name') + ' ' + Q('value') + '}';
end;

procedure TAdvChartCandleBoxplotTest.TestTheTooltipSaysWhatUpstreamSays;
var
  i, k, x, y, n: Integer;
  c, tip, hit: TJSONObject;
  block: TTyTooltipBlock;
  rows: TCbRows;
  got, exp, which: string;
  opt: TTyChartOption;
begin
  n := 0;
  for i := 0 to Cases.Count - 1 do
  begin
    c := Cases.Objects[i];
    if c.Find('tooltip') = nil then Continue;
    Inc(n);
    FWhere := c.Strings['id'];
    tip := c.Objects['tooltip'];
    NewChart(c.Objects['option']);
    x := tip.Arrays['at'].Integers[0];
    y := tip.Arrays['at'].Integers[1];
    FChart.Move(x, y);
    Frame;
    Inc(FCompared);
    if not FChart.TooltipShown then
    begin
      Bad('no box');
      Continue;
    end;
    which := FChart.TooltipShownWhich;
    block := nil;
    if tip.Strings['trigger'] = 'item' then
    begin
      hit := tip.Objects['hit'];
      Inc(FCompared);
      if which <> Format('item:%d:%d', [hit.Integers['seriesIndex'], hit.Integers['dataIndex']]) then
      begin
        Bad('shows ' + which);
        Continue;
      end;
      block := FChart.ContentOf(FChart.TooltipShownDatum);
    end
    else
    begin
      Inc(FCompared);
      if Copy(which, 1, 5) <> 'axis:' then
      begin
        Bad('shows ' + which);
        Continue;
      end;
      opt := TTyChartOption.Create;
      try
        opt.SetOptionText(c.Objects['option'].AsJSON);
        block := FChart.AxisContentAt(x, y, TyTooltipSpecOf(opt, -1, -1));
      finally
        opt.Free;
      end;
    end;
    try
      Inc(FCompared);
      if block = nil then
      begin
        Bad('no content');
        Continue;
      end;
      rows := RowsOf(block);
    finally
      block.Free;
    end;
    got := '';
    exp := '';
    for k := 0 to High(rows) do got := got + RowText(rows[k]);
    for k := 0 to tip.Arrays['lines'].Count - 1 do
      exp := exp + WantRowText(tip.Arrays['lines'].Objects[k]);
    Inc(FCompared);
    if got <> exp then Bad('rows ' + got + LineEnding + '    upstream ' + exp);
  end;
  AssertTrue('the tooltip cases', n >= 6);
  Finish('tooltip');
end;

{ ==================== the states ==================== }

procedure TAdvChartCandleBoxplotTest.TestAHighlightedBoxLooksAsUpstreamsDoes;
var
  i, k, j, n, raw, hi: Integer;
  c, e, st: TJSONObject;
  em: TJSONArray;
  lst: TTyPaintList;
  el: TTyChartElement;
  rest: array of TTyChartElement;
  found: Boolean;
  want, upRest, upNow: TTyChartColor;
  restCase: TJSONObject;
  restStyle: TJSONObject;
begin
  n := 0;
  for i := 0 to Cases.Count - 1 do
  begin
    c := Cases.Objects[i];
    if c.Find('emphasis') = nil then Continue;
    Inc(n);
    FWhere := c.Strings['id'];
    NewChart(c.Objects['option']);
    { the rest styles, before }
    lst := FChart.List;
    SetLength(rest, 0);
    for k := 0 to lst.Count - 1 do
    begin
      el := lst.Element(k);
      if (el.Datum.SeriesIndex = 0) and (el.Shape.Kind = cskPolygon) then
      begin
        raw := el.Datum.RawDataIndex;
        if raw >= Length(rest) then SetLength(rest, raw + 1);
        rest[raw] := el;
      end;
    end;
    restCase := c.Arrays['series'].Objects[0];
    em := c.Arrays['emphasis'];
    { the action, on the item upstream's emphasis state names }
    hi := -1;
    for k := 0 to em.Count - 1 do
      for j := 0 to em.Objects[k].Arrays['states'].Count - 1 do
        if em.Objects[k].Arrays['states'].Strings[j] = 'emphasis' then
          hi := em.Objects[k].Integers['i'];
    AssertTrue(FWhere + ': one emphasised', hi >= 0);
    FChart.DispatchAction(Format('{"type":"highlight","seriesIndex":0,"dataIndex":%d}', [hi]));
    Frame;
    lst := FChart.List;
    for k := 0 to em.Count - 1 do
    begin
      e := em.Objects[k];
      raw := e.Integers['i'];
      st := e.Objects['style'];
      found := False;
      for j := 0 to lst.Count - 1 do
      begin
        el := lst.Element(j);
        if (el.Datum.SeriesIndex <> 0) or (el.Datum.RawDataIndex <> raw)
          or (el.Shape.Kind <> cskPolygon) then Continue;
        found := True;
        Break;
      end;
      Inc(FCompared);
      if not found then
      begin
        Bad(Format('box %d: not drawn', [raw]));
        Continue;
      end;
      Same(Format('box %d line width', [raw]), el.Style.StrokeWidthLogical, st.Strings['lineWidth']);
      Same(Format('box %d opacity', [raw]), el.Style.Alpha, st.Strings['opacity']);
      Inc(FCompared);
      if (raw <= High(rest)) and (el.Z2 - rest[raw].Z2 <> e.Integers['z2'] - 100) then
        Bad(Format('box %d: z2 lifted by %d here, %d upstream', [raw,
          el.Z2 - rest[raw].Z2, e.Integers['z2'] - 100]));
      { the fill: written, exactly; else as upstream's moved from its rest }
      if ColourOf(c, st.Strings['fill'], 0, True, want)
        and (Pos('"' + LowerCase(st.Strings['fill']) + '"', LowerCase(c.Objects['option'].AsJSON)) > 0) then
      begin
        Inc(FCompared);
        if el.Style.FillColor <> want then
          Bad(Format('box %d: fill %s here, %s upstream', [raw, IntToHex(el.Style.FillColor, 8),
            st.Strings['fill']]));
      end
      else
      begin
        restStyle := restCase.Arrays['items'].Objects[raw].Objects['style'];
        upRest := 0;
        upNow := 0;
        TyTryParseChartColor(restStyle.Strings['fill'], upRest);
        TyTryParseChartColor(st.Strings['fill'], upNow);
        Inc(FCompared);
        if (upRest = upNow) <> ((raw <= High(rest)) and (el.Style.FillColor = rest[raw].Style.FillColor)) then
          Bad(Format('box %d: the fill moved %s upstream', [raw, BoolToStr(upRest <> upNow, True)]));
      end;
      if ColourOf(c, st.Strings['stroke'], 0, False, want) then
      begin
        Inc(FCompared);
        if el.Style.StrokeColor <> want then
          Bad(Format('box %d: stroke %s here, %s upstream', [raw, IntToHex(el.Style.StrokeColor, 8),
            st.Strings['stroke']]));
      end;
    end;
  end;
  AssertTrue('the emphasis cases', n >= 3);
  Finish('states');
end;

{ ==================== beyond the fixture ==================== }

procedure TAdvChartCandleBoxplotTest.TestTheQuantileIsUpstreamsInterpolation;
begin
  { H = (n - 1) p + 1: [1, 2, 3, 4] at 0.25 is 1.75 -> 1 + 0.75 (2 - 1) }
  AssertTrue(SameBits(TyQuantile([1, 2, 3, 4], 0.25), 1.75));
  AssertTrue(SameBits(TyQuantile([1, 2, 3, 4], 0.5), 2.5));
  { a whole position is the value there, not an interpolation }
  AssertTrue(SameBits(TyQuantile([1, 2, 3, 4, 5], 0.25), 2));
  { nothing: not-a-number }
  AssertTrue(IsNan(TyQuantile([], 0.5)));
  { one: itself at every quartile }
  AssertTrue(SameBits(TyQuantile([7], 0.75), 7));
end;

{ A SAMPLE THAT IS NOT A NUMBER compares false with everything -- here an
  ordered comparison with it would raise, so the reducer has to step round
  it; a row that is not a list makes nothing at all }
procedure TAdvChartCandleBoxplotTest.TestANaNSampleIsNeverAnOutlier;
var
  raw: TJSONData;
  boxes, outs: TJSONArray;
begin
  raw := GetJSON('[[1, "x", 3, 50], [2, 4]]');
  try
    AssertTrue(TyPrepareBoxplotData(TJSONArray(raw), nil, boxes, outs));
    try
      AssertEquals('two boxes', 2, boxes.Count);
      { [1, NaN, 3, 50]: NaN sorts where it was; the quartiles are NaN
        wherever it is read, so low and high are NaN and nothing is out }
      AssertEquals('no outliers', 0, outs.Count);
    finally
      boxes.Free;
      outs.Free;
    end;
  finally
    raw.Free;
  end;
  raw := GetJSON('[[1, 2], 3]');
  try
    AssertFalse('a row that is not a list', TyPrepareBoxplotData(TJSONArray(raw), nil, boxes, outs));
    AssertNull(boxes);
  finally
    raw.Free;
  end;
end;

procedure TAdvChartCandleBoxplotTest.TestATransformNobodyRegisteredHasNoTable;
var
  opt: TTyChartOption;
  cache: TTyDatasetCache;
begin
  opt := TTyChartOption.Create;
  cache := TTyDatasetCache.Create;
  try
    AssertTrue(opt.SetOptionText('{"dataset":[{"source":[[1,2],[3,4]]},' +
      '{"transform":{"type":"filter","config":{"dimension":0,">":1}}},' +
      '{"transform":[]},{"transform":{"type":"boxplot"},"fromDatasetIndex":9},' +
      '{"source":[{"a":1}]},{"transform":{"type":"boxplot"},"fromDatasetIndex":4}]}'));
    { D2's, not here yet }
    AssertNull('a filter', cache.ResultNode(opt, 1, 0));
    { an empty pipe throws upstream }
    AssertNull('an empty pipe', cache.ResultNode(opt, 2, 0));
    { an upstream naming nothing }
    AssertNull('no upstream', cache.ResultNode(opt, 3, 0));
    { a table of objects is not a boxplot's input }
    AssertNull('object rows', cache.ResultNode(opt, 5, 0));
    { and the root is itself }
    AssertNotNull('a root dataset', cache.ResultNode(opt, 0, 0));
    AssertNull('a root dataset has one result', cache.ResultNode(opt, 0, 1));
    { without a cache a computed dataset has no source at all }
    AssertFalse(TySourceOf(opt, 1, -1, nil).Valid);
  finally
    cache.Free;
    opt.Free;
  end;
end;

procedure TAdvChartCandleBoxplotTest.TestADatasetReadingItselfHasNoTable;
var
  opt: TTyChartOption;
  cache: TTyDatasetCache;
begin
  opt := TTyChartOption.Create;
  cache := TTyDatasetCache.Create;
  try
    { a cycle: 0 reads 1 and 1 reads 0 -- upstream recurses for ever; here
      neither has a table, and nothing hangs }
    AssertTrue(opt.SetOptionText('{"dataset":[' +
      '{"transform":{"type":"boxplot"},"fromDatasetIndex":1},' +
      '{"transform":{"type":"boxplot"},"fromDatasetIndex":0}]}'));
    AssertNull(cache.ResultNode(opt, 0, 0));
    AssertNull(cache.ResultNode(opt, 1, 0));
  finally
    cache.Free;
    opt.Free;
  end;
end;

procedure TAdvChartCandleBoxplotTest.TestTheCandleWidthRules;
var
  bw, bmax, bmin: TJSONData;
begin
  { the defaults: half a band between 1 and the band }
  AssertTrue(SameBits(TyCandleWidthOf(30, nil, nil, nil), 15));
  AssertTrue(SameBits(TyCandleWidthOf(1.5, nil, nil, nil), 1));
  bw := GetJSON('"10%"');
  bmax := GetJSON('8');
  bmin := GetJSON('"60%"');
  try
    { barWidth wins outright, the percent of the band }
    AssertTrue(SameBits(TyCandleWidthOf(50, bw, bmax, bmin), 5));
    { the cap, then the floor outermost }
    AssertTrue(SameBits(TyCandleWidthOf(50, nil, bmax, nil), 8));
    AssertTrue(SameBits(TyCandleWidthOf(50, nil, bmax, bmin), 30));
  finally
    bw.Free;
    bmax.Free;
    bmin.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartCandleBoxplotTest);
end.
