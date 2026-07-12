unit tyControls.IconFont;
{$mode objfpc}{$H+}

{ TTyIconFont — a non-visual icon-font source. Registers an icon font (a .ttf
  file, loaded PRIVATE to the process so it need not be OS-installed) and maps
  glyph *names* to Unicode codepoints, then renders any named glyph to a BGRA
  bitmap at a given pixel size + color. It is the scalable-vector-icon backbone
  consumed by TTyCharImage, TTyGlyphImageList and (later) the ribbon buttons.

  Rendering reuses BGRABitmap's system font renderer via the registered family
  name — no extra FreeType dependency. Font-file loading is done with each OS's
  NATIVE runtime-registration API (no install needed): Windows AddFontResourceEx/
  FR_PRIVATE, macOS/Cocoa CTFontManagerRegisterFontsForURL, Qt5/Qt6
  QFontDatabase.addApplicationFont, GTK2 fontconfig FcConfigAppFontAddFile. The
  name->codepoint map is pure and unit-tested headlessly; the rasterized pixels
  (and the non-Windows loaders) need a real machine + font to verify.

  Glyphs are stored as 'name=HEX' lines (e.g. save=F0C7) in the published Glyphs
  list, so they can be edited in the designer or loaded from a file. }

interface

uses
  Classes, SysUtils, Types, Graphics, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter;

type
  TTyIconFont = class(TComponent)
  private
    FGlyphs: TStringList;      // 'name=HEX' entries
    FFontFamily: string;
    FFontFile: string;
    FLoadedFile: string;       // the file currently registered (for clean removal)
    {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
    FQtFontId: Integer;        // Qt application-font id (>=0) for removeApplicationFont
    {$ENDIF}
    procedure SetGlyphs(AValue: TStringList);
    procedure SetFontFile(const AValue: string);
    procedure LoadFontFile(const APath: string);
    procedure UnloadFontFile;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Map (or re-map) a glyph name to a codepoint. }
    procedure MapGlyph(const AName: string; ACodepoint: Cardinal);
    procedure ClearGlyphs;
    { Codepoint for AName, or 0 if unmapped/invalid. }
    function CodepointOf(const AName: string): Cardinal;
    { The UTF-8 text for AName's glyph, or '' if unmapped. }
    function GlyphText(const AName: string): string;
    { True when AName resolves to a mapped codepoint. }
    function HasGlyph(const AName: string): Boolean;
    { Render AName's glyph centered in an ASizePx square, colored AColor, on a
      transparent background. Caller owns the returned bitmap. Returns an empty
      transparent bitmap when the name is unmapped or ASizePx <= 0. }
    function RenderGlyph(const AName: string; ASizePx: Integer;
      AColor: TTyColor): TBGRABitmap;
  published
    { The font family name used to render (must match the registered/installed
      family). When FontFile is set, this is typically the file's family. }
    property FontFamily: string read FFontFamily write FFontFamily;
    { Optional path to a .ttf loaded PRIVATE to the process (Windows). Setting it
      registers the font; clearing/reassigning unregisters the previous one. }
    property FontFile: string read FFontFile write SetFontFile;   // .ttf, loaded per-OS native
    { 'name=HEX' codepoint map, e.g. save=F0C7. }
    property Glyphs: TStringList read FGlyphs write SetGlyphs;
  end;

{ Pure: parse a hex codepoint string ('F0C7', '0xF0C7', '$F0C7', 'U+F0C7'),
  returning 0 on empty/invalid. Headless-testable. }
function TyParseCodepoint(const AHex: string): Cardinal;

implementation

uses
  LazUTF8
  {$IFDEF LCLQt5}, qt5{$ENDIF}
  {$IFDEF LCLQt6}, qt6{$ENDIF}
  {$IFDEF LCLCocoa}, MacOSAll{$ENDIF}
  ;

{$IFDEF LCLGtk2}
// GTK2/Pango resolve fonts through fontconfig; FPC ships no fontconfig binding, so
// declare the two C calls we need (libfontconfig is already linked by the GTK2 stack).
// FcConfigAppFontAddFile adds an app-scoped font file to the CURRENT config; contexts
// created AFTER this see the family (load at startup, before drawing).
type
  PFcConfig = Pointer;
function FcConfigGetCurrent: PFcConfig; cdecl; external 'fontconfig';
function FcConfigAppFontAddFile(config: PFcConfig; fileName: PAnsiChar): LongInt;
  cdecl; external 'fontconfig';
{$ENDIF}

{$IFDEF LCLWin32}
// FPC's Windows unit does not export the *Ex font APIs; declare them. Use the
// WIDE variants so a font path with non-ASCII characters (e.g. a Chinese user
// profile) registers correctly — the LCL path is UTF-8, converted to UTF-16.
const
  FR_PRIVATE = $10;
function AddFontResourceEx(lpszFilename: PWideChar; fl: LongWord;
  pdv: Pointer): LongInt; stdcall; external 'gdi32' name 'AddFontResourceExW';
function RemoveFontResourceEx(lpFileName: PWideChar; fl: LongWord;
  pdv: Pointer): LongBool; stdcall; external 'gdi32' name 'RemoveFontResourceExW';
{$ENDIF}

function TyParseCodepoint(const AHex: string): Cardinal;
var
  s: string;
  v: Int64;
begin
  s := Trim(AHex);
  if s = '' then Exit(0);
  // Normalize common prefixes to a bare hex string.
  if (Length(s) >= 2) and (s[1] = '0') and ((s[2] = 'x') or (s[2] = 'X')) then
    s := Copy(s, 3, MaxInt)
  else if (Length(s) >= 2) and ((s[1] = 'U') or (s[1] = 'u')) and (s[2] = '+') then
    s := Copy(s, 3, MaxInt)
  else if (s[1] = '$') then
    s := Copy(s, 2, MaxInt);
  if s = '' then Exit(0);
  if not TryStrToInt64('$' + s, v) then Exit(0);
  if (v < 0) or (v > $10FFFF) then Exit(0);
  if (v >= $D800) and (v <= $DFFF) then Exit(0);   // lone UTF-16 surrogate -> invalid
  Result := Cardinal(v);
end;

constructor TTyIconFont.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGlyphs := TStringList.Create;
  FGlyphs.NameValueSeparator := '=';
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  FQtFontId := -1;
  {$ENDIF}
end;

destructor TTyIconFont.Destroy;
begin
  UnloadFontFile;
  FGlyphs.Free;
  inherited Destroy;
end;

procedure TTyIconFont.SetGlyphs(AValue: TStringList);
begin
  FGlyphs.Assign(AValue);
end;

procedure TTyIconFont.MapGlyph(const AName: string; ACodepoint: Cardinal);
begin
  if AName = '' then Exit;
  FGlyphs.Values[AName] := IntToHex(ACodepoint, 1);
end;

procedure TTyIconFont.ClearGlyphs;
begin
  FGlyphs.Clear;
end;

function TTyIconFont.CodepointOf(const AName: string): Cardinal;
begin
  Result := TyParseCodepoint(FGlyphs.Values[AName]);
end;

function TTyIconFont.HasGlyph(const AName: string): Boolean;
begin
  Result := CodepointOf(AName) > 0;
end;

function TTyIconFont.GlyphText(const AName: string): string;
var
  cp: Cardinal;
begin
  cp := CodepointOf(AName);
  if cp = 0 then Exit('');
  Result := UnicodeToUTF8(cp);
end;

function TTyIconFont.RenderGlyph(const AName: string; ASizePx: Integer;
  AColor: TTyColor): TBGRABitmap;
var
  s: string;
  sz: TSize;
begin
  if ASizePx < 1 then ASizePx := 1;
  Result := TBGRABitmap.Create(ASizePx, ASizePx, BGRAPixelTransparent);
  s := GlyphText(AName);
  if (s = '') or (FFontFamily = '') then Exit;
  Result.FontName := FFontFamily;
  Result.FontHeight := ASizePx;
  Result.FontQuality := fqFineAntialiasing;
  Result.FontStyle := [];
  sz := Result.TextSize(s);
  Result.TextOut((ASizePx - sz.cx) div 2, (ASizePx - sz.cy) div 2, s,
    TyColorToBGRA(AColor));
end;

procedure TTyIconFont.SetFontFile(const AValue: string);
begin
  if FFontFile = AValue then Exit;
  UnloadFontFile;
  FFontFile := AValue;
  if FFontFile <> '' then
    LoadFontFile(FFontFile);
end;

procedure TTyIconFont.LoadFontFile(const APath: string);
{$IF DEFINED(WINDOWS) OR DEFINED(LCLQt5) OR DEFINED(LCLQt6) OR DEFINED(LCLCocoa)}
var
  {$IFDEF LCLWin32}
  w: UnicodeString;
  {$ENDIF}
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  ws: WideString;
  {$ENDIF}
  {$IFDEF LCLCocoa}
  url: CFURLRef;
  err: CFErrorRef;
  u8: RawByteString;
  {$ENDIF}
{$ENDIF}
begin
  if (APath = '') or (not FileExists(APath)) then Exit;
  {$IFDEF LCLWin32}
  w := UTF8ToUTF16(APath);
  if AddFontResourceEx(PWideChar(w), FR_PRIVATE, nil) > 0 then
    FLoadedFile := APath;
  {$ENDIF}
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  ws := UTF8ToUTF16(APath);                          // Qt takes a QString (PWideString)
  FQtFontId := QFontDatabase_addApplicationFont(@ws);
  if FQtFontId >= 0 then FLoadedFile := APath;       // font ids start at 0; -1 = failure
  {$ENDIF}
  {$IFDEF LCLCocoa}
  u8 := APath;                                        // UTF-8 filesystem path
  url := CFURLCreateFromFileSystemRepresentation(nil, CStringPtr(PAnsiChar(u8)),
    Length(u8), False);
  if url <> nil then
  try
    err := nil;
    if CTFontManagerRegisterFontsForURL(url, kCTFontManagerScopeProcess, err) <> 0 then
      FLoadedFile := APath;
  finally
    CFRelease(url);
  end;
  {$ENDIF}
  {$IFDEF LCLGtk2}
  // fontconfig wants the raw UTF-8 path; new Pango contexts then resolve the family.
  if FcConfigAppFontAddFile(FcConfigGetCurrent, PAnsiChar(APath)) <> 0 then
    FLoadedFile := APath;
  {$ENDIF}
end;

procedure TTyIconFont.UnloadFontFile;
{$IF DEFINED(WINDOWS) OR DEFINED(LCLCocoa)}
var
  {$IFDEF LCLWin32}
  w: UnicodeString;
  {$ENDIF}
  {$IFDEF LCLCocoa}
  url: CFURLRef;
  err: CFErrorRef;
  u8: RawByteString;
  {$ENDIF}
{$ENDIF}
begin
  {$IFDEF LCLWin32}
  if FLoadedFile <> '' then
  begin
    w := UTF8ToUTF16(FLoadedFile);
    RemoveFontResourceEx(PWideChar(w), FR_PRIVATE, nil);
  end;
  {$ENDIF}
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  if FQtFontId >= 0 then
  begin
    QFontDatabase_removeApplicationFont(FQtFontId);
    FQtFontId := -1;
  end;
  {$ENDIF}
  {$IFDEF LCLCocoa}
  if FLoadedFile <> '' then
  begin
    u8 := FLoadedFile;
    url := CFURLCreateFromFileSystemRepresentation(nil, CStringPtr(PAnsiChar(u8)),
      Length(u8), False);
    if url <> nil then
    try
      err := nil;
      CTFontManagerUnregisterFontsForURL(url, kCTFontManagerScopeProcess, err);
    finally
      CFRelease(url);
    end;
  end;
  {$ENDIF}
  {$IFDEF LCLGtk2}
  // fontconfig has no per-file app-font removal (only FcConfigAppFontClear wipes ALL),
  // so an added font stays registered for the process lifetime — nothing to undo here.
  {$ENDIF}
  FLoadedFile := '';
end;

end.
