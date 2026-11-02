unit test.cursorloan;

{$mode objfpc}{$H+}

{ #154: a control that shows a cursor or a hint for a while -- over a divider, a resize edge,
  a hinted grid cell -- gives its own Cursor, Hint and ShowHint back afterwards. They were
  overwritten on every mouse move, so what the application or the designer set was lost. }

interface

uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Columns, tyControls.Grid, tyControls.ValueListEditor, tyControls.Splitter,
  tyControls.Form;

type
  TLoanGrid = class(TTyStringGrid)
  public
    function CellMid(ACol, ARow: Integer): TPoint;
    function HeaderMidY: Integer;
  end;

  TCursorLoanTest = class(TTestCase)
  private
    FForm: TForm;
    function NewGrid: TLoanGrid;
    procedure CellHint(Sender: TObject; ACol, ARow: Integer; var AHint: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGridGivesItsCursorBack;
    procedure TestTheGridGivesItsHintBack;
    procedure TestTheValueListEditorGivesItsCursorBack;
    procedure TestASplitterKeepsAChosenCursor;
    procedure TestATyFormKeepsItsCursor;
    {$IFDEF LCLWin32}
    procedure TestTheTitleBarGivesItsCursorBack;
    {$ENDIF}
  end;

implementation

type
  TCrack = class(TControl);

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

function TLoanGrid.CellMid(ACol, ARow: Integer): TPoint;
var
  r: TRect;
begin
  r := CellRect(ACol, ARow);
  Result := Point((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
end;

function TLoanGrid.HeaderMidY: Integer;
begin
  Result := HeaderHeightPx div 2;
end;

procedure TCursorLoanTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 500, 400);
end;

procedure TCursorLoanTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TCursorLoanTest.NewGrid: TLoanGrid;
var
  i: Integer;
  c: TTyColumn;
begin
  Result := TLoanGrid.Create(FForm);
  Result.Parent := FForm;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 240);
  for i := 0 to 2 do
  begin
    c := Result.Header.Columns.Add as TTyColumn;
    c.Width := 80;
    c.Text := 'C' + IntToStr(i);
  end;
  Result.RowCount := 5;
end;

procedure TCursorLoanTest.CellHint(Sender: TObject; ACol, ARow: Integer; var AHint: string);
begin
  if ACol = 0 then AHint := 'cell' else AHint := '';
end;

procedure TCursorLoanTest.TestTheGridGivesItsCursorBack;
var
  g: TLoanGrid;
  p: TPoint;
begin
  g := NewGrid;
  g.Cursor := crHandPoint;
  TCrack(g).MouseMove([], 80, g.HeaderMidY);   // on the first column's divider
  AssertEquals('over a header divider: the resize cursor', Ord(crHSplit), Ord(g.Cursor));
  p := g.CellMid(0, 1);
  TCrack(g).MouseMove([], p.X, p.Y);
  AssertEquals('off it: the grid''s own cursor again', Ord(crHandPoint), Ord(g.Cursor));
end;

procedure TCursorLoanTest.TestTheGridGivesItsHintBack;
var
  g: TLoanGrid;
  p: TPoint;
begin
  g := NewGrid;
  g.Options := g.Options + [goCellHints];
  g.OnGetCellHint := @CellHint;
  g.Hint := 'grid';
  AssertTrue('setup: the grid follows its parent''s ShowHint', g.ParentShowHint);
  p := g.CellMid(0, 1);
  TCrack(g).MouseMove([], p.X, p.Y);
  AssertEquals('over a hinted cell: the cell''s hint', 'cell', g.Hint);
  AssertTrue('shown', g.ShowHint);
  p := g.CellMid(1, 1);
  TCrack(g).MouseMove([], p.X, p.Y);
  AssertEquals('over a cell with none: the grid''s own hint', 'grid', g.Hint);
  AssertTrue('and its own ParentShowHint', g.ParentShowHint);
  p := g.CellMid(0, 2);
  TCrack(g).MouseMove([], p.X, p.Y);
  AssertEquals('setup: a hinted cell again', 'cell', g.Hint);
  TCrack(g).MouseLeave;
  AssertEquals('the mouse gone: the grid''s own hint', 'grid', g.Hint);
  AssertTrue('and its own ParentShowHint', g.ParentShowHint);
end;

procedure TCursorLoanTest.TestTheValueListEditorGivesItsCursorBack;
var
  v: TTyValueListEditor;
  x: Integer;
  sawSplit: Boolean;
begin
  v := TTyValueListEditor.Create(FForm);
  v.Parent := FForm;
  v.Font.PixelsPerInch := 96;
  v.SetBounds(0, 0, 300, 200);
  v.AddRow('Name', 'Value');
  v.Cursor := crHandPoint;
  sawSplit := False;
  for x := 0 to v.ClientWidth - 1 do
  begin
    TCrack(v).MouseMove([], x, 10);
    if v.Cursor = crHSplit then
    begin
      sawSplit := True;
      Break;
    end;
  end;
  AssertTrue('setup: the key/value divider shows the resize cursor', sawSplit);
  TCrack(v).MouseMove([], v.ClientWidth - 10, 10);
  AssertEquals('off it: the editor''s own cursor again', Ord(crHandPoint), Ord(v.Cursor));
end;

procedure TCursorLoanTest.TestASplitterKeepsAChosenCursor;
var
  s, plain: TTySplitter;
begin
  s := TTySplitter.Create(FForm);
  s.Parent := FForm;
  s.Align := alLeft;
  s.Cursor := crSizeAll;
  TCrack(s).MouseEnter;
  AssertEquals('a cursor of its own stays over a hover', Ord(crSizeAll), Ord(s.Cursor));

  plain := TTySplitter.Create(FForm);
  plain.Parent := FForm;
  plain.Align := alTop;
  TCrack(plain).MouseEnter;
  AssertEquals('the derived cursor still follows Align', Ord(crVSplit), Ord(plain.Cursor));
end;

procedure TCursorLoanTest.TestATyFormKeepsItsCursor;
var
  f: TTyForm;
begin
  f := TTyForm.CreateNew(nil);
  try
    f.SetBounds(0, 0, 400, 300);
    f.Cursor := crHourGlass;
    TCrack(f).MouseMove([], 200, 150);
    AssertEquals('a move over the form keeps the form''s own cursor', Ord(crHourGlass), Ord(f.Cursor));
  finally
    f.Free;
  end;
end;

{$IFDEF LCLWin32}
procedure TCursorLoanTest.TestTheTitleBarGivesItsCursorBack;
var
  f: TTyForm;
  b: TTyTitleBar;
begin
  f := TTyForm.CreateNew(nil);
  b := TTyTitleBar.Create(f);
  try
    f.SetBounds(0, 0, 400, 300);
    b.Parent := f;
    f.TitleBar := b;
    b.Cursor := crHandPoint;
    TCrack(b).MouseMove([], 100, 0);   // the top resize zone
    AssertEquals('setup: the top edge shows the resize cursor', Ord(crSizeNS), Ord(b.Cursor));
    TCrack(b).MouseMove([], 100, b.Height - 2);
    AssertEquals('below it: the bar''s own cursor again', Ord(crHandPoint), Ord(b.Cursor));
  finally
    f.Free;
  end;
end;
{$ENDIF}

initialization
  RegisterTest(TCursorLoanTest);
end.
