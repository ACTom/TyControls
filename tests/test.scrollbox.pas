unit test.scrollbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller,
  tyControls.Base, tyControls.Panel, tyControls.ScrollBar, tyControls.ScrollBox;
type
  { Pure scroll-math functions — the headless-tested core. }
  TTyScrollBoxMathTest = class(TTestCase)
  published
    procedure TestScrollNeeded;
    procedure TestScrollMax;
    procedure TestClampScroll;
    procedure TestThumbPage;
  end;

  { The control: range computation, bar visibility, offset clamping, wheel. }
  TTyScrollBoxTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeyIsPanel;
    procedure TestNoBarsWhenContentFits;
    procedure TestVerticalBarWhenContentTaller;
    procedure TestHorizontalBarWhenContentWider;
    procedure TestBothBarsWhenContentBigger;
    procedure TestRangeIsChildBoundingBox;
    procedure TestScrollbarSyncsOffset;
    procedure TestOffsetClampsWhenBoxGrows;
    procedure TestWheelScrollsVertically;
    procedure TestScrollBarsAreNoDesignVisible;
    procedure TestBarInheritsController;
  end;
implementation

type
  TScrollBoxAccess = class(TTyScrollBox)
  public
    function StyleTypeKey: string;
    function VBar: TTyScrollBar;
    function HBar: TTyScrollBar;
    procedure CallWheel(WheelDelta: Integer);
  end;

function TScrollBoxAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

function TScrollBoxAccess.VBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if (Controls[i] is TTyScrollBar)
       and (TTyScrollBar(Controls[i]).Kind = sbVertical) then
      Exit(TTyScrollBar(Controls[i]));
end;

function TScrollBoxAccess.HBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if (Controls[i] is TTyScrollBar)
       and (TTyScrollBar(Controls[i]).Kind = sbHorizontal) then
      Exit(TTyScrollBar(Controls[i]));
end;

procedure TScrollBoxAccess.CallWheel(WheelDelta: Integer);
begin
  DoMouseWheel([], WheelDelta, Point(0, 0));
end;

{ helper: a plain child of a given size at a given position }
function MakeChild(AParent: TWinControl; AL, AT, AW, AH: Integer): TControl;
var c: TTyPanel;
begin
  c := TTyPanel.Create(AParent);
  c.Parent := AParent;
  c.SetBounds(AL, AT, AW, AH);
  Result := c;
end;

{ TTyScrollBoxMathTest }

procedure TTyScrollBoxMathTest.TestScrollNeeded;
begin
  AssertTrue('content taller than viewport needs a bar', TyScrollNeeded(300, 150));
  AssertFalse('content equal to viewport needs no bar', TyScrollNeeded(150, 150));
  AssertFalse('content shorter than viewport needs no bar', TyScrollNeeded(80, 150));
end;

procedure TTyScrollBoxMathTest.TestScrollMax;
begin
  AssertEquals('range = content - viewport', 150, TyScrollMax(300, 150));
  AssertEquals('fits -> 0', 0, TyScrollMax(100, 150));
  AssertEquals('equal -> 0', 0, TyScrollMax(150, 150));
end;

procedure TTyScrollBoxMathTest.TestClampScroll;
begin
  // content 300, viewport 150 -> max offset 150
  AssertEquals('mid stays', 40, TyClampScroll(40, 300, 150));
  AssertEquals('above max clamps to max', 150, TyClampScroll(999, 300, 150));
  AssertEquals('negative clamps to 0', 0, TyClampScroll(-5, 300, 150));
  // content fits -> everything pins to 0
  AssertEquals('fits pins to 0', 0, TyClampScroll(40, 100, 150));
end;

procedure TTyScrollBoxMathTest.TestThumbPage;
begin
  AssertEquals('page = viewport', 150, TyScrollThumbPage(150, 300));
  AssertEquals('never below 1', 1, TyScrollThumbPage(0, 300));
end;

{ TTyScrollBoxTest }

procedure TTyScrollBoxTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TTyScrollBoxTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyScrollBoxTest.TestTypeKeyIsPanel;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  AssertEquals('reuses TyPanel typeKey', 'TyPanel', SB.StyleTypeKey);
end;

procedure TTyScrollBoxTest.TestNoBarsWhenContentFits;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 10, 10, 100, 80);   // well inside
  SB.UpdateScrollRange;
  AssertTrue('no vertical bar when content fits',
    (SB.VBar = nil) or (not SB.VBar.Visible));
  AssertTrue('no horizontal bar when content fits',
    (SB.HBar = nil) or (not SB.HBar.Visible));
end;

procedure TTyScrollBoxTest.TestVerticalBarWhenContentTaller;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 10, 10, 100, 500);  // taller than the 200px viewport
  SB.UpdateScrollRange;
  AssertNotNull('vertical bar exists', SB.VBar);
  AssertTrue('vertical bar visible when content taller', SB.VBar.Visible);
end;

procedure TTyScrollBoxTest.TestHorizontalBarWhenContentWider;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 10, 10, 800, 80);   // wider than the 300px viewport
  SB.UpdateScrollRange;
  AssertNotNull('horizontal bar exists', SB.HBar);
  AssertTrue('horizontal bar visible when content wider', SB.HBar.Visible);
end;

procedure TTyScrollBoxTest.TestBothBarsWhenContentBigger;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 10, 10, 800, 500);  // bigger on both axes
  SB.UpdateScrollRange;
  AssertTrue('vertical bar visible', (SB.VBar <> nil) and SB.VBar.Visible);
  AssertTrue('horizontal bar visible', (SB.HBar <> nil) and SB.HBar.Visible);
end;

procedure TTyScrollBoxTest.TestRangeIsChildBoundingBox;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  // Two children; far edges at (20+150)=170 wide and (30+400)=430 tall.
  MakeChild(SB, 5, 5, 60, 60);
  MakeChild(SB, 20, 30, 150, 400);
  SB.UpdateScrollRange;
  AssertEquals('content width = far right edge', 170, SB.ContentWidth);
  AssertEquals('content height = far bottom edge', 430, SB.ContentHeight);
end;

procedure TTyScrollBoxTest.TestScrollbarSyncsOffset;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 600);   // vertical overflow (range 400+)
  SB.UpdateScrollRange;
  AssertNotNull('vbar present', SB.VBar);
  AssertEquals('offset starts at 0', 0, SB.ScrollY);

  // Move the scrollbar -> the box offset must follow.
  SB.VBar.Position := 50;
  AssertEquals('vertical offset follows scrollbar', 50, SB.ScrollY);
end;

procedure TTyScrollBoxTest.TestOffsetClampsWhenBoxGrows;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 600);   // range 400 (content 600 - view 200)
  SB.UpdateScrollRange;
  SB.VBar.Position := SB.VBar.Max;  // scroll to the very bottom
  AssertTrue('scrolled toward bottom', SB.ScrollY > 0);

  // Grow the box so the content now fits: offset must clamp back to 0 and the bar hide.
  SB.SetBounds(0, 0, 300, 700);
  SB.UpdateScrollRange;
  AssertEquals('offset clamped to 0 when content fits again', 0, SB.ScrollY);
  AssertTrue('vertical bar hidden when content fits again',
    (SB.VBar = nil) or (not SB.VBar.Visible));
end;

procedure TTyScrollBoxTest.TestWheelScrollsVertically;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 600);   // vertical overflow
  SB.UpdateScrollRange;
  AssertEquals('starts unscrolled', 0, SB.ScrollY);

  // Wheel DOWN (negative delta) scrolls content up -> offset increases.
  SB.CallWheel(-120);
  AssertTrue('wheel down increases the vertical offset', SB.ScrollY > 0);

  // Wheel UP back toward the top.
  SB.CallWheel(120);
  AssertEquals('wheel up returns to the top', 0, SB.ScrollY);
end;

procedure TTyScrollBoxTest.TestScrollBarsAreNoDesignVisible;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 800, 600);   // force both bars to exist
  SB.UpdateScrollRange;
  AssertTrue('vbar is csNoDesignVisible',
    csNoDesignVisible in SB.VBar.ControlStyle);
  AssertTrue('hbar is csNoDesignVisible',
    csNoDesignVisible in SB.HBar.ControlStyle);
end;

procedure TTyScrollBoxTest.TestBarInheritsController;
var
  Ctl: TTyStyleController;
  SB: TScrollBoxAccess;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    SB := TScrollBoxAccess.Create(FForm);
    SB.Parent := FForm;
    SB.Font.PixelsPerInch := 96;
    SB.Controller := Ctl;
    SB.SetBounds(0, 0, 300, 200);
    MakeChild(SB, 0, 0, 100, 600);
    SB.UpdateScrollRange;
    AssertNotNull('vbar present', SB.VBar);
    AssertTrue('embedded bar inherits the box Controller', SB.VBar.Controller = Ctl);
  finally
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyScrollBoxMathTest);
  RegisterTest(TTyScrollBoxTest);
end.
