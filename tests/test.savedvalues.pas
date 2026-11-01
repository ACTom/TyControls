unit test.savedvalues;

{$mode objfpc}{$H+}

{ #152: what a form file saves comes back as it was. Each case writes a form and reads it into
  another (or reads the text an older version wrote): a list box's selection under MultiSelect,
  column orders and widths, a shell tree's Directory, a title bar's ButtonWidth, a font list's
  chosen family, a column's gekText and a header's Height of 22. }

interface

uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Columns, tyControls.ListBox, tyControls.ListView, tyControls.ShellTreeView,
  tyControls.Form, tyControls.FontComboBox, tyControls.FontListBox, tyControls.Grid,
  tyControls.Controller, tyControls.BuiltinThemes, tyControls.ThemeRegistry,
  tyControls.FontFamilies;

type
  TSavedValuesTest = class(TTestCase)
  protected
    procedure SetUp; override;
  published
    procedure TestAListBoxKeepsItsSelectionUnderMultiSelect;
    procedure TestColumnOrdersComeBackAsSaved;
    procedure TestColumnWidthsOutsideTheUsualRangeComeBack;
    procedure TestAShellTreeKeepsItsDirectoryUnderARoot;
    procedure TestAnOldFormsButtonWidthIsNotAPin;
    procedure TestAButtonWidthPinnedAt46StaysPinned;
    procedure TestAFontListBoxSavesTheFamilyByName;
    procedure TestAColumnSetToTextStaysText;
    procedure TestAHeaderHeightOf22IsSaved;
  end;

implementation

type
  TGridCrack = class(TTyStringGrid);   // EditorKindFor is protected

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

function FormText(ASrc: TComponent): string;
var
  ms: TMemoryStream;
  ts: TStringStream;
begin
  ms := TMemoryStream.Create;
  ts := TStringStream.Create('');
  try
    ms.WriteComponent(ASrc);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    Result := ts.DataString;
  finally
    ts.Free;
    ms.Free;
  end;
end;

function FormFromText(const AText: string): TForm;
var
  ts: TStringStream;
  bs: TMemoryStream;
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

function NewForm: TForm;
begin
  Result := TForm.CreateNew(nil);
  Result.Name := 'Form1';
  Result.SetBounds(0, 0, 400, 300);
end;

procedure TSavedValuesTest.SetUp;
begin
  NeedWidgetSet;
  if GetClass('TTyListBox') = nil then RegisterClass(TTyListBox);
  if GetClass('TTyFontListBox') = nil then RegisterClass(TTyFontListBox);
end;

procedure TSavedValuesTest.TestAListBoxKeepsItsSelectionUnderMultiSelect;
var
  src, dst: TForm;
  l: TTyListBox;
begin
  src := NewForm;
  dst := nil;
  try
    l := TTyListBox.Create(src);
    l.Name := 'L';
    l.Parent := src;
    l.Items.Add('a');
    l.Items.Add('b');
    l.Items.Add('c');
    l.ItemIndex := 2;
    l.MultiSelect := True;
    AssertTrue('the single selection carries over', l.Selected[2]);
    AssertFalse('and no other row comes with it', l.Selected[0]);
    dst := FormFromText(FormText(src));
    l := dst.FindComponent('L') as TTyListBox;
    AssertTrue('read: MultiSelect', l.MultiSelect);
    AssertTrue('read: the saved row is selected', l.Selected[2]);
    AssertFalse('and only that row', l.Selected[0] or l.Selected[1]);
  finally
    dst.Free;
    src.Free;
  end;
end;

{ Positions per column index, written and read back. }
procedure CheckOrder(const APositions: array of Integer);
var
  src, dst: TForm;
  v: TTyListView;
  i: Integer;
  order: string;
begin
  order := '';
  for i := 0 to High(APositions) do order := order + IntToStr(APositions[i]) + ' ';
  src := NewForm;
  dst := nil;
  try
    v := TTyListView.Create(src);
    v.Name := 'V';
    v.Parent := src;
    for i := 0 to High(APositions) do
      (v.Header.Columns.Add as TTyColumn).Text := 'c' + IntToStr(i);
    { place them from the left, so each one lands where it is asked }
    for i := 0 to High(APositions) do
      (v.Header.Columns.Items[APositions[i]] as TTyColumn).Position := i;
    for i := 0 to High(APositions) do
      TTestCase.AssertEquals('setup ' + order + 'column ' + IntToStr(APositions[i]), i,
        Integer((v.Header.Columns.Items[APositions[i]] as TTyColumn).Position));
    dst := FormFromText(FormText(src));
    v := dst.FindComponent('V') as TTyListView;
    for i := 0 to High(APositions) do
      TTestCase.AssertEquals('read ' + order + 'column ' + IntToStr(APositions[i]), i,
        Integer((v.Header.Columns.Items[APositions[i]] as TTyColumn).Position));
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TSavedValuesTest.TestColumnOrdersComeBackAsSaved;
begin
  { APositions[i] is the column shown i-th }
  CheckOrder([2, 1, 0]);
  CheckOrder([3, 2, 1, 0]);
  CheckOrder([2, 0, 3, 1]);
  CheckOrder([1, 3, 0, 2]);
  { placed by column index rather than by where they go, this one lands 1, 3, 0, 2 }
  CheckOrder([3, 2, 0, 1]);
end;

procedure TSavedValuesTest.TestColumnWidthsOutsideTheUsualRangeComeBack;
var
  src, dst: TForm;
  v: TTyListView;
  c: TTyColumn;
begin
  src := NewForm;
  dst := nil;
  try
    v := TTyListView.Create(src);
    v.Name := 'V';
    v.Parent := src;
    c := v.Header.Columns.Add as TTyColumn;
    c.MinWidth := 2;
    c.Width := 5;
    c := v.Header.Columns.Add as TTyColumn;
    c.MaxWidth := 20000;
    c.Width := 15000;
    { a MinWidth past 10000, and a MaxWidth under 10: each re-clamps the width read before it }
    c := v.Header.Columns.Add as TTyColumn;
    c.MaxWidth := 20000;
    c.MinWidth := 12000;
    c.Width := 15000;
    c := v.Header.Columns.Add as TTyColumn;
    c.MinWidth := 2;
    c.MaxWidth := 5;
    c.Width := 3;
    AssertEquals('setup: narrow', 5, (v.Header.Columns.Items[0] as TTyColumn).Width);
    AssertEquals('setup: wide', 15000, (v.Header.Columns.Items[1] as TTyColumn).Width);
    AssertEquals('setup: wide, with a MinWidth past 10000', 15000,
      (v.Header.Columns.Items[2] as TTyColumn).Width);
    AssertEquals('setup: narrow, with a MaxWidth under 10', 3,
      (v.Header.Columns.Items[3] as TTyColumn).Width);
    dst := FormFromText(FormText(src));
    v := dst.FindComponent('V') as TTyListView;
    AssertEquals('read: narrow', 5, (v.Header.Columns.Items[0] as TTyColumn).Width);
    AssertEquals('read: wide', 15000, (v.Header.Columns.Items[1] as TTyColumn).Width);
    AssertEquals('read: MinWidth', 2, (v.Header.Columns.Items[0] as TTyColumn).MinWidth);
    AssertEquals('read: MaxWidth', 20000, (v.Header.Columns.Items[1] as TTyColumn).MaxWidth);
    AssertEquals('read: wide, with a MinWidth past 10000', 15000,
      (v.Header.Columns.Items[2] as TTyColumn).Width);
    AssertEquals('read: narrow, with a MaxWidth under 10', 3,
      (v.Header.Columns.Items[3] as TTyColumn).Width);
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TSavedValuesTest.TestAShellTreeKeepsItsDirectoryUnderARoot;
var
  src, dst: TForm;
  t: TTyShellTreeView;
  base, sub: string;
begin
  base := IncludeTrailingPathDelimiter(GetTempDir) + 'ty152_' + IntToStr(GetProcessID);
  sub := base + PathDelim + 'inner';
  AssertTrue('setup: folders', ForceDirectories(sub));
  src := NewForm;
  dst := nil;
  try
    t := TTyShellTreeView.Create(src);
    t.Name := 'T';
    t.Parent := src;
    t.Root := base;
    t.Directory := sub;
    AssertEquals('setup: selected', ExcludeTrailingPathDelimiter(sub),
      ExcludeTrailingPathDelimiter(t.Directory));
    dst := FormFromText(FormText(src));
    t := dst.FindComponent('T') as TTyShellTreeView;
    AssertEquals('read: the root', ExcludeTrailingPathDelimiter(base),
      ExcludeTrailingPathDelimiter(t.Root));
    AssertEquals('read: the directory under it', ExcludeTrailingPathDelimiter(sub),
      ExcludeTrailingPathDelimiter(t.Directory));
  finally
    dst.Free;
    src.Free;
    RemoveDir(sub);
    RemoveDir(base);
  end;
end;

{ The bar named B in a form read from AText, under the classic skin (narrower buttons). }
function BarUnderClassic(const AText: string; out AForm: TForm;
  AController: TTyStyleController): TTyTitleBar;
begin
  AForm := FormFromText(AText);
  Result := AForm.FindComponent('B') as TTyTitleBar;
  Result.Controller := AController;
end;

function BarForm(const AWidthLines: string): string;
begin
  Result :=
    'object Form1: TForm' + LineEnding +
    '  object B: TTyTitleBar' + LineEnding +
    '    Left = 0' + LineEnding +
    '    Top = 0' + LineEnding +
    '    Width = 300' + LineEnding +
    '    Height = 32' + LineEnding +
    AWidthLines +
    '  end' + LineEnding +
    'end' + LineEnding;
end;

procedure TSavedValuesTest.TestAnOldFormsButtonWidthIsNotAPin;
var
  src, old: TForm;
  b, fresh: TTyTitleBar;
  c: TTyStyleController;
begin
  TyRegisterBuiltinThemes;
  TyRegisterThemeDir(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim);
  c := TTyStyleController.Create(nil);
  src := NewForm;
  old := nil;
  fresh := nil;
  try
    c.ThemeName := 'classic';
    b := TTyTitleBar.Create(src);
    b.Name := 'B';
    b.Parent := src;
    AssertEquals('a bar never set writes no ButtonWidth', 0, Pos('ButtonWidth', FormText(src)));

    fresh := TTyTitleBar.Create(nil);
    fresh.SetBounds(0, 0, 300, 32);
    fresh.Controller := c;
    { what 3.0.0..3.0.3 wrote for every bar }
    b := BarUnderClassic(BarForm('    ButtonWidth = 46' + LineEnding), old, c);
    AssertEquals('read: follows the skin, as a bar never set does', fresh.RightInset, b.RightInset);
    AssertEquals('and saved again, writes none', 0, Pos('ButtonWidth', FormText(old)));
  finally
    fresh.Free;
    old.Free;
    src.Free;
    c.Free;
  end;
end;

procedure TSavedValuesTest.TestAButtonWidthPinnedAt46StaysPinned;
var
  src, dst: TForm;
  b, pinned, fresh: TTyTitleBar;
  c: TTyStyleController;
  t: string;
begin
  TyRegisterBuiltinThemes;
  TyRegisterThemeDir(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim);
  c := TTyStyleController.Create(nil);
  src := NewForm;
  dst := nil;
  pinned := nil;
  fresh := nil;
  try
    c.ThemeName := 'classic';
    fresh := TTyTitleBar.Create(nil);
    fresh.SetBounds(0, 0, 300, 32);
    fresh.Controller := c;
    pinned := TTyTitleBar.Create(nil);
    pinned.SetBounds(0, 0, 300, 32);
    pinned.Controller := c;
    pinned.ButtonWidth := 46;
    AssertTrue('setup: the skin''s buttons are not 46 wide', fresh.RightInset <> pinned.RightInset);

    b := TTyTitleBar.Create(src);
    b.Name := 'B';
    b.Parent := src;
    b.ButtonWidth := 46;
    t := FormText(src);
    AssertTrue('written' + LineEnding + t, Pos('ButtonWidth = 46', t) > 0);
    dst := FormFromText(t);
    b := dst.FindComponent('B') as TTyTitleBar;
    b.Controller := c;
    AssertEquals('read: still pinned at 46', pinned.RightInset, b.RightInset);

    FreeAndNil(dst);
    b := TTyTitleBar(src.FindComponent('B'));
    b.ButtonWidth := 40;
    dst := FormFromText(FormText(src));
    b := dst.FindComponent('B') as TTyTitleBar;
    b.Controller := c;
    pinned.ButtonWidth := 40;
    AssertEquals('another width: pinned too', pinned.RightInset, b.RightInset);
  finally
    fresh.Free;
    pinned.Free;
    dst.Free;
    src.Free;
    c.Free;
  end;
end;

{ A font past row 2 whose name a form file carries as a plain quoted string. }
function LateFont: string;
var
  fams: TStringList;
  i: Integer;
  ch: Char;
  ok: Boolean;
begin
  Result := '';
  fams := TStringList.Create;
  try
    TyGetFontFamilies(fams, False);
    for i := fams.Count - 1 downto 3 do
    begin
      ok := fams[i] <> '';
      for ch in fams[i] do
        if (ch < ' ') or (ch > '~') or (ch = '''') then ok := False;
      if ok then Exit(fams[i]);
    end;
  finally
    fams.Free;
  end;
end;

procedure TSavedValuesTest.TestAFontListBoxSavesTheFamilyByName;
var
  src, dst: TForm;
  f: TTyFontListBox;
  fam, t: string;
  p, q: Integer;
begin
  fam := LateFont;
  AssertTrue('setup: a font past row 2 with a plain name', fam <> '');
  src := NewForm;
  dst := nil;
  try
    f := TTyFontListBox.Create(src);
    f.Name := 'F';
    f.Parent := src;
    f.SelectedFont := fam;
    t := FormText(src);
    AssertTrue('the family is written by name' + LineEnding + t,
      Pos('SelectedFont = ''' + fam + '''', t) > 0);
    { another machine: the row it was at holds another font }
    p := Pos('ItemIndex = ', t);
    AssertTrue('setup: the row is written too', p > 0);
    q := p + Length('ItemIndex = ');
    while (q <= Length(t)) and (t[q] in ['0'..'9']) do Inc(q);
    t := Copy(t, 1, p - 1) + 'ItemIndex = 0' + Copy(t, q, MaxInt);
    dst := FormFromText(t);
    f := dst.FindComponent('F') as TTyFontListBox;
    AssertEquals('read: the family, not the row', fam, f.SelectedFont);
    AssertEquals('at its row here', f.Items.IndexOf(fam), f.ItemIndex);

    FreeAndNil(dst);
    f := TTyFontListBox(src.FindComponent('F'));
    f.ItemIndex := -1;
    AssertEquals('nothing chosen: nothing written', 0, Pos('SelectedFont', FormText(src)));
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TSavedValuesTest.TestAColumnSetToTextStaysText;
var
  src, dst: TForm;
  g: TTyStringGrid;
  c: TTyGridColumn;
begin
  src := NewForm;
  dst := nil;
  try
    g := TTyStringGrid.Create(src);
    g.Name := 'G';
    g.Parent := src;
    g.DefaultEditorKind := gekNumeric;
    c := g.Header.Columns.Add as TTyGridColumn;
    c.EditorKind := gekText;
    g.Header.Columns.Add;
    g.RowCount := 3;
    AssertTrue('setup: the column edits text', gekText = TGridCrack(g).EditorKindFor(0, 1));
    AssertTrue('setup: the other follows the grid', gekNumeric = TGridCrack(g).EditorKindFor(1, 1));
    dst := FormFromText(FormText(src));
    g := dst.FindComponent('G') as TTyStringGrid;
    AssertTrue('read: the column still edits text', gekText = TGridCrack(g).EditorKindFor(0, 1));
    AssertTrue('read: the other still follows the grid',
      gekNumeric = TGridCrack(g).EditorKindFor(1, 1));
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TSavedValuesTest.TestAHeaderHeightOf22IsSaved;
var
  src, dst: TForm;
  v: TTyListView;
begin
  src := NewForm;
  dst := nil;
  try
    v := TTyListView.Create(src);
    v.Name := 'V';
    v.Parent := src;
    v.Header.Columns.Add;
    AssertFalse('setup: a header never set follows the theme', v.Header.HeightIsExplicit);
    AssertEquals('and is not written', 0, Pos('Header.Height', FormText(src)));
    v.Header.Height := 22;
    dst := FormFromText(FormText(src));
    v := dst.FindComponent('V') as TTyListView;
    AssertTrue('read: a Height of 22 set is still set', v.Header.HeightIsExplicit);
    AssertEquals('read: 22', 22, v.Header.Height);
  finally
    dst.Free;
    src.Free;
  end;
end;

initialization
  RegisterTest(TSavedValuesTest);
end.
