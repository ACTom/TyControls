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
     pas binding doesn't export it).
   - Rounding a popup's corners: the cross-platform SetWindowRgn masks ONLY the top-level QWidget,
     but with QTSCROLLABLEFORMS (the Qt6 default) the painted surface is the form's scroll-area
     VIEWPORT plus the alClient windowed content control's own native widget — a Qt mask does not
     reach child QWidgets, so those keep square opaque corners. TyQtMaskWindowDeep re-applies the
     SAME region to every native surface; TyQtClearWindowMaskDeep removes them (SetWindowRgn(.,0) is
     a no-op on Qt, so a radius-0 theme must clear explicitly). }

interface
uses Forms, Controls, LCLType;

type
  { Called with the FULL UTF-8 commit string from a Qt input-method commit (no 7-byte truncation). }
  TTyImeCommitEvent = procedure(const ACommitUtf8: string) of object;

{ True iff this is a Qt build (so a caller can branch on it without its own IFDEFs). }
function TyIsQt: Boolean;

{ True iff running under the Qt WAYLAND platform plugin. Wayland has NO client-side window shaping
  (no XShape), so SetWindowRgn/setMask is silently ignored there — a popup must instead be drawn with
  SQUARE corners to match its un-shaped window (rounded corners on Wayland need a translucent surface,
  which LCL-Qt does not plumb). Always False off Qt / on X11 (xcb). Cached after the first query. }
function TyQtIsWayland: Boolean;

{ Re-type AForm's native window as a Qt POPUP (Qt::Popup | FramelessWindowHint). Call BEFORE the
  caller's Show (it HandleNeeds an invisible window, so Show then maps it app-positioned with no
  top-left flash). No-op off Qt / when no handle. }
procedure TyQtMakePopup(AForm: TCustomForm);

{ Begin a WM-driven interactive move of AForm's window (call from a mouse-DOWN handler while the
  button is held). Returns True if the system move started — then the caller must NOT do its own
  per-move repositioning. Qt6 only; returns False elsewhere so the caller keeps its fallback. }
function TyQtStartSystemMove(AForm: TCustomForm): Boolean;

{ Apply the rounded region ARgn (an LCL HRGN whose Qt backing is a live QRegion) to ALL the native
  QWidget surfaces of AForm's popup so the square corners are actually clipped on Qt6/X11 with
  QTSCROLLABLEFORMS: the form top-level + its container/viewport, AND the alClient content control's
  own widget + container/viewport. Call this WHILE ARgn is still a live HRGN (just before handing it
  to SetWindowRgn, which on Qt only masks the top-level and does not consume the HRGN). ContentCtl
  may be nil. No-op off Qt / when no handle. }
procedure TyQtMaskWindowDeep(AForm: TCustomForm; AContentCtl: TWinControl; ARgn: HRGN);

{ Clear the masks TyQtMaskWindowDeep set on all of AForm's native surfaces. Needed on Qt because
  SetWindowRgn(handle, 0, True) is a no-op there (it early-exits on a 0 region), so a reused popup
  switching to a 0-radius theme would otherwise keep a stale rounded mask. No-op off Qt. }
procedure TyQtClearWindowMaskDeep(AForm: TCustomForm; AContentCtl: TWinControl);

{ Install a Qt input-method commit interceptor on AControl's native widget. A custom-drawn TWinControl
  on Qt6 only receives an IME commit through LCL's UTF8KeyPress, whose TUTF8Char (String[7]) truncates
  any commit over ~2 CJK chars. This installs our own Qt event filter that reads the FULL
  QInputMethodEvent.commitString and hands it to AOnCommit, then EATS the event so LCL's truncated
  insert never runs. Returns an opaque handle to pass to TyQtUninstallIme (nil off Qt / on failure). }
function TyQtInstallImeCommit(AControl: TWinControl; AOnCommit: TTyImeCommitEvent): TObject;

{ Tear down a TyQtInstallImeCommit interceptor (frees the Qt event hook). Safe on nil / off Qt. }
procedure TyQtUninstallIme(var AHandle: TObject);

implementation

{$IF defined(LCLQT6) or defined(LCLQT5)}
uses
  SysUtils, LazUTF8,
  {$IFDEF LCLQT6} qt6, {$ELSE} qt5, {$ENDIF}
  qtwidgets, qtobjects;

type
  { Owns a Qt event filter on a widget that turns a full QInputMethodEvent commit into AOnCommit. }
  TTyQtImeHook = class
  private
    FHook: QObject_hookH;
    FOnCommit: TTyImeCommitEvent;
    function EventFilter(Sender: QObjectH; Event: QEventH): Boolean; cdecl;
  public
    constructor Create(AWidget: QWidgetH; AOnCommit: TTyImeCommitEvent);
    destructor Destroy; override;
  end;

constructor TTyQtImeHook.Create(AWidget: QWidgetH; AOnCommit: TTyImeCommitEvent);
begin
  inherited Create;
  FOnCommit := AOnCommit;
  // Installed AFTER LCL's own event filter (the handle already exists) -> Qt calls ours FIRST, so we
  // can consume the IME commit before LCL's SlotInputMethod squeezes it through TUTF8Char (String[7]).
  FHook := QObject_hook_create(AWidget);
  QObject_hook_hook_events(FHook, @EventFilter);
end;

destructor TTyQtImeHook.Destroy;
begin
  if FHook <> nil then
    QObject_hook_destroy(FHook);
  inherited Destroy;
end;

function TTyQtImeHook.EventFilter(Sender: QObjectH; Event: QEventH): Boolean; cdecl;
var
  ws: WideString;
  s: string;
begin
  Result := False;
  if QEvent_type(Event) <> QEventInputMethod then Exit;
  QInputMethodEvent_commitString(QInputMethodEventH(Event), @ws);
  if ws = '' then Exit;   // preedit-only (still composing): let Qt/LCL handle it, don't eat
  s := UTF16ToUTF8(ws);
  if (s <> '') and Assigned(FOnCommit) then
  begin
    FOnCommit(s);
    Result := True;       // EAT: stop LCL's SlotInputMethod from inserting the 7-byte-truncated copy
  end;
end;

function TyIsQt: Boolean;
begin
  Result := True;
end;

var
  GIsWayland: Integer = -1;   // -1 unknown, 0 no, 1 yes (platform is fixed for the process)

function TyQtIsWayland: Boolean;
var s: WideString;
begin
  if GIsWayland >= 0 then Exit(GIsWayland = 1);
  QGuiApplication_platformName(@s);   // 'wayland' / 'xcb' / '' (before the app is up)
  if s = 'wayland' then begin GIsWayland := 1; Exit(True); end;
  if s <> '' then GIsWayland := 0;    // cache only a DEFINITIVE answer; '' -> re-query next time
  Result := False;
end;

procedure TyQtMakePopup(AForm: TCustomForm);
var w: TQtMainWindow;
begin
  if AForm = nil then Exit;
  AForm.HandleNeeded;   // ensure the native window exists (still invisible) so we can re-type it
  if not AForm.HandleAllocated then Exit;
  w := TQtMainWindow(AForm.Handle);
  if (w.windowFlags and QtWindowType_Mask) = QtPopup then Exit;   // already a popup: leave it (avoids re-hide churn)
  // MUST be called BEFORE the caller's Show: the window is still hidden, so setWindowFlags' implicit
  // hide is a no-op and the following Show maps it directly as an app-positioned Qt::Popup — no
  // top-left flash, and it grabs/releases the mouse properly (fixes the 'grab only for popup
  // windows' warning + the leaked grab from it NOT being a popup).
  w.setWindowFlags(QtPopup or QtFramelessWindowHint);
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

{ Mask AW's outer widget and (when different) its container/viewport. GetContainerWidget is public on
  TQtWidget and resolves correctly in BOTH build configs: under QTSCROLLABLEFORMS it returns the
  scroll-area viewport (where LCL reparents children / where a TQtCustomControl paints); otherwise it
  returns FCentralWidget or the widget itself. So we avoid the {$IFDEF QTSCROLLABLEFORMS}-only
  ScrollArea field entirely. }
procedure MaskWidgetDeep(AW: TQtWidget; R: QRegionH);
var cont: QWidgetH;
begin
  if AW = nil then Exit;
  if AW.Widget <> nil then
    QWidget_setMask(AW.Widget, R);
  cont := AW.GetContainerWidget;
  if (cont <> nil) and (cont <> AW.Widget) then
    QWidget_setMask(cont, R);
end;

procedure ClearWidgetDeep(AW: TQtWidget);
var cont: QWidgetH;
begin
  if AW = nil then Exit;
  if AW.Widget <> nil then
    QWidget_clearMask(AW.Widget);
  cont := AW.GetContainerWidget;
  if (cont <> nil) and (cont <> AW.Widget) then
    QWidget_clearMask(cont);
end;

procedure TyQtMaskWindowDeep(AForm: TCustomForm; AContentCtl: TWinControl; ARgn: HRGN);
var R: QRegionH;
begin
  if (AForm = nil) or (not AForm.HandleAllocated) or (ARgn = 0) then Exit;
  R := TQtRegion(ARgn).FHandle;   // live QRegionH backing the LCL HRGN (Qt copies it on setMask)
  if R = nil then Exit;
  MaskWidgetDeep(TQtWidget(AForm.Handle), R);   // form top-level + its scroll-area viewport
  if (AContentCtl <> nil) and AContentCtl.HandleAllocated then
    MaskWidgetDeep(TQtWidget(AContentCtl.Handle), R);   // alClient control's own widget + viewport
end;

procedure TyQtClearWindowMaskDeep(AForm: TCustomForm; AContentCtl: TWinControl);
begin
  if (AForm = nil) or (not AForm.HandleAllocated) then Exit;
  ClearWidgetDeep(TQtWidget(AForm.Handle));
  if (AContentCtl <> nil) and AContentCtl.HandleAllocated then
    ClearWidgetDeep(TQtWidget(AContentCtl.Handle));
end;

function TyQtInstallImeCommit(AControl: TWinControl; AOnCommit: TTyImeCommitEvent): TObject;
var w: QWidgetH;
begin
  Result := nil;
  if (AControl = nil) or (not AControl.HandleAllocated) or (not Assigned(AOnCommit)) then Exit;
  w := TQtWidget(AControl.Handle).Widget;   // the widget that carries WA_InputMethodEnabled + the IME event
  if w = nil then Exit;
  Result := TTyQtImeHook.Create(w, AOnCommit);
end;

procedure TyQtUninstallIme(var AHandle: TObject);
begin
  FreeAndNil(AHandle);
end;

{$ELSE}

function TyIsQt: Boolean;
begin
  Result := False;
end;

function TyQtIsWayland: Boolean;
begin
  Result := False;   // non-Qt widgetset: never Wayland (Win32/GTK2/Cocoa).
end;

procedure TyQtMakePopup(AForm: TCustomForm);
begin
  // non-Qt widgetset: nothing to do.
end;

function TyQtStartSystemMove(AForm: TCustomForm): Boolean;
begin
  Result := False;
end;

procedure TyQtMaskWindowDeep(AForm: TCustomForm; AContentCtl: TWinControl; ARgn: HRGN);
begin
  // non-Qt widgetset: the cross-platform SetWindowRgn already clips the whole window; nothing to do.
end;

procedure TyQtClearWindowMaskDeep(AForm: TCustomForm; AContentCtl: TWinControl);
begin
  // non-Qt widgetset: nothing to do.
end;

function TyQtInstallImeCommit(AControl: TWinControl; AOnCommit: TTyImeCommitEvent): TObject;
begin
  Result := nil;   // non-Qt: IME flows through the normal LCL path (Win32 IME already works).
end;

procedure TyQtUninstallIme(var AHandle: TObject);
begin
  AHandle := nil;   // nothing was installed.
end;

{$ENDIF}

end.
