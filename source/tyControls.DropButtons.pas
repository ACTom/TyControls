unit tyControls.DropButtons;
{$mode objfpc}{$H+}
{ Drop-down buttons layered on top of TTyButton (unit tyControls.Button).

  TWO controls, sharing the arrow-triangle drawing + the "fire OnDropDown then pop
  the menu" logic:

    TTyDropDownButton — a SPLIT button: a primary caption area (fires the normal
      Click / OnClick) plus a right-hand arrow zone (a downward triangle) separated
      by a thin divider. Clicking the arrow zone opens DropDownMenu; clicking the
      primary area behaves like a plain button.

    TTyMenuButton — NO split: the WHOLE button drops the menu. It shows the caption
      + a trailing downward arrow, and ANY click opens DropDownMenu. A MenuButton's
      click IS the drop, so Click itself routes to the drop-down.

  Both REUSE the 'TyButton' style token (GetStyleTypeKey is inherited unchanged) —
  no new .tycss is introduced; the split divider uses the resolved style's
  BorderColor and the arrow uses its TextColor, so everything stays theme-driven.

  The menu popped is a tyControls.Menu.TTyPopupMenu (its virtual PopUp(X,Y) renders
  the themed menu). Popping needs a live window, so the actual PopUp call lives only
  in the real click path; the decision logic (hit-test + DoDropDown) is factored into
  headless-testable seams (TyDropArrowHit + a protected DoDropDown that records a
  "would-pop" flag) so it can be unit-tested without a GUI. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Accel,
  tyControls.Base, tyControls.Button, tyControls.Menu;

const
  { Default width (logical px, 96-PPI baseline) of a split button's right-hand
    arrow zone. Scaled to device px at paint / hit-test time. }
  TyDefaultDropArrowWidth = 18;

{ THE trailing drop-arrow zone — one pure rule, read by the PAINT and by the HIT TEST of
  every split control in the library (TTyDropDownButton, TTyToolButton's tbsDropDown).

  WHY IT EXISTS. The two used to compute the zone separately and got different answers.
  The paint measured back from the PADDED CONTENT box (AContentRect.Right, the rect
  TTyButton.RenderTo hands DrawContent); the hit test measured back from the CONTROL's
  right edge. They therefore stood exactly one right-padding apart — 6 device px under the
  default --pad-button. The visible cost was a strip of drawn arrow, starting AT the split
  divider, that ran the PRIMARY action: the user pressed the line that says "menu here" and
  got a save instead. A CENTRE probe never caught it, because the two zones overlap in the
  middle; only a probe at the divider itself can. (Recorded at the time in
  docs/controls/toolbar.md 3.2.1 as a both-sites fix, and it is now made.)

  WHAT IT ANSWERS. The zone's LEFT edge in client x — deliberately ONE number and not a
  span, because the left edge is the whole of what the paint and the hit test have to agree
  on, and a function that also returned a right edge would have to invent one for the paint
  (which draws to the content edge) different from the hit test's (which runs to the control
  edge, since the right padding holds no ink but is still the arrow end of the button).
  Each caller states its own far end, in its own units, right where it is used.

  -1 = NO ZONE: the arrow is non-positive, the content box is degenerate, or the arrow does
  not FIT inside the content box. "Does not fit" refuses rather than halving the arrow: a
  control configured with an arrow wider than its own content box is misconfigured, and
  leaving the primary action the whole face is the conservative reading. The paint refuses
  on the identical test, so an arrow that cannot be hit is never drawn either.

  AContentLeft/AContentRight  the content box in client x — the client rect already inset by
                              the theme's padding (TyButtonContentSpanX computes it for a
                              caller that has a style but no painter).
  AArrowWidthPx               the arrow zone's DEVICE width. }
function TyDropArrowZoneLeft(AContentLeft, AContentRight, AArrowWidthPx: Integer): Integer;

{ The content box's horizontal span in client x for a themed button: the client rect inset
  by the resolved style's left/right padding, converted with the SAME 96-baseline MulDiv
  that TTyPainter.Scale applies — so this reproduces exactly the AContentRect.Left/.Right
  that TTyButton.RenderTo hands to DrawContent. It exists so a HIT TEST, which has a style
  but no painter, can ask the question the paint answers from its rect. }
procedure TyButtonContentSpanX(AWidth, APPI: Integer; const AStyle: TTyStyleSet;
  out ALeft, ARight: Integer);

{ Pure hit-test seam: True iff a click at device-x AClickX (0-based within the
  control) falls in the RIGHT arrow zone of a split button AWidthPx wide whose arrow
  zone is AArrowWidthPx wide. The arrow zone is the rightmost AArrowWidthPx of the
  control; a click at exactly (AWidthPx - AArrowWidthPx) is the first arrow-zone
  pixel. Degenerate widths (arrow >= control, or non-positive) fall back sanely so a
  tiny/zero button never traps every click as an arrow hit.

  This is TyDropArrowZone over an UNPADDED box, kept as a named function because it is the
  arrow rule stated without a theme in the way — the form the pure unit tests pin and the
  form documentation quotes. The controls call TyDropArrowZone directly, with their real
  padding; see TTyDropDownButton.IsInArrowZone. }
function TyDropArrowHit(AClickX, AWidthPx, AArrowWidthPx: Integer): Boolean;

type
  { SPLIT drop-down button: caption (left, fires OnClick) + arrow zone (right, opens
    the menu), divided by a 1px line.

    AutoSize(继承自 TTyButton,默认 False)在这里同样有效:打开后按钮的宽度 = 标题 +
    主题内边距 + ArrowWidth。换皮肤会改字体和内边距,基类的 Invalidate 会重新量一遍,
    所以按钮跟着皮肤长宽,而不是抱着上一套皮肤的宽度把标题省略掉。 }
  TTyDropDownButton = class(TTyButton)
  private
    FDropDownMenu: TTyPopupMenu;
    FArrowWidth: Integer;
    FOnDropDown: TNotifyEvent;
    { Device-x of the last left mouse-down (-1 = none). LCL synthesises Click AFTER
      MouseUp, so the arrow-vs-primary decision is made from the DOWN position and
      applied in Click — see Click below. }
    FDownX: Integer;
    { Test-visible record of the last DoDropDown: did it decide to pop the menu?
      Set True when DoDropDown ran with a non-nil DropDownMenu (i.e. it WOULD have
      called PopUp). The actual PopUp is behind HandleAllocated in DoDropDown. }
    FRequestedPopup: Boolean;
    procedure SetDropDownMenu(AValue: TTyPopupMenu);
    procedure SetArrowWidth(AValue: Integer);
  protected
    { Device-px width of the arrow zone at APPI (ArrowWidth scaled). }
    function ArrowZoneWidth(APPI: Integer): Integer;
    { True iff a click at device-x AX lands in this control's arrow zone. }
    function IsInArrowZone(AX: Integer): Boolean;
    { Fire OnDropDown (so a handler may (re)populate the menu), then — if a menu is
      assigned — record the intent to pop it and, when a live window exists, pop it
      at the button's bottom-left in screen coords. Headless callers (tests) reach
      the "would-pop" record but never touch the GUI PopUp. }
    procedure DoDropDown; virtual;
    { Caption on the left of the arrow zone; a centered downward triangle in the arrow
      zone (AStyle.TextColor); a 1px divider (AStyle.BorderColor) between them. }
    procedure DrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet); override;
    { 基类给出的是「标题 + 主题内边距」的宽度;分割按钮把标题画在箭头区**左边**的
      子矩形里(见 DrawContent),所以它还得多让出整条箭头区,否则 AutoSize 报出来的
      宽度装不下自己画的东西——标题被箭头挤掉、省略号照旧。会说谎的 AutoSize 比没有
      更糟,所以这里加的必须正好是 DrawContent 让出的那一段(同一个 ArrowZoneWidth)。

      这个方法同时也是**尺寸下限**的宽度来源:TTyButton.UpdateSizeConstraints 就是调它来
      算 Constraints.MinWidth 的。所以箭头区不是装饰,而是最小宽度的一部分——一条被压到
      只装得下标题的分割按钮,箭头会直接吃掉标题。高度那半在 MeasureContentHeight 里,箭头
      **不**参与:它画在标题**旁边**(同一个上下沿),挤的是宽度不是高度。 }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    { The native click path routes here after a mouse-up. When the preceding mouse-down
      was in the arrow zone, this DROPS the menu (DoDropDown) and swallows the primary
      OnClick; otherwise it runs the normal TTyButton.Click (OnClick + ModalResult). }
    procedure Click; override;
    { Test seam: run the drop-down decision as a click in the arrow zone would,
      WITHOUT a GUI PopUp (DoDropDown pops only when a window handle exists). After
      it, RequestedPopup reflects whether a menu would have been shown. }
    procedure DropDownForTest;
    { True after a DoDropDown that had a menu assigned (would have popped it). }
    property RequestedPopup: Boolean read FRequestedPopup;
  published
    { The themed menu shown when the arrow zone is clicked. FreeNotification-tracked:
      freeing it nils this reference. }
    property DropDownMenu: TTyPopupMenu read FDropDownMenu write SetDropDownMenu;
    { Logical-px width of the right-hand arrow zone (default 18). }
    property ArrowWidth: Integer read FArrowWidth write SetArrowWidth default TyDefaultDropArrowWidth;
    { Fired just before the menu pops, so a handler can build/update it. }
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
  end;

  { WHOLE-button drop-down: caption + trailing downward arrow; ANY click drops the
    menu (Click itself routes to the drop). No split, no divider.

    AutoSize(继承自 TTyButton,默认仍是 False)在这里同样有效:宽度 = 标题 + 主题
    内边距 + 尾部箭头区。皮肤换了字体/内边距/--drop-arrow-width 之后,基类的
    Invalidate 会重新量一遍,所以按钮跟着皮肤长宽,而不是抱着上一套皮肤的宽度把标题
    省略掉。 }
  TTyMenuButton = class(TTyButton)
  private
    FDropDownMenu: TTyPopupMenu;
    FOnDropDown: TNotifyEvent;
    FRequestedPopup: Boolean;
    procedure SetDropDownMenu(AValue: TTyPopupMenu);
  protected
    { Fire OnDropDown, then record intent + (with a live window) pop DropDownMenu at
      the button's bottom-left. Same headless contract as the split button's version. }
    procedure DoDropDown; virtual;
    { Device-px width of the trailing arrow zone at APPI. The zone is a THEME metric
      ('--drop-arrow-width'), not a published property, so a skin can retune it —
      which is exactly why the preferred width has to be recomputed on a theme switch
      (the base class's Invalidate does that). Mirrors the value DrawContent reserves
      via APainter.Scale of the same metric; keep the two in step. }
    function ArrowZoneWidth(APPI: Integer): Integer;
    { Caption on the left, a trailing downward arrow on the right (AStyle.TextColor). }
    procedure DrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet); override;
    { 标题只占箭头区左边的子矩形,所以在基类的「标题 + 内边距」之上还要加一整条箭头区,
      否则 AutoSize 量出来的宽度装不下自己画的箭头。

      同样地,这里也是**尾部箭头区进入尺寸下限**的地方:TTyButton.UpdateSizeConstraints
      用本方法算 Constraints.MinWidth。皮肤改了 '--drop-arrow-width',换肤广播的那个裸
      Invalidate 会带着基类重量一遍,下限跟着走——下限必须是**推导**出来的,不能写死。 }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    { The whole button IS the drop: Click routes to DoDropDown (which also fires the
      inherited OnClick via inherited Click, so an OnClick handler still runs). }
    procedure Click; override;
    { Test seam mirroring TTyDropDownButton.DropDownForTest. }
    procedure DropDownForTest;
    property RequestedPopup: Boolean read FRequestedPopup;
  published
    property DropDownMenu: TTyPopupMenu read FDropDownMenu write SetDropDownMenu;
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
  end;

implementation

function TyDropArrowZoneLeft(AContentLeft, AContentRight, AArrowWidthPx: Integer): Integer;
begin
  // No arrow, or an empty/inverted content box (this also covers a zero-width control:
  // its content right, already inset by the padding, cannot exceed its content left).
  if (AArrowWidthPx <= 0) or (AContentRight <= AContentLeft) then
    Exit(-1);
  // An arrow that does not fit inside the content box is not drawn and not hit (see header).
  if AArrowWidthPx >= (AContentRight - AContentLeft) then
    Exit(-1);
  Result := AContentRight - AArrowWidthPx;
end;

procedure TyButtonContentSpanX(AWidth, APPI: Integer; const AStyle: TTyStyleSet;
  out ALeft, ARight: Integer);
begin
  ALeft  := MulDiv(AStyle.Padding.Left, APPI, 96);
  ARight := AWidth - MulDiv(AStyle.Padding.Right, APPI, 96);
end;

function TyDropArrowHit(AClickX, AWidthPx, AArrowWidthPx: Integer): Boolean;
var
  zoneLeft: Integer;
begin
  // The same rule, over a box with no padding: content box == the whole control.
  zoneLeft := TyDropArrowZoneLeft(0, AWidthPx, AArrowWidthPx);
  Result := (zoneLeft >= 0) and (AClickX >= zoneLeft) and (AClickX < AWidthPx);
end;

{ TTyDropDownButton }

constructor TTyDropDownButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FArrowWidth := TyDefaultDropArrowWidth;
  FDownX := -1;
  FRequestedPopup := False;
end;

procedure TTyDropDownButton.SetDropDownMenu(AValue: TTyPopupMenu);
begin
  if FDropDownMenu = AValue then Exit;
  if FDropDownMenu <> nil then
    FDropDownMenu.RemoveFreeNotification(Self);
  FDropDownMenu := AValue;
  if FDropDownMenu <> nil then
    FDropDownMenu.FreeNotification(Self);
  Invalidate;
end;

procedure TTyDropDownButton.SetArrowWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FArrowWidth = AValue then Exit;
  FArrowWidth := AValue;
  Invalidate;
end;

procedure TTyDropDownButton.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FDropDownMenu) then
    FDropDownMenu := nil;
end;

function TTyDropDownButton.ArrowZoneWidth(APPI: Integer): Integer;
begin
  // Logical -> device, same MulDiv convention the painter's Scale uses.
  Result := MulDiv(FArrowWidth, APPI, 96);
  if Result < 0 then Result := 0;
end;

function TTyDropDownButton.IsInArrowZone(AX: Integer): Boolean;
var
  ppi, cl, cr, zoneLeft: Integer;
begin
  { Measured from the PADDED CONTENT box — the same box DrawContent carves the arrow out of —
    so the divider the user can see is the first pixel that answers. It used to measure from
    the control's right edge, which put the boundary one right-padding to the RIGHT of the
    drawn divider and made the leading slice of the drawn arrow run the primary action. }
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  TyButtonContentSpanX(Width, ppi, CurrentStyle, cl, cr);
  zoneLeft := TyDropArrowZoneLeft(cl, cr, ArrowZoneWidth(ppi));
  // Far end = the CONTROL edge, not the content edge: the right padding carries no ink but
  // it is still the arrow end of the button, and stopping at the content edge would only
  // move the dead strip from the left of the chevron to its right.
  Result := (zoneLeft >= 0) and (AX >= zoneLeft) and (AX < Width);
end;

procedure TTyDropDownButton.DoDropDown;
var
  p: TPoint;
begin
  if Assigned(FOnDropDown) then FOnDropDown(Self);
  FRequestedPopup := FDropDownMenu <> nil;
  if not FRequestedPopup then Exit;
  // The themed PopUp needs a live window (ClientToScreen + a GUI form). Headless
  // callers stop after recording the intent above; only pop for real when mapped.
  if HandleAllocated then
  begin
    p := ClientToScreen(Point(0, Height));
    FDropDownMenu.PopUp(p.X, p.Y);
  end;
end;

procedure TTyDropDownButton.DropDownForTest;
begin
  DoDropDown;
end;

procedure TTyDropDownButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  // Remember WHERE the press landed; the native click that follows the mouse-up reads
  // it in Click to route arrow-zone presses to the drop-down. A non-left button leaves
  // the record cleared so it can never spuriously drop.
  if Button = mbLeft then FDownX := X else FDownX := -1;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyDropDownButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  // A release OUTSIDE the client suppresses the native Click that would otherwise
  // consume FDownX, so clear it here — otherwise a later keyboard/mnemonic/Default
  // Click (which never sets FDownX afresh) would misroute an old arrow-zone press to
  // the drop-down and swallow the primary OnClick.
  if (X < 0) or (Y < 0) or (X >= Width) or (Y >= Height) then
    FDownX := -1;
end;

procedure TTyDropDownButton.Click;
var
  inArrow: Boolean;
begin
  if not Enabled then Exit;
  // Decide from the mouse-down position: a press in the arrow zone drops the menu and
  // swallows the primary OnClick; anything else (incl. a keyboard-driven Click, where
  // FDownX stays -1) runs the normal button click.
  inArrow := (FDownX >= 0) and IsInArrowZone(FDownX);
  FDownX := -1;   // consume: the next Click without a fresh MouseDown is a primary click
  if inArrow then
    DoDropDown
  else
    inherited Click;
end;

procedure TTyDropDownButton.DrawContent(APainter: TTyPainter; const AContentRect: TRect;
  const AStyle: TTyStyleSet);
var
  divX, zoneLeft: Integer;
  captionRect, arrowRect: TRect;
  ctx: TBGRACanvas2D;
begin
  { The painter's Scale is the canonical logical->device (96-baseline) conversion, the same
    one RenderTo used to inset AContentRect. The zone itself comes from TyDropArrowZoneLeft —
    the ONE rule IsInArrowZone routes the click through — so the divider drawn below IS the
    first pixel that answers as an arrow. Fork this expression and the edge probe in
    tests/test.dropbuttons.pas goes red. }
  zoneLeft := TyDropArrowZoneLeft(AContentRect.Left, AContentRect.Right,
    APainter.Scale(FArrowWidth));
  if zoneLeft < 0 then
  begin
    // No room for an arrow (and so nothing hit-tests as one): a plain caption button.
    inherited DrawContent(APainter, AContentRect, AStyle);
    Exit;
  end;

  arrowRect := Rect(zoneLeft, AContentRect.Top, AContentRect.Right, AContentRect.Bottom);
  captionRect := Rect(AContentRect.Left, AContentRect.Top, zoneLeft, AContentRect.Bottom);

  // Caption in the left sub-rect (base class centres it there).
  inherited DrawContent(APainter, captionRect, AStyle);

  // 1px vertical divider between caption and arrow zone, in the themed border colour,
  // inset a few px top/bottom so it reads as a hairline. Canvas2D anti-aliases it.
  divX := arrowRect.Left;
  ctx := APainter.Bitmap.Canvas2D;
  ctx.beginPath;
  ctx.moveTo(divX + 0.5, arrowRect.Top + APainter.Scale(3));
  ctx.lineTo(divX + 0.5, arrowRect.Bottom - APainter.Scale(3));
  ctx.lineWidth := 1;
  ctx.strokeStyle(TyColorToBGRA(AStyle.BorderColor));
  ctx.stroke;

  // Centered small chevron (a shallow "v", fixed size), matching TTyComboBox's dropdown
  // chevron — a clean caret regardless of the button height/PPI.
  TyDrawDropChevron(APainter, ActiveController, arrowRect, AStyle.TextColor);
end;

procedure TTyDropDownButton.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  ppi: Integer;
begin
  // 基类量的是「标题 + 主题内边距」——即 RenderTo 内缩出来的那块内容区。
  inherited CalculatePreferredSize(PreferredWidth, PreferredHeight, WithThemeSpace);
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  // DrawContent 在同一块内容区里先切走右侧 APainter.Scale(FArrowWidth) 给箭头,标题
  // 只剩左边那半。ArrowZoneWidth 是同一个 MulDiv(...,ppi,96) 换算(命中测试也用它),
  // 所以「量到的」「画出来的」「点得到的」三者不会漂移。
  Inc(PreferredWidth, ArrowZoneWidth(ppi));
  if PreferredWidth < 1 then PreferredWidth := 1;
  { 高度依旧是 0 = LCL 的「本轴无意见」(基类已置 0,这里不碰):按钮只横向长,高度归
    排版的人管——工具条会把每个子控件钉到 ButtonHeight,控件再报一个高度就会来回顶,
    最后 LCL 以 "TControl.ChangeBounds loop detected" 收场。 }
end;

{ TTyMenuButton }

constructor TTyMenuButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRequestedPopup := False;
end;

procedure TTyMenuButton.SetDropDownMenu(AValue: TTyPopupMenu);
begin
  if FDropDownMenu = AValue then Exit;
  if FDropDownMenu <> nil then
    FDropDownMenu.RemoveFreeNotification(Self);
  FDropDownMenu := AValue;
  if FDropDownMenu <> nil then
    FDropDownMenu.FreeNotification(Self);
  Invalidate;
end;

procedure TTyMenuButton.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FDropDownMenu) then
    FDropDownMenu := nil;
end;

procedure TTyMenuButton.DoDropDown;
var
  p: TPoint;
begin
  if Assigned(FOnDropDown) then FOnDropDown(Self);
  FRequestedPopup := FDropDownMenu <> nil;
  if not FRequestedPopup then Exit;
  if HandleAllocated then
  begin
    p := ClientToScreen(Point(0, Height));
    FDropDownMenu.PopUp(p.X, p.Y);
  end;
end;

procedure TTyMenuButton.DropDownForTest;
begin
  DoDropDown;
end;

procedure TTyMenuButton.Click;
begin
  if not Enabled then Exit;
  // A MenuButton's click IS the drop — do it FIRST, then run the base OnClick/
  // ModalResult contract. Order matters: an OnClick handler that frees this button
  // (a common pattern) would leave DoDropDown dereferencing freed memory if it ran
  // last, so DoDropDown goes before inherited Click.
  DoDropDown;
  inherited Click;
end;

function TTyMenuButton.ArrowZoneWidth(APPI: Integer): Integer;
begin
  // 与 DrawContent 里 APainter.Scale(Metric('--drop-arrow-width', ...)) 同值:同一个
  // 主题度量、同一个 96 基线换算。皮肤调了这个度量,两边一起动。
  Result := MulDiv(ActiveController.Metric('--drop-arrow-width', TyDefaultDropArrowWidth),
    APPI, 96);
  if Result < 0 then Result := 0;
end;

procedure TTyMenuButton.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  ppi: Integer;
begin
  inherited CalculatePreferredSize(PreferredWidth, PreferredHeight, WithThemeSpace);
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  // 标题只画在箭头区左边(DrawContent 先切走尾部箭头区),所以宽度得把这一段算进来。
  Inc(PreferredWidth, ArrowZoneWidth(ppi));
  if PreferredWidth < 1 then PreferredWidth := 1;
  // 高度保持基类的 0(无意见),理由同 TTyButton:高度是排版的事,不是控件的事。
end;

procedure TTyMenuButton.DrawContent(APainter: TTyPainter; const AContentRect: TRect;
  const AStyle: TTyStyleSet);
var
  arrowW: Integer;
  captionRect, arrowRect: TRect;
begin
  arrowW := APainter.Scale(ActiveController.Metric('--drop-arrow-width', TyDefaultDropArrowWidth));
  if arrowW >= (AContentRect.Right - AContentRect.Left) then
    arrowW := (AContentRect.Right - AContentRect.Left) div 2;
  if arrowW < 0 then arrowW := 0;

  arrowRect := Rect(AContentRect.Right - arrowW, AContentRect.Top,
    AContentRect.Right, AContentRect.Bottom);
  captionRect := Rect(AContentRect.Left, AContentRect.Top,
    AContentRect.Right - arrowW, AContentRect.Bottom);

  // Caption centred in the sub-rect left of the trailing arrow (no divider — the
  // whole button is one clickable area).
  inherited DrawContent(APainter, captionRect, AStyle);

  if arrowW <= 0 then Exit;

  { The same chevron TTyDropDownButton draws twenty lines up, and TTyToolBar, and every
    combo-family field. This used to be a hand-rolled Canvas2D triangle with its own
    coefficients -- one of four such copies in the library -- so a "drop down" mark looked
    different depending on which button carried it. (Windows does draw the TOOLBAR split
    button's mark as a solid triangle rather than a chevron, but its combo box uses a chevron,
    and internal consistency across this library's own drop marks is worth more than matching
    one of the two Windows idioms on one of the sites.) }
  TyDrawDropChevron(APainter, ActiveController, arrowRect, AStyle.TextColor);
end;

end.
