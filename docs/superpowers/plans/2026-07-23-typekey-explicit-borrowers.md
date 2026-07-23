# Theme typeKey audit — the explicit-borrow population

Date: 2026-07-23 · branch `feat/prerelease-3.0-alpha` · follows commit `b824a49`


## Why this document exists

The first typeKey pass (`b824a49`) defined "borrowing" as *"has no `GetStyleTypeKey` of its
own"*. That missed an entire second population: **controls that DECLARE the method and return
a key naming a different control**. There are 30 of them. This is the audit of that set.

Verdicts below were reached by reading each control's `Paint`/`RenderTo` — every one cites the
drawing code. The standard applied is the library's own: *a control the theme layer cannot
reach is a bug*, and "it looks the same in today's light theme" is **not** a reason to borrow —
the question is whether a **skin** should be able to tell them apart.

## Status

- **Box keys: implemented.** Each control below gained its own `GetStyleTypeKey`, added to the
  donor's rule block as an extra selector so every resolved value stayed byte-identical
  (golden files: additions only).
- **Sub-part keys: NOT implemented — deliberately deferred.** They are a themability
  *expansion*, not a coverage gap, and several of them **would move pixels** because the
  current code invents a colour where the key should supply one (`TTyControlBar`'s gripper,
  `TTySizeBox`'s dots, `TTyChart`'s fixed series palette). That belongs in its own pass with
  the change acknowledged, not folded into a "nothing moves" refactor. Every one is recorded
  below so none of it is lost.


## Needs its own key — 27

### `TTyHtmlLabel` → `TyHtmlLabel`
*Unit:* `D:\Projects\ty-controls\source\tyControls.HtmlLabel.pas` · *was:* `TyLabel`

RenderTo (l.610-675) draws things TTyLabel never draws: it walks FLayout and paints per-run fragments, then for every <a> run (and every <u> run) fills a 1px underline band at Rect.Bottom-th and for <s> a strike band at mid-height (l.658-669). Worse, the link ink is resolved from NO key at all: l.638 hardcodes an inline stylesheet string, ActiveController.Model.ResolveOverride('color: var(--accent);'), so hyperlink colour inside rich text is nailed to --accent and is unreachable by any selector — the exact bug the last pass fixed for TTyLinkLabel by giving it TyLinkLabelLink. A skin that wants links in a different hue, or wants rich-text blocks at a different base size/leading than static captions, cannot express either. Underline/strike thickness is the literal P.Scale(1) (l.644-645).

**Deferred sub-part keys:** TyHtmlLabelLink

### `TTyLinkLabel` → `TyLinkLabel`
*Unit:* `D:\Projects\ty-controls\source\tyControls.LinkLabel.pas` · *was:* `TyLabel`

RenderTo (l.145-186) draws a caption plus an always-on 1px accent underline spanning the measured text width (l.170-181) — a mark TTyLabel has no concept of. The box borrow means font-name/size/weight/padding/opacity for a hyperlink are whatever static labels get; a skin cannot make links bolder, smaller, or padded differently without repainting every label. Three hardcoded visuals along the way: LinkColor (l.104-116) synthesises hover as TyLighten(col, 15) instead of resolving a :hover rule, and it resolves 'TyLinkLabelLink' with an EMPTY state set (l.112, ResolveStyle(..., [])), so :hover/:disabled on that key are dead selectors even though TTyGraphicControl.CurrentStates already reports FHover; the underline drop is the literal P.Scale(3) (l.173) and its thickness the literal 1 in TyLinkUnderlineRect (l.80). It also ignores S.Padding entirely (ContentRect = the full rect, l.164) while TTyLabel insets by all four sides — a resolved token silently dropped.

**Deferred sub-part keys:** TyLinkLabelLink (already exists; must be resolved WITH states)

### `TTyShadowLabel` → `TyShadowLabel`
*Unit:* `D:\Projects\ty-controls\source\tyControls.ShadowLabel.pas` · *was:* `TyLabel`

RenderTo (l.110-150) draws the caption TWICE: a shadow pass at ContentRect offset by P.Scale(FShadowOffsetX/Y) in FShadowColor, then the normal pass. Neither the shadow ink nor the offsets come from the theme — the constructor hardcodes FShadowColor := TyRGBA(0,0,0,120) and offsets 1,1 (l.60-62). The style model ALREADY carries this exact triple (tpShadow: ShadowColor/ShadowBlur/ShadowOffset, spelled 'shadow: dx dy blur color' in .tycss and used by builtin/adwaita on TyButton), and this control reads none of it — capability built, not wired. Consequence: a flat skin (material3/fluent) cannot flatten drop-shadowed captions, and a dark skin is stuck with a black-on-dark shadow; putting 'shadow:' on TyLabel to reach it would shadow every static label in the app.

### `TTyGlowLabel` → `TyGlowLabel`
*Unit:* `D:\Projects\ty-controls\source\tyControls.GlowLabel.pas` · *was:* `TyLabel`

RenderTo (l.133-206) rasterises the caption onto a SEPARATE transparent BGRA layer in FGlowColor, Gaussian-blurs it by P.Scale(FGlowRadius) via FilterBlurRadial, and stamps the result 1+Min(3, blurDev div 4) times under the crisp text (l.162-195) — an entire extra visual layer TTyLabel does not have. The halo's colour and radius are per-instance hardcoded defaults, TyRGBA(255,255,255,200) and 4 (l.78-79), so on any dark or flat skin the white Vista halo is simply wrong and the theme layer cannot touch it. Same tpShadow mapping as TTyShadowLabel (blur + zero offset) is already in the model and unused. It also ignores S.Padding (ContentRect = full rect, l.155) unlike TTyLabel, and the stamp count 3 / divisor 4 are magic numbers in the ink path.

### `TTyDivider` → `TyDivider`
*Unit:* `D:\Projects\ty-controls\source\tyControls.Divider.pas` · *was:* `TyLabel`

Strongest case in the group: this is not text chrome, it is a RULE. RenderTo strokes one or two solid horizontal bands (StrokeSeg, l.177-187) around an optional caption, and it is registered on the panel/container palette page next to TTyBevel and TTySplitter (designtime/tyControls.Design.pas:704), not with the labels. Its rule ink prefers S.BorderColor but NO shipped theme gives TyLabel a border-color (verified across themes/*.tycss and all 15 themes/builtin/*.tycss), so every skin falls into the else branch at l.216-217: a synthesised TyRGBA(R,G,B, alpha*40 div 100) of the text colour — a hardcoded ratio, and the band is therefore unthemable everywhere. That is precisely the Office group-header-band disease named for this phase. tests/test.divider.pas:210 proves it: to exercise the themed path the test must load 'TyLabel { border-color: #3B82F6 }', i.e. border every label in the app. TyToolBar/TyToolSeparator in light.tycss:679 is the library's own precedent block (one rule, separator owns its name so a skin can dot/fade/hide just the rule). Also literals: gap P.Scale(6), minRule P.Scale(4), ruleThick P.Scale(1) (l.224-226) belong in metric tokens the way TySegmentedPadVar does.

### `TTyCharImage` → `TyCharImage`
*Unit:* `D:\Projects\ty-controls\source\tyControls.CharImage.pas` · *was:* `TyLabel`

It draws no text at all. RenderTo (l.177-226) sizes a square slot and composites a rasterised icon-font bitmap from FIconFont.RenderGlyph centred in the box (l.212-216); S.TextColor is only the fallback ink when GlyphColor is the transparent sentinel. An icon and a paragraph caption are different things a skin routinely inks differently (icons at --muted against text at --on-surface); today that is impossible without recolouring every label. Its palette group agrees — it is registered with TTyImage/TTyGlyphImageList (designtime/tyControls.Design.pas:726), not with the labels at :671. It also ignores the resolved S.Padding and insets by its own hardcoded const TyCharImagePad = 2 (l.35, l.202) — a geometry literal that should be a metric token now that the box has a key to hang it on.

### `TTyButtonGroup` → `TyButtonGroup`
*Unit:* `D:\Projects\ty-controls\source\tyControls.ButtonGroup.pas` · *was:* `TyButton`

It draws a segmented BAR, not a button. RenderTo (l.286-370) tiles N segment rects and gives each ASYMMETRIC corners — only the first cell's left corners and the last cell's right corners take the radius, seams are square (l.341-343) — and deliberately leaves adjacent 1px borders doubled on the seam so they read as dividers (l.349-353). TTyButton draws one uniformly rounded frame plus a caption. The library already treats this archetype as its own themable thing: TTySegmented owns 'TySegmented' (track) + 'TySegmentedItem' (chip) with their own :hover/:selected rules (light.tycss:895-908), and TTyButtonGroup is the same archetype with none of that reach. Concrete consequence: the outer radius is read straight off TyButton's BorderRadius (l.319), so a pill-radius button skin gives the bar pill ends with square seams and the skin has no selector to correct it; and a segment's hover/selected treatment is by construction identical to a plain button's, so no skin can distinguish 'one button' from 'a bar of choices'. Side note found here: the empty-Items early-out (l.310-315) claims it 'still fills its background' but only TyFillParentBg ran — the group has no track fill of its own, which a TyButtonGroup key would give it.

**Deferred sub-part keys:** TyButtonGroupItem

### `TTyUpDown` → `TyUpDown`
*Unit:* `D:\Projects\ty-controls\source\tyControls.UpDown.pas` · *was:* `TyButton`

Paint (l.279-342) draws a frame, then TWO arrow glyphs (P.DrawGlyph tgArrowUp/tgArrowDown, l.303-304), then a hairline divider band between the halves in S.BorderColor (l.322-336), and each half gets its OWN :hover/:active background fill inset past the border (PaintHalf, l.287-305). A TTyButton is one hit area with a caption and never draws a seam or a glyph. Because the halves resolve 'TyButton' with hover/active states, a skin that gives buttons an accent-filled hover paints half a spinner accent — a spinner is field-adjacent chrome, not a command surface, and no selector separates them. TyDateTimeButton (light.tycss:698) is the library's precedent for a half/sub-button key. Themability bug met on the way: this control calls P.DrawGlyph directly instead of TyDrawGlyph, so the v3/C5 '--glyph-arrow-up' / '--glyph-arrow-down' icon-font overrides that TTySpinEdit honours (SpinEdit l.393-394) are silently ignored here; the glyph stroke thickness 3 is also a bare literal.

**Deferred sub-part keys:** TyUpDownButton

### `TTyChart` → `TyChart`
*Unit:* `D:\Projects\ty-controls\source\tyControls.Chart.pas` · *was:* `TyPanel`

Worst offender in the group. RenderTo:1561 draws the panel frame and then a whole data-visualisation on top of it: DrawTitle:1221 (P.DrawText with literal size 11 / weight 700 and Font.Name, not S.FontName), DrawLegend:1254 (swatch chips P.Scale(10), gaps 6/14/4, labels at literal 9/400), DrawAxesChart:1290-1321 (grid lines whose colour is the panel BORDER with a HARDCODED gridPx.alpha := 70, axis polyline at lineWidth 1, tick labels at literal 8/400, label gutter P.Scale(34)/(3)/(8)/(16)), bars 1346, line series lineWidth P.Scale(2) + markers of radius P.Scale(3):1380, DrawPie:1431-1447 (slice fills from the hardcoded TyChartPalette, separator lineWidth P.Scale(1), percentage labels 8/700). A panel draws a frame and one caption; none of this. The control already proves the pattern works by owning 'TyChartTooltip' (light.tycss:1019) — the tooltip is themable and everything else in the same control is not, and light.tycss:1013 says so in a comment: "the chart's own chrome resolves TyPanel and its series ride a fixed code palette, so the hover tooltip is the ONE key it owns". The series palette (TyChartPalette:205-213, eight literal Tableau-10 TColors) is the biggest hardcoded visual in the library; indexed sub-part keys are the only mechanism available today because Controller exposes only Metric(name, integer) and no colour-token accessor.

**Deferred sub-part keys:** TyChartTitle, TyChartLegend, TyChartAxis, TyChartGrid, TyChartLabel, TyChartSeries1..TyChartSeries8 (already owns TyChartTooltip)

### `TTyCalculator` → `TyCalculator`
*Unit:* `D:\Projects\ty-controls\source\tyControls.Calculator.pas` · *was:* `TyPanel`

Paint:447-469 draws its own panel background and then a DISPLAY BAND a panel never draws — and it reaches for a second foreign key to do it: line 455 resolves 'TyEdit' (TTyEdit's key), then hardcodes the band geometry (dispR insets P.Scale(4)/P.Scale(2):457, pad P.Scale(6):456, the two-line split mid = 2/5 of the band:462) and, worst, line 463 synthesises the secondary line's ink: dim := (es.TextColor and $00FFFFFF) or $A0000000 — literally the same hardcoded-alpha-tint disease as the Office group-header band this phase is fixing. The two text sizes are also literal deltas off the borrowed style: ResolveFontSize(es) - 1 (expression, 465) and + 6 (result, 468). A skin cannot make the calculator readout a dark LCD, cannot set its ink, and cannot restyle it without dragging every TTyEdit in the app along. The keypad is real TTyButton children so it is already reachable; only the box and the readout are not.

**Deferred sub-part keys:** TyCalculatorDisplay, TyCalculatorExpression

### `TTyBevel` → `TyBevel`
*Unit:* `D:\Projects\ty-controls\source\tyControls.Bevel.pas` · *was:* `TyPanel`

RenderTo:212-240 draws no panel at all — no fill, no border, no caption. It draws 1px HIGHLIGHT and SHADOW rails (HLine/VLine at 166-173), and for tbsFrame two nested rings with the colours swapped to fake a groove. Both colours are invented in code: BevelBaseColor:114 picks border, else background, else text, else literal TyRGB(128,128,128), then hiC := TyBevelLighten(baseC, 0.55) and loC := TyBevelDarken(baseC, 0.45) at 194-195 — two hardcoded blend amounts that ARE the control's entire appearance. The theme layer today can only nudge the bevel sideways by recolouring every panel border. A flat/modern skin's legitimate wish — one hairline instead of a fake-3D pair — is expressed by setting TyBevelHighlight and TyBevelShadow to the same colour, which is impossible while the two colours are literals in Pascal.

**Deferred sub-part keys:** TyBevelHighlight, TyBevelShadow

### `TTySizeBox` → `TySizeBox`
*Unit:* `D:\Projects\ty-controls\source\tyControls.SizeBox.pas` · *was:* `TyPanel`

RenderTo:237-261 draws the panel frame and then the classic engraved size grip: a 3/2/1 diagonal ladder of six square dots (TySizeGripDots:75), each painted twice — a shadow copy offset by a hardcoded +1 device px (258-259) under a highlight body (260-261). Both dot colours are code-invented from the panel token: seed := BorderColor else TextColor, then TyLighten(seed, 55) / TyDarken(seed, 30) at 248-249. The ladder metrics are literal constants, not theme metrics: GripDotLogical=2, GripStepLogical=4, GripPadLogical=3 (69-71) — note the library already has the Metric() mechanism for exactly this (see tyControls.ListGroupPanel.pas:27-33). Dots are not a thing a panel draws; the grip is unreachable and its 3D read is unremovable.

**Deferred sub-part keys:** TySizeBoxDot (plus metrics --sizebox-dot-size / --sizebox-dot-step / --sizebox-dot-pad)

### `TTyControlBar` → `TyControlBar`
*Unit:* `D:\Projects\ty-controls\source\tyControls.ControlBar.pas` · *was:* `TyPanel`

Paint:348-377 calls inherited (the TyPanel frame) and then overlays one GRIPPER per occupied band. DrawGripper:320-346 draws two vertical rails whose colour is again invented — 'if tpBorderColor in AStyle.Present then railColor := AStyle.BorderColor else AStyle.TextColor' (329-330) — at hardcoded metrics railW := P.Scale(1), railGap := P.Scale(3), inset := P.Scale(3) (335-337). A rebar's grip rails are not panel chrome; today a skin cannot recolour, thin, widen or delete them, and cannot tint the bar itself without tinting every panel. Its own unit header states the constraint that produced the bug: "HARD RULE: reuse the 'TyPanel' typeKey — no new .tycss" (line 21) — that rule is exactly what this phase reverses.

**Deferred sub-part keys:** TyControlBarGripper (resolve it as GetStyleTypeKey + 'Gripper', the TTyActivityBar 'Fill' pattern, so TTyCoolBar inherits its own gripper key for free)

### `TTyCoolBar` → `TyCoolBar`
*Unit:* `D:\Projects\ty-controls\source\tyControls.CoolBar.pas` · *was:* `TyPanel`

It has no Paint of its own, so its pixels are TTyControlBar's — which means it inherits the same defect: the frame plus per-band grippers, none of which a panel draws. Its GetStyleTypeKey:151 explicitly re-states 'TyPanel' with the comment "NO new .tycss (hard rule)", so it will keep pointing at the panel even after the base is fixed unless it is touched. Beyond that it is a genuinely different control from its base: its grippers are INTERACTIVE — MouseDown:296 hit-tests them via TyCoolGripperHit and drags resize the band (MouseMove:316-330) — so a skin has a real reason to make a draggable rail read differently from TTyControlBar's decorative one. If the project prefers the minimum change, deleting the override entirely is also correct (it would then inherit 'TyControlBar'); what is not correct is 'TyPanel'.

**Deferred sub-part keys:** TyCoolBarGripper (free if DrawGripper resolves GetStyleTypeKey + 'Gripper')

### `TTyColorGrid` → `TyColorGrid`
*Unit:* `D:\Projects\ty-controls\source\tyControls.ColorGrid.pas` · *was:* `TyPanel`

Paint:157-213 fills the parent background and then draws a swatch MATRIX: per cell a data-colour fill (198-200), a 1px outline and, on the selected cell, a thicker inset ring (202-205). None of that exists on a panel. Both chrome widths are literals — P.StrokeBorder(cellR, 0, 1, outline) and ringW := Math.Max(2, P.Scale(2)):190 — and the '0' radius means a skin can never round the swatches. The outline colour is a code-side fallback chain (outline := st.BorderColor; if alpha = 0 then st.TextColor, 174-175), so on a skin that leaves TyPanel's border transparent the grid silently switches to ink-coloured gridlines with no way to say otherwise. Selection feedback deserves a state-addressable key, which is the one thing the borrow cannot give it (TyPanel has no meaningful :selected).

**Deferred sub-part keys:** TyColorGridCell (+ :selected state for the ring: border-width 2 instead of the literal)

### `TTyShape` → `TyShape`
*Unit:* `D:\Projects\ty-controls\source\tyControls.Shape.pas` · *was:* `TyPanel`

RenderTo:141-276 builds a vector PATH — ellipse, circle, inscribed square, rounded rect, triangle/diamond polygons from TyShapePolygon, or a diagonal line — and fills it with the panel background and strokes it with the panel border. It is a diagram primitive that merely reuses the panel's two colour tokens; it is not a container surface. Concretely the borrow forces one decision on both: a skin that gives panels a card look (radius, subtle border) applies that radius to tskRoundRect (line 178 reads TyEffectiveCorners(S).TL) and that border to every arrowless shape on a diagram, and a skin that wants bold filled diagram shapes has to recolour every panel in the app to get them. Hardcoded along the way: ctx.lineCap := 'round' for the line kind (245) and ctx.lineJoin := 'miter' (266) are literal and differ from TTyStarShape's 'round' join — the same shape family renders with inconsistent joinery that no theme can reconcile.

### `TTyStarShape` → `TyStarShape`
*Unit:* `D:\Projects\ty-controls\source\tyControls.StarShape.pas` · *was:* `TyPanel`

RenderTo:140-212 traces the 2N-vertex star ring from TyStarPolygon and fills/strokes it with the panel's background/border. Same class of error as TTyShape: a decorative star is not a panel surface, and the practical consequence is that a rating/《badge》star cannot be given its own colour without repainting every container in the application. Hardcoded visuals: the edge inset TyStarMargin = 2 (line 33) is a literal logical-px constant where the library elsewhere uses a Metric() token, and ctx.lineJoin := 'round' (179) is fixed, so a skin cannot get the sharp-pointed star that most brands want. Note the last pass already split TTyRating off TyGauge and gave it 'TyRatingStar' — a themable star already exists in the library, and this one is invisible next to it.

### `TTyArrow` → `TyArrow`
*Unit:* `D:\Projects\ty-controls\source\tyControls.Arrow.pas` · *was:* `TyPanel`

RenderTo:207-270 fills and strokes the 7-point block-arrow polygon from TyArrowPolygon with the panel background/border. It draws no frame, no caption, no surface — a directional marker on a diagram is a different thing from a container that merely happens to use the same two tokens. The borrow makes the whole diagram family (TTyShape/TTyStarShape/TTyArrow, all registered together in designtime/tyControls.Design.pas:730) share one colour with every panel, so a skin can never express "diagram ink is accent, containers are neutral". ctx.lineJoin := 'miter' (261) is hardcoded, which is what makes a thick-bordered arrow grow spikes at its barbs with no theme control.

### `TTyImageView` → `TyImageView`
*Unit:* `D:\Projects\ty-controls\source\tyControls.ImageView.pas` · *was:* `TyPanel`

RenderTo:695 fills the whole control with the panel surface and then blits the zoomed/panned/filtered bitmap over it — the code's own comment calls it the "Mailbox surface" (694), i.e. the letterbox MAT a zoomed image floats on. That mat is the one visual the theme controls in this control, and its conventional treatment is the opposite of a panel's: photo viewers use a near-black or checkerboard mat so the image reads, while panels are the app's light surface. Today `TyImageView { background: #1e1e1e }` is inexpressible — the only way to darken the mat is to darken every panel. The precedent is already in the theme: light.tycss:313 split TyScrollBox off TyPanel for exactly this reason ("the scrolling WELL, which conventionally sinks where a panel lifts") even though TTyScrollBox also draws only a frame.

### `TTyImage` → `TyImage`
*Unit:* `D:\Projects\ty-controls\source\tyControls.Image.pas` · *was:* `TyPanel`

Weakest of the media trio on drawing (RenderTo:227-231 draws the panel frame only when Transparent=False, else nothing) but it has the sharpest reachability proof in the whole group. In its DEFAULT transparent mode the single style property it reads is opacity: 'else if tpOpacity in S.Present then P.Opacity := S.Opacity' (229-230), documented at line 20 as "the style opacity (e.g. :disabled opacity 0.5) is honored ... so a disabled image dims". light.tycss declares TyPanel with no state rules at all (only the one block at line 317, no :disabled), so that documented behaviour does not happen — and the only fix available while the key is borrowed, adding TyPanel:disabled { opacity }, would dim every panel, groupbox-adjacent surface and container in the app. The control is a media leaf, not a container (registered with TTyIconFont/TTyCharImage/TTyGlyphImageList, Design.pas:726); when opaque, the surface it paints is a picture mat and should be settable with TTyImageView's.

### `TTyPreviewBox` → `TyPreviewBox`
*Unit:* `D:\Projects\ty-controls\source\tyControls.PreviewBox.pas` · *was:* `TyPanel`

Medium strength — its own drawing (RenderTo:217-233) is a frame plus one centred string, the same two primitives TTyPanel.RenderTo uses for its Caption, so the case rests on role rather than on extra chrome. But the role is a distinct one the theme cannot name: this is the file dialogs' preview WELL (unit header line 15), hosting an image pane and a memo pane, and the string it draws is an EMPTY STATE ("cannot preview", rsPvCannotPreview via ShowMessage) painted at full S.TextColor — empty-state text is conventionally muted, and muting it today means muting every panel caption in the app. Same argument the theme already accepted for TyScrollBox at light.tycss:313. Note the box key alone is sufficient here — the placeholder is the only text the control draws, so its `color` becomes reachable with no sub-part. Contrast TTyPaintPanel, deliberately kept on TyPanel because it is "byte-compatible with a plain TTyPanel" and is a panel; a preview pane is not.

### `TTyListGroupPanel` → `TyListGroupPanel`
*Unit:* `D:\Projects\ty-controls\source\tyControls.ListGroupPanel.pas` · *was:* `TyPanel`

Lowest priority in the group, and its sub-part half is genuinely the model this phase should copy for the Office band (RenderTo:727 and :769 resolve its OWN TyListGroupHeader / TyListGroupItem instead of borrowing TyTreeHeaderSection / TyListItem, and light.tycss:1035 documents why). The remaining gap is only the BOX: line 687 is DrawFrame(P, R, BoxStyle) with BoxStyle = the panel's. That box is a navigation SIDER surface — the accordion's backdrop, clipped and scrolled (700-712) — and in every design system a sider carries its own surface token, distinct from a content card. As it stands a skin can style the sider's rows but not the sider, so `TyPanel { border-radius }` rounds it like a card and there is no way to say "flat, full-bleed". Cost is one extra selector with identical values. Also noted in passing: the item pill's vertical inset is derived as insetPx div 2 (774-775), i.e. a hardcoded 2:1 ratio against the --listgroup-item-inset token.

**Deferred sub-part keys:** none new — TyListGroupHeader / TyListGroupItem already exist and are correct

### `TTyRibbonBackstage` → `TyRibbonBackstage`
*Unit:* `D:\Projects\ty-controls\source\tyControls.RibbonBackstage.pas` · *was:* `TyRibbon`

RenderTo (RibbonBackstage.pas:370-492) is a full-window overlay that draws a 190px accent SIDEBAR panel (399), a back-chevron band (407-408), N command rows with per-row hover/active fills (441-449), separator rules (420-423, 435-439), per-row icon-font/image glyphs (453-473) and a large fallback content title (483-486). TTyRibbon draws none of these. Worse, 'TyRibbon' only supplies the content pane's background — everything that visually reads as 'backstage' is resolved from a SECOND foreign key, ResolveStyle('TyButton','primary') at 397/442/444, so a skin cannot make the sidebar anything but the primary-button colour and cannot separate a backstage row's hover/active from a button's. Hardcoded visual values met: sidebar font is ResolveFontSize(SideS) + 2 (402); the content title is fs + 8 at literal weight 600 (485); separator lines are painted in SideS.TextColor — ink used as a rule colour (417, 423, 436-437); back-chevron geometry P.Scale(22)/P.Scale(9) (407-408); divider insets P.Scale(16)/P.Scale(6) (423); row right pad P.Scale(8) (476); title rect P.Scale(40)/30/20/70 (484).

**Deferred sub-part keys:** TyRibbonBackstageSidebar (the accent command panel, currently TyButton.primary); TyRibbonBackstageItem + :hover/:selected (one command row, currently TyButton.primary:hover/:active); TyRibbonBackstageBack (the top back-arrow band); TyRibbonBackstageSeparator (the '-' rule and the bottom-block divider, currently drawn in the sidebar's text colour)

### `TTyRibbonQuickAccess` → `TyRibbonQuickAccess`
*Unit:* `D:\Projects\ty-controls\source\tyControls.RibbonQuickAccess.pas` · *was:* `TyTitleBar`

RenderTo (RibbonQuickAccess.pas:155-179) calls DrawFrame(R, S) with the title-bar style, and DrawFrame (Base.pas:890-935) applies that style's SHADOW, BACKGROUND, CORNER RADIUS and BORDER STROKE. But the QAT is not the caption band — it is a small alNone strip parented ONTO it (examples/ribbon/umain.pas:979-981: FQat.Parent := Bar; FQat.SetBounds(Bar.ClientWidth, 3, 5*28+8, 28)), so every geometric facet of TyTitleBar is re-drawn at strip scale in the middle of the caption. Five SHIPPED skins already misfire: win10.tycss:105 'border: 1px solid var(--titlebar-border)' paints a 1px box around the QAT; adwaita.tycss:61 'border-bottom: 1px solid var(--border)' paints a stray rule under it; macos.tycss:128 'border-radius: 6 6 0 0' gives it rounded top corners floating mid-bar; breeze.tycss:73 'border-radius: 3' likewise; classic.tycss:54 'linear-gradient(0deg, var(--accent), var(--title-mid), var(--title-light))' restarts the vertical gradient inside the QAT's own 28px rect at y=3, so a re-run gradient block sits on the bar. The stated rationale for the borrow (121-122: 'makes its child buttons' TyResolveParentBg pick the title-bar colour') does NOT require it — TyResolveParentBg (Base.pas:432-455) reads TTyCustomControl(AChild.Parent).CurrentStyle, i.e. whatever key the QAT itself declares, so an own key seeded to the same background keeps the blend byte-identical. Also stale docs: the unit header (17-18) and the method comment (53) still claim GetStyleTypeKey = 'TyRibbon' / 'REUSES the existing ribbon band token' while the body returns 'TyTitleBar'; and tests/test.ribbonquickaccess.pas:45-57 (TestTypeKeyIsTitleBar) pins the borrow and will need updating.

### `TTyRibbonGallery` → `TyRibbonGallery`
*Unit:* `D:\Projects\ty-controls\source\tyControls.RibbonGallery.pas` · *was:* `TyListBox`

RenderTo (RibbonGallery.pas:562-644) draws a DROP-DOWN CHEVRON — P.DrawDropChevron(arrowR, BoxStyle.TextColor) at 633 — over an '--gallery-arrow-width' zone that a list box has no concept of; the cells are a fixed-width tile ROW measured from '--gallery-cell-width' (579), not text rows measured from an item height. PaintCell (513-560) renders an IconFont GLYPH THUMBNAIL left of the caption (536-552); TTyListBox rows are text only. The popup content control TTyGalleryGrid also returns 'TyListBox' (229-232) yet lays a ROW-MAJOR GRID via TyGalleryGridRect (272) — so the single key 'TyListBox' currently has to mean 'scrolling text list', 'chevroned tile row' and 'tile grid' at once, and 'TyListItem' has to mean both a list row and a gallery tile. The library already rejected exactly this argument for the identical species: TTyValueListEditor (ValueListEditor.pas:1223-1240) unwelded from TyListBox/TyListItem because 'a property inspector that merely reuses TTyListBox's row loop' draws parts a list of strings has not, and got -Row/-Key/-Value/-Divider/-Expander. The gallery's in-source justification ('REUSE — the gallery is a list-of-cells surface', line 381) is that rejected argument verbatim. No hardcoded visuals found in the paint path — every metric goes through a --gallery-* token and PaintCell honours cellStyle.Padding (531, 556).

**Deferred sub-part keys:** TyRibbonGalleryItem + :hover/:active (one tile, currently TyListItem — shared with real list rows in both the inline row and the popup grid); TyRibbonGalleryPopup (TTyGalleryGrid's floating grid surface, currently TyListBox — a popup wants its own shadow/border independently of an inline row)

### `TTyTabSet` → `TyTabSet`
*Unit:* `D:\Projects\ty-controls\source\tyControls.TabSet.pas` · *was:* `TyTabControl`

'TyTabControl' HAS NO OWNING CONTROL. The only three tab-family key declarations in source/ are PageControl.pas:50 'TyPageControl', TabSet.pas:56 'TyTabControl' and TabSheet.pas:46 'TyTabSheet'; there is no TTyTabControl class anywhere in the library, and no theme defines 'TyTabSet'. So the TabSet is the sole consumer of a key named after a control that does not exist, while the name a skin author would actually reach for resolves to nothing — the borrowed-key-unreachable bug in its purest form. The borrow is also now actively wrong: since 0c98aee ('a caption-only strip must not frame a page body') TTyTabSet overrides HasPageBody := False (59-62), which makes TabStrip.RenderTo skip DrawFrame entirely and draw ONLY a baseline rail — P.FillBackground(Rect(0, ContentTop, W, ContentTop + BaseW), BaseFill, 0) at TabStrip.pas:806-814, consuming nothing but BoxStyle.BorderColor and BoxStyle.BorderWidth. Every other facet of the TyTabControl rule is dead on the TabSet: 'background: var(--surface)', 'border-radius: var(--radius)' (themes/auto.tycss:283-289) and showcase.tycss:327's 'shadow: 0px 1px 3px #0000001F' are never drawn — while the two facets that ARE live are simultaneously the page-control box border. A skin wanting a Material-style 2px accent underline rail under a caption-only strip would have to thicken and accent every TyTabControl-keyed box. The code already made this split in Pascal; the theme layer still cannot see it.

**Deferred sub-part keys:** TyTabSetRail (the baseline the tabs sit on — currently the page-container box's border-color/border-width repurposed; it is the ONLY mark the strip draws, so it needs to be settable without touching any box border)

### `TTyHeaderControl` → `TyHeaderControl`
*Unit:* `D:\Projects\ty-controls\source\tyControls.HeaderControl.pas` · *was:* `TyTreeHeader`

The same tokens mean two different things to the two consumers. The tree uses TyTreeHeader as a BAND INSIDE its own frame: TreeView.pas:3368-3374 fills headerBandRect with the background and 3485-3486 draws a bottom line — it never strokes a box. TTyHeaderControl calls DrawFrame(P, R, S) (HeaderControl.pas:405), which per Base.pas:890-935 paints background + BORDER STROKE + CORNER RADIUS + SHADOW. So 'border-radius' on TyTreeHeader means 'round the standalone strip' and 'nothing' to the tree, and 'border-color' means 'the strip's outer box' to one and 'the tree's column divider / header underline' to the other — they cannot be tuned apart. The marks differ too: the tree's sort indicator is a stroked vector glyph, P.DrawGlyph(sortBandR, tgArrowUp/tgArrowDown, ...) (TreeView.pas:3460-3469); the header control draws a FILLED Canvas2D triangle from its own pure geometry TyHeaderSortTriangle (HeaderControl.pas:466-474). It is also the ONLY consumer of TyTreeHeaderSection:hover (409-410, 427-428) — the tree's hover branch is dead code (TreeView.pas:3405-3408: 'NoColumn = -1, so this branch never fires') — and it owns an interactive resize grip + crHSplit cursor the tree header has no counterpart for. This is precisely the bug already fixed for TTyListView: ListView.pas:881-897 and DefaultTheme.pas:736-742 record that its column-header band and its group band 'resolved the SAME TyTreeHeader literal, so the two could never be styled apart'. TTyHeaderControl is the third consumer of that literal and was missed by that pass. Hardcoded visual values met: padL/padR := P.Scale(6) (416-417) while the resolved secStyle.Padding is fetched and then ignored (contrast RibbonGallery.PaintCell:531/556, which does use cellStyle.Padding); sortSize := P.Scale(9) (418) and gutter := sortSize * 2 (452); the section divider is a hard 1px line at cellRect.Right - 1 (479-480) that ignores S.BorderWidth entirely; TyHeaderResizeGrip = 4 (line 14).

**Deferred sub-part keys:** TyHeaderControlSection + :hover/:selected (one column cell, currently TyTreeHeaderSection — shared with the tree's own column headers); TyHeaderControlSortMark (the filled sort triangle: it is a different mark from the tree's stroked arrow glyph and currently takes the section's text colour with a hardcoded P.Scale(9) size); TyHeaderControlDivider (the between-section rule, currently a hardcoded 1px line in the strip's border colour)


## Borrow is correct — 3

### `TTyRelativePanel` keeps `TyPanel`

It draws nothing at all — the unit has no Paint and no RenderTo (grep for DrawFrame/DrawText/P.Scale over the file returns zero hits); every pixel comes from TTyPanel.RenderTo, whose class it extends (line 95). Its entire content is the pure solver TyRelativeSolve plus SetBounds calls in PerformLayout. It IS a panel — same frame, same optional caption, same padding — that differs only in a LAYOUT POLICY, and layout policy is not a visual identity a skin needs to address. This is exactly the category the previous pass and the theme kept on purpose: light.tycss:315 says "TTyScrollPanel and TTyPaintPanel are deliberately NOT here: they add no chrome of their own and keep inheriting", and TTyRelativePanel adds even less than TTyPaintPanel does. The override at line 333 restates what it would inherit anyway; giving this one a key would add a selector that can never be told apart from TyPanel by any rendering difference.

### `TTyRibbonPage` keeps `TyRibbon`

RenderTo (Ribbon.pas:1033-1056) draws a STRICT SUBSET of what the ribbon box already draws: backdrop fill + FillBackground(S.Background) and explicitly NO border — the in-source comment (1046-1048) says the ribbon's own frame draws the outer border and a page border would DOUBLE the edge where no group covers it. TTyRibbon.AdjustClientRect (597-613) insets the page by only 1px L/R and 2px bottom, so the page is literally the ribbon's body band continued; giving it a different background would show a 1px sliver of the ribbon's own colour framing every page. Both re-parenting paths confirm the identity: the Minimized flyout sets FFlyout.StyleKey := 'TyRibbon' (735) and the group-overflow popup sets FPopup.StyleKey := 'TyRibbon' (1176) — the page's content is re-hosted in surfaces keyed 'TyRibbon', so a page with its own colour would seam against its own flyout. No mark exists on the page that the ribbon does not already make. Minor flag (not a key issue): FillBackground hardcodes corner radius 0 (1050-1051) where S.BorderRadius belongs — inert today (every shipped skin sets TyRibbon border-radius: 0) but it would square off the bottom corners of a rounded ribbon.

### `TTyTreeSelect` keeps `TyComboBox`

RenderTo (TreeSelect.pas:689-754) makes exactly the three marks TTyComboBox.RenderTo makes (ComboBox.pas:834-861): DrawFrame(P, R, S); one left-aligned, ellipsised line drawn inside S.Padding; and the drop indicator through the SAME two-line pair — TyTryDrawGlyphOverride(..., '--glyph-dropdown', S.TextColor) falling back to P.DrawDropChevron — in a button zone measured from the SAME token, ActiveController.Metric('--field-button-width', TyFieldButtonWidth) (TreeSelect.pas:686 vs ComboBox.pas:527-530). Nothing is drawn that a combo does not draw: the dropdown is a real TTyTreeView themed by its own key (DropDown resolves FTree.StyleTypeKey at 543 to shape the popup), and the empty-state hint is not smuggled in — it resolves its own reachable key, ResolveStyle('TyTextHint','',[]) at 731, which is the library's correct pattern for a sub-part. This is a combo field that happens to drop a tree, it sits in the same form row as real combos and must not seam, and sharing the key deliberately inherits the combo's variants (a 'TyComboBox.small' dresses both identically). The intent is documented in three places: the unit header (26-30), GetStyleTypeKey (422) and themes/light.tycss:971-975 ('a TyTreeSelect { ... } rule would be dead CSS that never resolves'). No hardcoded visual values — the control explicitly bails rather than inventing a colour when the theme defines no background (706-712) or no text colour (715-722). Secondary observation, not a verdict flip: TTyCascader's FIELD paints the same three marks yet owns 'TyCascader' — but that key also anchors 'TyCascaderPanel'/'TyCascaderItem' (Cascader.pas:35-43, 1899) for a panel the Cascader draws itself; TreeSelect draws no panel of its own, so the asymmetry is justified.
