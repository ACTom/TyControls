unit test.focus.tabstop;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, DateUtils, TypInfo, Controls, Forms, LCLType, LCLIntf, LMessages,
  fpcunit, testregistry,
  test.designregistry,               // the runtime roster the completeness guard reads
  tyControls.Base, tyControls.ScrollBar,
  { focusable side }
  tyControls.Button, tyControls.ColorButton, tyControls.DropButtons,
  tyControls.GlyphButtons, tyControls.ButtonGroup, tyControls.ColorGrid,
  tyControls.Calculator, tyControls.Grid, tyControls.HeaderControl, tyControls.HSColorPicker,
  tyControls.LColorPicker, tyControls.ImageView, tyControls.Edit, tyControls.Columns,
  tyControls.ListBox, tyControls.CheckBox, tyControls.Segmented,
  tyControls.TreeView, tyControls.ListView, tyControls.ToggleSwitch,
  tyControls.Menu, tyControls.RibbonBackstage,
  { focusable side, added when the tables were extended from 47 classes to all 105 }
  tyControls.MaskEdit, tyControls.URLEdit, tyControls.ComboEdit, tyControls.NumericEdit,
  tyControls.CurrencyEdit, tyControls.CalcEdit, tyControls.CalcCurrencyEdit,
  tyControls.TrackEdit, tyControls.FloatSpinEdit, tyControls.SpinEdit,
  tyControls.ComboBox, tyControls.AdvancedComboBox, tyControls.CheckComboBox,
  tyControls.ColorBox, tyControls.ColorComboBox, tyControls.ComboBoxEx,
  tyControls.FilterComboBox, tyControls.FontComboBox, tyControls.FontSizeComboBox,
  tyControls.MRUComboBox, tyControls.OfficeComboBox, tyControls.ShellComboBox,
  tyControls.AdvancedListBox, tyControls.CheckListBox, tyControls.ColorListBox,
  tyControls.FontListBox, tyControls.OfficeListBox, tyControls.ValueListEditor,
  tyControls.ShellListView, tyControls.ShellTreeView,
  tyControls.PageControl, tyControls.TabSet,
  tyControls.Calendar, tyControls.DateTimePicker, tyControls.Dial, tyControls.GearDial,
  tyControls.Rating, tyControls.TrackBar, tyControls.Pagination, tyControls.Memo,
  tyControls.TreeSelect, tyControls.Cascader, tyControls.RibbonGallery,
  tyControls.ListGroupPanel, tyControls.RibbonAppMenu,
  { non-focusable side }
  tyControls.Panel, tyControls.Card, tyControls.GroupBox, tyControls.TabSheet,
  tyControls.FormSurface, tyControls.ToolBar, tyControls.StatusBar,
  tyControls.Ribbon, tyControls.RibbonQuickAccess, tyControls.Empty,
  tyControls.Splitter, tyControls.ExPanel, tyControls.CheckGroup,
  tyControls.RadioGroup, tyControls.ToolGroupPanel, tyControls.ScrollBox,
  tyControls.RelativePanel, tyControls.PaintPanel, tyControls.ControlBar,
  tyControls.Transfer, tyControls.Steps,
  { non-focusable side, same extension }
  tyControls.GridPanel, tyControls.ScrollPanel, tyControls.CoolBar, tyControls.ToolBarEx,
  tyControls.HtmlLabel, tyControls.PreviewBox, tyControls.Form;

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
    procedure TestEveryRegisteredWindowedControlIsOnATable;
    procedure TestPublishedDefaultAgreesWithTheConstructedValue;
    procedure TestEmbeddedScrollBarsNeverTakeFocusFromTheirHost;
    procedure TestAScrollBarTakesFocusOnlyWhenTabStopAsks;
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
    SetFocus call had been deleted. It is parked off-screen so the suite stays quiet.

    THE SUITE ALSO INSTALLS AN Application.OnException TRAP, and that is not decoration.

    An exception raised on this path is raised INSIDE the widgetset's WindowProc -- the
    click is dispatched by Perform, and the teardown at the end of every probe runs
    RemoveFocus, which sends WM_KILLFOCUS synchronously. Nothing there propagates back to
    the `try` in ClickAndReportFocus. LCL's TApplication.HandleException catches it instead
    and, with no OnException handler, calls ShowException -> a MODAL dialog. A console
    runner has nobody to dismiss it, so the whole suite stops dead in ShowModal with the
    CPU flat -- which is exactly how TTyCurrencyEdit took this file down before
    tyControls.Edit.pas's destructor was fixed. A trap turns that into a named failure, so
    the next control with a raising press or teardown FAILS instead of wedging the run. }
  TTyClickFocusTest = class(TTestCase)
  private
    FForm: TForm;
    FPark: TTyEdit;
    FPrevOnException: TExceptionEvent;
    FTrapped: string;
    procedure TrapException(Sender: TObject; E: Exception);
    { Fail with whatever the trap caught, if anything. Called after every probe rather than
      only in TearDown so the failure names the control that raised. }
    procedure AssertNothingRaised(const AWhere: string);
    { "Commit the field on the way out" -- the ordinary OnExit handler that used to land in
      freed memory. See TestFreeingAFocusedEditWhoseExitWritesTextDoesNotRaise. }
    procedure CommitTextOnExit(Sender: TObject);
    { Build AClass on the visible form, park focus on FPark, click it, and report where
      focus ended up. Frees the control before returning. }
    function ClickAndReportFocus(AClass: TTyCtlClass; out AMoved: Boolean): string;
    { #59: a grid whose one column edits in a pick list (apple, banana, cherry), the cells
      of rows 1 and 2 holding apple and banana. }
    function NewPickListGrid: TTyStringGrid;
    { Open the pick list on row ARow of AGrid and check it holds the focus, system and form. }
    function StartPickEdit(AGrid: TTyStringGrid; ARow: Integer): TTyComboBox;
    procedure AssertTheGridHasTheFocus(AGrid: TTyStringGrid; const AAfter: string);
    { A key as the system delivers it, to whatever window holds the focus. }
    procedure PressKey(AKey: Word; AChar: Char = #0);
    { A grid whose one column edits in AKind, row 1 holding AValue, the cursor on that cell
      and the focus on the grid -- not editing. }
    function NewEditorGrid(AKind: TTyGridEditorKind; const AValue: string): TTyStringGrid;
    { A printable key as the system delivers it: down, the character, up. }
    procedure TypeKey(AChar: Char);
    { #67: a grid whose one column edits through the mask 000-0000, row 1 holding AValue,
      the mask editor open on it with the focus. }
    function StartMaskEdit(const AValue: string; out AGrid: TTyStringGrid): TTyMaskEdit;
    { Fail unless the trap caught the mask's own "does not fill the mask" error -- the way
      LCL reports an exception raised in a key or mouse handler -- and clear it. }
    procedure AssertTheMaskWasReported(const AAfter: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAClickActuallyLandsFocusOnEveryFocusableControl;
    procedure TestTheGuardIsNotVacuousForANonFocusableControl;
    procedure TestClickThenArrowWalksAClickableStepsRail;
    procedure TestFreeingAFocusedEditWhoseExitWritesTextDoesNotRaise;
    procedure TestArrowNavigationNeverLandsOnAControlsOwnBar;
    procedure TestClickingAControlsOwnBarLeavesTheFocusWithTheControl;
    procedure TestUpDownInAPickListCellMoveTheCursor;
    procedure TestAPickInACellHandsTheFocusBackToTheGrid;
    procedure TestASpinCellKeepsTheNumberTypedIntoIt;
    procedure TestEscapeOnAnEditedMaskCellRaisesNothing;
    procedure TestAnUnfilledMaskCellIsRefusedAndReported;
    procedure TestAnUntouchedMaskCellCanAlwaysBeLeft;
    procedure TestAMaskCellWithNoMaskTakesAnyText;
    procedure TestTypingOnASpinCellStartsTheNumberWithThatKey;
    procedure TestTypingOnAMemoCellStartsTheTextWithThatKey;
    procedure TestTypingOnACalculatorCellStartsTheNumberWithThatKey;
    procedure TestTypingOnAMaskCellFillsTheFirstSlotWithThatKey;
    procedure TestTypingOnADateCellStartsTheFirstFieldWithThatKey;
    procedure TestTypingOnATimeCellStartsTheFirstFieldWithThatKey;
    procedure TestTypingOnAPickListCellPicksByThatKey;
  end;

implementation

{ TTyCustomGrid and TTyListView keep their two scroll bars PROTECTED, so reach them the way
  this repo already reaches protected members from a test: a descendant declared here, used
  purely as a cast. }
type
  TGridAccess = class(TTyCustomGrid);
  TWinAccess = class(TWinControl);   // FindNextControl is protected
  TListViewAccess = class(TTyListView);

function FocusableControls: TTyCtlClassArray; forward;

{ Used by the click probe to prove its own (narrower) roster is a SUBSET of the declared
  focusable table -- see the long note above ClickProbeControls. }
function InFocusableTable(ACls: TTyCtlClass): Boolean;
var
  list: TTyCtlClassArray;
  i: Integer;
begin
  list := FocusableControls;
  for i := 0 to High(list) do
    if list[i] = ACls then Exit(True);
  Result := False;
end;



{ Controls the user OPERATES: a click must land focus on them, and Tab must reach them.
  Each one either handles keys itself (button: Space/Enter; grid, tree, list, edit: the
  lot) or is the direct target of a click that changes
  its value (colour grid, hue/saturation pickers, header sections, segmented bars). }
function FocusableControls: TTyCtlClassArray;
begin
  Result := TTyCtlClassArray.Create(
    { push buttons and everything derived from one }
    TTyButton, TTyColorButton, TTyDropDownButton, TTyMenuButton,
    TTyGlyphButton, TTyGlyphContainerButton,
    { selection / picker / data controls fixed in this pass }
    TTyButtonGroup, TTyColorGrid, TTyDrawGrid, TTyStringGrid, TTyHeaderControl,
    TTyHSColorPicker, TTyLColorPicker, TTyImageView,
    { already focusable before this pass — listed so a regression shows up as a failure,
      and because several of them only got their DECLARED default fixed in it }
    TTyEdit, TTyListBox, TTyCheckBox, TTySegmented, TTyTreeView, TTyListView,
    TTyCalculator, TTyToggleSwitch, TTyMenuBar, TTyRibbonBackstage,

    { ===== the extension: the 47 focusable families the tables used to miss ==========
      Everything above this line was written by the click-focus sweep, which listed the
      classes it had touched: 47 entries across both tables, against 105 windowed TTy
      classes a .lfm can actually name. So 58 families had no declared-default guard at all
      -- not a known defect, a hole, and one that stayed invisible precisely because
      everything listed was green. The completeness guard below
      (TestEveryRegisteredWindowedControlIsOnATable) now derives the population from the
      design-time registry instead of from a hand-kept list, so this table cannot silently
      fall behind again.

      All 58 turned out to be already correct -- extending the tables found no live defect,
      which is the expected result for a coverage gap and is worth stating so nobody
      re-derives it. What the extension buys is the FUTURE case: mutating one newly-covered
      class's declared default (TTyDial, `default True` -> `default False`) now fails
      TestPublishedDefaultAgreesWithTheConstructedValue, and before this change it passed.

      An entry here is not decoration: TestPublishedDefaultAgreesWithTheConstructedValue
      checks each one's `default` against what its constructor produces, which is the .lfm
      streaming bug this file exists for. }

    { the text-entry family. All descend from TTyEdit (or from TTyNumericEdit, which does)
      and inherit its `default True` — listed individually because a DESCENDANT can re-set
      TabStop in its own constructor and the declared default lives on the ancestor, so the
      pair only stays consistent if each concrete class is checked. }
    TTyMaskEdit, TTyURLEdit, TTyComboEdit, TTyNumericEdit, TTyCurrencyEdit,
    TTyCalcEdit, TTyCalcCurrencyEdit, TTyTrackEdit, TTyFloatSpinEdit, TTySpinEdit,
    { the drop-down family: the FIELD takes the tab stop and owns the keyboard (typing,
      Alt+Down, arrows through the list). Their popup lists are separately forced to
      TabStop=False so a combo is one stop and not two — tyControls.ComboBox.pas:1174. }
    TTyComboBox, TTyAdvancedComboBox, TTyCheckComboBox, TTyColorBox, TTyColorComboBox,
    TTyComboBoxEx, TTyFilterComboBox, TTyFontComboBox, TTyFontSizeComboBox,
    TTyMRUComboBox, TTyOfficeComboBox, TTyShellComboBox,
    { the list family: arrow keys move the selection, so the list itself must hold focus }
    TTyAdvancedListBox, TTyCheckListBox, TTyColorListBox, TTyFontListBox, TTyOfficeListBox,
    TTyValueListEditor,
    { shell browsers — TTyListView / TTyTreeView with a directory behind them }
    TTyShellListView, TTyShellTreeView,
    { value pickers and data controls, each of which handles its own keys }
    TTyCalendar, TTyDateTimePicker, TTyMemo, TTyTrackBar, TTyDial, TTyGearDial,
    TTyRating, TTyPagination, TTyTreeSelect, TTyCascader, TTyRadioButton,

    { ----- entries that need their reason stated, because the name suggests otherwise ----

      TTyPageControl / TTyTabSet / TTyRibbon all descend from TTyCustomTabStrip, which is a
      keyboard control: Left/Right (or Up/Down) move between tabs, so the STRIP holds focus
      even though what it contains are pages full of other controls. That is the standard
      behaviour of every native tab control, and it is why these three sit here rather than
      with the containers — the container rule ("its interactive parts are its children")
      would be the wrong call for a widget whose own arrow keys do something. Note
      TTyRibbonGroup is on the OTHER table: a group is a plain box inside a ribbon page and
      has no keyboard of its own. }
    TTyPageControl, TTyTabSet, TTyRibbon,
    { TTyListGroupPanel is a LIST that happens to be named Panel — it groups list items, not
      child controls, and its arrow keys move the selected item. Constructor and declaration
      both say True. Named here explicitly so nobody "corrects" it onto the container table
      on the strength of the word Panel. }
    TTyListGroupPanel,
    { TTyRibbonGallery holds focus itself; its internal TTyGalleryGrid is forced to
      TabStop=False (tyControls.RibbonGallery.pas:224) for the same one-stop-per-widget
      reason the combos have. }
    TTyRibbonGallery,
    { TTyRibbonAppMenu is a TTyMenuButton — a button that opens the application menu, and a
      button is a tab stop. }
    TTyRibbonAppMenu);
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
    TTySteps,

    { ===== the extension: the 11 non-focusable families the tables used to miss =====
      See the header of the focusable table for what this extension is and why. }

    { containers — same rule as the ones above: the real controls are their children }
    TTyGridPanel, TTyScrollPanel, TTyCoolBar, TTyToolBarEx,
    { TTyGridCell is the designer cell INSIDE a TTyGridPanel (RegisterNoIcon, so it is
      streamed and selectable but never dragged from the palette). It is a drop target for
      other controls and has no keyboard of its own. }
    TTyGridCell,
    { TTyRibbonPage is the page a ribbon's tabs switch between — a box of TTyRibbonGroups.
      The keyboard belongs to the STRIP (TTyRibbon, on the other table), not to the page. }
    TTyRibbonPage,

    { ----- entries that need their reason stated ------------------------------------

      TTyToolButton and TTyToolSeparator are the one place a BUTTON legitimately stays out
      of the tab order, and they are the mirror of TTySpeedButton above: a tool-bar command
      acts on whatever the user was editing, so taking focus would move the caret out of it
      and the button would then act on nothing. tyControls.ToolBar.pas:319/875 declares AND
      constructs False, which is what makes it a legal disagreement with TTyButton's
      `default True` rather than a bug — TTyToolButton descends from TTyGlyphButtonBase,
      which redeclares `TabStop default False` (tyControls.GlyphButtons.pas:369) precisely so
      the override streams. The separator is painted furniture with no behaviour at all. }
    TTyToolButton, TTyToolSeparator,
    { TTyHtmlLabel renders markup; it is a LABEL, so it stays out of the focus order like
      every other label (TTyLinkLabel and friends are graphic controls and cannot be here at
      all — this table only holds windowed classes). Its constructor says so explicitly,
      tyControls.HtmlLabel.pas:366, because it descends from TTyCustomControl rather than
      from a label base and would otherwise just inherit LCL's False by accident. }
    TTyHtmlLabel,
    { TTyPreviewBox displays a rendering; there is nothing to type into it and nothing its
      arrow keys would move. }
    TTyPreviewBox,
    { TTyScrollBar is a pointer control: keyboard scrolling belongs to the control being
      scrolled (#56), so a bar is not a tab stop unless it is told to be. Its arrow / page /
      Home / End keys are still there for a bar that opts in with TabStop := True. }
    TTyScrollBar,
    { TTyTitleBar is the form's own chrome and a designer container (a menu bar, a quick
      access rail and a search box get dropped INTO it). Its buttons are TTyCaptionButtons
      with their own focus story; the bar itself is a drag handle, and a tab stop on it would
      mean Tab lands on the window's title.

      Worth its own note for a second reason: this class is the one the STATIC sweep that
      built this extension missed, because it is declared
      `TTyTitleBar = class(TTyCustomControl, ITyTitleBarTag)` and a hand-written parser that
      expects `class(TParent)` walks straight past an interface list. The completeness guard
      below found it on the first run. That is the argument for deriving the population at
      run time in one line rather than parsing sources cleverly. }
    TTyTitleBar);
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

{ THE REASON THE TABLES ABOVE CAN BE TRUSTED TOMORROW.

  The tables are a decision, so they have to be written by hand. What must NOT be written by
  hand is the POPULATION they are a decision about: the sweep that created this file listed
  the classes it had touched, 47 of them, and by the time anybody checked, 58 more windowed
  families had shipped with no declared-default guard at all. A hand-kept list of "all the
  controls" falls behind on the first new control and never says so.

  A static parse is not good enough either, and that is not a hypothesis: the sweep that
  produced the 58 was itself a script over `source/*.pas` matching `T... = class(TParent)`,
  and it silently missed TTyTitleBar, which is declared
  `class(TTyCustomControl, ITyTitleBarTag)`. This test found it on its first run.

  So the population is derived instead, the same way test.version.pas derives its own:
  test.designregistry PARSES designtime/tyControls.Design.pas at run time and returns every
  name in a RegisterComponents / RegisterNoIcon / RegisterDesignerBaseClass call. That file
  is the one place a control MUST be edited to reach the palette at all, so a new control
  appears here by construction, and this test fails until somebody decides which table it
  belongs on. Deciding is the point; being reminded to decide is what was missing.

  The filter is `InheritsFrom(TTyCustomControl)` — the windowed base, which is where TabStop
  is published and where MouseDown's click-to-focus lives. Graphic controls, non-visual
  components, forms and the two designer base classes drop out on their own; nothing is
  exempted by name, because a by-name exemption list is the same hand-kept list one level
  down. }
procedure TTyFocusTabStopTest.TestEveryRegisteredWindowedControlIsOnATable;
var
  names, listed, missing: TStringList;
  arr: TTyCtlClassArray;
  cls: TPersistentClass;
  i, windowed: Integer;
begin
  names := TStringList.Create;
  listed := TStringList.Create;
  missing := TStringList.Create;
  try
    arr := FocusableControls;
    for i := 0 to High(arr) do listed.Add(arr[i].ClassName);
    arr := ContainerAndChromeControls;
    for i := 0 to High(arr) do listed.Add(arr[i].ClassName);
    listed.Sorted := True;

    CollectRegisteredClassNames(names);
    { Sanity, so a parser that silently matched nothing cannot pass this test with an empty
      population — the exact failure mode that makes a derived list worth having. }
    AssertTrue('the design-registry parser found something at all', names.Count > 20);
    AssertTrue('...including the palette groups', names.IndexOf('TTyButton') >= 0);
    AssertTrue('...including the icon-less registrations', names.IndexOf('TTyGridCell') >= 0);

    windowed := 0;
    for i := 0 to names.Count - 1 do
    begin
      cls := GetClass(names[i]);
      { An unresolvable name is test.version's TestEveryRegisteredNameResolves to report;
        double-reporting it here would just make one omission look like two failures. }
      if cls = nil then Continue;
      if not cls.InheritsFrom(TTyCustomControl) then Continue;
      Inc(windowed);
      if listed.IndexOf(names[i]) < 0 then missing.Add(names[i]);
    end;

    { Second half of the same sanity check: the filter must not have rejected everything. }
    AssertTrue('the TTyCustomControl filter kept a realistic number of classes',
      windowed > 50);
    AssertEquals('registered windowed control(s) with no declared focus default. Every'
      + ' windowed TTy class a .lfm can name must appear in FocusableControls or in'
      + ' ContainerAndChromeControls, so that its TabStop default is a decision somebody'
      + ' wrote down (and so TestPublishedDefaultAgreesWithTheConstructedValue checks it).'
      + ' Add each of these to the right table, with a comment if the choice is not obvious'
      + ' from the class name:' + LineEnding + missing.Text, 0, missing.Count);
  finally
    missing.Free;
    listed.Free;
    names.Free;
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

{ The bars EMBEDDED in a scrolling control must not be tab stops: dragging one would move
  focus off the grid/tree/list it is scrolling, which would then drop its focus ring and its
  keyboard navigation mid-drag, and Tab would stop three times inside one widget. A
  standalone bar is not one by default either (#56); TabStop opts it in. }
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
  AssertFalse('a scroll bar dropped on a form is not a tab stop by default (#56)',
    standalone.TabStop);

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

{ #55/#56. TabStop used to keep a bar out of the Tab order and nothing more: LCL's arrow
  navigation (TApplication.DoArrowKey -> SelectNext with CheckTabStop = False) ignores it, and
  the bar's own click focused it whenever CanFocus said yes. The navigation list is built from
  CanFocus (TWinControl.GetTabOrderList), so CanFocus is where a bar that is not a tab stop has
  to say no. LCL's CanFocus only asks that every control up to the form is visible and
  enabled, so it answers here without the form ever being shown. }
procedure TTyFocusTabStopTest.TestAScrollBarTakesFocusOnlyWhenTabStopAsks;
var
  bar: TTyScrollBar;
  grid: TTyStringGrid;
begin
  bar := TTyScrollBar.Create(FForm);
  bar.Parent := FForm;
  AssertFalse('a standalone bar cannot take focus by default', bar.CanFocus);
  bar.TabStop := True;
  AssertTrue('TabStop opts it back in', bar.CanFocus);
  bar.TabStop := False;
  AssertFalse('and back out', bar.CanFocus);

  grid := TTyStringGrid.Create(FForm);
  grid.Parent := FForm;
  AssertTrue('setup: the grid itself can take focus', grid.CanFocus);
  TGridAccess(grid).VScrollBar.Visible := True;
  AssertFalse('the grid''s own bar cannot', TGridAccess(grid).VScrollBar.CanFocus);
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

{ Record, do not re-raise: the exception arrived inside a WindowProc and there is no frame
  of this test's to unwind to. Recording it lets the probe finish and the assertion below
  turn it into an ordinary red test. }
procedure TTyClickFocusTest.TrapException(Sender: TObject; E: Exception);
begin
  if FTrapped = '' then
    FTrapped := E.ClassName + ': ' + E.Message;
end;

procedure TTyClickFocusTest.CommitTextOnExit(Sender: TObject);
begin
  { Must differ from what is already there: SetTextInternal short-circuits on an unchanged
    string, and a no-op write never reaches the machinery this guard is about. }
  TTyEdit(Sender).Text := 'committed on exit';
end;

procedure TTyClickFocusTest.AssertNothingRaised(const AWhere: string);
var
  s: string;
begin
  if FTrapped = '' then Exit;
  s := FTrapped;
  FTrapped := '';   // one report per probe, so a later probe is not blamed for this one
  Fail(AWhere + ' raised an unhandled exception on the real message path: ' + s
    + '. Nothing here propagates back to the caller -- untrapped, LCL would show a modal '
    + 'error box and the console runner would block on it forever.');
end;

procedure TTyClickFocusTest.SetUp;
begin
  NeedWidgetSetForClicks;
  FTrapped := '';
  FPrevOnException := Forms.Application.OnException;
  Forms.Application.OnException := @TrapException;
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
  Forms.Application.OnException := FPrevOnException;
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

{ THE CLICK PROBE HAS ITS OWN ROSTER, AND IT IS DELIBERATELY NARROWER THAN THE TABLE ABOVE.

  This is the one place where "just iterate FocusableControls" is wrong, so it is written
  out rather than derived. The tables above are cheap: construct, read a flag, read RTTI.
  This suite is not -- every entry builds a real windowed control on a real visible form,
  allocates a handle, pumps the message queue and delivers a synthetic LM_LBUTTONDOWN. It
  was designed, and validated, against the 25 classes the click-focus sweep had touched.

  Pointing it at the extended table was tried and REVERTED, on evidence:

    * TTyCurrencyEdit DEADLOCKED the console runner. FIXED, and back on the roster below.
      The diagnosis in the first version of this note was wrong in one detail worth keeping,
      because it is what a coarse probe does to you: the press was innocent. Instrumentation
      stopped at `:parked`, so the block LOOKED like `Perform(LM_LBUTTONDOWN, ...)`; logging
      one statement further showed the click completing, focus landing correctly, and the
      probe blocking in `c.Free`. Freeing a FOCUSED edit runs TWinControl.Destroy ->
      RemoveFocus -> WM_KILLFOCUS -> DoExit, TTyNumericEdit.DoExit reformats the field, and
      the write reached an undo stack tyControls.Edit.pas's destructor had already freed --
      EAccessViolation inside a WindowProc, so LCL showed a modal error box and the runner
      waited on it forever with the CPU flat. It was never currency-specific: a bare TTyEdit
      whose OnExit writes Text did the same, and so did any numeric edit holding a grouped
      value. TTyCurrencyEdit was simply the only one whose DEFAULT value (the '$' makes the
      display differ from the raw form at 0) reached it, where plain TTyNumericEdit's
      `FText = AValue` short-circuit stepped over it. Root fix: tyControls.Edit.pas frees
      the text engine AFTER `inherited Destroy`.
    * Beyond that, the roster would pull in the shell browsers (TTyShellTreeView,
      TTyShellListView, TTyShellComboBox, TTyFilterComboBox), which enumerate the real
      filesystem on handle creation. That is a machine-dependent cost and a machine-
      dependent hang risk inside what is otherwise a pure unit suite.

  So: the declared-default guard covers all 105 windowed classes, because reading a flag is
  free. The click CHAIN is probed on this list. Adding to it is fine and welcome -- one
  class at a time, each one actually run -- but do not wire it to FocusableControls, or the
  next control with a blocking press takes the whole suite down with it. }
function ClickProbeControls: TTyCtlClassArray;
begin
  Result := TTyCtlClassArray.Create(
    TTyButton, TTyColorButton, TTyDropDownButton, TTyMenuButton,
    TTyGlyphButton, TTyGlyphContainerButton,
    TTyButtonGroup, TTyColorGrid, TTyDrawGrid, TTyStringGrid, TTyHeaderControl,
    TTyHSColorPicker, TTyLColorPicker, TTyImageView,
    TTyEdit, TTyListBox, TTyCheckBox, TTySegmented, TTyTreeView, TTyListView,
    TTyCalculator, TTyToggleSwitch, TTyMenuBar, TTyRibbonBackstage,
    { The numeric edit family, added with the teardown fix above. All five were run one at
      a time before being listed. TTyCurrencyEdit and TTyCalcCurrencyEdit are the two that
      actually exercise the fix at their default value -- the other three hold "0.00"/"0",
      whose blur reformat is a no-op write -- but the family is listed whole so a future
      change to any one of their Formatted overrides is clicked too. }
    TTyNumericEdit, TTyCurrencyEdit, TTyCalcEdit, TTyCalcCurrencyEdit, TTyTrackEdit);
end;

procedure TTyClickFocusTest.TestAClickActuallyLandsFocusOnEveryFocusableControl;
var
  list: TTyCtlClassArray;
  i: Integer;
  moved: Boolean;
  landed: string;
begin
  list := ClickProbeControls;
  AssertTrue('the roster must not be empty (a vacuous loop proves nothing)',
    Length(list) > 0);
  { Every class on the click roster must also be on the DECLARED table, or the two would
    drift apart silently and this suite could end up probing a control the tables no longer
    consider focusable. The reverse does not hold, and must not -- see the note above. }
  for i := 0 to High(list) do
    AssertTrue(list[i].ClassName + ' is on the click roster but not in FocusableControls',
      InFocusableTable(list[i]));
  for i := 0 to High(list) do
  begin
    landed := ClickAndReportFocus(list[i], moved);
    { Before the focus assertion: a control that RAISED has not been measured at all, and
      naming it here is the difference between a diagnosis and a wedged runner. }
    AssertNothingRaised(list[i].ClassName);
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
  AssertNothingRaised('TTyPanel');
  AssertFalse('a click on a TTyPanel must NOT move focus -- it is not a tab stop. '
    + 'If this passes, ClickAndReportFocus is not measuring the click at all.', moved);
end;

{ THE ROOT GUARD for the defect that used to hang this file, aimed at the ROOT and not at
  the control that reported it.

  TTyCurrencyEdit was only the messenger. What actually broke was tyControls.Edit.pas's
  destructor: it freed the undo stack and the measuring bitmap BEFORE `inherited Destroy`,
  and `inherited Destroy` is precisely what calls RemoveFocus -- so WM_KILLFOCUS came back
  synchronously, ran CM_EXIT -> DoExit -> OnExit, and any handler that wrote Text landed in
  SetTextInternal -> BeginUndoStep -> FUndoStack.Push on freed memory.

  So this probes a BARE TTyEdit with the most ordinary handler anyone would write -- commit
  the field on the way out -- rather than a currency edit. TTyCurrencyEdit reached the same
  freed pointer only because its symbol makes the blur reformat CHANGE the string, where a
  plain numeric edit at its default value short-circuits on `FText = AValue` and never gets
  there; pinning the symptom would leave every OnExit handler in every application still
  broken. TTyCurrencyEdit is on the click roster above, which covers the reported gesture. }
procedure TTyClickFocusTest.TestFreeingAFocusedEditWhoseExitWritesTextDoesNotRaise;
var
  e: TTyEdit;
begin
  e := TTyEdit.Create(FForm);
  e.Parent := FForm;
  e.SetBounds(220, 60, 260, 26);
  e.OnExit := @CommitTextOnExit;
  e.Visible := True;
  e.HandleNeeded;
  Forms.Application.ProcessMessages;

  { The edit must really HOLD focus, or RemoveFocus does nothing on Free and this passes
    vacuously -- the whole failure lives in the focus handover. }
  AssertTrue('the probe edit must be focusable, or this guard proves nothing', e.CanFocus);
  e.SetFocus;
  Forms.Application.ProcessMessages;
  AssertSame('the probe edit must hold focus before it is freed',
    TWinControl(e), TWinControl(FForm.ActiveControl));

  e.Free;
  Forms.Application.ProcessMessages;
  AssertNothingRaised('freeing a focused TTyEdit whose OnExit writes Text');
end;

{ The forum report behind this suite (#8): the rail took no focus, so its arrow keys -- the
  half of Clickable that is not the mouse -- were dead code. Both halves, end to end, on a
  real handle: nothing else in the suite joins them up. test.steps drives the protected
  PressAt/SendKey seams directly, which cannot see a focus failure at all. }
function NewScrollingGrid(AForm: TForm): TTyStringGrid;
var
  c: TTyColumn;
begin
  Result := TTyStringGrid.Create(AForm);
  Result.Parent := AForm;
  Result.SetBounds(220, 60, 260, 150);
  c := Result.Header.Columns.Add as TTyColumn;
  c.Width := 120;
  c.Text := 'C0';
  Result.RowCount := 100;          // more rows than fit: the vertical bar shows
  Result.HandleNeeded;
  Forms.Application.ProcessMessages;
end;

{ #55: the path #52 took. Arrow navigation asks the parent for the next control with TabStop
  not checked; inside a grid with its bar showing, nothing it can answer may be the bar.
  FindNextControl skips what is not IsVisible, and that asks the form too -- which is why this
  lives in the suite whose form is really shown: unshown, the bar is skipped for the wrong
  reason and the test proves nothing. }
procedure TTyClickFocusTest.TestArrowNavigationNeverLandsOnAControlsOwnBar;
var
  grid: TTyStringGrid;
  next: TWinControl;
begin
  grid := NewScrollingGrid(FForm);
  try
    AssertTrue('setup: the vertical bar is showing', TGridAccess(grid).VScrollBar.IsVisible);
    next := TWinAccess(grid).FindNextControl(nil, True, False, False);
    AssertFalse('forward: not a scroll bar', next is TTyScrollBar);
    next := TWinAccess(grid).FindNextControl(nil, False, False, False);
    AssertFalse('backward: not a scroll bar', next is TTyScrollBar);
  finally
    grid.Free;
  end;
end;

{ #55: a click on a control's own bar used to focus the BAR -- the grid lost its focus ring and
  its keys, and a cell being edited was committed and closed. The control gets the focus
  instead, so the keyboard goes on scrolling what the click scrolled; and when the focus is
  already inside the control (the editor of a cell) it stays where it is. A track click, not
  the thumb, so no drag capture is left behind. }
procedure TTyClickFocusTest.TestClickingAControlsOwnBarLeavesTheFocusWithTheControl;
var
  grid: TTyStringGrid;
  bar: TTyScrollBar;
  ed: TWinControl;

  procedure ClickTheTrack;
  var
    y: Integer;
  begin
    y := bar.Height - bar.Width - 4;   // above the bottom arrow, below the thumb at the top
    bar.Perform(LM_LBUTTONDOWN, MK_LBUTTON, MousePos(bar.Width div 2, y));
    bar.Perform(LM_LBUTTONUP, 0, MousePos(bar.Width div 2, y));
    Forms.Application.ProcessMessages;
  end;

begin
  grid := NewScrollingGrid(FForm);
  try
    bar := TGridAccess(grid).VScrollBar;
    AssertTrue('setup: the vertical bar is showing', bar.IsVisible);
    if FPark.CanFocus then FPark.SetFocus;
    Forms.Application.ProcessMessages;
    AssertSame('setup: the focus is parked elsewhere', TWinControl(FPark),
      TWinControl(FForm.ActiveControl));

    ClickTheTrack;
    AssertNothingRaised('a click on the grid''s bar');
    AssertSame('the grid has the focus, not its bar', TWinControl(grid),
      TWinControl(FForm.ActiveControl));

    AssertTrue('setup: editing', grid.BeginEdit(0, 1));
    Forms.Application.ProcessMessages;
    ed := grid.EditorControl as TWinControl;
    AssertSame('setup: the editor has the focus', ed, TWinControl(FForm.ActiveControl));
    ClickTheTrack;
    AssertTrue('a click on the bar does not end the edit', grid.Editing);
    AssertSame('and the editor keeps the focus', ed, TWinControl(FForm.ActiveControl));
  finally
    grid.Free;
  end;
end;

{ #59. A pick list in a cell commits the moment its item changes, and that closed the editor
  while it held the focus: the focus went to whatever the system picked next -- another
  control on the form -- and the keys that followed went there. Down was the usual way in: a
  closed pick list turned it into "the next item", so the cell's value changed as well, under
  a key the user had pressed to move.

  Real keys and clicks through the widgetset, on the shown form: only a shown form has a focus
  to lose. }
function TTyClickFocusTest.NewPickListGrid: TTyStringGrid;
var
  col: TTyGridColumn;
begin
  Result := NewScrollingGrid(FForm);
  col := Result.Header.Columns[0] as TTyGridColumn;
  col.EditorKind := gekPickList;
  col.PickList.CommaText := 'apple,banana,cherry';
  Result.Cells[0, 1] := 'apple';
  Result.Cells[0, 2] := 'banana';
end;

function TTyClickFocusTest.StartPickEdit(AGrid: TTyStringGrid; ARow: Integer): TTyComboBox;
begin
  AssertTrue('setup: editing row ' + IntToStr(ARow), AGrid.BeginEdit(0, ARow));
  Forms.Application.ProcessMessages;
  AssertTrue('setup: the cell edits in a pick list', AGrid.EditorControl is TTyComboBox);
  Result := TTyComboBox(AGrid.EditorControl);
  AssertSame('setup: the pick list is the active control', TWinControl(Result),
    TWinControl(FForm.ActiveControl));
  AssertTrue('setup: and holds the system focus', GetFocus = Result.Handle);
end;

procedure TTyClickFocusTest.AssertTheGridHasTheFocus(AGrid: TTyStringGrid;
  const AAfter: string);
begin
  AssertFalse(AAfter + ': the edit is over', AGrid.Editing);
  AssertSame(AAfter + ': the grid is the active control', TWinControl(AGrid),
    TWinControl(FForm.ActiveControl));
  AssertTrue(AAfter + ': and holds the system focus', GetFocus = AGrid.Handle);
end;

procedure TTyClickFocusTest.PressKey(AKey: Word; AChar: Char);
var
  h: HWND;
begin
  h := GetFocus;
  SendMessage(h, LM_KEYDOWN, AKey, 0);
  if AChar <> #0 then SendMessage(h, LM_CHAR, Ord(AChar), 0);
  SendMessage(h, LM_KEYUP, AKey, 0);
  Forms.Application.ProcessMessages;
end;

{ A closed pick list leaves Up/Down to the grid, as LCL's TPickListCellEditor does and as the
  text editor has since #52: commit, move a row, the focus back on the grid -- and the value
  left as it was. (Open, the list has the arrows; Alt+Down opens it.) }
procedure TTyClickFocusTest.TestUpDownInAPickListCellMoveTheCursor;
var
  grid: TTyStringGrid;
  pick: TTyComboBox;
begin
  grid := NewPickListGrid;
  try
    StartPickEdit(grid, 1);
    PressKey(VK_DOWN);
    AssertEquals('Down did not step the value', 'apple', grid.Cells[0, 1]);
    AssertEquals('Down moved the cursor a row', 2, grid.Row);
    AssertTheGridHasTheFocus(grid, 'after Down');

    StartPickEdit(grid, 2);
    PressKey(VK_UP);
    AssertEquals('Up did not step the value', 'banana', grid.Cells[0, 2]);
    AssertEquals('Up moved the cursor back a row', 1, grid.Row);
    AssertTheGridHasTheFocus(grid, 'after Up');

    { With a modifier the arrow is not navigation: Alt+Down still opens the list. lParam bit
      29 is the system's "Alt is down", which is where LCL reads it from. }
    StartPickEdit(grid, 1);
    SendMessage(GetFocus, LM_SYSKEYDOWN, VK_DOWN, $20000000);
    SendMessage(GetFocus, LM_SYSKEYUP, VK_DOWN, $20000000);
    Forms.Application.ProcessMessages;
    AssertTrue('Alt+Down opened the list', TTyComboBox(grid.EditorControl).DroppedDown);
    AssertTrue('and the cell is still being edited', grid.Editing);
    AssertEquals('on the same row', 1, grid.Row);
    TTyComboBox(grid.EditorControl).CloseUp;
    Forms.Application.ProcessMessages;

    { An open list has the arrows. The default list takes the keyboard into its own window;
      a key that reaches the field while it is open -- a list that does not take the
      activation does that -- steps the item, as the list would, and the cursor stays. }
    pick := StartPickEdit(grid, 1);
    pick.DropDown;
    Forms.Application.ProcessMessages;
    AssertTrue('setup: the list is open', pick.DroppedDown);
    SendMessage(pick.Handle, LM_KEYDOWN, VK_DOWN, 0);
    SendMessage(pick.Handle, LM_KEYUP, VK_DOWN, 0);
    Forms.Application.ProcessMessages;
    AssertEquals('the open list stepped the item', 'banana', grid.Cells[0, 1]);
    AssertEquals('and the cursor stayed on its row', 1, grid.Row);
    pick.CloseUp;
    Forms.Application.ProcessMessages;
    AssertNothingRaised('Up/Down in a pick list');
  finally
    grid.Free;
  end;
end;

{ A pick still commits at once -- and hands the focus back to the grid. From the keyboard (the
  first letter of an item) at once; from the open list, a click on a row, once the list has
  closed: the click is handled in the list's own window, and pulling the activation away under
  it is what TTyComboBox.PopupListChange defers its close-up to avoid. }
procedure TTyClickFocusTest.TestAPickInACellHandsTheFocusBackToTheGrid;
var
  grid: TTyStringGrid;
  pick: TTyComboBox;
  list: TTyListBox;
  r: TRect;
begin
  grid := NewPickListGrid;
  try
    StartPickEdit(grid, 2);
    PressKey(Ord('C'), 'c');
    AssertEquals('the first letter picked cherry, and that committed', 'cherry',
      grid.Cells[0, 2]);
    AssertTheGridHasTheFocus(grid, 'after a pick by its first letter');

    pick := StartPickEdit(grid, 1);
    pick.DropDown;
    Forms.Application.ProcessMessages;
    AssertTrue('setup: the list is open', pick.DroppedDown);
    list := pick.PopupList;
    r := list.ItemRect(2);
    AssertTrue('setup: cherry''s row is on the list', r.Bottom > r.Top);
    { Through the widgetset, as a real click comes: the list's own window proc. }
    SendMessage(list.Handle, LM_LBUTTONDOWN, MK_LBUTTON, MousePos((r.Left + r.Right) div 2,
      (r.Top + r.Bottom) div 2));
    SendMessage(list.Handle, LM_LBUTTONUP, 0, MousePos((r.Left + r.Right) div 2,
      (r.Top + r.Bottom) div 2));
    AssertTrue('setup: the list is still open while its click is handled', pick.DroppedDown);
    AssertFalse('the grid does not take the focus under the list''s click',
      FForm.ActiveControl = grid);
    Forms.Application.ProcessMessages;   // the deferred close-up
    Forms.Application.ProcessMessages;
    AssertFalse('the list closed', pick.DroppedDown);
    AssertEquals('the clicked row was picked, and that committed', 'cherry', grid.Cells[0, 1]);
    AssertTheGridHasTheFocus(grid, 'after a pick from the list');

    { Only a pick hands the focus to the grid. Opened, then left for another control: the
      focus goes where the user sent it, and the grid does not pull it back when the list
      closes. }
    grid.Cells[0, 2] := 'banana';
    pick := StartPickEdit(grid, 2);
    pick.DropDown;
    Forms.Application.ProcessMessages;
    AssertTrue('setup: the list is open again', pick.DroppedDown);
    FPark.SetFocus;
    Forms.Application.ProcessMessages;
    Forms.Application.ProcessMessages;
    AssertFalse('leaving the cell closed the list', pick.DroppedDown);
    AssertFalse('and ended the edit', grid.Editing);
    { The form's own record only: with the list's window active, a test process in the
      background cannot move the system's activation back to this form. }
    AssertSame('the focus is where it was sent', TWinControl(FPark),
      TWinControl(FForm.ActiveControl));
    AssertNothingRaised('picks in a pick list');
  finally
    grid.Free;
  end;
end;

function TTyClickFocusTest.NewEditorGrid(AKind: TTyGridEditorKind;
  const AValue: string): TTyStringGrid;
begin
  Result := NewScrollingGrid(FForm);
  (Result.Header.Columns[0] as TTyGridColumn).EditorKind := AKind;
  Result.Cells[0, 1] := AValue;
  Result.Col := 0;
  Result.Row := 1;
  Result.SetFocus;
  Forms.Application.ProcessMessages;
  AssertTrue('setup: the grid holds the focus', GetFocus = Result.Handle);
  AssertFalse('setup: and is not editing', Result.Editing);
end;

procedure TTyClickFocusTest.TypeKey(AChar: Char);
begin
  PressKey(Ord(UpCase(AChar)), AChar);
end;

{ #66. A number typed into a spin cell lived in the spin edit's text until the spin edit
  committed it -- on Enter, or in its DoExit, which runs only after OnExit. The grid ends the
  edit in OnExit, and read the spin edit's value there: the number from before the typing. So
  typing a number into the cell and moving on left the old one. Real keys, a real change of
  focus. }
procedure TTyClickFocusTest.TestASpinCellKeepsTheNumberTypedIntoIt;
var
  grid: TTyStringGrid;
  spin: TTySpinEdit;
begin
  grid := NewEditorGrid(gekSpin, '42');
  try
    AssertTrue('setup: editing the cell', grid.BeginEdit(0, 1));
    Forms.Application.ProcessMessages;
    AssertTrue('setup: the cell edits in a spin edit', grid.EditorControl is TTySpinEdit);
    spin := TTySpinEdit(grid.EditorControl);
    AssertTrue('setup: which holds the focus', GetFocus = spin.Handle);
    PressKey(VK_BACK);
    PressKey(VK_BACK);
    TypeKey('7');
    TypeKey('5');
    AssertEquals('setup: the number typed', '75', spin.Text);
    FPark.SetFocus;
    Forms.Application.ProcessMessages;
    AssertFalse('leaving the cell ended the edit', grid.Editing);
    AssertEquals('and the cell holds the number typed', '75', grid.Cells[0, 1]);

    { Ended from code, the same -- and clamped to the column's range, as the spin edit's own
      commit clamps it. }
    AssertTrue('setup: editing the cell again', grid.BeginEdit(0, 1));
    Forms.Application.ProcessMessages;
    spin := TTySpinEdit(grid.EditorControl);
    PressKey(VK_BACK);
    PressKey(VK_BACK);
    TypeKey('3');
    TypeKey('0');
    TypeKey('0');
    AssertEquals('setup: the number typed', '300', spin.Text);
    grid.EndEdit(True);
    AssertEquals('the cell holds it, clamped to the column''s maximum', '100',
      grid.Cells[0, 1]);
    AssertNothingRaised('typing into a spin cell');
  finally
    grid.Free;
  end;
end;

{ #67. A mask editor checks itself when the focus leaves it, and raises when a required slot
  is empty (maskedit.md 5.2) -- that is its job, and LCL's TMaskEdit does the same. The grid
  ended an edit by hiding the editor while it held the focus, so that check ran on every edit
  that ended: Escape on a cell with a slot emptied raised the error, for a value being thrown
  away; and a commit raised it and then wrote the unfilled value into the cell anyway. }
function TTyClickFocusTest.StartMaskEdit(const AValue: string;
  out AGrid: TTyStringGrid): TTyMaskEdit;
begin
  AGrid := NewEditorGrid(gekMask, AValue);
  (AGrid.Header.Columns[0] as TTyGridColumn).EditMask := '000-0000';
  AssertTrue('setup: editing the cell', AGrid.BeginEdit(0, 1));
  Forms.Application.ProcessMessages;
  AssertTrue('setup: the cell edits in a mask editor', AGrid.EditorControl is TTyMaskEdit);
  Result := TTyMaskEdit(AGrid.EditorControl);
  AssertTrue('setup: which holds the focus', GetFocus = Result.Handle);
end;

procedure TTyClickFocusTest.AssertTheMaskWasReported(const AAfter: string);
begin
  AssertTrue(AAfter + ': the mask''s own error was reported, got "' + FTrapped + '"',
    Pos('ETyMaskError', FTrapped) = 1);
  FTrapped := '';
end;

procedure TTyClickFocusTest.TestEscapeOnAnEditedMaskCellRaisesNothing;
var
  grid: TTyStringGrid;
  mask: TTyMaskEdit;
begin
  mask := StartMaskEdit('021-1234', grid);
  try
    PressKey(VK_END);
    PressKey(VK_BACK);
    AssertEquals('setup: a slot emptied', '021-123_', mask.Text);
    PressKey(VK_ESCAPE);
    AssertNothingRaised('Escape on a mask cell with a slot emptied');
    AssertFalse('Escape ended the edit', grid.Editing);
    AssertEquals('and left the cell as it was', '021-1234', grid.Cells[0, 1]);
    AssertTheGridHasTheFocus(grid, 'after Escape');

    { The mask editor, hidden, still holds the unfilled text it was left with. That is no
      business of the next edit, in a cell that is not a mask cell. }
    (grid.Header.Columns[0] as TTyGridColumn).EditorKind := gekText;
    grid.Row := 2;
    TypeKey('x');
    AssertTrue('setup: the text cell is being edited', grid.Editing);
    PressKey(VK_RETURN);
    AssertFalse('Enter ended the text edit', grid.Editing);
    AssertEquals('and wrote it', 'x', grid.Cells[0, 2]);
    AssertNothingRaised('a text edit after an abandoned mask edit');
  finally
    grid.Free;
  end;
end;

{ A required slot left empty is refused the way OnValidateCell refuses a value: the editor
  stays, nothing is written, the cursor does not move -- and the mask's own error is
  reported, as it is when the focus leaves a mask editor anywhere else. }
procedure TTyClickFocusTest.TestAnUnfilledMaskCellIsRefusedAndReported;
var
  grid: TTyStringGrid;
  mask: TTyMaskEdit;
  r: TRect;
begin
  mask := StartMaskEdit('021-1234', grid);
  try
    PressKey(VK_END);
    PressKey(VK_BACK);
    AssertEquals('setup: a slot emptied', '021-123_', mask.Text);

    PressKey(VK_RETURN);
    AssertTheMaskWasReported('Enter');
    AssertTrue('Enter left the edit open', grid.Editing);
    AssertEquals('wrote nothing', '021-1234', grid.Cells[0, 1]);
    AssertTrue('and the editor kept the focus', GetFocus = mask.Handle);

    PressKey(VK_DOWN);
    AssertTheMaskWasReported('Down');
    AssertTrue('Down left the edit open', grid.Editing);
    AssertEquals('and the cursor where it was', 1, grid.Row);

    r := grid.CellRect(0, 2);
    SendMessage(grid.Handle, LM_LBUTTONDOWN, MK_LBUTTON,
      MousePos((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2));
    SendMessage(grid.Handle, LM_LBUTTONUP, 0,
      MousePos((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2));
    Forms.Application.ProcessMessages;
    AssertTheMaskWasReported('a click on another cell');
    AssertTrue('the click left the edit open', grid.Editing);
    AssertEquals('and the cursor where it was', 1, grid.Row);
    AssertEquals('nothing written', '021-1234', grid.Cells[0, 1]);
    AssertTrue('the editor has the focus again', GetFocus = mask.Handle);

    { Filled, it commits. }
    TypeKey('9');
    AssertEquals('setup: the slot filled', '021-1239', mask.Text);
    PressKey(VK_RETURN);
    AssertNothingRaised('Enter on a filled mask');
    AssertFalse('Enter ended the edit', grid.Editing);
    AssertEquals('and wrote the value', '021-1239', grid.Cells[0, 1]);
    AssertTheGridHasTheFocus(grid, 'after Enter');

    { Leaving the grid altogether with a slot empty drops the edit: leaving is the same
      answer as Escape for a refused edit (TTyStringGrid.DoExit). Nothing is raised on the
      way -- raised in the middle of LCL's focus change, the error stopped the grid ever
      hearing that the focus had gone, and the editor stayed open on it. }
    AssertTrue('setup: editing the cell again', grid.BeginEdit(0, 1));
    Forms.Application.ProcessMessages;
    mask := TTyMaskEdit(grid.EditorControl);
    PressKey(VK_END);
    PressKey(VK_BACK);
    AssertEquals('setup: a slot emptied', '021-123_', mask.Text);
    { A click, through the widgetset, so a raise on the way is caught and reported as LCL
      reports one rather than thrown into this test. }
    SendMessage(FPark.Handle, LM_LBUTTONDOWN, MK_LBUTTON, MousePos(4, 4));
    SendMessage(FPark.Handle, LM_LBUTTONUP, 0, MousePos(4, 4));
    Forms.Application.ProcessMessages;
    AssertNothingRaised('leaving the grid with a slot empty');
    AssertFalse('leaving ended the edit', grid.Editing);
    AssertEquals('without writing', '021-1239', grid.Cells[0, 1]);
    AssertSame('the focus is where it was sent', TWinControl(FPark),
      TWinControl(FForm.ActiveControl));

    { Ended from code, an unfilled mask is not written either -- and nothing is raised into
      the caller. }
    grid.SetFocus;
    Forms.Application.ProcessMessages;
    AssertTrue('setup: editing the cell once more', grid.BeginEdit(0, 1));
    Forms.Application.ProcessMessages;
    mask := TTyMaskEdit(grid.EditorControl);
    PressKey(VK_END);
    PressKey(VK_BACK);
    AssertEquals('setup: a slot emptied', '021-123_', mask.Text);
    grid.EndEdit(True);
    Forms.Application.ProcessMessages;
    AssertNothingRaised('EndEdit(True) on an unfilled mask');
    AssertFalse('EndEdit ended the edit', grid.Editing);
    AssertEquals('without writing', '021-1239', grid.Cells[0, 1]);
  finally
    grid.Free;
  end;
end;

{ Only an edit is checked. A cell whose stored value does not fill the mask -- it came in
  from a file -- opens and closes again without a word, as an untouched mask editor leaves
  without one (maskedit.md 5.2: the exit check compares against the text on entry). }
procedure TTyClickFocusTest.TestAnUntouchedMaskCellCanAlwaysBeLeft;
var
  grid: TTyStringGrid;
begin
  StartMaskEdit('12', grid);
  try
    PressKey(VK_RETURN);
    AssertNothingRaised('Enter on an untouched mask cell');
    AssertFalse('Enter ended the edit', grid.Editing);
    AssertTheGridHasTheFocus(grid, 'after Enter');
  finally
    grid.Free;
  end;
end;

{ A mask column with no EditMask is a plain text cell, and nothing it holds is "unfilled". }
procedure TTyClickFocusTest.TestAMaskCellWithNoMaskTakesAnyText;
var
  grid: TTyStringGrid;
  mask: TTyMaskEdit;
begin
  grid := NewEditorGrid(gekMask, 'abc');
  try
    AssertTrue('setup: editing the cell', grid.BeginEdit(0, 1));
    Forms.Application.ProcessMessages;
    AssertTrue('setup: the cell edits in a mask editor', grid.EditorControl is TTyMaskEdit);
    mask := TTyMaskEdit(grid.EditorControl);
    PressKey(VK_END);
    TypeKey('d');
    AssertEquals('setup: the text typed', 'abcd', mask.Text);
    PressKey(VK_RETURN);
    AssertNothingRaised('Enter on a mask cell with no mask');
    AssertFalse('Enter ended the edit', grid.Editing);
    AssertEquals('and wrote the text', 'abcd', grid.Cells[0, 1]);
  finally
    grid.Free;
  end;
end;

{ #64. A key typed on a cell that is not being edited opens its editor, and the key is the
  first character of what the cell will hold -- grid.md promises it, and the text editor has
  always done it. Every other editor opened and the key was gone: the grid marked it handled
  but gave it only to the text editor.

  Real keys on the shown form: the editor takes the focus as it opens, and its own rules --
  digits only, the mask's slots, the date's fields, the pick list's letters -- sit behind the
  door a real key comes in by. }
procedure TTyClickFocusTest.TestTypingOnASpinCellStartsTheNumberWithThatKey;
var
  grid: TTyStringGrid;
  spin: TTySpinEdit;
begin
  grid := NewEditorGrid(gekSpin, '42');
  try
    TypeKey('7');
    AssertTrue('the key opened the spin editor', grid.EditorControl is TTySpinEdit);
    spin := TTySpinEdit(grid.EditorControl);
    AssertTrue('which holds the focus', GetFocus = spin.Handle);
    AssertEquals('the key is the first digit of the new number', '7', spin.Text);
    TypeKey('5');
    AssertEquals('the next key follows it', '75', spin.Text);
    grid.EndEdit(True);
    AssertEquals('and that is what the cell holds', '75', grid.Cells[0, 1]);

    { A key a number cannot take still opens the editor -- the grid does not know which keys
      a spin edit takes -- and must not leave the number emptied under it. }
    grid.SetFocus;
    Forms.Application.ProcessMessages;
    TypeKey('x');
    AssertTrue('the key opened the spin editor', grid.EditorControl is TTySpinEdit);
    AssertEquals('the number is still there', '75', TTySpinEdit(grid.EditorControl).Text);
    grid.EndEdit(True);
    AssertEquals('and the cell kept it', '75', grid.Cells[0, 1]);
    AssertNothingRaised('typing on a spin cell');
  finally
    grid.Free;
  end;
end;

procedure TTyClickFocusTest.TestTypingOnAMemoCellStartsTheTextWithThatKey;
var
  grid: TTyStringGrid;
  memo: TTyMemo;
begin
  grid := NewEditorGrid(gekMemo, 'old text');
  try
    TypeKey('n');
    AssertTrue('the key opened the memo editor', grid.EditorControl is TTyMemo);
    memo := TTyMemo(grid.EditorControl);
    AssertTrue('which holds the focus', GetFocus = memo.Handle);
    AssertEquals('the key is the first character of the new text', 'n', memo.Text);
    TypeKey('e');
    AssertEquals('the next key follows it', 'ne', memo.Text);
    grid.EndEdit(True);
    AssertEquals('and that is what the cell holds', 'ne', grid.Cells[0, 1]);
    AssertNothingRaised('typing on a memo cell');
  finally
    grid.Free;
  end;
end;

procedure TTyClickFocusTest.TestTypingOnACalculatorCellStartsTheNumberWithThatKey;
var
  grid: TTyStringGrid;
  calc: TTyCalcEdit;
  opened: string;
begin
  grid := NewEditorGrid(gekCalculator, '12');
  try
    TypeKey('3');
    AssertTrue('the key opened the calculator editor', grid.EditorControl is TTyCalcEdit);
    calc := TTyCalcEdit(grid.EditorControl);
    AssertTrue('which holds the focus', GetFocus = calc.Handle);
    AssertEquals('the key is the first digit of the new number', '3', calc.Text);
    TypeKey('4');
    AssertEquals('the next key follows it', '34', calc.Text);
    grid.EndEdit(True);
    AssertEquals('and that is what the cell holds', '34', grid.Cells[0, 1]);

    { A key a number cannot take leaves the number as the editor opened with it (formatted
      its own way: the calculator shows 34 as 34.00). }
    grid.SetFocus;
    Forms.Application.ProcessMessages;
    AssertTrue('setup: editing the cell', grid.BeginEdit(0, 1));
    Forms.Application.ProcessMessages;
    opened := TTyCalcEdit(grid.EditorControl).Text;
    grid.EndEdit(False);
    grid.SetFocus;
    Forms.Application.ProcessMessages;
    TypeKey('x');
    AssertTrue('the key opened the calculator editor', grid.EditorControl is TTyCalcEdit);
    AssertEquals('a key a number cannot take leaves it as it was', opened,
      TTyCalcEdit(grid.EditorControl).Text);
    grid.EndEdit(False);
    AssertNothingRaised('typing on a calculator cell');
  finally
    grid.Free;
  end;
end;

procedure TTyClickFocusTest.TestTypingOnAMaskCellFillsTheFirstSlotWithThatKey;
var
  grid: TTyStringGrid;
  mask: TTyMaskEdit;
begin
  grid := NewEditorGrid(gekMask, '021-1234');
  try
    (grid.Header.Columns[0] as TTyGridColumn).EditMask := '000-0000';
    TypeKey('9');
    AssertTrue('the key opened the mask editor', grid.EditorControl is TTyMaskEdit);
    mask := TTyMaskEdit(grid.EditorControl);
    AssertTrue('which holds the focus', GetFocus = mask.Handle);
    AssertEquals('the key fills the first slot and the old digits are gone', '9__-____',
      mask.Text);
    TypeKey('8');
    AssertEquals('the next key fills the next slot', '98_-____', mask.Text);
    grid.EndEdit(False);
    AssertNothingRaised('typing on a mask cell');
  finally
    grid.Free;
  end;
end;

{ The date and time cells share one picker, and it keeps the field the last edit left it on.
  Typing on a cell starts what the cell will hold, so the key goes into the first field
  whatever field that was. The field order is pinned so the expectation does not ride on
  this machine's locale. }
procedure TTyClickFocusTest.TestTypingOnADateCellStartsTheFirstFieldWithThatKey;
var
  grid: TTyStringGrid;
  dtp: TTyDateTimePicker;
begin
  grid := NewEditorGrid(gekDate, DateToStr(EncodeDate(2026, 10, 12)));
  try
    AssertTrue('setup: editing the cell', grid.BeginEdit(0, 1));
    Forms.Application.ProcessMessages;
    AssertTrue('setup: the cell edits in a date picker',
      grid.EditorControl is TTyDateTimePicker);
    dtp := TTyDateTimePicker(grid.EditorControl);
    dtp.DateFormat := 'yyyy-mm-dd';
    PressKey(VK_RIGHT);
    AssertEquals('setup: the last edit left the picker on its second field', 1, dtp.ActiveSeg);
    grid.EndEdit(False);
    grid.SetFocus;
    Forms.Application.ProcessMessages;

    TypeKey('2');
    AssertSame('the key opened the date picker', TControl(dtp), grid.EditorControl);
    AssertTrue('which holds the focus', GetFocus = dtp.Handle);
    AssertEquals('the key went into the first field', 0, dtp.ActiveSeg);
    AssertEquals('as its first digit', '2', dtp.DigitBuffer);
    TypeKey('0');
    TypeKey('3');
    TypeKey('0');
    AssertEquals('the year typed straight through', 2030, YearOf(dtp.Date));
    grid.EndEdit(True);
    AssertEquals('and that is what the cell holds', DateToStr(EncodeDate(2030, 10, 12)),
      grid.Cells[0, 1]);
    AssertNothingRaised('typing on a date cell');
  finally
    grid.Free;
  end;
end;

procedure TTyClickFocusTest.TestTypingOnATimeCellStartsTheFirstFieldWithThatKey;
var
  grid: TTyStringGrid;
  dtp: TTyDateTimePicker;
begin
  grid := NewEditorGrid(gekTime, '08:30');
  try
    AssertTrue('setup: editing the cell', grid.BeginEdit(0, 1));
    Forms.Application.ProcessMessages;
    AssertTrue('setup: the cell edits in a time picker',
      grid.EditorControl is TTyDateTimePicker);
    dtp := TTyDateTimePicker(grid.EditorControl);
    dtp.TimeFormat := 'hh:nn:ss';
    PressKey(VK_RIGHT);
    AssertEquals('setup: the last edit left the picker on its second field', 1, dtp.ActiveSeg);
    grid.EndEdit(False);
    grid.SetFocus;
    Forms.Application.ProcessMessages;

    TypeKey('1');
    AssertSame('the key opened the time picker', TControl(dtp), grid.EditorControl);
    AssertTrue('which holds the focus', GetFocus = dtp.Handle);
    AssertEquals('the key went into the first field', 0, dtp.ActiveSeg);
    AssertEquals('as its first digit', '1', dtp.DigitBuffer);
    TypeKey('9');
    AssertEquals('the hour typed straight through', 19, HourOf(dtp.Time));
    grid.EndEdit(True);
    { The grid writes a time as hh:nn (PendingEditText). }
    AssertEquals('and that is what the cell holds', '19:30', grid.Cells[0, 1]);
    AssertNothingRaised('typing on a time cell');
  finally
    grid.Free;
  end;
end;

{ A pick list takes a typed letter as "the item that starts with it", and a pick commits at
  once and hands the focus back to the grid (#59). Typing on, the letters run together into
  one search -- the same search an open pick list runs -- so "bl" reaches blueberry past
  banana. }
procedure TTyClickFocusTest.TestTypingOnAPickListCellPicksByThatKey;
var
  grid: TTyStringGrid;
begin
  grid := NewEditorGrid(gekPickList, 'apple');
  try
    (grid.Header.Columns[0] as TTyGridColumn).PickList.CommaText :=
      'apple,banana,blueberry,cherry';
    TypeKey('b');
    AssertEquals('the key picked the first item it starts, and that committed', 'banana',
      grid.Cells[0, 1]);
    AssertTheGridHasTheFocus(grid, 'after a pick by typing on the cell');
    TypeKey('l');
    AssertEquals('the next key went on with the same search', 'blueberry', grid.Cells[0, 1]);
    AssertTheGridHasTheFocus(grid, 'after typing on');
    AssertNothingRaised('typing on a pick-list cell');
  finally
    grid.Free;
  end;
end;

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
