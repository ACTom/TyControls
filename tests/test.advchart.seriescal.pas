unit test.advchart.seriescal;
{$mode objfpc}{$H+}
{ SERIES ON A CALENDAR other than a heatmap -- a scatter's and an
  effectScatter's symbols (where each lands, its size, ink and z2), an
  effectScatter's ripples as upstream's static first frame, and the
  symbols' labels -- held to what ECharts 6.1 draws.

  tools/advchart-oracle/series-calendar.js records every row under TZ=UTC. A
  row whose date is a number lands on a zone-dependent day and is compared
  only when this machine runs at UTC. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvanceChart;
type
  TScProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartSeriesCalendarOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TScProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FSymbols, FRipples, FZoned: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure RunSymbols(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestScatterSymbolsAsUpstreamDrawsThem;
    procedure TestTheGallerySymbolsAsUpstream;
  end;

implementation

procedure TScProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TScProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-series-calendar.json';
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

function Near(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) or IsInfinite(A) or IsInfinite(B) then
    Exit(IsNan(A) and IsNan(B));
  Result := Abs(A - B) <= 1e-9 * Max(1, Abs(B));
end;

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

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
  p := Length(s);
  while (p > 11) and not (s[p] in ['+', '-']) do Dec(p);
  Result := (p > 11) and (s[p] in ['+', '-']);
end;

procedure TAdvChartSeriesCalendarOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TScProbe.Create(FForm);
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
  FSymbols := 0;
  FRipples := 0;
  FZoned := 0;
  FReport := '';
end;

procedure TAdvChartSeriesCalendarOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartSeriesCalendarOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartSeriesCalendarOracleTest.RunSymbols(AGallery: Boolean);
var
  cases, series, rows: TJSONArray;
  cs, opt, se, row, sy, st, lb, pa, eff: TJSONObject;
  sl: TStringList;
  c, s, k, j, si, di, n, ripN: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  d: TJSONData;
  symAt, capAt, ripCount: array of Integer;
  cx, cy, w, h, op: Double;
  want: TTyChartColor;
  wantDrawn: Boolean;
  w_, ty: string;
  b: TTyRectF;
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
        ty := se.Get('type', '');
        if (ty <> 'scatter') and (ty <> 'effectScatter') then Continue;
        si := se.Integers['seriesIndex'];
        FName := Format('%s series %d', [cs.Strings['id'], si]);
        n := lst.Count;
        SetLength(symAt, 0);
        SetLength(capAt, 0);
        SetLength(ripCount, 0);
        SetLength(symAt, 4096);
        SetLength(capAt, 4096);
        SetLength(ripCount, 4096);
        for k := 0 to High(symAt) do
        begin
          symAt[k] := -1;
          capAt[k] := -1;
          ripCount[k] := 0;
        end;
        for k := 0 to n - 1 do
        begin
          e := lst.Element(k);
          if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex < 0)
            or (e.Datum.DataIndex > High(symAt)) then Continue;
          if (e.Caption.FontSizeLogical > 0) and (e.Caption.Text <> '') then
            capAt[e.Datum.DataIndex] := k
          else if e.Z2 = 99 then
            Inc(ripCount[e.Datum.DataIndex])
          else
            symAt[e.Datum.DataIndex] := k;
        end;
        if se.Find('rows') = nil then Continue;
        rows := se.Arrays['rows'];
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
          Inc(FCompared);
          if wantDrawn <> (symAt[di] >= 0) then
          begin
            if wantDrawn then Miss(w_ + ': a symbol upstream, none here')
            else Miss(w_ + ': no symbol upstream, one here');
            Continue;
          end;
          if not wantDrawn then Continue;
          Inc(FSymbols);
          e := lst.Element(symAt[di]);
          sy := row.Objects['symbol'];
          pa := sy.Objects['path'];
          { where it lands: the cell centre, moved by symbolOffset }
          cx := Num(sy.Find('x')) + Num(pa.Find('x'));
          cy := Num(sy.Find('y')) + Num(pa.Find('y'));
          b := TyShapeBounds(e.Shape);
          Inc(FCompared, 2);
          if Num(pa.Find('rotation')) = 0 then
          begin
            ty := sy.Get('pathType', '');
            if not (Near((b.Left + b.Right) / 2, cx) and Near((b.Top + b.Bottom) / 2, cy))
              and ((ty = 'circle') or (ty = 'rect') or (ty = 'roundRect')
                or (ty = 'diamond')) then
              Miss(Format('%s: %s centred at (%s, %s) upstream, (%s, %s) here', [w_, ty,
                Fmt(cx), Fmt(cy), Fmt((b.Left + b.Right) / 2), Fmt((b.Top + b.Bottom) / 2)]));
            w := Num(sy.Arrays['size'].Items[0]);
            h := Num(sy.Arrays['size'].Items[1]);
            if ((ty = 'circle') or (ty = 'rect') or (ty = 'roundRect') or (ty = 'diamond'))
              and not (Near(b.Right - b.Left, w) and Near(b.Bottom - b.Top, h)) then
              Miss(Format('%s: %s %s x %s upstream, %s x %s here', [w_, ty, Fmt(w), Fmt(h),
                Fmt(b.Right - b.Left), Fmt(b.Bottom - b.Top)]));
          end
          else
          begin
            { TURNED: a round symbol keeps its box, a rect a quarter-turn
              swaps its sides }
            ty := sy.Get('pathType', '');
            w := Num(sy.Arrays['size'].Items[0]);
            h := Num(sy.Arrays['size'].Items[1]);
            { and a round one turns about its own centre, which the offset
              moved }
            if (ty = 'circle') and not (Near((b.Left + b.Right) / 2, cx)
              and Near((b.Top + b.Bottom) / 2, cy)) then
              Miss(Format('%s: a turned circle centred at (%s, %s) upstream, (%s, %s) here',
                [w_, Fmt(cx), Fmt(cy), Fmt((b.Left + b.Right) / 2), Fmt((b.Top + b.Bottom) / 2)]));
            if (ty = 'circle') and (w = h)
              and not (Near(b.Right - b.Left, w) and Near(b.Bottom - b.Top, h)) then
              Miss(Format('%s: a turned circle %s wide upstream, %s here', [w_, Fmt(w),
                Fmt(b.Right - b.Left)]));
            if (ty = 'rect') and Near(Abs(Num(pa.Find('rotation'))), Pi / 2)
              and not (Near(b.Right - b.Left, h) and Near(b.Bottom - b.Top, w)) then
              Miss(Format('%s: a quarter-turned rect %s x %s upstream, %s x %s here', [w_,
                Fmt(h), Fmt(w), Fmt(b.Right - b.Left), Fmt(b.Bottom - b.Top)]));
          end;
          { the paint order }
          Inc(FCompared, 2);
          if e.Z <> sy.Integers['z'] then
            Miss(Format('%s: z %d upstream, %d here', [w_, sy.Integers['z'], e.Z]));
          if e.Z2 <> sy.Integers['z2'] then
            Miss(Format('%s: z2 %d upstream, %d here', [w_, sy.Integers['z2'], e.Z2]));
          { the ink }
          st := sy.Objects['style'];
          Inc(FCompared);
          if sy.Get('emptyBrush', False) or (sy.Get('type', '') = 'emptyCircle') then
          begin
            if TyTryParseChartColor(st.Get('stroke', ''), want) and (e.Style.StrokeColor <> want) then
              Miss(w_ + ': an empty symbol''s pen differs');
          end
          else if not IsNull(st.Find('fill')) and TyTryParseChartColor(st.Get('fill', ''), want) then
          begin
            if (not e.Style.HasFill) or (e.Style.FillColor <> want) then
              Miss(Format('%s: fill %s upstream, %.8x here', [w_, st.Get('fill', ''),
                e.Style.FillColor]));
          end;
          if st.Find('opacity') <> nil then op := Num(st.Find('opacity')) else op := 1;
          Inc(FCompared);
          if Abs(e.Style.Alpha - op) > 1e-12 then
            Miss(Format('%s: opacity %s upstream, %s here', [w_, Fmt(op), Fmt(e.Style.Alpha)]));
          { the ripples }
          ripN := 0;
          eff := nil;
          if not IsNull(row.Find('effect')) then
          begin
            eff := row.Objects['effect'];
            if not IsNull(eff.Find('ripples')) then ripN := eff.Arrays['ripples'].Count;
          end;
          Inc(FCompared);
          if ripCount[di] <> ripN then
            Miss(Format('%s: %d ripples upstream, %d here', [w_, ripN, ripCount[di]]));
          Inc(FRipples, ripN);
          if (ripN > 0) and (ripCount[di] = ripN) then
            for k := 0 to n - 1 do
            begin
              e := lst.Element(k);
              if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex <> di) or (e.Z2 <> 99) then
                Continue;
              st := eff.Arrays['ripples'].Objects[0].Objects['style'];
              Inc(FCompared);
              if not e.Silent then Miss(w_ + ': a ripple takes the pointer');
              if not IsNull(st.Find('fill')) then
              begin
                if TyTryParseChartColor(st.Get('fill', ''), want)
                  and not (e.Style.HasFill and (e.Style.FillColor = want)) then
                  Miss(w_ + ': a ripple''s fill differs');
              end
              else if TyTryParseChartColor(st.Get('stroke', ''), want)
                and (e.Style.HasFill or (e.Style.StrokeColor <> want)) then
                Miss(w_ + ': a ripple''s ring differs');
              Break;
            end;
          { the label }
          d := sy.Find('label');
          Inc(FCompared);
          if IsNull(d) or IsNull(TJSONObject(d).Find('text'))
            or (TJSONObject(d).Get('text', '') = '') or TJSONObject(d).Get('ignore', False) then
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
        end;
      end;
    finally
      opt.Free;
    end;
  end;
end;

procedure TAdvChartSeriesCalendarOracleTest.TestScatterSymbolsAsUpstreamDrawsThem;
begin
  RunSymbols(False);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the symbols were compared (%d, %d ripples, %d zoned)',
    [FSymbols, FRipples, FZoned]), (FSymbols >= 30) and (FRipples >= 10));
end;

procedure TAdvChartSeriesCalendarOracleTest.TestTheGallerySymbolsAsUpstream;
begin
  RunSymbols(True);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the gallery symbols were compared (%d)', [FSymbols]), FSymbols >= 50);
end;

initialization
  RegisterTest(TAdvChartSeriesCalendarOracleTest);
end.
