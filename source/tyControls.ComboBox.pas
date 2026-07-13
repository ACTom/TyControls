unit tyControls.ComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, StdCtrls, LCLType, LCLIntf,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.ListBox, tyControls.Popup, tyControls.Edit;
function TyComboTypeAheadMatch(AItems: TStrings; AStart: Integer; const APrefix: string): Integer;
function TyFilterItemsByPrefix(AItems: TStrings; const APrefix: string): TStringList;

type
  { csDropDownList = read-only (pick from list only). csDropDown = editable field
    with prefix autocomplete (an embedded TTyEdit overlays the text zone). }
  TTyComboBoxStyle = (csDropDownList, csDropDown);

  TTyComboBox = class(TTyCustomControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FText: string;
    FDropDownCount: Integer;
    FSorted: Boolean;
    FMaxLength: Integer;
    FCharCase: TEditCharCase;
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
    { Dropdown popup state }
    FPopup: TTyDropdownPopup; // lazy; created on first DropDown; freed in Destroy
    FPopupList: TTyListBox;   // owned by Self; parented into FPopup.Form via SetContent
    { Type-ahead state }
    FTypeAhead: string;
    FTypeAheadTick: QWord;
    procedure SetItems(const AValue: TStringList);
    procedure SetItemIndex(const AValue: Integer);
    procedure SetText(const AValue: string);
    procedure SetDropDownCount(const AValue: Integer);
    procedure SetSorted(const AValue: Boolean);
    procedure SetMaxLength(const AValue: Integer);
    procedure SetCharCase(const AValue: TEditCharCase);
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
    procedure SetController(AValue: TTyStyleController); override;
    { Headless-testable popup-height calculation: DropDownCount governs how many
      rows are visible before the dropdown scrolls. Separated from DropDown so it
      can be exercised without building a real win32 popup form. }
    function ComputePopupHeight(APPI: Integer): Integer;
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
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    // Field content paint (default: the selected item's text). A subclass draws a
    // swatch / glyph + text; ATextRect is the field's text zone (left of the chevron).
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); virtual;
    // Factory for the drop-down list (default: a plain TTyListBox). A subclass returns a
    // custom TTyListBox (e.g. one whose PaintItemContent draws colour swatches).
    function CreatePopupList: TTyListBox; virtual;
    // Style setter is virtual so a subclass can lock the mode (e.g. TTyColorBox forces
    // csDropDownList — a filtered editable popup would desync its per-item swatches).
    procedure SetStyle(AValue: TTyComboBoxStyle); virtual;
    procedure Paint; override;
    procedure Resize; override;
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
    procedure SelectItem(AIndex: Integer); virtual;
    function DroppedDown: Boolean;
    procedure DropDown; virtual;
    procedure CloseUp;
    { Expose popup list for headless tests and internal use }
    function PopupList: TTyListBox;
  published
    property Items: TStringList read FItems write SetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property Text: string read FText write SetText;
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
    { csDropDownList (default) = read-only; csDropDown = editable + prefix autocomplete. }
    property Style: TTyComboBoxStyle read FStyle write SetStyle default csDropDownList;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
    property OnCloseUp: TNotifyEvent read FOnCloseUp write FOnCloseUp;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;
implementation
uses
  Math, tyControls.QtWS;

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
  FPopup     := nil;
  FPopupList := nil;
  TabStop := True;
  Width := 145;
  Height := 26;
  { Editable-mode scaffolding. The editor stays hidden until Style := csDropDown. }
  FStyle := csDropDownList;
  FVisibleItems := TStringList.Create;
  FSyncingText := False;
  FShowingPopup := False;
  FEditor := TTyEdit.Create(Self);
  FEditor.Parent := Self;
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

procedure TTyComboBox.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  { In editable mode keep the visible field in sync with a programmatic Text set,
    but under the guard so it does not re-trigger the autocomplete filter/popup. }
  if (FEditor <> nil) and (FStyle = csDropDown) and (FEditor.Text <> AValue) then
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
    if FStyle = csDropDown then
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

procedure TTyComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  if FStyle = AValue then Exit;
  FStyle := AValue;
  if FEditor <> nil then
  begin
    FEditor.Visible := (FStyle = csDropDown);
    if FStyle = csDropDown then
    begin
      SetEditorText(FText);   // seed from current text without re-triggering filter
      LayoutEditor;
    end;
  end;
  Invalidate;
end;

procedure TTyComboBox.LayoutEditor;
var
  BtnW, PPI, PadL, PadT, PadR, PadB: Integer;
  S: TTyStyleSet;
begin
  if (FEditor = nil) or (FStyle <> csDropDown) then Exit;
  PPI  := Font.PixelsPerInch;
  BtnW := MulDiv(ButtonWidthLogical, PPI, 96);
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
    ClientHeight - PadT - PadB);
end;

procedure TTyComboBox.EditorChange(Sender: TObject);
var filtered: TStringList;
begin
  if FSyncingText then Exit;
  FText := FEditor.Text;
  FItemIndex := FItems.IndexOf(FText);   // -1 if not a member; do NOT blank FText
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
    idempotent. Also avoids hiding the popup synchronously inside a focus event. }
  if DroppedDown then Application.QueueAsyncCall(@DeferredCloseUp, 0);
  DoEditorCommit;   // genuine focus-out: let a subclass (MRU) remember the typed text
end;

procedure TTyComboBox.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
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
    if FStyle = csDropDownList then FText := '';
  end;
end;

procedure TTyComboBox.ItemsChanged(Sender: TObject);
begin
  { When items are added/removed (including a sorted insert that shifts indices),
    keep FItemIndex pinned to the selected item's text. }
  ResyncIndexFromText;
  Invalidate;
end;

function TTyComboBox.ComputePopupHeight(APPI: Integer): Integer;
var
  RowH, ScaledIH, VisibleRows: Integer;
begin
  { Row height = the popup list's ItemHeight (a subclass may draw taller rich rows —
    e.g. TTyAdvancedComboBox uses 40); fall back to the TTyListBox default (24) before the
    popup list exists (headless calc). Visible rows = min(Items.Count, DropDownCount), each
    scaled to the given PPI, + the 2px popup frame chrome. Single source of the sizing
    formula — DropDown calls this so the live popup and the headless calc stay in sync. }
  RowH := 24;
  if FPopupList <> nil then RowH := FPopupList.ItemHeight;
  ScaledIH := MulDiv(RowH, APPI, 96);
  VisibleRows := Min(FItems.Count, FDropDownCount);
  Result := VisibleRows * ScaledIH + 2;
end;

function TTyComboBox.ButtonWidthLogical: Integer;
begin
  Result := TyFieldButtonWidth;
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
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TTyComboBox.DroppedDown: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.IsOpen;
end;

{ Lazily create the popup helper and the list box (both live for the combo's
  lifetime — the helper reuses its form across multiple show/hide cycles). }
procedure TTyComboBox.EnsurePopup;
begin
  if FPopup <> nil then Exit;
  FPopup := TTyDropdownPopup.Create;
  FPopup.Controller := Self.Controller;
  FPopup.OnClose    := @PopupClosed;

  FPopupList := CreatePopupList;  // owned by the combo (virtual: a subclass may return a custom list)
  FPopupList.ForceSquareSurface := TyQtIsWayland;
  FPopupList.OnChange := @PopupListChange;

  { Wire the list into the helper's form (alClient; SetContent is one-shot). }
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

  FPopup.Popup(Self, Width, PopupH);
  DoDropDown;   // popup actually opened
end;

{ Editable-mode autocomplete: show the popup populated with the prefix-filtered
  subset (FVisibleItems) instead of the full list. Mirrors DropDown otherwise. }
procedure TTyComboBox.DropDownFiltered;
var
  PopupH, ScaledIH, VisibleRows: Integer;
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

  { Height off the FILTERED count (mirrors ComputePopupHeight's formula but on
    FVisibleItems, which is what is actually shown). }
  if FPopupList <> nil then                            // honour a subclass's taller rows
    ScaledIH := MulDiv(FPopupList.ItemHeight, Font.PixelsPerInch, 96)
  else
    ScaledIH := MulDiv(24, Font.PixelsPerInch, 96);
  VisibleRows := Min(FVisibleItems.Count, FDropDownCount);
  PopupH      := VisibleRows * ScaledIH + 2;

  { First open: show the popup, then immediately return focus to the editor. LCL
    focuses the popup's list on Show (which WS_EX_NOACTIVATE alone does not stop),
    so re-focusing keeps typing in the editor. FShowingPopup gates the editor's
    OnExit so this transient blur does not self-close the popup; FormDeactivate is
    suppressed for the NoActivate popup so the re-focus does not close it either.
    On later keystrokes the popup is already open — resize it IN PLACE (no Show, no
    focus churn / no per-keystroke flicker). }
  if FPopup.IsOpen then
    FPopup.Resize(Width, PopupH)
  else
  begin
    FShowingPopup := True;
    try
      FPopup.Popup(Self, Width, PopupH);
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
end;

procedure TTyComboBox.CloseUp;
begin
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
  { In editable mode a click on the text zone belongs to the embedded editor
    (caret placement / focus); only a click on the chevron toggles the dropdown. }
  if (FStyle = csDropDown) and not PointInChevron(ScreenToClient(Mouse.CursorPos)) then Exit;
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
  if FStyle = csDropDown then
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
  R, TextR, BtnR: TRect;
  BtnW: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Types.Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    BtnW := P.Scale(ButtonWidthLogical);
    BtnR := Types.Rect(R.Right - BtnW, R.Top, R.Right, R.Bottom);
    // Content honours the resolved Padding (consistent with Button/Edit/Panel);
    // the right edge stops at the chevron button zone.
    TextR := Types.Rect(R.Left + P.Scale(S.Padding.Left), R.Top + P.Scale(S.Padding.Top),
      R.Right - BtnW, R.Bottom - P.Scale(S.Padding.Bottom));
    PaintFieldContent(P, TextR, S);
    // v3/C5: the dropdown indicator is theme-overridable (--glyph-dropdown); else the built-in chevron.
    if not TyTryDrawGlyphOverride(P, ActiveController, BtnR, '--glyph-dropdown', S.TextColor) then
      P.DrawDropChevron(BtnR, S.TextColor);   // fixed small chevron (not stretched to height)
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
begin
  // Default: the selected item's text (unchanged from the old inline draw).
  if FText <> '' then
    P.DrawText(ATextRect, FText, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
      AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

function TTyComboBox.CreatePopupList: TTyListBox;
begin
  Result := TTyListBox.Create(Self);
end;

procedure TTyComboBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
