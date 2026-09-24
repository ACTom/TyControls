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

{ 整串合法才答 True 并填 ADoc;不合法答 False,ADoc 全是零值(Present 都为假)。 }
function TyToolLayoutParse(const AText: string; out ADoc: TTyToolLayoutDoc): Boolean;
{ 按 left、right、bottom 的顺序只写 Present 的组。调用方保证名字合法、不重名。 }
function TyToolLayoutFormat(const ADoc: TTyToolLayoutDoc): string;

implementation

const
  { key 区分大小写:Left= 是未知 key。 }
  SideKey: array[TTyToolLayoutSide] of string = ('left', 'right', 'bottom');
  WinsSuffix = 'Wins';
  ActiveSuffix = 'Active';

{ 按 ASep 普通切分,保留空段(空段由调用方判)。 }
function SplitPlain(const S: string; ASep: Char): TStringArray;
var
  i, start, n: Integer;
begin
  Result := nil;
  start := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = ASep) then
    begin
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n] := Copy(S, start, i - start);
      start := i + 1;
    end;
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
  segs, parts, names: TStringArray;
  seen: array of string;
  have: array[TTyToolLayoutSide, 0..2] of Boolean;
  vals: array[TTyToolLayoutSide, 0..2] of string;
  side, other: TTyToolLayoutSide;
  i, j, k, p, n: Integer;
  key: string;
  found: Boolean;
begin
  ADoc := Default(TTyToolLayoutDoc);
  Result := False;
  d := Default(TTyToolLayoutDoc);
  FillChar(have, SizeOf(have), 0);
  { 1. 按 | 切;标签在头、end 在尾,中间不许再出现 end(截断在值中间的串过不了这一关)。 }
  segs := SplitPlain(AText, '|');
  if Length(segs) < 2 then Exit;
  if segs[0] <> TyToolLayoutTag then Exit;
  if segs[High(segs)] <> 'end' then Exit;
  { 2. 中间每段:非空、有 =、key 非空、不重复。已知 key 记值,未知的忽略(以后加的 key)。 }
  seen := nil;
  for i := 1 to High(segs) - 1 do
  begin
    if (segs[i] = '') or (segs[i] = 'end') then Exit;
    p := Pos('=', segs[i]);
    if p <= 1 then Exit;
    key := Copy(segs[i], 1, p - 1);
    for j := 0 to High(seen) do
      if seen[j] = key then Exit;
    SetLength(seen, Length(seen) + 1);
    seen[High(seen)] := key;
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
  { 6. 名字在所有组里唯一(组件名不区分大小写)。 }
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
    for i := 0 to High(d[side].Names) do
      for other := side to High(TTyToolLayoutSide) do
        for j := 0 to High(d[other].Names) do
          if ((other <> side) or (j > i))
             and (CompareText(d[side].Names[i], d[other].Names[j]) = 0) then Exit;
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

end.
