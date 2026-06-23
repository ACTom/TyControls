unit tyControls.GtkWS;
{$mode objfpc}{$H+}

{ GTK2-only window helper for the Linux widgetset fixes. EVERY function is a NO-OP on non-GTK2
  widgetsets (Win32 / Qt5 / Qt6 / Cocoa / GTK3), so those already-working paths are completely
  untouched — only an LCLGTK2 build links the real body. Rationale:
   - A borderless TForm dragged by writing Left/Top is repositioned with gtk_window_move(), which
     the WM clamps to the bounding box of the whole X screen. On a multi-monitor layout where the
     monitors are NOT bottom-aligned (e.g. one low-left, one high-right) the lower monitor's bottom
     becomes a hard floor, so a window on the upper monitor can't be dragged past mid-screen.
   - gtk_window_begin_move_drag() hands the interactive move to the window manager (via
     _NET_WM_MOVERESIZE), which knows the real monitor layout and lets the window cross monitors
     freely — the GTK2 analogue of Qt6's QWindow.startSystemMove(). }

interface
uses Forms;

{ Begin a WM-driven interactive move of AForm's window (call from a mouse-DOWN handler while the
  button is held). Returns True if the system move started — then the caller must NOT do its own
  per-move repositioning. GTK2 only; returns False elsewhere so the caller keeps its fallback. }
function TyGtkStartSystemMove(AForm: TCustomForm): Boolean;

implementation

{$IFDEF LCLGTK2}
uses Types, Controls, gtk2;

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

{$ELSE}

function TyGtkStartSystemMove(AForm: TCustomForm): Boolean;
begin
  Result := False;
end;

{$ENDIF}

end.
