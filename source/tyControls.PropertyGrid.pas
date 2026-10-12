unit tyControls.PropertyGrid;
{$mode objfpc}{$H+}

{ A property grid (#65): point it at an object and it lists that object's published properties,
  each with the editor its type calls for, and writes what the user changes straight back.

  Two halves, kept apart on purpose:

    TTyPropertyRows        the object -> rows mapping. It reads the RTTI (TypInfo only -- no
                           IDEIntf, no PropEdits, so the main package gains no dependency), builds
                           the rows into any TTyCustomValueListEditor, reads values for display
                           and writes typed text back. Each row's Data points at a node of its own.
    TTyCustomPropertyGrid  the control: a TTyCustomValueListEditor whose commit hook
                           (CanCommitValue) hands every edit to the mapping.

  A node never keeps an instance pointer: it is reached afresh from the root each time, through
  the property chain (and a collection item through its index), so a sub-object a setter has
  replaced is never read through a stale pointer. }

interface

uses
  Classes, SysUtils, TypInfo, Graphics, Controls, Forms, LCLType,
  tyControls.ValueListEditor;

const
  { The kinds the grid shows by default: everything it can show except event handlers. Untyped,
    so it can be the published TypeFilter's default. }
  TyPropertyGridDefaultTypeFilter = [Low(TTypeKind)..High(TTypeKind)] - [tkMethod];
  TyPropertyGridDefaultMaxDepth = 6;

type
  { How the rows of one object are ordered: by name, as the Object Inspector does (the default),
    or in the order the class declares them (ancestors first). }
  TTyPropertyOrder = (poAlphabetical, poDeclared);

  TTyPropertyNodeKind = (
    pnkValue,           // number, text, character, boolean, enumeration or colour
    pnkSet,             // a set; its children are the elements
    pnkSetElement,      // one element of a set, as a boolean
    pnkObject,          // a TPersistent sub-object (or a csSubComponent component), expanded
    pnkFont,            // a TFont: expanded, and written back as a whole
    pnkCollection,      // a TCollection; its children are the items
    pnkCollectionItem,  // one collection item, expanded into its own properties
    pnkComponent,       // a reference to another component, picked by name
    pnkStrings,         // a TStrings, edited in a dialog
    pnkMethod);         // an event handler, shown by name, read-only

  TTyPropertyRows = class;

  { What one row stands for. Owned by TTyPropertyRows; TTyValueRow.Data points here. }
  TTyPropertyNode = class
  private
    FOwner: TTyPropertyRows;
    FParent: TTyPropertyNode;
    FPropInfo: PPropInfo;
    FKind: TTyPropertyNodeKind;
    FIndex: Integer;
    FDepth: Integer;
    FRow: TTyValueRow;
    { What the rows below were built from, for Refresh to notice when they no longer fit: the
      class of an expanded sub-object (nil when there was none), a collection's item count. }
    FBuiltClass: TClass;
    FBuiltCount: Integer;
  public
    { The property's name; a set element's name; '[i]' for a collection item. }
    function Name: string;
    { Dotted from the root: 'Font.Style.fsBold', 'Columns[0].Width'. }
    function Path: string;
    { The object that HAS this node's property (for a set element, the set's owner; for a
      collection item, nil). Resolved from the root on every call; nil when the chain is broken. }
    function Instance: TObject;
    property Parent: TTyPropertyNode read FParent;
    property PropInfo: PPropInfo read FPropInfo;   // nil for a collection item
    property Kind: TTyPropertyNodeKind read FKind;
    property Index: Integer read FIndex;           // set element ordinal / collection item index
    property Depth: Integer read FDepth;           // object nesting level, 0 at the root
    property Row: TTyValueRow read FRow;
  end;

  TTyFilterPropertyEvent = procedure(Sender: TObject; AInstance: TPersistent;
    const APropName: string; var AShow: Boolean) of object;

  { The names a component-reference row offers. AList arrives holding '(none)' and the
    type-compatible components of the candidate root, each name with its component in Objects[]:
    the root is the inspected component itself when it is a form, a data module or a frame (the
    components on it), else its Owner -- and the root itself is a candidate too. Add, remove or
    reorder entries (a component from another form, say: add its name WITH the component in
    Objects[], or it cannot be resolved). The current value is listed afterwards if the list lost
    it. }
  TTyGetComponentNamesEvent = procedure(Sender: TObject; AInstance: TPersistent;
    APropInfo: PPropInfo; AList: TStrings) of object;

  { A property's row has just been built: change its editor kind, its options, its DisplayValue,
    its style, or make it read-only. }
  TTyGetPropertyRowEvent = procedure(Sender: TObject; AInstance: TPersistent;
    APropInfo: PPropInfo; ARow: TTyValueRow) of object;

  { About to write ANewValue (the property's text as it will read: for one element of a set, the
    whole set) into AInstance.APropName; set AAllow to False to refuse it. }
  TTyPropertyChangingEvent = procedure(Sender: TObject; AInstance: TPersistent;
    const APropName, ANewValue: string; var AAllow: Boolean) of object;

  TTyPropertyChangedEvent = procedure(Sender: TObject; AInstance: TPersistent;
    const APropName: string) of object;

  { A write failed (a value that does not parse, or a setter that raised): E is the exception.
    The row keeps the value the object holds. }
  TTyPropertyErrorEvent = procedure(Sender: TObject; AInstance: TPersistent;
    const APropName: string; E: Exception) of object;

  { The '…' of a dialog row. Set AHandled when the handler did the editing (it writes the
    PROPERTY; the rows are re-read afterwards); left False, the grid's own editor runs (the text
    dialog of a TStrings, nothing for the others). AInstance is nil and APropName '' for a row
    that is not one of the grid's. }
  TTyEditPropertyEvent = procedure(Sender: TObject; ARow: TTyValueRow; AInstance: TPersistent;
    const APropName: string; var AHandled: Boolean) of object;

  { The object -> rows mapping. }
  TTyPropertyRows = class
  private
    FSender: TObject;
    FRoot: TPersistent;
    FNodes: TFPList;
    FTypeFilter: TTypeKinds;
    FHiddenProperties: TStringList;
    FOrder: TTyPropertyOrder;
    FMaxDepth: Integer;
    FOnFilterProperty: TTyFilterPropertyEvent;
    FOnGetComponentNames: TTyGetComponentNamesEvent;
    FOnGetPropertyRow: TTyGetPropertyRowEvent;
    procedure SetHiddenProperties(AValue: TStringList);
    function NewNode(AParent: TTyPropertyNode; APropInfo: PPropInfo; AKind: TTyPropertyNodeKind;
      AIndex: Integer): TTyPropertyNode;
    function Accept(AInstance: TObject; APropInfo: PPropInfo; AParent: TTyPropertyNode): Boolean;
    function KindOf(APropInfo: PPropInfo; AInstance: TObject): TTyPropertyNodeKind;
    procedure AddProperties(AEditor: TTyCustomValueListEditor; AParentRow: TTyValueRow;
      AParentNode: TTyPropertyNode; AInstance: TObject; ADepth: Integer);
    procedure AddChildren(AEditor: TTyCustomValueListEditor; ANode: TTyPropertyNode);
    procedure FillRow(ANode: TTyPropertyNode);
    function HolderOf(ANode: TTyPropertyNode): TObject;
    function ValueObject(ANode: TTyPropertyNode): TObject;
    function FontOwnerOf(ANode: TTyPropertyNode): TTyPropertyNode;
    procedure StoreFont(AFontNode: TTyPropertyNode; AFont: TFont);
    function FindComponentByName(ANode: TTyPropertyNode; const AName: string): TComponent;
    procedure WriteOn(ANode: TTyPropertyNode; AHolder: TObject; const AText: string);
  public
    constructor Create(ASender: TObject);
    destructor Destroy; override;
    { Replace AEditor's rows with ARoot's properties (none when ARoot is nil). }
    procedure Build(AEditor: TTyCustomValueListEditor; ARoot: TPersistent);
    { Drop the nodes. The rows they belong to must be cleared by the caller. }
    procedure Clear;
    function NodeOf(ARow: TTyValueRow): TTyPropertyNode;
    function NodeCount: Integer;
    function Node(AIndex: Integer): TTyPropertyNode;
    { The display text of ANode, read from the object now. }
    function ReadText(ANode: TTyPropertyNode): string;
    { Parse AText and write it into the object. Raises (EConvertError, ERangeError,
      EPropertyError, or whatever the setter raises) and writes nothing when it cannot; on
      success AText becomes what the object now reads back. }
    procedure WriteText(ANode: TTyPropertyNode; var AText: string);
    { A TFont property, written back whole: through its setter when it has one, else by Assign
      into the font it holds. }
    procedure WriteFont(ANode: TTyPropertyNode; AFont: TFont);
    { A TStrings property, likewise. }
    procedure WriteStrings(ANode: TTyPropertyNode; AStrings: TStrings);
    { What an object-valued node holds now: the sub-object, the font, the list, the collection,
      the referenced component, or for a collection item the item. }
    function ObjectOf(ANode: TTyPropertyNode): TObject;
    { The names a component-reference node offers, '(none)' first; Objects[] holds each component. }
    procedure ComponentNames(ANode: TTyPropertyNode; AList: TStrings);
    { Re-read every row's value from the object, except AExcept (the row being committed). }
    procedure RefreshValues(AExcept: TTyValueRow = nil);
    { The node whose Path is APath (case-insensitive), nil when there is none. }
    function FindByPath(const APath: string): TTyPropertyNode;
    { The property a node's row edits: its object and its name (a set element's is the set's).
      False for a collection item, or when the chain to the object is broken. }
    function PropertyOf(ANode: TTyPropertyNode; out AInstance: TPersistent;
      out APropName: string): Boolean;
    { PropertyOf, plus the text the property will read once AText is committed to the node's
      row: AText itself, except for a set element, where it is the whole set with that element
      flipped. }
    function ChangeOf(ANode: TTyPropertyNode; const AText: string; out AInstance: TPersistent;
      out APropName, ANewValue: string): Boolean;
    { True when the object no longer fits the rows: a sub-object came or went or changed class,
      or a collection's item count moved. Values alone never count. }
    function StructureChanged: Boolean;
    property Root: TPersistent read FRoot;
    property TypeFilter: TTypeKinds read FTypeFilter write FTypeFilter;
    property HiddenProperties: TStringList read FHiddenProperties write SetHiddenProperties;
    property Order: TTyPropertyOrder read FOrder write FOrder;
    { How many objects deep the rows go (a sub-object of a sub-object... ); stops a cycle. }
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
    property OnFilterProperty: TTyFilterPropertyEvent read FOnFilterProperty write FOnFilterProperty;
    property OnGetComponentNames: TTyGetComponentNamesEvent read FOnGetComponentNames
      write FOnGetComponentNames;
    { Called once per property row (not for a set's elements or a collection's items), after the
      row is filled. }
    property OnGetPropertyRow: TTyGetPropertyRowEvent read FOnGetPropertyRow
      write FOnGetPropertyRow;
  end;

  { How a write reaches the object: typed (or picked) text, a font from the font dialog, a list
    from the strings dialog. }
  TTyPropertyWriteKind = (pwkText, pwkFont, pwkStrings);

  { The control. Every field, method and property lives here; TTyPropertyGrid only publishes.

    The rows are the grid's own: it builds them from SelectedObject and rebuilds them when the
    object, the order or a filter changes. Do not AddRow / DeleteRow / Clear them -- the value
    list editor's row-set API is still reachable, but a row the grid did not build is not one of
    its properties. KeyOptions is fixed at []. }
  TTyCustomPropertyGrid = class(TTyCustomValueListEditor)
  private
    FRows: TTyPropertyRows;
    FSelectedObject: TPersistent;
    FOnEditRowApp: TTyValueEditEvent;
    FExpanded: TStringList;
    FHarvesting: Boolean;
    FBuildCount: Integer;
    FOnPropertyChanging: TTyPropertyChangingEvent;
    FOnPropertyChanged: TTyPropertyChangedEvent;
    FOnPropertyError: TTyPropertyErrorEvent;
    FOnEditProperty: TTyEditPropertyEvent;
    procedure SetSelectedObject(AValue: TPersistent);
    function GetSelectedComponent: TComponent;
    procedure SetSelectedComponent(AValue: TComponent);
    function FlatRowAt(AFlat: Integer): TTyValueRow;
    function FlatIndexOf(ARow: TTyValueRow): Integer;
    procedure InternalEditRow(Sender: TObject; ARow: TTyValueRow);
    function GetFixedKeyOptions: TTyKeyOptions;
    function GetPropertyOrder: TTyPropertyOrder;
    procedure SetPropertyOrder(AValue: TTyPropertyOrder);
    function GetTypeFilter: TTypeKinds;
    procedure SetTypeFilter(AValue: TTypeKinds);
    function GetHiddenProperties: TStrings;
    procedure SetHiddenProperties(AValue: TStrings);
    procedure HiddenChanged(Sender: TObject);
    function GetExpandedProperties: TStrings;
    procedure SetExpandedProperties(AValue: TStrings);
    procedure ExpandedChanged(Sender: TObject);
    procedure HarvestExpanded;
    procedure ApplyExpanded;
    function GetOnFilterProperty: TTyFilterPropertyEvent;
    procedure SetOnFilterProperty(AValue: TTyFilterPropertyEvent);
    function GetOnGetComponentNames: TTyGetComponentNamesEvent;
    procedure SetOnGetComponentNames(AValue: TTyGetComponentNamesEvent);
    function GetOnGetPropertyRow: TTyGetPropertyRowEvent;
    procedure SetOnGetPropertyRow(AValue: TTyGetPropertyRowEvent);
    procedure RebuildRows(AKeepTop: Boolean);
  protected
    function CanCommitValue(ARow: TTyValueRow; var AText: string): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    { 'TyPropertyGrid', hung on 'TyValueListEditor' (see the initialization): a theme silent about
      it styles the grid as the value list editor. The rows and their parts keep the editor's keys. }
    function GetStyleTypeKey: string; override;
    { One write into the object, wrapped in OnPropertyChanging / OnPropertyChanged /
      OnPropertyError. AText is the row's text for pwkText (and comes back as the object reads
      it), AObject the font or the list for the other two. AExceptRow is the row the caller will
      update itself. False when nothing was written -- refused, failed with OnPropertyError
      assigned, or the rows were rebuilt by a handler (then the caller's row is gone). Raises
      when the write fails and OnPropertyError is not assigned. }
    function WriteProperty(ANode: TTyPropertyNode; AKind: TTyPropertyWriteKind; AObject: TObject;
      AExceptRow: TTyValueRow; var AText: string): Boolean;
    { The TStrings editor: show AStrings, let the user change it, True when confirmed. The
      default is the library's multi-line text dialog; a descendant (or a test) supplies its own. }
    function ExecuteStringsDialog(const ATitle: string; AStrings: TStrings): Boolean; virtual;
    { What the '…' of a TStrings row runs: the dialog above, then the write. }
    procedure EditStringsRow(ARow: TTyValueRow);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Build the rows again from SelectedObject, keeping the expanded rows (ExpandedProperties)
      and the current row (by its path). }
    procedure Rebuild;
    { Re-read every row's value from the object, keeping the rows, what is expanded and the
      current row. When the object no longer fits the rows (a collection gained an item, a
      sub-object came or went) the rows are rebuilt, keeping the same. }
    procedure Refresh;
    { The property ARow edits: the object that has it and its name (for a set's element, the
      set). False for a collection item's row and for a row the grid did not build. }
    function PropertyAt(ARow: TTyValueRow; out AInstance: TPersistent;
      out APropName: string): Boolean;
    { The object inspected: any TPersistent. A component is let go of when it is freed (a free
      notification); anything else must be cleared here before it is freed. }
    property SelectedObject: TPersistent read FSelectedObject write SetSelectedObject;
    { The same object when it is a component, nil otherwise; setting it sets SelectedObject. The
      published face of the selection: a component picked in the Object Inspector. At design
      time its rows are listed but cannot be edited. }
    property SelectedComponent: TComponent read GetSelectedComponent write SetSelectedComponent;
    property PropertyRows: TTyPropertyRows read FRows;
    property KeyOptions: TTyKeyOptions read GetFixedKeyOptions;
    property PropertyOrder: TTyPropertyOrder read GetPropertyOrder write SetPropertyOrder
      default poAlphabetical;
    property TypeFilter: TTypeKinds read GetTypeFilter write SetTypeFilter
      default TyPropertyGridDefaultTypeFilter;
    { Property names ('Tag') or dotted paths ('Font.Height') never listed. }
    property HiddenProperties: TStrings read GetHiddenProperties write SetHiddenProperties;
    { The dotted paths of the expanded rows ('Font', 'Font.Style', 'Columns[0]'). Kept when the
      selection moves to another object, so a row expanded on one button is expanded on the
      next; adding a path expands that row. }
    property ExpandedProperties: TStrings read GetExpandedProperties write SetExpandedProperties;
    property OnFilterProperty: TTyFilterPropertyEvent read GetOnFilterProperty
      write SetOnFilterProperty;
    property OnGetComponentNames: TTyGetComponentNamesEvent read GetOnGetComponentNames
      write SetOnGetComponentNames;
    property OnGetPropertyRow: TTyGetPropertyRowEvent read GetOnGetPropertyRow
      write SetOnGetPropertyRow;
    property OnPropertyChanging: TTyPropertyChangingEvent read FOnPropertyChanging
      write FOnPropertyChanging;
    property OnPropertyChanged: TTyPropertyChangedEvent read FOnPropertyChanged
      write FOnPropertyChanged;
    { Unassigned, a failed write raises -- out of the event that made it, to
      Application.HandleException, as anything raised in an LCL event does. Either way the row
      keeps the value the object holds. }
    property OnPropertyError: TTyPropertyErrorEvent read FOnPropertyError write FOnPropertyError;
    property OnEditProperty: TTyEditPropertyEvent read FOnEditProperty write FOnEditProperty;
    { The value list editor's OnEditRow belongs to the grid (it runs OnEditProperty and the
      built-in editors); this redeclaration keeps code from replacing it. Assigned, it is asked
      after OnEditProperty leaves a row unhandled, and takes the row from the built-in editor.
      Prefer OnEditProperty. Not published. }
    property OnEditRow: TTyValueEditEvent read FOnEditRowApp write FOnEditRowApp;
  end;

  { The property grid. TTyCustomPropertyGrid holds everything; this class only publishes. What
    belongs to a list of names and values (KeyOptions, Items, Sorted, the multi-selection, the
    key events, OnEditRow, OnValueChanged) is not published: the rows are the object's. }
  TTyPropertyGrid = class(TTyCustomPropertyGrid)
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
    property BorderWidth;
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
    property ItemHeight;
    property ScrollBarAutoHide;
    property OnChange;
    property OnSelectionChange;
    property Align;
    property Anchors;
    property KeyColumnWidth;
    property ReadOnly;
    property Images;
    property SelectedComponent;
    property PropertyOrder;
    property TypeFilter;
    property HiddenProperties;
    property ExpandedProperties;
    property OnFilterProperty;
    property OnGetComponentNames;
    property OnGetPropertyRow;
    property OnPropertyChanging;
    property OnPropertyChanged;
    property OnPropertyError;
    property OnEditProperty;
  end;

{ True when ATypeInfo is TColor (graphics.pp declares TColor = TGraphicsColor, so the RTTI name
  is 'TGraphicsColor' on FPC 3.2.2 and 'TColor' once graphtype switches to System.UITypes). }
function TyIsColorType(ATypeInfo: PTypeInfo): Boolean;

implementation

uses
  tyControls.StyleModel, tyControls.StrConsts, tyControls.Dialogs;

function TyIsColorType(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := (ATypeInfo = TypeInfo(TColor))
    or SameText(ATypeInfo^.Name, 'TColor') or SameText(ATypeInfo^.Name, 'TGraphicsColor');
end;

{ The float format: always '.', never a thousands separator. The inline editor's number mode
  takes '.' only, so following the machine's locale would show a German user '1,5' that the
  editor then refuses to let them type. }
function DotFormat: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := #0;
end;

function BoolText(AValue: Boolean): string;
begin
  if AValue then Result := 'True' else Result := 'False';
end;

function IsDateType(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := (ATypeInfo = TypeInfo(TDateTime)) or (ATypeInfo = TypeInfo(TDate))
    or (ATypeInfo = TypeInfo(TTime));
end;

{ A one-byte character as text: printable ASCII as itself, anything else as '#n'. }
function CharText(ACode: Integer): string;
begin
  if (ACode >= 32) and (ACode < 127) then Result := Chr(ACode)
  else Result := '#' + IntToStr(ACode);
end;

function InvalidValue(const AText, AName: string): EConvertError;
begin
  Result := EConvertError.CreateFmt(rsTyPropGridInvalidValue, [AText, AName]);
end;

{ '#65' or a single character -> its code. }
function ParseCharCode(const AText, AName: string; AMax: Integer): Integer;
var u: UnicodeString;
begin
  if (Length(AText) > 1) and (AText[1] = '#') then
  begin
    if not TryStrToInt(Copy(AText, 2, MaxInt), Result) then raise InvalidValue(AText, AName);
  end
  else
  begin
    u := UTF8Decode(AText);
    if Length(u) <> 1 then raise InvalidValue(AText, AName);
    Result := Ord(u[1]);
  end;
  if (Result < 0) or (Result > AMax) then raise InvalidValue(AText, AName);
end;

{ Integer range of an ordinal type. otULong's bounds do not fit the Longint fields they are
  stored in, so they are spelled out. }
procedure OrdRange(ATypeInfo: PTypeInfo; out ALo, AHi: Int64);
var td: PTypeData;
begin
  td := GetTypeData(ATypeInfo);
  if td^.OrdType = otULong then
  begin
    ALo := 0;
    AHi := High(Cardinal);
  end
  else
  begin
    ALo := td^.MinValue;
    AHi := td^.MaxValue;
  end;
end;

{ GetOrdProp sign-extends a 4-byte unsigned value; undo that. }
function ReadOrd(AInstance: TObject; APropInfo: PPropInfo): Int64;
begin
  Result := GetOrdProp(AInstance, APropInfo);
  if (APropInfo^.PropType^.Kind = tkInteger)
    and (GetTypeData(APropInfo^.PropType)^.OrdType = otULong) then
    Result := Result and $FFFFFFFF;
end;

function FloatText(AValue: Extended; ATypeInfo: PTypeInfo): string;
var digits: Integer;
begin
  case GetTypeData(ATypeInfo)^.FloatType of
    ftSingle: digits := 7;
    ftDouble: digits := 15;
    ftCurr:   digits := 19;
  else
    digits := 18;
  end;
  Result := FloatToStrF(AValue, ffGeneral, digits, 0, DotFormat);
end;

function DateText(AValue: Double; ATypeInfo: PTypeInfo): string;
begin
  if ATypeInfo = TypeInfo(TDate) then Result := DateToStr(AValue)
  else if ATypeInfo = TypeInfo(TTime) then Result := TimeToStr(AValue)
  else Result := DateTimeToStr(AValue);
end;

{ The handler's name when its object publishes it, '' when unassigned. }
function MethodText(AInstance: TObject; APropInfo: PPropInfo): string;
var m: TMethod;
begin
  m := GetMethodProp(AInstance, APropInfo);
  Result := '';
  if m.Code = nil then Exit;
  if m.Data <> nil then Result := TObject(m.Data).MethodName(m.Code);
  if Result = '' then Result := '(' + HexStr(m.Code) + ')';
end;

{ The element type of a set, and the ordinal range it spans. }
procedure SetRange(ASetType: PTypeInfo; out AComp: PTypeInfo; out ALo, AHi: Integer);
var td: PTypeData;
begin
  AComp := GetTypeData(ASetType)^.CompType;
  td := GetTypeData(AComp);
  ALo := td^.MinValue;
  AHi := td^.MaxValue;
end;

{ An element's name: the enumeration's name for it, or the number for a set of an integer range. }
function ElementName(AComp: PTypeInfo; AOrd: Integer): string;
begin
  if AComp^.Kind = tkEnumeration then Result := GetEnumName(AComp, AOrd)
  else Result := IntToStr(AOrd);
end;

{ '[a,b]' -- built here rather than with SetToString, which cannot name an integer range. }
function SetText(ASetType: PTypeInfo; AValue: Int64): string;
var comp: PTypeInfo; lo, hi, i: Integer;
begin
  SetRange(ASetType, comp, lo, hi);
  Result := '';
  for i := lo to hi do
    if (AValue and (Int64(1) shl i)) <> 0 then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + ElementName(comp, i);
    end;
  Result := '[' + Result + ']';
end;

function FontText(AFont: TFont): string;
begin
  { The 'Name, Size' summary the value list editor composes for a font row with children. }
  Result := Format('%s, %d', [AFont.Name, AFont.Size]);
end;

function ComponentText(AComponent: TObject): string;
begin
  if AComponent = nil then Result := rsTyPropGridNone
  else if (AComponent is TComponent) and (TComponent(AComponent).Name <> '') then
    Result := TComponent(AComponent).Name
  else Result := '(' + AComponent.ClassName + ')';
end;

function SimpleText(AInstance: TObject; APropInfo: PPropInfo): string;
var pt: PTypeInfo; v: Int64;
begin
  pt := APropInfo^.PropType;
  case pt^.Kind of
    tkInteger:
      begin
        v := ReadOrd(AInstance, APropInfo);
        if TyIsColorType(pt) then Result := ColorToString(TColor(v))
        else Result := IntToStr(v);
      end;
    tkInt64:
      Result := IntToStr(GetInt64Prop(AInstance, APropInfo));
    tkQWord:
      Result := UIntToStr(QWord(GetInt64Prop(AInstance, APropInfo)));
    tkChar:
      Result := CharText(GetOrdProp(AInstance, APropInfo) and $FF);
    tkWChar:
      begin
        v := GetOrdProp(AInstance, APropInfo) and $FFFF;
        if (v < 32) or (v = 127) then Result := '#' + IntToStr(v)
        else Result := UTF8Encode(UnicodeString(WideChar(v)));
      end;
    tkEnumeration:
      Result := GetEnumName(pt, GetOrdProp(AInstance, APropInfo));
    tkBool:
      Result := BoolText(GetOrdProp(AInstance, APropInfo) <> 0);
    tkFloat:
      if IsDateType(pt) then Result := DateText(GetFloatProp(AInstance, APropInfo), pt)
      else Result := FloatText(GetFloatProp(AInstance, APropInfo), pt);
    tkSString, tkLString, tkAString, tkWString, tkUString:
      Result := GetStrProp(AInstance, APropInfo);
  else
    Result := '';
  end;
end;

procedure WriteSimple(AInstance: TObject; APropInfo: PPropInfo; const AText: string);
var
  pt: PTypeInfo;
  td: PTypeData;
  v, lo, hi: Int64;
  q: QWord;
  c: Longint;
  f: Extended;
  t: string;
begin
  pt := APropInfo^.PropType;
  td := GetTypeData(pt);
  t := Trim(AText);
  case pt^.Kind of
    tkInteger:
      if TyIsColorType(pt) then
      begin
        if not IdentToColor(t, c) then
        begin
          if not TryStrToInt64(t, v) then raise InvalidValue(AText, APropInfo^.Name);
          c := Longint(v);
        end;
        SetOrdProp(AInstance, APropInfo, c);
      end
      else
      begin
        if not TryStrToInt64(t, v) then raise InvalidValue(AText, APropInfo^.Name);
        OrdRange(pt, lo, hi);
        if (v < lo) or (v > hi) then
          raise ERangeError.CreateFmt(rsTyPropGridOutOfRange,
            [APropInfo^.Name, IntToStr(lo), IntToStr(hi)]);
        SetOrdProp(AInstance, APropInfo, v);
      end;
    tkInt64:
      begin
        if not TryStrToInt64(t, v) then raise InvalidValue(AText, APropInfo^.Name);
        if (v < td^.MinInt64Value) or (v > td^.MaxInt64Value) then
          raise ERangeError.CreateFmt(rsTyPropGridOutOfRange,
            [APropInfo^.Name, IntToStr(td^.MinInt64Value), IntToStr(td^.MaxInt64Value)]);
        SetInt64Prop(AInstance, APropInfo, v);
      end;
    tkQWord:
      begin
        if (t = '') or (t[1] = '-') or not TryStrToQWord(t, q) then
          raise InvalidValue(AText, APropInfo^.Name);
        SetInt64Prop(AInstance, APropInfo, Int64(q));
      end;
    tkChar:
      SetOrdProp(AInstance, APropInfo, ParseCharCode(AText, APropInfo^.Name, 255));
    tkWChar:
      SetOrdProp(AInstance, APropInfo, ParseCharCode(AText, APropInfo^.Name, $FFFF));
    tkEnumeration:
      begin
        v := GetEnumValue(pt, t);
        if (v < td^.MinValue) or (v > td^.MaxValue) then raise InvalidValue(AText, APropInfo^.Name);
        SetOrdProp(AInstance, APropInfo, v);
      end;
    tkBool:
      if SameText(t, 'True') then SetOrdProp(AInstance, APropInfo, 1)
      else if SameText(t, 'False') then SetOrdProp(AInstance, APropInfo, 0)
      else raise InvalidValue(AText, APropInfo^.Name);
    tkFloat:
      begin
        if IsDateType(pt) then
        begin
          if pt = TypeInfo(TDate) then f := StrToDate(t)
          else if pt = TypeInfo(TTime) then f := StrToTime(t)
          else f := StrToDateTime(t);
        end
        else if not TryStrToFloat(t, f, DotFormat) then
          raise InvalidValue(AText, APropInfo^.Name);
        SetFloatProp(AInstance, APropInfo, f);
      end;
    tkSString, tkLString, tkAString, tkWString, tkUString:
      SetStrProp(AInstance, APropInfo, AText);   // text is taken as typed, spaces and all
  else
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, APropInfo^.Name]);
  end;
end;

{ ---- TTyPropertyNode ---- }

function TTyPropertyNode.Name: string;
begin
  case FKind of
    pnkCollectionItem: Result := '[' + IntToStr(FIndex) + ']';
    pnkSetElement: Result := ElementName(GetTypeData(FPropInfo^.PropType)^.CompType, FIndex);
  else
    Result := FPropInfo^.Name;
  end;
end;

function TTyPropertyNode.Path: string;
begin
  if FParent = nil then Exit(Name);
  if FKind = pnkCollectionItem then Result := FParent.Path + Name
  else Result := FParent.Path + '.' + Name;
end;

function TTyPropertyNode.Instance: TObject;
begin
  if FKind = pnkCollectionItem then Exit(nil);
  Result := FOwner.HolderOf(Self);
end;


{ ---- TTyPropertyRows ---- }

constructor TTyPropertyRows.Create(ASender: TObject);
begin
  inherited Create;
  FSender := ASender;
  FNodes := TFPList.Create;
  FTypeFilter := TyPropertyGridDefaultTypeFilter;
  FHiddenProperties := TStringList.Create;
  FHiddenProperties.CaseSensitive := False;
  FOrder := poAlphabetical;
  FMaxDepth := TyPropertyGridDefaultMaxDepth;
end;

destructor TTyPropertyRows.Destroy;
begin
  Clear;
  FNodes.Free;
  FHiddenProperties.Free;
  inherited Destroy;
end;

procedure TTyPropertyRows.SetHiddenProperties(AValue: TStringList);
begin
  FHiddenProperties.Assign(AValue);
end;

procedure TTyPropertyRows.Clear;
var i: Integer;
begin
  for i := 0 to FNodes.Count - 1 do TObject(FNodes[i]).Free;
  FNodes.Clear;
  FRoot := nil;
end;

function TTyPropertyRows.NodeCount: Integer;
begin
  Result := FNodes.Count;
end;

function TTyPropertyRows.Node(AIndex: Integer): TTyPropertyNode;
begin
  Result := TTyPropertyNode(FNodes[AIndex]);
end;

function TTyPropertyRows.NodeOf(ARow: TTyValueRow): TTyPropertyNode;
begin
  Result := nil;
  if (ARow = nil) or (ARow.Data = nil) then Exit;
  if FNodes.IndexOf(ARow.Data) < 0 then Exit;   // not one of ours (an app-added row, say)
  Result := TTyPropertyNode(ARow.Data);
end;

function TTyPropertyRows.NewNode(AParent: TTyPropertyNode; APropInfo: PPropInfo;
  AKind: TTyPropertyNodeKind; AIndex: Integer): TTyPropertyNode;
begin
  Result := TTyPropertyNode.Create;
  Result.FOwner := Self;
  Result.FParent := AParent;
  Result.FPropInfo := APropInfo;
  Result.FKind := AKind;
  Result.FIndex := AIndex;
  if AParent <> nil then Result.FDepth := AParent.FDepth else Result.FDepth := 0;
  FNodes.Add(Result);
end;

{ The object a node's property sits on: the root, or what the parent node's property holds. }
function TTyPropertyRows.HolderOf(ANode: TTyPropertyNode): TObject;
begin
  Result := nil;
  if ANode.FParent = nil then Exit(FRoot);
  case ANode.FParent.FKind of
    pnkSet: Result := HolderOf(ANode.FParent);
    pnkObject, pnkFont, pnkCollectionItem: Result := ValueObject(ANode.FParent);
  end;
end;

{ What an object-valued node holds: the sub-object, or for a collection item the item. }
function TTyPropertyRows.ValueObject(ANode: TTyPropertyNode): TObject;
var h, coll: TObject;
begin
  Result := nil;
  if ANode.FKind = pnkCollectionItem then
  begin
    coll := ValueObject(ANode.FParent);
    if (coll is TCollection) and (ANode.FIndex < TCollection(coll).Count) then
      Result := TCollection(coll).Items[ANode.FIndex];
    Exit;
  end;
  h := HolderOf(ANode);
  if (h <> nil) and (ANode.FPropInfo^.PropType^.Kind = tkClass) then
    Result := GetObjectProp(h, ANode.FPropInfo);
end;

function TTyPropertyRows.ObjectOf(ANode: TTyPropertyNode): TObject;
begin
  Result := ValueObject(ANode);
end;

{ How a property is shown. A class property is told apart by its DECLARED class, except that a
  component which is a csSubComponent of its holder (a TTyButton's sub-parts, say) is a part of
  the object -- expanded like any sub-object -- and not a reference to pick from a list. }
function TTyPropertyRows.KindOf(APropInfo: PPropInfo; AInstance: TObject): TTyPropertyNodeKind;
var cls: TClass; obj: TObject;
begin
  case APropInfo^.PropType^.Kind of
    tkMethod: Result := pnkMethod;
    tkSet:    Result := pnkSet;
    tkClass:
      begin
        cls := GetTypeData(APropInfo^.PropType)^.ClassType;
        try
          obj := GetObjectProp(AInstance, APropInfo);
        except
          obj := nil;
        end;
        if cls.InheritsFrom(TComponent) then
        begin
          if (obj is TComponent) and (csSubComponent in TComponent(obj).ComponentStyle) then
            Result := pnkObject
          else
            Result := pnkComponent;
        end
        else if cls.InheritsFrom(TFont) then Result := pnkFont
        else if cls.InheritsFrom(TStrings) then Result := pnkStrings
        else if cls.InheritsFrom(TCollection) then Result := pnkCollection
        else Result := pnkObject;
      end;
  else
    Result := pnkValue;
  end;
end;

{ Is this property shown? Readable, of a kind the grid can show and the filter lets through, not
  hidden by name or path, and not refused by OnFilterProperty. }
function TTyPropertyRows.Accept(AInstance: TObject; APropInfo: PPropInfo;
  AParent: TTyPropertyNode): Boolean;
const
  Showable = [tkInteger, tkChar, tkEnumeration, tkFloat, tkSet, tkMethod, tkSString, tkLString,
    tkAString, tkWString, tkClass, tkWChar, tkBool, tkInt64, tkQWord, tkUString];
var
  path: string;
begin
  Result := False;
  if APropInfo^.GetProc = nil then Exit;
  if not (APropInfo^.PropType^.Kind in Showable) then Exit;
  if not (APropInfo^.PropType^.Kind in FTypeFilter) then Exit;
  { A set wider than 32 elements does not fit the Int64 TypInfo hands sets through (it would be
    truncated, silently), and a class property only means something when it is a TPersistent. }
  if (APropInfo^.PropType^.Kind = tkSet)
    and (GetTypeData(APropInfo^.PropType)^.SetSize > SizeOf(Longint)) then Exit;
  if (APropInfo^.PropType^.Kind = tkClass)
    and not GetTypeData(APropInfo^.PropType)^.ClassType.InheritsFrom(TPersistent) then Exit;
  if AParent <> nil then path := AParent.Path + '.' + APropInfo^.Name else path := APropInfo^.Name;
  if (FHiddenProperties.IndexOf(APropInfo^.Name) >= 0)
    or (FHiddenProperties.IndexOf(path) >= 0) then Exit;
  Result := True;
  if Assigned(FOnFilterProperty) and (AInstance is TPersistent) then
    FOnFilterProperty(FSender, TPersistent(AInstance), APropInfo^.Name, Result);
end;

function ComparePropNames(A, B: Pointer): Integer;
begin
  Result := CompareText(PPropInfo(A)^.Name, PPropInfo(B)^.Name);
end;

procedure TTyPropertyRows.AddProperties(AEditor: TTyCustomValueListEditor; AParentRow: TTyValueRow;
  AParentNode: TTyPropertyNode; AInstance: TObject; ADepth: Integer);
var
  pl: PPropList;
  n, i: Integer;
  list: TFPList;
  pi: PPropInfo;
  nd: TTyPropertyNode;
  row: TTyValueRow;
begin
  if AInstance = nil then Exit;
  list := TFPList.Create;
  try
    n := GetPropList(AInstance.ClassInfo, pl);   // NameIndex order: the declaration order
    try
      for i := 0 to n - 1 do
        if Accept(AInstance, pl^[i], AParentNode) then list.Add(pl^[i]);
    finally
      FreeMem(pl);
    end;
    { GetPropList can sort too, but case-sensitively; the inspector order is CompareText. }
    if FOrder = poAlphabetical then list.Sort(@ComparePropNames);
    for i := 0 to list.Count - 1 do
    begin
      pi := PPropInfo(list[i]);
      nd := NewNode(AParentNode, pi, KindOf(pi, AInstance), 0);
      nd.FDepth := ADepth;
      if AParentRow = nil then row := AEditor.AddRow(pi^.Name, '')
      else row := AParentRow.AddChild(pi^.Name, '');
      nd.FRow := row;
      row.Data := nd;
      FillRow(nd);
      if Assigned(FOnGetPropertyRow) and (AInstance is TPersistent) then
        FOnGetPropertyRow(FSender, TPersistent(AInstance), pi, row);
      AddChildren(AEditor, nd);
    end;
  finally
    list.Free;
  end;
end;

{ The rows below a node: a set's elements; a sub-object's, a font's or a collection item's own
  properties; a collection's items. Collapsed, as the Object Inspector shows them. Objects go
  MaxDepth levels deep and no further -- the guard against a cycle (A.Other = B, B.Other = A)
  and against a getter that makes a new object every time it is asked. }
procedure TTyPropertyRows.AddChildren(AEditor: TTyCustomValueListEditor; ANode: TTyPropertyNode);
var
  comp: PTypeInfo;
  lo, hi, i: Integer;
  el, item: TTyPropertyNode;
  obj: TObject;
  coll: TCollection;
  r: TTyValueRow;
begin
  case ANode.FKind of
    pnkSet:
      begin
        SetRange(ANode.FPropInfo^.PropType, comp, lo, hi);
        for i := lo to hi do
        begin
          el := NewNode(ANode, ANode.FPropInfo, pnkSetElement, i);
          r := ANode.FRow.AddChild(ElementName(comp, i), '');
          el.FRow := r;
          r.Data := el;
          FillRow(el);
        end;
        ANode.FRow.Expanded := False;
      end;
    pnkObject, pnkFont:
      begin
        if ANode.FDepth >= FMaxDepth then Exit;
        try
          obj := ValueObject(ANode);
        except
          obj := nil;   // a getter that raises shows its error on the row; nothing to expand
        end;
        if obj = nil then Exit;
        ANode.FBuiltClass := obj.ClassType;
        AddProperties(AEditor, ANode.FRow, ANode, obj, ANode.FDepth + 1);
        ANode.FRow.Expanded := False;
      end;
    pnkCollection:
      begin
        if ANode.FDepth >= FMaxDepth then Exit;
        try
          obj := ValueObject(ANode);
        except
          obj := nil;
        end;
        if not (obj is TCollection) then Exit;
        coll := TCollection(obj);
        ANode.FBuiltCount := coll.Count;
        for i := 0 to coll.Count - 1 do
        begin
          item := NewNode(ANode, nil, pnkCollectionItem, i);
          item.FDepth := ANode.FDepth + 1;
          r := ANode.FRow.AddChild('[' + IntToStr(i) + ']', '');
          item.FRow := r;
          r.Data := item;
          FillRow(item);
          if item.FDepth < FMaxDepth then
          begin
            AddProperties(AEditor, r, item, coll.Items[i], item.FDepth + 1);
            r.Expanded := False;
          end;
        end;
        ANode.FRow.Expanded := False;
      end;
  end;
end;

{ Editor kind, options, read-only flag and value of a node's row. }
procedure TTyPropertyRows.FillRow(ANode: TTyPropertyNode);
var
  row: TTyValueRow;
  pt: PTypeInfo;
  td: PTypeData;
  i: Integer;
  opts: string;
  names: TStringList;
begin
  row := ANode.FRow;
  if ANode.FKind = pnkCollectionItem then
  begin
    row.ReadOnly := True;
    row.Value := ReadText(ANode);
    Exit;
  end;
  pt := ANode.FPropInfo^.PropType;
  case ANode.FKind of
    pnkMethod:
      row.EditorKind := vekReadOnly;
    pnkSetElement:
      row.EditorKind := vekBoolean;
    pnkFont:
      row.EditorKind := vekFont;
    pnkStrings:
      row.EditorKind := vekDialog;
    pnkComponent:
      begin
        row.EditorKind := vekEnum;
        names := TStringList.Create;
        try
          ComponentNames(ANode, names);
          row.EnumValues := names.Text;
        finally
          names.Free;
        end;
      end;
    pnkValue:
      case pt^.Kind of
        tkInteger:
          if TyIsColorType(pt) then row.EditorKind := vekColor
          else row.EditorKind := vekInteger;
        tkInt64, tkQWord:
          row.EditorKind := vekInteger;
        tkFloat:
          if IsDateType(pt) then row.EditorKind := vekText   // locale text, typed freely
          else row.EditorKind := vekFloat;
        tkBool:
          row.EditorKind := vekBoolean;
        tkEnumeration:
          begin
            row.EditorKind := vekEnum;
            td := GetTypeData(pt);
            opts := '';
            for i := td^.MinValue to td^.MaxValue do
            begin
              if opts <> '' then opts := opts + LineEnding;
              opts := opts + GetEnumName(pt, i);
            end;
            row.EnumValues := opts;
          end;
      else
        row.EditorKind := vekText;
      end;
  end;
  case ANode.FKind of
    { Shown, not edited: a set is edited through its elements, a sub-object and a collection
      through their own rows. }
    pnkMethod, pnkSet, pnkObject, pnkCollection:
      row.ReadOnly := True;
    { Written whole into the object they hold when there is no setter. }
    pnkFont, pnkStrings:
      row.ReadOnly := False;
  else
    row.ReadOnly := ANode.FPropInfo^.SetProc = nil;
  end;
  row.Value := ReadText(ANode);
end;

function TTyPropertyRows.ReadText(ANode: TTyPropertyNode): string;
var h, obj: TObject;
begin
  Result := '';
  if ANode = nil then Exit;
  try
    if ANode.FKind = pnkCollectionItem then
    begin
      obj := ValueObject(ANode);
      if obj is TCollectionItem then Result := TCollectionItem(obj).DisplayName;
      Exit;
    end;
    h := HolderOf(ANode);
    if h = nil then Exit;
    case ANode.FKind of
      pnkValue:  Result := SimpleText(h, ANode.FPropInfo);
      pnkMethod: Result := MethodText(h, ANode.FPropInfo);
      pnkSet:    Result := SetText(ANode.FPropInfo^.PropType, GetOrdProp(h, ANode.FPropInfo));
      pnkSetElement:
        Result := BoolText((GetOrdProp(h, ANode.FPropInfo) and (Int64(1) shl ANode.FIndex)) <> 0);
      pnkComponent:
        Result := ComponentText(GetObjectProp(h, ANode.FPropInfo));
      pnkFont:
        begin
          obj := GetObjectProp(h, ANode.FPropInfo);
          if obj is TFont then Result := FontText(TFont(obj));
        end;
      pnkCollection:
        begin
          obj := GetObjectProp(h, ANode.FPropInfo);
          if obj is TCollection then Result := Format(rsTyPropGridItems, [TCollection(obj).Count]);
        end;
      pnkObject, pnkStrings:
        begin
          obj := GetObjectProp(h, ANode.FPropInfo);
          if obj <> nil then Result := '(' + obj.ClassName + ')';
        end;
    end;
  except
    on E: Exception do Result := '(' + E.Message + ')';   // a getter that raises is shown, not fatal
  end;
end;

procedure TTyPropertyRows.WriteOn(ANode: TTyPropertyNode; AHolder: TObject; const AText: string);
var
  cur, bit: Int64;
  t, nm: string;
  sz: Integer;
  comp: TComponent;
  fnt: TFont;
begin
  if AHolder = nil then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
  if ANode.FPropInfo = nil then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
  if ANode.FKind = pnkFont then
  begin
    { Typed (or SetRowValue'd) 'Name, Size': the font's other attributes stay as they are. }
    fnt := TFont.Create;
    try
      if GetObjectProp(AHolder, ANode.FPropInfo) is TFont then
      begin
        fnt.PixelsPerInch := TFont(GetObjectProp(AHolder, ANode.FPropInfo)).PixelsPerInch;
        fnt.Assign(TFont(GetObjectProp(AHolder, ANode.FPropInfo)));
      end;
      if TyParseFontDescriptor(AText, nm, sz) then
        SetOrdProp(fnt, 'Size', sz);
      if nm <> '' then fnt.Name := nm;
      StoreFont(ANode, fnt);
    finally
      fnt.Free;
    end;
    Exit;
  end;
  if ANode.FPropInfo^.SetProc = nil then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
  case ANode.FKind of
    pnkValue: WriteSimple(AHolder, ANode.FPropInfo, AText);
    pnkSetElement:
      begin
        t := Trim(AText);
        cur := GetOrdProp(AHolder, ANode.FPropInfo);
        bit := Int64(1) shl ANode.FIndex;
        if SameText(t, 'True') then cur := cur or bit
        else if SameText(t, 'False') then cur := cur and not bit
        else raise InvalidValue(AText, ANode.Name);
        SetOrdProp(AHolder, ANode.FPropInfo, cur);
      end;
    pnkComponent:
      begin
        if SameText(Trim(AText), rsTyPropGridNone) or (Trim(AText) = '') then comp := nil
        else
        begin
          comp := FindComponentByName(ANode, Trim(AText));
          if comp = nil then
            raise EPropertyError.CreateFmt(rsTyPropGridNoComponent, [AText]);
        end;
        SetObjectProp(AHolder, ANode.FPropInfo, comp);
      end;
  else
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
  end;
end;

{ The font a node belongs to when it is one of a font's own rows (Size, Name, Style's elements):
  those are written into a copy, and the copy stored whole. }
function TTyPropertyRows.FontOwnerOf(ANode: TTyPropertyNode): TTyPropertyNode;
var p: TTyPropertyNode;
begin
  Result := nil;
  p := ANode.FParent;
  if (p <> nil) and (p.FKind = pnkSet) then p := p.FParent;
  if (p <> nil) and (p.FKind = pnkFont) then Result := p;
end;

procedure TTyPropertyRows.StoreFont(AFontNode: TTyPropertyNode; AFont: TFont);
var h, cur: TObject;
begin
  h := HolderOf(AFontNode);
  if h = nil then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [FontText(AFont), AFontNode.Name]);
  if AFontNode.FPropInfo^.SetProc <> nil then
    SetObjectProp(h, AFontNode.FPropInfo, AFont)   // a TFont setter assigns: LCL's convention
  else
  begin
    cur := GetObjectProp(h, AFontNode.FPropInfo);
    if not (cur is TFont) then
      raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [FontText(AFont), AFontNode.Name]);
    TFont(cur).Assign(AFont);
  end;
end;

procedure TTyPropertyRows.WriteFont(ANode: TTyPropertyNode; AFont: TFont);
begin
  StoreFont(ANode, AFont);
end;

procedure TTyPropertyRows.WriteStrings(ANode: TTyPropertyNode; AStrings: TStrings);
var h, cur: TObject;
begin
  h := HolderOf(ANode);
  if h = nil then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AStrings.Text, ANode.Name]);
  if ANode.FPropInfo^.SetProc <> nil then
    SetObjectProp(h, ANode.FPropInfo, AStrings)
  else
  begin
    cur := GetObjectProp(h, ANode.FPropInfo);
    if not (cur is TStrings) then
      raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AStrings.Text, ANode.Name]);
    TStrings(cur).Assign(AStrings);
  end;
end;

{ The component the inspected component's Owner calls AName -- or one OnGetComponentNames put on
  the list -- provided it fits the property's class. }
function TTyPropertyRows.FindComponentByName(ANode: TTyPropertyNode; const AName: string): TComponent;
var names: TStringList; i: Integer; cls: TClass;
begin
  Result := nil;
  cls := GetTypeData(ANode.FPropInfo^.PropType)^.ClassType;
  names := TStringList.Create;
  try
    ComponentNames(ANode, names);
    for i := 1 to names.Count - 1 do   // 0 is '(none)'
      if SameText(names[i], AName) and (names.Objects[i] is TComponent)
        and names.Objects[i].InheritsFrom(cls) then
        Exit(TComponent(names.Objects[i]));
  finally
    names.Free;
  end;
end;

function CompareNames(List: TStringList; A, B: Integer): Integer;
begin
  Result := CompareText(List[A], List[B]);
end;

{ Where a component reference picks from. A form, a data module or a frame is the top of what it
  holds: inspecting one, a reference (the form's ActiveControl) points at the components on it,
  not at its siblings under Application. Anything else picks from its Owner's components -- the
  form it sits on. }
function CandidateRoot(AInspected: TComponent): TComponent;
begin
  if (AInspected is TCustomForm) or (AInspected is TDataModule) or (AInspected is TCustomFrame) then
    Result := AInspected
  else
    Result := AInspected.Owner;
end;

procedure TTyPropertyRows.ComponentNames(ANode: TTyPropertyNode; AList: TStrings);
var
  base, c: TComponent;
  cls: TClass;
  i: Integer;
  found: TStringList;
  h, cur: TObject;
begin
  AList.Clear;
  cls := GetTypeData(ANode.FPropInfo^.PropType)^.ClassType;
  base := nil;
  if FRoot is TComponent then base := CandidateRoot(TComponent(FRoot));
  found := TStringList.Create;
  try
    if base <> nil then
    begin
      for i := 0 to base.ComponentCount - 1 do
      begin
        c := base.Components[i];
        if (c.Name <> '') and c.InheritsFrom(cls) then found.AddObject(c.Name, c);
      end;
      { The candidate root is a candidate itself: a control's reference to its form. }
      if (base.Name <> '') and base.InheritsFrom(cls) then found.AddObject(base.Name, base);
    end;
    found.CustomSort(@CompareNames);
    AList.Add(rsTyPropGridNone);
    AList.AddStrings(found);
  finally
    found.Free;
  end;
  h := HolderOf(ANode);
  cur := nil;
  if h <> nil then
    try
      cur := GetObjectProp(h, ANode.FPropInfo);
    except
      cur := nil;
    end;
  if Assigned(FOnGetComponentNames) and (h is TPersistent) then
    FOnGetComponentNames(FSender, TPersistent(h), ANode.FPropInfo, AList);
  { The current value is always on the list, wherever it came from: a list that cannot show what
    the property holds would read as if it held something else. }
  if (cur <> nil) and (AList.IndexOfObject(cur) < 0) then
    AList.AddObject(ComponentText(cur), cur);
end;

procedure TTyPropertyRows.WriteText(ANode: TTyPropertyNode; var AText: string);
var fontNode: TTyPropertyNode; cur: TObject; tmp: TFont;
begin
  fontNode := FontOwnerOf(ANode);
  if fontNode <> nil then
  begin
    cur := ValueObject(fontNode);
    if not (cur is TFont) then
      raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
    tmp := TFont.Create;
    try
      tmp.PixelsPerInch := TFont(cur).PixelsPerInch;   // so Height copies across unscaled
      tmp.Assign(TFont(cur));
      WriteOn(ANode, tmp, AText);
      StoreFont(fontNode, tmp);
    finally
      tmp.Free;
    end;
  end
  else
    WriteOn(ANode, HolderOf(ANode), AText);
  AText := ReadText(ANode);
end;

procedure TTyPropertyRows.RefreshValues(AExcept: TTyValueRow);
var i: Integer; n: TTyPropertyNode; names: TStringList;
begin
  for i := 0 to FNodes.Count - 1 do
  begin
    n := TTyPropertyNode(FNodes[i]);
    if (n.FRow <> nil) and (n.FRow <> AExcept) then n.FRow.Value := ReadText(n);
    if (n.FRow <> nil) and (n.FKind = pnkComponent) then
    begin
      names := TStringList.Create;
      try
        try
          ComponentNames(n, names);
          n.FRow.EnumValues := names.Text;
        except
          // keep the old list: a broken chain shows on the value already
        end;
      finally
        names.Free;
      end;
    end;
  end;
end;

function TTyPropertyRows.FindByPath(const APath: string): TTyPropertyNode;
var i: Integer;
begin
  Result := nil;
  if APath = '' then Exit;
  for i := 0 to FNodes.Count - 1 do
    if SameText(TTyPropertyNode(FNodes[i]).Path, APath) then Exit(TTyPropertyNode(FNodes[i]));
end;

function TTyPropertyRows.PropertyOf(ANode: TTyPropertyNode; out AInstance: TPersistent;
  out APropName: string): Boolean;
var h: TObject;
begin
  AInstance := nil;
  APropName := '';
  Result := False;
  if (ANode = nil) or (ANode.FKind = pnkCollectionItem) or (ANode.FPropInfo = nil) then Exit;
  try
    h := HolderOf(ANode);
  except
    h := nil;
  end;
  if not (h is TPersistent) then Exit;
  AInstance := TPersistent(h);
  APropName := ANode.FPropInfo^.Name;
  Result := True;
end;

function TTyPropertyRows.ChangeOf(ANode: TTyPropertyNode; const AText: string;
  out AInstance: TPersistent; out APropName, ANewValue: string): Boolean;
var cur, bit: Int64;
begin
  ANewValue := AText;
  Result := PropertyOf(ANode, AInstance, APropName);
  if not Result or (ANode.FKind <> pnkSetElement) then Exit;
  try
    cur := GetOrdProp(AInstance, ANode.FPropInfo);
  except
    Exit;   // the write will fail and say why
  end;
  bit := Int64(1) shl ANode.FIndex;
  if SameText(Trim(AText), 'True') then cur := cur or bit
  else if SameText(Trim(AText), 'False') then cur := cur and not bit;
  ANewValue := SetText(ANode.FPropInfo^.PropType, cur);
end;

function TTyPropertyRows.StructureChanged: Boolean;
var
  i, n: Integer;
  nd: TTyPropertyNode;
  obj: TObject;
  cls: TClass;
begin
  Result := False;
  for i := 0 to FNodes.Count - 1 do
  begin
    nd := TTyPropertyNode(FNodes[i]);
    if not (nd.FKind in [pnkObject, pnkFont, pnkCollection]) then Continue;
    if nd.FDepth >= FMaxDepth then Continue;   // nothing was built below it, nothing to fit
    try
      obj := ValueObject(nd);
    except
      obj := nil;
    end;
    if nd.FKind = pnkCollection then
    begin
      if obj is TCollection then n := TCollection(obj).Count else n := 0;
      if n <> nd.FBuiltCount then Exit(True);
    end
    else
    begin
      if obj <> nil then cls := obj.ClassType else cls := nil;
      if cls <> nd.FBuiltClass then Exit(True);
    end;
  end;
end;

procedure TTyPropertyRows.Build(AEditor: TTyCustomValueListEditor; ARoot: TPersistent);
begin
  AEditor.Clear;
  Clear;
  FRoot := ARoot;
  if ARoot <> nil then AddProperties(AEditor, nil, nil, ARoot, 0);
  AEditor.UpdateRows;
end;

{ ---- TTyCustomPropertyGrid ---- }

constructor TTyCustomPropertyGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRows := TTyPropertyRows.Create(Self);
  FRows.HiddenProperties.OnChange := @HiddenChanged;
  FExpanded := TStringList.Create;
  FExpanded.CaseSensitive := False;
  FExpanded.Sorted := True;
  FExpanded.Duplicates := dupIgnore;
  FExpanded.OnChange := @ExpandedChanged;
  { The editor's own OnEditRow is the grid's: the application's handler lives in the field the
    redeclared OnEditRow reads, and InternalEditRow decides between OnEditProperty, it and the
    TStrings editor. }
  TTyCustomValueListEditor(Self).OnEditRow := @InternalEditRow;
end;

destructor TTyCustomPropertyGrid.Destroy;
begin
  Clear;          // rows first: their Data points at the nodes
  FreeAndNil(FRows);
  FreeAndNil(FExpanded);
  inherited Destroy;
end;

procedure TTyCustomPropertyGrid.SetSelectedObject(AValue: TPersistent);
begin
  if FSelectedObject = AValue then Exit;
  if FSelectedObject is TComponent then TComponent(FSelectedObject).RemoveFreeNotification(Self);
  FSelectedObject := AValue;
  if FSelectedObject is TComponent then TComponent(FSelectedObject).FreeNotification(Self);
  if csLoading in ComponentState then Exit;   // Loaded builds, once the filters are read too
  RebuildRows(False);
end;

function TTyCustomPropertyGrid.GetSelectedComponent: TComponent;
begin
  if FSelectedObject is TComponent then Result := TComponent(FSelectedObject)
  else Result := nil;
end;

procedure TTyCustomPropertyGrid.SetSelectedComponent(AValue: TComponent);
begin
  SetSelectedObject(AValue);
end;

procedure TTyCustomPropertyGrid.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent <> nil) and (TObject(AComponent) = FSelectedObject) then
  begin
    { Before anything of it is freed (TComponent.Destroy notifies first): the rows go without
      reading it -- rebuilding reads only the paths, and the new root is nil. }
    FSelectedObject := nil;
    if not (csDestroying in ComponentState) and (FRows <> nil) then RebuildRows(False);
  end;
end;

procedure TTyCustomPropertyGrid.Loaded;
begin
  inherited Loaded;
  RebuildRows(False);
end;

function TTyCustomPropertyGrid.GetStyleTypeKey: string;
begin
  Result := 'TyPropertyGrid';
end;

function TTyCustomPropertyGrid.GetFixedKeyOptions: TTyKeyOptions;
begin
  Result := [];
end;

function TTyCustomPropertyGrid.GetPropertyOrder: TTyPropertyOrder;
begin
  Result := FRows.Order;
end;

procedure TTyCustomPropertyGrid.SetPropertyOrder(AValue: TTyPropertyOrder);
begin
  if FRows.Order = AValue then Exit;
  FRows.Order := AValue;
  if not (csLoading in ComponentState) then Rebuild;
end;

function TTyCustomPropertyGrid.GetTypeFilter: TTypeKinds;
begin
  Result := FRows.TypeFilter;
end;

procedure TTyCustomPropertyGrid.SetTypeFilter(AValue: TTypeKinds);
begin
  if FRows.TypeFilter = AValue then Exit;
  FRows.TypeFilter := AValue;
  if not (csLoading in ComponentState) then Rebuild;
end;

function TTyCustomPropertyGrid.GetHiddenProperties: TStrings;
begin
  Result := FRows.HiddenProperties;
end;

procedure TTyCustomPropertyGrid.SetHiddenProperties(AValue: TStrings);
begin
  FRows.HiddenProperties.Assign(AValue);   // OnChange rebuilds
end;

procedure TTyCustomPropertyGrid.HiddenChanged(Sender: TObject);
begin
  if not (csLoading in ComponentState) then Rebuild;
end;

{ ExpandedProperties is kept in step lazily: it is read back from the rows (HarvestExpanded) when
  somebody asks for it and before the rows are rebuilt, and written onto the rows (ApplyExpanded)
  after every build and whenever the list itself is changed. A path the current object does not
  have stays on the list for the next object that does. }
procedure TTyCustomPropertyGrid.HarvestExpanded;
var
  i, at: Integer;
  nd: TTyPropertyNode;
  p: string;
begin
  if (FRows = nil) or (FExpanded = nil) then Exit;
  FHarvesting := True;
  FExpanded.BeginUpdate;
  try
    for i := 0 to FRows.NodeCount - 1 do
    begin
      nd := FRows.Node(i);
      if (nd.Row = nil) or not nd.Row.HasChildren then Continue;
      p := nd.Path;
      at := FExpanded.IndexOf(p);
      if nd.Row.Expanded then
      begin
        if at < 0 then FExpanded.Add(p);
      end
      else if at >= 0 then
        FExpanded.Delete(at);
    end;
  finally
    FExpanded.EndUpdate;
    FHarvesting := False;
  end;
end;

procedure TTyCustomPropertyGrid.ApplyExpanded;
var
  i: Integer;
  nd: TTyPropertyNode;
begin
  if (FRows = nil) or (FExpanded = nil) then Exit;
  for i := 0 to FRows.NodeCount - 1 do
  begin
    nd := FRows.Node(i);
    if (nd.Row = nil) or not nd.Row.HasChildren then Continue;
    nd.Row.Expanded := FExpanded.IndexOf(nd.Path) >= 0;
  end;
  UpdateRows;
end;

function TTyCustomPropertyGrid.GetExpandedProperties: TStrings;
begin
  HarvestExpanded;
  Result := FExpanded;
end;

procedure TTyCustomPropertyGrid.SetExpandedProperties(AValue: TStrings);
begin
  FExpanded.Assign(AValue);   // OnChange applies
end;

procedure TTyCustomPropertyGrid.ExpandedChanged(Sender: TObject);
begin
  if FHarvesting or (csLoading in ComponentState) then Exit;
  ApplyExpanded;
end;

function TTyCustomPropertyGrid.GetOnFilterProperty: TTyFilterPropertyEvent;
begin
  Result := FRows.OnFilterProperty;
end;

procedure TTyCustomPropertyGrid.SetOnFilterProperty(AValue: TTyFilterPropertyEvent);
begin
  FRows.OnFilterProperty := AValue;
end;

function TTyCustomPropertyGrid.GetOnGetComponentNames: TTyGetComponentNamesEvent;
begin
  Result := FRows.OnGetComponentNames;
end;

procedure TTyCustomPropertyGrid.SetOnGetComponentNames(AValue: TTyGetComponentNamesEvent);
begin
  FRows.OnGetComponentNames := AValue;
end;

function TTyCustomPropertyGrid.GetOnGetPropertyRow: TTyGetPropertyRowEvent;
begin
  Result := FRows.OnGetPropertyRow;
end;

procedure TTyCustomPropertyGrid.SetOnGetPropertyRow(AValue: TTyGetPropertyRowEvent);
begin
  FRows.OnGetPropertyRow := AValue;
end;

procedure TTyCustomPropertyGrid.Rebuild;
begin
  RebuildRows(True);
end;

{ The rows again from SelectedObject. Expansion comes back from ExpandedProperties and the current
  row by its path, so neither is lost to a rebuild nor to a move to another object of a like kind;
  AKeepTop keeps the scroll position too (the same object again), else the list starts at the top. }
procedure TTyCustomPropertyGrid.RebuildRows(AKeepTop: Boolean);
var
  cur: TTyValueRow;
  nd: TTyPropertyNode;
  selPath: string;
  keptTop, at: Integer;
begin
  if FRows = nil then Exit;
  HarvestExpanded;
  selPath := '';
  cur := FlatRowAt(ItemIndex);
  nd := FRows.NodeOf(cur);
  if nd <> nil then selPath := nd.Path;
  keptTop := TopIndex;
  Inc(FBuildCount);
  FRows.Build(Self, FSelectedObject);
  ApplyExpanded;
  nd := FRows.FindByPath(selPath);
  if nd <> nil then at := FlatIndexOf(nd.Row) else at := -1;
  SetItemIndexSilent(at);
  if AKeepTop then TopIndex := keptTop else TopIndex := 0;
  Invalidate;
end;

procedure TTyCustomPropertyGrid.Refresh;
begin
  if FRows = nil then Exit;
  if FRows.StructureChanged then
    RebuildRows(True)
  else
  begin
    FRows.RefreshValues(nil);
    Invalidate;
  end;
end;

function TTyCustomPropertyGrid.PropertyAt(ARow: TTyValueRow; out AInstance: TPersistent;
  out APropName: string): Boolean;
begin
  AInstance := nil;
  APropName := '';
  if FRows = nil then Exit(False);
  Result := FRows.PropertyOf(FRows.NodeOf(ARow), AInstance, APropName);
end;

{ The row at a display position: the same pre-order walk over expanded rows the editor lays out. }
function TTyCustomPropertyGrid.FlatRowAt(AFlat: Integer): TTyValueRow;
var n: Integer;

  function Walk(ARow: TTyValueRow): TTyValueRow;
  var i: Integer;
  begin
    if n = AFlat then Exit(ARow);
    Inc(n);
    Result := nil;
    if ARow.Expanded then
      for i := 0 to ARow.ChildCount - 1 do
      begin
        Result := Walk(ARow.Child[i]);
        if Result <> nil then Exit;
      end;
  end;

var i: Integer;
begin
  Result := nil;
  n := 0;
  if AFlat < 0 then Exit;
  for i := 0 to RowCount - 1 do
  begin
    Result := Walk(Row(i));
    if Result <> nil then Exit;
  end;
end;

{ The display position of ARow, -1 when a collapsed ancestor hides it. }
function TTyCustomPropertyGrid.FlatIndexOf(ARow: TTyValueRow): Integer;
var n, res: Integer;

  procedure Walk(R: TTyValueRow);
  var i: Integer;
  begin
    if res >= 0 then Exit;
    if R = ARow then begin res := n; Exit; end;
    Inc(n);
    if R.Expanded then
      for i := 0 to R.ChildCount - 1 do Walk(R.Child[i]);
  end;

var i: Integer;
begin
  n := 0;
  res := -1;
  if ARow <> nil then
    for i := 0 to RowCount - 1 do Walk(Row(i));
  Result := res;
end;

function TTyCustomPropertyGrid.WriteProperty(ANode: TTyPropertyNode; AKind: TTyPropertyWriteKind;
  AObject: TObject; AExceptRow: TTyValueRow; var AText: string): Boolean;
var
  inst: TPersistent;
  nm, newText, described: string;
  known, allow: Boolean;
  gen: Integer;
begin
  Result := False;
  { Listed at design time, never written: the designer would not know the component changed. }
  if csDesigning in ComponentState then Exit;
  case AKind of
    pwkFont:    described := FontText(TFont(AObject));
    pwkStrings: described := TStrings(AObject).Text;
  else
    described := AText;
  end;
  known := FRows.ChangeOf(ANode, described, inst, nm, newText);
  if not known then nm := ANode.Name;
  gen := FBuildCount;
  if known and Assigned(FOnPropertyChanging) then
  begin
    allow := True;
    FOnPropertyChanging(Self, inst, nm, newText, allow);
    { A handler that rebuilt the rows took ANode with them: nothing more can be done with it. }
    if not allow or (gen <> FBuildCount) then Exit;
  end;
  try
    case AKind of
      pwkFont:
        begin
          FRows.WriteFont(ANode, TFont(AObject));
          AText := FRows.ReadText(ANode);
        end;
      pwkStrings:
        FRows.WriteStrings(ANode, TStrings(AObject));
    else
      FRows.WriteText(ANode, AText);   // raises -> nothing written
    end;
  except
    on E: Exception do
    begin
      { The setter may have moved something before it raised: every row shows the object. }
      FRows.RefreshValues(nil);
      Invalidate;
      if not Assigned(FOnPropertyError) then raise;
      FOnPropertyError(Self, inst, nm, E);
      Exit;
    end;
  end;
  { A setter often moves other properties too (AutoSize -> Width): re-read the rest. The row
    being committed is left for the editor, which compares AText with its old value. }
  FRows.RefreshValues(AExceptRow);
  Invalidate;
  if Assigned(FOnPropertyChanged) and FRows.PropertyOf(ANode, inst, nm) then
    FOnPropertyChanged(Self, inst, nm);
  Result := gen = FBuildCount;
end;

function TTyCustomPropertyGrid.CanCommitValue(ARow: TTyValueRow; var AText: string): Boolean;
var nd: TTyPropertyNode;
begin
  if FRows = nil then Exit(inherited CanCommitValue(ARow, AText));   // being destroyed
  nd := FRows.NodeOf(ARow);
  if nd = nil then Exit(inherited CanCommitValue(ARow, AText));
  if (CommitFont <> nil) and (nd.Kind = pnkFont) then
    Result := WriteProperty(nd, pwkFont, CommitFont, ARow, AText)   // the font dialog's pick, whole
  else
    Result := WriteProperty(nd, pwkText, nil, ARow, AText);
end;

procedure TTyCustomPropertyGrid.InternalEditRow(Sender: TObject; ARow: TTyValueRow);
var
  nd: TTyPropertyNode;
  inst: TPersistent;
  nm: string;
  handled: Boolean;
  gen: Integer;
begin
  if (FRows = nil) or (csDesigning in ComponentState) then Exit;
  gen := FBuildCount;
  handled := False;
  if Assigned(FOnEditProperty) then
  begin
    PropertyAt(ARow, inst, nm);
    FOnEditProperty(Self, ARow, inst, nm, handled);
  end;
  if not handled and (gen = FBuildCount) and Assigned(FOnEditRowApp) then
  begin
    FOnEditRowApp(Self, ARow);
    handled := True;
  end;
  if handled or (gen <> FBuildCount) then
  begin
    { The handler wrote the property (or rebuilt the rows): show the object. }
    if gen = FBuildCount then FRows.RefreshValues(nil);
    Invalidate;
    Exit;
  end;
  nd := FRows.NodeOf(ARow);
  if (nd <> nil) and (nd.Kind = pnkStrings) then EditStringsRow(ARow);
end;

function TTyCustomPropertyGrid.ExecuteStringsDialog(const ATitle: string; AStrings: TStrings): Boolean;
var s: string;
begin
  s := AStrings.Text;
  if (s <> '') and (Copy(s, Length(s) - Length(LineEnding) + 1, MaxInt) = LineEnding) then
    SetLength(s, Length(s) - Length(LineEnding));   // no empty line under the last entry
  Result := TyTextQuery(ATitle, rsTyPropGridStringsPrompt, s);
  if Result then AStrings.Text := s;
end;

procedure TTyCustomPropertyGrid.EditStringsRow(ARow: TTyValueRow);
var nd: TTyPropertyNode; cur: TObject; tmp: TStringList; dummy: string;
begin
  nd := FRows.NodeOf(ARow);
  if (nd = nil) or (nd.Kind <> pnkStrings) or ReadOnly or ARow.ReadOnly then Exit;
  if csDesigning in ComponentState then Exit;
  cur := FRows.ObjectOf(nd);
  tmp := TStringList.Create;
  try
    if cur is TStrings then tmp.Assign(TStrings(cur));
    if ExecuteStringsDialog(Format(rsTyPropGridStringsTitle, [nd.Path]), tmp) then
    begin
      dummy := '';
      WriteProperty(nd, pwkStrings, tmp, nil, dummy);
    end;
  finally
    tmp.Free;
  end;
end;

{ Space flips a boolean row -- the list itself does nothing with Space in single selection. }
procedure TTyCustomPropertyGrid.KeyDown(var Key: Word; Shift: TShiftState);
var r: TTyValueRow;
begin
  if (Key = VK_SPACE) and (Shift = []) and not ReadOnly and (EditingRow < 0)
    and not (csDesigning in ComponentState) then
  begin
    r := FlatRowAt(ItemIndex);
    if (r <> nil) and (r.EditorKind = vekBoolean) and not r.ReadOnly then
    begin
      Key := 0;
      SetRowValue(r, BoolText(not SameText(r.Value, 'True')));
      Exit;
    end;
  end;
  inherited KeyDown(Key, Shift);
end;

initialization
  TyTryRegisterTypeKeyParent('TyPropertyGrid', 'TyValueListEditor');

finalization
  TyUnregisterTypeKeyParent('TyPropertyGrid');

end.
