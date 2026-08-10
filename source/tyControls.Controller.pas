unit tyControls.Controller;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, ExtCtrls,
  LazMethodList,
  tyControls.Types, tyControls.Component, tyControls.StyleModel, tyControls.Painter,
  tyControls.ThemeRegistry, tyControls.SystemTheme, tyControls.DensityPack;

type
  { P4 (D8 / §3.7). Theme follow policy. tfManual = the app drives Mode/ThemeName
    explicitly (default; manual override always wins). tfFollowSystem = the controller
    tracks the OS light/dark scheme + accent: it pulls the detected scheme into Mode and
    re-resolves the accent on RefreshFromSystem / live OS-change notifications. }
  TTyThemeFollow = (tfManual, tfFollowSystem);

  { 密度轴,与配色/皮肤正交。tdClassic = 什么都不叠(现值即经典);
    tdModern = 在当前主题之上追加现代密度包(只覆盖几何令牌)。 }
  TTyDensity = (tdClassic, tdModern);

var
  // When True (default), the first TTyStyleController created in a GUI context
  // sets TyFallbackFontName (tyControls.Painter) from the real system font, so
  // text with no themed font-family renders with a concrete name instead of ''
  // (BGRA's empty-name path drops the last glyph / mis-advances in the real GUI).
  // Headless test harnesses set this False BEFORE creating any controller, so
  // TyFallbackFontName stays '' and headless rendering remains deterministic.
  TyAutoSystemFontFallback: Boolean = True;

type
  TTyStyleController = class(TTyComponent)
  private
    FModel: TTyStyleModel;
    { False while FThemeName names a theme that could not be RESOLVED yet. A .lfm sets
      ThemeName during streaming, which runs before the form's OnCreate — so before an app
      has called TyRegisterBuiltinThemes. The name was recorded anyway, and the next attempt
      (ApplyBuiltin('default') in OnCreate, with the themes now registered) early-outed on
      "same name", leaving the model on the base layer for good: the demo's Dark button did
      nothing under `default`, and only started working once a DIFFERENT skin was picked. }
    FThemeApplied: Boolean;
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
    FDensity: TTyDensity;
    FStyleOverride: string;       // a themable tycss patch composed on top of the active theme
    procedure SetDensity(AValue: TTyDensity);
    procedure SetStyleOverride(const AValue: string);
    procedure ApplyStyleOverride; // if set, append the patch as the LAST additive layer
    { 把当前主题重新装一遍(REPLACE layer-1),然后按密度决定叠不叠包。
      换主题/换密度都走它 —— 密度包是追加层,换主题的 REPLACE 会冲掉它,
      不重叠的话「先开现代、再换皮肤」会悄悄退回经典(两边同步的老坑)。 }
    procedure ReloadThemeLayer;
    procedure ApplyDensityPack;   // 若 tdModern,追加现代包(在 layer-1 已装好之后)
    procedure SetThemeFile(const AValue: string);
    procedure SetThemeName(const AValue: string);
    function TryApplyThemeName: Boolean;   // resolve+load FThemeName; False if not registered (yet)
    procedure ThemeRegistryChanged(const AName: string);   // late-registration retry hook
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
    { Theme-system v3 · Phase A. Runtime accent picker over the model's var-override layer.
      SetAccent overrides --accent (the whole interactive palette — hover/active/focus-ring/
      selection/on-accent — re-derives from it), winning over the theme's per-mode accent
      AND the OS accent and surviving a light/dark flip; ResetAccent drops it back to the
      theme's own accent; AccentOverride is the current pick ('' = using the theme accent —
      drives a 'reset' control's enabled state). Both mutators repaint every registered
      control + fire change-listeners (Changed). The override also resets automatically on a
      theme switch (ThemeName/ThemeFile/LoadThemeCss REPLACE). }
    procedure SetAccent(const AHex: string);
    procedure ResetAccent;
    function AccentOverride: string;
    { v3/C. Resolve a named length metric from the active theme (e.g. '--checkbox-size'),
      falling back to ADefault (logical px). Controls call this instead of a hard-coded
      constant so a skin can retune their intrinsic geometry. }
    function Metric(const AName: string; ADefault: Integer): Integer;
  published
    { Version is inherited from TTyComponent — the shared non-visual base. }
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
    property Density: TTyDensity read FDensity write SetDensity default tdClassic;
    { A tycss PATCH composed on top of the active theme -- the "I just want to tweak the system
      theme a little" door, without authoring a whole theme. Full tycss WITH selectors
      (e.g. 'TyButton { --radius: 12px; } TyEdit:focus { border-color: #f00; }'), applied as the
      LAST (highest-priority) layer, so it wins over the theme and the density pack. It PERSISTS
      across theme switches and density changes: whenever layer-1 is (re)loaded, this patch is
      re-composed on top. The design-time editor is the SynEdit tycss editor (same as a control's
      StyleOverride); the default controller takes it in code. '' = no patch. }
    property StyleOverride: string read FStyleOverride write SetStyleOverride;
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

{ Density-aware default height for an interactive control, read once in its constructor.
  Classic returns the control's own classic default verbatim (byte-identical -- the token is
  NOT consulted, so mixed classic defaults stay put); modern returns --control-height, the
  density pack's roomier value (38), so an Edit/Button/ComboBox dropped under modern density
  comes up tall enough for the larger font instead of a classic-sized box. AController may be
  nil (falls back to the default controller). }
function TyDensityHeight(AController: TTyStyleController; AClassicH: Integer): Integer;

{ Density-aware value keyed on ANY length token. Classic returns AClassicVal verbatim (the
  token is NOT consulted, so a control whose classic default differs from the token's classic
  value does not drift); modern returns Metric(AToken, AClassicVal). Use this instead of a raw
  ActiveController.Metric(token, default) whenever the default is a control's OWN classic size
  that must stay byte-identical -- reading the token directly returns the token's classic value,
  not the control's, which silently shifts classic. AController may be nil. }
function TyDensityMetric(AController: TTyStyleController; AClassicVal: Integer;
  const AToken: string): Integer;

{ The theme's --line-height (TyLineHeightVar), in LOGICAL px, for laying out a caption that
  has more than one line. 0 = UNSET, which every consumer reads as "use the font's own line
  box" -- so the token moves nothing until a theme sets it, and a theme that shrinks the font
  and the leading together really does lower the height floor derived from them (a constant
  here would have frozen it). NOT density-keyed: extra leading is a typographic choice a
  theme makes outright, not a classic/modern variant of a control's own default.
  AController may be nil (falls back to the default controller). }
function TyLineHeight(AController: TTyStyleController): Integer;

implementation

var
  GDefaultController: TTyStyleController = nil;

constructor TTyStyleController.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FModel := TTyStyleModel.Create;
  FControls := TFPList.Create;
  FChangeListeners := TMethodList.Create;
  // Hear about themes registered AFTER we were handed a name (see ThemeRegistryChanged).
  TyAddThemeRegistryListener(@ThemeRegistryChanged);
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
  TyRemoveThemeRegistryListener(@ThemeRegistryChanged);
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

function TTyStyleController.TryApplyThemeName: Boolean;
var
  src, css: string;
begin
  Result := False;
  if FThemeName = '' then Exit;
  if TyResolveThemeCss(FThemeName, css) then
  begin
    // Compile-in built-in theme (registered as an inline CSS source): REPLACE layer-1
    // from the string + bump ThemeVersion. No file -> no hot-reload watch.
    FModel.LoadFromCss(css);
    ApplyDensityPack;
    ApplyStyleOverride;   // the user's patch persists across a theme switch (accent does not)
    FThemeApplied := True;
    Changed;
    Result := True;
  end
  else if TyResolveTheme(FThemeName, src) and (src <> '') and FileExists(src) then
  begin
    // §3.8 switch = REPLACE layer-1 (LoadFromFile uses AReplace=True and bumps
    // ThemeVersion). Never additive: switching themes must not stack residual rules.
    FModel.LoadFromFile(src);
    ApplyDensityPack;
    ApplyStyleOverride;
    FThemeApplied := True;
    Changed;
    Result := True;
  end;
end;

procedure TTyStyleController.ThemeRegistryChanged(const AName: string);
begin
  { A name we are still waiting for just became resolvable — apply it now. This is what
    makes a .lfm-designed ThemeName survive in a BUILT application, where streaming runs
    before the app registers its themes (see FThemeApplied). }
  if FThemeApplied or (FThemeName = '') then Exit;
  if not SameText(FThemeName, AName) then Exit;
  TryApplyThemeName;
end;

procedure TTyStyleController.SetThemeName(const AValue: string);
begin
  { Re-assigning the SAME name is a no-op only if that name was actually applied; see
    FThemeApplied. }
  if (FThemeName = AValue) and FThemeApplied then Exit;
  FThemeName := AValue;
  FThemeApplied := False;
  FThemeFile := '';   // ThemeFile/ThemeName are mutually exclusive sources for layer-1
  // Switching to a named theme drops the file source: disarm the hot-reload watch
  // (nothing to watch — FThemeFile is now empty).
  UpdateWatch;
  if AValue = '' then Exit;
  // May fail (name not registered yet) — ThemeRegistryChanged retries when it appears.
  TryApplyThemeName;
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

procedure TTyStyleController.ApplyDensityPack;
begin
  { 现代包只在 layer-1 已装好之后追加。经典什么都不做 —— 经典 = 不叠。 }
  if FDensity = tdModern then
    FModel.LoadFromCssAdditive(TyDensityModernCss);
end;

procedure TTyStyleController.ApplyStyleOverride;
begin
  { The user's tycss patch, composed on top of everything as the last additive layer -- so it
    wins over both the theme and the density pack. Applied AFTER ApplyDensityPack at every place
    layer-1 is (re)loaded, which is what makes it persist across theme/density changes. }
  if FStyleOverride <> '' then
    FModel.LoadFromCssAdditive(FStyleOverride);
end;

procedure TTyStyleController.SetStyleOverride(const AValue: string);
begin
  if FStyleOverride = AValue then Exit;
  FStyleOverride := AValue;
  { An additive layer cannot be individually unloaded, so changing the patch means rebuilding the
    whole layer chain: ReloadThemeLayer reloads layer-1 (REPLACE, clearing the old patch), then
    re-applies density and this new patch on top. }
  ReloadThemeLayer;
end;

procedure TTyStyleController.ReloadThemeLayer;
var
  src, css, keepAccent: string;
begin
  { 重装 layer-1(REPLACE),再按密度、再按 StyleOverride 叠。用于换密度 / 换 StyleOverride:
    追加层没法「卸下」,只能把底层重装一遍、再决定叠什么。
    这不是换主题(FThemeFile/FThemeName 没变),所以取色器选的强调色必须保留 —— 而 REPLACE 会清掉
    它(StyleModel:FVarOverrides.Clear),因此先存后还。 }
  keepAccent := AccentOverride;
  if FThemeFile <> '' then
  begin
    if FileExists(FThemeFile) then FModel.LoadFromFile(FThemeFile);
  end
  else if FThemeName <> '' then
  begin
    if TyResolveThemeCss(FThemeName, css) then FModel.LoadFromCss(css)
    else if TyResolveTheme(FThemeName, src) and (src <> '') and FileExists(src) then
      FModel.LoadFromFile(src);
  end
  else
    { 无主题(默认控制器就在内置 base 上):也得把用户层清成干净起点,否则改 StyleOverride 时
      旧补丁还留在 FRules 里、新补丁又追加 = 累积。 }
    FModel.LoadFromCss('');
  ApplyDensityPack;
  ApplyStyleOverride;
  if keepAccent <> '' then FModel.SetVarOverride('accent', keepAccent);   // 还原强调色
  Changed;
end;

procedure TTyStyleController.SetDensity(AValue: TTyDensity);
begin
  if FDensity = AValue then Exit;
  FDensity := AValue;
  { 换密度 = 把当前主题重装一遍再按新密度叠。tdModern 追加包,
    tdClassic 靠重装把包冲掉(追加层无法单独卸载)。 }
  ReloadThemeLayer;
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
  savedAccent: string;
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
      // A hot-reload re-applies the SAME theme with edits — NOT a switch to a different
      // theme — so the D2 reset must not fire. But LoadFromFile goes through the REPLACE
      // path (which clears overrides), so snapshot the user's accent pick and re-apply it
      // after the reload. (PollThemeFile is the one replace that isn't a theme switch.)
      savedAccent := FModel.VarOverride('accent');
      FModel.LoadFromFile(FThemeFile);
      if savedAccent <> '' then
        FModel.SetVarOverride('accent', savedAccent);
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
  ApplyDensityPack;
  ApplyStyleOverride;   // the user's patch rides on top of an explicitly loaded theme too
  // E23: snapshot the now-current file stamp so a later PollThemeFile only fires on a
  // genuine post-load change, and (re)arm the watch against this freshly loaded file.
  CaptureFileStamp;
  UpdateWatch;
  Changed;
end;

procedure TTyStyleController.LoadThemeCss(const ASource: string);
begin
  FModel.LoadFromCss(ASource);
  ApplyDensityPack;
  ApplyStyleOverride;
  Changed;
end;

procedure TTyStyleController.LoadThemeCssAdditive(const ASource: string);
begin
  FModel.LoadFromCssAdditive(ASource);
  Changed;
end;

procedure TTyStyleController.SetAccent(const AHex: string);
{ v3/A. Override --accent (whole palette re-derives) + repaint. See the interface comment. }
begin
  FModel.SetVarOverride('accent', AHex);
  Changed;
end;

procedure TTyStyleController.ResetAccent;
{ v3/A. Drop the accent override -> back to the theme's own accent + repaint. }
begin
  FModel.ClearVarOverride('accent');
  Changed;
end;

function TTyStyleController.AccentOverride: string;
{ v3/A. The current picked accent, or '' when using the theme's own accent. }
begin
  Result := FModel.VarOverride('accent');
end;

function TTyStyleController.Metric(const AName: string; ADefault: Integer): Integer;
{ v3/C. Named theme length metric, ADefault when unset. See the interface comment. }
begin
  Result := FModel.ResolveMetric(AName, ADefault);
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
  // Belt-and-suspenders behind each control's ResolveFontSize: keep the painter's zero-size text
  // fallback in step with the active theme's base font. If any draw site slips through with a
  // suppressed (0) font-size — a skin declaring its own typeKey rule drops the base font-size
  // under the all-or-nothing cascade — it then renders at the theme size, not a hardcoded default.
  TyFallbackFontSize := FModel.ResolveMetric('--font-size-base', TyFallbackFontSize);
  { af881: and drop the caption-measurement memo, in the SAME place and for the same
    reason -- this line above just moved a global the memo folds into its key, and the
    Invalidate broadcast below is the only notice a control gets that the theme changed.
    Strictly this is belt and braces: the memo keys on the resolved font tuple by value,
    so a theme that moves the font already misses. It is here so that a FUTURE theme input
    to text measurement cannot go stale merely because nobody remembered to extend the
    key -- and TyTextMeasureCacheDropsOnThemeChange pins the wiring, not the value, since
    a value assertion cannot tell "dropped and recomputed" from "never cached". }
  TyInvalidateTextMeasureCache;
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

function TyDensityMetric(AController: TTyStyleController; AClassicVal: Integer;
  const AToken: string): Integer;
var
  c: TTyStyleController;
begin
  c := AController;
  if c = nil then c := TyDefaultController;
  if c.Density = tdModern then
    Result := c.Metric(AToken, AClassicVal)
  else
    Result := AClassicVal;   { classic: keep the caller's own default, byte-identical }
end;

function TyLineHeight(AController: TTyStyleController): Integer;
var
  c: TTyStyleController;
begin
  c := AController;
  if c = nil then c := TyDefaultController;
  Result := c.Metric(TyLineHeightVar, 0);
  if Result < 0 then Result := 0;   // a negative leading is not a thing; treat it as unset
end;

function TyDensityHeight(AController: TTyStyleController; AClassicH: Integer): Integer;
begin
  Result := TyDensityMetric(AController, AClassicH, '--control-height');
end;

finalization
  FreeAndNil(GDefaultController);
end.
