unit test.propertygrid.fixtures;
{$mode objfpc}{$H+}

{ Fixtures and drivers shared by the property grid suites (#65).

  TPGBasic covers every simple type the grid maps, declared deliberately out of alphabetical order
  (and with one lower-case name) so the ordering guards have something to sort; it has a setter
  that moves another property (AutoGrow -> Width), one that raises (Boom), and a read-only
  property (Fixed).

  TPGGrid drives the control the way the user does: a click on the value cell, the keyboard,
  the dropped list -- and answers the dialogs without opening a modal window. }

interface

uses
  Classes, SysUtils, TypInfo, LCLType, Controls, Graphics, Forms,
  tyControls.ListBox, tyControls.ValueListEditor, tyControls.PropertyGrid;

type
  TPGKind = (pgkOne, pgkTwo, pgkThree);

  TPGBasic = class(TPersistent)
  private
    FZeta: Integer;
    FAlpha: string;
    FBeta: Integer;
    FRatio: Double;
    FSmall: Single;
    FMoney: Currency;
    FWhen: TDateTime;
    FDay: TDate;
    FBig: Int64;
    FHuge: QWord;
    FUnsigned: Cardinal;
    FLetter: Char;
    FWide: WideChar;
    FTitle: UnicodeString;
    FFlag: Boolean;
    FKind: TPGKind;
    FTint: TColor;
    FFixed: Integer;
    FAutoGrow: Boolean;
    FWidth: Integer;
    FBoom: Integer;
    FOnPing: TNotifyEvent;
    procedure SetAutoGrow(AValue: Boolean);
    procedure SetBoom(AValue: Integer);
  public
    BoomTries: Integer;
    constructor Create;
  published
    property Zeta: Integer read FZeta write FZeta;
    property Alpha: string read FAlpha write FAlpha;
    property beta: Integer read FBeta write FBeta;          // lower case on purpose
    property Ratio: Double read FRatio write FRatio;
    property Small: Single read FSmall write FSmall;
    property Money: Currency read FMoney write FMoney;
    property When: TDateTime read FWhen write FWhen;
    property Day: TDate read FDay write FDay;
    property Big: Int64 read FBig write FBig;
    property Huge: QWord read FHuge write FHuge;
    property Unsigned: Cardinal read FUnsigned write FUnsigned;
    property Letter: Char read FLetter write FLetter;
    property Wide: WideChar read FWide write FWide;
    property Title: UnicodeString read FTitle write FTitle;
    property Flag: Boolean read FFlag write FFlag;
    property Kind: TPGKind read FKind write FKind;
    property Tint: TColor read FTint write FTint;
    property Fixed: Integer read FFixed;                     // no setter
    property AutoGrow: Boolean read FAutoGrow write SetAutoGrow;
    property Width: Integer read FWidth write FWidth;
    property Boom: Integer read FBoom write SetBoom;          // the setter raises
    property OnPing: TNotifyEvent read FOnPing write FOnPing;
  end;

  { Publishes a method, so an assigned handler has a name to show. }
  TPGHandlers = class(TPersistent)
  published
    procedure Ping(Sender: TObject);
  end;

  TPGFlag = (pfA, pfB, pfC, pfD);
  TPGFlags = set of TPGFlag;
  TPGSmall = 0..7;
  TPGNums = set of TPGSmall;

  TPGInner = class(TPersistent)
  private
    FLevel: Integer;
    FNote: string;
  published
    property Level: Integer read FLevel write FLevel;
    property Note: string read FNote write FNote;
  end;

  TPGItem = class(TCollectionItem)
  private
    FCaption: string;
    FSize: Integer;
  protected
    function GetDisplayName: string; override;
  published
    property Caption: string read FCaption write FCaption;
    property Size: Integer read FSize write FSize;
  end;

  { Sets (enum and integer-range, with and without a setter), a sub-object with no setter, a
    collection, two TStrings (with and without a setter). }
  TPGHolder = class(TPersistent)
  private
    FFlags: TPGFlags;
    FFixedFlags: TPGFlags;
    FNums: TPGNums;
    FInner: TPGInner;
    FItems: TOwnedCollection;
    FLines: TStringList;
    FNotes: TStringList;
    function GetLines: TStrings;
    function GetNotes: TStrings;
    procedure SetLines(AValue: TStrings);
  public
    LinesSets: Integer;
    constructor Create;
    destructor Destroy; override;
  published
    property Flags: TPGFlags read FFlags write FFlags;
    property FixedFlags: TPGFlags read FFixedFlags;
    property Nums: TPGNums read FNums write FNums;
    property Inner: TPGInner read FInner;
    property Items: TOwnedCollection read FItems;
    property Lines: TStrings read GetLines write SetLines;
    property Notes: TStrings read GetNotes;
  end;

  { A cycle: A.Other = B and B.Other = A. Every read of Other is counted, and a runaway expansion
    is cut off by the getter itself (it raises past LinkReadLimit) so a grid WITHOUT a depth limit
    fails the test instead of overflowing the stack. }
  TPGLink = class(TPersistent)
  private
    FOther: TPGLink;
    FTag: Integer;
    function GetOther: TPGLink;
  public
    procedure Link(AOther: TPGLink);
  published
    property Tag: Integer read FTag write FTag;
    property Other: TPGLink read GetOther;
  end;

  TPGSub = class(TComponent)
  private
    FLevel: Integer;
  published
    property Level: Integer read FLevel write FLevel;
  end;

  { Sub is a csSubComponent (a part of the host); Ref is a reference to another component. }
  TPGHostComp = class(TComponent)
  private
    FSub: TPGSub;
    FRef: TComponent;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Sub: TPGSub read FSub;
    property Ref: TComponent read FRef write FRef;
  end;

  { A property picked from a list whose setter raises: the list must close all the same. }
  TPGTrap = class(TPersistent)
  private
    FMode: TPGKind;
    procedure SetMode(AValue: TPGKind);
  public
    ModeTries: Integer;
  published
    property Mode: TPGKind read FMode write SetMode;
  end;

  { Drives the inline editor the way the keyboard does. }
  TPGEditAccess = class(TTyValueEdit)
  public
    procedure TypeText(const AText: string);
    procedure PressKey(AKey: Word);
    procedure ClickEllipsis;
  end;

  { The control under test, with the user's gestures and the dialogs answered in code. }
  TPGGrid = class(TTyCustomPropertyGrid)
  protected
    function ExecuteFontDialog(AFont: TFont): Boolean; override;
    function ExecuteColorDialog(var AColor: TColor): Boolean; override;
    function ExecuteStringsDialog(const ATitle: string; AStrings: TStrings): Boolean; override;
  public
    FontAnswer: TFont;        // nil = the dialog is cancelled
    ColorAnswer: TColor;
    FontDialogs: Integer;
    StringsAnswer: string;    // what the "strings dialog" leaves in the list
    StringsAccept: Boolean;   // False = cancelled
    StringsDialogs: Integer;
    StringsTitle: string;
    StringsSeen: string;      // the list as the dialog was handed it
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The row at a dotted key path ('Font.Size', 'Items.[0].Caption'). Fails the test if missing. }
    function RowAt(const APath: string): TTyValueRow;
    function HasRow(const APath: string): Boolean;
    { The display position of ARow (expanding its ancestors first). }
    function FlatOf(ARow: TTyValueRow): Integer;
    procedure ClickValue(ARow: TTyValueRow);
    procedure Press(AKey: Word; AShift: TShiftState = []);
    procedure Select(ARow: TTyValueRow);
    function Dropped: TTyListBox;
    { Pick AText from the list the click / F2 dropped. }
    procedure PickFromDropdown(ARow: TTyValueRow; const AText: string);
    function Editor: TPGEditAccess;
    { Click the value cell, type AText over it, press Enter. }
    procedure TypeInto(ARow: TTyValueRow; const AText: string);
    function RootKeys: string;     // the root rows' keys, comma-separated
    { A click on ARow's expand triangle, where the user clicks it. }
    procedure ClickTriangle(ARow: TTyValueRow);
    { The row the selection is on (ItemIndex walked over the expanded rows), nil when none. }
    function CurrentRow: TTyValueRow;
    { csDesigning on and off, as the form designer sets it. }
    procedure DesignMode(AOn: Boolean);
  end;

{ The runner never calls Forms.Application.Initialize; a test that needs window handles does. }
procedure NeedWidgetSet;
var
  LinkReads: Integer = 0;
const
  LinkReadLimit = 400;
{ A shown host form for a control under test (a click focuses, and focusing on a hidden form raises). }
function NewHostForm: TForm;

implementation

uses
  fpcunit;

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

function NewHostForm: TForm;
begin
  NeedWidgetSet;
  Result := TForm.CreateNew(nil);
  Result.SetBounds(40, 40, 460, 760);
end;

{ ---- TPGBasic ---- }

constructor TPGBasic.Create;
begin
  inherited Create;
  FAlpha := 'start';
  FRatio := 1.5;
  FSmall := 0.1;
  FMoney := 12.25;
  FWhen := EncodeDate(2026, 10, 12) + EncodeTime(9, 30, 0, 0);
  FDay := EncodeDate(2026, 1, 2);
  FBig := -5000000000;
  FHuge := QWord(18000000000000000000);
  FUnsigned := 4000000000;
  FLetter := 'A';
  FWide := WideChar($4E2D);   // 中
  FTitle := 'title';
  FKind := pgkTwo;
  FTint := clRed;
  FFixed := 17;
  FWidth := 10;
end;

procedure TPGBasic.SetAutoGrow(AValue: Boolean);
begin
  FAutoGrow := AValue;
  if AValue then FWidth := 999;   // a setter that moves ANOTHER property
end;

procedure TPGBasic.SetBoom(AValue: Integer);
begin
  Inc(BoomTries);
  raise Exception.Create('boom');
end;

procedure TPGHandlers.Ping(Sender: TObject);
begin
end;

function TPGItem.GetDisplayName: string;
begin
  Result := FCaption;
end;

constructor TPGHolder.Create;
var it: TPGItem;
begin
  inherited Create;
  FFlags := [pfA, pfC];
  FFixedFlags := [pfB];
  FNums := [1, 3];
  FInner := TPGInner.Create;
  FInner.Level := 5;
  FItems := TOwnedCollection.Create(Self, TPGItem);
  it := TPGItem(FItems.Add); it.Caption := 'first'; it.Size := 10;
  it := TPGItem(FItems.Add); it.Caption := 'second'; it.Size := 20;
  FLines := TStringList.Create;
  FLines.Text := 'one' + LineEnding + 'two';
  FNotes := TStringList.Create;
  FNotes.Text := 'note';
end;

destructor TPGHolder.Destroy;
begin
  FNotes.Free;
  FLines.Free;
  FItems.Free;
  FInner.Free;
  inherited Destroy;
end;

function TPGHolder.GetLines: TStrings;
begin
  Result := FLines;
end;

function TPGHolder.GetNotes: TStrings;
begin
  Result := FNotes;
end;

procedure TPGHolder.SetLines(AValue: TStrings);
begin
  Inc(LinesSets);
  FLines.Assign(AValue);
end;

function TPGLink.GetOther: TPGLink;
begin
  Inc(LinkReads);
  if LinkReads > LinkReadLimit then raise Exception.Create('runaway expansion');
  Result := FOther;
end;

procedure TPGLink.Link(AOther: TPGLink);
begin
  FOther := AOther;
end;

constructor TPGHostComp.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSub := TPGSub.Create(Self);
  FSub.Name := 'Sub';
  FSub.SetSubComponent(True);
end;

procedure TPGTrap.SetMode(AValue: TPGKind);
begin
  Inc(ModeTries);
  raise Exception.Create('no mode change');
end;

{ ---- TPGEditAccess ---- }

procedure TPGEditAccess.TypeText(const AText: string);
var i: Integer; k: TUTF8Char;
begin
  SelectAll;                     // the first keystroke replaces the seeded value
  for i := 1 to Length(AText) do
  begin
    k := AText[i];               // ASCII only in these guards
    UTF8KeyPress(k);
  end;
end;

procedure TPGEditAccess.PressKey(AKey: Word);
var k: Word;
begin
  k := AKey;
  KeyDown(k, []);
end;

procedure TPGEditAccess.ClickEllipsis;
var r: TRect;
begin
  r := TrailingZone(Font.PixelsPerInch);
  MouseDown(mbLeft, [], (r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  MouseUp(mbLeft, [], (r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
end;

{ ---- TPGGrid ---- }

constructor TPGGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Font.PixelsPerInch := 96;
  KeyColumnWidth := 140;
  ColorAnswer := clLime;
end;

destructor TPGGrid.Destroy;
begin
  inherited Destroy;
end;

function TPGGrid.ExecuteFontDialog(AFont: TFont): Boolean;
begin
  Inc(FontDialogs);
  Result := FontAnswer <> nil;
  if Result then AFont.Assign(FontAnswer);
end;

function TPGGrid.ExecuteColorDialog(var AColor: TColor): Boolean;
begin
  AColor := ColorAnswer;
  Result := True;
end;

function TPGGrid.ExecuteStringsDialog(const ATitle: string; AStrings: TStrings): Boolean;
begin
  Inc(StringsDialogs);
  StringsTitle := ATitle;
  StringsSeen := AStrings.Text;
  Result := StringsAccept;
  if Result then AStrings.Text := StringsAnswer;
end;

function TPGGrid.HasRow(const APath: string): Boolean;
var parts: TStringList; r: TTyValueRow; i, k: Integer; found: Boolean;
begin
  Result := False;
  parts := TStringList.Create;
  try
    parts.Delimiter := '.';
    parts.StrictDelimiter := True;
    parts.DelimitedText := APath;
    r := nil;
    for i := 0 to parts.Count - 1 do
    begin
      found := False;
      if r = nil then
      begin
        for k := 0 to RowCount - 1 do
          if Row(k).Key = parts[i] then begin r := Row(k); found := True; Break; end;
      end
      else
        for k := 0 to r.ChildCount - 1 do
          if r.Child[k].Key = parts[i] then begin r := r.Child[k]; found := True; Break; end;
      if not found then Exit;
    end;
    Result := r <> nil;
  finally
    parts.Free;
  end;
end;

function TPGGrid.RowAt(const APath: string): TTyValueRow;
var parts: TStringList; i, k: Integer; found: Boolean;
begin
  parts := TStringList.Create;
  try
    parts.Delimiter := '.';
    parts.StrictDelimiter := True;
    parts.DelimitedText := APath;
    Result := nil;
    for i := 0 to parts.Count - 1 do
    begin
      found := False;
      if Result = nil then
      begin
        for k := 0 to RowCount - 1 do
          if Row(k).Key = parts[i] then begin Result := Row(k); found := True; Break; end;
      end
      else
        for k := 0 to Result.ChildCount - 1 do
          if Result.Child[k].Key = parts[i] then begin Result := Result.Child[k]; found := True; Break; end;
      if not found then
        raise EAssertionFailedError.Create('no row at ' + APath + ' (missing ' + parts[i] + ')');
    end;
  finally
    parts.Free;
  end;
end;

function TPGGrid.FlatOf(ARow: TTyValueRow): Integer;
var n, res: Integer; p: TTyValueRow; anyOpened: Boolean;

  procedure Walk(R: TTyValueRow);
  var i: Integer;
  begin
    if res >= 0 then Exit;
    if R = ARow then begin res := n; Exit; end;
    Inc(n);
    if R.Expanded then
      for i := 0 to R.ChildCount - 1 do Walk(R.Child[i]);
  end;

var i: Integer;
begin
  anyOpened := False;
  p := ARow.Parent;
  while p <> nil do
  begin
    if not p.Expanded then begin p.Expanded := True; anyOpened := True; end;
    p := p.Parent;
  end;
  if anyOpened then UpdateRows;
  n := 0; res := -1;
  for i := 0 to RowCount - 1 do Walk(Row(i));
  Result := res;
end;

procedure TPGGrid.Select(ARow: TTyValueRow);
var f: Integer;
begin
  f := FlatOf(ARow);
  TopIndex := f;          // scroll it into view, as the user would
  ItemIndex := f;
end;

procedure TPGGrid.ClickValue(ARow: TTyValueRow);
var f, x, y: Integer; r: TRect;
begin
  f := FlatOf(ARow);
  TopIndex := f;
  r := ItemRect(f);
  x := ClientWidth - 24;          // the value column
  y := (r.Top + r.Bottom) div 2;
  MouseDown(mbLeft, [], x, y);
  MouseUp(mbLeft, [], x, y);
end;

procedure TPGGrid.Press(AKey: Word; AShift: TShiftState);
var k: Word;
begin
  k := AKey;
  KeyDown(k, AShift);
end;

function TPGGrid.Dropped: TTyListBox;
begin
  Result := DropList;
end;

procedure TPGGrid.PickFromDropdown(ARow: TTyValueRow; const AText: string);
var lst: TTyListBox; i: Integer;
begin
  ClickValue(ARow);
  lst := Dropped;
  if lst = nil then raise EAssertionFailedError.Create('no list dropped for ' + ARow.Key);
  i := lst.Items.IndexOf(AText);
  if i < 0 then
  begin
    EndEdit(False);
    raise EAssertionFailedError.Create('''' + AText + ''' is not in the list for ' + ARow.Key
      + ': ' + lst.Items.CommaText);
  end;
  lst.SelectItem(i);
end;

function TPGGrid.Editor: TPGEditAccess;
begin
  Result := TPGEditAccess(InlineEditor);
end;

procedure TPGGrid.TypeInto(ARow: TTyValueRow; const AText: string);
begin
  ClickValue(ARow);
  if EditingRow < 0 then
    raise EAssertionFailedError.Create('the click did not open ' + ARow.Key);
  Editor.TypeText(AText);
  Editor.PressKey(VK_RETURN);
end;

function TPGGrid.RootKeys: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to RowCount - 1 do
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + Row(i).Key;
  end;
end;

{ The triangle sits in the indent slot before the key: left padding, then one slot per level. }
procedure TPGGrid.ClickTriangle(ARow: TTyValueRow);
var f, x, y, level: Integer; p: TTyValueRow; r: TRect;
begin
  f := FlatOf(ARow);
  TopIndex := f;
  level := 0;
  p := ARow.Parent;
  while p <> nil do begin Inc(level); p := p.Parent; end;
  r := ItemRect(f);
  { 14 is the editor's indent slot at the classic density these guards run at. }
  x := MulDiv(CurrentStyle.Padding.Left, Font.PixelsPerInch, 96)
    + level * MulDiv(14, Font.PixelsPerInch, 96) + 4;
  y := (r.Top + r.Bottom) div 2;
  MouseDown(mbLeft, [], x, y);
  MouseUp(mbLeft, [], x, y);
end;

function TPGGrid.CurrentRow: TTyValueRow;
var n: Integer; res: TTyValueRow;

  procedure Walk(R: TTyValueRow);
  var i: Integer;
  begin
    if res <> nil then Exit;
    if n = ItemIndex then begin res := R; Exit; end;
    Inc(n);
    if R.Expanded then
      for i := 0 to R.ChildCount - 1 do Walk(R.Child[i]);
  end;

var i: Integer;
begin
  res := nil;
  n := 0;
  if ItemIndex >= 0 then
    for i := 0 to RowCount - 1 do Walk(Row(i));
  Result := res;
end;

procedure TPGGrid.DesignMode(AOn: Boolean);
begin
  SetDesigning(AOn, False);
end;

end.
