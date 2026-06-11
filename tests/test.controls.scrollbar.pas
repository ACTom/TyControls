unit test.controls.scrollbar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  Forms, Controls,
  tyControls.ScrollBar;
type
  TTyScrollGeometryTest = class(TTestCase)
  published
    procedure TestVerticalThumbAtTop;
    procedure TestVerticalThumbAtBottom;
    procedure TestVerticalThumbMidway;
    procedure TestHorizontalThumbAtTop;
    procedure TestZeroRangeFillsTrack;
  end;

  TTyScrollBarDragTest = class(TTestCase)
  private
    FForm: TForm;
    FBar: TTyScrollBar;
    FChanges: Integer;
    procedure OnBarChange(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDragMovesPosition;
    procedure TestDragFiresOnChange;
    procedure TestDragClampsAtMax;
  end;
implementation
procedure TTyScrollGeometryTest.TestVerticalThumbAtTop;
var
  R: TRect;
begin
  // track 0,0..20,200 ; range 0..100 ; page 25 ; pos 0
  R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 0, 100, 0, 25);
  AssertEquals('thumb top at position 0', 0, R.Top);
  AssertEquals('thumb left spans track', 0, R.Left);
  AssertEquals('thumb right spans track', 20, R.Right);
  // 25/(100-0+25)=25/125=0.2 of 200 = 40
  AssertEquals('thumb height = page fraction of track', 40, R.Bottom - R.Top);
end;
procedure TTyScrollGeometryTest.TestVerticalThumbAtBottom;
var
  R: TRect;
begin
  // pos 100 is max (range 0..100, page 25 -> effective max 100)
  R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 0, 100, 100, 25);
  AssertEquals('thumb bottom hugs track end', 200, R.Bottom);
  AssertEquals('thumb height stays page-sized', 40, R.Bottom - R.Top);
end;
procedure TTyScrollGeometryTest.TestVerticalThumbMidway;
var
  R: TRect;
begin
  // pos 50 of travel 100 -> 0.5 of free space (200-40=160) -> top 80
  R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 0, 100, 50, 25);
  AssertEquals('thumb top at half travel', 80, R.Top);
  AssertEquals('thumb height stays page-sized', 40, R.Bottom - R.Top);
end;
procedure TTyScrollGeometryTest.TestHorizontalThumbAtTop;
var
  R: TRect;
begin
  R := TyScrollThumbRect(Rect(0, 0, 200, 20), sbHorizontal, 0, 100, 0, 25);
  AssertEquals('horizontal thumb left at position 0', 0, R.Left);
  AssertEquals('horizontal thumb top spans track', 0, R.Top);
  AssertEquals('horizontal thumb bottom spans track', 20, R.Bottom);
  AssertEquals('horizontal thumb width = page fraction', 40, R.Right - R.Left);
end;
procedure TTyScrollGeometryTest.TestZeroRangeFillsTrack;
var
  R: TRect;
begin
  // min=max -> nothing to scroll, thumb fills whole track
  R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 5, 5, 5, 10);
  AssertEquals('degenerate range: thumb top is track top', 0, R.Top);
  AssertEquals('degenerate range: thumb fills track', 200, R.Bottom);
end;
procedure TTyScrollBarDragTest.OnBarChange(Sender: TObject);
begin
  Inc(FChanges);
end;
procedure TTyScrollBarDragTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FBar := TTyScrollBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Kind := sbVertical;
  FBar.SetBounds(0, 0, 16, 200);
  FBar.Min := 0;
  FBar.Max := 100;
  FBar.PageSize := 25;
  FBar.Position := 0;
  FChanges := 0;
  FBar.OnChange := @OnBarChange;
end;
procedure TTyScrollBarDragTest.TearDown;
begin
  FForm.Free;
end;
procedure TTyScrollBarDragTest.TestDragMovesPosition;
begin
  // grab at thumb top (y=0), drag down by 80px = half of free space (160) -> pos 50
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(80);
  AssertEquals('drag of half free-space moves to mid position', 50, FBar.Position);
end;
procedure TTyScrollBarDragTest.TestDragFiresOnChange;
begin
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(80);
  AssertTrue('OnChange fired at least once during drag', FChanges >= 1);
end;
procedure TTyScrollBarDragTest.TestDragClampsAtMax;
begin
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(10000);
  AssertEquals('drag past end clamps at Max', 100, FBar.Position);
end;
initialization
  RegisterTest(TTyScrollGeometryTest);
  RegisterTest(TTyScrollBarDragTest);
end.
