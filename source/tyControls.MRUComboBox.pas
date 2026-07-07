unit tyControls.MRUComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils,
  tyControls.ComboBox;

type
  { An EDITABLE (csDropDown) combo that maintains a most-recently-used history.
    Each committed entry bubbles to the top of the list (case-insensitive dedupe),
    and the list is capped at MaxItems (oldest entries fall off the tail).
    Picking a dropdown row re-promotes it via the overridden DoSelect. No custom
    item paint (entries are plain text) — reuses the 'TyComboBox' style key. }
  TTyMRUComboBox = class(TTyComboBox)
  private
    FMaxItems: Integer;
    procedure SetMaxItems(AValue: Integer);
  protected
    { The base fires DoSelect after a dropdown row is picked; promote that text to
      the top of the history. AddToHistory does not recurse into DoSelect, so this
      is safe. }
    procedure DoSelect; override;
    { The editable field lost focus: remember whatever the user typed. This is how a
      freshly-TYPED value (never in the list) enters the history — DoSelect only fires
      for dropdown picks. }
    procedure DoEditorCommit; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Insert S at the top of the history (trimmed; empty is ignored). If S already
      exists (case-insensitive) it is moved to the top rather than duplicated. The
      list is then trimmed to MaxItems and the new entry becomes the selection. }
    procedure AddToHistory(const S: string);
  published
    { Maximum number of remembered entries (>= 1). Lowering it trims the tail. }
    property MaxItems: Integer read FMaxItems write SetMaxItems default 10;
  end;

implementation

constructor TTyMRUComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Style := csDropDown;   // editable: the user types a value that gets remembered
  Sorted := False;       // MRU order (recency) is never alphabetical
  FMaxItems := 10;
end;

procedure TTyMRUComboBox.SetMaxItems(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FMaxItems = AValue then Exit;
  FMaxItems := AValue;
  { Trim the tail so the current history honours the new cap. }
  while Items.Count > FMaxItems do
    Items.Delete(Items.Count - 1);
end;

procedure TTyMRUComboBox.AddToHistory(const S: string);
var
  t: string;
  existing, i: Integer;
begin
  t := Trim(S);
  if t = '' then Exit;
  { Find an existing entry case-insensitively so a re-typed value bubbles rather
    than duplicating with different casing. }
  existing := -1;
  for i := 0 to Items.Count - 1 do
    if SameText(Items[i], t) then
    begin
      existing := i;
      Break;
    end;
  Items.BeginUpdate;
  try
    { MRU order is recency, not alphabetical: Insert(0, …) means "top", which raises
      SSortedListError on a Sorted list. Force the list unsorted before reordering so a
      designer-set Sorted:=True can never crash the promote (or silently re-alphabetise). }
    Items.Sorted := False;
    if existing >= 0 then
      Items.Delete(existing);
    Items.Insert(0, t);
    while Items.Count > FMaxItems do
      Items.Delete(Items.Count - 1);
  finally
    Items.EndUpdate;
  end;
  ItemIndex := 0;
end;

procedure TTyMRUComboBox.DoSelect;
begin
  inherited DoSelect;
  AddToHistory(Text);
end;

procedure TTyMRUComboBox.DoEditorCommit;
begin
  inherited DoEditorCommit;
  AddToHistory(Text);
end;

end.
