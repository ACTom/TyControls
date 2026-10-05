unit test.advchart.insidelabel;
{$mode objfpc}{$H+}
{ A label's ink and its halo -- held to upstream byte for byte.

  tools/advchart-oracle/inside-label.js renders one labelled item per chart in
  the real ECharts 6.1 build and records the label's ink, its stroke colour
  and width, and its opacity, as zrender holds them: over a light fill, a mid
  one, a dark one, a gradient, no fill, a transparent pictorial target; inside
  and outside; on a light ground and a dark one; with a literal colour,
  `inherit`, `textBorderColor`, `textBorderWidth`; and under a hover.

  zrender's rule: a label is inside only over a host that HAS a fill. Inside,
  the ink is one of three by the fill's luminance (above a half, above a
  fifth), and the halo is the host's own fill -- only when the band is the
  one that reads against the ground, and never over a gradient. Outside, the
  ink is the theme's and the halo is the ground. Two pixels wide.

  TWO LEVELS. Every record is checked at the chooser, with the option read by
  the same reader the control uses -- dark grounds included. The light-ground
  ones are then checked again through a real render, on the caption the
  control actually built. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     fpjson, jsonparser, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Labels,
     tyControls.AdvChart.LabelOpt, tyControls.AdvChart.Color,
     tyControls.AdvanceChart;
type
  TInsideLabelProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartInsideLabelOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameInk(const AWhat: string; AGot: TTyChartColor; ABytes: TJSONData);
    procedure SameStroke(const AWhat: string; AColour: TTyChartColor;
      AWidth: Double; ARecord: TJSONObject);
    function BaseSpec(ACase: TJSONObject): TTyLabelSpec;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryInkAndHaloIsUpstreams;
    procedure TestEveryLightLabelIsDrawnSo;
    procedure TestTheHaloIsUnderTheGlyphsAndOutsideThem;
    procedure TestABorderOfNoneOrABackgroundTakesTheHaloAway;
    procedure TestAHoveredBarKeepsItsInsideLabelOnTop;
  end;

  TInsideLabelHoverProbe = class(TInsideLabelProbe)
  public
    procedure Hover(AX, AY: Integer);
  end;

implementation

procedure TInsideLabelProbe.Render(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TInsideLabelProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TInsideLabelHoverProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-inside-label.json';
end;

function ColourOf(ABytes: TJSONData): TTyChartColor;
var a: TJSONArray;
begin
  a := TJSONArray(ABytes);
  Result := TTyChartColor((Cardinal(a.Integers[3]) shl 24)
    or (Cardinal(a.Integers[0]) shl 16) or (Cardinal(a.Integers[1]) shl 8)
    or Cardinal(a.Integers[2]));
end;

function HexStr(AColour: TTyChartColor): string;
begin
  Result := '#' + IntToHex(AColour, 8);
end;

procedure TAdvChartInsideLabelOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
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
  FReport := '';
end;

procedure TAdvChartInsideLabelOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartInsideLabelOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartInsideLabelOracleTest.SameInk(const AWhat: string;
  AGot: TTyChartColor; ABytes: TJSONData);
var want: TTyChartColor;
begin
  Inc(FCompared);
  want := ColourOf(ABytes);
  if AGot <> want then
    Miss(Format('%s is %s upstream, %s here', [AWhat, HexStr(want), HexStr(AGot)]));
end;

{ No stroke upstream -- none, or a transparent one -- is none here too. }
procedure TAdvChartInsideLabelOracleTest.SameStroke(const AWhat: string;
  AColour: TTyChartColor; AWidth: Double; ARecord: TJSONObject);
var none, noneHere: Boolean; want: TTyChartColor;
begin
  Inc(FCompared);
  { A stroke of no width, or a transparent one, draws nothing. }
  none := not (ARecord.Find('strokeBytes') is TJSONArray);
  if not none then
    none := ((ColourOf(ARecord.Arrays['strokeBytes']) shr 24) = 0)
      or (ARecord.Floats['lineWidth'] <= 0);
  noneHere := (AWidth <= 0) or ((AColour shr 24) = 0);
  if none or noneHere then
  begin
    if none <> noneHere then
      Miss(Format('%s: a halo %s upstream, %s here', [AWhat,
        BoolToStr(not none, 'present', 'absent'),
        BoolToStr(not noneHere, 'present', 'absent')]));
    Exit;
  end;
  want := ColourOf(ARecord.Arrays['strokeBytes']);
  if AColour <> want then
    Miss(Format('%s: halo %s upstream, %s here', [AWhat, HexStr(want),
      HexStr(AColour)]));
  Inc(FCompared);
  if AWidth <> ARecord.Floats['lineWidth'] then
    Miss(Format('%s: halo %s px upstream, %s here', [AWhat,
      FloatToStr(ARecord.Floats['lineWidth']), FloatToStr(AWidth)]));
end;

function SeriesOf(ACase: TJSONObject): TJSONObject;
begin
  Result := TJSONObject(ACase.Objects['option'].Arrays['series'].Items[0]);
end;

function TAdvChartInsideLabelOracleTest.BaseSpec(ACase: TJSONObject): TTyLabelSpec;
var inks: TJSONObject; s: string; c: TTyChartColor; i: Integer;
    ser, lbl: TJSONObject;
begin
  inks := TJSONObject(FRoot).Objects['inks'];
  Result := TyLabelSpecNone;
  Result.AutoColour := True;
  for i := 0 to 2 do
  begin
    TyTryParseChartColor(inks.Arrays['band'].Strings[i], c);
    Result.InsideColour[i] := c;
  end;
  if ACase.Booleans['isDark'] then s := inks.Strings['outsideDark']
  else s := inks.Strings['outsideLight'];
  TyTryParseChartColor(s, c);
  Result.OutsideColour := c;
  Result.Ground := ColourOf(ACase.Arrays['ground']);
  Result.GroundDark := ACase.Booleans['isDark'];
  ser := SeriesOf(ACase);
  lbl := nil;
  if ser.Find('label') is TJSONObject then lbl := ser.Objects['label'];
  TyLabelReadInk(lbl, ser, Result);
  if ser.Strings['type'] = 'funnel' then Result.FunnelInherit := True;
end;

procedure TAdvChartInsideLabelOracleTest.TestEveryInkAndHaloIsUpstreams;
var
  cases, labels: TJSONArray;
  cs, rec, normal: TJSONObject;
  c, k, j: Integer;
  spec: TTyLabelSpec;
  host: TTyChartColor;
  hasFill, grad: Boolean;
  ink, stroke: TTyChartColor;
  w: Double;
  cap: TTyElementCaption;
  fillName: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := TJSONObject(cases.Items[c]);
    if cs.Booleans['documentary'] or cs.Booleans['deferred'] then Continue;
    FName := cs.Strings['id'];
    spec := BaseSpec(cs);
    labels := cs.Arrays['labels'];
    for k := 0 to labels.Count - 1 do
    begin
      rec := TJSONObject(labels.Items[k]);
      if rec.Strings['state'] = 'normal' then
      begin
        fillName := rec.Strings['hostFill'];
        hasFill := fillName <> 'none';
        grad := fillName = 'gradient';
        host := 0;
        if rec.Find('hostFillBytes') is TJSONArray then
          host := ColourOf(rec.Arrays['hostFillBytes']);
        TyLabelInk(spec, host, hasFill, grad, rec.Booleans['inside'], ink,
          stroke, w);
        SameInk(rec.Strings['text'] + ' ink', ink, rec.Arrays['fillBytes']);
        SameStroke(rec.Strings['text'], stroke, w, rec);
        Continue;
      end;
      { THE HOVER: worked out from the NORMAL fill, the way the caption is
        stamped. A hover that moves the label is not ported. }
      normal := nil;
      for j := 0 to labels.Count - 1 do
        if (TJSONObject(labels.Items[j]).Strings['state'] = 'normal')
          and (TJSONObject(labels.Items[j]).Strings['text'] = rec.Strings['text']) then
          normal := TJSONObject(labels.Items[j]);
      if normal = nil then Continue;
      if normal.Booleans['inside'] <> rec.Booleans['inside'] then Continue;
      fillName := normal.Strings['hostFill'];
      hasFill := fillName <> 'none';
      grad := fillName = 'gradient';
      host := 0;
      if normal.Find('hostFillBytes') is TJSONArray then
        host := ColourOf(normal.Arrays['hostFillBytes']);
      cap := Default(TTyElementCaption);
      TyLabelStampEmphasis(spec, host, hasFill, grad, normal.Booleans['inside'], cap);
      SameInk(rec.Strings['text'] + ' hovered ink', cap.EmphColour,
        rec.Arrays['fillBytes']);
      SameStroke(rec.Strings['text'] + ' hovered', cap.EmphStrokeColour,
        cap.EmphStrokeWidthLogical, rec);
    end;
  end;
  AssertTrue(Format('a great deal was compared (%d)', [FCompared]),
    FCompared > 120);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

procedure TAdvChartInsideLabelOracleTest.TestEveryLightLabelIsDrawnSo;
var
  form: TForm;
  ctl: TTyStyleController;
  chart: TInsideLabelProbe;
  bmp: TBGRABitmap;
  cases, labels: TJSONArray;
  cs, rec: TJSONObject;
  c, k, i, found, ran: Integer;
  el: TTyChartElement;
  role: string;
  rec2: TJSONObject;
begin
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  ran := 0;
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    chart := TInsideLabelProbe.Create(form);
    chart.Parent := form;
    chart.Controller := ctl;
    chart.SetBounds(0, 0, 400, 300);
    cases := TJSONObject(FRoot).Arrays['cases'];
    for c := 0 to cases.Count - 1 do
    begin
      cs := TJSONObject(cases.Items[c]);
      if cs.Booleans['documentary'] or cs.Booleans['deferred']
        or cs.Booleans['isDark'] then Continue;
      FName := cs.Strings['id'];
      chart.Option := '';
      chart.Option := cs.Objects['option'].AsJSON;
      bmp.Fill(BGRA(255, 255, 255, 255));
      chart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
      Inc(ran);
      labels := cs.Arrays['labels'];
      for k := 0 to labels.Count - 1 do
      begin
        rec := TJSONObject(labels.Items[k]);
        found := -1;
        for i := 0 to chart.List.Count - 1 do
        begin
          el := chart.List.Element(i);
          if (el.Caption.Text = rec.Strings['text'])
            and (el.Caption.FontSizeLogical > 0) then found := i;
        end;
        Inc(FCompared);
        if found < 0 then
        begin
          Miss(rec.Strings['text'] + ' was not drawn here');
          Continue;
        end;
        el := chart.List.Element(found);
        role := rec.Strings['inkRole'];
        if rec.Strings['state'] = 'normal' then
        begin
          { THE THEME'S OWN OUTSIDE INK is the port's voice, not #333. }
          if role <> 'outside' then
            SameInk(rec.Strings['text'] + ' drawn ink', el.Caption.Colour,
              rec.Arrays['fillBytes']);
          SameStroke(rec.Strings['text'] + ' drawn', el.Caption.StrokeColour,
            el.Caption.StrokeWidthLogical, rec);
          Inc(FCompared);
          if el.Style.Alpha <> rec.Floats['opacity'] then
            Miss(Format('%s opacity %s upstream, %s here', [rec.Strings['text'],
              FloatToStr(rec.Floats['opacity']), FloatToStr(el.Style.Alpha)]));
        end
        else
        begin
          { A HOVER THAT MOVES THE LABEL (emphasis.label.position) is not
            ported: its words stay where they were. }
          if cs.Arrays['labels'].Count > 0 then
          begin
            rec2 := TJSONObject(labels.Items[0]);
            if rec2.Booleans['inside'] <> rec.Booleans['inside'] then Continue;
          end;
          Inc(FCompared);
          if not el.Caption.HasEmph then
          begin
            Miss(rec.Strings['text'] + ' has no hover ink here');
            Continue;
          end;
          if role <> 'outside' then
            SameInk(rec.Strings['text'] + ' hovered ink', el.Caption.EmphColour,
              rec.Arrays['fillBytes']);
          SameStroke(rec.Strings['text'] + ' hovered', el.Caption.EmphStrokeColour,
            el.Caption.EmphStrokeWidthLogical, rec);
        end;
      end;
    end;
  finally
    bmp.Free;
    form.Free;
    ctl.Free;
  end;
  AssertTrue(Format('the charts ran (%d)', [ran]), ran >= 40);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

procedure TAdvChartInsideLabelOracleTest.TestTheHaloIsUnderTheGlyphsAndOutsideThem;
const
  cOpt = '{animation:false, xAxis:{type:"category", data:["c"]},'
    + ' yAxis:{type:"value"}, series:[{type:"bar", data:[10],'
    + ' itemStyle:{color:"#5470c6"}, label:{show:true, position:"top",'
    + ' fontSize:30, formatter:"IIII"%s}}]}';
var
  form: TForm;
  ctl: TTyStyleController;
  chart: TInsideLabelProbe;
  bmp: TBGRABitmap;
  red, redPlain, inkHalo, inkPlain: Integer;
  el: TTyChartElement;
  box, boxPlain: TTyRectF;
  p: TBGRAPixel;

  function Caption(out ABox: TTyRectF): Boolean;
  var k: Integer;
  begin
    Result := False;
    for k := 0 to chart.List.Count - 1 do
    begin
      el := chart.List.Element(k);
      if (el.Caption.Text = 'IIII') and (el.Caption.FontSizeLogical > 0) then
      begin
        ABox := el.Shape.Bounds;
        Exit(True);
      end;
    end;
  end;

  { The label's own ink -- the theme's dark outside ink. }
  function CountInk(const ABox: TTyRectF): Integer;
  var x, y: Integer;
  begin
    Result := 0;
    for y := Floor(ABox.Top) to Ceil(ABox.Bottom) do
      for x := Floor(ABox.Left) to Ceil(ABox.Right) do
      begin
        p := bmp.GetPixel(x, y);
        if (p.red < 110) and (p.green < 110) and (p.blue < 110) then Inc(Result);
      end;
  end;

  function CountRed(const ABox: TTyRectF): Integer;
  var x, y: Integer;
  begin
    Result := 0;
    for y := Floor(ABox.Top) - 3 to Ceil(ABox.Bottom) + 3 do
      for x := Floor(ABox.Left) - 3 to Ceil(ABox.Right) + 3 do
      begin
        p := bmp.GetPixel(x, y);
        if (p.red > 200) and (p.green < 90) and (p.blue < 90) then Inc(Result);
      end;
  end;

begin
  { A LABEL OVER WHITE with a red border two pixels wide: the halo shows as
    red round the glyphs -- and only there, because nothing else on this
    chart is red. The caption's box does not grow for it. }
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    chart := TInsideLabelProbe.Create(form);
    chart.Parent := form;
    chart.Controller := ctl;
    chart.SetBounds(0, 0, 400, 300);
    chart.Option := Format(cOpt, [', textBorderColor:"#ff0000", textBorderWidth:2']);
    chart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    AssertTrue('the label is there', Caption(box));
    AssertEquals('its halo is red', Integer($FFFF0000),
      Integer(el.Caption.StrokeColour));
    red := CountRed(box);
    inkHalo := CountInk(box);
    chart.Option := Format(cOpt, ['']);
    bmp.Fill(BGRA(255, 255, 255, 255));
    chart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    AssertTrue('the label is there without one', Caption(boxPlain));
    redPlain := CountRed(boxPlain);
    inkPlain := CountInk(boxPlain);
    { THE GLYPHS ON TOP: stamped under them, the halo leaves their ink as it
      was; stamped over them it eats into every stem. }
    AssertTrue(Format('the ink is on top of its halo (%d px of %d)',
      [inkHalo, inkPlain]), (inkPlain > 60) and (inkHalo * 10 >= inkPlain * 9));
    AssertTrue(Format('the halo is drawn (%d red px)', [red]), red > 60);
    AssertEquals('and nothing is red without it', 0, redPlain);
    AssertTrue('the box does not grow for the halo',
      (box.Left = boxPlain.Left) and (box.Right = boxPlain.Right)
      and (box.Top = boxPlain.Top) and (box.Bottom = boxPlain.Bottom));
  finally
    bmp.Free;
    form.Free;
    ctl.Free;
  end;
end;

procedure TAdvChartInsideLabelOracleTest.TestABorderOfNoneOrABackgroundTakesTheHaloAway;
var spec: TTyLabelSpec; ink, stroke: TTyChartColor; w: Double;
begin
  spec := TyLabelSpecNone;
  spec.AutoColour := True;
  spec.InsideColour[0] := $FF333333;
  spec.InsideColour[1] := $FFEEEEEE;
  spec.InsideColour[2] := $FFCCCCCC;
  spec.OutsideColour := $FF333333;
  spec.Ground := $FFFFFFFF;
  { A mid host inside on a light ground halos in its own colour... }
  TyLabelInk(spec, $FF5470C6, True, False, True, ink, stroke, w);
  AssertEquals('a halo by default', Integer($FF5470C6), Integer(stroke));
  AssertEquals(2, w, 0);
  { ...and `textBorderColor: 'none'` takes it away, width or not. }
  spec.HasBorderColour := True;
  spec.BorderColourNone := True;
  spec.HasBorderWidth := True;
  spec.BorderWidthLogical := 3;
  TyLabelInk(spec, $FF5470C6, True, False, True, ink, stroke, w);
  AssertEquals('none with a width is still none', 0, w, 0);
  { A label with its own background has no automatic halo. }
  spec.HasBorderColour := False;
  spec.BorderColourNone := False;
  spec.HasBackground := True;
  TyLabelInk(spec, $FF5470C6, True, False, True, ink, stroke, w);
  AssertEquals('a background, no halo', 0, w, 0);
  TyLabelInk(spec, $FF5470C6, True, False, False, ink, stroke, w);
  AssertEquals('nor outside', 0, w, 0);
end;

procedure TAdvChartInsideLabelOracleTest.TestAHoveredBarKeepsItsInsideLabelOnTop;
const
  cOpt = '{animation:false, xAxis:{type:"category", data:["c"]},'
    + ' yAxis:{type:"value"}, series:[{type:"bar", data:[10], barWidth:160,'
    + ' itemStyle:{color:"#5470c6"}, label:{show:true, fontSize:30,'
    + ' formatter:"IIII"}}]}';
var
  form: TForm;
  ctl: TTyStyleController;
  chart: TInsideLabelHoverProbe;
  bmp: TBGRABitmap;
  k, x, y, light, bar: Integer;
  el: TTyChartElement;
  box, host: TTyRectF;
  p: TBGRAPixel;
begin
  { THE LABEL OF A HOVERED BAR IS DRAWN AGAIN OVER THE LIFTED BAR, in the
    hover's ink. Without it the brighter copy of the bar covers the words. }
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    chart := TInsideLabelHoverProbe.Create(form);
    chart.Parent := form;
    chart.Controller := ctl;
    chart.SetBounds(0, 0, 400, 300);
    chart.Option := cOpt;
    chart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    box := TyRectF(0, 0, 0, 0);
    host := box;
    bar := -1;
    for k := 0 to chart.List.Count - 1 do
    begin
      el := chart.List.Element(k);
      if (el.Caption.Text = 'IIII') and (el.Caption.FontSizeLogical > 0) then
        box := el.Shape.Bounds
      else if (el.Datum.SeriesIndex = 0) and (el.Datum.DataIndex = 0)
        and el.Style.HasFill then
      begin
        host := el.Shape.Bounds;
        bar := k;
      end;
    end;
    AssertTrue('the bar is there', bar >= 0);
    { Over the bar, well below its label. }
    chart.Hover(Round((host.Left + host.Right) / 2), Round(host.Bottom) - 5);
    bmp.Fill(BGRA(255, 255, 255, 255));
    chart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    light := 0;
    for y := Floor(box.Top) to Ceil(box.Bottom) do
      for x := Floor(box.Left) to Ceil(box.Right) do
      begin
        p := bmp.GetPixel(x, y);
        if (p.red > 220) and (p.green > 220) and (p.blue > 220) then Inc(light);
      end;
    AssertTrue(Format('the light ink shows on the hovered bar (%d px)', [light]),
      light > 40);
  finally
    bmp.Free;
    form.Free;
    ctl.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartInsideLabelOracleTest);
end.
