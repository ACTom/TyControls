unit tyControls.AdvanceChart.Theme;

{ The chart's own tycss (its --advchart-* tokens and its TyAdvChart* rules), compiled into the
  binary and registered in this unit's initialization as the add-on "advchart", so every
  style model's base layer carries it after light.tycss. GENERATED from themes/advchart.tycss
  by scripts/gen-advchart-theme.ps1 - do NOT edit by hand; edit advchart.tycss and re-run the
  generator. Sync-tested byte-identical to advchart.tycss (test.advchart.theme). }

{$mode objfpc}{$H+}

interface

function TyAdvChartCss: string;

implementation

uses
  tyControls.Css.AddOns;

function TyAdvChartCss: string;
begin
  Result :=
    '/* TyAdvanceChart -- advchart.tycss: the chart''s own tokens and rules.' + LineEnding +
    '' + LineEnding +
    '   An add-on of the core''s base layer, not a theme of its own. The generated unit' + LineEnding +
    '   tyControls.AdvanceChart.Theme compiles this file in (scripts/gen-advchart-theme.ps1; never' + LineEnding +
    '   edit that unit by hand) and registers it in its initialization as the add-on "advchart"' + LineEnding +
    '   (TyRegisterAddOnCss). Every style model then loads it into its base layer after the whole' + LineEnding +
    '   of light.tycss and before the per-mode contrast snippet, so every theme, built-in or not,' + LineEnding +
    '   inherits these keys and tokens where it says nothing of its own, exactly as it did when' + LineEnding +
    '   they lived in light.tycss. A skin restyles them the way it restyles any other key.' + LineEnding +
    '' + LineEnding +
    '   Everything here is said in light.tycss''s vocabulary (--accent, --surface, --on-surface,' + LineEnding +
    '   --border, --muted, the type scale ...), so a skin that restyles those gets a matching' + LineEnding +
    '   chart for nothing. */' + LineEnding +
    '' + LineEnding +
    ':root {' + LineEnding +
    '  /* -- size tokens: the chart''s geometry (density phase 3) --' + LineEnding +
    '     classic value == the chart''s Pascal constant today; a density pack may override' + LineEnding +
    '     these names. */' + LineEnding +
    '  --advchart-label-margin: 8px;' + LineEnding +
    '  --advchart-minor-tick-length: 3px;' + LineEnding +
    '  --advchart-name-gap: 15px;' + LineEnding +
    '  --advchart-single-tick-length: 6px;' + LineEnding +
    '  --advchart-tick-length: 5px;' + LineEnding +
    '  --advchart-axispointer-margin: 3px;' + LineEnding +
    '  --advchart-tooltip-gap: 20px;' + LineEnding +
    '  --advchart-tooltip-gutter: 20px;' + LineEnding +
    '  --advchart-tooltip-marker: 10px;' + LineEnding +
    '  --advchart-tooltip-marker-gap: 6px;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* The chart control itself: the same frame as a panel''s (light.tycss''s TyPanel group). */' + LineEnding +
    'TyAdvChart {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: var(--pad-container);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* AdvChart: the series palette, DERIVED.' + LineEnding +
    '' + LineEnding +
    '   Item 18 asks for a derived ramp and this is what that buys: a skin that' + LineEnding +
    '   restyles --accent gets a matching chart for nothing, and one that restyles' + LineEnding +
    '   neither still gets a legible one. The eight TyChartSeries* keys in light.tycss are' + LineEnding +
    '   the OLD chart''s, and they are eight literals -- exactly what makes a chart look' + LineEnding +
    '   pasted on top of a theme instead of drawn in it.' + LineEnding +
    '' + LineEnding +
    '   The ramp walks away from --accent in both directions rather than around a' + LineEnding +
    '   hue circle, because a hue rotation has no idea what the theme''s accent is for' + LineEnding +
    '   and lands on colours a brand would not have chosen. Slot 1 IS the accent, so' + LineEnding +
    '   a single-series chart is drawn in the theme''s own colour.' + LineEnding +
    '' + LineEnding +
    '   Eight slots, cycled by (index mod 8), matching the old chart so nothing has' + LineEnding +
    '   to learn a second rule. */' + LineEnding +
    'TyAdvChartSeries1 { background: var(--accent); }' + LineEnding +
    'TyAdvChartSeries2 { background: mix(var(--accent), var(--on-surface), 35%); }' + LineEnding +
    'TyAdvChartSeries3 { background: lighten(var(--accent), 22%); }' + LineEnding +
    'TyAdvChartSeries4 { background: darken(var(--accent), 18%); }' + LineEnding +
    'TyAdvChartSeries5 { background: mix(var(--accent), var(--surface), 40%); }' + LineEnding +
    'TyAdvChartSeries6 { background: mix(var(--accent), var(--on-surface), 65%); }' + LineEnding +
    'TyAdvChartSeries7 { background: lighten(var(--accent), 38%); }' + LineEnding +
    'TyAdvChartSeries8 { background: darken(var(--accent), 34%); }' + LineEnding +
    'TyAdvChartSeries9 { background: mix(var(--accent), var(--on-surface), 15%); }' + LineEnding +
    '' + LineEnding +
    '/* AdvChart: the axis domain. Eight keys and four metrics, and the COUNT is part' + LineEnding +
    '   of the design -- twelve things can be checked by eye across seventeen themes' + LineEnding +
    '   and sixty-four cannot, so this is the smallest set that still lets a skin' + LineEnding +
    '   restyle an axis without touching the control.' + LineEnding +
    '' + LineEnding +
    '   Every colour DERIVES from a semantic token the theme already defines. A skin' + LineEnding +
    '   that restyled --border or --on-surface gets a matching axis for nothing, and' + LineEnding +
    '   one that restyled neither still gets a legible one. Not a literal anywhere:' + LineEnding +
    '   a hardcoded grey is exactly what makes a chart look pasted on top of a dark' + LineEnding +
    '   theme rather than drawn in it.' + LineEnding +
    '' + LineEnding +
    '   These are NEW keys, so every existing skin inherits them from this base layer' + LineEnding +
    '   untouched -- which is the only reason a change this wide is safe to make in' + LineEnding +
    '   one pass. A skin that later writes any rule for one of them replaces the' + LineEnding +
    '   whole key, variants included; that is this library''s rule and it is why the' + LineEnding +
    '   set is small enough to re-check. */' + LineEnding +
    'TyAdvChartAxisLine  { border-color: var(--border); border-width: 1px; }' + LineEnding +
    'TyAdvChartAxisTick  { border-color: var(--border); border-width: 1px; }' + LineEnding +
    '/* [R5-G] a shown grid''s border (grid.show): upstream''s tokens.color.neutral30 */' + LineEnding +
    'TyAdvChartGridBorder { border-color: #b7b9be; border-width: 1px; }' + LineEnding +
    '/* Muted, not full ink: an axis label is a reference, not content. --muted is' + LineEnding +
    '   already alpha over --on-surface, so it follows a dark theme by itself. */' + LineEnding +
    'TyAdvChartAxisLabel { color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    'TyAdvChartAxisName  { color: var(--on-surface); font-size: var(--font-size-base); }' + LineEnding +
    '/* The heavier label a TIME axis gives its coarse ticks -- the `Mar` in a run' + LineEnding +
    '   of day numbers. Upstream carries it as a rich-text style on the time axis''' + LineEnding +
    '   own defaults; here it is a key of its own so a skin can make the level' + LineEnding +
    '   marker darker, or larger, or nothing special at all. */' + LineEnding +
    'TyAdvChartAxisLabelPrimary { color: var(--muted); font-size: var(--font-size-base);' + LineEnding +
    '                             font-weight: var(--font-weight-bold); }' + LineEnding +
    '/* Alpha over --border, NEVER over --surface. On an image theme a translucent' + LineEnding +
    '   surface reads as a bright halo instead of a faint line -- this library has' + LineEnding +
    '   shipped that bug once already. */' + LineEnding +
    'TyAdvChartSplitLine { border-color: alpha(var(--border), 0.6); border-width: 1px; }' + LineEnding +
    '/* The alternating band. Alpha over the ink rather than a grey, so it darkens a' + LineEnding +
    '   light theme and lightens a dark one from the same declaration. */' + LineEnding +
    'TyAdvChartSplitArea { background: alpha(var(--on-surface), 0.04); }' + LineEnding +
    'TyAdvChartMinorTick { border-color: alpha(var(--border), 0.4); border-width: 1px; }' + LineEnding +
    'TyAdvChartMinorSplitLine { border-color: alpha(var(--border), 0.35); border-width: 1px; }' + LineEnding +
    '/* The ring a pie draws when it has no data at all. Upstream hard-codes' + LineEnding +
    '   lightgray; alpha over the ink instead, so it stays faint on either mode. */' + LineEnding +
    'TyAdvChartEmptyCircle { background: alpha(var(--on-surface), 0.10); }' + LineEnding +
    '/* showBackground: the strip behind a bar, the height of the plot. Upstream' + LineEnding +
    '   writes rgba(180,180,180,0.2) into the series default, which is a pale grey' + LineEnding +
    '   band across a dark skin; alpha over the ink darkens one and lightens the' + LineEnding +
    '   other from the same declaration. */' + LineEnding +
    'TyAdvChartBarBackground { background: alpha(var(--on-surface), 0.10); }' + LineEnding +
    '/* A TREE''S NODES AND EDGES. Upstream names the colours in the series''' + LineEnding +
    '   defaults -- lightsteelblue for a node, a light grey for an edge -- and a' + LineEnding +
    '   tree takes no palette slot; here they are keys, so a skin gives its trees' + LineEnding +
    '   its own accent and its own line ink. */' + LineEnding +
    'TyAdvChartTreeNode { background: alpha(var(--accent), 0.55); }' + LineEnding +
    'TyAdvChartTreeEdge { border-color: var(--border); border-width: 1px; }' + LineEnding +
    '/* A TREEMAP''S LABELS AND ITS BREADCRUMB. Upstream writes the label white --' + LineEnding +
    '   a fixed ink over palette fills, which do not change with the mode, so' + LineEnding +
    '   neither does this -- and draws the breadcrumb as a pale chip with' + LineEnding +
    '   secondary text: here the chip is alpha over the ink and the text muted,' + LineEnding +
    '   so a dark skin gets a dark chip. */' + LineEnding +
    'TyAdvChartTreemapLabel { color: #FFFFFF; font-size: var(--font-size-base); }' + LineEnding +
    'TyAdvChartBreadcrumb { background: alpha(var(--on-surface), 0.08); color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    '/* A hovered breadcrumb item. Upstream lifts it to the page''s own ground' + LineEnding +
    '   (tokens.color.background); the words keep their colour. */' + LineEnding +
    'TyAdvChartBreadcrumb:hover { background: var(--surface); color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    '/* A SANKEY''S LINKS. Upstream fills them a mid grey at 0.2 opacity; here the' + LineEnding +
    '   grey is the ink''s own muted tone, so a dark skin''s links stay grey on' + LineEnding +
    '   its ground. */' + LineEnding +
    'TyAdvChartSankeyLink { background: var(--muted); }' + LineEnding +
    '/* The chart''s own title and subtitle. Upstream draws them at 18/bold and' + LineEnding +
    '   12/regular; the sizes come from the type scale here so a dense skin gets a' + LineEnding +
    '   proportionate title instead of an 18px one on 11px axis labels. */' + LineEnding +
    '/* [R5-G] border-color: a title box''s default pen (borderWidth above 0) -- upstream''s tokens.color.primary */' + LineEnding +
    'TyAdvChartTitle { color: var(--on-surface); font-size: var(--font-size-title); font-weight: 700; border-color: #3c3c41; }' + LineEnding +
    'TyAdvChartSubtitle { color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    '/* A label OUTSIDE its mark: the theme''s own ink, not anything derived from the' + LineEnding +
    '   thing it names. Upstream picks #333 or #ccc by mode; this is the same idea' + LineEnding +
    '   said in the theme''s vocabulary. */' + LineEnding +
    'TyAdvChartLabel { color: var(--on-surface); font-size: var(--font-size-base); }' + LineEnding +
    '/* A label INSIDE its mark is a three-band table, not a light/dark pair, and the' + LineEnding +
    '   order reads backwards until you see why: on a mid-dark fill you want maximum' + LineEnding +
    '   contrast, but on a nearly black one the brightest ink glares and the dimmer' + LineEnding +
    '   one is easier to read. Band 1 is therefore LIGHTER than band 2.' + LineEnding +
    '     band 0 -- a light mark, so dark ink' + LineEnding +
    '     band 1 -- a mid mark, so the brightest ink' + LineEnding +
    '     band 2 -- a dark mark, so a softer light ink' + LineEnding +
    '   FIXED VALUES, NOT THE SURFACE PAIR: the band is chosen by the MARK''s fill,' + LineEnding +
    '   which does not change with the mode -- so the ink must not either, or a' + LineEnding +
    '   dark skin puts light ink on a light bar. Upstream''s #333, #eee, #ccc. */' + LineEnding +
    'TyAdvChartLabelOnLight { color: #333333; }' + LineEnding +
    'TyAdvChartLabelOnMid   { color: #EEEEEE; }' + LineEnding +
    'TyAdvChartLabelOnDark  { color: #CCCCCC; }' + LineEnding +
    '/* The legend. Upstream inks the words with tokens.color.secondary and greys a' + LineEnding +
    '   deselected item with tokens.color.disabled. This vocabulary has no disabled' + LineEnding +
    '   INK token -- only a disabled OPACITY -- so a switched-off item is the chart''s' + LineEnding +
    '   own ink faded far enough to read as off on either mode. The frame is drawn' + LineEnding +
    '   only when the option asks for one, so the last two are dormant on almost' + LineEnding +
    '   every chart. */' + LineEnding +
    'TyAdvChartLegend { color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    'TyAdvChartLegendInactive { color: alpha(var(--on-surface), 0.25); }' + LineEnding +
    'TyAdvChartLegendBorder { border-color: var(--border); border-width: 1px; }' + LineEnding +
    'TyAdvChartLegendBackground { background: var(--surface); }' + LineEnding +
    '/* The legend''s selector buttons (All / Inv) and the scrolling legend''s pager.' + LineEnding +
    '   Upstream draws a button as tertiary ink in a pale rounded frame that turns' + LineEnding +
    '   the lighter quaternary ink under the pointer, the page arrows in its accent' + LineEnding +
    '   with a pale accent for one that cannot go further, and the page count in' + LineEnding +
    '   the tertiary ink. Here the ink is the chart''s muted one (fainter when' + LineEnding +
    '   hovered), the frame the border, and the arrows the skin''s own accent. */' + LineEnding +
    'TyAdvChartLegendSelector { color: var(--muted); border-color: var(--border); font-size: var(--font-size-base); }' + LineEnding +
    'TyAdvChartLegendSelector:hover { color: alpha(var(--on-surface), 0.35); border-color: var(--border); font-size: var(--font-size-base); }' + LineEnding +
    'TyAdvChartLegendPageIcon { color: var(--accent); }' + LineEnding +
    'TyAdvChartLegendPageIconInactive { color: alpha(var(--accent), 0.25); }' + LineEnding +
    'TyAdvChartLegendPageText { color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    '/* A visualMap''s own picture. Upstream inks its texts with tokens.color.' + LineEnding +
    '   secondary, the bar''s inactive stretch and the frame with a pale grey, the' + LineEnding +
    '   handles'' rims white and the box transparent. The inactive stretch is the' + LineEnding +
    '   chart''s own ink faded, like a switched-off legend item; the rim is the' + LineEnding +
    '   surface, so a handle reads as cut out of whatever it sits on. The frame is' + LineEnding +
    '   drawn only when the option gives it a width. */' + LineEnding +
    'TyAdvChartVisualMap { color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    'TyAdvChartVisualMapInactive { color: alpha(var(--on-surface), 0.2); }' + LineEnding +
    'TyAdvChartVisualMapBorder { border-color: var(--border); }' + LineEnding +
    'TyAdvChartVisualMapBackground { background: transparent; }' + LineEnding +
    'TyAdvChartVisualMapHandle { border-color: var(--surface); }' + LineEnding +
    '/* A slider dataZoom. Upstream tints the whole component from its accent: a' + LineEnding +
    '   pale frame, the window filled with the accent at a fifth, handles white' + LineEnding +
    '   with a pale rim, the brush''s move bar the accent at half with a white' + LineEnding +
    '   grip, and the data shadow grey outside the window and bluer inside it.' + LineEnding +
    '   Here the accent is the skin''s own, the grey is the ink faded, and white' + LineEnding +
    '   is the surface. The labels beside the handles take the muted ink. */' + LineEnding +
    'TyAdvChartDataZoom { color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    'TyAdvChartDataZoomBorder { border-color: var(--border); }' + LineEnding +
    'TyAdvChartDataZoomBackground { background: transparent; }' + LineEnding +
    'TyAdvChartDataZoomFiller { background: alpha(var(--accent), 0.2); }' + LineEnding +
    'TyAdvChartDataZoomHandle { background: var(--surface); border-color: alpha(var(--accent), 0.35); }' + LineEnding +
    'TyAdvChartDataZoomMoveHandle { background: alpha(var(--accent), 0.5); color: var(--surface); }' + LineEnding +
    'TyAdvChartDataZoomShadow { background: alpha(var(--on-surface), 0.06); border-color: alpha(var(--on-surface), 0.3); }' + LineEnding +
    'TyAdvChartDataZoomShadowSelected { background: alpha(var(--accent), 0.12); border-color: alpha(var(--accent), 0.55); }' + LineEnding +
    '/* Under the pointer (or while a handle is dragged) a handle''s rim darkens' + LineEnding +
    '   and the move bar firms up; a brush across the body is the accent faded. */' + LineEnding +
    'TyAdvChartDataZoomHandle:hover { background: var(--surface); border-color: alpha(var(--accent), 0.55); }' + LineEnding +
    'TyAdvChartDataZoomMoveHandle:hover { background: alpha(var(--accent), 0.8); color: var(--surface); }' + LineEnding +
    'TyAdvChartDataZoomBrush { background: alpha(var(--accent), 0.3); }' + LineEnding +
    '/* The toolbox. Upstream draws its icons as hairline outlines in the accent,' + LineEnding +
    '   a deeper accent under the pointer, and the title that appears below the' + LineEnding +
    '   icon takes that same deeper ink; the bar itself has no ground and no' + LineEnding +
    '   frame unless the option asks. The rectangle a zoom drag sweeps out is the' + LineEnding +
    '   accent faded right down. */' + LineEnding +
    'TyAdvChartToolbox { border-color: var(--accent); font-size: var(--font-size-base); }' + LineEnding +
    'TyAdvChartToolbox:hover { border-color: darken(var(--accent), 25%); }' + LineEnding +
    'TyAdvChartToolboxBackground { background: transparent; }' + LineEnding +
    'TyAdvChartToolboxBorder { border-color: var(--border); }' + LineEnding +
    'TyAdvChartToolboxBrush { background: alpha(var(--accent), 0.15); }' + LineEnding +
    '/* The brush component''s covers. Upstream lays a pale tint over what it' + LineEnding +
    '   selects and rims it in a light grey; here the ink faded right down and' + LineEnding +
    '   the skin''s own border colour. */' + LineEnding +
    'TyAdvChartBrush { background: alpha(var(--on-surface), 0.06); border-color: var(--border); }' + LineEnding +
    '/* The timeline. Upstream builds the whole slider from its accent in steps:' + LineEnding +
    '   the axis line palest, the passed part of it a little deeper, the ticks' + LineEnding +
    '   deeper again and a passed tick deeper still, the checkpoint and the' + LineEnding +
    '   buttons the accent itself; under the pointer a tick, a button and a label' + LineEnding +
    '   take a darker accent. The labels are the muted ink; an empty symbol''s' + LineEnding +
    '   inside is the surface. */' + LineEnding +
    'TyAdvChartTimeline { border-color: alpha(var(--accent), 0.2); background: var(--surface); }' + LineEnding +
    'TyAdvChartTimelineProgress { border-color: alpha(var(--accent), 0.45); background: alpha(var(--accent), 0.65); }' + LineEnding +
    'TyAdvChartTimelineItem { background: alpha(var(--accent), 0.3); }' + LineEnding +
    'TyAdvChartTimelineItem:hover { background: darken(var(--accent), 10%); border-color: darken(var(--accent), 10%); }' + LineEnding +
    'TyAdvChartTimelineCheckpoint { background: var(--accent); border-color: var(--accent); }' + LineEnding +
    'TyAdvChartTimelineControl { background: var(--accent); border-color: var(--accent); }' + LineEnding +
    'TyAdvChartTimelineControl:hover { background: darken(var(--accent), 25%); border-color: darken(var(--accent), 25%); }' + LineEnding +
    'TyAdvChartTimelineLabel { color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    'TyAdvChartTimelineLabel:hover { color: darken(var(--accent), 10%); }' + LineEnding +
    '/* What a brush leaves out. Upstream greys the items outside every cover in a' + LineEnding +
    '   light neutral; here the skin''s border colour, which is that neutral. */' + LineEnding +
    'TyAdvChartBrushOut { color: var(--border); }' + LineEnding +
    '/* A parallel axis'' area select: the band a drag along the axis leaves.' + LineEnding +
    '   Upstream fills and rims it in one light blue at 30% opacity (the opacity' + LineEnding +
    '   is the chart''s, not the skin''s); here the accent halfway to the surface. */' + LineEnding +
    'TyAdvChartParallelSelect { background: mix(var(--accent), var(--surface), 50%); border-color: mix(var(--accent), var(--surface), 50%); }' + LineEnding +
    '/* A thumbnail''s box: the small copy of a graph in its corner. Upstream fills' + LineEnding +
    '   it with the option''s backgroundColor, else its neutral00 token, and rims' + LineEnding +
    '   it in its border token; here the skin''s surface and border. An author''s' + LineEnding +
    '   itemStyle colours win. */' + LineEnding +
    'TyAdvChartThumbnail { background: var(--surface); border-color: var(--border); }' + LineEnding +
    '/* The window over the copy, where the canvas looks. Upstream fills it with' + LineEnding +
    '   neutral30 and rims it with neutral40 (the 0.3 opacity is the option''s);' + LineEnding +
    '   here the skin''s border, rimmed a step toward the ink. */' + LineEnding +
    'TyAdvChartThumbnailWindow { background: var(--border); border-color: mix(var(--on-surface), var(--border), 25%); }' + LineEnding +
    '/* An axis break''s area: the zigzag band where a stretch of the axis is cut' + LineEnding +
    '   out, over the series. Upstream fills it white at 60% and rims it in its' + LineEnding +
    '   border grey, dashed; here the skin''s surface at 60% and its border, so a' + LineEnding +
    '   dark skin''s breaks are dark. The dash is the option''s (3, 3 by default). */' + LineEnding +
    'TyAdvChartBreakArea { background: alpha(var(--surface), 0.6); border-color: var(--border); border-width: 1px; }' + LineEnding +
    '/* A geo component''s map. Upstream fills a region with its backgroundTint' + LineEnding +
    '   token (a pale blue-grey at half), rims it in its border grey at half a' + LineEnding +
    '   pixel and, when the option shows them, writes the region names in its' + LineEnding +
    '   tertiary ink. Here a tenth of the accent in the surface, so a dark' + LineEnding +
    '   skin''s map is a dark one, the skin''s border, and the muted ink. The' + LineEnding +
    '   half-pixel rim is the option''s. */' + LineEnding +
    'TyAdvChartGeoArea { background: mix(var(--accent), var(--surface), 90%); border-color: var(--border); }' + LineEnding +
    'TyAdvChartGeoLabel { color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    '/* A map series'' regions. Upstream fills them with its background token (a' + LineEnding +
    '   near-white blue, lighter than a geo component''s tint) and rims them in' + LineEnding +
    '   the same border grey; here a twentieth of the accent in the surface, a' + LineEnding +
    '   shade lighter than a geo''s, and the skin''s border. */' + LineEnding +
    'TyAdvChartMapArea { background: mix(var(--accent), var(--surface), 95%); border-color: var(--border); }' + LineEnding +
    '/* A hovered or selected region and its name. Upstream fills it with its' + LineEnding +
    '   highlight token (a warm yellow at 80%) and writes the name in its primary' + LineEnding +
    '   ink; here a third of the accent in the surface and the skin''s own text' + LineEnding +
    '   colour, so the region stands out in any skin. */' + LineEnding +
    'TyAdvChartGeoArea:hover { background: mix(var(--accent), var(--surface), 65%); border-color: var(--border); }' + LineEnding +
    'TyAdvChartGeoLabel:hover { color: var(--on-surface); font-size: var(--font-size-base); }' + LineEnding +
    '/* A decal''s symbols, where the decal names no colour of its own -- the aria' + LineEnding +
    '   decals that tell the series apart without their colours. Upstream draws' + LineEnding +
    '   them rgba(0, 0, 0, 0.2): the readable ink of the surface at 20%, which on' + LineEnding +
    '   the light skin''s white is exactly that, and white at 20% on a dark one.' + LineEnding +
    '   An `empty*` symbol in the pattern is a hollow over the background:' + LineEnding +
    '   upstream''s neutral00 (#fff), the surface here -- exactly that on the' + LineEnding +
    '   light skin, and no white hole on a dark one. */' + LineEnding +
    'TyAdvChartDecal { color: alpha(on(var(--surface)), 0.2); background: var(--surface); }' + LineEnding +
    '/* The item the keyboard holds. Upstream has no keyboard, so this is the' + LineEnding +
    '   library''s own focus ring, drawn around the mark: the skin''s focus ring, at' + LineEnding +
    '   the width the other controls draw theirs. The offset follows the library''s' + LineEnding +
    '   ring convention (a positive one insets the ring), so a negative one sets it' + LineEnding +
    '   off the mark. */' + LineEnding +
    'TyAdvChartFocusItem { outline: 2px var(--focus-ring); outline-offset: -3px; }' + LineEnding +
    '/* The hover tooltip. TWO keys, because upstream''s whole typographic hierarchy' + LineEnding +
    '   inside the box is one weight difference -- the name at 400 and the value at' + LineEnding +
    '   900, in the same grey -- and one style set cannot say two weights. Said here' + LineEnding +
    '   in this vocabulary''s own terms instead: the name is the muted ink a label' + LineEnding +
    '   takes, the value is full ink and bold.' + LineEnding +
    '' + LineEnding +
    '   The chart paints NO box without a background on the first key (no surface =' + LineEnding +
    '   nothing to draw on), which is the same rule TyChartTooltip follows, and it' + LineEnding +
    '   is why both live in the base layer for every theme to inherit. A skin' + LineEnding +
    '   wanting the box to float adds `shadow:`; the base stays flat like the rest' + LineEnding +
    '   of light. The BORDER here is only the fallback -- an item tooltip tints its' + LineEnding +
    '   border with the colour of the datum under the pointer, which is what makes' + LineEnding +
    '   an ECharts tooltip look attached to the thing it describes. */' + LineEnding +
    'TyAdvChartTooltip {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--muted);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius-sm);' + LineEnding +
    '  padding: var(--pad-tooltip);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyAdvChartTooltipValue {' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-bold);' + LineEnding +
    '}' + LineEnding +
    '/* The axis pointer: the line that follows the cursor along an axis, the band' + LineEnding +
    '   a `shadow` draws instead, and the label at the axis end.' + LineEnding +
    '' + LineEnding +
    '   The line reads like a split line and not like an axis line -- it is a' + LineEnding +
    '   reading aid over the plot, not a piece of the frame -- so it takes the same' + LineEnding +
    '   --border it does. The BAND is alpha over the ink for the reason every other' + LineEnding +
    '   band in this chart is: it darkens a light theme and lightens a dark one from' + LineEnding +
    '   one declaration, where upstream''s literal rgba grey does neither.' + LineEnding +
    '' + LineEnding +
    '   The LABEL is the one piece here that is meant to stand out: upstream inks it' + LineEnding +
    '   white on an indigo chip, which is a colour this vocabulary already has a' + LineEnding +
    '   name for. Accent, therefore -- so a re-skinned chart labels its pointer in' + LineEnding +
    '   the skin''s own colour instead of ECharts''. */' + LineEnding +
    '/* A candlestick''s two directions. NOT "positive and negative" however they are' + LineEnding +
    '   usually described: both compare a datum against ITSELF -- close above open' + LineEnding +
    '   against open above close -- and either can happen in a rising market.' + LineEnding +
    '' + LineEnding +
    '   Upstream writes #eb5454 and #47b262, which is the East Asian convention' + LineEnding +
    '   (red up, green down) and the opposite of the North American one. This' + LineEnding +
    '   library has a --success and a --danger already and they carry exactly the' + LineEnding +
    '   right meaning in either convention, so a theme that wants the other way' + LineEnding +
    '   round swaps two lines here instead of restyling a chart. */' + LineEnding +
    '/* A GAUGE''S READING: the headline number under the needle, and the only thing' + LineEnding +
    '   in this vocabulary that had no donor. The chart''s own title key is bold but' + LineEnding +
    '   is sized off the title scale -- a gauge''s reading is the picture, not a' + LineEnding +
    '   heading over it -- and every label key is base size. Upstream writes 30px' + LineEnding +
    '   and a literal here is the right place for a literal: a skin that wants a' + LineEnding +
    '   quieter dial changes this one line. The gauge''s name caption takes' + LineEnding +
    '   TyAdvChartLabel, its scale takes TyAdvChartAxisLabel, its major ticks take' + LineEnding +
    '   TyAdvChartAxisTick and its minor ones TyAdvChartMinorTick, so this is the' + LineEnding +
    '   only key the whole series added. */' + LineEnding +
    'TyAdvChartGaugeDetail { color: var(--on-surface); font-size: 30px;' + LineEnding +
    '                        font-weight: var(--font-weight-bold); }' + LineEnding +
    'TyAdvChartCandleUp { background: var(--danger); }' + LineEnding +
    'TyAdvChartCandleDown { background: var(--success); }' + LineEnding +
    'TyAdvChartAxisPointer { border-color: var(--border); border-width: 1px; }' + LineEnding +
    'TyAdvChartAxisPointerShadow { background: alpha(var(--on-surface), 0.10); }' + LineEnding +
    '/* [R5-A] upstream''s tokens.color.shadow (light and dark alike): the colour of' + LineEnding +
    '   the shadows a series or a component casts by default -- a boxplot''s' + LineEnding +
    '   emphasis, a continuous visualMap''s indicator */' + LineEnding +
    'TyAdvChartShadow { color: rgba(0, 0, 0, 0.2); }' + LineEnding +
    'TyAdvChartAxisPointerLabel {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  color: var(--on-accent);' + LineEnding +
    '  border-radius: var(--radius-sm);' + LineEnding +
    '  padding: 5px 7px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    '/* The loading effect (showLoading): the mask over the chart, its words, and' + LineEnding +
    '   the turning arc. Upstream writes a white mask at 0.8, its darkest neutral' + LineEnding +
    '   for the words and the first palette colour for the arc -- on a light skin' + LineEnding +
    '   exactly this, and on a dark one a mask of its own surface instead of a' + LineEnding +
    '   white sheet over a dark chart. The arc''s width and radius are geometry the' + LineEnding +
    '   cfg sets (5 and 10 by default); only its colour is the skin''s. */' + LineEnding +
    'TyAdvChartLoading { background: alpha(var(--surface), 0.8); color: var(--on-surface);' + LineEnding +
    '                    font-size: var(--font-size-base); }' + LineEnding +
    'TyAdvChartLoadingSpinner { border-color: var(--accent); }' + LineEnding;
end;

initialization
  TyRegisterAddOnCss('advchart', TyAdvChartCss);

end.
