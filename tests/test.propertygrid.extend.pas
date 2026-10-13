unit test.propertygrid.extend;
{$mode objfpc}{$H+}

{ The property grid (#65), phase 2, plan D6 (a): what the grid does not show by itself, the
  application can. OnFilterProperty is asked about every published property -- an interface, a
  variant, a class that is not a TPersistent arrive with AShow False -- and such a property is
  listed once the handler shows it and OnGetPropertyText gives it a text; OnSetPropertyText makes
  it editable. For the types the grid does know, the two events take over the conversion.

  Edits go in the way the user makes them and the verdicts are read off the inspected objects. }

interface

uses
  Classes, SysUtils, Variants, TypInfo, LCLType, Controls, Graphics, Forms, fpcunit, testregistry,
  tyControls.ValueListEditor, tyControls.PropertyGrid, test.propertygrid.fixtures;

type
  TPropertyGridTextEventsTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: TPGGrid;
    FObj: TPGExotic;
    FObj2: TPGExotic;
    FBasic: TPGBasic;
    FAskedShow: TStringList;     // 'Name=AShow as it arrived'
    FShowExotic: Boolean;
    FHandleText: Boolean;
    FGetCalls, FSetCalls: TList;
    procedure Filter(Sender: TObject; AInstance: TPersistent; const APropName: string;
      var AShow: Boolean);
    procedure GetText(Sender: TObject; AInstance: TPersistent; APropInfo: PPropInfo;
      var AText: string; var AHandled: Boolean);
    procedure SetText(Sender: TObject; AInstance: TPersistent; APropInfo: PPropInfo;
      const AText: string; var AHandled: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheFilterIsAskedAboutEveryPropertyAndTheUnknownStayHidden;
    procedure TestShownButWithoutATextItStaysHidden;
    procedure TestAnInterfaceIsShownThroughTheEventsReadOnly;
    procedure TestAVariantIsWrittenThroughOnSetPropertyText;
    procedure TestAHandledTextOverridesABuiltInType;
    procedure TestWithSeveralObjectsTheEventsComeForEach;
  end;

implementation

procedure TPropertyGridTextEventsTest.SetUp;
begin
  FForm := NewHostForm;
  FGrid := TPGGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 440, 720);
  FObj := TPGExotic.Create('probe');
  FObj2 := TPGExotic.Create('other');
  FBasic := TPGBasic.Create;
  FAskedShow := TStringList.Create;
  FGetCalls := TList.Create;
  FSetCalls := TList.Create;
  FShowExotic := False;
  FHandleText := True;
  FForm.Show;
end;

procedure TPropertyGridTextEventsTest.TearDown;
begin
  FForm.Free;
  FObj.Free;
  FObj2.Free;
  FBasic.Free;
  FAskedShow.Free;
  FGetCalls.Free;
  FSetCalls.Free;
end;

procedure TPropertyGridTextEventsTest.Filter(Sender: TObject; AInstance: TPersistent;
  const APropName: string; var AShow: Boolean);
begin
  FAskedShow.Values[APropName] := BoolToStr(AShow, True);
  if FShowExotic and ((APropName = 'Intf') or (APropName = 'Amount') or (APropName = 'Raw')) then
    AShow := True;
end;

procedure TPropertyGridTextEventsTest.GetText(Sender: TObject; AInstance: TPersistent;
  APropInfo: PPropInfo; var AText: string; var AHandled: Boolean);
begin
  if not FHandleText then Exit;
  if AInstance is TPGExotic then
  begin
    if APropInfo^.Name = 'Intf' then
    begin
      FGetCalls.Add(AInstance);
      AText := TPGExotic(AInstance).Named.Name;
      AHandled := True;
    end
    else if APropInfo^.Name = 'Amount' then
    begin
      AText := VarToStr(TPGExotic(AInstance).Amount);
      AHandled := True;
    end;
    { Raw: left unhandled on purpose }
  end
  else if (AInstance is TPGBasic) and (APropInfo^.Name = 'Tint') then
  begin
    AText := '#' + IntToHex(ColorToRGB(TPGBasic(AInstance).Tint), 6);
    AHandled := True;
  end;
end;

procedure TPropertyGridTextEventsTest.SetText(Sender: TObject; AInstance: TPersistent;
  APropInfo: PPropInfo; const AText: string; var AHandled: Boolean);
begin
  FSetCalls.Add(AInstance);
  if (AInstance is TPGExotic) and (APropInfo^.Name = 'Amount') then
  begin
    TPGExotic(AInstance).Amount := StrToInt(Trim(AText));
    AHandled := True;
  end
  else if (AInstance is TPGBasic) and (APropInfo^.Name = 'Tint') then
  begin
    TPGBasic(AInstance).Tint := TColor(StrToInt('$' + Copy(AText, 2, MaxInt)));
    AHandled := True;
  end;
end;

procedure TPropertyGridTextEventsTest.TestTheFilterIsAskedAboutEveryPropertyAndTheUnknownStayHidden;
begin
  FGrid.OnFilterProperty := @Filter;
  FGrid.SelectedObject := FObj;
  AssertEquals('an interface arrives hidden', 'False', FAskedShow.Values['Intf']);
  AssertEquals('a variant too', 'False', FAskedShow.Values['Amount']);
  AssertEquals('a class that is no TPersistent too', 'False', FAskedShow.Values['Raw']);
  AssertEquals('an Integer arrives shown', 'True', FAskedShow.Values['Level']);
  AssertEquals('nobody turned them on: Level alone', 'Level', FGrid.RootKeys);
end;

procedure TPropertyGridTextEventsTest.TestShownButWithoutATextItStaysHidden;
begin
  FShowExotic := True;
  FGrid.OnFilterProperty := @Filter;
  FGrid.SelectedObject := FObj;
  AssertEquals('shown by the filter, but nothing gives them a text', 'Level', FGrid.RootKeys);
  FGrid.OnGetPropertyText := @GetText;
  FHandleText := False;
  FGrid.Rebuild;
  AssertEquals('a text handler that handles nothing: still hidden', 'Level', FGrid.RootKeys);
  FHandleText := True;
  FGrid.Rebuild;
  AssertEquals('handled: Amount and Intf; Raw is left unhandled', 'Amount,Intf,Level', FGrid.RootKeys);
end;

procedure TPropertyGridTextEventsTest.TestAnInterfaceIsShownThroughTheEventsReadOnly;
begin
  FShowExotic := True;
  FGrid.OnFilterProperty := @Filter;
  FGrid.OnGetPropertyText := @GetText;
  FGrid.SelectedObject := FObj;
  AssertEquals('the handler''s text', 'probe', FGrid.RowAt('Intf').Value);
  AssertTrue('no OnSetPropertyText: read-only', FGrid.RowAt('Intf').ReadOnly);
  FGrid.ClickValue(FGrid.RowAt('Intf'));
  AssertEquals('a click opens nothing', -1, FGrid.EditingRow);
  FObj.Named.Name := 'renamed';
  FGrid.Refresh;
  AssertEquals('and Refresh asks again', 'renamed', FGrid.RowAt('Intf').Value);
end;

procedure TPropertyGridTextEventsTest.TestAVariantIsWrittenThroughOnSetPropertyText;
begin
  FShowExotic := True;
  FGrid.OnFilterProperty := @Filter;
  FGrid.OnGetPropertyText := @GetText;
  FGrid.OnSetPropertyText := @SetText;
  FGrid.SelectedObject := FObj;
  AssertEquals('the handler''s text', '12', FGrid.RowAt('Amount').Value);
  AssertFalse('OnSetPropertyText assigned: editable', FGrid.RowAt('Amount').ReadOnly);
  FGrid.TypeInto(FGrid.RowAt('Amount'), '34');
  AssertEquals('through the setter', 1, FObj.AmountSets);
  AssertEquals('the variant holds it', 34, Integer(FObj.Amount));
  AssertEquals('and read back', '34', FGrid.RowAt('Amount').Value);
end;

procedure TPropertyGridTextEventsTest.TestAHandledTextOverridesABuiltInType;
begin
  FGrid.OnGetPropertyText := @GetText;
  FGrid.OnSetPropertyText := @SetText;
  FGrid.SelectedObject := FBasic;
  AssertEquals('Tint in the handler''s spelling, not clRed', '#0000FF', FGrid.RowAt('Tint').Value);
  AssertEquals('an unhandled property keeps the grid''s', 'pgkTwo', FGrid.RowAt('Kind').Value);
  FGrid.SetRowValue(FGrid.RowAt('Tint'), '#00FF00');   // the grid's own parser would refuse it
  AssertEquals('the handler wrote it', $00FF00, FBasic.Tint);
  AssertEquals('row', '#00FF00', FGrid.RowAt('Tint').Value);
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '5');
  AssertEquals('unhandled writes still reach the grid''s own conversion', 5, FBasic.Zeta);
end;

procedure TPropertyGridTextEventsTest.TestWithSeveralObjectsTheEventsComeForEach;
begin
  FShowExotic := True;
  FGrid.OnFilterProperty := @Filter;
  FGrid.OnGetPropertyText := @GetText;
  FGrid.OnSetPropertyText := @SetText;
  FGrid.SelectObjects([FObj, FObj2]);
  AssertEquals('probe and other: no text for both', '', FGrid.RowAt('Intf').Value);
  AssertTrue('the text was asked of the second object too', FGetCalls.IndexOf(FObj2) >= 0);
  FSetCalls.Clear;
  FGrid.TypeInto(FGrid.RowAt('Amount'), '89');
  AssertEquals('written through the event once per object', 2, FSetCalls.Count);
  AssertSame('first', FObj, TObject(FSetCalls[0]));
  AssertSame('second', FObj2, TObject(FSetCalls[1]));
  AssertEquals('the first holds it', 89, Integer(FObj.Amount));
  AssertEquals('the second too', 89, Integer(FObj2.Amount));
  AssertEquals('row', '89', FGrid.RowAt('Amount').Value);
end;

initialization
  RegisterTest(TPropertyGridTextEventsTest);
end.
