unit tyControls.SystemTheme;
{ P4 (D8 / §3.7). Best-effort OS light/dark + accent-colour detection.

  Hard rule (§7 risk 4): detection NEVER raises. Every platform path is wrapped so
  a missing key / unavailable API yields the documented fallback (tssUnknown for the
  scheme; False + a sensible accent fallback for the colour), never an exception. A
  caller in tfFollowSystem treats tssUnknown as "leave the current mode as-is".

  Platform coverage (§8 YAGNI: Windows + macOS first, Linux one-shot only):
    - Windows: registry (HKCU). Authoritative.
    - macOS  : the AppleInterfaceStyle global default, read through CoreFoundation
               (gated by the DARWIN define); accent not detected yet (returns False).
    - Qt5/Qt6 (any OS, in practice Linux): the LIVE widgetset palette — clWindow vs
               clWindowText for light/dark, clHighlight for the accent. Qt maps those onto
               QPalette, and on Plasma QPalette::Highlight IS the colour scheme's Selection
               background, i.e. where KDE puts the accent once it is applied. No D-Bus, no
               config parsing, no subprocess — cheap enough to sit on the follow poll.
    - Linux on GTK2/GTK3: tssUnknown / False. GTK2 reads the real GTK style but freezes it
               at widgetset construction; GTK3 hardcodes several entries outright. A value
               that is wrong or stale is worse than admitting we do not know — see
               TySysColorsTrackDesktop (tyControls.PlatformWS) for the whole reasoning. }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Graphics,
  tyControls.Types, tyControls.Css.Values, tyControls.PlatformWS;

type
  { Detected OS appearance. tssUnknown = could not determine (key/API absent or the
    platform has no reliable probe) — callers must treat it as "no change". }
  TTySystemScheme = (tssLight, tssDark, tssUnknown);

{ Detect the OS light/dark preference. Windows reads
  HKCU\...\Themes\Personalize\AppsUseLightTheme (DWORD: 1=light, 0=dark; absent =>
  tssUnknown). macOS reads the global AppleInterfaceStyle default ("Dark" => dark,
  absent => light). Linux/other => tssUnknown. Never raises. }
function TyDetectSystemScheme: TTySystemScheme;

{ Detect the OS accent colour into AColor as a TTyColor ($AARRGGBB, alpha forced FF).
  Windows reads HKCU\...\DWM\AccentColor (DWORD ABGR) first, then ColorizationColor
  (DWORD 0xAARRGGBB) as a fallback. Returns True on success. On failure returns False
  and leaves AColor set to a sensible neutral fallback (a Windows-blue) so a caller can
  still seed a theme. macOS/Linux: returns False (accent probe is a follow-up). Never
  raises. }
function TyDetectSystemAccent(out AColor: TTyColor): Boolean;

{ Light/dark decided from a window background and the text colour painted ON it.

  Compares the two rather than thresholding one: a mid-grey theme sits right on top of any
  fixed threshold and would flip-flop, but no readable theme paints its text at the same
  luminance as the surface behind it. Identical colours mean we did not really read a palette,
  so the answer is tssUnknown. Pure — exposed so the decision is testable without a desktop. }
function TySchemeFromPalette(ABg, AFg: TTyColor): TTySystemScheme;

{ The desktop appearance as seen through the LCL system colours. Both answer "unknown" on every
  widgetset whose system colours do not track the desktop (TySysColorsTrackDesktop), so on
  Win32/GTK2/GTK3/Cocoa builds these are inert and the platform probes above stay in charge.
  Never raise. }
function TyPaletteScheme: TTySystemScheme;
function TyPaletteAccent(out AColor: TTyColor): Boolean;

{ Convenience: the scheme as the lowercase mode string a theme/Controller expects:
  tssLight->'light', tssDark->'dark', tssUnknown->'' (empty = no override). }
function TySchemeToMode(AScheme: TTySystemScheme): string;

const
  { Fallback accent when the OS accent cannot be read — a neutral Windows blue
    (#0078D7). Documented so a follow-system theme still resolves something plausible. }
  TyDefaultAccent: TTyColor = TTyColor($FF0078D7);

implementation

{$IFDEF WINDOWS}
uses
  Registry, Windows;
{$ENDIF}
{$IFDEF DARWIN}
uses
  MacOSAll;  // CoreFoundation — CFPreferencesCopyAppValue for the macOS appearance
{$ENDIF}

function TySchemeToMode(AScheme: TTySystemScheme): string;
begin
  case AScheme of
    tssLight: Result := 'light';
    tssDark:  Result := 'dark';
  else
    Result := '';
  end;
end;

function TySchemeFromPalette(ABg, AFg: TTyColor): TTySystemScheme;
begin
  if ABg = AFg then Exit(tssUnknown);   // no readable palette says this
  if TyLuminance(AFg) > TyLuminance(ABg) then Result := tssDark else Result := tssLight;
end;

{ Read one LCL system colour as a TTyColor with alpha forced FF. ColorToRGB resolves the
  clXxx index through the widgetset; RedGreenBlue then splits the BGR-ordered TColor. }
function SysColorAsTy(AColor: TColor): TTyColor;
var r, g, b: Byte;
begin
  RedGreenBlue(ColorToRGB(AColor), r, g, b);
  Result := TyRGBA(r, g, b, $FF);
end;

function TyPaletteScheme: TTySystemScheme;
begin
  Result := tssUnknown;
  if not TySysColorsTrackDesktop then Exit;
  try
    Result := TySchemeFromPalette(SysColorAsTy(clWindow), SysColorAsTy(clWindowText));
  except
    Result := tssUnknown;   // never raise
  end;
end;

function TyPaletteAccent(out AColor: TTyColor): Boolean;
begin
  AColor := TyDefaultAccent;
  Result := False;
  if not TySysColorsTrackDesktop then Exit;
  try
    AColor := SysColorAsTy(clHighlight);
    Result := True;
  except
    AColor := TyDefaultAccent;   // never raise
    Result := False;
  end;
end;

{$IFDEF WINDOWS}
{ Read a DWORD under HKCU\<APath> named AName. Returns True + the value on success.
  The whole body is try/except: a missing key/value, wrong type, or any registry
  error yields False (the documented fallback), never an exception. }
function ReadHKCUDword(const APath, AName: string; out AValue: Cardinal): Boolean;
var
  reg: TRegistry;
begin
  Result := False;
  AValue := 0;
  reg := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
  try
    try
      reg.RootKey := HKEY_CURRENT_USER;
      if reg.OpenKeyReadOnly(APath) then
        try
          if reg.ValueExists(AName)
             and (reg.GetDataType(AName) in [rdInteger, rdBinary]) then
          begin
            AValue := Cardinal(reg.ReadInteger(AName));
            Result := True;
          end;
        finally
          reg.CloseKey;
        end;
    except
      // Any registry failure -> documented fallback (Result stays False).
      Result := False;
    end;
  finally
    reg.Free;
  end;
end;
{$ENDIF}

function TyDetectSystemScheme: TTySystemScheme;
{$IFDEF WINDOWS}
var
  v: Cardinal;
begin
  // 1 = apps use light theme, 0 = dark. Key absent on very old builds -> Unknown.
  if ReadHKCUDword('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
                   'AppsUseLightTheme', v) then
  begin
    if v = 0 then Result := tssDark else Result := tssLight;
  end
  else
    Result := tssUnknown;
end;
{$ELSE}
  {$IFDEF DARWIN}
var
  v: CFPropertyListRef;
  buf: array[0..63] of Char;
begin
  Result := tssLight;   // macOS default is light; only "Dark" flips it
  try
    { AppleInterfaceStyle lives in NSGlobalDomain and is simply ABSENT in light mode.
      Read it through CoreFoundation instead of forking `defaults`: this sits on the follow
      POLL (tyControls.Form's FFollowTimer, 750 ms, one timer per TTyForm), so shelling out
      meant a subprocess per tick per window on the main thread for as long as Follow was on.
      CFPreferencesCopyAppValue searches the app domain and then the global one -- the order
      NSUserDefaults uses -- so an app-level override still wins. }
    v := CFPreferencesCopyAppValue(CFSTR('AppleInterfaceStyle'),
                                   kCFPreferencesCurrentApplication);
    if v <> nil then
      try
        if (CFGetTypeID(v) = CFStringGetTypeID)
           and CFStringGetCString(CFStringRef(v), @buf[0], SizeOf(buf), kCFStringEncodingUTF8)
           and (Pos('dark', LowerCase(StrPas(@buf[0]))) > 0) then
          Result := tssDark;
      finally
        CFRelease(v);
      end;
  except
    Result := tssUnknown;   // never raise
  end;
end;
  {$ELSE}
begin
  { Linux/other. On Qt the widgetset palette IS the desktop's, so this answers; on GTK it
    reports tssUnknown and the caller keeps its current mode. §8 asked for a one-shot Linux
    probe -- this is it, and being a plain palette read it is also cheap enough to poll. }
  Result := TyPaletteScheme;
end;
  {$ENDIF}
{$ENDIF}

function TyDetectSystemAccent(out AColor: TTyColor): Boolean;
{$IFDEF WINDOWS}
var
  v: Cardinal;
  r, g, b: Byte;
begin
  Result := False;
  AColor := TyDefaultAccent;   // sensible fallback if neither key is readable
  // Preferred: DWM\AccentColor is an 0xAABBGGRR DWORD (ABGR). Map to TTyColor and
  // force alpha FF (the stored alpha is the system's, not the swatch's opacity).
  if ReadHKCUDword('Software\Microsoft\Windows\DWM', 'AccentColor', v) then
  begin
    r := Byte(v         and $FF);   // low byte  = red
    g := Byte((v shr 8) and $FF);   // next byte = green
    b := Byte((v shr 16) and $FF);  // next byte = blue
    AColor := TyRGBA(r, g, b, $FF);
    Exit(True);
  end;
  // Fallback: ColorizationColor is an 0xAARRGGBB DWORD (ARGB). Take RGB, force alpha FF.
  if ReadHKCUDword('Software\Microsoft\Windows\DWM', 'ColorizationColor', v) then
  begin
    r := Byte((v shr 16) and $FF);  // ARGB: red is bits 16..23
    g := Byte((v shr 8)  and $FF);
    b := Byte(v          and $FF);
    AColor := TyRGBA(r, g, b, $FF);
    Exit(True);
  end;
end;
{$ELSE}
begin
  { Qt maps clHighlight onto QPalette::Highlight, which under Plasma is the colour scheme's
    Selection background -- exactly where KDE lands an applied accent. So on a Qt build this
    IS the desktop accent, with no D-Bus and no kdeglobals parsing. Off Qt this is inert and
    we fall through to the documented neutral fallback: a plausible colour so a follow-system
    theme still seeds something, plus False so callers know it is not the real OS accent. }
  if TyPaletteAccent(AColor) then Exit(True);
  AColor := TyDefaultAccent;
  Result := False;
end;
{$ENDIF}

end.
