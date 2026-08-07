unit test.i18n;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, FileUtil,
  Translations,            // TPOFile, TranslateUnitResourceStrings (LazUtils)
  tyControls.StrConsts,    // the unit that DECLARES the resourcestrings
  tyControls.Calendar;     // TyDateTimeNamesUntranslatedMark (the load sentinel's default)
type
  TI18NTest = class(TTestCase)
  published
    procedure TestZhCNTranslatesAndRestores;
    procedure TestNoCatalogueEntryIsWhollyEmpty;
    procedure TestEveryStrConstsResourcestringIsInThePot;
    procedure TestTheShippedChineseCatalogueReallyGivesTheGridItsTruthyWord;
    procedure TestTheShippedCataloguesCarryTheDateTimeNames;
    procedure TestTheExampleCataloguesCarryTheLoadSentinel;
  end;

implementation

const
  ZH_CN_PO =
    'msgid ""'                                          + LineEnding +
    'msgstr ""'                                         + LineEnding +
    '"Content-Type: text/plain; charset=UTF-8\n"'       + LineEnding +
    '"Language: zh_CN\n"'                               + LineEnding +
    ''                                                  + LineEnding +
    '#: tycontrols.strconsts.rslintemptyimportpath'     + LineEnding +
    'msgid "empty @import path"'                        + LineEnding +
    'msgstr "@import 路径为空"'                          + LineEnding;

  EN_PO =                       // identity catalog to restore English (no untranslate API)
    'msgid ""'                                          + LineEnding +
    'msgstr ""'                                         + LineEnding +
    '"Content-Type: text/plain; charset=UTF-8\n"'       + LineEnding +
    '"Language: en\n"'                               + LineEnding +
    ''                                                  + LineEnding +
    '#: tycontrols.strconsts.rslintemptyimportpath'     + LineEnding +
    'msgid "empty @import path"'                        + LineEnding +
    'msgstr "empty @import path"'                       + LineEnding;

procedure TI18NTest.TestZhCNTranslatesAndRestores;
var
  po: TPOFile;
begin
  AssertEquals('precondition: English default', 'empty @import path', rsLintEmptyImportPath);
  po := TPOFile.Create(True);
  try
    po.ReadPOText(ZH_CN_PO);
    AssertTrue('translate call succeeded',
      TranslateUnitResourceStrings('tyControls.StrConsts', po));
    AssertEquals('translated to zh_CN', '@import 路径为空', rsLintEmptyImportPath);
  finally
    po.Free;
  end;
  po := TPOFile.Create(True);     // restore so later tests see English
  try
    po.ReadPOText(EN_PO);
    TranslateUnitResourceStrings('tyControls.StrConsts', po);
    AssertEquals('restored to English', 'empty @import path', rsLintEmptyImportPath);
  finally
    po.Free;
  end;
end;

{ A .po entry that is empty on BOTH sides is a landmine, not a no-op. LazUtils'
  TPOFile.Translate looks an item up by identifier, takes Item.Translation or falls back
  to Item.Original, and then:

      if Result='' then Raise Exception.Create('TPOFile.Translate Inconsistency');

  So a wholly empty entry does not translate to nothing -- it RAISES, during form
  streaming, before OnCreate runs. The LCL answers with a modal error box, which blocks
  Application.CreateForm forever: the program never opens its window and never exits. That
  is how ad81fa4 (retyping the text properties as TCaption, which made Lazarus emit
  catalogue entries for captions whose value is the empty string) left the groupbox,
  radiobutton and toggleswitch examples unable to start at all.

  An empty msgid with a REAL msgstr does not raise, and this guard deliberately allows it.
  It is not, however, a shape anything in this repo can USE: rsGridCheckedWord shipped
  empty in English on exactly that theory, and the runtime half worked -- LazUtils keys
  entries by identifier, so a hand-written entry with an empty msgid is found -- but
  Lazarus's extractor skips empty strings, so the entry never reached the .pot and no
  translator ever saw it. See TestEveryStrConstsResourcestringIsInThePot below. Only the
  both-sides-empty shape is forbidden here. }
procedure TI18NTest.TestNoCatalogueEntryIsWhollyEmpty;
var
  files: TStringList;
  lines: TStringList;
  i, j, k: Integer;
  bad, root: string;
  sawHeader: Boolean;
begin
  root := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
  files := FindAllFiles(root, '*.po', True);
  try
    AssertTrue('found catalogues to check', files.Count > 0);
    bad := '';
    for i := 0 to files.Count - 1 do
    begin
      lines := TStringList.Create;
      try
        lines.LoadFromFile(files[i]);
        sawHeader := False;
        for j := 0 to lines.Count - 1 do
        begin
          if Trim(lines[j]) <> 'msgid ""' then Continue;
          { The first such block is the header (msgstr "" followed by continuation
            lines carrying the metadata) -- skip exactly one. }
          if not sawHeader then begin sawHeader := True; Continue; end;
          k := j + 1;
          while (k < lines.Count) and (Trim(lines[k]) = '') do Inc(k);
          if (k < lines.Count) and (Trim(lines[k]) = 'msgstr ""') then
          begin
            { A continuation line right after means the value is non-empty. }
            if (k + 1 >= lines.Count) or (Copy(Trim(lines[k + 1]), 1, 1) <> '"') then
              bad := bad + LineEnding + '  ' + ExtractFileName(files[i]) + ':' + IntToStr(j + 1);
          end;
        end;
      finally
        lines.Free;
      end;
    end;
    AssertEquals('catalogue entries empty on BOTH sides (these raise at form-load time):'
      + bad, '', bad);
  finally
    files.Free;
  end;
end;

{ A resourcestring that never reaches the .pot cannot be translated by anyone, however
  carefully its comment describes the translation.

  Lazarus's extractor writes the .pot from the compiler's .rsj, and it SKIPS a string whose
  value is empty -- so exactly the strings that were designed to be filled in by a catalogue
  are the ones that silently never get an entry. Comparing the declarations against the
  catalogue is the only way to see it; the code compiles, the .po loads, and the feature
  just is not there.

  Failing entries are reported by name so the fix is either "add it to the .pot" or "give it
  a non-empty English baseline", decided per string. }
procedure TI18NTest.TestEveryStrConstsResourcestringIsInThePot;
var
  src, pot: TStringList;
  i, k, eq, depth: Integer;
  root, line, id, missing: string;
  inBlock: Boolean;
  potText: string;

  { A valid Pascal identifier and nothing else -- the guard that keeps prose out. }
  function IsIdent(const S: string): Boolean;
  var
    j: Integer;
  begin
    Result := (S <> '') and (S[1] in ['A'..'Z', 'a'..'z', '_']);
    if not Result then Exit;
    for j := 2 to Length(S) do
      if not (S[j] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit(False);
  end;

begin
  root := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
  AssertTrue('found the .pot', FileExists(root + 'languages' + PathDelim + 'tyControls.StrConsts.pot'));

  pot := TStringList.Create;
  src := TStringList.Create;
  try
    pot.LoadFromFile(root + 'languages' + PathDelim + 'tyControls.StrConsts.pot');
    potText := LowerCase(pot.Text);
    src.LoadFromFile(root + 'source' + PathDelim + 'tyControls.StrConsts.pas');

    inBlock := False;
    depth   := 0;
    missing := '';
    for i := 0 to src.Count - 1 do
    begin
      line := src[i];
      (* Brace depth FIRST, and it is what makes this readable at all: this unit documents
         nearly every string in a multi-line brace comment, and a comment's CONTINUATION
         lines do not start with an opening brace. Skipping only lines that BEGIN with one
         let the tail of a comment through as if it were code -- the first run of this test
         reported "LCL refuses it (customupdown.inc:380-389). %s" as an untranslated
         resourcestring. *)
      if depth > 0 then
      begin
        for k := 1 to Length(line) do
          if line[k] = '}' then Dec(depth) else if line[k] = '{' then Inc(depth);
        Continue;
      end;
      for k := 1 to Length(line) do
        if line[k] = '{' then Inc(depth) else if line[k] = '}' then Dec(depth);
      if depth > 0 then Continue;      { a comment opened on this line and did not close }

      line := Trim(line);
      if LowerCase(line) = 'resourcestring' then begin inBlock := True; Continue; end;
      if not inBlock then Continue;
      if (LowerCase(line) = 'implementation') or (LowerCase(line) = 'type')
         or (LowerCase(line) = 'var') or (LowerCase(line) = 'const') then
      begin
        inBlock := False;
        Continue;
      end;
      if (line = '') or (Copy(line, 1, 2) = '//') then Continue;
      eq := Pos('=', line);
      if eq < 2 then Continue;
      id := Trim(Copy(line, 1, eq - 1));
      if not IsIdent(id) then Continue;
      if Pos('#: tycontrols.strconsts.' + LowerCase(id) + LineEnding, potText) = 0 then
        missing := missing + LineEnding + '  ' + id;
    end;

    AssertEquals('resourcestrings declared in StrConsts.pas with no .pot entry -- nobody '
      + 'can translate these:' + missing, '', missing);
  finally
    src.Free;
    pot.Free;
  end;
end;

{ End to end, against the catalogue that actually ships.

  The test above proves the identifier reaches the .pot. This proves the rest of the chain:
  that the Chinese catalogue carries a translation for it, and that LazUtils hands that
  translation back when asked with the shipped English value. Both halves have been wrong
  here before -- the entry existed in the .po for a long while with an EMPTY msgid, which
  the runtime tolerated and every piece of .po tooling would have discarded on the next
  merge with the .pot, silently taking the feature with it.

  Read through TPOFile rather than TranslateUnitResourceStrings so the process-wide
  resourcestring is left alone; a translated one stays translated for every test that runs
  after it. }
procedure TI18NTest.TestTheShippedChineseCatalogueReallyGivesTheGridItsTruthyWord;
var
  po: TPOFile;
  root: string;
begin
  root := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
  po := TPOFile.Create(root + 'languages' + PathDelim + 'tycontrols.strconsts.zh_CN.po');
  try
    AssertEquals('the shipped zh_CN catalogue gives the grid its localised truthy word',
      '是', po.Translate('tycontrols.strconsts.rsgridcheckedword', rsGridCheckedWord));
  finally
    po.Free;
  end;
  AssertEquals('and reading the catalogue did not translate the running process',
    'yes', rsGridCheckedWord);
end;

{ The month/weekday-name chain, end to end against the catalogues that ship.
  TTyCalendar and TTyDateTimePicker take their names from the resourcestrings
  whenever a catalogue is loaded (tyControls.Calendar.TyDateTimeNames), and "a
  catalogue is loaded" is the rsTyDateTimeNamesLang sentinel differing from its
  compile-time marker. Two things must therefore be true of the SHIPPED files,
  or the feature dies with all tests green:

  * zh_CN must translate the sentinel AND the names -- or a Chinese app quietly
    falls back to OS-locale names and nobody notices on a Chinese machine.
  * the en catalogue must exist and translate the sentinel -- it is otherwise
    empty (English is the msgid baseline), and deleting it as "useless" is
    exactly the mistake this guard exists to catch: without it --lang=en keeps
    showing the OS locale's month names.

  Read through TPOFile so the running process's resourcestrings are untouched. }
procedure TI18NTest.TestTheShippedCataloguesCarryTheDateTimeNames;
var
  po: TPOFile;
  root: string;
begin
  root := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'languages' + PathDelim;

  po := TPOFile.Create(root + 'tycontrols.strconsts.zh_CN.po');
  try
    AssertEquals('zh_CN translates the load sentinel to its language code',
      'zh_CN', po.Translate('tycontrols.strconsts.rstydatetimenameslang',
                            TyDateTimeNamesUntranslatedMark));
    AssertEquals('zh_CN August', '八月',
      po.Translate('tycontrols.strconsts.rstylongmonth8', rsTyLongMonth8));
    AssertEquals('zh_CN short Sunday', '周日',
      po.Translate('tycontrols.strconsts.rstyshortday1', rsTyShortDay1));
  finally
    po.Free;
  end;

  AssertTrue('the English catalogue ships (its one job is the sentinel)',
    FileExists(root + 'tycontrols.strconsts.en.po'));
  po := TPOFile.Create(root + 'tycontrols.strconsts.en.po');
  try
    AssertEquals('en translates the load sentinel -- the entry that makes '
      + '--lang=en mean English month names',
      'en', po.Translate('tycontrols.strconsts.rstydatetimenameslang',
                         TyDateTimeNamesUntranslatedMark));
  finally
    po.Free;
  end;

  AssertEquals('and reading the catalogues did not translate the running process',
    TyDateTimeNamesUntranslatedMark, rsTyDateTimeNamesLang);
end;

{ The per-example copies are what the example EXES actually load (their .lpr
  points TranslateUnitResourceStringsEx at their own languages/ dir). A library
  catalogue updated without the copies leaves the two date demos -- the ones this
  feature was built for -- still showing the OS locale's names. }
procedure TI18NTest.TestTheExampleCataloguesCarryTheLoadSentinel;
const
  EXAMPLES: array[0..1] of string = ('calendar', 'datetimepicker');
  LANGS:    array[0..1] of string = ('zh_CN', 'en');
var
  po: TPOFile;
  root, f: string;
  e, l: Integer;
begin
  root := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples' + PathDelim;
  for e := 0 to High(EXAMPLES) do
    for l := 0 to High(LANGS) do
    begin
      f := root + EXAMPLES[e] + PathDelim + 'languages' + PathDelim
         + 'tycontrols.' + LANGS[l] + '.po';
      AssertTrue('catalogue exists: ' + f, FileExists(f));
      po := TPOFile.Create(f);
      try
        AssertEquals('sentinel translated in ' + EXAMPLES[e] + '/' + LANGS[l],
          LANGS[l], po.Translate('tycontrols.strconsts.rstydatetimenameslang',
                                 TyDateTimeNamesUntranslatedMark));
      finally
        po.Free;
      end;
    end;
end;

initialization
  RegisterTest(TI18NTest);
end.
