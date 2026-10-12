unit test.advchart.morph;
{$mode objfpc}{$H+}
{ ZRENDER'S PATH MORPHING, held to the real build. [Batch 136, D5 UT1]

  tools/advchart-oracle/universal-transition.js cuts zrender's morphing code
  out of the ECharts 6.1 dist and runs it on PathProxy data real elements
  built (a rect, a negative bar, rounded rects, sectors, a ring, an
  anticlockwise slice, a full circle, rounded sector corners, a circle, a
  polygon, a polyline, path:// shapes with one, two and three subpaths and a
  quadratic, a path that starts with an arc). Every case here feeds the
  recorded input to AdvChart.Morph and compares every number bit for bit:

    bezier     pathToBezierCurves on each path;
    polygons   pathToPolygons at the scales 1 and 3.5;
    align      fifteen pairs (different curve counts, different subpath
               counts, opposite windings, the same path twice):
               alignBezierCurves, each pair's centroids, its best ring
               offset, the reversed source and findBestMorphingRotation;
    transform  applyTransformOnBeziers;
    morph      prepareMorphPath on real elements with their transforms and
               the buildPath it substitutes, at nine t from 0 to 1;
    split      dividePath's split of rects, sectors, circles, a polygon and
               path:// shapes with several subpaths, into 1 to 12 pieces;
    grids      getDividingGrids, a zero and an empty side included;
    hilbert    sortPaths' key;
    batches    prepareMorphBatches, its wrap-round overwrite included. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape, tyControls.AdvChart.Morph;
type
  TAdvChartMorphTest = class(TTestCase)
  private
    FBad, FCompared: Integer;
    FReport: string;
    procedure Miss(const AWhere: string);
    procedure SameNums(const AWhere: string; const AGot: array of Double; AWant: TJSONData);
    procedure SameCurves(const AWhere: string; const AGot: TTyBezierCurves; AWant: TJSONData);
    procedure SameNum(const AWhere: string; AGot: Double; const AWant: string);
    procedure Finish(const AWhat: string);
  published
    procedure TestBezierCurvesAsUpstream;
    procedure TestPolygonsAsUpstream;
    procedure TestAlignmentAndRotationAsUpstream;
    procedure TestTransformAsUpstream;
    procedure TestMorphFramesAsUpstream;
    procedure TestSplitAsUpstream;
    procedure TestGridsHilbertBatchesAsUpstream;
  end;

implementation

var
  GFix: TJSONData = nil;

function Fix: TJSONObject;
var sl: TStringList;
begin
  if GFix = nil then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
        + 'advchart-universal-transition.json');
      GFix := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GFix);
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Hex(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function NumsOf(AData: TJSONData): TTyDoubleArray;
var i: Integer;
begin
  Result := nil;
  if (AData = nil) or (AData.JSONType <> jtArray) then Exit;
  SetLength(Result, AData.Count);
  for i := 0 to AData.Count - 1 do Result[i] := FromHex(AData.Items[i].AsString);
end;

function CurvesOf(AData: TJSONData): TTyBezierCurves;
var i: Integer;
begin
  Result := nil;
  if (AData = nil) or (AData.JSONType <> jtArray) then Exit;
  SetLength(Result, AData.Count);
  for i := 0 to AData.Count - 1 do Result[i] := NumsOf(AData.Items[i]);
end;

function MatOf(AData: TJSONData; out M: TTyMat2D): Boolean;
var a: TTyDoubleArray; i: Integer;
begin
  Result := (AData <> nil) and (AData.JSONType = jtArray);
  for i := 0 to 5 do M[i] := 0;
  if not Result then Exit;
  a := NumsOf(AData);
  for i := 0 to 5 do M[i] := a[i];
end;

function Cases(const AKind: string): TJSONArray;
var
  all: TJSONArray;
  i: Integer;
begin
  Result := TJSONArray.Create;
  all := Fix.Arrays['engine'];
  for i := 0 to all.Count - 1 do
    if all.Objects[i].Strings['kind'] = AKind then Result.Add(all.Objects[i].Clone);
end;

procedure TAdvChartMorphTest.Miss(const AWhere: string);
begin
  Inc(FBad);
  if FBad <= 25 then FReport := FReport + LineEnding + '  ' + AWhere;
end;

procedure TAdvChartMorphTest.SameNums(const AWhere: string; const AGot: array of Double;
  AWant: TJSONData);
var
  i: Integer;
  w: string;
begin
  if (AWant = nil) or (AWant.JSONType <> jtArray) then
  begin
    Miss(AWhere + ': no expectation');
    Exit;
  end;
  Inc(FCompared);
  if Length(AGot) <> AWant.Count then
  begin
    Miss(Format('%s: %d numbers, upstream %d', [AWhere, Length(AGot), AWant.Count]));
    Exit;
  end;
  for i := 0 to High(AGot) do
  begin
    w := AWant.Items[i].AsString;
    if Hex(AGot[i]) <> LowerCase(w) then
    begin
      Miss(Format('%s[%d]: %s (%s), upstream %s (%s)', [AWhere, i, Hex(AGot[i]),
        FloatToStr(AGot[i]), w, FloatToStr(FromHex(w))]));
      Exit;
    end;
  end;
end;

procedure TAdvChartMorphTest.SameNum(const AWhere: string; AGot: Double;
  const AWant: string);
begin
  Inc(FCompared);
  if Hex(AGot) <> LowerCase(AWant) then
    Miss(Format('%s: %s (%s), upstream %s (%s)', [AWhere, Hex(AGot), FloatToStr(AGot),
      AWant, FloatToStr(FromHex(AWant))]));
end;

{ a polygon's points, [[x, y], ...], flat }
function PointsFlat(AData: TJSONData): TTyDoubleArray;
var i: Integer;
begin
  Result := nil;
  if (AData = nil) or (AData.JSONType <> jtArray) then Exit;
  SetLength(Result, AData.Count * 2);
  for i := 0 to AData.Count - 1 do
  begin
    Result[i * 2] := FromHex(AData.Items[i].Items[0].AsString);
    Result[i * 2 + 1] := FromHex(AData.Items[i].Items[1].AsString);
  end;
end;

procedure TAdvChartMorphTest.SameCurves(const AWhere: string; const AGot: TTyBezierCurves;
  AWant: TJSONData);
var i: Integer;
begin
  Inc(FCompared);
  if (AWant = nil) or (AWant.JSONType <> jtArray) or (AWant.Count <> Length(AGot)) then
  begin
    if AWant = nil then Miss(AWhere + ': no expectation')
    else Miss(Format('%s: %d subpaths, upstream %d', [AWhere, Length(AGot), AWant.Count]));
    Exit;
  end;
  for i := 0 to High(AGot) do
    SameNums(Format('%s.%d', [AWhere, i]), AGot[i], AWant.Items[i]);
end;

procedure TAdvChartMorphTest.Finish(const AWhat: string);
begin
  if GetEnvironmentVariable('TY_MORPH_COUNTS') = '1' then
    WriteLn(Format('%s: %d compared', [AWhat, FCompared]));
  AssertTrue(Format('%s: %d of %d differ from upstream:%s', [AWhat, FBad, FCompared, FReport]),
    FBad = 0);
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
end;

procedure TAdvChartMorphTest.TestBezierCurvesAsUpstream;
var
  cs: TJSONArray;
  i: Integer;
  c: TJSONObject;
begin
  cs := Cases('bezier');
  try
    AssertTrue('bezier cases', cs.Count >= 17);
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      SameCurves(c.Strings['id'], TyPathToBezierCurves(NumsOf(c.Find('data'))), c.Find('out'));
    end;
  finally
    cs.Free;
  end;
  Finish('pathToBezierCurves');
end;

procedure TAdvChartMorphTest.TestPolygonsAsUpstream;
var
  cs: TJSONArray;
  i: Integer;
  c: TJSONObject;
begin
  cs := Cases('polygons');
  try
    AssertTrue('polygon cases', cs.Count >= 8);
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      SameCurves(c.Strings['id'], TyPathToPolygons(NumsOf(c.Find('data')),
        FromHex(c.Strings['scale'])), c.Find('out'));
    end;
  finally
    cs.Free;
  end;
  Finish('pathToPolygons');
end;

procedure TAdvChartMorphTest.TestAlignmentAndRotationAsUpstream;
var
  cs: TJSONArray;
  i, k: Integer;
  c: TJSONObject;
  fa, ta, na, nb: TTyBezierCurves;
  md: TTyMorphData;
  m: TJSONArray;
  id: string;
begin
  cs := Cases('align');
  try
    AssertTrue('align cases', cs.Count >= 15);
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      fa := TyPathToBezierCurves(NumsOf(c.Find('from')));
      ta := TyPathToBezierCurves(NumsOf(c.Find('to')));
      TyAlignBezierCurves(fa, ta, na, nb);
      SameCurves(id + '.alignedFrom', na, c.Find('alignedFrom'));
      SameCurves(id + '.alignedTo', nb, c.Find('alignedTo'));
      for k := 0 to Min(High(na), High(nb)) do
      begin
        SameNums(Format('%s.centroid%d.from', [id, k]), TyMorphCentroid(na[k]),
          c.Arrays['centroids'].Objects[k].Find('from'));
        SameNums(Format('%s.centroid%d.to', [id, k]), TyMorphCentroid(nb[k]),
          c.Arrays['centroids'].Objects[k].Find('to'));
        Inc(FCompared);
        if TyFindBestRingOffset(na[k], nb[k], TyMorphCentroid(na[k]), TyMorphCentroid(nb[k]))
          <> c.Arrays['offsets'].Integers[k] then
          Miss(Format('%s.offset%d: %d, upstream %d', [id, k, TyFindBestRingOffset(na[k],
            nb[k], TyMorphCentroid(na[k]), TyMorphCentroid(nb[k])), c.Arrays['offsets'].Integers[k]]));
        SameNums(Format('%s.reversed%d', [id, k]), TyMorphReverse(na[k]),
          c.Arrays['reversed'].Items[k]);
      end;
      md := TyFindBestMorphingRotation(na, nb, 10, Pi);
      m := c.Arrays['morph'];
      Inc(FCompared);
      if Length(md) <> m.Count then
      begin
        Miss(Format('%s.morph: %d subpaths, upstream %d', [id, Length(md), m.Count]));
        Continue;
      end;
      for k := 0 to High(md) do
      begin
        SameNums(Format('%s.morph%d.from', [id, k]), md[k].From, m.Objects[k].Find('from'));
        SameNums(Format('%s.morph%d.to', [id, k]), md[k].Dest, m.Objects[k].Find('to'));
        SameNums(Format('%s.morph%d.fromCp', [id, k]), md[k].FromCp, m.Objects[k].Find('fromCp'));
        SameNums(Format('%s.morph%d.toCp', [id, k]), md[k].DestCp, m.Objects[k].Find('toCp'));
        SameNum(Format('%s.morph%d.rotation', [id, k]), md[k].Rotation,
          m.Objects[k].Strings['rotation']);
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('alignBezierCurves / findBestMorphingRotation');
end;

procedure TAdvChartMorphTest.TestTransformAsUpstream;
var
  cs: TJSONArray;
  c: TJSONObject;
  cur: TTyBezierCurves;
  m: TTyMat2D;
begin
  cs := Cases('transform');
  try
    AssertEquals('transform cases', 1, cs.Count);
    c := cs.Objects[0];
    cur := CurvesOf(c.Find('curves'));
    MatOf(c.Find('m'), m);
    TyApplyTransformOnBeziers(cur, m);
    SameCurves('transform', cur, c.Find('out'));
  finally
    cs.Free;
  end;
  Finish('applyTransformOnBeziers');
end;

procedure TAdvChartMorphTest.TestMorphFramesAsUpstream;
var
  cs: TJSONArray;
  i, k: Integer;
  c: TJSONObject;
  fm, tm: TTyMat2D;
  hf, ht: Boolean;
  md: TTyMorphData;
  ts: TTyDoubleArray;
  cmds: TTyPathCmdArray;
begin
  cs := Cases('morph');
  try
    AssertTrue('morph cases', cs.Count >= 7);
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      hf := MatOf(c.Find('fromM'), fm);
      ht := MatOf(c.Find('toM'), tm);
      md := TyPrepareMorph(NumsOf(c.Find('fromData')), hf, fm, NumsOf(c.Find('toData')), ht, tm);
      ts := NumsOf(c.Find('ts'));
      for k := 0 to High(ts) do
        SameNums(Format('%s@%s', [c.Strings['id'], FloatToStr(ts[k])]), TyMorphPathData(md, ts[k]),
          c.Arrays['frames'].Items[k]);
      { the frame as drawing commands: one per move, line and cubic }
      cmds := TyMorphDataCmds(TyMorphPathData(md, 0.5));
      Inc(FCompared);
      if (Length(cmds) = 0) or (cmds[0].Kind <> pckMove) then
        Miss(c.Strings['id'] + ': the drawn frame does not start with a move');
    end;
  finally
    cs.Free;
  end;
  Finish('morphPath frames');
end;

procedure TAdvChartMorphTest.TestSplitAsUpstream;
var
  cs: TJSONArray;
  i, k, j: Integer;
  c, sh, w: TJSONObject;
  typ, id: string;
  pieces: TTyDividePieceArray;
  m: TTyMat2D;
  scale: Double;
  ps: TJSONArray;

  function SNum(const AKey: string): Double;
  begin
    Result := FromHex(sh.Strings[AKey]);
  end;

  procedure Same1(const AWhere: string; AGot: Double; const AKey: string);
  begin
    Inc(FCompared);
    if w.Find(AKey) = nil then
    begin
      Miss(AWhere + '.' + AKey + ': upstream has none');
      Exit;
    end;
    if Hex(AGot) <> w.Strings[AKey] then
      Miss(Format('%s.%s: %s, upstream %s', [AWhere, AKey, FloatToStr(AGot),
        FloatToStr(FromHex(w.Strings[AKey]))]));
  end;

begin
  cs := Cases('split');
  try
    AssertTrue('split cases', cs.Count >= 25);
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      typ := c.Strings['type'];
      sh := c.Objects['shape'];
      if typ = 'rect' then
        pieces := TyDivideRect(SNum('x'), SNum('y'), SNum('width'), SNum('height'),
          c.Integers['count'])
      else if typ = 'sector' then
        pieces := TyDivideSector(SNum('cx'), SNum('cy'), SNum('r0'), SNum('r'),
          SNum('startAngle'), SNum('endAngle'), sh.Find('clockwise') <> nil,
          (sh.Find('clockwise') <> nil) and sh.Booleans['clockwise'], c.Integers['count'])
      else if typ = 'circle' then
        pieces := TyDivideSector(SNum('cx'), SNum('cy'), 0, SNum('r'), 0, Pi * 2, False,
          False, c.Integers['count'])
      else
      begin
        scale := 1;
        if MatOf(c.Find('m'), m) then
          scale := Sqrt(Max(m[0] * m[0] + m[1] * m[1], m[2] * m[2] + m[3] * m[3]));
        pieces := TyDividePolygons(TyPathToPolygons(NumsOf(c.Find('data')), scale),
          c.Integers['count']);
      end;
      ps := c.Arrays['pieces'];
      Inc(FCompared);
      if Length(pieces) <> ps.Count then
      begin
        Miss(Format('%s: %d pieces, upstream %d', [id, Length(pieces), ps.Count]));
        Continue;
      end;
      for k := 0 to High(pieces) do
      begin
        w := ps.Objects[k];
        case pieces[k].Kind of
          dkRect:
            begin
              Inc(FCompared);
              if w.Strings['type'] <> 'rect' then Miss(Format('%s.%d: a rect, upstream %s', [id, k, w.Strings['type']]));
              Same1(Format('%s.%d', [id, k]), pieces[k].X, 'x');
              Same1(Format('%s.%d', [id, k]), pieces[k].Y, 'y');
              Same1(Format('%s.%d', [id, k]), pieces[k].W, 'width');
              Same1(Format('%s.%d', [id, k]), pieces[k].H, 'height');
            end;
          dkSector:
            begin
              Inc(FCompared);
              if w.Strings['type'] <> 'sector' then Miss(Format('%s.%d: a sector, upstream %s', [id, k, w.Strings['type']]));
              Same1(Format('%s.%d', [id, k]), pieces[k].CX, 'cx');
              Same1(Format('%s.%d', [id, k]), pieces[k].CY, 'cy');
              Same1(Format('%s.%d', [id, k]), pieces[k].R0, 'r0');
              Same1(Format('%s.%d', [id, k]), pieces[k].R, 'r');
              Same1(Format('%s.%d', [id, k]), pieces[k].StartAngle, 'startAngle');
              Same1(Format('%s.%d', [id, k]), pieces[k].EndAngle, 'endAngle');
              Inc(FCompared);
              if (w.Find('clockwise') = nil) or (w.Find('clockwise').JSONType = jtNull) then
              begin
                if pieces[k].HasClockwise then Miss(Format('%s.%d: a clockwise, upstream none', [id, k]));
              end
              else if (not pieces[k].HasClockwise) or (pieces[k].Clockwise <> w.Booleans['clockwise']) then
                Miss(Format('%s.%d: clockwise differs', [id, k]));
            end;
          dkPolygon:
            begin
              Inc(FCompared);
              if w.Strings['type'] <> 'polygon' then Miss(Format('%s.%d: a polygon, upstream %s', [id, k, w.Strings['type']]));
              Inc(FCompared);
              if Length(pieces[k].Points) <> Length(PointsFlat(w.Find('points'))) then
                Miss(Format('%s.%d.points: %d numbers, upstream %d', [id, k,
                  Length(pieces[k].Points), Length(PointsFlat(w.Find('points')))]))
              else
                for j := 0 to High(pieces[k].Points) do
                  SameNum(Format('%s.%d.points[%d]', [id, k, j]), pieces[k].Points[j],
                    Hex(PointsFlat(w.Find('points'))[j]));
            end;
        end;
      end;
    end;
  finally
    cs.Free;
  end;
  Finish('dividePath split');
end;

procedure TAdvChartMorphTest.TestGridsHilbertBatchesAsUpstream;
var
  cs: TJSONArray;
  c, r: TJSONObject;
  i, k, j: Integer;
  dim, inp: TTyDoubleArray;
  g: TTyDoubleArray;
  one: array of Integer;
  many: array of TTyIntegerArray;
  b: TTyMorphBatchArray;
  outs: TJSONArray;
  ok: Boolean;
begin
  cs := Cases('grids');
  try
    c := cs.Objects[0];
    for i := 0 to c.Arrays['rows'].Count - 1 do
    begin
      r := c.Arrays['rows'].Objects[i];
      dim := NumsOf(r.Find('dim'));
      g := TyDividingGrids(dim[0], dim[1], r.Integers['rowDim'], r.Integers['count']);
      Inc(FCompared);
      ok := Length(g) = r.Arrays['out'].Count;
      if ok then
        for k := 0 to High(g) do
          if g[k] <> r.Arrays['out'].Floats[k] then ok := False;
      if not ok then Miss(Format('grids %d: %d rows, upstream %s', [i, Length(g), r.Arrays['out'].AsJSON]));
    end;
  finally
    cs.Free;
  end;
  cs := Cases('hilbert');
  try
    c := cs.Objects[0];
    for i := 0 to c.Arrays['rows'].Count - 1 do
    begin
      r := c.Arrays['rows'].Objects[i];
      inp := NumsOf(r.Find('in'));
      SameNum(Format('hilbert %d', [i]), TyMorphHilbert(inp[0], inp[1], inp[2], inp[3], inp[4],
        inp[5]), r.Strings['out']);
    end;
  finally
    cs.Free;
  end;
  cs := Cases('batches');
  try
    c := cs.Objects[0];
    for i := 0 to c.Arrays['rows'].Count - 1 do
    begin
      r := c.Arrays['rows'].Objects[i];
      SetLength(one, r.Arrays['one'].Count);
      for k := 0 to High(one) do one[k] := r.Arrays['one'].Integers[k];
      SetLength(many, r.Arrays['many'].Count);
      for k := 0 to High(many) do
      begin
        SetLength(many[k], r.Arrays['many'].Arrays[k].Count);
        for j := 0 to High(many[k]) do many[k][j] := r.Arrays['many'].Arrays[k].Integers[j];
      end;
      b := TyPrepareMorphBatches(one, many);
      outs := r.Arrays['out'];
      Inc(FCompared);
      ok := Length(b) = outs.Count;
      if ok then
        for k := 0 to High(b) do
        begin
          if b[k].One <> outs.Objects[k].Integers['one'] then ok := False;
          if Length(b[k].Many) <> outs.Objects[k].Arrays['many'].Count then ok := False
          else
            for j := 0 to High(b[k].Many) do
              if b[k].Many[j] <> outs.Objects[k].Arrays['many'].Integers[j] then ok := False;
        end;
      if not ok then Miss(Format('batches %d differ from upstream %s', [i, outs.AsJSON]));
    end;
  finally
    cs.Free;
  end;
  Finish('grids / hilbert / batches');
end;

initialization
  RegisterTest(TAdvChartMorphTest);
finalization
  FreeAndNil(GFix);
end.
