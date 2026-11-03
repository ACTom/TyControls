unit test.advchart.reachstyles;
{$mode objfpc}{$H+}
{ WHAT REACHES THE AXIS POINTER'S LINE, THE COMPONENT BOXES, A CANDLESTICK
  AND A BAR'S CORNERS, held to upstream. [R7-X]

  - The axis pointer draws with getLineStyle (a line) or getAreaStyle (a
    band) of its model: the axis' own block key by key, over the tooltip's
    (its lineStyle -- crossStyle on a cross' other arm -- taken whole from
    the first tooltip level that has one), over the global axisPointer
    component, over the option root.
  - A title's, a legend's and a toolbox's box take getItemStyle(['color',
    'opacity']) of the component, climbing to the root's top-level keys
    where the component's defaults hold none; a continuous visualMap's
    itemWidth / itemHeight, a visualMap's text, a legend's icon and
    formatter climb the same way.
  - A candlestick's candlestickVisual reads getItemStyle() of the item
    model: the item's, the series' and the root's top-level keys.
  - A bar reads its corners per item.

  tests/fixtures/advchart-reach-styles.json, from the real ECharts 6.1 build
  (tools/advchart-oracle/reach-styles.js): per case settled (its action
  dispatched and settled), the sets root-styles.js records -- pens, looks,
  fills, shapes -- of the part: the series' views (''), the axes' pointer
  groups ('pointer', each entry prefixed with its axis), a component's box
  ('title', 'legend', 'toolbox', 'visualMap'); `texts`, `icons` and `vm`
  where a case asks.

  TestTheReachAsUpstream: the same off the port -- the series' elements of
  its frame (no text, no label line), the pointer shapes and the title
  boxes the last paint drew (PointerShapesDrawn, TitleFramesDrawn), a
  component's box element (z2 -1, no datum) of the frame. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart.Legend, tyControls.AdvanceChart.VisualMapView,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax, test.advchart.rootstyles;
type
  TReachProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
    function PtrShapes: TTyOverlayShapeArray;
    function TitleFrames: TTyOverlayShapeArray;
  end;

  TAdvChartReachStylesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FChart: TReachProbe;
    procedure Draw;
    procedure Settle(AStart: Double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheReachAsUpstream;
  end;

implementation

const
  cW = 400;
  cH = 300;
  T0 = 1700000000000.0;

function TReachProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TReachProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TReachProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function TReachProbe.PtrShapes: TTyOverlayShapeArray;
begin
  Result := PointerShapesDrawn;
end;

function TReachProbe.TitleFrames: TTyOverlayShapeArray;
begin
  Result := TitleFramesDrawn;
end;

function LoadJson(const AName: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartReachStylesOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FMeasure := LoadJson('advchart-text-style.json');
end;

procedure TAdvChartReachStylesOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartReachStylesOracleTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartReachStylesOracleTest.Settle(AStart: Double);
var t: Integer;
begin
  t := 16;
  while t <= 5000 do
  begin
    FChart.AnimNow := AStart + t;
    FChart.AnimTick(AStart + t);
    Inc(t, 250);
  end;
  Draw;
end;

procedure TAdvChartReachStylesOracleTest.TestTheReachAsUpstream;
var
  fix: TJSONData;
  cs: TJSONArray;
  c, vmRec: TJSONObject;
  i, k, nBad, nCases, nPtr, nBox: Integer;
  lst: TTyPaintList;
  el: TTyChartElement;
  pens, shapes, fills, looks, texts: TStringList;
  want, have, id, bad, part, s, pre: string;
  arr: TJSONArray;
  noColour: Boolean;
  ov: TTyOverlayShapeArray;
  opt: TTyChartOption;
  vs: TTyVmViewSpec;
  ls: TTyLegendSpec;

  function SetText(AList: TStringList): string;
  var j: Integer;
  begin
    Result := '';
    for j := 0 to AList.Count - 1 do Result := Result + ' ' + AList[j];
  end;

  function ArrText(AArr: TJSONArray; ASkipClear: Boolean): string;
  var j: Integer;
  begin
    Result := '';
    for j := 0 to AArr.Count - 1 do
      if not (ASkipClear and (Copy(AArr.Strings[j], Length(AArr.Strings[j]) - 1, 2) = '00')
        and (Pos('#', AArr.Strings[j]) > 0)) then
        Result := Result + ' ' + AArr.Strings[j];
  end;

  procedure Compare(const AKey: string; AHere: TStringList; ASkipClear: Boolean);
  begin
    arr := c.Find(AKey) as TJSONArray;
    if arr = nil then Exit;
    want := want + ' ' + AKey + ArrText(arr, ASkipClear);
    have := have + ' ' + AKey + SetText(AHere);
  end;

  { one element's records, prefixed (a pointer's axis) }
  procedure Take(const AEl: TTyChartElement; const APre: string);
  var p: string;
  begin
    if APre <> '' then p := APre + '|' else p := '';
    looks.Add(p + LooksOf(AEl));
    s := ShapeText(AEl);
    if s <> '' then shapes.Add(p + s);
    s := FillText(AEl);
    if s <> '' then fills.Add(p + s);
    if not (AEl.Style.StrokeWidthLogical > 0) then Exit;
    if ((AEl.Style.StrokeColor shr 24) = 0) and (AEl.Style.StrokeGradient.Kind = cgkNone) then Exit;
    s := PenOf(AEl);
    if noColour then s := Copy(s, Pos('|', s) + 1, MaxInt);
    pens.Add(p + s);
  end;

begin
  fix := LoadJson('advchart-reach-styles.json');
  pens := NewSet(dupIgnore);
  shapes := NewSet(dupAccept);
  fills := NewSet(dupIgnore);
  looks := NewSet(dupIgnore);
  texts := NewSet(dupIgnore);
  nBad := 0;
  nCases := 0;
  nPtr := 0;
  nBox := 0;
  bad := '';
  opt := TTyChartOption.Create;
  try
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      part := c.Strings['part'];
      noColour := c.Get('nocolour', False);
      FreeAndNil(FChart);
      FChart := TReachProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
        TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
        TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
      FChart.AnimationMode := camAlways;
      FChart.AnimNow := T0;
      FChart.SetBounds(0, 0, cW, cH);
      FChart.Option := c.Objects['option'].AsJSON;
      AssertEquals(id + ' parses', '', FChart.OptionError);
      Draw;
      Settle(T0);
      if c.Find('action') is TJSONObject then
      begin
        FChart.AnimNow := T0 + 10000;
        FChart.DispatchAction(c.Objects['action'].AsJSON);
        Settle(T0 + 10000);
      end;
      lst := FChart.Frame;
      pens.Clear;
      shapes.Clear;
      fills.Clear;
      looks.Clear;
      texts.Clear;
      shapes.Duplicates := dupAccept;
      if part = 'pointer' then
      begin
        Inc(nPtr);
        ov := FChart.PtrShapes;
        for k := 0 to High(ov) do Take(ov[k].El, ov[k].Owner);
      end
      else if part = 'title' then
      begin
        Inc(nBox);
        ov := FChart.TitleFrames;
        for k := 0 to High(ov) do Take(ov[k].El, '');
      end
      else
      begin
        { a box drawn as a fill and a pen of the same rect is one rect }
        if part <> '' then
        begin
          Inc(nBox);
          shapes.Duplicates := dupIgnore;
        end;
        for k := 0 to lst.Count - 1 do
        begin
          el := lst.Element(k);
          if GetEnvironmentVariable('TY_REACH_DUMP') = id then
            WriteLn(id + ' el ' + IntToStr(k) + ' role ' + IntToStr(Ord(el.Anim.Role)) + ' kind '
              + IntToStr(Ord(el.Datum.Kind)) + ' s ' + IntToStr(el.Datum.SeriesIndex) + ' i '
              + IntToStr(el.Datum.DataIndex) + ' z2 ' + IntToStr(el.Z2) + ' shape '
              + IntToStr(Ord(el.Shape.Kind)) + ' pen ' + PenOf(el) + ' fill ' + FillText(el)
              + ' looks ' + LooksOf(el) + ' text "' + el.Caption.Text + '"');
          if el.Ignore then Continue;
          if el.Caption.Text <> '' then texts.Add(el.Caption.Text);
          if el.IsGuide or (el.Anim.Role in [carLabel, carMarkLineLabel,
            carMarkPointLabel, carEndLabel, carLinesLabel, carGraphEdgeLabel]) then Continue;
          if el.Caption.FontSizeLogical > 0 then Continue;
          if part = '' then
          begin
            if not ((el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex >= 0)) then Continue;
          end
          else
          begin
            { the component's box: no datum, under everything of its own }
            if (el.Z2 <> -1) or (el.Datum.SeriesIndex >= 0)
              or not (el.Shape.Kind in [cskRect, cskRoundRect]) then Continue;
          end;
          Take(el, '');
        end;
      end;
      want := '';
      arr := c.Arrays['pens'];
      for k := 0 to arr.Count - 1 do
        want := want + ' ' + arr.Strings[k];
      have := SetText(pens);
      Compare('shapes', shapes, False);
      Compare('fills', fills, True);
      Compare('looks', looks, False);
      { the texts upstream draws are among the port's }
      arr := c.Find('texts') as TJSONArray;
      if arr <> nil then
        for k := 0 to arr.Count - 1 do
          if texts.IndexOf(arr.Strings[k]) < 0 then
          begin
            want := want + ' text ' + arr.Strings[k];
            have := have + ' text (none)';
          end;
      { a visualMap's item size and text, a legend's icon, as the model reads them }
      if (c.Find('vm') is TJSONObject) or (c.Find('icons') is TJSONArray) then
      begin
        AssertTrue(id + ' parses (model)', opt.SetOptionText(c.Objects['option'].AsJSON));
        if c.Find('vm') is TJSONObject then
        begin
          vmRec := c.Objects['vm'];
          vs := TyVisualMapViewSpecOf(opt, 0);
          want := want + ' vm ' + FloatToStr(vmRec.Arrays['itemSize'].Floats[0]) + 'x'
            + FloatToStr(vmRec.Arrays['itemSize'].Floats[1]);
          have := have + ' vm ' + FloatToStr(vs.ItemW) + 'x' + FloatToStr(vs.ItemH);
          if vmRec.Find('text') is TJSONArray then
          begin
            want := want + ' text ' + vmRec.Arrays['text'].Strings[0] + ',' + vmRec.Arrays['text'].Strings[1];
            have := have + ' text ' + vs.Text[0] + ',' + vs.Text[1];
          end;
        end;
        if c.Find('icons') is TJSONArray then
        begin
          ls := TyLegendSpecOf(opt, 0);
          want := want + ' icon ' + c.Arrays['icons'].Strings[0];
          have := have + ' icon ' + ls.Icon;
        end;
      end;
      Inc(nCases);
      if have <> want then
      begin
        Inc(nBad);
        bad := bad + LineEnding + Format('  %s: %s here, upstream %s', [id, Trim(have),
          Trim(want)]);
      end;
    end;
  finally
    opt.Free;
    pens.Free;
    shapes.Free;
    fills.Free;
    looks.Free;
    texts.Free;
    fix.Free;
  end;
  AssertTrue('cases', nCases >= 40);
  AssertTrue('pointer cases', nPtr >= 15);
  AssertTrue('box cases', nBox >= 8);
  AssertTrue(Format('%d of %d differ from upstream:%s', [nBad, nCases, bad]), nBad = 0);
end;

initialization
  RegisterTest(TAdvChartReachStylesOracleTest);
end.
