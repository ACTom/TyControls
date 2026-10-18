unit tyControls.Accessible;
{$mode objfpc}{$H+}
{ THE ACCESSIBLE TREE, AND ITS WAY OUT TO THE PLATFORM [Batch 144].

  LCL gives every control a TLazAccessibleObject -- a name, a description, a
  value, a role, a position and a size, and child objects for the things a
  custom-drawn control paints that are not controls (TTreeView's nodes). The
  widgetsets are meant to hand that tree to the platform's accessibility
  layer. IN LAZARUS 3.0 (and still in 4.x) ONLY Qt5 / Qt6 DO: the win32,
  gtk2, gtk3 and cocoa widgetsets register no accessible-object class
  (RegisterLazAccessibleObject answers False there), so on Windows a screen
  reader sees a custom-drawn control as an empty pane, whatever the LCL
  objects say.

  So this unit has three parts:

  - THE ORDERED CHILDREN. LCL keeps the child objects in an AVL tree sorted
    by DataObject (a pointer), and GetChildAccessibleObject(i) walks it from
    a cache that only answers neighbours of the last index asked. A control
    that wants its children in an order -- series in option order, items in
    data order -- has to make the pointer order the semantic order.
    TyAccAddChildren creates the children, each its own DataObject, and
    hands them back sorted by address, so the caller fills the first one
    with the first item and the AVL order is the reading order.
    TyAccChildren reads them back in that order.

  - ITyAccessibleHost: what a control answers beyond the objects' own
    fields -- bring the tree up to date, which child holds the keyboard
    focus, which are selected, move the keyboard focus to a child.

  - ON WINDOWS, AN MSAA SERVER over that tree (TTyAccessibleLink): the
    control's window is subclassed (SetWindowSubclass, so LCL's own window
    procedure is untouched and nothing is added on the paint path) and
    WM_GETOBJECT for OBJID_CLIENT answers an IAccessible built over the LCL
    objects. UI Automation reads MSAA through its proxy, so Narrator hears
    the same tree NVDA does. Every node is a full IAccessible addressed by
    its PATH from the root and resolved against the live tree on every call
    -- the tree is rebuilt when the control lays out again, and a client
    holding an old node gets RPC_E_DISCONNECTED rather than a freed object.
    Focus moves are announced with NotifyWinEvent(EVENT_OBJECT_FOCUS) and a
    rebuilt tree with EVENT_OBJECT_REORDER, the child id of a descendant
    being -(1 + its pre-order index): the root's get_accChild answers those
    (the convention browsers use for events about deep descendants). On
    other platforms the link is inert: Qt reads the LCL objects itself, and
    gtk / cocoa have nothing to hand them to. }
interface

uses
  Classes, SysUtils, Types, Controls;

type
  TTyAccObjectArray = array of TLazAccessibleObject;

  ITyAccessibleHost = interface
    ['{6C1D7F52-1E0B-4F7B-9B35-2B0E7D41A0C1}']
    { the tree up to date with what the control shows }
    procedure AccessibleSync;
    { the descendant that holds the keyboard focus inside the control; nil
      when none does (the control itself, or nothing) }
    function AccessibleFocusedChild: TLazAccessibleObject;
    function AccessibleSelected(AObj: TLazAccessibleObject): Boolean;
    { move the keyboard focus to AObj; False when it cannot take it }
    function AccessibleTakeFocus(AObj: TLazAccessibleObject): Boolean;
  end;

  { The control's way out to the platform. Owned by the control: created
    with it, Attach after its window is made, Detach before the window
    goes, freed with it (which disconnects every node a client still
    holds). }
  TTyAccessibleLink = class
  private
    FControl: TWinControl;
    FAnchor: TObject;
    FAnchorRef: IInterface;
  public
    constructor Create(AControl: TWinControl);
    destructor Destroy; override;
    procedure Attach;
    procedure Detach;
    { whether an assistive client has asked for the tree since the window
      was made -- the tree is worth keeping current only then }
    function InUse: Boolean;
    { the keyboard focus moved to AObj (a descendant of the control's root,
      or the root itself for nil) }
    procedure NotifyFocus(AObj: TLazAccessibleObject);
    { the tree under the root was rebuilt }
    procedure NotifyReorder;
    { the root as the platform's own object: an IAccessible on Windows, nil
      elsewhere -- what WM_GETOBJECT hands out }
    function Root: IUnknown;
  end;

{ AObj's children in the AVL order, which TyAccAddChildren made the order
  they were added in }
function TyAccChildren(AObj: TLazAccessibleObject): TTyAccObjectArray;

{ ACount new children of AParent, each its own DataObject, returned in
  address order -- the order LCL lists them in }
function TyAccAddChildren(AParent: TLazAccessibleObject; ACount: Integer): TTyAccObjectArray;

{ AObj's place among ARoot's descendants walked in pre-order (ARoot itself
  not counted, its first child 0); -1 when AObj is not under ARoot }
function TyAccPreorderIndex(ARoot, AObj: TLazAccessibleObject): Integer;

{ the descendant at pre-order index AIndex; nil when there is none }
function TyAccByPreorder(ARoot: TLazAccessibleObject; AIndex: Integer): TLazAccessibleObject;

{$IFDEF WINDOWS}
type
  { MSAA's IAccessible (oleacc.idl), every parameter as the C ABI passes it:
    a VARIANT by value as a record of its size, every out slot as a plain
    pointer the server writes -- no managed types cross the boundary }
  TTyAccVariant = packed record
    VType: Word;
    Reserved1, Reserved2, Reserved3: Word;
    case Integer of
      0: (LVal: LongInt);
      1: (PVal: Pointer);
      2: (Pad: array[0..1] of Pointer);
  end;
  PTyAccVariant = ^TTyAccVariant;

  IAccessible = interface(IDispatch)
    ['{618736E0-3C3D-11CF-810C-00AA00389B71}']
    function get_accParent(ppdispParent: PPointer): HResult; stdcall;
    function get_accChildCount(pcountChildren: PLongInt): HResult; stdcall;
    function get_accChild(varChild: TTyAccVariant; ppdispChild: PPointer): HResult; stdcall;
    function get_accName(varChild: TTyAccVariant; pszName: PPWideChar): HResult; stdcall;
    function get_accValue(varChild: TTyAccVariant; pszValue: PPWideChar): HResult; stdcall;
    function get_accDescription(varChild: TTyAccVariant; pszDescription: PPWideChar): HResult; stdcall;
    function get_accRole(varChild: TTyAccVariant; pvarRole: PTyAccVariant): HResult; stdcall;
    function get_accState(varChild: TTyAccVariant; pvarState: PTyAccVariant): HResult; stdcall;
    function get_accHelp(varChild: TTyAccVariant; pszHelp: PPWideChar): HResult; stdcall;
    function get_accHelpTopic(pszHelpFile: PPWideChar; varChild: TTyAccVariant;
      pidTopic: PLongInt): HResult; stdcall;
    function get_accKeyboardShortcut(varChild: TTyAccVariant; pszKeyboardShortcut: PPWideChar): HResult; stdcall;
    function get_accFocus(pvarChild: PTyAccVariant): HResult; stdcall;
    function get_accSelection(pvarChildren: PTyAccVariant): HResult; stdcall;
    function get_accDefaultAction(varChild: TTyAccVariant; pszDefaultAction: PPWideChar): HResult; stdcall;
    function accSelect(flagsSelect: LongInt; varChild: TTyAccVariant): HResult; stdcall;
    function accLocation(pxLeft, pyTop, pcxWidth, pcyHeight: PLongInt;
      varChild: TTyAccVariant): HResult; stdcall;
    function accNavigate(navDir: LongInt; varStart: TTyAccVariant;
      pvarEndUpAt: PTyAccVariant): HResult; stdcall;
    function accHitTest(xLeft, yTop: LongInt; pvarChild: PTyAccVariant): HResult; stdcall;
    function accDoDefaultAction(varChild: TTyAccVariant): HResult; stdcall;
    function put_accName(varChild: TTyAccVariant; szName: PWideChar): HResult; stdcall;
    function put_accValue(varChild: TTyAccVariant; szValue: PWideChar): HResult; stdcall;
  end;

const
  TyAccVtEmpty = 0;
  TyAccVtI4 = 3;
  TyAccVtDispatch = 9;
  TyAccChildSelf = 0;
  TyAccObjIdClient = -4;
  TyAccObjIdWindow = 0;
  TyAccStateSelected = $2;
  TyAccStateFocused = $4;
  TyAccStateChecked = $10;
  TyAccStateInvisible = $8000;
  TyAccStateFocusable = $100000;
  TyAccStateSelectable = $200000;
  TyAccNavUp = 1;
  TyAccNavDown = 2;
  TyAccNavLeft = 3;
  TyAccNavRight = 4;
  TyAccNavNext = 5;
  TyAccNavPrevious = 6;
  TyAccNavFirstChild = 7;
  TyAccNavLastChild = 8;
  TyAccSelTakeFocus = 1;
  TyAccEventFocus = $8005;
  TyAccEventReorder = $8004;
  TyAccDisconnected = HResult($80010108);

{ the MSAA role a TLazAccessibilityRole is }
function TyAccMsaaRole(ARole: TLazAccessibilityRole): LongInt;

{ a variant naming child AId (VT_I4) }
function TyAccChild(AId: LongInt): TTyAccVariant;

{ a BSTR out of a string an IAccessible wrote, freed }
function TyAccTakeBstr(ABstr: PWideChar): string;

{ release what a VARIANT out-slot holds (a dispatch), leave it empty }
procedure TyAccClearVariant(var AVar: TTyAccVariant);
{$ENDIF}

implementation

{$IFDEF WINDOWS}
uses Windows, CommCtrl, ctypes;
{$ENDIF}

function TyAccChildren(AObj: TLazAccessibleObject): TTyAccObjectArray;
var
  c: TLazAccessibleObject;
  n: Integer;
begin
  Result := nil;
  if AObj = nil then Exit;
  SetLength(Result, AObj.GetChildAccessibleObjectsCount);
  n := 0;
  for c in AObj do
  begin
    if n > High(Result) then SetLength(Result, n + 1);
    Result[n] := c;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function TyAccAddChildren(AParent: TLazAccessibleObject; ACount: Integer): TTyAccObjectArray;
var
  i, j: Integer;
  t: TLazAccessibleObject;
begin
  Result := nil;
  if (AParent = nil) or (ACount <= 0) then Exit;
  SetLength(Result, ACount);
  for i := 0 to ACount - 1 do
  begin
    Result[i] := TLazAccessibleObject.Create(AParent.OwnerControl);
    Result[i].DataObject := Result[i];
  end;
  { insertion sort by address: the AVL tree's own order }
  for i := 1 to ACount - 1 do
  begin
    t := Result[i];
    j := i - 1;
    while (j >= 0) and (PtrUInt(Pointer(Result[j])) > PtrUInt(Pointer(t))) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := t;
  end;
  for i := 0 to ACount - 1 do AParent.InsertChildAccessibleObject(Result[i]);
end;

function PreorderWalk(ANode, ATarget: TLazAccessibleObject; var ACount: Integer;
  AIndex: Integer; out AFound: TLazAccessibleObject): Boolean;
var
  kids: TTyAccObjectArray;
  i: Integer;
begin
  Result := False;
  AFound := nil;
  kids := TyAccChildren(ANode);
  for i := 0 to High(kids) do
  begin
    if ((ATarget <> nil) and (kids[i] = ATarget))
      or ((ATarget = nil) and (ACount = AIndex)) then
    begin
      AFound := kids[i];
      Exit(True);
    end;
    Inc(ACount);
    if PreorderWalk(kids[i], ATarget, ACount, AIndex, AFound) then Exit(True);
  end;
end;

function TyAccPreorderIndex(ARoot, AObj: TLazAccessibleObject): Integer;
var
  n: Integer;
  f: TLazAccessibleObject;
begin
  Result := -1;
  if (ARoot = nil) or (AObj = nil) then Exit;
  n := 0;
  if PreorderWalk(ARoot, AObj, n, -1, f) then Result := n;
end;

function TyAccByPreorder(ARoot: TLazAccessibleObject; AIndex: Integer): TLazAccessibleObject;
var n: Integer;
begin
  Result := nil;
  if (ARoot = nil) or (AIndex < 0) then Exit;
  n := 0;
  PreorderWalk(ARoot, nil, n, AIndex, Result);
end;

{$IFDEF WINDOWS}

{ ==================== the platform's entry points ==================== }

type
  TLresultFromObject = function(riid: PGUID; wParam: WPARAM; punk: Pointer): LRESULT; stdcall;
  TCreateStdAccessibleObject = function(hwnd: HWND; idObject: LongInt; riid: PGUID;
    ppvObject: PPointer): HResult; stdcall;

const
  IID_IAccessible: TGUID = '{618736E0-3C3D-11CF-810C-00AA00389B71}';
  IID_IDispatchAcc: TGUID = '{00020400-0000-0000-C000-000000000046}';
  cWmGetObject = $003D;
  cDispMemberNotFound = HResult($80020003);
  cSubclassId = $54794163;   { 'TyAc' }

var
  GOleAcc: HMODULE = 0;
  GOleAccTried: Boolean = False;
  GLresultFromObject: TLresultFromObject = nil;
  GCreateStdAccessibleObject: TCreateStdAccessibleObject = nil;

procedure TyNotifyWinEvent(AEvent: DWORD; AWnd: HWND; AObject, AChild: LongInt);
  stdcall; external 'user32.dll' name 'NotifyWinEvent';
function TySysAllocStringLen(psz: PWideChar; len: UINT): PWideChar;
  stdcall; external 'oleaut32.dll' name 'SysAllocStringLen';
procedure TySysFreeString(bstr: PWideChar);
  stdcall; external 'oleaut32.dll' name 'SysFreeString';

procedure LoadOleAcc;
begin
  if GOleAccTried then Exit;
  GOleAccTried := True;
  GOleAcc := LoadLibrary('oleacc.dll');
  if GOleAcc = 0 then Exit;
  Pointer(GLresultFromObject) := GetProcAddress(GOleAcc, 'LresultFromObject');
  Pointer(GCreateStdAccessibleObject) := GetProcAddress(GOleAcc, 'CreateStdAccessibleObject');
end;

function TyAccMsaaRole(ARole: TLazAccessibilityRole): LongInt;
begin
  case ARole of
    larAnimation: Result := $36;           { ROLE_SYSTEM_ANIMATION }
    larButton: Result := $2B;              { PUSHBUTTON }
    larCell: Result := $1D;                { CELL }
    larChart: Result := $11;               { CHART }
    larCheckBox: Result := $2C;            { CHECKBUTTON }
    larClock: Result := $3D;               { CLOCK }
    larColorPicker: Result := $38;         { DROPLIST: no colour role }
    larColumn: Result := $1B;              { COLUMN }
    larComboBox: Result := $2E;            { COMBOBOX }
    larDateField: Result := $2A;           { TEXT }
    larGrid: Result := $18;                { TABLE }
    larGroup: Result := $14;               { GROUPING }
    larImage: Result := $28;               { GRAPHIC }
    larLabel: Result := $29;               { STATICTEXT }
    larListBox: Result := $21;             { LIST }
    larListItem: Result := $22;            { LISTITEM }
    larMenuBar: Result := $02;             { MENUBAR }
    larMenuItem: Result := $0C;            { MENUITEM }
    larProgressIndicator: Result := $30;   { PROGRESSBAR }
    larRadioButton: Result := $2D;         { RADIOBUTTON }
    larResizeGrip: Result := $04;          { GRIP }
    larRow: Result := $1C;                 { ROW }
    larScrollBar: Result := $03;           { SCROLLBAR }
    larSpinner: Result := $34;             { SPINBUTTON }
    larTabControl: Result := $3C;          { PAGETABLIST }
    larText: Result := $29;                { STATICTEXT }
    larTextEditorMultiline, larTextEditorSingleline: Result := $2A;   { TEXT }
    larToolBar: Result := $16;             { TOOLBAR }
    larToolBarButton: Result := $2B;       { PUSHBUTTON }
    larTrackBar: Result := $33;            { SLIDER }
    larTreeView: Result := $23;            { OUTLINE }
    larTreeItem: Result := $24;            { OUTLINEITEM }
    larWindow: Result := $09;              { WINDOW }
  else
    Result := $0A;                         { CLIENT }
  end;
end;

function TyAccChild(AId: LongInt): TTyAccVariant;
begin
  Result := Default(TTyAccVariant);
  Result.VType := TyAccVtI4;
  Result.LVal := AId;
end;

function TyAccTakeBstr(ABstr: PWideChar): string;
var w: WideString;
begin
  Result := '';
  if ABstr = nil then Exit;
  w := WideString(ABstr);
  Result := UTF8Encode(w);
  TySysFreeString(ABstr);
end;

procedure TyAccClearVariant(var AVar: TTyAccVariant);
var u: IUnknown;
begin
  if (AVar.VType = TyAccVtDispatch) and (AVar.PVal <> nil) then
  begin
    { the slot's reference, taken over and dropped }
    Pointer(u) := AVar.PVal;
    u := nil;
  end;
  AVar := Default(TTyAccVariant);
end;

{ ==================== the anchor and the nodes ==================== }

type
  { What every node holds: the control, nil once it is gone -- the one
    thing a node may not outlive. Reference counted: the link and every
    node a client keeps hold it. }
  TTyMsaaAnchor = class(TInterfacedObject)
  public
    Control: TWinControl;
    Hooked: Boolean;
    HookedWnd: HWND;
    Used: Boolean;
  end;

  TTyPath = array of Integer;

  TTyMsaaNode = class(TInterfacedObject, IDispatch, IAccessible)
  private
    FAnchor: TTyMsaaAnchor;
    FAnchorRef: IInterface;
    FPath: TTyPath;
    function Host(out AHost: ITyAccessibleHost): Boolean;
    { the object this node is, the tree synced first }
    function Resolve(out AObj: TLazAccessibleObject): HResult;
    { the object varChild names relative to this node }
    function Target(const AVar: TTyAccVariant; out AObj: TLazAccessibleObject): HResult;
    function NodeFor(AObj: TLazAccessibleObject): IAccessible;
    function PutString(const AText: string; ADest: PPWideChar): HResult;
    procedure PutDispatch(AObj: TLazAccessibleObject; ADest: PTyAccVariant);
    function ScreenRect(AObj: TLazAccessibleObject; out R: TRect): Boolean;
  public
    constructor Create(AAnchor: TTyMsaaAnchor; const APath: TTyPath);
    { IDispatch }
    function GetTypeInfoCount(out count: LongInt): HResult; stdcall;
    function GetTypeInfo(Index, LocaleID: LongInt; out TypeInfo): HResult; stdcall;
    function GetIDsOfNames(const iid: TGUID; names: Pointer; NameCount, LocaleID: LongInt;
      DispIDs: Pointer): HResult; stdcall;
    function Invoke(DispID: LongInt; const iid: TGUID; LocaleID: LongInt; Flags: Word;
      var params; VarResult, ExcepInfo, ArgErr: Pointer): HResult; stdcall;
    { IAccessible }
    function get_accParent(ppdispParent: PPointer): HResult; stdcall;
    function get_accChildCount(pcountChildren: PLongInt): HResult; stdcall;
    function get_accChild(varChild: TTyAccVariant; ppdispChild: PPointer): HResult; stdcall;
    function get_accName(varChild: TTyAccVariant; pszName: PPWideChar): HResult; stdcall;
    function get_accValue(varChild: TTyAccVariant; pszValue: PPWideChar): HResult; stdcall;
    function get_accDescription(varChild: TTyAccVariant; pszDescription: PPWideChar): HResult; stdcall;
    function get_accRole(varChild: TTyAccVariant; pvarRole: PTyAccVariant): HResult; stdcall;
    function get_accState(varChild: TTyAccVariant; pvarState: PTyAccVariant): HResult; stdcall;
    function get_accHelp(varChild: TTyAccVariant; pszHelp: PPWideChar): HResult; stdcall;
    function get_accHelpTopic(pszHelpFile: PPWideChar; varChild: TTyAccVariant;
      pidTopic: PLongInt): HResult; stdcall;
    function get_accKeyboardShortcut(varChild: TTyAccVariant; pszKeyboardShortcut: PPWideChar): HResult; stdcall;
    function get_accFocus(pvarChild: PTyAccVariant): HResult; stdcall;
    function get_accSelection(pvarChildren: PTyAccVariant): HResult; stdcall;
    function get_accDefaultAction(varChild: TTyAccVariant; pszDefaultAction: PPWideChar): HResult; stdcall;
    function accSelect(flagsSelect: LongInt; varChild: TTyAccVariant): HResult; stdcall;
    function accLocation(pxLeft, pyTop, pcxWidth, pcyHeight: PLongInt;
      varChild: TTyAccVariant): HResult; stdcall;
    function accNavigate(navDir: LongInt; varStart: TTyAccVariant;
      pvarEndUpAt: PTyAccVariant): HResult; stdcall;
    function accHitTest(xLeft, yTop: LongInt; pvarChild: PTyAccVariant): HResult; stdcall;
    function accDoDefaultAction(varChild: TTyAccVariant): HResult; stdcall;
    function put_accName(varChild: TTyAccVariant; szName: PWideChar): HResult; stdcall;
    function put_accValue(varChild: TTyAccVariant; szValue: PWideChar): HResult; stdcall;
  end;

function PathOf(ARoot, AObj: TLazAccessibleObject; out APath: TTyPath): Boolean;
var
  chain: TTyAccObjectArray;
  kids: TTyAccObjectArray;
  o: TLazAccessibleObject;
  i, j, n: Integer;
begin
  APath := nil;
  Result := False;
  chain := nil;
  o := AObj;
  while (o <> nil) and (o <> ARoot) do
  begin
    SetLength(chain, Length(chain) + 1);
    chain[High(chain)] := o;
    o := o.Parent;
  end;
  if o <> ARoot then Exit;
  SetLength(APath, Length(chain));
  n := 0;
  o := ARoot;
  for i := High(chain) downto 0 do
  begin
    kids := TyAccChildren(o);
    APath[n] := -1;
    for j := 0 to High(kids) do
      if kids[j] = chain[i] then APath[n] := j;
    if APath[n] < 0 then Exit;
    o := chain[i];
    Inc(n);
  end;
  Result := True;
end;

constructor TTyMsaaNode.Create(AAnchor: TTyMsaaAnchor; const APath: TTyPath);
begin
  inherited Create;
  FAnchor := AAnchor;
  FAnchorRef := AAnchor;
  FPath := Copy(APath);
end;

function TTyMsaaNode.Host(out AHost: ITyAccessibleHost): Boolean;
begin
  AHost := nil;
  Result := (FAnchor.Control <> nil)
    and Supports(FAnchor.Control, ITyAccessibleHost, AHost);
end;

function TTyMsaaNode.Resolve(out AObj: TLazAccessibleObject): HResult;
var
  h: ITyAccessibleHost;
  kids: TTyAccObjectArray;
  i: Integer;
begin
  AObj := nil;
  if FAnchor.Control = nil then Exit(TyAccDisconnected);
  if Host(h) then h.AccessibleSync;
  AObj := FAnchor.Control.GetAccessibleObject;
  for i := 0 to High(FPath) do
  begin
    kids := TyAccChildren(AObj);
    if (FPath[i] < 0) or (FPath[i] > High(kids)) then
    begin
      AObj := nil;
      Exit(TyAccDisconnected);
    end;
    AObj := kids[FPath[i]];
  end;
  Result := S_OK;
end;

function TTyMsaaNode.Target(const AVar: TTyAccVariant; out AObj: TLazAccessibleObject): HResult;
var
  self_: TLazAccessibleObject;
  kids: TTyAccObjectArray;
begin
  AObj := nil;
  Result := Resolve(self_);
  if Result <> S_OK then Exit;
  if AVar.VType = TyAccVtEmpty then
  begin
    AObj := self_;
    Exit(S_OK);
  end;
  if AVar.VType <> TyAccVtI4 then Exit(E_INVALIDARG);
  if AVar.LVal = TyAccChildSelf then
  begin
    AObj := self_;
    Exit(S_OK);
  end;
  if AVar.LVal > 0 then
  begin
    kids := TyAccChildren(self_);
    if AVar.LVal > Length(kids) then Exit(E_INVALIDARG);
    AObj := kids[AVar.LVal - 1];
    Exit(S_OK);
  end;
  { a negative id is a descendant's pre-order number, asked of the root --
    the id the focus events carry }
  if Length(FPath) > 0 then Exit(E_INVALIDARG);
  AObj := TyAccByPreorder(self_, -AVar.LVal - 1);
  if AObj = nil then Exit(E_INVALIDARG);
  Result := S_OK;
end;

function TTyMsaaNode.NodeFor(AObj: TLazAccessibleObject): IAccessible;
var p: TTyPath;
begin
  Result := nil;
  if FAnchor.Control = nil then Exit;
  if not PathOf(FAnchor.Control.GetAccessibleObject, AObj, p) then Exit;
  Result := TTyMsaaNode.Create(FAnchor, p);
end;

function TTyMsaaNode.PutString(const AText: string; ADest: PPWideChar): HResult;
var w: WideString;
begin
  if ADest = nil then Exit(E_POINTER);
  ADest^ := nil;
  if AText = '' then Exit(S_FALSE);
  w := UTF8Decode(AText);
  ADest^ := TySysAllocStringLen(PWideChar(w), Length(w));
  Result := S_OK;
end;

procedure TTyMsaaNode.PutDispatch(AObj: TLazAccessibleObject; ADest: PTyAccVariant);
var
  acc: IAccessible;
  d: IDispatch;
begin
  ADest^ := Default(TTyAccVariant);
  acc := NodeFor(AObj);
  if acc = nil then Exit;
  d := acc;
  d._AddRef;
  ADest^.VType := TyAccVtDispatch;
  ADest^.PVal := Pointer(d);
end;

function TTyMsaaNode.ScreenRect(AObj: TLazAccessibleObject; out R: TRect): Boolean;
var
  c: TWinControl;
  o: TPoint;
  sz: TSize;
begin
  R := Types.Rect(0, 0, 0, 0);
  c := FAnchor.Control;
  Result := c <> nil;
  if not Result then Exit;
  o := c.ClientOrigin;
  if AObj = c.GetAccessibleObject then
  begin
    R := Types.Rect(o.X, o.Y, o.X + c.ClientWidth, o.Y + c.ClientHeight);
    Exit;
  end;
  { a child's position is in the control's client coordinates }
  sz := AObj.Size;
  R.Left := o.X + AObj.Position.X;
  R.Top := o.Y + AObj.Position.Y;
  R.Right := R.Left + sz.cx;
  R.Bottom := R.Top + sz.cy;
end;

function TTyMsaaNode.GetTypeInfoCount(out count: LongInt): HResult; stdcall;
begin
  count := 0;
  Result := S_OK;
end;

function TTyMsaaNode.GetTypeInfo(Index, LocaleID: LongInt; out TypeInfo): HResult; stdcall;
begin
  Pointer(TypeInfo) := nil;
  Result := E_NOTIMPL;
end;

function TTyMsaaNode.GetIDsOfNames(const iid: TGUID; names: Pointer; NameCount,
  LocaleID: LongInt; DispIDs: Pointer): HResult; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TTyMsaaNode.Invoke(DispID: LongInt; const iid: TGUID; LocaleID: LongInt;
  Flags: Word; var params; VarResult, ExcepInfo, ArgErr: Pointer): HResult; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TTyMsaaNode.get_accParent(ppdispParent: PPointer): HResult; stdcall;
var
  o: TLazAccessibleObject;
  acc: IAccessible;
  d: IDispatch;
begin
  if ppdispParent = nil then Exit(E_POINTER);
  ppdispParent^ := nil;
  Result := Resolve(o);
  if Result <> S_OK then Exit;
  if Length(FPath) = 0 then
  begin
    { the root's parent is the window's own object }
    LoadOleAcc;
    if (not FAnchor.Control.HandleAllocated) or not Assigned(GCreateStdAccessibleObject) then
      Exit(S_FALSE);
    Result := GCreateStdAccessibleObject(FAnchor.Control.Handle, TyAccObjIdWindow,
      @IID_IDispatchAcc, ppdispParent);
    Exit;
  end;
  acc := NodeFor(o.Parent);
  if acc = nil then Exit(S_FALSE);
  d := acc;
  d._AddRef;
  ppdispParent^ := Pointer(d);
  Result := S_OK;
end;

function TTyMsaaNode.get_accChildCount(pcountChildren: PLongInt): HResult; stdcall;
var o: TLazAccessibleObject;
begin
  if pcountChildren = nil then Exit(E_POINTER);
  pcountChildren^ := 0;
  Result := Resolve(o);
  if Result <> S_OK then Exit;
  pcountChildren^ := o.GetChildAccessibleObjectsCount;
end;

function TTyMsaaNode.get_accChild(varChild: TTyAccVariant; ppdispChild: PPointer): HResult; stdcall;
var
  o: TLazAccessibleObject;
  acc: IAccessible;
  d: IDispatch;
begin
  if ppdispChild = nil then Exit(E_POINTER);
  ppdispChild^ := nil;
  if (varChild.VType = TyAccVtI4) and (varChild.LVal = TyAccChildSelf) then
    Exit(E_INVALIDARG);
  Result := Target(varChild, o);
  if Result <> S_OK then Exit;
  acc := NodeFor(o);
  if acc = nil then Exit(E_INVALIDARG);
  d := acc;
  d._AddRef;
  ppdispChild^ := Pointer(d);
  Result := S_OK;
end;

function TTyMsaaNode.get_accName(varChild: TTyAccVariant; pszName: PPWideChar): HResult; stdcall;
var o: TLazAccessibleObject;
begin
  if pszName = nil then Exit(E_POINTER);
  pszName^ := nil;
  Result := Target(varChild, o);
  if Result = S_OK then Result := PutString(o.AccessibleName, pszName);
end;

function TTyMsaaNode.get_accValue(varChild: TTyAccVariant; pszValue: PPWideChar): HResult; stdcall;
var o: TLazAccessibleObject;
begin
  if pszValue = nil then Exit(E_POINTER);
  pszValue^ := nil;
  Result := Target(varChild, o);
  if Result = S_OK then Result := PutString(o.AccessibleValue, pszValue);
end;

function TTyMsaaNode.get_accDescription(varChild: TTyAccVariant;
  pszDescription: PPWideChar): HResult; stdcall;
var o: TLazAccessibleObject;
begin
  if pszDescription = nil then Exit(E_POINTER);
  pszDescription^ := nil;
  Result := Target(varChild, o);
  if Result = S_OK then Result := PutString(o.AccessibleDescription, pszDescription);
end;

function TTyMsaaNode.get_accRole(varChild: TTyAccVariant; pvarRole: PTyAccVariant): HResult; stdcall;
var o: TLazAccessibleObject;
begin
  if pvarRole = nil then Exit(E_POINTER);
  pvarRole^ := Default(TTyAccVariant);
  Result := Target(varChild, o);
  if Result <> S_OK then Exit;
  pvarRole^.VType := TyAccVtI4;
  pvarRole^.LVal := TyAccMsaaRole(o.AccessibleRole);
end;

function TTyMsaaNode.get_accState(varChild: TTyAccVariant; pvarState: PTyAccVariant): HResult; stdcall;
var
  o: TLazAccessibleObject;
  h: ITyAccessibleHost;
  st: LongInt;
  c: TWinControl;
begin
  if pvarState = nil then Exit(E_POINTER);
  pvarState^ := Default(TTyAccVariant);
  Result := Target(varChild, o);
  if Result <> S_OK then Exit;
  c := FAnchor.Control;
  st := 0;
  if not c.IsVisible then st := st or TyAccStateInvisible;
  if o = c.GetAccessibleObject then
  begin
    if c.TabStop and c.CanFocus then st := st or TyAccStateFocusable;
    if c.Focused then st := st or TyAccStateFocused;
  end
  else if o.GetChildAccessibleObjectsCount = 0 then
  begin
    { an item: it takes the keyboard focus inside the control, and the
      control says whether it is selected -- [F5] a check box's (a legend
      item, a visualMap piece) is checked }
    st := st or TyAccStateSelectable or TyAccStateFocusable;
    if Host(h) then
    begin
      if h.AccessibleSelected(o) then
        if o.AccessibleRole = larCheckBox then st := st or TyAccStateChecked
        else st := st or TyAccStateSelected;
      if c.Focused and (h.AccessibleFocusedChild = o) then st := st or TyAccStateFocused;
    end;
  end;
  pvarState^.VType := TyAccVtI4;
  pvarState^.LVal := st;
end;

function TTyMsaaNode.get_accHelp(varChild: TTyAccVariant; pszHelp: PPWideChar): HResult; stdcall;
begin
  if pszHelp <> nil then pszHelp^ := nil;
  Result := S_FALSE;
end;

function TTyMsaaNode.get_accHelpTopic(pszHelpFile: PPWideChar; varChild: TTyAccVariant;
  pidTopic: PLongInt): HResult; stdcall;
begin
  if pszHelpFile <> nil then pszHelpFile^ := nil;
  if pidTopic <> nil then pidTopic^ := 0;
  Result := S_FALSE;
end;

function TTyMsaaNode.get_accKeyboardShortcut(varChild: TTyAccVariant;
  pszKeyboardShortcut: PPWideChar): HResult; stdcall;
begin
  if pszKeyboardShortcut <> nil then pszKeyboardShortcut^ := nil;
  Result := S_FALSE;
end;

function TTyMsaaNode.get_accFocus(pvarChild: PTyAccVariant): HResult; stdcall;
var
  o, f: TLazAccessibleObject;
  h: ITyAccessibleHost;
begin
  if pvarChild = nil then Exit(E_POINTER);
  pvarChild^ := Default(TTyAccVariant);
  Result := Resolve(o);
  if Result <> S_OK then Exit;
  if not FAnchor.Control.Focused then Exit(S_FALSE);
  f := nil;
  if Host(h) then f := h.AccessibleFocusedChild;
  if (f = nil) or (f = o) then
  begin
    if Length(FPath) > 0 then Exit(S_FALSE);
    pvarChild^.VType := TyAccVtI4;
    pvarChild^.LVal := TyAccChildSelf;
    Exit(S_OK);
  end;
  PutDispatch(f, pvarChild);
  if pvarChild^.VType = TyAccVtEmpty then Result := S_FALSE;
end;

function TTyMsaaNode.get_accSelection(pvarChildren: PTyAccVariant): HResult; stdcall;
begin
  if pvarChildren = nil then Exit(E_POINTER);
  pvarChildren^ := Default(TTyAccVariant);
  Result := S_FALSE;
end;

function TTyMsaaNode.get_accDefaultAction(varChild: TTyAccVariant;
  pszDefaultAction: PPWideChar): HResult; stdcall;
begin
  if pszDefaultAction <> nil then pszDefaultAction^ := nil;
  Result := S_FALSE;
end;

function TTyMsaaNode.accSelect(flagsSelect: LongInt; varChild: TTyAccVariant): HResult; stdcall;
var
  o: TLazAccessibleObject;
  h: ITyAccessibleHost;
begin
  Result := Target(varChild, o);
  if Result <> S_OK then Exit;
  if (flagsSelect and TyAccSelTakeFocus) = 0 then Exit(cDispMemberNotFound);
  if Host(h) and h.AccessibleTakeFocus(o) then Result := S_OK
  else Result := S_FALSE;
end;

function TTyMsaaNode.accLocation(pxLeft, pyTop, pcxWidth, pcyHeight: PLongInt;
  varChild: TTyAccVariant): HResult; stdcall;
var
  o: TLazAccessibleObject;
  r: TRect;
begin
  if (pxLeft = nil) or (pyTop = nil) or (pcxWidth = nil) or (pcyHeight = nil) then
    Exit(E_POINTER);
  pxLeft^ := 0;
  pyTop^ := 0;
  pcxWidth^ := 0;
  pcyHeight^ := 0;
  Result := Target(varChild, o);
  if Result <> S_OK then Exit;
  if not ScreenRect(o, r) then Exit(S_FALSE);
  pxLeft^ := r.Left;
  pyTop^ := r.Top;
  pcxWidth^ := r.Right - r.Left;
  pcyHeight^ := r.Bottom - r.Top;
end;

function TTyMsaaNode.accNavigate(navDir: LongInt; varStart: TTyAccVariant;
  pvarEndUpAt: PTyAccVariant): HResult; stdcall;
var
  o, dest: TLazAccessibleObject;
  kids: TTyAccObjectArray;
  i: Integer;
begin
  if pvarEndUpAt = nil then Exit(E_POINTER);
  pvarEndUpAt^ := Default(TTyAccVariant);
  Result := Target(varStart, o);
  if Result <> S_OK then Exit;
  dest := nil;
  case navDir of
    TyAccNavFirstChild, TyAccNavLastChild:
      begin
        kids := TyAccChildren(o);
        if Length(kids) > 0 then
          if navDir = TyAccNavFirstChild then dest := kids[0] else dest := kids[High(kids)];
      end;
    TyAccNavNext, TyAccNavPrevious, TyAccNavDown, TyAccNavUp, TyAccNavRight, TyAccNavLeft:
      if (o.Parent <> nil) and (o <> FAnchor.Control.GetAccessibleObject) then
      begin
        kids := TyAccChildren(o.Parent);
        for i := 0 to High(kids) do
          if kids[i] = o then
          begin
            if ((navDir = TyAccNavNext) or (navDir = TyAccNavDown) or (navDir = TyAccNavRight))
              and (i < High(kids)) then
              dest := kids[i + 1]
            else if ((navDir = TyAccNavPrevious) or (navDir = TyAccNavUp) or (navDir = TyAccNavLeft))
              and (i > 0) then
              dest := kids[i - 1];
            Break;
          end;
      end;
  else
    Exit(E_INVALIDARG);
  end;
  if dest = nil then Exit(S_FALSE);
  PutDispatch(dest, pvarEndUpAt);
  if pvarEndUpAt^.VType = TyAccVtEmpty then Result := S_FALSE;
end;

function TTyMsaaNode.accHitTest(xLeft, yTop: LongInt; pvarChild: PTyAccVariant): HResult; stdcall;
var
  o, hit: TLazAccessibleObject;
  r: TRect;
  p: TPoint;

  { the last leaf under the point, in reading order: items are painted in
    data order, so the later one is on top where two overlap }
  procedure Walk(ANode: TLazAccessibleObject);
  var
    kids: TTyAccObjectArray;
    i: Integer;
    rr: TRect;
  begin
    kids := TyAccChildren(ANode);
    for i := 0 to High(kids) do
    begin
      if kids[i].GetChildAccessibleObjectsCount > 0 then Walk(kids[i])
      else if ScreenRect(kids[i], rr) and PtInRect(rr, p) then hit := kids[i];
    end;
  end;

begin
  if pvarChild = nil then Exit(E_POINTER);
  pvarChild^ := Default(TTyAccVariant);
  Result := Resolve(o);
  if Result <> S_OK then Exit;
  p := Types.Point(xLeft, yTop);
  if not ScreenRect(o, r) then Exit(S_FALSE);
  hit := nil;
  Walk(o);
  if hit = nil then
  begin
    if (o = FAnchor.Control.GetAccessibleObject) and not PtInRect(r, p) then Exit(S_FALSE);
    pvarChild^.VType := TyAccVtI4;
    pvarChild^.LVal := TyAccChildSelf;
    Exit(S_OK);
  end;
  PutDispatch(hit, pvarChild);
  if pvarChild^.VType = TyAccVtEmpty then Result := S_FALSE;
end;

function TTyMsaaNode.accDoDefaultAction(varChild: TTyAccVariant): HResult; stdcall;
begin
  Result := cDispMemberNotFound;
end;

function TTyMsaaNode.put_accName(varChild: TTyAccVariant; szName: PWideChar): HResult; stdcall;
begin
  Result := cDispMemberNotFound;
end;

function TTyMsaaNode.put_accValue(varChild: TTyAccVariant; szValue: PWideChar): HResult; stdcall;
begin
  Result := cDispMemberNotFound;
end;

{ ==================== the window ==================== }

function MsaaSubclassProc(hwnd: HWND; uMsg: cUINT; wParam: WPARAM; lParam: LPARAM;
  uISubClass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;
var
  anchor: TTyMsaaAnchor;
  acc: IAccessible;
begin
  if (uMsg = cWmGetObject) and (LongInt(DWORD(lParam)) = TyAccObjIdClient) then
  begin
    anchor := TTyMsaaAnchor(Pointer(dwRefData));
    LoadOleAcc;
    if (anchor <> nil) and (anchor.Control <> nil) and Assigned(GLresultFromObject) then
    begin
      anchor.Used := True;
      acc := TTyMsaaNode.Create(anchor, nil);
      Exit(GLresultFromObject(@IID_IAccessible, wParam, Pointer(acc)));
    end;
  end;
  Result := DefSubclassProc(hwnd, uMsg, wParam, lParam);
end;

{ ==================== the link ==================== }

constructor TTyAccessibleLink.Create(AControl: TWinControl);
var a: TTyMsaaAnchor;
begin
  inherited Create;
  FControl := AControl;
  a := TTyMsaaAnchor.Create;
  a.Control := AControl;
  FAnchor := a;
  FAnchorRef := a;
end;

destructor TTyAccessibleLink.Destroy;
begin
  Detach;
  TTyMsaaAnchor(FAnchor).Control := nil;
  FAnchorRef := nil;
  inherited Destroy;
end;

procedure TTyAccessibleLink.Attach;
var a: TTyMsaaAnchor;
begin
  a := TTyMsaaAnchor(FAnchor);
  if a.Hooked or (FControl = nil) or not FControl.HandleAllocated then Exit;
  if SetWindowSubclass(FControl.Handle, @MsaaSubclassProc, cSubclassId,
    DWORD_PTR(Pointer(a))) then
  begin
    a.Hooked := True;
    a.HookedWnd := FControl.Handle;
  end;
end;

procedure TTyAccessibleLink.Detach;
var a: TTyMsaaAnchor;
begin
  a := TTyMsaaAnchor(FAnchor);
  if not a.Hooked then Exit;
  RemoveWindowSubclass(a.HookedWnd, @MsaaSubclassProc, cSubclassId);
  a.Hooked := False;
  a.HookedWnd := 0;
  a.Used := False;
end;

function TTyAccessibleLink.InUse: Boolean;
begin
  Result := TTyMsaaAnchor(FAnchor).Hooked and TTyMsaaAnchor(FAnchor).Used;
end;

procedure TTyAccessibleLink.NotifyFocus(AObj: TLazAccessibleObject);
var id: Integer;
begin
  if not InUse then Exit;
  id := TyAccChildSelf;
  if AObj <> nil then
  begin
    id := TyAccPreorderIndex(FControl.GetAccessibleObject, AObj);
    if id < 0 then Exit;
    id := -(id + 1);
  end;
  TyNotifyWinEvent(TyAccEventFocus, TTyMsaaAnchor(FAnchor).HookedWnd, TyAccObjIdClient, id);
end;

procedure TTyAccessibleLink.NotifyReorder;
begin
  if not InUse then Exit;
  TyNotifyWinEvent(TyAccEventReorder, TTyMsaaAnchor(FAnchor).HookedWnd,
    TyAccObjIdClient, TyAccChildSelf);
end;

function TTyAccessibleLink.Root: IUnknown;
var acc: IAccessible;
begin
  acc := TTyMsaaNode.Create(TTyMsaaAnchor(FAnchor), nil);
  Result := acc;
end;

{$ELSE}

{ ==================== elsewhere: inert ==================== }

constructor TTyAccessibleLink.Create(AControl: TWinControl);
begin
  inherited Create;
  FControl := AControl;
end;

destructor TTyAccessibleLink.Destroy;
begin
  inherited Destroy;
end;

procedure TTyAccessibleLink.Attach;
begin
end;

procedure TTyAccessibleLink.Detach;
begin
end;

function TTyAccessibleLink.InUse: Boolean;
begin
  Result := False;
end;

procedure TTyAccessibleLink.NotifyFocus(AObj: TLazAccessibleObject);
begin
end;

procedure TTyAccessibleLink.NotifyReorder;
begin
end;

function TTyAccessibleLink.Root: IUnknown;
begin
  Result := nil;
end;

{$ENDIF}

end.
