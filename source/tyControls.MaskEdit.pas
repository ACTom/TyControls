unit tyControls.MaskEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, LCLType, LazUTF8,
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
{ '' when AMask is usable, otherwise the reason it is not -- see TTyMaskEdit.Mask for what
  this control's mask language is and, more to the point, what it is NOT. Setting Mask
  raises ETyMaskError with this text; call it first to check a mask without raising. }
function TyMaskRejectReason(const AMask: string): string;

type
  { Raised for a mask this control cannot honour. See TTyMaskEdit.Mask. }
  ETyMaskError = class(Exception);

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
    procedure SetMaskedText(const AValue: TCaption);
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
    { THE MASK LANGUAGE, and its boundary.

      Understood: '#' = digit, 'L' = letter, 'C' = any non-space. EVERY other character is
      a fixed literal, auto-inserted between slots. There is no escape character, no
      optional-slot code, no case-forcing '>' / '<', and no `mask;save;blank` triple.
      That is three codes against LCL/Delphi's ~17 (maskedit.pp), and implementing theirs
      is a separate job, not a bug fix.

      The bug fix is that the difference used to be SILENT. A Lazarus EditMask string is
      well-formed input to this parser and means something else: '000-0000' contains no
      '#', so all eight characters become literals, the field has no editable slot at all
      and can never take a keystroke -- with nothing raised, logged, or visible. Two
      shapes of that are now refused outright with ETyMaskError (see TyMaskRejectReason):

        * a non-empty mask with NO editable slot ('000-0000', '99/99/00', 'AAA-aaa').
          A field that cannot accept input has no legitimate use -- an inert edit is
          spelled Mask := '' (plain edit, still supported) or ReadOnly := True.
        * a mask containing ';', which is LCL's `mask;save;blank` separator and nothing
          else. This one has to be caught by name because such a mask can still have
          real slots: '##/##;1;_' would have taken digits and thrown ';1;_' away unseen.

      Deliberately NOT refused: an LCL code sitting among working slots. '19##' is a
      perfectly good year mask and a literal '9' is legal here, so guessing at intent
      would break working code to catch a hypothetical port. A leading '!' is left alone
      for the same reason -- and unlike ';' it announces itself, since as a literal it is
      drawn: '!##' displays as "!12". }
    property Mask: string read FMask write SetMask;
    { LCL and Delphi both call this property EditMask (maskedit.pp), so code ported
      from either fails to compile on the name alone -- before anyone gets as far as
      noticing that the mask LANGUAGE is different too (see Mask above). This is an alias
      on the same field, not a second mask. Not streamed: Mask is the persisted name. }
    property EditMask: string read FMask write SetMask stored False;
    { Typing (UTF8KeyPress), Delete/Backspace (KeyDown) and paste (FilterInsert) were all
      overridden. The plainest entry point of all was not: `Ed.Text := 'hello world'` went
      straight to TTyEdit's setter, so a phone field held a sentence, IsComplete then
      answered about a string the mask had never approved -- it counts slot POSITIONS, not
      legal characters, so '###-###' holding 'abc-def' reported COMPLETE -- and the
      caller's TyMaskExtract read back 'abcdef'.

      An assignment is now judged exactly as a paste into an empty field is: feed the
      incoming characters through the free slots in turn, keep what fits, drop the rest,
      rebuild the literals. One rule for both, so `Ed.Text := S` and Ctrl+V of the same S
      can never disagree.

      It never rejects and never raises -- LCL does not either (maskedit.pp:1656
      ApplyMaskToText, whose own comment ends "The text that is set, does not need to
      validate"; it pads and truncates instead). We truncate as it does. We do not pad:
      LCL always returns a full-length string of blank characters, this control has no
      blank character and defines IsComplete by how many slots are filled, so a value too
      short for the mask simply stays short and IsComplete says False.

      Static binding, unavoidable: this is a property override, so it intercepts
      assignments made through a TTyMaskEdit-typed (or descendant) reference. Casting to
      the base -- `TTyEdit(M).Text := X` -- still reaches TTyEdit's setter unfiltered.
      Do not do that. }
    property Text write SetMaskedText;
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

function TyMaskRejectReason(const AMask: string): string;
var
  i, slots: Integer;
begin
  Result := '';
  if AMask = '' then Exit;   // documented: no mask at all = plain edit
  if Pos(';', AMask) > 0 then
    Exit(Format('mask "%s" contains ";", which is LCL/Delphi''s "mask;save;blank" ' +
      'separator. This control does not implement that triple; everything after the ' +
      'first ";" would silently become literal text.', [AMask]));
  slots := 0;
  for i := 1 to Length(AMask) do
    if AMask[i] in ['#', 'L', 'C'] then Inc(slots);
  if slots = 0 then
    Result := Format('mask "%s" has no editable slot, so the field could never accept ' +
      'input. The slot codes here are "#" (digit), "L" (letter) and "C" (any ' +
      'non-space); LCL/Delphi codes such as 0 9 A a are plain literals in this mask ' +
      'language. Use Mask := '''' for an unmasked edit.', [AMask]);
end;

{ The characters of AInput this mask will take, in order, when appended after the ARaw
  already laid down. Shared by paste and by `Text :=` so the two cannot disagree. }
function MaskAcceptedFrom(const AMask, ARaw, AInput: string): string;
var
  i: Integer;
  slot: Char;
begin
  Result := '';
  for i := 1 to Length(AInput) do
  begin
    slot := TyMaskNextSlot(AMask, Length(ARaw) + Length(Result));
    if slot = #0 then Break;                  // every slot filled: ignore the rest
    if TyMaskSlotAccepts(slot, AInput[i]) then Result := Result + AInput[i];
  end;
end;

{ True when AText is EXACTLY what AMask produces for the significant chars it carries:
  literals in their own places, every significant char legal for its slot, and nothing
  left over. ARaw then holds those chars (it is scratch on a False result).

  Not the same question as TyMaskExtract, which copies whatever sits at a slot POSITION
  without asking whether it belongs there -- that is why IsComplete used to answer True
  for '###-###' holding 'abc-def'. }
function MaskConformingRaw(const AMask, AText: string; out ARaw: string): Boolean;
var
  i, ti: Integer;
  m: Char;
begin
  ARaw := '';
  ti := 1;
  for i := 1 to Length(AMask) do
  begin
    if ti > Length(AText) then Break;
    m := AMask[i];
    if m in ['#', 'L', 'C'] then
    begin
      if not TyMaskSlotAccepts(m, AText[ti]) then Exit(False);
      ARaw := ARaw + AText[ti];
      Inc(ti);
    end
    else if AText[ti] = m then
      Inc(ti)             // consume the matching literal
    else
      Exit(False);        // misaligned
  end;
  { Nothing left over, and no dangling trailing literal ('12/' on '##/##' extracts to
    '12', which re-applies to '12' -- so '12/' is NOT conforming and gets normalised). }
  Result := (ti > Length(AText)) and (TyMaskApply(AMask, ARaw) = AText);
end;

{ TTyMaskEdit }

procedure TTyMaskEdit.SetMask(const AValue: string);
var
  why: string;
begin
  if FMask = AValue then Exit;
  why := TyMaskRejectReason(AValue);
  if why <> '' then raise ETyMaskError.Create('TTyMaskEdit.Mask: ' + why);
  FMask := AValue;
  if csLoading in ComponentState then
    { Streaming order is fixed and against us: Text keeps the RTTI slot it inherited from
      TTyEdit, so the writer emits it BEFORE this descendant's Mask and the reader has
      already handed it over with no mask in force. Clearing here (below) threw away every
      value designed in the Object Inspector. Re-run it through the new mask instead. }
    SetMaskedText(Text)
  else
    Text := '';   // a new mask starts empty (predictable; masks are set before use)
end;

procedure TTyMaskEdit.ApplyRaw(const ARaw: string);
begin
  { Straight to the base setter on purpose: ARaw is already the accepted significant
    chars, so SetMaskedText would only re-derive the same string on every keystroke. }
  inherited Text := TyMaskApply(FMask, ARaw);
  CaretPos := UTF8Length(Text);   // append-only: caret always at the end
end;

procedure TTyMaskEdit.SetMaskedText(const AValue: TCaption);
var
  raw: string;
begin
  if FMask = '' then
  begin
    inherited Text := AValue;   // no mask -> plain edit, byte-identical
    Exit;
  end;
  { An already-conforming value (our own display string, an .lfm value, a copy from a
    sibling edit) is kept verbatim. Re-filtering it is NOT a no-op: 'C' accepts any
    non-space char, so on mask 'C-C' the filter eats the mask's own '-' as CONTENT and
    turns 'a-b' into 'a--'. Without this branch `Ed.Text := Ed.Text` corrupts itself. }
  if not MaskConformingRaw(FMask, AValue, raw) then
    raw := MaskAcceptedFrom(FMask, '', AValue);
  inherited Text := TyMaskApply(FMask, raw);
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
begin
  if FMask = '' then Exit(inherited FilterInsert(AText));   // plain edit, unchanged
  { Entry is append-only left-to-right, so an insertion is judged the same way a
    keystroke is: feed the incoming chars through the next free slot in turn and keep
    the ones it accepts (MaskAcceptedFrom -- the same rule `Text :=` uses, so paste and
    assignment cannot drift apart). Literals in the pasted text are dropped rather than
    matched -- TyMaskApply re-inserts them itself, so pasting "2026-07-30" into
    '####-##-##' lands the digits and rebuilds the dashes. }
  raw := TyMaskExtract(FMask, Text);
  keep := MaskAcceptedFrom(FMask, raw, AText);
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
