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
    procedure NameOfBounds;
    procedure GetBitmapSizesToRequest;
    procedure GetBitmapMissingIsEmptyNonNil;
    procedure GetBitmapNonSquareMasterKeepsAspect;
    procedure GetBitmapZeroSizeClampsToOne;
    procedure AddPictureBuildsMaster;
    procedure ClearEmpties;
    procedure IgnoresEmptyNameAndNil;
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
  end;

implementation

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

initialization
  RegisterTest(TImageCollectionTest);
  RegisterTest(TVirtualImageListTest);
end.
