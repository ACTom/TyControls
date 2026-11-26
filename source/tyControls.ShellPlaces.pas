unit tyControls.ShellPlaces;

{ #246. The PLACES a file dialog offers: the folders one click away in its left pane and in
  its folder drop-down. A flat list -- each place a folder, the name it is listed under, the
  heading it is listed below and its picture -- which the dialog fills with the standard
  places and then hands to the application (OnPlaces) to add to, remove from or reorder.

  Headless: no control, no canvas. The pane that shows the list is TTyShellPlacesView. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LazFileUtils,
  tyControls.FileSystem, tyControls.StrConsts;

type
  { One place. }
  TTyFilePlace = record
    Path: string;            // the folder; no trailing delimiter, except on a root
    Caption: string;         // what it is listed as
    Group: string;           // the heading it is listed under; '' = under no heading
    Icon: TTyFsPlaceIcon;    // its picture; never fpiByKind
  end;

  { The list. Order matters twice: places are listed in this order under their heading, and
    the headings in the order each is first met. }
  TTyFilePlaces = class
  private
    FItems: array of TTyFilePlace;
    function GetItem(AIndex: Integer): TTyFilePlace;
    procedure SetItem(AIndex: Integer; const AValue: TTyFilePlace);
    procedure CheckIndex(AIndex: Integer);
  public
    function Count: Integer;
    procedure Clear;
    { Appends a place and returns its index. AGroup is the heading it goes under -- one of
      the dialog's own (rsFdGroupPlaces, rsFdGroupDevices, rsFdGroupPinned, rsFdGroupRecent in
      tyControls.StrConsts) or any text of the application's, which then is a heading of its
      own; '' lists it under no heading, after the rest. ACaption '' is the folder's own name.
      A trailing delimiter is removed. Nothing is looked up on disk and a folder already
      listed is listed again: what the list holds is the caller's business. }
    function Add(const APath: string; const AGroup: string = ''; const ACaption: string = '';
      AIcon: TTyFsPlaceIcon = fpiFolder): Integer;
    { The same at AIndex (0 .. Count). }
    procedure Insert(AIndex: Integer; const APath: string; const AGroup: string = '';
      const ACaption: string = ''; AIcon: TTyFsPlaceIcon = fpiFolder);
    procedure Delete(AIndex: Integer);
    procedure Move(AFrom, ATo: Integer);
    { The first place whose folder is APath, as file names compare; -1 when there is none. }
    function IndexOf(const APath: string): Integer;
    procedure Assign(ASource: TTyFilePlaces);
    { The headings as they are shown: each Group once, in the order it is first met, the
      places under no heading ('') not among them. }
    function Groups: TStringArray;
    { Brings the places of each heading together, in the order Groups gives and with the
      places under no heading last, without changing the order within a heading: the order
      the list is SHOWN in. }
    procedure GroupTogether;
    property Items[AIndex: Integer]: TTyFilePlace read GetItem write SetItem; default;
  end;

  { The dialog has listed its places and is about to show them: APlaces is the application's
    to change. Sender is the dialog component. }
  TTyFilePlacesEvent = procedure(Sender: TObject; APlaces: TTyFilePlaces) of object;

{ What a place is listed as when nothing says otherwise: the folder's own name, and for a
  root, which has none, the root's name -- 'C:', as the Devices group lists it (TyFsRootName,
  #250). It was the root's path, 'C:\'. }
function TyFilePlaceCaption(const APath: string): string;

{ The places every dialog lists first, pure: the home folder -- each rkHome entry of ARoots,
  under the name rsFdPlaceHome rather than the folder's own -- and then AKnown, the common
  folders, as they are. The file dialogs list them under rsFdGroupPlaces, the folder picker
  at the top of its tree. }
function TyFsHomeAndKnown(const ARoots, AKnown: TTyFsRootArray): TTyFsRootArray;

{ The standard places, pure -- nothing is looked up on disk, the four inputs are all there is:

    under rsFdGroupPlaces    the home folder (the rkHome entries of ARoots, as rsFdPlaceHome)
                             and then AKnown, the common folders;
    under rsFdGroupPinned    APinned, one folder a line, each once; blank lines skipped;
    under rsFdGroupRecent    ARecent, less the folders the list has under another heading,
                             and no more than ARecentLimit of them;
    under rsFdGroupDevices   the rest of ARoots: drives, the file system's root, volumes.

  The devices come last: a machine may have many, and what the program pinned and where the
  user was last should not be below the fold for it. APinned and ARecent may be nil.
  APlaces is cleared first. }
procedure TyStandardFilePlaces(APlaces: TTyFilePlaces; const AKnown, ARoots: TTyFsRootArray;
  APinned, ARecent: TStrings; ARecentLimit: Integer = MaxInt);

{ The standard places of THIS machine: TyFsKnownFolders and TyFsRoots, APinned less the
  folders that do not exist, and -- with AShowRecent -- the folders of TyRecentFolders that
  exist and are not listed already, TyRecentFoldersLimit of them at most. }
procedure TyFillFilePlaces(APlaces: TTyFilePlaces; APinned: TStrings; AShowRecent: Boolean);

implementation

function TyFilePlaceCaption(const APath: string): string;
begin
  Result := ExtractFileName(ChompPathDelim(APath));
  if Result = '' then Result := TyFsRootName(APath);
end;

{ TTyFilePlaces }

function TTyFilePlaces.Count: Integer;
begin
  Result := Length(FItems);
end;

procedure TTyFilePlaces.Clear;
begin
  FItems := nil;
end;

procedure TTyFilePlaces.CheckIndex(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FItems)) then
    raise EListError.CreateFmt('Place index %d out of bounds (%d)', [AIndex, Length(FItems)]);
end;

function TTyFilePlaces.GetItem(AIndex: Integer): TTyFilePlace;
begin
  CheckIndex(AIndex);
  Result := FItems[AIndex];
end;

procedure TTyFilePlaces.SetItem(AIndex: Integer; const AValue: TTyFilePlace);
begin
  CheckIndex(AIndex);
  FItems[AIndex] := AValue;
  if FItems[AIndex].Icon = fpiByKind then FItems[AIndex].Icon := fpiFolder;
end;

function TTyFilePlaces.Add(const APath, AGroup, ACaption: string; AIcon: TTyFsPlaceIcon): Integer;
begin
  Result := Length(FItems);
  Insert(Result, APath, AGroup, ACaption, AIcon);
end;

procedure TTyFilePlaces.Insert(AIndex: Integer; const APath, AGroup, ACaption: string;
  AIcon: TTyFsPlaceIcon);
var
  i: Integer;
  p: TTyFilePlace;
begin
  if (AIndex < 0) or (AIndex > Length(FItems)) then
    raise EListError.CreateFmt('Place index %d out of bounds (%d)', [AIndex, Length(FItems)]);
  p.Path := ChompPathDelim(Trim(APath));   // a root keeps its delimiter
  if ACaption <> '' then
    p.Caption := ACaption
  else
    p.Caption := TyFilePlaceCaption(p.Path);
  p.Group := AGroup;
  if AIcon = fpiByKind then p.Icon := fpiFolder else p.Icon := AIcon;
  SetLength(FItems, Length(FItems) + 1);
  for i := High(FItems) downto AIndex + 1 do
    FItems[i] := FItems[i - 1];
  FItems[AIndex] := p;
end;

procedure TTyFilePlaces.Delete(AIndex: Integer);
var
  i: Integer;
begin
  CheckIndex(AIndex);
  for i := AIndex to High(FItems) - 1 do
    FItems[i] := FItems[i + 1];
  SetLength(FItems, Length(FItems) - 1);
end;

procedure TTyFilePlaces.Move(AFrom, ATo: Integer);
var
  p: TTyFilePlace;
  i: Integer;
begin
  CheckIndex(AFrom);
  CheckIndex(ATo);
  if AFrom = ATo then Exit;
  p := FItems[AFrom];
  if AFrom < ATo then
    for i := AFrom to ATo - 1 do FItems[i] := FItems[i + 1]
  else
    for i := AFrom downto ATo + 1 do FItems[i] := FItems[i - 1];
  FItems[ATo] := p;
end;

function TTyFilePlaces.IndexOf(const APath: string): Integer;
var
  i: Integer;
  p: string;
begin
  p := ChompPathDelim(Trim(APath));
  for i := 0 to High(FItems) do
    if CompareFilenames(FItems[i].Path, p) = 0 then Exit(i);
  Result := -1;
end;

procedure TTyFilePlaces.Assign(ASource: TTyFilePlaces);
begin
  if ASource = nil then
    FItems := nil
  else
    FItems := Copy(ASource.FItems);
end;

function TTyFilePlaces.Groups: TStringArray;
var
  i, j, n: Integer;
  known: Boolean;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(FItems) do
  begin
    if FItems[i].Group = '' then Continue;
    known := False;
    for j := 0 to n - 1 do
      if Result[j] = FItems[i].Group then
      begin
        known := True;
        Break;
      end;
    if known then Continue;
    SetLength(Result, n + 1);
    Result[n] := FItems[i].Group;
    Inc(n);
  end;
end;

procedure TTyFilePlaces.GroupTogether;
var
  heads: TStringArray;
  sorted: array of TTyFilePlace;
  g, i, n: Integer;
begin
  heads := Groups;
  SetLength(heads, Length(heads) + 1);
  heads[High(heads)] := '';                  // the places under no heading come last
  sorted := nil;
  SetLength(sorted, Length(FItems));
  n := 0;
  for g := 0 to High(heads) do
    for i := 0 to High(FItems) do
      if FItems[i].Group = heads[g] then
      begin
        sorted[n] := FItems[i];
        Inc(n);
      end;
  FItems := sorted;
end;

{ The standard places }

function TyFsHomeAndKnown(const ARoots, AKnown: TTyFsRootArray): TTyFsRootArray;
var
  i, n: Integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(ARoots) do
    if ARoots[i].Kind = rkHome then
    begin
      SetLength(Result, n + 1);
      Result[n] := ARoots[i];
      Result[n].Display := rsFdPlaceHome;
      Inc(n);
    end;
  SetLength(Result, n + Length(AKnown));
  for i := 0 to High(AKnown) do
    Result[n + i] := AKnown[i];
end;

procedure TyStandardFilePlaces(APlaces: TTyFilePlaces; const AKnown, ARoots: TTyFsRootArray;
  APinned, ARecent: TStrings; ARecentLimit: Integer);
var
  i, k, firstPinned, shown: Integer;
  p: string;
  isRoot: Boolean;
  first: TTyFsRootArray;

  { Whether p is among the places from AFrom on. }
  function ListedFrom(AFrom: Integer): Boolean;
  var
    k: Integer;
  begin
    for k := AFrom to APlaces.Count - 1 do
      if CompareFilenames(APlaces[k].Path, p) = 0 then Exit(True);
    Result := False;
  end;

begin
  APlaces.Clear;
  first := TyFsHomeAndKnown(ARoots, AKnown);
  for i := 0 to High(first) do
    APlaces.Add(first[i].Path, rsFdGroupPlaces, first[i].Display, TyFsPlaceIconOf(first[i]));
  firstPinned := APlaces.Count;
  if APinned <> nil then
    for i := 0 to APinned.Count - 1 do
    begin
      p := ChompPathDelim(Trim(APinned[i]));
      { A pinned folder is listed though it is a place above too -- the program asked for
        it by name -- but not twice among the pinned. }
      if (p = '') or ListedFrom(firstPinned) then Continue;
      APlaces.Add(p, rsFdGroupPinned);
    end;
  shown := 0;
  if ARecent <> nil then
    for i := 0 to ARecent.Count - 1 do
    begin
      if shown >= ARecentLimit then Break;
      p := ChompPathDelim(Trim(ARecent[i]));
      if (p = '') or ListedFrom(0) then Continue;
      isRoot := False;
      for k := 0 to High(ARoots) do
        if CompareFilenames(ChompPathDelim(ARoots[k].Path), p) = 0 then isRoot := True;
      if isRoot then Continue;   // listed below, among the devices
      APlaces.Add(p, rsFdGroupRecent);
      Inc(shown);
    end;
  for i := 0 to High(ARoots) do
    if ARoots[i].Kind <> rkHome then
      APlaces.Add(ARoots[i].Path, rsFdGroupDevices, ARoots[i].Display, TyFsPlaceIconOf(ARoots[i]));
end;

procedure TyFillFilePlaces(APlaces: TTyFilePlaces; APinned: TStrings; AShowRecent: Boolean);
var
  pinned, recent: TStringList;
  src: TStrings;
  i: Integer;
  p: string;
begin
  pinned := TStringList.Create;
  recent := TStringList.Create;
  try
    if APinned <> nil then
      for i := 0 to APinned.Count - 1 do
      begin
        p := ChompPathDelim(Trim(APinned[i]));
        if (p <> '') and DirectoryExistsUTF8(p) then pinned.Add(p);
      end;
    if AShowRecent then
    begin
      src := TyRecentFolders;
      for i := 0 to src.Count - 1 do
      begin
        p := ChompPathDelim(Trim(src[i]));
        if (p <> '') and DirectoryExistsUTF8(p) then recent.Add(p);
      end;
    end;
    TyStandardFilePlaces(APlaces, TyFsKnownFolders, TyFsRoots, pinned, recent,
      TyRecentFoldersLimit);
  finally
    recent.Free;
    pinned.Free;
  end;
end;

end.
