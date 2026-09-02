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

  A REJECTED OPTION KEEPS THE PREVIOUS ONE. A half-typed config in a design-time
  editor must not blank the chart; the error is reported and the last good tree
  stands.

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

    { Replace the whole option. Returns False on a parse error, in which case the
      previous tree and text are untouched and Error describes what went wrong. }
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
      a decade of answers on the internet, write `xAxis: {...}`.

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

resourcestring
  rsTyOptFunctionValue =
    'JavaScript functions cannot be used here. Write a template string such as '
  + '''{b}: {c}'', or the name of a registered handler such as ''@MyFormatter''.';

implementation

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
  parser := TJSONParser.Create(AText, [joUTF8, joComments, joIgnoreTrailingComma]);
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
        { The previous tree stands. A design-time editor shows the error while
          the chart keeps drawing what it last understood. }
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
