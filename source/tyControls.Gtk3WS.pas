unit tyControls.Gtk3WS;
{$mode objfpc}{$H+}

{ GTK3-only widgetset helpers. The whole unit is gated on {$IFDEF LCLGTK3}: on every other build it
  is an EMPTY unit (no code, no cross-platform stubs) -- tyControls.PlatformWS references these
  functions only from inside its own {$IFDEF LCLGTK3}, so nothing off GTK3 ever names them.

  This is deliberately NOT a copy of the GTK2 helpers -- only the facilities that are both needed
  and portable to GTK3 are here (the WM-driven move, the Wayland-popup machinery, and the IME
  take-commit read). The library's GTK3 dependency has three tiers, and only one moves: (1) the
  LCL's cross-platform API; (2) GTK3's frozen native C entry points; (3) LCL-GTK3's INTERNAL classes,
  reached in exactly ONE place (Gtk3NativeWidget) -- so an upstream change is a one-function repair. }

interface

{$IFDEF LCLGTK3}
uses Classes, Types, Forms, Controls, tyControls.Types;   // Classes: TNotifyEvent; tyControls.Types: TRect / TTyPopupAnchorMode / IME types

{ Begin a WM-driven interactive move of AForm's window (mouse-DOWN, button held). Returns True when
  the system move started -- the caller must NOT then reposition by hand. }
function TyGtk3StartSystemMove(AForm: TCustomForm): Boolean;

{ True when this GTK3 build is running under a Wayland compositor. Wayland forbids a client from
  placing its own top-levels and has no shape extension, so popups must be positioned by the
  compositor and cut to square corners. }
function TyGtk3IsWayland: Boolean;

{ The FULL input-method commit the GTK3 backend just delivered, when the string the control got
  through UTF8KeyPress was a truncated (TUTF8Char = String[7]) copy of it; '' otherwise. LCL-GTK3's
  IM leaves the whole composed string in TGtk3WidgetSet.IMCommitStr; the control reads it here. }
function TyGtk3TakeImeCommit(const ATruncated: string): string;

{ Anchor APopup under AAnchor (drop below) via gdk_window_move_to_rect, so the compositor places it
  by the anchor. Call BEFORE Show. }
procedure TyGtk3MakePopup(APopup: TCustomForm; AAnchor: TControl);

{ The core the AAnchor overload builds on: anchor APopup to AParent's GdkWindow at an anchor rect
  ALREADY in AParent's client coords (never screen coords, which Wayland refuses). AMode picks
  drop-below vs fly-out-to-a-side. }
procedure TyGtk3MakePopupRect(APopup, AParent: TCustomForm; const AAnchorInParent: TRect;
  AMode: TTyPopupAnchorMode = pamBelow);

{ Drop the grab a mapped popup left behind (on hide) -- an idle-time Hide has no input event to
  release it, so the pointer stays captured by the vanished surface. }
procedure TyGtk3ReleasePopupGrab(APopup: TCustomForm);

{ Seat-grab APopup and dismiss (AOnDismiss) on a button-press outside its widget tree -- exactly how
  LCL's GtkMenu dismisses. AGroupId keeps a menu cascade's sibling levels "inside"; ASeatGrab adds
  the compositor grab (a menu passes False and rides LCL's own gtk_grab); AExcludeCtl (a menu bar)
  is treated as "inside" so clicking it switches menus instead of dismissing. }
procedure TyGtk3GrabPopup(APopup: TCustomForm; AOnDismiss: TNotifyEvent; AGroupId: Pointer = nil;
  ASeatGrab: Boolean = True; AExcludeCtl: TWinControl = nil);
{$ENDIF}

implementation

{$IFDEF LCLGTK3}
uses
  LazGtk3, LazGdk3, LazGLib2, LazGObject2, gtk3int, gtk3procs, gtk3widgets;

{ The native GtkWidget behind an LCL handle. This is the whole of tier 3: under GTK3 the Handle is a
  TGtk3Widget INSTANCE that owns the widget, so a raw cast would read an object header as a widget. }
function Gtk3NativeWidget(AControl: TWinControl): PGtkWidget;
begin
  Result := nil;
  if (AControl = nil) or (not AControl.HandleAllocated) then Exit;
  Result := TGtk3Widget(AControl.Handle).Widget;
end;

function TyGtk3IsWayland: Boolean;
begin
  { The backend already knows, and it is the same answer its own window-creation code branches on. }
  Result := (GTK3WidgetSet <> nil) and GTK3WidgetSet.IsWayland;
end;

function TyGtk3StartSystemMove(AForm: TCustomForm): Boolean;
var
  W, Top: PGtkWidget;
  P: TPoint;
begin
  { Hand the drag to the window manager instead of writing Left/Top per mouse-move, which the WM
    clamps to the whole-screen bounding box. }
  Result := False;
  W := Gtk3NativeWidget(AForm);
  if W = nil then Exit;
  Top := gtk_widget_get_toplevel(W);
  if (Top = nil) or (not Gtk3IsGtkWindow(PGObject(Top))) then Exit;
  { NOTE: a GTK_WINDOW_POPUP passes Gtk3IsGtkWindow too, and a modal dialog is mapped as an
    unmovable xdg_popup -- which is why dialogs cannot be dragged on Wayland (an LCL-GTK3 limitation,
    documented in the README). Guarding on the window type stopped the MAIN window dragging too. }
  P := Mouse.CursorPos;   // LCL screen coords == root-window coords
  gtk_window_begin_move_drag(PGtkWindow(Top), 1, P.X, P.Y, gtk_get_current_event_time());
  Result := True;
end;

function TyGtk3TakeImeCommit(const ATruncated: string): string;
var
  pending: string;
begin
  Result := '';
  if GTK3WidgetSet = nil then Exit;
  { Copy out first: the backend passes this same field BY REFERENCE into DeliverIMCommit, so blanking
    the property while a caller still holds a reference would cut the string out from under them. }
  pending := GTK3WidgetSet.IMCommitStr;
  if pending = '' then Exit;
  { Staleness guard, both halves needed. Equal length => nothing was truncated. Prefix => a left-over
    value from an earlier key (the backend skips its clear while Ctrl is held without Alt) would not
    begin with what THIS keystroke delivered. }
  if Length(pending) <= Length(ATruncated) then Exit;
  if Copy(pending, 1, Length(ATruncated)) <> ATruncated then Exit;
  GTK3WidgetSet.IMCommitStr := '';   // consumed: never let the same commit arrive twice
  Result := pending;
end;

procedure TyGtk3MakePopupRect(APopup, AParent: TCustomForm; const AAnchorInParent: TRect;
  AMode: TTyPopupAnchorMode);
var
  popW, parentTop: PGtkWidget;
  gdkWin, parentGdkWin: PGdkWindow;
  r: TGdkRectangle;
  rectAnchor, winAnchor: TGdkGravity;
begin
  { Every step bails out silently on failure -> worst case is the pre-fix centred flyout, never a
    crash. HandleNeeded realizes the popup's window while it is still hidden, so the parent +
    move_to_rect apply before Show maps it as the xdg_popup. }
  if (APopup = nil) or (AParent = nil) then Exit;
  APopup.HandleNeeded;
  if (not APopup.HandleAllocated) or (not AParent.HandleAllocated) then Exit;
  popW := Gtk3NativeWidget(APopup);
  if popW = nil then Exit;
  popW := gtk_widget_get_toplevel(popW);
  parentTop := gtk_widget_get_toplevel(Gtk3NativeWidget(AParent));
  if (popW = nil) or (parentTop = nil)
     or (not Gtk3IsGtkWindow(PGObject(popW))) or (not Gtk3IsGtkWindow(PGObject(parentTop))) then Exit;
  gtk_window_set_transient_for(PGtkWindow(popW), PGtkWindow(parentTop));
  gtk_window_set_type_hint(PGtkWindow(popW), GDK_WINDOW_TYPE_HINT_POPUP_MENU);
  gdkWin := gtk_widget_get_window(popW);
  parentGdkWin := gtk_widget_get_window(parentTop);
  if (gdkWin = nil) or (parentGdkWin = nil) then Exit;
  { The load-bearing call. gtk_window_set_transient_for sets only the GTK/WM transient hint and does
    NOT reach the GdkWindow, so without this the popup is a "temporary window without parent" and
    gdk_window_move_to_rect (which anchors to the transient-for GdkWindow) has nothing to position
    against on Wayland. Confirmed on a real GTK3/Wayland session. }
  gdk_window_set_transient_for(gdkWin, parentGdkWin);
  { The anchor rect is already in AParent's client coords. Gravity pairs:
      pamBelow   -> popup's top-left snaps to the anchor's bottom-left (drop under it)
      pamRightOf -> popup's top-left snaps to the anchor's top-right (submenu opens right)
      pamLeftOf  -> popup's top-right snaps to the anchor's top-left (mirrored submenu opens left)
    Flip/slide let the compositor nudge it back on-screen at the edges. }
  case AMode of
    pamRightOf: begin rectAnchor := GDK_GRAVITY_NORTH_EAST; winAnchor := GDK_GRAVITY_NORTH_WEST; end;
    pamLeftOf:  begin rectAnchor := GDK_GRAVITY_NORTH_WEST; winAnchor := GDK_GRAVITY_NORTH_EAST; end;
  else          begin rectAnchor := GDK_GRAVITY_SOUTH_WEST; winAnchor := GDK_GRAVITY_NORTH_WEST; end;
  end;
  r.x := AAnchorInParent.Left; r.y := AAnchorInParent.Top;
  r.width := AAnchorInParent.Right - AAnchorInParent.Left;
  r.height := AAnchorInParent.Bottom - AAnchorInParent.Top;
  gdk_window_move_to_rect(gdkWin, @r, rectAnchor, winAnchor,
    GDK_ANCHOR_FLIP + GDK_ANCHOR_SLIDE, 0, 0);
end;

procedure TyGtk3MakePopup(APopup: TCustomForm; AAnchor: TControl);
var
  parentForm: TCustomForm;
  tl: TPoint;
begin
  if (APopup = nil) or (AAnchor = nil) then Exit;
  parentForm := GetParentForm(AAnchor);
  if parentForm = nil then Exit;
  { The whole anchor control, in the parent form's client coords, dropped below. }
  tl := AAnchor.ClientToParent(Point(0, 0), parentForm);
  TyGtk3MakePopupRect(APopup, parentForm,
    Rect(tl.x, tl.y, tl.x + AAnchor.Width, tl.y + AAnchor.Height), pamBelow);
end;

procedure TyGtk3ReleasePopupGrab(APopup: TCustomForm);
var
  disp: PGdkDisplay;
  seat: PGdkSeat;
  grabW, popTop: PGtkWidget;
begin
  if not TyGtk3IsWayland then Exit;
  disp := gdk_display_get_default;
  if disp = nil then Exit;
  { A borderless popup maps as a GTK_WINDOW_POPUP that takes an app-level GTK grab (gtk_grab_add).
    While held, an outside click is redirected to the popup rather than the window under the pointer,
    so the main form never gets it and the popup never deactivates; and a stale grab left after an
    idle-time Hide swallows the next click. Drop it, but ONLY when the current grab belongs to THIS
    popup so a legitimate grab elsewhere is untouched. }
  grabW := gtk_grab_get_current;
  if (grabW <> nil) and APopup.HandleAllocated then
  begin
    popTop := gtk_widget_get_toplevel(Gtk3NativeWidget(APopup));
    if gtk_widget_get_toplevel(grabW) = popTop then
      gtk_grab_remove(grabW);
  end;
  { And the compositor/seat grab, in case the popup took one too. }
  seat := gdk_display_get_default_seat(disp);
  if seat <> nil then gdk_seat_ungrab(seat);
  gdk_display_flush(disp);
end;

type
  PTyNotify = ^TNotifyEvent;

{ unmap-signal trampoline: the compositor dismissed the grabbing popup (or we hid it ourselves) --
  fire the stored dismiss handler. Idempotent on the LCL side, so a self-hide is harmless. }
procedure TyGtk3PopupUnmapCb(widget: PGtkWidget; data: gpointer); cdecl;
begin
  if (data <> nil) and Assigned(PTyNotify(data)^) then
    PTyNotify(data)^(nil);
end;

procedure TyGtk3PopupDismissFree(data: gpointer; closure: PGClosure); cdecl;
begin
  if data <> nil then Dispose(PTyNotify(data));
end;

{ button-press-event trampoline. While the popup holds the grab, every click is reported here. Walk
  up from the ACTUAL clicked widget: reaching the popup toplevel means INSIDE (keep it open); the
  excluded bar is also "inside"; a matching cascade group is "inside"; otherwise the click landed
  outside -> dismiss. Widget-hierarchy based (not coordinates), reliable on Wayland -- exactly how
  LCL's gtkWSPopupMenuButtonPress dismisses a GtkMenu. Never returns True. }
function TyGtk3PopupButtonPressCb(widget: PGtkWidget; event: PGdkEvent; data: gpointer): gboolean; cdecl;
var
  ew, w, top, excl: PGtkWidget;
  grpSelf, grpClick: gpointer;
begin
  Result := False;
  if event = nil then Exit;
  ew := gtk_get_event_widget(event);
  if ew = nil then Exit;
  excl := PGtkWidget(g_object_get_data(PGObject(widget), PChar('ty_popup_excl')));
  w := ew;
  while w <> nil do
  begin
    if w = widget then Exit;
    if (excl <> nil) and (w = excl) then Exit;
    w := gtk_widget_get_parent(w);
  end;
  top := gtk_widget_get_toplevel(ew);
  grpSelf := g_object_get_data(PGObject(widget), PChar('ty_popup_group'));
  if (grpSelf <> nil) and (top <> nil) then
  begin
    grpClick := g_object_get_data(PGObject(top), PChar('ty_popup_group'));
    if grpClick = grpSelf then Exit;
  end;
  if (data <> nil) and Assigned(PTyNotify(data)^) then
    PTyNotify(data)^(nil);
end;

procedure TyGtk3GrabPopup(APopup: TCustomForm; AOnDismiss: TNotifyEvent; AGroupId: Pointer;
  ASeatGrab: Boolean; AExcludeCtl: TWinControl);
var
  popW, exclW: PGtkWidget;
  gdkWin: PGdkWindow;
  disp: PGdkDisplay;
  seat: PGdkSeat;
  d, d2: PTyNotify;
begin
  if (not TyGtk3IsWayland) or (APopup = nil) or (not APopup.HandleAllocated) then Exit;
  popW := Gtk3NativeWidget(APopup);
  if popW = nil then Exit;
  popW := gtk_widget_get_toplevel(popW);
  if popW = nil then Exit;
  { Tag the cascade group + the excluded bar widget every time (a reused form may re-open at a
    different level / under a different bar). }
  g_object_set_data(PGObject(popW), PChar('ty_popup_group'), AGroupId);
  if (AExcludeCtl <> nil) and AExcludeCtl.HandleAllocated then
    exclW := Gtk3NativeWidget(AExcludeCtl)
  else
    exclW := nil;
  g_object_set_data(PGObject(popW), PChar('ty_popup_excl'), exclW);
  if ASeatGrab then
  begin
    gdkWin := gtk_widget_get_window(popW);
    disp := gdk_display_get_default;
    if (gdkWin <> nil) and (disp <> nil) then
    begin
      seat := gdk_display_get_default_seat(disp);
      if seat <> nil then
        gdk_seat_grab(seat, gdkWin, GDK_SEAT_CAPABILITY_ALL, gboolean(True), nil, nil, nil, nil);
    end;
  end;
  { Wire the dismiss handlers once per widget. destroy_data frees the heap TMethod when the widget is
    destroyed. unmap catches a compositor-driven hide; button-press catches an outside click. }
  if g_object_get_data(PGObject(popW), PChar('ty_dismiss_wired')) = nil then
  begin
    New(d);
    d^ := AOnDismiss;
    g_signal_connect_data(PGObject(popW), PChar('unmap'), TGCallback(@TyGtk3PopupUnmapCb),
      d, TGClosureNotify(@TyGtk3PopupDismissFree), []);
    New(d2);
    d2^ := AOnDismiss;
    g_signal_connect_data(PGObject(popW), PChar('button-press-event'), TGCallback(@TyGtk3PopupButtonPressCb),
      d2, TGClosureNotify(@TyGtk3PopupDismissFree), []);
    g_object_set_data(PGObject(popW), PChar('ty_dismiss_wired'), Pointer(1));
  end;
end;
{$ENDIF}

end.
