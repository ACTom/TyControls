unit test.buttongroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, Types, Forms, Controls, Graphics,
  BGRABitmap,
  tyControls.Base, tyControls.ButtonGroup, tyControls.Types, tyControls.Controller,
  tyControls.ToolBar;
type
  // Expose the protected SelectAt/RenderTo seams for headless testing.
  TTyButtonGroupAccess = class(TTyButtonGroup)
  public
    procedure DoSelectAt(AX: Integer);
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function StyleKey: string;
    // Expose the protected preferred-size calculation (what AutoSize resizes to).
    procedure CallPreferred(out AW, AH: Integer);
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
    procedure TestItemsChangeResetsSelection;
    procedure TestMultiSelectToggleFires;
    procedure TestPaintSmokeEmpty;
    procedure TestPaintSmokePopulated;
  end;

  { AutoSize / preferred-size suite. Every assertion goes through CalculatePreferredSize
    rather than through Width: LCL's AutoSizeDelayed suppresses auto-sizing while the parent
    form has no handle, and the headless runner never realises one — so reading Width here
    would measure nothing. }
  TButtonGroupAutoSizeTest = class(TTestCase)
  published
    procedure TestAutoSizePublishedAndOffByDefault;
    procedure TestEmptyGroupProposesNothing;
    procedure TestPreferredWidthIsCountTimesTheWidestCell;
    procedure TestPreferredWidthGrowsWithTheWidestCaption;
    procedure TestMnemonicMarkerCostsNoWidth;
    procedure TestRoomierThemePaddingWidensPreferredWidth;
    procedure TestAutoSizeSurvivesAHeightPinningParent;
  end;

  { SIZE FLOOR (Constraints.Min*). A hand-set Height and the theme's --control-height are
    REQUESTS; what is POSSIBLE is decided by the font and the padding, and only the control
    knows both. On Linux/Qt6 a 9pt CJK caption resolves through a fallback face whose ink is
    taller than Windows', and RenderTo draws each segment's text clipped and tlCenter, so a bar
    shorter than the ink quietly loses the BOTTOM of every caption.
    Unlike AutoSize, the floor is unconditional: it holds for a hand-sized bar too, which is
    exactly the bar that gets caught out. Everything here asserts Constraints, because
    AutoSizeDelayed suppresses real resizing while the parent form has no handle. }
  TButtonGroupFloorTest = class(TTestCase)
  published
    procedure TestFloorIsTheSameMeasurementAsThePreferredWidth;
    procedure TestFloorWidthScalesWithTheCellCount;
    procedure TestVerticalPaddingIsNotPartOfTheHeightFloor;
    procedure TestSmallerFontLowersTheFloor;
    procedure TestEmptyBarHasNoFloor;
    procedure TestFloorClampsAnImpossibleHeight;
    procedure TestFloorSurvivesAHeightPinningToolBar;
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

procedure TTyButtonGroupAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
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
    AssertEquals('TyButtonGroup', G.StyleKey);
    AssertEquals('TyButtonGroup', (G as ITyStyleable).GetStyleTypeKey);
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

procedure TButtonGroupTest.TestItemsChangeResetsSelection;
var G: TTyButtonGroup;
begin
  // Regression: TStrings.OnChange carries no diff, so positional selection bits can't
  // be remapped on an insert/delete — the group resets selection instead of silently
  // moving it onto the wrong item.
  G := TTyButtonGroup.Create(nil);
  try
    G.MultiSelect := True;
    G.Items.Add('A'); G.Items.Add('B'); G.Items.Add('C');
    G.SetSelected(1, True);
    AssertTrue('B selected', G.IsSelected(1));
    G.Items.Delete(0);   // list changed -> selection reset (not shifted onto 'B'->idx0)
    AssertFalse('selection cleared after delete (0)', G.IsSelected(0));
    AssertFalse('selection cleared after delete (1)', G.IsSelected(1));

    // Single-select index likewise resets on a structural change.
    G.MultiSelect := False;
    G.Items.Clear;
    G.Items.Add('X'); G.Items.Add('Y');
    G.ItemIndex := 1;
    AssertEquals('Y selected', 1, G.ItemIndex);
    G.Items.Add('Z');   // structural change resets the index
    AssertEquals('index reset after Add', -1, G.ItemIndex);
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

{ TButtonGroupAutoSizeTest }

const
  // One stylesheet shape reused across the suite: only the padding / font-size digits move,
  // so any width difference an assertion sees can only have come from what changed.
  cCssFmt = 'TyButtonGroup { background: #FFFFFF; color: #000000; border-width: 0px; ' +
            'padding: %dpx %dpx; font-size: %dpx; }';

procedure TButtonGroupAutoSizeTest.TestAutoSizePublishedAndOffByDefault;
{ AutoSize has to be settable from a .lfm and from the object inspector, and it has to stay
  OFF by default — every existing layout keeps the width it was designed with. }
var
  G: TTyButtonGroup;
begin
  G := TTyButtonGroup.Create(nil);
  try
    AssertTrue('AutoSize is published so a .lfm / the OI can set it',
      IsPublishedProp(G, 'AutoSize'));
    AssertFalse('but it stays OFF by default — a designed bar keeps its width', G.AutoSize);
  finally
    G.Free;
  end;
end;

procedure TButtonGroupAutoSizeTest.TestEmptyGroupProposesNothing;
{ An empty bar draws nothing (RenderTo returns after the background), so it has no opinion on
  either axis: 0 is LCL's "no preference", which leaves the designed 240px alone. Answering 1px
  here would collapse an empty group in the designer the moment AutoSize was switched on. }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
  w, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(Format(cCssFmt, [4, 10, 12]));
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.CallPreferred(w, h);
      AssertEquals('an empty bar proposes no width', 0, w);
      AssertEquals('an empty bar proposes no height', 0, h);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupAutoSizeTest.TestPreferredWidthIsCountTimesTheWidestCell;
{ RenderTo tiles the bar into EQUAL cells and centres each caption inside its cell minus the
  style's left/right padding — so the bar needs count x (widest caption + both paddings).
  Adding one more item no wider than the current widest must therefore add exactly one cell:
  that is the arithmetic this asserts (2 cells x 3 = 3 cells x 2), and it is what stops the
  last segment from being the only one that fits. }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
  w2, w3, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(Format(cCssFmt, [4, 10, 12]));
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.Items.Add('Alpha');           // the widest caption throughout
      G.Items.Add('Beta');
      G.CallPreferred(w2, h);
      AssertTrue('two cells want a real width', w2 > 0);
      { Height is deliberately UNSET (0 = "no preference on this axis" in LCL): the bar widens
        for its captions, but its height belongs to whoever lays out the row. Proposing one
        makes it fight any container that pins a height (TTyToolBar pins every child to its
        ButtonHeight) until LCL aborts with "TControl.ChangeBounds loop detected". }
      AssertEquals('height is left to the layout, not proposed', 0, h);

      G.Items.Add('Beta');            // no wider than 'Alpha' -> one more identical cell
      G.CallPreferred(w3, h);
      AssertEquals('three cells are exactly one and a half times two cells', w2 * 3, w3 * 2);
      AssertEquals('and still no height', 0, h);

      // The cell really carries BOTH paddings: 10px a side x 3 cells = 60px of the total.
      AssertTrue(Format('the width includes each cell''s padding (3 cells, got %d)', [w3]),
        w3 > 3 * (2 * 10));
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupAutoSizeTest.TestPreferredWidthGrowsWithTheWidestCaption;
{ The reported case: a caption swapped at runtime (a longer translation pushed in after the
  .lfm sized the bar) must make the bar want more width, not get ellipsised. Every cell is the
  same width, so it is the WIDEST caption that sets the cell — a single long item widens all
  of them. }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
  narrow, wide, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(Format(cCssFmt, [4, 10, 12]));
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.AutoSize := True;
      G.Items.Add('New');
      G.Items.Add('Open');
      G.CallPreferred(narrow, h);

      G.Items[1] := 'Open a recent work order';
      G.CallPreferred(wide, h);
      AssertTrue(Format('the widest caption sets every cell (%d -> %d)', [narrow, wide]),
        wide > narrow);
      AssertEquals('and never proposes a height', 0, h);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupAutoSizeTest.TestMnemonicMarkerCostsNoWidth;
{ RenderTo strips the '&' with TyParseMnemonic and draws it as an underline, not as a
  character — so measuring it would reserve width for ink that is never drawn. }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
  plain, marked, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(Format(cCssFmt, [4, 10, 12]));
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.Items.Add('Save');
      G.CallPreferred(plain, h);
      G.Items[0] := '&Save';
      G.CallPreferred(marked, h);
      AssertEquals('a mnemonic marker adds no width', plain, marked);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupAutoSizeTest.TestRoomierThemePaddingWidensPreferredWidth;
{ THE bug this work exists for: the 'xp' skin asks for 12px of horizontal button padding where
  the default asks 6px, so every hand-sized bar clipped its captions under xp. A theme switch
  reaches the control as a bare Invalidate, which is where the re-fit has to happen (TTyButton
  and TTyBadge re-measure the same way). Asserted through CalculatePreferredSize, since
  AutoSizeDelayed blocks a real resize while the parent form has no handle. }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
  tight, roomy, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.AutoSize := True;
      G.Items.Add('Day'); G.Items.Add('Week'); G.Items.Add('Month');

      Ctl.LoadThemeCss(Format(cCssFmt, [4, 4, 12]));
      G.CallPreferred(tight, h);

      // Same captions, same font — only the padding is roomier.
      Ctl.LoadThemeCss(Format(cCssFmt, [4, 30, 12]));
      G.CallPreferred(roomy, h);
      AssertTrue(Format('a roomier theme widens the bar (%d -> %d)', [tight, roomy]),
        roomy > tight);
      // 26px more padding per side, both sides, on each of the 3 cells.
      AssertEquals('the extra width is exactly the extra padding',
        tight + 3 * 2 * 26, roomy);
      AssertEquals('and no height is ever proposed', 0, h);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupAutoSizeTest.TestAutoSizeSurvivesAHeightPinningParent;
{ The regression that killed the demo at startup for TTyButton: a bar pins every child's
  height, the child proposes its own, and the two bounce until LCL aborts with
  "TControl.ChangeBounds loop detected". An AutoSize group on a real TTyToolBar must simply
  settle — and settle at the BAR's height, not its own idea of one. }
var
  F: TForm;
  Bar: TTyToolBar;
  G: TTyButtonGroup;
  hBefore: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.Align := alTop;
    Bar.ButtonHeight := 24;

    G := TTyButtonGroup.Create(F);
    G.Parent := Bar;
    G.Font.PixelsPerInch := 96;
    G.Items.Add('Day'); G.Items.Add('Week');
    G.AutoSize := True;          // this is the shape that used to loop
    hBefore := G.Height;

    // Grow a caption the way a translation does: it must not start a bounds war.
    G.Items[1] := 'The whole working week';
    Bar.Realign;

    AssertEquals('the bar still owns the height', hBefore, G.Height);
    AssertTrue('and the group is still a sane size', (G.Width > 0) and (G.Height > 0));
  finally
    F.Free;
  end;
end;

{ ---- TButtonGroupFloorTest ---- }

procedure TButtonGroupFloorTest.TestFloorIsTheSameMeasurementAsThePreferredWidth;
{ "What the bar asks for" and "what the bar refuses to go below" must be one measurement.
  Two formulas would eventually disagree, and the one that disagrees with RenderTo is the one
  that ellipsises captions while reporting a fit. }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
  pref, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(Format(cCssFmt, [4, 10, 12]));
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.Items.Add('Day'); G.Items.Add('Week'); G.Items.Add('Month');
      G.Invalidate;                    // the seam a theme switch arrives on
      G.CallPreferred(pref, h);

      AssertEquals('the width floor IS the preferred width', pref, G.Constraints.MinWidth);
      AssertTrue('and there is a real height floor', G.Constraints.MinHeight > 0);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupFloorTest.TestFloorWidthScalesWithTheCellCount;
{ RenderTo tiles the bar into equal cells, so the minimum is COUNT x cell. Under-count one cell
  and every segment clips — which is why this asserts the exact 3 -> 4 step, not "bigger". }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
  three: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(Format(cCssFmt, [4, 10, 12]));
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      // Identical captions, so every cell is provably the same width.
      G.Items.Add('Day'); G.Items.Add('Day'); G.Items.Add('Day');
      three := G.Constraints.MinWidth;
      AssertTrue('three cells must measure to something', three > 0);

      G.Items.Add('Day');              // Items.OnChange is this control's "caption changed"
      AssertEquals('a fourth identical cell costs exactly one more cell',
        three + three div 3, G.Constraints.MinWidth);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupFloorTest.TestVerticalPaddingIsNotPartOfTheHeightFloor;
{ RenderTo insets each cell's text rect LEFT and RIGHT only — the text gets the segment's full
  top-to-bottom span. So the height the captions need is the line itself, and adding the
  theme's vertical padding on top would silently inflate every bar (and grow tool-bar rows)
  for space the text never uses. Two themes differing ONLY in vertical padding must therefore
  produce the SAME floor on both axes. }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
  thinH, thinW: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.Items.Add('Day'); G.Items.Add('Week');

      Ctl.LoadThemeCss(Format(cCssFmt, [2, 6, 12]));
      G.Invalidate;
      thinH := G.Constraints.MinHeight;
      thinW := G.Constraints.MinWidth;

      // 2px -> 20px of vertical padding; the font and the horizontal padding do not move.
      Ctl.LoadThemeCss(Format(cCssFmt, [20, 6, 12]));
      G.Invalidate;
      AssertEquals('vertical padding is not part of what the captions need',
        thinH, G.Constraints.MinHeight);
      AssertEquals('and horizontal padding did not change either', thinW, G.Constraints.MinWidth);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupFloorTest.TestSmallerFontLowersTheFloor;
{ The floor is DERIVED, not a wall: shrink the font and the padding and the minimum shrinks
  with them. That is what makes "override the CSS if you want it smaller" a coherent answer
  instead of a refusal. }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
  bigH, bigW: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.Items.Add('新建'); G.Items.Add('打开');

      Ctl.LoadThemeCss(Format(cCssFmt, [4, 12, 20]));
      G.Invalidate;
      bigH := G.Constraints.MinHeight;
      bigW := G.Constraints.MinWidth;

      Ctl.LoadThemeCss(Format(cCssFmt, [1, 2, 8]));
      G.Invalidate;
      AssertTrue(Format('a smaller font lowers the height floor (%d -> %d)',
        [bigH, G.Constraints.MinHeight]), G.Constraints.MinHeight < bigH);
      AssertTrue(Format('a smaller font+padding lowers the width floor (%d -> %d)',
        [bigW, G.Constraints.MinWidth]), G.Constraints.MinWidth < bigW);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupFloorTest.TestEmptyBarHasNoFloor;
{ An empty bar draws nothing at all (RenderTo bails), so it demands nothing — and clearing the
  items has to RELEASE the floor, not leave the bar wedged at the width the old captions
  needed. }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(Format(cCssFmt, [4, 10, 12]));
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.Items.Add('A considerably longer segment caption');
      AssertTrue('a populated bar has a floor', G.Constraints.MinWidth > 0);

      G.Items.Clear;
      AssertEquals('clearing the items releases the width floor', 0, G.Constraints.MinWidth);
      AssertEquals('and the height floor with it', 0, G.Constraints.MinHeight);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupFloorTest.TestFloorClampsAnImpossibleHeight;
{ The point of putting this in Constraints rather than in a proposed size: an impossible
  request is clamped inside SetBounds, with nobody to negotiate with. }
var
  Ctl: TTyStyleController;
  G: TTyButtonGroupAccess;
  minH: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(Format(cCssFmt, [4, 10, 20]));
    G := TTyButtonGroupAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.Items.Add('新建'); G.Items.Add('打开');
      G.Invalidate;
      minH := G.Constraints.MinHeight;
      AssertTrue('a 20px font needs a real line', minH > 1);

      G.Height := 2;
      AssertTrue(Format('a too-short request is clamped up to the floor (%d >= %d)',
        [G.Height, minH]), G.Height >= minH);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonGroupFloorTest.TestFloorSurvivesAHeightPinningToolBar;
{ The floor must NOT reopen the fight a proposed height once started: a child on a TTyToolBar
  proposed its own height, the bar pinned its ButtonHeight back, and LCL aborted with
  "ChangeBounds loop detected" — the demo died at startup. Constraints clamp inside SetBounds
  with no negotiation. Reaching the end of this test IS the assertion. }
var
  F: TForm;
  Bar: TTyToolBar;
  G: TTyButtonGroup;
begin
  F := TForm.CreateNew(nil);
  try
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.ButtonHeight := 40;
    G := TTyButtonGroup.Create(Bar);
    G.Parent := Bar;
    G.Items.Add('新建'); G.Items.Add('打开');
    G.AutoSize := True;
    Bar.ButtonHeight := 41;            // a loop would abort the process here
    AssertTrue(Format('the bar asks for a height the floor can honour (min %d)',
      [G.Constraints.MinHeight]), G.Constraints.MinHeight <= 40);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TButtonGroupTest);
  RegisterTest(TButtonGroupAutoSizeTest);
  RegisterTest(TButtonGroupFloorTest);
end.
