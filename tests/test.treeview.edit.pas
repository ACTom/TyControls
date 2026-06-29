unit test.treeview.edit;
{ ③e — inline cell editing tests.
  E1: scaffolding only (toEditable option + editor field + edit-state +
  read-only props + stub methods).
  E2: the core lifecycle — EditNode opens + seeds + positions the editor,
  EndEditNode commits (OnNewText iff changed), CancelEdit discards
  (OnEditCancelled), plus the OnEditing veto. Headless: a real TForm parent +
  a Controller (so RenderTo/GetCellRect lay out), but no window handle — the
  tests drive EditNode/EndEditNode/CancelEdit directly (handle-needing calls
  CanFocus/SetFocus/SelectAll are guarded in the control). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType,
  fpcunit, testregistry,
  tyControls.Edit,
  tyControls.TreeView.Columns,
  tyControls.TreeView,
  tyControls.Controller;

type
  { E1: the opt-in option + edit state default to "off" }
  TTreeEditE1Test = class(TTestCase)
  published
    procedure TestEditableOptionDefaultsOff;
  end;

  { E3: triggers — MouseDown records the column under the cursor, double-click
    edits an editable cell (instead of toggling expand), F2 edits the focused
    node. Headless: a real TForm + Controller + a RenderTo layout pass so the
    hit-test resolves real device coordinates; the tests drive the protected
    MouseDown/DblClick/KeyDown through a hard-cast descendant. }
  TTreeEditE3Test = class(TTestCase)
  private
    FCtl:  TTyStyleController;
    FForm: TForm;
    FTree: TTyTreeView;
    procedure OnGetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
    procedure BuildTree(AColumns: Boolean);
    procedure Layout;
  protected
    procedure TearDown; override;
  published
    procedure TestMouseDownRecordsColumn;
    procedure TestDoubleClickEditsEditableCell;
    procedure TestDoubleClickTogglesWhenNotEditable;
    procedure TestF2EditsFocusedNode;
  end;

  { E2: open / commit / cancel + events. A 1-column tree with an OnGetText that
    returns a known per-node string; a real TForm + Controller so GetCellRect
    resolves a non-empty device rect. }
  TTreeEditE2Test = class(TTestCase)
  private
    FCtl:   TTyStyleController;
    FForm:  TForm;
    FTree:  TTyTreeView;
    FNode0: PTyTreeNode;
    { event bookkeeping }
    FEditingFired:    Integer;
    FEditingAllow:    Boolean;     // what the handler sets Allowed to
    FNewTextFired:    Integer;
    FNewTextValue:    string;
    FNewTextNode:     PTyTreeNode;
    FNewTextColumn:   Integer;
    FCancelledFired:  Integer;
    FCancelledNode:   PTyTreeNode;
    FCancelledColumn: Integer;
    procedure OnGetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
    procedure OnEditing(Sender: TTyTreeView; Node: PTyTreeNode; Column: Integer;
      var Allowed: Boolean);
    procedure OnNewText(Sender: TTyTreeView; Node: PTyTreeNode; Column: Integer;
      const NewText: string);
    procedure OnEditCancelled(Sender: TTyTreeView; Node: PTyTreeNode; Column: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEditNodeOpensAndSeedsText;
    procedure TestEditNodeVetoedByOnEditing;
    procedure TestEndEditNodeFiresOnNewTextOnChange;
    procedure TestEndEditNodeNoEventWhenUnchanged;
    procedure TestCancelEditFiresCancelledNoNewText;
  end;

implementation

const
  EDIT_THEME_CSS =
    'TyTreeView { background: #FFFFFF; border-width: 0px; padding: 0px; } ' +
    'TyTreeNode { background: none; color: #000000; } ' +
    'TyTreeNode:selected { background: #3B82F6; color: #FFFFFF; } ' +
    'TyEdit { background: #FFFFFF; color: #000000; border-width: 1px; } ';

type
  { hard-cast helper: reach the protected RenderTo (to lay out) + the private
    inline editor + the protected EditorBoundsFromCell from the test. }
  TEditTreeAccess = class(TTyTreeView)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function  Editor: TTyEdit;
    procedure SetEditorText(const S: string);
    function  EditorBoundsFromCellPub(const R: TRect): TRect;
    { E3: drive the protected input handlers + read the recorded column. }
    procedure MouseDownPub(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure DblClickPub;
    procedure KeyDownPub(var Key: Word; Shift: TShiftState);
    function  LastMouseColumnPub: Integer;
  end;

procedure TEditTreeAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

function TEditTreeAccess.Editor: TTyEdit;
begin
  Result := InlineEditor;
end;

procedure TEditTreeAccess.SetEditorText(const S: string);
begin
  InlineEditor.Text := S;
end;

function TEditTreeAccess.EditorBoundsFromCellPub(const R: TRect): TRect;
begin
  Result := EditorBoundsFromCell(R);
end;

procedure TEditTreeAccess.MouseDownPub(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  MouseDown(Button, Shift, X, Y);
end;

procedure TEditTreeAccess.DblClickPub;
begin
  DblClick;
end;

procedure TEditTreeAccess.KeyDownPub(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

function TEditTreeAccess.LastMouseColumnPub: Integer;
begin
  Result := LastMouseColumn;
end;

{ ----------------------------------------------------------------------------
  E1
  ---------------------------------------------------------------------------- }

procedure TTreeEditE1Test.TestEditableOptionDefaultsOff;
var
  Tree: TTyTreeView;
begin
  Tree := TTyTreeView.Create(nil);
  try
    AssertFalse('toEditable must default OFF', toEditable in Tree.Options);
    AssertFalse('IsEditing must default False', Tree.IsEditing);
    AssertFalse('EditNode(nil,0) must return False', Tree.EditNode(nil, 0));
  finally
    Tree.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  E3 — triggers (MouseDown column tracking, double-click-to-edit, F2)
  ---------------------------------------------------------------------------- }

procedure TTreeEditE3Test.OnGetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var Text: string);
begin
  Text := 'row' + IntToStr(Node^.Index);
end;

{ Build a tree with one root that has children (so it is expandable + collapsed)
  plus a couple of leaf siblings. With AColumns, three columns are added so the
  column hit-test resolves a non-main column. Layout mirrors the ③d GetCellRect
  fixture: col0=[0..120), col1=[120..200), col2=[200..300); header band y=[0..22),
  row 0 (root) y=[22..44). }
procedure TTreeEditE3Test.BuildTree(AColumns: Boolean);
var
  col0, col1, col2: TTyTreeColumn;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(EDIT_THEME_CSS);

  FForm := TForm.CreateNew(nil);
  FTree := TTyTreeView.Create(FForm);
  FTree.Parent     := FForm;
  FTree.Controller := FCtl;
  FTree.Font.PixelsPerInch := 96;
  FTree.DefaultNodeHeight  := 22;
  FTree.Indent             := 16;
  FTree.ShowButtons        := True;
  FTree.ShowTreeLines      := False;
  FTree.ShowRoot           := True;
  FTree.SetBounds(0, 0, 300, 200);
  FTree.OnGetText          := @OnGetText;

  if AColumns then
  begin
    col0 := FTree.Header.Columns.Add as TTyTreeColumn;
    col0.Width := 120; col0.Text := 'Name';
    col1 := FTree.Header.Columns.Add as TTyTreeColumn;
    col1.Width := 80;  col1.Text := 'Info';
    col2 := FTree.Header.Columns.Add as TTyTreeColumn;
    col2.Width := 100; col2.Text := 'Size';
    FTree.Header.MainColumn := 0;
    FTree.Header.Options    := [hoVisible];
  end;

  { 3 root nodes; the first is given children via AddChild (which also marks the
    parent nsHasChildren, so it is expandable + starts collapsed). }
  FTree.RootNodeCount := 3;
  FTree.InitNode(FTree.RootNode^.FirstChild);
  FTree.AddChild(FTree.RootNode^.FirstChild);
  FTree.AddChild(FTree.RootNode^.FirstChild);
end;

procedure TTreeEditE3Test.Layout;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(300, 200);
    TEditTreeAccess(FTree).RenderTo(Bmp.Canvas, Rect(0, 0, 300, 200), 96);
  finally
    Bmp.Free;
  end;
end;

procedure TTreeEditE3Test.TearDown;
begin
  FForm.Free;   // frees FTree (owned)
  FCtl.Free;
end;

{ MouseDown over column 1's x-band (x=150) records FLastMouseColumn = 1. }
procedure TTreeEditE3Test.TestMouseDownRecordsColumn;
begin
  BuildTree(True);
  Layout;
  { Row 0 (root) is y=[22..44); x=150 sits inside col1=[120..200). }
  TEditTreeAccess(FTree).MouseDownPub(mbLeft, [], 150, 30);
  AssertEquals('MouseDown records the column under the cursor',
    1, TEditTreeAccess(FTree).LastMouseColumnPub);
end;

{ Double-click on an editable cell starts editing and does NOT toggle expand. }
procedure TTreeEditE3Test.TestDoubleClickEditsEditableCell;
var
  root: PTyTreeNode;
begin
  BuildTree(False);
  FTree.Options         := [toEditable];
  FTree.ToggleOnDblClick := True;   { would expand if edit did not pre-empt it }
  Layout;
  root := FTree.RootNode^.FirstChild;
  AssertFalse('precondition: root starts collapsed', FTree.Expanded[root]);

  { No header band (0-column tree) ⇒ row 0 (root) is y=[0..22); x=120 is in the
    label zone (past the button slot). Press there, then dbl-click. }
  TEditTreeAccess(FTree).MouseDownPub(mbLeft, [], 120, 10);
  TEditTreeAccess(FTree).DblClickPub;

  AssertTrue('double-click on editable cell starts editing', FTree.IsEditing);
  AssertTrue('edited node is the pressed node', FTree.EditedNode = root);
  AssertFalse('editable double-click did NOT toggle expand', FTree.Expanded[root]);
end;

{ Without toEditable, double-click keeps the existing toggle-expand behaviour. }
procedure TTreeEditE3Test.TestDoubleClickTogglesWhenNotEditable;
var
  root: PTyTreeNode;
begin
  BuildTree(False);
  FTree.Options          := [];
  FTree.ToggleOnDblClick := True;
  Layout;
  root := FTree.RootNode^.FirstChild;
  AssertFalse('precondition: root starts collapsed', FTree.Expanded[root]);

  { 0-column tree ⇒ row 0 (root) is y=[0..22). }
  TEditTreeAccess(FTree).MouseDownPub(mbLeft, [], 120, 10);
  TEditTreeAccess(FTree).DblClickPub;

  AssertTrue('non-editable double-click toggles expand', FTree.Expanded[root]);
  AssertFalse('non-editable double-click does not edit', FTree.IsEditing);
end;

{ F2 on the focused node edits the effective column (FLastMouseColumn when valid). }
procedure TTreeEditE3Test.TestF2EditsFocusedNode;
var
  root: PTyTreeNode;
  Key: Word;
begin
  BuildTree(True);
  FTree.Options := [toEditable];
  Layout;
  root := FTree.RootNode^.FirstChild;

  { Press in column 1's band so FLastMouseColumn = 1; F2 then edits that column. }
  TEditTreeAccess(FTree).MouseDownPub(mbLeft, [], 150, 30);
  FTree.FocusedNode := root;

  Key := VK_F2;
  TEditTreeAccess(FTree).KeyDownPub(Key, []);

  AssertTrue('F2 starts editing the focused node', FTree.IsEditing);
  AssertTrue('F2 edits the focused node', FTree.EditedNode = root);
  AssertEquals('F2 edits the recorded column (FLastMouseColumn)',
    1, FTree.EditedColumn);
  AssertEquals('F2 consumed the key', 0, Key);
end;

{ ----------------------------------------------------------------------------
  E2 fixture
  ---------------------------------------------------------------------------- }

procedure TTreeEditE2Test.OnGetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var Text: string);
begin
  Text := 'row' + IntToStr(Node^.Index);
end;

procedure TTreeEditE2Test.OnEditing(Sender: TTyTreeView; Node: PTyTreeNode;
  Column: Integer; var Allowed: Boolean);
begin
  Inc(FEditingFired);
  Allowed := FEditingAllow;
end;

procedure TTreeEditE2Test.OnNewText(Sender: TTyTreeView; Node: PTyTreeNode;
  Column: Integer; const NewText: string);
begin
  Inc(FNewTextFired);
  FNewTextNode   := Node;
  FNewTextColumn := Column;
  FNewTextValue  := NewText;
end;

procedure TTreeEditE2Test.OnEditCancelled(Sender: TTyTreeView; Node: PTyTreeNode;
  Column: Integer);
begin
  Inc(FCancelledFired);
  FCancelledNode   := Node;
  FCancelledColumn := Column;
end;

procedure TTreeEditE2Test.SetUp;
var
  Bmp: TBitmap;
begin
  FEditingFired   := 0;
  FEditingAllow   := True;
  FNewTextFired   := 0;
  FNewTextValue   := '';
  FNewTextNode    := nil;
  FNewTextColumn  := -99;
  FCancelledFired := 0;
  FCancelledNode  := nil;
  FCancelledColumn := -99;

  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(EDIT_THEME_CSS);

  FForm := TForm.CreateNew(nil);
  FTree := TTyTreeView.Create(FForm);
  FTree.Parent     := FForm;
  FTree.Controller := FCtl;
  FTree.Font.PixelsPerInch := 96;
  FTree.DefaultNodeHeight  := 22;
  FTree.Indent             := 16;
  FTree.ShowRoot           := True;
  FTree.SetBounds(0, 0, 200, 160);
  FTree.OnGetText        := @OnGetText;
  FTree.OnEditing        := @OnEditing;
  FTree.OnNewText        := @OnNewText;
  FTree.OnEditCancelled  := @OnEditCancelled;
  FTree.Options          := [toEditable];

  { 0-column (③a) tree: 3 root nodes; the cell IS the content row rect. }
  FTree.RootNodeCount := 3;
  FNode0 := FTree.RootNode^.FirstChild;
  FTree.InitNode(FNode0);

  { Force a layout pass so the position cache + scroll state are built (mirrors
    the ③d GetCellRect tests). GetCellRect then returns a real device rect. }
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(200, 160);
    TEditTreeAccess(FTree).RenderTo(Bmp.Canvas, Rect(0, 0, 200, 160), 96);
  finally
    Bmp.Free;
  end;
end;

procedure TTreeEditE2Test.TearDown;
begin
  FForm.Free;   // frees FTree (owned)
  FCtl.Free;
end;

{ EditNode opens the editor, seeds it with EXACTLY the painted cell text, and
  positions FEditor.BoundsRect inside the client to match GetCellRect's cell. }
procedure TTreeEditE2Test.TestEditNodeOpensAndSeedsText;
var
  ok: Boolean;
  cellR, edR, wantR: TRect;
begin
  ok := FTree.EditNode(FNode0, 0);
  AssertTrue('EditNode(first,0) returns True', ok);
  AssertTrue('IsEditing True after open', FTree.IsEditing);
  AssertTrue('editor visible after open', TEditTreeAccess(FTree).Editor.Visible);
  AssertEquals('editor seeded with cell text', 'row0',
    TEditTreeAccess(FTree).Editor.Text);
  AssertTrue('EditedNode = the opened node', FTree.EditedNode = FNode0);
  AssertEquals('EditedColumn = 0', 0, FTree.EditedColumn);

  { bounds: non-empty + inside the client, and exactly the inset of GetCellRect. }
  edR := TEditTreeAccess(FTree).Editor.BoundsRect;
  AssertFalse('editor bounds non-empty', IsRectEmpty(edR));
  AssertTrue('editor left within client', (edR.Left >= 0) and (edR.Left < FTree.Width));
  AssertTrue('editor top within client',  (edR.Top  >= 0) and (edR.Top  < FTree.Height));

  AssertTrue('GetCellRect resolves', FTree.GetCellRect(FNode0, 0, cellR));
  wantR := TEditTreeAccess(FTree).EditorBoundsFromCellPub(cellR);
  AssertTrue('editor bounds == EditorBoundsFromCell(GetCellRect) (L)', edR.Left = wantR.Left);
  AssertTrue('editor bounds == EditorBoundsFromCell(GetCellRect) (T)', edR.Top = wantR.Top);
  AssertTrue('editor bounds == EditorBoundsFromCell(GetCellRect) (R)', edR.Right = wantR.Right);
  AssertTrue('editor bounds == EditorBoundsFromCell(GetCellRect) (B)', edR.Bottom = wantR.Bottom);
end;

{ OnEditing sets Allowed:=False ⇒ EditNode refuses, no editor shown. }
procedure TTreeEditE2Test.TestEditNodeVetoedByOnEditing;
begin
  FEditingAllow := False;
  AssertFalse('EditNode refused when vetoed', FTree.EditNode(FNode0, 0));
  AssertEquals('OnEditing fired once', 1, FEditingFired);
  AssertFalse('not editing after veto', FTree.IsEditing);
  AssertFalse('editor hidden after veto', TEditTreeAccess(FTree).Editor.Visible);
end;

{ Changing the text then committing fires OnNewText once with the new string. }
procedure TTreeEditE2Test.TestEndEditNodeFiresOnNewTextOnChange;
begin
  AssertTrue('open', FTree.EditNode(FNode0, 0));
  TEditTreeAccess(FTree).SetEditorText('changed');
  FTree.EndEditNode;
  AssertEquals('OnNewText fired exactly once', 1, FNewTextFired);
  AssertEquals('OnNewText carries the new text', 'changed', FNewTextValue);
  AssertTrue('OnNewText carries the node', FNewTextNode = FNode0);
  AssertEquals('OnNewText carries the column', 0, FNewTextColumn);
  AssertFalse('not editing after commit', FTree.IsEditing);
end;

{ Committing with the text unchanged must NOT fire OnNewText. }
procedure TTreeEditE2Test.TestEndEditNodeNoEventWhenUnchanged;
begin
  AssertTrue('open', FTree.EditNode(FNode0, 0));
  { leave FEditor.Text == 'row0' }
  FTree.EndEditNode;
  AssertEquals('OnNewText NOT fired when unchanged', 0, FNewTextFired);
  AssertFalse('not editing after commit', FTree.IsEditing);
end;

{ Cancel fires OnEditCancelled, never OnNewText, even with a changed text. }
procedure TTreeEditE2Test.TestCancelEditFiresCancelledNoNewText;
begin
  AssertTrue('open', FTree.EditNode(FNode0, 0));
  TEditTreeAccess(FTree).SetEditorText('discard-me');
  FTree.CancelEdit;
  AssertEquals('OnEditCancelled fired once', 1, FCancelledFired);
  AssertTrue('OnEditCancelled carries the node', FCancelledNode = FNode0);
  AssertEquals('OnEditCancelled carries the column', 0, FCancelledColumn);
  AssertEquals('OnNewText NOT fired on cancel', 0, FNewTextFired);
  AssertFalse('not editing after cancel', FTree.IsEditing);
end;

initialization
  RegisterTest(TTreeEditE1Test);
  RegisterTest(TTreeEditE2Test);
  RegisterTest(TTreeEditE3Test);
end.
