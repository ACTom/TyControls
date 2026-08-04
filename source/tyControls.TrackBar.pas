unit tyControls.TrackBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Animation;
type
  TTyTrackOrientation = (toHorizontal, toVertical);
  { Which side of the groove the ticks sit on. LCL: TTickMark = (tmBottomRight,
    tmTopLeft, tmBoth), comctrls.pp:2729. Own identifiers so a unit that uses both
    ComCtrls and this one has no ambiguity. }
  TTyTrackTickMark = (ttmBottomRight, ttmTopLeft, ttmBoth);
  { How the ticks are generated. LCL: TTickStyle = (tsNone, tsAuto, tsManual),
    comctrls.pp:2730. ttsAuto = one every Frequency units; ttsManual = only the values
    handed to SetTick, which is how an irregular scale (a gamma curve, a set of stops)
    is expressed. }
  TTyTrackTickStyle = (ttsNone, ttsAuto, ttsManual);

  TTyTrackBar = class(TTyCustomControl)
  private
    FMin, FMax, FPosition: Integer;
    FOrientation: TTyTrackOrientation;
    FReversed: Boolean;
    FTickMarks: TTyTrackTickMark;
    FTickStyle: TTyTrackTickStyle;
    FManualTicks: array of Integer;   // ttsManual: the hand-placed tick values
    FFrequency: Integer;
    FLineSize, FPageSize: Integer;
    FOnChange: TNotifyEvent;
    FThumbHover: Boolean;
    FShowValue: Boolean;
    { 数值读数占掉的那一条(横向在右、纵向在下)的像素宽/高。
      要量文字才知道,而量文字需要一个 painter —— 所以在 RenderTo 里算好缓存下来,
      几何与命中都读这个缓存值。首帧之前它是 0(还没画过的控件也拖不动)。 }
    FValueAreaPx: Integer;
    { 读数文字自身的高度(跨轴方向要让出多少),同样量于绘制、缓存于此:
      AutoSize 的跨轴预期尺寸要用它,而量文字必须有 painter。 }
    FValueTextPx: Integer;

    FAnimEnabled: Boolean;
    FPosAnim: TTyAnimator;      // 0..1 traversal driving FAnimFrom -> FAnimTo
    FAnimFrom, FAnimTo: Single; // displayed-thumb-position endpoints (Min..Max units)
    FTimer: TTimer;             // lazy; only created when actually animating
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure SetOrientation(const AValue: TTyTrackOrientation);
    procedure SetReversed(const AValue: Boolean);
    procedure SetTickMarks(const AValue: TTyTrackTickMark);
    procedure SetTickStyle(const AValue: TTyTrackTickStyle);
    procedure SetFrequency(const AValue: Integer);
    procedure SetLineSize(const AValue: Integer);
    procedure SetPageSize(const AValue: Integer);
    procedure SetShowValue(const AValue: Boolean);
    function  ValueText: string;
    function ThumbWAtPPI(APPI: Integer): Integer;
    function MainLen: Integer;
    function Inverted: Boolean;
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
  protected
    FDragging: Boolean;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    // Current displayed (possibly mid-animation) thumb position, eased between
    // the from/to endpoints. At rest this equals the logical FPosition.
    function DisplayPos: Single;
    // Steppable animation seam (no wall-clock): advance the thumb ease by AMs and
    // return True iff the eased progress changed. The lazy TTimer drives it at
    // runtime; tests drive it directly via an access subclass.
    function AdvanceAnimation(AMs: Integer): Boolean;
    // Force the *animating* path toward AValue (clamped) regardless of handle
    // state. Runtime always routes through SetPosition (which snaps headless);
    // this is the test seam so the animation is reachable without a window.
    procedure SetPositionAnimating(AValue: Integer);
    { AutoSize is republished on the base class already; without this it had nothing to
      ask. CROSS AXIS ONLY, the same split LCL makes in ShouldAutoAdjust
      (include/trackbar.inc:95-107): the length of the track is the form author's call,
      the thickness is what the theme's thumb, ticks and readout actually need. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ThumbRect: TRect;
    procedure DragTo(APos: Integer);
    { Place a tick by hand. Only drawn while TickStyle = ttsManual, which is what makes
      an irregular scale expressible at all; LCL's TCustomTrackBar.SetTick
      (comctrls.pp:2778) is the same call, forwarded to the widget's tick list. Values
      outside Min..Max and duplicates are ignored. }
    procedure SetTick(AValue: Integer);
    { Drop every hand-placed tick. LCL has no counterpart -- its ticks live in the
      widget and are cleared by recreating it -- but a tick list you can only add to is
      a leak in a control that lives as long as the form. }
    procedure ClearTicks;
    { How many hand-placed ticks are set (chiefly so the list is observable). }
    function TickCount: Integer;
    // On by default. When enabled and the control has a window handle, a
    // PROGRAMMATIC Position change (keyboard/wheel) eases the painted thumb to
    // the new value; with no handle (every render test) or while dragging it
    // snaps, preserving exact-pixel tests and live mouse tracking.
    property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;
  published
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property Orientation: TTyTrackOrientation read FOrientation write SetOrientation default toHorizontal;
    { Flip the value axis WITHOUT changing the orientation: a horizontal bar that counts
      down left-to-right, or a vertical bar with Min at the top. It used to be hard-wired
      to the orientation (vertical inverted, horizontal not) with no opt-out, so two of
      the four configurations were unreachable. LCL: comctrls.pp:2789.

      DIFFERS FROM LCL ON THE VERTICAL AXIS, deliberately: this bar's un-reversed
      vertical direction is Max at the top (a volume slider), because that is what makes
      "up increases" true for the keyboard, the wheel and the drag alike -- see KeyDown.
      LCL/Win32's un-reversed vertical is Min at the top, so a ported form that sets
      Reversed on a VERTICAL bar draws the other way round here. Migration: drop
      Reversed on ported vertical bars, set it on ported horizontal ones unchanged. }
    property Reversed: Boolean read FReversed write SetReversed default False;
    { Which side of the groove the ticks are drawn on. LCL: comctrls.pp:2795, same
      default. Ticks used to be nailed to one side (below when horizontal, right when
      vertical), so a slider needing them above its groove could not have them. }
    property TickMarks: TTyTrackTickMark read FTickMarks write SetTickMarks default ttmBottomRight;
    { How the ticks are chosen: ttsAuto (every Frequency units, the default and the old
      behaviour), ttsNone, or ttsManual -- only the values passed to SetTick. LCL:
      comctrls.pp:2796, same default. Frequency = 0 still suppresses the automatic
      ticks, so nothing that relied on that sentinel changes. }
    property TickStyle: TTyTrackTickStyle read FTickStyle write SetTickStyle default ttsAuto;
    { One tick per value-unit, matching LCL's TTrackBar (comctrls.pp: default 1). It
      was 0 here, and 0 means "no ticks" -- so a track bar dropped on a form showed a
      bare groove and the tick marks looked unimplemented rather than switched off. }
    property Frequency: Integer read FFrequency write SetFrequency default 1;
    property LineSize: Integer read FLineSize write SetLineSize default 1;
    property PageSize: Integer read FPageSize write SetPageSize default 10;
    { 在滑轨旁显示当前值(横向在右、纵向在下)。默认关 —— 打开会占掉一条空间,
      不该悄悄改变已有界面的排版。 }
    property ShowValue: Boolean read FShowValue write SetShowValue default False;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
    property OnClick;
  end;

function TyTrackThumbOffset(AMainLen, AThumbLen, AMin, AMax, APos: Integer; AInvert: Boolean): Integer;
function TyTrackPosFromOffset(AMainLen, AThumbLen, AMin, AMax, AOffset: Integer; AInvert: Boolean): Integer;

implementation

function TyTrackThumbOffset(AMainLen, AThumbLen, AMin, AMax, APos: Integer; AInvert: Boolean): Integer;
var travel, span, eff: Integer;
begin
  travel := AMainLen - AThumbLen;
  span := AMax - AMin;
  if (travel <= 0) or (span <= 0) then Exit(0);
  if APos < AMin then APos := AMin;
  if APos > AMax then APos := AMax;
  if AInvert then eff := AMax - APos else eff := APos - AMin;   // distance from the "0-offset" end
  Result := (travel * eff + span div 2) div span;
end;

function TyTrackPosFromOffset(AMainLen, AThumbLen, AMin, AMax, AOffset: Integer; AInvert: Boolean): Integer;
var travel, span, eff: Integer;
begin
  travel := AMainLen - AThumbLen;
  span := AMax - AMin;
  if (travel <= 0) or (span <= 0) then Exit(AMin);
  if AOffset < 0 then AOffset := 0;
  if AOffset > travel then AOffset := travel;
  eff := (AOffset * span + travel div 2) div travel;
  if AInvert then Result := AMax - eff else Result := AMin + eff;
end;

{ TTyTrackBar }

constructor TTyTrackBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FOrientation := toHorizontal;
  FReversed := False;
  FTickMarks := ttmBottomRight;   // LCL's default (comctrls.pp:2795)
  FTickStyle := ttsAuto;          // LCL's default (comctrls.pp:2796)
  FFrequency := 1;
  FLineSize := 1;
  FPageSize := 10;
  FDragging := False;
  FThumbHover := False;
  FAnimEnabled := True;
  // Thumb-glide animator: 0..1 traversal in ~120ms, decelerating. Start settled
  // at the rest endpoint so DisplayPos == FPosition before any change.
  FPosAnim.Progress := 1;
  FPosAnim.Target := 1;
  FPosAnim.DurationMs := 120;
  FPosAnim.Easing := teEaseOutCubic;
  FAnimFrom := FPosition;
  FAnimTo := FPosition;
  Width := 160;
  Height := TyDensityHeight(ActiveController, 24);
end;

destructor TTyTrackBar.Destroy;
begin
  // FTimer is owned by Self (would be freed by DestroyComponents), but free it
  // explicitly first so the OnTimer callback can never fire mid-teardown.
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyTrackBar.GetStyleTypeKey: string;
begin
  Result := 'TyTrackBar';
end;

function TTyTrackBar.ThumbWAtPPI(APPI: Integer): Integer;
begin
  Result := MulDiv(12, APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyTrackBar.MainLen: Integer;
begin
  if FOrientation = toVertical then Result := ClientHeight
  else Result := ClientWidth;
  { 读数占掉的那一条不属于滑轨。收口在这里,ThumbRect 与 DragTo 都走它,
    于是"画在哪"和"点了算多少"不会各算各的。 }
  Dec(Result, FValueAreaPx);
  if Result < 1 then Result := 1;
end;

procedure TTyTrackBar.SetShowValue(const AValue: Boolean);
begin
  if FShowValue = AValue then Exit;
  FShowValue := AValue;
  if not FShowValue then FValueAreaPx := 0;
  Invalidate;
end;

function TTyTrackBar.ValueText: string;
begin
  Result := IntToStr(FPosition);
end;

function TTyTrackBar.Inverted: Boolean;
begin
  { The axis' natural direction (horizontal = Min left, vertical = Max top), flipped by
    Reversed. Every geometry call -- thumb offset, drag, ticks -- reads this one
    function, so there is exactly one place that decides which way the values run. }
  Result := (FOrientation = toVertical) xor FReversed;
end;

procedure TTyTrackBar.SetReversed(const AValue: Boolean);
begin
  if FReversed = AValue then Exit;
  FReversed := AValue;
  Invalidate;
end;

procedure TTyTrackBar.SetTickMarks(const AValue: TTyTrackTickMark);
begin
  if FTickMarks = AValue then Exit;
  FTickMarks := AValue;
  Invalidate;
end;

procedure TTyTrackBar.SetTickStyle(const AValue: TTyTrackTickStyle);
begin
  if FTickStyle = AValue then Exit;
  FTickStyle := AValue;
  Invalidate;
end;

procedure TTyTrackBar.SetTick(AValue: Integer);
var
  i: Integer;
begin
  if (AValue < FMin) or (AValue > FMax) then Exit;
  for i := 0 to High(FManualTicks) do
    if FManualTicks[i] = AValue then Exit;    // a tick placed twice is still one tick
  SetLength(FManualTicks, Length(FManualTicks) + 1);
  FManualTicks[High(FManualTicks)] := AValue;
  if FTickStyle = ttsManual then Invalidate;
end;

procedure TTyTrackBar.ClearTicks;
begin
  if Length(FManualTicks) = 0 then Exit;
  SetLength(FManualTicks, 0);
  if FTickStyle = ttsManual then Invalidate;
end;

function TTyTrackBar.TickCount: Integer;
begin
  Result := Length(FManualTicks);
end;

procedure TTyTrackBar.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, thumbW, tickLen, cross: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  thumbW := ThumbWAtPPI(ppi);
  { The thumb spans the whole cross axis, so it sets the floor; the ticks are drawn
    against the far edge (4 device-independent px, the constant RenderTo scales) and
    would otherwise be painted straight over the thumb. }
  tickLen := MulDiv(4, ppi, 96);
  cross := thumbW + tickLen;
  { A readout needs its own room on top. Its height is measured at paint time and cached
    (FValueTextPx) for the same reason FValueAreaPx is: measuring text needs a painter.
    Before the first paint it is 0, so an AutoSize'd bar settles on its second layout --
    the same first-frame caveat MainLen already carries. }
  if FShowValue and (FValueTextPx > 0) then Inc(cross, FValueTextPx);
  Inc(cross, MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96));
  if cross < 1 then cross := 1;
  { CROSS AXIS ONLY: 0 means "no preference" to LCL, so the track keeps whatever length
    the form gave it and only the thickness follows the theme. }
  if FOrientation = toVertical then
  begin
    PreferredWidth := cross;
    PreferredHeight := 0;
  end
  else
  begin
    PreferredWidth := 0;
    PreferredHeight := cross;
  end;
end;

procedure TTyTrackBar.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;  // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyTrackBar.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then
    Invalidate;
  if not FPosAnim.Running then
    FTimer.Enabled := False;
end;

function TTyTrackBar.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FPosAnim.Advance(AMs);
end;

function TTyTrackBar.DisplayPos: Single;
begin
  Result := TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased);
end;

procedure TTyTrackBar.SetPositionAnimating(AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  // Arm the ease from the currently displayed thumb position to the new target,
  // independent of handle state (test seam). FPosition still tracks the logical
  // value for Min/Max/value semantics.
  FAnimFrom := DisplayPos;
  FAnimTo := Clamped;
  FPosAnim.Progress := 0;
  FPosAnim.Target := 1;
  FPosition := Clamped;
  Invalidate;
end;

function TTyTrackBar.ThumbRect: TRect;
var
  TW, Off: Integer;
  PPI: Integer;
begin
  PPI := Font.PixelsPerInch;
  TW := ThumbWAtPPI(PPI);
  Off := TyTrackThumbOffset(MainLen, TW, FMin, FMax, FPosition, Inverted);
  if FOrientation = toVertical then
    Result := Rect(0, Off, ClientWidth, Off + TW)
  else
    Result := Rect(Off, 0, Off + TW, ClientHeight);
end;

procedure TTyTrackBar.DragTo(APos: Integer);
var
  TW, Off: Integer;
  PPI: Integer;
begin
  PPI := Font.PixelsPerInch;
  TW := ThumbWAtPPI(PPI);
  Off := APos - TW div 2;
  Position := TyTrackPosFromOffset(MainLen, TW, FMin, FMax, Off, Inverted);
end;

procedure TTyTrackBar.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FPosition < FMin then FPosition := FMin;
  Invalidate;
end;

procedure TTyTrackBar.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  Invalidate;
end;

procedure TTyTrackBar.SetPosition(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  if FPosition = Clamped then Exit;
  // Decide how the PAINTED thumb reaches the new value:
  if FDragging then
  begin
    // Live drag: the thumb must track the mouse, so snap instantly.
    FAnimFrom := Clamped;
    FAnimTo := Clamped;
    FPosAnim.SetTargetImmediate(1);
  end
  else if FAnimEnabled and HandleAllocated then
  begin
    // Programmatic change with a window: ease the thumb from where it is now to
    // the new value. (Headless render tests have no handle -> they snap below.)
    FAnimFrom := DisplayPos;
    FAnimTo := Clamped;
    FPosAnim.Progress := 0;
    FPosAnim.Target := 1;
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else
  begin
    // Headless (no handle) or animations off: snap so DisplayPos == new
    // immediately, keeping the existing exact-pixel trackbar tests green.
    FAnimFrom := Clamped;
    FAnimTo := Clamped;
    FPosAnim.SetTargetImmediate(1);
  end;
  FPosition := Clamped;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyTrackBar.SetOrientation(const AValue: TTyTrackOrientation);
var
  w, h: Integer;
begin
  if FOrientation = AValue then Exit;
  FOrientation := AValue;
  { Swap the axis with the orientation, as LCL does. Without it, switching a 200x30 bar to
    vertical left a bar 200 wide and 30 tall drawing a vertical track inside it -- a
    horizontal box containing a vertical control, which every caller then had to fix by
    hand. Not during streaming: the .lfm carries explicit bounds and they must win. }
  if not (csLoading in ComponentState) then
  begin
    w := Width; h := Height;
    if ((AValue = toVertical) and (w > h)) or ((AValue = toHorizontal) and (h > w)) then
      SetBounds(Left, Top, h, w);
  end;
  Invalidate;
end;

procedure TTyTrackBar.SetFrequency(const AValue: Integer);
var
  Clamped: Integer;
begin
  if AValue < 0 then Clamped := 0 else Clamped := AValue;
  if FFrequency = Clamped then Exit;
  FFrequency := Clamped;
  Invalidate;
end;

procedure TTyTrackBar.SetLineSize(const AValue: Integer);
begin
  if AValue < 1 then
    FLineSize := 1
  else
    FLineSize := AValue;
end;

procedure TTyTrackBar.SetPageSize(const AValue: Integer);
begin
  if AValue < 1 then
    FPageSize := 1
  else
    FPageSize := AValue;
end;

procedure TTyTrackBar.KeyDown(var Key: Word; Shift: TShiftState);
var
  DecKey, IncKey: Word;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if FOrientation = toVertical then
  begin
    DecKey := VK_DOWN;
    IncKey := VK_UP;   // up increases (top=max)
  end
  else
  begin
    DecKey := VK_LEFT;
    IncKey := VK_RIGHT;
  end;
  if Key = IncKey then
  begin
    Position := FPosition + FLineSize;
    Key := 0;
  end
  else if Key = DecKey then
  begin
    Position := FPosition - FLineSize;
    Key := 0;
  end
  else
    case Key of
      VK_PRIOR:   // PageUp increases
        begin
          Position := FPosition + FPageSize;
          Key := 0;
        end;
      VK_NEXT:
        begin
          Position := FPosition - FPageSize;
          Key := 0;
        end;
      VK_HOME:
        begin
          Position := FMin;
          Key := 0;
        end;
      VK_END:
        begin
          Position := FMax;
          Key := 0;
        end;
    end;
end;

procedure TTyTrackBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    if FOrientation = toVertical then DragTo(Y) else DragTo(X);
    Invalidate;
  end;
end;

procedure TTyTrackBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  HoverRect: TRect;
  WasHover: Boolean;
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    if FOrientation = toVertical then DragTo(Y) else DragTo(X);
    Invalidate;
  end
  else
  begin
    HoverRect := ThumbRect;
    WasHover := FThumbHover;
    FThumbHover := (X >= HoverRect.Left) and (X < HoverRect.Right)
               and (Y >= HoverRect.Top) and (Y < HoverRect.Bottom);
    if FThumbHover <> WasHover then
      Invalidate;
  end;
end;

procedure TTyTrackBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := False;
    Invalidate;
  end;
end;

procedure TTyTrackBar.MouseLeave;
begin
  inherited MouseLeave;
  FThumbHover := False;
  // FDragging is NOT cleared here: drag ends on MouseUp only, so dragging
  // outside the control bounds and back stays consistent.
  Invalidate;
end;

function TTyTrackBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  // Let the published OnMouseWheel/Up/Down events fire first; if a handler marks
  // the wheel handled, honor that and do not step.
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if not Enabled then Exit;
  // Convention: match the native LCL TTrackBar slider -> wheel-up
  // (WheelDelta > 0) INCREASES Position by LineSize; wheel-down decreases it.
  Position := Position + Sign(WheelDelta) * FLineSize;
  Result := True;
end;

procedure TTyTrackBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, ThumbS: TTyStyleSet;
  R, ThumbR: TRect;
  ThumbStates: TTyStateSet;
  TW, MLen, Off: Integer;
  TickFill: TTyFill;
  TickLen, TickW, V, TickOff, Idx: Integer;
  vs, vw: TSize;

  { One tick at cross-axis-independent offset AC along the track, on whichever side(s)
    TickMarks names. Nested so the two generators (auto/manual) cannot drift apart on
    where a tick is drawn -- which is exactly how the side got hard-coded before. }
  procedure DrawTickAt(AC: Integer);
  begin
    if FOrientation = toVertical then
    begin
      if FTickMarks in [ttmBottomRight, ttmBoth] then
        P.FillBackground(Rect(R.Right - TickLen, R.Top + AC,
          R.Right, R.Top + AC + TickW), TickFill, 0);
      if FTickMarks in [ttmTopLeft, ttmBoth] then
        P.FillBackground(Rect(R.Left, R.Top + AC,
          R.Left + TickLen, R.Top + AC + TickW), TickFill, 0);
    end
    else
    begin
      if FTickMarks in [ttmBottomRight, ttmBoth] then
        P.FillBackground(Rect(R.Left + AC, R.Bottom - TickLen,
          R.Left + AC + TickW, R.Bottom), TickFill, 0);
      if FTickMarks in [ttmTopLeft, ttmBoth] then
        P.FillBackground(Rect(R.Left + AC, R.Top,
          R.Left + AC + TickW, R.Top + TickLen), TickFill, 0);
    end;
  end;

begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);

    // Compute thumb geometry using APPI for pixel-exact rendering.
    // Horizontal goes through the non-inverted branch of TyTrackThumbOffset,
    // which equals the legacy formula exactly (pixel regression).
    TW := MulDiv(12, APPI, 96);
    if TW < 1 then TW := 1;
    { 读数条:先量出它要多宽(按 Min/Max 里更宽的那个算,免得拖动时滑轨长度
      跟着位数变来变去、滑块自己抖),再把滑轨缩短同样多。 }
    if FShowValue then
    begin
      vs := P.MeasureText(IntToStr(FMin), S.FontName, ResolveFontSize(S), S.FontWeight);
      vw := P.MeasureText(IntToStr(FMax), S.FontName, ResolveFontSize(S), S.FontWeight);
      if vs.cx > vw.cx then vw := vs;
      FValueTextPx := vw.cy;    // cached for CalculatePreferredSize
      if FOrientation = toVertical then
        FValueAreaPx := vw.cy + MulDiv(4, APPI, 96)
      else
        FValueAreaPx := vw.cx + MulDiv(8, APPI, 96);
    end
    else
    begin
      FValueAreaPx := 0;
      FValueTextPx := 0;
    end;

    if FOrientation = toVertical then
      MLen := (R.Bottom - R.Top) - FValueAreaPx
    else
      MLen := (R.Right - R.Left) - FValueAreaPx;
    if MLen < 1 then MLen := 1;
    // The PAINTED thumb uses the displayed (possibly mid-animation) position; at
    // rest DisplayPos == FPosition so headless renders are pixel-identical. The
    // hover hit-test (ThumbRect), DragTo, hit math and keyboard keep using
    // FPosition for exact value semantics.
    Off := TyTrackThumbOffset(MLen, TW, FMin, FMax, Round(DisplayPos), Inverted);
    if FOrientation = toVertical then
      ThumbR := Rect(R.Left, R.Top + Off, R.Right, R.Top + Off + TW)
    else
      ThumbR := Rect(R.Left + Off, R.Top, R.Left + Off + TW, R.Bottom);

    // Resolve thumb style with hover/drag states
    ThumbStates := [];
    if FDragging then
      Include(ThumbStates, tysActive)
    else if FThumbHover then
      Include(ThumbStates, tysHover)
    else
      Include(ThumbStates, tysNormal);
    ThumbS := ActiveController.Model.ResolveStyle('TyTrackThumb', '', ThumbStates);

    if (tpBackground in ThumbS.Present) then
      P.FillBackground(ThumbR, ThumbS.Background, ThumbS.BorderRadius);

    { Tick marks. Which VALUES get one is TickStyle's call (auto = every Frequency
      units, manual = only the hand-placed ones); which SIDE they are drawn on is
      TickMarks'. Theme-driven colour (S.TextColor) either way. }
    if (FTickStyle <> ttsNone) and (FMax > FMin) then
    begin
      TickLen := P.Scale(4);
      TickW := P.Scale(1);
      if TickW < 1 then TickW := 1;
      TickFill := Default(TTyFill);
      TickFill.Kind := tfkSolid;
      TickFill.Color := S.TextColor;

      if FTickStyle = ttsManual then
      begin
        for Idx := 0 to High(FManualTicks) do
        begin
          { A tick the range has since moved past is not drawn -- TyTrackThumbOffset
            clamps, which would otherwise pile it onto an end and invent a mark. }
          if (FManualTicks[Idx] < FMin) or (FManualTicks[Idx] > FMax) then Continue;
          TickOff := TyTrackThumbOffset(MLen, TW, FMin, FMax, FManualTicks[Idx], Inverted);
          DrawTickAt(TickOff + TW div 2);
        end;
      end
      else if FFrequency > 0 then
      begin
        V := FMin;
        while V <= FMax do
        begin
          TickOff := TyTrackThumbOffset(MLen, TW, FMin, FMax, V, Inverted);
          DrawTickAt(TickOff + TW div 2);
          Inc(V, FFrequency);
        end;
      end;
    end;

    { 读数。画在滑轨让出来的那一条里,颜色/字体全走本体样式,不硬编码。 }
    if FShowValue and (FValueAreaPx > 0) then
    begin
      if FOrientation = toVertical then
        P.DrawText(Rect(R.Left, R.Bottom - FValueAreaPx, R.Right, R.Bottom),
          ValueText, S.FontName, ResolveFontSize(S), S.FontWeight, S.TextColor,
          taCenter, tlCenter, False)
      else
        P.DrawText(Rect(R.Right - FValueAreaPx, R.Top, R.Right, R.Bottom),
          ValueText, S.FontName, ResolveFontSize(S), S.FontWeight, S.TextColor,
          taRightJustify, tlCenter, False);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyTrackBar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
