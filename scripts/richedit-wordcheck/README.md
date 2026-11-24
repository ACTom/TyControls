# Checking TTyRichEdit's files against Word

What the rich edit writes must read in Microsoft Word as the control shows it, and what Word
lays out must be laid out the same way here. These scripts are how that was checked. They
need Word on Windows and are not part of any test run: nothing here is called by the suites.

Every script starts a Word of its own that stays invisible, opens only the files it is given
(read-only) or documents it creates itself, saves only into the folder you name, and ends
only that Word. None of them writes a Word setting (`Options.*`, `UserName`): those belong to
the person at the machine and outlive the script.

## Does Word read what we write?

1. Build and run a producer (Lazarus 4.4; the projects compile the package's sources in
   `../../source` directly):

       lazbuild scripts/richedit-wordcheck/make-content.lpi
       scripts/richedit-wordcheck/make-content.exe <repository>\ <out>\

   `make-content` writes `built.rtf` (a page made with `TTyRichBuilder`: links, bookmarks,
   lists, tab stops, shading, every line-spacing kind, a table, the page colour),
   `edited.rtf` (links and bookmarks made through the control's doors), `letters.rtf`
   (lettered and roman lists) and `wordtoc-edited.rtf` (a Word-written file changed the same
   way). Beside each: `<name>.expect.txt`, the lines Word's reading must contain.

       scripts/richedit-wordcheck/make-table-edits.exe tests\fixtures\rtf\word-table-styled.rtf <out>\

   `make-table-edits` changes a Word-written table through each table door and saves one
   file per change (`t1-shading.rtf`, `t2-width.rtf`, …; `t0-nothing.rtf` must be the fixture,
   byte for byte).

2. Let Word read them:

       pwsh scripts/richedit-wordcheck/check-content.ps1 -Dir <out>
       pwsh scripts/richedit-wordcheck/check-tables.ps1 -Dir <out> -Names t0-nothing,t1-shading,t2-width
       pwsh scripts/richedit-wordcheck/check-lists.ps1 -Dir <folder> -Names <name>
       pwsh scripts/richedit-wordcheck/check-grid.ps1 -Dir <folder> -Names <name> [-Table 2]

   `check-content` writes `<name>.dump.txt` (what Word reads: page set-up, background, links,
   bookmarks, each paragraph's formats, lists, tab stops, tables) and prints every expectation
   that the dump does not hold. `check-tables` lists every cell as Word has it
   (`<name>.word.txt`: widths, shading, the four borders, padding, vertical alignment, row
   heights, table alignment) and, where a `<name>.txt` in the same form stands beside the
   file, the lines that differ. `check-lists` compares the marker Word shows for each list
   item with a `<name>.markers.txt` (text, a tab, the marker the control draws). `check-grid`
   writes each table's grid as Word's own XML has it (`<name>.wordgrid.txt`: the grid's
   column widths, then per row every cell's column span, vertical merge, width and text) and
   compares it with a `<name>.grid.txt` in the same form — how merged and split cells are
   checked.

   Two things in Word's answers are Word's own and not a difference: a table's indent is
   measured to the text (the left padding more than `\trleft`), and a `%20` in an address is
   shown as the space it stands for.

`make-list-sample.py` writes a small file by hand with lists the way Word writes them (a list
table, an override with its start for every run, `\ls` and `\ilvl`): the form the control's
writer follows.

## How does Word lay a line out?

    pwsh scripts/richedit-wordcheck/measure-line-spacing.ps1 -OutDir <folder>
    python scripts/richedit-wordcheck/emf-positions.py <folder>/out2/page.emf

The measuring scripts build a document in Word (fonts and line spacings in turn, a one-cell
table after each paragraph as a ruler), take the page as a metafile and
`emf-positions.py` prints where every piece of text and every table line sits; 100 units are
12 points. From those numbers come the rules the layout follows: a font's own line height,
the 1.3 of East Asian fonts, where the extra of a multiple, of "at least" and of "exactly"
goes, multiples below one, and that a table has no top margin.
`measure-multiples-below-one.ps1`, `measure-page-colour.ps1` and
`measure-bookmark-names.ps1` answer one question each (their first lines say which).
