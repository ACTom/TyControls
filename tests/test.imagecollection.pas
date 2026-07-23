unit test.imagecollection;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes, tyControls.ImageCollection;

type
  TImageCollectionTest = class(TTestCase)
  private
    { A caller-owned WxH BGRABitmap filled opaque, for AddBitmap tests. }
    function MakeBmp(AW, AH: Integer; AColor: TBGRAPixel): TBGRABitmap;
  published
    procedure StartsEmpty;
    procedure AddAndQuery;
    procedure AddTakesCopy;
    procedure AddReplacesSameName;
    procedure NamesAreCaseSensitive;
    procedure NameOfBounds;
    procedure GetBitmapSizesToRequest;
    procedure GetBitmapMissingIsEmptyNonNil;
    procedure GetBitmapNonSquareMasterKeepsAspect;
    procedure GetBitmapZeroSizeClampsToOne;
    procedure AddPictureBuildsMaster;
    procedure ClearEmpties;
    procedure IgnoresEmptyNameAndNil;
    { ChangeStamp / render cache. }
    procedure ChangeStampStartsAtZero;
    procedure ChangeStampBumpsOnAddBitmap;
    procedure ChangeStampBumpsOnAddPicture;
    procedure ChangeStampBumpsOnClear;
    procedure CachedBitmapHitReturnsSameInstance;
    procedure CachedBitmapDistinctPerSize;
    procedure CachedBitmapMissingIsNil;
    procedure CachedBitmapClampsSizeToOne;
    procedure GetBitmapHitReturnsSamePixels;
    procedure GetBitmapCopyIsIndependentOfCache;
    procedure ReplacingMasterInvalidatesCache;
    procedure ClearInvalidatesCache;
    procedure CacheCapBoundsTheCache;
    procedure CacheEvictsLeastRecentlyUsed;
    procedure IsCachedDoesNotDisturbLruOrder;
    procedure LoweringCacheCapacityEvictsNow;
    procedure CacheCapacityClampsToOne;
  end;

  TVirtualImageListTest = class(TTestCase)
  private
    function MakeBmp(AW, AH: Integer; AColor: TBGRAPixel): TBGRABitmap;
  published
    procedure StartsEmptyDefaultSize16;
    procedure CountAndIndexOf;
    procedure RenderIndexReturnsRequestedSize;
    procedure RenderIndexBadIndexIsEmptyNonNil;
    procedure RenderIndexNoCollectionIsEmptyNonNil;
    procedure DrawDoesNotRaise;
    procedure DrawBadIndexDoesNotRaise;
    procedure CollectionFreedNilsReference;
    { Borrowed (cached) accessor. }
    procedure CachedIndexHitReturnsSameInstance;
    procedure CachedIndexBadIndexIsNil;
    procedure CachedIndexNoCollectionIsNil;
  end;

implementation

{ True when both bitmaps have the same dimensions and byte-identical pixels. }
function PixelsEqual(A, B: TBGRABitmap): Boolean;
var
  i: Integer;
  pa, pb: PBGRAPixel;
begin
  Result := (A <> nil) and (B <> nil) and (A.Width = B.Width) and (A.Height = B.Height);
  if not Result then Exit;
  pa := A.Data;
  pb := B.Data;
  for i := 0 to A.NbPixels - 1 do
  begin
    if not (pa^ = pb^) then Exit(False);
    Inc(pa);
    Inc(pb);
  end;
end;

{ ---- TImageCollectionTest ---- }

function TImageCollectionTest.MakeBmp(AW, AH: Integer; AColor: TBGRAPixel): TBGRABitmap;
begin
  Result := TBGRABitmap.Create(AW, AH, AColor);
end;

procedure TImageCollectionTest.StartsEmpty;
var
  c: TTyImageCollection;
begin
  c := TTyImageCollection.Create(nil);
  try
    AssertEquals('count', 0, c.Count);
    AssertEquals('indexof', -1, c.IndexOf('nope'));
    AssertFalse('contains', c.Contains('nope'));
  finally
    c.Free;
  end;
end;

procedure TImageCollectionTest.AddAndQuery;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('logo', b);
    AssertEquals('count', 1, c.Count);
    AssertEquals('indexof', 0, c.IndexOf('logo'));
    AssertTrue('contains', c.Contains('logo'));
    AssertEquals('nameof', 'logo', c.NameOf(0));
    AssertFalse('other missing', c.Contains('other'));
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.AddTakesCopy;
var
  c: TTyImageCollection;
  b, got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('logo', b);
    // Freeing the caller's bitmap must not affect the stored copy.
    b.Free;
    b := nil;
    got := c.GetBitmap('logo', 8);
    try
      AssertEquals('still there', 8, got.Width);
    finally
      got.Free;
    end;
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.AddReplacesSameName;
var
  c: TTyImageCollection;
  b1, b2, got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b1 := MakeBmp(8, 8, BGRAWhite);
  b2 := MakeBmp(20, 10, BGRAWhite);
  try
    c.AddBitmap('img', b1);
    c.AddBitmap('img', b2);   // replaces, no duplicate entry
    AssertEquals('count still 1', 1, c.Count);
    // The 20x10 master fits into a 20 square as 20x10 (aspect kept), centered.
    got := c.GetBitmap('img', 20);
    try
      AssertEquals('square', 20, got.Width);
      AssertEquals('square', 20, got.Height);
    finally
      got.Free;
    end;
  finally
    b1.Free;
    b2.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.NamesAreCaseSensitive;
var
  c: TTyImageCollection;
  b1, b2: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b1 := MakeBmp(8, 8, BGRAWhite);
  b2 := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('Save', b1);
    c.AddBitmap('save', b2);   // a DIFFERENT key -> a second entry, not a replace
    AssertEquals('two distinct entries', 2, c.Count);
    AssertTrue('Save present', c.IndexOf('Save') >= 0);
    AssertTrue('save present', c.IndexOf('save') >= 0);
    AssertTrue('distinct indices', c.IndexOf('Save') <> c.IndexOf('save'));
    AssertFalse('wrong case absent', c.Contains('SAVE'));
  finally
    b1.Free;
    b2.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.NameOfBounds;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('a', b);
    AssertEquals('neg', '', c.NameOf(-1));
    AssertEquals('over', '', c.NameOf(5));
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.GetBitmapSizesToRequest;
var
  c: TTyImageCollection;
  b, got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    got := c.GetBitmap('x', 16);
    try
      AssertNotNull('non-nil', got);
      AssertEquals('w', 16, got.Width);
      AssertEquals('h', 16, got.Height);
    finally
      got.Free;
    end;
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.GetBitmapMissingIsEmptyNonNil;
var
  c: TTyImageCollection;
  got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  try
    got := c.GetBitmap('missing', 16);
    try
      AssertNotNull('non-nil', got);
      AssertEquals('w', 16, got.Width);
      AssertEquals('h', 16, got.Height);
      // Empty => fully transparent top-left pixel.
      AssertEquals('transparent alpha', 0, got.GetPixel(0, 0).alpha);
    finally
      got.Free;
    end;
  finally
    c.Free;
  end;
end;

procedure TImageCollectionTest.GetBitmapNonSquareMasterKeepsAspect;
var
  c: TTyImageCollection;
  b, got: TBGRABitmap;
begin
  // A 20x10 master into a 20 square scales to 20x10 (contain), centered -> the
  // result is a 20x20 square with transparent bands top+bottom.
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(20, 10, BGRAWhite);
  try
    c.AddBitmap('wide', b);
    got := c.GetBitmap('wide', 20);
    try
      AssertEquals('square w', 20, got.Width);
      AssertEquals('square h', 20, got.Height);
      // Top band (y=0) is the transparent padding; the middle row is opaque.
      AssertEquals('pad transparent', 0, got.GetPixel(10, 0).alpha);
      AssertEquals('content opaque', 255, got.GetPixel(10, 10).alpha);
    finally
      got.Free;
    end;
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.GetBitmapZeroSizeClampsToOne;
var
  c: TTyImageCollection;
  b, got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    got := c.GetBitmap('x', 0);   // <=0 clamps to a 1px square
    try
      AssertNotNull('non-nil', got);
      AssertEquals('w', 1, got.Width);
      AssertEquals('h', 1, got.Height);
    finally
      got.Free;
    end;
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.AddPictureBuildsMaster;
var
  c: TTyImageCollection;
  pic: TPicture;
  got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  pic := TPicture.Create;
  try
    // Give the picture a concrete 12x12 bitmap graphic.
    pic.Bitmap.SetSize(12, 12);
    pic.Bitmap.Canvas.Brush.Color := clRed;
    pic.Bitmap.Canvas.FillRect(0, 0, 12, 12);
    c.AddPicture('pic', pic);
    AssertEquals('count', 1, c.Count);
    AssertTrue('contains', c.Contains('pic'));
    got := c.GetBitmap('pic', 16);
    try
      AssertEquals('w', 16, got.Width);
      AssertEquals('h', 16, got.Height);
    finally
      got.Free;
    end;
  finally
    pic.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.ClearEmpties;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('a', b);
    c.AddBitmap('b', b);
    AssertEquals('two', 2, c.Count);
    c.Clear;
    AssertEquals('cleared', 0, c.Count);
    AssertFalse('gone', c.Contains('a'));
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.IgnoresEmptyNameAndNil;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('', b);      // empty name -> no-op
    c.AddBitmap('n', nil);   // nil bitmap -> no-op
    c.AddPicture('', nil);   // empty name + nil -> no-op
    AssertEquals('still empty', 0, c.Count);
  finally
    b.Free;
    c.Free;
  end;
end;

{ ---- TImageCollectionTest: version + render cache ---- }

procedure TImageCollectionTest.ChangeStampStartsAtZero;
var
  c: TTyImageCollection;
begin
  c := TTyImageCollection.Create(nil);
  try
    AssertEquals('fresh change stamp', 0, Integer(c.ChangeStamp));
  finally
    c.Free;
  end;
end;

procedure TImageCollectionTest.ChangeStampBumpsOnAddBitmap;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
  v0: Cardinal;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    v0 := c.ChangeStamp;
    c.AddBitmap('x', b);
    AssertTrue('add bumps', c.ChangeStamp > v0);
    v0 := c.ChangeStamp;
    c.AddBitmap('x', b);   // replacing a master must bump too
    AssertTrue('replace bumps', c.ChangeStamp > v0);
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.ChangeStampBumpsOnAddPicture;
var
  c: TTyImageCollection;
  pic: TPicture;
  v0: Cardinal;
begin
  c := TTyImageCollection.Create(nil);
  pic := TPicture.Create;
  try
    pic.Bitmap.SetSize(12, 12);
    pic.Bitmap.Canvas.Brush.Color := clRed;
    pic.Bitmap.Canvas.FillRect(0, 0, 12, 12);
    v0 := c.ChangeStamp;
    c.AddPicture('pic', pic);
    AssertTrue('addpicture bumps', c.ChangeStamp > v0);
  finally
    pic.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.ChangeStampBumpsOnClear;
var
  c: TTyImageCollection;
  v0: Cardinal;
begin
  c := TTyImageCollection.Create(nil);
  try
    v0 := c.ChangeStamp;
    c.Clear;
    AssertTrue('clear bumps', c.ChangeStamp > v0);
  finally
    c.Free;
  end;
end;

procedure TImageCollectionTest.CachedBitmapHitReturnsSameInstance;
var
  c: TTyImageCollection;
  b, p1, p2: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    p1 := c.GetCachedBitmap('x', 16);
    p2 := c.GetCachedBitmap('x', 16);
    AssertNotNull('first', p1);
    AssertSame('cache hit is the same borrowed instance', p1, p2);
    AssertEquals('one entry', 1, c.CacheCount);
    AssertEquals('sized', 16, p1.Width);
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.CachedBitmapDistinctPerSize;
var
  c: TTyImageCollection;
  b, p8, p16: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    p8 := c.GetCachedBitmap('x', 8);
    p16 := c.GetCachedBitmap('x', 16);
    AssertEquals('8px', 8, p8.Width);
    AssertEquals('16px', 16, p16.Width);
    AssertEquals('keyed by (name, size)', 2, c.CacheCount);
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.CachedBitmapMissingIsNil;
var
  c: TTyImageCollection;
begin
  c := TTyImageCollection.Create(nil);
  try
    // The borrowed accessor reports "nothing to draw" as nil (unlike GetBitmap,
    // which owes the caller an empty square).
    AssertNull('missing name', c.GetCachedBitmap('missing', 16));
    AssertEquals('nothing cached', 0, c.CacheCount);
  finally
    c.Free;
  end;
end;

procedure TImageCollectionTest.CachedBitmapClampsSizeToOne;
var
  c: TTyImageCollection;
  b, got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    got := c.GetCachedBitmap('x', 0);
    AssertNotNull('non-nil', got);
    AssertEquals('w', 1, got.Width);
    AssertEquals('h', 1, got.Height);
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.GetBitmapHitReturnsSamePixels;
var
  c: TTyImageCollection;
  b, g1, g2: TBGRABitmap;
begin
  // A cache hit must not change what GetBitmap renders.
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(9, 5, BGRAWhite);   // non-square: exercises the aspect-fit path
  try
    c.AddBitmap('x', b);
    g1 := c.GetBitmap('x', 16);
    g2 := c.GetBitmap('x', 16);
    try
      AssertTrue('same pixels across calls', PixelsEqual(g1, g2));
      AssertTrue('but distinct owned copies', g1 <> g2);
    finally
      g1.Free;
      g2.Free;
    end;
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.GetBitmapCopyIsIndependentOfCache;
var
  c: TTyImageCollection;
  b, g1, g2: TBGRABitmap;
begin
  // GetBitmap hands back an OWNED copy. Callers such as TTyGlyphButtonBase and
  // TTyRibbonBackstage tint it in place (TyTintBitmapAlpha); that must never
  // reach the shared cache entry.
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    g1 := c.GetBitmap('x', 16);
    try
      TyTintBitmapAlpha(g1, $FFFF0000);   // opaque red, in place
    finally
      g1.Free;
    end;
    g2 := c.GetBitmap('x', 16);
    try
      // The master is white; a leaked tint would show up here.
      AssertEquals('red untouched', 255, g2.GetPixel(8, 8).red);
      AssertEquals('green untouched', 255, g2.GetPixel(8, 8).green);
      AssertEquals('blue untouched', 255, g2.GetPixel(8, 8).blue);
    finally
      g2.Free;
    end;
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.ReplacingMasterInvalidatesCache;
var
  c: TTyImageCollection;
  white, blue, got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  white := MakeBmp(8, 8, BGRAWhite);
  blue := MakeBmp(8, 8, BGRA(0, 0, 255, 255));
  try
    c.AddBitmap('x', white);
    got := c.GetCachedBitmap('x', 16);          // populate the cache
    AssertEquals('white cached', 255, got.GetPixel(8, 8).red);

    c.AddBitmap('x', blue);                      // bumps ChangeStamp under the live cache
    got := c.GetCachedBitmap('x', 16);
    AssertEquals('re-rendered blue', 0, got.GetPixel(8, 8).red);
    AssertEquals('re-rendered blue', 255, got.GetPixel(8, 8).blue);
  finally
    white.Free;
    blue.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.ClearInvalidatesCache;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    AssertNotNull('cached', c.GetCachedBitmap('x', 16));
    c.Clear;
    AssertEquals('cache dropped', 0, c.CacheCount);
    AssertNull('name gone', c.GetCachedBitmap('x', 16));
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.CacheCapBoundsTheCache;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
  sz: Integer;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    c.CacheCapacity := 3;
    for sz := 1 to 20 do
      c.GetCachedBitmap('x', sz);   // 20 distinct sizes, cap of 3
    AssertEquals('bounded', 3, c.CacheCount);
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.CacheEvictsLeastRecentlyUsed;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  // Eviction is asserted via IsCached, never by comparing against a pointer we
  // expect to have been freed: the allocator happily hands the same address back
  // for the replacement render, so such a comparison passes even when the LRU
  // order is inverted.
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    c.CacheCapacity := 2;
    c.GetCachedBitmap('x', 8);
    c.GetCachedBitmap('x', 16);
    c.GetCachedBitmap('x', 8);    // touch 8 -> 16 is now the least recently used
    c.GetCachedBitmap('x', 24);   // must evict 16, not 8
    AssertEquals('still bounded', 2, c.CacheCount);
    AssertTrue('8px survived (recently used)', c.IsCached('x', 8));
    AssertFalse('16px evicted (least recently used)', c.IsCached('x', 16));
    AssertTrue('24px inserted', c.IsCached('x', 24));
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.IsCachedDoesNotDisturbLruOrder;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    c.CacheCapacity := 2;
    c.GetCachedBitmap('x', 8);
    c.GetCachedBitmap('x', 16);
    c.IsCached('x', 8);           // a pure query: must NOT make 8 the most recent
    c.GetCachedBitmap('x', 24);   // so 8 is still the LRU and must be the victim
    AssertFalse('8px evicted despite the IsCached query', c.IsCached('x', 8));
    AssertTrue('16px survived', c.IsCached('x', 16));
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.LoweringCacheCapacityEvictsNow;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    c.GetCachedBitmap('x', 8);
    c.GetCachedBitmap('x', 16);
    c.GetCachedBitmap('x', 24);
    AssertEquals('three cached', 3, c.CacheCount);
    c.CacheCapacity := 1;   // shrinking must evict immediately, not lazily
    AssertEquals('trimmed', 1, c.CacheCount);
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionTest.CacheCapacityClampsToOne;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  // A zero/negative cap would evict the entry GetCachedBitmap is about to hand
  // back, leaving the caller with a dangling reference.
  c := TTyImageCollection.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('x', b);
    c.CacheCapacity := 0;
    AssertEquals('clamped', 1, c.CacheCapacity);
    AssertNotNull('still serves a borrowed render', c.GetCachedBitmap('x', 16));
    AssertEquals('one entry', 1, c.CacheCount);
  finally
    b.Free;
    c.Free;
  end;
end;

{ ---- TVirtualImageListTest ---- }

function TVirtualImageListTest.MakeBmp(AW, AH: Integer; AColor: TBGRAPixel): TBGRABitmap;
begin
  Result := TBGRABitmap.Create(AW, AH, AColor);
end;

procedure TVirtualImageListTest.StartsEmptyDefaultSize16;
var
  v: TTyVirtualImageList;
begin
  v := TTyVirtualImageList.Create(nil);
  try
    AssertEquals('count', 0, v.Count);
    AssertEquals('default size', 16, v.DefaultSize);
    AssertEquals('indexof', -1, v.IndexOf('x'));
  finally
    v.Free;
  end;
end;

procedure TVirtualImageListTest.CountAndIndexOf;
var
  c: TTyImageCollection;
  v: TTyVirtualImageList;
  b: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  v := TTyVirtualImageList.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('one', b);
    c.AddBitmap('two', b);
    v.Collection := c;
    v.Names.Add('one');
    v.Names.Add('two');
    AssertEquals('count', 2, v.Count);
    AssertEquals('idx one', 0, v.IndexOf('one'));
    AssertEquals('idx two', 1, v.IndexOf('two'));
    AssertEquals('nameof', 'two', v.NameOf(1));
    AssertEquals('missing', -1, v.IndexOf('three'));
  finally
    b.Free;
    v.Free;
    c.Free;
  end;
end;

procedure TVirtualImageListTest.RenderIndexReturnsRequestedSize;
var
  c: TTyImageCollection;
  v: TTyVirtualImageList;
  b, got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  v := TTyVirtualImageList.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('one', b);
    v.Collection := c;
    v.Names.Add('one');
    got := v.RenderIndex(0, 24);
    try
      AssertNotNull('non-nil', got);
      AssertEquals('w', 24, got.Width);
      AssertEquals('h', 24, got.Height);
    finally
      got.Free;
    end;
  finally
    b.Free;
    v.Free;
    c.Free;
  end;
end;

procedure TVirtualImageListTest.RenderIndexBadIndexIsEmptyNonNil;
var
  c: TTyImageCollection;
  v: TTyVirtualImageList;
  got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  v := TTyVirtualImageList.Create(nil);
  try
    v.Collection := c;
    got := v.RenderIndex(99, 16);   // out of range
    try
      AssertNotNull('non-nil', got);
      AssertEquals('w', 16, got.Width);
    finally
      got.Free;
    end;
  finally
    v.Free;
    c.Free;
  end;
end;

procedure TVirtualImageListTest.RenderIndexNoCollectionIsEmptyNonNil;
var
  v: TTyVirtualImageList;
  got: TBGRABitmap;
begin
  v := TTyVirtualImageList.Create(nil);
  try
    v.Names.Add('x');   // named, but no collection assigned
    got := v.RenderIndex(0, 16);
    try
      AssertNotNull('non-nil', got);
      AssertEquals('w', 16, got.Width);
    finally
      got.Free;
    end;
  finally
    v.Free;
  end;
end;

procedure TVirtualImageListTest.DrawDoesNotRaise;
var
  c: TTyImageCollection;
  v: TTyVirtualImageList;
  b: TBGRABitmap;
  target: TBitmap;
begin
  c := TTyImageCollection.Create(nil);
  v := TTyVirtualImageList.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  target := TBitmap.Create;
  try
    c.AddBitmap('one', b);
    v.Collection := c;
    v.Names.Add('one');
    target.SetSize(32, 32);
    v.Draw(target.Canvas, 0, 4, 4, 16);   // must not raise
    AssertTrue('drew', True);
  finally
    target.Free;
    b.Free;
    v.Free;
    c.Free;
  end;
end;

procedure TVirtualImageListTest.DrawBadIndexDoesNotRaise;
var
  v: TTyVirtualImageList;
  target: TBitmap;
begin
  v := TTyVirtualImageList.Create(nil);
  target := TBitmap.Create;
  try
    target.SetSize(32, 32);
    v.Draw(target.Canvas, 99, 0, 0, 16);   // bad index, no collection -> safe no-op blit
    v.Draw(nil, 0, 0, 0, 16);              // nil canvas -> safe
    AssertTrue('safe', True);
  finally
    target.Free;
    v.Free;
  end;
end;

procedure TVirtualImageListTest.CollectionFreedNilsReference;
var
  c: TTyImageCollection;
  v: TTyVirtualImageList;
begin
  c := TTyImageCollection.Create(nil);
  v := TTyVirtualImageList.Create(nil);
  try
    v.Collection := c;
    AssertSame('linked', c, v.Collection);
    c.Free;                 // FreeNotification should nil the reference
    c := nil;
    AssertNull('nil after free', v.Collection);
  finally
    v.Free;
    c.Free;
  end;
end;

procedure TVirtualImageListTest.CachedIndexHitReturnsSameInstance;
var
  c: TTyImageCollection;
  v: TTyVirtualImageList;
  b, p1, p2: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  v := TTyVirtualImageList.Create(nil);
  b := MakeBmp(8, 8, BGRAWhite);
  try
    c.AddBitmap('one', b);
    v.Collection := c;
    v.Names.Add('one');
    p1 := v.CachedIndex(0, 24);
    p2 := v.CachedIndex(0, 24);
    AssertNotNull('non-nil', p1);
    AssertEquals('sized', 24, p1.Width);
    AssertSame('borrowed, cached', p1, p2);
    // The borrowed reference is the collection's entry, not a copy.
    AssertSame('same entry as the collection serves', c.GetCachedBitmap('one', 24), p1);
  finally
    b.Free;
    v.Free;
    c.Free;
  end;
end;

procedure TVirtualImageListTest.CachedIndexBadIndexIsNil;
var
  c: TTyImageCollection;
  v: TTyVirtualImageList;
begin
  c := TTyImageCollection.Create(nil);
  v := TTyVirtualImageList.Create(nil);
  try
    v.Collection := c;
    AssertNull('out of range', v.CachedIndex(99, 16));
  finally
    v.Free;
    c.Free;
  end;
end;

procedure TVirtualImageListTest.CachedIndexNoCollectionIsNil;
var
  v: TTyVirtualImageList;
begin
  v := TTyVirtualImageList.Create(nil);
  try
    v.Names.Add('x');   // named, but no collection assigned
    AssertNull('no collection', v.CachedIndex(0, 16));
  finally
    v.Free;
  end;
end;

initialization
  RegisterTest(TImageCollectionTest);
  RegisterTest(TVirtualImageListTest);
end.
