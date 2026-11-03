unit tyControls.DB.Choices;
{$mode objfpc}{$H+}
{ The data-aware choices (issue #34): TTyDBCheckBox and TTyDBRadioGroup are LCL's TDBCheckBox
  and TDBRadioGroup on the library's own controls; TTyDBToggleSwitch, TTyDBSegmented and
  TTyDBRating have no LCL counterpart. Split as the rest of the library is: TTyCustomDBXxx
  holds the data link and the code, TTyDBXxx publishes the base control's list unchanged and
  the data properties after it, in the order LCL's counterpart publishes them.

  A CHOICE IS WRITTEN AS IT IS MADE. A click (or key) that changes the value puts the dataset
  in dsEdit, marks the link modified and writes the value into the record at once
  (TyDBChoiceChanged), as LCL's TDBCheckBox does: there is no half-made choice to wait for, and
  in a radio group the control the user clicked is a child button, which is not the one that
  later gets EditingDone. Escape therefore has nothing to take back; the record's own Cancel
  does.

  WHEN THE DATASET CANNOT BE EDITED. The check box and the switch ask before they flip and do
  not flip at all -- no OnChange, no OnClick -- when the answer is no. The rating has a
  ReadOnly of its own and is made read-only while the field cannot be changed (as LCL's
  TDBDateTimePicker is). The radio group and the segmented control have neither, so a change
  the dataset refuses is undone: the control goes back to the field.

  CODE. Setting the value from code -- State, Checked, ItemIndex, Value -- is an edit as a click
  is (#184), as on LCL's TDBCheckBox and TDBRadioGroup: every change of the value goes through
  one virtual of the base control (ChangeState, ChangeChecked, ChangeItemIndex, ChangeValue,
  SelectionChanged), which tells a click from code no more than LCL's DoOnChange does, and is
  refused the same way. Only DataChange's own load (FLoading) writes nothing back.

  NULL (plan D5): the check box shows cbGrayed, and writes NULL when AllowGrayed lets the user
  click to the grayed state; the switch shows off; the radio group and the segmented control
  select nothing (ItemIndex -1), which the user cannot pick back; the rating shows no stars,
  and clearing it to none writes NULL -- or 0 when the field is Required. }
interface

uses
  Classes, SysUtils, Controls, StdCtrls, LCLType, LMessages, DB, DBCtrls,
  tyControls.CheckBox, tyControls.ToggleSwitch, tyControls.RadioGroup, tyControls.Segmented,
  tyControls.Rating, tyControls.DB.Common;

type
  { A check box bound to a field. A boolean field is read and written with AsBoolean; any other
    field compares its text with ValueChecked and ValueUnchecked -- each a list of words
    separated by ';', matched without regard to case -- and writes the first word of the one
    that applies. NULL, or a text in neither list, shows cbGrayed. }
  TTyCustomDBCheckBox = class(TTyCustomCheckBox)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FValueChecked: string;
    FValueUnchecked: string;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    procedure SetValueChecked(const AValue: string);
    procedure SetValueUnchecked(const AValue: string);
    function ValueCheckedStored: Boolean;
    function ValueUncheckedStored: Boolean;
    { The state the field stands for (LCL's GetFieldCheckState). }
    function FieldState: TCheckBoxState;
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { Every change of State but a load from the field -- a click, Space, the accelerator, code
      -- is an edit, asked for before the box flips. }
    procedure ChangeState(AValue: TCheckBoxState); override;
    property Checked stored False;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    { Default BoolToStr(True) / BoolToStr(False), '-1' / '0', as in LCL. }
    property ValueChecked: string read FValueChecked write SetValueChecked stored ValueCheckedStored;
    property ValueUnchecked: string read FValueUnchecked write SetValueUnchecked stored ValueUncheckedStored;
    property State stored False;
  end;

  { TTyDBCheckBox publishes TTyCustomDBCheckBox's properties; everything lives in TTyCustomDBCheckBox. }
  TTyDBCheckBox = class(TTyCustomDBCheckBox)
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
    property State;
    property AllowGrayed;
    property Checked;
    property Alignment;
    property Caption;
    property Align;
    property Anchors;
    property OnChange;
    property DataField;
    property DataSource;
    property ReadOnly;
    property ValueChecked;
    property ValueUnchecked;
  end;

  { A switch bound to a field: TTyDBCheckBox's mapping without the grayed state. NULL, or a text
    in neither list, shows off. A click, Space and Checked set from code all toggle it, and all
    ask first. }
  TTyCustomDBToggleSwitch = class(TTyCustomToggleSwitch)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FValueChecked: string;
    FValueUnchecked: string;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    procedure SetValueChecked(const AValue: string);
    procedure SetValueUnchecked(const AValue: string);
    function ValueCheckedStored: Boolean;
    function ValueUncheckedStored: Boolean;
    function FieldChecked: Boolean;
    { May the user flip the switch now? Unbound, always; bound, when the dataset is (or can be
      put) in dsEdit -- asked BEFORE the switch moves. }
    function FlipAllowed: Boolean;
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { A Space the dataset would refuse is dropped before it arms the key-up toggle. }
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { Every change of Checked but a load from the field is an edit, asked for before the switch
      flips. }
    procedure ChangeChecked(AValue: Boolean); override;
    property Checked stored False;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Refused before the switch flips, so that no OnClick fires either. }
    procedure Click; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    property ValueChecked: string read FValueChecked write SetValueChecked stored ValueCheckedStored;
    property ValueUnchecked: string read FValueUnchecked write SetValueUnchecked stored ValueUncheckedStored;
  end;

  { TTyDBToggleSwitch publishes TTyCustomDBToggleSwitch's properties; everything lives in TTyCustomDBToggleSwitch. }
  TTyDBToggleSwitch = class(TTyCustomDBToggleSwitch)
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
    property Checked;
    property Caption;
    property OnChange;
    property Align;
    property Anchors;
    property DataField;
    property DataSource;
    property ReadOnly;
    property ValueChecked;
    property ValueUnchecked;
  end;

  { A radio group bound to a field. Option i stands for Values[i], or for Items[i] when that
    line of Values is empty or missing (LCL's rule); the field's Text selects the option that
    stands for it, and nothing when none does. The user's pick writes that value with
    Field.Text. Value is the selected option's value. }
  TTyCustomDBRadioGroup = class(TTyCustomRadioGroup)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FValues: TStringList;
    { The base control's own handler of an Items change, which rebuilds the buttons. }
    FBaseItemsChanged: TNotifyEvent;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    function GetValues: TStrings;
    procedure SetValues(AValue: TStrings);
    procedure ValuesChanged(Sender: TObject);
    { Items changed: the buttons are rebuilt, then the field's option selected again -- the
      base control keeps the old selection by caption, which may stand for another value now. }
    procedure FieldItemsChanged(Sender: TObject);
    function GetValue: string;
    procedure SetValue(const AValue: string);
    function IndexOfValue(const AValue: string): Integer;
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { Clicks land on the child buttons; the group hears of them here (and of code setting
      ItemIndex, which on a data-aware radio group is an edit too). }
    procedure SelectionChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    { The value option AIndex stands for; '' for -1. }
    function ButtonValue(AIndex: Integer): string;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    property Values: TStrings read GetValues write SetValues;
    { The selected option's value; setting it selects the option standing for it (none when
      no option does). }
    property Value: string read GetValue write SetValue;
    property ItemIndex stored False;
  end;

  { TTyDBRadioGroup publishes TTyCustomDBRadioGroup's properties; everything lives in TTyCustomDBRadioGroup. }
  TTyDBRadioGroup = class(TTyCustomDBRadioGroup)
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
    property Caption;
    property Alignment;
    property ClientWidth;
    property ClientHeight;
    property DockSite;
    property UseDockManager;
    property OnDockDrop;
    property OnDockOver;
    property OnUnDock;
    property OnGetSiteInfo;
    property OnGetDockCaption;
    property OnStartDock;
    property OnEndDock;
    property Align;
    property Anchors;
    property Items;
    property Columns;
    property ColumnLayout;
    property ItemIndex;
    property OnSelectionChanged;
    property OnItemEnter;
    property OnItemExit;
    property DataField;
    property DataSource;
    property ReadOnly;
    property Values;
  end;

  { A segmented control bound to a field: TTyDBRadioGroup's mapping (Values, Value) on one
    row of segments. A click, an arrow key or ItemIndex or Value set from code that moves the
    selection is an edit. }
  TTyCustomDBSegmented = class(TTyCustomSegmented)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FValues: TStringList;
    { The base control's own handler of an Items change, which keeps the selected index. }
    FBaseItemsChanged: TNotifyEvent;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    function GetValues: TStrings;
    procedure SetValues(AValue: TStrings);
    procedure ValuesChanged(Sender: TObject);
    { Items changed: the field's segment is selected again, as for a Values change. }
    procedure FieldItemsChanged(Sender: TObject);
    function GetValue: string;
    procedure SetValue(const AValue: string);
    function IndexOfValue(const AValue: string): Integer;
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { Every change of ItemIndex but a load from the field is an edit; one the dataset refuses
      is undone, the field's segment selected again. }
    procedure ChangeItemIndex(AValue: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    function ButtonValue(AIndex: Integer): string;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    property Values: TStrings read GetValues write SetValues;
    property Value: string read GetValue write SetValue;
    property ItemIndex stored False;
  end;

  { TTyDBSegmented publishes TTyCustomDBSegmented's properties; everything lives in TTyCustomDBSegmented. }
  TTyDBSegmented = class(TTyCustomDBSegmented)
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
    property OnChange;
    property Align;
    property Anchors;
    property DataField;
    property DataSource;
    property ReadOnly;
    property Values;
  end;

  { A star rating bound to a number field (AsFloat). With AllowHalf off it shows, and so
    writes, whole stars: a field's 3.5 shows as 4 (it is written back only when the rating is
    changed). No stars is NULL: a NULL field shows none, and clearing the rating to
    none writes NULL -- or 0 when the field is Required. The base control's own ReadOnly is on
    while this ReadOnly is, or while the field cannot be changed. }
  TTyCustomDBRating = class(TTyCustomRating)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    function GetAllowHalf: Boolean;
    { The base control's, then the field shown again at the new precision. }
    procedure SetAllowHalf(AValue: Boolean);
    { The base control's ReadOnly := ours, or the field cannot be changed (LCL's
      TDBDateTimePicker.CheckField does the same with CanModify), or no edit could begin --
      AutoEdit off and the record not being edited (TyDBEditCanBegin). }
    procedure SyncReadOnly;
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure LinkStateChange(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    { Every change of Value but a load from the field is an edit, asked for before the stars
      move: where the dataset cannot be edited a click finds the rating read-only, and a Value
      set from code is dropped likewise. }
    procedure ChangeValue(AValue: Double); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    property AllowHalf: Boolean read GetAllowHalf write SetAllowHalf default False;
    property Value stored False;
  end;

  { TTyDBRating publishes TTyCustomDBRating's properties; everything lives in TTyCustomDBRating. }
  TTyDBRating = class(TTyCustomDBRating)
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
    property Count;
    property Value;
    property AllowHalf;
    property ReadOnly;
    property OnChange;
    property Align;
    property Anchors;
    property DataField;
    property DataSource;
  end;

implementation

uses
  Math, tyControls.StyleModel;

{ ================================================================== TTyCustomDBCheckBox == }

constructor TTyCustomDBCheckBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FValueChecked := BoolToStr(True);
  FValueUnchecked := BoolToStr(False);
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
end;

destructor TTyCustomDBCheckBox.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBCheckBox.GetStyleTypeKey: string;
begin
  Result := 'TyDBCheckBox';
end;

function TTyCustomDBCheckBox.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBCheckBox.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBCheckBox.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBCheckBox.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBCheckBox.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBCheckBox.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBCheckBox.SetReadOnly(AValue: Boolean);
begin
  FDataLink.ReadOnly := AValue;
end;

procedure TTyCustomDBCheckBox.SetValueChecked(const AValue: string);
begin
  if FValueChecked = AValue then Exit;
  FValueChecked := AValue;
  if FDataLink.Field <> nil then DataChange(Self);
end;

procedure TTyCustomDBCheckBox.SetValueUnchecked(const AValue: string);
begin
  if FValueUnchecked = AValue then Exit;
  FValueUnchecked := AValue;
  if FDataLink.Field <> nil then DataChange(Self);
end;

function TTyCustomDBCheckBox.ValueCheckedStored: Boolean;
begin
  Result := FValueChecked <> BoolToStr(True);
end;

function TTyCustomDBCheckBox.ValueUncheckedStored: Boolean;
begin
  Result := FValueUnchecked <> BoolToStr(False);
end;

function TTyCustomDBCheckBox.FieldState: TCheckBoxState;
var
  f: TField;
begin
  f := FDataLink.Field;
  if f = nil then
    Result := cbUnchecked
  else if f.IsNull then
    Result := cbGrayed
  else if f.DataType = ftBoolean then
  begin
    if f.AsBoolean then Result := cbChecked else Result := cbUnchecked;
  end
  else if TyDBWordListHas(FValueChecked, f.AsString) then
    Result := cbChecked
  else if TyDBWordListHas(FValueUnchecked, f.AsString) then
    Result := cbUnchecked
  else
    Result := cbGrayed;
end;

procedure TTyCustomDBCheckBox.DataChange(Sender: TObject);
begin
  if FInUserEdit then Exit;   // the dataset entering dsEdit for the user's click
  FLoading := True;
  try
    State := FieldState;
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBCheckBox.UpdateData(Sender: TObject);
var
  f: TField;
begin
  f := FDataLink.Field;
  if State = cbGrayed then
    f.Clear
  else if f.DataType = ftBoolean then
    f.AsBoolean := State = cbChecked
  else if State = cbChecked then
    f.AsString := TyDBFirstWord(FValueChecked)
  else
    f.AsString := TyDBFirstWord(FValueUnchecked);
end;

procedure TTyCustomDBCheckBox.ChangeState(AValue: TCheckBoxState);
begin
  if FLoading or (FDataLink = nil) or (FDataLink.Field = nil)
    or (csLoading in ComponentState) then
  begin
    inherited ChangeState(AValue);
    Exit;
  end;
  { Refused before the box flips: no OnChange, no OnClick for a change that cannot be kept. }
  if not TyDBEditAllowed(FDataLink, FInUserEdit) then Exit;
  inherited ChangeState(AValue);
  TyDBChoiceChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBCheckBox.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBCheckBox.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

function TTyCustomDBCheckBox.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBCheckBox.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ============================================================== TTyCustomDBToggleSwitch == }

constructor TTyCustomDBToggleSwitch.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FValueChecked := BoolToStr(True);
  FValueUnchecked := BoolToStr(False);
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
end;

destructor TTyCustomDBToggleSwitch.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBToggleSwitch.GetStyleTypeKey: string;
begin
  Result := 'TyDBToggleSwitch';
end;

function TTyCustomDBToggleSwitch.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBToggleSwitch.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBToggleSwitch.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBToggleSwitch.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBToggleSwitch.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBToggleSwitch.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBToggleSwitch.SetReadOnly(AValue: Boolean);
begin
  FDataLink.ReadOnly := AValue;
end;

procedure TTyCustomDBToggleSwitch.SetValueChecked(const AValue: string);
begin
  if FValueChecked = AValue then Exit;
  FValueChecked := AValue;
  if FDataLink.Field <> nil then DataChange(Self);
end;

procedure TTyCustomDBToggleSwitch.SetValueUnchecked(const AValue: string);
begin
  if FValueUnchecked = AValue then Exit;
  FValueUnchecked := AValue;
  if FDataLink.Field <> nil then DataChange(Self);
end;

function TTyCustomDBToggleSwitch.ValueCheckedStored: Boolean;
begin
  Result := FValueChecked <> BoolToStr(True);
end;

function TTyCustomDBToggleSwitch.ValueUncheckedStored: Boolean;
begin
  Result := FValueUnchecked <> BoolToStr(False);
end;

function TTyCustomDBToggleSwitch.FieldChecked: Boolean;
var
  f: TField;
begin
  f := FDataLink.Field;
  if (f = nil) or f.IsNull then
    Result := False
  else if f.DataType = ftBoolean then
    Result := f.AsBoolean
  else
    Result := TyDBWordListHas(FValueChecked, f.AsString);
end;

function TTyCustomDBToggleSwitch.FlipAllowed: Boolean;
begin
  Result := (FDataLink.Field = nil) or TyDBEditAllowed(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBToggleSwitch.DataChange(Sender: TObject);
begin
  if FInUserEdit then Exit;
  FLoading := True;
  try
    Checked := FieldChecked;
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBToggleSwitch.UpdateData(Sender: TObject);
var
  f: TField;
begin
  f := FDataLink.Field;
  if f.DataType = ftBoolean then
    f.AsBoolean := Checked
  else if Checked then
    f.AsString := TyDBFirstWord(FValueChecked)
  else
    f.AsString := TyDBFirstWord(FValueUnchecked);
end;

procedure TTyCustomDBToggleSwitch.Click;
begin
  if not FlipAllowed then Exit;
  inherited Click;
end;

procedure TTyCustomDBToggleSwitch.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if ((Key = VK_SPACE) or (Key = VK_RETURN)) and Enabled and not FlipAllowed then
  begin
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TTyCustomDBToggleSwitch.ChangeChecked(AValue: Boolean);
begin
  if FLoading or (FDataLink = nil) or (FDataLink.Field = nil)
    or (csLoading in ComponentState) then
  begin
    inherited ChangeChecked(AValue);
    Exit;
  end;
  if not TyDBEditAllowed(FDataLink, FInUserEdit) then Exit;
  inherited ChangeChecked(AValue);
  TyDBChoiceChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBToggleSwitch.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBToggleSwitch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

function TTyCustomDBToggleSwitch.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBToggleSwitch.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ================================================================ TTyCustomDBRadioGroup == }

constructor TTyCustomDBRadioGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FValues := TStringList.Create;
  FValues.OnChange := @ValuesChanged;
  FBaseItemsChanged := TStringList(Items).OnChange;
  TStringList(Items).OnChange := @FieldItemsChanged;
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
end;

destructor TTyCustomDBRadioGroup.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  FreeAndNil(FValues);
  inherited Destroy;
end;

function TTyCustomDBRadioGroup.GetStyleTypeKey: string;
begin
  Result := 'TyDBRadioGroup';
end;

function TTyCustomDBRadioGroup.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBRadioGroup.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBRadioGroup.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBRadioGroup.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBRadioGroup.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBRadioGroup.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBRadioGroup.SetReadOnly(AValue: Boolean);
begin
  FDataLink.ReadOnly := AValue;
end;

function TTyCustomDBRadioGroup.GetValues: TStrings;
begin
  Result := FValues;
end;

procedure TTyCustomDBRadioGroup.SetValues(AValue: TStrings);
begin
  FValues.Assign(AValue);   // ValuesChanged reloads
end;

procedure TTyCustomDBRadioGroup.ValuesChanged(Sender: TObject);
begin
  if (FDataLink <> nil) and (FDataLink.Field <> nil) then DataChange(Self);
end;

procedure TTyCustomDBRadioGroup.FieldItemsChanged(Sender: TObject);
begin
  if Assigned(FBaseItemsChanged) then FBaseItemsChanged(Sender);
  ValuesChanged(Sender);
end;

function TTyCustomDBRadioGroup.ButtonValue(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then
    Result := ''
  else if (AIndex < FValues.Count) and (FValues[AIndex] <> '') then
    Result := FValues[AIndex]
  else
    Result := Items[AIndex];
end;

function TTyCustomDBRadioGroup.IndexOfValue(const AValue: string): Integer;
begin
  for Result := 0 to Items.Count - 1 do
    if ButtonValue(Result) = AValue then Exit;
  Result := -1;
end;

function TTyCustomDBRadioGroup.GetValue: string;
begin
  Result := ButtonValue(ItemIndex);
end;

procedure TTyCustomDBRadioGroup.SetValue(const AValue: string);
begin
  ItemIndex := IndexOfValue(AValue);
end;

procedure TTyCustomDBRadioGroup.DataChange(Sender: TObject);
begin
  if FInUserEdit then Exit;
  FLoading := True;
  try
    if FDataLink.Field = nil then
      ItemIndex := -1
    else
      ItemIndex := IndexOfValue(FDataLink.Field.Text);
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBRadioGroup.UpdateData(Sender: TObject);
begin
  if ItemIndex < 0 then
    FDataLink.Field.Clear
  else
    FDataLink.Field.Text := ButtonValue(ItemIndex);
end;

procedure TTyCustomDBRadioGroup.SelectionChanged;
begin
  inherited SelectionChanged;
  if FLoading or FInUserEdit or (csLoading in ComponentState) or (FDataLink = nil)
    or (FDataLink.Field = nil) then Exit;
  TyDBChoiceChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBRadioGroup.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBRadioGroup.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

function TTyCustomDBRadioGroup.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBRadioGroup.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ================================================================= TTyCustomDBSegmented == }

constructor TTyCustomDBSegmented.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FValues := TStringList.Create;
  FValues.OnChange := @ValuesChanged;
  FBaseItemsChanged := TStringList(Items).OnChange;
  TStringList(Items).OnChange := @FieldItemsChanged;
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
end;

destructor TTyCustomDBSegmented.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  FreeAndNil(FValues);
  inherited Destroy;
end;

function TTyCustomDBSegmented.GetStyleTypeKey: string;
begin
  Result := 'TyDBSegmented';
end;

function TTyCustomDBSegmented.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBSegmented.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBSegmented.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBSegmented.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBSegmented.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBSegmented.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBSegmented.SetReadOnly(AValue: Boolean);
begin
  FDataLink.ReadOnly := AValue;
end;

function TTyCustomDBSegmented.GetValues: TStrings;
begin
  Result := FValues;
end;

procedure TTyCustomDBSegmented.SetValues(AValue: TStrings);
begin
  FValues.Assign(AValue);
end;

procedure TTyCustomDBSegmented.ValuesChanged(Sender: TObject);
begin
  if (FDataLink <> nil) and (FDataLink.Field <> nil) then DataChange(Self);
end;

procedure TTyCustomDBSegmented.FieldItemsChanged(Sender: TObject);
begin
  if Assigned(FBaseItemsChanged) then FBaseItemsChanged(Sender);
  ValuesChanged(Sender);
end;

function TTyCustomDBSegmented.ButtonValue(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then
    Result := ''
  else if (AIndex < FValues.Count) and (FValues[AIndex] <> '') then
    Result := FValues[AIndex]
  else
    Result := Items[AIndex];
end;

function TTyCustomDBSegmented.IndexOfValue(const AValue: string): Integer;
begin
  for Result := 0 to Items.Count - 1 do
    if ButtonValue(Result) = AValue then Exit;
  Result := -1;
end;

function TTyCustomDBSegmented.GetValue: string;
begin
  Result := ButtonValue(ItemIndex);
end;

procedure TTyCustomDBSegmented.SetValue(const AValue: string);
begin
  ItemIndex := IndexOfValue(AValue);
end;

procedure TTyCustomDBSegmented.DataChange(Sender: TObject);
begin
  if FInUserEdit then Exit;
  FLoading := True;
  try
    if FDataLink.Field = nil then
      ItemIndex := -1
    else
      ItemIndex := IndexOfValue(FDataLink.Field.Text);
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBSegmented.UpdateData(Sender: TObject);
begin
  if ItemIndex < 0 then
    FDataLink.Field.Clear
  else
    FDataLink.Field.Text := ButtonValue(ItemIndex);
end;

procedure TTyCustomDBSegmented.ChangeItemIndex(AValue: Integer);
begin
  inherited ChangeItemIndex(AValue);
  if FLoading or FInUserEdit or (csLoading in ComponentState) or (FDataLink = nil)
    or (FDataLink.Field = nil) then Exit;
  TyDBChoiceChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBSegmented.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBSegmented.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

function TTyCustomDBSegmented.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBSegmented.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ==================================================================== TTyCustomDBRating == }

constructor TTyCustomDBRating.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
  FDataLink.OnActiveChange := @LinkStateChange;
  FDataLink.OnEditingChange := @LinkStateChange;
end;

destructor TTyCustomDBRating.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FDataLink.OnActiveChange := nil;
  FDataLink.OnEditingChange := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBRating.GetStyleTypeKey: string;
begin
  Result := 'TyDBRating';
end;

function TTyCustomDBRating.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBRating.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBRating.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBRating.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBRating.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBRating.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBRating.SetReadOnly(AValue: Boolean);
begin
  FDataLink.ReadOnly := AValue;
  SyncReadOnly;
end;

function TTyCustomDBRating.GetAllowHalf: Boolean;
begin
  Result := TTyCustomRating(Self).AllowHalf;
end;

procedure TTyCustomDBRating.SetAllowHalf(AValue: Boolean);
begin
  if AValue = AllowHalf then Exit;
  TTyCustomRating(Self).AllowHalf := AValue;
  if FDataLink.Field <> nil then DataChange(Self);
end;

procedure TTyCustomDBRating.SyncReadOnly;
begin
  TTyCustomRating(Self).ReadOnly := FDataLink.ReadOnly
    or ((FDataLink.Field <> nil) and not TyDBEditCanBegin(FDataLink));
end;

procedure TTyCustomDBRating.LinkStateChange(Sender: TObject);
begin
  SyncReadOnly;
end;

procedure TTyCustomDBRating.DataChange(Sender: TObject);
var
  v: Double;
begin
  if FInUserEdit then Exit;
  SyncReadOnly;
  if (FDataLink.Field = nil) or FDataLink.Field.IsNull then
    v := 0
  else
  begin
    v := TyDBReadNumber(FDataLink.Field);
    if not AllowHalf then v := Floor(v + 0.5);   // whole stars, half up
  end;
  FLoading := True;
  try
    Value := v;
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBRating.UpdateData(Sender: TObject);
begin
  if (Value = 0) and not FDataLink.Field.Required then
    FDataLink.Field.Clear
  else
    TyDBWriteNumber(FDataLink.Field, Value);
end;

procedure TTyCustomDBRating.KeyDown(var Key: Word; Shift: TShiftState);
begin
  SyncReadOnly;   // AutoEdit may have changed since, and a data source does not say so
  inherited KeyDown(Key, Shift);
end;

procedure TTyCustomDBRating.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  SyncReadOnly;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyCustomDBRating.ChangeValue(AValue: Double);
begin
  if FLoading or (FDataLink = nil) or (FDataLink.Field = nil)
    or (csLoading in ComponentState) then
  begin
    inherited ChangeValue(AValue);
    Exit;
  end;
  if not TyDBEditAllowed(FDataLink, FInUserEdit) then Exit;
  inherited ChangeValue(AValue);
  TyDBChoiceChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBRating.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBRating.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

function TTyCustomDBRating.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBRating.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

initialization
  { Each key falls back to its base control's (plan D8); the rating's filled stars are a
    sub-part resolved as the control's key + 'Star', so that key needs its parent too. }
  TyTryRegisterTypeKeyParent('TyDBCheckBox', 'TyCheckBox');
  TyTryRegisterTypeKeyParent('TyDBToggleSwitch', 'TyToggleSwitch');
  TyTryRegisterTypeKeyParent('TyDBRadioGroup', 'TyGroupBox');
  TyTryRegisterTypeKeyParent('TyDBSegmented', 'TySegmented');
  TyTryRegisterTypeKeyParent('TyDBRating', 'TyRating');
  TyTryRegisterTypeKeyParent('TyDBRatingStar', 'TyRatingStar');

finalization
  TyUnregisterTypeKeyParent('TyDBCheckBox');
  TyUnregisterTypeKeyParent('TyDBToggleSwitch');
  TyUnregisterTypeKeyParent('TyDBRadioGroup');
  TyUnregisterTypeKeyParent('TyDBSegmented');
  TyUnregisterTypeKeyParent('TyDBRating');
  TyUnregisterTypeKeyParent('TyDBRatingStar');

end.
