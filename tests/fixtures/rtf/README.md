# TTyRichEdit samples

Every file here and in `../txt/` is kept byte for byte (`.gitattributes`: `-text`). The words in
them are our own, so they can be public. `<name>.expected.txt` is the text `<name>.rtf` must read
as: UTF-8, one paragraph per line, each line ended by LF.

## Hand-made (`scripts/gen-richedit-fixtures.py` writes them; every byte is spelled out there)

| File | Code page, fonts | What it is for |
|---|---|---|
| `hand-big5.rtf` | `\ansicpg950`; f0 `\fcharset136` 新細明體, f1 Arial, f2 細明體 with no `\fcharset` | Traditional Chinese through `\'xx\'xx`. 許 (B3 5C) and 功 (A5 5C) end in a backslash byte. The last paragraph is in f2, which can only be decoded through `\ansicpg950`. |
| `hand-sjis.rtf` | `\ansicpg932`; f0 `\fcharset128` ＭＳ 明朝, f1 Arial | Japanese. ソ (83 5C) and 表 (95 5C) end in a backslash byte; the half-width katakana ｱｲｳ are single bytes and not lead bytes. |
| `hand-uc.rtf` | `\ansicpg936`; f0 `\fcharset134` 宋体, f1 Arial | `\uc0`, `\uc2`, `\uc1`; a negative `\u` (`\u-244` is ，); `\uc` ending with its group; a `\'xx` as the one fallback; a surrogate pair as one character. |
| `hand-split-dbcs.rtf` | `\ansicpg936`; f0 `\fcharset134` 宋体, f1 Arial | The two bytes of 中 kept apart by a group end, a control word, a group start (they join: same double-byte font), and by a font change to f1 (they do not). |

The expected texts were compared with what the system RichEdit (msftedit.dll, the engine WordPad
runs on, Windows 10 19044) reads from the same files. It agrees everywhere except:

- `hand-big5.rtf`, last paragraph: RichEdit decodes a font that names no charset with the
  system's code page (936 on the machine that made these), and shows nonsense. We decode it with
  the file's `\ansicpg`, as the RTF specification says and as the design requires.
- `hand-split-dbcs.rtf`, paragraphs 1 to 3: RichEdit pairs the lead byte with whatever byte comes
  next, a brace included, and shows nonsense. We join the halves. Paragraph 4 is RichEdit's own
  reading: `x?Ðy`.

Each `hand-*.rtf` ends the way WordPad ends a file: `}`, CR LF, and one NUL byte.

## Text files (`../txt/`, the same script)

| File | Bytes |
|---|---|
| `utf8-bom.txt` | UTF-8 with BOM, CRLF |
| `utf8-nobom.txt` | UTF-8, no BOM, LF |
| `utf16le.txt`, `utf16be.txt` | UTF-16 with BOM, CRLF; one character outside the BMP |
| `gbk.txt` | GBK (code page 936), CRLF; not valid UTF-8 |
| `mixed-eol.txt` | UTF-8 with BOM; five LF and two CRLF; nothing after the last line |
| `gbk-badbytes.txt` | GBK with a lone FF and a lead byte 81 right before a line end |
| `utf8-badbytes.txt` | UTF-8 (to be read with the encoding forced) with an overlong C0 AF, a lone 80, and a sequence cut short at the end of the file |

## Written by WordPad's engine (`scripts/gen-richedit-fixtures-msftedit.py`)

WordPad is a window around the system RichEdit control (msftedit.dll): what it saves is what
that control streams out. The script gives the control a short RTF source, lets it stream the
document back out (EM_STREAMOUT, SF_RTF), and keeps that output: the engine's own font table,
`\'xx` for text in the font's code page, `\uN?` for the rest, `\pntext` / `{\*\pn ...}` lists,
`{\pict{\*\picprop ...}\pngblip ...}`, `\trowd ... \cell ... \row`, and the `}` CR LF NUL ending.
The control lives in a message-only window; nothing was typed, clicked or pasted. Made on
Windows 10 19044, code page 936, `Riched20 10.0.19041`. `re-*.expected.txt` is the text the
control itself reports (EM_GETTEXTEX, raw), with a cell end counted as a paragraph end and the
row marks dropped; a picture is U+FFFC.

| File | Fonts | What it is for |
|---|---|---|
| `re-zh-plain.rtf` | 宋体 | Chinese only; full-width punctuation (the engine writes `\ldblquote`, `\rdblquote`, `\emdash`); an empty paragraph. |
| `re-zh-mixed.rtf` | 宋体, 黑体, 楷体, Arial, Segoe UI Symbol | Chinese and English mixed, font changes inside a paragraph, rare characters, one character outside the BMP (written as two `\uN?` in a font the engine picked). |
| `re-zh-list.rtf` | 宋体, Symbol | A bulleted list and a numbered list, with plain paragraphs around them. |
| `re-zh-picture.rtf` | 宋体, Segoe UI | Two PNG pictures (48 x 32, made by the script), one starting a paragraph and one inside a line. |
| `re-zh-table.rtf` | 宋体 | A 3 x 3 table between two paragraphs. |
| `re-styles.rtf` | 宋体 | Bold, italic, underline, strike-out, subscript, superscript, two text colours, a highlight, three sizes; centred, right, justified; indents, hanging indent; 1.5, double and exact line spacing; space before and after; left, centre and right tab stops. |

## In Word's writing, by hand (`scripts/gen-richedit-fixtures.py`)

Not saved by Word: written after the way Word writes RTF (the long header with `\stshf...`,
`\panose` and `\falt`, `\defchp`, a style sheet, `\rsidtbl`, `\info`; `\pard\plain` and the full
property list on every paragraph; one group per run; blocks after the last paragraph). The
system RichEdit reads all three and reports the same text and the same table structure.

| File | What it is for |
|---|---|
| `hand-word-zh.rtf` | The three font slots: Latin text `\hich\af37\dbch\af13\loch\f37`, East Asian text `\loch\af37\hich\af37\dbch\f13`, high-ANSI text `\loch\af37\dbch\af13\hich\f37` (é, ï in code page 1252). `\uc2` from the header with `\uN\'xx\'xx`; one character outside the code page under a local `\uc1`. |
| `hand-word-unknown.rtf` | One each of what phase 1 keeps without understanding: a style (`\s1`, the style sheet), a field (`\field`, hyperlink), a tracked insertion and deletion (`\revised`, `\deleted`, `\revtbl`), a comment (`\atrfstart` ... `\annotation`), a footnote, a formula (`\mmath`), a bookmark; and Word's blocks after the last paragraph (`\themedata`, `\latentstyles`, `\datastore`). `hand-word-unknown.visible.txt` is the paragraphs' text with every U+FFFC taken out (the field's result is inside its object, so it is not in that text). |
| `hand-word-table-merged.rtf` | A 3 x 3 table: a cell spanning two columns (`\clmgf`, `\clmrg`), a cell spanning two rows (`\clvmgf`, `\clvmrg`), and a nested 1 x 2 table (`\itap2`, `\nestcell`, `\nesttableprops`, `\nestrow`) in the last cell. The expected text has an empty paragraph for each swallowed cell and for the last cell's own paragraph after the nested table. |

## Saved from WordPad's window and by Word

Not here yet (`wp-*.rtf`, `word-*.rtf`): they need the desktop. This section lists each one when
it is added: the program and its version, the fonts, and what the file is for.
