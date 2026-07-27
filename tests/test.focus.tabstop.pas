unit test.focus.tabstop;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, Controls, Forms, fpcunit, testregistry,
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

initialization
  RegisterTest(TTyFocusTabStopTest);
end.
