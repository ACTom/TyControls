unit test.edit.word;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, LCLType,
  LazUTF8,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Edit;
type
  // Access subclass exposing the private word-boundary helpers publicly.
  TTyEditWordAccess = class(TTyEdit)
  public
    function NextWordBoundary(AIdx: Integer): Integer;
    function PrevWordBoundary(AIdx: Integer): Integer;
  end;

  TEditWordTest = class(TTestCase)
  private
    FForm: TCustomForm;
    FEdit: TTyEditWordAccess;
    procedure SetText(const S: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFooBarNext;
    procedure TestFooBarPrev;
    procedure TestFooDotBar;
    procedure TestAPlusB;
    procedure TestLeadingSpaces;
    procedure TestLeadingDashes;
    procedure TestTrailingSpaces;
    procedure TestAllPunct;
    procedure TestEmpty;
    procedure TestAccented;
    procedure TestCJK;
    procedure TestOutOfRangeClamp;
  end;
implementation

function TTyEditWordAccess.NextWordBoundary(AIdx: Integer): Integer;
begin
  Result := inherited NextWordBoundary(AIdx);
end;

function TTyEditWordAccess.PrevWordBoundary(AIdx: Integer): Integer;
begin
  Result := inherited PrevWordBoundary(AIdx);
end;

procedure TEditWordTest.SetText(const S: string);
begin
  FEdit.Text := S;
end;

procedure TEditWordTest.SetUp;
begin
  FForm := TCustomForm.CreateNew(nil);
  FEdit := TTyEditWordAccess.Create(FForm);
  FEdit.Parent := FForm;
end;

procedure TEditWordTest.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FEdit := nil;
end;

// 'foo bar': Next(0)=4, Next(3)=4, Next(4)=7, Next(7)=7(end).
procedure TEditWordTest.TestFooBarNext;
begin
  SetText('foo bar');
  AssertEquals('Next(0)', 4, FEdit.NextWordBoundary(0));
  AssertEquals('Next(3)', 4, FEdit.NextWordBoundary(3));
  AssertEquals('Next(4)', 7, FEdit.NextWordBoundary(4));
  AssertEquals('Next(7) end', 7, FEdit.NextWordBoundary(7));
end;

// Prev(7)=4, Prev(4)=0, Prev(3)=0, Prev(0)=0.
procedure TEditWordTest.TestFooBarPrev;
begin
  SetText('foo bar');
  AssertEquals('Prev(7)', 4, FEdit.PrevWordBoundary(7));
  AssertEquals('Prev(4)', 0, FEdit.PrevWordBoundary(4));
  AssertEquals('Prev(3)', 0, FEdit.PrevWordBoundary(3));
  AssertEquals('Prev(0)', 0, FEdit.PrevWordBoundary(0));
end;

// 'foo.bar' (dot is punct): Next(0)=4, Next(4)=7. Prev(7)=4, Prev(4)=0.
procedure TEditWordTest.TestFooDotBar;
begin
  SetText('foo.bar');
  AssertEquals('Next(0)', 4, FEdit.NextWordBoundary(0));
  AssertEquals('Next(4)', 7, FEdit.NextWordBoundary(4));
  AssertEquals('Prev(7)', 4, FEdit.PrevWordBoundary(7));
  AssertEquals('Prev(4)', 0, FEdit.PrevWordBoundary(4));
end;

// 'a+b': Next(0)=2, Prev(3)=2, Prev(2)=0.
procedure TEditWordTest.TestAPlusB;
begin
  SetText('a+b');
  AssertEquals('Next(0)', 2, FEdit.NextWordBoundary(0));
  AssertEquals('Prev(3)', 2, FEdit.PrevWordBoundary(3));
  AssertEquals('Prev(2)', 0, FEdit.PrevWordBoundary(2));
end;

// '  foo': Next(0)=2 (lands on 'f').
procedure TEditWordTest.TestLeadingSpaces;
begin
  SetText('  foo');
  AssertEquals('Next(0) lands on f', 2, FEdit.NextWordBoundary(0));
end;

// '--foo': Next(0)=2 (word-run loop skips nothing at 0, punct-run skips '--').
// DOCUMENT/assert 2 not 5.
procedure TEditWordTest.TestLeadingDashes;
begin
  SetText('--foo');
  AssertEquals('Next(0) is 2 not 5', 2, FEdit.NextWordBoundary(0));
end;

// 'foo   ' (trailing spaces): Next(0)=6 (end), Next(3)=6. Prev(6)=0.
procedure TEditWordTest.TestTrailingSpaces;
begin
  SetText('foo   ');
  AssertEquals('Next(0)', 6, FEdit.NextWordBoundary(0));
  AssertEquals('Next(3)', 6, FEdit.NextWordBoundary(3));
  AssertEquals('Prev(6)', 0, FEdit.PrevWordBoundary(6));
end;

// '....' (all punct): Next(0)=4, Prev(4)=0.
procedure TEditWordTest.TestAllPunct;
begin
  SetText('....');
  AssertEquals('Next(0)', 4, FEdit.NextWordBoundary(0));
  AssertEquals('Prev(4)', 0, FEdit.PrevWordBoundary(4));
end;

// '' (empty): Next(0)=0, Prev(0)=0.
procedure TEditWordTest.TestEmpty;
begin
  SetText('');
  AssertEquals('Next(0)', 0, FEdit.NextWordBoundary(0));
  AssertEquals('Prev(0)', 0, FEdit.PrevWordBoundary(0));
end;

// 'café bàr' — multibyte; indices are codepoint counts.
// 'café'=4 codepoints, then space at 4, 'bàr'=3 codepoints -> total 8.
// Next(0): skip word 'café' (4) then skip space -> 5.
// Next(5): skip word 'bàr' (to 8) -> 8 (end).
// Prev(8)=5, Prev(5)=0, Prev(4)=0.
procedure TEditWordTest.TestAccented;
begin
  SetText('café bàr');
  AssertEquals('codepoint length', 8, UTF8Length(FEdit.Text));
  AssertEquals('Next(0)', 5, FEdit.NextWordBoundary(0));
  AssertEquals('Next(5)', 8, FEdit.NextWordBoundary(5));
  AssertEquals('Prev(8)', 5, FEdit.PrevWordBoundary(8));
  AssertEquals('Prev(5)', 0, FEdit.PrevWordBoundary(5));
  AssertEquals('Prev(4)', 0, FEdit.PrevWordBoundary(4));
end;

// '你好 世界': each CJK char = 1 codepoint. '你好'=2, space at 2, '世界'=2 -> total 5.
// Next(0)=3 (skip word '你好' (2), skip space -> 3, lands on '世').
// Prev(5)=3, Prev(3)=0.
procedure TEditWordTest.TestCJK;
begin
  SetText('你好 世界');
  AssertEquals('codepoint length', 5, UTF8Length(FEdit.Text));
  AssertEquals('Next(0) lands on 世', 3, FEdit.NextWordBoundary(0));
  AssertEquals('Prev(5)', 3, FEdit.PrevWordBoundary(5));
  AssertEquals('Prev(3)', 0, FEdit.PrevWordBoundary(3));
end;

// Out-of-range clamp on 'foo bar' (Len=7):
// Next(-5) behaves as Next(0)=4; Next(999)=Len=7; Prev(-1)=0; Prev(999)=PrevWordBoundary(Len)=Prev(7)=4.
procedure TEditWordTest.TestOutOfRangeClamp;
begin
  SetText('foo bar');
  AssertEquals('Next(-5) == Next(0)', 4, FEdit.NextWordBoundary(-5));
  AssertEquals('Next(999) == Len', 7, FEdit.NextWordBoundary(999));
  AssertEquals('Prev(-1) == 0', 0, FEdit.PrevWordBoundary(-1));
  AssertEquals('Prev(999) == Prev(Len)', 4, FEdit.PrevWordBoundary(999));
end;

initialization
  RegisterTest(TEditWordTest);
end.
