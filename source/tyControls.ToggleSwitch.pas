unit tyControls.ToggleSwitch;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Animation;

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
    FCaption: string;
    FOnChange: TNotifyEvent;
    FKnobAnim: TTyAnimator;
    FAnimationsEnabled: Boolean;
    FTimer: TTimer;
    procedure SetChecked(const AValue: Boolean);
    procedure SetCaption(const AValue: string);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    function GetKnobAnimProgress: Single;
  protected
    function GetStyleTypeKey: string; override;
    function CurrentStates: TTyStateSet; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
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
    property Checked: Boolean read FChecked write SetChecked default False;
    // Optional text label drawn to the RIGHT of the switch (TToggleBox parity).
    // Empty (the default) renders the bare switch unchanged.
    property Caption: string read FCaption write SetCaption;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
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
  Width := 44;
  Height := 24;
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

procedure TTyToggleSwitch.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Invalidate;
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
