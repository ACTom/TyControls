unit test.advchart.sankey;
{$mode objfpc}{$H+}
{ THE SANKEY SERIES -- each node's rect, each link's band (its four path
  commands and its extent), their fills (the value mapped over the palette,
  a node's colour, a gradient between two), and each node label's words,
  anchor, alignment and z2 -- held to what ECharts 6.1 draws.

  tools/advchart-oracle/sankey.js records every node and link upstream
  paints, local to the box, with the group's translation. The port's paint
  list is read back through the control: a shape (x, y) under (tx, ty) is at
  x + tx, a rect's right edge (x + w) + tx.

  The link grey is the theme's (TyAdvChartSankeyLink) and is passed over,
  counted, as are the treemap's white grounds.

  GEOMETRY UPSTREAM CANNOT SHOW -- a NaN or infinite coordinate, which is
  what a sankey with no links or with nought-valued nodes lays out -- is not
  emitted here at all: the element must be absent, and is counted. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TSkProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartSankeyOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TSkProbe;
    FRoot: TJSONData;
    FBad, FCompared, FNodes, FLinks, FLabels, FGradients, FSkipped, FInvisible: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure RunCases(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSankeyAsUpstreamDrawsIt;
    procedure TestTheGallerySankeysAsUpstream;
  end;

implementation

function TSkProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TSkProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TSkProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-sankey.json';
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

function Finite(const A: array of Double): Boolean;
var k: Integer;
begin
  Result := False;
  for k := 0 to High(A) do
    if IsNan(A[k]) or IsInfinite(A[k]) then Exit;
  Result := True;
end;

function Hex(AData: TJSONData): Double;
var q: QWord; s: string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  s := AData.AsString;
  if s = 'NaN' then Exit(NaN);
  if s = 'Infinity' then Exit(Infinity);
  if s = '-Infinity' then Exit(NegInfinity);
  q := StrToQWord('$' + s);
  Move(q, Result, SizeOf(Result));
end;

{ the translation of a recorded transform, or none }
procedure TransOf(AData: TJSONData; out ATX, ATY: Double);
begin
  ATX := 0;
  ATY := 0;
  if (AData <> nil) and (AData.JSONType = jtArray) and (AData.Count >= 6) then
  begin
    ATX := Hex(AData.Items[4]);
    ATY := Hex(AData.Items[5]);
  end;
end;

procedure TAdvChartSankeyOracleTest.SetUp;
var sl: TStringList; m: TJSONObject;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TSkProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FNodes := 0;
  FLinks := 0;
  FLabels := 0;
  FGradients := 0;
  FSkipped := 0;
  FInvisible := 0;
  FReport := '';
end;

procedure TAdvChartSankeyOracleTest.TearDown;
begin
  FRoot.Free;
  FChart.Measurer := nil;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartSankeyOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartSankeyOracleTest.RunCases(AGallery: Boolean);
var
  cases, series, nodes, edges, stops: TJSONArray;
  cs, opt, se, nd, ed, rc, sh, lb, band: TJSONObject;
  sl: TStringList;
  c, s, k, j, W, H, got: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  d: TJSONData;
  bmp: TBGRABitmap;
  tx, ty, x, y, w_, h_, x1, y1, x2, y2, cx1, cy1, cx2, cy2, ext: Double;
  vertical: Boolean;
  nodeAt, capAt, linkAt: array of Integer;
  want: TTyChartColor;
  txt, what: string;
  cmd: array[0..3] of TTyPathCmd;

  procedure CheckCmd(AIdx: Integer; AX1, AY1, AX2, AY2, AX, AY: Double; ACurve: Boolean);
  begin
    Inc(FCompared);
    if ACurve then
    begin
      if not (Same(e.Shape.Cmds[AIdx].X1, AX1) and Same(e.Shape.Cmds[AIdx].Y1, AY1)
        and Same(e.Shape.Cmds[AIdx].X2, AX2) and Same(e.Shape.Cmds[AIdx].Y2, AY2)) then
        Miss(Format('%s: command %d control points (%s, %s) (%s, %s) upstream, (%s, %s) (%s, %s) here',
          [what, AIdx, Fmt(AX1), Fmt(AY1), Fmt(AX2), Fmt(AY2), Fmt(e.Shape.Cmds[AIdx].X1),
           Fmt(e.Shape.Cmds[AIdx].Y1), Fmt(e.Shape.Cmds[AIdx].X2), Fmt(e.Shape.Cmds[AIdx].Y2)]));
    end;
    if not (Same(e.Shape.Cmds[AIdx].X, AX) and Same(e.Shape.Cmds[AIdx].Y, AY)) then
      Miss(Format('%s: command %d ends at (%s, %s) upstream, (%s, %s) here',
        [what, AIdx, Fmt(AX), Fmt(AY), Fmt(e.Shape.Cmds[AIdx].X), Fmt(e.Shape.Cmds[AIdx].Y)]));
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    d := cs.Find('gallery');
    if AGallery <> ((d <> nil) and (d.JSONType = jtString)) then Continue;
    FName := cs.Strings['id'];
    W := cs.Get('W', 800);
    H := cs.Get('H', 600);
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
    bmp := TBGRABitmap.Create(W, H, BGRA(255, 255, 255, 255));
    try
      if opt.Find('color') = nil then
        opt.Add('color', GetJSON('["#5070dd","#b6d634","#505372","#ff994d",'
          + '"#0ca8df","#ffd10a","#fb628b","#785db0","#3fbe95"]'));
      if opt.Find('animation') = nil then opt.Add('animation', False);
      FChart.Option := '{}';
      FChart.Option := opt.AsJSON;
      FChart.SetBounds(0, 0, W, H);
      try
        FChart.Render(bmp.Canvas, Classes.Rect(0, 0, W, H), 96);
      except
        on Ex: Exception do
        begin
          Miss(Ex.ClassName + ': ' + Ex.Message);
          Continue;
        end;
      end;
      lst := FChart.List;
      series := cs.Arrays['series'];
      for s := 0 to series.Count - 1 do
      begin
        se := series.Objects[s];
        FName := cs.Strings['id'];
        nodes := se.Arrays['nodes'];
        edges := se.Arrays['edges'];
        vertical := se.Objects['resolved'].Get('orient', '') = 'vertical';
        SetLength(nodeAt, 0);
        SetLength(capAt, 0);
        SetLength(linkAt, 0);
        SetLength(nodeAt, nodes.Count);
        SetLength(capAt, nodes.Count);
        SetLength(linkAt, edges.Count);
        for k := 0 to High(nodeAt) do begin nodeAt[k] := -1; capAt[k] := -1; end;
        for k := 0 to High(linkAt) do linkAt[k] := -1;
        got := 0;
        for k := 0 to lst.Count - 1 do
        begin
          e := lst.Element(k);
          if e.Datum.SeriesIndex <> s then Continue;
          if e.Datum.IsEdge then
          begin
            if (e.Datum.DataIndex >= 0) and (e.Datum.DataIndex < edges.Count) then
              linkAt[e.Datum.DataIndex] := k
            else
              Inc(got);
          end
          else if (e.Datum.DataIndex >= 0) and (e.Datum.DataIndex < nodes.Count) then
          begin
            if (e.Caption.FontSizeLogical > 0) and (e.Caption.Text <> '') then
              capAt[e.Datum.DataIndex] := k
            else
              nodeAt[e.Datum.DataIndex] := k;
          end;
        end;
        Inc(FCompared);
        if got > 0 then Miss(Format('%d links here past upstream''s %d', [got, edges.Count]));
        { ---- the links ---- }
        for j := 0 to edges.Count - 1 do
        begin
          ed := edges.Objects[j];
          what := Format('link %d', [j]);
          band := ed.Objects['band'];
          sh := band.Objects['shape'];
          if not Finite([Hex(sh.Find('x1')), Hex(sh.Find('y1')), Hex(sh.Find('x2')),
            Hex(sh.Find('y2')), Hex(sh.Find('cpx1')), Hex(sh.Find('cpy1')),
            Hex(sh.Find('cpx2')), Hex(sh.Find('cpy2')), Hex(sh.Find('extent'))]) then
          begin
            Inc(FInvisible);
            Inc(FCompared);
            if linkAt[j] >= 0 then Miss(what + ': invisible upstream, emitted here');
            Continue;
          end;
          Inc(FCompared);
          if linkAt[j] < 0 then
          begin
            Miss(what + ': drawn upstream, not here');
            Continue;
          end;
          Inc(FLinks);
          e := lst.Element(linkAt[j]);
          TransOf(band.Find('transform'), tx, ty);
          sh := band.Objects['shape'];
          x1 := Hex(sh.Find('x1')); y1 := Hex(sh.Find('y1'));
          x2 := Hex(sh.Find('x2')); y2 := Hex(sh.Find('y2'));
          cx1 := Hex(sh.Find('cpx1')); cy1 := Hex(sh.Find('cpy1'));
          cx2 := Hex(sh.Find('cpx2')); cy2 := Hex(sh.Find('cpy2'));
          ext := Hex(sh.Find('extent'));
          Inc(FCompared);
          if Length(e.Shape.Cmds) <> 5 then
          begin
            Miss(Format('%s: %d path commands here, not five', [what, Length(e.Shape.Cmds)]));
            Continue;
          end;
          CheckCmd(0, 0, 0, 0, 0, x1 + tx, y1 + ty, False);
          CheckCmd(1, cx1 + tx, cy1 + ty, cx2 + tx, cy2 + ty, x2 + tx, y2 + ty, True);
          if vertical then
          begin
            CheckCmd(2, 0, 0, 0, 0, (x2 + ext) + tx, y2 + ty, False);
            CheckCmd(3, (cx2 + ext) + tx, cy2 + ty, (cx1 + ext) + tx, cy1 + ty,
              (x1 + ext) + tx, y1 + ty, True);
          end
          else
          begin
            CheckCmd(2, 0, 0, 0, 0, x2 + tx, (y2 + ext) + ty, False);
            CheckCmd(3, cx2 + tx, (cy2 + ext) + ty, cx1 + tx, (cy1 + ext) + ty,
              x1 + tx, (y1 + ext) + ty, True);
          end;
          Inc(FCompared, 2);
          if e.Z2 <> band.Get('z2', 0) then
            Miss(Format('%s: z2 %d upstream, %d here', [what, band.Get('z2', 0), e.Z2]));
          if Abs(e.Style.Alpha - Hex(band.Find('opacity'))) > 1e-12 then
            Miss(Format('%s: opacity %s upstream, %s here', [what,
              Fmt(Hex(band.Find('opacity'))), Fmt(e.Style.Alpha)]));
          { the fill }
          d := band.Find('fill');
          if (d = nil) or (d.JSONType = jtNull) then
          begin
            Inc(FCompared);
            if e.Style.HasFill then Miss(what + ': no fill upstream, one here');
          end
          else if d.JSONType = jtObject then
          begin
            Inc(FGradients);
            stops := TJSONObject(d).Arrays['colorStops'];
            Inc(FCompared, 2);
            if (e.Style.FillGradient.Kind <> cgkLinear)
              or (Length(e.Style.FillGradient.Stops) <> stops.Count) then
              Miss(what + ': a gradient upstream, none here')
            else if ((TJSONObject(d).Find('x2') is TJSONNumber)
              and (e.Style.FillGradient.X2 <> TJSONObject(d).Floats['x2']))
              or ((TJSONObject(d).Find('y2') is TJSONNumber)
              and (e.Style.FillGradient.Y2 <> TJSONObject(d).Floats['y2'])) then
              Miss(Format('%s: gradient toward (%s, %s) upstream, (%s, %s) here', [what,
                TJSONObject(d).Get('x2', 'null'), TJSONObject(d).Get('y2', 'null'),
                Fmt(e.Style.FillGradient.X2), Fmt(e.Style.FillGradient.Y2)]))
            else
              for k := 0 to stops.Count - 1 do
              begin
                Inc(FCompared);
                if TyTryParseChartColor(stops.Objects[k].Get('color', ''), want)
                  and (e.Style.FillGradient.Stops[k].Color <> want) then
                  Miss(Format('%s: stop %d %s upstream, %.8x here', [what, k,
                    stops.Objects[k].Get('color', ''), e.Style.FillGradient.Stops[k].Color]));
              end;
          end
          else if d.AsString = '#86878c' then
            Inc(FSkipped)
          else if TyTryParseChartColor(d.AsString, want) then
          begin
            Inc(FCompared);
            if not e.Style.HasFill or (e.Style.FillColor <> want) then
              Miss(Format('%s: fill %s upstream, %.8x here', [what, d.AsString,
                e.Style.FillColor]));
          end;
        end;
        { ---- the nodes and their labels ---- }
        for j := 0 to nodes.Count - 1 do
        begin
          nd := nodes.Objects[j];
          what := Format('node %d (%s)', [j, nd.Get('id', '')]);
          rc := nd.Objects['rect'];
          sh := rc.Objects['shape'];
          if not Finite([Hex(sh.Find('x')), Hex(sh.Find('y')), Hex(sh.Find('width')),
            Hex(sh.Find('height'))]) then
          begin
            Inc(FInvisible);
            Inc(FCompared);
            if (nodeAt[j] >= 0) or (capAt[j] >= 0) then
              Miss(what + ': invisible upstream, emitted here');
            Continue;
          end;
          Inc(FCompared);
          if nodeAt[j] < 0 then
          begin
            Miss(what + ': drawn upstream, not here');
            Continue;
          end;
          Inc(FNodes);
          e := lst.Element(nodeAt[j]);
          TransOf(rc.Find('transform'), tx, ty);
          sh := rc.Objects['shape'];
          x := Hex(sh.Find('x')); y := Hex(sh.Find('y'));
          w_ := Hex(sh.Find('width')); h_ := Hex(sh.Find('height'));
          Inc(FCompared, 4);
          { edges compared as a set: a rounded rect of negative height is
            flipped, by zrender's roundRect as by the port's }
          if not (Same(Min(e.Shape.Bounds.Left, e.Shape.Bounds.Right), Min(x + tx, (x + w_) + tx))
            and Same(Max(e.Shape.Bounds.Left, e.Shape.Bounds.Right), Max(x + tx, (x + w_) + tx))
            and Same(Min(e.Shape.Bounds.Top, e.Shape.Bounds.Bottom), Min(y + ty, (y + h_) + ty))
            and Same(Max(e.Shape.Bounds.Top, e.Shape.Bounds.Bottom), Max(y + ty, (y + h_) + ty))) then
            Miss(Format('%s: (%s, %s)-(%s, %s) upstream, (%s, %s)-(%s, %s) here',
              [what, Fmt(x + tx), Fmt(y + ty), Fmt((x + w_) + tx), Fmt((y + h_) + ty),
               Fmt(e.Shape.Bounds.Left), Fmt(e.Shape.Bounds.Top),
               Fmt(e.Shape.Bounds.Right), Fmt(e.Shape.Bounds.Bottom)]));
          Inc(FCompared);
          if e.Z2 <> rc.Get('z2', 0) then
            Miss(Format('%s: z2 %d upstream, %d here', [what, rc.Get('z2', 0), e.Z2]));
          d := rc.Find('fill');
          if (d = nil) or (d.JSONType = jtNull) then
          begin
            Inc(FCompared);
            if e.Style.HasFill then Miss(what + ': no fill upstream, one here');
          end
          else if (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, want) then
          begin
            Inc(FCompared);
            if not e.Style.HasFill or (e.Style.FillColor <> want) then
              Miss(Format('%s: fill %s upstream, %.8x here', [what, d.AsString,
                e.Style.FillColor]));
          end;
          { the label }
          d := nd.Find('label');
          Inc(FCompared);
          if (d = nil) or (d.JSONType <> jtObject) then
          begin
            if capAt[j] >= 0 then
              Miss(what + ': no label upstream, "' + lst.Element(capAt[j]).Caption.Text + '" here');
            Continue;
          end;
          lb := TJSONObject(d);
          txt := '';
          if lb.Find('lines') is TJSONArray then
            for k := 0 to lb.Arrays['lines'].Count - 1 do
            begin
              if k > 0 then txt := txt + #10;
              txt := txt + lb.Arrays['lines'].Strings[k];
            end;
          if (lb.Find('anchor') is TJSONObject) and not Finite([
            Hex(lb.Objects['anchor'].Find('x')), Hex(lb.Objects['anchor'].Find('y'))]) then
          begin
            Inc(FInvisible);
            Inc(FCompared);
            if capAt[j] >= 0 then Miss(what + ': a label nowhere upstream, one here');
            Continue;
          end;
          if txt = '' then
          begin
            if capAt[j] >= 0 then
              Miss(what + ': no label upstream, "' + lst.Element(capAt[j]).Caption.Text + '" here');
            Continue;
          end;
          if capAt[j] < 0 then
          begin
            Miss(what + ': label "' + txt + '" upstream, none here');
            Continue;
          end;
          Inc(FLabels);
          e := lst.Element(capAt[j]);
          TransOf(lb.Find('transform'), tx, ty);
          Inc(FCompared, 4);
          if e.Caption.Text <> txt then
            Miss(Format('%s: label "%s" upstream, "%s" here', [what, txt, e.Caption.Text]));
          if not (Same(e.Caption.X, tx) and Same(e.Caption.Y, ty)) then
            Miss(Format('%s: label at (%s, %s) upstream, (%s, %s) here', [what,
              Fmt(tx), Fmt(ty), Fmt(e.Caption.X), Fmt(e.Caption.Y)]));
          if e.Z2 <> lb.Get('z2', 0) then
            Miss(Format('%s: label z2 %d upstream, %d here', [what, lb.Get('z2', 0), e.Z2]));
          { an ink the option wrote is compared; the auto inks are the theme's }
          if (lb.Get('colourRule', '') = 'option')
            and TyTryParseChartColor(lb.Get('fill', ''), want) then
          begin
            Inc(FCompared);
            if e.Caption.Colour <> want then
              Miss(Format('%s: label ink %s upstream, %.8x here', [what, lb.Get('fill', ''),
                e.Caption.Colour]));
          end;
          { an array position leaves both alignments to the text: left, top }
          if not ((((lb.Get('align', 'left') = 'center') = (e.Caption.AnchorH = tahCentre))
            and ((lb.Get('align', 'left') = 'right') = (e.Caption.AnchorH = tahRight)))
            and (((lb.Get('verticalAlign', 'top') = 'middle') = (e.Caption.AnchorV = tavMiddle))
            and ((lb.Get('verticalAlign', 'top') = 'bottom') = (e.Caption.AnchorV = tavBottom)))) then
            Miss(Format('%s: label aligned %s/%s upstream, otherwise here', [what,
              lb.Get('align', 'null'), lb.Get('verticalAlign', 'null')]));
        end;
      end;
    finally
      bmp.Free;
      opt.Free;
    end;
  end;
end;

procedure TAdvChartSankeyOracleTest.TestTheSankeyAsUpstreamDrawsIt;
begin
  RunCases(False);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d nodes, %d links (%d gradients), %d labels; %d theme greys passed over, %d invisible',
    [FNodes, FLinks, FGradients, FLabels, FSkipped, FInvisible]),
    (FNodes >= 3000) and (FLinks >= 1500) and (FLabels >= 3000) and (FGradients >= 100));
end;

procedure TAdvChartSankeyOracleTest.TestTheGallerySankeysAsUpstream;
begin
  RunCases(True);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d nodes, %d links (%d gradients), %d labels',
    [FNodes, FLinks, FGradients, FLabels]), (FNodes >= 400) and (FLinks >= 400));
end;

initialization
  RegisterTest(TAdvChartSankeyOracleTest);
end.
