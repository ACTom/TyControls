unit tyControls.PlatformWS;
{$mode objfpc}{$H+}

{ Widgetset-NEUTRAL platform facts.

  A control that has to know something about the machine it is running on should ask a
  question about the machine, not about a widgetset. The distinction is not pedantry: the
  library asked "is this Qt-on-Wayland?" through TyQtIsWayland, whose non-Qt answer is a
  hard-coded False documented as "never Wayland (Win32/GTK2/Cocoa)". That was true while
  Linux meant Qt or GTK2. It stopped being true when GTK3 -- which has a first-class Wayland
  backend -- became the LCL's default Linux widgetset, and eight popup controls were left
  believing they were on X11 when they were not.

  So the question lives here, and each widgetset helper answers for itself. Every one of
  those answers is compile-time inert off its own widgetset, so this composes to exactly one
  live branch per build with no run-time cost. }

interface

uses
  Controls, Forms;

{ True when the session is a Wayland one.

  What it governs: Wayland gives a client no way to place its own top-level windows and has
  no shape extension, so a popup cannot be cut to a rounded or arrowed silhouette and cannot
  be positioned by hand. Controls that do either must degrade -- square corners, and let the
  compositor place the surface -- rather than draw something the compositor will ignore.

  Answering False when the truth is True is the dangerous direction: the control then paints
  a silhouette that never takes effect and positions a window that never moves. }
function TyIsWayland: Boolean;

{ True for an LCL-GTK3 build. }
function TyIsGtk3: Boolean;

var
  { EXPERIMENT, default OFF -- a switch, not a fix, and here is exactly why.

    LCL-GTK3 chooses a popup window's native type like this (gtk3widgets.pas, TGtk3Window's
    CreateWidget):

        if (AForm.BorderStyle = bsNone) and
           (Gtk3WidgetSet.IsWayland or (csNoFocus in AForm.ControlStyle)) then
          Result := TGtkWindow.new(GTK_WINDOW_POPUP)
        else
          Result := TGtkWindow.new(GTK_WINDOW_TOPLEVEL);

    So on X11 a borderless form WITHOUT csNoFocus becomes a managed TOPLEVEL -- placed and
    decorated by the window manager rather than by us. Every popup this library puts up is a
    borderless form and none of them set csNoFocus, which is a plausible common cause for the
    GTK3 reports of dropdowns that never appear and menus that appear in the wrong place.

    Plausible, not proven: it is read off the backend's source, and it cannot be tested from
    a Windows box. It also is not free -- taking the POPUP path via csNoFocus means the window
    does NOT get set_accept_focus, so a menu's arrow keys or a dropdown's type-ahead may stop
    working. Shipping that trade silently, on a guess, would be worse than the bug.

    Hence a switch. Set it True early (before any popup is shown) on a GTK3 machine and
    compare; the answer decides whether the real fix is ours, or an upstream request that X11
    should get POPUP with accept_focus the way Wayland already does. It is inert off GTK3. }
  TyGtk3PopupWindows: Boolean = False;

{ Call from a borderless popup window's constructor, before its handle exists. Applies
  TyGtk3PopupWindows. No-op off GTK3, and a no-op when the switch is off. }
procedure TyPreparePopupWindow(AForm: TCustomForm);

implementation

uses
  tyControls.QtWS, tyControls.GtkWS;

function TyIsWayland: Boolean;
begin
  { Each helper is a constant False off its own widgetset, so exactly one of these can ever
    be live in a given build. }
  Result := TyQtIsWayland or TyGtkIsWayland;
end;

function TyIsGtk3: Boolean;
begin
  {$IFDEF LCLGTK3}
  Result := True;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TyPreparePopupWindow(AForm: TCustomForm);
begin
  if (AForm = nil) or (not TyIsGtk3) or (not TyGtk3PopupWindows) then Exit;
  AForm.ControlStyle := AForm.ControlStyle + [csNoFocus];
end;

end.
