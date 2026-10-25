unit tyControls.PlatformWS;
{$mode objfpc}{$H+}

{ Widgetset-NEUTRAL platform facade.

  A control that has to do something platform-specific asks THIS unit, never a widgetset helper
  directly. Every function here dispatches, with conditional compilation, to the one widgetset
  helper that implements it (tyControls.Win32WS / .QtWS / .Gtk2WS / .Gtk3WS / .CocoaWS); on every other
  build the branch folds away and the call is inert. So all the {$IFDEF LCL...} lives in exactly
  ONE place -- here -- and control code stays free of widgetset names, and each widgetset unit
  carries only its own real code (no empty cross-platform stubs).

  Historical note: the library used to ask "is this Qt-on-Wayland?" through TyQtIsWayland, whose
  non-Qt answer was a hard-coded False. That was true while Linux meant Qt or GTK2; it broke when
  GTK3 -- a first-class Wayland backend -- became the LCL's default Linux widgetset. The question
  belongs here, phrased about the machine, not a widgetset. }

interface

uses
  Classes, Controls, Forms, Graphics, BGRABitmapTypes, Types, LCLType, tyControls.Types;

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
  NON-blocking WM handoffs (Qt/GTK) and defers Win32's to the drag-threshold path. Cocoa's
  performWindowDrag is modal too, so it is excluded with Win32's when AIncludeBlocking is False. }
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
{ macOS: give AForm, a popup about to be shown, a window level above the application's other
  windows on screen. fsStayOnTop puts it at the floating level, and a modal dialog sits above
  that, so a drop-down, menu or popover opened in one showed behind it (#104). The popup keeps
  the floating level unless one of those windows is at or above it, then goes one above the
  highest. No-op elsewhere. Call right before Show. }
procedure TyRaisePopupWindow(AForm: TCustomForm);

{ ---- the system's window frame (macOS frame spec 2026-10-14, #80) --------------------------- }

{ What the platform's own frame does for a TTyForm -- see TTyFrameTrait. Win32: a modal move and
  native edge resize. Cocoa: all four. Everything else: none. }
function TyFrameTraits: TTyFrameTraits;

{ Give AForm's window the frame the system draws, where it draws one for a TTyForm: on macOS a
  titled window whose title bar is transparent and whose content covers the whole window, so it
  gets the system's corners, shadow, edge resize, tiling and zoom while TTyTitleBar keeps drawing
  the bar. Safe to call repeatedly -- LCL-Cocoa rewrites the style mask whenever BorderIcons
  changes -- and before the handle exists (then a no-op). No-op off Cocoa. }
procedure TyApplyWindowFrame(AForm: TCustomForm; const AFrame: TTyWindowFrame);

{ The system's caption buttons on AForm's window; all zero when it has none. }
function TySystemButtonGroup(AForm: TCustomForm): TTySystemButtonGroup;

{ Put the system's caption buttons into ARect -- AForm client px, which on macOS is the whole
  window -- centred vertically. The system puts them back where its own title bar keeps them on
  every resize, so the title bar calls this from every layout pass. No-op off Cocoa. }
procedure TyPlaceSystemButtons(AForm: TCustomForm; const ARect: TRect);

{ What a title-bar double-click does here: macOS has a user setting for it
  (AppleActionOnDoubleClick); everywhere else it maximizes. }
function TyTitleDoubleClickAction: TTyTitleDoubleClick;

{ The system's zoom (macOS). False / no-op elsewhere. }
function TyIsWindowZoomed(AForm: TCustomForm): Boolean;
procedure TySetWindowZoomed(AForm: TCustomForm; AZoomed: Boolean);

{ Minimize THIS window the platform's way (macOS: into the Dock). False when the platform has no
  such call, and the caller falls back to its own. }
function TyMinimizeWindow(AForm: TCustomForm): Boolean;

{ The window's shadow and its light/dark system appearance -- on macOS hasShadow and an aqua /
  darkAqua NSAppearance, so the frame the system draws (the hairline border, the traffic lights)
  matches the theme. No-op elsewhere. }
procedure TyApplyWindowAppearance(AForm: TCustomForm; AShadow, ADark: Boolean);

{ ---- the device scale (#83) -------------------------------------------------------------- }

{ How many device pixels one LCL pixel of AControl covers: 2 on a Retina Mac, 1 elsewhere. LCL
  says it through TControl.GetCanvasScaleFactor, and today only LCL-Cocoa answers anything but 1
  (the window's backingScaleFactor; a graphic control takes its parent's). A widgetset that
  scales a window without saying so -- Qt6, GTK3 at an integer scale -- gets its own query here,
  in its WS unit, and the painter and the controls never see it. nil = 1. }
function TyControlDeviceScale(AControl: TControl): Double;

{ ---- drawing a bitmap (#94) -------------------------------------------------------------- }

{ Draw ASrc (ABitmap's pixels) into ADst (ACanvas's units) opaque -- the alpha channel ignored,
  as BGRA's Draw(..., True) does -- with less copying than BGRA's DrawPart, which copies the part
  on every widgetset but GTK and, on Cocoa, twice more in its Draw. Cocoa: the part copied once
  into memory CG owns and drawn as a CGImage on the canvas's CGContext; a window's canvas and a
  top-down bitmap only. False when nothing was drawn -- every other widgetset, or a canvas or
  bitmap it does not take -- and the caller draws its own way. }
function TyDrawOpaquePart(ACanvas: TCanvas; ABitmap: TBGRACustomBitmap; const ASrc, ADst: TRect): Boolean;

type
  { A form's window level, when it has a window on screen (TTyTestPlatform.LevelOf). }
  TTyWindowLevelQuery = function(AForm: TCustomForm; out ALevel: PtrInt): Boolean;

  { TEST SEAM. While Active, the functions in the section above (and TyStartSystemMove and
    TyRaisePopupWindow) answer from here instead of the widgetset, and the ones that act record
    what they were asked. It sits on the platform boundary only: the title bar, the chrome engine
    and the form run their own code against it, which is how the macOS behaviour is tested on
    Windows. Library code must never read it. }
  TTyTestPlatform = record
    Active: Boolean;
    Traits: TTyFrameTraits;
    ButtonGroup: TTySystemButtonGroup;
    DoubleClick: TTyTitleDoubleClick;
    Zoomed: Boolean;            // TyIsWindowZoomed answers it; TySetWindowZoomed writes it
    SystemMoveStarts: Boolean;  // TyStartSystemMove starts a move (a modal one only past the threshold)
    FrameApplies: Integer;
    LastFrame: TTyWindowFrame;
    LastFrameForm: TCustomForm;
    Placements: Integer;
    LastPlacement: TRect;
    LastPlacementForm: TCustomForm;
    ZoomRequests: Integer;
    Minimizes: Integer;
    SystemMoves: Integer;
    AppearanceApplies: Integer;
    LastShadow, LastDark: Boolean;
    DeviceScale: Double;        // TyControlDeviceScale answers it when > 0
    { TyRaisePopupWindow starts from FloatingLevel, asks LevelOf (unset = no window on screen)
      and records the level it gives. }
    FloatingLevel: PtrInt;
    LevelOf: TTyWindowLevelQuery;
    LevelSets: Integer;
    LastLevel: PtrInt;
    LastLevelForm: TCustomForm;
  end;

var
  TyTestPlatform: TTyTestPlatform;

{ Back to the real platform, every recorder cleared. }
procedure TyResetTestPlatform;

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
  {$IFDEF LCLCocoa}, tyControls.CocoaWS {$ENDIF}
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
  if TyTestPlatform.Active then
  begin
    Result := TyTestPlatform.SystemMoveStarts
      and (AIncludeBlocking or not (ftrModalMove in TyTestPlatform.Traits));
    if Result then Inc(TyTestPlatform.SystemMoves);
    Exit;
  end;
  {$IFDEF LCLWin32}
  if AIncludeBlocking then Result := TyWin32StartSystemMove(AForm) else Result := False;
  {$ELSE}{$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  Result := TyQtStartSystemMove(AForm);
  {$ELSE}{$IFDEF LCLGTK2}
  Result := TyGtk2StartSystemMove(AForm);
  {$ELSE}{$IFDEF LCLGTK3}
  Result := TyGtk3StartSystemMove(AForm);
  {$ELSE}{$IFDEF LCLCocoa}
  // performWindowDrag is a modal loop like Win32's caption move: past the threshold only
  if AIncludeBlocking then Result := TyCocoaStartSystemMove(AForm) else Result := False;
  {$ELSE}
  Result := False;
  {$ENDIF}{$ENDIF}{$ENDIF}{$IFEND}{$ENDIF}
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

function WindowLevelOf(AForm: TCustomForm; out ALevel: PtrInt): Boolean;
begin
  ALevel := 0;
  if TyTestPlatform.Active then
    Exit(Assigned(TyTestPlatform.LevelOf) and TyTestPlatform.LevelOf(AForm, ALevel));
  {$IFDEF LCLCocoa}
  Result := TyCocoaWindowLevel(AForm, ALevel);
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TyRaisePopupWindow(AForm: TCustomForm);
var
  i: Integer;
  own, top, lvl: PtrInt;
begin
  if TyTestPlatform.Active then
    own := TyTestPlatform.FloatingLevel
  else
  {$IFDEF LCLCocoa}
    own := TyCocoaFloatingLevel;
  {$ELSE}
    Exit;
  {$ENDIF}
  { Every time, even when nothing is above: that also drops a level an earlier show raised. }
  top := own - 1;
  for i := 0 to Screen.CustomFormCount - 1 do
    if (Screen.CustomForms[i] <> AForm) and WindowLevelOf(Screen.CustomForms[i], lvl)
       and (lvl > top) then
      top := lvl;
  if top >= own then
    own := top + 1;
  if TyTestPlatform.Active then
  begin
    Inc(TyTestPlatform.LevelSets);
    TyTestPlatform.LastLevel := own;
    TyTestPlatform.LastLevelForm := AForm;
    Exit;
  end;
  {$IFDEF LCLCocoa}
  TyCocoaSetWindowLevel(AForm, own);
  {$ENDIF}
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

{ ---- the system's window frame --------------------------------------------------------------- }

procedure TyResetTestPlatform;
begin
  TyTestPlatform := Default(TTyTestPlatform);
end;

function TyControlDeviceScale(AControl: TControl): Double;
begin
  if TyTestPlatform.Active and (TyTestPlatform.DeviceScale > 0) then
    Exit(TyTestPlatform.DeviceScale);
  if AControl = nil then Exit(1);
  Result := AControl.GetCanvasScaleFactor;
end;

function TyDrawOpaquePart(ACanvas: TCanvas; ABitmap: TBGRACustomBitmap; const ASrc, ADst: TRect): Boolean;
begin
  {$IFDEF LCLCocoa}
  Result := TyCocoaDrawOpaquePart(ACanvas, ABitmap, ASrc, ADst);
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

function TyFrameTraits: TTyFrameTraits;
begin
  if TyTestPlatform.Active then Exit(TyTestPlatform.Traits);
  {$IFDEF LCLWin32}
  Result := [ftrModalMove, ftrNativeResize];
  {$ELSE}{$IFDEF LCLCocoa}
  Result := [ftrModalMove, ftrNativeResize, ftrNativeZoom, ftrSystemButtons];
  {$ELSE}
  Result := [];
  {$ENDIF}{$ENDIF}
end;

procedure TyApplyWindowFrame(AForm: TCustomForm; const AFrame: TTyWindowFrame);
begin
  if TyTestPlatform.Active then
  begin
    Inc(TyTestPlatform.FrameApplies);
    TyTestPlatform.LastFrame := AFrame;
    TyTestPlatform.LastFrameForm := AForm;
    Exit;
  end;
  {$IFDEF LCLCocoa}
  TyCocoaApplyWindowFrame(AForm, AFrame);
  {$ENDIF}
end;

function TySystemButtonGroup(AForm: TCustomForm): TTySystemButtonGroup;
begin
  if TyTestPlatform.Active then Exit(TyTestPlatform.ButtonGroup);
  {$IFDEF LCLCocoa}
  Result := TyCocoaSystemButtonGroup(AForm);
  {$ELSE}
  Result := Default(TTySystemButtonGroup);
  {$ENDIF}
end;

procedure TyPlaceSystemButtons(AForm: TCustomForm; const ARect: TRect);
begin
  if TyTestPlatform.Active then
  begin
    Inc(TyTestPlatform.Placements);
    TyTestPlatform.LastPlacement := ARect;
    TyTestPlatform.LastPlacementForm := AForm;
    Exit;
  end;
  {$IFDEF LCLCocoa}
  TyCocoaPlaceSystemButtons(AForm, ARect);
  {$ENDIF}
end;

function TyTitleDoubleClickAction: TTyTitleDoubleClick;
begin
  if TyTestPlatform.Active then Exit(TyTestPlatform.DoubleClick);
  {$IFDEF LCLCocoa}
  Result := TyCocoaTitleDoubleClick;
  {$ELSE}
  Result := tdcMaximize;
  {$ENDIF}
end;

function TyIsWindowZoomed(AForm: TCustomForm): Boolean;
begin
  if TyTestPlatform.Active then Exit(TyTestPlatform.Zoomed);
  {$IFDEF LCLCocoa}
  Result := TyCocoaIsZoomed(AForm);
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TySetWindowZoomed(AForm: TCustomForm; AZoomed: Boolean);
begin
  if TyTestPlatform.Active then
  begin
    Inc(TyTestPlatform.ZoomRequests);
    TyTestPlatform.Zoomed := AZoomed;
    Exit;
  end;
  {$IFDEF LCLCocoa}
  TyCocoaSetZoomed(AForm, AZoomed);
  {$ENDIF}
end;

function TyMinimizeWindow(AForm: TCustomForm): Boolean;
begin
  if TyTestPlatform.Active then
  begin
    Inc(TyTestPlatform.Minimizes);
    Exit(True);
  end;
  {$IFDEF LCLCocoa}
  Result := TyCocoaMinimize(AForm);
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TyApplyWindowAppearance(AForm: TCustomForm; AShadow, ADark: Boolean);
begin
  if TyTestPlatform.Active then
  begin
    Inc(TyTestPlatform.AppearanceApplies);
    TyTestPlatform.LastShadow := AShadow;
    TyTestPlatform.LastDark := ADark;
    Exit;
  end;
  {$IFDEF LCLCocoa}
  TyCocoaApplyAppearance(AForm, AShadow, ADark);
  {$ENDIF}
end;

end.
