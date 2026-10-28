unit DRagLint.Diagnostics.ConcurrencyChecks;

{ Clippy-parity wave (plan 2026-10-27-clippy-rules-plan.md), lane L9.
  L0 shipped this unit as a STUB: Check returns nil. The lane replaces the body
  and adds the emitted ids to LINT_GATE_CONCURRENCY's checker (the ids are already
  in the gate list and in TRuleCatalog.BuiltinRegistry -- a lane registers
  nothing new in CLI.pas or RuleCatalog.pas).
  Rules: wait-while-holding-lock. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the wait-while-holding-lock rules. Flags a blocking call made while a lock is held.</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_CONCURRENCY).
  /// </remarks>
  TConcurrencyChecker = class
  public
    /// <summary>Runs the ConcurrencyChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (thresholds via ThresholdFor).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index.</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  ;

class function TConcurrencyChecker.Check(const AFile: string; const ACfg: TLintConfig;  // dl:ok unused-parameter@7485 -- REVIEWED 2026-10-28: gate-fixed checker signature (LINT_GATE_CONCURRENCY call sites); the rules are threshold-free
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;  // dl:ok unused-parameter@9a67 -- REVIEWED 2026-10-28: gate-fixed checker signature; the rules are store-free
const
  BLOCKING: array[0..7] of string = (
    'synchronize', 'waitfor', 'sendmessage', 'sleep', 'showmessage', 'messagedlg',
    'processmessages', 'waitforsingleobject');
var
  Src     : TBytes             ;
  PF      : TParsedFile        ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte);
    E:= Integer(N.EndByte);
    L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Lower-cased text with blanks removed and a leading 'self.' dropped, so
    'Self.FLock' and 'FLock' name the same lock. }
  function Canon(const AText: string): string;
  begin
    Result:= LowerCase(StringReplace(StringReplace(StringReplace(Trim(AText), ' ', '', [rfReplaceAll]),
      #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]));
    if StartsText('self.', Result) then Delete(Result, 1, Length('self.'));
  end;

  procedure EmitAt(const ANode: TTSNode; const ACallee, ALock: string);
  var
    P: TTSPoint    ;
    F: TLintFinding;
  begin
    P:= ANode.StartPoint;
    F:= Default(TLintFinding);
    F.RuleId   := 'wait-while-holding-lock';
    F.Severity := 'warning';
    F.Message  := Format('%s blocks while lock %s is held -- risk of deadlock; release the lock first',
      [ACallee, ALock]);
    F.FilePath := AFile;
    F.StartLine:= Integer(P.Row   ) + 1;
    F.StartCol := Integer(P.Column) + 1;
    F.EndLine  := F.StartLine;
    F.EndCol   := F.StartCol + Length(Trim(NodeStr(ANode)));
    Findings.Add(F);
  end;

  function IsBlocking(const ALastSeg: string): Boolean;
  var
    I: Integer;
  begin
    Result:= False;
    for I:= Low(BLOCKING) to High(BLOCKING) do
      if ALastSeg = BLOCKING[I] then Exit(True);
  end;

  { Classify one call. ACallee is the canonical callee text, AFirstArg the
    canonical first argument ('' when none). Updates AHeld (lock key -> display
    text) and reports a blocking call made while AHeld is non-empty. }
  procedure Classify(const ANode: TTSNode; const ACallee, AFirstArg: string;
    const AHeld: TDictionary<string, string>);
  var
    Dot     : Integer;
    LastSeg : string;
    Receiver: string;
    Key     : string;
  begin
    if ACallee = '' then Exit;
    Dot:= LastDelimiter('.', ACallee);
    LastSeg := Copy(ACallee, Dot + 1, MaxInt);
    Receiver:= Copy(ACallee, 1, Dot - 1);
    if (ACallee = 'tmonitor.enter') or (ACallee = 'entercriticalsection') then
    begin
      if AFirstArg <> '' then AHeld.AddOrSetValue(AFirstArg, AFirstArg);
    end
    else if (ACallee = 'tmonitor.exit') or (ACallee = 'leavecriticalsection') then
      AHeld.Remove(AFirstArg)
    else if (Receiver <> '') and ((LastSeg = 'enter') or (LastSeg = 'acquire')) then
      AHeld.AddOrSetValue(Receiver, Receiver)
    else if (Receiver <> '') and ((LastSeg = 'leave') or (LastSeg = 'release')) then
      AHeld.Remove(Receiver)
    else if (AHeld.Count > 0) and IsBlocking(LastSeg) then
      for Key in AHeld.Keys do
      begin
        EmitAt(ANode, ACallee, AHeld[Key]);
        Break;
      end;
  end;

  { Document-order walk of one routine body. A nested routine or an anonymous
    method has its own lock state (handled by Visit), so it is not entered. }
  procedure Scan(const N: TTSNode; const AHeld: TDictionary<string, string>);
  var
    I      : Integer;
    Args   : TTSNode;
    FirstA : string;
    Kid    : TTSNode;
  begin
    if N.IsNull then Exit;
    if (N.NodeType = 'defProc') or (N.NodeType = 'lambda') then Exit;
    if N.NodeType = 'exprCall' then
    begin
      FirstA:= '';
      Args:= N.ChildByField('args');
      if (not Args.IsNull) and (Args.NamedChildCount > 0) then
        FirstA:= Canon(NodeStr(Args.NamedChild(0)));
      if N.ChildCount > 0 then Classify(N, Canon(NodeStr(N.Child(0))), FirstA, AHeld);
    end
    else if (N.NodeType = 'statement') and (N.NamedChildCount = 1) then
    begin
      Kid:= N.NamedChild(0);
      if (Kid.NodeType = 'exprDot') or (Kid.NodeType = 'identifier') then
        Classify(Kid, Canon(NodeStr(Kid)), '', AHeld);
    end;
    for I:= 0 to N.NamedChildCount - 1 do Scan(N.NamedChild(I), AHeld);
  end;

  procedure Visit(const N: TTSNode);
  var
    I   : Integer;
    Held: TDictionary<string, string>;
  begin
    if N.IsNull then Exit;
    if (N.NodeType = 'defProc') or (N.NodeType = 'lambda') then
    begin
      Held:= TDictionary<string, string>.Create;
      try
        for I:= 0 to N.NamedChildCount - 1 do Scan(N.NamedChild(I), Held);
      finally
        Held.Free;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try
    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end;

end.
