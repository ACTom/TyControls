# Third-party notices

TyControls itself is Modified LGPL. This file covers third-party material **bundled in the
source tree**, and what an application that ships it has to carry.

Nothing here asks anything of your **end users**: no on-screen attribution, no link back, no
notice displayed at run time. The obligation is only that the copyright and permission text
below travels with the binary — a copy of this file in your release package satisfies it.

---

## Lucide icons — `assets/lucide/`, `source/tyControls.Icons.Lucide.pas`

Upstream: <https://lucide.dev> · pinned at `lucide-static@1.30.0` (see `assets/lucide/VERSION`).

**You only ship this if you `uses tyControls.Icons.Lucide`.** That unit is optional by
construction: the font lives inside it rather than in an LCL resource, so smart linking drops
the whole thing from an application that never names it — measured at 979 KB with the unit
against 0 bytes without it.

Two licences apply, both reproduced verbatim in `assets/lucide/LICENSE`: **ISC** for Lucide,
and **MIT** for the subset of icons derived from Feather (the file lists them by name).

```
ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

The Feather-derived icons additionally carry:

```
The MIT License (MIT)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The exact list of Feather-derived icon names is in `assets/lucide/LICENSE`; it is kept there
rather than duplicated here so it cannot drift from the upstream file.

---

## xterm.js — `source/tyControls.Unicode.Width.pas`, `source/tyControls.Unicode.Width.Data.inc`, `source/tyControls.Terminal.Parser.pas`, `source/tyControls.Terminal.Buffer.pas`, `source/tyControls.Terminal.Core.pas`, `source/tyControls.Terminal.Core.Services.inc`, `source/tyControls.Terminal.Core.InputHandler.inc`, `source/tyControls.Terminal.Core.WriteQueue.inc`, `source/tyControls.Terminal.Charsets.inc`, `source/tyControls.Terminal.Keyboard.pas`, `source/tyControls.Terminal.Render.pas`, `source/tyControls.Terminal.CustomGlyphs.inc`

Upstream: <https://github.com/xtermjs/xterm.js> · pinned at 6.0.0, commit `c58ea3637f39`.

The width unit and the three terminal units (the core with its three include files) are
ported from xterm.js, and the two other include files are generated from it: the width tables are dumped from the upstream build by
`tools/terminal-oracle/gen-unicode-tables.js`, the character set tables by
`tools/terminal-oracle/gen-terminal-charsets.js`.

The terminal view's parts come from the same code base: the keyboard unit is ported from
`src/common/input/Keyboard.ts`, `src/browser/Clipboard.ts` and the third-level-shift test of
`src/browser/CoreBrowserTerminal.ts`; the renderer resolves colours as
`src/browser/renderer/dom/DomRendererRowFactory.ts` does and draws box-drawing and block
characters as the WebGL addon's `CustomGlyphRasterizer.ts` does, from the definitions
`tools/terminal-oracle/gen-terminal-glyphs.js` dumps out of `CustomGlyphDefinitions.ts` into
the include. Their copyright lines (2014, 2016, 2018, 2021, 2023, and the addon's own
`LICENSE`, 2018) all name the xterm.js authors, whom the lines below already cover.

**You ship this if you `uses tyControls.Unicode.Width` or any `tyControls.Terminal*` unit**
(the terminal units use the width unit). The tables are constants inside the units, so smart
linking drops them from an application that never names them.

The grapheme join rules and the `'15'` table data come through xterm.js's
`addon-unicode-graphemes`, whose `UnicodeProperties.ts` is generated by the unicode-properties
project (<https://github.com/PerBothner/unicode-properties>). That project is MIT too. Its own
notice reads `Copyright 2018` and then the same permission text as below, word for word (only
the line breaks differ); its copyright line is listed with the others, the project named in
parentheses.

```
Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
Copyright (c) 2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
Copyright (c) 2023, The xterm.js authors (https://github.com/xtermjs/xterm.js)
Copyright (c) 2014-2026, The xterm.js authors (https://github.com/xtermjs/xterm.js)
Copyright 2018 (unicode-properties, https://github.com/PerBothner/unicode-properties)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### Test fixtures

`tests/fixtures/terminal-core-escape*.json` carry, base64-encoded, the input bytes of
xterm.js's `test/fixtures/escape_sequence_files/` (MIT, the terms above). Many of those files
first came from the vt100-parser project (<https://github.com/MarkLodato/vt100-parser>), which
is MIT as well, `Copyright (c) 2010 Mark Lodato`. The fixtures are not part of the library —
they live under `tests/` and are not shipped — this note keeps the repository's own credits
complete.

### Unicode data

The `'15'` table derives from the Unicode Character Database, under the Unicode License v3:

```
UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.
```
