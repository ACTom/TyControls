unit test.fontcombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, fpcunit, testregistry, tyControls.FontComboBox;
type
  TFontComboBoxTest = class(TTestCase)
  published
    procedure TestSelectedFontRoundTrip;
    procedure TestRefreshDoesNotCrash;
    procedure TestAFormFileDoesNotCarryThisMachinesFonts;
    procedure TestA300FormFileShowsThisMachinesFonts;
    procedure TestAFamilyThisMachineLacksIsNotSwappedForAnother;
    procedure TestNoVerticalAliasIsListed;
    procedure TestEveryFontPickerListsThroughTheOneFilter;
  end;
implementation

procedure TFontComboBoxTest.TestSelectedFontRoundTrip;
var c: TTyFontComboBox;
begin
  c := TTyFontComboBox.Create(nil);
  try
    // Replace the Screen.Fonts population with a deterministic set.
    c.Items.Clear;
    c.Items.Add('Arial');
    c.Items.Add('Courier New');
    c.Items.Add('Times New Roman');
    c.SelectedFont := 'Courier New';
    AssertEquals('selected', 'Courier New', c.SelectedFont);
    AssertEquals('index', 1, c.ItemIndex);
    c.SelectedFont := 'Nonexistent Font';   // not present -> selection unchanged
    AssertEquals('unchanged', 'Courier New', c.SelectedFont);
  finally c.Free; end;
end;

procedure TFontComboBoxTest.TestRefreshDoesNotCrash;
var c: TTyFontComboBox;
begin
  // Construction reads Screen.Fonts; RefreshFonts re-reads. Neither may crash headless.
  c := TTyFontComboBox.Create(nil);
  try
    c.RefreshFonts;
    AssertTrue('items count is sane', c.Items.Count >= 0);
  finally c.Free; end;
end;

{ Form-file plumbing for the tests below: what a form writes, and a form read back from text. }
function FCBFormText(ASrc: TForm): string;
var ms, ts: TMemoryStream; L: TStringList;
begin
  ms := TMemoryStream.Create;
  ts := TMemoryStream.Create;
  L := TStringList.Create;
  try
    ms.WriteComponent(ASrc);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    L.LoadFromStream(ts);
    Result := L.Text;
  finally
    L.Free;
    ts.Free;
    ms.Free;
  end;
end;

function FCBFromText(const AText: string): TForm;
var ts: TStringStream; bs: TMemoryStream;
begin
  Result := TForm.CreateNew(nil);
  ts := TStringStream.Create(AText);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    bs.ReadComponent(Result);
  finally
    bs.Free;
    ts.Free;
  end;
end;

{ A font this machine has, late in its list, whose name a form file can carry as a plain quoted
  string -- so the row it sits at here is not the row a stale index points at. }
function FCBLateFont: string;
var i: Integer; nm: string; ok: Boolean; ch: Char; fams: TStringList;
begin
  Result := '';
  fams := TStringList.Create;
  try
  TyFontPickerFamilies(fams);
  for i := fams.Count - 1 downto 3 do
  begin
    nm := fams[i];
    ok := nm <> '';
    for ch in nm do
      if (ch < ' ') or (ch > '~') or (ch = '''') then ok := False;
    if ok then Exit(nm);
  end;
  finally
    fams.Free;
  end;
end;

{ What a font picker lists on this machine, and how many '@' names Screen.Fonts has. }
function FCBPickerCount(out AAliases: Integer): Integer;
var i: Integer;
begin
  AAliases := 0;
  for i := 0 to Screen.Fonts.Count - 1 do
    if Copy(Screen.Fonts[i], 1, 1) = '@' then Inc(AAliases);
  Result := Screen.Fonts.Count - AAliases;
end;

{ What 3.0.0 wrote: another machine's list, with ItemIndex at row 2 (AChosen) or row 1 (a family
  this machine does not have). }
function FCBOldForm(const AChosen: string; AIndex: Integer): string;
var t: string;
begin
  if AIndex = 2 then t := AChosen else t := 'NoSuchFontB';
  Result :=
    'object Form1: TForm' + LineEnding +
    '  object F: TTyFontComboBox' + LineEnding +
    '    Items.Strings = (' + LineEnding +
    '      ''NoSuchFontA''' + LineEnding +
    '      ''NoSuchFontB''' + LineEnding +
    '      ''' + AChosen + '''' + LineEnding +
    '    )' + LineEnding +
    '    ItemIndex = ' + IntToStr(AIndex) + LineEnding +
    '    Text = ''' + t + '''' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
end;

procedure TFontComboBoxTest.TestAFormFileDoesNotCarryThisMachinesFonts;
var src: TForm; c: TTyFontComboBox; t: string;
begin
  src := TForm.CreateNew(nil);
  try
    c := TTyFontComboBox.Create(src);
    c.Name := 'F';
    c.Parent := src;
    AssertTrue('setup: this machine has fonts', c.Items.Count > 0);
    t := FCBFormText(src);
    AssertTrue('the installed fonts are not written into the form' + LineEnding + t,
      Pos('Items.Strings', t) = 0);
  finally
    src.Free;
  end;
end;

procedure TFontComboBoxTest.TestA300FormFileShowsThisMachinesFonts;
var dst: TForm; c: TTyFontComboBox; f: string; n: Integer;
begin
  f := FCBLateFont;
  AssertTrue('setup: a font past row 2 with a plain name', f <> '');
  dst := FCBFromText(FCBOldForm(f, 2));
  try
    c := dst.FindComponent('F') as TTyFontComboBox;
    AssertEquals('the list is this machine''s fonts, not the saved one',
      FCBPickerCount(n), c.Items.Count);
    AssertEquals('none of the saving machine''s missing fonts is listed', -1,
      c.Items.IndexOf('NoSuchFontA'));
    AssertEquals('the chosen family is still chosen, at the row it has here', f, c.SelectedFont);
    AssertEquals('and that row is its row on this machine', c.Items.IndexOf(f), c.ItemIndex);
    AssertTrue('which is a real row', c.ItemIndex >= 0);
  finally
    dst.Free;
  end;
end;

procedure TFontComboBoxTest.TestAFamilyThisMachineLacksIsNotSwappedForAnother;
var dst: TForm; c: TTyFontComboBox; n: Integer;
begin
  dst := FCBFromText(FCBOldForm('NoSuchFontC', 1));
  try
    c := dst.FindComponent('F') as TTyFontComboBox;
    AssertEquals('the list is this machine''s fonts', FCBPickerCount(n), c.Items.Count);
    AssertEquals('a family this machine lacks leaves nothing selected', -1, c.ItemIndex);
  finally
    dst.Free;
  end;
end;

{ Windows lists every CJK font twice: as itself and as an '@' alias that draws each glyph turned
  on its side. A picker that offers the alias hands the program a font no text should be set in. }
procedure TFontComboBoxTest.TestNoVerticalAliasIsListed;
var c: TTyFontComboBox; i, n, shown: Integer;
begin
  shown := FCBPickerCount(n);
  if n = 0 then Exit;   // this machine has no '@' fonts: nothing for the filter to leave out
  c := TTyFontComboBox.Create(nil);
  try
    AssertEquals('every installed font but the ' + IntToStr(n) + ' aliases', shown, c.Items.Count);
    for i := 0 to c.Items.Count - 1 do
      AssertFalse('no alias: ' + c.Items[i], Copy(c.Items[i], 1, 1) = '@');
    c.RefreshFonts;
    AssertEquals('and RefreshFonts lists the same', shown, c.Items.Count);
  finally c.Free; end;
end;

{ The font dialog builds its list where no test can reach it without putting a window up, so the
  rule is held on the source: no unit reads Screen.Fonts for a list but the filter itself, which
  lives in tyControls.FontComboBox. Comments and string literals are blanked out first, so prose
  about Screen.Fonts does not count. }
procedure TFontComboBoxTest.TestEveryFontPickerListsThroughTheOneFilter;

  function CodeOf(const S: string): string;
  var i, depth: Integer; inStr, inLine, inParen: Boolean;
  begin
    Result := S;
    depth := 0; inStr := False; inLine := False; inParen := False;
    i := 1;
    while i <= Length(Result) do
    begin
      if inLine then
      begin
        if Result[i] in [#10, #13] then inLine := False else Result[i] := ' ';
      end
      else if inParen then
      begin
        if (Result[i] = '*') and (i < Length(Result)) and (Result[i + 1] = ')') then
        begin
          Result[i] := ' '; Result[i + 1] := ' '; Inc(i); inParen := False;
        end
        else if not (Result[i] in [#10, #13]) then Result[i] := ' ';
      end
      else if depth > 0 then
      begin
        if Result[i] = '{' then Inc(depth) else if Result[i] = '}' then Dec(depth);
        if not (Result[i] in [#10, #13]) then Result[i] := ' ';
      end
      else if inStr then
      begin
        if Result[i] = '''' then inStr := False;
        Result[i] := ' ';
      end
      else if Result[i] = '{' then begin depth := 1; Result[i] := ' '; end
      else if (Result[i] = '/') and (i < Length(Result)) and (Result[i + 1] = '/') then
      begin inLine := True; Result[i] := ' '; end
      else if (Result[i] = '(') and (i < Length(Result)) and (Result[i + 1] = '*') then
      begin inParen := True; Result[i] := ' '; end
      else if Result[i] = '''' then begin inStr := True; Result[i] := ' '; end;
      Inc(i);
    end;
  end;

var
  dir, code: string;
  sr: TSearchRec;
  L: TStringList;
  readers: TStringList;
  scanned: Integer;
begin
  dir := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'source' + PathDelim;
  readers := TStringList.Create;
  L := TStringList.Create;
  try
    scanned := 0;
    if FindFirst(dir + '*.pas', faAnyFile, sr) = 0 then
    try
      repeat
        L.LoadFromFile(dir + sr.Name);
        Inc(scanned);
        code := LowerCase(CodeOf(L.Text));
        if Pos('screen.fonts', code) > 0 then readers.Add(sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    AssertTrue('the scan read the source tree (' + IntToStr(scanned) + ' units)', scanned > 100);
    AssertEquals('units that read Screen.Fonts themselves:' + LineEnding + readers.Text,
      'tyControls.FontComboBox.pas', Trim(readers.Text));
  finally
    L.Free;
    readers.Free;
  end;
end;

initialization
  RegisterTest(TFontComboBoxTest);
end.
