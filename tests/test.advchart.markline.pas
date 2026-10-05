unit test.advchart.markline;
{$mode objfpc}{$H+}
{ The PICTURE of a markLine -- the segment after zrender's sub-pixel step,
  its dash, the two end symbols (shape, box, turn, transform, path, colour)
  and the label (text, placement, pivot, transform, alignment, font, the
  style and the ink actually painted) -- held to what ECharts 6.1 draws.

  tools/advchart-oracle/markers-line.js records every drawn markLine of
  every series; the port's MarkLinePictures read-out is compared field by
  field, and the paint list is checked to carry the pieces.

  EXACT: bit for bit, -0 and 0 one; colours compared as the colours they
  name. A gallery series whose grid lands elsewhere here (its line's ends
  differ) is counted and passed over. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.ZrPath, tyControls.AdvChart.Color,
     tyControls.AdvChart.Marker, tyControls.AdvChart.MarkerView,
     tyControls.AdvanceChart;
type
  TMLineProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartMarkLineOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TMLineProbe;
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
    procedure CheckSymbol(const AWhat: string; const S: TTyMkSymbolPic; AFx: TJSONData);
    procedure CheckLabel(const AWhat: string; const B: TTyMkLabelPic; AFx: TJSONData);
    procedure RunCases(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMarkLinesAsUpstreamDrawsThem;
    procedure TestGalleryMarkLinesAsUpstream;
    procedure TestTheSegmentSymbolsAndLabelArePainted;
  end;

implementation

procedure TMLineProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TMLineProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-markers-line.json';
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

procedure TAdvChartMarkLineOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TMLineProbe.Create(FForm);
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

procedure TAdvChartMarkLineOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartMarkLineOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartMarkLineOracleTest.Num(const AWhat: string; A: Double; AFx: TJSONData);
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

procedure TAdvChartMarkLineOracleTest.NumOrNull(const AWhat: string; A: Double;
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

procedure TAdvChartMarkLineOracleTest.Str(const AWhat, A: string; AFx: TJSONData);
var want: string;
begin
  Inc(FCompared);
  if IsNull(AFx) then want := '' else want := AFx.AsString;
  if A <> want then Miss(Format('%s: "%s" upstream, "%s" here', [AWhat, want, A]));
end;

{ a colour as the colour it names: the palette's string, a hex written two
  ways, and an rgba() all compare by their four numbers }
procedure TAdvChartMarkLineOracleTest.Col(const AWhat, A: string; AFx: TJSONData);
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

procedure TAdvChartMarkLineOracleTest.Json(const AWhat: string; A, AFx: TJSONData);
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

procedure TAdvChartMarkLineOracleTest.Path(const AWhat: string; const P: TTyZrPath;
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

procedure TAdvChartMarkLineOracleTest.Mat(const AWhat: string; AHas: Boolean;
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

procedure TAdvChartMarkLineOracleTest.CheckSymbol(const AWhat: string;
  const S: TTyMkSymbolPic; AFx: TJSONData);
var o, st: TJSONObject;
begin
  Inc(FCompared);
  if IsNull(AFx) then
  begin
    if S.Present then Miss(AWhat + ': none upstream, one here');
    Exit;
  end;
  if not S.Present then
  begin
    Miss(AWhat + ': one upstream, none here');
    Exit;
  end;
  o := TJSONObject(AFx);
  Str(AWhat + ' symbol', S.Symbol, o.Find('symbol'));
  Str(AWhat + ' shapeType', S.ShapeType, o.Find('shapeType'));
  Inc(FCompared);
  if S.Empty <> o.Booleans['empty'] then Miss(AWhat + ': empty differs');
  Num(AWhat + ' box.x', S.Box.X, o.Objects['box'].Find('x'));
  Num(AWhat + ' box.y', S.Box.Y, o.Objects['box'].Find('y'));
  Num(AWhat + ' box.width', S.Box.W, o.Objects['box'].Find('width'));
  Num(AWhat + ' box.height', S.Box.H, o.Objects['box'].Find('height'));
  Num(AWhat + ' x', S.X, o.Find('x'));
  Num(AWhat + ' y', S.Y, o.Find('y'));
  Num(AWhat + ' rotation', S.Rotation, o.Find('rotation'));
  Mat(AWhat + ' transform', S.HasTransform, S.Transform, o.Find('transform'));
  Path(AWhat + ' path', S.Path, o.Find('path'));
  st := o.Objects['style'];
  Col(AWhat + ' fill', S.Fill, st.Find('fill'));
  Col(AWhat + ' stroke', S.Stroke, st.Find('stroke'));
  Num(AWhat + ' lineWidth', S.LineWidth, st.Find('lineWidth'));
  NumOrNull(AWhat + ' opacity', S.Opacity, st.Find('opacity'));
  Inc(FCompared);
  if S.Z2 <> o.Floats['z2'] then Miss(Format('%s z2: %s upstream, %s here', [AWhat,
    o.Find('z2').AsJSON, Fmt(S.Z2)]));
end;

procedure TAdvChartMarkLineOracleTest.CheckLabel(const AWhat: string;
  const B: TTyMkLabelPic; AFx: TJSONData);
var o, st, ink, inner: TJSONObject;
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
  Str(AWhat + ' text', B.Text, o.Find('text'));
  Num(AWhat + ' x', B.X, o.Find('x'));
  Num(AWhat + ' y', B.Y, o.Find('y'));
  Num(AWhat + ' rotation', B.Rotation, o.Find('rotation'));
  Num(AWhat + ' originX', B.OriginX, o.Find('originX'));
  Num(AWhat + ' originY', B.OriginY, o.Find('originY'));
  inner := o.Objects['inner'];
  Num(AWhat + ' inner.x', B.InnerX, inner.Find('x'));
  Num(AWhat + ' inner.y', B.InnerY, inner.Find('y'));
  Num(AWhat + ' inner.rotation', B.InnerRotation, inner.Find('rotation'));
  Num(AWhat + ' inner.originX', B.InnerOriginX, inner.Find('originX'));
  Num(AWhat + ' inner.originY', B.InnerOriginY, inner.Find('originY'));
  Mat(AWhat + ' transform', B.HasTransform, B.Transform, o.Find('transform'));
  Str(AWhat + ' align', B.Align, o.Find('align'));
  Str(AWhat + ' verticalAlign', B.VAlign, o.Find('verticalAlign'));
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
  Col(AWhat + ' default fill', B.DefFill, o.Objects['inkDefault'].Find('fill'));
  Col(AWhat + ' default stroke', B.DefStroke, o.Objects['inkDefault'].Find('stroke'));
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

procedure TAdvChartMarkLineOracleTest.RunCases(AGallery: Boolean);
var
  cases, series, items, dashA: TJSONArray;
  cs, opt, se, ml, it, ln, st: TJSONObject;
  sl: TStringList;
  c, s, k, j, q, si: Integer;
  pics: TTyMkLinePicArray;
  pic: TTyMkLinePic;
  d: TJSONData;
  w: string;
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
        colours are the skin's, by design, and every colour a marker falls
        back to is the series' }
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
        pics := FChart.MarkLinePictures(si);
        if IsNull(se.Find('markLine')) then
        begin
          Inc(FCompared);
          if Length(pics) > 0 then Miss('no markLine upstream, pictures here');
          Continue;
        end;
        ml := se.Objects['markLine'];
        items := ml.Arrays['items'];
        { the survivors, in data order }
        k := 0;
        for j := 0 to items.Count - 1 do
          if items.Objects[j].Booleans['survived'] then Inc(k);
        Inc(FCompared);
        if k <> Length(pics) then
        begin
          Miss(Format('%d lines upstream, %d here', [k, Length(pics)]));
          Continue;
        end;
        { A GRID THAT LANDED ELSEWHERE moves every line: a gallery series whose
          first drawn line has other ends is passed over }
        moved := False;
        k := 0;
        for j := 0 to items.Count - 1 do
        begin
          it := items.Objects[j];
          if not it.Booleans['survived'] then Continue;
          pic := pics[k];
          Inc(k);
          if (not it.Booleans['drawn']) or IsNull(it.Find('line')) or (not pic.Drawn) then Continue;
          ln := it.Objects['line'];
          moved := not (SameNum(pic.X1, ln.Objects['shape'].Strings['x1'])
            and SameNum(pic.Y1, ln.Objects['shape'].Strings['y1'])
            and SameNum(pic.X2, ln.Objects['shape'].Strings['x2'])
            and SameNum(pic.Y2, ln.Objects['shape'].Strings['y2']));
          Break;
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
          pic := pics[k];
          Inc(k);
          Inc(FLines);
          w := Format('#%d', [j]);
          Inc(FCompared, 2);
          if pic.Item <> j then Miss(Format('%s: picture of item %d', [w, pic.Item]));
          if pic.Drawn <> it.Booleans['drawn'] then
          begin
            Miss(w + ': drawn differs');
            Continue;
          end;
          if not pic.Drawn then Continue;
          ln := it.Objects['line'];
          Num(w + ' x1', pic.X1, ln.Objects['shape'].Find('x1'));
          Num(w + ' y1', pic.Y1, ln.Objects['shape'].Find('y1'));
          Num(w + ' x2', pic.X2, ln.Objects['shape'].Find('x2'));
          Num(w + ' y2', pic.Y2, ln.Objects['shape'].Find('y2'));
          Path(w + ' path', pic.Path, ln.Find('path'));
          st := ln.Objects['style'];
          Col(w + ' stroke', pic.Stroke, st.Find('stroke'));
          Num(w + ' lineWidth', pic.LineWidth, st.Find('lineWidth'));
          Json(w + ' lineDashType', pic.DashType, st.Find('lineDashType'));
          Inc(FCompared);
          if IsNull(st.Find('lineDash')) then
          begin
            if Length(pic.Dash) > 0 then Miss(w + ': no dash upstream, one here');
          end
          else
          begin
            dashA := st.Arrays['lineDash'];
            if dashA.Count <> Length(pic.Dash) then
              Miss(Format('%s: dash of %d upstream, %d here', [w, dashA.Count, Length(pic.Dash)]))
            else
              for q := 0 to dashA.Count - 1 do
                Num(Format('%s dash[%d]', [w, q]), pic.Dash[q], dashA.Items[q]);
          end;
          Num(w + ' dashOffset', pic.DashOffset, st.Find('lineDashOffset'));
          Num(w + ' opacity', pic.Opacity, st.Find('opacity'));
          Str(w + ' lineCap', pic.LineCap, st.Find('lineCap'));
          Str(w + ' lineJoin', pic.LineJoin, st.Find('lineJoin'));
          Inc(FCompared);
          if pic.Z2 <> ln.Floats['z2'] then
            Miss(Format('%s z2: %s upstream, %s here', [w, ln.Find('z2').AsJSON, Fmt(pic.Z2)]));
          CheckSymbol(w + ' from', pic.FromSym, it.Find('fromSymbol'));
          CheckSymbol(w + ' to', pic.ToSym, it.Find('toSymbol'));
          CheckLabel(w + ' label', pic.Lbl, it.Find('label'));
        end;
      end;
    finally
      opt.Free;
    end;
  end;
end;

procedure TAdvChartMarkLineOracleTest.TestMarkLinesAsUpstreamDrawsThem;
begin
  RunCases(False);
  AssertTrue('the synthetic lines were compared', FLines >= 150);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
end;

procedure TAdvChartMarkLineOracleTest.TestGalleryMarkLinesAsUpstream;
begin
  RunCases(True);
  AssertTrue('the gallery lines were compared', FLines >= 30);
  AssertTrue(Format('%d gallery series passed over:%s', [FSkipped, FSkipNames]),
    FSkipped <= 3);
  AssertTrue(Format('%d of %d comparisons differ from upstream (%d series passed over):%s',
    [FBad, FCompared, FSkipped, FReport]), FBad = 0);
end;

procedure TAdvChartMarkLineOracleTest.TestTheSegmentSymbolsAndLabelArePainted;
var
  lst: TTyPaintList;
  k, lines, polys, caps: Integer;
  e: TTyChartElement;
begin
  { a yAxis line: the dashed segment, a circle and an arrow, and the value
    at its end -- all over the series (z 5 against 2), all silent }
  FChart.Option := '{"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"line","data":[1,3,2],'
    + '"markLine":{"data":[{"yAxis":2.5}]}}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  lines := 0;
  polys := 0;
  caps := 0;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if e.Z <> 5 then Continue;
    { A MARKER TAKES THE POINTER -- upstream's markers answer it, and emit
      the chart's events [Batch 84; they were silent] -- but is no series
      datum: nothing that asks for a series' rows can find it }
    AssertFalse('a marker takes the pointer', e.Silent);
    AssertTrue('a marker is no series datum',
      (e.Datum.SeriesIndex < 0) and (e.Datum.Kind <> ctkSeries));
    if (e.Shape.Kind = cskPolyline) and (Length(e.Style.DashLogical) = 2) then Inc(lines)
    else if (e.Caption.Text = '2.5') then Inc(caps)
    else if e.Style.HasFill and (Length(e.Shape.Cmds) > 0) then Inc(polys);
  end;
  AssertEquals('the dashed segment', 1, lines);
  AssertEquals('the two end symbols', 2, polys);
  AssertEquals('the label', 1, caps);
end;

initialization
  RegisterTest(TAdvChartMarkLineOracleTest);
end.
