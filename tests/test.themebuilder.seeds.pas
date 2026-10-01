unit test.themebuilder.seeds;
{ The theme builder's seeds (phase 2): which declaration a column's seed comes from, and the
  edits that change it -- the value span only, one line added, or one block added; nothing
  else in the text moves. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, Dialogs, fpcunit, testregistry, tbcssscan, tbseeds, tbseedsframe;

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

  { The seeds panel, built headless (no parent). OnAsk answers from FAnswer and counts,
    OnEdits records what it was handed and counts; nothing is shown. }
  TTbSeedsFrameTests = class(TTestCase)
  private
    FFrame: TTbSeedsFrame;
    FAnswer: TModalResult;
    FAsked: Integer;
    FEdits: Integer;
    FLastText: string;
    FLastEdits: TTbTextEdits;
    FSyncText: string;
    FSynced: Integer;
    function AskStub(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult;
    procedure EditsStub(Sender: TObject; const AText: string; const AEdits: TTbTextEdits);
    procedure SyncStub(Sender: TObject);
    function Applied: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheMinimalTemplate;
    procedure TestAOneModeDocument;
    procedure TestInheritedSeedsAreGreyAndPerMode;
    procedure TestAnExpressionIsAskedAbout;
    procedure TestASharedSeedIsAskedAbout;
    procedure TestABrokenDocumentDisablesThePage;
    procedure TestTheDensityDoesNotCount;
    procedure TestARefreshWritesNothingBack;
    procedure TestSplittingFromThePanel;
    procedure TestTheRadiusOfTheDarkColumn;
    procedure TestTheWindowCatchesUpFirst;
  end;

const
  { E6: the accent in :root, shared by both modes }
  cSharedDoc = ':root { --accent: #3DAEE9; }'#10'@mode light {'#10'  :root {'#10'    --surface: #EFF0F1;'#10'  }'#10'}'#10 +
    '@mode dark {'#10'  :root {'#10'    --surface: #232629;'#10'  }'#10'}'#10;

implementation

uses
  tyControls.Types, tyControls.DefaultTheme, tyControls.ColorButton, tbtemplates, tbpreview,
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

{ ---- the panel ---- }

const
  cDarkDoc = '@mode light { :root { --accent: #111111; } }'#10'@mode dark { :root { --accent: #222222; } }';
  cExprDoc = '@mode light { :root { --surface: darken(#FFFFFF, 10%); } }'#10 +
    '@mode dark { :root { --surface: #222222; } }';

procedure TTbSeedsFrameTests.SetUp;
begin
  FFrame := TTbSeedsFrame.Create(nil);
  FFrame.OnAsk := @AskStub;
  FFrame.OnEdits := @EditsStub;
  FAnswer := mrCancel;
  FAsked := 0;
  FEdits := 0;
  FLastText := '';
  FLastEdits := nil;
  FSyncText := '';
  FSynced := 0;
end;

procedure TTbSeedsFrameTests.TearDown;
begin
  FreeAndNil(FFrame);
end;

function TTbSeedsFrameTests.AskStub(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult;
begin
  Inc(FAsked);
  Result := FAnswer;
end;

procedure TTbSeedsFrameTests.EditsStub(Sender: TObject; const AText: string;
  const AEdits: TTbTextEdits);
begin
  Inc(FEdits);
  FLastText := AText;
  FLastEdits := Copy(AEdits);
end;

{ the window catching up: a newer text than the panel last scanned, once }
procedure TTbSeedsFrameTests.SyncStub(Sender: TObject);
begin
  Inc(FSynced);
  if FSyncText <> '' then
  begin
    FFrame.UpdateFrom(FSyncText, '', False);
    FSyncText := '';
  end;
end;

function TTbSeedsFrameTests.Applied: string;
begin
  Result := TbApplyEdits(FLastText, FLastEdits);
end;

procedure TTbSeedsFrameTests.TestTheMinimalTemplate;
var
  seed, col: Integer;
begin
  FFrame.UpdateFrom(TbMinimalTemplate, '', False);
  AssertEquals('SF1: two columns', 2, Length(FFrame.Columns));
  AssertEquals('SF1: light', 'light', FFrame.Columns[0]);
  AssertEquals('SF1: dark', 'dark', FFrame.Columns[1]);
  AssertTrue('SF1: the dark swatches show', FFrame.Swatch(0, 1).Visible);
  AssertFalse('SF1: no split', FFrame.SplitButton.Visible);
  AssertFalse('SF1: not broken', FFrame.Broken);
  AssertEquals('SF1: light accent', '#3B82F6', FFrame.ResolvedText(0, 0));
  AssertEquals('SF1: dark accent', '#60A5FA', FFrame.ResolvedText(0, 1));
  AssertEquals('SF1: light radius', '6px', FFrame.ResolvedText(TbRadiusSeed, 0));
  AssertEquals('SF1: dark radius', '6px', FFrame.ResolvedText(TbRadiusSeed, 1));
  for seed := 0 to TbSeedCount - 1 do
    for col := 0 to 1 do
      AssertEquals('SF1: no note ' + IntToStr(seed) + '/' + IntToStr(col), '',
        FFrame.Note(seed, col).Caption);
  AssertEquals('SF1: the dark swatch shows the dark accent', '#60A5FA',
    TyColorHex(FFrame.Swatch(0, 1).SelectedColor));
  AssertEquals('SF1: the light one the light accent', '#3B82F6',
    TyColorHex(FFrame.Swatch(0, 0).SelectedColor));
  AssertEquals('SF1: the spin box', 6, FFrame.RadiusSpin(1).Value);
end;

procedure TTbSeedsFrameTests.TestAOneModeDocument;
begin
  FFrame.UpdateFrom(TyBuiltinThemeCss, '', False);
  AssertEquals('SF2: one column', 1, Length(FFrame.Columns));
  AssertEquals('SF2: the mode-less one', '', FFrame.Columns[0]);
  AssertFalse('SF2: no right column', FFrame.Swatch(0, 1).Visible);
  AssertFalse('SF2: no right spin box', FFrame.RadiusSpin(1).Visible);
  AssertTrue('SF2: split is offered', FFrame.SplitButton.Visible);
  AssertEquals('SF2: says so', rsTbSeedsSingleMode, FFrame.ModeNote.Caption);
end;

procedure TTbSeedsFrameTests.TestInheritedSeedsAreGreyAndPerMode;
begin
  FFrame.UpdateFrom(cDarkDoc, '', False);
  AssertEquals('SF3: light surface inherited', Ord(tssInherited), Ord(FFrame.Cell(1, 0).Source));
  AssertEquals('SF3: dark surface inherited', Ord(tssInherited), Ord(FFrame.Cell(1, 1).Source));
  AssertEquals('SF3: says so', rsTbSeedInherited, FFrame.Note(1, 0).Caption);
  AssertFalse('SF3: greyed', FFrame.Note(1, 0).Enabled);
  AssertTrue('SF3: an own one is not', FFrame.Note(0, 0).Enabled);
  AssertEquals('SF3: the base light surface', '#FFFFFF', FFrame.ResolvedText(1, 0));
  AssertEquals('SF3: the base dark surface', '#1E1E1E', FFrame.ResolvedText(1, 1));
end;

procedure TTbSeedsFrameTests.TestAnExpressionIsAskedAbout;
begin
  FFrame.UpdateFrom(cExprDoc, '', False);
  AssertEquals('an expression', rsTbSeedExpression, FFrame.Note(1, 0).Caption);
  FAnswer := mrNo;
  AssertFalse('SF4: no keeps it', FFrame.ApplyValue(1, 0, '#EEEEEE'));
  AssertEquals('SF4: nothing handed over', 0, FEdits);
  AssertEquals('SF4: asked once', 1, FAsked);
  FAnswer := mrYes;
  AssertTrue('SF4: yes replaces it', FFrame.ApplyValue(1, 0, '#EEEEEE'));
  AssertEquals('SF4: one set of edits', 1, FEdits);
  AssertEquals('SF4: the expression became the colour',
    StringReplace(cExprDoc, 'darken(#FFFFFF, 10%)', '#EEEEEE', []), Applied);
  FAsked := 0;
  AssertTrue('SF4: a literal', FFrame.ApplyValue(1, 1, '#333333'));
  AssertEquals('SF4: is not asked about', 0, FAsked);
end;

procedure TTbSeedsFrameTests.TestASharedSeedIsAskedAbout;
begin
  FFrame.UpdateFrom(cSharedDoc, '', False);
  AssertEquals('from :root', rsTbSeedShared, FFrame.Note(0, 0).Caption);
  FAnswer := mrYes;
  AssertTrue('SF5: yes', FFrame.ApplyValue(0, 0, '#000000'));
  AssertEquals('SF5: yes changes :root', StringReplace(cSharedDoc, '#3DAEE9', '#000000', []), Applied);
  FAnswer := mrNo;
  AssertTrue('SF5: no', FFrame.ApplyValue(0, 0, '#000000'));
  AssertEquals('SF5: no adds to the light block',
    StringReplace(cSharedDoc, '    --surface: #EFF0F1;'#10,
      '    --surface: #EFF0F1;'#10'    --accent: #000000;'#10, []), Applied);
  FEdits := 0;
  FAnswer := mrCancel;
  AssertFalse('SF5: cancel', FFrame.ApplyValue(0, 0, '#000000'));
  AssertEquals('SF5: cancel changes nothing', 0, FEdits);
  AssertEquals('SF5: it asked each time', 3, FAsked);
end;

procedure TTbSeedsFrameTests.TestABrokenDocumentDisablesThePage;
begin
  FFrame.UpdateFrom('TyButton {', '', True);
  AssertTrue('SF6: broken', FFrame.Broken);
  FAnswer := mrYes;
  AssertFalse('SF6: no change', FFrame.ApplyValue(0, 0, '#000000'));
  AssertEquals('SF6: not asked', 0, FAsked);
  AssertEquals('SF6: nothing handed over', 0, FEdits);
  AssertEquals('SF6: says why', rsTbSeedsBroken, FFrame.ModeNote.Caption);
  AssertFalse('SF6: the page is disabled', FFrame.Scroll.Enabled);
  AssertFalse('SF6: no split either', FFrame.SplitButton.Visible);
  FFrame.UpdateFrom(TbMinimalTemplate, '', False);
  AssertTrue('a good one enables it', FFrame.Scroll.Enabled);
  FFrame.UpdateFrom('TyButton { border-radius: 1px 2px 3px; }', '', False);
  AssertTrue('SF6: a text that does not load is broken too', FFrame.Broken);
end;

{ The preview in the modern density carries the density pack: a theme that sets --radius
  in its top-level :root (as the base does) is drawn with the pack's 8px there. The panel
  shows what the DOCUMENT says. (A theme with --radius in its @mode blocks keeps it in the
  preview too: the mode's :root is merged over the top-level one, the pack included.) }
procedure TTbSeedsFrameTests.TestTheDensityDoesNotCount;
var
  preview: TTbPreviewFrame;
  err: string;
begin
  preview := TTbPreviewFrame.Create(nil);
  try
    AssertTrue('loaded', preview.LoadDocument(TyBuiltinThemeCss, '', err));
    AssertEquals('classic: the document''s', 6, preview.Controller.Model.ResolveMetric('--radius', -1));
    AssertTrue('modern', preview.SetModern(True));
    AssertEquals('SF7: the preview in modern is 8', 8, preview.Controller.Model.ResolveMetric('--radius', -1));
    FFrame.UpdateFrom(TyBuiltinThemeCss, '', False);
    AssertEquals('SF7: the panel says what the document says', '6px', FFrame.ResolvedText(TbRadiusSeed, 0));
  finally
    preview.Free;
  end;
end;

procedure TTbSeedsFrameTests.TestARefreshWritesNothingBack;
begin
  FFrame.UpdateFrom(TbMinimalTemplate, '', False);
  AssertEquals('the first light accent', '#3B82F6', FFrame.ResolvedText(0, 0));
  FFrame.UpdateFrom(cDarkDoc, '', False);
  AssertEquals('SF8: a different light accent', '#111111', FFrame.ResolvedText(0, 0));
  AssertEquals('SF8: refreshing wrote nothing', 0, FEdits);
  FFrame.Swatch(0, 0).SelectedColor := TyRGBA($12, $34, $56, $FF);
  AssertEquals('SF8: a pick writes once', 1, FEdits);
  AssertEquals('SF8: the value', '#123456', FLastEdits[0].Text);
end;

procedure TTbSeedsFrameTests.TestSplittingFromThePanel;
begin
  FFrame.UpdateFrom(TyBuiltinThemeCss, '', False);
  AssertTrue('SF9: split', FFrame.SplitModes);
  AssertEquals('SF9: one set of edits', 1, FEdits);
  FFrame.UpdateFrom(Applied, '', False);
  AssertEquals('SF9: two columns', 2, Length(FFrame.Columns));
  AssertEquals('SF9: light', 'light', FFrame.Columns[0]);
  AssertEquals('SF9: own light', Ord(tssOwn), Ord(FFrame.Cell(1, 0).Source));
  AssertEquals('SF9: own dark', Ord(tssOwn), Ord(FFrame.Cell(1, 1).Source));
  AssertEquals('SF9: own dark radius', Ord(tssOwn), Ord(FFrame.Cell(TbRadiusSeed, 1).Source));
  AssertEquals('SF9: dark starts as light', FFrame.ResolvedText(1, 0), FFrame.ResolvedText(1, 1));
  AssertEquals('SF9: the dark accent too', FFrame.ResolvedText(0, 0), FFrame.ResolvedText(0, 1));
  AssertFalse('SF9: no split now', FFrame.SplitModes);
end;

procedure TTbSeedsFrameTests.TestTheRadiusOfTheDarkColumn;
begin
  FFrame.UpdateFrom(TbMinimalTemplate, '', False);
  FFrame.RadiusSpin(1).Value := 9;
  AssertEquals('SF10: one set of edits', 1, FEdits);
  AssertEquals('SF10: the value', '9px', FLastEdits[0].Text);
  AssertTrue('SF10: in the dark block', FLastEdits[0].Start > Pos('@mode dark', FLastText));
end;

procedure TTbSeedsFrameTests.TestTheWindowCatchesUpFirst;
const
  cNewer = '@mode light { :root { --accent: #444444; } }'#10'@mode dark { :root { --accent: #555555; } }';
begin
  FFrame.OnSync := @SyncStub;
  FFrame.UpdateFrom(TbMinimalTemplate, '', False);
  FSyncText := cNewer;
  AssertTrue('applied', FFrame.ApplyValue(0, 0, '#ABCDEF'));
  AssertEquals('SF11: synced', 1, FSynced);
  AssertEquals('SF11: worked out on the newer text', cNewer, FLastText);
  AssertEquals('SF11: and landed there', StringReplace(cNewer, '#444444', '#ABCDEF', []), Applied);
end;

initialization
  RegisterTest(TTbSeedEditTests);
  RegisterTest(TTbSeedsFrameTests);
end.
