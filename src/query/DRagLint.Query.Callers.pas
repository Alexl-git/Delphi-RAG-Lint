unit DRagLint.Query.Callers;

{ Shared caller queries -- the ONE place resolved callers and name-matched
  callers are computed.

  WHY THIS UNIT EXISTS. The resolved-caller rules (call_edges plus the
  callback-reach rules below) lived inline inside DRagLint.CLI.DoQuery, so the
  only way to ask the question was to SPAWN drag-lint.exe. The IDE hover did
  exactly that -- twice per hover, each spawn re-opening indexes the already
  running LSP server had open and warm. Serving the hover over the LSP needed
  the same computation callable in-process, and duplicating it would have left
  two copies of the callback rules to drift apart. So it moved here, and the CLI
  now renders from these functions rather than owning them.

  The CLI's rendered output -- text and --json alike -- is unchanged by the
  move, which is what run_query_callers_shared_guard.ps1 pins. }

interface

uses
  System.SysUtils           ,
  System.Generics.Collections,
  DRagLint.Core.Model       ,
  DRagLint.Core.Interfaces  ;

type
  /// <summary>One caller row, in the shape both the CLI renderer and the LSP
  /// hoverBundle reply need.</summary>
  /// <remarks>FilePath is file-NAME-only for resolved and callback rows (the
  /// idempotency design the JSON contract already carries) and the FULL path
  /// for name-matched rows, because the hover popup navigates to them. Line is
  /// meaningful only when HasLine is True: a resolved row whose caller symbol
  /// id is unknown deliberately carries no line, and the JSON renderer must
  /// omit the pair rather than emit 0.</remarks>
  TQueryCallerRow = record
    CallerQName: string ;
    FilePath   : string ;
    Line       : Integer;
    HasLine    : Boolean;
    /// <summary>'certain' | 'ambiguous' (from call_edges) | 'callback' (a
    /// by-name reach; see ResolvedCallersForName's remarks).</summary>
    Confidence : string ;
    TargetQName: string ;
    /// <summary>True on the first row of each TARGET's caller run.</summary>
    /// <remarks>Grouping cannot be recovered from TargetQName alone: OVERLOADS
    /// are distinct target symbols that share one qualified name, and the CLI's
    /// text form prints a header per TARGET -- so `TFoo.Create:` appears twice
    /// for two overloads that both have callers. Deriving the header from "the
    /// name changed" would silently merge them into one group. Always False on
    /// callback rows, which the text form prints with no header at all.</remarks>
    FirstOfTarget: Boolean;
    /// <summary>The call site's own source line, already trimmed. Filled by
    /// NameCallersForName only; always empty for resolved rows.</summary>
    /// <remarks>A resolved row's text is NOT filled here on purpose: this
    /// function answers from the index alone, and the text a reader wants is
    /// the one in the editor's UNSAVED buffer. Only the LSP has that, so it
    /// renders the line itself from FullPath + CallSiteLine.</remarks>
    CodeText   : string ;
    /// <summary>FilePath, fully qualified. Filled for resolved and callback
    /// rows, where FilePath is filename-only by contract.</summary>
    /// <remarks>Equal to FilePath for name-matched rows, which already carry
    /// the full path.</remarks>
    FullPath   : string ;
    /// <summary>The line of the CALL ITSELF, as opposed to Line, which for a
    /// resolved row is the caller ROUTINE's start line.</summary>
    /// <remarks>Both are wanted and neither substitutes for the other. Line is
    /// routine-granular and is what the CLI has always printed -- changing it
    /// would move every golden. CallSiteLine is what a reader means by "called
    /// from": the exact statement. The index has carried it all along in
    /// TResolvedCaller.CallSiteLine and this layer was dropping it. 0 when
    /// unknown.</remarks>
    CallSiteLine: Integer;
    /// <summary>Id of the symbol whose body contains this reference; 0 at unit
    /// level. Filled by NameCallersForName only.</summary>
    /// <remarks>The scoping key for a PARAMETER or LOCAL, which cannot be
    /// referenced outside the routine that declares it. Without it a usage list
    /// gathered by bare name sweeps in every same-named parameter in the index
    /// -- reported 2026-08-19 for two constructors that both take `btn`.
    /// Ids are per-DATABASE, so it is only meaningful against the store the row
    /// came from.</remarks>
    EnclosingSymbolId: Int64;
  end;

  TQueryCallerRows = TArray<TQueryCallerRow>;

/// <summary>Precise callers of every symbol matching <paramref name="AName"/>
/// in one store, keyed by resolved call edges rather than by name.</summary>
/// <param name="AStore">An open store; must not be nil.</param>
/// <param name="AName">Bare or qualified callee name, matched exactly.</param>
/// <returns>Rows in the CLI's historical emission order: all resolved callers
/// grouped per matching target, then the callback reaches. Empty when nothing
/// matches.</returns>
/// <remarks>
/// <para>CALLBACK REACHES. A routine handed somewhere BY NAME --
/// <c>Register(Pred)</c>, <c>@Handler</c>, <c>OnFoo := Handler</c> -- is
/// reached from that site but is not CALLED there, so the indexer records a
/// refs.kind='read' row and no call_edges row. Without reporting those, the
/// query that is documented as the PRECISE one answers 0 for a live predicate
/// while the plain name path answers 1, and the honest reading of that 0 is
/// "dead code".</para>
/// <para>call_edges is deliberately NOT widened to carry these. An edge there
/// means a call, with a call site and arguments; inventing one would make
/// callgraph, impact and call-path assert control flow that does not exist at
/// that line. So the reach is reported here and marked 'callback', where it can
/// never be mistaken for a call.</para>
/// <para>A CALL AT THE SAME SITE means the read is part of an ordinary
/// invocation, not a callback pass. <c>Self.Run</c> emits THREE refs at one
/// line -- 'call', 'member-access', and a 'read' whose receiver is NULL -- so
/// neither kind nor receiver alone can tell it from <c>Register(Pred)</c>. The
/// position can: a genuine callback has no call of the SAME NAME at its own
/// line. An earlier attempt filtered on receiver_text and let Self.Run through,
/// because that ref's receiver is NULL.</para>
/// <para>Still name-keyed, so a local variable sharing a routine's name can
/// produce a spurious row; the 'callback' marker is what keeps that honest.</para>
/// </remarks>
function ResolvedCallersForName(const AStore: ISymbolStore; const AName: string): TQueryCallerRows;

/// <summary>Name-matched callers of <paramref name="AName"/> in one store,
/// each carrying its own source line.</summary>
/// <param name="AStore">An open store; must not be nil.</param>
/// <param name="AName">Callee name, matched exactly (kind-blind).</param>
/// <param name="AContextLines">Context radius to read; 1 is enough to recover
/// the call site's own line, which is all CodeText needs.</param>
/// <returns>One row per reference, FilePath fully qualified, CodeText set to
/// the call site's own trimmed source line (empty when the file could not be
/// read). Confidence and TargetQName are empty: a name match asserts neither.</returns>
/// <remarks>Kind-blind by design -- this is the wide net the resolved query is
/// checked against, not a claim that each row is a call.</remarks>
function NameCallersForName(const AStore: ISymbolStore; const AName: string; AContextLines: Integer = 1): TQueryCallerRows;

implementation

uses
  System.Classes,
  System.StrUtils;

{ Pull the call site's OWN line out of the indexed context blob.
  FindCallersByNameWithContext formats each line as '%5d: %s', so after Trim the
  wanted line starts with '<StartLine>:'. Reading the file again here instead
  would be a second source of truth and would disagree with the index whenever
  the file has moved on. }
function CodeLineFromContext(const AContextText: string; ALine: Integer): string;
var
  Lines  : TArray<string>;
  L      : string        ;
  Trimmed: string        ;
  Prefix : string        ;
begin
  Result:= '';
  if (AContextText = '') or (ALine <= 0) then Exit;
  Prefix:= IntToStr(ALine) + ':';
  Lines := AContextText.Split([#10]);
  for L in Lines do
  begin
    Trimmed:= Trim(L);
    if Pos(Prefix, Trimmed) = 1 then Exit(Trim(Copy(Trimmed, Length(Prefix) + 1, MaxInt)));
  end;
end;

function ResolvedCallersForName(const AStore: ISymbolStore; const AName: string): TQueryCallerRows;
var
  Targets     : TArray<TSymbol>;
  Row         : TQueryCallerRow;
  NameIsRoutine: Boolean       ;
begin
  SetLength(Result, 0);
  if (AStore = nil) or (Trim(AName) = '') then Exit;

  Targets:= AStore.FindSymbolsByExactName(AName);

  for var T in Targets do
  begin
    var RCallers:= AStore.FindResolvedCallers(T.Id);
    var First: Boolean:= True;
    for var RC in RCallers do
    begin
      Row:= Default(TQueryCallerRow);
      Row.FirstOfTarget:= First;
      First:= False;
      Row.CallerQName := RC.EnclosingQName;
      Row.FilePath    := RC.Location      ;  { file name only, by contract }
      Row.FullPath    := RC.FullPath      ;  { ...and the openable one beside it }
      Row.CallSiteLine:= RC.CallSiteLine  ;
      Row.Confidence  := RC.Confidence    ;
      Row.TargetQName := T.QualifiedName  ;
      { The line is the caller SYMBOL's own start line (routine-granular, not
        the exact call-site line) -- unchanged from the CLI, whose JSON omits
        the pair entirely when the enclosing symbol is unknown. }
      if RC.EnclosingSymbolId > 0 then
      begin
        Row.Line   := AStore.GetSymbolById(RC.EnclosingSymbolId).StartLine;
        Row.HasLine:= True;
      end;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)]:= Row;
    end; // for RC
  end; // for T

  { Callback reaches -- only when the name denotes a ROUTINE. A 'read' of a
    variable that merely shares a class's or field's name is not a callback. }
  NameIsRoutine:= False;
  for var T in Targets do
    if T.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor] then
    begin
      NameIsRoutine:= True;
      Break;
    end;
  if not NameIsRoutine then Exit;

  var CallSites: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    var AllRefs:= AStore.FindCallersByName(AName);
    for var PosRef in AllRefs do
      if (PosRef.Kind = 'call') or (PosRef.Kind = 'member-access') then
        CallSites.AddOrSetValue(Format('%d:%d', [PosRef.FileId, PosRef.StartLine]), True);

    for var CbRef in AllRefs do
    begin
      if CbRef.Kind <> 'read' then Continue;
      if CallSites.ContainsKey(Format('%d:%d', [CbRef.FileId, CbRef.StartLine])) then Continue;

      var CbWhere: string:= AStore.GetFilePath(CbRef.FileId);
      var CbWho  : string:= '';
      if CbRef.EnclosingSymbolId > 0 then
        CbWho:= AStore.GetSymbolById(CbRef.EnclosingSymbolId).QualifiedName;
      if CbWho = '' then CbWho:= '(unit level)';

      Row:= Default(TQueryCallerRow);
      Row.CallerQName := CbWho                    ;
      Row.FilePath    := ExtractFileName(CbWhere) ;
      Row.FullPath    := CbWhere                  ;
      Row.Line        := CbRef.StartLine          ;
      Row.CallSiteLine:= CbRef.StartLine          ;
      Row.HasLine     := True                     ;
      Row.Confidence := 'callback'               ;
      Row.TargetQName:= AName                    ;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)]:= Row;
    end; // for CbRef
  finally
    CallSites.Free;
  end; // try
end; // function

function NameCallersForName(const AStore: ISymbolStore; const AName: string; AContextLines: Integer): TQueryCallerRows;
var
  Refs: TArray<TReference>;
  Row : TQueryCallerRow   ;
  i   : Integer           ;
begin
  SetLength(Result, 0);
  if (AStore = nil) or (Trim(AName) = '') then Exit;
  if AContextLines < 1 then AContextLines:= 1;

  Refs:= AStore.FindCallersByNameWithContext(AName, AContextLines);
  SetLength(Result, Length(Refs));
  for i:= Low(Refs) to High(Refs) do
  begin
    Row:= Default(TQueryCallerRow);
    Row.CallerQName:= '';
    Row.FilePath   := AStore.GetFilePath(Refs[i].FileId);
    Row.FullPath   := Row.FilePath;
    Row.Line       := Refs[i].StartLine;
    Row.CallSiteLine:= Refs[i].StartLine;
    Row.HasLine    := Refs[i].StartLine > 0;
    Row.Confidence := '';
    Row.TargetQName:= '';
    Row.CodeText   := CodeLineFromContext(Refs[i].ContextText, Refs[i].StartLine);
    Row.EnclosingSymbolId:= Refs[i].EnclosingSymbolId;
    Result[i]:= Row;
  end;
end; // function

end.
