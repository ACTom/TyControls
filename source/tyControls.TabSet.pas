unit tyControls.TabSet;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, LCLType, Controls, tyControls.Types, tyControls.Base, tyControls.TabStrip;
type
  { TTyTabSet — a pure tab strip (no page container) on the SP1 TTyCustomTabStrip
    header engine. Captions live in a TStrings; selection = TabIndex + OnChange. }
  TTyCustomTabSet = class(TTyCustomTabStrip)
  private
    { Backed by a TStringList (for its OnChange), but typed TStrings so the
      published Tabs field-read property matches its declared type. }
    FTabs: TStrings;
    FTabCaps: array of string;   { #173: Tabs as they were, to keep the selection on its tab }
    procedure SetTabs(AValue: TStrings);
    procedure TabsListChanged(Sender: TObject);
    procedure SnapTabs;
  protected
    { #114: what AutoSize asks for -- see the body. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    function GetStyleTypeKey: string; override;
    { No pages — see the class comment. Without this the header engine would frame
      the area below the tabs as a page container, i.e. an empty box under the strip
      (visible whenever Height > TabHeight). }
    function HasPageBody: Boolean; override;
    { Designer tab clicks select tabs (see TTyCustomTabStrip.CMDesignHitTest). }
    function DesignTabClicksEnabled: Boolean; override;
    function GetTabCount: Integer; override;
    function GetTabCaption(AIndex: Integer): string; override;
    procedure DoSelectTab(AIndex: Integer); override;
    procedure DoReorderTabs(AFrom, ATo: Integer); override;
    procedure RemoveTabData(AIndex: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function TabCountForTest: Integer;
    function TabCaptionForTest(AIndex: Integer): string;
    procedure RemoveTabForTest(AIndex: Integer);
    function StyleTypeKeyForTest: string;
  protected
    property Tabs: TStrings read FTabs write SetTabs;
  public
    { Public, although LCL's TCustomTabControl keeps TabIndex protected (comctrls.pp:471):
      TTyCustomTabStrip already has it public, and a redeclaration cannot take back what an
      ancestor shows -- `TTyCustomTabStrip(ATabSet).TabIndex` reaches it either way (plan
      N16), so a protected one here would only mislead. Redeclared for the RTTI default -1
      that TTyTabSet's published TabIndex inherits. }
    property TabIndex: Integer read FTabIndex write SetTabIndex default -1;
  end;

  { TTyTabSet publishes TTyCustomTabSet's properties; everything lives in TTyCustomTabSet. }
  TTyTabSet = class(TTyCustomTabSet)
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
    property Images;
    property ImagesWidth;
    property OnGetImageIndex;
    property TabHeight;
    property TabsClosable;
    property MiddleClickClose;
    property OnTabClose;
    { Per-tab state -- modified, preview, pinned, hint, ink -- asked of the host tab by tab.
      See TTyTabState in tyControls.TabStrip. }
    property OnGetTabState;
    property OnTabPinClick;
    property OnChange;
    property OnChanging;
    property OnReorder;
    property Align;
    property Anchors;
    property Tabs;
    property TabIndex;
    { Promoted from public on the header engine -- see TTyPageControl.TabPosition for why
      it is published on the concrete strips and not on the shared base. A caption-only
      strip on the left edge is the "sider" shape, which is the main reason to want it. }
    property TabPosition;
    { Promoted for the reason TabPosition is -- see TTyPageControl.MultiLine. A caption-only
      strip is the shape most likely to want folding: it has no page body competing for the
      space, so extra rows cost only the strip's own height. RowCount stays public (read-only,
      so it cannot be published). }
    property MultiLine;
    property RaggedRight;
  end;
implementation

constructor TTyCustomTabSet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFitsToStyle := True;   // AutoSize follows the theme (#114)
  FTabs := TStringList.Create;
  TStringList(FTabs).OnChange := @TabsListChanged;
  Width := 240; Height := 32;
end;

procedure TTyCustomTabSet.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, h: Integer;
begin
  { The bar's own height from the theme, or more when the font needs it; the width stays the
    form's. }
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := PartStyle('TyTab', '', [tysNormal]);
  { #173: a side band asks for its width -- the widest tab -- and leaves the height to the form;
    folded rows ask for all of them. AutoSize sized every band as one row across the top. }
  if BandIsVertical then
  begin
    PreferredWidth := BandThicknessPx;
    PreferredHeight := 0;
    Exit;
  end;
  PreferredWidth := 0;
  PreferredHeight := MulDiv(TabHeight, ppi, 96);
  h := TyFieldPreferredHeight(S, ResolveFontSize(S), ppi);
  if h > PreferredHeight then PreferredHeight := h;
  if HeaderMultiLine and (BandThicknessPx > PreferredHeight) then
    PreferredHeight := BandThicknessPx;
end;

destructor TTyCustomTabSet.Destroy;
begin
  FTabs.Free;
  inherited Destroy;
end;

function TTyCustomTabSet.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyTabControl': 'TyTabControl' names no control at all, and a caption-only strip is not a page container.
    Added to 'TyTabControl's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyTabSet';
end;

function TTyCustomTabSet.HasPageBody: Boolean;
begin
  Result := False;
end;

function TTyCustomTabSet.DesignTabClicksEnabled: Boolean;
begin
  Result := True;
end;

function TTyCustomTabSet.GetTabCount: Integer;
begin
  Result := FTabs.Count;
end;

function TTyCustomTabSet.GetTabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FTabs.Count) then Result := FTabs[AIndex] else Result := '';
end;

procedure TTyCustomTabSet.DoSelectTab(AIndex: Integer);
begin
  Invalidate;
end;

procedure TTyCustomTabSet.DoReorderTabs(AFrom, ATo: Integer);
begin
  { #173: the selection follows its tab, as TTyPageControl's follows its page -- pinned to the
    position, a drag past the selected tab selected another one with no OnChange. }
  if (AFrom >= 0) and (AFrom < FTabs.Count) and (ATo >= 0) and (ATo < FTabs.Count) then
  begin
    TStringList(FTabs).OnChange := nil;
    FTabs.Move(AFrom, ATo);
    TStringList(FTabs).OnChange := @TabsListChanged;
    SnapTabs;
    if FTabIndex = AFrom then
      FTabIndex := ATo
    else if (AFrom < FTabIndex) and (FTabIndex <= ATo) then
      Dec(FTabIndex)
    else if (ATo <= FTabIndex) and (FTabIndex < AFrom) then
      Inc(FTabIndex);
    TabsChanged;
  end;
end;

procedure TTyCustomTabSet.RemoveTabData(AIndex: Integer);
var want: Integer;
begin
  // Base DoCloseClick delegates ALL reconciliation here (mirror TTyPageControl.UnregisterPage).
  // FOnChange is PRIVATE on the base — route the selection change through SetTabIndex.
  if (AIndex < 0) or (AIndex >= FTabs.Count) then Exit;
  want := FTabIndex;
  if AIndex < FTabIndex then Dec(want);
  TStringList(FTabs).OnChange := nil;
  FTabs.Delete(AIndex);
  TStringList(FTabs).OnChange := @TabsListChanged;
  SnapTabs;
  if FTabs.Count = 0 then want := -1
  else if want > FTabs.Count - 1 then want := FTabs.Count - 1;
  if want <> FTabIndex then
    SetTabIndex(want)
  else
  begin
    TabsChanged;
    { #173: the selected tab closed (not the last): the index is the same, the tab is another --
      a change of the selection, and told. }
    if AIndex = FTabIndex then
    begin
      DoSelectTab(FTabIndex);
      NotifyTabChange;
    end;
  end;
  { A vetoing OnChanging handler makes SetTabIndex return without updating
    FTabIndex; the tab data is already gone, so clamp to keep the invariant.
    (When FTabs.Count = 0 this yields -1, which is correct.) }
  if FTabIndex > FTabs.Count - 1 then
    FTabIndex := FTabs.Count - 1;
end;

procedure TTyCustomTabSet.SetTabs(AValue: TStrings);
begin
  FTabs.Assign(AValue);
end;

procedure TTyCustomTabSet.SnapTabs;
var
  i: Integer;
begin
  SetLength(FTabCaps, FTabs.Count);
  for i := 0 to FTabs.Count - 1 do FTabCaps[i] := FTabs[i];
end;

procedure TTyCustomTabSet.TabsListChanged(Sender: TObject);
var
  carry: TTyItemCarry;
  i, want: Integer;
  gone: Boolean;
begin
  { #173: the selection stays on its tab across a Tabs edit -- found by its caption, a renamed one
    by its place (TyCarryItems), so a Delete or an Insert before it no longer moves the highlight
    onto another tab. The selected tab gone, the one now at its place (or the last) is selected.
    Either way the selection changed, and OnChange says so: it was clamped, or left on another
    tab, without a word. }
  carry := TyCarryItems(FTabCaps, FTabs);
  SnapTabs;
  if csLoading in ComponentState then
  begin
    TabsChanged;
    Exit;
  end;
  want := FTabIndex;
  gone := False;
  if FTabIndex >= 0 then
  begin
    want := -1;
    for i := 0 to High(carry) do
      if carry[i] = FTabIndex then want := i;
    if want < 0 then
    begin
      gone := True;
      want := FTabIndex;
      if want > FTabs.Count - 1 then want := FTabs.Count - 1;
    end;
  end;
  if (want = FTabIndex) and not gone then
  begin
    TabsChanged;
    Exit;
  end;
  FTabIndex := want;   { no OnChanging: a tab that is gone cannot be kept }
  DoSelectTab(FTabIndex);
  TabsChanged;
  NotifyTabChange;
end;

function TTyCustomTabSet.TabCountForTest: Integer; begin Result := GetTabCount; end;
function TTyCustomTabSet.TabCaptionForTest(AIndex: Integer): string; begin Result := GetTabCaption(AIndex); end;
procedure TTyCustomTabSet.RemoveTabForTest(AIndex: Integer); begin RemoveTabData(AIndex); end;
function TTyCustomTabSet.StyleTypeKeyForTest: string; begin Result := GetStyleTypeKey; end;

initialization
  RegisterClass(TTyTabSet);
end.
