unit DRagLint.Resolver.TypeAt;

interface

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils
  , System.Classes
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoTypeAt (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems (DRagLint.LSP.Completion.pas), DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp (DRagLint.LSP.Completion.pas), declaration (DRagLint.Resolver.TypeAt.pas), DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve/4 (DRagLint.Resolver.TypeAt.pas) (+2 more)
  /// Used in units: DRagLint.CLI, DRagLint.LSP.Completion, DRagLint.Resolver.TypeAt
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTypeAtResult = record
    FileName   : string    ;
    Line       : Integer   ;
    Col        : Integer   ;
    Token      : string    ;
    Containing : TSymbol   ;
    HasContain : Boolean   ;
    Resolved   : TSymbol   ;
    HasResolved: Boolean   ;
    Doc        : TParsedDoc;
    HasDoc     : Boolean   ;
    Note       : string    ;
    OwnerTypeFallback : Boolean;   // True only when the LHS type resolved but the member was NOT found on it or any base
    ResolvedStoreIndex: Integer;   // index into the AStores array the Resolved symbol came from; -1 if none
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoTypeAt (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems (DRagLint.LSP.Completion.pas), DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp (DRagLint.LSP.Completion.pas), DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)
  /// Used in units: DRagLint.CLI, DRagLint.LSP.Completion, DRagLint.LSP.Server, DRagLint.MCP.Server
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTypeAtResolver = class
    public
      /// <summary>Resolves the symbol referenced at a file position, searching
      /// every supplied store so a type or member declared in a different DB
      /// (e.g. a generic base in a platform-library index) can be resolved.</summary>
      /// <param name="AStores">All open stores. The store that OWNS AFile is the
      /// primary (file-scoped lookups use it); the rest are searched only for
      /// type / member resolution. Must not be empty.</param>
      /// <param name="AFile">Absolute path of the hovered source file.</param>
      /// <param name="ALine">1-based line.</param>
      /// <param name="ACol">1-based column.</param>
      /// <returns>The resolution result. OwnerTypeFallback is True when the LHS
      /// type resolved but the member could not be found on it or any base;
      /// ResolvedStoreIndex names the store the resolved symbol came from.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoTypeAt (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems (DRagLint.LSP.Completion.pas), DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp (DRagLint.LSP.Completion.pas), DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas) (+2 more)
      /// Calls: DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName, DRagLint.Core.Interfaces.ISymbolStore.FindContainingSymbol, DRagLint.Core.Interfaces.ISymbolStore.FindEnclosingRoutineByImpl, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Resolver.TypeAt.FindGenericBaseAnywhere, DRagLint.Resolver.TypeAt.FindTypeAnywhere, DRagLint.Resolver.TypeAt.InferLocalVarType, DRagLint.Resolver.TypeAt.ParseGenericBase, DRagLint.Resolver.TypeAt.ResolveMemberOnType, DRagLint.Resolver.TypeAt.StoreIndexOf, DRagLint.Resolver.TypeAt.TTypeAtResolver.ExtractTokenAt, DRagLint.Resolver.TypeAt.TypeIdentOfSignature, FillChar, Format
      /// Overload 1 of 2
      /// Complexity: 37 (cyclomatic, outer body), 193 lines (full implementation)
      /// Touches: file system
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindContainingSymbol"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindEnclosingRoutineByImpl"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.FindGenericBaseAnywhere"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Resolve(const AStores: TArray<ISymbolStore>; const AFile: string; ALine, ACol: Integer)         : TTypeAtResult; overload;
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->Observed:
      /// Resolve(TArray&lt;ISymbolStore&gt;.Create(AStore), AFile, ALine, ACol).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve/4
      /// Overload 2 of 2
      /// Pure
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.ExtractTokenAt"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.RenderJson"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.RenderText"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Resolve(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer)                  : TTypeAtResult; overload;
      /// <param name="ALine"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="APrecedingDot"><!-- drag-lint:auto type -->out Boolean</param>
      /// <param name="ALhs"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->Observed: ''; Copy(ALine, Start, EndIdx -
      /// Start).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve/4 (DRagLint.Resolver.TypeAt.pas)
      /// Calls: CharInSet, Copy
      /// Complexity: 12 (cyclomatic, outer body), 30 lines (full implementation)
      /// Mutates: APrecedingDot (out), ALhs (out)
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.RenderJson"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.RenderText"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function ExtractTokenAt(const ALine: string; ACol: Integer; out APrecedingDot: Boolean; out ALhs: string): string       ;
      /// <param name="AResult"><!-- drag-lint:auto type -->const TTypeAtResult</param>
      /// <returns><!-- drag-lint:auto -->Observed: SB.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoTypeAt (DRagLint.CLI.pas)
      /// Calls: DRagLint.Doc.Regions.TDocRegions.StripForDisplay, Format
      /// Pure
      /// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.ExtractTokenAt"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.RenderJson"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderText(const AResult: TTypeAtResult)                                                        : string       ;
      /// <param name="AResult"><!-- drag-lint:auto type -->const TTypeAtResult</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoTypeAt (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)
      /// Calls: Format, StringReplace
      /// Pure
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.ExtractTokenAt"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.RenderText"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderJson(const AResult: TTypeAtResult)                                                        : string       ;

      /// <summary>The TYPE whose members belong after a '.' at this position.</summary>
      /// <param name="AStores">Every open index, in priority order (the file's own
      /// project index first). The declaring type is frequently in a DIFFERENT
      /// database from the variable -- a project-local var of an RTL/VCL class is
      /// the common case -- so this must be the full set, never one store.</param>
      /// <param name="ALhsEndCol">1-based column of the LAST character of the LHS
      /// expression, i.e. the character immediately before the dot.</param>
      /// <param name="AStore">out: the store the returned type came from. Symbol
      /// ids are per-database, so every follow-up child/ancestor lookup MUST use
      /// this store and not AStores[0].</param>
      /// <returns>The class/record/interface to list members of, or a zeroed
      /// symbol (Id = 0) when the LHS type could not be established.</returns>
      /// <remarks>Split out of Resolve so completion stops at the TYPE instead of
      /// continuing to a named member. Resolve answers "what is the symbol at this
      /// position" -- for `AExceptionInfo.` that is the PARAMETER (skParam), which
      /// is why a caller testing Resolved.Kind for a class kind always got nothing.
      /// The cascade here is the one Resolve already applies internally: direct
      /// type, else the declared type from Signature, else source-scan inference
      /// for a local, else generic-base unwrap.</remarks>
      class function ResolveMemberScope(const AStores: TArray<ISymbolStore>; const AFile: string;
        ALine, ALhsEndCol: Integer; out AStore: ISymbolStore): TSymbol;

      /// <summary>Every member of a type that a completion list should offer:
      /// its own children plus those of each transitive ancestor.</summary>
      /// <param name="AStore">The store the type came from; ids are per-database.</param>
      /// <returns>Members, nearest declaration first, de-duplicated by name so an
      /// override is offered once rather than once per level of the hierarchy.</returns>
      class function CollectMembers(const AStore: ISymbolStore; ATypeId: Int64): TArray<TSymbol>;
  end;

implementation

uses
  DRagLint.Doc.Regions
  , DRagLint.Core.LiveDocs  { v(live-buffer): unsaved editor text, consulted before disk }
  ;

class function TTypeAtResolver.ExtractTokenAt(const ALine: string; ACol: Integer; out APrecedingDot: Boolean; out ALhs: string): string;
var
  I     : Integer;
  Start : Integer;
  EndIdx: Integer;
begin
  Result       := '';
  APrecedingDot:= False;
  ALhs         := '';
  if (ACol < 1) or (ACol > Length(ALine)) then Exit;

  // Walk left to find token start
  Start:= ACol;
  while (Start > 1) and CharInSet(ALine[Start - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Dec(Start);

  // Walk right to find token end
  EndIdx:= ACol;
  while (EndIdx <= Length(ALine)) and CharInSet(ALine[EndIdx], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(EndIdx);

  if EndIdx > Start then Result:= Copy(ALine, Start, EndIdx - Start);

  // Check char immediately before token start
  if (Start > 1) and (ALine[Start - 1] = '.') then
  begin
    APrecedingDot:= True;
    // Walk further left to extract LHS (allow dots so Foo.Bar.Baz works)
    I:= Start - 2;
    while (I >= 1) and CharInSet(ALine[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Dec(I);
    ALhs:= Copy(ALine, I + 1, Start - 2 - I);
  end;
end; // function

function WholeWordPresent(const AText, AWord: string): Boolean;
{ True if AWord appears in AText as a whole identifier (case-insensitive). }
var
  LowerT  : string ;
  LowerW  : string ;
  P       : Integer;
  AfterIdx: Integer;
  BeforeOk: Boolean;
  AfterOk : Boolean;
begin
  Result:= False;
  if AWord = '' then Exit;
  LowerT:= LowerCase(AText);
  LowerW:= LowerCase(AWord);
  P:= Pos(LowerW, LowerT);
  while P > 0 do
  begin
    BeforeOk:= (P = 1) or not CharInSet(LowerT[P - 1], ['a'..'z', '0'..'9', '_']);
    AfterIdx:= P + Length(LowerW);
    AfterOk:= (AfterIdx > Length(LowerT)) or not CharInSet(LowerT[AfterIdx], ['a'..'z', '0'..'9', '_']);
    if BeforeOk and AfterOk then Exit(True);
    P:= Pos(LowerW, LowerT, P + 1);
  end;
end; // function

function ExtractDeclType(const ALine, AVarName: string): string;
{ If ALine declares AVarName ("<names>: <Type>" or a param "(...AVarName: Type")
  return <Type>'s first identifier; '' otherwise. Skips ':=' assignments. }
var
  P    : Integer;
  Q    : Integer;
  Left : string ;
  Right: string ;
begin
  Result:= '';
  P:= Pos(':', ALine);
  if P = 0 then Exit;
  if (P < Length(ALine)) and (ALine[P + 1] = '=') then Exit; { ':=' assignment }
  Left:= Copy(ALine, 1, P - 1);
  if not WholeWordPresent(Left, AVarName) then Exit;
  Right:= TrimLeft(Copy(ALine, P + 1, MaxInt));
  Q:= 1;
  while (Q <= Length(Right)) and CharInSet(Right[Q], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(Q);
  if Q > 1 then Result:= Copy(Right, 1, Q - 1);
end;

function InferLocalVarType(const ALines: TArray<string>; ACursorIdx0: Integer; const AVarName: string): string;
{ v0.46: resolve a LOCAL variable / parameter's declared type by scanning UP
  from the cursor for "AVarName: Type" within the enclosing routine. Stops at
  the routine header (also checking its parameter list). The v0.19 resolver did
  not infer locals -- this is what lets hover narrow member access on a local
  (e.g. AButton.GroupIndex with AButton: TdxBarButton). }
var
  I    : Integer;
  Lower: string ;
begin
  Result:= '';
  I     := ACursorIdx0;
  if (I < 0) or (I > High(ALines)) then Exit;
  while I >= 0 do
  begin
    Lower:= LowerCase(TrimLeft(ALines[I]));
    if (Pos('procedure ', Lower) = 1) or (Pos('function ', Lower) = 1) or (Pos('constructor ', Lower) = 1) or (Pos('destructor ', Lower) = 1) then
    begin
      { routine header -- params may declare it; then stop (boundary). }
      Result:= ExtractDeclType(ALines[I], AVarName);
      Exit;
    end;
    Result:= ExtractDeclType(ALines[I], AVarName);
    if Result <> '' then Exit;
    Dec(I);
    if ACursorIdx0 - I > 400 then Break; { safety }
  end;
end; // function

function StoreIndexOf(const AStores: TArray<ISymbolStore>; const AStore: ISymbolStore): Integer;
{ Index of AStore within AStores by reference; -1 if not present or nil. }
var
  I: Integer;
begin
  Result:= -1;
  if AStore = nil then Exit;
  for I:= 0 to High(AStores) do
    if AStores[I] = AStore then Exit(I);
end;

function TypeIdentOfSignature(const ASig: string): string;
{ The leading type identifier of a VALUE symbol's signature (a var/param/field's
  declared type). Strips a leading ':', trims, then takes the run of identifier
  chars (keeps dots so 'System.TObject' stays whole; stops at space, ';', '<').
  'TThingList' -> 'TThingList'; ': TFoo;' -> 'TFoo'; 'TMyList<TThing>' -> 'TMyList'. }
var
  S: string ;
  I: Integer;
begin
  Result:= '';
  S:= Trim(ASig);
  if (S <> '') and (S[1] = ':') then S:= TrimLeft(Copy(S, 2, MaxInt));
  I:= 1;
  while (I <= Length(S)) and CharInSet(S[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Inc(I);
  if I > 1 then Result:= Copy(S, 1, I - 1);
end;

function FindTypeAnywhere(const AStores: TArray<ISymbolStore>; const AName: string; out AStore: ISymbolStore): TSymbol;
{ First store (in order) whose flat name lookup finds AName; returns that store
  in AStore so subsequent child/ancestor lookups use the right DB. Id=0 if none. }
var
  I  : Integer;
  Sym: TSymbol;
begin
  FillChar(Result, SizeOf(Result), 0);
  AStore:= nil;
  for I:= 0 to High(AStores) do
  begin
    Sym:= AStores[I].FindSymbolByExactNameAnywhere(AName);
    if Sym.Id > 0 then
    begin
      AStore:= AStores[I];
      Exit(Sym);
    end;
  end;
end;

{ The declaring unit of a qualified symbol name: 'Vcl.ExtCtrls.TTimer' ->
  'Vcl.ExtCtrls'. Empty when the name carries no unit prefix. }
function UnitOfQName(const AQName: string): string;
var
  DotPos: Integer;
begin
  Result:= '';
  DotPos:= LastDelimiter('.', AQName);
  if DotPos > 1 then Result:= Copy(AQName, 1, DotPos - 1);
end;

{ Does AQName's declaring unit appear in AUsedUnits? }
function DeclaredInAUsedUnit(const AQName: string; const AUsedUnits: TArray<string>): Boolean;
var
  U, Used: string;
begin
  Result:= False;
  U:= UnitOfQName(AQName);
  if U = '' then Exit;
  for Used in AUsedUnits do
    if SameText(Used, U) then Exit(True);
end;

{ The GUI framework a qualified name belongs to -- 'Vcl', 'FMX', or '' for
  everything else. Only these two matter: they are the pair that declares the
  same control names twice. }
function GuiNamespaceOf(const AQName: string): string;
var
  DotPos: Integer;
  Seg   : string ;
begin
  Result:= '';
  DotPos:= Pos('.', AQName);
  if DotPos <= 1 then Exit;
  Seg:= Copy(AQName, 1, DotPos - 1);
  if SameText(Seg, 'Vcl') or SameText(Seg, 'FMX') then Result:= Seg;
end;

{ A candidate from the framework the project does NOT use is not a worse
  answer -- it is not an answer at all, because a Delphi project is VCL or FMX,
  not both. AFramework is '' when the project genuinely does not say, and then
  nothing is excluded. }
function IsWrongFramework(const AQName, AFramework: string): Boolean;
var
  Ns: string;
begin
  Result:= False;
  if AFramework = '' then Exit;
  Ns:= GuiNamespaceOf(AQName);
  Result:= (Ns <> '') and not SameText(Ns, AFramework);
end;

function FindTypeWithMembersAnywhere(const AStores: TArray<ISymbolStore>; const AName: string;
  out AStore: ISymbolStore; const AUsedUnits: TArray<string> = nil;
  const AFramework: string = ''): TSymbol;
{ Like FindTypeAnywhere, but does not settle for the FIRST symbol carrying the
  name -- it prefers one that actually has members.

  WHY THIS EXISTS. A type name is rarely unique across a large index. The case
  that exposed it: 'TEurekaExceptionInfo' matches THIRTEEN symbols in the
  library index -- EAppCGI, EAppDataSnap, EAppISAPI, EDialogCGI ... all
  member-less re-declarations -- plus two aliases, plus the one real class,
  EException.TEurekaExceptionInfo, which is the only one with members. Taking
  the first match returned a member-less shell, so member completion produced
  an EMPTY list while looking, from the outside, exactly like "the type could
  not be resolved".

  An alias is followed once to its target before being judged, so
  'TFoo = Other.TFoo' resolves to the real declaration rather than being
  discarded for having no children of its own.

  v1.7: AUsedUnits NARROWS THE HEURISTIC WITH THE ONE FACT THAT DECIDES IT.

  Reported 2026-08-19: hovering `FRetryTimer.Enabled` in a VCL unit answered
  `FMX.Types.TTimer.Enabled`. Both frameworks declare TTimer, both have
  members, and FMX sorts first -- so "the first candidate with members" picked
  the framework the file does not use, and said so confidently. Following the
  declaration was correct (`FRetryTimer: TTimer` reported VCL); only the member
  lookup went wrong, which is the worst shape: the answer looks authoritative
  and names a real type.

  So when the caller can say which units the hovering FILE actually uses, a
  candidate declared in one of them wins outright. That is not full Delphi
  scope resolution -- it does not follow the uses graph transitively, and it
  cannot rank two used units that both declare the name -- but it settles the
  VCL/FMX case, which is the one that occurs, from a fact already in the index.

  LIMITATION, STILL STATED PLAINLY: with no AUsedUnits, or when no candidate is
  declared in a used unit, this falls back to the old rule -- the first
  candidate with members, in store priority order. Right for
  project-before-library, wrong for a genuine cross-unit name clash. }
var
  I, J     : Integer      ;
  Cands    : TArray<TSymbol>;
  Sym      : TSymbol      ;
  Best     : TSymbol      ;
  BestStore: ISymbolStore ;
  Target   : string       ;
  Alias    : TSymbol      ;
  AliasStore: ISymbolStore;
  WithMembers     : TSymbol     ;
  WithMembersStore: ISymbolStore;
begin
  FillChar(Result     , SizeOf(Result     ), 0);
  FillChar(Best       , SizeOf(Best       ), 0);
  FillChar(WithMembers, SizeOf(WithMembers), 0);
  AStore:= nil;
  BestStore:= nil;
  WithMembersStore:= nil;
  if AName = '' then Exit;

  for I:= 0 to High(AStores) do
  begin
    if AStores[I] = nil then Continue;
    Cands:= AStores[I].FindSymbolsByExactName(AName);
    for J:= 0 to High(Cands) do
    begin
      Sym:= Cands[J];
      if not (Sym.Kind in [skClass, skRecord, skInterface, skTypeAlias]) then Continue;

      { The project's framework excludes the other one OUTRIGHT. Delphi does not
        mix VCL and FMX in one project, so an FMX.* candidate in a VCL project
        is not a lower-ranked answer -- it is not a candidate. Dropping it here
        also fixes the cases the uses-clause rule cannot see, where the type
        arrives through a form or an ancestor rather than a direct `uses`. }
      if IsWrongFramework(Sym.QualifiedName, AFramework) then Continue;

      { Follow an alias to its target once -- the alias itself has no members. }
      if (Sym.Kind = skTypeAlias) and (Sym.Signature <> '') then
      begin
        Target:= TypeIdentOfSignature(Sym.Signature);
        { Strip a unit qualifier: 'EException.TEurekaExceptionInfo' -> the last
          dotted part is the type name the flat lookup indexes. }
        if Target <> '' then
        begin
          var DotPos: Integer:= LastDelimiter('.', Target);
          if DotPos > 0 then Target:= Copy(Target, DotPos + 1, MaxInt);
        end;
        if (Target <> '') and not SameText(Target, AName) then
        begin
          Alias:= FindTypeAnywhere(AStores, Target, AliasStore);
          if (Alias.Id > 0) and (AliasStore <> nil) and (Length(AliasStore.FindAllChildSymbols(Alias.Id)) > 0) then
          begin
            AStore:= AliasStore;
            Exit(Alias);
          end;
        end;
      end;

      if Best.Id <= 0 then begin Best:= Sym; BestStore:= AStores[I]; end;
      if Length(AStores[I].FindAllChildSymbols(Sym.Id)) > 0 then
      begin
        { Declared in a unit this file actually uses -> decided, stop looking. }
        if DeclaredInAUsedUnit(Sym.QualifiedName, AUsedUnits) then
        begin
          AStore:= AStores[I];
          Exit(Sym);
        end;
        { Otherwise remember the first with members and keep scanning, in case a
          later candidate IS in a used unit. Without this second pass the
          FMX/VCL case cannot be fixed at all: FMX is found first and would
          return immediately. }
        if WithMembers.Id <= 0 then
        begin
          WithMembers     := Sym;
          WithMembersStore:= AStores[I];
        end;
      end;
    end;
  end;

  { No candidate sat in a used unit. Fall back to the old rule -- first with
    members -- then to any plausible candidate, so callers can still report the
    type name rather than nothing at all. }
  if WithMembers.Id > 0 then
  begin
    Result:= WithMembers;
    AStore:= WithMembersStore;
    Exit;
  end;
  Result:= Best;
  AStore:= BestStore;
end;

function ResolveMemberOnType(const AStore: ISymbolStore; ATypeId: Int64; const AMember: string): TSymbol;
{ The member AMember on the type ATypeId: a direct child first, then each
  transitive ancestor (same store -- ids are per-DB). Id=0 if not found. }
var
  Anc: TArray<TTypeAncestor>;
  I  : Integer;
begin
  Result:= AStore.FindChildSymbolByName(ATypeId, AMember);
  if Result.Id > 0 then Exit;
  Anc:= AStore.GetTransitiveAncestors(ATypeId);
  for I:= 0 to High(Anc) do
  begin
    if Anc[I].SymbolId <= 0 then Continue;   // unresolved ancestor edge (e.g. an unindexed alias)
    Result:= AStore.FindChildSymbolByName(Anc[I].SymbolId, AMember);
    if Result.Id > 0 then Exit;
  end;
  FillChar(Result, SizeOf(Result), 0);
end;

function ParseGenericBase(const ASig: string; out ABaseName: string; out AArity: Integer): Boolean;
{ 'TList<TToken>' -> ('TList', 1); 'TDictionary<TKey, TList<T>>' -> ('TDictionary', 2).
  AArity = 1 + count of TOP-LEVEL commas inside the OUTERMOST <...>. False when no '<'. }
var
  I, Depth, Lt: Integer;
begin
  Result:= False;
  ABaseName:= '';
  AArity:= 0;
  Lt:= System.Pos('<', ASig);
  if Lt <= 1 then Exit;
  ABaseName:= Trim(Copy(ASig, 1, Lt - 1));
  if ABaseName = '' then Exit;
  AArity:= 1;
  Depth:= 0;
  for I:= Lt to Length(ASig) do
  begin
    case ASig[I] of
      '<': Inc(Depth);
      '>': begin Dec(Depth); if Depth = 0 then Break; end;
      ',': if Depth = 1 then Inc(AArity);
    end;
  end;
  Result:= True;
end;

function GenericArityOfName(const AName: string): Integer;
{ Arity of a symbol NAME like 'TList<T>' or 'TDictionary<TKey, TValue>'; 0 if non-generic. }
var
  Dummy: string;
begin
  if not ParseGenericBase(AName, Dummy, Result) then Result:= 0;
end;

function FindGenericBaseAnywhere(const AStores: TArray<ISymbolStore>; const ABaseName: string; AArity: Integer; out AStore: ISymbolStore): TSymbol;
{ A class/interface named ABaseName + '<...>' with matching generic arity, searched
  across all stores. Prefer a System.* (RTL) qname on ambiguity, else first in store
  order. Id=0 if none. }
var
  I, J     : Integer            ;
  Cands    : TArray<TSymbol>    ;
  HaveBest : Boolean            ;
begin
  FillChar(Result, SizeOf(Result), 0);
  AStore:= nil;
  HaveBest:= False;
  for I:= 0 to High(AStores) do
  begin
    Cands:= AStores[I].FindSymbolsByPrefix(ABaseName + '<', 200);
    for J:= 0 to High(Cands) do
    begin
      if not (Cands[J].Kind in [skClass, skInterface]) then Continue;
      if GenericArityOfName(Cands[J].Name) <> AArity then Continue;
      if not HaveBest then
      begin
        Result:= Cands[J];
        AStore:= AStores[I];
        HaveBest:= True;
      end
      else if (not StartsText('System.', Result.QualifiedName)) and StartsText('System.', Cands[J].QualifiedName) then
      begin
        { RTL-preferred disambiguation (best-effort; exact uses-based = D5). }
        Result:= Cands[J];
        AStore:= AStores[I];
      end;
    end;
  end;
end;

class function TTypeAtResolver.Resolve(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer): TTypeAtResult;
begin
  Result:= Resolve(TArray<ISymbolStore>.Create(AStore), AFile, ALine, ACol);
end;

class function TTypeAtResolver.Resolve(const AStores: TArray<ISymbolStore>; const AFile: string; ALine, ACol: Integer): TTypeAtResult;
var
  Lines       : TArray<string>;
  LineText    : string        ;
  PrecedingDot: Boolean       ;
  LhsText     : string        ;
  FileId      : Int64         ;
  LhsSym      : TSymbol       ;
  ResolvedSym : TSymbol       ;
  Primary     : ISymbolStore  ;
  LhsStore    : ISymbolStore  ;
  UsedUnits   : TArray<string>;
  Framework   : string        ;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.FileName        := AFile;
  Result.Line            := ALine;
  Result.Col             := ACol;
  Result.Note            := '';
  Result.ResolvedStoreIndex:= -1;

  if Length(AStores) = 0 then begin Result.Note:= 'no store.'; Exit; end;
  { Primary = the store that OWNS the hovered file (its file-scoped lookups --
    containing symbol, local-var inference -- must use that DB); default AStores[0]. }
  Primary:= AStores[0];
  for var si:= 0 to High(AStores) do
    if AStores[si].FindFileIdByPath(AFile) > 0 then begin Primary:= AStores[si]; Break; end;

  { v(live-buffer): resolve against the client's buffer when it has one. The
    declaration this scans for (`var Foo: TBar;`) is frequently typed in the
    same edit as the member access being resolved. }
  if not TLiveDocuments.Readable(AFile) then
  begin
    Result.Note:= 'File not found.';
    Exit;
  end;
  Lines:= TLiveDocuments.ReadLines(AFile);
  if (ALine < 1) or (ALine > Length(Lines)) then
  begin
    Result.Note:= 'Line out of range.';
    Exit;
  end;
  LineText:= Lines[ALine - 1];
  Result.Token:= ExtractTokenAt(LineText, ACol, PrecedingDot, LhsText);

  FileId:= Primary.FindFileIdByPath(AFile);

  { v1.7: the units this file actually USES -- the fact that decides VCL vs FMX
    when both declare the same type name. Read once here rather than per
    candidate; empty when the file is not indexed, in which case the type
    lookup falls back to its old behaviour. }
  UsedUnits:= nil;
  if FileId > 0 then
    for var UU in Primary.GetUnitUsesForFile(FileId) do
      if UU.UnitName <> '' then UsedUnits:= UsedUnits + [UU.UnitName];

  { v1.7: the PROJECT's framework, asked of the project store only. A library
    index carries Vcl.* and FMX.* alike by construction, so its answer describes
    the RTL rather than any consumer -- GuiFrameworkInUse says so itself, and
    returns '' on a tie rather than inventing a winner. Primary is the store
    that owns the hovered file, which is the project index whenever the file is
    indexed at all. }
  Framework:= '';
  if (Primary <> nil) and (FileId > 0) then
    try
      Framework:= Primary.GuiFrameworkInUse;
    except
      on E: Exception do Framework:= '';   { never let a preference query break hover }
    end;

  if FileId > 0 then
  begin
    Result.Containing:= Primary.FindContainingSymbol(FileId, ALine);
    Result.HasContain:= Result.Containing.Id > 0;
  end;

  if Result.Token = '' then
  begin
    Result.Note:= 'No identifier at position.';
    Exit;
  end;

  if PrecedingDot and (LhsText <> '') then
  begin
    LhsSym:= FindTypeAnywhere(AStores, LhsText, LhsStore);
    { The member-access LHS is a VALUE (local/param/field/var), not a type: e.g.
      `ATokens.Count` where ATokens: TThingList. Replace the value symbol with its
      declared TYPE (from its signature) so the member lookup runs against the type.
      If the type name does not resolve, LhsSym becomes empty and the source-scan
      inference below takes over. A direct type LHS (`TFoo.Bar`) skips this. }
    if (LhsSym.Id > 0) and not (LhsSym.Kind in [skClass, skRecord, skInterface, skTypeAlias]) then
    begin
      var VT: string:= TypeIdentOfSignature(LhsSym.Signature);
      var TS: TSymbol;
      FillChar(TS, SizeOf(TS), 0);
      { ...WithMembers: a bare first-match lookup lands on whichever
        same-named symbol the index happens to return first, and for a widely
        re-declared name that is usually a member-less shell -- which then makes
        every member lookup fall through to the owner-type floor and report
        "member may be inherited" for members that are right there on the real
        class. }
      if VT <> '' then TS:= FindTypeWithMembersAnywhere(AStores, VT, LhsStore, UsedUnits, Framework);
      LhsSym:= TS;
    end;
    { v0.46: LHS not a global symbol -> infer it as a local var/param and
      resolve its declared TYPE, so member access on a local narrows. }
    if LhsSym.Id <= 0 then
    begin
      var InferredType: string:= InferLocalVarType(Lines, ALine - 1, LhsText);
      if InferredType <> '' then
      begin
        LhsSym:= FindTypeAnywhere(AStores, InferredType, LhsStore);
        if LhsSym.Id <= 0 then Result.Note:= Format('inferred %s: %s (type not indexed)', [LhsText, InferredType]);
      end;
    end;
    if LhsSym.Id > 0 then
    begin
      { Direct child, else a member inherited from a same-store ancestor. }
      ResolvedSym:= ResolveMemberOnType(LhsStore, LhsSym.Id, Result.Token);
      if ResolvedSym.Id > 0 then
      begin
        Result.Resolved          := ResolvedSym;
        Result.HasResolved       := True;
        Result.ResolvedStoreIndex:= StoreIndexOf(AStores, LhsStore);
      end
      else if LhsSym.Kind in [skClass, skRecord, skInterface, skTypeAlias] then
      begin
        { Not on the type or any same-store ancestor. If the LHS is an alias to a
          generic instantiation (TThingList = TMyList<TThing>), unwrap it: match
          the generic base by (name, arity) across ALL stores and resolve the
          member there (incl. that base's own ancestry). This is the cross-DB path
          -- the generic base typically lives in a separate library index. }
        var GBase : string      ;
        var GArity: Integer     ;
        var GenStore: ISymbolStore;
        if (LhsSym.Kind = skTypeAlias) and ParseGenericBase(LhsSym.Signature, GBase, GArity) then
        begin
          var BaseSym: TSymbol:= FindGenericBaseAnywhere(AStores, GBase, GArity, GenStore);
          if BaseSym.Id > 0 then
          begin
            var Mem: TSymbol:= ResolveMemberOnType(GenStore, BaseSym.Id, Result.Token);
            if Mem.Id > 0 then
            begin
              Result.Resolved          := Mem;
              Result.HasResolved       := True;
              Result.OwnerTypeFallback := False;
              Result.ResolvedStoreIndex:= StoreIndexOf(AStores, GenStore);
              Result.Note:= Format('resolved via generic base %s', [BaseSym.QualifiedName]);
            end;
          end;
        end;
        { Owner-type floor -- only if the generic step did not resolve. }
        if not Result.HasResolved then
        begin
          Result.Resolved          := LhsSym;
          Result.HasResolved       := True;
          Result.OwnerTypeFallback := True;
          Result.ResolvedStoreIndex:= StoreIndexOf(AStores, LhsStore);
          Result.Note:= Format('owner type %s (member may be inherited)', [LhsSym.QualifiedName]);
        end;
      end
      else Result.Note:= 'Member ' + Result.Token + ' not found on ' + LhsSym.QualifiedName + '.';
    end // if
    else if Result.Note = '' then Result.Note:= 'LHS ' + LhsText + ' unresolved.';
  end // if
  else
  begin
    { v0.94 (hover scope fix): a bare identifier inside a routine body most
      often means THAT routine's own param/local, not some unrelated
      same-named global. Scope-first: find the routine whose IMPLEMENTATION
      BODY span contains the cursor line, and check whether Token is one of
      its direct children (param/local). Only fall through to the flat
      whole-DB name lookup when no such scoped match exists. }
    if FileId > 0 then
    begin
      var EnclRoutine: TSymbol:= Primary.FindEnclosingRoutineByImpl(FileId, ALine);
      if EnclRoutine.Id > 0 then
      begin
        var Local: TSymbol:= Primary.FindChildSymbolByName(EnclRoutine.Id, Result.Token);
        if (Local.Id > 0) and (Local.Kind in [skParam, skLocalVar]) then
        begin
          Result.Resolved          := Local;
          Result.HasResolved       := True;
          Result.ResolvedStoreIndex:= StoreIndexOf(AStores, Primary);
        end;
      end;
    end;

    if not Result.HasResolved then
    begin
      var BareStore: ISymbolStore;
      ResolvedSym:= FindTypeAnywhere(AStores, Result.Token, BareStore);
      if ResolvedSym.Id > 0 then
      begin
        Result.Resolved          := ResolvedSym;
        Result.HasResolved       := True;
        Result.ResolvedStoreIndex:= StoreIndexOf(AStores, BareStore);
      end
      else
      begin
        { v0.46: infer a bare local var/param's declared type. }
        var InferredType: string:= InferLocalVarType(Lines, ALine - 1, Result.Token);
        if InferredType <> '' then
        begin
          ResolvedSym:= FindTypeAnywhere(AStores, InferredType, BareStore);
          if ResolvedSym.Id > 0 then
          begin
            Result.Resolved          := ResolvedSym;
            Result.HasResolved       := True;
            Result.ResolvedStoreIndex:= StoreIndexOf(AStores, BareStore);
            Result.Note:= Format('%s: %s', [Result.Token, InferredType]);
          end
          else Result.Note:= Format('%s: %s (type not indexed)', [Result.Token, InferredType]);
        end
        else Result.Note:= 'unresolved (local type not inferred)';
      end; // else
    end; // if not Result.HasResolved
  end; // else

  if Result.HasResolved then
  begin
    { Doc lives in the SAME store the symbol came from (ids are per-DB). }
    var DocStore: ISymbolStore:= Primary;
    if (Result.ResolvedStoreIndex >= 0) and (Result.ResolvedStoreIndex <= High(AStores)) then
      DocStore:= AStores[Result.ResolvedStoreIndex];
    Result.Doc:= DocStore.GetSymbolDoc(Result.Resolved.Id);
    Result.HasDoc:= Result.Doc.HasContent;
  end;
end; // function

class function TTypeAtResolver.ResolveMemberScope(const AStores: TArray<ISymbolStore>; const AFile: string;
  ALine, ALhsEndCol: Integer; out AStore: ISymbolStore): TSymbol;
var
  Res     : TTypeAtResult ;
  Lines   : TArray<string>;
  VT      : string        ;
  LhsTok  : string        ;
  Dot     : Boolean       ;
  Ignored : string        ;
  GBase   : string        ;
  GArity  : Integer       ;
  GenStore: ISymbolStore  ;
  BaseSym : TSymbol       ;
begin
  FillChar(Result, SizeOf(Result), 0);
  AStore:= nil;
  if Length(AStores) = 0 then Exit;

  Res:= Resolve(AStores, AFile, ALine, ALhsEndCol);

  { 1. The LHS already IS a type -- `TFoo.`. }
  if Res.HasResolved and (Res.Resolved.Kind in [skClass, skRecord, skInterface, skTypeAlias]) then
  begin
    Result:= Res.Resolved;
    if (Res.ResolvedStoreIndex >= 0) and (Res.ResolvedStoreIndex <= High(AStores)) then
      AStore:= AStores[Res.ResolvedStoreIndex]
    else
      AStore:= AStores[0];
  end
  { 2. The LHS is a VALUE -- param, local, field, var. THIS is the step that was
       missing: Resolved.Kind is skParam/skLocalVar/skField here and never a class
       kind, while the declared type name sits in Signature. }
  else if Res.HasResolved then
  begin
    VT:= TypeIdentOfSignature(Res.Resolved.Signature);
    if VT <> '' then Result:= FindTypeWithMembersAnywhere(AStores, VT, AStore);
  end;

  { 3. Nothing indexed under that name -- infer the declaration by scanning the
       source above the cursor, the same fallback Resolve uses for locals. }
  if (Result.Id <= 0) and TLiveDocuments.Readable(AFile) then
  begin
    Lines:= TLiveDocuments.ReadLines(AFile);
    if (ALine >= 1) and (ALine <= Length(Lines)) then
    begin
      LhsTok:= ExtractTokenAt(Lines[ALine - 1], ALhsEndCol, Dot, Ignored);
      if LhsTok <> '' then
      begin
        VT:= InferLocalVarType(Lines, ALine - 1, LhsTok);
        if VT <> '' then Result:= FindTypeWithMembersAnywhere(AStores, VT, AStore);
      end;
    end;
  end;

  { 4. An alias to a generic instantiation (TThingList = TMyList<TThing>) has no
       members of its own -- unwrap to the generic base, which usually lives in a
       different index than the alias. }
  if (Result.Id > 0) and (Result.Kind = skTypeAlias) and ParseGenericBase(Result.Signature, GBase, GArity) then
  begin
    BaseSym:= FindGenericBaseAnywhere(AStores, GBase, GArity, GenStore);
    if BaseSym.Id > 0 then
    begin
      Result:= BaseSym;
      AStore:= GenStore;
    end;
  end;

  if Result.Id <= 0 then AStore:= nil;
end; // function

class function TTypeAtResolver.CollectMembers(const AStore: ISymbolStore; ATypeId: Int64): TArray<TSymbol>;
var
  Anc  : TArray<TTypeAncestor>;
  Kids : TArray<TSymbol>      ;
  I, J : Integer              ;
  Count: Integer              ;

  procedure AddUnique(const ASym: TSymbol);
  var
    K  : Integer;   { LOCAL on purpose -- sharing the outer J would corrupt the
                      ancestor loop that calls this. }
    Dup: Boolean;
  begin
    { Linear scan rather than a dictionary: a type's member list is tens of
      entries, and this avoids pulling Generics.Collections into the resolver. }
    if ASym.Name = '' then Exit;
    Dup:= False;
    for K:= 0 to Count - 1 do
      if SameText(Result[K].Name, ASym.Name) then begin Dup:= True; Break; end;
    if Dup then Exit;
    if Count = Length(Result) then SetLength(Result, (Count + 1) * 2);
    Result[Count]:= ASym;
    Inc(Count);
  end;

begin
  SetLength(Result, 0);
  Count:= 0;
  if (AStore = nil) or (ATypeId <= 0) then Exit;

  { Own members first, so an override shadows the ancestor's declaration -- the
    nearest one is the one the editor should describe. }
  Kids:= AStore.FindAllChildSymbols(ATypeId);
  for I:= 0 to High(Kids) do AddUnique(Kids[I]);

  Anc:= AStore.GetTransitiveAncestors(ATypeId);
  for I:= 0 to High(Anc) do
  begin
    if Anc[I].SymbolId <= 0 then Continue;   // unresolved ancestor edge (unindexed alias)
    Kids:= AStore.FindAllChildSymbols(Anc[I].SymbolId);
    for J:= 0 to High(Kids) do AddUnique(Kids[J]);
  end;

  SetLength(Result, Count);
end; // function

class function TTypeAtResolver.RenderText( const AResult: TTypeAtResult): string;
var
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    SB.AppendLine('File:         ' + AResult.FileName);
    SB.AppendLine(Format('Position:     line %d, col %d', [AResult.Line, AResult.Col]));
    if AResult.HasContain then SB.AppendLine('Containing:   ' + AResult.Containing.QualifiedName);
    if AResult.Token <> '' then SB.AppendLine('Token:        ' + AResult.Token);
    if AResult.HasResolved then
    begin
      SB.AppendLine('Resolved:     ' + AResult.Resolved.QualifiedName);
      if AResult.Resolved.Signature <> '' then SB.AppendLine('Signature:    ' + AResult.Resolved.Signature);
    end
    else if AResult.Note <> '' then SB.AppendLine('Resolved:     ' + AResult.Note);
    // v(ADP3 T1) review fix (finding 1): strip the ownership marker before it
    // reaches this plain-text render -- see TDocRegions.StripForDisplay's own
    // comment; the read path (AResult.Doc.Summary itself) must keep it. Test
    // the CLEANED summary for emptiness, not the raw one.
    var CleanTypeAtSummary: string:= TDocRegions.StripForDisplay(AResult.Doc.Summary);
    if AResult.HasDoc and (CleanTypeAtSummary <> '') then SB.AppendLine('Doc:          ' + CleanTypeAtSummary);
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

class function TTypeAtResolver.RenderJson( const AResult: TTypeAtResult): string;
var
  Fb: string;
begin
  if AResult.OwnerTypeFallback then Fb:= 'true' else Fb:= 'false';
  Result:= Format(
    '{"file":"%s","line":%d,"col":%d,"token":"%s",' + '"containing":"%s","resolved":"%s","signature":"%s","note":"%s",' + '"owner_type_fallback":%s}', [
      StringReplace(AResult.FileName, '\', '/', [rfReplaceAll]), AResult.Line, AResult.Col, AResult.Token, AResult.Containing.QualifiedName, AResult.Resolved.QualifiedName,
      AResult.Resolved.Signature, AResult.Note, Fb]);
end;

end.
