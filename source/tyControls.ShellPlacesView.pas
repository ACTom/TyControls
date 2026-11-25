unit tyControls.ShellPlacesView;

{ #246. The PLACES pane of the file dialogs: a flat list of folders one click away, under
  headings -- the common folders, the drives, what the application pinned, where the user
  was last. What every current platform dialog has on its left, in place of a folder tree.

  It shows a TTyFilePlaces list (tyControls.ShellPlaces) and is a list view in everything
  else: one column as wide as the pane, a picture a row, a band a heading (a click on the
  band folds its places away), the keyboard, the scroll bar and the theme of TTyListView.

  CHOOSING. A click on a place chooses it, and so does Enter on the highlighted one:
  SelectedPath is the folder and OnSelectPath says so. The arrow keys only move the
  highlight -- walking down the list does not read a drive per key press.

  FOLLOWING. The host tells the pane where it is with CurrentPath: the place that IS that
  folder is highlighted, and none when the folder is not a place. Writing it fires nothing. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, LCLType,
  tyControls.ListView, tyControls.Columns, tyControls.ImageCollection,
  tyControls.FileSystem, tyControls.ShellPlaces, tyControls.ShellIcons;

type
  TTyCustomShellPlacesView = class(TTyCustomListView)
  private
    FPlaces: TTyFilePlaces;           { owned; a copy of what SetPlaces was given, grouped together }
    FGroupOf: array of Integer;       { per place: the index of its heading in Groups, -1 for none }
    FIcons: TTyImageCollection;       { owned; the place pictures' masters }
    FImages: TTyVirtualImageList;     { owned; what the rows draw from }
    FCurrentPath: string;
    FOnSelectPath: TNotifyEvent;
    procedure Rebuild;
    procedure SetCurrentPath(const AValue: string);
    procedure HighlightCurrent;
    procedure Choose(AIndex: Integer);
  protected
    function GetItemText(AIndex, AColumn: Integer): string; override;
    function GetItemImageIndex(AIndex, AColumn: Integer): Integer; override;
    function GetItemGroup(AItemIndex: Integer): Integer; override;
    { A heading, not a counted bucket: the caption alone. }
    function GroupHeaderCaption(AGroup: Integer): string; override;
    { Enter on the highlighted place chooses it. }
    function ItemActivates(AIndex: Integer): Boolean; override;
    procedure DoItemActivate(AIndex: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Shows APlaces -- a copy of it, brought together by heading (TTyFilePlaces.GroupTogether)
      -- and highlights the place CurrentPath is, if it is one. nil shows nothing. }
    procedure SetPlaces(APlaces: TTyFilePlaces);
    function PlaceCount: Integer;
    { The AIndex-th place as it is shown, 0 .. PlaceCount - 1. }
    function PlaceAt(AIndex: Integer): TTyFilePlace;
    { The folder of the highlighted place; '' when none is. }
    function SelectedPath: string;
    { The folder the host is showing. The place that is this folder is highlighted, none
      when it is not a place. Fires no event. }
    property CurrentPath: string read FCurrentPath write SetCurrentPath;
    { The pictures the rows draw from (TyAddPlaceIcons). }
    property PlaceImages: TTyVirtualImageList read FImages;
    { The user chose a place -- a click, or Enter on the highlighted one -- that is not the
      folder the host is in already: go to SelectedPath. }
    property OnSelectPath: TNotifyEvent read FOnSelectPath write FOnSelectPath;
  end;

  { TTyShellPlacesView publishes TTyCustomShellPlacesView's properties; everything lives in
    TTyCustomShellPlacesView. Not on the component palette: the file dialogs build it. }
  TTyShellPlacesView = class(TTyCustomShellPlacesView)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnContextPopup;
    property OnResize;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property OnKeyDown;
    property OnKeyUp;
    property OnEnter;
    property OnExit;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property RowHeight;
    property HotTrack;
    property ScrollBarAutoHide;
    property Align;
    property Anchors;
    property OnSelectPath;
  end;

implementation

uses
  LazFileUtils;

constructor TTyCustomShellPlacesView.Create(AOwner: TComponent);
var
  c: TTyColumn;
begin
  inherited Create(AOwner);
  FPlaces := TTyFilePlaces.Create;

  { The rows are FPlaces, read through the four Get* overrides. }
  OwnerData := True;
  { One column, as wide as the pane, under no column header. }
  c := Header.Columns.Add as TTyColumn;
  c.Text := '';
  c.Width := 160;
  Header.AutoSizeIndex := 0;
  Header.Options := [hoAutoResize];   // and no hoVisible: no column header
  GroupView := True;
  HotTrack := True;

  { Ownerless, freed in the destructor: the image list's FreeNotification clears the
    inherited SmallImages reference, as in the shell list. }
  FIcons := TTyImageCollection.Create(nil);
  FImages := TTyVirtualImageList.Create(nil);
  FImages.Collection := FIcons;
  TyAddPlaceIcons(FIcons, FImages.Names);
  SmallImages := FImages;
end;

destructor TTyCustomShellPlacesView.Destroy;
begin
  FImages.Free;
  FIcons.Free;
  FPlaces.Free;
  inherited Destroy;
end;

procedure TTyCustomShellPlacesView.SetPlaces(APlaces: TTyFilePlaces);
begin
  FPlaces.Assign(APlaces);
  FPlaces.GroupTogether;
  Rebuild;
end;

procedure TTyCustomShellPlacesView.Rebuild;
var
  heads: TStringArray;
  i, g: Integer;
begin
  heads := FPlaces.Groups;
  BeginUpdate;
  try
    Groups.Clear;
    for g := 0 to High(heads) do
      Groups.Add.Caption := heads[g];
    SetLength(FGroupOf, FPlaces.Count);
    for i := 0 to FPlaces.Count - 1 do
    begin
      FGroupOf[i] := -1;
      for g := 0 to High(heads) do
        if heads[g] = FPlaces[i].Group then
        begin
          FGroupOf[i] := g;
          Break;
        end;
    end;
    ItemCount := FPlaces.Count;
  finally
    EndUpdate;   // lays the list out afresh, whatever did or did not change in between
  end;
  HighlightCurrent;
end;

function TTyCustomShellPlacesView.PlaceCount: Integer;
begin
  Result := FPlaces.Count;
end;

function TTyCustomShellPlacesView.PlaceAt(AIndex: Integer): TTyFilePlace;
begin
  Result := FPlaces[AIndex];
end;

function TTyCustomShellPlacesView.SelectedPath: string;
begin
  if (ItemIndex >= 0) and (ItemIndex < FPlaces.Count) then
    Result := FPlaces[ItemIndex].Path
  else
    Result := '';
end;

procedure TTyCustomShellPlacesView.SetCurrentPath(const AValue: string);
begin
  FCurrentPath := ChompPathDelim(Trim(AValue));   // a root keeps its delimiter
  HighlightCurrent;
end;

procedure TTyCustomShellPlacesView.HighlightCurrent;
begin
  ItemIndex := FPlaces.IndexOf(FCurrentPath);   // -1 when it is not a place: none highlighted
end;

procedure TTyCustomShellPlacesView.Choose(AIndex: Integer);
var
  path: string;
begin
  if (AIndex < 0) or (AIndex >= FPlaces.Count) then Exit;
  path := FPlaces[AIndex].Path;
  { The folder the host is in already: nothing to go to. (The second click of a double
    click lands here.) }
  if CompareFilenames(path, FCurrentPath) = 0 then Exit;
  FCurrentPath := path;
  if Assigned(FOnSelectPath) then FOnSelectPath(Self);
end;

function TTyCustomShellPlacesView.GetItemText(AIndex, AColumn: Integer): string;
begin
  if (AColumn = 0) and (AIndex >= 0) and (AIndex < FPlaces.Count) then
    Result := FPlaces[AIndex].Caption
  else
    Result := '';
end;

function TTyCustomShellPlacesView.GetItemImageIndex(AIndex, AColumn: Integer): Integer;
begin
  if (AColumn = 0) and (AIndex >= 0) and (AIndex < FPlaces.Count) then
    Result := TyPlaceIconIndex(FPlaces[AIndex].Icon)
  else
    Result := -1;
end;

function TTyCustomShellPlacesView.GetItemGroup(AItemIndex: Integer): Integer;
begin
  if (AItemIndex >= 0) and (AItemIndex <= High(FGroupOf)) then
    Result := FGroupOf[AItemIndex]
  else
    Result := -1;
end;

function TTyCustomShellPlacesView.GroupHeaderCaption(AGroup: Integer): string;
begin
  Result := Groups[AGroup].Caption;
end;

function TTyCustomShellPlacesView.ItemActivates(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < FPlaces.Count);
end;

procedure TTyCustomShellPlacesView.DoItemActivate(AIndex: Integer);
begin
  Choose(AIndex);
  inherited DoItemActivate(AIndex);
end;

procedure TTyCustomShellPlacesView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button = mbLeft) and IsEnabled then
    Choose(GetItemAt(X, Y));   // -1 on a heading or below the last place: nothing chosen
end;

end.
