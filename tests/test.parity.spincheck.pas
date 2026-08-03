unit test.parity.spincheck;
{ API-parity guards for TTySpinEdit's change notification and TTyCheckComboBox's
  per-item storage.

  A. TTySpinEdit.OnChange is the EDIT's change notification (LCL: TCustomEdit.Change,
     customedit.inc:622 -- reached from TextChanged on every keystroke). It used to fire
     only from inside `if FValue <> Clamped`, so a handler doing live validation heard
     NOTHING while the user typed. OnValueChange is the separate "the committed number
     moved" hook.

  B. TTyCheckComboBox used to write the raw check flag (0/1) into Items.Objects[],
     which is the application's slot. LCL hangs a TCheckComboItemState there instead
     (comboex.pas:262) and gives the app a Data field inside it, reachable through the
     control-level Objects[] property (comboex.inc:874/904). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, LCLType, fpcunit, testregistry,
  tyControls.SpinEdit, tyControls.ComboBox, tyControls.CheckComboBox,
  tyControls.CheckListBox;

type
  { Counts notifications so a test can assert HOW MANY times a handler ran, not
    merely that it ran once. }
  TEventCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  { Exposes the protected input dispatch + edit buffer. }
  TSpinProbe = class(TTySpinEdit)
  public
    procedure TypeChar(const C: TUTF8Char);
    procedure DoKey(K: Word);
    function BufferText: string;
  end;

  { Exposes the popup-boundary translation (so it can be driven against a standalone
    checklist, no window handle needed) and the state pool's size. }
  TCheckComboProbe = class(TTyCheckComboBox)
  public
    procedure PushForTest(L: TTyCheckListBox);
    procedure PullForTest(L: TTyCheckListBox);
    function PoolCount: Integer;
  end;

  TSpinChangeParityTest = class(TTestCase)
  published
    procedure TypingFiresOnChangePerKeystroke;
    procedure BackspaceFiresOnChangeAndNoOpStaysSilent;
    procedure ValueMoveStillFiresOnChange;
    procedure OnValueChangeIgnoresTypingAndFiresOnCommit;
    procedure StepFiresBothEvents;
    procedure RangeEditReclampNotifies;
    procedure EmptyRangeStaysUnboundedOnTheRangeSetters;
  end;

  TCheckComboDataParityTest = class(TTestCase)
  published
    procedure AppDataInObjectsIsNotACheck;
    procedure AppDataAndCheckStateCoexist;
    procedure StateAndDataSurviveSort;
    procedure InsertShiftsStateWithItsItem;
    procedure DeleteKeepsRemainingStatesAligned;
    procedure StatesNeverReachThePopupAsRawFlags;
    procedure RefillingItemsDoesNotStrandStates;
  end;

implementation

procedure TEventCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

{ TSpinProbe }

procedure TSpinProbe.TypeChar(const C: TUTF8Char);
var k: TUTF8Char;
begin
  k := C;
  UTF8KeyPress(k);
end;

procedure TSpinProbe.DoKey(K: Word);
var w: Word;
begin
  w := K;
  KeyDown(w, []);
end;

function TSpinProbe.BufferText: string;
begin
  Result := FEditText;
end;

{ TCheckComboProbe }

procedure TCheckComboProbe.PushForTest(L: TTyCheckListBox);
begin
  PushChecksToList(L);
end;

procedure TCheckComboProbe.PullForTest(L: TTyCheckListBox);
begin
  PullChecksFromList(L);
end;

function TCheckComboProbe.PoolCount: Integer;
begin
  Result := FStates.Count;
end;

{ TSpinChangeParityTest }

procedure TSpinChangeParityTest.TypingFiresOnChangePerKeystroke;
{ The typing path never reached the old notification at all: a handler enabling an
  OK button or validating live was dead for as long as the user was typing. }
var
  S: TSpinProbe;
  C: TEventCounter;
begin
  S := TSpinProbe.Create(nil);
  C := TEventCounter.Create;
  try
    S.MinValue := 0;
    S.MaxValue := 1000;
    S.Value := 0;
    S.OnChange := @C.Handle;
    C.Count := 0;
    S.TypeChar('4');
    S.TypeChar('2');
    AssertEquals('typed text is in the buffer', '042', S.BufferText);
    AssertEquals('OnChange is the edit notification: one per keystroke', 2, C.Count);
  finally
    C.Free;
    S.Free;
  end;
end;

procedure TSpinChangeParityTest.BackspaceFiresOnChangeAndNoOpStaysSilent;
{ Deleting is a text change too -- and a backspace with nothing to delete changes no
  text, so it must NOT notify (the counter is what distinguishes the two). }
var
  S: TSpinProbe;
  C: TEventCounter;
begin
  S := TSpinProbe.Create(nil);
  C := TEventCounter.Create;
  try
    S.MinValue := 0;
    S.MaxValue := 1000;
    S.Value := 42;              // buffer '42', caret at the end
    S.OnChange := @C.Handle;
    C.Count := 0;
    S.DoKey(VK_BACK);
    AssertEquals('buffer lost a digit', '4', S.BufferText);
    AssertEquals('deleting a character is a text change', 1, C.Count);
    S.DoKey(VK_HOME);
    C.Count := 0;
    S.DoKey(VK_BACK);           // caret 0: nothing to delete
    AssertEquals('a no-op backspace stays silent', 0, C.Count);
  finally
    C.Free;
    S.Free;
  end;
end;

procedure TSpinChangeParityTest.ValueMoveStillFiresOnChange;
{ The new contract is a SUPERSET of the old one: everything that used to notify still
  does, so handlers written against the old behaviour keep working. }
var
  S: TSpinProbe;
  C: TEventCounter;
begin
  S := TSpinProbe.Create(nil);
  C := TEventCounter.Create;
  try
    S.MinValue := 0;
    S.MaxValue := 100;
    S.Value := 50;
    S.OnChange := @C.Handle;
    C.Count := 0;
    S.Value := 60;
    AssertEquals('a value move still reaches OnChange', 1, C.Count);
    S.Value := 60;
    AssertEquals('re-writing the same value changes no text and stays silent', 1, C.Count);
  finally
    C.Free;
    S.Free;
  end;
end;

procedure TSpinChangeParityTest.OnValueChangeIgnoresTypingAndFiresOnCommit;
{ The other half of the split: OnValueChange is for "the number is now N", so a half-typed
  buffer must not wake it -- only the commit does. }
var
  S: TSpinProbe;
  C: TEventCounter;
begin
  S := TSpinProbe.Create(nil);
  C := TEventCounter.Create;
  try
    S.MinValue := 0;
    S.MaxValue := 1000;
    S.Value := 0;
    S.OnValueChange := @C.Handle;
    C.Count := 0;
    S.TypeChar('4');
    S.TypeChar('2');
    AssertEquals('typing does not move the committed value', 0, C.Count);
    AssertEquals('value untouched while typing', 0, S.Value);
    S.DoKey(VK_RETURN);
    AssertEquals('the commit does', 1, C.Count);
    AssertEquals('committed', 42, S.Value);
    S.DoKey(VK_RETURN);         // same buffer, same value
    AssertEquals('re-committing an unchanged value stays silent', 1, C.Count);
  finally
    C.Free;
    S.Free;
  end;
end;

procedure TSpinChangeParityTest.StepFiresBothEvents;
{ A spin step is both: the text is rewritten AND the number moves. }
var
  S: TSpinProbe;
  CText, CValue: TEventCounter;
begin
  S := TSpinProbe.Create(nil);
  CText := TEventCounter.Create;
  CValue := TEventCounter.Create;
  try
    S.MinValue := 0;
    S.MaxValue := 100;
    S.Value := 50;
    S.OnChange := @CText.Handle;
    S.OnValueChange := @CValue.Handle;
    CText.Count := 0;
    CValue.Count := 0;
    S.DoKey(VK_UP);
    AssertEquals('stepped', 51, S.Value);
    AssertEquals('the buffer was rewritten', 1, CText.Count);
    AssertEquals('and the value moved', 1, CValue.Count);
    S.Value := 100;
    CText.Count := 0;
    CValue.Count := 0;
    S.DoKey(VK_UP);             // already at Max: clamped back to 100, nothing moves
    AssertEquals('a step that clamps to where we already are rewrites no text', 0, CText.Count);
    AssertEquals('and moves no value', 0, CValue.Count);
  finally
    CValue.Free;
    CText.Free;
    S.Free;
  end;
end;

procedure TSpinChangeParityTest.RangeEditReclampNotifies;
{ Raising MinValue over the current value silently rewrote the displayed number. Both
  hooks have to hear it: the text changed and the committed value moved. }
var
  S: TSpinProbe;
  CText, CValue: TEventCounter;
begin
  S := TSpinProbe.Create(nil);
  CText := TEventCounter.Create;
  CValue := TEventCounter.Create;
  try
    S.MinValue := 0;
    S.MaxValue := 100;
    S.Value := 50;
    S.OnChange := @CText.Handle;
    S.OnValueChange := @CValue.Handle;
    CText.Count := 0;
    CValue.Count := 0;
    S.MinValue := 60;
    AssertEquals('reclamped', 60, S.Value);
    AssertEquals('OnChange heard the rewrite', 1, CText.Count);
    AssertEquals('OnValueChange heard the move', 1, CValue.Count);
    CText.Count := 0;
    CValue.Count := 0;
    S.MaxValue := 90;           // nothing to reclamp
    AssertEquals('a bound edit that moves nothing stays silent', 0, CText.Count);
    AssertEquals('on both hooks', 0, CValue.Count);
  finally
    CValue.Free;
    CText.Free;
    S.Free;
  end;
end;

procedure TSpinChangeParityTest.EmptyRangeStaysUnboundedOnTheRangeSetters;
{ Max <= Min means "no limit" (LCL spinedit.inc GetLimitedValue). The Value setter already
  knew that; the MinValue/MaxValue setters clamped unconditionally, so editing a bound
  could pin a value that writing it directly would have left alone. }
var
  S: TTySpinEdit;
begin
  S := TTySpinEdit.Create(nil);
  try
    S.MaxValue := 0;            // 0..0 == unbounded
    S.Value := 5000;
    AssertEquals('the value setter does not clamp an empty range', 5000, S.Value);
    S.MinValue := 100;          // 100..0, still empty
    AssertEquals('and neither does a bound edit', 5000, S.Value);
    S.MaxValue := 50;           // 100..50, still empty
    AssertEquals('in either direction', 5000, S.Value);
    S.MaxValue := 200;          // 100..200: a real range at last
    AssertEquals('a real range clamps', 200, S.Value);
  finally
    S.Free;
  end;
end;

{ TCheckComboDataParityTest }

procedure TCheckComboDataParityTest.AppDataInObjectsIsNotACheck;
{ Items.AddObject(s, Data) is the idiomatic way an app attaches per-row data. While the
  check flag WAS the Objects[] slot, any non-nil app object read back as "checked". }
var
  c: TTyCheckComboBox;
  d: TStringList;
begin
  c := TTyCheckComboBox.Create(nil);
  d := TStringList.Create;
  try
    c.Items.AddObject('Apple', d);
    c.Items.Add('Banana');
    AssertFalse('app data in Objects[] is not a check', c.Checked[0]);
    AssertEquals('nothing is checked', 0, c.CheckedCount);
    AssertEquals('and the field summary is empty', '', c.CheckedText);
  finally
    d.Free;
    c.Free;
  end;
end;

procedure TCheckComboDataParityTest.AppDataAndCheckStateCoexist;
{ Both orders: data attached first then checked, and checked first then data attached.
  Either one used to overwrite the other, because both wanted the same slot. }
var
  c: TTyCheckComboBox;
  d1, d2: TStringList;
begin
  c := TTyCheckComboBox.Create(nil);
  d1 := TStringList.Create;
  d2 := TStringList.Create;
  try
    c.Items.AddObject('Apple', d1);
    c.Items.Add('Banana');
    c.Checked[0] := True;
    AssertTrue('checked', c.Checked[0]);
    AssertSame('checking did not destroy the app data', d1, c.Objects[0]);

    c.Checked[1] := True;
    c.Objects[1] := d2;
    AssertSame('app data landed', d2, c.Objects[1]);
    AssertTrue('attaching app data did not destroy the check', c.Checked[1]);
    AssertEquals('both rows checked', 2, c.CheckedCount);
    AssertEquals('summary', 'Apple, Banana', c.CheckedText);
  finally
    d2.Free;
    d1.Free;
    c.Free;
  end;
end;

procedure TCheckComboDataParityTest.StateAndDataSurviveSort;
{ Sorted reorders the strings and their Objects[] together, which is the whole reason the
  state rides in that slot rather than in a parallel array. }
var
  c: TTyCheckComboBox;
  d: TStringList;
begin
  c := TTyCheckComboBox.Create(nil);
  d := TStringList.Create;
  try
    c.Items.AddObject('Zebra', d);
    c.Items.Add('Apple');
    c.Checked[0] := True;                 // Zebra
    c.Sorted := True;                     // Apple first now
    AssertTrue('Zebra still checked after the sort',
      c.Checked[c.Items.IndexOf('Zebra')]);
    AssertFalse('Apple still unchecked', c.Checked[c.Items.IndexOf('Apple')]);
    AssertSame('and Zebra kept its app data', d, c.Objects[c.Items.IndexOf('Zebra')]);
  finally
    d.Free;
    c.Free;
  end;
end;

procedure TCheckComboDataParityTest.InsertShiftsStateWithItsItem;
var
  c: TTyCheckComboBox;
begin
  c := TTyCheckComboBox.Create(nil);
  try
    c.Items.Add('Apple');
    c.Items.Add('Banana');
    c.Checked[1] := True;
    c.Items.Insert(0, 'Fig');
    AssertFalse('a freshly inserted item starts unchecked', c.Checked[0]);
    AssertFalse('Apple still unchecked', c.Checked[1]);
    AssertTrue('Banana kept its check across the shift', c.Checked[2]);
    AssertEquals('one check total', 1, c.CheckedCount);
  finally
    c.Free;
  end;
end;

procedure TCheckComboDataParityTest.DeleteKeepsRemainingStatesAligned;
var
  c: TTyCheckComboBox;
begin
  c := TTyCheckComboBox.Create(nil);
  try
    c.Items.Add('Apple');
    c.Items.Add('Banana');
    c.Items.Add('Cherry');
    c.Checked[0] := True;
    c.Checked[2] := True;
    c.Items.Delete(1);
    AssertEquals('two rows left', 2, c.Items.Count);
    AssertTrue('Apple still checked', c.Checked[0]);
    AssertTrue('Cherry still checked after shifting down', c.Checked[1]);
    AssertEquals('summary follows', 'Apple, Cherry', c.CheckedText);
  finally
    c.Free;
  end;
end;

procedure TCheckComboDataParityTest.StatesNeverReachThePopupAsRawFlags;
{ The popup checklist reads ITS Items.Objects[] as a raw 0/1 flag. The base class fills it
  with a plain Items.Assign, so without translation every row carrying anything at all --
  a state object OR the app's own object -- would drop down pre-ticked. }
var
  c: TCheckComboProbe;
  lst: TTyCheckListBox;
  d: TStringList;
begin
  c := TCheckComboProbe.Create(nil);
  lst := TTyCheckListBox.Create(nil);
  d := TStringList.Create;
  try
    c.Items.AddObject('Apple', d);
    c.Items.Add('Banana');
    c.Items.Add('Cherry');
    c.Checked[2] := True;

    lst.Items.Assign(c.Items);            // exactly what TTyComboBox.DropDown does
    c.PushForTest(lst);
    AssertFalse('a row carrying app data must not arrive ticked', lst.Checked[0]);
    AssertFalse('nor a bare row', lst.Checked[1]);
    AssertTrue('and a checked row must', lst.Checked[2]);
    AssertTrue('the popup holds a plain flag, never one of our state objects',
      PtrUInt(lst.Items.Objects[2]) < 4096);

    { the user ticks Apple and unticks Cherry in the popup }
    lst.Checked[0] := True;
    lst.Checked[2] := False;
    c.PullForTest(lst);
    AssertTrue('Apple came back checked', c.Checked[0]);
    AssertFalse('Cherry came back unchecked', c.Checked[2]);
    AssertSame('and the app data survived the round trip', d, c.Objects[0]);
  finally
    d.Free;
    lst.Free;
    c.Free;
  end;
end;

procedure TCheckComboDataParityTest.RefillingItemsDoesNotStrandStates;
{ Items.Clear / Items.Delete drop our pointers without telling us. LCL's model simply
  leaks them; the pool has to collect them, or a combo that refills itself (a filter box)
  grows one state per item per pass for the life of the control. }
var
  c: TCheckComboProbe;
  i, pass: Integer;
begin
  c := TCheckComboProbe.Create(nil);
  try
    for pass := 1 to 20 do
    begin
      c.Items.Clear;
      for i := 0 to 4 do c.Items.Add('Item' + IntToStr(i));
      c.Checked[0] := True;
      c.Checked[3] := True;
    end;
    AssertEquals('the surviving rows are still right', 2, c.CheckedCount);
    AssertTrue('20 refills must not strand 40 states (pool holds ' +
      IntToStr(c.PoolCount) + ')', c.PoolCount <= 20);
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TSpinChangeParityTest);
  RegisterTest(TCheckComboDataParityTest);
end.
