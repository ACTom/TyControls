unit test.partfont;
{ #113: the text INSIDE a control -- a list row, a grid cell, a tab, a segment, a header section,
  an alert's message, a dial's figure, a tree node -- takes the control's Font and its
  StyleOverride, as the control's own text already did. Each control here stands for one way
  a part used to read the theme alone. Seen the way a user sees it: rendered, with the red of
  Font.Color := clRed counted in the result. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, Graphics, Forms, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.ListBox, tyControls.Grid, tyControls.TabSet,
  tyControls.TabStrip, tyControls.Segmented, tyControls.HeaderControl, tyControls.Alert,
  tyControls.Dial, tyControls.ButtonGroup, tyControls.LinkLabel, tyControls.TreeView,
  tyControls.Edit, tyControls.Panel, tyControls.Popup, test.dpi.support;

type
  TPartFontTest = class(TTestCase)
  private
    FForm: TForm;
    function Snap(AControl: TControl; W, H: Integer): TBGRABitmap;
    function RedIn(B: TBGRABitmap; const R: TRect): Integer;
    function InkIn(B: TBGRABitmap; const R: TRect): Integer;
    procedure Redden(AControl: TControl);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestListRowsTakeTheListsFont;
    procedure TestASelectedRowKeepsItsHighlightInk;
    procedure TestGridCellsTakeTheGridsFont;
    procedure TestTabsTakeTheStripsFont;
    procedure TestSegmentsTakeTheControlsFont;
    procedure TestHeaderSectionsTakeTheHeadersFont;
    procedure TestAnAlertsMessageTakesItsFont;
    procedure TestTreeNodesTakeTheTreesFont;
    procedure TestADialsFigureTakesASizeSetOnIt;
    procedure TestButtonGroupSegmentsTakeTheStyleOverride;
    procedure TestALinkTakesTheStyleOverridesColour;
    procedure TestAPopupsContentTakesItsAnchorsFont;
  end;

implementation

type
  TListAcc = class(TTyListBox);
  TGridAcc = class(TTyStringGrid);
  TTabAcc = class(TTyTabSet);
  TSegAcc = class(TTySegmented);
  THdrAcc = class(TTyHeaderControl);
  TTreeAcc = class(TTyTreeView);
  TDialAcc = class(TTyDial);
  TGroupAcc = class(TTyButtonGroup);
  TLinkAcc = class(TTyLinkLabel);
  TAlertAcc = class(TTyAlert);
  TEditAcc = class(TTyEdit)
  public
    function Size: Integer;
    function Face: string;
  end;

function TEditAcc.Size: Integer;
begin
  Result := ResolveFontSize(CurrentStyle);
end;

function TEditAcc.Face: string;
begin
  Result := CurrentStyle.FontName;
end;

procedure TPartFontTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TPartFontTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TPartFontTest.Snap(AControl: TControl; W, H: Integer): TBGRABitmap;
var
  bmp: TBitmap;
  R: TRect;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(W, H);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, W, H);
    R := Rect(0, 0, W, H);
    if AControl is TTyListBox then TListAcc(AControl).RenderTo(bmp.Canvas, R, 96)
    else if AControl is TTyStringGrid then TGridAcc(AControl).RenderTo(bmp.Canvas, R, 96)
    else if AControl is TTyTabSet then TTabAcc(AControl).RenderTo(bmp.Canvas, R, 96)
    else if AControl is TTySegmented then TSegAcc(AControl).RenderTo(bmp.Canvas, R, 96)
    else if AControl is TTyHeaderControl then THdrAcc(AControl).RenderTo(bmp.Canvas, R, 96)
    else if AControl is TTyAlert then TAlertAcc(AControl).RenderTo(bmp.Canvas, R, 96)
    else if AControl is TTyTreeView then TTreeAcc(AControl).RenderTo(bmp.Canvas, R, 96)
    else if AControl is TTyButtonGroup then TGroupAcc(AControl).RenderTo(bmp.Canvas, R, 96)
    else if AControl is TTyLinkLabel then TLinkAcc(AControl).RenderTo(bmp.Canvas, R, 96)
    else if AControl is TTyDial then
    begin
      AControl.SetBounds(0, 0, W, H);
      TyTestPaintTree(AControl, bmp, nil);
    end;
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function TPartFontTest.RedIn(B: TBGRABitmap; const R: TRect): Integer;
var
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := 0;
  for y := R.Top to R.Bottom - 1 do
    for x := R.Left to R.Right - 1 do
    begin
      px := B.GetPixel(x, y);
      if (px.red > 170) and (px.green < 100) and (px.blue < 100) then Inc(Result);
    end;
end;

function TPartFontTest.InkIn(B: TBGRABitmap; const R: TRect): Integer;
var
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := 0;
  for y := R.Top to R.Bottom - 1 do
    for x := R.Left to R.Right - 1 do
    begin
      px := B.GetPixel(x, y);
      if (px.red < 140) and (px.green < 140) and (px.blue < 140) then Inc(Result);
    end;
end;

procedure TPartFontTest.Redden(AControl: TControl);
begin
  AControl.Font.Color := clRed;
  AControl.Font.Style := [fsBold];
end;

procedure TPartFontTest.TestListRowsTakeTheListsFont;
var
  l: TTyListBox;
  b: TBGRABitmap;
begin
  l := TTyListBox.Create(nil);
  try
    l.SetBounds(0, 0, 200, 80);
    l.Items.Add('MMMM WWWW');
    l.Items.Add('HHHH NNNN');
    Redden(l);
    b := Snap(l, 200, 80);
    try
      AssertTrue('the rows are drawn in the list''s red', RedIn(b, Rect(0, 0, 200, 80)) > 10);
    finally
      b.Free;
    end;
  finally
    l.Free;
  end;
end;

procedure TPartFontTest.TestASelectedRowKeepsItsHighlightInk;
var
  l: TTyListBox;
  b: TBGRABitmap;
  rowH: Integer;
begin
  l := TTyListBox.Create(nil);
  try
    l.SetBounds(0, 0, 200, 80);
    l.Items.Add('MMMM WWWW');
    l.Items.Add('HHHH NNNN');
    l.ItemIndex := 0;
    Redden(l);
    rowH := l.ItemHeight;
    b := Snap(l, 200, 80);
    try
      AssertEquals('the selected row keeps the theme''s highlight ink', 0,
        RedIn(b, Rect(0, 0, 200, rowH)));
      AssertTrue('the other row is red', RedIn(b, Rect(0, rowH, 200, 2 * rowH)) > 10);
    finally
      b.Free;
    end;
  finally
    l.Free;
  end;
end;

procedure TPartFontTest.TestGridCellsTakeTheGridsFont;
var
  g: TTyStringGrid;
  b: TBGRABitmap;
begin
  g := TTyStringGrid.Create(nil);
  try
    g.SetBounds(0, 0, 300, 160);
    g.Header.Columns.Add;
    g.Header.Columns.Add;
    g.RowCount := 3;
    g.Cells[0, 0] := 'MMMM';
    g.Cells[1, 1] := 'WWWW';
    Redden(g);
    b := Snap(g, 300, 160);
    try
      AssertTrue('the cells are drawn in the grid''s red', RedIn(b, Rect(0, 0, 300, 160)) > 10);
    finally
      b.Free;
    end;
  finally
    g.Free;
  end;
end;

procedure TPartFontTest.TestTabsTakeTheStripsFont;
var
  t: TTyTabSet;
  b: TBGRABitmap;
begin
  t := TTyTabSet.Create(nil);
  try
    t.SetBounds(0, 0, 300, 32);
    t.Tabs.Add('MMMM');
    t.Tabs.Add('WWWW');
    t.TabIndex := 0;
    Redden(t);
    b := Snap(t, 300, 32);
    try
      AssertTrue('the other tab is drawn in the strip''s red', RedIn(b, Rect(0, 0, 300, 32)) > 10);
    finally
      b.Free;
    end;
  finally
    t.Free;
  end;
end;

procedure TPartFontTest.TestSegmentsTakeTheControlsFont;
var
  s: TTySegmented;
  b: TBGRABitmap;
begin
  s := TTySegmented.Create(nil);
  try
    s.SetBounds(0, 0, 240, 32);
    s.Items.Add('MMMM');
    s.Items.Add('WWWW');
    s.ItemIndex := 0;
    Redden(s);
    b := Snap(s, 240, 32);
    try
      AssertTrue('the unselected segment is red', RedIn(b, Rect(0, 0, 240, 32)) > 10);
    finally
      b.Free;
    end;
  finally
    s.Free;
  end;
end;

procedure TPartFontTest.TestHeaderSectionsTakeTheHeadersFont;
var
  h: TTyHeaderControl;
  b: TBGRABitmap;
begin
  h := TTyHeaderControl.Create(nil);
  try
    h.SetBounds(0, 0, 300, 28);
    h.AddSection('MMMM WWWW', 150);
    Redden(h);
    b := Snap(h, 300, 28);
    try
      AssertTrue('the section is drawn in the header''s red', RedIn(b, Rect(0, 0, 300, 28)) > 10);
    finally
      b.Free;
    end;
  finally
    h.Free;
  end;
end;

procedure TPartFontTest.TestAnAlertsMessageTakesItsFont;
var
  a: TTyAlert;
  b: TBGRABitmap;
begin
  a := TTyAlert.Create(nil);
  try
    a.SetBounds(0, 0, 300, 48);
    a.Message := 'MMMM WWWW';
    Redden(a);
    b := Snap(a, 300, 48);
    try
      AssertTrue('the message is red', RedIn(b, Rect(0, 0, 300, 48)) > 10);
    finally
      b.Free;
    end;
  finally
    a.Free;
  end;
end;

procedure TPartFontTest.TestTreeNodesTakeTheTreesFont;
var
  t: TTyTreeView;
  b: TBGRABitmap;
begin
  t := TTyTreeView.Create(nil);
  try
    t.SetBounds(0, 0, 200, 80);
    t.Items.Add(nil, 'MMMM WWWW');
    Redden(t);
    b := Snap(t, 200, 80);
    try
      AssertTrue('the node is drawn in the tree''s red', RedIn(b, Rect(0, 0, 200, 80)) > 10);
    finally
      b.Free;
    end;
  finally
    t.Free;
  end;
end;

procedure TPartFontTest.TestADialsFigureTakesASizeSetOnIt;
var
  d: TTyDial;
  b: TBGRABitmap;
  small, big: Integer;
begin
  d := TTyDial.Create(FForm);
  d.Parent := FForm;
  d.ShowValue := True;
  b := Snap(d, 160, 160);
  try
    small := InkIn(b, Rect(40, 60, 120, 100));
  finally
    b.Free;
  end;
  d.Font.Size := 28;
  b := Snap(d, 160, 160);
  try
    big := InkIn(b, Rect(40, 60, 120, 100));
  finally
    b.Free;
  end;
  AssertTrue(Format('the figure grows with the size set on the dial (%d -> %d)', [small, big]),
    big > small * 2);
end;

procedure TPartFontTest.TestButtonGroupSegmentsTakeTheStyleOverride;
var
  g: TTyButtonGroup;
  b: TBGRABitmap;
  red0, red1: Integer;
begin
  g := TTyButtonGroup.Create(nil);
  try
    g.SetBounds(0, 0, 240, 32);
    g.Items.Add('One');
    g.Items.Add('Two');
    g.ItemIndex := 0;
    g.StyleOverride := 'background: #ff0000;';
    b := Snap(g, 240, 32);
    try
      red0 := RedIn(b, Rect(2, 2, 118, 30));    // the selected segment
      red1 := RedIn(b, Rect(122, 2, 238, 30));  // the other one
    finally
      b.Free;
    end;
    AssertTrue('the unselected segment takes the override''s red', red1 > 500);
    AssertTrue('the selected one keeps its highlight', red0 < red1 div 4);
  finally
    g.Free;
  end;
end;

procedure TPartFontTest.TestALinkTakesTheStyleOverridesColour;
var
  l: TTyLinkLabel;
  b: TBGRABitmap;
begin
  l := TTyLinkLabel.Create(nil);
  try
    l.SetBounds(0, 0, 200, 24);
    l.Caption := 'MMMM WWWW';
    l.Font.Style := [fsBold];
    l.StyleOverride := 'color: #ff0000;';
    b := Snap(l, 200, 24);
    try
      AssertTrue('the link is drawn in the override''s red', RedIn(b, Rect(0, 0, 200, 24)) > 10);
    finally
      b.Free;
    end;
  finally
    l.Free;
  end;
end;

procedure TPartFontTest.TestAPopupsContentTakesItsAnchorsFont;
var
  panel: TTyPanel;
  anchor: TTyEdit;
  pop: TForm;
  content, ref: TEditAcc;
begin
  panel := TTyPanel.Create(FForm);
  panel.Parent := FForm;
  anchor := TTyEdit.Create(FForm);
  anchor.Parent := panel;
  pop := TForm.CreateNew(nil);
  try
    content := TEditAcc.Create(pop);
    content.Parent := pop;
    ref := TEditAcc.Create(pop);
    ref.Parent := pop;
    FForm.Font.Name := 'Courier New';   // the form's: not the anchor's to hand on
    panel.Font.Size := ref.Size + 6;   // set on the anchor's container: it is the anchor's
    TyHandPopupFont(pop, content, anchor);
    AssertEquals('the content takes the size its anchor shows', ref.Size + 6, content.Size);
    AssertEquals('and not the form''s face', ref.Face, content.Face);
  finally
    pop.Free;
  end;
end;

initialization
  RegisterTest(TPartFontTest);
end.
