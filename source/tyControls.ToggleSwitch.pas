unit tyControls.ToggleSwitch;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Animation;

{ Pure knob-X geometry (device pixels). Progress is clamped to [0,1]:
    OffX = AMarginDev (knob at left margin)
    OnX  = ATrackWidthDev - AMarginDev - AKnobSideDev (knob at right margin)
  Result interpolates OffX..OnX by AProgress via TyLerpI. }
function TyToggleKnobX(ATrackWidthDev, AMarginDev, AKnobSideDev: Integer;
  AProgress: Single): Integer;

type
  TTyToggleSwitch = class(TTyCustomControl)
  private
    FChecked: Boolean;
    FCaption: TCaption;
    FOnChange: TNotifyEvent;
    FKnobAnim: TTyAnimator;
    FAnimationsEnabled: Boolean;
    FTimer: TTimer;
    FRefitting: Boolean;   // guards the AutoSize re-fit in Invalidate against re-entry
    procedure SetChecked(const AValue: Boolean);
    procedure SetCaption(const AValue: TCaption);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    function GetKnobAnimProgress: Single;
  protected
    function GetStyleTypeKey: string; override;
    function CurrentStates: TTyStateSet; override;
    { The size the caption actually needs, in DEVICE px at APPI. Measured with the SAME
      measurer the paint draws with (see the implementation), so what AutoSize reserves and
      what RenderTo puts on screen cannot drift. AHeight is the reference line height ('Ag'),
      returned for callers that want the caption's natural height — the switch itself never
      proposes one (see CalculatePreferredSize). }
    procedure MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
    { The width the switch needs: its pill zone plus — when there IS a caption — the gap and
      the measured caption, i.e. exactly the strip RenderTo hands to DrawText. Without this a
      switch keeps the width the .lfm gave it and a caption that outgrows it (a longer
      translation, a bigger theme font, another platform's default font) is simply cut off. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { A theme switch reaches every control as a bare Invalidate, and the new theme's font
      changes the width the caption needs — so an AutoSize switch must re-fit here too. }
    procedure Invalidate; override;
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    // Steppable animation seam (no wall-clock): advance the knob slide by AMs
    // and return True iff the eased progress changed. Tests drive this directly
    // via an access subclass; the lazy TTimer drives it at runtime.
    function AdvanceAnimation(AMs: Integer): Boolean;
    // Arm the knob slide toward ATarget without snapping (Progress is left where
    // it is so AdvanceAnimation can interpolate). Test seam only — at runtime
    // the slide is driven by SetChecked + the lazy TTimer.
    procedure ArmKnobAnim(ATarget: Single);
    // Raw (un-eased) knob progress, 0..1. Exposed for deterministic tests.
    property KnobAnimProgress: Single read GetKnobAnimProgress;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Toggle;
    procedure Click; override;
    // On by default. When enabled and the control has a window handle, flipping
    // Checked animates the knob slide; with no handle (every render test) it
    // snaps, preserving the existing exact-pixel toggle tests.
    property AnimationsEnabled: Boolean read FAnimationsEnabled write FAnimationsEnabled default True;
  published
    { Off by default (a designed switch keeps the width the .lfm gave it). Switch it on and the
      control WIDENS to hug its pill plus its caption, so a caption that grows — a longer
      translation, a theme with a bigger or heavier font, a platform whose default font measures
      wider — lengthens the switch instead of being cut off. Height is left alone (see
      CalculatePreferredSize): it belongs to whoever lays out the row. }
    property AutoSize;
    property Checked: Boolean read FChecked write SetChecked default False;
    // Optional text label drawn to the RIGHT of the switch (TToggleBox parity).
    // Empty (the default) renders the bare switch unchanged.
    property Caption: TCaption read FCaption write SetCaption;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { The constructor turns this on (Space toggles a focused switch); declaring the default
      to match is what lets a host turn it OFF in the .lfm — against the inherited
      `default False` that value is dropped as "already the default". }
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;

implementation

function TyToggleKnobX(ATrackWidthDev, AMarginDev, AKnobSideDev: Integer;
  AProgress: Single): Integer;
var
  OffX, OnX: Integer;
begin
  OffX := AMarginDev;
  OnX := ATrackWidthDev - AMarginDev - AKnobSideDev;
  if AProgress < 0 then AProgress := 0
  else if AProgress > 1 then AProgress := 1;
  Result := TyLerpI(OffX, OnX, AProgress);
end;

{ TTyToggleSwitch }

constructor TTyToggleSwitch.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FChecked := False;
  FAnimationsEnabled := True;
  // Knob slide animator: rest at 0 (off), ~120ms full traversal, decelerating.
  FKnobAnim.Progress := 0;
  FKnobAnim.Target := 0;
  FKnobAnim.DurationMs := 120;
  FKnobAnim.Easing := teEaseOutCubic;
  Height := TyDensityHeight(ActiveController, 24);   { classic 24 / modern --control-height }
  Width := MulDiv(Height, 44, 24);                   { keep the 44:24 pill aspect at any density }
end;

destructor TTyToggleSwitch.Destroy;
begin
  // FTimer is owned by Self (would be freed by DestroyComponents), but free it
  // explicitly first so the OnTimer callback can never fire mid-teardown.
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyToggleSwitch.GetStyleTypeKey: string;
begin
  Result := 'TyToggleSwitch';
end;

function TTyToggleSwitch.CurrentStates: TTyStateSet;
begin
  Result := inherited CurrentStates;
  if FChecked then
    Include(Result, tysActive);
end;

procedure TTyToggleSwitch.SetChecked(const AValue: Boolean);
begin
  if FChecked = AValue then Exit;
  FChecked := AValue;
  FKnobAnim.Target := Ord(AValue);
  if FAnimationsEnabled and HandleAllocated then
  begin
    // Animate: keep the current raw progress and let the lazy TTimer step the
    // knob toward the new target. Only reachable with a real window handle.
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else
    // Headless (no window handle) or animations off: snap so paint is correct
    // immediately. Because every render test runs handle-less, this keeps the
    // existing exact-pixel toggle tests green regardless of the default.
    FKnobAnim.SetTargetImmediate(Ord(AValue));
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyToggleSwitch.SetCaption(const AValue: TCaption);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  // 新标题要的宽度变了,所以 AutoSize 的开关必须重新贴合。
  // (标题是本控件自己的字段,不走 TControl.Caption,所以钩子在这里而不是 TextChanged。)
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyToggleSwitch.Invalidate;
begin
  inherited Invalidate;
  { 换肤时每个控件收到的只是一个裸 Invalidate(TTyStyleController 向注册控件广播),而新主题
    带来的是另一套字体 —— 标题需要的宽度也就跟着变了。不在这里重新贴合,控件就会留着旧主题
    的宽度,标题被切掉;TTyButton / TTyBadge 出于同样的理由也在自己的 Invalidate 里重量。
    FRefitting 挡住重入:AdjustSize -> SetBounds -> Invalidate 会递归。}
  if AutoSize and not FRefitting and not (csDestroying in ComponentState) then
  begin
    FRefitting := True;
    try
      InvalidatePreferredSize;
      AdjustSize;
    finally
      FRefitting := False;
    end;
  end;
end;

procedure TTyToggleSwitch.MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
{ 用 TTyPainter 量,而不是 LCL canvas:标题是 P.DrawText 以 BGRA 字体度量画出来的,只有同一个
  度量器给出的宽度才等于这些字形真正占的位置。画布传 nil —— BeginPaint 只建内部位图,EndPaint
  见 canvas 为 nil 就不 blit、直接释放,所以在 paint 周期之外调用安全且不泄漏
  (TTySegmented / TTyBadge 用的是同一套写法)。 }
var
  P: TTyPainter;
  S: TTyStyleSet;
  fs: Integer;
  sz: TSize;
begin
  AWidth := 0;
  AHeight := 0;
  // 和 RenderTo 画标题时用的是同一份已解析样式(字体名/字号/字重都取自它)。
  S := CurrentStyle;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1:什么都不画,只量
    fs := ResolveFontSize(S);
    // 稳定的参考字形:空标题也给出一行的高度。
    sz := P.MeasureText('Ag', S.FontName, fs, S.FontWeight);
    AHeight := sz.cy;
    // 空标题时 RenderTo 一个字都不画,所以宽度是 0,不是某个占位字符串的宽度。
    if FCaption <> '' then
      AWidth := P.MeasureText(FCaption, S.FontName, fs, S.FontWeight).cx;
    P.EndPaint;   // nil canvas -> 不 blit,只释放度量位图
  finally
    P.Free;
  end;
  if AWidth < 0 then AWidth := 0;
  if AHeight < 1 then AHeight := 1;
end;

procedure TTyToggleSwitch.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  ppi, devH, switchW, tw, th: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  { 开关区的宽度完全由高度推出(44:24 的药丸比例)—— RenderTo 里 SwitchW 的同一条式子。
    这个控件是无边框的窗口化控件,Paint 把 ClientRect 交给 RenderTo,所以那里的 DevH 就是
    这里的 Height。宽度依赖高度、高度不依赖宽度,所以两者之间不会来回弹。 }
  devH := Height;
  if devH < 1 then devH := 1;
  switchW := MulDiv(devH, 44, 24);
  MeasureCaption(ppi, tw, th);
  PreferredWidth := switchW;
  { 有标题时,RenderTo 把标题画进 [开关区右缘 + TyCheckBoxGap, 客户区右缘],左对齐并裁剪到
    这个矩形 —— 少算一个像素就是吃掉标题最后一个字。所以这里必须把间隙和标题都算进来。
    (TyToggleSwitch 的绘制路径不使用 padding 令牌 —— 主题也没给它 —— 所以预留里也没有
    padding:预留必须等于绘制,多算和少算一样是撒谎。) }
  if FCaption <> '' then
    Inc(PreferredWidth, MulDiv(TyCheckBoxGap, ppi, 96) + tw);
  if PreferredWidth < 1 then PreferredWidth := 1;
  { 只管宽度 —— 0 是 LCL 的"这个轴上没有意见",高度就留给排版方。开关同时提议高度,就会和
    任何钉死高度的容器打架(TTyToolBar 把每个子控件都压到 ButtonHeight),两边来回弹到 LCL
    以 "TControl.ChangeBounds loop detected" 中止。想要标题自然高度的调用方可以自己读
    MeasureCaption。 }
  PreferredHeight := 0;
end;

procedure TTyToggleSwitch.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;  // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyToggleSwitch.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then
    Invalidate;
  if not FKnobAnim.Running then
    FTimer.Enabled := False;
end;

function TTyToggleSwitch.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FKnobAnim.Advance(AMs);
end;

procedure TTyToggleSwitch.ArmKnobAnim(ATarget: Single);
begin
  FKnobAnim.Target := ATarget;
end;

function TTyToggleSwitch.GetKnobAnimProgress: Single;
begin
  Result := FKnobAnim.Progress;
end;

procedure TTyToggleSwitch.Toggle;
begin
  SetChecked(not FChecked);
end;

procedure TTyToggleSwitch.Click;
begin
  if not Enabled then Exit;
  Toggle;
  inherited Click;
end;

procedure TTyToggleSwitch.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if (Key = VK_SPACE) or (Key = VK_RETURN) then
  begin
    Toggle;
    Key := 0;
  end;
end;

procedure TTyToggleSwitch.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, TrackS, KnobStyle: TTyStyleSet;
  R, FullR, CaptionRect: TRect;
  TrackRadius: Integer;
  DevH, Margin, KnobSide, KnobLogical, KnobX, KnobRadiusLogical: Integer;
  SwitchW, Gap: Integer;
  KnobRect: TRect;
  KnobFill: TTyFill;
begin
  P := TTyPainter.Create;
  try
    // FullR = the whole client; R = the SWITCH zone. With no caption the switch
    // fills the client (R = FullR) so existing exact-pixel toggle tests are
    // unchanged. With a caption, the switch is constrained to a fixed-width zone
    // on the LEFT (its natural 44:24 aspect relative to the device height) and
    // the caption is drawn to the right of it.
    FullR := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    R := FullR;
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;

    // This is a WINDOWED control (unlike TTyLabel, a graphic control that draws straight over the
    // parent's painted surface). The track + caption cover only part of the client, so fill the
    // WHOLE background with the parent's themed surface first -- otherwise the uncovered strips
    // (around the pill, behind the caption) show the raw parent LCL Color (e.g. the OS grey on a
    // title bar). Solid + image themes both handled here.
    TyFillParentBg(Self, P, FullR, S);

    DevH := R.Bottom - R.Top;
    if FCaption <> '' then
    begin
      // Natural switch width keeps the default 44:24 aspect (→ exactly 44 dev-px
      // at the 24px default height), purely height-derived so it is theme-safe.
      SwitchW := MulDiv(DevH, 44, 24);
      if SwitchW > (FullR.Right - FullR.Left) then
        SwitchW := FullR.Right - FullR.Left;
      R.Right := R.Left + SwitchW;
    end;

    // Build a track style with a pill border-radius.
    // If the theme supplies a BorderRadius, use it; otherwise half the device height.
    TrackS := S;
    if TrackS.BorderRadius = 0 then
    begin
      // Compute logical radius so that Scale() → device half-height
      TrackRadius := MulDiv(DevH, 96, APPI) div 2;
      TrackS.BorderRadius := TrackRadius;
    end;
    DrawFrame(P, R, TrackS);

    // Knob geometry (device pixels)
    Margin := P.Scale(3);
    KnobSide := DevH - 2 * Margin;
    if KnobSide < 1 then KnobSide := 1;

    // Pure geometry seam: Progress = eased knob-animator position. With
    // animations off (the headless/test default) SetChecked snaps the animator,
    // so this equals Ord(FChecked) and the knob lands exactly on Off/On.
    KnobX := TyToggleKnobX(R.Right - R.Left, Margin, KnobSide, FKnobAnim.Eased);

    KnobRect := Rect(KnobX, Margin, KnobX + KnobSide, Margin + KnobSide);

    // Knob is its own sub-element typeKey (TyToggleKnob): both its fill color and
    // its border-radius come from there, not the parent's TextColor/BorderRadius.
    KnobStyle := ActiveController.Model.ResolveStyle('TyToggleKnob', '', []);

    // Logical knob values for FillBackground (which calls Scale internally).
    // Cap the token (TyToggleKnob.BorderRadius, logical) against the knob's logical
    // half-side; both are logical so Min is unit-safe. Default TyToggleKnob
    // border-radius:12px with a 44x24 toggle → KnobLogical div 2 = 9 →
    // Min(12,9)=9 → circle unchanged.
    KnobLogical := MulDiv(KnobSide, 96, APPI);
    KnobRadiusLogical := TyClampRadius(KnobStyle.BorderRadius, KnobLogical div 2);

    // Knob fill: solid TyToggleKnob.background (white in the default theme).
    KnobFill := Default(TTyFill);
    KnobFill.Kind := tfkSolid;
    KnobFill.Color := KnobStyle.Background.Color;

    P.FillBackground(KnobRect, KnobFill, KnobRadiusLogical);

    // Caption: drawn to the RIGHT of the switch zone, vertically centred, using
    // the same style tokens captioned controls use (font/size/weight/text-color).
    if FCaption <> '' then
    begin
      // The caption strip sits OUTSIDE the narrowed track rect, so DrawFrame never
      // composited a backdrop there. On an image theme fill it with the form's photo
      // (no-op off-image/headless) so it is not a solid gap beside the switch.
      FillSharpBackdrop(P, Rect(R.Right, FullR.Top, FullR.Right, FullR.Bottom));
      Gap := P.Scale(TyCheckBoxGap);
      CaptionRect := Rect(R.Right + Gap, FullR.Top, FullR.Right, FullR.Bottom);
      P.DrawText(CaptionRect, FCaption, S.FontName, ResolveFontSize(S),
        S.FontWeight, S.TextColor, taLeftJustify, tlCenter, True);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyToggleSwitch.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
