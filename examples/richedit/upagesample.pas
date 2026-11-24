unit upagesample;

{ A page built from code: what an application shows as its home page, a navigation page or a
  help page - rich content without a file and without an HTML viewer.

  BuildPage below makes the whole page with a TTyRichBuilder, top to bottom, in the order the
  page reads:
    - a picture (a glyph of the example's icon font) and a heading;
    - a paragraph with bold and coloured words, written as ONE sentence with marked spans
      (Say): a translator gets the whole sentence and may move the words - do the same in your
      own pages rather than cutting a sentence around its bold words;
    - a contents list of links to the sections further down ("#name": a click jumps to the
      bookmark by itself) and a link to a web page;
    - three sections, each with a bookmark at its heading: a shaded note; a bulleted and a
      numbered list with a second level; lines with tab stops and a dot leader; a two-column
      table with its own column widths;
    - "Back to the top" links.
  Text is in the automatic colour and links in the link look, so the page follows the skin
  and its dark mode by itself. The picture is pixels: it is drawn in the theme's accent when
  the page is built, so the form builds the page again when the skin changes. The two colours
  of the page's own (the red word, the note's ground) stay, as a document's colours do.

  Putting it in (upageform): Rich.SetContent(B) - a new content, no undo history;
  Rich.AppendContent(B) - added at the end as one undo step. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, BGRABitmap, BGRABitmapTypes, tyControls.Types,
  tyControls.Controller, tyControls.IconFont, tyControls.RichEdit.Model, StrUtils,
  tyControls.RichEdit.Attrs, tyControls.RichEdit.Builder, tyControls.RichEdit;

{ The whole page into B (a builder from Rich.NewBuilder). AIcons gives the picture at the top
  (nil: no picture). }
procedure BuildPage(B: TTyRichBuilder; AIcons: TTyCustomIconFont);

{ ASentence into B, the sentence whole: **text** bold, `text` in a code font, !!text!! red;
  the rest in B's current format, which it is again after each span. }
procedure Say(B: TTyRichBuilder; const ASentence: string);

{ One line "Appended at <time>." into B, for AppendContent. }
procedure BuildStamp(B: TTyRichBuilder);

{ The small example of the documentation (docs/controls/richedit.md, "Building content from
  code"), word for word: kept here so that it is compiled with the example. }
procedure ShowWelcome(Rich: TTyRichEdit);

resourcestring
  rsPgTitle      = 'A page built from code';
  // one sentence, its spans marked (see Say): a translator may reorder it as a whole
  rsPgIntro      = 'This page is not a file. It is made in `upagesample.pas` with ' +
                   '**TTyRichBuilder**, in calls that read the way the page does: ' +
                   '**bold words**, a word in !!red!!, links, lists, tab stops, a table and ' +
                   'a picture.';
  rsPgContents   = 'Contents';
  rsPgWeb        = 'The Lazarus home page';
  rsPgS1         = '1. Showing a page';
  rsPgS1a        = 'A rich edit can show a page instead of editing one: an application''s home ' +
                   'page, a page that leads to its parts, its help. It is read only, has no caret, ' +
                   'and a plain click on a link follows it.';
  rsPgS1b        = 'The same content is shown on two tabs of this window. The help page can be ' +
                   'selected and copied and scrolls by itself. The home page cannot be selected, ' +
                   'never takes the focus, has no scroll bars of its own and is as tall as its ' +
                   'content: the scroll box around it scrolls the whole page.';
  rsPgNote       = 'Note: switch the skin or the dark mode with this window open. The text and ' +
                   'the links take the new theme''s colours; only the colours the page chose ' +
                   'itself stay.';
  rsPgS1c        = 'A click on an entry of the contents jumps to its section: the section''s ' +
                   'heading comes to the top of the view.';
  rsPgS2         = '2. Lists and tab stops';
  rsPgS2a        = 'A bulleted list with a second level:';
  rsPgBullet1    = 'Links to the sections of the page';
  rsPgBullet1a   = 'each one jumps to a bookmark';
  rsPgBullet1b   = 'and "Back to the top" jumps back';
  rsPgBullet2    = 'Pictures from an image list, an icon font, a file or a resource';
  rsPgBullet3    = 'Tables with the widths you give their columns';
  rsPgS2b        = 'A numbered list:';
  rsPgStep1      = 'Make a builder: B := Rich.NewBuilder';
  rsPgStep1a     = 'add the text, the formats and the links to it';
  rsPgStep2      = 'Put it in: Rich.SetContent(B)';
  rsPgStep3      = 'Free the builder, or keep it and put it in again';
  rsPgS2c        = 'Tab stops with a dot leader, as in a table of contents:';
  rsPgTab1       = 'Showing a page';
  rsPgTab2       = 'Lists and tab stops';
  rsPgTab3       = 'A table';
  rsPgS3         = '3. A table';
  rsPgS3a        = 'Two columns, 1.5 and 3.5 inches wide:';
  rsPgColProp    = 'Property';
  rsPgColWhat    = 'On the home page';
  rsPgReadOnly   = 'True: nothing can be typed';
  rsPgAllowSel   = 'False: nothing can be selected';
  rsPgFocus      = 'False: a click never takes the focus';
  rsPgBars       = 'ssNone: no scroll bars of its own';
  rsPgAutoH      = 'True: as tall as its content';
  rsPgS3b        = 'The table''s cells hold text, links and pictures like any paragraph. The ' +
                   'columns keep the widths given here whatever the window''s width.';
  rsPgTop        = 'Back to the top';
  rsPgStamp      = 'Appended at %s.';

implementation

{ The glyph AName of AIcons as a PNG picture, ASize pixels, in the theme's accent (--accent)
  as the skin has it now - a picture does not change colour later: build the page again on a
  skin change (upageform does). }
procedure AddGlyph(B: TTyRichBuilder; AIcons: TTyCustomIconFont; const AName: string; ASize: Integer);
var
  bmp: TBGRABitmap;
  s: TMemoryStream;
begin
  if (AIcons = nil) or not AIcons.HasGlyph(AName) then Exit;
  bmp := AIcons.RenderGlyph(AName, ASize,
    TyDefaultController.Model.ResolveColorToken('--accent', TyRGB(37, 99, 235)));
  s := TMemoryStream.Create;
  try
    bmp.SaveToStreamAsPng(s);
    s.Position := 0;
    // its size in points: at 96 dpi a pixel is 0.75 point
    B.Picture(s, ASize * 0.75, ASize * 0.75);
  finally
    s.Free;
    bmp.Free;
  end;
end;

{ A section's heading: bookmark AName at its start, bold, larger, space above. }
procedure Heading(B: TTyRichBuilder; const AName, AText: string);
begin
  B.Paragraph.SpaceBefore(18).SpaceAfter(6).Bookmark(AName);
  B.Font('', 15).Bold.Text(AText);
  B.Paragraph.Reset;
end;

{ "Back to the top", a paragraph of its own. }
procedure BackToTop(B: TTyRichBuilder);
begin
  B.Paragraph.SpaceBefore(6).Link(rsPgTop, '#top');
end;

procedure BuildPage(B: TTyRichBuilder; AIcons: TTyCustomIconFont);
begin
  // the title: a picture and the heading, the bookmark the "back to the top" links go to
  B.Bookmark('top');
  AddGlyph(B, AIcons, 'book-open', 40);
  B.Text(' ').Font('', 22).Bold.Text(rsPgTitle);
  B.SpaceAfter(8);

  // a paragraph with words of its own format
  B.Paragraph.Reset.SpaceAfter(8);
  Say(B, rsPgIntro);

  // the contents: links to the sections' bookmarks, and one to a web page
  B.Paragraph.Bold.Text(rsPgContents).Reset;
  B.Paragraph.Bullet.Link(rsPgS1, '#showing');
  B.Paragraph.Bullet.Link(rsPgS2, '#lists');
  B.Paragraph.Bullet.Link(rsPgS3, '#table');
  B.Paragraph.Bullet.Link(rsPgWeb, 'https://www.lazarus-ide.org/');

  // 1. showing a page: text and a shaded note
  Heading(B, 'showing', rsPgS1);
  B.SpaceAfter(6).Text(rsPgS1a);
  B.Paragraph.SpaceAfter(6).Text(rsPgS1b);
  B.Paragraph.Shading(TColor($00D7F4FF)).Indent(6, 0, 6).Spacing(6, 6).Text(rsPgNote);
  B.Paragraph.SpaceAfter(6).Text(rsPgS1c);
  BackToTop(B);

  // 2. lists (a second level) and tab stops with a dot leader
  Heading(B, 'lists', rsPgS2);
  B.Text(rsPgS2a);
  B.Paragraph.Bullet(0).Text(rsPgBullet1);
  B.Paragraph.Bullet(1).Text(rsPgBullet1a);
  B.Paragraph.Bullet(1).Text(rsPgBullet1b);
  B.Paragraph.Bullet(0).Text(rsPgBullet2);
  B.Paragraph.Bullet(0).Text(rsPgBullet3);
  B.Paragraph.SpaceBefore(6).Text(rsPgS2b);
  B.Paragraph.Numbered(0).Text(rsPgStep1);
  B.Paragraph.Numbered(1).Text(rsPgStep1a);
  B.Paragraph.Numbered(0).Text(rsPgStep2);
  B.Paragraph.Numbered(0).Text(rsPgStep3);
  B.Paragraph.SpaceBefore(6).Text(rsPgS2c);
  B.Paragraph.Tab(300, rtaRight, rtlDot).Text(rsPgTab1 + #9'1');
  B.Paragraph.Tab(300, rtaRight, rtlDot).Text(rsPgTab2 + #9'2');
  B.Paragraph.Tab(300, rtaRight, rtlDot).Text(rsPgTab3 + #9'3');
  BackToTop(B);

  // 3. a table of two columns, 1.5 and 3.5 inches (1440 twips an inch)
  Heading(B, 'table', rsPgS3);
  B.Text(rsPgS3a);
  B.Table([2160, 5040]);
  B.Cell.Bold.Text(rsPgColProp).Cell.Text(rsPgColWhat).Reset;
  B.Row.Cell.Text('ReadOnly').Cell.Text(rsPgReadOnly);
  B.Row.Cell.Text('AllowSelection').Cell.Text(rsPgAllowSel);
  B.Row.Cell.Text('FocusOnClick').Cell.Text(rsPgFocus);
  B.Row.Cell.Text('ScrollBars').Cell.Text(rsPgBars);
  B.Row.Cell.Text('AutoHeight').Cell.Text(rsPgAutoH);
  B.EndTable;
  B.Paragraph.SpaceBefore(6).Text(rsPgS3b);
  BackToTop(B);
end;

procedure ShowWelcome(Rich: TTyRichEdit);
var
  B: TTyRichBuilder;
begin
  B := Rich.NewBuilder;              // the document's own defaults; yours to free
  try
    B.Font('', 20).Bold.Text('Welcome');
    B.Paragraph.Reset.Text('Read the ').Link('guide', '#guide')
      .Text(' or visit ').Link('the Lazarus site', 'https://www.lazarus-ide.org/').Text('.');
    B.Paragraph.Bullet.Text('A point');
    B.Paragraph.Bullet(1).Text('a point under it');
    B.Paragraph.Shading(TColor($00D7F4FF)).Text('A note on a light yellow ground.');
    B.Table([2160, 5040]);
    B.Cell.Bold.Text('Name').Cell.Text('What it is').Reset;
    B.Row.Cell.Text('Builder').Cell.Text('Content made from code');
    B.EndTable;
    B.Paragraph.SpaceBefore(12).Bookmark('guide').Bold.Text('The guide').Reset;
    B.Paragraph.Text('A "#guide" link jumps here by itself.');
    Rich.SetContent(B);              // a new content; AppendContent, InsertContent add to it
  finally
    B.Free;
  end;
end;

procedure Say(B: TTyRichBuilder; const ASentence: string);
var
  i, j: Integer;
  mark: string;
begin
  i := 1;
  while i <= Length(ASentence) do
  begin
    // a span: its opening mark, its text, the same mark closing it
    mark := '';
    if Copy(ASentence, i, 2) = '**' then mark := '**'
    else if Copy(ASentence, i, 2) = '!!' then mark := '!!'
    else if ASentence[i] = '`' then mark := '`';
    if mark <> '' then
    begin
      j := PosEx(mark, ASentence, i + Length(mark));
      if j > 0 then
      begin
        if mark = '**' then B.Bold
        else if mark = '!!' then B.Color(clRed)
        else B.Font('Consolas');
        B.Text(Copy(ASentence, i + Length(mark), j - i - Length(mark))).Reset;
        i := j + Length(mark);
        Continue;
      end;
    end;
    // plain text up to the next mark
    j := i + 1;
    while (j <= Length(ASentence)) and (Copy(ASentence, j, 2) <> '**') and
      (Copy(ASentence, j, 2) <> '!!') and (ASentence[j] <> '`') do
      Inc(j);
    B.Text(Copy(ASentence, i, j - i));
    i := j;
  end;
end;

procedure BuildStamp(B: TTyRichBuilder);
begin
  B.Text(Format(rsPgStamp, [TimeToStr(Now)]));
end;

end.
