unit test.treeview.lines;
{ #101: what the tree's lines and expanders look like is the theme's -- or one tree's --
  choice, and by default the lines no longer run through the chevron.

  The tree drew a full connector for every node -- the vertical line from the row above and
  a stub to its content -- meeting at the centre of the node's own expander slot. That is
  the geometry of a boxed +/- drawn on top of the junction; with a chevron in the slot the
  line ran straight through it. Four tokens, read per control (StyleToken / StyleColor,
  test.styletoken):

    --treeview-lines        guides (default): a vertical guide under each ancestor's
                            expander, nothing at the node's own level; classic: the old
                            connectors; none
    --treeview-lines-style  solid (default), dotted, dashed, or one or two lengths
    --treeview-lines-color  default: the tree's border colour, as before
    --treeview-expander     chevron (default), or plus-minus: a box over the junction

  A dotted or dashed line takes its phase from the content origin, not from where each
  segment starts, so segments in consecutive rows run on as one line, a stub meets its
  vertical on the same pattern, and the pattern scrolls with the content. ShowTreeLines is
  still the master switch.

  The lines are told apart by colour: the tree's own StyleOverride makes them pure red. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Columns,
  tyControls.TreeView, tyControls.BuiltinThemes;

type
  TTvLinesAccess = class(TTyTreeView)
  public
    procedure XRender(ABmp: TBGRABitmap; APPI: Integer = 96);
    function XBorder: TTyColor;
  end;

  TTreeViewLinesTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FTree: TTvLinesAccess;
    FA2: TTyTreeNodeItem;
    function RowTop(ARow: Integer): Integer;
    function RowH(ARow: Integer): Integer;
    function FirstX(APart: TTyTreeHitPart; ARow: Integer): Integer;
    function LastX(APart: TTyTreeHitPart; ARow: Integer): Integer;
    { the centre of row ARow's expander slot, which is where its lines run }
    function SlotX(ARow: Integer): Integer;
    function Render: TBGRABitmap;
    function IsLine(ABmp: TBGRABitmap; X, Y: Integer): Boolean;
    function IsInk(ABmp: TBGRABitmap; X, Y: Integer): Boolean;
    { the x of every line pixel across the tree at height Y }
    function LineXs(ABmp: TBGRABitmap; Y: Integer): TIntegerDynArray;
    function LineCount(ABmp: TBGRABitmap): Integer;
    { the line pixels down column X from AFromY to AToY (exclusive), as '#' and '.' }
    function Column(ABmp: TBGRABitmap; X, AFromY, AToY: Integer): string;
    procedure CheckXs(const AMsg: string; const AExpected: array of Integer;
      const AActual: TIntegerDynArray);
    procedure UseColumns;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheDefaultDrawsGuidesThatDoNotReachTheExpander;
    procedure TestClassicDrawsTheConnectors;
    procedure TestAGuideRunsUnderALastChildToo;
    procedure TestNoneDrawsNoLines;
    procedure TestShowTreeLinesIsTheMasterSwitch;
    procedure TestTheThemeChoosesForEveryTree;
    procedure TestTheColourIsTheBorderByDefault;
    procedure TestDottedAlternates;
    procedure TestADashListSetsTheRuns;
    procedure TestThePatternRunsOnAcrossRows;
    procedure TestTheCornerSharesThePhase;
    procedure TestThePatternMovesWithTheContent;
    procedure TestTheDashScalesWithTheDpi;
    procedure TestTheBoxDrawsPlusAndMinusOverTheJunction;
    procedure TestTheBoxIsHitLikeTheChevron;
    procedure TestALowRowGetsASmallerBox;
    procedure TestAColumnTreeDrawsTheSame;
    procedure TestRightToLeftKeepsTheLinesInTheSlots;
    procedure TestClassicSkinsPairBoxesWithDottedConnectors;
  end;

implementation

const
  RED = '--treeview-lines-color: #ff0000; ';

procedure TTvLinesAccess.XRender(ABmp: TBGRABitmap; APPI: Integer);
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(Width, Height);
    b.Canvas.Brush.Color := clWhite;
    b.Canvas.FillRect(0, 0, Width, Height);
    RenderTo(b.Canvas, Rect(0, 0, Width, Height), APPI);
    ABmp.Assign(b);
  finally
    b.Free;
  end;
end;

function TTvLinesAccess.XBorder: TTyColor;
begin
  Result := CurrentStyle.BorderColor;
end;

procedure TTreeViewLinesTest.SetUp;
var
  alpha, a1: TTyTreeNodeItem;
begin
  FCtl := TTyStyleController.Create(nil);
  FTree := TTvLinesAccess.Create(nil);
  FTree.Controller := FCtl;
  FTree.Font.PixelsPerInch := 96;
  FTree.SetBounds(0, 0, 300, 200);
  FTree.DefaultNodeHeight := 18;
  FTree.ShowRoot := True;
  { rows: 0 Alpha, 1 A1, 2 A1a, 3 A2 (collapsed, has a child), 4 Beta }
  alpha := FTree.Items.AddChild(nil, 'Alpha');
  a1 := FTree.Items.AddChild(alpha, 'A1');
  FTree.Items.AddChild(a1, 'A1a');
  FA2 := FTree.Items.AddChild(alpha, 'A2');
  FTree.Items.AddChild(FA2, 'A2a');
  FTree.Items.AddChild(nil, 'Beta');
  alpha.Expanded := True;
  a1.Expanded := True;
end;

procedure TTreeViewLinesTest.TearDown;
begin
  FTree.Free;
  FCtl.Free;
end;

function TTreeViewLinesTest.RowTop(ARow: Integer): Integer;
var
  n, last: PTyTreeNode;
  part: TTyTreeHitPart;
  y, row: Integer;
begin
  row := -1;
  last := nil;
  for y := 0 to FTree.Height - 1 do
  begin
    n := FTree.GetNodeAtPoint(FTree.Width div 2, y, part);
    if (n <> nil) and (n <> last) then
    begin
      Inc(row);
      last := n;
      if row = ARow then Exit(y);
    end;
  end;
  Fail(Format('precondition: there is a row %d', [ARow]));
  Result := -1;
end;

function TTreeViewLinesTest.RowH(ARow: Integer): Integer;
begin
  Result := RowTop(ARow + 1) - RowTop(ARow);
end;

function TTreeViewLinesTest.FirstX(APart: TTyTreeHitPart; ARow: Integer): Integer;
var
  x, y: Integer;
  part: TTyTreeHitPart;
begin
  y := RowTop(ARow) + 4;
  for x := 0 to FTree.Width - 1 do
    if (FTree.GetNodeAtPoint(x, y, part) <> nil) and (part = APart) then Exit(x);
  Fail('precondition: the row has that part');
  Result := -1;
end;

function TTreeViewLinesTest.LastX(APart: TTyTreeHitPart; ARow: Integer): Integer;
var
  x, y: Integer;
  part: TTyTreeHitPart;
begin
  y := RowTop(ARow) + 4;
  for x := FTree.Width - 1 downto 0 do
    if (FTree.GetNodeAtPoint(x, y, part) <> nil) and (part = APart) then Exit(x);
  Fail('precondition: the row has that part');
  Result := -1;
end;

function TTreeViewLinesTest.SlotX(ARow: Integer): Integer;
begin
  Result := (FirstX(hpButton, ARow) + LastX(hpButton, ARow) + 1) div 2;
end;

function TTreeViewLinesTest.Render: TBGRABitmap;
begin
  Result := TBGRABitmap.Create(FTree.Width, FTree.Height);
  FTree.XRender(Result);
end;

function TTreeViewLinesTest.IsLine(ABmp: TBGRABitmap; X, Y: Integer): Boolean;
var
  p: TBGRAPixel;
begin
  p := ABmp.GetPixel(X, Y);
  Result := (p.red > 200) and (p.green < 60) and (p.blue < 60);
end;

function TTreeViewLinesTest.IsInk(ABmp: TBGRABitmap; X, Y: Integer): Boolean;
var
  p: TBGRAPixel;
begin
  p := ABmp.GetPixel(X, Y);
  Result := (p.red < 140) and (p.green < 140) and (p.blue < 140);
end;

function TTreeViewLinesTest.LineXs(ABmp: TBGRABitmap; Y: Integer): TIntegerDynArray;
var
  x, n: Integer;
begin
  Result := nil;
  n := 0;
  for x := 0 to ABmp.Width - 1 do
    if IsLine(ABmp, x, Y) then
    begin
      Inc(n);
      SetLength(Result, n);
      Result[n - 1] := x;
    end;
end;

function TTreeViewLinesTest.LineCount(ABmp: TBGRABitmap): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
      if IsLine(ABmp, x, y) then Inc(Result);
end;

function TTreeViewLinesTest.Column(ABmp: TBGRABitmap; X, AFromY, AToY: Integer): string;
var
  y: Integer;
begin
  Result := '';
  for y := AFromY to AToY - 1 do
    if IsLine(ABmp, X, y) then Result := Result + '#' else Result := Result + '.';
end;

procedure TTreeViewLinesTest.CheckXs(const AMsg: string; const AExpected: array of Integer;
  const AActual: TIntegerDynArray);
var
  i: Integer;
  e, a: string;
begin
  e := '';
  for i := 0 to High(AExpected) do e := e + IntToStr(AExpected[i]) + ' ';
  a := '';
  for i := 0 to High(AActual) do a := a + IntToStr(AActual[i]) + ' ';
  AssertEquals(AMsg, e, a);
end;

procedure TTreeViewLinesTest.UseColumns;
var
  c: TTyColumn;
begin
  c := FTree.Header.Columns.Add as TTyColumn;
  c.Text := 'Name';
  c.Width := 250;
end;

procedure TTreeViewLinesTest.TestTheDefaultDrawsGuidesThatDoNotReachTheExpander;
var
  bmp: TBGRABitmap;
  xAlpha, xA1, y: Integer;
begin
  FTree.StyleOverride := RED;
  xAlpha := SlotX(0);
  xA1 := SlotX(1);
  bmp := Render;
  try
    CheckXs('A1a''s row: a guide under each ancestor''s expander, none at its own level',
      [xAlpha, xA1], LineXs(bmp, RowTop(2) + 2));
    for y := RowTop(1) to RowTop(2) - 1 do
      AssertFalse(Format('A1''s own expander has no line through it (y=%d)', [y]),
        IsLine(bmp, xA1, y));
    CheckXs('A1''s row has only Alpha''s guide, and no stub', [xAlpha],
      LineXs(bmp, RowTop(1) + RowH(1) div 2));
    AssertEquals('Alpha''s guide runs the full height of each descendant''s row',
      StringOfChar('#', RowTop(4) - RowTop(1)), Column(bmp, xAlpha, RowTop(1), RowTop(4)));
    AssertEquals('nothing on Alpha''s own row or Beta''s', '',
      StringReplace(Column(bmp, xAlpha, RowTop(0), RowTop(1)) + Column(bmp, xAlpha, RowTop(4),
        RowTop(4) + RowH(0)), '.', '', [rfReplaceAll]));
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestClassicDrawsTheConnectors;
var
  bmp: TBGRABitmap;
  xAlpha, xA1, mid: Integer;
begin
  FTree.StyleOverride := RED + '--treeview-lines: classic';
  xAlpha := SlotX(0);
  xA1 := SlotX(1);
  bmp := Render;
  try
    CheckXs('A1a''s row: the ancestors'' lines and its own elbow',
      [xAlpha, xA1, xA1 + 16], LineXs(bmp, RowTop(2) + 2));
    AssertTrue('A1''s own connector runs through its expander slot',
      IsLine(bmp, xA1, RowTop(1) + 1));
    mid := RowTop(1) + RowH(1) div 2;
    AssertTrue('and its stub runs right from there', IsLine(bmp, xA1 + 5, mid));
    AssertTrue('Alpha''s line runs on through A1''s row, Beta being below',
      IsLine(bmp, xAlpha, RowTop(1) + 1));
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestAGuideRunsUnderALastChildToo;
var
  bmp: TBGRABitmap;
  xAlpha, xA2: Integer;
begin
  { A2 is Alpha's last child: below it nothing at its level goes on, which is where the
    classic line stops and a guide does not }
  FA2.Expanded := True;   { rows: 0 Alpha, 1 A1, 2 A1a, 3 A2, 4 A2a, 5 Beta }
  xAlpha := SlotX(0);
  xA2 := SlotX(3);
  FTree.StyleOverride := RED;
  bmp := Render;
  try
    CheckXs('guides: one under A2 as well as under Alpha', [xAlpha, xA2],
      LineXs(bmp, RowTop(4) + 2));
  finally
    bmp.Free;
  end;
  FTree.StyleOverride := RED + '--treeview-lines: classic';
  bmp := Render;
  try
    CheckXs('classic: Alpha''s line and A2a''s own elbow, nothing under A2',
      [xAlpha, xA2 + 16], LineXs(bmp, RowTop(4) + 2));
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestNoneDrawsNoLines;
var
  bmp: TBGRABitmap;
begin
  FTree.StyleOverride := RED + '--treeview-lines: classic';
  bmp := Render;
  try
    AssertTrue('precondition: the colour finds the lines', LineCount(bmp) > 0);
  finally
    bmp.Free;
  end;
  FTree.StyleOverride := RED + '--treeview-lines: none';
  bmp := Render;
  try
    AssertEquals('none: not one line pixel', 0, LineCount(bmp));
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestShowTreeLinesIsTheMasterSwitch;
var
  bmp: TBGRABitmap;
begin
  FTree.StyleOverride := RED + '--treeview-lines: classic';
  bmp := Render;
  try
    AssertTrue('precondition: the override draws lines', LineCount(bmp) > 0);
  finally
    bmp.Free;
  end;
  FTree.ShowTreeLines := False;
  bmp := Render;
  try
    AssertEquals('ShowTreeLines False wins over classic', 0, LineCount(bmp));
  finally
    bmp.Free;
  end;
  FTree.StyleOverride := RED;
  bmp := Render;
  try
    AssertEquals('...and over the default guides', 0, LineCount(bmp));
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestTheThemeChoosesForEveryTree;
var
  bmp: TBGRABitmap;
  xA1: Integer;
begin
  xA1 := SlotX(1);
  FCtl.StyleOverride := ':root { --treeview-lines: classic; --treeview-lines-color: #ff0000; }';
  bmp := Render;
  try
    AssertTrue('the theme''s colour and the theme''s classic connectors',
      IsLine(bmp, xA1, RowTop(1) + 1));
  finally
    bmp.Free;
  end;
  FTree.StyleOverride := '--treeview-lines: guides';
  bmp := Render;
  try
    AssertFalse('the tree''s own choice wins', IsLine(bmp, xA1, RowTop(1) + 1));
    AssertTrue('and the theme''s colour still applies', LineCount(bmp) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestTheColourIsTheBorderByDefault;
var
  bmp: TBGRABitmap;
  p, want: TBGRAPixel;
begin
  bmp := Render;
  try
    p := bmp.GetPixel(SlotX(0), RowTop(2) + 2);
    want := TyColorToBGRA(FTree.XBorder);
    AssertEquals('red', want.red, p.red);
    AssertEquals('green', want.green, p.green);
    AssertEquals('blue', want.blue, p.blue);
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestDottedAlternates;
var
  bmp: TBGRABitmap;
  col: string;
  i: Integer;
begin
  FTree.StyleOverride := RED + '--treeview-lines-style: dotted';
  bmp := Render;
  try
    col := Column(bmp, SlotX(0), RowTop(1), RowTop(4));
    AssertTrue('precondition: there is a line', Pos('#', col) > 0);
    for i := 2 to Length(col) do
      AssertTrue(Format('dot, gap, dot... (at %d: %s)', [i, col]), col[i] <> col[i - 1]);
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestADashListSetsTheRuns;
var
  bmp: TBGRABitmap;
  col: string;
  i, len: Integer;
  runs: string;
begin
  FTree.StyleOverride := RED + '--treeview-lines-style: 5px 3px';
  bmp := Render;
  try
    col := Column(bmp, SlotX(0), RowTop(1), RowTop(4));
  finally
    bmp.Free;
  end;
  { the runs strictly inside the column: the first and the last may be cut }
  runs := '';
  len := 1;
  for i := 2 to Length(col) do
    if col[i] = col[i - 1] then Inc(len)
    else
    begin
      runs := runs + col[i - 1] + IntToStr(len) + ' ';
      len := 1;
    end;
  Delete(runs, 1, Pos(' ', runs));
  AssertTrue('precondition: several dashes: ' + runs, Length(runs) > 20);
  while runs <> '' do
  begin
    if runs[1] = '#' then
      AssertEquals('a dash is 5 px: ' + col, '#5', Copy(runs, 1, Pos(' ', runs) - 1))
    else
      AssertEquals('a gap is 3 px: ' + col, '.3', Copy(runs, 1, Pos(' ', runs) - 1));
    Delete(runs, 1, Pos(' ', runs));
  end;
  FTree.StyleOverride := RED + '--treeview-lines-style: 4px';
  bmp := Render;
  try
    col := Column(bmp, SlotX(0), RowTop(1), RowTop(4));
    AssertTrue('one length: a 4 px dash: ' + col, Pos('.####.', col) > 0);
    AssertTrue('...and as long a gap: ' + col, Pos('#....#', col) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestThePatternRunsOnAcrossRows;
var
  bmp: TBGRABitmap;
  col: string;
  i: Integer;
begin
  AssertTrue('precondition: a row is not a whole number of periods', RowH(1) mod 8 <> 0);
  FTree.StyleOverride := RED + '--treeview-lines-style: 5px 3px';
  bmp := Render;
  try
    col := Column(bmp, SlotX(0), RowTop(1), RowTop(4));
  finally
    bmp.Free;
  end;
  AssertTrue('precondition: dashes and gaps: ' + col, (Pos('#', col) > 0) and (Pos('.', col) > 0));
  for i := 1 to Length(col) - 8 do
    AssertEquals(Format('one pattern down three rows, period 8 (at %d): %s', [i, col]),
      col[i], col[i + 8]);
end;

procedure TTreeViewLinesTest.TestTheCornerSharesThePhase;
var
  bmp: TBGRABitmap;
  x, y, parity: Integer;
begin
  FTree.StyleOverride := RED + '--treeview-lines: classic; --treeview-lines-style: dotted';
  bmp := Render;
  try
    { right of the chevron, which is drawn over the junction }
    AssertTrue('precondition: the stubs are drawn',
      IsLine(bmp, SlotX(1) + 6, RowTop(1) + RowH(1) div 2)
      or IsLine(bmp, SlotX(1) + 5, RowTop(1) + RowH(1) div 2));
    parity := -1;
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
        if IsLine(bmp, x, y) then
        begin
          if parity < 0 then parity := (x + y) and 1;
          AssertEquals(Format('every dot on one checkerboard, verticals and stubs alike (%d,%d)',
            [x, y]), parity, (x + y) and 1);
        end;
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestThePatternMovesWithTheContent;
var
  f: TForm;
  bmp: TBGRABitmap;
  before, after: string;
  x, top, d: Integer;
begin
  f := TForm.CreateNew(nil);
  try
    FTree.Parent := f;
    FTree.SetBounds(0, 0, 300, 60);   { three rows show, so it scrolls }
    FTree.StyleOverride := RED + '--treeview-lines-style: 5px 3px';
    x := SlotX(0);
    top := RowTop(1);
    bmp := Render;
    try
      before := Column(bmp, x, top, FTree.ClientHeight - 4);
    finally
      bmp.Free;
    end;
    AssertTrue('precondition: dashes and gaps: ' + before, (Pos('#', before) > 0) and (Pos('.', before) > 0));
    AssertTrue('precondition: it can scroll', (FTree.VScroll <> nil) and FTree.VScroll.Visible);
    FTree.VScroll.Position := 3;
    d := -FTree.OffsetY;
    AssertTrue('precondition: scrolled by a part of a period', (d > 0) and (d mod 8 <> 0));
    bmp := Render;
    try
      after := Column(bmp, x, top - d, FTree.ClientHeight - 4 - d);
    finally
      bmp.Free;
    end;
    AssertEquals('the same pixels of content are dashes, wherever they are on screen',
      before, after);
  finally
    FTree.Parent := nil;
    f.Free;
  end;
end;

procedure TTreeViewLinesTest.TestTheBoxDrawsPlusAndMinusOverTheJunction;
var
  bmp: TBGRABitmap;
  x, mid, mid3: Integer;
begin
  FTree.StyleOverride := RED + '--treeview-lines: classic; --treeview-expander: plus-minus';
  x := SlotX(1);
  mid := RowTop(1) + RowH(1) div 2;
  mid3 := RowTop(3) + RowH(3) div 2;
  bmp := Render;
  try
    AssertTrue('the box''s left side, in the line colour', IsLine(bmp, x - 4, mid));
    AssertTrue('its right side', IsLine(bmp, x + 4, mid));
    AssertTrue('its top', IsLine(bmp, x, mid - 4));
    AssertTrue('its bottom', IsLine(bmp, x, mid + 4));
    AssertTrue('A1 is expanded: a minus', IsInk(bmp, x - 2, mid) and IsInk(bmp, x + 2, mid));
    AssertFalse('no bar across it', IsInk(bmp, x, mid - 2) or IsLine(bmp, x, mid - 2));
    AssertTrue('the line runs up to the box', IsLine(bmp, x, mid - 6));
    AssertTrue('A2 is collapsed: a plus', IsInk(bmp, x - 2, mid3) and IsInk(bmp, x, mid3 - 2)
      and IsInk(bmp, x, mid3 + 2));
    AssertFalse('the stub stops at the box', IsLine(bmp, x + 3, mid3));
    AssertTrue('the stub goes on outside it', IsLine(bmp, x + 5, mid3));
  finally
    bmp.Free;
  end;
  FTree.StyleOverride := RED + '--treeview-lines: classic';
  bmp := Render;
  try
    AssertFalse('the chevron draws no box', IsLine(bmp, x - 4, mid));
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestTheDashScalesWithTheDpi;
var
  bmp: TBGRABitmap;
  col: string;
  x, i, len: Integer;
begin
  FTree.StyleOverride := RED + '--treeview-lines-style: dotted';
  bmp := TBGRABitmap.Create(FTree.Width, FTree.Height);
  try
    FTree.XRender(bmp, 192);
    col := '';
    for x := 0 to bmp.Width - 1 do
    begin
      col := Column(bmp, x, 0, bmp.Height);
      if Pos('#', col) > 0 then Break;
    end;
  finally
    bmp.Free;
  end;
  AssertTrue('precondition: a line at 192 dpi', Pos('#', col) > 0);
  { the runs between the first dot and the last }
  col := Copy(col, Pos('#', col), MaxInt);
  while (col <> '') and (col[Length(col)] = '.') do Delete(col, Length(col), 1);
  AssertTrue('precondition: several dots: ' + col, Length(col) > 12);
  len := 1;
  for i := 2 to Length(col) do
    if col[i] = col[i - 1] then Inc(len)
    else
    begin
      AssertEquals('a 1px dot is 2 px at 192 dpi, and so is its gap: ' + col, 2, len);
      len := 1;
    end;
end;

procedure TTreeViewLinesTest.TestALowRowGetsASmallerBox;
var
  bmp: TBGRABitmap;
  x, mid: Integer;
begin
  FTree.DefaultNodeHeight := 9;
  FTree.StyleOverride := RED + '--treeview-lines: none; --treeview-expander: plus-minus';
  x := SlotX(1);
  mid := RowTop(1) + RowH(1) div 2;
  bmp := Render;
  try
    AssertTrue('the box fits the 9 px row: its side is 7', IsLine(bmp, x - 3, mid)
      and IsLine(bmp, x + 3, mid) and IsLine(bmp, x, mid - 3));
    AssertFalse('not the 9 px box of a taller row', IsLine(bmp, x - 4, mid));
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestTheBoxIsHitLikeTheChevron;
var
  a, b: Integer;
  part: TTyTreeHitPart;
begin
  a := FirstX(hpButton, 1);
  b := LastX(hpButton, 1);
  FTree.StyleOverride := '--treeview-expander: plus-minus';
  AssertEquals('the slot starts where it did', a, FirstX(hpButton, 1));
  AssertEquals('and ends where it did', b, LastX(hpButton, 1));
  AssertTrue('the box''s centre is the button',
    FTree.GetNodeAtPoint(SlotX(1), RowTop(1) + RowH(1) div 2, part) <> nil);
  AssertTrue('the button part', part = hpButton);
end;

procedure TTreeViewLinesTest.TestAColumnTreeDrawsTheSame;
var
  bmp: TBGRABitmap;
  guides, classic: TIntegerDynArray;
  xA1, mid: Integer;
begin
  FTree.StyleOverride := RED;
  bmp := Render;
  try
    guides := LineXs(bmp, RowTop(2) + 2);
  finally
    bmp.Free;
  end;
  FTree.StyleOverride := RED + '--treeview-lines: classic';
  bmp := Render;
  try
    classic := LineXs(bmp, RowTop(2) + 2);
  finally
    bmp.Free;
  end;
  UseColumns;
  FTree.StyleOverride := RED;
  bmp := Render;
  try
    CheckXs('guides', guides, LineXs(bmp, RowTop(2) + 2));
  finally
    bmp.Free;
  end;
  FTree.StyleOverride := RED + '--treeview-lines: classic; --treeview-expander: plus-minus';
  xA1 := SlotX(1);
  mid := RowTop(1) + RowH(1) div 2;
  bmp := Render;
  try
    CheckXs('classic', classic, LineXs(bmp, RowTop(2) + 2));
    AssertTrue('and the box', IsLine(bmp, xA1 - 4, mid) and IsLine(bmp, xA1 + 4, mid));
  finally
    bmp.Free;
  end;
  FTree.StyleOverride := RED + '--treeview-lines: none';
  bmp := Render;
  try
    AssertEquals('none', 0, LineCount(bmp));
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestRightToLeftKeepsTheLinesInTheSlots;
var
  bmp: TBGRABitmap;
  xs: TIntegerDynArray;
  a0, b0, a1, b1, mid: Integer;
begin
  FTree.BiDiMode := bdRightToLeft;
  FTree.StyleOverride := RED;
  a0 := FirstX(hpButton, 0); b0 := LastX(hpButton, 0);
  a1 := FirstX(hpButton, 1); b1 := LastX(hpButton, 1);
  AssertTrue('precondition: mirrored, A1''s slot is left of Alpha''s', b1 < a0);
  bmp := Render;
  try
    xs := LineXs(bmp, RowTop(2) + 2);
  finally
    bmp.Free;
  end;
  AssertEquals('two guides on A1a''s row', 2, Length(xs));
  AssertTrue('A1''s guide in A1''s slot', (xs[0] >= a1) and (xs[0] <= b1));
  AssertTrue('Alpha''s guide in Alpha''s slot', (xs[1] >= a0) and (xs[1] <= b0));
  { mirrored, A2's stub runs left from its box, and stops at it }
  FTree.StyleOverride := RED + '--treeview-lines: classic; --treeview-expander: plus-minus';
  bmp := Render;
  try
    xs := LineXs(bmp, RowTop(3) + 1);
    AssertEquals('precondition: A2''s own line and Alpha''s', 2, Length(xs));
    mid := RowTop(3) + RowH(3) div 2;
    AssertTrue('the stub, left of the box', IsLine(bmp, xs[0] - 5, mid));
    AssertFalse('not inside it', IsLine(bmp, xs[0] - 3, mid));
    AssertFalse('nor right of it', IsLine(bmp, xs[0] + 6, mid));
  finally
    bmp.Free;
  end;
end;

procedure TTreeViewLinesTest.TestClassicSkinsPairBoxesWithDottedConnectors;
var
  names: TStringArray;
  i: Integer;
  n: string;
begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  AssertTrue('precondition: the pack is there', Length(names) > 2);
  for i := 0 to High(names) do
  begin
    n := names[i];
    FCtl.ThemeName := n;
    if SameText(n, 'classic') or SameText(n, 'xp') then
    begin
      AssertEquals(n + ': lines', 'classic', FTree.StyleToken('--treeview-lines', ''));
      AssertEquals(n + ': style', 'dotted', FTree.StyleToken('--treeview-lines-style', ''));
      AssertEquals(n + ': expander', 'plus-minus', FTree.StyleToken('--treeview-expander', ''));
    end
    else
    begin
      AssertEquals(n + ': lines', 'guides', FTree.StyleToken('--treeview-lines', 'guides'));
      AssertEquals(n + ': style', 'solid', FTree.StyleToken('--treeview-lines-style', 'solid'));
      AssertEquals(n + ': expander', 'chevron', FTree.StyleToken('--treeview-expander', 'chevron'));
    end;
  end;
end;

initialization
  RegisterTest(TTreeViewLinesTest);
end.
