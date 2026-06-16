unit test.baseevents;
{ Baseline events published on the two base classes (Task 1).
  Publishing an inherited event makes it fire because every overridden dispatch
  method (MouseDown/KeyDown/MouseEnter/...) calls inherited. These tests inject
  the protected methods via access subclasses and assert the event fires. No
  Parent/handle needed: the dispatch is synchronous. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, TypInfo, fpcunit, testregistry,
  tyControls.TyLabel, tyControls.Edit;
type
  { Access subclass exposing TTyLabel's protected MouseDown (graphic control). }
  TLabelAccess = class(TTyLabel)
  public
    procedure DoMD(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure DoME;
  end;

  { Access subclass exposing TTyEdit's protected KeyDown/MouseEnter (windowed). }
  TEditAccess2 = class(TTyEdit)
  public
    procedure DoKD(var K: Word; S: TShiftState);
    procedure DoME;
  end;

  TBaseEventsTest = class(TTestCase)
  private
    FFired: Boolean;
    procedure HMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HNotify(Sender: TObject);
  published
    procedure TestGraphicMouseDownEventFires;
    procedure TestWindowedKeyDownEventFires;
    procedure TestWindowedMouseEnterFires;
    procedure TestGraphicMouseEnterFires;
    procedure TestGraphicTierAEventsPublished;
    procedure TestGraphicTierAPropsPublished;
    procedure TestWindowedTierAEventsPublished;
    procedure TestWindowedTierBEventsPublished;
  end;

implementation

procedure TLabelAccess.DoMD(B: TMouseButton; S: TShiftState; X, Y: Integer);
begin
  MouseDown(B, S, X, Y);
end;

procedure TLabelAccess.DoME;
begin
  MouseEnter;
end;

procedure TEditAccess2.DoKD(var K: Word; S: TShiftState);
begin
  KeyDown(K, S);
end;

procedure TEditAccess2.DoME;
begin
  MouseEnter;
end;

procedure TBaseEventsTest.HMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FFired := True;
end;

procedure TBaseEventsTest.HKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  FFired := True;
end;

procedure TBaseEventsTest.HNotify(Sender: TObject);
begin
  FFired := True;
end;

procedure TBaseEventsTest.TestGraphicMouseDownEventFires;
var L: TLabelAccess;
begin
  L := TLabelAccess.Create(nil);
  try
    FFired := False;
    L.OnMouseDown := @HMouseDown;  // fails to compile until published on TTyGraphicControl
    L.DoMD(mbLeft, [], 1, 1);
    AssertTrue('graphic OnMouseDown fired', FFired);
  finally
    L.Free;
  end;
end;

procedure TBaseEventsTest.TestWindowedKeyDownEventFires;
var E: TEditAccess2; K: Word;
begin
  E := TEditAccess2.Create(nil);
  try
    FFired := False;
    E.OnKeyDown := @HKeyDown;  // fails to compile until published on TTyCustomControl
    K := Ord('A');
    E.DoKD(K, []);
    AssertTrue('windowed OnKeyDown fired', FFired);
  finally
    E.Free;
  end;
end;

procedure TBaseEventsTest.TestWindowedMouseEnterFires;
var E: TEditAccess2;
begin
  E := TEditAccess2.Create(nil);
  try
    FFired := False;
    E.OnMouseEnter := @HNotify;  // fails to compile until published on TTyCustomControl
    E.DoME;
    AssertTrue('windowed OnMouseEnter fired', FFired);
  finally
    E.Free;
  end;
end;

procedure TBaseEventsTest.TestGraphicMouseEnterFires;
var L: TLabelAccess;
begin
  L := TLabelAccess.Create(nil);
  try
    FFired := False;
    L.OnMouseEnter := @HNotify;  // fails to compile until published on TTyGraphicControl
    L.DoME;
    AssertTrue('graphic OnMouseEnter fired', FFired);
  finally
    L.Free;
  end;
end;

procedure TBaseEventsTest.TestGraphicTierAEventsPublished;
{ RTTI: GetPropInfo returns nil for a non-published property. These Tier A
  events must be PUBLISHED on TTyGraphicControl (streamable + Object Inspector).
  TTyLabel is a TTyGraphicControl. }
var L: TTyLabel;
begin
  L := TTyLabel.Create(nil);
  try
    AssertTrue('OnClick',          GetPropInfo(L, 'OnClick') <> nil);
    AssertTrue('OnDblClick',       GetPropInfo(L, 'OnDblClick') <> nil);
    AssertTrue('OnMouseDown',      GetPropInfo(L, 'OnMouseDown') <> nil);
    AssertTrue('OnMouseUp',        GetPropInfo(L, 'OnMouseUp') <> nil);
    AssertTrue('OnMouseMove',      GetPropInfo(L, 'OnMouseMove') <> nil);
    AssertTrue('OnMouseEnter',     GetPropInfo(L, 'OnMouseEnter') <> nil);
    AssertTrue('OnMouseLeave',     GetPropInfo(L, 'OnMouseLeave') <> nil);
    AssertTrue('OnMouseWheel',     GetPropInfo(L, 'OnMouseWheel') <> nil);
    AssertTrue('OnMouseWheelUp',   GetPropInfo(L, 'OnMouseWheelUp') <> nil);
    AssertTrue('OnMouseWheelDown', GetPropInfo(L, 'OnMouseWheelDown') <> nil);
    AssertTrue('OnContextPopup',   GetPropInfo(L, 'OnContextPopup') <> nil);
    AssertTrue('OnResize',         GetPropInfo(L, 'OnResize') <> nil);
    AssertTrue('OnChangeBounds',   GetPropInfo(L, 'OnChangeBounds') <> nil);
    { Tier B must NOT be published on the graphic (non-windowed) class. }
    AssertTrue('OnKeyDown absent on graphic', GetPropInfo(L, 'OnKeyDown') = nil);
    AssertTrue('OnEnter absent on graphic',   GetPropInfo(L, 'OnEnter') = nil);
  finally
    L.Free;
  end;
end;

procedure TBaseEventsTest.TestGraphicTierAPropsPublished;
var L: TTyLabel;
begin
  L := TTyLabel.Create(nil);
  try
    AssertTrue('PopupMenu',      GetPropInfo(L, 'PopupMenu') <> nil);
    AssertTrue('Constraints',    GetPropInfo(L, 'Constraints') <> nil);
    AssertTrue('BorderSpacing',  GetPropInfo(L, 'BorderSpacing') <> nil);
    AssertTrue('Cursor',         GetPropInfo(L, 'Cursor') <> nil);
    AssertTrue('ParentShowHint', GetPropInfo(L, 'ParentShowHint') <> nil);
  finally
    L.Free;
  end;
end;

procedure TBaseEventsTest.TestWindowedTierAEventsPublished;
var E: TTyEdit;
begin
  E := TTyEdit.Create(nil);
  try
    AssertTrue('OnClick',          GetPropInfo(E, 'OnClick') <> nil);
    AssertTrue('OnDblClick',       GetPropInfo(E, 'OnDblClick') <> nil);
    AssertTrue('OnMouseDown',      GetPropInfo(E, 'OnMouseDown') <> nil);
    AssertTrue('OnMouseUp',        GetPropInfo(E, 'OnMouseUp') <> nil);
    AssertTrue('OnMouseMove',      GetPropInfo(E, 'OnMouseMove') <> nil);
    AssertTrue('OnMouseEnter',     GetPropInfo(E, 'OnMouseEnter') <> nil);
    AssertTrue('OnMouseLeave',     GetPropInfo(E, 'OnMouseLeave') <> nil);
    AssertTrue('OnMouseWheel',     GetPropInfo(E, 'OnMouseWheel') <> nil);
    AssertTrue('OnContextPopup',   GetPropInfo(E, 'OnContextPopup') <> nil);
    AssertTrue('OnResize',         GetPropInfo(E, 'OnResize') <> nil);
    AssertTrue('OnChangeBounds',   GetPropInfo(E, 'OnChangeBounds') <> nil);
    AssertTrue('PopupMenu',        GetPropInfo(E, 'PopupMenu') <> nil);
    AssertTrue('Constraints',      GetPropInfo(E, 'Constraints') <> nil);
    AssertTrue('Cursor',           GetPropInfo(E, 'Cursor') <> nil);
  finally
    E.Free;
  end;
end;

procedure TBaseEventsTest.TestWindowedTierBEventsPublished;
{ Tier B (focusable / TWinControl-declared) published ONLY on TTyCustomControl. }
var E: TTyEdit;
begin
  E := TTyEdit.Create(nil);
  try
    AssertTrue('OnKeyDown',       GetPropInfo(E, 'OnKeyDown') <> nil);
    AssertTrue('OnKeyUp',         GetPropInfo(E, 'OnKeyUp') <> nil);
    AssertTrue('OnKeyPress',      GetPropInfo(E, 'OnKeyPress') <> nil);
    AssertTrue('OnUTF8KeyPress',  GetPropInfo(E, 'OnUTF8KeyPress') <> nil);
    AssertTrue('OnEnter',         GetPropInfo(E, 'OnEnter') <> nil);
    AssertTrue('OnExit',          GetPropInfo(E, 'OnExit') <> nil);
    AssertTrue('OnEditingDone',   GetPropInfo(E, 'OnEditingDone') <> nil);
  finally
    E.Free;
  end;
end;

initialization
  RegisterTest(TBaseEventsTest);
end.
