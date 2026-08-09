unit test.lclimagelist;
{$mode objfpc}{$H+}

{ The bridge from this library's icons to a stock LCL TCustomImageList.

  These tests are mostly about the things that make a BRIDGE different from a list:

  DENSE AND ORDER-PRESERVING. Index i in the bridge must be index i in Source.Names, including
  when a name resolves to nothing. Several controls here carry hand-written index constants
  (TTyShellTreeView's folder=0/drive=1/file=2), and a fill that skipped a bad name would
  renumber everything after it -- silently, and only for the user whose icon happened to be
  missing.

  THE TRIGGERS. A bridge that does not refill is worse than no bridge: it shows the icons the
  form had when it loaded and never mentions that they changed. Each trigger is asserted on
  FillCount, because Count cannot tell "refilled with the same names" from "did not refill".

  WHAT IS NOT TESTED HERE, and why: whether a stock LCL control DRAWS these correctly. That
  needs a widgetset and a window. The contract this can honestly pin is that the list is
  populated, ordered, sized and invalidated -- everything up to LCL's own paint. }

interface

uses
  Classes, SysUtils, Types, Graphics, ImgList, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.IconFont, tyControls.ImageCollection,
  tyControls.LCLImageList;

type
  TLCLImageListTest = class(TTestCase)
  private
    FColl: TTyImageCollection;
    FList: TTyVirtualImageList;
    FBridge: TTyLCLImageList;
    procedure AddImage(const AName: string; AColor: TBGRAPixel);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AnEmptySourceLeavesAnEmptyList;
    procedure EveryNameGetsASlot;
    procedure AnUnresolvableNameStillTakesItsSlot;
    procedure TheBaseWidthIsWhatWasAskedFor;
    procedure MultiResolutionRegistersTheLadder;
    procedure SingleResolutionRegistersOnlyTheBase;
    procedure ChangingNamesRefills;
    procedure ChangingTheSourceRefills;
    procedure ChangingTheWidthRefills;
    procedure FreeingTheSourceEmptiesTheBridge;
    procedure WritingWidthDirectlyIsNotHowYouResize;
    procedure TheBridgeReportsTheLibraryVersion;
  end;

implementation

uses
  Forms;

{ Rendering a glyph needs a widgetset for the font, and the console runner never calls
  Application.Initialize -- the same one-shot init test.virtualimagelist.iconfont uses. }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TLCLImageListTest.AddImage(const AName: string; AColor: TBGRAPixel);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(32, 32, AColor);
  try
    FColl.AddBitmap(AName, bmp);
  finally
    bmp.Free;
  end;
end;

procedure TLCLImageListTest.SetUp;
begin
  NeedWidgetSet;
  FColl := TTyImageCollection.Create(nil);
  FList := TTyVirtualImageList.Create(nil);
  FBridge := TTyLCLImageList.Create(nil);
  AddImage('red', BGRA(255, 0, 0, 255));
  AddImage('green', BGRA(0, 255, 0, 255));
  AddImage('blue', BGRA(0, 0, 255, 255));
  FList.Collection := FColl;
end;

procedure TLCLImageListTest.TearDown;
begin
  FBridge.Free;
  FList.Free;
  FColl.Free;
end;

procedure TLCLImageListTest.AnEmptySourceLeavesAnEmptyList;
begin
  AssertEquals('no source, no images', 0, FBridge.Count);
  FBridge.Source := FList;              { source set, but Names is empty }
  AssertEquals('empty source, no images', 0, FBridge.Count);
end;

procedure TLCLImageListTest.EveryNameGetsASlot;
begin
  FList.Names.Text := 'red' + LineEnding + 'green' + LineEnding + 'blue';
  FBridge.Source := FList;
  AssertEquals('one image per name', 3, FBridge.Count);
end;

procedure TLCLImageListTest.AnUnresolvableNameStillTakesItsSlot;
var
  bmp: TBitmap;
begin
  { The property the index constants in this library depend on. 'nope' resolves to nothing, and
    if the fill skipped it then 'blue' would answer to index 1 instead of 2 -- a silent
    renumbering that only happens for the user whose icon is missing. }
  FList.Names.Text := 'red' + LineEnding + 'nope' + LineEnding + 'blue';
  FBridge.Source := FList;
  AssertEquals('the bad name kept its slot', 3, FBridge.Count);
  bmp := TBitmap.Create;
  try
    FBridge.GetBitmap(0, bmp);
    AssertEquals('slot 0 is a real image', FBridge.Width, bmp.Width);
    FBridge.GetBitmap(2, bmp);
    AssertEquals('and so is slot 2 -- nothing shifted', FBridge.Width, bmp.Width);
  finally
    bmp.Free;
  end;
end;

procedure TLCLImageListTest.TheBaseWidthIsWhatWasAskedFor;
begin
  FList.Names.Text := 'red';
  FBridge.ImageWidth := 24;
  FBridge.Source := FList;
  AssertEquals('the base width', 24, FBridge.Width);
  AssertEquals('square', 24, FBridge.Height);
end;

procedure TLCLImageListTest.MultiResolutionRegistersTheLadder;
begin
  { 16 / 24 / 32 / 48 covers LCL's own 100..300% buckets, so Scaled picks a pre-rendered one
    per monitor instead of upscaling the base. }
  FList.Names.Text := 'red';
  FBridge.ImageWidth := 16;
  FBridge.Source := FList;
  AssertEquals('four registered widths', 4, FBridge.ResolutionCount);
  AssertEquals('base', 16, FBridge.ResolutionByIndex[0].Width);
  AssertEquals('150%', 24, FBridge.ResolutionByIndex[1].Width);
  AssertEquals('200%', 32, FBridge.ResolutionByIndex[2].Width);
  AssertEquals('300%', 48, FBridge.ResolutionByIndex[3].Width);
end;

procedure TLCLImageListTest.SingleResolutionRegistersOnlyTheBase;
begin
  { The opt-out exists because TTyTreeView paints through Images.Draw -> GetResolution(FWidth)
    and never pulls another resolution, so for a tree the other three are rendered for nothing. }
  FList.Names.Text := 'red' + LineEnding + 'green';
  FBridge.MultiResolution := False;
  FBridge.ImageWidth := 16;
  FBridge.Source := FList;
  AssertEquals('one registered width', 1, FBridge.ResolutionCount);
  AssertEquals('still every name', 2, FBridge.Count);
end;

procedure TLCLImageListTest.ChangingNamesRefills;
var before: Integer;
begin
  FList.Names.Text := 'red';
  FBridge.Source := FList;
  before := FBridge.FillCount;
  { The ordinary way to use the component -- and before the multicast was added, this changed
    what the source exposes and told nobody at all. }
  FList.Names.Add('green');
  AssertTrue('the bridge was told', FBridge.FillCount > before);
  AssertEquals('and picked up the new name', 2, FBridge.Count);
end;

procedure TLCLImageListTest.ChangingTheSourceRefills;
var
  other: TTyVirtualImageList;
  before: Integer;
begin
  FList.Names.Text := 'red';
  FBridge.Source := FList;
  before := FBridge.FillCount;
  other := TTyVirtualImageList.Create(nil);
  try
    other.Collection := FColl;
    other.Names.Text := 'red' + LineEnding + 'green' + LineEnding + 'blue';
    FBridge.Source := other;
    AssertTrue('refilled', FBridge.FillCount > before);
    AssertEquals('from the new source', 3, FBridge.Count);
    { And the old source must no longer drive it, or two lists would fight over one bridge. }
    before := FBridge.FillCount;
    FList.Names.Add('blue');
    AssertEquals('the detached source is silent', before, FBridge.FillCount);
  finally
    FBridge.Source := nil;
    other.Free;
  end;
end;

procedure TLCLImageListTest.ChangingTheWidthRefills;
var before: Integer;
begin
  FList.Names.Text := 'red';
  FBridge.Source := FList;
  before := FBridge.FillCount;
  FBridge.ImageWidth := 32;
  AssertTrue('refilled', FBridge.FillCount > before);
  AssertEquals('at the new size', 32, FBridge.Width);
  AssertEquals('with the images still there', 1, FBridge.Count);
end;

procedure TLCLImageListTest.FreeingTheSourceEmptiesTheBridge;
var
  other: TTyVirtualImageList;
begin
  other := TTyVirtualImageList.Create(nil);
  other.Collection := FColl;
  other.Names.Text := 'red' + LineEnding + 'green';
  FBridge.Source := other;
  AssertEquals('filled', 2, FBridge.Count);
  { FreeNotification must both nil the reference and clear the images -- a bridge still holding
    rasters for a source that no longer exists is a list whose ImageIndexes mean nothing. }
  FreeAndNil(other);
  AssertTrue('reference dropped', FBridge.Source = nil);
  AssertEquals('and the images with it', 0, FBridge.Count);
end;

procedure TLCLImageListTest.WritingWidthDirectlyIsNotHowYouResize;
begin
  { Width and Height stay PUBLIC on TCustomImageList and both CLEAR the list when written. The
    component cannot stop that, so the behaviour is pinned rather than pretended away: this is
    what ImageWidth exists to be used instead of. }
  FList.Names.Text := 'red' + LineEnding + 'green';
  FBridge.Source := FList;
  AssertEquals('filled', 2, FBridge.Count);
  FBridge.Width := 20;
  AssertEquals('writing the inherited Width wipes the images -- use ImageWidth',
    0, FBridge.Count);
  FBridge.ImageWidth := 20;
  AssertEquals('and ImageWidth puts them back', 2, FBridge.Count);
end;

procedure TLCLImageListTest.TheBridgeReportsTheLibraryVersion;
begin
  { TCustomImageList publishes nothing at all, so Version has to be re-declared -- test.version
    requires it of every registered class, and this is the assertion that fails first if the
    re-declaration is ever dropped. }
  AssertEquals(TyVersion, FBridge.Version);
end;

initialization
  RegisterTest(TLCLImageListTest);

end.
