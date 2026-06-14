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
    FOnChange: TNotifyEvent;
    FKnobAnim: TTyAnimator;
    FAnimationsEnabled: Boolean;
    FTimer: TTimer;
    procedure SetChecked(const AValue: Boolean);
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
    // Raw (un-eased) knob progress, 0..1. Exposed for deterministic tests.
    property KnobAnimProgress: Single read GetKnobAnimProgress;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Toggle;
    procedure Click; override;
    // When enabled and the control has a window handle, flipping Checked
    // animates the knob slide; otherwise it snaps (the headless/test default).
    property AnimationsEnabled: Boolean read FAnimationsEnabled write FAnimationsEnabled default False;
  published
    property Checked: Boolean read FChecked write SetChecked default False;
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
  FAnimationsEnabled := False;
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
  if FAnimationsEnabled then
  begin
    // Animate: keep the current raw progress and let the driver step the knob
    // toward the new target. At runtime (window handle present) a lazy TTimer
    // owns the clock; tests step AdvanceAnimation manually. Do NOT snap here.
    if HandleAllocated then
    begin
      EnsureTimer;
      FTimer.Enabled := True;
    end;
  end
  else
    // Animations off (the headless/test default): snap so paint is correct
    // immediately — this preserves the existing exact-pixel toggle tests.
    FKnobAnim.SetTargetImmediate(Ord(AValue));
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
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
  S, TrackS: TTyStyleSet;
  R: TRect;
  TrackRadius: Integer;
  DevH, Margin, KnobSide, KnobLogical, KnobX, KnobRadiusLogical: Integer;
  KnobRect: TRect;
  KnobFill: TTyFill;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;

    // Build a track style with a pill border-radius.
    // If the theme supplies a BorderRadius, use it; otherwise half the device height.
    TrackS := S;
    DevH := R.Bottom - R.Top;
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

    // Logical knob values for FillBackground (which calls Scale internally)
    KnobLogical := MulDiv(KnobSide, 96, APPI);
    KnobRadiusLogical := KnobLogical div 2;

    // Knob fill: solid TextColor (white in the spec)
    KnobFill := Default(TTyFill);
    KnobFill.Kind := tfkSolid;
    KnobFill.Color := S.TextColor;

    P.FillBackground(KnobRect, KnobFill, KnobRadiusLogical);

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
