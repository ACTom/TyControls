unit test.glyphimagelist;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Graphics, fpcunit, testregistry,
  BGRABitmap, tyControls.IconFont, tyControls.GlyphImageList;

type
  TGlyphImageListTest = class(TTestCase)
  published
    procedure CountReflectsGlyphs;
    procedure GlyphNameOfInRange;
    procedure GlyphNameOfOutOfRange;
    procedure IndexOfFound;
    procedure IndexOfMissing;
    procedure RenderIndexNilFontEmptyBitmap;
    procedure RenderIndexBadIndexEmptyBitmap;
    procedure RenderIndexClampsSize;
    procedure DrawNilFontDoesNotRaise;
    procedure IconFontFreeNilsReference;
  end;

implementation

procedure TGlyphImageListTest.CountReflectsGlyphs;
var
  L: TTyGlyphImageList;
begin
  L := TTyGlyphImageList.Create(nil);
  try
    AssertEquals('empty', 0, L.Count);
    L.Glyphs.Text := 'save' + LineEnding + 'open' + LineEnding + 'trash';
    AssertEquals('three', 3, L.Count);
  finally
    L.Free;
  end;
end;

procedure TGlyphImageListTest.GlyphNameOfInRange;
var
  L: TTyGlyphImageList;
begin
  L := TTyGlyphImageList.Create(nil);
  try
    L.Glyphs.Text := 'save' + LineEnding + 'open';
    AssertEquals('idx0', 'save', L.GlyphNameOf(0));
    AssertEquals('idx1', 'open', L.GlyphNameOf(1));
  finally
    L.Free;
  end;
end;

procedure TGlyphImageListTest.GlyphNameOfOutOfRange;
var
  L: TTyGlyphImageList;
begin
  L := TTyGlyphImageList.Create(nil);
  try
    L.Glyphs.Text := 'save';   // 1 item, so index 0 is valid, 1 is past the end
    AssertEquals('valid', 'save', L.GlyphNameOf(0));
    AssertEquals('neg', '', L.GlyphNameOf(-1));
    AssertEquals('past end', '', L.GlyphNameOf(1));
  finally
    L.Free;
  end;
end;

procedure TGlyphImageListTest.IndexOfFound;
var
  L: TTyGlyphImageList;
begin
  L := TTyGlyphImageList.Create(nil);
  try
    L.Glyphs.Text := 'save' + LineEnding + 'open' + LineEnding + 'trash';
    AssertEquals('open', 1, L.IndexOf('open'));
    AssertEquals('trash', 2, L.IndexOf('trash'));
  finally
    L.Free;
  end;
end;

procedure TGlyphImageListTest.IndexOfMissing;
var
  L: TTyGlyphImageList;
begin
  L := TTyGlyphImageList.Create(nil);
  try
    L.Glyphs.Text := 'save';
    AssertEquals('missing', -1, L.IndexOf('nope'));
  finally
    L.Free;
  end;
end;

procedure TGlyphImageListTest.RenderIndexNilFontEmptyBitmap;
var
  L: TTyGlyphImageList;
  bmp: TBGRABitmap;
begin
  L := TTyGlyphImageList.Create(nil);
  try
    L.Glyphs.Text := 'save';
    // No IconFont assigned -> empty transparent bitmap of the requested size.
    bmp := L.RenderIndex(0, 24, $FF000000);
    try
      AssertTrue('non-nil', bmp <> nil);
      AssertEquals('width', 24, bmp.Width);
      AssertEquals('height', 24, bmp.Height);
    finally
      bmp.Free;
    end;
  finally
    L.Free;
  end;
end;

procedure TGlyphImageListTest.RenderIndexBadIndexEmptyBitmap;
var
  L: TTyGlyphImageList;
  f: TTyIconFont;
  bmp: TBGRABitmap;
begin
  L := TTyGlyphImageList.Create(nil);
  f := TTyIconFont.Create(nil);
  try
    f.MapGlyph('save', $F0C7);
    L.IconFont := f;
    L.Glyphs.Text := 'save';
    // Index out of range -> empty bitmap of the requested size (not nil).
    bmp := L.RenderIndex(5, 16, $FF000000);
    try
      AssertTrue('non-nil', bmp <> nil);
      AssertEquals('width', 16, bmp.Width);
    finally
      bmp.Free;
    end;
  finally
    L.Free;
    f.Free;
  end;
end;

procedure TGlyphImageListTest.RenderIndexClampsSize;
var
  L: TTyGlyphImageList;
  bmp: TBGRABitmap;
begin
  L := TTyGlyphImageList.Create(nil);
  try
    L.Glyphs.Text := 'save';
    // ASizePx <= 0 is clamped to a 1px square; must not raise or return nil.
    bmp := L.RenderIndex(0, 0, $FF000000);
    try
      AssertTrue('non-nil', bmp <> nil);
      AssertEquals('clamped', 1, bmp.Width);
    finally
      bmp.Free;
    end;
  finally
    L.Free;
  end;
end;

procedure TGlyphImageListTest.DrawNilFontDoesNotRaise;
var
  L: TTyGlyphImageList;
  bmp: TBitmap;
begin
  L := TTyGlyphImageList.Create(nil);
  bmp := TBitmap.Create;
  try
    bmp.SetSize(48, 48);
    L.Glyphs.Text := 'save';
    // No IconFont, and also a bad index — neither may raise.
    // (DrawIndex is what the size/colour-carrying form is called now; Draw carries
    // LCL's own (x, y, index) order.)
    L.DrawIndex(bmp.Canvas, 0, 4, 4, 16, $FF000000);
    L.DrawIndex(bmp.Canvas, 99, 4, 4, 16, $FF000000);
    AssertTrue('survived', True);
  finally
    bmp.Free;
    L.Free;
  end;
end;

procedure TGlyphImageListTest.IconFontFreeNilsReference;
var
  L: TTyGlyphImageList;
  f: TTyIconFont;
begin
  L := TTyGlyphImageList.Create(nil);
  try
    f := TTyIconFont.Create(nil);
    L.IconFont := f;
    AssertTrue('assigned', L.IconFont = f);
    f.Free;                       // FreeNotification -> reference nil'd
    AssertTrue('nil after free', L.IconFont = nil);
  finally
    L.Free;
  end;
end;

initialization
  RegisterTest(TGlyphImageListTest);
end.
