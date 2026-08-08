unit test.modecoherence;
{ Mode coherence: one window, one luminance class.

  A structural skin (themes/builtin/*.tycss) restyles only its OWN typeKeys; every other
  control falls back to the BASE layer, whose three seeds (--surface/--on-surface/--border,
  TyBuiltinBaseModeCss) swap per @mode. A dual-mode skin whose @mode dark block does not
  actually go dark therefore renders a MIXED window in dark mode: its own keys stay light
  while every base-fallback surface (list box, panel, status bar, memo, …) turns dark — the
  reported aero bug (light form + buttons around a black list box, dark-blue ink on black
  panels), and classic's identical latent one.

  The guard resolves a representative set of window SURFACES for every built-in theme in
  BOTH modes and asserts they all land in one luminance class — all-light or all-dark,
  never mixed. All-light in dark mode is allowed: a skin may document dark as a no-op
  (classic pins the base seeds to their light values), but it must then be a no-op for the
  WHOLE window, not half of it.

  A second assertion pins the user-visible symptom directly: the theme's window ink
  (TyLabel's resolved colour — what captions on panels are drawn with) must read against
  every one of those surfaces (Rec.601 luma delta >= 60, the contrast floor
  test.builtinthemes already uses for the title bar).

  TyForm backgrounds may be gradients (aero's steel-glass wash), so luminance comes from
  FillLuma, which reads a gradient's END STOPS (GradFrom/GradTo mean, the BarLuma
  precedent) — never TTyFill.Color, which a gradient leaves unset. FillLuma has its own
  test: a helper that mis-reads gradients would silently turn the whole guard vacuous. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller,
  tyControls.BuiltinThemes, tyControls.ToolBar;

type
  TModeCoherenceTest = class(TTestCase)
  private
    function Luma(AColor: TTyColor): Double;            // Rec.601, 0..255
    function FillLuma(const AFill: TTyFill): Double;    // gradient -> mean of end stops
    function FillIsOpaque(const AFill: TTyFill): Boolean;
    procedure FillMeanRGB(const AFill: TTyFill; out R, G, B: Double);
    function SameFill(const A, B: TTyFill): Boolean;
  published
    procedure TestFillLumaReadsGradientStops;
    procedure TestEveryBuiltinIsCoherentInBothModes;
    procedure TestNoOpDarkThemesAreModeInvariant;
    procedure TestToolRuleFallbackIsVisibleInBothModes;
  end;

implementation

const
  { The probe set: the form itself plus surfaces a skin typically does NOT restyle, so they
    exercise the base-layer fallback (TyListBox and TyPanel are the two the bug was
    reported on). TyGroupBox rides along: its base fill is transparent (alpha 0), so it
    only contributes where a skin paints it — the transparent-skip below must hold.
    TyToolBar and TyScrollBar complete the chrome-bar family TyStatusBar opened: all three
    fill from ONE token (--chrome-bar-bg), and a skin that retunes it in a plain :root —
    instead of per-@mode — drags its light chrome into dark mode (the aero chrome fix sets
    it per-mode; this sweep is what makes that shape mandatory). The ink floor applies to
    them like any surface: labels and captions do get parented to tool bars.
    TyCoolBar and TyControlBar joined when aero forked them from TyPanel (the first
    ALIAS_EXEMPTIONS rows in test.themes): once a key stops being a donor clone it can
    carry its own mistakes, and a rebar fill in a plain :root would drag light chrome
    into dark exactly like the bars above. In every non-diverged theme they resolve as
    TyPanel and the check is a free duplicate. TyTab rides for the same reason: aero
    re-seats the strip's rest state on the chrome family per-mode (--surface-tab-rest),
    and this sweep is what makes per-mode the mandatory shape for it. Labels are not
    parented to tab headers, but the tab's OWN rest ink is the same --on-surface seed
    the TyLabel floor models, so the floor transfers.
    TyScrollContent is the scrolling containers' windowed VIEWPORT (the child that clips
    the content inside TTyScrollBox / TTyScrollPanel). It joined when the aero-dark residue
    pass found the key had NO rule in ANY layer: TTyScrollContent.Paint fills its resolved
    background and nothing else, behind `if tpBackground in S.Present`, so an absent resolve
    left the widgetset's erase colour on screen. ApplyChromeTheme re-seeds that colour only
    for SOLID form backgrounds, so on a gradient-form skin (aero) it stayed a stale light
    grey — a LIGHT well lining a dark window. It is ALSO in cMustPaintKeys below, because
    for this key "absent" is precisely the bug and the transparent-skip below would wave it
    straight through.
    Keys the same residue pass examined and deliberately did NOT add, each because no
    resolve-level assertion can see the defect:
    - TyGridCell: TTyGridPanel's windowed layout cells borrow TTyGrid's DATA-cell key
      (tyControls.GridPanel.pas, TTyGridCell.GetStyleTypeKey -> 'TyGridCell'), whose base
      `background: none` is correct BY DESIGN for the grid body. But TTyGridCell.Paint is an
      EMPTY method — it never resolves or fills anything — so no value written under this
      key, or any other, would change one pixel. The light patch is purely the erase colour
      of a windowed control that declines to paint. Control-side fix, two options: give the
      layout cell its own typeKey (the borrowed-typeKey rule), or have its Paint fill the
      parent's background the way TTyGridPanel already does.
    - TyBevel: its resolved background is the shared container surface and is already
      mode-coherent; the control never fills it. The bright dark-mode rails come from
      tyControls.Bevel.pas:197, `TyBevelLighten(baseC, 0.55)`, which blends the border
      colour 55% toward pure WHITE regardless of mode. Mode-blind derivation inside the
      control; invisible to any resolve sweep. Fix belongs in that derivation. }
  cSurfaceKeys: array[0..11] of string =
    ('TyForm', 'TyListBox', 'TyPanel', 'TyStatusBar', 'TyMemo', 'TyGroupBox',
     'TyToolBar', 'TyScrollBar', 'TyCoolBar', 'TyControlBar', 'TyTab',
     'TyScrollContent');

  { Keys whose control paints NOTHING except its resolved background fill. For these an
    absent or transparent resolve does not mean "styled transparent", it means the pixels
    on screen are the host's unthemed erase colour — and that colour is re-seeded only for
    solid form backgrounds, so a gradient-form skin leaves it a stale light grey. The
    transparent-skip in the sweep below is a deliberate lenience for keys that MAY legally
    be see-through (TyGroupBox); for these keys the same lenience would hide exactly the
    defect being guarded, so they carry an opacity floor instead. }
  cMustPaintKeys: array[0..0] of string = ('TyScrollContent');

  { Light/dark class boundary on the 0..255 luma axis. Every shipped surface sits well
    clear of it (light skins >= ~190, dark ones <= ~70); a MIXED window straddles it by
    ~200, so the exact cut is not delicate. }
  cClassBoundary = 128.0;

  { The floor test.builtinthemes.TestOnTitleBarInkReadsOnTheBar already enforces. }
  cInkContrastFloor = 60.0;

function TModeCoherenceTest.Luma(AColor: TTyColor): Double;
begin
  Result := 0.299 * TyRedOf(AColor) + 0.587 * TyGreenOf(AColor)
          + 0.114 * TyBlueOf(AColor);
end;

function TModeCoherenceTest.FillLuma(const AFill: TTyFill): Double;
{ A gradient's TTyFill.Color is NOT the paint — the painter uses GradFrom/GradTo (the
  2-stop fast path; for >2 stops they are kept equal to stops[0]/[last]). Judge a gradient
  by the mean of its ends, a solid by its colour. }
begin
  if AFill.Kind = tfkLinearGradient then
    Result := (Luma(AFill.GradFrom) + Luma(AFill.GradTo)) / 2
  else
    Result := Luma(AFill.Color);
end;

procedure TModeCoherenceTest.FillMeanRGB(const AFill: TTyFill; out R, G, B: Double);
{ The fill's paint as a single RGB triple, on the same reading as FillLuma: a gradient is
  judged by the mean of its end stops, a solid by its colour. Needed as CHANNELS (not luma)
  because the tool-rule check composites an alpha ink over this ground before measuring. }
begin
  if AFill.Kind = tfkLinearGradient then
  begin
    R := (TyRedOf(AFill.GradFrom)   + TyRedOf(AFill.GradTo))   / 2;
    G := (TyGreenOf(AFill.GradFrom) + TyGreenOf(AFill.GradTo)) / 2;
    B := (TyBlueOf(AFill.GradFrom)  + TyBlueOf(AFill.GradTo))  / 2;
  end
  else
  begin
    R := TyRedOf(AFill.Color); G := TyGreenOf(AFill.Color); B := TyBlueOf(AFill.Color);
  end;
end;

function TModeCoherenceTest.SameFill(const A, B: TTyFill): Boolean;
{ Whole-fill equality. Compares the gradient stops as well as Color, because a theme could
  legally move a key from a solid to a gradient and comparing Color alone would call that
  "unchanged" -- the same blind spot FillLuma exists to avoid. }
begin
  Result := (A.Kind = B.Kind) and (A.Color = B.Color)
        and (A.GradFrom = B.GradFrom) and (A.GradTo = B.GradTo);
end;

function TModeCoherenceTest.FillIsOpaque(const AFill: TTyFill): Boolean;
{ Only solid and gradient fills have a luminance to class. A transparent fill (alpha 0,
  e.g. the base TyGroupBox) shows the surface behind it and inherits its class. }
begin
  case AFill.Kind of
    tfkSolid:          Result := TyAlphaOf(AFill.Color) > 0;
    tfkLinearGradient: Result := (TyAlphaOf(AFill.GradFrom) > 0)
                              or (TyAlphaOf(AFill.GradTo) > 0);
  else
    Result := False;   // none / image / nine-slice: no single luminance
  end;
end;

procedure TModeCoherenceTest.TestFillLumaReadsGradientStops;
{ The helper IS the guard's eyes: if it read TTyFill.Color for a gradient (which a
  gradient leaves at its zero default), every gradient form background would class as
  luma 0 = dark, and the coherence test would pass or fail on garbage. Pin the contract
  with fills built by hand, including a deliberately misleading Color. }
var f: TTyFill;
begin
  FillChar(f, SizeOf(f), 0);
  f.Kind := tfkSolid;
  f.Color := TyRGB(255, 255, 255);
  AssertEquals('solid white -> 255', 255.0, FillLuma(f), 0.01);
  f.Color := TyRGB(0, 0, 0);
  AssertEquals('solid black -> 0', 0.0, FillLuma(f), 0.01);

  FillChar(f, SizeOf(f), 0);
  f.Kind := tfkLinearGradient;
  f.GradFrom := TyRGB(0, 0, 0);
  f.GradTo := TyRGB(255, 255, 255);
  AssertEquals('black->white gradient -> mean 127.5', 127.5, FillLuma(f), 0.01);

  { The trap: a white gradient whose (unused) Color field is black. A helper that falls
    back to Color for gradients returns 0 here and the whole guard goes blind. }
  f.GradFrom := TyRGB(255, 255, 255);
  f.GradTo := TyRGB(255, 255, 255);
  f.Color := TyRGB(0, 0, 0);
  AssertEquals('gradient reads its stops, never Color', 255.0, FillLuma(f), 0.01);

  { And opacity classing: a transparent solid must be skipped, an opaque one kept. }
  FillChar(f, SizeOf(f), 0);
  f.Kind := tfkSolid;
  f.Color := TyRGBA(255, 255, 255, 0);
  AssertFalse('alpha-0 solid is not a classable surface', FillIsOpaque(f));
  f.Color := TyRGB(255, 255, 255);
  AssertTrue('opaque solid is classable', FillIsOpaque(f));
end;

procedure TModeCoherenceTest.TestEveryBuiltinIsCoherentInBothModes;
var
  c: TTyStyleController;
  names: TStringArray;
  i, m, k, mp: Integer;
  mode, detail: string;
  s, lbl: TTyStyleSet;
  lumas: array[0..High(cSurfaceKeys)] of Double;
  opaque: array[0..High(cSurfaceKeys)] of Boolean;
  measured: Integer;
  sawLight, sawDark: Boolean;
  inkLuma: Double;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    AssertTrue('there are built-in themes to check', Length(names) > 0);
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;

        measured := 0;
        sawLight := False; sawDark := False;
        detail := '';
        for k := 0 to High(cSurfaceKeys) do
        begin
          s := c.Model.ResolveStyle(cSurfaceKeys[k], '', []);
          opaque[k] := (tpBackground in s.Present) and FillIsOpaque(s.Background);
          { The opacity floor (cMustPaintKeys). For a control that paints its background
            and nothing else, an absent/transparent resolve IS the light-patch defect —
            and skipping it below is exactly how the defect stayed invisible to this
            sweep for as long as it did. Fail loudly, before the skip. }
          for mp := 0 to High(cMustPaintKeys) do
            if cSurfaceKeys[k] = cMustPaintKeys[mp] then
              AssertTrue(Format('%s/%s: %s must resolve an OPAQUE background — its control '
                + 'paints nothing else, so what shows instead is the host''s unthemed erase '
                + 'colour (a light patch in dark mode)', [names[i], mode, cSurfaceKeys[k]]),
                opaque[k]);
          if not opaque[k] then Continue;
          lumas[k] := FillLuma(s.Background);
          Inc(measured);
          if lumas[k] < cClassBoundary then sawDark := True else sawLight := True;
          detail := detail + Format('%s=%.0f ', [cSurfaceKeys[k], lumas[k]]);
        end;

        { A guard that measured nothing guards nothing. The form alone plus the two
          reported surfaces are always opaque in every shipped theme. }
        AssertTrue(Format('%s/%s: at least 3 opaque surfaces to judge (got %d)',
          [names[i], mode, measured]), measured >= 3);

        AssertFalse(Format('%s/%s: MIXED window — light and dark surfaces coexist '
          + '(luma 0..255, boundary %.0f): %s', [names[i], mode, cClassBoundary, detail]),
          sawLight and sawDark);

        { The symptom the user actually saw: caption ink unreadable on a fallback panel.
          The window ink (TyLabel) must read on every opaque surface of the window. }
        lbl := c.Model.ResolveStyle('TyLabel', '', []);
        AssertTrue(Format('%s/%s: the window ink (TyLabel) exists', [names[i], mode]),
          (tpTextColor in lbl.Present) and (TyAlphaOf(lbl.TextColor) > 0));
        inkLuma := Luma(lbl.TextColor);
        for k := 0 to High(cSurfaceKeys) do
          if opaque[k] then
            AssertTrue(Format('%s/%s: window ink (luma %.0f) is unreadable on %s '
              + '(luma %.0f, delta %.0f < %.0f)',
              [names[i], mode, inkLuma, cSurfaceKeys[k], lumas[k],
               Abs(inkLuma - lumas[k]), cInkContrastFloor]),
              Abs(inkLuma - lumas[k]) >= cInkContrastFloor);
      end;
  finally
    c.Free;
  end;
end;


procedure TModeCoherenceTest.TestNoOpDarkThemesAreModeInvariant;
{ The OTHER half of the dark contract, and the half that had no guard.

  docs/themes.md gives a skin exactly two legal answers to @mode dark: a real dark palette,
  or a WHOLE-WINDOW no-op that pins the base seeds back to their light values. The sweep
  above polices the first one. For a no-op theme all it confirms is that the surfaces stayed
  light -- and that is not the same thing as the no-op being complete.

  xp is what a PARTIAL no-op looks like. The base swaps THREE seeds per mode
  (--surface / --on-surface / --border); xp pinned the first two and left the third to fall
  through, so its dark mode drew the base's dark #3F3F46 hairlines, fallback frames and
  scroll thumb against its own unchanged Luna beige chrome -- 154 luma of contrast where the
  light mode has 6. Every BACKGROUND it resolved was correctly light, so the luminance sweep
  waved it past. A border is not a surface and was never measured.

  This assertion needs NO threshold, which is exactly why it is the one worth having: if a
  theme's dark surfaces come out light it has declared dark a no-op, and a no-op must be
  total. So resolve both modes and require equality key for key -- background AND border AND
  ink, the three things a seed feeds. A theme that means to go dark never reaches the
  comparison, and a theme that means to do nothing has nothing to explain.

  Failure prints the field that moved, because "xp/dark differs" without the field is half
  an hour of bisecting a stylesheet. }
var
  c: TTyStyleController;
  names: TStringArray;
  i, k: Integer;
  lightSet, darkSet: array[0..High(cSurfaceKeys)] of TTyStyleSet;
  s: TTyStyleSet;
  darkIsLight: Boolean;
  measured, noOpThemes: Integer;
begin
  TyRegisterBuiltinThemes;
  noOpThemes := 0;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    AssertTrue('there are built-in themes to check', Length(names) > 0);
    for i := 0 to High(names) do
    begin
      c.ThemeName := names[i];

      c.Mode := 'light';
      for k := 0 to High(cSurfaceKeys) do
        lightSet[k] := c.Model.ResolveStyle(cSurfaceKeys[k], '', []);

      c.Mode := 'dark';
      darkIsLight := True;
      measured := 0;
      for k := 0 to High(cSurfaceKeys) do
      begin
        s := c.Model.ResolveStyle(cSurfaceKeys[k], '', []);
        darkSet[k] := s;
        if (tpBackground in s.Present) and FillIsOpaque(s.Background) then
        begin
          Inc(measured);
          if FillLuma(s.Background) < cClassBoundary then darkIsLight := False;
        end;
      end;

      { Only a theme that actually rendered a LIGHT window in dark mode has taken the no-op
        branch. `measured` guards against calling a theme that resolved nothing "light". }
      if (measured < 3) or (not darkIsLight) then Continue;
      Inc(noOpThemes);

      for k := 0 to High(cSurfaceKeys) do
      begin
        AssertTrue(Format('%s: dark is a whole-window NO-OP (its surfaces stayed light), so '
          + '%s must resolve the SAME background in both modes -- a seed left unpinned falls '
          + 'through to the base''s dark value', [names[i], cSurfaceKeys[k]]),
          SameFill(lightSet[k].Background, darkSet[k].Background));
        AssertEquals(Format('%s: no-op dark, but %s''s BORDER moved between modes -- this is '
          + 'the xp defect: --border left out of the @mode dark pin, so a dark hairline is '
          + 'drawn on light chrome', [names[i], cSurfaceKeys[k]]),
          Int64(lightSet[k].BorderColor), Int64(darkSet[k].BorderColor));
        AssertEquals(Format('%s: no-op dark, but %s''s INK moved between modes',
          [names[i], cSurfaceKeys[k]]),
          Int64(lightSet[k].TextColor), Int64(darkSet[k].TextColor));
      end;
    end;

    { A guard that never took its branch guards nothing. classic, showcase and xp are the
      three shipped no-op themes; if a future retune gives them all real dark palettes this
      number must be revisited deliberately, not silently. }
    AssertTrue(Format('at least 2 built-ins must exercise the no-op branch (got %d) -- with '
      + 'none, this test is vacuous', [noOpThemes]), noOpThemes >= 2);
  finally
    c.Free;
  end;
end;

procedure TModeCoherenceTest.TestToolRuleFallbackIsVisibleInBothModes;
{ TyToolRuleInk's fallback had exactly one pixel probe behind it, against a synthetic LIGHT
  theme. The dimming factor (--tool-rule-alpha, now a real token in light.tycss rather than
  a bare constant in control code) was chosen because 50/255 of the text colour over a white
  surface lands within two levels of --border. Nobody had looked at what the same fraction
  does on a DARK skin, where the ink is light and the ground is dark -- it could have read
  far too bright, or vanished.

  It does neither, and the reason is structural: the ink is the mode's OWN text colour and
  the ground is the mode's OWN chrome, so the pair swaps together and the composite lands a
  similar distance off the bar in both modes. Measured over all 17 built-ins x 2 modes, the
  12 whose ghost ink is --on-surface sit 36..50 luma off the bar face in light AND in dark.

  Four skins come in thin, and they are thin for a reason that is NOT the mode: their ghost
  ink is a mid-luma ACCENT that they do not lift for dark, so the ink drifts toward the dark
  ground. office 29 -> 9, macos 24 -> 12, aero 21 -> 15, ubuntu 25 -> 18. A per-mode GLOBAL
  alpha cannot fix them: office would need ~161, which would take the base theme's dark
  hairline from 40 to 128 -- three times the weight of a real border. The remedy is per-skin,
  and the token is now in the theme layer precisely so those four can take it.

  So the floor here is deliberately LOW. It is not a legibility certificate -- it is the
  guard that the token still reaches the paint at a usable strength: a zeroed, mistyped or
  unparseable --tool-rule-alpha (the new failure mode that shipping a token creates) drops
  every theme to ~0..2 and dies here. The measured minimum today is 9 (office/dark), so the
  floor has 3 luma of headroom and no more; a skin that retunes into that gap is meant to
  fail and be looked at. }
const
  cRuleVisibilityFloor = 6.0;
var
  c: TTyStyleController;
  names: TStringArray;
  i, m, alpha: Integer;
  mode: string;
  ghost, bar: TTyStyleSet;
  ink: TTyColor;
  a, barR, barG, barB, cr, cg, cb, compLuma, barLuma: Double;
  exercised: Integer;
begin
  TyRegisterBuiltinThemes;
  exercised := 0;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    AssertTrue('there are built-in themes to check', Length(names) > 0);
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;

        ghost := c.Model.ResolveStyle('TyButton', 'ghost', []);
        bar := c.Model.ResolveStyle('TyToolBar', '', []);

        { Only the FALLBACK branch is under test. A skin whose ghost keeps an opaque border
          (bootstrap, win11) draws the rule in that border and is covered by the golden. }
        if TyAlphaOf(ghost.BorderColor) > 0 then Continue;
        if not ((tpBackground in bar.Present) and FillIsOpaque(bar.Background)) then Continue;

        { The metric comes from the THEME, exactly as the control reads it -- so a skin that
          retunes the token is measured at ITS value, not at the base default. }
        alpha := c.Metric(TyToolRuleAlphaVar, TyToolRuleGhostAlpha);
        ink := TyToolRuleInk(ghost, alpha);
        a := TyAlphaOf(ink) / 255;
        FillMeanRGB(bar.Background, barR, barG, barB);
        cr := barR + (TyRedOf(ink)   - barR) * a;
        cg := barG + (TyGreenOf(ink) - barG) * a;
        cb := barB + (TyBlueOf(ink)  - barB) * a;
        compLuma := 0.299 * cr + 0.587 * cg + 0.114 * cb;
        barLuma := FillLuma(bar.Background);
        Inc(exercised);

        AssertTrue(Format('%s/%s: the fallback tool rule is invisible on its own bar -- '
          + 'composited luma %.0f against bar %.0f (delta %.0f < %.0f) at alpha %d. A '
          + 'tbsDropDown then looks identical to a tbsButtonDrop, which is the bug '
          + 'TyToolRuleInk exists to prevent.',
          [names[i], mode, compLuma, barLuma, Abs(compLuma - barLuma),
           cRuleVisibilityFloor, alpha]),
          Abs(compLuma - barLuma) >= cRuleVisibilityFloor);
      end;

    { The ghost variant is what a FLAT bar (the default) hands every tool, so most themes
      must reach the fallback. If a refactor made ghost borders opaque everywhere this test
      would silently stop testing anything. }
    AssertTrue(Format('the fallback branch must actually be exercised (got %d theme/mode '
      + 'pairs) -- a skip-everything sweep proves nothing', [exercised]), exercised >= 20);
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TModeCoherenceTest);
end.
