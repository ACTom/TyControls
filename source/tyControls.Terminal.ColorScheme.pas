unit tyControls.Terminal.ColorScheme;
{$mode objfpc}{$H+}

{ 终端的独立配色方案(6 期):方案对象 TTyTerminalColorScheme,以及 Windows Terminal 配色
  JSON 的读和写。

  自己写的,没有移植代码。
  - 方案里有什么、没设的项怎么办,语义照 xterm.js 的 ITheme(xterm:src/browser/services/
    ThemeService.ts:81-131):失焦选区没设就用聚焦选区、不透明的选区色降到 0.3 透明度。
    这些由控件(tyControls.Terminal 的 EnsurePalette)在建色表时做,本单元只存颜色。
  - 优先级(程序的 OSC 覆盖 > 方案里设了的 > 主题)也在控件里,本单元不知道主题。
  - 格式照 Windows Terminal(github.com/microsoft/terminal,commit 4e2b8bd9):
    src/cascadia/TerminalSettingsModel/ColorScheme.cpp(必选的键、16 色、magenta 别名、
    ToJson 的键序)、JsonUtils.h(颜色只收 "#rgb" / "#rrggbb" 的字符串)、ColorScheme.h 与
    src/inc/DefaultSettings.h(四个可选项的缺省);文档
    https://learn.microsoft.com/en-us/windows/terminal/customize-settings/color-schemes 。
    和 WT 有意不同的几处见设计规格 §11.1.10。

  「未设置」是 clNone,不是 0:TColor 的零值是合法的黑色。clDefault 也当未设置;系统色
  (clWindow 这类)用的时候经 ColorToRGB 解成 RGB。TColor 是 $00BBGGRR,控件的色表和 WT 的
  #RRGGBB 是 $RRGGBB——换算只在 TyTermSchemeColorRgb / TyTermRgbToSchemeColor 两处。

  为什么解析前先自己解 \u 转义(TyTermJsonDecodeEscapes):FPC 3.2.2 的 jsonscanner 遇到
  两个挨着的 \u 转义会丢字节(中文名字写成转义就是这样),\u0000 也会被吞。AdvChart 有一份
  同样用途的预解码(tyControls.AdvChart.Option 的 TyDecodeUnicodeEscapes),但它不认注释
  (settings.json 的注释里有引号,会把串内串外弄反),还会把 \u0022 / \u005C 解成裸的引号、
  反斜杠(裸引号提前结束字符串)。这里另写一份:认 // 与 /* */ 注释,引号、反斜杠、控制
  字符保留成转义。 }

interface

uses
  SysUtils, Classes, Graphics, fpjson, jsonparser, jsonscanner, tyControls.StrConsts;

type
  { 前 16 个的序号就是 ANSI 号 }
  TTyTerminalSchemeSlot = (
    tssBlack, tssRed, tssGreen, tssYellow, tssBlue, tssPurple, tssCyan, tssWhite,
    tssBrightBlack, tssBrightRed, tssBrightGreen, tssBrightYellow,
    tssBrightBlue, tssBrightPurple, tssBrightCyan, tssBrightWhite,
    tssForeground, tssBackground, tssCursor, tssCursorText,
    tssSelection, tssSelectionInactive);

  { 读写的格式。以后加格式就加一个值,读写里各加一个分支;tcfAuto 读时按内容认 }
  TTyTerminalColorSchemeFormat = (tcfAuto, tcfWindowsTerminal);

  ETyTerminalColorSchemeError = class(Exception)
  private
    FKey: string;
  public
    constructor CreateKey(const AKey, AMessage: string);
    { 出错的 JSON 键;'' = 整段文本或整套 }
    property Key: string read FKey;
  end;

  { 一套配色。published 的 23 项在设计器里展开、只有改过的进 .lfm。OnChange 由控件挂上,
    宿主别改写。 }
  TTyTerminalColorScheme = class(TPersistent)
  private
    FOwner: TPersistent;
    FName: string;
    FColors: array[TTyTerminalSchemeSlot] of TColor;
    FRevision: Cardinal;
    FUpdateCount: Integer;
    FChangePending: Boolean;
    FOnChange: TNotifyEvent;
    function GetColor(ASlot: TTyTerminalSchemeSlot): TColor;
    procedure SetColor(ASlot: TTyTerminalSchemeSlot; AValue: TColor);
    function GetSlotColor(AIndex: Integer): TColor;
    procedure SetSlotColor(AIndex: Integer; AValue: TColor);
    procedure SetName(const AValue: string);
    procedure Changed;
  protected
    function GetOwner: TPersistent; override;
  public
    constructor Create(AOwner: TPersistent = nil);
    procedure Assign(ASource: TPersistent); override;
    { 名字和 22 色都相同 }
    function Equals(AObj: TObject): Boolean; override;
    { 全部 clNone、Name '';有变化才发 OnChange(一次) }
    procedure Clear;
    { 22 色都未设置(Name 不算) }
    function IsEmpty: Boolean;
    procedure BeginUpdate;
    { 期间有改动,最外层结束时只发一次 OnChange }
    procedure EndUpdate;
    { 这一槽设了没有、设了是什么 RGB($RRGGBB;系统色经 ColorToRGB) }
    function SlotRgb(ASlot: TTyTerminalSchemeSlot; out ARgb: Cardinal): Boolean;
    { 读一套:AText 是单个方案对象,或带 "schemes" 数组的 settings.json(按 AName 取;
      AName = '' 时数组里得恰好一套完整的)。失败抛 ETyTerminalColorSchemeError,方案不变 }
    procedure LoadFromText(const AText: string; const AName: string = '';
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto);
    { 文件整个读进来再走 LoadFromText;打不开文件时 RTL 的异常照抛 }
    procedure LoadFromFile(const AFileName: string; const AName: string = '';
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto);
    { 不抛:失败返回 False,AError 是消息 }
    function TryLoadFromText(const AText, AName: string; out AError: string;
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto): Boolean;
    function TryLoadFromFile(const AFileName, AName: string; out AError: string;
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto): Boolean;
    { 写成一个 WT 方案对象(键序照 WT 的 ToJson,四空格缩进,LF,末尾一个换行)。名字空或
      16 色不全时抛 ETyTerminalColorSchemeError。CursorText、SelectionInactiveBackground
      不写(WT 没有这两项) }
    function SaveToText(AFormat: TTyTerminalColorSchemeFormat = tcfWindowsTerminal): string;
    procedure SaveToFile(const AFileName: string;
      AFormat: TTyTerminalColorSchemeFormat = tcfWindowsTerminal);
    { 文本里有哪几套:按出现顺序,只列 name 是字符串的对象(不要求 16 色齐);单个对象就是
      它自己的名字(可能是 '');读不了的文本答空数组 }
    class function ListSchemeNames(const AText: string;
      AFormat: TTyTerminalColorSchemeFormat = tcfAuto): TStringArray;
    property Colors[ASlot: TTyTerminalSchemeSlot]: TColor read GetColor write SetColor;
    { 每次 OnChange 加一(控件拿它做色表的缓存键) }
    property Revision: Cardinal read FRevision;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  published
    property Name: string read FName write SetName;
    property Foreground: TColor index Ord(tssForeground) read GetSlotColor write SetSlotColor default clNone;
    property Background: TColor index Ord(tssBackground) read GetSlotColor write SetSlotColor default clNone;
    property CursorColor: TColor index Ord(tssCursor) read GetSlotColor write SetSlotColor default clNone;
    property CursorText: TColor index Ord(tssCursorText) read GetSlotColor write SetSlotColor default clNone;
    property SelectionBackground: TColor index Ord(tssSelection) read GetSlotColor write SetSlotColor default clNone;
    property SelectionInactiveBackground: TColor index Ord(tssSelectionInactive) read GetSlotColor
      write SetSlotColor default clNone;
    property Black: TColor index Ord(tssBlack) read GetSlotColor write SetSlotColor default clNone;
    property Red: TColor index Ord(tssRed) read GetSlotColor write SetSlotColor default clNone;
    property Green: TColor index Ord(tssGreen) read GetSlotColor write SetSlotColor default clNone;
    property Yellow: TColor index Ord(tssYellow) read GetSlotColor write SetSlotColor default clNone;
    property Blue: TColor index Ord(tssBlue) read GetSlotColor write SetSlotColor default clNone;
    property Purple: TColor index Ord(tssPurple) read GetSlotColor write SetSlotColor default clNone;
    property Cyan: TColor index Ord(tssCyan) read GetSlotColor write SetSlotColor default clNone;
    property White: TColor index Ord(tssWhite) read GetSlotColor write SetSlotColor default clNone;
    property BrightBlack: TColor index Ord(tssBrightBlack) read GetSlotColor write SetSlotColor default clNone;
    property BrightRed: TColor index Ord(tssBrightRed) read GetSlotColor write SetSlotColor default clNone;
    property BrightGreen: TColor index Ord(tssBrightGreen) read GetSlotColor write SetSlotColor default clNone;
    property BrightYellow: TColor index Ord(tssBrightYellow) read GetSlotColor write SetSlotColor default clNone;
    property BrightBlue: TColor index Ord(tssBrightBlue) read GetSlotColor write SetSlotColor default clNone;
    property BrightPurple: TColor index Ord(tssBrightPurple) read GetSlotColor write SetSlotColor default clNone;
    property BrightCyan: TColor index Ord(tssBrightCyan) read GetSlotColor write SetSlotColor default clNone;
    property BrightWhite: TColor index Ord(tssBrightWhite) read GetSlotColor write SetSlotColor default clNone;
  end;

{ '#rgb' 或 '#rrggbb',大小写不限,前后不许空白;别的一律 False(ARgb = 0) }
function TyTermParseSchemeColor(const AText: string; out ARgb: Cardinal): Boolean;
{ $RRGGBB -> '#RRGGBB'(大写) }
function TyTermSchemeColorText(ARgb: Cardinal): string;
{ TColor -> $RRGGBB;clNone / clDefault 答 False;系统色经 ColorToRGB }
function TyTermSchemeColorRgb(AColor: TColor; out ARgb: Cardinal): Boolean;
{ $RRGGBB -> TColor($00BBGGRR) }
function TyTermRgbToSchemeColor(ARgb: Cardinal): TColor;
{ 交给 fpjson 之前:字符串里的 \u 转义解成 UTF-8。认 // 与 /* */ 注释(原样拷,里面的引号
  不算);\u0022、\u005C 写回 \" 与 \\,小于 U+0020 的保留原转义;代理对合并,孤立的代理出
  U+FFFD;\\u 是字面的反斜杠加 u;不是完整转义的原样留给解析器报错 }
function TyTermJsonDecodeEscapes(const AText: string): string;
{ WT 的键名(16 色与四个可选项);CursorText / SelectionInactive 答 '' }
function TyTermWtSchemeKey(ASlot: TTyTerminalSchemeSlot): string;
{ 设计器「导入…」用:文本里能导入的方案名(settings.json 的 schemes 里 name 是字符串、16 色
  的键齐的,同名只列一次;单个对象就是它自己的名字,可能是 '')。一个都没有、或读不了时答
  False,AError 是消息 }
function TyTermSchemeImportPlan(const AText: string; out ANames: TStringArray; out AError: string): Boolean;

implementation

const
  WtKeys: array[TTyTerminalSchemeSlot] of string = (
    'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
    'brightBlack', 'brightRed', 'brightGreen', 'brightYellow',
    'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite',
    'foreground', 'background', 'cursorColor', '',
    'selectionBackground', '');

{ ---- 纯函数 ------------------------------------------------------------------------ }

function HexDigit(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function TyTermParseSchemeColor(const AText: string; out ARgb: Cardinal): Boolean;
var
  i, d: Integer;
  v, r, g, b: Cardinal;
begin
  ARgb := 0;
  Result := False;
  if not ((Length(AText) = 4) or (Length(AText) = 7)) then Exit;
  if AText[1] <> '#' then Exit;
  v := 0;
  for i := 2 to Length(AText) do
  begin
    d := HexDigit(AText[i]);
    if d < 0 then Exit;
    v := v * 16 + Cardinal(d);
  end;
  if Length(AText) = 4 then
  begin
    { #rgb:每一位重复一次(#1a2 = #11aa22) }
    r := (v shr 8) and $F;
    g := (v shr 4) and $F;
    b := v and $F;
    v := ((r * 17) shl 16) or ((g * 17) shl 8) or (b * 17);
  end;
  ARgb := v;
  Result := True;
end;

function TyTermSchemeColorText(ARgb: Cardinal): string;
begin
  Result := '#' + IntToHex(ARgb and $FFFFFF, 6);
end;

function TyTermSchemeColorRgb(AColor: TColor; out ARgb: Cardinal): Boolean;
var
  c: Cardinal;
begin
  ARgb := 0;
  if (AColor = clNone) or (AColor = clDefault) then Exit(False);
  { 系统色(高位 $80)解成 RGB;普通色原样($00BBGGRR) }
  c := Cardinal(ColorToRGB(AColor));
  ARgb := ((c and $FF) shl 16) or (c and $FF00) or ((c shr 16) and $FF);
  Result := True;
end;

function TyTermRgbToSchemeColor(ARgb: Cardinal): TColor;
begin
  Result := TColor(((ARgb and $FF) shl 16) or (ARgb and $FF00) or ((ARgb shr 16) and $FF));
end;

function TyTermWtSchemeKey(ASlot: TTyTerminalSchemeSlot): string;
begin
  Result := WtKeys[ASlot];
end;

function TyTermJsonDecodeEscapes(const AText: string): string;
var
  i, n, o, code, lo, k: Integer;
  inStr: Boolean;
  quote: Char;
  buf: string;

  procedure Put(C: Char);
  begin
    Inc(o);
    buf[o] := C;
  end;

  procedure PutCopy(AFrom, ACount: Integer);
  var j: Integer;
  begin
    for j := AFrom to AFrom + ACount - 1 do
      Put(AText[j]);
  end;

  { 位置 APos 起的四位十六进制,或 -1 }
  function HexAt(APos: Integer): Integer;
  var j, d: Integer;
  begin
    Result := -1;
    if APos + 3 > n then Exit;
    Result := 0;
    for j := APos to APos + 3 do
    begin
      d := HexDigit(AText[j]);
      if d < 0 then Exit(-1);
      Result := Result * 16 + d;
    end;
  end;

  procedure PutUtf8(ACode: Cardinal);
  begin
    if ACode < $80 then
      Put(Chr(ACode))
    else if ACode < $800 then
    begin
      Put(Chr($C0 or (ACode shr 6)));
      Put(Chr($80 or (ACode and $3F)));
    end
    else if ACode < $10000 then
    begin
      Put(Chr($E0 or (ACode shr 12)));
      Put(Chr($80 or ((ACode shr 6) and $3F)));
      Put(Chr($80 or (ACode and $3F)));
    end
    else
    begin
      Put(Chr($F0 or (ACode shr 18)));
      Put(Chr($80 or ((ACode shr 12) and $3F)));
      Put(Chr($80 or ((ACode shr 6) and $3F)));
      Put(Chr($80 or (ACode and $3F)));
    end;
  end;

begin
  if Pos('\u', AText) = 0 then Exit(AText);
  n := Length(AText);
  { 解出来的不会比原文长:\uXXXX 六个字节换成至多三个,一对代理十二个换成四个 }
  SetLength(buf, n);
  o := 0;
  inStr := False;
  quote := '"';
  i := 1;
  while i <= n do
  begin
    if not inStr then
    begin
      if (AText[i] = '/') and (i < n) and (AText[i + 1] = '/') then
      begin
        { 行注释:拷到行尾(含换行) }
        k := i;
        while (k <= n) and (AText[k] <> #10) do Inc(k);
        if k <= n then Inc(k);
        PutCopy(i, k - i);
        i := k;
        Continue;
      end;
      if (AText[i] = '/') and (i < n) and (AText[i + 1] = '*') then
      begin
        { 块注释:拷到 */;没收尾就拷到末尾,解析器会报 }
        k := i + 2;
        while (k < n) and not ((AText[k] = '*') and (AText[k + 1] = '/')) do Inc(k);
        if k < n then
          Inc(k, 2)
        else
          k := n + 1;
        PutCopy(i, k - i);
        i := k;
        Continue;
      end;
      if (AText[i] = '"') or (AText[i] = '''') then
      begin
        { 单引号串:jsonscanner 非严格模式收,照样认 }
        inStr := True;
        quote := AText[i];
      end;
      Put(AText[i]);
      Inc(i);
      Continue;
    end;

    if AText[i] = quote then
    begin
      inStr := False;
      Put(AText[i]);
      Inc(i);
      Continue;
    end;

    if AText[i] = '\' then
    begin
      if (i < n) and (AText[i + 1] = 'u') then
      begin
        code := HexAt(i + 2);
        if code >= 0 then
        begin
          k := i;           { 这个转义(或这一对)在原文里的起点 }
          Inc(i, 6);
          if (code >= $D800) and (code <= $DBFF) then
          begin
            lo := -1;
            if (i + 1 <= n) and (AText[i] = '\') and (AText[i + 1] = 'u') then
              lo := HexAt(i + 2);
            if (lo >= $DC00) and (lo <= $DFFF) then
            begin
              code := $10000 + ((code - $D800) shl 10) + (lo - $DC00);
              Inc(i, 6);
            end
            else
              code := $FFFD;
          end
          else if (code >= $DC00) and (code <= $DFFF) then
            code := $FFFD;
          if code = $22 then
          begin
            Put('\');
            Put('"');
          end
          else if code = $5C then
          begin
            Put('\');
            Put('\');
          end
          else if (code < $20) or ((code = $27) and (quote = '''')) then
            { 控制字符(和单引号串里的单引号)保留原转义 }
            PutCopy(k, 6)
          else
            PutUtf8(Cardinal(code));
          Continue;
        end;
      end;
      { 别的转义(含 \\ 与 \"):反斜杠连同后一个字符一起拷,\" 不会被当成串尾、\\u 不会
        被当成转义 }
      Put(AText[i]);
      Inc(i);
      if i <= n then
      begin
        Put(AText[i]);
        Inc(i);
      end;
      Continue;
    end;

    Put(AText[i]);
    Inc(i);
  end;
  SetLength(buf, o);
  Result := buf;
end;

{ ---- ETyTerminalColorSchemeError --------------------------------------------------- }

constructor ETyTerminalColorSchemeError.CreateKey(const AKey, AMessage: string);
begin
  inherited Create(AMessage);
  FKey := AKey;
end;

{ ---- 读 Windows Terminal 的 JSON ---------------------------------------------------- }

const
  { 消息里列名字最多这么多个 }
  MaxListedNames = 20;
  Ellipsis = #$E2#$80#$A6;

{ 四个可选项缺了按 WT 补(ColorScheme.h 的 WINRT_PROPERTY 默认值,DefaultSettings.h):
  前景 #FFFFFF、底 #000000、光标 #FFFFFF、选区 #FFFFFF(取 DEFAULT_FOREGROUND,不是这套的
  前景) }
function WtOptionalDefault(ASlot: TTyTerminalSchemeSlot): Cardinal;
begin
  case ASlot of
    tssBackground: Result := $000000;
  else
    Result := $FFFFFF;
  end;
end;

procedure AddName(var A: TStringArray; const S: string);
begin
  SetLength(A, Length(A) + 1);
  A[High(A)] := S;
end;

function NameList(const ANames: TStringArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ANames) do
  begin
    if i > 0 then Result := Result + ', ';
    if i >= MaxListedNames then
    begin
      Result := Result + Ellipsis;
      Break;
    end;
    Result := Result + ANames[i];
  end;
end;

{ 去 UTF-8 BOM、拒 UTF-16、预解码、解析(认注释与尾逗号;重复键 fpjson 默认抛)。
  调用者释放结果;空文本答 nil。 }
function WtParse(const AText: string): TJSONData;
var
  src: string;
  parser: TJSONParser;
begin
  src := AText;
  if (Length(src) >= 2) and (((src[1] = #$FF) and (src[2] = #$FE)) or ((src[1] = #$FE) and (src[2] = #$FF))) then
    raise ETyTerminalColorSchemeError.CreateKey('', rsTermSchemeUtf16);
  if (Length(src) >= 3) and (src[1] = #$EF) and (src[2] = #$BB) and (src[3] = #$BF) then
    Delete(src, 1, 3);
  parser := TJSONParser.Create(TyTermJsonDecodeEscapes(src), [joUTF8, joComments, joIgnoreTrailingComma]);
  try
    try
      Result := parser.Parse;
    except
      on E: Exception do
        raise ETyTerminalColorSchemeError.CreateKey('', Format(rsTermSchemeBadJson, [E.Message]));
    end;
  finally
    parser.Free;
  end;
end;

{ name 是字符串就答 True 和它;否则 False、'' }
function WtNameOf(AObj: TJSONObject; out AName: string): Boolean;
var
  d: TJSONData;
begin
  AName := '';
  d := AObj.Find('name');
  Result := (d <> nil) and (d.JSONType = jtString);
  if Result then AName := d.AsString;
end;

{ 16 色里这一色的键:主名在就用主名,5 / 13 号主名不在时看 magenta / brightMagenta
  (WT 的 TableColorsMapping 末两项,GH#11456);都不在答 '' }
function WtColourKey(AObj: TJSONObject; ASlot: TTyTerminalSchemeSlot): string;
begin
  Result := WtKeys[ASlot];
  if AObj.IndexOfName(Result) >= 0 then Exit;
  if (ASlot = tssPurple) and (AObj.IndexOfName('magenta') >= 0) then Exit('magenta');
  if (ASlot = tssBrightPurple) and (AObj.IndexOfName('brightMagenta') >= 0) then Exit('brightMagenta');
  Result := '';
end;

{ 16 色缺哪几个键(按槽的顺序,WT 的主名);只看键在不在,值的格式读的时候再查 }
function WtMissingKeys(AObj: TJSONObject): TStringArray;
var
  s: TTyTerminalSchemeSlot;
begin
  Result := nil;
  for s := tssBlack to tssBrightWhite do
    if WtColourKey(AObj, s) = '' then
      AddName(Result, WtKeys[s]);
end;

{ settings.json 的 schemes 里算数的一项:对象、name 是字符串、16 色的键齐(WT 的 FromJson
  对缺 name 或不满 16 色的静默跳过) }
function WtIsCandidate(AItem: TJSONData; out AName: string): Boolean;
begin
  AName := '';
  Result := (AItem is TJSONObject) and WtNameOf(TJSONObject(AItem), AName)
    and (Length(WtMissingKeys(TJSONObject(AItem))) = 0);
end;

{ 一色:必须是字符串、#rgb 或 #rrggbb;否则报错,Key = 键名,消息带原值 }
procedure WtReadColour(AObj: TJSONObject; const AKey: string; ADest: TTyTerminalColorScheme;
  ASlot: TTyTerminalSchemeSlot);
var
  d: TJSONData;
  rgb: Cardinal;
  shown: string;
begin
  d := AObj.Find(AKey);
  if (d <> nil) and (d.JSONType = jtString) and TyTermParseSchemeColor(d.AsString, rgb) then
  begin
    ADest.Colors[ASlot] := TyTermRgbToSchemeColor(rgb);
    Exit;
  end;
  if d = nil then
    shown := ''
  else if d.JSONType = jtString then
    shown := d.AsString
  else
    shown := d.AsJSON;
  raise ETyTerminalColorSchemeError.CreateKey(AKey, Format(rsTermSchemeBadColor, [AKey, shown]));
end;

{ 选中的那一套读进 ADest(一个临时对象):16 色、四个可选项(缺了按 WT 补)、名字。
  CursorText、SelectionInactiveBackground 留未设置(WT 没有这两项)。 }
procedure WtReadScheme(AObj: TJSONObject; ADest: TTyTerminalColorScheme);
var
  s: TTyTerminalSchemeSlot;
  nm: string;
begin
  for s := tssBlack to tssBrightWhite do
    WtReadColour(AObj, WtColourKey(AObj, s), ADest, s);
  for s in [tssForeground, tssBackground, tssCursor, tssSelection] do
    if AObj.IndexOfName(WtKeys[s]) >= 0 then
      WtReadColour(AObj, WtKeys[s], ADest, s)
    else
      ADest.Colors[s] := TyTermRgbToSchemeColor(WtOptionalDefault(s));
  WtNameOf(AObj, nm);
  ADest.Name := nm;
end;

{ 挑出要读的那一套(读的第 3–5 步);错误照 spec §11.1.8 }
function WtChoose(ARoot: TJSONData; const AName: string): TJSONObject;
var
  obj: TJSONObject;
  d: TJSONData;
  arr: TJSONArray;
  i: Integer;
  nm: string;
  names, missing: TStringArray;
  first: TJSONObject;
begin
  if not (ARoot is TJSONObject) then
    raise ETyTerminalColorSchemeError.CreateKey('', rsTermSchemeNotObject);
  obj := TJSONObject(ARoot);
  d := obj.Find('schemes');
  if d <> nil then
  begin
    { settings.json:按出现顺序,name 逐字相等(区分大小写)、16 色齐的第一个(WT 的 emplace
      不覆盖先到的);只校验选中的那一套 }
    if not (d is TJSONArray) then
      raise ETyTerminalColorSchemeError.CreateKey('schemes', rsTermSchemeSchemesNotArray);
    arr := TJSONArray(d);
    names := nil;
    first := nil;
    Result := nil;
    for i := 0 to arr.Count - 1 do
      if WtIsCandidate(arr.Items[i], nm) then
      begin
        AddName(names, nm);
        if first = nil then first := TJSONObject(arr.Items[i]);
        if (AName <> '') and (Result = nil) and (nm = AName) then
          Result := TJSONObject(arr.Items[i]);
      end;
    if AName <> '' then
    begin
      if Result = nil then
        raise ETyTerminalColorSchemeError.CreateKey('', Format(rsTermSchemeNotFound, [AName, NameList(names)]));
    end
    else if Length(names) = 0 then
      raise ETyTerminalColorSchemeError.CreateKey('', rsTermSchemeNoneValid)
    else if Length(names) > 1 then
      raise ETyTerminalColorSchemeError.CreateKey('', Format(rsTermSchemeNeedName, [NameList(names)]))
    else
      Result := first;
    Exit;
  end;
  { 单个方案对象:name 可以没有 }
  WtNameOf(obj, nm);
  if (AName <> '') and (nm <> AName) then
  begin
    names := nil;
    AddName(names, nm);
    raise ETyTerminalColorSchemeError.CreateKey('', Format(rsTermSchemeNotFound, [AName, NameList(names)]));
  end;
  missing := WtMissingKeys(obj);
  if Length(missing) > 0 then
    raise ETyTerminalColorSchemeError.CreateKey(missing[0], Format(rsTermSchemeMissingKeys, [NameList(missing)]));
  Result := obj;
end;

procedure WtLoad(ADest: TTyTerminalColorScheme; const AText, AName: string);
var
  root: TJSONData;
  tmp: TTyTerminalColorScheme;
begin
  root := WtParse(AText);
  try
    tmp := TTyTerminalColorScheme.Create(nil);
    try
      { 读进临时对象,整套读成功才 Assign(一次 OnChange);失败 ADest 不动 }
      WtReadScheme(WtChoose(root, AName), tmp);
      ADest.Assign(tmp);
    finally
      tmp.Free;
    end;
  finally
    root.Free;
  end;
end;

function WtListNames(const AText: string): TStringArray;
var
  root, d: TJSONData;
  i: Integer;
  nm: string;
begin
  Result := nil;
  try
    root := WtParse(AText);
  except
    on Exception do Exit(nil);
  end;
  try
    if not (root is TJSONObject) then Exit;
    d := TJSONObject(root).Find('schemes');
    if d = nil then
    begin
      WtNameOf(TJSONObject(root), nm);
      AddName(Result, nm);
    end
    else if d is TJSONArray then
      for i := 0 to TJSONArray(d).Count - 1 do
        if (TJSONArray(d).Items[i] is TJSONObject) and WtNameOf(TJSONObject(TJSONArray(d).Items[i]), nm) then
          AddName(Result, nm);
  finally
    root.Free;
  end;
end;

{ 名字写成 JSON 串:引号、反斜杠转义,控制字符写成六个字符的 u 转义,其余 UTF-8 原样 }
function WtQuote(const S: string): string;
var
  i: Integer;
begin
  Result := '"';
  for i := 1 to Length(S) do
    case S[i] of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #0..#31: Result := Result + '\u' + IntToHex(Ord(S[i]), 4);
    else
      Result := Result + S[i];
    end;
  Result := Result + '"';
end;

{ WT 的 ColorScheme::ToJson:name、foreground、background、selectionBackground、
  cursorColor,再按表的顺序 16 色;#RRGGBB 大写。四个可选项未设置的不写(WT 读时补),
  16 色缺或名字空报错(WT 会把它当无效跳过,写出去没用) }
function WtSave(AScheme: TTyTerminalColorScheme): string;
const
  Optional: array[0..3] of TTyTerminalSchemeSlot = (tssForeground, tssBackground, tssSelection, tssCursor);
var
  s: TTyTerminalSchemeSlot;
  i: Integer;
  rgb: Cardinal;
  missing: TStringArray;
begin
  if AScheme.Name = '' then
    raise ETyTerminalColorSchemeError.CreateKey('name', rsTermSchemeNoName);
  missing := nil;
  for s := tssBlack to tssBrightWhite do
    if not AScheme.SlotRgb(s, rgb) then
      AddName(missing, WtKeys[s]);
  if Length(missing) > 0 then
    raise ETyTerminalColorSchemeError.CreateKey(missing[0], Format(rsTermSchemeMissingKeys, [NameList(missing)]));
  Result := '{'#10'    "name": ' + WtQuote(AScheme.Name);
  for i := 0 to High(Optional) do
    if AScheme.SlotRgb(Optional[i], rgb) then
      Result := Result + ','#10'    "' + WtKeys[Optional[i]] + '": "' + TyTermSchemeColorText(rgb) + '"';
  for s := tssBlack to tssBrightWhite do
  begin
    AScheme.SlotRgb(s, rgb);
    Result := Result + ','#10'    "' + WtKeys[s] + '": "' + TyTermSchemeColorText(rgb) + '"';
  end;
  Result := Result + #10'}'#10;
end;

function TyTermSchemeImportPlan(const AText: string; out ANames: TStringArray; out AError: string): Boolean;
var
  root, d: TJSONData;
  i, k: Integer;
  nm: string;
  seen: Boolean;
begin
  ANames := nil;
  AError := '';
  try
    root := WtParse(AText);
    try
      d := nil;
      if root is TJSONObject then
        d := TJSONObject(root).Find('schemes');
      if d is TJSONArray then
      begin
        for i := 0 to TJSONArray(d).Count - 1 do
          if WtIsCandidate(TJSONArray(d).Items[i], nm) then
          begin
            { 同名的只有第一个读得到(WT 的 emplace):列一次 }
            seen := False;
            for k := 0 to High(ANames) do
              if ANames[k] = nm then seen := True;
            if not seen then AddName(ANames, nm);
          end;
        if Length(ANames) = 0 then
          raise ETyTerminalColorSchemeError.CreateKey('', rsTermSchemeNoneValid);
      end
      else
      begin
        { 单个对象(或 schemes 不是数组、顶层不是对象):照读的规则报错 }
        WtChoose(root, '');
        WtNameOf(TJSONObject(root), nm);
        AddName(ANames, nm);
      end;
    finally
      root.Free;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      ANames := nil;
      AError := E.Message;
      Result := False;
    end;
  end;
end;

{ ---- TTyTerminalColorScheme -------------------------------------------------------- }

constructor TTyTerminalColorScheme.Create(AOwner: TPersistent);
var
  s: TTyTerminalSchemeSlot;
begin
  inherited Create;
  FOwner := AOwner;
  { 未设置 = clNone(不是 0:0 是黑色);published 的 default clNone 必须等于这里 }
  for s := Low(s) to High(s) do
    FColors[s] := clNone;
end;

function TTyTerminalColorScheme.GetOwner: TPersistent;
begin
  { 设计器的属性路径与「已修改」标记靠它 }
  Result := FOwner;
end;

function TTyTerminalColorScheme.GetColor(ASlot: TTyTerminalSchemeSlot): TColor;
begin
  Result := FColors[ASlot];
end;

procedure TTyTerminalColorScheme.SetColor(ASlot: TTyTerminalSchemeSlot; AValue: TColor);
begin
  if FColors[ASlot] = AValue then Exit;
  FColors[ASlot] := AValue;
  Changed;
end;

function TTyTerminalColorScheme.GetSlotColor(AIndex: Integer): TColor;
begin
  Result := FColors[TTyTerminalSchemeSlot(AIndex)];
end;

procedure TTyTerminalColorScheme.SetSlotColor(AIndex: Integer; AValue: TColor);
begin
  SetColor(TTyTerminalSchemeSlot(AIndex), AValue);
end;

procedure TTyTerminalColorScheme.SetName(const AValue: string);
begin
  if FName = AValue then Exit;
  FName := AValue;
  Changed;
end;

procedure TTyTerminalColorScheme.Changed;
begin
  if FUpdateCount > 0 then
  begin
    FChangePending := True;
    Exit;
  end;
  Inc(FRevision);
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyTerminalColorScheme.Assign(ASource: TPersistent);
var
  src: TTyTerminalColorScheme;
  s: TTyTerminalSchemeSlot;
begin
  if ASource is TTyTerminalColorScheme then
  begin
    src := TTyTerminalColorScheme(ASource);
    BeginUpdate;
    try
      SetName(src.FName);
      for s := Low(s) to High(s) do
        SetColor(s, src.FColors[s]);
    finally
      EndUpdate;
    end;
  end
  else
    inherited Assign(ASource);
end;

function TTyTerminalColorScheme.Equals(AObj: TObject): Boolean;
var
  other: TTyTerminalColorScheme;
  s: TTyTerminalSchemeSlot;
begin
  if AObj = Self then Exit(True);
  if not (AObj is TTyTerminalColorScheme) then Exit(False);
  other := TTyTerminalColorScheme(AObj);
  if other.FName <> FName then Exit(False);
  for s := Low(s) to High(s) do
    if other.FColors[s] <> FColors[s] then Exit(False);
  Result := True;
end;

procedure TTyTerminalColorScheme.Clear;
var
  s: TTyTerminalSchemeSlot;
begin
  BeginUpdate;
  try
    SetName('');
    for s := Low(s) to High(s) do
      SetColor(s, clNone);
  finally
    EndUpdate;
  end;
end;

function TTyTerminalColorScheme.IsEmpty: Boolean;
var
  s: TTyTerminalSchemeSlot;
  rgb: Cardinal;
begin
  for s := Low(s) to High(s) do
    if TyTermSchemeColorRgb(FColors[s], rgb) then Exit(False);
  Result := True;
end;

procedure TTyTerminalColorScheme.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TTyTerminalColorScheme.EndUpdate;
begin
  if FUpdateCount <= 0 then Exit;
  Dec(FUpdateCount);
  if (FUpdateCount = 0) and FChangePending then
  begin
    FChangePending := False;
    Changed;
  end;
end;

function TTyTerminalColorScheme.SlotRgb(ASlot: TTyTerminalSchemeSlot; out ARgb: Cardinal): Boolean;
begin
  Result := TyTermSchemeColorRgb(FColors[ASlot], ARgb);
end;

procedure TTyTerminalColorScheme.LoadFromText(const AText: string; const AName: string;
  AFormat: TTyTerminalColorSchemeFormat);
begin
  case AFormat of
    { 目前只有 WT 一种;以后加格式时 tcfAuto 在这里按内容认 }
    tcfAuto, tcfWindowsTerminal:
      WtLoad(Self, AText, AName);
  end;
end;

function ReadWholeFile(const AFileName: string): string;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, fs.Size);
    if Length(Result) > 0 then
      fs.ReadBuffer(Result[1], Length(Result));
  finally
    fs.Free;
  end;
end;

procedure TTyTerminalColorScheme.LoadFromFile(const AFileName: string; const AName: string;
  AFormat: TTyTerminalColorSchemeFormat);
begin
  LoadFromText(ReadWholeFile(AFileName), AName, AFormat);
end;

function TTyTerminalColorScheme.TryLoadFromText(const AText, AName: string; out AError: string;
  AFormat: TTyTerminalColorSchemeFormat): Boolean;
begin
  AError := '';
  try
    LoadFromText(AText, AName, AFormat);
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function TTyTerminalColorScheme.TryLoadFromFile(const AFileName, AName: string; out AError: string;
  AFormat: TTyTerminalColorSchemeFormat): Boolean;
begin
  AError := '';
  try
    LoadFromFile(AFileName, AName, AFormat);
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function TTyTerminalColorScheme.SaveToText(AFormat: TTyTerminalColorSchemeFormat): string;
begin
  Result := '';
  case AFormat of
    { tcfAuto 写出时就是 WT(目前唯一的格式) }
    tcfAuto, tcfWindowsTerminal:
      Result := WtSave(Self);
  end;
end;

procedure TTyTerminalColorScheme.SaveToFile(const AFileName: string;
  AFormat: TTyTerminalColorSchemeFormat);
var
  txt: string;
  fs: TFileStream;
begin
  { 先拼好再开文件:名字空、缺色时不留下一个空文件;不加 BOM }
  txt := SaveToText(AFormat);
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    if txt <> '' then
      fs.WriteBuffer(txt[1], Length(txt));
  finally
    fs.Free;
  end;
end;

class function TTyTerminalColorScheme.ListSchemeNames(const AText: string;
  AFormat: TTyTerminalColorSchemeFormat): TStringArray;
begin
  Result := nil;
  case AFormat of
    tcfAuto, tcfWindowsTerminal:
      Result := WtListNames(AText);
  end;
end;

end.
