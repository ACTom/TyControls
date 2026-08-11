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
  Classes, SysUtils, Types, Graphics, LazMethodList, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Component, tyControls.Painter;

type
  TTyIconFont = class(TTyComponent)
  private
    FGlyphs: TStringList;      // 'name=HEX' entries
    FFontFamily: string;
    FFontFile: string;
    FLoadedFile: string;       // the file currently registered (for clean removal)
    FLoadError: string;        // why the last font source did not take, '' when it did
    { "A source was asked for" vs "it registered". Available needs both: a component with only
      a FontFamily is fine (the family is OS-installed), one that ASKED for a file or a byte
      buffer and did not get it is not. }
    FSourceRequested: Boolean;
    FSourceLoaded: Boolean;
    {$IFDEF LCLWin32}
    FMemFont: THandle;         // AddFontMemResourceEx handle; there is no removal BY NAME
    {$ENDIF}
    {$IFDEF LCLGtk2}
    FTempFile: string;         // fontconfig is path-only, so bytes have to land on disk
    {$ENDIF}
    FVersion: Integer;         // bumped by every change a consumer would have to repaint for
    FOnChange: TNotifyEvent;
    { Controls observe through here, NOT through the published OnChange -- assigning that from
      a control would silently overwrite whatever the application had put in it. Same pattern
      and same reason as TTyEdit's multicast OnChange. }
    FChangeHandlers: TMethodList;
    { Name -> codepoint, sorted and case-insensitive, rebuilt lazily from FGlyphs. The published
      list has to keep its authored ORDER (it is edited in the designer and round-trips through
      the .lfm), and TStringList.Values on an unsorted list is a linear scan -- fine for the
      dozen glyphs anyone maps by hand, not fine for a bundled set of 1600 with a picker asking
      per cell. }
    FIndex: TStringList;
    FIndexValid: Boolean;
    { The merged name list GlyphNames hands out, and the two things that can invalidate it.
      Deliberately not FIndex: that is this component's OWN map, used for LOOKUP; this is
      own-plus-listers, used for DISPLAY, and a bundled pack has an empty map and a full list. }
    FNames: TStringList;
    FNamesVersion: Integer;    // the FVersion it was built at; -1 = never built
    FNamesGen: Integer;        // the TyGlyphListerGeneration it was built at
    {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
    FQtFontId: Integer;        // Qt application-font id (>=0) for removeApplicationFont
    {$ENDIF}
    { Fields must precede methods in a visibility section (FPC objfpc). This Qt field is
      compiled only on Qt5/Qt6, so Win/GTK never saw the ordering, but Qt did. }
    function GetGlyphNames: TStrings;
    procedure SetGlyphs(AValue: TStringList);
    procedure SetFontFile(const AValue: string);
    procedure SetFontFamily(const AValue: string);
    procedure LoadFontFile(const APath: string);
    procedure UnloadFontFile;
    {$IFDEF LCLGtk2}
    function SpillToTempFile(ADataPtr: Pointer; ASize: PtrUInt): string;
    {$ENDIF}
    procedure GlyphsChanged(Sender: TObject);
    procedure Changed;
    procedure RebuildIndex;
    function GetAvailable: Boolean;
  protected
    { For a descendant whose font is registered somewhere ELSE -- a bundled pack, where one
      keeper registers the bytes for every component that shares the family. Without it such a
      component would report Available = True purely because it has a family name, which is the
      exact lie Available exists to prevent. }
    procedure SetSourceState(ARequested, ALoaded: Boolean; const AError: string);
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
    { Every name this font can actually render: the keys of its own Glyphs MERGED with whatever a
      registered lister offers for FontFamily, sorted and case-insensitively de-duplicated.

      The merge is the point. A hand-mapped component answers out of Glyphs; a bundled pack maps
      nothing by hand and answers entirely through its lister; a pack with two hand-added
      overrides answers from both -- and a picker or a property editor never has to know which
      kind of font it is holding. Before this existed, everything that wanted to show a user
      their choices read Glyphs directly, which is EMPTY for a bundled pack: the Object
      Inspector's GlyphName dropdown offered nothing at all for a TTyLucideIconFont.

      OWNED BY THIS COMPONENT and rebuilt in place -- read it, do not free or modify it. A
      browser drawing two thousand cells asks per repaint, and minting a fresh list each time
      would be two thousand string allocations a frame. It is rebuilt only when Version or the
      lister generation has moved, so the steady-state cost is two integer comparisons. }
    property GlyphNames: TStrings read GetGlyphNames;
    { The same names copied into ANames (cleared first), for a caller that wants to keep, sort
      differently or filter them without holding a reference into this component. Note that
      TStrings.Assign does not carry Sorted/Duplicates across, so ANames keeps its own. }
    procedure GetGlyphNamesInto(ANames: TStrings);
    { Render AName's glyph centered in an ASizePx square, colored AColor, on a
      transparent background. Caller owns the returned bitmap. Returns an empty
      transparent bitmap when the name is unmapped or ASizePx <= 0. }
    function RenderGlyph(const AName: string; ASizePx: Integer;
      AColor: TTyColor): TBGRABitmap;
    { v3/C5. Like RenderGlyph but takes a codepoint directly (no name map). Renders it
      centered in an ASizePx square with the current FontFamily. Caller owns the bitmap. }
    function RenderCodepoint(ACodepoint: Cardinal; ASizePx: Integer;
      AColor: TTyColor): TBGRABitmap;
    { Register a font from BYTES -- the path a BUNDLED font takes, where there is no file on
      disk to point FontFile at.

      ADataPtr need only stay valid for the duration of the call: Windows, Qt and Cocoa all
      COPY the buffer (measured on Windows -- the buffer was freed and the family still
      resolved), and the GTK2 fallback writes it out before returning.

      AFamily, when given, sets FontFamily too, because a caller with embedded bytes knows the
      family name at build time and asking it to discover the name at run time would mean
      shipping an sfnt parser for no reason.

      Sets Available / LoadError exactly like FontFile does. Only ONE source at a time: this
      unregisters whatever was registered before. }
    procedure LoadFontFromMemory(ADataPtr: Pointer; ASize: PtrUInt; const AFamily: string = '');

    { Is this component in a state where a glyph can actually come out?

      It exists because the failure it reports is otherwise SILENT and looks like a different
      bug. FontFile pointing at a missing or unregisterable file leaves FontFamily set, so
      RenderGlyph passes its own guard and hands back a bitmap of tofu boxes -- indistinguishable,
      to the caller and to the user, from "that glyph name is not mapped". And it cannot be
      answered by looking at Screen.Fonts: a font registered from MEMORY (which the bundled-font
      work will use) is not enumerable at all, while rendering by name works perfectly.

      So: True when there is a family to render with and, if a FontFile was asked for, it
      registered. LoadError carries the reason when this is False. }
    property Available: Boolean read GetAvailable;
    { Why the last FontFile assignment did not take, or '' if it did. }
    property LoadError: string read FLoadError;
    { Bumped by every change that alters what a glyph looks like -- the map, the family, the
      file. A consumer that caches rendered glyphs compares this instead of re-rendering; one
      that does not can just add a handler below. }
    property Version: Integer read FVersion;
    { Observe changes without taking the published OnChange away from the application. }
    procedure AddHandlerOnChange(const AHandler: TNotifyEvent; AsFirst: Boolean = False);
    procedure RemoveHandlerOnChange(const AHandler: TNotifyEvent);
    procedure RemoveAllHandlersOfObject(AnObject: TObject);
  published
    { The font family name used to render (must match the registered/installed
      family). When FontFile is set, this is typically the file's family. }
    property FontFamily: string read FFontFamily write SetFontFamily;
    { Optional path to a .ttf loaded PRIVATE to the process (Windows). Setting it
      registers the font; clearing/reassigning unregisters the previous one. }
    property FontFile: string read FFontFile write SetFontFile;   // .ttf, loaded per-OS native
    { 'name=HEX' codepoint map, e.g. save=F0C7. }
    property Glyphs: TStringList read FGlyphs write SetGlyphs;
    { Fired after any change to the map, the family or the file -- the hook a control uses to
      repaint. Before this existed, editing Glyphs at run time left every TTyCharImage,
      TTyGlyphImageList consumer and ribbon gallery showing the previous glyph until something
      else happened to invalidate them. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { An icon font whose bytes are EMBEDDED in the program: a bundled icon pack, dropped on a
    form like any other component.

    Why a class per pack rather than one component with a "which pack" property: each pack is
    its own optional unit, and a property would have to name every pack from a single unit --
    which would link every font into every application that used any of them. A class per
    pack keeps the dependency where it belongs, gives the palette one obvious entry per pack,
    and lets two packs coexist on one form.

    The base makes sure the process registers a given family ONCE, however many components are
    dropped on however many forms. That matters twice over: registering 850KB N times is
    wasteful, and the registration must NOT belong to an instance -- freeing the first component
    would otherwise unregister the font out from under the others. The keeper lives in this
    unit and outlives every component. }
  TTyIconPackFont = class(TTyIconFont)
  protected
    { The font file's bytes. Return a cached value: this is called per instance and the string
      is reference-counted, so a cached one costs a refcount and a fresh one costs a copy. }
    class function PackData: RawByteString; virtual; abstract;
    { The sfnt family name those bytes declare. }
    class function PackFamily: string; virtual; abstract;
  public
    constructor Create(AOwner: TComponent); override;
  end;

{ Pure: parse a hex codepoint string ('F0C7', '0xF0C7', '$F0C7', 'U+F0C7'),
  returning 0 on empty/invalid. Headless-testable. }
function TyParseCodepoint(const AHex: string): Cardinal;

type
  { A name -> codepoint source that is NOT the component's own Glyphs list. AFamily is the
    icon font's FontFamily, so one registered resolver can serve several fonts and decline the
    ones it does not know. Return False to pass to the next resolver. }
  TTyGlyphResolveFunc = function(const AFamily, AName: string;
    out ACodepoint: Cardinal): Boolean;

{ Register/unregister a fallback resolver, consulted by CodepointOf when the component's own
  Glyphs map has no entry for the name.

  This is the seam a BUNDLED icon font hangs on. Without it, shipping a font means also
  shipping 1600 'name=HEX' lines for the user to paste into Glyphs -- the exact chore that
  makes the current TTyIconFont "machinery without batteries". With it, an optional unit
  registers one function in its initialization and `CharImage.GlyphName := 'house'` works with
  nothing in Glyphs at all. Registering the same function twice is a no-op; resolvers are
  consulted in registration order. }
procedure TyRegisterGlyphResolver(AFunc: TTyGlyphResolveFunc);
procedure TyUnregisterGlyphResolver(AFunc: TTyGlyphResolveFunc);
{ How many resolvers are registered -- the honest query for a test or a diagnostic. }
function TyGlyphResolverCount: Integer;

type
  { The LIST half of the resolver seam. A resolver answers "what is this name worth"; this
    answers "what names are there at all" -- the only question a picker or a design-time dropdown
    can start from, and one a resolver cannot be asked, because a lookup does not invert and a
    pack's table is private to the pack's own unit.

    AFamily is the icon font's FontFamily, so a lister declines a family it does not serve
    exactly as a resolver does. APPEND to ANames; do not clear it. The caller has already put the
    component's own Glyphs keys there, and every lister is consulted rather than just the first.
    The Boolean is a diagnostic ("I serve this family"), not a stop signal. }
  TTyGlyphListFunc = function(const AFamily: string; ANames: TStrings): Boolean;

{ Register/unregister a name lister, consulted by TTyIconFont.GlyphNames and TyGlyphNamesFor.

  Unlike a resolver, EVERY lister is consulted: a name list is additive and two packs sharing one
  family is a merge, whereas a codepoint lookup has exactly one right answer and stops at the
  first. Registering the same function twice is a no-op. }
procedure TyRegisterGlyphLister(AFunc: TTyGlyphListFunc);
procedure TyUnregisterGlyphLister(AFunc: TTyGlyphListFunc);
{ How many listers are registered -- the honest query for a test or a diagnostic. }
function TyGlyphListerCount: Integer;
{ Bumped by every registration change. It is the ONLY event a cached name list can key on: a pack
  unit's initialization may run after a component was already created, and nothing else would
  tell that component its answer had changed. }
function TyGlyphListerGeneration: Integer;

{ Every name registered listers offer for AFamily, APPENDED to ANames -- not cleared, not sorted.
  For a caller that has a family but no component (a picker opened on a family name);
  TTyIconFont.GlyphNames is the same thing merged with the component's own map. }
procedure TyGlyphNamesFor(const AFamily: string; ANames: TStrings);

{ Register AData under AFamily once per process; a second call for the same family is a no-op
  and reports the first call's outcome. The registration is held by this unit, not by any
  component, so it survives the component that triggered it. Used by TTyIconPackFont; exposed
  because a pack unit may want to register from its own initialization too. }
function TyEnsurePackFont(const AFamily: string; const AData: RawByteString;
  out AError: string): Boolean;

{ v3/C5. Parse a glyph-override token '"Family" "\e5ca"' into a font family + codepoint.
  The two double-quoted parts are family then codepoint (a leading '\' on the codepoint is
  stripped). Returns False (family/codepoint left empty/0) when either is missing/invalid. }
function TyParseGlyphToken(const AToken: string; out AFamily: string; out ACodepoint: Cardinal): Boolean;

{ v3/C5. Render a glyph-override token into an ASizePx square (family must be an available/
  registered font). Returns nil when the token does not parse; otherwise a bitmap (possibly
  blank when the family/codepoint yields no ink). Uses a process-wide per-family font cache. }
function TyRenderGlyphToken(const AToken: string; ASizePx: Integer; AColor: TTyColor): TBGRABitmap;

implementation

uses
  LazUTF8
  {$IFDEF LCLQt5}, qt5{$ENDIF}
  {$IFDEF LCLQt6}, qt6{$ENDIF}
  {$IFDEF LCLCocoa}, MacOSAll{$ENDIF}
  ;

const
  { Prefix of the GTK2 spill files, shared by the writer and the stale-file sweep. }
  TyFontSpillPrefix = 'tycontrols-iconfont-';

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
{ The MEMORY pair. Not in FPC's Windows unit either. AddFontMemResourceEx returns an opaque
  HANDLE, NOT a face count -- the count comes back through the last parameter -- and that
  handle is the only way to remove the face later, because there is no name-based removal.
  GDI copies the buffer, so the caller's bytes can go immediately (verified by freeing the
  buffer and re-resolving the family). }
function AddFontMemResourceEx(pFileView: Pointer; cjSize: DWORD; pvResrved: Pointer;
  pNumFonts: PDWORD): THandle; stdcall; external 'gdi32' name 'AddFontMemResourceEx';
function RemoveFontMemResourceEx(h: THandle): LongBool; stdcall;
  external 'gdi32' name 'RemoveFontMemResourceEx';
{$ENDIF}

var
  GResolvers: array of TTyGlyphResolveFunc;

function TyGlyphResolverCount: Integer;
begin
  Result := Length(GResolvers);
end;

var
  GListers: array of TTyGlyphListFunc;
  GListerGen: Integer = 0;

function TyGlyphListerCount: Integer;
begin
  Result := Length(GListers);
end;

function TyGlyphListerGeneration: Integer;
begin
  Result := GListerGen;
end;

procedure TyRegisterGlyphLister(AFunc: TTyGlyphListFunc);
var i: Integer;
begin
  if AFunc = nil then Exit;
  for i := 0 to High(GListers) do
    if GListers[i] = AFunc then Exit;      // idempotent: a unit may be initialized twice
  SetLength(GListers, Length(GListers) + 1);
  GListers[High(GListers)] := AFunc;
  Inc(GListerGen);
end;

procedure TyUnregisterGlyphLister(AFunc: TTyGlyphListFunc);
var i, last: Integer;
begin
  for i := 0 to High(GListers) do
    if GListers[i] = AFunc then
    begin
      last := High(GListers);
      GListers[i] := GListers[last];       // order is irrelevant: the result is a merge
      SetLength(GListers, last);
      Inc(GListerGen);
      Exit;
    end;
end;

procedure TyGlyphNamesFor(const AFamily: string; ANames: TStrings);
var i: Integer;
begin
  if (ANames = nil) or (AFamily = '') then Exit;
  for i := 0 to High(GListers) do
    GListers[i](AFamily, ANames);          { every one -- see the declaration }
end;

procedure TyRegisterGlyphResolver(AFunc: TTyGlyphResolveFunc);
var i: Integer;
begin
  if AFunc = nil then Exit;
  for i := 0 to High(GResolvers) do
    if GResolvers[i] = AFunc then Exit;      // idempotent: a unit may initialize twice
  SetLength(GResolvers, Length(GResolvers) + 1);
  GResolvers[High(GResolvers)] := AFunc;
end;

procedure TyUnregisterGlyphResolver(AFunc: TTyGlyphResolveFunc);
var i, last: Integer;
begin
  for i := 0 to High(GResolvers) do
    if GResolvers[i] = AFunc then
    begin
      last := High(GResolvers);
      GResolvers[i] := GResolvers[last];     // order only matters among the survivors
      SetLength(GResolvers, last);
      Exit;
    end;
end;

type
  { One keeper per bundled family. It is a TTyIconFont only because that is where the
    per-widgetset registration lives; nothing draws with it. }
  TPackEntry = record
    Family: string;
    Keeper: TTyIconFont;
    Loaded: Boolean;
    Error: string;
  end;

var
  GPacks: array of TPackEntry;

function TyEnsurePackFont(const AFamily: string; const AData: RawByteString;
  out AError: string): Boolean;
var
  i: Integer;
begin
  AError := '';
  if AFamily = '' then
  begin
    AError := 'a bundled font needs a family name';
    Exit(False);
  end;
  for i := 0 to High(GPacks) do
    if SameText(GPacks[i].Family, AFamily) then
    begin
      AError := GPacks[i].Error;
      Exit(GPacks[i].Loaded);
    end;
  SetLength(GPacks, Length(GPacks) + 1);
  i := High(GPacks);
  GPacks[i].Family := AFamily;
  GPacks[i].Keeper := TTyIconFont.Create(nil);
  if AData = '' then
  begin
    GPacks[i].Loaded := False;
    GPacks[i].Error := 'the bundled font decoded to nothing';
  end
  else
  begin
    GPacks[i].Keeper.LoadFontFromMemory(@AData[1], Length(AData), AFamily);
    GPacks[i].Loaded := GPacks[i].Keeper.Available;
    GPacks[i].Error := GPacks[i].Keeper.LoadError;
  end;
  AError := GPacks[i].Error;
  Result := GPacks[i].Loaded;
end;

procedure FreePacks;
var i: Integer;
begin
  for i := 0 to High(GPacks) do
    GPacks[i].Keeper.Free;
  SetLength(GPacks, 0);
end;

function ResolveViaRegistry(const AFamily, AName: string; out ACodepoint: Cardinal): Boolean;
var i: Integer;
begin
  ACodepoint := 0;
  for i := 0 to High(GResolvers) do
    if GResolvers[i](AFamily, AName, ACodepoint) and (ACodepoint > 0) then
      Exit(True);
  ACodepoint := 0;
  Result := False;
end;

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
  FGlyphs.OnChange := @GlyphsChanged;
  FIndex := TStringList.Create;
  FIndex.CaseSensitive := False;
  FIndex.Sorted := True;
  FIndex.Duplicates := dupIgnore;
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  FQtFontId := -1;
  {$ENDIF}
end;

destructor TTyIconFont.Destroy;
begin
  UnloadFontFile;
  FGlyphs.OnChange := nil;   { the list outlives nothing, but the handler must not fire
                               into a half-destroyed component while it is being freed }
  FGlyphs.Free;
  FIndex.Free;
  FNames.Free;
  FChangeHandlers.Free;
  inherited Destroy;
end;

function TTyIconFont.GetGlyphNames: TStrings;
var
  i: Integer;
  nm: string;
begin
  if FNames = nil then
  begin
    FNames := TStringList.Create;
    FNames.CaseSensitive := False;
    FNames.Duplicates := dupIgnore;
    { Sorted BEFORE anything is added, and that is not a style choice: FPC applies Duplicates
      only inside Add on an already-sorted list, while assigning Sorted := True to a populated
      one merely sorts and folds nothing. A name present in BOTH Glyphs and the lister would
      then appear twice in the picker. Building sorted costs an insert-shift per name -- a few
      milliseconds for two thousand, paid once per invalidation. }
    FNames.Sorted := True;
    FNamesVersion := -1;
  end;
  { Version covers Glyphs and FontFamily; the generation covers a pack unit whose initialization
    ran AFTER this component was created. Nothing else can change the answer. }
  if (FNamesVersion = FVersion) and (FNamesGen = TyGlyphListerGeneration) then
    Exit(FNames);
  FNames.Clear;
  for i := 0 to FGlyphs.Count - 1 do
  begin
    nm := FGlyphs.Names[i];
    { The same two rejections RebuildIndex makes -- a line with no '=' has no name, and one whose
      value will not parse is not a glyph -- so the list never offers a name CodepointOf would
      answer 0 for. }
    if (nm <> '') and (TyParseCodepoint(FGlyphs.ValueFromIndex[i]) > 0) then
      FNames.Add(nm);
  end;
  TyGlyphNamesFor(FFontFamily, FNames);
  FNamesVersion := FVersion;
  FNamesGen := TyGlyphListerGeneration;
  Result := FNames;
end;

procedure TTyIconFont.GetGlyphNamesInto(ANames: TStrings);
begin
  if ANames = nil then Exit;
  ANames.Assign(GetGlyphNames);
end;

procedure TTyIconFont.SetSourceState(ARequested, ALoaded: Boolean; const AError: string);
begin
  FSourceRequested := ARequested;
  FSourceLoaded := ALoaded;
  FLoadError := AError;
end;

{ TTyIconPackFont }

constructor TTyIconPackFont.Create(AOwner: TComponent);
var
  err: string;
  ok: Boolean;
begin
  inherited Create(AOwner);
  ok := TyEnsurePackFont(PackFamily, PackData, err);
  FontFamily := PackFamily;
  { Say what really happened. A component that merely has a family name would otherwise
    report Available = True even when the shared registration failed. }
  SetSourceState(True, ok, err);
end;

procedure TTyIconFont.GlyphsChanged(Sender: TObject);
begin
  FIndexValid := False;
  Changed;
end;

procedure TTyIconFont.Changed;
begin
  Inc(FVersion);
  if FChangeHandlers <> nil then FChangeHandlers.CallNotifyEvents(Self);
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyIconFont.AddHandlerOnChange(const AHandler: TNotifyEvent; AsFirst: Boolean);
begin
  if FChangeHandlers = nil then FChangeHandlers := TMethodList.Create;
  FChangeHandlers.Add(TMethod(AHandler), not AsFirst);
end;

procedure TTyIconFont.RemoveHandlerOnChange(const AHandler: TNotifyEvent);
begin
  if FChangeHandlers <> nil then FChangeHandlers.Remove(TMethod(AHandler));
end;

procedure TTyIconFont.RemoveAllHandlersOfObject(AnObject: TObject);
begin
  { An observer being freed must leave the list, or the next change calls a method on a dead
    object -- the same rule TTyEdit follows. (No inherited to chain: TTyComponent is not a
    TControl, so this is the whole implementation rather than an override.) }
  if FChangeHandlers <> nil then FChangeHandlers.RemoveAllMethodsOfObject(AnObject);
end;

procedure TTyIconFont.RebuildIndex;
var
  i: Integer;
  nm: string;
  cp: Cardinal;
begin
  FIndex.Clear;
  for i := 0 to FGlyphs.Count - 1 do
  begin
    nm := FGlyphs.Names[i];
    if nm = '' then Continue;
    cp := TyParseCodepoint(FGlyphs.ValueFromIndex[i]);
    if cp = 0 then Continue;               { an unparseable line is not a glyph }
    { First entry wins on a duplicate name, because that is what TStringList.Values does and
      the index must answer exactly what the list would have. }
    if FIndex.IndexOf(nm) < 0 then
      FIndex.AddObject(nm, TObject(PtrInt(cp)));
  end;
  FIndexValid := True;
end;

procedure TTyIconFont.SetGlyphs(AValue: TStringList);
begin
  FGlyphs.Assign(AValue);   { fires GlyphsChanged }
end;

procedure TTyIconFont.SetFontFamily(const AValue: string);
begin
  if FFontFamily = AValue then Exit;
  FFontFamily := AValue;
  Changed;
end;

function TTyIconFont.GetAvailable: Boolean;
begin
  Result := (FFontFamily <> '') and ((not FSourceRequested) or FSourceLoaded);
end;

{$IFDEF LCLGtk2}
function TTyIconFont.SpillToTempFile(ADataPtr: Pointer; ASize: PtrUInt): string;
{ fontconfig's three app-font entry points are ALL path-based -- there is no memory API in the
  library at all -- so on GTK2 embedded bytes have to become a file. The discipline around that
  file is the fiddly part, and every rule here exists because the obvious version is wrong:

    - the name carries the PID, because a fixed name means a second instance TRUNCATES the very
      file the first one already handed to fontconfig, and fontconfig caches on name+mtime;
    - it is NOT deleted by UnloadFont, because fontconfig cannot un-register a single file
      (only FcConfigAppFontClear, which wipes every app font) and FreeType may re-open the path
      lazily for each new face -- so the file must outlive the component;
    - it is deleted in this unit's finalization, i.e. at process exit;
    - and stale files from crashed runs are swept at startup, or every SIGKILL leaks 850KB
      permanently on a long-lived desktop session. }
var
  dir: string;
  fs: TFileStream;
begin
  Result := '';
  dir := GetEnvironmentVariable('XDG_RUNTIME_DIR');   { per-user, 0700, tmpfs, cleared at logout }
  if (dir = '') or (not DirectoryExists(dir)) then dir := GetTempDir(False);
  if (dir = '') or (not DirectoryExists(dir)) then dir := GetAppConfigDir(False);
  if (dir = '') or (not DirectoryExists(dir)) then Exit;
  Result := IncludeTrailingPathDelimiter(dir) +
    Format(TyFontSpillPrefix + '%d-%p.ttf', [GetProcessID, ADataPtr]);
  try
    fs := TFileStream.Create(Result, fmCreate);
    try
      fs.WriteBuffer(ADataPtr^, ASize);
    finally
      fs.Free;
    end;
  except
    Result := '';
  end;
end;
{$ENDIF}

procedure TTyIconFont.LoadFontFromMemory(ADataPtr: Pointer; ASize: PtrUInt;
  const AFamily: string);
{$IF DEFINED(LCLWin32) OR DEFINED(LCLQt5) OR DEFINED(LCLQt6) OR DEFINED(LCLCocoa) OR DEFINED(LCLGtk2)}
var
  {$IFDEF LCLWin32}
  nFaces: DWORD;
  {$ENDIF}
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  ba: QByteArrayH;
  {$ENDIF}
  {$IFDEF LCLCocoa}
  prov: CGDataProviderRef;
  cgf: CGFontRef;
  err: CFErrorRef;
  {$ENDIF}
{$ENDIF}
begin
  UnloadFontFile;
  FFontFile := '';                 { a byte source replaces any file source }
  FSourceRequested := True;
  FSourceLoaded := False;
  FLoadError := 'the widgetset refused to register the embedded font';
  if (ADataPtr = nil) or (ASize = 0) then
    FLoadError := 'no font data given'
  else
  begin
    { Registering a face makes a family that previously fell back suddenly REAL -- same reason
      as the file path. See TyInvalidateTextMeasureCache. }
    TyInvalidateTextMeasureCache;
    {$IFDEF LCLWin32}
    nFaces := 0;
    FMemFont := THandle(AddFontMemResourceEx(ADataPtr, DWORD(ASize), nil, @nFaces));
    if (FMemFont <> 0) and (nFaces > 0) then FSourceLoaded := True;
    {$ENDIF}
    {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
    { The SIZED QByteArray constructor is essential: font data is full of NULs, and the
      single-argument form would stop at the first one. QByteArray(data, size) deep-copies,
      so both the QByteArray and our buffer can go straight after the call. }
    ba := QByteArray_Create(PAnsiChar(ADataPtr), Integer(ASize));
    try
      FQtFontId := QFontDatabase_addApplicationFontFromData(ba);
      if FQtFontId >= 0 then FSourceLoaded := True;
    finally
      QByteArray_Destroy(ba);
    end;
    {$ENDIF}
    {$IFDEF LCLCocoa}
    prov := CGDataProviderCreateWithData(nil, ADataPtr, ASize, nil);
    if prov <> nil then
    try
      cgf := CGFontCreateWithDataProvider(prov);
      if cgf <> nil then
      try
        err := nil;
        { `<> 0`, not `if ... then`: CTFontManagerRegisterGraphicsFont returns CBool
          (CTFontManager.pas:374), and CBool is NOT Boolean -- MacTypes.pas:345/347 defines it
          as SInt32 or SInt8 depending on the target, so `if <cbool> then` fails to compile
          ("Incompatible types: got ShortInt expected Boolean", reported building on macOS).
          A Boolean() typecast would compile on whichever of the two the machine happened to
          have and break on the other, since the sizes differ; comparing against zero is right
          for both. }
        if CTFontManagerRegisterGraphicsFont(cgf, err) <> 0 then FSourceLoaded := True;
      finally
        CGFontRelease(cgf);
      end;
    finally
      CGDataProviderRelease(prov);
    end;
    {$ENDIF}
    {$IFDEF LCLGtk2}
    FTempFile := SpillToTempFile(ADataPtr, ASize);
    if FTempFile = '' then
      FLoadError := 'no writable directory for the font spill file'
    else if FcConfigAppFontAddFile(FcConfigGetCurrent, PAnsiChar(FTempFile)) <> 0 then
      FSourceLoaded := True;
    {$ENDIF}
  end;
  if FSourceLoaded then FLoadError := '';
  if AFamily <> '' then FFontFamily := AFamily;
  Changed;
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
var
  i: Integer;
begin
  if AName = '' then Exit(0);
  if not FIndexValid then RebuildIndex;
  i := FIndex.IndexOf(AName);
  if i >= 0 then
    Exit(Cardinal(PtrInt(FIndex.Objects[i])));
  { Not in this component's own map: ask the registered resolvers. That is how a bundled font
    unit supplies 1600 names without anyone pasting them into Glyphs. }
  if not ResolveViaRegistry(FFontFamily, AName, Result) then
    Result := 0;
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

function TTyIconFont.RenderCodepoint(ACodepoint: Cardinal; ASizePx: Integer;
  AColor: TTyColor): TBGRABitmap;
var
  s: string;
  sz: TSize;
begin
  if ASizePx < 1 then ASizePx := 1;
  Result := TBGRABitmap.Create(ASizePx, ASizePx, BGRAPixelTransparent);
  if (ACodepoint = 0) or (FFontFamily = '') then Exit;
  s := UnicodeToUTF8(ACodepoint);
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
  FLoadError := '';
  FSourceRequested := False;
  FSourceLoaded := False;
  if FFontFile <> '' then
    LoadFontFile(FFontFile);
  Changed;
end;

procedure TTyIconFont.LoadFontFile(const APath: string);
{$IF DEFINED(LCLWin32) OR DEFINED(LCLQt5) OR DEFINED(LCLQt6) OR DEFINED(LCLCocoa)}
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
  { Every early return here used to be silent, and a silent one is the worst outcome: the
    family stays set, so RenderGlyph sails past its own guard and paints tofu. Say what
    happened -- Available and LoadError are the only way a caller can tell "the font is not
    there" from "that glyph name is not mapped". }
  FSourceRequested := True;
  FSourceLoaded := False;
  if APath = '' then
  begin
    FLoadError := 'no font file given';
    Exit;
  end;
  if not FileExists(APath) then
  begin
    FLoadError := 'font file not found: ' + APath;
    Exit;
  end;
  FLoadError := 'the widgetset refused to register ' + APath;   { cleared on success below }
  { Registering a face makes a family that previously fell back suddenly REAL, so every
    width already measured under the fallback is now wrong. The measure memo cannot key on
    the process font registry -- it is global OS state with no version -- so the one thing
    that changes it has to say so. See TyInvalidateTextMeasureCache. }
  TyInvalidateTextMeasureCache;
  {$IFDEF LCLWin32}
  w := UTF8ToUTF16(APath);
  if AddFontResourceEx(PWideChar(w), FR_PRIVATE, nil) > 0 then
  begin
    FLoadedFile := APath;
    FLoadError := '';
    FSourceLoaded := True;
  end;
  {$ENDIF}
  {$IF DEFINED(LCLQt5) OR DEFINED(LCLQt6)}
  ws := UTF8ToUTF16(APath);                          // Qt takes a QString (PWideString)
  FQtFontId := QFontDatabase_addApplicationFont(@ws);
  if FQtFontId >= 0 then                             // font ids start at 0; -1 = failure
  begin
    FLoadedFile := APath;
    FLoadError := '';
    FSourceLoaded := True;
  end;
  {$ENDIF}
  {$IFDEF LCLCocoa}
  u8 := APath;                                        // UTF-8 filesystem path
  url := CFURLCreateFromFileSystemRepresentation(nil, CStringPtr(PAnsiChar(u8)),
    Length(u8), False);
  if url <> nil then
  try
    err := nil;
    if CTFontManagerRegisterFontsForURL(url, kCTFontManagerScopeProcess, err) <> 0 then
    begin
      FLoadedFile := APath;
      FLoadError := '';
      FSourceLoaded := True;
    end;
  finally
    CFRelease(url);
  end;
  {$ENDIF}
  {$IFDEF LCLGtk2}
  // fontconfig wants the raw UTF-8 path; new Pango contexts then resolve the family.
  if FcConfigAppFontAddFile(FcConfigGetCurrent, PAnsiChar(APath)) <> 0 then
  begin
    FLoadedFile := APath;
    FLoadError := '';
    FSourceLoaded := True;
  end;
  {$ENDIF}
end;

procedure TTyIconFont.UnloadFontFile;
{$IF DEFINED(LCLWin32) OR DEFINED(LCLCocoa)}
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
  TyInvalidateTextMeasureCache;   { same reason as LoadFontFile, in reverse }
  {$IFDEF LCLWin32}
  if FLoadedFile <> '' then
  begin
    w := UTF8ToUTF16(FLoadedFile);
    RemoveFontResourceEx(PWideChar(w), FR_PRIVATE, nil);
  end;
  { A memory-registered face has no name to remove it by -- the HANDLE is the only key, which
    is why it has to be kept. }
  if FMemFont <> 0 then
  begin
    RemoveFontMemResourceEx(FMemFont);
    FMemFont := 0;
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
  FSourceLoaded := False;
end;

{ v3/C5 glyph-override helpers }

function TyParseGlyphToken(const AToken: string; out AFamily: string; out ACodepoint: Cardinal): Boolean;
var
  i: Integer;
  inq: Boolean;
  cur, cptok: string;
  parts: array of string;
begin
  AFamily := ''; ACodepoint := 0; Result := False;
  SetLength(parts, 0);
  inq := False; cur := '';
  for i := 1 to Length(AToken) do
    if AToken[i] = '"' then
    begin
      if inq then
      begin
        SetLength(parts, Length(parts) + 1);
        parts[High(parts)] := cur;
        cur := '';
        inq := False;
      end
      else
        inq := True;
    end
    else if inq then
      cur := cur + AToken[i];
  if Length(parts) < 2 then Exit;
  AFamily := Trim(parts[0]);
  cptok := Trim(parts[1]);
  if (cptok <> '') and (cptok[1] = '\') then Delete(cptok, 1, 1);   // CSS escape \e5ca
  ACodepoint := TyParseCodepoint(cptok);
  Result := (AFamily <> '') and (ACodepoint > 0);
end;

var
  GGlyphFontCache: TStringList = nil;   // family -> owned TTyIconFont (FontFamily set)

function GlyphFontForFamily(const AFamily: string): TTyIconFont;
var idx: Integer;
begin
  if GGlyphFontCache = nil then
  begin
    GGlyphFontCache := TStringList.Create;
    GGlyphFontCache.CaseSensitive := False;
  end;
  idx := GGlyphFontCache.IndexOf(AFamily);
  if idx >= 0 then
    Exit(TTyIconFont(GGlyphFontCache.Objects[idx]));
  Result := TTyIconFont.Create(nil);
  Result.FontFamily := AFamily;
  GGlyphFontCache.AddObject(AFamily, Result);
end;

function TyRenderGlyphToken(const AToken: string; ASizePx: Integer; AColor: TTyColor): TBGRABitmap;
var family: string; cp: Cardinal;
begin
  Result := nil;
  if not TyParseGlyphToken(AToken, family, cp) then Exit;
  Result := GlyphFontForFamily(family).RenderCodepoint(cp, ASizePx, AColor);
end;

procedure FreeGlyphFontCache;
var i: Integer;
begin
  if GGlyphFontCache = nil then Exit;
  for i := 0 to GGlyphFontCache.Count - 1 do
    GGlyphFontCache.Objects[i].Free;
  FreeAndNil(GGlyphFontCache);
end;

finalization
  FreeGlyphFontCache;
  { The pack keepers outlive every component on purpose -- this is where they end. }
  FreePacks;

end.
