unit test.corehooks;
{$mode objfpc}{$H+}

{ The protected hooks the data-aware controls stand on (issue #34, plan D3).

  A data-aware control has to tell the USER's edits from the values it loads itself, and four
  base controls gave a subclass no way to see the user's: the combo box's typing path and the
  date-time picker's calendar fired OnChange from private code, the radio group's clicks land
  on its child buttons, and the image's picture handler is private. Each now has a virtual
  hook, called where the event fires.

  THE INVARIANT. A hook is the old firing point, renamed -- not a second notification. So every
  test here logs the hook and the event into ONE string, in the order they ran, and compares
  it whole after each gesture: 'CO' is the hook and then OnChange, once each. A site that
  still fires the event directly logs a bare 'O'; a hook called where no event fires logs a
  bare 'C'. Counting the two separately would let a missing hook on one path hide behind an
  extra one on another.

  Every gesture is a real input path -- a key, a click, the wheel, the calendar's own keys --
  except the programmatic writes, which are what they are. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, fpcunit, testregistry,
  tyControls.Types, tyControls.ComboBox, tyControls.DateTimePicker, tyControls.Calendar,
  tyControls.RadioGroup, tyControls.CheckBox, tyControls.Image, tyControls.NumericEdit;

type
  { Hook 'C', OnChange 'O'. }
  THookCombo = class(TTyComboBox)
  protected
    procedure Change; override;
  public
    Log: string;
    constructor Create(AOwner: TComponent); override;
    procedure LogChange(Sender: TObject);
    procedure PressKey(AKey: Word);
    { A form being read: csLoading on, then Loaded. }
    procedure BeginReading;
    procedure EndReading;
  end;

  { Hook 'C', OnChange 'O'. }
  THookPicker = class(TTyDateTimePicker)
  protected
    procedure Change; override;
  public
    Log: string;
    constructor Create(AOwner: TComponent); override;
    procedure LogChange(Sender: TObject);
    procedure PressKey(AKey: Word);
    procedure Wheel(ADelta: Integer);
    { Press and release the left button on the middle of the up (or down) spin button. }
    procedure ClickSpin(AUp: Boolean);
    { The dropdown calendar, created and seeded as OpenDropDown does, without a window. }
    function OpenCalendar: TTyCalendar;
    { A key pressed inside the dropdown calendar. }
    procedure PressCalendarKey(AKey: Word);
  end;

  { Hook 'S', OnSelectionChanged 'E'. }
  THookRadioGroup = class(TTyRadioGroup)
  protected
    procedure SelectionChanged; override;
  public
    Log: string;
    constructor Create(AOwner: TComponent); override;
    procedure LogSelection(Sender: TObject);
  end;

  { Hook 'D', OnPictureChanged 'P'. }
  THookImage = class(TTyImage)
  protected
    procedure DoPictureChanged; override;
  public
    Log: string;
    constructor Create(AOwner: TComponent); override;
    procedure LogPicture(Sender: TObject);
  end;

  THookNumericEdit = class(TTyNumericEdit)
  public
    procedure AllowEmpty(AValue: Boolean);
    function EmptyIsAllowed: Boolean;
    procedure EnterField;
    procedure LeaveField;
  end;

  TCoreHooksTest = class(TTestCase)
  private
    FForm: TForm;
    function NewCombo(AStyle: TTyComboBoxStyle): THookCombo;
    function NewPicker: THookPicker;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { ComboBox.Change }
    procedure TestComboCodeSettingItemIndexCallsChangeThenOnChange;
    procedure TestComboKeyboardPickCallsChangeThenOnChange;
    procedure TestComboPopupPickCallsChangeThenOnChange;
    procedure TestComboPopupPickWithAnEditBoxCallsChangeThenOnChange;
    procedure TestComboTypingCallsChangeThenOnChange;
    procedure TestComboTypingInASimpleComboCallsChangeThenOnChange;
    procedure TestComboStreamedItemIndexCallsNeither;
    { DateTimePicker.Change }
    procedure TestPickerKeyCallsChangeThenOnChange;
    procedure TestPickerWheelCallsChangeThenOnChange;
    procedure TestPickerSpinButtonCallsChangeThenOnChange;
    procedure TestPickerClearingKeyCallsChangeThenOnChange;
    procedure TestPickerCalendarMoveCallsChangeThenOnChange;
    procedure TestPickerCalendarAcceptCallsChangeThenOnChange;
    procedure TestPickerEscapeCallsChangeThenOnChange;
    procedure TestPickerCodeWriteCallsNeitherByDefault;
    procedure TestPickerCodeWriteWithTheOptionCallsChangeThenOnChange;
    { RadioGroup.SelectionChanged }
    procedure TestRadioGroupClickCallsSelectionChangedFirst;
    procedure TestRadioGroupSpaceKeyCallsSelectionChangedFirst;
    procedure TestRadioGroupCodeSettingItemIndexCallsSelectionChangedFirst;
    { Image.DoPictureChanged }
    procedure TestImageLoadFromFileCallsDoPictureChangedFirst;
    procedure TestImageAssignCallsDoPictureChangedFirst;
    procedure TestImageClearCallsDoPictureChangedFirst;
    { NumericEdit.EmptyAllowed }
    procedure TestNumericEditEmptyIsNotAllowedByDefault;
    procedure TestNumericEditAllowingEmptyKeepsAnEmptyFieldEmpty;
    procedure TestNumericEditAllowingEmptyStillFormatsANumber;
  end;

implementation

uses
  DateUtils, dbfixtures;

var
  WidgetSetReady: Boolean = False;

{ The popup tests open a real dropdown, which needs the widgetset's window classes; the
  console runner registers them only when something asks (test.combobox.simple does the
  same, locally, so the suite runs on its own). }
procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

{ A gesture's log: AHook then AEvent, ATimes times over. }
function Pairs(const APair: string; ATimes: Integer): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to ATimes do Result := Result + APair;
end;

{ True when ALog is APair repeated at least once and nothing else. }
function IsPairs(const ALog, APair: string): Boolean;
begin
  Result := (ALog <> '') and (Length(ALog) mod Length(APair) = 0)
    and (ALog = Pairs(APair, Length(ALog) div Length(APair)));
end;

{ ---------------------------------------------------------------- probes ----------------- }

constructor THookCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  OnChange := @LogChange;
end;

procedure THookCombo.Change;
begin
  Log := Log + 'C';
  inherited Change;
end;

procedure THookCombo.LogChange(Sender: TObject);
begin
  Log := Log + 'O';
end;

procedure THookCombo.PressKey(AKey: Word);
begin
  KeyDown(AKey, []);
end;

procedure THookCombo.BeginReading;
begin
  Loading;
end;

procedure THookCombo.EndReading;
begin
  Loaded;
end;

constructor THookPicker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  OnChange := @LogChange;
end;

procedure THookPicker.Change;
begin
  Log := Log + 'C';
  inherited Change;
end;

procedure THookPicker.LogChange(Sender: TObject);
begin
  Log := Log + 'O';
end;

procedure THookPicker.PressKey(AKey: Word);
begin
  KeyDown(AKey, []);
end;

procedure THookPicker.Wheel(ADelta: Integer);
begin
  DoMouseWheel([], ADelta, Point(Width div 2, Height div 2));
end;

procedure THookPicker.ClickSpin(AUp: Boolean);
var
  L: TTyDateTimeRects;
  S: TTyStyleSet;
  sz, origin: Integer;
  txt: string;
  spans: TTySegmentArray;
  r: TRect;
  c: TPoint;
begin
  FieldLayout(ClientRect, Font.PixelsPerInch, L, S, sz, txt, spans, origin);
  if AUp then r := L.ButtonUp else r := L.ButtonDown;
  if IsRectEmpty(r) then raise Exception.Create('the picker shows no spin button');
  c := CenterPoint(r);
  MouseDown(mbLeft, [ssLeft], c.X, c.Y);
  MouseUp(mbLeft, [], c.X, c.Y);
end;

function THookPicker.OpenCalendar: TTyCalendar;
begin
  EnsurePopup;
  SeedPopupCalendar;
  Result := Calendar;
end;

type
  TCalendarKeys = class(TTyCalendar);

procedure THookPicker.PressCalendarKey(AKey: Word);
begin
  TCalendarKeys(Calendar).KeyDown(AKey, []);
end;

constructor THookRadioGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  OnSelectionChanged := @LogSelection;
end;

procedure THookRadioGroup.SelectionChanged;
begin
  Log := Log + 'S';
  inherited SelectionChanged;
end;

procedure THookRadioGroup.LogSelection(Sender: TObject);
begin
  Log := Log + 'E';
end;

constructor THookImage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  OnPictureChanged := @LogPicture;
end;

procedure THookImage.DoPictureChanged;
begin
  Log := Log + 'D';
  inherited DoPictureChanged;
end;

procedure THookImage.LogPicture(Sender: TObject);
begin
  Log := Log + 'P';
end;

procedure THookNumericEdit.AllowEmpty(AValue: Boolean);
begin
  EmptyAllowed := AValue;
end;

function THookNumericEdit.EmptyIsAllowed: Boolean;
begin
  Result := EmptyAllowed;
end;

procedure THookNumericEdit.EnterField;
begin
  DoEnter;
end;

procedure THookNumericEdit.LeaveField;
begin
  DoExit;
end;

{ ---------------------------------------------------------------- fixture ---------------- }

procedure TCoreHooksTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
end;

procedure TCoreHooksTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TCoreHooksTest.NewCombo(AStyle: TTyComboBoxStyle): THookCombo;
begin
  Result := THookCombo.Create(FForm);
  Result.Parent := FForm;
  Result.SetBounds(8, 8, 200, 160);
  Result.Style := AStyle;
  Result.Items.Add('Alpha');
  Result.Items.Add('Beta');
  Result.Items.Add('Gamma');
  Result.Log := '';
end;

function TCoreHooksTest.NewPicker: THookPicker;
begin
  Result := THookPicker.Create(FForm);
  Result.Parent := FForm;
  Result.SetBounds(8, 8, 220, 28);
  Result.Kind := dtkDate;
  Result.DateTime := EncodeDate(2026, 3, 14);
  Result.Log := '';
end;

{ ---------------------------------------------------------------- ComboBox --------------- }

procedure TCoreHooksTest.TestComboCodeSettingItemIndexCallsChangeThenOnChange;
var
  c: THookCombo;
begin
  c := NewCombo(csDropDownList);
  c.ItemIndex := 1;
  AssertEquals('a code write: hook, then event', 'CO', c.Log);
  c.ItemIndex := 1;
  AssertEquals('the same index again: neither', 'CO', c.Log);
end;

procedure TCoreHooksTest.TestComboKeyboardPickCallsChangeThenOnChange;
var
  c: THookCombo;
begin
  c := NewCombo(csDropDownList);
  c.ItemIndex := 0;
  c.Log := '';
  c.PressKey(VK_DOWN);
  AssertEquals('precondition: Down picked the next row', 1, c.ItemIndex);
  AssertEquals('a keyboard pick: hook, then event', 'CO', c.Log);
end;

procedure TCoreHooksTest.TestComboPopupPickCallsChangeThenOnChange;
var
  c: THookCombo;
begin
  c := NewCombo(csDropDownList);
  c.DropDown;
  try
    c.PopupList.SelectItem(2);   { the row the user chose in the open list }
    Forms.Application.ProcessMessages;
    AssertEquals('precondition: the row was taken', 2, c.ItemIndex);
    AssertEquals('a pick from the list: hook, then event', 'CO', c.Log);
  finally
    c.CloseUp;
  end;
end;

procedure TCoreHooksTest.TestComboPopupPickWithAnEditBoxCallsChangeThenOnChange;
var
  c: THookCombo;
begin
  { The editable combo commits a pick by its own path (it writes the field, not SelectItem). }
  c := NewCombo(csDropDown);
  c.DropDown;
  try
    c.PopupList.SelectItem(1);
    Forms.Application.ProcessMessages;
    AssertEquals('precondition: the row was taken', 'Beta', c.Text);
    AssertEquals('a pick into the edit box: hook, then event', 'CO', c.Log);
  finally
    c.CloseUp;
  end;
end;

procedure TCoreHooksTest.TestComboTypingCallsChangeThenOnChange;
var
  c: THookCombo;
begin
  c := NewCombo(csDropDown);
  try
    c.SimulateTypedTextForTest('Gam');
    AssertEquals('precondition: the field holds what was typed', 'Gam', c.Text);
    AssertEquals('typing: hook, then event', 'CO', c.Log);
    c.SimulateTypedTextForTest('Gamma');
    AssertEquals('each keystroke once', 'COCO', c.Log);
  finally
    c.CloseUp;
  end;
end;

procedure TCoreHooksTest.TestComboTypingInASimpleComboCallsChangeThenOnChange;
var
  c: THookCombo;
begin
  c := NewCombo(csSimple);
  c.SimulateTypedTextForTest('Beta');
  AssertEquals('precondition: the exact match is selected', 1, c.ItemIndex);
  AssertEquals('typing in csSimple: hook, then event', 'CO', c.Log);
end;

procedure TCoreHooksTest.TestComboStreamedItemIndexCallsNeither;
var
  c: THookCombo;
begin
  { A form file whose ItemIndex comes before its Items: the index waits for Loaded. Reading a
    form is nobody's edit -- the event never heard of it, and the hook must not either, or a
    data-aware combo would put its record into edit mode while its form loads. }
  c := THookCombo.Create(FForm);
  c.BeginReading;
  c.ItemIndex := 2;            { no rows yet: waits }
  c.Items.Add('Alpha');
  c.Items.Add('Beta');
  c.Items.Add('Gamma');
  c.Log := '';
  c.EndReading;
  AssertEquals('precondition: Loaded applied the waiting index', 2, c.ItemIndex);
  AssertEquals('reading a form: neither hook nor event', '', c.Log);
end;

{ ---------------------------------------------------------------- DateTimePicker --------- }

procedure TCoreHooksTest.TestPickerKeyCallsChangeThenOnChange;
var
  p: THookPicker;
  before: TDateTime;
begin
  p := NewPicker;
  before := p.DateTime;
  p.PressKey(VK_UP);
  AssertFalse('precondition: Up stepped the field', SameDateTime(before, p.DateTime));
  AssertEquals('a key: hook, then event', 'CO', p.Log);
end;

procedure TCoreHooksTest.TestPickerWheelCallsChangeThenOnChange;
var
  p: THookPicker;
  before: TDateTime;
begin
  p := NewPicker;
  before := p.DateTime;
  p.Wheel(120);
  AssertFalse('precondition: the wheel stepped the field', SameDateTime(before, p.DateTime));
  AssertEquals('the wheel: hook, then event', 'CO', p.Log);
end;

procedure TCoreHooksTest.TestPickerSpinButtonCallsChangeThenOnChange;
var
  p: THookPicker;
  before: TDateTime;
begin
  p := NewPicker;
  p.DateMode := dmUpDown;
  p.Log := '';
  before := p.DateTime;
  p.ClickSpin(True);
  AssertFalse('precondition: the button stepped the field', SameDateTime(before, p.DateTime));
  AssertEquals('a spin button: hook, then event', 'CO', p.Log);
end;

procedure TCoreHooksTest.TestPickerClearingKeyCallsChangeThenOnChange;
var
  p: THookPicker;
begin
  p := NewPicker;
  p.PressKey(VK_DELETE);
  AssertTrue('precondition: Delete emptied the field', p.DateIsNull);
  AssertEquals('emptying it: hook, then event', 'CO', p.Log);
end;

procedure TCoreHooksTest.TestPickerCalendarMoveCallsChangeThenOnChange;
var
  p: THookPicker;
  before: TDateTime;
begin
  p := NewPicker;
  before := p.DateTime;
  p.OpenCalendar;
  p.Log := '';
  p.PressCalendarKey(VK_RIGHT);   { the arrow inside the open calendar moves the day }
  AssertEquals('precondition: the picker followed the calendar',
    DateToStr(IncDay(before)), DateToStr(p.DateTime));
  AssertEquals('a move in the calendar: hook, then event', 'CO', p.Log);
end;

procedure TCoreHooksTest.TestPickerCalendarAcceptCallsChangeThenOnChange;
var
  p: THookPicker;
  cal: TTyCalendar;
begin
  { An empty field, the calendar opened over it, Enter: the day the calendar shows fills the
    field. Nothing moved inside the calendar, so this is the accept path's own notification
    and not the move path's. }
  p := NewPicker;
  p.PressKey(VK_DELETE);
  AssertTrue('precondition: empty', p.DateIsNull);
  cal := p.OpenCalendar;
  p.Log := '';
  p.PressCalendarKey(VK_RETURN);
  AssertFalse('precondition: Enter filled the field', p.DateIsNull);
  AssertEquals('with the calendar''s day', DateToStr(cal.Date), DateToStr(p.DateTime));
  AssertEquals('accepting a day: hook, then event', 'CO', p.Log);
end;

procedure TCoreHooksTest.TestPickerEscapeCallsChangeThenOnChange;
var
  p: THookPicker;
  before: TDateTime;
begin
  p := NewPicker;
  before := p.DateTime;
  p.PressKey(VK_UP);
  p.Log := '';
  p.PressKey(VK_ESCAPE);
  AssertTrue('precondition: Escape undid the step', SameDateTime(before, p.DateTime));
  AssertEquals('the undo: hook, then event', 'CO', p.Log);
end;

procedure TCoreHooksTest.TestPickerCodeWriteCallsNeitherByDefault;
var
  p: THookPicker;
begin
  p := NewPicker;
  p.DateTime := EncodeDate(2027, 1, 2);
  AssertEquals('a code write without dtpoDoChangeOnSetDateTime: neither', '', p.Log);
end;

procedure TCoreHooksTest.TestPickerCodeWriteWithTheOptionCallsChangeThenOnChange;
var
  p: THookPicker;
begin
  p := NewPicker;
  p.Options := p.Options + [dtpoDoChangeOnSetDateTime];
  p.Log := '';
  p.DateTime := EncodeDate(2027, 1, 2);
  AssertEquals('a code write with the option: hook, then event', 'CO', p.Log);
end;

{ ---------------------------------------------------------------- RadioGroup ------------- }

procedure TCoreHooksTest.TestRadioGroupClickCallsSelectionChangedFirst;
var
  g: THookRadioGroup;
begin
  g := THookRadioGroup.Create(FForm);
  g.Parent := FForm;
  g.SetBounds(8, 8, 200, 120);
  g.Items.Add('One');
  g.Items.Add('Two');
  g.Items.Add('Three');
  g.Log := '';
  g.Buttons[1].Click;           { the option the user clicked -- a child, not the group }
  AssertEquals('precondition: the click selected it', 1, g.ItemIndex);
  AssertEquals('a click: hook, then event', 'SE', g.Log);
end;

type
  TRadioKeys = class(TTyRadioButton);

procedure TCoreHooksTest.TestRadioGroupSpaceKeyCallsSelectionChangedFirst;
var
  g: THookRadioGroup;
  k: Word;
begin
  g := THookRadioGroup.Create(FForm);
  g.Parent := FForm;
  g.SetBounds(8, 8, 200, 120);
  g.Items.Add('One');
  g.Items.Add('Two');
  g.Log := '';
  k := VK_SPACE;
  TRadioKeys(g.Buttons[1]).KeyDown(k, []);
  AssertEquals('precondition: Space selected it', 1, g.ItemIndex);
  AssertEquals('a key: hook, then event', 'SE', g.Log);
end;

procedure TCoreHooksTest.TestRadioGroupCodeSettingItemIndexCallsSelectionChangedFirst;
var
  g: THookRadioGroup;
begin
  g := THookRadioGroup.Create(FForm);
  g.Parent := FForm;
  g.Items.Add('One');
  g.Items.Add('Two');
  g.Log := '';
  g.ItemIndex := 0;
  AssertEquals('a code write: hook, then event', 'SE', g.Log);
end;

{ ---------------------------------------------------------------- Image ------------------ }

procedure TCoreHooksTest.TestImageLoadFromFileCallsDoPictureChangedFirst;
var
  img: THookImage;
  fn: string;
  bytes: TBytes;
  fs: TFileStream;
begin
  fn := GetTempDir + 'tycorehooks_' + IntToStr(GetProcessID) + '.png';
  bytes := FixPng(4, 3, $FFFF, $8000, 0);
  fs := TFileStream.Create(fn, fmCreate);
  try
    fs.WriteBuffer(bytes[0], Length(bytes));
  finally
    fs.Free;
  end;
  img := THookImage.Create(FForm);
  try
    img.Parent := FForm;
    img.Log := '';
    img.Picture.LoadFromFile(fn);
    AssertEquals('precondition: the picture loaded', 4, img.Picture.Width);
    AssertTrue('a load: hook before event, once each per change -- got ' + img.Log,
      IsPairs(img.Log, 'DP'));
  finally
    DeleteFile(fn);
  end;
end;

procedure TCoreHooksTest.TestImageAssignCallsDoPictureChangedFirst;
var
  img: THookImage;
  src: TPicture;
  bmp: TBitmap;
begin
  img := THookImage.Create(FForm);
  img.Parent := FForm;
  src := TPicture.Create;
  bmp := TBitmap.Create;
  try
    bmp.SetSize(5, 2);
    src.Assign(bmp);
    img.Log := '';
    img.Picture.Assign(src);
    AssertEquals('precondition: the picture arrived', 5, img.Picture.Width);
    AssertTrue('an assign: hook before event, once each per change -- got ' + img.Log,
      IsPairs(img.Log, 'DP'));
  finally
    bmp.Free;
    src.Free;
  end;
end;

procedure TCoreHooksTest.TestImageClearCallsDoPictureChangedFirst;
var
  img: THookImage;
  bmp: TBitmap;
begin
  img := THookImage.Create(FForm);
  img.Parent := FForm;
  bmp := TBitmap.Create;
  try
    bmp.SetSize(5, 2);
    img.Picture.Assign(bmp);
  finally
    bmp.Free;
  end;
  img.Log := '';
  img.Picture.Clear;
  AssertTrue('precondition: the picture is gone', img.Picture.Graphic = nil);
  AssertTrue('a clear: hook before event, once each per change -- got ' + img.Log,
    IsPairs(img.Log, 'DP'));
end;

{ ---------------------------------------------------------------- NumericEdit ------------ }

procedure TCoreHooksTest.TestNumericEditEmptyIsNotAllowedByDefault;
var
  e: THookNumericEdit;
begin
  e := THookNumericEdit.Create(FForm);
  e.Parent := FForm;
  AssertFalse('EmptyAllowed is off unless a subclass turns it on', e.EmptyIsAllowed);
  { ...and off means what it always meant: an emptied field leaves as a zero. }
  e.EnterField;
  e.Text := '';
  e.LeaveField;
  AssertEquals('an empty field reads back as 0.00 on leaving', '0.00', e.Text);
end;

procedure TCoreHooksTest.TestNumericEditAllowingEmptyKeepsAnEmptyFieldEmpty;
var
  e: THookNumericEdit;
begin
  e := THookNumericEdit.Create(FForm);
  e.Parent := FForm;
  e.AllowEmpty(True);
  e.Text := '';
  e.EnterField;
  AssertEquals('entering keeps it empty', '', e.Text);
  e.LeaveField;
  AssertEquals('leaving keeps it empty', '', e.Text);
  AssertEquals('and its value reads 0', 0, e.Value, 0);
  e.Decimals := 3;               { a display property re-derives the text when not focused }
  AssertEquals('a reformat keeps it empty', '', e.Text);
end;

procedure TCoreHooksTest.TestNumericEditAllowingEmptyStillFormatsANumber;
var
  e: THookNumericEdit;
begin
  { The switch is about the EMPTY field only: a number still reformats on the way out. }
  e := THookNumericEdit.Create(FForm);
  e.Parent := FForm;
  e.AllowEmpty(True);
  e.EnterField;
  e.Text := '1234.5';
  e.LeaveField;
  AssertEquals('1,234.50', e.Text);
end;

initialization
  RegisterTest(TCoreHooksTest);
end.
