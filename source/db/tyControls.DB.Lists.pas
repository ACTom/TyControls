unit tyControls.DB.Lists;
{$mode objfpc}{$H+}
{ The data-aware lists (issue #34): TTyDBComboBox, TTyDBListBox, TTyDBLookupComboBox and
  TTyDBLookupListBox -- LCL's TDBComboBox, TDBListBox, TDBLookupComboBox and TDBLookupListBox on
  the library's own controls. Split as the rest of the library is; the lookup controls derive
  from the data-aware combo box and list box, as LCL's do, and use LCL's TDBLookup for the list
  they show.

  THE COMBO BOX AND THE LIST BOX hold a text value: they show Field.Text (selecting the item
  that has it) and write their text back with Field.Text. A change the user makes -- picking an
  item, typing in an editable combo box -- puts the dataset in dsEdit and marks the link
  modified; it is written on Enter, on EditingDone, when the control (or the combo box's
  editable field) loses focus, or by a Post made elsewhere. Escape takes it back: in the combo
  box, the whole record is cancelled when this control put it in dsEdit (LCL's EditingSource
  rule), otherwise the control goes back to the field. The combo box's own ReadOnly only
  reaches its editable field; with csDropDownList a pick from the list is undone instead, as
  any change is when the dataset cannot be edited. Setting the combo box's ItemIndex or Text
  from code is an edit too (as setting a TTyDBEdit's Text is); the list box's ItemIndex from
  code is not -- it tells a user's selection from its own.

  THE LOOKUP CONTROLS show the ListField of the ListSource rows and write the KeyField of the
  picked row into DataField -- or, for a lookup field (fkLookup), use the field's own
  definition and write its key fields. A pick is written into the record at once, as LCL's
  lookup controls write it. NullValueKey (a shortcut, 0 = none) clears the field. KeyValue is
  the selected row's key; setting it selects a row without editing the field -- it is for a
  lookup control used as a plain list, with no DataSource. EmptyValue / DisplayEmpty put a
  first row that stands for EmptyValue. The default Style of the lookup combo box is the
  library's csDropDownList (LCL's is csDropDown): a lookup can only hold a value of the list. }
interface

uses
  Classes, SysUtils, Controls, LCLType, LMessages, Variants, DB, DBCtrls,
  tyControls.ComboBox, tyControls.ListBox, tyControls.DB.Common;

type
  { A combo box bound to a text field (Field.Text in, Text out). }
  TTyCustomDBComboBox = class(TTyCustomComboBox)
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
    { Show AText, selecting the item that has it, as a load (not the user's change). }
    procedure ShowText(const AText: string);
    procedure CommitEdit;
    { Escape, from the combo box or its editable field: True when there was an edit to take back. }
    function UndoEdit: Boolean;
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DataChange(Sender: TObject); virtual;
    procedure UpdateData(Sender: TObject); virtual;
    { The base control's one change notification: a pick, a key, typing in the field -- and
      code setting ItemIndex or Text. Ignored while the field is loaded and while the control
      itself is read from a form. }
    procedure Change; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { With an editable field, the keys go to that child edit; Escape and Enter come on to the
      combo box here once the field is done with them. }
    function ChildKey(var Message: TLMKey): Boolean; override;
    { The editable field lost the focus. }
    procedure DoEditorCommit; override;
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
    { The editable field's read-only switch, and the link's: either keeps the field as it is. }
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    property ItemIndex stored False;
    property Text stored False;
  end;

  { TTyDBComboBox publishes TTyCustomDBComboBox's properties; everything lives in TTyCustomDBComboBox. }
  TTyDBComboBox = class(TTyCustomDBComboBox)
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
    property Items;
    property ItemIndex;
    property Text;
    property DropDownCount;
    property Sorted;
    property MaxLength;
    property CharCase;
    property Style;
    property ItemHeight;
    property ItemWidth;
    property TextHint;
    property ReadOnly;
    property OnDrawItem;
    property OnMeasureItem;
    property OnChange;
    property OnSelect;
    property OnDropDown;
    property OnCloseUp;
    property OnGetItems;
    property Align;
    property Anchors;
    property DataField;
    property DataSource;
  end;

  { A list box bound to a text field: the item whose text is Field.Text is selected; the
    user's selection is written with Field.Text. Single selection only. }
  TTyCustomDBListBox = class(TTyCustomListBox)
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
    { Select AIndex as a load: not the user's selection, and not reported as one. }
    procedure ShowIndex(AIndex: Integer);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DataChange(Sender: TObject); virtual;
    procedure UpdateData(Sender: TObject); virtual;
    { AUser (the selection moved under the mouse or a key) is an edit; code is not. }
    procedure DoSelectionChange(AUser: Boolean); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
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
    property ItemIndex stored False;
  end;

  { TTyDBListBox publishes TTyCustomDBListBox's properties; everything lives in TTyCustomDBListBox. }
  TTyDBListBox = class(TTyCustomDBListBox)
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
    property Items;
    property ItemIndex;
    property MultiSelect;
    property ExtendedSelect;
    property Sorted;
    property ItemHeight;
    property ScrollWidth;
    property ScrollBarAutoHide;
    property TopIndex;
    property OnChange;
    property OnSelectionChange;
    property Align;
    property Anchors;
    property DataField;
    property DataSource;
    property ReadOnly;
  end;

  { A combo box that picks a row of ListSource: it shows the row's ListField and writes its
    KeyField into DataField. }
  TTyCustomDBLookupComboBox = class(TTyCustomDBComboBox)
  private
    FLookup: TDBLookup;
    { The field the list was last built for: a new DataField builds it again. }
    FLookupField: TField;
    function GetKeyField: string;
    function GetListField: string;
    function GetListFieldIndex: Integer;
    function GetListSource: TDataSource;
    function GetLookupCache: Boolean;
    function GetNullValueKey: TShortCut;
    function GetEmptyValue: string;
    function GetDisplayEmpty: string;
    function GetScrollListDataset: Boolean;
    function GetKeyValue: Variant;
    procedure SetKeyField(const AValue: string);
    procedure SetListField(const AValue: string);
    procedure SetListFieldIndex(AValue: Integer);
    procedure SetListSource(AValue: TDataSource);
    procedure SetLookupCache(AValue: Boolean);
    procedure SetNullValueKey(AValue: TShortCut);
    procedure SetEmptyValue(const AValue: string);
    procedure SetDisplayEmpty(const AValue: string);
    procedure SetScrollListDataset(AValue: Boolean);
    procedure SetKeyValue(const AValue: Variant);
    { Build the list from ListSource (or the lookup field) and select the field's row. }
    procedure UpdateLookup;
  protected
    function GetStyleTypeKey: string; override;
    procedure DataChange(Sender: TObject); override;
    procedure UpdateData(Sender: TObject); override;
    { A pick from the list is written into the record at once. }
    procedure Change; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    property KeyValue: Variant read GetKeyValue write SetKeyValue;
    property KeyField: string read GetKeyField write SetKeyField;
    property ListField: string read GetListField write SetListField;
    property ListFieldIndex: Integer read GetListFieldIndex write SetListFieldIndex default 0;
    property ListSource: TDataSource read GetListSource write SetListSource;
    property LookupCache: Boolean read GetLookupCache write SetLookupCache default False;
    property NullValueKey: TShortCut read GetNullValueKey write SetNullValueKey default 0;
    property EmptyValue: string read GetEmptyValue write SetEmptyValue;
    property DisplayEmpty: string read GetDisplayEmpty write SetDisplayEmpty;
    property ScrollListDataset: Boolean read GetScrollListDataset write SetScrollListDataset default False;
    { The rows come from ListSource, not from the form file. }
    property Items stored False;
  end;

  { TTyDBLookupComboBox publishes TTyCustomDBLookupComboBox's properties; everything lives in TTyCustomDBLookupComboBox. }
  TTyDBLookupComboBox = class(TTyCustomDBLookupComboBox)
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
    property Items;
    property ItemIndex;
    property Text;
    property DropDownCount;
    property Sorted;
    property MaxLength;
    property CharCase;
    property Style;
    property ItemHeight;
    property ItemWidth;
    property TextHint;
    property ReadOnly;
    property OnDrawItem;
    property OnMeasureItem;
    property OnChange;
    property OnSelect;
    property OnDropDown;
    property OnCloseUp;
    property OnGetItems;
    property Align;
    property Anchors;
    property DataField;
    property DataSource;
    property KeyField;
    property ListField;
    property ListFieldIndex;
    property ListSource;
    property LookupCache;
    property NullValueKey;
    property EmptyValue;
    property DisplayEmpty;
    property ScrollListDataset;
  end;

  { A list box that picks a row of ListSource: TTyDBLookupComboBox's mapping as a list. }
  TTyCustomDBLookupListBox = class(TTyCustomDBListBox)
  private
    FLookup: TDBLookup;
    FLookupField: TField;
    function GetKeyField: string;
    function GetListField: string;
    function GetListFieldIndex: Integer;
    function GetListSource: TDataSource;
    function GetLookupCache: Boolean;
    function GetNullValueKey: TShortCut;
    function GetEmptyValue: string;
    function GetDisplayEmpty: string;
    function GetScrollListDataset: Boolean;
    function GetKeyValue: Variant;
    procedure SetKeyField(const AValue: string);
    procedure SetListField(const AValue: string);
    procedure SetListFieldIndex(AValue: Integer);
    procedure SetListSource(AValue: TDataSource);
    procedure SetLookupCache(AValue: Boolean);
    procedure SetNullValueKey(AValue: TShortCut);
    procedure SetEmptyValue(const AValue: string);
    procedure SetDisplayEmpty(const AValue: string);
    procedure SetScrollListDataset(AValue: Boolean);
    procedure SetKeyValue(const AValue: Variant);
    procedure UpdateLookup;
  protected
    function GetStyleTypeKey: string; override;
    procedure DataChange(Sender: TObject); override;
    procedure UpdateData(Sender: TObject); override;
    { The user's pick is written into the record at once. }
    procedure DoSelectionChange(AUser: Boolean); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    property KeyValue: Variant read GetKeyValue write SetKeyValue;
    property KeyField: string read GetKeyField write SetKeyField;
    property ListField: string read GetListField write SetListField;
    property ListFieldIndex: Integer read GetListFieldIndex write SetListFieldIndex default 0;
    property ListSource: TDataSource read GetListSource write SetListSource;
    property LookupCache: Boolean read GetLookupCache write SetLookupCache default False;
    property NullValueKey: TShortCut read GetNullValueKey write SetNullValueKey default 0;
    property EmptyValue: string read GetEmptyValue write SetEmptyValue;
    property DisplayEmpty: string read GetDisplayEmpty write SetDisplayEmpty;
    property ScrollListDataset: Boolean read GetScrollListDataset write SetScrollListDataset default False;
    property Items stored False;
  end;

  { TTyDBLookupListBox publishes TTyCustomDBLookupListBox's properties; everything lives in TTyCustomDBLookupListBox. }
  TTyDBLookupListBox = class(TTyCustomDBLookupListBox)
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
    property Items;
    property ItemIndex;
    property MultiSelect;
    property ExtendedSelect;
    property Sorted;
    property ItemHeight;
    property ScrollWidth;
    property ScrollBarAutoHide;
    property TopIndex;
    property OnChange;
    property OnSelectionChange;
    property Align;
    property Anchors;
    property DataField;
    property DataSource;
    property KeyField;
    property ListField;
    property ListFieldIndex;
    property ListSource;
    property LookupCache;
    property NullValueKey;
    property EmptyValue;
    property DisplayEmpty;
    property ReadOnly;
    property ScrollListDataset;
  end;

implementation

uses
  tyControls.StyleModel;

{ NullValueKey: AKey with AShift is the shortcut. Clears the field (for a lookup field, its key
  fields) when editing can begin -- what LCL's TDBLookup.HandleNullKey does, which it keeps
  private. Unbound, it only drops the selection; that part is the caller's. Returns True when
  the key was the shortcut. }
function NullKeyPressed(ALink: TFieldDataLink; ANullKey: TShortCut; AKey: Word;
  AShift: TShiftState; var AInUserEdit: Boolean): Boolean;
var
  fields: TList;
  i: Integer;
  started: Boolean;
begin
  Result := (ANullKey <> 0) and (KeyToShortCut(AKey, AShift) = ANullKey);
  if not Result or (ALink.Field = nil) then Exit;
  AInUserEdit := True;
  try
    started := ALink.Edit;
  finally
    AInUserEdit := False;
  end;
  if not started then Exit;
  if ALink.Field.FieldKind = fkLookup then
  begin
    fields := TList.Create;
    try
      ALink.DataSet.GetFieldList(fields, ALink.Field.KeyFields);
      for i := 0 to fields.Count - 1 do
        TField(fields[i]).Clear;
    finally
      fields.Free;
    end;
  end
  else
    ALink.Field.Clear;
end;

{ ================================================================== TTyCustomDBComboBox == }

constructor TTyCustomDBComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
end;

destructor TTyCustomDBComboBox.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBComboBox.GetStyleTypeKey: string;
begin
  Result := 'TyDBComboBox';
end;

function TTyCustomDBComboBox.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBComboBox.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBComboBox.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBComboBox.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBComboBox.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBComboBox.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBComboBox.SetReadOnly(AValue: Boolean);
begin
  TTyCustomComboBox(Self).ReadOnly := AValue;   // the editable field refuses typing...
  FDataLink.ReadOnly := AValue;                 // ...and the link refuses to start editing
end;

procedure TTyCustomDBComboBox.ShowText(const AText: string);
var
  was: Boolean;
  i: Integer;
begin
  was := FLoading;
  FLoading := True;
  try
    { Through Text first: setting ItemIndex alone does not reach an editable field's text. }
    ItemIndex := -1;
    Text := AText;
    i := Items.IndexOf(AText);
    if i >= 0 then ItemIndex := i;   // -1 would empty the text again
    FLoaded := TyDBLoadedText(Text);
  finally
    FLoading := was;
  end;
end;

procedure TTyCustomDBComboBox.DataChange(Sender: TObject);
begin
  if FInUserEdit then Exit;
  if FDataLink.Field = nil then ShowText('') else ShowText(FDataLink.Field.Text);
end;

procedure TTyCustomDBComboBox.UpdateData(Sender: TObject);
begin
  FDataLink.Field.Text := Text;
  FLoaded := TyDBLoadedText(Text);   // what the field holds now: changing back is an edit again
end;

procedure TTyCustomDBComboBox.Change;
begin
  inherited Change;
  if FLoading or FInUserEdit or (csLoading in ComponentState) or (FDataLink = nil)
    or (FDataLink.Field = nil) then Exit;
  if Text = FLoaded.Text then Exit;
  TyDBUserChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBComboBox.CommitEdit;
begin
  if (FDataLink <> nil) and FDataLink.Editing and not (csDestroying in ComponentState) then
    FDataLink.UpdateRecord;
end;

function TTyCustomDBComboBox.UndoEdit: Boolean;
begin
  Result := (FDataLink <> nil) and FDataLink.Editing;
  if not Result then Exit;
  if FDataLink.EditingSource then
    FDataLink.DataSet.Cancel   // this control put the record in dsEdit: the whole edit goes
  else
    FDataLink.Reset;
  SelectAll;
end;

procedure TTyCustomDBComboBox.KeyDown(var Key: Word; Shift: TShiftState);
var
  wasReturn: Boolean;
begin
  wasReturn := (Key = VK_RETURN) and (Shift = []);
  inherited KeyDown(Key, Shift);   // an open list takes Escape first, to close
  if (Key = VK_ESCAPE) and UndoEdit then
    Key := 0
  else if wasReturn then
    CommitEdit;
end;

function TTyCustomDBComboBox.ChildKey(var Message: TLMKey): Boolean;
begin
  case Message.CharCode of
    VK_ESCAPE:
      if UndoEdit then
      begin
        Message.CharCode := 0;
        Exit(True);
      end;
    VK_RETURN:
      CommitEdit;
  end;
  Result := inherited ChildKey(Message);
end;

procedure TTyCustomDBComboBox.DoEditorCommit;
begin
  inherited DoEditorCommit;
  CommitEdit;
end;

procedure TTyCustomDBComboBox.DoExit;
begin
  inherited DoExit;
  CommitEdit;
end;

procedure TTyCustomDBComboBox.EditingDone;
begin
  CommitEdit;
  inherited EditingDone;
end;

procedure TTyCustomDBComboBox.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBComboBox.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

function TTyCustomDBComboBox.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBComboBox.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ =================================================================== TTyCustomDBListBox == }

constructor TTyCustomDBListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
end;

destructor TTyCustomDBListBox.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBListBox.GetStyleTypeKey: string;
begin
  Result := 'TyDBListBox';
end;

function TTyCustomDBListBox.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBListBox.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBListBox.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBListBox.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBListBox.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBListBox.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBListBox.SetReadOnly(AValue: Boolean);
begin
  FDataLink.ReadOnly := AValue;
end;

procedure TTyCustomDBListBox.ShowIndex(AIndex: Integer);
var
  was: Boolean;
begin
  was := FLoading;
  FLoading := True;
  LockSelectionChange;   // OnSelectionChange reports it as the program's, not the user's
  try
    ItemIndex := AIndex;
    FLoaded := TyDBLoadedIndex(ItemIndex);
  finally
    UnlockSelectionChange;
    FLoading := was;
  end;
end;

procedure TTyCustomDBListBox.DataChange(Sender: TObject);
begin
  if FInUserEdit then Exit;
  if FDataLink.Field = nil then ShowIndex(-1) else ShowIndex(Items.IndexOf(FDataLink.Field.Text));
end;

procedure TTyCustomDBListBox.UpdateData(Sender: TObject);
begin
  if ItemIndex >= 0 then
    FDataLink.Field.Text := Items[ItemIndex];
  FLoaded := TyDBLoadedIndex(ItemIndex);
end;

procedure TTyCustomDBListBox.DoSelectionChange(AUser: Boolean);
begin
  inherited DoSelectionChange(AUser);
  if not AUser or FLoading or FInUserEdit or (FDataLink = nil) or (FDataLink.Field = nil) then
    Exit;
  if ItemIndex = FLoaded.Index then Exit;
  TyDBUserChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBListBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and FDataLink.Editing then
  begin
    FDataLink.Reset;
    Key := 0;
  end
  else if (Key = VK_RETURN) and (Shift = []) and FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBListBox.DoExit;
begin
  inherited DoExit;
  if (FDataLink <> nil) and FDataLink.Editing and not (csDestroying in ComponentState) then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBListBox.EditingDone;
begin
  if (FDataLink <> nil) and FDataLink.Editing then
    FDataLink.UpdateRecord;
  inherited EditingDone;
end;

procedure TTyCustomDBListBox.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBListBox.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

function TTyCustomDBListBox.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBListBox.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ============================================================ TTyCustomDBLookupComboBox == }

constructor TTyCustomDBLookupComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLookup := TDBLookup.Create(Self);
end;

function TTyCustomDBLookupComboBox.GetStyleTypeKey: string;
begin
  Result := 'TyDBLookupComboBox';
end;

function TTyCustomDBLookupComboBox.GetKeyField: string;
begin
  Result := FLookup.KeyField;
end;

function TTyCustomDBLookupComboBox.GetListField: string;
begin
  Result := FLookup.ListField;
end;

function TTyCustomDBLookupComboBox.GetListFieldIndex: Integer;
begin
  Result := FLookup.ListFieldIndex;
end;

function TTyCustomDBLookupComboBox.GetListSource: TDataSource;
begin
  Result := FLookup.ListSource;
end;

function TTyCustomDBLookupComboBox.GetLookupCache: Boolean;
begin
  Result := FLookup.LookupCache;
end;

function TTyCustomDBLookupComboBox.GetNullValueKey: TShortCut;
begin
  Result := FLookup.NullValueKey;
end;

function TTyCustomDBLookupComboBox.GetEmptyValue: string;
begin
  Result := FLookup.EmptyValue;
end;

function TTyCustomDBLookupComboBox.GetDisplayEmpty: string;
begin
  Result := FLookup.DisplayEmpty;
end;

function TTyCustomDBLookupComboBox.GetScrollListDataset: Boolean;
begin
  Result := FLookup.ScrollListDataset;
end;

function TTyCustomDBLookupComboBox.GetKeyValue: Variant;
begin
  Result := FLookup.GetKeyValue(ItemIndex);
end;

procedure TTyCustomDBLookupComboBox.SetKeyField(const AValue: string);
begin
  FLookup.KeyField := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupComboBox.SetListField(const AValue: string);
begin
  FLookup.ListField := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupComboBox.SetListFieldIndex(AValue: Integer);
begin
  FLookup.ListFieldIndex := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupComboBox.SetListSource(AValue: TDataSource);
begin
  FLookup.ListSource := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupComboBox.SetLookupCache(AValue: Boolean);
begin
  FLookup.LookupCache := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupComboBox.SetNullValueKey(AValue: TShortCut);
begin
  FLookup.NullValueKey := AValue;
end;

procedure TTyCustomDBLookupComboBox.SetEmptyValue(const AValue: string);
begin
  FLookup.EmptyValue := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupComboBox.SetDisplayEmpty(const AValue: string);
begin
  FLookup.DisplayEmpty := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupComboBox.SetScrollListDataset(AValue: Boolean);
begin
  FLookup.ScrollListDataset := AValue;
end;

procedure TTyCustomDBLookupComboBox.SetKeyValue(const AValue: Variant);
var
  was: Boolean;
begin
  was := FLoading;
  FLoading := True;   // a selection, not an edit of the field
  try
    ItemIndex := FLookup.GetKeyIndex(AValue);
  finally
    FLoading := was;
  end;
end;

procedure TTyCustomDBLookupComboBox.UpdateLookup;
begin
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  FLookup.Initialize(FDataLink, Items);
  FLookupField := FDataLink.Field;
  DataChange(Self);
end;

procedure TTyCustomDBLookupComboBox.DataChange(Sender: TObject);
var
  was: Boolean;
  i: Integer;
begin
  if FInUserEdit then Exit;
  if FDataLink.Field <> FLookupField then
  begin
    UpdateLookup;   // a new field (or none): build the list for it, which loads it too
    Exit;
  end;
  was := FLoading;
  FLoading := True;
  try
    i := FLookup.GetKeyIndex;
    { Through Text, as ShowText does, so an editable field shows the row too; then the row
      itself, by position -- two rows may show the same text. }
    ItemIndex := -1;
    if i >= 0 then Text := Items[i] else Text := '';
    ItemIndex := i;
    FLoaded := TyDBLoadedText(Text);
  finally
    FLoading := was;
  end;
end;

procedure TTyCustomDBLookupComboBox.UpdateData(Sender: TObject);
var
  was: Boolean;
begin
  if TyComboStyleHasEditBox(Style) then
  begin
    was := FLoading;
    FLoading := True;
    try
      ItemIndex := Items.IndexOf(Text);   // the typed text names a row, or none
    finally
      FLoading := was;
    end;
  end;
  { A text that names no row writes nothing (LCL cancels the record there, from inside the
    write); the field is shown again. }
  if ItemIndex >= 0 then
    FLookup.UpdateData(ItemIndex)
  else
    DataChange(Self);
  FLoaded := TyDBLoadedText(Text);
end;

procedure TTyCustomDBLookupComboBox.Change;
begin
  inherited Change;
  if FLoading or FInUserEdit or TyComboStyleHasEditBox(Style) or (FDataLink = nil) then Exit;
  if FDataLink.Editing then FDataLink.UpdateRecord;
end;

procedure TTyCustomDBLookupComboBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if NullKeyPressed(FDataLink, NullValueKey, Key, Shift, FInUserEdit) then
  begin
    if FDataLink.Field = nil then SetKeyValue(Null);   // a plain list: drop the selection
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TTyCustomDBLookupComboBox.Loaded;
begin
  inherited Loaded;
  UpdateLookup;
end;

{ ============================================================= TTyCustomDBLookupListBox == }

constructor TTyCustomDBLookupListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLookup := TDBLookup.Create(Self);
end;

function TTyCustomDBLookupListBox.GetStyleTypeKey: string;
begin
  Result := 'TyDBLookupListBox';
end;

function TTyCustomDBLookupListBox.GetKeyField: string;
begin
  Result := FLookup.KeyField;
end;

function TTyCustomDBLookupListBox.GetListField: string;
begin
  Result := FLookup.ListField;
end;

function TTyCustomDBLookupListBox.GetListFieldIndex: Integer;
begin
  Result := FLookup.ListFieldIndex;
end;

function TTyCustomDBLookupListBox.GetListSource: TDataSource;
begin
  Result := FLookup.ListSource;
end;

function TTyCustomDBLookupListBox.GetLookupCache: Boolean;
begin
  Result := FLookup.LookupCache;
end;

function TTyCustomDBLookupListBox.GetNullValueKey: TShortCut;
begin
  Result := FLookup.NullValueKey;
end;

function TTyCustomDBLookupListBox.GetEmptyValue: string;
begin
  Result := FLookup.EmptyValue;
end;

function TTyCustomDBLookupListBox.GetDisplayEmpty: string;
begin
  Result := FLookup.DisplayEmpty;
end;

function TTyCustomDBLookupListBox.GetScrollListDataset: Boolean;
begin
  Result := FLookup.ScrollListDataset;
end;

function TTyCustomDBLookupListBox.GetKeyValue: Variant;
begin
  Result := FLookup.GetKeyValue(ItemIndex);
end;

procedure TTyCustomDBLookupListBox.SetKeyField(const AValue: string);
begin
  FLookup.KeyField := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupListBox.SetListField(const AValue: string);
begin
  FLookup.ListField := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupListBox.SetListFieldIndex(AValue: Integer);
begin
  FLookup.ListFieldIndex := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupListBox.SetListSource(AValue: TDataSource);
begin
  FLookup.ListSource := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupListBox.SetLookupCache(AValue: Boolean);
begin
  FLookup.LookupCache := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupListBox.SetNullValueKey(AValue: TShortCut);
begin
  FLookup.NullValueKey := AValue;
end;

procedure TTyCustomDBLookupListBox.SetEmptyValue(const AValue: string);
begin
  FLookup.EmptyValue := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupListBox.SetDisplayEmpty(const AValue: string);
begin
  FLookup.DisplayEmpty := AValue;
  UpdateLookup;
end;

procedure TTyCustomDBLookupListBox.SetScrollListDataset(AValue: Boolean);
begin
  FLookup.ScrollListDataset := AValue;
end;

procedure TTyCustomDBLookupListBox.SetKeyValue(const AValue: Variant);
begin
  ShowIndex(FLookup.GetKeyIndex(AValue));   // a selection, not an edit of the field
end;

procedure TTyCustomDBLookupListBox.UpdateLookup;
begin
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  FLookup.Initialize(FDataLink, Items);
  FLookupField := FDataLink.Field;
  DataChange(Self);
end;

procedure TTyCustomDBLookupListBox.DataChange(Sender: TObject);
begin
  if FInUserEdit then Exit;
  if FDataLink.Field <> FLookupField then
  begin
    UpdateLookup;
    Exit;
  end;
  ShowIndex(FLookup.GetKeyIndex);
end;

procedure TTyCustomDBLookupListBox.UpdateData(Sender: TObject);
begin
  if ItemIndex >= 0 then FLookup.UpdateData(ItemIndex);
  FLoaded := TyDBLoadedIndex(ItemIndex);
end;

procedure TTyCustomDBLookupListBox.DoSelectionChange(AUser: Boolean);
begin
  inherited DoSelectionChange(AUser);
  if AUser and not FLoading and (FDataLink <> nil) and FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBLookupListBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if NullKeyPressed(FDataLink, NullValueKey, Key, Shift, FInUserEdit) then
  begin
    if FDataLink.Field = nil then ShowIndex(-1);   // a plain list: drop the selection
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TTyCustomDBLookupListBox.Loaded;
begin
  inherited Loaded;
  UpdateLookup;
end;

initialization
  { Each key falls back to its base control's (plan D8); the lookups to the data-aware ones
    they derive from, so a rule written for TyDBComboBox reaches the lookup combo box too. }
  TyTryRegisterTypeKeyParent('TyDBComboBox', 'TyComboBox');
  TyTryRegisterTypeKeyParent('TyDBLookupComboBox', 'TyDBComboBox');
  TyTryRegisterTypeKeyParent('TyDBListBox', 'TyListBox');
  TyTryRegisterTypeKeyParent('TyDBLookupListBox', 'TyDBListBox');

finalization
  TyUnregisterTypeKeyParent('TyDBComboBox');
  TyUnregisterTypeKeyParent('TyDBLookupComboBox');
  TyUnregisterTypeKeyParent('TyDBListBox');
  TyUnregisterTypeKeyParent('TyDBLookupListBox');

end.
