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
  tyControls.ComboBox, tyControls.FileSystem;

const
  { The published FilterIndex default -- 1-based, per the LCL FilterIndex convention. }
  DefaultFilterIndex = 1;

type
  TTyFilterComboBox = class(TTyComboBox)
  private
    FFilter: string;                { LCL filter string, verbatim }
    FSpecs: TTyFsFilterSpecArray;   { TyFsParseFilter(FFilter); row i <-> FSpecs[i] }
    FFilterIndex: Integer;          { 1-based; the active segment }
    FUpdating: Boolean;             { set while SetFilter rebuilds Items, so DoSelect
                                      does not misfire OnFilterChange during the repopulate }
    FOnFilterChange: TNotifyEvent;
    procedure SetFilter(const AValue: string);
    procedure SetFilterIndex(AValue: Integer);
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
  public
    constructor Create(AOwner: TComponent); override;
    { The active segment's pattern list (FSpecs[FilterIndex-1].Patterns); '' when the
      filter parsed to no segments. Equivalent to TyFsFilterPatterns(Filter, FilterIndex). }
    function Mask: string;
  published
    { The LCL filter string. Writing it reparses and rebuilds the drop-down; fires no event. }
    property Filter: string read FFilter write SetFilter;
    { The active segment, 1-based (LCL convention). }
    property FilterIndex: Integer read FFilterIndex write SetFilterIndex default DefaultFilterIndex;
    { The active mask changed (either by the user picking a row or by writing FilterIndex). }
    property OnFilterChange: TNotifyEvent read FOnFilterChange write FOnFilterChange;
  end;

implementation

constructor TTyFilterComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFilter := '';
  FSpecs := nil;
  FFilterIndex := DefaultFilterIndex;
  FUpdating := False;
end;

function TTyFilterComboBox.Mask: string;
begin
  if (FFilterIndex >= 1) and (FFilterIndex <= Length(FSpecs)) then
    Result := FSpecs[FFilterIndex - 1].Patterns
  else
    Result := '';
end;

procedure TTyFilterComboBox.SetFilter(const AValue: string);
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
end;

procedure TTyFilterComboBox.SelectModel(AModel: Integer);
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

procedure TTyFilterComboBox.SetFilterIndex(AValue: Integer);
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
  if Assigned(FOnFilterChange) then
    FOnFilterChange(Self);
end;

procedure TTyFilterComboBox.DoSelect;
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
    if Assigned(FOnFilterChange) then
      FOnFilterChange(Self);
  end;
end;

procedure TTyFilterComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  { Pick-only: a filtered editable popup would desync the row<->spec mapping. }
  inherited SetStyle(csDropDownList);
end;

initialization
  { So a .lfm that streams a TTyFilterComboBox resolves the class. }
  RegisterClass(TTyFilterComboBox);

end.
