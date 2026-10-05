unit tyControls.WindowEffects;
{$mode objfpc}{$H+}
{$IFDEF LCLCOCOA}{$modeswitch objectivec1}{$ENDIF}

{ Cross-platform window chrome effects for the borderless TTyForm: OS-level rounded
  corners + a native drop shadow. All platform/widgetset code is isolated here so
  Form.pas stays clean.

  - Windows: dwmapi.dll loaded DYNAMICALLY (GetProcAddress) so the binary still launches
    on XP/7 (no static import). Win11 -> DWM corner preference (anti-aliased) + free shadow +
    a pinned (COLOR_NONE) window-border so the 1px DWM frame stops flashing white/gray on
    activation; Vista..10 -> square + a top-1px DwmExtendFrameIntoClientArea for the popup-model
    shadow WITHOUT the WS_THICKFRAME activation-coloured 1px edge ring (Win10's equivalent of
    the Win11 COLOR_NONE fix; DWMWA_BORDER_COLOR is a no-op < Win11); XP -> square, no shadow.
    window-shadow: false -> DWMWA_NCRENDERING_POLICY=DISABLED, because on a RESIZABLE form the
    shadow is the STANDARD DWM frame shadow (left/right/bottom stay real frame under the
    top-only WM_NCCALCSIZE) and no margins call can remove that one — see ApplyWindows.
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

{ True only on Windows versions with NO DWM AT ALL -- XP / Server 2003 (major < 6), where the
  non-client area is always legacy-painted. Deliberately NOT "is composition enabled": Vista and
  Win7 can have it switched off at runtime, and those are versions whose frame handling is
  already settled and must not move. False on every non-Windows build. }
function TyOsLegacyNonClient: Boolean;

{ Whether the Win32 non-client calc should eat the WHOLE frame rather than only the top.

  The frame is kept for exactly ONE reason: it is what the DWM hangs the shadow on. On a
  version with no DWM the frame buys nothing and COSTS something -- the left/right/bottom bands
  stay real frame and the OS legacy-paints its own ring in them (on XP, the Luna blue border),
  and a WS_CAPTION window additionally gets its classic caption repainted over our chrome every
  time a menu or dropdown steals activation. Eating the whole frame is what ApplyThickFrame
  keys its WS_CAPTION removal off, so one flag settles both.

  Full-frame-eat has two costs, and BOTH are things XP does not have: the DWM shadow, and the
  shell's Aero Snap / native maximize (which need the WS_CAPTION this mode strips). That is
  why it is the right trade on XP specifically -- and why the gate is the OS version and not
  "is composition on". Vista and Win7 can run with composition off yet still have a DWM frame
  and snap to lose; their handling is settled and this must not touch it.

  Pure, so the rule is pinned rather than inferred from the platform code that reads it. }
function TyNcFullFrameEat(AShadowWanted, ALegacyNonClient: Boolean): Boolean;

{ Apply rounded corners + native shadow to AForm's window per platform/widgetset.
  Safe to call repeatedly and when AForm has no handle (no-op). Never raises. }
procedure TyApplyWindowEffects(AForm: TCustomForm; const AEffect: TTyWindowEffect);

var
  { TEST SEAM. The last effect TyApplyWindowEffects actually applied (i.e. the handle guard
    passed), plus a monotonic apply counter. Headless tests pin the whole form -> resolve ->
    apply pipe through these — e.g. that a TTyForm.StyleOverride 'window-shadow: false' really
    reaches the platform layer, at first apply AND on a live flip AND across maximize/restore —
    without reading DWM/Cocoa state back (which headless cannot). Library code must never make
    decisions from them. }
  TyLastWindowEffect: TTyWindowEffect;
  TyWindowEffectApplies: Cardinal = 0;

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

function TyNcFullFrameEat(AShadowWanted, ALegacyNonClient: Boolean): Boolean;
begin
  Result := (not AShadowWanted) or ALegacyNonClient;
end;

function TyRadiusToCornerPref(ARadiusPx: Integer; AMaximized: Boolean): Integer;
begin
  if AMaximized or (ARadiusPx <= 0) then Result := 1          // DWMWCP_DONOTROUND (1, NOT 0=DEFAULT)
  else if ARadiusPx <= 5 then Result := 3                     // DWMWCP_ROUNDSMALL
  else Result := 2;                                           // DWMWCP_ROUND
end;

{$IFDEF LCLWin32}
const
  DWMWA_NCRENDERING_POLICY       = 2;           // Vista+: force DWM non-client rendering on/off per window
  DWMNCRP_USEWINDOWSTYLE         = 0;           //   default: the window STYLE decides (frame windows render NC)
  DWMNCRP_DISABLED               = 1;           //   no DWM NC rendering: no frame visuals -> NO window shadow
  DWMNCRP_ENABLED                = 2;           //   force NC rendering even for styles that wouldn't (popup)
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
var h: HWND; ncrp, pref, bcol: DWORD; m: TDwmMargins; comp: BOOL;
begin
  LoadDwm;
  h := AForm.Handle;
  if Assigned(FnSetAttr) then       // Win11: corner preference (no-op error on <Win11)
  begin
    // window-shadow OPT-OUT — the fix for "window-shadow: false is ignored" (forum #14).
    // A RESIZABLE TTyForm is a WS_CAPTION|WS_THICKFRAME window whose WM_NCCALCSIZE eats only the
    // TOP (tyControls.Win32WS): left/right/bottom remain a REAL DWM-rendered frame, and DWM draws
    // the STANDARD frame shadow for any window whose non-client area it renders. That shadow is
    // entirely independent of DwmExtendFrameIntoClientArea, so the margins={0,0,0,0} below never
    // removed it — the opt-out silently did nothing on every resizable form (the default).
    // DWMWA_NCRENDERING_POLICY=DISABLED is the canonical per-window kill switch: DWM stops
    // rendering ALL frame visuals (standard shadow, Win11 1px border, and the frame-extension
    // glass, so the popup-model shadow dies with the same stone).
    // The Shadow=True branch must EXPLICITLY set a policy (not skip the call): a live theme
    // switch / StyleOverride flip false->true has to re-enable rendering on the SAME HWND — DWM
    // keeps per-window attributes until told otherwise, exactly like the corner preference. It
    // sets ENABLED, not USEWINDOWSTYLE: for the resizable (WS_CAPTION|WS_THICKFRAME) window the
    // two are identical, but a FIXED TTyForm is a bare WS_POPUP whose style renders no NC — under
    // USEWINDOWSTYLE its DwmExtendFrameIntoClientArea glass stays inert and it never had a shadow
    // at all (observed on Win10 19044); ENABLED arms the machinery so the top-1px extension below
    // yields the popup-model shadow too.
    // COMPANION: with NC rendering disabled, the L/R/B sizing bands of the resizable window get
    // LEGACY-painted as a classic frame ring (observed on Win10 19044), so ApplyResizeStrategy
    // resolves the same opt-out and makes WM_NCCALCSIZE full-frame-eat while it is active
    // (TyWin32ApplyNcResize's ANoFrame) — no NC band left to paint, clean edges.
    if E.Shadow then ncrp := DWMNCRP_ENABLED else ncrp := DWMNCRP_DISABLED;
    FnSetAttr(h, DWMWA_NCRENDERING_POLICY, @ncrp, SizeOf(ncrp));
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

function TyOsLegacyNonClient: Boolean;
begin
  { Major < 6 is XP / Server 2003 and older -- the versions with no dwmapi.dll at all. Vista is
    6.0 and Win7 is 6.1, and both stay OUT of this deliberately: they have a DWM frame and the
    shell gestures that ride on WS_CAPTION, so their non-client handling is settled and this
    must not disturb it. (Win32MajorVersion is the manifest-capped GetVersion value, which is
    fine here: every capped value is >= 6, so nothing modern can be mistaken for XP.) }
  Result := Win32MajorVersion < 6;
end;
{$ELSE}
function TyOsLegacyNonClient: Boolean;
begin
  { Off Win32 nothing consumes this -- the trade it feeds is a Win32 non-client question. }
  Result := False;
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
  TyLastWindowEffect := AEffect;   // test seam (see declaration): record only REAL applies,
  Inc(TyWindowEffectApplies);      // after the guard, before the platform branches
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
