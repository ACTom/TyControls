unit tyControls.ValueListEditor;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.Controller, tyControls.ListBox, tyControls.Edit;

type
  { Fired after a value cell commits with a changed value. }
  TTyValueEditEvent = procedure(Sender: TObject; ARow: Integer; const AKey, AValue: string) of object;

  { A two-column NAME / VALUE editor (a lightweight "property grid"): each row is a
    'key=value' pair (stored in the inherited Items TStringList, so Items.Names[i] /
    Items.ValueFromIndex[i] give the two columns). The KEY column is a read-only label;
    the VALUE column is edited IN PLACE via a themed TTyEdit overlay (click a value, or
    press F2/Enter on the selected row; Enter/blur commits, Esc cancels). The key/value
    split is KeyColumnWidth (logical px). Row layout, selection and scrolling come from
    TTyListBox; a thin theme-coloured divider separates the columns. Build with InsertRow
    (or Items.Add('key=value')); read/write via Keys[] / Values[] / ValueOf[]. }
  TTyValueListEditor = class(TTyListBox)
  private
    FEditor: TTyEdit;
    FEditRow: Integer;         // row being edited, or -1
    FEndingEdit: Boolean;      // re-entry guard for the editor's OnExit
    FKeyColumnWidth: Integer;  // logical px of the key column
    FReadOnly: Boolean;
    FOnValueChanged: TTyValueEditEvent;
    function Dp(ALogical: Integer): Integer;
    function ContentLeftDp: Integer;
    function ContentRightDp: Integer;
    function ContentTopDp: Integer;
    function SplitXDp: Integer;
    function CellRect(ARow, ACol: Integer): TRect;   // client px; col 0 = key, 1 = value
    function GetKey(AIndex: Integer): string;
    function GetValue(AIndex: Integer): string;
    procedure SetValue(AIndex: Integer; const AValue: string);
    function GetValueOf(const AKey: string): string;
    procedure SetValueOf(const AKey, AValue: string);
    procedure SetKeyColumnWidth(AValue: Integer);
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorExit(Sender: TObject);
    procedure EndEdit(ACommit: Boolean; ARestoreFocus: Boolean = False);
    procedure RepositionEditor;
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure SetController(AValue: TTyStyleController); override;   // theme the inline editor too
    procedure SetTopIndex(const AValue: Integer); override;          // commit before scrolling
    procedure Resize; override;                                       // re-bound the open editor
    procedure Paint; override;                                        // keep the editor on its cell
  public
    constructor Create(AOwner: TComponent); override;
    // Number of key/value rows.
    function RowCount: Integer;
    // Append a 'key=value' row.
    procedure InsertRow(const AKey, AValue: string);
    // Remove row AIndex (commits/cancels any in-progress edit first).
    procedure DeleteRow(AIndex: Integer);
    // Start editing row ARow's value in place (no-op when ReadOnly or out of range).
    procedure BeginEdit(ARow: Integer);
    // The key (name) of row AIndex ('' when out of range).
    property Keys[AIndex: Integer]: string read GetKey;
    // The value of row AIndex; writing commits programmatically ('' when out of range).
    property Values[AIndex: Integer]: string read GetValue write SetValue;
    // The value for a key by name ('' when the key is absent; writing updates it if present).
    property ValueOf[const AKey: string]: string read GetValueOf write SetValueOf;
    // The row currently being edited, or -1.
    property EditingRow: Integer read FEditRow;
    // Expose the inline editor for tests / descendants.
    property InlineEditor: TTyEdit read FEditor;
  published
    // Logical px width of the key column (the key/value divider position).
    property KeyColumnWidth: Integer read FKeyColumnWidth write SetKeyColumnWidth default 100;
    // When True, value cells cannot be edited (display only).
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    // Fires after a value commits with a change.
    property OnValueChanged: TTyValueEditEvent read FOnValueChanged write FOnValueChanged;
  end;

implementation

constructor TTyValueListEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEditRow := -1;
  FKeyColumnWidth := 100;
  Items.NameValueSeparator := '=';   // Items[i] = 'key=value'
  { Persistent hidden inline editor (shown at runtime over a value cell). csNoDesignVisible
    keeps this internal child out of the form designer (same as the TreeView's editor). }
  FEditor := TTyEdit.Create(Self);
  FEditor.Parent := Self;
  FEditor.Visible := False;
  FEditor.TabStop := False;
  FEditor.ControlStyle := FEditor.ControlStyle + [csNoDesignVisible];
  FEditor.OnKeyDown := @EditorKeyDown;
  FEditor.OnExit := @EditorExit;
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
  { Reserve the embedded scrollbar's width when it is showing (mirrors TTyListBox.RenderTo). }
  if Items.Count > VisibleRows then
    Dec(Result, Dp(TyScrollbarSize));
end;

function TTyValueListEditor.SplitXDp: Integer;
var lo, hi: Integer;
begin
  Result := ContentLeftDp + Dp(FKeyColumnWidth);
  { Keep a minimum width for BOTH columns. }
  lo := ContentLeftDp + Dp(24);
  hi := ContentRightDp - Dp(24);
  if hi < lo then hi := lo;
  if Result < lo then Result := lo;
  if Result > hi then Result := hi;
end;

function TTyValueListEditor.CellRect(ARow, ACol: Integer): TRect;
var sh, rowTop, splitX: Integer;
begin
  sh := Dp(ItemHeight);
  if sh < 1 then sh := 1;
  rowTop := ContentTopDp + (ARow - TopIndex) * sh;
  splitX := SplitXDp;
  if ACol = 0 then
    Result := Rect(ContentLeftDp, rowTop, splitX, rowTop + sh)
  else
    Result := Rect(splitX, rowTop, ContentRightDp, rowTop + sh);
end;

function TTyValueListEditor.RowCount: Integer;
begin
  Result := Items.Count;
end;

function TTyValueListEditor.GetKey(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then
    Result := Items.Names[AIndex]
  else
    Result := '';
end;

function TTyValueListEditor.GetValue(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then
    Result := Items.ValueFromIndex[AIndex]
  else
    Result := '';
end;

procedure TTyValueListEditor.SetValue(AIndex: Integer; const AValue: string);
var
  key, line: string;
  p: Integer;
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  if GetValue(AIndex) = AValue then Exit;
  { Preserve the EXACT key (everything up to the first '=') — Items.Names truncates and would
    drop it for a line with no '='. Rebuild the whole 'key=value' line so an empty value stores
    as 'key='. Force the list unsorted first: TStringList.Put raises SSortedListError on a sorted
    list, and a value editor is inherently order-preserving (never alphabetical). }
  line := Items[AIndex];
  p := Pos('=', line);
  if p = 0 then key := line else key := Copy(line, 1, p - 1);
  Items.Sorted := False;
  Items[AIndex] := key + '=' + AValue;
  Invalidate;
  if Assigned(FOnValueChanged) then
    FOnValueChanged(Self, AIndex, key, AValue);
end;

function TTyValueListEditor.GetValueOf(const AKey: string): string;
begin
  Result := Items.Values[AKey];
end;

procedure TTyValueListEditor.SetValueOf(const AKey, AValue: string);
var i: Integer;
begin
  i := Items.IndexOfName(AKey);
  if i >= 0 then SetValue(i, AValue);
end;

procedure TTyValueListEditor.SetKeyColumnWidth(AValue: Integer);
begin
  if AValue < 16 then AValue := 16;
  if FKeyColumnWidth = AValue then Exit;
  FKeyColumnWidth := AValue;
  if FEditRow >= 0 then
    FEditor.BoundsRect := CellRect(FEditRow, 1);   // keep the open editor over its cell
  Invalidate;
end;

procedure TTyValueListEditor.InsertRow(const AKey, AValue: string);
begin
  Items.Add(AKey + '=' + AValue);
end;

procedure TTyValueListEditor.DeleteRow(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  { Cancel an open edit whenever the delete removes OR shifts its row — an index-based
    FEditRow can't survive a delete at or above it (else a later commit hits the wrong row). }
  if (FEditRow >= 0) and (AIndex <= FEditRow) then EndEdit(False);
  Items.Delete(AIndex);
  Invalidate;
end;

procedure TTyValueListEditor.BeginEdit(ARow: Integer);
begin
  if FReadOnly then Exit;
  if (ARow < 0) or (ARow >= Items.Count) then Exit;
  if FEditRow = ARow then Exit;
  if FEditRow >= 0 then EndEdit(True);      // commit a previous edit first
  FEditRow := ARow;
  FEditor.Controller := Controller;          // theme the overlay with the grid's controller
  FEditor.Text := GetValue(ARow);
  FEditor.BoundsRect := CellRect(ARow, 1);
  FEditor.Visible := True;
  if CanFocus and FEditor.CanFocus then FEditor.SetFocus;
  Invalidate;                                // stop painting the cell's static value text
end;

procedure TTyValueListEditor.EndEdit(ACommit: Boolean; ARestoreFocus: Boolean);
var row: Integer;
begin
  if FEditor = nil then Exit;                // editor not created yet (during inherited Create)
  if FEditRow < 0 then Exit;
  if FEndingEdit then Exit;                  // guard: hiding the editor re-enters via OnExit
  FEndingEdit := True;
  try
    row := FEditRow;
    FEditRow := -1;
    FEditor.Visible := False;
    if ACommit then
      SetValue(row, FEditor.Text)            // writes back + fires OnValueChanged iff changed
    else
      Invalidate;                            // cancel: repaint the (unchanged) cell text
    { Return focus to the list on a keyboard commit/cancel (Enter/Esc) so arrow/F2 keep
      working; NOT on a blur (the user is moving focus elsewhere). }
    if ARestoreFocus and CanFocus then SetFocus;
  finally
    FEndingEdit := False;
  end;
end;

procedure TTyValueListEditor.RepositionEditor;
begin
  if FEditor = nil then Exit;                // not created yet (base ctor may Resize us early)
  if FEditRow < 0 then Exit;
  if FEditRow >= Items.Count then
    EndEdit(False)                            // row vanished (e.g. Items.Clear): cancel
  else
    FEditor.BoundsRect := CellRect(FEditRow, 1);   // track KeyColumnWidth / resize changes
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
  { Don't commit into freed state when a closing parent form drops the editor's focus during
    teardown (FEndingEdit only guards EndEdit re-entry, not destruction). }
  if csDestroying in ComponentState then Exit;
  if (FEditRow >= 0) and not FEndingEdit then
    EndEdit(True);                            // focus-loss commits (Explorer-style), no re-focus
end;

procedure TTyValueListEditor.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
  if FEditor <> nil then FEditor.Controller := AValue;   // keep the overlay on the same theme
end;

procedure TTyValueListEditor.SetTopIndex(const AValue: Integer);
begin
  { The inline editor can't follow rows through a scroll — commit + close it first. All scroll
    paths (wheel, scrollbar drag, keyboard auto-scroll) funnel through here. }
  if (FEditRow >= 0) and (AValue <> TopIndex) then EndEdit(True);
  inherited SetTopIndex(AValue);
end;

procedure TTyValueListEditor.Resize;
begin
  inherited Resize;
  RepositionEditor;                            // the content width (and split) changed
end;

procedure TTyValueListEditor.Paint;
begin
  inherited Paint;
  RepositionEditor;                            // catch-all: ItemHeight change, direct Items edits
end;

procedure TTyValueListEditor.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  splitX, lo, hi, pad: Integer;
  keyR, valR: TRect;
  divider: TTyColor;
begin
  pad := P.Scale(6);
  splitX := ARowRect.Left + P.Scale(FKeyColumnWidth);
  lo := ARowRect.Left + P.Scale(24);
  hi := ARowRect.Right - P.Scale(24);
  if hi < lo then hi := lo;
  if splitX < lo then splitX := lo;
  if splitX > hi then splitX := hi;

  keyR := Rect(ARowRect.Left + pad, ARowRect.Top, splitX - P.Scale(4), ARowRect.Bottom);
  valR := Rect(splitX + pad, ARowRect.Top, ARowRect.Right - P.Scale(4), ARowRect.Bottom);

  // Key (name) — a plain label in the theme text colour.
  P.DrawText(keyR, GetKey(AIndex), AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True);

  // Column divider: a subtle 1px line derived from the theme text colour (not hard-coded).
  divider := (AStyle.TextColor and $00FFFFFF) or $28000000;
  P.Bitmap.Canvas2D.fillStyle(TyColorToBGRA(divider));
  P.Bitmap.Canvas2D.fillRect(splitX, ARowRect.Top + P.Scale(3), 1,
    (ARowRect.Bottom - ARowRect.Top) - P.Scale(6));

  // Value — skipped while its inline editor is open over this row.
  if AIndex <> FEditRow then
    P.DrawText(valR, GetValue(AIndex), AStyle.FontName, ResolveFontSize(AStyle),
      AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

procedure TTyValueListEditor.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var row: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);   // focus + row selection
  if (Button = mbLeft) and not FReadOnly then
  begin
    row := RowAtY(Y);
    if (row >= 0) and (X >= SplitXDp) then     // clicked the VALUE column -> edit
      BeginEdit(row)
    else if FEditRow >= 0 then
      EndEdit(True);                           // clicked a key / elsewhere -> commit + close
  end;
end;

procedure TTyValueListEditor.KeyDown(var Key: Word; Shift: TShiftState);
begin
  { F2 (or Enter) on the selected row begins editing its value. }
  if ((Key = VK_F2) or (Key = VK_RETURN)) and (Shift = []) and (ItemIndex >= 0)
    and not FReadOnly and (FEditRow < 0) then
  begin
    BeginEdit(ItemIndex);
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

end.
