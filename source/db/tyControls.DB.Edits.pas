unit tyControls.DB.Edits;
{$mode objfpc}{$H+}
{ The data-aware edits (issue #34). The text controls TTyDBEdit, TTyDBMaskEdit, TTyDBMemo and
  TTyDBText are LCL's TDBEdit / TDBMemo / TDBText on the library's own controls; the numeric
  ones -- TTyDBNumericEdit, TTyDBCurrencyEdit, TTyDBSpinEdit, TTyDBFloatSpinEdit -- have no LCL
  counterpart (LCL can only bind a number field to a text edit) and read and write the field
  as the number it is.

  Each is split the way the rest of the library is: TTyCustomDBXxx holds the data link and all
  the code, TTyDBXxx publishes the base control's list unchanged and the data properties after
  it. DataSource, DataField, ReadOnly and Field are public on the custom class, as on LCL's
  TCustomDBComboBox / TCustomDBListBox.

  HOW A CONTROL TELLS THE USER'S EDIT FROM ITS OWN LOAD. Every one of these base controls fires
  its change notification when code sets the text, so the notification alone says nothing. A
  control loads the field in DataChange with FLoading set and remembers what it then showed
  (FLoaded); a change counts as the user's only when it arrives outside a load AND the value
  differs from what was loaded. Then the dataset goes into dsEdit and the link is marked
  modified (TyDBUserChanged); if the dataset cannot be edited the control is reset to the field.
  Keys that would change the text ask first, as LCL does, and are dropped when editing cannot
  begin; the change check catches everything else (paste, cut, undo, an IME commit).

  The value goes back to the field on EditingDone (Enter in an edit) and when the control loses
  focus; a Post made elsewhere writes it too, because the link is marked modified. Escape, while
  the dataset is being edited, puts the field's value back.

  The base controls' Text (and the memo's Lines) are not stored in a form file: the field is
  where the value lives, as in LCL, whose TDBEdit does not publish Text and whose TDBMemo and
  TDBText skip Lines and Caption when a form is read. }
interface

uses
  Classes, SysUtils, Controls, LCLType, LMessages, DB, DBCtrls,
  tyControls.Edit, tyControls.MaskEdit, tyControls.Memo, tyControls.TyLabel,
  tyControls.NumericEdit, tyControls.CurrencyEdit, tyControls.SpinEdit, tyControls.FloatSpinEdit,
  tyControls.DB.Common;

type
  { A one-line edit bound to a field. Shows Field.Text while it has focus and the field can be
    changed, Field.DisplayText otherwise; writes Field.Text back. A string field sets MaxLength
    to its size when MaxLength is 0, and the field's Alignment is copied, as in LCL. }
  TTyCustomDBEdit = class(TTyCustomEdit)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FLoaded: TTyDBLoadedValue;
    { Between DoEnter and DoExit: the field is shown in its editable form (LCL's
      FFocusedDisplay). Kept as a flag rather than read from Focused so the display follows the
      focus messages, not the widget's state at the moment DataChange runs. }
    FFocusedDisplay: Boolean;
    { MaxLength came from the field's size, not from the author; a later field that is not a
      string field takes it back to 0 instead of inheriting a limit nobody set. }
    FFieldMaxLength: Boolean;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure ValueChanged(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure EditingDone; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    { The control's own read-only switch, and the link's: either one keeps the field as it
      is (LCL's GetReadOnly / SetReadOnly). }
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    property Text stored False;
  end;

  { TTyDBEdit publishes TTyCustomDBEdit's properties; everything lives in TTyCustomDBEdit. }
  TTyDBEdit = class(TTyCustomDBEdit)
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
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
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
    property Action;
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
    property Text;
    property ReadOnly;
    property MaxLength;
    property PasswordChar;
    property EchoMode;
    property HideSelection;
    property AutoSelect;
    property TextHint;
    property Alignment;
    property CharCase;
    property NumbersOnly;
    property Align;
    property Anchors;
    property OnChange;
    property DataField;
    property DataSource;
  end;

  { A masked edit bound to a field. With CustomEditMask False (the default, as in LCL) the
    field's EditMask is applied; a field mask this control cannot parse -- the '#' code, which
    it refuses -- is left off rather than raising. With a mask in force the control shows and
    edits Field.Text and writes back MaskedValue (the literals kept only when the mask says
    ';1;'); an empty field writes an empty value without being validated, so a masked field
    can still be cleared. Without a mask it behaves as TTyDBEdit. }
  TTyCustomDBMaskEdit = class(TTyCustomMaskEdit)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FLoaded: TTyDBLoadedValue;
    FFocusedDisplay: Boolean;
    FFieldMaxLength: Boolean;
    FCustomEditMask: Boolean;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    function GetMask: string;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    procedure SetCustomEditMask(AValue: Boolean);
    procedure SetDBMask(const AValue: string);
    procedure ApplyFieldMask(const AMask: string);
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure ValueChanged(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure EditingDone; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    { False: the field's EditMask is the mask. True: Mask / EditMask are the author's. }
    property CustomEditMask: Boolean read FCustomEditMask write SetCustomEditMask default False;
    { A new mask empties a masked edit; these two load the field's value again afterwards. }
    property Mask: string read GetMask write SetDBMask;
    property EditMask: string read GetMask write SetDBMask stored False;
    property Text stored False;
  end;

  { TTyDBMaskEdit publishes TTyCustomDBMaskEdit's properties; everything lives in TTyCustomDBMaskEdit. }
  TTyDBMaskEdit = class(TTyCustomDBMaskEdit)
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
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
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
    property Action;
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
    property Text;
    property ReadOnly;
    property MaxLength;
    property PasswordChar;
    property EchoMode;
    property HideSelection;
    property AutoSelect;
    property TextHint;
    property Alignment;
    property CharCase;
    property NumbersOnly;
    property Align;
    property Anchors;
    property OnChange;
    property Mask;
    property SpaceChar;
    property EditMask;
    property CustomEditMask;
    property DataField;
    property DataSource;
  end;

  { A memo bound to a field. A blob (memo) field is loaded with AsString -- or Text when the
    field has an OnGetText -- and with AutoDisplay False shows '(DisplayLabel)' until the user
    presses Enter (or code calls LoadMemo). Any other field is shown like TTyDBEdit shows it.
    Writes back AsString, or Text when the field has an OnSetText (LCL's rules). Lines.Add
    and the like change the memo without notifying it and are not edits of the field. }
  TTyCustomDBMemo = class(TTyCustomMemo)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FLoaded: TTyDBLoadedValue;
    FFocusedDisplay: Boolean;
    FAutoDisplay: Boolean;
    { The memo holds the field's value, not the '(Note)' stand-in (LCL's FDBMemoLoaded).
      Nothing is typed into, or written back from, a memo that does not. }
    FMemoLoaded: Boolean;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    procedure SetAutoDisplay(AValue: Boolean);
    { Text without the line break TStrings.Text puts after the last line: what the user
      typed, and what goes into the field. }
    function MemoValue: string;
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure ValueChanged(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure EditingDone; override;
    { Load a blob field that AutoDisplay left unloaded. }
    procedure LoadMemo; virtual;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    property AutoDisplay: Boolean read FAutoDisplay write SetAutoDisplay default True;
    property Lines stored False;
    property Text stored False;
  end;

  { TTyDBMemo publishes TTyCustomDBMemo's properties; everything lives in TTyCustomDBMemo. }
  TTyDBMemo = class(TTyCustomDBMemo)
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
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
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
    property Action;
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
    property Lines;
    property Text;
    property WantTabs;
    property WantReturns;
    property ScrollBars;
    property ScrollBarAutoHide;
    property WordWrap;
    property ReadOnly;
    property HideSelection;
    property Alignment;
    property CharCase;
    property MaxLength;
    property Align;
    property Anchors;
    property OnChange;
    property OnSelectionChange;
    property AutoDisplay;
    property DataField;
    property DataSource;
  end;

  { A label showing a field's DisplayText. Without a field it is empty -- except in the form
    designer, where it shows its Name so it can be found and picked (LCL's TDBText). }
  TTyCustomDBText = class(TTyCustomLabel)
  private
    FDataLink: TFieldDataLink;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure DataChange(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure SetName(const AValue: TComponentName); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property Caption stored False;
  end;

  { TTyDBText publishes TTyCustomDBText's properties; everything lives in TTyCustomDBText. }
  TTyDBText = class(TTyCustomDBText)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
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
    property AutoSize;
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
    property Action;
    property OnPaint;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Caption;
    property Align;
    property Anchors;
    property Alignment;
    property Layout;
    property WordWrap;
    property Transparent;
    property FocusControl;
    property DataField;
    property DataSource;
  end;

  { A number edit bound to a field. Loads and writes the field as a number (AsFloat, AsCurrency
    or AsInteger by its type; never through Text, so the locale's DecimalSeparator does not
    matter). NULL shows as an empty field and an emptied field writes NULL. A value outside
    MinValue..MaxValue shows clamped; it is only written back if the user changes it. }
  TTyCustomDBNumericEdit = class(TTyCustomNumericEdit)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FLoaded: TTyDBLoadedValue;
    { Between DoEnter and DoExit. A reload shows the raw (editing) form then -- the base
      control asks Focused, which is not set yet while focus is still arriving. }
    FFocusedDisplay: Boolean;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    { No number in the field: the control's "no value", written back as NULL. }
    function IsBlank: Boolean;
    function GetMinValue: Double;
    function GetMaxValue: Double;
    procedure SetMinValue(const AValue: Double);
    procedure SetMaxValue(const AValue: Double);
    procedure SetRange(AMin, AMax: Double);
    function GetDecimals: Integer;
    procedure SetDecimals(AValue: Integer);
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure ValueChanged(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure EditingDone; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    { A range set after the control is bound shows the value clamped to it, the way a load
      does: that is the program's doing, not an edit. The field keeps its value until the
      user changes the control (plan D6). }
    property MinValue: Double read GetMinValue write SetMinValue;
    property MaxValue: Double read GetMaxValue write SetMaxValue;
    { The same for a Decimals set after binding: the display is rounded again, the field is
      not edited. An untouched control shows the field again at the new precision. }
    property Decimals: Integer read GetDecimals write SetDecimals default 2;
    property Text stored False;
  end;

  { TTyDBNumericEdit publishes TTyCustomDBNumericEdit's properties; everything lives in TTyCustomDBNumericEdit. }
  TTyDBNumericEdit = class(TTyCustomDBNumericEdit)
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
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
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
    property Action;
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
    property Text;
    property ReadOnly;
    property MaxLength;
    property PasswordChar;
    property EchoMode;
    property HideSelection;
    property AutoSelect;
    property TextHint;
    property Alignment;
    property CharCase;
    property NumbersOnly;
    property Align;
    property Anchors;
    property OnChange;
    property Decimals;
    property UseThousands;
    property MinValue;
    property MaxValue;
    property DataField;
    property DataSource;
  end;

  { A currency edit bound to a field: TTyDBNumericEdit with the currency symbol on the
    display. A currency field is read and written with AsCurrency. }
  TTyCustomDBCurrencyEdit = class(TTyCustomCurrencyEdit)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FLoaded: TTyDBLoadedValue;
    { Between DoEnter and DoExit. A reload shows the raw (editing) form then -- the base
      control asks Focused, which is not set yet while focus is still arriving. }
    FFocusedDisplay: Boolean;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    { No number in the field: the control's "no value", written back as NULL. }
    function IsBlank: Boolean;
    function GetMinValue: Double;
    function GetMaxValue: Double;
    procedure SetMinValue(const AValue: Double);
    procedure SetMaxValue(const AValue: Double);
    procedure SetRange(AMin, AMax: Double);
    function GetDecimals: Integer;
    procedure SetDecimals(AValue: Integer);
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure ValueChanged(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure EditingDone; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    { A range set after the control is bound shows the value clamped to it, the way a load
      does: that is the program's doing, not an edit. The field keeps its value until the
      user changes the control (plan D6). }
    property MinValue: Double read GetMinValue write SetMinValue;
    property MaxValue: Double read GetMaxValue write SetMaxValue;
    { The same for a Decimals set after binding: the display is rounded again, the field is
      not edited. An untouched control shows the field again at the new precision. }
    property Decimals: Integer read GetDecimals write SetDecimals default 2;
    property Text stored False;
  end;

  { TTyDBCurrencyEdit publishes TTyCustomDBCurrencyEdit's properties; everything lives in TTyCustomDBCurrencyEdit. }
  TTyDBCurrencyEdit = class(TTyCustomDBCurrencyEdit)
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
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
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
    property Action;
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
    property Text;
    property ReadOnly;
    property MaxLength;
    property PasswordChar;
    property EchoMode;
    property HideSelection;
    property AutoSelect;
    property TextHint;
    property Alignment;
    property CharCase;
    property NumbersOnly;
    property Align;
    property Anchors;
    property OnChange;
    property Decimals;
    property UseThousands;
    property MinValue;
    property MaxValue;
    property CurrencySymbol;
    property SymbolBefore;
    property DataField;
    property DataSource;
  end;

  { A decimal spin edit bound to a field: TTyDBNumericEdit with the step buttons. A step is
    an edit like a typed digit, refused the same way when the dataset cannot be edited. }
  TTyCustomDBFloatSpinEdit = class(TTyCustomFloatSpinEdit)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FLoaded: TTyDBLoadedValue;
    { Between DoEnter and DoExit. A reload shows the raw (editing) form then -- the base
      control asks Focused, which is not set yet while focus is still arriving. }
    FFocusedDisplay: Boolean;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    { No number in the field: the control's "no value", written back as NULL. }
    function IsBlank: Boolean;
    function GetMinValue: Double;
    function GetMaxValue: Double;
    procedure SetMinValue(const AValue: Double);
    procedure SetMaxValue(const AValue: Double);
    procedure SetRange(AMin, AMax: Double);
    function GetDecimals: Integer;
    procedure SetDecimals(AValue: Integer);
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure ValueChanged(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure EditingDone; override;
    { A step is an edit: refused, like a key, when the dataset cannot be edited. }
    procedure StepValue(ADelta: Double); override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    { A range set after the control is bound shows the value clamped to it, the way a load
      does: that is the program's doing, not an edit. The field keeps its value until the
      user changes the control (plan D6). }
    property MinValue: Double read GetMinValue write SetMinValue;
    property MaxValue: Double read GetMaxValue write SetMaxValue;
    { The same for a Decimals set after binding: the display is rounded again, the field is
      not edited. An untouched control shows the field again at the new precision. }
    property Decimals: Integer read GetDecimals write SetDecimals default 2;
    property Text stored False;
  end;

  { TTyDBFloatSpinEdit publishes TTyCustomDBFloatSpinEdit's properties; everything lives in TTyCustomDBFloatSpinEdit. }
  TTyDBFloatSpinEdit = class(TTyCustomDBFloatSpinEdit)
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
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
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
    property Action;
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
    property Text;
    property ReadOnly;
    property MaxLength;
    property PasswordChar;
    property EchoMode;
    property HideSelection;
    property AutoSelect;
    property TextHint;
    property Alignment;
    property CharCase;
    property NumbersOnly;
    property Align;
    property Anchors;
    property OnChange;
    property Decimals;
    property UseThousands;
    property MinValue;
    property MaxValue;
    property Increment;
    property EditorEnabled;
    property DataField;
    property DataSource;
  end;

  { An integer spin edit bound to a field, read and written as a number. NULL shows as an empty
    field (ValueEmpty); the base control has no gesture that empties it, so the user cannot write
    NULL back. A step (arrow key, wheel, button) and a typed digit are edits, refused when the
    dataset cannot be edited -- before they move the value, so no OnValueChange fires for a
    refused one. Enter writes the value back, as it does in the text edits. }
  TTyCustomDBSpinEdit = class(TTyCustomSpinEdit)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FLoaded: TTyDBLoadedValue;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    { Is (X, Y) on the up or the down button? The same rects the base control hit-tests. }
    function OnSpinButton(X, Y: Integer): Boolean;
    function GetMinValue: Integer;
    function GetMaxValue: Integer;
    procedure SetMinValue(const AValue: Integer);
    procedure SetMaxValue(const AValue: Integer);
    procedure SetRange(AMin, AMax: Integer);
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DoChange; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure EditingDone; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    { As in TTyDBNumericEdit: a range set from code re-clamps the display and is not an edit.
      A NULL field stays blank (ValueEmpty) under the new range. }
    property MinValue: Integer read GetMinValue write SetMinValue default 0;
    property MaxValue: Integer read GetMaxValue write SetMaxValue default 0;
    property Value stored False;
  end;

  { TTyDBSpinEdit publishes TTyCustomDBSpinEdit's properties; everything lives in TTyCustomDBSpinEdit. }
  TTyDBSpinEdit = class(TTyCustomDBSpinEdit)
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
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
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
    property Action;
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
    property MinValue;
    property MaxValue;
    property Value;
    property Increment;
    property ReadOnly;
    property EditorEnabled;
    property Alignment;
    property MaxLength;
    property ValueEmpty;
    property TextHint;
    property OnChange;
    property OnValueChange;
    property Align;
    property Anchors;
    property DataField;
    property DataSource;
  end;

implementation

uses
  Types, tyControls.Types, tyControls.Controller, tyControls.StyleModel;

const
  CStringFieldTypes = [ftString, ftFixedChar, ftWideString, ftFixedWideChar];

{ ======================================================================= TTyCustomDBEdit == }

constructor TTyCustomDBEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
  { The multicast list, not OnChange: OnChange belongs to the application. }
  AddHandlerOnChange(@ValueChanged);
end;

destructor TTyCustomDBEdit.Destroy;
begin
  { The link goes first, with its callbacks cut, and every handler that can still run while
    the inherited destructor takes focus away (DoExit, the change handler) checks for nil. }
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBEdit.GetStyleTypeKey: string;
begin
  Result := 'TyDBEdit';
end;

function TTyCustomDBEdit.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBEdit.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBEdit.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBEdit.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBEdit.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBEdit.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBEdit.SetReadOnly(AValue: Boolean);
begin
  TTyCustomEdit(Self).ReadOnly := AValue;   // the edit itself refuses input...
  FDataLink.ReadOnly := AValue;             // ...and the link refuses to start editing
end;

procedure TTyCustomDBEdit.DataChange(Sender: TObject);
var
  f: TField;
begin
  if FInUserEdit then Exit;   // the dataset entering dsEdit for the user's change: keep it
  f := FDataLink.Field;
  FLoading := True;
  try
    if f <> nil then
    begin
      Alignment := f.Alignment;
      if f.DataType in CStringFieldTypes then
      begin
        if (MaxLength = 0) or FFieldMaxLength then
        begin
          MaxLength := f.Size;
          FFieldMaxLength := True;
        end;
      end
      else if FFieldMaxLength then
      begin
        MaxLength := 0;
        FFieldMaxLength := False;
      end;
      if FFocusedDisplay and FDataLink.CanModify then
        Text := f.Text
      else
        Text := f.DisplayText;
    end
    else
    begin
      if FFieldMaxLength then
      begin
        MaxLength := 0;
        FFieldMaxLength := False;
      end;
      Text := '';
    end;
    FLoaded := TyDBLoadedText(Text);
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBEdit.UpdateData(Sender: TObject);
begin
  FDataLink.Field.Text := Text;
  FLoaded := TyDBLoadedText(Text);   // what the field holds now: changing back is an edit again
end;

procedure TTyCustomDBEdit.ValueChanged(Sender: TObject);
begin
  if FLoading or FInUserEdit or (FDataLink = nil) or (FDataLink.Field = nil) then Exit;
  if Text = FLoaded.Text then Exit;
  TyDBUserChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBEdit.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBEdit.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

procedure TTyCustomDBEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  { The base control erases as it handles the key, so the question comes first. }
  if ((Key = VK_BACK) or (Key = VK_DELETE)) and not TyDBEditAllowed(FDataLink, FInUserEdit) then
  begin
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and FDataLink.Editing then
  begin
    FDataLink.Reset;
    SelectAll;
    Key := 0;
  end;
end;

procedure TTyCustomDBEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if (UTF8Key <> '') and (UTF8Key[1] >= #32) and not TyDBKeyAllowed(FDataLink, UTF8Key, FInUserEdit) then
  begin
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TTyCustomDBEdit.DoEnter;
begin
  { Before inherited, so OnEnter and AutoSelect see the editable form of the value. }
  if not FFocusedDisplay then
  begin
    FFocusedDisplay := True;
    if FDataLink.Field <> nil then FDataLink.Reset;
  end;
  inherited DoEnter;
end;

procedure TTyCustomDBEdit.DoExit;
begin
  inherited DoExit;
  FFocusedDisplay := False;
  if (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  if FDataLink.Editing then
    FDataLink.UpdateRecord;   // writes only what this control changed
  { Show the field again, formatted; a value that failed to write raised above and stays
    on screen to be corrected. }
  if FDataLink.Field <> nil then FDataLink.Reset;
end;

procedure TTyCustomDBEdit.EditingDone;
begin
  if (FDataLink <> nil) and FDataLink.Editing then
    FDataLink.UpdateRecord;
  inherited EditingDone;
end;

function TTyCustomDBEdit.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBEdit.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ =================================================================== TTyCustomDBMaskEdit == }

constructor TTyCustomDBMaskEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
  AddHandlerOnChange(@ValueChanged);
end;

destructor TTyCustomDBMaskEdit.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBMaskEdit.GetStyleTypeKey: string;
begin
  Result := 'TyDBMaskEdit';
end;

function TTyCustomDBMaskEdit.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBMaskEdit.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBMaskEdit.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBMaskEdit.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

function TTyCustomDBMaskEdit.GetMask: string;
begin
  Result := inherited Mask;
end;

procedure TTyCustomDBMaskEdit.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBMaskEdit.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBMaskEdit.SetReadOnly(AValue: Boolean);
begin
  TTyCustomMaskEdit(Self).ReadOnly := AValue;
  FDataLink.ReadOnly := AValue;
end;

procedure TTyCustomDBMaskEdit.SetCustomEditMask(AValue: Boolean);
begin
  if FCustomEditMask = AValue then Exit;
  FCustomEditMask := AValue;
  { Back to the field's mask, or keeping the one in force: either way, show the field again. }
  if FDataLink.Field <> nil then FDataLink.Reset;
end;

procedure TTyCustomDBMaskEdit.SetDBMask(const AValue: string);
begin
  FLoading := True;   // the mask empties the text; that is not the user clearing the field
  try
    inherited Mask := AValue;
  finally
    FLoading := False;
  end;
  if FDataLink.Field <> nil then FDataLink.Reset;
end;

procedure TTyCustomDBMaskEdit.ApplyFieldMask(const AMask: string);
var
  m: string;
begin
  m := AMask;
  if TyMaskRejectReason(m) <> '' then m := '';   // e.g. '#': refused here, so not applied
  if GetMask <> m then inherited Mask := m;
end;

procedure TTyCustomDBMaskEdit.DataChange(Sender: TObject);
var
  f: TField;
begin
  if FInUserEdit then Exit;
  f := FDataLink.Field;
  FLoading := True;
  try
    if f <> nil then
    begin
      if not FCustomEditMask then ApplyFieldMask(f.EditMask);
      Alignment := f.Alignment;
      if f.DataType in CStringFieldTypes then
      begin
        if (MaxLength = 0) or FFieldMaxLength then
        begin
          MaxLength := f.Size;
          FFieldMaxLength := True;
        end;
      end
      else if FFieldMaxLength then
      begin
        MaxLength := 0;
        FFieldMaxLength := False;
      end;
      { A mask shapes the EDITABLE form; DisplayText may not fit it at all. }
      if (GetMask <> '') or (FFocusedDisplay and FDataLink.CanModify) then
        Text := f.Text
      else
        Text := f.DisplayText;
    end
    else
    begin
      if not FCustomEditMask then ApplyFieldMask('');
      if FFieldMaxLength then
      begin
        MaxLength := 0;
        FFieldMaxLength := False;
      end;
      Text := '';
    end;
    FLoaded := TyDBLoadedText(Text);
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBMaskEdit.UpdateData(Sender: TObject);
begin
  if GetMask = '' then
    FDataLink.Field.Text := Text
  else if MaskedValue = '' then
    FDataLink.Field.Text := ''
  else
  begin
    ValidateEdit;   // a half-filled mask raises here, before anything is written (LCL)
    FDataLink.Field.Text := MaskedValue;
  end;
  FLoaded := TyDBLoadedText(Text);   // what the field holds now: changing back is an edit again
end;

procedure TTyCustomDBMaskEdit.ValueChanged(Sender: TObject);
begin
  if FLoading or FInUserEdit or (FDataLink = nil) or (FDataLink.Field = nil) then Exit;
  if Text = FLoaded.Text then Exit;
  TyDBUserChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBMaskEdit.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBMaskEdit.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

procedure TTyCustomDBMaskEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if ((Key = VK_BACK) or (Key = VK_DELETE)) and not TyDBEditAllowed(FDataLink, FInUserEdit) then
  begin
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and FDataLink.Editing then
  begin
    FDataLink.Reset;
    SelectAll;
    Key := 0;
  end;
end;

procedure TTyCustomDBMaskEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if (UTF8Key <> '') and (UTF8Key[1] >= #32) and not TyDBKeyAllowed(FDataLink, UTF8Key, FInUserEdit) then
  begin
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TTyCustomDBMaskEdit.DoEnter;
begin
  if not FFocusedDisplay then
  begin
    FFocusedDisplay := True;
    if FDataLink.Field <> nil then FDataLink.Reset;
  end;
  inherited DoEnter;
end;

procedure TTyCustomDBMaskEdit.DoExit;
begin
  { The base validates a changed, half-filled mask here and raises; nothing is written then. }
  inherited DoExit;
  FFocusedDisplay := False;
  if (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  if FDataLink.Editing then
    FDataLink.UpdateRecord;
  if FDataLink.Field <> nil then FDataLink.Reset;
end;

procedure TTyCustomDBMaskEdit.EditingDone;
begin
  if (FDataLink <> nil) and FDataLink.Editing then
    FDataLink.UpdateRecord;
  inherited EditingDone;
end;

function TTyCustomDBMaskEdit.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBMaskEdit.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ======================================================================= TTyCustomDBMemo == }

constructor TTyCustomDBMemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FAutoDisplay := True;
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
  AddHandlerOnChange(@ValueChanged);
end;

destructor TTyCustomDBMemo.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBMemo.GetStyleTypeKey: string;
begin
  Result := 'TyDBMemo';
end;

function TTyCustomDBMemo.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBMemo.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBMemo.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBMemo.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBMemo.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBMemo.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBMemo.SetReadOnly(AValue: Boolean);
begin
  TTyCustomMemo(Self).ReadOnly := AValue;
  FDataLink.ReadOnly := AValue;
end;

procedure TTyCustomDBMemo.SetAutoDisplay(AValue: Boolean);
begin
  if FAutoDisplay = AValue then Exit;
  FAutoDisplay := AValue;
  if FAutoDisplay then LoadMemo;
end;

function TTyCustomDBMemo.MemoValue: string;
begin
  Result := Text;
  if (Lines.Count > 0) and (Copy(Result, Length(Result) - Length(LineEnding) + 1,
    Length(LineEnding)) = LineEnding) then
    SetLength(Result, Length(Result) - Length(LineEnding));
end;

procedure TTyCustomDBMemo.LoadMemo;
var
  s: string;
  wasLoading: Boolean;
begin
  if FMemoLoaded or (FDataLink.Field = nil) or not FDataLink.Field.IsBlob then Exit;
  wasLoading := FLoading;
  FLoading := True;
  try
    try
      { A field with OnGetText gets to say what the memo shows (LCL issue #33598). }
      if Assigned(FDataLink.Field.OnGetText) then
        s := FDataLink.Field.Text
      else
        s := FDataLink.Field.AsString;
      if MemoValue <> s then Text := s;
      FMemoLoaded := True;
    except
      on E: EInvalidOperation do
        Text := '(' + E.Message + ')';
    end;
    FLoaded := TyDBLoadedText(Text);
  finally
    FLoading := wasLoading;
  end;
end;

procedure TTyCustomDBMemo.DataChange(Sender: TObject);
var
  f: TField;
begin
  if FInUserEdit then Exit;
  f := FDataLink.Field;
  FLoading := True;
  try
    if f <> nil then
    begin
      if f.IsBlob then
      begin
        if FAutoDisplay or (FDataLink.Editing and FMemoLoaded) then
        begin
          FMemoLoaded := False;
          LoadMemo;
        end
        else
        begin
          Text := Format('(%s)', [f.DisplayLabel]);
          FMemoLoaded := False;
        end;
      end
      else
      begin
        if FFocusedDisplay and FDataLink.CanModify then
          Text := f.Text
        else
          Text := f.DisplayText;
        FMemoLoaded := True;
      end;
    end
    else
    begin
      if csDesigning in ComponentState then Text := Name else Text := '';
      FMemoLoaded := False;
    end;
    FLoaded := TyDBLoadedText(Text);
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBMemo.UpdateData(Sender: TObject);
begin
  if not FMemoLoaded or not FDataLink.CanModify then Exit;
  { A field with OnSetText gets to take the text apart (LCL issue #33498). }
  if Assigned(FDataLink.Field.OnSetText) then
    FDataLink.Field.Text := MemoValue
  else
    FDataLink.Field.AsString := MemoValue;
  FLoaded := TyDBLoadedText(Text);   // what the field holds now: changing back is an edit again
end;

procedure TTyCustomDBMemo.ValueChanged(Sender: TObject);
begin
  if FLoading or FInUserEdit or (FDataLink = nil) or (FDataLink.Field = nil) then Exit;
  if Text = FLoaded.Text then Exit;
  if not FMemoLoaded then
  begin
    { Something (a paste) went into the '(Note)' stand-in: it is not the field's text, and
      nothing written over it can be either. }
    FDataLink.Reset;
    Exit;
  end;
  TyDBUserChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBMemo.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBMemo.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

procedure TTyCustomDBMemo.KeyDown(var Key: Word; Shift: TShiftState);
begin
  { Enter on the '(Note)' stand-in loads the memo instead of starting a new line. }
  if (Key = VK_RETURN) and not FMemoLoaded and (FDataLink.Field <> nil) then
  begin
    LoadMemo;
    Key := 0;
    Exit;
  end;
  if ((Key = VK_BACK) or (Key = VK_DELETE))
    and not (FMemoLoaded and TyDBEditAllowed(FDataLink, FInUserEdit)) then
  begin
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and FDataLink.Editing then
  begin
    FDataLink.Reset;
    SelectAll;
    Key := 0;
  end;
end;

procedure TTyCustomDBMemo.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if (UTF8Key <> '') and (UTF8Key[1] >= #32)
    and not (FMemoLoaded and TyDBKeyAllowed(FDataLink, UTF8Key, FInUserEdit)) then
  begin
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TTyCustomDBMemo.DoEnter;
begin
  if not FFocusedDisplay then
  begin
    FFocusedDisplay := True;
    if FDataLink.Field <> nil then FDataLink.Reset;
  end;
  inherited DoEnter;
end;

procedure TTyCustomDBMemo.DoExit;
begin
  inherited DoExit;
  FFocusedDisplay := False;
  if (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  if FDataLink.Editing then
    FDataLink.UpdateRecord;
  if FDataLink.Field <> nil then FDataLink.Reset;
end;

procedure TTyCustomDBMemo.EditingDone;
begin
  if FDataLink <> nil then
  begin
    if FDataLink.Editing then
      FDataLink.UpdateRecord
    else if FDataLink.Field <> nil then
      FDataLink.Reset;   // LCL: an untouched memo shows the field again
  end;
  inherited EditingDone;
end;

function TTyCustomDBMemo.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBMemo.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ======================================================================= TTyCustomDBText == }

constructor TTyCustomDBText.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { Not csSetCaption: naming the label would put its Name in the caption at run time too. In
    the designer SetName does that on purpose. }
  ControlStyle := ControlStyle - [csSetCaption] + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
end;

destructor TTyCustomDBText.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBText.GetStyleTypeKey: string;
begin
  Result := 'TyDBText';
end;

function TTyCustomDBText.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBText.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBText.GetField: TField;
begin
  Result := FDataLink.Field;
end;

procedure TTyCustomDBText.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBText.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBText.DataChange(Sender: TObject);
begin
  if FDataLink.Field <> nil then
    Caption := FDataLink.Field.DisplayText
  else if csDesigning in ComponentState then
    Caption := Name   // otherwise an unbound label is an empty, unfindable box on the form
  else
    Caption := '';
end;

procedure TTyCustomDBText.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBText.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

procedure TTyCustomDBText.SetName(const AValue: TComponentName);
begin
  inherited SetName(AValue);
  if (csDesigning in ComponentState) and (FDataLink.Field = nil) then DataChange(nil);
end;

procedure TTyCustomDBText.Loaded;
begin
  inherited Loaded;
  DataChange(nil);
end;

function TTyCustomDBText.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBText.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ============================================================== TTyCustomDBNumericEdit == }

constructor TTyCustomDBNumericEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  EmptyAllowed := True;   // an empty field is NULL, and leaving it must not make it 0.00
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
  AddHandlerOnChange(@ValueChanged);
  Text := '';             // unbound, there is no value to show
end;

destructor TTyCustomDBNumericEdit.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBNumericEdit.GetStyleTypeKey: string;
begin
  Result := 'TyDBNumericEdit';
end;

function TTyCustomDBNumericEdit.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBNumericEdit.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBNumericEdit.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBNumericEdit.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBNumericEdit.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBNumericEdit.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBNumericEdit.SetReadOnly(AValue: Boolean);
begin
  TTyCustomEdit(Self).ReadOnly := AValue;
  FDataLink.ReadOnly := AValue;
end;

function TTyCustomDBNumericEdit.IsBlank: Boolean;
begin
  Result := Trim(Text) = '';
end;

function TTyCustomDBNumericEdit.GetMinValue: Double;
begin
  Result := TTyCustomNumericEdit(Self).MinValue;
end;

function TTyCustomDBNumericEdit.GetMaxValue: Double;
begin
  Result := TTyCustomNumericEdit(Self).MaxValue;
end;

procedure TTyCustomDBNumericEdit.SetMinValue(const AValue: Double);
begin
  SetRange(AValue, MaxValue);
end;

procedure TTyCustomDBNumericEdit.SetMaxValue(const AValue: Double);
begin
  SetRange(MinValue, AValue);
end;

{ The base control reformats to the clamped value and fires its change notification; that
  is the display following the program's new range, so it is taken as a load. A control the
  user has not changed shows the field again under the new range -- a range widened past what
  an earlier one clamped shows the field's own value, not the old clamp -- and that is what the
  user's edits are compared with next, as for Decimals (SetDecimals). }
procedure TTyCustomDBNumericEdit.SetRange(AMin, AMax: Double);
var
  was, untouched: Boolean;
begin
  untouched := (FDataLink.Field <> nil) and (IsBlank = FLoaded.IsNull)
    and (IsBlank or (Value = FLoaded.Number));
  was := FLoading;
  FLoading := True;
  try
    TTyCustomNumericEdit(Self).MinValue := AMin;
    TTyCustomNumericEdit(Self).MaxValue := AMax;
  finally
    FLoading := was;
  end;
  if untouched then
    DataChange(nil)
  else
    FLoaded := TyDBLoadedNumber(Value, IsBlank);
end;

function TTyCustomDBNumericEdit.GetDecimals: Integer;
begin
  Result := TTyCustomNumericEdit(Self).Decimals;
end;

{ The base control rounds the display to the new number of places and fires its change
  notification: the program's doing, like a range (SetRange), so it is taken as a load. A
  control the user has not changed shows the field again at the new precision -- not its old
  display rounded once more -- and that is what the user's edits are compared with next. }
procedure TTyCustomDBNumericEdit.SetDecimals(AValue: Integer);
var
  was, untouched: Boolean;
begin
  untouched := (FDataLink.Field <> nil) and (IsBlank = FLoaded.IsNull)
    and (IsBlank or (Value = FLoaded.Number));
  was := FLoading;
  FLoading := True;
  try
    TTyCustomNumericEdit(Self).Decimals := AValue;
  finally
    FLoading := was;
  end;
  if untouched then
    DataChange(nil)
  else
    FLoaded := TyDBLoadedNumber(Value, IsBlank);
end;

procedure TTyCustomDBNumericEdit.DataChange(Sender: TObject);
begin
  if FInUserEdit then Exit;
  FLoading := True;
  try
    if (FDataLink.Field = nil) or FDataLink.Field.IsNull then
      Text := ''
    else
    begin
      Value := TyDBReadNumber(FDataLink.Field);   // clamped to MinValue..MaxValue, as typed
      if FFocusedDisplay then Reformat(False);
    end;
    { What the control made of it -- rounded to Decimals, clamped -- since that is what a
      reformat later shows again. }
    FLoaded := TyDBLoadedNumber(Value, IsBlank);
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBNumericEdit.UpdateData(Sender: TObject);
begin
  if IsBlank then
    FDataLink.Field.Clear
  else
    TyDBWriteNumber(FDataLink.Field, Value);
  FLoaded := TyDBLoadedNumber(Value, IsBlank);   // what the field holds now: changing back is an edit again
end;

procedure TTyCustomDBNumericEdit.ValueChanged(Sender: TObject);
begin
  if FLoading or FInUserEdit or (FDataLink = nil) or (FDataLink.Field = nil) then Exit;
  { The text changes on every focus change (raw while focused, grouped after) without the value
    moving; only a different number, or a number appearing or going, is an edit. }
  if IsBlank = FLoaded.IsNull then
    if IsBlank or (Value = FLoaded.Number) then Exit;
  TyDBUserChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBNumericEdit.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBNumericEdit.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

procedure TTyCustomDBNumericEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if ((Key = VK_BACK) or (Key = VK_DELETE)) and not TyDBEditAllowed(FDataLink, FInUserEdit) then
  begin
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and FDataLink.Editing then
  begin
    FDataLink.Reset;
    SelectAll;
    Key := 0;
  end;
end;

procedure TTyCustomDBNumericEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  { Only for what this control would insert: any other character the base filter drops
    without the dataset being asked. Not the field's IsValidChar -- a float field's takes the
    locale's DecimalSeparator, this control always types a '.'. }
  if (Length(UTF8Key) = 1) and (UTF8Key[1] in ['0'..'9', '-', '.'])
    and not TyDBEditAllowed(FDataLink, FInUserEdit) then
  begin
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TTyCustomDBNumericEdit.DoEnter;
begin
  FFocusedDisplay := True;
  inherited DoEnter;
end;

procedure TTyCustomDBNumericEdit.DoExit;
begin
  FFocusedDisplay := False;
  inherited DoExit;   // regroups and clamps first: what is written is what is shown
  if (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  if FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBNumericEdit.EditingDone;
begin
  if (FDataLink <> nil) and FDataLink.Editing then
    FDataLink.UpdateRecord;
  inherited EditingDone;
end;

function TTyCustomDBNumericEdit.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBNumericEdit.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ============================================================== TTyCustomDBCurrencyEdit == }

constructor TTyCustomDBCurrencyEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  EmptyAllowed := True;   // an empty field is NULL, and leaving it must not make it 0.00
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
  AddHandlerOnChange(@ValueChanged);
  Text := '';             // unbound, there is no value to show
end;

destructor TTyCustomDBCurrencyEdit.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBCurrencyEdit.GetStyleTypeKey: string;
begin
  Result := 'TyDBCurrencyEdit';
end;

function TTyCustomDBCurrencyEdit.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBCurrencyEdit.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBCurrencyEdit.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBCurrencyEdit.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBCurrencyEdit.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBCurrencyEdit.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBCurrencyEdit.SetReadOnly(AValue: Boolean);
begin
  TTyCustomEdit(Self).ReadOnly := AValue;
  FDataLink.ReadOnly := AValue;
end;

function TTyCustomDBCurrencyEdit.IsBlank: Boolean;
begin
  Result := Trim(Text) = '';
end;

function TTyCustomDBCurrencyEdit.GetMinValue: Double;
begin
  Result := TTyCustomNumericEdit(Self).MinValue;
end;

function TTyCustomDBCurrencyEdit.GetMaxValue: Double;
begin
  Result := TTyCustomNumericEdit(Self).MaxValue;
end;

procedure TTyCustomDBCurrencyEdit.SetMinValue(const AValue: Double);
begin
  SetRange(AValue, MaxValue);
end;

procedure TTyCustomDBCurrencyEdit.SetMaxValue(const AValue: Double);
begin
  SetRange(MinValue, AValue);
end;

{ The base control reformats to the clamped value and fires its change notification; that
  is the display following the program's new range, so it is taken as a load. A control the
  user has not changed shows the field again under the new range -- a range widened past what
  an earlier one clamped shows the field's own value, not the old clamp -- and that is what the
  user's edits are compared with next, as for Decimals (SetDecimals). }
procedure TTyCustomDBCurrencyEdit.SetRange(AMin, AMax: Double);
var
  was, untouched: Boolean;
begin
  untouched := (FDataLink.Field <> nil) and (IsBlank = FLoaded.IsNull)
    and (IsBlank or (Value = FLoaded.Number));
  was := FLoading;
  FLoading := True;
  try
    TTyCustomNumericEdit(Self).MinValue := AMin;
    TTyCustomNumericEdit(Self).MaxValue := AMax;
  finally
    FLoading := was;
  end;
  if untouched then
    DataChange(nil)
  else
    FLoaded := TyDBLoadedNumber(Value, IsBlank);
end;

function TTyCustomDBCurrencyEdit.GetDecimals: Integer;
begin
  Result := TTyCustomNumericEdit(Self).Decimals;
end;

{ The base control rounds the display to the new number of places and fires its change
  notification: the program's doing, like a range (SetRange), so it is taken as a load. A
  control the user has not changed shows the field again at the new precision -- not its old
  display rounded once more -- and that is what the user's edits are compared with next. }
procedure TTyCustomDBCurrencyEdit.SetDecimals(AValue: Integer);
var
  was, untouched: Boolean;
begin
  untouched := (FDataLink.Field <> nil) and (IsBlank = FLoaded.IsNull)
    and (IsBlank or (Value = FLoaded.Number));
  was := FLoading;
  FLoading := True;
  try
    TTyCustomNumericEdit(Self).Decimals := AValue;
  finally
    FLoading := was;
  end;
  if untouched then
    DataChange(nil)
  else
    FLoaded := TyDBLoadedNumber(Value, IsBlank);
end;

procedure TTyCustomDBCurrencyEdit.DataChange(Sender: TObject);
begin
  if FInUserEdit then Exit;
  FLoading := True;
  try
    if (FDataLink.Field = nil) or FDataLink.Field.IsNull then
      Text := ''
    else
    begin
      Value := TyDBReadNumber(FDataLink.Field);   // clamped to MinValue..MaxValue, as typed
      if FFocusedDisplay then Reformat(False);
    end;
    { What the control made of it -- rounded to Decimals, clamped -- since that is what a
      reformat later shows again. }
    FLoaded := TyDBLoadedNumber(Value, IsBlank);
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBCurrencyEdit.UpdateData(Sender: TObject);
begin
  if IsBlank then
    FDataLink.Field.Clear
  else
    TyDBWriteNumber(FDataLink.Field, Value);
  FLoaded := TyDBLoadedNumber(Value, IsBlank);   // what the field holds now: changing back is an edit again
end;

procedure TTyCustomDBCurrencyEdit.ValueChanged(Sender: TObject);
begin
  if FLoading or FInUserEdit or (FDataLink = nil) or (FDataLink.Field = nil) then Exit;
  { The text changes on every focus change (raw while focused, grouped after) without the value
    moving; only a different number, or a number appearing or going, is an edit. }
  if IsBlank = FLoaded.IsNull then
    if IsBlank or (Value = FLoaded.Number) then Exit;
  TyDBUserChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBCurrencyEdit.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBCurrencyEdit.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

procedure TTyCustomDBCurrencyEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if ((Key = VK_BACK) or (Key = VK_DELETE)) and not TyDBEditAllowed(FDataLink, FInUserEdit) then
  begin
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and FDataLink.Editing then
  begin
    FDataLink.Reset;
    SelectAll;
    Key := 0;
  end;
end;

procedure TTyCustomDBCurrencyEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  { Only for what this control would insert: any other character the base filter drops
    without the dataset being asked. Not the field's IsValidChar -- a float field's takes the
    locale's DecimalSeparator, this control always types a '.'. }
  if (Length(UTF8Key) = 1) and (UTF8Key[1] in ['0'..'9', '-', '.'])
    and not TyDBEditAllowed(FDataLink, FInUserEdit) then
  begin
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TTyCustomDBCurrencyEdit.DoEnter;
begin
  FFocusedDisplay := True;
  inherited DoEnter;
end;

procedure TTyCustomDBCurrencyEdit.DoExit;
begin
  FFocusedDisplay := False;
  inherited DoExit;   // regroups and clamps first: what is written is what is shown
  if (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  if FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBCurrencyEdit.EditingDone;
begin
  if (FDataLink <> nil) and FDataLink.Editing then
    FDataLink.UpdateRecord;
  inherited EditingDone;
end;

function TTyCustomDBCurrencyEdit.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBCurrencyEdit.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ============================================================== TTyCustomDBFloatSpinEdit == }

constructor TTyCustomDBFloatSpinEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  EmptyAllowed := True;   // an empty field is NULL, and leaving it must not make it 0.00
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
  AddHandlerOnChange(@ValueChanged);
  Text := '';             // unbound, there is no value to show
end;

destructor TTyCustomDBFloatSpinEdit.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBFloatSpinEdit.GetStyleTypeKey: string;
begin
  Result := 'TyDBFloatSpinEdit';
end;

function TTyCustomDBFloatSpinEdit.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBFloatSpinEdit.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBFloatSpinEdit.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBFloatSpinEdit.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBFloatSpinEdit.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBFloatSpinEdit.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBFloatSpinEdit.SetReadOnly(AValue: Boolean);
begin
  TTyCustomEdit(Self).ReadOnly := AValue;
  FDataLink.ReadOnly := AValue;
end;

function TTyCustomDBFloatSpinEdit.IsBlank: Boolean;
begin
  Result := Trim(Text) = '';
end;

function TTyCustomDBFloatSpinEdit.GetMinValue: Double;
begin
  Result := TTyCustomNumericEdit(Self).MinValue;
end;

function TTyCustomDBFloatSpinEdit.GetMaxValue: Double;
begin
  Result := TTyCustomNumericEdit(Self).MaxValue;
end;

procedure TTyCustomDBFloatSpinEdit.SetMinValue(const AValue: Double);
begin
  SetRange(AValue, MaxValue);
end;

procedure TTyCustomDBFloatSpinEdit.SetMaxValue(const AValue: Double);
begin
  SetRange(MinValue, AValue);
end;

{ The base control reformats to the clamped value and fires its change notification; that
  is the display following the program's new range, so it is taken as a load. A control the
  user has not changed shows the field again under the new range -- a range widened past what
  an earlier one clamped shows the field's own value, not the old clamp -- and that is what the
  user's edits are compared with next, as for Decimals (SetDecimals). }
procedure TTyCustomDBFloatSpinEdit.SetRange(AMin, AMax: Double);
var
  was, untouched: Boolean;
begin
  untouched := (FDataLink.Field <> nil) and (IsBlank = FLoaded.IsNull)
    and (IsBlank or (Value = FLoaded.Number));
  was := FLoading;
  FLoading := True;
  try
    TTyCustomNumericEdit(Self).MinValue := AMin;
    TTyCustomNumericEdit(Self).MaxValue := AMax;
  finally
    FLoading := was;
  end;
  if untouched then
    DataChange(nil)
  else
    FLoaded := TyDBLoadedNumber(Value, IsBlank);
end;

function TTyCustomDBFloatSpinEdit.GetDecimals: Integer;
begin
  Result := TTyCustomNumericEdit(Self).Decimals;
end;

{ The base control rounds the display to the new number of places and fires its change
  notification: the program's doing, like a range (SetRange), so it is taken as a load. A
  control the user has not changed shows the field again at the new precision -- not its old
  display rounded once more -- and that is what the user's edits are compared with next. }
procedure TTyCustomDBFloatSpinEdit.SetDecimals(AValue: Integer);
var
  was, untouched: Boolean;
begin
  untouched := (FDataLink.Field <> nil) and (IsBlank = FLoaded.IsNull)
    and (IsBlank or (Value = FLoaded.Number));
  was := FLoading;
  FLoading := True;
  try
    TTyCustomNumericEdit(Self).Decimals := AValue;
  finally
    FLoading := was;
  end;
  if untouched then
    DataChange(nil)
  else
    FLoaded := TyDBLoadedNumber(Value, IsBlank);
end;

procedure TTyCustomDBFloatSpinEdit.DataChange(Sender: TObject);
begin
  if FInUserEdit then Exit;
  FLoading := True;
  try
    if (FDataLink.Field = nil) or FDataLink.Field.IsNull then
      Text := ''
    else
    begin
      Value := TyDBReadNumber(FDataLink.Field);   // clamped to MinValue..MaxValue, as typed
      if FFocusedDisplay then Reformat(False);
    end;
    { What the control made of it -- rounded to Decimals, clamped -- since that is what a
      reformat later shows again. }
    FLoaded := TyDBLoadedNumber(Value, IsBlank);
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBFloatSpinEdit.UpdateData(Sender: TObject);
begin
  if IsBlank then
    FDataLink.Field.Clear
  else
    TyDBWriteNumber(FDataLink.Field, Value);
  FLoaded := TyDBLoadedNumber(Value, IsBlank);   // what the field holds now: changing back is an edit again
end;

procedure TTyCustomDBFloatSpinEdit.ValueChanged(Sender: TObject);
begin
  if FLoading or FInUserEdit or (FDataLink = nil) or (FDataLink.Field = nil) then Exit;
  { The text changes on every focus change (raw while focused, grouped after) without the value
    moving; only a different number, or a number appearing or going, is an edit. }
  if IsBlank = FLoaded.IsNull then
    if IsBlank or (Value = FLoaded.Number) then Exit;
  TyDBUserChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBFloatSpinEdit.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBFloatSpinEdit.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

procedure TTyCustomDBFloatSpinEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if ((Key = VK_BACK) or (Key = VK_DELETE)) and not TyDBEditAllowed(FDataLink, FInUserEdit) then
  begin
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and FDataLink.Editing then
  begin
    FDataLink.Reset;
    SelectAll;
    Key := 0;
  end;
end;

procedure TTyCustomDBFloatSpinEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  { Only for what this control would insert: any other character the base filter drops
    without the dataset being asked. Not the field's IsValidChar -- a float field's takes the
    locale's DecimalSeparator, this control always types a '.'. }
  if (Length(UTF8Key) = 1) and (UTF8Key[1] in ['0'..'9', '-', '.'])
    and not TyDBEditAllowed(FDataLink, FInUserEdit) then
  begin
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TTyCustomDBFloatSpinEdit.DoEnter;
begin
  FFocusedDisplay := True;
  inherited DoEnter;
end;

procedure TTyCustomDBFloatSpinEdit.DoExit;
begin
  FFocusedDisplay := False;
  inherited DoExit;   // regroups and clamps first: what is written is what is shown
  if (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  if FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBFloatSpinEdit.EditingDone;
begin
  if (FDataLink <> nil) and FDataLink.Editing then
    FDataLink.UpdateRecord;
  inherited EditingDone;
end;

procedure TTyCustomDBFloatSpinEdit.StepValue(ADelta: Double);
begin
  if not TyDBEditAllowed(FDataLink, FInUserEdit) then Exit;
  inherited StepValue(ADelta);
end;

function TTyCustomDBFloatSpinEdit.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBFloatSpinEdit.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ =================================================================== TTyCustomDBSpinEdit == }

constructor TTyCustomDBSpinEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
end;

destructor TTyCustomDBSpinEdit.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBSpinEdit.GetStyleTypeKey: string;
begin
  Result := 'TyDBSpinEdit';
end;

function TTyCustomDBSpinEdit.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBSpinEdit.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBSpinEdit.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBSpinEdit.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBSpinEdit.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBSpinEdit.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBSpinEdit.SetReadOnly(AValue: Boolean);
begin
  TTyCustomSpinEdit(Self).ReadOnly := AValue;
  FDataLink.ReadOnly := AValue;
end;

function TTyCustomDBSpinEdit.OnSpinButton(X, Y: Integer): Boolean;
var
  ppi, bw: Integer;
begin
  ppi := Font.PixelsPerInch;
  bw := MulDiv(ActiveController.Metric('--field-button-width', TyFieldButtonWidth), ppi, 96);
  Result := PtInRect(TySpinUpButtonRect(ClientRect, ppi, bw), Point(X, Y))
    or PtInRect(TySpinDownButtonRect(ClientRect, ppi, bw), Point(X, Y));
end;

function TTyCustomDBSpinEdit.GetMinValue: Integer;
begin
  Result := TTyCustomSpinEdit(Self).MinValue;
end;

function TTyCustomDBSpinEdit.GetMaxValue: Integer;
begin
  Result := TTyCustomSpinEdit(Self).MaxValue;
end;

procedure TTyCustomDBSpinEdit.SetMinValue(const AValue: Integer);
begin
  SetRange(AValue, MaxValue);
end;

procedure TTyCustomDBSpinEdit.SetMaxValue(const AValue: Integer);
begin
  SetRange(MinValue, AValue);
end;

{ See TTyCustomDBNumericEdit.SetRange. The base re-clamps through its Value setter, which
  ends the blank state; a NULL field is still NULL, so it stays blank. A control the user has
  not changed shows the field again under the new range (a widened range brings back what an
  earlier one clamped). Otherwise the loaded text is left as it was: this control never
  reformats on its own, so only the user's own change can be compared with it, and one that
  types the field's value back writes the field's value. }
procedure TTyCustomDBSpinEdit.SetRange(AMin, AMax: Integer);
var
  was, blank, untouched: Boolean;
begin
  untouched := (FDataLink.Field <> nil) and (Text = FLoaded.Text);
  was := FLoading;
  blank := ValueEmpty;
  FLoading := True;
  try
    TTyCustomSpinEdit(Self).MinValue := AMin;
    TTyCustomSpinEdit(Self).MaxValue := AMax;
    if blank then ValueEmpty := True;
  finally
    FLoading := was;
  end;
  if untouched then DataChange(nil);
end;

procedure TTyCustomDBSpinEdit.DataChange(Sender: TObject);
var
  f: TField;
begin
  if FInUserEdit then Exit;
  f := FDataLink.Field;
  FLoading := True;
  try
    if (f = nil) or f.IsNull then
    begin
      Value := 0;
      ValueEmpty := True;
    end
    else
    begin
      Value := Round(TyDBReadNumber(f));   // clamped to MinValue..MaxValue
      ValueEmpty := False;                 // the same number as before the NULL row stays blank otherwise
    end;
    FLoaded := TyDBLoadedText(Text);
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBSpinEdit.UpdateData(Sender: TObject);
begin
  CommitEdit;   // what is typed, as the number it parses to -- what Enter or leaving would make of it
  if ValueEmpty then
    FDataLink.Field.Clear
  else
    TyDBWriteNumber(FDataLink.Field, Value);
  FLoaded := TyDBLoadedText(Text);   // what the field holds now: changing back is an edit again
end;

procedure TTyCustomDBSpinEdit.DoChange;
begin
  inherited DoChange;
  if FLoading or FInUserEdit or (FDataLink = nil) or (FDataLink.Field = nil) then Exit;
  if Text = FLoaded.Text then Exit;
  TyDBUserChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBSpinEdit.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBSpinEdit.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

procedure TTyCustomDBSpinEdit.KeyDown(var Key: Word; Shift: TShiftState);
var
  wasReturn: Boolean;
begin
  case Key of
    VK_ESCAPE:
      { The base only puts back the last committed value; a step has already committed. }
      if FDataLink.Editing then
      begin
        FDataLink.Reset;
        Key := 0;
        Exit;
      end;
    VK_UP, VK_DOWN, VK_BACK, VK_DELETE:
      if not TyDBEditAllowed(FDataLink, FInUserEdit) then
      begin
        Key := 0;
        Exit;
      end;
  end;
  wasReturn := (Key = VK_RETURN) and (Shift = []);
  inherited KeyDown(Key, Shift);
  if wasReturn and FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBSpinEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if (Length(UTF8Key) = 1) and (UTF8Key[1] in ['0'..'9', '-'])
    and not TyDBEditAllowed(FDataLink, FInUserEdit) then
  begin
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

function TTyCustomDBSpinEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  was: Boolean;
begin
  if TyDBEditAllowed(FDataLink, FInUserEdit) then
    Exit(inherited DoMouseWheel(Shift, WheelDelta, MousePos));
  { Refused: the base control's own read-only state turns the wheel away (and still gives the
    application's OnMouseWheel its turn). }
  was := TTyCustomSpinEdit(Self).ReadOnly;
  TTyCustomSpinEdit(Self).ReadOnly := True;
  try
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  finally
    TTyCustomSpinEdit(Self).ReadOnly := was;
  end;
end;

procedure TTyCustomDBSpinEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  was: Boolean;
begin
  if (Button <> mbLeft) or not OnSpinButton(X, Y) or TyDBEditAllowed(FDataLink, FInUserEdit) then
  begin
    inherited MouseDown(Button, Shift, X, Y);
    Exit;
  end;
  was := TTyCustomSpinEdit(Self).ReadOnly;   // refused: the press takes focus, the button does not step
  TTyCustomSpinEdit(Self).ReadOnly := True;
  try
    inherited MouseDown(Button, Shift, X, Y);
  finally
    TTyCustomSpinEdit(Self).ReadOnly := was;
  end;
end;

procedure TTyCustomDBSpinEdit.DoExit;
begin
  inherited DoExit;   // commits what was typed
  if (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  if FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBSpinEdit.EditingDone;
begin
  if (FDataLink <> nil) and FDataLink.Editing then
    FDataLink.UpdateRecord;
  inherited EditingDone;
end;

function TTyCustomDBSpinEdit.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBSpinEdit.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

initialization
  { Each key falls back to its base control's, so a theme that never names a TyDBXxx key
    styles these exactly like their base controls; a theme can still write rules for them. }
  TyTryRegisterTypeKeyParent('TyDBEdit', 'TyEdit');
  TyTryRegisterTypeKeyParent('TyDBMaskEdit', 'TyEdit');
  TyTryRegisterTypeKeyParent('TyDBMemo', 'TyMemo');
  TyTryRegisterTypeKeyParent('TyDBText', 'TyLabel');
  TyTryRegisterTypeKeyParent('TyDBNumericEdit', 'TyEdit');
  TyTryRegisterTypeKeyParent('TyDBCurrencyEdit', 'TyEdit');
  TyTryRegisterTypeKeyParent('TyDBSpinEdit', 'TySpinEdit');
  TyTryRegisterTypeKeyParent('TyDBFloatSpinEdit', 'TyEdit');

finalization
  TyUnregisterTypeKeyParent('TyDBEdit');
  TyUnregisterTypeKeyParent('TyDBMaskEdit');
  TyUnregisterTypeKeyParent('TyDBMemo');
  TyUnregisterTypeKeyParent('TyDBText');
  TyUnregisterTypeKeyParent('TyDBNumericEdit');
  TyUnregisterTypeKeyParent('TyDBCurrencyEdit');
  TyUnregisterTypeKeyParent('TyDBSpinEdit');
  TyUnregisterTypeKeyParent('TyDBFloatSpinEdit');

end.
