unit test.menu;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Forms, Menus, fpcunit, testregistry, tyControls.Menu;
type
  TMenuModelTest = class(TTestCase)
  published
    procedure TestBuildRowsMapsFields;
    procedure TestParseMnemonic;
    procedure TestBuildRowsParsesMnemonic;
  end;

  { Probe subclass: exposes TTyMenuView's protected geometry + navigation seams so
    the pure measure/hit-test/highlight logic is exercised headlessly (no window). }
  TTyMenuViewAccess = class(TTyMenuView)
  public
    function RowCount: Integer;
    function MeasureHeight(APPI: Integer): Integer;
    function RowTop(AIndex, APPI: Integer): Integer;
    function RowAtY(AY, APPI: Integer): Integer;
    procedure SetHighlight(AIndex: Integer);
    procedure MoveHighlight(ADelta: Integer);
    function Highlight: Integer;
    // Hover-open seams: SimulateHoverOnto highlights a row and arms the lazy hover-open
    // exactly as a mouse-move onto a new row does; TickHover runs the timer fire.
    procedure SimulateHoverOnto(AIndex: Integer);
    procedure TickHover;
  end;

  TMenuViewTest = class(TTestCase)
  private
    FOpenedIndex: Integer;
    procedure HandleOpenSubmenu(Sender: TObject; AIndex: Integer);
  published
    procedure TestMeasureAndHitTest;
    procedure TestKeyboardHighlightSkipsSeparatorsAndDisabled;
    procedure TestHoverOnSubmenuRowFiresOpenAfterTick;
  end;

  { Probe subclass: exposes TTyMenuPopup's protected ComputeBounds seam so the
    anchor->screen-rect placement (with edge flipping) is testable without a real
    win32 popup form (the GUI window itself raises 1407 headless). }
  TTyMenuPopupAccess = class(TTyMenuPopup)
  public
    function ComputeBounds(const AAnchor: TRect; AWidth, AHeight, APPI: Integer;
      AToRight: Boolean): TRect;
    function ChildRowCountForTest: Integer;
  end;

  { Verifies TTyMenuPopup (Task 4): the borderless TForm host + cascade. The window
    itself needs a GUI loop, so we exercise the headless seams: ComputeBounds (anchor
    -> screen rect with screen-edge flipping) and that activating a leaf row fires the
    source item's OnClick (the activation path a real click runs). FFired is set by
    the leaf's OnClick handler. }
  TMenuPopupTest = class(TTestCase)
  private
    FFired: Boolean;
    procedure LeafClick(Sender: TObject);
  published
    procedure TestActivateLeafFiresItemOnClick;
    procedure TestComputeBoundsFlipsNearScreenEdges;
    procedure TestOpenSubmenuParentDoesNotRaiseAndPopulatesChild;
  end;

  { Probe subclass: exposes TTyMenuBar's protected top-cell geometry seams so the
    horizontal cell layout + hit-test (which top item an X falls in) is testable
    headlessly, without a real bar window (the GUI window raises 1407 headless). }
  TTyMenuBarAccess = class(TTyMenuBar)
  public
    function TopCount: Integer;
    function TopCaption(AIndex: Integer): string;
    function TopCellWidth(AIndex, APPI: Integer): Integer;
    function TopLeft(AIndex, APPI: Integer): Integer;
    function TopAtX(AX, APPI: Integer): Integer;
    function FitWidth(APPI: Integer): Integer;
  end;

  { Verifies TTyMenuBar (Task 5): an associated TMainMenu rendered as horizontal top
    cells. The cell layout + hit-test are pure geometry (TopCount/TopCaption/TopLeft/
    TopAtX), exercised here with no window. }
  TMenuBarTest = class(TTestCase)
  published
    procedure TestTopCellsAndHitTest;
    procedure TestAutoSizeWidthFitsContentExceptAlignTopBottom;
  end;

  { Verifies TTyPopupMenu (Task 7): a themed context menu over the LCL TPopupMenu
    model. PopUp(X,Y) routes to our themed TTyMenuPopup renderer instead of the native
    menu; choosing a row fires the source item's OnClick. The window itself needs a GUI
    loop, so we drive the activation path through the ActivateRowForTest seam (mirrors
    choosing the row in the themed popup). FFired is set by the leaf's OnClick handler. }
  TPopupMenuTest = class(TTestCase)
  private
    FFired: Boolean;
    procedure LeafClick(Sender: TObject);
  published
    procedure TestPopupRoutesToThemedRendererAndFires;
  end;

implementation

procedure TMenuModelTest.TestBuildRowsMapsFields;
var mm: TMainMenu; top, sub: TMenuItem; rows: TTyMenuRowArray;
begin
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); top.Caption := 'File';        mm.Items.Add(top);
    // children of 'File': an item with a shortcut, a separator, a checked item, a submenu
    sub := TMenuItem.Create(mm); sub.Caption := 'Open'; sub.ShortCut := ShortCut(Ord('O'), [ssCtrl]);
    top.Add(sub);
    top.Add(NewLine);                                          // separator ('-')
    sub := TMenuItem.Create(mm); sub.Caption := 'Word Wrap'; sub.Checked := True; top.Add(sub);
    sub := TMenuItem.Create(mm); sub.Caption := 'Recent';
    sub.Add(NewItem('doc.txt', 0, False, True, nil, 0, ''));   // makes 'Recent' a submenu
    top.Add(sub);
    sub := TMenuItem.Create(mm); sub.Caption := 'Hidden'; sub.Visible := False; top.Add(sub);

    rows := TyBuildMenuRows(top);                              // rows for File's dropdown
    AssertEquals('visible rows', 4, Length(rows));             // Open, sep, Word Wrap, Recent (Hidden skipped)
    AssertEquals('open caption', 'Open', rows[0].Caption);
    AssertTrue ('open has shortcut text', rows[0].ShortcutText <> '');
    AssertTrue ('row1 is separator', rows[1].Kind = mrkSeparator);
    AssertTrue ('word wrap checked', rows[2].Checked);
    AssertEquals('no-shortcut item has EMPTY shortcut text (not "Unknown")', '', rows[2].ShortcutText);
    AssertTrue ('recent has submenu', rows[3].HasSubmenu);
  finally
    mm.Free;
  end;
end;

procedure TMenuModelTest.TestParseMnemonic;
var disp: string; pos: Integer; m: Char;
begin
  // single '&' -> mnemonic on the NEXT char, '&' removed from display
  m := TyParseMnemonic('&File', disp, pos);
  AssertEquals('display strips &', 'File', disp);
  AssertEquals('mnemonic char', 'F', m);
  AssertEquals('mnemonic pos (1-based)', 1, pos);

  // mid-word mnemonic
  m := TyParseMnemonic('Save &As', disp, pos);
  AssertEquals('display', 'Save As', disp);
  AssertEquals('mnemonic char', 'A', m);
  AssertEquals('mnemonic pos', 6, pos);

  // '&&' -> literal '&', no mnemonic
  m := TyParseMnemonic('Fish && Chips', disp, pos);
  AssertEquals('display keeps one &', 'Fish & Chips', disp);
  AssertEquals('no mnemonic', #0, m);
  AssertEquals('no mnemonic pos', 0, pos);

  // no '&' at all
  m := TyParseMnemonic('Edit', disp, pos);
  AssertEquals('display unchanged', 'Edit', disp);
  AssertEquals('no mnemonic', #0, m);

  // mnemonic is upper-cased
  m := TyParseMnemonic('e&xit', disp, pos);
  AssertEquals('display', 'exit', disp);
  AssertEquals('mnemonic upper-cased', 'X', m);
  AssertEquals('pos', 2, pos);
end;

procedure TMenuModelTest.TestBuildRowsParsesMnemonic;
var mm: TMainMenu; top, it: TMenuItem; rows: TTyMenuRowArray;
begin
  // TyBuildMenuRows must populate Display + Mnemonic from each item's '&' caption
  // (the letter-jump + underline rely on these per-row fields).
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); top.Caption := 'File'; mm.Items.Add(top);
    it := TMenuItem.Create(mm); it.Caption := '&Open'; top.Add(it);
    it := TMenuItem.Create(mm); it.Caption := 'E&xit'; top.Add(it);
    rows := TyBuildMenuRows(top);
    AssertEquals('open display', 'Open', rows[0].Display);
    AssertEquals('open mnemonic', 'O', rows[0].Mnemonic);
    AssertEquals('open mnemonic pos', 1, rows[0].MnemonicPos);
    AssertEquals('exit display', 'Exit', rows[1].Display);
    AssertEquals('exit mnemonic', 'X', rows[1].Mnemonic);
    AssertEquals('exit mnemonic pos', 2, rows[1].MnemonicPos);
  finally mm.Free; end;
end;

{ TTyMenuViewAccess }

function TTyMenuViewAccess.RowCount: Integer;
begin
  Result := inherited RowCount;
end;

function TTyMenuViewAccess.MeasureHeight(APPI: Integer): Integer;
begin
  Result := inherited MeasureHeight(APPI);
end;

function TTyMenuViewAccess.RowTop(AIndex, APPI: Integer): Integer;
begin
  Result := inherited RowTop(AIndex, APPI);
end;

function TTyMenuViewAccess.RowAtY(AY, APPI: Integer): Integer;
begin
  Result := inherited RowAtY(AY, APPI);
end;

procedure TTyMenuViewAccess.SetHighlight(AIndex: Integer);
begin
  inherited SetHighlight(AIndex);
end;

procedure TTyMenuViewAccess.MoveHighlight(ADelta: Integer);
begin
  inherited MoveHighlight(ADelta);
end;

function TTyMenuViewAccess.Highlight: Integer;
begin
  Result := inherited Highlight;
end;

procedure TTyMenuViewAccess.SimulateHoverOnto(AIndex: Integer);
begin
  // Mirror a mouse-move onto a NEW row: set the highlight, then arm the lazy
  // hover-open exactly as TTyMenuView.MouseMove does when the highlight changes.
  inherited SetHighlight(AIndex);
  inherited UpdateHoverOpen;
end;

procedure TTyMenuViewAccess.TickHover;
begin
  inherited TickHoverForTest;
end;

{ TTyMenuPopupAccess }

function TTyMenuPopupAccess.ComputeBounds(const AAnchor: TRect;
  AWidth, AHeight, APPI: Integer; AToRight: Boolean): TRect;
begin
  Result := inherited ComputeBounds(AAnchor, AWidth, AHeight, APPI, AToRight);
end;

function TTyMenuPopupAccess.ChildRowCountForTest: Integer;
begin
  Result := inherited ChildRowCountForTest;
end;

{ TTyMenuBarAccess }

function TTyMenuBarAccess.TopCount: Integer;
begin
  Result := inherited TopCount;
end;

function TTyMenuBarAccess.TopCaption(AIndex: Integer): string;
begin
  Result := inherited TopCaption(AIndex);
end;

function TTyMenuBarAccess.TopCellWidth(AIndex, APPI: Integer): Integer;
begin
  Result := inherited TopCellWidth(AIndex, APPI);
end;

function TTyMenuBarAccess.TopLeft(AIndex, APPI: Integer): Integer;
begin
  Result := inherited TopLeft(AIndex, APPI);
end;

function TTyMenuBarAccess.TopAtX(AX, APPI: Integer): Integer;
begin
  Result := inherited TopAtX(AX, APPI);
end;

function TTyMenuBarAccess.FitWidth(APPI: Integer): Integer;
begin
  Result := inherited FitWidth(APPI);
end;

{ TMenuViewTest }

procedure TMenuViewTest.HandleOpenSubmenu(Sender: TObject; AIndex: Integer);
begin
  FOpenedIndex := AIndex;
end;

procedure TMenuViewTest.TestHoverOnSubmenuRowFiresOpenAfterTick;
var v: TTyMenuViewAccess; mm: TMainMenu; top, sub: TMenuItem;
begin
  FOpenedIndex := -1;
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); top.Caption := 'File'; mm.Items.Add(top);
    // row 0: a plain leaf; row 1: a submenu parent (has a child item).
    top.Add(NewItem('Open', 0, False, True, nil, 0, ''));
    sub := TMenuItem.Create(mm); sub.Caption := 'Recent';
    sub.Add(NewItem('doc.txt', 0, False, True, nil, 0, ''));   // makes 'Recent' a submenu
    top.Add(sub);

    v := TTyMenuViewAccess.Create(nil);
    try
      v.SetRows(TyBuildMenuRows(top));
      v.OnOpenSubmenu := @HandleOpenSubmenu;

      // Hover the plain leaf (row 0): a tick must NOT fire OnOpenSubmenu (no submenu).
      v.SimulateHoverOnto(0);
      v.TickHover;
      AssertEquals('leaf hover does not open a submenu', -1, FOpenedIndex);

      // Hover the submenu row (row 1): arms the lazy hover-open; the tick fires it.
      v.SimulateHoverOnto(1);
      AssertEquals('not opened until the timer ticks', -1, FOpenedIndex);
      v.TickHover;
      AssertEquals('hover tick opens the submenu row', 1, FOpenedIndex);

      // Moving the highlight off the submenu row before a tick cancels the pending open.
      FOpenedIndex := -1;
      v.SimulateHoverOnto(1);   // re-arm on the submenu row
      v.SimulateHoverOnto(0);   // then move onto the leaf (disarms)
      v.TickHover;
      AssertEquals('moving off the submenu row cancels the pending open', -1, FOpenedIndex);
    finally v.Free; end;
  finally mm.Free; end;
end;

procedure TMenuViewTest.TestMeasureAndHitTest;
var v: TTyMenuViewAccess; mm: TMainMenu; top: TMenuItem;
begin
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); top.Caption := 'Edit'; mm.Items.Add(top);
    top.Add(NewItem('Cut',  0, False, True, nil, 0, ''));
    top.Add(NewLine);
    top.Add(NewItem('Copy', 0, False, True, nil, 0, ''));
    v := TTyMenuViewAccess.Create(nil);
    try
      v.SetRows(TyBuildMenuRows(top));
      AssertEquals('3 rows', 3, v.RowCount);
      // height = item rows * itemH + separators * sepH (+ vertical padding); just assert > 0 + monotonic
      AssertTrue('height positive', v.MeasureHeight(96) > 0);
      // hit-test: y inside row 0 maps to 0; the separator row reports -1 (not selectable)
      AssertEquals('row 0 hit', 0, v.RowAtY(v.RowTop(0, 96) + 1, 96));
      AssertEquals('separator not selectable', -1, v.RowAtY(v.RowTop(1, 96) + 1, 96));
    finally v.Free; end;
  finally mm.Free; end;
end;

procedure TMenuViewTest.TestKeyboardHighlightSkipsSeparatorsAndDisabled;
var v: TTyMenuViewAccess; mm: TMainMenu; top: TMenuItem;
begin
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); mm.Items.Add(top);
    top.Add(NewItem('A', 0, False, True,  nil, 0, ''));
    top.Add(NewLine);
    top.Add(NewItem('B', 0, False, False, nil, 0, ''));  // disabled (Enabled=False)
    top.Add(NewItem('C', 0, False, True,  nil, 0, ''));
    v := TTyMenuViewAccess.Create(nil);
    try
      v.SetRows(TyBuildMenuRows(top));
      v.SetHighlight(-1);
      v.MoveHighlight(+1); AssertEquals('first selectable A', 0, v.Highlight);
      v.MoveHighlight(+1); AssertEquals('skip sep+disabled to C', 3, v.Highlight);
      v.MoveHighlight(+1); AssertEquals('wraps to A', 0, v.Highlight);
      v.MoveHighlight(-1); AssertEquals('prev wraps to C', 3, v.Highlight);
    finally v.Free; end;
  finally mm.Free; end;
end;

{ TMenuPopupTest }

procedure TMenuPopupTest.LeafClick(Sender: TObject);
begin
  FFired := True;
end;

procedure TMenuPopupTest.TestActivateLeafFiresItemOnClick;
var pop: TTyMenuPopup; mm: TMainMenu; top, leaf: TMenuItem;
begin
  FFired := False;
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); mm.Items.Add(top);
    leaf := TMenuItem.Create(mm); leaf.Caption := 'Go';
    leaf.OnClick := @LeafClick;     // sets FFired := True
    top.Add(leaf);
    pop := TTyMenuPopup.Create(nil);
    try
      pop.SetRoot(top);
      pop.ActivateRowForTest(0);    // test seam: activate row 0 as if clicked
      AssertTrue('leaf OnClick fired', FFired);
    finally pop.Free; end;
  finally mm.Free; end;
end;

procedure TMenuPopupTest.TestOpenSubmenuParentDoesNotRaiseAndPopulatesChild;
var
  pop: TTyMenuPopupAccess; mm: TMainMenu; top, sub: TMenuItem;
begin
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); mm.Items.Add(top);
    // row 0 is a submenu parent with two visible children.
    sub := TMenuItem.Create(mm); sub.Caption := 'Recent';
    sub.Add(NewItem('a.txt', 0, False, True, nil, 0, ''));
    sub.Add(NewItem('b.txt', 0, False, True, nil, 0, ''));
    top.Add(sub);

    pop := TTyMenuPopupAccess.Create(nil);
    try
      pop.SetRoot(top);
      // Before opening there is no child cascade.
      AssertEquals('no child before opening', -1, pop.ChildRowCountForTest);
      // Activating the submenu-parent row must NOT raise (the old FView nil-deref bug)
      // and must create + POPULATE the child with the submenu's two rows.
      pop.ActivateRowForTest(0);
      AssertEquals('child created and populated with 2 rows', 2, pop.ChildRowCountForTest);
    finally pop.Free; end;
  finally mm.Free; end;
end;

procedure TMenuPopupTest.TestComputeBoundsFlipsNearScreenEdges;
var
  pop: TTyMenuPopupAccess; mm: TMainMenu; top: TMenuItem;
  anchor: TRect; r: TRect; w, h, sw, sh: Integer;
begin
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); mm.Items.Add(top);
    top.Add(NewItem('One', 0, False, True, nil, 0, ''));
    top.Add(NewItem('Two', 0, False, True, nil, 0, ''));
    pop := TTyMenuPopupAccess.Create(nil);
    try
      pop.SetRoot(top);
      w := 120; h := 80;
      sw := Screen.Width; sh := Screen.Height;

      // Anchor near top-left: popup hangs below the anchor, left edge aligned.
      anchor := Rect(40, 40, 160, 64);
      r := pop.ComputeBounds(anchor, w, h, 96, False);
      AssertEquals('drops below anchor bottom', anchor.Bottom, r.Top);
      AssertEquals('aligns to anchor left', anchor.Left, r.Left);
      AssertEquals('width preserved', w, r.Right - r.Left);
      AssertEquals('height preserved', h, r.Bottom - r.Top);

      // Anchor near the BOTTOM edge: not enough room below, flips ABOVE the anchor.
      anchor := Rect(40, sh - 10, 160, sh - 2);
      r := pop.ComputeBounds(anchor, w, h, 96, False);
      AssertTrue('flips above when no room below', r.Bottom <= anchor.Top + 1);

      // Anchor near the RIGHT edge: popup would overflow, flips LEFT of the anchor.
      anchor := Rect(sw - 6, 40, sw - 2, 64);
      r := pop.ComputeBounds(anchor, w, h, 96, True);   // AToRight submenu placement
      AssertTrue('flips left when no room right', r.Right <= anchor.Left + 1);
    finally pop.Free; end;
  finally mm.Free; end;
end;

{ TMenuBarTest }

procedure TMenuBarTest.TestTopCellsAndHitTest;
var bar: TTyMenuBarAccess; mm: TMainMenu;
begin
  mm := TMainMenu.Create(nil);
  try
    // NOTE: this LCL's NewSubMenu signature is
    //   NewSubMenu(const ACaption; hCtx; const AName; const Items: array of TMenuItem; ...)
    // so the children pass as an open array and the 3rd arg is the component Name
    // (not a single child item as the plan sketch assumed).
    mm.Items.Add(NewSubMenu('File', 0, '', [NewItem('New', 0, False, True, nil, 0, '')]));
    mm.Items.Add(NewSubMenu('Edit', 0, '', [NewItem('Cut', 0, False, True, nil, 0, '')]));
    bar := TTyMenuBarAccess.Create(nil);
    try
      bar.Menu := mm;
      AssertEquals('2 top cells', 2, bar.TopCount);
      AssertEquals('cell0 caption', 'File', bar.TopCaption(0));
      AssertEquals('hit inside cell1 -> 1', 1, bar.TopAtX(bar.TopLeft(1, 96) + 1, 96));
    finally bar.Free; end;
  finally mm.Free; end;
end;

procedure TMenuBarTest.TestAutoSizeWidthFitsContentExceptAlignTopBottom;
var
  bar: TTyMenuBarAccess; mm: TMainMenu; ppi, fit: Integer;
begin
  mm := TMainMenu.Create(nil);
  try
    // A 3-top-item menu so the fit-width is the sum of three cells + the bar padding.
    mm.Items.Add(NewSubMenu('File', 0, '', [NewItem('New', 0, False, True, nil, 0, '')]));
    mm.Items.Add(NewSubMenu('Edit', 0, '', [NewItem('Cut', 0, False, True, nil, 0, '')]));
    mm.Items.Add(NewSubMenu('View', 0, '', [NewItem('Zoom', 0, False, True, nil, 0, '')]));

    // Flag ON + Align=alNone: Width shrinks to exactly the content fit, which equals
    // TopLeft(last) + TopCellWidth(last) + the bar's right padding (== FitWidth).
    bar := TTyMenuBarAccess.Create(nil);
    try
      ppi := bar.Font.PixelsPerInch;
      if ppi <= 0 then ppi := 96;
      bar.Align := alNone;
      bar.AutoSizeWidth := True;
      bar.Menu := mm;
      AssertEquals('3 top cells', 3, bar.TopCount);
      // Content fit == last cell's right edge (TopLeft(last)+TopCellWidth(last)) plus
      // the bar's own right padding, so it must be at least that right edge.
      fit := bar.TopLeft(2, ppi) + bar.TopCellWidth(2, ppi);   // last cell right edge
      AssertTrue('content width is positive', fit > 0);
      AssertTrue('FitWidth covers the last cell right edge', bar.FitWidth(ppi) >= fit);
      AssertEquals('alNone Width fits the content', bar.FitWidth(ppi), bar.Width);
    finally bar.Free; end;

    // Flag ON but Align=alLeft (still not alTop/alBottom): also fits the content.
    bar := TTyMenuBarAccess.Create(nil);
    try
      ppi := bar.Font.PixelsPerInch;
      if ppi <= 0 then ppi := 96;
      bar.Align := alLeft;
      bar.AutoSizeWidth := True;
      bar.Menu := mm;
      AssertEquals('alLeft Width fits the content', bar.FitWidth(ppi), bar.Width);
    finally bar.Free; end;

    // Flag ON but Align=alTop: width is NOT force-fit (the LCL stretches it instead).
    bar := TTyMenuBarAccess.Create(nil);
    try
      bar.Align := alTop;
      bar.Width := 500;          // a deliberately non-fit width
      bar.AutoSizeWidth := True;
      bar.Menu := mm;
      AssertEquals('alTop width is left at its set value (not fit)', 500, bar.Width);
    finally bar.Free; end;
  finally mm.Free; end;
end;

{ TPopupMenuTest }

procedure TPopupMenuTest.LeafClick(Sender: TObject);
begin
  FFired := True;
end;

procedure TPopupMenuTest.TestPopupRoutesToThemedRendererAndFires;
var pm: TTyPopupMenu; it: TMenuItem;
begin
  FFired := False;
  pm := TTyPopupMenu.Create(nil);
  try
    it := TMenuItem.Create(pm); it.Caption := 'Paste';
    it.OnClick := @LeafClick;     // sets FFired := True
    pm.Items.Add(it);
    pm.ActivateRowForTest(0);     // test seam mirrors choosing the row in the themed popup
    AssertTrue('paste fired', FFired);
  finally pm.Free; end;
end;

initialization
  RegisterTest(TMenuModelTest);
  RegisterTest(TMenuViewTest);
  RegisterTest(TMenuPopupTest);
  RegisterTest(TMenuBarTest);
  RegisterTest(TPopupMenuTest);
end.
