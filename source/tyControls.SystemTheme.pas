unit tyControls.SystemTheme;
{ P4 (D8 / §3.7). Best-effort OS light/dark + accent-colour detection.

  Hard rule (§7 risk 4): detection NEVER raises. Every platform path is wrapped so
  a missing key / unavailable API yields the documented fallback (tssUnknown for the
  scheme; False + a sensible accent fallback for the colour), never an exception. A
  caller in tfFollowSystem treats tssUnknown as "leave the current mode as-is".

  Platform coverage (§8 YAGNI: Windows + macOS first, Linux one-shot only):
    - Windows: registry (HKCU). Authoritative.
    - macOS  : `defaults read -g AppleInterfaceStyle` (gated by the DARWIN define);
               accent not detected yet (returns False).
    - Linux/other: tssUnknown / False. (No reliable cross-DE probe — design §7 risk 4.) }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tyControls.Types;

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
  process;   // RunCommand (FCL) — shells out to `defaults` for the macOS appearance
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
  outp: string;
begin
  Result := tssLight;   // macOS default is light; only "Dark" flips it
  try
    // `defaults read -g AppleInterfaceStyle` prints "Dark" in dark mode, and errors
    // (no such key) in light mode. RunCommand swallows the non-zero exit.
    if RunCommand('/usr/bin/defaults', ['read', '-g', 'AppleInterfaceStyle'], outp) then
    begin
      if Pos('dark', LowerCase(outp)) > 0 then
        Result := tssDark;
    end;
  except
    Result := tssUnknown;   // never raise
  end;
end;
  {$ELSE}
begin
  Result := tssUnknown;   // Linux/other: no reliable cross-DE probe (§7 risk 4 / §8)
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
  // macOS/Linux: accent probe is a documented follow-up. Leave a plausible fallback
  // so a follow-system theme still seeds a colour; return False so callers know it
  // is not the real OS accent.
  AColor := TyDefaultAccent;
  Result := False;
end;
{$ENDIF}

end.
