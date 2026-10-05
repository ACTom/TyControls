unit test.advchart.pieavoid;
{$mode objfpc}{$H+}
{ A pie's label avoidance -- avoidOverlap, adjustSingleSide's shift and
  ellipse, the labelLine / edge alignments, bleedMargin, edgeDistance and the
  truncation the target widths bring -- held to ECharts 6.1 bit for bit.
  [Batch 109, roadmap B13]

  tools/advchart-oracle/pie-avoid.js runs the real dist with two read-only
  hooks round the one statement that calls avoidOverlap, and records each
  pie's list before and after the solver, then every pie label as drawn (the
  lines zrender drew, its transform, its alignment, hideOverlap's verdict,
  its label line).

  Two layers, reported apart:
    - THE SOLVER: each recorded list fed straight into TyPieAvoidOverlap, the
      rect measured with zrender's SSR width table (plain labels only -- a
      block's rect needs the option's styles, which the wiring has);
    - THE WIRING: the control renders each option and its pie labels are
      compared -- the label's x / y, the words drawn, the transform, the
      alignment, hidden or not, and the line: the solver's, bent by the two
      turn limits [Batch 112: they were only counted];
    - THE LIMITS: each recorded solver line bent by limitTurnAngle and
      limitSurfaceAngle (AdvChart.LabelGuide) against the line drawn.
      [Batch 112, roadmap B14] }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.LabelLayout, tyControls.AdvChart.LabelGuide, tyControls.AdvChart.Pie, tyControls.AdvChart.PieLabel, tyControls.AdvChart.Labels, tyControls.AdvChart.RichStyle,
     tyControls.AdvChart.Measure, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TPaProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  { the rect the solver asks for, from a recorded plain label }
  TPaRulesFit = class
  public
    Measurer: ITyTextMeasurer;
    Texts, Ellipses: array of string;
    Truncate: array of Boolean;
    OffX, OffY, Rots: array of Double;
    MarginTypes: array of Integer;
    Margins: array of TTyPieMargin;
    function RectOf(const AItem: TTyPieAvoidItem; AIndex: Integer): TTyXYWH;
  end;

  TAdvChartPieAvoidTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TPaProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FSsr: ITyTextMeasurer;
    FBad, FCompared: Integer;
    FPies, FItems, FMoved, FCut, FHidden, FLabels, FLines, FBent, FRich, FEmpty, FDrawn: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    procedure Same(const AWhat: string; AGot, AWant: Boolean);
    procedure Str(const AWhat, AGot, AWant: string);
    function Cases: TJSONArray;
    procedure Show(ACase: TJSONObject);
    procedure Finish(AMin: Integer);
    procedure CheckPie(ACase, APie: TJSONObject);
    procedure CheckLabels(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSolverAsUpstream;
    procedure TestTheChartAsUpstream;
    procedure TestTheGuardsWereKept;
    procedure TestOneLabelSeesOnlyTheLastStep;
    procedure TestTheLimitsBendTheSolversLines;
  end;

implementation

{ ---------------- the probe ---------------- }

function TPaProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TPaProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TPaProbe.List: TTyPaintList;
begin
  Result := SeriesList;
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

function AlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahCentre: Result := 'center';
    tahRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

function AlignToOf(const S: string): TTyPieAlignTo;
begin
  if S = 'labelLine' then Result := tpaLabelLine
  else if S = 'edge' then Result := tpaEdge
  else Result := tpaNone;
end;

function FixtureDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim;
end;

{ ---------------- the solver's rect, from a record ---------------- }

function TPaRulesFit.RectOf(const AItem: TTyPieAvoidItem; AIndex: Integer): TTyXYWH;
var
  cw, w, h, y: Double;
  raw: TTyXYWH;
begin
  if Texts[AIndex] = '' then raw := TyXYWH(0, 0, 0, 0)
  else
  begin
    TyPiePlainFit(Texts[AIndex], AItem.HasWidth, AItem.Width, Truncate[AIndex],
      Ellipses[AIndex], Measurer, '', 12, 400, cw);
    Measurer.MeasureLine(Texts[AIndex], '', 12, 400, w, h);
    { the TSpan's box, left and middle }
    y := 0 - h / 2;
    raw := TyXYWH(0, y, (0 + cw) - 0, (y + h) - y);
  end;
  Result := TyPieLabelGlobalRect(raw, AItem.LabelX, AItem.LabelY, OffX[AIndex],
    OffY[AIndex], Rots[AIndex], MarginTypes[AIndex], Margins[AIndex]);
end;

{ ---------------- the test case ---------------- }

procedure TAdvChartPieAvoidTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 120 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartPieAvoidTest.Num(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameNum(AGot, FromHex(AHex)) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartPieAvoidTest.Same(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s: %s upstream, %s here', [AWhat, BoolToStr(AWant, True),
      BoolToStr(AGot, True)]));
end;

procedure TAdvChartPieAvoidTest.Str(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s: "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

function TAdvChartPieAvoidTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

procedure TAdvChartPieAvoidTest.Show(ACase: TJSONObject);
var w, h: Integer;
begin
  w := ACase.Integers['W'];
  h := ACase.Integers['H'];
  FBmp.SetSize(w, h);
  FChart.Option := '{}';
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, w, h);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, w, h), 96);
end;

procedure TAdvChartPieAvoidTest.Finish(AMin: Integer);
begin
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > AMin);
end;

{ an item from a recorded entry }
function ItemOf(R: TJSONObject): TTyPieAvoidItem;
var
  e: TJSONObject;
  ln: TJSONArray;
  k: Integer;
begin
  Result := Default(TTyPieAvoidItem);
  e := R.Objects['entry'];
  Result.Centre := (not IsNull(R.Find('position'))) and (R.Strings['position'] = 'center');
  Result.OuterWord := (not IsNull(R.Find('position'))) and (R.Strings['position'] = 'outer');
  Result.HasLine := not IsNull(e.Find('line'));
  Result.AlignTo := AlignToOf(R.Strings['alignTo']);
  Result.Len := FromHex(R.Strings['len']);
  Result.Len2 := FromHex(R.Strings['len2']);
  Result.LabelDistance := FromHex(R.Strings['labelDistance']);
  Result.EdgeDistance := FromHex(R.Strings['edgeDistance']);
  Result.BleedMargin := FromHex(R.Strings['bleedMargin']);
  Result.HasStyleWidth := not IsNull(R.Find('labelStyleWidth'));
  if not IsNull(R.Find('padding')) then
    Result.PaddingH := FromHex(R.Arrays['padding'].Strings[1])
      + FromHex(R.Arrays['padding'].Strings[3]);
  Result.HasBackground := R.Booleans['background'];
  Result.UnconstrainedWidth := FromHex(e.Strings['unconstrainedWidth']);
  Result.LabelX := FromHex(e.Strings['labelX']);
  Result.LabelY := FromHex(e.Strings['labelY']);
  Result.Rect := RectOf(e.Arrays['rect']);
  if Result.HasLine then
  begin
    ln := e.Arrays['line'];
    for k := 0 to 2 do
      Result.Line[k] := TyPointF(FromHex(TJSONArray(ln.Items[k]).Strings[0]),
        FromHex(TJSONArray(ln.Items[k]).Strings[1]));
  end;
end;

{ THE SOLVER: every plain pie's recorded list straight into TyPieAvoidOverlap }
procedure TAdvChartPieAvoidTest.TestTheSolverAsUpstream;
var
  c, p, i, k, n: Integer;
  cs, pie, it, x: TJSONObject;
  pies, its: TJSONArray;
  items: TTyPieAvoidItemArray;
  fit: TPaRulesFit;
  plain: Boolean;
  r: TTyXYWH;
  ln: TJSONArray;
  ink: TTyLabelSpec;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    pies := cs.Arrays['pies'];
    for p := 0 to pies.Count - 1 do
    begin
      pie := pies.Objects[p];
      its := pie.Arrays['items'];
      plain := True;
      for i := 0 to its.Count - 1 do
        if its.Objects[i].Booleans['rich'] or not IsNull(its.Objects[i].Find('padding'))
          or its.Objects[i].Booleans['background'] then plain := False;
      if not plain then Continue;
      Inc(FPies);
      n := its.Count;
      SetLength(items, n);
      fit := TPaRulesFit.Create;
      try
        fit.Measurer := FSsr;
        SetLength(fit.Texts, n);
        SetLength(fit.Ellipses, n);
        SetLength(fit.Truncate, n);
        SetLength(fit.OffX, n);
        SetLength(fit.OffY, n);
        SetLength(fit.Rots, n);
        SetLength(fit.MarginTypes, n);
        SetLength(fit.Margins, n);
        for i := 0 to n - 1 do
        begin
          it := its.Objects[i];
          items[i] := ItemOf(it);
          { an author's width: the label is measured under it, and the
            solver never touches it }
          if items[i].HasStyleWidth then
          begin
            items[i].HasWidth := True;
            items[i].Width := FromHex(it.Strings['labelStyleWidth']);
          end;
          fit.Texts[i] := it.Strings['text'];
          if IsNull(it.Find('ellipsis')) then fit.Ellipses[i] := '...'
          else fit.Ellipses[i] := it.Strings['ellipsis'];
          fit.Truncate[i] := (not IsNull(it.Find('overflow')))
            and (it.Strings['overflow'] = 'truncate');
          fit.OffX[i] := FromHex(it.Arrays['offset'].Strings[0]);
          fit.OffY[i] := FromHex(it.Arrays['offset'].Strings[1]);
          fit.Rots[i] := FromHex(it.Objects['entry'].Strings['rotation']);
          { computeLabelGlobalRect's margins, through the unit's own rule:
            the label style's margin (minMargin already halved) and type }
          ink := TyLabelSpecNone;
          if not IsNull(it.Find('marginType')) then
          begin
            ink.MarginType := it.Integers['marginType'];
            for k := 0 to 3 do
              ink.MarginLogical[k] := FromHex(it.Arrays['margin'].Strings[k]);
          end;
          TyPieLabelMargin(ink, 1, fit.MarginTypes[i], fit.Margins[i]);
          { the measurement reproduces the entry rect }
          FName := Format('%s pie %d #%d "%s"', [cs.Strings['id'], p, i, fit.Texts[i]]);
          r := fit.RectOf(items[i], i);
          Num('entry rect.x', r.X, it.Objects['entry'].Arrays['rect'].Strings[0]);
          Num('entry rect.y', r.Y, it.Objects['entry'].Arrays['rect'].Strings[1]);
          Num('entry rect.w', r.W, it.Objects['entry'].Arrays['rect'].Strings[2]);
          Num('entry rect.h', r.H, it.Objects['entry'].Arrays['rect'].Strings[3]);
        end;
        if pie.Booleans['ran'] then
          TyPieAvoidOverlap(items, FromHex(pie.Strings['cx']), FromHex(pie.Strings['cy']),
            FromHex(pie.Strings['r']), RectOf(pie.Arrays['view']), @fit.RectOf);
        for i := 0 to n - 1 do
        begin
          it := its.Objects[i];
          x := it.Objects['exit'];
          FName := Format('%s pie %d #%d "%s"', [cs.Strings['id'], p, i, fit.Texts[i]]);
          Inc(FItems);
          if x.Strings['labelY'] <> it.Objects['entry'].Strings['labelY'] then Inc(FMoved);
          Num('label.x', items[i].LabelX, x.Strings['labelX']);
          Num('label.y', items[i].LabelY, x.Strings['labelY']);
          Num('rect.x', items[i].Rect.X, x.Arrays['rect'].Strings[0]);
          Num('rect.y', items[i].Rect.Y, x.Arrays['rect'].Strings[1]);
          Num('rect.w', items[i].Rect.W, x.Arrays['rect'].Strings[2]);
          Num('rect.h', items[i].Rect.H, x.Arrays['rect'].Strings[3]);
          Same('a width', items[i].HasWidth, not IsNull(x.Find('width')));
          if items[i].HasWidth and not IsNull(x.Find('width')) then
          begin
            Inc(FCut);
            Num('width', items[i].Width, x.Strings['width']);
          end;
          Same('a target', items[i].HasTarget, not IsNull(x.Find('target')));
          if items[i].HasTarget and not IsNull(x.Find('target')) then
            Num('target', items[i].Target, x.Strings['target']);
          if items[i].HasLine then
          begin
            ln := x.Arrays['line'];
            for k := 0 to 2 do
            begin
              Num('line x' + IntToStr(k), items[i].Line[k].X, TJSONArray(ln.Items[k]).Strings[0]);
              Num('line y' + IntToStr(k), items[i].Line[k].Y, TJSONArray(ln.Items[k]).Strings[1]);
            end;
          end;
        end;
      finally
        fit.Free;
      end;
    end;
  end;
  Finish(16000);
  AssertTrue(Format('pies compared (%d)', [FPies]), FPies >= 35);
  AssertTrue(Format('labels compared (%d)', [FItems]), FItems >= 800);
  AssertTrue(Format('moved labels compared (%d)', [FMoved]), FMoved >= 400);
  AssertTrue(Format('constrained labels compared (%d)', [FCut]), FCut >= 100);
end;

{ ---------------- the wiring ---------------- }

{ the caption of a pie label: series, datum }
function FindCaption(AList: TTyPaintList; ASeries, AData: Integer): Integer;
var i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Caption.LmKind = 2) and (AList.Element(i).Anim.Role = carLabel)
      and (AList.Element(i).Datum.SeriesIndex = ASeries)
      and (AList.Element(i).Datum.DataIndex = AData) then
      Exit(i);
  Result := -1;
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

{ A LABEL THAT DRAWS NOTHING has no caption here: its words cut to nothing
  (a room under one px), or hidden by minShowLabelAngle before any layout --
  upstream keeps an empty or ignored Text, the port no element }
function DrawsNothing(ACase: TJSONObject; ASeries, AData: Integer): Boolean;
var
  labs, lines: TJSONArray;
  i, k: Integer;
  lb: TJSONObject;
begin
  Result := False;
  labs := ACase.Arrays['labels'];
  for i := 0 to labs.Count - 1 do
  begin
    lb := labs.Objects[i];
    if (lb.Integers['s'] <> ASeries) or (lb.Integers['d'] <> AData) then Continue;
    lines := lb.Arrays['lines'];
    Result := True;
    for k := 0 to lines.Count - 1 do
      if lines.Strings[k] <> '' then Result := False;
    if lb.Booleans['ignore'] and IsNull(lb.Find('mat')) then Result := True;
    Exit;
  end;
end;

{ an item's exit line bent as the last pass bends it }
function BentLine(AItem: TJSONObject): TTyGuidePoints;
var
  ln: TJSONArray;
  k: Integer;
begin
  ln := AItem.Objects['exit'].Arrays['line'];
  for k := 0 to 2 do
    Result[k] := TyPointF(FromHex(TJSONArray(ln.Items[k]).Strings[0]),
      FromHex(TJSONArray(ln.Items[k]).Strings[1]));
  TyLimitTurnAngle(Result, TyGuideJsNumber(AItem.Find('minTurnAngle'), NaN));
  TyLimitSurfaceAngle(Result, FromHex(AItem.Arrays['normal'].Strings[0]),
    FromHex(AItem.Arrays['normal'].Strings[1]),
    TyGuideJsNumber(AItem.Find('maxSurfaceAngle'), NaN));
end;

{ the solver's answers on the elements: label.x / y and the line, bent by
  the two limits [Batch 112] }
procedure TAdvChartPieAvoidTest.CheckPie(ACase, APie: TJSONObject);
var
  its: TJSONArray;
  i, e, g, k, s: Integer;
  it, x: TJSONObject;
  el: TTyChartElement;
  bent: TTyGuidePoints;
begin
  its := APie.Arrays['items'];
  s := APie.Integers['s'];
  for i := 0 to its.Count - 1 do
  begin
    it := its.Objects[i];
    x := it.Objects['exit'];
    FName := Format('%s s%d d%d "%s"', [ACase.Strings['id'], s, it.Integers['d'],
      it.Strings['text']]);
    e := FindCaption(FChart.List, s, it.Integers['d']);
    Inc(FCompared);
    if e >= 0 then
    begin
      el := FChart.List.Element(e);
      Num('label.x', el.Caption.LmBaseX, x.Strings['labelX']);
      Num('label.y', el.Caption.LmBaseY, x.Strings['labelY']);
    end
    else if not DrawsNothing(ACase, s, it.Integers['d']) then
    begin
      Miss('no caption here');
      Continue;
    end;
    if IsNull(x.Find('line')) then Continue;
    g := FindGuide(FChart.List, s, it.Integers['d']);
    if g < 0 then
    begin
      { a line the option does not draw (labelLine.show false, a word other
        than outer / outside): the points steered the label and are gone }
      Continue;
    end;
    Inc(FLines);
    bent := BentLine(it);
    Inc(FCompared);
    if Length(FChart.List.Element(g).Shape.Points) <> 3 then
    begin
      Miss(Format('%d line points here', [Length(FChart.List.Element(g).Shape.Points)]));
      Continue;
    end;
    for k := 0 to 2 do
    begin
      Inc(FCompared, 2);
      if not SameNum(FChart.List.Element(g).Shape.Points[k].X, bent[k].X) then
        Miss(Format('line x%d: %s bent, %s here', [k, Fmt(bent[k].X),
          Fmt(FChart.List.Element(g).Shape.Points[k].X)]));
      if not SameNum(FChart.List.Element(g).Shape.Points[k].Y, bent[k].Y) then
        Miss(Format('line y%d: %s bent, %s here', [k, Fmt(bent[k].Y),
          Fmt(FChart.List.Element(g).Shape.Points[k].Y)]));
    end;
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

{ the words a caption draws, piece by piece }
function DrawnPieces(const C: TTyElementCaption): string;
var i: Integer;
begin
  if Length(C.RtPieces) = 0 then Exit(StringReplace(C.Text, #10, '|', [rfReplaceAll]));
  Result := '';
  for i := 0 to High(C.RtPieces) do
    if C.RtPieces[i].Kind = rpkText then
    begin
      if Result <> '' then Result := Result + '|';
      Result := Result + C.RtPieces[i].Text;
    end;
end;

procedure TAdvChartPieAvoidTest.CheckLabels(ACase: TJSONObject);
var
  labs, mat, lines, pts: TJSONArray;
  i, k, e, g: Integer;
  lb: TJSONObject;
  el: TTyChartElement;
  m: TTyMat2D;
  has: Boolean;
  want: string;
  box: TTyXYWH;
begin
  labs := ACase.Arrays['labels'];
  for i := 0 to labs.Count - 1 do
  begin
    lb := labs.Objects[i];
    FName := Format('%s label s%d d%d "%s"', [ACase.Strings['id'], lb.Integers['s'],
      lb.Integers['d'], lb.Strings['text']]);
    e := FindCaption(FChart.List, lb.Integers['s'], lb.Integers['d']);
    Inc(FCompared);
    if e < 0 then
    begin
      if DrawsNothing(ACase, lb.Integers['s'], lb.Integers['d']) then Inc(FEmpty)
      else Miss('no caption here');
      Continue;
    end;
    el := FChart.List.Element(e);
    Inc(FLabels);
    Same('ignore', el.Ignore, lb.Booleans['ignore']);
    if lb.Booleans['ignore'] then Inc(FHidden);
    if lb.Booleans['truncated'] then Inc(FCut);
    if Length(el.Caption.RtPieces) > 0 then Inc(FRich);
    lines := lb.Arrays['lines'];
    want := '';
    for k := 0 to lines.Count - 1 do
    begin
      if (Length(el.Caption.RtPieces) > 0) and (lines.Strings[k] = '') then Continue;
      if want <> '' then want := want + '|';
      want := want + lines.Strings[k];
    end;
    Str('drawn', DrawnPieces(el.Caption), want);
    mat := lb.Arrays['mat'];
    has := CaptionMat(el.Caption, m);
    Inc(FCompared);
    if has = IsNull(mat) then
      Miss('a transform upstream: ' + BoolToStr(not IsNull(mat), True))
    else if has then
    begin
      for k := 0 to 5 do Num('m' + IntToStr(k), m[k], mat.Strings[k]);
      Num('caption x', el.Caption.X, mat.Strings[4]);
      Num('caption y', el.Caption.Y, mat.Strings[5]);
    end;
    Str('align', AlignName(el.Caption.AnchorH), lb.Strings['align']);
    { the label's own box: a block's every piece (its background as wide as
      the width the solver set plus the padding), a plain one's width }
    if Length(el.Caption.RtPieces) > 0 then
    begin
      box := TyRtBounds(el.Caption.RtPieces);
      Num('local.x', box.X, lb.Arrays['local'].Strings[0]);
      Num('local.y', box.Y, lb.Arrays['local'].Strings[1]);
      Num('local.w', box.W, lb.Arrays['local'].Strings[2]);
      Num('local.h', box.H, lb.Arrays['local'].Strings[3]);
    end
    else
      Num('local.w', el.Caption.LmTextW, lb.Arrays['local'].Strings[2]);
    { the line's ignore follows hideOverlap; its points as drawn, bent by
      the turn limits [Batch 112: they were only counted] }
    if not IsNull(lb.Find('guide')) then
    begin
      g := FindGuide(FChart.List, lb.Integers['s'], lb.Integers['d']);
      if g >= 0 then
      begin
        Same('guide ignore', FChart.List.Element(g).Ignore,
          lb.Objects['guide'].Booleans['ignore']);
        pts := lb.Objects['guide'].Arrays['points'];
        Inc(FCompared);
        if Length(FChart.List.Element(g).Shape.Points) <> pts.Count then
          Miss(Format('%d drawn line points upstream, %d here', [pts.Count,
            Length(FChart.List.Element(g).Shape.Points)]))
        else
          for k := 0 to pts.Count - 1 do
          begin
            Num('drawn line x' + IntToStr(k), FChart.List.Element(g).Shape.Points[k].X,
              TJSONArray(pts.Items[k]).Strings[0]);
            Num('drawn line y' + IntToStr(k), FChart.List.Element(g).Shape.Points[k].Y,
              TJSONArray(pts.Items[k]).Strings[1]);
          end;
        Inc(FDrawn);
      end;
    end;
  end;
end;

procedure TAdvChartPieAvoidTest.TestTheChartAsUpstream;
var
  c, p: Integer;
  cs: TJSONObject;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    FName := cs.Strings['id'];
    Show(cs);
    for p := 0 to cs.Arrays['pies'].Count - 1 do
      CheckPie(cs, cs.Arrays['pies'].Objects[p]);
    CheckLabels(cs);
  end;
  Finish(21000);
  AssertTrue(Format('labels compared (%d)', [FLabels]), FLabels >= 900);
  AssertTrue(Format('label lines compared (%d)', [FLines]), FLines >= 700);
  AssertTrue(Format('cut labels compared (%d)', [FCut]), FCut >= 100);
  AssertTrue(Format('hidden labels compared (%d)', [FHidden]), FHidden >= 30);
  AssertTrue(Format('block labels compared (%d)', [FRich]), FRich >= 50);
  AssertTrue(Format('labels drawing nothing (%d)', [FEmpty]), FEmpty >= 10);
  { every drawn line, the bent ones among them [Batch 112] }
  AssertTrue(Format('drawn label lines compared (%d)', [FDrawn]), FDrawn >= 700);
end;

{ THE LAST PASS (labelLayout.ts:579-583): each solver line, bent by
  limitTurnAngle and limitSurfaceAngle with the item's limits and its
  slice's normal, is the line drawn [Batch 112] }
procedure TAdvChartPieAvoidTest.TestTheLimitsBendTheSolversLines;
var
  c, p, i, j, k: Integer;
  cs, pie, it, lb: TJSONObject;
  its, labs, pts: TJSONArray;
  bent: TTyGuidePoints;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    labs := cs.Arrays['labels'];
    for p := 0 to cs.Arrays['pies'].Count - 1 do
    begin
      pie := cs.Arrays['pies'].Objects[p];
      its := pie.Arrays['items'];
      for i := 0 to its.Count - 1 do
      begin
        it := its.Objects[i];
        if IsNull(it.Objects['exit'].Find('line')) then Continue;
        for j := 0 to labs.Count - 1 do
        begin
          lb := labs.Objects[j];
          if (lb.Integers['s'] <> pie.Integers['s']) or (lb.Integers['d'] <> it.Integers['d'])
            or IsNull(lb.Find('guide')) then Continue;
          FName := Format('%s s%d d%d', [cs.Strings['id'], lb.Integers['s'], lb.Integers['d']]);
          bent := BentLine(it);
          pts := lb.Objects['guide'].Arrays['points'];
          Inc(FCompared);
          if pts.Count <> 3 then
          begin
            Miss(Format('%d drawn points', [pts.Count]));
            Break;
          end;
          for k := 0 to 2 do
          begin
            Num('x' + IntToStr(k), bent[k].X, TJSONArray(pts.Items[k]).Strings[0]);
            Num('y' + IntToStr(k), bent[k].Y, TJSONArray(pts.Items[k]).Strings[1]);
          end;
          Inc(FLines);
          if TJSONArray(pts.Items[1]).AsJSON
            <> TJSONArray(it.Objects['exit'].Arrays['line'].Items[1]).AsJSON then
            Inc(FBent);
          Break;
        end;
      end;
    end;
  end;
  Finish(7000);
  AssertTrue(Format('lines compared (%d)', [FLines]), FLines >= 700);
  AssertTrue(Format('lines the limits bent (%d)', [FBent]), FBent >= 80);
end;

{ the oracle's own mutations of its transcription each changed the cases
  they name }
procedure TAdvChartPieAvoidTest.TestTheGuardsWereKept;
var
  g: TJSONArray;
  i: Integer;
begin
  g := TJSONObject(FRoot).Arrays['guards'];
  AssertTrue('guards', g.Count >= 15);
  for i := 0 to g.Count - 1 do
    AssertTrue(g.Objects[i].Strings['id'], g.Objects[i].Booleans['ok']);
end;

{ TyPlacePieLabel places ONE label, and what one label sees of the solver is
  its last step: the line stood off the label's x again }
procedure TAdvChartPieAvoidTest.TestOneLabelSeesOnlyTheLastStep;
var
  spec: TTyPieLabelSpec;
  lay: TTyPieLayout;
  sec: TTyPieSector;
  p: TTyPieLabelPlacement;
begin
  spec := TyPieLabelSpecDefault;
  lay := Default(TTyPieLayout);
  lay.Valid := True;
  lay.ViewRect := TyRectF(0, 0, 600, 400);
  lay.CX := 300;
  lay.CY := 200;
  lay.R1 := 100;
  sec := Default(TTyPieSector);
  sec.Valid := True;
  sec.CX := 300;
  sec.CY := 200;
  sec.R1 := 100;
  sec.StartRad := -0.3;
  sec.EndRad := 0.1;
  p := TyPlacePieLabel(spec, lay, sec, 96);
  AssertTrue(p.Valid);
  AssertEquals('the line ends distanceToLabelLine short of the label', 5.0,
    p.X - p.P3.X, 1e-9);
  AssertEquals('length2', 30.0, p.P3.X - p.P2.X, 1e-9);
  AssertEquals('length', 15.0, p.LineLen, 0);
  AssertEquals('length2 handed to the solver', 30.0, p.LineLen2, 0);
  AssertEquals('distance handed to the solver', 5.0, p.DistToLine, 0);
  AssertEquals('edgeDistance: 25% of the view width', 150.0, p.EdgeDist, 0);
end;

{ ---------------- plumbing ---------------- }

procedure TAdvChartPieAvoidTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TPaProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixtureDir + 'advchart-pie-avoid.json'));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixtureDir + 'advchart-pie-avoid.json');
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixtureDir + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FSsr := TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']);
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FReport := '';
  FPies := 0;
  FItems := 0;
  FMoved := 0;
  FCut := 0;
  FHidden := 0;
  FLabels := 0;
  FLines := 0;
  FBent := 0;
  FDrawn := 0;
  FRich := 0;
  FEmpty := 0;
end;

procedure TAdvChartPieAvoidTest.TearDown;
begin
  FSsr := nil;
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

initialization
  RegisterTest(TAdvChartPieAvoidTest);
end.
