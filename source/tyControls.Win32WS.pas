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

implementation

{$IFDEF WINDOWS}
uses
  Windows,
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

function NcWndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  st: PNcState;
  orig: WNDPROC;
  pt: TPoint;
  wr: Windows.RECT;
  ncp: PNCCalcSizeParams;
  maxed: Boolean;
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
        // Remove the native caption/border (don't inset by the caption height) so the themed client
        // + children fill the WHOLE window. Returning 0 makes rgrc[0] the new client rect; we leave
        // it equal to the full window rect (except the maximize branch, which pins it to the work
        // area). WS_THICKFRAME still gives the OS a sizing border, and WM_NCHITTEST maps the outer
        // BorderZone pixels to HTLEFT..HTBOTTOMRIGHT on the full window rect, so edge-resize works
        // WITHOUT carving a physical client inset (which only exposed the raw frame as side stripes).
        if st^.Resizable then
        begin
          ncp := PNCCalcSizeParams(LP);
          maxed := st^.Maximized;          // engine (work-area) maximize
          if not maxed then maxed := IsZoomed(Wnd);   // native maximize / Aero-Snap
          if maxed then
          begin
            // Pin the client to the monitor WORK AREA (LCL-sourced, stored in the state) so it can
            // never overhang under the taskbar. Robust for BOTH maximize paths — no frame-overhang
            // guessing. (Empty/unset work area -> leave client = window: a safe fallback, since the
            // engine maximize already sizes the window to the work area.)
            if (st^.WorkArea.Right > st^.WorkArea.Left)
               and (st^.WorkArea.Bottom > st^.WorkArea.Top) then
            begin
              ncp^.rgrc[0].Left   := st^.WorkArea.Left;
              ncp^.rgrc[0].Top    := st^.WorkArea.Top;
              ncp^.rgrc[0].Right  := st^.WorkArea.Right;
              ncp^.rgrc[0].Bottom := st^.WorkArea.Bottom;
            end;
          end
          // else (normal, non-maximized): intentionally leave rgrc[0] = the whole window rect.
          // No L/R/B inset — the themed client + children cover the ENTIRE window, identical to the
          // non-resizable path. Edge-resize is provided by WM_NCHITTEST (TyNcHitTest hit-tests the
          // FULL window rect and returns HTLEFT..HTBOTTOMRIGHT for the outer BorderZone pixels), so
          // the physical inset bought nothing functionally — it only left the raw WS_THICKFRAME frame
          // (DWM active-frame color) exposed under the themed client, showing as an ACCENT stripe on
          // the left and a WHITE stripe on the right. Removing it fixes the stripes while
          // WS_THICKFRAME + the full-window-rect hit-test keep native edge-resize intact.
        end;
        Result := 0;
        Exit;
      end;
    WM_NCHITTEST:
      begin
        // Screen coords come in lParam; map to window-relative for the pure mapper.
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
  // Gate native maximize (Aero Snap / Win+Up / system menu) on the maximize box: a fixed or
  // no-maximize window must not be maximizable into the inset-cleared state.
  if AAllowMaximize then
    style := style or WS_MAXIMIZEBOX
  else
    style := style and (not WS_MAXIMIZEBOX);
  SetWindowLongPtr(Wnd, GWL_STYLE, style);
  SetWindowPos(Wnd, 0, 0, 0, 0, 0,
    SWP_FRAMECHANGED or SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
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
  // Refresh the live parameters the proc reads (Resizable / zone / caption height).
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

{$ENDIF}

end.
