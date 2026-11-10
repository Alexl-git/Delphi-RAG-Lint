unit TreeSitter;

interface

uses
  SysUtils
  , TreeSitterLib
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: TreeSitter.TTSParser.ParseString (TreeSitter.pas), TreeSitter.TTSParser.SetLanguage (TreeSitter.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  ETreeSitterException = Exception;

  //some aliases, so TreeSitterLib is not needed in uses clause
  /// <remarks>
  /// <!-- drag-lint:auto -->some aliases, so TreeSitterLib is not needed in uses clause
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.pas), declaration (DRagLint.Diagnostics.AstChecks.pas), declaration (DRagLint.Diagnostics.ParseCache.pas), declaration (DRagLint.Index.CallResolver.pas), DRagLint.CLI.TreeSitterGrammarVersion (DRagLint.CLI.pas) (+13 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  PTSLanguage = TreeSitterLib.PTSLanguage;
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (TreeSitter.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTSLanguage = TSLanguage;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (TreeSitter.pas), TreeSitter.TTSLanguageHelper.GetFieldId (TreeSitter.pas), TreeSitter.TTSLanguageHelper.GetFieldName (TreeSitter.pas), TreeSitter.TTSTreeCursor.GetCurrentFieldId (TreeSitter.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSFieldId    = TreeSitterLib.TSFieldId;
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (TreeSitter.pas), TreeSitter.TTSLanguageHelper.GetSymbolForName (TreeSitter.pas), TreeSitter.TTSLanguageHelper.GetSymbolName (TreeSitter.pas), TreeSitter.TTSNodeHelper.GrammarSymbol (TreeSitter.pas), TreeSitter.TTSNodeHelper.Symbol (TreeSitter.pas) (+2 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSSymbol     = TreeSitterLib.TSSymbol;
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (TreeSitter.pas), TreeSitter.TTSLanguageHelper.GetSymbolType (TreeSitter.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSSymbolType = TreeSitterLib.TSSymbolType;

  PTSGetLanguageFunc = ^TTSGetLanguageFunc;
  /// <returns><!-- drag-lint:auto type -->PTSLanguage</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.TreeSitterGrammarVersion (DRagLint.CLI.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTSGetLanguageFunc = function(): PTSLanguage; cdecl;

  TTSLanguageHelper = record helper for TTSLanguage
    private
      /// <param name="AFieldId"><!-- drag-lint:auto type -->TSFieldId</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed:
      /// string(AnsiString(ts_language_field_name_for_id(@Self, AFieldId))).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: AnsiString, TreeSitterLib.ts_language_field_name_for_id</para>
      /// <seealso cref="TreeSitterLib.ts_language_field_name_for_id"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.FieldCount"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldId"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolForName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolName"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GetFieldName(AFieldId: TSFieldId): string                               ;
      /// <param name="AFieldName"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TSFieldId -- Observed:
      /// ts_language_field_id_for_name(@Self, PAnsiChar(ansiFieldName),
      /// Length(ansiFieldName)).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: AnsiString, PAnsiChar, TreeSitterLib.ts_language_field_id_for_name</para>
      /// <seealso cref="TreeSitterLib.ts_language_field_id_for_name"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.FieldCount"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolForName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolName"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GetFieldId(const AFieldName: string): TSFieldId                         ;
      /// <param name="ASymbol"><!-- drag-lint:auto type -->TSSymbol</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed:
      /// string(AnsiString(ts_language_symbol_name(@Self, ASymbol))).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: AnsiString, TreeSitterLib.ts_language_symbol_name</para>
      /// <seealso cref="TreeSitterLib.ts_language_symbol_name"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.FieldCount"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldId"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolForName"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GetSymbolName(ASymbol: TSSymbol): string                                ;
      /// <param name="ASymbolName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AIsNamed"><!-- drag-lint:auto type -->Boolean</param>
      /// <returns><!-- drag-lint:auto -->TSSymbol -- Observed:
      /// ts_language_symbol_for_name(@Self, PAnsiChar(ansiSymbolName),
      /// Length(ansiSymbolName), AIsNamed).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: AnsiString, PAnsiChar, TreeSitterLib.ts_language_symbol_for_name</para>
      /// <seealso cref="TreeSitterLib.ts_language_symbol_for_name"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.FieldCount"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldId"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolName"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GetSymbolForName(const ASymbolName: string; AIsNamed: Boolean): TSSymbol;
      /// <param name="ASymbol"><!-- drag-lint:auto type -->TSSymbol</param>
      /// <returns><!-- drag-lint:auto -->TSSymbolType -- Observed:
      /// ts_language_symbol_type(@Self, ASymbol).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_language_symbol_type</para>
      /// <seealso cref="TreeSitterLib.ts_language_symbol_type"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.FieldCount"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldId"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolForName"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GetSymbolType(ASymbol: TSSymbol): TSSymbolType                          ;
    public
      /// <returns><!-- drag-lint:auto -->UInt32 -- Observed: ts_language_version(@Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_language_version</para>
      /// <seealso cref="TreeSitterLib.ts_language_version"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.FieldCount"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldId"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolForName"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Version    : UInt32;
      /// <summary><!-- drag-lint:auto sum -->TTSLanguageHelper</summary>
      /// <returns><!-- drag-lint:auto -->UInt32 -- Observed:
      /// ts_language_field_count(@Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_language_field_count</para>
      /// <seealso cref="TreeSitterLib.ts_language_field_count"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldId"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolForName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolName"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FieldCount : UInt32;
      /// <returns><!-- drag-lint:auto -->UInt32 -- Observed:
      /// ts_language_symbol_count(@Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_language_symbol_count</para>
      /// <seealso cref="TreeSitterLib.ts_language_symbol_count"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.FieldCount"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldId"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolForName"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function SymbolCount: UInt32;

      /// <param name="AState"><!-- drag-lint:auto type -->TSStateId</param>
      /// <param name="ASymbol"><!-- drag-lint:auto type -->TSSymbol</param>
      /// <returns><!-- drag-lint:auto -->TSStateId -- Observed:
      /// ts_language_next_state(@Self, AState, ASymbol).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_language_next_state</para>
      /// <seealso cref="TreeSitterLib.ts_language_next_state"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.FieldCount"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldId"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetFieldName"/>
      /// <seealso cref="TreeSitter.TTSLanguageHelper.GetSymbolForName"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function NextState(AState: TSStateId; ASymbol: TSSymbol): TSStateId;

      property FieldName[AFieldId: TSFieldId]                             : string read GetFieldName       ;
      property FieldId[const AFieldName: string]                          : TSFieldId read GetFieldId      ;
      property SymbolName[ASymbol: TSSymbol]                              : string read GetSymbolName      ;
      property SymbolForName[const ASymbolName: string; AIsNamed: Boolean]: TSSymbol read GetSymbolForName ;
      property SymbolType[ASymbol: TSSymbol]                              : TSSymbolType read GetSymbolType;
  end; // record

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Diagnostics.ParseCache.pas) ?, DRagLint.Index.CallResolver.TCallResolver.WithStatementsOf (DRagLint.Index.CallResolver.pas) ?, TreeSitter.TTSParser.Parse (TreeSitter.pas), TreeSitter.TTSParser.ParseString (TreeSitter.pas), TreeSitter.TTSTree.Clone (TreeSitter.pas) (+14 more)</para>
  /// <para>Used in units: DRagLint.Convert.DfmReemit, DRagLint.Diagnostics.ParseCache, DRagLint.Index.CallResolver, DRagLint.Lint.Linter, DRagLint.LSP.Feature.FoldingRange, DRagLint.LSP.Feature.InlayHint, DRagLint.LSP.Feature.SemanticTokens, DRagLint.LSP.Server, DRagLint.LSP.SyntaxTree, DRagLint.Parser.Delphi13, DRagLint.Parser.DFM, TreeSitter</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTSTree    = class;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: DRagLint.Analysis.Cfg.FindClassDecl (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.ForLoopAlwaysExecutes (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.TBuilderState.EmitStmt (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Flow.Lattices.FirstIdentChild (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.FirstOperandChild (DRagLint.Analysis.Flow.Lattices.pas) (+1154 more)</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TTSNode  = TSNode;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit.CheckList (DRagLint.Diagnostics.AstChecks.pas) ?, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRaiseInFinally.SearchForRaise (DRagLint.Diagnostics.AstChecks.pas) ?, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSwallowedExcept.Visit (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors.Visit (DRagLint.Diagnostics.AstChecks.pas) ?, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals.CheckProc (DRagLint.Diagnostics.AstChecks.pas) ? (+72 more)</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TTSPoint = TSPoint;

    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: DRagLint.Convert.DfmReemit.ParseDfmBlock (DRagLint.Convert.DfmReemit.pas), DRagLint.Diagnostics.ParseCache.TAstParseCache.Get (DRagLint.Diagnostics.ParseCache.pas), DRagLint.Index.CallResolver.TCallResolver.WithStatementsOf (DRagLint.Index.CallResolver.pas), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), DRagLint.LSP.SyntaxTree.ParseDelphiUtf8 (DRagLint.LSP.SyntaxTree.pas) (+5 more)</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TTSInputEncoding = TreeSitterLib.TSInputEncoding;

    /// <param name="AByteIndex"><!-- drag-lint:auto type -->UInt32</param>
    /// <param name="APosition"><!-- drag-lint:auto type -->TTSPoint</param>
    /// <param name="ABytesRead"><!-- drag-lint:auto type -->var UInt32</param>
    /// <returns><!-- drag-lint:auto type -->TBytes</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: declaration (TreeSitter.pas), TreeSitter.TTSParser.Parse (TreeSitter.pas)</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TTSParseReadFunction = reference to function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes;

    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: DRagLint.Convert.DfmReemit.ParseDfmBlock (DRagLint.Convert.DfmReemit.pas), DRagLint.Diagnostics.ParseCache.TAstParseCache.Get (DRagLint.Diagnostics.ParseCache.pas), DRagLint.Index.CallResolver.TCallResolver.WithStatementsOf (DRagLint.Index.CallResolver.pas), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), DRagLint.LSP.SyntaxTree.ParseDelphiUtf8 (DRagLint.LSP.SyntaxTree.pas) (+5 more)</para>
    /// <para>Used in units: DRagLint.Convert.DfmReemit, DRagLint.Diagnostics.ParseCache, DRagLint.Index.CallResolver, DRagLint.Lint.Linter, DRagLint.LSP.SyntaxTree, DRagLint.Parser.Delphi13, DRagLint.Parser.DFM</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TTSParser = class
      strict private
        FParser: PTSParser               ;
        /// <returns><!-- drag-lint:auto -->PTSLanguage -- Observed:
        /// ts_parser_language(FParser).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_parser_language</para>
        /// <para>Reads: FParser</para>
        /// <seealso cref="TreeSitterLib.ts_parser_language"/>
        /// <seealso cref="TreeSitter.TTSParser.Create"/>
        /// <seealso cref="TreeSitter.TTSParser.Destroy"/>
        /// <seealso cref="TreeSitter.TTSParser.Parse"/>
        /// <seealso cref="TreeSitter.TTSParser.ParseString"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GetLanguage: PTSLanguage;
        /// <param name="Value"><!-- drag-lint:auto type -->const PTSLanguage</param>
        /// <exception cref="ETreeSitterException"><!-- drag-lint:auto exc -->Failed to set parser language to 0x%p</exception>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: DRagLint.Convert.DfmReemit.ParseDfmBlock (DRagLint.Convert.DfmReemit.pas), DRagLint.Diagnostics.ParseCache.TAstParseCache.Get (DRagLint.Diagnostics.ParseCache.pas), DRagLint.Index.CallResolver.TCallResolver.WithStatementsOf (DRagLint.Index.CallResolver.pas), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), DRagLint.LSP.SyntaxTree.ParseDelphiUtf8 (DRagLint.LSP.SyntaxTree.pas) (+4 more)</para>
        /// <para>Used in (via property Language): DRagLint.Convert.DfmReemit.ParseDfmBlock (DRagLint.Convert.DfmReemit.pas) [w], DRagLint.Diagnostics.ParseCache.TAstParseCache.Get (DRagLint.Diagnostics.ParseCache.pas) [w], DRagLint.Index.CallResolver.TCallResolver.WithStatementsOf (DRagLint.Index.CallResolver.pas) [w], DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas) [w], DRagLint.LSP.SyntaxTree.ParseDelphiUtf8 (DRagLint.LSP.SyntaxTree.pas) [w] (+4 more)</para>
        /// <para>Calls: TreeSitterLib.ts_parser_set_language</para>
        /// <para>Reads: FParser</para>
        /// <seealso cref="TreeSitterLib.ts_parser_set_language"/>
        /// <seealso cref="TreeSitter.TTSParser.Create"/>
        /// <seealso cref="TreeSitter.TTSParser.Destroy"/>
        /// <seealso cref="TreeSitter.TTSParser.GetLanguage"/>
        /// <seealso cref="TreeSitter.TTSParser.Parse"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        procedure SetLanguage(const Value: PTSLanguage);
      public
        /// <summary><!-- drag-lint:auto sum -->TTSParser</summary>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: [drag-lint]DRagLint.Convert.DfmReemit.ParseDfmBlock (DRagLint.Convert.DfmReemit.pas), [drag-lint]DRagLint.Diagnostics.ParseCache.TAstParseCache.Get (DRagLint.Diagnostics.ParseCache.pas), [drag-lint]DRagLint.Index.CallResolver.TCallResolver.WithStatementsOf (DRagLint.Index.CallResolver.pas), [drag-lint]DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), [drag-lint]DRagLint.Lint.Linter.TLinter.HarvestFile (DRagLint.Lint.Linter.pas), [drag-lint]DRagLint.LSP.SyntaxTree.ParseDelphiUtf8 (DRagLint.LSP.SyntaxTree.pas), [drag-lint]DRagLint.Parser.Delphi13.TDelphi13Parser.Parse (DRagLint.Parser.Delphi13.pas), [drag-lint]DRagLint.Parser.DFM.ExtractDfmEventBindings (DRagLint.Parser.DFM.pas), [drag-lint]DRagLint.Parser.DFM.TDFMParser.Parse (DRagLint.Parser.DFM.pas)</para>
        /// <para>Calls: TreeSitterLib.ts_parser_new</para>
        /// <para>virtual</para>
        /// <para>constructor</para>
        /// <para>Writes: FParser</para>
        /// <para>Directives: virtual</para>
        /// <seealso cref="TreeSitterLib.ts_parser_new"/>
        /// <seealso cref="TreeSitter.TTSParser.Destroy"/>
        /// <seealso cref="TreeSitter.TTSParser.GetLanguage"/>
        /// <seealso cref="TreeSitter.TTSParser.Parse"/>
        /// <seealso cref="TreeSitter.TTSParser.ParseString"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        constructor Create; virtual;
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_parser_delete</para>
        /// <para>Reads: FParser</para>
        /// <para>Directives: override</para>
        /// <seealso cref="TreeSitterLib.ts_parser_delete"/>
        /// <seealso cref="TreeSitter.TTSParser.Create"/>
        /// <seealso cref="TreeSitter.TTSParser.GetLanguage"/>
        /// <seealso cref="TreeSitter.TTSParser.Parse"/>
        /// <seealso cref="TreeSitter.TTSParser.ParseString"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        destructor Destroy; override;

        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_parser_reset</para>
        /// <para>Reads: FParser</para>
        /// <seealso cref="TreeSitterLib.ts_parser_reset"/>
        /// <seealso cref="TreeSitter.TTSParser.Create"/>
        /// <seealso cref="TreeSitter.TTSParser.Destroy"/>
        /// <seealso cref="TreeSitter.TTSParser.GetLanguage"/>
        /// <seealso cref="TreeSitter.TTSParser.Parse"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        procedure Reset;

        /// <param name="AString"><!-- drag-lint:auto type -->const string</param>
        /// <param name="AOldTree"><!-- drag-lint:auto type -->const TTSTree = nil</param>
        /// <returns><!-- drag-lint:auto -->TTSTree -- Observed: TTSTree.Create(Tree).</returns>
        /// <exception cref="ETreeSitterException"><!-- drag-lint:auto exc -->Cannot parse empty string; Faild to parse string</exception>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitter.TTSTree.Create, TreeSitter.TTSTree.TreeNilSafe, TreeSitterLib.ts_parser_parse_string_encoding</para>
        /// <para>Reads: FParser</para>
        /// <para>Owns returned: new (caller owns)</para>
        /// <seealso cref="TreeSitter.TTSTree.Create"/>
        /// <seealso cref="TreeSitter.TTSTree.TreeNilSafe"/>
        /// <seealso cref="TreeSitterLib.ts_parser_parse_string_encoding"/>
        /// <seealso cref="TreeSitter.TTSParser.Create"/>
        /// <seealso cref="TreeSitter.TTSParser.Destroy"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function ParseString(const AString: string; const AOldTree: TTSTree = nil): TTSTree                                          ;
        /// <param name="AParseReadFunction"><!-- drag-lint:auto type -->TTSParseReadFunction</param>
        /// <param name="AEncoding"><!-- drag-lint:auto type -->TTSInputEncoding</param>
        /// <param name="AOldTree"><!-- drag-lint:auto type -->const TTSTree = nil</param>
        /// <returns><!-- drag-lint:auto -->TTSTree -- Observed:
        /// TTSTree.Create(ts_parser_parse(FParser, AOldTree.TreeNilSafe, tsi)).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: DRagLint.Convert.DfmReemit.ParseDfmBlock (DRagLint.Convert.DfmReemit.pas), DRagLint.Diagnostics.ParseCache.TAstParseCache.Get (DRagLint.Diagnostics.ParseCache.pas), DRagLint.Index.CallResolver.TCallResolver.WithStatementsOf (DRagLint.Index.CallResolver.pas), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), DRagLint.LSP.SyntaxTree.ParseDelphiUtf8 (DRagLint.LSP.SyntaxTree.pas) (+3 more)</para>
        /// <para>Calls: TreeSitter.TTSTree.Create, TreeSitter.TTSTree.TreeNilSafe, TreeSitterLib.ts_parser_parse</para>
        /// <para>Reads: FParser</para>
        /// <para>Owns returned: new (caller owns)</para>
        /// <seealso cref="TreeSitter.TTSTree.Create"/>
        /// <seealso cref="TreeSitter.TTSTree.TreeNilSafe"/>
        /// <seealso cref="TreeSitterLib.ts_parser_parse"/>
        /// <seealso cref="TreeSitter.TTSParser.Create"/>
        /// <seealso cref="TreeSitter.TTSParser.Destroy"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function Parse(AParseReadFunction: TTSParseReadFunction; AEncoding: TTSInputEncoding; const AOldTree: TTSTree = nil): TTSTree;

        property Parser  : PTSParser read FParser;
        property Language: PTSLanguage read GetLanguage write SetLanguage;
    end;

    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: declaration (DRagLint.Diagnostics.ParseCache.pas), DRagLint.Index.CallResolver.TCallResolver.WithStatementsOf (DRagLint.Index.CallResolver.pas), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.HarvestFile (DRagLint.Lint.Linter.pas), DRagLint.LSP.Feature.FoldingRange.TLspFoldingRangeFeature.Handle (DRagLint.LSP.Feature.FoldingRange.pas) (+13 more)</para>
    /// <para>Used in units: DRagLint.Convert.DfmReemit, DRagLint.Diagnostics.ParseCache, DRagLint.Index.CallResolver, DRagLint.Lint.Linter, DRagLint.LSP.Feature.FoldingRange, DRagLint.LSP.Feature.InlayHint, DRagLint.LSP.Feature.SemanticTokens, DRagLint.LSP.Server, DRagLint.LSP.SyntaxTree, DRagLint.Parser.Delphi13, DRagLint.Parser.DFM, TreeSitter</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TTSTree = class
      strict private
        FTree: PTSTree;
      public
        /// <param name="ATree"><!-- drag-lint:auto type -->PTSTree</param>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: TreeSitter.TTSParser.Parse (TreeSitter.pas), TreeSitter.TTSParser.ParseString (TreeSitter.pas), TreeSitter.TTSTree.Clone (TreeSitter.pas)</para>
        /// <para>virtual</para>
        /// <para>constructor</para>
        /// <para>Writes: FTree</para>
        /// <para>Directives: virtual</para>
        /// <seealso cref="TreeSitter.TTSTree.Clone"/>
        /// <seealso cref="TreeSitter.TTSTree.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTree.Language"/>
        /// <seealso cref="TreeSitter.TTSTree.RootNode"/>
        /// <seealso cref="TreeSitter.TTSTree.TreeNilSafe"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        constructor Create(ATree: PTSTree); virtual;
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_tree_delete</para>
        /// <para>Reads: FTree</para>
        /// <para>Directives: override</para>
        /// <seealso cref="TreeSitterLib.ts_tree_delete"/>
        /// <seealso cref="TreeSitter.TTSTree.Clone"/>
        /// <seealso cref="TreeSitter.TTSTree.Create"/>
        /// <seealso cref="TreeSitter.TTSTree.Language"/>
        /// <seealso cref="TreeSitter.TTSTree.RootNode"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        destructor Destroy; override;

        /// <returns><!-- drag-lint:auto -->PTSLanguage -- Observed:
        /// ts_tree_language(FTree).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_tree_language</para>
        /// <para>Reads: FTree</para>
        /// <seealso cref="TreeSitterLib.ts_tree_language"/>
        /// <seealso cref="TreeSitter.TTSTree.Clone"/>
        /// <seealso cref="TreeSitter.TTSTree.Create"/>
        /// <seealso cref="TreeSitter.TTSTree.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTree.RootNode"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function Language   : PTSLanguage;
        /// <returns><!-- drag-lint:auto -->TTSNode -- Observed: ts_tree_root_node(FTree).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: DRagLint.Convert.DfmReemit.ParseDfmBlock (DRagLint.Convert.DfmReemit.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity/2 (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally (DRagLint.Diagnostics.AstChecks.pas) (+87 more)</para>
        /// <para>Calls: TreeSitterLib.ts_tree_root_node</para>
        /// <para>Reads: FTree</para>
        /// <seealso cref="TreeSitterLib.ts_tree_root_node"/>
        /// <seealso cref="TreeSitter.TTSTree.Clone"/>
        /// <seealso cref="TreeSitter.TTSTree.Create"/>
        /// <seealso cref="TreeSitter.TTSTree.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTree.Language"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function RootNode   : TTSNode;
        /// <returns><!-- drag-lint:auto -->PTSTree -- Observed: FTree.</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: TreeSitter.TTSParser.Parse (TreeSitter.pas), TreeSitter.TTSParser.ParseString (TreeSitter.pas)</para>
        /// <para>Reads: FTree</para>
        /// <para>Effect-free (proven)</para>
        /// <seealso cref="TreeSitter.TTSTree.Clone"/>
        /// <seealso cref="TreeSitter.TTSTree.Create"/>
        /// <seealso cref="TreeSitter.TTSTree.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTree.Language"/>
        /// <seealso cref="TreeSitter.TTSTree.RootNode"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function TreeNilSafe: PTSTree;
        /// <summary><!-- drag-lint:auto sum -->TTSTree</summary>
        /// <returns><!-- drag-lint:auto -->TTSTree -- Observed:
        /// TTSTree.Create(ts_tree_copy(FTree)).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitter.TTSTree.Create, TreeSitterLib.ts_tree_copy</para>
        /// <para>Reads: FTree</para>
        /// <para>Owns returned: new (caller owns)</para>
        /// <seealso cref="TreeSitter.TTSTree.Create"/>
        /// <seealso cref="TreeSitterLib.ts_tree_copy"/>
        /// <seealso cref="TreeSitter.TTSTree.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTree.Language"/>
        /// <seealso cref="TreeSitter.TTSTree.RootNode"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function Clone      : TTSTree;

        property Tree: PTSTree read FTree;
    end;

    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: DRagLint.Lint.QueryRules.NamedChildrenOf (DRagLint.Lint.QueryRules.pas), DRagLint.LSP.Feature.FoldingRange.WalkFolds (DRagLint.LSP.Feature.FoldingRange.pas), DRagLint.LSP.Feature.InlayHint.THintWalker.Walk (DRagLint.LSP.Feature.InlayHint.pas), DRagLint.LSP.Feature.SemanticTokens.WalkSyntax (DRagLint.LSP.Feature.SemanticTokens.pas), DRagLint.Query.SyntaxCount.CountTreeFeatures (DRagLint.Query.SyntaxCount.pas) (+1 more)</para>
    /// <para>Used in units: DRagLint.Lint.QueryRules, DRagLint.LSP.Feature.FoldingRange, DRagLint.LSP.Feature.InlayHint, DRagLint.LSP.Feature.SemanticTokens, DRagLint.Query.SyntaxCount, TreeSitter</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TTSTreeCursor = class
      strict private
        FTreeCursor: TSTreeCursor                 ;
        /// <returns><!-- drag-lint:auto -->PTSTreeCursor -- Observed: @FTreeCursor.</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: TreeSitter.TTSTreeCursor.Create/1 (TreeSitter.pas), TreeSitter.TTSTreeCursor.Reset/1 (TreeSitter.pas)</para>
        /// <para>Used in (via property TreeCursor): TreeSitter.TTSTreeCursor.Create/1 (TreeSitter.pas) [r], TreeSitter.TTSTreeCursor.Reset/1 (TreeSitter.pas) [r]</para>
        /// <para>Reads: FTreeCursor</para>
        /// <para>Effect-free (proven)</para>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentFieldId"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GetTreeCursor : PTSTreeCursor;
        /// <returns><!-- drag-lint:auto -->TTSNode -- Observed:
        /// ts_tree_cursor_current_node(@FTreeCursor).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: DRagLint.Lint.QueryRules.NamedChildrenOf (DRagLint.Lint.QueryRules.pas), DRagLint.LSP.Feature.FoldingRange.WalkFolds (DRagLint.LSP.Feature.FoldingRange.pas), DRagLint.LSP.Feature.InlayHint.THintWalker.Walk (DRagLint.LSP.Feature.InlayHint.pas), DRagLint.LSP.Feature.SemanticTokens.WalkSyntax (DRagLint.LSP.Feature.SemanticTokens.pas), DRagLint.Query.SyntaxCount.CountTreeFeatures (DRagLint.Query.SyntaxCount.pas)</para>
        /// <para>Used in (via property CurrentNode): DRagLint.Lint.QueryRules.NamedChildrenOf (DRagLint.Lint.QueryRules.pas) [r], DRagLint.LSP.Feature.FoldingRange.WalkFolds (DRagLint.LSP.Feature.FoldingRange.pas) [r], DRagLint.LSP.Feature.InlayHint.THintWalker.Walk (DRagLint.LSP.Feature.InlayHint.pas) [r], DRagLint.LSP.Feature.SemanticTokens.WalkSyntax (DRagLint.LSP.Feature.SemanticTokens.pas) [r], DRagLint.Query.SyntaxCount.CountTreeFeatures (DRagLint.Query.SyntaxCount.pas) [r]</para>
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_current_node</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_current_node"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GetCurrentNode: TTSNode;
        /// <returns><!-- drag-lint:auto -->string -- Observed:
        /// string(AnsiString(ts_tree_cursor_current_field_name(@FTreeCursor))).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: AnsiString, TreeSitterLib.ts_tree_cursor_current_field_name</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_current_field_name"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GetCurrentFieldName: string      ;
        /// <returns><!-- drag-lint:auto -->TSFieldId -- Observed:
        /// ts_tree_cursor_current_field_id(@FTreeCursor).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_current_field_id</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_current_field_id"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GetCurrentFieldId        : TSFieldId;
        /// <returns><!-- drag-lint:auto -->UInt32 -- Observed:
        /// ts_tree_cursor_current_depth(@FTreeCursor).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: DRagLint.Query.SyntaxCount.CountTreeFeatures (DRagLint.Query.SyntaxCount.pas)</para>
        /// <para>Used in (via property CurrentDepth): DRagLint.Query.SyntaxCount.CountTreeFeatures (DRagLint.Query.SyntaxCount.pas) [r]</para>
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_current_depth</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_current_depth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentFieldId"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GetCurrentDepth          : UInt32;
        /// <returns><!-- drag-lint:auto -->UInt32 -- Observed:
        /// ts_tree_cursor_current_descendant_index(@FTreeCursor).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_current_descendant_index</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_current_descendant_index"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentFieldId"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GetCurrentDescendantIndex: UInt32;
      public
        /// <summary><!-- drag-lint:auto sum -->TTSTreeCursor</summary>
        /// <param name="ANode"><!-- drag-lint:auto type -->TTSNode</param>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: DRagLint.Lint.QueryRules.NamedChildrenOf (DRagLint.Lint.QueryRules.pas), DRagLint.LSP.Feature.FoldingRange.WalkFolds (DRagLint.LSP.Feature.FoldingRange.pas), DRagLint.LSP.Feature.InlayHint.THintWalker.Walk (DRagLint.LSP.Feature.InlayHint.pas), DRagLint.LSP.Feature.SemanticTokens.WalkSyntax (DRagLint.LSP.Feature.SemanticTokens.pas), DRagLint.Query.SyntaxCount.CountTreeFeatures (DRagLint.Query.SyntaxCount.pas)</para>
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_new</para>
        /// <para>Overload 1 of 2</para>
        /// <para>virtual</para>
        /// <para>constructor</para>
        /// <para>Writes: FTreeCursor</para>
        /// <para>Directives: overload; virtual</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_new"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        constructor Create(ANode        : TTSNode      ); overload; virtual;
        /// <summary>TTSTreeCursor</summary>
        /// <param name="ACursorToCopy"><!-- drag-lint:auto type -->TTSTreeCursor</param>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitter.TTSTreeCursor.GetTreeCursor, TreeSitterLib.ts_tree_cursor_copy</para>
        /// <para>Overload 2 of 2</para>
        /// <para>virtual</para>
        /// <para>constructor</para>
        /// <para>Writes: FTreeCursor</para>
        /// <para>Directives: overload; virtual</para>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetTreeCursor"/>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_copy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        constructor Create(ACursorToCopy: TTSTreeCursor); overload; virtual;
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: FillChar, TreeSitterLib.ts_tree_cursor_delete</para>
        /// <para>Reads: FTreeCursor</para>
        /// <para>Directives: override</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_delete"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentFieldId"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        destructor Destroy; override;

        /// <param name="ANode"><!-- drag-lint:auto type -->TTSNode</param>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_reset</para>
        /// <para>Overload 1 of 2</para>
        /// <para>Reads: FTreeCursor</para>
        /// <para>Directives: overload</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_reset"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        procedure Reset(ANode  : TTSNode      ); overload;
        /// <param name="ACursor"><!-- drag-lint:auto type -->TTSTreeCursor</param>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitter.TTSTreeCursor.GetTreeCursor, TreeSitterLib.ts_tree_cursor_reset_to</para>
        /// <para>Overload 2 of 2</para>
        /// <para>Reads: FTreeCursor</para>
        /// <para>Directives: overload</para>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetTreeCursor"/>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_reset_to"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        procedure Reset(ACursor: TTSTreeCursor); overload;

        /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
        /// ts_tree_cursor_goto_parent(@FTreeCursor).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: DRagLint.LSP.Feature.FoldingRange.WalkFolds (DRagLint.LSP.Feature.FoldingRange.pas), DRagLint.LSP.Feature.InlayHint.THintWalker.Walk (DRagLint.LSP.Feature.InlayHint.pas), DRagLint.LSP.Feature.SemanticTokens.WalkSyntax (DRagLint.LSP.Feature.SemanticTokens.pas), DRagLint.Query.SyntaxCount.CountTreeFeatures (DRagLint.Query.SyntaxCount.pas)</para>
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_goto_parent</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_goto_parent"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GotoParent     : Boolean;
        /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
        /// ts_tree_cursor_goto_next_sibling(@FTreeCursor).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: DRagLint.Lint.QueryRules.NamedChildrenOf (DRagLint.Lint.QueryRules.pas), DRagLint.LSP.Feature.FoldingRange.WalkFolds (DRagLint.LSP.Feature.FoldingRange.pas), DRagLint.LSP.Feature.InlayHint.THintWalker.Walk (DRagLint.LSP.Feature.InlayHint.pas), DRagLint.LSP.Feature.SemanticTokens.WalkSyntax (DRagLint.LSP.Feature.SemanticTokens.pas), DRagLint.Query.SyntaxCount.CountTreeFeatures (DRagLint.Query.SyntaxCount.pas)</para>
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_goto_next_sibling</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_goto_next_sibling"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GotoNextSibling: Boolean;
        /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
        /// ts_tree_cursor_goto_previous_sibling(@FTreeCursor).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_goto_previous_sibling</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_goto_previous_sibling"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GotoPrevSibling: Boolean;
        /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
        /// ts_tree_cursor_goto_first_child(@FTreeCursor).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: DRagLint.Lint.QueryRules.NamedChildrenOf (DRagLint.Lint.QueryRules.pas), DRagLint.LSP.Feature.FoldingRange.WalkFolds (DRagLint.LSP.Feature.FoldingRange.pas), DRagLint.LSP.Feature.InlayHint.THintWalker.Walk (DRagLint.LSP.Feature.InlayHint.pas), DRagLint.LSP.Feature.SemanticTokens.WalkSyntax (DRagLint.LSP.Feature.SemanticTokens.pas), DRagLint.Query.SyntaxCount.CountTreeFeatures (DRagLint.Query.SyntaxCount.pas)</para>
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_goto_first_child</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_goto_first_child"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GotoFirstChild : Boolean;
        /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
        /// ts_tree_cursor_goto_last_child(@FTreeCursor).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_goto_last_child</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_goto_last_child"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GotoLastChild  : Boolean;
        /// <param name="AGoalDescendantIndex"><!-- drag-lint:auto type -->UInt32</param>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_goto_descendant</para>
        /// <para>Reads: FTreeCursor</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_goto_descendant"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        procedure GotoDescendant(AGoalDescendantIndex: UInt32);
        /// <param name="AGoalByte"><!-- drag-lint:auto type -->UInt32</param>
        /// <returns><!-- drag-lint:auto -->Int64 -- Observed:
        /// ts_tree_cursor_goto_first_child_for_byte(@FTreeCursor, AGoalByte).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_goto_first_child_for_byte</para>
        /// <para>Overload 1 of 2</para>
        /// <para>Reads: FTreeCursor</para>
        /// <para>Directives: overload</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_goto_first_child_for_byte"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GotoFirstChildForGoal(AGoalByte : UInt32  ): Int64; overload;
        /// <param name="AGoalPoint"><!-- drag-lint:auto type -->TTSPoint</param>
        /// <returns><!-- drag-lint:auto -->Int64 -- Observed:
        /// ts_tree_cursor_goto_first_child_for_point(@FTreeCursor, AGoalPoint).</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: TreeSitterLib.ts_tree_cursor_goto_first_child_for_point</para>
        /// <para>Overload 2 of 2</para>
        /// <para>Reads: FTreeCursor</para>
        /// <para>Directives: overload</para>
        /// <seealso cref="TreeSitterLib.ts_tree_cursor_goto_first_child_for_point"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Create"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.Destroy"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDepth"/>
        /// <seealso cref="TreeSitter.TTSTreeCursor.GetCurrentDescendantIndex"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function GotoFirstChildForGoal(AGoalPoint: TTSPoint): Int64; overload;

        property TreeCursor  : PTSTreeCursor read GetTreeCursor;
        property CurrentNode : TTSNode read GetCurrentNode;
        property CurrentFieldName      : string read GetCurrentFieldName      ;
        property CurrentFieldId        : TSFieldId read GetCurrentFieldId;
        property CurrentDescendantIndex: UInt32 read GetCurrentDescendantIndex;
        property CurrentDepth          : UInt32 read GetCurrentDepth;
    end;

    TTSNodeHelper = record helper for TTSNode
      /// <returns><!-- drag-lint:auto -->PTSLanguage -- Observed: ts_node_language(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_node_language</para>
      /// <seealso cref="TreeSitterLib.ts_node_language"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Language: PTSLanguage;

      /// <returns><!-- drag-lint:auto -->string -- Observed:
      /// string(AnsiString(ts_node_type(Self))).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Cfg.CfgFindProcs.Walk (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.ClassChainLacks (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DeclaredTypeOfVar.TyperefNameOf (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DeclaredTypeOfVar.Visit (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DottedCalleeText (DRagLint.Analysis.Cfg.pas) (+731 more)</para>
      /// <para>Calls: AnsiString, TreeSitterLib.ts_node_type</para>
      /// <seealso cref="TreeSitterLib.ts_node_type"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function NodeType: string       ;
      /// <returns><!-- drag-lint:auto -->TSSymbol -- Observed: ts_node_symbol(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_node_symbol</para>
      /// <seealso cref="TreeSitterLib.ts_node_symbol"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Symbol: TSSymbol       ;
      /// <returns><!-- drag-lint:auto -->string -- Observed:
      /// string(AnsiString(ts_node_grammar_type(Self))).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: AnsiString, TreeSitterLib.ts_node_grammar_type</para>
      /// <seealso cref="TreeSitterLib.ts_node_grammar_type"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GrammarType: string    ;
      /// <returns><!-- drag-lint:auto -->TSSymbol -- Observed:
      /// ts_node_grammar_symbol(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_node_grammar_symbol</para>
      /// <seealso cref="TreeSitterLib.ts_node_grammar_symbol"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GrammarSymbol: TSSymbol;

      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ts_node_is_null(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Cfg.CfgFindProcs.Walk (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.ClassChainLacks (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DeclaredTypeOfVar.TyperefNameOf (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DeclaredTypeOfVar.Visit (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DottedCalleeText (DRagLint.Analysis.Cfg.pas) (+794 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_is_null</para>
      /// <seealso cref="TreeSitterLib.ts_node_is_null"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsNull    : Boolean;
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ts_node_is_error(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors.Visit (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Lint.Linter.CollectDfmParseErrors.Visit (DRagLint.Lint.Linter.pas), DRagLint.Parser.Delphi13.CollectParseErrors (DRagLint.Parser.Delphi13.pas), DRagLint.Parser.DFM.CollectParseErrors (DRagLint.Parser.DFM.pas)</para>
      /// <para>Calls: TreeSitterLib.ts_node_is_error</para>
      /// <seealso cref="TreeSitterLib.ts_node_is_error"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsError   : Boolean;
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ts_node_has_error(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors.Visit (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Lint.Linter.CollectDfmParseErrors.Visit (DRagLint.Lint.Linter.pas), DRagLint.Parser.Delphi13.CollectParseErrors (DRagLint.Parser.Delphi13.pas), DRagLint.Parser.DFM.CollectParseErrors (DRagLint.Parser.DFM.pas), DRagLint.Parser.DFM.TDFMParser.Parse (DRagLint.Parser.DFM.pas) (+3 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_has_error</para>
      /// <seealso cref="TreeSitterLib.ts_node_has_error"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function HasError  : Boolean;
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ts_node_has_changes(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_node_has_changes</para>
      /// <seealso cref="TreeSitterLib.ts_node_has_changes"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function HasChanges: Boolean;
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ts_node_is_extra(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Diagnostics.CloneChecks.RunEngine.CollectLeaves (DRagLint.Diagnostics.CloneChecks.pas)</para>
      /// <para>Calls: TreeSitterLib.ts_node_is_extra</para>
      /// <seealso cref="TreeSitterLib.ts_node_is_extra"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsExtra   : Boolean;
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ts_node_is_missing(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors.Visit (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Lint.Linter.CollectDfmParseErrors.Visit (DRagLint.Lint.Linter.pas), DRagLint.Parser.Delphi13.CollectParseErrors (DRagLint.Parser.Delphi13.pas), DRagLint.Parser.DFM.CollectParseErrors (DRagLint.Parser.DFM.pas)</para>
      /// <para>Calls: TreeSitterLib.ts_node_is_missing</para>
      /// <seealso cref="TreeSitterLib.ts_node_is_missing"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsMissing : Boolean;
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ts_node_is_named(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSwallowedExcept.Visit (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.ExceptionThreadChecks.TExceptionThreadChecker.Check.ScanRaise (DRagLint.Diagnostics.ExceptionThreadChecks.pas), DRagLint.Lint.QueryRules.NamedChildrenOf (DRagLint.Lint.QueryRules.pas), DRagLint.LSP.Feature.SemanticTokens.IsKeywordType (DRagLint.LSP.Feature.SemanticTokens.pas), DRagLint.Query.SyntaxCount.CountTreeFeatures (DRagLint.Query.SyntaxCount.pas)</para>
      /// <para>Calls: TreeSitterLib.ts_node_is_named</para>
      /// <seealso cref="TreeSitterLib.ts_node_is_named"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsNamed   : Boolean;
      /// <returns><!-- drag-lint:auto -->TTSNode -- Observed: ts_node_parent(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Cfg.TBuilderState.BareIsRtl (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build.EnclosingListEnd (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckDatasetOpen.IsWholeStatement (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckHardcodedPath.IsConditionalAsgn (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSwallowedExcept.EnclosingDefProc (DRagLint.Diagnostics.AstChecks.pas) (+76 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_parent</para>
      /// <seealso cref="TreeSitterLib.ts_node_parent"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Parent    : TTSNode;
      /// <returns><!-- drag-lint:auto -->string -- Observed: string(AnsiString(pach)).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: AnsiString, FreeMem, TreeSitterLib.ts_node_string</para>
      /// <seealso cref="TreeSitterLib.ts_node_string"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ToString: string   ;

      /// <returns><!-- drag-lint:auto -->Integer -- Observed: ts_node_child_count(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Cfg.FindClassDecl (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build.AbsoluteTargetIdx (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build.AddArgs (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Diagnostics.AstChecks.CyclomaticCountDecisions (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit.Visit (DRagLint.Diagnostics.AstChecks.pas) (+118 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_child_count</para>
      /// <seealso cref="TreeSitterLib.ts_node_child_count"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.EndByte"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ChildCount: Integer            ;
      /// <summary><!-- drag-lint:auto sum -->TTSNodeHelper</summary>
      /// <param name="AIndex"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->TTSNode -- Observed: ts_node_child(Self,
      /// AIndex).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Cfg.FindClassDecl (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build.AbsoluteTargetIdx (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build.AddArgs (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Diagnostics.AstChecks.CyclomaticCountDecisions (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit.Visit (DRagLint.Diagnostics.AstChecks.pas) (+118 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_child</para>
      /// <seealso cref="TreeSitterLib.ts_node_child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.EndByte"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Child(AIndex: Integer): TTSNode;
      /// <returns><!-- drag-lint:auto -->TTSNode -- Observed: ts_node_next_sibling(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_node_next_sibling</para>
      /// <seealso cref="TreeSitterLib.ts_node_next_sibling"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function NextSibling: TTSNode;
      /// <returns><!-- drag-lint:auto -->TTSNode -- Observed: ts_node_prev_sibling(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_node_prev_sibling</para>
      /// <seealso cref="TreeSitterLib.ts_node_prev_sibling"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function PrevSibling: TTSNode;

      /// <returns><!-- drag-lint:auto -->Integer -- Observed:
      /// ts_node_named_child_count(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Cfg.CfgFindProcs.Walk (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.ClassChainLacks (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DeclaredTypeOfVar.TyperefNameOf (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DeclaredTypeOfVar.Visit (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DottedCalleeText (DRagLint.Analysis.Cfg.pas) (+445 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_named_child_count</para>
      /// <seealso cref="TreeSitterLib.ts_node_named_child_count"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function NamedChildCount: Integer            ;
      /// <param name="AIndex"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->TTSNode -- Observed: ts_node_named_child(Self,
      /// AIndex).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Cfg.CfgFindProcs.Walk (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.ClassChainLacks (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DeclaredTypeOfVar.TyperefNameOf (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DeclaredTypeOfVar.Visit (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DottedCalleeText (DRagLint.Analysis.Cfg.pas) (+450 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_named_child</para>
      /// <seealso cref="TreeSitterLib.ts_node_named_child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function NamedChild(AIndex: Integer): TTSNode;
      /// <returns><!-- drag-lint:auto -->TTSNode -- Observed:
      /// ts_node_next_named_sibling(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Diagnostics.FlowChecks.OverwrittenInsideFollowingTry (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Diagnostics.FlowChecks.ProtectedByFollowingTry (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Fix.Stmt.FixBareExcept (DRagLint.Fix.Stmt.pas), DRagLint.Fix.Stmt.FixCreateInsideTry (DRagLint.Fix.Stmt.pas)</para>
      /// <para>Calls: TreeSitterLib.ts_node_next_named_sibling</para>
      /// <seealso cref="TreeSitterLib.ts_node_next_named_sibling"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function NextNamedSibling: TTSNode;
      /// <returns><!-- drag-lint:auto -->TTSNode -- Observed:
      /// ts_node_prev_named_sibling(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_node_prev_named_sibling</para>
      /// <seealso cref="TreeSitterLib.ts_node_prev_named_sibling"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function PrevNamedSibling: TTSNode;

      /// <returns><!-- drag-lint:auto -->UInt32 -- Observed: ts_node_start_byte(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Cfg.NodeStr (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Flow.Lattices.ApplyWithRecordEntity (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.AssignmentTargetIndex (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.CollectReadsAndCallDefs.Walk (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.FreedOperandVar (DRagLint.Analysis.Flow.Lattices.pas) (+199 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_start_byte</para>
      /// <seealso cref="TreeSitterLib.ts_node_start_byte"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function StartByte : UInt32;
      /// <returns><!-- drag-lint:auto -->TTSPoint -- Observed:
      /// TTSPoint(ts_node_start_point(Self)); ts_node_start_point(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build.AddArgs (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build.AddDeclVars (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build.AddInline (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits.HandleProc (DRagLint.Diagnostics.AstChecks.pas) (+148 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_start_point, TTSPoint</para>
      /// <seealso cref="TreeSitterLib.ts_node_start_point"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function StartPoint: TTSPoint;
      /// <returns><!-- drag-lint:auto -->UInt32 -- Observed: ts_node_end_byte(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Cfg.NodeStr (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Flow.Lattices.NodeStr (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build.AddInlineVars (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TRoutineVarTable.Build.EnclosingListEnd (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Convert.DfmReemit.NodeText (DRagLint.Convert.DfmReemit.pas) (+113 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_end_byte</para>
      /// <seealso cref="TreeSitterLib.ts_node_end_byte"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function EndByte   : UInt32;
      /// <returns><!-- drag-lint:auto -->TTSPoint -- Observed:
      /// TTSPoint(ts_node_end_point(Self)); ts_node_end_point(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits.HandleProc (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckHardcodedPath.FindDefProcNamed.Walk (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRoutineMetrics.CheckProc (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors.Visit (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.DeadCodeChecks.TDeadCodeChecker.Check (DRagLint.Diagnostics.DeadCodeChecks.pas) (+48 more)</para>
      /// <para>Calls: TreeSitterLib.ts_node_end_point, TTSPoint</para>
      /// <seealso cref="TreeSitterLib.ts_node_end_point"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function EndPoint  : TTSPoint;

      /// <param name="AFieldName"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TTSNode -- Observed:
      /// ts_node_child_by_field_name(Self, PAnsiChar(ansiFieldName),
      /// Length(ansiFieldName)).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Analysis.Cfg.DeclaredTypeOfVar.Visit (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.DottedCalleeText (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.FindClassDecl (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.ForLoopAlwaysExecutes (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.IsValuedExit (DRagLint.Analysis.Cfg.pas) (+507 more)</para>
      /// <para>Calls: AnsiString, PAnsiChar, TreeSitterLib.ts_node_child_by_field_name</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="TreeSitterLib.ts_node_child_by_field_name"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ChildByField(const AFieldName: string): TTSNode; overload;
      /// <param name="AFieldId"><!-- drag-lint:auto type -->const UInt32</param>
      /// <returns><!-- drag-lint:auto -->TTSNode -- Observed:
      /// ts_node_child_by_field_id(Self, AFieldId).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_node_child_by_field_id</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="TreeSitterLib.ts_node_child_by_field_id"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ChildByField(const AFieldId: UInt32): TTSNode; overload  ;

      /// <returns><!-- drag-lint:auto -->UInt32 -- Observed:
      /// ts_node_descendant_count(Self).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_node_descendant_count</para>
      /// <seealso cref="TreeSitterLib.ts_node_descendant_count"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.EndByte"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DescendantCount: UInt32;

      /// <param name="A"><!-- drag-lint:auto type -->TTSNode</param>
      /// <param name="B"><!-- drag-lint:auto type -->TTSNode</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ts_node_eq(A, B).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: TreeSitterLib.ts_node_eq</para>
      /// <seealso cref="TreeSitterLib.ts_node_eq"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.DescendantCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class operator Equal(A: TTSNode; B: TTSNode): Boolean;
    end; // record

    TTSPointHelper = record helper for TTSPoint
      /// <summary><!-- drag-lint:auto sum -->TTSPointHelper</summary>
      /// <returns><!-- drag-lint:auto -->string -- Observed: Format('(%d, %d)', [row,
      /// column]).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: Format</para>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ToString: string;
    end;

implementation

{ TTSParser }

constructor TTSParser.Create;
begin
  FParser:= ts_parser_new;
end;

destructor TTSParser.Destroy;
begin
  ts_parser_delete(FParser);
  inherited;
end;

function TTSParser.GetLanguage: PTSLanguage;
begin
  Result:= ts_parser_language(FParser);
end;

type
  PTSInputReadPayLoad = ^TSInputReadPayLoad;
  TSInputReadPayLoad  = record
    ParseReadFunction: TTSParseReadFunction;
    Buffer           : TBytes              ;
  end;

function TSInputRead(payload: Pointer; byte_index: UInt32; position: TSPoint; var bytes_read: UInt32): PAnsiChar; cdecl;
begin
  PTSInputReadPayLoad(payload)^.Buffer:= PTSInputReadPayLoad(payload)^.ParseReadFunction(byte_index, position, bytes_read);
  if Length(PTSInputReadPayLoad(payload)^.Buffer) = 0 then Result:= nil else Result:= PAnsiChar(@PTSInputReadPayLoad(payload)^.Buffer[0]);
end;

function TTSParser.Parse(AParseReadFunction: TTSParseReadFunction; AEncoding: TTSInputEncoding; const AOldTree: TTSTree): TTSTree;
var
  tsi    : TSInput           ;
  payload: TSInputReadPayLoad;
begin
  payload.ParseReadFunction:= AParseReadFunction;
  tsi.payload:= @payload;
  tsi.read    := TSInputRead;
  tsi.encoding:= AEncoding;
  Result:= TTSTree.Create(ts_parser_parse(FParser, AOldTree.TreeNilSafe, tsi));
end;

function TTSParser.ParseString(const AString: string; const AOldTree: TTSTree): TTSTree;
var
  bytes: TBytes ;
  Tree : PTSTree;
  len  : Integer;
begin
  bytes:= TEncoding.Unicode.GetBytes(AString);
  len:= Length(bytes);
  if len > 0 then Tree:= ts_parser_parse_string_encoding(FParser, AOldTree.TreeNilSafe, @bytes[0], len, TSInputEncodingUTF16) else
    raise ETreeSitterException.Create('Cannot parse empty string');
  if Tree = nil then raise ETreeSitterException.Create('Faild to parse string');
  Result:= TTSTree.Create(Tree);
end;

procedure TTSParser.Reset;
begin
  ts_parser_reset(FParser);
end;

procedure TTSParser.SetLanguage(const Value: PTSLanguage);
begin
  if not ts_parser_set_language(FParser, Value) then raise ETreeSitterException.CreateFmt('Failed to set parser language to 0x%p', [Value]);
end;

{ TTSTree }

function TTSTree.Clone: TTSTree;
begin
  Result:= TTSTree.Create(ts_tree_copy(FTree));
end;

constructor TTSTree.Create(ATree: PTSTree);
begin
  FTree:= ATree;
end;

destructor TTSTree.Destroy;
begin
  if FTree <> nil then ts_tree_delete(FTree);
  inherited;
end;

function TTSTree.Language: PTSLanguage;
begin
  Result:= ts_tree_language(FTree);
end;

function TTSTree.RootNode: TTSNode;
begin
  Result:= ts_tree_root_node(FTree);
end;

function TTSTree.TreeNilSafe: PTSTree;
begin
  if Self <> nil then Result:= FTree else Result:= nil;
end;

{ TTSNodeHelper }

function TTSNodeHelper.Child(AIndex: Integer): TTSNode;
begin
  Result:= ts_node_child(Self, AIndex);
end;

function TTSNodeHelper.ChildByField(const AFieldId: UInt32): TTSNode;
begin
  Result:= ts_node_child_by_field_id(Self, AFieldId);
end;

function TTSNodeHelper.ChildByField(const AFieldName: string): TTSNode;
var
  ansiFieldName: AnsiString;
begin
  ansiFieldName:= AnsiString(AFieldName);
  Result:= ts_node_child_by_field_name(Self, PAnsiChar(ansiFieldName), Length(ansiFieldName));
end;

function TTSNodeHelper.ChildCount: Integer;
begin
  Result:= ts_node_child_count(Self);
end;

function TTSNodeHelper.DescendantCount: UInt32;
begin
  Result:= ts_node_descendant_count(Self);
end;

function TTSNodeHelper.EndByte: UInt32;
begin
  Result:= ts_node_end_byte(Self);
end;

function TTSNodeHelper.EndPoint: TTSPoint;
begin
  {$IFDEF WIN32}
  Result:= TTSPoint(ts_node_end_point(Self));
  {$ELSE}
  Result:= ts_node_end_point(Self);
  {$ENDIF}
end;

class operator TTSNodeHelper.Equal(A, B: TTSNode): Boolean;
begin
  Result:= ts_node_eq(A, B);
end;

function TTSNodeHelper.GrammarSymbol: TSSymbol;
begin
  Result:= ts_node_grammar_symbol(Self);
end;

function TTSNodeHelper.GrammarType: string;
begin
  Result:= string(AnsiString(ts_node_grammar_type(Self)));
end;

function TTSNodeHelper.HasChanges: Boolean;
begin
  Result:= ts_node_has_changes(Self);
end;

function TTSNodeHelper.HasError: Boolean;
begin
  Result:= ts_node_has_error(Self);
end;

function TTSNodeHelper.IsError: Boolean;
begin
  Result:= ts_node_is_error(Self);
end;

function TTSNodeHelper.IsExtra: Boolean;
begin
  Result:= ts_node_is_extra(Self);
end;

function TTSNodeHelper.IsMissing: Boolean;
begin
  Result:= ts_node_is_missing(Self);
end;

function TTSNodeHelper.IsNamed: Boolean;
begin
  Result:= ts_node_is_named(Self);
end;

function TTSNodeHelper.IsNull: Boolean;
begin
  Result:= ts_node_is_null(Self);
end;

function TTSNodeHelper.Language: PTSLanguage;
begin
  Result:= ts_node_language(Self);
end;

function TTSNodeHelper.NamedChild(AIndex: Integer): TTSNode;
begin
  Result:= ts_node_named_child(Self, AIndex);
end;

function TTSNodeHelper.NamedChildCount: Integer;
begin
  Result:= ts_node_named_child_count(Self);
end;

function TTSNodeHelper.NextNamedSibling: TTSNode;
begin
  Result:= ts_node_next_named_sibling(Self);
end;

function TTSNodeHelper.NextSibling: TTSNode;
begin
  Result:= ts_node_next_sibling(Self);
end;

function TTSNodeHelper.NodeType: string;
begin
  Result:= string(AnsiString(ts_node_type(Self)));
end;

function TTSNodeHelper.Parent: TTSNode;
begin
  Result:= ts_node_parent(Self);
end;

function TTSNodeHelper.PrevNamedSibling: TTSNode;
begin
  Result:= ts_node_prev_named_sibling(Self);
end;

function TTSNodeHelper.PrevSibling: TTSNode;
begin
  Result:= ts_node_prev_sibling(Self);
end;

function TTSNodeHelper.StartByte: UInt32;
begin
  Result:= ts_node_start_byte(Self);
end;

function TTSNodeHelper.StartPoint: TTSPoint;
begin
  {$IFDEF WIN32}
  Result:= TTSPoint(ts_node_start_point(Self));
  {$ELSE}
  Result:= ts_node_start_point(Self);
  {$ENDIF}
end;

function TTSNodeHelper.Symbol: TSSymbol;
begin
  Result:= ts_node_symbol(Self);
end;

function TTSNodeHelper.ToString: string;
var
  pach: PAnsiChar;
begin
  pach:= ts_node_string(Self);
  Result:= string(AnsiString(pach));
  FreeMem(pach);
end;

{ TTSPointHelper }

function TTSPointHelper.ToString: string;
begin
  Result:= Format('(%d, %d)', [row, column]);
end;

{ TTSLanguageHelper }

function TTSLanguageHelper.FieldCount: UInt32;
begin
  Result:= ts_language_field_count(@Self);
end;

function TTSLanguageHelper.GetFieldId(const AFieldName: string): TSFieldId;
var
  ansiFieldName: AnsiString;
begin
  ansiFieldName:= AnsiString(AFieldName);
  Result:= ts_language_field_id_for_name(@Self, PAnsiChar(ansiFieldName), Length(ansiFieldName));
end;

function TTSLanguageHelper.GetFieldName(AFieldId: TSFieldId): string;
begin
  Result:= string(AnsiString(ts_language_field_name_for_id(@Self, AFieldId)));
end;

function TTSLanguageHelper.GetSymbolForName(const ASymbolName: string; AIsNamed: Boolean): TSSymbol;
var
  ansiSymbolName: AnsiString;
begin
  ansiSymbolName:= AnsiString(ASymbolName);
  Result:= ts_language_symbol_for_name(@Self, PAnsiChar(ansiSymbolName), Length(ansiSymbolName), AIsNamed);
end;

function TTSLanguageHelper.GetSymbolName(ASymbol: TSSymbol): string;
begin
  Result:= string(AnsiString(ts_language_symbol_name(@Self, ASymbol)));
end;

function TTSLanguageHelper.GetSymbolType(ASymbol: TSSymbol): TSSymbolType;
begin
  Result:= ts_language_symbol_type(@Self, ASymbol);
end;

function TTSLanguageHelper.NextState(AState: TSStateId; ASymbol: TSSymbol): TSStateId;
begin
  Result:= ts_language_next_state(@Self, AState, ASymbol);
end;

function TTSLanguageHelper.SymbolCount: UInt32;
begin
  Result:= ts_language_symbol_count(@Self);
end;

function TTSLanguageHelper.Version: UInt32;
begin
  Result:= ts_language_version(@Self);
end;

{ TTSTreeCursor }

constructor TTSTreeCursor.Create(ANode: TTSNode);
begin
  FTreeCursor:= ts_tree_cursor_new(ANode);
end;

constructor TTSTreeCursor.Create(ACursorToCopy: TTSTreeCursor);
begin
  FTreeCursor:= ts_tree_cursor_copy(ACursorToCopy.TreeCursor);
end;

destructor TTSTreeCursor.Destroy;
begin
  ts_tree_cursor_delete(@FTreeCursor);
  FillChar(FTreeCursor, SizeOf(FTreeCursor), 0);
  inherited;
end;

function TTSTreeCursor.GetCurrentDepth: UInt32;
begin
  Result:= ts_tree_cursor_current_depth(@FTreeCursor);
end;

function TTSTreeCursor.GetCurrentDescendantIndex: UInt32;
begin
  Result:= ts_tree_cursor_current_descendant_index(@FTreeCursor);
end;

function TTSTreeCursor.GetCurrentFieldId: TSFieldId;
begin
  Result:= ts_tree_cursor_current_field_id(@FTreeCursor);
end;

function TTSTreeCursor.GetCurrentFieldName: string;
begin
  Result:= string(AnsiString(ts_tree_cursor_current_field_name(@FTreeCursor)));
end;

function TTSTreeCursor.GetCurrentNode: TTSNode;
begin
  Result:= ts_tree_cursor_current_node(@FTreeCursor);
end;

function TTSTreeCursor.GetTreeCursor: PTSTreeCursor;
begin
  Result:= @FTreeCursor;
end;

procedure TTSTreeCursor.GotoDescendant(AGoalDescendantIndex: UInt32);
begin
  ts_tree_cursor_goto_descendant(@FTreeCursor, AGoalDescendantIndex);
end;

function TTSTreeCursor.GotoFirstChild: Boolean;
begin
  Result:= ts_tree_cursor_goto_first_child(@FTreeCursor);
end;

function TTSTreeCursor.GotoFirstChildForGoal(AGoalPoint: TTSPoint): Int64;
begin
  Result:= ts_tree_cursor_goto_first_child_for_point(@FTreeCursor, AGoalPoint);
end;

function TTSTreeCursor.GotoFirstChildForGoal(AGoalByte: UInt32): Int64;
begin
  Result:= ts_tree_cursor_goto_first_child_for_byte(@FTreeCursor, AGoalByte);
end;

function TTSTreeCursor.GotoLastChild: Boolean;
begin
  Result:= ts_tree_cursor_goto_last_child(@FTreeCursor);
end;

function TTSTreeCursor.GotoNextSibling: Boolean;
begin
  Result:= ts_tree_cursor_goto_next_sibling(@FTreeCursor);
end;

function TTSTreeCursor.GotoParent: Boolean;
begin
  Result:= ts_tree_cursor_goto_parent(@FTreeCursor);
end;

function TTSTreeCursor.GotoPrevSibling: Boolean;
begin
  Result:= ts_tree_cursor_goto_previous_sibling(@FTreeCursor);
end;

procedure TTSTreeCursor.Reset(ACursor: TTSTreeCursor);
begin
  ts_tree_cursor_reset_to(@FTreeCursor, ACursor.TreeCursor);
end;

procedure TTSTreeCursor.Reset(ANode: TTSNode);
begin
  ts_tree_cursor_reset(@FTreeCursor, ANode);
end;

{ memory management functions }

function ts_malloc_func(SizeOf: NativeUInt): Pointer; cdecl;
begin
  GetMem(Result, SizeOf);
end;

function ts_calloc_func(nitems: NativeUInt; size: NativeUInt): Pointer; cdecl;
begin
  GetMem(Result, nitems * size);
  FillChar(Result^, nitems * size, 0);
end;

procedure ts_free_func(ptr: Pointer); cdecl;
begin
  FreeMem(ptr);
end;

function ts_realloc_func(ptr: Pointer; SizeOf: NativeUInt): Pointer; cdecl;
begin
  Result:= ptr;
  ReallocMem(Result, SizeOf);
end;

initialization
//provide our own MM functions so we can free data allocated by TS with our FreeMem
ts_set_allocator(@ts_malloc_func, @ts_calloc_func, @ts_realloc_func, @ts_free_func);
finalization
end.
