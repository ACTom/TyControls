unit test.virtualimagelist.baked;
{$mode objfpc}{$H+}

{ TTyVirtualImageList after it became a TCustomImageList.

  The reparent adds a whole second identity to a class twenty-one properties point at, and
  every way it can go wrong is SILENT -- FPC issues no diagnostic for a method that hides a
  non-virtual inherited one, and none of the failures below would fail a compile or show up in
  an existing test. These are the guards for the three invariants the design rests on, each of
  which was a measured defect on a first patched build:

  ONE COUNT. `function Count` returning Names.Count HID the inherited property: the same object
  answered 2 through a TTyVirtualImageList reference and 0 through a TCustomImageList one. The
  function is gone and these pin that the two agree.

  COUNT IS A READ. TCustomImageList.Count routes through GetResolution(FWidth), and
  GetResolution CREATES a resolution for a width that is not registered -- so on a list whose
  base width was not registered, one bounds check rescales every image (measured:
  ResolutionCount 2 -> 3). ApplySize registers the base width first; this pins that.

  ONE SIZE. DefaultSize and Width were independent fields, so the same object drew at 20px
  through one reference type and 16px through the other -- silently, in the size a user sees.

  And the streaming guard, which is the one that would damage a user's files rather than their
  pixels: TCustomImageList wants to write a pixel blob into every .lfm. Dropping it OUTRIGHT
  (rather than emptying it) is what keeps an existing form byte-identical, and re-registering
  Left/Top by hand is what stops the component's designer position being lost with it. }

interface

uses
  Classes, SysUtils, Types, Graphics, GraphType, ImgList, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.ImageCollection;

type
  TVirtualImageListBakedTest = class(TTestCase)
  private
    FColl: TTyImageCollection;
    FList: TTyVirtualImageList;
    FAnnounced: Integer;
    FLinkFired: Integer;
    FCountWhenLinkFired: Integer;
    procedure AddImage(const AName: string; AColor: TBGRAPixel);
    procedure AddMaster(const AName: string; ASize: Integer; AColor: TBGRAPixel);
    { The centre pixel of a baked slot as $AARRGGBB, read from the list's own storage. This is
      what a stock LCL consumer gets; RenderIndex would ask the source and prove nothing. }
    function SlotArgb(AWidth, AIndex: Integer): Int64;
    procedure ListAnnounced(Sender: TObject);
    procedure LinkFired(Sender: TObject);
    procedure LinkAddsAName(Sender: TObject);
    function AddItem(const AName: string; AColor: TBGRAPixel): TTyImageItem;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheBakedCountAgreesWithTheNameCount;
    procedure BothReferenceTypesReportTheSameCount;
    procedure AskingForTheCountDoesNotGrowTheList;
    procedure DefaultSizeAndWidthAreOneState;
    procedure AnUnresolvableNameKeepsItsSlot;
    procedure SingleResolutionRegistersOnlyTheBase;
    procedure ChangingNamesRebakes;
    { #202: a name added at the end renders that name and nothing else. }
    procedure AddingNamesAtTheEndRebuildsNothing;
    procedure AnImageAddedBesideEachNameRebuildsNothing;
    procedure AddedNamesGetTheirOwnPictures;
    procedure AnAddedNameIsBakedAtEveryWidth;
    procedure ABracketedBatchAnnouncesOnce;
    procedure ALinkedConsumerSeesTheAddedImage;
    procedure InsertingAndDeletingKeepSlotsInStep;
    procedure AssigningTheSameNamesDoesNothing;
    procedure ANameAddedFromInsideARebuildGetsOneSlot;
    { ...and the slots it keeps must still be right: every route that changes what a name draws.
      Each test has only the affected name in the list, so no other route can rebuild it by luck. }
    procedure ReplacingAnImageRefreshesItsSlot;
    procedure NewPixelsOnAnItemRefreshItsSlot;
    procedure RenamingAnImageBlanksTheOldName;
    procedure RenamingAnImageFillsTheNewName;
    procedure DeletingAnImageBlanksItsSlot;
    procedure AddingAResolutionRefreshesItsSlot;
    procedure ReorderingTiedMastersRefreshesItsSlot;
    procedure AChangeFromBeforeTheBakeKeepsTheSlot;
    procedure AssigningOverAnItemBlanksItsOldName;
    procedure AssigningOverAnItemFillsItsNewName;
    procedure ClearingTheCollectionBlanksEverySlot;
    procedure ALateImageFillsItsBlankSlot;
    procedure LosingTheCollectionBlanksTheSlots;
    procedure ClearingTheBakedSideIsRepaired;
    procedure ResizingTheBakedSideIsRepaired;
    procedure ItStillRendersOnDemandAtAnySize;
    procedure NoPixelBlobReachesTheLfm;
    procedure TheDesignerPositionSurvivesStreaming;
    procedure ItReportsTheLibraryVersion;
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

procedure TVirtualImageListBakedTest.AddImage(const AName: string; AColor: TBGRAPixel);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(32, 32, AColor);
  try
    FColl.AddBitmap(AName, bmp);
  finally
    bmp.Free;
  end;
end;

procedure TVirtualImageListBakedTest.AddMaster(const AName: string; ASize: Integer;
  AColor: TBGRAPixel);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(ASize, ASize, AColor);
  try
    FColl.AddMasterBitmap(AName, bmp);
  finally
    bmp.Free;
  end;
end;

function TVirtualImageListBakedTest.SlotArgb(AWidth, AIndex: Integer): Int64;
var
  raw: TRawImage;
  p: PByte;
begin
  FList.Resolution[AWidth].GetRawImage(AIndex, raw);
  p := raw.Data + ((AWidth div 2) * AWidth + (AWidth div 2)) * 4;
  Result := (Int64(p[3]) shl 24) or (Int64(p[2]) shl 16) or (Int64(p[1]) shl 8) or Int64(p[0]);
end;

procedure TVirtualImageListBakedTest.ListAnnounced(Sender: TObject);
begin
  Inc(FAnnounced);
end;

procedure TVirtualImageListBakedTest.LinkFired(Sender: TObject);
begin
  Inc(FLinkFired);
  FCountWhenLinkFired := FList.Count;
end;

procedure TVirtualImageListBakedTest.LinkAddsAName(Sender: TObject);
begin
  Inc(FLinkFired);
  if FLinkFired = 1 then FList.Names.Add('red');
end;

function TVirtualImageListBakedTest.AddItem(const AName: string; AColor: TBGRAPixel): TTyImageItem;
var bmp: TBGRABitmap;
begin
  { Straight into Images, which is the only way to get two masters of one size under one name. }
  Result := FColl.Images.Add;
  Result.ImageName := AName;
  bmp := TBGRABitmap.Create(32, 32, AColor);
  try
    Result.SetBitmap(bmp);
  finally
    bmp.Free;
  end;
end;

procedure TVirtualImageListBakedTest.SetUp;
begin
  NeedWidgetSet;
  FAnnounced := 0;
  FLinkFired := 0;
  FCountWhenLinkFired := -1;
  FColl := TTyImageCollection.Create(nil);
  FList := TTyVirtualImageList.Create(nil);
  AddImage('red', BGRA(255, 0, 0, 255));
  AddImage('green', BGRA(0, 255, 0, 255));
  AddImage('blue', BGRA(0, 0, 255, 255));
  FList.Collection := FColl;
end;

procedure TVirtualImageListBakedTest.TearDown;
begin
  FList.Free;
  FColl.Free;
end;

procedure TVirtualImageListBakedTest.TheBakedCountAgreesWithTheNameCount;
begin
  FList.Names.Text := 'red' + LineEnding + 'green' + LineEnding + 'blue';
  AssertEquals('one baked image per name', FList.Names.Count, FList.Count);
end;

procedure TVirtualImageListBakedTest.BothReferenceTypesReportTheSameCount;
var
  asLcl: TCustomImageList;
begin
  { THE regression this class exists to prevent. With `function Count` still declared, this
    assertion read 3 against 0 -- and nothing in the compiler or the test suite said a word. }
  FList.Names.Text := 'red' + LineEnding + 'green' + LineEnding + 'blue';
  asLcl := FList;
  AssertEquals('the same object, the same count, whichever way it is held',
    FList.Count, asLcl.Count);
end;

procedure TVirtualImageListBakedTest.AskingForTheCountDoesNotGrowTheList;
var
  before, i: Integer;
begin
  { A bounds check must not mutate the thing it is checking. TCustomImageList.Count routes
    through GetResolution(FWidth), and GetResolution CREATES what it cannot find -- so on a
    list whose base width is unregistered, every `AIndex < Images.Count` in the library grows
    it. Twenty-six call sites do exactly that.

    WHAT THIS DOES AND DOES NOT GUARD, said plainly because two earlier versions of it were
    fake. I could not construct a failing case: removing the base width from ApplySize's
    RegisterResolutions call does NOT make this fail, because the fill itself asks for that
    width and normalises the list before any test can look. So this is not a guard against
    getting ApplySize's argument order wrong -- it is a guard against a future change that
    makes Count lazily create on the STEADY state, which is the shape that would grow without
    bound. That is worth pinning and this pins it; the registration order is documented in the
    class comment instead, where an unverifiable claim belongs. }
  FList.Names.Text := 'red' + LineEnding + 'green';
  AssertEquals('the count is right', 2, FList.Count);
  before := FList.ResolutionCount;
  AssertTrue('some resolutions exist', before > 0);
  for i := 1 to 5 do
    AssertEquals('the count stays right', 2, FList.Count);
  AssertEquals('and repeated bounds checks registered nothing new',
    before, FList.ResolutionCount);
end;

procedure TVirtualImageListBakedTest.DefaultSizeAndWidthAreOneState;
begin
  FList.Names.Text := 'red';
  FList.DefaultSize := 24;
  AssertEquals('DefaultSize is what was asked for', 24, FList.DefaultSize);
  AssertEquals('and Width is the same number', 24, FList.Width);
  AssertEquals('square', 24, FList.Height);
  { The failure this replaces: DefaultSize = 20 while Width = 16 on the same object, so it drew
    at two different sizes depending on how the caller had declared its variable. }
  AssertEquals('no divergence', FList.DefaultSize, FList.Width);
end;

procedure TVirtualImageListBakedTest.AnUnresolvableNameKeepsItsSlot;
var
  bmp: TBitmap;
begin
  { Several controls here carry hand-written index constants, so a fill that skipped a bad name
    would renumber everything after it -- silently, and only for the user whose icon is
    missing. }
  FList.Names.Text := 'red' + LineEnding + 'nope' + LineEnding + 'blue';
  AssertEquals('the bad name kept its slot', 3, FList.Count);
  bmp := TBitmap.Create;
  try
    FList.GetBitmap(2, bmp);
    AssertEquals('and slot 2 is still a real image', FList.Width, bmp.Width);
  finally
    bmp.Free;
  end;
end;

procedure TVirtualImageListBakedTest.SingleResolutionRegistersOnlyTheBase;
begin
  FList.MultiResolution := False;
  FList.Names.Text := 'red' + LineEnding + 'green';
  AssertEquals('one registered width', 1, FList.ResolutionCount);
  AssertEquals('still every name', 2, FList.Count);
end;

procedure TVirtualImageListBakedTest.ChangingNamesRebakes;
var before: Integer;
begin
  FList.Names.Text := 'red' + LineEnding + 'green';
  before := FList.FillCount;
  FList.Names[0] := 'blue';
  AssertTrue('changing a name rebuilds the list', FList.FillCount > before);
  AssertEquals('and the baked side followed', 2, FList.Count);
  AssertEquals('slot 0 draws the new name', $FF0000FF, SlotArgb(16, 0));
  AssertEquals('slot 1 is untouched', $FF00FF00, SlotArgb(16, 1));
end;

procedure TVirtualImageListBakedTest.AddingNamesAtTheEndRebuildsNothing;
var before: Integer;
begin
  { THE defect in #202. Each of these used to clear the list and render every name again at four
    widths, so a loop of N adds cost 2N^2 renders: 56 s for 100 Lucide icons. }
  before := FList.FillCount;
  FList.Names.Add('red');
  FList.Names.Add('green');
  FList.Names.Add('blue');
  AssertEquals('no add rebuilt the list', before, FList.FillCount);
  AssertEquals('the baked side still followed', 3, FList.Count);
end;

procedure TVirtualImageListBakedTest.AnImageAddedBesideEachNameRebuildsNothing;
var before: Integer;
begin
  { The natural raster loop: every pass changes the collection, so "the collection changed, start
    again" would leave this one quadratic. A NEW name cannot change what an old slot draws. }
  before := FList.FillCount;
  AddImage('one', BGRA(128, 0, 0, 255));
  FList.Names.Add('one');
  AddImage('two', BGRA(0, 128, 0, 255));
  FList.Names.Add('two');
  AddImage('three', BGRA(0, 0, 128, 255));
  FList.Names.Add('three');
  AssertEquals('no pass rebuilt the list', before, FList.FillCount);
  AssertEquals('every slot arrived', 3, FList.Count);
  AssertEquals('slot 0', $FF800000, SlotArgb(16, 0));
  AssertEquals('slot 2', $FF000080, SlotArgb(16, 2));
end;

procedure TVirtualImageListBakedTest.AddedNamesGetTheirOwnPictures;
begin
  FList.Names.Add('red');
  FList.Names.Add('green');
  FList.Names.Add('blue');
  AssertEquals('slot 0', $FFFF0000, SlotArgb(16, 0));
  AssertEquals('slot 1', $FF00FF00, SlotArgb(16, 1));
  AssertEquals('slot 2', $FF0000FF, SlotArgb(16, 2));
end;

procedure TVirtualImageListBakedTest.AnAddedNameIsBakedAtEveryWidth;
begin
  { A flat colour scales to itself, so these masters differ on purpose: a slot only shows the
    right colour at a width if that width was really rendered and not scaled from the base.
    The pick is the smallest master at least the width asked for. }
  AddMaster('multi', 16, BGRA(255, 0, 0, 255));
  AddMaster('multi', 32, BGRA(0, 255, 0, 255));
  AddMaster('multi', 48, BGRA(0, 0, 255, 255));
  FList.Names.Add('red');
  FList.Names.Add('multi');
  AssertEquals('16 uses the 16 master', $FFFF0000, SlotArgb(16, 1));
  AssertEquals('24 uses the 32 master', $FF00FF00, SlotArgb(24, 1));
  AssertEquals('32 uses the 32 master', $FF00FF00, SlotArgb(32, 1));
  AssertEquals('48 uses the 48 master', $FF0000FF, SlotArgb(48, 1));
end;

procedure TVirtualImageListBakedTest.ABracketedBatchAnnouncesOnce;
var before: Integer;
begin
  { What the docs tell people to write for a batch. }
  FList.AddHandlerOnChange(@ListAnnounced);
  before := FList.FillCount;
  FList.Names.BeginUpdate;
  try
    FList.Names.Add('red');
    FList.Names.Add('green');
    FList.Names.Add('blue');
    AssertEquals('nothing is baked inside the bracket', 0, FList.Count);
  finally
    FList.Names.EndUpdate;
  end;
  AssertEquals('one announcement for the whole batch', 1, FAnnounced);
  AssertEquals('no rebuild', before, FList.FillCount);
  AssertEquals('every slot arrived', 3, FList.Count);
end;

procedure TVirtualImageListBakedTest.ALinkedConsumerSeesTheAddedImage;
var link: TChangeLink;
begin
  { LCL controls and TTyTreeView learn about a change through a TChangeLink and nothing else. The
    rebuild told them while the list was empty; an add has to tell them with the image in place. }
  link := TChangeLink.Create;
  try
    link.OnChange := @LinkFired;
    FList.RegisterChanges(link);
    FList.Names.Add('red');
    AssertEquals('the consumer was told once', 1, FLinkFired);
    AssertEquals('and the new image was already there', 1, FCountWhenLinkFired);
    FList.UnRegisterChanges(link);
  finally
    link.Free;
  end;
end;

procedure TVirtualImageListBakedTest.InsertingAndDeletingKeepSlotsInStep;
begin
  FList.Names.Text := 'red' + LineEnding + 'green';
  FList.Names.Insert(0, 'blue');
  AssertEquals('three after the insert', 3, FList.Count);
  AssertEquals('slot 0 is the inserted name', $FF0000FF, SlotArgb(16, 0));
  AssertEquals('slot 1 moved along', $FFFF0000, SlotArgb(16, 1));
  AssertEquals('slot 2 moved along', $FF00FF00, SlotArgb(16, 2));
  FList.Names.Delete(1);
  AssertEquals('two after the delete', 2, FList.Count);
  AssertEquals('slot 0 stayed', $FF0000FF, SlotArgb(16, 0));
  AssertEquals('slot 1 closed up', $FF00FF00, SlotArgb(16, 1));
end;

procedure TVirtualImageListBakedTest.AssigningTheSameNamesDoesNothing;
var
  link: TChangeLink;
  before: Integer;
begin
  FList.Names.Text := 'red' + LineEnding + 'green';
  before := FList.FillCount;
  link := TChangeLink.Create;
  try
    link.OnChange := @LinkFired;
    FList.RegisterChanges(link);
    FList.Names.Text := 'red' + LineEnding + 'green';
    AssertEquals('nothing was rebuilt', before, FList.FillCount);
    AssertEquals('and consumers have nothing to redraw', 0, FLinkFired);
    FList.UnRegisterChanges(link);
  finally
    link.Free;
  end;
end;

procedure TVirtualImageListBakedTest.ANameAddedFromInsideARebuildGetsOneSlot;
var link: TChangeLink;
begin
  { A rebuild tells consumers from inside its Clear, with the slots empty and the names not yet
    baked. A name added at that moment must wait for the fill that is already running: baked on
    its own it would get a second slot from that fill and every later index would be off by one. }
  link := TChangeLink.Create;
  try
    link.OnChange := @LinkAddsAName;
    FList.RegisterChanges(link);
    FList.Refill;
    FList.UnRegisterChanges(link);
  finally
    link.Free;
  end;
  AssertEquals('the one name', 1, FList.Names.Count);
  AssertEquals('has one slot', 1, FList.Count);
end;

procedure TVirtualImageListBakedTest.ReplacingAnImageRefreshesItsSlot;
begin
  FList.Names.Text := 'red' + LineEnding + 'green';
  AddImage('red', BGRA(128, 0, 128, 255));
  FList.Names.Add('blue');
  AssertEquals('the replaced image', $FF800080, SlotArgb(16, 0));
  AssertEquals('the other slot', $FF00FF00, SlotArgb(16, 1));
  AssertEquals('the added slot', $FF0000FF, SlotArgb(16, 2));
end;

procedure TVirtualImageListBakedTest.NewPixelsOnAnItemRefreshItsSlot;
var bmp: TBGRABitmap;
begin
  FList.Names.Add('red');
  bmp := TBGRABitmap.Create(32, 32, BGRA(128, 0, 128, 255));
  try
    FColl.Images[0].SetBitmap(bmp);
  finally
    bmp.Free;
  end;
  FList.Names.Add('blue');
  AssertEquals('the item''s new pixels', $FF800080, SlotArgb(16, 0));
end;

procedure TVirtualImageListBakedTest.RenamingAnImageBlanksTheOldName;
begin
  FList.Names.Add('red');
  FColl.Images[0].ImageName := 'renamed';
  FList.Names.Add('blue');
  AssertEquals('the old name has nothing to draw', 0, SlotArgb(16, 0) shr 24);
end;

procedure TVirtualImageListBakedTest.RenamingAnImageFillsTheNewName;
begin
  FList.Names.Add('renamed');
  AssertEquals('nothing is called that yet', 0, SlotArgb(16, 0) shr 24);
  FColl.Images[0].ImageName := 'renamed';
  FList.Names.Add('blue');
  AssertEquals('the new name took the picture', $FFFF0000, SlotArgb(16, 0));
end;

procedure TVirtualImageListBakedTest.DeletingAnImageBlanksItsSlot;
begin
  FList.Names.Add('red');
  FColl.Images.Delete(0);
  FList.Names.Add('blue');
  AssertEquals('the deleted image is gone', 0, SlotArgb(16, 0) shr 24);
  AssertEquals('and the slot is still there', 2, FList.Count);
end;

procedure TVirtualImageListBakedTest.AddingAResolutionRefreshesItsSlot;
begin
  FList.Names.Add('red');
  AssertEquals('48 stretches the one master', $FFFF0000, SlotArgb(48, 0));
  AddMaster('red', 64, BGRA(0, 0, 255, 255));
  FList.Names.Add('green');
  AssertEquals('48 now scales down from the new master', $FF0000FF, SlotArgb(48, 0));
  AssertEquals('16 still picks the closer one', $FFFF0000, SlotArgb(16, 0));
end;

procedure TVirtualImageListBakedTest.ReorderingTiedMastersRefreshesItsSlot;
var
  first, second: TTyImageItem;
begin
  { Two masters of one size under one name: the pick keeps the first in authoring order, so moving
    one changes what the name draws. }
  first := AddItem('tie', BGRA(128, 0, 0, 255));
  second := AddItem('tie', BGRA(0, 128, 0, 255));
  FList.Names.Add('tie');
  AssertEquals('the first master wins', $FF800000, SlotArgb(16, 0));
  second.Index := first.Index;
  FList.Names.Add('red');
  AssertEquals('the other one is first now', $FF008000, SlotArgb(16, 0));
end;

procedure TVirtualImageListBakedTest.AChangeFromBeforeTheBakeKeepsTheSlot;
var
  first, second: TTyImageItem;
  before: Integer;
begin
  { Moving a master is the one change that records its name's stamp last, so the stamp can equal
    the one the bake recorded. The slot already shows that change and must not be rebuilt for it. }
  first := AddItem('tie', BGRA(128, 0, 0, 255));
  second := AddItem('tie', BGRA(0, 128, 0, 255));
  second.Index := first.Index;
  FList.Names.Add('tie');
  before := FList.FillCount;
  AddImage('new', BGRA(0, 0, 128, 255));
  FList.Names.Add('new');
  AssertEquals('the kept slot was already right', before, FList.FillCount);
end;

procedure TVirtualImageListBakedTest.AssigningOverAnItemBlanksItsOldName;
var src: TTyImageItem;
begin
  src := AddItem('other', BGRA(128, 0, 128, 255));
  FList.Names.Add('red');
  FColl.Images[0].Assign(src);
  FList.Names.Add('blue');
  AssertEquals('red lost its only master', 0, SlotArgb(16, 0) shr 24);
end;

procedure TVirtualImageListBakedTest.AssigningOverAnItemFillsItsNewName;
var src: TTyImageItem;
begin
  { Item 0 was 'red'. It becomes a 'green' that comes before the original, so it wins the tie. }
  src := AddItem('green', BGRA(128, 0, 128, 255));
  FList.Names.Add('green');
  AssertEquals('the original green wins for now', $FF00FF00, SlotArgb(16, 0));
  FColl.Images[0].Assign(src);
  FList.Names.Add('blue');
  AssertEquals('the earlier master wins now', $FF800080, SlotArgb(16, 0));
end;

procedure TVirtualImageListBakedTest.ClearingTheCollectionBlanksEverySlot;
begin
  FList.Names.Text := 'red' + LineEnding + 'green';
  FColl.Clear;
  AddImage('blue', BGRA(0, 0, 255, 255));
  FList.Names.Add('blue');
  AssertEquals('red is gone', 0, SlotArgb(16, 0) shr 24);
  AssertEquals('green is gone', 0, SlotArgb(16, 1) shr 24);
  AssertEquals('the new one is there', $FF0000FF, SlotArgb(16, 2));
end;

procedure TVirtualImageListBakedTest.ALateImageFillsItsBlankSlot;
begin
  FList.Names.Add('late');
  AssertEquals('nothing to draw yet', 0, SlotArgb(16, 0) shr 24);
  AddImage('late', BGRA(128, 0, 128, 255));
  FList.Names.Add('red');
  AssertEquals('the image arrived', $FF800080, SlotArgb(16, 0));
end;

procedure TVirtualImageListBakedTest.LosingTheCollectionBlanksTheSlots;
begin
  FList.Names.Add('red');
  FreeAndNil(FColl);
  FList.Names.Add('green');
  AssertEquals('the source is gone', 0, SlotArgb(16, 0) shr 24);
  AssertEquals('both slots are there', 2, FList.Count);
end;

procedure TVirtualImageListBakedTest.ClearingTheBakedSideIsRepaired;
begin
  { Clear is public on TCustomImageList, and a kept slot it has emptied cannot be appended to. }
  FList.Names.Text := 'red' + LineEnding + 'green';
  FList.Clear;
  FList.Names.Add('blue');
  AssertEquals('every name has its slot back', 3, FList.Count);
  AssertEquals('slot 0', $FFFF0000, SlotArgb(16, 0));
  AssertEquals('slot 2', $FF0000FF, SlotArgb(16, 2));
end;

procedure TVirtualImageListBakedTest.ResizingTheBakedSideIsRepaired;
begin
  { Width and Height are public and writing either empties the list. On an empty list the slot
    count cannot show it, so the size has to be checked on its own. }
  FList.Height := 32;
  FList.Names.Add('red');
  AssertEquals('height is back', 16, FList.Height);
  FList.Names.Clear;
  FList.Width := 32;
  FList.Names.Add('red');
  AssertEquals('width is back', 16, FList.Width);
  AssertEquals('and the slot is the right size', $FFFF0000, SlotArgb(16, 0));
end;

procedure TVirtualImageListBakedTest.ItStillRendersOnDemandAtAnySize;
var
  bmp: TBGRABitmap;
begin
  { The half that must NOT have been lost. Descending from TCustomImageList adds a baked
    identity; it does not take away the ability to rasterise at the exact size a paint asked
    for, which is the reason this library's own controls look right at any DPI and row height. }
  FList.Names.Text := 'red';
  bmp := FList.RenderIndex(0, 37);
  try
    AssertEquals('rendered at exactly the size asked for, not a registered one', 37, bmp.Width);
    AssertEquals(37, bmp.Height);
  finally
    bmp.Free;
  end;
end;

procedure TVirtualImageListBakedTest.NoPixelBlobReachesTheLfm;
var
  ms, asText: TMemoryStream;
  txt: TStringList;
  s: string;
begin
  { TCustomImageList.DefineProperties writes binary Bitmap/BitmapAdv whenever Count > 0. Left
    in place it would put a stale raster dump -- baked on whatever machine last saved the form,
    at that machine's DPI -- into every .lfm holding one of these. Emptying it via WriteData is
    NOT enough either: that still leaves `Bitmap = { }` behind and rewrites every existing
    form the first time the IDE saves it. }
  FList.Name := 'Icons';
  FList.Names.Text := 'red' + LineEnding + 'green';
  AssertTrue('there is something baked to write', FList.Count > 0);
  { Binary out, then ObjectBinaryToText -- the same route test.imagecollection.streaming
    uses, and it avoids the reader's class-name lookup entirely. }
  { Binary out, then ObjectBinaryToText -- the same route test.imagecollection.streaming
    uses, and it avoids the reader's class-name lookup entirely. }
  ms := TMemoryStream.Create;
  asText := TMemoryStream.Create;
  txt := TStringList.Create;
  try
    ms.WriteComponent(FList);
    ms.Position := 0;
    ObjectBinaryToText(ms, asText);
    asText.Position := 0;
    txt.LoadFromStream(asText);
    s := txt.Text;
    AssertTrue('no pixel blob: ' + s, Pos('Bitmap', s) = 0);
    AssertTrue('and none of the multi-resolution one either: ' + s, Pos('BitmapAdv', s) = 0);
  finally
    txt.Free;
    asText.Free;
    ms.Free;
  end;
end;

procedure TVirtualImageListBakedTest.TheDesignerPositionSurvivesStreaming;
var
  ms: TMemoryStream;
  back: TTyVirtualImageList;
  di: LongInt;
begin
  { The cost of suppressing the blob through DefineProperties is that TComponent's Left/Top --
    where the designer keeps a non-visual component's icon position -- go with it unless they
    are re-registered by hand. Without this the icon snaps back to 0,0 on every reopen. }
  FList.Name := 'Icons';
  di := 0;
  LongRec(di).Lo := 123;
  LongRec(di).Hi := 45;
  FList.DesignInfo := di;
  ms := TMemoryStream.Create;
  back := TTyVirtualImageList.Create(nil);
  try
    ms.WriteComponent(FList);
    ms.Position := 0;
    ms.ReadComponent(back);     { into an EXISTING instance -- no class lookup }
    AssertEquals('designer Left survived', 123, LongRec(back.DesignInfo).Lo);
    AssertEquals('designer Top survived', 45, LongRec(back.DesignInfo).Hi);
  finally
    back.Free;
    ms.Free;
  end;
end;

procedure TVirtualImageListBakedTest.ItReportsTheLibraryVersion;
begin
  { TCustomImageList publishes nothing at all, so this property had to be re-declared when the
    ancestry changed -- and its design-time editor separately re-registered. }
  AssertEquals(TyVersion, FList.Version);
end;

initialization
  RegisterTest(TVirtualImageListBakedTest);

end.
