unit tyControls.WindowEffects;
{$mode objfpc}{$H+}
{$IFDEF LCLCOCOA}{$modeswitch objectivec1}{$ENDIF}

{ Cross-platform window chrome effects for the borderless TTyForm: OS-level rounded
  corners + a native drop shadow. All platform/widgetset code is isolated here so
  Form.pas stays clean.

  - Windows: dwmapi.dll loaded DYNAMICALLY (GetProcAddress) so the binary still launches
    on XP/7 (no static import). Win11 -> DWM corner preference (anti-aliased) + free shadow;
    Vista..10 -> square + DwmExtendFrameIntoClientArea native shadow; XP -> square, no shadow.
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
  end;

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

implementation

{$IFDEF WINDOWS}uses Windows;{$ENDIF}
{$IFDEF LCLCOCOA}uses CocoaAll;{$ENDIF}

function TyResolveWindowEffect(const AStyle: TTyStyleSet; AMaximized: Boolean): TTyWindowEffect;
begin
  if tpBorderRadius in AStyle.Present then Result.RadiusPx := AStyle.BorderRadius
  else Result.RadiusPx := TyDefaultWindowRadiusPx;            // default-on
  if tpWindowShadow in AStyle.Present then Result.Shadow := AStyle.WindowShadow
  else Result.Shadow := True;                                // default-on
  Result.Maximized := AMaximized;
end;

function TyRadiusToCornerPref(ARadiusPx: Integer; AMaximized: Boolean): Integer;
begin
  if AMaximized or (ARadiusPx <= 0) then Result := 1          // DWMWCP_DONOTROUND (1, NOT 0=DEFAULT)
  else if ARadiusPx <= 5 then Result := 3                     // DWMWCP_ROUNDSMALL
  else Result := 2;                                           // DWMWCP_ROUND
end;

{$IFDEF WINDOWS}
const
  DWMWA_WINDOW_CORNER_PREFERENCE = 33;
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
var h: HWND; pref: DWORD; m: TDwmMargins; comp: BOOL;
begin
  LoadDwm;
  h := AForm.Handle;
  if Assigned(FnSetAttr) then       // Win11: corner preference (no-op error on <Win11)
  begin
    pref := DWORD(TyRadiusToCornerPref(E.RadiusPx, E.Maximized));
    FnSetAttr(h, DWMWA_WINDOW_CORNER_PREFERENCE, @pref, SizeOf(pref));
  end;
  if Assigned(FnExtend) then        // Vista+: native shadow via 1px frame extension
  begin
    comp := False;
    if Assigned(FnCompEnabled) then FnCompEnabled(comp);
    FillChar(m, SizeOf(m), 0);
    if E.Shadow and comp and (not E.Maximized) then
    begin m.cxLeftWidth := 1; m.cxRightWidth := 1; m.cyTopHeight := 1; m.cyBottomHeight := 1; end;
    FnExtend(h, m);
  end;
end;
{$ENDIF}

{$IFDEF LCLCOCOA}
procedure ApplyCocoa(AForm: TCustomForm; const E: TTyWindowEffect);
var v, content: NSView; win: NSWindow; r: CGFloat;
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
    {$IFDEF WINDOWS}ApplyWindows(AForm, AEffect);{$ENDIF}
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

{$IFDEF WINDOWS}
finalization
  if GLib <> 0 then FreeLibrary(GLib);
{$ENDIF}
end.
