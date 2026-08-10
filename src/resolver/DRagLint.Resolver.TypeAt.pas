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
      /// Calls: by, children, DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName, DRagLint.Core.Interfaces.ISymbolStore.FindContainingSymbol, DRagLint.Core.Interfaces.ISymbolStore.FindEnclosingRoutineByImpl, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Resolver.TypeAt.FindGenericBaseAnywhere, DRagLint.Resolver.TypeAt.FindTypeAnywhere, DRagLint.Resolver.TypeAt.InferLocalVarType, DRagLint.Resolver.TypeAt.ParseGenericBase (+10 more)
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
  end;

implementation

uses
  DRagLint.Doc.Regions
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

  if not TFile.Exists(AFile) then
  begin
    Result.Note:= 'File not found.';
    Exit;
  end;
  Lines:= TFile.ReadAllLines(AFile, TEncoding.ANSI);
  if (ALine < 1) or (ALine > Length(Lines)) then
  begin
    Result.Note:= 'Line out of range.';
    Exit;
  end;
  LineText:= Lines[ALine - 1];
  Result.Token:= ExtractTokenAt(LineText, ACol, PrecedingDot, LhsText);

  FileId:= Primary.FindFileIdByPath(AFile);
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
      if VT <> '' then TS:= FindTypeAnywhere(AStores, VT, LhsStore);
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
