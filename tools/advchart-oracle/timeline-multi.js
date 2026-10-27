/*
Upstream's own answers for fix batch R5-G (spec section 244): SEVERAL
TIMELINES. Every timeline model has its own SliderTimelineView -- its own
layout, ticks, labels, buttons, checkpoint, hover and play timer -- and
every handler of every view dispatches timelineChange / timelinePlayChange,
which timelineAction.ts applies to ecModel.getComponent('timeline'): the
FIRST model. A view's next / prev, its timer's step and its drag's
"no change" test read its OWN model.

The harness, the clock, the records and the guards are timeline.js's; this
runs its MULTI_CASES (TIMELINE_SET=multi), where every state also records
`more`: for each timeline after the first, {model, timer, view} as the
first's are recorded, and a step may name the timeline it aims at (tl).

  node tools/advchart-oracle/timeline-multi.js

writes tests/fixtures/advchart-timeline-multi.json (ORACLE_OUT overrides).
Two generations byte-identical; ends with process.exit().
*/
'use strict';
process.env.TIMELINE_SET = 'multi';
require('./timeline.js');
