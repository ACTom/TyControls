unit test.iconfont;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, LazUTF8, tyControls.IconFont;

type
  TIconFontTest = class(TTestCase)
  published
    procedure ParseBareHex;
    procedure ParsePrefixes;
    procedure ParseInvalid;
    procedure ParseOutOfRange;
    procedure ParseRejectsSurrogate;
    procedure MapAndLookup;
    procedure GlyphTextMatchesUtf8;
    procedure HasGlyphReflectsMap;
    procedure GlyphsFromText;
    { Slice 0 of the bundled-icon-font work: the capability seam. Every one of these covers a
      state the component previously had no way to report, or a change no consumer could see. }
    procedure AvailableIsTrueWithJustAFamily;
    procedure AvailableIsFalseAndLoadErrorNamesTheMissingFile;
    procedure LoadErrorClearsWhenTheFileIsCleared;
    procedure VersionBumpsOnMapFamilyAndFile;
    procedure ChangeHandlerFiresAndCanBeRemoved;
    procedure ChangeHandlersDropAFreedObject;
    procedure LookupIsCaseInsensitive;
    procedure FirstDuplicateWinsLikeValues;
    procedure UnparseableLineIsNotAGlyph;
    procedure ResolverSuppliesNamesNotInTheMap;
    procedure OwnMapBeatsTheResolver;
    procedure ResolverRegistrationIsIdempotentAndRemovable;
  end;

  { An object with a method to hand to AddHandlerOnChange, so the multicast list has something
    real to call and to forget. }
  TChangeSpy = class
  public
    Hits: Integer;
    procedure OnChanged(Sender: TObject);
  end;

implementation

procedure TIconFontTest.ParseBareHex;
begin
  AssertEquals('F0C7', $F0C7, TyParseCodepoint('F0C7'));
  AssertEquals('lower', $F0C7, TyParseCodepoint('f0c7'));
end;

procedure TIconFontTest.ParsePrefixes;
begin
  AssertEquals('0x', $F0C7, TyParseCodepoint('0xF0C7'));
  AssertEquals('$', $F0C7, TyParseCodepoint('$F0C7'));
  AssertEquals('U+', $F0C7, TyParseCodepoint('U+F0C7'));
  AssertEquals('spaces', $F0C7, TyParseCodepoint('  F0C7 '));
end;

procedure TIconFontTest.ParseInvalid;
begin
  AssertEquals('empty', 0, TyParseCodepoint(''));
  AssertEquals('garbage', 0, TyParseCodepoint('ZZZ'));
  AssertEquals('prefix only', 0, TyParseCodepoint('0x'));
end;

procedure TIconFontTest.ParseOutOfRange;
begin
  // Above the Unicode ceiling U+10FFFF.
  AssertEquals('too big', 0, TyParseCodepoint('110000'));
end;

procedure TIconFontTest.ParseRejectsSurrogate;
begin
  // Lone UTF-16 surrogates (U+D800..U+DFFF) are not valid scalar values.
  AssertEquals('low surrogate start', 0, TyParseCodepoint('D800'));
  AssertEquals('high surrogate end', 0, TyParseCodepoint('DFFF'));
  // Just outside the surrogate gap stays valid.
  AssertEquals('below gap', $D7FF, TyParseCodepoint('D7FF'));
  AssertEquals('above gap', $E000, TyParseCodepoint('E000'));
end;

procedure TIconFontTest.MapAndLookup;
var
  f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    f.MapGlyph('save', $F0C7);
    AssertEquals('save', $F0C7, f.CodepointOf('save'));
    AssertEquals('unmapped', 0, f.CodepointOf('nope'));
    f.MapGlyph('save', $F1F8);   // re-map wins
    AssertEquals('remap', $F1F8, f.CodepointOf('save'));
  finally
    f.Free;
  end;
end;

procedure TIconFontTest.GlyphTextMatchesUtf8;
var
  f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    f.MapGlyph('save', $F0C7);
    AssertEquals('utf8', UnicodeToUTF8($F0C7), f.GlyphText('save'));
    AssertEquals('unmapped empty', '', f.GlyphText('nope'));
  finally
    f.Free;
  end;
end;

procedure TIconFontTest.HasGlyphReflectsMap;
var
  f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    f.MapGlyph('save', $F0C7);
    AssertTrue('has', f.HasGlyph('save'));
    AssertFalse('missing', f.HasGlyph('nope'));
  finally
    f.Free;
  end;
end;

procedure TIconFontTest.GlyphsFromText;
var
  f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    f.Glyphs.Text := 'trash=F1F8' + LineEnding + 'gear=F013';
    AssertEquals('trash', $F1F8, f.CodepointOf('trash'));
    AssertEquals('gear', $F013, f.CodepointOf('gear'));
  finally
    f.Free;
  end;
end;

procedure TChangeSpy.OnChanged(Sender: TObject);
begin
  Inc(Hits);
end;

{ A resolver that knows exactly one name, for exactly one family. }
function TestResolver(const AFamily, AName: string; out ACodepoint: Cardinal): Boolean;
begin
  ACodepoint := 0;
  Result := (AFamily = 'TestIcons') and (AName = 'from-resolver');
  if Result then ACodepoint := $E123;
end;

procedure TIconFontTest.AvailableIsTrueWithJustAFamily;
var f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    AssertFalse('no family yet -> nothing can render', f.Available);
    f.FontFamily := 'Segoe MDL2 Assets';
    AssertTrue('an OS-installed family needs no file', f.Available);
    AssertEquals('and nothing failed', '', f.LoadError);
  finally f.Free; end;
end;

procedure TIconFontTest.AvailableIsFalseAndLoadErrorNamesTheMissingFile;
var f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    f.FontFamily := 'TestIcons';
    f.FontFile := 'Z:' + PathDelim + 'definitely-not-here' + PathDelim + 'icons.ttf';
    { THE point of this property. Before it existed the family stayed set, RenderGlyph passed
      its own guard, and the caller got a bitmap of tofu that looked exactly like an unmapped
      glyph name. }
    AssertFalse('a font file that did not load means nothing can render', f.Available);
    AssertTrue('and the reason names the file: ' + f.LoadError,
      Pos('icons.ttf', f.LoadError) > 0);
  finally f.Free; end;
end;

procedure TIconFontTest.LoadErrorClearsWhenTheFileIsCleared;
var f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    f.FontFamily := 'TestIcons';
    f.FontFile := 'Z:' + PathDelim + 'nope.ttf';
    AssertTrue('failed', f.LoadError <> '');
    f.FontFile := '';
    AssertEquals('asking for no file is not an error', '', f.LoadError);
    AssertTrue('and the family alone is enough again', f.Available);
  finally f.Free; end;
end;

procedure TIconFontTest.VersionBumpsOnMapFamilyAndFile;
var f: TTyIconFont; v0, v1, v2: Integer;
begin
  f := TTyIconFont.Create(nil);
  try
    v0 := f.Version;
    f.MapGlyph('save', $F0C7);
    v1 := f.Version;
    AssertTrue('the map changed', v1 > v0);
    f.FontFamily := 'TestIcons';
    v2 := f.Version;
    AssertTrue('the family changed', v2 > v1);
    f.FontFile := 'Z:' + PathDelim + 'nope.ttf';
    AssertTrue('the file changed', f.Version > v2);
  finally f.Free; end;
end;

procedure TIconFontTest.ChangeHandlerFiresAndCanBeRemoved;
var f: TTyIconFont; spy: TChangeSpy;
begin
  f := TTyIconFont.Create(nil);
  spy := TChangeSpy.Create;
  try
    f.AddHandlerOnChange(@spy.OnChanged);
    f.MapGlyph('save', $F0C7);
    AssertEquals('a map edit reaches the observer', 1, spy.Hits);
    f.FontFamily := 'TestIcons';
    AssertEquals('so does a family change', 2, spy.Hits);
    f.RemoveHandlerOnChange(@spy.OnChanged);
    f.MapGlyph('gear', $F013);
    AssertEquals('and removal really removes', 2, spy.Hits);
  finally spy.Free; f.Free; end;
end;

procedure TIconFontTest.ChangeHandlersDropAFreedObject;
var f: TTyIconFont; spy: TChangeSpy;
begin
  f := TTyIconFont.Create(nil);
  spy := TChangeSpy.Create;
  try
    f.AddHandlerOnChange(@spy.OnChanged);
    { What a control must do on the way out. Without it the next change calls a method on
      freed memory -- the reason LCL's own multicast lists carry this. }
    f.RemoveAllHandlersOfObject(spy);
    FreeAndNil(spy);
    f.MapGlyph('save', $F0C7);   { must not touch the dead observer }
    AssertTrue('survived a change after the observer was freed', f.Version > 0);
  finally spy.Free; f.Free; end;
end;

procedure TIconFontTest.LookupIsCaseInsensitive;
var f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    f.Glyphs.Text := 'Save=F0C7';
    AssertEquals('exact', $F0C7, f.CodepointOf('Save'));
    AssertEquals('lower', $F0C7, f.CodepointOf('save'));
    AssertEquals('upper', $F0C7, f.CodepointOf('SAVE'));
  finally f.Free; end;
end;

procedure TIconFontTest.FirstDuplicateWinsLikeValues;
var f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    { The index has to answer what TStringList.Values would have answered, or swapping the
      lookup for a hash silently changes behaviour on a hand-edited map. }
    f.Glyphs.Text := 'save=F0C7' + LineEnding + 'save=E001';
    AssertEquals('first entry wins', $F0C7, f.CodepointOf('save'));
    AssertEquals('...which is what Values does', 'F0C7', f.Glyphs.Values['save']);
  finally f.Free; end;
end;

procedure TIconFontTest.UnparseableLineIsNotAGlyph;
var f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    f.Glyphs.Text := 'save=nothex' + LineEnding + 'gear=F013';
    AssertEquals('a bad value is no glyph', 0, f.CodepointOf('save'));
    AssertFalse('and HasGlyph agrees', f.HasGlyph('save'));
    AssertEquals('its neighbour is unaffected', $F013, f.CodepointOf('gear'));
  finally f.Free; end;
end;

procedure TIconFontTest.ResolverSuppliesNamesNotInTheMap;
var f: TTyIconFont;
begin
  TyRegisterGlyphResolver(@TestResolver);
  f := TTyIconFont.Create(nil);
  try
    f.FontFamily := 'TestIcons';
    { Nothing in Glyphs at all -- this is the whole point of the seam. A bundled font unit
      registers one function and every name it knows resolves. }
    AssertEquals('resolved without a map entry', $E123, f.CodepointOf('from-resolver'));
    AssertTrue('HasGlyph sees it too', f.HasGlyph('from-resolver'));
    AssertEquals('a name nobody knows is still 0', 0, f.CodepointOf('no-such-glyph'));
    f.FontFamily := 'SomethingElse';
    AssertEquals('a resolver may decline by family', 0, f.CodepointOf('from-resolver'));
  finally
    f.Free;
    TyUnregisterGlyphResolver(@TestResolver);
  end;
end;

procedure TIconFontTest.OwnMapBeatsTheResolver;
var f: TTyIconFont;
begin
  TyRegisterGlyphResolver(@TestResolver);
  f := TTyIconFont.Create(nil);
  try
    f.FontFamily := 'TestIcons';
    f.MapGlyph('from-resolver', $E999);
    AssertEquals('the map on the component is authoritative', $E999,
      f.CodepointOf('from-resolver'));
  finally
    f.Free;
    TyUnregisterGlyphResolver(@TestResolver);
  end;
end;

procedure TIconFontTest.ResolverRegistrationIsIdempotentAndRemovable;
var n: Integer;
begin
  n := TyGlyphResolverCount;
  TyRegisterGlyphResolver(@TestResolver);
  AssertEquals('registered', n + 1, TyGlyphResolverCount);
  TyRegisterGlyphResolver(@TestResolver);
  AssertEquals('a second registration of the same function is a no-op', n + 1,
    TyGlyphResolverCount);
  TyUnregisterGlyphResolver(@TestResolver);
  AssertEquals('and one unregister is enough', n, TyGlyphResolverCount);
end;

initialization
  RegisterTest(TIconFontTest);
end.
