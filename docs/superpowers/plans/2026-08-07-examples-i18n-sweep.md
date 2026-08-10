# Examples i18n sweep — code strings into resourcestrings (2026-08-07)

The 92-launch survey (46 examples × zh_CN and `--lang=en`) found ~39 examples
still building user-visible text from Pascal literals no catalogue could reach.
This pass converted them. This file records the mechanism findings and the
judgment lines, because both were non-obvious and will be needed again the next
time anyone adds a string to an example.

## How example i18n actually works (measured, not assumed)

- Runtime: each `.lpr` calls `SetDefaultLang('', LangDir)` (app catalogue:
  `<project>.<lang>.po`, `--lang=xx` overrides OS locale) plus
  `TranslateUnitResourceStringsEx('', LangDir, 'tycontrols',
  'tyControls.StrConsts')` (library catalogue). Both halves were verified on
  screen: zh_CN run fully Chinese including runtime-`Format` status lines,
  `--lang=en` fully English.
- **`lazbuild -B` does NOT regenerate the `.po`/`.pot`, despite `EnableI18N`
  in every `.lpi`.** That collection step is IDE-only. What the build does emit
  is `lib/<cpu>-<os>/<unit>.rsj` — and that is the source of truth for code
  strings: `name` is the lowercase `unit.constname` identifier the runtime
  looks up, and **`sourcebytes` (not `value`) holds the true UTF-8**; the
  `value` field spreads UTF-8 bytes over Latin-1 chars and produces mojibake
  if trusted.
- The `.po` files are therefore maintained by hand/script. Convention used
  throughout: `#: unit.constname`, `#, object-pascal-format` when the msgid
  carries `%`-placeholders, msgid = the Pascal source string, msgstr = zh_CN.
  TStrings-valued `.lfm` properties legitimately repeat one identifier with
  different msgids (runtime falls back to original-value matching).
- Two hazards are pinned by `test.i18n` / the smoke script and were re-proven
  by mutation here: an entry with msgid AND msgstr both empty raises inside
  `CreateForm` (looks like "the app is slow"), and a placeholder mismatch
  between msgid and msgstr is a runtime `Format` error waiting for that code
  path.

## What earns a resourcestring (the judgment line)

Converted: status/feedback lines (including every `Format` frame), column and
header titles built in code, group/tab captions, dialog titles and prompts,
menu items, hints, list items that are UI vocabulary (view names, style names,
weekday names), sample data the user reads as prose (grid regions/products/
order notes, tree folder names, transfer people names), and words interpolated
into sentences (`collapsed`/`expanded`, `On`/`Off`).

Left as literals, deliberately:

- Theme/mode names (`default`, `dark`), StyleClass/typeKey tokens, icon keys,
  font names, CSS snippets, `FormatDateTime` patterns, file names and paths,
  `SO-2026%04d`-style ID patterns, hex colours.
- Technical identifiers shown as themselves: event names (`OnChange`),
  enum spellings (`scLineUp`, `taCenter`, `True/False`), component names.
- listbox/combobox city lists: recognisable romanisations either way, and the
  combobox one sits under `Sorted=True` — translating re-orders the list under
  the "first item after sorting" comment.
- CSV import samples in grid (they demonstrate quoting/line-break parsing) and
  the hardcoded paste block.
- **examples/rtl in its entirety**: its strings are a self-managed
  English⇄Arabic pair corpus with its own in-app language switch — a third
  catalogue language would fight the demo's own axis. Its `.lfm` strings are
  in the `.po` like everyone else's.
- transitions and hint have no user-visible code strings.

Typed const arrays cannot hold resourcestrings, so data pools became mapper
functions (`RegionName(i)`, `KindDisplay(key)`, `OrderTitle(i)`, …). Where a
string is both display and predicate (listview's `Folder`, inputs' `About`
row, grid's kind keys for icon mapping), the comparison uses the same constant
— or, in treeview, the table keeps English keys and only display translates,
so the icon-by-kind mapping stays byte-stable.

## Incidental fixes that fell out

- grid `BtnLongCaptionClick`: `Pos('Word wrap', c.Text)` never matched the
  English long title, so the toggle could not switch back; now compares
  against the resourcestring, which is also translation-proof.
- antdesign `AlertClosed` mixed an ASCII open quote with a `」` close quote.
- inputs `.lfm` re-layout (13+ clipped labels): column-1 labels wrap in place,
  column-4 headers are `AutoSize = True` (skin-fit-guard-safe), over-long ones
  wrap into the free band above their control, three captions shortened (with
  `.po` msgid sync), form widened 1300→1316 so column 5 is not flush with the
  window edge.
- demo `Options` group narrowed 152→144 and moved 452→444: it ended 2 px shy
  of its pane and clipped under fatter skins.
- combobox right-column hint shortened: its third wrapped line was cut by the
  combo below.
- shapes `btndark` and demo `btnapdark` said 深色 where 42 siblings say 暗色.
- `examples/dialogs/languages/tycontrols.zh.po` dropped: byte-identical
  duplicate of `tycontrols.zh_CN.po`, never loaded on zh_CN (exact match
  wins), unmaintained for other zh locales, and demo.zh.po was already dropped
  on the same grounds.

## Verified

46/46 `lazbuild -B`, `check-lfm-props.py` OK, smoke launcher 46/46 visible
windows, full unit suite 5815/0/0 (unchanged from baseline — including
TSkinFitTest over the edited `.lfm`s), `.po` lint clean (93 files:
no empty-empty entries, placeholder parity, no duplicate conflicts).
