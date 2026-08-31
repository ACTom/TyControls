unit test.treeselect;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.TreeView, tyControls.TreeSelect;

type
  { Pure-rule tests: the geometry, the drop sizing, what the field says, and which click
    commits. All of them take plain integers/strings/enums, so they run with no window
    handle, no theme and no control instance at all. }
  TTyTreeSelectRulesTest = class(TTestCase)
  published
    procedure TestTextBandIsPaddedField;
    procedure TestButtonHugsRightEdgeFullHeight;
    procedure TestWideButtonOverridesRightPadding;
    procedure TestNoButtonHonoursRightPadding;
    procedure TestNarrowFieldKeepsButtonDropsText;
    procedure TestPaddingEatsWholeField;
    procedure TestZeroSizeEmpty;
    procedure TestDropWidthZeroFollowsField;
    procedure TestDropWidthOverridesField;
    procedure TestDropHeightZeroTakesDefault;
    procedure TestDropHeightOverridesDefault;
    procedure TestDropSizeFloorsAtOne;
    procedure TestFieldTextIsNodeCaption;
    procedure TestSelectedBlankCaptionIsNotHint;
    procedure TestNoSelectionShowsHint;
    procedure TestNoSelectionNoHintIsEmpty;
    procedure TestCommitPartsMatchTreeSelectionRule;
    procedure TestIndentCommitsOnlyOnFullRowSelect;
  end;

  { Headless control behaviour: the typeKey it borrows, the defaults, the selection rules
    over a real (populated) tree, the theme-driven drop sizing, the tree-seeding on open,
    and the paint's degradation when the theme says nothing. }
  TTyTreeSelectControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FCaptions: TStringList;   // node data holds an index into this
    FChanged: Integer;        // TTyTreeSelect.OnChange fire count
    procedure HandleChange(Sender: TObject);
    procedure HandleGetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeyIsComboBox;
    procedure TestDefaults;
    procedure TestItemsForwardToTheDropTree;
    procedure TestItemsSurviveStreaming;
    procedure TestTreeIsWiredToPicker;
    procedure TestSelectNodeCachesCaptionAndFiresChange;
    procedure TestSelectSameNodeDoesNotRefire;
    procedure TestClearSelectionEmptiesTextAndFires;
    procedure TestTextIsCachedUntilUpdateText;
    procedure TestPickNodeCommits;
    procedure TestDropSizeFollowsFieldWidthAndMetric;
    procedure TestDropHeightPropertyBeatsMetric;
    procedure TestDropWidthPropertyBeatsFieldWidth;
    procedure TestDropSizeScalesWithPPI;
    procedure TestSyncTreeSeedsFocusFromSelection;
    procedure TestSyncTreeNilClearsTreeSelection;
    procedure TestFieldPaintsThemeBackground;
    procedure TestUndefinedComboKeyPaintsNothing;
    procedure TestHintUsesTyTextHintInk;
    procedure TestHintFallsBackToFieldInkWithoutHintColour;
  end;

implementation

type
  { Reaches the protected paint + open-time seams. Opening the REAL popup is not a headless
    act (it shows a window), so the two halves the rules live in — DropDownSize and
    SyncTreeToSelection — are exercised directly, exactly as test.datetimepicker drives its
    calendar handlers instead of its dropdown. }
  TSelectAccess = class(TTyTreeSelect)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SyncTree;
  end;

function TSelectAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TSelectAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TSelectAccess.SyncTree;
begin
  SyncTreeToSelection;
end;

{ ── pure rules ───────────────────────────────────────────────────────────────── }

procedure TTyTreeSelectRulesTest.TestTextBandIsPaddedField;
var
  L: TTyTreeSelectLayout;
begin
  // 145x26 field, pad 4 all round, an 18px chevron zone: the text band is the field inset
  // by its padding, stopping at the zone.
  L := TyTreeSelectFieldLayout(145, 26, 4, 4, 4, 4, 18);
  AssertEquals('text starts at the left padding', 4, L.TextRect.Left);
  AssertEquals('text stops at the chevron zone', 127, L.TextRect.Right);
  AssertEquals('text band top = top padding', 4, L.TextRect.Top);
  AssertEquals('text band bottom = height - bottom padding', 22, L.TextRect.Bottom);
end;

procedure TTyTreeSelectRulesTest.TestButtonHugsRightEdgeFullHeight;
var
  L: TTyTreeSelectLayout;
begin
  L := TyTreeSelectFieldLayout(145, 26, 4, 4, 4, 4, 18);
  AssertEquals('zone left = width - its own width', 127, L.ButtonRect.Left);
  AssertEquals('zone right = the field edge', 145, L.ButtonRect.Right);
  // Full height, NOT inset by padding: the chevron centres itself in the zone.
  AssertEquals('zone spans the full height (top)', 0, L.ButtonRect.Top);
  AssertEquals('zone spans the full height (bottom)', 26, L.ButtonRect.Bottom);
end;

procedure TTyTreeSelectRulesTest.TestWideButtonOverridesRightPadding;
var
  L: TTyTreeSelectLayout;
begin
  // The zone is the right gutter: a 40px zone stops the text at 105, not at 145-4=141.
  L := TyTreeSelectFieldLayout(145, 26, 4, 4, 4, 4, 40);
  AssertEquals('text stops at the zone, not at the padding', 105, L.TextRect.Right);
  AssertEquals('zone took its full width', 105, L.ButtonRect.Left);
end;

procedure TTyTreeSelectRulesTest.TestNoButtonHonoursRightPadding;
var
  L: TTyTreeSelectLayout;
begin
  // No zone (width 0): now the themed right padding is what stops the text.
  L := TyTreeSelectFieldLayout(145, 26, 4, 4, 4, 4, 0);
  AssertEquals('no zone drawn', 0, L.ButtonRect.Right - L.ButtonRect.Left);
  AssertEquals('text stops at the right padding', 141, L.TextRect.Right);
end;

procedure TTyTreeSelectRulesTest.TestNarrowFieldKeepsButtonDropsText;
var
  L: TTyTreeSelectLayout;
begin
  // 12px wide, an 18px zone: the chevron is the affordance that says "this drops", so it
  // keeps what there is and the text collapses.
  L := TyTreeSelectFieldLayout(12, 26, 4, 4, 4, 4, 18);
  AssertEquals('zone clamped to the left edge', 0, L.ButtonRect.Left);
  AssertEquals('zone clamped to the field edge', 12, L.ButtonRect.Right);
  AssertEquals('text dropped', 0, L.TextRect.Right - L.TextRect.Left);
end;

procedure TTyTreeSelectRulesTest.TestPaddingEatsWholeField;
var
  L: TTyTreeSelectLayout;
begin
  // Padding wider than what the zone leaves: no text band, never an inverted one — and the
  // chevron survives, because a field you cannot drop is worse than a field with no text.
  L := TyTreeSelectFieldLayout(30, 26, 20, 20, 20, 20, 18);
  AssertEquals('no text', 0, L.TextRect.Right - L.TextRect.Left);
  AssertTrue('the chevron zone is still there', L.ButtonRect.Right > L.ButtonRect.Left);
end;

procedure TTyTreeSelectRulesTest.TestZeroSizeEmpty;
var
  L: TTyTreeSelectLayout;
begin
  L := TyTreeSelectFieldLayout(0, 26, 4, 4, 4, 4, 18);
  AssertEquals('zero width: no text', 0, L.TextRect.Right - L.TextRect.Left);
  AssertEquals('zero width: no zone', 0, L.ButtonRect.Right - L.ButtonRect.Left);
  L := TyTreeSelectFieldLayout(145, 0, 4, 4, 4, 4, 18);
  AssertEquals('zero height: no text', 0, L.TextRect.Right - L.TextRect.Left);
  AssertEquals('zero height: no zone', 0, L.ButtonRect.Right - L.ButtonRect.Left);
end;

procedure TTyTreeSelectRulesTest.TestDropWidthZeroFollowsField;
var
  S: TSize;
begin
  S := TyTreeSelectDropSize(145, 0, 0, 220);
  AssertEquals('a drop with no width of its own is as wide as the field', 145, S.cx);
end;

procedure TTyTreeSelectRulesTest.TestDropWidthOverridesField;
var
  S: TSize;
begin
  S := TyTreeSelectDropSize(145, 300, 0, 220);
  AssertEquals('a named width wins', 300, S.cx);
end;

procedure TTyTreeSelectRulesTest.TestDropHeightZeroTakesDefault;
var
  S: TSize;
begin
  S := TyTreeSelectDropSize(145, 0, 0, 220);
  AssertEquals('a drop with no height of its own takes the theme default', 220, S.cy);
end;

procedure TTyTreeSelectRulesTest.TestDropHeightOverridesDefault;
var
  S: TSize;
begin
  S := TyTreeSelectDropSize(145, 0, 180, 220);
  AssertEquals('a named height wins over the theme default', 180, S.cy);
end;

procedure TTyTreeSelectRulesTest.TestDropSizeFloorsAtOne;
var
  S: TSize;
begin
  // A zero-width field (or a theme metric of 0) must still be a window, not a slit.
  S := TyTreeSelectDropSize(0, 0, 0, 0);
  AssertEquals('width floors at 1', 1, S.cx);
  AssertEquals('height floors at 1', 1, S.cy);
end;

procedure TTyTreeSelectRulesTest.TestFieldTextIsNodeCaption;
var
  isHint: Boolean;
begin
  AssertEquals('a selection shows its caption', 'Engineering',
    TyTreeSelectFieldText(True, 'Engineering', 'pick one…', isHint));
  AssertFalse('and it is not the hint', isHint);
end;

procedure TTyTreeSelectRulesTest.TestSelectedBlankCaptionIsNotHint;
var
  isHint: Boolean;
begin
  // The rule that separates this from TTyEdit.TextHint: a node with a blank caption is
  // still a CHOSEN node, so the field shows nothing rather than lying with "pick one…".
  AssertEquals('a blank caption shows blank', '',
    TyTreeSelectFieldText(True, '', 'pick one…', isHint));
  AssertFalse('the hint does not come back for a selected node', isHint);
end;

procedure TTyTreeSelectRulesTest.TestNoSelectionShowsHint;
var
  isHint: Boolean;
begin
  AssertEquals('no selection shows the hint', 'pick one…',
    TyTreeSelectFieldText(False, 'stale', 'pick one…', isHint));
  AssertTrue('flagged as the hint, so it inks dimly', isHint);
end;

procedure TTyTreeSelectRulesTest.TestNoSelectionNoHintIsEmpty;
var
  isHint: Boolean;
begin
  AssertEquals('nothing to say', '', TyTreeSelectFieldText(False, '', '', isHint));
  AssertFalse('an empty hint is not a hint (nothing is drawn dimly)', isHint);
end;

procedure TTyTreeSelectRulesTest.TestCommitPartsMatchTreeSelectionRule;
begin
  // The parts the TREE selects on always commit...
  AssertTrue('the label commits', TyTreeSelectCommitsOn(hpLabel, False, False));
  AssertTrue('the image commits', TyTreeSelectCommitsOn(hpImage, False, False));
  // ...and the parts that own their own gesture never do. Expanding a branch to look
  // inside it must not choose it and slam the drop shut.
  AssertFalse('the expander does not commit', TyTreeSelectCommitsOn(hpButton, False, False));
  AssertFalse('the expander does not commit on a full-row tree either',
    TyTreeSelectCommitsOn(hpButton, True, False));
  AssertFalse('the checkbox does not commit', TyTreeSelectCommitsOn(hpCheckBox, True, False));
  AssertFalse('empty space commits nothing', TyTreeSelectCommitsOn(hpNowhere, True, False));
  AssertFalse('the header commits nothing', TyTreeSelectCommitsOn(hpHeaderSection, True, False));
end;

procedure TTyTreeSelectRulesTest.TestIndentCommitsOnlyOnFullRowSelect;
begin
  // Adversarial-review finding (CONFIRMED): the commit rule must MIRROR what the tree selects on
  // an indent-strip click, else the field refuses a node the tree highlighted. The tree selects
  // on hpIndent when full-row is on OR when it is SINGLE-select.
  // Multi-select, no full-row: the indent strip does NOT select, so it must not commit.
  AssertFalse('multi-select + no full-row: indent does not commit',
    TyTreeSelectCommitsOn(hpIndent, False, True));
  // Full-row: the indent strip selects -> commits (in either select mode).
  AssertTrue('full-row: indent commits',
    TyTreeSelectCommitsOn(hpIndent, True, True));
  AssertTrue('full-row commits in single-select too',
    TyTreeSelectCommitsOn(hpIndent, True, False));
  // SINGLE-select, no full-row: the tree STILL selects on indent (its MouseDown selects any node
  // part), so the field must commit — the bug was refusing exactly this.
  AssertTrue('single-select: indent commits even without full-row',
    TyTreeSelectCommitsOn(hpIndent, False, False));
end;

{ ── control ──────────────────────────────────────────────────────────────────── }

procedure TTyTreeSelectControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FCaptions := TStringList.Create;
  FCaptions.Add('Engineering');
  FCaptions.Add('Sales');
  FChanged := 0;
end;

procedure TTyTreeSelectControlTest.TearDown;
begin
  FForm.Free;
  FCaptions.Free;
  FCtl.Free;
end;

procedure TTyTreeSelectControlTest.HandleChange(Sender: TObject);
begin
  Inc(FChanged);
end;

procedure TTyTreeSelectControlTest.HandleGetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var Text: string);
var
  idx: Integer;
begin
  Text := '';
  if Node = nil then Exit;
  idx := PInteger(Sender.GetNodeData(Node))^;
  if (idx >= 0) and (idx < FCaptions.Count) then
    Text := FCaptions[idx];
end;

{ A picker over a two-node tree ('Engineering', 'Sales'), themed, at 96 PPI and at the
  control's own default size. The node data is an index into FCaptions, so a test can change
  what the tree ANSWERS for a node without rebuilding anything. }
type
  THostForm = class(TForm)   // a streamable root for the Items round-trip test
  published
    TSel: TTyTreeSelect;
  end;

function MakeSelect(AOwner: TForm; ACtl: TTyStyleController;
  AGetText: TTyTreeGetTextEvent; out n0, n1: PTyTreeNode): TSelectAccess;
begin
  Result := TSelectAccess.Create(AOwner);
  Result.Parent := AOwner;
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 145, 26);
  // NodeDataSize governs the allocation stride, so it must be set BEFORE any AddChild.
  Result.Tree.NodeDataSize := SizeOf(Integer);
  Result.Tree.OnGetText := AGetText;
  n0 := Result.Tree.AddChild(nil);
  n1 := Result.Tree.AddChild(nil);
  PInteger(Result.Tree.GetNodeData(n0))^ := 0;
  PInteger(Result.Tree.GetNodeData(n1))^ := 1;
end;

procedure TTyTreeSelectControlTest.TestItemsForwardToTheDropTree;
var
  TS: TTyTreeSelect;
  a: TTyTreeNodeItem;
begin
  { The published Items forward to the embedded tree (unnamed, so it streams nothing of
    its own): filling them at design time is how the dropdown gets its tree without
    code. Item mode and the virtual API stay mutually exclusive -- the tree's gates. }
  TS := TTyTreeSelect.Create(FForm);
  try
    a := TS.Items.AddChild(nil, 'A');
    TS.Items.AddChild(a, 'a1');
    AssertEquals('the drop tree materialised the items', 2, Integer(TS.Tree.RootNodeCount) + 1);
    AssertEquals('same collection the tree owns', 2, TS.Tree.Items.Count);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestItemsSurviveStreaming;
var
  Src, Dst: THostForm;
  MS: TMemoryStream;
  DstTS: TTyTreeSelect;
  a: TTyTreeNodeItem;
begin
  { The forwarding property must have a real setter: FPC's writer silently SKIPS a
    published collection without one (the TTyHeader.Columns lesson, 7d2c03d). }
  Src := THostForm.CreateNew(nil);
  Dst := THostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'HostForm9';
    Src.TSel := TTyTreeSelect.Create(Src);
    Src.TSel.Name := 'TSel';
    Src.TSel.Parent := Src;
    a := Src.TSel.Items.AddChild(nil, 'A');
    Src.TSel.Items.AddChild(a, 'a1');
    MS.WriteComponent(Src);

    MS.Position := 0;
    MS.ReadComponent(Dst);
    DstTS := Dst.FindComponent('TSel') as TTyTreeSelect;
    AssertEquals('the designed tree streamed', 2, DstTS.Items.Count);
    AssertEquals('with its caption', 'A', DstTS.Items[0].Text);
    AssertEquals('and its depth', 1, DstTS.Items[1].Level);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestTypeKeyIsComboBox;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  // Deliberately the COMBO's key, not one of its own: this is a combo field with a different
  // drop, so every skin themes it the day it lands and it can never be unstyled.
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    AssertEquals('TyComboBox', TS.StyleTypeKey);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestDefaults;
var
  TS: TTyTreeSelect;
begin
  TS := TTyTreeSelect.Create(FForm);
  try
    AssertNull('nothing selected', TS.SelectedNode);
    AssertEquals('no text', '', TS.Text);
    AssertEquals('no hint', '', TS.TextHint);
    AssertEquals('drop width follows the field', 0, TS.DropDownWidth);
    AssertEquals('drop height follows the theme', 0, TS.DropDownHeight);
    AssertTrue('focusable', TS.TabStop);
    AssertFalse('not dropped down', TS.DroppedDown);
    AssertEquals('combo drop width', 145, TS.Width);
    AssertEquals('combo drop height', 26, TS.Height);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestTreeIsWiredToPicker;
var
  TS: TTyTreeSelect;
begin
  TS := TTyTreeSelect.Create(FForm);
  try
    // The tree exists from the constructor (the app populates it long before any drop) and
    // it is the picker's own subclass, wired back — that override IS the commit path.
    AssertNotNull('the tree exists without ever dropping', TS.Tree);
    AssertTrue('it is the picker tree', TS.Tree is TTyTreeSelectTree);
    AssertSame('and it points back at the field', TS, TTyTreeSelectTree(TS.Tree).Picker);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestSelectNodeCachesCaptionAndFiresChange;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.OnChange := @HandleChange;
    TS.SelectedNode := n1;
    AssertEquals('OnChange fired once', 1, FChanged);
    AssertSame('the pick is the node', n1, TS.SelectedNode);
    // Read through the TREE's OnGetText — the same path that paints the row.
    AssertEquals('the field shows the node caption', 'Sales', TS.Text);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestSelectSameNodeDoesNotRefire;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.SelectedNode := n0;
    TS.OnChange := @HandleChange;
    TS.SelectedNode := n0;
    AssertEquals('re-selecting the same node is not a change', 0, FChanged);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestClearSelectionEmptiesTextAndFires;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.SelectedNode := n0;
    TS.OnChange := @HandleChange;
    TS.ClearSelection;
    AssertEquals('OnChange fired', 1, FChanged);
    AssertNull('nothing selected', TS.SelectedNode);
    AssertEquals('and the field says nothing', '', TS.Text);
    TS.ClearSelection;
    AssertEquals('clearing an empty field is not a change', 1, FChanged);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestTextIsCachedUntilUpdateText;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  // The caption is cached at selection time — the field must never deref the node while
  // painting (node pointers are the app's to free). So a caption that changes behind the
  // control's back does NOT appear until it is told, and then it does.
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.SelectedNode := n0;
    AssertEquals('cached at selection', 'Engineering', TS.Text);
    FCaptions[0] := 'R&D';
    AssertEquals('a caption changed behind our back does not leak in', 'Engineering', TS.Text);
    TS.OnChange := @HandleChange;
    TS.UpdateText;
    AssertEquals('UpdateText re-reads it', 'R&D', TS.Text);
    AssertEquals('a relabel is not a value change', 0, FChanged);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestPickNodeCommits;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  // What a click / Enter in the popup runs. With no window open it must still commit (and
  // queue no close) rather than depend on the popup existing.
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.OnChange := @HandleChange;
    TS.PickNode(n1);
    AssertSame('the pick took', n1, TS.SelectedNode);
    AssertEquals('the field shows it', 'Sales', TS.Text);
    AssertEquals('OnChange fired once', 1, FChanged);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestDropSizeFollowsFieldWidthAndMetric;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
  S: TSize;
begin
  // --treeselect-drop-height is a skin-tunable metric: a theme that sets it moves the drop,
  // proving the height is not baked into the control.
  FCtl.LoadThemeCss(':root { --treeselect-drop-height: 300px; }' +
    'TyComboBox { background: #FFFFFF; color: #111111; padding: 4px; }');
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    S := TS.DropDownSize;
    AssertEquals('as wide as the field', 145, S.cx);
    AssertEquals('as tall as the theme says', 300, S.cy);
    TS.SetBounds(0, 0, 260, 26);
    AssertEquals('a wider field drops a wider tree', 260, TS.DropDownSize.cx);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestDropHeightPropertyBeatsMetric;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  FCtl.LoadThemeCss(':root { --treeselect-drop-height: 300px; }' +
    'TyComboBox { background: #FFFFFF; color: #111111; padding: 4px; }');
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.DropDownHeight := 180;
    AssertEquals('the app''s height wins over the theme default', 180, TS.DropDownSize.cy);
    TS.DropDownHeight := -5;
    AssertEquals('a negative height is normalised to "follow the theme"', 0, TS.DropDownHeight);
    AssertEquals('...and does', 300, TS.DropDownSize.cy);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestDropWidthPropertyBeatsFieldWidth;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  FCtl.LoadThemeCss('TyComboBox { background: #FFFFFF; color: #111111; padding: 4px; }');
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.DropDownWidth := 320;   // a deep hierarchy needs more room than its field
    AssertEquals('the app''s width wins', 320, TS.DropDownSize.cx);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestDropSizeScalesWithPPI;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  // The knobs and the metric are LOGICAL px; the popup is asked for DEVICE px.
  FCtl.LoadThemeCss(':root { --treeselect-drop-height: 300px; }' +
    'TyComboBox { background: #FFFFFF; color: #111111; padding: 4px; }');
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.Font.PixelsPerInch := 192;
    AssertEquals('the themed height doubles at 2x', 600, TS.DropDownSize.cy);
    TS.DropDownHeight := 180;
    AssertEquals('and so does the app''s', 360, TS.DropDownSize.cy);
    // Width follows the field, which is ALREADY device px — it must not be scaled twice.
    AssertEquals('the field width is not re-scaled', 145, TS.DropDownSize.cx);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestSyncTreeSeedsFocusFromSelection;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  // Every open seeds the tree from the field, so the drop opens ON the current value
  // however it was set (here: programmatically, which does not touch the tree).
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.SelectedNode := n1;
    AssertNull('a programmatic pick does not touch the tree', TS.Tree.FocusedNode);
    TS.SyncTree;
    AssertSame('opening focuses the pick', n1, TS.Tree.FocusedNode);
    AssertTrue('and highlights it', TS.Tree.NodeSelected[n1]);
  finally
    TS.Free;
  end;
end;

procedure TTyTreeSelectControlTest.TestSyncTreeNilClearsTreeSelection;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
begin
  // The popup must not highlight a row the field does not name.
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.SelectedNode := n1;
    TS.SyncTree;
    TS.ClearSelection;
    TS.SyncTree;
    AssertFalse('the old row is no longer highlighted', TS.Tree.NodeSelected[n1]);
    AssertEquals('nothing is selected in the tree', 0, TS.Tree.SelectedCount);
  finally
    TS.Free;
  end;
end;

{ TestFieldPaintsThemeBackground
  Theme: a strongly blue TyComboBox fill. Probe the field's centre band and assert it is the
  themed fill — i.e. the field paints from the token, not from an LCL colour. }
procedure TTyTreeSelectControlTest.TestFieldPaintsThemeBackground;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss('TyComboBox { background: #3B82F6; color: #FFFFFF; ' +
    'border-radius: 4px; padding: 4px; font-size: 12px; }');
  Bmp := TBitmap.Create;
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.SelectedNode := n0;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(145, 26);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 145, 26);
    TS.RenderTo(Bmp.Canvas, Rect(0, 0, 145, 26), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Well inside the field, clear of the rounded corners and of the caption glyphs.
      Px := Reread.GetPixel(2, 13);
      AssertTrue('field painted in the themed fill', (Px.blue > 180) and (Px.red < 120));
    finally
      Reread.Free;
    end;
  finally
    TS.Free;
    Bmp.Free;
  end;
end;

{ TestUndefinedComboKeyPaintsNothing
  A rule FOR the key but WITHOUT a background suppresses the whole built-in layer for it
  (TTyStyleModel.UserHasTypeKey), so the field genuinely resolves no fill. It must then draw
  nothing at all rather than invent one — the canvas is untouched. }
procedure TTyTreeSelectControlTest.TestUndefinedComboKeyPaintsNothing;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss('TyComboBox { color: #111111; padding: 4px; font-size: 12px; }');
  Bmp := TBitmap.Create;
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.SelectedNode := n0;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(145, 26);
    Bmp.Canvas.Brush.Color := clFuchsia;   // a colour the control could never paint
    Bmp.Canvas.FillRect(0, 0, 145, 26);
    TS.RenderTo(Bmp.Canvas, Rect(0, 0, 145, 26), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel(72, 13);
      AssertTrue('nothing was painted over the canvas',
        (Px.red > 200) and (Px.blue > 200) and (Px.green < 60));
    finally
      Reread.Free;
    end;
  finally
    TS.Free;
    Bmp.Free;
  end;
end;

{ TestHintUsesTyTextHintInk
  White field, white field ink, GREEN TyTextHint: any green pixel in the text band can only
  be the hint drawn in the library-wide hint key's colour. }
procedure TTyTreeSelectControlTest.TestHintUsesTyTextHintInk;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  x, y: Integer;
  found: Boolean;
begin
  FCtl.LoadThemeCss(
    'TyComboBox { background: #FFFFFF; color: #FFFFFF; padding: 4px; font-size: 12px; }' +
    'TyTextHint { color: #10B981; }');
  Bmp := TBitmap.Create;
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.TextHint := 'pick a department';   // and NOTHING selected
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(145, 26);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 145, 26);
    TS.RenderTo(Bmp.Canvas, Rect(0, 0, 145, 26), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      found := False;
      for y := 4 to 21 do
        for x := 4 to 126 do   // the text band only: the chevron zone starts at 127
        begin
          Px := Reread.GetPixel(x, y);
          if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
          begin
            found := True;
            Break;
          end;
        end;
      AssertTrue('the hint drew in the TyTextHint ink', found);
    finally
      Reread.Free;
    end;
  finally
    TS.Free;
    Bmp.Free;
  end;
end;

{ TestHintFallsBackToFieldInkWithoutHintColour
  A rule FOR TyTextHint without a `color` suppresses the built-in one, so the hint key
  resolves NO ink. The hint must then take the FIELD's ink (inherit) — never a hard-coded
  grey, and never vanish. Field ink is green here, so green in the text band proves it. }
procedure TTyTreeSelectControlTest.TestHintFallsBackToFieldInkWithoutHintColour;
var
  TS: TSelectAccess;
  n0, n1: PTyTreeNode;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  x, y: Integer;
  found: Boolean;
begin
  FCtl.LoadThemeCss(
    'TyComboBox { background: #FFFFFF; color: #10B981; padding: 4px; font-size: 12px; }' +
    'TyTextHint { font-size: 12px; }');
  Bmp := TBitmap.Create;
  TS := MakeSelect(FForm, FCtl, @HandleGetText, n0, n1);
  try
    TS.TextHint := 'pick a department';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(145, 26);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 145, 26);
    TS.RenderTo(Bmp.Canvas, Rect(0, 0, 145, 26), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      found := False;
      for y := 4 to 21 do
        for x := 4 to 126 do
        begin
          Px := Reread.GetPixel(x, y);
          if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
          begin
            found := True;
            Break;
          end;
        end;
      AssertTrue('the hint fell back to the field ink', found);
    finally
      Reread.Free;
    end;
  finally
    TS.Free;
    Bmp.Free;
  end;
end;

initialization
  RegisterClasses([TTyTreeSelect]);   // the streaming reader instantiates by class name
  RegisterTest(TTyTreeSelectRulesTest);
  RegisterTest(TTyTreeSelectControlTest);
end.
