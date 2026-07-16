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
    - WM_NCHITTEST: screen point -> window-relative -> TyNcHitTest (the pure mapper in Form.pas)
      -> HTLEFT..HTBOTTOMRIGHT / HTCAPTION / HTCLIENT, gated by Resizable.
    - WM_NCDESTROY: restore the original proc and drop the per-window state.
  WS_THICKFRAME (stripped from a bsNone form) is (re)asserted per Resizable.

  LIVE resize / DWM-corner interaction / native maximize+snap are REAL-MACHINE checkpoints —
  they cannot be verified headlessly (no window manager). This unit's contract is only that it
  compiles and installs cleanly; the pure mapper it calls is unit-tested in test.form. }

interface

uses
  Forms;

{ Assert/clear WS_THICKFRAME on AForm's window per AResizable and refresh the frame
  (SetWindowPos SWP_FRAMECHANGED), then install (idempotent) or refresh the NC subclass so
  WM_NCCALCSIZE/WM_NCHITTEST are handled with the current Resizable / border-zone / caption
  height. Safe to call repeatedly and when AForm has no handle (no-op). No-op off Windows. }
procedure TyWin32ApplyNcResize(AForm: TCustomForm; AResizable: Boolean;
  ABorderZone, ACaptionHeight: Integer; AMaximized, AAllowMaximize: Boolean);

{ Begin a native top-edge resize of AForm. The flush title bar covers the top (there is no NC
  strip there), so the OS can't start a top resize itself; the title bar calls this from its top
  hot-zone via WM_NCLBUTTONDOWN/HTTOP. No-op off Windows / when AForm has no handle. }
procedure TyWin32BeginTopResize(AForm: TCustomForm);

{ Hand a title-bar drag to the OS as a native caption move (WM_NCLBUTTONDOWN/HTCAPTION) so Windows
  runs its modal move loop — which provides Aero Snap (drag to a screen edge) + the snap preview,
  none of which a manual Left/Top drag can trigger. Returns True when it took over the move (Win32
  with a handle); the caller then skips its manual-drag fallback. Returns False off Windows / with no
  handle so the caller keeps its existing per-move repositioning. Mirrors the Qt/GTK system-move. }
function TyWin32StartSystemMove(AForm: TCustomForm): Boolean;

implementation

{$IFDEF LCLWin32}
uses
  Windows,
  SysUtils,          // Win32MajorVersion / Win32MinorVersion (RTL globals) for the Vista/Win7 check
  Types,             // listed AFTER Windows so Types.Rect/Point (functions) shadow Windows' TYPES
  tyControls.Form;   // TyNcHitTest (pure mapper) + TyHT* — implementation-section cycle, legal

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
    WorkArea: TRect;      // monitor work area (LCL-sourced) -> pin the client when maximized
  end;

var
  GStates: array of PNcState;

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
  hit: Integer;        // WM_NCHITTEST: pure-mapper result to graft the top edge/caption onto DefWindowProc
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
          if (st^.WorkArea.Right > st^.WorkArea.Left)
             and (st^.WorkArea.Bottom > st^.WorkArea.Top) then
          begin
            ncp^.rgrc[0].Left   := st^.WorkArea.Left;
            ncp^.rgrc[0].Top    := st^.WorkArea.Top;
            ncp^.rgrc[0].Right  := st^.WorkArea.Right;
            ncp^.rgrc[0].Bottom := st^.WorkArea.Bottom;
          end;
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
        if st^.Resizable then
        begin
          // top-only NCCALCSIZE keeps left/right/bottom as the REAL OS sizing frame, so DefWindowProc
          // hit-tests those resize edges + corners correctly (accounting for the invisible outer resize
          // margin, which a full-window mapper cannot). Chain to it, then re-add ONLY the top: the flush
          // title bar makes the top edge + caption band client (DefWindowProc returns HTCLIENT there), so
          // we map HTTOP for the top resize strip and HTCAPTION for the title-bar drag band.
          Result := CallWindowProc(orig, Wnd, Msg, WP, LP);
          if Result = HTCLIENT then
          begin
            pt.X := SmallInt(LOWORD(DWORD(LP)));
            pt.Y := SmallInt(HIWORD(DWORD(LP)));
            if GetWindowRect(Wnd, @wr) then
            begin
              Dec(pt.X, wr.Left);
              Dec(pt.Y, wr.Top);
              hit := TyNcHitTest(Rect(0, 0, wr.Right - wr.Left, wr.Bottom - wr.Top),
                pt, st^.BorderZone, st^.CaptionH, st^.Resizable);
              if (hit = TyHTTOP) or (hit = TyHTTOPLEFT) or (hit = TyHTTOPRIGHT)
                 or (hit = TyHTCAPTION) then
                Result := hit;
            end;
          end;
          Exit;
        end;
        // Fixed (non-resizable): no sizing frame; the pure mapper yields only HTCAPTION / HTCLIENT.
        pt.X := SmallInt(LOWORD(DWORD(LP)));
        pt.Y := SmallInt(HIWORD(DWORD(LP)));
        if GetWindowRect(Wnd, @wr) then
        begin
          Dec(pt.X, wr.Left);
          Dec(pt.Y, wr.Top);
          Result := TyNcHitTest(Rect(0, 0, wr.Right - wr.Left, wr.Bottom - wr.Top),
            pt, st^.BorderZone, st^.CaptionH, st^.Resizable);
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

procedure ApplyThickFrame(Wnd: HWND; AResizable, AAllowMaximize: Boolean);
var style: PtrInt;
begin
  style := GetWindowLongPtr(Wnd, GWL_STYLE);
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
  ABorderZone, ACaptionHeight: Integer; AMaximized, AAllowMaximize: Boolean);
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
  if AForm.Monitor <> nil then
    st^.WorkArea := AForm.Monitor.WorkareaRect;   // LCL-sourced; pins the client when maximized
  ApplyThickFrame(Wnd, AResizable, AAllowMaximize);
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
  ABorderZone, ACaptionHeight: Integer; AMaximized, AAllowMaximize: Boolean);
begin
  // Non-Windows widgetset: native NC resize is a Win32-only strategy. GTK/Qt use the
  // AdjustClientRect gutter + WM handoff; Cocoa uses the resizable styleMask (later phases).
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
