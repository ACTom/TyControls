unit tyControls.AdvChart.AnimView;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the enter animations, between the paint list and the
  engine. [Batch 89, AN2]

  THE BINDING. A chart element is a record in a list that is rebuilt on every
  static render; an animation has to outlive that. So what animates is a
  PROXY -- a TTyAnimBag holding upstream's own props for one of upstream's
  elements (a bar's shape.x/y/width/height, a symbol's scaleX/scaleY and
  style.opacity, a line's clip rect) -- keyed by (series, view row, role).
  The builders tag each element with its role and the numbers upstream
  animates it in (TTyChartElement.Anim); Arm makes the proxies and starts
  their enter animations exactly as upstream's views do; Bind finds each
  element's proxy again after a rebuild; and a FRAME is the list with every
  bound element rewritten from its proxy's current values, which is what the
  dynamic layer draws while the clips run.

  WHAT EACH ROLE ANIMATES (wf86 3A/3B, the views cited there):
    bar          shape.height (or width laid on its side) 0 -> layout, enter
                 timing at the row (BarView.ts:241-314, 784-788)
    symbol       a scatter symbol path: scaleX/Y 0 -> size/2, style.opacity
                 0 -> its own, about the path's origin (Symbol.ts:184-200)
    lineSymbol   a line's symbol group: scale 0 -> 1, 200 ms, no easing,
                 delay = duration * (where the clip reaches it) + delay, or
                 the delay function at the row; ignores the threshold
                 (LineView.ts:1078-1177)
    lineClip     the line's clip rect grows along the base axis, enter timing
                 with no row; `clip: false` widens it after the call, and
                 the forced tracks write the unwidened rect back on the next
                 frame -- upstream's, kept (createClipPathFromCoordSys.ts)
    sector       a pie slice sweeps both angles out of the first slice's
                 start, or grows r from r0 for animationType 'scale'
                 (PieView.ts:55-130)
    funnel       style.opacity 0 -> its own (FunnelView.ts:70-79)
    gaugePointer rotation from the start angle, no row
    gaugeProgress shape.endAngle from the start angle, no row; its round
                 end cap follows the end (GaugeView.ts:464-483)
    radarLine,   shape.points out of the centre; both always, the area even
    radarArea    where nothing fills it (RadarView.ts:106-130)
    candle       shape.points: every point's value coordinate out of the
                 open price's (CandlestickView.ts:117-128, 326-332)
    label        LabelManager's first appearance: style.opacity 0 -> 1 at
                 the row, for a series that animates and a label that does
                 not count its value; a line symbol's own, 300 ms from 0,
                 the symbol's delay (LabelManager.ts:528-563)
    guide        a label line's style.strokePercent 0 -> 1, no row

  A LABEL FOLLOWS ITS HOST. zrender recomputes a text's place from its
  host's current rect every frame, so a bar's 'top' label rides the bar up;
  a frame moves each such label by the difference between its anchor on the
  host as drawn and on the host at rest.

  A PROXY AT REST IS THE LAYOUT. Every key is compared with the value the
  layout gave it; while all are equal the element is drawn untouched, so a
  finished animation draws exactly the static picture. A key that rests one
  unit in the last place off -- the final step computes (to - from) * 1 +
  from -- draws there, as upstream's does. }
interface
uses SysUtils, Classes, Math, contnrs,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Anim,
  tyControls.AdvChart.AnimOpt;

type
  TTyChartAnimProxy = class(TTyAnimBag)
  private
    FSeries, FIndex: Integer;
    FRole: string;
    FFinal: TTyAnimProps;
  public
    constructor Create(ASeries, AIndex: Integer; const ARole: string);
    { the values the layout gave every key }
    procedure SetFinal(const AProps: TTyAnimProps);
    function FinalOf(const AKey: string): TTyAnimValue;
    { every key at its layout value, bit for bit }
    function AtFinal: Boolean;
    property Series: Integer read FSeries;
    property Index: Integer read FIndex;
    property Role: string read FRole;
    property Final: TTyAnimProps read FFinal;
  end;

  TTyChartAnimProxyArray = array of TTyChartAnimProxy;

  { WHAT ARMING NEEDS TO KNOW OF ONE SERIES, by series index. }
  TTyChartAnimSeries = record
    Present: Boolean;
    Model: TTyAnimModel;
    { isAnimationEnabled: `animation` and the threshold }
    Enabled: Boolean;
    { seriesModel.get('animation') alone -- a line's symbols and their
      labels pop in above the threshold too }
    On_: Boolean;
    { a pie: animationType 'scale'; and the shared start angle of a first
      render, the first slice's that is a number }
    PieScale: Boolean;
    HasPieStart: Boolean;
    PieStart: Double;
    { LabelManager fades this series' labels in (the types this batch
      animates); label.valueAnimation turns the fade off }
    LabelFade: Boolean;
    LabelValueAnim: Boolean;
    { the base axis runs across the screen: a candle stands upright }
    BaseHoriz: Boolean;
  end;
  TTyChartAnimSeriesArray = array of TTyChartAnimSeries;

  TTyChartAnimSet = class
  private
    FItems: TFPList;
    FIndex: TFPHashList;
    FAnimation: TTyAnimation;
    procedure NoOp;
    function Make(ASeries, AIndex: Integer; const ARole: string): TTyChartAnimProxy;
    procedure ArmOne(AList: TTyPaintList; AAt: Integer; const AEl: TTyChartElement;
      const AC: TTyChartAnimSeries);
  public
    constructor Create(AAnimation: TTyAnimation);
    destructor Destroy; override;
    { every proxy freed, its clips taken off the driver }
    procedure Clear;
    function Count: Integer;
    function Item(AIndex: Integer): TTyChartAnimProxy;
    function Find(ASeries, AIndex: Integer; const ARole: string): TTyChartAnimProxy;
    { The enter animation of everything in AList that asks for one and has
      no proxy yet, as upstream's views start it. ASeries by series index. }
    procedure Arm(AList: TTyPaintList; const ASeries: TTyChartAnimSeriesArray);
    { the proxy each element reads, by insertion index; nil for none }
    function Bind(AList: TTyPaintList): TTyChartAnimProxyArray;
  end;

{ The proxy a role reads: several roles share one (a line's run and area its
  clip, a candle's body and wicks, a progress arc and its end cap). }
function TyChartAnimProxyRole(ARole: TTyChartAnimRole): string;
{ One element as its proxy says it is now. }
procedure TyAnimApply(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
{ ADest := ASource with every bound element applied and every following label
  moved with its host. Insertion indices are kept, so a hit on the frame names
  the same element as a hit on the list. }
procedure TyAnimBuildFrame(ASource, ADest: TTyPaintList;
  const ABind: TTyChartAnimProxyArray);
{ A shape scaled by (AFX, AFY) about (ACX, ACY). }
procedure TyShapeScaleAbout(var AShape: TTyChartShape; ACX, ACY, AFX, AFY: Double);
{ The first APercent of a polyline's length, as zrender's strokePercent draws
  it (PathProxy.rebuildPath). }
function TyPolylinePrefix(const APoints: TTyPointFArray; APercent: Double): TTyPointFArray;

implementation

uses tyControls.AdvChart.Labels, tyControls.AdvChart.Data;

{ ==================== the proxy ==================== }

constructor TTyChartAnimProxy.Create(ASeries, AIndex: Integer; const ARole: string);
begin
  inherited Create;
  FSeries := ASeries;
  FIndex := AIndex;
  FRole := ARole;
end;

procedure TTyChartAnimProxy.SetFinal(const AProps: TTyAnimProps);
var i: Integer;
begin
  SetLength(FFinal, Length(AProps));
  for i := 0 to High(AProps) do
  begin
    FFinal[i].Key := AProps[i].Key;
    FFinal[i].Value := TyAnimClone(AProps[i].Value);
  end;
end;

function TTyChartAnimProxy.FinalOf(const AKey: string): TTyAnimValue;
var i: Integer;
begin
  for i := 0 to High(FFinal) do
    if FFinal[i].Key = AKey then Exit(TyAnimClone(FFinal[i].Value));
  Result := TyAnimNull;
end;

function SameBitsD(A, B: Double): Boolean;
var qa, qb: QWord;
begin
  Move(A, qa, SizeOf(qa));
  Move(B, qb, SizeOf(qb));
  Result := qa = qb;
end;

function TTyChartAnimProxy.AtFinal: Boolean;
var
  i, k: Integer;
  v: TTyAnimValue;
begin
  for i := 0 to High(FFinal) do
  begin
    v := GetAnimProp(FFinal[i].Key);
    if v.Kind <> FFinal[i].Value.Kind then Exit(False);
    case v.Kind of
      avkNumber, avkBool:
        if not SameBitsD(v.Num, FFinal[i].Value.Num) then Exit(False);
      avkArray:
        begin
          if Length(v.Arr) <> Length(FFinal[i].Value.Arr) then Exit(False);
          for k := 0 to High(v.Arr) do
            if not SameBitsD(v.Arr[k], FFinal[i].Value.Arr[k]) then Exit(False);
        end;
      avkString:
        if v.Str <> FFinal[i].Value.Str then Exit(False);
    end;
  end;
  Result := True;
end;

{ ==================== the set ==================== }

function KeyOf(ASeries, AIndex: Integer; const ARole: string): ShortString;
begin
  Result := IntToStr(ASeries) + ':' + IntToStr(AIndex) + ':' + ARole;
end;

constructor TTyChartAnimSet.Create(AAnimation: TTyAnimation);
begin
  inherited Create;
  FAnimation := AAnimation;
  FItems := TFPList.Create;
  FIndex := TFPHashList.Create;
end;

destructor TTyChartAnimSet.Destroy;
begin
  Clear;
  FIndex.Free;
  FItems.Free;
  inherited Destroy;
end;

procedure TTyChartAnimSet.Clear;
var i: Integer;
begin
  for i := FItems.Count - 1 downto 0 do TObject(FItems[i]).Free;
  FItems.Clear;
  FIndex.Clear;
end;

function TTyChartAnimSet.Count: Integer;
begin
  Result := FItems.Count;
end;

function TTyChartAnimSet.Item(AIndex: Integer): TTyChartAnimProxy;
begin
  Result := TTyChartAnimProxy(FItems[AIndex]);
end;

function TTyChartAnimSet.Find(ASeries, AIndex: Integer;
  const ARole: string): TTyChartAnimProxy;
begin
  Result := TTyChartAnimProxy(FIndex.Find(KeyOf(ASeries, AIndex, ARole)));
end;

procedure TTyChartAnimSet.NoOp;
begin
  { the line clip's done: upstream passes one, and a done makes the
    animation forced -- every key a track, changed or not }
end;

function TTyChartAnimSet.Make(ASeries, AIndex: Integer;
  const ARole: string): TTyChartAnimProxy;
begin
  Result := TTyChartAnimProxy.Create(ASeries, AIndex, ARole);
  Result.Animation := FAnimation;
  FItems.Add(Result);
  FIndex.Add(KeyOf(ASeries, AIndex, ARole), Result);
end;

function TyChartAnimProxyRole(ARole: TTyChartAnimRole): string;
begin
  case ARole of
    carBar: Result := 'bar';
    carSymbol: Result := 'symbol';
    carLineSymbol: Result := 'lineSymbol';
    carLineRun, carLineArea: Result := 'lineClip';
    carSector: Result := 'sector';
    carFunnel: Result := 'funnel';
    carGaugePointer: Result := 'gaugePointer';
    carGaugeProgress, carGaugeCap: Result := 'gaugeProgress';
    carRadarLine: Result := 'radarLine';
    carRadarArea: Result := 'radarArea';
    carCandleBody, carCandleWickHigh, carCandleWickLow: Result := 'candle';
    carLabel: Result := 'label';
    carGuide: Result := 'guide';
  else
    Result := '';
  end;
end;

function KeyIndexOf(const AEl: TTyChartElement): Integer;
begin
  if AEl.Anim.Role in [carLineRun, carLineArea] then Result := -1
  else Result := AEl.Anim.Index;
end;

function Num1(const AKey: string; AValue: Double): TTyAnimProp;
begin
  Result := TyAnimProp(AKey, TyAnimNum(AValue));
end;

{ A timing option as a number the way a line's symbols read it: a function
  called with null, a number as it is, anything else not one. }
function TimingNumber(const AV: TTyAnimOptValue; AIndex: Integer;
  AHasIndex: Boolean): Double;
var h: TTyAnimTimingHandler;
begin
  case AV.Kind of
    aokNumber, aokBool: Result := AV.Num;
    aokString: Result := TyJsToNumber(AV.Str);
    aokHandler:
      if TyChartFindAnimTiming(AV.Str, h) and Assigned(h) then
        Result := h(AIndex, AHasIndex)
      else
        Result := NaN;
  else
    Result := NaN;
  end;
end;

{ LineView._initSymbolLabelAnimation's delay for the symbol at AEl:
  G = [x, y, clip x, y, width, height, flags] -- flag 1 a clip, 2 a
  horizontal base axis, 4 an inverse one. }
function LineSymbolDelay(const AEl: TTyChartElement;
  const AC: TTyChartAnimSeries): Double;
var
  flags: Integer;
  start, stop, cur, ratio, dur, del: Double;
  durV, delV: TTyAnimOptValue;
  hasClip: Boolean;
begin
  flags := Round(AEl.Anim.G[6]);
  hasClip := (flags and 1) <> 0;
  { undefined === undefined: no clip is a ratio of nought }
  ratio := 0;
  if hasClip then
  begin
    if (flags and 2) <> 0 then
    begin
      start := AEl.Anim.G[2];
      stop := AEl.Anim.G[2] + AEl.Anim.G[4];
      cur := AEl.Anim.G[0];
    end
    else
    begin
      start := AEl.Anim.G[3] + AEl.Anim.G[5];
      stop := AEl.Anim.G[3];
      cur := AEl.Anim.G[1];
    end;
    if stop = start then ratio := 0
    else ratio := (cur - start) / (stop - start);
  end;
  if (flags and 4) <> 0 then ratio := 1 - ratio;
  { seriesDuration, a function called with null }
  durV := TyAnimGetShallow(AC.Model, 'animationDuration');
  dur := TimingNumber(durV, -1, False);
  { `animationDelay || 0` }
  delV := TyAnimGetShallow(AC.Model, 'animationDelay');
  if not TyAnimOptTruthy(delV) then
    Result := dur * ratio + 0
  else if delV.Kind = aokHandler then
    Result := TimingNumber(delV, AEl.Anim.Index, True)
  else
  begin
    del := TimingNumber(delV, -1, False);
    Result := dur * ratio + del;
  end;
end;

procedure TTyChartAnimSet.ArmOne(AList: TTyPaintList; AAt: Integer;
  const AEl: TTyChartElement; const AC: TTyChartAnimSeries);
var
  p: TTyChartAnimProxy;
  props: TTyAnimProps;
  idx, k, n: Integer;
  opts: TTyAnimCallOpts;
  cfg: TTyAnimCfg;
  x, y, w, h, ex, half, delay: Double;
  flags: Integer;
  host: TTyChartElement;
  ring, from: TTyDoubleArray;
  pts: TTyPointFArray;

  procedure Start(const AProps: TTyAnimProps; const AOpts: TTyAnimCallOpts);
  begin
    TyInitProps(p, AProps, AC.Model, AOpts);
  end;

  { the radar's two, from one ring: polygon first, as RadarView adds them }
  procedure ArmRadar(const ARole: string);
  var q: TTyChartAnimProxy;
  begin
    if Find(AEl.Anim.Series, idx, ARole) <> nil then Exit;
    q := Make(AEl.Anim.Series, idx, ARole);
    q.Attr(TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ring, 2))]));
    q.SetFinal(TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ring, 2))]));
    q.SetAnimProp('shape.points', TyAnimArr(from, 2));
    TyInitProps(q, TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ring, 2))]),
      AC.Model, TyAnimCallAt(idx));
  end;

begin
  idx := KeyIndexOf(AEl);
  half := Pi / 2;
  case AEl.Anim.Role of
    carBar:
      begin
        p := Make(AEl.Anim.Series, idx, 'bar');
        props := TyAnimProps([Num1('shape.x', AEl.Anim.G[0]),
          Num1('shape.y', AEl.Anim.G[1]), Num1('shape.width', AEl.Anim.G[2]),
          Num1('shape.height', AEl.Anim.G[3])]);
        p.Attr(props);
        p.SetFinal(props);
        { the creator zeroes the length only for a series that animates }
        if AC.Enabled then
        begin
          if AEl.Anim.G[4] <> 0 then p.SetNum('shape.height', 0)
          else p.SetNum('shape.width', 0);
        end;
        Start(props, TyAnimCallAt(idx));
      end;
    carSymbol:
      begin
        p := Make(AEl.Anim.Series, idx, 'symbol');
        props := TyAnimProps([Num1('scaleX', AEl.Anim.G[2]),
          Num1('scaleY', AEl.Anim.G[3]), Num1('style.opacity', AEl.Anim.G[4])]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('scaleX', 0);
        p.SetNum('scaleY', 0);
        p.SetNum('style.opacity', 0);
        Start(props, TyAnimCallAt(idx));
      end;
    carLineSymbol:
      begin
        if not AC.On_ then Exit;
        p := Make(AEl.Anim.Series, idx, 'lineSymbol');
        props := TyAnimProps([Num1('scaleX', 1), Num1('scaleY', 1)]);
        p.SetFinal(props);
        p.Attr(TyAnimProps([Num1('scaleX', 0), Num1('scaleY', 0)]));
        { a raw animateTo: no easing, no scope }
        cfg := TyAnimCfg(200, LineSymbolDelay(AEl, AC), '');
        cfg.SetToFinal := True;
        p.AnimateTo(props, cfg);
      end;
    carLineRun, carLineArea:
      begin
        p := Make(AEl.Anim.Series, -1, 'lineClip');
        x := AEl.Anim.G[0];
        y := AEl.Anim.G[1];
        w := AEl.Anim.G[2];
        h := AEl.Anim.G[3];
        ex := AEl.Anim.G[4];
        flags := Round(AEl.Anim.G[5]);
        props := TyAnimProps([Num1('shape.x', x), Num1('shape.y', y),
          Num1('shape.width', w), Num1('shape.height', h)]);
        p.Attr(props);
        { the start rect: nothing of it along the base axis }
        if (flags and 2) <> 0 then
        begin
          if (flags and 4) <> 0 then p.SetNum('shape.x', x + w);
          p.SetNum('shape.width', 0);
        end
        else
        begin
          if (flags and 4) = 0 then p.SetNum('shape.y', y + h);
          p.SetNum('shape.height', 0);
        end;
        opts := TyAnimCallNoIndex;
        opts.Done := @NoOp;
        Start(props, opts);
        { `clip: false` widens across the base axis AFTER the call; what the
          static layer draws is the widened rect }
        if ex > 0 then
        begin
          if (flags and 2) <> 0 then
          begin
            p.SetNum('shape.y', p.Num('shape.y') - ex);
            p.SetNum('shape.height', p.Num('shape.height') + ex * 2);
            props[1].Value := TyAnimNum(y - ex);
            props[3].Value := TyAnimNum(h + ex * 2);
          end
          else
          begin
            p.SetNum('shape.x', p.Num('shape.x') - ex);
            p.SetNum('shape.width', p.Num('shape.width') + ex * 2);
            props[0].Value := TyAnimNum(x - ex);
            props[2].Value := TyAnimNum(w + ex * 2);
          end;
        end;
        p.SetFinal(props);
      end;
    carSector:
      begin
        p := Make(AEl.Anim.Series, idx, 'sector');
        props := TyAnimProps([Num1('shape.cx', AEl.Anim.G[0]),
          Num1('shape.cy', AEl.Anim.G[1]), Num1('shape.r0', AEl.Anim.G[2]),
          Num1('shape.r', AEl.Anim.G[3]), Num1('shape.startAngle', AEl.Anim.G[4]),
          Num1('shape.endAngle', AEl.Anim.G[5])]);
        p.Attr(props);
        p.SetFinal(props);
        if AC.PieScale then
        begin
          p.SetNum('shape.r', AEl.Anim.G[2]);
          Start(TyAnimProps([Num1('shape.r', AEl.Anim.G[3])]), TyAnimCallAt(idx));
        end
        else if AC.HasPieStart then
        begin
          p.SetNum('shape.startAngle', AC.PieStart);
          p.SetNum('shape.endAngle', AC.PieStart);
          Start(TyAnimProps([Num1('shape.startAngle', AEl.Anim.G[4]),
            Num1('shape.endAngle', AEl.Anim.G[5])]), TyAnimCallAt(idx));
        end;
      end;
    carFunnel:
      begin
        p := Make(AEl.Anim.Series, idx, 'funnel');
        props := TyAnimProps([Num1('style.opacity', AEl.Style.Alpha)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('style.opacity', 0);
        Start(props, TyAnimCallAt(idx));
      end;
    carGaugePointer:
      begin
        p := Make(AEl.Anim.Series, idx, 'gaugePointer');
        props := TyAnimProps([Num1('rotation', -(AEl.Anim.G[2] + half))]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('rotation', -(AEl.Anim.G[3] + half));
        Start(props, TyAnimCallNoIndex);
      end;
    carGaugeProgress:
      begin
        p := Make(AEl.Anim.Series, idx, 'gaugeProgress');
        props := TyAnimProps([Num1('shape.cx', AEl.Anim.G[0]),
          Num1('shape.cy', AEl.Anim.G[1]), Num1('shape.r0', AEl.Anim.G[2]),
          Num1('shape.r', AEl.Anim.G[3]), Num1('shape.startAngle', AEl.Anim.G[4]),
          Num1('shape.endAngle', AEl.Anim.G[5])]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('shape.endAngle', AEl.Anim.G[4]);
        Start(TyAnimProps([Num1('shape.endAngle', AEl.Anim.G[5])]),
          TyAnimCallNoIndex);
      end;
    carRadarLine, carRadarArea:
      begin
        pts := AEl.Shape.Points;
        n := Length(pts);
        if n = 0 then Exit;
        { the ring, closed: the line carries the closing point, the area
          does not }
        if AEl.Anim.Role = carRadarLine then
        begin
          SetLength(ring, n * 2);
          for k := 0 to n - 1 do
          begin
            ring[k * 2] := pts[k].X;
            ring[k * 2 + 1] := pts[k].Y;
          end;
        end
        else
        begin
          SetLength(ring, (n + 1) * 2);
          for k := 0 to n - 1 do
          begin
            ring[k * 2] := pts[k].X;
            ring[k * 2 + 1] := pts[k].Y;
          end;
          ring[n * 2] := pts[0].X;
          ring[n * 2 + 1] := pts[0].Y;
        end;
        SetLength(from, Length(ring));
        for k := 0 to Length(ring) div 2 - 1 do
        begin
          from[k * 2] := AEl.Anim.G[0];
          from[k * 2 + 1] := AEl.Anim.G[1];
        end;
        ArmRadar('radarArea');
        ArmRadar('radarLine');
      end;
    carCandleBody, carCandleWickHigh, carCandleWickLow:
      begin
        p := Make(AEl.Anim.Series, idx, 'candle');
        { [low-high body end x2, the other end x2, highest, body top,
          lowest, body bottom] -- candlestickLayout.ts' ends }
        SetLength(ring, 16);
        if AC.BaseHoriz then
        begin
          ring[0] := AEl.Anim.G[6];  ring[1] := AEl.Anim.G[1];
          ring[2] := AEl.Anim.G[7];  ring[3] := AEl.Anim.G[1];
          ring[4] := AEl.Anim.G[7];  ring[5] := AEl.Anim.G[2];
          ring[6] := AEl.Anim.G[6];  ring[7] := AEl.Anim.G[2];
          ring[8] := AEl.Anim.G[5];  ring[9] := AEl.Anim.G[3];
          ring[10] := AEl.Anim.G[5]; ring[11] := AEl.Anim.G[1];
          ring[12] := AEl.Anim.G[5]; ring[13] := AEl.Anim.G[4];
          ring[14] := AEl.Anim.G[5]; ring[15] := AEl.Anim.G[2];
        end
        else
        begin
          ring[0] := AEl.Anim.G[1];  ring[1] := AEl.Anim.G[6];
          ring[2] := AEl.Anim.G[1];  ring[3] := AEl.Anim.G[7];
          ring[4] := AEl.Anim.G[2];  ring[5] := AEl.Anim.G[7];
          ring[6] := AEl.Anim.G[2];  ring[7] := AEl.Anim.G[6];
          ring[8] := AEl.Anim.G[3];  ring[9] := AEl.Anim.G[5];
          ring[10] := AEl.Anim.G[1]; ring[11] := AEl.Anim.G[5];
          ring[12] := AEl.Anim.G[4]; ring[13] := AEl.Anim.G[5];
          ring[14] := AEl.Anim.G[2]; ring[15] := AEl.Anim.G[5];
        end;
        from := Copy(ring, 0, 16);
        for k := 0 to 7 do
          if AC.BaseHoriz then from[k * 2 + 1] := AEl.Anim.G[0]
          else from[k * 2] := AEl.Anim.G[0];
        props := TyAnimProps([TyAnimProp('shape.points', TyAnimArr(ring, 2))]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetAnimProp('shape.points', TyAnimArr(from, 2));
        Start(props, TyAnimCallAt(idx));
      end;
    carLabel:
      begin
        host := Default(TTyChartElement);
        if (AEl.Anim.HostPlus1 > 0) and (AEl.Anim.HostPlus1 <= AList.Count) then
          host := AList.Element(AEl.Anim.HostPlus1 - 1);
        props := TyAnimProps([Num1('style.opacity', 1)]);
        if host.Anim.Role = carLineSymbol then
        begin
          { the symbol's own: from 0 over 300 ms, the symbol's delay }
          if not AC.On_ then Exit;
          delay := LineSymbolDelay(host, AC);
          p := Make(AEl.Anim.Series, idx, 'label');
          p.Attr(props);
          p.SetFinal(props);
          cfg := TyAnimCfg(300, delay, '');
          p.AnimateFrom(TyAnimProps([Num1('style.opacity', 0)]), cfg);
          Exit;
        end;
        if not (AC.Enabled and AC.LabelFade) or AC.LabelValueAnim then Exit;
        p := Make(AEl.Anim.Series, idx, 'label');
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('style.opacity', 0);
        Start(props, TyAnimCallAt(idx));
      end;
    carGuide:
      begin
        if not AC.Enabled then Exit;
        p := Make(AEl.Anim.Series, idx, 'guide');
        props := TyAnimProps([Num1('style.strokePercent', 1)]);
        p.Attr(props);
        p.SetFinal(props);
        p.SetNum('style.strokePercent', 0);
        Start(props, TyAnimCallNoIndex);
      end;
  end;
  if AAt < 0 then ;
end;

procedure TTyChartAnimSet.Arm(AList: TTyPaintList;
  const ASeries: TTyChartAnimSeriesArray);
var
  i, s: Integer;
  el: TTyChartElement;
  role: string;
begin
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if el.Anim.Role = carNone then Continue;
    { a cap is armed by its arc, which comes after it in the list }
    if el.Anim.Role = carGaugeCap then Continue;
    s := el.Anim.Series;
    if (s < 0) or (s > High(ASeries)) or not ASeries[s].Present then Continue;
    role := TyChartAnimProxyRole(el.Anim.Role);
    if Find(s, KeyIndexOf(el), role) <> nil then Continue;
    ArmOne(AList, i, el, ASeries[s]);
  end;
end;

function TTyChartAnimSet.Bind(AList: TTyPaintList): TTyChartAnimProxyArray;
var
  i: Integer;
  el: TTyChartElement;
begin
  Result := nil;
  if (AList = nil) or (FItems.Count = 0) then Exit;
  SetLength(Result, AList.Count);
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if el.Anim.Role = carNone then
      Result[i] := nil
    else
      Result[i] := Find(el.Anim.Series, KeyIndexOf(el),
        TyChartAnimProxyRole(el.Anim.Role));
  end;
end;

{ ==================== geometry ==================== }

procedure TyShapeScaleAbout(var AShape: TTyChartShape; ACX, ACY, AFX, AFY: Double);
var
  i: Integer;
  f: Double;

  function SX(AV: Double): Double;
  begin
    Result := ACX + (AV - ACX) * AFX;
  end;

  function SY(AV: Double): Double;
  begin
    Result := ACY + (AV - ACY) * AFY;
  end;

begin
  f := Min(Abs(AFX), Abs(AFY));
  case AShape.Kind of
    cskRect, cskRoundRect, cskPath:
      begin
        AShape.Bounds := TyRectF(SX(AShape.Bounds.Left), SY(AShape.Bounds.Top),
          SX(AShape.Bounds.Right), SY(AShape.Bounds.Bottom));
        for i := 0 to 3 do AShape.Radii[i] := AShape.Radii[i] * f;
        AShape.RotCX := SX(AShape.RotCX);
        AShape.RotCY := SY(AShape.RotCY);
      end;
    cskCircle:
      begin
        AShape.CX := SX(AShape.CX);
        AShape.CY := SY(AShape.CY);
        if AFX = AFY then
          AShape.R1 := AShape.R1 * Abs(AFX)
        else
        begin
          AShape.Kind := cskEllipse;
          AShape.R0 := AShape.R1 * Abs(AFX);
          AShape.R1 := AShape.R1 * Abs(AFY);
        end;
      end;
    cskEllipse:
      begin
        AShape.CX := SX(AShape.CX);
        AShape.CY := SY(AShape.CY);
        AShape.R0 := AShape.R0 * Abs(AFX);
        AShape.R1 := AShape.R1 * Abs(AFY);
      end;
    cskSector:
      begin
        AShape.CX := SX(AShape.CX);
        AShape.CY := SY(AShape.CY);
        AShape.R0 := AShape.R0 * f;
        AShape.R1 := AShape.R1 * f;
        for i := 0 to 3 do AShape.SectorRadii[i] := AShape.SectorRadii[i] * f;
      end;
    cskPolyline, cskPolygon:
      begin
        AShape.Points := Copy(AShape.Points, 0, Length(AShape.Points));
        for i := 0 to High(AShape.Points) do
          AShape.Points[i] := TyPointF(SX(AShape.Points[i].X), SY(AShape.Points[i].Y));
        AShape.Cmds := Copy(AShape.Cmds, 0, Length(AShape.Cmds));
        for i := 0 to High(AShape.Cmds) do
        begin
          AShape.Cmds[i].X1 := SX(AShape.Cmds[i].X1);
          AShape.Cmds[i].Y1 := SY(AShape.Cmds[i].Y1);
          AShape.Cmds[i].X2 := SX(AShape.Cmds[i].X2);
          AShape.Cmds[i].Y2 := SY(AShape.Cmds[i].Y2);
          AShape.Cmds[i].X := SX(AShape.Cmds[i].X);
          AShape.Cmds[i].Y := SY(AShape.Cmds[i].Y);
        end;
        if AShape.HasCmdBounds then
          AShape.CmdBounds := TyRectF(SX(AShape.CmdBounds.Left),
            SY(AShape.CmdBounds.Top), SX(AShape.CmdBounds.Right),
            SY(AShape.CmdBounds.Bottom));
      end;
  end;
end;

function TyPolylinePrefix(const APoints: TTyPointFArray; APercent: Double): TTyPointFArray;
var
  i, n: Integer;
  total, want, seg, acc, t: Double;
begin
  n := Length(APoints);
  if (APercent >= 1) or (n < 2) then Exit(Copy(APoints, 0, n));
  Result := nil;
  if not (APercent > 0) then Exit;
  total := 0;
  for i := 1 to n - 1 do
    total := total + Hypot(APoints[i].X - APoints[i - 1].X,
      APoints[i].Y - APoints[i - 1].Y);
  want := total * APercent;
  SetLength(Result, n);
  Result[0] := APoints[0];
  acc := 0;
  for i := 1 to n - 1 do
  begin
    seg := Hypot(APoints[i].X - APoints[i - 1].X, APoints[i].Y - APoints[i - 1].Y);
    if acc + seg >= want then
    begin
      if seg > 0 then t := (want - acc) / seg else t := 0;
      Result[i] := TyPointF(APoints[i - 1].X + (APoints[i].X - APoints[i - 1].X) * t,
        APoints[i - 1].Y + (APoints[i].Y - APoints[i - 1].Y) * t);
      SetLength(Result, i + 1);
      Exit;
    end;
    acc := acc + seg;
    Result[i] := APoints[i];
  end;
end;

{ Nothing of it drawn and nothing of it hit, in this frame. }
procedure MakeInkless(var AEl: TTyChartElement);
begin
  AEl.Style.HasFill := False;
  AEl.Style.StrokeWidthLogical := 0;
  AEl.Caption.Text := '';
  AEl.Silent := True;
end;

function SectorFrom(const AEl: TTyChartElement; P: TTyChartAnimProxy): TTyChartShape;
begin
  Result := TyShapeSector(P.Num('shape.cx'), P.Num('shape.cy'), P.Num('shape.r0'),
    P.Num('shape.r'), P.Num('shape.startAngle'), P.Num('shape.endAngle'));
  Result.SectorRadii := AEl.Shape.SectorRadii;
end;

procedure TyAnimApply(var AEl: TTyChartElement; AProxy: TTyChartAnimProxy);
var
  x, y, w, h, fx, fy, a, d, c, s, cx, cy: Double;
  r: TTyRectF;
  v: TTyAnimValue;
  i, n: Integer;
  pts: TTyPointFArray;
  radii: array[0..3] of Double;
begin
  if (AProxy = nil) or AProxy.AtFinal then Exit;
  case AEl.Anim.Role of
    carBar:
      begin
        x := AProxy.Num('shape.x');
        y := AProxy.Num('shape.y');
        w := AProxy.Num('shape.width');
        h := AProxy.Num('shape.height');
        r := TyRectF(Min(x, x + w), Min(y, y + h), Max(x, x + w), Max(y, y + h));
        if AEl.Shape.Kind = cskRoundRect then
        begin
          for i := 0 to 3 do radii[i] := AEl.Shape.Radii[i];
          AEl.Shape := TyShapeRoundRect(r, radii);
        end
        else
          AEl.Shape := TyShapeRect(r);
      end;
    carSymbol, carLineSymbol:
      begin
        if AEl.Anim.Role = carSymbol then
        begin
          if AEl.Anim.G[2] <> 0 then fx := AProxy.Num('scaleX') / AEl.Anim.G[2]
          else fx := 1;
          if AEl.Anim.G[3] <> 0 then fy := AProxy.Num('scaleY') / AEl.Anim.G[3]
          else fy := 1;
          AEl.Style.Alpha := AProxy.Num('style.opacity');
        end
        else
        begin
          fx := AProxy.Num('scaleX');
          fy := AProxy.Num('scaleY');
        end;
        if (fx = 0) or (fy = 0) or IsNan(fx) or IsNan(fy) then
        begin
          MakeInkless(AEl);
          TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1], 0, 0);
        end
        else
          TyShapeScaleAbout(AEl.Shape, AEl.Anim.G[0], AEl.Anim.G[1], fx, fy);
        if AEl.Caption.HasHostBox then
        begin
          AEl.Caption.HostBox.X := AEl.Anim.G[0] + (AEl.Caption.HostBox.X - AEl.Anim.G[0]) * fx;
          AEl.Caption.HostBox.Y := AEl.Anim.G[1] + (AEl.Caption.HostBox.Y - AEl.Anim.G[1]) * fy;
          AEl.Caption.HostBox.W := AEl.Caption.HostBox.W * fx;
          AEl.Caption.HostBox.H := AEl.Caption.HostBox.H * fy;
        end;
      end;
    carLineRun, carLineArea:
      begin
        x := AProxy.Num('shape.x');
        y := AProxy.Num('shape.y');
        AEl.HasClip := True;
        AEl.ClipRect := TyRectF(x, y, x + AProxy.Num('shape.width'),
          y + AProxy.Num('shape.height'));
      end;
    carSector, carGaugeProgress:
      AEl.Shape := SectorFrom(AEl, AProxy);
    carGaugeCap:
      begin
        a := AProxy.Num('shape.endAngle');
        AEl.Shape.CX := AEl.Anim.G[0] + Cos(a) * AEl.Anim.G[2];
        AEl.Shape.CY := AEl.Anim.G[1] + Sin(a) * AEl.Anim.G[2];
      end;
    carFunnel:
      AEl.Style.Alpha := AProxy.Num('style.opacity');
    carGaugePointer:
      begin
        { the needle's angle is upstream's rotation turned back: the static
          needle turned about the hub by the difference }
        a := -AProxy.Num('rotation') - Pi / 2;
        d := a - AEl.Anim.G[2];
        cx := AEl.Anim.G[0];
        cy := AEl.Anim.G[1];
        if AEl.Shape.Kind = cskPath then
          AEl.Shape.RotationRad := AEl.Shape.RotationRad + d
        else
        begin
          c := Cos(d);
          s := Sin(d);
          AEl.Shape.Points := Copy(AEl.Shape.Points, 0, Length(AEl.Shape.Points));
          for i := 0 to High(AEl.Shape.Points) do
          begin
            x := AEl.Shape.Points[i].X - cx;
            y := AEl.Shape.Points[i].Y - cy;
            AEl.Shape.Points[i] := TyPointF(cx + x * c - y * s, cy + x * s + y * c);
          end;
        end;
      end;
    carRadarLine, carRadarArea:
      begin
        v := AProxy.GetAnimProp('shape.points');
        n := Length(v.Arr) div 2;
        if AEl.Anim.Role = carRadarArea then Dec(n);
        if n < 0 then n := 0;
        SetLength(pts, n);
        for i := 0 to n - 1 do pts[i] := TyPointF(v.Arr[i * 2], v.Arr[i * 2 + 1]);
        AEl.Shape.Points := pts;
      end;
    carCandleBody, carCandleWickHigh, carCandleWickLow:
      begin
        v := AProxy.GetAnimProp('shape.points');
        if Length(v.Arr) < 16 then Exit;
        { UPRIGHT when the body's first two points differ across -- they
          share the value coordinate either way, the same at every frame }
        if v.Arr[0] <> v.Arr[2] then
        begin
          if AEl.Anim.Role = carCandleBody then
          begin
            r := TyRectF(v.Arr[0], Min(v.Arr[1], v.Arr[5]), v.Arr[2],
              Max(v.Arr[1], v.Arr[5]));
            if r.Bottom - r.Top < 1 then r.Bottom := r.Top + 1;
            AEl.Shape := TyShapeRect(r);
          end
          else if AEl.Anim.Role = carCandleWickHigh then
            AEl.Shape.Points := [TyPointF(v.Arr[8], v.Arr[9]),
              TyPointF(v.Arr[10], v.Arr[11])]
          else
            AEl.Shape.Points := [TyPointF(v.Arr[12], v.Arr[13]),
              TyPointF(v.Arr[14], v.Arr[15])];
        end
        else
        begin
          if AEl.Anim.Role = carCandleBody then
          begin
            r := TyRectF(Min(v.Arr[0], v.Arr[4]), v.Arr[1], Max(v.Arr[0], v.Arr[4]),
              v.Arr[3]);
            if r.Right - r.Left < 1 then r.Right := r.Left + 1;
            AEl.Shape := TyShapeRect(r);
          end
          else if AEl.Anim.Role = carCandleWickHigh then
            AEl.Shape.Points := [TyPointF(v.Arr[8], v.Arr[9]),
              TyPointF(v.Arr[10], v.Arr[11])]
          else
            AEl.Shape.Points := [TyPointF(v.Arr[12], v.Arr[13]),
              TyPointF(v.Arr[14], v.Arr[15])];
        end;
      end;
    carLabel:
      begin
        a := AProxy.Num('style.opacity');
        if a <= 0 then MakeInkless(AEl)
        else AEl.Style.Alpha := AEl.Style.Alpha * a;
      end;
    carGuide:
      begin
        a := AProxy.Num('style.strokePercent');
        AEl.Shape.Points := TyPolylinePrefix(AEl.Shape.Points, a);
        if Length(AEl.Shape.Points) < 2 then MakeInkless(AEl);
      end;
  end;
end;

{ Where a following label's anchor is on a host as given. }
procedure AnchorOn(const AHost: TTyChartElement; const ALabel: TTyChartElement;
  out AX, AY: Double);
var
  b: TTyRectF;
  atX, atY: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  box: TTyXYWH;
begin
  if AHost.Caption.HasHostBox then
  begin
    box := AHost.Caption.HostBox;
    atX := ALabel.Anim.LabelAtX;
    atY := ALabel.Anim.LabelAtY;
    if ALabel.Anim.LabelAtXPct then atX := atX * box.W;
    if ALabel.Anim.LabelAtYPct then atY := atY * box.H;
    TyLabelAnchorXYWH(box, TTyLabelPosition(ALabel.Anim.LabelPos),
      ALabel.Anim.LabelDist, atX, atY, AX, AY, ah, av);
    Exit;
  end;
  b := TyShapeBounds(AHost.Shape);
  b.Left := b.Left - ALabel.Anim.LabelInflate;
  b.Top := b.Top - ALabel.Anim.LabelInflate;
  b.Right := b.Right + ALabel.Anim.LabelInflate;
  b.Bottom := b.Bottom + ALabel.Anim.LabelInflate;
  atX := ALabel.Anim.LabelAtX;
  atY := ALabel.Anim.LabelAtY;
  if ALabel.Anim.LabelAtXPct then atX := atX * (b.Right - b.Left);
  if ALabel.Anim.LabelAtYPct then atY := atY * (b.Bottom - b.Top);
  TyLabelAnchor(b, TTyLabelPosition(ALabel.Anim.LabelPos), ALabel.Anim.LabelDist,
    atX, atY, AX, AY, ah, av);
end;

procedure TyAnimBuildFrame(ASource, ADest: TTyPaintList;
  const ABind: TTyChartAnimProxyArray);
var
  i, h: Integer;
  el, hostS, hostF: TTyChartElement;
  x0, y0, x1, y1, dx, dy: Double;
begin
  if (ASource = nil) or (ADest = nil) then Exit;
  ADest.Clear;
  for i := 0 to ASource.Count - 1 do
  begin
    el := ASource.Element(i);
    if (i <= High(ABind)) and (ABind[i] <> nil) then TyAnimApply(el, ABind[i]);
    h := el.Anim.HostPlus1 - 1;
    if (el.Anim.Role = carLabel) and (h >= 0) and (h < i)
      and (h <= High(ABind)) and (ABind[h] <> nil) and not ABind[h].AtFinal then
    begin
      hostS := ASource.Element(h);
      hostF := ADest.Element(h);
      AnchorOn(hostS, el, x0, y0);
      AnchorOn(hostF, el, x1, y1);
      dx := x1 - x0;
      dy := y1 - y0;
      if (not IsNan(dx)) and (not IsNan(dy)) and ((dx <> 0) or (dy <> 0)) then
      begin
        el.Caption.X := el.Caption.X + dx;
        el.Caption.Y := el.Caption.Y + dy;
        el.Shape.Bounds := TyRectF(el.Shape.Bounds.Left + dx, el.Shape.Bounds.Top + dy,
          el.Shape.Bounds.Right + dx, el.Shape.Bounds.Bottom + dy);
      end;
    end;
    ADest.Add(el);
  end;
end;

end.
