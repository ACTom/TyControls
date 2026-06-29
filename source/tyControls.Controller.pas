unit tyControls.Controller;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, ExtCtrls,
  LazMethodList,
  tyControls.Types, tyControls.StyleModel, tyControls.Painter,
  tyControls.ThemeRegistry, tyControls.SystemTheme;

type
  { P4 (D8 / §3.7). Theme follow policy. tfManual = the app drives Mode/ThemeName
    explicitly (default; manual override always wins). tfFollowSystem = the controller
    tracks the OS light/dark scheme + accent: it pulls the detected scheme into Mode and
    re-resolves the accent on RefreshFromSystem / live OS-change notifications. }
  TTyThemeFollow = (tfManual, tfFollowSystem);

var
  // When True (default), the first TTyStyleController created in a GUI context
  // sets TyFallbackFontName (tyControls.Painter) from the real system font, so
  // text with no themed font-family renders with a concrete name instead of ''
  // (BGRA's empty-name path drops the last glyph / mis-advances in the real GUI).
  // Headless test harnesses set this False BEFORE creating any controller, so
  // TyFallbackFontName stays '' and headless rendering remains deterministic.
  TyAutoSystemFontFallback: Boolean = True;

type
  TTyStyleController = class(TComponent)
  private
    FModel: TTyStyleModel;
    FThemeFile: string;
    FThemeName: string;
    FControls: TFPList;
    FFollow: TTyThemeFollow;
    FHotReload: Boolean;
    FWatchTimer: TTimer;         // E23/DX: lazily created watch driver (nil until armed)
    FWatchAge: LongInt;          // last-seen FileAge of FThemeFile (-1 = unknown/missing)
    FWatchSize: Int64;           // last-seen size of FThemeFile (-1 = unknown/missing)
    FInPoll: Boolean;            // reentrancy guard for PollThemeFile / PollSystemTheme
    FLastMode: string;           // last system-followed mode ('light'/'dark'/''); poll change-anchor
    FLastAccent: string;         // last system-followed accent literal; poll change-anchor
    FChangeListeners: TMethodList;
    procedure SetThemeFile(const AValue: string);
    procedure SetThemeName(const AValue: string);
    function GetMode: string;
    procedure SetMode(const AValue: string);
    procedure SetFollow(const AValue: TTyThemeFollow);
    procedure SetHotReload(const AValue: Boolean);
    procedure UpdateWatch;                  // (re)arm or disarm the watch per state
    procedure CaptureFileStamp;             // snapshot FWatchAge/FWatchSize of ThemeFile
    procedure HandleWatchTimer(Sender: TObject);
    procedure SeedModeIfDual;   // dual-mode theme + no Mode -> adopt DefaultModeName (avoid undefined @mode vars)
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Model: TTyStyleModel read FModel;
    procedure LoadTheme(const AFileName: string);
    procedure LoadThemeCss(const ASource: string);
    procedure LoadThemeCssAdditive(const ASource: string);   // compose onto current (A6)
    procedure RegisterStyleable(AControl: TControl);
    procedure UnregisterStyleable(AControl: TControl);
    procedure Changed;
    procedure AddChangeListener(AListener: TNotifyEvent);
    procedure RemoveChangeListener(AListener: TNotifyEvent);
    { P4 (D8). Re-detect the OS scheme + accent and re-apply when following: set Mode
      from the detected scheme (tssUnknown -> keep current; never blanks the mode),
      bump the model (RebuildMergedVars re-resolves any 'system-accent'/'system-mode'
      sentinels to the freshly detected values), then Changed. Inert (no-op) under
      tfManual, so an app that drives Mode/ThemeName explicitly is never overridden.
      This is the method PollSystemTheme (and an app's manual re-sync) calls. }
    procedure RefreshFromSystem;
    { P4 (D8 / §3.7) LIVE-FOLLOW POLL — the headless-testable seam (mirrors PollThemeFile).
      Re-reads the OS mode + accent via TySystemModeHook/TySystemAccentHook; if EITHER
      changed since the last apply, re-applies (RefreshFromSystem -> SetMode / token re-resolve
      + Changed) and returns True so the caller (TTyForm's follow timer) can re-resolve its OWN
      chrome. No-op (False) under tfManual or when nothing changed, so a watch timer can call it
      every tick cheaply. WHY a poll and not a window message: LCL-Win32 consumes
      WM_SETTINGCHANGE in its callback (Application.IntfSettingsChange) and never DeliverMessage's
      it to a control's WndProc, and drops WM_DWMCOLORIZATIONCOLORCHANGED (< WM_USER) entirely —
      so an overridden WndProc can NEVER see either; polling the registry is the reliable path. }
    function PollSystemTheme: Boolean;
    { E23 (DX) hot-reload core. Re-check the watched ThemeFile's last-modified stamp
      (FileAge) + size against the snapshot taken at the last load/poll; if EITHER
      differs the file content changed, so reload it (LoadTheme -> Changed) and return
      True. Returns False when nothing changed, when HotReload is off, when no ThemeFile
      is set, or when the file is currently missing (skip silently — a save-in-progress
      may transiently unlink it; no raise). A reload that FAILS to parse is caught: the
      previous theme stays active (LoadTheme/LoadInto's fail-fast-keeps-previous contract)
      and the bad stamp is still recorded so the same broken content is not retried every
      tick (the next GOOD save differs again and reloads). Reentrancy-guarded. This is the
      fully headless-testable seam: tests call it directly instead of pumping a GUI loop. }
    function PollThemeFile: Boolean;
    function GetAbout: string;
  published
    { Read-only library version (TyVersion); the design-time editor opens the About dialog. }
    property About: string read GetAbout;
    property ThemeFile: string read FThemeFile write SetThemeFile;
    { B (Phase 2): switch theme by registered NAME. Resolves via TyResolveTheme and
      loads through the §3.8 REPLACE path (LoadFromFile -> LoadInto AReplace=True +
      bump ThemeVersion + Changed); NEVER additive, so switching A->B fully replaces
      layer-1 and leaves no residual previous theme. Mutually exclusive with ThemeFile:
      setting ThemeName clears the stored ThemeFile (and vice versa) so layer-1 has a
      single, unambiguous source. }
    property ThemeName: string read FThemeName write SetThemeName;
    { P3 (D7) single-file dual-mode. Select which '@mode NAME' block of
      the loaded theme is active (e.g. 'light'/'dark'). Delegates to Model.SetMode (re-merge
      + bump ThemeVersion) and repaints. An unknown/empty mode applies no mode overrides. }
    property Mode: string read GetMode write SetMode;
    { P4 (D8 / §3.7) follow policy. tfManual (default) = app drives Mode/ThemeName.
      Setting tfFollowSystem immediately pulls the OS scheme into Mode + re-resolves the
      accent (RefreshFromSystem); the live OS-change hook in TTyForm calls RefreshFromSystem
      while this is tfFollowSystem. A later explicit Mode/ThemeName set still wins (manual
      override), and remains until the next RefreshFromSystem. }
    property Follow: TTyThemeFollow read FFollow write SetFollow default tfManual;
    { E23 (DX) hot-reload. False (default). When True AND ThemeFile is set, the controller
      watches that file's content (last-modified stamp + size) and, on change, reloads the
      theme and repaints registered controls. The watch is driven at runtime by a lazily
      created TTimer (default 750ms) that simply calls PollThemeFile on each tick; the timer
      exists only while HotReload is True and a ThemeFile is set, and is freed otherwise.
      The TIMER firing needs a running GUI message loop; the change-detect + reload logic is
      fully exercised headless via the public PollThemeFile (drive it directly in tests). }
    property HotReload: Boolean read FHotReload write SetHotReload default False;
  end;

const
  cTyHotReloadPollMs = 750;   // watch-timer interval while HotReload is armed

function TyDefaultController: TTyStyleController;

implementation

var
  GDefaultController: TTyStyleController = nil;

function TTyStyleController.GetAbout: string;
begin
  Result := TyVersion;
end;

constructor TTyStyleController.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FModel := TTyStyleModel.Create;
  FControls := TFPList.Create;
  FChangeListeners := TMethodList.Create;
  // One-time: derive a concrete fallback font from the real system font when a
  // GUI app first creates a controller and the theme provides no font-family.
  // Only a FALLBACK (still token-driven: a themed font-family always wins). The
  // try/except keeps headless/widgetset-less contexts safe.
  if TyAutoSystemFontFallback and (TyFallbackFontName = '') then
    try
      if (Screen <> nil) and (Screen.SystemFont <> nil)
         and (Screen.SystemFont.Name <> '') then
        TyFallbackFontName := Screen.SystemFont.Name;
    except
      // ignore: leave fallback empty in non-GUI / unavailable-Screen contexts
    end;
end;

destructor TTyStyleController.Destroy;
begin
  FWatchTimer.Free;   // nil-safe; disarms the hot-reload watch
  FChangeListeners.Free;
  FControls.Free;
  FModel.Free;
  inherited Destroy;
end;

procedure TTyStyleController.SetThemeFile(const AValue: string);
begin
  if FThemeFile = AValue then Exit;
  FThemeFile := AValue;
  FThemeName := '';   // ThemeFile/ThemeName are mutually exclusive sources for layer-1
  if (AValue <> '') and FileExists(AValue) then
    LoadTheme(AValue)
  else
  begin
    // No load happened (cleared, or missing file): re-arm the watch against the new
    // target so a later appearance of the file is picked up by PollThemeFile.
    CaptureFileStamp;
    UpdateWatch;
  end;
end;

procedure TTyStyleController.SetThemeName(const AValue: string);
var
  src, css: string;
begin
  if FThemeName = AValue then Exit;
  FThemeName := AValue;
  FThemeFile := '';   // ThemeFile/ThemeName are mutually exclusive sources for layer-1
  // Switching to a named theme drops the file source: disarm the hot-reload watch
  // (nothing to watch — FThemeFile is now empty).
  UpdateWatch;
  if AValue = '' then Exit;
  if TyResolveThemeCss(AValue, css) then
  begin
    // Compile-in built-in theme (registered as an inline CSS source): REPLACE layer-1
    // from the string + bump ThemeVersion. No file -> no hot-reload watch.
    FModel.LoadFromCss(css);
    Changed;
  end
  else if TyResolveTheme(AValue, src) and (src <> '') and FileExists(src) then
  begin
    // §3.8 switch = REPLACE layer-1 (LoadFromFile uses AReplace=True and bumps
    // ThemeVersion). Never additive: switching themes must not stack residual rules.
    FModel.LoadFromFile(src);
    Changed;
  end;
end;

function TTyStyleController.GetMode: string;
begin
  Result := FModel.Mode;
end;

procedure TTyStyleController.SetMode(const AValue: string);
begin
  if FModel.Mode = AValue then Exit;
  FModel.SetMode(AValue);
  Changed;
end;

procedure TTyStyleController.SetFollow(const AValue: TTyThemeFollow);
begin
  if FFollow = AValue then Exit;
  FFollow := AValue;
  // Turning follow ON immediately syncs to the current OS state (mode + accent).
  if FFollow = tfFollowSystem then
    RefreshFromSystem;
end;

procedure TTyStyleController.RefreshFromSystem;
{ P4 (D8). Re-read the OS mode + accent and re-apply, but only while following. Detection
  goes through TySystemModeHook/TySystemAccentHook (defaulting to the live registry probe,
  overridable in tests) so this and the system-* token substitution read ONE seam. An empty
  mode ('' = unknown OS) leaves the current mode untouched so an unreadable OS never blanks
  the theme. SetMode re-merges (re-resolving any 'system-accent'/'system-mode' sentinel to
  the now-current OS values) and repaints; when the mode is unchanged we still RefreshSystemTokens
  so a pure ACCENT change (same light/dark, new accent colour) is picked up. The detected
  values are snapshotted into FLastMode/FLastAccent so PollSystemTheme can no-op until they move. }
var
  modeName, accent: string;
begin
  if FFollow <> tfFollowSystem then Exit;   // inert under manual: app override wins
  modeName := '';
  if Assigned(TySystemModeHook) then modeName := TySystemModeHook();
  accent := '';
  if Assigned(TySystemAccentHook) then accent := TySystemAccentHook();
  FLastMode := modeName;   // snapshot the RAW OS reading (so PollSystemTheme no-ops while it holds)
  FLastAccent := accent;
  // OS scheme unreadable (e.g. Linux has no registry hook -> '') AND no mode chosen yet: adopt the
  // theme's default mode so a dual-mode theme isn't left mode-less — its @mode-only vars (e.g.
  // --transparent-fill) would otherwise be UNDEFINED and blow up at resolve. A mode already in
  // effect is left untouched: an unreadable OS must never blank a deliberately-set mode.
  if (modeName = '') and (FModel.Mode = '') then
    modeName := FModel.DefaultModeName;
  if (modeName <> '') and (FModel.Mode <> modeName) then
    FModel.SetMode(modeName)   // scheme flipped -> switch @mode block (re-merges)
  else
    FModel.RefreshSystemTokens; // same/unknown scheme -> still re-resolve the accent
  Changed;
end;

function TTyStyleController.PollSystemTheme: Boolean;
{ See the interface comment. Change-aware: reads the OS mode+accent through the same hooks,
  and only does work when one of them differs from the last applied snapshot. The FInPoll
  guard is shared with PollThemeFile (both run from the same watch tick, and RefreshFromSystem's
  Changed could pump a re-entrant tick under a live loop). }
var
  modeName, accent: string;
begin
  Result := False;
  if (FFollow <> tfFollowSystem) or FInPoll then Exit;
  modeName := '';
  if Assigned(TySystemModeHook) then modeName := TySystemModeHook();
  accent := '';
  if Assigned(TySystemAccentHook) then accent := TySystemAccentHook();
  if (modeName = FLastMode) and (accent = FLastAccent) then Exit;   // OS unchanged -> nothing to do
  FInPoll := True;
  try
    RefreshFromSystem;   // applies + updates FLastMode/FLastAccent + Changed (child controls)
    Result := True;      // caller (TTyForm) re-resolves its own chrome on True
  finally
    FInPoll := False;
  end;
end;

procedure TTyStyleController.SetHotReload(const AValue: Boolean);
begin
  if FHotReload = AValue then Exit;
  FHotReload := AValue;
  // Snapshot the current file state on arming so an immediate poll won't false-fire,
  // then (re)arm or disarm the runtime watch timer.
  CaptureFileStamp;
  UpdateWatch;
end;

procedure TTyStyleController.CaptureFileStamp;
{ Snapshot the watched file's last-modified stamp + size as the change baseline.
  A missing/empty target yields (-1, -1); FileAge already returns -1 for a missing
  file, so a file that later appears differs from the baseline and triggers a load. }
var sr: TSearchRec;
begin
  FWatchAge := -1;
  FWatchSize := -1;
  if (FThemeFile = '') or not FileExists(FThemeFile) then Exit;
  FWatchAge := FileAge(FThemeFile);
  if FindFirst(FThemeFile, faAnyFile, sr) = 0 then
  begin
    FWatchSize := sr.Size;
    FindClose(sr);
  end;
end;

procedure TTyStyleController.UpdateWatch;
{ Arm the watch timer exactly when HotReload is on AND a ThemeFile is set; free it
  otherwise. The timer is the runtime-only driver — each tick calls PollThemeFile. It
  is created lazily (never in a headless test that only drives PollThemeFile directly).
  Creating it with no Owner keeps it off any form's component list; Destroy frees it. }
begin
  if FHotReload and (FThemeFile <> '') then
  begin
    if FWatchTimer = nil then
    begin
      FWatchTimer := TTimer.Create(nil);
      FWatchTimer.Enabled := False;
      FWatchTimer.Interval := cTyHotReloadPollMs;
      FWatchTimer.OnTimer := @HandleWatchTimer;
    end;
    FWatchTimer.Enabled := True;
  end
  else
    FreeAndNil(FWatchTimer);
end;

procedure TTyStyleController.HandleWatchTimer(Sender: TObject);
{ Runtime watch tick: re-check the file and reload iff it changed. The whole effect is
  in PollThemeFile so the logic stays headless-testable; this just wires it to the clock. }
begin
  PollThemeFile;
end;

function TTyStyleController.PollThemeFile: Boolean;
var
  age: LongInt;
  size: Int64;
  sr: TSearchRec;
begin
  Result := False;
  // Off / no target / reentrant -> no-op. The reentrancy guard matters because the
  // reload calls Changed (-> control Invalidate), which under a live loop could pump.
  if (not FHotReload) or (FThemeFile = '') or FInPoll then Exit;
  // Missing file: skip silently (a save may transiently unlink/rename) — no raise.
  if not FileExists(FThemeFile) then Exit;
  // Read the current stamp + size; unchanged on BOTH -> nothing to do.
  age := FileAge(FThemeFile);
  size := -1;
  if FindFirst(FThemeFile, faAnyFile, sr) = 0 then
  begin
    size := sr.Size;
    FindClose(sr);
  end;
  if (age = FWatchAge) and (size = FWatchSize) then Exit;
  // Content changed -> reload. Record the new stamp FIRST (even if the reload fails)
  // so a broken save isn't retried every tick; the next good save differs again.
  FWatchAge := age;
  FWatchSize := size;
  FInPoll := True;
  try
    try
      FModel.LoadFromFile(FThemeFile);
      // FThemeFile unchanged; named-theme already cleared when ThemeFile was set.
      Changed;
      Result := True;
    except
      on E: Exception do
        // Reload failed (bad theme): keep the previous theme (LoadFromFile fail-fast
        // already left it intact) and do not crash. Result stays False.
        ;
    end;
  finally
    FInPoll := False;
  end;
end;

procedure TTyStyleController.LoadTheme(const AFileName: string);
begin
  FModel.LoadFromFile(AFileName);
  FThemeFile := AFileName;
  FThemeName := '';   // explicit file load supersedes any named-theme selection
  // E23: snapshot the now-current file stamp so a later PollThemeFile only fires on a
  // genuine post-load change, and (re)arm the watch against this freshly loaded file.
  CaptureFileStamp;
  UpdateWatch;
  Changed;
end;

procedure TTyStyleController.LoadThemeCss(const ASource: string);
begin
  FModel.LoadFromCss(ASource);
  Changed;
end;

procedure TTyStyleController.LoadThemeCssAdditive(const ASource: string);
begin
  FModel.LoadFromCssAdditive(ASource);
  Changed;
end;

procedure TTyStyleController.RegisterStyleable(AControl: TControl);
begin
  if (AControl <> nil) and (FControls.IndexOf(AControl) < 0) then
    FControls.Add(AControl);
end;

procedure TTyStyleController.UnregisterStyleable(AControl: TControl);
var
  i: Integer;
begin
  i := FControls.IndexOf(AControl);
  if i >= 0 then
    FControls.Delete(i);
end;

procedure TTyStyleController.SeedModeIfDual;
begin
  { A dual-mode theme defines some vars ONLY inside its @mode blocks (e.g.
    --transparent-fill). If such a theme is active with NO mode selected, those vars
    are undefined and ResolveStyle raises "Undefined variable". So when mode-less and
    the theme is dual-mode (DefaultModeName <> ''), adopt the theme's default mode.
    Single-mode themes have DefaultModeName='' -> no-op; an already-set mode is left
    untouched. (The system-follow path already seeds in ApplySystemTheme; this covers
    the MANUAL ThemeName/ThemeFile/LoadThemeCss paths in one choke point.) }
  if (FModel.Mode = '') and (FModel.DefaultModeName <> '') then
    FModel.SetMode(FModel.DefaultModeName);
end;

procedure TTyStyleController.Changed;
var
  i: Integer;
begin
  SeedModeIfDual;
  for i := FControls.Count - 1 downto 0 do
    TControl(FControls[i]).Invalidate;
  FChangeListeners.CallNotifyEvents(Self);
end;

procedure TTyStyleController.AddChangeListener(AListener: TNotifyEvent);
begin
  FChangeListeners.Add(TMethod(AListener));
end;

procedure TTyStyleController.RemoveChangeListener(AListener: TNotifyEvent);
begin
  FChangeListeners.Remove(TMethod(AListener));
end;

function TyDefaultController: TTyStyleController;
begin
  if GDefaultController = nil then
    GDefaultController := TTyStyleController.Create(nil);
  Result := GDefaultController;
end;

finalization
  FreeAndNil(GDefaultController);
end.
