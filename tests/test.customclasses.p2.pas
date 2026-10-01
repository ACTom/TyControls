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
  tyControls.ScrollContent, tyControls.ControlBar, tyControls.CoolBar, tyControls.Button;

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

initialization
  RegisterClasses([TThirdPanel, TThirdGridPanel, TThirdScrollContent, TThirdCoolBar]);
  RegisterTest(TTyCustomClassesP2Test);
end.
