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

initialization
  RegisterTest(TIconFontTest);
end.
