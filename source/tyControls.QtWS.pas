unit tyControls.QtWS;
{$mode objfpc}{$H+}

{ Qt-only window helpers for the Linux widgetset fixes. EVERY function is a NO-OP on non-Qt
  widgetsets (Win32 / GTK2 / Cocoa / GTK3), so those already-working paths are completely untouched
  — only an LCLQT5/LCLQT6 build links the real bodies. Rationale (confirmed against the on-disk
  C:\lazarus LCL-Qt source):
   - A borderless TForm popup is shown as an ordinary frameless window: the X11 WM then CENTERS it
     over its parent and refuses the mouse grab ("This plugin supports grabbing the mouse only for
     popup windows"). Re-typing the window as Qt::Popup makes it app-positioned + grab-capable.
   - A borderless window can't be dragged by setting Left/Top — the WM ignores programmatic move()
     during a button grab. QWindow.startSystemMove() hands the drag to the WM (Qt6 only; the Qt5
     pas binding doesn't export it). }

interface
uses Forms;

{ True iff this is a Qt build (so a caller can branch on it without its own IFDEFs). }
function TyIsQt: Boolean;

{ Re-type AForm's native window as a Qt POPUP (Qt::Popup | FramelessWindowHint). Call once the
  handle exists (after Show). No-op off Qt / when no handle. }
procedure TyQtMakePopup(AForm: TCustomForm);

{ Begin a WM-driven interactive move of AForm's window (call from a mouse-DOWN handler while the
  button is held). Returns True if the system move started — then the caller must NOT do its own
  per-move repositioning. Qt6 only; returns False elsewhere so the caller keeps its fallback. }
function TyQtStartSystemMove(AForm: TCustomForm): Boolean;

implementation

{$IF defined(LCLQT6) or defined(LCLQT5)}
uses
  {$IFDEF LCLQT6} qt6, {$ELSE} qt5, {$ENDIF}
  qtwidgets;

function TyIsQt: Boolean;
begin
  Result := True;
end;

procedure TyQtMakePopup(AForm: TCustomForm);
var w: TQtMainWindow;
begin
  if (AForm = nil) or (not AForm.HandleAllocated) then Exit;
  w := TQtMainWindow(AForm.Handle);
  if (w.windowFlags and QtWindowType_Mask) = QtPopup then Exit;   // already a popup: don't re-flag (avoids re-hide churn)
  w.setWindowFlags(QtPopup or QtFramelessWindowHint);
  // setWindowFlags HIDES the window in Qt — must re-show. As a Qt::Popup it is now app-positioned
  // and grabs/releases the mouse properly (the prior 'grab only for popup windows' warning + the
  // leaked grab came from it NOT being a popup). The caller re-asserts SetBounds right after.
  w.setVisible(True);
end;

function TyQtStartSystemMove(AForm: TCustomForm): Boolean;
{$IFDEF LCLQT6}
var win: QWindowH;
{$ENDIF}
begin
  Result := False;
  {$IFDEF LCLQT6}
  if (AForm = nil) or (not AForm.HandleAllocated) then Exit;
  win := QWidget_windowHandle(TQtMainWindow(AForm.Handle).Widget);
  if win <> nil then
    Result := QWindow_startSystemMove(win);
  {$ENDIF}
  // Qt5: QWindow_startSystemMove is not in the qt5 pas binding -> no-op (caller keeps its fallback).
end;

{$ELSE}

function TyIsQt: Boolean;
begin
  Result := False;
end;

procedure TyQtMakePopup(AForm: TCustomForm);
begin
  // non-Qt widgetset: nothing to do.
end;

function TyQtStartSystemMove(AForm: TCustomForm): Boolean;
begin
  Result := False;
end;

{$ENDIF}

end.
