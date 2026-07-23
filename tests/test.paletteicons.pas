unit test.paletteicons;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, StrUtils, fpcunit, testregistry, LResources, test.designregistry;

type
  { Palette-icon guard.

    THE CONTRACT. designtime/tyControls.Design.pas includes tycontrols_icons.lrs and then calls
    RegisterComponents; the IDE looks each palette button's image up BY CLASS NAME. A class with
    no resource of that name gets a blank button — no error, no warning, just a hole in the
    palette. Every palette class therefore needs three resources (100% / 150% / 200%).

    WHY THIS FILE WAS REWRITTEN. It used to hold a hand-copied array of ~158 class names, kept in
    step by hand with two other hand-copied lists (scripts/gen-icons.ps1 $classes and the Glyphs[]
    table in tools/genicons/genicons.lpr). TTyDrawGrid and TTyStringGrid were added to the palette
    and missed by ALL THREE at once — so the array that was supposed to be the drift guard simply
    did not mention the two classes it should have caught, and this test stayed green while the
    IDE showed two blank buttons. A guard whose population is a copy of the thing it guards is not
    a guard.

    So the population is no longer written here: test.designregistry parses
    designtime/tyControls.Design.pas — the one file a control MUST be edited into to reach the
    IDE at all — and this unit checks resources against what it finds. Same construction as
    tests/test.version.pas, same parser, one copy of it.

    BOTH DIRECTIONS, because a parse that quietly shrinks reads exactly like success:
      * forward — every parsed palette class has its three PNG resources;
      * backward — every TTy* icon resource belongs to a parsed palette class. Lose a whole
        RegisterComponents group to a parser change and its icons become orphans, by name.
    (test.designregistry's own call-count check is the third link: it raises if the number of
    argument lists it matched stops equalling the number of times the source names the call.)

    RegisterNoIcon / RegisterDesignerBaseClass classes are registered but are NOT palette
    buttons; they are handled by name in their own test rather than being silently absent. }
  TPaletteIconTest = class(TTestCase)
  published
    procedure TestEveryPaletteClassHasItsIconResources;
    procedure TestNonPaletteRegistrationsHaveNoIcon;
    procedure TestNoOrphanIconResources;
  end;

implementation

const
  { HiDPI variants: '' = 100% (24px), '_150' = 150% (36px), '_200' = 200% (48px). The IDE picks
    the one matching the display scaling, so all three must exist or high-DPI users get the
    blank button instead. }
  Suffixes: array[0..2] of string = ('', '_150', '_200');
  { Only TyControls' own resources are this test's business — the LResources list is global and
    anything else linked into the runner may add to it. }
  CPrefix = 'TTy';
  CRegen = ' — add a glyph to tools/genicons/genicons.lpr and re-run scripts/gen-icons.ps1';
  { A floor, not the exact number: a hard count here would be one more thing to hand-maintain,
    which is the failure this file exists to end. It only has to be high enough that a parse
    returning nothing (or one lone group) cannot pass. }
  CMinPaletteClasses = 100;

procedure TPaletteIconTest.TestEveryPaletteClassHasItsIconResources;
var
  classes, bad: TStringList;
  i, j: Integer;
  nm: string;
  res: TLResource;
begin
  classes := TStringList.Create;
  bad := TStringList.Create;
  try
    CollectPaletteClassNames(classes);
    AssertTrue('the parse of designtime/tyControls.Design.pas returned only '
      + IntToStr(classes.Count) + ' palette classes — it has drifted, and the sweep below would'
      + ' silently be checking almost nothing', classes.Count >= CMinPaletteClasses);
    for i := 0 to classes.Count - 1 do
      for j := 0 to High(Suffixes) do
      begin
        nm := classes[i] + Suffixes[j];
        res := LazarusResources.Find(nm);
        if res = nil then
          bad.Add(nm + ': no icon resource — the IDE would show a blank palette button' + CRegen)
        else if res.ValueType <> 'PNG' then
          bad.Add(nm + ': icon resource is ' + res.ValueType + ', expected PNG');
      end;
    AssertEquals('classes registered with RegisterComponents whose palette icon is missing from'
      + ' designtime/tycontrols_icons.lrs:' + LineEnding + bad.Text, 0, bad.Count);
  finally
    bad.Free;
    classes.Free;
  end;
end;

{ The two icon-less registration shapes, named rather than merely absent.

  TTyGridCell and TTyFormSurface are registered with RegisterNoIcon on purpose: they are created
  by their owner (the grid, the form template), never dragged, so they have no palette button and
  must have no icon. TTyForm / TTyDialog are designer BASE classes, likewise not droppable.
  Asserting the absence keeps the exemption honest in both directions: put one of them on the
  palette and it moves into the parse above, which then demands its icon; generate an icon for
  one of them and this test says so instead of leaving a resource nobody can explain. }
procedure TPaletteIconTest.TestNonPaletteRegistrationsHaveNoIcon;
var
  nonPalette, palette, bad: TStringList;
  i, j: Integer;
  nm: string;
begin
  nonPalette := TStringList.Create;
  palette := TStringList.Create;
  bad := TStringList.Create;
  try
    CollectNoIconClassNames(nonPalette);
    AssertTrue('the parse found no RegisterNoIcon registrations — TTyGridCell and TTyFormSurface'
      + ' are registered that way, so the parser has drifted', nonPalette.Count > 0);
    CollectDesignerBaseClassNames(nonPalette);
    CollectPaletteClassNames(palette);

    for i := 0 to nonPalette.Count - 1 do
    begin
      if palette.IndexOf(nonPalette[i]) >= 0 then
      begin
        { Not a failure of the icon set — a change of category. Say so, because the right fix is
          to let the test above cover it, not to add an exception here. }
        bad.Add(nonPalette[i] + ': registered BOTH as a palette component and as an icon-less'
          + ' class — decide which it is');
        Continue;
      end;
      for j := 0 to High(Suffixes) do
      begin
        nm := nonPalette[i] + Suffixes[j];
        if LazarusResources.Find(nm) <> nil then
          bad.Add(nm + ': has a palette icon, but the class is not on the palette (RegisterNoIcon'
            + '/RegisterDesignerBaseClass) — drop it from the generator');
      end;
    end;
    AssertEquals('icon-less registrations that are not icon-less:' + LineEnding + bad.Text,
      0, bad.Count);
  finally
    bad.Free;
    palette.Free;
    nonPalette.Free;
  end;
end;

{ The backward direction. Every generated icon must answer to a palette registration; an orphan
  means either the .lrs still carries a renamed/withdrawn class (regenerate) or — the reason this
  direction exists — the parse has stopped seeing a registration that is still there, in which
  case the forward sweep above has silently narrowed and would not have told anyone. }
procedure TPaletteIconTest.TestNoOrphanIconResources;
var
  palette, bad: TStringList;
  i, j: Integer;
  nm, base: string;
  matched: Boolean;
begin
  palette := TStringList.Create;
  bad := TStringList.Create;
  try
    CollectPaletteClassNames(palette);
    for i := 0 to LazarusResources.Count - 1 do
    begin
      nm := LazarusResources.Items[i].Name;
      if not AnsiStartsStr(CPrefix, nm) then Continue;
      { strip the HiDPI suffix, if any; an UNKNOWN suffix must not be stripped — it is itself a
        finding (the IDE would never look that name up) }
      base := nm;
      for j := 0 to High(Suffixes) do
        if (Suffixes[j] <> '') and AnsiEndsStr(Suffixes[j], nm) then
        begin
          base := Copy(nm, 1, Length(nm) - Length(Suffixes[j]));
          Break;
        end;
      matched := palette.IndexOf(base) >= 0;
      if not matched then
        bad.Add(nm + ': icon resource with no RegisterComponents entry for ' + base);
    end;
    AssertEquals('orphan palette icons in designtime/tycontrols_icons.lrs — either the class left'
      + ' the palette and the icon was never regenerated, or the parse of'
      + ' designtime/tyControls.Design.pas no longer finds the group it belongs to (in which case'
      + ' the coverage of this whole unit has shrunk):' + LineEnding + bad.Text, 0, bad.Count);
  finally
    bad.Free;
    palette.Free;
  end;
end;

initialization
  {$I ../designtime/tycontrols_icons.lrs}
  RegisterTest(TPaletteIconTest);
end.
