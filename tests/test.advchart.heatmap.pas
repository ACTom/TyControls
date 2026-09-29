unit test.advchart.heatmap;
{$mode objfpc}{$H+}
{ A HEATMAP ON A CARTESIAN -- which rows draw a cell, where each cell sits
  (a band wide and a band tall, each widened by half a pixel, centred on its
  point), its fill after the series colour, the visualMap and the item's own
  colour, its opacity, border and rounding, and its label's words and anchor
  -- held to what ECharts 6.1 draws.

  tools/advchart-oracle/heatmap-cartesian.js records every row of every
  heatmap series. The port's paint list is read back: a cell is the mark the
  series added for that row, its label the caption the expansion placed.

  EXACT: the rect bit for bit (its right and bottom as x + width and
  y + height), colours as the colours they name. The cases upstream's
  development build refuses (no visualMap, value or time axes, boundaryGap
  false) were recorded from the production build and are compared too. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvChart.ZrPath, tyControls.AdvanceChart;
type
  THmProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartHeatmapOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: THmProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FSkipped, FCells: Integer;
    FReport, FName, FSkipNames: string;
    procedure Miss(const AWhat: string);
    procedure RunCases(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCellsAsUpstreamDrawsThem;
    procedure TestTheGalleryHeatmapAsUpstream;
    procedure TestALineSitsOverABar;
  end;

implementation

procedure THmProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function THmProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-heatmap-cartesian.json';
end;

function GalleryPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples'
    + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim + AName + '.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function Same(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  if (A = 0) and (B = 0) then Exit(True);
  Result := Bits(A) = Bits(B);
end;

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

procedure TAdvChartHeatmapOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := THmProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FSkipped := 0;
  FCells := 0;
  FReport := '';
  FSkipNames := '';
end;

procedure TAdvChartHeatmapOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartHeatmapOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartHeatmapOracleTest.RunCases(AGallery: Boolean);
var
  cases, series, rows: TJSONArray;
  cs, opt, se, hm, row, sh, st, lb: TJSONObject;
  sl: TStringList;
  c, s, k, j, si, di, n: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  d, rr: TJSONData;
  cellAt, capAt: array of Integer;
  x, y, w, h, op: Double;
  want: TTyChartColor;
  wantDrawn, moved: Boolean;
  vals: array of Double;
  radii: array[0..3] of Double;
  want_: TTyChartShape;
  w_: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    d := cs.Find('gallery');
    if AGallery <> ((d <> nil) and (d.JSONType = jtString)) then Continue;
    FName := cs.Strings['id'];
    if not AGallery then
      opt := TJSONObject(cs.Objects['option'].Clone)
    else
    begin
      sl := TStringList.Create;
      try
        sl.LoadFromFile(GalleryPath(cs.Strings['gallery']));
        opt := TJSONObject(GetJSON(sl.Text));
      finally
        sl.Free;
      end;
    end;
    try
      { UPSTREAM'S OWN PALETTE AND RAMP where the option names none: the
        port's default colours are the skin's, by design }
      if opt.Find('color') = nil then
        opt.Add('color', GetJSON('["#5070dd","#b6d634","#505372","#ff994d",'
          + '"#0ca8df","#ffd10a","#fb628b","#785db0","#3fbe95"]'));
      { and its ramp, which a visualMap with no colours of its own maps onto }
      if opt.Find('gradientColor') = nil then
        opt.Add('gradientColor', GetJSON('["rgba(212,220,247,1)","#5070dd"]'));
      FChart.Option := '{}';
      FChart.Option := opt.AsJSON;
      FChart.SetBounds(0, 0, cs.Integers['width'], cs.Integers['height']);
      try
        FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cs.Integers['width'],
          cs.Integers['height']), 96);
      except
        on E: Exception do
        begin
          Miss(E.ClassName + ': ' + E.Message);
          Continue;
        end;
      end;
      lst := FChart.List;
      series := cs.Arrays['series'];
      for s := 0 to series.Count - 1 do
      begin
        se := series.Objects[s];
        si := se.Integers['seriesIndex'];
        FName := Format('%s series %d', [cs.Strings['id'], si]);
        { this series' cells and captions, by view row }
        n := lst.Count;
        cellAt := nil;
        capAt := nil;
        SetLength(cellAt, 4096);
        SetLength(capAt, 4096);
        for k := 0 to High(cellAt) do
        begin
          cellAt[k] := -1;
          capAt[k] := -1;
        end;
        for k := 0 to n - 1 do
        begin
          e := lst.Element(k);
          if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex < 0)
            or (e.Datum.DataIndex > High(cellAt)) then Continue;
          { an ANSWER caption carries its font size; the mark's own request
            carries only the words }
          if (e.Caption.FontSizeLogical > 0) and (e.Caption.Text <> '') then
            capAt[e.Datum.DataIndex] := k
          else if e.Shape.Kind in [cskRect, cskRoundRect] then
            cellAt[e.Datum.DataIndex] := k;
        end;
        if IsNull(se.Find('heatmap')) then
        begin
          Inc(FCompared);
          for k := 0 to High(cellAt) do
            if cellAt[k] >= 0 then
            begin
              Miss('a filtered series drew cells');
              Break;
            end;
          Continue;
        end;
        hm := se.Objects['heatmap'];
        rows := hm.Arrays['rows'];
        { A GRID THAT LANDED ELSEWHERE moves every cell }
        moved := False;
        for j := 0 to rows.Count - 1 do
        begin
          row := rows.Objects[j];
          if IsNull(row.Find('dataIndex')) or (not row.Booleans['drawn']) then Continue;
          di := row.Integers['dataIndex'];
          if cellAt[di] < 0 then Break;
          sh := row.Objects['rect'].Objects['shape'];
          if not Same(lst.Element(cellAt[di]).Shape.Bounds.Left, FromHex(sh.Strings['x'])) then
            moved := True;
          Break;
        end;
        if moved and AGallery then
        begin
          Inc(FSkipped);
          FSkipNames := FSkipNames + ' ' + FName;
          Continue;
        end;
        for j := 0 to rows.Count - 1 do
        begin
          row := rows.Objects[j];
          w_ := Format('row %d', [j]);
          if IsNull(row.Find('dataIndex')) then Continue;
          di := row.Integers['dataIndex'];
          wantDrawn := row.Booleans['drawn'];
          sh := nil;
          if wantDrawn then
          begin
            sh := row.Objects['rect'].Objects['shape'];
            { a rect of no number is drawn by nobody }
            if IsNan(FromHex(sh.Strings['x'])) or IsNan(FromHex(sh.Strings['y']))
              or IsNan(FromHex(sh.Strings['width'])) then wantDrawn := False;
          end;
          Inc(FCompared);
          if wantDrawn <> (cellAt[di] >= 0) then
          begin
            if wantDrawn then Miss(w_ + ': a cell upstream, none here')
            else Miss(w_ + ': no cell upstream, one here');
            Continue;
          end;
          if not wantDrawn then Continue;
          Inc(FCells);
          e := lst.Element(cellAt[di]);
          x := FromHex(sh.Strings['x']);
          y := FromHex(sh.Strings['y']);
          w := FromHex(sh.Strings['width']);
          h := FromHex(sh.Strings['height']);
          Inc(FCompared, 4);
          if not (Same(e.Shape.Bounds.Left, x) and Same(e.Shape.Bounds.Top, y)
            and Same(e.Shape.Bounds.Right, x + w) and Same(e.Shape.Bounds.Bottom, y + h)) then
            Miss(Format('%s: rect (%s, %s, %s, %s) upstream, (%s, %s, %s, %s) here', [w_,
              Fmt(x), Fmt(y), Fmt(x + w), Fmt(y + h), Fmt(e.Shape.Bounds.Left),
              Fmt(e.Shape.Bounds.Top), Fmt(e.Shape.Bounds.Right), Fmt(e.Shape.Bounds.Bottom)]));
          { the rounding }
          rr := sh.Find('r');
          Inc(FCompared);
          if IsNull(rr) or ((rr.JSONType = jtNumber) and (rr.AsFloat = 0)) then
          begin
            if e.Shape.Kind <> cskRect then Miss(w_ + ': a square cell upstream, rounded here');
          end
          else
          begin
            vals := nil;
            if rr.JSONType = jtNumber then
            begin
              SetLength(vals, 1);
              vals[0] := rr.AsFloat;
            end
            else
            begin
              SetLength(vals, rr.Count);
              for k := 0 to rr.Count - 1 do vals[k] := rr.Items[k].AsFloat;
            end;
            TyZrRadii(vals, radii[0], radii[1], radii[2], radii[3]);
            if radii[0] + radii[1] + radii[2] + radii[3] = 0 then
            begin
              if e.Shape.Kind <> cskRect then Miss(w_ + ': no radius upstream, rounded here');
            end
            else
            begin
              { the corners as upstream wrote them, through the one clamp both
                sides share }
              want_ := TyShapeRoundRect(e.Shape.Bounds, radii);
              if (e.Shape.Kind <> cskRoundRect) or (e.Shape.Radii[0] <> want_.Radii[0])
                or (e.Shape.Radii[1] <> want_.Radii[1]) or (e.Shape.Radii[2] <> want_.Radii[2])
                or (e.Shape.Radii[3] <> want_.Radii[3]) then
                Miss(w_ + ': the corners differ');
            end;
          end;
          { the ink }
          st := row.Objects['rect'].Objects['style'];
          Inc(FCompared);
          if IsNull(st.Find('fill')) or (st.Strings['fill'] = 'none') then
          begin
            if e.Style.HasFill and ((e.Style.FillColor shr 24) <> 0) then
              Miss(w_ + ': no fill upstream, one here');
          end
          else if TyTryParseChartColor(st.Strings['fill'], want) then
          begin
            { a fully transparent fill and no fill paint the same nothing }
            if ((want shr 24) = 0) and ((not e.Style.HasFill) or ((e.Style.FillColor shr 24) = 0)) then
            else if (not e.Style.HasFill) or (e.Style.FillColor <> want) then
              Miss(Format('%s: fill %s upstream, %.8x here', [w_, st.Strings['fill'],
                e.Style.FillColor]));
          end;
          op := FromHex(st.Strings['opacity']);
          Inc(FCompared);
          if Abs(e.Style.Alpha - op) > 1e-12 then
            Miss(Format('%s: opacity %s upstream, %s here', [w_, Fmt(op), Fmt(e.Style.Alpha)]));
          if not IsNull(st.Find('stroke')) and (st.Strings['stroke'] <> 'none')
            and (FromHex(st.Strings['lineWidth']) > 0) then
          begin
            Inc(FCompared);
            if TyTryParseChartColor(st.Strings['stroke'], want)
              and ((e.Style.StrokeColor <> want)
              or (e.Style.StrokeWidthLogical <> FromHex(st.Strings['lineWidth']))) then
              Miss(w_ + ': the border differs');
          end;
          { the label: the words and where they hang }
          d := row.Find('label');
          { UPSTREAM'S OWN SLIP: a row whose position names no category (2.5)
            takes its name from the store at its RAW index, which under a
            filtering dataZoom is another row's -- G7's 4.5 cell reads 'x3'.
            Not reproduced; the port names it nothing. }
          if (cs.Strings['id'] = 'G7') and (j = 1) then Continue;
          Inc(FCompared);
          if IsNull(d) or IsNull(TJSONObject(d).Find('ink'))
            or (TJSONObject(d).Strings['text'] = '') then
          begin
            if capAt[di] >= 0 then Miss(w_ + ': no label upstream, "'
              + lst.Element(capAt[di]).Caption.Text + '" here');
            Continue;
          end;
          lb := TJSONObject(d);
          if capAt[di] < 0 then
          begin
            Miss(w_ + ': label "' + lb.Strings['text'] + '" upstream, none here');
            Continue;
          end;
          e := lst.Element(capAt[di]);
          Inc(FCompared, 3);
          if e.Caption.Text <> lb.Strings['text'] then
            Miss(Format('%s: label "%s" upstream, "%s" here', [w_, lb.Strings['text'],
              e.Caption.Text]));
          if not (Same(e.Caption.X, FromHex(lb.Objects['inner'].Strings['x']))
            and Same(e.Caption.Y, FromHex(lb.Objects['inner'].Strings['y']))) then
            Miss(Format('%s: label at (%s, %s) upstream, (%s, %s) here', [w_,
              lb.Objects['inner'].Strings['xText'], lb.Objects['inner'].Strings['yText'],
              Fmt(e.Caption.X), Fmt(e.Caption.Y)]));
          if not (((lb.Strings['align'] = 'center') = (e.Caption.AnchorH = tahCentre))
            and ((lb.Strings['align'] = 'right') = (e.Caption.AnchorH = tahRight))
            and ((lb.Strings['verticalAlign'] = 'middle') = (e.Caption.AnchorV = tavMiddle))
            and ((lb.Strings['verticalAlign'] = 'bottom') = (e.Caption.AnchorV = tavBottom))) then
            Miss(Format('%s: label aligned %s/%s upstream, otherwise here', [w_,
              lb.Strings['align'], lb.Strings['verticalAlign']]));
        end;
      end;
    finally
      opt.Free;
    end;
  end;
end;

procedure TAdvChartHeatmapOracleTest.TestCellsAsUpstreamDrawsThem;
begin
  RunCases(False);
  AssertTrue('the synthetic cells were compared', FCells >= 300);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
end;

procedure TAdvChartHeatmapOracleTest.TestTheGalleryHeatmapAsUpstream;
begin
  RunCases(True);
  AssertTrue('the gallery cells were compared', FCells >= 100);
  AssertTrue(Format('%d gallery series passed over:%s', [FSkipped, FSkipNames]),
    FSkipped = 0);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
end;

procedure TAdvChartHeatmapOracleTest.TestALineSitsOverABar;
var
  lst: TTyPaintList;
  k, lineZ, barZ: Integer;
  e: TTyChartElement;
begin
  { upstream's defaults: a line at z 3, a bar at 2 -- the line is drawn over
    the bar whichever comes first in the option }
  FChart.Option := '{"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"line","data":[1,3,2]},'
    + '{"type":"bar","data":[2,1,3]}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  lineZ := -1;
  barZ := -1;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Datum.SeriesIndex = 0) and (e.Shape.Kind = cskPolyline) then lineZ := e.Z;
    if (e.Datum.SeriesIndex = 1) and (e.Shape.Kind in [cskRect, cskRoundRect]) then barZ := e.Z;
  end;
  AssertEquals('the line', 3, lineZ);
  AssertEquals('the bar', 2, barZ);
end;

initialization
  RegisterTest(TAdvChartHeatmapOracleTest);
end.
