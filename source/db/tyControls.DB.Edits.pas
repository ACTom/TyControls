unit tyControls.DB.Edits;
{$mode objfpc}{$H+}
{ The data-aware text controls (issue #34): TTyDBEdit, TTyDBMaskEdit, TTyDBMemo and TTyDBText,
  LCL's TDBEdit / TDBMemo / TDBText on the library's own controls.

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

implementation

uses
  tyControls.StyleModel;

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

initialization
  { Each key falls back to its base control's, so a theme that never names a TyDBXxx key
    styles these exactly like their base controls; a theme can still write rules for them. }
  TyTryRegisterTypeKeyParent('TyDBEdit', 'TyEdit');
  TyTryRegisterTypeKeyParent('TyDBMaskEdit', 'TyEdit');
  TyTryRegisterTypeKeyParent('TyDBMemo', 'TyMemo');
  TyTryRegisterTypeKeyParent('TyDBText', 'TyLabel');

finalization
  TyUnregisterTypeKeyParent('TyDBEdit');
  TyUnregisterTypeKeyParent('TyDBMaskEdit');
  TyUnregisterTypeKeyParent('TyDBMemo');
  TyUnregisterTypeKeyParent('TyDBText');

end.
