unit test.toolgrouppanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  tyControls.Base, tyControls.Types, tyControls.Button, tyControls.ToolGroupPanel;
type
  TToolGroupPanelTest = class(TTestCase)
  private
    FClicked: Integer;
    procedure HandleClick(Sender: TObject);
  published
    // Pure flow-layout geometry (TyToolFlowRects)
    procedure TestFlowSingleRowNoWrap;
    procedure TestFlowSpacingBetweenButtons;
    procedure TestFlowWrapsToNewRow;
    procedure TestFlowRowHeightUniform;
    procedure TestFlowFirstOnRowNeverWraps;
    procedure TestFlowRespectsClientOrigin;
    procedure TestFlowEmpty;
    // Control behaviour
    procedure TestTypeKeyIsToolGroupPanel;
    procedure TestDefaultsAndPublished;
    procedure TestIsDesignerContainer;
    procedure TestAddButtonCreatesChild;
    procedure TestAddButtonWiresOnClick;
    procedure TestAddButtonGhostStyleClass;
    procedure TestAddedButtonsAreDesignVisible;
    procedure TestSpacingButtonHeightRoundTrip;
    procedure TestRelayoutSurvivesResize;
  end;
implementation

procedure TToolGroupPanelTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

{ ---- pure geometry ---------------------------------------------------------- }

procedure TToolGroupPanelTest.TestFlowSingleRowNoWrap;
var
  sizes: array[0..2] of TSize;
  r: TTyRectArray;
begin
  // 3 x 40px-wide buttons in a wide client -> one row, left-to-right.
  sizes[0].cx := 40; sizes[0].cy := 26;
  sizes[1].cx := 40; sizes[1].cy := 26;
  sizes[2].cx := 40; sizes[2].cy := 26;
  r := TyToolFlowRects(Rect(0, 0, 400, 100), sizes, 4, 26);
  AssertEquals('count', 3, Length(r));
  AssertEquals('b0 left', 0, r[0].Left);
  AssertEquals('b0 right', 40, r[0].Right);
  AssertEquals('b1 left = 40 + spacing', 44, r[1].Left);
  AssertEquals('b2 left = 88 + spacing', 88, r[2].Left);
  AssertEquals('all same top', r[0].Top, r[2].Top);
end;

procedure TToolGroupPanelTest.TestFlowSpacingBetweenButtons;
var
  sizes: array[0..1] of TSize;
  r: TTyRectArray;
begin
  sizes[0].cx := 30; sizes[0].cy := 26;
  sizes[1].cx := 30; sizes[1].cy := 26;
  r := TyToolFlowRects(Rect(0, 0, 400, 100), sizes, 10, 26);
  // gap between b0.Right and b1.Left must equal the spacing.
  AssertEquals('spacing gap', 10, r[1].Left - r[0].Right);
end;

procedure TToolGroupPanelTest.TestFlowWrapsToNewRow;
var
  sizes: array[0..2] of TSize;
  r: TTyRectArray;
begin
  // client width 100; two 60px buttons don't fit on one row -> b1 wraps.
  sizes[0].cx := 60; sizes[0].cy := 26;
  sizes[1].cx := 60; sizes[1].cy := 26;
  sizes[2].cx := 60; sizes[2].cy := 26;
  r := TyToolFlowRects(Rect(0, 0, 100, 200), sizes, 4, 26);
  AssertEquals('b0 on row 0', 0, r[0].Top);
  AssertEquals('b1 wraps to row 1', 26 + 4, r[1].Top);
  AssertEquals('b1 back at left', 0, r[1].Left);
  AssertEquals('b2 wraps to row 2', 2 * (26 + 4), r[2].Top);
end;

procedure TToolGroupPanelTest.TestFlowRowHeightUniform;
var
  sizes: array[0..1] of TSize;
  r: TTyRectArray;
begin
  // varying cy is ignored; every rect is AButtonHeight tall.
  sizes[0].cx := 40; sizes[0].cy := 10;
  sizes[1].cx := 40; sizes[1].cy := 99;
  r := TyToolFlowRects(Rect(0, 0, 400, 100), sizes, 4, 30);
  AssertEquals('b0 height forced to AButtonHeight', 30, r[0].Bottom - r[0].Top);
  AssertEquals('b1 height forced to AButtonHeight', 30, r[1].Bottom - r[1].Top);
end;

procedure TToolGroupPanelTest.TestFlowFirstOnRowNeverWraps;
var
  sizes: array[0..0] of TSize;
  r: TTyRectArray;
begin
  // A single button wider than the whole client still gets a rect on row 0 (no infinite
  // wrap / no empty rect) — the first button on a row never wraps.
  sizes[0].cx := 500; sizes[0].cy := 26;
  r := TyToolFlowRects(Rect(0, 0, 100, 200), sizes, 4, 26);
  AssertEquals('over-wide lone button stays on row 0', 0, r[0].Top);
  AssertEquals('over-wide lone button starts at left', 0, r[0].Left);
  AssertEquals('over-wide lone button keeps its width', 500, r[0].Right - r[0].Left);
end;

procedure TToolGroupPanelTest.TestFlowRespectsClientOrigin;
var
  sizes: array[0..1] of TSize;
  r: TTyRectArray;
begin
  // A client rect inset below a caption band (Top=16, Left=8): the first button starts
  // at that origin, not at (0,0), and wrapping returns to the client's Left.
  sizes[0].cx := 70; sizes[0].cy := 26;
  sizes[1].cx := 70; sizes[1].cy := 26;
  r := TyToolFlowRects(Rect(8, 16, 100, 200), sizes, 4, 26);
  AssertEquals('b0 left = client left', 8, r[0].Left);
  AssertEquals('b0 top = client top', 16, r[0].Top);
  // 8 + 70 = 78; next 70 would reach 148 > 100 -> wrap.
  AssertEquals('b1 wraps back to client left', 8, r[1].Left);
  AssertEquals('b1 on second row (client top + h + spacing)', 16 + 26 + 4, r[1].Top);
end;

procedure TToolGroupPanelTest.TestFlowEmpty;
var
  sizes: array of TSize;
  r: TTyRectArray;
begin
  SetLength(sizes, 0);
  r := TyToolFlowRects(Rect(0, 0, 100, 100), sizes, 4, 26);
  AssertEquals('empty -> zero rects', 0, Length(r));
end;

{ ---- control behaviour ------------------------------------------------------ }

procedure TToolGroupPanelTest.TestTypeKeyIsToolGroupPanel;
var P: TTyToolGroupPanel;
begin
  P := TTyToolGroupPanel.Create(nil);
  try
    // Its own token: a ribbon-style tool group is not a form group box, and the design
    // system already styles TyRibbonGroup unlike TyGroupBox.
    AssertEquals('TyToolGroupPanel', (P as ITyStyleable).GetStyleTypeKey);
  finally
    P.Free;
  end;
end;

procedure TToolGroupPanelTest.TestDefaultsAndPublished;
var P: TTyToolGroupPanel;
begin
  P := TTyToolGroupPanel.Create(nil);
  try
    AssertEquals('default Spacing', 4, P.Spacing);
    AssertEquals('default ButtonHeight', 26, P.ButtonHeight);
    AssertTrue('Spacing published', IsPublishedProp(P, 'Spacing'));
    AssertTrue('ButtonHeight published', IsPublishedProp(P, 'ButtonHeight'));
    AssertTrue('Caption published', IsPublishedProp(P, 'Caption'));
    AssertTrue('Alignment published', IsPublishedProp(P, 'Alignment'));
  finally
    P.Free;
  end;
end;

procedure TToolGroupPanelTest.TestIsDesignerContainer;
var P: TTyToolGroupPanel;
begin
  P := TTyToolGroupPanel.Create(nil);
  try
    // Inherited from TTyGroupBox — the IDE drops child controls INTO the panel.
    AssertTrue('accepts child controls', csAcceptsControls in P.ControlStyle);
  finally
    P.Free;
  end;
end;

procedure TToolGroupPanelTest.TestAddButtonCreatesChild;
var
  F: TForm; P: TTyToolGroupPanel; B0, B1: TTyButton;
begin
  F := TForm.CreateNew(nil);
  try
    P := TTyToolGroupPanel.Create(F);
    P.Parent := F;
    P.SetBounds(0, 0, 220, 92);
    AssertEquals('starts with no children', 0, P.ControlCount);
    B0 := P.AddButton('Cut');
    AssertNotNull('AddButton returns a button', B0);
    AssertSame('child parent is the panel', P, B0.Parent);
    AssertEquals('one child after first AddButton', 1, P.ControlCount);
    AssertEquals('caption set', 'Cut', B0.Caption);
    B1 := P.AddButton('Copy');
    AssertEquals('two children after second AddButton', 2, P.ControlCount);
    AssertTrue('distinct buttons', B0 <> B1);
  finally
    F.Free;
  end;
end;

procedure TToolGroupPanelTest.TestAddButtonWiresOnClick;
var
  F: TForm; P: TTyToolGroupPanel; B: TTyButton;
begin
  FClicked := 0;
  F := TForm.CreateNew(nil);
  try
    P := TTyToolGroupPanel.Create(F);
    P.Parent := F;
    B := P.AddButton('Go', @HandleClick);
    B.Click;
    AssertEquals('OnClick wired via AddButton', 1, FClicked);
  finally
    F.Free;
  end;
end;

procedure TToolGroupPanelTest.TestAddButtonGhostStyleClass;
var
  F: TForm; P: TTyToolGroupPanel; B: TTyButton;
begin
  F := TForm.CreateNew(nil);
  try
    P := TTyToolGroupPanel.Create(F);
    P.Parent := F;
    B := P.AddButton('Paste');
    AssertEquals('ghost style class', 'ghost', B.StyleClass);
  finally
    F.Free;
  end;
end;

procedure TToolGroupPanelTest.TestAddedButtonsAreDesignVisible;
var
  F: TForm; P: TTyToolGroupPanel; B: TTyButton;
begin
  // Buttons added via AddButton are the USER's controls, NOT auto-populated helpers —
  // they must NOT be marked csNoDesignVisible (a real container).
  F := TForm.CreateNew(nil);
  try
    P := TTyToolGroupPanel.Create(F);
    P.Parent := F;
    B := P.AddButton('Tool');
    AssertFalse('added button is design-visible (not a hidden helper)',
      csNoDesignVisible in B.ControlStyle);
  finally
    F.Free;
  end;
end;

procedure TToolGroupPanelTest.TestSpacingButtonHeightRoundTrip;
var P: TTyToolGroupPanel;
begin
  P := TTyToolGroupPanel.Create(nil);
  try
    P.Spacing := 12;
    AssertEquals('Spacing round-trips', 12, P.Spacing);
    P.ButtonHeight := 40;
    AssertEquals('ButtonHeight round-trips', 40, P.ButtonHeight);
    // Clamps to sane floors.
    P.Spacing := -5;
    AssertEquals('Spacing clamps to 0', 0, P.Spacing);
    P.ButtonHeight := 0;
    AssertEquals('ButtonHeight clamps to >= 1', 1, P.ButtonHeight);
  finally
    P.Free;
  end;
end;

procedure TToolGroupPanelTest.TestRelayoutSurvivesResize;
var
  F: TForm; P: TTyToolGroupPanel; i: Integer;
begin
  // Adding buttons then resizing narrow (forcing a wrap) then wide again must not crash
  // and must keep every child parented to the panel.
  F := TForm.CreateNew(nil);
  try
    P := TTyToolGroupPanel.Create(F);
    P.Parent := F;
    P.SetBounds(0, 0, 260, 92);
    P.AddButton('Bold');
    P.AddButton('Italic');
    P.AddButton('Underline');
    P.AddButton('Strike');
    AssertEquals('four children', 4, P.ControlCount);
    P.Width := 90;    // narrow -> wrap
    P.Width := 300;   // wide again -> unwrap
    P.Height := 60;
    for i := 0 to P.ControlCount - 1 do
      AssertSame('child still parented after resize', P, P.Controls[i].Parent);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TToolGroupPanelTest);
end.
