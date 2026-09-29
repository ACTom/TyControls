unit test.advchart.heatmapcal;
{$mode objfpc}{$H+}
{ A HEATMAP ON A CALENDAR -- which rows draw a cell, where each cell sits
  (the calendar's content rect for the row's date), its fill after the
  series colour, the visualMap and the item's own colour, its opacity,
  border and rounding, its label's words and anchor, and where the cell
  falls in the paint order against the calendar's own furniture -- held to
  what ECharts 6.1 draws.

  tools/advchart-oracle/heatmap-calendar.js records every row of every
  heatmap series under TZ=UTC. The port reads a date string on the local
  wall clock just as upstream does, so those agree in any zone; a row whose
  date is a NUMBER, or a string naming its own offset, lands on a
  zone-dependent day and is compared only when this machine runs at UTC. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvChart.ZrPath, tyControls.AdvanceChart;
type
  THcProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartHeatmapCalendarOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: THcProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FCells, FZoned: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure RunCases(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCellsAsUpstreamDrawsThem;
    procedure TestTheGalleryCalendarsAsUpstream;
  end;

implementation

procedure THcProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function THcProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-heatmap-calendar.json';
end;

function GalleryPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples'
    + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim + AName + '.json';
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

{ a fixture number: null is NaN, and the three reserved strings }
function Num(A: TJSONData): Double;
begin
  if IsNull(A) then Exit(NaN);
  if A.JSONType = jtString then
  begin
    if A.AsString = 'Infinity' then Exit(Infinity);
    if A.AsString = '-Infinity' then Exit(NegInfinity);
    if A.AsString = '-0' then Exit(-0.0);
    Exit(NaN);
  end;
  Result := A.AsFloat;
end;

{ A DATE WHOSE DAY DEPENDS ON THE ZONE: a number (or a boolean), or a
  string that names its own offset. }
function ZoneDependent(ARaw: TJSONData): Boolean;
var
  d: TJSONData;
  s: string;
  p: Integer;
begin
  Result := False;
  d := ARaw;
  if (d <> nil) and (d.JSONType = jtObject) then d := TJSONObject(d).Find('value');
  if (d = nil) or (d.JSONType <> jtArray) or (d.Count = 0) then Exit;
  d := d.Items[0];
  if d.JSONType in [jtNumber, jtBoolean] then Exit(True);
  if d.JSONType <> jtString then Exit;
  s := d.AsString;
  if (s <> '') and (UpCase(s[Length(s)]) = 'Z') then Exit(True);
  { an offset after the time: +hh, -hh, with or without minutes }
  p := Length(s);
  while (p > 11) and not (s[p] in ['+', '-']) do Dec(p);
  Result := (p > 11) and (s[p] in ['+', '-']);
end;

{ a null or empty value that upstream's ordinal guess keeps and draws }
function OrdinalGap(AHm, ARow: TJSONObject): Boolean;
var
  types, raw, v: TJSONData;
begin
  Result := False;
  types := AHm.Find('dimensionTypes');
  if (types = nil) or (types.JSONType <> jtArray) or (types.Count < 2) then Exit;
  if types.Items[1].AsString <> 'ordinal' then Exit;
  raw := ARow.Find('raw');
  if (raw <> nil) and (raw.JSONType = jtObject) then raw := TJSONObject(raw).Find('value');
  if (raw = nil) or (raw.JSONType <> jtArray) or (raw.Count < 2) then Exit;
  v := raw.Items[1];
  Result := IsNull(v) or ((v.JSONType = jtString) and (v.AsString = ''));
end;

procedure TAdvChartHeatmapCalendarOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := THcProbe.Create(FForm);
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
  FCells := 0;
  FZoned := 0;
  FReport := '';
end;

procedure TAdvChartHeatmapCalendarOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartHeatmapCalendarOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartHeatmapCalendarOracleTest.RunCases(AGallery: Boolean);
var
  cases, series, rows: TJSONArray;
  cs, opt, se, hm, row, sh, st, lb, rc: TJSONObject;
  sl: TStringList;
  c, s, k, j, si, di, n: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  d, rr: TJSONData;
  cellAt, capAt: array of Integer;
  x, y, w, h, op: Double;
  want: TTyChartColor;
  wantDrawn: Boolean;
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
      if opt.Find('gradientColor') = nil then
        opt.Add('gradientColor', GetJSON('["rgba(212,220,247,1)","#5070dd"]'));
      FChart.Option := '{}';
      FChart.Option := opt.AsJSON;
      FChart.SetBounds(0, 0, 800, 600);
      try
        FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
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
        if not se.Get('recorded', False) then Continue;
        si := se.Integers['seriesIndex'];
        FName := Format('%s series %d', [cs.Strings['id'], si]);
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
        for j := 0 to rows.Count - 1 do
        begin
          row := rows.Objects[j];
          di := row.Integers['index'];
          w_ := Format('row %d', [di]);
          if (GetLocalTimeOffset <> 0) and ZoneDependent(row.Find('raw')) then
          begin
            Inc(FZoned);
            Continue;
          end;
          wantDrawn := row.Booleans['drawn'];
          { UPSTREAM'S ORDINAL GUESS: a value dimension whose first rows hold
            a word is kept raw, and isNaN(null) and isNaN('') are false -- so
            a null or empty value draws a cell. Not reproduced: the port reads
            the value as a number and those rows are gaps. }
          if wantDrawn and OrdinalGap(hm, row) then Continue;
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
          rc := row.Objects['rect'];
          sh := rc.Objects['shape'];
          x := Num(sh.Find('x'));
          y := Num(sh.Find('y'));
          w := Num(sh.Find('width'));
          h := Num(sh.Find('height'));
          Inc(FCompared, 4);
          if not (Same(e.Shape.Bounds.Left, x) and Same(e.Shape.Bounds.Top, y)
            and Same(e.Shape.Bounds.Right, x + w) and Same(e.Shape.Bounds.Bottom, y + h)) then
            Miss(Format('%s: rect (%s, %s, %s, %s) upstream, (%s, %s, %s, %s) here', [w_,
              Fmt(x), Fmt(y), Fmt(x + w), Fmt(y + h), Fmt(e.Shape.Bounds.Left),
              Fmt(e.Shape.Bounds.Top), Fmt(e.Shape.Bounds.Right), Fmt(e.Shape.Bounds.Bottom)]));
          { the paint order: z as the series, z2 1 -- over the day cells,
            under the month lines }
          Inc(FCompared, 2);
          if e.Z <> rc.Integers['z'] then
            Miss(Format('%s: z %d upstream, %d here', [w_, rc.Integers['z'], e.Z]));
          if e.Z2 <> rc.Integers['z2'] then
            Miss(Format('%s: z2 %d upstream, %d here', [w_, rc.Integers['z2'], e.Z2]));
          { the rounding }
          rr := rc.Find('r');
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
              for k := 0 to rr.Count - 1 do vals[k] := Num(rr.Items[k]);
            end;
            TyZrRadii(vals, radii[0], radii[1], radii[2], radii[3]);
            if radii[0] + radii[1] + radii[2] + radii[3] = 0 then
            begin
              if e.Shape.Kind <> cskRect then Miss(w_ + ': no radius upstream, rounded here');
            end
            else
            begin
              want_ := TyShapeRoundRect(e.Shape.Bounds, radii);
              if (e.Shape.Kind <> cskRoundRect) or (e.Shape.Radii[0] <> want_.Radii[0])
                or (e.Shape.Radii[1] <> want_.Radii[1]) or (e.Shape.Radii[2] <> want_.Radii[2])
                or (e.Shape.Radii[3] <> want_.Radii[3]) then
                Miss(w_ + ': the corners differ');
            end;
          end;
          { the ink }
          st := row.Objects['style'];
          Inc(FCompared);
          if IsNull(st.Find('fill')) or (st.Get('fill', '') = 'none') then
          begin
            if e.Style.HasFill and ((e.Style.FillColor shr 24) <> 0) then
              Miss(w_ + ': no fill upstream, one here');
          end
          else if TyTryParseChartColor(st.Get('fill', ''), want) then
          begin
            if ((want shr 24) = 0) and ((not e.Style.HasFill) or ((e.Style.FillColor shr 24) = 0)) then
            else if (not e.Style.HasFill) or (e.Style.FillColor <> want) then
              Miss(Format('%s: fill %s upstream, %.8x here', [w_, st.Get('fill', ''),
                e.Style.FillColor]));
          end;
          if st.Find('opacity') <> nil then op := Num(st.Find('opacity')) else op := 1;
          Inc(FCompared);
          if Abs(e.Style.Alpha - op) > 1e-12 then
            Miss(Format('%s: opacity %s upstream, %s here', [w_, Fmt(op), Fmt(e.Style.Alpha)]));
          if not IsNull(st.Find('stroke')) and (st.Get('stroke', '') <> 'none')
            and (Num(st.Find('lineWidth')) > 0) then
          begin
            Inc(FCompared);
            if TyTryParseChartColor(st.Get('stroke', ''), want)
              and ((e.Style.StrokeColor <> want)
              or (e.Style.StrokeWidthLogical <> Num(st.Find('lineWidth')))) then
              Miss(w_ + ': the border differs');
          end;
          { the label: the words and where they hang }
          d := row.Find('label');
          Inc(FCompared);
          if IsNull(d) or IsNull(TJSONObject(d).Find('ink'))
            or (TJSONObject(d).Get('text', '') = '') then
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
          Inc(FCompared, 4);
          if e.Caption.Text <> lb.Strings['text'] then
            Miss(Format('%s: label "%s" upstream, "%s" here', [w_, lb.Strings['text'],
              e.Caption.Text]));
          if not (Same(e.Caption.X, Num(lb.Objects['inner'].Find('x')))
            and Same(e.Caption.Y, Num(lb.Objects['inner'].Find('y')))) then
            Miss(Format('%s: label at (%s, %s) upstream, (%s, %s) here', [w_,
              Fmt(Num(lb.Objects['inner'].Find('x'))), Fmt(Num(lb.Objects['inner'].Find('y'))),
              Fmt(e.Caption.X), Fmt(e.Caption.Y)]));
          if not (((lb.Strings['align'] = 'center') = (e.Caption.AnchorH = tahCentre))
            and ((lb.Strings['align'] = 'right') = (e.Caption.AnchorH = tahRight))
            and ((lb.Strings['verticalAlign'] = 'middle') = (e.Caption.AnchorV = tavMiddle))
            and ((lb.Strings['verticalAlign'] = 'bottom') = (e.Caption.AnchorV = tavBottom))) then
            Miss(Format('%s: label aligned %s/%s upstream, otherwise here', [w_,
              lb.Strings['align'], lb.Strings['verticalAlign']]));
          { over its cell, under the calendar's month lines (20) }
          if not ((e.Z2 > lst.Element(cellAt[di]).Z2) and (e.Z2 < 20)) then
            Miss(Format('%s: label z2 %d, not between its cell and the month lines',
              [w_, e.Z2]));
        end;
      end;
    finally
      opt.Free;
    end;
  end;
end;

procedure TAdvChartHeatmapCalendarOracleTest.TestCellsAsUpstreamDrawsThem;
begin
  RunCases(False);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the synthetic cells were compared (%d, %d zoned)', [FCells, FZoned]), FCells >= 250);
end;

procedure TAdvChartHeatmapCalendarOracleTest.TestTheGalleryCalendarsAsUpstream;
begin
  RunCases(True);
  AssertTrue(Format('the gallery cells were compared (%d)', [FCells]), FCells >= 1000);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
end;

initialization
  RegisterTest(TAdvChartHeatmapCalendarOracleTest);
end.
