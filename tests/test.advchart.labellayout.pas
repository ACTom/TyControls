unit test.advchart.labellayout;
{$mode objfpc}{$H+}
{ series.labelLayout -- the object and the function form, moveOverlap
  'shiftX' / 'shiftY' and hideOverlap across series -- held to what
  ECharts 6.1's LabelManager does, bit for bit. [Batch 103, roadmap B8]

  tools/advchart-oracle/label-layout.js runs the real dist and records the
  LabelManager's list on entry to layout() and on exit (the label's raw box,
  margins, inner transformable, label.x / y, the priority, the host's rect,
  the resolved layout) and every series label after the render (its
  transform, its box, its alignment and font size, its label line), the
  params each function form was called with, and the labels under a few
  highlights.

  Three layers, reported apart:
    - THE RULES: the recorded entries fed straight into TyLayoutLabels and
      TyLabelLocalTransform / TyLabelGeometry, every answer compared;
    - THE WIRING: the control renders each option (text measured with
      zrender's SSR width table) and its label layout list, its labels, the
      calls its handlers received and its states under the highlights are
      compared;
    - by hand: the option's reading, the sector's path rect, an unregistered
      handler, the percent words. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.AxisLabels,
     tyControls.AdvChart.LabelLayout, tyControls.AdvChart.States,
     tyControls.AdvChart.Measure, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLlProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Items: TTyLabelLayoutItemArray;
    function Els: TTyIntegerArray;
    function Frame: TTyPaintList;
  end;

  { the oracle's function forms, in Pascal, each one recording its args }
  TLlHandlers = class
  public
    Calls: array of TTyChartLabelLayoutArgs;
    W: Double;
    procedure Rec(const AArgs: TTyChartLabelLayoutArgs);
    function LlDx(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function LlRight(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function LlNone(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function LlAlign(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function LlText(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function LlTouch(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function LlPieLine(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
  end;

  TAdvChartLabelLayoutTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLlProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FH: TLlHandlers;
    FBad, FCompared: Integer;
    { what the wiring reached }
    FItemsSeen, FLabelsSeen, FHidden, FCalls, FHover, FTurned, FFree, FGuides: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    procedure Same(const AWhat: string; AGot, AWant: Boolean);
    procedure Str(const AWhat, AGot, AWant: string);
    function Cases: TJSONArray;
    function CaseById(const AId: string): TJSONObject;
    procedure Show(ACase: TJSONObject);
    procedure CheckManager(ACase: TJSONObject);
    procedure CheckLabels(ACase: TJSONObject);
    procedure CheckCalls(ACase: TJSONObject);
    procedure CheckHover(ACase: TJSONObject);
    procedure Finish(AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRulesAsUpstream;
    procedure TestTheChartLaysOutAsUpstream;
    procedure TestTheOptionReadsAsUpstream;
    procedure TestTheSectorPathRect;
    procedure TestTheArcAnglesRoundInDoubles;
    procedure TestAnUnregisteredHandlerIsAnEmptyLayout;
    procedure TestThePercentWords;
    procedure TestTheOffsetRunsAlongTheTurn;
    procedure TestAShiftOnAnAttachedLabelDrawsNothingDifferent;
    procedure TestAFreeLabelSlidesFromItsOldLayout;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TLlProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLlProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TLlProbe.Items: TTyLabelLayoutItemArray;
begin
  Result := LabelLayoutItems;
end;

function TLlProbe.Els: TTyIntegerArray;
begin
  Result := LabelLayoutEls;
end;

function TLlProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ---------------- numbers ---------------- }

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
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  if (A = 0) and (B = 0) then Exit(True);
  Result := Bits(A) = Bits(B);
end;

function IsNull(D: TJSONData): Boolean;
begin
  Result := (D = nil) or (D.JSONType = jtNull);
end;

function RectOf(A: TJSONArray): TTyXYWH;
begin
  Result := TyXYWH(FromHex(A.Strings[0]), FromHex(A.Strings[1]),
    FromHex(A.Strings[2]), FromHex(A.Strings[3]));
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-label-layout.json';
end;

{ a layout value's number: ['n', hex] }
function LayNum(D: TJSONData; out AValue: Double): Boolean;
begin
  Result := (D <> nil) and (D is TJSONArray) and (TJSONArray(D).Count = 2)
    and (TJSONArray(D).Items[0].JSONType = jtString)
    and (TJSONArray(D).Strings[0] = 'n');
  if Result then AValue := FromHex(TJSONArray(D).Strings[1]) else AValue := NaN;
end;

function LayTruthy(D: TJSONData): Boolean;
var v: Double;
begin
  if IsNull(D) then Exit(False);
  if LayNum(D, v) then Exit((not IsNan(v)) and (v <> 0));
  case D.JSONType of
    jtBoolean: Result := D.AsBoolean;
    jtString: Result := D.AsString <> '';
  else
    Result := True;
  end;
end;

function AlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahCentre: Result := 'center';
    tahRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

function VAlignName(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavMiddle: Result := 'middle';
    tavBottom: Result := 'bottom';
  else
    Result := 'top';
  end;
end;

{ the emphasis state as the oracle prints it, after the port's layout }
function EmphAfter(const AEntry: TJSONData; ADeclared, AShow: Boolean): string;
begin
  if (not ADeclared) and AShow then Exit('false');
  if IsNull(AEntry) then Exit('null');
  if AEntry.JSONType = jtBoolean then
  begin
    if AEntry.AsBoolean then Exit('true') else Exit('false');
  end;
  Result := AEntry.AsString;
end;

function JsonState(const D: TJSONData): string;
begin
  if IsNull(D) then Exit('null');
  if D.JSONType = jtBoolean then
  begin
    if D.AsBoolean then Exit('true') else Exit('false');
  end;
  Result := D.AsString;
end;

{ ---------------- the handlers ---------------- }

procedure TLlHandlers.Rec(const AArgs: TTyChartLabelLayoutArgs);
var n: Integer;
begin
  n := Length(Calls);
  SetLength(Calls, n + 1);
  Calls[n] := AArgs;
  Calls[n].LabelLinePoints := Copy(AArgs.LabelLinePoints);
end;

function TLlHandlers.LlDx(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Rec(AArgs);
  Result := Default(TTyChartLabelLayout);
  Result.HasDx := True;
  Result.Dx := AArgs.DataIndex * 3 - 6;
  Result.HasDy := True;
  Result.Dy := (AArgs.DataIndex mod 3) * 2;
  Result.HideOverlap := AArgs.DataIndex mod 2 = 0;
end;

function TLlHandlers.LlRight(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Rec(AArgs);
  Result := Default(TTyChartLabelLayout);
  Result.X := TyChartPosNum(AArgs.RectX + AArgs.RectW + 4);
  Result.Y := TyChartPosNum(AArgs.LabelRectY);
  Result.HasAlign := True;
  Result.Align := 'left';
  Result.HasVerticalAlign := True;
  Result.VerticalAlign := 'top';
  Result.MoveOverlap := 'shiftY';
end;

function TLlHandlers.LlNone(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Rec(AArgs);
  Result := Default(TTyChartLabelLayout);
end;

function TLlHandlers.LlAlign(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Rec(AArgs);
  Result := Default(TTyChartLabelLayout);
  Result.HasAlign := True;
  if AArgs.Align = '' then Result.Align := 'right' else Result.Align := 'left';
  Result.HasFontSize := True;
  Result.FontSize := 16 + AArgs.SeriesIndex * 2;
  Result.HideOverlap := True;
end;

function TLlHandlers.LlText(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Rec(AArgs);
  Result := Default(TTyChartLabelLayout);
  Result.HasRotate := True;
  Result.Rotate := Length(UTF8Decode(AArgs.Text)) * 10;
  Result.HideOverlap := True;
end;

function TLlHandlers.LlTouch(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Rec(AArgs);
  Result := Default(TTyChartLabelLayout);
  Result.X := TyChartPosNum(100 + AArgs.DataIndex * AArgs.LabelRectW);
  Result.Y := TyChartPosNum(100);
  Result.HasAlign := True;
  Result.Align := 'left';
  Result.HasVerticalAlign := True;
  Result.VerticalAlign := 'top';
  Result.HideOverlap := True;
end;

function TLlHandlers.LlPieLine(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
var pts: TTyPointFArray;
begin
  Rec(AArgs);
  Result := Default(TTyChartLabelLayout);
  if Length(AArgs.LabelLinePoints) = 0 then Exit;
  pts := Copy(AArgs.LabelLinePoints);
  if AArgs.LabelRectX < W / 2 then pts[2].X := AArgs.LabelRectX
  else pts[2].X := AArgs.LabelRectX + AArgs.LabelRectW;
  Result.HasLabelLinePoints := True;
  Result.LabelLinePoints := pts;
end;

{ ---------------- the test case ---------------- }

procedure TAdvChartLabelLayoutTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 120 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLabelLayoutTest.Num(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameNum(AGot, FromHex(AHex)) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartLabelLayoutTest.Same(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s: %s upstream, %s here', [AWhat, BoolToStr(AWant, True),
      BoolToStr(AGot, True)]));
end;

procedure TAdvChartLabelLayoutTest.Str(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s: "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

function TAdvChartLabelLayoutTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function TAdvChartLabelLayoutTest.CaseById(const AId: string): TJSONObject;
var c: Integer;
begin
  for c := 0 to Cases.Count - 1 do
    if Cases.Objects[c].Strings['id'] = AId then Exit(Cases.Objects[c]);
  Result := nil;
  Fail('no case ' + AId);
end;

procedure TAdvChartLabelLayoutTest.Show(ACase: TJSONObject);
begin
  FH.Calls := nil;
  FChart.Option := '{}';
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartLabelLayoutTest.Finish(AMin: Integer);
begin
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > AMin);
end;

{ an item from a recorded entry: what layout() starts from }
function ItemOf(AM: TJSONObject): TTyLabelLayoutItem;
var
  e, def, inner, lay: TJSONObject;
  k: Integer;
  mv: string;
begin
  Result := Default(TTyLabelLayoutItem);
  e := AM.Objects['entry'];
  def := AM.Objects['def'];
  Result.Priority := FromHex(AM.Strings['priority']);
  Result.DefIgnore := def.Booleans['ignore'];
  Result.HasGuide := not IsNull(def.Find('guideIgnore'));
  if Result.HasGuide then Result.DefGuideIgnore := def.Booleans['guideIgnore'];
  if (AM.Find('layout') <> nil) and (AM.Find('layout') is TJSONObject) then
  begin
    lay := AM.Objects['layout'];
    mv := '';
    if (lay.Find('moveOverlap') <> nil) and (lay.Find('moveOverlap').JSONType = jtString) then
      mv := lay.Strings['moveOverlap'];
    if mv = 'shiftX' then Result.Move := tlmShiftX
    else if mv = 'shiftY' then Result.Move := tlmShiftY;
    Result.HideOverlap := LayTruthy(lay.Find('hideOverlap'));
  end;
  Result.Free := IsNull(e.Find('position'));
  Result.RawLocal := RectOf(e.Arrays['rawLocal']);
  if not IsNull(e.Find('marginType')) then Result.MarginType := e.Integers['marginType'];
  if not IsNull(e.Find('margin')) then
    for k := 0 to 3 do Result.Margin[k] := FromHex(e.Arrays['margin'].Strings[k]);
  inner := e.Objects['inner'];
  Result.InnerX := FromHex(inner.Strings['x']);
  Result.InnerY := FromHex(inner.Strings['y']);
  Result.OriginX := FromHex(inner.Strings['originX']);
  Result.OriginY := FromHex(inner.Strings['originY']);
  Result.Rotation := FromHex(inner.Strings['rotation']);
  Result.ScaleX := FromHex(inner.Strings['scaleX']);
  Result.ScaleY := FromHex(inner.Strings['scaleY']);
  Result.OffX := FromHex(e.Arrays['offset'].Strings[0]);
  Result.OffY := FromHex(e.Arrays['offset'].Strings[1]);
  Result.LabelX := FromHex(e.Strings['labelX']);
  Result.LabelY := FromHex(e.Strings['labelY']);
  Result.EmphDeclared := (e.Find('emph') <> nil) and (e.Find('emph').JSONType = jtBoolean);
  Result.GuideEmphDeclared := (e.Find('guideEmph') <> nil)
    and (e.Find('guideEmph').JSONType = jtBoolean);
end;

{ THE RULES: the entries straight into the layout }
procedure TAdvChartLabelLayoutTest.TestTheRulesAsUpstream;
var
  c, i, k: Integer;
  cs, m, e, x: TJSONObject;
  mgr: TJSONArray;
  items: TTyLabelLayoutItemArray;
  mat: TTyMat2D;
  has: Boolean;
  box: TTyLabelBox;
  tr: TJSONArray;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    mgr := cs.Arrays['manager'];
    SetLength(items, mgr.Count);
    for i := 0 to mgr.Count - 1 do
    begin
      m := mgr.Objects[i];
      FName := Format('%s #%d "%s"', [cs.Strings['id'], i, m.Strings['text']]);
      items[i] := ItemOf(m);
      e := m.Objects['entry'];
      { the transform from the inner transformable }
      has := TyLabelLocalTransform(items[i].InnerX, items[i].InnerY,
        items[i].OriginX, items[i].OriginY, items[i].Rotation, items[i].ScaleX,
        items[i].ScaleY, mat);
      Inc(FCompared);
      if has = IsNull(e.Find('transform')) then
        Miss('a transform upstream: ' + BoolToStr(not IsNull(e.Find('transform')), True))
      else if has then
      begin
        tr := e.Arrays['transform'];
        for k := 0 to 5 do Num('m' + IntToStr(k), mat[k], tr.Strings[k]);
      end;
      { the geometry }
      box := TyLabelGeometry(items[i].RawLocal, mat, has, items[i].MarginType, items[i].Margin);
      Num('local.x', box.LocalRect.X, e.Arrays['local'].Strings[0]);
      Num('local.y', box.LocalRect.Y, e.Arrays['local'].Strings[1]);
      Num('local.w', box.LocalRect.W, e.Arrays['local'].Strings[2]);
      Num('local.h', box.LocalRect.H, e.Arrays['local'].Strings[3]);
      Num('rect.x', box.Rect.X, e.Arrays['rect'].Strings[0]);
      Num('rect.y', box.Rect.Y, e.Arrays['rect'].Strings[1]);
      Num('rect.w', box.Rect.W, e.Arrays['rect'].Strings[2]);
      Num('rect.h', box.Rect.H, e.Arrays['rect'].Strings[3]);
      Same('axisAligned', box.AxisAligned, e.Booleans['axisAligned']);
    end;
    TyLayoutLabels(items, 0, 0, cW, cH);
    for i := 0 to mgr.Count - 1 do
    begin
      m := mgr.Objects[i];
      FName := Format('%s #%d "%s"', [cs.Strings['id'], i, m.Strings['text']]);
      x := m.Objects['exit'];
      e := m.Objects['entry'];
      Same('ignore', items[i].Ignore, x.Booleans['ignore']);
      if items[i].HasGuide then Same('guide ignore', items[i].GuideIgnore, x.Booleans['guideIgnore']);
      Num('label.x', items[i].LabelX, x.Strings['labelX']);
      Num('label.y', items[i].LabelY, x.Strings['labelY']);
      Str('emphasis', EmphAfter(e.Find('emph'), items[i].EmphDeclared, items[i].EmphShow),
        JsonState(x.Find('emph')));
      if items[i].HasGuide then
        Str('guide emphasis', EmphAfter(e.Find('guideEmph'), items[i].GuideEmphDeclared,
          items[i].GuideEmphShow), JsonState(x.Find('guideEmph')));
    end;
  end;
  Finish(20000);
end;

{ ---------------- the wiring ---------------- }

procedure TAdvChartLabelLayoutTest.CheckManager(ACase: TJSONObject);
var
  mgr: TJSONArray;
  items: TTyLabelLayoutItemArray;
  els: TTyIntegerArray;
  i: Integer;
  m, e, x, inner: TJSONObject;
  el: TTyElementCaption;
  elx: TTyChartElement;
begin
  mgr := ACase.Arrays['manager'];
  items := FChart.Items;
  els := FChart.Els;
  Inc(FCompared);
  if Length(items) <> mgr.Count then
  begin
    Miss(Format('%d labels in the layout upstream, %d here', [mgr.Count, Length(items)]));
    Exit;
  end;
  for i := 0 to mgr.Count - 1 do
  begin
    m := mgr.Objects[i];
    e := m.Objects['entry'];
    x := m.Objects['exit'];
    inner := e.Objects['inner'];
    elx := FChart.List.Element(els[i]);
    el := elx.Caption;
    FName := Format('%s #%d "%s"', [ACase.Strings['id'], i, m.Strings['text']]);
    Inc(FItemsSeen);
    Inc(FCompared);
    if (elx.Datum.SeriesIndex <> m.Integers['s']) or (elx.Datum.DataIndex <> m.Integers['d'])
      or (el.Text <> m.Strings['text']) then
    begin
      Miss(Format('the label is s%d d%d "%s" here', [elx.Datum.SeriesIndex,
        elx.Datum.DataIndex, el.Text]));
      Continue;
    end;
    Num('priority', items[i].Priority, m.Strings['priority']);
    Num('raw.x', items[i].RawLocal.X, e.Arrays['rawLocal'].Strings[0]);
    Num('raw.y', items[i].RawLocal.Y, e.Arrays['rawLocal'].Strings[1]);
    Num('raw.w', items[i].RawLocal.W, e.Arrays['rawLocal'].Strings[2]);
    Num('raw.h', items[i].RawLocal.H, e.Arrays['rawLocal'].Strings[3]);
    Num('rotation', items[i].Rotation, inner.Strings['rotation']);
    Num('scaleX', items[i].ScaleX, inner.Strings['scaleX']);
    Num('scaleY', items[i].ScaleY, inner.Strings['scaleY']);
    Num('originX', items[i].OriginX, inner.Strings['originX']);
    Num('originY', items[i].OriginY, inner.Strings['originY']);
    Same('free', items[i].Free, IsNull(e.Find('position')));
    if not items[i].Free then
    begin
      Num('inner.x', items[i].InnerX, inner.Strings['x']);
      Num('inner.y', items[i].InnerY, inner.Strings['y']);
    end
    else
      Inc(FFree);
    Num('label.x', items[i].LabelX, x.Strings['labelX']);
    Num('label.y', items[i].LabelY, x.Strings['labelY']);
    Same('ignored at rest', items[i].DefIgnore, m.Objects['def'].Booleans['ignore']);
    Same('ignore', items[i].Ignore, x.Booleans['ignore']);
    Same('element ignore', elx.Ignore, x.Booleans['ignore']);
    if items[i].Ignore and not items[i].DefIgnore then Inc(FHidden);
    if items[i].HasGuide then
    begin
      Same('guide ignore', items[i].GuideIgnore, x.Booleans['guideIgnore']);
      Inc(FGuides);
    end
    else
    begin
      Inc(FCompared);
      if not IsNull(x.Find('guideIgnore')) then Miss('a label line upstream, none here');
    end;
    Str('emphasis', EmphAfter(e.Find('emph'), (JsonState(e.Find('emph')) = 'true')
      or (JsonState(e.Find('emph')) = 'false'), items[i].EmphShow), JsonState(x.Find('emph')));
  end;
end;

{ the transform a caption is drawn with }
function CaptionMat(const C: TTyElementCaption; out AM: TTyMat2D): Boolean;
begin
  if C.LmHasM then
  begin
    AM := C.LmM;
    Exit(True);
  end;
  Result := TyLabelLocalTransform(C.LmBaseX + C.LmOffX, C.LmBaseY + C.LmOffY,
    -C.LmOffX, -C.LmOffY, C.RotationRad, 1, 1, AM);
end;

function FontPx(AFont: Integer): Double;
begin
  if TyFontSizeIsPx(AFont) then Result := TyFontPxOf(AFont)
  else Result := AFont * 96 / 72;
end;

procedure TAdvChartLabelLayoutTest.CheckLabels(ACase: TJSONObject);
var
  labs, mat, pts: TJSONArray;
  i, j, k, g: Integer;
  lb, gd: TJSONObject;
  el, ge: TTyChartElement;
  found: Boolean;
  m: TTyMat2D;
  has: Boolean;
begin
  labs := ACase.Arrays['labels'];
  for i := 0 to labs.Count - 1 do
  begin
    lb := labs.Objects[i];
    FName := Format('%s label s%d d%s "%s"', [ACase.Strings['id'], lb.Integers['s'],
      lb.Find('d').AsString, lb.Strings['text']]);
    found := False;
    for j := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(j);
      if (el.Caption.LmKind = 0) or (el.Datum.SeriesIndex <> lb.Integers['s'])
        or (el.Datum.DataIndex <> lb.Integers['d']) or (el.Caption.Text <> lb.Strings['text']) then
        Continue;
      found := True;
      Inc(FLabelsSeen);
      Same('ignore', el.Ignore, lb.Booleans['ignore']);
      mat := lb.Arrays['mat'];
      has := CaptionMat(el.Caption, m);
      Inc(FCompared);
      if has = IsNull(mat) then
        Miss('a transform upstream: ' + BoolToStr(not IsNull(mat), True))
      else if has then
      begin
        for k := 0 to 5 do Num('m' + IntToStr(k), m[k], mat.Strings[k]);
        if Abs(m[1]) > 1e-9 then Inc(FTurned);
        { and the point the painter hangs the words at }
        Num('caption x', el.Caption.X, mat.Strings[4]);
        Num('caption y', el.Caption.Y, mat.Strings[5]);
      end;
      Str('align', AlignName(el.Caption.AnchorH), lb.Strings['align']);
      Str('verticalAlign', VAlignName(el.Caption.AnchorV), lb.Strings['verticalAlign']);
      if not IsNull(lb.Find('fontSize')) then
      begin
        Inc(FCompared);
        if not SameValue(FontPx(el.Caption.FontSizeLogical), lb.Floats['fontSize'], 1e-9) then
          Miss(Format('font size %s upstream, %s here', [Fmt(lb.Floats['fontSize']),
            Fmt(FontPx(el.Caption.FontSizeLogical))]));
      end;
      { the label line }
      if not IsNull(lb.Find('guide')) then
      begin
        gd := lb.Objects['guide'];
        g := -1;
        for k := 0 to FChart.List.Count - 1 do
          if (FChart.List.Element(k).Anim.Role = carGuide)
            and (FChart.List.Element(k).Anim.Series = lb.Integers['s'])
            and (FChart.List.Element(k).Anim.Index = lb.Integers['d']) then
          begin
            g := k;
            Break;
          end;
        Inc(FCompared);
        if g < 0 then
          Miss('a label line upstream, none here')
        else
        begin
          ge := FChart.List.Element(g);
          Same('guide ignore', ge.Ignore, gd.Booleans['ignore']);
          pts := gd.Arrays['points'];
          Inc(FCompared);
          if Length(ge.Shape.Points) <> pts.Count then
            Miss(Format('%d line points upstream, %d here', [pts.Count, Length(ge.Shape.Points)]))
          else
            for k := 0 to pts.Count - 1 do
            begin
              Num('line x' + IntToStr(k), ge.Shape.Points[k].X, TJSONArray(pts.Items[k]).Strings[0]);
              Num('line y' + IntToStr(k), ge.Shape.Points[k].Y, TJSONArray(pts.Items[k]).Strings[1]);
            end;
        end;
      end;
      Break;
    end;
    Inc(FCompared);
    if not found then Miss('a label upstream, none here');
  end;
end;

procedure TAdvChartLabelLayoutTest.CheckCalls(ACase: TJSONObject);
var
  calls, pts: TJSONArray;
  i, k: Integer;
  cl: TJSONObject;
  a: TTyChartLabelLayoutArgs;
begin
  calls := ACase.Arrays['calls'];
  Inc(FCompared);
  if Length(FH.Calls) <> calls.Count then
  begin
    Miss(Format('%d calls upstream, %d here', [calls.Count, Length(FH.Calls)]));
    Exit;
  end;
  for i := 0 to calls.Count - 1 do
  begin
    cl := calls.Objects[i];
    a := FH.Calls[i];
    FName := Format('%s call %d', [ACase.Strings['id'], i]);
    Inc(FCalls);
    Inc(FCompared);
    if (a.SeriesIndex <> cl.Integers['s']) or (a.DataIndex <> cl.Integers['d'])
      or (a.Text <> cl.Strings['text']) then
      Miss(Format('called for s%d d%d "%s" here, s%d d%d "%s" upstream', [a.SeriesIndex,
        a.DataIndex, a.Text, cl.Integers['s'], cl.Integers['d'], cl.Strings['text']]));
    Str('dataType', a.DataType, '');
    Same('rect', a.HasRect, not IsNull(cl.Find('rect')));
    if a.HasRect and not IsNull(cl.Find('rect')) then
    begin
      Num('rect.x', a.RectX, cl.Arrays['rect'].Strings[0]);
      Num('rect.y', a.RectY, cl.Arrays['rect'].Strings[1]);
      Num('rect.w', a.RectW, cl.Arrays['rect'].Strings[2]);
      Num('rect.h', a.RectH, cl.Arrays['rect'].Strings[3]);
    end;
    Num('labelRect.x', a.LabelRectX, cl.Arrays['labelRect'].Strings[0]);
    Num('labelRect.y', a.LabelRectY, cl.Arrays['labelRect'].Strings[1]);
    Num('labelRect.w', a.LabelRectW, cl.Arrays['labelRect'].Strings[2]);
    Num('labelRect.h', a.LabelRectH, cl.Arrays['labelRect'].Strings[3]);
    if IsNull(cl.Find('align')) then Str('align', a.Align, '')
    else Str('align', a.Align, cl.Strings['align']);
    if IsNull(cl.Find('verticalAlign')) then Str('verticalAlign', a.VerticalAlign, '')
    else Str('verticalAlign', a.VerticalAlign, cl.Strings['verticalAlign']);
    Inc(FCompared);
    if IsNull(cl.Find('labelLinePoints')) then
    begin
      if Length(a.LabelLinePoints) > 0 then Miss('line points here, none upstream');
    end
    else
    begin
      pts := cl.Arrays['labelLinePoints'];
      if Length(a.LabelLinePoints) <> pts.Count then
        Miss(Format('%d line points upstream, %d here', [pts.Count, Length(a.LabelLinePoints)]))
      else
        for k := 0 to pts.Count - 1 do
        begin
          Num('point x', a.LabelLinePoints[k].X, TJSONArray(pts.Items[k]).Strings[0]);
          Num('point y', a.LabelLinePoints[k].Y, TJSONArray(pts.Items[k]).Strings[1]);
        end;
    end;
  end;
end;

procedure TAdvChartLabelLayoutTest.CheckHover(ACase: TJSONObject);
var
  hv, labs: TJSONArray;
  h, i: Integer;
  pl, lb: TJSONObject;
  st: TTyStItem;
begin
  hv := ACase.Arrays['hover'];
  for h := 0 to hv.Count - 1 do
  begin
    pl := hv.Objects[h].Objects['payload'];
    AssertTrue('highlight', FChart.DispatchAction(pl.AsJSON));
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
    labs := hv.Objects[h].Arrays['labels'];
    for i := 0 to labs.Count - 1 do
    begin
      lb := labs.Objects[i];
      FName := Format('%s highlight %d, s%d d%d', [ACase.Strings['id'],
        pl.Integers['dataIndex'], lb.Integers['s'], lb.Integers['d']]);
      Inc(FCompared);
      if not FChart.ItemStates(lb.Integers['s'], lb.Integers['d'], st) or not st.Label_.Exists then
      begin
        Miss('no label states here');
        Continue;
      end;
      Inc(FHover);
      Same('ignore', st.Label_.Cur.Num[stkIgnore] <> 0, lb.Booleans['ignore']);
      if not IsNull(lb.Find('guideIgnore')) then
      begin
        Inc(FCompared);
        if not st.Guide.Exists then Miss('no line states here')
        else Same('guide ignore', st.Guide.Cur.Num[stkIgnore] <> 0, lb.Booleans['guideIgnore']);
      end;
    end;
    pl.Strings['type'] := 'downplay';
    FChart.DispatchAction(pl.AsJSON);
    pl.Strings['type'] := 'highlight';
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  end;
end;

procedure TAdvChartLabelLayoutTest.TestTheChartLaysOutAsUpstream;
var
  c: Integer;
  cs: TJSONObject;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    FName := cs.Strings['id'];
    Show(cs);
    CheckManager(cs);
    CheckLabels(cs);
    CheckCalls(cs);
    CheckHover(cs);
  end;
  Finish(20000);
  AssertTrue(Format('layout items compared (%d)', [FItemsSeen]), FItemsSeen >= 1000);
  AssertTrue(Format('labels compared (%d)', [FLabelsSeen]), FLabelsSeen >= 1200);
  AssertTrue(Format('hidden labels compared (%d)', [FHidden]), FHidden >= 150);
  AssertTrue(Format('calls compared (%d)', [FCalls]), FCalls >= 80);
  AssertTrue(Format('labels under a highlight compared (%d)', [FHover]), FHover >= 40);
  AssertTrue(Format('turned labels compared (%d)', [FTurned]), FTurned >= 50);
  AssertTrue(Format('free labels compared (%d)', [FFree]), FFree >= 60);
  AssertTrue(Format('label lines compared (%d)', [FGuides]), FGuides >= 50);
end;

{ ---------------- by hand ---------------- }

procedure TAdvChartLabelLayoutTest.TestTheOptionReadsAsUpstream;
var
  d: TJSONData;
  s: TTyLabelLayoutSpec;

  function Of_(const AJson: string; AHasKey, APie: Boolean): TTyLabelLayoutSpec;
  begin
    if AJson = '' then d := nil else d := GetJSON(AJson);
    try
      Result := TyLabelLayoutSpecOf(d, AHasKey, APie);
    finally
      FreeAndNil(d);
    end;
  end;

begin
  AssertTrue('not written: none', Of_('', False, False).Kind = tlkNone);
  s := Of_('', False, True);
  AssertTrue('a pie not written: the default', (s.Kind = tlkObject) and s.Obj.HideOverlap);
  AssertTrue('a pie with null: none', Of_('null', True, True).Kind = tlkNone);
  AssertTrue('{}: none', Of_('{}', True, False).Kind = tlkNone);
  s := Of_('{}', True, True);
  AssertTrue('a pie with {}: the default under it', (s.Kind = tlkObject) and s.Obj.HideOverlap);
  s := Of_('{"hideOverlap":false}', True, True);
  AssertTrue('a pie that says false', (s.Kind = tlkObject) and not s.Obj.HideOverlap);
  s := Of_('{"x":null}', True, False);
  AssertTrue('a key with null still lays out', s.Kind = tlkObject);
  AssertTrue('and x is absent', s.Obj.X.Kind = cpvAbsent);
  s := Of_('"@Fn"', True, True);
  AssertTrue('a handler', (s.Kind = tlkHandler) and (s.Handler = '@Fn'));
  AssertTrue('a string: keys of a string', Of_('"abc"', True, False).Kind = tlkObject);
  AssertTrue('an empty string: none', Of_('""', True, False).Kind = tlkNone);
  AssertTrue('true: none', Of_('true', True, False).Kind = tlkNone);
  AssertTrue('a number: none', Of_('5', True, False).Kind = tlkNone);
  s := Of_('{"x":"50%","y":20,"dx":3,"rotate":45,"align":"middle","moveOverlap":"shiftY",'
    + '"hideOverlap":1,"fontSize":16,"labelLinePoints":[[1,2],[3,4],[5,6]]}', True, False);
  AssertTrue('x text', (s.Obj.X.Kind = cpvText) and (s.Obj.X.Text = '50%'));
  AssertTrue('y number', (s.Obj.Y.Kind = cpvNumber) and (s.Obj.Y.Num = 20));
  AssertTrue('dx', s.Obj.HasDx and (s.Obj.Dx = 3) and not s.Obj.HasDy);
  AssertTrue('rotate', s.Obj.HasRotate and (s.Obj.Rotate = 45));
  AssertTrue('hideOverlap truthy', s.Obj.HideOverlap);
  AssertTrue('shiftY', TyLabelMoveOf(s.Obj) = tlmShiftY);
  AssertTrue('font size', s.Obj.HasFontSize and (s.Obj.FontSize = 16));
  AssertEquals('three points', 3, Length(s.Obj.LabelLinePoints));
  AssertEquals(5.0, s.Obj.LabelLinePoints[2].X);
  s.Obj.MoveOverlap := 'shifty';
  AssertTrue('moveOverlap is case-sensitive', TyLabelMoveOf(s.Obj) = tlmNone);
  s.Obj.MoveOverlap := 'shiftx';
  AssertTrue('either way', TyLabelMoveOf(s.Obj) = tlmNone);
end;

procedure TAdvChartLabelLayoutTest.TestTheSectorPathRect;
var r: TTyXYWH;
begin
  { a full turn is the disc }
  r := TySectorPathRect(10, 20, 0, 5, 0, 2 * Pi, True);
  AssertEquals(5.0, r.X);
  AssertEquals(15.0, r.Y);
  AssertEquals(10.0, r.W);
  AssertEquals(10.0, r.H);
  { a quarter from three o'clock to six, clockwise on screen: the centre,
    the start on the right and the end below }
  r := TySectorPathRect(0, 0, 0, 10, 0, Pi / 2, True);
  AssertTrue('from the centre', SameValue(r.X, 0, 1e-9) and SameValue(r.Y, 0, 1e-9));
  AssertTrue('to the arc', SameValue(r.W, 10, 1e-9) and SameValue(r.H, 10, 1e-9));
  { the same quarter the other way round passes through twelve, six and nine
    o'clock: three quarters of the disc }
  r := TySectorPathRect(0, 0, 0, 10, 0, Pi / 2, False);
  AssertTrue('three quarters', SameValue(r.X, -10, 1e-9) and SameValue(r.Y, -10, 1e-9)
    and SameValue(r.W, 20, 1e-9) and SameValue(r.H, 20, 1e-9));
  { a ring keeps its hole's arc, not the centre }
  r := TySectorPathRect(0, 0, 5, 10, Pi / 4, Pi / 2, True);
  AssertTrue('the hole keeps the centre out', r.X > 0);
end;

{ normalizeArcAngles' modPI2 rounds to 1e-8 of a half turn IN DOUBLES: the
  start of pie.default's second slice as PathProxy stores it (node) }
procedure TAdvChartLabelLayoutTest.TestTheArcAnglesRoundInDoubles;
var s, e: Double;
begin
  s := FromHex('4013071e0d6a156e');
  e := s + 0.35;
  TyNormalizeArcAngles(s, e, False);
  AssertEquals('4013071e0e03323a', LowerCase(IntToHex(Bits(s), 16)));
end;

procedure TAdvChartLabelLayoutTest.TestAnUnregisteredHandlerIsAnEmptyLayout;
var
  i, n: Integer;
  els: TTyIntegerArray;
  e: TTyChartElement;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[3,5],"label":{"show":true,'
    + '"position":"top","offset":[0,-20]},"labelLayout":"@NobodyRegisteredThis"}]}';
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  els := FChart.Els;
  AssertEquals('both labels laid out', 2, Length(els));
  n := 0;
  for i := 0 to High(els) do
  begin
    e := FChart.List.Element(els[i]);
    { the layout ran with nothing in it: the offset is gone }
    AssertTrue('at the anchor', SameValue(e.Caption.X, e.Caption.LmBaseX, 0)
      and SameValue(e.Caption.Y, e.Caption.LmBaseY, 0));
    Inc(n);
  end;
  AssertEquals(2, n);
end;

procedure TAdvChartLabelLayoutTest.TestThePercentWords;
begin
  AssertEquals(300.0, TyLabelLayoutPos(TyChartPosText('center'), 600));
  AssertEquals(300.0, TyLabelLayoutPos(TyChartPosText('middle'), 600));
  AssertEquals(0.0, TyLabelLayoutPos(TyChartPosText('left'), 600));
  AssertEquals(600.0, TyLabelLayoutPos(TyChartPosText('bottom'), 600));
  AssertEquals(150.0, TyLabelLayoutPos(TyChartPosText(' 25% '), 600));
  AssertEquals(200.0, TyLabelLayoutPos(TyChartPosText('200'), 600));
  AssertEquals(12.5, TyLabelLayoutPos(TyChartPosText('12.5px'), 600));
  AssertTrue(IsNan(TyLabelLayoutPos(TyChartPosText('abc'), 600)));
  AssertTrue(IsNan(TyLabelLayoutPos(TyChartPosAbsent, 600)));
  AssertEquals(7.0, TyLabelLayoutPos(TyChartPosNum(7), 600));
end;

{ the origin is minus the offset: the turn runs about the anchor }
procedure TAdvChartLabelLayoutTest.TestTheOffsetRunsAlongTheTurn;
var m: TTyMat2D;
begin
  AssertTrue(TyLabelLocalTransform(100 + 10, 50 + 0, -10, -0, Pi / 2, 1, 1, m));
  { (10, 0) turned a quarter counter-clockwise on screen is (0, -10) }
  AssertTrue('x', SameValue(m[4], 100, 1e-9));
  AssertTrue('y', SameValue(m[5], 40, 1e-9));
  { unturned: the plain sum, in zrender's order }
  AssertTrue(TyLabelLocalTransform(100.1 + 0.3, 50, -0.3, 0, 0, 1, 1, m));
  AssertEquals(0.3 + ((-0.3) + (100.1 + 0.3)), m[4]);
  { nothing to move or turn: no transform }
  AssertFalse(TyLabelLocalTransform(0, 0, 0, 0, 0, 1, 1, m));
  AssertFalse(TyLabelLocalTransform(1e-5, 0, 0, 0, 4e-5, 1, 1, m));
end;

{ THE QUIRK: a shift moves label.x / y and the rect, and an attached label
  is drawn where its host puts it -- and hideOverlap reads it there }
procedure TAdvChartLabelLayoutTest.TestAShiftOnAnAttachedLabelDrawsNothingDifferent;
var
  cs: TJSONObject;
  i, moved: Integer;
  els: TTyIntegerArray;
  items: TTyLabelLayoutItemArray;
  e: TTyChartElement;
begin
  cs := CaseById('shiftY.attached.hide');
  Show(cs);
  els := FChart.Els;
  items := FChart.Items;
  moved := 0;
  for i := 0 to High(items) do
  begin
    e := FChart.List.Element(els[i]);
    AssertFalse('attached', items[i].Free);
    AssertTrue('drawn at the anchor', SameValue(e.Caption.X, e.Caption.LmBaseX, 0)
      and SameValue(e.Caption.Y, e.Caption.LmBaseY, 0));
    if not SameValue(items[i].LabelY, items[i].InnerY, 1e-9) then Inc(moved);
  end;
  AssertTrue('some were shifted', moved > 0);
end;

{ A LABEL PUT AT ITS OWN x / y moves from its old layout in an update, as
  LabelManager's _animateLabels moves a pie's -- it no longer rides its
  host, and it does not jump }
procedure TAdvChartLabelLayoutTest.TestAFreeLabelSlidesFromItsOldLayout;
const
  cT0 = 1000000;
  cOpt = '{"animationDurationUpdate":1000,"animationEasingUpdate":"linear",'
    + '"xAxis":{},"yAxis":{},"series":[{"type":"scatter","data":[[1,2],[3,4]],'
    + '"label":{"show":true},"labelLayout":{"x":%d,"y":100}}]}';
var
  t, i: Integer;
  x: Double;
  found: Boolean;
  e: TTyChartElement;

  procedure Settle(AStart: Double);
  begin
    t := 16;
    while t <= 5000 do
    begin
      FChart.AnimNow := AStart + t;
      FChart.AnimTick(AStart + t);
      Inc(t, 250);
    end;
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  end;

  function LabelX(AList: TTyPaintList): Double;
  var k: Integer;
  begin
    Result := NaN;
    for k := 0 to AList.Count - 1 do
      if (AList.Element(k).Anim.Role = carLabel) and (AList.Element(k).Anim.Series = 0)
        and (AList.Element(k).Anim.Index = 0) then
        Exit(AList.Element(k).Caption.X);
  end;

begin
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := cT0;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := Format(cOpt, [100]);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  Settle(cT0);
  AssertTrue('at 100', SameValue(LabelX(FChart.Frame), 100, 1e-9));
  FChart.AnimNow := cT0 + 10000;
  FChart.Option := Format(cOpt, [300]);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  FChart.AnimNow := cT0 + 10000 + 500;
  FChart.AnimTick(cT0 + 10000 + 500);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  x := LabelX(FChart.Frame);
  AssertTrue(Format('on its way (%s)', [Fmt(x)]), (x > 100.5) and (x < 299.5));
  Settle(cT0 + 10000);
  AssertTrue('at 300', SameValue(LabelX(FChart.Frame), 300, 1e-9));
  found := False;
  for i := 0 to High(FChart.Els) do
  begin
    e := FChart.List.Element(FChart.Els[i]);
    if e.Caption.LmFree then found := True;
  end;
  AssertTrue('free', found);
end;

{ ---------------- plumbing ---------------- }

procedure TAdvChartLabelLayoutTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TLlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
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
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FH := TLlHandlers.Create;
  FH.W := cW;
  TyChartRegisterLabelLayoutHandler('LL_DX', @FH.LlDx);
  TyChartRegisterLabelLayoutHandler('LL_RIGHT', @FH.LlRight);
  TyChartRegisterLabelLayoutHandler('LL_NONE', @FH.LlNone);
  TyChartRegisterLabelLayoutHandler('LL_ALIGN', @FH.LlAlign);
  TyChartRegisterLabelLayoutHandler('LL_TEXT', @FH.LlText);
  TyChartRegisterLabelLayoutHandler('LL_TOUCH', @FH.LlTouch);
  TyChartRegisterLabelLayoutHandler('LL_PIELINE', @FH.LlPieLine);
  FBad := 0;
  FCompared := 0;
  FReport := '';
  FItemsSeen := 0;
  FLabelsSeen := 0;
  FHidden := 0;
  FCalls := 0;
  FHover := 0;
  FTurned := 0;
  FFree := 0;
  FGuides := 0;
end;

procedure TAdvChartLabelLayoutTest.TearDown;
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
  RegisterTest(TAdvChartLabelLayoutTest);
end.
