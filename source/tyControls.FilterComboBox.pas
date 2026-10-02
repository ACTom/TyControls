unit tyControls.FilterComboBox;

{ A combo that lists the filter presets parsed from an LCL filter string
  ('Text (*.txt)|*.txt|All files|*.*'). Each parsed segment's Caption is a row;
  selecting a row makes that segment's pattern list the active Mask, which a host
  file list reads as `List.Mask := FilterCombo.Mask`.

  Locked to csDropDownList (pick-only): an editable csDropDown popup prefix-FILTERS
  its rows, so the visible row index would no longer line up with the parsed-spec
  array (the ColorBox lesson). Each row therefore carries its 0-based model index in
  Items.Objects[] (TObject(PtrInt(i))); the active segment is read back through it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  tyControls.ComboBox, tyControls.FileSystem, tyControls.ShellListView;

const
  { The published FilterIndex default -- 1-based, per the LCL FilterIndex convention. }
  DefaultFilterIndex = 1;

type
  TTyCustomFilterComboBox = class(TTyCustomComboBox)
  private
    FFilter: string;                { LCL filter string, verbatim }
    FSpecs: TTyFsFilterSpecArray;   { TyFsParseFilter(FFilter); row i <-> FSpecs[i] }
    FFilterIndex: Integer;          { 1-based; the active segment }
    FUpdating: Boolean;             { set while SetFilter rebuilds Items, so DoSelect
                                      does not misfire OnFilterChange during the repopulate }
    FOnFilterChange: TNotifyEvent;
    FShellListView: TTyShellListView;
    procedure SetFilter(const AValue: string);
    procedure SetFilterIndex(AValue: Integer);
    procedure SetShellListView(AValue: TTyShellListView);
    { Copy the active Mask into the linked list. The one line every host used to
      have to write by hand in an OnFilterChange handler. }
    procedure PushMask;
    { Select the row whose Objects[] model index = AModel, so the WRITE side is
      symmetric with the Objects[]-payload READ side in DoSelect -- correct even if a
      host set Sorted:=True and the base reordered Items. -1 when no row matches. }
    procedure SelectModel(AModel: Integer);
  protected
    { A row was committed by the user (chevron pick or keyboard). Recover the active
      segment from the row's Objects[] model index and fire OnFilterChange on a change. }
    procedure DoSelect; override;
    { Always pick-only -- ignore any attempt to make the field editable. }
    procedure SetStyle(AValue: TTyComboBoxStyle); override;
    { Nils a link whose list is being freed (filectrl.pp:565 does the same). }
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    { The active segment's pattern list (FSpecs[FilterIndex-1].Patterns); '' when the
      filter parsed to no segments. Equivalent to TyFsFilterPatterns(Filter, FilterIndex). }
    function Mask: string;

    { Parse an LCL filter string into a caller-supplied TStrings -- LCL's
      TCustomFilterComboBox.ConvertFilterToStrings (filectrl.pp:163-164), argument
      for argument, so ported code compiles unchanged.

      AClearStrings False APPENDS, which is the mode the free function
      TyFsParseFilter cannot express: it returns a fresh record array, so there was
      no way to merge one filter into an existing list. AAddDescription and
      AAddFilter choose which half of each segment is emitted; with both set the
      description precedes its pattern list, pairwise. }
    class procedure ConvertFilterToStrings(const AFilter: string; AStrings: TStrings;
      AClearStrings, AAddDescription, AAddFilter: Boolean);
    { The LCL filter string. Writing it reparses and rebuilds the drop-down; fires no event. }
    property Filter: string read FFilter write SetFilter;
    { The active segment, 1-based (LCL convention). }
    property FilterIndex: Integer read FFilterIndex write SetFilterIndex default DefaultFilterIndex;
    { The active mask changed (either by the user picking a row or by writing FilterIndex). }
    property OnFilterChange: TNotifyEvent read FOnFilterChange write FOnFilterChange;
    { The file list this combo filters, assignable in the Object Inspector: picking
      a row pushes the new Mask straight into it. This is the whole point of the
      control and it was missing -- every filter combo needed a hand-written
      OnFilterChange handler that copied Mask across, and a ported .lfm carrying
      `ShellListView = ShellListView1` would not load. LCL: filectrl.pp:167,
      published at :195, pushed from Select (:551). }
    property ShellListView: TTyShellListView read FShellListView write SetShellListView;
  end;

  { TTyFilterComboBox publishes TTyCustomFilterComboBox's properties; everything lives in TTyCustomFilterComboBox. }
  TTyFilterComboBox = class(TTyCustomFilterComboBox)
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
    property Filter;
    property FilterIndex;
    property OnFilterChange;
    property ShellListView;
  end;

implementation

constructor TTyCustomFilterComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFilter := '';
  FSpecs := nil;
  FFilterIndex := DefaultFilterIndex;
  FUpdating := False;
end;

function TTyCustomFilterComboBox.Mask: string;
begin
  if (FFilterIndex >= 1) and (FFilterIndex <= Length(FSpecs)) then
    Result := FSpecs[FFilterIndex - 1].Patterns
  else
    Result := '';
end;

class procedure TTyCustomFilterComboBox.ConvertFilterToStrings(const AFilter: string;
  AStrings: TStrings; AClearStrings, AAddDescription, AAddFilter: Boolean);
var
  specs: TTyFsFilterSpecArray;
  i: Integer;
begin
  if AStrings = nil then Exit;
  AStrings.BeginUpdate;
  try
    if AClearStrings then
      AStrings.Clear;
    { TyFsParseFilter is crash-safe: '' -> empty array; a malformed / odd-segment
      string yields a spec whose Patterns is ''. }
    specs := TyFsParseFilter(AFilter);
    for i := 0 to High(specs) do
    begin
      if AAddDescription then AStrings.Add(specs[i].Caption);
      if AAddFilter      then AStrings.Add(specs[i].Patterns);
    end;
  finally
    AStrings.EndUpdate;
  end;
end;

procedure TTyCustomFilterComboBox.SetShellListView(AValue: TTyShellListView);
begin
  if FShellListView = AValue then Exit;
  FShellListView := AValue;
  if AValue <> nil then
  begin
    { So Notification fires even when the list has a different owner. }
    AValue.FreeNotification(Self);
    { Adopt the current filter immediately: wiring the pair up must not leave the
      list unfiltered until the user happens to touch the combo. }
    PushMask;
  end;
end;

procedure TTyCustomFilterComboBox.PushMask;
begin
  if FShellListView = nil then Exit;
  if ComponentState * [csLoading, csDesigning] <> [] then Exit;
  FShellListView.Mask := Mask;
end;

procedure TTyCustomFilterComboBox.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FShellListView) then
    FShellListView := nil;
end;

procedure TTyCustomFilterComboBox.SetFilter(const AValue: string);
var
  i, maxIdx: Integer;
begin
  FFilter := AValue;
  FUpdating := True;
  try
    { TyFsParseFilter is crash-safe: '' -> empty array; a malformed / odd-segment
      string yields a spec whose Patterns is ''. }
    FSpecs := TyFsParseFilter(AValue);
    Items.Clear;
    for i := 0 to High(FSpecs) do
      Items.AddObject(FSpecs[i].Caption, TObject(PtrInt(i)));
    { Clamp FilterIndex to [1 .. Max(1, Length(FSpecs))]. }
    maxIdx := Length(FSpecs);
    if maxIdx < 1 then
      maxIdx := 1;
    if FFilterIndex < 1 then
      FFilterIndex := 1;
    if FFilterIndex > maxIdx then
      FFilterIndex := maxIdx;
    if Length(FSpecs) > 0 then
      SelectModel(FFilterIndex - 1)
    else
      ItemIndex := -1;
  finally
    FUpdating := False;
  end;
  { A new filter string is a new active mask even though FilterIndex may not have
    moved, so the linked list has to hear about it. (Still fires no OnFilterChange:
    writing Filter is the host's own action, not a user pick.) }
  PushMask;
end;

procedure TTyCustomFilterComboBox.SelectModel(AModel: Integer);
var
  k: Integer;
begin
  for k := 0 to Items.Count - 1 do
    if PtrInt(Items.Objects[k]) = AModel then
    begin
      ItemIndex := k;
      Exit;
    end;
  ItemIndex := -1;
end;

procedure TTyCustomFilterComboBox.SetFilterIndex(AValue: Integer);
var
  maxIdx: Integer;
begin
  maxIdx := Length(FSpecs);
  if maxIdx < 1 then
    maxIdx := 1;
  if AValue < 1 then
    AValue := 1;
  if AValue > maxIdx then
    AValue := maxIdx;
  if AValue = FFilterIndex then
    Exit;
  FFilterIndex := AValue;
  { Setting ItemIndex goes through SelectItem (fires base OnChange only, never DoSelect),
    so OnFilterChange is not double-fired here. }
  if Length(FSpecs) > 0 then
    SelectModel(FFilterIndex - 1);
  { The list first, then the event: an OnFilterChange handler that reads the list
    must not see it still showing the previous mask's contents. }
  PushMask;
  if Assigned(FOnFilterChange) then
    FOnFilterChange(Self);
end;

procedure TTyCustomFilterComboBox.DoSelect;
var
  newIdx: Integer;
begin
  inherited DoSelect;   { preserve base OnSelect semantics }
  if FUpdating then
    Exit;
  if (ItemIndex < 0) or (ItemIndex >= Items.Count) then
    Exit;
  newIdx := PtrInt(Items.Objects[ItemIndex]) + 1;   { model index -> 1-based FilterIndex }
  if newIdx <> FFilterIndex then
  begin
    FFilterIndex := newIdx;
    PushMask;                      { the list first -- see SetFilterIndex }
    if Assigned(FOnFilterChange) then
      FOnFilterChange(Self);
  end;
end;

procedure TTyCustomFilterComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  { Pick-only, and ONLY pick-only: a FILTERED editable popup would desync the row<->spec
    mapping, so the edit box is what has to go. Owner-draw is a different question and used
    to be lost with it, because this flattened every value to csDropDownList. }
  inherited SetStyle(TyComboStylePickOnly(AValue));
end;

initialization
  { So a .lfm that streams a TTyFilterComboBox resolves the class. }
  RegisterClass(TTyFilterComboBox);

end.
