unit test.advchart.sunburst;
{$mode objfpc}{$H+}
{ THE SUNBURST SERIES -- which nodes are drawn, each sector's centre, radii
  and sweep, its fill after the palette, the lift and the item/level/series
  colours, and each label's words, anchor, turn and alignment -- held to what
  ECharts 6.1 draws.

  tools/advchart-oracle/sunburst.js records every SeriesData row and every
  drawn piece. The port's paint list is read back: a piece is the sector
  stamped with its row, its label the caption the expansion placed.

  EXACT: radii, angles and anchors to the bit. A visualMap's fill is the
  next batch's and those rows' colours are passed over, counted.

  ONE CASE IS A DEVIATION, NAMED: V-string. Upstream sums string values with
  JS `+` and concatenates them ('5' + '3' is '053'); the port adds numbers.
  TestStringValuesAddAsNumbers holds the port's side. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvanceChart;
type
  TSbProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartSunburstOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TSbProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FPieces, FLabels, FSkipped: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure RunCases(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSunburstAsUpstreamDrawsIt;
    procedure TestTheGallerySunburstsAsUpstream;
    procedure TestStringValuesAddAsNumbers;
    procedure TestAnArrayValueCountsItsFirstEntry;
  end;

implementation

procedure TSbProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TSbProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-sunburst.json';
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

procedure TAdvChartSunburstOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TSbProbe.Create(FForm);
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
  FPieces := 0;
  FLabels := 0;
  FSkipped := 0;
  FReport := '';
end;

procedure TAdvChartSunburstOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartSunburstOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartSunburstOracleTest.RunCases(AGallery: Boolean);
var
  cases, series, pieces, rows: TJSONArray;
  cs, opt, se, pc, sh, st, lb, row: TJSONObject;
  sl: TStringList;
  c, s, k, j, si, ri, n: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  d: TJSONData;
  secAt, capAt: array of Integer;
  a0, a1: Double;
  want: TTyChartColor;
  w_: string;
  vm: Boolean;
  cr: array of Double;
  wantR: TTyCornerRadii;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    d := cs.Find('gallery');
    if AGallery <> ((d <> nil) and (d.JSONType = jtString)) then Continue;
    FName := cs.Strings['id'];
    if FName = 'V-string' then Continue;
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
      { UPSTREAM'S OWN PALETTE where the option names none }
      if opt.Find('color') = nil then
        opt.Add('color', GetJSON('["#5070dd","#b6d634","#505372","#ff994d",'
          + '"#0ca8df","#ffd10a","#fb628b","#785db0","#3fbe95"]'));
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
        si := se.Integers['seriesIndex'];
        FName := Format('%s series %d', [cs.Strings['id'], si]);
        rows := se.Arrays['rows'];
        n := rows.Count;
        SetLength(secAt, 0);
        SetLength(capAt, 0);
        SetLength(secAt, n);
        SetLength(capAt, n);
        for k := 0 to n - 1 do
        begin
          secAt[k] := -1;
          capAt[k] := -1;
        end;
        for k := 0 to lst.Count - 1 do
        begin
          e := lst.Element(k);
          if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex < 0)
            or (e.Datum.DataIndex >= n) then Continue;
          if (e.Caption.FontSizeLogical > 0) and (e.Caption.Text <> '') then
            capAt[e.Datum.DataIndex] := k
          else if e.Shape.Kind = cskSector then
            secAt[e.Datum.DataIndex] := k;
        end;
        { nothing drawn that upstream does not draw }
        for ri := 0 to n - 1 do
        begin
          row := rows.Objects[ri];
          Inc(FCompared);
          if row.Get('drawn', False) <> (secAt[ri] >= 0) then
          begin
            if row.Get('drawn', False) then Miss(Format('row %d: a piece upstream, none here', [ri]))
            else Miss(Format('row %d: no piece upstream, one here', [ri]));
          end;
        end;
        pieces := se.Arrays['pieces'];
        for j := 0 to pieces.Count - 1 do
        begin
          pc := pieces.Objects[j];
          ri := pc.Integers['row'];
          w_ := Format('row %d (%s)', [ri, rows.Objects[ri].Get('name', '')]);
          if secAt[ri] < 0 then Continue;
          Inc(FPieces);
          e := lst.Element(secAt[ri]);
          sh := pc.Objects['shape'];
          a0 := Min(Num(sh.Find('startAngle')), Num(sh.Find('endAngle')));
          a1 := Max(Num(sh.Find('startAngle')), Num(sh.Find('endAngle')));
          Inc(FCompared, 6);
          if not (Same(e.Shape.CX, Num(sh.Find('cx'))) and Same(e.Shape.CY, Num(sh.Find('cy')))
            and Same(e.Shape.R0, Num(sh.Find('r0'))) and Same(e.Shape.R1, Num(sh.Find('r')))
            and Same(e.Shape.StartRad, a0) and Same(e.Shape.EndRad, a1)) then
            Miss(Format('%s: sector (%s, %s) r %s..%s at %s..%s upstream, (%s, %s) r %s..%s at %s..%s here',
              [w_, Fmt(Num(sh.Find('cx'))), Fmt(Num(sh.Find('cy'))), Fmt(Num(sh.Find('r0'))),
               Fmt(Num(sh.Find('r'))), Fmt(a0), Fmt(a1), Fmt(e.Shape.CX), Fmt(e.Shape.CY),
               Fmt(e.Shape.R0), Fmt(e.Shape.R1), Fmt(e.Shape.StartRad), Fmt(e.Shape.EndRad)]));
          { the corners, as zrender normalises them }
          d := sh.Find('cornerRadius');
          SetLength(cr, 0);
          if (d <> nil) and (d.JSONType = jtArray) then
          begin
            SetLength(cr, d.Count);
            for k := 0 to d.Count - 1 do cr[k] := Num(d.Items[k]);
          end
          else if (d <> nil) and (d.JSONType = jtNumber) then
          begin
            SetLength(cr, 4);
            for k := 0 to 3 do cr[k] := d.AsFloat;
          end;
          wantR := TySectorRadii(cr);
          Inc(FCompared);
          for k := 0 to 3 do
            if not Same(e.Shape.SectorRadii[k], wantR[k]) then
            begin
              Miss(Format('%s: corner %d is %s upstream, %s here', [w_, k,
                Fmt(wantR[k]), Fmt(e.Shape.SectorRadii[k])]));
              Break;
            end;
          Inc(FCompared);
          if e.Z2 <> pc.Integers['z2'] then
            Miss(Format('%s: z2 %d upstream, %d here', [w_, pc.Integers['z2'], e.Z2]));
          { the ink }
          st := pc.Objects['ink'];
          d := rows.Objects[ri].Find('visualMapFill');
          vm := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;
          if vm then Inc(FSkipped)
          else if TyTryParseChartColor(st.Get('fill', ''), want) then
          begin
            Inc(FCompared);
            if e.Style.FillColor <> want then
              Miss(Format('%s: fill %s upstream, %.8x here', [w_, st.Get('fill', ''),
                e.Style.FillColor]));
          end;
          if (st.Get('stroke', '') <> 'white') and TyTryParseChartColor(st.Get('stroke', ''), want) then
          begin
            Inc(FCompared);
            if e.Style.StrokeColor <> want then Miss(w_ + ': the border differs');
          end;
          Inc(FCompared, 2);
          if e.Style.StrokeWidthLogical <> Num(st.Find('lineWidth')) then
            Miss(Format('%s: border %s wide upstream, %s here', [w_,
              Fmt(Num(st.Find('lineWidth'))), Fmt(e.Style.StrokeWidthLogical)]));
          if not IsNull(st.Find('opacity')) and (Abs(e.Style.Alpha - Num(st.Find('opacity'))) > 1e-12) then
            Miss(w_ + ': the opacity differs');
          { the label }
          d := pc.Find('label');
          Inc(FCompared);
          if IsNull(d) or IsNull(TJSONObject(d).Find('text'))
            or TJSONObject(d).Get('ignore', False) or IsNull(TJSONObject(d).Find('x')) then
          begin
            if (capAt[ri] >= 0) and not (not IsNull(d) and IsNull(TJSONObject(d).Find('x'))
              and not IsNull(TJSONObject(d).Find('text'))) then
              Miss(w_ + ': no label upstream, "' + lst.Element(capAt[ri]).Caption.Text + '" here');
            Continue;
          end;
          lb := TJSONObject(d);
          if capAt[ri] < 0 then
          begin
            Miss(w_ + ': label "' + lb.Get('text', '') + '" upstream, none here');
            Continue;
          end;
          Inc(FLabels);
          e := lst.Element(capAt[ri]);
          Inc(FCompared, 4);
          if e.Caption.Text <> lb.Get('text', '') then
            Miss(Format('%s: label "%s" upstream, "%s" here', [w_, lb.Get('text', ''),
              e.Caption.Text]));
          if not (Same(e.Caption.X, Num(lb.Find('x'))) and Same(e.Caption.Y, Num(lb.Find('y')))) then
            Miss(Format('%s: label at (%s, %s) upstream, (%s, %s) here', [w_,
              Fmt(Num(lb.Find('x'))), Fmt(Num(lb.Find('y'))), Fmt(e.Caption.X), Fmt(e.Caption.Y)]));
          if not Same(e.Caption.RotationRad, Num(lb.Find('rotation'))) then
            Miss(Format('%s: label turned %s upstream, %s here', [w_,
              Fmt(Num(lb.Find('rotation'))), Fmt(e.Caption.RotationRad)]));
          if not (((lb.Get('align', '') = 'center') = (e.Caption.AnchorH = tahCentre))
            and ((lb.Get('align', '') = 'right') = (e.Caption.AnchorH = tahRight))
            and ((lb.Get('verticalAlign', '') = 'middle') = (e.Caption.AnchorV = tavMiddle))
            and ((lb.Get('verticalAlign', '') = 'bottom') = (e.Caption.AnchorV = tavBottom))) then
            Miss(Format('%s: label aligned %s/%s upstream, otherwise here', [w_,
              lb.Get('align', ''), lb.Get('verticalAlign', '')]));
        end;
      end;
    finally
      opt.Free;
    end;
  end;
end;

procedure TAdvChartSunburstOracleTest.TestTheSunburstAsUpstreamDrawsIt;
begin
  RunCases(False);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d pieces, %d labels (%d fills passed over)',
    [FPieces, FLabels, FSkipped]), (FPieces >= 300) and (FLabels >= 200)
    and (FSkipped < FPieces div 10));
end;

procedure TAdvChartSunburstOracleTest.TestTheGallerySunburstsAsUpstream;
begin
  RunCases(True);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d pieces, %d labels (%d fills passed over)',
    [FPieces, FLabels, FSkipped]), FPieces >= 100);
end;

procedure TAdvChartSunburstOracleTest.TestStringValuesAddAsNumbers;
var lst: TTyPaintList; k: Integer; seen: Boolean;
begin
  FChart.Option := '{"animation":false,"series":[{"type":"sunburst","sort":null,'
    + '"label":{"formatter":"{b}: {c}"},"data":[{"name":"S","children":['
    + '{"name":"s1","value":"5"},{"name":"s2","value":"3"}]},{"name":"U","value":"8"}]}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  seen := False;
  for k := 0 to lst.Count - 1 do
    if lst.Element(k).Caption.Text = 'S: 8' then seen := True;
  AssertTrue('the parent of "5" and "3" is 8, not "053"', seen);
  { S and U are 8 each: S takes the upper half, from twelve o'clock }
  for k := 0 to lst.Count - 1 do
    if (lst.Element(k).Shape.Kind = cskSector) and (lst.Element(k).Datum.DataIndex = 1) then
      AssertEquals('S ends half way round', Pi / 2,
        lst.Element(k).Shape.EndRad, 1e-12);
end;

procedure TAdvChartSunburstOracleTest.TestAnArrayValueCountsItsFirstEntry;
var lst: TTyPaintList; k, n: Integer;
begin
  { completeTreeValue reads value[0]: A is 4 of 8, half way round, and its
    parent-less sum is not 103 }
  FChart.Option := '{"animation":false,"series":[{"type":"sunburst","sort":null,'
    + '"data":[{"name":"A","value":[4,99]},{"name":"B","value":4}]}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  n := 0;
  for k := 0 to lst.Count - 1 do
    if (lst.Element(k).Shape.Kind = cskSector) and (lst.Element(k).Datum.DataIndex = 1) then
    begin
      Inc(n);
      AssertEquals('A ends half way round', Pi / 2, lst.Element(k).Shape.EndRad, 1e-12);
    end;
  AssertEquals('A is drawn once', 1, n);
end;

initialization
  RegisterTest(TAdvChartSunburstOracleTest);
end.
