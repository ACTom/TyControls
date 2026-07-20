{ 网格导出/导入用到的**纯文本编解码**。

  这里只有字符串进、字符串出:没有网格、没有列模型、没有任何控件状态。
  从 tyControls.Grid 里搬出来正是因为这一点 —— 它们本来就是自由函数,
  搬家不需要给网格开任何新的口子,也就不会用"多一个接口"换掉"少一处重复"。

  (架构审计里另外三个候选 —— 撤销栈、筛选/分组的模型、导出的其余部分 ——
  都要先把方法从类里挖出来、再给网格加一层回调接口才搬得动。
  净效果是主文件少几百行、接口多几十行,不划算,明确不做。) }
unit tyControls.Grid.Csv;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { 解析结果:每行一个字段数组。行与行的字段数**不要求一致** ——
    真实的 CSV 经常参差不齐,补齐是调用方的事。 }
  TTyCsvRows = array of TStringArray;

{ 一个 CSV 字段的转义。含分隔符、引号或换行时加引号,内部引号翻倍。 }
function TyCsvQuote(const AValue: string; ADelimiter: Char): string;

{ 字符级流式 CSV 解析:整段文本一次扫完,只有**引号之外**的换行才断行。

  这是为了修一个数据正确性缺陷:早先的做法是先 `TStringList.Text := AText`
  按行切、再逐行拆字段 —— 引号内的换行(Excel 导出很常见)会被当成行分隔符,
  于是行数凭空变多、单元格被拦腰截断,而且**不报任何错**。 }
function TyCsvParse(const AText: string; ADelimiter: Char): TTyCsvRows;

{ HTML 文本转义。导出表格时用,别让单元格里的 < 把表格结构撑破。 }
function TyHtmlEscape(const S: string): string;

implementation

function TyCsvQuote(const AValue: string; ADelimiter: Char): string;
begin
  { 含分隔符、引号或换行的字段必须加引号,内部引号翻倍 —— 否则导出的 CSV 读不回来。 }
  if (Pos(ADelimiter, AValue) > 0) or (Pos('"', AValue) > 0)
     or (Pos(#13, AValue) > 0) or (Pos(#10, AValue) > 0) then
    Result := '"' + StringReplace(AValue, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := AValue;
end;

function TyCsvParse(const AText: string; ADelimiter: Char): TTyCsvRows;
var
  i, n, rowN, colN: Integer;
  cur: string;
  inQuote: Boolean;
  row: TStringArray;

  procedure PushField;
  begin
    SetLength(row, colN + 1);
    row[colN] := cur;
    Inc(colN);
    cur := '';
  end;

  procedure PushRow;
  begin
    PushField;
    SetLength(Result, rowN + 1);
    Result[rowN] := row;
    Inc(rowN);
    SetLength(row, 0);
    colN := 0;
  end;

begin
  SetLength(Result, 0);
  SetLength(row, 0);
  rowN := 0;
  colN := 0;
  cur := '';
  inQuote := False;
  n := Length(AText);
  i := 1;
  while i <= n do
  begin
    if inQuote then
    begin
      if AText[i] = '"' then
      begin
        if (i < n) and (AText[i + 1] = '"') then
        begin
          cur := cur + '"';      { 翻倍的引号 = 一个字面引号 }
          Inc(i);
        end
        else
          inQuote := False;
      end
      else
        cur := cur + AText[i];   { 引号内:换行也只是普通字符 }
    end
    else if AText[i] = '"' then
      inQuote := True
    else if AText[i] = ADelimiter then
      PushField
    else if AText[i] = #13 then
    begin
      PushRow;
      if (i < n) and (AText[i + 1] = #10) then Inc(i);   { 吃掉 CRLF 的 LF }
    end
    else if AText[i] = #10 then
      PushRow
    else
      cur := cur + AText[i];
    Inc(i);
  end;

  { 收尾:文本末尾没有换行时,最后一行还没入账。
    但要区分"真有最后一行"和"末尾就是个换行" —— 后者不该多出一个空行。 }
  if (cur <> '') or (colN > 0) then PushRow;
end;

function TyHtmlEscape(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

end.
