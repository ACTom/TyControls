unit test.customclasses.p3;
{$mode objfpc}{$H+}

{ Custom-class split, phase 3 (bars, ribbon, window chrome, images, pickers, the terminal and
  the tool windows). The same three kinds of test as test.customclasses.p1, on the same fixture
  and checks (TTyCustomClassesPhaseCase):

  * THIRD-PARTY MIMICS: a TTyCustomXxx descendant that publishes two properties of its own
    choosing -- it can be created (T-a), publishes exactly its LCL root's names plus the two
    (T-b), streams those two and not a property it left out (T-c), resolves the same theme
    type key and paints the same pixels as the library's final class (T-d), streams nothing
    from a fresh instance (T-e), and reaches a public property through a TTyCustomXxx
    reference (T-v). Each family also gets the messages a widgetset delivers, next to the
    final class, and must answer the same.
  * DERIVED CONTROLS SEEN BY THEIR FAMILY: from 4.0 on a TTyToolBarEx is a TTyCustomToolBar
    but no longer a TTyToolBar; library code that meant "any tool bar" asks for the custom
    class, and each such check has a test that fails when it is put back.
  * CHECKS WIDENED FOR THIRD PARTIES: a host that accepts any TTyCustomXxx child (a tool
    bar's buttons, a ribbon's pages and groups, a form's content surface, a tool-window bar's
    windows), proven with a mimic. }

interface

uses
  Classes, SysUtils, TypInfo, Types, Controls, Forms, Graphics, Menus, LCLType, LMessages,
  fpcunit, testregistry,
  test.customclasses, test.customclasses.p1,
  tyControls.Base, tyControls.Button, tyControls.GlyphButtons, tyControls.ToolBar,
  tyControls.ToolBarEx, tyControls.StatusBar, tyControls.ScrollBar, tyControls.Painter,
  tyControls.Ribbon, tyControls.RibbonGallery, tyControls.RibbonBackstage,
  tyControls.Form, tyControls.Menu, tyControls.FormSurface, tyControls.Controller,
  tyControls.CharImage, tyControls.IconFont, tyControls.Shape, tyControls.Chart,
  tyControls.ColorGrid, tyControls.Terminal, tyControls.ToolWindows,
  tyControls.ToolWindows.DesignRules;

type
  TP3RenderProc = procedure(C: TControl; ACanvas: TCanvas; const R: TRect);

  TTyCustomClassesP3Test = class(TTyCustomClassesPhaseCase)
  private
    FChanges: Integer;
    FHosts: TList;
    FLastSender: TObject;
    FData: string;
    procedure CountChange(Sender: TObject);
    procedure Launcher(Sender: TTyCustomRibbonGroup);
    procedure PaintButton(Sender: TTyCustomToolButton; AState: Integer);
    procedure DrawPanel(AStatusBar: TTyCustomStatusBar; APanel: TTyStatusPanel;
      APainter: TTyPainter; const ARect: TRect);
    procedure TermData(Sender: TObject; const AData: RawByteString);
    function NewHost: TForm;
    { Stream the form that owns ASrc and read it into a fresh form; the copy of ASrc. }
    function HostRoundTrip(ASrc: TComponent): TComponent;
    { T-d: render both through ARender onto sentinel bitmaps and compare every pixel. }
    procedure CheckSamePaint(AThird, AOwn: TControl; AW, AH: Integer; ARender: TP3RenderProc);
  protected
    procedure TearDown; override;
  published
    { Task 20: bars }
    procedure TestThirdToolBar;
    procedure TestThirdToolButton;
    procedure TestToolButtonFindsItsToolBarEx;
    procedure TestToolBarTakesAThirdPartyToolButton;
    procedure TestThirdStatusBar;
    procedure TestStatusPanelsReachAThirdPartyBar;
    procedure TestThirdScrollBar;
    { Task 21: ribbon }
    procedure TestThirdRibbonPage;
    procedure TestThirdRibbonGroup;
    procedure TestRibbonTakesAThirdPartyPage;
    procedure TestRibbonPageLaysOutAThirdPartyGroup;
    procedure TestRibbonIndexesReadBeforeTheirItemsWait;
    { Task 22: window chrome }
    procedure TestThirdTitleBar;
    procedure TestThirdMenuBar;
    procedure TestThirdFormSurface;
    procedure TestFormWiresAThirdPartySurface;
    { Task 23: images and shapes }
    procedure TestThirdCharImage;
    procedure TestThirdShape;
    procedure TestThirdChart;
    { T-d, pixel for pixel, per task }
    procedure TestBarMimicsPaintLikeTheirFinalClass;
    procedure TestRibbonMimicsPaintLikeTheirFinalClass;
    procedure TestChromeMimicsPaintLikeTheirFinalClass;
    procedure TestImageMimicsPaintLikeTheirFinalClass;
    { Real input, one per family. }
    procedure TestInputThirdToolButtonClicks;
    procedure TestInputThirdScrollBarStepsOnArrowKeys;
    procedure TestInputThirdRibbonGroupLauncher;
  end;

  { --- third-party mimics ------------------------------------------------------------ }

  TThirdToolBar = class(TTyCustomToolBar)
  published
    property ButtonWidth;
    property Flat;
  end;

  TThirdToolButton = class(TTyCustomToolButton)
  published
    property Style;
    property Down;
  end;

  TThirdStatusBar = class(TTyCustomStatusBar)
  published
    property Panels;
    property SimpleText;
  end;

  { Max ahead of Position: the bar clamps Position to Max as it is written (the same order
    rule as TTyCustomTrackBar / TTyCustomProgressBar; see the plan's Task 31 list). }
  TThirdScrollBar = class(TTyCustomScrollBar)
  published
    property Max;
    property Position;
  end;

  TThirdRibbonPage = class(TTyCustomRibbonPage)
  published
    property Caption;
    property Context;
  end;

  TThirdRibbonGroup = class(TTyCustomRibbonGroup)
  published
    property Caption;
    property ShowCaption;
  end;

  { ItemIndex ahead of what it indexes -- the order the library's own classes never use. }
  TIdxRibbonGallery = class(TTyCustomRibbonGallery)
  published
    property ItemIndex;
    property Items;
  end;

  TIdxRibbonBackstage = class(TTyCustomRibbonBackstage)
  published
    property ItemIndex;
    property Commands;
  end;

  TThirdTitleBar = class(TTyCustomTitleBar)
  published
    property Caption;
    property ShowMinimize;
  end;

  TThirdMenuBar = class(TTyCustomMenuBar)
  published
    property Menu;
    property AutoSizeWidth;
  end;

  TThirdFormSurface = class(TTyCustomFormSurface)
  published
    property Purpose;
  end;

  TThirdCharImage = class(TTyCustomCharImage)
  published
    property IconFont;
    property GlyphName;
  end;

  TThirdShape = class(TTyCustomShape)
  published
    property Shape;
    property OnShapeClick;
  end;

  TThirdChart = class(TTyCustomChart)
  published
    property ChartType;
    property Series;
  end;

implementation

type
  TP3ToolBarCracker = class(TTyCustomToolBar)
  public
    procedure ForceLayout;
  end;

  TP3ToolBarExCracker = class(TTyCustomToolBarEx)
  public
    procedure ForceLayout;
  end;

  TP3RibbonPageCracker = class(TTyCustomRibbonPage)
  public
    procedure ForceLayout;
  end;

  TP3RibbonCracker = class(TTyCustomRibbon)
  public
    function TabCount: Integer;
  end;

  { Counts the repaints a status bar asks for: the panel collection's only way to tell its bar
    that a panel changed. }
  TP3CountingStatusBar = class(TTyCustomStatusBar)
  public
    Invalidations: Integer;
    procedure Invalidate; override;
  end;

  TP3ToolBarRender = class(TTyCustomToolBar);
  TP3ToolButtonRender = class(TTyCustomToolButton);
  TP3StatusBarRender = class(TTyCustomStatusBar);
  TP3ScrollBarRender = class(TTyCustomScrollBar);
  TP3RibbonPageRender = class(TTyCustomRibbonPage);
  TP3RibbonGroupRender = class(TTyCustomRibbonGroup);
  TP3TitleBarRender = class(TTyCustomTitleBar);
  TP3CharImageRender = class(TTyCustomCharImage);
  TP3ShapeRender = class(TTyCustomShape);
  TP3ChartRender = class(TTyCustomChart);
procedure TP3ToolBarCracker.ForceLayout;
var r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AlignControls(nil, r);
end;

procedure TP3ToolBarExCracker.ForceLayout;
var r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AlignControls(nil, r);
end;

procedure TP3RibbonPageCracker.ForceLayout;
var r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AlignControls(nil, r);
end;

function TP3RibbonCracker.TabCount: Integer;
begin
  Result := GetTabCount;
end;

procedure TP3CountingStatusBar.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

procedure TTyCustomClassesP3Test.CountChange(Sender: TObject);
begin
  Inc(FChanges);
  FLastSender := Sender;
end;

procedure TTyCustomClassesP3Test.Launcher(Sender: TTyCustomRibbonGroup);
begin
  Inc(FChanges);
  FLastSender := Sender;
end;

procedure TTyCustomClassesP3Test.PaintButton(Sender: TTyCustomToolButton; AState: Integer);
begin
  Inc(FChanges);
  FLastSender := Sender;
end;

procedure TTyCustomClassesP3Test.DrawPanel(AStatusBar: TTyCustomStatusBar; APanel: TTyStatusPanel;
  APainter: TTyPainter; const ARect: TRect);
begin
  Inc(FChanges);
  FLastSender := AStatusBar;
end;

procedure TTyCustomClassesP3Test.TermData(Sender: TObject; const AData: RawByteString);
begin
  FData := FData + AData;
end;

procedure TTyCustomClassesP3Test.TearDown;
var
  i: Integer;
begin
  if FHosts <> nil then
    for i := FHosts.Count - 1 downto 0 do
      TObject(FHosts[i]).Free;
  FreeAndNil(FHosts);
  inherited TearDown;
end;

function TTyCustomClassesP3Test.NewHost: TForm;
begin
  if FHosts = nil then FHosts := TList.Create;
  Result := TForm.CreateNew(nil);
  Result.SetBounds(0, 0, 600, 400);
  FHosts.Add(Result);
end;

function TTyCustomClassesP3Test.HostRoundTrip(ASrc: TComponent): TComponent;
var
  ms: TMemoryStream;
  dst: TForm;
begin
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(ASrc.Owner);
    ms.Position := 0;
    dst := NewHost;
    ms.ReadComponent(dst);
  finally
    ms.Free;
  end;
  Result := dst.FindComponent(ASrc.Name);
  AssertTrue('the round trip brought ' + ASrc.Name + ' back', Result <> nil);
end;

{ ------------------------------------------------------------------ Task 20: bars }

procedure TTyCustomClassesP3Test.TestThirdToolBar;
var
  third, back: TThirdToolBar;
  own: TTyToolBar;
  c: TTyCustomToolBar;
begin
  third := TThirdToolBar.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdToolBar, ['ButtonWidth', 'Flat']);
  third.ButtonWidth := 60;
  third.Flat := False;
  third.List := False;
  CheckStreamText(third, ['ButtonWidth', 'Flat'], 'List');
  back := TThirdToolBar.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: ButtonWidth round-trips', 60, back.ButtonWidth);
  AssertFalse('T-c: Flat round-trips', back.Flat);
  AssertTrue('T-c: the unpublished List stayed at its default', back.List);
  own := TTyToolBar.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdToolBar, ['ButtonWidth', 'Flat']);
  c := third;
  c.Indent := 7;
  AssertEquals('T-v: Indent is public through a TTyCustomToolBar reference', 7, third.Indent);
end;

procedure TTyCustomClassesP3Test.TestThirdToolButton;
var
  third, back: TThirdToolButton;
  own: TTyToolButton;
  c: TTyCustomToolButton;
begin
  third := TThirdToolButton.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdToolButton, ['Style', 'Down']);
  third.Style := tbsCheck;
  third.Down := True;
  third.Grouped := True;
  CheckStreamText(third, ['Style', 'Down'], 'Grouped');
  back := TThirdToolButton.Create(FForm);
  StreamInto(third, back);
  AssertTrue('T-c: Style round-trips', back.Style = tbsCheck);
  AssertTrue('T-c: Down round-trips', back.Down);
  AssertFalse('T-c: the unpublished Grouped stayed at its default', back.Grouped);
  own := TTyToolButton.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  { The key follows the style (a space holder draws the separator's rule), from the custom
    class: a third party's separator resolves the separator's rules too. }
  third.Style := tbsDivider;
  own.Style := tbsDivider;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdToolButton, ['Style', 'Down']);
  AssertFalse('T-e: a tool button is never a tab stop, the mimic neither', third.TabStop);
  c := third;
  c.Wrap := True;
  AssertTrue('T-v: Wrap is public through a TTyCustomToolButton reference', third.Wrap);
end;

{ S20-1 (A20-1). A tool button on a TTyToolBarEx finds its bar: the Ex bar is a
  TTyCustomToolBar but, since 4.0, no TTyToolBar. }
procedure TTyCustomClassesP3Test.TestToolButtonFindsItsToolBarEx;
var
  bar: TP3ToolBarExCracker;
  b: TTyToolButton;
begin
  bar := TP3ToolBarExCracker(TTyToolBarEx.Create(FForm));
  bar.Parent := FForm;
  bar.Align := alNone;
  bar.SetBounds(0, 0, 400, 40);
  AssertFalse('precondition: the Ex bar is no TTyToolBar (or this proves nothing)',
    TObject(bar) is TTyToolBar);
  b := TTyToolButton.Create(FForm);
  b.Parent := bar;
  b.Caption := 'Go';
  AssertTrue('the button finds the Ex bar as its tool bar', b.ToolBar = TTyCustomToolBar(bar));
  AssertEquals('and its place in the bar''s Buttons[]', 0, b.Index);
  { The bar's DropDownWidth reaches the button only through ToolBar. }
  b.Style := tbsDropDown;
  bar.DropDownWidth := 30;
  AssertEquals('the arrow zone comes from the Ex bar''s DropDownWidth', 30,
    TP3ToolButtonRender(b).ArrowZoneWidth(96));
end;

{ S20-2 (C19-2). A third party's tool button on the library's bar is one of its Buttons[],
  gets the bar's width floor, and as a space holder is not dressed in 'ghost'. }
procedure TTyCustomClassesP3Test.TestToolBarTakesAThirdPartyToolButton;
var
  bar: TP3ToolBarCracker;
  ex: TP3ToolBarExCracker;
  third, sep, exSep: TThirdToolButton;
  got: TTyCustomToolButton;
begin
  bar := TP3ToolBarCracker(TTyToolBar.Create(FForm));
  bar.Parent := FForm;
  bar.Align := alNone;
  bar.SetBounds(0, 0, 400, 40);
  AssertTrue('the bar is flat (or the ghost check proves nothing)', bar.Flat);
  bar.ButtonWidth := 90;
  third := TThirdToolButton.Create(FForm);
  third.Parent := bar;
  third.Width := 40;
  sep := TThirdToolButton.Create(FForm);
  sep.Parent := bar;
  sep.Style := tbsSeparator;
  AssertEquals('both are the bar''s buttons', 2, bar.ButtonCount);
  got := bar.Buttons[0];
  AssertTrue('Buttons[] hands out the third party''s button as it is', got = third);
  AssertFalse('which is no TTyToolButton', got is TTyToolButton);
  AssertEquals('IndexOfButton knows it', 1, bar.IndexOfButton(sep));
  AssertEquals('Index answers through the bar', 0, third.Index);
  bar.ForceLayout;
  AssertTrue('the bar floors the button to its ButtonWidth', third.Width >= 90);
  AssertEquals('a third-party separator is not ghosted', '', sep.StyleClass);
  AssertEquals('a third-party push button is', 'ghost', third.StyleClass);
  { The Ex bar keeps its own copy of the space-holder exception. }
  ex := TP3ToolBarExCracker(TTyToolBarEx.Create(FForm));
  ex.Parent := FForm;
  ex.Align := alNone;
  ex.Wrapable := False;
  ex.SetBounds(0, 50, 400, 40);
  exSep := TThirdToolButton.Create(FForm);
  exSep.Parent := ex;
  exSep.Style := tbsDivider;
  ex.ForceLayout;
  AssertEquals('a third-party divider on the Ex bar is not ghosted', '', exSep.StyleClass);
end;

procedure TTyCustomClassesP3Test.TestThirdStatusBar;
var
  third, back: TThirdStatusBar;
  own: TTyStatusBar;
  c: TTyCustomStatusBar;
begin
  third := TThirdStatusBar.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdStatusBar, ['Panels', 'SimpleText']);
  third.Panels.Add.Text := 'Ready';
  third.SimpleText := 'idle';
  third.SizeGrip := False;
  CheckStreamText(third, ['Panels', 'SimpleText'], 'SizeGrip');
  back := TThirdStatusBar.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: the panel round-trips', 1, back.Panels.Count);
  AssertEquals('T-c: with its text', 'Ready', back.Panels[0].Text);
  AssertEquals('T-c: SimpleText round-trips', 'idle', back.SimpleText);
  AssertTrue('T-c: the unpublished SizeGrip stayed at its default', back.SizeGrip);
  own := TTyStatusBar.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdStatusBar, ['Panels', 'SimpleText']);
  c := third;
  c.OnDrawPanel := @DrawPanel;
  c.SimplePanel := True;
  AssertTrue('T-v: SimplePanel and OnDrawPanel are public through a TTyCustomStatusBar '
    + 'reference', third.SimplePanel and Assigned(third.OnDrawPanel));
end;

{ S20-3 (C19-3). The panel collection finds its owner as TTyCustomStatusBar: a panel added to,
  or changed on, a third party's bar repaints that bar. }
procedure TTyCustomClassesP3Test.TestStatusPanelsReachAThirdPartyBar;
var
  bar: TP3CountingStatusBar;
  p: TTyStatusPanel;
begin
  bar := TP3CountingStatusBar.Create(FForm);
  bar.Parent := FForm;
  bar.Invalidations := 0;
  p := bar.Panels.Add;
  AssertTrue('adding a panel repaints the third-party bar', bar.Invalidations > 0);
  bar.Invalidations := 0;
  p.Text := 'changed';
  AssertTrue('and so does changing one', bar.Invalidations > 0);
end;

procedure TTyCustomClassesP3Test.TestThirdScrollBar;
var
  third, back: TThirdScrollBar;
  own: TTyScrollBar;
  c: TTyCustomScrollBar;
begin
  third := TThirdScrollBar.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdScrollBar, ['Max', 'Position']);
  third.Max := 200;
  third.Position := 150;
  third.SmallChange := 5;
  CheckStreamText(third, ['Max', 'Position'], 'SmallChange');
  back := TThirdScrollBar.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Max round-trips', 200, back.Max);
  AssertEquals('T-c: Position round-trips (Max is read first)', 150, back.Position);
  AssertEquals('T-c: the unpublished SmallChange stayed at its default', 1, back.SmallChange);
  own := TTyScrollBar.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdScrollBar, ['Max', 'Position']);
  AssertTrue('T-e: a scroll bar is a tab stop, the mimic too', third.TabStop);
  c := third;
  c.LargeChange := 20;
  AssertEquals('T-v: LargeChange is public through a TTyCustomScrollBar reference', 20,
    third.LargeChange);
end;

{ ------------------------------------------------------------------ Task 21: ribbon }

procedure TTyCustomClassesP3Test.TestThirdRibbonPage;
var
  host: TForm;
  third, back: TThirdRibbonPage;
  own: TTyRibbonPage;
begin
  host := NewHost;
  third := TThirdRibbonPage.Create(host);
  third.Name := 'Pg';
  third.Parent := host;
  CheckPublishesOnly(TThirdRibbonPage, ['Caption', 'Context']);
  third.Caption := 'Home';
  third.Context := 'pic';
  third.Hint := 'h';
  CheckStreamText(third, ['Caption', 'Context'], '');
  back := HostRoundTrip(third) as TThirdRibbonPage;
  AssertEquals('T-c: Caption round-trips', 'Home', back.Caption);
  AssertEquals('T-c: Context round-trips', 'pic', back.Context);
  own := TTyRibbonPage.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdRibbonPage, ['Caption', 'Context']);
end;

procedure TTyCustomClassesP3Test.TestThirdRibbonGroup;
var
  third, back: TThirdRibbonGroup;
  own: TTyRibbonGroup;
  c: TTyCustomRibbonGroup;
begin
  third := TThirdRibbonGroup.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdRibbonGroup, ['Caption', 'ShowCaption']);
  third.Caption := 'Clipboard';
  third.ShowCaption := False;
  third.ShowDialogLauncher := True;
  CheckStreamText(third, ['Caption', 'ShowCaption'], 'ShowDialogLauncher');
  back := TThirdRibbonGroup.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Caption round-trips', 'Clipboard', back.Caption);
  AssertFalse('T-c: ShowCaption round-trips', back.ShowCaption);
  AssertFalse('T-c: the unpublished ShowDialogLauncher stayed at its default',
    back.ShowDialogLauncher);
  own := TTyRibbonGroup.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdRibbonGroup, ['Caption', 'ShowCaption']);
  c := third;
  c.OnDialogLauncher := @Launcher;
  AssertTrue('T-v: OnDialogLauncher is public through a TTyCustomRibbonGroup reference',
    Assigned(third.OnDialogLauncher));
end;

{ S21-1 (C20-1, C20-3). A third party's page joins the library's ribbon: it is registered as a
  page, the ribbon hands it out as it is, a Context change re-lays the strip, and freeing the
  page takes it out of the ribbon. }
procedure TTyCustomClassesP3Test.TestRibbonTakesAThirdPartyPage;
var
  rb: TTyRibbon;
  own: TTyRibbonPage;
  third: TThirdRibbonPage;
  pg: TTyCustomRibbonPage;
begin
  rb := TTyRibbon.Create(FForm);
  rb.Parent := FForm;
  own := rb.AddPage('Home');
  third := TThirdRibbonPage.Create(FForm);
  third.Caption := 'Insert';
  third.Parent := rb;
  AssertEquals('the ribbon registers the third-party page', 2, rb.PageCount);
  pg := rb.Pages[1];
  AssertTrue('Pages[] hands it out as it is', pg = third);
  AssertFalse('and it is no TTyRibbonPage', pg is TTyRibbonPage);
  rb.ActivePage := third;
  AssertTrue('it can be the active page', rb.ActivePage = third);
  AssertEquals('both tabs show', 2, TP3RibbonCracker(rb).TabCount);
  third.Context := 'pictures';
  AssertEquals('a Context of its own hides its tab until the context is shown', 1,
    TP3RibbonCracker(rb).TabCount);
  rb.ShowContext('pictures');
  AssertEquals('and shows it again with the context', 2, TP3RibbonCracker(rb).TabCount);
  third.Free;
  AssertEquals('freeing the page takes it out of the ribbon', 1, rb.PageCount);
  AssertTrue('the library''s own page remains', rb.Pages[0] = own);
end;

{ S21-2 (C20-2). The page lays out a third party's group with its own: the group is captured
  into the page's left-to-right order and placed by the page. }
procedure TTyCustomClassesP3Test.TestRibbonPageLaysOutAThirdPartyGroup;
var
  pg: TP3RibbonPageCracker;
  g: TThirdRibbonGroup;
begin
  pg := TP3RibbonPageCracker(TTyRibbonPage.Create(FForm));
  pg.Parent := FForm;
  pg.SetBounds(0, 0, 500, 90);
  g := TThirdRibbonGroup.Create(FForm);
  g.Parent := pg;
  g.Width := 120;
  AssertTrue('precondition: a group docks left until its page lays it out', g.Align = alLeft);
  pg.ForceLayout;
  AssertTrue('the page took the third-party group into its own layout', g.Align = alNone);
  AssertEquals('at the band''s full height', pg.ClientHeight, g.Height);
  AssertTrue('and shows it', g.Visible);
end;

{ An index a third party publishes ahead of the strings it indexes (the library's own classes
  publish the strings first) waits for Loaded instead of falling off the empty list, and
  lands without telling anyone -- reading a form is not a selection. }
procedure TTyCustomClassesP3Test.TestRibbonIndexesReadBeforeTheirItemsWait;
var
  host: TForm;
  gal, galBack: TIdxRibbonGallery;
  bs, bsBack: TIdxRibbonBackstage;
begin
  host := NewHost;
  gal := TIdxRibbonGallery.Create(host);
  gal.Name := 'Gal';
  gal.Parent := host;
  gal.Items.CommaText := 'a,b,c';
  gal.ItemIndex := 2;
  bs := TIdxRibbonBackstage.Create(host);
  bs.Name := 'Bs';
  bs.Parent := host;
  bs.Commands.CommaText := 'Info,New,Open';
  bs.ItemIndex := 1;
  AssertTrue('precondition: the gallery streams ItemIndex ahead of Items',
    Pos('ItemIndex', StreamedText(gal)) < Pos('Items.Strings', StreamedText(gal)));
  galBack := HostRoundTrip(gal) as TIdxRibbonGallery;
  AssertEquals('the gallery index waits for its items', 2, galBack.ItemIndex);
  bsBack := TIdxRibbonBackstage(galBack.Owner.FindComponent('Bs'));
  AssertEquals('the backstage index waits for its commands', 1, bsBack.ItemIndex);
end;

{ ------------------------------------------------------------------ Task 22: window chrome }

procedure TTyCustomClassesP3Test.TestThirdTitleBar;
var
  third, back: TThirdTitleBar;
  own: TTyTitleBar;
  c: TTyCustomTitleBar;
begin
  third := TThirdTitleBar.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdTitleBar, ['Caption', 'ShowMinimize']);
  third.Caption := 'Editor';
  third.ShowMinimize := False;
  third.ShowClose := False;
  CheckStreamText(third, ['Caption', 'ShowMinimize'], 'ShowClose');
  back := TThirdTitleBar.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Caption round-trips', 'Editor', back.Caption);
  AssertFalse('T-c: ShowMinimize round-trips', back.ShowMinimize);
  AssertTrue('T-c: the unpublished ShowClose stayed at its default', back.ShowClose);
  own := TTyTitleBar.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdTitleBar, ['Caption', 'ShowMinimize']);
  c := third;
  c.ShowMaximize := False;
  AssertFalse('T-v: ShowMaximize is public through a TTyCustomTitleBar reference',
    third.ShowMaximize);
end;

procedure TTyCustomClassesP3Test.TestThirdMenuBar;
var
  host: TForm;
  third, back: TThirdMenuBar;
  own: TTyMenuBar;
  mm: TMainMenu;
begin
  host := NewHost;
  mm := TMainMenu.Create(host);
  mm.Name := 'MM';
  third := TThirdMenuBar.Create(host);
  third.Name := 'MB';
  third.Parent := host;
  CheckPublishesOnly(TThirdMenuBar, ['Menu', 'AutoSizeWidth']);
  third.Menu := mm;
  third.AutoSizeWidth := True;
  back := HostRoundTrip(third) as TThirdMenuBar;
  AssertTrue('T-c: Menu round-trips (by name)', (back.Menu <> nil) and (back.Menu.Name = 'MM'));
  AssertTrue('T-c: AutoSizeWidth round-trips', back.AutoSizeWidth);
  own := TTyMenuBar.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdMenuBar, ['Menu', 'AutoSizeWidth']);
  AssertTrue('T-e: a menu bar is a tab stop, the mimic too', TThirdMenuBar.Create(FForm).TabStop);
end;

{ Purpose is read-only (the designer's caption for the surface): published, never streamed. }
procedure TTyCustomClassesP3Test.TestThirdFormSurface;
var
  third: TThirdFormSurface;
  own: TTyFormSurface;
begin
  third := TThirdFormSurface.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdFormSurface, ['Purpose']);
  AssertTrue('the purpose reads through the mimic', third.Purpose <> '');
  AssertFalse('T-c: a read-only property does not stream', HasProp(StreamedText(third), 'Purpose'));
  own := TTyFormSurface.Create(FForm);
  own.Parent := FForm;
  AssertEquals('the same purpose as the library''s surface', own.Purpose, third.Purpose);
  CheckSameTypeKey(third, own);
end;

{ C11-3 (Form.pas). A TTyForm wires a third party's surface as its content host: the form's
  controller reaches it. }
procedure TTyCustomClassesP3Test.TestFormWiresAThirdPartySurface;
var
  f: TTyForm;
  s: TThirdFormSurface;
  ctl: TTyStyleController;
begin
  f := TTyForm.CreateNew(nil);
  try
    s := TThirdFormSurface.Create(f);
    s.Parent := f;
    ctl := TTyStyleController.Create(f);
    f.Controller := ctl;
    AssertTrue('the form handed its controller to the third-party surface',
      s.Controller = ctl);
  finally
    f.Free;
  end;
end;

{ ------------------------------------------------------------------ Task 23: images and shapes }

procedure TTyCustomClassesP3Test.TestThirdCharImage;
var
  host: TForm;
  third, back: TThirdCharImage;
  own: TTyCharImage;
  fnt: TTyIconFont;
  c: TTyCustomCharImage;
begin
  host := NewHost;
  fnt := TTyIconFont.Create(host);
  fnt.Name := 'Icons';
  third := TThirdCharImage.Create(host);
  third.Name := 'Img';
  third.Parent := host;
  CheckPublishesOnly(TThirdCharImage, ['IconFont', 'GlyphName']);
  third.IconFont := fnt;
  third.GlyphName := 'home';
  third.GlyphSize := 30;
  CheckStreamText(third, ['IconFont', 'GlyphName'], 'GlyphSize');
  back := HostRoundTrip(third) as TThirdCharImage;
  AssertTrue('T-c: IconFont round-trips (by name)',
    (back.IconFont <> nil) and (back.IconFont.Name = 'Icons'));
  AssertEquals('T-c: GlyphName round-trips', 'home', back.GlyphName);
  AssertEquals('T-c: the unpublished GlyphSize stayed at its default', 0, back.GlyphSize);
  own := TTyCharImage.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdCharImage, ['IconFont', 'GlyphName']);
  c := third;
  c.GlyphSize := 12;
  AssertEquals('T-v: GlyphSize is public through a TTyCustomCharImage reference', 12,
    third.GlyphSize);
end;

procedure TTyCustomClassesP3Test.TestThirdShape;
var
  third, back: TThirdShape;
  own: TTyShape;
begin
  third := TThirdShape.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdShape, ['Shape', 'OnShapeClick']);
  third.Shape := tskEllipse;
  CheckStreamText(third, ['Shape'], '');
  back := TThirdShape.Create(FForm);
  StreamInto(third, back);
  AssertTrue('T-c: Shape round-trips', back.Shape = tskEllipse);
  third.OnShapeClick := @CountChange;
  AssertTrue('the published event is the custom class''s', Assigned(third.OnShapeClick));
  own := TTyShape.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdShape, ['Shape', 'OnShapeClick']);
end;

procedure TTyCustomClassesP3Test.TestThirdChart;
var
  third, back: TThirdChart;
  own: TTyChart;
  c: TTyCustomChart;
begin
  third := TThirdChart.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdChart, ['ChartType', 'Series']);
  third.ChartType := ctBar;
  with third.Series.Add do
  begin
    Name := 'Sales';
    Values := '1,2,3';
  end;
  third.ShowLegend := False;
  CheckStreamText(third, ['ChartType', 'Series'], 'ShowLegend');
  back := TThirdChart.Create(FForm);
  StreamInto(third, back);
  AssertTrue('T-c: ChartType round-trips', back.ChartType = ctBar);
  AssertEquals('T-c: the series round-trips', 1, back.Series.Count);
  AssertEquals('T-c: with its values', '1,2,3', back.Series[0].Values);
  AssertTrue('T-c: the unpublished ShowLegend stayed at its default', back.ShowLegend);
  own := TTyChart.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdChart, ['ChartType']);
  c := third;
  c.ShowGrid := False;
  AssertFalse('T-v: ShowGrid is public through a TTyCustomChart reference', third.ShowGrid);
end;

{ ------------------------------------------------------------------ Task 24: pickers, terminal }

{ ------------------------------------------------------------------ Task 25: tool windows }

{ ------------------------------------------------------------------ T-d }

{ One renderer per family: RenderTo is protected, the empty crackers reach it. }
procedure RenderToolBar(C: TControl; ACanvas: TCanvas; const R: TRect);
begin
  TP3ToolBarRender(C).RenderTo(ACanvas, R, 96);
end;

procedure RenderToolButton(C: TControl; ACanvas: TCanvas; const R: TRect);
begin
  TP3ToolButtonRender(C).RenderTo(ACanvas, R, 96);
end;

procedure RenderStatusBar(C: TControl; ACanvas: TCanvas; const R: TRect);
begin
  TP3StatusBarRender(C).RenderTo(ACanvas, R, 96);
end;

procedure RenderScrollBar(C: TControl; ACanvas: TCanvas; const R: TRect);
begin
  TP3ScrollBarRender(C).RenderTo(ACanvas, R, 96);
end;

procedure RenderRibbonPage(C: TControl; ACanvas: TCanvas; const R: TRect);
begin
  TP3RibbonPageRender(C).RenderTo(ACanvas, R, 96);
end;

procedure RenderRibbonGroup(C: TControl; ACanvas: TCanvas; const R: TRect);
begin
  TP3RibbonGroupRender(C).RenderTo(ACanvas, R, 96);
end;

procedure RenderTitleBar(C: TControl; ACanvas: TCanvas; const R: TRect);
begin
  TP3TitleBarRender(C).RenderTo(ACanvas, R, 96);
end;

procedure RenderCharImage(C: TControl; ACanvas: TCanvas; const R: TRect);
begin
  TP3CharImageRender(C).RenderTo(ACanvas, R, 96);
end;

procedure RenderShape(C: TControl; ACanvas: TCanvas; const R: TRect);
begin
  TP3ShapeRender(C).RenderTo(ACanvas, R, 96);
end;

procedure RenderChart(C: TControl; ACanvas: TCanvas; const R: TRect);
begin
  TP3ChartRender(C).RenderTo(ACanvas, R, 96);
end;

{ Each pair is set up the same way -- same size, same values, unfocused -- and must paint the
  same pixels: the drawing, the state it reads and the theme rules it resolves all live in the
  custom class, where the third party gets them. }
procedure TTyCustomClassesP3Test.CheckSamePaint(AThird, AOwn: TControl; AW, AH: Integer;
  ARender: TP3RenderProc);
var
  a, b: TBitmap;
  diff: string;
  x, y, painted: Integer;
begin
  if AThird.Parent = nil then AThird.Parent := FForm;
  if AOwn.Parent = nil then AOwn.Parent := FForm;
  AThird.SetBounds(0, 0, AW, AH);
  AOwn.SetBounds(0, AH + 10, AW, AH);
  a := NewSentinelBitmap(AW, AH);
  b := NewSentinelBitmap(AW, AH);
  try
    ARender(AThird, a.Canvas, Rect(0, 0, AW, AH));
    ARender(AOwn, b.Canvas, Rect(0, 0, AW, AH));
    painted := 0;
    for y := 0 to a.Height - 1 do
      for x := 0 to a.Width - 1 do
        if a.Canvas.Pixels[x, y] <> CSentinel then Inc(painted);
    AssertTrue('T-d: ' + AThird.ClassName + ' painted something (or this proves nothing)',
      painted > 0);
    AssertTrue('T-d: ' + AThird.ClassName + ' paints exactly what ' + AOwn.ClassName
      + ' paints: ' + diff, SameBitmaps(a, b, diff));
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TTyCustomClassesP3Test.TestBarMimicsPaintLikeTheirFinalClass;
var
  tb: TThirdToolBar;
  otb: TTyToolBar;
  bt: TThirdToolButton;
  obt: TTyToolButton;
  sb: TThirdStatusBar;
  osb: TTyStatusBar;
  sc: TThirdScrollBar;
  osc: TTyScrollBar;
begin
  tb := TThirdToolBar.Create(FForm);
  otb := TTyToolBar.Create(FForm);
  tb.Align := alNone;
  otb.Align := alNone;
  CheckSamePaint(tb, otb, 300, 40, @RenderToolBar);

  bt := TThirdToolButton.Create(FForm);
  obt := TTyToolButton.Create(FForm);
  bt.Caption := 'Save';
  obt.Caption := 'Save';
  bt.Style := tbsCheck;
  obt.Style := tbsCheck;
  bt.Down := True;
  obt.Down := True;
  CheckSamePaint(bt, obt, 80, 30, @RenderToolButton);

  sb := TThirdStatusBar.Create(FForm);
  osb := TTyStatusBar.Create(FForm);
  sb.Align := alNone;
  osb.Align := alNone;
  sb.Panels.Add.Text := 'Ready';
  osb.Panels.Add.Text := 'Ready';
  CheckSamePaint(sb, osb, 300, 24, @RenderStatusBar);

  sc := TThirdScrollBar.Create(FForm);
  osc := TTyScrollBar.Create(FForm);
  sc.Position := 30;
  osc.Position := 30;
  CheckSamePaint(sc, osc, 200, 17, @RenderScrollBar);
end;

procedure TTyCustomClassesP3Test.TestRibbonMimicsPaintLikeTheirFinalClass;
var
  rp: TThirdRibbonPage;
  orp: TTyRibbonPage;
  rg: TThirdRibbonGroup;
  org: TTyRibbonGroup;
begin
  rp := TThirdRibbonPage.Create(FForm);
  orp := TTyRibbonPage.Create(FForm);
  CheckSamePaint(rp, orp, 300, 90, @RenderRibbonPage);

  rg := TThirdRibbonGroup.Create(FForm);
  org := TTyRibbonGroup.Create(FForm);
  rg.Align := alNone;
  org.Align := alNone;
  rg.Caption := 'Font';
  org.Caption := 'Font';
  CheckSamePaint(rg, org, 140, 90, @RenderRibbonGroup);
end;

procedure TTyCustomClassesP3Test.TestChromeMimicsPaintLikeTheirFinalClass;
var
  tt: TThirdTitleBar;
  ott: TTyTitleBar;
begin
  tt := TThirdTitleBar.Create(FForm);
  ott := TTyTitleBar.Create(FForm);
  tt.Align := alNone;
  ott.Align := alNone;
  tt.Caption := 'Editor';
  ott.Caption := 'Editor';
  CheckSamePaint(tt, ott, 300, 32, @RenderTitleBar);
end;

procedure TTyCustomClassesP3Test.TestImageMimicsPaintLikeTheirFinalClass;
var
  ci: TThirdCharImage;
  oci: TTyCharImage;
  sh: TThirdShape;
  osh: TTyShape;
  ch: TThirdChart;
  och: TTyChart;
begin
  ci := TThirdCharImage.Create(FForm);
  oci := TTyCharImage.Create(FForm);
  ci.Color := clYellow;
  oci.Color := clYellow;
  CheckSamePaint(ci, oci, 40, 40, @RenderCharImage);

  sh := TThirdShape.Create(FForm);
  osh := TTyShape.Create(FForm);
  sh.Shape := tskEllipse;
  osh.Shape := tskEllipse;
  CheckSamePaint(sh, osh, 60, 40, @RenderShape);

  ch := TThirdChart.Create(FForm);
  och := TTyChart.Create(FForm);
  ch.Series.Add.Values := '1,3,2';
  och.Series.Add.Values := '1,3,2';
  CheckSamePaint(ch, och, 200, 120, @RenderChart);
end;

{ ------------------------------------------------------------------ real input }

procedure PressAndRelease(C: TControl; X, Y: Integer);
begin
  C.Perform(LM_LBUTTONDOWN, MK_LBUTTON, MousePos(X, Y));
  C.Perform(LM_LBUTTONUP, 0, MousePos(X, Y));
end;

procedure TTyCustomClassesP3Test.TestInputThirdToolButtonClicks;
var
  bar: TTyToolBar;
  third: TThirdToolButton;
  own: TTyToolButton;
  a: Integer;
begin
  NeedWidgetSet;
  bar := TTyToolBar.Create(FForm);
  bar.Parent := FForm;
  bar.HandleNeeded;
  third := TThirdToolButton.Create(FForm);
  third.Parent := bar;
  third.Style := tbsCheck;
  third.SetBounds(0, 0, 60, 28);
  third.HandleNeeded;
  own := TTyToolButton.Create(FForm);
  own.Parent := bar;
  own.Style := tbsCheck;
  own.SetBounds(70, 0, 60, 28);
  own.HandleNeeded;
  third.OnClick := @CountChange;
  own.OnClick := @CountChange;
  FChanges := 0;
  PressAndRelease(third, 10, 10);
  a := FChanges;
  FChanges := 0;
  PressAndRelease(own, 10, 10);
  AssertEquals('the mimic clicks once on press + release', 1, a);
  AssertEquals('as TTyToolButton does', FChanges, a);
  AssertTrue('a check-style click presses the mimic', third.Down);
  AssertEquals('as it presses TTyToolButton', own.Down, third.Down);
end;

procedure TTyCustomClassesP3Test.TestInputThirdScrollBarStepsOnArrowKeys;
var
  third: TThirdScrollBar;
  own: TTyScrollBar;
begin
  NeedWidgetSet;
  third := TThirdScrollBar.Create(FForm);
  third.Parent := FForm;
  third.HandleNeeded;
  own := TTyScrollBar.Create(FForm);
  own.Parent := FForm;
  own.HandleNeeded;
  third.Position := 10;
  own.Position := 10;
  third.Perform(CN_KEYDOWN, VK_RIGHT, 0);
  own.Perform(CN_KEYDOWN, VK_RIGHT, 0);
  AssertTrue('Right moves the mimic', third.Position > 10);
  AssertEquals('as it moves TTyScrollBar', own.Position, third.Position);
  third.Perform(CN_KEYDOWN, VK_END, 0);
  own.Perform(CN_KEYDOWN, VK_END, 0);
  AssertEquals('End as on TTyScrollBar', own.Position, third.Position);
end;

procedure TTyCustomClassesP3Test.TestInputThirdRibbonGroupLauncher;
var
  third: TThirdRibbonGroup;
  own: TTyRibbonGroup;
  a: Integer;
begin
  NeedWidgetSet;
  third := TThirdRibbonGroup.Create(FForm);
  third.Parent := FForm;
  third.Align := alNone;
  third.SetBounds(0, 0, 140, 90);
  third.ShowDialogLauncher := True;
  third.HandleNeeded;
  own := TTyRibbonGroup.Create(FForm);
  own.Parent := FForm;
  own.Align := alNone;
  own.SetBounds(150, 0, 140, 90);
  own.ShowDialogLauncher := True;
  own.HandleNeeded;
  third.OnDialogLauncher := @Launcher;
  own.OnDialogLauncher := @Launcher;
  FChanges := 0;
  FLastSender := nil;
  PressAndRelease(third, 135, 85);
  a := FChanges;
  AssertTrue('the launcher reports the third-party group itself', FLastSender = third);
  FChanges := 0;
  PressAndRelease(own, 135, 85);
  AssertEquals('a click on the mimic''s launcher fires it once', 1, a);
  AssertEquals('as on TTyRibbonGroup', FChanges, a);
end;

initialization
  RegisterClasses([TThirdToolBar, TThirdToolButton, TThirdStatusBar, TThirdScrollBar,
    TThirdRibbonPage, TThirdRibbonGroup, TIdxRibbonGallery, TIdxRibbonBackstage, TThirdTitleBar,
    TThirdMenuBar, TThirdFormSurface, TThirdCharImage, TThirdShape, TThirdChart]);
  RegisterTest(TTyCustomClassesP3Test);
end.
