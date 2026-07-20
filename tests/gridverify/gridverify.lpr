{ 真机验收探针 —— 不是单元测试的替代品,是它够不到的那一层。

  无头测试把网格渲染到离屏位图;这里建的是**真实窗体 + 真实控件句柄**,
  走 widgetset 的真实绘制路径,然后把结果存成 PNG 供人(或模型)过目。
  它验证的正是无头测试验证不了的东西:真机上会不会崩、会不会画成空白。

  为什么要有它:这台机器上的安全软件拦截模拟输入与屏幕捕获,
  GUI 自动化走不通。让程序**自己**把画面存下来,就绕开了整条外部观察链。

  用法:gridverify.exe [输出目录]    退出码 0 = 全部通过。 }
program gridverify;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, Graphics, Controls, Classes, SysUtils, Types,
  IntfGraphics, FPImage,
  StrUtils,
  tyControls.Types, tyControls.Base, tyControls.Columns, tyControls.Grid;

var
  OutDir: string;
  Form: TForm;
  Grid: TTyStringGrid;
  Failures: Integer = 0;
  Checks: Integer = 0;

var
  LogF: TextFile;
  LogOpen: Boolean = False;

{ 日志同时进文件 —— 子系统/重定向的差异会让 stdout 到不了调用方,
  而卡在哪一步这种信息恰恰是出问题时唯一有用的东西。 }
procedure Say(const AMsg: string);
begin
  WriteLn(AMsg);
  Flush(Output);
  if LogOpen then
  begin
    WriteLn(LogF, AMsg);
    Flush(LogF);
  end;
end;

procedure Check(const AWhat: string; ACond: Boolean; const ADetail: string = '');
begin
  Inc(Checks);
  if ACond then
    Say('  PASS  ' + AWhat)
  else
  begin
    Inc(Failures);
    Say('  FAIL  ' + AWhat + IfThen(ADetail <> '', '  <- ' + ADetail, ''));
  end;
end;

var
  Cap: TBitmap = nil;

{ 把网格画进 Cap 一次。后面的存图与数墨都读它 —— 别每次都重画一遍整幅网格。 }
procedure Capture;
begin
  Application.ProcessMessages;
  if Cap = nil then
  begin
    Cap := TBitmap.Create;
    Cap.PixelFormat := pf32bit;
  end;
  Cap.SetSize(Grid.Width, Grid.Height);
  Cap.Canvas.Brush.Color := clWhite;
  Cap.Canvas.FillRect(0, 0, Cap.Width, Cap.Height);
  Grid.PaintTo(Cap.Canvas, 0, 0);
end;

{ 把网格**当前的真实绘制**存成 PNG。走 PaintTo,也就是控件在屏幕上用的那条路径。 }
procedure Shot(const AName: string);
var
  png: TPortableNetworkGraphic;
begin
  Capture;
  png := TPortableNetworkGraphic.Create;
  try
    png.Assign(Cap);
    png.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + AName + '.png');
    Say('  shot  ' + AName + '.png');
  finally
    png.Free;
  end;
end;

{ 数一数某个矩形里有多少"墨"(非背景像素)—— 用来断言"这块地方不是空白"。
  读的是 Capture 已经画好的那一份;逐像素走 IntfImage 而不是 Canvas.Pixels
  (后者每个像素一次 GDI 往返,一个单元格就要几千次)。 }
function InkIn(const R: TRect): Integer;
var
  img: TLazIntfImage;
  x, y: Integer;
  c: TFPColor;
begin
  Result := 0;
  if Cap = nil then Exit;
  img := Cap.CreateIntfImage;
  try
    for y := R.Top to R.Bottom - 1 do
      for x := R.Left to R.Right - 1 do
      begin
        if (y < 0) or (y >= img.Height) or (x < 0) or (x >= img.Width) then Continue;
        c := img.Colors[x, y];
        { 深色像素 = 文字。背景不管是白还是浅灰都不会这么深。 }
        if (c.red shr 8) + (c.green shr 8) + (c.blue shr 8) < 380 then Inc(Result);
      end;
  finally
    img.Free;
  end;
end;

procedure Reset(ARows: Integer = 12);
var
  r: Integer;
begin
  { **列也要重建** —— 有的场景会删列,而 ClearCells 只清内容。
    不重建的话后面的场景是在一张少了一列的表上跑,
    失败信息会指向控件,其实是上一个场景的残留。 }
  while Grid.Header.Columns.Count > 0 do
    Grid.Header.Columns.Delete(Grid.Header.Columns.Count - 1);
  (Grid.Header.Columns.Add as TTyColumn).Width := 120;
  (Grid.Header.Columns.Add as TTyColumn).Width := 120;
  (Grid.Header.Columns.Add as TTyColumn).Width := 160;

  Grid.OnGetCellStyle := nil;
  Grid.OnGetCellText := nil;
  Grid.UngroupRows;
  Grid.ClearFilters;
  Grid.SortMode := gsmDisplay;
  Grid.SortByColumn(-1, sdAscending);
  Grid.ClearCells;
  Grid.RowCount := ARows;
  Grid.FixedRows := 0;
  for r := 0 to ARows - 1 do
  begin
    Grid.Cells[0, r] := Format('%.2d', [r]);
    Grid.Cells[1, r] := Chr(Ord('A') + (r mod 3));      { 3 个组 }
    Grid.Cells[2, r] := Format('item-%d', [r]);
  end;
  Grid.ClearUndo;
  Application.ProcessMessages;
end;

{ --- 场景 --- }

{ A1:固定行 + 排序叠加。冻结带里换成排在最前的那一行,内容必须照画。
  这是本轮最险的一个:改错了不编译报错、不抛异常,只是**静默画空白**。 }
procedure Case_FixedRowsWithSort;
var
  cell: TRect;
  ink, blank: Integer;
begin
  Say('[1] 固定行 + 降序排 —— 冻结带里的内容不能是空白');
  Reset(12);
  Grid.FixedRows := 2;
  Grid.SortByColumn(0, sdDescending);
  Application.ProcessMessages;

  Check('降序后显示位置 0 是数据行 11', Grid.DisplayToData(0) = 11,
    Format('实际 %d', [Grid.DisplayToData(0)]));

  { 冻结带里那两行的可见矩形必须非空、且画出了字。 }
  Capture;
  { 基线:网格末行之下那片必然空白的区域,同样大小。
    要区分的是"完全没画"和"画了字",拿绝对墨量当阈值分不清细字与空白。 }
  blank := InkIn(Rect(4, Grid.Height - 60, 124, Grid.Height - 36));
  cell := Grid.CellVisibleRect(0, Grid.DisplayToData(0));
  Check('冻结带首行的可见矩形非空', not IsRectEmpty(cell),
    Format('%d,%d-%d,%d', [cell.Left, cell.Top, cell.Right, cell.Bottom]));
  if not IsRectEmpty(cell) then
  begin
    ink := InkIn(cell);
    Check('冻结带首行真的画出了字', ink > blank + 1,
      Format('墨 %d,空白基线 %d', [ink, blank]));
  end;

  cell := Grid.CellVisibleRect(0, Grid.DisplayToData(1));
  if not IsRectEmpty(cell) then
  begin
    ink := InkIn(cell);
    Check('冻结带第二行也画出了字', ink > blank + 1,
      Format('墨 %d,空白基线 %d', [ink, blank]));
  end;

  { 被推到正文里的数据行 0 也要画得出来。 }
  cell := Grid.CellVisibleRect(0, 0);
  Check('数据行 0(现在在正文最下面)可见矩形非空', not IsRectEmpty(cell));
  Shot('1-fixedrows-sorted');
end;

{ 分组时按 Ctrl+A:显示序两端是分组行,锚点不能落在负的数据行上。 }
procedure Case_SelectAllWhenGrouped;
var
  n: Integer;
begin
  Say('[2] 分组之后 Ctrl+A —— 要选中全部数据,不是一行');
  Reset(12);
  Grid.GroupByColumn(1);
  Application.ProcessMessages;
  Check('确实有分组行', Grid.DisplayToData(0) < 0);

  Grid.SelectAll;
  n := Grid.SelectedCellCount;
  Check('选中的格数 = 12 行 x 3 列', n = 36, Format('实际 %d', [n]));
  Shot('2-selectall-grouped');
end;

{ 挂着逐格外观钩子再开分组 —— 从前这条路会把负行号喂给宿主,在**绘制里**崩。 }
var
  HookMinRow: Integer;

type
  THookHost = class
    procedure GetCellStyle(Sender: TObject; ACol, ARow: Integer;
      var ABackground: TTyFill; var ATextColor: TTyColor;
      var AFontName: string; var AFontSize, AFontWeight: Integer;
      var AHAlign: TAlignment; var AVAlign: TTextLayout);
  end;

procedure THookHost.GetCellStyle(Sender: TObject; ACol, ARow: Integer;
  var ABackground: TTyFill; var ATextColor: TTyColor;
  var AFontName: string; var AFontSize, AFontWeight: Integer;
  var AHAlign: TAlignment; var AVAlign: TTextLayout);
begin
  if ARow < HookMinRow then HookMinRow := ARow;
  { 宿主按行号索引自己的数据 —— 这是这个钩子最正常的用法。
    收到负行号时这一句就会越界。 }
  if ARow >= 0 then
  begin
    ATextColor := TyRGB(30, 30, 30);
    if (ARow mod 2) = 0 then AFontWeight := 700;
  end;
end;

var
  Host: THookHost;

procedure Case_CellStyleHookWithGrouping;
begin
  Say('[3] OnGetCellStyle + 分组 —— 宿主不能收到负行号(从前会崩在绘制里)');
  Reset(12);
  HookMinRow := MaxInt;
  Grid.OnGetCellStyle := @Host.GetCellStyle;
  Grid.GroupByColumn(1);
  Application.ProcessMessages;
  Shot('3-cellstyle-grouped');

  Check('钩子确实被调用过', HookMinRow <> MaxInt);
  Check('宿主没收到负行号', HookMinRow >= 0, Format('最小收到 %d', [HookMinRow]));
  Grid.OnGetCellStyle := nil;
end;

{ 删掉一列之后表还在不在 —— 从前筛选留在旧列号上会让整表变空。 }
procedure Case_DeleteColumnKeepsTable;
var
  before, after: Integer;
begin
  Say('[4] 有筛选时删列 —— 表不能变空');
  Reset(12);
  Grid.SetColumnFilter(2, 'item-');       { 第 2 列的筛选,全部行都匹配 }
  Application.ProcessMessages;
  before := Grid.DisplayRowCount;
  Check('前置:筛选没筛掉任何行', before = 12, Format('实际 %d', [before]));

  Grid.DeleteColumn(0);                   { 删掉它左边的列 —— 筛选要跟着左移 }
  Application.ProcessMessages;
  after := Grid.DisplayRowCount;
  Check('删列之后表还在(不是 0 行)', after = 12, Format('实际 %d', [after]));
  Shot('4-after-delete-column');
end;

{ 给选区涂色再撤销 —— 用户报的那个:整片涂、一格一格退。 }
procedure Case_ColourSelectionUndo;
var
  painted, n: Integer;
begin
  Say('[5] 选区涂色 + 一次撤销 —— 整片退回去');
  Reset(12);
  Grid.SelectRange(0, 1, 2, 4);           { 3 列 x 4 行 }
  Application.ProcessMessages;
  Grid.ClearUndo;

  painted := Grid.SetSelectionColor(TyRGB(255, 0, 0));
  Check('涂了 12 格', painted = 12, Format('实际 %d', [painted]));
  Check('左上角上了色', Grid.CellColors[0, 1] = TyRGB(255, 0, 0));
  Check('右下角上了色', Grid.CellColors[2, 4] = TyRGB(255, 0, 0));
  Shot('5a-coloured');

  n := Grid.UndoCount;
  Check('涂一片 = 一条撤销记录', n = 1, Format('实际 %d 条', [n]));

  Grid.Undo;
  Application.ProcessMessages;
  Check('一次撤销后左上角退回', Grid.CellColors[0, 1] = 0);
  Check('一次撤销后右下角也退回', Grid.CellColors[2, 4] = 0);
  Check('栈里不剩别的', not Grid.CanUndo);
  Shot('5b-undone');
end;

{ 物理排序:真的搬数据,而且撤得回来。 }
procedure Case_PhysicalSortUndo;
var
  first: string;
begin
  Say('[6] 物理排序(gsmData)+ 撤销');
  Reset(12);
  Grid.CellColors[0, 0] := TyRGB(0, 0, 255);   { 给"值 00"那一行做个记号 }
  Grid.SortMode := gsmData;
  Grid.ClearUndo;

  Grid.SortByColumn(0, sdDescending);
  Application.ProcessMessages;
  first := Grid.Cells[0, 0];
  Check('降序后存储里第一行真的换成了 11', first = '11', '实际 ' + first);
  Check('底色跟着那一行数据走到了末行',
    Grid.CellColors[0, 11] = TyRGB(0, 0, 255));
  Shot('6a-physically-sorted');

  Grid.Undo;
  Application.ProcessMessages;
  first := Grid.Cells[0, 0];
  Check('撤销后第一行回到 00', first = '00', '实际 ' + first);
  Check('底色也回到了第一行', Grid.CellColors[0, 0] = TyRGB(0, 0, 255));
  Shot('6b-sort-undone');
end;

{ 两级分组:同名子组出现在不同父组下,必须各折各的。 }
procedure Case_MultiLevelGrouping;
var
  r, groups: Integer;
begin
  Say('[7] 两级分组');
  Reset(12);
  for r := 0 to 11 do
  begin
    Grid.Cells[1, r] := Chr(Ord('A') + (r mod 2));        { 父:A/B }
    Grid.Cells[2, r] := Chr(Ord('X') + ((r div 2) mod 2));{ 子:X/Y,两个父下都有 }
  end;
  Grid.GroupByColumns([1, 2]);
  Application.ProcessMessages;

  groups := 0;
  for r := 0 to Grid.DisplayRowCount - 1 do
    if Grid.DisplayToData(r) < 0 then Inc(groups);
  { 2 个父组,每个父组下 2 个子组 = 2 + 4 = 6 个分组行。 }
  Check('分组行数 = 6(2 父 + 4 子)', groups = 6, Format('实际 %d', [groups]));
  Shot('7-two-level-grouping');
end;

begin
  OutDir := ExtractFilePath(ParamStr(0));
  if ParamCount >= 1 then OutDir := ParamStr(1);
  ForceDirectories(OutDir);

  Application.Initialize;
  Host := THookHost.Create;

  Form := TForm.Create(nil);
  Form.SetBounds(-3000, 100, 1000, 560);    { 挪到屏幕外,别打扰正在用电脑的人 }
  Form.Caption := 'gridverify';

  Grid := TTyStringGrid.Create(Form);
  Grid.Parent := Form;
  Grid.SetBounds(0, 0, 980, 520);
  (Grid.Header.Columns.Add as TTyColumn).Width := 120;
  (Grid.Header.Columns.Add as TTyColumn).Width := 120;
  (Grid.Header.Columns.Add as TTyColumn).Width := 160;
  Grid.DefaultRowHeight := 24;
  Form.Show;                                { 要有真实句柄,绘制才是真实路径 }
  Application.ProcessMessages;

  AssignFile(LogF, IncludeTrailingPathDelimiter(OutDir) + 'verify.log');
  Rewrite(LogF);
  LogOpen := True;
  Say('=== gridverify ===');
  Say('输出目录: ' + OutDir);
  Say('');
  try
    Case_FixedRowsWithSort;      Say('');
    Case_SelectAllWhenGrouped;   Say('');
    Case_CellStyleHookWithGrouping; Say('');
    Case_DeleteColumnKeepsTable; Say('');
    Case_ColourSelectionUndo;    Say('');
    Case_PhysicalSortUndo;       Say('');
    Case_MultiLevelGrouping;     Say('');
  except
    on E: Exception do
    begin
      Inc(Failures);
      Say('  EXCEPTION  ' + E.ClassName + ': ' + E.Message);
    end;
  end;

  Say(Format('=== %d 项检查,%d 项失败 ===', [Checks, Failures]));
  if Cap <> nil then Cap.Free;
  if LogOpen then CloseFile(LogF);
  Form.Hide;
  Host.Free;
  Form.Free;
  if Failures > 0 then Halt(1);
end.
