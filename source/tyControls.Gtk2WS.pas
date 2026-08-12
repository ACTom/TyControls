unit tyControls.Gtk2WS;
{$mode objfpc}{$H+}

{ GTK2-only widgetset helpers. The whole unit is gated on {$IFDEF LCLGTK2}: on every other build it
  is an EMPTY unit (no code, no cross-platform stubs) -- tyControls.PlatformWS references these
  functions only from inside its own {$IFDEF LCLGTK2}, so nothing off GTK2 ever names them.

  1. WM-driven window move (TyGtk2StartSystemMove): a borderless TForm dragged by writing Left/Top is
     repositioned with gtk_window_move(), which the WM clamps to the whole-X-screen bounding box --
     on a multi-monitor layout that is not bottom-aligned, the lower monitor's bottom is a hard
     floor. gtk_window_begin_move_drag() hands the move to the WM.

  2. Input method (TyGtk2InstallIme): stock LCL ships NO working GTK2 IME (its commit/preedit
     delivery hides behind an undefined WITH_GTK2_IM define), so composed CJK never reaches a control.
     We attach our OWN GtkIMContext: a key snooper feeds key events to it BEFORE LCL's widgets see
     them, and the context's 'commit' signal hands the FULL committed UTF-8 to the control (also
     dodging the TUTF8Char/String[7] truncation). Focus is driven from the control's DoEnter/DoExit. }

interface

{$IFDEF LCLGTK2}
uses Classes, Types, Forms, Controls, tyControls.Types;   // Classes: TNotifyEvent; Types: TRect; tyControls.Types: TTyImeCommitEvent / TTyImeCaretQuery

{ Begin a WM-driven interactive move of AForm's window (call from a mouse-DOWN handler while the
  button is held). Returns True if the system move started -- then the caller must NOT do its own
  per-move repositioning. }
function TyGtk2StartSystemMove(AForm: TCustomForm): Boolean;

{ Attach our own GtkIMContext to AControl so it receives FULL composed CJK commits via AOnCommit.
  ACaretQuery (may be nil) returns the caret rect (client device px) placing the candidate window.
  Returns an opaque handle to free with the control's normal teardown, or nil on failure. }
function TyGtk2InstallIme(AControl: TWinControl; AOnCommit: TTyImeCommitEvent;
  ACaretQuery: TTyImeCaretQuery): TObject;

{ Tell a TyGtk2InstallIme handle the control gained/lost focus (drive from DoEnter/DoExit). The IM
  only composes while focused. Safe on nil / non-hook handles. }
procedure TyGtk2ImeSetFocus(AHandle: TObject; AFocused: Boolean);
{$ENDIF}

implementation

{$IFDEF LCLGTK2}
uses gtk2, gdk2, glib2, Gtk2Proc;   // Gtk2Proc: GetControlWindow (the control's client GdkWindow)

function TyGtk2StartSystemMove(AForm: TCustomForm): Boolean;
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
  // gtk_im_context_filter_keypress returns gboolean (Boolean32 in this binding) -- assign directly,
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
  // Map the caret point from the control's coords into the TOPLEVEL widget's coords -- this adds the
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

function TyGtk2InstallIme(AControl: TWinControl; AOnCommit: TTyImeCommitEvent;
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

procedure TyGtk2ImeSetFocus(AHandle: TObject; AFocused: Boolean);
begin
  if AHandle is TTyGtkImeHook then
    TTyGtkImeHook(AHandle).SetFocused(AFocused);
end;
{$ENDIF}

end.
