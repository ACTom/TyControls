unit tyControls.Win32WS;
{$mode objfpc}{$H+}

{ Windows-only native non-client edge-resize glue for the borderless TTyForm. EVERY routine
  is a NO-OP on non-Windows widgetsets, so GTK2 / Qt5 / Qt6 / Cocoa builds link empty bodies
  and are completely untouched — exactly the isolation pattern of tyControls.WindowEffects /
  QtWS / GtkWS. This unit exists (rather than living in Form.pas) because pulling the Windows
  unit into Form.pas's namespace shadows Types.Rect/Point and Classes.RegisterClass, which the
  rest of Form.pas relies on.

  Mechanism (see the B1 spike note in tyControls.Form): LCL-Win32 never lets a WndProc override
  see WM_NCCALCSIZE (absent from its dispatch) and discards a WndProc's WM_NCHITTEST result
  (it returns DefWindowProc's value), so we SUBCLASS the HWND via SetWindowLongPtr(GWLP_WNDPROC)
  after the handle exists and chain CallWindowProc for everything else. The subclass:
    - WM_NCCALCSIZE (wParam=TRUE): return 0 -> the client rect is left equal to the whole window
      rect (the native caption/border chrome is not carved out), while the WS_THICKFRAME sizing
      border stays a hit-testable non-client region the OS resizes natively.
    - WM_NCHITTEST: screen point -> window-relative -> TyResolveNcHit (the pure composer in
      Form.pas), which keeps DefWindowProc's answer for the real sizing frame and maps the rest
      itself -> HTLEFT..HTBOTTOMRIGHT / HTCAPTION / HTCLIENT, gated by Resizable + maximized.
    - WM_NCDESTROY: restore the original proc and drop the per-window state.
  WS_THICKFRAME (stripped from a bsNone form) is (re)asserted per Resizable, and a resizable
  top-level window trades LCL's WS_POPUP for WS_CAPTION so the shell treats it as an ordinary
  window and gives it Aero Snap + the native maximize/minimize animations (see ApplyThickFrame).

  LIVE resize / DWM-corner interaction / native maximize+snap are REAL-MACHINE checkpoints —
  they cannot be verified headlessly (no window manager). This unit's contract is only that it
  compiles and installs cleanly; the pure mapper it calls is unit-tested in test.form. }

interface

uses
  Forms, Controls;

{ Assert/clear WS_THICKFRAME on AForm's window per AResizable and refresh the frame
  (SetWindowPos SWP_FRAMECHANGED), then install (idempotent) or refresh the NC subclass so
  WM_NCCALCSIZE/WM_NCHITTEST are handled with the current Resizable / border-zone / caption
  height. ANoFrame accompanies the window-shadow:false opt-out (tyControls.WindowEffects sets
  DWMWA_NCRENDERING_POLICY=DISABLED): with DWM NC rendering off, the L/R/B sizing bands the
  top-only WM_NCCALCSIZE normally leaves as real frame get LEGACY-painted as a classic ring —
  so ANoFrame makes WM_NCCALCSIZE eat the WHOLE frame (client := window rect, like the fixed
  branch) and the bands cease to exist. Edge-resize survives: WM_NCHITTEST's own zone mapper
  answers HTLEFT..HTBOTTOMRIGHT from inside the window, and WS_THICKFRAME still makes
  DefWindowProc run the native resize loop on those codes. Safe to call repeatedly and when
  AForm has no handle (no-op). No-op off Windows. }
procedure TyWin32ApplyNcResize(AForm: TCustomForm; AResizable: Boolean;
  ABorderZone, ACaptionHeight: Integer; AMaximized, AAllowMaximize: Boolean;
  ANoFrame: Boolean = False);

{ The window-shadow:false companion for the CONTENT HOST, and the thing that makes the window
  mouse-resizable at all in that mode.

  ANoFrame makes WM_NCCALCSIZE hand the whole window rect to the client, which leaves the
  alClient TTyFormSurface covering every pixel of the window. Mouse messages are routed to the
  innermost child under the pointer, so the FORM is then never hit-tested and its zone mapper --
  the only thing that can report HTLEFT..HTBOTTOMRIGHT once the frame has been eaten -- never
  runs. Measured on Win10 19044: hovering the bottom-right corner produced 13 WM_NCHITTEST and
  13 WM_NCMOUSEMOVE(HTBOTTOMRIGHT) with the shadow on, and 0 of each with it off. That is the
  forum report "resizing the form via mouse only works once".

  The fix is not to give the band back to the OS: letting the normal top-only branch run in this
  mode paints the pale classic ring the full-frame-eat exists to avoid (scanned inward from the
  left edge: 1px white, then 5px of 180-grey, in both activation states). Instead the SURFACE
  reports HTTRANSPARENT inside the AZone band, which per MSDN makes the system keep hit-testing
  the windows underneath -- i.e. the form -- so the mapper runs and the pixels stay ours to
  paint. Nothing moves and nothing is inset; only the hit test changes.

  A control of the surface's own that sits flush in the band still takes the hit, because a child
  is above its parent in the search. That matches the shadow-on mode, where those pixels are OS
  non-client and no child can reach them either.

  Idempotent; the subclass is installed once per HWND and restored on WM_NCDESTROY. Call with
  AEnabled False (shadow on, fixed size, maximized) to leave the surface reporting normally.
  No-op off Windows and when AControl has no handle. }
procedure TyWin32SetEdgePassthrough(AControl: TWinControl; AZone: Integer; AEnabled: Boolean);

{ Begin a native top-edge resize of AForm. The flush title bar covers the top (there is no NC
  strip there), so the OS can't start a top resize itself; the title bar calls this from its top
  hot-zone via WM_NCLBUTTONDOWN/HTTOP. No-op off Windows / when AForm has no handle. }
procedure TyWin32BeginTopResize(AForm: TCustomForm);

{ Hand a title-bar drag to the OS as a native caption move (WM_NCLBUTTONDOWN/HTCAPTION) so Windows
  runs its modal move loop — which provides Aero Snap (drag to a screen edge) + the snap preview,
  and, on a window the OS itself has maximized, the restore-under-the-cursor-and-keep-dragging that
  every native title bar performs; none of it reachable from a manual Left/Top drag. Returns True
  when it took over the move (Win32 with a handle); the caller then skips its manual-drag fallback.
  Returns False off Windows / with no handle so the caller keeps its existing per-move
  repositioning. Mirrors the Qt/GTK system-move. }
function TyWin32StartSystemMove(AForm: TCustomForm): Boolean;

implementation

{$IFDEF LCLWin32}
uses
  Windows,
  SysUtils,          // Win32MajorVersion / Win32MinorVersion (RTL globals) for the Vista/Win7 check
  Types,             // listed AFTER Windows so Types.Rect/Point (functions) shadow Windows' TYPES
  tyControls.Form;   // TyResolveNcHit (pure hit-test composer) — implementation-section cycle, legal

type
  { Per-subclassed-window state. Keyed by HWND in a parallel array (a handful of TTyForms at
    most), so the static window proc can recover the form's current Resizable / border zone /
    caption height + the original proc to chain. }
  PNcState = ^TNcState;
  TNcState = record
    Wnd: HWND;
    OrigProc: WNDPROC;
    Resizable: Boolean;
    BorderZone: Integer;
    CaptionH: Integer;
    Maximized: Boolean;   // engine (work-area) maximize -> suppress the NC resize inset
    NoFrame: Boolean;     // window-shadow:false companion -> full-frame-eat (see TyWin32ApplyNcResize)
    WorkArea: TRect;      // last known monitor work area -> fallback pin for the maximized client
  end;

  { Per-subclassed-SURFACE state. Separate from TNcState on purpose: this rides a CHILD window,
    handles exactly one message, and must not be confused with the form's NC subclass if both
    ever land on the same handle. }
  PEdgeState = ^TEdgeState;
  TEdgeState = record
    Wnd: HWND;
    OrigProc: WNDPROC;
    Zone: Integer;
    Enabled: Boolean;
  end;

var
  GStates: array of PNcState;
  GEdges: array of PEdgeState;

function FindEdge(Wnd: HWND): PEdgeState;
var i: Integer;
begin
  for i := 0 to High(GEdges) do
    if GEdges[i]^.Wnd = Wnd then Exit(GEdges[i]);
  Result := nil;
end;

procedure DropEdge(Wnd: HWND);
var i, last: Integer;
begin
  for i := 0 to High(GEdges) do
    if GEdges[i]^.Wnd = Wnd then
    begin
      Dispose(GEdges[i]);
      last := High(GEdges);
      GEdges[i] := GEdges[last];            // swap-remove (order irrelevant)
      SetLength(GEdges, last);
      Exit;
    end;
end;

function FindState(Wnd: HWND): PNcState;
var i: Integer;
begin
  for i := 0 to High(GStates) do
    if GStates[i]^.Wnd = Wnd then Exit(GStates[i]);
  Result := nil;
end;

procedure DropState(Wnd: HWND);
var i, last: Integer;
begin
  for i := 0 to High(GStates) do
    if GStates[i]^.Wnd = Wnd then
    begin
      Dispose(GStates[i]);
      last := High(GStates);
      GStates[i] := GStates[last];          // swap-remove (order irrelevant)
      SetLength(GStates, last);
      Exit;
    end;
end;

var
  GAeroThickFrame: Integer = -1;   // -1 unknown / 0 no / 1 yes

// True on Vista/Win7 (major 6.0/6.1), which render the THICK frosted Aero-glass sizing frame. On those we
// keep the TOP framed too (symmetric with L/R/B) instead of a flush title bar. Win32MajorVersion/MinorVersion
// (from the Windows unit — no external DLL) are reliable HERE: Win7 reports 6.1 (below the un-manifested
// GetVersion cap, so no lie), while Win8+ / Win10 / Win11 report >= 6.2 (their real version or the manifest
// cap), so "6.x with x<=1" isolates exactly Vista/Win7. (We deliberately do NOT static-import ntdll.dll for
// RtlGetVersion — a top-level static ntdll import breaks the Win10/11 loader: "ole.DLL not found".)
function TyOsThickAeroFrame: Boolean;
begin
  if GAeroThickFrame < 0 then
  begin
    if (Win32MajorVersion = 6) and (Win32MinorVersion <= 1) then
      GAeroThickFrame := 1
    else
      GAeroThickFrame := 0;
  end;
  Result := GAeroThickFrame = 1;
end;

function NcWndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  st: PNcState;
  orig: WNDPROC;
  pt: TPoint;
  wr: Windows.RECT;
  ncp: PNCCalcSizeParams;
  maxed: Boolean;
  savedTop: LongInt;   // WM_NCCALCSIZE: the flush-title-bar top to restore after DefWindowProc insets
  wa: TRect;           // WM_NCCALCSIZE: work area to pin the client to while maximized
  mon: TMonitor;       // ..sourced from the monitor the window is on RIGHT NOW
begin
  st := FindState(Wnd);
  if st = nil then
    // Lost our state (shouldn't happen) -> behave as the default window proc.
    Exit(DefWindowProc(Wnd, Msg, WP, LP));
  orig := st^.OrigProc;
  case Msg of
    WM_NCCALCSIZE:
      if WP <> 0 then
      begin
        ncp := PNCCalcSizeParams(LP);
        if not st^.Resizable then
        begin
          // Fixed bsNone form: no sizing frame -> leave rgrc[0] = the whole window rect so the
          // themed client + flush title bar cover the window. Return 0 (client := window rect).
          Result := 0;
          Exit;
        end;
        maxed := st^.Maximized;          // engine (work-area) maximize
        if not maxed then maxed := IsZoomed(Wnd);   // native maximize / Aero-Snap
        if maxed then
        begin
          // Maximized: pin the client to the monitor WORK AREA (LCL-sourced) so it can never
          // overhang under the taskbar. Robust for BOTH maximize paths. A maximized window shows
          // no sizing band, so there is no edge strip to reason about here. (Empty work area ->
          // leave client = window: a safe fallback, since the engine already sized to the work area.)
          //
          // Take the work area of the monitor the window is on RIGHT NOW, not the one cached at the
          // last TyWin32ApplyNcResize: the window may have been dragged to another monitor since
          // (a plain move refreshes nothing), and a NATIVE maximize — which Aero Snap now performs —
          // sends this message BEFORE the WM_SIZE that would refresh the cache. Pinning to the wrong
          // monitor's work area would put the client somewhere else entirely.
          mon := Screen.MonitorFromWindow(Wnd);
          if mon <> nil then wa := mon.WorkareaRect else wa := st^.WorkArea;
          if (wa.Right > wa.Left) and (wa.Bottom > wa.Top) then
          begin
            ncp^.rgrc[0].Left   := wa.Left;
            ncp^.rgrc[0].Top    := wa.Top;
            ncp^.rgrc[0].Right  := wa.Right;
            ncp^.rgrc[0].Bottom := wa.Bottom;
          end;
          Result := 0;
          Exit;
        end;
        if st^.NoFrame then
        begin
          // window-shadow:false opt-out. NC rendering is DISABLED for this window (WindowEffects
          // sets DWMWA_NCRENDERING_POLICY=DISABLED to kill the standard frame shadow), and with
          // it disabled the L/R/B sizing bands are no longer rendered by DWM but LEGACY-painted —
          // a pale classic frame ring. Measured on Win10 19044 by letting the normal branch run
          // in this mode and scanning the pixels inward from the window's left edge: 1px white
          // then a 5px 180-grey band, in both activation states. So the band really cannot be
          // left to the OS, and client := whole window rect stays.
          //
          // That has a consequence this comment used to get WRONG: it claimed "the in-window
          // WM_NCHITTEST zone mapper below keeps edge-resize alive". It does not, on its own.
          // The client now covers the whole window, so the alClient TTyFormSurface child covers
          // every pixel too, and a mouse over the edge is routed to the CHILD -- this window is
          // never hit-tested at all (measured: hovering the bottom-right corner produced 13
          // WM_NCHITTEST + 13 WM_NCMOUSEMOVE(HTBOTTOMRIGHT) with the shadow on, and 0 of each
          // with it off). What keeps the mapper reachable is TTyForm insetting its CLIENT RECT
          // by the border zone in this mode, so the surface stops short of the band and the
          // band's pixels belong to this window. See TTyForm.AdjustClientRect.
          Result := 0;
          Exit;
        end;
        // Normal (non-maximized): the Windows Terminal / Chromium "top-only" custom-frame model.
        // DefWindowProc insets the client to the standard sizing frame on all four edges; restore ONLY
        // the top so the flush title bar covers it. The TTyFormSurface child then covers this inset
        // client edge-to-edge (no dead band). A ~1px OS window border remains (client sits ~1px inside
        // the visible bounds) — it is DWM-owned NC and NOT removable on Win10 without losing the shadow:
        // client=window ("full-frame-eat") drops the border but brings the transparent EDGE BAND back,
        // because the child surface is ALSO clipped to the parent's WS_THICKFRAME redirection surface
        // (~window-frame). So we accept the 1px, exactly as Chrome / VS Code / Windows Terminal do.
        savedTop := ncp^.rgrc[0].Top;
        CallWindowProc(orig, Wnd, Msg, WP, LP);    // DefWindowProc: standard 4-edge sizing-frame inset
        // Win8+ (thin 1px frame): restore the TOP so the custom title bar is flush at y=0. Vista/Win7
        // (thick frosted Aero frame): DON'T restore — let the OS frame the top too, so all four edges
        // carry the same Aero border (symmetric), instead of a bare flush top next to thick sides.
        if not TyOsThickAeroFrame then
          ncp^.rgrc[0].Top := savedTop;
        Result := 0;
        Exit;
      end;
    WM_NCHITTEST:
      begin
        pt.X := SmallInt(LOWORD(DWORD(LP)));
        pt.Y := SmallInt(HIWORD(DWORD(LP)));
        if GetWindowRect(Wnd, @wr) then
        begin
          Dec(pt.X, wr.Left);
          Dec(pt.Y, wr.Top);
          maxed := st^.Maximized;                     // engine (work-area) maximize
          if not maxed then maxed := IsZoomed(Wnd);   // native maximize / Aero Snap
          // Ask the OS FIRST: top-only NCCALCSIZE keeps left/right/bottom as the REAL sizing
          // frame, and only DefWindowProc knows where that frame sits — it includes the invisible
          // outer resize margin, which a mapper working from the window rect cannot see.
          // TyResolveNcHit keeps that answer for the sizing frame and maps everything else
          // itself: the flush title bar makes the top edge + caption band client (HTTOP for the
          // top resize strip, HTCAPTION for the drag band), and — now that ApplyThickFrame adds
          // WS_CAPTION for Aero Snap — it also DISCARDS the phantom caption / sysmenu / min /
          // max / close band DefWindowProc infers from that style for a caption we never draw.
          Result := TyResolveNcHit(CallWindowProc(orig, Wnd, Msg, WP, LP),
            Rect(0, 0, wr.Right - wr.Left, wr.Bottom - wr.Top),
            pt, st^.BorderZone, st^.CaptionH, st^.Resizable, maxed);
          Exit;
        end;
        // GetWindowRect failed (degenerate): fall through to the original proc.
      end;
    WM_NCACTIVATE:
      begin
        // Frameless custom-chrome window: when a popup (dialog / combobox dropdown / menu) steals
        // focus, the main window DEACTIVATES and Win10 repaints the non-client frame in its INACTIVE
        // color — a white 1px edge that only clears when the mouse hovers an edge (which triggers a
        // per-edge NC repaint). We render the whole window ourselves (WM_NCCALCSIZE removes the frame,
        // the shadow comes from DWM sheet-of-glass), so there is NO native frame that should change on
        // (de)activation. Suppress that repaint by chaining to the original proc with lParam = -1:
        // per MSDN, an lParam of -1 tells the default handler NOT to repaint the non-client area on
        // activation-state change, while still updating the internal active/inactive state correctly.
        // WP (TRUE/FALSE = becoming active/inactive) is left untouched so state bookkeeping stays sane.
        // We route through st^.OrigProc (the captured LCL proc), NOT a raw DefWindowProc, so the
        // subclass chain is preserved exactly like the fall-through below.
        Exit(CallWindowProc(orig, Wnd, Msg, WP, LPARAM(-1)));
      end;
    WM_NCDESTROY:
      begin
        // Restore the original proc BEFORE the window dies, then chain so LCL cleans up.
        SetWindowLongPtr(Wnd, GWLP_WNDPROC, LONG_PTR(orig));
        DropState(Wnd);
        Exit(CallWindowProc(orig, Wnd, Msg, WP, LP));
      end;
  end;
  Result := CallWindowProc(orig, Wnd, Msg, WP, LP);
end;

procedure ApplyThickFrame(Wnd: HWND; AResizable, AAllowMaximize, ANoFrame: Boolean);
var style: PtrInt;
begin
  style := GetWindowLongPtr(Wnd, GWL_STYLE);
  { Aero Snap, the native maximize, and the minimize/restore animations are all run by the OS's
    own move loop, and it only offers them to a window that LOOKS like an ordinary top-level
    window: WS_CAPTION present, WS_POPUP absent. LCL builds a bsNone form as a bare WS_POPUP with
    no caption — exactly the combination the shell refuses to snap, which is why dragging to the
    top edge merely RESIZED this window (the "snap up" fallback for a window it considers
    non-maximizable) instead of maximizing it, and why a maximized window could not be dragged
    back off. Trading WS_POPUP for WS_CAPTION is the standard custom-frame recipe (Chromium,
    Electron, framelesshelper all do it): nothing native is DRAWN, because WM_NCCALCSIZE above
    already collapses the non-client area to nothing at the top, but the window manager now runs
    its full snap / maximize / animation logic for us.

    Only for a resizable TOP-LEVEL window:
      - WS_CHILD (an embedded form) must keep its child styles — a caption there is meaningless.
      - a fixed or rolled-up window cannot snap or maximize anyway, and WS_CAPTION would add the
        OS minimum window height that the roll-up (window-shade) deliberately sheds with
        WS_THICKFRAME, so it goes back to being a plain popup.
      - Vista/Win7 (the thick frosted Aero frame) keep the NON-CLIENT top strip — see the
        WM_NCCALCSIZE branch above — so a WS_CAPTION there would give them a real, painted OS
        title bar sitting above ours. They stay as they were, snap included.
      - ANoFrame (window-shadow: false) is the case where "nothing native is DRAWN" stops being
        true. That mode sets DWMWA_NCRENDERING_POLICY = DISABLED, which hands the window back to
        LEGACY non-client rendering, and legacy rendering draws the caption of a WS_CAPTION window
        whenever its activation state changes — over our chrome, without ever sending the window a
        WM_NCPAINT (a message spy on the real window logs WM_NCACTIVATE, WM_ACTIVATE and two
        WM_NCCALCSIZE round trips on deactivation, and no paint message at all). Stripping
        WS_CAPTION is what actually stops it: verified by clearing the bit on the live window and
        watching the classic caption disappear. The cost is the shell's snap/maximise logic in
        THIS mode only, which is the right trade -- a caption Windows insists on painting is worse
        than a gesture, and an app that turns the shadow off has already opted out of OS chrome. }
  if (style and WS_CHILD) = 0 then
  begin
    if AResizable and (not TyOsThickAeroFrame) and (not ANoFrame) then
      style := (style and (not WS_POPUP)) or WS_CAPTION
    else
      style := (style and (not WS_CAPTION)) or WS_POPUP;
  end;
  if AResizable then
    style := style or WS_THICKFRAME
  else
    style := style and (not WS_THICKFRAME);
  if AAllowMaximize then
    style := style or WS_MAXIMIZEBOX
  else
    style := style and (not WS_MAXIMIZEBOX);
  SetWindowLongPtr(Wnd, GWL_STYLE, style);
  SetWindowPos(Wnd, 0, 0, 0, 0, 0,
    SWP_FRAMECHANGED or SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  InvalidateRect(Wnd, nil, True);
end;

procedure TyWin32ApplyNcResize(AForm: TCustomForm; AResizable: Boolean;
  ABorderZone, ACaptionHeight: Integer; AMaximized, AAllowMaximize: Boolean;
  ANoFrame: Boolean);
var
  Wnd: HWND;
  st: PNcState;
begin
  if (AForm = nil) or (not AForm.HandleAllocated) then Exit;
  Wnd := AForm.Handle;
  st := FindState(Wnd);
  if st = nil then
  begin
    // First install on this HWND: capture the prior (LCL) proc and route through ours.
    New(st);
    st^.Wnd := Wnd;
    st^.OrigProc := WNDPROC(GetWindowLongPtr(Wnd, GWLP_WNDPROC));
    SetLength(GStates, Length(GStates) + 1);
    GStates[High(GStates)] := st;
    SetWindowLongPtr(Wnd, GWLP_WNDPROC, LONG_PTR(@NcWndProc));
  end;
  // Refresh the live parameters the proc reads (Resizable / zone / caption height / edge-band colour).
  st^.Resizable := AResizable;
  st^.BorderZone := ABorderZone;
  st^.CaptionH := ACaptionHeight;
  st^.Maximized := AMaximized;
  st^.NoFrame := ANoFrame;
  if AForm.Monitor <> nil then
    st^.WorkArea := AForm.Monitor.WorkareaRect;   // LCL-sourced fallback for the maximized client pin
  ApplyThickFrame(Wnd, AResizable, AAllowMaximize, ANoFrame);
end;

function EdgeWndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  st: PEdgeState;
  orig: WNDPROC;
  pt: TPoint;
  wr: TRect;
begin
  st := FindEdge(Wnd);
  if st = nil then
    Exit(DefWindowProc(Wnd, Msg, WP, LP));
  orig := st^.OrigProc;
  case Msg of
    WM_NCHITTEST:
      // lParam is a SCREEN point, so compare against the surface's screen rect directly. The
      // decision itself is the pure TyEdgePassthrough, next to the other hit-test mappers and
      // unit-tested there -- this proc only supplies the rect and the point.
      if GetWindowRect(Wnd, @wr) then
      begin
        pt.X := SmallInt(LOWORD(DWORD(LP)));
        pt.Y := SmallInt(HIWORD(DWORD(LP)));
        if TyEdgePassthrough(wr, pt, st^.Zone, st^.Enabled) then
          Exit(HTTRANSPARENT);   // "not mine" -> the system asks the form underneath
      end;
    WM_NCDESTROY:
      begin
        SetWindowLongPtr(Wnd, GWLP_WNDPROC, LONG_PTR(orig));
        DropEdge(Wnd);
        Exit(CallWindowProc(orig, Wnd, Msg, WP, LP));
      end;
  end;
  Result := CallWindowProc(orig, Wnd, Msg, WP, LP);
end;

procedure TyWin32SetEdgePassthrough(AControl: TWinControl; AZone: Integer; AEnabled: Boolean);
var
  Wnd: HWND;
  st: PEdgeState;
begin
  if (AControl = nil) or (not AControl.HandleAllocated) then Exit;
  Wnd := AControl.Handle;
  st := FindEdge(Wnd);
  if st = nil then
  begin
    // Nothing to turn off and nothing installed: stay out of the window entirely, so a form
    // that never uses the opt-out is byte-for-byte the window it was before.
    if not AEnabled then Exit;
    New(st);
    st^.Wnd := Wnd;
    st^.OrigProc := WNDPROC(GetWindowLongPtr(Wnd, GWLP_WNDPROC));
    SetLength(GEdges, Length(GEdges) + 1);
    GEdges[High(GEdges)] := st;
    SetWindowLongPtr(Wnd, GWLP_WNDPROC, LONG_PTR(@EdgeWndProc));
  end;
  st^.Zone := AZone;
  st^.Enabled := AEnabled;
end;

procedure TyWin32BeginTopResize(AForm: TCustomForm);
begin
  if (AForm = nil) or (not AForm.HandleAllocated) then Exit;
  ReleaseCapture;
  SendMessage(AForm.Handle, WM_NCLBUTTONDOWN, HTTOP, 0);
end;

function TyWin32StartSystemMove(AForm: TCustomForm): Boolean;
begin
  Result := False;
  if (AForm = nil) or (not AForm.HandleAllocated) then Exit;
  // Release LCL's just-set mouse capture, then let the OS run its modal caption-move loop (which
  // includes Aero Snap + the snap preview). The press originated on the title-bar child, but a
  // WM_NCLBUTTONDOWN on the FORM with HTCAPTION starts the standard window drag regardless — the
  // Chrome / VS Code custom-title-bar route. SendMessage blocks until the drag ends, so on return
  // the move is already complete; the caller clears LCL capture and Exits (no manual repositioning).
  ReleaseCapture;
  SendMessage(AForm.Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
  Result := True;
end;

{$ELSE}

procedure TyWin32ApplyNcResize(AForm: TCustomForm; AResizable: Boolean;
  ABorderZone, ACaptionHeight: Integer; AMaximized, AAllowMaximize: Boolean;
  ANoFrame: Boolean);
begin
  // Non-Windows widgetset: native NC resize is a Win32-only strategy. GTK/Qt use the
  // AdjustClientRect gutter + WM handoff; Cocoa uses the resizable styleMask (later phases).
end;

procedure TyWin32SetEdgePassthrough(AControl: TWinControl; AZone: Integer; AEnabled: Boolean);
begin
  // The band this opens up only exists because Win32's WM_NCCALCSIZE gave the client the whole
  // window. GTK/Qt keep their alClient children off the edge with the AdjustClientRect gutter
  // instead, and Cocoa has a real resizable frame.
end;

procedure TyWin32BeginTopResize(AForm: TCustomForm);
begin
  // Native top-edge resize is a Win32-only strategy for now; GTK/Qt top-resize lands in Phase C.
end;

function TyWin32StartSystemMove(AForm: TCustomForm): Boolean;
begin
  // Native caption move is a Win32-only strategy; Qt/GTK have their own TyQt/TyGtkStartSystemMove.
  Result := False;
end;

{$ENDIF}

end.
