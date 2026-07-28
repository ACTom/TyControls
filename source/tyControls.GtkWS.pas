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
uses Forms, Controls, tyControls.Types;   // tyControls.Types: shared TTyImeCommitEvent / TTyImeCaretQuery

{ Begin a WM-driven interactive move of AForm's window (call from a mouse-DOWN handler while the
  button is held). Returns True if the system move started — then the caller must NOT do its own
  per-move repositioning. GTK2 only; returns False elsewhere so the caller keeps its fallback. }
function TyGtkStartSystemMove(AForm: TCustomForm): Boolean;

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

implementation

{$IFDEF LCLGTK2}
uses Types, gtk2, gdk2, glib2, Gtk2Proc;   // Gtk2Proc: GetControlWindow (the control's client GdkWindow)

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
  Types, LazGtk3, LazGdk3, LazGLib2, LazGObject2, gtk3int, gtk3procs, gtk3widgets;

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
  { Gtk3IsGtkWindow only proves the GType is GtkWindow, which GTK_WINDOW_POPUP satisfies just
    as well as GTK_WINDOW_TOPLEVEL -- and a POPUP has no move request to make. On X11 it is
    override-redirect, so the WM never acts on _NET_WM_MOVERESIZE for a window it does not
    manage; on Wayland a popup with a transient parent is an xdg_popup, which has no move
    protocol at all. begin_move_drag is silently a no-op on either.

    Reporting True there is worse than doing nothing: the caller reads it as "the system took
    the drag" and stands down its own per-mouse-move fallback, so the window stops moving
    altogether. That is exactly why dialogs could not be dragged while the main window could
    -- LCL-GTK3 gives every borderless form a transient parent when one is active, and only
    the FIRST form (created when there is no active window yet) escapes it. }
  if gtk_window_get_window_type(PGtkWindow(Top)) <> GTK_WINDOW_TOPLEVEL then Exit;
  P := Mouse.CursorPos;   // LCL screen coords == root-window coords
  gtk_window_begin_move_drag(PGtkWindow(Top), 1, P.X, P.Y, gtk_get_current_event_time());
  Result := True;
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

{$ELSE}

function TyGtkStartSystemMove(AForm: TCustomForm): Boolean;
begin
  Result := False;
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

{$ENDIF}
{$ENDIF}

end.
