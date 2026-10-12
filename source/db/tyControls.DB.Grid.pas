unit tyControls.DB.Grid;
{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}
{ The data-aware grid (issue #34, phase 2): LCL's TDBGrid on top of the library's string grid.
  TTyCustomDBGrid holds the data link and all the code, TTyDBGrid publishes.

  THE RECORD WINDOW. The grid never copies the dataset. It works the way LCL's TDBGrid does:
  the data link's BufferCount is the number of whole rows the body has room for, the grid's
  RowCount is the number of records in that buffer (DataLink.RecordCount), and data row i IS
  buffer record i -- to read a cell the grid sets DataLink.ActiveRecord to the row, reads the
  field and puts ActiveRecord back (in a finally), so the dataset's current record never moves
  under the user. The cursor row follows the dataset: whenever the dataset scrolls, changes or
  opens, Row becomes DataLink.ActiveRecord. Moving through the records is the dataset's job
  (DataLink.MoveBy and friends); the buffer is recomputed when the body changes height (a
  resize, a row height or header change, a theme whose row height differs).

  CELL TEXT is the field's, never the string grid's cell store: Field.DisplayText; a memo shows
  what its DisplayText says ('(MEMO)') unless dgDisplayMemoText, then its content; a ftBlob
  field '(blob)', as LCL's; a NULL field what its DisplayText says, which for a plain field is
  empty -- the store is never consulted, so nothing written there can show through. A boolean
  field is a check box column while dgeCheckboxColumn is on (checked, unchecked, grayed for
  NULL); its cell text is then the string grid's own check vocabulary ('1', '', '2').

  OPTIONS are LCL's: Options is a TDBGridOptions and OptionsExtra a TDBGridExtraOptions, the
  types of LCL's DBGrids unit, with LCL's defaults, so a form written for TDBGrid reads the same
  values. They are mapped onto the string grid underneath (titles = the header band, the
  indicator, the grid lines, column sizing and moving, Tab, row select, header hot tracking and
  pushed look, cell hints, ellipsis, row highlight, thumb tracking, double-click auto size).
  The string grid's own options are not published here. The options this grid does not act on
  yet are kept and read back.

  COLUMNS. Columns is the header's collection itself (a TTyDBGridColumns of TTyDBGridColumn):
  each column names a field (FieldName). With no design columns and dgeAutoColumns, the grid
  makes one automatic column per field when the dataset opens (the field's visibility,
  DisplayName title, DisplayWidth width, alignment and read-only flag) and drops them when it
  closes; automatic columns are never written to a form file, and none are made in the
  designer. A design column takes its title, width and alignment from its field until they are
  set; only the values set are written to the form file. DisplayFormat is pushed to a numeric
  or date-time field only when the column's own DisplayFormat was set, as LCL's TColumn does.

  CLIENT-SIDE SORTING, FILTERING AND GROUPING are off: they work on the cell store, which this
  grid does not use, and they would reorder a window of the dataset rather than the dataset.
  The display order is always the buffer order; sorting belongs to the dataset. Undo is off too
  (UndoLimit 0): the values live in the dataset.

  MOVING is the dataset's, as in LCL's TDBGrid: every move the user makes becomes a move of the
  data link and the cursor row only follows the dataset (DataSetScrolled). A row move of the
  string grid -- an arrow, Enter, Tab wrapping, a click on another row, Row := from code -- is
  DataLink.MoveBy(the row difference) (MoveCursor); PgUp / PgDn are MoveBy(+-the window's rows)
  (LCL's VisibleRowCount, no overlap row); Ctrl+Home / Ctrl+End are First / Last; Home / End
  stay the string grid's (first / last column); one wheel notch is MoveBy(+-1). The vertical
  bar is the grid's own, scrolled by whole records: for a sequenced dataset (IsSequenced and not
  Filtered) its range is the records and its position RecNo - 1, and moving it sets RecNo; for
  any other dataset it is LCL's three-position bar (top, middle, bottom -- BOF, inside, EOF) and
  moving it moves by its direction: one step MoveBy(+-1), more MoveBy(+-the window's rows). It
  shows when the records do not all fit in the window (a sequenced dataset), or when the window
  is full (any other). Horizontal scrolling is the string grid's.

  EDITING (LCL's TDBGrid again). A cell opens its editor with the field's Text (a memo's
  content under dgDisplayMemoText), its mask is the field's EditMask through OnFieldEditMask,
  a lookup field edits as a pick list of its LookupDataSet. Opening an editor on the current
  record -- typing, F2, a double click -- puts the dataset in dsEdit through the data link; a
  refused Edit (the data source does not AutoEdit, say) makes the cell read-only and the key is
  swallowed. Leaving the cell writes the text into the field (Field.Text; a lookup writes its
  key fields as well); leaving the record posts it (the dataset's own CheckBrowseMode), and so
  does the dataset's Post while an editor is open (UpdateData). Esc drops the cell's edit, and
  with no editor open cancels the record. Down past the last record appends one while the
  grid can modify and dgDisableInsert is off; a new record nobody has typed into is cancelled
  again by Up, by Down (when inserted inside the dataset), by a click on another row, by any
  move, and by the focus leaving the grid (dgCancelOnExit). Insert inserts, Ctrl+Del deletes --
  asked first through ConfirmDeleteRecord when dgConfirmDelete. A check box writes AsBoolean
  (a boolean field) or the column's words (another field). A value the field or the dataset
  refuses (an exception from Field.Text or from Post) keeps the editor on its cell with what
  the user typed; the exception goes on to the application. A cell is read-only when the grid
  is ReadOnly, dgEditing is off, the data link is ReadOnly, the dataset or the field cannot
  modify, the column is ReadOnly, or the field is calculated, an auto-increment counter, a
  blob (a memo without dgDisplayMemoText) or a lookup whose key fields cannot be modified.
  A check box toggles only when the dataset goes into dsEdit (CanToggleCellCheck): a refused
  toggle changes nothing and reports nothing (no OnCheckBoxChange).

  TAB (dgTabs) moves field by field and, past the last field of the window's last row, on to
  the next record's first field -- appending past the last record as Down does; Shift+Tab is
  the mirror. LCL leaves the grid there instead while the record is being edited or the grid
  cannot modify; this grid always goes on.

  THE INDICATOR (plan D6) marks the current record with its state -- a triangle browsing, an
  I-beam editing, the I-beam in the insert colour (the accent the theme gives a selected cell)
  inserting -- and every other selected row (dgMultiselect) with a dot. A theme replaces a
  mark with an icon-font glyph: '--glyph-dbgrid-browse', '-edit', '-insert', '-selected';
  otherwise the grid draws it with the painter in the indicator column's text colour. It turns
  round with the reading direction.

  MULTISELECT (dgMultiselect, LCL's rules): a click selects the record clicked alone, Ctrl+click
  (and Ctrl+*) toggles it, Shift+Up / Shift+Down extend or shrink the run, the other moves select
  the record moved to alone; dgPersistentMultiSelect keeps the selection through all of them
  but Ctrl+click. SelectedRows holds a bookmark per record (TTyBookmarkList); a selected row is
  drawn as a selected cell is. The list empties when the dataset closes or is changed, and when
  dgMultiselect goes.

  A TITLE CLICK is OnTitleClick(Column) -- the dataset is the one to sort (IndexFieldNames, an
  ORDER BY); there are no filter buttons on the titles either.

  EVENTS are LCL's (plan D9) with this grid's column in place of TColumn; the drawing ones
  carry the painter (there is no canvas to draw on), and OnPrepareCanvas changes the cell's
  style (TTyGridCellAppearance) rather than a canvas. While a cell's event runs the data link's
  active record is that cell's row. }
interface

uses
  Classes, SysUtils, Math, Types, Controls, Graphics, StdCtrls, LCLType, LMessages, LazUTF8,
  DB, DBCtrls, Grids, DBGrids,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Columns, tyControls.Grid,
  tyControls.Grid.Layout;

const
  { LCL's TDBGrid defaults (dbgrids.pas, TCustomDBGrid.Options / OptionsExtra). Untyped, so
    they can stand in a default clause. }
  TyDBGridDefaultOptions = [dgColumnResize, dgColumnMove, dgTitles, dgIndicator, dgRowLines,
    dgColLines, dgConfirmDelete, dgCancelOnExit, dgTabs, dgEditing, dgAlwaysShowSelection];
  TyDBGridDefaultExtraOptions = [dgeAutoColumns, dgeCheckboxColumn];
  { The indicator column's width (logical px), LCL's DEFINDICATORCOLWIDTH. }
  TyDBGridIndicatorWidth = 12;

type
  { What the indicator column shows on a row (plan D6). }
  TTyDBGridIndicator = (dgiNone, dgiBrowse, dgiEdit, dgiInsert, dgiSelected);

const
  { The icon-font override each indicator mark looks for (v3/C5); without one the grid draws
    its own mark with the painter. }
  TyDBGridIndicatorTokens: array[TTyDBGridIndicator] of string = (
    '', '--glyph-dbgrid-browse', '--glyph-dbgrid-edit', '--glyph-dbgrid-insert',
    '--glyph-dbgrid-selected');

type
  TTyCustomDBGrid = class;
  TTyDBGridColumn = class;

  { LCL's DBGrids event types, with this grid's column where LCL's take a TColumn. }
  TTyDBGridClickEvent = procedure(Column: TTyDBGridColumn) of object;
  { OnDrawColumnCell: the cell's background is painted, its text not yet. Draw with APainter
    in Rect; AHandled := True and the grid draws no text of its own. }
  TTyDBGridDrawColumnCellEvent = procedure(Sender: TObject; const Rect: TRect;
    DataCol: Integer; Column: TTyDBGridColumn; State: TGridDrawState;
    APainter: TTyPainter; var AHandled: Boolean) of object;
  { OnDrawColumnTitle: after the title is drawn, as LCL's (DefaultDrawing). }
  TTyDBGridDrawColumnTitleEvent = procedure(Sender: TObject; const Rect: TRect;
    DataCol: Integer; Column: TTyDBGridColumn; State: TGridDrawState;
    APainter: TTyPainter) of object;
  { OnPrepareCanvas: LCL hands over the canvas to set colours and font on; this grid draws
    with a painter, and what a cell is drawn with is AStyle -- background, text colour, font,
    alignment -- which the handler may change. }
  TTyDBGridPrepareStyleEvent = procedure(Sender: TObject; DataCol: Integer;
    Column: TTyDBGridColumn; AState: TGridDrawState;
    var AStyle: TTyGridCellAppearance) of object;
  TTyDBGridSelEditorEvent = procedure(Sender: TObject; Column: TTyDBGridColumn;
    var Editor: TWinControl) of object;
  TTyDBGridCheckboxStateEvent = procedure(Sender: TObject; Column: TTyDBGridColumn;
    var AState: TCheckBoxState) of object;
  TTyDBGridCellHintEvent = procedure(Sender: TObject; Column: TTyDBGridColumn;
    var AText: string) of object;

  { LCL's TBookmarkList, for the rows the user picked under dgMultiselect: a bookmark per
    record, made, compared (CompareBookmarks) and freed by the dataset. The list is the
    grid's; it empties when the dataset closes or dgMultiselect goes. }
  TTyBookmarkList = class
  private
    FGrid: TTyCustomDBGrid;
    FList: array of TBookmark;
    FDataSet: TDataSet;   // the one the bookmarks came from
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TBookmark;
    function GetCurrentRowSelected: Boolean;
    procedure SetCurrentRowSelected(AValue: Boolean);
    function LinkDataSet: TDataSet;
    procedure FreeOne(ABookmark: TBookmark);
    procedure Changed;
  public
    constructor Create(AGrid: TTyCustomDBGrid);
    destructor Destroy; override;
    procedure Clear;
    { Delete every selected record from the dataset, then forget them (LCL's). }
    procedure Delete;
    { The position of the record ABookmark marks, -1 when it is not selected. }
    function IndexOf(const ABookmark: TBookmark): Integer;
    { Forget the bookmarks the dataset no longer holds (BookmarkValid); True when any went. }
    function Refresh: Boolean;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TBookmark read GetItem; default;
    { Is the dataset's current record selected? Setting it selects or deselects it. }
    property CurrentRowSelected: Boolean read GetCurrentRowSelected
      write SetCurrentRowSelected;
  end;

  { LCL's TComponentDataLink, which DBGrids keeps to itself: every dataset event reaches the
    grid. UpdateData (the dataset is about to post or leave the record) writes the open
    editor's text into its field. }
  TTyDBGridDataLink = class(TDataLink)
  private
    FGrid: TTyCustomDBGrid;
  protected
    procedure ActiveChanged; override;
    procedure DataSetChanged; override;
    procedure DataSetScrolled(Distance: Integer); override;
    procedure EditingChanged; override;
    procedure LayoutChanged; override;
    procedure RecordChanged(Field: TField); override;
    procedure UpdateData; override;
  public
    constructor Create(AGrid: TTyCustomDBGrid);
    { TDataLink keeps it protected; the grid moves through it. }
    function MoveBy(Distance: Integer): Integer; override;
  end;

  { What TTyCustomDBGrid.DataOp does to the dataset. }
  TTyDBGridDataOp = (dgoMoveBy, dgoRecNo, dgoFirst, dgoLast, dgoInsert, dgoAppend);

  { One column of the data-aware grid: a field by name. Text (the title), Width and Alignment
    follow the field until they are set -- set from code, the Object Inspector or a form file,
    or changed by the user (a dragged width) -- and only then are they written to a form
    file. The title of a column is the field's DisplayName (its FieldName while the dataset is
    closed), the width the one DisplayWidth asks for (TTyCustomDBGrid.DefaultFieldWidth), the
    alignment the field's (centred for a check box column). }
  TTyDBGridColumn = class(TTyGridColumn)
  private
    FFieldName: string;
    FField: TField;
    FAutomatic: Boolean;
    FDisplayFormat: string;
    FDisplayFormatSet: Boolean;
    FTitleSet: Boolean;
    FWidthSet: Boolean;
    FAlignmentSet: Boolean;
    { The values the column had from its field when they were last given: a value still
      equal to one of them is the field's, not the user's. }
    FDefTitle: TCaption;
    FDefWidth: Integer;
    FDefAlignment: TAlignment;
    function GetGrid: TTyCustomDBGrid;
    function GetTitle: TCaption;
    procedure SetTitle(const AValue: TCaption);
    function IsTitleStored: Boolean;
    function GetWidth: Integer;
    procedure SetWidth(AValue: Integer);
    function IsWidthStored: Boolean;
    function GetAlignment: TAlignment;
    procedure SetAlignment(AValue: TAlignment);
    function IsAlignmentStored: Boolean;
    function GetDisplayFormat: string;
    procedure SetDisplayFormat(const AValue: string);
    function IsDisplayFormatStored: Boolean;
    procedure SetFieldName(const AValue: string);
    procedure ApplyDisplayFormat;
  protected
    function GetDisplayName: string; override;
    { Find the field in ADataSet (nil: none), push DisplayFormat to it when set, and give the
      title, width and alignment their field defaults where the user has not set them. }
    procedure LinkField(ADataSet: TDataSet);
    procedure ApplyFieldDefaults;
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(ASource: TPersistent); override;
    { The field this column shows; nil while the dataset is closed or has no such field. }
    property Field: TField read FField;
    { Made by the grid from the dataset's fields (no design columns); never streamed. }
    property IsAutomatic: Boolean read FAutomatic;
    property Grid: TTyCustomDBGrid read GetGrid;
  published
    property FieldName: string read FFieldName write SetFieldName;
    { The format a numeric or date-time field is shown with. Read: the column's own when it
      was set, the field's otherwise. }
    property DisplayFormat: string read GetDisplayFormat write SetDisplayFormat
      stored IsDisplayFormatStored;
    property Text: TCaption read GetTitle write SetTitle stored IsTitleStored;
    property Width: Integer read GetWidth write SetWidth stored IsWidthStored;
    property Alignment: TAlignment read GetAlignment write SetAlignment
      stored IsAlignmentStored;
  end;

  { The header's collection in a data-aware grid. Adding a design column drops the automatic
    ones (LCL's TDBGridColumns.Add does the same); removing the last design column brings them
    back while the dataset is open. }
  TTyDBGridColumns = class(TTyColumns)
  private
    FGrid: TTyCustomDBGrid;
    function GetItem(AIndex: Integer): TTyDBGridColumn;
    procedure SetItem(AIndex: Integer; AValue: TTyDBGridColumn);
  protected
    procedure Update(Item: TCollectionItem); override;
  public
    function Add: TTyDBGridColumn;
    function ColumnByFieldName(const AFieldName: string): TTyDBGridColumn;
    function ColumnFromField(AField: TField): TTyDBGridColumn;
    function HasAutomaticColumns: Boolean;
    function HasDesignColumns: Boolean;
    property Grid: TTyCustomDBGrid read FGrid;
    property Items[AIndex: Integer]: TTyDBGridColumn read GetItem write SetItem; default;
  end;

  TTyCustomDBGrid = class(TTyCustomStringGrid)
  private
    FDataLink: TTyDBGridDataLink;
    FDBOptions: TDBGridOptions;
    FExtraOptions: TDBGridExtraOptions;
    FLayoutLock: Integer;
    FAddingAutoColumns: Boolean;
    FUpdatingBuffer: Boolean;
    FSyncingRow: Boolean;
    { The record bar: the grid is pushing values into it (its OnChange is not the user's);
      UpdateScrollBars is asking whether it wants the bar (ContentHeightPx answers that);
      the bar's visibility is being laid out again; where the bar was last. }
    FSettingBar: Boolean;
    FMeasuringBars: Boolean;
    FLayingOutBars: Boolean;
    FBarPosition: Integer;
    { The text an editor reopens with after its field refused it (GetEditText answers it). }
    FHoldingText: Boolean;
    FHeldCol, FHeldRow: Integer;
    FHeldText: string;
    FCommittingForData: Boolean;
    { A gesture closed the editor itself before it moved the record (to tell a new record
      nobody typed into): a refused move still brings the editor back. }
    FEditorWasOpen: Boolean;
    { Moves DataOp has made (a MoveBy that went somewhere, a First, an Append, ...): a
      gesture compares it before and after to tell whether the record changed. }
    FMoveCount: Integer;
    FSelectedRows: TTyBookmarkList;
    { Which rows are selected, worked out once per paint (RowIsSelected). }
    FSelRowCache: array of Boolean;
    FSelCacheValid: Boolean;
    FUserCreateEditLink: TTyGridCreateEditLinkEvent;
    FControlLink: TTyGridEditLink;
    FOnFieldEditMask: TGetDbEditMaskEvent;
    FOnCellClick: TTyDBGridClickEvent;
    FOnTitleClick: TTyDBGridClickEvent;
    FOnColEnter: TNotifyEvent;
    FOnColExit: TNotifyEvent;
    FOnColumnMoved: TMovedEvent;
    FOnColumnSized: TNotifyEvent;
    FOnDrawColumnCell: TTyDBGridDrawColumnCellEvent;
    FOnDrawColumnTitle: TTyDBGridDrawColumnTitleEvent;
    FOnPrepareCanvas: TTyDBGridPrepareStyleEvent;
    FOnSelectEditor: TTyDBGridSelEditorEvent;
    FOnUserCheckboxState: TTyDBGridCheckboxStateEvent;
    FOnGetCellHint: TTyDBGridCellHintEvent;
    FOnEditButtonClick: TNotifyEvent;
    procedure SetOnGetCellHint(AValue: TTyDBGridCellHintEvent);
    { The string grid's own hint, cell edit-link and their LCL-shaped counterparts here. }
    procedure BaseCellHint(Sender: TObject; ACol, ARow: Integer; var AHint: string);
    procedure ProvideEditLink(Sender: TObject; ACol, ARow: Integer;
      var ALink: TTyGridEditLink);
    function GetDataSource: TDataSource;
    procedure SetDataSource(AValue: TDataSource);
    function GetColumns: TTyDBGridColumns;
    procedure SetColumns(AValue: TTyDBGridColumns);
    function IsColumnsStored: Boolean;
    procedure SetDBOptions(AValue: TDBGridOptions);
    procedure SetExtraOptions(AValue: TDBGridExtraOptions);
    { Push Options onto the string grid underneath. }
    procedure ApplyOptions;
    procedure AddAutomaticColumns;
    procedure RemoveAutomaticColumns;
    procedure LinkColumns;
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    { --- what the data link reports --- }
    procedure LinkActiveChanged; virtual;
    procedure LinkDataSetChanged; virtual;
    procedure LinkDataSetScrolled(ADistance: Integer); virtual;
    procedure LinkRecordChanged(AField: TField); virtual;
    procedure LinkEditingChanged; virtual;
    procedure LinkUpdateData; virtual;
    { The columns or the dataset's fields changed: drop or make the automatic columns, find
      every column's field again, and resize the record window. }
    procedure LayoutChanged; virtual;
    { A column of Columns came or went (TTyDBGridColumns.Update). }
    procedure ColumnsChanged;
    { The buffer holds as many records as the body has whole rows for; RowCount follows the
      records in it, Row the dataset's current one. }
    procedure UpdateBufferCount;
    { Row := DataLink.ActiveRecord. }
    procedure SyncCurrentRow;
    { How many whole rows the body has room for (at least one). }
    function RecordCapacity: Integer;
    { The field column ACol shows, nil for none. }
    function ColumnField(ACol: Integer): TField;
    { Does ACol show a boolean field as a check box (dgeCheckboxColumn)? }
    function IsCheckBoxColumn(ACol: Integer): Boolean;
    { What a cell of field AField shows, read on the current buffer record. }
    function FieldCellText(AField: TField): string; virtual;

    function GetStyleTypeKey: string; override;
    function ColumnClass: TTyGridColumnClass; override;
    function ColumnsClass: TTyColumnsClass; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    procedure Paint; override;
    procedure UpdateScrollBars; override;
    function GetCellText(ACol, ARow: Integer): string; override;
    function GetEditText(ACol, ARow: Integer): string; override;
    procedure SetEditText(ACol, ARow: Integer; const AText: string); override;
    function EditorKindFor(ACol, ARow: Integer): TTyGridEditorKind; override;
    { Plan D10: the footer does not total the record window -- a sum of the rows on screen is
      not a sum of the dataset, and walking a dataset of a million rows per paint is not an
      option. A column's footer value comes from OnColumnCalc. }
    procedure AccumulateCell(ACol, ADataRow: Integer; AKind: TTyGridAggregate;
      var AAcc: Double; var ACount: Integer; var AStarted: Boolean); override;

    { --- moving (plan Task 3) --- }
    { IsSequenced and not Filtered: the records can be counted and reached by RecNo. }
    function DataSetIsSequenced: Boolean;
    { The window's rows: what PgUp / PgDn and a page of the bar move by (LCL's
      VisibleRowCount). }
    function PageRecords: Integer;
    { The record bar's maximum position, page and position (see the unit comment). }
    procedure RecordBarParams(out AMax, APage, APosition: Integer);
    { Do the records call for a bar (the dataset does not fit the window)? }
    function WantsRecordBar: Boolean;
    { Give the bar its range and position, and lay the bars out again when it has to come or
      go. }
    procedure UpdateRecordBar;
    { While UpdateScrollBars measures: as tall as the records want (a bar or none), so the
      string grid places the bar and leaves room for it; otherwise the window's height. }
    function ContentHeightPx: Integer; override;
    procedure DoVScroll(APosition: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    function ChildKey(var Message: TLMKey): Boolean; override;
    procedure DoExit; override;
    { OnKeyDown (and the key handlers) for a key this grid handles itself instead of passing
      it to the string grid, as LCL's TDBGrid.KeyDown does. }
    procedure UserKeyDown(var Key: Word; Shift: TShiftState);
    { Do AOp to the dataset (ADelta: the distance, or the RecNo), the open editor's text
      written first. False when the editor's value was refused (the editor stays) or there is
      no dataset. An exception -- the dataset would not post the record being left -- keeps
      the editor on the cell it was on, and goes on. }
    function DataOp(AOp: TTyDBGridDataOp; ADelta: Integer = 0): Boolean;
    { Close the open editor, writing its text (TryEndEdit). False: refused, still open. }
    function CommitEditor: Boolean;
    { Open the editor on the current cell again, after the dataset refused what it held. }
    procedure ReopenEditor;
    { LCL's doVKDown / doVKUp: Down past the last record appends, a new record nobody typed
      into is cancelled. }
    procedure KeyDownRecord;
    procedure KeyUpRecord;

    { --- editing (plan Task 4) --- }
    { The grid as a whole may change the dataset: not ReadOnly, dgEditing, the link not
      ReadOnly, the dataset open and modifiable. }
    function GridCanModify: Boolean;
    { No editing in this column: see the unit comment's list. }
    function ColumnIsReadOnly(ACol: Integer): Boolean;
    { A record inserted and not changed since (LCL's InsertCancelable). }
    function InsertCancelable: Boolean;
    { Before an editor opens on the current record: the dataset goes into dsEdit (refused:
      no editor), and a lookup column's pick list is filled. }
    function CanEditCell(ACol, ARow: Integer): Boolean; override;
    function EditMaskFor(ACol: Integer): string; override;
    function MaxEditLengthFor(ACol, ARow: Integer): Integer; override;
    { Write AText, the cell's new text, into AField: AsBoolean for a boolean check box (the
      check box vocabulary), AsString for a memo and another check box column, Text
      otherwise; a lookup field then writes its key fields from the LookupDataSet. }
    procedure WriteFieldText(ACol: Integer; AField: TField; const AText: string); virtual;
    procedure WriteLookupKeys(AField: TField; const AText: string);
    procedure FillLookupPickList(ACol: Integer; AField: TField);
    { Asked before Ctrl+Del deletes, when dgConfirmDelete is set: True deletes. A themed
      TyMessageDlg with OK and Cancel, as LCL asks with its MessageDlg. }
    function ConfirmDeleteRecord: Boolean; virtual;
    { The check box toggle writes the field: none while the cell is read-only or the dataset
      will not edit (then no OnCellEdited, no OnCheckBoxChange either). }
    function CanToggleCellCheck(ACol, ARow: Integer): Boolean; override;
    { Does ACol show a check box (a boolean field under dgeCheckboxColumn, or a column whose
      EditorKind is gekCheckBox)? }
    function ColumnShowsCheckBox(ACol: Integer): Boolean;
    { A check box cell's text under OnUserCheckboxState (the current buffer record). }
    function UserCheckBoxText(ACol: Integer; AField: TField): string;

    { --- the indicator, multiselect, title click, events (plan Task 5) --- }
    { What the indicator shows on data row ARow (plan D6): the current record's state -- a
      triangle browsing, a bar editing, a bar in the insert colour inserting -- and a dot on
      the other selected rows under dgMultiselect. }
    function IndicatorFor(ARow: Integer): TTyDBGridIndicator;
    procedure RenderChrome(P: TTyPainter; const M: TTyGridMetrics); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); override;
    procedure RenderHeaderSections(P: TTyPainter; const M: TTyGridMetrics;
      AHeaderH: Integer); override;
    function DoDrawCell(P: TTyPainter; ACol, ARow: Integer): Boolean; override;
    procedure DoGetCellStyle(ACol, ARow: Integer;
      var AAppearance: TTyGridCellAppearance); override;
    { A selected row (dgMultiselect) is drawn as a selected cell is. }
    function CellStates(ACol, ARow: Integer): TTyStateSet; override;
    { The LCL draw state of a body cell. }
    function DrawStateOf(ACol, ARow: Integer): TGridDrawState;
    { Is data row ARow one of SelectedRows? }
    function RowIsSelected(ARow: Integer): Boolean;
    { LCL's ClearSelection: under dgMultiselect without dgPersistentMultiSelect, forget the
      selection; ASelectCurrent then selects the current record. }
    procedure ClearSelection(ASelectCurrent: Boolean);
    procedure ToggleSelectedRow;
    { Shift+Up / Shift+Down (LCL's SelectNext): the record moved to is selected; the one
      left is deselected when both were selected (the run shrinks), selected otherwise. }
    procedure ExtendSelection(APrevSelected, ANewSelected, ADown: Boolean);
    { Tab past the last field of the window's last row goes on to the next record (appending
      at the end, as Down does), Shift+Tab before the first field of its first row back to
      the record before. False: nothing moved, the key is the string grid's. }
    function WrapTab(ABackward: Boolean): Boolean;
    function ShowsFilterButton(ACol: Integer): Boolean; override;
    procedure InvokeEllipsis(ACol, ARow: Integer); override;
    procedure CursorMoved(AOldCol, AOldRow: Integer); override;
    procedure HeaderSectionClicked(ACol: Integer); override;
    procedure ColumnSized(ACol: Integer); override;
    procedure ColumnMoved(AFromPos, AToPos: Integer); override;
    { OnMouseWheel / OnMouseWheelUp / OnMouseWheelDown, LCL's TControl.DoMouseWheel order,
      for the data path, which never reaches TControl.DoMouseWheel. }
    function FireWheelEvents(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean;
    { The column ACol as this grid's column (nil when out of range). }
    function DBColumn(ACol: Integer): TTyDBGridColumn;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The display order is the buffer order (see the unit comment). }
    function DisplayToData(APos: Integer): Integer; override;
    function DataToDisplay(ARow: Integer): Integer; override;
    function DisplayRowCount: Integer; override;
    { The width (logical px) a column of AField gets by default, titled ATitle: DisplayWidth
      characters of the cell font ('MX' halved, as LCL measures), at least the title in the
      header font while there are titles, plus the cells' padding. A field with no
      DisplayWidth, or none at all, gets DefaultColWidth. }
    function DefaultFieldWidth(AField: TField; const ATitle: string): Integer;
    { A row move is a record move: DataLink.MoveBy(ARow - Row), then the column. The row
      follows the dataset (DataSetScrolled), never the other way. }
    procedure MoveCursor(ACol, ARow: Integer); override;
    property DataLink: TTyDBGridDataLink read FDataLink;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property Columns: TTyDBGridColumns read GetColumns write SetColumns stored IsColumnsStored;
    property Options: TDBGridOptions read FDBOptions write SetDBOptions
      default TyDBGridDefaultOptions;
    property OptionsExtra: TDBGridExtraOptions read FExtraOptions write SetExtraOptions
      default TyDBGridDefaultExtraOptions;
    { The rows the user selected (dgMultiselect). }
    property SelectedRows: TTyBookmarkList read FSelectedRows;
    { The edit mask of a cell of Field, starting from Field.EditMask (LCL's). }
    property OnFieldEditMask: TGetDbEditMaskEvent read FOnFieldEditMask write FOnFieldEditMask;
    { LCL's events (plan D9). OnCellClick: a left click on a body cell, the record moved
      there. OnTitleClick: a click on a title -- the application sorts the dataset; the grid
      does not sort. OnColExit / OnColEnter: the current column is about to change / has
      changed. OnColumnMoved: the user dragged a column to another place (display
      positions). OnColumnSized: the user let go of a column divider. OnSelectEditor: an
      editor is about to open; Editor comes in nil (the grid's own), a control put there edits
      the cell instead -- given the field's text, read back when the cell is left.
      OnUserCheckboxState: the state a check box cell shows. OnGetCellHint: the hint of the
      cell under the mouse, the dataset on its record. OnEditButtonClick: the ellipsis button
      of a gekEllipsis column. OnDrawColumnCell / OnDrawColumnTitle / OnPrepareCanvas: see
      their types. While a cell event runs, the data link's active record is that cell's row,
      so Column.Field reads the row's value. }
    property OnCellClick: TTyDBGridClickEvent read FOnCellClick write FOnCellClick;
    property OnColEnter: TNotifyEvent read FOnColEnter write FOnColEnter;
    property OnColExit: TNotifyEvent read FOnColExit write FOnColExit;
    property OnColumnMoved: TMovedEvent read FOnColumnMoved write FOnColumnMoved;
    property OnColumnSized: TNotifyEvent read FOnColumnSized write FOnColumnSized;
    property OnDrawColumnCell: TTyDBGridDrawColumnCellEvent
      read FOnDrawColumnCell write FOnDrawColumnCell;
    property OnDrawColumnTitle: TTyDBGridDrawColumnTitleEvent
      read FOnDrawColumnTitle write FOnDrawColumnTitle;
    property OnEditButtonClick: TNotifyEvent read FOnEditButtonClick write FOnEditButtonClick;
    property OnGetCellHint: TTyDBGridCellHintEvent read FOnGetCellHint write SetOnGetCellHint;
    property OnPrepareCanvas: TTyDBGridPrepareStyleEvent
      read FOnPrepareCanvas write FOnPrepareCanvas;
    property OnSelectEditor: TTyDBGridSelEditorEvent read FOnSelectEditor write FOnSelectEditor;
    property OnTitleClick: TTyDBGridClickEvent read FOnTitleClick write FOnTitleClick;
    property OnUserCheckboxState: TTyDBGridCheckboxStateEvent
      read FOnUserCheckboxState write FOnUserCheckboxState;
    { The string grid's host edit-link event, asked first; OnSelectEditor after it. }
    property OnCreateEditLink: TTyGridCreateEditLinkEvent
      read FUserCreateEditLink write FUserCreateEditLink;
  end;

  { TTyDBGrid publishes TTyCustomDBGrid's properties; everything lives in TTyCustomDBGrid. }
  TTyDBGrid = class(TTyCustomDBGrid)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Align;
    property Anchors;
    property DataSource;
    property Columns;
    property Options;
    property OptionsExtra;
    property ReadOnly;
    property DefaultRowHeight;
    property DefaultColWidth;
    property AutoFillColumns;
    property ScrollBars;
    property ScrollBarAutoHide;
    property FixedCols;
    property AlternateRows;
    property GridLineWidth;
    property OnGetCellStyle;
    property OnGetCellBorder;
    property OnGetHeaderStyle;
    property OnColumnSizing;
    property OnEndColumnSize;
    property OnColumnMove;
    property OnClickCell;
    property OnDblClickCell;
    property OnRightClickCell;
    property OnHeaderClick;
    property OnHeaderRightClick;
    property OnTopLeftChanged;
    property OnCellClick;
    property OnColEnter;
    property OnColExit;
    property OnColumnMoved;
    property OnColumnSized;
    property OnDrawColumnCell;
    property OnDrawColumnTitle;
    property OnEditButtonClick;
    property OnFieldEditMask;
    property OnGetCellHint;
    property OnPrepareCanvas;
    property OnSelectEditor;
    property OnTitleClick;
    property OnUserCheckboxState;
  end;

implementation

uses
  Variants, Dialogs, BGRABitmap, tyControls.StyleModel, tyControls.Dialogs,
  tyControls.ScrollBar,
  tyControls.DB.Common, tyControls.DB.StrConsts;

type
  { TControl keeps Text protected; the editor a handler gave OnSelectEditor is read and
    written through it. }
  TTyDBGridControlText = class(TWinControl);

  { The control OnSelectEditor handed over, as the string grid's host edit link: it is
    placed on the cell, given the field's text, and read when the cell is left. The grid
    shows and hides it; the application owns it. }
  TTyDBGridControlLink = class(TTyGridEditLink)
  public
    Control: TWinControl;
    function CreateEditor(AParent: TWinControl; ACol, ARow: Integer): TWinControl; override;
    procedure SetBounds(const ARect: TRect); override;
    function GetValue: string; override;
    procedure SetValue(const AValue: string); override;
    procedure FocusEditor; override;
    procedure ReleaseEditor; override;
  end;

function TTyDBGridControlLink.CreateEditor(AParent: TWinControl; ACol,
  ARow: Integer): TWinControl;
begin
  Result := Control;
  if Control = nil then Exit;
  Control.Parent := AParent;
  Control.Visible := True;
end;

procedure TTyDBGridControlLink.SetBounds(const ARect: TRect);
begin
  if Control <> nil then Control.BoundsRect := ARect;
end;

function TTyDBGridControlLink.GetValue: string;
begin
  if Control <> nil then
    Result := TTyDBGridControlText(Control).Text
  else
    Result := '';
end;

procedure TTyDBGridControlLink.SetValue(const AValue: string);
begin
  if Control <> nil then TTyDBGridControlText(Control).Text := AValue;
end;

procedure TTyDBGridControlLink.FocusEditor;
begin
  if (Control <> nil) and Control.HandleAllocated and Control.CanFocus then Control.SetFocus;
end;

procedure TTyDBGridControlLink.ReleaseEditor;
begin
  if Control <> nil then Control.Visible := False;
  Control := nil;
end;

{ ---- the marks the indicator draws when the theme gives no glyph ---------------------- }

{ The mark AKind in the square ABox (device px) in AColor; AMirror turns it round for a
  right-to-left grid (the triangle points the way the rows read). The stroke is a seventh of
  the box, so the mark keeps its weight at every DPI. }
procedure DrawIndicatorMark(P: TTyPainter; const ABox: TRect; AKind: TTyDBGridIndicator;
  AColor: TTyColor; AMirror: Boolean);
var
  side, stroke: Double;

  function X(AX: Double): Double;
  begin
    if AMirror then AX := 1 - AX;
    Result := ABox.Left + AX * side;
  end;

  function Y(AY: Double): Double;
  begin
    Result := ABox.Top + AY * side;
  end;

  procedure Line(AX0, AY0, AX1, AY1: Double);
  begin
    P.BeginPath;
    P.MoveTo(X(AX0), Y(AY0));
    P.LineTo(X(AX1), Y(AY1));
    P.StrokePath(AColor, stroke);
  end;

  { The text cursor's I-beam: a bar with a serif at each end. }
  procedure IBeam;
  begin
    Line(0.5, 0.14, 0.5, 0.86);
    Line(0.3, 0.14, 0.7, 0.14);
    Line(0.3, 0.86, 0.7, 0.86);
  end;

begin
  side := ABox.Right - ABox.Left;
  if side <= 0 then Exit;
  { StrokePath takes logical px and scales them itself. }
  stroke := P.Unscale(Round(side)) / 7;
  if stroke <= 0 then stroke := side / 7;
  P.SaveState;
  try
    P.SetLineCap(tlcRound);
    P.SetLineJoin(tljRound);
    case AKind of
      dgiBrowse:
        begin
          P.BeginPath;
          P.MoveTo(X(0.28), Y(0.18));
          P.LineTo(X(0.28), Y(0.82));
          P.LineTo(X(0.78), Y(0.5));
          P.ClosePath;
          P.FillPath(AColor);
        end;
      dgiEdit, dgiInsert:
        IBeam;
      dgiSelected:
        begin
          P.BeginPath;
          P.ArcTo(ABox.Left + 0.5 * side, ABox.Top + 0.5 * side, 0.2 * side, 0, 2 * Pi);
          P.ClosePath;
          P.FillPath(AColor);
        end;
    end;
  finally
    P.RestoreState;
  end;
end;

{ ================================================================== TTyDBGridDataLink == }

constructor TTyDBGridDataLink.Create(AGrid: TTyCustomDBGrid);
begin
  inherited Create;
  FGrid := AGrid;
  VisualControl := True;
end;

procedure TTyDBGridDataLink.ActiveChanged;
begin
  if FGrid <> nil then FGrid.LinkActiveChanged;
end;

procedure TTyDBGridDataLink.DataSetChanged;
begin
  if FGrid <> nil then FGrid.LinkDataSetChanged;
end;

procedure TTyDBGridDataLink.DataSetScrolled(Distance: Integer);
begin
  if FGrid <> nil then FGrid.LinkDataSetScrolled(Distance);
end;

procedure TTyDBGridDataLink.EditingChanged;
begin
  if FGrid <> nil then FGrid.LinkEditingChanged;
end;

procedure TTyDBGridDataLink.LayoutChanged;
begin
  if FGrid <> nil then FGrid.LayoutChanged;
end;

procedure TTyDBGridDataLink.RecordChanged(Field: TField);
begin
  if FGrid <> nil then FGrid.LinkRecordChanged(Field);
end;

procedure TTyDBGridDataLink.UpdateData;
begin
  if FGrid <> nil then FGrid.LinkUpdateData;
end;

function TTyDBGridDataLink.MoveBy(Distance: Integer): Integer;
begin
  Result := inherited MoveBy(Distance);
end;

{ ==================================================================== TTyDBGridColumn == }

constructor TTyDBGridColumn.Create(ACollection: TCollection);
var
  g: TTyCustomDBGrid;
begin
  inherited Create(ACollection);
  { Before any field default is given, the "default" a value is compared with is the one the
    column was born with: a value still equal to it has not been set. }
  FDefTitle := inherited Text;
  FDefWidth := inherited Width;
  FDefAlignment := inherited Alignment;
  g := GetGrid;
  FAutomatic := (g <> nil) and g.FAddingAutoColumns;
end;

function TTyDBGridColumn.GetGrid: TTyCustomDBGrid;
begin
  if Collection is TTyDBGridColumns then
    Result := TTyDBGridColumns(Collection).FGrid
  else
    Result := nil;
end;

procedure TTyDBGridColumn.Assign(ASource: TPersistent);
var
  src: TTyDBGridColumn;
begin
  inherited Assign(ASource);
  if ASource is TTyDBGridColumn then
  begin
    src := TTyDBGridColumn(ASource);
    FFieldName := src.FFieldName;
    FDisplayFormat := src.FDisplayFormat;
    FDisplayFormatSet := src.FDisplayFormatSet;
    FTitleSet := src.FTitleSet;
    FWidthSet := src.FWidthSet;
    FAlignmentSet := src.FAlignmentSet;
    FDefTitle := src.FDefTitle;
    FDefWidth := src.FDefWidth;
    FDefAlignment := src.FDefAlignment;
    if Grid <> nil then Grid.ColumnsChanged;
  end;
end;

function TTyDBGridColumn.GetDisplayName: string;
begin
  if FFieldName <> '' then
    Result := FFieldName
  else
    Result := inherited GetDisplayName;
end;

function TTyDBGridColumn.GetTitle: TCaption;
begin
  Result := inherited Text;
end;

procedure TTyDBGridColumn.SetTitle(const AValue: TCaption);
begin
  FTitleSet := True;
  inherited Text := AValue;
end;

function TTyDBGridColumn.IsTitleStored: Boolean;
begin
  Result := FTitleSet or (inherited Text <> FDefTitle);
end;

function TTyDBGridColumn.GetWidth: Integer;
begin
  Result := inherited Width;
end;

procedure TTyDBGridColumn.SetWidth(AValue: Integer);
begin
  FWidthSet := True;
  inherited Width := AValue;
end;

function TTyDBGridColumn.IsWidthStored: Boolean;
begin
  Result := FWidthSet or (inherited Width <> FDefWidth);
end;

function TTyDBGridColumn.GetAlignment: TAlignment;
begin
  Result := inherited Alignment;
end;

procedure TTyDBGridColumn.SetAlignment(AValue: TAlignment);
begin
  FAlignmentSet := True;
  inherited Alignment := AValue;
end;

function TTyDBGridColumn.IsAlignmentStored: Boolean;
begin
  Result := FAlignmentSet or (inherited Alignment <> FDefAlignment);
end;

function TTyDBGridColumn.GetDisplayFormat: string;
begin
  if FDisplayFormatSet then
    Result := FDisplayFormat
  else if FField is TNumericField then
    Result := TNumericField(FField).DisplayFormat
  else if FField is TDateTimeField then
    Result := TDateTimeField(FField).DisplayFormat
  else
    Result := '';
end;

procedure TTyDBGridColumn.SetDisplayFormat(const AValue: string);
begin
  if FDisplayFormatSet and (FDisplayFormat = AValue) then Exit;
  FDisplayFormat := AValue;
  FDisplayFormatSet := True;
  ApplyDisplayFormat;
  if Grid <> nil then Grid.Invalidate;
end;

function TTyDBGridColumn.IsDisplayFormatStored: Boolean;
begin
  Result := FDisplayFormatSet;
end;

procedure TTyDBGridColumn.ApplyDisplayFormat;
begin
  if (FField = nil) or not FDisplayFormatSet then Exit;
  if FField is TNumericField then
    TNumericField(FField).DisplayFormat := FDisplayFormat
  else if FField is TDateTimeField then
    TDateTimeField(FField).DisplayFormat := FDisplayFormat;
end;

procedure TTyDBGridColumn.SetFieldName(const AValue: string);
begin
  if FFieldName = AValue then Exit;
  FFieldName := AValue;
  if Grid <> nil then Grid.LayoutChanged;
end;

procedure TTyDBGridColumn.LinkField(ADataSet: TDataSet);
begin
  if (ADataSet <> nil) and (FFieldName <> '') then
    FField := ADataSet.FindField(FFieldName)
  else
    FField := nil;
  ApplyDisplayFormat;
  ApplyFieldDefaults;
end;

procedure TTyDBGridColumn.ApplyFieldDefaults;
var
  g: TTyCustomDBGrid;
  defTitle: TCaption;
  defWidth: Integer;
  defAlign: TAlignment;
begin
  g := Grid;
  if g = nil then Exit;
  { The title first: the default width makes room for it. }
  if FFieldName = '' then
    defTitle := ''
  else if FField <> nil then
    defTitle := FField.DisplayName
  else
    defTitle := FFieldName;
  if not FTitleSet and (inherited Text = FDefTitle) then
  begin
    inherited Text := defTitle;
    FDefTitle := inherited Text;
  end
  else
    FDefTitle := defTitle;

  defWidth := g.DefaultFieldWidth(FField, inherited Text);
  if not FWidthSet and (inherited Width = FDefWidth) then
  begin
    inherited Width := defWidth;
    FDefWidth := inherited Width;   // after the column's own MinWidth / MaxWidth
  end
  else
    FDefWidth := defWidth;

  if (FField <> nil) and (FField.DataType = ftBoolean)
    and (dgeCheckboxColumn in g.OptionsExtra) then
    defAlign := taCenter
  else if FField <> nil then
    defAlign := FField.Alignment
  else
    defAlign := taLeftJustify;
  if not FAlignmentSet and (inherited Alignment = FDefAlignment) then
    inherited Alignment := defAlign;
  FDefAlignment := defAlign;
end;

{ =================================================================== TTyDBGridColumns == }

function TTyDBGridColumns.GetItem(AIndex: Integer): TTyDBGridColumn;
begin
  Result := TTyDBGridColumn(inherited Items[AIndex]);
end;

procedure TTyDBGridColumns.SetItem(AIndex: Integer; AValue: TTyDBGridColumn);
begin
  Items[AIndex].Assign(AValue);
end;

procedure TTyDBGridColumns.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if FGrid <> nil then FGrid.ColumnsChanged;
end;

function TTyDBGridColumns.Add: TTyDBGridColumn;
begin
  Result := TTyDBGridColumn(inherited Add);
end;

function TTyDBGridColumns.ColumnByFieldName(const AFieldName: string): TTyDBGridColumn;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
    if CompareText(Items[i].FieldName, AFieldName) = 0 then Exit(Items[i]);
  Result := nil;
end;

function TTyDBGridColumns.ColumnFromField(AField: TField): TTyDBGridColumn;
var
  i: Integer;
begin
  if AField <> nil then
    for i := 0 to Count - 1 do
      if Items[i].Field = AField then Exit(Items[i]);
  Result := nil;
end;

function TTyDBGridColumns.HasAutomaticColumns: Boolean;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
    if Items[i].IsAutomatic then Exit(True);
  Result := False;
end;

function TTyDBGridColumns.HasDesignColumns: Boolean;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
    if not Items[i].IsAutomatic then Exit(True);
  Result := False;
end;

{ ==================================================================== TTyBookmarkList == }

constructor TTyBookmarkList.Create(AGrid: TTyCustomDBGrid);
begin
  inherited Create;
  FGrid := AGrid;
end;

destructor TTyBookmarkList.Destroy;
begin
  Clear;
  inherited Destroy;
end;

function TTyBookmarkList.LinkDataSet: TDataSet;
begin
  Result := nil;
  if (FGrid <> nil) and (FGrid.DataLink <> nil) and FGrid.DataLink.Active then
    Result := FGrid.DataLink.DataSet;
end;

procedure TTyBookmarkList.FreeOne(ABookmark: TBookmark);
begin
  { The dataset made it and is told it goes (TDataSet.FreeBookmark; a bookmark is a managed
    array in FPC 3.2, released with the list's slot). }
  if FDataSet <> nil then FDataSet.FreeBookmark(ABookmark);
end;

procedure TTyBookmarkList.Changed;
begin
  if FGrid <> nil then FGrid.Invalidate;
end;

function TTyBookmarkList.GetCount: Integer;
begin
  Result := Length(FList);
end;

function TTyBookmarkList.GetItem(AIndex: Integer): TBookmark;
begin
  if (AIndex < 0) or (AIndex >= Length(FList)) then
    raise EListError.CreateFmt('TTyBookmarkList: index %d out of bounds (count %d)',
      [AIndex, Length(FList)]);
  Result := FList[AIndex];
end;

procedure TTyBookmarkList.Clear;
var
  i: Integer;
begin
  if Length(FList) = 0 then Exit;
  for i := 0 to High(FList) do
    FreeOne(FList[i]);
  SetLength(FList, 0);
  FDataSet := nil;
  Changed;
end;

function TTyBookmarkList.IndexOf(const ABookmark: TBookmark): Integer;
var
  ds: TDataSet;
  i: Integer;
begin
  Result := -1;
  ds := LinkDataSet;
  if (ds = nil) or (ABookmark = nil) or (ds <> FDataSet) then Exit;
  for i := 0 to High(FList) do
    if ds.CompareBookmarks(FList[i], ABookmark) = 0 then Exit(i);
end;

function TTyBookmarkList.GetCurrentRowSelected: Boolean;
var
  ds: TDataSet;
  bm: TBookmark;
begin
  Result := False;
  ds := LinkDataSet;
  if (ds = nil) or (Length(FList) = 0) or (ds.State in [dsInsert, dsSetKey]) then Exit;
  bm := ds.GetBookmark;
  try
    Result := IndexOf(bm) >= 0;
  finally
    ds.FreeBookmark(bm);
  end;
end;

procedure TTyBookmarkList.SetCurrentRowSelected(AValue: Boolean);
var
  ds: TDataSet;
  bm: TBookmark;
  i, n: Integer;
begin
  ds := LinkDataSet;
  { A record not posted yet has no place to mark (LCL's: nothing selected while inserting). }
  if (ds = nil) or ds.IsEmpty or (ds.State in [dsInsert, dsSetKey]) then Exit;
  if (FDataSet <> nil) and (FDataSet <> ds) then Clear;
  bm := ds.GetBookmark;
  if bm = nil then Exit;
  FDataSet := ds;
  i := IndexOf(bm);
  if AValue = (i >= 0) then
  begin
    ds.FreeBookmark(bm);
    Exit;
  end;
  if AValue then
  begin
    n := Length(FList);
    SetLength(FList, n + 1);
    FList[n] := bm;
  end
  else
  begin
    ds.FreeBookmark(bm);
    FreeOne(FList[i]);
    { Element by element: the bookmarks are managed, Move would skip their reference counts. }
    for n := i to High(FList) - 1 do
      FList[n] := FList[n + 1];
    SetLength(FList, Length(FList) - 1);
    if Length(FList) = 0 then FDataSet := nil;
  end;
  Changed;
end;

procedure TTyBookmarkList.Delete;
var
  ds: TDataSet;
  i: Integer;
begin
  ds := LinkDataSet;
  if (ds = nil) or (Length(FList) = 0) then Exit;
  ds.DisableControls;
  try
    for i := 0 to High(FList) do
      if ds.BookmarkValid(FList[i]) then
      begin
        ds.GotoBookmark(FList[i]);
        ds.Delete;
      end;
  finally
    Clear;
    ds.EnableControls;
  end;
end;

function TTyBookmarkList.Refresh: Boolean;
var
  ds: TDataSet;
  i, n: Integer;
begin
  Result := False;
  ds := LinkDataSet;
  if ds = nil then Exit;
  n := 0;
  for i := 0 to High(FList) do
    if ds.BookmarkValid(FList[i]) then
    begin
      FList[n] := FList[i];
      Inc(n);
    end
    else
    begin
      FreeOne(FList[i]);
      Result := True;
    end;
  SetLength(FList, n);
  if n = 0 then FDataSet := nil;
  if Result then Changed;
end;

{ ==================================================================== TTyCustomDBGrid == }

constructor TTyCustomDBGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TTyDBGridColumns(Header.Columns).FGrid := Self;
  FDataLink := TTyDBGridDataLink.Create(Self);
  FDBOptions := TyDBGridDefaultOptions;
  FExtraOptions := TyDBGridDefaultExtraOptions;
  { The values are the dataset's: nothing to undo in a store this grid does not use. }
  UndoLimit := 0;
  { A header click is the application's to sort the dataset with, not the grid's. }
  Header.Options := Header.Options - [hoHeaderClickAutoSort];
  IndicatorWidth := TyDBGridIndicatorWidth;
  FSelectedRows := TTyBookmarkList.Create(Self);
  FControlLink := TTyDBGridControlLink.Create;
  { The string grid asks its host edit-link event before every editor; this grid asks the
    application's (OnCreateEditLink here) and then OnSelectEditor. }
  inherited OnCreateEditLink := @ProvideEditLink;
  ApplyOptions;
end;

destructor TTyCustomDBGrid.Destroy;
begin
  { The bookmarks go back to the dataset while it is still there. The link next: freeing it
    unhooks the data source without another event. The columns are told the grid is going,
    so the header freeing them reaches nothing of ours. }
  if FSelectedRows <> nil then FSelectedRows.Clear;
  FreeAndNil(FDataLink);
  FreeAndNil(FSelectedRows);
  if Header <> nil then TTyDBGridColumns(Header.Columns).FGrid := nil;
  inherited Destroy;
  { After the string grid, which releases an editor still open through it. }
  FreeAndNil(FControlLink);
end;

function TTyCustomDBGrid.GetStyleTypeKey: string;
begin
  Result := 'TyDBGrid';
end;

function TTyCustomDBGrid.ColumnClass: TTyGridColumnClass;
begin
  Result := TTyDBGridColumn;
end;

function TTyCustomDBGrid.ColumnsClass: TTyColumnsClass;
begin
  Result := TTyDBGridColumns;
end;

function TTyCustomDBGrid.GetDataSource: TDataSource;
begin
  if FDataLink <> nil then
    Result := FDataLink.DataSource
  else
    Result := nil;
end;

procedure TTyCustomDBGrid.SetDataSource(AValue: TDataSource);
begin
  if AValue = DataSource then Exit;
  if FSelectedRows <> nil then FSelectedRows.Clear;
  ChangeDataSource(Self, FDataLink, AValue);
  LayoutChanged;
end;

function TTyCustomDBGrid.GetColumns: TTyDBGridColumns;
begin
  Result := TTyDBGridColumns(Header.Columns);
end;

procedure TTyCustomDBGrid.SetColumns(AValue: TTyDBGridColumns);
begin
  Header.Columns.Assign(AValue);
end;

function TTyCustomDBGrid.IsColumnsStored: Boolean;
begin
  Result := Columns.HasDesignColumns;
end;

procedure TTyCustomDBGrid.SetDBOptions(AValue: TDBGridOptions);
begin
  { LCL: a row-select grid neither edits nor highlights a row of its own. }
  if dgRowSelect in AValue then
    AValue := AValue - [dgEditing, dgAlwaysShowEditor, dgRowHighlight];
  if FDBOptions = AValue then Exit;
  FDBOptions := AValue;
  { The selection belongs to dgMultiselect. }
  if not (dgMultiselect in FDBOptions) and (FSelectedRows <> nil) then FSelectedRows.Clear;
  ApplyOptions;
  { Titles on or off change the body's height, and dgDisplayMemoText the text. }
  UpdateBufferCount;
  Invalidate;
end;

procedure TTyCustomDBGrid.SetExtraOptions(AValue: TDBGridExtraOptions);
begin
  if FExtraOptions = AValue then Exit;
  FExtraOptions := AValue;
  { dgeAutoColumns makes or drops the automatic columns; dgeCheckboxColumn changes a boolean
    column's look and its default alignment. }
  LayoutChanged;
  Invalidate;
end;

procedure TTyCustomDBGrid.ApplyOptions;
var
  o: TTyGridOptions;

  procedure Put(AOption: TTyGridOption; AOn: Boolean);
  begin
    if AOn then Include(o, AOption) else Exclude(o, AOption);
  end;

begin
  o := inherited Options;
  Put(goHorzLine, dgRowLines in FDBOptions);
  Put(goVertLine, dgColLines in FDBOptions);
  Put(goColSizing, dgColumnResize in FDBOptions);
  Put(goColMoving, dgColumnMove in FDBOptions);
  Put(goRowSelect, dgRowSelect in FDBOptions);
  Put(goTabs, dgTabs in FDBOptions);
  Put(goHeaderHotTracking, dgHeaderHotTracking in FDBOptions);
  Put(goHeaderPushedLook, dgHeaderPushedLook in FDBOptions);
  Put(goCellHints, dgCellHints in FDBOptions);
  Put(goTruncCellHints, dgTruncCellHints in FDBOptions);
  Put(goCellEllipsis, dgCellEllipsis in FDBOptions);
  Put(goRowHighlight, dgRowHighlight in FDBOptions);
  Put(goThumbTracking, dgThumbTracking in FDBOptions);
  Put(goDblClickAutoSize, dgDblClickAutoSize in FDBOptions);
  { What the string grid does to its own rows has no meaning on a window of records: a range
    of cells across it, a row dragged to another height or another place. goEditing is left
    as it is -- it is the string grid's ReadOnly, which this grid publishes as its own. }
  Exclude(o, goRangeSelect);
  Exclude(o, goRowSizing);
  Exclude(o, goRowMoving);
  inherited Options := o;
  ShowIndicator := dgIndicator in FDBOptions;
  if dgTitles in FDBOptions then
    Header.Options := Header.Options + [hoVisible]
  else
    Header.Options := Header.Options - [hoVisible];
  HideSelectionWhenInactive := not (dgAlwaysShowSelection in FDBOptions);
end;

procedure TTyCustomDBGrid.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

procedure TTyCustomDBGrid.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBGrid.Loaded;
begin
  inherited Loaded;
  LayoutChanged;
end;

{ ---- the columns -------------------------------------------------------------------- }

procedure TTyCustomDBGrid.ColumnsChanged;
begin
  if FLayoutLock = 0 then LayoutChanged;
end;

procedure TTyCustomDBGrid.AddAutomaticColumns;
var
  ds: TDataSet;
  f: TField;
  c: TTyDBGridColumn;
  i: Integer;
begin
  { LCL makes none in the designer: a column there would be the user's to edit, and an
    automatic one is never saved. }
  if (csDesigning in ComponentState) or (FDataLink = nil) or not FDataLink.Active
    or not (dgeAutoColumns in FExtraOptions) then Exit;
  ds := FDataLink.DataSet;
  Columns.BeginUpdate;
  FAddingAutoColumns := True;
  try
    for i := 0 to ds.FieldCount - 1 do
    begin
      f := ds.Fields[i];
      c := Columns.Add;
      c.FFieldName := f.FieldName;
      c.LinkField(ds);
      c.Visible := f.Visible;
      c.ReadOnly := f.ReadOnly;
    end;
  finally
    FAddingAutoColumns := False;
    Columns.EndUpdate;
  end;
end;

procedure TTyCustomDBGrid.RemoveAutomaticColumns;
var
  i: Integer;
begin
  if not Columns.HasAutomaticColumns then Exit;
  Columns.BeginUpdate;
  try
    for i := Columns.Count - 1 downto 0 do
      if Columns[i].IsAutomatic then Columns.Delete(i);
  finally
    Columns.EndUpdate;
  end;
end;

procedure TTyCustomDBGrid.LinkColumns;
var
  ds: TDataSet;
  i: Integer;
begin
  if (FDataLink <> nil) and FDataLink.Active then ds := FDataLink.DataSet else ds := nil;
  for i := 0 to Columns.Count - 1 do
    Columns[i].LinkField(ds);
end;

procedure TTyCustomDBGrid.LayoutChanged;
begin
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  if (FDataLink = nil) or (FLayoutLock > 0) then Exit;
  Inc(FLayoutLock);
  try
    if Columns.HasDesignColumns
      or not FDataLink.Active or not (dgeAutoColumns in FExtraOptions) then
      RemoveAutomaticColumns
    else if Columns.Count = 0 then
      AddAutomaticColumns;
    LinkColumns;
  finally
    Dec(FLayoutLock);
  end;
  UpdateBufferCount;
  Invalidate;
end;

function TTyCustomDBGrid.ColumnField(ACol: Integer): TField;
begin
  Result := nil;
  if (FDataLink = nil) or not FDataLink.Active then Exit;
  if (ACol < 0) or (ACol >= Header.Columns.Count) then Exit;
  if Header.Columns.Items[ACol] is TTyDBGridColumn then
    Result := TTyDBGridColumn(Header.Columns.Items[ACol]).Field;
end;

function TTyCustomDBGrid.IsCheckBoxColumn(ACol: Integer): Boolean;
var
  f: TField;
begin
  f := ColumnField(ACol);
  Result := (f <> nil) and (f.DataType = ftBoolean) and (dgeCheckboxColumn in FExtraOptions);
end;

function TTyCustomDBGrid.DefaultFieldWidth(AField: TField; const ATitle: string): Integer;
var
  bmp: TBGRABitmap;
  cellSty, headSty: TTyStyleSet;
  charW, n, titleW: Integer;
begin
  if (AField = nil) or (AField.DisplayWidth <= 0) then Exit(DefaultColWidth);
  { A 1x1 bitmap only to measure with, at 96 PPI: the answer is in logical px. }
  bmp := TBGRABitmap.Create(1, 1);
  try
    cellSty := ActiveController.Model.ResolveStyle('TyGridCell', StyleClass, []);
    TyConfigureTextFont(bmp, cellSty.FontName, ResolveFontSize(cellSty), cellSty.FontWeight, 96);
    charW := bmp.TextSize('MX').cx div 2;
    if charW <= 0 then charW := 8;   // LCL's fallback
    n := Max(AField.DisplayWidth, UTF8Length(ATitle));
    Result := n * charW + cellSty.Padding.Left + cellSty.Padding.Right;
    if (dgTitles in FDBOptions) and (ATitle <> '') then
    begin
      headSty := ActiveController.Model.ResolveStyle('TyGridHeader', StyleClass, []);
      TyConfigureTextFont(bmp, headSty.FontName, ResolveFontSize(headSty), headSty.FontWeight, 96);
      titleW := bmp.TextSize(ATitle).cx + headSty.Padding.Left + headSty.Padding.Right + 6;
      if titleW > Result then Result := titleW;
    end;
  finally
    bmp.Free;
  end;
end;

{ ---- the record window ------------------------------------------------------------- }

function TTyCustomDBGrid.RecordCapacity: Integer;
var
  rowH: Integer;
begin
  rowH := ScaleI(DefaultRowHeight);
  if rowH <= 0 then rowH := 1;
  Result := (ViewportH - FrozenHeightPx) div rowH;
  if Result < 1 then Result := 1;
end;

procedure TTyCustomDBGrid.UpdateBufferCount;
var
  n, recs: Integer;
begin
  if FUpdatingBuffer or (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  FUpdatingBuffer := True;
  try
    recs := 0;
    if FDataLink.Active then
    begin
      n := RecordCapacity;
      if FDataLink.BufferCount <> n then FDataLink.BufferCount := n;
      recs := FDataLink.RecordCount;
    end;
    if RowCount <> recs then
    begin
      RowCount := recs;
      Invalidate;
    end;
    SyncCurrentRow;
  finally
    FUpdatingBuffer := False;
  end;
  UpdateRecordBar;
end;

procedure TTyCustomDBGrid.SyncCurrentRow;
var
  r: Integer;
begin
  if (FDataLink = nil) or not FDataLink.Active or (RowCount = 0) then Exit;
  r := FDataLink.ActiveRecord;
  if (r < 0) or (r >= RowCount) or (r = Row) then Exit;
  FSyncingRow := True;
  try
    Row := r;
  finally
    FSyncingRow := False;
  end;
end;

procedure TTyCustomDBGrid.UpdateScrollBars;
begin
  { The string grid decides whether the vertical bar shows from the content height, which
    here is the records' answer (ContentHeightPx), so it leaves room for the bar the records
    want; the range and position are the records' too (UpdateRecordBar). }
  FMeasuringBars := True;
  try
    inherited UpdateScrollBars;
  finally
    FMeasuringBars := False;
  end;
  { The body's height is settled here (a resize, a row height, the header): the buffer
    follows it. }
  UpdateBufferCount;
end;

procedure TTyCustomDBGrid.Paint;
begin
  { A theme that changes the row height reaches no hook of ours before the next paint. }
  if (FDataLink <> nil) and FDataLink.Active and (FDataLink.BufferCount <> RecordCapacity) then
    UpdateBufferCount;
  inherited Paint;
end;

{ ---- the data link's events --------------------------------------------------------- }

procedure TTyCustomDBGrid.LinkActiveChanged;
begin
  if csDestroying in ComponentState then Exit;
  { The cell under an open editor is gone (its text, when there was a record to write it
    to, went in through UpdateData first). }
  if EditorMode then EndEdit(False);
  { The bookmarks are the dataset's: a closed (or another) dataset has none of them. }
  if FSelectedRows <> nil then FSelectedRows.Clear;
  { Opened: make the automatic columns, find the fields, size the window. Closed: drop the
    automatic columns, forget the fields, no rows. }
  LayoutChanged;
end;

procedure TTyCustomDBGrid.LinkDataSetChanged;
begin
  if csDestroying in ComponentState then Exit;
  { Posted, cancelled, inserted, deleted, refreshed: the record under an open editor may be
    another one now. A post wrote the editor's text first (UpdateData); a cancel drops it. }
  if EditorMode and not FCommittingForData then EndEdit(False);
  LayoutChanged;
end;

procedure TTyCustomDBGrid.LinkDataSetScrolled(ADistance: Integer);
begin
  if csDestroying in ComponentState then Exit;
  { The editor's cell now shows another record. A move in dsEdit wrote the editor's text
    before it moved (UpdateData); nothing else may land in the new record. }
  if EditorMode and not FCommittingForData then EndEdit(False);
  UpdateBufferCount;
  SyncCurrentRow;
  { The window moved under every row (Distance <> 0), or only the current record did. }
  Invalidate;
end;

procedure TTyCustomDBGrid.LinkRecordChanged(AField: TField);
begin
  if csDestroying in ComponentState then Exit;
  Invalidate;
end;

procedure TTyCustomDBGrid.LinkEditingChanged;
begin
  if csDestroying in ComponentState then Exit;
  Invalidate;
end;

procedure TTyCustomDBGrid.LinkUpdateData;
begin
  { The dataset is about to post the record or leave it (UpdateRecord): what the open editor
    holds goes into its field first, as LCL's UpdateData writes the editor's text. A value
    the field refuses raises out of the post, and the editor stays on its cell
    (SetEditText). }
  if FCommittingForData or not EditorMode then Exit;
  FCommittingForData := True;
  try
    { A value the grid refuses -- a mask left unfilled (#69), an OnValidateCell that says
      no -- is not saved, and neither is the record: the post stops here, the record stays
      in edit with the editor open, and the user completes the value or leaves with Esc.
      Posting the rest without it would drop the user's typing without a word. The mask
      says why with its own error, as LCL's grid does from UpdateData; another refusal has
      already said its piece, so the post just stops. }
    if not TryEndEdit(True) then
    begin
      if MaskUnfilled then ReportUnfilledMask;
      Abort;
    end;
  finally
    FCommittingForData := False;
  end;
end;

{ ---- the cells ---------------------------------------------------------------------- }

function TTyCustomDBGrid.DisplayToData(APos: Integer): Integer;
begin
  if (APos >= 0) and (APos < RowCount) then Result := APos else Result := -1;
end;

function TTyCustomDBGrid.DataToDisplay(ARow: Integer): Integer;
begin
  if (ARow >= 0) and (ARow < RowCount) then Result := ARow else Result := -1;
end;

function TTyCustomDBGrid.DisplayRowCount: Integer;
begin
  Result := RowCount;
end;

function TTyCustomDBGrid.FieldCellText(AField: TField): string;
begin
  if (AField.DataType = ftBoolean) and (dgeCheckboxColumn in FExtraOptions) then
  begin
    { The string grid's check vocabulary: checked, unchecked, grayed. }
    if AField.IsNull then
      Result := '2'
    else if AField.AsBoolean then
      Result := '1'
    else
      Result := '';
  end
  else if (AField.DataType in [ftMemo, ftWideMemo]) and (dgDisplayMemoText in FDBOptions) then
    Result := AField.AsString
  else if AField.DataType = ftBlob then
    Result := '(blob)'
  else
    Result := AField.DisplayText;
end;

function TTyCustomDBGrid.GetCellText(ACol, ARow: Integer): string;
var
  f: TField;
  old: Integer;
begin
  { The whole answer: never the string grid's store, never its OnGetCellText. }
  Result := '';
  f := ColumnField(ACol);
  if (f = nil) or (ARow < 0) or (ARow >= FDataLink.RecordCount) then Exit;
  old := FDataLink.ActiveRecord;
  FDataLink.ActiveRecord := ARow;
  try
    Result := FieldCellText(f);
    if Assigned(FOnUserCheckboxState) and ColumnShowsCheckBox(ACol) then
      Result := UserCheckBoxText(ACol, f);
  finally
    FDataLink.ActiveRecord := old;
  end;
end;

{ LCL's DrawCheckboxBitmaps: the state the field gives (a boolean's value; another field's
  ValueChecked / ValueUnchecked, anything else grayed), then OnUserCheckboxState's word, as
  the text the string grid's check box reads. }
function TTyCustomDBGrid.UserCheckBoxText(ACol: Integer; AField: TField): string;
var
  st: TCheckBoxState;
  c: TTyGridColumn;
  wc, wu: string;
begin
  c := GridColumn(ACol);
  if c <> nil then
  begin
    wc := c.ValueChecked;
    wu := c.ValueUnchecked;
  end
  else
  begin
    wc := '';
    wu := '';
  end;
  if AField.IsNull then
    st := cbGrayed
  else if AField.DataType = ftBoolean then
  begin
    if AField.AsBoolean then st := cbChecked else st := cbUnchecked;
  end
  else if (wc <> '') and (AField.AsString = wc) then
    st := cbChecked
  else if AField.AsString = wu then
    st := cbUnchecked
  else
    st := cbGrayed;
  FOnUserCheckboxState(Self, DBColumn(ACol), st);
  case st of
    cbChecked:
      if (AField.DataType <> ftBoolean) and (wc <> '') then Result := wc else Result := '1';
    cbUnchecked:
      if AField.DataType <> ftBoolean then Result := wu else Result := '';
  else
    Result := '2';
  end;
end;

function TTyCustomDBGrid.GetEditText(ACol, ARow: Integer): string;
var
  f: TField;
  old: Integer;
begin
  { An editor reopening after its field refused the text gets the text back, not the field's
    value (SetEditText). }
  if FHoldingText and (ACol = FHeldCol) and (ARow = FHeldRow) then Exit(FHeldText);
  Result := '';
  f := ColumnField(ACol);
  if (f = nil) or (ARow < 0) or (ARow >= FDataLink.RecordCount) then Exit;
  old := FDataLink.ActiveRecord;
  FDataLink.ActiveRecord := ARow;
  try
    if (f.DataType in [ftMemo, ftWideMemo]) and (dgDisplayMemoText in FDBOptions) then
      Result := f.AsString
    else
      Result := f.Text;
  finally
    FDataLink.ActiveRecord := old;
  end;
end;

{ Every user edit lands here (the editor's commit, a check box, paste, cut, fill, replace,
  clear): into the field of the current record, never into the cell store. Another row's
  cell is not the current record and is left alone, and so is a read-only cell. }
procedure TTyCustomDBGrid.SetEditText(ACol, ARow: Integer; const AText: string);
var
  f: TField;
  kind: TTyGridEditorKind;
begin
  f := ColumnField(ACol);
  if (f = nil) or (ARow <> FDataLink.ActiveRecord) or ColumnIsReadOnly(ACol) then Exit;
  if not FDataLink.Editing and not FDataLink.Edit then Exit;   // refused: read-only
  try
    WriteFieldText(ACol, f, AText);
  except
    { The field (or its OnValidate) refused the text: the editor stays on its cell with what
      the user typed -- it has just been closed by the commit, so it opens again -- and the
      exception goes on to the application, as LCL's grid lets it. }
    kind := EditorKindFor(ACol, ARow);
    if (ACol = Col) and (ARow = Row) and not EditorMode
      and not (kind in [gekNone, gekCheckBox, gekRating, gekColor]) then
    begin
      FHeldCol := ACol;
      FHeldRow := ARow;
      FHeldText := AText;
      FHoldingText := True;
      try
        try
          BeginEdit(ACol, ARow);
        except
          { Opening it again is a courtesy; the field's exception is the one to report. }
        end;
      finally
        FHoldingText := False;
      end;
    end;
    raise;
  end;
end;

function TTyCustomDBGrid.EditorKindFor(ACol, ARow: Integer): TTyGridEditorKind;
var
  f: TField;
begin
  { A boolean field is a check box whether or not it can be changed: the kind is also how
    the cell is drawn. }
  if IsCheckBoxColumn(ACol) then Exit(gekCheckBox);
  Result := inherited EditorKindFor(ACol, ARow);
  if (Result = gekNone) or (Result = gekCheckBox) then Exit;
  f := ColumnField(ACol);
  if (f = nil) or ColumnIsReadOnly(ACol) then Exit(gekNone);
  { The field's own kind replaces the plain text editor, never a kind the column or
    OnGetEditorKind chose. The mask the event gives is asked only for the current cell, the
    one an editor can open on (this is asked for every cell painted). }
  if Result <> gekText then Exit;
  if f.FieldKind = fkLookup then
    Result := gekPickList
  else if (f.EditMask <> '')
    or ((ACol = Col) and (ARow = Row) and Assigned(FOnFieldEditMask)
        and (EditMaskFor(ACol) <> '')) then
    Result := gekMask;
end;

procedure TTyCustomDBGrid.AccumulateCell(ACol, ADataRow: Integer; AKind: TTyGridAggregate;
  var AAcc: Double; var ACount: Integer; var AStarted: Boolean);
begin
end;

{ ---- moving ------------------------------------------------------------------------- }

function TTyCustomDBGrid.DataSetIsSequenced: Boolean;
begin
  { LCL asks both: a filtered dataset may say it is sequenced while its RecNo and
    RecordCount count records the filter hides. }
  Result := (FDataLink <> nil) and FDataLink.Active and FDataLink.DataSet.IsSequenced
    and not FDataLink.DataSet.Filtered;
end;

function TTyCustomDBGrid.PageRecords: Integer;
begin
  Result := FDataLink.BufferCount;
  if Result < 1 then Result := 1;
end;

procedure TTyCustomDBGrid.RecordBarParams(out AMax, APage, APosition: Integer);
var
  ds: TDataSet;
begin
  AMax := 0;
  APage := 0;
  APosition := 0;
  if (FDataLink = nil) or not FDataLink.Active then Exit;
  ds := FDataLink.DataSet;
  if DataSetIsSequenced then
  begin
    { LCL's range is RecordCount + VisibleRowCount - 1 with a page of VisibleRowCount; this
      bar's Max is the last POSITION, so the same bar is Max = RecordCount - 1. }
    APage := PageRecords;
    AMax := ds.RecordCount - 1;
    if AMax < 0 then AMax := 0;
    if ds.BOF then
      APosition := 0
    else if ds.EOF then
      APosition := AMax
    else
      APosition := ds.RecNo - 1;
  end
  else
  begin
    { LCL's three positions: at the start, somewhere inside, at the end. }
    AMax := 4;
    APage := 2;
    if ds.EOF then
      APosition := 4
    else if ds.BOF then
      APosition := 0
    else
      APosition := 2;
  end;
  if APosition > AMax then APosition := AMax;
  if APosition < 0 then APosition := 0;
end;

function TTyCustomDBGrid.WantsRecordBar: Boolean;
begin
  Result := False;
  if (FDataLink = nil) or not FDataLink.Active then Exit;
  { The window's capacity, not BufferCount: this is asked while the bars are being laid out,
    before the buffer follows the new height. A window that is not full holds every record
    there is, whatever the dataset can count. }
  if DataSetIsSequenced then
    Result := FDataLink.DataSet.RecordCount > RecordCapacity
  else
    Result := FDataLink.RecordCount >= RecordCapacity;
end;

procedure TTyCustomDBGrid.UpdateRecordBar;
var
  bar: TTyScrollBar;
  aMax, aPage, aPos: Integer;
  want: Boolean;
begin
  bar := VScrollBar;
  if (bar = nil) or (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  case VertScrollBarMode of
    gsbAlways: want := True;
    gsbNever:  want := False;
  else
    want := WantsRecordBar;
  end;
  if (bar.Visible <> want) and not FLayingOutBars then
  begin
    { The bar comes or goes: the string grid lays both bars out again (and comes back here,
      with the bar placed). }
    FLayingOutBars := True;
    try
      UpdateScrollBars;
    finally
      FLayingOutBars := False;
    end;
    Exit;
  end;
  if not bar.Visible then Exit;
  RecordBarParams(aMax, aPage, aPos);
  FSettingBar := True;
  try
    bar.Min := 0;
    bar.Max := aMax;
    bar.PageSize := aPage;
    { Not under the user's hand: a drag keeps the thumb where the mouse put it. }
    if not bar.Dragging then bar.SetPositionSnapped(aPos);
  finally
    FSettingBar := False;
  end;
  if not bar.Dragging then FBarPosition := aPos;
end;

function TTyCustomDBGrid.ContentHeightPx: Integer;
begin
  if FMeasuringBars then
  begin
    if WantsRecordBar then
      Result := MaxInt div 4
    else
      Result := 0;
  end
  else
    Result := inherited ContentHeightPx;
end;

procedure TTyCustomDBGrid.DoVScroll(APosition: Integer);
var
  delta, recNo: Integer;
begin
  if FSettingBar then Exit;
  if (FDataLink = nil) or not FDataLink.Active then Exit;
  if APosition = FBarPosition then Exit;
  delta := APosition - FBarPosition;
  FBarPosition := APosition;
  if DataSetIsSequenced then
  begin
    { Line, page or thumb, the position is a record: RecNo is position + 1. }
    recNo := APosition + 1;
    if recNo > FDataLink.DataSet.RecordCount then recNo := FDataLink.DataSet.RecordCount;
    if recNo < 1 then recNo := 1;
    DataOp(dgoRecNo, recNo);
  end
  else if delta < -1 then
    DataOp(dgoMoveBy, -PageRecords)
  else if delta > 1 then
    DataOp(dgoMoveBy, PageRecords)
  else
    DataOp(dgoMoveBy, delta);
  { Where the dataset really is (a three-position bar goes back to the middle). }
  UpdateRecordBar;
end;

function TTyCustomDBGrid.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  notches: Integer;
begin
  { No dataset: the string grid's wheel, which fires the application's handlers itself. }
  if (FDataLink = nil) or not FDataLink.Active then
    Exit(inherited DoMouseWheel(Shift, WheelDelta, MousePos));
  { The application's handlers first, as LCL's TControl.DoMouseWheel asks them. }
  if FireWheelEvents(Shift, WheelDelta, MousePos) then Exit(True);
  { One record per notch, as LCL's TDBGrid moves one per wheel message. }
  notches := Abs(WheelDelta) div 120;   // WHEEL_DELTA
  if notches < 1 then notches := 1;
  if WheelDelta > 0 then
    DataOp(dgoMoveBy, -notches)
  else
    DataOp(dgoMoveBy, notches);
  Result := True;
end;

{ The wheel events on the data path, which moves records instead of calling the string grid's
  DoMouseWheel (that one fires them through TControl, #62). TDBGridEventsTest.
  TestOneNotchFiresTheEventOnce counts the events on both paths and turns red on a double fire. }
function TTyCustomDBGrid.FireWheelEvents(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := False;
  if Assigned(OnMouseWheel) then OnMouseWheel(Self, Shift, WheelDelta, MousePos, Result);
  if Result then Exit;
  if WheelDelta < 0 then
  begin
    if Assigned(OnMouseWheelDown) then OnMouseWheelDown(Self, Shift, MousePos, Result);
  end
  else if Assigned(OnMouseWheelUp) then
    OnMouseWheelUp(Self, Shift, MousePos, Result);
end;

procedure TTyCustomDBGrid.MoveCursor(ACol, ARow: Integer);
begin
  { LCL's BeforeMoveSelection: the column the user is leaving hears it first, while it is
    still the current one. }
  if Assigned(FOnColExit) and not FSyncingRow and (ACol <> Col) and (ACol >= 0)
    and (ACol < Columns.Count) and not (csDesigning in ComponentState) then
    FOnColExit(Self);
  if FSyncingRow or (FDataLink = nil) or not FDataLink.Active or (RowCount = 0)
    or (ARow = Row) then
  begin
    inherited MoveCursor(ACol, ARow);
    Exit;
  end;
  { The record moves; the row follows it (DataSetScrolled). Out of the window is fine --
    the window scrolls. }
  if not DataOp(dgoMoveBy, ARow - Row) then Exit;
  if ACol <> Col then inherited MoveCursor(ACol, Row);
end;

procedure TTyCustomDBGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  hit: TTyGridHit;
begin
  { LCL: a click on another row first drops a new record nobody typed into, when it is the
    appended one (the editor's text written first -- what was typed is a change). The
    string grid then moves the cursor, which moves the record (MoveCursor). }
  FEditorWasOpen := EditorMode;
  try
    hit := CellAt(X, Y);
    if (FDataLink <> nil) and FDataLink.Active and (Button = mbLeft) then
    begin
      if (hit.Part = ghpCell) and (hit.Row <> Row) and CommitEditor and InsertCancelable
        and FDataLink.DataSet.EOF then
        FDataLink.DataSet.Cancel;
    end;
    inherited MouseDown(Button, Shift, X, Y);
    { The record is the clicked one now (unless the click was refused). }
    if (FDataLink <> nil) and FDataLink.Active and (Button = mbLeft)
      and (hit.Part = ghpCell) and (hit.Row = Row) and (hit.Col = Col) then
    begin
      { LCL's multiselect clicks: Ctrl toggles the record, a plain click selects it alone. }
      if dgMultiselect in FDBOptions then
      begin
        if ssCtrl in Shift then
          ToggleSelectedRow
        else
          ClearSelection(True);
      end;
      if Assigned(FOnCellClick) and not (csDesigning in ComponentState) then
        FOnCellClick(DBColumn(hit.Col));
    end;
  finally
    FEditorWasOpen := False;
  end;
end;

procedure TTyCustomDBGrid.UserKeyDown(var Key: Word; Shift: TShiftState);
begin
  if Assigned(OnKeyDown) then OnKeyDown(Self, Key, Shift);
  if Key <> 0 then DoCallKeyEventHandler(chtOnKeyDown, Key, Shift);
end;

procedure TTyCustomDBGrid.KeyDown(var Key: Word; Shift: TShiftState);
var
  ds: TDataSet;
  tabWraps: Boolean;
  prevSel, newSel: Boolean;
  moves: Integer;
begin
  { Tab wraps to another record only off the window's last field (first, backwards); every
    other Tab is the string grid's, which moves within the window (and so through
    MoveCursor). }
  tabWraps := (Key = VK_TAB) and (dgTabs in FDBOptions) and (FDataLink <> nil)
    and FDataLink.Active and (Shift * [ssCtrl, ssAlt, ssMeta] = []) and (RowCount > 0)
    and (((ssShift in Shift) and (Col <= FirstVisibleCol) and (Row = 0))
      or (not (ssShift in Shift) and (Col >= LastVisibleCol) and (Row = RowCount - 1)));
  if (FDataLink = nil) or not FDataLink.Active or not Enabled
    or not (tabWraps or (Key in [VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT, VK_HOME, VK_END,
                                VK_ESCAPE, VK_INSERT, VK_DELETE, VK_MULTIPLY]))
    { Home / End without Ctrl are the string grid's: the first and the last column. }
    or ((Key in [VK_HOME, VK_END, VK_DELETE, VK_MULTIPLY]) and not (ssCtrl in Shift))
    { Esc in the editor drops the cell's edit, which is the string grid's. }
    or ((Key = VK_ESCAPE) and EditorMode) then
  begin
    inherited KeyDown(Key, Shift);
    Exit;
  end;
  UserKeyDown(Key, Shift);
  if Key = 0 then Exit;
  ds := FDataLink.DataSet;
  case Key of
    VK_TAB:
      if WrapTab(ssShift in Shift) then
        Key := 0
      else
        inherited KeyDown(Key, Shift);
    VK_DOWN, VK_UP:
      begin
        { LCL's SelectNext: Shift extends the selection over the record moved to, a plain
          arrow selects that record alone (dgMultiselect without dgPersistentMultiSelect). }
        prevSel := False;
        if (ssShift in Shift) and (dgMultiselect in FDBOptions) then
          prevSel := FSelectedRows.CurrentRowSelected;
        moves := FMoveCount;
        if Key = VK_DOWN then KeyDownRecord else KeyUpRecord;
        if (FMoveCount <> moves) and (ds.State = dsBrowse) then
        begin
          if ssShift in Shift then
          begin
            if [dgMultiselect, dgPersistentMultiSelect] * FDBOptions = [dgMultiselect] then
            begin
              newSel := FSelectedRows.CurrentRowSelected;
              ExtendSelection(prevSel, newSel, Key = VK_DOWN);
            end;
          end
          else
            ClearSelection(True);
        end;
        Key := 0;
      end;
    VK_NEXT:
      begin
        DataOp(dgoMoveBy, PageRecords);
        ClearSelection(True);
        Key := 0;
      end;
    VK_PRIOR:
      begin
        DataOp(dgoMoveBy, -PageRecords);
        ClearSelection(True);
        Key := 0;
      end;
    VK_HOME:
      begin
        DataOp(dgoFirst);
        ClearSelection(True);
        Key := 0;
      end;
    VK_END:
      begin
        DataOp(dgoLast);
        ClearSelection(True);
        Key := 0;
      end;
    VK_MULTIPLY:
      { LCL: Ctrl+* toggles the current record's selection. }
      if dgMultiselect in FDBOptions then
      begin
        ToggleSelectedRow;
        Key := 0;
      end;
    VK_ESCAPE:
      { No editor open: the record's changes go. Nothing to cancel leaves the key to the
        form (its Cancel button). }
      if ds.State in dsEditModes then
      begin
        ds.Cancel;
        Key := 0;
      end;
    VK_INSERT:
      if GridCanModify and not (dgDisableInsert in FDBOptions) then
      begin
        DataOp(dgoInsert);
        Key := 0;
      end;
    VK_DELETE:
      if GridCanModify and not (dgDisableDelete in FDBOptions) and not ds.IsEmpty then
        if not (dgConfirmDelete in FDBOptions) or ConfirmDeleteRecord then
        begin
          if EditorMode then EndEdit(False);
          ds.Delete;
          Key := 0;
        end;
  end;
end;

procedure TTyCustomDBGrid.KeyDownRecord;
var
  ds: TDataSet;
begin
  FEditorWasOpen := EditorMode;
  try
    { The editor's text first: what was typed makes a new record a changed one. }
    if not CommitEditor then Exit;
    ds := FDataLink.DataSet;
    if InsertCancelable then
    begin
      { On the appended record, Down stays; on one inserted inside the dataset it drops it. }
      if not ds.EOF then ds.Cancel;
      Exit;
    end;
    if not DataOp(dgoMoveBy, 1) then Exit;
    FEditorWasOpen := False;
    if GridCanModify and ds.EOF and not (dgDisableInsert in FDBOptions) then
      DataOp(dgoAppend);
  finally
    FEditorWasOpen := False;
  end;
end;

procedure TTyCustomDBGrid.KeyUpRecord;
begin
  FEditorWasOpen := EditorMode;
  try
    if not CommitEditor then Exit;
    if InsertCancelable then
      FDataLink.DataSet.Cancel
    else
      DataOp(dgoMoveBy, -1);
  finally
    FEditorWasOpen := False;
  end;
end;

function TTyCustomDBGrid.CommitEditor: Boolean;
var
  w: TWinControl;
begin
  Result := True;
  if not EditorMode then Exit;
  Result := TryEndEdit(True);
  if not Result then
  begin
    { The string grid's RefocusEditor, which it keeps to itself: a refused value keeps the
      keyboard in its editor. }
    w := InplaceEditor;
    if (w <> nil) and w.HandleAllocated and w.CanFocus then w.SetFocus;
  end;
end;

procedure TTyCustomDBGrid.ReopenEditor;
begin
  try
    BeginEdit(Col, Row);
  except
    { A courtesy; the dataset's exception is the one to report. }
  end;
end;

function TTyCustomDBGrid.DataOp(AOp: TTyDBGridDataOp; ADelta: Integer): Boolean;
var
  ds: TDataSet;
  wasEditing: Boolean;
begin
  Result := False;
  if (FDataLink = nil) or not FDataLink.Active then Exit;
  wasEditing := EditorMode or FEditorWasOpen;
  if not CommitEditor then Exit;
  ds := FDataLink.DataSet;
  try
    case AOp of
      dgoMoveBy:
        if FDataLink.MoveBy(ADelta) <> 0 then Inc(FMoveCount);
      dgoRecNo:  ds.RecNo := ADelta;
      dgoFirst:  ds.First;
      dgoLast:   ds.Last;
      dgoInsert: ds.Insert;
      dgoAppend: ds.Append;
    end;
    if AOp <> dgoMoveBy then Inc(FMoveCount);
  except
    { The record could not be left (its post was refused): the user goes on where they were
      typing. }
    if wasEditing and not EditorMode and FDataLink.Active and (ds.State in dsEditModes) then
      ReopenEditor;
    raise;
  end;
  Result := True;
end;

procedure TTyCustomDBGrid.KeyPress(var Key: Char);
var
  f: TField;
begin
  if (FDataLink <> nil) and FDataLink.Active and not EditorMode and (Key >= #32) then
  begin
    { A character the field does not take (a letter in a number) starts nothing. LCL's
      EditorCanAcceptKey. }
    f := ColumnField(Col);
    if (f <> nil) and not IsCheckBoxColumn(Col) and (f.FieldKind = fkData)
      and not f.IsValidChar(Key) then
    begin
      Key := #0;
      Exit;
    end;
  end;
  inherited KeyPress(Key);
  { Typing that opened no editor -- a read-only cell, a dataset that would not edit -- is
    swallowed, as LCL's grid swallows it. }
  if (FDataLink <> nil) and FDataLink.Active and not EditorMode and (Key >= #32) then
    Key := #0;
end;

procedure TTyCustomDBGrid.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);
  if (FDataLink <> nil) and FDataLink.Active and not EditorMode and (Length(UTF8Key) > 1) then
    UTF8Key := '';
end;

function TTyCustomDBGrid.ChildKey(var Message: TLMKey): Boolean;
var
  wasEditing: Boolean;
begin
  { The string grid's #52 claim, whole (its override is private to it, so "inherited" here
    may not reach it): an unmodified arrow a child leaves standing goes nowhere, and Up / Down
    in the editor move -- here as LCL's doVKDown / doVKUp, appending past the last record
    included. }
  if (Message.CharCode in [VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN])
    and (GetKeyShiftState * [ssShift, ssCtrl, ssAlt, ssMeta] = []) then
  begin
    wasEditing := EditorMode;
    if EditorMode and (Message.CharCode in [VK_UP, VK_DOWN]) then
    begin
      if (FDataLink <> nil) and FDataLink.Active then
      begin
        if Message.CharCode = VK_DOWN then KeyDownRecord else KeyUpRecord;
      end
      else if Message.CharCode = VK_DOWN then
        MoveCursor(Col, Row + 1)
      else
        MoveCursor(Col, Row - 1);
    end;
    if wasEditing and not EditorMode and HandleAllocated and CanFocus then SetFocus;
    Message.CharCode := VK_UNKNOWN;
    Exit(True);
  end;
  Result := inherited ChildKey(Message);
end;

procedure TTyCustomDBGrid.DoExit;
begin
  { dgCancelOnExit: a new record nobody typed into does not outlive the focus. An editor
    still open here holds a refused value -- the user did type. }
  if (FDataLink <> nil) and FDataLink.Active and (dgCancelOnExit in FDBOptions)
    and not EditorMode and InsertCancelable then
    FDataLink.DataSet.Cancel;
  inherited DoExit;
end;

{ ---- editing ------------------------------------------------------------------------ }

function TTyCustomDBGrid.GridCanModify: Boolean;
begin
  Result := not ReadOnly and (dgEditing in FDBOptions) and (FDataLink <> nil)
    and FDataLink.Active and not FDataLink.ReadOnly and FDataLink.DataSet.CanModify;
end;

function TTyCustomDBGrid.ColumnIsReadOnly(ACol: Integer): Boolean;
var
  f: TField;
  c: TTyGridColumn;
  keys: TList;
  i: Integer;
begin
  Result := True;
  if not GridCanModify then Exit;
  c := GridColumn(ACol);
  if (c = nil) or c.ReadOnly then Exit;
  f := ColumnField(ACol);
  if f = nil then Exit;
  if f.FieldKind = fkLookup then
  begin
    { A lookup is changed through its key fields: read-only when it has none, or one of them
      cannot be modified (LCL's EditorIsReadOnly). }
    keys := TList.Create;
    try
      f.DataSet.GetFieldList(keys, f.KeyFields);
      if keys.Count = 0 then Exit;
      for i := 0 to keys.Count - 1 do
        if not TField(keys[i]).CanModify then Exit;
    finally
      keys.Free;
    end;
    Exit(False);
  end;
  { A memo edits as text only while it shows its text; any other blob not at all. }
  if f.IsBlob and not ((f.DataType in [ftMemo, ftWideMemo])
    and (dgDisplayMemoText in FDBOptions)) then Exit;
  Result := not TyFieldIsEditable(f) or not f.CanModify;
end;

function TTyCustomDBGrid.InsertCancelable: Boolean;
begin
  Result := (FDataLink <> nil) and FDataLink.Active
    and (FDataLink.DataSet.State = dsInsert) and not FDataLink.DataSet.Modified;
end;

function TTyCustomDBGrid.CanEditCell(ACol, ARow: Integer): Boolean;
var
  f: TField;
begin
  Result := inherited CanEditCell(ACol, ARow);
  if not Result then Exit;
  { A check box (drawn as one even when read-only) toggles only when it may. }
  if ColumnIsReadOnly(ACol) then Exit(False);
  { BeginEdit asks before it moves to another row; that record's Edit comes when its text
    is written (SetEditText). }
  if (FDataLink = nil) or not FDataLink.Active or (ARow <> Row) then Exit;
  { LCL's EditorIsReadOnly: not editing yet, start; refused, read-only. }
  if not FDataLink.Editing then Result := FDataLink.Edit;
  if not Result then Exit;
  f := ColumnField(ACol);
  if (f <> nil) and (f.FieldKind = fkLookup) and (EditorKindFor(ACol, ARow) = gekPickList) then
    FillLookupPickList(ACol, f);
end;

function TTyCustomDBGrid.EditMaskFor(ACol: Integer): string;
var
  f: TField;
begin
  Result := inherited EditMaskFor(ACol);   // the column's own, when it has one
  if Result <> '' then Exit;
  f := ColumnField(ACol);
  if f = nil then Exit;
  Result := f.EditMask;
  if Assigned(FOnFieldEditMask) then FOnFieldEditMask(Self, f, Result);
end;

function TTyCustomDBGrid.MaxEditLengthFor(ACol, ARow: Integer): Integer;
var
  f: TField;
begin
  Result := inherited MaxEditLengthFor(ACol, ARow);
  if Result <> 0 then Exit;
  { LCL: a string field takes no more than its Size. }
  f := ColumnField(ACol);
  if (f is TStringField) and (f.FieldKind = fkData) then Result := f.Size;
end;

procedure TTyCustomDBGrid.WriteFieldText(ACol: Integer; AField: TField; const AText: string);
var
  c: TTyGridColumn;
  unchecked: string;
begin
  if IsCheckBoxColumn(ACol) then
  begin
    { The check box vocabulary: '2' grayed (NULL), the column's unchecked word or '' off,
      anything else on. }
    if AText = '2' then
      AField.Clear
    else
    begin
      c := GridColumn(ACol);
      if c <> nil then unchecked := c.ValueUnchecked else unchecked := '';
      AField.AsBoolean := (AText <> '') and ((unchecked = '') or not SameText(AText, unchecked));
    end;
  end
  else if (AField.DataType in [ftMemo, ftWideMemo])
    or (EditorKindFor(ACol, Row) = gekCheckBox) then
    { A memo's content; a check box column's words (ValueChecked / ValueUnchecked). }
    AField.AsString := AText
  else
  begin
    AField.Text := AText;
    if AField.FieldKind = fkLookup then WriteLookupKeys(AField, AText);
  end;
end;

procedure TTyCustomDBGrid.WriteLookupKeys(AField: TField; const AText: string);
var
  lds: TDataSet;
  keys: Variant;
  wasActive: Boolean;
  bm: TBookmark;
begin
  keys := Null;
  if AField.LookupCache then
    keys := AField.LookupList.FirstKeyByValue(AText)
  else
  begin
    lds := AField.LookupDataSet;
    if lds = nil then Exit;
    { LCL's LookupGetBookMark / LookupGotoBookMark: the lookup table is put back. }
    wasActive := lds.Active;
    bm := nil;
    if wasActive then
    begin
      bm := lds.GetBookmark;
      lds.DisableControls;
    end
    else
      lds.Open;
    try
      if lds.Locate(AField.LookupResultField, AText, []) then
        keys := lds.FieldValues[AField.LookupKeyFields];
    finally
      if wasActive then
      begin
        try
          lds.GotoBookmark(bm);
          lds.FreeBookmark(bm);
        finally
          lds.EnableControls;
        end;
      end
      else
        lds.Close;
    end;
  end;
  AField.DataSet.FieldValues[AField.KeyFields] := keys;
end;

procedure TTyCustomDBGrid.FillLookupPickList(ACol: Integer; AField: TField);
var
  c: TTyGridColumn;
  lds: TDataSet;
  wasActive: Boolean;
  bm: TBookmark;
begin
  { Into the column's own list, as LCL's TColumn.GetPickList fills it. }
  c := GridColumn(ACol);
  if c = nil then Exit;
  c.PickList.BeginUpdate;
  try
    c.PickList.Clear;
    if AField.LookupCache then
      AField.LookupList.ValuesToStrings(c.PickList)
    else
    begin
      lds := AField.LookupDataSet;
      if lds = nil then Exit;
      wasActive := lds.Active;
      bm := nil;
      if wasActive then
      begin
        bm := lds.GetBookmark;
        lds.DisableControls;
      end
      else
        lds.Open;
      try
        lds.First;
        while not lds.EOF do
        begin
          c.PickList.Add(lds.FieldByName(AField.LookupResultField).AsString);
          lds.Next;
        end;
      finally
        if wasActive then
        begin
          try
            lds.GotoBookmark(bm);
            lds.FreeBookmark(bm);
          finally
            lds.EnableControls;
          end;
        end
        else
          lds.Close;
      end;
    end;
  finally
    c.PickList.EndUpdate;
  end;
end;

function TTyCustomDBGrid.ConfirmDeleteRecord: Boolean;
begin
  Result := TyMessageDlg(rsTyDBNavConfirmDelete, mtConfirmation, [mbOK, mbCancel], 0) <> mrCancel;
end;

function TTyCustomDBGrid.ColumnShowsCheckBox(ACol: Integer): Boolean;
var
  c: TTyGridColumn;
begin
  if IsCheckBoxColumn(ACol) then Exit(True);
  c := GridColumn(ACol);
  Result := (c <> nil) and (c.EditorKind = gekCheckBox);
end;

function TTyCustomDBGrid.CanToggleCellCheck(ACol, ARow: Integer): Boolean;
begin
  Result := inherited CanToggleCellCheck(ACol, ARow);
  if not Result or (FDataLink = nil) or not FDataLink.Active then Exit;
  { Only the current record is written (SetEditText); LCL's EditorIsReadOnly: a dataset that
    will not go into dsEdit makes the cell read-only, and the toggle is not a toggle. }
  if (ARow <> FDataLink.ActiveRecord) or ColumnIsReadOnly(ACol) then Exit(False);
  if not FDataLink.Editing then Result := FDataLink.Edit;
end;

function TTyCustomDBGrid.DBColumn(ACol: Integer): TTyDBGridColumn;
begin
  Result := nil;
  if (ACol >= 0) and (ACol < Columns.Count) then Result := Columns[ACol];
end;

{ ---- the indicator ------------------------------------------------------------------ }

function TTyCustomDBGrid.IndicatorFor(ARow: Integer): TTyDBGridIndicator;
begin
  Result := dgiNone;
  if (FDataLink = nil) or not FDataLink.Active or (ARow < 0)
    or (ARow >= FDataLink.RecordCount) then Exit;
  if ARow = FDataLink.ActiveRecord then
    case FDataLink.DataSet.State of
      dsEdit:   Result := dgiEdit;
      dsInsert: Result := dgiInsert;
    else
      Result := dgiBrowse;
    end
  else if RowIsSelected(ARow) then
    Result := dgiSelected;
end;

procedure TTyCustomDBGrid.RenderChrome(P: TTyPainter; const M: TTyGridMetrics);
var
  i0, i1, r: Integer;
  kind: TTyDBGridIndicator;
  indS, selS: TTyStyleSet;
  ink, insertInk: TTyColor;
  mirror: Boolean;

  procedure DrawOne;
  var
    rr, box: TRect;
    side, cx, cy: Integer;
    c: TTyColor;
  begin
    rr := TyGridRowRect(DataToDisplay(r), M);
    side := Min(i1 - i0, rr.Bottom - rr.Top) - ScaleI(2);
    if side <= 0 then Exit;
    cx := (i0 + i1) div 2;
    cy := (rr.Top + rr.Bottom) div 2;
    box := Rect(cx - side div 2, cy - side div 2, cx - side div 2 + side,
      cy - side div 2 + side);
    if kind = dgiInsert then c := insertInk else c := ink;
    if not TyTryDrawGlyphOverride(P, ActiveController, box,
      TyDBGridIndicatorTokens[kind], c) then
      DrawIndicatorMark(P, box, kind, c, mirror);
  end;

begin
  inherited RenderChrome(P, M);
  if (FDataLink = nil) or not FDataLink.Active or (RowCount = 0) then Exit;
  if not IndicatorBandX(i0, i1) then Exit;
  { The marks take the indicator column's own text colour, as its row numbers do; the insert
    bar the accent a theme gives a selected cell -- a theme colour either way. }
  indS := ActiveController.Model.ResolveStyle('TyGridIndicator', StyleClass, []);
  if tpTextColor in indS.Present then ink := indS.TextColor
  else ink := CurrentStyle.TextColor;
  selS := ActiveController.Model.ResolveStyle('TyGridCell', StyleClass, [tysSelected]);
  if (tpBackground in selS.Present) and (selS.Background.Kind <> tfkNone) then
    insertInk := selS.Background.Color
  else
    insertInk := ink;
  mirror := RtlLayout;
  for r := 0 to RowCount - 1 do
  begin
    kind := IndicatorFor(r);
    if kind = dgiNone then Continue;
    DrawInRowBand(P, DataToDisplay(r), M, @DrawOne);
  end;
end;

{ ---- multiselect -------------------------------------------------------------------- }

function TTyCustomDBGrid.RowIsSelected(ARow: Integer): Boolean;
var
  old: Integer;
begin
  Result := False;
  if (FSelectedRows = nil) or (FSelectedRows.Count = 0) or not (dgMultiselect in FDBOptions)
    or (FDataLink = nil) or not FDataLink.Active or (ARow < 0)
    or (ARow >= FDataLink.RecordCount) then Exit;
  if FSelCacheValid and (ARow < Length(FSelRowCache)) then Exit(FSelRowCache[ARow]);
  old := FDataLink.ActiveRecord;
  FDataLink.ActiveRecord := ARow;
  try
    Result := FSelectedRows.CurrentRowSelected;
  finally
    FDataLink.ActiveRecord := old;
  end;
end;

procedure TTyCustomDBGrid.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  r: Integer;
begin
  { Every cell of a row asks whether the row is selected (CellStates): ask the bookmarks once
    per row and frame. }
  SetLength(FSelRowCache, 0);
  if (FDataLink <> nil) and FDataLink.Active and (FSelectedRows.Count > 0)
    and (dgMultiselect in FDBOptions) then
  begin
    SetLength(FSelRowCache, FDataLink.RecordCount);
    for r := 0 to High(FSelRowCache) do
      FSelRowCache[r] := RowIsSelected(r);
  end;
  FSelCacheValid := True;
  try
    inherited RenderTo(ACanvas, ARect, APPI);
  finally
    FSelCacheValid := False;
  end;
end;

function TTyCustomDBGrid.CellStates(ACol, ARow: Integer): TTyStateSet;
begin
  Result := inherited CellStates(ACol, ARow);
  if RowIsSelected(ARow) then Include(Result, tysSelected);
end;

procedure TTyCustomDBGrid.ClearSelection(ASelectCurrent: Boolean);
begin
  if [dgMultiselect, dgPersistentMultiSelect] * FDBOptions <> [dgMultiselect] then Exit;
  FSelectedRows.Clear;
  if ASelectCurrent then FSelectedRows.CurrentRowSelected := True;
end;

procedure TTyCustomDBGrid.ToggleSelectedRow;
begin
  if not (dgMultiselect in FDBOptions) then Exit;
  FSelectedRows.CurrentRowSelected := not FSelectedRows.CurrentRowSelected;
end;

procedure TTyCustomDBGrid.ExtendSelection(APrevSelected, ANewSelected, ADown: Boolean);
var
  old, prev: Integer;
begin
  FSelectedRows.CurrentRowSelected := True;
  { The record left is the buffer's neighbour: the move was one record. }
  old := FDataLink.ActiveRecord;
  if ADown then prev := old - 1 else prev := old + 1;
  if (prev < 0) or (prev >= FDataLink.RecordCount) then Exit;
  FDataLink.ActiveRecord := prev;
  try
    FSelectedRows.CurrentRowSelected := not (APrevSelected and ANewSelected);
  finally
    FDataLink.ActiveRecord := old;
  end;
end;

function TTyCustomDBGrid.WrapTab(ABackward: Boolean): Boolean;
var
  moves: Integer;
  st: TDataSetState;
begin
  moves := FMoveCount;
  st := FDataLink.DataSet.State;
  { Down's and Up's own steps (LCL's MoveSel ends in doVKDown / doVKUp): the editor's text
    first, a new record nobody typed into dropped, past the last record an Append. }
  if ABackward then KeyUpRecord else KeyDownRecord;
  Result := (FMoveCount <> moves) or (FDataLink.DataSet.State <> st);
  if not Result then Exit;
  if ABackward then
    inherited MoveCursor(LastVisibleCol, Row)
  else
    inherited MoveCursor(FirstVisibleCol, Row);
end;

{ ---- what the string grid would sort and filter by ------------------------------------ }

function TTyCustomDBGrid.ShowsFilterButton(ACol: Integer): Boolean;
begin
  { Filtering is the dataset's (see the unit comment): no funnel on a title. }
  Result := False;
end;

{ ---- events ------------------------------------------------------------------------- }

function TTyCustomDBGrid.DrawStateOf(ACol, ARow: Integer): TGridDrawState;
begin
  Result := [];
  if IsCellSelected(ACol, ARow) or RowIsSelected(ARow) then Include(Result, gdSelected);
  if (ACol = Col) and (ARow = Row) then Include(Result, gdFocused);
  if (goRowHighlight in inherited Options) and (ARow = Row) then
    Include(Result, gdRowHighlight);
end;

function TTyCustomDBGrid.DoDrawCell(P: TTyPainter; ACol, ARow: Integer): Boolean;
var
  r: TRect;
  old: Integer;
begin
  Result := False;
  if Assigned(FOnDrawColumnCell) and not (csDesigning in ComponentState)
    and (FDataLink <> nil) and FDataLink.Active and (ARow >= 0)
    and (ARow < FDataLink.RecordCount) then
  begin
    r := CellVisibleRect(ACol, ARow);
    if not IsRectEmpty(r) then
    begin
      old := FDataLink.ActiveRecord;
      FDataLink.ActiveRecord := ARow;
      try
        FOnDrawColumnCell(Self, r, ACol, DBColumn(ACol), DrawStateOf(ACol, ARow), P, Result);
      finally
        FDataLink.ActiveRecord := old;
      end;
    end;
  end;
  if not Result then Result := inherited DoDrawCell(P, ACol, ARow);
end;

procedure TTyCustomDBGrid.RenderHeaderSections(P: TTyPainter; const M: TTyGridMetrics;
  AHeaderH: Integer);
var
  i, l, w, bandTop: Integer;
begin
  inherited RenderHeaderSections(P, M, AHeaderH);
  if not Assigned(FOnDrawColumnTitle) or (csDesigning in ComponentState) then Exit;
  { The sections' own geometry (TTyCustomGrid.RenderHeaderSections). }
  bandTop := GroupBandHeightPx;
  for i := 0 to Columns.Count - 1 do
  begin
    if not Columns[i].Visible then Continue;
    l := ColumnLeftPx(i);
    w := ColumnWidthPx(i);
    if (w <= 0) or (l >= M.ClientW) or (l + w <= 0) then Continue;
    if not ClipColToBody(M, i, l, w) then Continue;
    FOnDrawColumnTitle(Self, Rect(l, bandTop, l + w, bandTop + AHeaderH), i, Columns[i], [gdFixed], P);
  end;
end;

procedure TTyCustomDBGrid.DoGetCellStyle(ACol, ARow: Integer;
  var AAppearance: TTyGridCellAppearance);
var
  before: TTyFill;
  old: Integer;
begin
  inherited DoGetCellStyle(ACol, ARow, AAppearance);
  if not Assigned(FOnPrepareCanvas) or (FDataLink = nil) or not FDataLink.Active
    or (ARow < 0) or (ARow >= FDataLink.RecordCount) then Exit;
  before := AAppearance.Background;
  old := FDataLink.ActiveRecord;
  FDataLink.ActiveRecord := ARow;
  try
    FOnPrepareCanvas(Self, ACol, DBColumn(ACol), DrawStateOf(ACol, ARow), AAppearance);
  finally
    FDataLink.ActiveRecord := old;
  end;
  { As the string grid's own OnGetCellStyle: a background the handler set is the cell's
    (drawn, and kept under the decoration layers). }
  AAppearance.HasBackground := AAppearance.Background.Kind <> tfkNone;
  if AAppearance.HasBackground
    and ((before.Kind <> AAppearance.Background.Kind)
         or (before.Color <> AAppearance.Background.Color)) then
    AAppearance.HasExplicitBackground := True;
end;

procedure TTyCustomDBGrid.InvokeEllipsis(ACol, ARow: Integer);
begin
  { LCL's EditButtonClicked: the column's button was pressed. The string grid's own
    OnEllipsisClick (which may write a value) follows. }
  if Assigned(FOnEditButtonClick) and not (csDesigning in ComponentState) then
    FOnEditButtonClick(Self);
  inherited InvokeEllipsis(ACol, ARow);
end;

procedure TTyCustomDBGrid.CursorMoved(AOldCol, AOldRow: Integer);
begin
  inherited CursorMoved(AOldCol, AOldRow);
  if (Col <> AOldCol) and Assigned(FOnColEnter) and not (csDesigning in ComponentState) then
    FOnColEnter(Self);
end;

procedure TTyCustomDBGrid.HeaderSectionClicked(ACol: Integer);
begin
  inherited HeaderSectionClicked(ACol);
  if Assigned(FOnTitleClick) and not (csDesigning in ComponentState)
    and (DBColumn(ACol) <> nil) then
    FOnTitleClick(DBColumn(ACol));
end;

procedure TTyCustomDBGrid.ColumnSized(ACol: Integer);
begin
  inherited ColumnSized(ACol);
  if Assigned(FOnColumnSized) and not (csDesigning in ComponentState) then
    FOnColumnSized(Self);
end;

procedure TTyCustomDBGrid.ColumnMoved(AFromPos, AToPos: Integer);
begin
  inherited ColumnMoved(AFromPos, AToPos);
  if Assigned(FOnColumnMoved) and not (csDesigning in ComponentState) then
    FOnColumnMoved(Self, AFromPos, AToPos);
end;

procedure TTyCustomDBGrid.SetOnGetCellHint(AValue: TTyDBGridCellHintEvent);
begin
  FOnGetCellHint := AValue;
  { The string grid sets Hint and ShowHint whenever its own hint event is assigned; it is
    hooked only while the application asks, so the grid's Hint is left alone otherwise. }
  if Assigned(AValue) then
    inherited OnGetCellHint := @BaseCellHint
  else
    inherited OnGetCellHint := nil;
end;

procedure TTyCustomDBGrid.BaseCellHint(Sender: TObject; ACol, ARow: Integer;
  var AHint: string);
var
  old: Integer;
begin
  if not Assigned(FOnGetCellHint) or (FDataLink = nil) or not FDataLink.Active
    or (ARow < 0) or (ARow >= FDataLink.RecordCount) then Exit;
  old := FDataLink.ActiveRecord;
  FDataLink.ActiveRecord := ARow;
  try
    FOnGetCellHint(Self, DBColumn(ACol), AHint);
  finally
    FDataLink.ActiveRecord := old;
  end;
end;

procedure TTyCustomDBGrid.ProvideEditLink(Sender: TObject; ACol, ARow: Integer;
  var ALink: TTyGridEditLink);
var
  ed: TWinControl;
begin
  if Assigned(FUserCreateEditLink) then FUserCreateEditLink(Self, ACol, ARow, ALink);
  if (ALink <> nil) or not Assigned(FOnSelectEditor) then Exit;
  ed := nil;
  FOnSelectEditor(Self, DBColumn(ACol), ed);
  if (ed = nil) or (ed = Self) then Exit;
  TTyDBGridControlLink(FControlLink).Control := ed;
  ALink := FControlLink;
end;

initialization
  { A theme that says nothing about the data-aware grid styles it as the grid. }
  TyTryRegisterTypeKeyParent('TyDBGrid', 'TyGrid');

finalization
  TyUnregisterTypeKeyParent('TyDBGrid');

end.
