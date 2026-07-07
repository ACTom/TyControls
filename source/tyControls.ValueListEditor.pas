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
    FEditor: TTyEdit;
    FEditFlat: Integer;               // flat index being edited, or -1
    FEndingEdit: Boolean;
    FRebuilding: Boolean;
    FDropMode: Boolean;               // a boolean/enum dropdown is open (suppresses OnExit commit)
    FDropSeeding: Boolean;            // guard while seeding the dropdown's selection
    FEnumPopup: TTyDropdownPopup;     // lazy dropdown for vekBoolean / vekEnum
    FEnumList: TTyListBox;
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
    procedure BeginTextEdit(AFlat: Integer);
    procedure BeginDropdown(AFlat: Integer; const AOptions: string);
    procedure DropPick(Sender: TObject);
    procedure DropClick(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure DropClosed(Sender: TObject);
    procedure EditColorRow(AFlat: Integer);
    procedure EditFontRow(AFlat: Integer);
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
    // Number of VISIBLE (expanded) rows — root rows plus expanded descendants.
    function VisibleRowCount: Integer;
    // The visible (flat) index being edited, or -1.
    property EditingRow: Integer read FEditFlat;
    property Keys[AIndex: Integer]: string read GetKey;                 // root rows
    property Values[AIndex: Integer]: string read GetValue write SetValue;
    property ValueOf[const AKey: string]: string read GetValueOf write SetValueOf;
    property InlineEditor: TTyEdit read FEditor;
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
  BGRABitmap, BGRABitmapTypes, BGRACanvas2D, tyControls.ColorMath,
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
  FKeyColumnWidth := 110;
  FIndent := 14;
  FEditor := TTyEdit.Create(Self);
  FEditor.Parent := Self;
  FEditor.Visible := False;
  FEditor.TabStop := False;
  FEditor.ControlStyle := FEditor.ControlStyle + [csNoDesignVisible];
  FEditor.OnKeyDown := @EditorKeyDown;
  FEditor.OnExit := @EditorExit;
end;

destructor TTyValueListEditor.Destroy;
begin
  FreeAndNil(FEnumPopup);   // free the popup (its form) before the list it only parented
  FreeAndNil(FEnumList);
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
var r: TTyValueRow;
begin
  if (AFlat < 0) or (AFlat > High(FFlatRow)) then Exit;
  r := FFlatRow[AFlat];
  if r.Value = AText then Exit;
  r.Value := AText;
  Invalidate;
  if Assigned(FOnValueChanged) then FOnValueChanged(Self, r);
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
    vekColor:   EditColorRow(AFlat);
    vekFont:    EditFontRow(AFlat);
    vekDialog:  if Assigned(FOnEditRow) then begin FOnEditRow(Self, r); Invalidate; end;
  else
    BeginTextEdit(AFlat);   // vekText / vekInteger / vekFloat
  end;
end;

procedure TTyValueListEditor.BeginTextEdit(AFlat: Integer);
begin
  FEditFlat := AFlat;
  FEditor.ReadOnly := False;
  FEditor.Controller := Controller;
  FEditor.Text := FFlatRow[AFlat].Value;
  FEditor.BoundsRect := CellRect(AFlat, 1);
  FEditor.Visible := True;
  if CanFocus and FEditor.CanFocus then FEditor.SetFocus;
  Invalidate;
end;

procedure TTyValueListEditor.BeginDropdown(AFlat: Integer; const AOptions: string);
var cell: TRect; rows: Integer;
begin
  FEditFlat := AFlat;
  FDropMode := True;
  cell := CellRect(AFlat, 1);
  { The edit overlay is the field + the popup anchor — read-only, so the value is PICKED. }
  FEditor.ReadOnly := True;
  FEditor.Controller := Controller;
  FEditor.Text := FFlatRow[AFlat].Value;
  FEditor.BoundsRect := cell;
  FEditor.Visible := True;
  if FEnumPopup = nil then
  begin
    FEnumPopup := TTyDropdownPopup.Create;
    FEnumPopup.OnClose := @DropClosed;
    FEnumList := TTyListBox.Create(nil);
    FEnumList.OnChange := @DropPick;      // a real selection change picks + closes
    FEnumList.OnMouseUp := @DropClick;    // ...and so does clicking the ALREADY-selected row
    FEnumPopup.SetContent(FEnumList);
  end;
  FEnumList.Controller := Controller;
  FDropSeeding := True;   // seeding the selection must not fire a pick
  FEnumList.Items.Text := StringReplace(AOptions, LineEnding, #10, [rfReplaceAll]);
  FEnumList.ItemIndex := FEnumList.Items.IndexOf(FFlatRow[AFlat].Value);
  FDropSeeding := False;
  rows := FEnumList.Items.Count;
  if rows > 8 then rows := 8;
  if rows < 1 then rows := 1;
  FEnumPopup.Popup(FEditor, cell.Right - cell.Left, rows * Dp(ItemHeight) + Dp(2));
end;

procedure TTyValueListEditor.DropPick(Sender: TObject);
begin
  if FDropSeeding then Exit;
  if (FEnumList.ItemIndex >= 0) and (FEditFlat >= 0) then
    CommitEditor(FEditFlat, FEnumList.Items[FEnumList.ItemIndex]);
  if FEnumPopup <> nil then FEnumPopup.Close;
end;

{ Clicking a row that is ALREADY selected fires no OnChange (SelectItem exits early), so the
  pick would be a dead interaction. MouseUp fires on every click, so commit+close from here
  too; on a changing click OnChange already ran and FEditFlat is -1, making this a safe no-op. }
procedure TTyValueListEditor.DropClick(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if FDropSeeding or (Button <> mbLeft) then Exit;
  if (FEnumList.ItemIndex >= 0) and (FEditFlat >= 0) then
    CommitEditor(FEditFlat, FEnumList.Items[FEnumList.ItemIndex]);
  if FEnumPopup <> nil then FEnumPopup.Close;
end;

procedure TTyValueListEditor.DropClosed(Sender: TObject);
begin
  FDropMode := False;
  if FEditor <> nil then begin FEditor.ReadOnly := False; FEditor.Visible := False; end;
  FEditFlat := -1;
  Invalidate;
  if CanFocus then SetFocus;
end;

procedure TTyValueListEditor.EditColorRow(AFlat: Integer);
var col: TColor; a: Byte;
begin
  col := StringToColorDef(FFlatRow[AFlat].Value, clBlack);
  a := 255;
  if TySelectColor('选择颜色', col, a) then
    CommitEditor(AFlat, ColorToString(col));
  if CanFocus then SetFocus;
end;

procedure TTyValueListEditor.EditFontRow(AFlat: Integer);
var dlg: TTyFontDialog; nm: string; sz: Integer; hasSize: Boolean;
begin
  dlg := TTyFontDialog.Create(nil);
  try
    hasSize := TyParseFontDescriptor(FFlatRow[AFlat].Value, nm, sz);
    if nm <> '' then dlg.Font.Name := nm;
    if hasSize and (sz > 0) then dlg.Font.Size := sz;   // else keep the dialog's own default size
    if dlg.Execute then
      CommitEditor(AFlat, Format('%s, %d', [dlg.Font.Name, dlg.Font.Size]));
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
    if FEnumPopup <> nil then FEnumPopup.Close;   // the dropdown's cleanup runs in DropClosed
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
    // '…' affordance for the dialog-based editors (colour / font / custom), at the right edge.
    if r.EditorKind in [vekColor, vekFont, vekDialog] then
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
