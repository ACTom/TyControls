unit tyControls.WindowEffects;
{$mode objfpc}{$H+}
{$IFDEF LCLCOCOA}{$modeswitch objectivec1}{$ENDIF}

{ Cross-platform window chrome effects for the borderless TTyForm: OS-level rounded
  corners + a native drop shadow. All platform/widgetset code is isolated here so
  Form.pas stays clean.

  - Windows: dwmapi.dll loaded DYNAMICALLY (GetProcAddress) so the binary still launches
    on XP/7 (no static import). Win11 -> DWM corner preference (anti-aliased) + free shadow +
    a pinned (COLOR_NONE) window-border so the 1px DWM frame stops flashing white/gray on
    activation; Vista..10 -> square + SHEET-OF-GLASS DwmExtendFrameIntoClientArea (margins -1)
    for the native shadow WITHOUT the WS_THICKFRAME activation-coloured 1px edge ring (Win10's
    equivalent of the Win11 COLOR_NONE fix; DWMWA_BORDER_COLOR is a no-op < Win11); XP -> square,
    no shadow.
  - macOS (Cocoa): contentView.layer cornerRadius (anti-aliased) + NSWindow.hasShadow.
  - Linux: documented no-op extension point (see TyApplyWindowEffects). }

interface
uses Classes, SysUtils, Controls, Forms, tyControls.Types;
type
  { Logical (CSS) px radius, plus flags. RadiusPx is the css border-radius value (points/
    logical px); each platform scales as needed. Maximized -> always square. }
  TTyWindowEffect = record
    RadiusPx:  Integer;
    Shadow:    Boolean;
    Maximized: Boolean;
    // COLORREF (0x00BBGGRR) for the Win11 DWM window border (DWMWA_BORDER_COLOR). Resolved from the
    // theme: an explicit theme border (e.g. XP-Luna blue) shows that colour; otherwise the solid
    // background colour so the hairline blends into the client; $FFFFFFFE (COLOR_NONE) when neither
    // applies (image/gradient background). Theme-driven so the border is themeable, not hard-hidden.
    BorderColorRGB: Cardinal;
  end;

const
  TyDwmColorNone = Cardinal($FFFFFFFE);   // DWMWA_COLOR_NONE sentinel (no visible border)

const
  TyDefaultWindowRadiusPx = 8;   // corners ON by default; a theme sets border-radius: 0 to turn them off

{ Resolve the effect from a TyForm style under the DEFAULT-ON policy: corners + shadow are ON
  unless the theme opts out (border-radius: 0 / window-shadow: false). Pure -> headless-testable. }
function TyResolveWindowEffect(const AStyle: TTyStyleSet; AMaximized: Boolean): TTyWindowEffect;

{ Pure mapping for the Win11 DWM_WINDOW_CORNER_PREFERENCE enum:
  1 = DONOTROUND, 2 = ROUND, 3 = ROUNDSMALL. (0 = DEFAULT lets DWM decide -> it ROUNDS
  top-level windows, which is NOT what we want for opt-out/maximize.) Exposed for testing. }
function TyRadiusToCornerPref(ARadiusPx: Integer; AMaximized: Boolean): Integer;

{ Apply rounded corners + native shadow to AForm's window per platform/widgetset.
  Safe to call repeatedly and when AForm has no handle (no-op). Never raises. }
procedure TyApplyWindowEffects(AForm: TCustomForm; const AEffect: TTyWindowEffect);

{ True when AControl's window is an OS-resizable, non-maximized window (WS_THICKFRAME on Windows;
  False on other platforms). }
function TyWindowResizable(AControl: TControl): Boolean;
{ Hand a bottom/corner drag from a child control (e.g. a status bar that covers the form's bottom
  edge) to the OS window-resize loop. AEdge is a Win32 WM_NCHITTEST edge code (HTBOTTOM=15,
  HTBOTTOMLEFT=16, HTBOTTOMRIGHT=17; 0 = none). Returns True iff it started an OS resize (Windows,
  resizable, non-maximized); a no-op returning False otherwise. }
function TyStartNativeResize(AControl: TControl; AEdge: Integer): Boolean;

implementation

{$IFDEF LCLWin32}uses Windows;{$ENDIF}
{$IFDEF LCLCOCOA}uses CocoaAll;{$ENDIF}

function TyToColorRef(c: TTyColor): Cardinal;   // TTyColor $AARRGGBB -> COLORREF 0x00BBGGRR
begin
  Result := Cardinal(TyRedOf(c)) or (Cardinal(TyGreenOf(c)) shl 8) or (Cardinal(TyBlueOf(c)) shl 16);
end;

function TyResolveWindowEffect(const AStyle: TTyStyleSet; AMaximized: Boolean): TTyWindowEffect;
begin
  if tpBorderRadius in AStyle.Present then Result.RadiusPx := AStyle.BorderRadius
  else Result.RadiusPx := TyDefaultWindowRadiusPx;            // default-on
  if tpWindowShadow in AStyle.Present then Result.Shadow := AStyle.WindowShadow
  else Result.Shadow := True;                                // default-on
  Result.Maximized := AMaximized;
  // DWM window-border colour, theme-driven (Win11 only; harmless elsewhere):
  //  - explicit theme border (border-color + width>0) -> that colour (e.g. XP-Luna blue frame);
  //  - else a SOLID themed background -> the background colour, so the 1px DWM border blends away
  //    (COLOR_NONE was observed NOT to hide it on some machines; a matching colour is more reliable);
  //  - else (image/gradient bg, no single colour) -> COLOR_NONE.
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0) then
    Result.BorderColorRGB := TyToColorRef(AStyle.BorderColor)
  else if (tpBackground in AStyle.Present) and (AStyle.Background.Kind = tfkSolid) then
    Result.BorderColorRGB := TyToColorRef(AStyle.Background.Color)
  else
    Result.BorderColorRGB := TyDwmColorNone;
end;

function TyRadiusToCornerPref(ARadiusPx: Integer; AMaximized: Boolean): Integer;
begin
  if AMaximized or (ARadiusPx <= 0) then Result := 1          // DWMWCP_DONOTROUND (1, NOT 0=DEFAULT)
  else if ARadiusPx <= 5 then Result := 3                     // DWMWCP_ROUNDSMALL
  else Result := 2;                                           // DWMWCP_ROUND
end;

{$IFDEF LCLWin32}
const
  DWMWA_WINDOW_CORNER_PREFERENCE = 33;
  DWMWA_BORDER_COLOR             = 34;          // Win11 22000+: the 1px DWM window-border color
  DWMWA_COLOR_NONE               = $FFFFFFFE;   // "no visible border" sentinel for DWMWA_BORDER_COLOR
  Win11Build                     = 22000;       // first Win11 build; DWMWA_BORDER_COLOR is a no-op before it
type
  TDwmMargins = record cxLeftWidth, cxRightWidth, cyTopHeight, cyBottomHeight: LongInt; end;
  TDwmSetWindowAttribute = function(h: HWND; a: DWORD; pv: Pointer; cb: DWORD): HRESULT; stdcall;
  TDwmExtendFrame = function(h: HWND; const m: TDwmMargins): HRESULT; stdcall;
  TDwmIsCompEnabled = function(out e: BOOL): HRESULT; stdcall;
var
  GLoaded: Boolean = False;
  GLib: HMODULE = 0;
  FnSetAttr: TDwmSetWindowAttribute = nil;
  FnExtend: TDwmExtendFrame = nil;
  FnCompEnabled: TDwmIsCompEnabled = nil;

procedure LoadDwm;
begin
  if GLoaded then Exit;
  GLoaded := True;
  GLib := LoadLibrary('dwmapi.dll');               // absent on XP -> 0 -> all Fn stay nil
  if GLib = 0 then Exit;
  Pointer(FnSetAttr) := GetProcAddress(GLib, 'DwmSetWindowAttribute');
  Pointer(FnExtend) := GetProcAddress(GLib, 'DwmExtendFrameIntoClientArea');
  Pointer(FnCompEnabled) := GetProcAddress(GLib, 'DwmIsCompositionEnabled');
end;

procedure ApplyWindows(AForm: TCustomForm; const E: TTyWindowEffect);
var h: HWND; pref, bcol: DWORD; m: TDwmMargins; comp: BOOL;
begin
  LoadDwm;
  h := AForm.Handle;
  if Assigned(FnSetAttr) then       // Win11: corner preference (no-op error on <Win11)
  begin
    pref := DWORD(TyRadiusToCornerPref(E.RadiusPx, E.Maximized));
    FnSetAttr(h, DWMWA_WINDOW_CORNER_PREFERENCE, @pref, SizeOf(pref));
    // Pin the 1px DWM window border so it stops showing as a hairline edge (a faint light line in a
    // dark theme) and stops flashing white (deactivated) / gray (dragging) as focus moves to a popup
    // and back. A resizable TTyForm carries WS_THICKFRAME, and Win11 draws a DWM border on such
    // windows whose color tracks active/inactive; the form has its OWN custom chrome + rounded corners
    // + shadow, so it needs no OS border. COLOR_NONE removes the visible border entirely.
    //
    // Call it UNCONDITIONALLY (no Win32BuildNumber gate): an un-manifested exe misreports
    // Win32BuildNumber as 9200 (Win8) EVEN ON Win11, so a `>= 22000` gate wrongly skips this on the
    // very OS where the border shows — the exact reported hairline. DWMWA_BORDER_COLOR is ignored
    // (errors harmlessly) on Win10 and older, so the unconditional call is safe there; and on real
    // Win11 the OS honors it regardless of the misreported build number (same as the corner
    // preference above, which is applied here and demonstrably works). If a real machine ever needs
    // visible edge separation, the fallback is a theme-matched COLORREF (0x00BBGGRR) instead of NONE.
    bcol := E.BorderColorRGB;   // theme-driven (see TyResolveWindowEffect); COLOR_NONE if unset
    FnSetAttr(h, DWMWA_BORDER_COLOR, @bcol, SizeOf(bcol));
  end;
  if Assigned(FnExtend) then        // Vista+: native shadow via frame extension
  begin
    comp := False;
    if Assigned(FnCompEnabled) then FnCompEnabled(comp);
    FillChar(m, SizeOf(m), 0);
    if E.Shadow and comp and (not E.Maximized) then
    begin
      // Canonical "borderless window WITH drop shadow": extend the frame a HAIRLINE — but ONLY on the
      // TOP. Any single non-zero margin re-enables the full native DWM drop shadow (it wraps all four
      // sides regardless of which edge is extended), so 1px on top is enough. We must NOT extend the
      // left/right/bottom: on a resizable WS_THICKFRAME form the client's BeginPaint SYSRGN stays inset
      // a hairline short of the client edge, so the form's opaque paint canNOT cover that outermost
      // pixel row/column — and any glass we extend there shows through as a ~1px light band (invisible
      // in light themes, a faint line in dark ones: the reported edge). The top is covered flush by the
      // opaque title bar, so its 1px extension is always hidden. This pairs with the top-only
      // WM_NCCALCSIZE in tyControls.Win32WS (left/right/bottom stay real OS frame).
      //
      // We also deliberately do NOT use the {-1,-1,-1,-1} "sheet of glass": -1 turns the ENTIRE window
      // into glass that shows through wherever a pixel is alpha 0, an even worse version of the same
      // edge band. On Win11 the 1px DWM border is additionally pinned to COLOR_NONE above; on Win10 a
      // faint activation-tracked edge may remain (WM_NCACTIVATE suppresses its repaint).
      m.cyTopHeight := 1;   // top-only; left/right/bottom stay 0 (see above)
    end;
    FnExtend(h, m);
  end;
end;
{$ENDIF}

{$IFDEF LCLCOCOA}
procedure ApplyCocoa(AForm: TCustomForm; const E: TTyWindowEffect);
// r is Double (not CGFloat): CocoaAll doesn't surface CGFloat in all FPC versions, and the
// CALayer binding's setCornerRadius takes Double — which CGFloat already is on 64-bit macOS.
var v, content: NSView; win: NSWindow; r: Double;
begin
  v := NSView(AForm.Handle);          // LCL-Cocoa: Form.Handle is a TCocoaWindowContent (NSView)
  if v = nil then Exit;
  win := v.window;
  if win = nil then Exit;
  content := win.contentView;
  if content = nil then Exit;
  content.setWantsLayer(True);
  if E.Maximized then r := 0 else r := E.RadiusPx;     // points (logical) == css px
  if content.layer <> nil then
  begin
    content.layer.setCornerRadius(r);
    content.layer.setMasksToBounds(r > 0);
  end;
  win.setHasShadow(E.Shadow);
end;
{$ENDIF}

procedure TyApplyWindowEffects(AForm: TCustomForm; const AEffect: TTyWindowEffect);
begin
  if (AForm = nil) or (not AForm.HandleAllocated) then Exit;
  try
    {$IFDEF LCLWin32}ApplyWindows(AForm, AEffect);{$ENDIF}
    {$IFDEF LCLCOCOA}ApplyCocoa(AForm, AEffect);{$ENDIF}
    { Linux extension point — documented no-ops for now:
      LCLQT5/LCLQT6: translucent window + AA paint + custom shadow (Qt composites
        lightweight children, so no Win32-HWND blocker) -- the promising future path.
      LCLGTK2: gdk_window_shape_combine_region gives only jagged corners -> skipped per the
        AA-only rule.  LCLGTK3: no window-shape API.  All deferred until a Linux verify rig. }
  except
    // capability/quirk failures must never crash the host app -- degrade silently
  end;
end;

function TyWindowResizable(AControl: TControl): Boolean;
{$IFDEF LCLWin32}
var frm: TCustomForm;
{$ENDIF}
begin
  Result := False;
  {$IFDEF LCLWin32}
  frm := GetParentForm(AControl);
  if (frm <> nil) and frm.HandleAllocated and (frm.WindowState <> wsMaximized) then
    Result := (GetWindowLong(frm.Handle, GWL_STYLE) and WS_THICKFRAME) <> 0;
  {$ENDIF}
end;

function TyStartNativeResize(AControl: TControl; AEdge: Integer): Boolean;
{$IFDEF LCLWin32}
var frm: TCustomForm;
{$ENDIF}
begin
  Result := False;
  if AEdge = 0 then Exit;
  {$IFDEF LCLWin32}
  frm := GetParentForm(AControl);
  if (frm <> nil) and frm.HandleAllocated and (frm.WindowState <> wsMaximized)
    and ((GetWindowLong(frm.Handle, GWL_STYLE) and WS_THICKFRAME) <> 0) then
  begin
    ReleaseCapture;                                          // release the child's mouse capture
    SendMessage(frm.Handle, WM_NCLBUTTONDOWN, WPARAM(AEdge), 0);  // OS takes over the resize drag
    Result := True;
  end;
  {$ENDIF}
end;

{$IFDEF LCLWin32}
finalization
  if GLib <> 0 then FreeLibrary(GLib);
  GLib := 0; FnSetAttr := nil; FnExtend := nil; FnCompEnabled := nil;  // no dangling procs post-unload
{$ENDIF}
end.
