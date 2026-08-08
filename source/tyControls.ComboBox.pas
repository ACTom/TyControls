unit tyControls.ComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, StdCtrls, LCLType, LCLIntf,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.ListBox, tyControls.Popup, tyControls.Edit;
function TyComboTypeAheadMatch(AItems: TStrings; AStart: Integer; const APrefix: string): Integer;
function TyFilterItemsByPrefix(AItems: TStrings; const APrefix: string): TStringList;
{ Position of AText in AItems, or -1. The case-sensitivity switch is AddHistoryItem's
  (LCL passes it per call), so it lives with the list search rather than in the caller. }
function TyComboIndexOfText(AItems: TStrings; const AText: string; ACaseSensitive: Boolean): Integer;

const
  { The classic field height, in logical px -- ONE constant because two places must agree on
    it: Create (the default control Height) and the csSimple field zone (the strip the field
    keeps while the rest of the Height belongs to the embedded list). Both read it through
    TyDensityHeight, so modern density's --control-height still governs. }
  TyComboClassicFieldHeight = 26;

type
  { csDropDownList = read-only (pick from list only). csDropDown = editable field
    with prefix autocomplete (an embedded TTyEdit overlays the text zone).
    csOwnerDrawFixed / csOwnerDrawEditableFixed are those same two shapes with the ROWS
    (and, for the pick-only one, the closed field) handed to the application's OnDrawItem
    instead of painted from the theme -- LCL's stdctrls.pp:266/:268 spelling and meaning.
    csOwnerDrawVariable / csOwnerDrawEditableVariable are the Fixed pair plus per-row
    HEIGHTS: OnMeasureItem is asked for each row, so a list can mix a one-line entry with a
    two-line one. That is the ONLY thing the Variable pair adds -- everything else about
    them, including OnDrawItem, is the Fixed behaviour.

    csSimple is LCL's seventh value (stdctrls.pp:264): the edit field with the list
    PERMANENTLY docked under it -- no popup, no drop arrow, and the control's Height spans
    field + list. All of that is measured off the real Win32 control, not recalled: with
    CBS_SIMPLE the LCL height is honoured verbatim (win32listsl.inc GetComboHeight returns
    FSender.Height), GetComboBoxInfo reports an empty rcButton (no arrow) and a live edit
    child, and CB_GETDROPPEDSTATE answers 1 while CB_SHOWDROPDOWN is documented and observed
    to do nothing -- so here DroppedDown READS True and WRITES are ignored, and
    OnDropDown/OnCloseUp/OnGetItems never fire, because nothing ever opens or closes.

    THE NEW VALUES ARE APPENDED, NOT INSERTED. A .lfm stores the identifier, so order does
    not matter there -- but `default csDropDownList` on the published property stores the
    ORDINAL, and every .lfm that omits Style is read against it. csDropDownList has to stay
    at 0 or every existing form silently changes mode. That is also why csSimple sits at
    ordinal 6 HERE and ordinal 1 in LCL: appending is the streaming contract, LCL's order is
    not. An .lfm moves between the two by identifier and never notices; code that stores
    Ord(Style) or does arithmetic on it is the one thing that diverges, and it is documented
    as such (docs/controls/combobox.md §8.1). }
  TTyComboBoxStyle = (csDropDownList, csDropDown, csOwnerDrawFixed, csOwnerDrawEditableFixed,
                      csOwnerDrawVariable, csOwnerDrawEditableVariable, csSimple);

  { The three questions LCL asks of a combo style through TComboBoxStyleHelper
    (stdctrls.pp:271-278). Plain functions rather than a type helper because a helper on an
    enum is reachable only where the helper's unit is in scope AND nothing else has a helper
    for the same type -- one helper per type wins, silently. }
  { Does an embedded TTyEdit cover the text zone? }
  function TyComboStyleHasEditBox(AStyle: TTyComboBoxStyle): Boolean;
  { Do the drop-down rows belong to OnDrawItem? }
  function TyComboStyleIsOwnerDrawn(AStyle: TTyComboBoxStyle): Boolean;
  { Do the rows get their HEIGHT from OnMeasureItem? LCL: TComboBoxStyleHelper.IsVariable
    (stdctrls.pp:277). Separate from IsOwnerDrawn because they are separate questions --
    every Variable style is owner-drawn, but the Fixed ones share one height. }
  function TyComboStyleIsVariable(AStyle: TTyComboBoxStyle): Boolean;
  { The same style with the edit box taken off -- LCL's SetEditBox(False). What a combo that
    is pick-only BY CONSTRUCTION (the check combo, the colour box) should apply instead of
    swallowing the value whole, so an orthogonal choice like owner-draw still gets through. }
  function TyComboStylePickOnly(AStyle: TTyComboBoxStyle): TTyComboBoxStyle;

type
  { The application paints one row -- or the closed field. LCL's own TDrawItemEvent
    (stdctrls.pp:282) is `(Control: TWinControl; Index: Integer; ARect: TRect;
    State: TOwnerDrawState)` with NO canvas, because there the host reaches it through
    Control.Canvas: LCL's TCustomComboBox descends from TWinControl and hand-makes a
    TControlCanvas (customcombobox.inc:891) which it re-points at whichever DC is being
    drawn -- the edit area on one call, the list on the next.

    THAT IS NOT AVAILABLE HERE and the difference is structural, not a preference. This
    combo descends from TCustomControl, which already owns a Canvas bound to the combo's own
    window; the drop-down rows are painted by a SEPARATE control in a SEPARATE window, so
    Control.Canvas could never be their surface. Reproducing LCL's route would mean shadowing
    an inherited property with a different object -- a handler drawing on the wrong window
    whenever anything reached the ancestor's Canvas instead.

    So the canvas is a parameter, which is what the two owner-draw controls already in this
    library do (TTyTreeView.OnDrawNode, and LCL's OWN menu owner-draw, TMenuDrawItemEvent).
    Sender is the combo either way, so Items[Index] reads the same as it would in LCL. }
  TTyDrawItemEvent = procedure(Sender: TObject; ACanvas: TCanvas; Index: Integer;
    ARect: TRect; AState: TOwnerDrawState) of object;

  { How tall ONE drop-down row should be, in LOGICAL px. LCL's TMeasureItemEvent
    (stdctrls.pp:284) with the same shape: AHeight arrives SEEDED with what the row would
    otherwise be (the pinned ItemHeight, or the list's themed one), and the handler
    overwrites it -- so a handler that only wants to change SOME rows can leave the rest
    alone by not touching the parameter. An answer below 1 is ignored and the seed kept,
    because a zero-height row is not a row, it is a hung paint loop.

    No canvas parameter, and LCL's has none either: measuring is arithmetic on the app's own
    data. A handler that must measure TEXT can reach the combo's Canvas through Sender.
    Index is an index into ITEMS, mapped back for you when the popup is showing the
    autocomplete's filtered subset -- the same guarantee OnDrawItem gives. }
  TTyMeasureItemEvent = procedure(Sender: TObject; Index: Integer;
    var AHeight: Integer) of object;

  { One collected owner-draw row: the rect the list actually painted it in, the index into
    the COMBO's Items (not the popup list's -- they differ under the autocomplete filter),
    and the state the handler is told about. }
  TTyComboRowDraw = record
    R: TRect;
    SrcIndex: Integer;
    St: TOwnerDrawState;
  end;

  TTyComboBox = class(TTyCustomControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FText: TCaption;
    FDropDownCount: Integer;
    FSorted: Boolean;
    FMaxLength: Integer;
    FCharCase: TEditCharCase;
    { 0 = follow the popup list's own (themed, density-aware) row height; > 0 pins it.
      Kept as a combo-level value so the height is known BEFORE the popup list exists
      and so a .lfm can stream it. }
    FItemHeight: Integer;
    { 0 = the dropdown is exactly as wide as the closed field; > 0 is a MINIMUM width in
      logical px, which is how LCL spells "let the list be wider than the field". }
    FItemWidth: Integer;
    FTextHint: TCaption;
    FReadOnly: Boolean;
    { Editable-mode (csDropDown) state }
    FStyle: TTyComboBoxStyle;
    FEditor: TTyEdit;             // embedded edit field; owned by Self, parented to Self
    FVisibleItems: TStringList;   // prefix-filtered subset shown in the autocomplete popup
    FSyncingText: Boolean;        // guard: True while we set FEditor.Text programmatically
    FShowingPopup: Boolean;       // guard: True during the autocomplete first-open focus dance
    FOnChange: TNotifyEvent;
    FOnSelect: TNotifyEvent;
    FOnDropDown: TNotifyEvent;
    FOnCloseUp: TNotifyEvent;
    FOnGetItems: TNotifyEvent;
    { Dropdown popup state }
    FPopup: TTyDropdownPopup; // lazy; created on first DropDown; freed in Destroy
    FPopupList: TTyListBox;   // owned by Self; parented into FPopup.Form via SetContent --
    // or, in csSimple, docked as a child of the combo itself (same instance, same class,
    // whichever shape the Style asks for; see AttachEmbeddedList/DetachEmbeddedList)
    { Type-ahead state }
    FTypeAhead: string;
    FTypeAheadTick: QWord;
    { Owner-draw state. FRowDraw is filled while the popup list paints and drained
      immediately after it composites — see DispatchRowOwnerDraw. }
    FOnDrawItem: TTyDrawItemEvent;
    FRowDraw: array of TTyComboRowDraw;
    FRowDrawCount: Integer;
    { Per-row heights (the two Variable styles). }
    FOnMeasureItem: TTyMeasureItemEvent;
    procedure SetOnDrawItem(const AValue: TTyDrawItemEvent);
    procedure SetOnMeasureItem(const AValue: TTyMeasureItemEvent);
    { OnDrawItem's Index is an index into ITEMS. The popup may be holding the
      prefix-filtered subset instead, so map it back. }
    function RowSourceIndex(AList: TTyListBox; ARow: Integer): Integer;
    procedure SetItems(const AValue: TStringList);
    procedure SetItemIndex(const AValue: Integer);
    procedure SetText(const AValue: TCaption);
    procedure SetDropDownCount(const AValue: Integer);
    procedure SetSorted(const AValue: Boolean);
    procedure SetMaxLength(const AValue: Integer);
    procedure SetCharCase(const AValue: TEditCharCase);
    procedure SetItemHeight(const AValue: Integer);
    procedure SetItemWidth(const AValue: Integer);
    procedure SetTextHint(const AValue: TCaption);
    procedure SetReadOnly(const AValue: Boolean);
    function  GetDroppedDown: Boolean;
    procedure SetDroppedDown(const AValue: Boolean);
    { The edit portion's selection API. All four route to the embedded TTyEdit and are
      quiet no-ops in csDropDownList, where there is no editable run to select. }
    function  GetSelStart: Integer;
    procedure SetSelStart(const AValue: Integer);
    function  GetSelLength: Integer;
    procedure SetSelLength(const AValue: Integer);
    function  GetSelText: string;
    procedure SetSelText(const AValue: string);
    { Set the embedded editor's text under the FSyncingText guard (exception-safe),
      so a programmatic write never re-triggers the autocomplete filter. }
    procedure SetEditorText(const S: string);
    procedure EditorChange(Sender: TObject);
    { The autocomplete popup shows non-activating (editor keeps focus), so it never
      fires OnDeactivate and the popup form's key handler never runs — the editable
      field drives close: OnExit closes on focus-out, OnKeyDown handles Escape. }
    procedure EditorExit(Sender: TObject);
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LayoutEditor;
    procedure DropDownFiltered;
    { --- csSimple: the permanently-docked list ----------------------------------------
      The embedded list IS FPopupList -- the same instance the popup styles show, made by
      the same CreatePopupList factory, so a subclass's swatch/preview rows paint and
      hit-test identically in both shapes. Two lists of the same class would already be one
      too many; a second ROW PAINTER would be the classic divergence this shares an
      instance to rule out. Attach re-parents it from the popup form (or nowhere) into the
      combo below the field zone; Detach hands it back. }
    procedure EnsureListBox;
    procedure AttachEmbeddedList;
    procedure DetachEmbeddedList;
    procedure LayoutEmbeddedList;
    { The windowed-ghost guard: a windowed child erases to its LCL Color before painting,
      so the embedded list's Color is set to the theme's list surface -- never left at the
      parent's Color (memory/windowed-ghost-erases-to-parent-color). }
    procedure ApplyEmbeddedListColor;
    { Mirror Items / the selection into the embedded list with its OnChange detached --
      the same detach-assign-reattach DropDown uses, because TTyListBox.SelectItem fires
      OnChange and the echo would commit right back into us. }
    procedure SyncEmbeddedItems;
    procedure SyncEmbeddedSelection;
    { The strip the FIELD keeps in csSimple, in device px: the themed field height (the
      same TyDensityHeight(...) number Create sizes the whole control by elsewhere). }
    function FieldZoneHeight(APPI: Integer): Integer;
    function PointInChevron(const P: TPoint): Boolean;
    { Re-locate FItemIndex from the currently-selected text after the item list
      has been reordered (e.g. by sorting). Keeps the SAME item selected. }
    procedure ResyncIndexFromText;
    { Fires when the underlying TStringList mutates (add/insert/delete). Lets us
      keep FItemIndex pinned to its item while Sorted reorders insertions. }
    procedure ItemsChanged(Sender: TObject);
    function ButtonWidthLogical: Integer;
    { User-driven selection: applies AIndex via SelectItem and fires OnSelect
      only when the selection actually changed. Distinct from the programmatic
      ItemIndex setter, which fires OnChange but never OnSelect. }
    procedure UserSelect(AIndex: Integer);
    { Lazily create the popup helper + list box (shared by DropDown/DropDownFiltered). }
    procedure EnsurePopup;
    { Popup event handlers }
    procedure PopupListChange(Sender: TObject);
    procedure PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PopupClosed(Sender: TObject);
    procedure DeferredCloseUp(Data: PtrInt);
  protected
    { Guard: tick at last CloseUp. Click reopens only if > 200ms have passed.
      Mirrored from FPopup.CloseUpTick (via PopupClosed) so test subclasses can
      still manipulate it (e.g. AgeCloseUpTick) without accessing FPopup directly. }
    FCloseUpTick: QWord;
    { False = do not write Items into the .lfm (see ItemsStored). A subclass whose OWN
      published member is the row set (TTyComboBoxEx's ItemsEx) clears this: writing both
      would put two sources of truth for one list into the same file, and the reader
      applies them in declaration order — ancestor first — so the rows would be built
      twice. READING an Items block is unaffected, so older .lfm files still load. }
    FItemsStreamed: Boolean;
    procedure SetController(AValue: TTyStyleController); override;
    { Headless-testable popup-height calculation: DropDownCount governs how many
      rows are visible before the dropdown scrolls. Separated from DropDown so it
      can be exercised without building a real win32 popup form. }
    function ComputePopupHeight(APPI: Integer): Integer;
    { The height of the first min(ACount, DropDownCount) rows of whatever the popup list is
      CURRENTLY holding, plus the 2px frame chrome. Factored out because the plain drop and
      the autocomplete's filtered one differ in exactly one number -- how many rows there
      are -- and because with per-row heights the answer is a SUM, not a multiplication, so
      having two copies of it would mean two places to get the measure calls right. }
    function PopupHeightFor(ACount, APPI: Integer): Integer;
    { The dropdown's width: the field, widened to ItemWidth when that is larger. Same
      separation as ComputePopupHeight — one formula, exercised headless. }
    function ComputePopupWidth(APPI: Integer): Integer;
    procedure DoSelect; virtual;
    { Fires when the editable (csDropDown) field loses focus with committed text.
      Default no-op; TTyMRUComboBox overrides it to remember the typed value. }
    procedure DoEditorCommit; virtual;
    { A row was picked in the popup (the csDropDownList path). Default: commit it via
      UserSelect and close the dropdown. TTyCheckComboBox overrides this to toggle a
      checkbox and KEEP the popup open (multi-select) instead of committing/closing. }
    procedure DoPopupPick(AIndex: Integer); virtual;
    procedure DoDropDown; virtual;
    procedure DoCloseUp; virtual;
    { Items was mutated (add / insert / delete / clear / assign / a sorted reorder). Fires
      BEFORE the selection is re-pinned, so a subclass keeping a side model per row
      (TTyComboBoxEx's ItemsEx) can reconcile it while the list is still the truth. }
    procedure DoItemsChanged; virtual;
    function ItemsStored: Boolean;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    // Field content paint (default: the selected item's text). A subclass draws a
    // swatch / glyph + text; ATextRect is the field's text zone (left of the chevron).
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); virtual;
    { Paints TextHint into the field when there is nothing else to show. Separate so a
      subclass that REPLACES PaintFieldContent (image rows, a checked-items summary) can
      still opt its own empty state into the placeholder instead of losing it. }
    procedure PaintTextHint(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
    // Factory for the drop-down list (default: a plain TTyListBox). A subclass returns a
    // custom TTyListBox (e.g. one whose PaintItemContent draws colour swatches).
    function CreatePopupList: TTyListBox; virtual;
    // Style setter is virtual so a subclass can lock the mode (e.g. TTyColorBox forces
    // csDropDownList — a filtered editable popup would desync its per-item swatches).
    procedure SetStyle(AValue: TTyComboBoxStyle); virtual;
    { The state the CLOSED FIELD's OnDrawItem call carries. odComboBoxEdit is how a shared
      handler tells "this is the field" from "this is a row" (LCLType:1163; Windows'
      ODS_COMBOBOXEDIT). odBackgroundPainted is always in it: DrawFrame has already laid the
      themed surface down, so a handler that only writes text sits on the right background
      instead of painting one of its own over ours -- and it has to be TOLD, or it will. }
    function FieldOwnerDrawState: TOwnerDrawState;
    procedure Paint; override;
    procedure Resize; override;
    { After streaming: bounds are final only now, so the csSimple layout (field zone +
      docked list) is re-run against the Height the .lfm actually carried. }
    procedure Loaded; override;
    procedure Click; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetStyleTypeKey: string; override;
    { Test seam: True when the embedded editor exists and is visible (csDropDown). }
    function EditorVisibleForTest: Boolean;
    { Test seam: the embedded editor's MaxLength (-1 when the editor is absent). }
    function EditorMaxLengthForTest: Integer;
    { Test seams: what actually reached the embedded editor. A forwarding property that
      stores but never forwards is the failure mode these pin. }
    function EditorTextHintForTest: string;
    function EditorReadOnlyForTest: Boolean;
    { Test seams for the two popup-geometry formulas (the protected ones are where the
      sizing lives; these let a headless test pin the arithmetic, not just the setter). }
    function ComputePopupHeightForTest(APPI: Integer): Integer;
    function ComputePopupWidthForTest(APPI: Integer): Integer;
    { Test seam: the csSimple field strip in device px -- what the docked list's Top must
      equal, so a geometry test pins the EDGE and not a centre. }
    function FieldZoneHeightForTest(APPI: Integer): Integer;
    { Test seams that drive the REAL editor paths headlessly. SimulateTypedText writes the
      embedded editor's text WITHOUT the FSyncingText guard, so EditorChange runs exactly
      as it does for a keystroke (the guard exists to tell programmatic seeding apart from
      typing -- this seam IS the typing). SimulateEditorKey routes through EditorKeyDown
      and returns what is LEFT of the key, so a test can pin both halves: a taken key
      comes back 0, an untaken one (csSimple must NOT swallow Escape) comes back as sent. }
    procedure SimulateTypedTextForTest(const S: string);
    function SimulateEditorKeyForTest(AKey: Word): Word;
    procedure SelectItem(AIndex: Integer); virtual;
    procedure DropDown; virtual;
    procedure CloseUp;
    { Highlight the whole edit run (csDropDown only). LCL's combo has this so a field can
      be pre-selected on focus-in. }
    procedure SelectAll;
    { MRU promotion, on EVERY combo the way LCL has it: move AItem to row 0, drop its old
      position, trim the tail past AMaxHistoryCount, optionally make it the field text.
      TTyMRUComboBox's AddToHistory is the same idea with the cap as a property. }
    procedure AddHistoryItem(const AItem: string; AMaxHistoryCount: Integer;
      ASetAsText, ACaseSensitive: Boolean); overload;
    procedure AddHistoryItem(const AItem: string; AnObject: TObject;
      AMaxHistoryCount: Integer; ASetAsText, ACaseSensitive: Boolean); overload;
    { Expose popup list for headless tests and internal use }
    function PopupList: TTyListBox;
    { --- the drop-down row owner-draw protocol --------------------------------------
      True when the application has actually taken the rows over: an owner-draw Style AND a
      handler. Without the handler the themed default stays, so assigning Style alone can
      never blank a control -- which is the failure mode of "owner-draw means paint
      nothing" and it is not worth reproducing.

      The three calls below are what a drop-down list makes to join in. They are METHODS on
      the combo (with free-function wrappers underneath) rather than an ancestor class,
      because the popup lists in this family do not share one: TTyCheckComboBox's descends
      from TTyCheckListBox, everyone else's from TTyListBox, and single inheritance means no
      shim class can reach both.

        Begin  -- before the list paints; drops anything a previous paint left behind.
        Collect -- from PaintItemContent, per row. True = the host owns this row, so the
                  default CONTENT is skipped; the themed row background stays (RenderTo has
                  already drawn it, and odBackgroundPainted says so).
        Dispatch -- after the list's paint has composited. THIS IS THE ONLY PLACE THE HOST
                  CALLBACK MAY RUN: the painter builds into a BGRA layer that EndPaint
                  blits over the canvas, so anything a handler drew before that point is
                  simply erased (commit d427095, and the two owner-draw controls that
                  already dispatch this way). }
    function OwnerDrawsRows: Boolean;
    procedure BeginRowOwnerDraw;
    function CollectRowOwnerDraw(AList: TTyListBox; const ARowRect: TRect;
      AIndex: Integer): Boolean;
    procedure DispatchRowOwnerDraw(ACanvas: TCanvas; const ARect: TRect);
    { Test seam: how many rows the last list paint handed to the host. }
    function RowOwnerDrawCountForTest: Integer;
    { --- the per-row HEIGHT protocol -------------------------------------------------
      True when the rows really do have their own heights: a Variable Style AND a handler.
      Without the handler the one shared height stays, so assigning Style alone can never
      collapse a list -- the same rule OwnerDrawsRows follows, for the same reason.

      MeasureRowHeight is the one call a drop-down list makes: hand it the list, the row and
      the height the row would otherwise have, and it comes back with the host's answer (or
      the seed, unchanged, when nobody is listening). It is a METHOD with a free-function
      wrapper for the same reason the draw protocol is -- the popup lists in this family do
      not share an ancestor, TTyCheckComboBox's descends from TTyCheckListBox.

      NOT CACHED, deliberately: this is called from the row walkers, so a handler is asked
      about a row several times per layout. A dropdown shows DropDownCount rows (8 by
      default) and OnMeasureItem is arithmetic on the app's own data; a cache would have to
      be invalidated on Items, on Style, on the handler and on density, and getting one of
      those wrong is a stale row height nobody can explain. If a host ever needs the calls
      counted down, it can memoise inside its own handler. }
    function MeasuresRows: Boolean;
    function MeasureRowHeight(AList: TTyListBox; ARow, ADefault: Integer): Integer;
    { The three control-level list methods LCL's combo has. Clear empties Items AND blanks
      Text -- doing only the first leaves the field displaying an item that is no longer in
      the list, which is the bug you get from calling Items.Clear by hand. }
    procedure Clear;
    procedure ClearSelection;
    { virtual + overload so a subclass can both REDIRECT this (TTyComboBoxEx routes the
      object into its per-row entry instead of the raw Objects[] slot, which it owns) and
      ADD an image/state-carrying form beside it without hiding this one. }
    procedure AddItem(const AItem: string; AnObject: TObject); virtual; overload;
    function Count: Integer;
    { Read/WRITE, as on LCL's combo: assigning True opens the list, False closes it. It
      was a bare function here, so `Combo.DroppedDown := True` — the idiom for opening a
      combo from a button or a shortcut — did not compile. Public, not published: the
      open/closed state is runtime, never something a .lfm should carry. }
    property DroppedDown: Boolean read GetDroppedDown write SetDroppedDown;
    { The edit portion's selection (UTF-8 positions), forwarded to the embedded editor.
      Zeros in csDropDownList, where nothing is editable. }
    property SelStart: Integer read GetSelStart write SetSelStart;
    property SelLength: Integer read GetSelLength write SetSelLength;
    property SelText: string read GetSelText write SetSelText;
  published
    property Items: TStringList read FItems write SetItems stored ItemsStored;
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property Text: TCaption read FText write SetText;
    { Max number of rows visible in the dropdown before it scrolls (LCL default 8). }
    property DropDownCount: Integer read FDropDownCount write SetDropDownCount default 8;
    { When True, Items are kept in ascending (case-insensitive) order and the
      previously-selected item stays selected (tracked by its text). }
    property Sorted: Boolean read FSorted write SetSorted default False;
    { MaxLength/CharCase apply to the embedded edit field. In csDropDown mode they
      are forwarded to that field (CharCase transforms typed text; MaxLength caps
      its length). In csDropDownList mode there is no editable text, so they are
      inert — published for native-API parity and streaming round-trip. }
    property MaxLength: Integer read FMaxLength write SetMaxLength default 0;
    property CharCase: TEditCharCase read FCharCase write SetCharCase default ecNormal;
    { csDropDownList (default) = read-only; csDropDown = editable + prefix autocomplete;
      csOwnerDrawFixed / csOwnerDrawEditableFixed = the same two with the rows drawn by
      OnDrawItem; csOwnerDrawVariable / csOwnerDrawEditableVariable = those two again, with
      each row's HEIGHT coming from OnMeasureItem; csSimple = the editable field with the
      list PERMANENTLY docked under it (Height spans field + list, no popup, no arrow).
      NOTE the default is the OPPOSITE of LCL's csDropDown, and deliberately so: every
      .lfm in this repo and in users' projects omits Style and expects a pick-only combo.
      See docs/controls/combobox.md §8.1 for the full value table, including csSimple's
      ordinal divergence from LCL (6 here, 1 there -- appended, never inserted). }
    property Style: TTyComboBoxStyle read FStyle write SetStyle default csDropDownList;
    { Pixel height of one dropdown row. 0 (default) = follow the theme's --item-height,
      so a density change still moves the rows; a positive value pins them. }
    property ItemHeight: Integer read FItemHeight write SetItemHeight default 0;
    { MINIMUM dropdown width in logical px. 0 (default) = exactly the field width. Lets a
      list of long paths open wider than the closed combo. }
    property ItemWidth: Integer read FItemWidth write SetItemWidth default 0;
    { Placeholder shown while the field is empty. Forwarded to the embedded editor in
      csDropDown; painted by the field itself in csDropDownList, which has no editor. }
    property TextHint: TCaption read FTextHint write SetTextHint;
    { Rejects typing in the edit portion while the dropdown still works. Inert in
      csDropDownList, which has no editable text at all. }
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    { The application paints a drop-down row -- and, in csOwnerDrawFixed, the closed field.
      LCL's OnDrawItem (stdctrls.pp:399) plus the canvas its signature leaves implicit; see
      TTyDrawItemEvent for why that one parameter had to be added. Runs only when Style is
      one of the owner-draw values; the handler is called AFTER the themed background is down
      (odBackgroundPainted) and after the painter has composited, on the real canvas.

      ARect is the row's own painted rect and the clip is set to it, so a handler cannot
      bleed into its neighbour. Index is an index into Items -- mapped back for you when the
      popup is showing the autocomplete's filtered subset. }
    property OnDrawItem: TTyDrawItemEvent read FOnDrawItem write SetOnDrawItem;
    { The application says how tall ONE drop-down row is. LCL's OnMeasureItem
      (stdctrls.pp:402). Consulted ONLY by the two Variable styles -- csOwnerDrawVariable
      and csOwnerDrawEditableVariable -- because they are the only ones that have per-row
      heights at all; under any other Style every row is ItemHeight and this never fires.
      That pairing is the reason the event and the styles landed together: an event no Style
      could reach would be a published property the control does not honour. }
    property OnMeasureItem: TTyMeasureItemEvent read FOnMeasureItem write SetOnMeasureItem;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
    property OnCloseUp: TNotifyEvent read FOnCloseUp write FOnCloseUp;
    { Fires as the list is about to be shown, so the application can fill Items
      just-in-time. It runs BEFORE DropDown's empty-list guard — that ordering is the
      whole point, since a lazy combo starts empty and would otherwise never open. }
    property OnGetItems: TNotifyEvent read FOnGetItems write FOnGetItems;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

  { The plain combo's drop-down list, and the reference implementation of the row
    owner-draw protocol: three calls, nothing else. A popup list that already descends from
    TTyListBox should descend from THIS instead and add one line to its PaintItemContent
    (the Collect-and-skip); one that descends from somewhere else (TTyCheckComboPopupList,
    off TTyCheckListBox) copies the Paint body below verbatim. }
  TTyComboPopupList = class(TTyListBox)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    { Per-row heights, asked of the owning combo. Inert unless the combo is in a Variable
      Style with a handler, in which case the seed -- the one shared height this would
      otherwise be -- goes out as OnMeasureItem's starting value and comes back as the
      row's own. }
    function RowHeight(AIndex: Integer): Integer; override;
    procedure Paint; override;
  public
    { Paint the rows AND run the owning combo's post-composite owner-draw pass. Public and
      canvas-taking so a headless test can drive the whole dispatch into a bitmap -- Paint
      needs a window handle, and the defect this pass exists to avoid is only visible in
      the pixels. }
    procedure RenderWithOwnerDraw(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

{ The protocol as free functions, for a popup list whose ancestor is fixed elsewhere. Each
  finds the combo through the list's Owner -- CreatePopupList does Create(Self) throughout
  this family, which is the same route every one of these lists already takes to reach its
  combo from PaintItemContent. A list with no combo owner is left alone. }
procedure TyComboBeginRowOwnerDraw(AList: TTyListBox);
function  TyComboCollectRowOwnerDraw(AList: TTyListBox; const ARowRect: TRect;
  AIndex: Integer): Boolean;
procedure TyComboDispatchRowOwnerDraw(AList: TTyListBox; ACanvas: TCanvas; const ARect: TRect);
{ The height half of the same story: a popup list whose ancestor is fixed elsewhere calls
  this from its own RowHeight override. ADefault is what the row would be without a host
  answer, and it is what comes back when there is none. }
function  TyComboMeasureRowHeight(AList: TTyListBox; ARow, ADefault: Integer): Integer;

implementation
uses
  Math, tyControls.QtWS, tyControls.PlatformWS;

function TyComboStyleHasEditBox(AStyle: TTyComboBoxStyle): Boolean;
begin
  { csSimple is in the True row of LCL's own table (customcombobox.inc:1255): the simple
    combo IS an edit with a list under it. }
  Result := AStyle in [csDropDown, csOwnerDrawEditableFixed, csOwnerDrawEditableVariable,
                       csSimple];
end;

function TyComboStyleIsOwnerDrawn(AStyle: TTyComboBoxStyle): Boolean;
begin
  Result := AStyle in [csOwnerDrawFixed, csOwnerDrawEditableFixed,
                       csOwnerDrawVariable, csOwnerDrawEditableVariable];
end;

function TyComboStyleIsVariable(AStyle: TTyComboBoxStyle): Boolean;
begin
  Result := AStyle in [csOwnerDrawVariable, csOwnerDrawEditableVariable];
end;

function TyComboStylePickOnly(AStyle: TTyComboBoxStyle): TTyComboBoxStyle;
begin
  case AStyle of
    csDropDown:                  Result := csDropDownList;
    csOwnerDrawEditableFixed:    Result := csOwnerDrawFixed;
    csOwnerDrawEditableVariable: Result := csOwnerDrawVariable;
    { LCL's own SetEditBox(False) row for csSimple is csDropDownList
      (customcombobox.inc:1300): there is no pick-only simple value in the enum, so taking
      the edit box off a simple combo takes the permanent list with it. The pick-only
      family (colour/check/office/shell/filter/advanced) therefore lands on csDropDownList
      when handed csSimple -- decided HERE, once, tested per class, and written up in
      docs/controls/combobox.md §8.2. A host that wants a permanently-visible pick-only
      list has the corresponding LIST control (TTyColorListBox, TTyCheckListBox, ...);
      that is LCL's answer too, which is why its mapping looks the way it does. }
    csSimple:                    Result := csDropDownList;
  else
    Result := AStyle;
  end;
end;

function TyComboOwnerOf(AList: TTyListBox): TTyComboBox;
begin
  Result := nil;
  if (AList <> nil) and (AList.Owner is TTyComboBox) then
    Result := TTyComboBox(AList.Owner);
end;

procedure TyComboBeginRowOwnerDraw(AList: TTyListBox);
var C: TTyComboBox;
begin
  C := TyComboOwnerOf(AList);
  if C <> nil then C.BeginRowOwnerDraw;
end;

function TyComboCollectRowOwnerDraw(AList: TTyListBox; const ARowRect: TRect;
  AIndex: Integer): Boolean;
var C: TTyComboBox;
begin
  C := TyComboOwnerOf(AList);
  Result := (C <> nil) and C.CollectRowOwnerDraw(AList, ARowRect, AIndex);
end;

procedure TyComboDispatchRowOwnerDraw(AList: TTyListBox; ACanvas: TCanvas; const ARect: TRect);
var C: TTyComboBox;
begin
  C := TyComboOwnerOf(AList);
  if C <> nil then C.DispatchRowOwnerDraw(ACanvas, ARect);
end;

function TyComboMeasureRowHeight(AList: TTyListBox; ARow, ADefault: Integer): Integer;
var C: TTyComboBox;
begin
  C := TyComboOwnerOf(AList);
  if C = nil then Exit(ADefault);
  Result := C.MeasureRowHeight(AList, ARow, ADefault);
end;

{ TTyComboPopupList }

procedure TTyComboPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  { Collect-and-skip. The row BACKGROUND is already down (RenderTo fills it before calling
    here), so an owner-drawn row still gets its hover / selection highlight and the handler
    is told so via odBackgroundPainted -- the same division TTyMenuView draws. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  inherited PaintItemContent(P, ARowRect, AIndex, AStyle);
end;

function TTyComboPopupList.RowHeight(AIndex: Integer): Integer;
begin
  Result := TyComboMeasureRowHeight(Self, AIndex, inherited RowHeight(AIndex));
end;

procedure TTyComboPopupList.RenderWithOwnerDraw(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  TyComboBeginRowOwnerDraw(Self);
  RenderTo(ACanvas, ARect, APPI);   // collects during the row loop; ends with EndPaint
  TyComboDispatchRowOwnerDraw(Self, ACanvas, ARect);
end;

procedure TTyComboPopupList.Paint;
begin
  RenderWithOwnerDraw(Canvas, ClientRect, Font.PixelsPerInch);
end;

function TyComboTypeAheadMatch(AItems: TStrings; AStart: Integer; const APrefix: string): Integer;
var n, i, idx: Integer; pfx: string;
begin
  Result := -1;
  n := AItems.Count;
  if (n = 0) or (APrefix = '') then Exit;
  pfx := LowerCase(APrefix);
  for i := 1 to n do
  begin
    idx := (AStart + i) mod n;      // start searching AFTER AStart, wrapping
    if idx < 0 then idx := idx + n;
    if Copy(LowerCase(AItems[idx]), 1, Length(pfx)) = pfx then
      Exit(idx);
  end;
end;

function TyFilterItemsByPrefix(AItems: TStrings; const APrefix: string): TStringList;
var i: Integer; p: string;
begin
  Result := TStringList.Create;
  if AItems = nil then Exit;
  p := LowerCase(APrefix);
  for i := 0 to AItems.Count - 1 do
    if (p = '') or (Copy(LowerCase(AItems[i]), 1, Length(p)) = p) then
      Result.AddObject(AItems[i], AItems.Objects[i]);   // carry Objects[] so a subclass's
      // per-item data (e.g. TTyComboBoxEx image indices) survives the prefix filter
end;

function TyComboIndexOfText(AItems: TStrings; const AText: string; ACaseSensitive: Boolean): Integer;
var i: Integer;
begin
  Result := -1;
  if AItems = nil then Exit;
  for i := 0 to AItems.Count - 1 do
    if (ACaseSensitive and (AItems[i] = AText))
    or ((not ACaseSensitive) and (AnsiCompareText(AItems[i], AText) = 0)) then
      Exit(i);
end;

constructor TTyComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;
  FItemIndex := -1;
  FText := '';
  FDropDownCount := 8;
  FSorted := False;
  FMaxLength := 0;
  FCharCase := ecNormal;
  FItemHeight := 0;   // follow the theme until a host pins it
  FItemWidth  := 0;   // dropdown exactly as wide as the field
  FTextHint   := '';
  FReadOnly   := False;
  FItemsStreamed := True;   // the plain combo's Items IS the persisted row set
  FPopup     := nil;
  FPopupList := nil;
  TabStop := True;
  Width := 145;
  Height := TyDensityHeight(ActiveController, TyComboClassicFieldHeight);
  { Editable-mode scaffolding. The editor stays hidden until Style := csDropDown. }
  FStyle := csDropDownList;
  FVisibleItems := TStringList.Create;
  FSyncingText := False;
  FShowingPopup := False;
  FEditor := TTyEdit.Create(Self);
  FEditor.Parent := Self;
  { The combo has ALREADY drawn the field -- background, border, radius -- and owns the focus
    ring. Without this the editor drew a SECOND rounded frame inside the first, and the drop
    chevron ended up in the gap between the two, which is what "the arrow is jammed against the
    edge in editable mode" turned out to be: the chevron never moved (measured 3px from the
    outer border in BOTH styles), the inner box appeared next to it. The class is a themed
    variant, not a hardcoded look -- see TyEdit.embedded in themes/light.tycss. }
  FEditor.StyleClass := 'embedded';
  FEditor.Visible := False;
  FEditor.OnChange  := @EditorChange;
  FEditor.OnExit    := @EditorExit;
  FEditor.OnKeyDown := @EditorKeyDown;
  { Keep the (normally hidden) child editor out of the IDE designer's selectable
    sub-control set — same rule as the TreeView inline editor. }
  FEditor.ControlStyle := FEditor.ControlStyle + [csNoDesignVisible];
end;

destructor TTyComboBox.Destroy;
begin
  { Cancel any queued async calls so they can't fire into a freed combo. }
  Application.RemoveAsyncCalls(Self);
  { Free the popup helper first (it owns its form; FPopupList is owned by Self
    and will be freed below — the helper only parented it, not owned it). }
  FreeAndNil(FPopup);
  { Free the list box (owned by Self; no longer parented to anything after the
    helper's form was freed above). }
  FreeAndNil(FPopupList);
  { FEditor is owned by Self and auto-freed by the component chain; only the
    filtered-subset list needs an explicit free. }
  FVisibleItems.Free;
  FItems.Free;
  inherited Destroy;
end;

function TTyComboBox.GetStyleTypeKey: string;
begin
  Result := 'TyComboBox';
end;

procedure TTyComboBox.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
  { Keep an already-created popup list in sync when the controller is reassigned;
    otherwise FPopupList keeps the old controller until the next DropDown. }
  if FPopupList <> nil then
    FPopupList.Controller := AValue;
  { Propagate to the popup helper so ApplyRegion resolves the background color
    from the updated theme. }
  if FPopup <> nil then
    FPopup.Controller := AValue;
  { Keep the embedded editor themed by the same controller. }
  if FEditor <> nil then
    FEditor.Controller := AValue;
  { csSimple: the docked list re-reads its surface colour and the field zone re-measures
    (a density flip moves --control-height, which moves where the list starts). }
  if FStyle = csSimple then
  begin
    ApplyEmbeddedListColor;
    LayoutEditor;
    LayoutEmbeddedList;
  end;
end;

procedure TTyComboBox.DoSelect;
begin
  if Assigned(FOnSelect) then FOnSelect(Self);
end;

procedure TTyComboBox.DoEditorCommit;
begin
  // default: no-op (see TTyMRUComboBox)
end;

procedure TTyComboBox.DoPopupPick(AIndex: Integer);
begin
  UserSelect(AIndex);                                 // commit the picked row...
  Application.QueueAsyncCall(@DeferredCloseUp, 0);     // ...and close the dropdown
end;

procedure TTyComboBox.DoDropDown;
begin
  if Assigned(FOnDropDown) then FOnDropDown(Self);
end;

procedure TTyComboBox.DoCloseUp;
begin
  if Assigned(FOnCloseUp) then FOnCloseUp(Self);
end;

procedure TTyComboBox.UserSelect(AIndex: Integer);
var
  OldIndex: Integer;
begin
  OldIndex := FItemIndex;
  SelectItem(AIndex);            // fires OnChange on a real change
  if FItemIndex <> OldIndex then
    DoSelect;                    // OnSelect = the user actually picked something
end;

procedure TTyComboBox.SetItems(const AValue: TStringList);
begin
  { TStringList.Assign copies the source's Sorted flag, which would silently drop
    our Sorted state. Re-apply it so an externally-set Items list stays sorted. }
  FItems.Assign(AValue);
  if FItems.Sorted <> FSorted then
    FItems.Sorted := FSorted;
  Invalidate;
end;

procedure TTyComboBox.SetText(const AValue: TCaption);
begin
  if FText = AValue then Exit;
  FText := AValue;
  { In editable mode keep the visible field in sync with a programmatic Text set,
    but under the guard so it does not re-trigger the autocomplete filter/popup. }
  if (FEditor <> nil) and TyComboStyleHasEditBox(FStyle) and (FEditor.Text <> AValue) then
    SetEditorText(AValue);
  Invalidate;
end;

procedure TTyComboBox.SetItemIndex(const AValue: Integer);
begin
  SelectItem(AValue);
end;

procedure TTyComboBox.SetDropDownCount(const AValue: Integer);
begin
  if FDropDownCount = AValue then Exit;
  { Clamp to at least 1 visible row, mirroring LCL behaviour. }
  if AValue < 1 then
    FDropDownCount := 1
  else
    FDropDownCount := AValue;
  { If the popup is currently open, re-size it on the next DropDown. No live
    resize here to keep the open popup stable. }
end;

procedure TTyComboBox.SetSorted(const AValue: Boolean);
begin
  if FSorted = AValue then Exit;
  FSorted := AValue;
  { TStringList natively supports Sorted: it sorts in place (ascending,
    case-insensitive by default) and keeps subsequent Adds sorted. Setting it
    reorders the items, so the selected index becomes stale — re-find it by text. }
  FItems.OnChange := nil;        // avoid re-entrancy while we flip Sorted
  FItems.Sorted := FSorted;
  FItems.OnChange := @ItemsChanged;
  ResyncIndexFromText;
  { The reorder above ran with ItemsChanged detached, so the csSimple docked list --
    which mirrors Items LIVE -- has to be told by hand. }
  if FStyle = csSimple then
  begin
    SyncEmbeddedItems;
    SyncEmbeddedSelection;
  end;
  Invalidate;
end;

procedure TTyComboBox.SetMaxLength(const AValue: Integer);
begin
  FMaxLength := AValue;
  { Forward to the embedded field so csDropDown caps typed text (mirrors
    SetCharCase). FEditor always exists post-construction, so this stays in sync
    in every mode and streaming order. }
  if FEditor <> nil then
    FEditor.MaxLength := AValue;
end;

procedure TTyComboBox.SetCharCase(const AValue: TEditCharCase);
begin
  FCharCase := AValue;
  { In editable mode the transform applies to the embedded field. }
  if FEditor <> nil then
  begin
    FEditor.CharCase := AValue;
    { TTyEdit re-cases its buffer in place without firing OnChange; keep our Text
      in sync so the getter matches what the field now displays. }
    if TyComboStyleHasEditBox(FStyle) then
      FText := FEditor.Text;
  end;
end;

function TTyComboBox.EditorVisibleForTest: Boolean;
begin
  Result := (FEditor <> nil) and FEditor.Visible;
end;

function TTyComboBox.EditorMaxLengthForTest: Integer;
begin
  if FEditor <> nil then
    Result := FEditor.MaxLength
  else
    Result := -1;
end;

function TTyComboBox.EditorTextHintForTest: string;
begin
  if FEditor <> nil then Result := FEditor.TextHint else Result := '';
end;

function TTyComboBox.EditorReadOnlyForTest: Boolean;
begin
  Result := (FEditor <> nil) and FEditor.ReadOnly;
end;

function TTyComboBox.ComputePopupHeightForTest(APPI: Integer): Integer;
begin
  Result := ComputePopupHeight(APPI);
end;

procedure TTyComboBox.SimulateTypedTextForTest(const S: string);
begin
  if FEditor = nil then Exit;
  FEditor.Text := S;   // NOT SetEditorText: the guard must stay down so EditorChange runs
end;

function TTyComboBox.SimulateEditorKeyForTest(AKey: Word): Word;
begin
  Result := AKey;
  if FEditor = nil then Exit;
  EditorKeyDown(FEditor, Result, []);
end;

function TTyComboBox.ComputePopupWidthForTest(APPI: Integer): Integer;
begin
  Result := ComputePopupWidth(APPI);
end;

procedure TTyComboBox.SetItemHeight(const AValue: Integer);
begin
  if FItemHeight = AValue then Exit;
  if AValue < 0 then FItemHeight := 0 else FItemHeight := AValue;
  { Push it into an already-built popup list. Only when pinned: 0 must leave whatever the
    list chose for itself, which is how TTyAdvancedComboBox keeps its 40px rich rows. }
  if (FPopupList <> nil) and (FItemHeight > 0) then
    FPopupList.ItemHeight := FItemHeight;
  Invalidate;
end;

procedure TTyComboBox.SetItemWidth(const AValue: Integer);
begin
  if FItemWidth = AValue then Exit;
  if AValue < 0 then FItemWidth := 0 else FItemWidth := AValue;
  { No live resize of an open popup: the next DropDown picks the new width up, same rule
    DropDownCount already follows. }
end;

procedure TTyComboBox.SetTextHint(const AValue: TCaption);
begin
  if FTextHint = AValue then Exit;
  FTextHint := AValue;
  { csDropDown borrows TTyEdit's hint painting; csDropDownList has no editor, so the
    field paints it in PaintFieldContent. Forward unconditionally so a hint set before
    the style switch is already in place afterwards (mirrors MaxLength/CharCase). }
  if FEditor <> nil then
    FEditor.TextHint := AValue;
  Invalidate;
end;

procedure TTyComboBox.SetReadOnly(const AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  if FEditor <> nil then
    FEditor.ReadOnly := AValue;
end;

function TTyComboBox.GetDroppedDown: Boolean;
begin
  { csSimple: True, always. Measured, not assumed -- a real CBS_SIMPLE combo answers 1 to
    CB_GETDROPPEDSTATE while its permanent list shows, which is what LCL's Win32
    GetDroppedDown forwards. The list never opens or closes, so the answer never moves. }
  if FStyle = csSimple then Exit(True);
  Result := (FPopup <> nil) and FPopup.IsOpen;
end;

procedure TTyComboBox.SetDroppedDown(const AValue: Boolean);
begin
  { csSimple: writes are ignored, both directions -- CB_SHOWDROPDOWN "has no effect on a
    combo box created with the CBS_SIMPLE style", and the probe confirms DroppedDown stays
    True through both writes. Routing them into DropDown/CloseUp would be worse than the
    no-op: those are guarded too, but a subclass override (the check combo pushes state in
    DropDown) would run for an open that cannot happen. }
  if FStyle = csSimple then Exit;
  { Routed through the virtual DropDown / CloseUp so a subclass's override still runs
    (TTyCheckComboBox pushes its check states in DropDown, for one). }
  if AValue then
    DropDown
  else
    CloseUp;
end;

function TTyComboBox.GetSelStart: Integer;
begin
  if FEditor <> nil then Result := FEditor.SelStart else Result := 0;
end;

procedure TTyComboBox.SetSelStart(const AValue: Integer);
begin
  if FEditor <> nil then FEditor.SelStart := AValue;
end;

function TTyComboBox.GetSelLength: Integer;
begin
  if FEditor <> nil then Result := FEditor.SelLength else Result := 0;
end;

procedure TTyComboBox.SetSelLength(const AValue: Integer);
begin
  if FEditor <> nil then FEditor.SelLength := AValue;
end;

function TTyComboBox.GetSelText: string;
begin
  if FEditor <> nil then Result := FEditor.SelText else Result := '';
end;

procedure TTyComboBox.SetSelText(const AValue: string);
begin
  { No resync afterwards on purpose: TTyEdit.SetSelText fires its OnChange once for the
    whole replace, and our EditorChange handler is what pulls the new text back into
    FText. Re-reading here as well would be code no test can distinguish. }
  if FEditor <> nil then FEditor.SelText := AValue;
end;

procedure TTyComboBox.SelectAll;
begin
  if FEditor <> nil then FEditor.SelectAll;
end;

procedure TTyComboBox.AddHistoryItem(const AItem: string; AMaxHistoryCount: Integer;
  ASetAsText, ACaseSensitive: Boolean);
begin
  AddHistoryItem(AItem, nil, AMaxHistoryCount, ASetAsText, ACaseSensitive);
end;

procedure TTyComboBox.AddHistoryItem(const AItem: string; AnObject: TObject;
  AMaxHistoryCount: Integer; ASetAsText, ACaseSensitive: Boolean);
var
  Existing: Integer;
  WasSorted: Boolean;
begin
  { Sorted forbids InsertObject on a TStringList ("Operation not allowed on sorted
    list"), and an MRU order is by definition not alphabetical — so drop Sorted for the
    duration and restore it, which re-sorts and makes the promotion a no-op visually.
    Better than raising in the caller's face on a combo that merely had Sorted set. }
  WasSorted := FItems.Sorted;
  if WasSorted then FItems.Sorted := False;
  try
    Existing := TyComboIndexOfText(FItems, AItem, ACaseSensitive);
    if Existing >= 0 then FItems.Delete(Existing);   // promote, never duplicate
    FItems.InsertObject(0, AItem, AnObject);
    { Trim from the BOTTOM: the least recently used entries are the ones that go. }
    if AMaxHistoryCount > 0 then
      while FItems.Count > AMaxHistoryCount do
        FItems.Delete(FItems.Count - 1);
  finally
    if WasSorted then FItems.Sorted := True;
  end;
  if ASetAsText then Text := AItem;
end;

procedure TTyComboBox.SetEditorText(const S: string);
begin
  if FEditor = nil then Exit;
  FSyncingText := True;
  try
    FEditor.Text := S;
  finally
    FSyncingText := False;
  end;
end;

procedure TTyComboBox.Clear;
begin
  FItems.Clear;
  { Items.Clear fires ItemsChanged -> ResyncIndexFromText, which drops ItemIndex and blanks
    the display -- but only in csDropDownList; in csDropDown it deliberately leaves the
    field's free text alone, because there the text is not required to be a list member.
    Clear means "empty the control", so the editable mode needs blanking here. }
  FItemIndex := -1;
  FText := '';
  if (FEditor <> nil) and (FEditor.Text <> '') then FEditor.Text := '';
  Invalidate;
end;

procedure TTyComboBox.ClearSelection;
begin
  { Drops the selection without touching the list. LCL spells it this way; ItemIndex := -1
    is the same thing, but only if you already know that -1 is the sentinel. }
  SelectItem(-1);
end;

procedure TTyComboBox.AddItem(const AItem: string; AnObject: TObject);
begin
  FItems.AddObject(AItem, AnObject);
end;

function TTyComboBox.Count: Integer;
begin
  Result := FItems.Count;
end;

procedure TTyComboBox.SetStyle(AValue: TTyComboBoxStyle);
var
  WasSimple: Boolean;
begin
  if FStyle = AValue then Exit;
  { Entering csSimple while a popup is open: close it under the OLD style's semantics,
    BEFORE the flip -- once FStyle is csSimple, CloseUp is a guarded no-op and the popup
    would be left showing over a control that no longer owns one. }
  if (AValue = csSimple) and (FPopup <> nil) and FPopup.IsOpen then
    CloseUp;
  WasSimple := FStyle = csSimple;
  FStyle := AValue;
  if FEditor <> nil then
  begin
    FEditor.Visible := TyComboStyleHasEditBox(FStyle);
    if TyComboStyleHasEditBox(FStyle) then
    begin
      SetEditorText(FText);   // seed from current text without re-triggering filter
      LayoutEditor;
    end;
  end;
  if FStyle = csSimple then
    AttachEmbeddedList
  else if WasSimple then
  begin
    DetachEmbeddedList;
    { Leaving csSimple: the Height was field + list; a popup style's whole control IS the
      field. Win32 does the same snap through AdaptBounds (win32wsstdctrls.pp:1139 --
      every style but csSimple is forced back to the combo height). Skipped while
      streaming: a load can only ever ENTER csSimple (FStyle starts at the default), so
      this branch running under csLoading would mean a double Style write in one .lfm --
      but guard it anyway, Height here would clobber the streamed one. }
    if not (csLoading in ComponentState) then
      Height := FieldZoneHeight(Font.PixelsPerInch);
  end;
  Invalidate;
end;

function TTyComboBox.FieldZoneHeight(APPI: Integer): Integer;
begin
  { The themed field height (classic 26 / modern --control-height), scaled to device px --
    the strip the FIELD keeps in csSimple. NOT derived from the control's Height: in
    csSimple the Height is field + list and belongs to the user, exactly as on Win32 where
    CBS_SIMPLE follows the LCL height verbatim (win32listsl.inc GetComboHeight). }
  Result := MulDiv(TyDensityHeight(ActiveController, TyComboClassicFieldHeight), APPI, 96);
end;

function TTyComboBox.FieldZoneHeightForTest(APPI: Integer): Integer;
begin
  Result := FieldZoneHeight(APPI);
end;

procedure TTyComboBox.EnsureListBox;
begin
  if FPopupList <> nil then Exit;
  FPopupList := CreatePopupList;  // virtual: a subclass returns its own list class, and
  // that ONE factory serves both shapes -- popup and embedded -- so the rows cannot
  // paint one way dropped down and another way docked.
  { csNoDesignVisible BEFORE any Parent/Visible change (memory/designer-internal-
    subcontrol-leak, and the PageControl ordering note: the show-state re-eval runs at the
    VISIBLE change and must already see the flag). Set unconditionally at creation: in the
    popup it is moot (the list lives in a runtime form), embedded it is what keeps the
    non-simple styles' hidden list out of the IDE designer. While csSimple the list is
    Visible=True, and the flag does not hide a visible control at design time -- the
    design-shown state is `Visible or (csDesigning and not csNoDesignVisible)` -- so the
    docked list still shows in the designer, unselectable there because its Owner is the
    combo, not the form. }
  FPopupList.ControlStyle := FPopupList.ControlStyle + [csNoDesignVisible];
  { A pinned ItemHeight overrides whatever the list (or a subclass's factory) chose;
    0 leaves that choice alone so themed / rich-row lists keep working. }
  if FItemHeight > 0 then
    FPopupList.ItemHeight := FItemHeight;
  FPopupList.OnChange := @PopupListChange;
end;

procedure TTyComboBox.AttachEmbeddedList;
begin
  EnsureListBox;
  { If the list is currently the popup form's content, take it back through SetContent(nil)
    -- otherwise the LATER SetContent(FPopupList) on leaving csSimple would no-op on "same
    content" while the list is actually parented to the combo. }
  if FPopup <> nil then
    FPopup.SetContent(nil);
  FPopupList.Align := alNone;          // SetContent had set alClient; the field zone is ours
  FPopupList.TabStop := False;         // one tab stop per combo: the field
  { Square corners: the OS simple list is square, the docked seam wants no gap, and -- the
    load-bearing half -- a rounded frame leaves corner pixels for the windowed control's
    ERASE colour to show through (the ghost). ForceSquareSurface makes the paint cover the
    full rect; ApplyEmbeddedListColor covers the pre-paint erase flash. }
  FPopupList.ForceSquareSurface := True;
  FPopupList.Controller := Self.Controller;
  ApplyEmbeddedListColor;
  SyncEmbeddedItems;
  SyncEmbeddedSelection;
  FPopupList.Parent := Self;
  FPopupList.Visible := True;
  LayoutEmbeddedList;
end;

procedure TTyComboBox.DetachEmbeddedList;
begin
  if FPopupList = nil then Exit;
  FPopupList.Visible := False;         // hide first: no flash while it changes homes
  FPopupList.Parent := nil;
  if FPopup <> nil then
    FPopup.SetContent(FPopupList);     // re-home into the popup form (alClient again)
  FPopupList.ForceSquareSurface := TyIsWayland;   // the popup rule, as EnsurePopup set it
  FPopupList.Visible := True;          // the popup form's Show/Hide is the gate again
end;

procedure TTyComboBox.LayoutEmbeddedList;
var
  FieldH, ListH: Integer;
begin
  if (FStyle <> csSimple) or (FPopupList = nil) or (FPopupList.Parent <> Self) then Exit;
  FieldH := FieldZoneHeight(Font.PixelsPerInch);
  ListH := ClientHeight - FieldH;
  if ListH < 0 then ListH := 0;        // a field-height csSimple combo shows just the field,
  // as the OS one does -- the list is there, zero rows tall, and grows with the control.
  FPopupList.SetBounds(0, FieldH, ClientWidth, ListH);
end;

procedure TTyComboBox.ApplyEmbeddedListColor;
var
  S: TTyStyleSet;
begin
  if FPopupList = nil then Exit;
  { The theme's list surface, not the parent's LCL Color: a windowed child erases to its
    own Color before Paint, and inheriting the parent's leaves a foreign flash (and, on any
    rounded theme, foreign corners -- squared off above, but the erase is still visible
    between frames). Same resolution ApplyRegion makes for the popup form. Non-solid
    backgrounds (image/gradient themes) keep the default: there is no one colour to erase
    to, and the full-rect paint covers the surface anyway. }
  S := ActiveController.Model.ResolveStyle('TyListBox', '', []);
  if S.Background.Kind = tfkSolid then
    FPopupList.Color := TyColorToLCL(S.Background.Color);
end;

procedure TTyComboBox.SyncEmbeddedItems;
begin
  if FPopupList = nil then Exit;
  FPopupList.OnChange := nil;
  try
    FPopupList.Items.Assign(FItems);
  finally
    FPopupList.OnChange := @PopupListChange;
  end;
end;

procedure TTyComboBox.SyncEmbeddedSelection;
begin
  if FPopupList = nil then Exit;
  FPopupList.OnChange := nil;
  try
    FPopupList.SelectItem(FItemIndex);   // scrolls into view (EnsureSelectionVisible)
  finally
    FPopupList.OnChange := @PopupListChange;
  end;
end;

procedure TTyComboBox.SetOnDrawItem(const AValue: TTyDrawItemEvent);
begin
  { Assigning (or clearing) the handler is what switches an owner-draw Style between the
    host's rows and the themed default, so it has to repaint -- setting Style first and the
    handler second is the ordinary order, and without this the field would keep the render
    it had before the handler existed. }
  FOnDrawItem := AValue;
  Invalidate;
end;

procedure TTyComboBox.SetOnMeasureItem(const AValue: TTyMeasureItemEvent);
begin
  { Assigning (or clearing) this changes every ROW HEIGHT in the drop-down, so an already-
    built list has to repaint -- its row geometry is derived live from RowHeight, but nothing
    tells it the answers just changed. The popup's own HEIGHT is re-sized on the next
    DropDown, the same rule DropDownCount and ItemWidth already follow: no live resize of an
    open popup. }
  FOnMeasureItem := AValue;
  if FPopupList <> nil then FPopupList.Invalidate;
  Invalidate;
end;

function TTyComboBox.OwnerDrawsRows: Boolean;
begin
  Result := TyComboStyleIsOwnerDrawn(FStyle) and Assigned(FOnDrawItem);
end;

function TTyComboBox.MeasuresRows: Boolean;
begin
  Result := TyComboStyleIsVariable(FStyle) and Assigned(FOnMeasureItem);
end;

function TTyComboBox.MeasureRowHeight(AList: TTyListBox; ARow, ADefault: Integer): Integer;
var
  h: Integer;
begin
  Result := ADefault;
  if not MeasuresRows then Exit;
  { Seeded with what the row would otherwise be, so a handler that only cares about SOME
    rows leaves the rest at the theme's height by not touching the parameter. }
  h := ADefault;
  FOnMeasureItem(Self, RowSourceIndex(AList, ARow), h);
  { A zero (or negative) answer is not a row, it is a paint loop that never advances -- and
    it is the shape a handler that forgot one branch of its case statement returns. Keep the
    seed rather than propagate it. }
  if h > 0 then Result := h;
end;

function TTyComboBox.RowOwnerDrawCountForTest: Integer;
begin
  Result := FRowDrawCount;
end;

function TTyComboBox.RowSourceIndex(AList: TTyListBox; ARow: Integer): Integer;
begin
  { OnDrawItem's Index indexes ITEMS, as LCL documents it -- but the popup may be holding
    the prefix-filtered subset (the editable styles' autocomplete) rather than Items, and a
    handler doing the obvious Items[Index] would then read the wrong row or run off the end.
    TyFilterItemsByPrefix keeps order and drops nothing when the prefix is empty, so an
    equal count IS the full list; anything shorter is mapped back by text -- the same
    mapping PopupListChange makes when it commits a picked row, and with the same limit
    (duplicate texts map to the first). }
  Result := ARow;
  if (AList = nil) or (ARow < 0) or (ARow >= AList.Items.Count) then Exit;
  if AList.Items.Count = FItems.Count then Exit;
  Result := FItems.IndexOf(AList.Items[ARow]);
end;

function TTyComboBox.FieldOwnerDrawState: TOwnerDrawState;
begin
  Result := [odComboBoxEdit, odBackgroundPainted];
  if not Enabled then Result := Result + [odDisabled, odGrayed];
  if Focused then Include(Result, odFocused);
end;

procedure TTyComboBox.BeginRowOwnerDraw;
begin
  { Drop anything a previous paint left: a RenderTo that collects and never dispatches
    (a golden-image test drawing the list straight to a bitmap) would otherwise leak its
    rows into the next real paint. }
  FRowDrawCount := 0;
end;

function TTyComboBox.CollectRowOwnerDraw(AList: TTyListBox; const ARowRect: TRect;
  AIndex: Integer): Boolean;
var
  St: TOwnerDrawState;
begin
  Result := OwnerDrawsRows;
  if not Result then Exit;
  { odBackgroundPainted always: RenderTo filled this row before calling PaintItemContent,
    so the handler must be told not to paint one of its own over the highlight. }
  St := [odBackgroundPainted];
  if not Enabled then St := St + [odDisabled, odGrayed];
  if AList <> nil then
  begin
    if AList.MultiSelect then
    begin
      if AList.Selected[AIndex] then Include(St, odSelected);
    end
    else if AIndex = AList.ItemIndex then
      Include(St, odSelected);
  end;
  if FRowDrawCount = Length(FRowDraw) then
    SetLength(FRowDraw, Length(FRowDraw) + 8);
  FRowDraw[FRowDrawCount].R := ARowRect;
  FRowDraw[FRowDrawCount].SrcIndex := RowSourceIndex(AList, AIndex);
  FRowDraw[FRowDrawCount].St := St;
  Inc(FRowDrawCount);
end;

procedure TTyComboBox.DispatchRowOwnerDraw(ACanvas: TCanvas; const ARect: TRect);
var
  k: Integer;
  R: TRect;
begin
  if (ACanvas = nil) or (FRowDrawCount = 0) or not Assigned(FOnDrawItem) then Exit;
  { --- the host pass, on the COMPOSITED canvas ---------------------------------------
    Everything the list drew went into the painter's BGRA layer, which EndPaint has just
    blitted over ACanvas; a GDI draw made before that point is erased, which is the whole
    reason this loop is here and not inside the row loop.

    The per-row bracket is Canvas.SaveHandleState / RestoreHandleState and NOT raw
    SaveDC/RestoreDC. RestoreDC swaps the DC's selected pen/font/brush back, but an LCL
    TCanvas caches which of ITS objects it believes are selected and only re-selects one
    when a property actually CHANGES -- so from the second callback on that cache is a lie,
    and a handler assigning the SAME Font.Color (or Pen.Color) it assigned last row gets a
    silent no-op and inks with whatever the restore put back. A host cannot defend against
    that: an OnDrawItem doing the ordinary thing -- one ink on every row -- would paint row
    one correctly and every row after it in a foreign colour. The canvas-aware pair calls
    DeselectHandles on both sides, so the cache never outlives the DC state it describes.
    It is the bracket LCL's own per-cell owner-draw hook uses (TCustomGrid.DoDrawCell around
    OnDrawCell) and the one LCLIntf's header points at. Both sibling instances of this
    defect shipped and were fixed: commits 2477173 (tree) and 7629c14 (menu). FillRect is
    immune (LCL hands it the brush handle explicitly), which is why a guard written around
    Brush + FillRect cannot see any of this.

    The rects are painter-local (0-based inside ARect); offset into canvas device coords and
    clip each row to its own, so no handler can bleed into its neighbour. }
  for k := 0 to FRowDrawCount - 1 do
  begin
    R := FRowDraw[k].R;
    Types.OffsetRect(R, ARect.Left, ARect.Top);
    ACanvas.SaveHandleState;
    try
      IntersectClipRect(ACanvas.Handle, R.Left, R.Top, R.Right, R.Bottom);
      FOnDrawItem(Self, ACanvas, FRowDraw[k].SrcIndex, R, FRowDraw[k].St);
    finally
      ACanvas.RestoreHandleState;
    end;
  end;
end;

procedure TTyComboBox.LayoutEditor;
var
  BtnW, PPI, PadL, PadT, PadR, PadB, BottomY: Integer;
  S: TTyStyleSet;
begin
  if (FEditor = nil) or not TyComboStyleHasEditBox(FStyle) then Exit;
  PPI  := Font.PixelsPerInch;
  { csSimple: no chevron (the OS simple combo reports an EMPTY rcButton), so the field
    spans the full width -- and only the FIELD ZONE's height, because everything under it
    is the docked list, not more field. }
  if FStyle = csSimple then
  begin
    BtnW := 0;
    BottomY := FieldZoneHeight(PPI);
    if BottomY > ClientHeight then BottomY := ClientHeight;
  end
  else
  begin
    BtnW := MulDiv(ButtonWidthLogical, PPI, 96);
    BottomY := ClientHeight;
  end;
  { Inset the editor to the same field rectangle RenderTo paints the text into:
    the resolved Padding on all sides, stopping short of the chevron zone. Keeps
    the embedded editor aligned with the frame on any theme. }
  S    := CurrentStyle;
  PadL := MulDiv(S.Padding.Left,   PPI, 96);
  PadT := MulDiv(S.Padding.Top,    PPI, 96);
  PadR := MulDiv(S.Padding.Right,  PPI, 96);
  PadB := MulDiv(S.Padding.Bottom, PPI, 96);
  FEditor.SetBounds(PadL, PadT,
    ClientWidth - BtnW - PadL - PadR,
    BottomY - PadT - PadB);
end;

procedure TTyComboBox.EditorChange(Sender: TObject);
var filtered: TStringList;
begin
  if FSyncingText then Exit;
  FText := FEditor.Text;
  FItemIndex := FItems.IndexOf(FText);   // -1 if not a member; do NOT blank FText
  { csSimple: typing NEVER filters and never pops a suggestion list -- the docked list
    always shows every row, as the OS one does (CBS_SIMPLE has no autocomplete of its
    own). What typing does move is the SELECTION, to the exact-text match just computed
    (or off, at -1), and the docked list mirrors that. }
  if FStyle = csSimple then
  begin
    SyncEmbeddedSelection;
    if Assigned(FOnChange) then FOnChange(Self);
    Exit;
  end;
  filtered := TyFilterItemsByPrefix(FItems, FText);
  try
    FVisibleItems.Assign(filtered);
  finally filtered.Free; end;
  if FVisibleItems.Count = 0 then
    CloseUp
  else
    DropDownFiltered;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyComboBox.EditorExit(Sender: TObject);
begin
  { Close the autocomplete popup when the editable field truly loses focus (click
    elsewhere). Skip the transient blur while we are opening the popup and bouncing
    focus back to the editor (FShowingPopup) — that is not a real focus-out. A row
    click does not blur the editor (the popup is non-activating), so this does not
    fire mid-pick and interrupt the commit. }
  if csDestroying in ComponentState then Exit;
  if FShowingPopup then Exit;
  { Defer the close: if this blur was actually a click landing ON a popup row (an
    edge if the OS ever activates the popup on click despite WS_EX_NOACTIVATE), the
    row's PopupListChange still runs and commits first; the deferred CloseUp is
    idempotent. Also avoids hiding the popup synchronously inside a focus event.
    csSimple is excluded by name, not by the guard chain: DroppedDown is pinned True
    there, and queueing a (no-op) close for a list that cannot close is churn. }
  if (FStyle <> csSimple) and DroppedDown then
    Application.QueueAsyncCall(@DeferredCloseUp, 0);
  DoEditorCommit;   // genuine focus-out: let a subclass (MRU) remember the typed text
end;

procedure TTyComboBox.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  { csSimple: Up/Down in the field move the LIST selection -- the Win32 simple combo's
    behaviour, and the only way the docked list is keyboard-reachable while the field
    keeps focus. Home/End are NOT taken: in an edit they move the caret, and stealing
    them would make the field half an editor. Escape is NOT taken either: there is
    nothing to dismiss (DroppedDown is pinned True here, so the popup branch below would
    otherwise swallow every Escape into a no-op CloseUp). }
  if FStyle = csSimple then
  begin
    if FItems.Count = 0 then Exit;
    case Key of
      VK_DOWN:
        begin
          if FItemIndex < 0 then UserSelect(0)
          else if FItemIndex < FItems.Count - 1 then UserSelect(FItemIndex + 1);
          Key := 0;
        end;
      VK_UP:
        begin
          if FItemIndex < 0 then UserSelect(0)
          else if FItemIndex > 0 then UserSelect(FItemIndex - 1);
          Key := 0;
        end;
    end;
    Exit;
  end;
  { Popup keys can't reach the popup form (it never focuses); handle the essential
    dismiss here so Escape closes the suggestion list. }
  if not DroppedDown then Exit;
  if Key = VK_ESCAPE then
  begin
    CloseUp;
    Key := 0;
  end;
end;

function TTyComboBox.PointInChevron(const P: TPoint): Boolean;
var BtnW: Integer;
begin
  BtnW := MulDiv(ButtonWidthLogical, Font.PixelsPerInch, 96);
  Result := P.X >= ClientWidth - BtnW;
end;

procedure TTyComboBox.ResyncIndexFromText;
var
  Idx: Integer;
begin
  { Keep the SAME item selected after the list was reordered: locate the current
    selection text and pin FItemIndex to it. No OnChange — the selection (text)
    did not change, only its position. }
  if FItemIndex < 0 then Exit;        // nothing was selected
  Idx := FItems.IndexOf(FText);
  if Idx >= 0 then
    FItemIndex := Idx
  else
  begin
    { Selected text no longer present — clear selection. In editable mode the
      field keeps its free text (it may just not be a list member); only the
      read-only list-mode blanks the display. }
    FItemIndex := -1;
    if not TyComboStyleHasEditBox(FStyle) then FText := '';
  end;
end;

procedure TTyComboBox.DoItemsChanged;
begin
  // default: no-op (see TTyComboBoxEx)
end;

function TTyComboBox.ItemsStored: Boolean;
begin
  Result := FItemsStreamed;
end;

procedure TTyComboBox.ItemsChanged(Sender: TObject);
begin
  { Subclass side models reconcile first — they may change what Items holds in Objects[],
    and ResyncIndexFromText below must see the settled list. }
  DoItemsChanged;
  { When items are added/removed (including a sorted insert that shifts indices),
    keep FItemIndex pinned to the selected item's text. }
  ResyncIndexFromText;
  { csSimple: the docked list shows Items LIVE -- there is no DropDown moment to copy them
    at, so every mutation pushes through here (rows first, then the re-pinned selection). }
  if FStyle = csSimple then
  begin
    SyncEmbeddedItems;
    SyncEmbeddedSelection;
  end;
  Invalidate;
end;

function TTyComboBox.ComputePopupHeight(APPI: Integer): Integer;
begin
  Result := PopupHeightFor(FItems.Count, APPI);
end;

function TTyComboBox.PopupHeightFor(ACount, APPI: Integer): Integer;
var
  RowH, i, n: Integer;
begin
  { Row height = the popup list's ItemHeight (a subclass may draw taller rich rows —
    e.g. TTyAdvancedComboBox uses 40); fall back to the TTyListBox default (24) before the
    popup list exists (headless calc). Visible rows = min(Items.Count, DropDownCount), each
    scaled to the given PPI, + the 2px popup frame chrome. Single source of the sizing
    formula — DropDown calls this so the live popup and the headless calc stay in sync.
    An explicit ItemHeight wins over both, and is readable before the popup exists.

    A SUM, not a multiplication: under a Variable Style each row answers for itself, so the
    popup is exactly as tall as the rows it will show. With one shared height the sum is
    n * scaled(RowH) + 2, which is the arithmetic this replaced, digit for digit. }
  RowH := 24;
  if FItemHeight > 0 then
    RowH := FItemHeight
  else if FPopupList <> nil then
    RowH := FPopupList.ItemHeight;
  n := Min(ACount, FDropDownCount);
  Result := 2;
  for i := 0 to n - 1 do
    Inc(Result, MulDiv(MeasureRowHeight(FPopupList, i, RowH), APPI, 96));
end;

function TTyComboBox.ComputePopupWidth(APPI: Integer): Integer;
var Scaled: Integer;
begin
  { The field width is the floor — a dropdown narrower than the combo it hangs off looks
    broken — and ItemWidth raises it, which is exactly LCL's "minimum pixels allocated to
    the items in the dropdown list" (customcombobox.inc AdjustDropDown). }
  Result := Width;
  if FItemWidth > 0 then
  begin
    Scaled := MulDiv(FItemWidth, APPI, 96);
    if Scaled > Result then Result := Scaled;
  end;
end;

function TTyComboBox.ButtonWidthLogical: Integer;
begin
  Result := ActiveController.Metric('--field-button-width', TyFieldButtonWidth);
end;

procedure TTyComboBox.SelectItem(AIndex: Integer);
var
  NewIndex: Integer;
  NewText: string;
begin
  if (AIndex >= 0) and (AIndex < FItems.Count) then
  begin
    NewIndex := AIndex;
    NewText := FItems[AIndex];
  end
  else
  begin
    NewIndex := -1;
    NewText := '';
  end;
  if (NewIndex = FItemIndex) and (NewText = FText) then Exit;
  FItemIndex := NewIndex;
  FText := NewText;
  { csSimple keeps its two views in step with the model: the FIELD (a real TTyEdit --
    seeded under the guard, so EditorChange does not echo) and the DOCKED LIST (synced
    with OnChange detached, so the list's own change event does not commit back). The
    popup styles have neither concern here: their list is re-populated on every DropDown,
    and their editor is seeded by the pick/commit paths that already own that. }
  if FStyle = csSimple then
  begin
    if FEditor <> nil then SetEditorText(FText);
    SyncEmbeddedSelection;
  end;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

{ Lazily create the popup helper and the list box (both live for the combo's
  lifetime — the helper reuses its form across multiple show/hide cycles). }
procedure TTyComboBox.EnsurePopup;
begin
  if FPopup <> nil then Exit;
  FPopup := TTyDropdownPopup.Create;
  FPopup.Controller := Self.Controller;
  FPopup.OnClose    := @PopupClosed;

  { The list itself may already exist -- a combo that spent time in csSimple made it for
    the embedded shape -- so its creation lives in EnsureListBox and only the POPUP wiring
    happens here. DropDown's csSimple guard means this never runs while the list is
    docked, so re-pointing the surface rule and the parent is safe. }
  EnsureListBox;
  FPopupList.ForceSquareSurface := TyIsWayland;

  { Wire the list into the helper's form (alClient; SetContent swaps stale content out). }
  FPopup.SetContent(FPopupList);

  { Key handling on the popup form. }
  FPopup.Form.KeyPreview := True;
  FPopup.Form.OnKeyDown  := @PopupKeyDown;
end;

{ Ensure the popup helper and its TTyListBox child exist, then show the popup. }
procedure TTyComboBox.DropDown;
var
  PopupH: Integer;
  S: TTyStyleSet;
begin
  { csSimple has no popup to open -- the list is already on screen. First line, BEFORE
    OnGetItems: LCL's simple combo never fires OnGetItems either, because the widgetset
    about-to-drop notification this models never arrives for CBS_SIMPLE. A lazy-filled
    simple combo populates Items itself; there is no open moment to hang it on. }
  if FStyle = csSimple then Exit;
  { Lazy population, and it MUST come before the empty-list guard below: a lazy combo
    starts with no rows, so a hook fired after the guard could never fill anything and
    the user's first click would do nothing at all. This is the hole OnDropDown cannot
    plug — that one only fires once the popup has already been shown. }
  if Assigned(FOnGetItems) then FOnGetItems(Self);
  if FItems.Count = 0 then Exit;
  EnsurePopup;
  { Chevron/list-mode drop activates normally (auto-closes on deactivate). Only the
    autocomplete popup (DropDownFiltered, opened WHILE typing) shows non-activating,
    so the editor keeps focus; a chevron drop may happen with the editor unfocused,
    where activate + deactivate-close is the robust behavior. }
  FPopup.NoActivate := False;

  { Sync controller every DropDown so DPI/theme changes take effect. }
  FPopupList.Controller := Self.Controller;
  FPopup.Controller     := Self.Controller;

  { Sync items and selection — detach OnChange to prevent recursion. }
  FPopupList.OnChange := nil;
  FPopupList.Items.Assign(FItems);
  FPopupList.SelectItem(FItemIndex);
  FPopupList.OnChange := @PopupListChange;

  { Resolve the list's corner radius so the popup window region matches the
    themed fill (same value the old ApplyPopupRegion computed). }
  S := ActiveController.Model.ResolveStyle('TyListBox', '', []);
  FPopup.CornerRadiusLogical := S.BorderRadius;

  { Size: height = min(DropDownCount, Items.Count) rows (+ frame chrome). }
  PopupH := ComputePopupHeight(Font.PixelsPerInch);

  FPopup.Popup(Self, ComputePopupWidth(Font.PixelsPerInch), PopupH);
  DoDropDown;   // popup actually opened
end;

{ Editable-mode autocomplete: show the popup populated with the prefix-filtered
  subset (FVisibleItems) instead of the full list. Mirrors DropDown otherwise. }
procedure TTyComboBox.DropDownFiltered;
var
  PopupH, PopupW: Integer;
  S: TTyStyleSet;
begin
  if FVisibleItems.Count = 0 then Exit;
  EnsurePopup;
  { Autocomplete popup shows non-activating so typing in the editor is uninterrupted. }
  FPopup.NoActivate := True;

  FPopupList.Controller := Self.Controller;
  FPopup.Controller     := Self.Controller;

  { Populate from the filtered subset. No selection is forced — the field text
    drives the match; picking a row is what commits a selection. }
  FPopupList.OnChange := nil;
  FPopupList.Items.Assign(FVisibleItems);
  FPopupList.SelectItem(-1);
  FPopupList.OnChange := @PopupListChange;

  S := ActiveController.Model.ResolveStyle('TyListBox', '', []);
  FPopup.CornerRadiusLogical := S.BorderRadius;

  { Height off the FILTERED count -- the SAME formula ComputePopupHeight uses, called on
    the count that is actually showing. It used to be a second copy of the arithmetic here,
    which is one copy too many now that a row's height can be the host's answer. }
  PopupH := PopupHeightFor(FVisibleItems.Count, Font.PixelsPerInch);
  PopupW := ComputePopupWidth(Font.PixelsPerInch);

  { First open: show the popup, then immediately return focus to the editor. LCL
    focuses the popup's list on Show (which WS_EX_NOACTIVATE alone does not stop),
    so re-focusing keeps typing in the editor. FShowingPopup gates the editor's
    OnExit so this transient blur does not self-close the popup; FormDeactivate is
    suppressed for the NoActivate popup so the re-focus does not close it either.
    On later keystrokes the popup is already open — resize it IN PLACE (no Show, no
    focus churn / no per-keystroke flicker). }
  if FPopup.IsOpen then
    FPopup.Resize(PopupW, PopupH)
  else
  begin
    FShowingPopup := True;
    try
      FPopup.Popup(Self, PopupW, PopupH);
      if FEditor.HandleAllocated and FEditor.CanFocus then FEditor.SetFocus;
    finally
      FShowingPopup := False;
    end;
    DoDropDown;
  end;
end;

procedure TTyComboBox.Resize;
begin
  inherited Resize;
  LayoutEditor;
  LayoutEmbeddedList;   // csSimple only (guarded inside): the list zone tracks the bounds
end;

procedure TTyComboBox.Loaded;
begin
  inherited Loaded;
  { Streaming order writes Height (a TControl property) before Style (ours), so SetStyle's
    attach already saw the streamed Height -- but bounds can still be adjusted after that
    (anchors, parent scaling). Re-run the csSimple layout against the FINAL geometry. }
  if FStyle = csSimple then
  begin
    LayoutEditor;
    LayoutEmbeddedList;
  end;
end;

procedure TTyComboBox.CloseUp;
begin
  { csSimple: a full no-op, matching the wire. The list cannot hide, and OnCloseUp must
    not fire for a close that did not happen -- LCL's fires from CBN_CLOSEUP, which a
    CBS_SIMPLE combo never sends. (SetStyle closes an open popup BEFORE flipping into
    csSimple, so this guard never strands one.) }
  if FStyle = csSimple then Exit;
  { If the popup is open, close it — FPopup.Close fires PopupClosed (OnClose)
    which mirrors FCloseUpTick, Invalidates, and calls DoCloseUp. }
  if (FPopup <> nil) and FPopup.IsOpen then
  begin
    FPopup.Close;   // → PopupClosed fires here
    Exit;
  end;
  { Popup was not open (headless test path or already closed): record the tick
    and fire bookkeeping so the race guard still works in tests. }
  FCloseUpTick := GetTickCount64;
  Invalidate;
  DoCloseUp;
end;

procedure TTyComboBox.Click;
begin
  if not Enabled then Exit;
  inherited Click;
  { csSimple: nothing to toggle -- no popup, no chevron. The click still reached the
    user's OnClick above; the field itself belongs to the embedded editor. }
  if FStyle = csSimple then Exit;
  { In editable mode a click on the text zone belongs to the embedded editor
    (caret placement / focus); only a click on the chevron toggles the dropdown. }
  if TyComboStyleHasEditBox(FStyle) and not PointInChevron(ScreenToClient(Mouse.CursorPos)) then Exit;
  { If dropped down, close. Otherwise open — but guard the reopen race:
    clicking the combo while it is open fires FormDeactivate→FPopup.Close→
    PopupClosed BEFORE this Click handler runs, so DroppedDown is already False
    here. We suppress reopen if CloseUp happened within the last 200 ms.
    FCloseUpTick is mirrored from FPopup.CloseUpTick in PopupClosed. }
  if DroppedDown then
    CloseUp
  else if GetTickCount64 - FCloseUpTick > 200 then
    DropDown;
end;

procedure TTyComboBox.KeyDown(var Key: Word; Shift: TShiftState);
var Cnt: Integer;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  { csSimple: there is no open/close, so Escape and F4/Alt+Down mean nothing here -- and
    with DroppedDown pinned True they would otherwise EAT every Escape (breaking a
    dialog's cancel) and every F4 for the sake of a no-op CloseUp. The plain
    Up/Down/Home/End navigation below is exactly what the simple combo's list does, so it
    falls through. }
  if FStyle <> csSimple then
  begin
    if (Key = VK_ESCAPE) and DroppedDown then
    begin
      CloseUp; Key := 0; Exit;
    end;
    { Alt+Down or F4 toggles the dropdown. Must precede the plain VK_DOWN case. }
    if ((Key = VK_DOWN) and (ssAlt in Shift)) or (Key = VK_F4) then
    begin
      if DroppedDown then CloseUp else DropDown;
      Key := 0; Exit;
    end;
  end;
  Cnt := FItems.Count;
  if Cnt = 0 then Exit;
  case Key of
    VK_DOWN:
      begin
        if FItemIndex < 0 then UserSelect(0)
        else if FItemIndex < Cnt - 1 then UserSelect(FItemIndex + 1);
        Key := 0;
      end;
    VK_UP:
      begin
        if FItemIndex < 0 then UserSelect(0)
        else if FItemIndex > 0 then UserSelect(FItemIndex - 1);
        Key := 0;
      end;
    VK_HOME: begin UserSelect(0); Key := 0; end;
    VK_END:  begin UserSelect(Cnt - 1); Key := 0; end;
  end;
end;

procedure TTyComboBox.UTF8KeyPress(var UTF8Key: TUTF8Char);
var nowTick: QWord; hit: Integer;
begin
  if not Enabled then Exit;
  inherited UTF8KeyPress(UTF8Key);
  if (UTF8Key = '') or (UTF8Key[1] < #32) then Exit;
  nowTick := GetTickCount64;
  if nowTick - FTypeAheadTick > 600 then FTypeAhead := '';   // restart after a pause
  FTypeAheadTick := nowTick;
  FTypeAhead := FTypeAhead + UTF8Key;
  hit := TyComboTypeAheadMatch(FItems, FItemIndex, FTypeAhead);
  if hit >= 0 then UserSelect(hit);
end;

{ Popup event handlers }

procedure TTyComboBox.PopupListChange(Sender: TObject);
var
  Picked: string;
  FullIdx, OldIndex: Integer;
begin
  { User clicked / chose a row in the popup list -> a user-driven selection.
    Defer the close: hiding the popup synchronously here — still inside the list's
    click handler — leaves LCL's click-completion focus path pointing at the
    now-hidden popup form, raising EInvalidOperation
    '[TCustomForm.SetFocus] ... Can not focus'. Closing on the next message cycle
    lets the click finish first. }
  if TyComboStyleHasEditBox(FStyle) then
  begin
    { Commit by the row's text read from the list ACTUALLY shown — the popup may
      hold the filtered subset (autocomplete typing → DropDownFiltered) OR the full
      Items (chevron → DropDown), so FPopupList.Items is the only reliable source;
      reading a parallel FVisibleItems mis-maps when the chevron shows the full list
      after a prior filter (clicking Alpha returned the filtered row's text), and its
      count-guard rejected every click when no filter had run (empty FVisibleItems).
      Seed the editor under the re-entrancy guard (else EditorChange would re-filter
      and re-open the popup), map the text back to the full list for FItemIndex, then
      fire OnChange/OnSelect. }
    if (FPopupList.ItemIndex < 0) or (FPopupList.ItemIndex >= FPopupList.Items.Count) then Exit;
    Picked  := FPopupList.Items[FPopupList.ItemIndex];
    FullIdx := FItems.IndexOf(Picked);
    OldIndex := FItemIndex;
    SetEditorText(Picked);
    FText := Picked;
    FItemIndex := FullIdx;
    Invalidate;
    if Assigned(FOnChange) then FOnChange(Self);
    if FItemIndex <> OldIndex then DoSelect;
    { csSimple takes this same commit path (it has an edit box, and its docked list holds
      the FULL Items so the text→index map above is the identity) -- but there is no popup
      to close and no OnCloseUp to earn, and the caret goes back to the field so typing
      continues after a pick, which is where the OS simple combo keeps it. }
    if FStyle = csSimple then
    begin
      if (FEditor <> nil) and FEditor.HandleAllocated and FEditor.CanFocus then
        FEditor.SetFocus;
    end
    else
      Application.QueueAsyncCall(@DeferredCloseUp, 0);
    Exit;
  end;
  DoPopupPick(FPopupList.ItemIndex);
end;

procedure TTyComboBox.DeferredCloseUp(Data: PtrInt);
begin
  CloseUp;
end;

{ Called by TTyDropdownPopup.OnClose when the popup hides (click-away, Escape,
  or programmatic FPopup.Close).  This is the single bookkeeping point. }
procedure TTyComboBox.PopupClosed(Sender: TObject);
begin
  { Mirror the helper's close-up tick into the protected field so test subclasses
    (e.g. AgeCloseUpTick) and the Click guard can use it without touching FPopup. }
  if FPopup <> nil then
    FCloseUpTick := FPopup.CloseUpTick;
  Invalidate;
  DoCloseUp;
end;

procedure TTyComboBox.PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    CloseUp;
    Key := 0;
  end;
end;

{ Protected accessor for headless tests }
function TTyComboBox.PopupList: TTyListBox;
begin
  Result := FPopupList;
end;

procedure TTyComboBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, TextR, BtnR, FieldR, PaintR: TRect;
  BtnW: Integer;
  FieldOwnerDraw: Boolean;
begin
  { The CLOSED FIELD belongs to the host in the pick-only owner-draw style only. The
    editable one puts a real TTyEdit over the text zone, so there would be nothing left for
    a handler to show -- the same split Windows makes, where an owner-draw combo gets a
    WM_DRAWITEM for its edit area only when it is CBS_DROPDOWNLIST. And no handler means the
    themed default: assigning Style must never be able to blank a control on its own.
    (csSimple is never owner-drawn -- LCL's IsOwnerDrawn table says False -- and the
    HasEditBox arm below already excludes it.) }
  FieldOwnerDraw := TyComboStyleIsOwnerDrawn(FStyle)
    and not TyComboStyleHasEditBox(FStyle) and Assigned(FOnDrawItem);
  { csSimple: the combo's own paint is the FIELD STRIP only. Everything below it belongs
    to the docked list -- a separate windowed child that paints itself -- so the frame is
    clamped to the field zone and nothing is composited over the list's area (at design
    time too, where the list is a design-visible child). }
  PaintR := ARect;
  if (FStyle = csSimple)
     and (PaintR.Top + FieldZoneHeight(APPI) < PaintR.Bottom) then
    PaintR.Bottom := PaintR.Top + FieldZoneHeight(APPI);
  P := TTyPainter.Create;
  try
    R := Types.Rect(0, 0, PaintR.Right - PaintR.Left, PaintR.Bottom - PaintR.Top);
    P.BeginPaint(ACanvas, PaintR, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    { csSimple has no drop arrow: the OS control reports an empty rcButton, and there is
      nothing a click on one would do. The text zone runs to the right padding instead.
      BtnW = 0 is the ENFORCEMENT (an empty BtnR draws nothing and TextR spans the width);
      the `FStyle <> csSimple` gate on the chevron below is intent + a skipped glyph
      resolve. Mutation-tested as a pair: flipping either alone changes no visible pixel
      (the editor overlays the text zone), flipping both paints an arrow and goes red. }
    if FStyle = csSimple then
      BtnW := 0
    else
      BtnW := P.Scale(ButtonWidthLogical);
    BtnR := Types.Rect(R.Right - BtnW, R.Top, R.Right, R.Bottom);
    // Content honours the resolved Padding (consistent with Button/Edit/Panel);
    // the right edge stops at the chevron button zone.
    TextR := Types.Rect(R.Left + P.Scale(S.Padding.Left), R.Top + P.Scale(S.Padding.Top),
      R.Right - BtnW, R.Bottom - P.Scale(S.Padding.Bottom));
    if not FieldOwnerDraw then
      PaintFieldContent(P, TextR, S);
    // v3/C5: the dropdown indicator is theme-overridable (--glyph-dropdown); else the built-in chevron.
    if FStyle <> csSimple then
      if not TyTryDrawGlyphOverride(P, ActiveController, BtnR, '--glyph-dropdown', S.TextColor) then
        P.DrawDropChevron(BtnR, S.TextColor);   // fixed small chevron (not stretched to height)
    P.EndPaint;

    { The host's field pass, on the COMPOSITED canvas. It cannot run above: the painter
      builds into a BGRA layer and EndPaint blits that over ACanvas, so a GDI draw made
      before this line is erased. Clipped to the same text zone PaintFieldContent would have
      been given, so a handler cannot paint over the frame or the chevron. Only ONE callback
      here, so the stale-DC defect the row loop guards against cannot arise -- the bracket is
      the canvas-aware pair anyway, because the next thing anyone adds beside it makes it
      two. }
    if FieldOwnerDraw then
    begin
      FieldR := TextR;
      Types.OffsetRect(FieldR, ARect.Left, ARect.Top);
      ACanvas.SaveHandleState;
      try
        IntersectClipRect(ACanvas.Handle, FieldR.Left, FieldR.Top, FieldR.Right, FieldR.Bottom);
        FOnDrawItem(Self, ACanvas, FItemIndex, FieldR, FieldOwnerDrawState);
      finally
        ACanvas.RestoreHandleState;
      end;
    end;
  finally
    P.Free;
  end;
end;

procedure TTyComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
begin
  // Default: the selected item's text (unchanged from the old inline draw).
  if FText <> '' then
    P.DrawText(ATextRect, FText, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
      AStyle.TextColor, taLeftJustify, tlCenter, True)
  else
    PaintTextHint(P, ATextRect, AStyle);
end;

procedure TTyComboBox.PaintTextHint(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
var HintColor: TTyColor;
begin
  { Only the pick-only field paints its own hint: in csDropDown the embedded TTyEdit
    covers this zone and draws the same hint itself, so drawing here too would double it.
    The dim ink is the shared 'TyTextHint' token TTyEdit resolves — no hardcoded grey. }
  if (FTextHint = '') or TyComboStyleHasEditBox(FStyle) then Exit;
  HintColor := ActiveController.Model.ResolveStyle('TyTextHint', '', []).TextColor;
  P.DrawText(ATextRect, FTextHint, AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight, HintColor, taLeftJustify, tlCenter, True);
end;

function TTyComboBox.CreatePopupList: TTyListBox;
begin
  { TTyComboPopupList, not a bare TTyListBox: the only difference is the three owner-draw
    calls, every one of which is inert while OwnerDrawsRows is False, so the default combo
    renders exactly as before. }
  Result := TTyComboPopupList.Create(Self);
end;

procedure TTyComboBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
