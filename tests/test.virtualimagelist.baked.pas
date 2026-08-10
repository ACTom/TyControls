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
  Classes, SysUtils, Types, Graphics, ImgList, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.ImageCollection;

type
  TVirtualImageListBakedTest = class(TTestCase)
  private
    FColl: TTyImageCollection;
    FList: TTyVirtualImageList;
    procedure AddImage(const AName: string; AColor: TBGRAPixel);
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

procedure TVirtualImageListBakedTest.SetUp;
begin
  NeedWidgetSet;
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
  FList.Names.Text := 'red';
  before := FList.FillCount;
  FList.Names.Add('green');
  AssertTrue('a name change rebakes', FList.FillCount > before);
  AssertEquals('and the baked side followed', 2, FList.Count);
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
