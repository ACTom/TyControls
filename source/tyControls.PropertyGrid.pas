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
  Classes, SysUtils, TypInfo, Graphics, Controls, LCLType,
  tyControls.ValueListEditor;

type
  { How the rows of one object are ordered: by name, as the Object Inspector does (the default),
    or in the order the class declares them (ancestors first). }
  TTyPropertyOrder = (poByName, poDeclared);

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
    procedure SetHiddenProperties(AValue: TStringList);
    function NewNode(AParent: TTyPropertyNode; APropInfo: PPropInfo; AKind: TTyPropertyNodeKind;
      AIndex: Integer): TTyPropertyNode;
    function Accept(AInstance: TObject; APropInfo: PPropInfo; AParent: TTyPropertyNode): Boolean;
    function KindOf(APropInfo: PPropInfo; AInstance: TObject): TTyPropertyNodeKind;
    procedure AddProperties(AEditor: TTyCustomValueListEditor; AParentRow: TTyValueRow;
      AParentNode: TTyPropertyNode; AInstance: TObject; ADepth: Integer);
    procedure FillRow(ANode: TTyPropertyNode);
    function HolderOf(ANode: TTyPropertyNode): TObject;
    function ValueObject(ANode: TTyPropertyNode): TObject;
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
    { Re-read every row's value from the object, except AExcept (the row being committed). }
    procedure RefreshValues(AExcept: TTyValueRow = nil);
    property Root: TPersistent read FRoot;
    property TypeFilter: TTypeKinds read FTypeFilter write FTypeFilter;
    property HiddenProperties: TStringList read FHiddenProperties write SetHiddenProperties;
    property Order: TTyPropertyOrder read FOrder write FOrder;
    { How many objects deep the rows go (a sub-object of a sub-object... ); stops a cycle. }
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
    property OnFilterProperty: TTyFilterPropertyEvent read FOnFilterProperty write FOnFilterProperty;
  end;

  { The control. Phase 1 skeleton: SelectedObject + the write path; the published surface,
    events and refresh/expansion bookkeeping come with the rest of #65. }
  TTyCustomPropertyGrid = class(TTyCustomValueListEditor)
  private
    FRows: TTyPropertyRows;
    FSelectedObject: TPersistent;
    procedure SetSelectedObject(AValue: TPersistent);
    function FlatRowAt(AFlat: Integer): TTyValueRow;
  protected
    function CanCommitValue(ARow: TTyValueRow; var AText: string): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Rebuild the rows from SelectedObject (after changing a filter, say). }
    procedure Rebuild;
    property SelectedObject: TPersistent read FSelectedObject write SetSelectedObject;
    property PropertyRows: TTyPropertyRows read FRows;
  end;

const
  { The kinds the grid shows by default: everything it can show except event handlers. }
  TyPropertyGridDefaultTypeFilter: TTypeKinds = [Low(TTypeKind)..High(TTypeKind)] - [tkMethod];
  TyPropertyGridDefaultMaxDepth = 6;

{ True when ATypeInfo is TColor (graphics.pp declares TColor = TGraphicsColor, so the RTTI name
  is 'TGraphicsColor' on FPC 3.2.2 and 'TColor' once graphtype switches to System.UITypes). }
function TyIsColorType(ATypeInfo: PTypeInfo): Boolean;

implementation

uses
  tyControls.StrConsts;

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
    pnkSetElement: Result := GetEnumName(GetTypeData(FPropInfo^.PropType)^.CompType, FIndex);
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
  FOrder := poByName;
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

function TTyPropertyRows.KindOf(APropInfo: PPropInfo; AInstance: TObject): TTyPropertyNodeKind;
begin
  case APropInfo^.PropType^.Kind of
    tkMethod: Result := pnkMethod;
  else
    Result := pnkValue;
  end;
end;

{ Is this property shown? Readable, of a kind the grid can show and the filter lets through, not
  hidden by name or path, and not refused by OnFilterProperty. }
function TTyPropertyRows.Accept(AInstance: TObject; APropInfo: PPropInfo;
  AParent: TTyPropertyNode): Boolean;
const
  Showable = [tkInteger, tkChar, tkEnumeration, tkFloat, tkMethod, tkSString, tkLString,
    tkAString, tkWString, tkWChar, tkBool, tkInt64, tkQWord, tkUString];
var
  path: string;
begin
  Result := False;
  if APropInfo^.GetProc = nil then Exit;
  if not (APropInfo^.PropType^.Kind in Showable) then Exit;
  if not (APropInfo^.PropType^.Kind in FTypeFilter) then Exit;
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
    if FOrder = poByName then list.Sort(@ComparePropNames);
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
    end;
  finally
    list.Free;
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
begin
  row := ANode.FRow;
  pt := ANode.FPropInfo^.PropType;
  case ANode.FKind of
    pnkMethod:
      row.EditorKind := vekReadOnly;
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
  row.ReadOnly := (ANode.FKind = pnkMethod) or (ANode.FPropInfo^.SetProc = nil);
  row.Value := ReadText(ANode);
end;

function TTyPropertyRows.ReadText(ANode: TTyPropertyNode): string;
var h: TObject;
begin
  Result := '';
  if ANode = nil then Exit;
  try
    h := HolderOf(ANode);
    if h = nil then Exit;
    case ANode.FKind of
      pnkValue:  Result := SimpleText(h, ANode.FPropInfo);
      pnkMethod: Result := MethodText(h, ANode.FPropInfo);
    end;
  except
    on E: Exception do Result := '(' + E.Message + ')';   // a getter that raises is shown, not fatal
  end;
end;

procedure TTyPropertyRows.WriteOn(ANode: TTyPropertyNode; AHolder: TObject; const AText: string);
begin
  if AHolder = nil then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
  if (ANode.FPropInfo = nil) or (ANode.FPropInfo^.SetProc = nil) then
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
  case ANode.FKind of
    pnkValue: WriteSimple(AHolder, ANode.FPropInfo, AText);
  else
    raise EPropertyError.CreateFmt(rsTyPropGridInvalidValue, [AText, ANode.Name]);
  end;
end;

procedure TTyPropertyRows.WriteText(ANode: TTyPropertyNode; var AText: string);
begin
  WriteOn(ANode, HolderOf(ANode), AText);
  AText := ReadText(ANode);
end;

procedure TTyPropertyRows.RefreshValues(AExcept: TTyValueRow);
var i: Integer; n: TTyPropertyNode;
begin
  for i := 0 to FNodes.Count - 1 do
  begin
    n := TTyPropertyNode(FNodes[i]);
    if (n.FRow <> nil) and (n.FRow <> AExcept) then n.FRow.Value := ReadText(n);
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
end;

destructor TTyCustomPropertyGrid.Destroy;
begin
  Clear;          // rows first: their Data points at the nodes
  FreeAndNil(FRows);
  inherited Destroy;
end;

procedure TTyCustomPropertyGrid.SetSelectedObject(AValue: TPersistent);
begin
  if FSelectedObject = AValue then Exit;
  FSelectedObject := AValue;
  Rebuild;
end;

procedure TTyCustomPropertyGrid.Rebuild;
begin
  FRows.Build(Self, FSelectedObject);
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

function TTyCustomPropertyGrid.CanCommitValue(ARow: TTyValueRow; var AText: string): Boolean;
var nd: TTyPropertyNode;
begin
  if FRows = nil then Exit(inherited CanCommitValue(ARow, AText));   // being destroyed
  nd := FRows.NodeOf(ARow);
  if nd = nil then Exit(inherited CanCommitValue(ARow, AText));
  FRows.WriteText(nd, AText);   // raises -> nothing written, the row keeps its value
  { A setter often moves other properties too (AutoSize -> Width): re-read the rest. The row
    being committed is left for the editor, which compares AText with its old value. }
  FRows.RefreshValues(ARow);
  Invalidate;
  Result := True;
end;

{ Space flips a boolean row -- the list itself does nothing with Space in single selection. }
procedure TTyCustomPropertyGrid.KeyDown(var Key: Word; Shift: TShiftState);
var r: TTyValueRow;
begin
  if (Key = VK_SPACE) and (Shift = []) and not ReadOnly and (EditingRow < 0) then
  begin
    r := FlatRowAt(ItemIndex);
    if (r <> nil) and (r.EditorKind = vekBoolean) and not r.ReadOnly then
    begin
      SetRowValue(r, BoolText(not SameText(r.Value, 'True')));
      Key := 0;
      Exit;
    end;
  end;
  inherited KeyDown(Key, Shift);
end;

end.
