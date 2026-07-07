unit tyControls.CheckComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox, tyControls.CheckListBox;

type
  { A combo box whose drop-down is a CHECK list: the user ticks any number of items and the
    popup STAYS OPEN (multi-select) instead of closing on a pick; the field shows a summary
    (the checked item texts joined by Separator, or EmptyText when none). The per-item checked
    state lives in THIS combo's Items.Objects[i] (0/1) — the persistent truth — and is copied
    into the popup checklist on open (via Items.Assign) and synced back on each toggle, so it
    survives open/close and Sorted (no parallel array). Locked to csDropDownList (an editable
    prefix-filtered field is meaningless for a multi-check). Build with Items.Add + Checked[]. }
  TTyCheckComboBox = class(TTyComboBox)
  private
    FSeparator: string;
    FEmptyText: string;
    function GetChecked(AIndex: Integer): Boolean;
    procedure SetChecked(AIndex: Integer; AValue: Boolean);
    procedure SetEmptyText(const AValue: string);
    procedure PopupCheckClick(Sender: TObject);
  protected
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    { A row pick must NOT commit/close — checking is a toggle, and the popup stays open. The
      checkbox toggle + field sync happen in the checklist / PopupCheckClick, so this is a no-op. }
    procedure DoPopupPick(AIndex: Integer); override;
    procedure SetStyle(AValue: TTyComboBoxStyle); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Number of checked items.
    function CheckedCount: Integer;
    // The field summary (checked item texts joined by Separator, or EmptyText when none).
    function CheckedText: string;
    property Checked[AIndex: Integer]: Boolean read GetChecked write SetChecked;
  published
    // Joins the checked item texts in the field summary (default ', ').
    property Separator: string read FSeparator write FSeparator;
    // Shown in the field when nothing is checked (default '').
    property EmptyText: string read FEmptyText write SetEmptyText;
  end;

implementation

constructor TTyCheckComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSeparator := ', ';
  FEmptyText := '';
end;

function TTyCheckComboBox.GetChecked(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Items.Count)
    and (PtrInt(Items.Objects[AIndex]) <> 0);
end;

procedure TTyCheckComboBox.SetChecked(AIndex: Integer; AValue: Boolean);
var
  lst: TTyListBox;   // PopupList (nil when the dropdown is closed — no side effect)
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  if GetChecked(AIndex) = AValue then Exit;
  Items.Objects[AIndex] := TObject(PtrInt(Ord(AValue)));
  { Keep a live popup in sync (programmatic set while the dropdown is open). }
  lst := PopupList;
  if (lst is TTyCheckListBox) and (AIndex < lst.Items.Count) then
    TTyCheckListBox(lst).Checked[AIndex] := AValue;
  Invalidate;
end;

procedure TTyCheckComboBox.SetEmptyText(const AValue: string);
begin
  if FEmptyText = AValue then Exit;
  FEmptyText := AValue;
  Invalidate;
end;

function TTyCheckComboBox.CheckedCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to Items.Count - 1 do
    if GetChecked(i) then Inc(Result);
end;

function TTyCheckComboBox.CheckedText: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to Items.Count - 1 do
    if GetChecked(i) then
    begin
      if Result <> '' then Result := Result + FSeparator;
      Result := Result + Items[i];
    end;
  if Result = '' then Result := FEmptyText;
end;

procedure TTyCheckComboBox.PopupCheckClick(Sender: TObject);
var
  i: Integer;
  lst: TTyCheckListBox;
begin
  { A checkbox was toggled in the popup: sync the state from the popup COPY back to our own
    Items.Objects (same order — csDropDownList never filters), repaint the field summary, and
    notify. The popup stays open. }
  if not (PopupList is TTyCheckListBox) then Exit;
  lst := TTyCheckListBox(PopupList);
  for i := 0 to Items.Count - 1 do
    if i < lst.Items.Count then
      Items.Objects[i] := lst.Items.Objects[i];
  Invalidate;
  if Assigned(OnChange) then OnChange(Self);
end;

function TTyCheckComboBox.CreatePopupList: TTyListBox;
var lst: TTyCheckListBox;
begin
  lst := TTyCheckListBox.Create(Self);
  lst.OnClickCheck := @PopupCheckClick;
  Result := lst;
end;

procedure TTyCheckComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect;
  const AStyle: TTyStyleSet);
begin
  P.DrawText(ATextRect, CheckedText, AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

procedure TTyCheckComboBox.DoPopupPick(AIndex: Integer);
begin
  // Intentionally empty: no single-item commit, no close (see class header).
end;

procedure TTyCheckComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  inherited SetStyle(csDropDownList);   // multi-check is pick-only; ignore editable mode
end;

end.
