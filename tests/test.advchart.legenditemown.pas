unit test.advchart.legenditemown;
{$mode objfpc}{$H+}
{ WHAT A LEGEND ITEM READS OF ITS OWN, held to ECharts 6.1. [R5-F, spec 243]

  tools/advchart-oracle/legend-item-own.js runs the real dist: legends whose
  symbolRotate (the legend's, an item's, 'inherit' to the series'), whose
  items' symbolKeepAspect and whose items' textStyle (rich styles over the
  legend's, a box) are written; each item group's hit rect (its bounding
  rect, which the box layout lays out), its icon paths (where they are) and
  its text's painted spans.

  The control renders each option; legend 0's layout and its elements are
  compared item by item. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StyleModel, tyControls.FontUnits,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart.Legend,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLioProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartLegendItemOwnOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLioProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FItems, FRuns: Integer;
    FReport, FName: string;
    procedure NewChart;
    procedure Miss(const AWhat: string);
    procedure Near(const AWhat: string; AGot: Double; const AHex: string);
    procedure CheckCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLegendItemsAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TLioProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLioProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLioProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

procedure ParseFont(const AFont: string; out AWeight: Integer; out ASize: Double);
var
  parts: TStringList;
  i: Integer;
  s, w: string;
begin
  AWeight := 400;
  ASize := 0;
  parts := TStringList.Create;
  try
    parts.Delimiter := ' ';
    parts.StrictDelimiter := True;
    parts.DelimitedText := AFont;
    for i := 0 to parts.Count - 1 do
    begin
      s := parts[i];
      if (Length(s) > 2) and (Copy(s, Length(s) - 1, 2) = 'px') then
      begin
        ASize := StrToFloat(Copy(s, 1, Length(s) - 2), DefaultFormatSettings);
        if i > 0 then
        begin
          w := parts[i - 1];
          if w = 'bold' then AWeight := 700
          else if w = 'normal' then AWeight := 400
          else AWeight := StrToIntDef(w, 400);
        end;
        Exit;
      end;
    end;
  finally
    parts.Free;
  end;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-legend-item-own.json';
end;

procedure TAdvChartLegendItemOwnOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FItems := 0;
  FRuns := 0;
  FReport := '';
end;

procedure TAdvChartLegendItemOwnOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TLioProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartLegendItemOwnOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartLegendItemOwnOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLegendItemOwnOracleTest.Near(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameValue(AGot, FromHex(AHex), 1e-9) then
    Miss(Format('%s %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartLegendItemOwnOracleTest.CheckCase(ACase: TJSONObject);
var
  items, icons, runs, hit: TJSONArray;
  it, ic, tx: TJSONObject;
  i, j, k, idx, first, last, n, w, nIcon: Integer;
  lay: TTyLegendLayout;
  l: TTyPaintList;
  pe: PTyChartElement;
  b: TTyRectF;
  r: TJSONArray;
  sz: Double;
  texts: array of string;
  sizes: array of Double;
  weights: array of Integer;
  fills: array of TTyChartColor;
  c: TTyChartColor;
  wantCx, wantCy, rot, sn, cs, dx, dy, px, py: Double;
  found: Boolean;
begin
  NewChart;
  FChart.Option := ACase.Objects['option'].AsJSON;
  AssertEquals(ACase.Strings['id'] + ': the option parses', '', FChart.OptionError);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  lay := FChart.LegendLayout(0);
  l := FChart.List;
  items := ACase.Arrays['items'];
  for i := 0 to items.Count - 1 do
  begin
    it := items.Objects[i];
    FName := Format('%s %s', [ACase.Strings['id'], it.Strings['name']]);
    idx := -1;
    for k := 0 to High(lay.Items) do
      if lay.Items[k].Name = it.Strings['name'] then idx := k;
    Inc(FCompared);
    if idx < 0 then
    begin
      Miss('no such item');
      Continue;
    end;
    Inc(FItems);
    { THE GROUP'S RECT: the hit rect, which the box layout placed }
    hit := it.Arrays['hit'];
    b := lay.Items[idx].Bounds;
    Near('hit x', b.Left, hit.Strings[0]);
    Near('hit y', b.Top, hit.Strings[1]);
    Near('hit w', b.Right - b.Left, hit.Strings[2]);
    Near('hit h', b.Bottom - b.Top, hit.Strings[3]);
    { the item's run of elements: after its hit rect, to the next one }
    first := -1;
    last := l.Count - 1;
    for k := 0 to l.Count - 1 do
    begin
      pe := l.Ref(k);
      if pe^.Datum.Kind <> ctkLegend then Continue;
      if first >= 0 then
      begin
        last := k - 1;
        Break;
      end;
      if pe^.Datum.DataIndex = idx then first := k + 1;
    end;
    Inc(FCompared);
    if first < 0 then
    begin
      Miss('no hit rect');
      Continue;
    end;
    { THE ICONS: as many paths, each where upstream's is (its centre; a
      turned one's box is its local rect's through the turn) }
    icons := it.Arrays['icons'];
    nIcon := 0;
    for k := first to last do
      if (l.Ref(k)^.Caption.Text = '') and (l.Ref(k)^.Caption.FontSizeLogical = 0) then
      begin
        if nIcon < icons.Count then
        begin
          ic := icons.Objects[nIcon];
          r := ic.Arrays['rect'];
          b := TyShapeBounds(l.Ref(k)^.Shape);
          wantCx := FromHex(r.Strings[0]) + FromHex(r.Strings[2]) / 2;
          wantCy := FromHex(r.Strings[1]) + FromHex(r.Strings[3]) / 2;
          { A TURNED POLYGON: upstream's rect is its local rect through the
            turn, centred on the turn's origin; the points turned back by the
            angle about that centre are the local shape, whose box is centred
            there too }
          rot := FromHex(ic.Strings['rotation']);
          if (rot <> 0) and (Length(l.Ref(k)^.Shape.Points) > 0) then
          begin
            sn := Sin(rot);
            cs := Cos(rot);
            for j := 0 to High(l.Ref(k)^.Shape.Points) do
            begin
              dx := l.Ref(k)^.Shape.Points[j].X - wantCx;
              dy := l.Ref(k)^.Shape.Points[j].Y - wantCy;
              px := wantCx + dx * cs - dy * sn;
              py := wantCy + dx * sn + dy * cs;
              if j = 0 then b := TyRectF(px, py, px, py)
              else b := TyRectF(Min(b.Left, px), Min(b.Top, py), Max(b.Right, px), Max(b.Bottom, py));
            end;
          end;
          Inc(FCompared, 2);
          if not SameValue((b.Left + b.Right) / 2, wantCx, 1e-6)
            or not SameValue((b.Top + b.Bottom) / 2, wantCy, 1e-6) then
            Miss(Format('icon %d centre (%s, %s) upstream, (%s, %s) here', [nIcon,
              Fmt(wantCx), Fmt(wantCy), Fmt((b.Left + b.Right) / 2), Fmt((b.Top + b.Bottom) / 2)]));
        end;
        Inc(nIcon);
      end;
    Inc(FCompared);
    if nIcon <> icons.Count then
      Miss(Format('%d icon paths upstream, %d here', [icons.Count, nIcon]));
    { THE WORDS: the spans, their fonts and inks }
    tx := it.Objects['text'];
    runs := tx.Arrays['runs'];
    found := False;
    for k := first to last do
    begin
      pe := l.Ref(k);
      if pe^.Caption.Text = '' then Continue;
      found := True;
      texts := nil;
      sizes := nil;
      weights := nil;
      fills := nil;
      if Length(pe^.Caption.RtPieces) = 0 then
      begin
        SetLength(texts, 1);
        SetLength(sizes, 1);
        SetLength(weights, 1);
        SetLength(fills, 1);
        texts[0] := pe^.Caption.Text;
        sizes[0] := TyFontPxOf(pe^.Caption.FontSizeLogical);
        weights[0] := pe^.Caption.FontWeight and TyChartFontWeightMask;
        fills[0] := pe^.Caption.Colour;
      end
      else
        for j := 0 to High(pe^.Caption.RtPieces) do
          if pe^.Caption.RtPieces[j].Kind = rpkText then
          begin
            n := Length(texts);
            SetLength(texts, n + 1);
            SetLength(sizes, n + 1);
            SetLength(weights, n + 1);
            SetLength(fills, n + 1);
            texts[n] := pe^.Caption.RtPieces[j].Text;
            sizes[n] := pe^.Caption.RtPieces[j].FontSizePx;
            weights[n] := pe^.Caption.RtPieces[j].FontWeight and TyChartFontWeightMask;
            fills[n] := pe^.Caption.RtPieces[j].Fill;
          end;
      Inc(FCompared);
      if Length(texts) <> runs.Count then
      begin
        Miss(Format('%d spans upstream, %d here', [runs.Count, Length(texts)]));
        Break;
      end;
      for j := 0 to runs.Count - 1 do
      begin
        Inc(FRuns);
        ParseFont(runs.Objects[j].Strings['font'], w, sz);
        if weights[j] = 0 then weights[j] := 400;
        Inc(FCompared, 3);
        if texts[j] <> runs.Objects[j].Strings['text'] then
          Miss(Format('span %d "%s" upstream, "%s" here', [j, runs.Objects[j].Strings['text'], texts[j]]));
        if not SameValue(sizes[j], sz, 1e-9) or (weights[j] <> w) then
          Miss(Format('span %d font %s upstream, %spx %d here', [j, runs.Objects[j].Strings['font'],
            Fmt(sizes[j]), weights[j]]));
        { an ink the option wrote (the skin's default ink aside) }
        if (runs.Objects[j].Find('fill') <> nil) and (runs.Objects[j].Find('fill').JSONType = jtString)
          and (runs.Objects[j].Strings['fill'] <> '#54555a')
          and TyTryParseChartColor(runs.Objects[j].Strings['fill'], c) and (c <> fills[j]) then
          Miss(Format('span %d fill %s upstream, $%.8x here', [j, runs.Objects[j].Strings['fill'], fills[j]]));
      end;
      Break;
    end;
    Inc(FCompared);
    if not found then Miss('no words');
  end;
end;

procedure TAdvChartLegendItemOwnOracleTest.TestTheLegendItemsAsUpstream;
var
  cases: TJSONArray;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
    CheckCase(cases.Objects[c]);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('items compared (%d)', [FItems]), FItems >= 20);
  AssertTrue(Format('spans compared (%d)', [FRuns]), FRuns >= 20);
end;

initialization
  RegisterTest(TAdvChartLegendItemOwnOracleTest);
end.
