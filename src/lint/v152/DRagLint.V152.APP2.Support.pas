unit DRagLint.V152.APP2.Support;

{ Wave v152 lane APP2 -- helpers of DRagLint.V152.APP2 (private to the lane).
  O01: ui-call-in-console-or-service across units. The v151 per-file rule sees a dialog call only
  when it is written in the console program's own file; this pass follows a call from a console
  program into a routine declared in another unit of its uses closure that shows a dialog,
  directly or through other routines. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces  // ISymbolStore
  , DRagLint.V151.Api  // TProgramConsoleProbe
  ;

const
  /// <summary>Host rule id the findings are reported under, so --rule reaches them.</summary>
  APP2_RULE_UI_CALL = 'ui-call-in-console-or-service';

type
  /// <summary>Cross-unit pass of ui-call-in-console-or-service (owner ruling 2026-11-17: follow calls into other units).</summary>
  /// <remarks>
  /// Source-text based like the v151 per-file rule: a routine is matched by its simple name,
  /// restricted to the units the console program uses (transitively), so a same-named routine in an
  /// unused unit never matches. The text pass follows stand-alone routines only (a method call needs a
  /// receiver type, which text alone cannot give). 1.56 G-62: when the run has an index, a second pass
  /// follows METHODS through the resolved call edges (certain, routine calls) back from every routine that
  /// shows a dialog or carries a ui_affinity, over at most 8 hops with a visited set per seed (cycles end),
  /// to a console program's main block or to a method of a TService descendant, and prints the chain.
  /// Its findings are added only at call sites the text pass did not report. Stateless; class methods only.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V152.APP2.TV152APP2Rules.CheckProject (DRagLint.V152.APP2.pas)</para>
  /// <para>Used in units: DRagLint.V152.APP2</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TApp2CrossUnit = class
  public
    /// <summary>Reports, in every console program of the project, each call of a dialog-showing routine declared in another unit.</summary>
    /// <param name="AFilePaths">Every file of the run; programs are the .dpr files, units the .pas files.</param>
    /// <param name="AProjectPath">The --project file, or '' for a database-wide run; when set, only the program with that base name is checked.</param>
    /// <param name="AProgramHasConsole">The run's program probe (lint-all's, as writeln-in-gui-app gets it); nil = unknown.
    /// A program is a console program when its own directives say so (ProgramSrcHasConsole) or the probe does.</param>
    /// <param name="AStore">The run's index; nil = text pass only (no method following).</param>
    /// <returns>One warning per call, located in the program file (or, for a service, in the calling method's file); nil when there is none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas) ?, DRagLint.V152.APP2.TV152APP2Rules.CheckProject (DRagLint.V152.APP2.pas)</para>
    /// <para>Calls: DRagLint.V151.APP.Support.ReadAppSource, DRagLint.V151.APP.Support.TAppSrc.Create, DRagLint.V152.APP2.Support.CheckProgram, DRagLint.V152.APP2.Support.UnitOf, ExtractFileExt, SameText</para>
    /// <para>Returns: nil; Acc.ToArray</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.APP.Support.ReadAppSource"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.Create"/>
    /// <seealso cref="DRagLint.V152.APP2.Support.CheckProgram"/>
    /// <seealso cref="DRagLint.V152.APP2.Support.UnitOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Run(const AFilePaths: TArray<string>; const AProjectPath: string;
      const AProgramHasConsole: TProgramConsoleProbe; const AStore: ISymbolStore = nil): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Math
  , System.IOUtils
  , System.RegularExpressions
  , DRagLint.Core.Encoding  // ReadSourceFileLines
  , DRagLint.V151.APP.Support
  ;

const
  DIALOG_RE =
    '(?<![\w\.])(?:(?:(?:Vcl|FMX)\.)?Dialogs\.)?' +
    '(?:ShowMessage|ShowMessageFmt|ShowMessagePos|MessageDlg|MessageDlgPos|TaskMessageDlg|InputBox|InputQuery)\s*\(' +
    '|\bApplication\s*\.\s*MessageBox\s*\(|\bTDialogService\s*\.\s*\w+\s*\(';
  USES_RE    = '\buses\b([^;]*);';
  IDENT_RE   = '[A-Za-z_][\w\.]*';
  DECL_LOOKBACK = 24;  { chars before a name that cover procedure / function plus blanks }
  MAX_HOPS      = 8;   { G-62: resolved call hops walked back from a dialog routine }
  CONF_CERTAIN  = 'certain';
  UNIT_CLASS_METHOD_PARTS = 3;  { Unit.Class.Method }

type
  /// <summary>One scanned file of the run.</summary>
  TApp2File = record
    Path: string;
    Src : TAppSrc;
  end;

function UnitOf(const APath: string): string;
begin
  Result:= LowerCase(TPath.GetFileNameWithoutExtension(APath));
end;

procedure UsesOf(const ASrc: TAppSrc; AOut: TList<string>);
var
  U, W: TMatch;
begin
  for U in TRegEx.Matches(ASrc.Masked, USES_RE, [roIgnoreCase]) do
    for W in TRegEx.Matches(U.Groups[1].Value, IDENT_RE) do
      if not SameText(W.Value, 'in') then AOut.Add(LowerCase(W.Value));
end;

function ClosureOf(const AProgram: TAppSrc; const AUnits: TDictionary<string, TApp2File>): TList<string>;
var
  Todo: TStack<string>;
  Name, Used: string;
  Direct: TList<string>;
begin
  Result:= TList<string>.Create;
  Todo:= TStack<string>.Create;
  Direct:= TList<string>.Create;
  try
    UsesOf(AProgram, Direct);
    for Used in Direct do Todo.Push(Used);
    while Todo.Count > 0 do
    begin
      Name:= Todo.Pop;
      if Result.Contains(Name) or not AUnits.ContainsKey(Name) then Continue;
      Result.Add(Name);
      Direct.Clear;
      UsesOf(AUnits[Name].Src, Direct);
      for Used in Direct do Todo.Push(Used);
    end;
  finally
    Direct.Free;
    Todo.Free;
  end;
end;

{ Name (lower case) -> declaring unit, for every stand-alone routine of the closure that shows a dialog, directly or by calling one. }
function DialogRoutines(const AClosure: TList<string>; const AUnits: TDictionary<string, TApp2File>): TDictionary<string, string>;
var
  Added, Shows: Boolean;
  UnitName, Key, Body, Other: string;
  R: TAppRoutine;
begin
  Result:= TDictionary<string, string>.Create;
  repeat
    Added:= False;
    for UnitName in AClosure do
      for R in AUnits[UnitName].Src.Routines do
      begin
        Key:= LowerCase(R.Name);
        if Key.Contains('.') or Result.ContainsKey(Key) then Continue;
        Body:= AUnits[UnitName].Src.BodyOf(R);
        Shows:= TRegEx.IsMatch(Body, DIALOG_RE, [roIgnoreCase]);
        if not Shows then
          for Other in Result.Keys do
            if TRegEx.IsMatch(Body, '(?<![\w\.])' + TRegEx.Escape(Other) + '\b', [roIgnoreCase]) then
            begin
              Shows:= True;
              Break;
            end;
        if Shows then
        begin
          Result.Add(Key, UnitName);
          Added:= True;
        end;
      end;
  until not Added;
end;

{ True when the word at AIndex (0-based) is the name in a procedure / function header rather than a call. }
function IsDeclarationAt(const AMasked: string; AIndex: Integer): Boolean;
var
  Start: Integer;
begin
  Start:= Max(1, AIndex - DECL_LOOKBACK + 1);
  Result:= TRegEx.IsMatch(Copy(AMasked, Start, AIndex - Start + 1), '\b(?:procedure|function)\s+\z', [roIgnoreCase]);
end;

procedure CheckProgram(const AProgPath: string; const AProgram: TAppSrc; const AUnits: TDictionary<string, TApp2File>;
  AAcc: TList<TLintFinding>);
var
  Closure: TList<string>;
  Dialogs: TDictionary<string, string>;
  Own, Names: TList<string>;
  R: TAppRoutine;
  M: TMatch;
  Key, Qualifier, DeclUnit: string;
  F: TLintFinding;
begin
  Closure:= ClosureOf(AProgram, AUnits);
  Dialogs:= DialogRoutines(Closure, AUnits);
  Own:= TList<string>.Create;
  Names:= TList<string>.Create;
  try
    for R in AProgram.Routines do Own.Add(LowerCase(R.Name));
    for Key in Dialogs.Keys do
      if not Own.Contains(Key) then Names.Add(TRegEx.Escape(Key));
    if Names.Count = 0 then Exit;
    for M in TRegEx.Matches(AProgram.Masked,
      '(?<![\w\.])(?:(?<q>[A-Za-z_][\w\.]*)\.)?(?<n>' + string.Join('|', Names.ToArray) + ')\b',
      [roIgnoreCase]) do
    begin
      Key:= LowerCase(M.Groups['n'].Value);
      Qualifier:= LowerCase(M.Groups['q'].Value);
      DeclUnit:= Dialogs[Key];
      if (Qualifier <> '') and (Qualifier <> DeclUnit) then Continue;
      if IsDeclarationAt(AProgram.Masked, M.Index) then Continue;
      F:= Default(TLintFinding);
      F.RuleId   := APP2_RULE_UI_CALL;
      F.FilePath := AProgPath;
      F.StartLine:= AProgram.LineOf(M.Index + 1);
      F.StartCol := AProgram.ColOf(M.Index + 1);
      F.EndLine  := AProgram.LineOf(M.Index + M.Length + 1);
      F.EndCol   := AProgram.ColOf(M.Index + M.Length + 1);
      F.Severity := 'warning';
      F.Message  := 'Call to ' + M.Groups['n'].Value + ' (unit ' + DeclUnit + ') shows a dialog in a console program -- ' +
        'there is no desktop to show it on, so the call blocks forever or fails.';
      AAcc.Add(F);
    end;
  finally
    Names.Free;
    Own.Free;
    Dialogs.Free;
    Closure.Free;
  end;
end;

function ShortQName(const AQName: string): string;
var
  Parts: TArray<string>;
begin
  Parts:= AQName.Split(['.']);
  Result:= if Length(Parts) >= 2 then Parts[High(Parts) - 1] + '.' + Parts[High(Parts)] else AQName;
end;

{ True when the routine's body (ImplStartLine..ImplEndLine) holds a dialog call outside a // comment. }
function BodyShowsDialog(const ALines: TArray<string>; const ASym: TSymbol): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if (ALines = nil) or (ASym.ImplStartLine <= 0) or (ASym.ImplEndLine > Length(ALines)) then Exit;
  for I:= ASym.ImplStartLine to ASym.ImplEndLine do
    if not Trim(ALines[I - 1]).StartsWith('//') and TRegEx.IsMatch(ALines[I - 1], DIALOG_RE, [roIgnoreCase]) then
      Exit(True);
end;

{ G-62: walks the resolved call edges back from every dialog routine to a console program's main block
  (caller id 0 in a program file) or to a method of a TService descendant; one finding per call site. }
procedure FollowMethods(const AStore: ISymbolStore; AProgramPaths: TList<string>; AAcc: TList<TLintFinding>);
type
  TStep = record
    SymId: Int64;
    Chain: string;
  end;
var
  Services, Emitted, Reported: TDictionary<string, Boolean>;
  Lines: TDictionary<string, TArray<string>>;
  Visited: TDictionary<Int64, Boolean>;
  Frontier, Next: TList<TStep>;
  SF: TSymbolFacts;
  U, Caller: TSymbol;
  Step, First: TStep;
  C: TResolvedCaller;
  F: TLintFinding;
  Hop: Integer;
  Why, Key, Name, Where: string;
  Parts: TArray<string>;

  function LinesOf(const APath: string): TArray<string>;
  begin
    if not Lines.TryGetValue(APath, Result) then
    begin
      try
        Result:= ReadSourceFileLines(APath);
      except  // dl:ok bare-except@8ac3 -- REVIEWED 2026-11-27 v156 G62R: one unreadable source file must cost its own findings, never abort the lint run
        Result:= nil;
      end;
      Lines.Add(APath, Result);
    end;
  end;

  function IsServiceMethod(const ASym: TSymbol): Boolean;
  begin
    Parts:= ASym.QualifiedName.Split(['.']);
    Result:= (Length(Parts) >= UNIT_CLASS_METHOD_PARTS) and Services.ContainsKey(LowerCase(Parts[High(Parts) - 1]));
  end;

begin
  Services:= TDictionary<string, Boolean>.Create;
  Emitted:= TDictionary<string, Boolean>.Create;
  Reported:= TDictionary<string, Boolean>.Create;
  Lines:= TDictionary<string, TArray<string>>.Create;
  Visited:= TDictionary<Int64, Boolean>.Create;
  Frontier:= TList<TStep>.Create;
  Next:= TList<TStep>.Create;
  try
    for Name in AStore.FindDescendantNames('TService') do Services.AddOrSetValue(LowerCase(Name), True);
    Services.Remove('tservice');
    if (Services.Count = 0) and (AProgramPaths.Count = 0) then Exit;
    for F in AAcc do Reported.AddOrSetValue(LowerCase(F.FilePath) + '|' + IntToStr(F.StartLine), True);
    for SF in AStore.GetAllSymbolFacts do
    begin
      U:= AStore.GetSymbolById(SF.SymbolId);
      if U.Id = 0 then Continue;
      if SF.UiAffinity <> '' then Why:= 'touches ' + SF.UiAffinity
      else if BodyShowsDialog(LinesOf(AStore.GetFilePath(U.FileId)), U) then Why:= 'shows a dialog'
      else Continue;
      Visited.Clear;
      Visited.Add(U.Id, True);
      Frontier.Clear;
      First.SymId:= U.Id;
      First.Chain:= ShortQName(U.QualifiedName);
      Frontier.Add(First);
      for Hop:= 1 to MAX_HOPS do
      begin
        Next.Clear;
        for Step in Frontier do
          for C in AStore.FindResolvedCallers(Step.SymId) do
          begin
            if (C.Mode <> '') or (C.Confidence <> CONF_CERTAIN) or (C.FullPath = '') or (C.CallSiteLine <= 0) then Continue;
            if C.EnclosingSymbolId = 0 then
            begin
              if not AProgramPaths.Contains(LowerCase(C.FullPath)) then Continue;
              Where:= 'in a console program';
              Caller:= Default(TSymbol);
            end
            else
            begin
              if Visited.ContainsKey(C.EnclosingSymbolId) then Continue;
              Caller:= AStore.GetSymbolById(C.EnclosingSymbolId);
              if Caller.Id = 0 then Continue;
              if not IsServiceMethod(Caller) then
              begin
                Visited.Add(C.EnclosingSymbolId, True);
                First.SymId:= Caller.Id;
                First.Chain:= ShortQName(Caller.QualifiedName) + ' -> ' + Step.Chain;
                Next.Add(First);
                Continue;
              end;
              Where:= 'in a method of a Windows service';
            end;
            Key:= LowerCase(C.FullPath) + '|' + IntToStr(C.CallSiteLine);
            if Reported.ContainsKey(Key) or Emitted.ContainsKey(Key) then Continue;
            Emitted.Add(Key, True);
            F:= Default(TLintFinding);
            F.RuleId   := APP2_RULE_UI_CALL;
            F.FilePath := C.FullPath;
            F.StartLine:= C.CallSiteLine;
            F.EndLine  := C.CallSiteLine;
            F.StartCol := 1;
            F.EndCol   := 1;
            F.Severity := 'warning';
            F.Message  := 'Call chain ' + (if Caller.Id = 0 then '' else ShortQName(Caller.QualifiedName) + ' -> ') + Step.Chain +
              ' reaches a routine that ' + Why + ' ' + Where +
              ' -- there is no desktop to show it on, so the call blocks forever or fails.';
            AAcc.Add(F);
          end;
        if Next.Count = 0 then Break;
        Frontier.Clear;
        Frontier.AddRange(Next);
      end;
    end;
  finally
    Next.Free;
    Frontier.Free;
    Visited.Free;
    Lines.Free;
    Reported.Free;
    Emitted.Free;
    Services.Free;
  end;
end;

class function TApp2CrossUnit.Run(const AFilePaths: TArray<string>; const AProjectPath: string;
  const AProgramHasConsole: TProgramConsoleProbe; const AStore: ISymbolStore): TArray<TLintFinding>;
var
  Units: TDictionary<string, TApp2File>;
  ProgramPaths: TList<string>;
  Programs: TList<TApp2File>;
  Acc: TList<TLintFinding>;
  P, Text, ProjBase: string;
  Item: TApp2File;
begin
  Result:= nil;
  ProjBase:= if AProjectPath = '' then '' else UnitOf(AProjectPath);
  Units:= TDictionary<string, TApp2File>.Create;
  Programs:= TList<TApp2File>.Create;
  Acc:= TList<TLintFinding>.Create;
  ProgramPaths:= TList<string>.Create;
  try
    try
      for P in AFilePaths do
      begin
        if not (SameText(ExtractFileExt(P), '.pas') or SameText(ExtractFileExt(P), '.dpr')) then Continue;
        Text:= ReadAppSource(P);
        if Text = '' then Continue;
        Item.Path:= P;
        Item.Src := TAppSrc.Create(Text);
        if not SameText(ExtractFileExt(P), '.dpr') then
          Units.AddOrSetValue(UnitOf(P), Item)
        // 1.54.1 INT: the writeln-in-gui-app decision (directives, not raw text; DCC_ConsoleTarget via the probe)
        else if ((ProjBase = '') or (UnitOf(P) = ProjBase)) and (ProgramSrcHasConsole(Item.Src, '', '', '') or
          (Assigned(AProgramHasConsole) and AProgramHasConsole())) then
          Programs.Add(Item)
        else
          Item.Src.Free;
      end;
      for Item in Programs do CheckProgram(Item.Path, Item.Src, Units, Acc);
      for Item in Programs do ProgramPaths.Add(LowerCase(Item.Path));
      if AStore <> nil then FollowMethods(AStore, ProgramPaths, Acc);
      Result:= Acc.ToArray;
    finally
      for Item in Programs do Item.Src.Free;
      for Item in Units.Values do Item.Src.Free;
    end;
  finally
    ProgramPaths.Free;
    Acc.Free;
    Programs.Free;
    Units.Free;
  end;
end;

end.
