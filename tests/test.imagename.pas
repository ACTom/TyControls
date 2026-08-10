unit test.imagename;
{$mode objfpc}{$H+}

{ The ImageName rollout, one pattern shared by every icon-bearing control: the NAME is the
  durable state and the INDEX is a view of it, resolved against the associated list's Names. A
  name outlives a reorder of the list; an index does not. These tests pin the behaviours that a
  per-control hand-rolled copy would get subtly wrong -- resolve both ways, follow a reorder,
  survive a list that arrives late (streaming), stay inert on a foreign list with no names, and
  stream the index ONLY when a name cannot capture the choice (the reorder-clobber guard).

  Control-level here is TTyImage (its own Images); item-level is TTyColumn (resolves against the
  owning TTyHeader.Images). The other rolled-out controls reuse the same TyImage* helpers and the
  same setter shape, so this unit is the behavioural contract for all of them. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TImageNameTest = class(TTestCase)
  private
    FColl:  TObject;   // TTyImageCollection, held opaque to keep the uses list in the impl
    FList:  TObject;   // TTyVirtualImageList over FColl, Names = home/settings/search
    FBaked: TObject;   // a stock LCL TImageList: a foreign list with NO names
    procedure ReorderTo(const ANames: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { control-level: TTyImage }
    procedure SettingTheNameResolvesTheIndex;
    procedure SettingTheIndexStoresTheName;
    procedure TheNameFollowsAReorder;
    procedure APendingIndexResolvesWhenImagesArrive;
    procedure AForeignListLeavesTheNameInertAndKeepsTheIndex;
    procedure AClearedIndexClearsTheName;
    { the streaming guard }
    procedure ANamedImageDoesNotStreamItsIndex;
    procedure AForeignIndexDoesStream;
    { item-level: TTyColumn via TTyHeader }
    procedure AColumnResolvesAgainstTheHeaderList;
    procedure AColumnPendingIndexResolvesWhenTheHeaderGetsImages;
    procedure AColumnNameFollowsAReorder;
    { control-level via a foreign owner list: TTyTabSheet against its pager }
    procedure APageResolvesAgainstThePagerList;
    procedure APagePendingIndexResolvesWhenThePagerGetsImages;
  end;

implementation

uses
  Types, Graphics, ImgList, Controls, TypInfo, Forms,
  BGRABitmap, BGRABitmapTypes,
  tyControls.ImageCollection, tyControls.ImageDraw,
  tyControls.Image, tyControls.Columns, tyControls.TabSheet, tyControls.PageControl;

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TImageNameTest.ReorderTo(const ANames: string);
begin
  TTyVirtualImageList(FList).Names.Text := ANames;
end;

procedure TImageNameTest.SetUp;
  procedure AddImg(AColl: TTyImageCollection; const AName: string; AColor: TBGRAPixel);
  var bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(24, 24, AColor);
    try AColl.AddBitmap(AName, bmp); finally bmp.Free; end;
  end;
var
  c: TTyImageCollection;
  v: TTyVirtualImageList;
  baked: TImageList;
  bmp: TBitmap;
begin
  NeedWidgetSet;
  c := TTyImageCollection.Create(nil);
  AddImg(c, 'home',     BGRA(255, 0, 0, 255));
  AddImg(c, 'settings', BGRA(0, 255, 0, 255));
  AddImg(c, 'search',   BGRA(0, 0, 255, 255));
  FColl := c;

  v := TTyVirtualImageList.Create(nil);
  v.Collection := c;
  v.Names.Text := 'home' + LineEnding + 'settings' + LineEnding + 'search';
  FList := v;

  baked := TImageList.Create(nil);
  baked.Width := 16; baked.Height := 16;
  bmp := TBitmap.Create;
  try
    bmp.SetSize(16, 16);
    bmp.Canvas.Brush.Color := clRed; bmp.Canvas.FillRect(0, 0, 16, 16);
    baked.Add(bmp, nil);
    baked.Add(bmp, nil);
  finally
    bmp.Free;
  end;
  FBaked := baked;
end;

procedure TImageNameTest.TearDown;
begin
  FBaked.Free;
  FList.Free;
  FColl.Free;
end;

{ ---- control-level: TTyImage --------------------------------------------- }

procedure TImageNameTest.SettingTheNameResolvesTheIndex;
var img: TTyImage;
begin
  img := TTyImage.Create(nil);
  try
    img.Images := TTyVirtualImageList(FList);
    img.ImageName := 'settings';
    AssertEquals('the name resolves to its slot', 1, img.ImageIndex);
  finally
    img.Free;
  end;
end;

procedure TImageNameTest.SettingTheIndexStoresTheName;
var img: TTyImage;
begin
  img := TTyImage.Create(nil);
  try
    img.Images := TTyVirtualImageList(FList);
    img.ImageIndex := 2;
    AssertEquals('the index write became the durable name', 'search', img.ImageName);
  finally
    img.Free;
  end;
end;

procedure TImageNameTest.TheNameFollowsAReorder;
var img: TTyImage;
begin
  img := TTyImage.Create(nil);
  try
    img.Images := TTyVirtualImageList(FList);
    img.ImageName := 'search';                 // slot 2 now
    AssertEquals('search starts at 2', 2, img.ImageIndex);
    ReorderTo('search' + LineEnding + 'home' + LineEnding + 'settings');
    AssertEquals('the name followed its image to slot 0', 0, img.ImageIndex);
    AssertEquals('the name itself is unchanged', 'search', img.ImageName);
  finally
    img.Free;
  end;
end;

procedure TImageNameTest.APendingIndexResolvesWhenImagesArrive;
var img: TTyImage;
begin
  img := TTyImage.Create(nil);
  try
    img.ImageIndex := 1;                        // no list yet -> pending, no name
    AssertEquals('no name while the list is nil', '', img.ImageName);
    img.Images := TTyVirtualImageList(FList);   // the list arrives
    AssertEquals('the pending index resolved to a name', 'settings', img.ImageName);
    AssertEquals('and the index reads back the same slot', 1, img.ImageIndex);
  finally
    img.Free;
  end;
end;

procedure TImageNameTest.AForeignListLeavesTheNameInertAndKeepsTheIndex;
var img: TTyImage;
begin
  img := TTyImage.Create(nil);
  try
    img.Images := TImageList(FBaked);           // a foreign list: no names
    img.ImageIndex := 1;
    AssertEquals('a foreign list yields no name', '', img.ImageName);
    AssertEquals('the index is the key there', 1, img.ImageIndex);
  finally
    img.Free;
  end;
end;

procedure TImageNameTest.AClearedIndexClearsTheName;
var img: TTyImage;
begin
  img := TTyImage.Create(nil);
  try
    img.Images := TTyVirtualImageList(FList);
    img.ImageName := 'home';
    img.ImageIndex := -1;                       // explicit "no icon"
    AssertEquals('-1 cleared the name', '', img.ImageName);
    AssertEquals('and the index is -1', -1, img.ImageIndex);
  finally
    img.Free;
  end;
end;

{ ---- the streaming guard: index streams ONLY when a name cannot hold it --- }

procedure TImageNameTest.ANamedImageDoesNotStreamItsIndex;
var img: TTyImage;
begin
  { The reorder-clobber guard: when a name captures the choice, the index MUST NOT also stream,
    or a stale index would overwrite the name on the next load after a reorder. IsStoredProp
    evaluates the property's `stored` function, which is exactly what the streamer consults. }
  img := TTyImage.Create(nil);
  try
    img.Images := TTyVirtualImageList(FList);
    img.ImageName := 'home';
    AssertFalse('a named image does not stream its index',
      IsStoredProp(img, 'ImageIndex'));
  finally
    img.Free;
  end;
end;

procedure TImageNameTest.AForeignIndexDoesStream;
var img: TTyImage;
begin
  { With a foreign list the name is inert, so the index is the only durable state and MUST
    stream, or the icon choice would be lost on save. }
  img := TTyImage.Create(nil);
  try
    img.Images := TImageList(FBaked);
    img.ImageIndex := 1;
    AssertTrue('a foreign index is the only key, so it streams',
      IsStoredProp(img, 'ImageIndex'));
  finally
    img.Free;
  end;
end;

{ ---- item-level: TTyColumn via TTyHeader ---------------------------------- }

procedure TImageNameTest.AColumnResolvesAgainstTheHeaderList;
var h: TTyHeader; col: TTyColumn;
begin
  h := TTyHeader.Create;
  try
    h.Images := TTyVirtualImageList(FList);
    col := h.Columns.Add;
    col.ImageName := 'settings';
    AssertEquals('the column resolves against the header list', 1, col.ImageIndex);
  finally
    h.Free;
  end;
end;

procedure TImageNameTest.AColumnPendingIndexResolvesWhenTheHeaderGetsImages;
var h: TTyHeader; col: TTyColumn;
begin
  h := TTyHeader.Create;
  try
    col := h.Columns.Add;
    col.ImageIndex := 2;                        // header has no list yet -> pending, no name
    AssertEquals('no name while the header list is nil', '', col.ImageName);
    h.Images := TTyVirtualImageList(FList);      // the list arrives on the header
    AssertEquals('the column pending index resolved', 'search', col.ImageName);
    AssertEquals('and reads back the same slot', 2, col.ImageIndex);
  finally
    h.Free;
  end;
end;

procedure TImageNameTest.AColumnNameFollowsAReorder;
var h: TTyHeader; col: TTyColumn;
begin
  h := TTyHeader.Create;
  try
    h.Images := TTyVirtualImageList(FList);
    col := h.Columns.Add;
    col.ImageName := 'home';                    // slot 0
    ReorderTo('settings' + LineEnding + 'search' + LineEnding + 'home');
    AssertEquals('the column name followed its image to slot 2', 2, col.ImageIndex);
  finally
    h.Free;
  end;
end;

{ ---- control-level against a foreign owner: TTyTabSheet resolves via its pager  }

procedure TImageNameTest.APageResolvesAgainstThePagerList;
var f: TForm; pc: TTyPageControl; sheet: TTyTabSheet;
begin
  f := TForm.CreateNew(nil);
  try
    pc := TTyPageControl.Create(f);
    pc.Parent := f;
    pc.Images := TTyVirtualImageList(FList);
    sheet := pc.AddPage('a page');
    sheet.ImageName := 'settings';
    AssertEquals('the page resolves against the pager list', 1, sheet.ImageIndex);
  finally
    f.Free;
  end;
end;

procedure TImageNameTest.APagePendingIndexResolvesWhenThePagerGetsImages;
var f: TForm; pc: TTyPageControl; sheet: TTyTabSheet;
begin
  { The DoImagesChanged path: the page's ImageIndex is written while the pager has no list, so it
    stays pending; assigning the list to the pager must convert it to the durable name. }
  f := TForm.CreateNew(nil);
  try
    pc := TTyPageControl.Create(f);
    pc.Parent := f;
    sheet := pc.AddPage('a page');
    sheet.ImageIndex := 2;                       // pager has no Images yet -> pending, no name
    AssertEquals('no name while the pager list is nil', '', sheet.ImageName);
    pc.Images := TTyVirtualImageList(FList);      // the list arrives on the pager
    AssertEquals('the page pending index resolved', 'search', sheet.ImageName);
    AssertEquals('and reads back the same slot', 2, sheet.ImageIndex);
  finally
    f.Free;
  end;
end;

initialization
  RegisterTest(TImageNameTest);

end.
