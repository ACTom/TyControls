# Find: adversarial RTF cases

Small RTF files that attack the raw-byte filter of the finder (`tyControls.RichEdit.Find`): the
filter looks for a needle in a paragraph's unparsed bytes and must never say "cannot match"
where the reader would read the needle. `TTyRichFindTest.TestTheAdversarialFiles` reads
`cases.txt` - per line, tab-separated: the file, the needle as hex of its UTF-8, `m` when the
case must match, the places the needle is found (`-`: none) and what the file is about. Each
file is searched read whole, read lazily with the filter and without it: all three must give
those places. A file may serve two lines (two needles). They are kept byte for byte
(`.gitattributes`: `tests/fixtures/rtf/** -text`); none of their words is anyone's.

| File | Needle | Case | Found at | What it is |
|---|---|---|---|---|
| `H1.rtf` | ab | m | 7 | a hex LF inside a word |
| `H2.rtf` | hello |  | 7 | a hex CR inside a word |
| `H3.rtf` | hello |  | 7 | a hex NUL inside a word |
| `H4.rtf` | hello |  | 7 | a hex control byte (01) inside a word |
| `H5.rtf` | 中文 |  | 7 | a hex LF between a lead and a trail byte |
| `H6.rtf` | hello |  | 7 | a raw control byte (01) inside a word |
| `H7.rtf` | hello |  | 7 | a raw line break of the source inside a word |
| `H8.rtf` | a<09>b |  | 7 | a hex tab |
| `U1.rtf` | ab |  | 7 | \|u without a number skips what follows |
| `U2.rtf` | a—b |  | 7 | \|uc0 |
| `U3.rtf` | a—b |  | 7 | \|uc2 with a hex pair as the fallback |
| `U4.rtf` | a—?b |  | 7 | a control word ends the skip |
| `U5.rtf` | a—?b |  | 7 | a group start ends the skip |
| `U6.rtf` | a—b |  | 7 | a control symbol as the fallback |
| `U7.rtf` | a—xb |  | 7 | the optional hyphen as the fallback |
| `U8.rtf` | a送b |  | 7 | negative \|u |
| `U9.rtf` | ab |  | 7 | \|u65 \|u66 any case |
| `U10.rtf` | a😀b |  | 7 | a surrogate pair (not filtered) |
| `U11.rtf` | bc |  | 9 | text after a lone high surrogate |
| `U12.rtf` | cd |  | 10 | \|u above 65535 next to text |
| `U13.rtf` | a—zb |  | - | a bin as the fallback |
| `U14.rtf` | a—xb |  | 7 | a raw control byte as the fallback |
| `U15.rtf` | a—b |  | 7 | a raw control byte as the fallback, then text |
| `C1.rtf` | привет |  | 7 | upper case as hex in 1251, searched in lower case |
| `C2.rtf` | Прab中 |  | 7 | a font switch in the middle of a word |
| `C3.rtf` | ａｂ |  | 7 | full-width Latin in GBK, any case |
| `C4.rtf` | 表示 |  | 7 | Shift-JIS trail byte 5C as hex |
| `C5.rtf` | 中 |  | 7 | a lead byte at a group's end, the trail after it |
| `C6.rtf` | 文x |  | - | two lead bytes waiting |
| `C7.rtf` | Привет | m | 0 | the font table given again in the body with another charset |
| `C8.rtf` | При | m | 0 | \|ansicpg given again in the body |
| `C9.rtf` | 中 |  | 4 | a font added by a second table in the body |
| `C10.rtf` |  |  | 7 | Symbol charset |
| `C11.rtf` | café |  | 7 | \|mac |
| `C12.rtf` | пр |  | 7 | a font whose number is not in the table |
| `S1.rtf` | cooperate |  | 7 | the optional hyphen inside a word |
| `S2.rtf` | a b |  | 7 | the non-breaking space |
| `S3.rtf` | a<0B>b |  | 7 | a line break inside a paragraph |
| `S4.rtf` | “a”–‘b’• |  | 7 | quotes and dashes |
| `S5.rtf` | hello |  | 7 | a word split by a line break of the source after a control word |
| `S6.rtf` | hello world |  | 7 | a word split by an unknown group |
| `S7.rtf` | ab |  | 7 | a bin outside a picture |
| `S8.rtf` | axxb |  | 7 | hidden text |
| `S9.rtf` | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbc |  | 7 | a needle longer than 64 |
| `S10.rtf` | item |  | 7 | a list marker is no text of the paragraph |
| `S11.rtf` | ab |  | 7 | a star symbol in the middle |
| `S12.rtf` | a\{b} |  | 7 | an escaped backslash and braces |
| `F1.rtf` | manual |  | - | the display text of a hyperlink |
| `F2.rtf` | chapter |  | - | a word with a bookmark inside |
| `V1.rtf` | 😀 |  | 8 | a surrogate pair split by a skipped pntext group holding a \|u |
| `V2.rtf` | 😀 |  | - | a surrogate pair split by an upr whose ud holds a \|u |
| `V3.rtf` | 😀 |  | 8 | a surrogate pair split by a lone fldinst holding a \|u |
| `V4.rtf` | 😀 |  | 8 | a surrogate pair split by an info group holding a \|u |
| `V5.rtf` | 😀 |  | 8 | a surrogate pair split by a listtext group without a \|u |
| `V6.rtf` | 😀 |  | 8 | a surrogate pair split by a listtext group holding another high half |
| `V6.rtf` | 🈀 |  | - | the same file: the pair the other high half would make |
| `V7.rtf` | a😀b |  | 7 | a pair split by listtext, the needle with the letters around it |
| `V8.rtf` | 😀 |  | - | a high half before the paragraph end, listtext, a low half |
| `V9.rtf` | 😀 |  | 8 | a pair split by listtext holding a picture |
| `V10.rtf` | ffd8 |  | - | a picture inside listtext is no text |
| `V11.rtf` | ffd8 |  | - | a picture inside a field result is no text |
| `V12.rtf` | ffd8 |  | - | a picture inside upr is no text |
| `V13.rtf` | 😀<0D><0A>b |  | 8 | a needle with a paragraph end and a pair split by listtext |
| `V14.rtf` | 中 |  | 7 | a lead byte, listtext with bytes, the trail byte |
| `V15.rtf` | a—b |  | - | a \|uc skip across a listtext group |
| `V15.rtf` | a—?b |  | 7 | the same file: the fallback is text after the group |
| `V16.rtf` | 😀 |  | - | a pair split by a nonshppict group holding a \|u |
| `V17.rtf` | 😀 |  | - | a pair split by a header group holding a \|u |
| `V18.rtf` | 😀 |  | - | a pair split by a footnote holding a \|u |
| `V19.rtf` | 😀 |  | 8 | a pair split by a stylesheet holding a \|u |
| `V20.rtf` | 😀 |  | 8 | a pair split by a pn group with pntxtb holding a \|u |
| `B13.rtf` | ffd8 |  | 8 | a picture below 4100 groups: the reader reads its hex as text |
| `B13b.rtf` | ffd8 |  | 8 | text below 4100 groups |
