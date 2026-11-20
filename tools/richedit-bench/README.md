# Rich edit large-file bench

Measures what the TTyRichEdit design promises for large files (section 3.9 of the design:
a 100 MB txt or RTF shows its first screen in 1 s, any place in 100 ms, a keystroke paints
in 30 ms, memory stays within three times the file) on the machine it runs on, and prints
each figure against that line. The performance suite (`tests/test.richedit.perf.pas`) holds
the same figures to three times the line so that a busy gate passes; this tool does not.

It builds from `source/` without the package, as the other tools here do:

    /c/lazarus/lazbuild.exe tools/richedit-bench/richeditbench.lpi
    tools/richedit-bench/richeditbench.exe --quick          # 1 MB files, one run: seconds
    tools/richedit-bench/richeditbench.exe                  # 100 MB files, five runs each

The project builds at `-O1`, the level the test project builds at; the table names the level.

## Switches

| switch | |
|---|---|
| `--dir <folder>` | where the input files are made and the saves written (default `<temp>/tyrichbench`); never the repository |
| `--out <folder>` | where the table goes (default: `--dir`) |
| `--runs N` | runs per file (default 5; `--quick`: 1) |
| `--quick` | 1 MB files (eight small pictures), one run: to see it work, not the acceptance (the memory lines are below what the program itself takes, and a 1 MB file is too small to evict anything) |
| `--keep` | the input files are kept (default: each is deleted after its runs) |
| `--only k,k` | some of the files: `utf8`, `gbk`, `rtf`, `pictures`, `fields`, `equations` |
| `--size WxH` | the view (default 1200 x 900 at 96 PPI) |
| `--mb N` | the files' size (default 100) |

## The files

Made by the tool, deterministic (fixed text, a fixed seed for the pictures):

- `utf8` - the performance suite's three kinds of line (Chinese and Latin mixed, CRLF) and two
  short ones, 50 bytes a line on average: about two million lines in 100 MB, as the design
  counts them; `gbk` - the same lines in GBK, to 100 MB of GBK.
- `rtf` - in every hundred paragraphs, 84 of the suite's formatted paragraphs (bold, colour,
  Chinese as `\uN` in SimSun), a bullet list and a numbered list of five items each (Word's
  `\listtable`), and a table of two rows of three cells.
- `pictures` - 200 pictures, PNG and JPEG by turns in eight sizes from 200 x 150 to
  2400 x 1600 (about 0.1 MB to a few MB each), fifteen paragraphs before each.
- beyond the plan's four, reported apart: `fields` (200,000 hyperlinks and a 5,000-entry table
  of contents) and `equations` (2,000 of Word's equations), the suite's own files.

## How a run measures

Every run of every file is a fresh process (the program starts itself with `--child`), so no
run is warmed by the one before; the first run after the file was written counts as it is
(the file is in the system's cache then, as it is for every run). Before each run the
processor's load is sampled for a second: above 15 % the tool waits and tries again, six
times, then runs it and marks it busy; a figure is judged on the runs that were not busy.

The control has no window. It is painted by `PaintArea` into an off-screen bitmap as a window
paint (pictures deferred to the background work, the kept surface brought up to date and
blitted): the path `Paint` takes, without the system's own copy to the screen. In order:

1. **first screen** - from `LoadFromFile` to the end of the first paint;
2. RTF: the middle of what is indexed while the load goes on; then the rest of the index
   (`FinishLoading`, printed: the control does it in the background);
3. **the middle** (`ScrollY` to half the height) set and painted; then the background work
   decodes that view's pictures and the paint after it (printed);
4. **a place never shown** (70 % of the height: for an RTF, never parsed since the index);
5. **Ctrl+End** to the end of its paint;
6. other places shown until that place's layout has left the cache (2,048 paragraphs kept;
   24 places at least, more than the RTF reader's 16 parsed intervals) and **that place
   again**;
7. a find of a string that is not there, over the whole document in the background find's
   pieces (the whole and the longest piece, printed);
8. a **save unchanged** (checked byte for byte against the file), the memory after
   everything was read;
9. **keystrokes**, each from the key to the end of its paint: at the start (then a save after
   that one edit, printed), a character and a Backspace in the middle, one at the end;
10. the memory at the end and the peaks.

Memory is the working set and the private bytes (Windows), against three times the file's size.

Beside each view the runs file keeps `<figure>_layout` (the part until the view was laid
out) and `<figure>_parsed` (the RTF bytes parsed for it), and beside each key
`<figure>_keyonly` (the key without its paint): where the time went.

Each run checks what it measured and the table prints what failed: every timed paint changed
the pixels, every key added one undo step, the place never shown was laid out and parsed for
the paint, the place again was evicted (laid out and parsed again), a txt's first characters
are the ones written (its encoding was found), the unchanged save is the file.

## Output

The table on the console, and in the output folder `richedit-bench.md`,
`richedit-bench.csv` (figure, line, median, min, max, verdict) and `richedit-bench-runs.csv`
(every value of every run). The machine is printed first: CPU, cores, memory, Windows, the
compiler and its optimisation level, the processor's load before the runs.
