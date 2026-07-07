unit tyControls.ValueListEditor;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.Controller, tyControls.ListBox, tyControls.Edit, tyControls.ImageCollection,
  tyControls.Popup;

type
  { How a row's VALUE cell is edited. Layer 1 implements vekText (inline TTyEdit) and vekReadOnly;
    the typed editors (bool/enum/colour/font/dialog) are added in a later layer but the kind is
    stored now so the model is complete. }
  TTyValueEditorKind = (vekText, vekInteger, vekFloat, vekBoolean, vekEnum, vekColor, vekFont,
    vekDialog, vekReadOnly);

  { One row of the property inspector: a key/value pair with optional display overrides, a value
    type, per-row styling, and CHILD rows (nesting). Owns its children. }
  TTyValueRow = class
  private
    FChildren: array of TTyValueRow;
    function GetChild(AIndex: Integer): TTyValueRow;
  public
    Key: string;
    DisplayKey: string;      // shown in the key column; '' => use Key (for i18n / formatting)
    Value: string;           // the actual value (text form)
    DisplayValue: string;    // shown in the value column; '' => use Value
    EditorKind: TTyValueEditorKind;
    EnumValues: string;      // vekEnum: options, one per line
    ReadOnly: Boolean;
    Bold: Boolean;           // draw the value bold
    TextColor: TColor;       // value colour; clDefault => theme
    ImageIndex: Integer;     // value cell image (via the editor's Images); -1 => none
    Expanded: Boolean;
    constructor Create;
    destructor Destroy; override;
    // Append a child row (nesting). Returns it for further configuration.
    function AddChild(const AKey, AValue: string): TTyValueRow;
    function ChildCount: Integer;
    property Child[AIndex: Integer]: TTyValueRow read GetChild;
    function HasChildren: Boolean;
    function EffectiveKey: string;     // DisplayKey or Key
    function EffectiveValue: string;   // DisplayValue or Value
  end;

  { Fired after a value cell commits with a changed value. }
  TTyValueEditEvent = procedure(Sender: TObject; ARow: TTyValueRow) of object;

  { Input restriction for the inline editor: vnmInteger allows only digits + a leading '-';
    vnmFloat additionally allows a single '.'. }
  TTyValueNumericMode = (vnmNone, vnmInteger, vnmFloat);

  { Which kind of pick list is currently dropped. }
  TTyValueDropKind = (dkNone, dkEnum, dkColor);

  { The inline VALUE editor: a TTyEdit that can (a) restrict typing to a number and (b) show a
    trailing "…" button. The text stays freely clickable / selectable / copyable — only the "…"
    fires OnEllipsis (which opens the dialog). Reused for every editable value kind. }
  TTyValueEdit = class(TTyEdit)
  private
    FNumericMode: TTyValueNumericMode;
    FShowEllipsis: Boolean;
    FOnEllipsis: TNotifyEvent;
  protected
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet); override;
    function FilterInsert(const AText: string): string; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    property NumericMode: TTyValueNumericMode read FNumericMode write FNumericMode;
    property ShowEllipsis: Boolean read FShowEllipsis write FShowEllipsis;
    property OnEllipsis: TNotifyEvent read FOnEllipsis write FOnEllipsis;
  end;

  { A property-inspector-class two-column editor: a KEY column (labels, with expand/collapse
    triangles for nested rows) and an editable VALUE column, split by a DRAGGABLE divider. Rows
    are TTyValueRow objects (Key/DisplayKey, Value/DisplayValue, a value TYPE, per-row bold/colour/
    image, and CHILD rows). Build with AddRow (returns the row to nest / type / style) or the
    simple InsertRow(key, value). Row layout, selection and scrolling come from TTyListBox. }
  TTyValueListEditor = class(TTyListBox)
  private
    FRoot: array of TTyValueRow;      // owned root rows
    FFlatRow: array of TTyValueRow;   // visible (expanded) rows, flattened
    FFlatLevel: array of Integer;     // indent level per flat row
    FEditor: TTyValueEdit;
    FEditFlat: Integer;               // flat index being edited, or -1
    FEndingEdit: Boolean;
    FRebuilding: Boolean;
    FDropMode: Boolean;               // a boolean/enum/colour dropdown is open (suppresses OnExit commit)
    FDropSeeding: Boolean;            // guard while seeding the dropdown's selection
    FDropKind: TTyValueDropKind;      // which pick list is dropped (enum text vs colour swatches)
    FDropPopup: TTyDropdownPopup;     // lazy dropdown shared by bool/enum and colour
    FEnumList: TTyListBox;            // content for vekBoolean / vekEnum
    FColorList: TTyListBox;           // content for vekColor (a TTyColorMorePopupList instance)
    FMoreCaption: string;             // vekColor: the trailing "more…" row caption
    FColorDlgRow: TTyValueRow;        // row awaiting the deferred "more…" colour dialog (by identity), or nil
    FKeyColumnWidth: Integer;         // logical px
    FIndent: Integer;                 // logical px per nesting level
    FReadOnly: Boolean;
    FDraggingSplit: Boolean;
    FImages: TTyVirtualImageList;
    FOnValueChanged: TTyValueEditEvent;
    FOnEditRow: TTyValueEditEvent;    // vekDialog: the app shows a dialog + sets ARow.Value
    function Dp(ALogical: Integer): Integer;
    function ContentLeftDp: Integer;
    function ContentRightDp: Integer;
    function ContentTopDp: Integer;
    function SplitXDp: Integer;
    function CellRect(AFlat, ACol: Integer): TRect;   // client px; col 0=key,1=value
    function FlatAtY(AY: Integer): Integer;           // flat index at client Y (or -1)
    function TriangleHit(AFlat, AX: Integer): Boolean;
    function OverSplit(AX: Integer): Boolean;
    procedure RebuildFlat;
    procedure AppendFlat(ARow: TTyValueRow; ALevel: Integer);
    procedure FreeRows;
    function GetKey(AIndex: Integer): string;
    function GetValue(AIndex: Integer): string;
    procedure SetValue(AIndex: Integer; const AValue: string);
    function GetValueOf(const AKey: string): string;
    procedure SetValueOf(const AKey, AValue: string);
    procedure SetKeyColumnWidth(AValue: Integer);
    procedure SetImages(const AValue: TTyVirtualImageList);
    procedure CommitEditor(AFlat: Integer; const AText: string);
    procedure CommitEditorRow(ARow: TTyValueRow; const AText: string);
    function RowExists(ARow: TTyValueRow): Boolean;
    procedure BeginInlineEdit(AFlat: Integer; ANumeric: TTyValueNumericMode; AEllipsis: Boolean);
    procedure BeginDropdown(AFlat: Integer; const AOptions: string);
    procedure BeginColorDropdown(AFlat: Integer);
    procedure EnsureDropPopup;
    procedure ConfigureDropCorners;
    procedure HandleDropCommit;
    procedure DeferredColorDialog(Data: PtrInt);
    procedure DropPick(Sender: TObject);
    procedure DropClick(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure DropClosed(Sender: TObject);
    procedure EditorEllipsis(Sender: TObject);
    procedure EditFontRow(AFlat: Integer);
    procedure SeedFontFromRow(ARow: TTyValueRow; AFont: TFont);
    procedure SyncFontChildren(ARow: TTyValueRow; AFont: TFont);
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorExit(Sender: TObject);
    procedure EndEdit(ACommit: Boolean; ARestoreFocus: Boolean = False);
    procedure RepositionEditor;
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure SetController(AValue: TTyStyleController); override;
    procedure SetTopIndex(const AValue: Integer); override;
    procedure Resize; override;
    procedure Paint; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Append a root row and return it (nest via its AddChild, set EditorKind / style, etc.).
    function AddRow(const AKey, AValue: string): TTyValueRow;
    // Simple form: append a plain text root row (kept for the previous API).
    procedure InsertRow(const AKey, AValue: string);
    procedure Clear;
    // Number of ROOT rows.
    function RowCount: Integer;
    // Root row AIndex (nil out of range).
    function Row(AIndex: Integer): TTyValueRow;
    // Remove root row AIndex (frees it + its children; cancels any edit).
    procedure DeleteRow(AIndex: Integer);
    // Rebuild the visible list from the current tree. Call after adding CHILD rows via
    // TTyValueRow.AddChild (the simple AddRow / InsertRow / DeleteRow / SetExpanded rebuild
    // on their own; direct child mutation is invisible to the control until UpdateRows).
    procedure UpdateRows;
    // Expand / collapse a row (rebuilds the visible list).
    procedure SetExpanded(ARow: TTyValueRow; AExpanded: Boolean);
    // Start editing the VISIBLE row at flat index AFlat (no-op when ReadOnly / read-only row).
    procedure BeginEdit(AFlat: Integer);
    // Run the dialog editor for a vekFont / vekDialog row (what the inline "…" button triggers).
    procedure InvokeRowDialog(AFlat: Integer);
    // Number of VISIBLE (expanded) rows — root rows plus expanded descendants.
    function VisibleRowCount: Integer;
    // The visible (flat) index being edited, or -1.
    property EditingRow: Integer read FEditFlat;
    property Keys[AIndex: Integer]: string read GetKey;                 // root rows
    property Values[AIndex: Integer]: string read GetValue write SetValue;
    property ValueOf[const AKey: string]: string read GetValueOf write SetValueOf;
    property InlineEditor: TTyValueEdit read FEditor;
  published
    property KeyColumnWidth: Integer read FKeyColumnWidth write SetKeyColumnWidth default 110;
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    property Images: TTyVirtualImageList read FImages write SetImages;
    property OnValueChanged: TTyValueEditEvent read FOnValueChanged write FOnValueChanged;
    // Fires for a vekDialog row (click its value / '…'): show a custom dialog and set ARow.Value.
    property OnEditRow: TTyValueEditEvent read FOnEditRow write FOnEditRow;
  end;

{ Parse a 'Name, Size' font descriptor defensively. The LAST comma-separated token that is a
  pure integer is the size; everything before it rejoins as the name (so a family name that
  itself contains commas is preserved). Returns True only when a numeric size was found —
  callers must NOT force a default size when it's False, or a real stored size is silently lost. }
function TyParseFontDescriptor(const ADesc: string; out AName: string; out ASize: Integer): Boolean;

implementation

uses
  Forms, BGRABitmap, BGRABitmapTypes, BGRACanvas2D, tyControls.ColorMath,
  tyControls.ColorBox, tyControls.ColorComboBox,
  tyControls.Dialogs.Color, tyControls.Dialogs.Font;

function TyParseFontDescriptor(const ADesc: string; out AName: string; out ASize: Integer): Boolean;
var i, p: Integer;
begin
  p := 0;
  for i := Length(ADesc) downto 1 do
    if ADesc[i] = ',' then begin p := i; Break; end;
  Result := (p > 0) and TryStrToInt(Trim(Copy(ADesc, p + 1, MaxInt)), ASize);
  if Result then
    AName := Trim(Copy(ADesc, 1, p - 1))
  else
  begin
    AName := Trim(ADesc);   // no numeric token: the whole descriptor is the name
    ASize := 0;
  end;
end;

{ ---- TTyValueEdit ---- }

function TTyValueEdit.RightReserve(APPI: Integer): Integer;
begin
  if FShowEllipsis then Result := MulDiv(18, APPI, 96) else Result := 0;
end;

procedure TTyValueEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect;
  const AStyle: TTyStyleSet);
begin
  if not FShowEllipsis then Exit;
  APainter.DrawText(AZone, '…', AStyle.FontName, ResolveFontSize(AStyle) + 2, 700,
    AStyle.TextColor, taCenter, tlCenter, False);
end;

{ Scrub an insertion (typing / paste / IME) down to a valid number fragment. Called after any
  selected text is removed, so Text/CaretPos are the residual state: a '-' is accepted only at the
  very front and only once; a '.' only for vnmFloat and only once; everything non-digit is dropped. }
function TTyValueEdit.FilterInsert(const AText: string): string;
var i: Integer; ch: Char; hasDot, hasMinus, atFront: Boolean;
begin
  if FNumericMode = vnmNone then Exit(inherited FilterInsert(AText));
  Result := '';
  hasDot   := Pos('.', Text) > 0;
  hasMinus := Pos('-', Text) > 0;
  atFront  := CaretPos = 0;
  for i := 1 to Length(AText) do
  begin
    ch := AText[i];
    if (ch >= '0') and (ch <= '9') then
      Result := Result + ch
    else if (ch = '-') and atFront and (Result = '') and not hasMinus then
    begin
      Result := Result + ch; hasMinus := True;   // a single leading minus
    end
    else if (ch = '.') and (FNumericMode = vnmFloat) and not hasDot then
    begin
      Result := Result + ch; hasDot := True;      // one decimal point (float only)
    end;
    // any other character (letters, extra sign/dot, multi-byte) is dropped
  end;
end;

procedure TTyValueEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FShowEllipsis and (Button = mbLeft)
    and PtInRect(TrailingZone(Font.PixelsPerInch), Point(X, Y)) then
  begin
    if Assigned(FOnEllipsis) then FOnEllipsis(Self);
    Exit;   // the "…" button consumed the click — don't move the caret / select
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

{ ---- TTyValueRow ---- }

constructor TTyValueRow.Create;
begin
  inherited Create;
  EditorKind := vekText;
  TextColor := clDefault;
  ImageIndex := -1;
  Expanded := True;
end;

destructor TTyValueRow.Destroy;
var i: Integer;
begin
  for i := 0 to High(FChildren) do FChildren[i].Free;
  inherited Destroy;
end;

function TTyValueRow.GetChild(AIndex: Integer): TTyValueRow;
begin
  if (AIndex >= 0) and (AIndex <= High(FChildren)) then Result := FChildren[AIndex] else Result := nil;
end;

function TTyValueRow.AddChild(const AKey, AValue: string): TTyValueRow;
begin
  Result := TTyValueRow.Create;
  Result.Key := AKey;
  Result.Value := AValue;
  SetLength(FChildren, Length(FChildren) + 1);
  FChildren[High(FChildren)] := Result;
end;

function TTyValueRow.ChildCount: Integer;
begin
  Result := Length(FChildren);
end;

function TTyValueRow.HasChildren: Boolean;
begin
  Result := Length(FChildren) > 0;
end;

function TTyValueRow.EffectiveKey: string;
begin
  if DisplayKey <> '' then Result := DisplayKey else Result := Key;
end;

function TTyValueRow.EffectiveValue: string;
begin
  if DisplayValue <> '' then Result := DisplayValue else Result := Value;
end;

{ ---- TTyValueListEditor ---- }

constructor TTyValueListEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEditFlat := -1;
  FColorDlgRow := nil;
  FKeyColumnWidth := 110;
  FIndent := 14;
  FMoreCaption := '更多…';
  FEditor := TTyValueEdit.Create(Self);
  FEditor.Parent := Self;
  FEditor.Visible := False;
  FEditor.TabStop := False;
  FEditor.ControlStyle := FEditor.ControlStyle + [csNoDesignVisible];
  FEditor.OnKeyDown := @EditorKeyDown;
  FEditor.OnExit := @EditorExit;
  FEditor.OnEllipsis := @EditorEllipsis;
end;

destructor TTyValueListEditor.Destroy;
begin
  Application.RemoveAsyncCalls(Self);   // cancel a pending deferred "more…" colour dialog
  FreeAndNil(FDropPopup);   // free the popup (its form) before the lists it only parented
  FreeAndNil(FEnumList);
  FreeAndNil(FColorList);
  FreeRows;
  inherited Destroy;
end;

procedure TTyValueListEditor.FreeRows;
var i: Integer;
begin
  for i := 0 to High(FRoot) do FRoot[i].Free;
  SetLength(FRoot, 0);
  SetLength(FFlatRow, 0);
  SetLength(FFlatLevel, 0);
end;

procedure TTyValueListEditor.AppendFlat(ARow: TTyValueRow; ALevel: Integer);
var i, n: Integer;
begin
  n := Length(FFlatRow);
  SetLength(FFlatRow, n + 1);
  SetLength(FFlatLevel, n + 1);
  FFlatRow[n] := ARow;
  FFlatLevel[n] := ALevel;
  if ARow.Expanded then
    for i := 0 to ARow.ChildCount - 1 do
      AppendFlat(ARow.Child[i], ALevel + 1);
end;

procedure TTyValueListEditor.RebuildFlat;
var i, newIdx: Integer; sel: TTyValueRow;
begin
  if FRebuilding then Exit;
  if FEditFlat >= 0 then EndEdit(True);   // commit before the flat indices change
  FRebuilding := True;
  try
    { Remember the selected ROW OBJECT so we can re-pin the selection by identity, not by
      position: expand/collapse/add/delete renumber the flat rows, and the base only clamps
      FItemIndex on a shrink — an expand would silently leave it pointing at a different row. }
    sel := nil;
    if (ItemIndex >= 0) and (ItemIndex <= High(FFlatRow)) then
      sel := FFlatRow[ItemIndex];
    SetLength(FFlatRow, 0);
    SetLength(FFlatLevel, 0);
    for i := 0 to High(FRoot) do
      AppendFlat(FRoot[i], 0);
    { Keep the base row count in sync (drives RowAtY / scrolling); content is drawn from FFlat. }
    Items.BeginUpdate;
    try
      Items.Clear;
      for i := 0 to High(FFlatRow) do Items.Add(FFlatRow[i].EffectiveKey);
    finally
      Items.EndUpdate;
    end;
    { Re-pin selection to the same row (or clear it if that row scrolled out of the tree,
      e.g. its parent collapsed). Silent: only the position moved, the selection set didn't. }
    newIdx := -1;
    if sel <> nil then
      for i := 0 to High(FFlatRow) do
        if FFlatRow[i] = sel then begin newIdx := i; Break; end;
    SetItemIndexSilent(newIdx);
  finally
    FRebuilding := False;
  end;
  Invalidate;
end;

function TTyValueListEditor.Dp(ALogical: Integer): Integer;
begin
  Result := MulDiv(ALogical, Font.PixelsPerInch, 96);
end;

function TTyValueListEditor.ContentLeftDp: Integer;
begin
  Result := Dp(CurrentStyle.Padding.Left);
end;

function TTyValueListEditor.ContentTopDp: Integer;
begin
  Result := Dp(CurrentStyle.Padding.Top);
end;

function TTyValueListEditor.ContentRightDp: Integer;
begin
  Result := ClientWidth - Dp(CurrentStyle.Padding.Right);
  if Length(FFlatRow) > VisibleRows then Dec(Result, Dp(TyScrollbarSize));
end;

function TTyValueListEditor.SplitXDp: Integer;
var lo, hi: Integer;
begin
  Result := ContentLeftDp + Dp(FKeyColumnWidth);
  lo := ContentLeftDp + Dp(24);
  hi := ContentRightDp - Dp(40);
  if hi < lo then hi := lo;
  if Result < lo then Result := lo;
  if Result > hi then Result := hi;
end;

function TTyValueListEditor.CellRect(AFlat, ACol: Integer): TRect;
var sh, rowTop, splitX: Integer;
begin
  sh := Dp(ItemHeight);
  if sh < 1 then sh := 1;
  rowTop := ContentTopDp + (AFlat - TopIndex) * sh;
  splitX := SplitXDp;
  if ACol = 0 then
    Result := Rect(ContentLeftDp, rowTop, splitX, rowTop + sh)
  else
    Result := Rect(splitX, rowTop, ContentRightDp, rowTop + sh);
end;

function TTyValueListEditor.FlatAtY(AY: Integer): Integer;
var sh: Integer;
begin
  sh := Dp(ItemHeight);
  if sh < 1 then Exit(-1);
  Result := TopIndex + (AY - ContentTopDp) div sh;
  if (Result < 0) or (Result > High(FFlatRow)) then Result := -1;
end;

function TTyValueListEditor.TriangleHit(AFlat, AX: Integer): Boolean;
var tx: Integer;
begin
  Result := False;
  if (AFlat < 0) or (AFlat > High(FFlatRow)) then Exit;
  if not FFlatRow[AFlat].HasChildren then Exit;
  tx := ContentLeftDp + FFlatLevel[AFlat] * Dp(FIndent);
  Result := (AX >= tx) and (AX < tx + Dp(FIndent));
end;

function TTyValueListEditor.OverSplit(AX: Integer): Boolean;
begin
  Result := Abs(AX - SplitXDp) <= Dp(3);
end;

{ ---- data API (root rows) ---- }

function TTyValueListEditor.AddRow(const AKey, AValue: string): TTyValueRow;
begin
  Result := TTyValueRow.Create;
  Result.Key := AKey;
  Result.Value := AValue;
  SetLength(FRoot, Length(FRoot) + 1);
  FRoot[High(FRoot)] := Result;
  RebuildFlat;
end;

procedure TTyValueListEditor.InsertRow(const AKey, AValue: string);
begin
  AddRow(AKey, AValue);
end;

procedure TTyValueListEditor.Clear;
begin
  if FEditFlat >= 0 then EndEdit(False);
  FreeRows;
  RebuildFlat;
end;

function TTyValueListEditor.RowCount: Integer;
begin
  Result := Length(FRoot);
end;

function TTyValueListEditor.VisibleRowCount: Integer;
begin
  Result := Length(FFlatRow);
end;

procedure TTyValueListEditor.UpdateRows;
begin
  RebuildFlat;
end;

function TTyValueListEditor.Row(AIndex: Integer): TTyValueRow;
begin
  if (AIndex >= 0) and (AIndex <= High(FRoot)) then Result := FRoot[AIndex] else Result := nil;
end;

function TTyValueListEditor.GetKey(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(FRoot)) then Result := FRoot[AIndex].Key else Result := '';
end;

function TTyValueListEditor.GetValue(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(FRoot)) then Result := FRoot[AIndex].Value else Result := '';
end;

procedure TTyValueListEditor.SetValue(AIndex: Integer; const AValue: string);
begin
  if (AIndex < 0) or (AIndex > High(FRoot)) then Exit;
  if FRoot[AIndex].Value = AValue then Exit;
  FRoot[AIndex].Value := AValue;
  Invalidate;
  if Assigned(FOnValueChanged) then FOnValueChanged(Self, FRoot[AIndex]);
end;

function TTyValueListEditor.GetValueOf(const AKey: string): string;
var i: Integer;
begin
  for i := 0 to High(FRoot) do
    if FRoot[i].Key = AKey then Exit(FRoot[i].Value);
  Result := '';
end;

procedure TTyValueListEditor.SetValueOf(const AKey, AValue: string);
var i: Integer;
begin
  for i := 0 to High(FRoot) do
    if FRoot[i].Key = AKey then begin SetValue(i, AValue); Exit; end;
end;

procedure TTyValueListEditor.DeleteRow(AIndex: Integer);
var i: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FRoot)) then Exit;
  if FEditFlat >= 0 then EndEdit(False);
  FRoot[AIndex].Free;
  for i := AIndex to High(FRoot) - 1 do FRoot[i] := FRoot[i + 1];
  SetLength(FRoot, Length(FRoot) - 1);
  RebuildFlat;
end;

procedure TTyValueListEditor.SetExpanded(ARow: TTyValueRow; AExpanded: Boolean);
begin
  if ARow = nil then Exit;
  if ARow.Expanded = AExpanded then Exit;
  ARow.Expanded := AExpanded;
  RebuildFlat;
end;

procedure TTyValueListEditor.SetKeyColumnWidth(AValue: Integer);
begin
  if AValue < 16 then AValue := 16;
  if FKeyColumnWidth = AValue then Exit;
  FKeyColumnWidth := AValue;
  if FEditFlat >= 0 then FEditor.BoundsRect := CellRect(FEditFlat, 1);
  Invalidate;
end;

procedure TTyValueListEditor.SetImages(const AValue: TTyVirtualImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  Invalidate;
end;

procedure TTyValueListEditor.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then FImages := nil;
end;

{ ---- inline editor ---- }

procedure TTyValueListEditor.CommitEditor(AFlat: Integer; const AText: string);
begin
  if (AFlat < 0) or (AFlat > High(FFlatRow)) then Exit;
  CommitEditorRow(FFlatRow[AFlat], AText);
end;

{ Commit by row IDENTITY (not flat index) — used by the deferred colour dialog, which must survive
  the row being renumbered/scrolled across the async + modal boundary. }
procedure TTyValueListEditor.CommitEditorRow(ARow: TTyValueRow; const AText: string);
begin
  if (ARow = nil) or (ARow.Value = AText) then Exit;
  ARow.Value := AText;
  Invalidate;
  if Assigned(FOnValueChanged) then FOnValueChanged(Self, ARow);
end;

{ Is ARow still somewhere in the tree? Guards the deferred colour dialog against a row freed
  (DeleteRow / Clear) while the async call / modal was pending. }
function TTyValueListEditor.RowExists(ARow: TTyValueRow): Boolean;

  function InNode(ANode: TTyValueRow): Boolean;
  var i: Integer;
  begin
    if ANode = ARow then Exit(True);
    Result := False;
    for i := 0 to ANode.ChildCount - 1 do
      if InNode(ANode.Child[i]) then Exit(True);
  end;

var i: Integer;
begin
  Result := False;
  if ARow = nil then Exit;
  for i := 0 to High(FRoot) do
    if InNode(FRoot[i]) then Exit(True);
end;

procedure TTyValueListEditor.BeginEdit(AFlat: Integer);
var r: TTyValueRow;
begin
  if FReadOnly then Exit;
  if (AFlat < 0) or (AFlat > High(FFlatRow)) then Exit;
  r := FFlatRow[AFlat];
  if r.ReadOnly or (r.EditorKind = vekReadOnly) then Exit;
  if FEditFlat = AFlat then Exit;
  if FEditFlat >= 0 then EndEdit(True);
  case r.EditorKind of
    vekBoolean: BeginDropdown(AFlat, 'False'#10'True');
    vekEnum:    BeginDropdown(AFlat, r.EnumValues);
    vekColor:   BeginColorDropdown(AFlat);
    vekInteger: BeginInlineEdit(AFlat, vnmInteger, False);
    vekFloat:   BeginInlineEdit(AFlat, vnmFloat, False);
    vekFont:    BeginInlineEdit(AFlat, vnmNone, True);   // editable text + "…" -> font dialog
    vekDialog:  BeginInlineEdit(AFlat, vnmNone, True);   // editable text + "…" -> OnEditRow
  else
    BeginInlineEdit(AFlat, vnmNone, False);              // vekText
  end;
end;

{ Show the inline text editor over the value cell. The text is freely editable / selectable /
  copyable; ANumeric restricts typing to a number; AEllipsis adds a trailing "…" button whose
  click (only) opens the row's dialog (font / custom) — see EditorEllipsis. }
procedure TTyValueListEditor.BeginInlineEdit(AFlat: Integer; ANumeric: TTyValueNumericMode;
  AEllipsis: Boolean);
begin
  FEditFlat := AFlat;
  FEditor.NumericMode := ANumeric;
  FEditor.ShowEllipsis := AEllipsis;
  FEditor.ReadOnly := False;
  FEditor.Controller := Controller;
  FEditor.Text := FFlatRow[AFlat].Value;
  FEditor.BoundsRect := CellRect(AFlat, 1);
  FEditor.Visible := True;
  if CanFocus and FEditor.CanFocus then FEditor.SetFocus;
  Invalidate;
end;

{ Create the shared dropdown popup + its two content lists (text for enum/bool, swatches for
  colour) lazily. Both lists route selection through DropPick/DropClick → HandleDropCommit. }
procedure TTyValueListEditor.EnsureDropPopup;
begin
  if FDropPopup <> nil then Exit;
  FDropPopup := TTyDropdownPopup.Create;
  FDropPopup.OnClose := @DropClosed;
  FEnumList := TTyListBox.Create(nil);
  FEnumList.OnChange := @DropPick;      // a real selection change picks + closes
  FEnumList.OnMouseUp := @DropClick;    // ...and so does clicking the ALREADY-selected row
  FColorList := TTyColorMorePopupList.Create(nil);   // draws swatches; the clNone "more…" as text
  FColorList.OnChange := @DropPick;
  FColorList.OnMouseUp := @DropClick;
end;

{ Match the popup WINDOW's rounded region to the list's themed fill radius, else the square
  window corners show through as black outside the rounded fill. Mirrors TTyComboBox.DropDown. }
procedure TTyValueListEditor.ConfigureDropCorners;
begin
  FDropPopup.Controller := Controller;
  FDropPopup.CornerRadiusLogical := ActiveController.Model.ResolveStyle('TyListBox', '', []).BorderRadius;
end;

procedure TTyValueListEditor.BeginDropdown(AFlat: Integer; const AOptions: string);
var cell: TRect; rows: Integer;
begin
  FEditFlat := AFlat;
  FDropMode := True;
  FDropKind := dkEnum;
  cell := CellRect(AFlat, 1);
  { The edit overlay is the field + the popup anchor — read-only, so the value is PICKED. }
  FEditor.NumericMode := vnmNone;
  FEditor.ShowEllipsis := False;
  FEditor.ReadOnly := True;
  FEditor.Controller := Controller;
  FEditor.Text := FFlatRow[AFlat].Value;
  FEditor.BoundsRect := cell;
  FEditor.Visible := True;
  EnsureDropPopup;
  FDropPopup.SetContent(FEnumList);
  FEnumList.Controller := Controller;
  FDropSeeding := True;   // seeding the selection must not fire a pick
  FEnumList.Items.Text := StringReplace(AOptions, LineEnding, #10, [rfReplaceAll]);
  FEnumList.ItemIndex := FEnumList.Items.IndexOf(FFlatRow[AFlat].Value);
  FDropSeeding := False;
  ConfigureDropCorners;
  rows := FEnumList.Items.Count;
  if rows > 8 then rows := 8;
  if rows < 1 then rows := 1;
  FDropPopup.Popup(FEditor, cell.Right - cell.Left, rows * Dp(ItemHeight) + Dp(2));
end;

{ vekColor: a palette dropdown (swatch per colour) whose LAST row is a "more…" entry (clNone
  sentinel) that opens the themed colour dialog. }
procedure TTyValueListEditor.BeginColorDropdown(AFlat: Integer);
var cell: TRect; rows, idx: Integer;
begin
  FEditFlat := AFlat;
  FDropMode := True;
  FDropKind := dkColor;
  cell := CellRect(AFlat, 1);
  FEditor.NumericMode := vnmNone;
  FEditor.ShowEllipsis := False;
  FEditor.ReadOnly := True;
  FEditor.Controller := Controller;
  FEditor.Text := FFlatRow[AFlat].Value;
  FEditor.BoundsRect := cell;
  FEditor.Visible := True;
  EnsureDropPopup;
  FDropPopup.SetContent(FColorList);
  FColorList.Controller := Controller;
  FDropSeeding := True;
  FColorList.Items.Clear;
  TyAddDefaultColorPalette(FColorList.Items);
  idx := TySelectColorIndex(FColorList.Items, StringToColorDef(FFlatRow[AFlat].Value, clBlack));
  TyAddColorItem(FColorList.Items, FMoreCaption, clNone);   // "more…" sentinel, kept LAST
  FColorList.ItemIndex := idx;
  FDropSeeding := False;
  ConfigureDropCorners;
  rows := FColorList.Items.Count;
  if rows > 10 then rows := 10;
  if rows < 1 then rows := 1;
  FDropPopup.Popup(FEditor, cell.Right - cell.Left, rows * Dp(ItemHeight) + Dp(2));
end;

{ Shared commit for both dropdown lists (fired by OnChange and by OnMouseUp — the latter so a
  click on the ALREADY-selected row still commits, since SelectItem fires no OnChange). }
procedure TTyValueListEditor.HandleDropCommit;
var flat, idx: Integer;
begin
  if FDropSeeding then Exit;
  flat := FEditFlat;
  if flat < 0 then begin if FDropPopup <> nil then FDropPopup.Close; Exit; end;
  case FDropKind of
    dkEnum:
      begin
        if FEnumList.ItemIndex >= 0 then CommitEditor(flat, FEnumList.Items[FEnumList.ItemIndex]);
        if FDropPopup <> nil then FDropPopup.Close;
      end;
    dkColor:
      begin
        idx := FColorList.ItemIndex;
        if idx < 0 then begin if FDropPopup <> nil then FDropPopup.Close; Exit; end;
        if TyColorOfItem(FColorList.Items, idx) = clNone then
        begin
          { "more…": close the popup, then open the modal dialog on a DEFERRED call so this
            mouse-down event (and the popup's mouse capture) fully unwinds first. Remember the row
            by IDENTITY — the flat index can shift across the async + modal boundary. }
          FColorDlgRow := FFlatRow[flat];
          if FDropPopup <> nil then FDropPopup.Close;
          Application.QueueAsyncCall(@DeferredColorDialog, 0);
        end
        else
        begin
          CommitEditor(flat, ColorToString(TyColorOfItem(FColorList.Items, idx)));
          if FDropPopup <> nil then FDropPopup.Close;
        end;
      end;
  else
    if FDropPopup <> nil then FDropPopup.Close;
  end;
end;

procedure TTyValueListEditor.DeferredColorDialog(Data: PtrInt);
var col: TColor; a: Byte; r: TTyValueRow;
begin
  r := FColorDlgRow;
  FColorDlgRow := nil;
  if (r = nil) or not RowExists(r) then Exit;   // row removed while the async call was pending
  col := StringToColorDef(r.Value, clBlack);
  a := 255;
  if TySelectColor('选择颜色', col, a) and RowExists(r) then   // re-check: the modal pumped messages
    CommitEditorRow(r, ColorToString(col));
end;

procedure TTyValueListEditor.DropPick(Sender: TObject);
begin
  HandleDropCommit;
end;

{ Clicking a row that is ALREADY selected fires no OnChange (SelectItem exits early), so the pick
  would be a dead interaction — commit from MouseUp too (a safe no-op on a changing click). }
procedure TTyValueListEditor.DropClick(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then HandleDropCommit;
end;

procedure TTyValueListEditor.DropClosed(Sender: TObject);
begin
  FDropMode := False;
  FDropKind := dkNone;
  if FEditor <> nil then begin FEditor.ReadOnly := False; FEditor.Visible := False; end;
  FEditFlat := -1;
  Invalidate;
  if CanFocus then SetFocus;
end;

{ The inline "…" button was clicked (or InvokeRowDialog called): run the row's dialog editor. }
procedure TTyValueListEditor.EditorEllipsis(Sender: TObject);
begin
  InvokeRowDialog(FEditFlat);
end;

procedure TTyValueListEditor.InvokeRowDialog(AFlat: Integer);
var r: TTyValueRow;
begin
  if (AFlat < 0) or (AFlat > High(FFlatRow)) then Exit;
  r := FFlatRow[AFlat];
  if FReadOnly or r.ReadOnly then Exit;
  case r.EditorKind of
    vekFont:   EditFontRow(AFlat);
    vekDialog: if Assigned(FOnEditRow) then begin FOnEditRow(Self, r); Invalidate; end;
  end;
  { reflect the picked value in the still-open inline field }
  if (FEditFlat = AFlat) and (FEditor <> nil) and FEditor.Visible then
    FEditor.Text := r.Value;
end;

{ Seed a TFont from a Font row: from its child rows (Name/Size/Bold/Italic/Color) if it has
  them, else from its 'Name, Size' descriptor. }
procedure ApplyStyleFlag(AFont: TFont; AFlag: TFontStyle; const AValue: string);
begin
  if SameText(Trim(AValue), 'True') then AFont.Style := AFont.Style + [AFlag]
  else AFont.Style := AFont.Style - [AFlag];
end;

procedure TTyValueListEditor.SeedFontFromRow(ARow: TTyValueRow; AFont: TFont);
var i, j, sz: Integer; c, g: TTyValueRow; k, gk, nm: string;
begin
  if ARow.HasChildren then
  begin
    for i := 0 to ARow.ChildCount - 1 do
    begin
      c := ARow.Child[i];
      k := LowerCase(c.Key);
      if k = 'name' then begin if Trim(c.Value) <> '' then AFont.Name := c.Value; end
      else if k = 'size' then begin if StrToIntDef(c.Value, 0) > 0 then AFont.Size := StrToIntDef(c.Value, AFont.Size); end
      else if k = 'bold' then ApplyStyleFlag(AFont, fsBold, c.Value)
      else if k = 'italic' then ApplyStyleFlag(AFont, fsItalic, c.Value)
      else if k = 'color' then AFont.Color := StringToColorDef(c.Value, AFont.Color)
      else if (k = 'style') and c.HasChildren then     // OI-style Font -> Style -> Bold/Italic
        for j := 0 to c.ChildCount - 1 do
        begin
          g := c.Child[j]; gk := LowerCase(g.Key);
          if gk = 'bold' then ApplyStyleFlag(AFont, fsBold, g.Value)
          else if gk = 'italic' then ApplyStyleFlag(AFont, fsItalic, g.Value);
        end;
    end;
  end
  else if TyParseFontDescriptor(ARow.Value, nm, sz) then
  begin
    if nm <> '' then AFont.Name := nm;
    if sz > 0 then AFont.Size := sz;
  end
  else if Trim(ARow.Value) <> '' then
    AFont.Name := Trim(ARow.Value);
end;

{ After the font dialog: write the picked font back into the matching child rows so the sub-
  properties reflect the choice (each changed child fires OnValueChanged). }
function BoolStr(AOn: Boolean): string;
begin
  if AOn then Result := 'True' else Result := 'False';
end;

procedure TTyValueListEditor.SyncFontChildren(ARow: TTyValueRow; AFont: TFont);
var didChange: Boolean;

  procedure SetChild(ARowc: TTyValueRow; const ANewValue: string);
  begin
    if ANewValue <> ARowc.Value then
    begin
      ARowc.Value := ANewValue;
      didChange := True;
      if Assigned(FOnValueChanged) then FOnValueChanged(Self, ARowc);
    end;
  end;

var i, j: Integer; c, g: TTyValueRow; k, gk: string;
begin
  didChange := False;
  for i := 0 to ARow.ChildCount - 1 do
  begin
    c := ARow.Child[i];
    k := LowerCase(c.Key);
    if k = 'name' then SetChild(c, AFont.Name)
    else if k = 'size' then SetChild(c, IntToStr(AFont.Size))
    else if k = 'bold' then SetChild(c, BoolStr(fsBold in AFont.Style))
    else if k = 'italic' then SetChild(c, BoolStr(fsItalic in AFont.Style))
    else if k = 'color' then SetChild(c, ColorToString(AFont.Color))
    else if (k = 'style') and c.HasChildren then     // OI-style Font -> Style -> Bold/Italic
      for j := 0 to c.ChildCount - 1 do
      begin
        g := c.Child[j]; gk := LowerCase(g.Key);
        if gk = 'bold' then SetChild(g, BoolStr(fsBold in AFont.Style))
        else if gk = 'italic' then SetChild(g, BoolStr(fsItalic in AFont.Style));
      end;
  end;
  if didChange then RebuildFlat;
end;

procedure TTyValueListEditor.EditFontRow(AFlat: Integer);
var dlg: TTyFontDialog; r: TTyValueRow;
begin
  r := FFlatRow[AFlat];
  dlg := TTyFontDialog.Create(nil);
  try
    SeedFontFromRow(r, dlg.Font);
    if dlg.Execute then
    begin
      CommitEditor(AFlat, Format('%s, %d', [dlg.Font.Name, dlg.Font.Size]));
      if r.HasChildren then SyncFontChildren(r, dlg.Font);
    end;
  finally
    dlg.Free;
  end;
  if CanFocus then SetFocus;
end;

procedure TTyValueListEditor.EndEdit(ACommit: Boolean; ARestoreFocus: Boolean);
var flat: Integer;
begin
  if FEditor = nil then Exit;
  if FDropMode then
  begin
    { Normally Close -> DropClosed does the cleanup. But if the popup was never actually shown
      (e.g. seeding raised before Popup), Close is a no-op and DropClosed never fires — so run the
      cleanup ourselves rather than leaving the control stuck in FDropMode with a visible anchor. }
    if (FDropPopup <> nil) and FDropPopup.IsOpen then
      FDropPopup.Close
    else
      DropClosed(nil);
    Exit;
  end;
  if FEditFlat < 0 then Exit;
  if FEndingEdit then Exit;
  FEndingEdit := True;
  try
    flat := FEditFlat;
    FEditFlat := -1;
    FEditor.Visible := False;
    if ACommit then CommitEditor(flat, FEditor.Text) else Invalidate;
    if ARestoreFocus and CanFocus then SetFocus;
  finally
    FEndingEdit := False;
  end;
end;

procedure TTyValueListEditor.RepositionEditor;
begin
  if FEditor = nil then Exit;
  if FEditFlat < 0 then Exit;
  if FEditFlat > High(FFlatRow) then
    EndEdit(False)
  else
    FEditor.BoundsRect := CellRect(FEditFlat, 1);
end;

procedure TTyValueListEditor.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN: begin EndEdit(True,  True); Key := 0; end;
    VK_ESCAPE: begin EndEdit(False, True); Key := 0; end;
  end;
end;

procedure TTyValueListEditor.EditorExit(Sender: TObject);
begin
  if csDestroying in ComponentState then Exit;
  if FDropMode then Exit;   // the popup took focus; the dropdown drives commit/close, not this
  if (FEditFlat >= 0) and not FEndingEdit then EndEdit(True);
end;

procedure TTyValueListEditor.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
  if FEditor <> nil then FEditor.Controller := AValue;
end;

procedure TTyValueListEditor.SetTopIndex(const AValue: Integer);
begin
  if (FEditFlat >= 0) and (AValue <> TopIndex) then EndEdit(True);
  inherited SetTopIndex(AValue);
end;

procedure TTyValueListEditor.Resize;
begin
  inherited Resize;
  RepositionEditor;
end;

procedure TTyValueListEditor.Paint;
begin
  inherited Paint;
  RepositionEditor;
end;

{ ---- painting ---- }

procedure TTyValueListEditor.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  r: TTyValueRow;
  level, splitX, lo, hi, pad, indentX, sz, weight, imgSz, sw: Integer;
  keyR, valR, tri, swR: TRect;
  divider, keyCol, valCol: TTyColor;
  ctx: TBGRACanvas2D;
  bmp: TBGRABitmap;
  cy: Single;
begin
  if (AIndex < 0) or (AIndex > High(FFlatRow)) then Exit;
  r := FFlatRow[AIndex];
  level := FFlatLevel[AIndex];
  pad := P.Scale(5);

  splitX := ARowRect.Left + P.Scale(FKeyColumnWidth);
  lo := ARowRect.Left + P.Scale(24);
  hi := ARowRect.Right - P.Scale(40);
  if hi < lo then hi := lo;
  if splitX < lo then splitX := lo;
  if splitX > hi then splitX := hi;

  indentX := ARowRect.Left + level * P.Scale(FIndent);

  // Expand / collapse triangle for rows with children.
  if r.HasChildren then
  begin
    ctx := P.Bitmap.Canvas2D;
    sz := P.Scale(9);
    tri := Rect(indentX + P.Scale(2), ARowRect.Top + ((ARowRect.Bottom - ARowRect.Top) - sz) div 2,
      indentX + P.Scale(2) + sz, 0);
    tri.Bottom := tri.Top + sz;
    cy := (tri.Top + tri.Bottom) / 2;
    ctx.fillStyle(TyColorToBGRA(AStyle.TextColor));
    ctx.beginPath;
    if r.Expanded then
    begin
      ctx.moveTo(tri.Left, tri.Top + sz * 0.15);
      ctx.lineTo(tri.Right, tri.Top + sz * 0.15);
      ctx.lineTo((tri.Left + tri.Right) / 2, tri.Top + sz * 0.7);
    end
    else
    begin
      ctx.moveTo(tri.Left, tri.Top);
      ctx.lineTo(tri.Left, tri.Bottom);
      ctx.lineTo(tri.Left + sz * 0.7, cy);
    end;
    ctx.closePath;
    ctx.fill;
  end;

  // Key label (after the triangle + indent).
  keyCol := AStyle.TextColor;
  keyR := Rect(indentX + P.Scale(FIndent), ARowRect.Top, splitX - P.Scale(4), ARowRect.Bottom);
  P.DrawText(keyR, r.EffectiveKey, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
    keyCol, taLeftJustify, tlCenter, True);

  // Column divider.
  divider := (AStyle.TextColor and $00FFFFFF) or $28000000;
  P.Bitmap.Canvas2D.fillStyle(TyColorToBGRA(divider));
  P.Bitmap.Canvas2D.fillRect(splitX, ARowRect.Top + P.Scale(2), 1,
    (ARowRect.Bottom - ARowRect.Top) - P.Scale(4));

  // Value cell (skipped while its inline editor is open).
  if AIndex <> FEditFlat then
  begin
    valR := Rect(splitX + pad, ARowRect.Top, ARowRect.Right - P.Scale(4), ARowRect.Bottom);
    // '…' affordance for the ellipsis-dialog editors (font / custom), at the right edge. (vekColor
    // uses a dropdown, so it shows a swatch instead of a '…'.)
    if r.EditorKind in [vekFont, vekDialog] then
    begin
      P.DrawText(Rect(valR.Right - P.Scale(16), valR.Top, valR.Right, valR.Bottom), '…',
        AStyle.FontName, ResolveFontSize(AStyle) + 2, 700, AStyle.TextColor, taCenter, tlCenter, False);
      valR.Right := valR.Right - P.Scale(18);
    end;
    // colour swatch for a colour row.
    if r.EditorKind = vekColor then
    begin
      sw := (ARowRect.Bottom - ARowRect.Top) - P.Scale(8);
      if sw < 6 then sw := 6;
      swR := Rect(valR.Left, ARowRect.Top + ((ARowRect.Bottom - ARowRect.Top) - sw) div 2,
        valR.Left + sw, ARowRect.Top + ((ARowRect.Bottom - ARowRect.Top) - sw) div 2 + sw);
      P.Bitmap.Canvas2D.fillStyle(TyColorToBGRA(TyColorFromLCL(StringToColorDef(r.Value, clBlack), 255)));
      P.Bitmap.Canvas2D.fillRect(swR.Left, swR.Top, sw, sw);
      P.StrokeBorder(swR, 0, 1, AStyle.TextColor);
      valR.Left := valR.Left + sw + P.Scale(5);
    end;
    // optional image
    if (FImages <> nil) and (r.ImageIndex >= 0) and (r.ImageIndex < FImages.Count) then
    begin
      imgSz := (ARowRect.Bottom - ARowRect.Top) - P.Scale(6);
      if imgSz < 8 then imgSz := 8;
      bmp := FImages.RenderIndex(r.ImageIndex, imgSz);
      if bmp <> nil then
        try
          P.Bitmap.PutImage(valR.Left,
            ARowRect.Top + ((ARowRect.Bottom - ARowRect.Top - bmp.Height) div 2), bmp,
            dmDrawWithTransparency);
        finally bmp.Free; end;
      valR.Left := valR.Left + imgSz + P.Scale(4);
    end;
    if r.TextColor <> clDefault then valCol := TyColorFromLCL(r.TextColor, 255)
    else valCol := AStyle.TextColor;
    if r.Bold then weight := 700 else weight := AStyle.FontWeight;
    P.DrawText(valR, r.EffectiveValue, AStyle.FontName, ResolveFontSize(AStyle), weight,
      valCol, taLeftJustify, tlCenter, True);
  end;
end;

{ ---- mouse / keyboard ---- }

procedure TTyValueListEditor.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var flat: Integer;
begin
  if (Button = mbLeft) and OverSplit(X) then
  begin
    FDraggingSplit := True;
    Exit;   // start dragging the divider (don't select / edit)
  end;
  flat := FlatAtY(Y);
  if (Button = mbLeft) and TriangleHit(flat, X) then
  begin
    SetExpanded(FFlatRow[flat], not FFlatRow[flat].Expanded);
    Exit;
  end;
  inherited MouseDown(Button, Shift, X, Y);   // focus + row selection
  if (Button = mbLeft) and not FReadOnly and (flat >= 0) then
  begin
    if X >= SplitXDp then BeginEdit(flat)
    else if FEditFlat >= 0 then EndEdit(True);
  end;
end;

procedure TTyValueListEditor.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if FDraggingSplit then
  begin
    SetKeyColumnWidth(Round((X - ContentLeftDp) * 96 / Font.PixelsPerInch));
    Exit;
  end;
  if OverSplit(X) then Cursor := crHSplit else Cursor := crDefault;
  inherited MouseMove(Shift, X, Y);
end;

procedure TTyValueListEditor.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FDraggingSplit and (Button = mbLeft) then FDraggingSplit := False;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TTyValueListEditor.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if ((Key = VK_F2) or (Key = VK_RETURN)) and (Shift = []) and (ItemIndex >= 0)
    and not FReadOnly and (FEditFlat < 0) then
  begin
    BeginEdit(ItemIndex);
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

end.
