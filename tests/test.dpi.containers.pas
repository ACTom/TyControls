unit test.dpi.containers;
{ Containers that lay their children out from KNOBS OF THEIR OWN.      (ACTom/TyControls#2)

  A tool bar's Indent, a status panel's Width, a grid panel's gutter, a splitter's MinSize
  are all LOGICAL px -- a number somebody typed into the Object Inspector, or a theme token
  -- and every one of them used to be added, raw, to numbers that are DEVICE px: the
  container's ClientWidth, a child's Width, a child's size floor. Those are the same number
  at 96 PPI and at no other.

  LCL cannot help here. Its DPI pass scales what it knows about -- bounds, Constraints,
  BorderSpacing -- and a control's own published integers are not among them. So at 175% a
  form's buttons came through 1.75x larger and were then laid out, by their own tool bar, in
  rows still pitched and spaced for 96.

  THE SHAPE OF EVERY TEST HERE: build the same container at 96 and at 168 PPI and compare
  what it did with its children. 168 is 175%, the scaling the defect was reported at, and
  it is deliberately not a multiple of 96: a knob that was scaled by the wrong proportion
  does not land on the right number by accident. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, ExtCtrls, LCLType,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Button,
  tyControls.ToolBar, tyControls.ToolBarEx, tyControls.ToolGroupPanel,
  tyControls.GridPanel, tyControls.RelativePanel, tyControls.StatusBar,
  tyControls.Splitter, tyControls.DateTimePicker;

type
  { AlignControls is protected and this runner has no message pump to run it for us. }
  TToolBarLayoutAccess = class(TTyToolBar)
  public
    procedure ForceLayout;
  end;

  TToolBarExLayoutAccess = class(TTyToolBarEx)
  public
    procedure ForceLayout;
  end;

  TToolGroupLayoutAccess = class(TTyToolGroupPanel)
  public
    procedure ForceLayout;
  end;

  TSplitterDragAccess = class(TTySplitter)
  public
    procedure FakeDrag(AStartX, AEndX, AYMid: Integer);
  end;

  TDateTimePickerSizeAccess = class(TTyDateTimePicker)
  public
    procedure CallPreferredSize(out AW, AH: Integer);
  end;

  TTyContainerDpiTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    function S(AValue, APPI: Integer): Integer;
    function NewTool(ABar: TWinControl; APPI: Integer): TTyButton;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestToolBarRowFollowsThePPI;
    procedure TestToolBarExRowAndChevronFollowThePPI;
    procedure TestToolGroupPanelRowsDoNotRunIntoEachOther;
    procedure TestGridPanelAbsoluteTrackAndGutterFollowThePPI;
    procedure TestRelativePanelSpacingFollowsThePPI;
    procedure TestStatusBarPanelWidthFollowsThePPI;
    procedure TestSplitterMinSizeFollowsThePPI;
    procedure TestDateTimePickerHeightFloorFollowsThePPI;
  end;

implementation

const
  HI = 168;      // 175%

procedure TToolBarLayoutAccess.ForceLayout;
var
  dummy: TRect;
begin
  dummy := ClientRect;
  AlignControls(nil, dummy);
end;

procedure TToolBarExLayoutAccess.ForceLayout;
var
  dummy: TRect;
begin
  dummy := ClientRect;
  AlignControls(nil, dummy);
end;

procedure TToolGroupLayoutAccess.ForceLayout;
var
  dummy: TRect;
begin
  dummy := ClientRect;
  AlignControls(nil, dummy);
end;

procedure TSplitterDragAccess.FakeDrag(AStartX, AEndX, AYMid: Integer);
begin
  MouseDown(mbLeft, [], AStartX, AYMid);
  MouseMove([ssLeft], AEndX, AYMid);
  MouseUp(mbLeft, [], AEndX, AYMid);
end;

procedure TDateTimePickerSizeAccess.CallPreferredSize(out AW, AH: Integer);
begin
  AW := 0;
  AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

{ ===== harness ============================================================== }

procedure TTyContainerDpiTest.SetUp;
begin
  inherited SetUp;
  { Tokens of this suite's own, so the numbers below do not depend on whichever theme an
    earlier test left on the default controller. Root tokens only -- a partial type rule is
    how a theme erases a control. }
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(':root { --font-size-base: 9; --line-height: 14; --control-height: 24; '
    + '--toolbar-pad-y: 4; --spacing: 8; }');
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(40, 40, 1400, 900);
  FForm.Font.PixelsPerInch := 96;
  FForm.Font.Size := 9;
end;

procedure TTyContainerDpiTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TTyContainerDpiTest.S(AValue, APPI: Integer): Integer;
begin
  Result := MulDiv(AValue, APPI, 96);
end;

function TTyContainerDpiTest.NewTool(ABar: TWinControl; APPI: Integer): TTyButton;
begin
  { A plain button with no caption and a width of its own, as the tool bar's own geometry
    tests use: nothing about it depends on a measured string, so what is left to compare is
    what the BAR did with it. }
  Result := TTyButton.Create(FForm);
  Result.Controller := FCtl;
  { Parented AFTER the bar was given its PPI: a ParentFont child takes its parent's PPI on
    the way in, which is how it gets it on a real form too. }
  Result.Parent := ABar;
  Result.Width := S(60, APPI);
end;

{ ===== tool bars ============================================================ }

procedure TTyContainerDpiTest.TestToolBarRowFollowsThePPI;

  procedure Build(APPI: Integer; out ALeft, AGap, ATop, ARowH, ABarH: Integer);
  var
    tb: TToolBarLayoutAccess;
    b1, b2: TTyButton;
  begin
    tb := TToolBarLayoutAccess.Create(FForm);
    tb.Controller := FCtl;
    tb.Parent := FForm;
    tb.Font.PixelsPerInch := APPI;
    tb.Indent := 10;
    tb.ButtonSpacing := 6;
    tb.Width := S(600, APPI);
    b1 := NewTool(tb, APPI);
    b2 := NewTool(tb, APPI);
    AssertEquals('precondition: the tools took the bar''s PPI', APPI, b1.Font.PixelsPerInch);
    tb.ForceLayout;
    ALeft := b1.Left;
    AGap := b2.Left - (b1.Left + b1.Width);
    ATop := b1.Top;
    ARowH := b1.Height;
    ABarH := tb.Height;
    tb.Free;       // frees nothing else: the tools are owned by the form
    b1.Free;
    b2.Free;
  end;

var
  l96, g96, t96, r96, h96: Integer;
  l, g, t, r, h: Integer;
begin
  Build(96, l96, g96, t96, r96, h96);
  AssertEquals('precondition: at 96 PPI the first tool sits at Indent', 10, l96);
  AssertEquals('precondition: at 96 PPI the tools are ButtonSpacing apart', 6, g96);
  AssertEquals('precondition: at 96 PPI the row starts at --toolbar-pad-y', 4, t96);

  Build(HI, l, g, t, r, h);
  AssertEquals('Indent at 168 PPI', S(10, HI), l);
  AssertEquals('ButtonSpacing at 168 PPI', S(6, HI), g);
  AssertEquals('--toolbar-pad-y at 168 PPI', S(4, HI), t);
  AssertTrue(Format('the row is at least ButtonHeight tall at 168 PPI: %d px, wanted %d',
    [r, S(24, HI)]), r >= S(24, HI));
  AssertEquals('the bar grows to pad + row + pad, all at 168 PPI', 2 * S(4, HI) + r, h);
  AssertTrue(Format('...which is NOT the height the 96-PPI bar had (%d)', [h96]), h > h96);
end;

procedure TTyContainerDpiTest.TestToolBarExRowAndChevronFollowThePPI;

  procedure Build(APPI: Integer; out ALeft, AGap, ATop, AChevronW, AChevronRightGap: Integer);
  var
    tb: TToolBarExLayoutAccess;
    tools: array[0..5] of TTyButton;
    i: Integer;
    chevron: TControl;
  begin
    tb := TToolBarExLayoutAccess.Create(FForm);
    tb.Controller := FCtl;
    tb.Parent := FForm;
    tb.Font.PixelsPerInch := APPI;
    tb.Wrapable := False;          // the path TTyToolBarEx lays out itself
    tb.Indent := 10;
    tb.ButtonSpacing := 6;
    { Too narrow for six tools at either PPI, so the chevron is up in both. }
    tb.SetBounds(0, 0, S(200, APPI), S(40, APPI));
    for i := 0 to High(tools) do
      tools[i] := NewTool(tb, APPI);
    tb.ForceLayout;
    ALeft := tools[0].Left;
    AGap := tools[1].Left - (tools[0].Left + tools[0].Width);
    ATop := tools[0].Top;
    chevron := nil;
    for i := 0 to tb.ControlCount - 1 do
      if tb.Controls[i].Visible and (tb.Controls[i].Owner = tb) then
        chevron := tb.Controls[i];   // the only child the BAR owns; the tools are the form's
    AssertNotNull('precondition: the bar overflows, so the chevron is showing', chevron);
    AssertTrue('precondition: the first two tools fit', tools[1].Visible);
    AChevronW := chevron.Width;
    AChevronRightGap := tb.ClientWidth - (chevron.Left + chevron.Width);
    for i := 0 to High(tools) do tools[i].Free;
    tb.Free;
  end;

var
  l, g, t, cw, cg: Integer;
begin
  Build(96, l, g, t, cw, cg);
  AssertEquals('precondition: Indent at 96 PPI', 10, l);
  AssertEquals('precondition: ButtonSpacing at 96 PPI', 6, g);
  AssertEquals('precondition: the chevron cell at 96 PPI', 30, cw);

  Build(HI, l, g, t, cw, cg);
  AssertEquals('Indent at 168 PPI', S(10, HI), l);
  AssertEquals('ButtonSpacing at 168 PPI', S(6, HI), g);
  AssertEquals('--toolbar-pad-y at 168 PPI', S(4, HI), t);
  { The chevron is a button with a size floor of its own, so it may be wider than its
    cell -- never narrower. }
  AssertTrue(Format('the chevron cell at 168 PPI: %d px, wanted at least %d', [cw, S(30, HI)]),
    cw >= S(30, HI));
  AssertEquals('the chevron stands Indent off the far edge at 168 PPI', S(10, HI), cg);
end;

procedure TTyContainerDpiTest.TestToolGroupPanelRowsDoNotRunIntoEachOther;
{ The visible form of the defect: a button is clamped UP to its own floor by SetBounds, so
  rows pitched at the bare ButtonHeight overlapped as soon as the floor was the taller of
  the two -- which at 175% it always is, 42 px against 26. }

  procedure Build(APPI: Integer; out ARow2Top, ARow1Bottom, AGapWanted, ARowH: Integer);
  var
    p: TToolGroupLayoutAccess;
    a, b: TTyButton;
  begin
    p := TToolGroupLayoutAccess.Create(FForm);
    p.Controller := FCtl;
    p.Parent := FForm;
    p.Font.PixelsPerInch := APPI;
    p.Spacing := 4;
    p.ButtonHeight := 26;
    { Narrow enough that the second button has to start a row of its own. }
    p.SetBounds(0, 0, S(90, APPI), S(160, APPI));
    a := p.AddButton('Cut');
    a.Controller := FCtl;
    a.Width := S(60, APPI);
    b := p.AddButton('Copy');
    b.Controller := FCtl;
    b.Width := S(60, APPI);
    p.ForceLayout;
    AssertTrue('precondition: the second button wrapped onto a row of its own',
      b.Top > a.Top);
    ARow1Bottom := a.Top + a.Height;
    ARow2Top := b.Top;
    AGapWanted := S(4, APPI);
    ARowH := a.Height;
    p.Free;
  end;

var
  top2, bottom1, gap, rowH: Integer;
begin
  Build(96, top2, bottom1, gap, rowH);
  AssertEquals('precondition: rows are Spacing apart at 96 PPI', gap, top2 - bottom1);

  Build(HI, top2, bottom1, gap, rowH);
  AssertTrue(Format('the rows overlap at 168 PPI: row one ends at %d, row two starts at %d',
    [bottom1, top2]), top2 >= bottom1);
  AssertEquals('...and are Spacing apart, at 168 PPI', gap, top2 - bottom1);
  AssertTrue(Format('a row is at least ButtonHeight tall at 168 PPI: %d, wanted %d',
    [rowH, S(26, HI)]), rowH >= S(26, HI));
end;

{ ===== panels =============================================================== }

procedure TTyContainerDpiTest.TestGridPanelAbsoluteTrackAndGutterFollowThePPI;

  procedure Build(APPI: Integer; out AFixedW, AGutter, AStarW, ATotal: Integer);
  var
    g: TTyGridPanel;
    a, b: TTyGridCell;
  begin
    g := TTyGridPanel.Create(FForm);
    g.Controller := FCtl;
    g.Parent := FForm;
    g.Font.PixelsPerInch := APPI;
    g.SetBounds(0, 0, S(400, APPI), S(100, APPI));
    g.ColumnCount := 2;
    g.RowCount := 1;
    g.Spacing := 8;
    g.ColumnSizes := '100, *';
    a := TTyGridCell(g.Cells[0, 0]);
    b := TTyGridCell(g.Cells[1, 0]);
    AssertNotNull('precondition: cell 0', a);
    AssertNotNull('precondition: cell 1', b);
    AFixedW := a.Width;
    AGutter := b.Left - (a.Left + a.Width);
    AStarW := b.Width;
    ATotal := g.ClientWidth;
    g.Free;
  end;

var
  fixedW, gutter, starW, total: Integer;
begin
  Build(96, fixedW, gutter, starW, total);
  AssertEquals('precondition: the absolute track at 96 PPI', 100, fixedW);
  AssertEquals('precondition: the gutter at 96 PPI', 8, gutter);

  Build(HI, fixedW, gutter, starW, total);
  AssertEquals('an absolute track is logical px: 100 at 168 PPI', S(100, HI), fixedW);
  AssertEquals('Spacing is logical px: 8 at 168 PPI', S(8, HI), gutter);
  AssertEquals('...and the star track takes exactly what is left', total - fixedW - gutter,
    starW);
end;

procedure TTyContainerDpiTest.TestRelativePanelSpacingFollowsThePPI;

  function Build(APPI: Integer): Integer;
  var
    rp: TTyRelativePanel;
    a, b: TPanel;
  begin
    rp := TTyRelativePanel.Create(FForm);
    rp.Controller := FCtl;
    rp.Parent := FForm;
    rp.Font.PixelsPerInch := APPI;
    rp.Spacing := 10;
    rp.SetBounds(0, 0, S(300, APPI), S(100, APPI));
    a := TPanel.Create(FForm);
    a.Parent := rp;
    a.SetBounds(0, 0, S(50, APPI), S(20, APPI));
    b := TPanel.Create(FForm);
    b.Parent := rp;
    b.SetBounds(0, 0, S(30, APPI), S(20, APPI));
    rp.SetRules(a, [traAlignParentLeft, traAlignParentTop]);
    rp.SetRules(b, [trRightOf], a);
    rp.PerformLayout;
    Result := b.Left - (a.Left + a.Width);
    a.Free;
    b.Free;
    rp.Free;
  end;

begin
  AssertEquals('precondition: Spacing at 96 PPI', 10, Build(96));
  AssertEquals('Spacing is logical px: 10 at 168 PPI', S(10, HI), Build(HI));
end;

procedure TTyContainerDpiTest.TestStatusBarPanelWidthFollowsThePPI;
{ Asked of the HIT TEST, which shares its cell rects with the paint through one function
  (PanelWidthsPx) -- so where the pointer finds the seam is where the separator is drawn. }

  function Seam(APPI: Integer): Integer;
  var
    bar: TTyStatusBar;
    x: Integer;
  begin
    bar := TTyStatusBar.Create(FForm);
    bar.Controller := FCtl;
    bar.Parent := FForm;
    bar.Font.PixelsPerInch := APPI;
    bar.Align := alNone;
    bar.SizeGrip := False;
    bar.SetBounds(0, 0, S(600, APPI), S(22, APPI));
    bar.Panels.Add.Width := 100;
    bar.Panels.Add.Width := 60;
    bar.Panels.Add.Width := 0;       // takes what is left
    Result := -1;
    for x := 0 to bar.Width - 1 do
      if bar.PanelAtPos(x, 2) = 1 then
      begin
        Result := x;
        Break;
      end;
    bar.Free;
  end;

var
  lo, hi_: Integer;
begin
  lo := Seam(96);
  AssertTrue('precondition: the second panel was found at 96 PPI', lo > 0);
  hi_ := Seam(HI);
  { The seam is the bar's padding plus the first panel's width, both logical. }
  AssertEquals('the first panel is 100 LOGICAL px wide: the seam at 168 PPI',
    S(lo - 100, HI) + S(100, HI), hi_);
  AssertTrue(Format('...which is not where it was at 96 PPI (%d)', [lo]), hi_ > lo);
end;

procedure TTyContainerDpiTest.TestSplitterMinSizeFollowsThePPI;

  function FlooredAt(APPI: Integer): Integer;
  var
    pan: TPanel;
    sp: TSplitterDragAccess;
  begin
    pan := TPanel.Create(FForm);
    pan.Parent := FForm;
    pan.Align := alNone;
    pan.SetBounds(0, 0, S(200, APPI), S(200, APPI));
    sp := TSplitterDragAccess.Create(FForm);
    sp.Controller := FCtl;
    sp.Parent := FForm;
    sp.Font.PixelsPerInch := APPI;
    sp.Align := alNone;            // no align engine here; see test.splitter
    sp.SetBounds(pan.Width, 0, S(5, APPI), S(200, APPI));
    sp.Align := alLeft;
    sp.MinSize := 40;
    sp.AutoSnap := False;          // so the drag stops AT the floor instead of closing
    sp.FakeDrag(0, -2000, 100);
    Result := pan.Width;
    sp.Free;
    pan.Free;
  end;

begin
  AssertEquals('precondition: the pane stops at MinSize at 96 PPI', 40, FlooredAt(96));
  AssertEquals('MinSize is logical px: 40 at 168 PPI', S(40, HI), FlooredAt(HI));
end;

procedure TTyContainerDpiTest.TestDateTimePickerHeightFloorFollowsThePPI;
{ The floor under an auto-sized picker's height is --control-height, a logical number that
  used to be compared, raw, with a device-px text height. }

  function Pref(APPI: Integer): Integer;
  var
    p: TDateTimePickerSizeAccess;
    w: Integer;
  begin
    p := TDateTimePickerSizeAccess.Create(FForm);
    p.Controller := FCtl;
    p.Parent := FForm;
    p.Font.PixelsPerInch := APPI;
    p.CallPreferredSize(w, Result);
    p.Free;
  end;

var
  lo, hi_: Integer;
begin
  lo := Pref(96);
  hi_ := Pref(HI);
  AssertTrue(Format('precondition: at 96 PPI the picker is at least --control-height'
    + ' tall (%d)', [lo]), lo >= 24);
  AssertTrue(Format('at 168 PPI it is at least --control-height tall IN DEVICE PX: %d,'
    + ' wanted %d', [hi_, S(24, HI)]), hi_ >= S(24, HI));
end;

initialization
  RegisterTest(TTyContainerDpiTest);

end.
