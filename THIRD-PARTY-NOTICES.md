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

## Apache ECharts example gallery

`examples/advchart/gallery/*.json` are the option trees of the official Apache ECharts
example gallery, converted from TypeScript to JSON by `tools/advchart-gallery/harvest.js`.
They are DATA, not code: each file is one chart configuration, and the conversion changes
only the notation. Callbacks cannot survive the trip to JSON and are dropped; the index
records how many each example lost.

They are used as a conformance corpus -- the point of the demo is to show what
`TTyAdvanceChart` does with an option written for ECharts, unmodified.

Source: https://github.com/apache/echarts-examples
Copyright The Apache Software Foundation, licensed under the Apache License 2.0.

```
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
