unit tyControls.Button;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, LMessages, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Animation, tyControls.Accel,
  tyControls.StrConsts;
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
    FRefitting: Boolean;   // guards the AutoSize re-fit in Invalidate against re-entry
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
    // Draw the button's content within the already-padded AContentRect using the
    // resolved style AStyle. Base draws the centered caption; descendants (glyph /
    // dropdown / colour buttons) override to add a glyph, arrow or swatch, and may
    // call inherited with a narrowed rect to place the caption. The frame, hover
    // bg-fade, states and badge are handled by RenderTo around this hook.
    procedure DrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet); virtual;
    { The size the caption actually needs: measured text plus the THEME's padding — the very
      inset RenderTo applies before DrawContent, so what AutoSize reserves and what gets
      drawn cannot drift. Without this a button keeps its designed width and a caption that
      outgrows it (a longer translation, a bigger density, a heavier font) is ellipsised.
      Descendants that draw more than the caption (a glyph, an arrow, a swatch) add their
      slot by overriding and calling inherited first. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { The caption's drawn size in DEVICE px at APPI, mnemonic markers removed. }
    procedure MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
    { Caption changes at runtime route here (CM_TEXTCHANGED); with AutoSize the button must
      re-measure to the new text (mirrors TTyTag / TTyLabel). }
    procedure TextChanged; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { A theme switch arrives as a bare Invalidate, and the new theme's font/padding change the
      width the caption needs — so an AutoSize button must re-fit here too. }
    procedure Invalidate; override;
    procedure Paint; override;
    function DialogChar(var Message: TLMKey): Boolean; override;
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
    { Off by default (a designed button keeps the width the .lfm gave it). Switch it on and
      the button WIDENS to hug its caption plus the theme's padding, so a caption that grows
      — a longer translation, a denser scale, a heavier font — lengthens the button instead
      of being ellipsised. Height is left alone (see CalculatePreferredSize): it belongs to
      whoever lays out the row, which is what makes this safe inside a TTyToolBar. }
    property AutoSize;
    // On by default. When enabled and the control has a window handle, hovering
    // fades the background between the normal and hover styles; with no handle
    // (every render test) it snaps, preserving the existing exact-pixel paint tests.
    property AnimationsEnabled: Boolean read FAnimationsEnabled write FAnimationsEnabled default True;
    // Native TButton parity. Default: Enter on the form activates this button.
    // Cancel: Esc activates it. ModalResult: clicking sets the host form's
    // ModalResult (closing a modal dialog).
    property Default: Boolean read FDefault write SetDefault default False;
    property Cancel: Boolean read FCancel write SetCancel default False;
    // VS Code-style persistent selected state: when True, CurrentStates injects
    // tysSelected, triggering the theme's ':selected' rules (e.g. TyButton.ghost:selected).
    // Mutually-exclusive grouping is left to the app, which toggles each button's Down
    // in OnClick (no built-in GroupIndex this round).
    property Down: Boolean read FDown write SetDown default False;
    property ModalResult: TModalResult read FModalResult write FModalResult default mrNone;
    // Badge: numeric only, >99 shows '99+'. ShowBadge is the master switch; by default
    // it shows even for 0, and OnBadgeDisplay may rewrite the text or set AVisible:=False
    // to hide it. Styled via the TyBadge typeKey theme.
    property ShowBadge: Boolean read FShowBadge write SetShowBadge default False;
    property BadgeValue: Integer read FBadgeValue write SetBadgeValue default 0;
    property BadgePosition: TTyBadgePosition read FBadgePosition write SetBadgePosition default bpBottomRight;
    property OnBadgeDisplay: TTyBadgeDisplayEvent read FOnBadgeDisplay write FOnBadgeDisplay;
    property Caption;
    property Enabled;
    property Font;
    { A push button is a tab stop, exactly as the native TButton is: Tab reaches it and
      Space/Enter presses it (KeyDown below), and TTyCustomControl.MouseDown gates its
      click-to-focus on this flag, so without it a click never moved focus off whatever
      had it. Re-published with default True so a host that wants a particular button OUT
      of the cycle can say TabStop=False in the .lfm and have it STREAM — with the
      inherited `default False` a False was equal to the declared default and silently
      dropped, leaving the constructor's True to win at run time. }
    property TabStop default True;
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
  TyAccelRegister(Self);
  // LCL's TWinControl defaults TabStop to False, which for a button means the Space/Enter
  // handling in KeyDown can never fire and a click cannot move focus onto it (see the
  // gate in TTyCustomControl.MouseDown). Every descendant that must stay OUT of the tab
  // cycle turns it back off explicitly (TTySpeedButton; TTyTransfer's rail buttons).
  TabStop := True;
  FAnimationsEnabled := True;
  FBadgePosition := bpBottomRight;
  // Hover bg-fade animator: rest at 0 (normal), ~120ms full traversal,
  // decelerating. Mirrors the ToggleSwitch knob-slide timing.
  FBgAnim.Progress := 0;
  FBgAnim.Target := 0;
  FBgAnim.DurationMs := 120;
  FBgAnim.Easing := teEaseOutCubic;
  Width := 88;
  Height := TyDensityHeight(ActiveController, 30);
end;

destructor TTyButton.Destroy;
begin
  // FTimer is owned by Self (would be freed by DestroyComponents), but free it
  // explicitly first so the OnTimer callback can never fire mid-teardown.
  FreeAndNil(FTimer);
  TyAccelUnregister(Self);
  inherited Destroy;
end;

function TTyButton.DialogChar(var Message: TLMKey): Boolean;
begin
  if Enabled and TyIsAccelKey(Message, Caption) then
  begin
    Click;
    Exit(True);
  end;
  Result := inherited DialogChar(Message);
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
  if FBadgeValue > 99 then AText := rsBadgeOverflow else AText := IntToStr(FBadgeValue);
  vis := True;   // default: show (including '0'); the event may override
  if Assigned(FOnBadgeDisplay) then FOnBadgeDisplay(Self, FBadgeValue, AText, vis);
  Result := vis and (AText <> '');
end;

procedure TTyButton.DrawBadge(P: TTyPainter; const AFullRect: TRect);
var
  S: TTyStyleSet;
  txt: string;
  fs, fw, padX, padY, tw, bh, bw, inset, minSize, x, y, half, themedR, rLogical: Integer;
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
  // Both metrics are theme tokens (TTyBadge resolves the SAME two the same way, so the
  // built-in and standalone badges retune together and cannot drift).
  minSize := ActiveController.Metric(TyBadgeMinSizeVar, TyBadgeMinSize);
  if minSize < 1 then minSize := 1;
  bh := szH.cy + 2 * padY;
  if bh < P.Scale(minSize) then bh := P.Scale(minSize);  // degenerate-measure floor: stay visible
  tw := szW.cx;
  bw := tw + 2 * padX;
  if bw < bh then bw := bh;                     // single glyph -> near-circle
  inset := ActiveController.Metric(TyBadgeInsetVar, TyBadgeInset);
  if inset < 0 then inset := 0;
  inset := P.Scale(inset);
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
  // Anti-clip breathing room. The pill is sized to MeasureText, but some widgetsets (notably
  // LCL-Qt6) render small bold glyphs a hair larger than they measure; DrawText clips to its rect,
  // so the digit edges get shaved -> the number looks cut off and the clipped AA edges read as
  // blurry (TyBadge padding is 0px vertically, so the height is especially tight). Inflate ONLY the
  // text's clip rect by 1px each side: the centred text stays on the same point and the pill
  // geometry is unchanged, so Windows / headless render byte-identically (their measure == render,
  // so nothing was at the clip boundary).
  Dec(badgeRect.Left, P.Scale(1));  Dec(badgeRect.Top, P.Scale(1));
  Inc(badgeRect.Right, P.Scale(1)); Inc(badgeRect.Bottom, P.Scale(1));
  // ASmallCrisp: on Linux/macOS the digits are supersampled (BGRA otherwise renders small bold
  // text soft there); Windows ignores the flag and renders identically to before.
  P.DrawText(badgeRect, txt, S.FontName, fs, fw, S.TextColor, taCenter, tlCenter, False, 0, True);
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
    // Fill the parent's OPAQUE surface first, so a transparent/ghost background (and the
    // gaps outside the rounded frame) show the parent — not the Win10 DWM sheet-of-glass,
    // which otherwise bleeds through a windowed button and washes white on deactivate.
    TyFillParentBg(Self, P, ContentRect, S);
    DrawFrame(P, ContentRect, S);
    BadgeArea := ContentRect;   // full client rect for badge positioning (pre-padding)
    // Inset content by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    DrawContent(P, ContentRect, S);
    DrawBadge(P, BadgeArea);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyButton.TextChanged;
begin
  inherited TextChanged;
  // The new caption needs a different width, so an auto-sized button must re-fit.
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyButton.Invalidate;
begin
  inherited Invalidate;
  { A theme switch reaches every control as a bare Invalidate (TTyStyleController broadcasts
    one to each registered control), and the new theme brings a different font and padding —
    so the width an AutoSize button needs changed too. Without re-fitting here the button
    keeps the old theme's width and the caption is ellipsised, which is exactly what the
    demo's tool-bar buttons did when the skin was switched to antdesign.
    TTyBadge re-measures from its own Invalidate override for the same reason.
    FRefitting guards the re-entry: AdjustSize -> SetBounds -> Invalidate would recurse. }
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

procedure TTyButton.MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
var
  S: TTyStyleSet;
  Meas: TBitmap;
  disp: string;
  mp: Integer;
begin
  S := CurrentStyle;
  // The '&' markers are not drawn, so they must not be measured either.
  TyParseMnemonic(Caption, disp, mp);
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
    Meas.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
    if S.FontWeight >= 600 then
      Meas.Canvas.Font.Style := [fsBold]
    else
      Meas.Canvas.Font.Style := [];
    AWidth := Meas.Canvas.TextWidth(disp);
    // A stable reference glyph: an empty caption still sizes to one line.
    AHeight := Meas.Canvas.TextHeight('Ag');
    if AWidth < 0 then AWidth := 0;
    if AHeight < 1 then AHeight := 1;
  finally
    Meas.Free;
  end;
end;

procedure TTyButton.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, tw, th: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  MeasureCaption(ppi, tw, th);
  // The SAME padding RenderTo insets ContentRect by before handing it to DrawContent.
  PreferredWidth := tw + MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96);
  if PreferredWidth < 1 then PreferredWidth := 1;
  { WIDTH ONLY — 0 is LCL's "no preference on this axis", so the button keeps its height.
    A button grows sideways to fit a longer caption; its height is a LAYOUT decision, owned
    by whoever arranges the row. Proposing a height as well makes the button fight any
    container that pins one: TTyToolBar sizes every child to its ButtonHeight, so a button
    asking for a taller one bounced between the two forever and LCL aborted with
    "TControl.ChangeBounds loop detected". Callers who want the caption's natural height can
    read it from MeasureCaption plus the style's vertical padding. }
  PreferredHeight := 0;
end;

procedure TTyButton.DrawContent(APainter: TTyPainter; const AContentRect: TRect;
  const AStyle: TTyStyleSet);
var
  disp: string;
  mp: Integer;
begin
  TyParseMnemonic(Caption, disp, mp);
  APainter.DrawText(AContentRect, disp, AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight, AStyle.TextColor, taCenter, tlCenter, True, TyAccelGatePos(mp));
end;

procedure TTyButton.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
