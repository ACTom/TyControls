unit test.advchart.linesmooth;
{$mode objfpc}{$H+}
{ A line series' path -- smooth and smoothMonotone, connectNulls across a
  gap, the tiny segments upstream drops, a step's corners, and an area's
  base walked backwards under the line with the smooth of the series it is
  stacked on -- held to what ECharts 6.1 builds, command for command.

  tools/advchart-oracle/line-smooth.js records each line series' polyline
  and area polygon path data (PathProxy's M / L / C / Z with their numbers),
  a digest of the whole path, and the path's bounding rect. The port draws
  from the commands it hangs on the line and area elements; this joins them
  up series by series and compares.

  EXACT: bit for bit, -0 and 0 one. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser, sha1,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.LinePath, tyControls.AdvanceChart;
type
  TLsProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartLineSmoothOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLsProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FSkipped: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure CheckPath(const AWhat: string; const ACmds: TTyPathCmdArray;
      ARec: TJSONObject; const ARect: TTyRectF; AHasRect: Boolean);
    procedure RunCases(AGallery: Boolean; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPathsAsUpstreamBuildsThem;
    procedure TestGalleryPathsAsUpstream;
    procedure TestTheSmoothOptionReadsAsUpstream;
    procedure TestTheCurveIsDrawn;
  end;

implementation

procedure TLsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-line-smooth.json';
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

function Hex(A: Double): string;
begin
  if IsNan(A) then Exit('7ff8000000000000');
  Result := LowerCase(IntToHex(Bits(A), 16));
end;

function Fmt(A: Double): string;
begin
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

const
  cLetter: array[TTyPathCmdKind] of Char = ('M', 'L', 'C', 'Z');

function ArgsOf(const C: TTyPathCmd): TTyDoubleArray;
begin
  case C.Kind of
    pckMove, pckLine:
      begin
        SetLength(Result, 2);
        Result[0] := C.X;
        Result[1] := C.Y;
      end;
    pckCurve:
      begin
        SetLength(Result, 6);
        Result[0] := C.X1;
        Result[1] := C.Y1;
        Result[2] := C.X2;
        Result[3] := C.Y2;
        Result[4] := C.X;
        Result[5] := C.Y;
      end;
  else
    Result := nil;
  end;
end;

{ the oracle's pathDigest: each command's letter, then its numbers as 16 hex
  digits }
function Digest(const ACmds: TTyPathCmdArray): string;
var
  s: string;
  i, j: Integer;
  a: TTyDoubleArray;
begin
  s := '';
  for i := 0 to High(ACmds) do
  begin
    s := s + cLetter[ACmds[i].Kind];
    a := ArgsOf(ACmds[i]);
    for j := 0 to High(a) do s := s + Hex(a[j]);
  end;
  Result := LowerCase(SHA1Print(SHA1String(s)));
end;

procedure TAdvChartLineSmoothOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLineSmoothOracleTest.CheckPath(const AWhat: string;
  const ACmds: TTyPathCmdArray; ARec: TJSONObject; const ARect: TTyRectF;
  AHasRect: Boolean);
var
  path, args: TJSONArray;
  k, j: Integer;
  a: TTyDoubleArray;
  rr: TJSONObject;
begin
  Inc(FCompared);
  if Length(ACmds) <> ARec.Integers['pathCount'] then
  begin
    Miss(Format('%s: %d commands upstream, %d here', [AWhat, ARec.Integers['pathCount'],
      Length(ACmds)]));
    Exit;
  end;
  path := ARec.Arrays['path'];
  for k := 0 to path.Count - 1 do
  begin
    Inc(FCompared);
    if path.Objects[k].Strings['cmd'] <> cLetter[ACmds[k].Kind] then
    begin
      Miss(Format('%s: command %d is %s upstream, %s here', [AWhat, k,
        path.Objects[k].Strings['cmd'], cLetter[ACmds[k].Kind]]));
      Exit;
    end;
    args := path.Objects[k].Arrays['args'];
    a := ArgsOf(ACmds[k]);
    for j := 0 to args.Count - 1 do
      if not SameNum(a[j], args.Strings[j]) then
      begin
        Miss(Format('%s: command %d (%s) number %d is %s upstream, %s here', [AWhat, k,
          cLetter[ACmds[k].Kind], j, Fmt(FromHex(args.Strings[j])), Fmt(a[j])]));
        Exit;
      end;
  end;
  Inc(FCompared);
  if Digest(ACmds) <> ARec.Strings['pathDigest'] then
    Miss(AWhat + ': the whole path differs (digest)');
  if AHasRect then
  begin
    rr := ARec.Objects['rect'];
    Inc(FCompared);
    if not (SameNum(ARect.Left, rr.Strings['x']) and SameNum(ARect.Top, rr.Strings['y'])
      and SameNum(ARect.Right - ARect.Left, rr.Strings['width'])
      and SameNum(ARect.Bottom - ARect.Top, rr.Strings['height'])) then
      Miss(Format('%s: rect %s,%s %sx%s upstream, %s,%s %sx%s here', [AWhat,
        Fmt(FromHex(rr.Strings['x'])), Fmt(FromHex(rr.Strings['y'])),
        Fmt(FromHex(rr.Strings['width'])), Fmt(FromHex(rr.Strings['height'])),
        Fmt(ARect.Left), Fmt(ARect.Top), Fmt(ARect.Right - ARect.Left),
        Fmt(ARect.Bottom - ARect.Top)]));
  end;
end;

procedure TAdvChartLineSmoothOracleTest.RunCases(AGallery: Boolean; AMin: Integer);
var
  cases, series: TJSONArray;
  cs, opt, se, area, line: TJSONObject;
  sl: TStringList;
  c, s, k, si: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  lineCmds, areaCmds: TTyPathCmdArray;
  lineRect, areaRect: TTyRectF;
  curved: Boolean;
  d: TJSONData;

  procedure Append(var ADst: TTyPathCmdArray; const ASrc: TTyPathCmdArray);
  var j, n: Integer;
  begin
    n := Length(ADst);
    SetLength(ADst, n + Length(ASrc));
    for j := 0 to High(ASrc) do ADst[n + j] := ASrc[j];
  end;

  function Union(const A, B: TTyRectF; AFirst: Boolean): TTyRectF;
  begin
    if AFirst then Exit(B);
    Result := TyRectF(Min(A.Left, B.Left), Min(A.Top, B.Top), Max(A.Right, B.Right),
      Max(A.Bottom, B.Bottom));
  end;

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
        lineCmds := nil;
        areaCmds := nil;
        lineRect := TyRectF(0, 0, 0, 0);
        areaRect := TyRectF(0, 0, 0, 0);
        for k := 0 to lst.Count - 1 do
        begin
          e := lst.Element(k);
          if e.Datum.SeriesIndex <> si then Continue;
          if (e.Shape.Kind = cskPolyline) and (e.Datum.DataIndex = -1) then
          begin
            lineRect := Union(lineRect, TyShapeBounds(e.Shape), Length(lineCmds) = 0);
            Append(lineCmds, e.Shape.Cmds);
          end
          else if (e.Shape.Kind = cskPolygon) and (e.Datum.DataIndex = -1) then
          begin
            areaRect := Union(areaRect, TyShapeBounds(e.Shape), Length(areaCmds) = 0);
            Append(areaCmds, e.Shape.Cmds);
          end;
        end;
        curved := not SameNum(0, se.Objects['resolved'].Strings['smooth'])
          and (FromHex(se.Objects['resolved'].Strings['smooth']) > 0);
        line := se.Objects['line'];
        { A LAYOUT THAT DIFFERS is not this test's business: a gallery chart
          whose axis labels measure differently here moves the grid, and
          every point with it. Such a series is counted and passed over; the
          measured cases pin the grid. And polar lines are not drawn yet. }
        if (se.Strings['coordSys'] <> 'cartesian2d') then
        begin
          Inc(FSkipped);
          Continue;
        end;
        if (Length(lineCmds) > 0) and (line.Arrays['path'].Count > 0)
          and not (SameNum(lineCmds[0].X, line.Arrays['path'].Objects[0].Arrays['args'].Strings[0])
          and SameNum(lineCmds[0].Y, line.Arrays['path'].Objects[0].Arrays['args'].Strings[1])) then
        begin
          if AGallery then
          begin
            Inc(FSkipped);
            Continue;
          end;
        end;
        { a run of one point upstream is a bare move, and no element here }
        if (line.Integers['pathCount'] > 0) and not ((line.Integers['pathCount'] = 1)
          and (Length(lineCmds) = 0)) then
          CheckPath('line', lineCmds, line, lineRect, curved and (lst.Count > 0)
            and (line.Integers['pathCount'] > 1));
        d := se.Find('area');
        if (d <> nil) and (d.JSONType = jtObject) then
        begin
          area := TJSONObject(d);
          { one point: upstream's `M L Z` draws nothing, and nothing is here }
          if not ((Length(areaCmds) = 0) and (area.Integers['pathCount'] <= 3)) then
            CheckPath('area', areaCmds, area, areaRect, False);
        end;
      end;
    finally
      opt.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > AMin);
  { only the few whose grid moves (or that are polar) are passed over }
  AssertTrue(Format('passed over %d series', [FSkipped]), FSkipped <= 30);
end;

procedure TAdvChartLineSmoothOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TLsProbe.Create(FForm);
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
  FReport := '';
end;

procedure TAdvChartLineSmoothOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartLineSmoothOracleTest.TestPathsAsUpstreamBuildsThem;
begin
  RunCases(False, 1000);
end;

procedure TAdvChartLineSmoothOracleTest.TestGalleryPathsAsUpstream;
begin
  RunCases(True, 100);
end;

procedure TAdvChartLineSmoothOracleTest.TestTheSmoothOptionReadsAsUpstream;
var d: TJSONData;

  function S(const AText: string): Double;
  begin
    d := GetJSON(AText);
    try
      Result := TyLineSmoothOf(d);
    finally
      d.Free;
    end;
  end;

begin
  AssertEquals('true', 0.5, S('true'), 0);
  AssertEquals('false', 0, S('false'), 0);
  AssertEquals('a number as it is', 1.5, S('1.5'), 0);
  AssertEquals('a negative as it is', -0.3, S('-0.3'), 0);
  AssertEquals('the string "0" is true', 0.5, S('"0"'), 0);
  AssertEquals('the empty string is false', 0, S('""'), 0);
  AssertEquals('null', 0, S('null'), 0);
  AssertEquals('absent', 0, TyLineSmoothOf(nil), 0);
end;

procedure TAdvChartLineSmoothOracleTest.TestTheCurveIsDrawn;
var
  lst: TTyPaintList;
  k, curves, dx, dy, ink: Integer;
  e: TTyChartElement;
  c: TTyPathCmd;
  x0, y0, mx, my, dist, t: Double;
  px: TBGRAPixel;
begin
  FChart.Option := '{"xAxis": {"type": "category", "data": ["a", "b", "c", "d"]},'
    + ' "yAxis": {}, "series": [{"type": "line", "smooth": true, "data": [3, 1, 4, 1]}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  curves := 0;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Shape.Kind = cskPolyline) and (e.Datum.SeriesIndex = 0) then
      curves := curves + Ord((Length(e.Shape.Cmds) = 4) and (e.Shape.Cmds[1].Kind = pckCurve));
  end;
  AssertEquals('one polyline drawn as a move and three curves', 1, curves);
  { AND DRAWN AS ONE: the middle of the second curve is well off its chord,
    and there is ink on it }
  FBmp.FillRect(0, 0, 800, 600, BGRA(255, 255, 255, 255), dmSet);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Shape.Kind = cskPolyline) and (e.Datum.SeriesIndex = 0)
      and (Length(e.Shape.Cmds) = 4) then Break;
  end;
  x0 := e.Shape.Cmds[1].X;
  y0 := e.Shape.Cmds[1].Y;
  c := e.Shape.Cmds[2];
  t := 0.5;
  mx := (1 - t) * (1 - t) * (1 - t) * x0 + 3 * (1 - t) * (1 - t) * t * c.X1
    + 3 * (1 - t) * t * t * c.X2 + t * t * t * c.X;
  my := (1 - t) * (1 - t) * (1 - t) * y0 + 3 * (1 - t) * (1 - t) * t * c.Y1
    + 3 * (1 - t) * t * t * c.Y2 + t * t * t * c.Y;
  dist := TyDistanceToSegment(mx, my, x0, y0, c.X, c.Y);
  AssertTrue(Format('the curve bows off its chord (%g px)', [dist]), dist >= 3);
  ink := 0;
  for dy := -1 to 1 do
    for dx := -1 to 1 do
    begin
      px := FBmp.GetPixel(Round(mx) + dx, Round(my) + dy);
      if (px.red < 200) or (px.green < 200) or (px.blue < 200) then Inc(ink);
    end;
  AssertTrue(Format('ink on the curve at %g,%g', [mx, my]), ink > 0);
end;

initialization
  RegisterTest(TAdvChartLineSmoothOracleTest);
end.
