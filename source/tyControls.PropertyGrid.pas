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
  Classes, SysUtils, Types, TypInfo, Graphics, Controls, Forms, LCLType, Menus,
  tyControls.ValueListEditor, tyControls.Menu;

const
  { The kinds the grid shows by default: everything it can show except event handlers. Untyped,
    so it can be the published TypeFilter's default. }
  TyPropertyGridDefaultTypeFilter = [Low(TTypeKind)..High(TTypeKind)] - [tkMethod];
  TyPropertyGridDefaultMaxDepth = 6;
  { What a collection row reads with several objects selected. }
  TyPropertyGridSeveral = '(…)';

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
    pnkMethod,          // an event handler, shown by name, read-only
    pnkCustom,          // a kind the grid does not show itself, shown through OnGetPropertyText
    pnkCategory);       // a category's heading (ShowCategories); its rows are the properties in it

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
    { AddChildren built the rows below it (a descendant's BuildPropertyRow may not have): only
      then does Refresh compare FBuiltClass / FBuiltCount with the object. }
    FChildrenBuilt: Boolean;
    { Several objects selected and this sub-object is not of one class in all of them (or is
      missing from some): the row is read-only and has nothing below it. }
    FMixed: Boolean;
    { Some selected object's property has no setter (with one object: the property has none). }
    FNoSetter: Boolean;
    { A category heading's name. }
    FCategory: string;
    { FilterText is set and something below this row matches it: the row is opened for it. }
    FFilterOpen: Boolean;
  public
    { The property's name; a set element's name; '[i]' for a collection item; '@' and the name
      for a category heading. }
    function Name: string;
    { Dotted from the root: 'Font.Style.fsBold', 'Columns[0].Width'. A category is not part of
      its properties' paths ('Font', not '@Appearance.Font'); its own path is '@Appearance'. }
    function Path: string;
    { The object that HAS this node's property (for a set element, the set's owner; for a
      collection item, nil). Resolved from the root on every call; nil when the chain is broken.
      With several objects selected, the first one's. }
    function Instance: TObject;
    property Parent: TTyPropertyNode read FParent;
    property PropInfo: PPropInfo read FPropInfo;   // nil for a collection item
    property Kind: TTyPropertyNodeKind read FKind;
    property Index: Integer read FIndex;           // set element ordinal / collection item index
    property Depth: Integer read FDepth;           // object nesting level, 0 at the root
    property Row: TTyValueRow read FRow;
  end;

  { Asked about every published property TypeFilter and HiddenProperties let through. AShow
    arrives True for a property the grid can show and False for one it cannot by itself (an
    interface, a variant, a record, a set of more than 32 elements, a class that is not a
    TPersistent); such a property is listed when the handler sets AShow and OnGetPropertyText
    supplies its text. }
  TTyFilterPropertyEvent = procedure(Sender: TObject; AInstance: TPersistent;
    const APropName: string; var AShow: Boolean) of object;

  { The text a property's row shows, instead of the grid's own (set AHandled). For a kind the
    grid does not show itself this is the only text there is. Asked for each selected object. }
  TTyGetPropertyTextEvent = procedure(Sender: TObject; AInstance: TPersistent;
    APropInfo: PPropInfo; var AText: string; var AHandled: Boolean) of object;

  { Write AText into the property yourself (set AHandled): the grid's own conversion is skipped.
    A kind the grid does not show itself is editable only while this is assigned. Asked for
    each selected object; an exception goes the way a setter's does (OnPropertyError). }
  TTySetPropertyTextEvent = procedure(Sender: TObject; AInstance: TPersistent;
    APropInfo: PPropInfo; const AText: string; var AHandled: Boolean) of object;

  { The names a component-reference row offers. AList arrives holding '(none)' and the
    type-compatible components of the candidate root, each name with its component in Objects[]:
    the root is the inspected component itself when it is a form, a data module or a frame (the
    components on it), else its Owner -- and the root itself is a candidate too. Add, remove or
    reorder entries (a component from another form, say: add its name WITH the component in
    Objects[], or it cannot be resolved). The current value is listed afterwards if the list lost
    it. }
  TTyGetComponentNamesEvent = procedure(Sender: TObject; AInstance: TPersistent;
    APropInfo: PPropInfo; AList: TStrings) of object;

  { A property's row has just been built (with the rows below it): change its editor kind, its
    options, its DisplayValue, its style, or make it read-only. }
  TTyGetPropertyRowEvent = procedure(Sender: TObject; AInstance: TPersistent;
    APropInfo: PPropInfo; ARow: TTyValueRow) of object;

  { The category a top-level property is listed under while ShowCategories is on. ACategory
    arrives holding the built-in one (TyPropertyGridCategoryOf); change it to any other, a name
    of the application's own included. An empty name counts as Other. With several objects
    selected, asked for the first. }
  TTyGetPropertyCategoryEvent = procedure(Sender: TObject; AInstance: TPersistent;
    const APropName: string; var ACategory: string) of object;

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

  { The object -> rows mapping. It maps one object or several at once: with several, a row is a
    property every one of them has (same name, same type), and every node is resolved in each
    object in turn -- the "In" functions below take the object's position among the roots. }
  TTyPropertyRows = class
  private
    FSender: TObject;
    FRoots: array of TPersistent;
    FNodes: TFPList;
    FTypeFilter: TTypeKinds;
    FHiddenProperties: TStringList;
    FOrder: TTyPropertyOrder;
    FMaxDepth: Integer;
    FOnFilterProperty: TTyFilterPropertyEvent;
    FOnGetComponentNames: TTyGetComponentNamesEvent;
    FOnGetPropertyRow: TTyGetPropertyRowEvent;
    FOnGetPropertyText: TTyGetPropertyTextEvent;
    FOnSetPropertyText: TTySetPropertyTextEvent;
    FShowCategories: Boolean;
    FFilterText: string;
    FOnGetPropertyCategory: TTyGetPropertyCategoryEvent;
    procedure SetHiddenProperties(AValue: TStringList);
    { GetPropText for AInstance's property: True with the text when it was handled. }
    function CustomText(AInstance: TObject; APropInfo: PPropInfo; out AText: string): Boolean;
    { A property's node and row, under AParentRow (nil: a top-level row), built by BuildRow. }
    procedure AddPropertyRow(AEditor: TTyCustomValueListEditor; AParentRow: TTyValueRow;
      AParentNode: TTyPropertyNode; APropInfo: PPropInfo; const AInstances: array of TObject;
      ADepth: Integer);
    { The top-level properties (APropInfos, in their order) under a heading per category. }
    procedure AddCategories(AEditor: TTyCustomValueListEditor; APropInfos: TFPList;
      const AInstances: array of TObject);
    { FilterText: hide every row that neither matches it nor has a match below it nor sits
      below a match, and open the rows a match is below. }
    procedure ApplyFilter(AEditor: TTyCustomValueListEditor);
    function NewNode(AParent: TTyPropertyNode; APropInfo: PPropInfo; AKind: TTyPropertyNodeKind;
      AIndex: Integer): TTyPropertyNode;
    function Accept(AInstance: TObject; APropInfo: PPropInfo; AParent: TTyPropertyNode): Boolean;
    { APropInfo (taken from AInstances[0]) is a property every other instance has too: by name,
      of the same type, and shown by the filters there as well. }
    function SharedByAll(const AInstances: array of TObject; APropInfo: PPropInfo;
      AParent: TTyPropertyNode): Boolean;
    function KindOf(APropInfo: PPropInfo; AInstance: TObject): TTyPropertyNodeKind;
    procedure AddProperties(AEditor: TTyCustomValueListEditor; AParentRow: TTyValueRow;
      AParentNode: TTyPropertyNode; const AInstances: array of TObject; ADepth: Integer);
    { The class every root's sub-object has at ANode, nil when there is none; AMixed when they
      differ (or some root has none). }
    procedure SubObjectClass(ANode: TTyPropertyNode; out AClass: TClass; out AMixed: Boolean);
    function HolderOf(ANode: TTyPropertyNode): TObject;
    function ValueObject(ANode: TTyPropertyNode): TObject;
    function FontOwnerOf(ANode: TTyPropertyNode): TTyPropertyNode;
    procedure StoreFont(AFontNode: TTyPropertyNode; ARoot: Integer; AFont: TFont);
    function FindComponentByName(ANode: TTyPropertyNode; const AName: string): TComponent;
    procedure WriteOn(ANode: TTyPropertyNode; AHolder: TObject; APropInfo: PPropInfo;
      const AText: string);
    function GetRoot: TPersistent;
    function GetRoots(AIndex: Integer): TPersistent;
  protected
    { The three ways a descendant (TTyCustomPropertyGrid's own, which hands them to the grid's
      virtual methods) takes part in the mapping. BuildRow fills ANode's row (ANode.Row exists,
      its key the property's name) and adds the rows below it; the default is FillRow and then
      AddChildren. GetPropText / SetPropText are asked before the grid's own conversion of any
      property (not of a set's element, which is part of its set); True = handled. The defaults
      ask OnGetPropertyText / OnSetPropertyText. }
    procedure BuildRow(AEditor: TTyCustomValueListEditor; ANode: TTyPropertyNode); virtual;
    function GetPropText(AInstance: TPersistent; APropInfo: PPropInfo;
      var AText: string): Boolean; virtual;
    function SetPropText(AInstance: TPersistent; APropInfo: PPropInfo;
      const AText: string): Boolean; virtual;
  public
    constructor Create(ASender: TObject);
    destructor Destroy; override;
    { Replace AEditor's rows with ARoot's properties (none when ARoot is nil). }
    procedure Build(AEditor: TTyCustomValueListEditor; ARoot: TPersistent); overload;
    { The same for several objects at once: the properties all of them have. A nil entry is
      skipped. A sub-object is expanded only when it is of one class in every object, and a
      collection not at all (its items cannot be matched up one to one). }
    procedure Build(AEditor: TTyCustomValueListEditor; const ARoots: array of TPersistent); overload;
    { How many objects the rows stand for, and each of them. }
    function RootCount: Integer;
    property Roots[AIndex: Integer]: TPersistent read GetRoots;
    { ANode resolved in the ARoot-th object: the object that has its property, that property's
      own PPropInfo there (a property of the same name on another class has another one), and
      what an object-valued node holds there. nil when the chain is broken. }
    function HolderIn(ANode: TTyPropertyNode; ARoot: Integer): TObject;
    function PropInfoIn(ANode: TTyPropertyNode; AHolder: TObject; ARoot: Integer): PPropInfo;
    function ValueObjectIn(ANode: TTyPropertyNode; ARoot: Integer): TObject;
    { ReadText, PropertyOf, ChangeOf and the writes, for the ARoot-th object alone. }
    function ReadTextIn(ANode: TTyPropertyNode; ARoot: Integer): string;
    function PropertyOfIn(ANode: TTyPropertyNode; ARoot: Integer; out AInstance: TPersistent;
      out APropName: string): Boolean;
    function ChangeOfIn(ANode: TTyPropertyNode; ARoot: Integer; const AText: string;
      out AInstance: TPersistent; out APropName, ANewValue: string): Boolean;
    procedure WriteTextIn(ANode: TTyPropertyNode; ARoot: Integer; const AText: string);
    procedure WriteFontIn(ANode: TTyPropertyNode; ARoot: Integer; AFont: TFont);
    procedure WriteStringsIn(ANode: TTyPropertyNode; ARoot: Integer; AStrings: TStrings);
    { What BuildRow does by default: FillRow sets the row's editor kind, options, read-only flag
      and value from the property; AddChildren adds the rows below it (a set's elements, a
      sub-object's or a font's properties, a collection's items), collapsed. }
    procedure FillRow(ANode: TTyPropertyNode);
    procedure AddChildren(AEditor: TTyCustomValueListEditor; ANode: TTyPropertyNode);
    { OnGetPropertyText / OnSetPropertyText themselves (what GetText and SetText do by
      default): True when the handler handled it. }
    function CallGetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
      var AText: string): Boolean;
    function CallSetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
      const AText: string): Boolean;
    { The category a top-level property of AInstance goes under: the built-in one, then
      OnGetPropertyCategory's say. }
    function CategoryOf(AInstance: TObject; APropInfo: PPropInfo): string;
    { Drop the nodes. The rows they belong to must be cleared by the caller. }
    procedure Clear;
    function NodeOf(ARow: TTyValueRow): TTyPropertyNode;
    function NodeCount: Integer;
    function Node(AIndex: Integer): TTyPropertyNode;
    { The display text of ANode, read from the object now. With several objects: the text they
      all read, or '' when they do not agree; a collection reads '(…)'. }
    function ReadText(ANode: TTyPropertyNode): string;
    { Parse AText and write it into the object (each object in turn, when there are several).
      Raises (EConvertError, ERangeError, EPropertyError, or whatever the setter raises) and
      writes nothing more when it cannot -- objects before the one that failed keep what was
      written; on success AText becomes what the objects now read back. }
    procedure WriteText(ANode: TTyPropertyNode; var AText: string);
    { A TFont property, written back whole: through its setter when it has one, else by Assign
      into the font it holds. }
    procedure WriteFont(ANode: TTyPropertyNode; AFont: TFont);
    { A TStrings property, likewise. }
    procedure WriteStrings(ANode: TTyPropertyNode; AStrings: TStrings);
    { What an object-valued node holds now: the sub-object, the font, the list, the collection,
      the referenced component, or for a collection item the item. The first object's. }
    function ObjectOf(ANode: TTyPropertyNode): TObject;
    { The names a component-reference node offers, '(none)' first; Objects[] holds each component. }
    procedure ComponentNames(ANode: TTyPropertyNode; AList: TStrings);
    { Re-read every row's value from the object, except AExcept (the row being committed). }
    procedure RefreshValues(AExcept: TTyValueRow = nil);
    { The node whose Path is APath (case-insensitive), nil when there is none. }
    function FindByPath(const APath: string): TTyPropertyNode;
    { The property a node's row edits: its object and its name (a set element's is the set's).
      False for a collection item, or when the chain to the object is broken. The first object's. }
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
    { The (first) object the rows stand for, nil when none. }
    property Root: TPersistent read GetRoot;
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
    property OnGetPropertyText: TTyGetPropertyTextEvent read FOnGetPropertyText
      write FOnGetPropertyText;
    property OnSetPropertyText: TTySetPropertyTextEvent read FOnSetPropertyText
      write FOnSetPropertyText;
    { The top-level properties under a heading row per category (TTyValueRow.Heading): the
      built-in ones in the order Layout, Appearance, Behavior, Events, then the application's
      own by name, then Other; an empty category has no heading. Within one, PropertyOrder. }
    property ShowCategories: Boolean read FShowCategories write FShowCategories;
    property OnGetPropertyCategory: TTyGetPropertyCategoryEvent read FOnGetPropertyCategory
      write FOnGetPropertyCategory;
    { Only the rows whose name holds this text (ignoring case; '' = every row), the rows above
      them -- opened -- and the rows below them. Applied by Build. }
    property FilterText: string read FFilterText write FFilterText;
  end;

  { What is done to a collection: an item added, deleted, or moved to another index. }
  TTyCollectionAction = (caAdd, caDelete, caMove);

  { About to change ACollection; set AAllow to False to refuse. caAdd: the new item will take
    index AIndex (= ANewIndex). caDelete: the item at AIndex goes (ANewIndex is -1). caMove: the
    item at AIndex moves to ANewIndex. Refusing and doing the change another way is how a host
    whose own data follows the items (a string grid's cells follow its columns by index) keeps
    them together: the grid only uses TCollection's own Add, Delete and Index. }
  TTyCollectionChangingEvent = procedure(Sender: TObject; ACollection: TCollection;
    AAction: TTyCollectionAction; AIndex, ANewIndex: Integer; var AAllow: Boolean) of object;

  { ACollection has changed; the indexes as for TTyCollectionChangingEvent (for caAdd, where the
    new item ended up). The rows are already rebuilt. }
  TTyCollectionChangedEvent = procedure(Sender: TObject; ACollection: TCollection;
    AAction: TTyCollectionAction; AIndex, ANewIndex: Integer) of object;

  { Create the item to add yourself (a particular item class, first values): create it in
    ACollection and hand it back in AItem. Left nil, the grid calls ACollection.Add. The grid
    then moves it to where it was asked to go. }
  TTyCreateCollectionItemEvent = procedure(Sender: TObject; ACollection: TCollection;
    var AItem: TCollectionItem) of object;

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
    FSelected: array of TPersistent;   // the selection, in the order it was given; no nil, no repeat
    FOnEditRowApp: TTyValueEditEvent;
    FExpanded: TStringList;
    FHarvesting: Boolean;
    FBuildCount: Integer;
    FOnPropertyChanging: TTyPropertyChangingEvent;
    FOnPropertyChanged: TTyPropertyChangedEvent;
    FOnPropertyError: TTyPropertyErrorEvent;
    FOnEditProperty: TTyEditPropertyEvent;
    FOnCollectionChanging: TTyCollectionChangingEvent;
    FOnCollectionChanged: TTyCollectionChangedEvent;
    FOnCreateCollectionItem: TTyCreateCollectionItemEvent;
    { The built-in menu of a collection row and an item row, built on first use, and the path of
      the row it was opened on. }
    FMenu: TTyPopupMenu;
    FMenuAdd, FMenuDelete, FMenuUp, FMenuDown: TMenuItem;
    FMenuPath: string;
    { The category headings shown so far ('@Layout'): one shown for the first time opens. }
    FSeenCategories: TStringList;
    { ExpandedProperties as it was before FilterText was set, given back when it is cleared. }
    FPreFilterExpanded: TStringList;
    FFiltering: Boolean;
    function GetSelectedObject: TPersistent;
    procedure SetSelectedObject(AValue: TPersistent);
    function GetSelectedObjects(AIndex: Integer): TPersistent;
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
    function GetOnGetPropertyText: TTyGetPropertyTextEvent;
    procedure SetOnGetPropertyText(AValue: TTyGetPropertyTextEvent);
    function GetOnSetPropertyText: TTySetPropertyTextEvent;
    procedure SetOnSetPropertyText(AValue: TTySetPropertyTextEvent);
    function GetShowCategories: Boolean;
    procedure SetShowCategories(AValue: Boolean);
    function GetOnGetPropertyCategory: TTyGetPropertyCategoryEvent;
    procedure SetOnGetPropertyCategory(AValue: TTyGetPropertyCategoryEvent);
    function GetFilterText: string;
    procedure SetFilterText(const AValue: string);
    { A category heading shown for the first time is opened (its path goes on ExpandedProperties);
      from then on it is whatever the user (or the list) made it. }
    procedure OpenNewCategories;
    { ASelect, when given, is the path of the row to make current (and scroll into view)
      instead of the one that was. }
    procedure RebuildRows(AKeepTop: Boolean; const ASelect: string = '';
      AHarvest: Boolean = True);
    { Can the user add, delete and move items here: a collection or an item row, one object,
      not ReadOnly, not at design time. }
    function CollectionEditable(ANode: TTyPropertyNode): Boolean;
    { The one place a collection changes: resolve APath, ask OnCollectionChanging, do it, keep
      the expanded rows with their items, rebuild, put the current row on the item, announce. }
    function DoCollectionAction(AAction: TTyCollectionAction; const APath: string;
      ADelta: Integer): TCollectionItem;
    procedure RemapExpanded(const ACollPath: string; AAction: TTyCollectionAction;
      AFrom, ATo: Integer);
    procedure BuildCollectionMenu;
    procedure MenuAddClick(Sender: TObject);
    procedure MenuDeleteClick(Sender: TObject);
    procedure MenuUpClick(Sender: TObject);
    procedure MenuDownClick(Sender: TObject);
  protected
    function CanCommitValue(ARow: TTyValueRow; var AText: string): Boolean; override;
    procedure SeedEditFont(ARow: TTyValueRow; AFont: TFont); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { A right click (or the menu key) on a collection or item row shows the built-in menu: Add
      Item, Delete Item, Move Up, Move Down. Only while PopupMenu is not assigned -- the
      application's own menu wins, and it can do the same through the public methods. }
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    { Shows the built-in menu at screen point (X, Y). A descendant (or a test) can show it its
      own way. }
    procedure ShowCollectionMenu(AMenu: TPopupMenu; X, Y: Integer); virtual;
    { The built-in menu, nil until it is first needed. }
    property CollectionMenu: TTyPopupMenu read FMenu;
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
    { Builds the row of one property (not of a category heading, a set's element or a collection's
      item): ANode.Row is already made -- its key the property's name, its Data the node -- and
      this fills it and adds the rows below it. The default is PropertyRows.FillRow, then
      PropertyRows.AddChildren. Override it to make the rows of some type your own way: set the
      editor kind, the options, ReadOnly, add rows below or none. The value is read and written
      through GetPropertyText / SetPropertyText (override those too, for a type whose text the
      grid does not make itself), and OnGetPropertyRow still comes after. }
    procedure BuildPropertyRow(ANode: TTyPropertyNode); virtual;
    { A property's text, asked before the grid's own conversion: True = handled, AText is it.
      The default asks OnGetPropertyText. With several objects selected, asked for each. }
    function GetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
      var AText: string): Boolean; virtual;
    { Write AText into the property yourself: True = handled, the grid's own conversion is
      skipped. The default asks OnSetPropertyText. An exception goes the way a setter's does. }
    function SetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
      const AText: string): Boolean; virtual;
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
    { Add an item to the collection at APath ('Items', 'Header.Columns'), at the end; or, given
      an item's path ('Items[1]'), right after that item. OnCreateCollectionItem may create it,
      else ACollection.Add does. Returns the new item, nil when OnCollectionChanging refused
      (or at design time). The rows are rebuilt with the new item's row current. }
    function AddCollectionItem(const APath: string): TCollectionItem;
    { Delete the item at APath ('Items[1]'). The current row moves to the next item, else the
      one before, else the collection's row. }
    procedure DeleteCollectionItem(const APath: string);
    { Move the item at APath by ADelta places (-1 up, 1 down), stopping at either end. }
    procedure MoveCollectionItem(const APath: string; ADelta: Integer);
    { The row the selection is on, nil when none. }
    function SelectedRow: TTyValueRow;
    { The dotted path of one of the grid's rows, as ExpandedProperties and the collection
      methods spell it ('Font.Size', 'Items[1].Caption'); '' for a row the grid did not build. }
    function RowPath(ARow: TTyValueRow): string;
    { The property ARow edits: the object that has it and its name (for a set's element, the
      set). False for a collection item's row and for a row the grid did not build. }
    function PropertyAt(ARow: TTyValueRow; out AInstance: TPersistent;
      out APropName: string): Boolean;
    { Inspect several objects at once. The rows are the properties all of them have (the same
      name and the same type; a sub-object only expands when it is of one class in all of
      them). A value they do not agree on shows an empty cell; whatever is entered is written
      into every one of them -- OnPropertyChanging is asked for each first (one refusal and none
      is written), OnPropertyChanged follows for each. A setter that raises stops the write at
      that object: those before it keep the new value, the rows show what the objects hold, and
      OnPropertyError names the object that failed. A collection is shown as '(…)', read-only and
      unexpanded. nil entries and repeats are dropped; an empty array clears the selection. A
      component is dropped from the selection when it is freed. }
    procedure SelectObjects(const AObjects: array of TPersistent);
    function SelectedCount: Integer;
    property SelectedObjects[AIndex: Integer]: TPersistent read GetSelectedObjects;
    { The object inspected: any TPersistent (with several selected, the first). Setting it
      selects that object alone. A component is let go of when it is freed (a free
      notification); anything else must be cleared here before it is freed. }
    property SelectedObject: TPersistent read GetSelectedObject write SetSelectedObject;
    { The same object when it is a component and the only one selected, nil otherwise; setting
      it sets SelectedObject. The published face of the selection: a component picked in the
      Object Inspector. At design time its rows are listed but cannot be edited. }
    property SelectedComponent: TComponent read GetSelectedComponent write SetSelectedComponent;
    property PropertyRows: TTyPropertyRows read FRows;
    property KeyOptions: TTyKeyOptions read GetFixedKeyOptions;
    property PropertyOrder: TTyPropertyOrder read GetPropertyOrder write SetPropertyOrder
      default poAlphabetical;
    property TypeFilter: TTypeKinds read GetTypeFilter write SetTypeFilter
      default TyPropertyGridDefaultTypeFilter;
    { Property names ('Tag') or dotted paths ('Font.Height') never listed. }
    property HiddenProperties: TStrings read GetHiddenProperties write SetHiddenProperties;
    { The dotted paths of the expanded rows ('Font', 'Font.Style', 'Columns[0]'), and '@' with
      the name for an open category heading ('@Layout'). Kept when the selection moves to
      another object, so a row expanded on one button is expanded on the next; adding a path
      expands that row. A category heading the grid shows for the first time is open (its path
      is added); take it off the list to close it. }
    property ExpandedProperties: TStrings read GetExpandedProperties write SetExpandedProperties;
    { Group the top-level properties by category, each group under a heading row that is not
      edited and opens and closes (Enter, or its triangle). Built-in categories by name: Layout
      (Left, Top, Width, Height, Align, Anchors, AutoSize, BorderSpacing, Constraints,
      ChildSizing), Appearance (Color, Font, Caption, Text, Visible, StyleClass, StyleOverride,
      Images, ImageIndex, Cursor, ParentColor, ParentFont), Behavior (Enabled, ReadOnly, TabStop,
      TabOrder, Hint, ShowHint, PopupMenu, Action), Events (every event), Other (the rest);
      OnGetPropertyCategory changes any. A sub-property stays with its parent. Off by default. }
    property ShowCategories: Boolean read GetShowCategories write SetShowCategories default False;
    property OnGetPropertyCategory: TTyGetPropertyCategoryEvent read GetOnGetPropertyCategory
      write SetOnGetPropertyCategory;
    { Only the properties whose name holds this text, ignoring case (a sub-property or a set's
      element too: the rows above it are shown and opened for it, and a matching row keeps the
      rows below it). OnFilterProperty is asked first; this filters what it lets through. Clear
      it and the rows are opened and closed as they were before it was set. '' by default. }
    property FilterText: string read GetFilterText write SetFilterText;
    property OnFilterProperty: TTyFilterPropertyEvent read GetOnFilterProperty
      write SetOnFilterProperty;
    property OnGetComponentNames: TTyGetComponentNamesEvent read GetOnGetComponentNames
      write SetOnGetComponentNames;
    property OnGetPropertyRow: TTyGetPropertyRowEvent read GetOnGetPropertyRow
      write SetOnGetPropertyRow;
    { A property's text both ways, instead of the grid's own conversion -- and the way to show
      a kind the grid does not show itself (see TTyFilterPropertyEvent). Together with
      OnGetPropertyRow (the editor) and OnEditProperty (a dialog) an application can support any
      type. Assigning them does not rebuild the rows; call Rebuild. }
    property OnGetPropertyText: TTyGetPropertyTextEvent read GetOnGetPropertyText
      write SetOnGetPropertyText;
    property OnSetPropertyText: TTySetPropertyTextEvent read GetOnSetPropertyText
      write SetOnSetPropertyText;
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
    property OnCollectionChanging: TTyCollectionChangingEvent read FOnCollectionChanging
      write FOnCollectionChanging;
    property OnCollectionChanged: TTyCollectionChangedEvent read FOnCollectionChanged
      write FOnCollectionChanged;
    property OnCreateCollectionItem: TTyCreateCollectionItemEvent read FOnCreateCollectionItem
      write FOnCreateCollectionItem;
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
    property ShowCategories;
    property OnFilterProperty;
    property OnGetPropertyCategory;
    property OnGetComponentNames;
    property OnGetPropertyRow;
    property OnGetPropertyText;
    property OnSetPropertyText;
    property OnPropertyChanging;
    property OnPropertyChanged;
    property OnPropertyError;
    property OnEditProperty;
    property OnCollectionChanging;
    property OnCollectionChanged;
    property OnCreateCollectionItem;
  end;

{ True when ATypeInfo is TColor (graphics.pp declares TColor = TGraphicsColor, so the RTTI name
  is 'TGraphicsColor' on FPC 3.2.2 and 'TColor' once graphtype switches to System.UITypes). }
function TyIsColorType(ATypeInfo: PTypeInfo): Boolean;

{ The built-in category of a property (see TTyCustomPropertyGrid.ShowCategories): an event is
  Events, the names of the table go under Layout, Appearance or Behavior, the rest under Other.
  The names are the resourcestrings rsTyPropGridCat*, translated. }
function TyPropertyGridCategoryOf(const APropName: string; AKind: TTypeKind): string;

implementation

uses
  tyControls.StyleModel, tyControls.StrConsts, tyControls.Dialogs;

function TyIsColorType(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := (ATypeInfo = TypeInfo(TColor))
    or SameText(ATypeInfo^.Name, 'TColor') or SameText(ATypeInfo^.Name, 'TGraphicsColor');
end;

const
  CCatLayout: array[0..9] of string = ('Left', 'Top', 'Width', 'Height', 'Align', 'Anchors',
    'AutoSize', 'BorderSpacing', 'Constraints', 'ChildSizing');
  CCatAppearance: array[0..11] of string = ('Color', 'Font', 'Caption', 'Text', 'Visible',
    'StyleClass', 'StyleOverride', 'Images', 'ImageIndex', 'Cursor', 'ParentColor', 'ParentFont');
  CCatBehavior: array[0..7] of string = ('Enabled', 'ReadOnly', 'TabStop', 'TabOrder', 'Hint',
    'ShowHint', 'PopupMenu', 'Action');

function NameIn(const AName: string; const ANames: array of string): Boolean;
var i: Integer;
begin
  for i := 0 to High(ANames) do
    if SameText(ANames[i], AName) then Exit(True);
  Result := False;
end;

function TyPropertyGridCategoryOf(const APropName: string; AKind: TTypeKind): string;
begin
  if AKind = tkMethod then Result := rsTyPropGridCatEvents
  else if NameIn(APropName, CCatLayout) then Result := rsTyPropGridCatLayout
  else if NameIn(APropName, CCatAppearance) then Result := rsTyPropGridCatAppearance
  else if NameIn(APropName, CCatBehavior) then Result := rsTyPropGridCatBehavior
  else Result := rsTyPropGridCatOther;
end;

{ Where a category's heading goes: the built-in ones in their order, the application's own after
  them (sorted by name among themselves), Other last. }
function CategoryRank(const ACategory: string): Integer;
begin
  if ACategory = rsTyPropGridCatLayout then Result := 0
  else if ACategory = rsTyPropGridCatAppearance then Result := 1
  else if ACategory = rsTyPropGridCatBehavior then Result := 2
  else if ACategory = rsTyPropGridCatEvents then Result := 3
  else if ACategory = rsTyPropGridCatOther then Result := 5
  else Result := 4;
end;

function CompareCategories(List: TStringList; A, B: Integer): Integer;
begin
  Result := CategoryRank(List[A]) - CategoryRank(List[B]);
  if Result = 0 then Result := CompareText(List[A], List[B]);
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

{ A font into AHolder's font property: through its setter when it has one (a TFont setter
  assigns: LCL's convention), else by Assign into the font it holds. }
procedure StoreFontOn(AHolder: TObject; APropInfo: PPropInfo; AFont: TFont; const AName: string);
var cur: TObject;
begin
  if (AHolder = nil) or (APropInfo = nil) then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [FontText(AFont), AName]);
  if APropInfo^.SetProc <> nil then
    SetObjectProp(AHolder, APropInfo, AFont)
  else
  begin
    cur := GetObjectProp(AHolder, APropInfo);
    if not (cur is TFont) then
      raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [FontText(AFont), AName]);
    TFont(cur).Assign(AFont);
  end;
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
    pnkCategory: Result := '@' + FCategory;
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
  if FKind in [pnkCollectionItem, pnkCategory] then Exit(nil);
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
  SetLength(FRoots, 0);
end;

function TTyPropertyRows.RootCount: Integer;
begin
  Result := Length(FRoots);
end;

function TTyPropertyRows.GetRoot: TPersistent;
begin
  if Length(FRoots) > 0 then Result := FRoots[0] else Result := nil;
end;

function TTyPropertyRows.GetRoots(AIndex: Integer): TPersistent;
begin
  if (AIndex < 0) or (AIndex >= Length(FRoots)) then
    raise EListError.CreateFmt('Root index %d out of bounds', [AIndex]);
  Result := FRoots[AIndex];
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

{ The object a node's property sits on in the ARoot-th object: that root, or what the parent
  node's property holds there. }
function TTyPropertyRows.HolderIn(ANode: TTyPropertyNode; ARoot: Integer): TObject;
begin
  Result := nil;
  if (ARoot < 0) or (ARoot >= Length(FRoots)) then Exit;
  if ANode.FParent = nil then Exit(FRoots[ARoot]);
  case ANode.FParent.FKind of
    pnkSet: Result := HolderIn(ANode.FParent, ARoot);
    pnkObject, pnkFont, pnkCollectionItem: Result := ValueObjectIn(ANode.FParent, ARoot);
  end;
end;

{ The node's PPropInfo is the first object's. Another object may be of another class, where the
  property of the same name has its own getter and setter: look it up there, and accept it only
  when it is of the same type (Build listed only such properties; a setter that has since
  swapped a sub-object for another class breaks the chain). }
function TTyPropertyRows.PropInfoIn(ANode: TTyPropertyNode; AHolder: TObject;
  ARoot: Integer): PPropInfo;
begin
  Result := nil;
  if (AHolder = nil) or (ANode.FPropInfo = nil) then Exit;
  if ARoot = 0 then Exit(ANode.FPropInfo);
  Result := GetPropInfo(AHolder, ANode.FPropInfo^.Name);
  if (Result <> nil) and (Result^.PropType <> ANode.FPropInfo^.PropType) then Result := nil;
end;

{ What an object-valued node holds in the ARoot-th object: the sub-object, or for a collection
  item the item. }
function TTyPropertyRows.ValueObjectIn(ANode: TTyPropertyNode; ARoot: Integer): TObject;
var h, coll: TObject; pi: PPropInfo;
begin
  Result := nil;
  if ANode.FKind = pnkCollectionItem then
  begin
    coll := ValueObjectIn(ANode.FParent, ARoot);
    if (coll is TCollection) and (ANode.FIndex < TCollection(coll).Count) then
      Result := TCollection(coll).Items[ANode.FIndex];
    Exit;
  end;
  h := HolderIn(ANode, ARoot);
  pi := PropInfoIn(ANode, h, ARoot);
  if (pi <> nil) and (pi^.PropType^.Kind = tkClass) then
    Result := GetObjectProp(h, pi);
end;

function TTyPropertyRows.HolderOf(ANode: TTyPropertyNode): TObject;
begin
  Result := HolderIn(ANode, 0);
end;

function TTyPropertyRows.ValueObject(ANode: TTyPropertyNode): TObject;
begin
  Result := ValueObjectIn(ANode, 0);
end;

function TTyPropertyRows.ObjectOf(ANode: TTyPropertyNode): TObject;
begin
  Result := ValueObject(ANode);
end;

{ Can the grid show this property by itself? A set wider than 32 elements does not fit the Int64
  TypInfo hands sets through (it would be truncated, silently), and a class property only means
  something to the grid when it is a TPersistent. The rest (interfaces, variants, records...)
  only through OnGetPropertyText. }
function GridShows(APropInfo: PPropInfo): Boolean;
const
  Showable = [tkInteger, tkChar, tkEnumeration, tkFloat, tkSet, tkMethod, tkSString, tkLString,
    tkAString, tkWString, tkClass, tkWChar, tkBool, tkInt64, tkQWord, tkUString];
begin
  Result := False;
  if not (APropInfo^.PropType^.Kind in Showable) then Exit;
  if (APropInfo^.PropType^.Kind = tkSet)
    and (GetTypeData(APropInfo^.PropType)^.SetSize > SizeOf(Longint)) then Exit;
  if (APropInfo^.PropType^.Kind = tkClass)
    and not GetTypeData(APropInfo^.PropType)^.ClassType.InheritsFrom(TPersistent) then Exit;
  Result := True;
end;

{ How a property is shown. A class property is told apart by its DECLARED class, except that a
  component which is a csSubComponent of its holder (a TTyButton's sub-parts, say) is a part of
  the object -- expanded like any sub-object -- and not a reference to pick from a list. }
function TTyPropertyRows.KindOf(APropInfo: PPropInfo; AInstance: TObject): TTyPropertyNodeKind;
var cls: TClass; obj: TObject;
begin
  if not GridShows(APropInfo) then Exit(pnkCustom);
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
function TTyPropertyRows.CustomText(AInstance: TObject; APropInfo: PPropInfo;
  out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  if not (AInstance is TPersistent) then Exit;
  Result := GetPropText(TPersistent(AInstance), APropInfo, AText);
  if not Result then AText := '';
end;

function TTyPropertyRows.CallGetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
  var AText: string): Boolean;
begin
  Result := False;
  if Assigned(FOnGetPropertyText) then
    FOnGetPropertyText(FSender, AInstance, APropInfo, AText, Result);
end;

function TTyPropertyRows.CallSetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
  const AText: string): Boolean;
begin
  Result := False;
  if Assigned(FOnSetPropertyText) then
    FOnSetPropertyText(FSender, AInstance, APropInfo, AText, Result);
end;

function TTyPropertyRows.GetPropText(AInstance: TPersistent; APropInfo: PPropInfo;
  var AText: string): Boolean;
begin
  Result := CallGetPropertyText(AInstance, APropInfo, AText);
end;

function TTyPropertyRows.SetPropText(AInstance: TPersistent; APropInfo: PPropInfo;
  const AText: string): Boolean;
begin
  Result := CallSetPropertyText(AInstance, APropInfo, AText);
end;

procedure TTyPropertyRows.BuildRow(AEditor: TTyCustomValueListEditor; ANode: TTyPropertyNode);
begin
  FillRow(ANode);
  AddChildren(AEditor, ANode);
end;

function TTyPropertyRows.CategoryOf(AInstance: TObject; APropInfo: PPropInfo): string;
begin
  Result := TyPropertyGridCategoryOf(APropInfo^.Name, APropInfo^.PropType^.Kind);
  if Assigned(FOnGetPropertyCategory) and (AInstance is TPersistent) then
    FOnGetPropertyCategory(FSender, TPersistent(AInstance), APropInfo^.Name, Result);
  if Trim(Result) = '' then Result := rsTyPropGridCatOther;
end;

{ Is this property shown? Readable, of a kind the filter lets through, not hidden by name or
  path, and then OnFilterProperty's say -- asked about every such property, the ones the grid
  cannot show by itself too (AShow False on the way in): those are listed when the handler
  turns AShow on and OnGetPropertyText gives them a text. }
function TTyPropertyRows.Accept(AInstance: TObject; APropInfo: PPropInfo;
  AParent: TTyPropertyNode): Boolean;
var
  path, t: string;
  shows: Boolean;
begin
  Result := False;
  if APropInfo^.GetProc = nil then Exit;
  if not (APropInfo^.PropType^.Kind in FTypeFilter) then Exit;
  if AParent <> nil then path := AParent.Path + '.' + APropInfo^.Name else path := APropInfo^.Name;
  if (FHiddenProperties.IndexOf(APropInfo^.Name) >= 0)
    or (FHiddenProperties.IndexOf(path) >= 0) then Exit;
  shows := GridShows(APropInfo);
  Result := shows;
  if Assigned(FOnFilterProperty) and (AInstance is TPersistent) then
    FOnFilterProperty(FSender, TPersistent(AInstance), APropInfo^.Name, Result);
  if Result and not shows then Result := CustomText(AInstance, APropInfo, t);
end;

function TTyPropertyRows.SharedByAll(const AInstances: array of TObject; APropInfo: PPropInfo;
  AParent: TTyPropertyNode): Boolean;
var k: Integer; other: PPropInfo;
begin
  Result := False;
  for k := 1 to High(AInstances) do
  begin
    if AInstances[k] = nil then Exit;
    other := GetPropInfo(AInstances[k], APropInfo^.Name);
    if (other = nil) or (other^.PropType <> APropInfo^.PropType) then Exit;
    if not Accept(AInstances[k], other, AParent) then Exit;
  end;
  Result := True;
end;

function ComparePropNames(A, B: Pointer): Integer;
begin
  Result := CompareText(PPropInfo(A)^.Name, PPropInfo(B)^.Name);
end;

procedure TTyPropertyRows.AddPropertyRow(AEditor: TTyCustomValueListEditor; AParentRow: TTyValueRow;
  AParentNode: TTyPropertyNode; APropInfo: PPropInfo; const AInstances: array of TObject;
  ADepth: Integer);
var
  k: Integer;
  other: PPropInfo;
  nd: TTyPropertyNode;
  row: TTyValueRow;
  first: TObject;
begin
  first := AInstances[0];
  nd := NewNode(AParentNode, APropInfo, KindOf(APropInfo, first), 0);
  nd.FDepth := ADepth;
  nd.FNoSetter := APropInfo^.SetProc = nil;
  for k := 1 to High(AInstances) do
  begin
    other := GetPropInfo(AInstances[k], APropInfo^.Name);
    if (other = nil) or (other^.SetProc = nil) then nd.FNoSetter := True;
  end;
  if AParentRow = nil then row := AEditor.AddRow(APropInfo^.Name, '')
  else row := AParentRow.AddChild(APropInfo^.Name, '');
  nd.FRow := row;
  row.Data := nd;
  BuildRow(AEditor, nd);
  if Assigned(FOnGetPropertyRow) and (first is TPersistent) then
    FOnGetPropertyRow(FSender, TPersistent(first), APropInfo, row);
end;

procedure TTyPropertyRows.AddCategories(AEditor: TTyCustomValueListEditor; APropInfos: TFPList;
  const AInstances: array of TObject);
var
  cats: TStringList;
  names: array of string;
  i, c: Integer;
  head: TTyPropertyNode;
  row: TTyValueRow;
begin
  cats := TStringList.Create;   // case-insensitive: 'layout' from a handler joins Layout
  try
    SetLength(names, APropInfos.Count);
    for i := 0 to APropInfos.Count - 1 do
    begin
      names[i] := CategoryOf(AInstances[0], PPropInfo(APropInfos[i]));
      if cats.IndexOf(names[i]) < 0 then cats.Add(names[i]);
    end;
    cats.CustomSort(@CompareCategories);
    for c := 0 to cats.Count - 1 do
    begin
      head := NewNode(nil, nil, pnkCategory, 0);
      head.FCategory := cats[c];
      row := AEditor.AddRow(cats[c], '');
      row.Heading := True;
      row.Data := head;
      head.FRow := row;
      for i := 0 to APropInfos.Count - 1 do
        if SameText(names[i], cats[c]) then
          AddPropertyRow(AEditor, row, nil, PPropInfo(APropInfos[i]), AInstances, 0);
    end;
  finally
    cats.Free;
  end;
end;

procedure TTyPropertyRows.ApplyFilter(AEditor: TTyCustomValueListEditor);
var
  f: string;
  i: Integer;

  { True when R or a row below it matches. }
  function Mark(R: TTyValueRow; AUnderMatch: Boolean): Boolean;
  var nd: TTyPropertyNode; own, below: Boolean; j: Integer;
  begin
    nd := NodeOf(R);
    own := (nd <> nil) and (nd.FKind <> pnkCategory) and (Pos(f, LowerCase(nd.Name)) > 0);
    below := False;
    for j := 0 to R.ChildCount - 1 do
      if Mark(R.Child[j], AUnderMatch or own) then below := True;
    if nd <> nil then nd.FFilterOpen := below;
    R.Hidden := not (own or below or AUnderMatch);
    Result := own or below;
  end;

begin
  f := LowerCase(Trim(FFilterText));
  if f = '' then Exit;   // the rows are new: nothing hidden, nothing opened
  for i := 0 to AEditor.RowCount - 1 do Mark(AEditor.Row(i), False);
end;

procedure TTyPropertyRows.AddProperties(AEditor: TTyCustomValueListEditor; AParentRow: TTyValueRow;
  AParentNode: TTyPropertyNode; const AInstances: array of TObject; ADepth: Integer);
var
  pl: PPropList;
  n, i: Integer;
  list: TFPList;
  first: TObject;
begin
  if Length(AInstances) = 0 then Exit;
  first := AInstances[0];
  if first = nil then Exit;
  list := TFPList.Create;
  try
    n := GetPropList(first.ClassInfo, pl);   // NameIndex order: the declaration order
    try
      for i := 0 to n - 1 do
        if Accept(first, pl^[i], AParentNode) and SharedByAll(AInstances, pl^[i], AParentNode) then
          list.Add(pl^[i]);
    finally
      FreeMem(pl);
    end;
    { GetPropList can sort too, but case-sensitively; the inspector order is CompareText. }
    if FOrder = poAlphabetical then list.Sort(@ComparePropNames);
    { Categories group the object's own properties only: a sub-property goes with its parent. }
    if (AParentNode = nil) and FShowCategories then
      AddCategories(AEditor, list, AInstances)
    else
      for i := 0 to list.Count - 1 do
        AddPropertyRow(AEditor, AParentRow, AParentNode, PPropInfo(list[i]), AInstances, ADepth);
  finally
    list.Free;
  end;
end;

procedure TTyPropertyRows.SubObjectClass(ANode: TTyPropertyNode; out AClass: TClass;
  out AMixed: Boolean);
var k: Integer; obj: TObject; cls: TClass;
begin
  AClass := nil;
  AMixed := False;
  for k := 0 to High(FRoots) do
  begin
    try
      obj := ValueObjectIn(ANode, k);
    except
      obj := nil;   // a getter that raises shows its error on the row; nothing to expand
    end;
    if obj <> nil then cls := obj.ClassType else cls := nil;
    if k = 0 then AClass := cls
    else if cls <> AClass then
    begin
      AClass := nil;
      AMixed := True;
      Exit;
    end;
  end;
end;

{ The rows below a node: a set's elements; a sub-object's, a font's or a collection item's own
  properties; a collection's items. Collapsed, as the Object Inspector shows them. Objects go
  MaxDepth levels deep and no further -- the guard against a cycle (A.Other = B, B.Other = A)
  and against a getter that makes a new object every time it is asked. }
procedure TTyPropertyRows.AddChildren(AEditor: TTyCustomValueListEditor; ANode: TTyPropertyNode);
var
  comp: PTypeInfo;
  lo, hi, i, k: Integer;
  el, item: TTyPropertyNode;
  obj: TObject;
  objs: array of TObject;
  cls: TClass;
  mixed: Boolean;
  coll: TCollection;
  r: TTyValueRow;
begin
  ANode.FChildrenBuilt := True;
  case ANode.FKind of
    pnkSet:
      begin
        SetRange(ANode.FPropInfo^.PropType, comp, lo, hi);
        for i := lo to hi do
        begin
          el := NewNode(ANode, ANode.FPropInfo, pnkSetElement, i);
          el.FNoSetter := ANode.FNoSetter;
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
        SubObjectClass(ANode, cls, mixed);
        ANode.FBuiltClass := cls;
        ANode.FMixed := mixed;
        if mixed then
        begin
          { Not one class in every selected object: nothing is common below it, and a font
            written whole into all of them would overwrite what they do not share. }
          ANode.FRow.ReadOnly := True;
          Exit;
        end;
        if cls = nil then Exit;
        SetLength(objs, Length(FRoots));
        for k := 0 to High(FRoots) do objs[k] := ValueObjectIn(ANode, k);
        AddProperties(AEditor, ANode.FRow, ANode, objs, ANode.FDepth + 1);
        ANode.FRow.Expanded := False;
      end;
    pnkCollection:
      begin
        if ANode.FDepth >= FMaxDepth then Exit;
        { Several objects: their items cannot be matched up one to one. }
        if Length(FRoots) > 1 then Exit;
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
            AddProperties(AEditor, r, item, [coll.Items[i]], item.FDepth + 1);
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
    pnkCustom:
      row.EditorKind := vekText;   // OnGetPropertyRow can make it anything else
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
    { Written only by the application, through OnSetPropertyText. }
    pnkCustom:
      row.ReadOnly := not Assigned(FOnSetPropertyText);
  else
    row.ReadOnly := ANode.FNoSetter;
  end;
  row.Value := ReadText(ANode);
end;

function TTyPropertyRows.ReadTextIn(ANode: TTyPropertyNode; ARoot: Integer): string;
var h, obj: TObject; pi: PPropInfo; t: string;
begin
  Result := '';
  if ANode = nil then Exit;
  try
    if ANode.FKind = pnkCollectionItem then
    begin
      obj := ValueObjectIn(ANode, ARoot);
      if obj is TCollectionItem then Result := TCollectionItem(obj).DisplayName;
      Exit;
    end;
    h := HolderIn(ANode, ARoot);
    pi := PropInfoIn(ANode, h, ARoot);
    if pi = nil then Exit;
    { The application's text first, for any property (a set's element is part of its set). }
    if (ANode.FKind <> pnkSetElement) and CustomText(h, pi, t) then Exit(t);
    case ANode.FKind of
      pnkValue:  Result := SimpleText(h, pi);
      pnkMethod: Result := MethodText(h, pi);
      pnkSet:    Result := SetText(pi^.PropType, GetOrdProp(h, pi));
      pnkSetElement:
        Result := BoolText((GetOrdProp(h, pi) and (Int64(1) shl ANode.FIndex)) <> 0);
      pnkComponent:
        Result := ComponentText(GetObjectProp(h, pi));
      pnkFont:
        begin
          obj := GetObjectProp(h, pi);
          if obj is TFont then Result := FontText(TFont(obj));
        end;
      pnkCollection:
        begin
          obj := GetObjectProp(h, pi);
          if obj is TCollection then Result := Format(rsTyPropGridItems, [TCollection(obj).Count]);
        end;
      pnkObject, pnkStrings:
        begin
          obj := GetObjectProp(h, pi);
          if obj <> nil then Result := '(' + obj.ClassName + ')';
        end;
    end;
  except
    on E: Exception do Result := '(' + E.Message + ')';   // a getter that raises is shown, not fatal
  end;
end;

function TTyPropertyRows.ReadText(ANode: TTyPropertyNode): string;
var k: Integer;
begin
  if Length(FRoots) <= 1 then Exit(ReadTextIn(ANode, 0));
  Result := '';
  if ANode = nil then Exit;
  { Several collections: neither a count nor items stand for all of them. }
  if ANode.FKind = pnkCollection then Exit(TyPropertyGridSeveral);
  Result := ReadTextIn(ANode, 0);
  for k := 1 to High(FRoots) do
    if ReadTextIn(ANode, k) <> Result then Exit('');   // they disagree: an empty cell
end;

procedure TTyPropertyRows.WriteOn(ANode: TTyPropertyNode; AHolder: TObject; APropInfo: PPropInfo;
  const AText: string);
var
  cur, bit: Int64;
  t, nm: string;
  sz: Integer;
  comp: TComponent;
  fnt: TFont;
begin
  if AHolder = nil then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
  if APropInfo = nil then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
  { The application's conversion first (a set's element is written as part of its set). }
  if (ANode.FKind <> pnkSetElement) and (AHolder is TPersistent)
    and SetPropText(TPersistent(AHolder), APropInfo, AText) then Exit;
  if ANode.FKind = pnkFont then
  begin
    { Typed (or SetRowValue'd) 'Name, Size': the font's other attributes stay as they are. }
    fnt := TFont.Create;
    try
      if GetObjectProp(AHolder, APropInfo) is TFont then
      begin
        fnt.PixelsPerInch := TFont(GetObjectProp(AHolder, APropInfo)).PixelsPerInch;
        fnt.Assign(TFont(GetObjectProp(AHolder, APropInfo)));
      end;
      if TyParseFontDescriptor(AText, nm, sz) then
        SetOrdProp(fnt, 'Size', sz);
      if nm <> '' then fnt.Name := nm;
      StoreFontOn(AHolder, APropInfo, fnt, ANode.Name);
    finally
      fnt.Free;
    end;
    Exit;
  end;
  if APropInfo^.SetProc = nil then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
  case ANode.FKind of
    pnkValue: WriteSimple(AHolder, APropInfo, AText);
    pnkSetElement:
      begin
        t := Trim(AText);
        cur := GetOrdProp(AHolder, APropInfo);
        bit := Int64(1) shl ANode.FIndex;
        if SameText(t, 'True') then cur := cur or bit
        else if SameText(t, 'False') then cur := cur and not bit
        else raise InvalidValue(AText, ANode.Name);
        SetOrdProp(AHolder, APropInfo, cur);
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
        SetObjectProp(AHolder, APropInfo, comp);
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

procedure TTyPropertyRows.StoreFont(AFontNode: TTyPropertyNode; ARoot: Integer; AFont: TFont);
var h: TObject;
begin
  h := HolderIn(AFontNode, ARoot);
  StoreFontOn(h, PropInfoIn(AFontNode, h, ARoot), AFont, AFontNode.Name);
end;

procedure TTyPropertyRows.WriteFontIn(ANode: TTyPropertyNode; ARoot: Integer; AFont: TFont);
begin
  StoreFont(ANode, ARoot, AFont);
end;

procedure TTyPropertyRows.WriteFont(ANode: TTyPropertyNode; AFont: TFont);
var k: Integer;
begin
  for k := 0 to High(FRoots) do WriteFontIn(ANode, k, AFont);
end;

procedure TTyPropertyRows.WriteStringsIn(ANode: TTyPropertyNode; ARoot: Integer;
  AStrings: TStrings);
var h, cur: TObject; pi: PPropInfo;
begin
  h := HolderIn(ANode, ARoot);
  pi := PropInfoIn(ANode, h, ARoot);
  if pi = nil then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AStrings.Text, ANode.Name]);
  if pi^.SetProc <> nil then
    SetObjectProp(h, pi, AStrings)
  else
  begin
    cur := GetObjectProp(h, pi);
    if not (cur is TStrings) then
      raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AStrings.Text, ANode.Name]);
    TStrings(cur).Assign(AStrings);
  end;
end;

procedure TTyPropertyRows.WriteStrings(ANode: TTyPropertyNode; AStrings: TStrings);
var k: Integer;
begin
  for k := 0 to High(FRoots) do WriteStringsIn(ANode, k, AStrings);
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
  if Root is TComponent then base := CandidateRoot(TComponent(Root));   // the first object's
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

procedure TTyPropertyRows.WriteTextIn(ANode: TTyPropertyNode; ARoot: Integer; const AText: string);
var fontNode: TTyPropertyNode; cur, h: TObject; tmp: TFont;
begin
  fontNode := FontOwnerOf(ANode);
  if fontNode <> nil then
  begin
    cur := ValueObjectIn(fontNode, ARoot);
    if not (cur is TFont) then
      raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
    tmp := TFont.Create;
    try
      tmp.PixelsPerInch := TFont(cur).PixelsPerInch;   // so Height copies across unscaled
      tmp.Assign(TFont(cur));
      WriteOn(ANode, tmp, ANode.FPropInfo, AText);
      StoreFont(fontNode, ARoot, tmp);
    finally
      tmp.Free;
    end;
  end
  else
  begin
    h := HolderIn(ANode, ARoot);
    WriteOn(ANode, h, PropInfoIn(ANode, h, ARoot), AText);
  end;
end;

procedure TTyPropertyRows.WriteText(ANode: TTyPropertyNode; var AText: string);
var k: Integer;
begin
  for k := 0 to High(FRoots) do WriteTextIn(ANode, k, AText);
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

function TTyPropertyRows.PropertyOfIn(ANode: TTyPropertyNode; ARoot: Integer;
  out AInstance: TPersistent; out APropName: string): Boolean;
var h: TObject;
begin
  AInstance := nil;
  APropName := '';
  Result := False;
  if (ANode = nil) or (ANode.FKind = pnkCollectionItem) or (ANode.FPropInfo = nil) then Exit;
  try
    h := HolderIn(ANode, ARoot);
  except
    h := nil;
  end;
  if not (h is TPersistent) then Exit;
  AInstance := TPersistent(h);
  APropName := ANode.FPropInfo^.Name;
  Result := True;
end;

function TTyPropertyRows.PropertyOf(ANode: TTyPropertyNode; out AInstance: TPersistent;
  out APropName: string): Boolean;
begin
  Result := PropertyOfIn(ANode, 0, AInstance, APropName);
end;

function TTyPropertyRows.ChangeOfIn(ANode: TTyPropertyNode; ARoot: Integer; const AText: string;
  out AInstance: TPersistent; out APropName, ANewValue: string): Boolean;
var cur, bit: Int64; pi: PPropInfo;
begin
  ANewValue := AText;
  Result := PropertyOfIn(ANode, ARoot, AInstance, APropName);
  if not Result or (ANode.FKind <> pnkSetElement) then Exit;
  pi := PropInfoIn(ANode, AInstance, ARoot);
  if pi = nil then Exit;   // the write will fail and say why
  try
    cur := GetOrdProp(AInstance, pi);
  except
    Exit;
  end;
  bit := Int64(1) shl ANode.FIndex;
  if SameText(Trim(AText), 'True') then cur := cur or bit
  else if SameText(Trim(AText), 'False') then cur := cur and not bit;
  ANewValue := SetText(pi^.PropType, cur);
end;

function TTyPropertyRows.ChangeOf(ANode: TTyPropertyNode; const AText: string;
  out AInstance: TPersistent; out APropName, ANewValue: string): Boolean;
begin
  Result := ChangeOfIn(ANode, 0, AText, AInstance, APropName, ANewValue);
end;

function TTyPropertyRows.StructureChanged: Boolean;
var
  i, n: Integer;
  nd: TTyPropertyNode;
  obj: TObject;
  cls: TClass;
  mixed: Boolean;
begin
  Result := False;
  for i := 0 to FNodes.Count - 1 do
  begin
    nd := TTyPropertyNode(FNodes[i]);
    if not (nd.FKind in [pnkObject, pnkFont, pnkCollection]) or not nd.FChildrenBuilt then Continue;
    if nd.FDepth >= FMaxDepth then Continue;   // nothing was built below it, nothing to fit
    if nd.FKind = pnkCollection then
    begin
      if Length(FRoots) > 1 then Continue;      // not expanded with several objects
      try
        obj := ValueObject(nd);
      except
        obj := nil;
      end;
      if obj is TCollection then n := TCollection(obj).Count else n := 0;
      if n <> nd.FBuiltCount then Exit(True);
    end
    else
    begin
      SubObjectClass(nd, cls, mixed);
      if (cls <> nd.FBuiltClass) or (mixed <> nd.FMixed) then Exit(True);
    end;
  end;
end;

procedure TTyPropertyRows.Build(AEditor: TTyCustomValueListEditor; ARoot: TPersistent);
begin
  if ARoot = nil then Build(AEditor, [])
  else Build(AEditor, [ARoot]);
end;

procedure TTyPropertyRows.Build(AEditor: TTyCustomValueListEditor;
  const ARoots: array of TPersistent);
var i, n: Integer; insts: array of TObject;
begin
  AEditor.Clear;
  Clear;
  n := 0;
  SetLength(FRoots, Length(ARoots));
  for i := 0 to High(ARoots) do
    if ARoots[i] <> nil then
    begin
      FRoots[n] := ARoots[i];
      Inc(n);
    end;
  SetLength(FRoots, n);
  if n > 0 then
  begin
    SetLength(insts, n);
    for i := 0 to n - 1 do insts[i] := FRoots[i];
    AddProperties(AEditor, nil, nil, insts, 0);
    ApplyFilter(AEditor);
  end;
  AEditor.UpdateRows;
end;

{ ---- TTyGridPropertyRows: the grid's own mapping ---- }

type
  { The mapping a property grid uses: its three hooks are the grid's virtual methods, so a
    descendant of the grid takes part without knowing the mapping class. }
  TTyGridPropertyRows = class(TTyPropertyRows)
  private
    FGrid: TTyCustomPropertyGrid;
  protected
    procedure BuildRow(AEditor: TTyCustomValueListEditor; ANode: TTyPropertyNode); override;
    function GetPropText(AInstance: TPersistent; APropInfo: PPropInfo;
      var AText: string): Boolean; override;
    function SetPropText(AInstance: TPersistent; APropInfo: PPropInfo;
      const AText: string): Boolean; override;
  end;

procedure TTyGridPropertyRows.BuildRow(AEditor: TTyCustomValueListEditor; ANode: TTyPropertyNode);
begin
  if AEditor = FGrid then FGrid.BuildPropertyRow(ANode)
  else inherited BuildRow(AEditor, ANode);
end;

function TTyGridPropertyRows.GetPropText(AInstance: TPersistent; APropInfo: PPropInfo;
  var AText: string): Boolean;
begin
  Result := FGrid.GetPropertyText(AInstance, APropInfo, AText);
end;

function TTyGridPropertyRows.SetPropText(AInstance: TPersistent; APropInfo: PPropInfo;
  const AText: string): Boolean;
begin
  Result := FGrid.SetPropertyText(AInstance, APropInfo, AText);
end;

{ ---- TTyCustomPropertyGrid ---- }

constructor TTyCustomPropertyGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRows := TTyGridPropertyRows.Create(Self);
  TTyGridPropertyRows(FRows).FGrid := Self;
  FRows.HiddenProperties.OnChange := @HiddenChanged;
  FSeenCategories := TStringList.Create;
  FSeenCategories.CaseSensitive := False;
  FPreFilterExpanded := TStringList.Create;
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
  FreeAndNil(FSeenCategories);
  FreeAndNil(FPreFilterExpanded);
  FreeAndNil(FMenu);   // no owner: the grid frees it (its items with it)
  inherited Destroy;
end;

procedure TTyCustomPropertyGrid.SelectObjects(const AObjects: array of TPersistent);
var
  fresh: array of TPersistent;
  i, j, n: Integer;
  dup, same: Boolean;
begin
  n := 0;
  SetLength(fresh, Length(AObjects));
  for i := 0 to High(AObjects) do
  begin
    if AObjects[i] = nil then Continue;
    dup := False;
    for j := 0 to n - 1 do
      if fresh[j] = AObjects[i] then dup := True;
    if dup then Continue;
    fresh[n] := AObjects[i];
    Inc(n);
  end;
  SetLength(fresh, n);
  same := n = Length(FSelected);
  if same then
    for i := 0 to n - 1 do
      if fresh[i] <> FSelected[i] then same := False;
  if same then Exit;
  { #183: an edit in progress is written to the object it was made on before that object leaves
    the grid, as LCL's object inspector does (SetSelection calls ValueEditExit first). It was
    thrown away: a click on a control that takes no focus never gave the editor its OnExit. }
  if EditingRow >= 0 then EndEdit(True);
  for i := 0 to High(FSelected) do
    if FSelected[i] is TComponent then TComponent(FSelected[i]).RemoveFreeNotification(Self);
  FSelected := fresh;
  for i := 0 to High(FSelected) do
    if FSelected[i] is TComponent then TComponent(FSelected[i]).FreeNotification(Self);
  if csLoading in ComponentState then Exit;   // Loaded builds, once the filters are read too
  RebuildRows(False);
end;

function TTyCustomPropertyGrid.SelectedCount: Integer;
begin
  Result := Length(FSelected);
end;

function TTyCustomPropertyGrid.GetSelectedObjects(AIndex: Integer): TPersistent;
begin
  if (AIndex < 0) or (AIndex >= Length(FSelected)) then
    raise EListError.CreateFmt('Selected object index %d out of bounds (%d selected)',
      [AIndex, Length(FSelected)]);
  Result := FSelected[AIndex];
end;

function TTyCustomPropertyGrid.GetSelectedObject: TPersistent;
begin
  if Length(FSelected) > 0 then Result := FSelected[0] else Result := nil;
end;

procedure TTyCustomPropertyGrid.SetSelectedObject(AValue: TPersistent);
begin
  if AValue = nil then SelectObjects([]) else SelectObjects([AValue]);
end;

function TTyCustomPropertyGrid.GetSelectedComponent: TComponent;
begin
  if (Length(FSelected) = 1) and (FSelected[0] is TComponent) then
    Result := TComponent(FSelected[0])
  else
    Result := nil;
end;

procedure TTyCustomPropertyGrid.SetSelectedComponent(AValue: TComponent);
begin
  SetSelectedObject(AValue);
end;

procedure TTyCustomPropertyGrid.Notification(AComponent: TComponent; Operation: TOperation);
var i, at: Integer;
begin
  inherited Notification(AComponent, Operation);
  if (Operation <> opRemove) or (AComponent = nil) then Exit;
  at := -1;
  for i := 0 to High(FSelected) do
    if TObject(FSelected[i]) = TObject(AComponent) then at := i;
  if at < 0 then Exit;
  { Before anything of it is freed (TComponent.Destroy notifies first): it leaves the selection
    without being read -- rebuilding reads only the paths and the objects still selected. }
  for i := at to High(FSelected) - 1 do FSelected[i] := FSelected[i + 1];
  SetLength(FSelected, Length(FSelected) - 1);
  if not (csDestroying in ComponentState) and (FRows <> nil) then
    RebuildRows(Length(FSelected) > 0);   // the rest stay where they were
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
    { FilterText opens the rows a match is below, whatever the list says. }
    nd.Row.Expanded := (FExpanded.IndexOf(nd.Path) >= 0) or nd.FFilterOpen;
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

function TTyCustomPropertyGrid.GetOnGetPropertyText: TTyGetPropertyTextEvent;
begin
  Result := FRows.OnGetPropertyText;
end;

procedure TTyCustomPropertyGrid.SetOnGetPropertyText(AValue: TTyGetPropertyTextEvent);
begin
  FRows.OnGetPropertyText := AValue;
end;

function TTyCustomPropertyGrid.GetOnSetPropertyText: TTySetPropertyTextEvent;
begin
  Result := FRows.OnSetPropertyText;
end;

procedure TTyCustomPropertyGrid.SetOnSetPropertyText(AValue: TTySetPropertyTextEvent);
begin
  FRows.OnSetPropertyText := AValue;
end;

function TTyCustomPropertyGrid.GetShowCategories: Boolean;
begin
  Result := FRows.ShowCategories;
end;

procedure TTyCustomPropertyGrid.SetShowCategories(AValue: Boolean);
begin
  if FRows.ShowCategories = AValue then Exit;
  FRows.ShowCategories := AValue;
  if not (csLoading in ComponentState) then Rebuild;
end;

function TTyCustomPropertyGrid.GetOnGetPropertyCategory: TTyGetPropertyCategoryEvent;
begin
  Result := FRows.OnGetPropertyCategory;
end;

procedure TTyCustomPropertyGrid.SetOnGetPropertyCategory(AValue: TTyGetPropertyCategoryEvent);
begin
  FRows.OnGetPropertyCategory := AValue;
end;

function TTyCustomPropertyGrid.GetFilterText: string;
begin
  Result := FRows.FilterText;
end;

{ Setting a filter keeps a copy of ExpandedProperties: while it filters, the rows a match is below
  are opened for it (and what the user opens or closes is taken as usual), and clearing it puts
  the copy back, so the rows are as they were before the search. }
procedure TTyCustomPropertyGrid.SetFilterText(const AValue: string);
var
  sel: string;
  wasOn, nowOn: Boolean;
begin
  if FRows.FilterText = AValue then Exit;
  wasOn := Trim(FRows.FilterText) <> '';
  nowOn := Trim(AValue) <> '';
  sel := RowPath(SelectedRow);
  if nowOn and not wasOn then
  begin
    HarvestExpanded;
    FPreFilterExpanded.Assign(FExpanded);
    FFiltering := True;
  end;
  FRows.FilterText := AValue;
  if csLoading in ComponentState then Exit;   // Loaded builds
  if not nowOn and FFiltering then
  begin
    FFiltering := False;
    FHarvesting := True;
    try
      FExpanded.Assign(FPreFilterExpanded);
    finally
      FHarvesting := False;
    end;
    RebuildRows(False, sel, False);
  end
  else if nowOn or wasOn then
    RebuildRows(False, sel);
end;

procedure TTyCustomPropertyGrid.OpenNewCategories;
var
  i: Integer;
  nd: TTyPropertyNode;
  p: string;
begin
  for i := 0 to FRows.NodeCount - 1 do
  begin
    nd := FRows.Node(i);
    if nd.Kind <> pnkCategory then Continue;
    p := nd.Path;
    if FSeenCategories.IndexOf(p) >= 0 then Continue;
    FSeenCategories.Add(p);
    FHarvesting := True;
    try
      FExpanded.Add(p);
      if FFiltering then FPreFilterExpanded.Add(p);   // open after the search too
    finally
      FHarvesting := False;
    end;
  end;
end;

procedure TTyCustomPropertyGrid.BuildPropertyRow(ANode: TTyPropertyNode);
begin
  FRows.FillRow(ANode);
  FRows.AddChildren(Self, ANode);
end;

function TTyCustomPropertyGrid.GetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
  var AText: string): Boolean;
begin
  Result := FRows.CallGetPropertyText(AInstance, APropInfo, AText);
end;

function TTyCustomPropertyGrid.SetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
  const AText: string): Boolean;
begin
  Result := FRows.CallSetPropertyText(AInstance, APropInfo, AText);
end;

procedure TTyCustomPropertyGrid.Rebuild;
begin
  RebuildRows(True);
end;

{ The rows again from SelectedObject. Expansion comes back from ExpandedProperties and the current
  row by its path, so neither is lost to a rebuild nor to a move to another object of a like kind;
  AKeepTop keeps the scroll position too (the same object again), else the list starts at the top. }
procedure TTyCustomPropertyGrid.RebuildRows(AKeepTop: Boolean; const ASelect: string;
  AHarvest: Boolean);
var
  cur: TTyValueRow;
  nd: TTyPropertyNode;
  selPath: string;
  keptTop, at, shown: Integer;
begin
  if FRows = nil then Exit;
  { Not after a collection change: the old rows still carry the old indexes, and the list has
    already been moved along with the items (RemapExpanded). }
  if AHarvest then HarvestExpanded;
  selPath := ASelect;
  if selPath = '' then
  begin
    cur := FlatRowAt(ItemIndex);
    nd := FRows.NodeOf(cur);
    if nd <> nil then selPath := nd.Path;
  end;
  keptTop := TopIndex;
  Inc(FBuildCount);
  FRows.Build(Self, FSelected);
  OpenNewCategories;
  ApplyExpanded;
  nd := FRows.FindByPath(selPath);
  if nd <> nil then at := FlatIndexOf(nd.Row) else at := -1;
  SetItemIndexSilent(at);
  if AKeepTop then TopIndex := keptTop else TopIndex := 0;
  if (ASelect <> '') and (at >= 0) then
  begin
    shown := VisibleRowCount;
    if shown < 1 then shown := 1;
    if at < TopIndex then TopIndex := at
    else if at >= TopIndex + shown then TopIndex := at - shown + 1;
  end;
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

{ The row at a display position: the same pre-order walk over expanded rows the editor lays out
  (a hidden row and everything below it left out). }
function TTyCustomPropertyGrid.FlatRowAt(AFlat: Integer): TTyValueRow;
var n: Integer;

  function Walk(ARow: TTyValueRow): TTyValueRow;
  var i: Integer;
  begin
    if ARow.Hidden then Exit(nil);
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

{ The display position of ARow, -1 when it is hidden or a collapsed (or hidden) ancestor hides it. }
function TTyCustomPropertyGrid.FlatIndexOf(ARow: TTyValueRow): Integer;
var n, res: Integer;

  procedure Walk(R: TTyValueRow);
  var i: Integer;
  begin
    if (res >= 0) or R.Hidden then Exit;
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
  insts: array of TPersistent;
  names, newTexts: array of string;
  known: array of Boolean;
  inst: TPersistent;
  nm, described: string;
  allow: Boolean;
  gen, n, k: Integer;
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
  { One object or several: each is asked about, and written, in turn. }
  n := FRows.RootCount;
  if n < 1 then n := 1;
  SetLength(insts, n);
  SetLength(names, n);
  SetLength(newTexts, n);
  SetLength(known, n);
  for k := 0 to n - 1 do
  begin
    known[k] := FRows.ChangeOfIn(ANode, k, described, insts[k], names[k], newTexts[k]);
    if not known[k] then names[k] := ANode.Name;
  end;
  gen := FBuildCount;
  if Assigned(FOnPropertyChanging) then
    for k := 0 to n - 1 do
    begin
      if not known[k] then Continue;
      allow := True;
      FOnPropertyChanging(Self, insts[k], names[k], newTexts[k], allow);
      { One refusal and none is written. A handler that rebuilt the rows took ANode with them:
        nothing more can be done with it. }
      if not allow or (gen <> FBuildCount) then Exit;
    end;
  for k := 0 to n - 1 do
    try
      case AKind of
        pwkFont:    FRows.WriteFontIn(ANode, k, TFont(AObject));
        pwkStrings: FRows.WriteStringsIn(ANode, k, TStrings(AObject));
      else
        FRows.WriteTextIn(ANode, k, AText);   // raises -> nothing written to this object
      end;
    except
      on E: Exception do
      begin
        { The setter may have moved something before it raised, and the objects before this
          one keep what they took: every row shows the objects. }
        FRows.RefreshValues(nil);
        Invalidate;
        if not Assigned(FOnPropertyError) then raise;
        FOnPropertyError(Self, insts[k], names[k], E);
        Exit;
      end;
    end;
  if AKind <> pwkStrings then AText := FRows.ReadText(ANode);   // as the objects read it back
  { A setter often moves other properties too (AutoSize -> Width): re-read the rest. The row
    being committed is left for the editor, which compares AText with its old value. }
  FRows.RefreshValues(AExceptRow);
  Invalidate;
  if Assigned(FOnPropertyChanged) then
    for k := 0 to n - 1 do
    begin
      if gen <> FBuildCount then Break;   // a handler rebuilt the rows: ANode is gone
      if FRows.PropertyOfIn(ANode, k, inst, nm) then FOnPropertyChanged(Self, inst, nm);
    end;
  Result := gen = FBuildCount;
end;

procedure TTyCustomPropertyGrid.SeedEditFont(ARow: TTyValueRow; AFont: TFont);
var
  nd: TTyPropertyNode;
  inst, cur: TObject;
begin
  { #183: the font the object holds, whole, as LCL's font property editor starts from it
    (graphpropedits.pas, FontDialog.Font := TFont(GetObjectValue)). Seeded from the rows, a
    bold font opened regular and its CharSet, Pitch, Quality and Orientation were dropped. }
  nd := nil;
  if FRows <> nil then nd := FRows.NodeOf(ARow);
  if (nd <> nil) and (nd.Kind = pnkFont) and (nd.PropInfo <> nil) then
  begin
    inst := nd.Instance;
    if inst <> nil then
    begin
      cur := GetObjectProp(inst, nd.PropInfo);
      if cur is TFont then
      begin
        AFont.Assign(TFont(cur));
        Exit;
      end;
    end;
  end;
  inherited SeedEditFont(ARow, AFont);
end;

function TTyCustomPropertyGrid.CanCommitValue(ARow: TTyValueRow; var AText: string): Boolean;
var nd: TTyPropertyNode;
begin
  if FRows = nil then Exit(inherited CanCommitValue(ARow, AText));   // being destroyed
  nd := FRows.NodeOf(ARow);
  if nd = nil then Exit(inherited CanCommitValue(ARow, AText));
  if nd.Kind = pnkCategory then Exit(False);   // a heading has no value to write
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
var nd: TTyPropertyNode; cur: TObject; tmp: TStringList; dummy: string; k: Integer;
begin
  nd := FRows.NodeOf(ARow);
  if (nd = nil) or (nd.Kind <> pnkStrings) or ReadOnly or ARow.ReadOnly then Exit;
  if csDesigning in ComponentState then Exit;
  cur := FRows.ObjectOf(nd);
  tmp := TStringList.Create;
  try
    if cur is TStrings then tmp.Assign(TStrings(cur));
    { Several objects whose lists differ: the dialog starts empty, as their cell is. }
    for k := 1 to FRows.RootCount - 1 do
      if not (FRows.ValueObjectIn(nd, k) is TStrings)
        or (TStrings(FRows.ValueObjectIn(nd, k)).Text <> tmp.Text) then
      begin
        tmp.Clear;
        Break;
      end;
    if ExecuteStringsDialog(Format(rsTyPropGridStringsTitle, [nd.Path]), tmp) then
    begin
      dummy := '';
      WriteProperty(nd, pwkStrings, tmp, nil, dummy);
    end;
  finally
    tmp.Free;
  end;
end;

{ ---- collection items: add, delete, move (plan D2) ---- }

function TTyCustomPropertyGrid.CollectionEditable(ANode: TTyPropertyNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [pnkCollection, pnkCollectionItem])
    and (FRows.RootCount = 1) and not ReadOnly and not (csDesigning in ComponentState);
end;

{ The expanded paths follow their items: an item that moves takes its expansion along, the
  items after an added or a deleted one shift by one, a deleted item's go with it. }
procedure TTyCustomPropertyGrid.RemapExpanded(const ACollPath: string;
  AAction: TTyCollectionAction; AFrom, ATo: Integer);
var
  old: TStringList;
  i, close, n: Integer;
  e, prefix, rest: string;
begin
  prefix := ACollPath + '[';
  old := TStringList.Create;
  FHarvesting := True;   // the list changes, the rows are rebuilt from it afterwards
  FExpanded.BeginUpdate;
  try
    old.Assign(FExpanded);
    FExpanded.Clear;
    for i := 0 to old.Count - 1 do
    begin
      e := old[i];
      if SameText(Copy(e, 1, Length(prefix)), prefix) then
      begin
        close := Pos(']', Copy(e, Length(prefix) + 1, MaxInt));
        if (close > 0)
          and TryStrToInt(Copy(e, Length(prefix) + 1, close - 1), n) then
        begin
          rest := Copy(e, Length(prefix) + close + 1, MaxInt);
          case AAction of
            caAdd:
              if n >= ATo then Inc(n);
            caDelete:
              if n = AFrom then Continue
              else if n > AFrom then Dec(n);
            caMove:
              if n = AFrom then n := ATo
              else if (AFrom < ATo) and (n > AFrom) and (n <= ATo) then Dec(n)
              else if (AFrom > ATo) and (n >= ATo) and (n < AFrom) then Inc(n);
          end;
          e := prefix + IntToStr(n) + ']' + rest;
        end;
      end;
      FExpanded.Add(e);
    end;
  finally
    FExpanded.EndUpdate;
    FHarvesting := False;
    old.Free;
  end;
end;

function TTyCustomPropertyGrid.DoCollectionAction(AAction: TTyCollectionAction;
  const APath: string; ADelta: Integer): TCollectionItem;
var
  nd, collNode, p: TTyPropertyNode;
  r: TTyValueRow;
  obj: TObject;
  coll: TCollection;
  idx, fromIdx, toIdx, gen: Integer;
  allow: Boolean;
  collPath, sel: string;
begin
  Result := nil;
  if (FRows = nil) or (csDesigning in ComponentState) then Exit;
  { An open cell editor first: its text is committed (or, for a delete, dropped) before the
    rows move under it. A commit may rebuild the rows, so the path is resolved after it. }
  if EditingRow >= 0 then EndEdit(AAction <> caDelete);
  nd := FRows.FindByPath(APath);
  if (nd = nil) or not (nd.Kind in [pnkCollection, pnkCollectionItem])
    or (FRows.RootCount <> 1) then
    raise EPropertyError.CreateFmt('"%s" is not a collection or a collection item of the '
      + 'inspected object', [APath]);
  if nd.Kind = pnkCollection then
  begin
    collNode := nd;
    idx := -1;
  end
  else
  begin
    collNode := nd.Parent;
    idx := nd.Index;
  end;
  obj := FRows.ObjectOf(collNode);
  if not (obj is TCollection) then
    raise EPropertyError.CreateFmt('"%s" is not a collection', [collNode.Path]);
  coll := TCollection(obj);
  if (AAction <> caAdd) and ((idx < 0) or (idx >= coll.Count)) then
    raise EPropertyError.CreateFmt('"%s" is not an item of the collection', [APath]);
  case AAction of
    caAdd:
      begin
        if idx < 0 then toIdx := coll.Count else toIdx := idx + 1;
        fromIdx := toIdx;
      end;
    caDelete:
      begin
        fromIdx := idx;
        toIdx := -1;
      end;
  else
    begin
      fromIdx := idx;
      toIdx := idx + ADelta;
      if toIdx < 0 then toIdx := 0;                          // stop at either end
      if toIdx > coll.Count - 1 then toIdx := coll.Count - 1;
      if toIdx = fromIdx then Exit;                           // nowhere to go: nothing happens
    end;
  end;
  if Assigned(FOnCollectionChanging) then
  begin
    allow := True;
    gen := FBuildCount;
    FOnCollectionChanging(Self, coll, AAction, fromIdx, toIdx, allow);
    if not allow or (gen <> FBuildCount) then Exit;
  end;
  collPath := collNode.Path;
  HarvestExpanded;
  try
    case AAction of
      caAdd:
        begin
          Result := nil;
          if Assigned(FOnCreateCollectionItem) then FOnCreateCollectionItem(Self, coll, Result);
          if Result = nil then Result := coll.Add
          else if Result.Collection <> coll then
            raise EPropertyError.Create('OnCreateCollectionItem returned an item of another '
              + 'collection');
          if Result.Index <> toIdx then Result.Index := toIdx;
          toIdx := Result.Index;
          fromIdx := toIdx;
        end;
      caDelete:
        coll.Delete(fromIdx);
      caMove:
        coll.Items[fromIdx].Index := toIdx;
    end;
  except
    RebuildRows(True);   // whatever got done, the rows show it
    raise;
  end;
  RemapExpanded(collPath, AAction, fromIdx, toIdx);
  case AAction of
    caDelete:
      if fromIdx < coll.Count then sel := collPath + '[' + IntToStr(fromIdx) + ']'
      else if coll.Count > 0 then sel := collPath + '[' + IntToStr(coll.Count - 1) + ']'
      else sel := collPath;
  else
    sel := collPath + '[' + IntToStr(toIdx) + ']';
  end;
  { The row made current has to be seen: the collection's row and every row above it open (a
    category heading too -- it is above the row, not in its path). }
  if sel <> collPath then
  begin
    FHarvesting := True;
    try
      r := collNode.Row;
      while r <> nil do
      begin
        p := FRows.NodeOf(r);
        if p <> nil then FExpanded.Add(p.Path);
        r := r.Parent;
      end;
    finally
      FHarvesting := False;
    end;
  end;
  RebuildRows(True, sel, False);
  if Assigned(FOnCollectionChanged) then
    FOnCollectionChanged(Self, coll, AAction, fromIdx, toIdx);
end;

function TTyCustomPropertyGrid.AddCollectionItem(const APath: string): TCollectionItem;
begin
  Result := DoCollectionAction(caAdd, APath, 0);
end;

procedure TTyCustomPropertyGrid.DeleteCollectionItem(const APath: string);
begin
  DoCollectionAction(caDelete, APath, 0);
end;

procedure TTyCustomPropertyGrid.MoveCollectionItem(const APath: string; ADelta: Integer);
begin
  DoCollectionAction(caMove, APath, ADelta);
end;

function TTyCustomPropertyGrid.SelectedRow: TTyValueRow;
begin
  Result := FlatRowAt(ItemIndex);
end;

function TTyCustomPropertyGrid.RowPath(ARow: TTyValueRow): string;
var nd: TTyPropertyNode;
begin
  Result := '';
  if FRows = nil then Exit;
  nd := FRows.NodeOf(ARow);
  if nd <> nil then Result := nd.Path;
end;

procedure TTyCustomPropertyGrid.BuildCollectionMenu;

  function AddItem(const ACaption: string; AKey: Word; AShift: TShiftState;
    AOnClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FMenu);
    Result.Caption := ACaption;
    Result.ShortCut := ShortCut(AKey, AShift);   // shown beside the item: the same keys work
    Result.OnClick := AOnClick;
    FMenu.Items.Add(Result);
  end;

var sep: TMenuItem;
begin
  if FMenu <> nil then Exit;
  FMenu := TTyPopupMenu.Create(nil);
  FMenuAdd := AddItem(rsTyPropGridAddItem, VK_INSERT, [], @MenuAddClick);
  FMenuDelete := AddItem(rsTyPropGridDeleteItem, VK_DELETE, [ssModifier], @MenuDeleteClick);
  sep := TMenuItem.Create(FMenu);
  sep.Caption := '-';
  FMenu.Items.Add(sep);
  FMenuUp := AddItem(rsTyPropGridMoveUp, VK_UP, [ssModifier], @MenuUpClick);
  FMenuDown := AddItem(rsTyPropGridMoveDown, VK_DOWN, [ssModifier], @MenuDownClick);
end;

procedure TTyCustomPropertyGrid.MenuAddClick(Sender: TObject);
begin
  AddCollectionItem(FMenuPath);
end;

procedure TTyCustomPropertyGrid.MenuDeleteClick(Sender: TObject);
begin
  DeleteCollectionItem(FMenuPath);
end;

procedure TTyCustomPropertyGrid.MenuUpClick(Sender: TObject);
begin
  MoveCollectionItem(FMenuPath, -1);
end;

procedure TTyCustomPropertyGrid.MenuDownClick(Sender: TObject);
begin
  MoveCollectionItem(FMenuPath, 1);
end;

procedure TTyCustomPropertyGrid.ShowCollectionMenu(AMenu: TPopupMenu; X, Y: Integer);
begin
  AMenu.PopUp(X, Y);
end;

procedure TTyCustomPropertyGrid.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
var
  flat, itemCount: Integer;
  r: TTyValueRow;
  nd: TTyPropertyNode;
  coll: TObject;
  isItem: Boolean;
  at: TPoint;
begin
  inherited DoContextPopup(MousePos, Handled);   // OnContextPopup first; it may take it
  if Handled or (PopupMenu <> nil) or (FRows = nil) then Exit;
  if (MousePos.X = -1) and (MousePos.Y = -1) then
    flat := ItemIndex   // the menu key: the current row
  else
  begin
    flat := RowAtY(MousePos.Y);
    if (flat < 0) or (flat >= DisplayRowCount) then Exit;
    if flat <> ItemIndex then ItemIndex := flat;   // the row clicked becomes the current one
  end;
  r := FlatRowAt(flat);
  nd := FRows.NodeOf(r);
  if not CollectionEditable(nd) then Exit;
  isItem := nd.Kind = pnkCollectionItem;
  if isItem then coll := FRows.ObjectOf(nd.Parent) else coll := FRows.ObjectOf(nd);
  if not (coll is TCollection) then Exit;
  itemCount := TCollection(coll).Count;
  BuildCollectionMenu;
  FMenuPath := nd.Path;
  FMenuDelete.Enabled := isItem;
  FMenuUp.Enabled := isItem and (nd.Index > 0);
  FMenuDown.Enabled := isItem and (nd.Index < itemCount - 1);
  FMenu.Controller := ActiveController;
  FMenu.PopupComponent := Self;
  if (MousePos.X = -1) and (MousePos.Y = -1) then
    at := ClientToScreen(Point(ItemRect(flat).Left, ItemRect(flat).Bottom))
  else
    at := ClientToScreen(MousePos);
  Handled := True;
  ShowCollectionMenu(FMenu, at.X, at.Y);
end;

{ Space flips a boolean row -- the list itself does nothing with Space in single selection.
  On a collection or item row: Insert adds, Ctrl+Delete deletes, Ctrl+Up / Ctrl+Down move --
  taken before the list, which would move the selection on Ctrl+Up / Ctrl+Down. }
procedure TTyCustomPropertyGrid.KeyDown(var Key: Word; Shift: TShiftState);
var r: TTyValueRow; nd: TTyPropertyNode; path: string;
begin
  if FRows <> nil then
  begin
    nd := FRows.NodeOf(FlatRowAt(ItemIndex));
    if CollectionEditable(nd) then
    begin
      path := nd.Path;
      if (Key = VK_INSERT) and (Shift = []) then
      begin
        Key := 0;
        AddCollectionItem(path);
        Exit;
      end;
      if nd.Kind = pnkCollectionItem then
      begin
        if (Key = VK_DELETE) and (Shift = [ssModifier]) then
        begin
          Key := 0;
          DeleteCollectionItem(path);
          Exit;
        end;
        if ((Key = VK_UP) or (Key = VK_DOWN)) and (Shift = [ssModifier]) then
        begin
          if Key = VK_UP then MoveCollectionItem(path, -1) else MoveCollectionItem(path, 1);
          Key := 0;
          Exit;
        end;
      end;
    end;
  end;
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
