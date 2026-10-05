unit tyControls.DB.DateTime;
{$mode objfpc}{$H+}
{ The data-aware date controls (issue #34): TTyDBDateTimePicker, LCL's TDBDateTimePicker on the
  library's picker, and TTyDBCalendar, LCL's TDBCalendar on the library's calendar -- split like
  the rest, the data properties public on the custom class and published after the base
  control's list.

  THE PICKER loads the field with AsDateTime and shows NULL as its empty value (TyNullDate);
  with NullInputAllowed, N or Delete empties it and writes NULL. It hears every change through
  the base control's Change -- keys, wheel, spin buttons and the dropdown calendar, which never
  passes through the picker's own key and mouse code -- and takes one that leaves the loaded
  value for the user's edit. A refused edit (AutoEdit off and nobody editing) puts the field's
  value back and does not reach OnChange. The base control is read-only while this ReadOnly is
  or while the field cannot be changed (LCL's CheckField), so keys, wheel and spin buttons do
  nothing then, and the dropdown neither opens nor gives a day. Enter, EditingDone and leaving
  the control write the value back; a date field gets the date alone, a time field the time.
  Escape, while the record is being edited, brings back the FIELD's value -- not the base
  control's snapshot from when focus arrived, which an Enter in between has already written
  past.

  THE CALENDAR shows the field's day, clamped into MinDate..MaxDate (SetDateClamped: a field
  outside the range is not an exception). A NULL field leaves the calendar on the day it shows:
  a calendar has no empty state. A day picked by the user -- a click, an arrow key, Page Up --
  puts the record in dsEdit and marks the link modified; accepting a day (a click on it, Enter,
  Space), EditingDone and leaving the control write it back, and so does a Post made elsewhere.
  LCL's TDBCalendar never marks its link modified, so a picked day is never written; this one
  is. A date-and-time field keeps its time of day. }
interface

uses
  Classes, SysUtils, Controls, LCLType, LMessages, DB, DBCtrls,
  tyControls.DateTimePicker, tyControls.Calendar, tyControls.DB.Common;

type
  TTyCustomDBDateTimePicker = class(TTyCustomDateTimePicker)
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
    { The base control's ReadOnly := ours, or the field cannot be changed. }
    procedure SyncReadOnly;
    procedure LinkStateChange(Sender: TObject);
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Change; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoExit; override;
    { The value lives in the field, not in the form file. }
    property DateTime stored False;
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
  end;

  { TTyDBDateTimePicker publishes TTyCustomDBDateTimePicker's properties; everything lives in TTyCustomDBDateTimePicker. }
  TTyDBDateTimePicker = class(TTyCustomDBDateTimePicker)
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
    property DateTime;
    property Kind;
    property DateFormat;
    property TimeFormat;
    property MinDate;
    property MaxDate;
    property ReadOnly;
    property ShowCheckBox;
    property Checked;
    property DroppedDown;
    property Alignment;
    property LeadingZeros;
    property CenturyFrom;
    property Options;
    property DateMode;
    property NullInputAllowed;
    property TextForNullDate;
    property OnChange;
    property OnDropDown;
    property OnCloseUp;
    property OnChecked;
    property OnCheckBoxChange;
    property Align;
    property Anchors;
    property DataField;
    property DataSource;
  end;

  TTyCustomDBCalendar = class(TTyCustomCalendar)
  private
    FDataLink: TFieldDataLink;
    FInUserEdit: Boolean;
    FLoaded: TTyDBLoadedValue;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    procedure SyncReadOnly;
    procedure LinkStateChange(Sender: TObject);
    { The user may have moved the day (it was ABefore): an edit, unless it is the loaded day. }
    procedure UserMoved(ABefore: TDateTime);
    { The user accepted the day shown: write it into the record. }
    procedure Accepted;
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
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
    { The value lives in the field, not in the form file. }
    property Date stored False;
  end;

  { TTyDBCalendar publishes TTyCustomDBCalendar's properties; everything lives in TTyCustomDBCalendar. }
  TTyDBCalendar = class(TTyCustomDBCalendar)
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
    property Date;
    property DateTime;
    property MinDate;
    property MaxDate;
    property FirstDayOfWeek;
    property DisplaySettings;
    property WeekNumbers;
    property ShowToday;
    property ReadOnly;
    property OnChange;
    property OnDayChanged;
    property OnMonthChanged;
    property OnYearChanged;
    property OnAccept;
    property OnViewChange;
    property Align;
    property Anchors;
    property DataField;
    property DataSource;
  end;

implementation

uses
  Types, DateUtils, tyControls.StyleModel;

{ ============================================================ TTyCustomDBDateTimePicker == }

constructor TTyCustomDBDateTimePicker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
  FDataLink.OnActiveChange := @LinkStateChange;
  FDataLink.OnEditingChange := @LinkStateChange;
  { Unbound, there is no date to show (LCL's TDBDateTimePicker starts empty too). }
  FLoading := True;
  try
    DateTime := TyNullDate;
  finally
    FLoading := False;
  end;
  FLoaded := TyDBLoadedDate(0, True);
end;

destructor TTyCustomDBDateTimePicker.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FDataLink.OnActiveChange := nil;
  FDataLink.OnEditingChange := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBDateTimePicker.GetStyleTypeKey: string;
begin
  Result := 'TyDBDateTimePicker';
end;

function TTyCustomDBDateTimePicker.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBDateTimePicker.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBDateTimePicker.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBDateTimePicker.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBDateTimePicker.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBDateTimePicker.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBDateTimePicker.SetReadOnly(AValue: Boolean);
begin
  FDataLink.ReadOnly := AValue;
  SyncReadOnly;
end;

procedure TTyCustomDBDateTimePicker.SyncReadOnly;
begin
  if FDataLink = nil then Exit;
  inherited ReadOnly := FDataLink.ReadOnly
    or ((FDataLink.Field <> nil) and not FDataLink.CanModify);
end;

procedure TTyCustomDBDateTimePicker.LinkStateChange(Sender: TObject);
begin
  SyncReadOnly;
end;

procedure TTyCustomDBDateTimePicker.DataChange(Sender: TObject);
var
  f: TField;
begin
  if FInUserEdit then Exit;   // the dataset entering dsEdit for the user's change: keep it
  SyncReadOnly;
  f := FDataLink.Field;
  FLoading := True;
  try
    if (f = nil) or f.IsNull then
      DateTime := TyNullDate
    else
      DateTime := f.AsDateTime;   // clamped to MinDate..MaxDate, as typed
    { The field is the value Escape and focus come back to, even when the value did not
      move; and a half-typed field belongs to the record that was showing. }
    ConfirmChanges;
    UndoChanges;
    FLoaded := TyDBLoadedDate(DateTime, DateIsNull);
  finally
    FLoading := False;
  end;
end;

procedure TTyCustomDBDateTimePicker.UpdateData(Sender: TObject);
var
  f: TField;
begin
  f := FDataLink.Field;
  if DateIsNull then
    f.Clear
  else
    case f.DataType of
      ftDate: f.AsDateTime := DateOf(DateTime);   // a date column gets no time of day
      ftTime: f.AsDateTime := TimeOf(DateTime);
    else
      f.AsDateTime := DateTime;
    end;
  FLoaded := TyDBLoadedDate(DateTime, DateIsNull);   // what the field holds now: changing back is an edit again
end;

{ Every user change of the value arrives here, the dropdown calendar's included. The edit
  comes first, as in LCL's TDBDateTimePicker.Change: a change the dataset refuses is undone
  by the reset and never reaches the application's OnChange. }
procedure TTyCustomDBDateTimePicker.Change;
begin
  if not (FLoading or FInUserEdit or (FDataLink = nil) or (FDataLink.Field = nil)
    or (csLoading in ComponentState)) then
    if (DateIsNull <> FLoaded.IsNull)
      or not (DateIsNull or TyEqualDateTime(DateTime, FLoaded.Date)) then
    begin
      TyDBUserChanged(FDataLink, FInUserEdit);
      if not FDataLink.Editing then Exit;   // refused: the field's value is back
    end;
  inherited Change;
end;

procedure TTyCustomDBDateTimePicker.KeyDown(var Key: Word; Shift: TShiftState);
var
  wasReturn: Boolean;
begin
  { An open dropdown takes Escape to close; otherwise, while the record is being edited,
    Escape shows the field again. The reload confirms the field's value as the one the
    base control's own undo returns to. }
  if (Key = VK_ESCAPE) and not ((Popup <> nil) and Popup.IsOpen) and FDataLink.Editing then
  begin
    FDataLink.Reset;
    Key := 0;
    Exit;
  end;
  wasReturn := (Key = VK_RETURN) and (Shift = []);
  inherited KeyDown(Key, Shift);
  if wasReturn and FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBDateTimePicker.DoExit;
begin
  inherited DoExit;   // commits what was typed
  if (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  if FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBDateTimePicker.EditingDone;
begin
  if (FDataLink <> nil) and FDataLink.Editing then
    FDataLink.UpdateRecord;
  inherited EditingDone;
end;

procedure TTyCustomDBDateTimePicker.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBDateTimePicker.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

function TTyCustomDBDateTimePicker.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBDateTimePicker.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

{ ================================================================== TTyCustomDBCalendar == }

constructor TTyCustomDBCalendar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
  FDataLink.OnActiveChange := @LinkStateChange;
  FDataLink.OnEditingChange := @LinkStateChange;
  FLoaded := TyDBLoadedDate(0, True);
end;

destructor TTyCustomDBCalendar.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FDataLink.OnActiveChange := nil;
  FDataLink.OnEditingChange := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBCalendar.GetStyleTypeKey: string;
begin
  Result := 'TyDBCalendar';
end;

function TTyCustomDBCalendar.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBCalendar.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBCalendar.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBCalendar.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

procedure TTyCustomDBCalendar.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBCalendar.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBCalendar.SetReadOnly(AValue: Boolean);
begin
  FDataLink.ReadOnly := AValue;
  SyncReadOnly;
end;

procedure TTyCustomDBCalendar.SyncReadOnly;
begin
  if FDataLink = nil then Exit;
  inherited ReadOnly := FDataLink.ReadOnly
    or ((FDataLink.Field <> nil) and not FDataLink.CanModify);
end;

procedure TTyCustomDBCalendar.LinkStateChange(Sender: TObject);
begin
  SyncReadOnly;
end;

{ No load flag: the calendar announces only the user's own picks (SelectDate); a date set from
  code, clamped or not, fires nothing. }
procedure TTyCustomDBCalendar.DataChange(Sender: TObject);
var
  f: TField;
begin
  if FInUserEdit then Exit;
  SyncReadOnly;
  f := FDataLink.Field;
  if (f <> nil) and not f.IsNull then
    SetDateClamped(f.AsDateTime);   // a field outside MinDate..MaxDate is not an exception
  FLoaded := TyDBLoadedDate(Date, (f = nil) or f.IsNull);
end;

procedure TTyCustomDBCalendar.UpdateData(Sender: TObject);
var
  f: TField;
begin
  f := FDataLink.Field;
  if (f.DataType = ftDate) or f.IsNull then
    f.AsDateTime := DateOf(Date)
  else
    f.AsDateTime := DateOf(Date) + TimeOf(f.AsDateTime);   // the day moves, the hour stays
  FLoaded := TyDBLoadedDate(Date, False);   // what the field holds now: changing back is an edit again
end;

procedure TTyCustomDBCalendar.UserMoved(ABefore: TDateTime);
begin
  if (FDataLink.Field = nil) or (DateOf(Date) = DateOf(ABefore)) then Exit;
  if not FLoaded.IsNull and (DateOf(Date) = DateOf(FLoaded.Date)) then Exit;
  TyDBUserChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBCalendar.Accepted;
begin
  if FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBCalendar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  before: TDateTime;
  onDay: Boolean;
begin
  before := Date;
  { A day cell clicked in the days view is the calendar's accept gesture (it fires OnAccept). }
  onDay := (Button = mbLeft) and (ViewMode = cvmDays) and (HitTest(Point(X, Y)) = cpDate);
  inherited MouseDown(Button, Shift, X, Y);
  UserMoved(before);
  if onDay then Accepted;
end;

procedure TTyCustomDBCalendar.KeyDown(var Key: Word; Shift: TShiftState);
var
  before: TDateTime;
  accept: Boolean;
begin
  if (Key = VK_ESCAPE) and FDataLink.Editing then
  begin
    FDataLink.Reset;   // the field's day again
    Key := 0;
    Exit;
  end;
  before := Date;
  accept := (Key = VK_RETURN) or (Key = VK_SPACE);   // the calendar's accept keys
  inherited KeyDown(Key, Shift);
  UserMoved(before);
  if accept then Accepted;
end;

procedure TTyCustomDBCalendar.DoExit;
begin
  inherited DoExit;
  if (FDataLink = nil) or (csDestroying in ComponentState) then Exit;
  if FDataLink.Editing then
    FDataLink.UpdateRecord;
end;

procedure TTyCustomDBCalendar.EditingDone;
begin
  if (FDataLink <> nil) and FDataLink.Editing then
    FDataLink.UpdateRecord;
  inherited EditingDone;
end;

procedure TTyCustomDBCalendar.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBCalendar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

function TTyCustomDBCalendar.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBCalendar.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

initialization
  TyTryRegisterTypeKeyParent('TyDBDateTimePicker', 'TyDateTimePicker');
  TyTryRegisterTypeKeyParent('TyDBCalendar', 'TyCalendar');

finalization
  TyUnregisterTypeKeyParent('TyDBDateTimePicker');
  TyUnregisterTypeKeyParent('TyDBCalendar');

end.
