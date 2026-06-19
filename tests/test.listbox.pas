unit test.listbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller,
  tyControls.Base, tyControls.ListBox, tyControls.ScrollBar;
type
  TTyListBoxTest = class(TTestCase)
  private
    FForm: TForm;
    FList: TTyListBox;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestItemsOwnedAndLive;
    procedure TestSelectItemFiresOnChangeOnce;
    procedure TestSelectOutOfRangeClears;
    procedure TestKeyboardMovesSelection;
    procedure TestVisibleRowsMath;
    procedure TestTopIndexFollowsSelection;
    procedure TestTopIndexClamps;
    procedure TestWheelScrolls;
    procedure TestSelectedRowRendersActiveStyle;
    procedure TestSelectedRowRoundedCorners;
    procedure TestScrollBarAppearsWhenOverflow;
    procedure TestScrollBarSyncsTopIndex;
    procedure TestItemsShrinkClampsTopIndex;
    procedure TestDisabledKeyIgnored;
    procedure TestEmbeddedScrollbarDragScrollsList;
    procedure TestMultiSelectSelectedAndSelCount;
    procedure TestSingleSelectSelectedReflectsItemIndex;
    procedure TestClearSelectionNoOpInSingle;
    procedure TestMultiSelectMouseClicks;
    procedure TestPageKeysSingleSelect;
    procedure TestMultiSelectShiftDownExtends;
    procedure TestSpaceNotConsumedInSingleSelect;
    procedure TestSortedSortsAndKeepsSelection;
    procedure TestSortedKeepsMultiSelection;
  end;

  { A2 regression: embedded scrollbar must inherit controller and DPI width }
  TTyListBoxScrollBarPropTest = class(TTestCase)
  published
    procedure TestScrollBarInheritsController;
    procedure TestScrollBarWidthUpdatesOnDPIChange;
  end;
implementation

type
  TListBoxAccess = class(TTyListBox)
  public
    function StyleTypeKey: string;
    procedure CallDoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint);
    procedure CallUpdateScrollBar;
    function FindScrollBar: TTyScrollBar;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoMouseDown(Shift: TShiftState; X, Y: Integer);
    procedure DoKeyDown(Key: Word; Shift: TShiftState);
    function PressKey(Key: Word; Shift: TShiftState): Word;
  end;

  { Hard-cast target to drive the embedded scrollbar's protected mouse handlers. }
  TScrollBarAccess = class(TTyScrollBar)
  public
    procedure CallMouseDown(Btn: TMouseButton; X, Y: Integer);
    procedure CallMouseMove(X, Y: Integer);
    procedure CallMouseUp(Btn: TMouseButton; X, Y: Integer);
  end;

  TChangeProbe = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

procedure TScrollBarAccess.CallMouseDown(Btn: TMouseButton; X, Y: Integer);
begin
  MouseDown(Btn, [], X, Y);
end;

procedure TScrollBarAccess.CallMouseMove(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TScrollBarAccess.CallMouseUp(Btn: TMouseButton; X, Y: Integer);
begin
  MouseUp(Btn, [], X, Y);
end;

procedure TChangeProbe.Handle(Sender: TObject);
begin
  Inc(Count);
end;

function TListBoxAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TListBoxAccess.CallDoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint);
begin
  DoMouseWheel(Shift, WheelDelta, MousePos);
end;

procedure TListBoxAccess.CallUpdateScrollBar;
begin
  UpdateScrollBar;
end;

function TListBoxAccess.FindScrollBar: TTyScrollBar;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to ControlCount - 1 do
    if Controls[I] is TTyScrollBar then
    begin
      Result := TTyScrollBar(Controls[I]);
      Exit;
    end;
end;

procedure TListBoxAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TListBoxAccess.DoMouseDown(Shift: TShiftState; X, Y: Integer);
begin
  MouseDown(mbLeft, Shift, X, Y);
end;

procedure TListBoxAccess.DoKeyDown(Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

function TListBoxAccess.PressKey(Key: Word; Shift: TShiftState): Word;
begin
  KeyDown(Key, Shift);
  Result := Key;
end;

{ TTyListBoxTest }

procedure TTyListBoxTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FList := TTyListBox.Create(FForm);
  FList.Parent := FForm;
  // Pin the PPI: on macOS Font.PixelsPerInch defaults to 72, which would
  // scale ItemHeight 24 -> 18 and change VisibleRows; the geometry tests
  // assume 96ppi (scale factor 1).
  FList.Font.PixelsPerInch := 96;
end;

procedure TTyListBoxTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyListBoxTest.TestTypeKey;
var
  Acc: TListBoxAccess;
begin
  Acc := TListBoxAccess.Create(FForm);
  Acc.Parent := FForm;
  try
    AssertEquals('TyListBox', Acc.StyleTypeKey);
  finally
    Acc.Free;
  end;
end;

procedure TTyListBoxTest.TestItemsOwnedAndLive;
begin
  FList.Items.Add('Alpha');
  FList.Items.Add('Beta');
  FList.Items.Add('Gamma');
  AssertEquals('items count after 3 adds', 3, FList.Items.Count);
  AssertEquals('item 0', 'Alpha', FList.Items[0]);
  AssertEquals('item 1', 'Beta', FList.Items[1]);
  AssertEquals('item 2', 'Gamma', FList.Items[2]);
end;

procedure TTyListBoxTest.TestSelectItemFiresOnChangeOnce;
var
  Probe: TChangeProbe;
begin
  FList.Items.Add('One');
  FList.Items.Add('Two');
  Probe := TChangeProbe.Create;
  try
    FList.OnChange := @Probe.Handle;
    FList.SelectItem(0);
    AssertEquals('OnChange fires once on real change', 1, Probe.Count);
    FList.SelectItem(0);
    AssertEquals('OnChange does not fire when index unchanged', 1, Probe.Count);
    FList.SelectItem(1);
    AssertEquals('OnChange fires on second real change', 2, Probe.Count);
  finally
    Probe.Free;
  end;
end;

procedure TTyListBoxTest.TestSelectOutOfRangeClears;
begin
  FList.Items.Add('One');
  FList.Items.Add('Two');
  FList.SelectItem(0);
  AssertEquals('index 0 selected', 0, FList.ItemIndex);
  FList.SelectItem(99);
  AssertEquals('out-of-range clears to -1', -1, FList.ItemIndex);
  FList.SelectItem(-5);
  AssertEquals('negative index clears to -1', -1, FList.ItemIndex);
end;

procedure TTyListBoxTest.TestKeyboardMovesSelection;
var
  I: Integer;
begin
  for I := 0 to 4 do
    FList.Items.Add(IntToStr(I));
  AssertEquals('initial ItemIndex', -1, FList.ItemIndex);

  // DOWN from -1 selects 0
  FList.SimulateKeyDown(VK_DOWN);
  AssertEquals('DOWN from -1 -> 0', 0, FList.ItemIndex);

  // DOWN again -> 1
  FList.SimulateKeyDown(VK_DOWN);
  AssertEquals('DOWN -> 1', 1, FList.ItemIndex);

  // UP -> 0
  FList.SimulateKeyDown(VK_UP);
  AssertEquals('UP -> 0', 0, FList.ItemIndex);

  // END -> last (4)
  FList.SimulateKeyDown(VK_END);
  AssertEquals('END -> 4', 4, FList.ItemIndex);

  // HOME -> first (0)
  FList.SimulateKeyDown(VK_HOME);
  AssertEquals('HOME -> 0', 0, FList.ItemIndex);

  // UP at 0 stays at 0
  FList.SimulateKeyDown(VK_UP);
  AssertEquals('UP clamps at 0', 0, FList.ItemIndex);

  // DOWN to end, then DOWN again clamps
  FList.SelectItem(4);
  FList.SimulateKeyDown(VK_DOWN);
  AssertEquals('DOWN clamps at last', 4, FList.ItemIndex);
end;

procedure TTyListBoxTest.TestVisibleRowsMath;
var
  LB: TTyListBox;
begin
  // Height = 100, ItemHeight = 24 @96ppi -> 100 div 24 = 4
  // Create without parent to avoid LCL cocoa geometry constraints
  LB := TTyListBox.Create(nil);
  try
    LB.Font.PixelsPerInch := 96;  // pin (macOS defaults to 72)
    LB.ItemHeight := 24;
    LB.Height := 100;
    // VisibleRows uses Height div MulDiv(ItemHeight, PPI, 96)
    // At 96ppi (default on test platform), MulDiv(24, 96, 96) = 24; 100 div 24 = 4
    AssertEquals('VisibleRows = 4 for height 100, itemheight 24@96ppi', 4, LB.VisibleRows);
  finally
    LB.Free;
  end;
end;

procedure TTyListBoxTest.TestTopIndexFollowsSelection;
var
  I: Integer;
begin
  for I := 0 to 9 do
    FList.Items.Add(IntToStr(I));
  FList.ItemHeight := 24;
  FList.Height := 100;
  // VisibleRows = 4; select item 9 -> TopIndex should be 9 - 4 + 1 = 6
  FList.SelectItem(9);
  AssertEquals('TopIndex after select 9 with 4 visible rows', 6, FList.TopIndex);
  // select item 0 -> TopIndex should be 0
  FList.SelectItem(0);
  AssertEquals('TopIndex after select 0', 0, FList.TopIndex);
end;

procedure TTyListBoxTest.TestTopIndexClamps;
var
  I: Integer;
begin
  for I := 0 to 9 do
    FList.Items.Add(IntToStr(I));
  FList.ItemHeight := 24;
  FList.Height := 100;
  // Max TopIndex = Max(0, Items.Count - VisibleRows) = Max(0, 10 - 4) = 6
  FList.TopIndex := 999;
  AssertEquals('TopIndex clamps to max (6)', 6, FList.TopIndex);
  FList.TopIndex := -5;
  AssertEquals('TopIndex clamps to 0', 0, FList.TopIndex);
end;

procedure TTyListBoxTest.TestWheelScrolls;
var
  Acc: TListBoxAccess;
  I: Integer;
  Pt: TPoint;
begin
  // Use access subclass to call DoMouseWheel
  Acc := TListBoxAccess.Create(FForm);
  Acc.Parent := FForm;
  for I := 0 to 9 do
    Acc.Items.Add(IntToStr(I));
  Acc.ItemHeight := 24;
  Acc.Height := 100;
  Acc.TopIndex := 0;
  AssertEquals('TopIndex starts at 0', 0, Acc.TopIndex);
  // Negative WheelDelta = scroll down (content moves up = TopIndex increases)
  Pt := Point(0, 0);
  Acc.CallDoMouseWheel([], -120, Pt);
  AssertEquals('negative delta scrolls down: TopIndex 0 -> 3', 3, Acc.TopIndex);
end;

{ TestSelectedRowRendersActiveStyle
  Stylesheet: TyListBox dark bg, TyListItem:active blue.
  3 items, ItemIndex=1 (row 1 selected). Render to 120x100 bitmap @96ppi.
  Row 1 band is y=[24..48); row 0 band is y=[0..24).
  Probe (10, 36) inside row 1 -> blue dominant (B>180, R<120).
  Probe (10, 12) inside row 0 -> NOT blue dominant. }
procedure TTyListBoxTest.TestSelectedRowRendersActiveStyle;
var
  Ctl: TTyStyleController;
  LB: TListBoxAccess;
  F: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyListBox { background: #101010; border-width: 0px; } ' +
      'TyListItem { color: #CCCCCC; } ' +
      'TyListItem:active { background: #3B82F6; }');
    LB := TListBoxAccess.Create(F);
    LB.Parent := F;
    LB.Controller := Ctl;
    LB.Font.PixelsPerInch := 96;
    LB.ItemHeight := 24;
    LB.SetBounds(0, 0, 120, 100);
    LB.Items.Add('Alpha');
    LB.Items.Add('Beta');
    LB.Items.Add('Gamma');
    LB.SelectItem(1);   // row 1 = active
    LB.TopIndex := 0;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 100);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 120, 100);
    LB.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 100), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Row 1 (y=24..47): probe at (80, 36) — far right of text area, background only
      // "Beta" at 12pt is ~30px wide; x=80 is beyond the text, shows row background
      Px := Reread.GetPixel(80, 36);
      AssertTrue(Format('row1 blue dominant: B > 180 (actual R=%d G=%d B=%d)',
        [Px.red, Px.green, Px.blue]), Px.blue > 180);
      AssertTrue(Format('row1 blue dominant: R < 120 (actual R=%d G=%d B=%d)',
        [Px.red, Px.green, Px.blue]),  Px.red  < 120);
      // Row 0 (y=0..23): probe at (80, 12) — background area, not selected
      Px := Reread.GetPixel(80, 12);
      AssertTrue('row0 not blue dominant: B < R+50 or B <= 180',
        (Px.blue < 180) or (Px.blue <= Px.red + 50));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

{ TestSelectedRowRoundedCorners
  The selection bar spans the listbox INTERIOR edge-to-edge (no side gap) and is CAPPED
  to the CONTAINER's rounded corner: the first row rounds its top corners by the TyListBox
  radius so a square highlight never pokes past the rounded border.

  (a) Theme wiring: ResolveStyle('TyListBox','',[]).BorderRadius > 0.
  (b) Pixel proof: row 0 centre IS the accent fill; its LEFT EDGE at mid-row IS the accent
      fill (full width, no gap); its extreme top-left corner is NOT the accent fill (the
      rounded cap shows the listbox background there, never poking past the border). }
procedure TTyListBoxTest.TestSelectedRowRoundedCorners;
var
  Ctl: TTyStyleController;
  LB: TListBoxAccess;
  F: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxCorner, PxCenter: TBGRAPixel;
  RowTop, RowBottom, CenterY: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    // Big CONTAINER radius (12) + no border so the rounded top-left clearly exposes the
    // listbox background at the extreme corner; the selection caps to that radius.
    Ctl.LoadThemeCss(
      'TyListBox { background: #101010; border-width: 0px; border-radius: 12px; padding: 2px; } ' +
      'TyListItem { color: #CCCCCC; } ' +
      'TyListItem:active { background: #3B82F6; }');

    // (a) theme wiring — the CONTAINER radius drives the end-row cap now.
    AssertTrue('TyListBox border-radius wired (>0)',
      Ctl.Model.ResolveStyle('TyListBox', '', []).BorderRadius > 0);

    LB := TListBoxAccess.Create(F);
    LB.Parent := F;
    LB.Controller := Ctl;
    LB.Font.PixelsPerInch := 96;
    LB.ItemHeight := 24;
    LB.SetBounds(0, 0, 120, 100);
    LB.Items.Add('Alpha');
    LB.Items.Add('Beta');
    LB.Items.Add('Gamma');
    LB.SelectItem(0);   // row 0 = active (first item -> top corners capped)
    LB.TopIndex := 0;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 100);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 120, 100);
    LB.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 100), 96);

    CenterY := 13;                  // mid row 0 (content top padding 2 + half of 24)

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Centre of the row (well away from text at x=80) must be the accent fill.
      PxCenter := Reread.GetPixel(80, CenterY);
      AssertTrue(Format('row0 centre is accent fill (R=%d G=%d B=%d)',
        [PxCenter.red, PxCenter.green, PxCenter.blue]),
        (PxCenter.blue > 180) and (PxCenter.red < 120));

      // Single padding inset (no big side gap): x=4 at mid-row — solid accent now, whereas
      // the OLD double inset started the fill at x=4 (only an AA edge there). LEFT of the
      // text glyphs, below the corner curve.
      PxCenter := Reread.GetPixel(4, CenterY);
      AssertTrue(Format('row0 left reaches single-inset edge (R=%d G=%d B=%d)',
        [PxCenter.red, PxCenter.green, PxCenter.blue]),
        (PxCenter.blue > 180) and (PxCenter.red < 120));

      // Capped: the extreme top-left corner is rounded to the container (and the fill is
      // inset by the padding), so it is NOT the accent fill — never poking past the border.
      PxCorner := Reread.GetPixel(0, 0);
      AssertFalse(Format('row0 top-left corner NOT accent (capped) (R=%d G=%d B=%d)',
        [PxCorner.red, PxCorner.green, PxCorner.blue]),
        (PxCorner.blue > 180) and (PxCorner.red < 120));
    finally
      Reread.Free;
    end;

    // Issue 2: a SHORT list (3 rows in a 100px box) must NOT let the last item's highlight
    // bleed into the empty space below it. Select the last item, re-render, and check the
    // empty area below the rows is the listbox background, not the accent fill.
    LB.SelectItem(2);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 120, 100);
    LB.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 100), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      // Rows end at y = 2 + 3*24 = 74; sample well below that (y=85) in the empty band.
      PxCenter := Reread.GetPixel(80, 85);
      AssertFalse(Format('empty space below last item NOT accent (R=%d G=%d B=%d)',
        [PxCenter.red, PxCenter.green, PxCenter.blue]),
        (PxCenter.blue > 180) and (PxCenter.red < 120));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

{ TestScrollBarAppearsWhenOverflow
  10 items, height=100 (4 visible rows) -> scrollbar child exists and Visible.
  Reduce to 3 items -> scrollbar not visible. }
procedure TTyListBoxTest.TestScrollBarAppearsWhenOverflow;
var
  LB: TListBoxAccess;
  F: TForm;
  SB: TTyScrollBar;
  I: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    LB := TListBoxAccess.Create(F);
    LB.Parent := F;
    LB.Font.PixelsPerInch := 96;
    LB.ItemHeight := 24;
    LB.SetBounds(0, 0, 120, 100);  // 4 visible rows
    for I := 0 to 9 do
      LB.Items.Add('Item ' + IntToStr(I));
    LB.CallUpdateScrollBar;
    SB := LB.FindScrollBar;
    AssertNotNull('scrollbar child exists when overflow', SB);
    AssertTrue('scrollbar visible when overflow', SB.Visible);

    // Reduce items to 3 (< 4 visible rows)
    LB.Items.Clear;
    LB.Items.Add('A');
    LB.Items.Add('B');
    LB.Items.Add('C');
    LB.CallUpdateScrollBar;
    // Scrollbar should now be hidden (it may or may not be freed, but must be invisible)
    SB := LB.FindScrollBar;
    if SB <> nil then
      AssertFalse('scrollbar hidden when not overflow', SB.Visible)
    else
      AssertTrue('scrollbar absent when not overflow: ok', True);
  finally
    F.Free;
  end;
end;

{ TestScrollBarSyncsTopIndex
  Overflow setup (10 items, 4 rows).
  Set scrollbar Position := 3 -> TopIndex = 3.
  Set TopIndex := 0 -> scrollbar Position = 0. }
procedure TTyListBoxTest.TestScrollBarSyncsTopIndex;
var
  LB: TListBoxAccess;
  F: TForm;
  SB: TTyScrollBar;
  I: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    LB := TListBoxAccess.Create(F);
    LB.Parent := F;
    LB.Font.PixelsPerInch := 96;
    LB.ItemHeight := 24;
    LB.SetBounds(0, 0, 120, 100);  // 4 visible rows
    for I := 0 to 9 do
      LB.Items.Add('Item ' + IntToStr(I));
    LB.CallUpdateScrollBar;
    SB := LB.FindScrollBar;
    AssertNotNull('scrollbar present', SB);

    // Moving scrollbar changes TopIndex
    SB.Position := 3;
    AssertEquals('scrollbar pos 3 -> TopIndex = 3', 3, LB.TopIndex);

    // Moving TopIndex changes scrollbar
    LB.TopIndex := 0;
    AssertEquals('TopIndex 0 -> scrollbar pos = 0', 0, SB.Position);
  finally
    F.Free;
  end;
end;

{ TestItemsShrinkClampsTopIndex
  Setup: 10 items, height=100 (4 visible rows), TopIndex=6.
  Then: Items.Clear, add 3 items, CallUpdateScrollBar.
  With 3 items and 4 visible rows, MaxTop=0 → TopIndex must be clamped to 0. }
procedure TTyListBoxTest.TestItemsShrinkClampsTopIndex;
var
  LB: TListBoxAccess;
  F: TForm;
  I: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    LB := TListBoxAccess.Create(F);
    LB.Parent := F;
    LB.Font.PixelsPerInch := 96;
    LB.ItemHeight := 24;
    LB.SetBounds(0, 0, 160, 100);  // VisibleRows = 4
    for I := 0 to 9 do
      LB.Items.Add('item' + IntToStr(I));
    LB.CallUpdateScrollBar;
    LB.TopIndex := 6;  // max valid for 10 items, 4 rows
    AssertEquals('TopIndex=6 before shrink', 6, LB.TopIndex);

    // Mutate items directly (bypassing SetItems)
    LB.Items.Clear;
    LB.Items.Add('a');
    LB.Items.Add('b');
    LB.Items.Add('c');
    // Now 3 items, 4 rows -> MaxTop=0; FTopIndex is still stale at 6
    LB.CallUpdateScrollBar;

    AssertEquals('TopIndex clamped to 0 after shrink to 3 items', 0, LB.TopIndex);
  finally
    F.Free;
  end;
end;

procedure TTyListBoxTest.TestDisabledKeyIgnored;
var
  I: Integer;
begin
  for I := 0 to 4 do
    FList.Items.Add(IntToStr(I));
  FList.SelectItem(0);
  AssertEquals('ItemIndex 0 before disable', 0, FList.ItemIndex);
  FList.Enabled := False;
  // VK_DOWN would normally move ItemIndex to 1
  FList.SimulateKeyDown(VK_DOWN);
  AssertEquals('disabled listbox arrow key ignored', 0, FList.ItemIndex);
end;

{ TestEmbeddedScrollbarDragScrollsList
  Overflow listbox (20 items, 4 visible rows). Drive the embedded scrollbar's
  mouse handlers (down on the thumb, move toward the bottom of the track, up)
  and assert ListBox.TopIndex follows the scrollbar drag via the OnChange sync.
  This is the regression that the dead mouse handling previously broke: before
  the fix the scrollbar's Position never moved on mouse, so TopIndex stayed 0. }
procedure TTyListBoxTest.TestEmbeddedScrollbarDragScrollsList;
var
  LB: TListBoxAccess;
  F: TForm;
  SB: TTyScrollBar;
  SBA: TScrollBarAccess;
  I, ThumbCenterY: Integer;
  ThumbR, TrackR: TRect;
begin
  F := TForm.CreateNew(nil);
  try
    LB := TListBoxAccess.Create(F);
    LB.Parent := F;
    LB.Font.PixelsPerInch := 96;
    LB.ItemHeight := 24;
    LB.SetBounds(0, 0, 120, 100);  // 4 visible rows
    for I := 0 to 19 do
      LB.Items.Add('Item ' + IntToStr(I));
    LB.CallUpdateScrollBar;
    SB := LB.FindScrollBar;
    AssertNotNull('scrollbar present for overflow list', SB);
    AssertTrue('scrollbar visible for overflow list', SB.Visible);
    AssertEquals('TopIndex starts at 0', 0, LB.TopIndex);

    // Drive a drag from the thumb toward the bottom of the scrollbar's track.
    SBA := TScrollBarAccess(SB);
    TrackR := SB.ClientRect;
    ThumbR := TyScrollThumbRect(TrackR, sbVertical, SB.Min, SB.Max,
      SB.Position, SB.PageSize);
    ThumbCenterY := (ThumbR.Top + ThumbR.Bottom) div 2;

    SBA.CallMouseDown(mbLeft, SB.Width div 2, ThumbCenterY);
    SBA.CallMouseMove(SB.Width div 2, TrackR.Bottom - 1);
    SBA.CallMouseUp(mbLeft, SB.Width div 2, TrackR.Bottom - 1);

    // Scrollbar should now be near its Max, and TopIndex must follow it.
    AssertTrue(Format('scrollbar Position advanced toward Max (actual %d, max %d)',
      [SB.Position, SB.Max]), SB.Position >= SB.Max - 1);
    AssertEquals('list TopIndex follows scrollbar Position', SB.Position, LB.TopIndex);
    AssertTrue(Format('list scrolled substantially via scrollbar drag (TopIndex %d)',
      [LB.TopIndex]), LB.TopIndex > 0);
  finally
    F.Free;
  end;
end;

{ TTyListBoxScrollBarPropTest }

{ TestScrollBarInheritsController
  A2 regression: after UpdateScrollBar the embedded scrollbar's Controller
  must equal the listbox's Controller (not nil from stale creation-time value).

  Setup: 10-item listbox (needs scrollbar), assign a fresh TTyStyleController,
  call CallUpdateScrollBar, assert FindScrollBar.Controller = the controller. }
procedure TTyListBoxScrollBarPropTest.TestScrollBarInheritsController;
var
  Ctl: TTyStyleController;
  LB: TListBoxAccess;
  F: TForm;
  SB: TTyScrollBar;
  I: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  try
    LB := TListBoxAccess.Create(F);
    LB.Parent := F;
    LB.Font.PixelsPerInch := 96;
    LB.ItemHeight := 24;
    LB.SetBounds(0, 0, 120, 100);
    for I := 0 to 9 do
      LB.Items.Add('Item ' + IntToStr(I));
    { Assign controller BEFORE UpdateScrollBar so we test the propagation path }
    LB.Controller := Ctl;
    LB.CallUpdateScrollBar;
    SB := LB.FindScrollBar;
    AssertNotNull('scrollbar must exist for overflow list', SB);
    AssertTrue('embedded scrollbar Controller must equal listbox Controller',
      SB.Controller = Ctl);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ TestScrollBarWidthUpdatesOnDPIChange
  A2 regression: scrollbar width must be recomputed on every UpdateScrollBar call
  so a DPI change takes effect without a recreation.

  Simulate DPI change by changing Font.PixelsPerInch from 96 to 192, then call
  CallUpdateScrollBar, and assert the scrollbar width = MulDiv(12, 192, 96) = 24. }
procedure TTyListBoxScrollBarPropTest.TestScrollBarWidthUpdatesOnDPIChange;
var
  LB: TListBoxAccess;
  F: TForm;
  SB: TTyScrollBar;
  I: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    LB := TListBoxAccess.Create(F);
    LB.Parent := F;
    LB.Font.PixelsPerInch := 96;
    LB.ItemHeight := 24;
    LB.SetBounds(0, 0, 120, 100);
    for I := 0 to 9 do
      LB.Items.Add('Item ' + IntToStr(I));
    LB.CallUpdateScrollBar;
    SB := LB.FindScrollBar;
    AssertNotNull('scrollbar must exist', SB);
    AssertEquals('scrollbar width at 96 ppi = 12', 12, SB.Width);

    { Simulate DPI change to 192 ppi }
    LB.Font.PixelsPerInch := 192;
    LB.CallUpdateScrollBar;
    AssertEquals('scrollbar width at 192 ppi = 24', 24, SB.Width);
  finally
    F.Free;
  end;
end;

procedure TTyListBoxTest.TestMultiSelectSelectedAndSelCount;
begin
  FList.Items.Clear;
  FList.Items.Add('a'); FList.Items.Add('b'); FList.Items.Add('c'); FList.Items.Add('d');
  FList.MultiSelect := True;
  AssertEquals('empty selcount', 0, FList.SelCount);
  FList.Selected[1] := True;
  FList.Selected[3] := True;
  AssertTrue('1 selected', FList.Selected[1]);
  AssertFalse('0 not selected', FList.Selected[0]);
  AssertEquals('selcount 2', 2, FList.SelCount);
  FList.Selected[1] := False;
  AssertEquals('selcount 1', 1, FList.SelCount);
  FList.SelectAll;
  AssertEquals('select all', 4, FList.SelCount);
  FList.ClearSelection;
  AssertEquals('cleared', 0, FList.SelCount);
end;

procedure TTyListBoxTest.TestSingleSelectSelectedReflectsItemIndex;
begin
  FList.Items.Clear; FList.Items.Add('a'); FList.Items.Add('b');
  FList.MultiSelect := False;
  FList.ItemIndex := 1;
  AssertTrue('Selected[1] true in single', FList.Selected[1]);
  AssertFalse('Selected[0] false', FList.Selected[0]);
  AssertEquals('selcount 1 in single', 1, FList.SelCount);
  FList.SelectAll;   // no-op in single mode
  AssertEquals('SelectAll no-op single', 1, FList.SelCount);
end;

procedure TTyListBoxTest.TestClearSelectionNoOpInSingle;
begin
  FList.Items.Clear; FList.Items.Add('a'); FList.Items.Add('b');
  FList.MultiSelect := False;
  FList.ItemIndex := 1;
  FList.ClearSelection;                 // no-op in single mode
  AssertEquals('single ItemIndex unchanged by ClearSelection', 1, FList.ItemIndex);
  AssertEquals('selcount still 1', 1, FList.SelCount);
end;

procedure TTyListBoxTest.TestMultiSelectMouseClicks;
var LA: TListBoxAccess;
begin
  LA := TListBoxAccess.Create(FForm); LA.Parent := FForm;
  LA.Font.PixelsPerInch := 96; LA.SetBounds(0,0,160,240);
  LA.Items.Add('0'); LA.Items.Add('1'); LA.Items.Add('2'); LA.Items.Add('3'); LA.Items.Add('4');
  LA.MultiSelect := True;
  LA.DoMouseDown([], 5, 1*24+2);                 // plain click row 1
  AssertEquals('plain click selects 1', 1, LA.SelCount);
  AssertTrue('row1 selected', LA.Selected[1]);
  LA.DoMouseDown([ssCtrl], 5, 3*24+2);           // ctrl-click row 3 -> add
  AssertEquals('ctrl adds -> 2', 2, LA.SelCount);
  AssertTrue('row3 selected', LA.Selected[3]);
  AssertTrue('row1 still selected', LA.Selected[1]);
  LA.DoMouseDown([ssShift], 5, 4*24+2);          // shift-click row 4 -> range anchor(3)..4
  AssertTrue('row3..4 selected', LA.Selected[3] and LA.Selected[4]);
  AssertFalse('row1 cleared by shift-range', LA.Selected[1]);
  LA.DoMouseDown([], 5, 0*24+2);                 // plain click row 0 -> only 0
  AssertEquals('plain resets to 1', 1, LA.SelCount);
  AssertTrue('row0', LA.Selected[0]);
end;

procedure TTyListBoxTest.TestPageKeysSingleSelect;
var LA: TListBoxAccess; i: Integer;
begin
  LA := TListBoxAccess.Create(FForm); LA.Parent := FForm;
  LA.Font.PixelsPerInch := 96; LA.SetBounds(0,0,160,120);  // 120/24 = 5 visible rows
  for i := 0 to 19 do LA.Items.Add(IntToStr(i));
  LA.MultiSelect := False; LA.ItemIndex := 0;
  LA.DoKeyDown(VK_NEXT, []);                 // PageDown
  AssertEquals('pagedown +VisibleRows', LA.VisibleRows, LA.ItemIndex);
  LA.DoKeyDown(VK_PRIOR, []);                // PageUp
  AssertEquals('pageup back to 0', 0, LA.ItemIndex);
end;

// Seed the anchor with a Task-5 mouse click (anchor=focus=1), then Shift+Down extends.
procedure TTyListBoxTest.TestMultiSelectShiftDownExtends;
var LA: TListBoxAccess;
begin
  LA := TListBoxAccess.Create(FForm); LA.Parent := FForm;
  LA.Font.PixelsPerInch := 96; LA.SetBounds(0,0,160,240);
  LA.Items.Add('0'); LA.Items.Add('1'); LA.Items.Add('2'); LA.Items.Add('3');
  LA.MultiSelect := True;
  LA.DoMouseDown([], 5, 1*24+2);             // anchor=focus=1, selects {1}
  LA.DoKeyDown(VK_DOWN, [ssShift]);          // extend 1..2
  AssertTrue('1..2 selected', LA.Selected[1] and LA.Selected[2]);
  AssertFalse('3 not', LA.Selected[3]);
  LA.DoKeyDown(VK_DOWN, [ssShift]);          // extend 1..3
  AssertTrue('1..3 selected', LA.Selected[1] and LA.Selected[2] and LA.Selected[3]);
  LA.DoKeyDown(VK_SPACE, []);                // toggle focus(3) off
  AssertFalse('focus 3 toggled off', LA.Selected[3]);
end;

procedure TTyListBoxTest.TestSpaceNotConsumedInSingleSelect;
var LA: TListBoxAccess;
begin
  LA := TListBoxAccess.Create(FForm); LA.Parent := FForm;
  LA.Font.PixelsPerInch := 96; LA.SetBounds(0,0,160,120);
  LA.Items.Add('a'); LA.Items.Add('b');
  // single-select: Space must NOT be consumed (Key unchanged)
  LA.MultiSelect := False; LA.ItemIndex := 0;
  AssertEquals('single-select Space not consumed', VK_SPACE, Integer(LA.PressKey(VK_SPACE, [])));
  // multi-select: Space toggles row and consumes key (Key = 0)
  LA.MultiSelect := True; LA.ItemIndex := 0;
  AssertEquals('multi-select Space consumed', 0, Integer(LA.PressKey(VK_SPACE, [])));
  AssertTrue('multi Space toggled row 0 on', LA.Selected[0]);
end;

{ TestSortedSortsAndKeepsSelection
  Single-select: add items out of order, select one, set Sorted:=True.
  Items must be ascending (case-insensitive) and the SAME item must stay
  selected (its index re-pinned by text). No spurious OnChange. }
procedure TTyListBoxTest.TestSortedSortsAndKeepsSelection;
var
  Probe: TChangeProbe;
begin
  FList.Items.Clear;
  FList.Items.Add('Gamma');
  FList.Items.Add('Alpha');
  FList.Items.Add('Beta');
  FList.MultiSelect := False;
  FList.SelectItem(0);                         // 'Gamma' selected (index 0)
  AssertEquals('selected text before sort', 'Gamma', FList.Items[FList.ItemIndex]);

  Probe := TChangeProbe.Create;
  try
    FList.OnChange := @Probe.Handle;
    FList.Sorted := True;

    // Items now ascending
    AssertEquals('sorted item 0', 'Alpha', FList.Items[0]);
    AssertEquals('sorted item 1', 'Beta',  FList.Items[1]);
    AssertEquals('sorted item 2', 'Gamma', FList.Items[2]);

    // Same item still selected (re-pinned to its new index)
    AssertEquals('Gamma re-pinned to index 2', 2, FList.ItemIndex);
    AssertEquals('selected text unchanged after sort', 'Gamma',
      FList.Items[FList.ItemIndex]);

    // The selection (text) did not logically change -> no spurious OnChange
    AssertEquals('no spurious OnChange on index-shift', 0, Probe.Count);
  finally
    Probe.Free;
  end;
end;

{ TestSortedKeepsMultiSelection
  MultiSelect: select two items, set Sorted:=True, the SAME two items must
  still be selected after the indices have been remapped by the sort. }
procedure TTyListBoxTest.TestSortedKeepsMultiSelection;
begin
  FList.Items.Clear;
  FList.Items.Add('Delta');
  FList.Items.Add('Alpha');
  FList.Items.Add('Charlie');
  FList.Items.Add('Bravo');
  FList.MultiSelect := True;
  FList.Selected[0] := True;   // 'Delta'
  FList.Selected[2] := True;   // 'Charlie'
  AssertEquals('two selected before sort', 2, FList.SelCount);

  FList.Sorted := True;

  // Ascending order: Alpha, Bravo, Charlie, Delta
  AssertEquals('sorted item 0', 'Alpha',   FList.Items[0]);
  AssertEquals('sorted item 1', 'Bravo',   FList.Items[1]);
  AssertEquals('sorted item 2', 'Charlie', FList.Items[2]);
  AssertEquals('sorted item 3', 'Delta',   FList.Items[3]);

  // The SAME two strings remain selected, at their NEW indices.
  AssertEquals('still two selected after sort', 2, FList.SelCount);
  AssertTrue('Charlie selected (now index 2)', FList.Selected[2]);
  AssertTrue('Delta selected (now index 3)',   FList.Selected[3]);
  AssertFalse('Alpha not selected (now index 0)', FList.Selected[0]);
  AssertFalse('Bravo not selected (now index 1)', FList.Selected[1]);
end;

initialization
  RegisterTest(TTyListBoxTest);
  RegisterTest(TTyListBoxScrollBarPropTest);
end.
