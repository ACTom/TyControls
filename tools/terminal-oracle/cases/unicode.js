// Hand-written inputs for unicode-cases.js -- inputs only, no expected values
// (spec 13.2). The answers come from xterm.js when the fixture is generated.
//
// sequences: code points fed one by one to charProperties, the preceding state
//            starting at 0 and then taking each step's result.
// strings:   UTF-16 code units for getStringCellWidth. Units, not a JS string,
//            because JSON cannot carry a lone surrogate.
// extraReps: code points added to the representative set that unicode-cases.js
//            pairs and triples (one per distinct 15-table value is taken anyway).
'use strict';

const sequences = [
  { id: 'combining-a-acute', codepoints: [0x61, 0x301] },          // a mark after a narrow char
  { id: 'combining-two-marks', codepoints: [0x65, 0x301, 0x302] }, // two marks in a row
  { id: 'combining-after-wide', codepoints: [0x4E00, 0x301] },     // stays 2 wide (oldWidth > width)
  { id: 'combining-at-start', codepoints: [0x301] },               // nothing before it
  { id: 'hangul-l-v-t', codepoints: [0x1100, 0x1161, 0x11A8] },    // GB6, GB7
  { id: 'hangul-lv-t', codepoints: [0xAC00, 0x11A8] },             // GB7
  { id: 'hangul-lvt-t', codepoints: [0xAC01, 0x11A8] },            // GB8
  { id: 'hangul-l-l', codepoints: [0x1100, 0x1100] },              // GB6
  { id: 'hangul-t-v-breaks', codepoints: [0x11A8, 0x1161] },       // no join
  { id: 'ri-pair', codepoints: [0x1F1E8, 0x1F1F3] },               // a flag pair is forced 2 wide
  { id: 'ri-three', codepoints: [0x1F1E8, 0x1F1F3, 0x1F1FA] },     // the third starts anew
  { id: 'ri-four', codepoints: [0x1F1E8, 0x1F1F3, 0x1F1FA, 0x1F1F8] }, // two pairs
  { id: 'zwj-family', codepoints: [0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467] }, // GB9 + GB11
  { id: 'zwj-then-letter', codepoints: [0x1F468, 0x200D, 0x41] },  // not ExtPic after the ZWJ
  { id: 'vs16-smile', codepoints: [0x263A, 0xFE0F] },              // VS16 forces wide
  { id: 'vs15-smile', codepoints: [0x263A, 0xFE0E] },              // VS15
  { id: 'vs16-heart', codepoints: [0x2764, 0xFE0F] },
  { id: 'keycap-one', codepoints: [0x31, 0xFE0F, 0x20E3] },        // an emoji sequence starting in ASCII
  { id: 'prepend-arabic-digit', codepoints: [0x600, 0x661] },      // GB9a
  { id: 'prepend-then-ascii', codepoints: [0x600, 0x61] },         // the ASCII fast path's preceding test
  { id: 'spacing-mark', codepoints: [0x915, 0x93F] },              // GB9b
  { id: 'emoji-modifier', codepoints: [0x1F44D, 0x1F3FD] },        // skin tone
  { id: 'ambiguous-letters', codepoints: [0x3B1, 0x2026, 0xFFFD, 0xE000] },
  { id: 'controls', codepoints: [0x0, 0x7, 0x1B, 0x7F, 0x9F] },
  { id: 'surrogate-codepoints', codepoints: [0xD800, 0xDBFF, 0xDC00, 0xDFFF] }, // as code points
  { id: 'soft-hyphen', codepoints: [0xAD, 0x61] },
  { id: 'plane-16', codepoints: [0x10FFFD, 0x10FFFF] },            // the last run
];

const strings = [
  { id: 'empty', units: [] },
  { id: 'ascii', units: [0x61, 0x62, 0x63] },
  { id: 'cjk', units: [0x4E2D, 0x6587] },
  { id: 'e-acute', units: [0x65, 0x301] },
  { id: 'family', units: [0xD83D, 0xDC68, 0x200D, 0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDC67] },
  { id: 'flags-odd', units: [0xD83C, 0xDDE8, 0xD83C, 0xDDF3, 0xD83C, 0xDDFA] },
  { id: 'smile-vs16', units: [0x263A, 0xFE0F] },
  { id: 'smile-vs15', units: [0x263A, 0xFE0E] },
  { id: 'ellipsis', units: [0x2026] },
  { id: 'lone-high-at-end', units: [0x61, 0xD83D] },
  { id: 'high-then-letter', units: [0xD83D, 0x61] },
  { id: 'high-high-low', units: [0xD83D, 0xD83D, 0xDE00] },
  { id: 'lone-low', units: [0xDE00, 0x61] },
  { id: 'low-then-high', units: [0xDE00, 0xD83D] },
  { id: 'two-fffd', units: [0xFFFD, 0xFFFD] },
  { id: 'hangul', units: [0x1100, 0x1161, 0x11A8] },
  { id: 'prepend-ascii', units: [0x600, 0x61] },
];

const extraReps = [0x41, 0x200D, 0xFE0E, 0xFE0F, 0x1F1E6, 0x4E00, 0x1F600, 0x301];

module.exports = { sequences, strings, extraReps };
