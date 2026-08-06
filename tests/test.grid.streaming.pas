unit test.grid.streaming;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, Controls, Forms, fpcunit, testregistry,
  tyControls.Columns, tyControls.Grid, tyControls.GridPanel, tyControls.GridCell,
  tyControls.Button, tyControls.ListView, tyControls.TreeView;

type
  { 拿真实的示例 .lfm 去校验控件的**发布面**。

    动机:属性没 published 出来,编译期完全看不出来 —— 只有运行时流式化才炸
    ("Error reading Grid.Anchors: Unknown property"),而那时已经到用户手里了。
    示例窗体一律用 .lfm 设计,所以拿 .lfm 当输入,是唯一能在无头环境复现该失败的办法。 }
  TTyGridStreamingTest = class(TTestCase)
  published
    procedure TestExampleLfmPropertiesAllExistOnTheControls;
    procedure TestGridPublishesStandardLayoutProperties;
    procedure TestGridPanelCellsSurviveRoundTrip;
    procedure TestGridPanelPublishesDesignerProps;
    procedure TestHeaderColumnsSurviveRoundTrip;
    procedure TestListViewAndTreeHeaderColumnsSurviveRoundTrip;
    procedure TestHeaderColumnsAssignmentReplacesTheCollection;
  end;

  { A streamable root that owns the design tree (mirrors test.pagecontrol.streaming). }
  TGridHostForm = class(TForm)
  published
    Grid: TTyGridPanel;
  end;

  { Roots for the header-column round trips below. Each holds one control whose columns
    live under the shared TTyHeader. }
  TColHostForm = class(TForm)
  published
    Grid: TTyStringGrid;
    LV: TTyListView;
    Tree: TTyTreeView;
  end;

implementation

{ 找到本仓库根目录(测试 exe 在 tests/ 下)。 }
function RepoRoot: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

{ 逐行扫 .lfm:
    'object Name: TClassName'  → 切换当前类
    '  PropName = ...'         → 若当前类是 TTy* 且已注册,校验该属性存在
  只校验我们自己的控件(TTy 开头);LCL 原生控件不在本测试职责内。 }
procedure TTyGridStreamingTest.TestExampleLfmPropertiesAllExistOnTheControls;
var
  lfm: TStringList;
  i, p: Integer;
  line, clsName, propName: string;
  cls: TPersistentClass;
  bad: TStringList;
  fn: string;
  dot: Integer;
begin
  fn := RepoRoot + 'examples' + PathDelim + 'grid' + PathDelim + 'umain.lfm';
  AssertTrue('示例 .lfm 存在:' + fn, FileExists(fn));

  lfm := TStringList.Create;
  bad := TStringList.Create;
  try
    lfm.LoadFromFile(fn);
    cls := nil;
    for i := 0 to lfm.Count - 1 do
    begin
      line := Trim(lfm[i]);
      if line = '' then Continue;

      if (Pos('object ', line) = 1) then
      begin
        { 'object Grid: TTyStringGrid' → 取冒号后的类名 }
        p := Pos(':', line);
        clsName := '';
        if p > 0 then clsName := Trim(Copy(line, p + 1, MaxInt));
        cls := nil;
        if (clsName <> '') and (Pos('TTy', clsName) = 1) then
          cls := GetClass(clsName);
        Continue;
      end;

      if line = 'end' then
      begin
        cls := nil;                      { 简化:只校验最内层 object 的直属属性 }
        Continue;
      end;

      if cls = nil then Continue;

      p := Pos('=', line);
      if p <= 1 then Continue;
      propName := Trim(Copy(line, 1, p - 1));
      if propName = '' then Continue;
      { 集合/列表续行等非属性行:属性名必须是合法标识符 }
      if not (propName[1] in ['A'..'Z', 'a'..'z', '_']) then Continue;

      { 带点的子属性(`Items.Strings`、`Font.Height`)是合法 LFM 写法:
        点号后面归子对象自己的流式化管,这里只校验**第一段**在宿主上存在。
        整串丢给 GetPropInfo 会把所有子属性都误判成"不存在"。 }
      dot := Pos('.', propName);
      if dot > 0 then propName := Copy(propName, 1, dot - 1);
      if propName = '' then Continue;

      if GetPropInfo(cls, propName) = nil then
        bad.Add(Format('%s.%s (第 %d 行)', [cls.ClassName, propName, i + 1]));
    end;

    AssertEquals('示例 .lfm 里有属性在控件上不存在 → 运行时会报 Unknown property:' + LineEnding
      + bad.Text, 0, bad.Count);
  finally
    bad.Free;
    lfm.Free;
  end;
end;

{ 直接的发布面守卫:网格必须发布这些 LCL 标准布局属性,
  否则任何在设计器里摆过位置的窗体一启动就报错。 }
procedure TTyGridStreamingTest.TestGridPublishesStandardLayoutProperties;
const
  cMust: array[0..8] of string = (
    'Align', 'Anchors', 'BorderSpacing', 'Constraints', 'Visible',
    'TabStop', 'TabOrder', 'StyleClass', 'Controller');
var
  i: Integer;
begin
  for i := 0 to High(cMust) do
  begin
    AssertTrue('TTyStringGrid 必须发布 ' + cMust[i],
      GetPropInfo(TTyStringGrid, cMust[i]) <> nil);
    AssertTrue('TTyDrawGrid 必须发布 ' + cMust[i],
      GetPropInfo(TTyDrawGrid, cMust[i]) <> nil);
  end;
end;

{ A full WriteComponent/ReadComponent round-trip (pure runtime, not just designer):
  a 2×2 grid with a control dropped into cell (1,1) must reload with EXACTLY 4 cells
  (not 8) and the child re-seated on the cell at (1,1). Guards the "streamed grids
  double-create their cells" bug — the constructor seeds a default 2×2 (FPC's TReader
  sets csLoading only AFTER Create), the streamed cells register on top, and without
  the Loaded-time discard you get 8 cells. }
procedure TTyGridStreamingTest.TestGridPanelCellsSurviveRoundTrip;
var
  Src, Dst: TGridHostForm;
  cellObj, reCell: TTyGridCell;
  marker: TTyButton;
  MS: TMemoryStream;
  i: Integer;
  DstGrid: TTyGridPanel;
  found: Boolean;
begin
  Src := TGridHostForm.CreateNew(nil);
  Dst := TGridHostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'HostForm1';
    Src.Grid := TTyGridPanel.Create(Src);
    Src.Grid.Name := 'Grid';
    Src.Grid.Parent := Src;
    AssertEquals('2x2 default = 4 cells pre-stream', 4, Src.Grid.CellCount);
    { Name the cells so they stream (the designer would; we do it explicitly). }
    for i := 0 to Src.Grid.CellCount - 1 do
      TTyGridCell(Src.Grid.CellAt(i)).Name := 'Cell' + IntToStr(i);
    cellObj := TTyGridCell(Src.Grid.Cells[1, 1]);
    AssertNotNull('cell (1,1) present pre-stream', cellObj);
    marker := TTyButton.Create(Src);
    marker.Name := 'Marker';
    marker.Parent := cellObj;            { a control "dropped" into cell (1,1) }

    MS.WriteComponent(Src);
    MS.Position := 0;
    MS.ReadComponent(Dst);               { read into a CreateNew'd root (no resource ctor) }

    DstGrid := Dst.FindComponent('Grid') as TTyGridPanel;
    AssertNotNull('grid survived', DstGrid);
    AssertEquals('exactly 4 cells after roundtrip (no double-create)', 4, DstGrid.CellCount);
    reCell := TTyGridCell(DstGrid.Cells[1, 1]);
    AssertNotNull('cell (1,1) reseated', reCell);
    { the dropped child survives on the cell at (1,1) }
    found := False;
    for i := 0 to reCell.ControlCount - 1 do
      if reCell.Controls[i] is TTyButton then found := True;
    AssertTrue('marker survived as child of cell (1,1)', found);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

{ Direct published-surface guard: TTyGridPanel must publish these props, or any
  form that set them in the designer will fail to stream at runtime. }
procedure TTyGridStreamingTest.TestGridPanelPublishesDesignerProps;
{ Visible is intentionally NOT asserted: no TTy container publishes it (TTyPanel /
  TTyPageControl / TTyTabSheet / TTyExPanel / … all manage visibility internally), so
  TTyGridPanel follows the house convention. }
const cMust: array[0..6] of string =
  ('ColumnCount', 'RowCount', 'ColumnSizes', 'RowSizes', 'Spacing',
   'Align', 'Anchors');
var i: Integer;
begin
  for i := 0 to High(cMust) do
    AssertTrue('TTyGridPanel must publish ' + cMust[i],
      GetPropInfo(TTyGridPanel, cMust[i]) <> nil);
end;

{ ------------------------------------------------- TTyHeader.Columns streaming --

  The columns of a grid, a list view and a tree view all live in ONE collection type
  reached through ONE property: TTyHeader.Columns. That property used to be declared
  `read FColumns` with no writer, and FPC gates BOTH halves of streaming on the writer
  being present -- for every property kind, collections included:

    - TWriter.WriteProperty (writer.inc) returns immediately when SetProc is nil unless
      the value is a TComponent subcomponent. A TTyColumns is a TCollection, so the
      designer wrote nothing: a user who added columns in the Object Inspector got them
      on screen and lost them on save, silently.
    - TReader.ReadPropValue (reader.inc) raises EReadError('Property is read-only')
      before it even looks at the kind, so a hand-written `Header.Columns = <...>` in a
      .lfm took the whole form down at CreateForm.

  Nothing headless had ever streamed a designer-authored grid, so neither half showed up
  until examples/rtl/umain.lfm declared its columns in the form file. These three tests
  are the guard. The first two are round trips rather than RTTI-shape assertions on
  purpose: `GetPropInfo(...)^.SetProc <> nil` would pass against a setter that dropped
  the columns on the floor. }

procedure TTyGridStreamingTest.TestHeaderColumnsSurviveRoundTrip;
var
  Src, Dst: TColHostForm;
  MS: TMemoryStream;
  col: TTyGridColumn;
  DstGrid: TTyStringGrid;
  Txt: TStringStream;
begin
  Src := TColHostForm.CreateNew(nil);
  Dst := TColHostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  Txt := TStringStream.Create('');
  try
    Src.Name := 'ColHost1';
    Src.Grid := TTyStringGrid.Create(Src);
    Src.Grid.Name := 'Grid';
    Src.Grid.Parent := Src;

    col := Src.Grid.Header.Columns.Add as TTyGridColumn;
    col.Text := 'Name';   col.Width := 168; col.Alignment := taLeftJustify;
    col := Src.Grid.Header.Columns.Add as TTyGridColumn;
    col.Text := 'Qty';    col.Width := 68;  col.Alignment := taRightJustify;
    col.SortKind := gskNumber;
    col := Src.Grid.Header.Columns.Add as TTyGridColumn;
    col.Text := 'Action'; col.Width := 96;  col.CellDisplay := gcdButton;
    AssertEquals('3 columns pre-stream', 3, Src.Grid.Header.Columns.Count);

    { The WRITER half. A property the writer skips leaves no trace in the text form,
      which is exactly what the designer would have saved. }
    MS.WriteComponent(Src);
    MS.Position := 0;
    ObjectBinaryToText(MS, Txt);
    AssertTrue('the writer must emit Header.Columns (a skipped property = columns lost '
      + 'on every designer save)', Pos('Columns', Txt.DataString) > 0);
    AssertTrue('and the column captions with it', Pos('Action', Txt.DataString) > 0);

    { The READER half. }
    MS.Position := 0;
    MS.ReadComponent(Dst);

    DstGrid := Dst.FindComponent('Grid') as TTyStringGrid;
    AssertNotNull('grid survived', DstGrid);
    AssertEquals('3 columns after round trip', 3, DstGrid.Header.Columns.Count);
    AssertEquals('column 0 caption', 'Name',
      (DstGrid.Header.Columns.Items[0] as TTyColumn).Text);
    AssertEquals('column 1 caption', 'Qty',
      (DstGrid.Header.Columns.Items[1] as TTyColumn).Text);
    AssertEquals('column 1 width', 68,
      (DstGrid.Header.Columns.Items[1] as TTyColumn).Width);
    AssertTrue('column 1 alignment', taRightJustify =
      (DstGrid.Header.Columns.Items[1] as TTyColumn).Alignment);
    { A grid's collection is created with TTyGridColumn, so the reader must re-add that
      class and its own published fields must survive too. }
    AssertTrue('reloaded items are TTyGridColumn',
      DstGrid.Header.Columns.Items[2] is TTyGridColumn);
    AssertTrue('column 2 CellDisplay', gcdButton =
      (DstGrid.Header.Columns.Items[2] as TTyGridColumn).CellDisplay);
    AssertTrue('column 1 SortKind', gskNumber =
      (DstGrid.Header.Columns.Items[1] as TTyGridColumn).SortKind);
  finally
    Txt.Free;
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

{ The same header type backs all three controls, so a fix that only reached the grid
  would be a fix in the wrong place. }
procedure TTyGridStreamingTest.TestListViewAndTreeHeaderColumnsSurviveRoundTrip;
var
  Src, Dst: TColHostForm;
  MS: TMemoryStream;
  c: TTyColumn;
begin
  Src := TColHostForm.CreateNew(nil);
  Dst := TColHostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'ColHost2';
    Src.LV := TTyListView.Create(Src);
    Src.LV.Name := 'LV';
    Src.LV.Parent := Src;
    c := Src.LV.Header.Columns.Add as TTyColumn; c.Text := 'File'; c.Width := 190;
    c := Src.LV.Header.Columns.Add as TTyColumn; c.Text := 'Size'; c.Width := 90;

    Src.Tree := TTyTreeView.Create(Src);
    Src.Tree.Name := 'Tree';
    Src.Tree.Parent := Src;
    c := Src.Tree.Header.Columns.Add as TTyColumn; c.Text := 'Node'; c.Width := 280;
    c := Src.Tree.Header.Columns.Add as TTyColumn; c.Text := 'Kind'; c.Width := 150;
    Src.Tree.Header.MainColumn := 0;

    MS.WriteComponent(Src);
    MS.Position := 0;
    MS.ReadComponent(Dst);

    AssertEquals('list view keeps 2 columns', 2,
      (Dst.FindComponent('LV') as TTyListView).Header.Columns.Count);
    AssertEquals('list view column 0 caption', 'File',
      ((Dst.FindComponent('LV') as TTyListView).Header.Columns.Items[0] as TTyColumn).Text);
    AssertEquals('tree keeps 2 columns', 2,
      (Dst.FindComponent('Tree') as TTyTreeView).Header.Columns.Count);
    AssertEquals('tree column 1 caption', 'Kind',
      ((Dst.FindComponent('Tree') as TTyTreeView).Header.Columns.Items[1] as TTyColumn).Text);
    { MainColumn is clamped to NoColumn while Columns.Count = 0. It may only survive
      because the columns arrived first -- which is the whole point of them arriving. }
    AssertEquals('tree MainColumn survived', 0,
      (Dst.FindComponent('Tree') as TTyTreeView).Header.MainColumn);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

{ The setter also has to be correct as a plain assignment -- that is the contract
  TTyStatusBar.Panels and TTyListView.Items already keep. Self-assignment is the case
  that bites: TCollection.Assign clears the destination first, so `H.Columns := H.Columns`
  through a naive setter empties it. }
procedure TTyGridStreamingTest.TestHeaderColumnsAssignmentReplacesTheCollection;
var
  A, B: TTyHeader;
  c: TTyColumn;
begin
  A := TTyHeader.Create;
  B := TTyHeader.Create;
  try
    c := A.Columns.Add as TTyColumn; c.Text := 'one'; c.Width := 40;
    c := A.Columns.Add as TTyColumn; c.Text := 'two'; c.Width := 50;

    c := B.Columns.Add as TTyColumn; c.Text := 'stale';

    B.Columns := A.Columns;
    AssertEquals('assignment replaces, not appends', 2, B.Columns.Count);
    AssertEquals('copied caption 0', 'one', (B.Columns.Items[0] as TTyColumn).Text);
    AssertEquals('copied width 1', 50, (B.Columns.Items[1] as TTyColumn).Width);

    A.Columns := A.Columns;
    AssertEquals('self-assignment must not empty the collection', 2, A.Columns.Count);
    AssertEquals('self-assignment keeps caption 1', 'two',
      (A.Columns.Items[1] as TTyColumn).Text);
  finally
    B.Free;
    A.Free;
  end;
end;

initialization
  { The reader instantiates streamed children by class name — register them. }
  RegisterClasses([TTyGridPanel, TTyGridCell, TTyButton,
                   TTyStringGrid, TTyListView, TTyTreeView]);
  RegisterTest(TTyGridStreamingTest);
end.
