unit TreeSitter.Query;

interface

uses
  TreeSitterLib
  , TreeSitter
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Lint.QueryRules.TQueryRule.Create (DRagLint.Lint.QueryRules.pas), declaration (TreeSitter.Query.pas), TreeSitter.Query.TTSQuery.Create (TreeSitter.Query.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTSQueryError             = TreeSitterLib.TSQueryError;
  TTSQueryPredicateStep     = TreeSitterLib.TSQueryPredicateStep;
  TTSQueryPredicateStepType = TreeSitterLib.TSQueryPredicateStepType;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Lint.QueryRules.AllPredicatesPass (DRagLint.Lint.QueryRules.pas), declaration (TreeSitter.Query.pas), TreeSitter.Query.TTSQuery.PredicatesForPattern (TreeSitter.Query.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTSQueryPredicateStepArray = array of TTSQueryPredicateStep;
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (TreeSitter.Query.pas), TreeSitter.Query.TTSQuery.QuantifierForCapture (TreeSitter.Query.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTSQuantifier              = TreeSitterLib.TSQuantifier;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Lint.QueryRules.pas), DRagLint.Lint.QueryRules.TQueryRule.Create (DRagLint.Lint.QueryRules.pas), declaration (TreeSitter.Query.pas), TreeSitter.Query.TTSQueryCursor.Execute (TreeSitter.Query.pas)
  /// Used in units: DRagLint.Lint.QueryRules, TreeSitter.Query
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTSQuery = class
    strict private
      FQuery: PTSQuery;
    public
      /// <param name="ALanguage"><!-- drag-lint:auto type -->PTSLanguage</param>
      /// <param name="ASource"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AErrorOffset"><!-- drag-lint:auto type -->var UInt32</param>
      /// <param name="AErrorType"><!-- drag-lint:auto type -->var TTSQueryError</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.QueryRules.TQueryRule.Create (DRagLint.Lint.QueryRules.pas)
      /// Calls: AnsiString, PAnsiChar, TreeSitterLib.ts_query_new
      /// virtual
      /// constructor
      /// Writes: FQuery
      /// <seealso cref="TreeSitterLib.ts_query_new"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureCount"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.PatternCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(ALanguage: PTSLanguage; const ASource: string; var AErrorOffset: UInt32; var AErrorType: TTSQueryError); virtual;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_delete
      /// Reads: FQuery
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_delete"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureCount"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.PatternCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;

      /// <returns><!-- drag-lint:auto -->Observed: ts_query_pattern_count(FQuery).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_pattern_count
      /// Reads: FQuery
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_pattern_count"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureCount"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function PatternCount: UInt32;
      /// <summary><!-- drag-lint:auto -->TTSQuery</summary>
      /// <returns><!-- drag-lint:auto -->Observed: ts_query_capture_count(FQuery).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_capture_count
      /// Reads: FQuery
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_capture_count"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.PatternCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function CaptureCount: UInt32;
      /// <returns><!-- drag-lint:auto -->Observed: ts_query_string_count(FQuery).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_string_count
      /// Reads: FQuery
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_string_count"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureCount"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function StringCount : UInt32;

      /// <param name="APatternIndex"><!-- drag-lint:auto type -->UInt32</param>
      /// <returns><!-- drag-lint:auto -->Observed:
      /// ts_query_start_byte_for_pattern(FQuery, APatternIndex).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_start_byte_for_pattern
      /// Reads: FQuery
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_start_byte_for_pattern"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureCount"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function StartByteForPattern (APatternIndex: UInt32): UInt32;
      /// <param name="APatternIndex"><!-- drag-lint:auto type -->UInt32</param>
      /// <returns><!-- drag-lint:auto type -->TTSQueryPredicateStepArray</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.QueryRules.AllPredicatesPass (DRagLint.Lint.QueryRules.pas)
      /// Calls: Move, TreeSitterLib.ts_query_predicates_for_pattern
      /// Reads: FQuery
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_predicates_for_pattern"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureCount"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function PredicatesForPattern(APatternIndex: UInt32): TTSQueryPredicateStepArray;

      /// <param name="ACaptureIndex"><!-- drag-lint:auto type -->UInt32</param>
      /// <returns><!-- drag-lint:auto -->Observed: string(res).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)
      /// Calls: Move, TreeSitterLib.ts_query_capture_name_for_id
      /// Reads: FQuery
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_capture_name_for_id"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureCount"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.PatternCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function CaptureNameForID(ACaptureIndex: UInt32): string;
      /// <param name="AStringIndex"><!-- drag-lint:auto type -->UInt32</param>
      /// <returns><!-- drag-lint:auto -->Observed: string(res).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.QueryRules.AllPredicatesPass (DRagLint.Lint.QueryRules.pas)
      /// Calls: Move, TreeSitterLib.ts_query_string_value_for_id
      /// Reads: FQuery
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_string_value_for_id"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureCount"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function StringValueForID(AStringIndex : UInt32): string;

      /// <param name="APatternIndex"><!-- drag-lint:auto type -->UInt32</param>
      /// <param name="ACaptureIndex"><!-- drag-lint:auto type -->UInt32</param>
      /// <returns><!-- drag-lint:auto -->Observed:
      /// ts_query_capture_quantifier_for_id(FQuery, APatternIndex, ACaptureIndex).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_capture_quantifier_for_id
      /// Reads: FQuery
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_capture_quantifier_for_id"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureCount"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function QuantifierForCapture(APatternIndex, ACaptureIndex: UInt32): TTSQuantifier;

      property Query: PTSQuery read FQuery;
  end;

  TTSQueryCapture      = TreeSitterLib.TSQueryCapture;
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Lint.QueryRules.ResolveCaptureText (DRagLint.Lint.QueryRules.pas), DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas), declaration (TreeSitter.Query.pas), TreeSitter.Query.TTSQueryMatchHelper.CapturesArray (TreeSitter.Query.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTSQueryCaptureArray = array of TTSQueryCapture;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas), declaration (TreeSitter.Query.pas), TreeSitter.Query.TTSQueryCursor.NextCapture (TreeSitter.Query.pas), TreeSitter.Query.TTSQueryCursor.NextMatch (TreeSitter.Query.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTSQueryMatch = TreeSitterLib.TSQueryMatch;

  TTSQueryMatchHelper = record helper for TTSQueryMatch
    /// <summary><!-- drag-lint:auto -->TTSQueryMatchHelper</summary>
    /// <returns><!-- drag-lint:auto type -->TTSQueryCaptureArray</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Calls: Move
    /// Pure
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CapturesArray: TTSQueryCaptureArray;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)
  /// Used in units: DRagLint.Lint.QueryRules
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTSQueryCursor = class
    strict private
      FQueryCursor: PTSQueryCursor;

      /// <returns><!-- drag-lint:auto -->Observed:
      /// ts_query_cursor_match_limit(FQueryCursor).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_cursor_match_limit
      /// Reads: FQueryCursor
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_cursor_match_limit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.DidExceedMatchLimit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Execute"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GetMatchLimit: UInt32;
      /// <param name="Value"><!-- drag-lint:auto type -->const UInt32</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_cursor_set_match_limit
      /// Reads: FQueryCursor
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_cursor_set_match_limit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.DidExceedMatchLimit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Execute"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetMatchLimit(const Value: UInt32);
    public
      /// <summary><!-- drag-lint:auto -->TTSQueryCursor</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)
      /// virtual
      /// constructor
      /// Writes: FQueryCursor
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.DidExceedMatchLimit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Execute"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.GetMatchLimit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.NextCapture"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create; virtual;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_cursor_delete
      /// Reads: FQueryCursor
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_cursor_delete"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.DidExceedMatchLimit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Execute"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.GetMatchLimit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;

      /// <param name="AQuery"><!-- drag-lint:auto type -->TTSQuery</param>
      /// <param name="ANode"><!-- drag-lint:auto type -->TTSNode</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)
      /// Calls: TreeSitterLib.ts_query_cursor_exec
      /// Reads: FQueryCursor
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_cursor_exec"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.DidExceedMatchLimit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.GetMatchLimit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Execute(AQuery: TTSQuery; ANode: TTSNode);
      /// <returns><!-- drag-lint:auto -->Observed:
      /// ts_query_cursor_did_exceed_match_limit(FQueryCursor).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_cursor_did_exceed_match_limit
      /// Reads: FQueryCursor
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_cursor_did_exceed_match_limit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Execute"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.GetMatchLimit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DidExceedMatchLimit: Boolean;
      /// <param name="AMaxStartDepth"><!-- drag-lint:auto type -->UInt32</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_cursor_set_max_start_depth
      /// Reads: FQueryCursor
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_cursor_set_max_start_depth"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.DidExceedMatchLimit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Execute"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetMaxStartDepth(AMaxStartDepth: UInt32);

      /// <param name="AMatch"><!-- drag-lint:auto type -->var TTSQueryMatch</param>
      /// <returns><!-- drag-lint:auto -->Observed:
      /// ts_query_cursor_next_match(FQueryCursor, AMatch).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)
      /// Calls: TreeSitterLib.ts_query_cursor_next_match
      /// Reads: FQueryCursor
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_cursor_next_match"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.DidExceedMatchLimit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Execute"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function NextMatch(var AMatch: TTSQueryMatch): Boolean                             ;
      /// <param name="AMatch"><!-- drag-lint:auto type -->var TTSQueryMatch</param>
      /// <param name="ACaptureIndex"><!-- drag-lint:auto type -->var UInt32</param>
      /// <returns><!-- drag-lint:auto -->Observed:
      /// ts_query_cursor_next_capture(FQueryCursor, AMatch, ACaptureIndex).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TreeSitterLib.ts_query_cursor_next_capture
      /// Reads: FQueryCursor
      /// Pure
      /// <seealso cref="TreeSitterLib.ts_query_cursor_next_capture"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Create"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Destroy"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.DidExceedMatchLimit"/>
      /// <seealso cref="TreeSitter.Query.TTSQueryCursor.Execute"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function NextCapture(var AMatch: TTSQueryMatch; var ACaptureIndex: UInt32): Boolean;

      property QueryCursor: PTSQueryCursor read FQueryCursor;
      property MatchLimit : UInt32 read GetMatchLimit write SetMatchLimit;
  end;

implementation

{ TTSQuery }

function TTSQuery.CaptureCount: UInt32;
begin
  Result:= ts_query_capture_count(FQuery);
end;

function TTSQuery.CaptureNameForID(ACaptureIndex: UInt32): string;
var
  pac: PAnsiChar ;
  len: UInt32    ;
  res: AnsiString;
begin
  pac:= ts_query_capture_name_for_id(FQuery, ACaptureIndex, len);
  SetLength(res, len);
  if len > 0 then Move(pac[0], res[1], len * SizeOf(pac[0]));
  Result:= string(res);
end;

constructor TTSQuery.Create(ALanguage: PTSLanguage; const ASource: string; var AErrorOffset: UInt32; var AErrorType: TTSQueryError);
var
  ansiSource: AnsiString;
begin
  ansiSource:= AnsiString(ASource);
  FQuery:= ts_query_new(ALanguage, PAnsiChar(ansiSource), Length(ansiSource), AErrorOffset, AErrorType);
end;

destructor TTSQuery.Destroy;
begin
  ts_query_delete(FQuery);
  inherited;
end;

function TTSQuery.PatternCount: UInt32;
begin
  Result:= ts_query_pattern_count(FQuery);
end;

function TTSQuery.PredicatesForPattern( APatternIndex: UInt32): TTSQueryPredicateStepArray;
var
  count: UInt32                    ;
  parr : PTSQueryPredicateStepArray;
begin
  count:= 0;
  parr:= ts_query_predicates_for_pattern(FQuery, APatternIndex, count);
  if (parr <> nil) and (count > 0) then
  begin
    SetLength(Result, count);
    Move(parr[0], Result[0], count * SizeOf(Result[0]));
  end;
end;

function TTSQuery.QuantifierForCapture(APatternIndex, ACaptureIndex: UInt32): TTSQuantifier;
begin
  Result:= ts_query_capture_quantifier_for_id(FQuery, APatternIndex, ACaptureIndex);
end;

function TTSQuery.StartByteForPattern(APatternIndex: UInt32): UInt32;
begin
  Result:= ts_query_start_byte_for_pattern(FQuery, APatternIndex);
end;

function TTSQuery.StringCount: UInt32;
begin
  Result:= ts_query_string_count(FQuery);
end;

function TTSQuery.StringValueForID(AStringIndex: UInt32): string;
var
  pac: PAnsiChar ;
  len: UInt32    ;
  res: AnsiString;
begin
  pac:= ts_query_string_value_for_id(FQuery, AStringIndex, len);
  SetLength(res, len);
  if len > 0 then Move(pac[0], res[1], len * SizeOf(pac[0]));
  Result:= string(res);
end;

{ TTSQueryCursor }

constructor TTSQueryCursor.Create;
begin
  FQueryCursor:= ts_query_cursor_new;
end;

destructor TTSQueryCursor.Destroy;
begin
  ts_query_cursor_delete(FQueryCursor);
  inherited;
end;

function TTSQueryCursor.DidExceedMatchLimit: Boolean;
begin
  Result:= ts_query_cursor_did_exceed_match_limit(FQueryCursor);
end;

procedure TTSQueryCursor.Execute(AQuery: TTSQuery; ANode: TTSNode);
begin
  ts_query_cursor_exec(FQueryCursor, AQuery.Query, ANode);
end;

function TTSQueryCursor.GetMatchLimit: UInt32;
begin
  Result:= ts_query_cursor_match_limit(FQueryCursor);
end;

function TTSQueryCursor.NextCapture(var AMatch: TTSQueryMatch; var ACaptureIndex: UInt32): Boolean;
begin
  Result:= ts_query_cursor_next_capture(FQueryCursor, AMatch, ACaptureIndex);
end;

function TTSQueryCursor.NextMatch(var AMatch: TTSQueryMatch): Boolean;
begin
  Result:= ts_query_cursor_next_match(FQueryCursor, AMatch);
end;

procedure TTSQueryCursor.SetMatchLimit(const Value: UInt32);
begin
  ts_query_cursor_set_match_limit(FQueryCursor, Value);
end;

procedure TTSQueryCursor.SetMaxStartDepth(AMaxStartDepth: UInt32);
begin
  ts_query_cursor_set_max_start_depth(FQueryCursor, AMaxStartDepth);
end;

{ TTSQueryMatchHelper }

function TTSQueryMatchHelper.CapturesArray: TTSQueryCaptureArray;
begin
  SetLength(Result, capture_count);
  if capture_count > 0 then Move(captures[0], Result[0], capture_count * SizeOf(captures[0]));
end;

end.
