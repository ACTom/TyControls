unit test.listviewprops;
{ #125: TTyListView has one sort state with its Header -- Header.SortColumn / SortDirection sort
  the list, the list's own two show in the header, and a form file carries them once;
  Header.AutoSizeIndex fills the rest of the width; RowSelect = False highlights the main
  column only; an inline rename reads and writes Header.MainColumn's text; and AutoSort only
  governs the header click, as LCL's -- a list with a SortColumn stays sorted as items change. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, LCLType, Controls, Forms, fpcunit, testregistry,
  tyControls.Edit, tyControls.Columns, tyControls.ListView.Layout, tyControls.ListView;

type
  TLvProbe = class(TTyListView)
  public
    function ItemAtRow(APos: Integer): Integer;
    function Editor: TTyEdit;
    procedure Render(ABmp: TBitmap);
    procedure ClickAt(X, Y: Integer);
  end;

  TListViewPropsTest = class(TTestCase)
  private
    function NewReport: TLvProbe;
    function CaptionAtRow(L: TLvProbe; APos: Integer): string;
  published
    procedure TestHeaderSortColumnSortsTheList;
    procedure TestTheListsSortShowsInTheHeader;
    procedure TestAFormFileCarriesTheSortOnce;
    procedure TestAHandWrittenHeaderSortLoads;
    procedure TestAHeaderClickShowsInTheHeader;
    procedure TestAutoSizeIndexFillsTheRest;
    procedure TestWithoutRowSelectOnlyTheMainColumnIsHighlighted;
    procedure TestARenameEditsTheMainColumn;
    procedure TestASortedListStaysSortedWithoutAutoSort;
    procedure TestASortedListPaintsSortedInsideAnUpdate;
  end;

implementation

function TLvProbe.ItemAtRow(APos: Integer): Integer;
begin
  Result := DisplayToItem(APos);
end;

function TLvProbe.Editor: TTyEdit;
begin
  Result := InlineEditor;
end;

procedure TLvProbe.Render(ABmp: TBitmap);
begin
  ABmp.PixelFormat := pf32bit;
  ABmp.SetSize(Width, Height);
  RenderTo(ABmp.Canvas, Rect(0, 0, Width, Height), 96);
end;

procedure TLvProbe.ClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

function TListViewPropsTest.NewReport: TLvProbe;
const
  W: array[0..2] of Integer = (100, 50, 80);
var
  i: Integer;
  c: TTyColumn;
  it: TTyListItem;
begin
  Result := TLvProbe.Create(nil);
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 300, 200);
  Result.ViewStyle := lvsReport;
  for i := 0 to 2 do
  begin
    c := Result.Header.Columns.Add as TTyColumn;
    c.Width := W[i];
  end;
  for i := 0 to 2 do
  begin
    it := Result.Items.Add;
    it.Caption := Chr(Ord('c') - i);   // c, b, a
    it.SubItems.Add('s' + IntToStr(i));
    it.SubItems.Add('');
  end;
end;

function TListViewPropsTest.CaptionAtRow(L: TLvProbe; APos: Integer): string;
begin
  Result := L.Items[L.ItemAtRow(APos)].Caption;
end;

procedure TListViewPropsTest.TestHeaderSortColumnSortsTheList;
var
  l: TLvProbe;
begin
  l := NewReport;
  try
    l.Header.SortColumn := 0;
    AssertEquals('the list sorts by it', 'a', CaptionAtRow(l, 0));
    AssertEquals('and says so', 0, l.SortColumn);
    l.Header.SortDirection := sdDescending;
    AssertEquals('the direction too', 'c', CaptionAtRow(l, 0));
  finally
    l.Free;
  end;
end;

procedure TListViewPropsTest.TestTheListsSortShowsInTheHeader;
var
  l: TLvProbe;
begin
  l := NewReport;
  try
    l.SortColumn := 1;
    l.SortDirection := sdDescending;
    AssertEquals('the header''s arrow column', 1, l.Header.SortColumn);
    AssertTrue('and direction', l.Header.SortDirection = sdDescending);
  finally
    l.Free;
  end;
end;

procedure TListViewPropsTest.TestAFormFileCarriesTheSortOnce;
var
  f: TForm;
  l: TTyListView;
  ms, ts: TMemoryStream;
  txt: TStringList;
begin
  f := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  ts := TMemoryStream.Create;
  txt := TStringList.Create;
  try
    l := TTyListView.Create(f);
    l.Name := 'LV';
    l.Parent := f;
    l.SortColumn := 1;
    ms.WriteComponent(f);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    txt.LoadFromStream(ts);
    AssertTrue('under the name it always had' + LineEnding + txt.Text,
      Pos('SortColumn = 1', txt.Text) > 0);
    AssertEquals('and not again under the header''s' + LineEnding + txt.Text, 0,
      Pos('Header.SortColumn', txt.Text));
  finally
    txt.Free;
    ts.Free;
    ms.Free;
    f.Free;
  end;
end;

procedure TListViewPropsTest.TestAHandWrittenHeaderSortLoads;
const
  LFM =
    'object F: TForm' + LineEnding +
    '  object LV: TTyListView' + LineEnding +
    '    Header.SortColumn = 1' + LineEnding +
    '    Header.SortDirection = sdDescending' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
var
  f: TForm;
  ts: TStringStream;
  bs: TMemoryStream;
  l: TTyListView;
begin
  f := TForm.CreateNew(nil);
  ts := TStringStream.Create(LFM);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    bs.ReadComponent(f);
    l := f.FindComponent('LV') as TTyListView;
    AssertEquals('the list sorts by the header''s column', 1, l.SortColumn);
    AssertTrue('and direction', l.SortDirection = sdDescending);
  finally
    bs.Free;
    ts.Free;
    f.Free;
  end;
end;

procedure TListViewPropsTest.TestAHeaderClickShowsInTheHeader;
var
  l: TLvProbe;
begin
  l := NewReport;
  try
    l.ClickAt(40, 5);   // on the first column's header
    AssertEquals('the click sorts', 'a', CaptionAtRow(l, 0));
    AssertEquals('and the header shows it', 0, l.Header.SortColumn);
    l.Header.Options := l.Header.Options;   // any later header change
    AssertEquals('which does not undo it', 0, l.SortColumn);
  finally
    l.Free;
  end;
end;

procedure TListViewPropsTest.TestAutoSizeIndexFillsTheRest;
var
  l: TLvProbe;
  c1: TTyColumn;
begin
  l := NewReport;
  try
    c1 := l.Header.Columns.Items[1] as TTyColumn;
    l.Header.AutoSizeIndex := 1;
    l.Header.Options := l.Header.Options + [hoAutoResize];
    AssertEquals('the auto column takes the rest', 300 - 180, c1.Width);
    (l.Header.Columns.Items[0] as TTyColumn).Width := 150;
    AssertEquals('and gives up what a neighbour took', 300 - 230, c1.Width);
  finally
    l.Free;
  end;
end;

procedure TListViewPropsTest.TestWithoutRowSelectOnlyTheMainColumnIsHighlighted;
var
  sel, plain: TLvProbe;
  a, b: TBitmap;
  x, y: Integer;
begin
  sel := NewReport;
  plain := NewReport;
  a := TBitmap.Create;
  b := TBitmap.Create;
  try
    sel.RowSelect := False;
    plain.RowSelect := False;
    sel.ItemIndex := 0;
    sel.Render(a);
    plain.Render(b);
    { The first scan line where the main column's leading edge is highlighted. }
    y := -1;
    for x := 0 to a.Height - 1 do
      if ColorToRGB(b.Canvas.Pixels[4, x]) <> ColorToRGB(a.Canvas.Pixels[4, x]) then
      begin
        y := x;
        Break;
      end;
    AssertTrue('the main column is highlighted', y >= 0);
    { Past the main column the two lists paint alike: no highlight, and the other columns'
      text in the ink of a row that is not selected. }
    for y := 0 to a.Height - 1 do
      for x := 102 to a.Width - 1 do
        if ColorToRGB(b.Canvas.Pixels[x, y]) <> ColorToRGB(a.Canvas.Pixels[x, y]) then
          Fail(Format('the other columns of the selected row are not highlighted (%d,%d)', [x, y]));
  finally
    a.Free;
    b.Free;
    sel.Free;
    plain.Free;
  end;
end;

procedure TListViewPropsTest.TestARenameEditsTheMainColumn;
var
  l: TLvProbe;
  k: Word;
begin
  l := NewReport;
  try
    l.ReadOnly := False;
    l.Header.MainColumn := 1;
    l.BeginEdit(0);
    AssertEquals('it opens on the main column''s text', 's0', l.Editor.Text);
    l.Editor.Text := 'renamed';
    k := VK_RETURN;
    l.Editor.OnKeyDown(l.Editor, k, []);
    AssertEquals('and writes it back there', 'renamed', l.Items[0].SubItems[0]);
    AssertEquals('leaving the caption alone', 'c', l.Items[0].Caption);
  finally
    l.Free;
  end;
end;

procedure TListViewPropsTest.TestASortedListStaysSortedWithoutAutoSort;
var
  l: TLvProbe;
begin
  l := NewReport;
  try
    l.AutoSort := False;
    l.SortColumn := 0;
    l.Items.Add.Caption := '0';
    AssertEquals('a new item takes its sorted place', '0', CaptionAtRow(l, 0));
  finally
    l.Free;
  end;
end;

procedure TListViewPropsTest.TestASortedListPaintsSortedInsideAnUpdate;
var
  l: TLvProbe;
  b: TBitmap;
begin
  l := NewReport;
  b := TBitmap.Create;
  try
    l.AutoSort := False;
    l.SortColumn := 0;
    l.BeginUpdate;
    try
      l.Items.Add.Caption := '0';
      l.Render(b);   // a paint inside the update settles the order itself
      AssertEquals('sorted there too', '0', CaptionAtRow(l, 0));
    finally
      l.EndUpdate;
    end;
  finally
    b.Free;
    l.Free;
  end;
end;

initialization
  RegisterTest(TListViewPropsTest);
end.
