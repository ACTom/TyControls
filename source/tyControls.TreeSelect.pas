unit tyControls.TreeSelect;
{$mode objfpc}{$H+}
{ TTyTreeSelect — a combo-like FIELD whose dropdown is a real TTyTreeView: pick one value
  out of a HIERARCHY without spending a whole panel on it.

  The gap it fills: we have a tree and we have a combo, but not the two together. A form row
  that picks a department / a category / a folder had to be hand-built every time — a combo
  cannot show structure, and a tree is a full-height panel that does not fit a row.

  COMPOSITION, not a re-implementation. Two battle-tested parts are wired together and
  neither is copied:
    * TTyDropdownPopup (tyControls.Popup) — the borderless popup window: drop/flip
      placement, the rounded window region, the Qt/Wayland workarounds, deactivate-close,
      and the reopen-race tick. The same helper TTyComboBox and TTyDateTimePicker drop.
    * TTyTreeView — the real control, exposed as the public Tree property so the app builds
      its node structure (and answers OnGetText) exactly as it would for a standalone tree.
  This unit adds only what neither part has: a field that paints the pick, and the rules
  that turn "a node was clicked" into "a value was chosen".

  A WINDOWED control (TTyCustomControl), like TTyComboBox and unlike its batch siblings
  TTyTag / TTyAlert: it takes focus, Alt+Down / F4 open the drop and Escape closes it — a
  graphic control has no handle, so it could do none of that.

  typeKey 'TyComboBox' — deliberately NOT one of its own. This IS a combo field: same frame,
  same padding, same chevron zone, sitting in the same form row as a real combo; and the
  whole combo family (TTyColorBox, TTyCheckComboBox, TTyComboBoxEx, TTyMRUComboBox …) already
  shares that one key by inheritance. Reusing it means a TreeSelect is themed by every skin
  the day it lands — no .tycss change, and no chance of an unstyled control. The dropdown is
  the TREE's own 'TyTreeView' key, and an empty field's TextHint takes the library-wide
  'TyTextHint' ink (TTyEdit's hint key — same hint, same colour). }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType, LCLIntf,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.StyleModel, tyControls.Popup, tyControls.TreeView;

const
  { Built-in logical-px default (96-PPI baseline) for the drop's height when the app names
    none. A skin retunes it through the named theme metric below (the v3/C convention); this
    is only what a theme that sets it falls back from. Scaled to device px at the call site.
    It is a HEIGHT and not a row count (TTyComboBox.DropDownCount) on purpose: a tree's rows
    appear and disappear as branches expand, so "8 rows tall" would resize the window under
    the user's pointer on every expand. A tree drop is a fixed viewport that scrolls. }
  TyTreeSelectDropHeight = 220;

  { The metric token that fallback backs. A named constant rather than a literal so a typo
    cannot silently strand one call site on the default (the tyControls.Types convention). }
  TyTreeSelectDropHeightVar = '--treeselect-drop-height';

type
  { The geometry of the field, in DEVICE pixels relative to the control rect's top-left.
      TextRect   — where the pick (or the hint) is drawn; empty => nothing is drawn.
      ButtonRect — the chevron zone at the right; empty only when it was given no width. }
  TTyTreeSelectLayout = record
    TextRect: TRect;
    ButtonRect: TRect;
  end;

{ Pure geometry for the field. All inputs/outputs are DEVICE px.
    AClientWidth/AClientHeight — the control size.
    APadLeft/Top/Right/Bottom  — the themed padding.
    AButtonWidth               — the chevron zone's width.
  The chevron zone is a full-height strip hugging the right edge and it is served FIRST: it
  is the affordance that says "this drops down" (TyTagLayout's rule for its own close slot),
  so a field too narrow for both keeps it and the text collapses to empty rather than showing
  a sliver. The text band is the field inset by its padding, right-clamped to the zone's left
  edge — the zone already provides that gutter, which is why a wide chevron overrides the
  themed right padding instead of adding to it (this is what TTyComboBox.RenderTo does inline;
  here it is one function so the paint and any hit-test cannot drift apart).
  Padding that eats the whole field, or a zero size, leaves rects empty rather than inverted.
  Headless-safe: no control state, no handle — the tests call it directly. }
function TyTreeSelectFieldLayout(AClientWidth, AClientHeight, APadLeft, APadTop,
  APadRight, APadBottom, AButtonWidth: Integer): TTyTreeSelectLayout;

{ The dropdown window's size, DEVICE px.
    AFieldWidth    — the field's own width, which a zero ADropWidth follows.
    ADropWidth     — the app's DropDownWidth; <= 0 means "as wide as the field".
    ADropHeight    — the app's DropDownHeight; <= 0 means "the theme's ADefaultHeight".
    ADefaultHeight — the resolved --treeselect-drop-height.
  "0 = follow the field" is the width default because a drop that lines up with its field is
  what makes the two read as one widget; an app that needs to show deep indentation names a
  wider one. Both axes floor at 1: a popup must be a window, not a slit. }
function TyTreeSelectDropSize(AFieldWidth, ADropWidth, ADropHeight,
  ADefaultHeight: Integer): TSize;

{ What the field draws, and whether that is the HINT (which inks differently).
  The rule: a selection shows its node's caption — even an EMPTY one. A node whose caption
  is blank is still a chosen node, and showing "pick one…" over it would be a lie about the
  control's state. The hint therefore means exactly "nothing is selected", never "the text
  happens to be empty" (which is where TTyEdit's identical-looking hint differs: an edit has
  no selection to speak of, so for it empty text IS the empty state). }
function TyTreeSelectFieldText(AHasSelection: Boolean; const ANodeText, ATextHint: string;
  out AIsHint: Boolean): string;

{ Whether a click that landed on APart of a node commits that node as the pick.
  It mirrors TTyTreeView's OWN selection rule, so the picker can never commit a node the tree
  did not select (or refuse one it did): the expander and the checkbox each own their gesture
  (the tree toggles and deliberately leaves the selection alone — expanding a branch to look
  inside it must not choose it and slam the drop shut), the label/image always select, and the
  bare indent only counts when the tree is in toFullRowSelect. Anything else — empty space
  below the last node, the header band — selects nothing and so commits nothing. }
function TyTreeSelectCommitsOn(APart: TTyTreeHitPart; AFullRowSelect, AMultiSelect: Boolean): Boolean;

{ The node's MAIN-column caption, read through the TREE's own text events — the very path
  TTyTreeView.RenderTo draws the row with, so the field shows exactly the words the popup row
  shows. (TTyTreeView.GetNodeSearchText does this too, but it is private to that unit.)
  Answers '' for nil, for the hidden root, and for a tree that answers no text at all. }
function TyTreeSelectNodeText(ATree: TTyTreeView; ANode: PTyTreeNode): string;

type
  TTyTreeSelect = class;

  { The tree that lives in the drop. It exists ONLY so the picker can watch for the commit
    gestures without eating TTyTreeView.OnNodeClick / OnChange: those are the APP's events —
    the app owns this tree (it builds the nodes and answers OnGetText), and a picker that
    hijacked them would break silently the moment the app assigned one of its own. Overriding
    is the only wiring the app cannot clobber.
    With Picker = nil it is an ordinary TTyTreeView. }
  TTyTreeSelectTree = class(TTyTreeView)
  private
    FPicker: TTyTreeSelect;
  protected
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    { The tree's own typeKey. GetStyleTypeKey is PROTECTED on the base and this is not its
      unit, so the picker — which shapes the popup window to that key's resolved radius —
      reaches it through here rather than by re-spelling the key and hoping the two agree. }
    function StyleTypeKey: string;
    { The field this tree drops from; nil = a plain tree. }
    property Picker: TTyTreeSelect read FPicker write FPicker;
  end;

  { A combo-like field that drops a real tree. The app builds the hierarchy through the
    public Tree property, the user picks a node, and SelectedNode / Text carry the result.

    Colour/size variants are plain StyleClass, and because the field resolves 'TyComboBox'
    they are the COMBO's variants — 'TyComboBox.small' dresses a TreeSelect and a ComboBox
    identically, which is the point of sharing the key. }
  TTyTreeSelect = class(TTyCustomControl)
  private
    FTree: TTyTreeSelectTree;
    FPopup: TTyDropdownPopup;      // lazy; created on first DropDown; freed in Destroy
    FSelectedNode: PTyTreeNode;
    { The pick's caption, cached at selection time. The field NEVER derefs the node while
      painting: node pointers are the app's to free (TTyTreeView is a virtual tree), and a
      paint that re-read a deleted node would be a dangling read on every Invalidate. See
      UpdateText for the "the caption changed under us" case. }
    FText: string;
    FTextHint: string;
    FDropDownWidth: Integer;
    FDropDownHeight: Integer;
    FCloseUpTick: QWord;           // tick at last CloseUp — the reopen-race guard
    FOnChange: TNotifyEvent;
    FOnDropDown: TNotifyEvent;
    FOnCloseUp: TNotifyEvent;
    procedure SetSelectedNode(AValue: PTyTreeNode);
    procedure SetTextHint(const AValue: string);
    procedure SetDropDownWidth(AValue: Integer);
    procedure SetDropDownHeight(AValue: Integer);
    function GetFieldText: string;
    { A property's read must name a field of its OWN type, and FTree is the descendant —
      hence the getter for a plain TTyTreeView view of it. }
    function GetTree: TTyTreeView;
    { TTyDropdownPopup.OnClose: the single bookkeeping point for a popup that closed for ANY
      reason (click-away, Escape, a pick, a programmatic CloseUp). }
    procedure PopupClosed(Sender: TObject);
    procedure PopupFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DeferredCloseUp(Data: PtrInt);
  protected
    function GetStyleTypeKey: string; override;
    procedure SetController(AValue: TTyStyleController); override;
    { Create the popup helper and park the tree in it. Lazy (the window is only needed once
      the user drops), unlike the TREE itself, which exists from the constructor because the
      app populates it long before — and maybe without ever — opening the drop. }
    procedure EnsurePopup;
    { Point the tree's focus/selection at the field's pick, and scroll it into view. Called on
      every open, so a drop always opens ON the current value however it was set — and a
      cancelled navigation (arrow keys move the tree's own selection) is undone by the next
      open rather than leaking into the field. A nil pick CLEARS the tree's selection: the
      popup must not highlight a row the field does not name. }
    procedure SyncTreeToSelection;
    { The field's geometry, fed from the resolved theme. AWidth/AHeight are device px so
      nothing here reads Width behind the caller's back. }
    function LayoutFor(AWidth, AHeight, APPI: Integer): TTyTreeSelectLayout;
    procedure DoChange; virtual;
    procedure DoDropDown; virtual;
    procedure DoCloseUp; virtual;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Click; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Open the drop. No-op when disabled, already open, or within 200ms of a CloseUp (the
      click-while-open reopen race: the popup deactivates and closes BEFORE this control's
      Click handler runs, so Click would see a closed popup and re-open it). }
    procedure DropDown;
    { Hide the drop (idempotent). Fires OnCloseUp. }
    procedure CloseUp;
    function DroppedDown: Boolean;
    { Commit ANode as the user's pick: select it (OnChange fires when the value actually
      changed) and close the drop. This is what a click / Enter in the popup runs; public so a
      host can drive the same gesture from a shortcut or a context menu. }
    procedure PickNode(ANode: PTyTreeNode);
    { Nothing selected: Text goes empty and the TextHint (if any) takes over. }
    procedure ClearSelection;
    { Re-read the selected node's caption into Text. Call it when what the tree answers for
      the CURRENT pick changed (the app renamed the node). No OnChange — the value did not
      change, only its label. }
    procedure UpdateText;
    { The dropdown window's size in DEVICE px at this field's PPI — what DropDown will ask
      for. Public: a host may want to know, and it is the seam the sizing rules are tested
      through (opening a real window is not a headless act). }
    function DropDownSize: TSize;
    { The tree in the drop. THE app-facing surface: build the hierarchy on it (AddChild /
      RootNodeCount / OnInitChildren), answer OnGetText on it, set its Options / Images /
      Indent on it. It is not published — a virtual tree's nodes are pointers, so there is
      nothing for the .lfm to stream; populate it from code (FormCreate), as VirtualTreeView
      has always been used.
      NOTE (a repo trap): if you give it COLUMNS, set Header.MainColumn AFTER Columns.Add —
      setting it first clamps it to NoColumn and the main column never paints. }
    property Tree: TTyTreeView read GetTree;
    { The chosen node, or nil. Setting it is a programmatic pick: Text re-caches and OnChange
      fires, but the drop does not close and the tree is not touched until it next opens (see
      SyncTreeToSelection). The pointer is the APP's: delete the node from the tree and this
      dangles, exactly as any PTyTreeNode the app holds does — clear or re-set it first. }
    property SelectedNode: PTyTreeNode read FSelectedNode write SetSelectedNode;
    { The pick's caption; '' when nothing is selected. Read-only: the value here is a NODE —
      text is what it looks like, not what it is, and writing a caption could not name one. }
    property Text: string read GetFieldText;
  published
    { Drawn in the 'TyTextHint' ink while nothing is selected (the same key, and so the same
      dim colour, as TTyEdit.TextHint). A selected node's blank caption is NOT the empty
      state and does not bring it back. }
    property TextHint: string read FTextHint write SetTextHint;
    { The drop's width in LOGICAL px; 0 (default) = as wide as the field. }
    property DropDownWidth: Integer read FDropDownWidth write SetDropDownWidth default 0;
    { The drop's height in LOGICAL px; 0 (default) = the theme's --treeselect-drop-height. }
    property DropDownHeight: Integer read FDropDownHeight write SetDropDownHeight default 0;
    { The pick changed — by the user, or by writing SelectedNode. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { Fired BEFORE the popup window shows (unlike TTyComboBox, which fires it after): a tree
      is the one drop whose content is routinely built on demand, and this is the hook that
      has to be able to (re)populate Tree while the size is still being decided. }
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
    property OnCloseUp: TNotifyEvent read FOnCloseUp write FOnCloseUp;
    property TabStop default True;
    property Align;
    property Anchors;
    property Enabled;
    property Font;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

implementation

{ --- pure rules / geometry ---------------------------------------------------- }

function TyTreeSelectFieldLayout(AClientWidth, AClientHeight, APadLeft, APadTop,
  APadRight, APadBottom, AButtonWidth: Integer): TTyTreeSelectLayout;
var
  btnL, textL, textR, textT, textB: Integer;
begin
  Result.TextRect := Rect(0, 0, 0, 0);
  Result.ButtonRect := Rect(0, 0, 0, 0);
  if (AClientWidth <= 0) or (AClientHeight <= 0) then Exit;
  // Clamp every negative input once, here, so the arithmetic below reads straight.
  if APadLeft < 0 then APadLeft := 0;
  if APadTop < 0 then APadTop := 0;
  if APadRight < 0 then APadRight := 0;
  if APadBottom < 0 then APadBottom := 0;
  if AButtonWidth < 0 then AButtonWidth := 0;

  btnL := AClientWidth - AButtonWidth;
  if btnL < 0 then btnL := 0;   // narrower than its own chevron: the zone takes what there is
  if AButtonWidth > 0 then
    Result.ButtonRect := Rect(btnL, 0, AClientWidth, AClientHeight);

  textL := APadLeft;
  textR := AClientWidth - APadRight;
  if textR > btnL then textR := btnL;   // the chevron zone IS the right gutter
  textT := APadTop;
  textB := AClientHeight - APadBottom;
  if (textR > textL) and (textB > textT) then
    Result.TextRect := Rect(textL, textT, textR, textB);
end;

function TyTreeSelectDropSize(AFieldWidth, ADropWidth, ADropHeight,
  ADefaultHeight: Integer): TSize;
begin
  if ADropWidth > 0 then
    Result.cx := ADropWidth
  else
    Result.cx := AFieldWidth;
  if ADropHeight > 0 then
    Result.cy := ADropHeight
  else
    Result.cy := ADefaultHeight;
  if Result.cx < 1 then Result.cx := 1;
  if Result.cy < 1 then Result.cy := 1;
end;

function TyTreeSelectFieldText(AHasSelection: Boolean; const ANodeText, ATextHint: string;
  out AIsHint: Boolean): string;
begin
  AIsHint := False;
  if AHasSelection then
  begin
    Result := ANodeText;   // even '' — see the interface comment
    Exit;
  end;
  Result := ATextHint;
  AIsHint := Result <> '';   // no hint set: an empty field, not an empty hint drawn dimly
end;

function TyTreeSelectCommitsOn(APart: TTyTreeHitPart; AFullRowSelect, AMultiSelect: Boolean): Boolean;
begin
  case APart of
    hpLabel, hpImage: Result := True;
    // The rule must MIRROR what the tree itself selects on an indent-strip click, or the field
    // refuses a node the tree visibly highlighted (the documented "can never refuse a node the
    // tree did select" invariant). The tree selects on hpIndent when toFullRowSelect is on OR
    // when it is SINGLE-select (single-select's MouseDown selects any node part). Only in
    // multi-select without full-row does the indent strip not select.
    hpIndent: Result := AFullRowSelect or (not AMultiSelect);
  else
    // hpButton / hpCheckBox own their own gesture; hpNowhere and the header parts are not a
    // node at all. Listed as the fall-through so a TTyTreeHitPart added later defaults to
    // "does not commit" — a new part that silently chose a value would be the worse bug.
    Result := False;
  end;
end;

function TyTreeSelectNodeText(ATree: TTyTreeView; ANode: PTyTreeNode): string;
begin
  Result := '';
  if (ATree = nil) or (ANode = nil) or (ANode = ATree.RootNode) then Exit;
  if Assigned(ATree.OnGetTextWithType) then
    ATree.OnGetTextWithType(ATree, ANode, ATree.Header.MainColumn, ttNormal, Result)
  else if Assigned(ATree.OnGetText) then
    ATree.OnGetText(ATree, ANode, Result);
end;

{ --- TTyTreeSelectTree -------------------------------------------------------- }

function TTyTreeSelectTree.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;   // reachable here: we ARE a TTyTreeView
end;

procedure TTyTreeSelectTree.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  hitNode: PTyTreeNode;
  hitPart: TTyTreeHitPart;
begin
  // The base first: it owns the selection, the expand toggle and the drag state machine, and
  // the commit below is only allowed to happen ON TOP of whatever it decided.
  inherited MouseUp(Button, Shift, X, Y);
  if (FPicker = nil) or (Button <> mbLeft) then Exit;
  hitNode := GetNodeAtPoint(X, Y, hitPart);
  if (hitNode <> nil) and TyTreeSelectCommitsOn(hitPart, toFullRowSelect in Options, toMultiSelect in Options) then
    FPicker.PickNode(hitNode);
end;

procedure TTyTreeSelectTree.KeyDown(var Key: Word; Shift: TShiftState);
begin
  // BEFORE the base: TTyTreeView's own VK_RETURN fires OnNodeDblClick and consumes the key,
  // so a picker that waited for `inherited` would never see Enter at all.
  if (FPicker <> nil) and (Key = VK_RETURN) and (FocusedNode <> nil) then
  begin
    Key := 0;
    FPicker.PickNode(FocusedNode);
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

{ --- TTyTreeSelect ------------------------------------------------------------ }

constructor TTyTreeSelect.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelectedNode := nil;
  FText := '';
  FTextHint := '';
  FDropDownWidth := 0;
  FDropDownHeight := 0;
  FCloseUpTick := 0;
  FPopup := nil;
  TabStop := True;
  // The combo's drop size: a TreeSelect must sit in a row of combos without a seam.
  Width := 145;
  Height := TyDensityHeight(ActiveController, 26);
  { The tree exists from the start — the app populates it in FormCreate, long before (and
    perhaps without ever) a drop. Owned by Self, so the component chain frees it; it is only
    PARENTED into the popup form, which never owns it (TTyDropdownPopup.SetContent). }
  FTree := TTyTreeSelectTree.Create(Self);
  FTree.Picker := Self;
end;

destructor TTyTreeSelect.Destroy;
begin
  { A queued DeferredCloseUp must not fire into a freed field. }
  Application.RemoveAsyncCalls(Self);
  { Free the popup helper first: hiding its form fires OnClose (PopupClosed), which would
    re-enter a half-destroyed picker. Detach, then free the helper + its window. }
  if FPopup <> nil then
    FPopup.OnClose := nil;
  FreeAndNil(FPopup);
  { The tree is owned by Self (not by the popup form), so it outlived the window above and is
    freed here — after it, so nothing can reach it through a dying form. }
  FreeAndNil(FTree);
  inherited Destroy;
end;

function TTyTreeSelect.GetStyleTypeKey: string;
begin
  // Not 'TyTreeSelect': see the unit header. This IS a combo field.
  Result := 'TyComboBox';
end;

function TTyTreeSelect.GetTree: TTyTreeView;
begin
  Result := FTree;
end;

function TTyTreeSelect.GetFieldText: string;
begin
  Result := FText;
end;

procedure TTyTreeSelect.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
  { Keep the parts themed by the same controller when it is reassigned; otherwise the tree
    keeps the old theme until the next DropDown re-syncs it. }
  if FTree <> nil then
    FTree.Controller := AValue;
  if FPopup <> nil then
    FPopup.Controller := AValue;
end;

{ --- selection ---------------------------------------------------------------- }

procedure TTyTreeSelect.SetSelectedNode(AValue: PTyTreeNode);
begin
  if FSelectedNode = AValue then Exit;
  FSelectedNode := AValue;
  FText := TyTreeSelectNodeText(FTree, AValue);   // cache now; never deref at paint time
  Invalidate;
  DoChange;
end;

procedure TTyTreeSelect.ClearSelection;
begin
  SetSelectedNode(nil);
end;

procedure TTyTreeSelect.UpdateText;
begin
  FText := TyTreeSelectNodeText(FTree, FSelectedNode);
  Invalidate;
end;

procedure TTyTreeSelect.PickNode(ANode: PTyTreeNode);
begin
  SetSelectedNode(ANode);
  { Deferred: hiding the popup synchronously here — still inside the tree's mouse/key
    handler — leaves LCL's click-completion focus path pointing at the now-hidden popup form
    (EInvalidOperation '[TCustomForm.SetFocus] … Can not focus'), the exact trap
    TTyComboBox's row-pick documents. Closing next message cycle lets the click finish. }
  if DroppedDown then
    Application.QueueAsyncCall(@DeferredCloseUp, 0);
end;

procedure TTyTreeSelect.SyncTreeToSelection;
begin
  if FTree = nil then Exit;
  if FSelectedNode = nil then
  begin
    FTree.ClearSelection;   // no pick => no highlighted row (no-op when nothing is selected)
    Exit;
  end;
  FTree.FocusedNode := FSelectedNode;      // focusing selects, in single-select mode
  FTree.Selected[FSelectedNode] := True;   // idempotent: covers focus ALREADY being there,
                                           // where the setter above short-circuits
  FTree.ScrollIntoView(FSelectedNode);
end;

{ --- dropdown ----------------------------------------------------------------- }

procedure TTyTreeSelect.EnsurePopup;
begin
  if FPopup <> nil then Exit;
  FPopup := TTyDropdownPopup.Create;
  { ActiveController, never the raw Controller: a field themed by the global default has
    Controller = nil, and handing that on would leave the parts unthemed (the AV this exact
    line caused in TTyDateTimePicker's dropdown). }
  FPopup.Controller := ActiveController;
  FPopup.OnClose := @PopupClosed;
  FTree.Controller := ActiveController;
  { SetContent only PARENTS the tree (alClient) into the helper's form — no ownership moves,
    which is why Destroy can free the form and the tree independently. }
  FPopup.SetContent(FTree);
  { Escape closes from anywhere in the popup, whatever has focus inside it. }
  FPopup.Form.KeyPreview := True;
  FPopup.Form.OnKeyDown := @PopupFormKeyDown;
end;

function TTyTreeSelect.DropDownSize: TSize;
var
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  Result := TyTreeSelectDropSize(Width,
    MulDiv(FDropDownWidth, ppi, 96), MulDiv(FDropDownHeight, ppi, 96),
    MulDiv(ActiveController.Metric(TyTreeSelectDropHeightVar, TyTreeSelectDropHeight), ppi, 96));
end;

procedure TTyTreeSelect.DropDown;
var
  sz: TSize;
  treeStyle: TTyStyleSet;
begin
  if not Enabled then Exit;
  if DroppedDown then Exit;
  { The click-while-open reopen race: the popup deactivates → Close → PopupClosed BEFORE this
    control's Click runs, so DroppedDown is already False there and a click on an open field
    would re-open instead of closing it. }
  if GetTickCount64 - FCloseUpTick <= 200 then Exit;

  EnsurePopup;
  { Re-sync every open so a theme / DPI change since the last one takes effect. }
  FPopup.Controller := ActiveController;
  FTree.Controller := ActiveController;
  { Shape the popup window to the TREE's own resolved radius, so the window's corners match
    the fill the tree paints into them (TTyComboBox does this from its list's radius). }
  treeStyle := ActiveController.Model.ResolveStyle(FTree.StyleTypeKey, FTree.StyleClass, []);
  FPopup.CornerRadiusLogical := treeStyle.BorderRadius;

  DoDropDown;             // BEFORE the window: the hook that may (re)populate the tree
  SyncTreeToSelection;    // ...and after it, so a just-built tree still opens on the value
  sz := DropDownSize;
  FPopup.Popup(Self, sz.cx, sz.cy);
  Invalidate;
end;

procedure TTyTreeSelect.CloseUp;
begin
  if (FPopup <> nil) and FPopup.IsOpen then
  begin
    FPopup.Close;   // → PopupClosed: stamps the tick, invalidates, fires OnCloseUp
    Exit;
  end;
  { No window (headless, or already closed): still stamp the tick and fire the bookkeeping so
    the reopen guard works and a host sees the same events either way. }
  FCloseUpTick := GetTickCount64;
  Invalidate;
  DoCloseUp;
end;

function TTyTreeSelect.DroppedDown: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.IsOpen;
end;

procedure TTyTreeSelect.PopupClosed(Sender: TObject);
begin
  { Mirror the helper's tick into our own so the Click guard can use it without reaching into
    FPopup (and so it survives the helper being freed). }
  if FPopup <> nil then
    FCloseUpTick := FPopup.CloseUpTick;
  Invalidate;
  DoCloseUp;
end;

procedure TTyTreeSelect.PopupFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    CloseUp;   // dismiss without committing — the tree's own selection is re-seeded next open
    Key := 0;
  end;
end;

procedure TTyTreeSelect.DeferredCloseUp(Data: PtrInt);
begin
  CloseUp;
end;

{ --- events ------------------------------------------------------------------- }

procedure TTyTreeSelect.DoChange;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyTreeSelect.DoDropDown;
begin
  if Assigned(FOnDropDown) then FOnDropDown(Self);
end;

procedure TTyTreeSelect.DoCloseUp;
begin
  if Assigned(FOnCloseUp) then FOnCloseUp(Self);
end;

{ --- property setters --------------------------------------------------------- }

procedure TTyTreeSelect.SetTextHint(const AValue: string);
begin
  if FTextHint = AValue then Exit;
  FTextHint := AValue;
  Invalidate;   // only visible while nothing is selected; a repaint decides that
end;

procedure TTyTreeSelect.SetDropDownWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;   // "<= 0 = follow the field" has one spelling
  if FDropDownWidth = AValue then Exit;
  FDropDownWidth := AValue;
  { No live resize of an open popup: the size is decided at open, and re-sizing the window
    under the user's pointer is worse than applying it on the next drop. }
end;

procedure TTyTreeSelect.SetDropDownHeight(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FDropDownHeight = AValue then Exit;
  FDropDownHeight := AValue;
end;

{ --- input -------------------------------------------------------------------- }

procedure TTyTreeSelect.Click;
begin
  if not Enabled then Exit;
  inherited Click;
  { The whole field is the drop affordance (there is no editable zone to protect, as
    TTyComboBox's csDropDown has): a click anywhere toggles. DropDown's own 200ms guard
    handles the case where the click already closed the popup by deactivating it. }
  if DroppedDown then
    CloseUp
  else
    DropDown;
end;

procedure TTyTreeSelect.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and DroppedDown then
  begin
    CloseUp;
    Key := 0;
    Exit;
  end;
  { Alt+Down / F4 — the OS-standard "open this combo" keys. No plain Up/Down stepping (the
    combo's): a hierarchy has no linear "next value" a blind step could name, and stepping
    into a collapsed branch from a closed field would pick nodes the user cannot see. }
  if ((Key = VK_DOWN) and (ssAlt in Shift)) or (Key = VK_F4) then
  begin
    if DroppedDown then CloseUp else DropDown;
    Key := 0;
  end;
end;

{ --- painting ----------------------------------------------------------------- }

function TTyTreeSelect.LayoutFor(AWidth, AHeight, APPI: Integer): TTyTreeSelectLayout;
var
  S: TTyStyleSet;
begin
  if APPI <= 0 then APPI := 96;
  S := CurrentStyle;
  // MulDiv(...,APPI,96) is the same logical->device conversion TTyPainter.Scale applies, so
  // the rects measured here are the rects the paint drew.
  Result := TyTreeSelectFieldLayout(AWidth, AHeight,
    MulDiv(S.Padding.Left, APPI, 96), MulDiv(S.Padding.Top, APPI, 96),
    MulDiv(S.Padding.Right, APPI, 96), MulDiv(S.Padding.Bottom, APPI, 96),
    MulDiv(ActiveController.Metric('--field-button-width', TyFieldButtonWidth), APPI, 96));
end;

procedure TTyTreeSelect.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, hintS: TTyStyleSet;
  R: TRect;
  Lay: TTyTreeSelectLayout;
  shown: string;
  isHint: Boolean;
  ink: TTyColor;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at ARect.Left/Top,
    // so a non-zero ARect origin would shift the field.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    if not (tpBackground in S.Present) then
    begin
      // A theme that does not define the combo field gets no field at all rather than a
      // hard-coded one. Degrade, never crash, never invent a colour.
      P.EndPaint;
      Exit;
    end;
    DrawFrame(P, R, S);   // background + border + shadow + opacity + focus ring

    if not (tpTextColor in S.Present) then
    begin
      // No ink to draw WITH. The text and the chevron are the only things left, and both
      // would have to be invented — so draw neither (the frame above still says where the
      // field is). Never a hard-coded colour.
      P.EndPaint;
      Exit;
    end;

    Lay := LayoutFor(R.Right - R.Left, R.Bottom - R.Top, APPI);
    shown := TyTreeSelectFieldText(FSelectedNode <> nil, FText, FTextHint, isHint);
    ink := S.TextColor;
    if isHint then
    begin
      // The library-wide hint key (TTyEdit.TextHint's). No colour of its own -> the hint just
      // takes the field's ink: dimmer is nicer, but inventing a grey is not an option.
      hintS := ActiveController.Model.ResolveStyle('TyTextHint', '', []);
      if tpTextColor in hintS.Present then
        ink := hintS.TextColor;
    end;

    if (shown <> '') and (Lay.TextRect.Right > Lay.TextRect.Left) then
      // Left-aligned + ellipsised, exactly like the combo's field: a pick too long for the
      // field shows 'Engineer…', not a glyph sheared at the clip edge.
      P.DrawText(Lay.TextRect, shown, S.FontName, ResolveFontSize(S), S.FontWeight,
        ink, taLeftJustify, tlCenter, True);

    if Lay.ButtonRect.Right > Lay.ButtonRect.Left then
      // v3/C5: the drop indicator is theme-overridable (--glyph-dropdown); else the built-in
      // chevron. The same two lines TTyComboBox draws, so the two fields' chevrons cannot
      // drift apart. Always the FIELD's ink — the chevron belongs to the field, not the hint.
      if not TyTryDrawGlyphOverride(P, ActiveController, Lay.ButtonRect, '--glyph-dropdown',
        S.TextColor) then
        P.DrawDropChevron(Lay.ButtonRect, S.TextColor);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyTreeSelect.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
