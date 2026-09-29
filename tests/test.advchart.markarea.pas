unit test.advchart.markarea;
{$mode objfpc}{$H+}
{ The PICTURE of a markArea -- the polygon on its four corners (fill after
  the series colour's alpha 0.4, stroke, width, dash, opacity), its rect
  grown by the stroke, the label placed against that rect with its inside
  or outside ink -- held to what ECharts 6.1 draws; an area clipped by the
  axes draws nothing.

  tools/advchart-oracle/markers-area.js records every markArea of every
  series; the port's MarkAreaPictures read-out is compared field by field.

  EXACT: bit for bit, -0 and 0 one; colours compared as the colours they
  name. A gallery series whose areas land elsewhere here is counted and
  passed over. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.ZrPath, tyControls.AdvChart.Color,
     tyControls.AdvChart.Marker, tyControls.AdvChart.MarkerView,
     tyControls.AdvanceChart;
type
  TMAreaProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartMarkAreaOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TMAreaProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FSkipped, FLines: Integer;
    FReport, FName, FSkipNames: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; A: Double; AFx: TJSONData);
    procedure NumOrNull(const AWhat: string; A: Double; AFx: TJSONData);
    procedure Str(const AWhat, A: string; AFx: TJSONData);
    procedure Col(const AWhat, A: string; AFx: TJSONData);
    procedure Json(const AWhat: string; A, AFx: TJSONData);
    procedure Path(const AWhat: string; const P: TTyZrPath; AFx: TJSONData);
    procedure Mat(const AWhat: string; AHas: Boolean; const M: TTyMat2D; AFx: TJSONData);
    procedure Rect(const AWhat: string; const R: TTyXYWH; AFx: TJSONData);
    procedure CheckArea(const AWhat: string; const P: TTyMkAreaPic; AFx: TJSONObject);
    procedure CheckLabel(const AWhat: string; const B: TTyMkPtLabelPic; AFx: TJSONData);
    procedure RunCases(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMarkAreasAsUpstreamDrawsThem;
    procedure TestGalleryMarkAreasAsUpstream;
    procedure TestTheAreaSitsUnderTheSeries;
  end;

implementation

procedure TMAreaProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TMAreaProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-markers-area.json';
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
  if IsInfinite(A) then
    if A > 0 then Exit('Infinity') else Exit('-Infinity');
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameNum(A: Double; const AHex: string): Boolean;
var b: Double;
begin
  b := FromHex(AHex);
  if IsNan(A) or IsNan(b) then Exit(IsNan(A) and IsNan(b));
  if (A = 0) and (b = 0) then Exit(True);
  Result := Bits(A) = Bits(b);
end;

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

function SameJson(A, B: TJSONData): Boolean;
var i: Integer;
begin
  if IsNull(A) or IsNull(B) then Exit(IsNull(A) and IsNull(B));
  if A.JSONType <> B.JSONType then Exit(False);
  case A.JSONType of
    jtNumber: Result := A.AsFloat = B.AsFloat;
    jtString: Result := A.AsString = B.AsString;
    jtBoolean: Result := A.AsBoolean = B.AsBoolean;
    jtArray:
      begin
        if A.Count <> B.Count then Exit(False);
        for i := 0 to A.Count - 1 do
          if not SameJson(A.Items[i], B.Items[i]) then Exit(False);
        Result := True;
      end;
  else
    Result := A.AsJSON = B.AsJSON;
  end;
end;

procedure TAdvChartMarkAreaOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TMAreaProbe.Create(FForm);
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
  FLines := 0;
  FReport := '';
  FSkipNames := '';
end;

procedure TAdvChartMarkAreaOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartMarkAreaOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartMarkAreaOracleTest.Num(const AWhat: string; A: Double; AFx: TJSONData);
begin
  Inc(FCompared);
  if IsNull(AFx) then
  begin
    Miss(Format('%s: null upstream, %s here', [AWhat, Fmt(A)]));
    Exit;
  end;
  if not SameNum(A, AFx.AsString) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AFx.AsString)), Fmt(A)]));
end;

procedure TAdvChartMarkAreaOracleTest.NumOrNull(const AWhat: string; A: Double;
  AFx: TJSONData);
begin
  if IsNull(AFx) then
  begin
    Inc(FCompared);
    if not IsNan(A) then Miss(Format('%s: null upstream, %s here', [AWhat, Fmt(A)]));
    Exit;
  end;
  Num(AWhat, A, AFx);
end;

procedure TAdvChartMarkAreaOracleTest.Str(const AWhat, A: string; AFx: TJSONData);
var want: string;
begin
  Inc(FCompared);
  if IsNull(AFx) then want := '' else want := AFx.AsString;
  if A <> want then Miss(Format('%s: "%s" upstream, "%s" here', [AWhat, want, A]));
end;

{ a colour as the colour it names: the palette's string, a hex written two
  ways, and an rgba() all compare by their four numbers }
procedure TAdvChartMarkAreaOracleTest.Col(const AWhat, A: string; AFx: TJSONData);
var
  want: string;
  r1, g1, b1, a1, r2, g2, b2, a2: Double;
begin
  Inc(FCompared);
  if IsNull(AFx) then want := '' else want := AFx.AsString;
  if A = want then Exit;
  if (A <> '') and (want <> '') and TyTryParseCssRgba(A, r1, g1, b1, a1)
    and TyTryParseCssRgba(want, r2, g2, b2, a2) and (r1 = r2) and (g1 = g2)
    and (b1 = b2) and (a1 = a2) then Exit;
  Miss(Format('%s: "%s" upstream, "%s" here', [AWhat, want, A]));
end;

procedure TAdvChartMarkAreaOracleTest.Json(const AWhat: string; A, AFx: TJSONData);
var got: string;
begin
  Inc(FCompared);
  if not SameJson(A, AFx) then
  begin
    if A = nil then got := 'null' else got := A.AsJSON;
    if AFx = nil then Miss(AWhat + ': null upstream, ' + got + ' here')
    else Miss(AWhat + ': ' + AFx.AsJSON + ' upstream, ' + got + ' here');
  end;
end;

procedure TAdvChartMarkAreaOracleTest.Path(const AWhat: string; const P: TTyZrPath;
  AFx: TJSONData);
var
  a: TJSONArray;
  k, j: Integer;
  o: TJSONObject;
begin
  Inc(FCompared);
  a := TJSONArray(AFx);
  if a.Count <> Length(P) then
  begin
    Miss(Format('%s: %d commands upstream, %d here', [AWhat, a.Count, Length(P)]));
    Exit;
  end;
  for k := 0 to a.Count - 1 do
  begin
    o := a.Objects[k];
    Inc(FCompared);
    if o.Strings['cmd'] <> TyZrCmdName[P[k].Cmd] then
    begin
      Miss(Format('%s: command %d is %s upstream, %s here', [AWhat, k, o.Strings['cmd'],
        TyZrCmdName[P[k].Cmd]]));
      Exit;
    end;
    for j := 0 to o.Arrays['args'].Count - 1 do
      if not SameNum(P[k].V[j], o.Arrays['args'].Strings[j]) then
      begin
        Miss(Format('%s: command %d (%s) number %d is %s upstream, %s here', [AWhat, k,
          o.Strings['cmd'], j, Fmt(FromHex(o.Arrays['args'].Strings[j])), Fmt(P[k].V[j])]));
        Exit;
      end;
  end;
end;

procedure TAdvChartMarkAreaOracleTest.Mat(const AWhat: string; AHas: Boolean;
  const M: TTyMat2D; AFx: TJSONData);
var k: Integer;
begin
  Inc(FCompared);
  if IsNull(AFx) then
  begin
    if AHas then Miss(AWhat + ': no transform upstream, one here');
    Exit;
  end;
  if not AHas then
  begin
    Miss(AWhat + ': a transform upstream, none here');
    Exit;
  end;
  for k := 0 to 5 do
    if not SameNum(M[k], TJSONArray(AFx).Strings[k]) then
    begin
      Miss(Format('%s[%d]: %s upstream, %s here', [AWhat, k,
        Fmt(FromHex(TJSONArray(AFx).Strings[k])), Fmt(M[k])]));
      Exit;
    end;
end;

procedure TAdvChartMarkAreaOracleTest.Rect(const AWhat: string; const R: TTyXYWH;
  AFx: TJSONData);
var o: TJSONObject;
begin
  o := TJSONObject(AFx);
  Num(AWhat + '.x', R.X, o.Find('x'));
  Num(AWhat + '.y', R.Y, o.Find('y'));
  Num(AWhat + '.width', R.W, o.Find('width'));
  Num(AWhat + '.height', R.H, o.Find('height'));
end;

procedure TAdvChartMarkAreaOracleTest.CheckLabel(const AWhat: string;
  const B: TTyMkPtLabelPic; AFx: TJSONData);
var o, st, ink, inner, df: TJSONObject;
begin
  Inc(FCompared);
  if IsNull(AFx) then
  begin
    if B.Present then Miss(AWhat + ': none upstream, one here');
    Exit;
  end;
  if not B.Present then
  begin
    Miss(AWhat + ': one upstream, none here');
    Exit;
  end;
  o := TJSONObject(AFx);
  Inc(FCompared);
  if IsNull(o.Find('text')) then
  begin
    if B.HasText then Miss(AWhat + ': no text upstream, "' + B.Text + '" here');
  end
  else Str(AWhat + ' text', B.Text, o.Find('text'));
  Json(AWhat + ' position', B.Position, o.Find('position'));
  Num(AWhat + ' distance', B.Distance, o.Find('distance'));
  Rect(AWhat + ' rect', B.Rect, o.Find('rect'));
  inner := o.Objects['inner'];
  Num(AWhat + ' inner.x', B.InnerX, inner.Find('x'));
  Num(AWhat + ' inner.y', B.InnerY, inner.Find('y'));
  Num(AWhat + ' inner.rotation', B.InnerRotation, inner.Find('rotation'));
  Num(AWhat + ' inner.originX', B.InnerOriginX, inner.Find('originX'));
  Num(AWhat + ' inner.originY', B.InnerOriginY, inner.Find('originY'));
  Mat(AWhat + ' transform', B.HasTransform, B.Transform, o.Find('transform'));
  Str(AWhat + ' align', B.Align, o.Find('align'));
  Str(AWhat + ' verticalAlign', B.VAlign, o.Find('verticalAlign'));
  Str(AWhat + ' authorAlign', B.AuthorAlign, o.Find('authorAlign'));
  Str(AWhat + ' authorVerticalAlign', B.AuthorVAlign, o.Find('authorVerticalAlign'));
  Inc(FCompared);
  if B.Inside <> o.Booleans['inside'] then Miss(AWhat + ': inside differs');
  Str(AWhat + ' font', B.Font, o.Find('font'));
  Json(AWhat + ' fontSize', B.FontSize, o.Find('fontSize'));
  Json(AWhat + ' fontWeight', B.FontWeight, o.Find('fontWeight'));
  Json(AWhat + ' fontStyle', B.FontStyle, o.Find('fontStyle'));
  Json(AWhat + ' fontFamily', B.FontFamily, o.Find('fontFamily'));
  st := o.Objects['style'];
  Col(AWhat + ' style.fill', B.StyleFill, st.Find('fill'));
  Col(AWhat + ' style.stroke', B.StyleStroke, st.Find('stroke'));
  NumOrNull(AWhat + ' style.lineWidth', B.StyleLineWidth, st.Find('lineWidth'));
  if IsNan(B.StyleOpacity) then Num(AWhat + ' style.opacity', 1, st.Find('opacity'))
  else Num(AWhat + ' style.opacity', B.StyleOpacity, st.Find('opacity'));
  Json(AWhat + ' style.backgroundColor', B.StyleBackground, st.Find('backgroundColor'));
  df := o.Objects['inkDefault'];
  Col(AWhat + ' default fill', B.DefFill, df.Find('fill'));
  Col(AWhat + ' default stroke', B.DefStroke, df.Find('stroke'));
  Str(AWhat + ' default align', B.DefAlign, df.Find('align'));
  Str(AWhat + ' default verticalAlign', B.DefVAlign, df.Find('verticalAlign'));
  Inc(FCompared);
  if IsNull(o.Find('ink')) then
  begin
    if B.HasInk then Miss(AWhat + ': no ink upstream, some here');
  end
  else if not B.HasInk then
    Miss(AWhat + ': ink upstream, none here')
  else
  begin
    ink := o.Objects['ink'];
    Col(AWhat + ' ink.fill', B.InkFill, ink.Find('fill'));
    Col(AWhat + ' ink.stroke', B.InkStroke, ink.Find('stroke'));
    NumOrNull(AWhat + ' ink.lineWidth', B.InkLineWidth, ink.Find('lineWidth'));
    Num(AWhat + ' ink.opacity', B.InkOpacity, ink.Find('opacity'));
  end;
  Inc(FCompared, 2);
  if B.Z2 <> o.Floats['z2'] then Miss(Format('%s z2: %s upstream, %s here', [AWhat,
    o.Find('z2').AsJSON, Fmt(B.Z2)]));
  if B.Silent <> o.Booleans['silent'] then Miss(AWhat + ': silent differs');
end;

procedure TAdvChartMarkAreaOracleTest.CheckArea(const AWhat: string;
  const P: TTyMkAreaPic; AFx: TJSONObject);
var
  o, st, vis: TJSONObject;
  k: Integer;
  d: TJSONData;
begin
  vis := AFx.Objects['visual'];
  d := vis.Find('fill');
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    Inc(FCompared);
    if P.FillData = nil then Miss(AWhat + ': a gradient fill upstream, none here');
  end
  else if P.HasFill then Col(AWhat + ' visual fill', P.Fill, d)
  else
  begin
    Inc(FCompared);
    if not IsNull(d) then Miss(AWhat + ': a fill upstream, none here');
  end;
  d := vis.Find('stroke');
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    Inc(FCompared);
    if P.StrokeData = nil then Miss(AWhat + ': a gradient stroke upstream, none here');
  end
  else Col(AWhat + ' visual stroke', P.Stroke, d);
  Inc(FCompared);
  if P.Z2 <> vis.Floats['z2'] then Miss(Format('%s z2: %s upstream, %s here', [AWhat,
    vis.Find('z2').AsJSON, Fmt(P.Z2)]));
  Inc(FCompared);
  if P.Drawn = AFx.Booleans['allClipped'] then
  begin
    Miss(AWhat + ': clipped differs');
    Exit;
  end;
  if not P.Drawn then Exit;
  o := AFx.Objects['polygon'];
  for k := 0 to 3 do
  begin
    Num(Format('%s point %d x', [AWhat, k]), P.Points[k].X,
      o.Objects['shape'].Arrays['points'].Arrays[k].Items[0]);
    Num(Format('%s point %d y', [AWhat, k]), P.Points[k].Y,
      o.Objects['shape'].Arrays['points'].Arrays[k].Items[1]);
  end;
  Path(AWhat + ' path', P.Path, o.Find('path'));
  Rect(AWhat + ' bbox', P.BBox, o.Find('bbox'));
  Rect(AWhat + ' rect', P.Rect, o.Find('rect'));
  st := o.Objects['style'];
  Num(AWhat + ' lineWidth', P.LineWidth, st.Find('lineWidth'));
  Num(AWhat + ' opacity', P.Opacity, st.Find('opacity'));
  Num(AWhat + ' lineDashOffset', P.DashOffset, st.Find('lineDashOffset'));
  Json(AWhat + ' lineDash', P.Dash, st.Find('lineDash'));
  Str(AWhat + ' lineCap', P.LineCap, st.Find('lineCap'));
  Str(AWhat + ' lineJoin', P.LineJoin, st.Find('lineJoin'));
  CheckLabel(AWhat + ' label', P.Lbl, AFx.Find('label'));
end;

procedure TAdvChartMarkAreaOracleTest.RunCases(AGallery: Boolean);
var
  cases, series, items: TJSONArray;
  cs, opt, se, it: TJSONObject;
  sl: TStringList;
  c, s, k, j, si: Integer;
  pics: TTyMkAreaPicArray;
  d: TJSONData;
  moved: Boolean;
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
      { UPSTREAM'S OWN PALETTE where the option names none: the port's default
        colours are the skin's, by design }
      if opt.Find('color') = nil then
        opt.Add('color', GetJSON('["#5070dd","#b6d634","#505372","#ff994d",'
          + '"#0ca8df","#ffd10a","#fb628b","#785db0","#3fbe95"]'));
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
      series := cs.Arrays['series'];
      for s := 0 to series.Count - 1 do
      begin
        se := series.Objects[s];
        si := se.Integers['seriesIndex'];
        FName := Format('%s series %d', [cs.Strings['id'], si]);
        pics := FChart.MarkAreaPictures(si);
        if IsNull(se.Find('markArea')) then
        begin
          Inc(FCompared);
          if Length(pics) > 0 then Miss('no markArea upstream, pictures here');
          Continue;
        end;
        items := se.Objects['markArea'].Arrays['items'];
        k := 0;
        for j := 0 to items.Count - 1 do
          if items.Objects[j].Booleans['survived'] then Inc(k);
        Inc(FCompared);
        if k <> Length(pics) then
        begin
          Miss(Format('%d areas upstream, %d here', [k, Length(pics)]));
          Continue;
        end;
        { A GRID THAT LANDED ELSEWHERE moves every area }
        moved := False;
        k := 0;
        for j := 0 to items.Count - 1 do
        begin
          it := items.Objects[j];
          if not it.Booleans['survived'] then Continue;
          if pics[k].Drawn and not SameNum(pics[k].Points[0].X,
            it.Arrays['points'].Arrays[0].Strings[0]) then moved := True;
          Inc(k);
        end;
        if moved and AGallery then
        begin
          Inc(FSkipped);
          FSkipNames := FSkipNames + ' ' + FName;
          Continue;
        end;
        k := 0;
        for j := 0 to items.Count - 1 do
        begin
          it := items.Objects[j];
          if not it.Booleans['survived'] then Continue;
          Inc(FLines);
          Inc(FCompared);
          if pics[k].Item <> j then Miss(Format('#%d: picture of item %d', [j, pics[k].Item]));
          CheckArea(Format('#%d', [j]), pics[k], it);
          Inc(k);
        end;
      end;
    finally
      opt.Free;
    end;
  end;
end;

procedure TAdvChartMarkAreaOracleTest.TestMarkAreasAsUpstreamDrawsThem;
begin
  RunCases(False);
  AssertTrue('the synthetic areas were compared', FLines >= 120);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
end;

procedure TAdvChartMarkAreaOracleTest.TestGalleryMarkAreasAsUpstream;
begin
  RunCases(True);
  AssertTrue('the gallery areas were compared', FLines >= 3);
  AssertTrue(Format('%d gallery series passed over:%s', [FSkipped, FSkipNames]),
    FSkipped <= 2);
  AssertTrue(Format('%d of %d comparisons differ from upstream (%d series passed over):%s',
    [FBad, FCompared, FSkipped, FReport]), FBad = 0);
end;

procedure TAdvChartMarkAreaOracleTest.TestTheAreaSitsUnderTheSeries;
var
  lst: TTyPaintList;
  k, areas, caps, lineZ: Integer;
  e: TTyChartElement;
begin
  { a named range: a translucent band at z 1 -- UNDER the line at 2 -- and
    its name above it }
  FChart.Option := '{"xAxis":{"type":"category","data":["a","b","c","d"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"line","data":[1,3,2,4],'
    + '"markArea":{"data":[[{"name":"band","xAxis":"b"},{"xAxis":"c"}]]}}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  areas := 0;
  caps := 0;
  lineZ := -1;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Shape.Kind = cskPolyline) and (e.Datum.SeriesIndex = 0) then lineZ := e.Z;
    if e.Z <> 1 then Continue;
    AssertTrue('a marker is silent', e.Silent);
    if e.Caption.Text = 'band' then Inc(caps)
    else if (e.Shape.Kind = cskPolygon) and e.Style.HasFill then
    begin
      Inc(areas);
      AssertTrue('translucent', (e.Style.FillColor shr 24) < 200);
    end;
  end;
  AssertEquals('the band', 1, areas);
  AssertEquals('its name', 1, caps);
  { a line's own z is 3 (LineSeries.ts:161) [Batch 68] }
  AssertEquals('the line over it', 3, lineZ);
end;

initialization
  RegisterTest(TAdvChartMarkAreaOracleTest);
end.
