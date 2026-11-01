unit test.advchart.labellayoutsize;
{$mode objfpc}{$H+}
{ labelLayout's width and height, held to ECharts 6.1 [R5-C]: the label's
  style takes them (LabelManager's LABEL_OPTION_TO_STYLE_KEYS) -- an
  overflow cuts or wraps at the width, a lineOverflow drops the lines past
  the height, a box is drawn at that size and the layout weighs it.

  tools/advchart-oracle/label-layout-size.js records every series label of
  each option after a render: hidden or not, the lines it draws, its rect
  (the bounding rect through its transform). The control renders the same
  option (zrender's SSR width table measures the words) and each label is
  compared bit for bit. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Handlers, tyControls.AdvanceChart.Measure, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Drag(AX, AY, ADX, ADY: Integer);
  end;

  TLsHandlers = class
  public
    function Widths(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
  end;

  TAdvChartLabelLayoutSizeTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLsProbe;
    FH: TLsHandlers;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FLabels, FHidden: Integer;
    FName, FReport: string;
    procedure Miss(const AWhat: string);
    procedure Near(const AWhat: string; AGot, AWant: Double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSizesAsUpstream;
    procedure TestADragAsUpstream;
  end;

implementation

function TLsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TLsProbe.Drag(AX, AY, ADX, ADY: Integer);
begin
  MouseDown(mbLeft, [ssLeft], AX, AY);
  MouseMove([ssLeft], AX + ADX, AY + ADY);
  MouseUp(mbLeft, [], AX + ADX, AY + ADY);
end;

{ label-layout-size.js' @LS_W }
function TLsHandlers.Widths(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Result := Default(TTyChartLabelLayout);
  Result.HasWidth := True;
  Result.Width := 20 + (AArgs.DataIndex mod 3) * 15;
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

procedure TAdvChartLabelLayoutSizeTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 100 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLabelLayoutSizeTest.Near(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not (Abs(AGot - AWant) <= 1e-9) then
    Miss(Format('%s: %.17g upstream, %.17g here', [AWhat, AWant, AGot]));
end;

function FindLabel(AList: TTyPaintList; ASeries, AData: Integer): Integer;
var i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Caption.LmKind > 0) and (AList.Element(i).Anim.Role <> carGuide)
      and ((AList.Element(i).Caption.LmHostPlus1 > 0) or (AList.Element(i).Caption.LmKind = 2))
      and (AList.Element(i).Caption.FontSizeLogical > 0)
      and (AList.Element(i).Datum.SeriesIndex = ASeries)
      and (AList.Element(i).Datum.DataIndex = AData) then
      Exit(i);
  Result := -1;
end;

procedure TAdvChartLabelLayoutSizeTest.TestTheSizesAsUpstream;
var
  cs, labs, tx: TJSONArray;
  c, i, k, n, li: Integer;
  cse, lb: TJSONObject;
  el: TTyChartElement;
  texts: array of string;
  b: TTyRectF;
  got, want: string;
begin
  cs := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cs.Count - 1 do
  begin
    cse := cs.Objects[c];
    FChart.Option := '{}';
    FChart.Option := cse.Objects['option'].AsJSON;
    FChart.SetBounds(0, 0, cse.Integers['W'], cse.Integers['H']);
    FBmp.SetSize(cse.Integers['W'], cse.Integers['H']);
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cse.Integers['W'], cse.Integers['H']), 96);
    labs := cse.Arrays['labels'];
    for i := 0 to labs.Count - 1 do
    begin
      lb := labs.Objects[i];
      FName := Format('%s s%d d%d', [cse.Strings['id'], lb.Integers['s'], lb.Integers['d']]);
      li := FindLabel(FChart.List, lb.Integers['s'], lb.Integers['d']);
      Inc(FCompared);
      if li < 0 then
      begin
        Miss('a label upstream, none here');
        Continue;
      end;
      el := FChart.List.Element(li);
      Inc(FLabels);
      Inc(FCompared);
      if el.Ignore <> lb.Booleans['ignore'] then
        Miss(Format('ignore %s upstream', [BoolToStr(lb.Booleans['ignore'], True)]));
      if el.Ignore then
      begin
        Inc(FHidden);
        Continue;
      end;
      { the lines it draws }
      texts := nil;
      if Length(el.Caption.RtPieces) > 0 then
      begin
        for k := 0 to High(el.Caption.RtPieces) do
          if el.Caption.RtPieces[k].Kind = rpkText then
          begin
            n := Length(texts);
            SetLength(texts, n + 1);
            texts[n] := el.Caption.RtPieces[k].Text;
          end;
      end
      else
      begin
        SetLength(texts, 1);
        texts[0] := el.Caption.Text;
      end;
      tx := lb.Arrays['texts'];
      got := '';
      for k := 0 to High(texts) do got := got + '|' + texts[k];
      want := '';
      for k := 0 to tx.Count - 1 do want := want + '|' + tx.Strings[k];
      Inc(FCompared);
      if got <> want then Miss('texts ' + want + ' upstream, ' + got + ' here');
      { the rect the layout weighs: the box the element holds is the port's
        own arithmetic (a centre less half a width), so its edges are held
        to upstream's within 1e-9 px }
      b := el.Shape.Bounds;
      Near('left', b.Left, FromHex(lb.Arrays['rect'].Strings[0]));
      Near('top', b.Top, FromHex(lb.Arrays['rect'].Strings[1]));
      Near('right', b.Right, FromHex(lb.Arrays['rect'].Strings[0]) + FromHex(lb.Arrays['rect'].Strings[2]));
      Near('bottom', b.Bottom, FromHex(lb.Arrays['rect'].Strings[1]) + FromHex(lb.Arrays['rect'].Strings[3]));
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('labels compared (%d)', [FLabels]), FLabels >= 100);
  AssertTrue(Format('hidden compared (%d)', [FHidden]), FHidden >= 10);
end;

function FindGuide(AList: TTyPaintList; ASeries, AData: Integer): Integer;
var i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Anim.Role = carGuide) and (AList.Element(i).Anim.Series = ASeries)
      and (AList.Element(i).Anim.Index = AData) then
      Exit(i);
  Result := -1;
end;

{ zrender's Draggable on a draggable label: pressed at its middle, moved by
  the drift, released -- each label where upstream left it, each line as
  routed again }
procedure TAdvChartLabelLayoutSizeTest.TestADragAsUpstream;
var
  cs, labs, dr, gs, pts: TJSONArray;
  c, i, k, li, gi, cw, ch: Integer;
  cse, lb, m, g: TJSONObject;
  el: TTyChartElement;
  b: TTyRectF;
  done: Integer;
begin
  done := 0;
  cs := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cs.Count - 1 do
  begin
    cse := cs.Objects[c];
    if cse.Find('drift') = nil then Continue;
    cw := cse.Integers['W'];
    ch := cse.Integers['H'];
    FChart.Option := '{}';
    FChart.Option := cse.Objects['option'].AsJSON;
    FChart.SetBounds(0, 0, cw, ch);
    FBmp.SetSize(cw, ch);
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
    { the cursor the layout gives }
    labs := cse.Arrays['labels'];
    for i := 0 to labs.Count - 1 do
    begin
      lb := labs.Objects[i];
      FName := Format('%s s%d d%d', [cse.Strings['id'], lb.Integers['s'], lb.Integers['d']]);
      li := FindLabel(FChart.List, lb.Integers['s'], lb.Integers['d']);
      Inc(FCompared);
      if li < 0 then begin Miss('no label'); Continue; end;
      Inc(FCompared);
      if FChart.List.Element(li).Cursor <> lb.Strings['cursor'] then
        Miss('cursor ' + lb.Strings['cursor'] + ' upstream, ' + FChart.List.Element(li).Cursor + ' here');
    end;
    dr := cse.Arrays['drift'];
    for k := 0 to dr.Count - 1 do
    begin
      m := dr.Objects[k];
      li := FindLabel(FChart.List, 0, m.Integers['d']);
      AssertTrue('a label to drag', li >= 0);
      b := FChart.List.Element(li).Shape.Bounds;
      { pressed just inside its right edge: labels at one point overlap,
        the widest reaches furthest }
      FChart.Drag(Floor(b.Right) - 1, Round((b.Top + b.Bottom) / 2),
        m.Integers['dx'], m.Integers['dy']);
      FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
    end;
    labs := cse.Arrays['labelsAfter'];
    for i := 0 to labs.Count - 1 do
    begin
      lb := labs.Objects[i];
      FName := Format('%s after s%d d%d', [cse.Strings['id'], lb.Integers['s'], lb.Integers['d']]);
      li := FindLabel(FChart.List, lb.Integers['s'], lb.Integers['d']);
      Inc(FCompared);
      if li < 0 then begin Miss('no label'); Continue; end;
      el := FChart.List.Element(li);
      b := el.Shape.Bounds;
      Near('left', b.Left, FromHex(lb.Arrays['rect'].Strings[0]));
      Near('top', b.Top, FromHex(lb.Arrays['rect'].Strings[1]));
      Inc(done);
    end;
    gs := cse.Arrays['guidesAfter'];
    for i := 0 to gs.Count - 1 do
    begin
      g := gs.Objects[i];
      FName := Format('%s line s%d d%d', [cse.Strings['id'], g.Integers['s'], g.Integers['d']]);
      gi := FindGuide(FChart.List, g.Integers['s'], g.Integers['d']);
      Inc(FCompared);
      if gi < 0 then begin Miss('no line'); Continue; end;
      el := FChart.List.Element(gi);
      pts := g.Arrays['points'];
      Inc(FCompared);
      if Length(el.Shape.Points) <> pts.Count then
      begin
        Miss('point count');
        Continue;
      end;
      for k := 0 to pts.Count - 1 do
      begin
        Inc(FCompared, 2);
        if (Bits(el.Shape.Points[k].X) <> Bits(FromHex(TJSONArray(pts.Items[k]).Strings[0])))
          or (Bits(el.Shape.Points[k].Y) <> Bits(FromHex(TJSONArray(pts.Items[k]).Strings[1]))) then
          Miss(Format('point %d: (%.17g, %.17g) upstream, (%.17g, %.17g) here', [k,
            FromHex(TJSONArray(pts.Items[k]).Strings[0]), FromHex(TJSONArray(pts.Items[k]).Strings[1]),
            el.Shape.Points[k].X, el.Shape.Points[k].Y]));
      end;
    end;
    { [R5-F] AN UPDATE AFTER THE DRAG (a legend toggle): updateLayoutConfig
      lays every label out afresh, the drag gone }
    if cse.Find('then') = nil then Continue;
    FChart.DispatchAction(cse.Objects['then'].AsJSON);
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
    labs := cse.Arrays['labelsThen'];
    for i := 0 to labs.Count - 1 do
    begin
      lb := labs.Objects[i];
      FName := Format('%s then s%d d%d', [cse.Strings['id'], lb.Integers['s'], lb.Integers['d']]);
      li := FindLabel(FChart.List, lb.Integers['s'], lb.Integers['d']);
      Inc(FCompared);
      if li < 0 then begin Miss('no label'); Continue; end;
      el := FChart.List.Element(li);
      if el.Ignore then Continue;
      b := el.Shape.Bounds;
      Near('left', b.Left, FromHex(lb.Arrays['rect'].Strings[0]));
      Near('top', b.Top, FromHex(lb.Arrays['rect'].Strings[1]));
      Inc(done);
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('labels after a drag (%d)', [done]), done >= 9);
end;

procedure TAdvChartLabelLayoutSizeTest.SetUp;
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
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FH := TLsHandlers.Create;
  TyChartRegisterLabelLayoutHandler('LS_W', @FH.Widths);
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-label-layout-size.json');
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FLabels := 0;
  FHidden := 0;
  FReport := '';
end;

procedure TAdvChartLabelLayoutSizeTest.TearDown;
begin
  TyChartClearLabelLayoutHandlers;
  FreeAndNil(FH);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

initialization
  RegisterTest(TAdvChartLabelLayoutSizeTest);
end.
