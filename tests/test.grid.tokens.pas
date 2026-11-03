unit test.grid.tokens;

{ #197: every part of the table can be themed. Each test reads pixels: a token nobody draws by is
  the failure this guards against, and only the picture can tell. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes, LMessages,
  tyControls.Types, tyControls.Controller, tyControls.Columns, tyControls.Grid, tyControls.Grid.Layout,
  tyControls.ListView,
  tyControls.ListView.Layout, tyControls.TreeView, tyControls.Panel;

type
  TGridTokensTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FBmp: TBitmap;
    FRe: TBGRABitmap;
    procedure Theme(const ACss: string);
    function MakeGrid(AHeader: Boolean = True): TTyStringGrid;
    procedure Render(AGrid: TTyStringGrid);
    procedure RenderList(AList: TTyListView);
    function Px(X, Y: Integer): TBGRAPixel;
    function IsColor(X, Y: Integer; R, G, B: Byte): Boolean;
    function CountRow(Y, X0, X1: Integer; R, G, B: Byte): Integer;
    function CountCol(X, Y0, Y1: Integer; R, G, B: Byte): Integer;
    function CountBox(const ABox: TRect; R, G, B: Byte): Integer;
    function FirstColor(const ABox: TRect; R, G, B: Byte): TPoint;
    function Reddish(const ABox: TRect): Integer;
    procedure CheckScrollAgainstAFullRepaint(AGrid: TTyStringGrid; ADy: Integer; const AWhat: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the frame }
    procedure TestTheHeaderDoesNotCoverTheFrame;
    procedure TestTheHeaderKeepsToTheRoundedCorners;
    procedure TestARowFillDoesNotCoverTheFrame;
    procedure TestAnEmptyGridsFrameIsAPlainFrame;
    procedure TestAScrollKeepsTheBottomBorderAndCorners;
    procedure TestAListViewHeaderDoesNotCoverTheFrame;
    { grid lines }
    procedure TestAWidthOfZeroHidesOneDirection;
    procedure TestTheLinesHaveTheirOwnWidthAndColour;
    procedure TestALineCanBeDashed;
    procedure TestATranslucentLineBlendsAndLeavesNoHole;
    procedure TestTheHostsLineStyleBeatsASkinThatHidesThatDirection;
    procedure TestTheHostsLineWidthBeatsTheTheme;
    procedure TestLinesCanStopWithTheColumns;
    procedure TestOneGridTakesTheTokensInItsOverride;
    procedure TestAScrollWithDashedLinesMatchesAFullRepaint;
    { the header }
    procedure TestTheSeparatorHasWidthHeightColourAndStyle;
    procedure TestASeparatorOfZeroWidthIsGone;
    procedure TestTheRuleUnderTheHeader;
    procedure TestThePointerOverTheTableDoesNotLightEverySection;
    procedure TestTheSectionUnderThePointerLights;
    procedure TestASortedAndAFilteredSectionHaveTheirLook;
    procedure TestHeaderTextPadding;
    procedure TestOneGridsHeaderFromItsOverride;
    procedure TestABackgroundOfNoneInAnOverride;
    procedure TestRaisedSections;
    { the sort mark }
    procedure TestTheSortMarkCanBeHidden;
    procedure TestTheSortMarksColourAndShape;
    procedure TestTheUnsortedHint;
    procedure TestTheListViewHasTheSameMark;
    { rows and cells }
    procedure TestHoverCanLightARowAColumnOrNothing;
    procedure TestSelectedAndHovered;
    procedure TestASortedColumnsBody;
    procedure TestTheSelectionFrameIsOverTheGridLines;
    procedure TestTheFillHandleSize;
    procedure TestTheFocusRing;
    { bands }
    procedure TestTheFrozenEdge;
    procedure TestTheFrozenShadowOnlyOnceScrolled;
    procedure TestTheFootersRule;
    procedure TestTheCursorsRowNumber;
    { the theme engine }
    procedure TestAVarMayNameNoneOrAnotherVar;
  end;

implementation

type
  TGridAccess = class(TTyStringGrid)
  public
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure HoverAt(X, Y: Integer);
    procedure EnterControl;
    function Metrics: TTyGridMetrics;
    function ColLeft(ACol: Integer): Integer;
    procedure ScrollTo(AValue: Integer);
    procedure ScrollBy(ADy: Integer);
    procedure ForgetSurface;
    function FastFrames: Integer;
  end;

  TListAccess = class(TTyListView)
  public
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TPanelAccess = class(TTyPanel)
  public
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

procedure TGridAccess.DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TGridAccess.HoverAt(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TGridAccess.EnterControl;
var
  msg: TLMessage;
begin
  msg := Default(TLMessage);
  msg.Msg := CM_MOUSEENTER;
  Dispatch(msg);
end;

function TGridAccess.Metrics: TTyGridMetrics;
begin
  Result := GridMetrics;
end;

function TGridAccess.ColLeft(ACol: Integer): Integer;
begin
  Result := ColumnLeftPx(ACol);
end;

procedure TGridAccess.ScrollTo(AValue: Integer);
begin
  ScrollY := AValue;
end;

procedure TGridAccess.ScrollBy(ADy: Integer);
begin
  ScrollVerticallyBy(ADy);
end;

procedure TGridAccess.ForgetSurface;
begin
  InvalidateSurface;
end;

function TGridAccess.FastFrames: Integer;
begin
  Result := FastScrollFrames;
end;

procedure TListAccess.DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TPanelAccess.DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

const
  BASE_THEME =
    'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
    'TyGridLine { background: #C0C0C0; }' +
    'TyGridHeader { background: #E0E0E0; color: #000000; }' +
    'TyGridHeaderSection { background: none; color: #000000; }';
  W = 400;
  H = 300;

procedure TGridTokensTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 600, 500);
  FBmp := TBitmap.Create;
  FBmp.PixelFormat := pf32bit;
  FBmp.SetSize(W, H);
end;

procedure TGridTokensTest.TearDown;
begin
  FreeAndNil(FRe);
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

procedure TGridTokensTest.Theme(const ACss: string);
begin
  FCtl.LoadThemeCss(BASE_THEME + ACss);
end;

function TGridTokensTest.MakeGrid(AHeader: Boolean): TTyStringGrid;
var
  i: Integer;
  c: TTyColumn;
begin
  Result := TGridAccess.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, W, H);
  for i := 0 to 3 do
  begin
    c := Result.Header.Columns.Add as TTyColumn;
    c.Width := 80;
  end;
  if not AHeader then
    Result.Header.Options := Result.Header.Options - [hoVisible];
  Result.Header.Height := 24;
  Result.DefaultRowHeight := 20;
  Result.RowCount := 6;
  { No selection frame or cursor fill to step around unless a test asks for them. }
  Result.ShowFocusCell := False;
  Result.SelectionMode := gsmRow;
end;

procedure TGridTokensTest.Render(AGrid: TTyStringGrid);
begin
  FBmp.Canvas.Brush.Color := clWhite;
  FBmp.Canvas.FillRect(Rect(0, 0, W, H));
  TGridAccess(AGrid).DoRender(FBmp.Canvas, Rect(0, 0, W, H), 96);
  FreeAndNil(FRe);
  FRe := TBGRABitmap.Create(FBmp);
end;

procedure TGridTokensTest.RenderList(AList: TTyListView);
begin
  FBmp.Canvas.Brush.Color := clWhite;
  FBmp.Canvas.FillRect(Rect(0, 0, W, H));
  TListAccess(AList).DoRender(FBmp.Canvas, Rect(0, 0, W, H), 96);
  FreeAndNil(FRe);
  FRe := TBGRABitmap.Create(FBmp);
end;

function TGridTokensTest.Px(X, Y: Integer): TBGRAPixel;
begin
  Result := FRe.GetPixel(X, Y);
end;

function TGridTokensTest.IsColor(X, Y: Integer; R, G, B: Byte): Boolean;
var
  c: TBGRAPixel;
begin
  c := Px(X, Y);
  Result := (c.red = R) and (c.green = G) and (c.blue = B);
end;

function TGridTokensTest.CountRow(Y, X0, X1: Integer; R, G, B: Byte): Integer;
var
  x: Integer;
begin
  Result := 0;
  for x := X0 to X1 do
    if IsColor(x, Y, R, G, B) then Inc(Result);
end;

function TGridTokensTest.CountCol(X, Y0, Y1: Integer; R, G, B: Byte): Integer;
var
  y: Integer;
begin
  Result := 0;
  for y := Y0 to Y1 do
    if IsColor(X, y, R, G, B) then Inc(Result);
end;

function TGridTokensTest.Reddish(const ABox: TRect): Integer;
var
  x, y: Integer;
  c: TBGRAPixel;
begin
  { A chevron is antialiased and drawn lighter than its ink: red against a grey band, not #FF0000. }
  Result := 0;
  for y := ABox.Top to ABox.Bottom - 1 do
    for x := ABox.Left to ABox.Right - 1 do
    begin
      c := Px(x, y);
      if c.red > c.green + 60 then Inc(Result);
    end;
end;

function TGridTokensTest.CountBox(const ABox: TRect; R, G, B: Byte): Integer;
var
  y: Integer;
begin
  Result := 0;
  for y := ABox.Top to ABox.Bottom - 1 do
    Inc(Result, CountRow(y, ABox.Left, ABox.Right - 1, R, G, B));
end;

function TGridTokensTest.FirstColor(const ABox: TRect; R, G, B: Byte): TPoint;
var
  x, y: Integer;
begin
  for x := ABox.Left to ABox.Right - 1 do
    for y := ABox.Top to ABox.Bottom - 1 do
      if IsColor(x, y, R, G, B) then Exit(Point(x, y));
  Result := Point(-1, -1);
end;

{ ---- the frame ---- }

procedure TGridTokensTest.TestTheHeaderDoesNotCoverTheFrame;
var
  g: TTyStringGrid;
begin
  Theme('TyGrid { border-width: 1px; border-color: #0000FF; }');
  g := MakeGrid;
  Render(g);
  { The band runs from y = 0 and went over the frame's top edge and the sides beside it. }
  AssertTrue('the top border is over the header', IsColor(150, 0, 0, 0, 255));
  AssertTrue('the left border is beside the header', IsColor(0, 12, 0, 0, 255));
  AssertTrue('and under it, the header', IsColor(150, 1, $E0, $E0, $E0));
end;

procedure TGridTokensTest.TestTheHeaderKeepsToTheRoundedCorners;
var
  g: TTyStringGrid;
begin
  Theme('TyGrid { border-width: 1px; border-color: #0000FF; border-radius: 8px; }' +
    'TyGridHeader { background: #FF0000; }');
  g := MakeGrid;
  Render(g);
  { Outside the arc the band's square corner showed. }
  AssertFalse('the corner pixel is not the band''s', IsColor(0, 0, 255, 0, 0));
  AssertFalse('nor the one inside it', IsColor(1, 1, 255, 0, 0));
  AssertTrue('the corner shows what lay under the control', Px(0, 0).red > 200);
  AssertTrue('and it does on the right', Px(W - 1, 0).green > 200);
  AssertTrue('inside the arc the band goes on', IsColor(4, 4, 255, 0, 0));
end;

procedure TGridTokensTest.TestARowFillDoesNotCoverTheFrame;
var
  g: TTyStringGrid;
  y: Integer;
begin
  Theme('TyGrid { border-width: 1px; border-color: #0000FF; }' +
    'TyGridCell:selected { background: #00FF00; }');
  g := MakeGrid;
  g.Row := 1;
  Render(g);
  y := 24 + 20 + 10;
  AssertTrue('precondition: the row is selected', IsColor(40, y, 0, 255, 0));
  AssertTrue('its fill stops at the left border', IsColor(0, y, 0, 0, 255));
end;

procedure TGridTokensTest.CheckScrollAgainstAFullRepaint(AGrid: TTyStringGrid; ADy: Integer; const AWhat: string);
var
  g: TGridAccess;
  moved: TBGRABitmap;
  x, y, diff, before: Integer;
  a, b: TBGRAPixel;
begin
  g := TGridAccess(AGrid);
  before := g.FastFrames;
  g.ScrollBy(ADy);
  Render(g);
  AssertTrue(AWhat + ': precondition: the scroll took the fast path', g.FastFrames > before);
  moved := TBGRABitmap.Create(FBmp);
  try
    g.ForgetSurface;
    Render(g);
    diff := 0;
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do
      begin
        a := Px(x, y);
        b := moved.GetPixel(x, y);
        if (a.red <> b.red) or (a.green <> b.green) or (a.blue <> b.blue) then Inc(diff);
      end;
    AssertEquals(AWhat, 0, diff);
  finally
    moved.Free;
  end;
end;

procedure TGridTokensTest.TestAnEmptyGridsFrameIsAPlainFrame;
const
  RULE = '{ background: #F0F0F0; color: #000000; border-width: 2px; border-color: #0000FF; border-radius: 8px; padding: 0px; }';
var
  g: TTyStringGrid;
  pn: TPanelAccess;
  plain: TBGRABitmap;
  x, y, diff: Integer;
  a, b: TBGRAPixel;
begin
  { The frame goes under the content and back over it, and where the content did not touch it has
    to come out as if it had never been apart: the fill cut once, the border stroked once. }
  FCtl.LoadThemeCss('TyGrid ' + RULE + ' TyPanel ' + RULE);
  pn := TPanelAccess.Create(FForm);
  pn.Parent := FForm;
  pn.Controller := FCtl;
  pn.SetBounds(0, 0, W, H);
  FBmp.Canvas.Brush.Color := clWhite;
  FBmp.Canvas.FillRect(Rect(0, 0, W, H));
  pn.DoRender(FBmp.Canvas, Rect(0, 0, W, H), 96);
  plain := TBGRABitmap.Create(FBmp);
  try
    g := MakeGrid(False);
    g.GridLineStyle := glsNone;
    g.RowCount := 0;
    Render(g);
    diff := 0;
    for y := 0 to 11 do
      for x := 0 to 11 do
      begin
        a := Px(x, y);
        b := plain.GetPixel(x, y);
        if (Abs(a.red - b.red) > 1) or (Abs(a.green - b.green) > 1) or (Abs(a.blue - b.blue) > 1) then
          Inc(diff);
      end;
    AssertEquals('the top left corner, pixel for pixel', 0, diff);
    AssertTrue('and the corner is there to compare', plain.GetPixel(5, 1).blue > plain.GetPixel(5, 1).red);
  finally
    plain.Free;
  end;
end;

procedure TGridTokensTest.TestAScrollKeepsTheBottomBorderAndCorners;
var
  g: TTyStringGrid;
begin
  { No header and no H bar: the frame's top and bottom edges and all four corners lie across rows
    that scroll. Moved with the rest, the bottom border would stay behind as a line. }
  Theme('TyGrid { border-width: 2px; border-color: #0000FF; border-radius: 8px; }' +
    'TyGridCellAlt { background: #F0F0D0; }');
  g := MakeGrid(False);
  g.RowCount := 200;
  g.AlternateRows := True;
  Render(g);
  CheckScrollAgainstAFullRepaint(g, 7, 'down by less than a row');
  CheckScrollAgainstAFullRepaint(g, 45, 'down by a few rows');
  CheckScrollAgainstAFullRepaint(g, -13, 'up');
  { and with a header in the top band }
  g.Header.Options := g.Header.Options + [hoVisible];
  TGridAccess(g).ForgetSurface;
  Render(g);
  CheckScrollAgainstAFullRepaint(g, 9, 'with a header, down');
  CheckScrollAgainstAFullRepaint(g, -5, 'with a header, up');
end;

procedure TGridTokensTest.TestAListViewHeaderDoesNotCoverTheFrame;
var
  l: TTyListView;
  c: TTyColumn;
begin
  FCtl.LoadThemeCss('TyListView { background: #FFFFFF; border-width: 1px; border-color: #0000FF; border-radius: 8px; }' +
    'TyListViewHeader { background: #FF0000; color: #000000; }');
  l := TListAccess.Create(FForm);
  l.Parent := FForm;
  l.Controller := FCtl;
  l.SetBounds(0, 0, W, H);
  l.ViewStyle := lvsReport;
  c := l.Header.Columns.Add as TTyColumn;
  c.Width := 300;
  RenderList(l);
  AssertTrue('the top border is over the band', IsColor(150, 0, 0, 0, 255));
  AssertFalse('the band keeps to the rounded corner', IsColor(0, 0, 255, 0, 0));
  AssertTrue('inside the arc the band goes on', IsColor(150, 5, 255, 0, 0));
end;

{ ---- grid lines ---- }

procedure TGridTokensTest.TestAWidthOfZeroHidesOneDirection;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-line-v-width: 0; }');
  g := MakeGrid(False);
  Render(g);
  AssertEquals('no vertical line in a row''s middle', 0, CountRow(10, 0, 330, $C0, $C0, $C0));
  AssertTrue('the horizontal lines stay', CountRow(19, 0, 100, $C0, $C0, $C0) > 90);
  Theme(':root { --grid-line-h-width: 0; }');
  Render(g);
  AssertEquals('no horizontal line', 0, CountRow(19, 2, 70, $C0, $C0, $C0));
  AssertTrue('the vertical lines stay', IsColor(79, 10, $C0, $C0, $C0));
end;

procedure TGridTokensTest.TestTheLinesHaveTheirOwnWidthAndColour;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-line-h-width: 3px; --grid-line-h-color: #FF0000; --grid-line-v-color: #00FF00; }');
  g := MakeGrid(False);
  Render(g);
  AssertEquals('a horizontal line 3 thick, on its boundary', 3, CountCol(40, 17, 22, 255, 0, 0));
  AssertTrue('the vertical line has its own colour', IsColor(79, 10, 0, 255, 0));
end;

procedure TGridTokensTest.TestALineCanBeDashed;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-line-h-style: 2px 3px; --grid-line-v-style: dotted; --grid-line-v-color: #00FF00; }');
  g := MakeGrid(False);
  Render(g);
  { 2 on, 3 off from x = 0: 40% of the row, a little over at the ends. }
  AssertEquals('a dashed line, 2 on 3 off', 20, CountRow(19, 0, 49, $C0, $C0, $C0));
  AssertTrue('on', IsColor(5, 19, $C0, $C0, $C0));
  AssertFalse('off', IsColor(7, 19, $C0, $C0, $C0));
  AssertEquals('a dotted line: every other pixel in a row of 20', 9, CountCol(79, 0, 18, 0, 255, 0) - 1);
end;

procedure TGridTokensTest.TestATranslucentLineBlendsAndLeavesNoHole;
var
  g: TTyStringGrid;
  c: TBGRAPixel;
begin
  Theme('TyGrid { background: #0000FF; } TyGridLine { background: rgba(255, 0, 0, 0.5); }');
  g := MakeGrid(False);
  Render(g);
  c := Px(40, 39);   { row 1's line: row 0 has the cursor, and its fill }
  AssertTrue(Format('the line lies over the grid''s blue: %d,%d,%d', [c.red, c.green, c.blue]),
    (c.red > 60) and (c.blue > 60));
  AssertTrue(Format('and did not write through to the white under the control: %d', [c.green]), c.green < 40);
end;

procedure TGridTokensTest.TestTheHostsLineStyleBeatsASkinThatHidesThatDirection;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-line-v-width: 0; }');
  g := MakeGrid(False);
  g.GridLineStyle := glsVertical;
  Render(g);
  AssertTrue('asked for by the host, shown', IsColor(79, 10, $C0, $C0, $C0));
  AssertEquals('and the other direction is off', 0, CountRow(19, 2, 70, $C0, $C0, $C0));
  g.GridLineStyle := glsNone;
  Render(g);
  AssertFalse('none is none', IsColor(79, 10, $C0, $C0, $C0));
end;

procedure TGridTokensTest.TestTheHostsLineWidthBeatsTheTheme;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-line-h-width: 3px; }');
  g := MakeGrid(False);
  g.GridLineWidth := 2;
  Render(g);
  AssertEquals('the property''s width', 2, CountCol(40, 16, 22, $C0, $C0, $C0));
end;

procedure TGridTokensTest.TestLinesCanStopWithTheColumns;
var
  g: TTyStringGrid;
begin
  Theme('');
  g := MakeGrid(False);
  Render(g);
  AssertTrue('by default a row''s line crosses the empty part', IsColor(360, 19, $C0, $C0, $C0));
  Theme(':root { --grid-line-extend: columns; }');
  Render(g);
  AssertFalse('stopped with the columns', IsColor(360, 19, $C0, $C0, $C0));
  AssertTrue('the columns keep theirs', IsColor(300, 19, $C0, $C0, $C0));
end;

procedure TGridTokensTest.TestOneGridTakesTheTokensInItsOverride;
var
  g: TTyStringGrid;
begin
  Theme('');
  g := MakeGrid(False);
  g.StyleOverride := '--grid-line-v-width: 0; --grid-line-color: #FF0000';
  Render(g);
  AssertFalse('no vertical line on this grid', IsColor(79, 10, 255, 0, 0));
  AssertTrue('its lines have its colour', IsColor(40, 19, 255, 0, 0));
end;

procedure TGridTokensTest.TestAScrollWithDashedLinesMatchesAFullRepaint;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-line-v-style: dashed; --grid-line-h-style: dotted; }');
  g := MakeGrid(False);
  g.RowCount := 200;
  Render(g);
  CheckScrollAgainstAFullRepaint(g, 13, 'the pattern moves with its row');
  CheckScrollAgainstAFullRepaint(g, -7, 'and back');
end;

{ ---- the header ---- }

procedure TGridTokensTest.TestTheSeparatorHasWidthHeightColourAndStyle;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-header-rule-width: 0; --grid-header-separator-width: 2px; --grid-header-separator-height: 50%; }' +
    'TyGridHeader { border-color: #FF0000; }');
  g := MakeGrid;
  Render(g);
  { The band is 24 high and the first column ends at 80. }
  AssertEquals('half the band''s height', 12, CountCol(79, 0, 23, 255, 0, 0));
  AssertTrue('centred', IsColor(79, 12, 255, 0, 0));
  AssertFalse('not at the top', IsColor(79, 2, 255, 0, 0));
  AssertEquals('two pixels wide', 2, CountRow(12, 76, 82, 255, 0, 0));
  g.StyleOverride := '--grid-header-separator-height: 10px; --grid-header-separator-width: 1px';
  Render(g);
  AssertEquals('or in pixels', 10, CountCol(79, 0, 23, 255, 0, 0));
  g.StyleOverride := '--grid-header-separator-width: 1px; --grid-header-separator-style: 1px 1px';
  Render(g);
  AssertEquals('and dotted: half of its 12', 6, CountCol(79, 0, 23, 255, 0, 0));
  g.StyleOverride := '--grid-header-separator-color: #00FF00';
  Render(g);
  AssertTrue('its own colour', CountCol(79, 0, 23, 0, 255, 0) > 0);
end;

procedure TGridTokensTest.TestASeparatorOfZeroWidthIsGone;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-header-rule-width: 0; --grid-header-separator-width: 0; } TyGridHeader { border-color: #FF0000; }');
  g := MakeGrid;
  Render(g);
  AssertEquals('no separator', 0, CountCol(79, 0, 23, 255, 0, 0));
end;

procedure TGridTokensTest.TestTheRuleUnderTheHeader;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-header-rule-width: 2px; --grid-header-rule-color: #FF0000; }');
  g := MakeGrid;
  Render(g);
  AssertEquals('two rows, the last of the band', 2, CountCol(40, 20, 26, 255, 0, 0));
  AssertTrue('at its foot', IsColor(40, 23, 255, 0, 0));
  AssertTrue('across the whole width', IsColor(370, 23, 255, 0, 0));
  g.StyleOverride := '--grid-header-rule-width: 0';
  Render(g);
  AssertEquals('none', 0, CountCol(40, 20, 26, 255, 0, 0));
end;

procedure TGridTokensTest.TestThePointerOverTheTableDoesNotLightEverySection;
var
  g: TGridAccess;
begin
  Theme('TyGridHeaderSection:hover { background: #FF0000; }');
  g := TGridAccess(MakeGrid);
  g.EnterControl;
  g.HoverAt(40, 100);   { in the body }
  Render(g);
  AssertTrue('the band keeps its colour', IsColor(40, 5, $E0, $E0, $E0));
end;

procedure TGridTokensTest.TestTheSectionUnderThePointerLights;
var
  g: TGridAccess;
begin
  Theme('TyGridHeaderSection:hover { background: #FF0000; } :root { --grid-header-rule-width: 0; }');
  g := TGridAccess(MakeGrid);
  g.Header.Options := g.Header.Options + [hoHotTrack];
  g.EnterControl;
  g.HoverAt(120, 10);   { the second section }
  Render(g);
  AssertTrue('the one under the pointer', IsColor(120, 5, 255, 0, 0));
  AssertTrue('not its neighbour', IsColor(40, 5, $E0, $E0, $E0));
end;

procedure TGridTokensTest.TestASortedAndAFilteredSectionHaveTheirLook;
var
  g: TTyStringGrid;
begin
  Theme('TyGridHeaderSorted { background: #FF0000; } TyGridHeaderFiltered { background: #00FF00; }');
  g := MakeGrid;
  Render(g);
  AssertTrue('nothing sorted yet', IsColor(120, 5, $E0, $E0, $E0));
  g.Header.SortColumn := 1;
  Render(g);
  AssertTrue('the sorted section', IsColor(100, 5, 255, 0, 0));
  AssertTrue('not the next', IsColor(200, 5, $E0, $E0, $E0));
end;

procedure TGridTokensTest.TestHeaderTextPadding;
var
  g: TTyStringGrid;
  a, b: TPoint;
begin
  Theme(':root { --grid-header-rule-width: 0; --grid-header-separator-width: 0; }');
  g := MakeGrid;
  TTyColumn(g.Header.Columns.Items[0]).Text := 'III';
  Render(g);
  a := FirstColor(Rect(0, 2, 40, 22), 0, 0, 0);
  g.StyleOverride := '--grid-header-padding-start: 16px';
  Render(g);
  b := FirstColor(Rect(0, 2, 40, 22), 0, 0, 0);
  AssertTrue('there is a caption', a.X >= 0);
  AssertEquals('it moves with the padding', a.X + 10, b.X);
end;

procedure TGridTokensTest.TestOneGridsHeaderFromItsOverride;
var
  g, other: TTyStringGrid;
begin
  Theme('');
  g := MakeGrid;
  other := MakeGrid;
  g.StyleOverride := '--grid-header-bg: #FF0000; --grid-header-color: #00FF00';
  TTyColumn(g.Header.Columns.Items[0]).Text := 'HHHH';
  Render(g);
  AssertTrue('this grid''s band', IsColor(200, 5, 255, 0, 0));
  AssertTrue('its caption''s ink', CountBox(Rect(0, 0, 60, 22), 0, 255, 0) > 0);
  Render(other);
  AssertTrue('the other grid keeps the theme''s', IsColor(200, 5, $E0, $E0, $E0));
end;

procedure TGridTokensTest.TestABackgroundOfNoneInAnOverride;
var
  g: TTyStringGrid;
begin
  Theme('');
  g := MakeGrid;
  g.StyleOverride := '--grid-header-bg: none';
  Render(g);
  AssertTrue('the band shows the grid''s own surface', IsColor(200, 5, 255, 255, 255));
end;

procedure TGridTokensTest.TestRaisedSections;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-header-bevel: raised; --grid-header-bevel-light: #FF0000; --grid-header-bevel-dark: #00FF00;' +
    ' --grid-header-separator-width: 0; --grid-header-rule-width: 0; }');
  g := MakeGrid;
  Render(g);
  AssertTrue('the section''s top edge is light', IsColor(40, 0, 255, 0, 0));
  AssertTrue('its left edge', IsColor(0, 12, 255, 0, 0));
  AssertTrue('its bottom edge is dark', IsColor(40, 23, 0, 255, 0));
  AssertTrue('its right edge', IsColor(79, 12, 0, 255, 0));
end;

{ ---- the sort mark ---- }

procedure TGridTokensTest.TestTheSortMarkCanBeHidden;
var
  g: TTyStringGrid;
begin
  Theme(':root { --sort-glyph-color: #FF0000; --grid-header-rule-width: 0; }');
  g := MakeGrid;
  g.Header.SortColumn := 0;
  Render(g);
  AssertTrue('the mark', Reddish(Rect(60, 2, 78, 22)) > 0);
  g.StyleOverride := '--sort-glyph: none';
  Render(g);
  AssertEquals('none', 0, Reddish(Rect(60, 2, 78, 22)));
end;

procedure TGridTokensTest.TestTheSortMarksColourAndShape;
var
  g: TTyStringGrid;
  chevron, triangle: Integer;

  function Inked: Integer;
  begin
    Result := Reddish(Rect(60, 2, 78, 22));
  end;

begin
  Theme(':root { --sort-glyph-color: #FF0000; --grid-header-rule-width: 0; }');
  g := MakeGrid;
  g.Header.SortColumn := 0;
  Render(g);
  chevron := Inked;
  g.StyleOverride := '--sort-glyph: triangle';
  Render(g);
  triangle := Inked;
  AssertTrue(Format('a chevron is a line (%d), a triangle is solid (%d)', [chevron, triangle]),
    triangle > chevron);
  g.StyleOverride := '--sort-glyph: triangle; --sort-glyph-size: 16px';
  Render(g);
  AssertTrue('and the size is the token''s', Inked > triangle);
end;

procedure TGridTokensTest.TestTheUnsortedHint;
var
  g: TGridAccess;
begin
  Theme(':root { --sort-glyph-unsorted-color: #FF0000; --grid-header-rule-width: 0; --sort-glyph-color: #00FF00; }');
  g := TGridAccess(MakeGrid);
  Render(g);
  AssertEquals('none by default', 0, Reddish(Rect(60, 2, 78, 22)));
  g.StyleOverride := '--sort-glyph-unsorted: always; --sort-glyph: triangle';
  Render(g);
  AssertTrue('on a column that is not sorted', Reddish(Rect(60, 2, 78, 22)) > 0);
  g.StyleOverride := '--sort-glyph-unsorted: hover; --sort-glyph: triangle';
  Render(g);
  AssertEquals('hover, with the pointer elsewhere', 0, Reddish(Rect(60, 2, 78, 22)));
  g.EnterControl;
  g.HoverAt(40, 10);
  Render(g);
  AssertTrue('hover, with the pointer on the section', Reddish(Rect(60, 2, 78, 22)) > 0);
end;

procedure TGridTokensTest.TestTheListViewHasTheSameMark;
var
  l: TTyListView;
  c: TTyColumn;

  function Red: Integer;
  begin
    Result := Reddish(Rect(0, 0, 200, 24));
  end;

begin
  FCtl.LoadThemeCss('TyListView { background: #FFFFFF; border-width: 0px; }' +
    'TyListViewHeader { background: #E0E0E0; color: #000000; } :root { --sort-glyph-color: #FF0000; }');
  l := TListAccess.Create(FForm);
  l.Parent := FForm;
  l.Controller := FCtl;
  l.SetBounds(0, 0, W, H);
  l.ViewStyle := lvsReport;
  c := l.Header.Columns.Add as TTyColumn;
  c.Width := 200;
  l.Header.SortColumn := 0;
  l.SortColumn := 0;
  RenderList(l);
  AssertTrue('the family''s mark, in the family''s colour', Red > 0);
  l.StyleOverride := '--sort-glyph: none';
  RenderList(l);
  AssertEquals('and its switch', 0, Red);
end;

{ ---- rows and cells ---- }

procedure TGridTokensTest.TestHoverCanLightARowAColumnOrNothing;
var
  g: TGridAccess;
  y0, y1: Integer;
begin
  Theme('TyGridCell:hover { background: #FF0000; } TyGridLine { background: transparent; }');
  g := TGridAccess(MakeGrid(False));
  g.GridLineStyle := glsNone;
  g.EnterControl;
  g.HoverAt(120, 50);   { column 1, row 2 }
  y0 := 50;
  y1 := 90;
  Render(g);
  AssertTrue('by default, the cell', IsColor(120, y0, 255, 0, 0));
  AssertFalse('not the rest of its row', IsColor(40, y0, 255, 0, 0));
  g.StyleOverride := '--grid-hover: row';
  Render(g);
  AssertTrue('row: its neighbour on the row', IsColor(40, y0, 255, 0, 0));
  AssertFalse('row: not the next row', IsColor(120, y1, 255, 0, 0));
  g.StyleOverride := '--grid-hover: column';
  Render(g);
  AssertTrue('column: its neighbour in the column', IsColor(120, y1, 255, 0, 0));
  AssertFalse('column: not along the row', IsColor(40, y0, 255, 0, 0));
  g.StyleOverride := '--grid-hover: cross';
  Render(g);
  AssertTrue('cross: along the row', IsColor(40, y0, 255, 0, 0));
  AssertTrue('cross: down the column', IsColor(120, y1, 255, 0, 0));
  AssertFalse('cross: not elsewhere', IsColor(40, y1, 255, 0, 0));
  g.StyleOverride := '--grid-hover: none';
  Render(g);
  AssertFalse('none', IsColor(120, y0, 255, 0, 0));
end;

procedure TGridTokensTest.TestSelectedAndHovered;
var
  g: TGridAccess;
begin
  Theme('TyGridCell:selected { background: #00FF00; color: #000000; }' +
    ' :root { --grid-selected-hover-bg: #FF0000; --grid-hover: row; }');
  FCtl.LoadThemeCss(BASE_THEME + 'TyGridCell:selected { background: #00FF00; color: #000000; }' +
    ' TyGridCellSelectedHover { background: #FF0000; } :root { --grid-hover: row; }');
  g := TGridAccess(MakeGrid(False));
  g.GridLineStyle := glsNone;
  g.Row := 2;
  Render(g);
  AssertTrue('selected', IsColor(40, 50, 0, 255, 0));
  g.EnterControl;
  g.HoverAt(120, 50);
  Render(g);
  AssertTrue('selected and under the pointer', IsColor(40, 50, 255, 0, 0));
end;

procedure TGridTokensTest.TestASortedColumnsBody;
var
  g: TTyStringGrid;
begin
  Theme('TyGridCellSorted { background: #FF0000; }');
  g := MakeGrid;
  g.GridLineStyle := glsNone;
  g.Row := 5;
  Render(g);
  AssertFalse('nothing sorted', IsColor(120, 60, 255, 0, 0));
  g.Header.SortColumn := 1;
  Render(g);
  AssertTrue('the sorted column', IsColor(120, 60, 255, 0, 0));
  AssertFalse('not its neighbour', IsColor(40, 60, 255, 0, 0));
end;

procedure TGridTokensTest.TestTheSelectionFrameIsOverTheGridLines;
var
  g: TTyStringGrid;
begin
  Theme('TyGridSelectionFrame { border-color: #FF0000; border-width: 1px; }');
  g := MakeGrid(False);
  g.SelectionMode := gsmCell;
  g.Col := 0;
  g.Row := 1;
  Render(g);
  { Its right and bottom edges are on the pixel of the cell's grid lines. }
  AssertTrue('the right edge', IsColor(79, 30, 255, 0, 0));
  AssertTrue('the bottom edge', IsColor(40, 39, 255, 0, 0));
end;

procedure TGridTokensTest.TestTheFillHandleSize;
var
  g: TTyStringGrid;
  small, big: Integer;
begin
  Theme('TyGridSelectionFrame { border-color: #FF0000; border-width: 1px; background: #00FF00; color: #0000FF; }');
  g := MakeGrid(False);
  g.SelectionMode := gsmCell;
  g.Col := 0;
  g.Row := 1;
  Render(g);
  small := CountBox(Rect(60, 20, 90, 50), 0, 255, 0);
  g.StyleOverride := '--grid-fill-handle-size: 12px';
  Render(g);
  big := CountBox(Rect(60, 20, 90, 50), 0, 255, 0);
  AssertTrue(Format('the handle grows, %d to %d', [small, big]), big > small);
end;

procedure TGridTokensTest.TestTheFocusRing;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-focus-ring-color: #FF0000; }');
  g := MakeGrid(False);
  g.ShowFocusCell := True;
  g.HideSelectionWhenInactive := False;
  g.Col := 1;
  g.Row := 1;
  Render(g);
  AssertEquals('none by default', 0, CountRow(20, 80, 160, 255, 0, 0));
  g.StyleOverride := '--grid-focus-ring-width: 2px';
  Render(g);
  AssertTrue('round the cursor''s cell: the top', CountRow(20, 80, 159, 255, 0, 0) > 70);
  AssertTrue('two thick', CountRow(21, 80, 159, 255, 0, 0) > 70);
  AssertTrue('the left', IsColor(80, 30, 255, 0, 0));
  g.StyleOverride := '--grid-focus-ring-width: 1px; --grid-focus-ring-style: 2px 2px';
  Render(g);
  AssertEquals('dashed', 40, CountRow(20, 80, 159, 255, 0, 0));
  g.ShowFocusCell := False;
  g.StyleOverride := '--grid-focus-ring-width: 2px';
  Render(g);
  AssertEquals('ShowFocusCell turns it off', 0, CountRow(20, 80, 160, 255, 0, 0));
end;

{ ---- bands ---- }

procedure TGridTokensTest.TestTheFrozenEdge;
var
  g: TTyStringGrid;
begin
  Theme(':root { --grid-frozen-line-color: #FF0000; --grid-frozen-line-width: 2px; }');
  g := MakeGrid;
  Render(g);
  AssertEquals('nothing frozen, no edge', 0, CountRow(60, 0, 200, 255, 0, 0));
  g.FixedCols := 1;
  g.FixedRows := 1;
  Render(g);
  AssertEquals('the frozen column''s edge, 2 wide', 2, CountRow(70, 70, 90, 255, 0, 0));
  AssertTrue('on its own side of the boundary', IsColor(79, 70, 255, 0, 0));
  AssertTrue('the frozen row''s edge', CountCol(200, 24, 60, 255, 0, 0) = 2);
  g.StyleOverride := '--grid-frozen-line-width: 0';
  Render(g);
  AssertEquals('width 0, none', 0, CountRow(70, 70, 90, 255, 0, 0));
end;

procedure TGridTokensTest.TestTheFrozenShadowOnlyOnceScrolled;
var
  g: TTyStringGrid;
begin
  Theme('TyGrid { background: #FFFFFF; } :root { --grid-frozen-line-width: 0; --grid-frozen-shadow-size: 6px;' +
    ' --grid-frozen-shadow-color: rgba(255, 0, 0, 0.8); }');
  g := MakeGrid;
  g.GridLineStyle := glsNone;
  g.RowCount := 100;
  g.FixedRows := 1;
  Render(g);
  AssertTrue('not scrolled: no shadow', Px(200, 44 + 2).green = 255);
  TGridAccess(g).ScrollTo(30);
  Render(g);
  AssertTrue('scrolled: under the frozen row', Px(200, 44).green < 200);
  AssertTrue('fading', Px(200, 44).green < Px(200, 48).green);
  AssertTrue('and gone past its size', Px(200, 52).green = 255);
end;

procedure TGridTokensTest.TestTheFootersRule;
var
  g: TGridAccess;
  y: Integer;
begin
  Theme(':root { --grid-footer-rule-color: #FF0000; --grid-footer-rule-width: 2px; }');
  g := TGridAccess(MakeGrid);
  g.ShowFooter := True;
  Render(g);
  y := g.Metrics.ClientH;
  AssertTrue('along the footer''s top', IsColor(200, y, 255, 0, 0));
  AssertTrue('2 thick', IsColor(200, y + 1, 255, 0, 0));
  AssertFalse('no more', IsColor(200, y + 2, 255, 0, 0));
  g.StyleOverride := '--grid-footer-rule-width: 0';
  Render(g);
  AssertFalse('width 0, none', IsColor(200, y, 255, 0, 0));
end;

procedure TGridTokensTest.TestTheCursorsRowNumber;
var
  g: TTyStringGrid;
begin
  Theme('TyGridIndicator { background: #E0E0E0; color: #000000; }' +
    ' TyGridIndicatorActive { background: #FF0000; color: #000000; }');
  g := MakeGrid;
  g.ShowIndicator := True;
  g.ShowRowNumbers := True;
  g.Row := 1;
  Render(g);
  AssertTrue('the cursor''s row', IsColor(2, 24 + 20 + 2, 255, 0, 0));
  AssertFalse('not another', IsColor(2, 24 + 2, 255, 0, 0));
end;

{ ---- the theme engine ---- }

procedure TGridTokensTest.TestAVarMayNameNoneOrAnotherVar;
var
  s: TTyStyleSet;
begin
  FCtl.LoadThemeCss(':root { --a: none; --b: var(--c); --c: 17px; --d: linear-gradient(90deg, #FF0000, #0000FF); }' +
    'TyX { background: var(--a); font-size: var(--b); } TyY { background: var(--d); }');
  s := FCtl.Model.ResolveStyle('TyX', '', []);
  AssertTrue('a background of var(--none) is none', s.Background.Kind = tfkNone);
  AssertEquals('a length through two names', 17, s.FontSize);
  s := FCtl.Model.ResolveStyle('TyY', '', []);
  AssertTrue('a gradient through a name', s.Background.Kind <> tfkSolid);
end;

initialization
  RegisterTest(TGridTokensTest);

end.
