unit test.customclasses.p2;
{$mode objfpc}{$H+}

{ Custom-class split, phase 2 (containers, lists and grids). The same three kinds of test as
  test.customclasses.p1, on the same fixture and checks (TTyCustomClassesPhaseCase):

  * THIRD-PARTY MIMICS: a TTyCustomXxx descendant that publishes two properties of its own
    choosing -- it can be created (T-a), publishes exactly its LCL root's names plus the two
    (T-b), streams those two and not a property it left out (T-c), resolves the same theme
    type key as the library's final class (T-d), streams nothing from a fresh instance (T-e),
    and reaches a public property through a TTyCustomXxx reference (T-v).
  * DERIVED CONTROLS SEEN BY THEIR FAMILY: from 4.0 on a TTyShellTreeView is a
    TTyCustomTreeView but no longer a TTyTreeView; library code that meant "any tree" asks for
    the custom class, and each such check has a test that fails when it is put back.
  * CHECKS WIDENED FOR THIRD PARTIES: a host that accepts any TTyCustomXxx child (a grid
    panel's cells, a scroll box's viewport, a page control's sheets), proven with a mimic. }

interface

uses
  Classes, SysUtils, TypInfo, Controls, Forms, Graphics, fpcunit, testregistry,
  test.customclasses, test.customclasses.p1,
  tyControls.Base, tyControls.Panel, tyControls.GridPanel, tyControls.ScrollBox,
  tyControls.ScrollContent, tyControls.ControlBar, tyControls.CoolBar, tyControls.Button,
  tyControls.GroupBox, tyControls.RadioGroup, tyControls.CheckBox, tyControls.TabStrip,
  tyControls.TabSheet, tyControls.PageControl, tyControls.ListBox, tyControls.CheckListBox,
  tyControls.ComboBox, tyControls.CheckComboBox, tyControls.Transfer, tyControls.Cascader;

type
  TTyCustomClassesP2Test = class(TTyCustomClassesPhaseCase)
  private
    FChanges: Integer;
    procedure CountChange(Sender: TObject);
  published
    { Task 12: panels }
    procedure TestThirdPanel;
    procedure TestThirdGridPanel;
    procedure TestGridCellJoinsAThirdPartyGridPanel;
    procedure TestScrollBoxTakesAThirdPartyViewport;
    procedure TestThirdCoolBarBandsReachTheirHost;
    procedure TestScrollContentStreamsFromAFormFile;
    { Task 13: groups and decoration }
    procedure TestThirdGroupBox;
    procedure TestThirdRadioGroup;
    { Task 14: tabs }
    procedure TestThirdPageControl;
    procedure TestTabSheetJoinsAThirdPartyPageControl;
    procedure TestPageControlDropsAFreedThirdPartySheet;
    procedure TestPageControlHandsOutAThirdPartySheetAsItIs;
    procedure TestThirdTabSheetKeepsItsBoundsOutOfTheStream;
    { Task 15: list boxes }
    procedure TestThirdListBox;
    procedure TestThirdCheckListBox;
    procedure TestCheckComboPopupListTravelsTheWidenedApi;
    { Task 16: compound pickers }
    procedure TestThirdCascader;
    procedure TestThirdTransfer;
  end;

  { --- third-party mimics ------------------------------------------------------------ }

  TThirdPanel = class(TTyCustomPanel)
  published
    property Caption;
    property Alignment;
  end;

  TThirdGridPanel = class(TTyCustomGridPanel)
  published
    property ColumnCount;
    property RowCount;
  end;

  TThirdScrollContent = class(TTyCustomScrollContent)
  published
    property Align;
  end;

  TThirdCoolBar = class(TTyCustomCoolBar)
  published
    property Bands;
    property Vertical;
  end;

  TThirdGroupBox = class(TTyCustomGroupBox)
  published
    property Caption;
    property Alignment;
  end;

  { Items before ItemIndex: the index is read back against the items already there. }
  TThirdRadioGroup = class(TTyCustomRadioGroup)
  published
    property Items;
    property ItemIndex;
  end;

  TThirdPageControl = class(TTyCustomPageControl)
  published
    property ActivePageIndex;
    property TabPosition;
  end;

  TThirdTabSheet = class(TTyCustomTabSheet)
  published
    property Caption;
    property ImageIndex;
  end;

  TThirdListBox = class(TTyCustomListBox)
  published
    property Items;
    property ItemIndex;
  end;

  TThirdCheckListBox = class(TTyCustomCheckListBox)
  published
    property Items;
    property AllowGrayed;
  end;

  TThirdCascader = class(TTyCustomCascader)
  published
    property Nodes;
    property Separator;
  end;

  TThirdTransfer = class(TTyCustomTransfer)
  published
    property Items;
    property Selected;
  end;

implementation

type
  { WordWrap is protected on the custom panel (TCustomPanel keeps it protected); RenderTo is
    protected on every family. }
  TP2PanelCracker = class(TTyCustomPanel)
  public
    procedure SetWrap(AValue: Boolean);
    function WrapNow: Boolean;
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect);
  end;

  TP2GroupBoxCracker = class(TTyCustomGroupBox)
  public
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect);
  end;

  TP2ListBoxCracker = class(TTyCustomListBox)
  public
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect);
    function ItemKey: string;
  end;

  { CreatePopupList is protected: the list a check combo would drop. }
  TP2CheckComboCracker = class(TTyCustomCheckComboBox)
  public
    function MakePopupList: TTyCustomListBox;
  end;

  { ContentHost is protected: where the box actually puts its children. }
  TP2ScrollBoxCracker = class(TTyCustomScrollBox)
  public
    function Host: TWinControl;
  end;

procedure TP2PanelCracker.SetWrap(AValue: Boolean);
begin
  WordWrap := AValue;
end;

function TP2PanelCracker.WrapNow: Boolean;
begin
  Result := WordWrap;
end;

procedure TP2PanelCracker.DoRender(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderTo(ACanvas, ARect, 96);
end;

procedure TP2GroupBoxCracker.DoRender(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderTo(ACanvas, ARect, 96);
end;

procedure TP2ListBoxCracker.DoRender(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderTo(ACanvas, ARect, 96);
end;

function TP2ListBoxCracker.ItemKey: string;
begin
  Result := GetItemStyleTypeKey;
end;

function TP2CheckComboCracker.MakePopupList: TTyCustomListBox;
begin
  Result := CreatePopupList;
end;

function TP2ScrollBoxCracker.Host: TWinControl;
begin
  Result := ContentHost;
end;

procedure TTyCustomClassesP2Test.CountChange(Sender: TObject);
begin
  Inc(FChanges);
end;

{ ------------------------------------------------------------------ Task 12: panels }

procedure TTyCustomClassesP2Test.TestThirdPanel;
var
  third, back: TThirdPanel;
  own: TTyPanel;
  c: TTyCustomPanel;
  bmA, bmB: TBitmap;
  diff: string;
begin
  third := TThirdPanel.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(10, 10, 160, 40);
  CheckPublishesOnly(TThirdPanel, ['Caption', 'Alignment']);
  third.Caption := 'Panel';
  third.Alignment := taLeftJustify;
  TP2PanelCracker(third).SetWrap(True);
  CheckStreamText(third, ['Caption', 'Alignment'], 'WordWrap');
  back := TThirdPanel.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Caption round-trips', 'Panel', back.Caption);
  AssertTrue('T-c: Alignment round-trips', back.Alignment = taLeftJustify);
  AssertFalse('T-c: the unpublished WordWrap stayed at its default',
    TP2PanelCracker(back).WrapNow);
  { T-d: the frame and caption are drawn by the custom class, so the same caption, alignment
    and bounds are the same picture. }
  own := TTyPanel.Create(FForm);
  own.Parent := FForm;
  own.SetBounds(10, 60, 160, 40);
  own.Caption := 'Panel';
  own.Alignment := taLeftJustify;
  TP2PanelCracker(third).SetWrap(False);
  CheckSameTypeKey(third, own);
  bmA := NewSentinelBitmap(160, 40);
  bmB := NewSentinelBitmap(160, 40);
  try
    TP2PanelCracker(third).DoRender(bmA.Canvas, Rect(0, 0, 160, 40));
    TP2PanelCracker(own).DoRender(bmB.Canvas, Rect(0, 0, 160, 40));
    AssertTrue('T-d: the mimic paints exactly what TTyPanel paints: ' + diff,
      SameBitmaps(bmA, bmB, diff));
  finally
    bmA.Free;
    bmB.Free;
  end;
  CheckFreshDefaults(TThirdPanel, ['Alignment']);
  { T-v: Alignment is public (TCustomPanel); WordWrap is protected, hence the cracker. }
  c := third;
  c.Alignment := taRightJustify;
  AssertTrue('T-v', third.Alignment = taRightJustify);
end;

procedure TTyCustomClassesP2Test.TestThirdGridPanel;
var
  third, back: TThirdGridPanel;
  own: TTyGridPanel;
  c: TTyCustomGridPanel;
begin
  third := TThirdGridPanel.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(0, 0, 300, 200);
  CheckPublishesOnly(TThirdGridPanel, ['ColumnCount', 'RowCount']);
  third.ColumnCount := 3;
  third.RowCount := 4;
  third.Spacing := 9;
  CheckStreamText(third, ['ColumnCount', 'RowCount'], 'Spacing');
  back := TThirdGridPanel.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertEquals('T-c: ColumnCount round-trips', 3, back.ColumnCount);
  AssertEquals('T-c: RowCount round-trips', 4, back.RowCount);
  AssertEquals('T-c: the unpublished Spacing stayed at its default', 4, back.Spacing);
  AssertEquals('the mimic seats a cell per slot, as TTyGridPanel does', 12, third.CellCount);
  own := TTyGridPanel.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdGridPanel, ['ColumnCount', 'RowCount']);
  c := third;
  c.Spacing := 2;
  AssertEquals('T-v: Spacing is public through a TTyCustomGridPanel reference', 2, third.Spacing);
end;

{ S12-1. A grid cell parented to a third party's grid panel registers with it and is laid out
  in its slot. The cell asks `is TTyCustomGridPanel`; asking for TTyGridPanel left a mimic
  with no cells at all -- not even the 2x2 it seeds itself. }
procedure TTyCustomClassesP2Test.TestGridCellJoinsAThirdPartyGridPanel;
var
  grid: TThirdGridPanel;
  cell, seeded: TTyGridCell;
  before: Integer;
begin
  grid := TThirdGridPanel.Create(FForm);
  grid.Parent := FForm;
  grid.SetBounds(0, 0, 200, 100);
  AssertFalse('the mimic is no TTyGridPanel (or this proves nothing)', TObject(grid) is TTyGridPanel);
  AssertEquals('the mimic seated its own 2x2', 4, grid.CellCount);
  seeded := TTyGridCell(grid.Cells[1, 1]);
  AssertTrue('the (1,1) slot holds a cell', seeded <> nil);
  before := grid.CellCount;
  cell := TTyGridCell.Create(FForm);
  cell.Col := 1;
  cell.Row := 1;
  cell.Parent := grid;
  AssertEquals('the new cell registered with the third-party grid', before + 1, grid.CellCount);
  AssertTrue('and was laid out into the (1,1) slot',
    EqualRect(cell.BoundsRect, seeded.BoundsRect) and (cell.Width > 0));
end;

{ S12-2. A scroll box takes a third party's content control as its viewport: children placed
  on the box live in it. The box asks `is TTyCustomScrollContent`. }
procedure TTyCustomClassesP2Test.TestScrollBoxTakesAThirdPartyViewport;
var
  box: TTyScrollBox;
  view: TThirdScrollContent;
begin
  box := TTyScrollBox.Create(FForm);
  box.Parent := FForm;
  box.SetBounds(0, 0, 200, 150);
  AssertTrue('without a viewport the box hosts its own children',
    TP2ScrollBoxCracker(box).Host = box);
  view := TThirdScrollContent.Create(FForm);
  view.Parent := box;
  AssertTrue('the box adopts the third party''s viewport as its content host',
    TP2ScrollBoxCracker(box).Host = view);
end;

{ S12-3. A band edited through a third party's cool bar reaches the bar: the collection finds
  its owner as TTyCustomCoolBar, relays the bar and fires its OnChange. }
procedure TTyCustomClassesP2Test.TestThirdCoolBarBandsReachTheirHost;
var
  bar: TThirdCoolBar;
  c: TTyCustomCoolBar;
  band: TTyCoolBand;
  p: TTyPanel;
begin
  bar := TThirdCoolBar.Create(FForm);
  bar.Parent := FForm;
  bar.Font.PixelsPerInch := 96;
  bar.SetBounds(0, 0, 400, 60);
  p := TTyPanel.Create(FForm);
  p.Parent := bar;
  p.SetBounds(10, 0, 80, 30);
  band := bar.Bands.Add;
  band.Control := p;
  FChanges := 0;
  c := bar;
  c.OnChange := @CountChange;
  band.Break := True;
  AssertTrue('editing a band of the third-party bar notifies the bar', FChanges > 0);
end;

{ The viewport only RegisterClass'd -- it is not on the palette but it is in .lfm files
  (examples/containers). Since 4.0 the base class publishes nothing, so it reads its bounds
  and children only because TTyScrollContent publishes them itself. }
procedure TTyCustomClassesP2Test.TestScrollContentStreamsFromAFormFile;
const
  CText =
    'object SbView: TTyScrollContent' + LineEnding +
    '  Left = 4' + LineEnding +
    '  Height = 300' + LineEnding +
    '  Top = 6' + LineEnding +
    '  Width = 420' + LineEnding +
    '  Visible = False' + LineEnding +
    '  object SbBtn: TTyButton' + LineEnding +
    '    Left = 12' + LineEnding +
    '    Height = 28' + LineEnding +
    '    Top = 250' + LineEnding +
    '    Width = 90' + LineEnding +
    '    Caption = ''Far down''' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
var
  src: TStringStream;
  bin: TMemoryStream;
  view: TTyScrollContent;
begin
  src := TStringStream.Create(CText);
  bin := TMemoryStream.Create;
  view := TTyScrollContent.Create(FForm);
  try
    ObjectTextToBinary(src, bin);
    bin.Position := 0;
    bin.ReadComponent(view);
    AssertEquals('Left', 4, view.Left);
    AssertEquals('Top', 6, view.Top);
    AssertEquals('Width', 420, view.Width);
    AssertEquals('Height', 300, view.Height);
    AssertFalse('Visible (published by TTyScrollContent itself since 4.0)', view.Visible);
    AssertEquals('the child came along', 1, view.ControlCount);
    AssertEquals('as a button at its streamed place', 250, view.Controls[0].Top);
  finally
    src.Free;
    bin.Free;
  end;
end;

{ ------------------------------------------------------------------ Task 13: groups }

procedure TTyCustomClassesP2Test.TestThirdGroupBox;
var
  third, back: TThirdGroupBox;
  own: TTyGroupBox;
  c: TTyCustomGroupBox;
  bmA, bmB: TBitmap;
  diff: string;
begin
  third := TThirdGroupBox.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(10, 10, 180, 90);
  CheckPublishesOnly(TThirdGroupBox, ['Caption', 'Alignment']);
  third.Caption := 'Options';
  third.Alignment := taCenter;
  third.ClientWidth := 150;
  CheckStreamText(third, ['Caption', 'Alignment'], 'ClientWidth');
  back := TThirdGroupBox.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Caption round-trips', 'Options', back.Caption);
  AssertTrue('T-c: Alignment round-trips', back.Alignment = taCenter);
  own := TTyGroupBox.Create(FForm);
  own.Parent := FForm;
  own.SetBounds(10, 110, 180, 90);
  own.Caption := 'Options';
  own.Alignment := taCenter;
  third.SetBounds(10, 10, 180, 90);
  CheckSameTypeKey(third, own);
  bmA := NewSentinelBitmap(180, 90);
  bmB := NewSentinelBitmap(180, 90);
  try
    TP2GroupBoxCracker(third).DoRender(bmA.Canvas, Rect(0, 0, 180, 90));
    TP2GroupBoxCracker(own).DoRender(bmB.Canvas, Rect(0, 0, 180, 90));
    AssertTrue('T-d: the mimic paints exactly what TTyGroupBox paints: ' + diff,
      SameBitmaps(bmA, bmB, diff));
  finally
    bmA.Free;
    bmB.Free;
  end;
  CheckFreshDefaults(TThirdGroupBox, ['Caption', 'Alignment']);
  c := third;
  c.Alignment := taRightJustify;
  AssertTrue('T-v: Alignment is public through a TTyCustomGroupBox reference',
    third.Alignment = taRightJustify);
end;

{ The radio group builds its own TTyRadioButton children -- a third party's group does too, and
  checking one of them reports back to the group that built it. }
procedure TTyCustomClassesP2Test.TestThirdRadioGroup;
var
  third, back: TThirdRadioGroup;
  own: TTyRadioGroup;
  c: TTyCustomRadioGroup;
begin
  third := TThirdRadioGroup.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(0, 0, 200, 120);
  CheckPublishesOnly(TThirdRadioGroup, ['Items', 'ItemIndex']);
  third.Items.CommaText := 'one,two,three';
  third.ItemIndex := 2;
  third.Columns := 2;
  CheckStreamText(third, ['Items', 'ItemIndex'], 'Columns');
  back := TThirdRadioGroup.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertEquals('T-c: Items round-trip', 'one,two,three', back.Items.CommaText);
  AssertEquals('T-c: ItemIndex round-trips', 2, back.ItemIndex);
  AssertEquals('T-c: the unpublished Columns stayed at its default', 1, back.Columns);
  { The group's own children are the library's radio buttons, and they answer to it. }
  AssertTrue('the group built a TTyRadioButton for each item', third.Buttons[1] is TTyRadioButton);
  FChanges := 0;
  third.OnSelectionChanged := @CountChange;
  third.Buttons[1].Checked := True;
  AssertEquals('checking the second child selects it in the third-party group', 1, third.ItemIndex);
  AssertTrue('and the group reports the change', FChanges > 0);
  own := TTyRadioGroup.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdRadioGroup, ['Items', 'ItemIndex']);
  c := third;
  c.Columns := 3;
  AssertEquals('T-v: Columns is public through a TTyCustomRadioGroup reference', 3, third.Columns);
end;

{ ------------------------------------------------------------------ Task 14: tabs }

procedure TTyCustomClassesP2Test.TestThirdPageControl;
var
  third, back: TThirdPageControl;
  own: TTyPageControl;
  c: TTyCustomPageControl;
  pg: TTyTabSheet;
  i: Integer;
begin
  { Owned by the page control itself, so they stream as its children. }
  third := TThirdPageControl.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(0, 0, 300, 200);
  CheckPublishesOnly(TThirdPageControl, ['ActivePageIndex', 'TabPosition']);
  for i := 0 to 2 do
  begin
    pg := TTyTabSheet.Create(third);
    pg.Name := 'Pg' + IntToStr(i);
    pg.Caption := 'Page ' + IntToStr(i);
    pg.Parent := third;
  end;
  third.ActivePageIndex := 1;
  third.TabPosition := tpBottom;
  third.TabsClosable := True;
  CheckStreamText(third, ['ActivePageIndex', 'TabPosition'], 'TabsClosable');
  back := TThirdPageControl.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertEquals('T-c: the pages came along', 3, back.PageCount);
  AssertEquals('T-c: ActivePageIndex round-trips', 1, back.ActivePageIndex);
  AssertTrue('T-c: TabPosition round-trips', back.TabPosition = tpBottom);
  AssertFalse('T-c: the unpublished TabsClosable stayed at its default', back.TabsClosable);
  own := TTyPageControl.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdPageControl, ['ActivePageIndex', 'TabPosition']);
  c := third;
  c.TabsClosable := False;
  AssertFalse('T-v: TabsClosable is public through a TTyCustomPageControl reference',
    third.TabsClosable);
end;

{ S14-1. A library page parented to a third party's page control joins it: the page asks
  `is TTyCustomPageControl`, so the host counts it, it names the host, and activating it shows
  it. Asking for TTyPageControl left the mimic with no pages at all. }
procedure TTyCustomClassesP2Test.TestTabSheetJoinsAThirdPartyPageControl;
var
  pc: TThirdPageControl;
  a, b: TTyTabSheet;
begin
  pc := TThirdPageControl.Create(FForm);
  pc.Parent := FForm;
  pc.SetBounds(0, 0, 300, 200);
  AssertFalse('the mimic is no TTyPageControl (or this proves nothing)', TObject(pc) is TTyPageControl);
  a := TTyTabSheet.Create(FForm);
  a.Parent := pc;
  b := TTyTabSheet.Create(FForm);
  b.Parent := pc;
  AssertEquals('both pages registered with the third-party host', 2, pc.PageCount);
  AssertTrue('a page names its host', TObject(b.PageControl) = TObject(pc));
  AssertEquals('and knows its place in it', 1, b.PageIndex);
  pc.ActivePageIndex := 1;
  AssertTrue('activating the page shows it', b.Visible);
  AssertFalse('and hides the other', a.Visible);
end;

{ S14-2. A third party's page, the active one, freed: the page control hears the removal --
  it asks `is TTyCustomTabSheet` -- and forgets it. The judgement is "ActivePage = nil"; the
  page must never be dereferenced after the free. }
procedure TTyCustomClassesP2Test.TestPageControlDropsAFreedThirdPartySheet;
var
  pc: TTyPageControl;
  sheet: TThirdTabSheet;
begin
  pc := TTyPageControl.Create(FForm);
  pc.Parent := FForm;
  pc.SetBounds(0, 0, 300, 200);
  sheet := TThirdTabSheet.Create(FForm);
  sheet.Parent := pc;
  AssertEquals('the third-party page registered', 1, pc.PageCount);
  AssertTrue('and is the active page', pc.ActivePage = sheet);
  sheet.Free;
  AssertEquals('freeing it removed it from the host', 0, pc.PageCount);
  AssertTrue('and the host no longer hands it out', pc.ActivePage = nil);
end;

{ S14-3. The page control hands out what it holds. A third party's page is a TTyCustomTabSheet
  and not a TTyTabSheet, so ActivePage and Pages[] are typed TTyCustomTabSheet -- the way
  LCL's TCustomTabControl hands out TCustomPage -- rather than cast to the final class, which
  would be a lie about this page. The declared type is pinned through RTTI (the getter is
  private), which is also what the snapshot's type-rename table allows for. }
procedure TTyCustomClassesP2Test.TestPageControlHandsOutAThirdPartySheetAsItIs;
var
  pc: TTyPageControl;
  sheet: TThirdTabSheet;
  got: TTyCustomTabSheet;
  pi: PPropInfo;
begin
  pc := TTyPageControl.Create(FForm);
  pc.Parent := FForm;
  pc.SetBounds(0, 0, 300, 200);
  pc.AddPage('library');
  sheet := TThirdTabSheet.Create(FForm);
  sheet.Parent := pc;
  pc.ActivePage := sheet;
  got := pc.ActivePage;
  AssertTrue('ActivePage is the third party''s page', got = sheet);
  AssertFalse('which is not a TTyTabSheet', TObject(got) is TTyTabSheet);
  AssertTrue('Pages[] hands out the same page', pc.Pages[1] = sheet);
  AssertTrue('AddPage still builds a TTyTabSheet', TObject(pc.Pages[0]) is TTyTabSheet);
  pi := GetPropInfo(TTyPageControl, 'ActivePage');
  AssertTrue('ActivePage is published', pi <> nil);
  AssertEquals('and declared as the custom class', 'TTyCustomTabSheet', pi^.PropType^.Name);
end;

{ The page's bounds, TabOrder and Visible belong to the pager; their `stored False` sits on
  TTyCustomTabSheet (Left..Height in its published section, where TControl already has them),
  so a third party's page keeps them out of its .lfm too. }
procedure TTyCustomClassesP2Test.TestThirdTabSheetKeepsItsBoundsOutOfTheStream;
var
  third: TThirdTabSheet;
  own: TTyTabSheet;
  txt: string;
begin
  third := TThirdTabSheet.Create(FForm);
  CheckPublishesOnly(TThirdTabSheet, ['Caption', 'ImageIndex']);
  third.Caption := 'Third';
  third.ImageIndex := 3;
  third.SetBounds(30, 40, 120, 90);
  AssertEquals('precondition: Left really is non-zero', 30, third.Left);
  CheckStreamText(third, ['Caption', 'ImageIndex'], 'Left');
  txt := StreamedText(third);
  AssertFalse('nor Top', HasProp(txt, 'Top'));
  AssertFalse('nor Width', HasProp(txt, 'Width'));
  AssertFalse('nor Height', HasProp(txt, 'Height'));
  own := TTyTabSheet.Create(FForm);
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdTabSheet, ['Caption', 'ImageIndex']);
end;

{ ------------------------------------------------------------------ Task 15: list boxes }

procedure TTyCustomClassesP2Test.TestThirdListBox;
var
  third, back: TThirdListBox;
  own: TTyListBox;
  c: TTyCustomListBox;
  bmA, bmB: TBitmap;
  diff: string;
begin
  third := TThirdListBox.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(0, 0, 150, 100);
  CheckPublishesOnly(TThirdListBox, ['Items', 'ItemIndex']);
  third.Items.CommaText := 'cherry,apple,banana';
  third.ItemIndex := 2;
  CheckStreamText(third, ['Items', 'ItemIndex'], 'Sorted');
  back := TThirdListBox.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertEquals('T-c: Items round-trip', 'cherry,apple,banana', back.Items.CommaText);
  AssertEquals('T-c: ItemIndex round-trips', 2, back.ItemIndex);
  own := TTyListBox.Create(FForm);
  own.Parent := FForm;
  own.SetBounds(0, 110, 150, 100);
  own.Items.CommaText := 'cherry,apple,banana';
  own.ItemIndex := 2;
  CheckSameTypeKey(third, own);
  AssertEquals('T-d: the row type key is the custom class''s too',
    TP2ListBoxCracker(own).ItemKey, TP2ListBoxCracker(third).ItemKey);
  bmA := NewSentinelBitmap(150, 100);
  bmB := NewSentinelBitmap(150, 100);
  try
    TP2ListBoxCracker(third).DoRender(bmA.Canvas, Rect(0, 0, 150, 100));
    TP2ListBoxCracker(own).DoRender(bmB.Canvas, Rect(0, 0, 150, 100));
    AssertTrue('T-d: the mimic paints exactly what TTyListBox paints: ' + diff,
      SameBitmaps(bmA, bmB, diff));
  finally
    bmA.Free;
    bmB.Free;
  end;
  CheckFreshDefaults(TThirdListBox, ['Items', 'ItemIndex']);
  { T-v: Sorted is public (TCustomListBox). }
  c := third;
  c.Sorted := True;
  AssertEquals('T-v: sorting through a TTyCustomListBox reference', 'apple,banana,cherry',
    third.Items.CommaText);
end;

procedure TTyCustomClassesP2Test.TestThirdCheckListBox;
var
  third, back: TThirdCheckListBox;
  own: TTyCheckListBox;
  c: TTyCustomCheckListBox;
begin
  third := TThirdCheckListBox.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(0, 0, 150, 100);
  CheckPublishesOnly(TThirdCheckListBox, ['Items', 'AllowGrayed']);
  third.Items.CommaText := 'one,two';
  third.AllowGrayed := True;
  third.ItemIndex := 1;
  CheckStreamText(third, ['Items', 'AllowGrayed'], 'ItemIndex');
  back := TThirdCheckListBox.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertEquals('T-c: Items round-trip', 'one,two', back.Items.CommaText);
  AssertTrue('T-c: AllowGrayed round-trips', back.AllowGrayed);
  AssertEquals('T-c: the unpublished ItemIndex stayed at its default', -1, back.ItemIndex);
  own := TTyCheckListBox.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdCheckListBox, ['Items', 'AllowGrayed']);
  c := third;
  c.Checked[0] := True;
  AssertTrue('T-v: Checked[] is public through a TTyCustomCheckListBox reference',
    third.Checked[0]);
end;

{ S15-1. The check combo's drop-down list descends from TTyCheckListBox, which since 4.0 is a
  TTyCustomListBox and no longer a TTyListBox -- which is why the combo popup API (the
  CreatePopupList factory, PopupList, the row owner-draw calls) takes TTyCustomListBox. The
  factory hands the list over through that API and a tick on it reaches the combo. }
procedure TTyCustomClassesP2Test.TestCheckComboPopupListTravelsTheWidenedApi;
var
  cc: TTyCheckComboBox;
  l: TTyCustomListBox;
begin
  cc := TTyCheckComboBox.Create(FForm);
  cc.Parent := FForm;
  cc.Items.CommaText := 'red,green,blue';
  l := TP2CheckComboCracker(cc).MakePopupList;
  try
    AssertTrue('the check combo drops a check list', l is TTyCheckListBox);
    AssertFalse('which is no TTyListBox since 4.0 (the reason the API widened)',
      TObject(l) is TTyListBox);
    l.Items.Assign(cc.Items);
    TTyCheckListBox(l).Checked[1] := True;
    cc.PullChecksForTest(TTyCheckListBox(l));
    AssertTrue('the tick on the popup list reached the combo', cc.Checked[1]);
    AssertFalse('and only that one', cc.Checked[0] or cc.Checked[2]);
  finally
    l.Free;
  end;
end;

{ ------------------------------------------------------------------ Task 16: compound pickers }

procedure TTyCustomClassesP2Test.TestThirdCascader;
var
  third, back: TThirdCascader;
  own: TTyCascader;
  c: TTyCustomCascader;
  east, zj: TTyCascaderNode;
begin
  third := TThirdCascader.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdCascader, ['Nodes', 'Separator']);
  east := third.Nodes.AddNode('East');
  zj := east.Children.AddNode('Zhejiang');
  zj.Children.AddNode('Hangzhou');
  third.Nodes.AddNode('West');
  third.Separator := ' > ';
  third.DropDownRows := 4;
  CheckStreamText(third, ['Nodes', 'Separator'], 'DropDownRows');
  back := TThirdCascader.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  { T-c on a nested collection: every level comes back. }
  AssertEquals('T-c: the top level round-trips', 2, back.Nodes.Count);
  AssertEquals('T-c: captions too', 'East', back.Nodes[0].Caption);
  AssertEquals('T-c: and the second level', 'Zhejiang', back.Nodes[0].Children[0].Caption);
  AssertEquals('T-c: and the third', 'Hangzhou', back.Nodes[0].Children[0].Children[0].Caption);
  AssertEquals('T-c: Separator round-trips', ' > ', back.Separator);
  AssertEquals('T-c: the unpublished DropDownRows stayed at its default', 8, back.DropDownRows);
  own := TTyCascader.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  { No T-e: Nodes is a collection (TWriter writes one whenever there is no ancestor to compare
    with) and Separator has had no declared default since 3.0, so a fresh TTyCascader streams
    both as well. }
  c := third;
  c.DropDownRows := 5;
  AssertEquals('T-v: DropDownRows is public through a TTyCustomCascader reference', 5,
    third.DropDownRows);
end;

procedure TTyCustomClassesP2Test.TestThirdTransfer;
var
  third, back: TThirdTransfer;
  own: TTyTransfer;
  c: TTyCustomTransfer;
begin
  third := TThirdTransfer.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(0, 0, 360, 200);
  CheckPublishesOnly(TThirdTransfer, ['Items', 'Selected']);
  third.Items.CommaText := 'a,b,c';
  third.Selected.CommaText := 'x,y';
  third.LeftTitle := 'Source';
  CheckStreamText(third, ['Items', 'Selected'], 'LeftTitle');
  back := TThirdTransfer.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertEquals('T-c: Items round-trip', 'a,b,c', back.Items.CommaText);
  AssertEquals('T-c: Selected round-trips', 'x,y', back.Selected.CommaText);
  AssertEquals('T-c: the unpublished LeftTitle stayed at its default', '', back.LeftTitle);
  own := TTyTransfer.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdTransfer, ['Items', 'Selected']);
  c := third;
  c.ShowTitles := False;
  AssertFalse('T-v: ShowTitles is public through a TTyCustomTransfer reference', third.ShowTitles);
end;

initialization
  RegisterClasses([TThirdPanel, TThirdGridPanel, TThirdScrollContent, TThirdCoolBar,
    TThirdGroupBox, TThirdRadioGroup, TThirdPageControl, TThirdTabSheet, TThirdListBox,
    TThirdCheckListBox, TThirdCascader, TThirdTransfer]);
  RegisterTest(TTyCustomClassesP2Test);
end.
