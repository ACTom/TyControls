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

  CODE. Setting the value from code is not the user's edit -- except on the radio group, whose
  only change notification is the one a click gives too (SelectionChanged), so setting its
  ItemIndex or Value from code edits the field, as it does on LCL's TDBRadioGroup.

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
    property Checked stored False;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Every way the user toggles a check box -- a click, Space, its accelerator -- ends here. }
    procedure Click; override;
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
    in neither list, shows off. A click, Space and Enter all toggle it, and all three ask first. }
  TTyCustomDBToggleSwitch = class(TTyCustomToggleSwitch)
  private
    FDataLink: TFieldDataLink;
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
    { Space and Enter toggle the base switch without going through Click. }
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    property Checked stored False;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
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
    row of segments. A click or an arrow key that moves the selection is the user's edit;
    setting ItemIndex or Value from code is not. }
  TTyCustomDBSegmented = class(TTyCustomSegmented)
  private
    FDataLink: TFieldDataLink;
    FInUserEdit: Boolean;
    FValues: TStringList;
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
    function GetValue: string;
    procedure SetValue(const AValue: string);
    function IndexOfValue(const AValue: string): Integer;
    { The selection moved under the user's hand (it was ABefore). }
    procedure UserMoved(ABefore: Integer);
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
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
    writes, whole stars: a field's 3.5 shows as 4 (it is written back only when the user
    changes the rating). No stars is NULL: a NULL field shows none, and clearing the rating to
    none writes NULL -- or 0 when the field is Required. The base control's own ReadOnly is on
    while this ReadOnly is, or while the field cannot be changed. }
  TTyCustomDBRating = class(TTyCustomRating)
  private
    FDataLink: TFieldDataLink;
    FInUserEdit: Boolean;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    { The base control's ReadOnly := ours, or the field cannot be changed (LCL's
      TDBDateTimePicker.CheckField does the same with CanModify). }
    procedure SyncReadOnly;
    procedure UserMoved(ABefore: Double);
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure LinkStateChange(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
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
  State := FieldState;
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

procedure TTyCustomDBCheckBox.Click;
var
  before: TCheckBoxState;
begin
  { Refused before the box flips: no OnChange, no OnClick for a change that cannot be kept. }
  if (FDataLink.Field <> nil) and not TyDBEditAllowed(FDataLink, FInUserEdit) then Exit;
  before := State;
  inherited Click;
  if (FDataLink.Field <> nil) and (State <> before) then
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
  Checked := FieldChecked;
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
var
  before: Boolean;
begin
  if not FlipAllowed then Exit;
  before := Checked;
  inherited Click;
  if (FDataLink.Field <> nil) and (Checked <> before) then
    TyDBChoiceChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBToggleSwitch.KeyDown(var Key: Word; Shift: TShiftState);
var
  before: Boolean;
begin
  if ((Key = VK_SPACE) or (Key = VK_RETURN)) and Enabled and not FlipAllowed then
  begin
    Key := 0;
    Exit;
  end;
  before := Checked;
  inherited KeyDown(Key, Shift);
  if (FDataLink.Field <> nil) and (Checked <> before) then
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
  if FDataLink.Field = nil then
    ItemIndex := -1
  else
    ItemIndex := IndexOfValue(FDataLink.Field.Text);
end;

procedure TTyCustomDBSegmented.UpdateData(Sender: TObject);
begin
  if ItemIndex < 0 then
    FDataLink.Field.Clear
  else
    FDataLink.Field.Text := ButtonValue(ItemIndex);
end;

procedure TTyCustomDBSegmented.UserMoved(ABefore: Integer);
begin
  if (ItemIndex = ABefore) or (FDataLink.Field = nil) then Exit;
  TyDBChoiceChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBSegmented.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  before: Integer;
begin
  before := ItemIndex;
  inherited MouseDown(Button, Shift, X, Y);
  UserMoved(before);
end;

procedure TTyCustomDBSegmented.KeyDown(var Key: Word; Shift: TShiftState);
var
  before: Integer;
begin
  before := ItemIndex;
  inherited KeyDown(Key, Shift);
  UserMoved(before);
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

procedure TTyCustomDBRating.SyncReadOnly;
begin
  TTyCustomRating(Self).ReadOnly := FDataLink.ReadOnly
    or ((FDataLink.Field <> nil) and not FDataLink.CanModify);
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
  Value := v;
end;

procedure TTyCustomDBRating.UpdateData(Sender: TObject);
begin
  if (Value = 0) and not FDataLink.Field.Required then
    FDataLink.Field.Clear
  else
    TyDBWriteNumber(FDataLink.Field, Value);
end;

procedure TTyCustomDBRating.UserMoved(ABefore: Double);
begin
  if (Value = ABefore) or (FDataLink.Field = nil) then Exit;
  TyDBChoiceChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBRating.KeyDown(var Key: Word; Shift: TShiftState);
var
  before: Double;
begin
  before := Value;
  inherited KeyDown(Key, Shift);
  UserMoved(before);
end;

procedure TTyCustomDBRating.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  before: Double;
begin
  before := Value;
  inherited MouseDown(Button, Shift, X, Y);
  UserMoved(before);
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
