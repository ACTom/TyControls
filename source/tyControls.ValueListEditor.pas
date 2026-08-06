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
    FParent: TTyValueRow;    // back-reference (NOT owned); nil for a root row
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
    property Parent: TTyValueRow read FParent;   // owning row (nil for a root row)
    function HasChildren: Boolean;
    function EffectiveKey: string;     // DisplayKey or Key
    function EffectiveValue: string;   // DisplayValue or Value
  end;

  { Fired after a value cell commits with a changed value. }
  TTyValueEditEvent = procedure(Sender: TObject; ARow: TTyValueRow) of object;

  { A keyUnique collision: ARow kept its old key, AKey is the name the user tried to give it.
    LCL raises a ShowMessage from inside the control (valedit.pas:1614); a control library
    must not, so the refusal is reported here and the app decides whether to say anything. }
  TTyKeyRejectedEvent = procedure(Sender: TObject; ARow: TTyValueRow; const AKey: string) of object;

  { Input restriction for the inline editor: vnmInteger allows only digits + a leading '-';
    vnmFloat additionally allows a single '.'. }
  TTyValueNumericMode = (vnmNone, vnmInteger, vnmFloat);

  { Which kind of pick list is currently dropped. }
  TTyValueDropKind = (dkNone, dkEnum, dkColor);

  { What the USER may do to the ROW SET at run time -- the switch that turns a read-only
    property sheet into an editable name/value list (the classic ini / environment-variable
    editor). Without it the user could change VALUES but never add, remove or rename an
    entry: rows could only be built from code.

    Identifiers are LCL's verbatim (C:\lazarus\lcl\valedit.pas:109) so
    `VLE.KeyOptions := [keyEdit, keyAdd]` ports across unchanged; the TYPE names carry the
    library's TTy prefix like every other option set here.

      keyEdit    the KEY cell is editable -- click it (or Shift+F2 on the selected row; plain
                 F2 already opens the VALUE) and the same inline editor opens over column 0,
                 committing to Row.Key.
      keyAdd     Insert (no modifiers) inserts a blank row AT the current position.
                 IMPLIES keyEdit, exactly as LCL's SetKeyOptions does (valedit.pas:1037-1038):
                 a row you can add but not name is not worth adding.
      keyDelete  Ctrl+Delete removes the current ROOT row.
      keyUnique  a rename that collides with a SIBLING's key is refused -- see
                 OnKeyRejected for the collision rule and how it differs from LCL's.

    Default [] -- every flag off, which is the behaviour this control already had.

    ORDINALS ARE API. A set property streams as a byte of bit positions, so reordering
    these renames every flag in every .lfm already written. Append only. }
  TTyKeyOption = (keyEdit, keyAdd, keyDelete, keyUnique);
  TTyKeyOptions = set of TTyKeyOption;

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
    simple InsertRow(key, value). Row layout, selection and scrolling come from TTyListBox.

    It REUSES TTyListBox's virtualised row loop but is not a list box, so it renders from its
    own keys -- see GetStyleTypeKey / GetItemStyleTypeKey / PaintItemContent. }
  TTyValueListEditor = class(TTyListBox)
  private
    FRoot: array of TTyValueRow;      // owned root rows
    FFlatRow: array of TTyValueRow;   // visible (expanded) rows, flattened
    FFlatLevel: array of Integer;     // indent level per flat row
    FEditor: TTyValueEdit;
    FEditFlat: Integer;               // flat index being edited, or -1
    FEditCol: Integer;                // which COLUMN that editor sits over: 0 = key, 1 = value
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
    FKeyOptions: TTyKeyOptions;
    FDraggingSplit: Boolean;
    FImages: TTyVirtualImageList;
    FOnValueChanged: TTyValueEditEvent;
    FOnKeyChanged: TTyValueEditEvent;      // a keyEdit rename committed
    FOnKeyRejected: TTyKeyRejectedEvent;   // a keyUnique collision refused a rename
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
    function GetRowCount: Integer;
    procedure SetRowCount(AValue: Integer);
    { Root-row index of the row the user currently has selected, or -1. Selection is a FLAT
      index, so this walks up to the owning root row. }
    function CurrentRootIndex: Integer;
    function GetValueFromIndex(AIndex: Integer): string;
    procedure SetValueFromIndex(AIndex: Integer; const AValue: string);
    function GetValue(const AKey: string): string;
    procedure SetValue(const AKey, AValue: string);
    procedure SetKeyColumnWidth(AValue: Integer);
    procedure SetKeyOptions(AValue: TTyKeyOptions);
    procedure SetImages(const AValue: TTyVirtualImageList);
    { keyUnique's collision rule: does AKey already name one of ARow's SIBLINGS? Case-insensitive
      (LCL uses AnsiCompareText, valedit.pas:1610) and blind to empty keys, like LCL's.

      SIBLINGS, not the whole list, and that is a deliberate divergence: LCL's list is flat, so
      "sibling" and "every row" are the same set over there. Ours nests, and the nesting produces
      legitimate duplicates by design -- every vekFont row grows children called 'name', 'size',
      'bold' (SeedFontFromRow), so two font rows in one sheet already hold two 'size' keys. A
      flat-global rule would declare that pre-existing tree invalid and make nested rows
      un-renameable the moment keyUnique went on. }
    function KeyCollides(ARow: TTyValueRow; const AKey: string): Boolean;
    procedure CommitEditor(AFlat: Integer; const AText: string);
    { Commit a keyEdit rename. False = keyUnique refused it (OnKeyRejected has fired and the row
      still holds its old key); the caller must not treat the edit as applied. }
    function CommitKeyEdit(ARow: TTyValueRow; const AText: string): Boolean;
    procedure CommitEditorRow(ARow: TTyValueRow; const AText: string);
    function RowExists(ARow: TTyValueRow): Boolean;
    function ChildByKey(ARow: TTyValueRow; const AKey: string): TTyValueRow;
    function StyleFlags(ARow: TTyValueRow): string;      // 'Bold Italic' from bold/italic children
    function IsStyleComposite(ARow: TTyValueRow): Boolean;
    function IsFontComposite(ARow: TTyValueRow): Boolean;
    function ComposeValue(ARow: TTyValueRow; out AValue: string): Boolean;   // font/style summary
    procedure PropagateUp(ARow: TTyValueRow);            // update composite ancestors after a child edit
    procedure RecomputeComposite(ARow: TTyValueRow);     // recompute a subtree's composite values
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
    procedure RepositionEditor;
  protected
    { Close whatever cell editor is open: ACommit applies the typed text (to the row's VALUE, or
      to its KEY when the key column is the one being edited), otherwise it is discarded.
      Protected rather than private because it is the other half of BeginEdit / BeginKeyEdit --
      a descendant that opens an editor has to be able to close one, and the guards drive the
      commit through here rather than by simulating a click somewhere else on the control. }
    procedure EndEdit(ACommit: Boolean; ARestoreFocus: Boolean = False);
    { NOT MIRRORED, and this is the whole reason TTyListBox asks per class.

      Every other member of the list-box family hit-tests rows on Y alone, so mirroring the
      row can move the paint without stranding a click. This one reads X three times -- the
      splitter drag (OverSplit), which column a click opens an editor in, and the expander
      triangle -- and it reads it from ContentLeftDp / SplitXDp / ContentRightDp, a SECOND
      computation of the geometry PaintItemContent derives from ARowRect. ContentRightDp even
      subtracts the scroll bar from the right on its own. Let the base mirror the row while
      those stay put and the splitter is grabbed a scrollbar's width from where it is drawn:
      the "painted here, answers there" bug this pass exists to remove.

      Removing this override means first collapsing those two computations into one -- the
      cell rects and the hit tests both coming from CellRect -- and mirroring THAT. Until
      then a mirrored form gets a left-to-right property inspector, which is honest. }
    function RtlRowLayout: Boolean; override;
    function GetStyleTypeKey: string; override;
    function GetItemStyleTypeKey: string; override;
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
    { LCL's signature (valedit.pas:188 `function InsertRow(const KeyName, Value: string;
      Append: Boolean): Integer`), and its return value: the index of the row that was made.
      This used to be a two-argument PROCEDURE that always appended, so a ported call failed
      to compile on the arity and there was no insert-at-a-position on the class at all --
      AddRow appends, DeleteRow removes, and building a list in a chosen order meant
      rebuilding it wholesale.

      AAppend=False inserts BEFORE the currently selected root row, which is what LCL's
      not-Append means (it inserts at the grid's current Row). It defaults to True so the
      calls already written keep working unchanged. }
    function InsertRow(const AKey, AValue: string; AAppend: Boolean = True): Integer;
    { Insert a root row at a chosen index and return it -- the general form InsertRow's
      Boolean is a two-case shorthand for. An index past the end appends. }
    function InsertRowAt(AIndex: Integer; const AKey, AValue: string): TTyValueRow;
    procedure Clear;
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
    { Start editing that row's KEY -- the rename gesture keyEdit turns on, and a no-op without it
      (or while ReadOnly). Public alongside BeginEdit so a host can offer "rename" from its own
      menu instead of only through the click / Shift+F2 the control handles itself. }
    procedure BeginKeyEdit(AFlat: Integer);
    // Run the dialog editor for a vekFont / vekDialog row (what the inline "…" button triggers).
    procedure InvokeRowDialog(AFlat: Integer);
    // Set a row's value programmatically (by identity): fires OnValueChanged and propagates to
    // composite ancestors (a Font/Style parent's value re-summarises from its children).
    procedure SetRowValue(ARow: TTyValueRow; const AText: string);
    { Number of rows that CURRENTLY HAVE A DISPLAY POSITION — root rows plus the descendants
      of expanded ones. A DATA metric: collapsing a node lowers it, resizing the control never
      does. This used to be called VisibleRowCount, which is a different measurement one class
      over -- see there. DisplayRowCount is the name TTyCustomGrid already uses for exactly
      this idea, so the two read alike in a log. }
    function DisplayRowCount: Integer;
    { How many rows the VIEWPORT currently holds -- a viewport metric, the same thing LCL's
      TCustomGrid.VisibleRowCount means (grids.pas:1301, body at 2274), which TValueListEditor
      inherits through TCustomStringGrid -> TCustomDrawGrid (republished public, grids.pas:1538)
      because over there this class IS a grid.

      It is NOT "how many rows are expanded". That is DisplayRowCount, and it used to be what
      this name returned here -- so paging maths ported from Lazarus compiled and computed
      garbage: with 500 expanded rows it paged 500 rows at a time. Both are Integer and both
      are public, so nothing warned anybody. This is the same collision fixed on TTyCustomGrid
      in 03c29b3; it did not land here because ours is a TTyListBox, not a grid.

      Faithful to LCL down to the off-by-one: LCL answers `VisibleGrid.Bottom - VisibleGrid.Top`,
      one LESS than the number of rows touching the viewport, so a page turn leaves one row of
      overlap. The overlap is dropped when the whole list fits, exactly as LCL's
      `if GridHeight <= ClientHeight then inc(Result)` does. }
    function VisibleRowCount: Integer;
    // The visible (flat) index being edited, or -1.
    property EditingRow: Integer read FEditFlat;
    { True while the open editor sits over the KEY column (a keyEdit rename) rather than the value.
      A pure query -- EditingRow alone cannot tell the two apart, and "which cell is open" decides
      where the commit lands. }
    function IsEditingKey: Boolean;
    { Number of ROOT rows -- read/write, as LCL declares it (valedit.pas:237, a property, not
      a function, so it can be read through RTTI or a binding layer and `VLE.RowCount := 0` is
      the one-line way to empty the list). Writing grows the list with blank rows or trims it
      from the end.

      Two deliberate differences from LCL, both consequences of not being a grid: it counts
      DATA rows only (LCL's includes the fixed title row, so the same list reports one more
      over there), and it is public rather than published -- a live row count in a .lfm would
      make the designer manufacture blank rows on every load. }
    property RowCount: Integer read GetRowCount write SetRowCount;
    property Keys[AIndex: Integer]: string read GetKey;                 // root rows
    { Values[] is indexed BY KEY, matching TValueListEditor on LCL / Delphi:
        property Values[const Key: string]: string read GetValue write SetValue;
      -- C:\lazarus\lcl\valedit.pas:202. It is the class's most-used member, so the identifier
      has to mean the same thing here as everywhere else. It used to be indexed by ROW NUMBER
      with the keyed form hidden as ValueOf[], so Values[0] named two different rows on the two
      libraries and every ported call site had to be rewritten (BREAKING: ValueOf[] is gone --
      it IS Values[] now, and the old Values[i] is ValueFromIndex[i]).

      The row form is deliberately NOT an overload of the same name: an Integer/string overload
      pair is exactly how a ported call lands on the wrong member and compiles. The split
      follows TStrings' own Values[Name] / ValueFromIndex[Index]. }
    property Values[const AKey: string]: string read GetValue write SetValue;
    // Root row AIndex's value -- the row-numbered form, pairing with Keys[] above.
    property ValueFromIndex[AIndex: Integer]: string read GetValueFromIndex write SetValueFromIndex;
    property InlineEditor: TTyValueEdit read FEditor;
  published
    property KeyColumnWidth: Integer read FKeyColumnWidth write SetKeyColumnWidth default 110;
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    { What the user may do to the row set: rename a key, add a row, delete a row, and whether a
      rename must stay unique. See TTyKeyOption. Default [], which is the behaviour that shipped
      before this existed -- values editable, the row SET fixed.

      ReadOnly still wins over all four: it turns the whole control read-only, so a ReadOnly
      sheet with KeyOptions set neither renames nor adds nor deletes. }
    property KeyOptions: TTyKeyOptions read FKeyOptions write SetKeyOptions default [];
    property Images: TTyVirtualImageList read FImages write SetImages;
    property OnValueChanged: TTyValueEditEvent read FOnValueChanged write FOnValueChanged;
    { A keyEdit rename COMMITTED (ARow.Key already holds the new name). Distinct from
      OnValueChanged on purpose -- that one is documented as naming the row whose VALUE moved,
      and firing it for a rename would make it lie. }
    property OnKeyChanged: TTyValueEditEvent read FOnKeyChanged write FOnKeyChanged;
    { A keyUnique rename REFUSED. The row kept its old key; the app decides whether to tell the
      user (LCL pops its own ShowMessage from inside the control; we do not). }
    property OnKeyRejected: TTyKeyRejectedEvent read FOnKeyRejected write FOnKeyRejected;
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

{ Density-aware icon/indent slot (logical px). Mirrors TyDensityHeight: at CLASSIC density it
  returns AClassic byte-identical (--icon-size is defined in the base theme as 16 and so cannot be
  used as a fallback here without shifting the classic geometry); at MODERN density it reads the
  --icon-size token (falling back to AClassic only if the token is somehow unset). }
function TyDensityIconSlot(AController: TTyStyleController; AClassic: Integer): Integer;
var c: TTyStyleController;
begin
  c := AController;
  if c = nil then c := TyDefaultController;
  if c.Density = tdModern then
    Result := c.Metric('--icon-size', AClassic)
  else
    Result := AClassic;   { classic: byte-identical to the control's own constant }
end;

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
  { The trailing "…" button slot: 18 logical px at classic, --icon-size at modern density. }
  if FShowEllipsis then Result := MulDiv(TyDensityIconSlot(ActiveController, 18), APPI, 96)
  else Result := 0;
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
  Result.FParent := Self;
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
  FEditCol := 1;      // the value column: what an edit meant before the key became editable
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
  if Length(FFlatRow) > VisibleRows then Dec(Result, Dp(ActiveController.Metric('--scrollbar-size', TyScrollbarSize)));
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
var tx, indent: Integer;
begin
  Result := False;
  if (AFlat < 0) or (AFlat > High(FFlatRow)) then Exit;
  if not FFlatRow[AFlat].HasChildren then Exit;
  indent := Dp(TyDensityIconSlot(ActiveController, FIndent));
  tx := ContentLeftDp + FFlatLevel[AFlat] * indent;
  Result := (AX >= tx) and (AX < tx + indent);
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

function TTyValueListEditor.InsertRowAt(AIndex: Integer;
  const AKey, AValue: string): TTyValueRow;
var
  i: Integer;
begin
  if AIndex < 0 then AIndex := 0;
  if AIndex > Length(FRoot) then AIndex := Length(FRoot);
  Result := TTyValueRow.Create;
  Result.Key := AKey;
  Result.Value := AValue;
  SetLength(FRoot, Length(FRoot) + 1);
  for i := High(FRoot) downto AIndex + 1 do FRoot[i] := FRoot[i - 1];
  FRoot[AIndex] := Result;
  RebuildFlat;
end;

function TTyValueListEditor.CurrentRootIndex: Integer;
var
  r: TTyValueRow;
  i: Integer;
begin
  Result := -1;
  if (ItemIndex < 0) or (ItemIndex > High(FFlatRow)) then Exit;
  r := FFlatRow[ItemIndex];
  while (r <> nil) and (r.Parent <> nil) do r := r.Parent;
  for i := 0 to High(FRoot) do
    if FRoot[i] = r then Exit(i);
end;

function TTyValueListEditor.InsertRow(const AKey, AValue: string;
  AAppend: Boolean = True): Integer;
var
  at: Integer;
begin
  if AAppend then
  begin
    AddRow(AKey, AValue);
    Exit(High(FRoot));
  end;
  at := CurrentRootIndex;
  if at < 0 then at := 0;    // nothing selected: LCL's current row on a fresh grid is the top
  InsertRowAt(at, AKey, AValue);
  Result := at;
end;

procedure TTyValueListEditor.Clear;
begin
  if FEditFlat >= 0 then EndEdit(False);
  FreeRows;
  RebuildFlat;
end;

function TTyValueListEditor.GetRowCount: Integer;
begin
  Result := Length(FRoot);
end;

procedure TTyValueListEditor.SetRowCount(AValue: Integer);
var
  i: Integer;
begin
  if AValue < 0 then AValue := 0;
  if AValue = Length(FRoot) then Exit;
  if FEditFlat >= 0 then EndEdit(False);
  { Trim from the END, so shrinking keeps the rows the caller built first. Each dropped row
    owns its children, so it has to be freed, not just unlinked. }
  for i := AValue to High(FRoot) do FRoot[i].Free;
  i := Length(FRoot);
  SetLength(FRoot, AValue);
  while i < AValue do
  begin
    FRoot[i] := TTyValueRow.Create;   // grown rows are blank; the caller names them
    Inc(i);
  end;
  RebuildFlat;
end;

function TTyValueListEditor.DisplayRowCount: Integer;
begin
  Result := Length(FFlatRow);
end;

function TTyValueListEditor.VisibleRowCount: Integer;
var
  sh, avail, touching, rest: Integer;
begin
  Result := 0;
  sh := Dp(ItemHeight);
  if sh < 1 then Exit;
  { Height, not ClientHeight -- the same headless note TTyListBox.VisibleRows carries: without
    a native handle ClientHeight lags SetBounds, and this control is borderless so at run time
    the two agree. The first row starts below the style's top padding, so that is not viewport. }
  avail := Height - ContentTopDp;
  if avail <= 0 then Exit;
  touching := (avail + sh - 1) div sh;      // a partially visible last row still touches
  rest := Length(FFlatRow) - TopIndex;      // rows left below the scroll position
  if rest < 0 then rest := 0;
  if touching > rest then touching := rest;
  { One LESS than the rows on screen (see the declaration): the overlap row that makes PageDown
    leave the seam row visible. Dropped when the whole list fits, mirroring LCL. }
  Result := touching - 1;
  if ContentTopDp + Length(FFlatRow) * sh <= Height then Inc(Result);
  if Result < 0 then Result := 0;
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

function TTyValueListEditor.GetValueFromIndex(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(FRoot)) then Result := FRoot[AIndex].Value else Result := '';
end;

{ The row-numbered setter addresses EXISTING rows only -- out of range is a no-op. It must NOT
  grow the list the way the keyed setter does, or a stray index would append an empty-keyed row. }
procedure TTyValueListEditor.SetValueFromIndex(AIndex: Integer; const AValue: string);
begin
  if (AIndex < 0) or (AIndex > High(FRoot)) then Exit;
  if FRoot[AIndex].Value = AValue then Exit;
  FRoot[AIndex].Value := AValue;
  Invalidate;
  if Assigned(FOnValueChanged) then FOnValueChanged(Self, FRoot[AIndex]);
end;

{ Key matching FOLDS CASE, as on LCL: TValueListEditor resolves the key through
  Strings.IndexOfName (valedit.pas:1094), which compares with TStringList.DoCompareText on a
  list whose CaseSensitive is never set -- i.e. False. Comparing with '=' here would compile and
  then read '' for a ported Values['height'] whose row is keyed 'Height'. }
function TTyValueListEditor.GetValue(const AKey: string): string;
var i: Integer;
begin
  for i := 0 to High(FRoot) do
    if SameText(FRoot[i].Key, AKey) then Exit(FRoot[i].Value);
  Result := '';
end;

{ Writing an UNKNOWN key APPENDS that row, as on LCL, where the setter falls through to
  Strings.Add (valedit.pas:1110-1114) -- ported code populates the editor by assigning to keys
  that do not exist yet, and dropping those writes would be silent data loss. The append is a
  row ADD, not a value CHANGE, so it stays silent like AddRow / InsertRow: OnValueChanged
  reports which EXISTING row changed and has no prior row to name here. }
procedure TTyValueListEditor.SetValue(const AKey, AValue: string);
var i: Integer;
begin
  for i := 0 to High(FRoot) do
    if SameText(FRoot[i].Key, AKey) then begin SetValueFromIndex(i, AValue); Exit; end;
  AddRow(AKey, AValue);   // (key, value) -- see AddRow's declaration, not the other order
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
  if FEditFlat >= 0 then FEditor.BoundsRect := CellRect(FEditFlat, FEditCol);
  Invalidate;
end;

{ LCL normalises the same way (valedit.pas:1035-1039): keyAdd pulls keyEdit in with it, because a
  blank row you cannot name is not a row anybody wanted. So `KeyOptions := [keyAdd]` READS BACK as
  [keyEdit, keyAdd] -- deliberate, and pinned by a test, since a setter that silently rewrites its
  argument is exactly the kind of thing a later refactor "tidies away". }
procedure TTyValueListEditor.SetKeyOptions(AValue: TTyKeyOptions);
begin
  if keyAdd in AValue then Include(AValue, keyEdit);
  if FKeyOptions = AValue then Exit;
  FKeyOptions := AValue;
  { A key edit already open stops being legal the moment keyEdit goes away -- committing it
    afterwards would apply a rename through a switch the app has just turned off. }
  if (FEditFlat >= 0) and (FEditCol = 0) and not (keyEdit in FKeyOptions) then EndEdit(False);
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

function TTyValueListEditor.KeyCollides(ARow: TTyValueRow; const AKey: string): Boolean;
var
  i: Integer;
  p, sib: TTyValueRow;
begin
  Result := False;
  { An empty name collides with nothing -- LCL skips empty Names[] the same way. Otherwise the
    blank rows keyAdd inserts would refuse to coexist, and two of them is the normal state of a
    list somebody is filling in. }
  if (ARow = nil) or (AKey = '') then Exit;
  p := ARow.Parent;
  if p = nil then
  begin
    for i := 0 to High(FRoot) do
      if (FRoot[i] <> ARow) and (FRoot[i].Key <> '') and SameText(FRoot[i].Key, AKey) then Exit(True);
  end
  else
    for i := 0 to p.ChildCount - 1 do
    begin
      sib := p.Child[i];
      if (sib <> ARow) and (sib.Key <> '') and SameText(sib.Key, AKey) then Exit(True);
    end;
end;

function TTyValueListEditor.CommitKeyEdit(ARow: TTyValueRow; const AText: string): Boolean;
begin
  Result := True;
  if ARow = nil then Exit;
  if ARow.Key = AText then Exit;                 // unchanged: not a rename, and never a collision
  if (keyUnique in FKeyOptions) and KeyCollides(ARow, AText) then
  begin
    Result := False;
    if Assigned(FOnKeyRejected) then FOnKeyRejected(Self, ARow, AText);
    Invalidate;                                  // repaint the key cell the editor was covering
    Exit;
  end;
  ARow.Key := AText;
  if Assigned(FOnKeyChanged) then FOnKeyChanged(Self, ARow);
  Invalidate;
end;

{ Commit by row IDENTITY (not flat index) — used by the deferred colour dialog, which must survive
  the row being renumbered/scrolled across the async + modal boundary. }
procedure TTyValueListEditor.CommitEditorRow(ARow: TTyValueRow; const AText: string);
begin
  if (ARow = nil) or (ARow.Value = AText) then Exit;
  ARow.Value := AText;
  if Assigned(FOnValueChanged) then FOnValueChanged(Self, ARow);
  PropagateUp(ARow);   // a Font/Style parent re-summarises from its (now-changed) children
  Invalidate;
end;

procedure TTyValueListEditor.SetRowValue(ARow: TTyValueRow; const AText: string);
begin
  CommitEditorRow(ARow, AText);
end;

function TTyValueListEditor.ChildByKey(ARow: TTyValueRow; const AKey: string): TTyValueRow;
var i: Integer;
begin
  Result := nil;
  if ARow = nil then Exit;
  for i := 0 to ARow.ChildCount - 1 do
    if SameText(ARow.Child[i].Key, AKey) then Exit(ARow.Child[i]);
end;

{ Space-separated enabled style words from the Bold/Italic/Underline/StrikeOut children (the four
  TFont.Style flags), in that order — e.g. '' / 'Bold' / 'Bold Underline'. }
function TTyValueListEditor.StyleFlags(ARow: TTyValueRow): string;

  function On_(const AKey: string): Boolean;
  var c: TTyValueRow;
  begin
    c := ChildByKey(ARow, AKey);
    Result := (c <> nil) and SameText(Trim(c.Value), 'True');
  end;

begin
  Result := '';
  if On_('bold')      then Result := Result + 'Bold ';
  if On_('italic')    then Result := Result + 'Italic ';
  if On_('underline') then Result := Result + 'Underline ';
  if On_('strikeout') then Result := Result + 'StrikeOut ';
  Result := Trim(Result);
end;

function TTyValueListEditor.IsStyleComposite(ARow: TTyValueRow): Boolean;
begin
  Result := SameText(ARow.Key, 'style') and
    ((ChildByKey(ARow, 'bold') <> nil) or (ChildByKey(ARow, 'italic') <> nil) or
     (ChildByKey(ARow, 'underline') <> nil) or (ChildByKey(ARow, 'strikeout') <> nil));
end;

function TTyValueListEditor.IsFontComposite(ARow: TTyValueRow): Boolean;
begin
  Result := (ARow.EditorKind = vekFont) and ARow.HasChildren;
end;

{ The summarised value for a recognised composite row (font / style), else False. A Style node
  reads 'Regular' or e.g. 'Bold, Italic'; a Font node reads 'Name, Size' + trailing style words
  (so a Bold change is visible on the Font row too), pulling style from a nested Style child if
  present, else from direct Bold/Italic children. }
function TTyValueListEditor.ComposeValue(ARow: TTyValueRow; out AValue: string): Boolean;
var nm, sz, flags: string; c, styleNode: TTyValueRow;
begin
  Result := True;
  if IsStyleComposite(ARow) then
  begin
    flags := StyleFlags(ARow);
    if flags = '' then AValue := 'Regular'
    else AValue := StringReplace(flags, ' ', ', ', [rfReplaceAll]);
  end
  else if IsFontComposite(ARow) then
  begin
    nm := ''; c := ChildByKey(ARow, 'name'); if c <> nil then nm := c.Value;
    sz := ''; c := ChildByKey(ARow, 'size'); if c <> nil then sz := c.Value;
    styleNode := ChildByKey(ARow, 'style');
    if styleNode <> nil then flags := StyleFlags(styleNode) else flags := StyleFlags(ARow);
    AValue := nm;
    if sz <> '' then AValue := AValue + ', ' + sz;
    if flags <> '' then AValue := AValue + ' ' + flags;   // e.g. 'Segoe UI, 9 Bold Italic'
  end
  else
    Result := False;
end;

procedure TTyValueListEditor.PropagateUp(ARow: TTyValueRow);
var p, nextP: TTyValueRow; nv: string;
begin
  p := ARow.Parent;
  while p <> nil do
  begin
    nextP := p.Parent;   // capture BEFORE the OnValueChanged handler can restructure/free the tree
    if ComposeValue(p, nv) and (nv <> p.Value) then
    begin
      p.Value := nv;
      if Assigned(FOnValueChanged) then FOnValueChanged(Self, p);
    end;
    if (nextP <> nil) and not RowExists(nextP) then Break;   // the handler freed the ancestor chain
    p := nextP;
  end;
end;

{ Recompute composite values across a subtree, deepest first (so a Style node is summarised
  before the Font node that folds it in). Used after the font dialog writes the leaf children. }
procedure TTyValueListEditor.RecomputeComposite(ARow: TTyValueRow);
var i: Integer; nv: string;
begin
  for i := 0 to ARow.ChildCount - 1 do RecomputeComposite(ARow.Child[i]);
  if ComposeValue(ARow, nv) and (nv <> ARow.Value) then
  begin
    ARow.Value := nv;
    if Assigned(FOnValueChanged) then FOnValueChanged(Self, ARow);
  end;
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
  { Same row AND same column: already editing this cell. A KEY edit on this row is a DIFFERENT
    cell, so clicking the value must still hand over -- without the column test the key editor
    stayed open and the click on the value did nothing. }
  if (FEditFlat = AFlat) and (FEditCol = 1) then Exit;
  if FEditFlat >= 0 then EndEdit(True);
  { EndEdit may have rebuilt or shortened the flat list (a commit handler can edit the tree). }
  if (AFlat < 0) or (AFlat > High(FFlatRow)) then Exit;
  r := FFlatRow[AFlat];
  { A Font/Style COMPOSITE row's value is DERIVED from its children (see ComposeValue), so it must
    NOT be freely typed — the typed text would be overwritten by the next child edit, or left as a
    stray value if the font dialog is cancelled. A Style composite has no dialog of its own, so
    there is nothing to edit inline (the user edits its child flags). }
  if IsStyleComposite(r) then Exit;
  case r.EditorKind of
    vekBoolean: BeginDropdown(AFlat, 'False'#10'True');
    vekEnum:    BeginDropdown(AFlat, r.EnumValues);
    vekColor:   BeginColorDropdown(AFlat);
    vekInteger: BeginInlineEdit(AFlat, vnmInteger, False);
    vekFloat:   BeginInlineEdit(AFlat, vnmFloat, False);
    vekFont, vekDialog:
      begin
        { The value is authoritative FROM the dialog (font picker / OnEditRow), so the inline text
          is READ-ONLY — still clickable / selectable / copyable, just edited via the "…" button
          (not free-typed). This also keeps a Font composite in sync with its children. }
        BeginInlineEdit(AFlat, vnmNone, True);
        FEditor.ReadOnly := True;
      end;
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
  FEditCol := 1;
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

{ keyEdit: the SAME inline editor, over column 0, holding the row's Key. Plain text always -- the
  per-row EditorKind (numeric / dropdown / dialog) describes how the VALUE is edited and has
  nothing to say about the name, so a vekColor row's key is still typed, not picked. A read-only
  ROW is read-only in its value only: renaming the entry is a row-set operation, which is what
  KeyOptions governs. }
function TTyValueListEditor.IsEditingKey: Boolean;
begin
  Result := (FEditFlat >= 0) and (FEditCol = 0);
end;

procedure TTyValueListEditor.BeginKeyEdit(AFlat: Integer);
begin
  if FReadOnly or not (keyEdit in FKeyOptions) then Exit;
  if (AFlat < 0) or (AFlat > High(FFlatRow)) then Exit;
  if (FEditFlat = AFlat) and (FEditCol = 0) then Exit;
  if FEditFlat >= 0 then EndEdit(True);
  { EndEdit can drop rows out from under us (a rejected commit repaints, a handler may edit the
    tree), so re-check before indexing. }
  if (AFlat < 0) or (AFlat > High(FFlatRow)) then Exit;
  FEditFlat := AFlat;
  FEditCol := 0;
  FEditor.NumericMode := vnmNone;
  FEditor.ShowEllipsis := False;
  FEditor.ReadOnly := False;
  FEditor.Controller := Controller;
  FEditor.Text := FFlatRow[AFlat].Key;    // the REAL key, not EffectiveKey: DisplayKey is a label
  FEditor.BoundsRect := CellRect(AFlat, 0);
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
  { 'TyListBox' on purpose, NOT this control's key: the popup's CONTENT is a real TTyListBox
    (FEnumList / FColorList), so the window mask must match the radius that list fills with.
    Reading the inspector's own radius here would round the window to a shape its content
    does not have. }
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
  { Commit + CLOSE the inline editor before the modal opens. Otherwise the editor loses focus to
    the dialog, its OnExit commits the (stale) editor text, and that overwrites the value the
    dialog just set — the classic "font dialog changes nothing" bug. }
  if FEditFlat = AFlat then EndEdit(True);
  case r.EditorKind of
    vekFont:   EditFontRow(AFlat);
    vekDialog: if Assigned(FOnEditRow) then begin FOnEditRow(Self, r); Invalidate; end;
  end;
end;

{ Seed a TFont from a Font row: from its child rows (Name/Size/Bold/Italic/Color) if it has
  them, else from its 'Name, Size' descriptor. }
procedure ApplyStyleFlag(AFont: TFont; AFlag: TFontStyle; const AValue: string);
begin
  if SameText(Trim(AValue), 'True') then AFont.Style := AFont.Style + [AFlag]
  else AFont.Style := AFont.Style - [AFlag];
end;

{ Map a child key to its TFont.Style flag (all four: bold/italic/underline/strikeout). }
function TyFontStyleKey(const AKey: string; out AFlag: TFontStyle): Boolean;
var k: string;
begin
  Result := True;
  k := LowerCase(AKey);
  if k = 'bold' then AFlag := fsBold
  else if k = 'italic' then AFlag := fsItalic
  else if k = 'underline' then AFlag := fsUnderline
  else if k = 'strikeout' then AFlag := fsStrikeOut
  else Result := False;
end;

procedure TTyValueListEditor.SeedFontFromRow(ARow: TTyValueRow; AFont: TFont);
var i, j, sz: Integer; c, g: TTyValueRow; k, nm: string; flag: TFontStyle;
begin
  if ARow.HasChildren then
  begin
    for i := 0 to ARow.ChildCount - 1 do
    begin
      c := ARow.Child[i];
      k := LowerCase(c.Key);
      if k = 'name' then begin if Trim(c.Value) <> '' then AFont.Name := c.Value; end
      else if k = 'size' then begin if StrToIntDef(c.Value, 0) > 0 then AFont.Size := StrToIntDef(c.Value, AFont.Size); end
      else if k = 'color' then AFont.Color := StringToColorDef(c.Value, AFont.Color)
      else if TyFontStyleKey(k, flag) then ApplyStyleFlag(AFont, flag, c.Value)
      else if (k = 'style') and c.HasChildren then     // OI-style Font -> Style -> Bold/Italic/...
        for j := 0 to c.ChildCount - 1 do
        begin
          g := c.Child[j];
          if TyFontStyleKey(g.Key, flag) then ApplyStyleFlag(AFont, flag, g.Value);
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

var i, j: Integer; c, g: TTyValueRow; k: string; flag: TFontStyle;
begin
  didChange := False;
  for i := 0 to ARow.ChildCount - 1 do
  begin
    c := ARow.Child[i];
    k := LowerCase(c.Key);
    if k = 'name' then SetChild(c, AFont.Name)
    else if k = 'size' then SetChild(c, IntToStr(AFont.Size))
    else if k = 'color' then SetChild(c, ColorToString(AFont.Color))
    else if TyFontStyleKey(k, flag) then SetChild(c, BoolStr(flag in AFont.Style))
    else if (k = 'style') and c.HasChildren then     // OI-style Font -> Style -> Bold/Italic/...
      for j := 0 to c.ChildCount - 1 do
      begin
        g := c.Child[j];
        if TyFontStyleKey(g.Key, flag) then SetChild(g, BoolStr(flag in AFont.Style));
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
      if r.HasChildren then
      begin
        SyncFontChildren(r, dlg.Font);   // write Name/Size/Bold/Italic/Color leaves
        RecomputeComposite(r);           // re-summarise the Style node + the Font row from the leaves
        Invalidate;
      end
      else
        CommitEditor(AFlat, Format('%s, %d', [dlg.Font.Name, dlg.Font.Size]));
    end;
  finally
    dlg.Free;
  end;
  if CanFocus then SetFocus;
end;

procedure TTyValueListEditor.EndEdit(ACommit: Boolean; ARestoreFocus: Boolean);
var flat, col: Integer;
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
    col := FEditCol;
    FEditFlat := -1;
    FEditCol := 1;
    FEditor.Visible := False;
    if ACommit then
    begin
      { Column 0 is a RENAME, not a value change: it writes Row.Key, fires OnKeyChanged, and can
        be refused outright by keyUnique. Routing it through CommitEditor would have written the
        typed text into the row's VALUE -- the key cell's editor silently corrupting the row it
        was opened on. }
      if col = 0 then
      begin
        if (flat >= 0) and (flat <= High(FFlatRow)) then CommitKeyEdit(FFlatRow[flat], FEditor.Text);
      end
      else
        CommitEditor(flat, FEditor.Text);
    end
    else
      Invalidate;
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
    FEditor.BoundsRect := CellRect(FEditFlat, FEditCol);
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

function TTyValueListEditor.RtlRowLayout: Boolean;
begin
  { See the declaration: the x-axis hit tests here are computed a second time and would not
    follow. }
  Result := False;
end;

function TTyValueListEditor.GetStyleTypeKey: string;
begin
  { Its own key, not the ancestor's. This is a property inspector that merely reuses
    TTyListBox's row loop: it draws two COLUMNS split by a user-draggable divider, an indented
    key column, per-row expand/collapse triangles and a value column with swatches and a '…'
    dialog affordance -- none of which a list of strings has. While it rendered from
    'TyListBox'/'TyListItem' a skin could not tint the key column, colour the divider, restyle
    the expander, or make an inspector's selection read differently from a plain list's. Its
    parts are TyValueListEditor (frame), TyValueListEditorRow, -Key, -Value, -Divider,
    -Expander. }
  Result := 'TyValueListEditor';
end;

function TTyValueListEditor.GetItemStyleTypeKey: string;
begin
  { The inspector's rows are not list items: this is the seam that unwelds them. }
  Result := 'TyValueListEditorRow';
end;

procedure TTyValueListEditor.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  r: TTyValueRow;
  level, splitX, lo, hi, pad, indentX, indent, sz, weight, imgSz, sw: Integer;
  keyR, valR, tri, swR: TRect;
  { Named *Sty, not *S: 'keyS' collides with the published Keys[] property (identifiers are
    case-insensitive), and the compiler reports it as a duplicate identifier. }
  expSty, keySty, divSty, valSty: TTyStyleSet;
  divider, keyCol, valCol, valDef, triCol: TTyColor;
  ctx: TBGRACanvas2D;
  bmp: TBGRABitmap;
  cy: Single;
begin
  if (AIndex < 0) or (AIndex > High(FFlatRow)) then Exit;
  r := FFlatRow[AIndex];
  level := FFlatLevel[AIndex];
  pad := P.Scale(5);

  { The inspector's four sub-parts, each with a key a skin can reach: the expander triangle,
    the key column, the column divider and the value column. Every one falls back to what it
    took from the ROW style before, so a theme that defines none of them paints exactly as it
    did -- these are hooks, not a repaint. Colour only: the geometry (indent, divider width,
    swatch size) stays where the layout constants put it. }
  expSty := ActiveController.Model.ResolveStyle('TyValueListEditorExpander', '', []);
  keySty := ActiveController.Model.ResolveStyle('TyValueListEditorKey', '', []);
  divSty := ActiveController.Model.ResolveStyle('TyValueListEditorDivider', '', []);
  valSty := ActiveController.Model.ResolveStyle('TyValueListEditorValue', '', []);
  if tpTextColor in expSty.Present then triCol := expSty.TextColor else triCol := AStyle.TextColor;
  if tpTextColor in keySty.Present then keyCol := keySty.TextColor else keyCol := AStyle.TextColor;
  if tpTextColor in valSty.Present then valDef := valSty.TextColor else valDef := AStyle.TextColor;

  splitX := ARowRect.Left + P.Scale(FKeyColumnWidth);
  lo := ARowRect.Left + P.Scale(24);
  hi := ARowRect.Right - P.Scale(40);
  if hi < lo then hi := lo;
  if splitX < lo then splitX := lo;
  if splitX > hi then splitX := hi;

  indent := TyDensityIconSlot(ActiveController, FIndent);
  indentX := ARowRect.Left + level * P.Scale(indent);

  // Expand / collapse triangle for rows with children.
  if r.HasChildren then
  begin
    ctx := P.Bitmap.Canvas2D;
    sz := P.Scale(9);
    tri := Rect(indentX + P.Scale(2), ARowRect.Top + ((ARowRect.Bottom - ARowRect.Top) - sz) div 2,
      indentX + P.Scale(2) + sz, 0);
    tri.Bottom := tri.Top + sz;
    cy := (tri.Top + tri.Bottom) / 2;
    ctx.fillStyle(TyColorToBGRA(triCol));
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

  // Key label (after the triangle + indent), skipped while ITS inline editor is open -- else the
  // old name shows through beside the text being typed, exactly as the value cell would.
  if not ((AIndex = FEditFlat) and (FEditCol = 0)) then
  begin
    keyR := Rect(indentX + P.Scale(indent), ARowRect.Top, splitX - P.Scale(4), ARowRect.Bottom);
    P.DrawText(keyR, r.EffectiveKey, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
      keyCol, taLeftJustify, tlCenter, True);
  end;

  // Column divider. Its own key ('TyValueListEditorDivider') -- taking the colour from a
  // background, like every other rule/line key in the library ('TyGridLine'). Silent theme =>
  // the old derivation, the row text colour at a fixed alpha.
  if tpBackground in divSty.Present then divider := divSty.Background.Color
  else divider := (AStyle.TextColor and $00FFFFFF) or $28000000;
  P.Bitmap.Canvas2D.fillStyle(TyColorToBGRA(divider));
  P.Bitmap.Canvas2D.fillRect(splitX, ARowRect.Top + P.Scale(2), 1,
    (ARowRect.Bottom - ARowRect.Top) - P.Scale(4));

  // Value cell (skipped while ITS inline editor is open -- a KEY edit on this row leaves the
  // value cell alone, so the row still reads as the thing being renamed).
  if (AIndex <> FEditFlat) or (FEditCol <> 1) then
  begin
    valR := Rect(splitX + pad, ARowRect.Top, ARowRect.Right - P.Scale(4), ARowRect.Bottom);
    // '…' affordance for the ellipsis-dialog editors (font / custom), at the right edge. (vekColor
    // uses a dropdown, so it shows a swatch instead of a '…'.)
    if r.EditorKind in [vekFont, vekDialog] then
    begin
      P.DrawText(Rect(valR.Right - P.Scale(16), valR.Top, valR.Right, valR.Bottom), '…',
        AStyle.FontName, ResolveFontSize(AStyle) + 2, 700, valDef, taCenter, tlCenter, False);
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
      P.StrokeBorder(swR, 0, 1, valDef);
      valR.Left := valR.Left + sw + P.Scale(5);
    end;
    // optional image
    if (FImages <> nil) and (r.ImageIndex >= 0) and (r.ImageIndex < FImages.Count) then
    begin
      imgSz := (ARowRect.Bottom - ARowRect.Top) - P.Scale(6);
      if imgSz < 8 then imgSz := 8;
      bmp := FImages.CachedIndex(r.ImageIndex, imgSz);   // borrowed; do NOT free
      if bmp <> nil then
        P.Bitmap.PutImage(valR.Left,
          ARowRect.Top + ((ARowRect.Bottom - ARowRect.Top - bmp.Height) div 2), bmp,
          dmDrawWithTransparency);
      valR.Left := valR.Left + imgSz + P.Scale(4);
    end;
    { The per-row override still wins over the theme -- an app that colours one value red
      means it, and the value column's key only supplies the DEFAULT. }
    if r.TextColor <> clDefault then valCol := TyColorFromLCL(r.TextColor, 255)
    else valCol := valDef;
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
    { keyEdit turns the key cell into the second editable column. Off, a click left of the
      divider keeps doing what it always did: commit whatever was open and select the row. }
    else if keyEdit in FKeyOptions then BeginKeyEdit(flat)
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
var at: Integer;
begin
  { keyAdd / keyDelete are ROW-SET gestures, so they run before the edit keys and regardless of
    whether an editor is open -- but never while the control is ReadOnly, which outranks all of
    KeyOptions. LCL: valedit.pas:1296-1312. }
  if not FReadOnly then
  begin
    { Insert with NO modifiers. LCL inserts AT the current row rather than appending
      (InsertRow('','',False), valedit.pas:1301), so the new row lands where the user is looking. }
    if (keyAdd in FKeyOptions) and (Key = VK_INSERT) and (Shift = []) then
    begin
      if FEditFlat >= 0 then EndEdit(True);
      InsertRow('', '', False);
      Key := 0;
      Exit;
    end;
    { Ctrl+Delete, not bare Delete: bare Delete belongs to the text being typed, and LCL carries
      the same note (valedit.pas:1308-1309) after testers reported Delphi's documented plain
      Delete never actually fires. }
    if (keyDelete in FKeyOptions) and (Key = VK_DELETE) and (Shift = [ssModifier]) then
    begin
      at := CurrentRootIndex;      // DeleteRow is indexed by ROOT row; selection is a flat index
      if at >= 0 then
      begin
        if FEditFlat >= 0 then EndEdit(False);   // the row is going away: do not commit into it
        DeleteRow(at);
      end;
      Key := 0;
      Exit;
    end;
  end;
  if ((Key = VK_F2) or (Key = VK_RETURN)) and (Shift = []) and (ItemIndex >= 0)
    and not FReadOnly and (FEditFlat < 0) then
  begin
    BeginEdit(ItemIndex);
    Key := 0;
    Exit;
  end;
  { Shift+F2 opens the KEY cell -- F2 is already taken by the value editor, and keyEdit must be
    reachable without a mouse or the flag is only half there. }
  if (Key = VK_F2) and (Shift = [ssShift]) and (ItemIndex >= 0)
    and not FReadOnly and (keyEdit in FKeyOptions) then
  begin
    BeginKeyEdit(ItemIndex);
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

end.
