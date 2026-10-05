unit tyControls.TabSet;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, tyControls.TabStrip;
type
  { TTyTabSet — a pure tab strip (no page container) on the SP1 TTyCustomTabStrip
    header engine. Captions live in a TStrings; selection = TabIndex + OnChange. }
  TTyCustomTabSet = class(TTyCustomTabStrip)
  private
    { Backed by a TStringList (for its OnChange), but typed TStrings so the
      published Tabs field-read property matches its declared type. }
    FTabs: TStrings;
    procedure SetTabs(AValue: TStrings);
    procedure TabsListChanged(Sender: TObject);
  protected
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
    property OnTabClose;
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
  FTabs := TStringList.Create;
  TStringList(FTabs).OnChange := @TabsListChanged;
  Width := 240; Height := 32;
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
  // Selection stays pinned to the POSITION, not the moved tab (matches TTyPageControl.DoReorderTabs — FTabIndex unadjusted).
  if (AFrom >= 0) and (AFrom < FTabs.Count) and (ATo >= 0) and (ATo < FTabs.Count) then
  begin
    TStringList(FTabs).OnChange := nil;
    FTabs.Move(AFrom, ATo);
    TStringList(FTabs).OnChange := @TabsListChanged;
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
  if FTabs.Count = 0 then want := -1
  else if want > FTabs.Count - 1 then want := FTabs.Count - 1;
  if want <> FTabIndex then
    SetTabIndex(want)
  else
    // Removing the selected tab (not last): TabIndex is numerically unchanged, so — for a caption-only strip keyed on index — we intentionally do NOT fire OnChange (only the underlying caption changed). Repaint only.
    TabsChanged;
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

procedure TTyCustomTabSet.TabsListChanged(Sender: TObject);
begin
  // Only the upper bound is clamped. A direct Tabs.Delete BELOW the selection shifts the highlight by one (bare TStringList.OnChange carries no index) — the close-button path goes through RemoveTabData which handles it; direct Tabs edits below the selection are a known, uncommon desync.
  if FTabIndex > FTabs.Count - 1 then FTabIndex := FTabs.Count - 1;
  TabsChanged;
end;

function TTyCustomTabSet.TabCountForTest: Integer; begin Result := GetTabCount; end;
function TTyCustomTabSet.TabCaptionForTest(AIndex: Integer): string; begin Result := GetTabCaption(AIndex); end;
procedure TTyCustomTabSet.RemoveTabForTest(AIndex: Integer); begin RemoveTabData(AIndex); end;
function TTyCustomTabSet.StyleTypeKeyForTest: string; begin Result := GetStyleTypeKey; end;

initialization
  RegisterClass(TTyTabSet);
end.
