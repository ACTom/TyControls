unit tyControls.ComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, StdCtrls, LCLType, LCLIntf,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.ListBox, tyControls.QtWS;
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
    FPopup: TForm;           // lazy; created on first DropDown; freed in Destroy
    FPopupList: TTyListBox;  // owned by FPopup
    FPopupRect: TRect;       // computed screen rect of the last DropDown (for the deferred Qt re-apply)
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
    procedure PopupDeactivate(Sender: TObject);
    procedure PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DeferredCloseUp(Data: PtrInt);
    { Qt/X11 re-places + un-masks a frameless window at MAP time (after Show); re-assert the
      dropdown's bounds + region next event-loop turn, once the native window has settled. }
    procedure DeferredReapplyGeometry(Data: PtrInt);
    { Shape the borderless popup window with a rounded region so the opaque
      rectangular corners outside the themed rounded fill are clipped away. The
      radius tracks the dropdown list's own resolved BorderRadius, scaled to the
      popup's device PPI. No-op when the radius is 0 (leave rectangular) or off
      Windows. Re-applied on every DropDown so it follows a new size/PPI/theme. }
    procedure ApplyPopupRegion(AWidth, AHeight: Integer);
  protected
    { Guard: tick at last CloseUp. Click reopens only if > 200ms have passed.
      This prevents the click-while-open reopen race where PopupDeactivate fires
      CloseUp BEFORE Click runs, so Click would see DroppedDown=False and reopen.
      Protected so test subclasses can manipulate it for headless logic tests. }
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
  // Rounded popup corners use the CROSS-PLATFORM LCLIntf SetWindowRgn/CreateRoundRectRgn (win32/
  // gtk2/qt all implement them) — no Windows unit. (Rect()/Point() call sites stay qualified Types.*.)
  Math;

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
  FPopup := nil;
  FPopupList := nil;
  TabStop := True;
  Width := 145;
  Height := 26;
end;

destructor TTyComboBox.Destroy;
begin
  { Cancel any queued DeferredCloseUp so it can't fire into a freed combo. }
  Application.RemoveAsyncCalls(Self);
  { Free popup (and its owned listbox) if it was ever created.
    We must detach the OnDeactivate handler first to avoid re-entering CloseUp
    from the TForm destruction path. }
  if FPopup <> nil then
  begin
    FPopup.OnDeactivate := nil;
    FreeAndNil(FPopup);
    FPopupList := nil;  // freed by FPopup (was owned by it)
  end;
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
  Result := (FPopup <> nil) and FPopup.Visible;
end;

{ Ensure the popup form and its TTyListBox child exist.
  Called lazily on first DropDown. }
procedure TTyComboBox.DropDown;
var
  PopupH, PopupW: Integer;
  P: TPoint;
  ParentForm: TCustomForm;
begin
  if FItems.Count = 0 then Exit;

  { Lazily create the popup form + listbox }
  if FPopup = nil then
  begin
    FPopup := TForm.CreateNew(nil);
    FPopup.BorderStyle := bsNone;
    FPopup.ShowInTaskBar := stNever;
    FPopup.FormStyle := fsStayOnTop;

    ParentForm := GetParentForm(Self);
    if ParentForm <> nil then
    begin
      FPopup.PopupParent := ParentForm;
      FPopup.PopupMode := pmExplicit;
    end;

    FPopup.KeyPreview := True;
    FPopup.OnDeactivate := @PopupDeactivate;
    FPopup.OnKeyDown := @PopupKeyDown;

    FPopupList := TTyListBox.Create(FPopup);
    FPopupList.Parent := FPopup;
    FPopupList.Align := alClient;
    FPopupList.OnChange := @PopupListChange;
  end;

  { Sync controller every DropDown so DPI/theme changes take effect }
  FPopupList.Controller := Self.Controller;

  { Sync items and selection — detach OnChange to prevent recursion }
  FPopupList.OnChange := nil;
  FPopupList.Items.Assign(FItems);
  { Use the private field path via SelectItem with temp guard:
    SelectItem won't fire our nil'd OnChange anyway }
  FPopupList.SelectItem(FItemIndex);
  FPopupList.OnChange := @PopupListChange;

  { Size: height = min(DropDownCount, Items.Count) rows (+ frame chrome).
    Shared with the headless ComputePopupHeight so sizing cannot drift. }
  PopupH := ComputePopupHeight(Font.PixelsPerInch);
  PopupW := Width;

  { Position below the combo }
  P := ControlToScreen(Types.Point(0, Height));
  FPopupRect := Types.Rect(P.X, P.Y, P.X + PopupW, P.Y + PopupH);
  FPopup.SetBounds(P.X, P.Y, PopupW, PopupH);

  FPopup.Show;
  TyQtMakePopup(FPopup);   // Qt: re-type as Qt::Popup so the WM positions it (app-driven) + allows the mouse grab
  // Qt/X11 RE-PLACES + un-masks a frameless window at MAP time; re-assert now AND again next
  // event-loop turn (DeferredReapplyGeometry), once the native window settles. No-op on Win32/GTK2.
  FPopup.SetBounds(P.X, P.Y, PopupW, PopupH);
  { Round the popup window's corners to match the dropdown's themed fill, now that
    the handle is allocated by Show. Re-applied here every DropDown so it follows
    the popup's current size, PPI and theme. }
  ApplyPopupRegion(PopupW, PopupH);
  Application.QueueAsyncCall(@DeferredReapplyGeometry, 0);
  DoDropDown;   // popup actually opened
end;

{ Shape the popup window with a rounded region matching the dropdown list's themed
  BorderRadius (scaled to device PPI). On non-Windows this is a graceful no-op. }
procedure TTyComboBox.ApplyPopupRegion(AWidth, AHeight: Integer);
var
  S: TTyStyleSet;
  d: Integer;
  Rgn: HRGN;
begin
  if (FPopup = nil) or (not FPopup.HandleAllocated) then Exit;
  { Resolve the dropdown list's own style so the corner radius tracks the theme.
    The popup hosts a TTyListBox (style key 'TyListBox'); resolve it through the
    combo's active controller (the same theme the popup list paints with). }
  S := ActiveController.Model.ResolveStyle('TyListBox', '', []);
  // Fill the window background with the list surface so the corner gaps OUTSIDE the rounded region
  // are not the dark default form Color (the Linux 'black corners') where a widgetset region no-ops.
  if S.Background.Kind = tfkSolid then
    FPopup.Color := TyColorToLCL(S.Background.Color);
  { Scale the logical BorderRadius to the popup's device PPI; the rounded-rect
    region uses the FULL corner diameter (2 * radius). }
  d := MulDiv(S.BorderRadius, FPopup.Font.PixelsPerInch, 96) * 2;
  if d <= 0 then
  begin
    { Radius 0: leave the window rectangular (clear any region from a prior open). }
    SetWindowRgn(FPopup.Handle, 0, True);
    Exit;
  end;
  { +1 on the extents: CreateRoundRectRgn's right/bottom are exclusive. SetWindowRgn takes ownership
    of Rgn; do not delete it. LCLIntf routes it: win32 native / gtk2 shape-combine / qt setMask. }
  Rgn := CreateRoundRectRgn(0, 0, AWidth + 1, AHeight + 1, d, d);
  SetWindowRgn(FPopup.Handle, Rgn, True);
end;

procedure TTyComboBox.CloseUp;
begin
  if (FPopup <> nil) and FPopup.Visible then
  begin
    { Detach deactivate to prevent re-entering CloseUp from Hide }
    FPopup.OnDeactivate := nil;
    FPopup.Hide;
    FPopup.OnDeactivate := @PopupDeactivate;
  end;
  FCloseUpTick := GetTickCount64;
  Invalidate;
  DoCloseUp;   // dropdown closed
end;

procedure TTyComboBox.Click;
begin
  if not Enabled then Exit;
  inherited Click;
  { If dropped down, close. Otherwise open — but guard the reopen race:
    clicking the combo while it is open fires PopupDeactivate→CloseUp BEFORE
    this Click handler runs, so DroppedDown is already False here. We suppress
    reopen if CloseUp happened within the last 200 ms. }
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

procedure TTyComboBox.DeferredReapplyGeometry(Data: PtrInt);
begin
  // One event-loop turn after Show, by when Qt's map-time reparent/flag churn has settled — so this
  // SetBounds + region finally stick (harmless re-assert on Win32/GTK2).
  if (FPopup = nil) or (not FPopup.Visible) then Exit;
  FPopup.SetBounds(FPopupRect.Left, FPopupRect.Top,
    FPopupRect.Right - FPopupRect.Left, FPopupRect.Bottom - FPopupRect.Top);
  ApplyPopupRegion(FPopupRect.Right - FPopupRect.Left, FPopupRect.Bottom - FPopupRect.Top);
end;

procedure TTyComboBox.DeferredCloseUp(Data: PtrInt);
begin
  CloseUp;
end;

procedure TTyComboBox.PopupDeactivate(Sender: TObject);
begin
  CloseUp;
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
