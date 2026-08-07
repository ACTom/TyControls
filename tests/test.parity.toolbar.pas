unit test.parity.toolbar;
{$mode objfpc}{$H+}

{ API-parity guards for TTyToolBar.Images and TTyToolBar.ShowCaptions.

  Both used to be published-but-inert knobs: Images was an LCL TImageList (a type NO
  ty control can draw from -- every icon in this library comes from the name-keyed BGRA
  TTyImageCollection), and ShowCaptions was stored, triggered a relayout and was then
  read by nothing. The Object Inspector offered two settings the control ignored.

  These tests pin the wiring that replaced them:
    * the bar LENDS its TTyImageCollection to tool buttons that have none of their own,
      follows/retracts only the reference it lent, and never touches a tool that carries
      its own collection;
    * ShowCaptions reaches each tool's ShowCaption, which makes a tool icon-only, but
      never overrides a per-tool ShowCaption the host wrote itself.

  The paint tests are the ones that actually prove "icon-only": a property flag that
  flips without changing a single pixel would be the same lie in a new place. }

interface
uses
  Classes, SysUtils, Types, TypInfo, Controls, Graphics, Forms,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ImageCollection, tyControls.GlyphButtons, tyControls.ToolBar;

type
  { Exposes the protected paint path so the glyph/caption composite is renderable headlessly. }
  TSpeedButtonAccess = class(TTySpeedButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { Shared fixture: a bar on a form, plus two distinct icon collections. }
  TToolBarParityFixture = class(TTestCase)
  protected
    FForm: TForm;
    FBar: TTyToolBar;
    FColl: TTyImageCollection;
    FOther: TTyImageCollection;
    FTool: TTySpeedButton;
    procedure SetUp; override;
    procedure TearDown; override;
    { A tool button parented onto the bar (nothing else set). }
    function AddTool: TTySpeedButton;
  end;

  TToolBarImagesParityTest = class(TToolBarParityFixture)
  published
    procedure TestImagesIsATyImageCollection;
    procedure TestLendsItsCollectionToANewTool;
    procedure TestSettingImagesReachesToolsAlreadyOnTheBar;
    procedure TestNeverClobbersAToolsOwnCollection;
    procedure TestLentReferenceFollowsTheBar;
    procedure TestTakesBackWhatItLentWhenCleared;
    procedure TestFreedCollectionIsNilled;
  end;

  TToolBarShowCaptionsParityTest = class(TToolBarParityFixture)
  published
    procedure TestShowCaptionIsPublishedAndDefaultsTrue;
    procedure TestBarPropagatesShowCaptionsToTools;
    procedure TestExplicitToolShowCaptionSurvivesTheBar;
    procedure TestExplicitShowCaptionPinsEvenWhenItMatchesTheBar;
    procedure TestIconOnlyRectCenters;
    procedure TestIconOnlyRectClampsAndDegenerates;
  end;

  { TTyToolButton's LCL surface: the six styles under LCL's own identifiers, the properties
    that exist, and — just as load-bearing — the ones that deliberately do NOT.

    The whole class exists because plans/2026-08-04 lists "TToolButton 整个类" as missing, so
    what is guarded here is the SHAPE of the port: an .lfm line copied out of an LCL form has
    to read back, and no property may be offered that the control does not honour. }
  TToolButtonApiParityTest = class(TTestCase)
  published
    procedure TestStyleEnumIsLclsSixInLclsOrder;
    procedure TestStyleIsPublishedAndDefaultsToButton;
    procedure TestGroupedIsTheOneGroupingModel;
    procedure TestLclsLyingPropertiesAreNotCopied;
    procedure TestImageIndexIsPublishedAndDefaultsMinusOne;
    procedure TestWrapIsPublishedAndDefaultsFalse;
    procedure TestDropDownMenuIsTheThemedMenu;
    procedure TestArrowEventIsPublished;
    procedure TestATabStopWouldBreakTheBar;
    procedure TestSpaceHolderBorrowsTheSeparatorKey;
  end;

  { The BAR's own LCL members this batch added — the published surface and, just as
    load-bearing, the two that are deliberately absent. Behaviour lives in
    tests/test.toolbar.pas (TToolBarMembersTest) and test.toolbar.paintbutton.pas;
    what is pinned HERE is the API shape an .lfm and the Object Inspector see. }
  TToolBarMembersApiParityTest = class(TTestCase)
  published
    procedure TestButtonWidthIsPublishedAndUnsetMeansNoFloor;
    procedure TestDropDownWidthIsPublishedAndDefaultsToTheToken;
    procedure TestListIsPublishedAndTheInvertedDefaultIsDeliberate;
    procedure TestOnPaintButtonIsPublishedWithLclsShape;
    procedure TestHotAndDisabledImagesAreDeliberatelyAbsent;
    procedure TestGlyphLayoutStreamsOnlyWhenTheHostWroteIt;
  end;

  { Pixel proof that ShowCaption changes what is painted, not just a field. }
  TGlyphButtonCaptionPaintTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FColl: TTyImageCollection;
    { A speed button on FForm/FCtl with a solid 'ico' image glyph tinted GREEN and a
      caption drawn in the theme's RED, so glyph ink and caption ink are separable. }
    function MakeButton(AShowCaption: Boolean; const ACaption: string): TSpeedButtonAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCaptionShownPutsGlyphAtTheLeft;
    procedure TestIconOnlyHidesCaptionAndCentersGlyph;
    procedure TestNoIconKeepsItsCaptionEvenWhenSuppressed;
  end;

implementation

const
  { Paint-test canvas. Content box == client box (the theme sets padding 0), so the
    expected glyph rects are computed straight from these. }
  BtnW = 80;
  BtnH = 40;
  GlyphPx = 16;

procedure TSpeedButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ ---- ink probes ---------------------------------------------------------- }

{ The glyph is tinted pure green, the caption is drawn in pure red and the button
  background is black, so a channel-dominance test tells the two inks apart even on
  antialiased edges. }
function IsGlyphInk(const P: TBGRAPixel): Boolean;
begin
  Result := (P.green > 100) and (P.green > P.red + 40) and (P.green > P.blue + 40);
end;

function IsCaptionInk(const P: TBGRAPixel): Boolean;
begin
  Result := (P.red > 100) and (P.red > P.green + 40) and (P.red > P.blue + 40);
end;

{ Horizontal centre of the glyph ink, or -1 when none was painted. }
function GlyphInkCenterX(ABmp: TBGRABitmap): Integer;
var
  x, y, lo, hi: Integer;
begin
  lo := MaxInt; hi := -1;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
      if IsGlyphInk(ABmp.GetPixel(x, y)) then
      begin
        if x < lo then lo := x;
        if x > hi then hi := x;
      end;
  if hi < 0 then Exit(-1);
  Result := (lo + hi) div 2;
end;

function HasCaptionInk(ABmp: TBGRABitmap): Boolean;
var
  x, y: Integer;
begin
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
      if IsCaptionInk(ABmp.GetPixel(x, y)) then Exit(True);
  Result := False;
end;

{ Render B into a BtnW x BtnH canvas and re-read it. Caller frees the result. }
function RenderButton(B: TSpeedButtonAccess): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(BtnW, BtnH);
    // Pre-fill white: the canvas start state is otherwise undefined, and white is
    // neither glyph ink nor caption ink under the probes above.
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, BtnW, BtnH);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, BtnW, BtnH), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ ---- TToolBarParityFixture ----------------------------------------------- }

procedure TToolBarParityFixture.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 200);
  FBar := TTyToolBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alNone;          // keep the LCL align engine off our explicit bounds
  FBar.SetBounds(0, 0, 300, 30);
  FColl := TTyImageCollection.Create(FForm);
  FOther := TTyImageCollection.Create(FForm);
  FTool := nil;
end;

procedure TToolBarParityFixture.TearDown;
begin
  FreeAndNil(FForm);   // owns the bar, the tools and both collections
end;

function TToolBarParityFixture.AddTool: TTySpeedButton;
begin
  Result := TTySpeedButton.Create(FForm);
  Result.Parent := FBar;
end;

{ ---- TToolBarImagesParityTest -------------------------------------------- }

procedure TToolBarImagesParityTest.TestImagesIsATyImageCollection;
var
  PI: PPropInfo;
begin
  PI := GetPropInfo(FBar, 'Images');
  AssertTrue('Images is published', PI <> nil);
  // An LCL TImageList is index-keyed and nothing in this library renders from one:
  // whatever a host assigned there could never reach a tool button. The bar's icon
  // source has to be the same name-keyed BGRA collection the buttons consume.
  AssertEquals('Images must be the collection the tool buttons can actually draw from',
    'TTyImageCollection', string(PI^.PropType^.Name));
end;

procedure TToolBarImagesParityTest.TestLendsItsCollectionToANewTool;
begin
  FBar.Images := FColl;
  FTool := AddTool;    // joins the bar afterwards
  AssertSame('a tool with no collection of its own draws from the bar''s',
    FColl, FTool.Images);
end;

procedure TToolBarImagesParityTest.TestSettingImagesReachesToolsAlreadyOnTheBar;
begin
  FTool := AddTool;    // on the bar BEFORE it has any collection
  AssertTrue('no collection yet', FTool.Images = nil);
  FBar.Images := FColl;
  AssertSame('assigning Images reaches the tools already docked', FColl, FTool.Images);
end;

procedure TToolBarImagesParityTest.TestNeverClobbersAToolsOwnCollection;
begin
  FTool := AddTool;
  FTool.Images := FOther;          // the app made its own choice for this tool
  FBar.Images := FColl;
  AssertSame('the bar must not overwrite a tool that carries its own collection',
    FOther, FTool.Images);
  FBar.Images := nil;
  AssertSame('...and clearing the bar must not take away what it never lent',
    FOther, FTool.Images);
end;

procedure TToolBarImagesParityTest.TestLentReferenceFollowsTheBar;
begin
  FBar.Images := FColl;
  FTool := AddTool;
  AssertSame('lent the first collection', FColl, FTool.Images);
  FBar.Images := FOther;
  AssertSame('the lent reference follows the bar to the new collection',
    FOther, FTool.Images);
end;

procedure TToolBarImagesParityTest.TestTakesBackWhatItLentWhenCleared;
begin
  FBar.Images := FColl;
  FTool := AddTool;
  FBar.Images := nil;
  AssertTrue('clearing the bar takes back the reference it lent', FTool.Images = nil);
end;

procedure TToolBarImagesParityTest.TestFreedCollectionIsNilled;
var
  C: TTyImageCollection;
begin
  // Owner nil ON PURPOSE: with no shared owner the opRemove only arrives if the bar
  // registered a FreeNotification, so this pins the registration, not the Notification
  // override. Without it the bar (and every reference it lent) would dangle.
  C := TTyImageCollection.Create(nil);
  try
    FBar.Images := C;
    AssertSame('assigned', C, FBar.Images);
  finally
    FreeAndNil(C);
  end;
  AssertTrue('freeing the collection nils the bar''s reference', FBar.Images = nil);
end;

{ ---- TToolBarShowCaptionsParityTest -------------------------------------- }

procedure TToolBarShowCaptionsParityTest.TestShowCaptionIsPublishedAndDefaultsTrue;
var
  B: TTyGlyphButton;
begin
  B := TTyGlyphButton.Create(nil);
  try
    AssertTrue('ShowCaption is published on the glyph button',
      IsPublishedProp(B, 'ShowCaption'));
    // A glyph button used on its own is icon + caption; only a container asks for
    // icon-only, so the standalone default has to stay "show it".
    AssertTrue('a glyph button shows its caption by default', B.ShowCaption);
  finally
    B.Free;
  end;
end;

procedure TToolBarShowCaptionsParityTest.TestBarPropagatesShowCaptionsToTools;
begin
  FTool := AddTool;
  // LCL parity: the bar's default (False) means icon-only tools.
  AssertFalse('a tool joins the bar with the bar''s ShowCaptions', FTool.ShowCaption);
  FBar.ShowCaptions := True;
  AssertTrue('turning captions on reaches the tools', FTool.ShowCaption);
  FBar.ShowCaptions := False;
  AssertFalse('turning captions off reaches the tools', FTool.ShowCaption);
end;

procedure TToolBarShowCaptionsParityTest.TestExplicitToolShowCaptionSurvivesTheBar;
begin
  FTool := AddTool;
  FTool.ShowCaption := True;       // this one tool wants its label whatever the bar says
  FBar.ShowCaptions := False;
  AssertTrue('a per-tool ShowCaption must survive the bar''s default', FTool.ShowCaption);
  FBar.ShowCaptions := True;
  FBar.ShowCaptions := False;
  AssertTrue('...and every later change to it', FTool.ShowCaption);
end;

procedure TToolBarShowCaptionsParityTest.TestExplicitShowCaptionPinsEvenWhenItMatchesTheBar;
begin
  FTool := AddTool;                // joins with the bar's default: ShowCaption = False
  FTool.ShowCaption := False;      // the host asks for icon-only ON THIS TOOL, same value
  // Writing the property is the claim, not the value change: if the claim were only
  // recorded when the value actually moved, this tool would silently follow the bar
  // back up. It must stay icon-only.
  FBar.ShowCaptions := True;
  AssertFalse('writing the value the bar already pushed still pins the tool',
    FTool.ShowCaption);
end;

procedure TToolBarShowCaptionsParityTest.TestIconOnlyRectCenters;
var
  R: TRect;
begin
  // 100x40 box, 20px glyph -> centred on BOTH axes: (40,10)-(60,30). The caption-less
  // glyph must NOT keep the glyph-left anchor, or an icon-only tool would hug its left
  // edge with dead space where the text used to be.
  R := TyGlyphButtonIconOnlyRect(Rect(0, 0, 100, 40), 20);
  AssertEquals('icon-only glyph.Left', 40, R.Left);
  AssertEquals('icon-only glyph.Top', 10, R.Top);
  AssertEquals('icon-only glyph.Right', 60, R.Right);
  AssertEquals('icon-only glyph.Bottom', 30, R.Bottom);
  // An offset content rect centres inside ITS box, not the control's origin.
  R := TyGlyphButtonIconOnlyRect(Rect(10, 5, 50, 25), 10);
  AssertEquals('offset icon-only glyph.Left', 25, R.Left);
  AssertEquals('offset icon-only glyph.Top', 10, R.Top);
end;

procedure TToolBarShowCaptionsParityTest.TestIconOnlyRectClampsAndDegenerates;
var
  R: TRect;
begin
  // Oversized glyph clamps to the box's SHORT side and stays inside the box.
  R := TyGlyphButtonIconOnlyRect(Rect(0, 0, 30, 18), 50);
  AssertEquals('clamped to the short side (w)', 18, R.Right - R.Left);
  AssertEquals('clamped to the short side (h)', 18, R.Bottom - R.Top);
  AssertTrue('never overhangs the content box',
    (R.Left >= 0) and (R.Right <= 30) and (R.Top >= 0) and (R.Bottom <= 18));
  // No glyph -> an empty rect at the content origin, never a negative one.
  R := TyGlyphButtonIconOnlyRect(Rect(5, 7, 105, 47), 0);
  AssertEquals('no glyph -> empty (w)', 0, R.Right - R.Left);
  AssertEquals('no glyph -> empty (h)', 0, R.Bottom - R.Top);
  // Degenerate box -> likewise empty (and no negative dimension).
  R := TyGlyphButtonIconOnlyRect(Rect(4, 4, 4, 4), 16);
  AssertEquals('degenerate box -> empty (w)', 0, R.Right - R.Left);
  AssertEquals('degenerate box -> empty (h)', 0, R.Bottom - R.Top);
end;

{ ---- TToolButtonApiParityTest --------------------------------------------- }

procedure TToolButtonApiParityTest.TestStyleEnumIsLclsSixInLclsOrder;
var
  PI: PPropInfo;
  TD: PTypeData;
  B: TTyToolButton;
const
  { LCL's TToolButtonStyle, comctrls.pp:2068. An .lfm stores an enum by IDENTIFIER, so a
    `Style = tbsDropDown` copied out of an LCL form only loads here if the name matches — and
    the ORDER matters too, because `default tbsButton` and any ordinal cast ride on it. }
  Expect: array[0..5] of string = (
    'tbsButton', 'tbsCheck', 'tbsDropDown', 'tbsSeparator', 'tbsDivider', 'tbsButtonDrop');
var
  i: Integer;
begin
  B := TTyToolButton.Create(nil);
  try
    PI := GetPropInfo(B, 'Style');
    AssertTrue('Style is published', PI <> nil);
    AssertEquals('Style is an enumeration', Ord(tkEnumeration), Ord(PI^.PropType^.Kind));
    TD := GetTypeData(PI^.PropType);
    AssertEquals('exactly six members — no more, no fewer', 5, TD^.MaxValue);
    AssertEquals('and they start at 0', 0, TD^.MinValue);
    for i := 0 to High(Expect) do
      AssertEquals(Format('member %d', [i]), Expect[i],
        GetEnumName(PI^.PropType, i));
  finally
    B.Free;
  end;
end;

procedure TToolButtonApiParityTest.TestStyleIsPublishedAndDefaultsToButton;
var
  B: TTyToolButton;
begin
  B := TTyToolButton.Create(nil);
  try
    AssertEquals('a fresh tool button is a plain command button',
      Ord(tbsButton), Ord(B.Style));
    // The declared default has to agree with the constructor, or the streamer writes Style
    // into every .lfm just to restate what Create already did.
    AssertEquals('the declared default agrees with the constructor',
      Ord(tbsButton), GetPropInfo(B, 'Style')^.Default);
  finally
    B.Free;
  end;
end;

procedure TToolButtonApiParityTest.TestGroupedIsTheOneGroupingModel;
var
  B: TTyToolButton;
begin
  { THE DECISION, pinned. LCL's TToolButton groups by ADJACENCY (Grouped: Boolean); this
    library's TTySpeedButton groups by NUMBER (GroupIndex: Integer). They answer the same
    question two different ways, so a class that published BOTH would let a host set a
    GroupIndex the adjacency rule silently ignores — a lying property by construction.
    TTyToolButton takes Grouped (it is the LCL class being ported) and must NOT carry
    GroupIndex; TTySpeedButton keeps GroupIndex and is the control to reach for when groups
    must be numbered. The two are inter-translatable: give each maximal Grouped run its own
    GroupIndex. }
  B := TTyToolButton.Create(nil);
  try
    AssertTrue('Grouped is published', IsPublishedProp(B, 'Grouped'));
    AssertFalse('...and defaults off', B.Grouped);
    AssertTrue('GroupIndex must NOT be published beside it',
      GetPropInfo(B, 'GroupIndex') = nil);
    AssertTrue('AllowAllUp is published (Grouped is unusable without it)',
      IsPublishedProp(B, 'AllowAllUp'));
  finally
    B.Free;
  end;
  // The other half of the decision: the numbered model still exists, on the other class.
  AssertTrue('TTySpeedButton keeps GroupIndex',
    GetPropInfo(TTySpeedButton, 'GroupIndex') <> nil);
  AssertTrue('...and does not carry Grouped either',
    GetPropInfo(TTySpeedButton, 'Grouped') = nil);
end;

procedure TToolButtonApiParityTest.TestLclsLyingPropertiesAreNotCopied;
begin
  { TToolButton.Marked and TToolButton.Indeterminate are declared, stored and Invalidate in
    LCL — and are then read by NOTHING in its Paint or GetButtonDrawDetail. They are lying
    properties in the REFERENCE implementation, and copying a property list wholesale is
    exactly how a port imports a defect. Left absent rather than declared-and-unhonoured, which
    is the same rule the six styles were judged by.
    If either is ever built here, build the PAINT first and delete the line — do not relax it.
    MenuItem is absent for a different reason (scope: a second menu model on top of
    DropdownMenu), and gets no assertion because it is not a lie, just missing. }
  AssertTrue('Marked must not be published until something draws it',
    GetPropInfo(TTyToolButton, 'Marked') = nil);
  AssertTrue('Indeterminate must not be published until something draws it',
    GetPropInfo(TTyToolButton, 'Indeterminate') = nil);
end;

procedure TToolButtonApiParityTest.TestImageIndexIsPublishedAndDefaultsMinusOne;
var
  B: TTyToolButton;
  PI: PPropInfo;
begin
  B := TTyToolButton.Create(nil);
  try
    PI := GetPropInfo(B, 'ImageIndex');
    AssertTrue('ImageIndex is published', PI <> nil);
    AssertEquals('the declared default is LCL''s -1', -1, PI^.Default);
    AssertEquals('and a fresh button reads back as -1', -1, B.ImageIndex);
    // It must be READABLE as well as writable: TWriter skips a setter-less property and the
    // IDE reports "Cannot read property" for a write-only one.
    AssertTrue('has a getter', PI^.GetProc <> nil);
    AssertTrue('has a setter', PI^.SetProc <> nil);
  finally
    B.Free;
  end;
end;

procedure TToolButtonApiParityTest.TestWrapIsPublishedAndDefaultsFalse;
var
  B: TTyToolButton;
begin
  B := TTyToolButton.Create(nil);
  try
    AssertTrue('Wrap is published', IsPublishedProp(B, 'Wrap'));
    AssertFalse('and defaults off', B.Wrap);
    AssertEquals('the declared default agrees', 0, GetPropInfo(B, 'Wrap')^.Default);
  finally
    B.Free;
  end;
end;

procedure TToolButtonApiParityTest.TestDropDownMenuIsTheThemedMenu;
var
  B: TTyToolButton;
  PI: PPropInfo;
begin
  { LCL types it TPopupMenu. Here it is TTyPopupMenu — which IS a TPopupMenu descendant, so
    this is a NARROWING and not a different concept, and it is the type the library's other two
    drop-down buttons already take. A plain TPopupMenu here would pop the platform menu in the
    middle of a self-drawn tool bar. }
  B := TTyToolButton.Create(nil);
  try
    PI := GetPropInfo(B, 'DropdownMenu');
    AssertTrue('DropdownMenu is published', PI <> nil);
    AssertEquals('and is the themed menu', 'TTyPopupMenu', string(PI^.PropType^.Name));
    { LCL spells it DropdownMenu (lower-case d); TTyDropDownButton spells its own property
      DropDownMenu. The two live side by side in this library, so the one on the LCL port has
      to carry the LCL spelling or reading either class's source is a coin flip.
      Asserted on PI^.Name — the identifier RTTI actually recorded — and NOT by asking
      GetPropInfo for the other spelling: GetPropInfo compares case-INSENSITIVELY in FPC, so
      that form of the check passes whichever way the property was declared. }
    AssertEquals('the LCL spelling is the one declared', 'DropdownMenu', string(PI^.Name));
  finally
    B.Free;
  end;
end;

procedure TToolButtonApiParityTest.TestArrowEventIsPublished;
var
  B: TTyToolButton;
begin
  B := TTyToolButton.Create(nil);
  try
    AssertTrue('OnArrowClick is published', IsPublishedProp(B, 'OnArrowClick'));
  finally
    B.Free;
  end;
end;

procedure TToolButtonApiParityTest.TestATabStopWouldBreakTheBar;
var
  B: TTyToolButton;
begin
  { A bar of ten tools must not plant ten dead stops in the Tab cycle, and a click on one must
    not pull focus out of the editor the command acts upon. Same call TTySpeedButton makes.
    The DECLARED default has to be False too, or a host that wants a focusable tool writes
    TabStop=True and the streamer drops it as equal to the inherited default. }
  B := TTyToolButton.Create(nil);
  try
    AssertFalse('a tool button is not a tab stop', B.TabStop);
    AssertEquals('and the declared default says so', 0, GetPropInfo(B, 'TabStop')^.Default);
  finally
    B.Free;
  end;
end;

procedure TToolButtonApiParityTest.TestSpaceHolderBorrowsTheSeparatorKey;
var
  B: TTyToolButton;
begin
  { A tbsDivider draws the standalone separator's rule, so it resolves the standalone
    separator's key: a skin that dims one dims the other, and a theme author has no second
    spelling to keep in step. A command tool button stays on 'TyButton' — it IS a push button,
    and the bar hands it the 'ghost' variant for the flat toolbar look. }
  B := TTyToolButton.Create(nil);
  try
    AssertEquals('a command tool button is a button',
      'TyButton', (B as ITyStyleable).GetStyleTypeKey);
    B.Style := tbsSeparator;
    AssertEquals('a tbsSeparator is a separator',
      'TyToolSeparator', (B as ITyStyleable).GetStyleTypeKey);
    B.Style := tbsDivider;
    AssertEquals('and so is a tbsDivider',
      'TyToolSeparator', (B as ITyStyleable).GetStyleTypeKey);
    B.Style := tbsDropDown;
    AssertEquals('back to a button', 'TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

{ ---- TToolBarMembersApiParityTest ----------------------------------------- }

procedure TToolBarMembersApiParityTest.TestButtonWidthIsPublishedAndUnsetMeansNoFloor;
var
  Bar: TTyToolBar;
  PI: PPropInfo;
begin
  Bar := TTyToolBar.Create(nil);
  try
    PI := GetPropInfo(Bar, 'ButtonWidth');
    AssertTrue('ButtonWidth is published', PI <> nil);
    AssertTrue('readable', PI^.GetProc <> nil);
    AssertTrue('and writable', PI^.SetProc <> nil);
    { DIVERGENCE from LCL, pinned: there an unset ButtonWidth is a themed ~23px floor,
      because LCL derives every button's width from content each layout. Here a width is a
      DESIGNED value the .lfm owns, so unset must mean NO floor — a default floor would
      silently widen every existing bar the day it shipped. }
    AssertEquals('unset reads back as 0 — no floor', 0, Bar.ButtonWidth);
    // The ButtonHeight storage arrangement: streamed only once the host actually wrote it.
    AssertFalse('unset does not stream', IsStoredProp(Bar, PI));
    Bar.ButtonWidth := 60;
    AssertTrue('an explicit value streams', IsStoredProp(Bar, PI));
  finally
    Bar.Free;
  end;
end;

procedure TToolBarMembersApiParityTest.TestDropDownWidthIsPublishedAndDefaultsToTheToken;
var
  Bar: TTyToolBar;
  PI: PPropInfo;
begin
  Bar := TTyToolBar.Create(nil);
  try
    PI := GetPropInfo(Bar, 'DropDownWidth');
    AssertTrue('DropDownWidth is published', PI <> nil);
    { 0 = "the theme's --drop-arrow-width owns the zone" — the tab strip's ImagesWidth
      convention, where LCL instead defaults to a native-theme measurement. The declared
      default must agree with the constructor or the streamer writes the 0 into every .lfm. }
    AssertEquals('a fresh bar follows the token', 0, Bar.DropDownWidth);
    AssertEquals('and the declared default says so', 0, PI^.Default);
  finally
    Bar.Free;
  end;
end;

procedure TToolBarMembersApiParityTest.TestListIsPublishedAndTheInvertedDefaultIsDeliberate;
var
  Bar: TTyToolBar;
  PI: PPropInfo;
begin
  Bar := TTyToolBar.Create(nil);
  try
    PI := GetPropInfo(Bar, 'List');
    AssertTrue('List is published', PI <> nil);
    { THE INVERSION, pinned (the combo's inverted pick-only default is the precedent): LCL
      defaults List=False (icon stacked above the caption). Here an auto-sized glyph takes
      the box it is given, so the stacked layout with an auto GlyphSize fills the row and
      collapses the caption — a False default would make ShowCaptions=True paint NO caption
      on every icon tool, a lying property by construction. True (icon beside caption) is
      the library's resting look; False remains available WITH an explicit GlyphSize. }
    AssertTrue('a fresh bar is in list mode — the inverted default is deliberate', Bar.List);
    AssertEquals('the declared default agrees with the constructor', 1, PI^.Default);
  finally
    Bar.Free;
  end;
end;

procedure TToolBarMembersApiParityTest.TestOnPaintButtonIsPublishedWithLclsShape;
var
  PI: PPropInfo;
begin
  PI := GetPropInfo(TTyToolBar, 'OnPaintButton');
  AssertTrue('OnPaintButton is published', PI <> nil);
  AssertEquals('and is the two-argument LCL shape (Sender + State), typed to the tool button',
    'TTyToolBarOnPaintButton', string(PI^.PropType^.Name));
end;

procedure TToolBarMembersApiParityTest.TestHotAndDisabledImagesAreDeliberatelyAbsent;
begin
  { THE REFUSAL, pinned the LyingPropertiesStayUnpublished way. LCL's HotImages /
    DisabledImages swap in a SECOND image list, keyed by the same ImageIndex, when a button
    is hovered / disabled. Two reasons they are not carried:

    * This library's glyph pipeline TINTS every collection image to the state's resolved
      TextColor (TyTintBitmapAlpha replaces RGB wholesale, keeping alpha) — so the classic
      job of those lists, a different COLOUR treatment per state, is already the THEME's,
      per skin, via the :hover / :disabled rules. A swapped image would be re-tinted the
      same way, so all a second collection could ever add is a different SHAPE per state.
    * Serving that residue would put a second, per-bar image-state model beside the theme's
      state model, with a per-name silent fallback (a name missing from the alternate
      collection shows the base icon) — a "sometimes works" surface.

    If a per-state SHAPE swap is ever really wanted, the seam is a protected virtual
    glyph-source resolver on TTyGlyphButtonBase consulted by its DrawContent — build that
    first, then delete these lines; do not relax them. }
  AssertTrue('HotImages must not be published until something honours it',
    GetPropInfo(TTyToolBar, 'HotImages') = nil);
  AssertTrue('DisabledImages must not be published until something honours it',
    GetPropInfo(TTyToolBar, 'DisabledImages') = nil);
end;

procedure TToolBarMembersApiParityTest.TestGlyphLayoutStreamsOnlyWhenTheHostWroteIt;
var
  Bar: TTyToolBar;
  B: TTyToolButton;
  PI: PPropInfo;
begin
  { The storage half of List's adopt contract. An ADOPTED layout must not stream — the
    reload would come back through the setter, claim the property for the host, and List
    could never move that button again. And the base's `default glLeft` must be GONE
    (nodefault): an explicit glLeft on a List=False bar equals the old default, so the
    default directive would suppress writing exactly the case that must survive. }
  Bar := TTyToolBar.Create(nil);
  B := TTyToolButton.Create(nil);
  try
    PI := GetPropInfo(B, 'GlyphLayout');
    AssertTrue('GlyphLayout is published on the tool button', PI <> nil);
    AssertEquals('the inherited default directive is removed (nodefault)',
      Longint($80000000), PI^.Default);
    AssertFalse('a fresh button does not stream it', IsStoredProp(B, PI));
    B.Parent := Bar;                 // joins List=True -> adopts glLeft
    Bar.List := False;               // adopts glTop
    AssertFalse('an ADOPTED layout does not stream either', IsStoredProp(B, PI));
    B.GlyphLayout := glTop;          // the host writes the very value the bar adopted
    AssertTrue('an explicit write streams, even at the adopted value', IsStoredProp(B, PI));
  finally
    B.Free;
    Bar.Free;
  end;
end;

{ ---- TGlyphButtonCaptionPaintTest ---------------------------------------- }

procedure TGlyphButtonCaptionPaintTest.SetUp;
var
  Master: TBGRABitmap;
begin
  FCtl := TTyStyleController.Create(nil);
  // Black plate, RED caption ink, no padding -> the content box IS the client box, so
  // the expected glyph rects below are exact.
  FCtl.LoadThemeCss(
    'TySpeedButton { background: #000000; color: #FF0000; padding: 0px; '
    + 'border-width: 0px; font-size: 14px; }');
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 200);
  FColl := TTyImageCollection.Create(FForm);
  // A fully opaque square master: GetBitmap scales it 1:1 into the glyph square and
  // TyTintBitmapAlpha recolours it to GlyphColor, so the drawn glyph is a solid block
  // of a known colour -- deterministic headless ink, no font required.
  Master := TBGRABitmap.Create(GlyphPx, GlyphPx, BGRAWhite);
  try
    FColl.AddBitmap('ico', Master);
  finally
    Master.Free;
  end;
end;

procedure TGlyphButtonCaptionPaintTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

function TGlyphButtonCaptionPaintTest.MakeButton(AShowCaption: Boolean;
  const ACaption: string): TSpeedButtonAccess;
begin
  Result := TSpeedButtonAccess.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;     // Scale() 1:1, so logical == device px
  Result.SetBounds(0, 0, BtnW, BtnH);
  Result.GlyphSize := GlyphPx;
  Result.GlyphColor := TyRGB(0, 255, 0);   // GREEN, distinct from the red caption ink
  Result.Caption := ACaption;
  Result.ShowCaption := AShowCaption;
end;

procedure TGlyphButtonCaptionPaintTest.TestCaptionShownPutsGlyphAtTheLeft;
var
  B: TSpeedButtonAccess;
  Img: TBGRABitmap;
  cx: Integer;
begin
  // Baseline (ShowCaption = True): glyph-left anchor -> a 16px glyph at x 0..16
  // (centre 8) with the caption drawn to its right.
  B := MakeButton(True, 'MMMM');
  B.Images := FColl;
  B.ImageName := 'ico';
  Img := RenderButton(B);
  try
    cx := GlyphInkCenterX(Img);
    AssertTrue('the glyph was painted', cx >= 0);
    AssertTrue(Format('glyph stays left-anchored beside the caption (centre x=%d, expected ~8)',
      [cx]), (cx >= 4) and (cx <= 12));
    AssertTrue('the caption is painted when ShowCaption is on', HasCaptionInk(Img));
  finally
    Img.Free;
  end;
end;

procedure TGlyphButtonCaptionPaintTest.TestIconOnlyHidesCaptionAndCentersGlyph;
var
  B: TSpeedButtonAccess;
  Img: TBGRABitmap;
  cx: Integer;
begin
  // ShowCaption = False with an icon available: NO caption ink anywhere, and the glyph
  // re-centres in the whole 80px content box (centre 40, not the left-anchored 8).
  B := MakeButton(False, 'MMMM');
  B.Images := FColl;
  B.ImageName := 'ico';
  Img := RenderButton(B);
  try
    cx := GlyphInkCenterX(Img);
    AssertTrue('the glyph is still painted', cx >= 0);
    AssertTrue(Format('icon-only re-centres the glyph (centre x=%d, expected ~40)',
      [cx]), (cx >= 36) and (cx <= 44));
    AssertFalse('icon-only must paint no caption at all', HasCaptionInk(Img));
  finally
    Img.Free;
  end;
end;

procedure TGlyphButtonCaptionPaintTest.TestNoIconKeepsItsCaptionEvenWhenSuppressed;
var
  B: TSpeedButtonAccess;
  Img: TBGRABitmap;
begin
  // No image and no icon font: there is nothing to show INSTEAD of the caption, so
  // suppressing it would paint an empty box. Since the bar's LCL-parity default is
  // ShowCaptions = False, that would blank every caption-only tool in every app.
  B := MakeButton(False, 'MMMM');   // no Images / ImageName assigned
  Img := RenderButton(B);
  try
    AssertEquals('no glyph source -> no glyph ink', -1, GlyphInkCenterX(Img));
    AssertTrue('a tool with no icon keeps its caption', HasCaptionInk(Img));
  finally
    Img.Free;
  end;
end;

initialization
  RegisterTest(TToolBarImagesParityTest);
  RegisterTest(TToolBarShowCaptionsParityTest);
  RegisterTest(TToolButtonApiParityTest);
  RegisterTest(TToolBarMembersApiParityTest);
  RegisterTest(TGlyphButtonCaptionPaintTest);
end.
