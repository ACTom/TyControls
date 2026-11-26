unit test.filedialog.places;
{$mode objfpc}{$H+}

{ #246: the places of the file dialogs.

  The list of places (tyControls.ShellPlaces) and the recent folders (tyControls.FileSystem)
  are held against inputs made for the test: nothing here depends on which folders this
  machine has, except where a test says the machine's own list is what it reads. The pane,
  the folder drop-down and the dialogs are then handed such lists and asked what they show
  and where they go. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, Dialogs, LCLType, fpcunit, testregistry,
  LazFileUtils, FileUtil, BGRABitmap, BGRABitmapTypes,
  tyControls.ListView, tyControls.ListView.Layout,
  tyControls.FileSystem, tyControls.StrConsts, tyControls.ShellPlaces, tyControls.ShellIcons,
  tyControls.ShellPlacesView, tyControls.ShellComboBox, tyControls.ShellTreeView,
  tyControls.ImageCollection, tyControls.TreeView,
  tyControls.Dialogs.FileDialog, tyControls.Dialogs.SelectPath;

type
  { Saves the process's recent folders and their limit around every test, and gives each a
    folder of its own to make folders in. }
  TPlacesTestBase = class(TTestCase)
  private
    FSavedRecent: string;
    FSavedLimit: Integer;
  protected
    FTemp: string;
    function Dir(const AName: string): string;   // made under FTemp
    procedure SetUp; override;
    procedure TearDown; override;
  end;

  { tyControls.FileSystem: the picture of a place, the recent folders }
  TPlaceIconAndRecentTest = class(TPlacesTestBase)
  published
    procedure APlaceWithoutAPictureGetsTheOneItsKindSays;
    procedure APictureOfItsOwnWins;
    procedure TheCommonFoldersCarryTheirOwnPictures;
    procedure TheRecentFoldersStartEmptyAndAreOneList;
    procedure TheLatestFolderHeadsTheList;
    procedure AFolderNotedAgainMovesToTheHead;
    procedure ATrailingDelimiterIsNotASecondFolder;
    procedure TheListKeepsNoMoreThanTheLimit;
    procedure ALimitOfNoneKeepsNone;
    procedure AnEmptyNameIsNotNoted;
  end;

  { tyControls.ShellIcons: the pictures }
  TPlaceIconsTest = class(TTestCase)
  private
    FIcons: TTyImageCollection;
    FImages: TTyVirtualImageList;
    function Pix(AIcon: TTyFsPlaceIcon; X, Y: Integer): TBGRAPixel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure EachPictureHasANameAndAPlaceInTheList;
    procedure ThePicturesAreAddedAfterWhatIsThere;
    procedure EachPictureIsTheOneItsNameSays;
  end;

  { tyControls.ShellPlaces: the list }
  TFilePlacesListTest = class(TPlacesTestBase)
  private
    FList: TTyFilePlaces;
    function Paths: string;   // the paths, blank-joined
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure APlaceIsListedUnderItsFoldersName;
    procedure ARootIsListedUnderItsName;
    procedure ACaptionOfItsOwnWins;
    procedure ATrailingDelimiterIsRemoved;
    procedure APlaceWithoutAPictureIsAFolder;
    procedure InsertPutsThePlaceWhereAsked;
    procedure DeleteAndMove;
    procedure AnIndexOutOfBoundsRaises;
    procedure IndexOfComparesAsFileNamesDo;
    procedure TheHeadingsAreInTheOrderTheyAreFirstMet;
    procedure GroupTogetherKeepsTheOrderWithinAHeading;
    procedure ThePlacesUnderNoHeadingComeLast;
    procedure AssignCopies;
  end;

  { tyControls.ShellPlaces: the standard places }
  TStandardPlacesTest = class(TPlacesTestBase)
  private
    FList: TTyFilePlaces;
    FKnown, FRoots: TTyFsRootArray;
    FPinned, FRecent: TStringList;
    function Shown: string;   // 'heading:caption' of each place, blank-joined
    procedure Known(const APath, ADisplay: string; AIcon: TTyFsPlaceIcon);
    procedure Root(const APath, ADisplay: string; AKind: TTyFsRootKind);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheHomeFolderAndThenTheCommonFolders;
    procedure TheOrderIsPlacesPinnedRecentDevices;
    procedure TheHomeFolderHeadsThePlacesUnderItsName;
    procedure EachPlaceHasItsPicture;
    procedure APinnedFolderIsListedOnce;
    procedure APinnedFolderThatIsACommonFolderIsListedAllTheSame;
    procedure BlankLinesArePassedOver;
    procedure ARecentFolderListedElsewhereIsLeftOut;
    procedure ARecentFolderThatIsADriveIsLeftOut;
    procedure TheRecentLimitCountsWhatIsShown;
    procedure TheListIsClearedFirst;
    procedure OnThisMachineAMissingFolderIsLeftOut;
    procedure OnThisMachineRecentFoldersAreOptional;
    procedure OnThisMachineTheRecentLimitApplies;
  end;

  { TTyShellPlacesView }
  TPlacesViewTest = class(TPlacesTestBase)
  private
    FForm: TForm;
    FView: TTyShellPlacesView;
    FList: TTyFilePlaces;
    FChosen: TStringList;
    procedure Chose(Sender: TObject);
    procedure Click(AIndex: Integer);
    procedure Show3;   // a, b under 'One'; c under 'Two'
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ItShowsEveryPlace;
    procedure ARowSaysTheCaptionAndHasThePicture;
    procedure ARowIsUnderItsHeading;
    procedure AHeadingSaysItsCaptionAlone;
    procedure ThePlacesAreBroughtTogetherByHeading;
    procedure TheCurrentFolderIsHighlightedWhenItIsAPlace;
    procedure NoPlaceIsHighlightedWhenItIsNot;
    procedure WritingTheCurrentFolderFiresNothing;
    procedure AClickChoosesThePlace;
    procedure AClickOnTheCurrentFolderChoosesNothing;
    procedure AClickBelowTheLastPlaceChoosesNothing;
    procedure EnterChoosesTheHighlightedPlace;
    procedure AnArrowKeyMovesTheHighlightOnly;
    procedure NewPlacesKeepTheCurrentFolderHighlighted;
    procedure NoPlacesShowNothing;
    procedure TheSameNumberOfOtherPlacesIsLaidOutAfresh;
    procedure ARightClickChoosesNothing;
    procedure ADisabledPaneChoosesNothing;
    procedure TheOneColumnIsAsWideAsThePane;
    procedure ThereIsNoColumnHeaderAndThePicturesAreItsOwn;
    procedure APlainListViewStillCountsItsGroups;
    procedure TheHeadingsDrawnAreTheOnesThePaneGives;
  end;

  { the folder drop-down }
  TLookInWithPlacesTest = class(TPlacesTestBase)
  private
    FList: TTyFilePlaces;
    function Rows(const A: TTyLookInPlaceArray): string;   // 'depth:display', blank-joined
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheChainComesFirstAndThenThePlaces;
    procedure APlaceRowCarriesItsPicture;
    procedure TheDriveOfTheChainIsNotListedTwice;
    procedure AFolderPlaceOnTheChainIsListedAllTheSame;
    procedure WithoutADirectoryThePlacesAreAllThereIs;
    procedure TheBoxListsThePlacesItIsGiven;
    procedure TheBoxGoesBackToTheRoots;
    procedure ThePlacePicturesFollowTheTwoOldOnes;
    procedure InAPlaceTheFieldShowsItsNameAndPicture;
    procedure OutsideAPlaceTheFieldShowsTheFolder;
  end;

  { the open and save dialogs }
  TFileDialogPlacesTest = class(TPlacesTestBase)
  private
    FForm: TTyFileDialogForm;
    FEvents: Integer;
    FSender: TObject;
    procedure AddAPlace(Sender: TObject; APlaces: TTyFilePlaces);
    procedure AddToThePlaces(Sender: TObject; APlaces: TTyFilePlaces);
    procedure DropTheRest(Sender: TObject; APlaces: TTyFilePlaces);
    procedure KeepOpen(Sender: TObject; var ACanClose: Boolean);
    procedure Build;
    function Accept(const AName: string): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheLeftPaneIsThePlaces;
    procedure ThePaneAndTheDropDownShowTheSamePlaces;
    procedure TheFolderTreeOnRequest;
    procedure NoLeftPaneOnRequest;
    procedure BackToThePlaces;
    procedure ThePaneFollowsTheListIntoAPlace;
    procedure ThePaneHighlightsNothingOutsideThePlaces;
    procedure ChoosingAPlaceGoesThere;
    procedure TheTreeFollowsWhenItIsBuiltLater;
    procedure APinnedFolderIsAmongThePlaces;
    procedure OnPlacesMayAdd;
    procedure OnPlacesMayRemove;
    procedure OnPlacesSaysTheFormWhenThereIsNoComponent;
    procedure AnAcceptedDialogNotesItsFolder;
    procedure ARefusedDialogNotesNothing;
    procedure ACancelledDialogNotesNothing;
    procedure WithoutRecentFoldersNothingIsNotedOrShown;
    procedure TheRecentFolderIsShownTheNextTime;
    procedure ChoosingInTheTreeGoesThere;
    procedure ATreeBuiltBeforeAnyFolderIsShown;
    procedure WhatOnPlacesAddsGoesUnderItsHeading;
    procedure ADialogTheProgramKeepsOpenNotesNothing;
    procedure ANameTypedWithItsFolderNotesThatFolder;
  end;

  { the dialog components }
  TFileDialogComponentPlacesTest = class(TPlacesTestBase)
  private
    FEvents: Integer;
    FSender: TObject;
    procedure Places(Sender: TObject; APlaces: TTyFilePlaces);
    function Streamed(AComp: TComponent): string;
  published
    procedure TheDefaults;
    procedure TheFormIsBuiltWithWhatTheComponentSays;
    procedure OnPlacesFiresOnceABuildAndSaysTheComponent;
    procedure TheDefaultsAreNotWritten;
    procedure WhatIsSetIsWrittenAndReadBack;
  end;

  { the folder picker }
  TSelectPathPlacesTest = class(TPlacesTestBase)
  published
    procedure TheCommonFoldersAreAboveTheDrives;
    procedure APlaceIsListedUnderItsName;
    procedure ARootedPickerListsItsRootAlone;
    procedure GoingToAPlaceSelectsItsOwnNode;
    procedure APlaceIsShownUnderItsNameWithItsPicture;
    procedure TheHomeFolderIsAPlaceWhereThereIsOne;
  end;

implementation

type
  TViewAccess = class(TTyShellPlacesView)
  public
    function XText(AIndex: Integer): string;
    function XTextIn(AIndex, AColumn: Integer): string;
    function XImageIn(AIndex, AColumn: Integer): Integer;
    function XImage(AIndex: Integer): Integer;
    function XGroup(AIndex: Integer): Integer;
    function XHeading(AGroup: Integer): string;
    procedure XMouseDown(X, Y: Integer);
    procedure XRightDown(X, Y: Integer);
    procedure XKey(AKey: Word);
  end;

  TListAccess = class(TTyListView)
  public
    function XHeading(AGroup: Integer): string;
  end;

  { A pane that notes which headings the list asked for while it drew. }
  TDrawnHeadings = class(TTyShellPlacesView)
  protected
    function GroupHeaderCaption(AGroup: Integer): string; override;
  public
    Asked: string;
    procedure Draw;
  end;

  { The picker with places made for the test in place of the machine's. }
  TProbePicker = class(TTySelectPathForm)
  public
    Probe: TTyFsRootArray;
    UseProbe: Boolean;
    function TopPlaces: TTyFsRootArray; override;
    function XImage(ANode: PTyTreeNode): Integer;
  end;

  TComboAccess = class(TTyShellComboBox)
  public
    function XFieldCaption: string;
    function XFieldGlyph: Integer;
  end;

  { The dialog form with its message boxes swapped out: a refused name is refused silently. }
  TQuietFileDialog = class(TTyFileDialogForm)
  protected
    procedure ReportProblem(const AMsg: string); override;
    function ConfirmChoice(const AMsg: string): Boolean; override;
  end;

function TViewAccess.XText(AIndex: Integer): string;
begin
  Result := GetItemText(AIndex, 0);
end;

function TViewAccess.XTextIn(AIndex, AColumn: Integer): string;
begin
  Result := GetItemText(AIndex, AColumn);
end;

function TViewAccess.XImageIn(AIndex, AColumn: Integer): Integer;
begin
  Result := GetItemImageIndex(AIndex, AColumn);
end;

function TViewAccess.XImage(AIndex: Integer): Integer;
begin
  Result := GetItemImageIndex(AIndex, 0);
end;

function TViewAccess.XGroup(AIndex: Integer): Integer;
begin
  Result := GetItemGroup(AIndex);
end;

function TViewAccess.XHeading(AGroup: Integer): string;
begin
  Result := GroupHeaderCaption(AGroup);
end;

procedure TViewAccess.XMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

procedure TViewAccess.XKey(AKey: Word);
begin
  KeyDown(AKey, []);
end;

procedure TViewAccess.XRightDown(X, Y: Integer);
begin
  MouseDown(mbRight, [ssRight], X, Y);
end;

function TDrawnHeadings.GroupHeaderCaption(AGroup: Integer): string;
begin
  Result := inherited GroupHeaderCaption(AGroup);
  Asked := Asked + Result + ';';
end;

procedure TDrawnHeadings.Draw;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(Width, Height);
    RenderTo(bmp.Canvas, Rect(0, 0, Width, Height), 96);
  finally
    bmp.Free;
  end;
end;

function TListAccess.XHeading(AGroup: Integer): string;
begin
  Result := GroupHeaderCaption(AGroup);
end;

function TProbePicker.TopPlaces: TTyFsRootArray;
begin
  if UseProbe then Result := Probe else Result := inherited TopPlaces;
end;

function TProbePicker.XImage(ANode: PTyTreeNode): Integer;
var
  ghosted: Boolean;
begin
  Result := -1;
  ghosted := False;
  Tree.OnGetImageIndex(Tree, ANode, ikNormal, 0, ghosted, Result);
end;

function TComboAccess.XFieldCaption: string;
begin
  Result := FieldCaption;
end;

function TComboAccess.XFieldGlyph: Integer;
begin
  Result := FieldGlyph;
end;

procedure TQuietFileDialog.ReportProblem(const AMsg: string);
begin
end;

function TQuietFileDialog.ConfirmChoice(const AMsg: string): Boolean;
begin
  Result := True;
end;

{ TPlacesTestBase }

procedure TPlacesTestBase.SetUp;
begin
  inherited SetUp;
  FSavedRecent := TyRecentFolders.Text;
  FSavedLimit := TyRecentFoldersLimit;
  TyRecentFolders.Clear;
  TyRecentFoldersLimit := 5;
  FTemp := ChompPathDelim(AppendPathDelim(GetTempDir) + 'tyfdplaces_' + IntToStr(GetProcessID)
    + '_' + IntToStr(Random(MaxInt)));
  ForceDirectoriesUTF8(FTemp);
end;

procedure TPlacesTestBase.TearDown;
begin
  if (FTemp <> '') and DirectoryExistsUTF8(FTemp) then
    DeleteDirectory(FTemp, False);
  TyRecentFoldersLimit := FSavedLimit;
  TyRecentFolders.Text := FSavedRecent;
  inherited TearDown;
end;

function TPlacesTestBase.Dir(const AName: string): string;
begin
  Result := FTemp + PathDelim + AName;
  ForceDirectoriesUTF8(Result);
end;

{ TPlaceIconAndRecentTest }

procedure TPlaceIconAndRecentTest.APlaceWithoutAPictureGetsTheOneItsKindSays;
var
  r: TTyFsRoot;
begin
  r.Path := 'x'; r.Display := 'x'; r.Icon := fpiByKind;
  r.Kind := rkDrive;
  AssertEquals('a drive', Ord(fpiDrive), Ord(TyFsPlaceIconOf(r)));
  r.Kind := rkRoot;
  AssertEquals('the root of the file system', Ord(fpiDrive), Ord(TyFsPlaceIconOf(r)));
  r.Kind := rkVolume;
  AssertEquals('a mounted volume', Ord(fpiDrive), Ord(TyFsPlaceIconOf(r)));
  r.Kind := rkHome;
  AssertEquals('the home folder', Ord(fpiHome), Ord(TyFsPlaceIconOf(r)));
  r.Kind := rkPlace;
  AssertEquals('a curated place', Ord(fpiFolder), Ord(TyFsPlaceIconOf(r)));
end;

procedure TPlaceIconAndRecentTest.APictureOfItsOwnWins;
var
  r: TTyFsRoot;
begin
  r.Path := 'x'; r.Display := 'x'; r.Kind := rkDrive; r.Icon := fpiMusic;
  AssertEquals(Ord(fpiMusic), Ord(TyFsPlaceIconOf(r)));
end;

procedure TPlaceIconAndRecentTest.TheCommonFoldersCarryTheirOwnPictures;
const
  cFile =
    'XDG_VIDEOS_DIR="$HOME/V"'#10'XDG_MUSIC_DIR="$HOME/M"'#10'XDG_PICTURES_DIR="$HOME/P"'#10 +
    'XDG_DOWNLOAD_DIR="$HOME/Dl"'#10'XDG_DOCUMENTS_DIR="$HOME/Doc"'#10'XDG_DESKTOP_DIR="$HOME/Desk"'#10;
  cWant: array[0..5] of TTyFsPlaceIcon = (fpiDesktop, fpiDocuments, fpiDownloads, fpiPictures,
    fpiMusic, fpiVideos);
var
  r: TTyFsRootArray;
  i: Integer;
begin
  r := TyFsParseUserDirs(cFile, '/home/u');
  AssertEquals('all six', 6, Length(r));
  for i := 0 to 5 do
    AssertEquals(r[i].Display, Ord(cWant[i]), Ord(r[i].Icon));
end;

procedure TPlaceIconAndRecentTest.TheRecentFoldersStartEmptyAndAreOneList;
begin
  AssertEquals('emptied by SetUp', 0, TyRecentFolders.Count);
  AssertSame('one list for the process', TyRecentFolders, TyRecentFolders);
end;

procedure TPlaceIconAndRecentTest.TheLatestFolderHeadsTheList;
begin
  TyNoteRecentFolder(FTemp + PathDelim + 'a');
  TyNoteRecentFolder(FTemp + PathDelim + 'b');
  AssertEquals(2, TyRecentFolders.Count);
  AssertEquals('the latest first', FTemp + PathDelim + 'b', TyRecentFolders[0]);
  AssertEquals(FTemp + PathDelim + 'a', TyRecentFolders[1]);
end;

procedure TPlaceIconAndRecentTest.AFolderNotedAgainMovesToTheHead;
begin
  TyNoteRecentFolder(FTemp + PathDelim + 'a');
  TyNoteRecentFolder(FTemp + PathDelim + 'b');
  TyNoteRecentFolder(FTemp + PathDelim + 'a');
  AssertEquals('listed once', 2, TyRecentFolders.Count);
  AssertEquals(FTemp + PathDelim + 'a', TyRecentFolders[0]);
  AssertEquals(FTemp + PathDelim + 'b', TyRecentFolders[1]);
end;

procedure TPlaceIconAndRecentTest.ATrailingDelimiterIsNotASecondFolder;
begin
  TyNoteRecentFolder(FTemp + PathDelim + 'a');
  TyNoteRecentFolder(FTemp + PathDelim + 'a' + PathDelim);
  AssertEquals(1, TyRecentFolders.Count);
  AssertEquals('kept without it', FTemp + PathDelim + 'a', TyRecentFolders[0]);
  { One that got in with a delimiter -- a list the program loaded -- is found too. }
  TyRecentFolders.Text := FTemp + PathDelim + 'b' + PathDelim;
  TyNoteRecentFolder(FTemp + PathDelim + 'b');
  AssertEquals('the loaded one is the same folder', 1, TyRecentFolders.Count);
end;

procedure TPlaceIconAndRecentTest.TheListKeepsNoMoreThanTheLimit;
var
  i: Integer;
begin
  TyRecentFoldersLimit := 3;
  for i := 1 to 5 do
    TyNoteRecentFolder(FTemp + PathDelim + IntToStr(i));
  AssertEquals(3, TyRecentFolders.Count);
  AssertEquals('the latest three, latest first', FTemp + PathDelim + '5', TyRecentFolders[0]);
  AssertEquals(FTemp + PathDelim + '3', TyRecentFolders[2]);
end;

procedure TPlaceIconAndRecentTest.ALimitOfNoneKeepsNone;
begin
  TyRecentFoldersLimit := 0;
  TyNoteRecentFolder(FTemp + PathDelim + 'a');
  AssertEquals(0, TyRecentFolders.Count);
end;

procedure TPlaceIconAndRecentTest.AnEmptyNameIsNotNoted;
begin
  TyNoteRecentFolder('');
  TyNoteRecentFolder('   ');
  AssertEquals(0, TyRecentFolders.Count);
end;

{ TPlaceIconsTest }

procedure TPlaceIconsTest.SetUp;
begin
  inherited SetUp;
  FIcons := TTyImageCollection.Create(nil);
  FImages := TTyVirtualImageList.Create(nil);
  FImages.Collection := FIcons;
  TyAddPlaceIcons(FIcons, FImages.Names);
end;

procedure TPlaceIconsTest.TearDown;
begin
  FImages.Free;
  FIcons.Free;
  inherited TearDown;
end;

function TPlaceIconsTest.Pix(AIcon: TTyFsPlaceIcon; X, Y: Integer): TBGRAPixel;
var
  bmp: TBGRABitmap;
begin
  bmp := FImages.CachedIndex(TyPlaceIconIndex(AIcon), 128);   // borrowed
  AssertNotNull(TyPlaceIconName(AIcon), bmp);
  Result := bmp.GetPixel(X, Y);
end;

procedure TPlaceIconsTest.EachPictureHasANameAndAPlaceInTheList;
var
  a, b: TTyFsPlaceIcon;
begin
  AssertEquals('no picture is left to the kind', '', TyPlaceIconName(fpiByKind));
  for a := fpiFolder to High(TTyFsPlaceIcon) do
  begin
    AssertTrue('a name', TyPlaceIconName(a) <> '');
    for b := fpiFolder to High(TTyFsPlaceIcon) do
      if a <> b then
        AssertTrue('of its own', TyPlaceIconName(a) <> TyPlaceIconName(b));
    AssertEquals('in the order of the type', Ord(a) - Ord(fpiFolder), TyPlaceIconIndex(a));
    AssertEquals('after what the list had', Ord(a) - Ord(fpiFolder) + 2, TyPlaceIconIndex(a, 2));
    AssertEquals('and that is where its name is', TyPlaceIconName(a),
      FImages.Names[TyPlaceIconIndex(a)]);
  end;
  AssertEquals('a place without a picture is drawn as a folder', TyPlaceIconIndex(fpiFolder),
    TyPlaceIconIndex(fpiByKind));
  AssertEquals(TyPlaceIconIndex(fpiFolder, 2), TyPlaceIconIndex(fpiByKind, 2));
  AssertEquals('nine in all', 9, FImages.Names.Count);
  { The names are what a program asks an image list for: each says what its picture is. }
  AssertEquals('place-folder', TyPlaceIconName(fpiFolder));
  AssertEquals('place-drive', TyPlaceIconName(fpiDrive));
  AssertEquals('place-home', TyPlaceIconName(fpiHome));
  AssertEquals('place-desktop', TyPlaceIconName(fpiDesktop));
  AssertEquals('place-documents', TyPlaceIconName(fpiDocuments));
  AssertEquals('place-downloads', TyPlaceIconName(fpiDownloads));
  AssertEquals('place-pictures', TyPlaceIconName(fpiPictures));
  AssertEquals('place-music', TyPlaceIconName(fpiMusic));
  AssertEquals('place-videos', TyPlaceIconName(fpiVideos));
end;

procedure TPlaceIconsTest.ThePicturesAreAddedAfterWhatIsThere;
var
  names: TStringList;
  icons: TTyImageCollection;
begin
  names := TStringList.Create;
  icons := TTyImageCollection.Create(nil);
  try
    names.Add('mine');
    TyAddPlaceIcons(icons, names);
    AssertEquals(10, names.Count);
    AssertEquals('mine', names[0]);
    AssertEquals(TyPlaceIconName(fpiFolder), names[1]);
    AssertEquals(TyPlaceIconName(fpiVideos), names[9]);
    TyAddPlaceIcons(icons, nil);   // no list of names to keep: the collection alone
  finally
    icons.Free;
    names.Free;
  end;
end;

{ One tell-tale pixel or two of each 128 px master: what the picture IS, so that a name
  cannot end up on another drawing. }
procedure TPlaceIconsTest.EachPictureIsTheOneItsNameSays;
var
  c: TBGRAPixel;
begin
  c := Pix(fpiFolder, 64, 80);
  AssertTrue('folder: amber', (c.alpha > 200) and (c.red > c.green) and (c.green > c.blue));
  c := Pix(fpiDrive, 60, 95);
  AssertTrue('drive: steel blue', (c.alpha > 200) and (c.blue > c.green) and (c.green > c.red));
  AssertEquals('drive: a low box, nothing above it', 0, Pix(fpiDrive, 64, 20).alpha);
  c := Pix(fpiHome, 40, 100);
  AssertTrue('home: a blue wall', (c.alpha > 200) and (c.blue > c.green) and (c.green > c.red));
  AssertTrue('home: a roof above it', Pix(fpiHome, 64, 30).alpha > 200);
  AssertEquals('home: and nothing beside the roof''s tip', 0, Pix(fpiHome, 10, 20).alpha);
  c := Pix(fpiDesktop, 64, 55);
  AssertTrue('desktop: a bright screen', (c.alpha > 200) and (c.blue > 220) and (c.red < 140));
  AssertTrue('desktop: on a foot', Pix(fpiDesktop, 64, 108).alpha > 200);
  c := Pix(fpiDocuments, 64, 38);
  AssertTrue('documents: a line of writing', (c.red > 230) and (c.green > 230) and (c.blue > 230));
  c := Pix(fpiDocuments, 64, 20);
  AssertTrue('documents: on a blue sheet', (c.alpha > 200) and (c.blue > c.red));
  c := Pix(fpiDownloads, 64, 40);
  AssertTrue('downloads: green', (c.alpha > 200) and (c.green > c.red) and (c.green > c.blue));
  c := Pix(fpiPictures, 40, 46);
  AssertTrue('pictures: a yellow sun', (c.red > 230) and (c.green > 190) and (c.blue < 130));
  c := Pix(fpiMusic, 38, 96);
  AssertTrue('music: a pink note', (c.alpha > 200) and (c.red > c.blue) and (c.blue > c.green));
  c := Pix(fpiVideos, 30, 40);
  AssertTrue('videos: purple', (c.alpha > 200) and (c.blue > c.red) and (c.red > c.green));
  c := Pix(fpiVideos, 62, 64);
  AssertTrue('videos: with a white play mark', (c.red > 225) and (c.green > 225) and (c.blue > 225));
end;

{ TFilePlacesListTest }

procedure TFilePlacesListTest.SetUp;
begin
  inherited SetUp;
  FList := TTyFilePlaces.Create;
end;

procedure TFilePlacesListTest.TearDown;
begin
  FList.Free;
  inherited TearDown;
end;

function TFilePlacesListTest.Paths: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FList.Count - 1 do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + FList[i].Path;
  end;
end;

procedure TFilePlacesListTest.APlaceIsListedUnderItsFoldersName;
begin
  AssertEquals('the index it got', 0, FList.Add(FTemp + PathDelim + 'reports', 'G'));
  AssertEquals('reports', FList[0].Caption);
  AssertEquals('G', FList[0].Group);
  AssertEquals(FTemp + PathDelim + 'reports', FList[0].Path);
  AssertEquals('the next one', 1, FList.Add(FTemp + PathDelim + 'x'));
  AssertEquals('under no heading unless told', '', FList[1].Group);
end;

procedure TFilePlacesListTest.ARootIsListedUnderItsName;
begin
  { #250: a root has no last part to be listed as. It is listed under its name, 'C:', the
    name the Devices group and the folder picker show it by -- not under its path. }
  {$IFDEF MSWINDOWS}
  FList.Add('C:\');
  AssertEquals('a drive: its name', 'C:', FList[0].Caption);
  AssertEquals('a root keeps its delimiter', 'C:\', FList[0].Path);
  {$ELSE}
  FList.Add('/');
  AssertEquals('/', FList[0].Caption);
  AssertEquals('/', FList[0].Path);
  {$ENDIF}
end;

procedure TFilePlacesListTest.ACaptionOfItsOwnWins;
begin
  FList.Add(FTemp + PathDelim + 'reports', 'G', 'Quarterly');
  AssertEquals('Quarterly', FList[0].Caption);
end;

procedure TFilePlacesListTest.ATrailingDelimiterIsRemoved;
begin
  FList.Add('  ' + FTemp + PathDelim + 'reports' + PathDelim + ' ');
  AssertEquals(FTemp + PathDelim + 'reports', FList[0].Path);
  AssertEquals('and the name is still the folder''s', 'reports', FList[0].Caption);
end;

procedure TFilePlacesListTest.APlaceWithoutAPictureIsAFolder;
var
  p: TTyFilePlace;
begin
  FList.Add(FTemp, '', '', fpiByKind);
  AssertEquals('added', Ord(fpiFolder), Ord(FList[0].Icon));
  FList.Add(FTemp, '', '', fpiMusic);
  AssertEquals('one that was given is kept', Ord(fpiMusic), Ord(FList[1].Icon));
  p := FList[1];
  p.Icon := fpiByKind;
  FList[1] := p;
  AssertEquals('written', Ord(fpiFolder), Ord(FList[1].Icon));
end;

procedure TFilePlacesListTest.InsertPutsThePlaceWhereAsked;
begin
  FList.Add('a');
  FList.Add('c');
  FList.Insert(1, 'b', 'G', 'Bee', fpiHome);
  AssertEquals('a b c', Paths);
  AssertEquals('Bee', FList[1].Caption);
  AssertEquals('G', FList[1].Group);
  AssertEquals(Ord(fpiHome), Ord(FList[1].Icon));
  FList.Insert(0, 'first');
  FList.Insert(FList.Count, 'last');
  AssertEquals('first a b c last', Paths);
end;

procedure TFilePlacesListTest.DeleteAndMove;
begin
  FList.Add('a'); FList.Add('b'); FList.Add('c'); FList.Add('d');
  FList.Delete(1);
  AssertEquals('a c d', Paths);
  FList.Move(0, 2);
  AssertEquals('down', 'c d a', Paths);
  FList.Move(2, 0);
  AssertEquals('and up again', 'a c d', Paths);
  FList.Move(1, 1);
  AssertEquals('to where it is', 'a c d', Paths);
  FList.Delete(2);
  FList.Delete(0);
  AssertEquals('c', Paths);
  FList.Clear;
  AssertEquals(0, FList.Count);
end;

procedure TFilePlacesListTest.AnIndexOutOfBoundsRaises;
var
  raised: Integer;
  p: TTyFilePlace;
begin
  FList.Add('a');
  raised := 0;
  try p := FList[1]; except on EListError do Inc(raised); end;
  try p := FList[-1]; except on EListError do Inc(raised); end;
  try FList.Delete(1); except on EListError do Inc(raised); end;
  try FList.Move(0, 1); except on EListError do Inc(raised); end;
  try FList.Move(1, 0); except on EListError do Inc(raised); end;
  try FList.Insert(2, 'x'); except on EListError do Inc(raised); end;
  try FList.Insert(-1, 'x'); except on EListError do Inc(raised); end;
  p.Path := 'z'; p.Caption := 'z'; p.Group := ''; p.Icon := fpiFolder;
  try FList[1] := p; except on EListError do Inc(raised); end;
  AssertEquals('all eight', 8, raised);
  AssertEquals('and nothing changed', 1, FList.Count);
end;

procedure TFilePlacesListTest.IndexOfComparesAsFileNamesDo;
begin
  FList.Add(FTemp + PathDelim + 'One');
  FList.Add(FTemp + PathDelim + 'Two');
  FList.Add(FTemp + PathDelim + 'Two');
  AssertEquals('the first of two', 1, FList.IndexOf(FTemp + PathDelim + 'Two'));
  AssertEquals('a trailing delimiter is the same folder', 0,
    FList.IndexOf(FTemp + PathDelim + 'One' + PathDelim));
  AssertEquals(-1, FList.IndexOf(FTemp + PathDelim + 'Three'));
  if FilenamesCaseSensitive then
    AssertEquals('case counts here', -1, FList.IndexOf(FTemp + PathDelim + 'one'))
  else
    AssertEquals('case does not count here', 0, FList.IndexOf(FTemp + PathDelim + 'one'));
end;

procedure TFilePlacesListTest.TheHeadingsAreInTheOrderTheyAreFirstMet;
var
  g: TStringArray;
begin
  FList.Add('a', 'Two');
  FList.Add('b');
  FList.Add('c', 'One');
  FList.Add('d', 'Two');
  g := FList.Groups;
  AssertEquals('each once, none for the place under no heading', 2, Length(g));
  AssertEquals('Two', g[0]);
  AssertEquals('One', g[1]);
end;

procedure TFilePlacesListTest.GroupTogetherKeepsTheOrderWithinAHeading;
begin
  FList.Add('a', 'Two');
  FList.Add('b', 'One');
  FList.Add('c', 'Two');
  FList.Add('d', 'One');
  FList.Add('e', 'Two');
  FList.GroupTogether;
  AssertEquals('a c e b d', Paths);
  AssertEquals('Two', FList[2].Group);
  AssertEquals('One', FList[3].Group);
end;

procedure TFilePlacesListTest.ThePlacesUnderNoHeadingComeLast;
begin
  FList.Add('a');
  FList.Add('b', 'One');
  FList.Add('c');
  FList.GroupTogether;
  AssertEquals('b a c', Paths);
end;

procedure TFilePlacesListTest.AssignCopies;
var
  other: TTyFilePlaces;
  p: TTyFilePlace;
begin
  other := TTyFilePlaces.Create;
  try
    FList.Add('a', 'G', 'A', fpiHome);
    other.Add('gone');
    other.Assign(FList);
    AssertEquals(1, other.Count);
    AssertEquals('A', other[0].Caption);
    AssertEquals(Ord(fpiHome), Ord(other[0].Icon));
    FList.Add('b');
    AssertEquals('a copy, not the same list', 1, other.Count);
    other.Assign(FList);
    p := FList[0];
    p.Caption := 'changed';
    FList[0] := p;
    AssertEquals('a place changed in the one is not changed in the other', 'A', other[0].Caption);
    other.Assign(nil);
    AssertEquals('nothing assigned is nothing', 0, other.Count);
  finally
    other.Free;
  end;
end;

{ TStandardPlacesTest }

procedure TStandardPlacesTest.SetUp;
begin
  inherited SetUp;
  FList := TTyFilePlaces.Create;
  FPinned := TStringList.Create;
  FRecent := TStringList.Create;
  FKnown := nil;
  FRoots := nil;
end;

procedure TStandardPlacesTest.TearDown;
begin
  FRecent.Free;
  FPinned.Free;
  FList.Free;
  inherited TearDown;
end;

procedure TStandardPlacesTest.Known(const APath, ADisplay: string; AIcon: TTyFsPlaceIcon);
begin
  SetLength(FKnown, Length(FKnown) + 1);
  FKnown[High(FKnown)].Path := APath;
  FKnown[High(FKnown)].Display := ADisplay;
  FKnown[High(FKnown)].Kind := rkPlace;
  FKnown[High(FKnown)].Icon := AIcon;
end;

procedure TStandardPlacesTest.Root(const APath, ADisplay: string; AKind: TTyFsRootKind);
begin
  SetLength(FRoots, Length(FRoots) + 1);
  FRoots[High(FRoots)].Path := APath;
  FRoots[High(FRoots)].Display := ADisplay;
  FRoots[High(FRoots)].Kind := AKind;
end;

function TStandardPlacesTest.Shown: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FList.Count - 1 do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + FList[i].Group + ':' + FList[i].Caption;
  end;
end;

procedure TStandardPlacesTest.TheHomeFolderAndThenTheCommonFolders;
var
  r: TTyFsRootArray;
begin
  Root(PathDelim + 'r', 'R', rkRoot);
  Root(PathDelim + 'home' + PathDelim + 'tom', 'tom', rkHome);
  Root(PathDelim + 'vol', 'Vol', rkVolume);
  Known(PathDelim + 'home' + PathDelim + 'tom' + PathDelim + 'D', 'Documents', fpiDocuments);
  r := TyFsHomeAndKnown(FRoots, FKnown);
  AssertEquals('the home folder and the one common folder: no drive, no volume', 2, Length(r));
  AssertEquals(PathDelim + 'home' + PathDelim + 'tom', r[0].Path);
  AssertEquals('under the name for it, not the folder''s', rsFdPlaceHome, r[0].Display);
  AssertEquals('still the home folder: the house', Ord(fpiHome), Ord(TyFsPlaceIconOf(r[0])));
  AssertEquals('Documents', r[1].Display);
  AssertEquals(Ord(fpiDocuments), Ord(r[1].Icon));
  AssertEquals('nothing in, nothing out', 0, Length(TyFsHomeAndKnown(nil, nil)));
end;

procedure TStandardPlacesTest.TheOrderIsPlacesPinnedRecentDevices;
begin
  Root(PathDelim + 'r', 'R', rkRoot);
  Root(PathDelim + 'vol', 'Vol', rkVolume);
  Known(PathDelim + 'h' + PathDelim + 'Docs', 'Documents', fpiDocuments);
  Known(PathDelim + 'h' + PathDelim + 'Mus', 'Music', fpiMusic);
  FPinned.Add(PathDelim + 'p' + PathDelim + 'project');
  FRecent.Add(PathDelim + 'q' + PathDelim + 'last');
  TyStandardFilePlaces(FList, FKnown, FRoots, FPinned, FRecent);
  AssertEquals(
    rsFdGroupPlaces + ':Documents ' + rsFdGroupPlaces + ':Music ' +
    rsFdGroupPinned + ':project ' + rsFdGroupRecent + ':last ' +
    rsFdGroupDevices + ':R ' + rsFdGroupDevices + ':Vol', Shown);
  AssertEquals('the folders themselves', PathDelim + 'p' + PathDelim + 'project', FList[2].Path);
  AssertEquals(PathDelim + 'vol', FList[5].Path);
end;

procedure TStandardPlacesTest.TheHomeFolderHeadsThePlacesUnderItsName;
begin
  Root(PathDelim + 'r', 'R', rkRoot);
  Root(PathDelim + 'home' + PathDelim + 'tom', 'tom', rkHome);
  Known(PathDelim + 'home' + PathDelim + 'tom' + PathDelim + 'D', 'Documents', fpiDocuments);
  TyStandardFilePlaces(FList, FKnown, FRoots, nil, nil);
  AssertEquals(rsFdGroupPlaces + ':' + rsFdPlaceHome + ' ' + rsFdGroupPlaces + ':Documents ' +
    rsFdGroupDevices + ':R', Shown);
  AssertEquals('the home folder is not a device too', 3, FList.Count);
  AssertEquals(PathDelim + 'home' + PathDelim + 'tom', FList[0].Path);
end;

procedure TStandardPlacesTest.EachPlaceHasItsPicture;
begin
  Root(PathDelim + 'r', 'R', rkRoot);
  Root(PathDelim + 'h', 'h', rkHome);
  Known(PathDelim + 'h' + PathDelim + 'M', 'Music', fpiMusic);
  FPinned.Add(PathDelim + 'p');
  FRecent.Add(PathDelim + 'q');
  TyStandardFilePlaces(FList, FKnown, FRoots, FPinned, FRecent);
  AssertEquals('home', Ord(fpiHome), Ord(FList[0].Icon));
  AssertEquals('a common folder: its own', Ord(fpiMusic), Ord(FList[1].Icon));
  AssertEquals('pinned: a folder', Ord(fpiFolder), Ord(FList[2].Icon));
  AssertEquals('recent: a folder', Ord(fpiFolder), Ord(FList[3].Icon));
  AssertEquals('a device: a drive', Ord(fpiDrive), Ord(FList[4].Icon));
end;

procedure TStandardPlacesTest.APinnedFolderIsListedOnce;
begin
  FPinned.Add(PathDelim + 'p' + PathDelim + 'one');
  FPinned.Add(PathDelim + 'p' + PathDelim + 'two');
  FPinned.Add(PathDelim + 'p' + PathDelim + 'one' + PathDelim);
  TyStandardFilePlaces(FList, FKnown, FRoots, FPinned, nil);
  AssertEquals(rsFdGroupPinned + ':one ' + rsFdGroupPinned + ':two', Shown);
end;

procedure TStandardPlacesTest.APinnedFolderThatIsACommonFolderIsListedAllTheSame;
begin
  Known(PathDelim + 'h' + PathDelim + 'Docs', 'Documents', fpiDocuments);
  FPinned.Add(PathDelim + 'h' + PathDelim + 'Docs');
  TyStandardFilePlaces(FList, FKnown, FRoots, FPinned, nil);
  AssertEquals(rsFdGroupPlaces + ':Documents ' + rsFdGroupPinned + ':Docs', Shown);
end;

procedure TStandardPlacesTest.BlankLinesArePassedOver;
begin
  FPinned.Add('');
  FPinned.Add('   ');
  FPinned.Add(PathDelim + 'p');
  FRecent.Add('');
  FRecent.Add(PathDelim + 'q');
  TyStandardFilePlaces(FList, FKnown, FRoots, FPinned, FRecent);
  AssertEquals(rsFdGroupPinned + ':p ' + rsFdGroupRecent + ':q', Shown);
end;

procedure TStandardPlacesTest.ARecentFolderListedElsewhereIsLeftOut;
begin
  Root(PathDelim + 'h', 'h', rkHome);
  Known(PathDelim + 'h' + PathDelim + 'Docs', 'Documents', fpiDocuments);
  FPinned.Add(PathDelim + 'p');
  FRecent.Add(PathDelim + 'h' + PathDelim + 'Docs' + PathDelim);   // a common folder
  FRecent.Add(PathDelim + 'p');                                    // a pinned one
  FRecent.Add(PathDelim + 'h');                                    // the home folder
  FRecent.Add(PathDelim + 'q');
  FRecent.Add(PathDelim + 'q');                                    // itself, twice
  TyStandardFilePlaces(FList, FKnown, FRoots, FPinned, FRecent);
  AssertEquals(rsFdGroupPlaces + ':' + rsFdPlaceHome + ' ' + rsFdGroupPlaces + ':Documents ' +
    rsFdGroupPinned + ':p ' + rsFdGroupRecent + ':q', Shown);
end;

procedure TStandardPlacesTest.ARecentFolderThatIsADriveIsLeftOut;
begin
  Root(PathDelim + 'vol', 'Vol', rkVolume);
  FRecent.Add(PathDelim + 'vol');
  FRecent.Add(PathDelim + 'vol' + PathDelim + 'sub');
  TyStandardFilePlaces(FList, FKnown, FRoots, nil, FRecent);
  AssertEquals('the drive is among the devices only; a folder on it is recent',
    rsFdGroupRecent + ':sub ' + rsFdGroupDevices + ':Vol', Shown);
end;

procedure TStandardPlacesTest.TheRecentLimitCountsWhatIsShown;
begin
  Known(PathDelim + 'h' + PathDelim + 'Docs', 'Documents', fpiDocuments);
  FRecent.Add(PathDelim + 'h' + PathDelim + 'Docs');   // left out: not one of the two
  FRecent.Add(PathDelim + 'a');
  FRecent.Add(PathDelim + 'b');
  FRecent.Add(PathDelim + 'c');
  TyStandardFilePlaces(FList, FKnown, FRoots, nil, FRecent, 2);
  AssertEquals(rsFdGroupPlaces + ':Documents ' + rsFdGroupRecent + ':a ' + rsFdGroupRecent + ':b',
    Shown);
  TyStandardFilePlaces(FList, FKnown, FRoots, nil, FRecent, 0);
  AssertEquals('none', rsFdGroupPlaces + ':Documents', Shown);
  TyStandardFilePlaces(FList, FKnown, FRoots, nil, FRecent);
  AssertEquals('no limit given: all', 4, FList.Count);
end;

procedure TStandardPlacesTest.TheListIsClearedFirst;
begin
  FList.Add('stale');
  TyStandardFilePlaces(FList, FKnown, FRoots, nil, nil);
  AssertEquals(0, FList.Count);
end;

procedure TStandardPlacesTest.OnThisMachineAMissingFolderIsLeftOut;
var
  here: string;
begin
  here := Dir('pinned');
  FPinned.Add(here);
  FPinned.Add(FTemp + PathDelim + 'not-there');
  TyRecentFolders.Add(FTemp + PathDelim + 'gone');
  TyRecentFolders.Add(Dir('recent'));
  TyFillFilePlaces(FList, FPinned, True);
  AssertTrue('the pinned folder that exists', FList.IndexOf(here) >= 0);
  AssertEquals(rsFdGroupPinned, FList[FList.IndexOf(here)].Group);
  AssertEquals('the one that does not', -1, FList.IndexOf(FTemp + PathDelim + 'not-there'));
  AssertTrue('the recent folder that exists', FList.IndexOf(FTemp + PathDelim + 'recent') >= 0);
  AssertEquals(rsFdGroupRecent, FList[FList.IndexOf(FTemp + PathDelim + 'recent')].Group);
  AssertEquals('the one that is gone', -1, FList.IndexOf(FTemp + PathDelim + 'gone'));
  AssertEquals('it stays in the list all the same: the drive may be back', 2, TyRecentFolders.Count);
  AssertEquals('the machine''s own places are there', Length(TyFsKnownFolders) + Length(TyFsRoots) + 2,
    FList.Count);
end;

procedure TStandardPlacesTest.OnThisMachineRecentFoldersAreOptional;
begin
  TyRecentFolders.Add(Dir('recent'));
  TyFillFilePlaces(FList, nil, False);
  AssertEquals(-1, FList.IndexOf(FTemp + PathDelim + 'recent'));
  TyFillFilePlaces(FList, nil, True);
  AssertTrue(FList.IndexOf(FTemp + PathDelim + 'recent') >= 0);
end;

procedure TStandardPlacesTest.OnThisMachineTheRecentLimitApplies;
begin
  { A list the program loaded may be longer than the limit. }
  TyRecentFolders.Add(Dir('r1'));
  TyRecentFolders.Add(Dir('r2'));
  TyRecentFolders.Add(Dir('r3'));
  TyRecentFoldersLimit := 2;
  TyFillFilePlaces(FList, nil, True);
  AssertTrue(FList.IndexOf(FTemp + PathDelim + 'r1') >= 0);
  AssertTrue(FList.IndexOf(FTemp + PathDelim + 'r2') >= 0);
  AssertEquals('the third is beyond it', -1, FList.IndexOf(FTemp + PathDelim + 'r3'));
end;

{ TPlacesViewTest }

procedure TPlacesViewTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 500);
  FView := TTyShellPlacesView.Create(FForm);
  FView.Parent := FForm;
  FView.SetBounds(0, 0, 200, 400);
  FView.OnSelectPath := @Chose;
  FList := TTyFilePlaces.Create;
  FChosen := TStringList.Create;
end;

procedure TPlacesViewTest.TearDown;
begin
  FChosen.Free;
  FList.Free;
  FForm.Free;
  inherited TearDown;
end;

procedure TPlacesViewTest.Chose(Sender: TObject);
begin
  FChosen.Add(FView.SelectedPath);
end;

procedure TPlacesViewTest.Show3;
begin
  FList.Add(PathDelim + 'x' + PathDelim + 'a', 'One', 'A', fpiHome);
  FList.Add(PathDelim + 'x' + PathDelim + 'b', 'One', 'B', fpiMusic);
  FList.Add(PathDelim + 'x' + PathDelim + 'c', 'Two', 'C', fpiDrive);
  FView.SetPlaces(FList);
end;

{ A click in the middle of place AIndex's row, found by asking the view where its rows are. }
procedure TPlacesViewTest.Click(AIndex: Integer);
var
  y, first, last: Integer;
begin
  first := -1;
  last := -1;
  for y := 0 to FView.Height - 1 do
    if FView.GetItemAt(20, y) = AIndex then
    begin
      if first < 0 then first := y;
      last := y;
    end;
  AssertTrue('place ' + IntToStr(AIndex) + ' has a row', first >= 0);
  TViewAccess(FView).XMouseDown(20, (first + last) div 2);
end;

procedure TPlacesViewTest.ItShowsEveryPlace;
begin
  Show3;
  AssertEquals(3, FView.PlaceCount);
  AssertEquals('C', FView.PlaceAt(2).Caption);
  AssertEquals(PathDelim + 'x' + PathDelim + 'c', FView.PlaceAt(2).Path);
end;

procedure TPlacesViewTest.ARowSaysTheCaptionAndHasThePicture;
begin
  Show3;
  AssertEquals('A', TViewAccess(FView).XText(0));
  AssertEquals('B', TViewAccess(FView).XText(1));
  AssertEquals('the last one too', 'C', TViewAccess(FView).XText(2));
  AssertEquals('there is one column: a second has no text', '', TViewAccess(FView).XTextIn(0, 1));
  AssertEquals('and no picture', -1, TViewAccess(FView).XImageIn(0, 1));
  AssertEquals('home', TyPlaceIconIndex(fpiHome), TViewAccess(FView).XImage(0));
  AssertEquals('music', TyPlaceIconIndex(fpiMusic), TViewAccess(FView).XImage(1));
  AssertEquals('drive', TyPlaceIconIndex(fpiDrive), TViewAccess(FView).XImage(2));
  AssertEquals('the picture is the one of that name', TyPlaceIconName(fpiMusic),
    FView.PlaceImages.Names[TViewAccess(FView).XImage(1)]);
  AssertEquals('past the end: nothing', '', TViewAccess(FView).XText(3));
  AssertEquals(-1, TViewAccess(FView).XImage(3));
  AssertEquals(-1, TViewAccess(FView).XImage(-1));
end;

procedure TPlacesViewTest.ARowIsUnderItsHeading;
begin
  FList.Add('n', '', 'N');
  Show3;
  { brought together: A B (One), C (Two), N (none) }
  AssertEquals(0, TViewAccess(FView).XGroup(0));
  AssertEquals(0, TViewAccess(FView).XGroup(1));
  AssertEquals(1, TViewAccess(FView).XGroup(2));
  AssertEquals('under no heading', -1, TViewAccess(FView).XGroup(3));
  AssertEquals('past the end', -1, TViewAccess(FView).XGroup(4));
end;

procedure TPlacesViewTest.AHeadingSaysItsCaptionAlone;
begin
  Show3;
  AssertEquals('no count in brackets', 'One', TViewAccess(FView).XHeading(0));
  AssertEquals('Two', TViewAccess(FView).XHeading(1));
end;

procedure TPlacesViewTest.ThePlacesAreBroughtTogetherByHeading;
begin
  FList.Add('a', 'One', 'A');
  FList.Add('c', 'Two', 'C');
  FList.Add('b', 'One', 'B');
  FView.SetPlaces(FList);
  AssertEquals('A', FView.PlaceAt(0).Caption);
  AssertEquals('B', FView.PlaceAt(1).Caption);
  AssertEquals('C', FView.PlaceAt(2).Caption);
  AssertEquals('the caller''s list is left as it was', 'C', FList[1].Caption);
end;

procedure TPlacesViewTest.TheCurrentFolderIsHighlightedWhenItIsAPlace;
begin
  Show3;
  FView.CurrentPath := PathDelim + 'x' + PathDelim + 'b' + PathDelim;
  AssertEquals(1, FView.ItemIndex);
  AssertEquals(PathDelim + 'x' + PathDelim + 'b', FView.SelectedPath);
  AssertEquals('kept without the delimiter', PathDelim + 'x' + PathDelim + 'b', FView.CurrentPath);
end;

procedure TPlacesViewTest.NoPlaceIsHighlightedWhenItIsNot;
begin
  Show3;
  FView.CurrentPath := PathDelim + 'x' + PathDelim + 'b';
  FView.CurrentPath := PathDelim + 'x' + PathDelim + 'b' + PathDelim + 'deeper';
  AssertEquals(-1, FView.ItemIndex);
  AssertEquals('', FView.SelectedPath);
  FView.CurrentPath := PathDelim + 'x' + PathDelim + 'a';
  FView.CurrentPath := '';
  AssertEquals('nowhere', -1, FView.ItemIndex);
end;

procedure TPlacesViewTest.WritingTheCurrentFolderFiresNothing;
begin
  Show3;
  FView.CurrentPath := PathDelim + 'x' + PathDelim + 'b';
  AssertEquals(0, FChosen.Count);
end;

procedure TPlacesViewTest.AClickChoosesThePlace;
begin
  Show3;
  Click(2);
  AssertEquals(1, FChosen.Count);
  AssertEquals(PathDelim + 'x' + PathDelim + 'c', FChosen[0]);
  AssertEquals(2, FView.ItemIndex);
  AssertEquals('and that is where the pane now is', PathDelim + 'x' + PathDelim + 'c',
    FView.CurrentPath);
  Click(0);
  AssertEquals(2, FChosen.Count);
  AssertEquals(PathDelim + 'x' + PathDelim + 'a', FChosen[1]);
end;

procedure TPlacesViewTest.AClickOnTheCurrentFolderChoosesNothing;
begin
  Show3;
  FView.CurrentPath := PathDelim + 'x' + PathDelim + 'a';
  Click(0);
  AssertEquals('there already', 0, FChosen.Count);
  { deeper inside the place it is a way back up }
  FView.CurrentPath := PathDelim + 'x' + PathDelim + 'a' + PathDelim + 'sub';
  Click(0);
  AssertEquals(1, FChosen.Count);
end;

procedure TPlacesViewTest.AClickBelowTheLastPlaceChoosesNothing;
begin
  Show3;
  TViewAccess(FView).XMouseDown(20, FView.Height - 3);
  AssertEquals(0, FChosen.Count);
end;

procedure TPlacesViewTest.EnterChoosesTheHighlightedPlace;
begin
  Show3;
  FView.CurrentPath := PathDelim + 'x' + PathDelim + 'a';
  FView.ItemIndex := 1;
  TViewAccess(FView).XKey(VK_RETURN);
  AssertEquals(1, FChosen.Count);
  AssertEquals(PathDelim + 'x' + PathDelim + 'b', FChosen[0]);
end;

procedure TPlacesViewTest.AnArrowKeyMovesTheHighlightOnly;
begin
  Show3;
  FView.CurrentPath := PathDelim + 'x' + PathDelim + 'a';
  TViewAccess(FView).XKey(VK_DOWN);
  AssertEquals('the highlight moved', 1, FView.ItemIndex);
  AssertEquals('nothing was chosen', 0, FChosen.Count);
  AssertEquals('and the pane is where it was', PathDelim + 'x' + PathDelim + 'a', FView.CurrentPath);
end;

procedure TPlacesViewTest.NewPlacesKeepTheCurrentFolderHighlighted;
begin
  Show3;
  FView.CurrentPath := PathDelim + 'x' + PathDelim + 'c';
  FList.Insert(0, PathDelim + 'x' + PathDelim + 'new', 'One', 'New');
  FView.SetPlaces(FList);
  AssertEquals(4, FView.PlaceCount);
  AssertEquals('C is one row further down', 3, FView.ItemIndex);
  FList.Delete(3);
  FView.SetPlaces(FList);
  AssertEquals('and gone with its place', -1, FView.ItemIndex);
end;

procedure TPlacesViewTest.NoPlacesShowNothing;
begin
  Show3;
  FView.SetPlaces(nil);
  AssertEquals(0, FView.PlaceCount);
  AssertEquals(-1, FView.ItemIndex);
  AssertEquals(0, TViewAccess(FView).Groups.Count);
end;

procedure TPlacesViewTest.TheSameNumberOfOtherPlacesIsLaidOutAfresh;

  function TopOf(AIndex: Integer): Integer;
  var
    y: Integer;
  begin
    for y := 0 to FView.Height - 1 do
      if FView.GetItemAt(20, y) = AIndex then Exit(y);
    Result := -1;
  end;

var
  before: Integer;
begin
  Show3;                       // A, B under One; C under Two
  before := TopOf(1);
  AssertTrue(before > 0);
  FList.Clear;
  FList.Add('a', 'One', 'A');
  FList.Add('b', 'Two', 'B');  // B is now the first under Two: a heading above it
  FList.Add('c', 'Two', 'C');
  FView.SetPlaces(FList);
  AssertTrue('B moved down by the heading now above it', TopOf(1) > before);
  AssertEquals('and C is where B''s old neighbour was not', 1, TViewAccess(FView).XGroup(2));
end;

procedure TPlacesViewTest.ARightClickChoosesNothing;
var
  y: Integer;
begin
  Show3;
  for y := 0 to FView.Height - 1 do
    if FView.GetItemAt(20, y) = 2 then
    begin
      TViewAccess(FView).XRightDown(20, y + 2);
      Break;
    end;
  AssertEquals(0, FChosen.Count);
  AssertEquals('the pane is where it was', '', FView.CurrentPath);
end;

procedure TPlacesViewTest.ADisabledPaneChoosesNothing;
begin
  Show3;
  FView.Enabled := False;
  Click(2);
  AssertEquals(0, FChosen.Count);
end;

procedure TPlacesViewTest.TheOneColumnIsAsWideAsThePane;
begin
  Show3;
  AssertEquals('one column', 1, FView.ColumnCount);
  FView.SetBounds(0, 0, 260, 400);
  AssertEquals(260, FView.Column[0].Width);
  FView.SetBounds(0, 0, 150, 400);
  AssertEquals('it follows the pane', 150, FView.Column[0].Width);
end;

procedure TPlacesViewTest.ThereIsNoColumnHeaderAndThePicturesAreItsOwn;
begin
  Show3;
  AssertEquals('no band for a column header above the places', 0,
    TViewAccess(FView).CurrentMetrics.HeaderH);
  AssertSame('the rows draw from the place pictures', FView.PlaceImages,
    TViewAccess(FView).SmallImages);
  AssertEquals(9, FView.PlaceImages.Names.Count);
end;

procedure TPlacesViewTest.APlainListViewStillCountsItsGroups;
var
  lv: TListAccess;
begin
  lv := TListAccess.Create(FForm);
  lv.Parent := FForm;
  lv.Groups.Add.Caption := 'Group';
  lv.GroupView := True;
  lv.Items.Add.GroupIndex := 0;
  lv.Items.Add.GroupIndex := 0;
  AssertEquals('Group (2)', lv.XHeading(0));
end;

procedure TPlacesViewTest.TheHeadingsDrawnAreTheOnesThePaneGives;
var
  v: TDrawnHeadings;
begin
  v := TDrawnHeadings.Create(FForm);
  v.Parent := FForm;
  v.SetBounds(0, 0, 200, 300);
  FList.Add('a', 'One', 'A');
  FList.Add('b', 'Two', 'B');
  v.SetPlaces(FList);
  v.Asked := '';
  v.Draw;
  AssertEquals('each band asked the pane what to say, once, and got the caption alone',
    'One;Two;', v.Asked);
end;

{ TLookInWithPlacesTest }

procedure TLookInWithPlacesTest.SetUp;
begin
  inherited SetUp;
  FList := TTyFilePlaces.Create;
end;

procedure TLookInWithPlacesTest.TearDown;
begin
  FList.Free;
  inherited TearDown;
end;

function TLookInWithPlacesTest.Rows(const A: TTyLookInPlaceArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + IntToStr(A[i].Depth) + ':' + A[i].Display;
  end;
end;

procedure TLookInWithPlacesTest.TheChainComesFirstAndThenThePlaces;
var
  here: string;
  r, chain: TTyLookInPlaceArray;
  i: Integer;
begin
  here := Dir('deep');
  FList.Add(PathDelim + 'x' + PathDelim + 'a', 'One', 'A', fpiHome);
  FList.Add(PathDelim + 'x' + PathDelim + 'b', 'Two', 'B', fpiFolder);
  r := TyLookInPlacesFrom(here, FList);
  chain := TyLookInPlaces(here);
  { the chain of the other overloads, less the roots it is followed by there }
  i := 0;
  while (i < Length(chain)) and (chain[i].Depth = i) do Inc(i);
  AssertTrue('there is a chain', i >= 2);
  AssertEquals('the chain and the two places', i + 2, Length(r));
  AssertEquals('the last of the chain is the folder', here, r[i - 1].Path);
  AssertEquals(i - 1, r[i - 1].Depth);
  AssertEquals('A', r[i].Display);
  AssertEquals('at the left edge', 0, r[i].Depth);
  AssertEquals(PathDelim + 'x' + PathDelim + 'a', r[i].Path);
  AssertEquals('B', r[i + 1].Display);
  AssertEquals('a chain row has no picture of its own', Ord(fpiByKind), Ord(r[0].Icon));
end;

procedure TLookInWithPlacesTest.APlaceRowCarriesItsPicture;
var
  r: TTyLookInPlaceArray;
begin
  FList.Add(PathDelim + 'x' + PathDelim + 'a', '', 'A', fpiMusic);
  FList.Add(PathDelim + 'x' + PathDelim + 'd', '', 'D', fpiDrive);
  r := TyLookInPlacesFrom('', FList);
  AssertEquals(Ord(fpiMusic), Ord(r[0].Icon));
  AssertTrue('a folder', r[0].Folder);
  AssertEquals(Ord(fpiDrive), Ord(r[1].Icon));
  AssertFalse('a drive is not', r[1].Folder);
end;

procedure TLookInWithPlacesTest.TheDriveOfTheChainIsNotListedTwice;
var
  crumbs: TStringArray;
  r: TTyLookInPlaceArray;
  i, hits: Integer;
begin
  crumbs := TyFsBreadcrumb(FTemp);
  FList.Add(crumbs[0], 'Devices', 'the root', fpiDrive);
  FList.Add(PathDelim + 'x' + PathDelim + 'other', 'Devices', 'another', fpiDrive);
  r := TyLookInPlacesFrom(FTemp, FList);
  hits := 0;
  for i := 0 to High(r) do
    if SameFileName(r[i].Path, crumbs[0]) then Inc(hits);
  AssertEquals('once: as the head of the chain', 1, hits);
  AssertEquals('the other drive is listed', 'another', r[High(r)].Display);
  AssertEquals('the chain and that one', Length(crumbs) + 1, Length(r));
end;

procedure TLookInWithPlacesTest.AFolderPlaceOnTheChainIsListedAllTheSame;
var
  crumbs: TStringArray;
  r: TTyLookInPlaceArray;
begin
  crumbs := TyFsBreadcrumb(FTemp);
  { The chain's root as a FOLDER place, and the folder itself: both stay. }
  FList.Add(crumbs[0], 'One', 'root as a folder', fpiFolder);
  FList.Add(FTemp, 'One', 'here', fpiFolder);
  r := TyLookInPlacesFrom(FTemp, FList);
  AssertEquals(Length(crumbs) + 2, Length(r));
  AssertEquals('root as a folder', r[Length(crumbs)].Display);
  AssertEquals('here', r[Length(crumbs) + 1].Display);
end;

procedure TLookInWithPlacesTest.WithoutADirectoryThePlacesAreAllThereIs;
begin
  FList.Add(PathDelim + 'x' + PathDelim + 'a', '', 'A');
  FList.Add(PathDelim + 'x' + PathDelim + 'b', '', 'B', fpiDrive);
  AssertEquals('0:A 0:B', Rows(TyLookInPlacesFrom('', FList)));
  AssertEquals('no list: no rows', 0, Length(TyLookInPlacesFrom('', nil)));
end;

procedure TLookInWithPlacesTest.TheBoxListsThePlacesItIsGiven;
var
  c: TTyShellComboBox;
begin
  c := TTyShellComboBox.Create(nil);
  try
    FList.Add(PathDelim + 'x' + PathDelim + 'a', '', 'A');
    FList.Add(PathDelim + 'x' + PathDelim + 'b', '', 'B');
    c.SetPlaces(FList);
    AssertEquals('they stand in for the roots', 2, c.Items.Count);
    AssertEquals('A', c.Items[0]);
    AssertEquals('B', c.Items[1]);
    FList.Add(PathDelim + 'x' + PathDelim + 'c', '', 'C');
    AssertEquals('a copy: the caller''s list is its own', 2, c.Items.Count);
    c.ItemIndex := 1;
    AssertEquals(PathDelim + 'x' + PathDelim + 'b', c.SelectedPath);
  finally
    c.Free;
  end;
end;

procedure TLookInWithPlacesTest.TheBoxGoesBackToTheRoots;
var
  c: TTyShellComboBox;
begin
  c := TTyShellComboBox.Create(nil);
  try
    FList.Add(PathDelim + 'x' + PathDelim + 'a', '', 'A');
    c.SetPlaces(FList);
    c.SetPlaces(nil);
    AssertEquals(Length(TyFsRoots), c.Items.Count);
  finally
    c.Free;
  end;
end;

procedure TLookInWithPlacesTest.ThePlacePicturesFollowTheTwoOldOnes;
var
  c: TTyShellComboBox;
begin
  c := TTyShellComboBox.Create(nil);
  try
    AssertEquals('drive', c.LookInImages.Names[TyLookInDriveGlyph]);
    AssertEquals('folder', c.LookInImages.Names[TyLookInFolderGlyph]);
    AssertEquals(TyPlaceIconName(fpiFolder), c.LookInImages.Names[TyLookInPlaceGlyphs]);
    FList.Add(PathDelim + 'x' + PathDelim + 'a', '', 'A', fpiVideos);
    c.SetPlaces(FList);
    AssertEquals('the row asks for the picture of that name', TyPlaceIconName(fpiVideos),
      c.LookInImages.Names[c.GlyphOfModel(0)]);
  finally
    c.Free;
  end;
end;

procedure TLookInWithPlacesTest.InAPlaceTheFieldShowsItsNameAndPicture;
var
  c: TComboAccess;
begin
  c := TComboAccess.Create(nil);
  try
    FList.Add(FTemp, 'One', 'My place', fpiMusic);
    c.SetPlaces(FList);
    c.Directory := FTemp;
    AssertEquals('My place', c.XFieldCaption);
    AssertEquals(TyPlaceIconName(fpiMusic), c.LookInImages.Names[c.XFieldGlyph]);
  finally
    c.Free;
  end;
end;

procedure TLookInWithPlacesTest.OutsideAPlaceTheFieldShowsTheFolder;
var
  c: TComboAccess;
  sub: string;
begin
  c := TComboAccess.Create(nil);
  try
    sub := Dir('inside');
    FList.Add(FTemp, 'One', 'My place', fpiMusic);
    c.SetPlaces(FList);
    c.Directory := sub;
    AssertEquals('inside', c.XFieldCaption);
    AssertEquals('a folder', TyLookInFolderGlyph, c.XFieldGlyph);
  finally
    c.Free;
  end;
end;

{ TFileDialogPlacesTest }

procedure TFileDialogPlacesTest.SetUp;
begin
  inherited SetUp;
  FForm := nil;
  FEvents := 0;
  FSender := nil;
end;

procedure TFileDialogPlacesTest.TearDown;
begin
  FreeAndNil(FForm);
  inherited TearDown;
end;

procedure TFileDialogPlacesTest.Build;
begin
  FreeAndNil(FForm);
  FForm := TQuietFileDialog.CreateNew(nil);
  FForm.InitialDir := FTemp;
end;

function TFileDialogPlacesTest.Accept(const AName: string): Boolean;
begin
  FForm.NameEdit.Text := AName;
  FForm.ModalResult := mrOK;
  Result := FForm.CloseQuery;
end;

procedure TFileDialogPlacesTest.AddAPlace(Sender: TObject; APlaces: TTyFilePlaces);
begin
  Inc(FEvents);
  FSender := Sender;
  APlaces.Add(FTemp, 'Mine', 'Added');
end;

procedure TFileDialogPlacesTest.AddToThePlaces(Sender: TObject; APlaces: TTyFilePlaces);
begin
  APlaces.Add(FTemp, rsFdGroupPlaces, 'One more');
end;

procedure TFileDialogPlacesTest.KeepOpen(Sender: TObject; var ACanClose: Boolean);
begin
  ACanClose := False;
end;

procedure TFileDialogPlacesTest.DropTheRest(Sender: TObject; APlaces: TTyFilePlaces);
begin
  APlaces.Clear;
  APlaces.Add(FTemp, 'Mine', 'Only');
end;

procedure TFileDialogPlacesTest.TheLeftPaneIsThePlaces;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(False, False, '');
  try
    AssertEquals(Ord(fdpPlaces), Ord(d.LeftPane));
    AssertNotNull('the pane', d.PlacesView);
    AssertTrue(d.PlacesView.Visible);
    AssertNull('no tree is built', d.ShellTree);
    AssertTrue('the machine''s places are in it',
      d.PlacesView.PlaceCount >= Length(TyFsKnownFolders) + Length(TyFsRoots));
  finally
    d.Free;
  end;
  d := TyBuildFileDialog(True, True, '');
  try
    AssertNotNull('the save dialog with a preview too', d.PlacesView);
    AssertTrue(d.PlacesView.PlaceCount > 0);
  finally
    d.Free;
  end;
end;

procedure TFileDialogPlacesTest.ThePaneAndTheDropDownShowTheSamePlaces;
var
  i, n: Integer;
begin
  Build;
  FForm.OnPlaces := @DropTheRest;
  FForm.RefreshPlaces;
  AssertEquals(1, FForm.Places.Count);
  AssertEquals(1, FForm.PlacesView.PlaceCount);
  AssertEquals('Only', FForm.PlacesView.PlaceAt(0).Caption);
  { the drop-down: the chain to FTemp, and then that place }
  n := FForm.LookInBox.Items.Count;
  AssertEquals('Only', FForm.LookInBox.Items[n - 1]);
  AssertEquals('the chain and the place', Length(TyFsBreadcrumb(FTemp)) + 1, n);
  for i := 0 to n - 2 do
    AssertTrue('row ' + IntToStr(i) + ' is of the chain', FForm.LookInBox.DepthOfModel(i) = i);
end;

procedure TFileDialogPlacesTest.TheFolderTreeOnRequest;
begin
  Build;
  FForm.LeftPane := fdpFolderTree;
  AssertNotNull('the tree', FForm.ShellTree);
  AssertTrue(FForm.ShellTree.Visible);
  AssertTrue('with the places at its top (#245)', FForm.ShellTree.ShowPlaces);
  AssertFalse('the pane is put away', FForm.PlacesView.Visible);
  AssertEquals('the tree shows where the list is', FTemp, ChompPathDelim(FForm.ShellTree.SelectedPath));
  AssertEquals('first of the band for Tab', 0, FForm.ShellTree.TabOrder);
end;

procedure TFileDialogPlacesTest.NoLeftPaneOnRequest;
var
  i: Integer;
  split: TControl;
begin
  Build;
  FForm.LeftPane := fdpNone;
  AssertFalse(FForm.PlacesView.Visible);
  AssertNull('no tree either', FForm.ShellTree);
  split := nil;
  for i := 0 to FForm.ShellList.Parent.ControlCount - 1 do
    if FForm.ShellList.Parent.Controls[i].ClassName = 'TTySplitter' then
      split := FForm.ShellList.Parent.Controls[i];
  AssertNotNull(split);
  AssertFalse('and no divider with nothing to divide', split.Visible);
end;

procedure TFileDialogPlacesTest.BackToThePlaces;
var
  i: Integer;
  split: TControl;
begin
  Build;
  FForm.LeftPane := fdpNone;
  FForm.LeftPane := fdpFolderTree;
  FForm.LeftPane := fdpPlaces;
  AssertTrue(FForm.PlacesView.Visible);
  AssertFalse(FForm.ShellTree.Visible);
  split := nil;
  for i := 0 to FForm.ShellList.Parent.ControlCount - 1 do
    if FForm.ShellList.Parent.Controls[i].ClassName = 'TTySplitter' then
      split := FForm.ShellList.Parent.Controls[i];
  AssertTrue('the divider is back', split.Visible);
  AssertEquals(0, FForm.PlacesView.Left);
  AssertTrue('right of the pane', split.Left >= FForm.PlacesView.Width);
end;

procedure TFileDialogPlacesTest.ThePaneFollowsTheListIntoAPlace;
begin
  Build;
  FForm.PinnedFolders.Add(Dir('pinned'));
  FForm.RefreshPlaces;
  FForm.InitialDir := FTemp + PathDelim + 'pinned';
  AssertEquals(FTemp + PathDelim + 'pinned', FForm.PlacesView.SelectedPath);
  AssertEquals(rsFdGroupPinned, FForm.PlacesView.PlaceAt(FForm.PlacesView.ItemIndex).Group);
end;

procedure TFileDialogPlacesTest.ThePaneHighlightsNothingOutsideThePlaces;
begin
  Build;
  FForm.PinnedFolders.Add(Dir('pinned'));
  FForm.RefreshPlaces;
  FForm.InitialDir := FTemp + PathDelim + 'pinned';
  FForm.InitialDir := Dir('pinned' + PathDelim + 'deeper');
  AssertEquals(-1, FForm.PlacesView.ItemIndex);
end;

procedure TFileDialogPlacesTest.ChoosingAPlaceGoesThere;
var
  idx: Integer;
begin
  Build;
  FForm.PinnedFolders.Add(Dir('pinned'));
  FForm.RefreshPlaces;
  idx := FForm.Places.IndexOf(FTemp + PathDelim + 'pinned');
  AssertTrue(idx >= 0);
  FForm.PlacesView.ItemIndex := idx;
  TViewAccess(FForm.PlacesView).XKey(VK_RETURN);
  AssertEquals('the list', FTemp + PathDelim + 'pinned', ChompPathDelim(FForm.CurrentDirectory));
  AssertEquals('the folder box', FTemp + PathDelim + 'pinned', FForm.LookInBox.Directory);
  { A place that is gone meanwhile is not gone to, and not left highlighted. }
  FForm.PinnedFolders.Add(Dir('doomed'));
  FForm.RefreshPlaces;
  RemoveDirUTF8(FTemp + PathDelim + 'doomed');
  FForm.PlacesView.ItemIndex := FForm.Places.IndexOf(FTemp + PathDelim + 'doomed');
  TViewAccess(FForm.PlacesView).XKey(VK_RETURN);
  AssertEquals('still there', FTemp + PathDelim + 'pinned', ChompPathDelim(FForm.CurrentDirectory));
  AssertEquals('and the pane says so', FTemp + PathDelim + 'pinned', FForm.PlacesView.SelectedPath);
end;

procedure TFileDialogPlacesTest.TheTreeFollowsWhenItIsBuiltLater;
begin
  Dir('sub');   // before the tree reads the folder it is in
  Build;
  FForm.Options := [ofForceShowHidden];
  FForm.LeftPane := fdpFolderTree;
  AssertTrue('the option set before the tree was there reaches it', FForm.ShellTree.ShowHidden);
  FForm.InitialDir := FTemp + PathDelim + 'sub';
  AssertEquals('and it follows the list', FTemp + PathDelim + 'sub',
    ChompPathDelim(FForm.ShellTree.SelectedPath));
  FForm.LeftPane := fdpPlaces;
  FForm.InitialDir := FTemp;
  AssertEquals('put away, the tree is not walked along', FTemp + PathDelim + 'sub',
    ChompPathDelim(FForm.ShellTree.SelectedPath));
  FForm.LeftPane := fdpFolderTree;
  AssertEquals('shown again, it is brought up to date', FTemp,
    ChompPathDelim(FForm.ShellTree.SelectedPath));
end;

procedure TFileDialogPlacesTest.APinnedFolderIsAmongThePlaces;
var
  idx: Integer;
begin
  Build;
  FForm.PinnedFolders.Add(Dir('pinned'));
  AssertEquals('not until the places are listed again', -1,
    FForm.Places.IndexOf(FTemp + PathDelim + 'pinned'));
  FForm.RefreshPlaces;
  idx := FForm.Places.IndexOf(FTemp + PathDelim + 'pinned');
  AssertTrue(idx >= 0);
  AssertEquals(rsFdGroupPinned, FForm.Places[idx].Group);
  AssertEquals('pinned', FForm.Places[idx].Caption);
  FForm.PinnedFolders := nil;
  FForm.RefreshPlaces;
  AssertEquals('and unpinned', -1, FForm.Places.IndexOf(FTemp + PathDelim + 'pinned'));
end;

procedure TFileDialogPlacesTest.OnPlacesMayAdd;
var
  idx: Integer;
begin
  Build;
  FForm.OnPlaces := @AddAPlace;
  FForm.RefreshPlaces;
  AssertEquals(1, FEvents);
  idx := FForm.Places.IndexOf(FTemp);
  AssertTrue(idx >= 0);
  AssertEquals('Added', FForm.PlacesView.PlaceAt(idx).Caption);
  AssertEquals('under a heading of the program''s own', 'Mine', FForm.PlacesView.PlaceAt(idx).Group);
  AssertEquals('which the pane shows', 'Mine',
    TViewAccess(FForm.PlacesView).Groups[TViewAccess(FForm.PlacesView).Groups.Count - 1].Caption);
  AssertEquals('the standard places are still there', Length(TyFsKnownFolders) + Length(TyFsRoots) + 1,
    FForm.Places.Count);
end;

procedure TFileDialogPlacesTest.OnPlacesMayRemove;
begin
  Build;
  FForm.OnPlaces := @DropTheRest;
  FForm.RefreshPlaces;
  AssertEquals(1, FForm.PlacesView.PlaceCount);
  FForm.OnPlaces := nil;
  FForm.RefreshPlaces;
  AssertEquals('listed afresh each time', Length(TyFsKnownFolders) + Length(TyFsRoots),
    FForm.PlacesView.PlaceCount);
end;

procedure TFileDialogPlacesTest.OnPlacesSaysTheFormWhenThereIsNoComponent;
begin
  Build;
  FForm.OnPlaces := @AddAPlace;
  FForm.RefreshPlaces;
  AssertSame(FForm, FSender);
end;

procedure TFileDialogPlacesTest.AnAcceptedDialogNotesItsFolder;
begin
  Build;
  with TStringList.Create do
    try Add('x'); SaveToFile(FTemp + PathDelim + 'a.txt'); finally Free; end;
  AssertTrue(Accept('a.txt'));
  AssertEquals(1, TyRecentFolders.Count);
  AssertEquals(FTemp, TyRecentFolders[0]);
end;

procedure TFileDialogPlacesTest.ARefusedDialogNotesNothing;
begin
  Build;
  FForm.Options := [ofFileMustExist];
  AssertFalse(Accept('not-there.txt'));
  AssertEquals(0, TyRecentFolders.Count);
end;

procedure TFileDialogPlacesTest.ACancelledDialogNotesNothing;
begin
  Build;
  FForm.NameEdit.Text := 'a.txt';
  FForm.ModalResult := mrCancel;
  AssertTrue(FForm.CloseQuery);
  AssertEquals(0, TyRecentFolders.Count);
end;

procedure TFileDialogPlacesTest.WithoutRecentFoldersNothingIsNotedOrShown;
begin
  TyRecentFolders.Add(Dir('earlier'));
  Build;
  FForm.ShowRecentFolders := False;
  FForm.RefreshPlaces;
  AssertEquals('not shown', -1, FForm.Places.IndexOf(FTemp + PathDelim + 'earlier'));
  AssertTrue(Accept('new.txt'));
  AssertEquals('not noted', 1, TyRecentFolders.Count);
  AssertEquals(FTemp + PathDelim + 'earlier', TyRecentFolders[0]);
end;

procedure TFileDialogPlacesTest.TheRecentFolderIsShownTheNextTime;
var
  idx: Integer;
begin
  Build;
  FForm.InitialDir := Dir('work');
  AssertTrue(Accept('new.txt'));
  Build;
  FForm.RefreshPlaces;
  idx := FForm.Places.IndexOf(FTemp + PathDelim + 'work');
  AssertTrue('the folder the last dialog was accepted in', idx >= 0);
  AssertEquals(rsFdGroupRecent, FForm.Places[idx].Group);
end;

procedure TFileDialogPlacesTest.ChoosingInTheTreeGoesThere;
begin
  Dir('sub');
  Build;
  FForm.LeftPane := fdpFolderTree;
  AssertTrue(FForm.ShellTree.SelectPath(FTemp + PathDelim + 'sub'));
  AssertEquals('the list went along', FTemp + PathDelim + 'sub', ChompPathDelim(FForm.CurrentDirectory));
end;

procedure TFileDialogPlacesTest.ATreeBuiltBeforeAnyFolderIsShown;
begin
  FForm := TQuietFileDialog.CreateNew(nil);
  AssertEquals('nowhere yet', '', FForm.CurrentDirectory);
  FForm.LeftPane := fdpFolderTree;
  AssertNotNull(FForm.ShellTree);
  AssertEquals('and the tree has nothing selected', '', FForm.ShellTree.SelectedPath);
  AssertEquals('nor the pane', -1, FForm.PlacesView.ItemIndex);
end;

procedure TFileDialogPlacesTest.WhatOnPlacesAddsGoesUnderItsHeading;
var
  i, added, firstDevice: Integer;
begin
  Build;
  FForm.OnPlaces := @AddToThePlaces;
  FForm.RefreshPlaces;
  added := FForm.Places.IndexOf(FTemp);
  firstDevice := -1;
  for i := 0 to FForm.Places.Count - 1 do
    if (firstDevice < 0) and (FForm.Places[i].Group = rsFdGroupDevices) then firstDevice := i;
  AssertTrue('there are devices', firstDevice >= 0);
  AssertTrue('added at the end, it is listed with the other places, above the devices',
    added < firstDevice);
  AssertEquals(FForm.Places.Count, FForm.PlacesView.PlaceCount);
  for i := 0 to FForm.Places.Count - 1 do
    AssertEquals('row ' + IntToStr(i) + ' of the pane is place ' + IntToStr(i),
      FForm.Places[i].Path, FForm.PlacesView.PlaceAt(i).Path);
end;

procedure TFileDialogPlacesTest.ADialogTheProgramKeepsOpenNotesNothing;
begin
  Build;
  FForm.OnCloseQuery := @KeepOpen;
  AssertFalse(Accept('new.txt'));
  AssertEquals(0, TyRecentFolders.Count);
end;

procedure TFileDialogPlacesTest.ANameTypedWithItsFolderNotesThatFolder;
begin
  Build;
  Dir('elsewhere');
  AssertTrue(Accept(FTemp + PathDelim + 'elsewhere' + PathDelim + 'new.txt'));
  AssertEquals('where the file is, not where the list was', FTemp + PathDelim + 'elsewhere',
    TyRecentFolders[0]);
end;

{ TFileDialogComponentPlacesTest }

procedure TFileDialogComponentPlacesTest.Places(Sender: TObject; APlaces: TTyFilePlaces);
begin
  Inc(FEvents);
  FSender := Sender;
  APlaces.Add(FTemp, 'Mine', 'From the component');
end;

function TFileDialogComponentPlacesTest.Streamed(AComp: TComponent): string;
var
  ms, ts: TMemoryStream;
  L: TStringList;
begin
  ms := TMemoryStream.Create;
  ts := TMemoryStream.Create;
  L := TStringList.Create;
  try
    ms.WriteComponent(AComp);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    L.LoadFromStream(ts);
    Result := L.Text;
  finally
    L.Free;
    ts.Free;
    ms.Free;
  end;
end;

procedure TFileDialogComponentPlacesTest.TheDefaults;
var
  d: TTySaveDialog;
begin
  d := TTySaveDialog.Create(nil);
  try
    AssertEquals(Ord(fdpPlaces), Ord(d.LeftPane));
    AssertTrue(d.ShowRecentFolders);
    AssertEquals(0, d.PinnedFolders.Count);
    d.PinnedFolders.Add('x');
    d.PinnedFolders := nil;
    AssertEquals('assigning nothing empties the list', 0, d.PinnedFolders.Count);
    AssertNotNull('and leaves it there', d.PinnedFolders);
  finally
    d.Free;
  end;
end;

procedure TFileDialogComponentPlacesTest.TheFormIsBuiltWithWhatTheComponentSays;
var
  d: TTyOpenDialog;
  f: TTyFileDialogForm;
begin
  TyRecentFolders.Add(Dir('earlier'));
  d := TTyOpenDialog.Create(nil);
  try
    d.InitialDir := FTemp;
    d.PinnedFolders.Add(Dir('pinned'));
    f := d.BuildForm;
    try
      AssertEquals(Ord(fdpPlaces), Ord(f.LeftPane));
      AssertTrue('the pinned folder', f.PlacesView.PlaceCount > 0);
      AssertTrue(f.Places.IndexOf(FTemp + PathDelim + 'pinned') >= 0);
      AssertTrue('the recent one', f.Places.IndexOf(FTemp + PathDelim + 'earlier') >= 0);
    finally
      f.Free;
    end;
    d.LeftPane := fdpFolderTree;
    d.ShowRecentFolders := False;
    f := d.BuildForm;
    try
      AssertEquals(Ord(fdpFolderTree), Ord(f.LeftPane));
      AssertNotNull(f.ShellTree);
      AssertFalse(f.ShowRecentFolders);
      AssertEquals('no recent folder', -1, f.Places.IndexOf(FTemp + PathDelim + 'earlier'));
      AssertTrue('the pinned one is in the drop-down all the same',
        f.LookInBox.Items.IndexOf('pinned') >= 0);
    finally
      f.Free;
    end;
    d.LeftPane := fdpNone;
    f := d.BuildForm;
    try
      AssertEquals(Ord(fdpNone), Ord(f.LeftPane));
    finally
      f.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TFileDialogComponentPlacesTest.OnPlacesFiresOnceABuildAndSaysTheComponent;
var
  d: TTyOpenDialog;
  f: TTyFileDialogForm;
begin
  d := TTyOpenDialog.Create(nil);
  try
    d.OnPlaces := @Places;
    f := d.BuildForm;
    try
      AssertEquals('once', 1, FEvents);
      AssertSame('the component, not the form', d, FSender);
      AssertTrue(f.Places.IndexOf(FTemp) >= 0);
      AssertEquals('From the component', f.PlacesView.PlaceAt(f.Places.IndexOf(FTemp)).Caption);
    finally
      f.Free;
    end;
    f := d.BuildForm;
    try
      AssertEquals('and once more for the next', 2, FEvents);
    finally
      f.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TFileDialogComponentPlacesTest.TheDefaultsAreNotWritten;
var
  src: TForm;
  d: TTyOpenDialog;
  s: string;
begin
  src := TForm.CreateNew(nil);
  try
    d := TTyOpenDialog.Create(src);
    d.Name := 'D';
    s := Streamed(src);
    AssertEquals('LeftPane', 0, Pos('LeftPane', s));
    AssertEquals('ShowRecentFolders', 0, Pos('ShowRecentFolders', s));
    AssertEquals('PinnedFolders', 0, Pos('PinnedFolders', s));
  finally
    src.Free;
  end;
end;

procedure TFileDialogComponentPlacesTest.WhatIsSetIsWrittenAndReadBack;
var
  src, dst: TForm;
  d, back: TTyOpenDialog;
  ms: TMemoryStream;
  s: string;
begin
  src := TForm.CreateNew(nil);
  dst := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    d := TTyOpenDialog.Create(src);
    d.Name := 'D';
    d.LeftPane := fdpFolderTree;
    d.ShowRecentFolders := False;
    d.PinnedFolders.Add('C:\one');
    d.PinnedFolders.Add('C:\two');
    s := Streamed(src);
    AssertTrue('LeftPane', Pos('LeftPane = fdpFolderTree', s) > 0);
    AssertTrue('ShowRecentFolders', Pos('ShowRecentFolders = False', s) > 0);
    AssertTrue('PinnedFolders', Pos('PinnedFolders.Strings', s) > 0);
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    back := dst.FindComponent('D') as TTyOpenDialog;
    AssertNotNull(back);
    AssertEquals(Ord(fdpFolderTree), Ord(back.LeftPane));
    AssertFalse(back.ShowRecentFolders);
    AssertEquals('C:\one' + LineEnding + 'C:\two' + LineEnding, back.PinnedFolders.Text);
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

{ TSelectPathPlacesTest }

procedure TSelectPathPlacesTest.TheCommonFoldersAreAboveTheDrives;
var
  d: TTySelectPathForm;
  n: PTyTreeNode;
  known: TTyFsRootArray;
  roots: TTyFsRootArray;
  count, homes, i: Integer;
begin
  known := TyFsKnownFolders;
  roots := TyFsRoots;
  homes := 0;
  for i := 0 to High(roots) do
    if roots[i].Kind = rkHome then Inc(homes);
  d := TyBuildSelectPathDialog('Folder', '');
  try
    count := 0;
    n := d.Tree.GetFirst;
    while n <> nil do
    begin
      Inc(count);
      n := d.Tree.GetNextSibling(n);
    end;
    AssertEquals('the home folder, the common folders, the drives',
      homes + Length(known) + Length(TyDriveRoots), count);
    { the last top-level node is a drive, the one before the first drive a place }
    n := d.Tree.GetFirst;
    for i := 1 to homes + Length(known) do
      n := d.Tree.GetNextSibling(n);
    AssertNotNull('the first drive', n);
    AssertEquals('by its name (#250)', TyFsRootName(TyDriveRoots[0]), d.NodeText(n));
  finally
    d.Free;
  end;
end;

procedure TSelectPathPlacesTest.APlaceIsListedUnderItsName;
var
  d: TTySelectPathForm;
  n: PTyTreeNode;
  known: TTyFsRootArray;
  roots: TTyFsRootArray;
  i: Integer;
begin
  known := TyFsKnownFolders;
  if Length(known) = 0 then Exit;   // a machine without any: nothing to list
  roots := TyFsRoots;
  d := TyBuildSelectPathDialog('Folder', '');
  try
    n := d.Tree.GetFirst;
    for i := 0 to High(roots) do
      if roots[i].Kind = rkHome then
      begin
        AssertEquals(rsFdPlaceHome, d.NodeText(n));
        n := d.Tree.GetNextSibling(n);
      end;
    for i := 0 to High(known) do
    begin
      AssertEquals('its name, whatever the folder is called', known[i].Display, d.NodeText(n));
      n := d.Tree.GetNextSibling(n);
    end;
  finally
    d.Free;
  end;
end;

procedure TSelectPathPlacesTest.ARootedPickerListsItsRootAlone;
var
  d: TTySelectPathForm;
  n: PTyTreeNode;
begin
  Dir('sub');
  d := TyBuildSelectPathDialog('Folder', FTemp);
  try
    n := d.Tree.GetFirst;
    AssertNotNull(n);
    AssertNull('one node at the top', d.Tree.GetNextSibling(n));
    AssertEquals('under its own name', ExtractFileName(FTemp), d.NodeText(n));
  finally
    d.Free;
  end;
end;

procedure TSelectPathPlacesTest.GoingToAPlaceSelectsItsOwnNode;
var
  d: TTySelectPathForm;
  known: TTyFsRootArray;
begin
  known := TyFsKnownFolders;
  if Length(known) = 0 then Exit;
  d := TyBuildSelectPathDialog('Folder', '');
  try
    d.Directory := known[0].Path;
    AssertEquals(known[0].Path, ChompPathDelim(d.SelectedPath));
    AssertEquals('the place''s node at the top, not the folder under its drive', 0,
      d.Tree.GetNodeLevel(d.Tree.FocusedNode));
    AssertEquals(known[0].Display, d.NodeText(d.Tree.FocusedNode));
  finally
    d.Free;
  end;
end;

procedure TSelectPathPlacesTest.APlaceIsShownUnderItsNameWithItsPicture;
var
  d: TProbePicker;
  place, kid, drive: PTyTreeNode;
begin
  Dir('realname' + PathDelim + 'kid');
  d := TProbePicker.CreateNew(nil);
  try
    SetLength(d.Probe, 1);
    d.Probe[0].Path := FTemp + PathDelim + 'realname';
    d.Probe[0].Display := 'Called otherwise';
    d.Probe[0].Kind := rkPlace;
    d.Probe[0].Icon := fpiMusic;
    d.UseProbe := True;
    d.PopulateRoots;
    place := d.Tree.GetFirst;
    AssertEquals('its name, not its folder''s', 'Called otherwise', d.NodeText(place));
    AssertEquals('its picture', TyPlaceIconIndex(fpiMusic), d.XImage(place));
    d.Tree.Expanded[place] := True;
    kid := d.Tree.GetFirstChild(place);
    AssertNotNull(kid);
    AssertEquals('a folder under it: its own name', 'kid', d.NodeText(kid));
    AssertEquals('and a folder''s picture', TyPlaceIconIndex(fpiFolder), d.XImage(kid));
    drive := d.Tree.GetNextSibling(place);
    AssertNotNull('the drives follow', drive);
    AssertEquals('by its name (#250)', TyFsRootName(TyDriveRoots[0]), d.NodeText(drive));
    AssertEquals('a drive''s picture', TyPlaceIconIndex(fpiDrive), d.XImage(drive));
    d.Directory := FTemp + PathDelim + 'realname' + PathDelim + 'kid';
    AssertSame('a folder inside a place is shown under the place', kid, d.Tree.FocusedNode);
    { Populated again without the place, nothing of it is left: the first node is the drive. }
    d.Probe := nil;
    d.PopulateRoots;
    AssertEquals(TyFsRootName(TyDriveRoots[0]), d.NodeText(d.Tree.GetFirst));
    AssertEquals(TyPlaceIconIndex(fpiDrive), d.XImage(d.Tree.GetFirst));
  finally
    d.Free;
  end;
end;

procedure TSelectPathPlacesTest.TheHomeFolderIsAPlaceWhereThereIsOne;
var
  d: TProbePicker;
  roots, top: TTyFsRootArray;
  i, homes: Integer;
begin
  roots := TyFsRoots;
  homes := 0;
  d := TProbePicker.CreateNew(nil);
  try
    top := d.TopPlaces;
    for i := 0 to High(roots) do
      if roots[i].Kind = rkHome then
      begin
        AssertEquals(roots[i].Path, top[homes].Path);
        AssertEquals(rsFdPlaceHome, top[homes].Display);
        Inc(homes);
      end;
    AssertEquals('and then the common folders', homes + Length(TyFsKnownFolders), Length(top));
    if Length(top) > homes then
      AssertEquals('the first of them', TyFsKnownFolders[0].Path, top[homes].Path);
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TPlaceIconsTest);
  RegisterTest(TPlaceIconAndRecentTest);
  RegisterTest(TFilePlacesListTest);
  RegisterTest(TStandardPlacesTest);
  RegisterTest(TPlacesViewTest);
  RegisterTest(TLookInWithPlacesTest);
  RegisterTest(TFileDialogPlacesTest);
  RegisterTest(TFileDialogComponentPlacesTest);
  RegisterTest(TSelectPathPlacesTest);

end.
