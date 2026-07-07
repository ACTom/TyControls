unit tyControls.Popup;
{$mode objfpc}{$H+}

{ Shared dropdown-popup helpers used by TTyComboBox, TTyDateTimePicker, etc.

  TyPopupRect   — pure function: compute a screen rect for a dropdown,
                  dropping below the anchor and flipping above when there
                  isn't room below within the screen height.

  TTyDropdownPopup — reusable borderless popup-window host.  Extracted from
                     TTyComboBox.DoDropDown / ApplyPopupRegion / PopupResize /
                     PopupDeactivate so multiple controls can share the same
                     battle-tested mechanics.
}

interface
uses
  Classes, SysUtils, Types, Controls, Forms, LCLType, LCLIntf,
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  tyControls.Types, tyControls.Controller, tyControls.QtWS;

// ---------------------------------------------------------------------------
// TyPopupRect — screen rect for a dropdown of (AContentW x AContentH)
// anchored to AAnchorScreen (screen coordinates).
// Drops below the anchor; flips above when there isn't AContentH room below
// within AScreenH.
// ---------------------------------------------------------------------------
function TyPopupRect(const AAnchorScreen: TRect;
  AContentW, AContentH, AScreenH: Integer): TRect;

// ---------------------------------------------------------------------------
// TTyDropdownPopup — borderless popup-window host.
// ---------------------------------------------------------------------------
type
  TTyDropdownPopup = class
  private
    FForm        : TForm;
    FContent     : TControl;
    FAnchor      : TControl;        // anchor control of the last Popup (for in-place Resize)
    FRect        : TRect;           // last computed screen rect (for deferred Qt re-apply)
    FCornerRadiusLogical: Integer;
    FOnClose     : TNotifyEvent;
    FController  : TTyStyleController; // for resolving themed corner-radius in ApplyRegion
    FClosing     : Boolean;         // guard: prevents re-entrant deactivate→close→deactivate loops
    FCloseUpTick : QWord;           // tick when popup last closed (deactivate-reopen-race guard)
    FNoActivate  : Boolean;         // show without stealing activation (autocomplete popups)

    procedure FormDeactivate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure DeferredReapplyGeometry(Data: PtrInt);
    procedure ApplyRegion(AWidth, AHeight: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    { Parent AControl into the form with Align=alClient.  Call before Popup.
      Can be called only once; subsequent calls are ignored. The helper only
      PARENTS the content; the caller retains ownership (unless AControl.Owner =
      the form), so the caller is responsible for freeing it. }
    procedure SetContent(AControl: TControl);

    { Compute the screen rect via TyPopupRect, size/show the form non-activating,
      apply the rounded region.  AAnchor is the control the popup drops from
      (its ClientToScreen(Rect(0,0,Width,Height)) is used as the anchor rect). }
    procedure Popup(AAnchor: TControl; AContentWidth, AContentHeight: Integer);

    { Re-anchor + resize an ALREADY-open popup in place — recomputes the drop rect
      from the last anchor and re-applies the region, but does NOT re-Show and does
      NOT activate. Used to refresh an autocomplete popup as the filtered row count
      changes without stealing focus back from the owner's editor. No-op if closed. }
    procedure Resize(AContentWidth, AContentHeight: Integer);

    { Hide the popup and fire OnClose (guarded against re-entrancy). }
    procedure Close;

    { True while the popup form is visible. }
    function IsOpen: Boolean;

    { Logical corner radius for the popup window's rounded region (matches the
      hosted content control's theme; 0 = rectangular). }
    property CornerRadiusLogical: Integer
      read FCornerRadiusLogical write FCornerRadiusLogical;

    { Optional style controller used in ApplyRegion to resolve the background
      color for the popup form (fills the corner gaps).  When nil the form
      Color is left at its default.  Set before calling Popup. }
    property Controller: TTyStyleController
      read FController write FController;

    { When True the popup is shown WITHOUT taking activation, so the owner control
      (e.g. an editable ComboBox's embedded edit) keeps focus and keystrokes keep
      flowing. Win32-only (WS_EX_NOACTIVATE); a no-op elsewhere. Because such a
      window never activates it also never fires OnDeactivate, so the OWNER must
      drive Close (focus-out / row-click / Escape). Default False (list-mode popups
      activate and auto-close on deactivate, unchanged). Set before Popup. }
    property NoActivate: Boolean read FNoActivate write FNoActivate;

    { Fired when the popup closes (user click-away, Escape, or programmatic Close). }
    property OnClose: TNotifyEvent read FOnClose write FOnClose;

    { The hosted TForm.  Callers may set KeyPreview / OnKeyDown on it. }
    property Form: TForm read FForm;

    { Tick value (GetTickCount64) recorded at the moment the popup last closed.
      The owner can use this to guard against the click-while-open reopen race:
      PopupDeactivate fires Close BEFORE the owner control's Click handler runs,
      so Click sees IsOpen=False and would reopen.  Guard: reopen only when
      (GetTickCount64 - CloseUpTick > 200). }
    property CloseUpTick: QWord read FCloseUpTick;
  end;

implementation

// ---------------------------------------------------------------------------
// TyPopupRect
// ---------------------------------------------------------------------------
function TyPopupRect(const AAnchorScreen: TRect;
  AContentW, AContentH, AScreenH: Integer): TRect;
var
  belowTop: Integer;
begin
  belowTop := AAnchorScreen.Bottom;
  if (belowTop + AContentH > AScreenH) and
     (AAnchorScreen.Top - AContentH >= 0) then
  begin
    // Flip above: not enough room below, and there IS room above.
    Result.Top    := AAnchorScreen.Top - AContentH;
    Result.Bottom := AAnchorScreen.Top;
  end
  else
  begin
    // Drop below the anchor (default).
    Result.Top    := belowTop;
    Result.Bottom := belowTop + AContentH;
  end;
  Result.Left  := AAnchorScreen.Left;
  Result.Right := AAnchorScreen.Left + AContentW;
end;

// ---------------------------------------------------------------------------
// TTyDropdownPopup
// ---------------------------------------------------------------------------

constructor TTyDropdownPopup.Create;
begin
  inherited Create;
  FCornerRadiusLogical := 0;
  FClosing := False;
  FCloseUpTick := 0;
  FController := nil;
  FNoActivate := False;
  FAnchor := nil;

  FForm := TForm.CreateNew(nil);
  FForm.BorderStyle  := bsNone;
  FForm.ShowInTaskBar := stNever;
  FForm.FormStyle    := fsStayOnTop;
  FForm.KeyPreview   := True;
  FForm.OnDeactivate := @FormDeactivate;
  FForm.OnResize     := @FormResize;
end;

destructor TTyDropdownPopup.Destroy;
begin
  // Detach handlers before freeing the form to prevent callbacks into a
  // half-destroyed object during TForm's own destruction.
  if FForm <> nil then
  begin
    FForm.OnDeactivate := nil;
    FForm.OnResize     := nil;
    Application.RemoveAsyncCalls(Self);
    FreeAndNil(FForm);
    FContent := nil;  // only parented here; freed by its own owner, not us
  end;
  inherited Destroy;
end;

procedure TTyDropdownPopup.SetContent(AControl: TControl);
begin
  if FContent <> nil then Exit;   // already set; ownership is for the form's lifetime
  FContent := AControl;
  FContent.Parent := FForm;
  FContent.Align  := alClient;
end;

function TTyDropdownPopup.IsOpen: Boolean;
begin
  Result := (FForm <> nil) and FForm.Visible;
end;

procedure TTyDropdownPopup.Popup(AAnchor: TControl;
  AContentWidth, AContentHeight: Integer);
var
  AnchorTL: TPoint;
  AnchorScreen: TRect;
  ParentForm: TCustomForm;
  PopupW, PopupH: Integer;
  {$IFDEF WINDOWS}exStyle: PtrInt;{$ENDIF}
begin
  FAnchor := AAnchor;   // remembered so Resize can re-anchor an already-open popup
  // Resolve the anchor control's screen rectangle.
  AnchorTL := AAnchor.ClientToScreen(Types.Point(0, 0));
  AnchorScreen := Types.Rect(AnchorTL.X, AnchorTL.Y,
    AnchorTL.X + AAnchor.Width, AnchorTL.Y + AAnchor.Height);

  // Compute drop/flip rect.
  FRect := TyPopupRect(AnchorScreen, AContentWidth, AContentHeight, Screen.Height);
  PopupW := FRect.Right - FRect.Left;
  PopupH := FRect.Bottom - FRect.Top;

  // Wire PopupParent so the popup is modal-stacked above the owner form (and
  // stays in front when focus returns to the owner).
  ParentForm := GetParentForm(AAnchor);
  if ParentForm <> nil then
  begin
    FForm.PopupParent := ParentForm;
    FForm.PopupMode   := pmExplicit;
  end;

  // Qt: re-type as Qt::Popup BEFORE Show (app-positioned, no top-left flash,
  // correct grab behaviour).  No-op on Win32/GTK2/Cocoa.
  TyQtMakePopup(FForm);

  {$IFDEF WINDOWS}
  // Toggle WS_EX_NOACTIVATE per NoActivate so the (reused) form matches the current
  // mode: set it BEFORE Show so even ShowWindow(SW_SHOW) is passive and the owner's
  // embedded editor keeps focus; clear it for ordinary activating popups. Needs the
  // handle first.
  if not FForm.HandleAllocated then FForm.HandleNeeded;
  exStyle := Windows.GetWindowLongPtr(FForm.Handle, Windows.GWL_EXSTYLE);
  if FNoActivate then
    exStyle := exStyle or Windows.WS_EX_NOACTIVATE
  else
    exStyle := exStyle and not Windows.WS_EX_NOACTIVATE;
  Windows.SetWindowLongPtr(FForm.Handle, Windows.GWL_EXSTYLE, exStyle);
  {$ENDIF}

  FForm.SetBounds(FRect.Left, FRect.Top, PopupW, PopupH);
  FForm.Show;

  // Qt/X11 may re-place + un-mask a frameless window at MAP time; re-assert
  // NOW and again next event-loop turn.
  FForm.SetBounds(FRect.Left, FRect.Top, PopupW, PopupH);
  ApplyRegion(PopupW, PopupH);
  Application.QueueAsyncCall(@DeferredReapplyGeometry, 0);
end;

procedure TTyDropdownPopup.Resize(AContentWidth, AContentHeight: Integer);
var
  AnchorTL: TPoint;
  AnchorScreen: TRect;
  W, H: Integer;
begin
  if (FForm = nil) or (not FForm.Visible) or (FAnchor = nil) then Exit;
  // Recompute the drop/flip rect from the same anchor (position may shift when the
  // row count changes), then reposition WITHOUT re-Show — no activation, so the
  // owner's editor keeps focus while the suggestion list refreshes.
  AnchorTL := FAnchor.ClientToScreen(Types.Point(0, 0));
  AnchorScreen := Types.Rect(AnchorTL.X, AnchorTL.Y,
    AnchorTL.X + FAnchor.Width, AnchorTL.Y + FAnchor.Height);
  FRect := TyPopupRect(AnchorScreen, AContentWidth, AContentHeight, Screen.Height);
  W := FRect.Right - FRect.Left;
  H := FRect.Bottom - FRect.Top;
  FForm.SetBounds(FRect.Left, FRect.Top, W, H);
  ApplyRegion(W, H);
end;

procedure TTyDropdownPopup.Close;
var WasVisible: Boolean;
begin
  if FClosing then Exit;
  FClosing := True;
  try
    WasVisible := (FForm <> nil) and FForm.Visible;
    if WasVisible then
    begin
      // Detach deactivate to prevent re-entering Close from TForm.Hide.
      FForm.OnDeactivate := nil;
      FForm.Hide;
      FForm.OnDeactivate := @FormDeactivate;
    end;
    { Only stamp the reopen-race tick and notify when a genuinely-open popup closed. A Close on
      an already-hidden popup is a true no-op — this makes Close idempotent, so a pick that both
      commits and closes cannot fire OnClose twice (commit→Close, then a trailing deactivate
      →Close) or re-run cleanup on a stale state. }
    if WasVisible then
    begin
      FCloseUpTick := GetTickCount64;
      if Assigned(FOnClose) then
        FOnClose(Self);
    end;
  finally
    FClosing := False;
  end;
end;

// ---------------------------------------------------------------------------
// Private implementation
// ---------------------------------------------------------------------------

{ Shape the popup window with a rounded region matching CornerRadiusLogical
  (scaled to the popup's device PPI).  Cross-platform via LCLIntf
  CreateRoundRectRgn / SetWindowRgn.  No-op when radius=0 or on Wayland
  (no XShape).  Re-applied on every Popup so it follows size/PPI/theme. }
procedure TTyDropdownPopup.ApplyRegion(AWidth, AHeight: Integer);
var
  S : TTyStyleSet;
  d : Integer;
  Rgn: HRGN;
begin
  if (FForm = nil) or (not FForm.HandleAllocated) then Exit;

  // Paint the window background with the popup's surface color so the corner
  // gaps outside the rounded region are not the default dark form Color on
  // Linux ('black corners') where a widgetset region is a no-op.
  if (FController <> nil) then
  begin
    S := FController.Model.ResolveStyle('TyListBox', '', []);
    if S.Background.Kind = tfkSolid then
      FForm.Color := TyColorToLCL(S.Background.Color);
  end;

  // Wayland ignores window masks (no XShape): the content must paint square
  // corners (ForceSquareSurface was set on the content control in Popup), so
  // we skip shaping and keep a clean rectangle.
  if TyQtIsWayland then Exit;

  // Scale logical radius to device pixels; the rounded-rect region uses the
  // full corner diameter (2 × radius).
  d := MulDiv(FCornerRadiusLogical, FForm.Font.PixelsPerInch, 96) * 2;
  if d <= 0 then
  begin
    // Radius 0: leave rectangular (clear any stale mask from a prior show).
    // Qt: SetWindowRgn(..,0) is a no-op; clear deep first.
    if FContent is TWinControl then
      TyQtClearWindowMaskDeep(FForm, TWinControl(FContent))
    else
      TyQtClearWindowMaskDeep(FForm, nil);
    SetWindowRgn(FForm.Handle, 0, True);
    Exit;
  end;

  // +1 on extents: CreateRoundRectRgn right/bottom are exclusive.
  // SetWindowRgn takes ownership of Rgn; do not delete it.
  Rgn := CreateRoundRectRgn(0, 0, AWidth + 1, AHeight + 1, d, d);
  // Qt6/X11 (QTSCROLLABLEFORMS): also mask the scroll-area viewport and the
  // alClient content control's own native widget, which the top-level mask
  // never reaches.  No-op off Qt.
  if FContent is TWinControl then
    TyQtMaskWindowDeep(FForm, TWinControl(FContent), Rgn)
  else
    TyQtMaskWindowDeep(FForm, nil, Rgn);
  SetWindowRgn(FForm.Handle, Rgn, True);
end;

{ Qt drops a window's mask on every resize (layout-driven resize after Show
  wipes the region → opaque corners).  Re-assert it on every resize event so
  the rounded corners survive.  Idempotent on Win32/GTK2. }
procedure TTyDropdownPopup.FormResize(Sender: TObject);
begin
  if (FForm <> nil) and FForm.Visible and FForm.HandleAllocated then
    ApplyRegion(FForm.Width, FForm.Height);
end;

{ Popup lost focus (user clicked away) → close. }
procedure TTyDropdownPopup.FormDeactivate(Sender: TObject);
begin
  { A NoActivate (autocomplete) popup never legitimately takes activation, so a
    deactivate here is spurious (e.g. the owner re-focusing its embedded editor
    right after Show) — the OWNER drives close in that mode, not deactivate. }
  if FNoActivate then Exit;
  Close;
end;

{ One event-loop turn after Show, once Qt's map-time reparent/flag churn has
  settled — re-assert bounds and region so they stick on Qt/X11. }
procedure TTyDropdownPopup.DeferredReapplyGeometry(Data: PtrInt);
begin
  if (FForm = nil) or (not FForm.Visible) then Exit;
  FForm.SetBounds(FRect.Left, FRect.Top,
    FRect.Right - FRect.Left, FRect.Bottom - FRect.Top);
  ApplyRegion(FRect.Right - FRect.Left, FRect.Bottom - FRect.Top);
end;

end.
