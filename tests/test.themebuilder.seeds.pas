unit test.themebuilder.seeds;
{ The theme builder's seeds (phase 2): which declaration a column's seed comes from, and the
  edits that change it -- the value span only, one line added, or one block added; nothing
  else in the text moves. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tbcssscan, tbseeds;

type
  TTbSeedEditTests = class(TTestCase)
  private
    function SetSeed(const AText: string; ASeed: Integer; const AColumn, AValue: string;
      AShared: Boolean = False; const AEol: string = #10): string;
    function ReadTheme(const ARel: string): string;
  published
    procedure TestOnlyTheValueChanges;
    procedure TestACommentedSeedIsNotTheSeed;
    procedure TestTheLastDeclarationCounts;
    procedure TestAMissingSeedIsALineIndentedAsTheBlock;
    procedure TestAOneLineBlockGetsItOnItsLine;
    procedure TestASharedSeed;
    procedure TestAMissingModeBlock;
    procedure TestAMissingRootBlock;
    procedure TestCRLFStaysCRLF;
    procedure TestABlockThatNeverCloses;
    procedure TestWhatIsALiteral;
    procedure TestSplittingIntoTwoModes;
    procedure TestTheRepositoryThemes;
  end;

const
  { E6: the accent in :root, shared by both modes }
  cSharedDoc = ':root { --accent: #3DAEE9; }'#10'@mode light {'#10'  :root {'#10'    --surface: #EFF0F1;'#10'  }'#10'}'#10 +
    '@mode dark {'#10'  :root {'#10'    --surface: #232629;'#10'  }'#10'}'#10;

implementation

uses
  test.themebuilder.golden;

const
  cAccent = 0;
  cSurface = 1;
  cOnSurface = 2;
  cRadius = 5;

function TTbSeedEditTests.SetSeed(const AText: string; ASeed: Integer; const AColumn,
  AValue: string; AShared: Boolean; const AEol: string): string;
var
  s: TTbCssScan;
  e: TTbTextEdits;
begin
  s := TbScanCss(AText);
  try
    e := TbSeedSetEdits(s, AEol, ASeed, AColumn, AValue, AShared);
    if e = nil then
      Exit('<nil>');
    Result := TbApplyEdits(AText, e);
  finally
    s.Free;
  end;
end;

function TTbSeedEditTests.ReadTheme(const ARel: string): string;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(TbThemesDir + StringReplace(ARel, '/', PathDelim, [rfReplaceAll]));
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

procedure TTbSeedEditTests.TestOnlyTheValueChanges;
const
  cT = '@mode light {'#10'  :root {'#10'  --accent: #3B82F6; --surface: #FFFFFF;'#10'  }'#10'}'#10 +
    '@mode dark {'#10'  :root {'#10'  --accent:     #60A5FA;'#10'  }'#10'}'#10;
begin
  AssertEquals('E1: the surface of the light block',
    StringReplace(cT, '#FFFFFF', '#EEEEEE', []), SetSeed(cT, cSurface, 'light', '#EEEEEE'));
  AssertEquals('E1: the dark accent keeps its alignment',
    StringReplace(cT, '#60A5FA', '#123456', []), SetSeed(cT, cAccent, 'dark', '#123456'));
end;

procedure TTbSeedEditTests.TestACommentedSeedIsNotTheSeed;
const
  cT = ':root {'#10'  /* --accent: #000000; */'#10'  --accent: #111111;'#10'}'#10;
begin
  AssertEquals('E2', StringReplace(cT, '#111111', '#222222', []), SetSeed(cT, cAccent, '', '#222222'));
end;

procedure TTbSeedEditTests.TestTheLastDeclarationCounts;
begin
  AssertEquals('E3', ':root { --accent: #111111; --accent: #333333; }',
    SetSeed(':root { --accent: #111111; --accent: #222222; }', cAccent, '', '#333333'));
end;

procedure TTbSeedEditTests.TestAMissingSeedIsALineIndentedAsTheBlock;
begin
  AssertEquals('E4', ':root {'#10'  --accent: #111111;'#10'  --surface: #FFFFFF;'#10'}'#10,
    SetSeed(':root {'#10'  --accent: #111111;'#10'}'#10, cSurface, '', '#FFFFFF'));
end;

procedure TTbSeedEditTests.TestAOneLineBlockGetsItOnItsLine;
const
  cT = '@mode light { :root { --accent: #1E66F5; } }'#10'@mode dark  { :root { --accent: #89B4FA; } }'#10;
begin
  AssertEquals('E5', '@mode light { :root { --accent: #1E66F5; --radius: 8px; } }'#10 +
    '@mode dark  { :root { --accent: #89B4FA; } }'#10, SetSeed(cT, cRadius, 'light', '8px'));
end;

procedure TTbSeedEditTests.TestASharedSeed;
var
  s: TTbCssScan;
  c: TTbSeedCell;
begin
  s := TbScanCss(cSharedDoc);
  try
    c := TbSeedCell(s, cAccent, 'light');
    AssertEquals('E6: shared', Ord(tssShared), Ord(c.Source));
    AssertEquals('E6: as written', '#3DAEE9', c.Raw);
  finally
    s.Free;
  end;
  AssertEquals('E6: changed in :root', StringReplace(cSharedDoc, '#3DAEE9', '#000000', []),
    SetSeed(cSharedDoc, cAccent, 'light', '#000000', True));
  AssertEquals('E6: added to the light block',
    StringReplace(cSharedDoc, '    --surface: #EFF0F1;'#10,
      '    --surface: #EFF0F1;'#10'    --accent: #000000;'#10, []),
    SetSeed(cSharedDoc, cAccent, 'light', '#000000', False));
end;

procedure TTbSeedEditTests.TestAMissingModeBlock;
const
  cT = '@mode light {'#10'  :root {'#10'    --accent: #111111;'#10'  }'#10'}'#10;
  cT2 = '@mode dark {'#10'  :root {'#10'    --accent: #222222;'#10'  }'#10'}'#10;
begin
  AssertEquals('E7: dark after',
    Copy(cT, 1, Length(cT) - 1) + #10#10'@mode dark {'#10'  :root {'#10'    --accent: #222222;'#10'  }'#10'}'#10,
    SetSeed(cT, cAccent, 'dark', '#222222'));
  AssertEquals('E7: light before',
    '@mode light {'#10'  :root {'#10'    --accent: #111111;'#10'  }'#10'}'#10#10 + cT2,
    SetSeed(cT2, cAccent, 'light', '#111111'));
end;

procedure TTbSeedEditTests.TestAMissingRootBlock;
begin
  AssertEquals('E8: before the first rule',
    ':root {'#10'  --accent: #111111;'#10'}'#10#10'TyButton { color: red; }'#10,
    SetSeed('TyButton { color: red; }'#10, cAccent, '', '#111111'));
  AssertEquals('E8: an empty text', ':root {'#10'  --accent: #111111;'#10'}'#10,
    SetSeed('', cAccent, '', '#111111'));
end;

procedure TTbSeedEditTests.TestCRLFStaysCRLF;
begin
  AssertEquals('E9', ':root {'#13#10'  --accent: #111111;'#13#10'  --surface: #FFFFFF;'#13#10'}'#13#10,
    SetSeed(':root {'#13#10'  --accent: #111111;'#13#10'}'#13#10, cSurface, '', '#FFFFFF', False, #13#10));
end;

procedure TTbSeedEditTests.TestABlockThatNeverCloses;
begin
  AssertEquals('E10: a value is still replaced', ':root { --accent: #222222;',
    SetSeed(':root { --accent: #111111;', cAccent, '', '#222222'));
  AssertEquals('E10: nowhere to add a line', '<nil>',
    SetSeed(':root { --accent: #111111;', cSurface, '', '#FFFFFF'));
end;

procedure TTbSeedEditTests.TestWhatIsALiteral;
begin
  AssertTrue('E11: #abc', TbIsLiteralSeedValue(cAccent, '#abc'));
  AssertTrue('E11: #AABBCCDD', TbIsLiteralSeedValue(cAccent, '#AABBCCDD'));
  AssertFalse('E11: darken', TbIsLiteralSeedValue(cAccent, 'darken(--x, 4%)'));
  AssertFalse('E11: system-accent', TbIsLiteralSeedValue(cAccent, 'system-accent'));
  AssertFalse('E11: var', TbIsLiteralSeedValue(cAccent, 'var(--a)'));
  AssertFalse('E11: a colour name', TbIsLiteralSeedValue(cAccent, 'red'));
  AssertTrue('E11: 6px', TbIsLiteralSeedValue(cRadius, '6px'));
  AssertTrue('E11: 6', TbIsLiteralSeedValue(cRadius, '6'));
  AssertTrue('E11: 12PX', TbIsLiteralSeedValue(cRadius, '12PX'));
  AssertFalse('E11: var radius', TbIsLiteralSeedValue(cRadius, 'var(--r)'));
  AssertFalse('E11: 6em', TbIsLiteralSeedValue(cRadius, '6em'));
  AssertEquals('an opaque colour', '#123456', TbColorText($FF123456));
  AssertEquals('a translucent one', '#12345680', TbColorText($80123456));
  AssertEquals('a radius', '6px', TbRadiusText(6));
end;

procedure TTbSeedEditTests.TestSplittingIntoTwoModes;
const
  cT = ':root {'#10'  --accent: #111111; --radius: 4px;'#10'  --muted: #999999;'#10'}'#10'TyButton { color: red; }'#10;
  cHead = ':root {'#10'  --accent: #111111; --radius: 4px;'#10'  --muted: #999999;'#10'}';
  cSix = '    --accent: #111111;'#10'    --surface: #FFFFFF;'#10'    --on-surface: #1F2937;'#10 +
    '    --border: #D1D5DB;'#10'    --danger: #EF4444;'#10'    --radius: 4px;'#10;
var
  s, s2: TTbCssScan;
  e: TTbTextEdits;
  after: string;
  cols: TStringArray;
  seed, col: Integer;
begin
  s := TbScanCss(cT);
  try
    e := TbSplitModesEdits(s, #10, ['#111111', '#FFFFFF', '#1F2937', '#D1D5DB', '#EF4444', '4px']);
    after := TbApplyEdits(cT, e);
  finally
    s.Free;
  end;
  AssertEquals('E12: two blocks after the :root', cHead +
    #10#10'@mode light {'#10'  :root {'#10 + cSix + '  }'#10'}'#10#10 +
    '@mode dark {'#10'  :root {'#10 + cSix + '  }'#10'}' +
    #10'TyButton { color: red; }'#10, after);
  s2 := TbScanCss(after);
  try
    cols := TbSeedColumns(s2);
    AssertEquals('E12: two columns', 2, Length(cols));
    AssertEquals('E12: light', 'light', cols[0]);
    AssertEquals('E12: dark', 'dark', cols[1]);
    for seed := 0 to TbSeedCount - 1 do
      for col := 0 to 1 do
        AssertEquals('E12: own ' + TbSeedNames[seed] + ' ' + cols[col], Ord(tssOwn),
          Ord(TbSeedCell(s2, seed, cols[col]).Source));
    AssertTrue('E12: a two-mode document is not split again',
      Length(TbSplitModesEdits(s2, #10, ['#111111', '#FFFFFF', '#1F2937', '#D1D5DB', '#EF4444', '4px'])) = 0);
  finally
    s2.Free;
  end;
end;

procedure TTbSeedEditTests.TestTheRepositoryThemes;
var
  s: TTbCssScan;
  seed: Integer;
  c: TTbSeedCell;
  cols: TStringArray;

  procedure Open(const ARel: string);
  begin
    FreeAndNil(s);
    s := TbScanCss(ReadTheme(ARel));
  end;

begin
  s := nil;
  try
    Open('auto.tycss');
    for seed := 0 to TbSeedCount - 1 do
    begin
      AssertEquals('E13: auto light ' + TbSeedNames[seed], Ord(tssOwn), Ord(TbSeedCell(s, seed, 'light').Source));
      AssertEquals('E13: auto dark ' + TbSeedNames[seed], Ord(tssOwn), Ord(TbSeedCell(s, seed, 'dark').Source));
    end;
    Open('builtin/classic.tycss');
    AssertEquals('E13: classic light surface', Ord(tssInherited), Ord(TbSeedCell(s, cSurface, 'light').Source));
    AssertEquals('E13: classic dark surface', Ord(tssOwn), Ord(TbSeedCell(s, cSurface, 'dark').Source));
    Open('builtin/win11.tycss');
    c := TbSeedCell(s, cRadius, 'light');
    AssertEquals('E13: win11 light radius', Ord(tssShared), Ord(c.Source));
    AssertEquals('E13: win11 radius as written', '5px', c.Raw);
    AssertEquals('E13: win11 dark radius', Ord(tssShared), Ord(TbSeedCell(s, cRadius, 'dark').Source));
    Open('builtin/breeze.tycss');
    AssertEquals('E13: breeze light accent', Ord(tssShared), Ord(TbSeedCell(s, cAccent, 'light').Source));
    AssertEquals('E13: breeze dark accent', Ord(tssShared), Ord(TbSeedCell(s, cAccent, 'dark').Source));
    Open('builtin/aero.tycss');
    c := TbSeedCell(s, cSurface, 'dark');
    AssertEquals('E13: aero dark surface', Ord(tssOwn), Ord(c.Source));
    AssertTrue('E13: an expression', c.IsExpression);
    Open('system.tycss');
    c := TbSeedCell(s, cAccent, 'light');
    AssertTrue('E13: system accent is an expression', c.IsExpression);
    AssertEquals('E13: system-accent', 'system-accent', c.Raw);
    Open('light.tycss');
    cols := TbSeedColumns(s);
    AssertEquals('E13: light has one column', 1, Length(cols));
    AssertEquals('E13: the one', '', cols[0]);
    for seed := 0 to TbSeedCount - 1 do
      AssertEquals('E13: light ' + TbSeedNames[seed], Ord(tssOwn), Ord(TbSeedCell(s, seed, '').Source));
    Open('palettes/catppuccin.tycss');
    AssertEquals('E13: catppuccin light radius', Ord(tssInherited), Ord(TbSeedCell(s, cRadius, 'light').Source));
    AssertEquals('E13: catppuccin dark radius', Ord(tssInherited), Ord(TbSeedCell(s, cRadius, 'dark').Source));
    AssertEquals('on-surface is a seed', 'on-surface', TbSeedNames[cOnSurface]);
  finally
    s.Free;
  end;
end;

initialization
  RegisterTest(TTbSeedEditTests);
end.
