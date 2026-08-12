unit tyControls.GtkWS;
{$mode objfpc}{$H+}

{ GTK2-only widgetset helpers for the Linux fixes. EVERY function is a NO-OP on non-GTK2 widgetsets
  (Win32 / Qt5 / Qt6 / Cocoa / GTK3), so those already-working paths are completely untouched — only
  an LCLGTK2 build links the real bodies. Two facilities:

  1. WM-driven window move (TyGtkStartSystemMove): a borderless TForm dragged by writing Left/Top is
     repositioned with gtk_window_move(), which the WM clamps to the bounding box of the whole X
     screen — on a multi-monitor layout that is not bottom-aligned, the lower monitor's bottom is a
     hard floor. gtk_window_begin_move_drag() hands the move to the WM (the GTK2 analogue of Qt6's
     QWindow.startSystemMove()).

  2. Input method (TyGtkInstallIme): stock LCL ships NO working GTK2 IME — its commit/preedit
     delivery is all behind a WITH_GTK2_IM define, never defined anywhere, so composed CJK never
     reaches a control (even SynEdit). We attach our OWN GtkIMContext to the control: a key snooper
     feeds key events to it BEFORE LCL's widgets see them (so when the IM consumes a composition key
     LCL never gets it, and LCL's own dead global context never competes), and the context's 'commit'
     signal hands the FULL committed UTF-8 string to the control (also dodging the TUTF8Char/String[7]
     truncation that bites Qt6). Focus is driven from the control's DoEnter/DoExit. }

interface
uses Classes, Types, Forms, Controls, tyControls.Types;   // Classes: TNotifyEvent; Types: TRect (anchor rect); tyControls.Types: shared TTyImeCommitEvent / TTyImeCaretQuery

{ Begin a WM-driven interactive move of AForm's window (call from a mouse-DOWN handler while the
  button is held). Returns True if the system move started — then the caller must NOT do its own
  per-move repositioning. GTK2 only; returns False elsewhere so the caller keeps its fallback. }
function TyGtkStartSystemMove(AForm: TCustomForm): Boolean;

{ GTK3/Wayland: declare AForm's whole window OPAQUE (gdk_window_set_opaque_region), so the compositor
  stops showing the desktop through any pixel with alpha<255. On GTK3 a borderless form gets an RGBA
  (32-bit) visual for corners/shadow, and the library's alpha effects (disabled dimming, transparent
  labels/graphics) then leak the desktop through. Rounded corners are already square on Wayland, so
  nothing is lost. Call once the window is mapped (and after resize). No-op off GTK3-Wayland. }
procedure TyGtk3SetWindowOpaque(AForm: TCustomForm);

{ Attach our own GtkIMContext to AControl so it receives FULL composed CJK commits via AOnCommit.
  ACaretQuery (may be nil) returns the caret rect (client device px) used to place the candidate
  window. Returns an opaque handle to free with the control's normal teardown (TObject.Free / the
  shared TyQtUninstallIme), or nil off GTK2 / on failure. }
function TyGtkInstallIme(AControl: TWinControl; AOnCommit: TTyImeCommitEvent;
  ACaretQuery: TTyImeCaretQuery): TObject;

{ Tell a TyGtkInstallIme handle the control gained/lost focus (drive from DoEnter/DoExit). The IM
  only composes while focused. Safe on nil / non-GTK handles / off GTK2. }
procedure TyGtkImeSetFocus(AHandle: TObject; AFocused: Boolean);

{ The FULL input-method commit the GTK3 backend just delivered, when the string a control
  received through UTF8KeyPress was a truncated copy of it; '' otherwise (including on every
  non-GTK3 build, so the call site needs no IFDEF).

  WHY this exists. LCL-GTK3 already runs a working IM: its commit handler puts the whole
  composed string into TGtk3WidgetSet.IMCommitStr, a plain string. Both of the paths that
  hand it to a control then copy it into a TUTF8Char -- which is String[7]. A CJK codepoint
  is three bytes, so nine bytes of three characters arrive as two characters and an orphan
  lead byte. That is the entire "only two characters commit" defect; native TEdit escapes it
  because a GtkEntry does its own IM internally and never crosses that boundary.

  So the fix is not to install another IM context, the way the GTK2 helper above does. That
  is not even possible here: gtk_key_snooper_install is absent from every Lazarus GTK3
  binding, and a key-press-event handler would sit BEHIND the backend's own, which already
  returns True for each key its IM consumed. The untruncated string is simply still sitting
  in IMCommitStr when the control's UTF8KeyPress runs, so the control reads it there.

  ATruncated is what UTF8KeyPress was handed. A result is returned only when the pending
  string is strictly longer AND starts with it -- the backend does not always clear
  IMCommitStr (it skips the clear while Ctrl is held without Alt), so a stale value must not
  be mistaken for this keystroke's. The field is consumed on a hit so it cannot be read twice. }
function TyGtkTakeImeCommit(const ATruncated: string): string;

{ True when this is a GTK3 build running on a Wayland compositor. False on GTK2 (which has no
  Wayland backend at all) and off GTK entirely.

  WHY it matters here rather than only in the Qt helper: Wayland forbids a client from placing
  its own windows and has no shape extension, so every popup this library cuts to a rounded or
  arrowed silhouette has to degrade to a square one. That rule used to be asked of
  TyQtIsWayland, which answers False on every non-Qt widgetset -- correct while Linux meant Qt
  or GTK2, and wrong the moment GTK3 became the default Linux widgetset. }
function TyGtkIsWayland: Boolean;

type
  { How a Wayland popup snaps to its anchor rect: drop directly BELOW it (dropdowns, bar cells,
    context menus) or fly out to one SIDE of it (a submenu cascade -- LTR opens right, mirrored
    opens left). Widgetset-neutral so it can sit in the shared interface; only GTK3 reads it. }
  TTyPopupAnchorMode = (pamBelow, pamRightOf, pamLeftOf);

{ Turn APopup into a Wayland xdg_popup anchored under AAnchor (via gdk_window_move_to_rect), so
  the compositor places it by the anchor instead of centring a free-floating top-level. GTK3
  only; a no-op on GTK2 (X11) and non-GTK. Call BEFORE Show, like TyQtMakePopup -- but GTK needs
  the ANCHOR control passed in (Qt derives the anchor from the geometry itself; GDK does not, so
  a one-argument mirror is impossible). }
procedure TyGtk3MakePopup(APopup: TCustomForm; AAnchor: TControl);

{ The core the AAnchor-control overload builds on: Wayland-anchor APopup to AParent's GdkWindow
  using an anchor rect ALREADY in AParent's client coords (a plain LCL walk produces it -- never
  screen coords, which Wayland refuses). Menus call this directly because their anchor is a bar
  cell or a parent-row edge, not a whole control, and a submenu's parent is the PARENT POPUP, not
  the app form. AMode picks drop-below vs fly-out-to-a-side. GTK3 only; no-op elsewhere. }
procedure TyGtk3MakePopupRect(APopup, AParent: TCustomForm; const AAnchorInParent: TRect;
  AMode: TTyPopupAnchorMode = pamBelow);

{ GTK3/Wayland: explicitly drop the seat grab a mapped popup left behind. A dropdown that hides at
  idle (the deferred close) rather than during the click event has no input event left to release
  the grab, so the pointer stays captured by the vanished surface -- no hover reaches other
  controls and the next click is swallowed. Call right after hiding the popup. No-op off
  GTK3-Wayland. }
procedure TyGtk3ReleasePopupGrab(APopup: TCustomForm);

{ GTK3/Wayland: seat-grab APopup and wire a button-press handler that fires AOnDismiss when a click
  lands OUTSIDE the popup's widget tree -- exactly how LCL's own GtkMenu dismisses (walk up from the
  clicked widget; if it never reaches the popup it was outside). Reliable on Wayland because it is
  widget-hierarchy based, not coordinate based. Call AFTER the popup is mapped.

  AGroupId lets a MULTI-LEVEL popup (a menu cascade, where each submenu is a SEPARATE top-level)
  survive clicks on its sibling levels: pass the same non-nil id (e.g. the root popup pointer) when
  grabbing every level, and a click whose top-level carries the same group id counts as "inside".
  Pass nil for a single popup (a combobox dropdown), where any outside click dismisses.

  ASeatGrab adds a compositor seat grab (needed to route outside clicks to a plain dropdown). A
  MENU already lives under LCL's own gtk_grab AND drives hover-switch by re-showing one reused form,
  which a seat grab fights -- pass False there and rely on the existing gtk_grab.

  AExcludeCtl is a control (the menu BAR) whose own clicks must NOT dismiss -- the bar switches/opens
  menus itself, so a click that walks up THROUGH it is treated as "inside". No-op off GTK3-Wayland. }
procedure TyGtk3GrabPopup(APopup: TCustomForm; AOnDismiss: TNotifyEvent; AGroupId: Pointer = nil;
  ASeatGrab: Boolean = True; AExcludeCtl: TWinControl = nil);

implementation

{$IFDEF LCLGTK2}
uses gtk2, gdk2, glib2, Gtk2Proc;   // Gtk2Proc: GetControlWindow (the control's client GdkWindow); Types comes from the interface uses

function TyGtkStartSystemMove(AForm: TCustomForm): Boolean;
var
  W, Top: PGtkWidget;
  P: TPoint;
begin
  Result := False;
  if (AForm = nil) or (not AForm.HandleAllocated) then Exit;
  W := {%H-}PGtkWidget(AForm.Handle);
  if W = nil then Exit;
  Top := gtk_widget_get_toplevel(W);
  if (Top = nil) or not GTK_IS_WINDOW(Top) then Exit;
  P := Mouse.CursorPos;   // LCL screen coords == X11 root-window coords
  gtk_window_begin_move_drag(GTK_WINDOW(Top), 1, P.X, P.Y, gtk_get_current_event_time());
  Result := True;
end;

procedure TyGtk3SetWindowOpaque(AForm: TCustomForm);
begin
  // GTK2 is X11-only -- no RGBA-window desktop show-through to guard against.
end;

type
  TTyGtkImeHook = class
  private
    FIM: PGtkIMContext;
    FWidget: PGtkWidget;
    FOnCommit: TTyImeCommitEvent;
    FCaretQuery: TTyImeCaretQuery;
    FSnooperID: guint;
    FFocused: Boolean;
    function ToplevelWin: PGdkWindow;   // the form's window (what the IM anchors to)
    procedure UpdateCursorLocation;
  public
    constructor Create(AWidget: PGtkWidget; AOnCommit: TTyImeCommitEvent; ACaretQuery: TTyImeCaretQuery);
    destructor Destroy; override;
    procedure SetFocused(AFocused: Boolean);
    procedure DoCommit(const S: string);
    function FilterKey(event: PGdkEventKey): Boolean;
  end;

{ GTK 'commit' signal: void commit(GtkIMContext*, gchar* str, gpointer data). }
procedure TyGtkImeCommitCB(context: PGtkIMContext; str: PgChar; data: gpointer); cdecl;
begin
  if (data <> nil) and (str <> nil) then
    TTyGtkImeHook(data).DoCommit(PChar(str));   // PChar -> string (auto-converts the UTF-8 bytes)
end;

{ Process-wide key snooper: see every key BEFORE widget dispatch. Only the FOCUSED control's hook
  acts; if its IM consumes the key, return nonzero so LCL never processes it. }
function TyGtkImeSnoop(grab_widget: PGtkWidget; event: PGdkEventKey; data: gpointer): gint; cdecl;
begin
  Result := 0;
  if (data <> nil) and TTyGtkImeHook(data).FilterKey(event) then
    Result := 1;
end;

constructor TTyGtkImeHook.Create(AWidget: PGtkWidget; AOnCommit: TTyImeCommitEvent; ACaretQuery: TTyImeCaretQuery);
begin
  inherited Create;
  FWidget := AWidget;
  FOnCommit := AOnCommit;
  FCaretQuery := ACaretQuery;
  FIM := gtk_im_multicontext_new;
  if ToplevelWin <> nil then
    gtk_im_context_set_client_window(FIM, ToplevelWin);
  g_signal_connect(FIM, 'commit', TGCallback(@TyGtkImeCommitCB), Self);
  FSnooperID := gtk_key_snooper_install(@TyGtkImeSnoop, Self);
end;

destructor TTyGtkImeHook.Destroy;
begin
  if FSnooperID <> 0 then
    gtk_key_snooper_remove(FSnooperID);
  if FIM <> nil then
  begin
    if FFocused then
      gtk_im_context_focus_out(FIM);
    g_object_unref(FIM);
  end;
  inherited Destroy;
end;

function TTyGtkImeHook.ToplevelWin: PGdkWindow;
var top: PGtkWidget;
begin
  // fcitx/ibus anchor the cursor location to the TOPLEVEL (form) window, not the control's window,
  // so that is what we set as the IM client window and translate the caret into.
  Result := nil;
  if FWidget = nil then Exit;
  top := gtk_widget_get_toplevel(FWidget);
  if top <> nil then
    Result := GetControlWindow(top);
end;

function TTyGtkImeHook.FilterKey(event: PGdkEventKey): Boolean;
begin
  Result := False;
  if (not FFocused) or (FIM = nil) then Exit;
  // GTK is a PUSH model (unlike Qt's pull/inputMethodQuery): re-push the caret location on every key
  // so the candidate window tracks the caret across commits, not just at focus-in.
  UpdateCursorLocation;
  // gtk_im_context_filter_keypress returns gboolean (Boolean32 in this binding) — assign directly,
  // do NOT compare to 0 (Boolean32 vs integer won't compile).
  Result := gtk_im_context_filter_keypress(FIM, event);
end;

procedure TTyGtkImeHook.DoCommit(const S: string);
begin
  if Assigned(FOnCommit) and (S <> '') then
    FOnCommit(S);
end;

procedure TTyGtkImeHook.UpdateCursorLocation;
var
  r: TRect;
  area: TGdkRectangle;
  top: PGtkWidget;
  ax, ay: gint;
  ok: Boolean;
begin
  if (FIM = nil) or (not Assigned(FCaretQuery)) or (FWidget = nil) then Exit;
  r := FCaretQuery();   // caret rect in the control's CLIENT coords
  top := gtk_widget_get_toplevel(FWidget);
  if top = nil then Exit;
  // Map the caret point from the control's coords into the TOPLEVEL widget's coords — this adds the
  // control's offset within the form even when GetControlWindow gives the SAME (shared) window for
  // both (ctrlOrigin==topOrigin, so a window-origin diff was 0). set_client_window is the toplevel.
  ax := 0; ay := 0;
  ok := gtk_widget_translate_coordinates(FWidget, top, r.Left, r.Top, @ax, @ay);
  if not ok then Exit;
  area.x := ax;
  area.y := ay;
  area.width := r.Right - r.Left;
  area.height := r.Bottom - r.Top;
  gtk_im_context_set_cursor_location(FIM, @area);
end;

procedure TTyGtkImeHook.SetFocused(AFocused: Boolean);
begin
  if (FFocused = AFocused) or (FIM = nil) then Exit;
  FFocused := AFocused;
  if AFocused then
  begin
    // (re)bind the client window now that the widget is realized, then focus + place the candidate.
    if ToplevelWin <> nil then
      gtk_im_context_set_client_window(FIM, ToplevelWin);
    gtk_im_context_focus_in(FIM);
    UpdateCursorLocation;
  end
  else
    gtk_im_context_focus_out(FIM);
end;

function TyGtkInstallIme(AControl: TWinControl; AOnCommit: TTyImeCommitEvent;
  ACaretQuery: TTyImeCaretQuery): TObject;
var
  W: PGtkWidget;
begin
  Result := nil;
  if (AControl = nil) or (not AControl.HandleAllocated) or (not Assigned(AOnCommit)) then Exit;
  W := {%H-}PGtkWidget(AControl.Handle);
  if W = nil then Exit;
  Result := TTyGtkImeHook.Create(W, AOnCommit, ACaretQuery);
end;

procedure TyGtkImeSetFocus(AHandle: TObject; AFocused: Boolean);
begin
  if AHandle is TTyGtkImeHook then
    TTyGtkImeHook(AHandle).SetFocused(AFocused);
end;

function TyGtkIsWayland: Boolean;
begin
  Result := False;   // GTK2 has no Wayland backend: an LCLGTK2 build is always X11.
end;

function TyGtkTakeImeCommit(const ATruncated: string): string;
begin
  Result := '';   // GTK2 delivers full commits through TyGtkInstallIme's own context.
end;

procedure TyGtk3MakePopup(APopup: TCustomForm; AAnchor: TControl);
begin
  // GTK2 is X11-only (Wayland via XWayland, which honours absolute placement) -- nothing to do.
end;

procedure TyGtk3MakePopupRect(APopup, AParent: TCustomForm; const AAnchorInParent: TRect;
  AMode: TTyPopupAnchorMode);
begin
  // GTK2 is X11-only -- nothing to do.
end;

procedure TyGtk3ReleasePopupGrab(APopup: TCustomForm);
begin
  // GTK2 is X11-only -- no Wayland grab to drop.
end;

procedure TyGtk3GrabPopup(APopup: TCustomForm; AOnDismiss: TNotifyEvent; AGroupId: Pointer; ASeatGrab: Boolean; AExcludeCtl: TWinControl);
begin
  // GTK2 is X11-only -- no Wayland grabbing popup.
end;

{$ELSE}
{$IFDEF LCLGTK3}

{ ------------------------------------------------------------------------------------
  GTK3. Deliberately NOT a copy of the GTK2 block: only the two facilities that are both
  needed and portable are here, and the GTK2 code above is untouched so the widgetset that
  works today cannot regress.

  The library's dependency on GTK3 comes in three tiers, and only one of them is a risk:
    1. the LCL's own cross-platform API (SetWindowRgn and friends) -- backend-independent;
    2. GTK3's native C entry points (gtk_window_begin_move_drag, ...) -- GTK3 is a
       maintenance series, so this surface is effectively frozen;
    3. LCL-GTK3's INTERNAL classes -- not public API, and the tier that actually moves.
  Tier 3 is reached in exactly ONE place below (Gtk3NativeWidget), so an upstream change to
  the backend's internals is a one-function repair rather than a sweep.
  ------------------------------------------------------------------------------------ }

uses
  LazGtk3, LazGdk3, LazGLib2, LazGObject2, lazcairo1, gtk3int, gtk3procs, gtk3widgets;   // Types comes from the interface uses; lazcairo1: opaque-region

{ The native GtkWidget behind an LCL handle. This is the whole of tier 3: under GTK2 a
  control's Handle IS the PGtkWidget and the library casts it directly, but under GTK3 the
  Handle is a TGtk3Widget INSTANCE that owns the widget -- so the GTK2 cast would be reading
  an object header as a widget. Anything needing a native widget goes through here. }
function Gtk3NativeWidget(AControl: TWinControl): PGtkWidget;
begin
  Result := nil;
  if (AControl = nil) or (not AControl.HandleAllocated) then Exit;
  Result := TGtk3Widget(AControl.Handle).Widget;
end;

function TyGtkStartSystemMove(AForm: TCustomForm): Boolean;
var
  W, Top: PGtkWidget;
  P: TPoint;
begin
  { Same rule as GTK2: hand the drag to the window manager instead of writing Left/Top per
    mouse-move, which the WM clamps to the bounding box of the whole screen. }
  Result := False;
  W := Gtk3NativeWidget(AForm);
  if W = nil then Exit;
  Top := gtk_widget_get_toplevel(W);
  if (Top = nil) or (not Gtk3IsGtkWindow(PGObject(Top))) then Exit;
  { NOTE: a GTK_WINDOW_POPUP passes Gtk3IsGtkWindow too, and a popup has no move request to
    make -- which is why dialogs cannot be dragged. Guarding on the window type was tried and
    REVERTED: it stopped the MAIN window dragging as well, so on this setup begin_move_drag
    evidently does work for whatever type the main window is. Diagnose what actually differs
    between the two windows before gating this again. }
  P := Mouse.CursorPos;   // LCL screen coords == root-window coords
  gtk_window_begin_move_drag(PGtkWindow(Top), 1, P.X, P.Y, gtk_get_current_event_time());
  Result := True;
end;

procedure TyGtk3SetWindowOpaque(AForm: TCustomForm);
var
  W, Top: PGtkWidget;
  gdkWin: PGdkWindow;
  rect: Tcairo_rectangle_int_t;
  region: Pcairo_region_t;
begin
  if (not TyGtkIsWayland) or (AForm = nil) or (not AForm.HandleAllocated) then Exit;
  W := Gtk3NativeWidget(AForm);
  if W = nil then Exit;
  Top := gtk_widget_get_toplevel(W);
  if Top = nil then Exit;
  gdkWin := gtk_widget_get_window(Top);
  if gdkWin = nil then Exit;
  { Whole window opaque so the compositor ignores per-pixel alpha (an oversized rect covers any
    size / HiDPI scale; the compositor clips it to the window). }
  rect.x := 0; rect.y := 0; rect.width := 1 shl 15; rect.height := 1 shl 15;
  region := cairo_region_create_rectangle(@rect);
  gdk_window_set_opaque_region(gdkWin, region);
  cairo_region_destroy(region);
end;

function TyGtkInstallIme(AControl: TWinControl; AOnCommit: TTyImeCommitEvent;
  ACaretQuery: TTyImeCaretQuery): TObject;
begin
  { NOT ported from the GTK2 block, for two reasons, both checked rather than assumed:
    the GTK2 hook is driven by gtk_key_snooper_install, which GTK3 deprecated and the
    Lazarus GTK3 bindings do not export at all; and LCL-GTK3 carries its own IM plumbing
    (TGtk3WidgetSet.IMCommitStr / IMInFilter / IMTarget in gtk3procs), so the GTK2 premise
    -- that stock LCL delivers no composed text -- may simply not hold here. Wiring an
    own-context IME before establishing that it is needed would be inventing a problem.
    Left as its own task; CJK input on GTK3 needs a real machine to assess. }
  Result := nil;
end;

procedure TyGtkImeSetFocus(AHandle: TObject; AFocused: Boolean);
begin
  // No own IME context on GTK3 yet -- see TyGtkInstallIme.
end;

function TyGtkIsWayland: Boolean;
begin
  { The backend already knows, and it is the same answer its own window-creation code
    branches on -- so asking it keeps our popups and its windows on one story. }
  Result := (GTK3WidgetSet <> nil) and GTK3WidgetSet.IsWayland;
end;

function TyGtkTakeImeCommit(const ATruncated: string): string;
var
  pending: string;
begin
  Result := '';
  if GTK3WidgetSet = nil then Exit;
  { Copy out first: the backend passes this same field BY REFERENCE into DeliverIMCommit, so
    blanking the property while a caller still holds a reference to it would cut the string
    out from under them. }
  pending := GTK3WidgetSet.IMCommitStr;
  if pending = '' then Exit;
  { Staleness guard, both halves needed. Longer: equal length means nothing was truncated and
    the control already has the whole thing. Prefix: a left-over value from an earlier key
    (the backend skips its clear while Ctrl is held without Alt) would not begin with what
    THIS keystroke delivered. }
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
  { The load-bearing call. gtk_window_set_transient_for sets only the GTK/WM transient hint and
    does NOT reach the GdkWindow, so without this the popup is a "temporary window without parent"
    and gdk_window_move_to_rect (which anchors to the transient-for GdkWindow) has nothing on
    Wayland to position against. Confirmed on a real GTK3/Wayland session. }
  gdk_window_set_transient_for(gdkWin, parentGdkWin);
  { The anchor rect is already in AParent's client coords -- Wayland refuses screen coords, so the
    caller walks the control tree (ClientToParent / a parent-row rect) to get here. Gravity pairs:
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
  if not TyGtkIsWayland then Exit;
  disp := gdk_display_get_default;
  if disp = nil then Exit;
  { A borderless popup maps as a GTK_WINDOW_POPUP that takes an app-level GTK grab (gtk_grab_add).
    While it is held, an outside click is redirected to the popup rather than the window under the
    pointer, so the main form never gets it and the popup never deactivates -> it can't be dismissed
    by clicking away, and a stale grab left after an idle-time Hide swallows the next click. Drop it,
    but ONLY when the current grab belongs to THIS popup so a legitimate grab elsewhere is untouched. }
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
  fire the stored dismiss handler. It is idempotent on the LCL side, so a self-hide is harmless. }
procedure TyGtk3PopupUnmapCb(widget: PGtkWidget; data: gpointer); cdecl;
begin
  if (data <> nil) and Assigned(PTyNotify(data)^) then
    PTyNotify(data)^(nil);
end;

procedure TyGtk3PopupDismissFree(data: gpointer; closure: PGClosure); cdecl;
begin
  if data <> nil then Dispose(PTyNotify(data));
end;

{ button-press-event trampoline. While the popup holds the grab, every click is reported here.
  Walk up the widget tree from the ACTUAL clicked widget: if we reach the popup toplevel the click
  was INSIDE (keep it open, let the list handle it); otherwise it landed outside -> dismiss. This is
  widget-hierarchy based (not coordinates), so it is reliable on Wayland -- and it is exactly how
  LCL's own gtkWSPopupMenuButtonPress dismisses a GtkMenu. Never returns True (an inside click must
  still reach the row). }
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
  { Walk up from the clicked widget: reaching the popup means INSIDE (keep); reaching the excluded
    bar means the bar handles it (keep, don't dismiss). }
  w := ew;
  while w <> nil do
  begin
    if w = widget then Exit;
    if (excl <> nil) and (w = excl) then Exit;
    w := gtk_widget_get_parent(w);
  end;
  { Same cascade group? A menu tags every level's top-level with the root id, so a click on a
    sibling submenu is still "inside" and must not dismiss. }
  top := gtk_widget_get_toplevel(ew);
  grpSelf := g_object_get_data(PGObject(widget), PChar('ty_popup_group'));
  if (grpSelf <> nil) and (top <> nil) then
  begin
    grpClick := g_object_get_data(PGObject(top), PChar('ty_popup_group'));
    if grpClick = grpSelf then Exit;
  end;
  writeln(StdErr, '[TyGtk3GrabPopup] outside button-press -> dismiss');
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
  st: TGdkGrabStatus;
  d, d2: PTyNotify;
begin
  if (not TyGtkIsWayland) or (APopup = nil) or (not APopup.HandleAllocated) then Exit;
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
      begin
        st := gdk_seat_grab(seat, gdkWin, GDK_SEAT_CAPABILITY_ALL, gboolean(True), nil, nil, nil, nil);
        writeln(StdErr, '[TyGtk3GrabPopup] gdk_seat_grab status=', Ord(st), ' (0=success)');
      end;
    end;
  end;
  { Wire the compositor dismiss (unmap) to AOnDismiss, once per widget. destroy_data frees the
    heap TMethod when the widget is destroyed. }
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
    writeln(StdErr, '[TyGtk3GrabPopup] wired unmap + button-press -> dismiss');
  end;
end;

{$ELSE}

function TyGtkStartSystemMove(AForm: TCustomForm): Boolean;
begin
  Result := False;
end;

procedure TyGtk3SetWindowOpaque(AForm: TCustomForm);
begin
  // not a GTK build: nothing to do.
end;

function TyGtkInstallIme(AControl: TWinControl; AOnCommit: TTyImeCommitEvent;
  ACaretQuery: TTyImeCaretQuery): TObject;
begin
  Result := nil;   // non-GTK2: no own-context IME needed.
end;

procedure TyGtkImeSetFocus(AHandle: TObject; AFocused: Boolean);
begin
  // non-GTK2: nothing to do.
end;

function TyGtkIsWayland: Boolean;
begin
  Result := False;   // not a GTK build: Wayland is not reachable from here.
end;

function TyGtkTakeImeCommit(const ATruncated: string): string;
begin
  Result := '';   // not a GTK3 build: nothing truncated a commit here.
end;

procedure TyGtk3MakePopup(APopup: TCustomForm; AAnchor: TControl);
begin
  // not a GTK build: nothing to do.
end;

procedure TyGtk3MakePopupRect(APopup, AParent: TCustomForm; const AAnchorInParent: TRect;
  AMode: TTyPopupAnchorMode);
begin
  // not a GTK build: nothing to do.
end;

procedure TyGtk3ReleasePopupGrab(APopup: TCustomForm);
begin
  // not a GTK build: no Wayland grab to drop.
end;

procedure TyGtk3GrabPopup(APopup: TCustomForm; AOnDismiss: TNotifyEvent; AGroupId: Pointer; ASeatGrab: Boolean; AExcludeCtl: TWinControl);
begin
  // not a GTK build: no Wayland grabbing popup.
end;

{$ENDIF}
{$ENDIF}

end.
