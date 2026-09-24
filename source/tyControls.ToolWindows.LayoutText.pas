unit tyControls.ToolWindows.LayoutText;
{$mode objfpc}{$H+}

{ 工具窗口布局串(spec §10.2 / §10.3):解析、格式化、版本漂移计划。纯函数,无控件,可无头测。
  格式照 TTyStringGrid.SaveLayoutToString 的约定(一行、| 分段、key=value),但解析更严:
  普通字符切分(不用 TStringList.DelimitedText,它仍然特殊处理引号)、必须以 end 收尾、
  数字只认 1-5 位纯数字。控件只负责把现状装成输入、把计划照做成一个批次
  (TTyToolWindowManager 在 tyControls.ToolWindows)。 }

interface

uses
  SysUtils;

const
  TyToolLayoutTag = 'TYTOOLLAYOUT/1';
  { 解析接受的最长布局串(字符数)。几十个窗口的布局串不过几百字节;上限挡住的是喂进来的
    垃圾(读错了文件、配置被截成别的东西),超长直接答 False,不去切分。 }
  TyToolLayoutMaxLength = 65536;

type
  TTyToolLayoutSide = (tlsLeft, tlsRight, tlsBottom);

  TTyToolLayoutGroup = record
    Present: Boolean;         { p、pWins、pActive 三个 key 都在 }
    Size: Integer;            { 0..99999 }
    Collapsed: Boolean;
    Names: TStringArray;      { 按顺序 }
    Active: string;           { '' 或 Names 里的一个(拼写取 Names 里的那个) }
  end;

  TTyToolLayoutDoc = array[TTyToolLayoutSide] of TTyToolLayoutGroup;

  { 程序此刻的一条可用栏(manager 装)。Names 按窗口顺序,空名 / 重名照实填 —— 找不到、
    匹配到不止一个都由计划自己判。 }
  TTyToolLayoutBarState = record
    Usable: Boolean;          { 有这个 Placement 的可用栏 }
    Names: TStringArray;
    Active: Integer;          { 当前页的窗口序号,-1 = 没有 }
  end;
  TTyToolLayoutWorld = array[TTyToolLayoutSide] of TTyToolLayoutBarState;

  { 一个窗口的身份 = 它此刻在哪条栏的第几个。 }
  TTyToolLayoutRef = record
    Side: TTyToolLayoutSide;
    Index: Integer;
  end;

  TTyToolLayoutBarPlan = record
    { 串里有这一组、这条栏可用:尺寸和收起才写。 }
    Apply: Boolean;
    Size: Integer;
    Collapsed: Boolean;
    { 应用之后这条栏的窗口顺序(已放置的在前,未放置的留在原栏、保持相对顺序)。 }
    Order: array of TTyToolLayoutRef;
    { Order 里的下标,-1 = 没有当前页。 }
    Active: Integer;
  end;
  TTyToolLayoutPlan = array[TTyToolLayoutSide] of TTyToolLayoutBarPlan;

{ 整串合法才答 True 并填 ADoc;不合法答 False,ADoc 全是零值(Present 都为假)。超过
  TyToolLayoutMaxLength 的一律不合法。 }
function TyToolLayoutParse(const AText: string; out ADoc: TTyToolLayoutDoc): Boolean;
{ 存储层带进来的外壳去掉:开头的 UTF-8 BOM、结尾的空白(CR / LF / 空格 / Tab)——
  TStringList.Text、写进文件再读回来都会带上。只去这两样,中间的照旧严格。 }
function TyToolLayoutUnwrap(const AText: string): string;
{ 按 left、right、bottom 的顺序只写 Present 的组。调用方保证名字合法、不重名。 }
function TyToolLayoutFormat(const ADoc: TTyToolLayoutDoc): string;

{ spec §10.3:格式对、但窗口变了时,保存的布局落到此刻的窗口上是什么样。只对 Usable 的栏
  出计划(不可用的栏 Order 为空、Apply 为假、Active -1,调用方不碰它)。
  - 在可用栏的窗口里按名字找(CompareText);找不到、匹配到不止一个 → 丢掉这个名字。
  - 程序没有对应可用栏的组整组忽略,里面的名字算未放置。
  - 名字列在另一类栏下(按窗口此刻所在的栏判侧 / 底)→ 未放置。
  - 未放置的留在此刻的栏,排在已放置的后面,保持相对顺序。
  - 当前页:保存的名字最终在这条栏里就用它;否则此刻的当前页还在就不变;否则第一个;
    否则没有。缺组的栏也照这条回落。 }
function TyToolLayoutPlanFor(const AWorld: TTyToolLayoutWorld;
  const ADoc: TTyToolLayoutDoc): TTyToolLayoutPlan;

implementation

const
  { key 区分大小写:Left= 是未知 key。 }
  SideKey: array[TTyToolLayoutSide] of string = ('left', 'right', 'bottom');
  WinsSuffix = 'Wins';
  ActiveSuffix = 'Active';

{ 按 ASep 普通切分,保留空段(空段由调用方判)。先数段数、一次分配:逐段 SetLength + 1 是
  平方级的拷贝。 }
function SplitPlain(const S: string; ASep: Char): TStringArray;
var
  i, start, n: Integer;
begin
  n := 1;
  for i := 1 to Length(S) do
    if S[i] = ASep then Inc(n);
  Result := nil;
  SetLength(Result, n);
  n := 0;
  start := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = ASep) then
    begin
      Result[n] := Copy(S, start, i - start);
      Inc(n);
      start := i + 1;
    end;
end;

{ 按 CompareStr(逐字节,不看区域设置)升序排,自底向上归并。判重用:排好之后相等的必然相邻。 }
procedure SortPlain(var A: TStringArray);
var
  buf: TStringArray;
  width, lo, mid, hi, i, j, k, n: Integer;
begin
  n := Length(A);
  if n < 2 then Exit;
  buf := nil;
  SetLength(buf, n);
  width := 1;
  while width < n do
  begin
    lo := 0;
    while lo < n do
    begin
      mid := lo + width;
      if mid > n then mid := n;
      hi := lo + 2 * width;
      if hi > n then hi := n;
      i := lo;
      j := mid;
      k := lo;
      while (i < mid) and (j < hi) do
      begin
        if CompareStr(A[j], A[i]) < 0 then
        begin
          buf[k] := A[j];
          Inc(j);
        end
        else
        begin
          buf[k] := A[i];
          Inc(i);
        end;
        Inc(k);
      end;
      while i < mid do
      begin
        buf[k] := A[i];
        Inc(i);
        Inc(k);
      end;
      while j < hi do
      begin
        buf[k] := A[j];
        Inc(j);
        Inc(k);
      end;
      lo := hi;
    end;
    for i := 0 to n - 1 do A[i] := buf[i];
    width := width * 2;
  end;
end;

{ 有没有两项相等(先排序,相等的相邻)。 }
function HasDuplicate(const A: TStringArray): Boolean;
var
  s: TStringArray;
  i: Integer;
begin
  { 动态数组按值传也共用同一块:拷一份再排,不动调用方的顺序。 }
  s := Copy(A);
  SortPlain(s);
  for i := 1 to High(s) do
    if s[i] = s[i - 1] then Exit(True);
  Result := False;
end;

function TyToolLayoutUnwrap(const AText: string): string;
const
  Bom = #$EF#$BB#$BF;
var
  first, last: Integer;
begin
  first := 1;
  if Copy(AText, 1, Length(Bom)) = Bom then first := Length(Bom) + 1;
  last := Length(AText);
  while (last >= first) and (AText[last] in [#9, #10, #13, ' ']) do Dec(last);
  Result := Copy(AText, first, last - first + 1);
end;

{ 1-5 位 '0'..'9',别的一概不认(' 240'、'$F0'、'+240'、'-1' 都拒;Grid 的 Trim + TryStrToInt
  会接受,这里不照抄)。 }
function IsSizeDigits(const S: string): Boolean;
var
  i: Integer;
begin
  Result := (Length(S) >= 1) and (Length(S) <= 5);
  if not Result then Exit;
  for i := 1 to Length(S) do
    if not (S[i] in ['0'..'9']) then Exit(False);
end;

function TyToolLayoutParse(const AText: string; out ADoc: TTyToolLayoutDoc): Boolean;
var
  d: TTyToolLayoutDoc;
  segs, parts, names, keys, all: TStringArray;
  have: array[TTyToolLayoutSide, 0..2] of Boolean;
  vals: array[TTyToolLayoutSide, 0..2] of string;
  side: TTyToolLayoutSide;
  i, j, k, p, n: Integer;
  key: string;
  found: Boolean;
begin
  ADoc := Default(TTyToolLayoutDoc);
  Result := False;
  d := Default(TTyToolLayoutDoc);
  FillChar(have, SizeOf(have), 0);
  { 0. 超长直接拒,不切分(见 TyToolLayoutMaxLength)。 }
  if Length(AText) > TyToolLayoutMaxLength then Exit;
  { 1. 按 | 切;标签在头、end 在尾,中间不许再出现 end(截断在值中间的串过不了这一关)。 }
  segs := SplitPlain(AText, '|');
  if Length(segs) < 2 then Exit;
  if segs[0] <> TyToolLayoutTag then Exit;
  if segs[High(segs)] <> 'end' then Exit;
  { 2. 中间每段:非空、有 =、key 非空、不重复(区分大小写;排序后比相邻,不两两比)。已知 key
    记值,未知的忽略(以后加的 key)。 }
  keys := nil;
  SetLength(keys, Length(segs) - 2);
  for i := 1 to High(segs) - 1 do
  begin
    if (segs[i] = '') or (segs[i] = 'end') then Exit;
    p := Pos('=', segs[i]);
    if p <= 1 then Exit;
    key := Copy(segs[i], 1, p - 1);
    keys[i - 1] := key;
    for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
    begin
      k := -1;
      if key = SideKey[side] then k := 0
      else if key = SideKey[side] + WinsSuffix then k := 1
      else if key = SideKey[side] + ActiveSuffix then k := 2;
      if k >= 0 then
      begin
        have[side, k] := True;
        vals[side, k] := Copy(segs[i], p + 1, MaxInt);
      end;
    end;
  end;
  if HasDuplicate(keys) then Exit;
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
  begin
    { 3. 一组三个 key 全有或全无;不完整整串拒绝。 }
    n := Ord(have[side, 0]) + Ord(have[side, 1]) + Ord(have[side, 2]);
    if n = 0 then Continue;
    if n <> 3 then Exit;
    d[side].Present := True;
    { 4. 尺寸,标志:正好两个字段。 }
    parts := SplitPlain(vals[side, 0], ',');
    if Length(parts) <> 2 then Exit;
    if not IsSizeDigits(parts[0]) then Exit;
    d[side].Size := StrToInt(parts[0]);
    if parts[1] = '1' then d[side].Collapsed := True
    else if parts[1] <> '0' then Exit;
    { 5. 名字:空串 = 空列表;否则每项非空、是合法标识符(允许带点,给以后按 Owner 路径
      区分 frame 里的窗口留口子)。 }
    names := nil;
    if vals[side, 1] <> '' then
    begin
      names := SplitPlain(vals[side, 1], ',');
      for j := 0 to High(names) do
        if (names[j] = '') or not IsValidIdent(names[j], True, True) then Exit;
    end;
    d[side].Names := names;
  end;
  { 6. 名字在所有组里唯一(组件名不区分大小写,CompareText)。名字都过了 IsValidIdent,只有
    ASCII:LowerCase 之后逐字节比就是 CompareText 的答案;排序后比相邻,不两两比。 }
  all := nil;
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
  begin
    n := Length(all);
    SetLength(all, n + Length(d[side].Names));
    for i := 0 to High(d[side].Names) do
      all[n + i] := LowerCase(d[side].Names[i]);
  end;
  if HasDuplicate(all) then Exit;
  { 7. 当前页:空,或自己组里的一个名字(拼写取列表里的)。 }
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
  begin
    if not d[side].Present or (vals[side, 2] = '') then Continue;
    found := False;
    for j := 0 to High(d[side].Names) do
      if CompareText(d[side].Names[j], vals[side, 2]) = 0 then
      begin
        d[side].Active := d[side].Names[j];
        found := True;
        Break;
      end;
    if not found then Exit;
  end;
  ADoc := d;
  Result := True;
end;

function JoinNames(const ANames: TStringArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ANames) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + ANames[i];
  end;
end;

function TyToolLayoutFormat(const ADoc: TTyToolLayoutDoc): string;
var
  side: TTyToolLayoutSide;
begin
  { 顺序只靠列表位置,不写数字顺序键(index-keyed-string-sort-trap)。 }
  Result := TyToolLayoutTag;
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
  begin
    if not ADoc[side].Present then Continue;
    Result := Result + '|' + Format('%s=%d,%d', [SideKey[side], ADoc[side].Size,
      Ord(ADoc[side].Collapsed)])
      + '|' + SideKey[side] + WinsSuffix + '=' + JoinNames(ADoc[side].Names)
      + '|' + SideKey[side] + ActiveSuffix + '=' + ADoc[side].Active;
  end;
  Result := Result + '|end';
end;

function TyToolLayoutPlanFor(const AWorld: TTyToolLayoutWorld;
  const ADoc: TTyToolLayoutDoc): TTyToolLayoutPlan;
type
  TEntry = record
    Name: string;
    Ref: TTyToolLayoutRef;
    Dup: Boolean;
  end;
var
  entries: array of TEntry;
  { 每个窗口被哪一组放置了(按 entries 下标);未放置 = 不在里面。 }
  placedBy: array of Boolean;
  placedSide: array of TTyToolLayoutSide;
  placed: array[TTyToolLayoutSide] of array of Integer;   { 按组内顺序,entries 下标 }
  side, g: TTyToolLayoutSide;
  i, j, k, e, n: Integer;
  ref: TTyToolLayoutRef;

  function EntryOf(ASide: TTyToolLayoutSide; AIndex: Integer): Integer;
  var
    x: Integer;
  begin
    for x := 0 to High(entries) do
      if (entries[x].Ref.Side = ASide) and (entries[x].Ref.Index = AIndex) then Exit(x);
    Result := -1;
  end;

  procedure AddRef(ASide: TTyToolLayoutSide; const ARef: TTyToolLayoutRef);
  var
    m: Integer;
  begin
    m := Length(Result[ASide].Order);
    SetLength(Result[ASide].Order, m + 1);
    Result[ASide].Order[m] := ARef;
  end;

begin
  Result := Default(TTyToolLayoutPlan);
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
    Result[side].Active := -1;
  { 1. 名字索引:可用栏里每个有名字的窗口;同名(CompareText)的都记成重名。 }
  entries := nil;
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
  begin
    if not AWorld[side].Usable then Continue;
    for i := 0 to High(AWorld[side].Names) do
    begin
      if AWorld[side].Names[i] = '' then Continue;
      n := Length(entries);
      SetLength(entries, n + 1);
      entries[n].Name := AWorld[side].Names[i];
      entries[n].Ref.Side := side;
      entries[n].Ref.Index := i;
      entries[n].Dup := False;
      for j := 0 to n - 1 do
        if CompareText(entries[j].Name, entries[n].Name) = 0 then
        begin
          entries[j].Dup := True;
          entries[n].Dup := True;
        end;
    end;
  end;
  placedBy := nil;
  placedSide := nil;
  SetLength(placedBy, Length(entries));
  SetLength(placedSide, Length(entries));
  { 2. 每个串里有、程序里也可用的组,按组内顺序放置。 }
  for g := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
  begin
    placed[g] := nil;
    if not (ADoc[g].Present and AWorld[g].Usable) then Continue;
    for i := 0 to High(ADoc[g].Names) do
    begin
      e := -1;
      for j := 0 to High(entries) do
        if CompareText(entries[j].Name, ADoc[g].Names[i]) = 0 then
        begin
          e := j;
          Break;
        end;
      if (e < 0) or entries[e].Dup then Continue;
      { 列在另一类栏下(一侧一底):未放置。 }
      if (entries[e].Ref.Side = tlsBottom) <> (g = tlsBottom) then Continue;
      placedBy[e] := True;
      placedSide[e] := g;
      SetLength(placed[g], Length(placed[g]) + 1);
      placed[g][High(placed[g])] := e;
    end;
  end;
  { 3、4、5. 每条可用栏:已放置的在前,此刻在这条栏里、谁都没放置的在后;当前页;尺寸。 }
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
  begin
    if not AWorld[side].Usable then Continue;
    for i := 0 to High(placed[side]) do
      AddRef(side, entries[placed[side][i]].Ref);
    for i := 0 to High(AWorld[side].Names) do
    begin
      e := EntryOf(side, i);
      if (e >= 0) and placedBy[e] then Continue;
      ref.Side := side;
      ref.Index := i;
      AddRef(side, ref);
    end;
    { 当前页:保存的名字最终在这条栏里 → 它。 }
    if ADoc[side].Present and (ADoc[side].Active <> '') then
      for k := 0 to High(Result[side].Order) do
      begin
        e := EntryOf(Result[side].Order[k].Side, Result[side].Order[k].Index);
        if (e >= 0) and placedBy[e] and (placedSide[e] = side)
           and (CompareText(entries[e].Name, ADoc[side].Active) = 0) then
        begin
          Result[side].Active := k;
          Break;
        end;
      end;
    { 否则此刻的当前页还在 → 不变。 }
    if (Result[side].Active < 0) and (AWorld[side].Active >= 0) then
      for k := 0 to High(Result[side].Order) do
        if (Result[side].Order[k].Side = side)
           and (Result[side].Order[k].Index = AWorld[side].Active) then
        begin
          Result[side].Active := k;
          Break;
        end;
    { 否则第一个;否则没有。 }
    if (Result[side].Active < 0) and (Length(Result[side].Order) > 0) then
      Result[side].Active := 0;
    if ADoc[side].Present then
    begin
      Result[side].Apply := True;
      Result[side].Size := ADoc[side].Size;
      Result[side].Collapsed := ADoc[side].Collapsed;
    end;
  end;
end;

end.
