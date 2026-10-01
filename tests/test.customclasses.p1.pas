unit test.customclasses.p1;
{$mode objfpc}{$H+}

{ Custom-class split, phase 1 (input and display controls). Three kinds of test live here:

  * THIRD-PARTY MIMICS. A class the way issue #8 wants to write one: derived from a
    TTyCustomXxx, publishing two properties of its own choosing and nothing else. Each is held
    to the same checks -- it can be created on a form (T-a), it publishes exactly its LCL root's
    names plus the two (T-b), those two survive a stream round trip while a property it did NOT
    publish stays out of the text (T-c), it resolves the same theme type key -- and where the
    family has a RenderTo, paints the same pixels -- as the library's own final class (T-d), a
    fresh instance streams neither of its two properties, i.e. their declared defaults match the
    constructor (T-e), and a property the plan puts in public is reachable through a
    TTyCustomXxx reference (T-v, a compile-time check).
  * DERIVED CONTROLS SEEN BY THEIR FAMILY. From 4.0 on a TTyGlyphButton is a TTyCustomButton but
    no longer a TTyButton, the LCL way. Library code that meant "any button" had to change its
    `is TTyButton` to the custom class; each such change has a test here that fails when the
    check is put back.
  * CHECKS WIDENED FOR THIRD PARTIES. Grouping and ownership checks that now accept any
    TTyCustomXxx descendant, proven with a mimic in the group. }

interface

uses
  Classes, SysUtils, TypInfo, Controls, Forms, Graphics, LCLType, fpcunit, testregistry,
  test.customclasses,
  tyControls.Base, tyControls.Button, tyControls.GlyphButtons, tyControls.ToolBar,
  tyControls.ToolBarEx, tyControls.TyLabel, tyControls.Tag, tyControls.TextMenu, tyControls.Edit,
  tyControls.MaskEdit, tyControls.Memo, tyControls.UpDown, tyControls.NumericEdit,
  tyControls.FloatSpinEdit, tyControls.CheckBox, tyControls.ListBox, tyControls.ComboBox,
  tyControls.ComboBoxEx, tyControls.ColorBox, tyControls.ColorComboBox, tyControls.ShellComboBox,
  tyControls.ProgressBar, tyControls.Gauge, tyControls.TrackBar;

type
  TTyCustomClassesP1Test = class(TTestCase)
  private
    FForm: TForm;
    FDrawCalls: Integer;
    procedure CountDraw(Sender: TObject; ACanvas: TCanvas; Index: Integer; ARect: TRect;
      AState: TOwnerDrawState);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
    { T-b: AClass publishes its LCL root's names plus ANames, nothing else. }
    procedure CheckPublishesOnly(AClass: TClass; const ANames: array of string);
    { T-c: AShown appear in the streamed text of AComp, AHidden does not. }
    procedure CheckStreamText(AComp: TComponent; const AShown: array of string;
      const AHidden: string);
    { T-e: a fresh instance of AClass streams none of ANames; an ordinal one also reads back its
      declared default. }
    procedure CheckFreshDefaults(AClass: TComponentClass; const ANames: array of string);
    { T-d: both resolve the same theme type key. }
    procedure CheckSameTypeKey(AThird, AFinal: TComponent);
  published
    { Task 2: buttons }
    procedure TestFlatToolBarGhostsGlyphAndSpeedButtons;
    procedure TestFlatToolBarExGhostsGlyphAndSpeedButtons;
    procedure TestSpeedButtonGroupTakesAThirdPartyMember;
    procedure TestThirdButton;
    procedure TestThirdSpeedButton;
    { Task 3: labels }
    procedure TestThirdLabel;
    procedure TestThirdTag;
    { Task 4: edits I }
    procedure TestThirdEdit;
    procedure TestThirdMaskEdit;
    { Task 5: edits II }
    procedure TestThirdMemo;
    procedure TestThirdUpDown;
    procedure TestUpDownAssociationIsExclusiveAcrossThirdParties;
    procedure TestFloatSpinEditKeepsItsUseThousandsDefault;
    { Task 6: choice }
    procedure TestThirdCheckBox;
    procedure TestThirdRadioButton;
    procedure TestRadioGroupTakesAThirdPartyMember;
    { Task 7: combo boxes I }
    procedure TestDerivedComboPopupReachesTheOwnerDraw;
    procedure TestThirdComboBoxExItemsDriveTheList;
    procedure TestThirdComboBox;
    { Task 8: combo boxes II }
    procedure TestColorBoxPopupUsesItsOwnSwatchGeometry;
    procedure TestThirdColorBox;
    procedure TestThirdShellComboBox;
    { Task 9: progress and indicators }
    procedure TestThirdProgressBar;
    procedure TestThirdGauge;
    { Task 10: dials and sliders }
    procedure TestThirdTrackBar;
  end;

  { --- third-party mimics ------------------------------------------------------------ }

  TThirdButton = class(TTyCustomButton)
  published
    property Caption;
    property Down;
  end;

  TThirdSpeedButton = class(TTyCustomSpeedButton)
  published
    property GroupIndex;
    property Down;
  end;

  TThirdLabel = class(TTyCustomLabel)
  published
    property Caption;
    property WordWrap;
  end;

  TThirdTag = class(TTyCustomTag)
  published
    property Caption;
    property Closable;
  end;

  TThirdEdit = class(TTyCustomEdit)
  published
    property Text;
    property ReadOnly;
  end;

  { Mask rather than EditMask: EditMask is the LCL-spelled alias and is `stored False`, so it
    could not show up in a streamed text. }
  TThirdMaskEdit = class(TTyCustomMaskEdit)
  published
    property Mask;
    property Text;
  end;

  TThirdMemo = class(TTyCustomMemo)
  published
    property Lines;
    property ReadOnly;
  end;

  TThirdUpDown = class(TTyCustomUpDown)
  published
    property Associate;
    property Position;
  end;

  TThirdCheckBox = class(TTyCustomCheckBox)
  published
    property Checked;
    property Caption;
  end;

  TThirdRadioButton = class(TTyCustomRadioButton)
  published
    property Checked;
    property GroupIndex;
  end;

  TThirdComboBox = class(TTyCustomComboBox)
  published
    property Items;
    property ItemIndex;
  end;

  TThirdComboBoxEx = class(TTyCustomComboBoxEx)
  published
    property ItemsEx;
    property Images;
  end;

  TThirdColorBox = class(TTyCustomColorBox)
  published
    property Selected;
    property Style;
  end;

  TThirdShellComboBox = class(TTyCustomShellComboBox)
  published
    property Directory;
    property Items;
  end;

  { Max before Position on purpose: the order a descendant publishes in is the order its .lfm
    is written in. }
  TThirdProgressBar = class(TTyCustomProgressBar)
  published
    property Max;
    property Position;
  end;

  { Max before Value: the reader applies properties in the order they were published, and a
    Value read before its Max is clamped to the default Max of 100. }
  TThirdGauge = class(TTyCustomGauge)
  published
    property Max;
    property Value;
  end;

  TThirdTrackBar = class(TTyCustomTrackBar)
  published
    property Position;
    property Max;
  end;

{ The streamed text of AComp (ObjectBinaryToText of WriteComponent). }
function StreamedText(AComp: TComponent): string;
{ Stream ASrc and read it back into ADst. }
procedure StreamInto(ASrc, ADst: TComponent);
{ Fill with a sentinel, then compare every pixel. }
function SameBitmaps(A, B: TBitmap; out AFirstDiff: string): Boolean;

implementation

type
  TP1ButtonCracker = class(TTyCustomButton)
  public
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect);
  end;

  { Reaches the label's protected layout properties (D3: protected, as in TCustomLabel) and
    its renderer. }
  TP1LabelCracker = class(TTyCustomLabel)
  public
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect);
    procedure SetLayoutTo(AValue: TTextLayout);
    function LayoutNow: TTextLayout;
  end;

  { SpaceChar is protected on the custom class (TCustomMaskEdit keeps it protected). }
  TP1MaskCracker = class(TTyCustomMaskEdit)
  public
    procedure SetSpace(AValue: Char);
    function SpaceNow: Char;
  end;

  { The up-down's own properties are protected (TCustomUpDown keeps them protected). }
  TP1UpDownCracker = class(TTyCustomUpDown)
  public
    procedure SetIncrementTo(AValue: Integer);
    function IncrementNow: Integer;
  end;

  { CreatePopupList is protected: this builds the list a combo would drop. }
  TP1ComboCracker = class(TTyCustomComboBox)
  public
    function MakePopupList: TTyListBox;
  end;

  { Two descendants that publish nothing but TabStop: on the bare base it carries LCL's
    `default False`; on the track bar's custom class it carries the redeclared True. }
  TP1BareTabStop = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  published
    property TabStop;
  end;

  TP1TrackBarTabStop = class(TTyCustomTrackBar)
  published
    property TabStop;
  end;

  TP1ToolBar = class(TTyToolBar)
  public
    procedure ForceLayout;
  end;

  TP1ToolBarEx = class(TTyToolBarEx)
  public
    procedure ForceLayout;
  end;

const
  CSentinel = TColor($00FF00FF);

procedure TP1ButtonCracker.DoRender(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderTo(ACanvas, ARect, 96);
end;

procedure TP1LabelCracker.DoRender(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderTo(ACanvas, ARect, 96);
end;

procedure TP1LabelCracker.SetLayoutTo(AValue: TTextLayout);
begin
  Layout := AValue;
end;

function TP1LabelCracker.LayoutNow: TTextLayout;
begin
  Result := Layout;
end;

procedure TP1MaskCracker.SetSpace(AValue: Char);
begin
  SpaceChar := AValue;
end;

function TP1MaskCracker.SpaceNow: Char;
begin
  Result := SpaceChar;
end;

procedure TP1UpDownCracker.SetIncrementTo(AValue: Integer);
begin
  Increment := AValue;
end;

function TP1UpDownCracker.IncrementNow: Integer;
begin
  Result := Increment;
end;

function TP1ComboCracker.MakePopupList: TTyListBox;
begin
  Result := CreatePopupList;
end;

function TP1BareTabStop.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;

procedure TP1ToolBar.ForceLayout;
var r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AlignControls(nil, r);
end;

procedure TP1ToolBarEx.ForceLayout;
var r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AlignControls(nil, r);
end;

function StreamedText(AComp: TComponent): string;
var
  ms: TMemoryStream;
  ss: TStringStream;
begin
  ms := TMemoryStream.Create;
  ss := TStringStream.Create('');
  try
    ms.WriteComponent(AComp);
    ms.Position := 0;
    ObjectBinaryToText(ms, ss);
    Result := ss.DataString;
  finally
    ms.Free;
    ss.Free;
  end;
end;

procedure StreamInto(ASrc, ADst: TComponent);
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(ASrc);
    ms.Position := 0;
    ms.ReadComponent(ADst);
  finally
    ms.Free;
  end;
end;

function SameBitmaps(A, B: TBitmap; out AFirstDiff: string): Boolean;
var
  x, y: Integer;
begin
  AFirstDiff := '';
  if (A.Width <> B.Width) or (A.Height <> B.Height) then
  begin
    AFirstDiff := 'sizes differ';
    Exit(False);
  end;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.Canvas.Pixels[x, y] <> B.Canvas.Pixels[x, y] then
      begin
        AFirstDiff := Format('(%d,%d): %.6x vs %.6x', [x, y, A.Canvas.Pixels[x, y],
          B.Canvas.Pixels[x, y]]);
        Exit(False);
      end;
  Result := True;
end;

function NewSentinelBitmap(AW, AH: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := CSentinel;
  Result.Canvas.FillRect(0, 0, AW, AH);
end;

function HasProp(const AText, AName: string): Boolean;
begin
  { `Name = value`, or `Name.Strings = (` for a TStrings property. }
  Result := (Pos(' ' + AName + ' = ', AText) > 0) or (Pos(' ' + AName + '.', AText) > 0);
end;

{ ------------------------------------------------------------------ fixture }

procedure TTyCustomClassesP1Test.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
end;

procedure TTyCustomClassesP1Test.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TTyCustomClassesP1Test.CountDraw(Sender: TObject; ACanvas: TCanvas; Index: Integer;
  ARect: TRect; AState: TOwnerDrawState);
begin
  Inc(FDrawCalls);
end;

procedure TTyCustomClassesP1Test.CheckPublishesOnly(AClass: TClass; const ANames: array of string);
var
  want, got: TStringList;
  i: Integer;
begin
  want := PublishedNames(LclRootOf(AClass.ClassParent));
  got := PublishedNames(AClass);
  try
    for i := Low(ANames) to High(ANames) do
      want.Add(ANames[i]);
    AssertEquals('T-b: ' + AClass.ClassName + ' publishes its LCL root''s names plus its own',
      want.CommaText, got.CommaText);
  finally
    want.Free;
    got.Free;
  end;
end;

procedure TTyCustomClassesP1Test.CheckStreamText(AComp: TComponent; const AShown: array of string;
  const AHidden: string);
var
  txt: string;
  i: Integer;
begin
  txt := StreamedText(AComp);
  for i := Low(AShown) to High(AShown) do
    AssertTrue('T-c: ' + AComp.ClassName + ' streams ' + AShown[i] + ':' + LineEnding + txt,
      HasProp(txt, AShown[i]));
  if AHidden <> '' then
    AssertFalse('T-c: ' + AComp.ClassName + ' did not publish ' + AHidden + ', so it must not '
      + 'stream it:' + LineEnding + txt, HasProp(txt, AHidden));
end;

procedure TTyCustomClassesP1Test.CheckFreshDefaults(AClass: TComponentClass;
  const ANames: array of string);
var
  inst: TComponent;
  txt: string;
  i: Integer;
  pi: PPropInfo;
begin
  inst := AClass.Create(FForm);
  try
    if inst is TControl then TControl(inst).Parent := FForm;
    txt := StreamedText(inst);
    for i := Low(ANames) to High(ANames) do
    begin
      AssertFalse('T-e: a fresh ' + AClass.ClassName + ' streams ' + ANames[i]
        + ' -- its declared default disagrees with the constructor:' + LineEnding + txt,
        HasProp(txt, ANames[i]));
      pi := GetPropInfo(inst, ANames[i]);
      AssertTrue('T-e: ' + ANames[i] + ' is published', pi <> nil);
      if (pi^.PropType^.Kind in [tkInteger, tkChar, tkEnumeration, tkSet, tkWChar, tkBool])
         and (pi^.Default <> Low(LongInt)) then
        AssertEquals('T-e: ' + AClass.ClassName + '.' + ANames[i] + ' reads its declared default',
          pi^.Default, GetOrdProp(inst, pi));
    end;
  finally
    inst.Free;
  end;
end;

procedure TTyCustomClassesP1Test.CheckSameTypeKey(AThird, AFinal: TComponent);
var
  a, b: ITyStyleable;
begin
  AssertTrue('T-d: ' + AThird.ClassName + ' is styleable', Supports(AThird, ITyStyleable, a));
  AssertTrue('T-d: ' + AFinal.ClassName + ' is styleable', Supports(AFinal, ITyStyleable, b));
  AssertEquals('T-d: ' + AThird.ClassName + ' resolves the same theme rules as '
    + AFinal.ClassName, b.GetStyleTypeKey, a.GetStyleTypeKey);
end;

{ ------------------------------------------------------------------ Task 2: buttons }

{ S2-1. A flat bar dresses every push button on it in the 'ghost' variant. Before 4.0 the bar
  asked `is TTyButton`, which every glyph, speed and tool button answered True; on the custom
  chain they answer False, and only `is TTyCustomButton` still finds them. }
procedure TTyCustomClassesP1Test.TestFlatToolBarGhostsGlyphAndSpeedButtons;
var
  bar: TP1ToolBar;
  g: TTyGlyphButton;
  s: TTySpeedButton;
begin
  bar := TP1ToolBar.Create(FForm);
  bar.Parent := FForm;
  bar.Align := alNone;
  bar.SetBounds(0, 0, 400, 40);
  AssertTrue('the bar is flat (or this proves nothing)', bar.Flat);
  g := TTyGlyphButton.Create(FForm);
  g.Parent := bar;
  s := TTySpeedButton.Create(FForm);
  s.Parent := bar;
  AssertFalse('a glyph button is not a TTyButton since 4.0 (or this proves nothing)',
    TObject(g) is TTyButton);
  AssertEquals('precondition: unstyled', '', g.StyleClass);
  bar.ForceLayout;
  AssertEquals('the flat bar ghosts a glyph button', 'ghost', g.StyleClass);
  AssertEquals('and a speed button', 'ghost', s.StyleClass);
end;

{ S2-2. TTyToolBarEx keeps its own copy of the flat rule (it never calls ApplyToButton). }
procedure TTyCustomClassesP1Test.TestFlatToolBarExGhostsGlyphAndSpeedButtons;
var
  bar: TP1ToolBarEx;
  g: TTyGlyphButton;
  s: TTySpeedButton;
begin
  bar := TP1ToolBarEx.Create(FForm);
  bar.Parent := FForm;
  bar.Align := alNone;
  bar.Wrapable := False;
  bar.SetBounds(0, 0, 400, 40);
  AssertTrue('the bar is flat (or this proves nothing)', bar.Flat);
  g := TTyGlyphButton.Create(FForm);
  g.Parent := bar;
  g.Width := 60;
  s := TTySpeedButton.Create(FForm);
  s.Parent := bar;
  bar.ForceLayout;
  AssertEquals('the flat Ex bar ghosts a glyph button', 'ghost', g.StyleClass);
  AssertEquals('and a speed button', 'ghost', s.StyleClass);
end;

{ S1-1. A third party's speed button joins a group of the library's own: pressing either
  releases the other, both ways. }
procedure TTyCustomClassesP1Test.TestSpeedButtonGroupTakesAThirdPartyMember;
var
  own: TTySpeedButton;
  third: TThirdSpeedButton;
begin
  own := TTySpeedButton.Create(FForm);
  own.Parent := FForm;
  own.GroupIndex := 1;
  third := TThirdSpeedButton.Create(FForm);
  third.Parent := FForm;
  third.GroupIndex := 1;
  own.Down := True;
  third.Down := True;
  AssertFalse('pressing the third-party member releases the library''s', own.Down);
  own.Down := True;
  AssertFalse('and the other way round', third.Down);
  AssertTrue('FindDownButton sees the group across both', own.FindDownButton = own);
end;

procedure TTyCustomClassesP1Test.TestThirdButton;
var
  third, back: TThirdButton;
  own: TTyButton;
  c: TTyCustomButton;
  bmA, bmB: TBitmap;
  diff: string;
begin
  { T-a }
  third := TThirdButton.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(10, 10, 88, 30);
  { T-b }
  CheckPublishesOnly(TThirdButton, ['Caption', 'Down']);
  { T-c: ModalResult is public on the custom class, so the mimic did not publish it. }
  third.Caption := 'Hello';
  third.Down := True;
  third.ModalResult := mrOk;
  CheckStreamText(third, ['Caption', 'Down'], 'ModalResult');
  back := TThirdButton.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Caption round-trips', 'Hello', back.Caption);
  AssertTrue('T-c: Down round-trips', back.Down);
  { T-d }
  own := TTyButton.Create(FForm);
  own.Parent := FForm;
  own.SetBounds(10, 50, 88, 30);
  own.Caption := 'Hello';
  third.Down := False;
  CheckSameTypeKey(third, own);
  bmA := NewSentinelBitmap(88, 30);
  bmB := NewSentinelBitmap(88, 30);
  try
    TP1ButtonCracker(third).DoRender(bmA.Canvas, Rect(0, 0, 88, 30));
    TP1ButtonCracker(own).DoRender(bmB.Canvas, Rect(0, 0, 88, 30));
    AssertTrue('T-d: the mimic paints exactly what TTyButton paints: ' + diff,
      SameBitmaps(bmA, bmB, diff));
  finally
    bmA.Free;
    bmB.Free;
  end;
  { T-e }
  CheckFreshDefaults(TThirdButton, ['Caption', 'Down']);
  { T-v: ModalResult and AllowAllUp are public on the custom classes (TCustomButton). }
  c := third;
  c.ModalResult := mrCancel;
  AssertEquals('T-v: public through a TTyCustomButton reference', Ord(mrCancel), Ord(c.ModalResult));
end;

procedure TTyCustomClassesP1Test.TestThirdSpeedButton;
var
  third, back: TThirdSpeedButton;
  own: TTySpeedButton;
  c: TTyCustomSpeedButton;
begin
  third := TThirdSpeedButton.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdSpeedButton, ['GroupIndex', 'Down']);
  third.GroupIndex := 2;
  third.Down := True;
  third.AllowAllUp := True;
  CheckStreamText(third, ['GroupIndex', 'Down'], 'AllowAllUp');
  back := TThirdSpeedButton.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: GroupIndex round-trips', 2, back.GroupIndex);
  AssertTrue('T-c: Down round-trips', back.Down);
  own := TTySpeedButton.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  AssertEquals('T-d: and it is the speed button''s own key', 'TySpeedButton',
    (own as ITyStyleable).GetStyleTypeKey);
  CheckFreshDefaults(TThirdSpeedButton, ['GroupIndex', 'Down']);
  { A speed button stays out of the tab cycle; the redeclared default lives in the custom
    class, so the mimic gets it too. }
  AssertFalse('T-e: the mimic is not a tab stop, like TTySpeedButton', third.TabStop);
  AssertEquals('T-e: and TabStop''s declared default on the custom class says so', 0,
    GetPropInfo(TTySpeedButton, 'TabStop')^.Default);
  c := third;
  c.AllowAllUp := False;
  AssertFalse('T-v: AllowAllUp is public through a TTyCustomSpeedButton reference', c.AllowAllUp);
end;

{ ------------------------------------------------------------------ Task 3: labels }

procedure TTyCustomClassesP1Test.TestThirdLabel;
var
  third, back: TThirdLabel;
  own: TTyLabel;
  c: TTyCustomLabel;
  bmA, bmB: TBitmap;
  diff: string;
begin
  third := TThirdLabel.Create(FForm);
  third.Parent := FForm;
  third.SetBounds(10, 10, 120, 20);
  CheckPublishesOnly(TThirdLabel, ['Caption', 'WordWrap']);
  third.Caption := 'Hello';
  third.WordWrap := True;
  { Layout is protected on the custom class, as on TCustomLabel: the mimic reaches it only
    through a subclass of its own, and did not publish it. }
  TP1LabelCracker(third).SetLayoutTo(tlBottom);
  CheckStreamText(third, ['Caption', 'WordWrap'], 'Layout');
  back := TThirdLabel.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Caption round-trips', 'Hello', back.Caption);
  AssertTrue('T-c: WordWrap round-trips', back.WordWrap);
  AssertTrue('T-c: the unpublished Layout stayed at its default',
    TP1LabelCracker(back).LayoutNow = tlCenter);
  { T-d: the label is theme-locked and drawn entirely by the custom class, so a mimic with the
    same caption and bounds is the same picture. }
  own := TTyLabel.Create(FForm);
  own.Parent := FForm;
  own.SetBounds(10, 40, 120, 20);
  own.Caption := 'Hello';
  third.WordWrap := False;
  TP1LabelCracker(third).SetLayoutTo(tlCenter);
  CheckSameTypeKey(third, own);
  bmA := NewSentinelBitmap(120, 20);
  bmB := NewSentinelBitmap(120, 20);
  try
    TP1LabelCracker(third).DoRender(bmA.Canvas, Rect(0, 0, 120, 20));
    TP1LabelCracker(own).DoRender(bmB.Canvas, Rect(0, 0, 120, 20));
    AssertTrue('T-d: the mimic paints exactly what TTyLabel paints: ' + diff,
      SameBitmaps(bmA, bmB, diff));
  finally
    bmA.Free;
    bmB.Free;
  end;
  CheckFreshDefaults(TThirdLabel, ['Caption', 'WordWrap']);
  { T-v: Caption is public (TControl); the label's own properties are protected (TCustomLabel),
    which is what the cracker above is for. }
  c := third;
  c.Caption := 'via the custom class';
  AssertEquals('T-v', 'via the custom class', third.Caption);
end;

procedure TTyCustomClassesP1Test.TestThirdTag;
var
  third, back: TThirdTag;
  own: TTyTag;
  c: TTyCustomTag;
begin
  third := TThirdTag.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdTag, ['Caption', 'Closable']);
  third.Caption := 'beta';
  third.Closable := True;
  third.Align := alTop;   // TTyTag publishes Align; the mimic does not
  CheckStreamText(third, ['Caption', 'Closable'], 'Align');
  back := TThirdTag.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Caption round-trips', 'beta', back.Caption);
  AssertTrue('T-c: Closable round-trips', back.Closable);
  own := TTyTag.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdTag, ['Caption', 'Closable']);
  c := third;
  c.Closable := False;
  AssertFalse('T-v: Closable is public through a TTyCustomTag reference', third.Closable);
end;

{ ------------------------------------------------------------------ Task 4: edits I }

procedure TTyCustomClassesP1Test.TestThirdEdit;
var
  third, back: TThirdEdit;
  own: TTyEdit;
  c: TTyCustomEdit;
  ime: ITyImeEditable;
  acts: ITyTextEditActions;
begin
  third := TThirdEdit.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdEdit, ['Text', 'ReadOnly']);
  third.Text := 'abc';
  third.ReadOnly := True;
  third.MaxLength := 5;
  CheckStreamText(third, ['Text', 'ReadOnly'], 'MaxLength');
  back := TThirdEdit.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Text round-trips', 'abc', back.Text);
  AssertTrue('T-c: ReadOnly round-trips', back.ReadOnly);
  AssertEquals('T-c: the unpublished MaxLength stayed at its default', 0, back.MaxLength);
  own := TTyEdit.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdEdit, ['Text', 'ReadOnly']);
  { The edit is a tab stop and says so in its declared default; that redeclaration lives in
    the custom class, so a mimic that publishes TabStop gets the same default. }
  AssertTrue('T-e: the mimic is a tab stop, like TTyEdit', third.TabStop);
  { T-f: the edit interfaces are on the custom class's header, so the mimic has them -- the
    shared right-click menu and the IME bridge both find a third party's edit. }
  AssertTrue('T-f: ITyImeEditable', Supports(third, ITyImeEditable, ime));
  AssertTrue('T-f: ITyTextEditActions', Supports(third, ITyTextEditActions, acts));
  ime := nil;
  acts := nil;
  c := third;
  c.MaxLength := 3;
  AssertEquals('T-v: MaxLength is public through a TTyCustomEdit reference', 3, third.MaxLength);
end;

procedure TTyCustomClassesP1Test.TestThirdMaskEdit;
var
  third, back: TThirdMaskEdit;
  own: TTyMaskEdit;
begin
  third := TThirdMaskEdit.Create(FForm);
  third.Parent := FForm;
  own := TTyMaskEdit.Create(FForm);
  own.Parent := FForm;
  CheckPublishesOnly(TThirdMaskEdit, ['Mask', 'Text']);
  { Text's masked setter is the redeclaration `property Text write SetMaskedText`; it sits in
    the custom class, so assigning through the mimic is filtered exactly like TTyMaskEdit. }
  third.Mask := '00/00/0000';
  own.Mask := '00/00/0000';
  third.Text := '12345678';
  own.Text := '12345678';
  AssertEquals('the mimic''s Text goes through the masked setter', own.Text, third.Text);
  AssertEquals('which lays the digits into the mask', '12/34/5678', third.Text);
  TP1MaskCracker(third).SetSpace('*');
  CheckStreamText(third, ['Mask', 'Text'], 'SpaceChar');
  back := TThirdMaskEdit.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Mask round-trips', '00/00/0000', back.Mask);
  AssertEquals('T-c: Text round-trips', '12/34/5678', back.Text);
  AssertEquals('T-c: the unpublished SpaceChar stayed at its default', TyMaskDefaultBlank,
    TP1MaskCracker(back).SpaceNow);
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdMaskEdit, ['Mask', 'Text']);
end;

{ ------------------------------------------------------------------ Task 5: edits II }

procedure TTyCustomClassesP1Test.TestThirdMemo;
var
  third, back: TThirdMemo;
  own: TTyMemo;
  c: TTyCustomMemo;
begin
  third := TThirdMemo.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdMemo, ['Lines', 'ReadOnly']);
  third.Lines.Text := 'one' + LineEnding + 'two';
  third.ReadOnly := True;
  third.WantTabs := True;
  CheckStreamText(third, ['Lines', 'ReadOnly'], 'WantTabs');
  back := TThirdMemo.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Lines round-trip', 2, back.Lines.Count);
  AssertEquals('T-c: line two', 'two', back.Lines[1]);
  AssertTrue('T-c: ReadOnly round-trips', back.ReadOnly);
  AssertFalse('T-c: the unpublished WantTabs stayed at its default', back.WantTabs);
  own := TTyMemo.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdMemo, ['Lines', 'ReadOnly']);
  c := third;
  c.WantTabs := False;
  AssertFalse('T-v: WantTabs is public through a TTyCustomMemo reference', third.WantTabs);
end;

{ Associate is a component reference and so is not part of the stream check here (a lone
  up-down streamed as its own root has no owner to resolve it against); S4-2 below drives it. }
procedure TTyCustomClassesP1Test.TestThirdUpDown;
var
  third, back: TThirdUpDown;
  own: TTyUpDown;
begin
  third := TThirdUpDown.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdUpDown, ['Associate', 'Position']);
  third.Position := 40;
  TP1UpDownCracker(third).SetIncrementTo(5);
  CheckStreamText(third, ['Position'], 'Increment');
  back := TThirdUpDown.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Position round-trips', 40, back.Position);
  AssertEquals('T-c: the unpublished Increment stayed at its default', 1,
    TP1UpDownCracker(back).IncrementNow);
  own := TTyUpDown.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdUpDown, ['Associate', 'Position']);
  { T-v: everything the up-down adds is protected (TCustomUpDown), hence the cracker. }
end;

{ S4-2. One field, one stepper: a second up-down that tries to drive a field a sibling already
  drives is refused -- and a third party's up-down is a sibling like any other. }
procedure TTyCustomClassesP1Test.TestUpDownAssociationIsExclusiveAcrossThirdParties;
var
  ed: TTyEdit;
  own: TTyUpDown;
  third: TThirdUpDown;
  raised: Boolean;
begin
  ed := TTyEdit.Create(FForm);
  ed.Name := 'Field';
  ed.Parent := FForm;
  own := TTyUpDown.Create(FForm);
  own.Name := 'OwnUpDown';
  own.Parent := FForm;
  third := TThirdUpDown.Create(FForm);
  third.Name := 'ThirdUpDown';
  third.Parent := FForm;
  own.Associate := ed;
  raised := False;
  try
    third.Associate := ed;
  except
    raised := True;
  end;
  AssertTrue('a third-party up-down cannot take a field the library''s already drives', raised);
  own.Associate := nil;
  third.Associate := ed;
  raised := False;
  try
    own.Associate := ed;
  except
    raised := True;
  end;
  AssertTrue('and the library''s cannot take one the third party drives', raised);
end;

{ TTyFloatSpinEdit groups no thousands by default although the numeric edit it descends from
  does. The `default False` redeclaration lives on TTyCustomFloatSpinEdit, so the published
  class reads it -- and so does any descendant of the custom class. }
procedure TTyCustomClassesP1Test.TestFloatSpinEditKeepsItsUseThousandsDefault;
var
  e: TTyFloatSpinEdit;
begin
  AssertEquals('precondition: the numeric edit declares True', 1,
    GetPropInfo(TTyNumericEdit, 'UseThousands')^.Default);
  AssertEquals('the float spin edit declares False', 0,
    GetPropInfo(TTyFloatSpinEdit, 'UseThousands')^.Default);
  e := TTyFloatSpinEdit.Create(FForm);
  AssertFalse('and its constructor agrees', e.UseThousands);
end;

{ ------------------------------------------------------------------ Task 6: choice }

procedure TTyCustomClassesP1Test.TestThirdCheckBox;
var
  third, back: TThirdCheckBox;
  own: TTyCheckBox;
  c: TTyCustomCheckBox;
begin
  third := TThirdCheckBox.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdCheckBox, ['Checked', 'Caption']);
  third.Checked := True;
  third.Caption := 'Agree';
  third.AllowGrayed := True;
  CheckStreamText(third, ['Checked', 'Caption'], 'AllowGrayed');
  back := TThirdCheckBox.Create(FForm);
  StreamInto(third, back);
  AssertTrue('T-c: Checked round-trips', back.Checked);
  AssertEquals('T-c: Caption round-trips', 'Agree', back.Caption);
  AssertFalse('T-c: the unpublished AllowGrayed stayed at its default', back.AllowGrayed);
  own := TTyCheckBox.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdCheckBox, ['Checked', 'Caption']);
  AssertTrue('T-e: the mimic is a tab stop, like TTyCheckBox', third.TabStop);
  { T-v: AllowGrayed is public (TCustomCheckBox); Checked is protected there, as in LCL, which
    is why the mimic publishes it. }
  c := third;
  c.AllowGrayed := False;
  AssertFalse('T-v: AllowGrayed is public through a TTyCustomCheckBox reference', third.AllowGrayed);
end;

procedure TTyCustomClassesP1Test.TestThirdRadioButton;
var
  third, back: TThirdRadioButton;
  own: TTyRadioButton;
  c: TTyCustomRadioButton;
begin
  third := TThirdRadioButton.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdRadioButton, ['Checked', 'GroupIndex']);
  third.GroupIndex := 3;
  third.Checked := True;
  third.Alignment := taLeftJustify;   // public, not published by the mimic
  CheckStreamText(third, ['Checked', 'GroupIndex'], 'Alignment');
  back := TThirdRadioButton.Create(FForm);
  StreamInto(third, back);
  AssertTrue('T-c: Checked round-trips', back.Checked);
  AssertEquals('T-c: GroupIndex round-trips', 3, back.GroupIndex);
  own := TTyRadioButton.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdRadioButton, ['Checked', 'GroupIndex']);
  c := third;
  c.GroupIndex := 4;
  AssertEquals('T-v: GroupIndex is public through a TTyCustomRadioButton reference', 4,
    third.GroupIndex);
end;

{ S5-1. Same parent, same GroupIndex: checking one radio unchecks the other, whichever of the
  two is the third party's. }
procedure TTyCustomClassesP1Test.TestRadioGroupTakesAThirdPartyMember;
var
  own: TTyRadioButton;
  third: TThirdRadioButton;
begin
  own := TTyRadioButton.Create(FForm);
  own.Parent := FForm;
  own.GroupIndex := 1;
  third := TThirdRadioButton.Create(FForm);
  third.Parent := FForm;
  third.GroupIndex := 1;
  own.Checked := True;
  third.Checked := True;
  AssertFalse('checking the third-party radio unchecks the library''s', own.Checked);
  own.Checked := True;
  AssertFalse('and the other way round', third.Checked);
end;

{ ------------------------------------------------------------------ Task 7: combo boxes I }

{ S7-1. A combo's drop-down list finds its combo through Owner to hand rows to the host's
  OnDrawItem. Every derived combo -- TTyComboBoxEx here -- is a TTyCustomComboBox and, since 4.0,
  not a TTyComboBox; the lookup that asked for TTyComboBox left every one of their lists painting
  their own rows behind the host's back. }
procedure TTyCustomClassesP1Test.TestDerivedComboPopupReachesTheOwnerDraw;
var
  c: TTyComboBoxEx;
  l: TTyListBox;
  bmp: TBitmap;
begin
  c := TTyComboBoxEx.Create(FForm);
  c.Items.Add('Alpha');
  c.Items.Add('Beta');
  c.OnDrawItem := @CountDraw;
  c.Style := csOwnerDrawFixed;
  l := TP1ComboCracker(c).MakePopupList;
  AssertTrue('the Ex combo drops a TTyComboPopupList (or this proves nothing)',
    l is TTyComboPopupList);
  l.Parent := FForm;
  l.Font.PixelsPerInch := 96;
  l.ItemHeight := 24;
  l.SetBounds(0, 0, 160, 80);
  l.Items.Assign(c.Items);
  l.TopIndex := 0;
  bmp := NewSentinelBitmap(160, 80);
  try
    FDrawCalls := 0;
    TTyComboPopupList(l).RenderWithOwnerDraw(bmp.Canvas, Rect(0, 0, 160, 80), 96);
    AssertEquals('the host''s OnDrawItem ran once per row of the derived combo''s list', 2,
      FDrawCalls);
  finally
    bmp.Free;
  end;
end;

{ S7-2. ItemsEx is the item source: the collection tells its combo when it changes, and the
  combo rebuilds Items. The collection finds that combo through its owner, which for a third
  party's TTyCustomComboBoxEx descendant is not a TTyComboBoxEx. }
procedure TTyCustomClassesP1Test.TestThirdComboBoxExItemsDriveTheList;
var
  third: TThirdComboBoxEx;
begin
  third := TThirdComboBoxEx.Create(FForm);
  CheckPublishesOnly(TThirdComboBoxEx, ['ItemsEx', 'Images']);
  third.ItemsEx.AddItem('Save', 3);
  third.ItemsEx.AddItem('Open', 4);
  AssertEquals('the collection reached the painted list', 2, third.Items.Count);
  third.ItemsEx[0].Caption := 'Store';
  AssertEquals('so does a caption edit', 'Store', third.Items[0]);
  { Images only: TWriter writes a collection property whenever there is no ancestor to compare
    with, empty or not (writer.inc), so ItemsEx = <> is in every fresh stream. }
  CheckFreshDefaults(TThirdComboBoxEx, ['Images']);
end;

procedure TTyCustomClassesP1Test.TestThirdComboBox;
var
  third, back: TThirdComboBox;
  own: TTyComboBox;
  c: TTyCustomComboBox;
begin
  third := TThirdComboBox.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdComboBox, ['Items', 'ItemIndex']);
  third.Items.Add('one');
  third.Items.Add('two');
  third.ItemIndex := 1;
  third.DropDownCount := 3;
  CheckStreamText(third, ['Items', 'ItemIndex'], 'DropDownCount');
  back := TThirdComboBox.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Items round-trip', 2, back.Items.Count);
  AssertEquals('T-c: ItemIndex round-trips', 1, back.ItemIndex);
  AssertEquals('T-c: the unpublished DropDownCount stayed at its default', 8, back.DropDownCount);
  own := TTyComboBox.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  { Items only: ItemIndex has no declared default on TTyComboBox either, so a fresh combo
    writes ItemIndex = -1 (the 3.0 snapshot records the same). }
  CheckFreshDefaults(TThirdComboBox, ['Items']);
  AssertTrue('T-e: the mimic is a tab stop, like TTyComboBox', third.TabStop);
  c := third;
  c.DropDownCount := 5;
  AssertEquals('T-v: DropDownCount is public through a TTyCustomComboBox reference', 5,
    third.DropDownCount);
end;

{ ------------------------------------------------------------------ Task 8: combo boxes II }

{ The combo's own drop-down list, built and rendered off-screen. }
function RenderColorComboList(AForm: TForm; ACombo: TTyCustomComboBox): TBitmap;
var
  l: TTyListBox;
begin
  l := TP1ComboCracker(ACombo).MakePopupList;
  l.Parent := AForm;
  l.Font.PixelsPerInch := 96;
  l.ItemHeight := 24;
  l.SetBounds(0, 0, 160, 80);
  l.Items.Assign(ACombo.Items);
  l.TopIndex := 0;
  Result := NewSentinelBitmap(160, 80);
  TTyComboPopupList(l).RenderWithOwnerDraw(Result.Canvas, Rect(0, 0, 160, 80), 96);
  l.Free;
end;

{ S8-1. The colour list's rows take the swatch geometry and pseudo-row colours from the box
  that owns them, which they find through Owner. A third party's colour box is a
  TTyCustomColorBox and not a TTyColorBox; a lookup that asked for TTyColorBox left its
  drop-down ignoring ColorRectWidth. (The library's own TTyColorComboBox drops a list of its
  own that never consulted the owner's geometry, in 3.0 as now -- so it is not the witness.) }
procedure TTyCustomClassesP1Test.TestColorBoxPopupUsesItsOwnSwatchGeometry;
var
  narrow, wide: TThirdColorBox;
  a, b: TBitmap;
  diff: string;
begin
  narrow := TThirdColorBox.Create(FForm);
  narrow.ColorRectWidth := 8;
  wide := TThirdColorBox.Create(FForm);
  wide.ColorRectWidth := 40;
  AssertFalse('the mimic is not a TTyColorBox (or this proves nothing)',
    TObject(narrow) is TTyColorBox);
  a := RenderColorComboList(FForm, narrow);
  b := RenderColorComboList(FForm, wide);
  try
    AssertFalse('the drop-down rows follow the box''s own ColorRectWidth',
      SameBitmaps(a, b, diff));
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TTyCustomClassesP1Test.TestThirdColorBox;
var
  third, back: TThirdColorBox;
  own: TTyColorBox;
  c: TTyCustomColorBox;
begin
  third := TThirdColorBox.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdColorBox, ['Selected', 'Style']);
  third.Style := [cbStandardColors];
  third.Selected := clRed;
  third.ColorRectWidth := 30;
  CheckStreamText(third, ['Selected', 'Style'], 'ColorRectWidth');
  back := TThirdColorBox.Create(FForm);
  StreamInto(third, back);
  AssertTrue('T-c: Style round-trips', back.Style = [cbStandardColors]);
  AssertEquals('T-c: Selected round-trips', clRed, back.Selected);
  AssertEquals('T-c: the unpublished ColorRectWidth stayed at its default', 0, back.ColorRectWidth);
  own := TTyColorBox.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  { Style only: Selected has no default on TTyColorBox either (a fresh box streams it). }
  CheckFreshDefaults(TThirdColorBox, ['Style']);
  { T-v: the colour box's own properties are public (TCustomColorBox), and Style through the
    custom class is the PALETTE set -- the redeclaration lives there, not on TTyColorBox. }
  c := third;
  c.ColorRectWidth := 12;
  AssertEquals('T-v: ColorRectWidth is public through a TTyCustomColorBox reference', 12,
    third.ColorRectWidth);
  AssertTrue('T-v: and Style on the custom class is the palette', c.Style = [cbStandardColors]);
end;

procedure TTyCustomClassesP1Test.TestThirdShellComboBox;
var
  third: TThirdShellComboBox;
  own: TTyShellComboBox;
  dir, diff: string;
  a, b: TBitmap;
begin
  third := TThirdShellComboBox.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdShellComboBox, ['Directory', 'Items']);
  dir := ExcludeTrailingPathDelimiter(GetTempDir);
  third.Directory := dir;
  CheckStreamText(third, ['Directory'], '');
  own := TTyShellComboBox.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  { S8-2. The drop-down draws each folder with its glyph and indent, asking its owner for them;
    a third party's shell combo is a TTyCustomShellComboBox, so its rows look the same. }
  own.Directory := dir;
  AssertTrue('the folder chain has rows (or this proves nothing)', own.Items.Count > 0);
  a := RenderColorComboList(FForm, third);
  b := RenderColorComboList(FForm, own);
  try
    AssertTrue('the mimic''s drop-down rows are the library''s: ' + diff, SameBitmaps(a, b, diff));
  finally
    a.Free;
    b.Free;
  end;
  CheckFreshDefaults(TThirdShellComboBox, ['Directory']);
end;

{ ------------------------------------------------------------------ Task 9: progress }

procedure TTyCustomClassesP1Test.TestThirdProgressBar;
var
  third, back: TThirdProgressBar;
  own: TTyProgressBar;
  c: TTyCustomProgressBar;
  txt: string;
begin
  third := TThirdProgressBar.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdProgressBar, ['Max', 'Position']);
  third.Max := 50;
  third.Position := 40;
  third.Step := 5;
  CheckStreamText(third, ['Max', 'Position'], 'Step');
  txt := StreamedText(third);
  AssertTrue('T-c: Max is written before Position, the order the mimic published them in',
    Pos(' Max = ', txt) < Pos(' Position = ', txt));
  back := TThirdProgressBar.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Max round-trips', 50, back.Max);
  AssertEquals('T-c: Position round-trips (not clamped by a default Max)', 40, back.Position);
  AssertEquals('T-c: the unpublished Step stayed at its default', 10, back.Step);
  own := TTyProgressBar.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdProgressBar, ['Max', 'Position']);
  c := third;
  c.Step := 2;
  AssertEquals('T-v: Step is public through a TTyCustomProgressBar reference', 2, third.Step);
end;

procedure TTyCustomClassesP1Test.TestThirdGauge;
var
  third, back: TThirdGauge;
  own: TTyGauge;
begin
  third := TThirdGauge.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdGauge, ['Max', 'Value']);
  third.Max := 200;
  third.Value := 150;
  third.Thickness := 20;
  CheckStreamText(third, ['Max', 'Value'], 'Thickness');
  back := TThirdGauge.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Max round-trips', 200, back.Max, 1e-9);
  AssertEquals('T-c: Value round-trips', 150, back.Value, 1e-9);
  own := TTyGauge.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  { Value only: Max is a Double with no default on TTyGauge too, so a fresh gauge writes it. }
  CheckFreshDefaults(TThirdGauge, ['Value']);
end;

{ ------------------------------------------------------------------ Task 10: dials and sliders }

procedure TTyCustomClassesP1Test.TestThirdTrackBar;
var
  third, back: TThirdTrackBar;
  own: TTyTrackBar;
  c: TTyCustomTrackBar;
begin
  third := TThirdTrackBar.Create(FForm);
  third.Parent := FForm;
  CheckPublishesOnly(TThirdTrackBar, ['Position', 'Max']);
  third.Max := 20;
  third.Position := 7;
  third.TickMarks := ttmBoth;
  CheckStreamText(third, ['Position', 'Max'], 'TickMarks');
  back := TThirdTrackBar.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: Max round-trips', 20, back.Max);
  AssertEquals('T-c: Position round-trips', 7, back.Position);
  own := TTyTrackBar.Create(FForm);
  own.Parent := FForm;
  CheckSameTypeKey(third, own);
  CheckFreshDefaults(TThirdTrackBar, ['Position', 'Max']);
  { T-e, TabStop: a track bar is a tab stop out of the constructor, and the declaration that
    says so must travel with the custom class -- a descendant that publishes TabStop has to
    read default True, or a .lfm that switches it off loses the setting. }
  AssertTrue('T-e: the mimic is a tab stop', third.TabStop);
  AssertEquals('precondition: on the bare base TabStop declares LCL''s default False', 0,
    GetPropInfo(TP1BareTabStop, 'TabStop')^.Default);
  AssertEquals('T-e: a descendant of the custom track bar publishing TabStop reads default True',
    1, GetPropInfo(TP1TrackBarTabStop, 'TabStop')^.Default);
  c := third;
  c.TickMarks := ttmTopLeft;
  AssertTrue('T-v: TickMarks is public through a TTyCustomTrackBar reference (Q6: public, not '
    + 'LCL''s published)', third.TickMarks = ttmTopLeft);
end;

initialization
  RegisterClasses([TThirdButton, TThirdSpeedButton, TThirdLabel, TThirdTag, TThirdEdit,
    TThirdMaskEdit, TThirdMemo, TThirdUpDown, TThirdCheckBox, TThirdRadioButton,
    TThirdComboBox, TThirdComboBoxEx, TThirdColorBox, TThirdShellComboBox, TThirdProgressBar,
    TThirdGauge, TThirdTrackBar]);
  RegisterTest(TTyCustomClassesP1Test);
end.
