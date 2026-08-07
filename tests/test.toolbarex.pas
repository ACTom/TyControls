unit test.toolbarex;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  tyControls.ToolBar, tyControls.ToolBarEx, tyControls.Button;
type
  { The pure fit/overflow decision — the headless-tested core. }
  TToolBarExOverflowTest = class(TTestCase)
  published
    procedure TestAllFitNoChevron;
    procedure TestExactFitNoChevron;
    procedure TestOverflowReservesChevron;
    procedure TestAlwaysAtLeastOne;
    procedure TestEmpty;
    procedure TestChevronEatsIntoAvail;
    procedure TestZeroChevronWidthClamped;
  end;

  { A probe that drives the protected AlignControls synchronously (headless has no message
    pump), mirroring TTyToolBarAccess.ForceLayout in test.toolbar. }
  TTyToolBarExAccess = class(TTyToolBarEx)
  public
    procedure ForceLayout;
    function StyleTypeKey: string;
  end;

  { A button that counts hidden->visible transitions, to prove a steady re-layout does not
    force overflow buttons back on (the old AlignControls re-showed EVERY candidate before
    measuring, so each pass toggled the overflow set on then off — that per-pass churn is what
    made LCL abort with an InvalidatePreferredSize loop in the real GUI). }
  TCountingButton = class(TTyButton)
  public
    ShowCount: Integer;
    procedure SetVisible(Value: Boolean); override;
  end;

  { The control: which-buttons-hidden set, the chevron show/hide, the wrapping passthrough. }
  TToolBarExControlTest = class(TTestCase)
  private
    FForm: TForm;
    function MakeBtn(ABar: TWinControl; AWidth: Integer): TTyButton;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInheritsToolBarTypeKey;
    procedure TestNoOverflowWhenAllFit;
    procedure TestTrailingButtonsOverflow;
    procedure TestWiderBarRestoresHiddenButtons;
    procedure TestChevronIsNoDesignVisible;
    procedure TestChevronNotInOverflowSet;
    procedure TestWrapableSkipsOverflow;
    procedure TestWrapableGeometryIsTheBaseSolvers;
    procedure TestFreedChildDropsFromOverflow;
    procedure TestSteadyRelayoutDoesNotReshowOverflow;
    procedure TestSpaceHolderIsNotGivenTheGhostVariant;
    procedure TestOverflowFitUsesFlooredWidths;
  end;

implementation

{ TToolBarExOverflowTest }

procedure TToolBarExOverflowTest.TestAllFitNoChevron;
begin
  // 3x 40 = 120 <= 200 -> all fit, no chevron, count = 3.
  AssertEquals('all fit', 3, TyToolbarOverflowCount([40, 40, 40], 200, 30));
end;

procedure TToolBarExOverflowTest.TestExactFitNoChevron;
begin
  // total exactly equals avail -> still "all fit" (<= is inclusive), no chevron.
  AssertEquals('exact fit', 3, TyToolbarOverflowCount([50, 50, 50], 150, 30));
end;

procedure TToolBarExOverflowTest.TestOverflowReservesChevron;
begin
  // 4x 60 = 240 > 200 -> overflow. avail-chevron = 200-30 = 170 -> 2 lead buttons (120)
  // fit, a 3rd (180) would exceed 170.
  AssertEquals('overflow leaves 2', 2, TyToolbarOverflowCount([60, 60, 60, 60], 200, 30));
end;

procedure TToolBarExOverflowTest.TestAlwaysAtLeastOne;
begin
  // A single button wider than the whole bar still shows (never 0).
  AssertEquals('at least one', 1, TyToolbarOverflowCount([500], 100, 30));
  // Two huge buttons: still at least the first.
  AssertEquals('at least the first of two', 1, TyToolbarOverflowCount([500, 500], 100, 30));
end;

procedure TToolBarExOverflowTest.TestEmpty;
begin
  AssertEquals('no buttons -> 0', 0, TyToolbarOverflowCount([], 200, 30));
end;

procedure TToolBarExOverflowTest.TestChevronEatsIntoAvail;
begin
  // 3x 70 = 210 > 200 -> overflow. With chevron 30, avail = 170; only 2 (140) fit.
  AssertEquals('chevron reserved', 2, TyToolbarOverflowCount([70, 70, 70], 200, 30));
  // Widen the bar so all fit exactly at the total (210) -> no chevron, count 3.
  AssertEquals('all fit when wide', 3, TyToolbarOverflowCount([70, 70, 70], 210, 30));
end;

procedure TToolBarExOverflowTest.TestZeroChevronWidthClamped;
begin
  // A negative chevron width is clamped to 0 (no crash / no negative avail growth).
  // 3x 80 = 240 > 100 -> overflow; avail = 100 -> only 1 fits (2nd would be 160).
  AssertEquals('neg chevron clamped', 1, TyToolbarOverflowCount([80, 80, 80], 100, -5));
end;

{ TTyToolBarExAccess }

procedure TTyToolBarExAccess.ForceLayout;
var dummy: TRect;
begin
  // AlignControls uses ClientWidth internally (ignores ARect); in the headless runner
  // ClientWidth matches Width so positions are deterministic.
  dummy := Rect(0, 0, Width, Height);
  AlignControls(nil, dummy);
end;

procedure TCountingButton.SetVisible(Value: Boolean);
begin
  if Value and not Visible then Inc(ShowCount);
  inherited SetVisible(Value);
end;

function TTyToolBarExAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

{ TToolBarExControlTest }

procedure TToolBarExControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 500, 200);
end;

procedure TToolBarExControlTest.TearDown;
begin
  FForm.Free;
end;

function TToolBarExControlTest.MakeBtn(ABar: TWinControl; AWidth: Integer): TTyButton;
begin
  Result := TTyButton.Create(FForm);
  Result.Parent := ABar;
  Result.Width := AWidth;
end;

procedure TToolBarExControlTest.TestInheritsToolBarTypeKey;
var TB: TTyToolBarExAccess;
begin
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  AssertEquals('inherits TyToolBar typeKey', 'TyToolBar', TB.StyleTypeKey);
end;

procedure TToolBarExControlTest.TestNoOverflowWhenAllFit;
var TB: TTyToolBarExAccess;
begin
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  TB.Align := alNone;
  TB.Wrapable := False;
  TB.Indent := 4;
  TB.ButtonSpacing := 2;
  TB.ButtonHeight := 24;
  TB.Width := 300;

  MakeBtn(TB, 60);
  MakeBtn(TB, 60);
  TB.ForceLayout;

  AssertEquals('nothing overflows', 0, TB.OverflowCount);
  AssertFalse('no chevron shown', TB.OverflowVisible);
end;

procedure TToolBarExControlTest.TestTrailingButtonsOverflow;
var
  TB: TTyToolBarExAccess;
  B1, B2, B3, B4: TTyButton;
begin
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  TB.Align := alNone;
  TB.Wrapable := False;
  TB.Indent := 0;
  TB.ButtonSpacing := 0;
  TB.ButtonHeight := 24;
  TB.Width := 200;   // avail - chevron(30) = 170

  B1 := MakeBtn(TB, 60);
  B2 := MakeBtn(TB, 60);
  B3 := MakeBtn(TB, 60);   // 3rd (180) exceeds 170 -> overflow
  B4 := MakeBtn(TB, 60);
  TB.ForceLayout;

  // 4x60 = 240 > 200 -> overflow. 2 lead fit (120 <= 170), 2 go to overflow.
  AssertEquals('two overflow', 2, TB.OverflowCount);
  AssertTrue('chevron shown', TB.OverflowVisible);
  AssertTrue('B1 stays visible', B1.Visible);
  AssertTrue('B2 stays visible', B2.Visible);
  AssertFalse('B3 hidden into overflow', B3.Visible);
  AssertFalse('B4 hidden into overflow', B4.Visible);
end;

procedure TToolBarExControlTest.TestWiderBarRestoresHiddenButtons;
var
  TB: TTyToolBarExAccess;
  B1, B2, B3: TTyButton;
begin
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  TB.Align := alNone;
  TB.Wrapable := False;
  TB.Indent := 0;
  TB.ButtonSpacing := 0;
  TB.ButtonHeight := 24;

  B1 := MakeBtn(TB, 60);
  B2 := MakeBtn(TB, 60);
  B3 := MakeBtn(TB, 60);

  // Narrow first -> overflow.
  TB.Width := 120;
  TB.ForceLayout;
  AssertTrue('some overflow when narrow', TB.OverflowCount > 0);
  AssertFalse('B3 hidden when narrow', B3.Visible);

  // Widen so all three (180) fit -> the hidden button must come back.
  TB.Width := 400;
  TB.ForceLayout;
  AssertEquals('no overflow when wide', 0, TB.OverflowCount);
  AssertFalse('chevron gone', TB.OverflowVisible);
  AssertTrue('B1 visible', B1.Visible);
  AssertTrue('B2 visible', B2.Visible);
  AssertTrue('B3 restored visible', B3.Visible);
end;

procedure TToolBarExControlTest.TestChevronIsNoDesignVisible;
var
  TB: TTyToolBarExAccess;
  i: Integer;
  more: TControl;
begin
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  TB.Align := alNone;
  TB.Wrapable := False;
  TB.Width := 100;

  MakeBtn(TB, 80);
  MakeBtn(TB, 80);   // force overflow -> the chevron button is created
  TB.ForceLayout;
  AssertTrue('chevron shown', TB.OverflowVisible);

  // Find the chevron child (the one that is NOT a caption-less content button) — it is the
  // only child carrying csNoDesignVisible.
  more := nil;
  for i := 0 to TB.ControlCount - 1 do
    if csNoDesignVisible in TB.Controls[i].ControlStyle then
      more := TB.Controls[i];
  AssertNotNull('a csNoDesignVisible chevron exists', more);
end;

procedure TToolBarExControlTest.TestChevronNotInOverflowSet;
var
  TB: TTyToolBarExAccess;
begin
  // Even when many buttons overflow, the internal chevron must never be counted as an
  // overflow content button (it is skipped in the layout scan).
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  TB.Align := alNone;
  TB.Wrapable := False;
  TB.Indent := 0;
  TB.ButtonSpacing := 0;
  TB.ButtonHeight := 24;
  TB.Width := 100;

  MakeBtn(TB, 80);
  MakeBtn(TB, 80);
  MakeBtn(TB, 80);
  TB.ForceLayout;
  // 3 content buttons, avail-chevron = 70 -> only 1 lead fits -> 2 overflow (not 3, the
  // chevron is not a content button).
  AssertEquals('overflow excludes the chevron', 2, TB.OverflowCount);
end;

procedure TToolBarExControlTest.TestWrapableSkipsOverflow;
var
  TB: TTyToolBarExAccess;
begin
  // With Wrapable=True the base wrapping layout runs and NO chevron is used, exactly like
  // TTyToolBar (the overflow path is bypassed).
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  TB.Align := alNone;
  TB.Wrapable := True;
  TB.Indent := 4;
  TB.ButtonSpacing := 2;
  TB.ButtonHeight := 24;
  TB.Width := 100;   // narrow enough that non-wrapping would overflow

  MakeBtn(TB, 60);
  MakeBtn(TB, 60);
  MakeBtn(TB, 60);
  TB.ForceLayout;

  AssertEquals('wrapping never overflows', 0, TB.OverflowCount);
  AssertFalse('wrapping shows no chevron', TB.OverflowVisible);
end;

procedure TToolBarExControlTest.TestWrapableGeometryIsTheBaseSolvers;
var
  TB: TTyToolBarExAccess;
  B1, B2, B3: TTyButton;
begin
  { TestWrapableSkipsOverflow proves the chevron path is BYPASSED when Wrapable=True. It does
    not prove what the buttons then do -- so a change to the base solver could move every tool
    on every Ex bar and nothing here would notice. This subclass overrides AlignControls
    WHOLESALE and reaches the base only through that one `inherited` call, which is exactly the
    seam that has been missed in this file before.

    The widths are chosen to land on the wrap rule's BOUNDARY, so this also pins the comparison
    itself through the subclass: bar 100, indent 4 -> the usable edge is 96. B2 ends at
    4+46+2+44 = 96 exactly. The rule is `>`, so 96 does NOT wrap and B2 stays on row 1 at
    x = 4+46+2 = 52; a rule of `>=` would drop it to row 2 at the indent. B3 then genuinely
    overflows (98+60 = 158) and opens row 2.

    Tops are asserted as a DIFFERENCE, never as an absolute: the first row starts at
    ContentPadY, a theme token (--toolbar-pad-y) whose value is not this test's business. The
    difference is ButtonHeight + ButtonSpacing = 26 and is pure layout arithmetic. }
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  TB.Align := alNone;
  TB.Wrapable := True;
  TB.Indent := 4;
  TB.ButtonSpacing := 2;
  TB.ButtonHeight := 24;
  TB.Width := 100;

  B1 := MakeBtn(TB, 46);
  B2 := MakeBtn(TB, 44);
  B3 := MakeBtn(TB, 60);
  TB.ForceLayout;

  AssertEquals('b1 starts at the indent', 4, B1.Left);
  AssertEquals('b2 ends exactly ON the usable edge, so it does NOT wrap', 52, B2.Left);
  AssertEquals('b2 shares b1''s row', B1.Top, B2.Top);
  AssertEquals('b3 overflows and restarts at the indent', 4, B3.Left);
  AssertEquals('b3 is one row down: buttonHeight + spacing', 26, B3.Top - B1.Top);
  AssertEquals('wrapping still never overflows', 0, TB.OverflowCount);
end;

procedure TToolBarExControlTest.TestFreedChildDropsFromOverflow;
var
  TB: TTyToolBarExAccess;
  B3: TTyButton;
begin
  // A freed overflow child must be removed from the per-child overflow assignment
  // (Notification/opRemove), leaving no dangling pointer.
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  TB.Align := alNone;
  TB.Wrapable := False;
  TB.Indent := 0;
  TB.ButtonSpacing := 0;
  TB.ButtonHeight := 24;
  TB.Width := 100;

  MakeBtn(TB, 80);
  MakeBtn(TB, 80);
  B3 := MakeBtn(TB, 80);
  TB.ForceLayout;
  AssertTrue('B3 is in overflow', TB.OverflowCount >= 1);

  B3.Free;   // fires Notification(opRemove) on the bar
  AssertTrue('overflow count dropped by the freed child',
    TB.OverflowCount <= 1);   // was 2 (B2,B3); B3 removed -> 1
end;

procedure TToolBarExControlTest.TestSteadyRelayoutDoesNotReshowOverflow;
var
  TB: TTyToolBarExAccess;
  B3, B4: TCountingButton;
  i: Integer;
begin
  // A steady re-layout (nothing changed) must leave the overflow buttons hidden WITHOUT
  // toggling them back on first. Re-showing an overflow button every pass is what invalidated
  // the preferred size each time and made the real GUI abort with an InvalidatePreferredSize
  // loop. Here we count hidden->visible transitions on the two overflow buttons across a second
  // layout: it must be zero.
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  TB.Align := alNone;
  TB.Wrapable := False;
  TB.Indent := 0;
  TB.ButtonSpacing := 0;
  TB.ButtonHeight := 24;
  TB.Width := 200;   // avail - chevron(30) = 170

  // Two lead buttons fit (120 <= 170); the last two overflow.
  MakeBtn(TB, 60);
  MakeBtn(TB, 60);
  B3 := TCountingButton.Create(FForm); B3.Parent := TB; B3.Width := 60;
  B4 := TCountingButton.Create(FForm); B4.Parent := TB; B4.Width := 60;

  TB.ForceLayout;                       // initial: B3/B4 pushed to overflow (hidden)
  AssertFalse('B3 hidden after first layout', B3.Visible);
  AssertFalse('B4 hidden after first layout', B4.Visible);

  B3.ShowCount := 0;
  B4.ShowCount := 0;
  for i := 1 to 3 do TB.ForceLayout;    // steady re-layouts: overflow set is unchanged

  AssertEquals('B3 never re-shown during steady re-layout', 0, B3.ShowCount);
  AssertEquals('B4 never re-shown during steady re-layout', 0, B4.ShowCount);
  AssertFalse('B3 still hidden', B3.Visible);
  AssertFalse('B4 still hidden', B4.Visible);
end;

procedure TToolBarExControlTest.TestSpaceHolderIsNotGivenTheGhostVariant;
var
  TB: TTyToolBarExAccess;
  cmd, sep: TTyToolButton;
begin
  { This override keeps its OWN copy of the base's flat/ghost rule (it never calls
    ApplyToButton), so it needs its own copy of the space-holder exception too — a tbsSeparator
    resolves the 'TyToolSeparator' key, where a 'ghost' variant no skin defines is meaningless
    and leaves a StyleClass on a control the host never styled. The Ex bar has already been the
    place where one copy of this rule was fixed and the other was not. }
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Align := alNone;
  TB.Wrapable := False;
  TB.Width := 300;
  AssertTrue('the bar is flat (or this proves nothing)', TB.Flat);

  cmd := TTyToolButton.Create(FForm); cmd.Parent := TB; cmd.Width := 40;
  sep := TTyToolButton.Create(FForm); sep.Parent := TB; sep.Style := tbsSeparator;
  TB.ForceLayout;

  AssertEquals('a command tool button DOES take the flat variant', 'ghost', cmd.StyleClass);
  AssertEquals('a space holder is left alone', '', sep.StyleClass);
end;

procedure TToolBarExControlTest.TestOverflowFitUsesFlooredWidths;
var
  TB: TTyToolBarExAccess;
  B1, B2, B3: TTyToolButton;
  i: Integer;
begin
  { The base bar's ButtonWidth floor must reach the OVERFLOW fit too: the decision has to be
    made over the widths the buttons are actually laid out at, or a floored button would be
    judged to fit by its narrower natural width and then be drawn overlapping the chevron. }
  TB := TTyToolBarExAccess.Create(FForm);
  TB.Parent := FForm;
  TB.Font.PixelsPerInch := 96;
  TB.Align := alNone;
  TB.Wrapable := False;
  TB.Indent := 0;
  TB.ButtonSpacing := 0;
  TB.ButtonHeight := 24;
  TB.Width := 200;   // avail - chevron(30) = 170

  for i := 1 to 3 do
  begin
    with TTyToolButton.Create(FForm) do
    begin
      Parent := TB;
      Width := 30;
    end;
  end;
  B1 := TTyToolButton(TB.Controls[0]);
  B2 := TTyToolButton(TB.Controls[1]);
  B3 := TTyToolButton(TB.Controls[2]);

  TB.ForceLayout;
  AssertEquals('3x30 = 90 fits a 200 bar with room to spare', 0, TB.OverflowCount);

  TB.ButtonWidth := 80;   // floored: 3x80 = 240 > 200; 2 fit in avail-chevron (160 <= 170)
  TB.ForceLayout;
  AssertEquals('the fit is decided over the FLOORED widths', 1, TB.OverflowCount);
  AssertEquals('and the lead buttons are laid out at the floor', 80, B1.Width);
  AssertEquals('...both of them', 80, B2.Width);
  AssertFalse('the third went to the overflow', B3.Visible);

  TB.ButtonWidth := 0;    // floor off: everything fits again, widths restored
  TB.ForceLayout;
  AssertEquals('no overflow once the floor is lowered', 0, TB.OverflowCount);
  AssertEquals('and the natural width comes back', 30, B1.Width);
end;

initialization
  RegisterTest(TToolBarExOverflowTest);
  RegisterTest(TToolBarExControlTest);
end.
