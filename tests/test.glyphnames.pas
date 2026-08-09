unit test.glyphnames;
{$mode objfpc}{$H+}

{ "What names does this font offer?" -- the question a picker starts from.

  WHY IT NEEDED A NEW SEAM. TTyIconFont already had a RESOLVER seam so a bundled pack could
  answer name -> codepoint without shipping two thousand 'name=HEX' lines for the user to paste
  into Glyphs. That works, and it left a hole nobody noticed: a lookup does not invert. Anything
  that wanted to SHOW a user their choices read Glyphs directly -- which a bundled pack leaves
  deliberately EMPTY -- so the Object Inspector's GlyphName dropdown offered nothing at all for a
  TTyLucideIconFont, the icon font most users will have dropped on their form. The lister is the
  list half of that seam.

  WHAT THESE PIN, beyond "it returns names":
  - the MERGE (own Glyphs + listers), because the whole point is that a caller never has to know
    which kind of font it is holding;
  - the de-duplication, which only works because the list is built Sorted from empty -- FPC
    applies Duplicates inside Add on an already-sorted list, and assigning Sorted := True to a
    populated list folds nothing;
  - the two invalidations, one of which is easy to miss: a pack unit's initialization can run
    AFTER a component was created, so a cache keyed only on the component's own Version would
    serve an empty list forever. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.IconFont;

type
  TGlyphNamesTest = class(TTestCase)
  private
    FFont: TTyIconFont;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure OwnGlyphsAreListedSortedAndWithoutTheJunkLines;
    procedure AListerAddsNamesTheComponentNeverMapped;
    procedure ListersAreAllConsultedNotJustTheFirst;
    procedure AListerDecliningAFamilyContributesNothing;
    procedure ANameInBothSourcesAppearsOnce;
    procedure TheListIsBorrowedAndStable;
    procedure MappingAGlyphInvalidatesTheList;
    procedure RegisteringAListerLaterInvalidatesTheList;
    procedure RegisteringTheSameListerTwiceIsANoOp;
    procedure GetGlyphNamesIntoCopiesRatherThanShares;
    procedure TyGlyphNamesForAppendsAndDoesNotClear;
  end;

implementation

{ Two listers over disjoint families, plus one that shares 'shared-family' with the first, so
  "every lister is consulted" and "declining by family" can be told apart. }
var
  GAlphaCalls: Integer = 0;

function AlphaLister(const AFamily: string; ANames: TStrings): Boolean;
begin
  Inc(GAlphaCalls);
  if not SameText(AFamily, 'test-alpha') and not SameText(AFamily, 'shared-family') then
    Exit(False);
  ANames.Add('alpha-one');
  ANames.Add('alpha-two');
  ANames.Add('from-glyphs');   { deliberately collides with a hand-mapped name }
  Result := True;
end;

function BetaLister(const AFamily: string; ANames: TStrings): Boolean;
begin
  if not SameText(AFamily, 'shared-family') then Exit(False);
  ANames.Add('beta-one');
  Result := True;
end;

procedure TGlyphNamesTest.SetUp;
begin
  FFont := TTyIconFont.Create(nil);
  GAlphaCalls := 0;
end;

procedure TGlyphNamesTest.TearDown;
begin
  { Listers are process-global; leaking one would leak into every later test in the suite. }
  TyUnregisterGlyphLister(@AlphaLister);
  TyUnregisterGlyphLister(@BetaLister);
  FFont.Free;
end;

procedure TGlyphNamesTest.OwnGlyphsAreListedSortedAndWithoutTheJunkLines;
begin
  FFont.Glyphs.Text := 'zeta=E001' + LineEnding + 'alpha=E002' + LineEnding
    + 'no-equals-sign' + LineEnding + 'bad-value=nothex';
  { The two rejections RebuildIndex makes, so the list can never offer a name CodepointOf would
    answer 0 for -- a picker showing an unrenderable name is worse than not showing it. }
  AssertEquals('only the two real glyphs', 2, FFont.GlyphNames.Count);
  AssertEquals('sorted', 'alpha', FFont.GlyphNames[0]);
  AssertEquals('sorted', 'zeta', FFont.GlyphNames[1]);
end;

procedure TGlyphNamesTest.AListerAddsNamesTheComponentNeverMapped;
begin
  { The headline: an EMPTY Glyphs and a full list, which is exactly a bundled pack. }
  TyRegisterGlyphLister(@AlphaLister);
  FFont.FontFamily := 'test-alpha';
  AssertEquals('nothing is mapped by hand', 0, FFont.Glyphs.Count);
  AssertTrue('yet names are offered', FFont.GlyphNames.Count >= 3);
  AssertTrue('and they are the lister''s', FFont.GlyphNames.IndexOf('alpha-one') >= 0);
end;

procedure TGlyphNamesTest.ListersAreAllConsultedNotJustTheFirst;
begin
  { A resolver stops at the first hit -- one right answer. A name list is a MERGE, so stopping
    early would silently hide a second pack that shares the family. }
  TyRegisterGlyphLister(@AlphaLister);
  TyRegisterGlyphLister(@BetaLister);
  FFont.FontFamily := 'shared-family';
  AssertTrue('the first lister contributed', FFont.GlyphNames.IndexOf('alpha-one') >= 0);
  AssertTrue('and so did the second', FFont.GlyphNames.IndexOf('beta-one') >= 0);
end;

procedure TGlyphNamesTest.AListerDecliningAFamilyContributesNothing;
begin
  TyRegisterGlyphLister(@AlphaLister);
  FFont.FontFamily := 'some-other-font';
  FFont.MapGlyph('only-mine', $E100);
  AssertEquals('just the hand-mapped one', 1, FFont.GlyphNames.Count);
  AssertEquals('only-mine', FFont.GlyphNames[0]);
  AssertTrue('the lister WAS asked -- it declined, it was not skipped', GAlphaCalls > 0);
end;

procedure TGlyphNamesTest.ANameInBothSourcesAppearsOnce;
var
  i, n: Integer;
begin
  { This only holds because the list is built Sorted from EMPTY. FPC applies Duplicates inside
    Add on an already-sorted list; setting Sorted := True on a populated one sorts and folds
    nothing, and the picker would show the name twice. }
  TyRegisterGlyphLister(@AlphaLister);
  FFont.FontFamily := 'test-alpha';
  FFont.MapGlyph('from-glyphs', $E200);
  n := 0;
  for i := 0 to FFont.GlyphNames.Count - 1 do
    if SameText(FFont.GlyphNames[i], 'from-glyphs') then Inc(n);
  AssertEquals('present exactly once', 1, n);
end;

procedure TGlyphNamesTest.TheListIsBorrowedAndStable;
var
  a, b: TStrings;
begin
  { A browser drawing two thousand cells asks per repaint. Handing back a fresh list each time
    would be two thousand string allocations a frame, so the contract is "borrowed": same object,
    caller must not free it. }
  TyRegisterGlyphLister(@AlphaLister);
  FFont.FontFamily := 'test-alpha';
  a := FFont.GlyphNames;
  b := FFont.GlyphNames;
  AssertTrue('the same borrowed list', a = b);
end;

procedure TGlyphNamesTest.MappingAGlyphInvalidatesTheList;
var
  before: Integer;
begin
  TyRegisterGlyphLister(@AlphaLister);
  FFont.FontFamily := 'test-alpha';
  before := FFont.GlyphNames.Count;
  FFont.MapGlyph('brand-new', $E300);
  AssertEquals('the cache followed Version', before + 1, FFont.GlyphNames.Count);
  AssertTrue('and the new name is there', FFont.GlyphNames.IndexOf('brand-new') >= 0);
end;

procedure TGlyphNamesTest.RegisteringAListerLaterInvalidatesTheList;
var
  before: Integer;
begin
  { The invalidation that is easy to miss. A pack unit's initialization can run AFTER a component
    exists -- the application adds `uses tyControls.Icons.Lucide` to one form. Keyed only on the
    component's own Version, the cache would serve the empty list it built at creation for the
    rest of the process. }
  FFont.FontFamily := 'test-alpha';
  before := FFont.GlyphNames.Count;
  AssertEquals('nothing yet', 0, before);
  TyRegisterGlyphLister(@AlphaLister);
  AssertTrue('the generation moved and the list rebuilt', FFont.GlyphNames.Count >= 3);
end;

procedure TGlyphNamesTest.RegisteringTheSameListerTwiceIsANoOp;
var
  n: Integer;
begin
  n := TyGlyphListerCount;
  TyRegisterGlyphLister(@AlphaLister);
  TyRegisterGlyphLister(@AlphaLister);
  AssertEquals('registered once', n + 1, TyGlyphListerCount);
  TyUnregisterGlyphLister(@AlphaLister);
  AssertEquals('and removed once', n, TyGlyphListerCount);
end;

procedure TGlyphNamesTest.GetGlyphNamesIntoCopiesRatherThanShares;
var
  mine: TStringList;
begin
  TyRegisterGlyphLister(@AlphaLister);
  FFont.FontFamily := 'test-alpha';
  mine := TStringList.Create;
  try
    FFont.GetGlyphNamesInto(mine);
    AssertEquals('copied', FFont.GlyphNames.Count, mine.Count);
    { A copy, so the caller can filter it without corrupting the component's cache. }
    mine.Clear;
    AssertTrue('the component still has its own', FFont.GlyphNames.Count >= 3);
  finally
    mine.Free;
  end;
end;

procedure TGlyphNamesTest.TyGlyphNamesForAppendsAndDoesNotClear;
var
  sl: TStringList;
begin
  { The component-free entry point: a picker opened on a family name. Appending is the contract
    because TTyIconFont.GlyphNames calls it with its OWN keys already in the list. }
  TyRegisterGlyphLister(@AlphaLister);
  sl := TStringList.Create;
  try
    sl.Add('pre-existing');
    TyGlyphNamesFor('test-alpha', sl);
    AssertEquals('the caller''s entry survived', 'pre-existing', sl[0]);
    AssertTrue('and the lister appended', sl.IndexOf('alpha-one') > 0);
  finally
    sl.Free;
  end;
end;

initialization
  RegisterTest(TGlyphNamesTest);

end.
