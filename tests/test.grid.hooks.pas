unit test.grid.hooks;
{ The hooks a subclass of the string grid builds on (#34, the data-aware grid):
  GetEditText / SetEditText, ColumnClass, DoVScroll and CursorMoved; and (TGridHeaderHooksTest)
  the header gestures a subclass hears about -- HeaderSectionClicked, ColumnSized,
  ColumnMoved -- and the CanToggleCellCheck veto.

  A probe subclass keeps its own values next to the cell store and answers GetEditText
  from them, so every assertion can tell "came through the hook" from "came from the
  store": the two always hold different strings. SetEditText is logged and never passed
  on, so the store staying as it was proves a write did not go round the hook.

  The defaults (read and write Cells) are pinned by every other grid suite passing
  unchanged; this unit pins that the hooks are where the grid actually reads and writes. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, LCLType,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Columns, tyControls.Edit, tyControls.ScrollBar,
  tyControls.ComboBox, tyControls.DateTimePicker, tyControls.SpinEdit,
  tyControls.TrackBar, tyControls.Memo, tyControls.MaskEdit, tyControls.CalcEdit,
  tyControls.Grid;

type
  TProbeColumn = class(TTyGridColumn);

  { A host editor that only records what the grid hands it. }
  TProbeLink = class(TTyGridEditLink)
  public
    Edit: TTyEdit;
    GivenValue: string;
    function  CreateEditor(AParent: TWinControl; ACol, ARow: Integer): TWinControl; override;
    procedure SetBounds(const ARect: TRect); override;
    function  GetValue: string; override;
    procedure SetValue(const AValue: string); override;
    procedure FocusEditor; override;
    procedure ReleaseEditor; override;
  end;

  THookGrid = class(TTyStringGrid)
  protected
    function  GetEditText(ACol, ARow: Integer): string; override;
    procedure SetEditText(ACol, ARow: Integer; const AText: string); override;
    procedure CursorMoved(AOldCol, AOldRow: Integer); override;
    procedure DoVScroll(APosition: Integer); override;
    function  ColumnClass: TTyGridColumnClass; override;
  public
    { 'col:row=text' -- what GetEditText answers for that cell. A cell not listed falls
      back to the store. }
    Probe: TStringList;
    { One 'col:row=text' line per SetEditText call, in order. }
    Writes: TStringList;
    { One 'oldcol:oldrow>col:row' line per CursorMoved call. }
    Moves: TStringList;
    { The positions DoVScroll was handed. }
    VScrolls: TStringList;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetProbe(ACol, ARow: Integer; const AText: string);
    function  PressKey(AKey: Word): Boolean;
    procedure ClickCell(ACol, ARow: Integer);
    procedure ClickStar(ACol, ARow, AStar: Integer);
    procedure Ellipsis(ACol, ARow: Integer);
    function  ScrollPos: Integer;
    function  TextEd: TTyEdit;
    function  Spin: TTySpinEdit;
    function  Slider: TTyTrackBar;
    function  Memo: TTyMemo;
    function  Mask: TTyMaskEdit;
    function  Calc: TTyCalcEdit;
    function  Picker: TTyDateTimePicker;
    function  Pick: TTyComboBox;
  end;

  { Logs the header hooks; CanToggleCellCheck answers Allow. }
  THeaderHookGrid = class(TTyStringGrid)
  protected
    procedure HeaderSectionClicked(ACol: Integer); override;
    procedure ColumnSized(ACol: Integer); override;
    procedure ColumnMoved(AFromPos, AToPos: Integer); override;
    function CanToggleCellCheck(ACol, ARow: Integer): Boolean; override;
  public
    Log: TStringList;
    Allow: Boolean;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function TitlePoint(ACol: Integer): TPoint;
    function DividerPoint(ACol: Integer): TPoint;
    procedure Press(const APt: TPoint);
    procedure DragTo(const APt: TPoint);
    procedure Release(const APt: TPoint);
    function PressKey(AKey: Word): Word;
  end;

  TGridHeaderHooksTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: THeaderHookGrid;
    FChanges, FEdits: Integer;
    procedure CountChange(Sender: TObject; ACol, ARow: Integer; AChecked: Boolean);
    procedure CountEdit(Sender: TObject; ACol, ARow: Integer; const AOldText,
      ANewText: string; var AAccept: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestATitleClickReachesHeaderSectionClicked;
    procedure TestADividerDragReachesColumnSizedOnly;
    procedure TestAColumnDragReachesColumnMovedOnly;
    procedure TestCanToggleCellCheckVetoesTheWholeToggle;
  end;

  TGridHooksTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: THookGrid;
    FLink: TProbeLink;
    FVeto: Boolean;
    procedure Build(ACols, ARows: Integer);
    function  Col1: TTyGridColumn;
    procedure CreateLink(Sender: TObject; ACol, ARow: Integer; var ALink: TTyGridEditLink);
    procedure PickedByHost(Sender: TObject; ACol, ARow: Integer;
      var ANewText: string; var AAccept: Boolean);
    procedure VetoMove(Sender: TObject; ACol, ARow: Integer; var ACanSelect: Boolean);
    { Opens (1, 2) with AKind, store AStore and probe AProbe; answers what the editor shows. }
    function  OpenWith(AKind: TTyGridEditorKind; const AStore, AProbe: string): string;
    procedure AssertWroteOnly(const AMsg, AExpectedLine: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryEditorOpensWithGetEditText;
    procedure TestAHostEditLinkOpensWithGetEditText;
    procedure TestEveryEditorCommitsThroughSetEditText;
    procedure TestAnUnchangedEditIsComparedWithGetEditText;
    procedure TestTheCheckBoxToggleWritesThroughSetEditText;
    procedure TestRatingAndEllipsisWriteThroughSetEditText;
    procedure TestPasteWritesThroughSetEditText;
    procedure TestFillHandleWritesThroughSetEditText;
    procedure TestReplaceAndBandClearWriteThroughSetEditText;
    procedure TestNoUserEditWritesTheStoreDirectly;
    procedure TestColumnClassIsWhatTheHeaderCreates;
    procedure TestDoVScrollSeesTheBarAndNotTheGridsOwnPush;
    procedure TestCursorMovedAfterKeyboardAndMouseMoves;
    procedure TestCursorMovedNotAfterAVetoOrANoOp;
  end;

implementation

uses
  StrUtils;

var
  ColumnClassCalls: Integer = 0;

function Key(ACol, ARow: Integer): string;
begin
  Result := IntToStr(ACol) + ':' + IntToStr(ARow);
end;

{ ---- TProbeLink ---- }

function TProbeLink.CreateEditor(AParent: TWinControl; ACol, ARow: Integer): TWinControl;
begin
  Edit := TTyEdit.Create(nil);
  Edit.Parent := AParent;
  Result := Edit;
end;

procedure TProbeLink.SetBounds(const ARect: TRect);
begin
  Edit.BoundsRect := ARect;
end;

function TProbeLink.GetValue: string;
begin
  Result := Edit.Text;
end;

procedure TProbeLink.SetValue(const AValue: string);
begin
  GivenValue := AValue;
  Edit.Text := AValue;
end;

procedure TProbeLink.FocusEditor;
begin
end;

procedure TProbeLink.ReleaseEditor;
begin
  FreeAndNil(Edit);
end;

{ ---- THookGrid ---- }

constructor THookGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Probe := TStringList.Create;
  Writes := TStringList.Create;
  Moves := TStringList.Create;
  VScrolls := TStringList.Create;
end;

destructor THookGrid.Destroy;
begin
  inherited Destroy;
  Probe.Free;
  Writes.Free;
  Moves.Free;
  VScrolls.Free;
end;

function THookGrid.GetEditText(ACol, ARow: Integer): string;
var
  i: Integer;
begin
  i := Probe.IndexOfName(Key(ACol, ARow));
  if i >= 0 then Result := Probe.ValueFromIndex[i]
  else Result := inherited GetEditText(ACol, ARow);
end;

procedure THookGrid.SetEditText(ACol, ARow: Integer; const AText: string);
begin
  { Logged and kept on the probe side; the store is never touched. }
  Writes.Add(Key(ACol, ARow) + '=' + AText);
  Probe.Values[Key(ACol, ARow)] := AText;
end;

procedure THookGrid.CursorMoved(AOldCol, AOldRow: Integer);
begin
  Moves.Add(Key(AOldCol, AOldRow) + '>' + Key(Col, Row));
end;

procedure THookGrid.DoVScroll(APosition: Integer);
begin
  VScrolls.Add(IntToStr(APosition));
  inherited DoVScroll(APosition);
end;

function THookGrid.ColumnClass: TTyGridColumnClass;
begin
  { Runs inside the inherited constructor: no field of this class exists yet. }
  Inc(ColumnClassCalls);
  Result := TProbeColumn;
end;

procedure THookGrid.SetProbe(ACol, ARow: Integer; const AText: string);
begin
  Probe.Values[Key(ACol, ARow)] := AText;
end;

function THookGrid.PressKey(AKey: Word): Boolean;
var
  k: Word;
begin
  k := AKey;
  KeyDown(k, []);
  Result := k = 0;
end;

procedure THookGrid.ClickCell(ACol, ARow: Integer);
var
  r: TRect;
begin
  r := CellVisibleRect(ACol, ARow);
  MouseDown(mbLeft, [], (r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  MouseUp(mbLeft, [], (r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
end;

procedure THookGrid.ClickStar(ACol, ARow, AStar: Integer);
var
  r: TRect;
begin
  r := RatingStarRect(ACol, ARow, AStar);
  SetRatingByPoint(ACol, ARow, (r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
end;

procedure THookGrid.Ellipsis(ACol, ARow: Integer);
begin
  InvokeEllipsis(ACol, ARow);
end;

function THookGrid.ScrollPos: Integer;
begin Result := ScrollY; end;
function THookGrid.TextEd: TTyEdit;
begin Result := InlineEditor; end;
function THookGrid.Spin: TTySpinEdit;
begin Result := SpinEditor; end;
function THookGrid.Slider: TTyTrackBar;
begin Result := SliderEditor; end;
function THookGrid.Memo: TTyMemo;
begin Result := MemoEditor; end;
function THookGrid.Mask: TTyMaskEdit;
begin Result := MaskEditor; end;
function THookGrid.Calc: TTyCalcEdit;
begin Result := CalcEditor; end;
function THookGrid.Picker: TTyDateTimePicker;
begin Result := DateEditor; end;
function THookGrid.Pick: TTyComboBox;
begin Result := PickEditor; end;

{ ---- fixture ---- }

procedure TGridHooksTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 700, 500);
  FVeto := False;
end;

procedure TGridHooksTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FLink);
  FGrid := nil;
end;

procedure TGridHooksTest.Build(ACols, ARows: Integer);
var
  i: Integer;
  c: TTyColumn;
begin
  FGrid := THookGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.Font.PixelsPerInch := 96;
  FGrid.SetBounds(0, 0, 400, 240);
  for i := 0 to ACols - 1 do
  begin
    c := FGrid.Header.Columns.Add as TTyColumn;
    c.Width := 80;
    c.Text := 'C' + IntToStr(i);
  end;
  FGrid.DefaultRowHeight := 20;
  FGrid.RowCount := ARows;
end;

function TGridHooksTest.Col1: TTyGridColumn;
begin
  Result := FGrid.Header.Columns.Items[1] as TTyGridColumn;
end;

procedure TGridHooksTest.CreateLink(Sender: TObject; ACol, ARow: Integer;
  var ALink: TTyGridEditLink);
begin
  if FLink = nil then FLink := TProbeLink.Create;
  ALink := FLink;
end;

procedure TGridHooksTest.PickedByHost(Sender: TObject; ACol, ARow: Integer;
  var ANewText: string; var AAccept: Boolean);
begin
  ANewText := 'from the dialog';
end;

procedure TGridHooksTest.VetoMove(Sender: TObject; ACol, ARow: Integer;
  var ACanSelect: Boolean);
begin
  if FVeto then ACanSelect := False;
end;

function TGridHooksTest.OpenWith(AKind: TTyGridEditorKind;
  const AStore, AProbe: string): string;
var
  kindName: string;
begin
  FGrid.EndEdit(False);
  FGrid.Probe.Clear;
  FGrid.Writes.Clear;
  Col1.EditorKind := AKind;
  Col1.MinValue := 0;
  Col1.MaxValue := 100;
  Col1.PickList.CommaText := 'a,b,c,d';
  FGrid.Cells[1, 2] := AStore;
  FGrid.SetProbe(1, 2, AProbe);
  kindName := IntToStr(Ord(AKind));
  AssertTrue('setup: an editor opens for kind ' + kindName, FGrid.BeginEdit(1, 2));
  case AKind of
    gekPickList:
      if FGrid.Pick.ItemIndex >= 0 then Result := FGrid.Pick.Items[FGrid.Pick.ItemIndex]
      else Result := '';
    gekDate:       Result := DateToStr(FGrid.Picker.Date);
    gekTime:       Result := FormatDateTime('hh:nn', FGrid.Picker.DateTime);
    gekSpin:       Result := IntToStr(FGrid.Spin.Value);
    gekSlider:     Result := IntToStr(FGrid.Slider.Position);
    { TTyMemo.Text answers with a trailing line break (a TStrings habit); not what is
      being pinned here. }
    gekMemo:       Result := TrimRight(FGrid.Memo.Text);
    gekMask:       Result := FGrid.Mask.Text;
    gekCalculator: Result := FGrid.Calc.Text;
    else           Result := FGrid.TextEd.Text;
  end;
end;

procedure TGridHooksTest.AssertWroteOnly(const AMsg, AExpectedLine: string);
begin
  AssertEquals(AMsg + ': one write through SetEditText', 1, FGrid.Writes.Count);
  AssertEquals(AMsg + ': and it is this one', AExpectedLine, FGrid.Writes[0]);
end;

{ ================= edit text ================= }

procedure TGridHooksTest.TestEveryEditorOpensWithGetEditText;
{ Red if any one editor kind reads Cells[] when it opens: the store holds a different,
  equally valid value, so the editor would show that one. }
var
  d1, d2: string;
begin
  Build(4, 10);
  d1 := DateToStr(EncodeDate(2020, 1, 2));
  d2 := DateToStr(EncodeDate(2021, 5, 6));
  AssertEquals('text',       'probe', OpenWith(gekText,       'store', 'probe'));
  AssertEquals('numeric',    '22',    OpenWith(gekNumeric,    '1',     '22'));
  AssertEquals('password',   'probe', OpenWith(gekPassword,   'store', 'probe'));
  AssertEquals('ellipsis',   'probe', OpenWith(gekEllipsis,   'store', 'probe'));
  AssertEquals('pick list',  'c',     OpenWith(gekPickList,   'a',     'c'));
  AssertEquals('date',       d2,      OpenWith(gekDate,       d1,      d2));
  AssertEquals('time',       '13:45', OpenWith(gekTime,       '08:10', '13:45'));
  AssertEquals('spin',       '7',     OpenWith(gekSpin,       '3',     '7'));
  AssertEquals('slider',     '85',    OpenWith(gekSlider,     '40',    '85'));
  AssertEquals('memo',       'probe', OpenWith(gekMemo,       'store', 'probe'));
  AssertEquals('mask',       'probe', OpenWith(gekMask,       'store', 'probe'));
  AssertEquals('calculator', '42',    OpenWith(gekCalculator, '1',     '42'));
  FGrid.EndEdit(False);
end;

procedure TGridHooksTest.TestAHostEditLinkOpensWithGetEditText;
begin
  Build(4, 10);
  FGrid.OnCreateEditLink := @CreateLink;
  FGrid.Cells[1, 2] := 'store';
  FGrid.SetProbe(1, 2, 'probe');
  AssertTrue('setup: the host editor opens', FGrid.BeginEdit(1, 2));
  AssertEquals('the host editor is handed GetEditText', 'probe', FLink.GivenValue);
  FLink.Edit.Text := 'typed';
  FGrid.EndEdit(True);
  AssertWroteOnly('the host editor''s commit', '1:2=typed');
  AssertEquals('the store is untouched', 'store', FGrid.Cells[1, 2]);
end;

procedure TGridHooksTest.TestEveryEditorCommitsThroughSetEditText;
{ Every kind's commit lands in SetEditText and nowhere else: the store keeps its value. }
const
  STORE = 'store';
var
  d1, d2: string;

  procedure Commit(const AMsg, AExpected, AStore: string);
  begin
    FGrid.EndEdit(True);
    AssertWroteOnly(AMsg, '1:2=' + AExpected);
    AssertEquals(AMsg + ': the store is untouched', AStore, FGrid.Cells[1, 2]);
  end;

begin
  Build(4, 10);
  d1 := DateToStr(EncodeDate(2020, 1, 2));
  d2 := DateToStr(EncodeDate(2021, 5, 6));

  OpenWith(gekText, STORE, 'probe');
  FGrid.TextEd.Text := 'new';
  Commit('text', 'new', STORE);

  OpenWith(gekNumeric, '1', '22');
  FGrid.TextEd.Text := '333';
  Commit('numeric', '333', '1');

  OpenWith(gekPickList, 'a', 'c');
  FGrid.Pick.ItemIndex := 1;
  Commit('pick list', 'b', 'a');

  OpenWith(gekDate, d1, d2);
  FGrid.Picker.Date := EncodeDate(2022, 3, 4);
  Commit('date', DateToStr(EncodeDate(2022, 3, 4)), d1);

  OpenWith(gekTime, '08:10', '13:45');
  FGrid.Picker.DateTime := EncodeTime(9, 30, 0, 0);
  Commit('time', '09:30', '08:10');

  OpenWith(gekSpin, '3', '7');
  FGrid.Spin.Value := 9;
  Commit('spin', '9', '3');

  OpenWith(gekSlider, '40', '85');
  FGrid.Slider.Position := 60;
  Commit('slider', '60', '40');

  OpenWith(gekMemo, STORE, 'probe');
  FGrid.Memo.Text := 'new';
  Commit('memo', 'new' + LineEnding, STORE);   { see OpenWith }

  OpenWith(gekMask, STORE, 'probe');
  FGrid.Mask.Text := 'new';
  Commit('mask', 'new', STORE);

  OpenWith(gekCalculator, '1', '42');
  FGrid.Calc.Text := '99';
  Commit('calculator', '99', '1');
end;

procedure TGridHooksTest.TestAnUnchangedEditIsComparedWithGetEditText;
{ The commit decides "changed or not" against GetEditText. Compared with the store, an edit
  the user did not touch would look changed (store 'store' vs editor 'probe') and be
  written back. }
begin
  Build(4, 10);
  OpenWith(gekText, 'store', 'probe');
  FGrid.EndEdit(True);
  AssertEquals('nothing changed, nothing written', 0, FGrid.Writes.Count);

  { The pick list's "nothing chosen" answer is GetEditText too. }
  OpenWith(gekPickList, 'a', 'not in the list');
  AssertEquals('setup: nothing is chosen', -1, FGrid.Pick.ItemIndex);
  FGrid.EndEdit(True);
  AssertEquals('nothing chosen, nothing written', 0, FGrid.Writes.Count);
end;

procedure TGridHooksTest.TestTheCheckBoxToggleWritesThroughSetEditText;
begin
  Build(4, 10);
  Col1.EditorKind := gekCheckBox;
  FGrid.ToggleCellChecked(1, 3);
  AssertWroteOnly('the check box toggle', '1:3=1');
  AssertEquals('the store is untouched', '', FGrid.Cells[1, 3]);

  { The gesture, not just the method: Space on a check box cell. }
  FGrid.Writes.Clear;
  FGrid.MoveCursor(1, 4);
  FGrid.PressKey(VK_SPACE);
  AssertWroteOnly('Space on a check box', '1:4=1');
end;

procedure TGridHooksTest.TestRatingAndEllipsisWriteThroughSetEditText;
begin
  Build(4, 10);
  Col1.EditorKind := gekRating;
  FGrid.ClickStar(1, 2, 3);
  AssertWroteOnly('a star', '1:2=3');
  AssertEquals('the store is untouched', '', FGrid.Cells[1, 2]);

  FGrid.Writes.Clear;
  Col1.EditorKind := gekEllipsis;
  FGrid.OnEllipsisClick := @PickedByHost;
  FGrid.Ellipsis(1, 3);
  AssertWroteOnly('the ellipsis', '1:3=from the dialog');
  AssertEquals('the store is untouched', '', FGrid.Cells[1, 3]);
end;

procedure TGridHooksTest.TestPasteWritesThroughSetEditText;
begin
  Build(4, 10);
  FGrid.MoveCursor(1, 2);
  FGrid.PasteFromText('x'#9'y'#13#10'z'#13#10);
  AssertEquals('three cells pasted, three writes', 3, FGrid.Writes.Count);
  AssertEquals('1:2=x', FGrid.Writes[0]);
  AssertEquals('2:2=y', FGrid.Writes[1]);
  AssertEquals('1:3=z', FGrid.Writes[2]);
  AssertEquals('the store is untouched', 0, FGrid.StoredCellCount);
end;

procedure TGridHooksTest.TestFillHandleWritesThroughSetEditText;
begin
  Build(4, 10);
  FGrid.Cells[0, 0] := '1';
  FGrid.Cells[0, 1] := '2';
  FGrid.SelectRange(0, 0, 0, 1);
  FGrid.FillFromSelectionTo(0, 4);
  AssertEquals('three cells filled, three writes', 3, FGrid.Writes.Count);
  AssertEquals('0:2=3', FGrid.Writes[0]);
  AssertEquals('0:3=4', FGrid.Writes[1]);
  AssertEquals('0:4=5', FGrid.Writes[2]);
  AssertEquals('the store holds only the source', 2, FGrid.StoredCellCount);
end;

procedure TGridHooksTest.TestReplaceAndBandClearWriteThroughSetEditText;
begin
  Build(4, 10);
  FGrid.Cells[1, 1] := 'foo';
  AssertEquals('one replaced', 1, FGrid.ReplaceCells('foo', 'bar', False, True, True));
  AssertWroteOnly('find and replace', '1:1=bar');
  AssertEquals('the store is untouched', 'foo', FGrid.Cells[1, 1]);

  FGrid.Writes.Clear;
  FGrid.ClearRowContents(1, 1);
  AssertEquals('a row of four cells, four writes', 4, FGrid.Writes.Count);
  AssertEquals('1:1=', FGrid.Writes[1]);
  AssertEquals('the store is untouched', 'foo', FGrid.Cells[1, 1]);

  FGrid.Writes.Clear;
  FGrid.ClearColContents(1, 1);
  AssertEquals('a column of ten cells, ten writes', 10, FGrid.Writes.Count);
end;

{ Strip Pascal comments -- braces NEST in FPC, so do (* *) -- and string literals'
  contents; line breaks are kept so line structure survives. }
function StripCode(const S: string): string;
var
  i, n, depth, o: Integer;
begin
  SetLength(Result, Length(S));
  o := 0;
  i := 1;
  n := Length(S);
  while i <= n do
  begin
    if S[i] = '{' then
    begin
      depth := 1;
      Inc(i);
      while (i <= n) and (depth > 0) do
      begin
        if S[i] = '{' then Inc(depth)
        else if S[i] = '}' then Dec(depth)
        else if S[i] in [#10, #13] then begin Inc(o); Result[o] := S[i]; end;
        Inc(i);
      end;
    end
    else if (S[i] = '(') and (i < n) and (S[i + 1] = '*') then
    begin
      Inc(i, 2);
      while (i < n) and not ((S[i] = '*') and (S[i + 1] = ')')) do
      begin
        if S[i] in [#10, #13] then begin Inc(o); Result[o] := S[i]; end;
        Inc(i);
      end;
      Inc(i, 2);
    end
    else if (S[i] = '/') and (i < n) and (S[i + 1] = '/') then
    begin
      while (i <= n) and not (S[i] in [#10, #13]) do Inc(i);
    end
    else if S[i] = '''' then
    begin
      Inc(i);
      while (i <= n) and (S[i] <> '''') and not (S[i] in [#10, #13]) do Inc(i);
      Inc(i);
      Inc(o); Result[o] := '''';
      Inc(o); Result[o] := '''';
    end
    else
    begin
      Inc(o);
      Result[o] := S[i];
      Inc(i);
    end;
  end;
  SetLength(Result, o);
end;

procedure TGridHooksTest.TestNoUserEditWritesTheStoreDirectly;
{ The colour toggle opens a modal dialog, so it cannot be driven here; this guard covers it
  and every path to come. A `Cells[..] :=` is allowed only in the routines that ARE
  operations on the store. Anything else is a user edit that went round SetEditText. }
const
  ALLOWED: array[0..6] of string = (
    'TTyCustomStringGrid.SetEditText',      { the default itself }
    'TTyCustomStringGrid.ApplyUndoStep',    { undo / redo replay the store's own record }
    'TTyCustomStringGrid.ShiftCells',       { inserting / deleting rows and columns }
    'TTyCustomStringGrid.SwapRows',         { a physical row exchange }
    'TTyCustomStringGrid.ApplyOrderToData', { a physical sort rewrites the store }
    'TTyCustomStringGrid.LoadFromCSVText',  { loading the store }
    'TTyGridStrings.Put');                  { the Cols / Rows TStrings view }
var
  src: TStringList;
  lines: TStringList;
  i, j, p, q, depth: Integer;
  ln, routine, bad, tail: string;
  inImpl, ok: Boolean;
begin
  src := TStringList.Create;
  lines := TStringList.Create;
  try
    src.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'source'
      + PathDelim + 'tyControls.Grid.pas');
    lines.Text := StripCode(src.Text);
    bad := '';
    routine := '';
    inImpl := False;
    for i := 0 to lines.Count - 1 do
    begin
      ln := lines[i];
      if Trim(ln) = 'implementation' then inImpl := True;
      if not inImpl then Continue;
      if AnsiStartsStr('procedure ', ln) or AnsiStartsStr('function ', ln)
         or AnsiStartsStr('constructor ', ln) or AnsiStartsStr('destructor ', ln) then
      begin
        routine := Copy(ln, Pos(' ', ln) + 1, MaxInt);
        p := 1;
        while (p <= Length(routine)) and (routine[p] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
          Inc(p);
        routine := Copy(routine, 1, p - 1);
      end;
      p := Pos('Cells[', ln);
      while p > 0 do
      begin
        { find the matching ']' }
        q := p + Length('Cells[');
        depth := 1;
        while (q <= Length(ln)) and (depth > 0) do
        begin
          if ln[q] = '[' then Inc(depth) else if ln[q] = ']' then Dec(depth);
          Inc(q);
        end;
        tail := TrimLeft(Copy(ln, q, MaxInt));
        if AnsiStartsStr(':=', tail) then
        begin
          ok := False;
          for j := Low(ALLOWED) to High(ALLOWED) do
            if routine = ALLOWED[j] then ok := True;
          if not ok then bad := bad + LineEnding + '  ' + routine + ': ' + Trim(ln);
        end;
        p := PosEx('Cells[', ln, q);
      end;
    end;
    AssertEquals('user edits that write Cells[] instead of SetEditText:', '', bad);
    { The guard must see something, or it guards nothing. }
    AssertTrue('the guard found the routines it allows', Pos('ShiftCells', src.Text) > 0);
  finally
    lines.Free;
    src.Free;
  end;
end;

{ ================= column class ================= }

procedure TGridHooksTest.TestColumnClassIsWhatTheHeaderCreates;
var
  before: Integer;
  plain: TTyStringGrid;
begin
  before := ColumnClassCalls;
  Build(2, 3);
  AssertEquals('asked once, while constructing', before + 1, ColumnClassCalls);
  AssertEquals('the header creates the subclass''s column class', TProbeColumn.ClassName,
    FGrid.Header.Columns.Add.ClassName);
  AssertTrue('every column is one', FGrid.Header.Columns.Items[0] is TProbeColumn);

  plain := TTyStringGrid.Create(nil);
  try
    AssertEquals('a plain grid still makes TTyGridColumn', TTyGridColumn.ClassName,
      plain.Header.Columns.Add.ClassName);
  finally
    plain.Free;
  end;
end;

{ ================= vertical scroll ================= }

procedure TGridHooksTest.TestDoVScrollSeesTheBarAndNotTheGridsOwnPush;
var
  k: Word;
  before: Integer;
begin
  Build(4, 60);
  AssertTrue('setup: the bar has a range', FGrid.VScrollBar.Max > 0);

  { The grid scrolling itself (the cursor followed) pushes into the bar: not a user scroll. }
  FGrid.MoveCursor(0, 40);
  AssertTrue('setup: the grid did scroll', FGrid.VScrollBar.Position > 0);
  AssertEquals('the grid''s own push is not reported', 0, FGrid.VScrolls.Count);

  { The bar moved by the user (here a key routed to it, the way a host does since #56). }
  before := FGrid.VScrollBar.Position;
  k := VK_UP;
  AssertTrue('setup: the bar took the key', FGrid.VScrollBar.ScrollByKey(k));
  AssertEquals('the bar''s move reaches DoVScroll once', 1, FGrid.VScrolls.Count);
  AssertEquals('with the bar''s new position', IntToStr(FGrid.VScrollBar.Position),
    FGrid.VScrolls[0]);
  AssertTrue('setup: it did move', FGrid.VScrollBar.Position < before);
  AssertEquals('and the default still scrolls the grid there',
    FGrid.VScrollBar.Position, FGrid.ScrollPos);
end;

{ ================= cursor moved ================= }

procedure TGridHooksTest.TestCursorMovedAfterKeyboardAndMouseMoves;
begin
  Build(4, 10);
  AssertEquals('setup: the cursor starts at the origin', '0:0', Key(FGrid.Col, FGrid.Row));
  AssertTrue('setup: Down was handled', FGrid.PressKey(VK_DOWN));
  AssertEquals('a key move is reported once', 1, FGrid.Moves.Count);
  AssertEquals('from where to where', '0:0>0:1', FGrid.Moves[0]);

  FGrid.ClickCell(2, 3);
  AssertEquals('setup: the click moved the cursor', '2:3', Key(FGrid.Col, FGrid.Row));
  AssertEquals('a click is reported once', 2, FGrid.Moves.Count);
  AssertEquals('from where to where', '0:1>2:3', FGrid.Moves[1]);

  FGrid.Row := 5;
  AssertEquals('so is a host setting Row', '2:3>2:5', FGrid.Moves[2]);
end;

procedure TGridHooksTest.TestCursorMovedNotAfterAVetoOrANoOp;
begin
  Build(4, 10);
  FGrid.OnSelectCell := @VetoMove;
  FVeto := True;
  FGrid.PressKey(VK_DOWN);
  FGrid.ClickCell(2, 3);
  AssertEquals('setup: the veto held', '0:0', Key(FGrid.Col, FGrid.Row));
  AssertEquals('a vetoed move is not reported', 0, FGrid.Moves.Count);

  FVeto := False;
  FGrid.MoveCursor(0, 0);
  FGrid.PressKey(VK_UP);    { already on the first row }
  AssertEquals('a move to where the cursor already is is not reported', 0, FGrid.Moves.Count);
end;

{ ---- THeaderHookGrid ---- }

constructor THeaderHookGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Log := TStringList.Create;
  Allow := True;
end;

destructor THeaderHookGrid.Destroy;
begin
  inherited Destroy;
  Log.Free;
end;

procedure THeaderHookGrid.HeaderSectionClicked(ACol: Integer);
begin
  inherited HeaderSectionClicked(ACol);
  Log.Add('clicked ' + IntToStr(ACol));
end;

procedure THeaderHookGrid.ColumnSized(ACol: Integer);
begin
  inherited ColumnSized(ACol);
  Log.Add('sized ' + IntToStr(ACol));
end;

procedure THeaderHookGrid.ColumnMoved(AFromPos, AToPos: Integer);
begin
  inherited ColumnMoved(AFromPos, AToPos);
  Log.Add(Format('moved %d %d', [AFromPos, AToPos]));
end;

function THeaderHookGrid.CanToggleCellCheck(ACol, ARow: Integer): Boolean;
begin
  Result := inherited CanToggleCellCheck(ACol, ARow) and Allow;
  Log.Add('asked ' + Key(ACol, ARow));
end;

function THeaderHookGrid.TitlePoint(ACol: Integer): TPoint;
var
  r: TRect;
begin
  r := CellRect(ACol, 0);
  Result := Point((r.Left + r.Right) div 2, HeaderHeightPx div 2);
end;

function THeaderHookGrid.DividerPoint(ACol: Integer): TPoint;
begin
  Result := Point(ColumnResizeEdgeX(ACol), HeaderHeightPx div 2);
end;

procedure THeaderHookGrid.Press(const APt: TPoint);
begin
  MouseDown(mbLeft, [], APt.X, APt.Y);
end;

procedure THeaderHookGrid.DragTo(const APt: TPoint);
begin
  MouseMove([ssLeft], APt.X, APt.Y);
end;

procedure THeaderHookGrid.Release(const APt: TPoint);
begin
  MouseUp(mbLeft, [], APt.X, APt.Y);
end;

function THeaderHookGrid.PressKey(AKey: Word): Word;
begin
  Result := AKey;
  KeyDown(Result, []);
end;

{ ---- TGridHeaderHooksTest ---- }

procedure TGridHeaderHooksTest.SetUp;
var
  i: Integer;
  c: TTyColumn;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 700, 500);
  FGrid := THeaderHookGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.Font.PixelsPerInch := 96;
  FGrid.SetBounds(0, 0, 500, 240);
  for i := 0 to 3 do
  begin
    c := FGrid.Header.Columns.Add as TTyColumn;
    c.Width := 90;
    c.Text := 'C' + IntToStr(i);
  end;
  FGrid.RowCount := 5;
  FChanges := 0;
  FEdits := 0;
end;

procedure TGridHeaderHooksTest.TearDown;
begin
  FreeAndNil(FForm);
  FGrid := nil;
end;

procedure TGridHeaderHooksTest.CountChange(Sender: TObject; ACol, ARow: Integer;
  AChecked: Boolean);
begin
  Inc(FChanges);
end;

procedure TGridHeaderHooksTest.CountEdit(Sender: TObject; ACol, ARow: Integer;
  const AOldText, ANewText: string; var AAccept: Boolean);
begin
  Inc(FEdits);
end;

{ M: the hook not called, or called for a release on another title. }
procedure TGridHeaderHooksTest.TestATitleClickReachesHeaderSectionClicked;
begin
  FGrid.Press(FGrid.TitlePoint(2));
  AssertEquals('not on the press', 0, FGrid.Log.Count);
  FGrid.Release(FGrid.TitlePoint(2));
  AssertEquals('on the release', 'clicked 2', Trim(FGrid.Log.Text));
  FGrid.Log.Clear;
  FGrid.Press(FGrid.TitlePoint(2));
  FGrid.Release(FGrid.TitlePoint(1));
  AssertEquals('released on another title: nothing', 0, FGrid.Log.Count);
end;

procedure TGridHeaderHooksTest.TestADividerDragReachesColumnSizedOnly;
var
  pt: TPoint;
begin
  pt := FGrid.DividerPoint(1);
  FGrid.Press(pt);
  FGrid.DragTo(Point(pt.X + 15, pt.Y));
  AssertEquals('nothing while dragging', 0, FGrid.Log.Count);
  FGrid.Release(Point(pt.X + 15, pt.Y));
  AssertEquals('the width', 105, (FGrid.Header.Columns.Items[1] as TTyColumn).Width);
  AssertEquals('sized, no click', 'sized 1', Trim(FGrid.Log.Text));
end;

procedure TGridHeaderHooksTest.TestAColumnDragReachesColumnMovedOnly;
begin
  FGrid.Press(FGrid.TitlePoint(0));
  FGrid.DragTo(FGrid.TitlePoint(2));
  FGrid.Release(FGrid.TitlePoint(2));
  AssertEquals('moved from position 0 to 2, no click', 'moved 0 2', Trim(FGrid.Log.Text));
  AssertEquals('it is at 2', 2, (FGrid.Header.Columns.Items[0] as TTyColumn).Position);
end;

{ M: the veto asked after the write, or not at all. }
procedure TGridHeaderHooksTest.TestCanToggleCellCheckVetoesTheWholeToggle;
begin
  (FGrid.Header.Columns.Items[1] as TTyGridColumn).EditorKind := gekCheckBox;
  FGrid.Cells[1, 0] := '';
  FGrid.OnCheckBoxChange := @CountChange;
  FGrid.OnCellEdited := @CountEdit;
  FGrid.Col := 1;
  FGrid.Allow := False;
  FGrid.PressKey(VK_SPACE);
  AssertEquals('asked', 'asked 1:0', Trim(FGrid.Log.Text));
  AssertEquals('vetoed: not written', '', FGrid.Cells[1, 0]);
  AssertEquals('no OnCellEdited', 0, FEdits);
  AssertEquals('no OnCheckBoxChange', 0, FChanges);
  FGrid.Allow := True;
  FGrid.PressKey(VK_SPACE);
  AssertEquals('allowed: written', '1', FGrid.Cells[1, 0]);
  AssertEquals('OnCellEdited', 1, FEdits);
  AssertEquals('OnCheckBoxChange', 1, FChanges);
end;

initialization
  RegisterTest(TGridHooksTest);
  RegisterTest(TGridHeaderHooksTest);
end.
