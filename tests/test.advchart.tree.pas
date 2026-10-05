unit test.advchart.tree;
{$mode objfpc}{$H+}
{ THE TREE SERIES -- which nodes are drawn, where each lands, its symbol's
  ink, every curve edge's four points, and each label's words and anchor --
  held to what ECharts 6.1 draws.

  tools/advchart-oracle/tree.js records every SeriesData row (the virtual
  root first, then the hierarchy in pre-order) and every edge. The port's
  paint list is read back: a node is the symbol the series added for that
  row, an edge the curve stamped with its child's row, a label the caption
  the expansion placed.

  EXACT: positions and edge points to the bit. Colours are compared where the
  option wrote them -- a tree's own defaults are the skin's, by the theme
  rule. The radial layout and the polyline edges are the next batch's, and
  their cases are counted as passed over, not compared. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvChart.Option, tyControls.AdvChart.Tree,
     tyControls.AdvanceChart;
type
  TTrProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartTreeOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTrProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FNodes, FEdges, FLabels, FSkipped: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure RunCases(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTreeAsUpstreamDrawsIt;
    procedure TestTheGalleryTreesAsUpstream;
    procedure TestATreeTakesNoPaletteSlot;
    procedure TestRightAndWidthDropTheDefaultLeft;
  end;

implementation

procedure TTrProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TTrProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-tree.json';
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
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
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

procedure TAdvChartTreeOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TTrProbe.Create(FForm);
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
  FNodes := 0;
  FEdges := 0;
  FLabels := 0;
  FSkipped := 0;
  FReport := '';
end;

procedure TAdvChartTreeOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartTreeOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartTreeOracleTest.RunCases(AGallery: Boolean);
var
  cases, series, rows, edges, cmds: TJSONArray;
  cs, opt, se, row, sy, st, lb, ed, sh, mg: TJSONObject;
  sl: TStringList;
  c, s, k, j, si, ri, n: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  d: TJSONData;
  symAt, capAt, edgeAt: array of Integer;
  cx, cy, w, h, ox, oy, lx, ly: Double;
  want: TTyChartColor;
  b: TTyRectF;
  w_, ty: string;
  radial, poly: Boolean;
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
        radial := se.Get('layout', '') = 'radial';
        poly := se.Get('edgeShape', '') = 'polyline';
        rows := se.Arrays['rows'];
        n := rows.Count;
        SetLength(symAt, 0);
        SetLength(capAt, 0);
        SetLength(edgeAt, 0);
        SetLength(symAt, n);
        SetLength(capAt, n);
        SetLength(edgeAt, n);
        for k := 0 to n - 1 do
        begin
          symAt[k] := -1;
          capAt[k] := -1;
          edgeAt[k] := -1;
        end;
        for k := 0 to lst.Count - 1 do
        begin
          e := lst.Element(k);
          if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex < 0)
            or (e.Datum.DataIndex >= n) then Continue;
          if (e.Caption.FontSizeLogical > 0) and (e.Caption.Text <> '') then
            capAt[e.Datum.DataIndex] := k
          else if e.Z2 >= 100 then
            symAt[e.Datum.DataIndex] := k
          else
            edgeAt[e.Datum.DataIndex] := k;
        end;
        mg := se.Objects['mainGroup'];
        ox := Num(mg.Find('x'));
        oy := Num(mg.Find('y'));
        { ---- the nodes ---- }
        for ri := 0 to n - 1 do
        begin
          row := rows.Objects[ri];
          w_ := Format('row %d (%s)', [ri, row.Get('name', '')]);
          Inc(FCompared);
          if row.Get('drawn', False) <> (symAt[ri] >= 0) then
          begin
            if row.Get('drawn', False) then Miss(w_ + ': a node upstream, none here')
            else Miss(w_ + ': no node upstream, one here');
            Continue;
          end;
          if not row.Get('drawn', False) then Continue;
          Inc(FNodes);
          sy := row.Objects['symbol'];
          e := lst.Element(symAt[ri]);
          b := TyShapeBounds(e.Shape);
          cx := Num(sy.Arrays['global'].Items[0]) + Num(sy.Objects['path'].Find('x'));
          cy := Num(sy.Arrays['global'].Items[1]) + Num(sy.Objects['path'].Find('y'));
          ty := sy.Get('pathType', '');
          Inc(FCompared, 2);
          if (Num(sy.Objects['path'].Find('rotation')) = 0)
            and ((ty = 'circle') or (ty = 'rect') or (ty = 'roundRect') or (ty = 'diamond')) then
          begin
            if not (Near((b.Left + b.Right) / 2, cx) and Near((b.Top + b.Bottom) / 2, cy)) then
              Miss(Format('%s: centred at (%s, %s) upstream, (%s, %s) here', [w_, Fmt(cx), Fmt(cy),
                Fmt((b.Left + b.Right) / 2), Fmt((b.Top + b.Bottom) / 2)]));
            w := Num(sy.Arrays['size'].Items[0]);
            h := Num(sy.Arrays['size'].Items[1]);
            if not (Near(b.Right - b.Left, w) and Near(b.Bottom - b.Top, h)) then
              Miss(Format('%s: %s x %s upstream, %s x %s here', [w_, Fmt(w), Fmt(h),
                Fmt(b.Right - b.Left), Fmt(b.Bottom - b.Top)]));
          end;
          { the layout itself, exactly: the symbol's group is the node }
          Inc(FCompared);
          if (ty = 'circle') and (Num(sy.Objects['path'].Find('x')) = 0)
            and (Num(sy.Objects['path'].Find('y')) = 0) and (e.Shape.Kind = cskCircle)
            and not (Same(e.Shape.CX, ox + Num(row.Objects['layout'].Find('x')))
              and Same(e.Shape.CY, oy + Num(row.Objects['layout'].Find('y')))) then
            Miss(Format('%s: at (%s, %s) upstream, (%s, %s) here', [w_,
              Fmt(ox + Num(row.Objects['layout'].Find('x'))),
              Fmt(oy + Num(row.Objects['layout'].Find('y'))), Fmt(e.Shape.CX), Fmt(e.Shape.CY)]));
          Inc(FCompared, 2);
          if e.Z2 <> sy.Integers['z2'] then
            Miss(Format('%s: z2 %d upstream, %d here', [w_, sy.Integers['z2'], e.Z2]));
          st := sy.Objects['ink'];
          if (st.Get('stroke', '') <> 'lightsteelblue') and (st.Get('stroke', '') <> '')
            and TyTryParseChartColor(st.Get('stroke', ''), want) and sy.Get('emptyBrush', False) then
          begin
            Inc(FCompared);
            if e.Style.StrokeColor <> want then Miss(w_ + ': the ring''s colour differs');
          end;
          if sy.Get('emptyBrush', False) then
          begin
            Inc(FCompared);
            { a ring of no size paints nothing at any width; the port draws it
              at none, so no dot is left where upstream draws nothing }
            if (Num(sy.Arrays['size'].Items[0]) <> 0) and (Num(sy.Arrays['size'].Items[1]) <> 0)
              and (e.Style.StrokeWidthLogical <> Num(st.Find('lineWidth'))) then
              Miss(Format('%s: ring %s wide upstream, %s here', [w_,
                Fmt(Num(st.Find('lineWidth'))), Fmt(e.Style.StrokeWidthLogical)]));
            { a hollow node shows the ground; a node hiding children is solid }
            Inc(FCompared);
            if (st.Get('fill', '') <> '#fff') and TyTryParseChartColor(st.Get('fill', ''), want)
              and (st.Get('fill', '') <> 'lightsteelblue') and (e.Style.FillColor <> want) then
              Miss(w_ + ': the fill differs');
            if (st.Get('fill', '') = st.Get('stroke', '')) and (e.Style.FillColor <> e.Style.StrokeColor) then
              Miss(w_ + ': a collapsed node is solid upstream, hollow here');
          end
          else if (st.Get('fill', '') <> 'lightsteelblue')
            and TyTryParseChartColor(st.Get('fill', ''), want) then
          begin
            Inc(FCompared);
            if e.Style.FillColor <> want then Miss(w_ + ': the fill differs');
          end;
          if not IsNull(st.Find('opacity')) then
          begin
            Inc(FCompared);
            if Abs(e.Style.Alpha - Num(st.Find('opacity'))) > 1e-12 then
              Miss(Format('%s: opacity %s upstream, %s here', [w_, Fmt(Num(st.Find('opacity'))),
                Fmt(e.Style.Alpha)]));
          end;
          { ---- its label ---- }
          d := row.Find('label');
          Inc(FCompared);
          if IsNull(d) or (TJSONObject(d).Get('text', '') = '') then
          begin
            if capAt[ri] >= 0 then Miss(w_ + ': no label upstream, "'
              + lst.Element(capAt[ri]).Caption.Text + '" here');
            Continue;
          end;
          lb := TJSONObject(d);
          if capAt[ri] < 0 then
          begin
            Miss(w_ + ': label "' + lb.Strings['text'] + '" upstream, none here');
            Continue;
          end;
          Inc(FLabels);
          e := lst.Element(capAt[ri]);
          Inc(FCompared, 3);
          if e.Caption.Text <> lb.Strings['text'] then
            Miss(Format('%s: label "%s" upstream, "%s" here', [w_, lb.Strings['text'],
              e.Caption.Text]));
          { the anchor: where the words' own origin lands -- the transform's
            move, which for a radial label includes its turn about the box }
          lx := Num(lb.Objects['inner'].Find('x'));
          ly := Num(lb.Objects['inner'].Find('y'));
          { A TURNED LABEL WITH AN OFFSET is drawn at the transform's move:
            the offset runs along the turn (origin = -offset), which the
            inner point does not show [Batch 103: the port added the offset
            in screen axes, and this compared the inner point] }
          if (not radial) and not IsNull(lb.Find('transform'))
            and (Num(lb.Objects['inner'].Find('rotation')) <> 0) then
          begin
            lx := Num(lb.Arrays['transform'].Items[4]);
            ly := Num(lb.Arrays['transform'].Items[5]);
          end;
          if radial then
          begin
            lx := Num(lb.Arrays['transform'].Items[4]);
            ly := Num(lb.Arrays['transform'].Items[5]);
            Inc(FCompared);
            if not Same(e.Caption.RotationRad, Num(lb.Objects['inner'].Find('rotation'))) then
              Miss(Format('%s: label turned %s upstream, %s here', [w_,
                Fmt(Num(lb.Objects['inner'].Find('rotation'))), Fmt(e.Caption.RotationRad)]));
          end;
          if not (Same(e.Caption.X, lx) and Same(e.Caption.Y, ly)) then
            Miss(Format('%s: label at (%s, %s) upstream, (%s, %s) here', [w_,
              Fmt(lx), Fmt(ly), Fmt(e.Caption.X), Fmt(e.Caption.Y)]));
          if not (((lb.Get('align', '') = 'center') = (e.Caption.AnchorH = tahCentre))
            and ((lb.Get('align', '') = 'right') = (e.Caption.AnchorH = tahRight))
            and ((lb.Get('verticalAlign', '') = 'middle') = (e.Caption.AnchorV = tavMiddle))
            and ((lb.Get('verticalAlign', '') = 'bottom') = (e.Caption.AnchorV = tavBottom))) then
            Miss(Format('%s: label aligned %s/%s upstream, otherwise here', [w_,
              lb.Get('align', ''), lb.Get('verticalAlign', '')]));
        end;
        { ---- the edges ---- }
        edges := se.Arrays['edges'];
        if poly then
        begin
          for j := 0 to edges.Count - 1 do
          begin
            ed := edges.Objects[j];
            if ed.Get('kind', '') <> 'polyline' then Continue;
            ri := ed.Integers['owner'];
            w_ := Format('fork from row %d', [ri]);
            Inc(FCompared);
            if edgeAt[ri] < 0 then
            begin
              Miss(w_ + ': drawn upstream, not here');
              Continue;
            end;
            Inc(FEdges);
            e := lst.Element(edgeAt[ri]);
            cmds := ed.Arrays['commands'];
            Inc(FCompared);
            if Length(e.Shape.Cmds) <> cmds.Count then
            begin
              Miss(Format('%s: %d commands upstream, %d here', [w_, cmds.Count,
                Length(e.Shape.Cmds)]));
              Continue;
            end;
            for k := 0 to cmds.Count - 1 do
            begin
              Inc(FCompared, 3);
              if ((cmds.Objects[k].Get('cmd', '') = 'M') <> (e.Shape.Cmds[k].Kind = pckMove))
                or not Same(e.Shape.Cmds[k].X, ox + Num(cmds.Objects[k].Arrays['args'].Items[0]))
                or not Same(e.Shape.Cmds[k].Y, oy + Num(cmds.Objects[k].Arrays['args'].Items[1])) then
              begin
                Miss(Format('%s: command %d %s %s,%s upstream, %s,%s here', [w_, k,
                  cmds.Objects[k].Get('cmd', ''),
                  Fmt(ox + Num(cmds.Objects[k].Arrays['args'].Items[0])),
                  Fmt(oy + Num(cmds.Objects[k].Arrays['args'].Items[1])),
                  Fmt(e.Shape.Cmds[k].X), Fmt(e.Shape.Cmds[k].Y)]));
                Break;
              end;
            end;
            st := ed.Objects['ink'];
            Inc(FCompared);
            if e.Style.StrokeWidthLogical <> Num(st.Find('lineWidth')) then
              Miss(w_ + ': the width differs');
            if (st.Get('stroke', '') <> '#cfd2d7') and TyTryParseChartColor(st.Get('stroke', ''), want)
              and (e.Style.StrokeColor <> want) then
              Miss(w_ + ': the colour differs');
          end;
          { and none here that upstream does not draw }
          for ri := 0 to n - 1 do
            if edgeAt[ri] >= 0 then
            begin
              k := 0;
              for j := 0 to edges.Count - 1 do
                if (edges.Objects[j].Get('kind', '') = 'polyline')
                  and (edges.Objects[j].Integers['owner'] = ri) then k := 1;
              Inc(FCompared);
              if k = 0 then Miss(Format('a fork from row %d here, none upstream', [ri]));
            end;
          Continue;
        end;
        for j := 0 to edges.Count - 1 do
        begin
          ed := edges.Objects[j];
          if ed.Get('kind', '') <> 'curve' then Continue;
          ri := ed.Arrays['to'].Integers[0];
          w_ := Format('edge to row %d', [ri]);
          Inc(FCompared);
          if edgeAt[ri] < 0 then
          begin
            Miss(w_ + ': drawn upstream, not here');
            Continue;
          end;
          Inc(FEdges);
          e := lst.Element(edgeAt[ri]);
          sh := ed.Objects['shape'];
          Inc(FCompared, 8);
          if (Length(e.Shape.Cmds) <> 2) or (e.Shape.Cmds[1].Kind <> pckCurve) then
          begin
            Miss(w_ + ': not a cubic here');
            Continue;
          end;
          if not (Same(e.Shape.Cmds[0].X, ox + Num(sh.Find('x1')))
            and Same(e.Shape.Cmds[0].Y, oy + Num(sh.Find('y1')))
            and Same(e.Shape.Cmds[1].X1, ox + Num(sh.Find('cpx1')))
            and Same(e.Shape.Cmds[1].Y1, oy + Num(sh.Find('cpy1')))
            and Same(e.Shape.Cmds[1].X2, ox + Num(sh.Find('cpx2')))
            and Same(e.Shape.Cmds[1].Y2, oy + Num(sh.Find('cpy2')))
            and Same(e.Shape.Cmds[1].X, ox + Num(sh.Find('x2')))
            and Same(e.Shape.Cmds[1].Y, oy + Num(sh.Find('y2')))) then
            Miss(Format('%s: M %s,%s C %s,%s %s,%s %s,%s upstream, M %s,%s C %s,%s %s,%s %s,%s here',
              [w_, Fmt(ox + Num(sh.Find('x1'))), Fmt(oy + Num(sh.Find('y1'))),
               Fmt(ox + Num(sh.Find('cpx1'))), Fmt(oy + Num(sh.Find('cpy1'))),
               Fmt(ox + Num(sh.Find('cpx2'))), Fmt(oy + Num(sh.Find('cpy2'))),
               Fmt(ox + Num(sh.Find('x2'))), Fmt(oy + Num(sh.Find('y2'))),
               Fmt(e.Shape.Cmds[0].X), Fmt(e.Shape.Cmds[0].Y), Fmt(e.Shape.Cmds[1].X1),
               Fmt(e.Shape.Cmds[1].Y1), Fmt(e.Shape.Cmds[1].X2), Fmt(e.Shape.Cmds[1].Y2),
               Fmt(e.Shape.Cmds[1].X), Fmt(e.Shape.Cmds[1].Y)]));
          st := ed.Objects['ink'];
          Inc(FCompared, 2);
          if e.Style.StrokeWidthLogical <> Num(st.Find('lineWidth')) then
            Miss(Format('%s: %s wide upstream, %s here', [w_, Fmt(Num(st.Find('lineWidth'))),
              Fmt(e.Style.StrokeWidthLogical)]));
          if (st.Get('stroke', '') <> '#cfd2d7') and TyTryParseChartColor(st.Get('stroke', ''), want)
            and (e.Style.StrokeColor <> want) then
            Miss(w_ + ': the colour differs');
          if not IsNull(st.Find('opacity')) and (Abs(e.Style.Alpha - Num(st.Find('opacity'))) > 1e-12) then
            Miss(w_ + ': the opacity differs');
          if e.Z2 <> ed.Integers['z2'] then
            Miss(Format('%s: z2 %d upstream, %d here', [w_, ed.Integers['z2'], e.Z2]));
        end;
        { no edge here that upstream does not draw }
        for ri := 0 to n - 1 do
          if edgeAt[ri] >= 0 then
          begin
            k := 0;
            for j := 0 to edges.Count - 1 do
              if (edges.Objects[j].Get('kind', '') = 'curve')
                and (edges.Objects[j].Arrays['to'].Integers[0] = ri) then k := 1;
            Inc(FCompared);
            if k = 0 then Miss(Format('an edge to row %d here, none upstream', [ri]));
          end;
      end;
    finally
      opt.Free;
    end;
  end;
end;

procedure TAdvChartTreeOracleTest.TestTheTreeAsUpstreamDrawsIt;
begin
  RunCases(False);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d nodes, %d edges, %d labels (%d passed over)',
    [FNodes, FEdges, FLabels, FSkipped]), (FNodes >= 300) and (FEdges >= 200) and (FLabels >= 200));
end;

procedure TAdvChartTreeOracleTest.TestTheGalleryTreesAsUpstream;
begin
  RunCases(True);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d nodes, %d edges, %d labels (%d passed over)',
    [FNodes, FEdges, FLabels, FSkipped]), FNodes >= 100);
end;

procedure TAdvChartTreeOracleTest.TestATreeTakesNoPaletteSlot;
var
  lst: TTyPaintList;
  k: Integer;
  e: TTyChartElement;
  found: Boolean;
  want: TTyChartColor;
begin
  { a tree's defaults name its colour, so it takes no slot: the bar after it
    is the palette's FIRST colour, as upstream's is }
  FChart.Option := '{"color": ["#112233", "#445566"], "xAxis": {"type": "category",'
    + ' "data": ["a"]}, "yAxis": {}, "series": [{"type": "tree", "data": [{"name": "r"}]},'
    + ' {"type": "bar", "data": [3]}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  AssertTrue('parses', TyTryParseChartColor('#112233', want));
  found := False;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Datum.SeriesIndex = 1) and (e.Shape.Kind = cskRect) and e.Style.HasFill then
    begin
      found := True;
      AssertEquals('the bar takes the first colour', want, e.Style.FillColor);
    end;
  end;
  AssertTrue('the bar is drawn', found);
end;

procedure TAdvChartTreeOracleTest.TestRightAndWidthDropTheDefaultLeft;
var
  opt: TTyChartOption;
  sv: TTyTreeSolved;
begin
  { mergeDefaultAndTheme's count-based merge: `right` and `width` written are
    two of the three, so the default `left: '12%'` is DROPPED and the box is
    pinned at the right -- getLayoutRect would otherwise take the left and
    ignore the right. Likewise `bottom` and `height` drop the default top. }
  opt := TTyChartOption.Create;
  try
    AssertTrue(opt.SetOptionText('{"series": [{"type": "tree", "right": 50, "width": 300,'
      + ' "bottom": 40, "height": 200, "data": [{"name": "r"}]}]}'));
    sv := TyTreeSolve(opt, 0, TyRectF(0, 0, 800, 600), 96);
    AssertEquals('x: 800 - 50 - 300', 450, sv.Box.X);
    AssertEquals('width as written', 300, sv.Box.W);
    AssertEquals('y: 600 - 40 - 200', 360, sv.Box.Y);
  finally
    opt.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartTreeOracleTest);
end.
