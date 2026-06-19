unit tyControls.Button;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Animation;
type
  // Which corner the numeric badge sits in (inset within the button's client rect).
  TTyBadgePosition = (bpTopLeft, bpTopRight, bpBottomLeft, bpBottomRight);
  // Display hook: default text/visibility are computed first, then this may rewrite
  // AText or set AVisible:=False for a custom policy (e.g. hide when AValue < 3).
  TTyBadgeDisplayEvent = procedure(Sender: TObject; AValue: Integer;
    var AText: string; var AVisible: Boolean) of object;

  TTyButton = class(TTyCustomControl)
  private
    FBgAnim: TTyAnimator;
    FAnimationsEnabled: Boolean;
    FTimer: TTimer;
    FDefault: Boolean;
    FCancel: Boolean;
    FModalResult: TModalResult;
    FDown: Boolean;
    FShowBadge: Boolean;
    FBadgeValue: Integer;
    FBadgePosition: TTyBadgePosition;
    FOnBadgeDisplay: TTyBadgeDisplayEvent;
    procedure SetShowBadge(AValue: Boolean);
    procedure SetBadgeValue(AValue: Integer);
    procedure SetBadgePosition(AValue: TTyBadgePosition);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    function GetBgAnimProgress: Single;
    procedure SetCancel(AValue: Boolean);
    procedure SetDefault(AValue: Boolean);
    procedure SetDown(AValue: Boolean);
    // Register/unregister Self as the host form's Default/Cancel control. No-op
    // when there is no parent form yet (e.g. Default/Cancel streamed from the LFM
    // before Parent); Loaded re-applies it once the parent is known.
    procedure RegisterDefaultWithForm;
    procedure RegisterCancelWithForm;
  protected
    function GetStyleTypeKey: string; override;
    // Inject tysSelected when Down (and enabled), so ':selected' theme rules apply.
    function CurrentStates: TTyStateSet; override;
    // Decide whether/what to draw for the badge. ShowBadge off -> False; else default
    // text ('99+' cap, includes '0') + AVisible:=True, then OnBadgeDisplay may rewrite;
    // True only when visible and the text is non-empty.
    function ResolveBadgeDisplay(out AText: string): Boolean;
    // Paint the badge (if visible) at the chosen corner, inset within AFullRect.
    procedure DrawBadge(P: TTyPainter; const AFullRect: TRect);
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    // VCL-style dialog-key path (CM_DIALOGKEY carries a VK_* CharCode). LCL marks
    // CM_DIALOGKEY "unimplemented" so a real form drives the action methods above,
    // not this handler; it exists so the same routing is exercisable headlessly
    // through the directly-testable WantsDialogKey seam.
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    // Steppable animation seam (no wall-clock): advance the hover bg-fade by AMs
    // and return True iff the eased progress changed. Tests drive this directly
    // via an access subclass; the lazy TTimer drives it at runtime.
    function AdvanceAnimation(AMs: Integer): Boolean;
    // Arm the bg-fade toward ATarget without snapping (Progress is left where it
    // is so AdvanceAnimation can interpolate). Test seam only — at runtime the
    // hover path is driven by MouseEnter/MouseLeave + the lazy TTimer.
    procedure ArmBgAnim(ATarget: Single);
    // Raw (un-eased) fade progress, 0..1. Exposed for deterministic tests.
    property BgAnimProgress: Single read GetBgAnimProgress;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Re-apply Default/Cancel registration after streaming: if Default/Cancel was
    // loaded from the LFM before Parent was assigned, the setter's GetParentForm
    // returned nil and the registration was dropped — redo it now that the parent
    // form is known (mirrors native re-application in Loaded/CreateWnd).
    procedure Loaded; override;
    procedure Click; override;
    // LCL-native default/cancel routing. A focused control's Enter/Esc make the
    // owning form invoke ExecuteDefaultAction / ExecuteCancelAction on its
    // DefaultControl / CancelControl (registered by SetDefault/SetCancel below).
    procedure ExecuteDefaultAction; override;
    procedure ExecuteCancelAction; override;
    // Directly-testable dialog-key seam: True iff this button should activate for
    // ACharCode — VK_RETURN when Default, VK_ESCAPE when Cancel. The CMDialogKey
    // handler (and headless tests) route through here.
    function WantsDialogKey(ACharCode: Word): Boolean;
  published
    // On by default. When enabled and the control has a window handle, hovering
    // fades the background between the normal and hover styles; with no handle
    // (every render test) it snaps, preserving the existing exact-pixel paint tests.
    property AnimationsEnabled: Boolean read FAnimationsEnabled write FAnimationsEnabled default True;
    // Native TButton parity. Default: Enter on the form activates this button.
    // Cancel: Esc activates it. ModalResult: clicking sets the host form's
    // ModalResult (closing a modal dialog).
    property Default: Boolean read FDefault write SetDefault default False;
    property Cancel: Boolean read FCancel write SetCancel default False;
    // VS Code 风格常驻选中态:为 True 时 CurrentStates 注入 tysSelected,触发主题里的
    // ':selected' 规则(如 TyButton.ghost:selected)。互斥分组由应用在 OnClick 里自行
    // 切换各按钮的 Down(本期不内建 GroupIndex)。
    property Down: Boolean read FDown write SetDown default False;
    property ModalResult: TModalResult read FModalResult write FModalResult default mrNone;
    // 角标(badge):仅数字,>99 显示 '99+'。ShowBadge 为总开关;默认显示含 0,可经
    // OnBadgeDisplay 改写文本或置 AVisible:=False 自定义隐藏。样式由 TyBadge typeKey 主题化。
    property ShowBadge: Boolean read FShowBadge write SetShowBadge default False;
    property BadgeValue: Integer read FBadgeValue write SetBadgeValue default 0;
    property BadgePosition: TTyBadgePosition read FBadgePosition write SetBadgePosition default bpBottomRight;
    property OnBadgeDisplay: TTyBadgeDisplayEvent read FOnBadgeDisplay write FOnBadgeDisplay;
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
  FAnimationsEnabled := True;
  FBadgePosition := bpBottomRight;
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
var
  Form: TCustomForm;
begin
  if not Enabled then Exit;
  // Set the host form's ModalResult BEFORE OnClick (native TButton semantics,
  // buttons.inc:160-170). This lets an OnClick handler veto/override the close by
  // writing Form.ModalResult := mrNone; doing it after would clobber the handler.
  if FModalResult <> mrNone then
  begin
    Form := GetParentForm(Self);
    if Form <> nil then
      Form.ModalResult := FModalResult;
  end;
  inherited Click;  // OnClick may now veto by resetting Form.ModalResult
end;

procedure TTyButton.RegisterDefaultWithForm;
var
  Form: TCustomForm;
begin
  // Register/unregister with the host form so its Enter handling routes here.
  Form := GetParentForm(Self);
  if Form <> nil then
  begin
    if FDefault then
      Form.DefaultControl := Self
    else if Form.DefaultControl = Self then
      Form.DefaultControl := nil;
  end;
end;

procedure TTyButton.RegisterCancelWithForm;
var
  Form: TCustomForm;
begin
  // Register/unregister with the host form so its Esc handling routes here.
  Form := GetParentForm(Self);
  if Form <> nil then
  begin
    if FCancel then
      Form.CancelControl := Self
    else if Form.CancelControl = Self then
      Form.CancelControl := nil;
  end;
end;

procedure TTyButton.Loaded;
begin
  inherited Loaded;
  // Parent is assigned by now; re-apply registration dropped during streaming
  // (Default/Cancel set before Parent => GetParentForm was nil in the setter).
  if FDefault then RegisterDefaultWithForm;
  if FCancel then RegisterCancelWithForm;
end;

procedure TTyButton.SetDefault(AValue: Boolean);
begin
  if FDefault = AValue then Exit;
  FDefault := AValue;
  RegisterDefaultWithForm;
end;

procedure TTyButton.SetCancel(AValue: Boolean);
begin
  if FCancel = AValue then Exit;
  FCancel := AValue;
  RegisterCancelWithForm;
end;

procedure TTyButton.SetDown(AValue: Boolean);
begin
  if FDown = AValue then Exit;
  FDown := AValue;
  Invalidate;
end;

function TTyButton.CurrentStates: TTyStateSet;
begin
  Result := inherited CurrentStates;   // hover/active/focused/disabled, or normal
  // Enabled=False makes inherited return [tysDisabled] only; disabled wins, so we
  // never layer selected on top of it. Otherwise Down adds the resting selected state.
  if FDown and Enabled then
  begin
    Include(Result, tysSelected);
    Exclude(Result, tysNormal);
  end;
end;

procedure TTyButton.SetShowBadge(AValue: Boolean);
begin
  if FShowBadge = AValue then Exit;
  FShowBadge := AValue;
  Invalidate;
end;

procedure TTyButton.SetBadgeValue(AValue: Integer);
begin
  if FBadgeValue = AValue then Exit;
  FBadgeValue := AValue;
  if FShowBadge then Invalidate;
end;

procedure TTyButton.SetBadgePosition(AValue: TTyBadgePosition);
begin
  if FBadgePosition = AValue then Exit;
  FBadgePosition := AValue;
  if FShowBadge then Invalidate;
end;

function TTyButton.ResolveBadgeDisplay(out AText: string): Boolean;
var vis: Boolean;
begin
  Result := False;
  AText := '';
  if not FShowBadge then Exit;
  if FBadgeValue > 99 then AText := '99+' else AText := IntToStr(FBadgeValue);
  vis := True;   // default: show (including '0'); the event may override
  if Assigned(FOnBadgeDisplay) then FOnBadgeDisplay(Self, FBadgeValue, AText, vis);
  Result := vis and (AText <> '');
end;

procedure TTyButton.DrawBadge(P: TTyPainter; const AFullRect: TRect);
var
  S: TTyStyleSet;
  txt: string;
  fs, fw, padX, padY, tw, bh, bw, inset, x, y, half, themedR, rLogical: Integer;
  szH, szW: TSize;
  badgeRect: TRect;
begin
  if not ResolveBadgeDisplay(txt) then Exit;
  S := ActiveController.Model.ResolveStyle('TyBadge', '', []);
  if not (tpBackground in S.Present) then Exit;   // no theme key -> nothing to draw
  fs := ResolveFontSize(S);
  fw := S.FontWeight;
  // Height from a stable reference glyph ('0'); width from the actual text.
  szH := P.MeasureText('0', S.FontName, fs, fw);
  szW := P.MeasureText(txt, S.FontName, fs, fw);
  padX := P.Scale(S.Padding.Left);
  padY := P.Scale(S.Padding.Top);
  bh := szH.cy + 2 * padY;
  if bh < P.Scale(8) then bh := P.Scale(8);    // degenerate-measure floor: stay visible
  tw := szW.cx;
  bw := tw + 2 * padX;
  if bw < bh then bw := bh;                     // single glyph -> near-circle
  inset := P.Scale(2);
  case FBadgePosition of
    bpTopLeft:     begin x := AFullRect.Left  + inset;       y := AFullRect.Top    + inset;       end;
    bpTopRight:    begin x := AFullRect.Right - inset - bw;  y := AFullRect.Top    + inset;       end;
    bpBottomLeft:  begin x := AFullRect.Left  + inset;       y := AFullRect.Bottom - inset - bh;  end;
    bpBottomRight: begin x := AFullRect.Right - inset - bw;  y := AFullRect.Bottom - inset - bh;  end;
  else
    begin x := AFullRect.Right - inset - bw; y := AFullRect.Bottom - inset - bh; end;
  end;
  badgeRect := Rect(x, y, x + bw, y + bh);
  // Pill by default (half-height radius); honour a smaller themed radius if set.
  // FillBackground takes a LOGICAL radius and Scales it, so unscale the device half.
  half := P.Unscale(bh div 2);
  themedR := TyEffectiveCorners(S).TL;
  if themedR <= 0 then rLogical := half
  else rLogical := TyClampRadius(themedR, half);
  P.FillBackground(badgeRect, S.Background, TyUniformCorners(rLogical));
  P.DrawText(badgeRect, txt, S.FontName, fs, fw, S.TextColor, taCenter, tlCenter, False);
end;

function TTyButton.WantsDialogKey(ACharCode: Word): Boolean;
begin
  Result := (FDefault and (ACharCode = VK_RETURN)) or
            (FCancel  and (ACharCode = VK_ESCAPE));
end;

procedure TTyButton.ExecuteDefaultAction;
begin
  if FDefault then
    Click
  else
    inherited ExecuteDefaultAction;
end;

procedure TTyButton.ExecuteCancelAction;
begin
  if FCancel then
    Click
  else
    inherited ExecuteCancelAction;
end;

procedure TTyButton.CMDialogKey(var Message: TCMDialogKey);
begin
  if WantsDialogKey(Message.CharCode) then
  begin
    if Enabled then Click;
    Message.Result := 1;  // handled
  end
  else
    inherited;
end;

procedure TTyButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if (Key = VK_SPACE) or (Key = VK_RETURN) then
  begin
    Click;            // Click already guards Enabled and fires OnClick
    Key := 0;
  end;
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

procedure TTyButton.ArmBgAnim(ATarget: Single);
begin
  FBgAnim.Target := ATarget;
end;

function TTyButton.GetBgAnimProgress: Single;
begin
  Result := FBgAnim.Progress;
end;

procedure TTyButton.MouseEnter;
begin
  inherited MouseEnter;  // sets FHover := True; Invalidate
  FBgAnim.Target := 1;
  if FAnimationsEnabled and HandleAllocated then
  begin
    // Animate: keep the current raw progress and let the lazy TTimer step the
    // fade toward the hover target. Only reachable with a real window handle.
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else
    // Headless (no window handle) or animations off: snap so paint is correct
    // immediately. Because every render test runs handle-less, this keeps the
    // existing exact-pixel button tests green regardless of the default.
    FBgAnim.SetTargetImmediate(1);
end;

procedure TTyButton.MouseLeave;
begin
  inherited MouseLeave;  // sets FHover := False; Invalidate
  FBgAnim.Target := 0;
  if FAnimationsEnabled and HandleAllocated then
  begin
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else
    FBgAnim.SetTargetImmediate(0);
end;

procedure TTyButton.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, NormalS, HoverS: TTyStyleSet;
  ContentRect, BadgeArea: TRect;
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
      // Resting end = the current state set MINUS hover (a selected button rests on
      // its :selected bg, a plain one on :normal); hover end = current state PLUS hover.
      // Alpha participates in the lerp (ghost's transparent rest -> opaque hover fade).
      NormalS := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, CurrentStates - [tysHover]);
      HoverS  := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, CurrentStates + [tysHover]);
      if (NormalS.Background.Kind = tfkSolid) and (HoverS.Background.Kind = tfkSolid) then
        S.Background.Color := TyLerpColor(NormalS.Background.Color, HoverS.Background.Color, Eased);
    end;
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, ContentRect, S);
    BadgeArea := ContentRect;   // full client rect for badge positioning (pre-padding)
    // Inset content by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    P.DrawText(ContentRect, Caption, S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taCenter, tlCenter, True);
    DrawBadge(P, BadgeArea);
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
