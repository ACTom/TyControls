unit tbproblems;
{ The problem list: TyLintCssEx turned into rows the window shows, plus the tool's own.
  Lint knows only the variables the document defines; the engine resolves the rest from
  the base theme the document sits on, so an "undefined variable" the base defines is not a
  problem here (the library's lint keeps its behaviour -- the filter is the tool's). An
  untitled document cannot resolve url() paths (they are read from the file's folder), so
  each line with a url() says to save first. Rows without a position (the preview could not
  load, a mode was refused) come first, then by line and column. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tyControls.ThemeLint;

resourcestring
  rsTbSaveForAssets = 'Save the file first: url() paths are read from the file''s folder.';

type
  TTbProblemOrigin = (tpoLint, tpoLoad, tpoDocument);
  TTbProblem = record
    Line, Col: Integer;                 { 0 = no position }
    Severity: TTyLintSeverity;
    Origin: TTbProblemOrigin;
    Kind: TTyLintKind;                  { meaningful for tpoLint only }
    Text: string;
  end;
  TTbProblems = array of TTbProblem;

{ names (lower case, no --) the base layer defines, in any mode }
procedure TbBaseVarNames(ADest: TStrings);
{ lint issues (minus undefined variables the base defines) + a hint per line with url()
  when the document has no folder yet; sorted: no position first, then by line and column }
function TbCollectProblems(const AText, ABaseDir: string; AUntitled: Boolean;
  ABaseVars: TStrings): TTbProblems;
{ inserted after every row with the same key, so the list stays sorted }
procedure TbAddProblem(var AList: TTbProblems; ALine, ACol: Integer;
  ASeverity: TTyLintSeverity; AOrigin: TTbProblemOrigin; const AText: string);
function TbHasParseError(const AList: TTbProblems): Boolean;
function TbErrorCount(const AList: TTbProblems): Integer;
{ '12:5  text' / '—  text' }
function TbProblemCaption(const AProblem: TTbProblem): string;

implementation

uses
  tyControls.StyleModel, tyControls.Css.Catalog;

procedure TbBaseVarNames(ADest: TStrings);
const
  cModes: array[0..2] of string = ('', 'light', 'dark');
var
  model: TTyStyleModel;
  m, i: Integer;
  names: TStringList;
begin
  names := TStringList.Create;
  model := TTyStyleModel.Create;   { nothing loaded: the base layer alone }
  try
    names.Sorted := True;
    names.Duplicates := dupIgnore;
    for m := 0 to High(cModes) do
    begin
      model.SetMode(cModes[m]);
      for i := 0 to High(TyCatalogTokens) do
        if model.RawVar(TyCatalogTokens[i]) <> '' then
          names.Add(LowerCase(Copy(TyCatalogTokens[i], 3, MaxInt)));
    end;
    ADest.AddStrings(names);
  finally
    model.Free;
    names.Free;
  end;
end;

{ the sort key: no position first, then line, then column }
function KeyLess(const A, B: TTbProblem): Boolean;
begin
  if (A.Line = 0) <> (B.Line = 0) then
    Exit(A.Line = 0);
  if A.Line <> B.Line then
    Exit(A.Line < B.Line);
  Result := A.Col < B.Col;
end;

procedure InsertSorted(var AList: TTbProblems; const AProblem: TTbProblem);
var
  i, at: Integer;
begin
  { after every row whose key is not greater: stable }
  at := Length(AList);
  while (at > 0) and KeyLess(AProblem, AList[at - 1]) do
    Dec(at);
  SetLength(AList, Length(AList) + 1);
  for i := High(AList) downto at + 1 do
    AList[i] := AList[i - 1];
  AList[at] := AProblem;
end;

procedure SortProblems(var AList: TTbProblems);
var
  src: TTbProblems;
  i: Integer;
begin
  src := Copy(AList);
  AList := nil;
  for i := 0 to High(src) do
    InsertSorted(AList, src[i]);
end;

procedure TbAddProblem(var AList: TTbProblems; ALine, ACol: Integer;
  ASeverity: TTyLintSeverity; AOrigin: TTbProblemOrigin; const AText: string);
var
  p: TTbProblem;
begin
  p := Default(TTbProblem);
  p.Line := ALine;
  p.Col := ACol;
  p.Severity := ASeverity;
  p.Origin := AOrigin;
  p.Kind := tlkParseError;
  p.Text := AText;
  InsertSorted(AList, p);
end;

procedure AppendLint(var AList: TTbProblems; const AIssue: TTyLintIssue);
var
  n: Integer;
begin
  n := Length(AList);
  SetLength(AList, n + 1);
  AList[n] := Default(TTbProblem);
  AList[n].Line := AIssue.Line;
  AList[n].Col := AIssue.Col;
  AList[n].Severity := AIssue.Severity;
  AList[n].Origin := tpoLint;
  AList[n].Kind := AIssue.Kind;
  AList[n].Text := AIssue.Message;
end;

{ a warning on each line with a url() that is not a data: URL, comments skipped (they may
  run over several lines); one per line }
procedure AddUnsavedAssetHints(var AList: TTbProblems; const AText: string);
var
  lines: TStringList;
  li, i, n: Integer;
  s, rest: string;
  inComment, reported: Boolean;
  p: TTbProblem;
begin
  lines := TStringList.Create;
  try
    lines.Text := AText;
    inComment := False;
    for li := 0 to lines.Count - 1 do
    begin
      s := lines[li];
      n := Length(s);
      reported := False;
      i := 1;
      while i <= n do
      begin
        if inComment then
        begin
          if (s[i] = '*') and (i < n) and (s[i + 1] = '/') then
          begin
            inComment := False;
            Inc(i, 2);
          end
          else
            Inc(i);
          Continue;
        end;
        if (s[i] = '/') and (i < n) and (s[i + 1] = '*') then
        begin
          inComment := True;
          Inc(i, 2);
          Continue;
        end;
        if (not reported) and (i + 3 <= n) and SameText(Copy(s, i, 4), 'url(') then
        begin
          rest := TrimLeft(Copy(s, i + 4, MaxInt));
          if (rest <> '') and (rest[1] in ['"', '''']) then
            rest := Copy(rest, 2, MaxInt);
          if not SameText(Copy(rest, 1, 5), 'data:') then
          begin
            p := Default(TTbProblem);
            p.Line := li + 1;
            p.Col := i;
            p.Severity := tlsWarning;
            p.Origin := tpoDocument;
            p.Kind := tlkMissingAsset;
            p.Text := rsTbSaveForAssets;
            SetLength(AList, Length(AList) + 1);
            AList[High(AList)] := p;
            reported := True;
          end;
          Inc(i, 4);
          Continue;
        end;
        Inc(i);
      end;
    end;
  finally
    lines.Free;
  end;
end;

function TbCollectProblems(const AText, ABaseDir: string; AUntitled: Boolean;
  ABaseVars: TStrings): TTbProblems;
var
  issues: TTyLintIssues;
  i: Integer;
begin
  Result := nil;
  issues := TyLintCssEx(AText, ABaseDir);
  for i := 0 to High(issues) do
  begin
    { the engine resolves a variable the base defines; lint only knows the document's }
    if (issues[i].Kind = tlkUndefinedVar) and (ABaseVars <> nil)
       and (ABaseVars.IndexOf(LowerCase(issues[i].Subject)) >= 0) then
      Continue;
    AppendLint(Result, issues[i]);
  end;
  if AUntitled then
    AddUnsavedAssetHints(Result, AText);
  SortProblems(Result);
end;

function TbHasParseError(const AList: TTbProblems): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(AList) do
    if (AList[i].Origin = tpoLint) and (AList[i].Kind = tlkParseError) then
      Exit(True);
  Result := False;
end;

function TbErrorCount(const AList: TTbProblems): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(AList) do
    if AList[i].Severity = tlsError then
      Inc(Result);
end;

function TbProblemCaption(const AProblem: TTbProblem): string;
begin
  if AProblem.Line > 0 then
    Result := Format('%d:%d  %s', [AProblem.Line, AProblem.Col, AProblem.Text])
  else
    Result := #$E2#$80#$94'  ' + AProblem.Text;   { an em dash: no position }
end;

end.
