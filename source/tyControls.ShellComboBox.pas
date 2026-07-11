unit tyControls.ShellComboBox;

{ A "look in" combo: the field shows the current directory's clean label, and the
  drop-down lists the directory's breadcrumb ancestor chain (root -> current, indented
  by depth) followed by the other roots (drives / places). Picking a row navigates the
  host to that directory.

  Locked to csDropDownList (pick-only): an editable csDropDown popup prefix-FILTERS its
  rows, so the visible row index would no longer line up with the model array (the
  ColorBox lesson). Each row carries its 0-based model index in Items.Objects[]
  (TObject(PtrInt(i))); the picked path is read back through it.

  No icons in the drop-down (a deliberate simplification): hierarchy is expressed by
  leading-space indentation only. A file dialog that needs folder/drive glyphs adds them
  separately. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics,
  tyControls.Types, tyControls.Painter,
  tyControls.ComboBox, tyControls.FileSystem;

type
  { One look-in row: a navigable Path, a friendly Display label, and its Depth in the
    breadcrumb chain (0 = a root; other roots appended after the chain are also Depth 0). }
  TTyLookInPlace = record
    Path, Display: string;
    Depth: Integer;
  end;
  TTyLookInPlaceArray = array of TTyLookInPlace;

{ The look-in rows for directory ADir: first the breadcrumb chain (TyFsBreadcrumb, one
  row per crumb, Depth 0..N), then every TyFsRoots root whose Path differs from the
  chain's own root crumb (so the current drive/root is not listed twice), each Depth 0.

  Each crumb's Display is a friendly label: the matching TyFsRoots.Display when a root's
  Path SameFileName's the crumb; else ExtractFileName(ExcludeTrailingPathDelimiter(crumb));
  else the crumb verbatim (a bare drive root 'C:\'). ADir = '' yields only the roots. }
function TyLookInPlaces(const ADir: string): TTyLookInPlaceArray;

type
  TTyShellComboBox = class(TTyComboBox)
  private
    FDirectory: string;             { current directory, trailing-separator-normalised }
    FPlaces: TTyLookInPlaceArray;   { the model behind the current Items; row <-> Objects[]=PtrInt(index) }
    FUpdating: Boolean;             { set while SetDirectory rebuilds Items, so DoSelect
                                      does not misfire OnSelectPath during the repopulate }
    FOnSelectPath: TNotifyEvent;
    procedure SetDirectory(const AValue: string);
  protected
    { A row was committed by the user. Navigate to its path (rebuild + reselect) and fire
      OnSelectPath when the path actually changed. }
    procedure DoSelect; override;
    { Draw the current directory's clean label (no indentation) into the field. }
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    { Always pick-only -- ignore any attempt to make the field editable. }
    procedure SetStyle(AValue: TTyComboBoxStyle); override;
  public
    { The Path of the currently-selected row (via Objects[] -> FPlaces), else FDirectory. }
    function SelectedPath: string;
  published
    { The current directory. Writing it rebuilds the drop-down and selects the current-dir
      row; fires no event. Early-exits when the new path SameFileName's the current one
      (re-entrancy guard: DoSelect -> SetDirectory -> host navigates -> host sets Directory
      back -> must not loop). }
    property Directory: string read FDirectory write SetDirectory;
    { The user picked a place -- the host navigates to SelectedPath. }
    property OnSelectPath: TNotifyEvent read FOnSelectPath write FOnSelectPath;
  end;

implementation

{ A friendly label for APath given a roots snapshot: a matching root's Display, else the
  leaf name, else the path verbatim. Shared by TyLookInPlaces and PaintFieldContent. }
function TyLookInLabelFor(const APath: string; const ARoots: TTyFsRootArray): string;
var
  i: Integer;
begin
  for i := 0 to High(ARoots) do
    if SameFileName(ARoots[i].Path, APath) then
      Exit(ARoots[i].Display);
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if Result = '' then
    Result := APath;
end;

function TyLookInPlaces(const ADir: string): TTyLookInPlaceArray;
var
  crumbs: TStringArray;
  roots: TTyFsRootArray;
  i, n: Integer;
  firstCrumb: string;
begin
  Result := nil;
  n := 0;
  crumbs := TyFsBreadcrumb(ADir);
  roots := TyFsRoots;
  { 1. The breadcrumb chain: root -> current, Depth = position in the chain. }
  for i := 0 to High(crumbs) do
  begin
    SetLength(Result, n + 1);
    Result[n].Path := crumbs[i];
    Result[n].Display := TyLookInLabelFor(crumbs[i], roots);
    Result[n].Depth := i;
    Inc(n);
  end;
  { 2. The other roots (Path <> the chain's own root crumb), Depth 0. }
  if Length(crumbs) > 0 then
    firstCrumb := crumbs[0]
  else
    firstCrumb := '';
  for i := 0 to High(roots) do
  begin
    if (firstCrumb <> '') and SameFileName(roots[i].Path, firstCrumb) then
      Continue;
    SetLength(Result, n + 1);
    Result[n].Path := roots[i].Path;
    Result[n].Display := roots[i].Display;
    Result[n].Depth := 0;
    Inc(n);
  end;
end;

{ TTyShellComboBox }

function TTyShellComboBox.SelectedPath: string;
var
  modelIdx: Integer;
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
  begin
    modelIdx := PtrInt(Items.Objects[ItemIndex]);
    if (modelIdx >= 0) and (modelIdx <= High(FPlaces)) then
      Exit(FPlaces[modelIdx].Path);
  end;
  Result := FDirectory;
end;

procedure TTyShellComboBox.SetDirectory(const AValue: string);
var
  p2: string;
  i, sel: Integer;
begin
  p2 := ExcludeTrailingPathDelimiter(Trim(AValue));
  { Re-entrancy guard: navigating back to the same directory must not rebuild + loop. }
  if SameFileName(p2, FDirectory) then
    Exit;
  FDirectory := p2;
  FUpdating := True;
  try
    FPlaces := TyLookInPlaces(p2);
    Items.Clear;
    for i := 0 to High(FPlaces) do
      Items.AddObject(StringOfChar(' ', 2 * FPlaces[i].Depth) + FPlaces[i].Display,
        TObject(PtrInt(i)));
    { Select the row whose Path is the current directory (the last breadcrumb); -1 if none. }
    sel := -1;
    for i := 0 to High(FPlaces) do
      if SameFileName(FPlaces[i].Path, FDirectory) then
      begin
        sel := i;
        Break;
      end;
    ItemIndex := sel;
  finally
    FUpdating := False;
  end;
  Invalidate;
end;

procedure TTyShellComboBox.DoSelect;
var
  modelIdx: Integer;
  picked: string;
begin
  inherited DoSelect;   { preserve base OnSelect semantics }
  if FUpdating then
    Exit;
  if (ItemIndex < 0) or (ItemIndex >= Items.Count) then
    Exit;
  modelIdx := PtrInt(Items.Objects[ItemIndex]);
  if (modelIdx < 0) or (modelIdx > High(FPlaces)) then
    Exit;
  picked := FPlaces[modelIdx].Path;
  if not SameFileName(picked, FDirectory) then
  begin
    SetDirectory(picked);   { rebuild; its own early-exit prevents a second pass }
    if Assigned(FOnSelectPath) then
      FOnSelectPath(Self);
  end;
end;

procedure TTyShellComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect;
  const AStyle: TTyStyleSet);
var
  lbl: string;
begin
  if FDirectory = '' then
  begin
    inherited PaintFieldContent(P, ATextRect, AStyle);
    Exit;
  end;
  lbl := TyLookInLabelFor(FDirectory, TyFsRoots);
  P.DrawText(ATextRect, lbl, AStyle.FontName, AStyle.FontSize, AStyle.FontWeight,
    AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

procedure TTyShellComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  { Pick-only: a filtered editable popup would desync the row<->place mapping. }
  inherited SetStyle(csDropDownList);
end;

initialization
  { So a .lfm that streams a TTyShellComboBox resolves the class. }
  RegisterClass(TTyShellComboBox);

end.
