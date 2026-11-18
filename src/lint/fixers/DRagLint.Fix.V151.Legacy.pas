unit DRagLint.Fix.V151.Legacy;

{ Wave v151 lane FIX-OLD -- autofixes that drive a refactoring ENGINE for rules
  that shipped without a fix:
    * with-statement, nested-with, with-hides-outer-symbol
      -> the unwith engine (DRagLint.Refactor.Unwith), one with per finding;
    * local-shadows-field (locals only) -> the routine-local rename proof
      (DRagLint.Refactor.RenameProof.ProveLocalRename).
  The statement-level fixes of the lane (repeated-else-if-condition,
  dead-store-before-out-arg, is-always-true, identifier-case-mismatch,
  unused-global) live beside their helpers in DRagLint.Fix.Stmt.
  Self-registering from the initialization section; nothing uses this unit, so
  no unit cycle forms. Both engines need the index (AutofixStore): without
  --db every fixer here declines. }

interface

uses
  DRagLint.Core.Interfaces;

/// <summary>Hands the platform library store to the with-statement fixer (FixWith), for ancestors the project index does not hold (TObject).</summary>
/// <param name="pLib">The library store; nil = a class target whose ancestor is outside the project is declined (unresolved-ancestor).</param>
/// <remarks>Set by the fix-all run (lint --fix without --fix-rule) around BuildAutofixEdits and cleared after. Not thread-safe; call from the run thread only. The caller keeps ownership of the store.</remarks>
procedure SetFixWithLibrary(const pLib: ISymbolStore);

implementation

uses
  System.SysUtils
  , System.Classes
  , System.RegularExpressions
  , TreeSitter
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  , DRagLint.Refactor.Rename
  , DRagLint.Refactor.RenameProof
  , DRagLint.Refactor.Unwith
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Lint.Autofix
  ;

var
  { the library store of the current fix-all run (SetFixWithLibrary); nil = none }
  GFixWithLib: ISymbolStore = nil;

procedure SetFixWithLibrary(const pLib: ISymbolStore);
begin
  GFixWithLib:= pLib;
end;

const
  { the last 7-bit character: the diff below works on 7-bit text only }
  MAX_ASCII = 127;
  { the prefix a renamed shadowing local gets (Delphi's own convention for locals) }
  LOCAL_PREFIX = 'L';

{ True when every character of S is 7-bit }
function IsAscii(const S: string): Boolean;
var
  C: Char;
begin
  for C in S do
    if Ord(C) > MAX_ASCII then Exit(False);
  Result:= True;
end;

{ the deepest named node of ARoot holding the 0-based point (ARow, ACol) }
function NodeAtPoint(const ARoot: TTSNode; ARow, ACol: Integer): TTSNode;
const
  ROW_SHIFT = 32;  { a point as one ordered Int64: row in the high half, column in the low half }
var
  I    : Integer;
  Ch   : TTSNode;
  Found: Boolean;
  P    : Int64  ;
begin
  P:= (Int64(ARow) shl ROW_SHIFT) or Cardinal(ACol);
  Result:= ARoot;
  repeat
    Found:= False;
    for I:= 0 to Result.NamedChildCount - 1 do
    begin
      Ch:= Result.NamedChild(I);
      if (((Int64(Ch.StartPoint.Row) shl ROW_SHIFT) or Ch.StartPoint.Column) <= P)
         and (((Int64(Ch.EndPoint.Row) shl ROW_SHIFT) or Ch.EndPoint.Column) > P) then
      begin
        Result:= Ch;
        Found := True;
        Break;
      end;
    end;
  until not Found;
end;

{ the 1-based line of the with statement that holds the finding (with-statement,
  and nested-with sit on the with itself,
  with-hides-outer-symbol on a bare name in its body); 0 when there is none }
function WithLineOf(const AFinding: TLintFinding): Integer;
var
  PF: TParsedFile;
  N : TTSNode    ;
begin
  Result:= 0;
  PF:= TAstParseCache.Get(AFinding.FilePath);
  if PF.Tree = nil then Exit;
  N:= NodeAtPoint(PF.Tree.RootNode, AFinding.StartLine - 1, AFinding.StartCol - 1);
  while (not N.IsNull) and (N.NodeType <> 'with') do N:= N.Parent;
  if not N.IsNull then Result:= Integer(N.StartPoint.Row) + 1;
end;

{ ONE tekReplaceLines edit that turns ALines into the text of ANewBytes: the
  changed run of lines between the common head and the common tail. nil when
  either side is not 7-bit or nothing differs. }
function DiffEdit(const APath: string; ALines: TStringList; const ANewBytes: TBytes): TArray<TTextEdit>;
var
  NewL      : TStringList;
  F, OE, NE : Integer    ;
  Run       : TArray<string>;
  I         : Integer    ;
  E         : TTextEdit  ;
begin
  Result:= nil;
  NewL:= TStringList.Create;
  try
    NewL.Text:= TEncoding.ANSI.GetString(ANewBytes);
    if not IsAscii(NewL.Text) or not IsAscii(ALines.Text) then Exit;
    F:= 0;
    while (F < ALines.Count) and (F < NewL.Count) and (ALines[F] = NewL[F]) do Inc(F);
    OE:= ALines.Count - 1;
    NE:= NewL.Count - 1;
    while (OE >= F) and (NE >= F) and (ALines[OE] = NewL[NE]) do
    begin
      Dec(OE);
      Dec(NE);
    end;
    if (F > OE) or (F > NE) then Exit;  { a pure insertion or deletion: unwith never makes one }
    Run:= nil;
    for I:= F to NE do Run:= Run + [NewL[I]];
    E:= Default(TTextEdit);
    E.FilePath  := APath;
    E.Kind      := tekReplaceLines;
    E.Line      := F + 1;
    E.EndLine   := OE + 1;
    E.Text      := string.Join(sLineBreak, Run);
    E.ExpectText:= ALines[F];
    Result:= [E];
  finally
    NewL.Free;
  end;
end;

{ with-statement / nested-with / with-hides-outer-symbol:
  remove the with that holds the finding by qualifying each bare name of its
  body that the target's member closure declares -- exactly the unwith
  engine's `--plan` rewrite of that one with. The engine refuses (and this
  fixer declines) whenever its two BEFORE proofs disagree or cannot be made:
  the static member closure and the resolver's binding of each name in the
  index, plus target stability, a call / cast / getter target, a conditional,
  asm or an anonymous method in the body, and the rest of its refusal list.
  RISKY (opt-in): the third proof, re-indexing the rewritten file and checking
  every name still binds as before, runs only in `unwith --apply`; --fix has
  no index of the edited bytes. Use `unwith --apply` for the fully proven path.
  with-multiple-items gets no fixer: the engine refuses every `with A, B do`
  (multiple-targets), so registering it would only advertise a fix that never applies. }
function FixWith(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Store: ISymbolStore   ;
  Plan : TUnwithFilePlan;
  L    : Integer        ;
begin
  Result:= nil;
  Store:= AutofixStore;
  if (Store = nil) or (ALines = nil) then Exit;
  L:= WithLineOf(AFinding);
  if L = 0 then Exit;
  Plan:= UnwithPlanFile(Store, GFixWithLib, AFinding.FilePath, L);
  if (Length(Plan.Sites) <> 1) or (Plan.Sites[0].Refusal <> '') or (Length(Plan.NewBytes) = 0) then Exit;
  Result:= DiffEdit(AFinding.FilePath, ALines, Plan.NewBytes);
end;

{ local-shadows-field (locals only): rename the local to L<Name>.
  PROOF: ProveLocalRename decides every occurrence of the old name in the
  owning routine (by the resolver's binding under a with) and refuses when the
  routine already names the new one; this fixer also declines when the new
  name occurs anywhere in the file. A local is visible in its routine only, so
  renaming all its occurrences and nothing else keeps every binding: the
  field stays reachable as before and the local's uses still reach the local.
  A PARAMETER is declined: its name is part of the routine's signature (the
  interface declaration, named arguments, documentation). }
function FixLocalShadowsField(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@3e5a -- REVIEWED 2026-11-14: a fixer declines (Exit) on every source shape it was not written for; guard clauses by design
var
  M         : TMatch     ;
  Nm, NewNm : string     ;
  Proof     : TRenameProof;
  RE        : TRenameEdit;
  E         : TTextEdit  ;
begin
  Result:= nil;
  if ALines = nil then Exit;
  M:= TRegEx.Match(AFinding.Message, '^Local "(\w+)"');
  if not M.Success then Exit;
  Nm:= M.Groups[1].Value;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count)
     or (Copy(ALines[AFinding.StartLine - 1], AFinding.StartCol, Length(Nm)) <> Nm) then Exit;
  NewNm:= LOCAL_PREFIX + Nm;
  if TRegEx.IsMatch(ALines.Text, '(?<![\w&])' + NewNm + '(?!\w)', [roIgnoreCase]) then Exit;
  Proof:= ProveLocalRename(AutofixStore, AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, NewNm);
  if (not Proof.Found) or (Length(Proof.Refusals) > 0) or (Length(Proof.Edits) = 0) then Exit;
  for RE in Proof.Edits do
  begin
    if not SameText(RE.FilePath, AFinding.FilePath) then Exit(nil);
    E:= Default(TTextEdit);
    E.FilePath  := RE.FilePath;
    E.Kind      := tekReplaceInLine;
    E.Line      := RE.Line;
    E.Col       := RE.Col;
    E.EndCol    := RE.Col + Length(RE.OldName);
    E.Text      := RE.NewName;
    E.ExpectText:= RE.OldName;
    E.AtomGroup := Format('local-shadows-field:%s:%d:%d', [AFinding.FilePath, AFinding.StartLine, AFinding.StartCol]);  { all or none }
    Result:= Result + [E];
  end;
end;

initialization
  RegisterFixer('with-statement', FixWith, True);
  RegisterFixer('nested-with', FixWith, True);
  RegisterFixer('with-hides-outer-symbol', FixWith, True);
  RegisterFixer('local-shadows-field', FixLocalShadowsField);

end.
