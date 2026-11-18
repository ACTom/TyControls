# Find: adversarial RTF cases

Small RTF files with a needle and the places it is found. Each is a form in which a search
that judged a paragraph by its bytes in the file once lost a hit - what those bytes read as
was the reader's to say (a code page, a group left open, a byte still waiting for its
second) - or a neighbour of such a form. The finder (`tyControls.RichEdit.Find`) reads every
paragraph through the reader now, so the cases pin what the reader makes of each file, read
whole and read lazily alike. `TTyRichFindTest.TestTheAdversarialFiles` reads `cases.txt` - per
line, tab-separated: the file, the needle as hex of its UTF-8, the options (`m` match case,
`w` whole word, `-` none), the places the needle is found (`-`: none) and what the file is
about. Each file is searched read whole and read lazily: both must give those places. A file
may serve two lines (two needles). The `D` files are of another kind: the default font named
again in the body (`\deff`), where the reader's index and its parse once took the change at
different places and reading the file raised. They are kept byte for byte (`.gitattributes`:
`tests/fixtures/rtf/** -text`); none of their words is anyone's.

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
| `U10.rtf` | a😀b |  | 7 | a surrogate pair |
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
| `R1.rtf` | axyz |  | 7 | text directly in upr before its ud |
| `R2.rtf` | ax |  | 7 | the same, one character each |
| `R3.rtf` | xyzc |  | 8 | text directly in upr after its ud |
| `R4.rtf` | u2more |  | 10 | a paragraph that begins inside ud, then upr's own text |
| `R5.rtf` | 😀 |  | 8 | a pair: the high half in ud, a \|u directly in upr, the low half after |
| `R6.rtf` | 中 |  | 8 | a lead byte in ud, a byte directly in upr, the trail after |
| `R7.rtf` | ax |  | 7 | a control word that is a character directly in upr |
| `R8.rtf` | ax |  | 7 | a hex byte directly in upr |
| `R9.rtf` | axc |  | 7 | the ansi half as a group, as Word writes it |
| `R10.rtf` | axc |  | 7 | a line break of the file directly in upr |
| `R11.rtf` | axyz<0D><0A>c |  | 7 | a needle with a paragraph end, text directly in upr |
| `R12.rtf` | axyzd |  | 7 | upr nested in ud nested in upr |
| `R13.rtf` | ax |  | - | upr in a field result (an object: nothing to find) |
| `R14.rtf` | axyz |  | 7 | upr, any case |
| `R15.rtf` | axyz | w | 8 | upr, whole word |
| `T1.rtf` | yc |  | 11 | a row end inside ud right after the last cell: the next paragraph begins inside ud |
| `T2.rtf` | yc |  | 11 | the same, any case |
| `T3.rtf` | y | w | 11 | the same, whole word |
| `T4.rtf` | yc |  | 9 | the same, a row of one cell |
| `T5.rtf` | yc<0D><0A>d |  | 11 | the same, a needle with a paragraph end |
| `T6.rtf` | yc |  | 13 | text before the row end: the row end ends a paragraph inside ud |
| `T7.rtf` | yzc |  | 11 | the row end in ud, then upr's own text and a second ud |
| `T8.rtf` | yJc |  | 11 | a row end inside an ordinary group after the last cell |
| `L1.rtf` | b? |  | 8 | a lead byte left waiting in a field's result: its ? comes out before the field |
| `L2.rtf` | b? |  | 8 | the same, the file cut short inside the result |
| `L3.rtf` | b? |  | 8 | the same, inside a group of the result |
| `L4.rtf` | b? |  | 8 | the same, the lead byte raw |
| `L5.rtf` | b? |  | 8 | two fields, a lead byte left in each |
| `L6.rtf` | b? |  | 8 | the same, a paragraph after |
| `L7.rtf` | b? |  | 8 | the same, in upr's ud inside the result |
| `L8.rtf` | b? |  | - | the lead byte before the field, its trail in the result: no ? at all |
| `L9.rtf` | b? |  | - | a character after the lead byte in the result: the ? is the result's |
| `L10.rtf` | b? |  | - | a lead byte left in a list's marker: none comes out |
| `W1.rtf` | b? |  | 1 | a lead byte left waiting in a field's result, text of the field itself before and behind the result |
| `W2.rtf` | b? |  | 1 | the same, spaces between the field's groups |
| `W3.rtf` | b? |  | 1 | the same, a hex byte behind the result |
| `W4.rtf` | b? |  | 1 | the same, a character word behind the result |
| `W5.rtf` | b? |  | 1 | the same, a \|u behind the result |
| `W6.rtf` | b? |  | 1 | the same, a control symbol behind the result |
| `W7.rtf` | b? |  | 1 | the same, in an inner field of a result that has text |
| `W8.rtf` | b? |  | 1 | the same, the file cut short behind the text |
| `W9.rtf` | b? |  | 1 | the same, the lead byte raw |
| `W10.rtf` | b? |  | 8 | the same, in a later paragraph |
| `W10.rtf` | r<0A>ab? |  | 5 | the same, in a later paragraph |
| `W11.rtf` | b? |  | 1 | the same, a Shift-JIS font |
| `W12.rtf` | b? |  | 1 | the same, a character word before the result |
| `W13.rtf` | b? |  | 1 | the same, in a table cell |
| `X1.rtf` | b? |  | 1 | a lead byte left waiting in a result, nothing before the result |
| `X2.rtf` | b? |  | 1 | the same, nothing behind the result |
| `X3.rtf` | b? |  | 1 | the same, a line break of the source before and behind the result |
| `X4.rtf` | b? |  | 1 | the same, a formatting word before and behind the result |
| `X5.rtf` | b? |  | - | a single-byte font: the byte is a character of the result, no ? comes out |
| `X5.rtf` | ab | m | 0 | a single-byte font: the byte is a character of the result, no ? comes out |
| `X6.rtf` | b? |  | - | a whole pair in the result: no ? comes out |
| `X6.rtf` | ab | m | 0 | a whole pair in the result: no ? comes out |
| `X7.rtf` | b? |  | 1 | a lead byte left waiting in a result, an instruction before it and text behind |
| `D1.rtf` | •ab |  | 7 | the default font named again after text: what has no font of its own is in the new one from there on |
| `D1.rtf` | zz | m | 11 | the default font named again after text: what has no font of its own is in the new one from there on |
| `D2.rtf` | t? |  | 7 | the default font named again in a field's result, a lead byte of the new one behind it, the file cut short there |
| `D3.rtf` | t? |  | 7 | the same, the file whole |
| `D3.rtf` | zz | m | 12 | the same, the file whole |
| `D4.rtf` | •ab |  | 7 | the default font named in the header alone |
