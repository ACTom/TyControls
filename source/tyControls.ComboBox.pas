unit tyControls.ComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, StdCtrls, LCLType, LCLIntf,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.ListBox, tyControls.Popup;
function TyComboTypeAheadMatch(AItems: TStrings; AStart: Integer; const APrefix: string): Integer;

type
  TTyComboBox = class(TTyCustomControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FText: string;
    FDropDownCount: Integer;
    FSorted: Boolean;
    FMaxLength: Integer;
    FCharCase: TEditCharCase;
    FOnChange: TNotifyEvent;
    FOnSelect: TNotifyEvent;
    FOnDropDown: TNotifyEvent;
    FOnCloseUp: TNotifyEvent;
    { Dropdown popup state }
    FPopup: TTyDropdownPopup; // lazy; created on first DropDown; freed in Destroy
    FPopupList: TTyListBox;   // owned by Self; parented into FPopup.Form via SetContent
    { Type-ahead state }
    FTypeAhead: string;
    FTypeAheadTick: QWord;
    procedure SetItems(const AValue: TStringList);
    procedure SetItemIndex(const AValue: Integer);
    procedure SetText(const AValue: string);
    procedure SetDropDownCount(const AValue: Integer);
    procedure SetSorted(const AValue: Boolean);
    procedure SetCharCase(const AValue: TEditCharCase);
    { Re-locate FItemIndex from the currently-selected text after the item list
      has been reordered (e.g. by sorting). Keeps the SAME item selected. }
    procedure ResyncIndexFromText;
    { Fires when the underlying TStringList mutates (add/insert/delete). Lets us
      keep FItemIndex pinned to its item while Sorted reorders insertions. }
    procedure ItemsChanged(Sender: TObject);
    function ButtonWidthLogical: Integer;
    { User-driven selection: applies AIndex via SelectItem and fires OnSelect
      only when the selection actually changed. Distinct from the programmatic
      ItemIndex setter, which fires OnChange but never OnSelect. }
    procedure UserSelect(AIndex: Integer);
    { Popup event handlers }
    procedure PopupListChange(Sender: TObject);
    procedure PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PopupClosed(Sender: TObject);
    procedure DeferredCloseUp(Data: PtrInt);
  protected
    { Guard: tick at last CloseUp. Click reopens only if > 200ms have passed.
      Mirrored from FPopup.CloseUpTick (via PopupClosed) so test subclasses can
      still manipulate it (e.g. AgeCloseUpTick) without accessing FPopup directly. }
    FCloseUpTick: QWord;
    procedure SetController(AValue: TTyStyleController); override;
    { Headless-testable popup-height calculation: DropDownCount governs how many
      rows are visible before the dropdown scrolls. Separated from DropDown so it
      can be exercised without building a real win32 popup form. }
    function ComputePopupHeight(APPI: Integer): Integer;
    procedure DoSelect; virtual;
    procedure DoDropDown; virtual;
    procedure DoCloseUp; virtual;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Click; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetStyleTypeKey: string; override;
    procedure SelectItem(AIndex: Integer);
    function DroppedDown: Boolean;
    procedure DropDown; virtual;
    procedure CloseUp;
    { Expose popup list for headless tests and internal use }
    function PopupList: TTyListBox;
  published
    property Items: TStringList read FItems write SetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property Text: string read FText write SetText;
    { Max number of rows visible in the dropdown before it scrolls (LCL default 8). }
    property DropDownCount: Integer read FDropDownCount write SetDropDownCount default 8;
    { When True, Items are kept in ascending (case-insensitive) order and the
      previously-selected item stays selected (tracked by its text). }
    property Sorted: Boolean read FSorted write SetSorted default False;
    { MaxLength/CharCase apply to the edit field of an editable combo. This combo
      is read-only (csDropDownList); they are published for native-API parity and
      streaming round-trip, and are reserved for a future editable mode. They have
      no effect on the displayed (read-only) selected text. }
    property MaxLength: Integer read FMaxLength write FMaxLength default 0;
    property CharCase: TEditCharCase read FCharCase write SetCharCase default ecNormal;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
    property OnCloseUp: TNotifyEvent read FOnCloseUp write FOnCloseUp;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;
implementation
uses
  Math, tyControls.QtWS;

function TyComboTypeAheadMatch(AItems: TStrings; AStart: Integer; const APrefix: string): Integer;
var n, i, idx: Integer; pfx: string;
begin
  Result := -1;
  n := AItems.Count;
  if (n = 0) or (APrefix = '') then Exit;
  pfx := LowerCase(APrefix);
  for i := 1 to n do
  begin
    idx := (AStart + i) mod n;      // start searching AFTER AStart, wrapping
    if idx < 0 then idx := idx + n;
    if Copy(LowerCase(AItems[idx]), 1, Length(pfx)) = pfx then
      Exit(idx);
  end;
end;

constructor TTyComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;
  FItemIndex := -1;
  FText := '';
  FDropDownCount := 8;
  FSorted := False;
  FMaxLength := 0;
  FCharCase := ecNormal;
  FPopup     := nil;
  FPopupList := nil;
  TabStop := True;
  Width := 145;
  Height := 26;
end;

destructor TTyComboBox.Destroy;
begin
  { Cancel any queued async calls so they can't fire into a freed combo. }
  Application.RemoveAsyncCalls(Self);
  { Free the popup helper first (it owns its form; FPopupList is owned by Self
    and will be freed below — the helper only parented it, not owned it). }
  FreeAndNil(FPopup);
  { Free the list box (owned by Self; no longer parented to anything after the
    helper's form was freed above). }
  FreeAndNil(FPopupList);
  FItems.Free;
  inherited Destroy;
end;

function TTyComboBox.GetStyleTypeKey: string;
begin
  Result := 'TyComboBox';
end;

procedure TTyComboBox.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
  { Keep an already-created popup list in sync when the controller is reassigned;
    otherwise FPopupList keeps the old controller until the next DropDown. }
  if FPopupList <> nil then
    FPopupList.Controller := AValue;
  { Propagate to the popup helper so ApplyRegion resolves the background color
    from the updated theme. }
  if FPopup <> nil then
    FPopup.Controller := AValue;
end;

procedure TTyComboBox.DoSelect;
begin
  if Assigned(FOnSelect) then FOnSelect(Self);
end;

procedure TTyComboBox.DoDropDown;
begin
  if Assigned(FOnDropDown) then FOnDropDown(Self);
end;

procedure TTyComboBox.DoCloseUp;
begin
  if Assigned(FOnCloseUp) then FOnCloseUp(Self);
end;

procedure TTyComboBox.UserSelect(AIndex: Integer);
var
  OldIndex: Integer;
begin
  OldIndex := FItemIndex;
  SelectItem(AIndex);            // fires OnChange on a real change
  if FItemIndex <> OldIndex then
    DoSelect;                    // OnSelect = the user actually picked something
end;

procedure TTyComboBox.SetItems(const AValue: TStringList);
begin
  { TStringList.Assign copies the source's Sorted flag, which would silently drop
    our Sorted state. Re-apply it so an externally-set Items list stays sorted. }
  FItems.Assign(AValue);
  if FItems.Sorted <> FSorted then
    FItems.Sorted := FSorted;
  Invalidate;
end;

procedure TTyComboBox.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Invalidate;
end;

procedure TTyComboBox.SetItemIndex(const AValue: Integer);
begin
  SelectItem(AValue);
end;

procedure TTyComboBox.SetDropDownCount(const AValue: Integer);
begin
  if FDropDownCount = AValue then Exit;
  { Clamp to at least 1 visible row, mirroring LCL behaviour. }
  if AValue < 1 then
    FDropDownCount := 1
  else
    FDropDownCount := AValue;
  { If the popup is currently open, re-size it on the next DropDown. No live
    resize here to keep the open popup stable. }
end;

procedure TTyComboBox.SetSorted(const AValue: Boolean);
begin
  if FSorted = AValue then Exit;
  FSorted := AValue;
  { TStringList natively supports Sorted: it sorts in place (ascending,
    case-insensitive by default) and keeps subsequent Adds sorted. Setting it
    reorders the items, so the selected index becomes stale — re-find it by text. }
  FItems.OnChange := nil;        // avoid re-entrancy while we flip Sorted
  FItems.Sorted := FSorted;
  FItems.OnChange := @ItemsChanged;
  ResyncIndexFromText;
  Invalidate;
end;

procedure TTyComboBox.SetCharCase(const AValue: TEditCharCase);
begin
  { Stored for API parity; read-only combo has no edit text to transform. }
  FCharCase := AValue;
end;

procedure TTyComboBox.ResyncIndexFromText;
var
  Idx: Integer;
begin
  { Keep the SAME item selected after the list was reordered: locate the current
    selection text and pin FItemIndex to it. No OnChange — the selection (text)
    did not change, only its position. }
  if FItemIndex < 0 then Exit;        // nothing was selected
  Idx := FItems.IndexOf(FText);
  if Idx >= 0 then
    FItemIndex := Idx
  else
  begin
    { Selected text no longer present — clear selection. }
    FItemIndex := -1;
    FText := '';
  end;
end;

procedure TTyComboBox.ItemsChanged(Sender: TObject);
begin
  { When items are added/removed (including a sorted insert that shifts indices),
    keep FItemIndex pinned to the selected item's text. }
  ResyncIndexFromText;
  Invalidate;
end;

function TTyComboBox.ComputePopupHeight(APPI: Integer): Integer;
const
  { The dropdown popup uses a default TTyListBox, whose ItemHeight default is 24
    (TTyListBox.ItemHeight default). The popup never overrides it. }
  cPopupRowHeight = 24;
var
  ScaledIH, VisibleRows: Integer;
begin
  { Visible rows = min(Items.Count, DropDownCount); each row scaled to the given
    PPI; plus the 2px popup frame chrome. Single source of the sizing formula —
    DropDown calls this so the live popup and the headless calc stay in sync. }
  ScaledIH := MulDiv(cPopupRowHeight, APPI, 96);
  VisibleRows := Min(FItems.Count, FDropDownCount);
  Result := VisibleRows * ScaledIH + 2;
end;

function TTyComboBox.ButtonWidthLogical: Integer;
begin
  Result := TyFieldButtonWidth;
end;

procedure TTyComboBox.SelectItem(AIndex: Integer);
var
  NewIndex: Integer;
  NewText: string;
begin
  if (AIndex >= 0) and (AIndex < FItems.Count) then
  begin
    NewIndex := AIndex;
    NewText := FItems[AIndex];
  end
  else
  begin
    NewIndex := -1;
    NewText := '';
  end;
  if (NewIndex = FItemIndex) and (NewText = FText) then Exit;
  FItemIndex := NewIndex;
  FText := NewText;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TTyComboBox.DroppedDown: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.IsOpen;
end;

{ Ensure the popup helper and its TTyListBox child exist, then show the popup. }
procedure TTyComboBox.DropDown;
var
  PopupH: Integer;
  S: TTyStyleSet;
begin
  if FItems.Count = 0 then Exit;

  { Lazily create the popup helper and the list box (both live for the combo's
    lifetime — the helper reuses its form across multiple show/hide cycles). }
  if FPopup = nil then
  begin
    FPopup := TTyDropdownPopup.Create;
    FPopup.Controller := Self.Controller;
    FPopup.OnClose    := @PopupClosed;

    FPopupList := TTyListBox.Create(Self);  // owned by the combo, not the form
    FPopupList.ForceSquareSurface := TyQtIsWayland;
    FPopupList.OnChange := @PopupListChange;

    { Wire the list into the helper's form (alClient; SetContent is one-shot). }
    FPopup.SetContent(FPopupList);

    { Key handling on the popup form. }
    FPopup.Form.KeyPreview := True;
    FPopup.Form.OnKeyDown  := @PopupKeyDown;
  end;

  { Sync controller every DropDown so DPI/theme changes take effect. }
  FPopupList.Controller := Self.Controller;
  FPopup.Controller     := Self.Controller;

  { Sync items and selection — detach OnChange to prevent recursion. }
  FPopupList.OnChange := nil;
  FPopupList.Items.Assign(FItems);
  FPopupList.SelectItem(FItemIndex);
  FPopupList.OnChange := @PopupListChange;

  { Resolve the list's corner radius so the popup window region matches the
    themed fill (same value the old ApplyPopupRegion computed). }
  S := ActiveController.Model.ResolveStyle('TyListBox', '', []);
  FPopup.CornerRadiusLogical := S.BorderRadius;

  { Size: height = min(DropDownCount, Items.Count) rows (+ frame chrome). }
  PopupH := ComputePopupHeight(Font.PixelsPerInch);

  FPopup.Popup(Self, Width, PopupH);
  DoDropDown;   // popup actually opened
end;

procedure TTyComboBox.CloseUp;
begin
  { If the popup is open, close it — FPopup.Close fires PopupClosed (OnClose)
    which mirrors FCloseUpTick, Invalidates, and calls DoCloseUp. }
  if (FPopup <> nil) and FPopup.IsOpen then
  begin
    FPopup.Close;   // → PopupClosed fires here
    Exit;
  end;
  { Popup was not open (headless test path or already closed): record the tick
    and fire bookkeeping so the race guard still works in tests. }
  FCloseUpTick := GetTickCount64;
  Invalidate;
  DoCloseUp;
end;

procedure TTyComboBox.Click;
begin
  if not Enabled then Exit;
  inherited Click;
  { If dropped down, close. Otherwise open — but guard the reopen race:
    clicking the combo while it is open fires FormDeactivate→FPopup.Close→
    PopupClosed BEFORE this Click handler runs, so DroppedDown is already False
    here. We suppress reopen if CloseUp happened within the last 200 ms.
    FCloseUpTick is mirrored from FPopup.CloseUpTick in PopupClosed. }
  if DroppedDown then
    CloseUp
  else if GetTickCount64 - FCloseUpTick > 200 then
    DropDown;
end;

procedure TTyComboBox.KeyDown(var Key: Word; Shift: TShiftState);
var Cnt: Integer;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and DroppedDown then
  begin
    CloseUp; Key := 0; Exit;
  end;
  { Alt+Down or F4 toggles the dropdown. Must precede the plain VK_DOWN case. }
  if ((Key = VK_DOWN) and (ssAlt in Shift)) or (Key = VK_F4) then
  begin
    if DroppedDown then CloseUp else DropDown;
    Key := 0; Exit;
  end;
  Cnt := FItems.Count;
  if Cnt = 0 then Exit;
  case Key of
    VK_DOWN:
      begin
        if FItemIndex < 0 then UserSelect(0)
        else if FItemIndex < Cnt - 1 then UserSelect(FItemIndex + 1);
        Key := 0;
      end;
    VK_UP:
      begin
        if FItemIndex < 0 then UserSelect(0)
        else if FItemIndex > 0 then UserSelect(FItemIndex - 1);
        Key := 0;
      end;
    VK_HOME: begin UserSelect(0); Key := 0; end;
    VK_END:  begin UserSelect(Cnt - 1); Key := 0; end;
  end;
end;

procedure TTyComboBox.UTF8KeyPress(var UTF8Key: TUTF8Char);
var nowTick: QWord; hit: Integer;
begin
  if not Enabled then Exit;
  inherited UTF8KeyPress(UTF8Key);
  if (UTF8Key = '') or (UTF8Key[1] < #32) then Exit;
  nowTick := GetTickCount64;
  if nowTick - FTypeAheadTick > 600 then FTypeAhead := '';   // restart after a pause
  FTypeAheadTick := nowTick;
  FTypeAhead := FTypeAhead + UTF8Key;
  hit := TyComboTypeAheadMatch(FItems, FItemIndex, FTypeAhead);
  if hit >= 0 then UserSelect(hit);
end;

{ Popup event handlers }

procedure TTyComboBox.PopupListChange(Sender: TObject);
begin
  { User clicked / chose a row in the popup list -> a user-driven selection.
    Defer the close: hiding the popup synchronously here — still inside the list's
    click handler — leaves LCL's click-completion focus path pointing at the
    now-hidden popup form, raising EInvalidOperation
    '[TCustomForm.SetFocus] ... Can not focus'. Closing on the next message cycle
    lets the click finish first. }
  UserSelect(FPopupList.ItemIndex);
  Application.QueueAsyncCall(@DeferredCloseUp, 0);
end;

procedure TTyComboBox.DeferredCloseUp(Data: PtrInt);
begin
  CloseUp;
end;

{ Called by TTyDropdownPopup.OnClose when the popup hides (click-away, Escape,
  or programmatic FPopup.Close).  This is the single bookkeeping point. }
procedure TTyComboBox.PopupClosed(Sender: TObject);
begin
  { Mirror the helper's close-up tick into the protected field so test subclasses
    (e.g. AgeCloseUpTick) and the Click guard can use it without touching FPopup. }
  if FPopup <> nil then
    FCloseUpTick := FPopup.CloseUpTick;
  Invalidate;
  DoCloseUp;
end;

procedure TTyComboBox.PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    CloseUp;
    Key := 0;
  end;
end;

{ Protected accessor for headless tests }
function TTyComboBox.PopupList: TTyListBox;
begin
  Result := FPopupList;
end;

procedure TTyComboBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, TextR, BtnR: TRect;
  BtnW: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Types.Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    BtnW := P.Scale(ButtonWidthLogical);
    BtnR := Types.Rect(R.Right - BtnW, R.Top, R.Right, R.Bottom);
    // Content honours the resolved Padding (consistent with Button/Edit/Panel);
    // the right edge stops at the chevron button zone.
    TextR := Types.Rect(R.Left + P.Scale(S.Padding.Left), R.Top + P.Scale(S.Padding.Top),
      R.Right - BtnW, R.Bottom - P.Scale(S.Padding.Bottom));
    if FText <> '' then
      P.DrawText(TextR, FText, S.FontName, S.FontSize, S.FontWeight,
        S.TextColor, taLeftJustify, tlCenter, True);
    P.DrawGlyph(BtnR, tgChevronDown, S.TextColor, 2);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyComboBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
