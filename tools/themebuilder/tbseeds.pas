unit tbseeds;
{ The six seeds of a theme (themes/auto.tycss, its SEED part): --accent, --surface,
  --on-surface, --border, --danger and --radius. Everything else in a theme can be derived
  from them, so the seeds panel shows and edits just these.

  A column is a mode: a theme with @mode blocks has two (light, dark), one with only a
  top-level :root has one (''). Whether it has modes is the style model's answer, not the
  text's: a document whose @mode blocks all come from a file it @imports has two columns
  too (TbSeedColumnsFor, TTbSeedEval.HasModes). The value a column shows is the one the
  engine would use in that mode (TTyStyleModel.RebuildMergedVars): any @mode block for the
  mode wins over any :root, and of each kind the importer wins over what it imports (a
  file's own content goes on top of its imports, StyleModel.ExpandSheet). So, in order: the
  document's own block for the mode (the last declaration counts); an imported file's
  block for it (tssImported -- when the document's :root sets the seed too, that value is
  overridden: Overridden); the document's top-level :root (shared by both modes); an
  imported file's :root (tssImported); else the base theme's (inherited -- shown greyed).
  Only the files the document imports are looked at (TbScanImports), and only for where a
  seed is set, never for what it comes to (that is TTbSeedEval's).

  Changing a seed changes the text as little as it can: a value that is there has just its
  value span replaced (the rest of its line -- other declarations, alignment spaces,
  comments -- stays); a seed that is not there gets one line added to the block that
  should hold it, or one block when there is none. A value that is not a plain colour (a
  plain length for --radius) is an expression -- var(), darken(), system-accent -- and the
  panel asks before replacing it.

  The colours a column shows are worked out by TTbSeedEval: a style model of its own, the
  text loaded over the base the way the preview loads it but WITHOUT the density pack (the
  modern density sets --radius itself), asked once per mode. Not the preview's controller:
  that one is in one mode at a time and carries the density the preview shows. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tyControls.Types, tyControls.StyleModel, tbcssscan;

const
  TbSeedCount = 6;
  TbSeedNames: array[0..TbSeedCount - 1] of string =
    ('accent', 'surface', 'on-surface', 'border', 'danger', 'radius');
  TbRadiusSeed = 5;

type
  { tssShared: only in the top-level :root of a two-mode document; tssImported: a file the
    document @imports decides it }
  TTbSeedSource = (tssOwn, tssShared, tssInherited, tssImported);
  TTbSeedCell = record
    Seed: Integer;
    Column: string;          { '' = a one-mode document; 'light' / 'dark' }
    Source: TTbSeedSource;
    Block, Decl: Integer;    { the document's declaration (the one overridden, for an
                               Overridden cell); -1 when it has none }
    Raw: string;             { as written -- in the document, else in the imported file; ''
                               when inherited }
    IsExpression: Boolean;
    Overridden: Boolean;     { tssImported: the document's :root sets it, an imported @mode
                               block for the column wins over it }
  end;

function TbSeedColumns(AScan: TTbCssScan): TStringArray;       { [''] or ['light', 'dark'] }
function TbSeedColumnsFor(AHasModes: Boolean): TStringArray;   { the same, by the model's answer }
function TbSeedCell(AScan: TTbCssScan; ASeed: Integer; const AColumn: string): TTbSeedCell;
{ the same, with the files the document imports (TbScanImports) taken into account }
function TbSeedCellIn(AScan: TTbCssScan; const AImports: TTbCssScans; ASeed: Integer;
  const AColumn: string): TTbSeedCell;
function TbIsLiteralSeedValue(ASeed: Integer; const ARaw: string): Boolean;
function TbColorText(AColor: TTyColor): string;                { '#RRGGBB'; '#RRGGBBAA' when not opaque }
function TbRadiusText(APx: Integer): string;                    { '6px' }
{ AShared: for a tssShared cell, True = change the :root value, False = add to the column's block;
  for a tssInherited cell of a two-mode document, True = add it to the top-level :root (both
  modes -- what the seeds page offers for --radius first).
  A tssImported cell (TbSeedCell sees it as shared or inherited) takes AShared = False: only
  the document's own block for the column comes after the import and wins.
  nil when there is nowhere to put it (a block that never closes). }
function TbSeedSetEdits(AScan: TTbCssScan; const AEol: string; ASeed: Integer;
  const AColumn, AValue: string; AShared: Boolean): TTbTextEdits;
{ a one-mode document -> two @mode blocks with the five colour seeds (AValues[seed]; the radius
  one is not used); nil for a two-mode one. --radius stays where it is (the :root, or the
  base): in an @mode block it would win over the modern density's radius (the density pack
  is a :root, and any @mode block beats every :root) -- a split must not change the look. }
function TbSplitModesEdits(AScan: TTbCssScan; const AEol: string;
  const AValues: array of string): TTbTextEdits;

type
  TTbSeedValues = array[0..TbSeedCount - 1] of string;   { '#RRGGBB[AA]' / '6px'; '' = none }

  { What a column's seed comes to, on a model of its own. Not the preview's controller: it is
    in one mode at a time (two columns would mean switching it back and forth, and every
    switch repaints the preview), and in the modern density it carries the density pack,
    whose --radius (8px) is not the document's. So: the text loaded over the base as the
    preview loads it (url() and @import from the document's folder) and nothing on top. }
  TTbSeedEval = class
  private
    FModel: TTyStyleModel;
    FLoaded: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    { the text over the base, as the preview loads it but without a density pack; False: it does not load }
    function Load(const AText, ABaseDir: string): Boolean;
    function HasModes: Boolean;     { the loaded theme has @mode blocks, its own or imported }
    function Color(ASeed: Integer; const AColumn: string; out AColor: TTyColor): Boolean;
    function Radius(const AColumn: string; out APx: Integer): Boolean;
    { all six for a column, the model switched to its mode once (Color and Radius switch on
      every call): TbColorText / TbRadiusText, '' for one that does not resolve }
    procedure Values(const AColumn: string; out AValues: TTbSeedValues);
  end;

implementation

uses
  tbthemesource;

{ ---- TTbSeedEval ---- }

constructor TTbSeedEval.Create;
begin
  inherited Create;
  FModel := TTyStyleModel.Create;   { the base layer, as every model starts }
end;

destructor TTbSeedEval.Destroy;
begin
  FModel.Free;
  inherited Destroy;
end;

function TTbSeedEval.Load(const AText, ABaseDir: string): Boolean;
begin
  try
    FModel.LoadFromSource(TTbTextThemeSource.Create(AText, ABaseDir));
    FLoaded := True;
  except
    FLoaded := False;
  end;
  Result := FLoaded;
end;

function TTbSeedEval.HasModes: Boolean;
begin
  Result := FLoaded and (Length(FModel.ModeNames) > 0);
end;

function TTbSeedEval.Color(ASeed: Integer; const AColumn: string; out AColor: TTyColor): Boolean;
var
  s: TTyStyleSet;
begin
  AColor := 0;
  Result := False;
  if not FLoaded then Exit;
  FModel.SetMode(AColumn);
  s := FModel.ResolveOverride('color: var(--' + TbSeedNames[ASeed] + ');');
  if tpTextColor in s.Present then
  begin
    AColor := s.TextColor;
    Result := True;
  end;
end;

procedure TTbSeedEval.Values(const AColumn: string; out AValues: TTbSeedValues);
var
  seed, px: Integer;
  s: TTyStyleSet;
begin
  for seed := 0 to TbSeedCount - 1 do
    AValues[seed] := '';
  if not FLoaded then Exit;
  FModel.SetMode(AColumn);
  for seed := 0 to TbSeedCount - 1 do
    if seed = TbRadiusSeed then
    begin
      px := FModel.ResolveMetric('--radius', -1);
      if px >= 0 then
        AValues[seed] := TbRadiusText(px);
    end
    else
    begin
      s := FModel.ResolveOverride('color: var(--' + TbSeedNames[seed] + ');');
      if tpTextColor in s.Present then
        AValues[seed] := TbColorText(s.TextColor);
    end;
end;

function TTbSeedEval.Radius(const AColumn: string; out APx: Integer): Boolean;
begin
  APx := -1;
  Result := False;
  if not FLoaded then Exit;
  FModel.SetMode(AColumn);
  APx := FModel.ResolveMetric('--radius', -1);
  Result := APx >= 0;
end;

function TbSeedColumns(AScan: TTbCssScan): TStringArray;
begin
  Result := TbSeedColumnsFor(AScan.HasModes);
end;

function TbSeedColumnsFor(AHasModes: Boolean): TStringArray;
begin
  if AHasModes then
  begin
    SetLength(Result, 2);
    Result[0] := 'light';
    Result[1] := 'dark';
  end
  else
  begin
    SetLength(Result, 1);
    Result[0] := '';
  end;
end;

{ the last declaration of AName in the blocks of this kind (and mode): later wins, as in the engine }
function FindLast(AScan: TTbCssScan; AKind: TTbBlockKind; const AMode, AName: string;
  out ABlock, ADecl: Integer): Boolean;
var
  b, d: Integer;
  blk: TTbBlock;
begin
  ABlock := -1;
  ADecl := -1;
  for b := 0 to AScan.Count - 1 do
  begin
    blk := AScan.Block(b);
    if blk.Kind <> AKind then Continue;
    if (AKind = tbkModeRoot) and (blk.Mode <> AMode) then Continue;
    for d := 0 to High(blk.Decls) do
      if SameText(blk.Decls[d].Name, AName) then
      begin
        ABlock := b;
        ADecl := d;
      end;
  end;
  Result := ABlock >= 0;
end;

function TbSeedCell(AScan: TTbCssScan; ASeed: Integer; const AColumn: string): TTbSeedCell;
begin
  Result := TbSeedCellIn(AScan, nil, ASeed, AColumn);
end;

{ the last of the imported files (the one added last, which wins) that sets AName in a block
  of this kind (and mode); its raw value }
function FindImported(const AImports: TTbCssScans; AKind: TTbBlockKind; const AMode, AName: string;
  out ARaw: string): Boolean;
var
  i, b, d: Integer;
begin
  ARaw := '';
  for i := High(AImports) downto 0 do
    if FindLast(AImports[i], AKind, AMode, AName, b, d) then
    begin
      ARaw := AImports[i].DeclValue(b, d);
      Exit(True);
    end;
  Result := False;
end;

function TbSeedCellIn(AScan: TTbCssScan; const AImports: TTbCssScans; ASeed: Integer;
  const AColumn: string): TTbSeedCell;
var
  name, imported: string;
  b, d: Integer;
  inRoot: Boolean;
begin
  Result := Default(TTbSeedCell);
  Result.Seed := ASeed;
  Result.Column := AColumn;
  Result.Block := -1;
  Result.Decl := -1;
  Result.Source := tssInherited;
  if AScan = nil then Exit;
  name := '--' + TbSeedNames[ASeed];
  if (AColumn <> '') and FindLast(AScan, tbkModeRoot, AColumn, name, b, d) then
    Result.Source := tssOwn
  else
  begin
    inRoot := FindLast(AScan, tbkRoot, '', name, b, d);
    if (AColumn <> '') and FindImported(AImports, tbkModeRoot, AColumn, name, imported) then
    begin
      { an imported @mode block beats every :root, the document's too }
      Result.Source := tssImported;
      Result.Overridden := inRoot;
      Result.Raw := imported;
      Result.IsExpression := not TbIsLiteralSeedValue(ASeed, imported);
      if inRoot then
      begin
        Result.Block := b;
        Result.Decl := d;
      end;
      Exit;
    end;
    if not inRoot then
    begin
      if FindImported(AImports, tbkRoot, '', name, imported) then
      begin
        Result.Source := tssImported;
        Result.Raw := imported;
        Result.IsExpression := not TbIsLiteralSeedValue(ASeed, imported);
      end;
      Exit;
    end;
    if AColumn = '' then Result.Source := tssOwn else Result.Source := tssShared;
  end;
  Result.Block := b;
  Result.Decl := d;
  Result.Raw := AScan.DeclValue(b, d);
  Result.IsExpression := not TbIsLiteralSeedValue(ASeed, Result.Raw);
end;

function TbIsLiteralSeedValue(ASeed: Integer; const ARaw: string): Boolean;
var
  s: string;
  i, n: Integer;
begin
  s := Trim(ARaw);
  if ASeed = TbRadiusSeed then
  begin
    if SameText(Copy(s, Length(s) - 1, 2), 'px') then
      SetLength(s, Length(s) - 2);
    if s = '' then Exit(False);
    for i := 1 to Length(s) do
      if not (s[i] in ['0'..'9']) then
        Exit(False);
    Exit(True);
  end;
  if (s = '') or (s[1] <> '#') then Exit(False);
  n := Length(s) - 1;
  if not (n in [3, 4, 6, 8]) then Exit(False);
  for i := 2 to Length(s) do
    if not (s[i] in ['0'..'9', 'a'..'f', 'A'..'F']) then
      Exit(False);
  Result := True;
end;

function TbColorText(AColor: TTyColor): string;
var
  a: Cardinal;
begin
  Result := Format('#%.2X%.2X%.2X', [(AColor shr 16) and $FF, (AColor shr 8) and $FF,
    AColor and $FF]);
  a := (AColor shr 24) and $FF;
  if a <> $FF then
    Result := Result + Format('%.2X', [a]);
end;

function TbRadiusText(APx: Integer): string;
begin
  Result := IntToStr(APx) + 'px';
end;

{ ---- where a line goes ---- }

{ the last block of this kind (and mode) in document order; -1 when none }
function LastBlock(AScan: TTbCssScan; AKind: TTbBlockKind; const AMode: string): Integer;
var
  b: Integer;
begin
  Result := -1;
  for b := 0 to AScan.Count - 1 do
    if (AScan.Block(b).Kind = AKind)
       and ((AKind <> tbkModeRoot) or (AScan.Block(b).Mode = AMode)) then
      Result := b;
end;

function OneEdit(AStart, AStop: Integer; const AText: string): TTbTextEdits;
begin
  SetLength(Result, 1);
  Result[0] := TbEdit(AStart, AStop, AText);
end;

{ ALine as one more declaration of the block: on a line of its own, indented as the block's
  last declaration, when the closing brace is on a line of its own; else just before it }
function InsertIntoBlock(AScan: TTbCssScan; ABlock: Integer; const ALine, AEol: string): TTbTextEdits;
var
  blk: TTbBlock;
  ls, close: Integer;
  indent, before: string;
begin
  Result := nil;
  blk := AScan.Block(ABlock);
  close := blk.CloseBrace;
  if close = 0 then Exit;
  ls := TbLineStart(AScan.Text, close);
  before := Copy(AScan.Text, ls, close - ls);
  if Trim(before) = '' then
  begin
    if Length(blk.Decls) > 0 then
      indent := TbLineIndent(AScan.Text, blk.Decls[High(blk.Decls)].NameStart)
    else
      indent := before + '  ';
    Result := OneEdit(ls, ls, indent + ALine + AEol);
  end
  else if (close > 1) and (AScan.Text[close - 1] in [' ', #9]) then
    Result := OneEdit(close, close, ALine + ' ')
  else
    Result := OneEdit(close, close, ' ' + ALine + ' ');
end;

function ModeBlockText(const AMode: string; const ALines: array of string; const AEol: string): string;
var
  i: Integer;
begin
  Result := '@mode ' + AMode + ' {' + AEol + '  :root {' + AEol;
  for i := 0 to High(ALines) do
    Result := Result + '    ' + ALines[i] + AEol;
  Result := Result + '  }' + AEol + '}';
end;

{ the first block in document order, where it starts (its @mode for a mode block) }
function FirstBlockStart(AScan: TTbCssScan): Integer;
begin
  if AScan.Count = 0 then Exit(0);
  if AScan.Block(0).Kind = tbkModeRoot then
    Result := AScan.Block(0).ModeStart
  else
    Result := AScan.Block(0).HeadStart;
end;

function NewModeBlock(AScan: TTbCssScan; const AMode: string; const ALines: array of string;
  const AEol: string): TTbTextEdits;
var
  b, first, last: Integer;
  block: string;
begin
  Result := nil;
  block := ModeBlockText(AMode, ALines, AEol);
  first := -1;
  last := -1;
  for b := 0 to AScan.Count - 1 do
    if AScan.Block(b).Kind = tbkModeRoot then
    begin
      if first < 0 then first := b;
      last := b;
    end;
  if first >= 0 then
  begin
    { light goes before the first mode block, any other mode after the last }
    if AMode = 'light' then
      Result := OneEdit(AScan.Block(first).ModeStart, AScan.Block(first).ModeStart,
        block + AEol + AEol)
    else if AScan.Block(last).OuterClose > 0 then
      Result := OneEdit(AScan.Block(last).OuterClose + 1, AScan.Block(last).OuterClose + 1,
        AEol + AEol + block);
  end
  else if TbIsBlank(AScan.Text) then
    Result := OneEdit(1, Length(AScan.Text) + 1, block + AEol)
  else
    Result := OneEdit(TbEndInsertPos(AScan.Text), TbEndInsertPos(AScan.Text), AEol + AEol + block);
end;

function NewRootBlock(AScan: TTbCssScan; const ALine, AEol: string): TTbTextEdits;
var
  block: string;
  p: Integer;
begin
  block := ':root {' + AEol + '  ' + ALine + AEol + '}';
  if AScan.Count > 0 then
  begin
    p := FirstBlockStart(AScan);
    Result := OneEdit(p, p, block + AEol + AEol);
  end
  else if TbIsBlank(AScan.Text) then
    Result := OneEdit(1, Length(AScan.Text) + 1, block + AEol)
  else
    Result := OneEdit(TbEndInsertPos(AScan.Text), TbEndInsertPos(AScan.Text), AEol + AEol + block);
end;

function TbSeedSetEdits(AScan: TTbCssScan; const AEol: string; ASeed: Integer;
  const AColumn, AValue: string; AShared: Boolean): TTbTextEdits;
var
  cell: TTbSeedCell;
  decl: TTbDecl;
  target: Integer;
  line: string;
  toRoot: Boolean;
begin
  Result := nil;
  cell := TbSeedCell(AScan, ASeed, AColumn);
  line := '--' + TbSeedNames[ASeed] + ': ' + AValue + ';';
  if (cell.Source = tssOwn) or ((cell.Source = tssShared) and AShared) then
  begin
    { the value span only: the rest of the line (other declarations, alignment, comments) stays }
    decl := AScan.Block(cell.Block).Decls[cell.Decl];
    Exit(OneEdit(decl.ValueStart, decl.ValueEnd, AValue));
  end;
  toRoot := (AColumn = '') or (AShared and (cell.Source = tssInherited));
  if toRoot then
    target := LastBlock(AScan, tbkRoot, '')
  else
    target := LastBlock(AScan, tbkModeRoot, AColumn);
  if target >= 0 then
    Result := InsertIntoBlock(AScan, target, line, AEol)
  else if toRoot then
    Result := NewRootBlock(AScan, line, AEol)
  else
    Result := NewModeBlock(AScan, AColumn, [line], AEol);
end;

function TbSplitModesEdits(AScan: TTbCssScan; const AEol: string;
  const AValues: array of string): TTbTextEdits;
var
  lines: array of string;
  i, b, p: Integer;
  light, dark: string;
begin
  Result := nil;
  if AScan.HasModes or (Length(AValues) < TbSeedCount) then Exit;
  SetLength(lines, TbRadiusSeed);
  for i := 0 to TbRadiusSeed - 1 do
    lines[i] := '--' + TbSeedNames[i] + ': ' + AValues[i] + ';';
  light := ModeBlockText('light', lines, AEol);
  dark := ModeBlockText('dark', lines, AEol);
  if TbIsBlank(AScan.Text) then
    Exit(OneEdit(1, Length(AScan.Text) + 1, light + AEol + AEol + dark + AEol));
  { after the last :root that closes: the mode blocks are read after it, as they must be }
  p := 0;
  for b := 0 to AScan.Count - 1 do
    if (AScan.Block(b).Kind = tbkRoot) and (AScan.Block(b).CloseBrace > 0) then
      p := AScan.Block(b).CloseBrace + 1;
  if p = 0 then
    p := TbEndInsertPos(AScan.Text);
  Result := OneEdit(p, p, AEol + AEol + light + AEol + AEol + dark);
end;

end.
