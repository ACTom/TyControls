unit test.grid.streaming;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry,
  tyControls.Grid;

type
  { 拿真实的示例 .lfm 去校验控件的**发布面**。

    动机:属性没 published 出来,编译期完全看不出来 —— 只有运行时流式化才炸
    ("Error reading Grid.Anchors: Unknown property"),而那时已经到用户手里了。
    示例窗体一律用 .lfm 设计,所以拿 .lfm 当输入,是唯一能在无头环境复现该失败的办法。 }
  TTyGridStreamingTest = class(TTestCase)
  published
    procedure TestExampleLfmPropertiesAllExistOnTheControls;
    procedure TestGridPublishesStandardLayoutProperties;
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

initialization
  RegisterTest(TTyGridStreamingTest);
end.
