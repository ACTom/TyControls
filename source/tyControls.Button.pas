unit tyControls.Button;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Animation;
type
  TTyButton = class(TTyCustomControl)
  private
    FBgAnim: TTyAnimator;
    FAnimationsEnabled: Boolean;
    FTimer: TTimer;
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    function GetBgAnimProgress: Single;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    // Steppable animation seam (no wall-clock): advance the hover bg-fade by AMs
    // and return True iff the eased progress changed. Tests drive this directly
    // via an access subclass; the lazy TTimer drives it at runtime.
    function AdvanceAnimation(AMs: Integer): Boolean;
    // Raw (un-eased) fade progress, 0..1. Exposed for deterministic tests.
    property BgAnimProgress: Single read GetBgAnimProgress;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Click; override;
    // When enabled and the control has a window handle, hovering fades the
    // background between the normal and hover styles; otherwise it snaps (the
    // headless/test default), preserving the existing exact-pixel paint tests.
    property AnimationsEnabled: Boolean read FAnimationsEnabled write FAnimationsEnabled default False;
  published
    property Caption;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;
implementation

constructor TTyButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAnimationsEnabled := False;
  // Hover bg-fade animator: rest at 0 (normal), ~120ms full traversal,
  // decelerating. Mirrors the ToggleSwitch knob-slide timing.
  FBgAnim.Progress := 0;
  FBgAnim.Target := 0;
  FBgAnim.DurationMs := 120;
  FBgAnim.Easing := teEaseOutCubic;
end;

destructor TTyButton.Destroy;
begin
  // FTimer is owned by Self (would be freed by DestroyComponents), but free it
  // explicitly first so the OnTimer callback can never fire mid-teardown.
  FreeAndNil(FTimer);
  inherited Destroy;
end;

procedure TTyButton.Click;
begin
  if not Enabled then Exit;
  inherited Click;
end;

function TTyButton.GetStyleTypeKey: string;
begin
  Result := 'TyButton';
end;

procedure TTyButton.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;  // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyButton.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then
    Invalidate;
  if not FBgAnim.Running then
    FTimer.Enabled := False;
end;

function TTyButton.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FBgAnim.Advance(AMs);
end;

function TTyButton.GetBgAnimProgress: Single;
begin
  Result := FBgAnim.Progress;
end;

procedure TTyButton.MouseEnter;
begin
  inherited MouseEnter;  // sets FHover := True; Invalidate
  FBgAnim.Target := 1;
  if FAnimationsEnabled then
  begin
    // Animate: keep the current raw progress and let the driver step the fade
    // toward the hover target. At runtime (window handle present) a lazy TTimer
    // owns the clock; tests step AdvanceAnimation manually. Do NOT snap here.
    if HandleAllocated then
    begin
      EnsureTimer;
      FTimer.Enabled := True;
    end;
  end
  else
    // Animations off (the headless/test default): snap so paint is correct
    // immediately — this preserves the existing exact-pixel button tests.
    FBgAnim.SetTargetImmediate(1);
end;

procedure TTyButton.MouseLeave;
begin
  inherited MouseLeave;  // sets FHover := False; Invalidate
  FBgAnim.Target := 0;
  if FAnimationsEnabled then
  begin
    if HandleAllocated then
    begin
      EnsureTimer;
      FTimer.Enabled := True;
    end;
  end
  else
    FBgAnim.SetTargetImmediate(0);
end;

procedure TTyButton.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, NormalS, HoverS: TTyStyleSet;
  ContentRect: TRect;
  Eased: Single;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    Eased := FBgAnim.Eased;
    // When mid-fade, blend the normal-state and hover-state background colours.
    // Resolving both explicitly keeps the maths independent of FHover and lets
    // the eased animator drive the visible colour. At Eased=0 this is exactly
    // the normal background; at Eased=1 exactly the hover background.
    if (Eased > 0) and (Eased < 1) and (S.Background.Kind = tfkSolid) then
    begin
      NormalS := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysNormal]);
      HoverS  := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysHover]);
      if (NormalS.Background.Kind = tfkSolid) and (HoverS.Background.Kind = tfkSolid) then
        S.Background.Color := TyLerpColor(NormalS.Background.Color, HoverS.Background.Color, Eased);
    end;
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, ContentRect, S);
    // Inset content by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    P.DrawText(ContentRect, Caption, S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taCenter, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyButton.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
