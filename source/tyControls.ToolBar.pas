unit tyControls.ToolBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Button,
  tyControls.GlyphButtons, tyControls.ImageCollection,
  tyControls.DropButtons,       // TyDropArrowHit — ONE arrow-zone hit rule for the whole library
  tyControls.Menu,              // TTyPopupMenu — the themed menu a tool button drops
  tyControls.Controller;

const
  { LCL's TToolButton.cDefSeparatorWidth / cDefDividerWidth (comctrls.pp:2144-2145), in logical
    px. Setting Style to a space-holder resizes the button to these, exactly as LCL's SetStyle
    does — a separator that kept a command button's width would leave a hole in the bar. }
  TyToolSeparatorWidth = 8;
  TyToolDividerWidth   = 5;

type
  { LCL's TToolButtonStyle (comctrls.pp:2068), member for member AND in LCL's order.

    The NAMES are copied deliberately: an .lfm stores an enum by identifier, so `Style =
    tbsDropDown` copied out of an LCL form only reads back here if the identifier matches.
    (Same call the status bar already made — TTyStatusPanelStyle is LCL's psText/psOwnerDraw
    verbatim.) The cost is that a unit which uses BOTH `ComCtrls` and this one gets LCL's
    TToolButtonStyle members shadowed by these; qualify (`tyControls.ToolBar.tbsButton`) if a
    form really needs both.

    All six are BUILT. Two of LCL's other properties are not, and for a reason worth recording:
    TToolButton.Marked and TToolButton.Indeterminate are stored, invalidate, and are then read
    by NOTHING in LCL's own Paint or GetButtonDrawDetail — they are lying properties in the
    reference implementation, so copying them would import the defect this pass exists to
    remove. TToolButton.MenuItem is absent too, but only for scope: it copies caption/enabled/
    image/checked off a TMenuItem and pops it, which is a second menu model on top of
    DropdownMenu. }
  TTyToolButtonStyle = (
    tbsButton,      // plain command button: a click fires OnClick
    tbsCheck,       // toggle: a click flips Down; groupable (see Grouped)
    tbsDropDown,    // SPLIT: main area + a right-hand arrow zone with its own hit test
    tbsSeparator,   // space holder: takes room, draws nothing
    tbsDivider,     // space holder with a vertical rule
    tbsButtonDrop   // button with an ATTACHED arrow: any click drops the menu, no split
  );

  TTyToolBar = class;

  TTyToolSeparator = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Align;
    property StyleClass;
    property Controller;
  end;

  { LCL's TToolButton (comctrls.pp:2103) — the toolbar's own button class.

    It lives in THIS unit, next to the bar, for the same reason LCL puts TToolButton next to
    TToolBar: three of its properties are defined RELATIVE TO THE BAR and cannot be honoured
    from outside it. `Grouped` means "one of the run of adjacent grouped check buttons on my
    bar"; `Wrap` means "the bar's row breaks after me"; `Index` is a position in the bar's
    button list. A separate unit would have had to reach back into the bar anyway, and the bar
    would not have been able to see the button at all (a cycle).

    It descends from TTyGlyphButtonBase, so the icon plumbing (Images/ImageName/IconFont/
    GlyphName/GlyphSize/ShowCaption/Spacing) is inherited rather than restated, and the bar's
    existing lend-Images / adopt-ShowCaptions machinery reaches it with no new code.

    NOT from TTySpeedButton, deliberately — see Grouped. }
  TTyToolButton = class(TTyGlyphButtonBase)
  private
    FStyle: TTyToolButtonStyle;
    FGrouped: Boolean;
    FAllowAllUp: Boolean;
    FWrap: Boolean;
    FDropdownMenu: TTyPopupMenu;
    FOnArrowClick: TNotifyEvent;
    { The index LAST WRITTEN through ImageIndex. It is not the icon — ImageName is (see
      ImageIndex) — it is what a write asked for, kept so an unresolvable request survives. }
    FImageIndex: Integer;
    { True while an ImageIndex write has not yet been turned into an ImageName because there
      was no collection to look it up in. Cleared the moment it is resolved, so a later retry
      can never overwrite a name the host set afterwards. }
    FImageIndexPending: Boolean;
    { Device-x of the last left mouse-down (-1 = none). LCL synthesises Click AFTER MouseUp,
      so the arrow-vs-main decision is made from the DOWN position and applied in Click —
      exactly as TTyDropDownButton does it. }
    FDownX: Integer;
    { Test-visible record of the last CheckMenuDropdown: would it have popped a menu? }
    FRequestedPopup: Boolean;
    { True while the GROUP is releasing this button, so the AllowAllUp guard in SetDown —
      which exists to stop the USER un-pressing the only down radio — does not also block the
      group's own bookkeeping. (TTySpeedButton carries the same guard for the same reason.) }
    FInGroupUpdate: Boolean;
    procedure SetStyle(AValue: TTyToolButtonStyle);
    procedure SetGrouped(AValue: Boolean);
    procedure SetAllowAllUp(AValue: Boolean);
    procedure SetWrap(AValue: Boolean);
    procedure SetDropdownMenu(AValue: TTyPopupMenu);
    function GetImageIndex: Integer;
    procedure SetImageIndex(AValue: Integer);
    function GetIndex: Integer;
    function GetToolBar: TTyToolBar;
    { Turn a pending ImageIndex into an ImageName as soon as a collection is available.
      Exactly TWO retry points, because each covers a case the other cannot:
        * TTyToolBar.ApplyToolProperties — the bar handing a collection over. It runs both when
          a tool JOINS a bar that already has one (InsertControl) and when a bar that already
          has tools is GIVEN one (SetImages), which is why there is no SetParent override here:
          one that only covered the join was redundant with this, and a mutation of either left
          the other covering for it.
        * Loaded — the case the bar cannot reach: a button carrying its OWN Images in an .lfm.
          The reader fixes that component reference up AFTER the properties are streamed, so
          ImageIndex was read while Images was still nil, and the write that finally sets it
          goes through an inherited private setter this class cannot hook. }
    procedure ResolveImageIndex;
    { Release this button without consulting AllowAllUp — the group's own bookkeeping.
      LCL writes CurButton.FDown directly for the same reason (toolbutton.inc:645). }
    procedure ForceUp;
    { Ask the host bar to re-run its layout (a Wrap or a Style change moves the rows). }
    procedure RequestBarRelayout;
    { True iff device-x AX is in the arrow zone. tbsDropDown only — every other style is one
      hit zone, which is what makes the split a property of the STYLE and not of the geometry. }
    function IsInArrowZone(AX: Integer): Boolean;
  protected
    { 'TyToolSeparator' for the two space-holder styles, the inherited 'TyButton' otherwise.
      The key follows the STYLE because the ink does: a tbsDivider draws the standalone
      TTyToolSeparator's rule, and giving it a key of its own would let a skin dim one and not
      the other — two spellings of one divider that a theme author must remember to keep in
      step. A command tool button keeps 'TyButton' (it IS a push button) and gets its flat
      toolbar look from the 'ghost' StyleClass the bar hands it when Flat is on, which is the
      one lever LCL's Flat pulls too. }
    function GetStyleTypeKey: string; override;
    { The arrow zone in DEVICE px at APPI, 0 for a style that has none. A THEME metric
      ('--drop-arrow-width'), not a published width: LCL puts DropDownWidth/ButtonDropWidth on
      the TOOLBAR, and in this library a resting visual value belongs to a token. Same metric
      TTyMenuButton reserves, so every trailing chevron in the library is one width. }
    function ArrowZoneWidth(APPI: Integer): Integer;
    { The space-holder's logical width (0 for a real button) — the value SetStyle applies and
      CalculatePreferredSize reports, from one place so they cannot disagree. }
    function SpaceHolderWidth: Integer;
    { Main area + arrow zone, then the inherited glyph/caption draw in the main area and a
      chevron in the zone. tbsDropDown additionally gets the 1px divider that says where the
      second hit zone starts; tbsButtonDrop does NOT (LCL: "not separated from each other"). }
    procedure DrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet); override;
    { A space holder is its fixed width and asks for no caption room; the two arrow styles add
      the zone DrawContent carves off, or AutoSize (and the size FLOOR that rides on it) would
      report a fit while the chevron ate the caption. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { A space holder stacks no ink, so it must not push the bar's rows taller than the tools. }
    function MeasureContentHeight(APPI: Integer): Integer; override;
    { Grouping belongs here and not only in Click: `Btn.Down := True` from code is an ordinary
      way to preselect a radio, and LCL routes the same way (SetDown -> uncheck the group). }
    procedure SetDown(AValue: Boolean); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { The space-holder paint. Its own path rather than a branch inside the button's, because a
      separator has no frame, no padding, no content box and no badge. }
    procedure RenderSpaceHolder(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Loaded; override;
    { The click router. tbsSeparator/tbsDivider swallow it (LCL's CMHitTest declines the hit);
      tbsCheck flips Down first; tbsButtonDrop drops the menu; a click that STARTED in a
      tbsDropDown's arrow zone drops the menu or — only when there is no menu — fires
      OnArrowClick, and never the primary OnClick. }
    procedure Click; override;
    { Fires OnArrowClick. Public and virtual, as LCL's is. }
    procedure ArrowClick; virtual;
    { Pop DropdownMenu if there is one. Returns True iff a menu WOULD be shown, so a headless
      caller learns the decision without a window (the real PopUp is behind HandleAllocated,
      the same seam TTyDropDownButton.DoDropDown uses).
      DIVERGENCE: LCL also requires DropdownMenu.AutoPopup and accepts a MenuItem instead
      (toolbutton.inc:892). Neither applies here — the library's two other drop-down buttons
      ignore AutoPopup as well, so "a menu that is assigned is a menu that drops" is one rule
      across all three. }
    function CheckMenuDropdown: Boolean; virtual;
    { LCL's signature (toolbutton.inc:478). True iff (X, Y) is inside the arrow zone — which
      only a tbsDropDown has. Routed through TyDropArrowHit, the SAME pure rule
      TTyDropDownButton hit-tests with, so the two controls cannot disagree about where an
      arrow zone begins. }
    function PointInArrow(const X, Y: Integer): Boolean;
    { Test seam: run the drop-down decision as an arrow click would, with no GUI PopUp. }
    procedure DropDownForTest;
    { The [AStart..AEnd] span of the group this button belongs to, in the host bar's Buttons[]
      index space. False (and -1/-1) unless it is a GROUPED tbsCheck on a bar — LCL's
      GetGroupBounds contract, and the same three conditions. }
    function GetGroupBounds(out AStart, AEnd: Integer): Boolean;
    { True when the whole group may be up: trivially so when this button is not grouped, and
      otherwise only if SOME member of the group has AllowAllUp (LCL's GroupAllUpAllowed). }
    function GroupAllUpAllowed: Boolean;
    { True after a CheckMenuDropdown that had a menu to pop. }
    property RequestedPopup: Boolean read FRequestedPopup;
    { Position in the host bar's Buttons[] list, or -1 when this button is not on a bar.
      LCL publishes the same read-only property. }
    property Index: Integer read GetIndex;
    { The bar this button sits on, or nil. }
    property ToolBar: TTyToolBar read GetToolBar;
  published
    { Which of the six kinds this button is. Changing it to a space holder resizes the button
      to TyToolSeparatorWidth / TyToolDividerWidth, as LCL's SetStyle does. }
    property Style: TTyToolButtonStyle read FStyle write SetStyle default tbsButton;
    { LCL's ADJACENCY grouping: this button forms an exclusive (radio) set with the run of
      NEIGHBOURING buttons on the same bar that are also Grouped and are tbsCheck — space
      holders inside the run do not break it, anything else does. Pressing one releases the
      others; AllowAllUp lets the whole run go up.

      This is the ONE grouping model on this class. GroupIndex — the numbered model — is
      deliberately NOT published here even though a sibling control has it: they answer the
      same question two ways, and a class carrying both would let a host set a GroupIndex that
      the adjacency rule ignores. TTySpeedButton keeps GroupIndex and is the control to reach
      for when groups must be numbered rather than adjacent; the two are exactly
      inter-translatable (give each maximal Grouped run its own GroupIndex). }
    property Grouped: Boolean read FGrouped write SetGrouped default False;
    { Lets a click on the pressed member of a group release it, leaving the whole group up.
      Setting it re-evaluates the group, as TTySpeedButton's does: turning it OFF on a group
      that is currently all-up would otherwise leave an exclusive group with nothing selected
      until the user happened to click. }
    property AllowAllUp: Boolean read FAllowAllUp write SetAllowAllUp default False;
    { LCL's TRAILING row break: the bar's row ends AFTER this button, and the NEXT one starts a
      new row. Kept trailing on purpose so a ported .lfm means what it says; the bar converts
      it to the layout solver's LEADING flag with the documented one-liner
      `breakBefore[i] := (i > 0) and wrapAfter[i-1]` (see TyToolbarLayout, and
      TyToolWrapToBreakBefore below, which is that line as a function).

      TWO DIVERGENCES, both in the bar's favour and both pinned by tests:
      * LCL reads Wrap ONLY when TToolBar.Wrapable is False (toolbar.inc:1003). Here it is
        honoured in BOTH modes — a division the host asked for in so many words is not a
        surprise, and refusing it would put the feature out of reach of the default bar
        (Wrapable defaults to True).
      * Wrap on the LAST button does nothing here. LCL still bumps its FRowCount for it and
        ends up reporting a row with nothing on it, which the bar would then be sized for.
      Wrap on an INVISIBLE button also does nothing: an invisible tool is not laid out, so it
      has no row to end. And it does nothing on a TTyToolBarEx in overflow mode
      (Wrapable = False there), which by construction has exactly one row. }
    property Wrap: Boolean read FWrap write SetWrap default False;
    { The icon, addressed by POSITION in the effective image collection (normally the one the
      bar lends), instead of by name.

      There is only ONE piece of icon state on this button and it is the inherited ImageName:
      writing ImageIndex looks the position up (TTyImageCollection.NameOf, which is insertion
      order) and stores the NAME, and reading it back reports the current name's position
      (IndexOf). So the two are two spellings of one thing and there is no precedence rule to
      remember — the last write wins because there is nothing else for it to win against.

      A write made before any collection is available (code that sets ImageIndex before
      Parent, or an .lfm, whose component references are fixed up after the properties are
      read) is REMEMBERED and applied the moment one arrives.

      DIVERGENCE from LCL, which keeps the index raw and looks it up at paint: here the name
      is authoritative, so re-ordering the collection does not silently change which icon an
      existing button draws — it changes what its ImageIndex reads back as. -1 means "no icon
      by index" and clears the name (only once ImageIndex has actually been written; a button
      that only ever used ImageName is never touched by this). }
    property ImageIndex: Integer read GetImageIndex write SetImageIndex default -1;
    { The themed menu dropped by a tbsDropDown's arrow zone or by any click on a tbsButtonDrop.
      TTyPopupMenu rather than LCL's TPopupMenu — it IS a TPopupMenu descendant, so this is a
      narrowing and not a different concept, and it is what the library's other two drop-down
      buttons take. FreeNotification-tracked. }
    property DropdownMenu: TTyPopupMenu read FDropdownMenu write SetDropdownMenu;
    { Fired by a click in a tbsDropDown's arrow zone — but only when no DropdownMenu was
      dropped, exactly as LCL suppresses it (toolbutton.inc:170-179): the event is the
      ALTERNATIVE to a menu, not a hook in front of it. If you need to run code BEFORE the
      menu pops (to build it, say), TTyDropDownButton.OnDropDown is that hook. }
    property OnArrowClick: TNotifyEvent read FOnArrowClick write FOnArrowClick;
    { A tool button never takes focus — the point of a toolbar is that clicking it leaves the
      caret where it was. Same call TTySpeedButton makes, and the declared default has to
      agree with the constructor or the streamer writes TabStop into every .lfm. }
    property TabStop default False;
    { The resting pressed state. Inherited from TTyButton and re-listed only to say that on a
      tbsCheck it is the CHECKED state a click flips (and that the group keeps exclusive), where
      on the other styles it is just the ':selected' look. Caption / Enabled / Visible / Hint /
      ShowHint / Align / Anchors / StyleClass / Controller / OnClick all come from the bases. }
    property Down;
  end;

  TTyToolBar = class(TTyCustomControl)
  private
    FButtonHeight: Integer;
    FButtonHeightExplicit: Boolean;
    FButtonSpacing: Integer;
    FIndent: Integer;
    FWrapable: Boolean;
    FShowCaptions: Boolean;
    FFlat: Boolean;
    FImages: TTyImageCollection;
    { The collection this bar last LENT to its tools. A tool still holding it is one we
      handed it to, so we may re-point or take it back; anything else is the host's own
      choice and is left alone. Nil'd with FImages in Notification — a freed collection's
      address can be re-used, and a stale marker would make us adopt a stranger's. }
    FLentImages: TTyImageCollection;
    FInLayout: Boolean;
    function GetButtonHeight: Integer;
    function GetButtonCount: Integer;
    function GetButton(AIndex: Integer): TTyToolButton;
    procedure SetButtonHeight(AValue: Integer);
    procedure SetButtonSpacing(AValue: Integer);
    procedure SetIndent(AValue: Integer);
    procedure SetWrapable(AValue: Boolean);
    procedure SetShowCaptions(AValue: Boolean);
    procedure SetImages(AValue: TTyImageCollection);
    procedure SetFlat(AValue: Boolean);
    procedure Relayout;
  protected
    { The vertical breathing room above the first row and below the last, in logical px.
      Theme-driven (--toolbar-pad-y) rather than a published property: it is chrome, and
      the fallback is 4 — byte-for-byte the value Indent used to supply here, so no
      existing bar changes height. Protected because TTyToolBarEx lays its own row out and
      must use the SAME pad, or the two bars would sit their tools at different heights. }
    function ContentPadY: Integer;
    { Protected rather than private so a test can drive the one call a relayout makes
      without needing a window handle and a live align pass. }
    procedure ApplyToButton(B: TTyButton);
    { Push Images + ShowCaptions onto every tool that can draw an icon. Protected for the
      same reason. }
    procedure ApplyToolProperties;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure InsertControl(AControl: TControl; Index: Integer); override;
    { The bar's TTyToolButton children, in child order — LCL's TToolBar.ButtonCount /
      Buttons[] (comctrls.pp:2367), and the index space TTyToolButton.Index, Grouped and
      GetGroupBounds all speak in.

      Only TTyToolButtons are in it, which is LCL's rule too: its FButtons list holds nothing
      else, so a plain button, an edit or a separator CONTROL sitting between two grouped check
      buttons does not divide their group. (A tbsSeparator tool BUTTON is in the list and, per
      LCL, does not divide one either — see TyToolGroupBounds.)
      An out-of-range index answers nil rather than raising: callers here walk the list while
      a layout is moving under them. }
    property ButtonCount: Integer read GetButtonCount;
    property Buttons[AIndex: Integer]: TTyToolButton read GetButton;
    { Position of AButton in Buttons[], or -1 when it is not one of ours. }
    function IndexOfButton(AButton: TTyToolButton): Integer;
  published
    { Density-aware: unset follows --control-height (classic 24 / modern 38). A host/.lfm value
      pins it (streamed only when explicitly set -- stored FButtonHeightExplicit). }
    property ButtonHeight: Integer read GetButtonHeight write SetButtonHeight stored FButtonHeightExplicit;
    property ButtonSpacing: Integer read FButtonSpacing write SetButtonSpacing default 2;
    { Blank space at the LEADING edge of the bar, before the first tool — and nothing else.
      LCL's TToolBar.Indent (comctrls.pp:2398) means exactly that, and ours used to mean
      two more things besides: it was also the TOP pad every row started at, and the bar's
      auto-grown height was `Indent*2 + rows`. So `Indent := 24` — a perfectly ordinary LCL
      value, used to clear a logo or a leading label — silently made the bar 48 px taller
      and pushed its tools down 24 px, which is not what any LCL form that set it asked for.
      The vertical breathing room is now its own value (ContentPadY, theme token
      --toolbar-pad-y, default 4 = the old Indent default), so the two knobs move apart.

      Still differs from LCL in one respect: LCL's default is 1, ours is 4. That one is left
      alone on purpose — a `default` directive is what decides how every existing .lfm that
      OMITTED the value is read, so changing it would re-indent every toolbar already out
      there. A ported form that relied on LCL's 1 should set Indent := 1 explicitly. }
    property Indent: Integer read FIndent write SetIndent default 4;
    property Wrapable: Boolean read FWrapable write SetWrapable default True;
    { LCL parity: False (the default) makes the tools ICON-ONLY, True draws their captions.
      It reaches every child that CAN draw an icon (TTyGlyphButtonBase — TTyGlyphButton /
      TTySpeedButton / TTyGlyphContainerButton) via AdoptShowCaption, which is a no-op on
      any tool whose ShowCaption the host set itself. A plain TTyButton has no glyph model
      at all and is untouched, and a glyph tool with no icon keeps its caption rather than
      painting an empty box — so the False default can never blank an existing toolbar. }
    property ShowCaptions: Boolean read FShowCaptions write SetShowCaptions default False;
    property Flat: Boolean read FFlat write SetFlat default True;
    { The icon source the tools draw from: a child glyph button that has no Images of its
      own is LENT this collection, so tools only need an ImageName. A tool carrying its own
      collection keeps it — the bar re-points or takes back only the reference IT lent.

      A TTyImageCollection, NOT an LCL TImageList: every icon in this library comes from
      the name-keyed BGRA collection (see tyControls.ImageCollection), so a TImageList here
      could never reach a tool button no matter what a host assigned — which is exactly why
      this property used to do nothing. }
    property Images: TTyImageCollection read FImages write SetImages;
    property Align default alTop;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ AIndent is the LEADING (horizontal) gap before the first tool on every row; ATopPad is the
  vertical gap above the first row. They used to be one number, so a bar could not be indented
  without also being padded — see TTyToolBar.Indent.

  ABreakBefore is a FORCED row division, parallel to AItemSizes: item i opens a new row whether
  or not it would have fitted. It is what LCL's TToolButton.Wrap needs and what the width rule
  alone can never express — a group division the width did not ask for. Same shape and same
  tolerance as TyCoolBarPack's ABreaks (tyControls.CoolBar): a SHORTER array is legal and a
  missing entry reads as False, so a caller that knows only the leading flags may pass just
  those, and an empty array means "no breaks at all".

  Two rules that are not obvious:

  * The flag is LEADING — "item i STARTS a row" — matching TyCoolBarPack. LCL's Wrap is
    TRAILING: toolbar.inc:1003 applies it in the step-to-next-position, so it moves the NEXT
    control. The mapping is `breakBefore[i] := (i > 0) and wrapAfter[i-1]`, and it is pinned by
    a test rather than left for the caller to rediscover. Leading also makes an empty row
    unrepresentable: a break on item 0 has no row above it to leave and is ignored, where LCL's
    trailing Wrap on the LAST button still bumps its FRowCount and leaves the bar a row too tall.

  * The break is honoured REGARDLESS of AWrapable. With AWrapable=False this is exactly LCL's
    behaviour (that is the only mode in which LCL reads Wrap at all); with AWrapable=True we
    additionally let an explicit break compose with the width rule, which LCL does not. Honouring
    a division the host asked for in so many words is not a surprise, and refusing it would put
    the feature out of reach of the default bar — Wrapable defaults to True here. }
function TyToolbarLayout(const AItemSizes: array of TSize; ABarWidth, AIndent, ATopPad, ASpacing, AButtonHeight: Integer; AWrapable: Boolean; out ARows: Integer): TTyRectArray; overload;
function TyToolbarLayout(const AItemSizes: array of TSize; const ABreakBefore: array of Boolean;
  ABarWidth, AIndent, ATopPad, ASpacing, AButtonHeight: Integer; AWrapable: Boolean;
  out ARows: Integer): TTyRectArray; overload;

{ THE SHIFT, as a function rather than as a line every caller re-derives: LCL's Wrap is
  TRAILING ("the row breaks after button i") and TyToolbarLayout's ABreakBefore is LEADING
  ("button i starts a row"), so

      breakBefore[i] := (i > 0) and wrapAfter[i - 1]

  Two things it deliberately cannot express, both of them LCL bugs rather than features:
  it never produces a break on item 0 (there is no item -1 to trail, and a leading break there
  would open an empty row), and it DROPS wrapAfter on the LAST item — LCL bumps its FRowCount
  for that one and reports a row with nothing on it, which is a bar one button-height too tall.
  An empty input gives an empty result. }
function TyToolWrapToBreakBefore(const AWrapAfter: array of Boolean): TBooleanDynArray;

{ LCL's TToolButton.GetGroupBounds (toolbutton.inc:807) as a pure function over the bar's
  button list: the [AStart..AEnd] span of the adjacency group containing AIndex.

  False (with AStart = AEnd = -1) unless item AIndex is itself Grouped AND tbsCheck — which is
  LCL's rule and is what makes `Grouped` inert on a plain command button rather than a lie. The
  run then extends in both directions while the neighbour is Grouped and is one of
  tbsCheck / tbsSeparator / tbsDivider: a space holder INSIDE a run of radios does not divide
  it (you may put a gap between two of them), but a command, drop-down or ungrouped button does.

  Both arrays are parallel to the button list; the shorter one governs, so a caller cannot
  read past either. Headless-testable — no bar, no window, no paint. }
function TyToolGroupBounds(const AGrouped: array of Boolean;
  const AStyles: array of TTyToolButtonStyle; AIndex: Integer;
  out AStart, AEnd: Integer): Boolean;

{ The separator/divider INK, shared by TTyToolSeparator and by a space-holder TTyToolButton so
  a skin physically cannot make the two disagree — they resolve the same 'TyToolSeparator' key
  and then run this same routine. The caller does its own BeginPaint + FillSharpBackdrop first
  (that part needs the control), and passes the already-resolved style.
  ADrawRule = False lays only the seamless backdrop, which is what a tbsSeparator is: room, and
  no ink. }
procedure TyDrawToolSeparatorInk(P: TTyPainter; AWidth, AHeight: Integer;
  const AStyle: TTyStyleSet; ADrawRule: Boolean);

implementation

{ The break-free entry point is a pure DELEGATION, not a second copy of the loop: there is one
  implementation, so "no break set lays out exactly as it did before" is true by construction
  rather than by two bodies being kept in step. Kept as an overload rather than folded into the
  new signature because every existing caller — the control below, and the tests that pin its
  arithmetic — passes no flags, and a source break for all of them buys nothing. }
function TyToolbarLayout(const AItemSizes: array of TSize; ABarWidth, AIndent, ATopPad, ASpacing, AButtonHeight: Integer; AWrapable: Boolean; out ARows: Integer): TTyRectArray;
var
  noBreaks: array of Boolean;   // nil -> Length 0 -> every entry reads as False
begin
  noBreaks := nil;
  Result := TyToolbarLayout(AItemSizes, noBreaks, ABarWidth, AIndent, ATopPad, ASpacing,
    AButtonHeight, AWrapable, ARows);
end;

function TyToolbarLayout(const AItemSizes: array of TSize; const ABreakBefore: array of Boolean;
  ABarWidth, AIndent, ATopPad, ASpacing, AButtonHeight: Integer; AWrapable: Boolean;
  out ARows: Integer): TTyRectArray;
var
  i, x, y: Integer;
  brk: Boolean;
begin
  Result := nil;
  SetLength(Result, Length(AItemSizes));
  ARows := 1;
  x := AIndent; y := ATopPad;
  for i := 0 to High(AItemSizes) do
  begin
    { A missing flag reads as False, so a short (or absent) array is legal — TyCoolBarPack's
      tolerance, and what makes the break-free overload a delegation rather than a fork. }
    brk := (i < Length(ABreakBefore)) and ABreakBefore[i];
    { `i > 0` guards BOTH rules, which is what keeps the break from opening an empty leading
      row. It also leaves the width rule byte-for-byte what it was: with brk always False this
      whole condition collapses to `AWrapable and (i > 0) and overflow` — the original, with its
      operands merely regrouped. The break is deliberately OUTSIDE the AWrapable test: see the
      interface comment for why it is honoured in both modes. }
    if (i > 0) and (brk or (AWrapable and (x + AItemSizes[i].cx > ABarWidth - AIndent))) then
    begin
      x := AIndent; Inc(y, AButtonHeight + ASpacing); Inc(ARows);
    end;
    Result[i].Left := x;
    Result[i].Top := y;
    Result[i].Right := x + AItemSizes[i].cx;
    Result[i].Bottom := y + AButtonHeight;
    Inc(x, AItemSizes[i].cx + ASpacing);
  end;
end;

function TyToolWrapToBreakBefore(const AWrapAfter: array of Boolean): TBooleanDynArray;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AWrapAfter));
  for i := 0 to High(Result) do
    Result[i] := (i > 0) and AWrapAfter[i - 1];
end;

function TyToolGroupBounds(const AGrouped: array of Boolean;
  const AStyles: array of TTyToolButtonStyle; AIndex: Integer;
  out AStart, AEnd: Integer): Boolean;
var
  n: Integer;
begin
  AStart := -1;
  AEnd := -1;
  // The SHORTER array governs: neither loop below may read past either one.
  n := Length(AGrouped);
  if Length(AStyles) < n then n := Length(AStyles);
  // LCL's three conditions, in one place: on a bar (the caller's business), Grouped, tbsCheck.
  Result := (AIndex >= 0) and (AIndex < n) and AGrouped[AIndex] and (AStyles[AIndex] = tbsCheck);
  if not Result then Exit;
  AStart := AIndex;
  AEnd := AIndex;
  while (AStart > 0) and AGrouped[AStart - 1]
    and (AStyles[AStart - 1] in [tbsCheck, tbsSeparator, tbsDivider]) do
    Dec(AStart);
  while (AEnd < n - 1) and AGrouped[AEnd + 1]
    and (AStyles[AEnd + 1] in [tbsCheck, tbsSeparator, tbsDivider]) do
    Inc(AEnd);
end;

{ A 1px hairline / rule fill. Factored out because `Default(TTyFill)` is NOT usable inside
  TTyToolButton: TTyButton publishes a property named `Default`, which shadows the compiler
  intrinsic of that name inside every method of a descendant, and the resulting error
  ("Incompatible types: got Boolean expected TTyFill") points at the assignment rather than at
  the shadowing. One helper, so no method of that class has to know. }
function TyToolRuleFill(AColor: TTyColor): TTyFill;
begin
  Result := Default(TTyFill);
  Result.Kind := tfkSolid;
  Result.Color := AColor;
end;

procedure TyDrawToolSeparatorInk(P: TTyPainter; AWidth, AHeight: Integer;
  const AStyle: TTyStyleSet; ADrawRule: Boolean);
begin
  if tpBackground in AStyle.Present then
    P.FillBackground(Rect(0, 0, AWidth, AHeight), AStyle.Background, 0);   // seamless with the bar
  if not ADrawRule then Exit;
  P.FillBackground(Rect(AWidth div 2, P.Scale(3), AWidth div 2 + 1, AHeight - P.Scale(3)),
    TyToolRuleFill(AStyle.BorderColor), 0);
end;

{ TTyToolSeparator }
constructor TTyToolSeparator.Create(AOwner: TComponent);
begin inherited Create(AOwner); Width := 8; Height := TyDensityHeight(ActiveController, 24); end;
// Its own key, NOT the bar's. The separator draws ink the bar does not — an inset
// vertical rule — and borrowing 'TyToolBar' made that rule the SAME colour as the bar's
// own bottom hairline BY CONSTRUCTION, so a theme could not dim, thicken or suppress the
// divider while keeping the bar's edge (the classic "lighter inset divider on a bordered
// bar"). It needs background too: that fill is what keeps the separator seamless with
// the bar it sits on.
function TTyToolSeparator.GetStyleTypeKey: string; begin Result := 'TyToolSeparator'; end;
procedure TTyToolSeparator.Paint; begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;
procedure TTyToolSeparator.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var P: TTyPainter; S: TTyStyleSet; W, H: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    FillSharpBackdrop(P, Rect(0, 0, W, H));   // photo through the separator on an image theme (no-op on solid)
    // The bg fill (seamless with the bar) + the inset 1px rule now live in TyDrawToolSeparatorInk,
    // which a tbsDivider TTyToolButton runs too — one routine, so the two can never drift apart.
    TyDrawToolSeparatorInk(P, W, H, S, True);
    P.EndPaint;
  finally P.Free; end;
end;

{ ========================================================================== }
{ TTyToolButton                                                              }
{ ========================================================================== }

constructor TTyToolButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FStyle := tbsButton;
  FImageIndex := -1;
  FImageIndexPending := False;
  FDownX := -1;
  FGlyphLayout := glLeft;
  { A tool button is the one button that must NOT take focus: the point of a tool bar is that
    a click on it leaves the caret in the editor the command acts upon. TTyButton turns TabStop
    on for push buttons, so undo it — a bar of ten tools would otherwise plant ten dead stops
    in the Tab cycle. The keyboard path is the mnemonic, not Tab. }
  TabStop := False;
  // LCL's TToolButton.GetControlClassDefaultSize (toolbutton.inc:1207) is 23 x 22. The height
  // rides the density axis because everything else in this library does; the bar overrides it
  // per row anyway, so it only decides what a button dropped OUTSIDE a bar looks like.
  Width := 23;
  Height := TyDensityHeight(ActiveController, 22);
end;

procedure TTyToolButton.Loaded;
begin
  inherited Loaded;
  { The retry for the case the bar cannot reach: a button carrying its OWN Images in an .lfm.
    The reader streams properties first and fixes COMPONENT REFERENCES up afterwards, so
    ImageIndex was read against a nil collection — and the assignment that finally arrives goes
    through TTyGlyphButtonBase's private setter, which this class has no way to hook. Loaded is
    the first moment after the fixup that is ours. }
  ResolveImageIndex;
end;

function TTyToolButton.GetStyleTypeKey: string;
begin
  if FStyle in [tbsSeparator, tbsDivider] then
    Result := 'TyToolSeparator'
  else
    Result := inherited GetStyleTypeKey;   // 'TyButton'
end;

function TTyToolButton.GetToolBar: TTyToolBar;
begin
  if Parent is TTyToolBar then
    Result := TTyToolBar(Parent)
  else
    Result := nil;
end;

function TTyToolButton.GetIndex: Integer;
var
  bar: TTyToolBar;
begin
  bar := GetToolBar;
  if bar = nil then Exit(-1);
  Result := bar.IndexOfButton(Self);
end;

procedure TTyToolButton.RequestBarRelayout;
var
  bar: TTyToolBar;
begin
  if csLoading in ComponentState then Exit;
  bar := GetToolBar;
  // Relayout is private on TTyToolBar; private is UNIT-wide in Object Pascal, which is one
  // more reason this class lives here rather than in a unit of its own.
  if bar <> nil then bar.Relayout;
end;

procedure TTyToolButton.SetStyle(AValue: TTyToolButtonStyle);
begin
  if FStyle = AValue then Exit;
  FStyle := AValue;
  { Order matters: the floor has to move BEFORE the width does. Constraints.MinWidth is
    clamped inside SetBounds, so assigning the 8/5px space-holder width while the old
    command-button minimum is still in force would silently keep the button wide. }
  UpdateSizeConstraints;
  { LCL's SetStyle resizes to the space-holder width (toolbutton.inc:733) — but NOT while
    streaming. Width is declared on TControl and Style on this class, so an .lfm writes Width
    FIRST: without the guard, a separator the designer had widened to 20 would be snapped back
    to 8 by its own Style line on every load, and the designed value could never survive. An
    interactive Style change still snaps, which is what makes the property usable in the IDE. }
  if (FStyle in [tbsSeparator, tbsDivider]) and not (csLoading in ComponentState) then
    Width := SpaceHolderWidth;
  Invalidate;
  RequestBarRelayout;
end;

function TTyToolButton.SpaceHolderWidth: Integer;
begin
  case FStyle of
    tbsSeparator: Result := TyToolSeparatorWidth;
    tbsDivider:   Result := TyToolDividerWidth;
  else
    Result := 0;
  end;
end;

procedure TTyToolButton.SetWrap(AValue: Boolean);
begin
  if FWrap = AValue then Exit;
  FWrap := AValue;
  RequestBarRelayout;   // the rows moved
end;

procedure TTyToolButton.SetDropdownMenu(AValue: TTyPopupMenu);
begin
  if FDropdownMenu = AValue then Exit;
  if FDropdownMenu <> nil then FDropdownMenu.RemoveFreeNotification(Self);
  FDropdownMenu := AValue;
  if FDropdownMenu <> nil then FDropdownMenu.FreeNotification(Self);
  Invalidate;
end;

procedure TTyToolButton.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FDropdownMenu) then
    FDropdownMenu := nil;
end;

{ ---- icon by position ----------------------------------------------------- }

function TTyToolButton.GetImageIndex: Integer;
var
  n: Integer;
begin
  { DERIVED whenever it can be: ImageName is the state, this is a view of it. That is what
    makes "set the name, read the index" and "set the index, read the name" agree without a
    precedence rule. }
  if (Images <> nil) and (ImageName <> '') then
  begin
    n := Images.IndexOf(ImageName);
    if n >= 0 then Exit(n);
  end;
  // Nothing resolvable (no collection yet, no name, or a name this collection does not
  // carry) -> report what was last asked for.
  Result := FImageIndex;
end;

procedure TTyToolButton.SetImageIndex(AValue: Integer);
begin
  if AValue < -1 then AValue := -1;   // one "no icon" value, not a range of them
  FImageIndex := AValue;
  // Mark FIRST: the request exists whether or not it can be served right now, and marking it
  // only when it can be served is how a streamed ImageIndex would silently vanish.
  FImageIndexPending := True;
  ResolveImageIndex;
end;

procedure TTyToolButton.ResolveImageIndex;
begin
  if not FImageIndexPending then Exit;   // nothing outstanding: never touch a host's ImageName
  if Images = nil then Exit;             // still not resolvable; a later retry will get it
  FImageIndexPending := False;
  if FImageIndex < 0 then
    ImageName := ''                      // an explicit -1 clears the icon, as LCL's does
  else
    ImageName := Images.NameOf(FImageIndex);   // '' when the index is past the end
end;

{ ---- grouping ------------------------------------------------------------- }

function TTyToolButton.GetGroupBounds(out AStart, AEnd: Integer): Boolean;
var
  bar: TTyToolBar;
  n, i, me: Integer;
  groupFlags: array of Boolean;
  styles: array of TTyToolButtonStyle;
begin
  AStart := -1;
  AEnd := -1;
  bar := GetToolBar;
  // The three conditions are re-stated by TyToolGroupBounds for item `me`; this early exit
  // only avoids building the arrays for the overwhelmingly common ungrouped case.
  if (bar = nil) or (not FGrouped) or (FStyle <> tbsCheck) then Exit(False);
  n := bar.ButtonCount;
  SetLength(groupFlags, n);
  SetLength(styles, n);
  me := -1;
  for i := 0 to n - 1 do
  begin
    groupFlags[i] := bar.Buttons[i].Grouped;
    styles[i] := bar.Buttons[i].Style;
    if bar.Buttons[i] = Self then me := i;
  end;
  if me < 0 then Exit(False);
  Result := TyToolGroupBounds(groupFlags, styles, me, AStart, AEnd);
end;

function TTyToolButton.GroupAllUpAllowed: Boolean;
var
  s, e, i: Integer;
  bar: TTyToolBar;
begin
  if not GetGroupBounds(s, e) then Exit(True);   // ungrouped: nothing constrains it
  bar := GetToolBar;
  for i := s to e do
    if bar.Buttons[i].AllowAllUp then Exit(True);
  Result := False;
end;

procedure TTyToolButton.ForceUp;
begin
  FInGroupUpdate := True;
  try
    Down := False;
  finally
    FInGroupUpdate := False;
  end;
end;

procedure TTyToolButton.SetDown(AValue: Boolean);
var
  s, e, i: Integer;
  bar: TTyToolBar;
  b: TTyToolButton;
begin
  if Down = AValue then Exit;
  { The group's own bookkeeping (ForceUp) goes straight through: the guard below exists to
    stop the USER releasing the only pressed radio, not to stop the group replacing it. }
  if FInGroupUpdate then
  begin
    inherited SetDown(AValue);
    Exit;
  end;
  // LCL toolbutton.inc:632 — pressing is always allowed; RELEASING a grouped check button
  // needs the group's permission.
  if AValue or (FStyle <> tbsCheck) or GroupAllUpAllowed then
    inherited SetDown(AValue);
  if not Down then Exit;   // it went (or stayed) up: nothing to release
  if not GetGroupBounds(s, e) then Exit;
  bar := GetToolBar;
  for i := s to e do
  begin
    b := bar.Buttons[i];
    if (b <> Self) and (b <> nil) and b.Down then b.ForceUp;
  end;
end;

procedure TTyToolButton.SetGrouped(AValue: Boolean);
var
  s, e, i, j: Integer;
  bar: TTyToolBar;
begin
  if FGrouped = AValue then Exit;
  FGrouped := AValue;
  Invalidate;
  if csLoading in ComponentState then Exit;
  { Joining a group must leave it with at most ONE member down — LCL's SetGrouped
    (toolbutton.inc:659) does the same sweep. Without it, `Grouped := True` on two already-down
    buttons produces an exclusive group with two selections, and the next click makes it look
    as if a release were lost. }
  if not GetGroupBounds(s, e) then Exit;
  bar := GetToolBar;
  for i := s to e - 1 do
    if bar.Buttons[i].Down then
    begin
      for j := i + 1 to e do
        if bar.Buttons[j].Down then bar.Buttons[j].ForceUp;
      Break;
    end;
end;

procedure TTyToolButton.SetAllowAllUp(AValue: Boolean);
var
  s, e, i: Integer;
  bar: TTyToolBar;
  anyDown: Boolean;
begin
  if FAllowAllUp = AValue then Exit;
  FAllowAllUp := AValue;
  { Turning it OFF means "this group must always have exactly one member down". If none is,
    press Self — it is the button the caller was configuring, so it is the least surprising
    one to become the selection. (TTySpeedButton.SetAllowAllUp restores the same invariant;
    a raw field write left an exclusive group with nothing selected until the user clicked.) }
  if AValue then Exit;
  if not GetGroupBounds(s, e) then Exit;
  bar := GetToolBar;
  anyDown := False;
  for i := s to e do
    if bar.Buttons[i].Down then
    begin
      anyDown := True;
      Break;
    end;
  if not anyDown then Down := True;
end;

{ ---- arrow zone / drop-down ----------------------------------------------- }

function TTyToolButton.ArrowZoneWidth(APPI: Integer): Integer;
begin
  if not (FStyle in [tbsDropDown, tbsButtonDrop]) then Exit(0);
  // Same metric and same 96-baseline conversion TTyMenuButton reserves, so a skin that
  // retunes '--drop-arrow-width' moves every chevron in the library together.
  Result := MulDiv(ActiveController.Metric('--drop-arrow-width', TyDefaultDropArrowWidth),
    APPI, 96);
  if Result < 0 then Result := 0;
end;

function TTyToolButton.IsInArrowZone(AX: Integer): Boolean;
begin
  // tbsButtonDrop draws an arrow but is ONE hit zone (LCL: "not separated from each other"),
  // so only tbsDropDown has a zone to be inside.
  if FStyle <> tbsDropDown then Exit(False);
  Result := TyDropArrowHit(AX, Width, ArrowZoneWidth(Font.PixelsPerInch));
end;

function TTyToolButton.PointInArrow(const X, Y: Integer): Boolean;
begin
  Result := (Y >= 0) and (Y <= ClientHeight) and IsInArrowZone(X);
end;

function TTyToolButton.CheckMenuDropdown: Boolean;
var
  p: TPoint;
begin
  Result := (not (csDesigning in ComponentState)) and (FDropdownMenu <> nil);
  FRequestedPopup := Result;
  if not Result then Exit;
  // The themed PopUp needs a live window (ClientToScreen + a GUI form). Headless callers stop
  // after the decision above; only pop for real when mapped.
  if HandleAllocated then
  begin
    p := ClientToScreen(Point(0, Height));
    FDropdownMenu.PopUp(p.X, p.Y);
  end;
end;

procedure TTyToolButton.ArrowClick;
begin
  if Assigned(FOnArrowClick) then FOnArrowClick(Self);
end;

procedure TTyToolButton.DropDownForTest;
begin
  CheckMenuDropdown;
end;

{ ---- clicking ------------------------------------------------------------- }

procedure TTyToolButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  // Remember WHERE the press landed; the native Click that follows the mouse-up reads it to
  // route arrow-zone presses. A non-left button leaves the record cleared so it can never
  // spuriously drop. (TTyDropDownButton.MouseDown, same rule.)
  if Button = mbLeft then FDownX := X else FDownX := -1;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyToolButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  // A release OUTSIDE the client suppresses the native Click that would otherwise consume
  // FDownX, so clear it here — else a later keyboard/mnemonic Click (which never sets FDownX
  // afresh) would misroute a stale arrow-zone press and swallow the primary OnClick.
  if (X < 0) or (Y < 0) or (X >= Width) or (Y >= Height) then FDownX := -1;
end;

procedure TTyToolButton.Click;
var
  inArrow: Boolean;
begin
  if not Enabled then Exit;
  // A space holder is not a control surface. LCL declines the hit outright (CMHitTest,
  // toolbutton.inc:557); doing it here keeps a mnemonic/keyboard Click out too.
  if FStyle in [tbsSeparator, tbsDivider] then
  begin
    FDownX := -1;
    Exit;
  end;
  // Decide from the mouse-DOWN position, then consume it: the next Click without a fresh
  // MouseDown (keyboard, mnemonic) is a primary click by definition.
  inArrow := (FDownX >= 0) and IsInArrowZone(FDownX);
  FDownX := -1;

  if FStyle = tbsButtonDrop then
  begin
    // The whole face drops (LCL routes tbsButtonDrop through CheckMenuDropdown on any press).
    // The menu first, then the ordinary OnClick — the order TTyMenuButton uses, and for its
    // reason: an OnClick handler that frees the button would leave the pop dereferencing
    // freed memory if it ran last.
    CheckMenuDropdown;
    inherited Click;
    Exit;
  end;

  if inArrow then
  begin
    // LCL toolbutton.inc:170-179: the arrow zone NEVER fires the primary OnClick, and
    // OnArrowClick is suppressed when a menu was actually shown.
    if not CheckMenuDropdown then ArrowClick;
    Exit;
  end;

  if FStyle = tbsCheck then Down := not Down;   // SetDown releases the group
  inherited Click;
end;

{ ---- measuring + painting -------------------------------------------------- }

function TTyToolButton.MeasureContentHeight(APPI: Integer): Integer;
begin
  // A space holder stacks no ink. Reporting a caption line here would raise
  // Constraints.MinHeight above the bar's ButtonHeight and make every row that carries a
  // separator taller than every row that does not.
  if FStyle in [tbsSeparator, tbsDivider] then Exit(0);
  Result := inherited MeasureContentHeight(APPI);
end;

procedure TTyToolButton.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  ppi: Integer;
begin
  if FStyle in [tbsSeparator, tbsDivider] then
  begin
    ppi := Font.PixelsPerInch;
    if ppi <= 0 then ppi := 96;
    PreferredWidth := MulDiv(SpaceHolderWidth, ppi, 96);
    PreferredHeight := 0;   // the height axis belongs to whoever lays out the row
    Exit;
  end;
  // Glyph slot, gap and caption come from TTyGlyphButtonBase.
  inherited CalculatePreferredSize(PreferredWidth, PreferredHeight, WithThemeSpace);
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  // DrawContent carves the arrow zone off the SAME content box, so the width has to carry it
  // or AutoSize (and the size FLOOR that rides on this method) would report a fit while the
  // chevron ate the caption. ArrowZoneWidth answers 0 for the styles that have no zone.
  Inc(PreferredWidth, ArrowZoneWidth(ppi));
  if PreferredWidth < 1 then PreferredWidth := 1;
end;

procedure TTyToolButton.DrawContent(APainter: TTyPainter; const AContentRect: TRect;
  const AStyle: TTyStyleSet);
var
  arrowW, divX, boxW: Integer;
  mainRect, arrowRect: TRect;
begin
  if not (FStyle in [tbsDropDown, tbsButtonDrop]) then
  begin
    inherited DrawContent(APainter, AContentRect, AStyle);
    Exit;
  end;
  boxW := AContentRect.Right - AContentRect.Left;
  { Same metric and same 96-baseline conversion ArrowZoneWidth uses (APainter.Scale IS that
    MulDiv), so the drawn zone and the hit-tested zone are the same WIDTH.
    They are not yet at the same OFFSET: this one is measured from the padded content box,
    while IsInArrowZone measures from the control's right edge — so the two are out by the
    theme's right padding. That deviation is inherited from TTyDropDownButton, which hit-tests
    through the very same TyDropArrowHit; correcting it on one control alone would break the
    single rule the two share, so it is recorded in docs/controls/toolbar.md (3.2.1) as a
    both-sites fix rather than silently forked here. }
  arrowW := APainter.Scale(ActiveController.Metric('--drop-arrow-width', TyDefaultDropArrowWidth));
  if arrowW < 0 then arrowW := 0;
  // Never let the zone swallow the whole caption area on a too-narrow button.
  if arrowW >= boxW then arrowW := boxW div 2;

  arrowRect := Rect(AContentRect.Right - arrowW, AContentRect.Top,
    AContentRect.Right, AContentRect.Bottom);
  mainRect := Rect(AContentRect.Left, AContentRect.Top,
    AContentRect.Right - arrowW, AContentRect.Bottom);

  inherited DrawContent(APainter, mainRect, AStyle);   // glyph + caption in what is left

  if arrowW <= 0 then Exit;

  { The DIVIDER is the visible half of the hit test: it is what tells a user that the right end
    of a tbsDropDown is a second target. tbsButtonDrop has one target, so it gets no divider —
    LCL says the same thing ("button with arrow (not separated from each other)"). }
  if FStyle = tbsDropDown then
  begin
    divX := arrowRect.Left;
    APainter.FillBackground(Rect(divX, arrowRect.Top + APainter.Scale(3),
      divX + 1, arrowRect.Bottom - APainter.Scale(3)),
      TyToolRuleFill(AStyle.BorderColor), 0);
  end;
  APainter.DrawDropChevron(arrowRect, AStyle.TextColor);
end;

procedure TTyToolButton.RenderSpaceHolder(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;   // 'TyToolSeparator' — see GetStyleTypeKey
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    FillSharpBackdrop(P, Rect(0, 0, W, H));
    TyDrawToolSeparatorInk(P, W, H, S, FStyle = tbsDivider);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyToolButton.Paint;
begin
  // A space holder has no frame, no padding, no content box and no badge — so it does not go
  // through the button's paint at all.
  if FStyle in [tbsSeparator, tbsDivider] then
    RenderSpaceHolder(Canvas, ClientRect, Font.PixelsPerInch)
  else
    inherited Paint;
end;

{ TTyToolBar }
constructor TTyToolBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls];   // hosts the tool buttons
  FButtonHeight := 24; FButtonHeightExplicit := False;   // follow --control-height (density-aware) until set
  FButtonSpacing := 2; FIndent := 4; FWrapable := True; FFlat := True;
  Align := alTop;
  Width := 300; Height := 30;
end;

function TTyToolBar.GetStyleTypeKey: string; begin Result := 'TyToolBar'; end;

function TTyToolBar.ContentPadY: Integer;
begin
  Result := ActiveController.Metric('--toolbar-pad-y', 4);
  if Result < 0 then Result := 0;
end;

function TTyToolBar.GetButtonCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyToolButton then Inc(Result);
end;

function TTyToolBar.GetButton(AIndex: Integer): TTyToolButton;
var
  i, k: Integer;
begin
  Result := nil;
  if AIndex < 0 then Exit;
  k := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyToolButton then
    begin
      if k = AIndex then Exit(TTyToolButton(Controls[i]));
      Inc(k);
    end;
end;

function TTyToolBar.IndexOfButton(AButton: TTyToolButton): Integer;
var
  i, k: Integer;
begin
  Result := -1;
  if AButton = nil then Exit;
  k := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyToolButton then
    begin
      if Controls[i] = AButton then Exit(k);
      Inc(k);
    end;
end;

function TTyToolBar.GetButtonHeight: Integer;
begin
  if FButtonHeightExplicit then
    Result := FButtonHeight
  else
    Result := TyDensityMetric(ActiveController, 24, '--control-height');
end;
procedure TTyToolBar.SetButtonHeight(AValue: Integer); begin FButtonHeightExplicit := True; if FButtonHeight = AValue then Exit; FButtonHeight := AValue; Relayout; end;
procedure TTyToolBar.SetButtonSpacing(AValue: Integer); begin if FButtonSpacing = AValue then Exit; FButtonSpacing := AValue; Relayout; end;
procedure TTyToolBar.SetIndent(AValue: Integer); begin if FIndent = AValue then Exit; FIndent := AValue; Relayout; end;
procedure TTyToolBar.SetWrapable(AValue: Boolean); begin if FWrapable = AValue then Exit; FWrapable := AValue; Relayout; end;
procedure TTyToolBar.SetShowCaptions(AValue: Boolean); begin if FShowCaptions = AValue then Exit; FShowCaptions := AValue; ApplyToolProperties; Relayout; end;
procedure TTyToolBar.SetFlat(AValue: Boolean); begin if FFlat = AValue then Exit; FFlat := AValue; Relayout; end;

procedure TTyToolBar.SetImages(AValue: TTyImageCollection);
begin
  if FImages = AValue then Exit;
  // FreeNotification, not just the Notification override: opRemove only reaches us for a
  // component we asked about. A collection that is not owned by our owner (created with
  // Owner = nil, or living on another form) would be freed without a word, leaving FImages
  // AND every reference we lent to the tools dangling.
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  ApplyToolProperties;
  Relayout;
end;

procedure TTyToolBar.ApplyToButton(B: TTyButton);
begin
  { A tbsSeparator / tbsDivider tool button is a SPACE HOLDER, not a button: it resolves the
    'TyToolSeparator' key and paints a rule, so stamping the button-family 'ghost' variant on
    it would ask the theme for a rule (TyToolSeparator.ghost) that no skin defines, and would
    also leave a StyleClass behind on a control the host never styled. }
  if (B is TTyToolButton) and (TTyToolButton(B).Style in [tbsSeparator, tbsDivider]) then Exit;
  // Reuse the ghost/flat TTyButton look, but only over a class the bar itself put
  // there. Assigning unconditionally (which is what this did) meant every relayout
  // wiped a caller's StyleClass := 'primary' -- and a relayout runs on any metric
  // change, so the styling vanished at an unpredictable moment rather than at once.
  if FFlat then
  begin
    if B.StyleClass = '' then B.StyleClass := 'ghost';
  end
  else
    if B.StyleClass = 'ghost' then B.StyleClass := '';
  // Images/ShowCaptions are NOT pushed from here: this runs on every relayout (many per
  // resize), and re-asserting host-visible state that often is what made the StyleClass
  // handling above a bug in the first place. They are applied by ApplyToolProperties at
  // the three moments they can actually change -- the two setters and a tool joining.
end;

procedure TTyToolBar.ApplyToolProperties;
var
  i: Integer;
  G: TTyGlyphButtonBase;
begin
  if csDestroying in ComponentState then Exit;
  for i := 0 to ControlCount - 1 do
  begin
    // Only a glyph button has an icon model to point at a collection; a plain TTyButton
    // (or a separator) has nothing to draw an image with, so the bar leaves it alone.
    if not (Controls[i] is TTyGlyphButtonBase) then Continue;
    G := TTyGlyphButtonBase(Controls[i]);
    // Lend the bar's collection ONLY to a tool that has none, or that still holds the one
    // we lent last time. A tool with its own collection keeps it: the bar manages the
    // reference it put there and nothing else.
    if (G.Images = nil) or (G.Images = FLentImages) then
      G.Images := FImages;
    // Container default; a no-op on any tool whose ShowCaption the host wrote itself.
    G.AdoptShowCaption(FShowCaptions);
    { A tool button whose ImageIndex was set before any collection existed has been holding the
      request; the line above may just have handed it the collection that resolves it. (Private
      is unit-wide in Object Pascal, which is why the button can live in this unit and keep its
      retry out of the public surface.) }
    if G is TTyToolButton then TTyToolButton(G).ResolveImageIndex;
  end;
  // Remember what a later pass must recognise as "ours to re-point or take back".
  FLentImages := FImages;
end;

procedure TTyToolBar.InsertControl(AControl: TControl; Index: Integer);
begin
  inherited InsertControl(AControl, Index);
  // A tool can join the bar long after Images/ShowCaptions were set (code that builds the
  // bar top-down, an .lfm whose component references are fixed up last, or TTyToolBarEx
  // handing a button back from its overflow flyout), so the bar's icon source is applied
  // HERE as well as in the setters. Doing it here rather than in the layout pass also
  // means TTyToolBarEx — which overrides AlignControls and never calls ApplyToButton —
  // still hands its tools the bar's icons.
  ApplyToolProperties;
end;

procedure TTyToolBar.Relayout;
begin
  if csDestroying in ComponentState then Exit;
  Realign;        // re-runs AlignControls over the children
  Invalidate;
end;

procedure TTyToolBar.AlignControls(AControl: TControl; var ARect: TRect);
var
  ih: Integer;
  i, n, rows: Integer;
  sizes: array of TSize;
  rects: TTyRectArray;
  ctl: TControl;
  list: array of TControl;
  wrapAfter: array of Boolean;
  breaks: TBooleanDynArray;
  newH, bh, padY: Integer;
begin
  // re-entrancy guard: Height assignment at the end triggers another AlignControls call
  if FInLayout then Exit;
  FInLayout := True;
  try
    // collect visible children in child order
    SetLength(list, ControlCount); n := 0;
    for i := 0 to ControlCount - 1 do
    begin
      ctl := Controls[i];
      if ctl.Visible then begin list[n] := ctl; Inc(n); end;
    end;
    SetLength(list, n); SetLength(sizes, n); SetLength(wrapAfter, n);
    for i := 0 to n - 1 do
    begin
      if list[i] is TTyButton then ApplyToButton(TTyButton(list[i]));
      sizes[i].cx := list[i].Width;
      sizes[i].cy := list[i].Height;  // cy is not used by TyToolbarLayout (AButtonHeight governs row height)
      { TToolButton.Wrap, collected over the VISIBLE tools only — an invisible tool is not laid
        out, so it has no row to end. Any other kind of child reads as False: only a tool button
        carries the flag. }
      wrapAfter[i] := (list[i] is TTyToolButton) and TTyToolButton(list[i]).Wrap;
    end;
    { ButtonHeight is what the bar ASKS for; a child may refuse to be that short. Controls
      whose caption decides their size publish Constraints.MinHeight, and SetBounds clamps to
      it -- so a row sized purely from ButtonHeight left the child overflowing DOWNWARD out
      of its slot: it covered the bar's bottom border and stopped lining up with the children
      that did fit. Take the tallest floor in the row first, then lay out against that. }
    bh := GetButtonHeight;
    for i := 0 to n - 1 do
      if list[i].Constraints.MinHeight > bh then bh := list[i].Constraints.MinHeight;
    padY := ContentPadY;
    { LCL's TRAILING Wrap -> the solver's LEADING break, through the one function that shift
      lives in. With no tool button carrying Wrap the result is all-False, which the solver
      reads exactly as the break-free overload did — so an existing bar does not move a pixel. }
    breaks := TyToolWrapToBreakBefore(wrapAfter);
    rects := TyToolbarLayout(sizes, breaks, ClientWidth, FIndent, padY, FButtonSpacing, bh, FWrapable, rows);
    for i := 0 to n - 1 do
    begin
      { Centre each child in the row. A child SHORTER than the row (a separator, a combo that
        is happy at 24 while a CJK caption needs 29) must sit on the row's centre line, or the
        bar reads as ragged -- which is the second half of the same report. }
      ih := list[i].Height;
      if ih > bh then ih := bh;
      if list[i].Constraints.MinHeight > ih then ih := list[i].Constraints.MinHeight;
      list[i].SetBounds(rects[i].Left, rects[i].Top + (bh - ih) div 2, list[i].Width, ih);
    end;
    // grow the bar to fit the rows when alTop/alBottom
    if (Align in [alTop, alBottom]) and (rows > 0) then
    begin
      // The VERTICAL pad closes the bar, top and bottom -- Indent is horizontal and has no
      // business in a height (a bar indented 24px to clear a logo was 48px taller for it).
      newH := padY*2 + rows*bh + (rows-1)*FButtonSpacing;
      if Height <> newH then
        Height := newH;
    end;
  finally
    FInLayout := False;
  end;
end;

procedure TTyToolBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FImages then FImages := nil;
    // Clear the lent-marker too. It points at the same object; left stale it would be a
    // dangling address that a freshly allocated collection could land on, and the next
    // pass would then mistake a tool's OWN collection for one of ours and overwrite it.
    if AComponent = FLentImages then FLentImages := nil;
  end;
end;

procedure TTyToolBar.Paint; begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;
procedure TTyToolBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var P: TTyPainter; S: TTyStyleSet; W, H, bw: Integer; bg: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    // Lay the form's photo down FIRST so an alpha CSS background tints the photo (glass),
    // like TTyPanel. No-op (False) on solid/non-image themes -> their look is unchanged.
    FillSharpBackdrop(P, Rect(0, 0, W, H));
    // Paint S.Background directly (not a solid bg.Color rebuild) so an alpha() background is
    // honored OVER the backdrop instead of replacing it with an opaque tint.
    if tpBackground in S.Present then P.FillBackground(Rect(0, 0, W, H), S.Background, 0);
    bg := Default(TTyFill); bg.Kind := tfkSolid;
    bw := P.Scale(S.BorderWidth); if bw < 1 then bw := 1;
    if tpBorderColor in S.Present then
    begin
      bg.Color := S.BorderColor;
      P.FillBackground(Rect(0, H - bw, W, H), bg, 0);   // bottom hairline
    end;
    P.EndPaint;
  finally P.Free; end;
end;

end.
