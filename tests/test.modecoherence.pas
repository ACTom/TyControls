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
  tyControls.BuiltinThemes;

type
  TModeCoherenceTest = class(TTestCase)
  private
    function Luma(AColor: TTyColor): Double;            // Rec.601, 0..255
    function FillLuma(const AFill: TTyFill): Double;    // gradient -> mean of end stops
    function FillIsOpaque(const AFill: TTyFill): Boolean;
  published
    procedure TestFillLumaReadsGradientStops;
    procedure TestEveryBuiltinIsCoherentInBothModes;
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
    the TyLabel floor models, so the floor transfers. }
  cSurfaceKeys: array[0..10] of string =
    ('TyForm', 'TyListBox', 'TyPanel', 'TyStatusBar', 'TyMemo', 'TyGroupBox',
     'TyToolBar', 'TyScrollBar', 'TyCoolBar', 'TyControlBar', 'TyTab');

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
  i, m, k: Integer;
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

initialization
  RegisterTest(TModeCoherenceTest);
end.
