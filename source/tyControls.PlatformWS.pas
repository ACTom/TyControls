unit tyControls.PlatformWS;
{$mode objfpc}{$H+}

{ Widgetset-NEUTRAL platform facade.

  A control that has to do something platform-specific asks THIS unit, never a widgetset helper
  directly. Every function here dispatches, with conditional compilation, to the one widgetset
  helper that implements it (tyControls.Win32WS / .QtWS / .Gtk2WS / .Gtk3WS); on every other
  build the branch folds away and the call is inert. So all the {$IFDEF LCL...} lives in exactly
  ONE place -- here -- and control code stays free of widgetset names, and each widgetset unit
  carries only its own real code (no empty cross-platform stubs).

  Historical note: the library used to ask "is this Qt-on-Wayland?" through TyQtIsWayland, whose
  non-Qt answer was a hard-coded False. That was true while Linux meant Qt or GTK2; it broke when
  GTK3 -- a first-class Wayland backend -- became the LCL's default Linux widgetset. The question
  belongs here, phrased about the machine, not a widgetset. }

interface

uses
  Classes, Controls, Forms, Types, LCLType, tyControls.Types;

{ ---- platform facts ---------------------------------------------------------------------- }

{ True when the session is a Wayland one. Wayland gives a client no way to place its own
  top-levels and has no shape extension, so popups can't be hand-positioned or cut to a rounded
  silhouette and must degrade. Answering False when the truth is True is the dangerous direction. }
function TyIsWayland: Boolean;

{ True for an LCL-GTK3 build. }
function TyIsGtk3: Boolean;

{ True only on a GTK3 build running under Wayland -- the exact gate for the GTK3/Wayland-specific
  inline behaviour a couple of popup controls still need (focus the list, re-map on a hover switch)
  that is NOT a widgetset call and so can't hide behind one. }
function TyIsGtk3Wayland: Boolean;

{ True on widgetsets whose open popup takes a pointer grab (Qt, GTK): a menu bar then never receives
  MouseMove while a dropdown is open, so it must poll the global cursor to switch tops on hover.
  False on Win32, where ordinary MouseMove still reaches the bar. }
function TyPopupGrabsPointer: Boolean;

{ True on widgetsets that resolve the LCL system colours (clWindow / clWindowText / clHighlight)
  from the LIVE desktop palette, which makes reading them a legitimate appearance probe.

  Qt5/Qt6 map them onto QPalette and drop their cache on the application palette change, so they
  track a Plasma colour-scheme switch. GTK2 does read the real GTK style -- but only once, when
  the widgetset is constructed; the 'style-set' callbacks that would refresh it are compiled only
  under EventTrace, so the values freeze at startup. GTK3 leaves several entries hardcoded and
  says so itself ("SOME SYSCOLORS ARE STILL HARDCODED"). Win32 and Cocoa have authoritative
  probes of their own and never need this. So: Qt only. }
function TySysColorsTrackDesktop: Boolean;

var
  { EXPERIMENT, default OFF. On a GTK3 build, opt a borderless popup into the native GTK_WINDOW_POPUP
    path via csNoFocus (see the long note kept with TyPreparePopupWindow's history). Inert off GTK3. }
  TyGtk3PopupWindows: Boolean = False;

{ Call from a borderless popup window's constructor, before its handle exists. Applies
  TyGtk3PopupWindows. No-op off GTK3, and a no-op when the switch is off. }
procedure TyPreparePopupWindow(AForm: TCustomForm);

{ ---- window move / non-client resize ----------------------------------------------------- }

{ Hand a borderless window's title-bar drag to the window manager (Win32 Aero-snap, Qt
  startSystemMove, GTK begin_move_drag) instead of writing Left/Top per mouse-move. Returns True
  when the system move started -- then the caller must NOT do its own repositioning.

  AIncludeBlocking=False excludes Win32's caption move (WM_NCLBUTTONDOWN), which is a BLOCKING modal
  loop that would swallow a double-click's second press: on the mouse-DOWN a caller wants only the
  NON-blocking WM handoffs (Qt/GTK) and defers Win32's to the drag-threshold path. }
function TyStartSystemMove(AForm: TCustomForm; AIncludeBlocking: Boolean = True): Boolean;

{ Reposition a form during a MANUAL title-bar drag -- the non-WM path taken off Win32 (Cocoa/Qt5,
  and a modal GTK2 dialog whose WM refuses to interactively move it). Repositions immediately on
  every widgetset EXCEPT GTK2, where the moves are rate-limited: a modal dialog moves via a per-move
  gtk_window_move and an animating compositor eases each one, so one commit per mouse-move would crawl.
  Call TyDragMoveFlush at drag end to land the final (possibly deferred) position; it is a no-op off
  GTK2. Keeps the widgetset conditional here in the facade instead of in the chrome engine. }
procedure TyDragMoveForm(AForm: TCustomForm; ALeft, ATop: Integer);
procedure TyDragMoveFlush(AForm: TCustomForm);

{ Win32 non-client resize band for a borderless self-drawn form (Aero snap / edge resize). No-op
  off Win32. }
procedure TyNcApplyResize(AForm: TCustomForm; AResizable: Boolean;
  ABorderZone, ACaptionHeight: Integer; AMaximized, AAllowMaximize: Boolean;
  ANoFrame: Boolean = False);
procedure TyNcBeginTopResize(AForm: TCustomForm);
procedure TyNcSetEdgePassthrough(AControl: TWinControl; AZone: Integer; AEnabled: Boolean);

{ ---- popups (Qt::Popup / Wayland xdg_popup) ---------------------------------------------- }

{ Re-type AForm as a native popup so it maps app-positioned and grabs like a menu (Qt only). }
procedure TyPreparePopupNative(AForm: TCustomForm);
{ GTK3/Wayland: anchor APopup under AAnchor (drop below). No-op elsewhere. }
procedure TyAnchorPopupBelow(APopup: TCustomForm; AAnchor: TControl);
{ GTK3/Wayland: anchor APopup to AParent's window at ARect (in AParent client coords), AMode picks
  drop-below vs fly-out-to-a-side. No-op elsewhere. }
procedure TyAnchorPopupRect(APopup, AParent: TCustomForm; const ARect: TRect;
  AMode: TTyPopupAnchorMode);
{ GTK3/Wayland: seat-grab APopup and dismiss (AOnDismiss) on an outside click; AGroupId keeps a
  menu cascade's sibling levels "inside"; ASeatGrab / AExcludeCtl -- see the GTK3 helper. }
procedure TyGrabPopup(APopup: TCustomForm; AOnDismiss: TNotifyEvent; AGroupId: Pointer = nil;
  ASeatGrab: Boolean = True; AExcludeCtl: TWinControl = nil);
{ GTK3/Wayland: drop the grab a popup left behind (on hide). No-op elsewhere. }
procedure TyReleasePopupGrab(APopup: TCustomForm);
{ Qt: mask a frameless popup (and its scroll-area viewport + content) to a rounded region; and the
  clear. No-op elsewhere (Win32/GTK use SetWindowRgn on the top-level directly). }
procedure TyMaskPopupWindow(AForm: TCustomForm; AContentCtl: TWinControl; ARgn: HRGN);
procedure TyClearPopupWindowMask(AForm: TCustomForm; AContentCtl: TWinControl);
{ Win32: toggle WS_EX_NOACTIVATE so a passive popup (autocomplete dropdown) never steals focus. No-op
  elsewhere. Call before Show. }
procedure TySetPopupNoActivate(AForm: TCustomForm; ANoActivate: Boolean);

{ ---- input method (IME) ------------------------------------------------------------------ }

{ Attach an own-context IME so a control receives FULL composed CJK commits (Qt intercepts the
  truncating TUTF8Char path; GTK2 attaches a GtkIMContext because stock LCL-GTK2 delivers none).
  Returns an opaque handle, or nil when the widgetset needs no such hook. }
function TyImeInstall(AControl: TWinControl; AOnCommit: TTyImeCommitEvent;
  ACaretQuery: TTyImeCaretQuery): TObject;
{ Tear an install down (Qt); nils the handle. }
procedure TyImeUninstall(var AHandle: TObject);
{ GTK2: tell the own IM context the control gained/lost focus. No-op elsewhere. }
procedure TyImeSetFocus(AHandle: TObject; AFocused: Boolean);
{ Qt: reposition the candidate window at the caret. No-op elsewhere. }
procedure TyImeUpdateCaret;
{ GTK3: the FULL commit the backend delivered when the control got a truncated copy through
  UTF8KeyPress; '' otherwise (so the call site needs no IFDEF). }
function TyImeTakeCommit(const ATruncated: string): string;
{ Win32: follow the caret with the IMM32 candidate window (HWND-based IME). No-op elsewhere -- Qt/GTK
  own-context IMEs installed via TyImeInstall place their own candidate window. }
procedure TySetImeCaretPos(AControl: TWinControl; AClientX, AClientY: Integer);

implementation

uses
  SysUtils   // anchor: keeps the list well-formed when no widgetset branch below is live
  {$IFDEF LCLWin32}, tyControls.Win32WS {$ENDIF}
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}, tyControls.QtWS {$IFEND}
  {$IFDEF LCLGTK2}, tyControls.Gtk2WS {$ENDIF}
  {$IFDEF LCLGTK3}, tyControls.Gtk3WS {$ENDIF}
  ;

function TyIsWayland: Boolean;
begin
  { Exactly one widgetset branch is ever live; every other build folds to a plain False. Qt answers
    for a Qt5/Qt6 session, GTK3 for a GTK3 one; GTK2 is X11-only (XWayland), so False is right there. }
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  Result := TyQtIsWayland;
  {$ELSE}{$IFDEF LCLGTK3}
  Result := TyGtk3IsWayland;
  {$ELSE}
  Result := False;
  {$ENDIF}{$IFEND}
end;

function TyIsGtk3: Boolean;
begin
  {$IFDEF LCLGTK3} Result := True; {$ELSE} Result := False; {$ENDIF}
end;

function TyIsGtk3Wayland: Boolean;
begin
  {$IFDEF LCLGTK3} Result := TyGtk3IsWayland; {$ELSE} Result := False; {$ENDIF}
end;

function TyPopupGrabsPointer: Boolean;
begin
  {$IFDEF LCLWin32} Result := False; {$ELSE} Result := True; {$ENDIF}
end;

function TySysColorsTrackDesktop: Boolean;
begin
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)} Result := True; {$ELSE} Result := False; {$IFEND}
end;

procedure TyPreparePopupWindow(AForm: TCustomForm);
begin
  if (AForm = nil) or (not TyIsGtk3) or (not TyGtk3PopupWindows) then Exit;
  AForm.ControlStyle := AForm.ControlStyle + [csNoFocus];
end;

function TyStartSystemMove(AForm: TCustomForm; AIncludeBlocking: Boolean): Boolean;
begin
  {$IFDEF LCLWin32}
  if AIncludeBlocking then Result := TyWin32StartSystemMove(AForm) else Result := False;
  {$ELSE}{$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  Result := TyQtStartSystemMove(AForm);
  {$ELSE}{$IFDEF LCLGTK2}
  Result := TyGtk2StartSystemMove(AForm);
  {$ELSE}{$IFDEF LCLGTK3}
  Result := TyGtk3StartSystemMove(AForm);
  {$ELSE}
  Result := False;
  {$ENDIF}{$ENDIF}{$IFEND}{$ENDIF}
end;

{$IFDEF LCLGTK2}
const
  Gtk2DragThrottleMs = 120;   // min gap between committed moves so an animating compositor doesn't crawl
var
  GDragTick: QWord = 0;       // GetTickCount64 of the last committed move; 0 = fresh drag (commit at once)
  GDragPending: Boolean = False;
  GDragLeft, GDragTop: Integer;   // latest requested target, held for the flush
{$ENDIF}

procedure TyDragMoveForm(AForm: TCustomForm; ALeft, ATop: Integer);
{$IFDEF LCLGTK2}
var tick: QWord;
{$ENDIF}
begin
  if AForm = nil then Exit;
  {$IFDEF LCLGTK2}
  GDragLeft := ALeft; GDragTop := ATop;
  tick := TThread.GetTickCount64;
  if (GDragTick = 0) or (tick - GDragTick >= Gtk2DragThrottleMs) then
  begin
    AForm.Left := ALeft; AForm.Top := ATop;
    GDragTick := tick; GDragPending := False;
  end
  else
    GDragPending := True;   // defer: TyDragMoveFlush lands it on MouseUp
  {$ELSE}
  AForm.Left := ALeft; AForm.Top := ATop;
  {$ENDIF}
end;

procedure TyDragMoveFlush(AForm: TCustomForm);
begin
  {$IFDEF LCLGTK2}
  if (AForm <> nil) and GDragPending then
  begin
    AForm.Left := GDragLeft; AForm.Top := GDragTop;
    GDragPending := False;
  end;
  GDragTick := 0;   // arm a fresh throttle window for the next drag
  {$ENDIF}
end;

procedure TyNcApplyResize(AForm: TCustomForm; AResizable: Boolean;
  ABorderZone, ACaptionHeight: Integer; AMaximized, AAllowMaximize: Boolean; ANoFrame: Boolean);
begin
  {$IFDEF LCLWin32}
  TyWin32ApplyNcResize(AForm, AResizable, ABorderZone, ACaptionHeight, AMaximized, AAllowMaximize, ANoFrame);
  {$ENDIF}
end;

procedure TyNcBeginTopResize(AForm: TCustomForm);
begin
  {$IFDEF LCLWin32} TyWin32BeginTopResize(AForm); {$ENDIF}
end;

procedure TyNcSetEdgePassthrough(AControl: TWinControl; AZone: Integer; AEnabled: Boolean);
begin
  {$IFDEF LCLWin32} TyWin32SetEdgePassthrough(AControl, AZone, AEnabled); {$ENDIF}
end;

procedure TyPreparePopupNative(AForm: TCustomForm);
begin
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)} TyQtMakePopup(AForm); {$IFEND}
end;

procedure TyAnchorPopupBelow(APopup: TCustomForm; AAnchor: TControl);
begin
  {$IFDEF LCLGTK3} TyGtk3MakePopup(APopup, AAnchor); {$ENDIF}
end;

procedure TyAnchorPopupRect(APopup, AParent: TCustomForm; const ARect: TRect;
  AMode: TTyPopupAnchorMode);
begin
  {$IFDEF LCLGTK3} TyGtk3MakePopupRect(APopup, AParent, ARect, AMode); {$ENDIF}
end;

procedure TyGrabPopup(APopup: TCustomForm; AOnDismiss: TNotifyEvent; AGroupId: Pointer;
  ASeatGrab: Boolean; AExcludeCtl: TWinControl);
begin
  {$IFDEF LCLGTK3} TyGtk3GrabPopup(APopup, AOnDismiss, AGroupId, ASeatGrab, AExcludeCtl); {$ENDIF}
end;

procedure TyReleasePopupGrab(APopup: TCustomForm);
begin
  {$IFDEF LCLGTK3} TyGtk3ReleasePopupGrab(APopup); {$ENDIF}
end;

procedure TyMaskPopupWindow(AForm: TCustomForm; AContentCtl: TWinControl; ARgn: HRGN);
begin
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)} TyQtMaskWindowDeep(AForm, AContentCtl, ARgn); {$IFEND}
end;

procedure TyClearPopupWindowMask(AForm: TCustomForm; AContentCtl: TWinControl);
begin
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)} TyQtClearWindowMaskDeep(AForm, AContentCtl); {$IFEND}
end;

procedure TySetPopupNoActivate(AForm: TCustomForm; ANoActivate: Boolean);
begin
  {$IFDEF LCLWin32} TyWin32SetNoActivate(AForm, ANoActivate); {$ENDIF}
end;

function TyImeInstall(AControl: TWinControl; AOnCommit: TTyImeCommitEvent;
  ACaretQuery: TTyImeCaretQuery): TObject;
begin
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  Result := TyQtInstallIme(AControl, AOnCommit, ACaretQuery);
  {$ELSE}{$IFDEF LCLGTK2}
  Result := TyGtk2InstallIme(AControl, AOnCommit, ACaretQuery);
  {$ELSE}
  Result := nil;
  {$ENDIF}{$IFEND}
end;

procedure TyImeUninstall(var AHandle: TObject);
begin
  { Freeing the handle IS the teardown on every widgetset: each hook object's destructor does its
    own widgetset-specific cleanup (Qt removes its event filter; GTK2 removes the key snooper +
    unrefs the GtkIMContext). So there is nothing to dispatch -- and it MUST run on GTK2 too, not
    just Qt, or the snooper dangles into a freed control. nil-safe (Win32/Cocoa never install one). }
  FreeAndNil(AHandle);
end;

procedure TyImeSetFocus(AHandle: TObject; AFocused: Boolean);
begin
  {$IFDEF LCLGTK2} TyGtk2ImeSetFocus(AHandle, AFocused); {$ENDIF}
end;

procedure TyImeUpdateCaret;
begin
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)} TyQtImeUpdateCaret; {$IFEND}
end;

function TyImeTakeCommit(const ATruncated: string): string;
begin
  {$IFDEF LCLGTK3} Result := TyGtk3TakeImeCommit(ATruncated); {$ELSE} Result := ''; {$ENDIF}
end;

procedure TySetImeCaretPos(AControl: TWinControl; AClientX, AClientY: Integer);
begin
  {$IFDEF LCLWin32} TyWin32SetImeCaretPos(AControl, AClientX, AClientY); {$ENDIF}
end;

end.
