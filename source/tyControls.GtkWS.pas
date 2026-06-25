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
uses Forms, Controls, tyControls.QtWS;   // QtWS: shared TTyImeCommitEvent / TTyImeCaretQuery types

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

implementation

{$IFDEF LCLGTK2}
uses Types, gtk2, gdk2, glib2;

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
    TTyGtkImeHook(data).DoCommit(StrPas(PChar(str)));
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
  if (FWidget <> nil) and (FWidget^.window <> nil) then
    gtk_im_context_set_client_window(FIM, FWidget^.window);
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
begin
  if (FIM = nil) or (not Assigned(FCaretQuery)) then Exit;
  r := FCaretQuery();   // caret rect in the control's client device px == widget-window coords
  area.x := r.Left;
  area.y := r.Top;
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
    if (FWidget <> nil) and (FWidget^.window <> nil) then
      gtk_im_context_set_client_window(FIM, FWidget^.window);
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

{$ENDIF}

end.
