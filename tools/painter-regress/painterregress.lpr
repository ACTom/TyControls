program painterregress;
{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}
{ PAINTER REGRESSION: every text path of the library, drawn off screen and fingerprinted,
  so a change to the shared text renderer (tyControls.Painter, TTyGdiTextRenderer) can be
  held to "not one pixel moved" -- and timed before and after.

  Written for the terminal's phase 5 (Task 8A), when the Windows text renderer was made to
  keep one GDI bitmap; kept so that anyone who changes Painter.pas again can rerun it.
  Builds from source/ (and tests/test.dpi.support for the off-screen painting) without
  the package; no window is shown -- forms are painted into bitmaps the way
  tests/test.dpi.snapshot paints them (TyTestPaintTree).

    painterregress --hashes <file>        render every scene, write "name w h hash" lines
    painterregress --check <file>         render every scene, compare with the file
    painterregress --dump <dir>           also write every scene as a PNG into <dir>
    painterregress --diff <dir1> <dir2>   count the differing pixels of same-named PNGs
    painterregress --perf [--perf-out <file>] [--perf-base <file>]
                                          time the heavy scenes cold and warm; with a base
                                          file, print the ratio and flag > 10 % slower
    --only <text>                         only the scenes whose name contains <text>

  THE SCENES (all at 96 / 120 / 144 / 192 PPI unless said):
    ex-*      every example form file under examples/ (read through a real TReader, as
              test.dpi.snapshot does; the classes are registered by pr_classes.pas, made
              by gen-classes.py)
    dlg-*     the built dialogs: message, input, text, select value, colour, font, find,
              replace, progress, about, select path, open (a folder of this tool's own
              files with fixed dates), icon browser -- 96 and 144
    memo-*    TTyMemo: mixed Chinese and English, CJK, emoji, tabs, a long line scrolled
              sideways, a selection, read-only, disabled, 8 / 12 / 16 pt, bold, italic
    grid-*    TTyStringGrid: header and fixed column, multi-line cells, CJK and emoji
              cells, a selected row, a sorted column's arrow, the in-place editor open
    ctl-*     Edit, ComboBox, ListBox, TreeView, ListView, Label (wrapped), Button,
              TabSet, StatusBar, Breadcrumb, the hint window, TTyTerminalView
    text-*    TTyPainter directly: DrawText (one line, ellipsis, mnemonic, several lines),
              DrawTextRotated, DrawTextLineBidi (Arabic with Latin); DrawTextSupersampled
              exists only on Linux and macOS and is not drawn here

  LIMITS. ClearType on or off is the machine's own setting (changing it would change the
  system for everyone); the check must run on the machine and setting the hashes came
  from. Scenes that show today's date (the calendar and date examples) or the library
  version (about) change with them: take the hashes and check on the same day and
  commit, or take new hashes from the unchanged commit first. }

uses
  Interfaces, SysUtils, StrUtils, Classes, Math, Types, Forms, Controls, Graphics, LCLType, LCLIntf,
  LResources, FileUtil, Menus, ExtCtrls, StdCtrls, ComCtrls, ActnList, Dialogs,
  BGRABitmap, BGRABitmapTypes,
  test.dpi.support,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Base, tyControls.Form, tyControls.Memo, tyControls.Grid, tyControls.Edit,
  tyControls.ComboBox, tyControls.ListBox, tyControls.TreeView, tyControls.ListView,
  tyControls.Columns, tyControls.TyLabel, tyControls.Button, tyControls.TabSet,
  tyControls.StatusBar, tyControls.Breadcrumb, tyControls.Hint, tyControls.Dialogs,
  tyControls.Dialogs.Color, tyControls.Dialogs.Font, tyControls.Dialogs.Find,
  tyControls.Dialogs.Progress, tyControls.Dialogs.About, tyControls.Dialogs.SelectPath,
  tyControls.Dialogs.FileDialog, tyControls.Dialogs.IconBrowser, tyControls.Terminal,
  tyControls.Terminal.Core, tyControls.AnalogClock, tyControls.DateTimePicker, tyControls.Calendar,
  pr_classes;

type
  TSnapshotStandIn = class(TComponent);
  TDialogAccess = class(TTyDialog);
  { the terminal rasterizes new glyphs under a time budget per frame: a picture wants
    them all, whatever the machine's speed }
  TShotTerminal = class(TTyTerminalView)
  public
    procedure NoBudget;
  end;

  TReaderSink = class
    procedure ReaderError(Reader: TReader; const AMessage: string; var Handled: Boolean);
    procedure ReaderFindMethod(Reader: TReader; const AMethodName: string;
      var Address: CodePointer; var Error: Boolean);
    procedure ReaderFindClass(Reader: TReader; const AClassName: string;
      var ComponentClass: TComponentClass);
    procedure ReaderPropertyNotFound(Reader: TReader; Instance: TPersistent;
      var PropName: string; IsPath: Boolean; var Handled, Skip: Boolean);
  end;

  { scrolls to the caret sideways the way a key press does (protected) }
  TShotMemo = class(TTyMemo)
  public
    procedure ScrollToCaret;
  end;

procedure TShotMemo.ScrollToCaret;
begin
  EnsureCaretXVisible(Font.PixelsPerInch);
end;

procedure TShotTerminal.NoBudget;
begin
  RasterBudgetMs := 0;
end;

const
  { a fixed moment for everything that shows the time (2024-03-15 10:09:30) }
  FrozenNow = 45366.4232638889;

{ what reads the clock is set to FrozenNow, so a scene is the same run after run }
procedure Freeze(ARoot: TComponent);
var
  k: Integer;
  c: TComponent;
begin
  for k := 0 to ARoot.ComponentCount - 1 do
  begin
    c := ARoot.Components[k];
    if c is TTyAnalogClock then
    begin
      TTyAnalogClock(c).Running := False;
      TTyAnalogClock(c).Time := FrozenNow;
    end
    else if c is TTyDateTimePicker then
      TTyDateTimePicker(c).DateTime := FrozenNow
    else if c is TTyCalendar then
      TTyCalendar(c).Date := Trunc(FrozenNow);
    if c.ComponentCount > 0 then
      Freeze(c);
  end;
end;

var
  RepoRoot, OnlyText, DumpDir: string;
  Log: TStringList;
  Sink: TReaderSink;
  Ctl: TTyStyleController;
  Names: TStringList;       { name=w h hash, in render order }

procedure TReaderSink.ReaderError(Reader: TReader; const AMessage: string; var Handled: Boolean);
begin
  Log.Add('reader: ' + AMessage);
  Handled := True;
end;

procedure TReaderSink.ReaderFindMethod(Reader: TReader; const AMethodName: string;
  var Address: CodePointer; var Error: Boolean);
begin
  Address := nil;
  Error := False;
end;

procedure TReaderSink.ReaderFindClass(Reader: TReader; const AClassName: string;
  var ComponentClass: TComponentClass);
var
  cls: TPersistentClass;
begin
  if ComponentClass <> nil then Exit;
  cls := GetClass(AClassName);
  if (cls <> nil) and cls.InheritsFrom(TComponent) then
    ComponentClass := TComponentClass(cls)
  else
  begin
    Log.Add('class not registered, stood in for: ' + AClassName);
    ComponentClass := TSnapshotStandIn;
  end;
end;

procedure TReaderSink.ReaderPropertyNotFound(Reader: TReader; Instance: TPersistent;
  var PropName: string; IsPath: Boolean; var Handled, Skip: Boolean);
begin
  Handled := True;
  Skip := True;
end;

{ ---- fingerprints ---------------------------------------------------------------------- }

function Fnv64(ABmp: TBitmap): QWord;
var
  y, x, n: Integer;
  p: PByte;
begin
  Result := QWord($CBF29CE484222325);
  n := ABmp.Width * 3;
  for y := 0 to ABmp.Height - 1 do
  begin
    p := ABmp.ScanLine[y];
    for x := 0 to n - 1 do
    begin
      Result := (Result xor p^) * QWord($100000001B3);
      Inc(p);
    end;
  end;
end;

procedure Record_(const AName: string; ABmp: TBitmap);
var
  png: TPortableNetworkGraphic;
begin
  Names.Add(Format('%s %d %d %.16x', [AName, ABmp.Width, ABmp.Height, Fnv64(ABmp)]));
  if DumpDir <> '' then
  begin
    png := TPortableNetworkGraphic.Create;
    try
      png.Assign(ABmp);
      png.SaveToFile(IncludeTrailingPathDelimiter(DumpDir) + AName + '.png');
    finally
      png.Free;
    end;
  end;
end;

function Wanted(const AName: string): Boolean;
begin
  Result := (OnlyText = '') or (Pos(OnlyText, AName) > 0);
end;

{ the tree under ARoot into a pf24bit bitmap of its size, sentinel first }
function PaintOf(ARoot: TControl): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(Max(1, ARoot.Width), Max(1, ARoot.Height));
  Result.Canvas.Brush.Color := TColor($00FF00FF);
  Result.Canvas.FillRect(0, 0, Result.Width, Result.Height);
  TyTestPaintTree(ARoot, Result, Log);
end;

procedure Shoot(ARoot: TControl; const AName: string);
var
  bmp: TBitmap;
begin
  bmp := PaintOf(ARoot);
  try
    Record_(AName, bmp);
  finally
    bmp.Free;
  end;
end;

{ ---- example forms (test.dpi.snapshot's LoadExample) ------------------------------------ }

function LoadExample(const ARelativeLfm: string; APPI: Integer): TTyForm;
var
  txt: TFileStream;
  bin: TMemoryStream;
  rd: TReader;
begin
  Application.Scaled := False;
  TyTestSimulateScreen(APPI);
  Result := TTyForm.CreateNew(nil);
  Result.Font.PixelsPerInch := 96;
  Application.Scaled := True;
  txt := TFileStream.Create(RepoRoot + ARelativeLfm, fmOpenRead or fmShareDenyNone);
  bin := TMemoryStream.Create;
  try
    LRSObjectTextToBinary(txt, bin);
    bin.Position := 0;
    rd := TReader.Create(bin, 4096);
    try
      rd.OnError := @Sink.ReaderError;
      rd.OnFindMethod := @Sink.ReaderFindMethod;
      rd.OnFindComponentClass := @Sink.ReaderFindClass;
      rd.OnPropertyNotFound := @Sink.ReaderPropertyNotFound;
      rd.ReadRootComponent(Result);
    finally
      rd.Free;
    end;
  finally
    bin.Free;
    txt.Free;
  end;
  if APPI <> 96 then
    Result.AutoAdjustLayout(lapAutoAdjustForDPI, 96, APPI, Result.Width, MulDiv(Result.Width, APPI, 96));
  Freeze(Result);
  TyTestSettle(Result);
  TyTestSettle(Result);
end;

function ExampleFiles: TStringList;
var
  found: TStringList;
  e: Integer;
  rel: string;
begin
  Result := TStringList.Create;
  found := FindAllFiles(RepoRoot + 'examples', '*.lfm', True);
  try
    found.Sort;
    for e := 0 to found.Count - 1 do
    begin
      rel := StringReplace(ExtractRelativePath(ExpandFileName(RepoRoot), ExpandFileName(found[e])),
        '\', '/', [rfReplaceAll]);
      if Pos('/lib/', rel) > 0 then Continue;
      Result.Add(rel);
    end;
  finally
    found.Free;
  end;
end;

const
  AllPPIs: array[0..3] of Integer = (96, 120, 144, 192);
  TwoPPIs: array[0..1] of Integer = (96, 144);

procedure SceneExamples;
var
  files: TStringList;
  e, p: Integer;
  frm: TTyForm;
  nm: string;
begin
  files := ExampleFiles;
  try
    for e := 0 to files.Count - 1 do
      for p := 0 to High(AllPPIs) do
      begin
        nm := Format('ex-%s-%d', [StringReplace(ChangeFileExt(files[e], ''), '/', '-', [rfReplaceAll]), AllPPIs[p]]);
        if not Wanted(nm) then Continue;
        frm := nil;
        try
          try
            frm := LoadExample(files[e], AllPPIs[p]);
            Shoot(frm, nm);
          except
            on Ex: Exception do Log.Add(Format('%s: %s: %s', [nm, Ex.ClassName, Ex.Message]));
          end;
        finally
          frm.Free;
        end;
      end;
  finally
    files.Free;
  end;
end;

{ ---- dialogs ------------------------------------------------------------------------------ }

function StableDir: string;
const
  Stamp = 45000.5;    { a fixed date (2023-03-15 12:00): the file list shows the dates }
var
  d: string;
  k: Integer;
  sl: TStringList;
begin
  d := RepoRoot + 'tests/fixtures/painter-regress/files';
  ForceDirectories(d);
  for k := 1 to 3 do
    if not FileExists(d + '/' + Format('note-%d.txt', [k])) then
    begin
      sl := TStringList.Create;
      try
        sl.Add(Format('file %d', [k]));
        sl.SaveToFile(d + '/' + Format('note-%d.txt', [k]));
      finally
        sl.Free;
      end;
    end;
  for k := 1 to 3 do
    FileSetDate(d + '/' + Format('note-%d.txt', [k]), DateTimeToFileDate(Stamp + k));
  Result := d;
end;

function BuildDialog(AIndex: Integer; out AName: string): TTyDialog;
var
  e: TTyEdit;
  m: TTyMemo;
  l: TTyListBox;
  items: TStringList;
  fnt: TFont;
begin
  Result := nil;
  AName := '';
  case AIndex of
    0: begin
         AName := 'message';
         Result := TyBuildMessageDialog('The file has been changed on disk. Reload it and lose'
           + ' the changes made here, or keep editing this copy? 文件已在磁盘上修改。', mtConfirmation,
           [mbYes, mbNo, mbCancel]);
       end;
    1: begin
         AName := 'input';
         Result := TyBuildInputDialog('Rename', 'New name 新名称:', 'old.txt', e);
       end;
    2: begin
         AName := 'text';
         Result := TyBuildTextDialog('Notes', 'Anything to add?', 'one' + LineEnding + '两行', m);
       end;
    3: begin
         AName := 'selectvalue';
         items := TStringList.Create;
         try
           items.Add('Alpha');
           items.Add('Beta 贝塔');
           items.Add('Gamma');
           Result := TyBuildSelectValueDialog('Pick one', 'Which?', items, 1, l);
         finally
           items.Free;
         end;
       end;
    4: begin
         AName := 'color';
         Result := TyBuildColorDialog('Select Color', TyRGB(59, 130, 246));
       end;
    5: begin
         AName := 'font';
         items := TStringList.Create;
         fnt := TFont.Create;
         try
           items.Add('Arial');
           items.Add('Courier New');
           items.Add('Tahoma');
           Result := TyBuildFontDialog('Font', fnt, items);
         finally
           fnt.Free;
           items.Free;
         end;
       end;
    6: begin
         AName := 'find';
         Result := TTyFindForm.CreateNew(nil, 0);
         TTyFindForm(Result).Build(False);
       end;
    7: begin
         AName := 'replace';
         Result := TTyFindForm.CreateNew(nil, 0);
         TTyFindForm(Result).Build(True);
       end;
    8: begin
         AName := 'progress';
         Result := TTyProgressForm.CreateNew(nil, 0);
         TTyProgressForm(Result).Build(True);
         TTyProgressForm(Result).UpdateView(40, 0, 100, 'Copying 40 of 100...');
       end;
    9: begin
         AName := 'about';
         Result := TyBuildAboutDialog('About', 'TyControls', '3.0.0', 'Themed controls for'
           + ' Lazarus.' + LineEnding + 'One look on every platform. 每个平台一个样子。', '(c) the authors',
           'MIT', 'https://example.invalid');
       end;
    10: begin
          AName := 'selectpath';
          Result := TyBuildSelectPathDialog('Select a folder', StableDir);
        end;
    11: begin
          AName := 'open';
          Result := TyBuildFileDialog(False, True, 'Open');
          TTyFileDialogForm(Result).InitialDir := StableDir;
        end;
    12: begin
          AName := 'iconbrowser';
          Result := TyBuildIconBrowserDialog('Icons', nil);
        end;
  end;
end;

procedure SceneDialogs;
var
  p, k: Integer;
  d: TTyDialog;
  nm, base: string;
begin
  for k := 0 to 12 do
    for p := 0 to High(TwoPPIs) do
    begin
      Application.Scaled := False;
      TyTestSimulateScreen(TwoPPIs[p]);
      d := nil;
      try
        try
          d := BuildDialog(k, base);
          nm := Format('dlg-%s-%d', [base, TwoPPIs[p]]);
          if (d = nil) or not Wanted(nm) then Continue;
          TyTestSettle(d);
          TDialogAccess(d).Resize;
          TyTestSettle(d);
          Shoot(d, nm);
        except
          on Ex: Exception do Log.Add(Format('dialog %d at %d: %s: %s', [k, TwoPPIs[p], Ex.ClassName, Ex.Message]));
        end;
      finally
        d.Free;
      end;
    end;
end;

{ ---- controls built here ------------------------------------------------------------------- }

function NewHost(APPI, AW, AH: Integer): TTyForm;
begin
  Application.Scaled := False;
  TyTestSimulateScreen(APPI);
  Result := TTyForm.CreateNew(nil);
  Result.SetBounds(0, 0, MulDiv(AW, APPI, 96), MulDiv(AH, APPI, 96));
end;

function Mixed: string;
begin
  Result := 'Hello 你好 world 世界 mixed 中英混排 text, 1234.';
end;

procedure MemoScene(const AName: string; APPI, AVariant: Integer);
var
  f: TTyForm;
  m: TTyMemo;
  k: Integer;
  s: string;
begin
  if not Wanted(AName) then Exit;
  f := NewHost(APPI, 360, 200);
  try
    m := TShotMemo.Create(f);
    m.Controller := Ctl;
    m.Parent := f;
    m.SetBounds(0, 0, f.Width, f.Height);
    m.HideSelection := False;           { unfocused, as every picture here: show it }
    case AVariant of
      0: begin
           m.Lines.Add(Mixed);
           m.Lines.Add('第二行：全角标点，以及“引号”。');
           m.Lines.Add('English only, with punctuation: a, b; c.');
         end;
      1: for k := 0 to 8 do
           m.Lines.Add('中文字符测试第' + IntToStr(k) + '行，汉字排版、标点符号。');
      2: begin
           m.Lines.Add('Emoji 😀😃😄 👍🎉 and text');
           m.Lines.Add('🇨🇳 flags 👨‍👩‍👧 family');
         end;
      3: begin
           m.Lines.Add('a'#9'tab'#9'separated'#9'columns');
           m.Lines.Add('longer'#9'x'#9'中文'#9'end');
         end;
      4: begin
           s := '';
           for k := 0 to 30 do s := s + 'word' + IntToStr(k) + ' 中文 ';
           m.Lines.Add(s);
           m.Lines.Add('second line');
           m.CaretPos := Length(UTF8Decode(s)) - 1;
           TShotMemo(m).ScrollToCaret;
         end;
      5: begin
           m.Lines.Add(Mixed);
           m.Lines.Add('selected part 选中的部分 here');
           m.SelStart := 8;
           m.SelLength := 30;
         end;
      6: begin
           m.Lines.Add(Mixed);
           m.ReadOnly := True;
         end;
      7: begin
           m.Lines.Add(Mixed);
           m.Enabled := False;
         end;
      8, 9, 10: begin
           m.Font.Size := 8 + (AVariant - 8) * 4;
           m.Lines.Add(Mixed);
           m.Lines.Add('Size ' + IntToStr(m.Font.Size));
         end;
      11: begin
           m.Font.Style := [fsBold];
           m.Lines.Add(Mixed);
         end;
      12: begin
           m.Font.Style := [fsItalic];
           m.Lines.Add(Mixed);
         end;
    end;
    TyTestSettle(f);
    Shoot(f, AName);
  finally
    f.Free;
  end;
end;

procedure SceneMemos;
const
  V: array[0..12] of string = ('mixed', 'cjk', 'emoji', 'tabs', 'long-scrolled', 'selection', 'readonly',
    'disabled', '8pt', '12pt', '16pt', 'bold', 'italic');
var
  p, k: Integer;
begin
  for p := 0 to High(AllPPIs) do
    for k := 0 to High(V) do
      MemoScene(Format('memo-%s-%d', [V[k], AllPPIs[p]]), AllPPIs[p], k);
end;

procedure GridScene(const AName: string; APPI, AVariant: Integer);
var
  f: TTyForm;
  g: TTyStringGrid;
  r: Integer;
begin
  if not Wanted(AName) then Exit;
  f := NewHost(APPI, 420, 220);
  try
    g := TTyStringGrid.Create(f);
    g.Controller := Ctl;
    g.Parent := f;
    g.SetBounds(0, 0, f.Width, f.Height);
    g.Header.Columns.Add.Text := '#';
    g.Header.Columns.Add.Text := 'Name 名称';
    g.Header.Columns.Add.Text := 'Size';
    g.Header.Columns.Add.Text := 'Note';
    g.Header.Columns.Add.Text := 'Emoji';
    g.RowCount := 8;
    g.FixedRows := 1;
    g.FixedCols := 1;
    for r := 0 to 7 do
    begin
      g.Cells[0, r] := IntToStr(r);
      g.Cells[1, r] := 'item ' + IntToStr(r) + ' 项目';
      g.Cells[2, r] := IntToStr(r * 1024);
      g.Cells[3, r] := '中文说明 ' + IntToStr(r);
      g.Cells[4, r] := '😀 ok';
    end;
    case AVariant of
      1: begin
           g.RowHeights[2] := 48;
           g.Cells[3, 2] := 'first line' + LineEnding + '第二行';
         end;
      2: g.SelectRows(3, 3);
      3: g.SortByColumn(2, sdDescending);
      4: begin
           g.Col := 1;
           g.Row := 2;
           g.EditorMode := True;
         end;
    end;
    TyTestSettle(f);
    Shoot(f, AName);
  finally
    f.Free;
  end;
end;

procedure SceneGrids;
const
  V: array[0..4] of string = ('plain', 'multiline', 'selected-row', 'sorted', 'editor');
var
  p, k: Integer;
begin
  for p := 0 to High(AllPPIs) do
    for k := 0 to High(V) do
      GridScene(Format('grid-%s-%d', [V[k], AllPPIs[p]]), AllPPIs[p], k);
end;

procedure SceneControls;
var
  p, k: Integer;
  f: TTyForm;
  ed: TTyEdit;
  cb: TTyComboBox;
  lb: TTyListBox;
  tv: TTyTreeView;
  lv: TTyListView;
  lab: TTyLabel;
  bt: TTyButton;
  ts: TTyTabSet;
  sb: TTyStatusBar;
  bc: TTyBreadcrumb;
  node: TTyTreeNodeItem;
  it: TTyListItem;
  nm: string;
begin
  for p := 0 to High(AllPPIs) do
  begin
    nm := Format('ctl-panel-%d', [AllPPIs[p]]);
    if not Wanted(nm) then Continue;
    f := NewHost(AllPPIs[p], 520, 460);
    try
      ed := TTyEdit.Create(f);
      ed.Controller := Ctl;
      ed.Parent := f;
      ed.SetBounds(8, 8, MulDiv(240, AllPPIs[p], 96), MulDiv(28, AllPPIs[p], 96));
      ed.Text := 'Edit 编辑框 😀';
      cb := TTyComboBox.Create(f);
      cb.Controller := Ctl;
      cb.Parent := f;
      cb.SetBounds(MulDiv(260, AllPPIs[p], 96), 8, MulDiv(240, AllPPIs[p], 96), MulDiv(28, AllPPIs[p], 96));
      cb.Items.Add('Combo 组合框');
      cb.ItemIndex := 0;
      lb := TTyListBox.Create(f);
      lb.Controller := Ctl;
      lb.Parent := f;
      lb.SetBounds(8, MulDiv(44, AllPPIs[p], 96), MulDiv(160, AllPPIs[p], 96), MulDiv(120, AllPPIs[p], 96));
      for k := 0 to 5 do lb.Items.Add('List 列表 ' + IntToStr(k));
      lb.ItemIndex := 2;
      tv := TTyTreeView.Create(f);
      tv.Controller := Ctl;
      tv.Parent := f;
      tv.SetBounds(MulDiv(176, AllPPIs[p], 96), MulDiv(44, AllPPIs[p], 96), MulDiv(160, AllPPIs[p], 96), MulDiv(120, AllPPIs[p], 96));
      node := tv.Items.Add(nil, 'Root 根');
      tv.Items.AddChild(node, 'Child 子节点');
      tv.Items.AddChild(node, 'Another');
      lv := TTyListView.Create(f);
      lv.Controller := Ctl;
      lv.Parent := f;
      lv.SetBounds(MulDiv(344, AllPPIs[p], 96), MulDiv(44, AllPPIs[p], 96), MulDiv(168, AllPPIs[p], 96), MulDiv(120, AllPPIs[p], 96));
      lv.Columns.Add.Text := 'Name';
      lv.Columns.Add.Text := '大小';
      for k := 0 to 3 do
      begin
        it := lv.Items.Add;
        it.Caption := 'file ' + IntToStr(k) + ' 文件';
        it.SubItems.Add(IntToStr(k * 10) + ' KB');
      end;
      lab := TTyLabel.Create(f);
      lab.Controller := Ctl;
      lab.Parent := f;
      lab.WordWrap := True;
      lab.SetBounds(8, MulDiv(172, AllPPIs[p], 96), MulDiv(240, AllPPIs[p], 96), MulDiv(60, AllPPIs[p], 96));
      lab.Caption := 'A label long enough to wrap onto a second line, 还有中文的自动换行测试。';
      bt := TTyButton.Create(f);
      bt.Controller := Ctl;
      bt.Parent := f;
      bt.SetBounds(MulDiv(260, AllPPIs[p], 96), MulDiv(172, AllPPIs[p], 96), MulDiv(120, AllPPIs[p], 96), MulDiv(30, AllPPIs[p], 96));
      bt.Caption := '&Button 按钮';
      ts := TTyTabSet.Create(f);
      ts.Controller := Ctl;
      ts.Parent := f;
      ts.SetBounds(8, MulDiv(240, AllPPIs[p], 96), MulDiv(500, AllPPIs[p], 96), MulDiv(32, AllPPIs[p], 96));
      ts.Tabs.Add('First 第一');
      ts.Tabs.Add('Second');
      ts.Tabs.Add('第三页');
      bc := TTyBreadcrumb.Create(f);
      bc.Controller := Ctl;
      bc.Parent := f;
      bc.SetBounds(8, MulDiv(280, AllPPIs[p], 96), MulDiv(500, AllPPIs[p], 96), MulDiv(28, AllPPIs[p], 96));
      bc.Items.Add('Home');
      bc.Items.Add('文档');
      bc.Items.Add('Reports 报告');
      sb := TTyStatusBar.Create(f);
      sb.Controller := Ctl;
      sb.Parent := f;
      sb.SetBounds(0, MulDiv(420, AllPPIs[p], 96), f.Width, MulDiv(26, AllPPIs[p], 96));
      sb.Panels.Add.Text := 'Ready 就绪';
      sb.Panels.Add.Text := 'Ln 1, Col 1';
      TyTestSettle(f);
      Shoot(f, nm);
    finally
      f.Free;
    end;
  end;
end;

procedure SceneHint;
var
  p: Integer;
  h: TTyHintWindow;
  r: TRect;
  nm: string;
begin
  for p := 0 to High(TwoPPIs) do
  begin
    nm := Format('ctl-hint-%d', [TwoPPIs[p]]);
    if not Wanted(nm) then Continue;
    Application.Scaled := False;
    TyTestSimulateScreen(TwoPPIs[p]);
    h := TTyHintWindow.Create(nil);
    try
      r := h.CalcHintRect(400, 'A hint with 中文 in it', nil);
      h.SetBounds(0, 0, Max(1, r.Right - r.Left), Max(1, r.Bottom - r.Top));
      h.Caption := 'A hint with 中文 in it';
      Shoot(h, nm);
    finally
      h.Free;
    end;
  end;
end;

procedure SceneTerminal;
var
  p: Integer;
  f: TTyForm;
  t: TShotTerminal;
  sz: TSize;
  nm, s: string;
  k: Integer;
begin
  for p := 0 to High(TwoPPIs) do
  begin
    nm := Format('ctl-terminal-%d', [TwoPPIs[p]]);
    if not Wanted(nm) then Continue;
    f := NewHost(TwoPPIs[p], 600, 300);
    try
      t := TShotTerminal.Create(f);
      t.NoBudget;
      t.Controller := Ctl;
      t.Parent := f;
      sz := t.SizeForGrid(60, 12);
      t.SetBounds(0, 0, sz.cx, sz.cy);
      s := #27'[1mbold'#27'[0m '#27'[3mitalic'#27'[0m '#27'[31mred'#27'[0m 中文 한국어 😀'#13#10;
      for k := 0 to 8 do
        s := s + 'line ' + IntToStr(k) + ' 终端里的中文 ' + #27'[4munderlined'#27'[0m ─┼─ ░▒▓'#13#10;
      t.WriteSync(s + #27'[?25l');
      f.SetBounds(0, 0, sz.cx, sz.cy);
      Shoot(f, nm);
    finally
      f.Free;
    end;
  end;
end;

procedure SceneText;
var
  p, k: Integer;
  bmp: TBitmap;
  P_: TTyPainter;
  w, h: Integer;
  nm: string;
begin
  for p := 0 to High(AllPPIs) do
    for k := 0 to 5 do
    begin
      case k of
        0: nm := 'text-line';
        1: nm := 'text-ellipsis';
        2: nm := 'text-mnemonic';
        3: nm := 'text-multiline';
        4: nm := 'text-rotated';
      else
        nm := 'text-bidi';
      end;
      nm := Format('%s-%d', [nm, AllPPIs[p]]);
      if not Wanted(nm) then Continue;
      w := MulDiv(320, AllPPIs[p], 96);
      h := MulDiv(120, AllPPIs[p], 96);
      bmp := TBitmap.Create;
      P_ := TTyPainter.Create;
      try
        bmp.PixelFormat := pf24bit;
        bmp.SetSize(w, h);
        bmp.Canvas.Brush.Color := clWhite;
        bmp.Canvas.FillRect(0, 0, w, h);
        P_.BeginPaint(bmp.Canvas, Rect(0, 0, w, h), AllPPIs[p]);
        case k of
          0: P_.DrawText(Rect(4, 4, w - 4, h - 4), 'One line 一行文字 😀', 'Segoe UI', 9, 400, TyRGB(20, 20, 20),
               taLeftJustify, tlTop, False);
          1: P_.DrawText(Rect(4, 4, MulDiv(120, AllPPIs[p], 96), h - 4), 'A line far too long to fit, 太长了',
               'Segoe UI', 10, 700, TyRGB(0, 60, 160), taLeftJustify, tlTop, True);
          2: P_.DrawText(Rect(4, 4, w - 4, h - 4), 'Save as...', 'Segoe UI', 9, 400, TyRGB(0, 0, 0),
               taCenter, tlCenter, False, 6);
          3: P_.DrawText(Rect(4, 4, w - 4, h - 4), 'First line' + LineEnding + '第二行' + LineEnding + 'Third',
               'Microsoft YaHei', 9, 400, TyRGB(60, 0, 0), taLeftJustify, tlTop, False, 0, False, True);
          4: begin
               P_.DrawTextRotated('Rotated 旋转', 'Segoe UI', 10, 400, TyRGB(0, 0, 0), w / 2, h / 2, Pi / 6,
                 taCenter, tlCenter);
               P_.DrawTextRotated('Vertical', 'Segoe UI', 9, 400, TyRGB(120, 0, 0), 16, h / 2, Pi / 2,
                 taCenter, tlCenter);
             end;
        else
          P_.DrawText(Rect(4, 4, w - 4, h - 4), 'مرحبا بالعالم Acme 2024', 'Segoe UI', 11, 400, TyRGB(0, 0, 0),
            taLeftJustify, tlTop, False);
        end;
        P_.EndPaint;
        Record_(nm, bmp);
      finally
        P_.Free;
        bmp.Free;
      end;
    end;
end;

procedure RenderAll;
begin
  SceneText;
  SceneMemos;
  SceneGrids;
  SceneControls;
  SceneHint;
  SceneTerminal;
  SceneDialogs;
  SceneExamples;
end;

{ ---- perf -------------------------------------------------------------------------------- }

type
  TPerfRow = record
    Name: string;
    Cold, Warm: Double;
  end;

var
  Perf: array of TPerfRow;

procedure AddPerf(const AName: string; ACold, AWarm: Double);
begin
  SetLength(Perf, Length(Perf) + 1);
  Perf[High(Perf)].Name := AName;
  Perf[High(Perf)].Cold := ACold;
  Perf[High(Perf)].Warm := AWarm;
end;

function QpcMs: Double;
begin
  Result := TyTermDefaultClock;
end;

function MedianOf(var A: array of Double): Double;
var
  i, j: Integer;
  t: Double;
begin
  for i := 1 to High(A) do
  begin
    t := A[i];
    j := i - 1;
    while (j >= 0) and (A[j] > t) do
    begin
      A[j + 1] := A[j];
      Dec(j);
    end;
    A[j + 1] := t;
  end;
  Result := A[Length(A) div 2];
end;

{ AMake builds the tree (cold: text caches dropped first), then its first paint is timed,
  then 15 more (warm), median; five rounds, median of the cold ones }
type
  TMakeProc = function(APPI: Integer): TTyForm;
  TAfterProc = procedure(AForm: TTyForm);

procedure TimeTree(const AName: string; AMake: TMakeProc; AAfter: TAfterProc);
var
  cold: array[0..4] of Double;
  warm: array[0..14] of Double;
  warms: array[0..4] of Double;
  round, k: Integer;
  f: TTyForm;
  bmp: TBitmap;
  t: Double;
begin
  for round := 0 to 4 do
  begin
    TyInvalidateTextMeasureCache;
    f := AMake(96);
    try
      bmp := TBitmap.Create;
      try
        bmp.PixelFormat := pf24bit;
        bmp.SetSize(f.Width, f.Height);
        t := QpcMs;
        TyTestPaintTree(f, bmp, Log);
        cold[round] := QpcMs - t;
        for k := 0 to High(warm) do
        begin
          if Assigned(AAfter) then AAfter(f);
          t := QpcMs;
          TyTestPaintTree(f, bmp, Log);
          warm[k] := QpcMs - t;
        end;
        warms[round] := MedianOf(warm);
      finally
        bmp.Free;
      end;
    finally
      f.Free;
    end;
  end;
  AddPerf(AName, MedianOf(cold), MedianOf(warms));
end;

var
  PageFlip: Integer;

function MakeMemo(APPI: Integer): TTyForm;
var
  m: TTyMemo;
  sl: TStringList;
  k: Integer;
begin
  Result := NewHost(APPI, 800, 600);
  m := TTyMemo.Create(Result);
  m.Name := 'Memo';
  m.Controller := Ctl;
  m.Parent := Result;
  m.SetBounds(0, 0, Result.Width, Result.Height);
  sl := TStringList.Create;
  try
    for k := 0 to 9999 do
      sl.Add(Format('%5d  the quick brown fox 中文混排的一行 %d jumps over', [k, k * 7]));
    m.Lines.Assign(sl);
  finally
    sl.Free;
  end;
  TyTestSettle(Result);
end;

procedure MemoPage(AForm: TTyForm);
var
  m: TTyMemo;
begin
  { a page further down each time: new lines, new glyph runs }
  m := TTyMemo(AForm.FindComponent('Memo'));
  Inc(PageFlip);
  m.CaretPos := (PageFlip * 40 mod 9000) * 50;
end;

function MakeGrid(APPI: Integer): TTyForm;
var
  g: TTyStringGrid;
  c, r: Integer;
begin
  Result := NewHost(APPI, 1000, 700);
  g := TTyStringGrid.Create(Result);
  g.Controller := Ctl;
  g.Parent := Result;
  g.SetBounds(0, 0, Result.Width, Result.Height);
  for c := 0 to 19 do
    g.Header.Columns.Add.Text := 'Col ' + IntToStr(c);
  g.RowCount := 100;
  for r := 0 to 99 do
    for c := 0 to 19 do
      g.Cells[c, r] := Format('%d,%d 数据', [c, r]);
  TyTestSettle(Result);
end;

function MakeTerminal(APPI: Integer): TTyForm;
var
  t: TShotTerminal;
  sz: TSize;
  s: RawByteString;
  k, j: Integer;
begin
  Result := NewHost(APPI, 100, 100);
  t := TShotTerminal.Create(Result);
  t.NoBudget;
  t.Controller := Ctl;
  t.Parent := Result;
  sz := t.SizeForGrid(100, 30);
  t.SetBounds(0, 0, sz.cx, sz.cy);
  Result.SetBounds(0, 0, sz.cx, sz.cy);
  s := '';
  for k := 0 to 29 do
  begin
    for j := 0 to 49 do
      s := s + UTF8Encode(WideChar($4E00 + (k * 50 + j) mod 2000));
    if k < 29 then s := s + #13#10;
  end;
  t.WriteSync(s + #27'[?25l');
end;

procedure PerfExamples;
var
  files: TStringList;
  e: Integer;
  frm: TTyForm;
  bmp: TBitmap;
  t, cold, warm: Double;
begin
  files := ExampleFiles;
  cold := 0;
  warm := 0;
  try
    for e := 0 to files.Count - 1 do
    begin
      TyInvalidateTextMeasureCache;
      frm := nil;
      try
        try
          frm := LoadExample(files[e], 96);
          bmp := TBitmap.Create;
          try
            bmp.PixelFormat := pf24bit;
            bmp.SetSize(frm.Width, frm.Height);
            t := QpcMs;
            TyTestPaintTree(frm, bmp, Log);
            cold := cold + (QpcMs - t);
            t := QpcMs;
            TyTestPaintTree(frm, bmp, Log);
            warm := warm + (QpcMs - t);
          finally
            bmp.Free;
          end;
        except
          on Ex: Exception do Log.Add('perf ' + files[e] + ': ' + Ex.Message);
        end;
      finally
        frm.Free;
      end;
    end;
  finally
    files.Free;
  end;
  AddPerf('example forms (sum of 1 paint each)', cold, warm);
end;

procedure RunPerf(const AOut, ABase: string);
var
  sl, base: TStringList;
  k, j: Integer;
  bc, bw: Double;
  parts: TStringArray;
  worst: Double;
begin
  Perf := nil;
  PageFlip := 0;
  TimeTree('Memo 10k lines, a page (warm = scrolled a page each paint)', @MakeMemo, @MemoPage);
  TimeTree('Grid 100 x 20', @MakeGrid, nil);
  TimeTree('Terminal 100 x 30 CJK', @MakeTerminal, nil);
  { the examples twice: the first pass warms what is not text (theme parsing, icons) }
  PerfExamples;
  Perf := Copy(Perf, 0, Length(Perf) - 1);
  PerfExamples;
  base := TStringList.Create;
  sl := TStringList.Create;
  try
    if ABase <> '' then base.LoadFromFile(ABase);
    WriteLn('| scene | cold ms | warm ms |', IfThen(ABase <> '', ' base cold | base warm | cold ratio | warm ratio |', ''));
    WriteLn('|---|---|---|', IfThen(ABase <> '', '---|---|---|---|', ''));
    worst := 0;
    for k := 0 to High(Perf) do
    begin
      sl.Add(Format('%s'#9'%.3f'#9'%.3f', [Perf[k].Name, Perf[k].Cold, Perf[k].Warm]));
      if ABase <> '' then
      begin
        bc := 0;
        bw := 0;
        for j := 0 to base.Count - 1 do
        begin
          parts := base[j].Split([#9]);
          if (Length(parts) = 3) and (parts[0] = Perf[k].Name) then
          begin
            bc := StrToFloat(parts[1]);
            bw := StrToFloat(parts[2]);
          end;
        end;
        WriteLn(Format('| %s | %.2f | %.2f | %.2f | %.2f | %.3f | %.3f |', [Perf[k].Name, Perf[k].Cold, Perf[k].Warm,
          bc, bw, Perf[k].Cold / Max(bc, 1e-9), Perf[k].Warm / Max(bw, 1e-9)]));
        worst := Max(worst, Max(Perf[k].Cold / Max(bc, 1e-9), Perf[k].Warm / Max(bw, 1e-9)));
      end
      else
        WriteLn(Format('| %s | %.2f | %.2f |', [Perf[k].Name, Perf[k].Cold, Perf[k].Warm]));
    end;
    if ABase <> '' then
      WriteLn(Format('worst ratio %.3f -- %s', [worst, IfThen(worst > 1.10, 'SLOWER THAN 10 %', 'within 10 %')]));
    if AOut <> '' then sl.SaveToFile(AOut);
  finally
    sl.Free;
    base.Free;
  end;
end;

{ ---- diff of two PNG folders --------------------------------------------------------------- }

procedure DiffDirs(const A, B: string);
var
  files: TStringList;
  k, x, y, n, total, differing: Integer;
  pa, pb: TBGRABitmap;
  nm: string;
begin
  files := FindAllFiles(A, '*.png', False);
  total := 0;
  differing := 0;
  try
    files.Sort;
    for k := 0 to files.Count - 1 do
    begin
      nm := ExtractFileName(files[k]);
      if not FileExists(IncludeTrailingPathDelimiter(B) + nm) then
      begin
        WriteLn('missing in ', B, ': ', nm);
        Continue;
      end;
      pa := TBGRABitmap.Create(files[k]);
      pb := TBGRABitmap.Create(IncludeTrailingPathDelimiter(B) + nm);
      try
        Inc(total);
        n := 0;
        if (pa.Width <> pb.Width) or (pa.Height <> pb.Height) then
          n := -1
        else
          for y := 0 to pa.Height - 1 do
            for x := 0 to pa.Width - 1 do
              if pa.GetPixel(x, y) <> pb.GetPixel(x, y) then Inc(n);
        if n <> 0 then
        begin
          Inc(differing);
          WriteLn(Format('%s: %d pixels differ', [nm, n]));
        end;
      finally
        pa.Free;
        pb.Free;
      end;
    end;
    WriteLn(Format('%d pictures, %d differ', [total, differing]));
  finally
    files.Free;
  end;
end;

{ ---- main -------------------------------------------------------------------------------- }

function Arg(const AName: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to ParamCount - 1 do
    if ParamStr(i) = AName then Exit(ParamStr(i + 1));
end;

function Has(const AName: string): Boolean;
var
  i: Integer;
begin
  for i := 1 to ParamCount do
    if ParamStr(i) = AName then Exit(True);
  Result := False;
end;

var
  hashFile, checkFile: string;
  want: TStringList;
  k, bad, missing: Integer;
  saveX, saveY: Integer;
begin
  RepoRoot := IncludeTrailingPathDelimiter(ExpandFileName(ExtractFilePath(ParamStr(0)) + '../..'));
  RepoRoot := StringReplace(RepoRoot, '\', '/', [rfReplaceAll]);
  if Has('--diff') then
  begin
    for k := 1 to ParamCount - 2 do
      if ParamStr(k) = '--diff' then DiffDirs(ParamStr(k + 1), ParamStr(k + 2));
    Exit;
  end;
  OnlyText := Arg('--only');
  DumpDir := Arg('--dump');
  if DumpDir <> '' then ForceDirectories(DumpDir);
  hashFile := Arg('--hashes');
  checkFile := Arg('--check');
  Application.Initialize;
  TyRegisterBuiltinThemes;
  PrRegisterClasses;
  RegisterClasses([TMainMenu, TPopupMenu, TMenuItem, TTimer, TPanel, TLabel, TButton,
    TEdit, TMemo, TImageList, TActionList, TAction, TTreeView, TListView, TListBox,
    TComboBox, TCheckBox, TRadioButton, TGroupBox, TPageControl, TTabSheet]);
  TyFallbackFontName := 'Segoe UI';
  saveX := ScreenInfo.PixelsPerInchX;
  saveY := ScreenInfo.PixelsPerInchY;
  Log := TStringList.Create;
  Sink := TReaderSink.Create;
  Names := TStringList.Create;
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.ThemeName := 'default';
    Ctl.Mode := 'light';
    if Has('--perf') then
    begin
      RunPerf(Arg('--perf-out'), Arg('--perf-base'));
      Exit;
    end;
    RenderAll;
    ScreenInfo.PixelsPerInchX := saveX;
    ScreenInfo.PixelsPerInchY := saveY;
    WriteLn(Names.Count, ' scenes');
    if hashFile <> '' then
    begin
      ForceDirectories(ExtractFilePath(hashFile));
      Names.SaveToFile(hashFile);
      WriteLn('wrote ', hashFile);
    end;
    if checkFile <> '' then
    begin
      want := TStringList.Create;
      try
        want.LoadFromFile(checkFile);
        bad := 0;
        missing := 0;
        for k := 0 to want.Count - 1 do
          if Names.IndexOf(want[k]) < 0 then
          begin
            WriteLn('DIFFERS or missing: ', want[k]);
            Inc(bad);
          end;
        for k := 0 to Names.Count - 1 do
          if want.IndexOf(Names[k]) < 0 then
            Inc(missing);
        WriteLn(Format('%d scenes in the file, %d rendered, %d not identical', [want.Count, Names.Count, bad]));
        if (bad > 0) or (want.Count <> Names.Count) then
          ExitCode := 1;
      finally
        want.Free;
      end;
    end;
    if Log.Count > 0 then
      Log.SaveToFile(IncludeTrailingPathDelimiter(GetTempDir) + 'painterregress-log.txt');
    WriteLn(Log.Count, ' log lines (', IncludeTrailingPathDelimiter(GetTempDir) + 'painterregress-log.txt)');
  finally
    Ctl.Free;
    Names.Free;
    Sink.Free;
    Log.Free;
  end;
end.
