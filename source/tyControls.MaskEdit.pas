unit tyControls.MaskEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, LCLType, LazUTF8,
  tyControls.Edit;

{ Mask slot codes: '#' = digit (0-9), 'L' = letter (A-Za-z), 'C' = any non-space;
  every other char is a fixed LITERAL, auto-inserted between slots. }
function TyMaskSlotAccepts(ASlot, ACh: Char): Boolean;
{ Lay the significant chars of ARaw into AMask, inserting literals between them.
  Deferred: a literal is only emitted once the slot AFTER it is filled, so a partial
  string never shows a dangling trailing separator ("12" not "12/"). }
function TyMaskApply(const AMask, ARaw: string): string;
{ Recover the significant (non-literal) chars from AText for AMask (round-trips
  TyMaskApply for conforming input). }
function TyMaskExtract(const AMask, AText: string): string;
{ Mask char of the (AFilledCount+1)-th editable slot, or #0 when all slots are filled. }
function TyMaskNextSlot(const AMask: string; AFilledCount: Integer): Char;
{ True when every editable slot in AMask is filled by AText. }
function TyMaskIsComplete(const AMask, AText: string): Boolean;

type
  { A masked edit (date / phone / IP …). Subclasses TTyEdit and reuses its text engine +
    'TyEdit' theme. Entry is append-only left-to-right: each keystroke that matches the
    next editable slot is accepted (literals auto-inserted), everything else rejected;
    backspace removes the last significant char. The displayed Text is always derived
    from the significant chars via TyMaskApply, so there is no separate model to keep in
    sync. Set Mask to '' to fall back to a plain edit. }
  TTyMaskEdit = class(TTyEdit)
  private
    FMask: string;
    procedure SetMask(const AValue: string);
    procedure ApplyRaw(const ARaw: string);
  protected
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { The seam TTyEdit provides for exactly this, and the one path this control never
      took. Typing was masked because UTF8KeyPress is overridden; PASTE is not typing --
      it funnels through InjectStringAt -> FilterInsert, which was inherited unchanged.
      So Ctrl+V put arbitrary text into a masked field: a phone mask happily held
      "hello world", IsComplete then answered about a string the mask never approved,
      and the caller's TyMaskExtract read back nonsense. LCL guards the same three
      messages (LM_PASTE/LM_CUT/LM_CLEAR) for the same reason. }
    function FilterInsert(const AText: string): string; override;
  public
    // True when every slot of the mask is filled (e.g. gate an OK button).
    function IsComplete: Boolean;
  published
    property Mask: string read FMask write SetMask;
    { LCL and Delphi both call this property EditMask (maskedit.pp), so code ported
      from either fails to compile on the name alone -- before anyone gets as far as
      noticing that the mask LANGUAGE is different too. This is an alias on the same
      field, not a second mask.

      What it is NOT: LCL's mask language. This control understands three slot codes
      ('#' digit, 'L' letter, 'C' any non-space) and treats every other character as a
      fixed literal; it has no escape character, no optional-slot codes, and no
      `mask;save;blank` triple. A Lazarus EditMask string will therefore be ACCEPTED
      and will silently mean something else -- '!90:00;1;_' has no '#' in it, so every
      character of it becomes a literal and the field takes no input at all. Not
      streamed: Mask is the persisted name. }
    property EditMask: string read FMask write SetMask stored False;
  end;

implementation

function TyMaskSlotAccepts(ASlot, ACh: Char): Boolean;
begin
  case ASlot of
    '#': Result := ACh in ['0'..'9'];
    'L': Result := ACh in ['A'..'Z', 'a'..'z'];
    'C': Result := ACh > ' ';
  else
    Result := False;   // literal slots are not user-fillable
  end;
end;

function TyMaskApply(const AMask, ARaw: string): string;
var
  i, ri: Integer;
  m: Char;
  pending: string;
begin
  Result := '';
  pending := '';
  ri := 1;
  for i := 1 to Length(AMask) do
  begin
    m := AMask[i];
    if m in ['#', 'L', 'C'] then
    begin
      if ri > Length(ARaw) then Break;   // out of input: drop any pending trailing literal
      Result := Result + pending + ARaw[ri];
      pending := '';
      Inc(ri);
    end
    else
      pending := pending + m;             // literal: hold until the next slot is filled
  end;
end;

function TyMaskExtract(const AMask, AText: string): string;
var
  i, ti: Integer;
  m: Char;
begin
  Result := '';
  ti := 1;
  for i := 1 to Length(AMask) do
  begin
    if ti > Length(AText) then Break;
    m := AMask[i];
    if m in ['#', 'L', 'C'] then
    begin
      Result := Result + AText[ti];
      Inc(ti);
    end
    else if AText[ti] = m then
      Inc(ti)           // consume the matching literal
    else
      Break;            // misaligned: stop
  end;
end;

function TyMaskNextSlot(const AMask: string; AFilledCount: Integer): Char;
var i, cnt: Integer;
begin
  cnt := 0;
  for i := 1 to Length(AMask) do
    if AMask[i] in ['#', 'L', 'C'] then
    begin
      if cnt = AFilledCount then Exit(AMask[i]);
      Inc(cnt);
    end;
  Result := #0;
end;

function TyMaskIsComplete(const AMask, AText: string): Boolean;
var i, slots: Integer;
begin
  slots := 0;
  for i := 1 to Length(AMask) do
    if AMask[i] in ['#', 'L', 'C'] then Inc(slots);
  Result := (slots > 0) and (Length(TyMaskExtract(AMask, AText)) >= slots);
end;

{ TTyMaskEdit }

procedure TTyMaskEdit.SetMask(const AValue: string);
begin
  if FMask = AValue then Exit;
  FMask := AValue;
  Text := '';   // a new mask starts empty (predictable; masks are set before use)
end;

procedure TTyMaskEdit.ApplyRaw(const ARaw: string);
begin
  Text := TyMaskApply(FMask, ARaw);
  CaretPos := UTF8Length(Text);   // append-only: caret always at the end
end;

procedure TTyMaskEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  raw: string;
  slot, c: Char;
begin
  if FMask = '' then
  begin
    inherited UTF8KeyPress(UTF8Key);   // no mask -> behave as a plain edit
    Exit;
  end;
  if Length(UTF8Key) = 1 then
  begin
    c := UTF8Key[1];
    raw := TyMaskExtract(FMask, Text);
    slot := TyMaskNextSlot(FMask, Length(raw));
    if (slot <> #0) and TyMaskSlotAccepts(slot, c) then
      ApplyRaw(raw + c);
  end;
  UTF8Key := '';   // always swallow: we manage Text ourselves (also rejects multibyte)
end;

procedure TTyMaskEdit.KeyDown(var Key: Word; Shift: TShiftState);
var raw: string;
begin
  if (FMask <> '') and (Shift = []) and ((Key = VK_BACK) or (Key = VK_DELETE)) then
  begin
    { Delete used to fall through to the plain edit, which removes the character at the
      caret -- including a mask LITERAL, leaving Text no longer conforming to the mask
      the control claims to enforce. This model has no mid-text hole, so both keys mean
      the same thing: drop the last significant char. }
    raw := TyMaskExtract(FMask, Text);
    if raw <> '' then Delete(raw, Length(raw), 1);
    ApplyRaw(raw);
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

function TTyMaskEdit.FilterInsert(const AText: string): string;
var
  raw, keep: string;
  i: Integer;
  slot, c: Char;
begin
  if FMask = '' then Exit(inherited FilterInsert(AText));   // plain edit, unchanged
  { Entry is append-only left-to-right, so an insertion is judged the same way a
    keystroke is: feed the incoming chars through the next free slot in turn and keep
    the ones it accepts. Literals in the pasted text are dropped rather than matched --
    TyMaskApply re-inserts them itself, so pasting "2026-07-30" into '####-##-##'
    lands the digits and rebuilds the dashes. }
  raw := TyMaskExtract(FMask, Text);
  keep := '';
  for i := 1 to Length(AText) do
  begin
    slot := TyMaskNextSlot(FMask, Length(raw) + Length(keep));
    if slot = #0 then Break;                  // every slot filled: ignore the rest
    c := AText[i];
    if TyMaskSlotAccepts(slot, c) then keep := keep + c;
  end;
  if keep <> '' then ApplyRaw(raw + keep);
  { ApplyRaw has already rewritten Text through the mask, so there is nothing left for
    the base insert to do -- '' is InjectStringAt's documented "insert nothing". }
  Result := '';
end;

function TTyMaskEdit.IsComplete: Boolean;
begin
  Result := TyMaskIsComplete(FMask, Text);
end;

end.
