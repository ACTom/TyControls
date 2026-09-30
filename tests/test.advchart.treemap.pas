unit test.advchart.treemap;
{$mode objfpc}{$H+}
{ THE TREEMAP SERIES -- which nodes are drawn, each background and content
  rect to the bit, their fills, each label's words (after zrender's line drop
  and truncation), anchor and z2, and the breadcrumb's arrows and words --
  held to what ECharts 6.1 draws.

  tools/advchart-oracle/treemap.js records every row and every element
  upstream paints. The port's paint list is read back through the control,
  measuring text with zrender's own SSR width table (the oracle's).

  A rect upstream is a shape (x, y, w, h) under a group transform (tx, ty):
  its left is x + tx and its right (x + w) + tx, and that is what the port's
  bounds must be, bit for bit. A white background is the port's ground (the
  theme's) and is passed over, counted.

  A LABEL'S WORDS ARE PASSED OVER, counted, where the case writes a
  `fontSize`: the port reads an author's size into its logical unit, the
  theme's points, so 14 there is 14 pt, not upstream's 14 px -- a question
  for every series, not this one. The anchor and z2 are still compared. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TTmProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartTreemapOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTmProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FRects, FLabels, FCrumbs, FSkipped, FSkippedWords: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure RunCases(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTreemapAsUpstreamDrawsIt;
    procedure TestTheGalleryTreemapAsUpstream;
  end;

implementation

function TTmProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TTmProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TTmProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-treemap.json';
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

{ a double from the fixture: 16 hex digits of its bits, or a number }
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

procedure TAdvChartTreemapOracleTest.SetUp;
var sl: TStringList; m: TJSONObject;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TTmProbe.Create(FForm);
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
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FRects := 0;
  FLabels := 0;
  FCrumbs := 0;
  FSkipped := 0;
  FSkippedWords := 0;
  FReport := '';
end;

procedure TAdvChartTreemapOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Measurer := nil;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartTreemapOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartTreemapOracleTest.RunCases(AGallery: Boolean);
var
  cases, series, elems, rows: TJSONArray;
  cs, opt, se, ex, sh: TJSONObject;
  sl: TStringList;
  c, s, k, j, si, n, row, want, got, wantLbl: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  d, tr: TJSONData;
  tx, ty, sx, sy, sw, shh, px, py: Double;
  kind, w_, txt: string;
  bgAt, ctAt, capAt: array of Integer;
  lblText: array of string;
  lblX, lblY: array of Double;
  lblZ2: array of Integer;
  hasLbl: array of Boolean;
  crumbEls, crumbCaps: array of Integer;
  wantCol: TTyChartColor;
  seenCrumb, seenCrumbText: Integer;
  sized: Boolean;
  lastTx, lastTy: Double;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    d := cs.Find('gallery');
    if AGallery <> ((d <> nil) and (d.JSONType = jtString)) then Continue;
    FName := cs.Strings['id'];
    d := cs.Find('option');
    sized := (d <> nil) and (Pos('"fontSize"', d.AsJSON) > 0);
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
      if opt.Find('animation') = nil then opt.Add('animation', False);
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
        { the port's elements by row }
        SetLength(bgAt, 0); SetLength(ctAt, 0); SetLength(capAt, 0);
        SetLength(bgAt, n); SetLength(ctAt, n); SetLength(capAt, n);
        for k := 0 to n - 1 do
        begin
          bgAt[k] := -1; ctAt[k] := -1; capAt[k] := -1;
        end;
        crumbEls := nil;
        crumbCaps := nil;
        for k := 0 to lst.Count - 1 do
        begin
          e := lst.Element(k);
          if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex < 0)
            or (e.Datum.DataIndex >= n) then Continue;
          if (e.Caption.FontSizeLogical > 0) and (e.Caption.Text <> '') then
          begin
            if e.Z2 >= 100000 then
            begin
              SetLength(crumbCaps, Length(crumbCaps) + 1);
              crumbCaps[High(crumbCaps)] := k;
            end
            else
              capAt[e.Datum.DataIndex] := k;
          end
          else if e.Shape.Kind = cskPolygon then
          begin
            SetLength(crumbEls, Length(crumbEls) + 1);
            crumbEls[High(crumbEls)] := k;
          end
          else if e.Shape.Kind = cskRect then
          begin
            if e.Z2 mod 100 = 20 then bgAt[e.Datum.DataIndex] := k
            else if e.Z2 mod 100 = 30 then ctAt[e.Datum.DataIndex] := k;
          end;
        end;
        { the labels upstream: each row's tspans, joined }
        SetLength(lblText, 0); SetLength(lblX, 0); SetLength(lblY, 0);
        SetLength(lblZ2, 0); SetLength(hasLbl, 0);
        SetLength(lblText, n); SetLength(lblX, n); SetLength(lblY, n);
        SetLength(lblZ2, n); SetLength(hasLbl, n);
        elems := se.Arrays['elements'];
        seenCrumb := 0;
        seenCrumbText := 0;
        for j := 0 to elems.Count - 1 do
        begin
          ex := elems.Objects[j];
          kind := ex.Get('kind', '');
          row := ex.Get('row', -1);
          tr := ex.Find('transform');
          tx := 0;
          ty := 0;
          if (tr <> nil) and (tr.JSONType = jtArray) then
          begin
            tx := Hex(TJSONArray(tr).Items[4]);
            ty := Hex(TJSONArray(tr).Items[5]);
          end;
          w_ := Format('row %d %s', [row, kind]);
          if (kind = 'bg') or (kind = 'content') then
          begin
            if (row < 0) or (row >= n) then Continue;
            if kind = 'bg' then got := bgAt[row] else got := ctAt[row];
            Inc(FCompared);
            if got < 0 then
            begin
              Miss(w_ + ': drawn upstream, not here');
              Continue;
            end;
            Inc(FRects);
            e := lst.Element(got);
            sh := ex.Objects['shape'];
            sx := Hex(sh.Find('x'));
            sy := Hex(sh.Find('y'));
            sw := Hex(sh.Find('width'));
            shh := Hex(sh.Find('height'));
            Inc(FCompared, 4);
            if not (Same(e.Shape.Bounds.Left, sx + tx) and Same(e.Shape.Bounds.Top, sy + ty)
              and Same(e.Shape.Bounds.Right, (sx + sw) + tx)
              and Same(e.Shape.Bounds.Bottom, (sy + shh) + ty)) then
              Miss(Format('%s: (%s, %s)-(%s, %s) upstream, (%s, %s)-(%s, %s) here',
                [w_, Fmt(sx + tx), Fmt(sy + ty), Fmt((sx + sw) + tx), Fmt((sy + shh) + ty),
                 Fmt(e.Shape.Bounds.Left), Fmt(e.Shape.Bounds.Top),
                 Fmt(e.Shape.Bounds.Right), Fmt(e.Shape.Bounds.Bottom)]));
            Inc(FCompared);
            if e.Z2 <> ex.Integers['z2'] then
              Miss(Format('%s: z2 %d upstream, %d here', [w_, ex.Integers['z2'], e.Z2]));
            d := ex.Find('fill');
            if (d = nil) or (d.JSONType = jtNull) then
            begin
              Inc(FCompared);
              if e.Style.HasFill then Miss(w_ + ': no fill upstream, one here');
            end
            else if (d.AsString = '#fff') or (d.AsString = 'white') then
              Inc(FSkipped)
            else if TyTryParseChartColor(d.AsString, wantCol) then
            begin
              Inc(FCompared);
              if not e.Style.HasFill or (e.Style.FillColor <> wantCol) then
                Miss(Format('%s: fill %s upstream, %.8x here', [w_, d.AsString,
                  e.Style.FillColor]));
            end;
          end
          else if kind = 'tspan' then
          begin
            if (row < 0) or (row >= n) then Continue;
            if hasLbl[row] then lblText[row] := lblText[row] + #10 + ex.Get('text', '')
            else lblText[row] := ex.Get('text', '');
            hasLbl[row] := True;
            lblX[row] := tx;
            lblY[row] := ty;
            lblZ2[row] := ex.Integers['z2'];
          end
          else if kind = 'crumb' then
          begin
            Inc(FCompared);
            if seenCrumb > High(crumbEls) then
            begin
              Miss('a crumb upstream, none here');
              Inc(seenCrumb);
              Continue;
            end;
            Inc(FCrumbs);
            e := lst.Element(crumbEls[seenCrumb]);
            Inc(seenCrumb);
            tr := ex.Find('points');
            Inc(FCompared);
            if Length(e.Shape.Points) <> tr.Count then
            begin
              Miss(Format('crumb %d: %d points upstream, %d here', [seenCrumb,
                tr.Count, Length(e.Shape.Points)]));
              Continue;
            end;
            for k := 0 to tr.Count - 1 do
            begin
              px := Hex(TJSONArray(tr.Items[k]).Items[0]) + tx;
              py := Hex(TJSONArray(tr.Items[k]).Items[1]) + ty;
              Inc(FCompared);
              if not (Same(e.Shape.Points[k].X, px) and Same(e.Shape.Points[k].Y, py)) then
              begin
                Miss(Format('crumb %d point %d: (%s, %s) upstream, (%s, %s) here',
                  [seenCrumb, k, Fmt(px), Fmt(py), Fmt(e.Shape.Points[k].X),
                   Fmt(e.Shape.Points[k].Y)]));
                Break;
              end;
            end;
          end
          else if (kind = 'crumbText') and (seenCrumbText > 0)
            and (tx = lastTx) and (ty = lastTy) then
          begin
            { the next line of the same crumb's words }
            e := lst.Element(crumbCaps[seenCrumbText - 1]);
            txt := ex.Get('text', '');
            Inc(FCompared);
            if Pos(#10 + txt, e.Caption.Text) = 0 then
              Miss(Format('crumb text line "%s" upstream, "%s" here', [txt, e.Caption.Text]));
          end
          else if kind = 'crumbText' then
          begin
            lastTx := tx;
            lastTy := ty;
            Inc(FCompared);
            if seenCrumbText > High(crumbCaps) then
            begin
              Miss('crumb text "' + ex.Get('text', '') + '" upstream, none here');
              Inc(seenCrumbText);
              Continue;
            end;
            e := lst.Element(crumbCaps[seenCrumbText]);
            Inc(seenCrumbText);
            Inc(FCompared, 3);
            if Copy(e.Caption.Text, 1, Pos(#10, e.Caption.Text + #10) - 1) <> ex.Get('text', '') then
              Miss(Format('crumb text "%s" upstream, "%s" here', [ex.Get('text', ''),
                e.Caption.Text]));
            if not (Same(e.Caption.X, tx) and Same(e.Caption.Y, ty)) then
              Miss(Format('crumb text "%s" at (%s, %s) upstream, (%s, %s) here',
                [ex.Get('text', ''), Fmt(tx), Fmt(ty), Fmt(e.Caption.X), Fmt(e.Caption.Y)]));
            if e.Z2 <> ex.Integers['z2'] then
              Miss(Format('crumb text z2 %d upstream, %d here', [ex.Integers['z2'], e.Z2]));
          end;
        end;
        Inc(FCompared, 2);
        if seenCrumb <> Length(crumbEls) then
          Miss(Format('%d crumbs upstream, %d here', [seenCrumb, Length(crumbEls)]));
        if seenCrumbText <> Length(crumbCaps) then
          Miss(Format('%d crumb texts upstream, %d here', [seenCrumbText, Length(crumbCaps)]));
        { nothing drawn here that upstream does not draw, and the labels }
        for row := 0 to n - 1 do
        begin
          w_ := Format('row %d (%s)', [row, rows.Objects[row].Get('name', '')]);
          { the rects upstream counted above; extra ones here }
          want := 0;
          for j := 0 to elems.Count - 1 do
            if (elems.Objects[j].Get('row', -1) = row)
              and ((elems.Objects[j].Get('kind', '') = 'bg')
                or (elems.Objects[j].Get('kind', '') = 'content')) then Inc(want);
          got := Ord(bgAt[row] >= 0) + Ord(ctAt[row] >= 0);
          Inc(FCompared);
          if got > want then Miss(Format('%s: %d rects upstream, %d here', [w_, want, got]));
          { a label: its words joined; all-empty lines draw nothing here }
          txt := StringReplace(lblText[row], #10, '', [rfReplaceAll]);
          if hasLbl[row] and (txt <> '') then wantLbl := 1 else wantLbl := 0;
          if sized then
          begin
            { the words hang on the size; the anchor does not }
            Inc(FSkippedWords);
            if (capAt[row] < 0) or (wantLbl = 0) then Continue;
            e := lst.Element(capAt[row]);
            Inc(FCompared, 2);
            if not (Same(e.Caption.X, lblX[row]) and Same(e.Caption.Y, lblY[row])) then
              Miss(Format('%s: label at (%s, %s) upstream, (%s, %s) here', [w_,
                Fmt(lblX[row]), Fmt(lblY[row]), Fmt(e.Caption.X), Fmt(e.Caption.Y)]));
            if e.Z2 <> lblZ2[row] then
              Miss(Format('%s: label z2 %d upstream, %d here', [w_, lblZ2[row], e.Z2]));
            Continue;
          end;
          Inc(FCompared);
          if wantLbl <> Ord(capAt[row] >= 0) then
          begin
            if wantLbl = 1 then Miss(Format('%s: label "%s" upstream, none here',
              [w_, lblText[row]]))
            else Miss(Format('%s: no label upstream, "%s" here', [w_,
              lst.Element(capAt[row]).Caption.Text]));
            Continue;
          end;
          if wantLbl = 0 then Continue;
          Inc(FLabels);
          e := lst.Element(capAt[row]);
          Inc(FCompared, 3);
          if e.Caption.Text <> lblText[row] then
            Miss(Format('%s: label "%s" upstream, "%s" here', [w_, lblText[row],
              e.Caption.Text]));
          if not (Same(e.Caption.X, lblX[row]) and Same(e.Caption.Y, lblY[row])) then
            Miss(Format('%s: label at (%s, %s) upstream, (%s, %s) here', [w_,
              Fmt(lblX[row]), Fmt(lblY[row]), Fmt(e.Caption.X), Fmt(e.Caption.Y)]));
          if e.Z2 <> lblZ2[row] then
            Miss(Format('%s: label z2 %d upstream, %d here', [w_, lblZ2[row], e.Z2]));
        end;
      end;
    finally
      opt.Free;
    end;
  end;
end;

procedure TAdvChartTreemapOracleTest.TestTheTreemapAsUpstreamDrawsIt;
begin
  RunCases(False);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d rects, %d labels, %d crumbs (%d white grounds passed over)',
    [FRects, FLabels, FCrumbs, FSkipped]),
    (FRects >= 5000) and (FLabels >= 1000) and (FCrumbs >= 300)
    and (FSkippedWords < FLabels div 5));
end;

procedure TAdvChartTreemapOracleTest.TestTheGalleryTreemapAsUpstream;
begin
  RunCases(True);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d rects, %d labels, %d crumbs',
    [FRects, FLabels, FCrumbs]), (FRects = 10) and (FLabels = 3) and (FCrumbs = 4));
end;

initialization
  RegisterTest(TAdvChartTreemapOracleTest);
end.
