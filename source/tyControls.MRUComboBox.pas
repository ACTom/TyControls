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
      list is then trimmed to MaxItems and the new entry becomes the selection.
      This control's documented name for the promotion; the promote/dedupe/trim itself
      is the base's AddHistoryItem, called with MaxItems and the case-insensitive,
      object-less arguments this narrower contract implies. }
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
begin
  { Trim + ignore-empty is this control's own contract: a stray-whitespace entry is not a
    history entry. The base's AddHistoryItem has no such guard (nor should it — a plain
    combo's history is whatever the caller says it is). }
  t := Trim(S);
  if t = '' then Exit;
  { The base drops Sorted for its insert and RESTORES it afterwards, which would
    re-alphabetise the list it had just promoted into. MRU order is recency by definition
    (the constructor sets Sorted:=False for the same reason), so drop it here and leave it
    dropped — that also makes the base's restore a no-op. A designer-set Sorted:=True must
    neither raise SSortedListError on the promote nor silently turn the history
    alphabetical. }
  Items.Sorted := False;
  { One promote/dedupe/trim, in the base, exactly as every other combo runs it. This
    method's narrower contract is expressed as ARGUMENTS — always case-insensitive, never
    an object, capped at MaxItems — instead of as a second implementation that drifts.
    (BeginUpdate keeps the delete+insert+trim a single Items notification, as before.) }
  Items.BeginUpdate;
  try
    AddHistoryItem(t, nil, FMaxItems, False, False);
  finally
    Items.EndUpdate;
  end;
  { Kept from the hand-rolled version: an MRU box shows its most recent entry, and the
    base's ASetAsText only writes Text — ItemIndex is what a host reads back. }
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
