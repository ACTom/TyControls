unit test.devicescale.controls;
{$mode objfpc}{$H+}

{ #83: controls in the states where they draw on the painter's layer directly.

  The palette sweep (test.devicescale.sweep) sees each control as it is created -- an image with
  no picture, a tree with no nodes -- so the drawing that needs content is never reached there.
  Each check here builds a control WITH that content, draws it at S = 2 and compares it with
  S = 1 (test.devicescale.support). }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, ImgList, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.IconFont, tyControls.Image, tyControls.ImageView, tyControls.GlyphButtons,
  tyControls.CharImage, tyControls.ComboBoxEx, Menus, tyControls.HtmlLabel, tyControls.GlowLabel,
  tyControls.Menu, tyControls.Chart, tyControls.HeaderControl, tyControls.Dialogs.Color,
  tyControls.ListView, tyControls.ListBox, tyControls.AdvancedListBox, tyControls.TabSet,
  tyControls.ListGroupPanel, tyControls.ValueListEditor, tyControls.ListView.Layout,
  tyControls.Columns, tyControls.TreeView,
  tyControls.Types, test.devicescale.support;

type
  TDeviceScaleControlsTest = class(TDeviceScaleCase)
  private
    FIconFont: TTyIconFont;
    FImages: TImageList;
    FMode: Integer;
    function IconFont: TTyIconFont;
    function Images: TImageList;
    function BuildImage(AParent: TWinControl; APPI: Integer): TControl;
    function BuildImageView(AParent: TWinControl; APPI: Integer): TControl;
    function BuildGlyphButton(AParent: TWinControl; APPI: Integer): TControl;
    function BuildCharImage(AParent: TWinControl; APPI: Integer): TControl;
    function BuildComboBoxEx(AParent: TWinControl; APPI: Integer): TControl;
    function BuildHtmlLabel(AParent: TWinControl; APPI: Integer): TControl;
    function BuildGlowLabel(AParent: TWinControl; APPI: Integer): TControl;
    function BuildMenuView(AParent: TWinControl; APPI: Integer): TControl;
    function BuildBarChart(AParent: TWinControl; APPI: Integer): TControl;
    function BuildHeader(AParent: TWinControl; APPI: Integer): TControl;
    function BuildHsvSquare(AParent: TWinControl; APPI: Integer): TControl;
    function BuildHueBar(AParent: TWinControl; APPI: Integer): TControl;
    function BuildListViewReport(AParent: TWinControl; APPI: Integer): TControl;
    function BuildListViewMarquee(AParent: TWinControl; APPI: Integer): TControl;
    function BuildListBoxScrolled(AParent: TWinControl; APPI: Integer): TControl;
    function BuildAdvancedListBox(AParent: TWinControl; APPI: Integer): TControl;
    function BuildTabSetOverflow(AParent: TWinControl; APPI: Integer): TControl;
    function BuildListGroupPanel(AParent: TWinControl; APPI: Integer): TControl;
    function BuildValueListEditor(AParent: TWinControl; APPI: Integer): TControl;
    procedure TabImage(Sender: TObject; AIndex: Integer; var AImageIndex: Integer);
    function NewTree(AParent: TWinControl; APPI: Integer; AColumns: Boolean): TTyTreeView;
    function BuildTreeLines(AParent: TWinControl; APPI: Integer): TControl;
    function BuildTreeSeparators(AParent: TWinControl; APPI: Integer): TControl;
    function BuildTreeMixedCheck(AParent: TWinControl; APPI: Integer): TControl;
    function BuildTreeColumns(AParent: TWinControl; APPI: Integer): TControl;
    function BuildTreeColumnDrag(AParent: TWinControl; APPI: Integer): TControl;
    function BuildTreeDropMark(AParent: TWinControl; APPI: Integer): TControl;
  protected
    procedure TearDown; override;
  published
    { Task 9: icons and pictures. }
    procedure TestImageStretched;
    procedure TestImageCentred;
    procedure TestImageAtItsOwnSize;
    procedure TestImageFromImageList;
    procedure TestImageView;
    procedure TestGlyphButtonIcon;
    procedure TestCharImage;
    procedure TestComboBoxExImage;
    { Task 10: text laid out on the layer, and the rest of that family. }
    procedure TestHtmlLabelRichText;
    procedure TestGlowLabel;
    procedure TestMenuViewBannerAndIcons;
    procedure TestBarChartWithLegend;
    procedure TestHeaderDividers;
    procedure TestColourSquare;
    procedure TestHueBar;
    { Task 11: lists and their clips. }
    procedure TestListViewReport;
    procedure TestListViewMarquee;
    { A 1-px rule drawn in layout coordinates hardly moves the comparison: half its length at
      half its strength, on a field the same colour. The header's dividers are such rules, so
      they are checked as rules (CheckRules). }
    procedure TestListViewHeaderRules;
    procedure TestListBoxScrolled;
    procedure TestAdvancedListBoxIcons;
    procedure TestTabSetOverflow;
    procedure TestListGroupPanelIcons;
    procedure TestValueListEditorImage;
    { Task 12: the tree's lines, marks and clips. }
    procedure TestTreeLines;
    procedure TestTreeSeparators;
    procedure TestTreeMixedCheck;
    procedure TestTreeColumnsWithLines;
    procedure TestTreeHeaderRules;
    procedure TestTreeSeparatorRules;
    procedure TestTreeColumnDrag;
    procedure TestTreeDropAbove;
    procedure TestTreeDropBelow;
    procedure TestTreeDropOn;
  end;

{ A picture with structure in every direction, so a placement or a stretch that is off shows. }
procedure TyFillTestPicture(ABmp: TBitmap; AW, AH: Integer);

implementation

type
  TControlAccess = class(TControl);
  TListViewAccess = class(TTyListView);
  TTreeAccess = class(TTyTreeView);

const
  CTreeW = 240;
  CTreeH = 160;

procedure TyFillTestPicture(ABmp: TBitmap; AW, AH: Integer);
var
  x, y: Integer;
begin
  ABmp.PixelFormat := pf24bit;
  ABmp.SetSize(AW, AH);
  for y := 0 to AH - 1 do
    for x := 0 to AW - 1 do
      ABmp.Canvas.Pixels[x, y] := RGBToColor((x * 255) div AW, (y * 255) div AH,
        ((x div 4 + y div 4) mod 2) * 200);
end;

procedure TDeviceScaleControlsTest.TearDown;
begin
  FreeAndNil(FIconFont);
  FreeAndNil(FImages);
  inherited TearDown;
end;

function TDeviceScaleControlsTest.IconFont: TTyIconFont;
var
  i: Integer;
begin
  if FIconFont = nil then
  begin
    FIconFont := TTyIconFont.Create(nil);
    FIconFont.FontFamily := 'Arial';
    for i := 0 to 11 do
      FIconFont.MapGlyph('glyph' + IntToStr(i), Ord('A') + i);   // letters: a font with ink
  end;
  Result := FIconFont;
end;

function TDeviceScaleControlsTest.Images: TImageList;
var
  b: TBitmap;
begin
  if FImages = nil then
  begin
    FImages := TImageList.Create(nil);
    FImages.Width := 16;
    FImages.Height := 16;
    b := TBitmap.Create;
    try
      TyFillTestPicture(b, 16, 16);
      FImages.Add(b, nil);
    finally
      b.Free;
    end;
  end;
  Result := FImages;
end;

{ ---- builders ---- }

function TDeviceScaleControlsTest.BuildImage(AParent: TWinControl; APPI: Integer): TControl;
var
  im: TTyImage;
  b: TBitmap;
begin
  im := TTyImage.Create(AParent);
  im.Parent := AParent;
  TControlAccess(im).Font.PixelsPerInch := APPI;
  if FMode = 3 then
  begin
    { From an image list instead of a picture -- a foreign (LCL) one with a 16 px bitmap
      only, which at S = 2 must still show 16 layout pixels. }
    im.Images := Images;
    im.ImageIndex := 0;
    im.Center := True;
  end
  else
  begin
    b := TBitmap.Create;
    try
      TyFillTestPicture(b, 40, 28);
      im.Picture.Assign(b);
    finally
      b.Free;
    end;
  end;
  case FMode of
    0: im.Stretch := True;
    1: im.Center := True;
  end;
  Result := im;
end;

function TDeviceScaleControlsTest.BuildImageView(AParent: TWinControl; APPI: Integer): TControl;
var
  v: TTyImageView;
  b: TBitmap;
begin
  v := TTyImageView.Create(AParent);
  v.Parent := AParent;
  TControlAccess(v).Font.PixelsPerInch := APPI;
  b := TBitmap.Create;
  try
    TyFillTestPicture(b, 60, 40);
    v.Picture.Assign(b);
  finally
    b.Free;
  end;
  Result := v;
end;

function TDeviceScaleControlsTest.BuildGlyphButton(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyGlyphButton;
begin
  g := TTyGlyphButton.Create(AParent);
  g.Parent := AParent;
  TControlAccess(g).Font.PixelsPerInch := APPI;
  g.IconFont := IconFont;
  g.GlyphName := 'glyph3';
  g.Caption := 'Save';
  Result := g;
end;

function TDeviceScaleControlsTest.BuildCharImage(AParent: TWinControl; APPI: Integer): TControl;
var
  c: TTyCharImage;
begin
  c := TTyCharImage.Create(AParent);
  c.Parent := AParent;
  TControlAccess(c).Font.PixelsPerInch := APPI;
  c.IconFont := IconFont;
  c.GlyphName := 'glyph6';
  Result := c;
end;

function TDeviceScaleControlsTest.BuildComboBoxEx(AParent: TWinControl; APPI: Integer): TControl;
var
  c: TTyComboBoxEx;
begin
  c := TTyComboBoxEx.Create(AParent);
  c.Parent := AParent;
  TControlAccess(c).Font.PixelsPerInch := APPI;
  c.Images := Images;
  c.AddItem('First', 0);
  c.AddItem('Second', 0);
  c.ItemIndex := 0;
  Result := c;
end;

{ ---- Task 9 ---- }

procedure TDeviceScaleControlsTest.TestImageStretched;
begin
  FMode := 0;
  CheckScale('TTyImage-stretched', @BuildImage, 120, 80);
end;

procedure TDeviceScaleControlsTest.TestImageCentred;
begin
  FMode := 1;
  CheckScale('TTyImage-centred', @BuildImage, 120, 80);
end;

procedure TDeviceScaleControlsTest.TestImageAtItsOwnSize;
begin
  FMode := 2;
  CheckScale('TTyImage-own-size', @BuildImage, 120, 80);
end;

procedure TDeviceScaleControlsTest.TestImageFromImageList;
begin
  FMode := 3;
  CheckScale('TTyImage-image-list', @BuildImage, 60, 40);
end;

procedure TDeviceScaleControlsTest.TestImageView;
begin
  CheckScale('TTyImageView', @BuildImageView, 160, 120);
end;

procedure TDeviceScaleControlsTest.TestGlyphButtonIcon;
begin
  CheckScale('TTyGlyphButton-icon', @BuildGlyphButton, 110, 32);
end;

procedure TDeviceScaleControlsTest.TestCharImage;
begin
  CheckScale('TTyCharImage', @BuildCharImage, 64, 64);
end;

procedure TDeviceScaleControlsTest.TestComboBoxExImage;
begin
  CheckScale('TTyComboBoxEx-image', @BuildComboBoxEx, 160, 28);
end;

{ ---- Task 10 ---- }

function TDeviceScaleControlsTest.BuildHtmlLabel(AParent: TWinControl; APPI: Integer): TControl;
var
  h: TTyHtmlLabel;
begin
  h := TTyHtmlLabel.Create(AParent);
  h.Parent := AParent;
  TControlAccess(h).Font.PixelsPerInch := APPI;
  h.Html := 'Plain <b>bold</b> <u>under</u> <s>struck</s> <a href="x">link</a>';
  Result := h;
end;

function TDeviceScaleControlsTest.BuildGlowLabel(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyGlowLabel;
begin
  g := TTyGlowLabel.Create(AParent);
  g.Parent := AParent;
  TControlAccess(g).Font.PixelsPerInch := APPI;
  g.Caption := 'Glowing';
  g.GlowRadius := 6;
  g.GlowColor := TyRGBA(255, 0, 0, 255);   // a halo strong enough to show where it lands
  Result := g;
end;

function TDeviceScaleControlsTest.BuildMenuView(AParent: TWinControl; APPI: Integer): TControl;
var
  v: TTyMenuView;
  mm: TMainMenu;
  top, it: TMenuItem;
begin
  mm := TMainMenu.Create(AParent);   // freed with the form
  top := TMenuItem.Create(mm);
  top.Caption := 'File';
  mm.Items.Add(top);
  it := NewItem('Open', 0, False, True, nil, 0, '');
  it.ImageIndex := 0;
  top.Add(it);
  top.Add(NewItem('Save as', 0, False, True, nil, 0, ''));
  v := TTyMenuView.Create(AParent);
  v.Parent := AParent;
  TControlAccess(v).Font.PixelsPerInch := APPI;
  v.Images := Images;
  v.BannerCaption := 'Tools';
  v.BannerWidth := 22;
  v.SetRows(TyBuildMenuRows(top));
  Result := v;
end;

function TDeviceScaleControlsTest.BuildBarChart(AParent: TWinControl; APPI: Integer): TControl;
var
  c: TTyChart;
begin
  c := TTyChart.Create(AParent);
  c.Parent := AParent;
  TControlAccess(c).Font.PixelsPerInch := APPI;
  c.ChartType := ctBar;
  c.Title := 'Sales';
  c.Categories.Add('Q1');
  c.Categories.Add('Q2');
  c.Categories.Add('Q3');
  c.Series.Add.Values := '3,5,2';
  c.Series.Add.Values := '4,1,6';
  Result := c;
end;

function TDeviceScaleControlsTest.BuildHeader(AParent: TWinControl; APPI: Integer): TControl;
var
  h: TTyHeaderControl;
begin
  h := TTyHeaderControl.Create(AParent);
  h.Parent := AParent;
  TControlAccess(h).Font.PixelsPerInch := APPI;
  h.AddSection('Name', 80);
  h.AddSection('Size', 60);
  h.AddSection('Date', 70);
  Result := h;
end;

function TDeviceScaleControlsTest.BuildHsvSquare(AParent: TWinControl; APPI: Integer): TControl;
var
  q: TTyHSVSquare;
begin
  q := TTyHSVSquare.Create(AParent);
  q.Parent := AParent;
  TControlAccess(q).Font.PixelsPerInch := APPI;
  q.Hue := 200;
  Result := q;
end;

function TDeviceScaleControlsTest.BuildHueBar(AParent: TWinControl; APPI: Integer): TControl;
var
  b: TTyHueBar;
begin
  b := TTyHueBar.Create(AParent);
  b.Parent := AParent;
  TControlAccess(b).Font.PixelsPerInch := APPI;
  b.Hue := 120;
  Result := b;
end;

procedure TDeviceScaleControlsTest.TestHtmlLabelRichText;
begin
  CheckScale('TTyHtmlLabel-rich', @BuildHtmlLabel, 260, 26);
end;

procedure TDeviceScaleControlsTest.TestGlowLabel;
begin
  CheckScale('TTyGlowLabel', @BuildGlowLabel, 140, 40);
end;

procedure TDeviceScaleControlsTest.TestMenuViewBannerAndIcons;
begin
  CheckScale('TTyMenuView-banner-icons', @BuildMenuView, 180, 80);
end;

procedure TDeviceScaleControlsTest.TestBarChartWithLegend;
begin
  CheckScale('TTyChart-bars', @BuildBarChart, 260, 180);
end;

procedure TDeviceScaleControlsTest.TestHeaderDividers;
begin
  CheckScale('TTyHeaderControl-sections', @BuildHeader, 240, 26);
end;

procedure TDeviceScaleControlsTest.TestColourSquare;
begin
  CheckScale('TTyHSVSquare', @BuildHsvSquare, 120, 120);
end;

procedure TDeviceScaleControlsTest.TestHueBar;
begin
  CheckScale('TTyHueBar', @BuildHueBar, 18, 120);
end;

{ ---- Task 11 ---- }

function TDeviceScaleControlsTest.BuildListViewReport(AParent: TWinControl; APPI: Integer): TControl;
var
  lv: TTyListView;
  i: Integer;
  it: TTyListItem;
begin
  lv := TTyListView.Create(AParent);
  lv.Parent := AParent;
  TControlAccess(lv).Font.PixelsPerInch := APPI;
  lv.ViewStyle := lvsReport;
  lv.GridLines := True;
  lv.SmallImages := Images;
  lv.MultiSelect := True;
  lv.Columns.Add.Text := 'Name';
  lv.Columns.Add.Text := 'Size';
  lv.Columns.Add.Text := 'Kind';
  for i := 0 to 3 do
  begin
    it := lv.Items.Add;
    it.Caption := 'Item ' + IntToStr(i);
    it.ImageIndex := 0;
    it.SubItems.Add(IntToStr(i * 10) + ' KB');
    it.SubItems.Add('File');
  end;
  Result := lv;
end;

function TDeviceScaleControlsTest.BuildListViewMarquee(AParent: TWinControl; APPI: Integer): TControl;
begin
  { A rubber band in progress: pressed on the empty area below the rows, dragged up-left. }
  Result := BuildListViewReport(AParent, APPI);
  TControlAccess(Result).MouseDown(mbLeft, [ssLeft], 220, 140);
  TControlAccess(Result).MouseMove([ssLeft], 40, 50);
end;

function TDeviceScaleControlsTest.BuildListBoxScrolled(AParent: TWinControl; APPI: Integer): TControl;
var
  lb: TTyListBox;
  i: Integer;
begin
  lb := TTyListBox.Create(AParent);
  lb.Parent := AParent;
  TControlAccess(lb).Font.PixelsPerInch := APPI;
  for i := 0 to 29 do lb.Items.Add('Row number ' + IntToStr(i));
  lb.TopIndex := 5;
  Result := lb;
end;

function TDeviceScaleControlsTest.BuildAdvancedListBox(AParent: TWinControl; APPI: Integer): TControl;
var
  lb: TTyAdvancedListBox;
begin
  lb := TTyAdvancedListBox.Create(AParent);
  lb.Parent := AParent;
  TControlAccess(lb).Font.PixelsPerInch := APPI;
  lb.Images := Images;
  lb.AddItem('First', 'with a subtitle', 0);
  lb.AddItem('Second', 'another one', 0);
  Result := lb;
end;

procedure TDeviceScaleControlsTest.TabImage(Sender: TObject; AIndex: Integer; var AImageIndex: Integer);
begin
  AImageIndex := 0;
end;

function TDeviceScaleControlsTest.BuildTabSetOverflow(AParent: TWinControl; APPI: Integer): TControl;
var
  ts: TTyTabSet;
  i: Integer;
begin
  ts := TTyTabSet.Create(AParent);
  ts.Parent := AParent;
  TControlAccess(ts).Font.PixelsPerInch := APPI;
  ts.Images := Images;
  ts.OnGetImageIndex := @TabImage;
  for i := 0 to 9 do ts.Tabs.Add('Tab number ' + IntToStr(i));
  ts.TabIndex := 1;
  Result := ts;
end;

function TDeviceScaleControlsTest.BuildListGroupPanel(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyListGroupPanel;
  gi: Integer;
begin
  g := TTyListGroupPanel.Create(AParent);
  g.Parent := AParent;
  TControlAccess(g).Font.PixelsPerInch := APPI;
  g.Images := Images;
  gi := g.AddGroup('Documents', 0);
  g.AddItem(gi, 'Report', 0);
  g.AddItem(gi, 'Letter', 0);
  gi := g.AddGroup('Pictures', 0);
  g.AddItem(gi, 'Holiday', 0);
  Result := g;
end;

function TDeviceScaleControlsTest.BuildValueListEditor(AParent: TWinControl; APPI: Integer): TControl;
var
  v: TTyValueListEditor;
begin
  v := TTyValueListEditor.Create(AParent);
  v.Parent := AParent;
  TControlAccess(v).Font.PixelsPerInch := APPI;
  v.Images := Images;
  v.AddRow('Name', 'Value').ImageIndex := 0;
  v.AddRow('Other', 'Thing');
  Result := v;
end;

procedure TDeviceScaleControlsTest.TestListViewReport;
begin
  CheckScale('TTyListView-report', @BuildListViewReport, 280, 140);
end;

procedure TDeviceScaleControlsTest.TestListViewMarquee;
begin
  CheckScale('TTyListView-marquee', @BuildListViewMarquee, 280, 160);
end;

procedure TDeviceScaleControlsTest.TestListViewHeaderRules;
const
  W = 280;
  H = 140;
var
  f: TForm;
  c: TControl;
  headerH: Integer;
begin
  f := TForm.CreateNew(nil);
  try
    f.SetBounds(0, 0, W + 40, H + 40);
    c := BuildListViewReport(f, 96);
    c.SetBounds(0, 0, W, H);
    headerH := TListViewAccess(c).CurrentMetrics.HeaderH;
  finally
    f.Free;
  end;
  AssertTrue('the report view has a header', headerH > 4);
  { Three 100-px columns in 280: two dividers inside the control. }
  CheckRules('the list view header dividers', @BuildListViewReport, W, H,
    Rect(0, 0, W, headerH), True, 2, 8);
end;

procedure TDeviceScaleControlsTest.TestListBoxScrolled;
begin
  CheckScale('TTyListBox-scrolled', @BuildListBoxScrolled, 160, 120);
end;

procedure TDeviceScaleControlsTest.TestAdvancedListBoxIcons;
begin
  CheckScale('TTyAdvancedListBox-icons', @BuildAdvancedListBox, 200, 120);
end;

procedure TDeviceScaleControlsTest.TestTabSetOverflow;
begin
  CheckScale('TTyTabSet-overflow', @BuildTabSetOverflow, 240, 32);
end;

procedure TDeviceScaleControlsTest.TestListGroupPanelIcons;
begin
  CheckScale('TTyListGroupPanel-icons', @BuildListGroupPanel, 200, 160);
end;

procedure TDeviceScaleControlsTest.TestValueListEditorImage;
begin
  CheckScale('TTyValueListEditor-image', @BuildValueListEditor, 200, 80);
end;

{ ---- Task 12 ---- }

function TDeviceScaleControlsTest.NewTree(AParent: TWinControl; APPI: Integer;
  AColumns: Boolean): TTyTreeView;
var
  a, b: TTyTreeNodeItem;
  col: TTyColumn;
begin
  Result := TTyTreeView.Create(AParent);
  Result.Parent := AParent;
  TControlAccess(Result).Font.PixelsPerInch := APPI;
  { Sized here as well: the drag states below are set up with the mouse, on this layout. }
  Result.SetBounds(0, 0, CTreeW, CTreeH);
  Result.ShowTreeLines := False;
  Result.ShowSeparators := False;
  if AColumns then
  begin
    col := Result.Header.Columns.Add as TTyColumn;
    col.Text := 'Name';
    col.Width := 100;
    col := Result.Header.Columns.Add as TTyColumn;
    col.Text := 'Size';
    col.Width := 70;
    col := Result.Header.Columns.Add as TTyColumn;
    col.Text := 'Kind';
    col.Width := 70;
  end;
  a := Result.Items.AddChild(nil, 'Documents');
  b := Result.Items.AddChild(a, 'Reports');
  Result.Items.AddChild(b, 'First quarter');
  Result.Items.AddChild(b, 'Second quarter');
  Result.Items.AddChild(a, 'Letters');
  b := Result.Items.AddChild(nil, 'Pictures');
  Result.Items.AddChild(b, 'Holiday');
  Result.FullExpand;
end;

function TDeviceScaleControlsTest.BuildTreeLines(AParent: TWinControl; APPI: Integer): TControl;
var
  t: TTyTreeView;
begin
  t := NewTree(AParent, APPI, False);
  t.ShowTreeLines := True;
  Result := t;
end;

function TDeviceScaleControlsTest.BuildTreeSeparators(AParent: TWinControl; APPI: Integer): TControl;
var
  t: TTyTreeView;
begin
  t := NewTree(AParent, APPI, False);
  t.ShowSeparators := True;
  Result := t;
end;

function TDeviceScaleControlsTest.BuildTreeMixedCheck(AParent: TWinControl; APPI: Integer): TControl;
var
  t: TTyTreeView;
  i: Integer;
begin
  t := NewTree(AParent, APPI, False);
  t.Options := t.Options + [toCheckSupport];
  for i := 0 to t.Items.Count - 1 do
  begin
    t.Items[i].CheckType := ctTriStateCheckBox;
    if i mod 2 = 0 then t.Items[i].CheckState := csMixed;
  end;
  t.FullExpand;   // switching the check support on folds the tree back
  Result := t;
end;

function TDeviceScaleControlsTest.BuildTreeColumns(AParent: TWinControl; APPI: Integer): TControl;
var
  t: TTyTreeView;
begin
  t := NewTree(AParent, APPI, True);
  t.ShowTreeLines := True;
  Result := t;
end;

function TDeviceScaleControlsTest.BuildTreeColumnDrag(AParent: TWinControl; APPI: Integer): TControl;
var
  t: TTyTreeView;
  y: Integer;
begin
  { "Name" pressed in the header and dragged over "Size": the ghost over Name, the drop caret at
    Size's left edge. }
  t := NewTree(AParent, APPI, True);
  y := t.ContentRect.Top div 2;
  TControlAccess(t).MouseDown(mbLeft, [ssLeft], 40, y);
  TControlAccess(t).MouseMove([ssLeft], 130, y);
  Result := t;
end;

function TDeviceScaleControlsTest.BuildTreeDropMark(AParent: TWinControl; APPI: Integer): TControl;
var
  t: TTyTreeView;
  target: PTyTreeNode;
begin
  t := NewTree(AParent, APPI, False);
  target := t.Items[2].Node;   // "First quarter", a level-2 row in the middle
  TTreeAccess(t).SetActiveDragState(target, target, TTyTreeDropMode(FMode));
  Result := t;
end;

procedure TDeviceScaleControlsTest.TestTreeLines;
begin
  CheckScale('TTyTreeView-lines', @BuildTreeLines, CTreeW, CTreeH);
end;

procedure TDeviceScaleControlsTest.TestTreeSeparators;
begin
  CheckScale('TTyTreeView-separators', @BuildTreeSeparators, CTreeW, CTreeH);
end;

procedure TDeviceScaleControlsTest.TestTreeMixedCheck;
begin
  CheckScale('TTyTreeView-mixed-check', @BuildTreeMixedCheck, CTreeW, CTreeH);
end;

procedure TDeviceScaleControlsTest.TestTreeColumnsWithLines;
begin
  CheckScale('TTyTreeView-columns', @BuildTreeColumns, CTreeW, CTreeH);
end;

procedure TDeviceScaleControlsTest.TestTreeHeaderRules;
var
  f: TForm;
  c: TControl;
  band: TRect;
begin
  { As TestListViewHeaderRules. The band is the header above the content, between the
    content's sides (inside the frame). }
  f := TForm.CreateNew(nil);
  try
    f.SetBounds(0, 0, CTreeW + 40, CTreeH + 40);
    c := BuildTreeColumns(f, 96);
    band := TTyTreeView(c).ContentRect;
    band := Rect(band.Left, 0, band.Right, band.Top);
  finally
    f.Free;
  end;
  AssertTrue('the tree has a header', band.Bottom > 8);
  { Two dividers between three sections. }
  CheckRules('the tree header dividers', @BuildTreeColumns, CTreeW, CTreeH, band, True, 2, 8);
end;

procedure TDeviceScaleControlsTest.TestTreeSeparatorRules;
var
  f: TForm;
  c: TControl;
  band: TRect;
begin
  f := TForm.CreateNew(nil);
  try
    f.SetBounds(0, 0, CTreeW + 40, CTreeH + 40);
    c := BuildTreeSeparators(f, 96);
    band := TTyTreeView(c).ContentRect;
  finally
    f.Free;
  end;
  { A rule under each of the two top-level rows. }
  CheckRules('the tree row separators', @BuildTreeSeparators, CTreeW, CTreeH, band, False, 2, 8);
end;

procedure TDeviceScaleControlsTest.TestTreeColumnDrag;
begin
  CheckScale('TTyTreeView-column-drag', @BuildTreeColumnDrag, CTreeW, CTreeH);
end;

procedure TDeviceScaleControlsTest.TestTreeDropAbove;
begin
  FMode := Ord(dmAbove);
  CheckScale('TTyTreeView-drop-above', @BuildTreeDropMark, CTreeW, CTreeH);
end;

procedure TDeviceScaleControlsTest.TestTreeDropBelow;
begin
  FMode := Ord(dmBelow);
  CheckScale('TTyTreeView-drop-below', @BuildTreeDropMark, CTreeW, CTreeH);
end;

procedure TDeviceScaleControlsTest.TestTreeDropOn;
begin
  FMode := Ord(dmOn);
  CheckScale('TTyTreeView-drop-on', @BuildTreeDropMark, CTreeW, CTreeH);
end;

initialization
  RegisterTest(TDeviceScaleControlsTest);

end.
