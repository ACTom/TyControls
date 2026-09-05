unit tyControls.AdvChart.Option;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the option tree. THIS IS THE API.

  A chart is configured by an ECharts-shaped option object rather than by
  published properties, because ~1,950 option paths do not fit in an Object
  Inspector and because it makes ECharts' documentation, its gallery and a decade
  of answers on the internet usable as-is.

  RELAXED JSON, NOT STRICT. ECharts configs in the wild are JS object literals:
  unquoted keys, single quotes, trailing commas, comments. Requiring strict JSON
  would make "paste an ECharts config" -- the entire reason to choose an option
  tree -- false. FPC's own fcl-json already accepts all of that outside strict
  mode; verified empirically rather than assumed, and there is no hand-written
  JSON5 lexer here as a result.

  WHAT IT DOES NOT DO, deliberately: incremental merge. ECharts' setOption
  carries normalMerge / replaceMerge / replaceAll with id and name matching and
  deliberate index holes -- about 3,700 lines in its own source, and an XL on its
  own. SetOptionText replaces the option WHOLE (ECharts' notMerge). Nothing in a
  first release needs the incremental form, and building it later changes no call
  site that only ever replaced.

  A REJECTED OPTION LEAVES NO OPTION. The tree goes and Error says why, so the
  chart is blank rather than showing something the option no longer says. The
  earlier rule kept the last good tree, for an editor that re-applied text on
  every keystroke; the editor that was actually built is modal and writes back
  on OK, so what the rule bought was a control whose picture and property
  disagreed with nothing on screen admitting it.

  LCL-free: SysUtils, Classes and fcl-json only. }
interface
uses SysUtils, Classes, fpjson, jsonparser, jsonscanner;

type
  TTyOptionError = record
    { True when there IS an error. A record rather than a nil check so the
      message and position survive alongside the last good tree. }
    Failed: Boolean;
    Message: string;
    Line, Col: Integer;
  end;

  TTyChartOption = class
  private
    FRoot: TJSONData;
    FText: string;
    FError: TTyOptionError;
    procedure SetError(const AMsg: string; ALine, ACol: Integer);
    procedure ClearError;
  public
    constructor Create;
    destructor Destroy; override;

    { Replace the whole option. Returns False on a parse error, in which case
      the tree is DROPPED -- there is no option until one parses -- and Error
      describes what went wrong. FText keeps its last parsed value; the control
      is what remembers the text a host wrote. }
    function SetOptionText(const AText: string): Boolean;
    procedure Clear;

    { Resolve a dotted/indexed path -- 'series[0].itemStyle.color'. nil when any
      step is missing, which is the normal case for an option nobody set, not an
      error. }
    function Find(const APath: string): TJSONData;
    function Has(const APath: string): Boolean;

    { Typed reads with a default. The default is what the theme or the series
      type decided; these never raise, because a chart must draw something when
      an option is absent or is the wrong type. }
    function GetStr(const APath: string; const ADefault: string): string;
    function GetInt(const APath: string; ADefault: Integer): Integer;
    function GetFloat(const APath: string; ADefault: Double): Double;
    function GetBool(const APath: string; ADefault: Boolean): Boolean;
    { Length of the array at APath; 0 when it is absent or is not an array. }
    function CountAt(const APath: string): Integer;

    { ---- component slots ----
      A top-level component may be written as a bare object OR as an array, and
      the two mean the same thing: ECharts normalises with normalizeToArray
      before anything reads it (Global.ts:369). Most of its gallery, and most of
      a decade of answers on the internet, write the bare form.

      CountAt deliberately does NOT normalise -- an object is not an array, and
      a test pins that -- so reaching for it here is the bug this pair exists to
      prevent: a bare object yields zero components and zero diagnostics, and
      the chart silently draws nothing.

      AMainType is a single root key ('series', 'xAxis', 'grid'), not a path:
      normalisation is a rule about component SLOTS, not about every array in
      the tree. `data: 5` is not a one-element data array and must not become one. }
    function ComponentCount(const AMainType: string): Integer;
    function ComponentAt(const AMainType: string; AIndex: Integer): TJSONData;

    property Root: TJSONData read FRoot;
    property Text: string read FText;
    property Error: TTyOptionError read FError;
  end;

{ Does this text look like it contains a JS function value? Used to turn
  fcl-json's correct-but-bare "unexpected token" into a message that says what to
  write instead. Exported so the design-time editor can warn BEFORE parsing. }
function TyOptionTextHasFunction(const AText: string): Boolean;

implementation

uses
  { Only for the diagnostic resourcestrings; kept out of the interface uses so
    the dependency stays one-way and invisible to hosts. LazUTF8 is here for
    UnicodeToUTF8, used by the escape decoder below. }
  tyControls.StrConsts, LazUTF8;

function TyOptionTextHasFunction(const AText: string): Boolean;
var
  low: string;
begin
  low := LowerCase(AText);
  { Deliberately crude. Its only job is to improve a message that is already an
    error, so a false positive costs a slightly-off hint and a false negative
    costs the original message -- neither is a defect worth a JS tokeniser. }
  Result := (Pos('function', low) > 0) or (Pos('=>', low) > 0);
end;

constructor TTyChartOption.Create;
begin
  inherited Create;
  FRoot := nil;
  FText := '';
  ClearError;
end;

destructor TTyChartOption.Destroy;
begin
  FreeAndNil(FRoot);
  inherited Destroy;
end;

procedure TTyChartOption.ClearError;
begin
  FError.Failed := False;
  FError.Message := '';
  FError.Line := 0;
  FError.Col := 0;
end;

procedure TTyChartOption.SetError(const AMsg: string; ALine, ACol: Integer);
begin
  FError.Failed := True;
  FError.Message := AMsg;
  FError.Line := ALine;
  FError.Col := ACol;
end;

procedure TTyChartOption.Clear;
begin
  FreeAndNil(FRoot);
  FText := '';
  ClearError;
end;

{ fcl-json reports position inside the message text rather than in the exception
  type, so dig it out for an editor that wants to put a caret there. Best effort:
  a message we cannot read still reaches the caller intact. }
procedure ExtractPos(const AMsg: string; out ALine, ACol: Integer);
var
  i, j: Integer;
  s: string;
begin
  ALine := 0;
  ACol := 0;
  i := Pos('line ', AMsg);
  if i > 0 then
  begin
    j := i + 5;
    s := '';
    while (j <= Length(AMsg)) and (AMsg[j] in ['0'..'9']) do
    begin
      s := s + AMsg[j];
      Inc(j);
    end;
    ALine := StrToIntDef(s, 0);
  end;
  i := Pos('Pos ', AMsg);
  if i > 0 then
  begin
    j := i + 4;
    s := '';
    while (j <= Length(AMsg)) and (AMsg[j] in ['0'..'9']) do
    begin
      s := s + AMsg[j];
      Inc(j);
    end;
    ACol := StrToIntDef(s, 0);
  end;
end;

{ \uXXXX escapes decoded to UTF-8 before the parser sees them.

  FPC 3.2.2's jsonscanner loses ADJACENT escapes: `"\u4e2d\u6587"` decodes to
  four bytes rather than six, because the second escape overwrites the tail of
  the first. One character between them and it is fine -- which is why it went
  unnoticed, since two escapes in a row is precisely how a CJK string written in
  \u form looks, and this library's own demos carry Chinese labels.

  Only inside strings, and a doubled backslash is a literal backslash rather
  than the start of an escape -- so `"\\u0041"` stays the six characters the
  author wrote. Anything that is not a well-formed escape is passed through
  untouched, leaving the parser to report it. }
function TyDecodeUnicodeEscapes(const AText: string): string;
var
  i, code, lo: Integer;
  inStr: Boolean;
  quote: Char;

  { The four hex digits at i+2, or -1. }
  function HexAt(APos: Integer): Integer;
  var k, d: Integer;
  begin
    Result := -1;
    if APos + 3 > Length(AText) then Exit;
    Result := 0;
    for k := APos to APos + 3 do
    begin
      case AText[k] of
        '0'..'9': d := Ord(AText[k]) - Ord('0');
        'a'..'f': d := Ord(AText[k]) - Ord('a') + 10;
        'A'..'F': d := Ord(AText[k]) - Ord('A') + 10;
      else
        Exit(-1);
      end;
      Result := Result * 16 + d;
    end;
  end;

begin
  if Pos('\u', AText) = 0 then Exit(AText);
  Result := '';
  inStr := False;
  quote := '"';
  i := 1;
  while i <= Length(AText) do
  begin
    if not inStr then
    begin
      if (AText[i] = '"') or (AText[i] = '''') then
      begin
        inStr := True;
        quote := AText[i];
      end;
      Result := Result + AText[i];
      Inc(i);
      Continue;
    end;

    if AText[i] = quote then
    begin
      inStr := False;
      Result := Result + AText[i];
      Inc(i);
      Continue;
    end;

    if AText[i] = '\' then
    begin
      { A doubled backslash is one literal backslash: the `u` after it is text,
        not an escape. Copying both keeps it that way. }
      if (i < Length(AText)) and (AText[i + 1] = 'u') then
      begin
        code := HexAt(i + 2);
        if code >= 0 then
        begin
          Inc(i, 6);
          { A high surrogate is half a character. Join it with its low half; a
            lone one is passed through as U+FFFD rather than emitted as an
            invalid sequence. }
          if (code >= $D800) and (code <= $DBFF) then
          begin
            lo := -1;
            if (i + 1 <= Length(AText)) and (AText[i] = '\')
              and (AText[i + 1] = 'u') then
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
          Result := Result + UnicodeToUTF8(Cardinal(code));
          Continue;
        end;
      end;
      { Not an escape we handle -- copy the backslash AND what follows, so a
        `\"` cannot be mistaken for the end of the string. }
      Result := Result + AText[i];
      Inc(i);
      if i <= Length(AText) then
      begin
        Result := Result + AText[i];
        Inc(i);
      end;
      Continue;
    end;

    Result := Result + AText[i];
    Inc(i);
  end;
end;

function TTyChartOption.SetOptionText(const AText: string): Boolean;
var
  parser: TJSONParser;
  parsed: TJSONData;
  line, col: Integer;
  msg: string;
begin
  Result := False;
  if Trim(AText) = '' then
  begin
    { An empty option is a legitimate state -- a chart with nothing configured --
      and is not an error. }
    Clear;
    Exit(True);
  end;
  parsed := nil;
  { DECODED FIRST -- see TyDecodeUnicodeEscapes. The scanner in FPC 3.2.2 drops
    bytes when two \uXXXX escapes are adjacent, which is what every CJK string
    written in escape form looks like. }
  parser := TJSONParser.Create(TyDecodeUnicodeEscapes(AText),
    [joUTF8, joComments, joIgnoreTrailingComma]);
  try
    try
      parsed := parser.Parse;
    except
      on E: Exception do
      begin
        ExtractPos(E.Message, line, col);
        msg := E.Message;
        if TyOptionTextHasFunction(AText) then
          msg := msg + ' ' + rsTyOptFunctionValue;
        SetError(msg, line, col);
        { THE TREE GOES. An option that does not parse leaves NO chart, not the
          previous one.

          It used to keep the last good tree, on the theory that a design-time
          editor re-applies the text on every keystroke and blanking on each
          half-typed character would be unusable. That premise is gone: the
          editor is a modal dialog that writes back on OK, and the Object
          Inspector commits once per edit, so nothing ever pushes half-typed
          text at the control.

          What was left was a control that lies -- the property holding one
          option while the picture showed another, with nothing on screen
          saying so. At design time that reads as "my edit did nothing", which
          is a worse signal than a blank chart next to an error. }
        FreeAndNil(FRoot);
        Exit(False);
      end;
    end;
  finally
    parser.Free;
  end;
  FreeAndNil(FRoot);
  FRoot := parsed;
  FText := AText;
  ClearError;
  Result := True;
end;

{ Split one path step into a name and an optional index: 'series[0]' -> 'series',
  0. AIndex is -1 when the step carries no subscript. }
procedure SplitStep(const AStep: string; out AName: string; out AIndex: Integer);
var
  lb, rb: Integer;
begin
  AName := AStep;
  AIndex := -1;
  lb := Pos('[', AStep);
  if lb = 0 then Exit;
  rb := Pos(']', AStep);
  if rb <= lb then Exit;
  AName := Copy(AStep, 1, lb - 1);
  AIndex := StrToIntDef(Copy(AStep, lb + 1, rb - lb - 1), -1);
end;

function TTyChartOption.Find(const APath: string): TJSONData;
var
  steps: TStringList;
  i, idx: Integer;
  name: string;
  cur: TJSONData;
begin
  Result := nil;
  if (FRoot = nil) or (APath = '') then Exit;
  cur := FRoot;
  steps := TStringList.Create;
  try
    steps.Delimiter := '.';
    steps.StrictDelimiter := True;
    steps.DelimitedText := APath;
    for i := 0 to steps.Count - 1 do
    begin
      if steps[i] = '' then Exit(nil);
      SplitStep(steps[i], name, idx);
      if name <> '' then
      begin
        if not (cur is TJSONObject) then Exit(nil);
        cur := TJSONObject(cur).Find(name);
        if cur = nil then Exit(nil);
      end;
      if idx >= 0 then
      begin
        if not (cur is TJSONArray) then Exit(nil);
        if idx >= TJSONArray(cur).Count then Exit(nil);
        cur := TJSONArray(cur).Items[idx];
      end;
    end;
    Result := cur;
  finally
    steps.Free;
  end;
end;

function TTyChartOption.Has(const APath: string): Boolean;
begin
  Result := Find(APath) <> nil;
end;

function TTyChartOption.GetStr(const APath: string; const ADefault: string): string;
var d: TJSONData;
begin
  d := Find(APath);
  if (d = nil) or (d.JSONType in [jtNull, jtArray, jtObject]) then
    Exit(ADefault);
  Result := d.AsString;
end;

function TTyChartOption.GetInt(const APath: string; ADefault: Integer): Integer;
var d: TJSONData;
begin
  d := Find(APath);
  if (d = nil) or not (d.JSONType in [jtNumber, jtBoolean]) then
    Exit(ADefault);
  Result := d.AsInteger;
end;

function TTyChartOption.GetFloat(const APath: string; ADefault: Double): Double;
var d: TJSONData;
begin
  d := Find(APath);
  if (d = nil) or (d.JSONType <> jtNumber) then
    Exit(ADefault);
  Result := d.AsFloat;
end;

function TTyChartOption.GetBool(const APath: string; ADefault: Boolean): Boolean;
var d: TJSONData;
begin
  d := Find(APath);
  if (d = nil) or (d.JSONType <> jtBoolean) then
    Exit(ADefault);
  Result := d.AsBoolean;
end;

function TTyChartOption.CountAt(const APath: string): Integer;
var d: TJSONData;
begin
  d := Find(APath);
  if (d = nil) or not (d is TJSONArray) then
    Exit(0);
  Result := TJSONArray(d).Count;
end;

function TTyChartOption.ComponentCount(const AMainType: string): Integer;
var d: TJSONData;
begin
  if (FRoot = nil) or not (FRoot is TJSONObject) then Exit(0);
  d := TJSONObject(FRoot).Find(AMainType);
  if d = nil then Exit(0);
  { jtNull is `xAxis: null` -- written, but written as nothing. }
  if d.JSONType = jtNull then Exit(0);
  if d is TJSONArray then Exit(TJSONArray(d).Count);
  Result := 1;
end;

function TTyChartOption.ComponentAt(const AMainType: string; AIndex: Integer): TJSONData;
var d: TJSONData;
begin
  Result := nil;
  if AIndex < 0 then Exit;
  if (FRoot = nil) or not (FRoot is TJSONObject) then Exit;
  d := TJSONObject(FRoot).Find(AMainType);
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  if d is TJSONArray then
  begin
    if AIndex >= TJSONArray(d).Count then Exit;
    Exit(TJSONArray(d).Items[AIndex]);
  end;
  { A bare component IS index 0, and there is no index 1. }
  if AIndex = 0 then Result := d;
end;

end.
