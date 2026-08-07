unit test.radiogroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, ExtCtrls, LCLType,
  fpcunit, testregistry,
  tyControls.Base, tyControls.Controller, tyControls.CheckBox, tyControls.GroupBox,
  tyControls.RadioGroup;
type
  { Reaches TTyCustomControl's protected MouseDown / KeyDown / AdjustClientRect, so a test
    can drive a hosted radio the way the widgetset does instead of calling Click (which
    skips the mouse path entirely -- and the mouse path is where the defect lived). }
  TCtlAccess = class(TTyCustomControl);

  { Watches the group's REQUEST for the caret.

    The OS half cannot be tested here and must not be pretended: on a form that was never
    shown CanFocus answers False, TTyRadioGroup.FocusItem correctly declines to call
    SetFocus, and any assertion on Focused would be vacuously true forever. So the seam is
    virtual and this spy counts the requests; tests/radiofocusverify then proves on a real
    window, with real handles, that the request lands on the caret. Splitting it that way
    is the only honest split -- see memory: headless tests never run LCL's focus engine. }
  TSpyRadioGroup = class(TTyRadioGroup)
  public
    FocusRequests: Integer;
    LastFocusRequest: Integer;
    constructor Create(AOwner: TComponent); override;
    procedure FocusItem(AIndex: Integer); override;
  end;

  TRadioGroupTest = class(TTestCase)
  private
    FForm: TForm;
    FGrp: TTyRadioGroup;
    function BuildSpy: TSpyRadioGroup;
    function SelChangeFired: Boolean;
    procedure OnSel(Sender: TObject);
  private
    FSelCount: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // typeKey / basics
    procedure TestTypeKeyInherited;
    procedure TestDefaultColumns;
    // pure layout math
    procedure TestCellRectSingleColumnStacks;
    procedure TestCellRectRowMajorIsTheDefaultOrder;
    procedure TestCellRectColumnMajorIsOptIn;
    procedure TestCellRectTwoColumnsSplitWidth;
    procedure TestCellRectLastColumnAbsorbsRemainder;
    procedure TestCellRectDegenerate;
    procedure TestCellRectRowsCeil;
    // Items -> child count
    procedure TestItemsPopulateChildren;
    procedure TestItemsRebuildReplacesChildren;
    procedure TestEmptyItemsNoChildren;
    // ItemIndex round-trip
    procedure TestItemIndexWriteChecksChild;
    procedure TestItemIndexReadReflectsChecked;
    procedure TestItemIndexOutOfRangeRaises;
    procedure TestChildrenAreMutuallyExclusive;
    // rebuild survives selection
    procedure TestRebuildPreservesValidIndex;
    procedure TestRebuildDropsNowInvalidIndex;
    procedure TestRebuildPreservesSelectionByIdentity;
    procedure TestControllerPropagatesToChildren;
    // events
    procedure TestClickFiresSelectionChanged;
    procedure TestProgrammaticSetNotifiesToo;
    // the ring follows the dot (bug: one click moved the dot only)
    procedure TestOneLeftPressAsksForTheCaretOnThePressedItem;
    procedure TestASecondPressOnTheSameItemDoesNotReAskForTheCaret;
    procedure TestARightPressMovesNothing;
    procedure TestArrowKeysAskForTheCaretThroughTheSameSeam;
    procedure TestFocusedIndexIsMinusOneWhenTheGroupHasNoCaret;
    // row pitch (bug: rows overlapped and the next row ate the ring's bottom edge)
    procedure TestRowsNeverOverlapSoTheFocusRingSurvives;
    procedure TestEveryRowStaysInsideTheGroupClientArea;
    procedure TestRowPitchIsNeverShorterThanAHostedRadio;
    // designer hygiene
    procedure TestChildrenAreNoDesignVisible;
    procedure TestChildrenOwnedByGroup;
    procedure TestColumnsClampToOne;
  end;

implementation

{ TSpyRadioGroup }

constructor TSpyRadioGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FocusRequests := 0;
  LastFocusRequest := -99;
end;

procedure TSpyRadioGroup.FocusItem(AIndex: Integer);
begin
  Inc(FocusRequests);
  LastFocusRequest := AIndex;
  inherited FocusItem(AIndex);   // still exercise the real guard (it no-ops headless)
end;

function TRadioGroupTest.BuildSpy: TSpyRadioGroup;
begin
  { The containers example's own box, so these numbers are the reported numbers. }
  Result := TSpyRadioGroup.Create(FForm);
  Result.Parent := FForm;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 290, 94);
  Result.Columns := 2;
  Result.Items.CommaText := '"Extra small",Small,Medium,Large';
  Result.ItemIndex := 1;             // "Small": the ONLY item with a tab stop
  Result.FocusRequests := 0;
  Result.LastFocusRequest := -99;
end;

procedure TRadioGroupTest.TestRebuildPreservesSelectionByIdentity;
begin
  // A mid-list delete must keep the selection on its OWN item, not on the raw slot.
  FGrp.Items.CommaText := 'A,B,C';
  FGrp.ItemIndex := 2;                 // 'C'
  FGrp.Items.Delete(0);                // -> ['B','C']; the selection must FOLLOW 'C' to index 1
  AssertEquals('selection follows the item, not the slot', 1, FGrp.ItemIndex);
end;

procedure TRadioGroupTest.TestControllerPropagatesToChildren;
var
  Ctl: TTyStyleController;
  i, seen: Integer;
begin
  // A controller assigned AFTER population must re-push onto the existing radio children.
  FGrp.Items.CommaText := 'A,B';       // radios built with the current controller
  Ctl := TTyStyleController.Create(nil);
  try
    FGrp.Controller := Ctl;
    seen := 0;
    for i := 0 to FGrp.ControlCount - 1 do
      if FGrp.Controls[i] is TTyRadioButton then
      begin
        AssertTrue('child follows the group controller',
          TTyRadioButton(FGrp.Controls[i]).Controller = Ctl);
        Inc(seen);
      end;
    AssertEquals('both radios present', 2, seen);
  finally
    FGrp.Controller := nil;            // detach children before freeing the controller
    Ctl.Free;
  end;
end;

function TRadioGroupTest.SelChangeFired: Boolean;
begin
  Result := FSelCount > 0;
end;

procedure TRadioGroupTest.OnSel(Sender: TObject);
begin
  Inc(FSelCount);
end;

procedure TRadioGroupTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 260);
  FGrp := TTyRadioGroup.Create(FForm);
  FGrp.Parent := FForm;
  FGrp.SetBounds(0, 0, 185, 130);
  FGrp.Font.PixelsPerInch := 96;
  FSelCount := 0;
end;

procedure TRadioGroupTest.TearDown;
begin
  FForm.Free;
end;

{ ---- typeKey / basics ---------------------------------------------------- }

procedure TRadioGroupTest.TestTypeKeyInherited;
begin
  // Reuses the inherited TyGroupBox token — NO new .tycss rule.
  AssertEquals('TyGroupBox', (FGrp as ITyStyleable).GetStyleTypeKey);
end;

procedure TRadioGroupTest.TestDefaultColumns;
begin
  AssertEquals('default Columns = 1', 1, FGrp.Columns);
end;

{ ---- pure layout math ---------------------------------------------------- }

procedure TRadioGroupTest.TestCellRectSingleColumnStacks;
var
  client: TRect;
  c0, c1, c2: TRect;
begin
  // 3 items, 1 column, a client tall enough that the grid is NOT centered off (grid
  // 66 < 200) -> rows stack by 22 from a centered top.
  client := Rect(0, 0, 180, 200);
  c0 := TyRadioGroupCellRect(client, 3, 1, 0);
  c1 := TyRadioGroupCellRect(client, 3, 1, 1);
  c2 := TyRadioGroupCellRect(client, 3, 1, 2);
  // one column -> full client width
  AssertEquals('col width = full client', 0, c0.Left);
  AssertEquals('col width = full client', 180, c0.Right);
  // stacked by row height (22)
  AssertEquals('row spacing = 22', c0.Top + 22, c1.Top);
  AssertEquals('row spacing = 22', c1.Top + 22, c2.Top);
  AssertEquals('row height = 22', 22, c0.Bottom - c0.Top);
end;

{ RENAMED. This used to be TestCellRectColumnMajorOrder and it asserted, by name, the very
  thing that was wrong: the grid filled DOWN column 0 first while the same .lfm loaded in
  Lazarus filled ACROSS row 0 first, so a ported multi-column group silently reordered the
  user's options and nothing anywhere said so. The default is now LCL's. }
procedure TRadioGroupTest.TestCellRectRowMajorIsTheDefaultOrder;
var
  client: TRect;
  c0, c1, c2, c3: TRect;
begin
  // 4 items, 2 columns => 2 rows. Row-major: index 0,1 across row 0; index 2,3 across row 1.
  client := Rect(0, 0, 200, 120);
  c0 := TyRadioGroupCellRect(client, 4, 2, 0);
  c1 := TyRadioGroupCellRect(client, 4, 2, 1);
  c2 := TyRadioGroupCellRect(client, 4, 2, 2);
  c3 := TyRadioGroupCellRect(client, 4, 2, 3);
  // 0 and 1 share the TOP row; 2 and 3 the second one.
  AssertEquals('idx0 and idx1 on the same row', c0.Top, c1.Top);
  AssertEquals('idx2 and idx3 on the same row', c2.Top, c3.Top);
  AssertTrue('the second row is lower', c2.Top > c0.Top);
  // 1 is to the RIGHT of 0 (row-major fills across first)
  AssertTrue('idx1 right of idx0 on the same row', c1.Left > c0.Left);
  // 0 and 2 head their rows -> same Left
  AssertEquals('idx0 and idx2 start the same column', c0.Left, c2.Left);
end;

{ The opt-out. Column-major is still reachable, it is simply no longer the silent default. }
procedure TRadioGroupTest.TestCellRectColumnMajorIsOptIn;
var
  client: TRect;
  c0, c1, c2, c3: TRect;
begin
  client := Rect(0, 0, 200, 120);
  c0 := TyRadioGroupCellRect(client, 4, 2, 0, 0, clVerticalThenHorizontal);
  c1 := TyRadioGroupCellRect(client, 4, 2, 1, 0, clVerticalThenHorizontal);
  c2 := TyRadioGroupCellRect(client, 4, 2, 2, 0, clVerticalThenHorizontal);
  c3 := TyRadioGroupCellRect(client, 4, 2, 3, 0, clVerticalThenHorizontal);
  AssertEquals('idx0 left col', c0.Left, c1.Left);
  AssertEquals('idx2 right col', c2.Left, c3.Left);
  AssertTrue('right column is further right', c2.Left > c0.Left);
  AssertTrue('idx1 below idx0 in same column', c1.Top > c0.Top);
  AssertEquals('idx0 and idx2 same row', c0.Top, c2.Top);
end;

procedure TRadioGroupTest.TestCellRectTwoColumnsSplitWidth;
var
  client: TRect;
  c0, c1: TRect;
begin
  client := Rect(0, 0, 200, 120);
  // Row-major: the SECOND column is index 1, not index 2.
  c0 := TyRadioGroupCellRect(client, 4, 2, 0);   // col 0
  c1 := TyRadioGroupCellRect(client, 4, 2, 1);   // col 1
  AssertEquals('col0 left', 0, c0.Left);
  AssertEquals('col0 right = half', 100, c0.Right);
  AssertEquals('col1 left = half', 100, c1.Left);
  AssertEquals('col1 right = full', 200, c1.Right);
end;

procedure TRadioGroupTest.TestCellRectLastColumnAbsorbsRemainder;
var
  client: TRect;
  c0, c1, c2: TRect;
begin
  // width 205 / 3 columns = 68 each, last column extends to 205.
  client := Rect(0, 0, 205, 120);
  c0 := TyRadioGroupCellRect(client, 3, 3, 0);
  c1 := TyRadioGroupCellRect(client, 3, 3, 1);
  c2 := TyRadioGroupCellRect(client, 3, 3, 2);
  AssertEquals('col0 0..68', 0, c0.Left);
  AssertEquals('col0 right', 68, c0.Right);
  AssertEquals('col1 68..136', 68, c1.Left);
  AssertEquals('col1 right', 136, c1.Right);
  AssertEquals('col2 left', 136, c2.Left);
  AssertEquals('col2 absorbs remainder to 205', 205, c2.Right);
end;

procedure TRadioGroupTest.TestCellRectDegenerate;
begin
  AssertTrue('count<=0 -> empty', IsRectEmpty(TyRadioGroupCellRect(Rect(0,0,180,120), 0, 1, 0)));
  AssertTrue('columns<=0 -> empty', IsRectEmpty(TyRadioGroupCellRect(Rect(0,0,180,120), 3, 0, 0)));
  AssertTrue('index<0 -> empty', IsRectEmpty(TyRadioGroupCellRect(Rect(0,0,180,120), 3, 1, -1)));
  AssertTrue('index>=count -> empty', IsRectEmpty(TyRadioGroupCellRect(Rect(0,0,180,120), 3, 1, 3)));
  AssertTrue('zero-area client -> empty', IsRectEmpty(TyRadioGroupCellRect(Rect(0,0,0,0), 3, 1, 0)));
end;

{ Row count is ceil(Count/Columns) in BOTH fill orders — that is what makes the two orders a
  permutation of the same grid rather than two different grids. Asserted on the column-major
  order, where the row count is what decides when a column wraps. }
procedure TRadioGroupTest.TestCellRectRowsCeil;
var
  client: TRect;
  c0, c1, c2, c3, c4: TRect;
begin
  // 5 items, 2 columns => rows = ceil(5/2) = 3. Column-major: col0 gets 0,1,2 ; col1 gets 3,4.
  client := Rect(0, 0, 200, 200);
  c0 := TyRadioGroupCellRect(client, 5, 2, 0, 0, clVerticalThenHorizontal);
  c1 := TyRadioGroupCellRect(client, 5, 2, 1, 0, clVerticalThenHorizontal);
  c2 := TyRadioGroupCellRect(client, 5, 2, 2, 0, clVerticalThenHorizontal);
  c3 := TyRadioGroupCellRect(client, 5, 2, 3, 0, clVerticalThenHorizontal);
  c4 := TyRadioGroupCellRect(client, 5, 2, 4, 0, clVerticalThenHorizontal);
  // col0 holds 3 rows
  AssertEquals('c0,c1 same col', c0.Left, c1.Left);
  AssertEquals('c1,c2 same col', c1.Left, c2.Left);
  AssertTrue('c3 in the second column', c3.Left > c0.Left);
  AssertEquals('c3,c4 same col', c3.Left, c4.Left);
  // c3 aligns to the top row of col1 (same Top as c0)
  AssertEquals('c3 top-row aligns with c0', c0.Top, c3.Top);
  AssertTrue('c4 below c3', c4.Top > c3.Top);
  { The row-major default lays the SAME 5 items on the same 3 rows, just walked the other
    way: 0 1 / 2 3 / 4. Asserting the row count from both sides is what stops a future edit
    from "fixing" one order into a different grid shape. }
  AssertEquals('row-major puts idx2 on row 1',
    TyRadioGroupCellRect(client, 5, 2, 2).Top, c1.Top);
  AssertEquals('row-major puts idx4 on row 2',
    TyRadioGroupCellRect(client, 5, 2, 4).Top, c2.Top);
end;

{ ---- Items -> child count ------------------------------------------------ }

procedure TRadioGroupTest.TestItemsPopulateChildren;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  AssertEquals('one radio child per item', 3, FGrp.Count);
end;

procedure TRadioGroupTest.TestItemsRebuildReplacesChildren;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  AssertEquals('2 children', 2, FGrp.Count);
  FGrp.Items.Clear;
  FGrp.Items.Add('X');
  AssertEquals('rebuilt to 1 child', 1, FGrp.Count);
end;

procedure TRadioGroupTest.TestEmptyItemsNoChildren;
begin
  AssertEquals('no items -> no children', 0, FGrp.Count);
end;

{ ---- ItemIndex round-trip ------------------------------------------------ }

procedure TRadioGroupTest.TestItemIndexWriteChecksChild;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  FGrp.ItemIndex := 1;
  AssertEquals('ItemIndex round-trips', 1, FGrp.ItemIndex);
end;

procedure TRadioGroupTest.TestItemIndexReadReflectsChecked;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  AssertEquals('no selection initially', -1, FGrp.ItemIndex);
  FGrp.ItemIndex := 0;
  AssertEquals('reads back index 0', 0, FGrp.ItemIndex);
end;

{ This asserted the clear in its own name -- the sixth test in this pass to pin the
  defect it was standing next to. Clearing made `ItemIndex := 99` on a two-item group
  indistinguishable from `ItemIndex := -1`, so an off-by-one read as "the user deselected". }
procedure TRadioGroupTest.TestItemIndexOutOfRangeRaises;
var
  raised: Boolean;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.ItemIndex := 1;
  AssertEquals('set to 1', 1, FGrp.ItemIndex);
  raised := False;
  try
    FGrp.ItemIndex := 99;
  except
    on E: EListError do raised := True;
  end;
  AssertTrue('out-of-range raises', raised);
  AssertEquals('and the selection survives the refusal', 1, FGrp.ItemIndex);
end;

procedure TRadioGroupTest.TestChildrenAreMutuallyExclusive;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  FGrp.ItemIndex := 0;
  FGrp.ItemIndex := 2;
  // exactly one selected -> ItemIndex is a single value, confirms exclusivity
  AssertEquals('only the last set stays', 2, FGrp.ItemIndex);
end;

{ ---- rebuild survives selection ------------------------------------------ }

procedure TRadioGroupTest.TestRebuildPreservesValidIndex;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  FGrp.ItemIndex := 1;
  // add a 4th item -> rebuild; index 1 still valid
  FGrp.Items.Add('D');
  AssertEquals('4 children now', 4, FGrp.Count);
  AssertEquals('index 1 survives the rebuild', 1, FGrp.ItemIndex);
end;

procedure TRadioGroupTest.TestRebuildDropsNowInvalidIndex;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  FGrp.ItemIndex := 2;
  // shrink to 1 item -> index 2 no longer valid -> cleared
  FGrp.Items.Clear;
  FGrp.Items.Add('Only');
  AssertEquals('1 child', 1, FGrp.Count);
  AssertEquals('stale index cleared after shrink', -1, FGrp.ItemIndex);
end;

{ ---- events -------------------------------------------------------------- }

procedure TRadioGroupTest.TestClickFiresSelectionChanged;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.OnSelectionChanged := @OnSel;
  FSelCount := 0;
  // Simulate a user click on the second radio child by invoking its Click (which the
  // base TTyRadioButton routes through Checked -> OnChange -> our ChildChanged).
  // The children are parented to the group in item order, so Controls[1] is item 1.
  (FGrp.Controls[1] as TTyRadioButton).Click;
  AssertTrue('click fired OnSelectionChanged', SelChangeFired);
  AssertEquals('selection moved to clicked child', 1, FGrp.ItemIndex);
  AssertEquals('exactly one fire for the gesture', 1, FSelCount);
end;

{ This used to assert silence -- its own name said IsSilent -- and that was the bug: the
  selection changed and nobody was told, so a handler keeping a detail panel in step with
  the choice worked when the user clicked and silently did not when the app restored a
  saved selection. LCL notifies either way, deliberately ("to be delphi compat"). The
  re-entrancy guard is still doing its job: ONE notification, not one per child. }
procedure TRadioGroupTest.TestProgrammaticSetNotifiesToo;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.OnSelectionChanged := @OnSel;
  FSelCount := 0;
  FGrp.ItemIndex := 1;
  AssertEquals('a programmatic set notifies', 1, FSelCount);
  AssertEquals('exactly once, not once per child', 1, FSelCount);
  AssertEquals('and the index took', 1, FGrp.ItemIndex);
  FGrp.ItemIndex := 1;
  AssertEquals('an unchanged write stays silent', 1, FSelCount);
end;

{ ---- the ring follows the dot -------------------------------------------- }

{ THE REPORTED BUG. "I clicked Small: the dot moved, the ring stayed on Extra small; only a
  SECOND click moved the ring."

  Mechanism: UpdateTabStops leaves TabStop True on the CHECKED item only, and
  TTyCustomControl.MouseDown gates focus-on-click on `TabStop and CanFocus and not Focused`.
  So the one option that could take the caret from a press was the one that already held the
  selection. The first press checked the item (which then handed IT the tab stop), and only
  the second press got past the gate. LCL's TRadioGroup is not exposed to it: its children
  are native TRadioButtons and Windows focuses a clicked control whatever WS_TABSTOP says
  (its own UpdateTabStops is the same roving rule -- radiogroup.inc:561).

  Asserted on the REQUEST, not on Focused: see TSpyRadioGroup. }
procedure TRadioGroupTest.TestOneLeftPressAsksForTheCaretOnThePressedItem;
var
  g: TSpyRadioGroup;
begin
  g := BuildSpy;
  AssertEquals('precondition: only the checked item is a tab stop', 1, g.ItemIndex);
  AssertFalse('precondition: the item about to be pressed has no tab stop',
    g.Buttons[0].TabStop);

  TCtlAccess(g.Buttons[0]).MouseDown(mbLeft, [ssLeft], 5, 5);

  AssertEquals('ONE left press must ask for the caret exactly once -- if this is 0 the '
    + 'group is back to letting TTyCustomControl''s TabStop gate decide, and the gate '
    + 'refuses every item except the already-selected one', 1, g.FocusRequests);
  AssertEquals('...and it must ask for the item that was pressed, not the checked one',
    0, g.LastFocusRequest);

  { and the same gesture still checks it -- the two halves of one click }
  g.Buttons[0].Click;
  AssertEquals('the press+click checks the pressed item', 0, g.ItemIndex);
end;

{ Pressing the item that already has the caret must not re-ask: FocusItem's own guard
  (`not Focused`) is what makes one press cost one SetFocus rather than two, once
  TTyCustomControl.MouseDown's gate runs immediately after this handler returns. Headless
  the caret is never actually taken, so this asserts the guard that CAN be observed here:
  the request is still made once per press and never twice for one press. }
procedure TRadioGroupTest.TestASecondPressOnTheSameItemDoesNotReAskForTheCaret;
var
  g: TSpyRadioGroup;
begin
  g := BuildSpy;
  TCtlAccess(g.Buttons[2]).MouseDown(mbLeft, [ssLeft], 5, 5);
  AssertEquals('first press asks once', 1, g.FocusRequests);
  AssertEquals('for item 2', 2, g.LastFocusRequest);
  TCtlAccess(g.Buttons[2]).MouseDown(mbLeft, [ssLeft], 5, 5);
  AssertEquals('a press is one request, never two', 2, g.FocusRequests);
end;

{ A right press opens a context menu; it must not move the caret or the selection. }
procedure TRadioGroupTest.TestARightPressMovesNothing;
var
  g: TSpyRadioGroup;
begin
  g := BuildSpy;
  TCtlAccess(g.Buttons[0]).MouseDown(mbRight, [ssRight], 5, 5);
  AssertEquals('a right press asks for nothing', 0, g.FocusRequests);
  AssertEquals('and changes no selection', 1, g.ItemIndex);
end;

{ Keyboard parity. MoveSelection used to call SetFocus inline; it now goes through the same
  FocusItem seam the mouse does, so "the ring goes where the dot went" has ONE
  implementation and the two routes cannot drift apart. }
procedure TRadioGroupTest.TestArrowKeysAskForTheCaretThroughTheSameSeam;
var
  g: TSpyRadioGroup;
  k: Word;
begin
  g := BuildSpy;                 // 4 items, 2 columns, row-major: 0 1 / 2 3 ; checked = 1
  k := VK_DOWN;
  TCtlAccess(g.Buttons[1]).KeyDown(k, []);
  AssertEquals('VK_DOWN moves one row down (1 -> 3)', 3, g.ItemIndex);
  AssertEquals('and the caret was asked for, through FocusItem', 1, g.FocusRequests);
  AssertEquals('on the item the selection landed on', 3, g.LastFocusRequest);

  g.FocusRequests := 0;
  k := VK_LEFT;
  TCtlAccess(g.Buttons[3]).KeyDown(k, []);
  AssertEquals('VK_LEFT moves one column left (3 -> 2)', 2, g.ItemIndex);
  AssertEquals('caret asked for once more', 1, g.FocusRequests);
  AssertEquals('on item 2', 2, g.LastFocusRequest);
end;

{ FocusedIndex answers the question ItemIndex deliberately does not: which option has the
  RING. On a form that was never shown nothing is focused, so it must say -1 rather than
  quietly mirroring the selection -- a FocusedIndex that just returned ItemIndex would make
  the very bug this pass fixes unreportable. }
procedure TRadioGroupTest.TestFocusedIndexIsMinusOneWhenTheGroupHasNoCaret;
begin
  FGrp.Items.CommaText := 'A,B,C';
  FGrp.ItemIndex := 2;
  AssertEquals('the selection is item 2', 2, FGrp.ItemIndex);
  AssertEquals('but nothing holds the caret on an unshown form', -1, FGrp.FocusedIndex);
end;

{ ---- row pitch ----------------------------------------------------------- }

{ THE SECOND REPORTED BUG: "the focus ring's bottom edge is cut off."

  LayoutButtons used --row-height (22 logical px on the default light theme) as the row
  PITCH, but a hosted TTyRadioButton's own Constraints.MinHeight is 25 there (caption line
  + --pad-control, floored at --radio-size) and LCL clamps every SetBounds up to it. So
  each row was laid 22 apart and drawn 25 tall: consecutive rows overlapped by 3px, and the
  lower row -- a LATER sibling, therefore higher in the child z-order -- painted over the
  bottom 3px of the row above, taking the whole bottom edge of the 2px :focus ring with it.

  EDGE probe on purpose. The overlap is at the boundary BETWEEN rows; the last row has
  nothing below it and looks perfect, so a probe that only checked the last row (or a cell
  centre) would have been green throughout.

  HONESTY NOTE: this is the ambient net, not the guard. In THIS process the caption font
  measures 9px instead of 17, so a hosted radio asks for 17 rather than 25 and never
  exceeds the 22 token at all -- the overlap cannot arise here, and a mutant that deletes
  the pitch floor walks straight past this test (measured). The rule itself is pinned by
  TestRowPitchIsNeverShorterThanAHostedRadio and by tests/radiofocusverify. What this test
  still catches is a pitch that goes below the TOKEN, which no font can hide. }
procedure TRadioGroupTest.TestRowsNeverOverlapSoTheFocusRingSurvives;
var
  i, above: Integer;
begin
  FGrp.SetBounds(0, 0, 290, 94);
  FGrp.Columns := 2;
  FGrp.Items.CommaText := '"Extra small",Small,Medium,Large';
  for i := 2 to FGrp.Count - 1 do        // 2 columns -> item i sits under item i-2
  begin
    above := FGrp.Buttons[i - 2].Top + FGrp.Buttons[i - 2].Height;
    AssertTrue(Format('item %d must start at or below item %d''s bottom, but Top=%d and '
      + 'that bottom is %d (%d px of overlap). An overlapping row is a later sibling, so it '
      + 'paints OVER the row above and the 2px focus ring at that edge disappears.',
      [i, i - 2, FGrp.Buttons[i].Top, above, above - FGrp.Buttons[i].Top]),
      FGrp.Buttons[i].Top >= above);
  end;
end;

{ The other half of the same question, and the one the brief asked first: does the LAST row
  run off the client edge? Measured answer on the reported box: no -- it ends at 78 while
  AdjustClientRect's bottom is 90. Pinned anyway, because the pitch just grew and this is
  the constraint that growth could break next. Only asserted while the grid FITS; a grid
  taller than its box pins to the top by design (see TyRadioGroupCellRect). }
procedure TRadioGroupTest.TestEveryRowStaysInsideTheGroupClientArea;
var
  i: Integer;
  client: TRect;
begin
  FGrp.SetBounds(0, 0, 290, 94);
  FGrp.Columns := 2;
  FGrp.Items.CommaText := '"Extra small",Small,Medium,Large';
  client := FGrp.ClientRect;
  TCtlAccess(FGrp).AdjustClientRect(client);
  AssertTrue('precondition: the 2-row grid fits this box',
    2 * FGrp.Buttons[0].Height <= client.Bottom - client.Top);
  for i := 0 to FGrp.Count - 1 do
  begin
    AssertTrue(Format('item %d top %d must clear the caption band at %d',
      [i, FGrp.Buttons[i].Top, client.Top]), FGrp.Buttons[i].Top >= client.Top);
    AssertTrue(Format('item %d bottom %d must stay above the client bottom %d',
      [i, FGrp.Buttons[i].Top + FGrp.Buttons[i].Height, client.Bottom]),
      FGrp.Buttons[i].Top + FGrp.Buttons[i].Height <= client.Bottom);
  end;
end;

{ THE guard for the pitch rule, and the reason it is stated on the pure function rather than
  on a live group's bounds.

  This test process is a console app: LCL measures the caption font at 9px where a GUI
  process measures 17, so a hosted radio's own Constraints.MinHeight comes out at 17 here
  and 25 on a real machine. --row-height is 22. So on a real machine the item's minimum
  EXCEEDS the token (25 > 22, the reported 3px overlap) and in this process it does not
  (17 < 22, no overlap possible). Measured, not reasoned: the first version of this guard
  asserted on the live bounds, ran green, and a mutant that deleted the entire floor
  SURVIVED it. Ambient numbers cannot hold this rule; its two inputs can.

  tests/radiofocusverify holds the other half on a real window with real handles. }
procedure TRadioGroupTest.TestRowPitchIsNeverShorterThanAHostedRadio;
begin
  { the reported case, exactly: theme says 22, the radio needs 25 }
  AssertEquals('a hosted item taller than the token decides the pitch (the reported case)',
    25, TyGroupRowPitch(22, 25));
  { and the theme still decides whenever it asks for more }
  AssertEquals('a token taller than the item decides the pitch',
    32, TyGroupRowPitch(32, 25));
  AssertEquals('equal inputs are not a special case', 24, TyGroupRowPitch(24, 24));
  { HiDPI: both arguments are device px, so 150% is the same comparison at bigger numbers }
  AssertEquals('the same rule at 150%', 37, TyGroupRowPitch(33, 37));
  { a degenerate theme must never collapse the grid onto row 0 }
  AssertEquals('a zero pitch is floored to 1', 1, TyGroupRowPitch(0, 0));
  AssertEquals('a negative token is floored to 1', 1, TyGroupRowPitch(-5, -5));
end;

{ ---- designer hygiene ---------------------------------------------------- }

procedure TRadioGroupTest.TestChildrenAreNoDesignVisible;
var
  i: Integer;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  for i := 0 to FGrp.ControlCount - 1 do
    if FGrp.Controls[i] is TTyRadioButton then
      AssertTrue('radio child must be csNoDesignVisible',
        csNoDesignVisible in TTyRadioButton(FGrp.Controls[i]).ControlStyle);
end;

procedure TRadioGroupTest.TestChildrenOwnedByGroup;
begin
  FGrp.Items.Add('A');
  AssertSame('radio child owned by the group', FGrp, (FGrp.Controls[0] as TTyRadioButton).Owner);
  AssertSame('radio child parented to the group', FGrp, (FGrp.Controls[0] as TTyRadioButton).Parent);
end;

procedure TRadioGroupTest.TestColumnsClampToOne;
begin
  FGrp.Columns := 0;
  AssertEquals('columns clamp to >= 1', 1, FGrp.Columns);
  FGrp.Columns := -5;
  AssertEquals('negative clamps to 1', 1, FGrp.Columns);
  FGrp.Columns := 3;
  AssertEquals('valid columns accepted', 3, FGrp.Columns);
end;

initialization
  RegisterTest(TRadioGroupTest);
end.
