unit tyControls.TabSet;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, tyControls.TabStrip;
type
  { TTyTabSet — a pure tab strip (no page container) on the SP1 TTyCustomTabStrip
    header engine. Captions live in a TStrings; selection = TabIndex + OnChange. }
  TTyTabSet = class(TTyCustomTabStrip)
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
  published
    property Tabs: TStrings read FTabs write SetTabs;
    property TabIndex: Integer read FTabIndex write SetTabIndex default -1;
  end;
implementation

constructor TTyTabSet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTabs := TStringList.Create;
  TStringList(FTabs).OnChange := @TabsListChanged;
  Width := 240; Height := 32;
end;

destructor TTyTabSet.Destroy;
begin
  FTabs.Free;
  inherited Destroy;
end;

function TTyTabSet.GetStyleTypeKey: string;
begin
  Result := 'TyTabControl';
end;

function TTyTabSet.HasPageBody: Boolean;
begin
  Result := False;
end;

function TTyTabSet.GetTabCount: Integer;
begin
  Result := FTabs.Count;
end;

function TTyTabSet.GetTabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FTabs.Count) then Result := FTabs[AIndex] else Result := '';
end;

procedure TTyTabSet.DoSelectTab(AIndex: Integer);
begin
  Invalidate;
end;

procedure TTyTabSet.DoReorderTabs(AFrom, ATo: Integer);
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

procedure TTyTabSet.RemoveTabData(AIndex: Integer);
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

procedure TTyTabSet.SetTabs(AValue: TStrings);
begin
  FTabs.Assign(AValue);
end;

procedure TTyTabSet.TabsListChanged(Sender: TObject);
begin
  // Only the upper bound is clamped. A direct Tabs.Delete BELOW the selection shifts the highlight by one (bare TStringList.OnChange carries no index) — the close-button path goes through RemoveTabData which handles it; direct Tabs edits below the selection are a known, uncommon desync.
  if FTabIndex > FTabs.Count - 1 then FTabIndex := FTabs.Count - 1;
  TabsChanged;
end;

function TTyTabSet.TabCountForTest: Integer; begin Result := GetTabCount; end;
function TTyTabSet.TabCaptionForTest(AIndex: Integer): string; begin Result := GetTabCaption(AIndex); end;
procedure TTyTabSet.RemoveTabForTest(AIndex: Integer); begin RemoveTabData(AIndex); end;
function TTyTabSet.StyleTypeKeyForTest: string; begin Result := GetStyleTypeKey; end;

initialization
  RegisterClass(TTyTabSet);
end.
