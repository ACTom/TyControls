unit test.imageink.hosts;
{$mode objfpc}{$H+}

{ The controls that hand the image helpers an ink (the rule itself is in test.imageink).

  Every control that draws an image-list item beside text draws an icon-font glyph of a
  TTyVirtualImageList in that text's colour, for the state the row is in. Each test paints the
  real control -- through its own paint, not a helper called on its behalf -- with a theme
  whose text colour is one no default produces, and looks for the glyph in that colour:

    * two inks, two outcomes: the glyph is the first ink, then the second, and never black;
    * a GlyphColor that names a colour wins over both;
    * the image from the collection beside it keeps its own colour throughout.

  The glyph is U+2588, a full block, and the rows carry no text, so a solid square of the
  ink can only be the glyph: text and rules never make one. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, ImgList, Menus, DB, BufDataset,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.IconFont,
  tyControls.ImageCollection, tyControls.ImageDraw, tyControls.Columns,
  tyControls.TreeView, tyControls.ListView, tyControls.ListView.Layout, tyControls.ListBox, tyControls.AdvancedListBox,
  tyControls.AdvancedComboBox, tyControls.ComboBoxEx, tyControls.Grid,
  tyControls.ListGroupPanel, tyControls.Menu, tyControls.TabStrip, tyControls.TabSet,
  tyControls.ValueListEditor, tyControls.Image, tyControls.DB.Navigator,
  test.devicescale.support;

type
  TInkRender = function: TBGRABitmap of object;

  TImageInkHostsTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FColl: TTyImageCollection;
    FFont: TTyIconFont;
    FList: TTyVirtualImageList;
    FControl: TControl;      { what Paint renders }
    FGhost: Boolean;         { what the tree's OnGetImageIndex answers }
    FTabImage: Integer;
    function Paint: TBGRABitmap;
    { True when ABmp holds a solid CBlock x CBlock square of AColor; APt is its corner. }
    function FindBlock(ABmp: TBGRABitmap; AColor: TTyColor; out APt: TPoint): Boolean;
    function HasBlock(ABmp: TBGRABitmap; AColor: TTyColor): Boolean;
    { The theme: ARule with its %s filled by a colour. }
    procedure Theme(const ARule: string; AColor: TTyColor);
    { The whole rule for a host: ARule is the theme rule that sets its text colour. }
    procedure CheckFollowsTheInk(const AHost, ARule: string; AHasImage: Boolean = True);
    { One state: the glyph painted now is exactly AColor. }
    procedure CheckGlyphIs(const AWhat: string; AColor: TTyColor);
    function Place(AControl: TControl; AW, AH: Integer): TControl;
    function NewTree: TTyTreeView;
    function NewListView(AStyle: TTyListViewStyle): TTyListView;
    function NewRichList: TTyAdvancedListBox;
    function NewMenu(AOnTheLclMenu: Boolean; AEnabled: Boolean = True): TTyMenuView;
    function NewTreeHeader: TTyTreeView;
    function NewListGroup(AGlyphOnTheHeader, ACollapsed: Boolean): TTyListGroupPanel;
    procedure CheckTreeSelectedRow(ATree: TTyTreeView);
    procedure TreeImage(Sender: TTyCustomTreeView; Node: PTyTreeNode; Kind: TTyVTImageKind;
      Column: Integer; var Ghosted: Boolean; var ImageIndex: Integer);
    procedure TabImage(Sender: TObject; AIndex: Integer; var AImageIndex: Integer);
    procedure ImageCells(Sender: TObject; ACol, ARow: Integer; var ADisplay: TTyGridCellDisplay);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { tree view }
    procedure TestTreeNodes;
    procedure TestTreeNodesInAColumnTree;
    procedure TestTreeHeader;
    procedure TestTreeHeaderRightToLeft;
    procedure TestTreeSelectedRowTakesTheSelectionsInkOnlyWhereTheRowIsTheSelections;
    procedure TestColumnTreeSelectedRowLikewise;
    procedure TestTreeDisabledIsTheDisabledInkOnce;
    procedure TestTreeGhostedNodeFadesTheGlyphToo;
    procedure TestTreeDoesNotGoBackToTheFontEveryFrame;
    { list view }
    procedure TestListViewReport;
    procedure TestListViewIcon;
    procedure TestListViewTile;
    procedure TestListViewSmallIcon;
    procedure TestListViewHeader;
    procedure TestListViewSelectedAndDisabledItems;
    procedure TestListViewCutItemFadesTheGlyphToo;
    { the rich row }
    procedure TestRichRow;
    procedure TestRichRowRightToLeft;
    procedure TestRichRowSelected;
    procedure TestRichComboField;
    { the rest }
    procedure TestComboBoxExField;
    procedure TestComboBoxExOverlay;
    procedure TestGridHeader;
    procedure TestGridImageCell;
    procedure TestListGroupItem;
    procedure TestListGroupHeader;
    procedure TestListGroupItemCollapsed;
    procedure TestListGroupHeaderCollapsed;
    procedure TestMenu;
    procedure TestMenuOnTheLclMenusOwnList;
    procedure TestMenuDisabledItemIsTheDisabledInkOnce;
    procedure TestTabStrip;
    procedure TestValueListEditor;
    procedure TestNavigator;
    procedure TestNavigatorDisabledButtonIsTheDisabledInkOnce;
    procedure TestImageControl;
  end;

implementation

type
  TControlAccess = class(TControl);

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

const
  CBlock = 5;
  { Colours no default produces. }
  InkA: TTyColor     = $FFD2283C;
  InkB: TTyColor     = $FF1EAA5A;
  InkSel: TTyColor   = $FF0A7CC8;
  InkDis: TTyColor   = $FF8C6E14;
  Explicit: TTyColor = $FF963CC8;
  Photo: TTyColor    = $FF145AE6;
  Black: TTyColor    = $FF000000;
  GLYPH = 0;    { 'block', from the font }
  IMAGE = 1;    { 'photo', from the collection }

var
  ResolverHits: Integer = 0;

function CountingResolver(const AFamily, AName: string; out ACodepoint: Cardinal): Boolean;
begin
  ACodepoint := 0;
  Result := (AName <> '') and (AName[1] = 'c');
  if Result then
  begin
    Inc(ResolverHits);
    ACodepoint := $2588;
  end;
end;

function Css(AColor: TTyColor): string;
begin
  Result := Format('#%.2x%.2x%.2x', [TyRedOf(AColor), TyGreenOf(AColor), TyBlueOf(AColor)]);
end;

procedure TImageInkHostsTest.SetUp;
var
  bmp: TBGRABitmap;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FCtl := TTyStyleController.Create(nil);
  FColl := TTyImageCollection.Create(nil);
  bmp := TBGRABitmap.Create(32, 32, TyColorToBGRA(Photo));
  try
    FColl.AddBitmap('photo', bmp);
  finally
    bmp.Free;
  end;
  FFont := TTyIconFont.Create(nil);
  FFont.FontFamily := 'Arial';
  FFont.MapGlyph('block', $2588);
  FList := TTyVirtualImageList.Create(nil);
  FList.Collection := FColl;
  FList.IconFont := FFont;
  FList.Names.Text := 'block' + LineEnding + 'photo';
  FControl := nil;
  FGhost := False;
  FTabImage := GLYPH;
end;

procedure TImageInkHostsTest.TearDown;
begin
  FForm.Free;    { and the controls on it }
  FList.Free;
  FFont.Free;
  FColl.Free;
  FCtl.Free;
end;

function TImageInkHostsTest.Paint: TBGRABitmap;
begin
  Result := TyPaintOwnSurface(FControl, 1);
end;

function TImageInkHostsTest.FindBlock(ABmp: TBGRABitmap; AColor: TTyColor;
  out APt: TPoint): Boolean;
var
  x, y, dx, dy: Integer;
  px: TBGRAPixel;
  r, g, b: Byte;
  solid: Boolean;
begin
  r := TyRedOf(AColor);
  g := TyGreenOf(AColor);
  b := TyBlueOf(AColor);
  APt := Point(-1, -1);
  for y := 0 to ABmp.Height - CBlock do
    for x := 0 to ABmp.Width - CBlock do
    begin
      solid := True;
      for dy := 0 to CBlock - 1 do
      begin
        for dx := 0 to CBlock - 1 do
        begin
          px := ABmp.GetPixel(x + dx, y + dy);
          if (px.red <> r) or (px.green <> g) or (px.blue <> b) then
          begin
            solid := False;
            Break;
          end;
        end;
        if not solid then Break;
      end;
      if solid then
      begin
        APt := Point(x, y);
        Exit(True);
      end;
    end;
  Result := False;
end;

function TImageInkHostsTest.HasBlock(ABmp: TBGRABitmap; AColor: TTyColor): Boolean;
var
  pt: TPoint;
begin
  Result := FindBlock(ABmp, AColor, pt);
end;

procedure TImageInkHostsTest.Theme(const ARule: string; AColor: TTyColor);
begin
  FCtl.StyleOverride := Format(ARule, [Css(AColor)]);
end;

procedure TImageInkHostsTest.CheckFollowsTheInk(const AHost, ARule: string; AHasImage: Boolean);
var
  bmp: TBGRABitmap;
begin
  Theme(ARule, InkA);
  bmp := Paint;
  try
    AssertTrue(AHost + ': the glyph is drawn in the text colour', HasBlock(bmp, InkA));
    AssertFalse(AHost + ': and not in black', HasBlock(bmp, Black));
    if AHasImage then
      AssertTrue(AHost + ': the collection image keeps its colours', HasBlock(bmp, Photo));
  finally
    bmp.Free;
  end;

  Theme(ARule, InkB);
  bmp := Paint;
  try
    AssertTrue(AHost + ': another text colour, another glyph colour', HasBlock(bmp, InkB));
    AssertFalse(AHost + ': and nothing left in the first', HasBlock(bmp, InkA));
    if AHasImage then
      AssertTrue(AHost + ': the collection image still keeps its colours', HasBlock(bmp, Photo));
  finally
    bmp.Free;
  end;

  FList.GlyphColor := Explicit;
  try
    bmp := Paint;
    try
      AssertTrue(AHost + ': a GlyphColor that names a colour is that colour',
        HasBlock(bmp, Explicit));
      AssertFalse(AHost + ': whatever the text colour is', HasBlock(bmp, InkB));
    finally
      bmp.Free;
    end;
  finally
    FList.GlyphColor := TyGlyphColorDefault;
  end;
end;

procedure TImageInkHostsTest.CheckGlyphIs(const AWhat: string; AColor: TTyColor);
var
  bmp: TBGRABitmap;
begin
  bmp := Paint;
  try
    AssertTrue(AWhat, HasBlock(bmp, AColor));
  finally
    bmp.Free;
  end;
end;

function TImageInkHostsTest.Place(AControl: TControl; AW, AH: Integer): TControl;
begin
  AControl.Parent := FForm;
  TControlAccess(AControl).Font.PixelsPerInch := 96;
  AControl.SetBounds(0, 0, AW, AH);
  FControl := AControl;
  Result := AControl;
end;

{ ---- tree view ---------------------------------------------------------------------------- }

procedure TImageInkHostsTest.TreeImage(Sender: TTyCustomTreeView; Node: PTyTreeNode;
  Kind: TTyVTImageKind; Column: Integer; var Ghosted: Boolean; var ImageIndex: Integer);
begin
  if Kind = ikNormal then Ghosted := FGhost;
end;

function TImageInkHostsTest.NewTree: TTyTreeView;
begin
  Result := TTyTreeView.Create(FForm);
  Result.Controller := FCtl;
  Place(Result, 240, 120);
  Result.Images := FList;
  Result.ShowRoot := False;
  Result.ShowTreeLines := False;
  Result.HideSelection := False;
  Result.Items.AddChild(nil, '').ImageIndex := GLYPH;
  Result.Items.AddChild(nil, '').ImageIndex := IMAGE;
end;

procedure TImageInkHostsTest.TestTreeNodes;
begin
  NewTree;
  CheckFollowsTheInk('tree', 'TyTreeNode { color: %s; }');
end;

procedure TImageInkHostsTest.TestTreeNodesInAColumnTree;
var
  t: TTyTreeView;
begin
  t := NewTree;
  (t.Header.Columns.Add as TTyColumn).Width := 120;
  (t.Header.Columns.Add as TTyColumn).Width := 80;
  t.Header.MainColumn := 0;
  CheckFollowsTheInk('tree with columns', 'TyTreeNode { color: %s; }');
end;

function TImageInkHostsTest.NewTreeHeader: TTyTreeView;
var
  c: TTyColumn;
begin
  Result := TTyTreeView.Create(FForm);
  Result.Controller := FCtl;
  Place(Result, 240, 120);
  Result.Header.Images := FList;
  Result.Header.Options := Result.Header.Options + [hoVisible];
  c := Result.Header.Columns.Add as TTyColumn;
  c.Width := 100;
  c.ImageIndex := GLYPH;
  c := Result.Header.Columns.Add as TTyColumn;
  c.Width := 100;
  c.ImageIndex := IMAGE;
end;

procedure TImageInkHostsTest.TestTreeHeader;
begin
  NewTreeHeader;
  CheckFollowsTheInk('tree header', 'TyTreeHeaderSection { color: %s; }');
end;

procedure TImageInkHostsTest.TestTreeHeaderRightToLeft;
begin
  NewTreeHeader.BiDiMode := bdRightToLeft;
  CheckFollowsTheInk('tree header, right to left', 'TyTreeHeaderSection { color: %s; }');
end;

procedure TImageInkHostsTest.CheckTreeSelectedRow(ATree: TTyTreeView);
begin
  FCtl.StyleOverride := Format('TyTreeNode { color: %s; } TyTreeNode:selected { color: %s; }',
    [Css(InkA), Css(InkSel)]);
  ATree.Selected := ATree.GetFirst;
  { The highlight is the caption's: the icon stands on the plain row. }
  CheckGlyphIs('without full-row select the icon keeps the plain row''s ink', InkA);
  ATree.Options := ATree.Options + [toFullRowSelect];
  CheckGlyphIs('with it the icon stands on the selection and takes its ink', InkSel);
  ATree.Selected := nil;
  CheckGlyphIs('and gives it back when the row is no longer selected', InkA);
end;

procedure TImageInkHostsTest.TestTreeSelectedRowTakesTheSelectionsInkOnlyWhereTheRowIsTheSelections;
begin
  CheckTreeSelectedRow(NewTree);
end;

procedure TImageInkHostsTest.TestColumnTreeSelectedRowLikewise;
var
  t: TTyTreeView;
begin
  t := NewTree;
  (t.Header.Columns.Add as TTyColumn).Width := 120;
  (t.Header.Columns.Add as TTyColumn).Width := 80;
  t.Header.MainColumn := 0;
  CheckTreeSelectedRow(t);
end;

procedure TImageInkHostsTest.TestTreeDisabledIsTheDisabledInkOnce;
var
  t: TTyTreeView;
  bmp: TBGRABitmap;
begin
  t := NewTree;
  FCtl.StyleOverride := Format('TyTreeView:disabled { opacity: 1; } ' +
    'TyTreeNode { color: %s; } TyTreeNode:disabled { color: %s; }', [Css(InkA), Css(InkDis)]);
  CheckGlyphIs('enabled: the row''s ink', InkA);
  t.Enabled := False;
  bmp := Paint;
  try
    { Exactly the disabled ink: dimmed a second time it would be a paler colour. }
    AssertTrue('disabled: the disabled ink, at full strength', HasBlock(bmp, InkDis));
    AssertFalse('and not the enabled one', HasBlock(bmp, InkA));
  finally
    bmp.Free;
  end;
end;

procedure TImageInkHostsTest.TestTreeGhostedNodeFadesTheGlyphToo;
var
  t: TTyTreeView;
  bmp: TBGRABitmap;
  at: TPoint;
  px: TBGRAPixel;
begin
  t := NewTree;
  t.OnGetImageIndex := @TreeImage;
  Theme('TyTreeNode { color: %s; }', InkA);
  bmp := Paint;
  try
    AssertTrue('setup: the glyph in the ink', FindBlock(bmp, InkA, at));
    AssertTrue('setup: the image in its colour', HasBlock(bmp, Photo));
  finally
    bmp.Free;
  end;
  FGhost := True;
  bmp := Paint;
  try
    AssertFalse('a ghosted node''s glyph is not at full strength', HasBlock(bmp, InkA));
    AssertFalse('nor is the image', HasBlock(bmp, Photo));
    { It is still the ink, faded towards the white under it -- not the black of a glyph
      nobody handed an ink. }
    px := bmp.GetPixel(at.X + CBlock div 2, at.Y + CBlock div 2);
    AssertTrue(Format('the faded glyph is still red-ish (%d,%d,%d)', [px.red, px.green, px.blue]),
      (px.red > px.green + 20) and (px.red > px.blue + 20));
    AssertTrue('and paler than the ink', px.green > TyGreenOf(InkA) + 40);
  finally
    bmp.Free;
  end;
end;

procedure TImageInkHostsTest.TestTreeDoesNotGoBackToTheFontEveryFrame;
var
  t: TTyTreeView;
  list: TTyVirtualImageList;
  i, firstFrame: Integer;
begin
  { Six rows over two glyphs, one row selected: three (glyph, ink) pairs a frame. With one
    cached glyph every row whose glyph or ink differs from the row before re-rendered it. }
  TyRegisterGlyphResolver(@CountingResolver);
  list := TTyVirtualImageList.Create(nil);
  try
    list.IconFont := FFont;
    list.Names.Text := 'c1' + LineEnding + 'c2';
    t := TTyTreeView.Create(FForm);
    t.Controller := FCtl;
    Place(t, 240, 200);
    t.Images := list;
    t.ShowRoot := False;
    t.HideSelection := False;
    t.Options := t.Options + [toFullRowSelect];
    for i := 0 to 5 do
      t.Items.AddChild(nil, '').ImageIndex := i mod 2;
    t.Selected := t.GetFirst;
    FCtl.StyleOverride := Format('TyTreeNode { color: %s; } TyTreeNode:selected { color: %s; }',
      [Css(InkA), Css(InkSel)]);
    ResolverHits := 0;
    Paint.Free;
    firstFrame := ResolverHits;
    ResolverHits := 0;
    Paint.Free;
    { A row asks the font once which source has its name; a render asks again. }
    AssertEquals('the second frame: six lookups and no render', 6, ResolverHits);
    AssertEquals('the first frame rendered the three pairs once each', 6 + 3, firstFrame);
    t.Images := nil;
  finally
    list.Free;
    TyUnregisterGlyphResolver(@CountingResolver);
  end;
end;

{ ---- list view ---------------------------------------------------------------------------- }

function TImageInkHostsTest.NewListView(AStyle: TTyListViewStyle): TTyListView;
begin
  Result := TTyListView.Create(FForm);
  Result.Controller := FCtl;
  Place(Result, 300, 200);
  Result.ViewStyle := AStyle;
  Result.SmallImages := FList;
  Result.LargeImages := FList;
  if AStyle = lvsReport then
    (Result.Header.Columns.Add as TTyColumn).Width := 200;
  Result.Items.Add.ImageIndex := GLYPH;
  Result.Items.Add.ImageIndex := IMAGE;
end;

procedure TImageInkHostsTest.TestListViewReport;
begin
  NewListView(lvsReport);
  CheckFollowsTheInk('list view, report', 'TyListViewItem { color: %s; }');
end;

procedure TImageInkHostsTest.TestListViewIcon;
begin
  NewListView(lvsIcon);
  CheckFollowsTheInk('list view, icons', 'TyListViewItem { color: %s; }');
end;

procedure TImageInkHostsTest.TestListViewTile;
begin
  NewListView(lvsTile);
  CheckFollowsTheInk('list view, tiles', 'TyListViewItem { color: %s; }');
end;

procedure TImageInkHostsTest.TestListViewSmallIcon;
begin
  NewListView(lvsSmallIcon);
  CheckFollowsTheInk('list view, small icons', 'TyListViewItem { color: %s; }');
end;

procedure TImageInkHostsTest.TestListViewHeader;
var
  lv: TTyListView;
  c: TTyColumn;
begin
  lv := TTyListView.Create(FForm);
  lv.Controller := FCtl;
  Place(lv, 300, 120);
  lv.ViewStyle := lvsReport;
  lv.SmallImages := FList;
  c := lv.Header.Columns.Add as TTyColumn;
  c.Width := 100;
  c.ImageIndex := GLYPH;
  c := lv.Header.Columns.Add as TTyColumn;
  c.Width := 100;
  c.ImageIndex := IMAGE;
  CheckFollowsTheInk('list view header', 'TyListViewHeaderSection { color: %s; }');
end;

procedure TImageInkHostsTest.TestListViewSelectedAndDisabledItems;
var
  lv: TTyListView;
  bmp: TBGRABitmap;
begin
  lv := NewListView(lvsReport);
  FCtl.StyleOverride := Format('TyListViewItem { color: %s; } ' +
    'TyListViewItem:selected { color: %s; } TyListViewItem:disabled { color: %s; }',
    [Css(InkA), Css(InkSel), Css(InkDis)]);
  CheckGlyphIs('at rest: the item''s ink', InkA);
  lv.ItemIndex := 0;
  CheckGlyphIs('selected: the selection''s ink', InkSel);
  lv.ItemIndex := -1;
  lv.Items[0].States := [lisDisabled];
  bmp := Paint;
  try
    AssertTrue('a disabled item: the disabled ink, at full strength', HasBlock(bmp, InkDis));
    AssertFalse('and not the enabled one', HasBlock(bmp, InkA));
  finally
    bmp.Free;
  end;
end;

procedure TImageInkHostsTest.TestListViewCutItemFadesTheGlyphToo;
var
  lv: TTyListView;
  bmp: TBGRABitmap;
  at: TPoint;
  px: TBGRAPixel;
begin
  lv := NewListView(lvsReport);
  Theme('TyListViewItem { color: %s; }', InkA);
  bmp := Paint;
  try
    AssertTrue('setup: the glyph in the ink', FindBlock(bmp, InkA, at));
  finally
    bmp.Free;
  end;
  lv.Items[0].States := [lisCut];
  lv.Items[1].States := [lisCut];
  bmp := Paint;
  try
    AssertFalse('a cut item''s glyph is not at full strength', HasBlock(bmp, InkA));
    AssertFalse('nor is its image', HasBlock(bmp, Photo));
    px := bmp.GetPixel(at.X + CBlock div 2, at.Y + CBlock div 2);
    AssertTrue(Format('the faded glyph is still red-ish (%d,%d,%d)', [px.red, px.green, px.blue]),
      (px.red > px.green + 20) and (px.red > px.blue + 20));
    AssertTrue('and paler than the ink', px.green > TyGreenOf(InkA) + 40);
  finally
    bmp.Free;
  end;
end;

{ ---- the rich row ------------------------------------------------------------------------- }

function TImageInkHostsTest.NewRichList: TTyAdvancedListBox;
begin
  Result := TTyAdvancedListBox.Create(FForm);
  Result.Controller := FCtl;
  Place(Result, 240, 160);
  Result.Images := FList;
  Result.AddItem('', '', GLYPH);
  Result.AddItem('', '', IMAGE);
end;

procedure TImageInkHostsTest.TestRichRow;
begin
  NewRichList;
  CheckFollowsTheInk('rich list', 'TyListItem { color: %s; }');
end;

procedure TImageInkHostsTest.TestRichRowRightToLeft;
begin
  NewRichList.BiDiMode := bdRightToLeft;
  CheckFollowsTheInk('rich list, right to left', 'TyListItem { color: %s; }');
end;

procedure TImageInkHostsTest.TestRichRowSelected;
var
  lb: TTyAdvancedListBox;
begin
  lb := NewRichList;
  FCtl.StyleOverride := Format('TyListItem { color: %s; } TyListItem:active { color: %s; }',
    [Css(InkA), Css(InkSel)]);
  CheckGlyphIs('at rest: the row''s ink', InkA);
  lb.ItemIndex := 0;
  CheckGlyphIs('selected: the selected row''s ink', InkSel);
end;

procedure TImageInkHostsTest.TestRichComboField;
var
  cb: TTyAdvancedComboBox;
begin
  cb := TTyAdvancedComboBox.Create(FForm);
  cb.Controller := FCtl;
  Place(cb, 200, 40);
  cb.Images := FList;
  cb.AddItem('', '', GLYPH);
  cb.ItemIndex := 0;
  CheckFollowsTheInk('rich combo field', 'TyComboBox { color: %s; }', False);
end;

{ ---- the rest ----------------------------------------------------------------------------- }

procedure TImageInkHostsTest.TestComboBoxExField;
var
  cb: TTyComboBoxEx;
begin
  cb := TTyComboBoxEx.Create(FForm);
  cb.Controller := FCtl;
  Place(cb, 200, 40);
  cb.Images := FList;
  cb.ItemsEx.AddItem('', GLYPH);
  cb.ItemIndex := 0;
  CheckFollowsTheInk('image combo field', 'TyComboBox { color: %s; }', False);
end;

procedure TImageInkHostsTest.TestComboBoxExOverlay;
var
  cb: TTyComboBoxEx;
begin
  { the overlay, stamped on a row image that carries its own colours }
  cb := TTyComboBoxEx.Create(FForm);
  cb.Controller := FCtl;
  Place(cb, 200, 40);
  cb.Images := FList;
  cb.ItemsEx.AddItem('', IMAGE).OverlayImageIndex := GLYPH;
  cb.ItemIndex := 0;
  CheckFollowsTheInk('image combo overlay', 'TyComboBox { color: %s; }', False);
end;

procedure TImageInkHostsTest.ImageCells(Sender: TObject; ACol, ARow: Integer;
  var ADisplay: TTyGridCellDisplay);
begin
  ADisplay := gcdImage;
end;

procedure TImageInkHostsTest.TestGridHeader;
var
  g: TTyStringGrid;
  c: TTyColumn;
begin
  g := TTyStringGrid.Create(FForm);
  g.Controller := FCtl;
  Place(g, 300, 120);
  g.Images := FList;
  g.Header.Options := g.Header.Options + [hoVisible];
  c := g.Header.Columns.Add as TTyColumn;
  c.Width := 100;
  c.ImageIndex := GLYPH;
  c := g.Header.Columns.Add as TTyColumn;
  c.Width := 100;
  c.ImageIndex := IMAGE;
  g.RowCount := 0;
  CheckFollowsTheInk('grid header', 'TyGridHeaderSection { color: %s; }');
end;

procedure TImageInkHostsTest.TestGridImageCell;
var
  g: TTyStringGrid;
  bmp: TBGRABitmap;
begin
  g := TTyStringGrid.Create(FForm);
  g.Controller := FCtl;
  Place(g, 300, 120);
  g.Images := FList;
  (g.Header.Columns.Add as TTyColumn).Width := 100;
  (g.Header.Columns.Add as TTyColumn).Width := 100;
  g.RowCount := 2;
  g.OnGetCellDisplay := @ImageCells;
  g.Cells[0, 1] := IntToStr(IMAGE);
  g.Cells[1, 1] := IntToStr(GLYPH);
  CheckFollowsTheInk('grid image cell', 'TyGridCell { color: %s; }');
  { the glyph's row selected, the cursor on the cell beside it: the selection's ink }
  FCtl.StyleOverride := Format('TyGridCell { color: %s; } ' +
    'TyGridCell:selected { color: %s; background: #404040; }', [Css(InkA), Css(InkSel)]);
  g.SelectionMode := gsmRow;
  g.Row := 1;
  bmp := Paint;
  try
    AssertTrue('a selected cell: the selection''s ink', HasBlock(bmp, InkSel));
  finally
    bmp.Free;
  end;
end;

function TImageInkHostsTest.NewListGroup(AGlyphOnTheHeader, ACollapsed: Boolean): TTyListGroupPanel;
var
  g: TTyListGroup;
begin
  Result := TTyListGroupPanel.Create(FForm);
  Result.Controller := FCtl;
  Place(Result, 240, 200);
  Result.Images := FList;
  Result.Collapsed := ACollapsed;
  g := Result.Groups.Add;
  if AGlyphOnTheHeader then
  begin
    g.ImageIndex := GLYPH;
    g.Items.Add.ImageIndex := IMAGE;
  end
  else
  begin
    g.ImageIndex := IMAGE;
    g.Items.Add.ImageIndex := GLYPH;
  end;
end;

const
  { an open group's header resolves :selected }
  GroupHeaderRule = 'TyListGroupHeader { color: %0:s; } TyListGroupHeader:selected { color: %0:s; }';

procedure TImageInkHostsTest.TestListGroupItem;
begin
  NewListGroup(False, False);
  CheckFollowsTheInk('list group item', 'TyListGroupItem { color: %s; }');
end;

procedure TImageInkHostsTest.TestListGroupHeader;
begin
  NewListGroup(True, False);
  CheckFollowsTheInk('list group header', GroupHeaderRule);
end;

procedure TImageInkHostsTest.TestListGroupItemCollapsed;
begin
  NewListGroup(False, True);
  CheckFollowsTheInk('collapsed list group item', 'TyListGroupItem { color: %s; }');
end;

procedure TImageInkHostsTest.TestListGroupHeaderCollapsed;
begin
  NewListGroup(True, True);
  CheckFollowsTheInk('collapsed list group header', GroupHeaderRule);
end;

function TImageInkHostsTest.NewMenu(AOnTheLclMenu: Boolean; AEnabled: Boolean): TTyMenuView;
var
  mm: TMainMenu;
  top, it: TMenuItem;
begin
  mm := TMainMenu.Create(FForm);
  if AOnTheLclMenu then mm.Images := FList;
  top := TMenuItem.Create(mm);
  mm.Items.Add(top);
  it := TMenuItem.Create(mm);
  it.ImageIndex := GLYPH;
  it.Enabled := AEnabled;
  top.Add(it);
  it := TMenuItem.Create(mm);
  it.ImageIndex := IMAGE;
  it.Enabled := AEnabled;
  top.Add(it);
  Result := TTyMenuView.Create(FForm);
  Result.Controller := FCtl;
  Place(Result, 200, 80);
  if not AOnTheLclMenu then Result.Images := FList;
  Result.SetRows(TyBuildMenuRows(top));
end;

procedure TImageInkHostsTest.TestMenu;
begin
  NewMenu(False);
  CheckFollowsTheInk('menu', 'TyMenuItem { color: %s; }');
end;

procedure TImageInkHostsTest.TestMenuOnTheLclMenusOwnList;
begin
  NewMenu(True);
  CheckFollowsTheInk('menu, the LCL menu''s Images', 'TyMenuItem { color: %s; }');
end;

procedure TImageInkHostsTest.TestMenuDisabledItemIsTheDisabledInkOnce;
var
  bmp: TBGRABitmap;
  onLcl: Boolean;
begin
  for onLcl := False to True do
  begin
    FreeAndNil(FControl);
    NewMenu(onLcl, False);
    FCtl.StyleOverride := Format('TyMenuItem { color: %s; } TyMenuItem:disabled { color: %s; }',
      [Css(InkA), Css(InkDis)]);
    bmp := Paint;
    try
      AssertTrue('a disabled item: the disabled ink, at full strength', HasBlock(bmp, InkDis));
      AssertFalse('and not the enabled one', HasBlock(bmp, InkA));
      { Only the glyph leaves the LCL list's own drawing: an image of it is still greyed the
        way that list greys a disabled item. }
      if onLcl then
        AssertFalse('the LCL menu''s image is greyed by its list', HasBlock(bmp, Photo));
    finally
      bmp.Free;
    end;
  end;
end;

procedure TImageInkHostsTest.TabImage(Sender: TObject; AIndex: Integer; var AImageIndex: Integer);
begin
  if AIndex = 0 then AImageIndex := GLYPH else AImageIndex := IMAGE;
end;

procedure TImageInkHostsTest.TestTabStrip;
var
  t: TTyTabSet;
begin
  t := TTyTabSet.Create(FForm);
  t.Controller := FCtl;
  Place(t, 240, 40);
  t.Tabs.AddStrings(['', '']);
  t.Images := FList;
  t.OnGetImageIndex := @TabImage;
  t.TabIndex := 1;    { the glyph's tab at rest }
  CheckFollowsTheInk('tab', 'TyTab { color: %s; }');
end;

procedure TImageInkHostsTest.TestValueListEditor;
var
  e: TTyValueListEditor;
begin
  e := TTyValueListEditor.Create(FForm);
  e.Controller := FCtl;
  Place(e, 240, 120);
  e.Images := FList;
  e.AddRow('', '').ImageIndex := GLYPH;
  e.AddRow('', '').ImageIndex := IMAGE;
  CheckFollowsTheInk('value list', 'TyValueListEditorRow { color: %s; }');
end;

procedure TImageInkHostsTest.TestNavigator;
var
  n: TTyDBNavigator;
  ds: TBufDataset;
  src: TDataSource;
  i: Integer;
begin
  { A navigator's images are one per button: the glyph on all of them, on a dataset that
    leaves some of the buttons usable. }
  FList.Names.Clear;
  for i := 0 to 9 do
    FList.Names.Add('block');
  ds := TBufDataset.Create(nil);
  src := TDataSource.Create(nil);
  try
    ds.FieldDefs.Add('ID', ftInteger);
    ds.CreateDataset;
    ds.AppendRecord([1]);
    ds.AppendRecord([2]);
    ds.MergeChangeLog;
    ds.First;
    src.DataSet := ds;
    n := TTyDBNavigator.Create(FForm);
    n.Controller := FCtl;
    Place(n, 300, 40);
    n.Images := FList;
    n.DataSource := src;
    CheckFollowsTheInk('navigator', 'TyDBNavigatorButton { color: %s; }', False);
    n.DataSource := nil;
  finally
    src.Free;
    ds.Free;
  end;
end;

procedure TImageInkHostsTest.TestNavigatorDisabledButtonIsTheDisabledInkOnce;
var
  n: TTyDBNavigator;
  list: TTyVirtualImageList;
  bmp: TBGRABitmap;
  i: Integer;
begin
  list := TTyVirtualImageList.Create(nil);
  try
    list.Collection := FColl;
    list.IconFont := FFont;
    for i := 0 to 4 do
    begin
      list.Names.Add('block');
      list.Names.Add('photo');
    end;
    n := TTyDBNavigator.Create(FForm);
    n.Controller := FCtl;
    Place(n, 300, 40);
    n.Images := list;
    Theme('TyDBNavigatorButton:disabled { color: %s; opacity: 1; }', InkDis);
    bmp := Paint;
    try
      { The button is ghosted because it cannot be used. The glyph already wears the disabled
        ink and is not faded on top of it; the image has no ink to wear and is. }
      AssertTrue('the glyph: the disabled ink, at full strength', HasBlock(bmp, InkDis));
      AssertFalse('the image: ghosted', HasBlock(bmp, Photo));
    finally
      bmp.Free;
    end;
    n.Images := nil;
  finally
    list.Free;
  end;
end;

procedure TImageInkHostsTest.TestImageControl;
var
  img: TTyImage;
  bmp: TBGRABitmap;
begin
  img := TTyImage.Create(FForm);
  img.Controller := FCtl;
  Place(img, 48, 48);
  img.Images := FList;
  img.ImageIndex := GLYPH;
  CheckFollowsTheInk('image control', 'TyImage { color: %s; }', False);
  img.ImageIndex := IMAGE;
  Theme('TyImage { color: %s; }', InkA);
  bmp := Paint;
  try
    AssertTrue('a collection image keeps its colours', HasBlock(bmp, Photo));
  finally
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TImageInkHostsTest);

end.
