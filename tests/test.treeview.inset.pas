unit test.treeview.inset;
{ #99: the tree's main column has a leading inset, and the gap in front of the caption can
  be set.

  The main column started its content at the cell's edge plus the indent, so a level-0 node
  without root lines put its icon right on the edge, and nothing but Indent -- which is also
  the image slot's width -- could move it. --treeview-margin is now an inset before the
  indent at every level (4 px by default, as --listview-text-margin, so a tree lines up with
  list rows), and the expander, the tree lines, the image and the caption all move with it.
  --treeview-icon-gap sets the gap in front of the caption (2 px, as before). Both are read
  per control, so one tree can set them in its StyleOverride (StyleMetric, test.stylemetric).

  Where things are is read from the hit test (image, expander) and from the rendered tree
  (the caption's ink, the tree lines), each against the same tree with the margin at 0. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, Controls, ImgList, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Columns, tyControls.TreeView;

type
  TTvInsetAccess = class(TTyTreeView)
  public
    procedure XRender(ABmp: TBGRABitmap);
  end;

  TTreeViewInsetTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FImages: TImageList;
    FTree: TTvInsetAccess;
    function RowY(ARow: Integer): Integer;
    { the first / last x across row ARow that the hit test calls APart }
    function FirstX(APart: TTyTreeHitPart; ARow: Integer): Integer;
    function LastX(APart: TTyTreeHitPart; ARow: Integer): Integer;
    function Render: TBGRABitmap;
    { the leftmost dark (caption) pixel on row ARow right of AFromX }
    function InkLeft(ABmp: TBGRABitmap; ARow, AFromX: Integer): Integer;
    { the leftmost pixel on row ARow, one pixel below its top, that is not the background:
      with root lines on, the elbow line of a child row }
    function LineX(ABmp: TBGRABitmap; ARow: Integer): Integer;
    { every x left of AMaxX on row ARow, one pixel below its top, that is drawn and is not the
      red icon: the tree lines crossing that row -- the ancestors' and the node's own elbow }
    function LineXs(ABmp: TBGRABitmap; ARow, AMaxX: Integer): TIntegerDynArray;
    procedure CheckLinesMove(AColumns: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLevelZeroHasTheMargin;
    procedure TestStyleOverrideSetsTheMargin;
    procedure TestTheThemeSetsTheMargin;
    procedure TestTheGapSitsInFrontOfTheCaption;
    procedure TestTheExpanderAndTheLinesMoveWithIt;
    procedure TestTheLinesMoveInAColumnTreeToo;
    procedure TestTheWidthCountsTheMarginAndTheGap;
    procedure TestRightToLeftMirrorsIt;
    procedure TestTreeAndListMarginsAgreeAtBothDensities;
    procedure TestTheOldSignatureKeepsItsGeometry;
  end;

implementation

const
  ICON = 16;

procedure TTvInsetAccess.XRender(ABmp: TBGRABitmap);
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(Width, Height);
    b.Canvas.Brush.Color := clWhite;
    b.Canvas.FillRect(0, 0, Width, Height);
    RenderTo(b.Canvas, Rect(0, 0, Width, Height), 96);
    ABmp.Assign(b);
  finally
    b.Free;
  end;
end;

procedure TTreeViewInsetTest.SetUp;
var
  b: TBitmap;
  it: TTyTreeNodeItem;
begin
  FCtl := TTyStyleController.Create(nil);
  FImages := TImageList.Create(nil);
  FImages.Width := ICON;
  FImages.Height := ICON;
  b := TBitmap.Create;
  try
    b.PixelFormat := pf24bit;
    b.SetSize(ICON, ICON);
    b.Canvas.Brush.Color := RGBToColor(255, 0, 0);
    b.Canvas.FillRect(0, 0, ICON, ICON);
    FImages.Add(b, nil);
  finally
    b.Free;
  end;
  FTree := TTvInsetAccess.Create(nil);
  FTree.Controller := FCtl;
  FTree.Font.PixelsPerInch := 96;
  FTree.SetBounds(0, 0, 300, 200);
  FTree.Images := FImages;
  FTree.ShowRoot := False;
  FTree.ShowTreeLines := False;
  it := FTree.Items.AddChild(nil, 'Alpha');
  it.ImageIndex := 0;
  it := FTree.Items.AddChild(it, 'Child');
  it.ImageIndex := 0;
  it := FTree.Items.AddChild(nil, 'Beta');
  it.ImageIndex := 0;
end;

procedure TTreeViewInsetTest.TearDown;
begin
  FTree.Free;
  FImages.Free;
  FCtl.Free;
end;

function TTreeViewInsetTest.RowY(ARow: Integer): Integer;
var
  n: PTyTreeNode;
  part: TTyTreeHitPart;
  y, row: Integer;
  last: PTyTreeNode;
begin
  { walk down the middle of the tree; a new node is a new row }
  row := -1;
  last := nil;
  for y := 0 to FTree.Height - 1 do
  begin
    n := FTree.GetNodeAtPoint(FTree.Width div 2, y, part);
    if (n <> nil) and (n <> last) then
    begin
      Inc(row);
      last := n;
      if row = ARow then Exit(y + 4);
    end;
  end;
  Fail(Format('precondition: there is a row %d', [ARow]));
  Result := -1;
end;

function TTreeViewInsetTest.FirstX(APart: TTyTreeHitPart; ARow: Integer): Integer;
var
  x, y: Integer;
  part: TTyTreeHitPart;
begin
  y := RowY(ARow);
  for x := 0 to FTree.Width - 1 do
    if (FTree.GetNodeAtPoint(x, y, part) <> nil) and (part = APart) then Exit(x);
  Fail('precondition: the row has that part');
  Result := -1;
end;

function TTreeViewInsetTest.LastX(APart: TTyTreeHitPart; ARow: Integer): Integer;
var
  x, y: Integer;
  part: TTyTreeHitPart;
begin
  y := RowY(ARow);
  for x := FTree.Width - 1 downto 0 do
    if (FTree.GetNodeAtPoint(x, y, part) <> nil) and (part = APart) then Exit(x);
  Fail('precondition: the row has that part');
  Result := -1;
end;

function TTreeViewInsetTest.Render: TBGRABitmap;
begin
  Result := TBGRABitmap.Create(FTree.Width, FTree.Height);
  FTree.XRender(Result);
end;

function TTreeViewInsetTest.InkLeft(ABmp: TBGRABitmap; ARow, AFromX: Integer): Integer;
var
  x, y, top: Integer;
  p: TBGRAPixel;
begin
  top := RowY(ARow) - 4;
  for x := AFromX to ABmp.Width - 1 do
    for y := top to top + 14 do
    begin
      p := ABmp.GetPixel(x, y);
      if (p.red < 110) and (p.green < 110) and (p.blue < 110) then Exit(x);
    end;
  Fail('precondition: the caption is drawn');
  Result := -1;
end;

function TTreeViewInsetTest.LineX(ABmp: TBGRABitmap; ARow: Integer): Integer;
var
  x, y: Integer;
  bg, p: TBGRAPixel;
begin
  y := RowY(ARow) - 3;   { one pixel into the row, above the elbow's horizontal run }
  bg := ABmp.GetPixel(ABmp.Width - 3, y);
  for x := 0 to ABmp.Width - 1 do
  begin
    p := ABmp.GetPixel(x, y);
    if (Abs(p.red - bg.red) > 24) or (Abs(p.green - bg.green) > 24) or (Abs(p.blue - bg.blue) > 24) then
      Exit(x);
  end;
  Fail('precondition: a tree line is drawn on the row');
  Result := -1;
end;

function TTreeViewInsetTest.LineXs(ABmp: TBGRABitmap; ARow, AMaxX: Integer): TIntegerDynArray;
var
  x, y, n: Integer;
  bg, p: TBGRAPixel;
begin
  Result := nil;
  n := 0;
  y := RowY(ARow) - 3;
  bg := ABmp.GetPixel(ABmp.Width - 3, y);
  for x := 0 to AMaxX - 1 do
  begin
    p := ABmp.GetPixel(x, y);
    if (p.red > 200) and (p.green < 60) then Continue;   { the icon }
    if (Abs(p.red - bg.red) > 24) or (Abs(p.green - bg.green) > 24) or (Abs(p.blue - bg.blue) > 24) then
    begin
      Inc(n);
      SetLength(Result, n);
      Result[n - 1] := x;
    end;
  end;
end;

procedure TTreeViewInsetTest.CheckLinesMove(AColumns: Boolean);
var
  btn0, img0, i: Integer;
  lines0, lines: TIntegerDynArray;
  bmp: TBGRABitmap;
  c: TTyColumn;
begin
  if AColumns then
  begin
    c := FTree.Header.Columns.Add as TTyColumn;
    c.Text := 'Name';
    c.Width := 250;
  end;
  FTree.ShowRoot := True;
  FTree.ShowTreeLines := True;
  FTree.FullExpand;
  { #101: the classic connectors, which draw the node's own elbow as well as its ancestors' }
  FTree.StyleOverride := '--treeview-margin: 0px; --treeview-lines: classic';
  btn0 := FirstX(hpButton, 0);
  img0 := FirstX(hpImage, 1);
  bmp := Render;
  try
    lines0 := LineXs(bmp, 1, img0);
  finally
    bmp.Free;
  end;
  { Alpha has a sibling below it, so its line runs down through its child's row; the child's
    own elbow is the other }
  AssertTrue('precondition: the ancestor''s line and the elbow cross the child''s row',
    Length(lines0) >= 2);
  FTree.StyleOverride := '--treeview-margin: 10px; --treeview-lines: classic';
  AssertEquals('the expander', btn0 + 10, FirstX(hpButton, 0));
  bmp := Render;
  try
    lines := LineXs(bmp, 1, img0 + 10);
  finally
    bmp.Free;
  end;
  AssertEquals('as many line pixels', Length(lines0), Length(lines));
  for i := 0 to High(lines0) do
    AssertEquals('every tree line on the child''s row moves with the margin', lines0[i] + 10, lines[i]);
end;

procedure TTreeViewInsetTest.TestLevelZeroHasTheMargin;
var
  img0, lbl0: Integer;
begin
  FTree.StyleOverride := '--treeview-margin: 0px';
  img0 := FirstX(hpImage, 0);
  FTree.StyleOverride := '';
  AssertEquals('the level-0 image is 4 px in by default', img0 + 4, FirstX(hpImage, 0));
end;

procedure TTreeViewInsetTest.TestStyleOverrideSetsTheMargin;
var
  img0: Integer;
  bmp: TBGRABitmap;
  ink0: Integer;
begin
  FTree.FullExpand;   { row 1 is Alpha's child }
  FTree.StyleOverride := '--treeview-margin: 0px';
  img0 := FirstX(hpImage, 0);
  bmp := Render;
  try
    ink0 := InkLeft(bmp, 0, img0 + ICON);
  finally
    bmp.Free;
  end;
  FTree.StyleOverride := '--treeview-margin: 10px';
  AssertEquals('the image', img0 + 10, FirstX(hpImage, 0));
  bmp := Render;
  try
    AssertEquals('the caption with it', ink0 + 10, InkLeft(bmp, 0, img0 + 10 + ICON));
  finally
    bmp.Free;
  end;
  AssertEquals('a child row too: the margin comes before every level''s indent',
    img0 + 10 + 16, FirstX(hpImage, 1));
end;

procedure TTreeViewInsetTest.TestTheThemeSetsTheMargin;
var
  img0: Integer;
begin
  FTree.StyleOverride := '--treeview-margin: 0px';
  img0 := FirstX(hpImage, 0);
  FTree.StyleOverride := '';
  FCtl.StyleOverride := ':root { --treeview-margin: 7px; }';
  AssertEquals('the theme''s margin', img0 + 7, FirstX(hpImage, 0));
end;

procedure TTreeViewInsetTest.TestTheGapSitsInFrontOfTheCaption;
var
  img, ink2: Integer;
  bmp: TBGRABitmap;
begin
  img := FirstX(hpImage, 0);
  bmp := Render;
  try
    ink2 := InkLeft(bmp, 0, img + ICON);
  finally
    bmp.Free;
  end;
  FTree.StyleOverride := '--treeview-icon-gap: 8px';
  AssertEquals('the image stays', img, FirstX(hpImage, 0));
  bmp := Render;
  try
    AssertEquals('the caption moves by the extra 6 px', ink2 + 6, InkLeft(bmp, 0, img + ICON));
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewInsetTest.TestTheExpanderAndTheLinesMoveWithIt;
begin
  CheckLinesMove(False);
end;

procedure TTreeViewInsetTest.TestTheLinesMoveInAColumnTreeToo;
begin
  { a tree with columns paints its rows through the other path }
  CheckLinesMove(True);
end;

procedure TTreeViewInsetTest.TestTheWidthCountsTheMarginAndTheGap;
var
  r0: Integer;
begin
  FTree.StyleOverride := '--treeview-margin: 0px';
  Render.Free;
  r0 := FTree.RangeX;
  AssertTrue('precondition: the paint measured the rows', r0 > 0);
  FTree.StyleOverride := '--treeview-margin: 10px';
  Render.Free;
  AssertEquals('the scroll width counts the margin', r0 + 10, FTree.RangeX);
  FTree.StyleOverride := '--treeview-margin: 10px; --treeview-icon-gap: 8px';
  Render.Free;
  AssertEquals('and the extra gap', r0 + 10 + 6, FTree.RangeX);
end;

procedure TTreeViewInsetTest.TestRightToLeftMirrorsIt;
var
  img0: Integer;
begin
  FTree.BiDiMode := bdRightToLeft;
  FTree.StyleOverride := '--treeview-margin: 0px';
  img0 := LastX(hpImage, 0);
  FTree.StyleOverride := '--treeview-margin: 10px';
  AssertEquals('the image 10 px in from the right edge', img0 - 10, LastX(hpImage, 0));
end;

procedure TTreeViewInsetTest.TestTreeAndListMarginsAgreeAtBothDensities;
begin
  AssertEquals('classic: the tree''s margin is the list''s text margin',
    FCtl.Metric('--listview-text-margin', 0), FTree.StyleMetric('--treeview-margin', -1));
  FCtl.Density := tdModern;
  AssertEquals('modern: so it is with the density pack too',
    FCtl.Metric('--listview-text-margin', 0), FTree.StyleMetric('--treeview-margin', -1));
  AssertTrue('precondition: the pack changes it', FTree.StyleMetric('--treeview-margin', -1) <> 4);
end;

procedure TTreeViewInsetTest.TestTheOldSignatureKeepsItsGeometry;
var
  s: TTyTreeCaptionSlots;
begin
  { a caller of the public helper from before #99 gets what it always got: no inset, the
    2 px pad and no extra gap }
  s := TyTreeCaptionSlots(10, 210, 96, 16, 0, False, True, True, True, False);
  AssertEquals('the check box at the cell''s edge', 10, s.CheckX);
  AssertEquals('then the image', 10 + 16, s.ImageX);
  AssertEquals('then the caption', 10 + 16 + 16, s.CaptionX);
  AssertEquals('with no extra gap', 0, s.GapW);
  s := TyTreeCaptionSlots(10, 210, 96, 16, 1, True, False, True, True, False);
  AssertEquals('a level-1 node with root lines: two indent steps', 10 + 32, s.ImageX);
end;

initialization
  RegisterTest(TTreeViewInsetTest);
end.
