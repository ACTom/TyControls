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

## Saved by WordPad and by Word

Not here yet; this section lists each one when it is added: the program and its version, the
fonts, and what the file is for.
