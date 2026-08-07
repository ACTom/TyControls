unit test.focus.tabstop;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, Controls, Forms, LCLType, LMessages,
  fpcunit, testregistry,
  tyControls.Base, tyControls.ScrollBar,
  { focusable side }
  tyControls.Button, tyControls.ColorButton, tyControls.DropButtons,
  tyControls.GlyphButtons, tyControls.ButtonGroup, tyControls.ColorGrid,
  tyControls.Calculator, tyControls.Grid, tyControls.HeaderControl, tyControls.HSColorPicker,
  tyControls.LColorPicker, tyControls.ImageView, tyControls.Edit,
  tyControls.ListBox, tyControls.CheckBox, tyControls.Segmented,
  tyControls.TreeView, tyControls.ListView, tyControls.ToggleSwitch,
  tyControls.Menu, tyControls.RibbonBackstage,
  { non-focusable side }
  tyControls.Panel, tyControls.Card, tyControls.GroupBox, tyControls.TabSheet,
  tyControls.FormSurface, tyControls.ToolBar, tyControls.StatusBar,
  tyControls.Ribbon, tyControls.RibbonQuickAccess, tyControls.Empty,
  tyControls.Splitter, tyControls.ExPanel, tyControls.CheckGroup,
  tyControls.RadioGroup, tyControls.ToolGroupPanel, tyControls.ScrollBox,
  tyControls.RelativePanel, tyControls.PaintPanel, tyControls.ControlBar,
  tyControls.Transfer, tyControls.Steps;

type
  { Any windowed TyControl, as a class reference — TabStop is published on
    TTyCustomControl, so one table can carry them all. }
  TTyCtlClass = class of TTyCustomControl;
  TTyCtlClassArray = array of TTyCtlClass;

  { WHY this suite exists.

    TTyCustomControl.MouseDown is the ONLY thing that focuses a custom-drawn control on
    click (LCL focuses native widgets for you and nothing else), and it gates that on
    TabStop. LCL's TWinControl defaults TabStop to False. So a control that forgets the
    one line in its constructor is not merely absent from the Tab order — it can never be
    focused at all, its KeyDown is dead code, and the user's report is "clicking this
    control does nothing". That failure is invisible at compile time and invisible in a
    paint test, which is why it survived across dozens of controls.

    The two tables below are the DECISION, written down: a control belongs on the
    focusable side exactly when the user can do something with it once it holds focus
    (press it, type in it, arrow around it), and on the other side when it is a container
    or chrome whose interactive parts are its children. Moving a control between the
    tables is meant to be a deliberate edit, not something that happens by accident. }
  TTyFocusTabStopTest = class(TTestCase)
  private
    FForm: TForm;
    { Construct AClass owned by the test form (no Parent needed — TabStop is decided in
      the constructor) and hand it back for inspection. }
    function Build(AClass: TTyCtlClass): TTyCustomControl;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestControlsThatActOnInputAreTabStops;
    procedure TestContainersAndChromeStayOutOfTheFocusOrder;
    procedure TestPublishedDefaultAgreesWithTheConstructedValue;
    procedure TestEmbeddedScrollBarsNeverTakeFocusFromTheirHost;
    procedure TestTransferRailStaysOutOfTheTabOrder;
    procedure TestCalculatorKeypadIsNotTheTabOrder;
  end;

  { WHY a SECOND suite, on top of the TabStop tables above.

    Everything above reads a FLAG. Not one assertion in it proves the flag is connected to
    anything: TTyCustomControl.MouseDown is what turns a click into focus, and a descendant
    that overrides MouseDown and forgets `inherited`, or that swallows a CM_ message without
    passing it on, keeps TabStop=True and still cannot be focused by clicking. The user's
    report ("clicking this control does nothing") would be identical, and every test above
    would stay green. That gap is the whole reason the author had to promise the forum a
    systematic focus pass.

    So this suite drives the CHAIN, not the flag: a real, handle-allocated, visible form;
    focus parked on a known control; then the very LM_LBUTTONDOWN the widgetset posts when
    the OS reports a click, delivered by Perform straight into the control's own WindowProc.
    Perform rather than a Win32 PostMessage on purpose -- it is the same entry point every
    widgetset uses, so the guard is not Win32-only, and it still runs the whole real path
    (WindowProc -> WMLButtonDown -> TControl.MouseDown -> TTyCustomControl.MouseDown ->
    SetFocus).

    The form must be genuinely VISIBLE, not merely handle-allocated: CanFocus is False for a
    hidden control, and TTyCustomControl.MouseDown gates on CanFocus, so a hidden-form
    version of this test would pass vacuously for every control -- including a control whose
    SetFocus call had been deleted. It is parked off-screen so the suite stays quiet. }
  TTyClickFocusTest = class(TTestCase)
  private
    FForm: TForm;
    FPark: TTyEdit;
    { Build AClass on the visible form, park focus on FPark, click it, and report where
      focus ended up. Frees the control before returning. }
    function ClickAndReportFocus(AClass: TTyCtlClass; out AMoved: Boolean): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAClickActuallyLandsFocusOnEveryFocusableControl;
    procedure TestTheGuardIsNotVacuousForANonFocusableControl;
    procedure TestClickThenArrowWalksAClickableStepsRail;
  end;

implementation

{ TTyCustomGrid and TTyListView keep their two scroll bars PROTECTED, so reach them the way
  this repo already reaches protected members from a test: a descendant declared here, used
  purely as a cast. }
type
  TGridAccess = class(TTyCustomGrid);
  TListViewAccess = class(TTyListView);


{ Controls the user OPERATES: a click must land focus on them, and Tab must reach them.
  Each one either handles keys itself (button: Space/Enter; scroll bar: arrows/page/Home/
  End; grid, tree, list, edit: the lot) or is the direct target of a click that changes
  its value (colour grid, hue/saturation pickers, header sections, segmented bars). }
function FocusableControls: TTyCtlClassArray;
begin
  Result := TTyCtlClassArray.Create(
    { push buttons and everything derived from one }
    TTyButton, TTyColorButton, TTyDropDownButton, TTyMenuButton,
    TTyGlyphButton, TTyGlyphContainerButton,
    { selection / picker / data controls fixed in this pass }
    TTyButtonGroup, TTyColorGrid, TTyDrawGrid, TTyStringGrid, TTyHeaderControl,
    TTyHSColorPicker, TTyLColorPicker, TTyImageView, TTyScrollBar,
    { already focusable before this pass — listed so a regression shows up as a failure,
      and because several of them only got their DECLARED default fixed in it }
    TTyEdit, TTyListBox, TTyCheckBox, TTySegmented, TTyTreeView, TTyListView,
    TTyCalculator, TTyToggleSwitch, TTyMenuBar, TTyRibbonBackstage);
end;

{ Containers and chrome. Every one of these either holds the real controls as children
  (panel, card, group box, page, scroll box, tool bar, transfer box) or is painted
  furniture (status bar, splitter, empty-state). Giving one a tab stop makes a click
  ANYWHERE on its surface — including the empty background between its children — steal
  focus from the child that had it, and adds a Tab stop that does nothing. }
function ContainerAndChromeControls: TTyCtlClassArray;
begin
  Result := TTyCtlClassArray.Create(
    { the one button that must not take focus — classic TSpeedButton behaviour }
    TTySpeedButton,
    { containers }
    TTyPanel, TTyCard, TTyGroupBox, TTyTabSheet, TTyFormSurface, TTyScrollBox,
    TTyRelativePanel, TTyPaintPanel, TTyControlBar, TTyExPanel, TTyCheckGroup,
    TTyRadioGroup, TTyToolGroupPanel, TTyEmpty,
    { bars / chrome }
    TTyToolBar, TTyStatusBar, TTyRibbonGroup, TTyRibbonQuickAccess, TTySplitter,
    { a composite whose interaction lives entirely in its children }
    TTyTransfer,
    { a status rail, inert until Clickable is switched on (which sets TabStop) }
    TTySteps);
end;

procedure TTyFocusTabStopTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TTyFocusTabStopTest.TearDown;
begin
  FForm.Free;   // owns every control the test built
  FForm := nil;
end;

function TTyFocusTabStopTest.Build(AClass: TTyCtlClass): TTyCustomControl;
begin
  Result := AClass.Create(FForm);
end;

procedure TTyFocusTabStopTest.TestControlsThatActOnInputAreTabStops;
var
  list: TTyCtlClassArray;
  i: Integer;
  c: TTyCustomControl;
begin
  list := FocusableControls;
  for i := 0 to High(list) do
  begin
    c := Build(list[i]);
    AssertTrue(c.ClassName + ' must be focusable: without TabStop a click on it cannot '
      + 'move focus, and its keyboard handling can never run',
      c.TabStop);
  end;
end;

procedure TTyFocusTabStopTest.TestContainersAndChromeStayOutOfTheFocusOrder;
var
  list: TTyCtlClassArray;
  i: Integer;
  c: TTyCustomControl;
begin
  list := ContainerAndChromeControls;
  for i := 0 to High(list) do
  begin
    c := Build(list[i]);
    AssertFalse(c.ClassName + ' must NOT be a tab stop: a click on its background would '
      + 'pull focus off the child that had it',
      c.TabStop);
  end;
end;

{ The .lfm side of the same knob, and a bug class of its own: FPC streams a published
  property only when its value differs from the DECLARED default. A control whose
  constructor sets TabStop := True while the declaration still says `default False`
  cannot be turned off from a form file — the designer sees False = the declared default,
  writes nothing, and the constructor's True wins again at load. The mirror case is just
  as bad: TTyDrawGrid used to declare `default True` while its constructor left TabStop
  False, so every .lfm holding one got a spurious `TabStop = False` line — and the grid
  was unfocusable anyway. So: the declared default must equal what the constructor
  actually produces.

  Scope note — this runs over the two tables above, i.e. over controls a .lfm can name.
  The library also has internal, code-created controls (the colour dialog's picker twins,
  the menu popup view) that are never streamed, so their declared default is irrelevant
  and they are deliberately not listed. }
procedure TTyFocusTabStopTest.TestPublishedDefaultAgreesWithTheConstructedValue;

  procedure CheckOne(AClass: TTyCtlClass);
  var
    c: TTyCustomControl;
    pi: PPropInfo;
  begin
    c := Build(AClass);
    pi := GetPropInfo(AClass, 'TabStop');
    AssertTrue(AClass.ClassName + ' must publish TabStop (a host has to be able to '
      + 'override it in the .lfm)', pi <> nil);
    AssertEquals(AClass.ClassName + ': the declared default must match what the '
      + 'constructor sets, or the .lfm cannot override it',
      Ord(c.TabStop), pi^.Default);
  end;

var
  list: TTyCtlClassArray;
  i: Integer;
begin
  list := FocusableControls;
  for i := 0 to High(list) do CheckOne(list[i]);
  list := ContainerAndChromeControls;
  for i := 0 to High(list) do CheckOne(list[i]);
end;

{ A standalone TTyScrollBar is focusable (it owns the arrow/page/Home/End keyboard), but
  the bars EMBEDDED in a scrolling control must not be: dragging one would move focus off
  the grid/tree/list it is scrolling, which would then drop its focus ring and its
  keyboard navigation mid-drag, and Tab would stop three times inside one widget. }
procedure TTyFocusTabStopTest.TestEmbeddedScrollBarsNeverTakeFocusFromTheirHost;
var
  standalone: TTyScrollBar;
  grid: TTyStringGrid;
  tree: TTyTreeView;
  list: TTyListView;
  box: TTyScrollBox;
  i, found: Integer;
begin
  standalone := TTyScrollBar.Create(FForm);
  AssertTrue('a scroll bar dropped on a form is a keyboard control', standalone.TabStop);

  grid := TTyStringGrid.Create(FForm);
  AssertFalse('the grid vertical bar must not steal the grid focus', TGridAccess(grid).VScrollBar.TabStop);
  AssertFalse('the grid horizontal bar must not steal the grid focus', TGridAccess(grid).HScrollBar.TabStop);
  AssertTrue('...while the grid itself takes focus', grid.TabStop);

  tree := TTyTreeView.Create(FForm);
  AssertFalse('the tree vertical bar must not steal the tree focus', tree.VScroll.TabStop);
  AssertFalse('the tree horizontal bar must not steal the tree focus', tree.HScroll.TabStop);

  list := TTyListView.Create(FForm);
  AssertFalse('the list-view vertical bar must not steal its focus', TListViewAccess(list).VScrollBar.TabStop);
  AssertFalse('the list-view horizontal bar must not steal its focus', TListViewAccess(list).HScrollBar.TabStop);

  { The scroll box keeps its two bars private, so go through its child list. A resize is
    what makes it measure (Resize -> UpdateScrollRange -> EnsureBars), so ask for one
    rather than trusting a construction-time side effect. }
  box := TTyScrollBox.Create(FForm);
  box.SetBounds(0, 0, 300, 200);
  found := 0;
  for i := 0 to box.ControlCount - 1 do
    if box.Controls[i] is TTyScrollBar then
    begin
      Inc(found);
      AssertFalse('a scroll box bar must not be a tab stop of its own',
        TTyScrollBar(box.Controls[i]).TabStop);
    end;
  AssertEquals('the scroll box built both of its bars (the loop must not be vacuous)',
    2, found);
end;

{ TTyTransfer builds its four move arrows out of TTyButton, which IS a tab stop — the box
  turns that back off per instance so Tab does not crawl through the middle of the widget
  on its way from the left pane to the right one. Guards the arrows against silently
  inheriting a change to the button base. }
procedure TTyFocusTabStopTest.TestTransferRailStaysOutOfTheTabOrder;
var
  t: TTyTransfer;
  m: TTyTransferMove;
begin
  t := TTyTransfer.Create(FForm);
  for m := Low(TTyTransferMove) to High(TTyTransferMove) do
    AssertFalse('the rail arrow ' + IntToStr(Ord(m)) + ' must stay out of the tab order',
      t.MoveButton[m].TabStop);
  AssertTrue('...while both panes stay reachable', t.LeftPane.TabStop and t.RightPane.TabStop);
end;

{ The calculator is a single keyboard control that happens to be DRAWN as twenty buttons:
  TTyCalculator.KeyDown is what turns a digit or an operator key into input. Its keypad
  children are TTyButtons, which are tab stops by default — if that leaked through, a click
  on a key would move focus onto the key, and the next keystroke would reach that button
  (whose Space/Enter just presses it again) instead of the calculator. }
procedure TTyFocusTabStopTest.TestCalculatorKeypadIsNotTheTabOrder;
var
  calc: TTyCalculator;
  i, keys: Integer;
begin
  calc := TTyCalculator.Create(FForm);
  AssertTrue('the calculator itself holds the focus — it is the thing that types',
    calc.TabStop);
  keys := 0;
  for i := 0 to calc.ControlCount - 1 do
    if calc.Controls[i] is TTyButton then
    begin
      Inc(keys);
      AssertFalse('keypad key "' + TTyButton(calc.Controls[i]).Caption
        + '" must not take focus off the calculator',
        TTyButton(calc.Controls[i]).TabStop);
    end;
  AssertTrue('the keypad was actually built (the loop above must not be vacuous)', keys > 10);
end;

{ ---------------------------------------------------------------------------------------
  TTyClickFocusTest -- the chain, not the flag.
  --------------------------------------------------------------------------------------- }

{ The console runner registers no window classes until the widgetset is up, and CreateHandle
  then fails with error 1407. Same lazy bootstrap test.base / test.form already use. }
var
  ClickFocusWidgetSet: Boolean = False;

procedure NeedWidgetSetForClicks;
begin
  if ClickFocusWidgetSet then Exit;
  Forms.Application.Initialize;
  ClickFocusWidgetSet := True;
end;

{ The lParam the widgetset packs a click position into. }
function MousePos(X, Y: Integer): PtrInt;
begin
  Result := PtrInt((Y shl 16) or (X and $FFFF));
end;

procedure TTyClickFocusTest.SetUp;
begin
  NeedWidgetSetForClicks;
  FForm := TForm.CreateNew(nil);
  { Off-screen, but genuinely shown: CanFocus needs Visible all the way up, and the whole
    point of this suite is that the gate TTyCustomControl.MouseDown checks is really open. }
  FForm.SetBounds(-4000, -4000, 640, 480);
  FForm.Visible := True;
  FForm.HandleNeeded;
  FPark := TTyEdit.Create(FForm);
  FPark.Parent := FForm;
  FPark.SetBounds(8, 8, 160, 26);
  FPark.HandleNeeded;
end;

procedure TTyClickFocusTest.TearDown;
begin
  FForm.Free;      // owns every control the test built
  FForm := nil;
  FPark := nil;
end;

function TTyClickFocusTest.ClickAndReportFocus(AClass: TTyCtlClass;
  out AMoved: Boolean): string;
var
  c: TTyCustomControl;
  before, after: TWinControl;
begin
  AMoved := False;
  Result := '<none>';
  c := AClass.Create(FForm);
  try
    c.Parent := FForm;
    { Roomy enough that a quarter-in probe point lands on the control's own body rather than
      on a scroll bar, a chevron or a spin pair parked at the far edge. }
    c.SetBounds(220, 60, 260, 150);
    { A rail is inert by contract until Clickable is on, and that property is what couples
      TabStop -- probe the configured-interactive rail, which is what the roster means. }
    if c is TTySteps then
    begin
      TTySteps(c).Items.Text := 'One' + LineEnding + 'Two' + LineEnding + 'Three';
      TTySteps(c).Clickable := True;
    end;
    { A few roster members are born hidden because their host shows them on demand (the
      ribbon backstage overlay). CanFocus is False while hidden, so probing them as-built
      would assert on visibility, not on the focus chain. }
    c.Visible := True;
    c.HandleNeeded;
    Forms.Application.ProcessMessages;

    { Park focus elsewhere FIRST, so a pass proves the click MOVED focus rather than
      finding it already there. }
    if FPark.CanFocus then FPark.SetFocus;
    Forms.Application.ProcessMessages;
    before := FForm.ActiveControl;

    { PRESS only, deliberately -- no matching LM_LBUTTONUP. Focus is taken on the press
      (TTyCustomControl.MouseDown), so the release adds nothing to what is being asserted,
      while it DOES fire Click: TTyColorButton's click opens a modal colour dialog, which
      wedges the whole console runner with no way out. Press-only keeps the guard on the
      thing it is guarding.

      LOWER-left quadrant, not upper: a quarter down the left edge sits on TTyRibbonBackstage's
      "Back" band, whose whole job is to hide the overlay -- the click focused the control and
      then closed it, which reads as a focus failure and is not one. Three-quarters down is
      clear of that band, and a quarter in from the left stays clear of the chevrons, spin
      pairs and scroll bars that live at the right edge. }
    c.Perform(LM_LBUTTONDOWN, MK_LBUTTON, MousePos(c.Width div 4, (c.Height * 3) div 4));
    Forms.Application.ProcessMessages;

    after := FForm.ActiveControl;
    if after <> nil then Result := after.ClassName;
    { Focus must have MOVED, and must have landed on the control itself or on one of its own
      embedded children (a composite legitimately hands focus to its inner editor). An
      ANCESTOR does not count -- focus falling back to the form is the failure, not a pass --
      and `after = before` never counts, or a control that focuses nothing would ride on the
      park edit's focus and every row would be green. }
    AMoved := (after <> nil) and (after <> before)
              and ((after = c) or c.IsParentOf(after));
  finally
    c.Free;
  end;
end;

procedure TTyClickFocusTest.TestAClickActuallyLandsFocusOnEveryFocusableControl;
var
  list: TTyCtlClassArray;
  i: Integer;
  moved: Boolean;
  landed: string;
begin
  list := FocusableControls;
  AssertTrue('the roster must not be empty (a vacuous loop proves nothing)',
    Length(list) > 0);
  for i := 0 to High(list) do
  begin
    landed := ClickAndReportFocus(list[i], moved);
    AssertTrue(list[i].ClassName + ': a click must land focus on it. TabStop is True, so '
      + 'the gate is open -- if this fails the MouseDown chain is broken (an override that '
      + 'forgot `inherited`, or a swallowed CM_ message). Focus ended on: ' + landed,
      moved);
  end;
end;

{ The mutation guard for the guard above. A container is deliberately NOT a tab stop, so
  clicking it must leave focus where it was -- if this ever reports "moved", the helper is
  counting something other than the click (the park edit's own focus, say) and every PASS
  in the roster test is worthless. }
procedure TTyClickFocusTest.TestTheGuardIsNotVacuousForANonFocusableControl;
var
  moved: Boolean;
begin
  ClickAndReportFocus(TTyPanel, moved);
  AssertFalse('a click on a TTyPanel must NOT move focus -- it is not a tab stop. '
    + 'If this passes, ClickAndReportFocus is not measuring the click at all.', moved);
end;

{ The forum report behind this suite (#8): the rail took no focus, so its arrow keys -- the
  half of Clickable that is not the mouse -- were dead code. Both halves, end to end, on a
  real handle: nothing else in the suite joins them up. test.steps drives the protected
  PressAt/SendKey seams directly, which cannot see a focus failure at all. }
procedure TTyClickFocusTest.TestClickThenArrowWalksAClickableStepsRail;
var
  s: TTySteps;
  wasIndex: Integer;
begin
  s := TTySteps.Create(FForm);
  s.Parent := FForm;
  s.SetBounds(220, 60, 300, 90);
  s.Items.Text := 'One' + LineEnding + 'Two' + LineEnding + 'Three';
  s.Clickable := True;
  s.StepIndex := 0;
  s.HandleNeeded;
  Forms.Application.ProcessMessages;

  if FPark.CanFocus then FPark.SetFocus;
  Forms.Application.ProcessMessages;

  s.Perform(LM_LBUTTONDOWN, MK_LBUTTON, MousePos(4, s.Height div 2));
  Forms.Application.ProcessMessages;
  AssertSame('the click must focus the rail, or no key can ever reach it',
    TWinControl(s), TWinControl(FForm.ActiveControl));

  { CN_KEYDOWN, not LM_KEYDOWN: the widgetset delivers a keystroke to the FOCUSED control as
    the CN_ notification, and that is the message TWinControl turns into KeyDown. Driving
    LM_KEYDOWN instead reaches the control but never its KeyDown, so the rail would not move
    and the test would blame the control for the harness. (test.steps' own SendKey calls
    KeyDown directly and so cannot tell these two apart -- which is exactly why this test
    exists alongside it.) }
  wasIndex := s.StepIndex;
  s.Perform(CN_KEYDOWN, VK_RIGHT, 0);
  Forms.Application.ProcessMessages;
  AssertEquals('Right on a focused horizontal rail steps forward one',
    wasIndex + 1, s.StepIndex);

  s.Perform(CN_KEYDOWN, VK_LEFT, 0);
  Forms.Application.ProcessMessages;
  AssertEquals('...and Left steps back', wasIndex, s.StepIndex);
end;

initialization
  RegisterTest(TTyFocusTabStopTest);
  RegisterTest(TTyClickFocusTest);
end.
