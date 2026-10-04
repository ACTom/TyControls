unit test.customclasses.p4;
{$mode objfpc}{$H+}

{ Custom-class split, phase 4 (the non-visual components: controllers, icon fonts and image
  lists, hints and notifications, dialogs). Same fixture and checks as the earlier phases
  (TTyCustomClassesPhaseCase), minus the paint comparison -- nothing here paints itself:

  * THIRD-PARTY MIMICS: a TTyCustomXxx descendant that publishes two properties of its own
    choosing -- it can be created without an owner (T-a), publishes exactly its LCL root's
    names plus the two (T-b; the root is TComponent, or TCustomImageList for the image lists),
    streams those two and not a property it left out (T-c), streams nothing from a fresh
    instance (T-e), and reaches a public property through a TTyCustomXxx reference (T-v).
  * DERIVED COMPONENTS SEEN BY THEIR FAMILY: from 4.0 on a TTyLucideImageList is a
    TTyCustomVirtualImageList but no longer a TTyVirtualImageList; library code that meant "any
    virtual image list" asks for the custom class, and each such check has a test that fails
    when it is put back.
  * COMPONENT REFERENCES THE LCL WAY: a property that references a splittable component names
    its custom class (LCL's Images: TCustomImageList), so a third party's -- and the library's
    own derived -- component can be assigned to it. }

interface

uses
  Classes, SysUtils, TypInfo, Controls, Forms, Graphics,
  fpcunit, testregistry,
  test.customclasses, test.customclasses.p1,
  BGRABitmap, BGRABitmapTypes, ImgList,
  tyControls.Base, tyControls.Controller, tyControls.NativeStyler, tyControls.IconFont,
  tyControls.Icons.Lucide, tyControls.ImageCollection, tyControls.ImageDraw, tyControls.Image,
  tyControls.CharImage, tyControls.GlyphButtons, tyControls.ToolBar, tyControls.RibbonBackstage,
  tyControls.Hint, tyControls.BalloonHint, tyControls.Popover, tyControls.Notification,
  tyControls.Panel, Dialogs, tyControls.Dialogs, tyControls.Dialogs.Progress,
  tyControls.Dialogs.About, tyControls.Dialogs.IconBrowser;

type
  TTyCustomClassesP4Test = class(TTyCustomClassesPhaseCase)
  published
    { Task 27: controllers }
    procedure TestThirdStyleController;
    procedure TestThirdNativeStyler;
    { Task 28: icon fonts and images }
    procedure TestThirdIconFont;
    procedure TestThirdVirtualImageList;
    procedure TestLucideImageListTakesTheVectorPath;
    procedure TestLucideIconFontFitsAnIconFontProperty;
    procedure TestImagePropertiesNameTheCustomClasses;
    { Task 29: hints and notifications }
    procedure TestThirdPopover;
    procedure TestThirdNotification;
    procedure TestThirdHintAndBalloonHint;
    { Task 30: dialogs }
    procedure TestThirdMessage;
    procedure TestThirdInputDialog;
    procedure TestDialogsSplitTheLclWay;
  end;

  { --- third-party mimics ------------------------------------------------------------ }

  TThirdStyleController = class(TTyCustomStyleController)
  published
    property ThemeName;
    property Mode;
  end;

  TThirdNativeStyler = class(TTyCustomNativeStyler)
  published
    property Enabled;
    property ApplyFontSize;
  end;

  TThirdIconFont = class(TTyCustomIconFont)
  published
    property FontFamily;
    property Glyphs;
  end;

  TThirdVirtualImageList = class(TTyCustomVirtualImageList)
  published
    property Names;
    property Collection;
  end;

  TThirdPopover = class(TTyCustomPopover)
  published
    property Content;
    property Placement;
  end;

  TThirdNotification = class(TTyCustomNotification)
  published
    property Title;
    property Message;
  end;

  TThirdHint = class(TTyCustomHint)
  published
    property Active;
  end;

  TThirdBalloonHint = class(TTyCustomBalloonHint)
  published
    property Title;
    property HideInterval;
  end;

  TThirdMessage = class(TTyCustomMessage)
  published
    property Msg;
    property Buttons;
  end;

  TThirdInputDialog = class(TTyCustomInputDialog)
  published
    property Prompt;
    property Value;
  end;

implementation

{ T-a: a non-visual component is created without an owner just as well. }
procedure CheckCreatesWithoutOwner(AClass: TComponentClass);
var
  c: TComponent;
begin
  c := AClass.Create(nil);
  try
    TAssert.AssertNotNull('T-a: ' + AClass.ClassName + '.Create(nil)', c);
  finally
    c.Free;
  end;
end;

{ ------------------------------------------------------------------ Task 27: controllers }

procedure TTyCustomClassesP4Test.TestThirdStyleController;
var
  third, back: TThirdStyleController;
  c: TTyCustomStyleController;
begin
  CheckCreatesWithoutOwner(TThirdStyleController);
  third := TThirdStyleController.Create(FForm);
  CheckPublishesOnly(TThirdStyleController, ['ThemeName', 'Mode']);
  { ThemeName and ThemeFile are one source (setting either clears the other), so the property
    left out is Density. A name nobody registered is recorded all the same. }
  third.ThemeName := 'p4-unregistered-theme';
  third.Mode := 'dark';
  third.Density := tdModern;
  CheckStreamText(third, ['ThemeName', 'Mode'], 'Density');
  back := TThirdStyleController.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: ThemeName round-trips', 'p4-unregistered-theme', back.ThemeName);
  AssertEquals('T-c: Mode round-trips', 'dark', back.Mode);
  AssertTrue('T-c: the unpublished Density stayed at its default', back.Density = tdClassic);
  CheckFreshDefaults(TThirdStyleController, ['ThemeName', 'Mode']);
  c := third;
  c.HotReload := True;
  AssertTrue('T-v: HotReload is public through a TTyCustomStyleController reference',
    third.HotReload);
end;

procedure TTyCustomClassesP4Test.TestThirdNativeStyler;
var
  third, back: TThirdNativeStyler;
  c: TTyCustomNativeStyler;
begin
  CheckCreatesWithoutOwner(TThirdNativeStyler);
  third := TThirdNativeStyler.Create(FForm);
  CheckPublishesOnly(TThirdNativeStyler, ['Enabled', 'ApplyFontSize']);
  AssertTrue('the fresh styler is enabled (or the round trip proves nothing)', third.Enabled);
  third.Enabled := False;
  third.ApplyFontSize := True;
  third.ApplyFontName := True;
  CheckStreamText(third, ['Enabled', 'ApplyFontSize'], 'ApplyFontName');
  back := TThirdNativeStyler.Create(FForm);
  StreamInto(third, back);
  AssertFalse('T-c: Enabled round-trips', back.Enabled);
  AssertTrue('T-c: ApplyFontSize round-trips', back.ApplyFontSize);
  AssertFalse('T-c: the unpublished ApplyFontName stayed at its default', back.ApplyFontName);
  CheckFreshDefaults(TThirdNativeStyler, ['Enabled', 'ApplyFontSize']);
  c := third;
  c.Root := FForm;
  AssertTrue('T-v: Root is public through a TTyCustomNativeStyler reference', third.Root = FForm);
end;

{ ------------------------------------------------------------------ Task 28: icon fonts and images }

procedure TTyCustomClassesP4Test.TestThirdIconFont;
var
  third, back: TThirdIconFont;
  c: TTyCustomIconFont;
begin
  CheckCreatesWithoutOwner(TThirdIconFont);
  third := TThirdIconFont.Create(FForm);
  CheckPublishesOnly(TThirdIconFont, ['FontFamily', 'Glyphs']);
  third.FontFamily := 'p4-family';
  third.MapGlyph('save', $F0C7);
  { A file that is not there: the name is still recorded (LoadError says why it did not take). }
  third.FontFile := 'p4-no-such-font.ttf';
  CheckStreamText(third, ['FontFamily', 'Glyphs'], 'FontFile');
  back := TThirdIconFont.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: FontFamily round-trips', 'p4-family', back.FontFamily);
  AssertEquals('T-c: the glyph map round-trips', Int64($F0C7), Int64(back.CodepointOf('save')));
  AssertEquals('T-c: the unpublished FontFile stayed empty', '', back.FontFile);
  CheckFreshDefaults(TThirdIconFont, ['FontFamily', 'Glyphs']);
  c := third;
  c.FontFile := '';
  AssertEquals('T-v: FontFile is public through a TTyCustomIconFont reference', '', third.FontFile);
end;

procedure TTyCustomClassesP4Test.TestThirdVirtualImageList;
var
  third, back: TThirdVirtualImageList;
  coll: TTyImageCollection;
  c: TTyCustomVirtualImageList;
  ms: TMemoryStream;
  dst: TForm;
begin
  CheckCreatesWithoutOwner(TThirdVirtualImageList);
  AssertTrue('T-b: the LCL root is TCustomImageList',
    LclRootOf(TThirdVirtualImageList.ClassParent) = TCustomImageList);
  CheckPublishesOnly(TThirdVirtualImageList, ['Names', 'Collection']);
  coll := TTyImageCollection.Create(FForm);
  coll.Name := 'P4Coll';
  third := TThirdVirtualImageList.Create(FForm);
  third.Name := 'P4List';
  third.Names.Text := 'open' + LineEnding + 'save';
  third.Collection := coll;
  AssertEquals('precondition: the fresh list is 16 px (or the round trip proves nothing)', 16,
    third.DefaultSize);
  third.DefaultSize := 24;
  CheckStreamText(third, ['Names', 'Collection'], 'DefaultSize');
  { Collection is a component reference: stream the form that owns both, as an .lfm does. }
  dst := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(FForm);
    ms.Position := 0;
    ms.ReadComponent(dst);
    back := dst.FindComponent('P4List') as TThirdVirtualImageList;
    AssertEquals('T-c: Names round-trip', 2, back.Names.Count);
    AssertEquals('T-c: in order', 'save', back.Names[1]);
    AssertTrue('T-c: the Collection reference round-trips',
      back.Collection = dst.FindComponent('P4Coll'));
    AssertEquals('T-c: the unpublished DefaultSize stayed at its default', 16, back.DefaultSize);
  finally
    ms.Free;
    dst.Free;
  end;
  CheckFreshDefaults(TThirdVirtualImageList, ['Names', 'Collection']);
  c := third;
  c.GlyphColor := $FF336699;
  AssertEquals('T-v: GlyphColor is public through a TTyCustomVirtualImageList reference',
    Int64($FF336699), Int64(third.GlyphColor));
end;

{ S28-1 (A28-1). The bundled Lucide list takes the image-drawing unit's on-demand vector path
  and resolves an ImageName to its index. Before 4.0 ImageDraw asked `is TTyVirtualImageList`,
  which the Lucide list answered True; on the custom chain it answers False, and only
  `is TTyCustomVirtualImageList` still finds it -- asked the old way, every control fed a Lucide
  list falls back to the baked raster path and an ImageName finds nothing. }
procedure TTyCustomClassesP4Test.TestLucideImageListTakesTheVectorPath;
var
  list: TTyLucideImageList;
  img: TTyImage;
  bmp: TBGRABitmap;
  x, y: Integer;
  ink: Boolean;
begin
  list := TTyLucideImageList.Create(FForm);
  AssertFalse('the Lucide list is not a TTyVirtualImageList since 4.0 (or this proves nothing)',
    TObject(list) is TTyVirtualImageList);
  list.Names.Text := TyIconHouse + LineEnding + TyIconSettings;
  AssertFalse('it is drawn on demand, as a vector, not from baked rasters', TyImageIsBaked(list));
  AssertEquals('its count is its name list', 2, TyImageCount(list));
  AssertEquals('a name resolves to its slot', 1, TyImageIndexOfName(list, TyIconSettings));
  AssertEquals('and a slot to its name', TyIconHouse, TyImageNameOfIndex(list, 0));
  img := TTyImage.Create(FForm);
  img.Parent := FForm;
  img.Images := list;
  img.ImageName := TyIconSettings;
  AssertEquals('a TTyImage fed the Lucide list finds the icon by name', 1, img.ImageIndex);
  bmp := TyRenderImage(list, 1, 24, 96, False);
  try
    AssertNotNull('the icon renders', bmp);
    AssertEquals('at exactly the size asked for (the vector path)', 24, bmp.Width);
    ink := False;
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
        if bmp.GetPixel(x, y).alpha <> 0 then ink := True;
    AssertTrue('with ink in it', ink);
  finally
    bmp.Free;
  end;
end;

{ S28-2 (D11, forced). Every IconFont property names TTyCustomIconFont, because the bundled
  TTyLucideIconFont is no TTyIconFont since 4.0. Compile-time first: these assignments do not
  compile against a TTyIconFont-typed property. }
procedure TTyCustomClassesP4Test.TestLucideIconFontFitsAnIconFontProperty;
var
  fnt: TTyLucideIconFont;
  ci: TTyCharImage;
  gb: TTyGlyphButton;
begin
  fnt := TTyLucideIconFont.Create(FForm);
  AssertFalse('the Lucide font is not a TTyIconFont since 4.0 (or this proves nothing)',
    TObject(fnt) is TTyIconFont);
  ci := TTyCharImage.Create(FForm);
  ci.Parent := FForm;
  ci.IconFont := fnt;
  ci.GlyphName := TyIconHouse;
  AssertTrue('the char image reaches the glyph through the Lucide font',
    ci.IconFont.HasGlyph(ci.GlyphName));
  gb := TTyGlyphButton.Create(FForm);
  gb.Parent := FForm;
  gb.IconFont := fnt;
  AssertTrue('a glyph button takes it too', gb.IconFont = fnt);
  FreeAndNil(fnt);
  AssertNull('and lets go of it when it is freed', ci.IconFont);
end;

{ D11, the LCL way (Images: TCustomImageList): the component-reference properties name the
  custom classes, so a third party's font or collection is assignable. RTTI pins the declared
  type; G6 holds the rest of each row to 3.0. }
procedure CheckPropType(AClass: TClass; const AProp, AType: string);
var
  pi: PPropInfo;
begin
  pi := GetPropInfo(AClass, AProp);
  TAssert.AssertNotNull(AClass.ClassName + '.' + AProp + ' is published', pi);
  TAssert.AssertEquals(AClass.ClassName + '.' + AProp + ' names the custom class', AType,
    pi^.PropType^.Name);
end;

procedure TTyCustomClassesP4Test.TestImagePropertiesNameTheCustomClasses;
begin
  CheckPropType(TTyCharImage, 'IconFont', 'TTyCustomIconFont');
  CheckPropType(TTyGlyphButton, 'IconFont', 'TTyCustomIconFont');
  CheckPropType(TTyVirtualImageList, 'IconFont', 'TTyCustomIconFont');
  CheckPropType(TTyGlyphButton, 'Images', 'TTyCustomImageCollection');
  CheckPropType(TTyToolBar, 'HotImages', 'TTyCustomImageCollection');
  CheckPropType(TTyRibbonBackstage, 'Images', 'TTyCustomImageCollection');
  CheckPropType(TTyVirtualImageList, 'Collection', 'TTyCustomImageCollection');
end;

{ ------------------------------------------------------------------ Task 29: hints and notifications }

procedure TTyCustomClassesP4Test.TestThirdPopover;
var
  third, back: TThirdPopover;
  pnl: TTyPanel;
  c: TTyCustomPopover;
  ms: TMemoryStream;
  dst: TForm;
begin
  CheckCreatesWithoutOwner(TThirdPopover);
  CheckPublishesOnly(TThirdPopover, ['Content', 'Placement']);
  pnl := TTyPanel.Create(FForm);
  pnl.Name := 'P4PopContent';
  pnl.Parent := FForm;
  third := TThirdPopover.Create(FForm);
  third.Name := 'P4Pop';
  third.Content := pnl;
  third.Placement := ppTop;
  third.Title := 'Hidden title';
  CheckStreamText(third, ['Content', 'Placement'], 'Title');
  { Content is a component reference: stream the form that owns both, as an .lfm does. }
  dst := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(FForm);
    ms.Position := 0;
    ms.ReadComponent(dst);
    back := dst.FindComponent('P4Pop') as TThirdPopover;
    AssertTrue('T-c: the Content reference round-trips',
      back.Content = dst.FindComponent('P4PopContent'));
    AssertTrue('T-c: Placement round-trips', back.Placement = ppTop);
    AssertEquals('T-c: the unpublished Title stayed empty', '', back.Title);
  finally
    ms.Free;
    dst.Free;
  end;
  CheckFreshDefaults(TThirdPopover, ['Content', 'Placement']);
  { T-k: the popover answers its theme keys as class functions (it is not ITyStyleable); they
    live on the custom class, so a third party's popover reads the library's rules. }
  AssertEquals('T-k: StyleTypeKey', TTyPopover.StyleTypeKey, TThirdPopover.StyleTypeKey);
  AssertEquals('T-k: TitleStyleTypeKey', TTyPopover.TitleStyleTypeKey,
    TThirdPopover.TitleStyleTypeKey);
  c := third;
  c.ShowArrow := False;
  AssertFalse('T-v: ShowArrow is public through a TTyCustomPopover reference', third.ShowArrow);
end;

procedure TTyCustomClassesP4Test.TestThirdNotification;
var
  third, back: TThirdNotification;
  c: TTyCustomNotification;
begin
  CheckCreatesWithoutOwner(TThirdNotification);
  third := TThirdNotification.Create(FForm);
  CheckPublishesOnly(TThirdNotification, ['Title', 'Message']);
  third.Title := 'Saved';
  third.Message := 'All changes are on disk.';
  third.Closable := False;
  CheckStreamText(third, ['Title', 'Message'], 'Closable');
  back := TThirdNotification.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Title round-trips', 'Saved', back.Title);
  AssertEquals('T-c: Message round-trips', 'All changes are on disk.', back.Message);
  AssertTrue('T-c: the unpublished Closable stayed at its default', back.Closable);
  CheckFreshDefaults(TThirdNotification, ['Title', 'Message']);
  AssertEquals('T-k: StyleTypeKey', TTyNotification.StyleTypeKey, TThirdNotification.StyleTypeKey);
  AssertEquals('T-k: CloseStyleTypeKey', TTyNotification.CloseStyleTypeKey,
    TThirdNotification.CloseStyleTypeKey);
  c := third;
  c.Duration := 1234;
  AssertEquals('T-v: Duration is public through a TTyCustomNotification reference', 1234,
    third.Duration);
end;

procedure TTyCustomClassesP4Test.TestThirdHintAndBalloonHint;
var
  h, hb: TThirdHint;
  b, bb: TThirdBalloonHint;
  ch: TTyCustomHint;
  cb: TTyCustomBalloonHint;
begin
  CheckCreatesWithoutOwner(TThirdHint);
  CheckCreatesWithoutOwner(TThirdBalloonHint);
  CheckPublishesOnly(TThirdHint, ['Active']);
  CheckPublishesOnly(TThirdBalloonHint, ['Title', 'HideInterval']);
  { Active swaps the application's hint window class; turn it off for the round trip. }
  h := TThirdHint.Create(FForm);
  h.Active := False;
  CheckStreamText(h, ['Active'], '');
  { Two round trips in one test: the copies get no owner, or the reader's generated root names
    collide on the shared form. }
  hb := TThirdHint.Create(nil);
  try
    StreamInto(h, hb);
    AssertFalse('T-c: Active round-trips', hb.Active);
  finally
    hb.Free;
  end;
  b := TThirdBalloonHint.Create(FForm);
  b.Title := 'Caps Lock is on';
  b.HideInterval := 2500;
  b.Description := 'Hidden description';
  CheckStreamText(b, ['Title', 'HideInterval'], 'Description');
  bb := TThirdBalloonHint.Create(nil);
  try
    StreamInto(b, bb);
    AssertEquals('T-c: Title round-trips', 'Caps Lock is on', bb.Title);
    AssertEquals('T-c: HideInterval round-trips', 2500, bb.HideInterval);
    AssertEquals('T-c: the unpublished Description stayed empty', '', bb.Description);
  finally
    bb.Free;
  end;
  CheckFreshDefaults(TThirdBalloonHint, ['Title', 'HideInterval']);
  ch := h;
  ch.Active := False;
  AssertFalse('T-v: Active is public through a TTyCustomHint reference', h.Active);
  cb := b;
  cb.Icon := biInfo;
  AssertTrue('T-v: Icon is public through a TTyCustomBalloonHint reference', b.Icon = biInfo);
end;

{ ------------------------------------------------------------------ Task 30: dialogs }

procedure TTyCustomClassesP4Test.TestThirdMessage;
var
  third, back: TThirdMessage;
  c: TTyCustomMessage;
begin
  CheckCreatesWithoutOwner(TThirdMessage);
  third := TThirdMessage.Create(FForm);
  CheckPublishesOnly(TThirdMessage, ['Msg', 'Buttons']);
  third.Msg := 'Discard the changes?';
  third.Buttons := [mbYes, mbNo];
  third.DlgType := mtWarning;
  CheckStreamText(third, ['Msg', 'Buttons'], 'DlgType');
  back := TThirdMessage.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Msg round-trips', 'Discard the changes?', back.Msg);
  AssertTrue('T-c: Buttons round-trip', back.Buttons = [mbYes, mbNo]);
  AssertTrue('T-c: the unpublished DlgType stayed at its default', back.DlgType = mtInformation);
  CheckFreshDefaults(TThirdMessage, ['Msg', 'Buttons']);
  c := third;
  c.Title := 'Close';
  AssertEquals('T-v: Title is public through a TTyCustomMessage reference', 'Close', third.Title);
end;

procedure TTyCustomClassesP4Test.TestThirdInputDialog;
var
  third, back: TThirdInputDialog;
  c: TTyCustomInputDialog;
begin
  CheckCreatesWithoutOwner(TThirdInputDialog);
  third := TThirdInputDialog.Create(FForm);
  CheckPublishesOnly(TThirdInputDialog, ['Prompt', 'Value']);
  third.Prompt := 'Name:';
  third.Value := 'untitled';
  third.Caption := 'Hidden caption';
  CheckStreamText(third, ['Prompt', 'Value'], 'Caption');
  back := TThirdInputDialog.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Prompt round-trips', 'Name:', back.Prompt);
  AssertEquals('T-c: Value round-trips', 'untitled', back.Value);
  AssertEquals('T-c: the unpublished Caption stayed empty', '', back.Caption);
  CheckFreshDefaults(TThirdInputDialog, ['Prompt', 'Value']);
  c := third;
  c.Caption := 'Rename';
  AssertEquals('T-v: Caption is public through a TTyCustomInputDialog reference', 'Rename',
    third.Caption);
end;

{ Plan appendix F: the dialogs with an LCL counterpart that is split (TCustomTaskDialog) or with
  none are split; the TCommonDialog family stays unsplit, as LCL leaves it, and so do the
  TForm-role classes. The structural guard G5 holds every registered class to one of the two
  lists; this pins the dialog half by name, so a change of mind shows up here. }
procedure TTyCustomClassesP4Test.TestDialogsSplitTheLclWay;

  procedure CheckSplit(AClass: TClass);
  begin
    AssertEquals(AClass.ClassName + ' sits on its custom class',
      'TTyCustom' + Copy(AClass.ClassName, 4, MaxInt), AClass.ClassParent.ClassName);
  end;

begin
  CheckSplit(TTyMessage);
  CheckSplit(TTyInputDialog);
  CheckSplit(TTyPasswordDialog);
  CheckSplit(TTyTextDialog);
  CheckSplit(TTySelectValueDialog);
  CheckSplit(TTyProgressDialog);
  CheckSplit(TTyAboutDialog);
  CheckSplit(TTyIconBrowserDialog);
  AssertEquals('TTyAboutDialog keeps TComponent under its custom class (its Version is the app''s)',
    'TComponent', TTyAboutDialog.ClassParent.ClassParent.ClassName);
  AssertEquals('TTyDialog is not split (the TForm role)', 'TTyForm', TTyDialog.ClassParent.ClassName);
end;

initialization
  RegisterClasses([TThirdStyleController, TThirdNativeStyler, TThirdIconFont,
    TThirdVirtualImageList, TThirdPopover, TThirdNotification, TThirdHint, TThirdBalloonHint,
    TThirdMessage, TThirdInputDialog]);
  RegisterTest(TTyCustomClassesP4Test);
end.
