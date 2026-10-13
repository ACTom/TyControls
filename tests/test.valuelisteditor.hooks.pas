unit test.valuelisteditor.hooks;
{$mode objfpc}{$H+}

{ The two additive hooks TTyCustomValueListEditor grew for the property grid (#65):
    * TTyValueRow.Data, a pointer the editor never owns;
    * CanCommitValue, asked before ANY commit moves a row's value.

  The point of the second one is that it is asked on EVERY route a value can take into a row, so
  the guards below drive each route the way the user does -- click the value cell, type, Enter;
  pick from the dropped list; the colour dialog behind "more…"; the font dialog with and without
  child rows -- plus the two programmatic writes. A descendant that stores values somewhere
  (the property grid writes them into an object) loses data on any route that slips past it.

  The two dialogs are answered through the protected ExecuteFontDialog / ExecuteColorDialog, so
  no modal window opens. }

interface

uses
  Classes, SysUtils, LCLType, Controls, Graphics, Forms, fpcunit, testregistry,
  tyControls.ListBox, tyControls.ValueListEditor, tyControls.ColorBox;

type
  { Drives the inline editor the way the keyboard does. }
  TVleEditAccess = class(TTyValueEdit)
  public
    procedure TypeText(const AText: string);
    procedure PressKey(AKey: Word);
    procedure ClickEllipsis;
  end;

  { An editor that records every question CanCommitValue is asked and answers with Allow. }
  TVetoValueList = class(TTyValueListEditor)
  protected
    function CanCommitValue(ARow: TTyValueRow; var AText: string): Boolean; override;
    function ExecuteFontDialog(AFont: TFont): Boolean; override;
    function ExecuteColorDialog(var AColor: TColor): Boolean; override;
  public
    Allow: Boolean;
    Rewrite: string;          // non-empty: the hook rewrites AText to this
    Asked: Integer;
    AskedRow: TTyValueRow;
    AskedText: string;
    AskedFont: string;        // CommitFont at the time of the question ('' when nil)
    PickName: string;         // what the "font dialog" picks
    PickSize: Integer;
    PickStyle: TFontStyles;
    PickColor: TColor;        // what the "colour dialog" picks
    procedure ClickValue(AFlat: Integer);
    procedure Press(AKey: Word; AShift: TShiftState = []);
    function Dropped: TTyListBox;
  end;

  TValueListCommitHookTest = class(TTestCase)
  private
    FForm: TForm;
    FVle: TVetoValueList;
    FChanged: Integer;
    procedure ValueChanged(Sender: TObject; ARow: TTyValueRow);
    function Editor: TVleEditAccess;
    procedure TypeAndEnter(AFlat: Integer; const AText: string);
    function FontRowWithChildren(out AName, ASize, ABold: TTyValueRow): TTyValueRow;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRowDataIsNilAndNotOwned;
    procedure TestInlineEditAsksAndAVetoKeepsTheValue;
    procedure TestInlineEditAllowedCommitsOnce;
    procedure TestRewrittenTextIsWhatTheRowKeeps;
    procedure TestRewriteBackToTheOldValueIsNoChange;
    procedure TestEnumPickAsks;
    procedure TestBooleanPickAsks;
    procedure TestColourPickAsks;
    procedure TestColourDialogAsks;
    procedure TestFontDialogOnALeafRowAsks;
    procedure TestFontDialogWithChildrenAsksOnceForTheWholeFont;
    procedure TestFontDialogWithChildrenAllowedMovesTheChildren;
    procedure TestSetRowValueAsks;
    procedure TestValuesAndValueFromIndexAsk;
  end;

implementation

{ ---- helpers ---- }

procedure TVleEditAccess.TypeText(const AText: string);
var i: Integer; k: TUTF8Char;
begin
  SelectAll;                     // the first keystroke replaces the seeded value
  for i := 1 to Length(AText) do
  begin
    k := AText[i];               // ASCII only in these guards
    UTF8KeyPress(k);
  end;
end;

procedure TVleEditAccess.PressKey(AKey: Word);
var k: Word;
begin
  k := AKey;
  KeyDown(k, []);
end;

procedure TVleEditAccess.ClickEllipsis;
var r: TRect;
begin
  r := TrailingZone(Font.PixelsPerInch);
  MouseDown(mbLeft, [], (r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  MouseUp(mbLeft, [], (r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
end;

function TVetoValueList.CanCommitValue(ARow: TTyValueRow; var AText: string): Boolean;
begin
  Inc(Asked);
  AskedRow := ARow;
  AskedText := AText;
  if CommitFont <> nil then
    AskedFont := Format('%s, %d', [CommitFont.Name, CommitFont.Size])
  else
    AskedFont := '';
  if Rewrite <> '' then AText := Rewrite;
  Result := Allow;
end;

function TVetoValueList.ExecuteFontDialog(AFont: TFont): Boolean;
var f: TFont;
begin
  { What a user clicking through the dialog leaves behind: a different face, size and style. }
  f := TFont.Create;
  try
    f.Assign(AFont);
    f.Name := PickName;
    f.Style := PickStyle;
    AFont.Assign(f);
  finally
    f.Free;
  end;
  AFont.Size := PickSize;
  Result := True;
end;

function TVetoValueList.ExecuteColorDialog(var AColor: TColor): Boolean;
begin
  AColor := PickColor;
  Result := True;
end;

procedure TVetoValueList.ClickValue(AFlat: Integer);
var r: TRect; x, y: Integer;
begin
  r := ItemRect(AFlat);
  x := ClientWidth - 24;          // the value column: right of the divider
  y := (r.Top + r.Bottom) div 2;
  MouseDown(mbLeft, [], x, y);
  MouseUp(mbLeft, [], x, y);
end;

procedure TVetoValueList.Press(AKey: Word; AShift: TShiftState);
var k: Word;
begin
  k := AKey;
  KeyDown(k, AShift);
end;

function TVetoValueList.Dropped: TTyListBox;
begin
  Result := DropList;
end;

procedure TValueListCommitHookTest.ValueChanged(Sender: TObject; ARow: TTyValueRow);
begin
  Inc(FChanged);
end;

function TValueListCommitHookTest.Editor: TVleEditAccess;
begin
  Result := TVleEditAccess(FVle.InlineEditor);
end;

procedure TValueListCommitHookTest.TypeAndEnter(AFlat: Integer; const AText: string);
begin
  FVle.ClickValue(AFlat);
  AssertEquals('the click opened the value cell', AFlat, FVle.EditingRow);
  Editor.TypeText(AText);
  Editor.PressKey(VK_RETURN);
  AssertEquals('Enter closed the editor', -1, FVle.EditingRow);
end;

function TValueListCommitHookTest.FontRowWithChildren(out AName, ASize, ABold: TTyValueRow): TTyValueRow;
var style: TTyValueRow;
begin
  Result := FVle.AddRow('Font', 'Arial, 10');
  Result.EditorKind := vekFont;
  AName := Result.AddChild('Name', 'Arial');
  ASize := Result.AddChild('Size', '10');
  ASize.EditorKind := vekInteger;
  style := Result.AddChild('Style', 'Regular');
  ABold := style.AddChild('Bold', 'False');
  ABold.EditorKind := vekBoolean;
  style.AddChild('Italic', 'False').EditorKind := vekBoolean;
  FVle.UpdateRows;
end;

var
  WidgetSetReady: Boolean = False;

{ The runner never calls Forms.Application.Initialize, so without this the window classes are
  unregistered and HandleNeeded fails with 1407. Once, lazily -- see test.base. }
procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TValueListCommitHookTest.SetUp;
begin
  NeedWidgetSet;
  FChanged := 0;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(40, 40, 420, 320);
  FVle := TVetoValueList.Create(FForm);
  FVle.Parent := FForm;
  FVle.SetBounds(0, 0, 360, 260);
  FVle.Font.PixelsPerInch := 96;
  FVle.KeyColumnWidth := 120;
  FVle.OnValueChanged := @ValueChanged;
  FVle.PickName := 'Courier New';
  FVle.PickSize := 14;
  FVle.PickStyle := [fsBold];
  FVle.PickColor := clLime;
  { Shown: a click focuses the control, and focusing a control on a hidden form raises. }
  FForm.Show;
  FVle.HandleNeeded;
end;

procedure TValueListCommitHookTest.TearDown;
begin
  FForm.Free;   // owns FVle
  FForm := nil;
  FVle := nil;
end;

{ ---- Data ---- }

type
  TFreeProbe = class
  public
    Freed: PBoolean;
    destructor Destroy; override;
  end;

destructor TFreeProbe.Destroy;
begin
  Freed^ := True;
  inherited Destroy;
end;

procedure TValueListCommitHookTest.TestRowDataIsNilAndNotOwned;
var r, c: TTyValueRow; probe: TFreeProbe; freed: Boolean;
begin
  r := FVle.AddRow('A', '1');
  c := r.AddChild('B', '2');
  AssertTrue('a new row carries no data', r.Data = nil);
  AssertTrue('nor does a new child row', c.Data = nil);
  freed := False;
  probe := TFreeProbe.Create;
  probe.Freed := @freed;
  try
    r.Data := probe;
    AssertTrue('Data keeps what it was given', r.Data = Pointer(probe));
    FVle.Clear;    // frees the row
    AssertFalse('freeing the row leaves its Data alone -- it is not owned', freed);
  finally
    probe.Free;
  end;
  AssertTrue('(and the probe does report its own destruction)', freed);
end;

{ ---- the inline editor ---- }

procedure TValueListCommitHookTest.TestInlineEditAsksAndAVetoKeepsTheValue;
var r: TTyValueRow;
begin
  r := FVle.AddRow('Width', '100');
  r.EditorKind := vekInteger;
  FVle.Allow := False;
  TypeAndEnter(0, '250');
  AssertEquals('the hook was asked once', 1, FVle.Asked);
  AssertSame('about this row', r, FVle.AskedRow);
  AssertEquals('with the typed text', '250', FVle.AskedText);
  AssertEquals('refused: the row keeps its value', '100', r.Value);
  AssertEquals('and OnValueChanged stays silent', 0, FChanged);
end;

procedure TValueListCommitHookTest.TestInlineEditAllowedCommitsOnce;
var r: TTyValueRow;
begin
  r := FVle.AddRow('Caption', 'Old');
  FVle.Allow := True;
  TypeAndEnter(0, 'New');
  AssertEquals('asked once', 1, FVle.Asked);
  AssertEquals('allowed: the row took the text', 'New', r.Value);
  AssertEquals('OnValueChanged fired once', 1, FChanged);
end;

procedure TValueListCommitHookTest.TestRewrittenTextIsWhatTheRowKeeps;
var r: TTyValueRow;
begin
  r := FVle.AddRow('Width', '100');
  r.EditorKind := vekInteger;
  FVle.Allow := True;
  FVle.Rewrite := '7';         // the descendant stored 7 and reads it back as '7'
  TypeAndEnter(0, '007');
  AssertEquals('the hook saw what was typed', '007', FVle.AskedText);
  AssertEquals('the row holds the rewritten form', '7', r.Value);
  AssertEquals('one change', 1, FChanged);
end;

procedure TValueListCommitHookTest.TestRewriteBackToTheOldValueIsNoChange;
var r: TTyValueRow;
begin
  r := FVle.AddRow('Width', '7');
  r.EditorKind := vekInteger;
  FVle.Allow := True;
  FVle.Rewrite := '7';         // '007' over 7 is still 7
  TypeAndEnter(0, '007');
  AssertEquals('asked', 1, FVle.Asked);
  AssertEquals('the row still reads 7', '7', r.Value);
  AssertEquals('so nothing changed and nothing fired', 0, FChanged);
end;

{ ---- the dropped lists ---- }

procedure TValueListCommitHookTest.TestEnumPickAsks;
var r: TTyValueRow; lst: TTyListBox;
begin
  r := FVle.AddRow('Align', 'alNone');
  r.EditorKind := vekEnum;
  r.EnumValues := 'alNone' + LineEnding + 'alTop' + LineEnding + 'alClient';
  FVle.Allow := False;
  FVle.ClickValue(0);
  lst := FVle.Dropped;
  AssertNotNull('the click dropped the enum list', lst);
  lst.SelectItem(2);
  AssertEquals('the pick asked', 1, FVle.Asked);
  AssertEquals('about the picked name', 'alClient', FVle.AskedText);
  AssertEquals('refused: unchanged', 'alNone', r.Value);
  AssertEquals('no event', 0, FChanged);
  AssertNull('and the list closed', FVle.Dropped);

  FVle.Allow := True;
  FVle.ClickValue(0);
  FVle.Dropped.SelectItem(1);
  AssertEquals('allowed: taken', 'alTop', r.Value);
  AssertEquals('one event', 1, FChanged);
end;

procedure TValueListCommitHookTest.TestBooleanPickAsks;
var r: TTyValueRow;
begin
  r := FVle.AddRow('Visible', 'True');
  r.EditorKind := vekBoolean;
  FVle.Allow := False;
  FVle.ItemIndex := 0;
  FVle.Press(VK_F2);                        // the keyboard route into the cell
  AssertNotNull('F2 dropped the False/True list', FVle.Dropped);
  FVle.Dropped.SelectItem(0);               // False
  AssertEquals('asked', 1, FVle.Asked);
  AssertEquals('about False', 'False', FVle.AskedText);
  AssertEquals('refused: still True', 'True', r.Value);
  AssertEquals('no event', 0, FChanged);
end;

procedure TValueListCommitHookTest.TestColourPickAsks;
var r: TTyValueRow; lst: TTyListBox; i, idx: Integer; want: string;
begin
  r := FVle.AddRow('Color', 'clRed');
  r.EditorKind := vekColor;
  FVle.Allow := False;
  FVle.ClickValue(0);
  lst := FVle.Dropped;
  AssertNotNull('the click dropped the swatches', lst);
  idx := -1;
  for i := 0 to lst.Items.Count - 2 do      // the last row is "more…"
    if TyColorOfItem(lst.Items, i) <> clRed then begin idx := i; Break; end;
  AssertTrue('a swatch other than red exists', idx >= 0);
  want := ColorToString(TyColorOfItem(lst.Items, idx));
  lst.SelectItem(idx);
  AssertEquals('the swatch pick asked', 1, FVle.Asked);
  AssertEquals('with that colour''s name', want, FVle.AskedText);
  AssertEquals('refused: still red', 'clRed', r.Value);
  AssertEquals('no event', 0, FChanged);
end;

procedure TValueListCommitHookTest.TestColourDialogAsks;
var r: TTyValueRow; lst: TTyListBox;
begin
  r := FVle.AddRow('Color', 'clRed');
  r.EditorKind := vekColor;
  FVle.Allow := False;
  FVle.ClickValue(0);
  lst := FVle.Dropped;
  AssertNotNull('dropped', lst);
  AssertEquals('the last row is the "more…" sentinel', clNone,
    TyColorOfItem(lst.Items, lst.Items.Count - 1));
  lst.SelectItem(lst.Items.Count - 1);
  AssertEquals('picking "more…" is not itself a commit', 0, FVle.Asked);
  Forms.Application.ProcessMessages;        // the dialog runs on a queued call
  AssertEquals('the dialog''s answer asked', 1, FVle.Asked);
  AssertEquals('with the colour the dialog picked', 'clLime', FVle.AskedText);
  AssertEquals('refused: still red', 'clRed', r.Value);
  AssertEquals('no event', 0, FChanged);

  FVle.Allow := True;
  FVle.ClickValue(0);
  FVle.Dropped.SelectItem(FVle.Dropped.Items.Count - 1);
  Forms.Application.ProcessMessages;
  AssertEquals('allowed: the dialog''s colour landed', 'clLime', r.Value);
  AssertEquals('one event', 1, FChanged);
end;

{ ---- the font dialog ---- }

procedure TValueListCommitHookTest.TestFontDialogOnALeafRowAsks;
var r: TTyValueRow;
begin
  r := FVle.AddRow('Font', 'Arial, 10');
  r.EditorKind := vekFont;
  FVle.Allow := False;
  FVle.ClickValue(0);
  AssertEquals('the font row opened (read-only text with a "…")', 0, FVle.EditingRow);
  Editor.ClickEllipsis;                     // the "…" opens the dialog
  AssertEquals('asked once', 1, FVle.Asked);
  AssertEquals('with the picked font, Name, Size', 'Courier New, 14', FVle.AskedText);
  AssertEquals('and CommitFont is the picked font while asking', 'Courier New, 14', FVle.AskedFont);
  AssertEquals('refused: unchanged', 'Arial, 10', r.Value);
  AssertEquals('no event', 0, FChanged);
  AssertNull('CommitFont is gone once the question is over', FVle.CommitFont);
end;

procedure TValueListCommitHookTest.TestFontDialogWithChildrenAsksOnceForTheWholeFont;
var font, nm, sz, bold: TTyValueRow;
begin
  font := FontRowWithChildren(nm, sz, bold);
  FVle.Allow := False;
  FVle.InvokeRowDialog(0);
  AssertEquals('ONE question for the whole font', 1, FVle.Asked);
  AssertSame('asked on the font row, not on a leaf', font, FVle.AskedRow);
  AssertEquals('with the summary of what was picked', 'Courier New, 14 Bold', FVle.AskedText);
  AssertEquals('CommitFont carried the picked font', 'Courier New, 14', FVle.AskedFont);
  AssertEquals('refused: the name leaf is untouched', 'Arial', nm.Value);
  AssertEquals('so is the size leaf', '10', sz.Value);
  AssertEquals('and the bold leaf', 'False', bold.Value);
  AssertEquals('and the font row', 'Arial, 10', font.Value);
  AssertEquals('and not one OnValueChanged', 0, FChanged);
end;

procedure TValueListCommitHookTest.TestFontDialogWithChildrenAllowedMovesTheChildren;
var font, nm, sz, bold: TTyValueRow;
begin
  font := FontRowWithChildren(nm, sz, bold);
  FVle.Allow := True;
  FVle.InvokeRowDialog(0);
  AssertEquals('asked once', 1, FVle.Asked);
  AssertEquals('the name leaf followed', 'Courier New', nm.Value);
  AssertEquals('the size leaf followed', '14', sz.Value);
  AssertEquals('the bold leaf followed', 'True', bold.Value);
  AssertEquals('the font row re-summarised', 'Courier New, 14 Bold', font.Value);
  AssertTrue('and the changes were reported', FChanged > 0);
end;

{ ---- programmatic writes ---- }

procedure TValueListCommitHookTest.TestSetRowValueAsks;
var r, c: TTyValueRow;
begin
  r := FVle.AddRow('Node', '');
  c := r.AddChild('Leaf', 'a');
  FVle.UpdateRows;
  FVle.Allow := False;
  FVle.SetRowValue(c, 'b');
  AssertEquals('asked', 1, FVle.Asked);
  AssertSame('about the child', c, FVle.AskedRow);
  AssertEquals('refused: unchanged', 'a', c.Value);
  AssertEquals('no event', 0, FChanged);
  FVle.Allow := True;
  FVle.SetRowValue(c, 'b');
  AssertEquals('allowed', 'b', c.Value);
  AssertEquals('one event', 1, FChanged);
end;

procedure TValueListCommitHookTest.TestValuesAndValueFromIndexAsk;
begin
  FVle.AddRow('Width', '100');
  FVle.AddRow('Height', '50');
  FVle.Allow := False;
  FVle.Values['Width'] := '1';
  AssertEquals('Values[] asked', 1, FVle.Asked);
  AssertEquals('refused: unchanged', '100', FVle.Values['Width']);
  FVle.ValueFromIndex[1] := '2';
  AssertEquals('ValueFromIndex[] asked', 2, FVle.Asked);
  AssertEquals('refused: unchanged', '50', FVle.ValueFromIndex[1]);
  AssertEquals('no event', 0, FChanged);
  FVle.Allow := True;
  FVle.Values['Width'] := '1';
  AssertEquals('allowed', '1', FVle.Values['Width']);
  AssertEquals('one event', 1, FChanged);
end;

initialization
  RegisterTest(TValueListCommitHookTest);
end.
