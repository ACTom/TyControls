unit test.menu;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Forms, Menus, fpcunit, testregistry, tyControls.Menu;
type
  TMenuModelTest = class(TTestCase)
  published
    procedure TestBuildRowsMapsFields;
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
  end;

  TMenuViewTest = class(TTestCase)
  published
    procedure TestMeasureAndHitTest;
    procedure TestKeyboardHighlightSkipsSeparatorsAndDisabled;
  end;

  { Probe subclass: exposes TTyMenuPopup's protected ComputeBounds seam so the
    anchor->screen-rect placement (with edge flipping) is testable without a real
    win32 popup form (the GUI window itself raises 1407 headless). }
  TTyMenuPopupAccess = class(TTyMenuPopup)
  public
    function ComputeBounds(const AAnchor: TRect; AWidth, AHeight, APPI: Integer;
      AToRight: Boolean): TRect;
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
    AssertTrue ('recent has submenu', rows[3].HasSubmenu);
  finally
    mm.Free;
  end;
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

{ TTyMenuPopupAccess }

function TTyMenuPopupAccess.ComputeBounds(const AAnchor: TRect;
  AWidth, AHeight, APPI: Integer; AToRight: Boolean): TRect;
begin
  Result := inherited ComputeBounds(AAnchor, AWidth, AHeight, APPI, AToRight);
end;

{ TMenuViewTest }

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

initialization
  RegisterTest(TMenuModelTest);
  RegisterTest(TMenuViewTest);
  RegisterTest(TMenuPopupTest);
end.
