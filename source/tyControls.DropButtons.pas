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
  tyControls.Button, tyControls.Menu;

const
  { Default width (logical px, 96-PPI baseline) of a split button's right-hand
    arrow zone. Scaled to device px at paint / hit-test time. }
  TyDefaultDropArrowWidth = 18;

{ Pure hit-test seam: True iff a click at device-x AClickX (0-based within the
  control) falls in the RIGHT arrow zone of a split button AWidthPx wide whose arrow
  zone is AArrowWidthPx wide. The arrow zone is the rightmost AArrowWidthPx of the
  control; a click at exactly (AWidthPx - AArrowWidthPx) is the first arrow-zone
  pixel. Degenerate widths (arrow >= control, or non-positive) fall back sanely so a
  tiny/zero button never traps every click as an arrow hit. }
function TyDropArrowHit(AClickX, AWidthPx, AArrowWidthPx: Integer): Boolean;

type
  { SPLIT drop-down button: caption (left, fires OnClick) + arrow zone (right, opens
    the menu), divided by a 1px line. }
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
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
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
    menu (Click itself routes to the drop). No split, no divider. }
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
    { Caption on the left, a trailing downward arrow on the right (AStyle.TextColor). }
    procedure DrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet); override;
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

function TyDropArrowHit(AClickX, AWidthPx, AArrowWidthPx: Integer): Boolean;
begin
  // Degenerate: no arrow zone, or it would swallow the whole (or an impossibly wide)
  // control — treat nothing as an arrow hit so the primary action still works.
  if (AArrowWidthPx <= 0) or (AWidthPx <= 0) or (AArrowWidthPx >= AWidthPx) then
    Exit(False);
  Result := AClickX >= (AWidthPx - AArrowWidthPx);
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
begin
  Result := TyDropArrowHit(AX, Width, ArrowZoneWidth(Font.PixelsPerInch));
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
  arrowW, divX, cx, cy, half, hh: Integer;
  captionRect, arrowRect: TRect;
  ctx: TBGRACanvas2D;
begin
  // The painter's Scale is the canonical logical->device (96-baseline) conversion,
  // the same one RenderTo used to inset AContentRect — so the drawn arrow zone lines
  // up with the device-space arrow zone the MouseUp hit-test (ArrowZoneWidth) uses.
  arrowW := APainter.Scale(FArrowWidth);
  if arrowW < 0 then arrowW := 0;

  // Guard against a too-narrow content rect: never let the arrow zone consume the
  // whole caption area (leave at least a sliver for the caption).
  if arrowW >= (AContentRect.Right - AContentRect.Left) then
    arrowW := (AContentRect.Right - AContentRect.Left) div 2;

  arrowRect := Rect(AContentRect.Right - arrowW, AContentRect.Top,
    AContentRect.Right, AContentRect.Bottom);
  captionRect := Rect(AContentRect.Left, AContentRect.Top,
    AContentRect.Right - arrowW, AContentRect.Bottom);

  // Caption in the left sub-rect (base class centres it there).
  inherited DrawContent(APainter, captionRect, AStyle);

  if arrowW <= 0 then Exit;

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

  // Centered downward triangle filled with the text colour. Half-width ~ 1/4 of the
  // arrow zone, height ~ half that, so it reads as a small caret regardless of PPI.
  cx := (arrowRect.Left + arrowRect.Right) div 2;
  cy := (arrowRect.Top + arrowRect.Bottom) div 2;
  half := APainter.Scale(4);
  if half < 3 then half := 3;
  hh := (half * 6) div 10;   // ~0.6 aspect -> a squat, clearly-downward triangle
  if hh < 2 then hh := 2;

  ctx := APainter.Bitmap.Canvas2D;
  ctx.beginPath;
  ctx.moveTo(cx - half, cy - hh);   // top-left
  ctx.lineTo(cx + half, cy - hh);   // top-right
  ctx.lineTo(cx, cy + hh);          // bottom apex (points down)
  ctx.closePath;
  ctx.fillStyle(TyColorToBGRA(AStyle.TextColor));
  ctx.fill;
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
  inherited Click;   // still runs the base ModalResult + OnClick contract
  DoDropDown;        // a MenuButton's click IS the drop
end;

procedure TTyMenuButton.DrawContent(APainter: TTyPainter; const AContentRect: TRect;
  const AStyle: TTyStyleSet);
var
  arrowW, cx, cy, half, hh: Integer;
  captionRect, arrowRect: TRect;
  ctx: TBGRACanvas2D;
begin
  arrowW := APainter.Scale(TyDefaultDropArrowWidth);
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

  cx := (arrowRect.Left + arrowRect.Right) div 2;
  cy := (arrowRect.Top + arrowRect.Bottom) div 2;
  half := APainter.Scale(4);
  if half < 3 then half := 3;
  hh := (half * 6) div 10;
  if hh < 2 then hh := 2;

  ctx := APainter.Bitmap.Canvas2D;
  ctx.beginPath;
  ctx.moveTo(cx - half, cy - hh);
  ctx.lineTo(cx + half, cy - hh);
  ctx.lineTo(cx, cy + hh);
  ctx.closePath;
  ctx.fillStyle(TyColorToBGRA(AStyle.TextColor));
  ctx.fill;
end;

end.
