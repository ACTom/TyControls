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
  Classes, SysUtils, FileUtil, LazFileUtils, Types, TypInfo, ImgList, Controls, Forms, Graphics, ComCtrls,
  StdCtrls,
  BGRABitmap,
  BGRABitmapTypes, fpcunit, testregistry,
  test.customclasses, test.customclasses.p1,
  tyControls.Base, tyControls.Panel, tyControls.GridPanel, tyControls.ScrollBox,
  tyControls.ScrollContent, tyControls.ControlBar, tyControls.CoolBar, tyControls.Button,
  tyControls.GroupBox, tyControls.RadioGroup, tyControls.CheckBox, tyControls.TabStrip,
  tyControls.TabSheet, tyControls.PageControl, tyControls.TabSet, tyControls.ListBox, tyControls.CheckListBox,
  tyControls.ComboBox, tyControls.CheckComboBox, tyControls.Transfer, tyControls.Cascader,
  tyControls.ImageCollection, tyControls.TreeView, tyControls.ShellTreeView, tyControls.ListView,
  tyControls.ListView.Layout, tyControls.ShellListView, tyControls.Grid, tyControls.Columns,
  tyControls.ColorBox, tyControls.ColorListBox;

type
  TTyCustomClassesP2Test = class(TTyCustomClassesPhaseCase)
  private
    FChanges: Integer;
    FHosts: TList;
    FGetTextSender: TObject;
    FGetTextSenderIsCustom: Boolean;
    procedure CountChange(Sender: TObject);
    procedure TreeGetText(Sender: TTyCustomTreeView; Node: PTyTreeNode; var Text: string);
    procedure GridGetCellText(Sender: TObject; ACol, ARow: Integer; var AText: string);
    procedure GridHeaderClicked(Sender: TObject; ACol: Integer);
    { A form to put a control on for HostRoundTrip; freed in TearDown. }
    function NewHost: TForm;
    { T-c for a control that builds children it owns (a radio group's buttons, a transfer's
      panes): stream the form that owns ASrc, read it into a fresh form, and return the copy of
      ASrc -- the way a .lfm carries it, children left to the control to rebuild. }
    function HostRoundTrip(ASrc: TComponent): TComponent;
    { A three-icon virtual list (home / settings / search), owned by the caller. }
    function NewNamedImages(out AColl: TTyImageCollection): TTyVirtualImageList;
  protected
    procedure TearDown; override;
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
    procedure TestTabSetIndexIsPublicOnTheCustomClass;
    { Task 15: list boxes }
    procedure TestThirdListBox;
    procedure TestIndexesReadBeforeTheirItemsWaitForThem;
    procedure TestThirdCheckListBox;
    procedure TestCheckComboPopupListTravelsTheWidenedApi;
    procedure TestCheckComboDropsAThirdPartyCheckList;
    { Task 16: compound pickers }
    procedure TestThirdCascader;
    procedure TestThirdTransfer;
    { Task 17: trees and list views }
    procedure TestThirdTreeView;
    procedure TestTreeNodeResolvesItsIconOnAThirdPartyTree;
    procedure TestShellTreeViewHearsItsNodeCollection;
    procedure TestThirdTreeViewNodeCollectionBuildsTheTree;
    procedure TestShellListItemResolvesItsIconOnTheShellList;
    procedure TestShellTreeDrivesAThirdPartyShellList;
    procedure TestThirdListView;
    { Task 18: grids }
    procedure TestThirdStringGrid;
    procedure TestThirdDrawGrid;
    procedure TestDrawGridPromotesWhatTCustomDrawGridPromotes;
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

  { LCL's order: TRadioGroup publishes ItemIndex ahead of Items (extctrls.pp), so a ported
    group reads the index before there is anything for it to point at. }
  TThirdRadioGroup = class(TTyCustomRadioGroup)
  published
    property ItemIndex;
    property Items;
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

  { ItemIndex ahead of Items. TListBox happens to publish Items first (stdctrls.pp:710-712),
    but the order is the third party's to choose, and the index must survive either. }
  TThirdListBox = class(TTyCustomListBox)
  published
    property ItemIndex;
    property Items;
  end;

  { Every index-like property ahead of what it indexes -- the order a third party may well
    choose, and the one the library's own final classes never use. }
  TIdxListBox = class(TTyCustomListBox)
  protected
    procedure DoSelectionChange(AUser: Boolean); override;
  public
    SelectionChanges: Integer;
  published
    property TopIndex;
    property ItemIndex;
    property Items;
  end;

  { Selected ahead of the Style whose palette holds it (TTyColorListBox does the same). }
  TIdxColorListBox = class(TTyCustomColorListBox)
  published
    property Selected;
    property Style;
  end;

  TIdxStringGrid = class(TTyCustomStringGrid)
  published
    property Col;
    property Row;
    property RowCount;
    property Header;
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

  TThirdTreeView = class(TTyCustomTreeView)
  published
    property Items;
    property OnGetText;
  end;

  TThirdListView = class(TTyCustomListView)
  published
    property ViewStyle;
    property Items;
  end;

  { No ColCount on this grid: the columns are Header.Columns, so the mimic publishes Header. }
  TThirdStringGrid = class(TTyCustomStringGrid)
  published
    property RowCount;
    property Header;
  end;

  TThirdDrawGrid = class(TTyCustomDrawGrid)
  published
    property RowCount;
    property OnGetCellText;
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

  { A third party's own check list, dropped by its own check combo: it is a
    TTyCustomCheckListBox and not a TTyCheckListBox. }
  TP2ThirdCheckList = class(TTyCustomCheckListBox);

  TP2ThirdListCheckCombo = class(TTyCustomCheckComboBox)
  protected
    function CreatePopupList: TTyCustomListBox; override;
  end;

  { A third party's shell list, linked to the library's shell tree. }
  TP2ThirdShellList = class(TTyCustomShellListView);

  { The tree's own properties are protected (TCustomTreeView keeps them protected). }
  TP2TreeCracker = class(TTyCustomTreeView)
  public
    procedure SetRootCount(AValue: Cardinal);
    procedure SetNodeHeight(AValue: Integer);
    function NodeHeightNow: Integer;
  end;

  { RowHeight is protected (Ty's own, and TCustomListView's are mostly protected). }
  TP2ListViewCracker = class(TTyCustomListView)
  public
    procedure SetRowHeightTo(AValue: Integer);
    function RowHeightNow: Integer;
    procedure SetSmall(AValue: TCustomImageList);
    procedure SetLarge(AValue: TCustomImageList);
  end;

  { GetCellText is protected: what the grid would draw in a cell. }
  TP2DrawGridCracker = class(TTyCustomDrawGrid)
  public
    function CellText(ACol, ARow: Integer): string;
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

function TP2ThirdListCheckCombo.CreatePopupList: TTyCustomListBox;
begin
  Result := TP2ThirdCheckList.Create(Self);
end;

procedure TP2TreeCracker.SetRootCount(AValue: Cardinal);
begin
  RootNodeCount := AValue;
end;

procedure TP2TreeCracker.SetNodeHeight(AValue: Integer);
begin
  DefaultNodeHeight := AValue;
end;

function TP2TreeCracker.NodeHeightNow: Integer;
begin
  Result := DefaultNodeHeight;
end;

procedure TP2ListViewCracker.SetRowHeightTo(AValue: Integer);
begin
  RowHeight := AValue;
end;

function TP2ListViewCracker.RowHeightNow: Integer;
begin
  Result := RowHeight;
end;

procedure TP2ListViewCracker.SetSmall(AValue: TCustomImageList);
begin
  SmallImages := AValue;
end;

procedure TP2ListViewCracker.SetLarge(AValue: TCustomImageList);
begin
  LargeImages := AValue;
end;

function TP2DrawGridCracker.CellText(ACol, ARow: Integer): string;
begin
  Result := GetCellText(ACol, ARow);
end;

function TP2ScrollBoxCracker.Host: TWinControl;
begin
  Result := ContentHost;
end;

procedure TTyCustomClassesP2Test.CountChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyCustomClassesP2Test.TearDown;
var
  i: Integer;
begin
  if FHosts <> nil then
    for i := FHosts.Count - 1 downto 0 do
      TObject(FHosts[i]).Free;
  FreeAndNil(FHosts);
  inherited TearDown;
end;

function TTyCustomClassesP2Test.NewHost: TForm;
begin
  if FHosts = nil then FHosts := TList.Create;
  Result := TForm.CreateNew(nil);
  Result.SetBounds(0, 0, 600, 400);
  FHosts.Add(Result);
end;

function TTyCustomClassesP2Test.HostRoundTrip(ASrc: TComponent): TComponent;
var
  ms: TMemoryStream;
  dst: TForm;
begin
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(ASrc.Owner);
    ms.Position := 0;
    dst := NewHost;
    ms.ReadComponent(dst);
  finally
    ms.Free;
  end;
  Result := dst.FindComponent(ASrc.Name);
  AssertTrue('the round trip brought ' + ASrc.Name + ' back', Result <> nil);
end;

procedure TTyCustomClassesP2Test.TreeGetText(Sender: TTyCustomTreeView; Node: PTyTreeNode;
  var Text: string);
begin
  FGetTextSender := Sender;
  FGetTextSenderIsCustom := TObject(Sender) is TTyCustomTreeView;
  Text := 'row ' + IntToStr(Node^.Index);
end;

procedure TTyCustomClassesP2Test.GridHeaderClicked(Sender: TObject; ACol: Integer);
begin
  Inc(FChanges);
end;

procedure TTyCustomClassesP2Test.GridGetCellText(Sender: TObject; ACol, ARow: Integer;
  var AText: string);
begin
  Inc(FChanges);
  AText := Format('%d:%d', [ACol, ARow]);
end;

function TTyCustomClassesP2Test.NewNamedImages(out AColl: TTyImageCollection): TTyVirtualImageList;

  procedure AddImg(const AName: string; AColor: TBGRAPixel);
  var bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(24, 24, AColor);
    try AColl.AddBitmap(AName, bmp); finally bmp.Free; end;
  end;

begin
  NeedWidgetSet;
  AColl := TTyImageCollection.Create(nil);
  AddImg('home', BGRA(255, 0, 0, 255));
  AddImg('settings', BGRA(0, 255, 0, 255));
  AddImg('search', BGRA(0, 0, 255, 255));
  Result := TTyVirtualImageList.Create(nil);
  Result.Collection := AColl;
  Result.Names.Text := 'home' + LineEnding + 'settings' + LineEnding + 'search';
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
  host: TForm;
  third, back: TThirdRadioGroup;
  own: TTyRadioGroup;
  c: TTyCustomRadioGroup;
begin
  { On a host form of its own: the group builds and owns its radio buttons, which a .lfm never
    carries -- streamed as the root, the group would write them out as its children. }
  host := NewHost;
  third := TThirdRadioGroup.Create(host);
  third.Name := 'RG';
  third.Parent := host;
  third.SetBounds(0, 0, 200, 120);
  CheckPublishesOnly(TThirdRadioGroup, ['ItemIndex', 'Items']);
  third.Items.CommaText := 'one,two,three';
  third.ItemIndex := 2;
  third.Columns := 2;
  CheckStreamText(third, ['ItemIndex', 'Items'], 'Columns');
  back := HostRoundTrip(third) as TThirdRadioGroup;
  AssertEquals('T-c: Items round-trip', 'one,two,three', back.Items.CommaText);
  AssertEquals('T-c: ItemIndex round-trips, though it is read before the items', 2,
    back.ItemIndex);
  AssertTrue('T-c: and the third button is the checked one', back.Buttons[2].Checked);
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
  CheckFreshDefaults(TThirdRadioGroup, ['ItemIndex', 'Items']);
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

{ TabIndex is public on TTyCustomTabSet: the strip it descends from has it public already, so a
  protected redeclaration hid nothing and only misled (N16). }
procedure TTyCustomClassesP2Test.TestTabSetIndexIsPublicOnTheCustomClass;
var
  own: TTyTabSet;
  c: TTyCustomTabSet;
begin
  own := TTyTabSet.Create(FForm);
  own.Parent := FForm;
  own.Tabs.CommaText := 'one,two,three';
  c := own;
  c.TabIndex := 2;
  AssertEquals('TabIndex through a TTyCustomTabSet reference', 2, c.TabIndex);
  AssertEquals('is the tab set''s own', 2, own.TabIndex);
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
  CheckPublishesOnly(TThirdListBox, ['ItemIndex', 'Items']);
  third.Items.CommaText := 'cherry,apple,banana';
  third.ItemIndex := 2;
  CheckStreamText(third, ['ItemIndex', 'Items'], 'Sorted');
  back := TThirdListBox.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertEquals('T-c: Items round-trip', 'cherry,apple,banana', back.Items.CommaText);
  AssertEquals('T-c: ItemIndex round-trips, though it is read before the items', 2,
    back.ItemIndex);
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
  CheckFreshDefaults(TThirdListBox, ['ItemIndex', 'Items']);
  { T-v: Sorted is public (TCustomListBox). }
  c := third;
  c.Sorted := True;
  AssertEquals('T-v: sorting through a TTyCustomListBox reference', 'apple,banana,cherry',
    third.Items.CommaText);
end;

procedure TIdxListBox.DoSelectionChange(AUser: Boolean);
begin
  Inc(SelectionChanges);
  inherited DoSelectionChange(AUser);
end;

{ A list box, a colour list box and a string grid whose index-like properties are read before
  what they point into. Each value waits for Loaded and lands where it was saved, as it
  does on the final classes, which publish the items first. }
procedure TTyCustomClassesP2Test.TestIndexesReadBeforeTheirItemsWaitForThem;
var
  lb, lbBack: TIdxListBox;
  cl, clBack: TIdxColorListBox;
  g, gBack: TIdxStringGrid;
  host: TForm;
  i: Integer;
  txt: string;
begin
  { Each on a form of its own, round-tripped the way a .lfm carries it. }
  host := NewHost;
  lb := TIdxListBox.Create(host);
  lb.Name := 'LB';
  lb.Parent := host;
  lb.SetBounds(0, 0, 150, 60);
  for i := 0 to 9 do lb.Items.Add('row ' + IntToStr(i));
  lb.ItemIndex := 7;
  lb.TopIndex := 3;       // scrolled away from the selection: both have to come back as saved
  AssertEquals('setup: the top row stayed where it was put', 3, lb.TopIndex);
  txt := StreamedText(lb);
  AssertTrue('setup: TopIndex streams ahead of Items' + LineEnding + txt,
    Pos('TopIndex', txt) < Pos('Items', txt));
  lbBack := HostRoundTrip(lb) as TIdxListBox;
  AssertEquals('the items came back', 10, lbBack.Items.Count);
  AssertEquals('ItemIndex read before Items lands on the saved row', 7, lbBack.ItemIndex);
  AssertEquals('and TopIndex read before Items keeps the saved scroll', 3, lbBack.TopIndex);
  AssertEquals('applied without a selection-change notification: reading a form is not one',
    0, lbBack.SelectionChanges);

  host := NewHost;
  cl := TIdxColorListBox.Create(host);
  cl.Name := 'CL';
  cl.Parent := host;
  cl.Style := [cbStandardColors, cbExtendedColors, cbPrettyNames];
  cl.Selected := clMoneyGreen;
  AssertEquals('setup: the extended palette holds clMoneyGreen', clMoneyGreen, cl.Selected);
  clBack := HostRoundTrip(cl) as TIdxColorListBox;
  AssertTrue('the palette came back', cbExtendedColors in clBack.Style);
  AssertEquals('Selected read before the Style that holds it', clMoneyGreen, clBack.Selected);

  host := NewHost;
  g := TIdxStringGrid.Create(host);
  g.Name := 'G';
  g.Parent := host;
  g.SetBounds(0, 0, 300, 200);
  for i := 0 to 2 do (g.Header.Columns.Add as TTyGridColumn).Text := 'c' + IntToStr(i);
  g.RowCount := 6;
  g.Col := 2;
  g.Row := 4;
  AssertEquals('setup: the cursor sits at column 2', 2, g.Col);
  AssertEquals('setup: and row 4', 4, g.Row);
  gBack := HostRoundTrip(g) as TIdxStringGrid;
  AssertEquals('the columns came back', 3, gBack.Header.Columns.Count);
  AssertEquals('Col read before the columns lands on the saved column', 2, gBack.Col);
  AssertEquals('Row read before RowCount lands on the saved row', 4, gBack.Row);
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

{ C6-5 (widened in the phase-2 fixes): a check combo that drops a third party's
  TTyCustomCheckListBox -- not the library's TTyCheckListBox -- still pushes its ticks into the
  list when it opens, hears a tick made on the list, and keeps an open list in step when code
  sets State[]. The list's OnClickCheck is wired by the combo, since a third party's
  CreatePopupList cannot reach the combo's private handler. }
procedure TTyCustomClassesP2Test.TestCheckComboDropsAThirdPartyCheckList;
var
  cc: TP2ThirdListCheckCombo;
  l: TTyCustomCheckListBox;
begin
  NeedWidgetSet;
  cc := TP2ThirdListCheckCombo.Create(FForm);
  cc.Parent := FForm;
  cc.Items.CommaText := 'red,green,blue';
  cc.Checked[1] := True;
  cc.DropDown;
  try
    AssertTrue('the combo dropped the third party''s list', cc.PopupList is TP2ThirdCheckList);
    AssertFalse('which is no TTyCheckListBox', TObject(cc.PopupList) is TTyCheckListBox);
    l := TTyCustomCheckListBox(cc.PopupList);
    AssertTrue('opening pushed the combo''s tick into the list', l.Checked[1]);
    AssertFalse('and only that one', l.Checked[0] or l.Checked[2]);
    AssertTrue('the combo wired the list''s OnClickCheck', Assigned(l.OnClickCheck));
    l.Checked[2] := True;            // the user ticks "blue" on the list
    l.OnClickCheck(l);
    AssertTrue('the tick on the list reached the combo', cc.Checked[2]);
    cc.State[0] := cbChecked;        // code sets a row while the list is open
    AssertTrue('the open list follows State[]', l.Checked[0]);
  finally
    cc.CloseUp;
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
  host: TForm;
  third, back: TThirdTransfer;
  own: TTyTransfer;
  c: TTyCustomTransfer;
begin
  { On a host form of its own: the transfer builds and owns its panes and arrow buttons. }
  host := NewHost;
  third := TThirdTransfer.Create(host);
  third.Name := 'Tr';
  third.Parent := host;
  third.SetBounds(0, 0, 360, 200);
  CheckPublishesOnly(TThirdTransfer, ['Items', 'Selected']);
  third.Items.CommaText := 'a,b,c';
  third.Selected.CommaText := 'x,y';
  third.LeftTitle := 'Source';
  CheckStreamText(host, ['Items', 'Selected'], 'LeftTitle');
  back := HostRoundTrip(third) as TThirdTransfer;
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

{ ------------------------------------------------------------------ Task 17: trees and lists }

{ The mimic tree, and T-f: an event fired on a third party's tree hands over that tree, typed as
  what it is -- a TTyCustomTreeView (plan D10, LCL's TTVExpandingEvent and friends name
  TCustomTreeView). With the old TTyTreeView Sender the library would have had to call a
  third party's (or the shell) tree a TTyTreeView. }
procedure TTyCustomClassesP2Test.TestThirdTreeView;
var
  third, back: TThirdTreeView;
  own: TTyTreeView;
  c: TTyCustomTreeView;
  n: PTyTreeNode;
begin
  third := TThirdTreeView.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(0, 0, 200, 150);
  CheckPublishesOnly(TThirdTreeView, ['Items', 'OnGetText']);
  third.Items.Add(nil, 'alpha');
  third.Items.AddChild(third.Items[0], 'beta');
  TP2TreeCracker(third).SetNodeHeight(31);
  CheckStreamText(third, ['Items'], 'DefaultNodeHeight');
  back := TThirdTreeView.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertEquals('T-c: the items round-trip', 2, back.Items.Count);
  AssertEquals('T-c: with their text', 'beta', back.Items[1].Text);
  AssertTrue('T-c: the unpublished DefaultNodeHeight stayed unset',
    TP2TreeCracker(back).NodeHeightNow <> 31);
  own := TTyTreeView.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdTreeView, ['OnGetText']);
  { T-f, on a virtual tree (Items and OnGetText do not mix). }
  c := TThirdTreeView.Create(FForm);
  c.Parent := FForm;
  TThirdTreeView(c).OnGetText := @TreeGetText;
  TP2TreeCracker(c).SetRootCount(2);
  n := c.GetFirst;
  AssertTrue('the virtual tree has a first node', n <> nil);
  FGetTextSender := nil;
  AssertEquals('OnGetText supplied the text', 'row 0', c.NodeText[n]);
  AssertTrue('T-f: Sender is the third-party tree itself', FGetTextSender = TObject(c));
  AssertTrue('T-f: typed as the custom class', FGetTextSenderIsCustom);
  AssertFalse('T-f: which is not a TTyTreeView', FGetTextSender is TTyTreeView);
end;

{ S17-1. A node's ImageName resolves against its tree's Images when the tree is any
  TTyCustomTreeView: the node item asks its collection's owner `is TTyCustomTreeView`.
  (Executing it found the shell tree never reaches this path -- it refuses the item model --
  so this is a widening for third parties, witnessed by a mimic.) }
procedure TTyCustomClassesP2Test.TestTreeNodeResolvesItsIconOnAThirdPartyTree;
var
  coll: TTyImageCollection;
  imgs: TTyVirtualImageList;
  tree: TThirdTreeView;
  node: TTyTreeNodeItem;
begin
  imgs := NewNamedImages(coll);
  tree := TThirdTreeView.Create(nil);
  try
    tree.Images := imgs;
    node := tree.Items.Add(nil, 'a node');
    node.ImageName := 'search';
    AssertEquals('the node resolves its name against the third-party tree''s list', 2,
      node.ImageIndex);
    node.ImageIndex := 1;
    AssertEquals('and an index turns into the durable name', 'settings', node.ImageName);
  finally
    tree.Free;
    imgs.Free;
    coll.Free;
  end;
end;

{ S17-2, the library's own derived tree. The shell tree builds its nodes from the file system
  and refuses the item model: an item added to its Items must be heard -- the collection asks
  its owner `is TTyCustomTreeView` -- and refused with the item-model error. Asking for
  TTyTreeView, the shell tree never heard its own collection change. }
procedure TTyCustomClassesP2Test.TestShellTreeViewHearsItsNodeCollection;
var
  tree: TTyShellTreeView;
  raised: Boolean;
begin
  tree := TTyShellTreeView.Create(FForm);
  AssertFalse('the shell tree is no TTyTreeView since 4.0 (or this proves nothing)',
    TObject(tree) is TTyTreeView);
  raised := False;
  try
    tree.Items.Add(nil, 'not from the file system');
  except
    on E: ETyTreeItemMode do raised := True;
  end;
  AssertTrue('the shell tree heard the item and refused the item model', raised);
end;

{ S17-2 again, on a mimic: a node added to a third party's tree's Items reaches the tree, which
  rebuilds its nodes from them. }
procedure TTyCustomClassesP2Test.TestThirdTreeViewNodeCollectionBuildsTheTree;
var
  tree: TThirdTreeView;
  n: PTyTreeNode;
begin
  tree := TThirdTreeView.Create(FForm);
  tree.Parent := FForm;
  AssertTrue('an empty tree has no first node', tree.GetFirst = nil);
  tree.Items.Add(nil, 'first');
  n := tree.GetFirst;
  AssertTrue('adding an item built a node', n <> nil);
  AssertEquals('carrying the item''s text', 'first', tree.NodeText[n]);
  tree.Items[0].Text := 'renamed';
  AssertEquals('and an edit to the item reaches the node', 'renamed', tree.NodeText[tree.GetFirst]);
end;

{ S17-3. A list item's ImageName resolves against its view's Small/LargeImages for any
  TTyCustomListView -- the shell list included, which is no TTyListView since 4.0. }
procedure TTyCustomClassesP2Test.TestShellListItemResolvesItsIconOnTheShellList;
var
  coll: TTyImageCollection;
  imgs: TTyVirtualImageList;
  lv: TTyShellListView;
  it: TTyListItem;
begin
  imgs := NewNamedImages(coll);
  lv := TTyShellListView.Create(nil);
  try
    AssertFalse('the shell list is no TTyListView since 4.0 (or this proves nothing)',
      TObject(lv) is TTyListView);
    TP2ListViewCracker(lv).SetSmall(imgs);
    TP2ListViewCracker(lv).SetLarge(imgs);
    it := lv.Items.Add;
    it.ImageName := 'settings';
    AssertEquals('the item resolves its name against the shell list''s images', 1, it.ImageIndex);
  finally
    lv.Free;
    imgs.Free;
    coll.Free;
  end;
end;

{ TTyShellTreeView.ShellListView takes any TTyCustomShellListView, as LCL's
  TCustomShellTreeView.ShellListView takes a TCustomShellListView (shellctrls.pas:139): a third
  party's list can be linked, and the tree drives its Directory. (TTyFilterComboBox.ShellListView
  stays TTyShellListView, as LCL's TFilterComboBox.ShellListView is a TShellListView,
  filectrl.pp:167.) }
procedure TTyCustomClassesP2Test.TestShellTreeDrivesAThirdPartyShellList;
var
  root, sub: string;
  tree: TTyShellTreeView;
  list: TP2ThirdShellList;
begin
  { Under the user's folder, not %TEMP%: the tree will not walk through a hidden ancestor. }
  root := ChompPathDelim(AppendPathDelim(GetUserDir) + 'tycustomshelllink_' + IntToStr(GetProcessID));
  sub := AppendPathDelim(root) + 'a';
  ForceDirectories(sub);
  tree := TTyShellTreeView.Create(nil);
  list := TP2ThirdShellList.Create(nil);
  try
    AssertTrue('fixture reachable', tree.SelectPath(root));
    tree.ShellListView := list;
    AssertTrue('linking pushed the tree''s folder into the third party''s list',
      SameFileName(ExcludeTrailingPathDelimiter(list.Directory), root));
    AssertTrue('precondition', tree.SelectPath(sub));
    AssertTrue('selecting a folder moved the list there',
      SameFileName(ExcludeTrailingPathDelimiter(list.Directory), sub));
    AssertEquals('the property is typed for any shell list', 'TTyCustomShellListView',
      GetPropInfo(TTyShellTreeView, 'ShellListView')^.PropType^.Name);
    FreeAndNil(list);
    AssertTrue('freeing the list unlinks it', tree.ShellListView = nil);
  finally
    list.Free;
    tree.Free;
    DeleteDirectory(root, False);
  end;
end;

procedure TTyCustomClassesP2Test.TestThirdListView;
var
  third, back: TThirdListView;
  own: TTyListView;
  c: TTyCustomListView;
begin
  third := TThirdListView.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(0, 0, 240, 160);
  CheckPublishesOnly(TThirdListView, ['ViewStyle', 'Items']);
  third.ViewStyle := lvsList;
  third.Items.Add.Caption := 'one';
  third.Items.Add.Caption := 'two';
  TP2ListViewCracker(third).SetRowHeightTo(33);
  CheckStreamText(third, ['ViewStyle', 'Items'], 'RowHeight');
  back := TThirdListView.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertTrue('T-c: ViewStyle round-trips', back.ViewStyle = lvsList);
  AssertEquals('T-c: the items round-trip', 2, back.Items.Count);
  AssertEquals('T-c: with their captions', 'two', back.Items[1].Caption);
  AssertTrue('T-c: the unpublished RowHeight stayed unset', TP2ListViewCracker(back).RowHeightNow <> 33);
  own := TTyListView.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdListView, ['ViewStyle']);
  { T-v: MultiSelect is public (TCustomListView). }
  c := third;
  c.MultiSelect := True;
  AssertTrue('T-v: MultiSelect is public through a TTyCustomListView reference', third.MultiSelect);
end;

{ ------------------------------------------------------------------ Task 18: grids }

procedure TTyCustomClassesP2Test.TestThirdStringGrid;
var
  third, back: TThirdStringGrid;
  own: TTyStringGrid;
  c: TTyCustomStringGrid;
  col: TTyGridColumn;
begin
  third := TThirdStringGrid.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(0, 0, 300, 200);
  CheckPublishesOnly(TThirdStringGrid, ['RowCount', 'Header']);
  col := third.Header.Columns.Add as TTyGridColumn;
  col.Text := 'Name';
  col := third.Header.Columns.Add as TTyGridColumn;
  col.Text := 'Qty';
  col.Width := 68;
  third.RowCount := 5;
  third.ReadOnly := True;
  CheckStreamText(third, ['RowCount', 'Header'], 'ReadOnly');
  back := TThirdStringGrid.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertEquals('T-c: RowCount round-trips', 5, back.RowCount);
  AssertEquals('T-c: the columns round-trip', 2, back.Header.Columns.Count);
  AssertEquals('T-c: with their captions', 'Qty', (back.Header.Columns.Items[1] as TTyColumn).Text);
  AssertEquals('T-c: and widths', 68, (back.Header.Columns.Items[1] as TTyColumn).Width);
  AssertTrue('T-c: the column class came back', back.Header.Columns.Items[0] is TTyGridColumn);
  AssertFalse('T-c: the unpublished ReadOnly stayed at its default', back.ReadOnly);
  own := TTyStringGrid.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdStringGrid, ['RowCount']);
  { T-v: Cells[] and SelectionMode are public (TCustomStringGrid / Ty's own, public there). }
  c := third;
  c.Cells[0, 1] := 'apple';
  AssertEquals('T-v: Cells[] through a TTyCustomStringGrid reference', 'apple', third.Cells[0, 1]);
end;

procedure TTyCustomClassesP2Test.TestThirdDrawGrid;
var
  third, back: TThirdDrawGrid;
  own: TTyDrawGrid;
begin
  third := TThirdDrawGrid.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdDrawGrid, ['RowCount', 'OnGetCellText']);
  third.RowCount := 7;
  third.FixedRows := 1;
  CheckStreamText(third, ['RowCount'], 'FixedRows');
  back := TThirdDrawGrid.Create(FForm);
  back.Parent := FForm;
  StreamInto(third, back);
  AssertEquals('T-c: RowCount round-trips', 7, back.RowCount);
  AssertEquals('T-c: the unpublished FixedRows stayed at its default', 0, back.FixedRows);
  FChanges := 0;
  third.OnGetCellText := @GridGetCellText;
  AssertEquals('the published event supplies the cell text', '2:3',
    TP2DrawGridCracker(third).CellText(2, 3));
  AssertEquals('once', 1, FChanges);
  own := TTyDrawGrid.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdDrawGrid, ['RowCount', 'OnGetCellText']);
end;

{ TCustomGrid keeps its grid properties protected and TCustomDrawGrid promotes a batch of them
  to public (grids.pas:1397); TTyCustomGrid and TTyCustomDrawGrid do the same. Reaching them
  through a TTyCustomDrawGrid reference compiles -- that is the check -- and the values land. }
procedure TTyCustomClassesP2Test.TestDrawGridPromotesWhatTCustomDrawGridPromotes;
var
  g: TTyCustomDrawGrid;
begin
  g := TThirdDrawGrid.Create(FForm);
  g.Parent := FForm;
  g.RowCount := 4;
  g.FixedRows := 1;
  g.FixedCols := 1;
  g.DefaultRowHeight := 30;
  g.DefaultColWidth := 90;
  g.AutoFillColumns := True;
  g.FocusRectVisible := False;
  g.FadeUnfocusedSelection := False;
  g.GridLineWidth := 2;
  g.OnHeaderClick := @GridHeaderClicked;   // TCustomDrawGrid declares it public (grids.pas:1561)
  AssertEquals('RowCount', 4, g.RowCount);
  AssertEquals('FixedRows', 1, g.FixedRows);
  AssertEquals('FixedCols', 1, g.FixedCols);
  AssertEquals('DefaultRowHeight', 30, g.DefaultRowHeight);
  AssertEquals('DefaultColWidth', 90, g.DefaultColWidth);
  AssertTrue('AutoFillColumns', g.AutoFillColumns);
  AssertFalse('FocusRectVisible', g.FocusRectVisible);
  AssertEquals('GridLineWidth', 2, g.GridLineWidth);
  AssertTrue('OnHeaderClick', Assigned(g.OnHeaderClick));
end;

initialization
  RegisterClasses([TThirdPanel, TThirdGridPanel, TThirdScrollContent, TThirdCoolBar,
    TThirdGroupBox, TThirdRadioGroup, TThirdPageControl, TThirdTabSheet, TThirdListBox,
    TThirdCheckListBox, TIdxListBox, TIdxColorListBox, TIdxStringGrid, TThirdCascader, TThirdTransfer, TThirdTreeView, TThirdListView,
    TThirdStringGrid, TThirdDrawGrid]);
  RegisterTest(TTyCustomClassesP2Test);
end.
