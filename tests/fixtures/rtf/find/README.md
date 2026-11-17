# Find: adversarial RTF cases

Review C of Task 11b attacked the raw-byte filter of the finder (`tyControls.RichEdit.Find`) with
these files (its probe `pf`); fix wave W19 keeps them as test data of `TTyRichFindTest`
(`TestTheAdversarialFiles`), which reads `cases.txt`: each file is searched for its needle read
whole, read lazily with the filter and without it, and the three must agree. One line per file
below: the needle (control characters shown as `<0A>`, `<09>`, ...), `m` when the case must match,
and what the file is about. They are kept byte for byte (`.gitattributes`: `tests/fixtures/rtf/**
-text`); none of their words is anyone's.

| File | Needle | Case | What it is |
|---|---|---|---|
| `H1.rtf` | ab | m | a hex LF inside a word |
| `H2.rtf` | hello |  | a hex CR inside a word |
| `H3.rtf` | hello |  | a hex NUL inside a word |
| `H4.rtf` | hello |  | a hex control byte (01) inside a word |
| `H5.rtf` | 中文 |  | a hex LF between a lead and a trail byte |
| `H6.rtf` | hello |  | a raw control byte (01) inside a word |
| `H7.rtf` | hello |  | a raw line break of the source inside a word |
| `H8.rtf` | a<09>b |  | a hex tab |
| `U1.rtf` | ab |  | \|u without a number skips what follows |
| `U2.rtf` | a—b |  | \|uc0 |
| `U3.rtf` | a—b |  | \|uc2 with a hex pair as the fallback |
| `U4.rtf` | a—?b |  | a control word ends the skip |
| `U5.rtf` | a—?b |  | a group start ends the skip |
| `U6.rtf` | a—b |  | a control symbol as the fallback |
| `U7.rtf` | a—xb |  | the optional hyphen as the fallback |
| `U8.rtf` | a送b |  | negative \|u |
| `U9.rtf` | ab |  | \|u65 \|u66 any case |
| `U10.rtf` | a😀b |  | a surrogate pair (not filtered) |
| `U11.rtf` | bc |  | text after a lone high surrogate |
| `U12.rtf` | cd |  | \|u above 65535 next to text |
| `U13.rtf` | a—zb |  | a bin as the fallback |
| `U14.rtf` | a—xb |  | a raw control byte as the fallback |
| `U15.rtf` | a—b |  | a raw control byte as the fallback, then text |
| `C1.rtf` | привет |  | upper case as hex in 1251, searched in lower case |
| `C2.rtf` | Прab中 |  | a font switch in the middle of a word |
| `C3.rtf` | ａｂ |  | full-width Latin in GBK, any case |
| `C4.rtf` | 表示 |  | Shift-JIS trail byte 5C as hex |
| `C5.rtf` | 中 |  | a lead byte at a group's end, the trail after it |
| `C6.rtf` | 文x |  | two lead bytes waiting |
| `C7.rtf` | Привет | m | the font table given again in the body with another charset |
| `C8.rtf` | При | m | \|ansicpg given again in the body |
| `C9.rtf` | 中 |  | a font added by a second table in the body |
| `C10.rtf` |  |  | Symbol charset |
| `C11.rtf` | café |  | \|mac |
| `C12.rtf` | пр |  | a font whose number is not in the table |
| `S1.rtf` | cooperate |  | the optional hyphen inside a word |
| `S2.rtf` | a b |  | the non-breaking space |
| `S3.rtf` | a<0B>b |  | a line break inside a paragraph |
| `S4.rtf` | “a”–‘b’• |  | quotes and dashes |
| `S5.rtf` | hello |  | a word split by a line break of the source after a control word |
| `S6.rtf` | hello world |  | a word split by an unknown group |
| `S7.rtf` | ab |  | a bin outside a picture |
| `S8.rtf` | axxb |  | hidden text |
| `S9.rtf` | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbc |  | a needle longer than 64 |
| `S10.rtf` | item |  | a list marker is no text of the paragraph |
| `S11.rtf` | ab |  | a star symbol in the middle |
| `S12.rtf` | a\{b} |  | an escaped backslash and braces |
| `F1.rtf` | manual |  | the display text of a hyperlink |
| `F2.rtf` | chapter |  | a word with a bookmark inside |
