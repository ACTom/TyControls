unit test.imagedraw;
{$mode objfpc}{$H+}

{ The two-path image helper.

  What is worth pinning here is the stuff that made per-call-site copies of this go wrong:

  THE PATH SPLIT. `is TTyVirtualImageList`, tested for the NARROW type -- after the reparent a
  a stock TImageList is ALSO a TCustomImageList, so a test for the WIDE type would send both down
  the same branch. TyImageIsBaked and the count/measure helpers must route a Ty list one way
  and a baked list the other.

  MEASURE MUST NOT MUTATE. TyImageSizePx on a baked list must not grow that list -- LCL's
  ResolutionForPPI creates a resolution for any width it lacks, and a layout pass calling that
  would spray resolutions into a list the application owns. Asserted by watching ResolutionCount
  across a measure that asks for a size not registered.

  THE BOOLEAN CONTRACT of TyPutImage: True for the Ty branch (drawn in-layer) and for the
  nothing-to-draw cases; False ONLY for a baked list, which the caller still owes to the
  post-EndPaint pass. Getting this wrong makes a control whose Ty icons work and whose LCL
  icons silently never appear.

  The baked branch's actual GDI DRAW is not asserted -- it needs a real widgetset resolution
  and a window. What is assertable headlessly is the routing, the counts, the sizes and the
  no-mutation promise, which is where the defects were. }

interface

uses
  Classes, SysUtils, Types, Graphics, GraphType, ImgList, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.ImageCollection, tyControls.ImageDraw;

type
  TImageDrawTest = class(TTestCase)
  private
    FColl: TTyImageCollection;
    FVector: TTyVirtualImageList;   // ours -- the on-demand branch
    FBaked: TImageList;             // a STOCK LCL list -- the baked branch, the real foreign case
    procedure AddImage(const AName: string; AColor: TBGRAPixel);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure NilIsNeitherBakedNorCounted;
    procedure OurListIsNotBaked;
    procedure AnLclListIsBaked;
    procedure CountAsksTheRightBranch;
    procedure SizeOfOurListIsWhatYouAskFor;
    procedure SizeOfANilOrEmptyListReservesNoSlot;
    procedure MeasuringABakedListDoesNotGrowIt;
    procedure PutImageDrawsOurBranchInLayer;
    procedure PutImageDefersABakedList;
    procedure PutImageOnNothingIsDone;
    procedure PutImageAfterEndPaintReportsDoneAndDrawsNothing;
    procedure GhostPolarityIsATableNotANot;
    procedure BlitDrawsOurBranchInLayer;
    procedure BlitMaterialisesABakedListInLayer;
    procedure RenderReturnsAnOwnedBitmapOurBranch;
    procedure RenderMaterialisesABakedListToAnOwnedBitmap;
    procedure NameResolvesBothWaysOnOurList;
    procedure NameResolutionIsInertOnAForeignList;
    procedure NameResolutionGuardsNilEmptyAndOutOfRange;
    procedure TheNameTracksTheImageAcrossAReorder;
  end;

implementation

uses
  Forms;

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TImageDrawTest.AddImage(const AName: string; AColor: TBGRAPixel);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(32, 32, AColor);
  try
    FColl.AddBitmap(AName, bmp);
  finally
    bmp.Free;
  end;
end;

procedure TImageDrawTest.SetUp;
var bmp: TBitmap;
begin
  NeedWidgetSet;
  FColl := TTyImageCollection.Create(nil);
  AddImage('red', BGRA(255, 0, 0, 255));
  AddImage('green', BGRA(0, 255, 0, 255));
  FVector := TTyVirtualImageList.Create(nil);
  FVector.Collection := FColl;
  FVector.Names.Text := 'red' + LineEnding + 'green';
  { A plain LCL TImageList with two registered resolutions, so the measure trap (asking for a
    width it does not have) has something real to mint against -- this is exactly the foreign
    list a user might assign, and the branch the helper defers/bakes for. }
  FBaked := TImageList.Create(nil);
  FBaked.Width := 16;
  FBaked.Height := 16;
  FBaked.RegisterResolutions([16, 32]);
  bmp := TBitmap.Create;
  try
    bmp.SetSize(16, 16);
    bmp.Canvas.Brush.Color := clRed;
    bmp.Canvas.FillRect(0, 0, 16, 16);
    FBaked.Add(bmp, nil);      { one image -> Count = 1, ResolutionCount = 2 }
  finally
    bmp.Free;
  end;
end;

procedure TImageDrawTest.TearDown;
begin
  FBaked.Free;
  FVector.Free;
  FColl.Free;
end;

procedure TImageDrawTest.NilIsNeitherBakedNorCounted;
begin
  AssertFalse('nil is not baked', TyImageIsBaked(nil));
  AssertEquals('nil counts zero', 0, TyImageCount(nil));
  AssertEquals('nil reserves no width', 0, TyImageSizePx(nil, 24, 96).cx);
end;

procedure TImageDrawTest.OurListIsNotBaked;
begin
  { The path test, at the narrow type. Our list renders on demand -- it is not baked, even
    though it now inherits TCustomImageList. }
  AssertFalse('a TTyVirtualImageList is the on-demand branch', TyImageIsBaked(FVector));
end;

procedure TImageDrawTest.AnLclListIsBaked;
begin
  { And a stock LCL TImageList -- also a TCustomImageList descendant, which a test for the
    WIDE type would get wrong -- takes the baked branch, which is the whole reason for the
    narrow-type check. }
  AssertTrue('a stock TImageList is the baked branch', TyImageIsBaked(FBaked));
end;

procedure TImageDrawTest.CountAsksTheRightBranch;
begin
  AssertEquals('our list counts its names', 2, TyImageCount(FVector));
  AssertEquals('the baked list counts its slots', 1, TyImageCount(FBaked));
end;

procedure TImageDrawTest.SizeOfOurListIsWhatYouAskFor;
var sz: TSize;
begin
  { On demand: the answer is the question. A tree asking for a 37px slot gets a 37px icon. }
  sz := TyImageSizePx(FVector, 37, 96);
  AssertEquals('width is what was asked', 37, sz.cx);
  AssertEquals('height too', 37, sz.cy);
end;

procedure TImageDrawTest.SizeOfANilOrEmptyListReservesNoSlot;
var
  empty: TTyVirtualImageList;
begin
  empty := TTyVirtualImageList.Create(nil);
  try
    AssertEquals('an empty list reserves no width', 0, TyImageSizePx(empty, 24, 96).cx);
    AssertEquals('and no height', 0, TyImageSizePx(empty, 24, 96).cy);
  finally
    empty.Free;
  end;
end;

procedure TImageDrawTest.MeasuringABakedListDoesNotGrowIt;
var
  before: Integer;
  sz: TSize;
begin
  { THE measure trap. LCL's ResolutionForPPI creates a resolution for a width it lacks, so a
    layout pass done the obvious way grows the host's list, permanently. This helper only reads.
    Ask for a size that is NOT one of the registered [16,24,32,48]. }
  before := FBaked.ResolutionCount;
  AssertTrue('the baked list has resolutions', before > 0);
  sz := TyImageSizePx(FBaked, 20, 96);
  AssertTrue('measuring returned something', sz.cx > 0);
  AssertEquals('and it registered nothing new', before, FBaked.ResolutionCount);
  { A few more distinct drifting sizes -- the shape that sprays resolutions if it mutates. }
  TyImageSizePx(FBaked, 21, 96);
  TyImageSizePx(FBaked, 27, 96);
  TyImageSizePx(FBaked, 40, 120);
  AssertEquals('still nothing new after several odd sizes', before, FBaked.ResolutionCount);
end;

procedure TImageDrawTest.PutImageDrawsOurBranchInLayer;
var
  dest: TBGRABitmap;
  handled: Boolean;
begin
  dest := TBGRABitmap.Create(64, 64, BGRAPixelTransparent);
  try
    handled := TyPutImage(dest, FVector, 0, 4, 4, 24, False);
    AssertTrue('our branch is drawn in-layer, nothing owed', handled);
    { The icon actually landed -- 'red' is opaque, so there is ink where it was put. }
    AssertTrue('ink appeared in the layer', dest.GetPixel(16, 16).alpha > 40);
  finally
    dest.Free;
  end;
end;

procedure TImageDrawTest.PutImageDefersABakedList;
var
  dest: TBGRABitmap;
begin
  dest := TBGRABitmap.Create(64, 64, BGRAPixelTransparent);
  try
    { False = "still owed to the post-EndPaint pass". This is the one result that is NOT
      decoration: a caller that ignores it draws Ty icons and silently loses baked ones. }
    AssertFalse('a baked list is deferred', TyPutImage(dest, FBaked, 0, 4, 4, 16, False));
    AssertEquals('and nothing was drawn in-layer for it', 0, dest.GetPixel(8, 8).alpha);
  finally
    dest.Free;
  end;
end;

procedure TImageDrawTest.PutImageOnNothingIsDone;
var
  dest: TBGRABitmap;
begin
  dest := TBGRABitmap.Create(16, 16, BGRAPixelTransparent);
  try
    AssertTrue('nil list: nothing owed', TyPutImage(dest, nil, 0, 0, 0, 16, False));
    AssertTrue('bad index: nothing owed', TyPutImage(dest, FVector, 99, 0, 0, 16, False));
    AssertTrue('zero slot: nothing owed', TyPutImage(dest, FVector, 0, 0, 0, 0, False));
  finally
    dest.Free;
  end;
end;

procedure TImageDrawTest.PutImageAfterEndPaintReportsDoneAndDrawsNothing;
begin
  { The silent-failure mirror: after EndPaint the layer bitmap is gone, so ADest is nil. The
    contract is that this reports True (nothing owed) rather than crashing -- the caller was
    meant to use TyDrawImage past this point. }
  AssertTrue('a nil dest reports done, does not raise', TyPutImage(nil, FVector, 0, 0, 0, 16, False));
end;

procedure TImageDrawTest.GhostPolarityIsATableNotANot;
begin
  { The polarity that shipped "every icon disabled" twice. The table is indexed by GHOSTED:
    False must be the normal effect, True the disabled one. A `not` dropped anywhere flips
    both of these at once. }
  AssertTrue('not ghosted = normal', TyGhostEffect[False] = gdeNormal);
  AssertTrue('ghosted = disabled', TyGhostEffect[True] = gdeDisabled);
end;

procedure TImageDrawTest.BlitDrawsOurBranchInLayer;
var dest: TBGRABitmap;
begin
  { The simple-control path: both branches land in the layer, no deferral. Our branch is the
    same on-demand render as TyPutImage. }
  dest := TBGRABitmap.Create(64, 64, BGRAPixelTransparent);
  try
    TyBlitImage(dest, FVector, 0, 4, 4, 24, 96, False);
    AssertTrue('our icon landed in the layer', dest.GetPixel(16, 16).alpha > 40);
  finally
    dest.Free;
  end;
end;

procedure TImageDrawTest.BlitMaterialisesABakedListInLayer;
var dest: TBGRABitmap;
begin
  { THE new path this commit adds. A stock TImageList has no BGRA to borrow, so TyBlitImage
    materialises its resolution into the layer. This is the branch that lets a simple in-layer
    control accept a foreign list without a post-EndPaint pass. The baked sample's one image is
    solid red, so ink must appear where it is blitted. }
  dest := TBGRABitmap.Create(64, 64, BGRAPixelTransparent);
  try
    TyBlitImage(dest, FBaked, 0, 4, 4, 16, 96, False);
    AssertTrue('the foreign list was materialised into the layer',
      dest.GetPixel(10, 10).alpha > 40);
    AssertTrue('and it is the red image', dest.GetPixel(10, 10).red > 180);
  finally
    dest.Free;
  end;
end;

procedure TImageDrawTest.RenderReturnsAnOwnedBitmapOurBranch;
var bmp: TBGRABitmap;
begin
  { For a control that owns its scaling (TTyImage). Our branch renders the vector at the size
    asked, caller-owned. }
  bmp := TyRenderImage(FVector, 0, 40, 96, False);
  try
    AssertTrue('got a bitmap', bmp <> nil);
    AssertEquals('at the requested size', 40, bmp.Width);
    AssertTrue('with ink', bmp.GetPixel(20, 20).alpha > 40);
  finally
    bmp.Free;
  end;
end;

procedure TImageDrawTest.RenderMaterialisesABakedListToAnOwnedBitmap;
var bmp: TBGRABitmap;
begin
  { A foreign list materialised to an owned bitmap -- the same GetBitmap path TyBlitImage uses,
    but handed back for the caller to composite however it likes. }
  bmp := TyRenderImage(FBaked, 0, 16, 96, False);
  try
    AssertTrue('got a bitmap', bmp <> nil);
    AssertTrue('it is the red image', bmp.GetPixel(8, 8).red > 180);
  finally
    bmp.Free;
  end;
end;

procedure TImageDrawTest.NameResolvesBothWaysOnOurList;
begin
  { Ours carries Names ('red','green'), so a name maps to its slot and back. This is the primitive
    every ImageName-bearing control leans on: keep the name, derive the index. }
  AssertEquals('red is slot 0', 0, TyImageIndexOfName(FVector, 'red'));
  AssertEquals('green is slot 1', 1, TyImageIndexOfName(FVector, 'green'));
  AssertEquals('slot 0 is red', 'red', TyImageNameOfIndex(FVector, 0));
  AssertEquals('slot 1 is green', 'green', TyImageNameOfIndex(FVector, 1));
end;

procedure TImageDrawTest.NameResolutionIsInertOnAForeignList;
begin
  { A stock LCL list has no names. The helpers must NOT raise and must NOT invent a mapping -- a
    control assigned a foreign list simply keeps working by index. }
  AssertEquals('no name on a foreign list', -1, TyImageIndexOfName(FBaked, 'red'));
  AssertEquals('no name for a foreign slot', '', TyImageNameOfIndex(FBaked, 0));
end;

procedure TImageDrawTest.NameResolutionGuardsNilEmptyAndOutOfRange;
begin
  AssertEquals('nil list, by name', -1, TyImageIndexOfName(nil, 'red'));
  AssertEquals('nil list, by index', '', TyImageNameOfIndex(nil, 0));
  AssertEquals('empty name never matches', -1, TyImageIndexOfName(FVector, ''));
  AssertEquals('a negative index has no name', '', TyImageNameOfIndex(FVector, -1));
  AssertEquals('an index past the end has no name', '', TyImageNameOfIndex(FVector, 99));
end;

procedure TImageDrawTest.TheNameTracksTheImageAcrossAReorder;
begin
  { The whole reason a control keeps the NAME and not the index: reorder the list and the name
    still points at its own image, at a NEW index. An index-keyed control would now show the
    wrong icon; a name-keyed one follows the image. }
  FVector.Names.Text := 'green' + LineEnding + 'red';
  AssertEquals('green moved to slot 0', 0, TyImageIndexOfName(FVector, 'green'));
  AssertEquals('red moved to slot 1', 1, TyImageIndexOfName(FVector, 'red'));
  AssertEquals('slot 0 now names green', 'green', TyImageNameOfIndex(FVector, 0));
end;

initialization
  RegisterTest(TImageDrawTest);

end.
