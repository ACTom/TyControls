unit test.buttongroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, Types, Forms, Controls, Graphics,
  BGRABitmap,
  tyControls.Base, tyControls.ButtonGroup, tyControls.Types, tyControls.Controller;
type
  // Expose the protected SelectAt/RenderTo seams for headless testing.
  TTyButtonGroupAccess = class(TTyButtonGroup)
  public
    procedure DoSelectAt(AX: Integer);
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function StyleKey: string;
  end;

  TButtonGroupTest = class(TTestCase)
  private
    FChanged: Integer;
    procedure HandleChange(Sender: TObject);
  published
    procedure TestTypeKey;
    procedure TestDefaultSize;
    procedure TestSegmentAtBasics;
    procedure TestSegmentAtOutOfRange;
    procedure TestSegmentRectTilesWidth;
    procedure TestSegmentRectOutOfRange;
    procedure TestSingleSelectClickFiresOnce;
    procedure TestSingleSelectNoOpDoesNotFire;
    procedure TestMultiSelectRoundTrip;
    procedure TestMultiSelectToggleFires;
    procedure TestPaintSmokeEmpty;
    procedure TestPaintSmokePopulated;
  end;
implementation

procedure TTyButtonGroupAccess.DoSelectAt(AX: Integer);
begin
  SelectAt(AX);
end;

procedure TTyButtonGroupAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

function TTyButtonGroupAccess.StyleKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TButtonGroupTest.HandleChange(Sender: TObject);
begin
  Inc(FChanged);
end;

procedure TButtonGroupTest.TestTypeKey;
var G: TTyButtonGroupAccess;
begin
  G := TTyButtonGroupAccess.Create(nil);
  try
    // REUSE the button token — no new .tycss rule.
    AssertEquals('TyButton', G.StyleKey);
    AssertEquals('TyButton', (G as ITyStyleable).GetStyleTypeKey);
  finally
    G.Free;
  end;
end;

procedure TButtonGroupTest.TestDefaultSize;
var G: TTyButtonGroup;
begin
  G := TTyButtonGroup.Create(nil);
  try
    AssertEquals('default width', 240, G.Width);
    AssertEquals('default height', 30, G.Height);
    AssertFalse('MultiSelect default False', G.MultiSelect);
    AssertEquals('ItemIndex default -1', -1, G.ItemIndex);
    AssertTrue('ItemIndex published', IsPublishedProp(G, 'ItemIndex'));
    AssertTrue('MultiSelect published', IsPublishedProp(G, 'MultiSelect'));
    AssertTrue('Items published', IsPublishedProp(G, 'Items'));
  finally
    G.Free;
  end;
end;

procedure TButtonGroupTest.TestSegmentAtBasics;
begin
  // 3 segments across width 300 -> equal 100px slices.
  AssertEquals('x=50 -> seg 0', 0, TySegmentAt(50, 300, 3));
  AssertEquals('x=150 -> seg 1', 1, TySegmentAt(150, 300, 3));
  AssertEquals('x=250 -> seg 2', 2, TySegmentAt(250, 300, 3));
  // Slice boundaries: [0,100)->0, [100,200)->1, [200,300)->2.
  AssertEquals('x=0 -> seg 0', 0, TySegmentAt(0, 300, 3));
  AssertEquals('x=99 -> seg 0', 0, TySegmentAt(99, 300, 3));
  AssertEquals('x=100 -> seg 1', 1, TySegmentAt(100, 300, 3));
  AssertEquals('x=299 -> seg 2 (last)', 2, TySegmentAt(299, 300, 3));
end;

procedure TButtonGroupTest.TestSegmentAtOutOfRange;
begin
  AssertEquals('x<0 -> -1', -1, TySegmentAt(-1, 300, 3));
  AssertEquals('x=width -> -1', -1, TySegmentAt(300, 300, 3));
  AssertEquals('x>width -> -1', -1, TySegmentAt(999, 300, 3));
  AssertEquals('empty count -> -1', -1, TySegmentAt(50, 300, 0));
  AssertEquals('negative count -> -1', -1, TySegmentAt(50, 300, -2));
  AssertEquals('zero width -> -1', -1, TySegmentAt(50, 0, 3));
end;

procedure TButtonGroupTest.TestSegmentRectTilesWidth;
var
  n, W, H, i: Integer;
  r, prev: TRect;
begin
  // Rects must tile the width with no gaps/overlaps and cover [0,W) x [0,H); the
  // last cell absorbs the integer-division remainder. Use 301 (indivisible by 4).
  W := 301; H := 30; n := 4;
  prev := Rect(0, 0, 0, 0);
  for i := 0 to n - 1 do
  begin
    r := TySegmentRect(i, W, H, n);
    AssertEquals('seg ' + IntToStr(i) + ' top = 0', 0, r.Top);
    AssertEquals('seg ' + IntToStr(i) + ' bottom = H', H, r.Bottom);
    if i = 0 then
      AssertEquals('first seg starts at 0', 0, r.Left)
    else
      AssertEquals('seg ' + IntToStr(i) + ' left abuts prev right (no gap/overlap)',
        prev.Right, r.Left);
    AssertTrue('seg ' + IntToStr(i) + ' has positive width', r.Right > r.Left);
    prev := r;
  end;
  // Last cell reaches the full width exactly (absorbs the +1 rounding remainder).
  AssertEquals('last seg right = W (absorbs remainder)', W, prev.Right);
end;

procedure TButtonGroupTest.TestSegmentRectOutOfRange;
var r: TRect;
begin
  r := TySegmentRect(-1, 300, 30, 3);
  AssertTrue('index < 0 -> empty rect', (r.Right - r.Left) = 0);
  r := TySegmentRect(3, 300, 30, 3);
  AssertTrue('index >= count -> empty rect', (r.Right - r.Left) = 0);
  r := TySegmentRect(0, 300, 30, 0);
  AssertTrue('count 0 -> empty rect', (r.Right - r.Left) = 0);
end;

procedure TButtonGroupTest.TestSingleSelectClickFiresOnce;
var G: TTyButtonGroupAccess;
begin
  FChanged := 0;
  G := TTyButtonGroupAccess.Create(nil);
  try
    G.Items.Add('A'); G.Items.Add('B'); G.Items.Add('C');
    G.Width := 300;
    G.OnSelectionChange := @HandleChange;
    AssertEquals('starts unselected', -1, G.ItemIndex);
    // A click at x=150 (in a 300px/3 group) selects segment 1.
    G.DoSelectAt(150);
    AssertEquals('click selected seg 1', 1, G.ItemIndex);
    AssertEquals('OnSelectionChange fired once', 1, FChanged);
    // Selecting a DIFFERENT segment fires again.
    G.DoSelectAt(250);
    AssertEquals('click selected seg 2', 2, G.ItemIndex);
    AssertEquals('OnSelectionChange fired again', 2, FChanged);
  finally
    G.Free;
  end;
end;

procedure TButtonGroupTest.TestSingleSelectNoOpDoesNotFire;
var G: TTyButtonGroupAccess;
begin
  FChanged := 0;
  G := TTyButtonGroupAccess.Create(nil);
  try
    G.Items.Add('A'); G.Items.Add('B'); G.Items.Add('C');
    G.Width := 300;
    G.ItemIndex := 1;             // select via property (also fires; reset counter after)
    G.OnSelectionChange := @HandleChange;
    FChanged := 0;
    // Clicking the ALREADY-selected segment must NOT fire (no-op).
    G.DoSelectAt(150);
    AssertEquals('same-segment click is a no-op', 1, G.ItemIndex);
    AssertEquals('no-op does not fire', 0, FChanged);
    // Setting ItemIndex to its current value is likewise a no-op.
    G.ItemIndex := 1;
    AssertEquals('same ItemIndex set does not fire', 0, FChanged);
  finally
    G.Free;
  end;
end;

procedure TButtonGroupTest.TestMultiSelectRoundTrip;
var G: TTyButtonGroup;
begin
  G := TTyButtonGroup.Create(nil);
  try
    G.MultiSelect := True;
    G.Items.Add('A'); G.Items.Add('B'); G.Items.Add('C');
    AssertFalse('none selected initially', G.IsSelected(0));
    G.SetSelected(0, True);
    G.SetSelected(2, True);
    AssertTrue('seg 0 selected', G.IsSelected(0));
    AssertFalse('seg 1 not selected', G.IsSelected(1));
    AssertTrue('seg 2 selected', G.IsSelected(2));
    G.SetSelected(0, False);
    AssertFalse('seg 0 cleared', G.IsSelected(0));
    AssertTrue('seg 2 still selected', G.IsSelected(2));
    // Out-of-range is safe.
    AssertFalse('out-of-range -> False', G.IsSelected(9));
    G.SetSelected(9, True);   // no crash, no effect
  finally
    G.Free;
  end;
end;

procedure TButtonGroupTest.TestMultiSelectToggleFires;
var G: TTyButtonGroupAccess;
begin
  FChanged := 0;
  G := TTyButtonGroupAccess.Create(nil);
  try
    G.MultiSelect := True;
    G.Items.Add('A'); G.Items.Add('B'); G.Items.Add('C');
    G.Width := 300;
    G.OnSelectionChange := @HandleChange;
    // A click toggles that segment ON and fires.
    G.DoSelectAt(50);   // seg 0
    AssertTrue('seg 0 toggled on', G.IsSelected(0));
    AssertEquals('toggle on fired', 1, FChanged);
    // Clicking the same segment toggles it OFF and fires again.
    G.DoSelectAt(50);
    AssertFalse('seg 0 toggled off', G.IsSelected(0));
    AssertEquals('toggle off fired', 2, FChanged);
    // SetSelected to the SAME value is a no-op (does not fire).
    G.SetSelected(1, False);
    AssertEquals('no-op SetSelected does not fire', 2, FChanged);
    G.SetSelected(1, True);
    AssertEquals('real SetSelected fires', 3, FChanged);
  finally
    G.Free;
  end;
end;

procedure TButtonGroupTest.TestPaintSmokeEmpty;
var
  F: TCustomForm; G: TTyButtonGroupAccess; Bmp: TBitmap;
begin
  // 0 items: paint must not crash (headless-safe).
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    G := TTyButtonGroupAccess.Create(F);
    G.Parent := F;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 30);
    G.RenderTo(Bmp.Canvas, Rect(0, 0, 240, 30), 96);
    AssertTrue('empty group RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

procedure TButtonGroupTest.TestPaintSmokePopulated;
var
  F: TCustomForm; G: TTyButtonGroupAccess; Bmp: TBitmap;
begin
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    G := TTyButtonGroupAccess.Create(F);
    G.Parent := F;
    G.Items.Add('One'); G.Items.Add('Two'); G.Items.Add('Three');
    G.ItemIndex := 1;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 30);
    G.RenderTo(Bmp.Canvas, Rect(0, 0, 240, 30), 96);
    AssertTrue('populated group RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

initialization
  RegisterTest(TButtonGroupTest);
end.
