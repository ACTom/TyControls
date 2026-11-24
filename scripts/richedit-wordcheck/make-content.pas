program make_content;
{ Writes the files the second Word check opens: a page made with the builder, a document the
  editor's own doors changed (links, bookmarks), and a Word-written file changed the same
  way. Beside each file an .expect.txt: lines the Word-side dump must contain, word for word.
  No window is shown: the controls are created without a parent and never made visible. }
{$mode objfpc}{$H+}

uses
  Interfaces, Forms, Classes, SysUtils, Graphics, Controls, LazUTF8,
  tyControls.Controller, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands, tyControls.RichEdit.Attrs, tyControls.RichEdit.Builder,
  tyControls.RichEdit;

var
  OutDir, Repo: string;
  Ctl: TTyStyleController;
  Expect: TStringList;
  Log: TStringList;

procedure Say(const S: string);
begin
  Log.Add(S);
end;

procedure Want(const S: string);
begin
  Expect.Add(S);
end;

function NewRich: TTyRichEdit;
begin
  Result := TTyRichEdit.Create(nil);
  Result.Controller := Ctl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 600, 400);
end;

procedure SaveAll(ARich: TTyRichEdit; const AName: string);
begin
  ARich.SaveToFile(OutDir + AName + '.rtf', rfRtf);
  Expect.SaveToFile(OutDir + AName + '.expect.txt');
  Expect.Clear;
  Say('wrote ' + AName);
end;

{ The first place S stands at, selected (the control's own find: the positions of a document
  count its invisible marks, the text does not). }
procedure SelectText(ARich: TTyRichEdit; const S: string);
begin
  ARich.SelStart := 0;
  ARich.SelLength := 0;
  if not ARich.FindNext(S, []) then
    raise Exception.Create('text not found: ' + S);
end;

{ The caret AOffset characters after the start of the first S. }
procedure CaretIn(ARich: TTyRichEdit; const S: string; AOffset: Integer);
var
  p: TTyRichPos;
begin
  SelectText(ARich, S);
  p := ARich.SelStart;
  ARich.SelStart := p + AOffset;
  ARich.SelLength := 0;
end;

{ The size the control shows the text at the selection in, as Word prints a size. }
function ShownSize(ARich: TTyRichEdit): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FormatFloat('0.##', ARich.SelAttributes.SizeF, fs);
end;

procedure Must(ACond: Boolean; const AWhat: string);
begin
  if not ACond then
    raise Exception.Create('refused: ' + AWhat);
end;

{ ---------- 1: a page made with the builder ---------- }
procedure MakeBuilt;
var
  R: TTyRichEdit;
  B: TTyRichBuilder;
  i: Integer;
begin
  R := NewRich;
  try
    B := R.NewBuilder;
    try
      B.PageSetup(12240, 1440, 1800).DocumentColor(TColor($E0FFFF));   // RGB 255,255,224
      Want('page=612|72|90');
      Want('background=14745599');

      B.Font('Arial', 20).Bold.Bookmark('top').Text('Heading one').Paragraph;
      Want('bookmark[top]=');
      Want('para=Heading one|rule=0|ls=12|before=0|after=0|shade=auto|align=0|size=20|bold=1');
      B.Reset;

      B.Font('Arial', 10.5).Text('Half point size ten and a half.').Paragraph;
      Want('para=Half point size ten and a half.|rule=0|ls=12|before=0|after=0|shade=auto|align=0|size=10.5|bold=0');
      B.Reset;

      B.Text('Go to ').Link('section two', '#sec2').Text(' or ').Link('第二节', '#第二节')
        .Text(' or ').Link('the web', 'https://example.com/a%20b?x=1&y=2').Text('.').Paragraph;
      Want('link=|sec2|section two');
      Want('link=|第二节|第二节');
      Want('link=https://example.com/a b?x=1&y=2||the web');   // Word shows %20 as the space it stands for

      B.Bullet(0).Text('bullet level one').Paragraph;
      B.Bullet(1).Text('bullet level two').Paragraph;
      B.Numbered(0, 3).Text('numbered from three').Paragraph;
      B.Numbered(0).Text('numbered next').Paragraph;
      B.Numbered(1).Text('numbered inner').Paragraph;
      B.Numbered(1).Text('numbered inner two').Paragraph;
      B.Numbered(0).Text('numbered outer again').Paragraph;
      Want('list=bullet level one|level=1');
      Want('list=bullet level two|level=2');
      Want('indent=bullet level two|54|-18|0');
      Want('list=numbered from three|level=1|string=3.');
      Want('list=numbered next|level=1|string=4.');
      Want('list=numbered inner|level=2|string=1.');
      Want('list=numbered inner two|level=2|string=2.');
      Want('list=numbered outer again|level=1|string=5.');
      B.Reset;

      B.Tab(100).Tab(300, rtaRight, rtlDot).Text('name'#9'value'#9'12.50').Paragraph;
      Want('tabs=name|100:0:0,300:2:1');
      B.Reset;

      B.Shading(TColor($00FFFF)).Text('a shaded note paragraph').Paragraph;       // yellow
      Want('para=a shaded note paragraph|rule=0|ls=12|before=0|after=0|shade=65535|align=0|size=');
      B.Reset;

      B.LineSpacing(1.5).Text('one and a half lines').Paragraph;
      Want('para=one and a half lines|rule=1|ls=18|');
      B.Reset;
      B.LineSpacing(3).Text('three lines').Paragraph;
      Want('para=three lines|rule=5|ls=36|');
      B.Reset;
      B.LineSpacing(1.15).Text('one point one five').Paragraph;
      Want('para=one point one five|rule=5|ls=13.8|');
      B.Reset;
      B.LineSpacingExact(20).Text('exactly twenty points').Paragraph;
      Want('para=exactly twenty points|rule=4|ls=20|');
      B.Reset;
      B.Spacing(6, 12).Align(paraCenter).Text('space six before twelve after centred').Paragraph;
      Want('para=space six before twelve after centred|rule=0|ls=12|before=6|after=12|shade=auto|align=1|');
      B.Reset;
      B.Indent(36, -18, 24).Text('indented with a hanging first line').Paragraph;
      Want('indent=indented with a hanging first line|36|-18|24');
      B.Reset;

      B.Color(clRed).Text('red ').Color(clDefault).Highlight(clYellow).Text('marked ')
        .Highlight(clNone).Superscript.Text('up').Superscript(False).Subscript.Text('down')
        .Subscript(False).StrikeOut.Text(' struck').StrikeOut(False).Paragraph;
      Want('run=red |255|');
      B.Reset;

      B.Table([2000, 4000]);
      B.Cell.Text('a1').Cell.Text('b1 中文');
      B.Row;
      B.Cell.Text('a2').Cell.Bold.Text('b2').Bold(False);
      B.EndTable;
      Want('table=1|rows=2|cols=2|w=100,200');
      Want('cell=1,2|b1 中文');

      B.Paragraph.Font('宋体', 14).Bold.BookmarkStart('sec2').Text('Section two')
        .BookmarkEnd('sec2').Paragraph;
      Want('bookmark[sec2]=Section two');
      B.Reset;
      for i := 1 to 3 do
        B.Text('Body of section two, line ' + IntToStr(i) + '.').Paragraph;
      B.Bold.Bookmark('第二节').Text('第二节 中文书签').Paragraph;
      Want('bookmark[第二节]=');
      B.Reset;
      B.Text('末尾。');
      R.SetContent(B);
    finally
      B.Free;
    end;
    // text with no size of its own: Word must show it at the size the control shows it in
    SelectText(R, 'Body of section two, line 1.');
    Want('para=Body of section two, line 1.|rule=0|ls=12|before=0|after=0|shade=auto|align=0|size='
      + ShownSize(R) + '|bold=0');
    Say('the document''s own size: ' + ShownSize(R));
    SaveAll(R, 'built');
  finally
    R.Free;
  end;
end;

{ ---------- 2: the editor's own doors ---------- }
procedure MakeEdited;
var
  R: TTyRichEdit;
  B: TTyRichBuilder;
begin
  R := NewRich;
  try
    B := R.NewBuilder;
    try
      B.Text('First paragraph with a word to link and another one.').Paragraph;
      B.Text('Second paragraph holds the target heading.').Paragraph;
      B.Text('Third paragraph: 这里有中文目标。').Paragraph;
      B.Text('Fourth paragraph: a link to change, a link to remove.');
      R.SetContent(B);
    finally
      B.Free;
    end;

    SelectText(R, 'target heading');
    Must(R.AddBookmark('Target_1'), 'AddBookmark Target_1');
    Want('bookmark[Target_1]=target heading');
    SelectText(R, '中文目标');
    Must(R.AddBookmark('中文书签'), 'AddBookmark Chinese');
    Want('bookmark[中文书签]=中文目标');
    CaretIn(R, 'Third', 0);
    Must(R.AddBookmark('ToRename'), 'AddBookmark ToRename');
    Must(R.RenameBookmark('ToRename', 'Renamed_2'), 'RenameBookmark');
    Want('bookmark[Renamed_2]=');
    Want('nobookmark=ToRename');
    CaretIn(R, 'Fourth', 0);
    Must(R.AddBookmark('ToDelete'), 'AddBookmark ToDelete');
    Must(R.DeleteBookmark('ToDelete'), 'DeleteBookmark');
    Want('nobookmark=ToDelete');

    SelectText(R, 'word to link');
    Must(R.InsertLink('#Target_1'), 'InsertLink to a bookmark');
    Want('link=|Target_1|word to link');
    SelectText(R, 'another one');
    Must(R.InsertLink('https://example.com/文档?q=a b'), 'InsertLink web');
    Want('link=https://example.com/文档?q=a b||another one');
    CaretIn(R, 'a link to change', 0);
    Must(R.InsertLink('#中文书签', '到中文书签'), 'InsertLink with a text');
    Want('link=|中文书签|到中文书签');

    SelectText(R, 'a link to change');
    Must(R.InsertLink('http://old.example/'), 'InsertLink to change');
    CaretIn(R, 'link to change', 2);
    Must(R.SetLink('http://new.example/path'), 'SetLink');
    Want('link=http://new.example/path||a link to change');
    Want('nolink=http://old.example/');

    SelectText(R, 'a link to remove');
    Must(R.InsertLink('http://gone.example/'), 'InsertLink to remove');
    CaretIn(R, 'link to remove', 2);
    Must(R.RemoveLink, 'RemoveLink');
    Want('nolink=http://gone.example/');
    Want('links=4');
    Want('bookmarks=3');
    SelectText(R, 'Second paragraph holds the');
    Want('para=Second paragraph holds the target heading.|rule=0|ls=12|before=0|after=0|shade=auto|align=0|size='
      + ShownSize(R) + '|bold=0');
    SaveAll(R, 'edited');
  finally
    R.Free;
  end;
end;

{ ---------- 2b: lettered and roman lists through the paragraph door ---------- }
procedure MakeLetters;
var
  R: TTyRichEdit;
  B: TTyRichBuilder;
  i: Integer;
const
  Names: array[0..8] of string = ('letter one', 'letter two', 'letter three', 'upper one',
    'upper two', 'roman one', 'roman two', 'far one', 'far two');
begin
  R := NewRich;
  try
    B := R.NewBuilder;
    try
      for i := 0 to 8 do
      begin
        B.Text(Names[i]).Paragraph;
        if i in [2, 4, 6] then B.Text('plain between ' + IntToStr(i)).Paragraph;
      end;
      B.Text('the end');
      R.SetContent(B);
    finally
      B.Free;
    end;
    // lower letters from 26: z, aa, bb
    SelectText(R, 'letter one'); R.Paragraph.Numbering := lkLowerAlpha; R.Paragraph.NumberingStart := 26;
    SelectText(R, 'letter two'); R.Paragraph.Numbering := lkLowerAlpha;
    SelectText(R, 'letter three'); R.Paragraph.Numbering := lkLowerAlpha;
    Want('list=letter one|level=1|string=z.');
    Want('list=letter two|level=1|string=aa.');
    Want('list=letter three|level=1|string=bb.');
    // upper letters from 52: ZZ, AAA
    SelectText(R, 'upper one'); R.Paragraph.Numbering := lkUpperAlpha; R.Paragraph.NumberingStart := 52;
    SelectText(R, 'upper two'); R.Paragraph.Numbering := lkUpperAlpha;
    Want('list=upper one|level=1|string=ZZ.');
    Want('list=upper two|level=1|string=AAA.');
    // lower roman from 9: ix, x
    SelectText(R, 'roman one'); R.Paragraph.Numbering := lkLowerRoman; R.Paragraph.NumberingStart := 9;
    SelectText(R, 'roman two'); R.Paragraph.Numbering := lkLowerRoman;
    Want('list=roman one|level=1|string=ix.');
    Want('list=roman two|level=1|string=x.');
    // letters at the limit the control writes in letters, and one past it
    SelectText(R, 'far one'); R.Paragraph.Numbering := lkLowerAlpha; R.Paragraph.NumberingStart := 780;
    SelectText(R, 'far two'); R.Paragraph.Numbering := lkLowerAlpha;
    SaveAll(R, 'letters');
  finally
    R.Free;
  end;
end;

{ ---------- 3: a Word-written file changed through the same doors ---------- }
procedure MakeWordEdited;
var
  R: TTyRichEdit;
  i, n: Integer;
  first: string;
begin
  R := NewRich;
  try
    R.LoadFromFile(Repo + 'tests\fixtures\rtf\word-toc.rtf');
    n := R.BookmarkCount;
    Say('word-toc bookmarks (listed): ' + IntToStr(n));
    for i := 0 to n - 1 do
      Say('  ' + R.BookmarkName(i));
    first := '';
    if n > 0 then
      first := R.BookmarkName(0);
    R.SelStart := 0;
    R.SelLength := 0;
    Must(R.AddBookmark('Added_By_Us'), 'AddBookmark in a Word file');
    Want('bookmark[Added_By_Us]=');
    if first <> '' then
    begin
      Must(R.RenameBookmark(first, 'Renamed_By_Us'), 'RenameBookmark in a Word file');
      Want('bookmark[Renamed_By_Us]');
      Want('nobookmark=' + first);
    end;
    SaveAll(R, 'wordtoc-edited');
  finally
    R.Free;
  end;
end;

begin
  Application.Initialize;
  Repo := ParamStr(1);
  OutDir := ParamStr(2);
  Log := TStringList.Create;
  Expect := TStringList.Create;
  Ctl := TTyStyleController.Create(nil);
  try
    try
      MakeBuilt;
      MakeEdited;
      MakeLetters;
      MakeWordEdited;
      Say('ALL DONE');
    except
      on E: Exception do
        Say('FATAL ' + E.ClassName + ': ' + E.Message);
    end;
  finally
    Log.SaveToFile(OutDir + 'make-content.log');
    Ctl.Free;
  end;
end.
