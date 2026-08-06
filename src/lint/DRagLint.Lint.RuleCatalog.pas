unit DRagLint.Lint.RuleCatalog;

{ Single machine-readable catalog of every drag-lint rule. The BUILT-IN registry
  below is the one place that knows each built-in's category / title / default
  severity / default-enabled / parameters. External .scm rules are merged in by
  BuildCatalog (source:"scm"); their severity/message come from the sidecar json
  and their category from ScmCategory(). Pure metadata -- no analysis logic. }

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections, System.Generics.Defaults,
  System.JSON, System.IOUtils;

type
  /// <summary>A single configurable parameter of a rule (threshold or naming knob).</summary>
  TRuleParam = record
    Name      : string;  // config key (e.g. 'threshold', 'class_prefix')
    ParamType : string;  // 'int' | 'string' | 'stringlist' | 'bool'
    DefaultVal: string;  // textual default
  end;

  /// <summary>One catalogued rule.</summary>
  TRuleInfo = record
    Id             : string;
    Category       : string;  // one of the 12 canonical buckets
    Title          : string;
    DefaultSeverity: string;  // 'hint' | 'info' | 'warning' | 'error'
    Source         : string;  // 'builtin' | 'scm'
    DefaultEnabled : Boolean;
    Params         : TArray<TRuleParam>;
  end;

  /// <summary>Per-category and total rule counts for the catalog summary.</summary>
  TCatalogSummary = record
    Total      : Integer;
    Categories : Integer;
    PerCategory: TArray<TPair<string, Integer>>;  // (category, count), category order = first-seen
  end;

  TRuleCatalog = class
  public
    /// <summary>The in-code registry of all built-in rules (no .scm).</summary>
    class function BuiltinRegistry: TArray<TRuleInfo>; static;
    /// <summary>Full catalog: built-ins + external .scm rules from ARulesDir
    /// (default &lt;exe-dir&gt;\rules). Deduped by id (builtin wins). Sorted by
    /// (category, id). When ACategory&lt;&gt;'' only that category is returned.</summary>
    class function BuildCatalog(const ARulesDir: string = '';
      const ACategory: string = ''): TArray<TRuleInfo>; static;
    /// <summary>Totals + per-category counts over ACatalog.</summary>
    class function Summarize(const ACatalog: TArray<TRuleInfo>): TCatalogSummary; static;
    /// <summary>Category bucket for an external .scm rule id; 'other' if unmapped.</summary>
    class function ScmCategory(const AId: string): string; static;
  end;

implementation

function MkParam(const AName, AType, ADefault: string): TRuleParam;
begin
  Result.Name:= AName; Result.ParamType:= AType; Result.DefaultVal:= ADefault;
end;

class function TRuleCatalog.BuiltinRegistry: TArray<TRuleInfo>;
var
  L: TList<TRuleInfo>;
  procedure B(const AId, ACat, ASev, ATitle: string; AEnabled: Boolean = True;
    const AParams: TArray<TRuleParam> = nil);
  var R: TRuleInfo;
  begin
    R.Id:= AId; R.Category:= ACat; R.DefaultSeverity:= ASev; R.Title:= ATitle;
    R.Source:= 'builtin'; R.DefaultEnabled:= AEnabled; R.Params:= AParams;
    L.Add(R);
  end;
begin
  L:= TList<TRuleInfo>.Create;
  try
    { --- bug-patterns --- }
    B('syntax-error',                  'bug-patterns', 'error',   'Source has a syntax error');
    B('unbalanced-begin-end',          'bug-patterns', 'warning', 'Unbalanced begin/end');
    B('raise-in-finally',              'bug-patterns', 'warning', 'raise inside a finally block masks the in-flight exception');
    B('code-after-exit',               'bug-patterns', 'warning', 'Unreachable code after Exit/raise/Break/Continue/Halt');
    B('control-flow-in-finally',       'bug-patterns', 'warning', 'Exit/Break/Continue/Halt inside a finally block');
    B('missing-inherited-ctor',        'bug-patterns', 'warning', 'Constructor without an inherited call');
    B('missing-inherited-dtor',        'bug-patterns', 'warning', 'Destructor without an inherited call');
    B('float-equality-comparison',     'bug-patterns', 'warning', 'Floating-point value compared with =');
    B('length-zero-compare',           'bug-patterns', 'info',    'Length(s) compared to 0 -- use s = '''' / s <> ''''');
    B('string-equality-comparison',    'bug-patterns', 'info',    'String compared with = -- consider SameText/SameStr semantics');
    B('format-argument-count',         'bug-patterns', 'error',   'Format() argument count does not match the specifiers');
    B('format-specifier-type-mismatch','bug-patterns', 'error',   'Format() specifier type does not match the literal argument');
    B('loop-executes-at-most-once',    'bug-patterns', 'warning', 'Loop body starts with Exit/Break/raise -- runs at most once');
    B('virtual-method-in-constructor', 'bug-patterns', 'warning', 'Virtual/dynamic method called from a constructor');
    B('try-except-swallowed',          'bug-patterns', 'warning', 'try..except swallows the exception (no raise/log)');
    B('criticalsection-not-released',  'bug-patterns', 'error',   'Critical section acquired without a matching Leave/Release in finally');
    B('ui-access-in-thread',           'bug-patterns', 'warning', 'UI access inside a TThread.Execute (not thread-safe)');
    B('global-form-variable',          'bug-patterns', 'warning', 'Unit-level global variable of the form class type -- potential leak');
    B('unsafe-typecast-without-is',    'bug-patterns', 'warning', 'Hard cast TFoo(x) of an object reference with no guarding ''x is TFoo''', False); { OFF by default -- heuristic; many unguarded casts are provably safe. Opt in via "enabled" }
    B('exception-constructed-but-not-raised', 'bug-patterns', 'warning', 'Exception E...Create(...) constructed as a statement but never raised');
    B('duplicate-exception-handler',   'bug-patterns', 'warning', 'Two ''on <Class>'' handlers for the same class in one try -- the second is unreachable');
    B('repeated-else-if-condition',    'bug-patterns', 'warning', 'The same condition repeats in an if/else-if chain -- the later branch is unreachable');
    B('property-references-itself',    'bug-patterns', 'warning', 'A property''s read/write accessor is the property itself -- infinite recursion');
    B('exhaustive-enum-case',          'bug-patterns', 'warning', 'case on an enum type omits some members and has no else (store-aware; same-file enums covered without a DB)', False); { OFF by default -- a case handling a subset with no else is common; opt in via "enabled" }
    B('lossy-cast',                    'bug-patterns', 'info',    'Ansi-narrowing cast of a Unicode string -- characters outside the code page are lost (W1057)');

    { --- resource-lifetime --- }
    B('freeandnil-on-interface',       'resource-lifetime', 'warning', 'FreeAndNil on an interface reference');
    B('interface-object-mixing',       'resource-lifetime', 'info',    'Object aliased into an interface AND manually freed in the same routine -- dual-handle double-free risk', False); { OFF by default -- first-cut same-routine heuristic; opt in via "enabled" }
    B('unprotected-object-free',       'resource-lifetime', 'warning', 'Object created + freed without try-finally');
    B('use-after-free',                'resource-lifetime', 'warning', 'Object used after X.Free');
    B('destructor-without-override',   'resource-lifetime', 'warning', 'Destructor not declared ''override'' -- hides the inherited destructor (leak)');
    B('create-inside-try',             'resource-lifetime', 'warning', 'Object constructed as the first statement inside its try..finally -- construct before the try');
    B('abstract-method-instantiation', 'resource-lifetime', 'warning', 'TFoo.Create on a class with an unimplemented abstract method -- raises EAbstractError (store-backed)');

    { --- security --- }
    B('unsafe-shellexecute',           'security', 'error',   'WinExec/ShellExecute/CreateProcess with a non-literal command');
    B('path-traversal',                'security', 'warning', 'Concatenated path passed to a file API -- path traversal risk');
    B('weak-random-for-security',      'security', 'warning', 'A security-named variable is generated with System.Random (not a CSPRNG)');
    B('dfm-hardcoded-credential',      'security', 'warning', 'A credential-named DFM property (Password/Secret/ApiKey) holds a literal string');
    B('insecure-temp-file',            'security', 'warning', 'File written to a hardcoded temp path (\Temp\, C:\Temp) -- predictable/insecure location');

    { --- platform --- }
    B('win64-pointer-cast',            'platform', 'warning', 'Pointer cast to a 32-bit integer type -- unsafe on Win64');
    B('nativeint-truncation',          'platform', 'warning', 'NativeInt/pointer-sized value cast to a 32-bit integer type -- truncates on Win64');
    B('default-encoding-io',           'platform', 'warning', 'File I/O (LoadFromFile/SaveToFile, TFile.*, TStreamReader/Writer) with no explicit TEncoding -- defaults to ANSI/locale', False); { OFF by default -- FP-sanity over src/ found 65 findings across 16/103 files, mostly TFile.ReadAllText on known-ASCII project/config files (dproj/json); opt in via "enabled": ["default-encoding-io"] }

    { --- complexity (all parameterized) --- }
    B('too-many-parameters',  'complexity', 'info', 'Routine has too many parameters', True, [MkParam('threshold','int','7')]);
    B('too-many-locals',      'complexity', 'info', 'Routine has too many local variables', True, [MkParam('threshold','int','25')]);
    B('method-too-long',      'complexity', 'info', 'Routine body is too long', True, [MkParam('threshold','int','120')]);
    B('deep-nesting',         'complexity', 'info', 'Nesting is too deep', True, [MkParam('threshold','int','5')]);
    B('too-many-exit-points', 'complexity', 'info', 'Routine has too many Exit statements', True, [MkParam('threshold','int','5')]);
    B('cyclomatic-complexity','complexity', 'info', 'Cyclomatic complexity is too high', True, [MkParam('threshold','int','15')]);
    B('cognitive-complexity', 'complexity', 'info', 'Cognitive complexity is too high (nesting-weighted)', True, [MkParam('threshold','int','25')]);
    B('case-with-too-few-branches','complexity', 'hint', 'case has fewer than N branches -- an if is clearer', True, [MkParam('threshold','int','2')]);
    B('boolean-expression-complexity','complexity', 'info', 'Boolean expression has more than N and/or/xor operators', True, [MkParam('threshold','int','4')]);
    B('duplicate-code',       'complexity', 'info', 'Duplicated code block detected (Type-2, renamed-identifier tolerant)', True, [MkParam('threshold','int','90')]);
    B('unit-too-large',       'complexity', 'info', 'Unit exceeds N source lines', True, [MkParam('threshold','int','2000')]);

    { --- firedac --- }
    B('firedac-open-execsql-mismatch', 'firedac', 'warning', 'Open vs ExecSQL does not match the SQL kind');
    B('dataset-open-without-close',    'firedac', 'warning', 'Dataset opened without a matching Close in finally');
    B('field-by-name-in-loop',         'firedac', 'warning', 'FieldByName called inside a loop -- cache the field');

    { --- dead-code --- }
    B('unused-local',          'dead-code', 'hint',    'Local variable is never used');
    B('unused-parameter',      'dead-code', 'warning', 'Parameter is never used');
    B('identical-then-else',   'dead-code', 'warning', 'then and else branches are identical');
    B('referenced-never-set',  'dead-code', 'warning', 'Private field is read but never assigned');
    B('redundant-parentheses', 'dead-code', 'hint',    'Redundant parentheses around a single term or nested parens');
    B('commented-out-code',    'dead-code', 'hint',    'Comment appears to be commented-out code (assignment or call)');
    B('function-result-ignored','dead-code','hint',    'Result of a same-unit function call is discarded', False); { OFF by default -- FP-prone (builders/adders/runners legitimately discard results); opt in via "enabled" }
    B('redundant-cast',        'dead-code', 'hint',    'Cast of a value to the type it already has (no-op)');

    { --- data-flow --- }
    B('used-before-assignment','data-flow', 'warning', 'Variable used before assignment');
    B('function-result-not-set','data-flow','warning', 'Function Result not assigned on every path');
    B('out-param-not-set',     'data-flow', 'warning', 'out parameter not assigned on every path');
    B('overwrite-before-read', 'data-flow', 'info',    'Value overwritten before it is read');
    B('write-only-local',      'data-flow', 'info',    'Local assigned but never read');
    B('loop-var-after-loop',   'data-flow', 'warning', 'Loop variable used after the loop');
    B('object-leak',           'data-flow', 'info',    'Created object may leak (not freed on every path)');
    B('not-assigned-interface','data-flow', 'warning', 'Interface variable dereferenced before assignment (nil interface call)');
    B('double-free',           'data-flow', 'warning', 'Object freed twice on a path with no reassignment between (double free)');

    { --- naming (all info; two ship disabled) --- }
    B('type-name-prefix',    'naming', 'info', 'Type name must carry the configured prefix', True,
      [MkParam('class_prefix','string','T'), MkParam('exception_prefix','string','E'),
       MkParam('interface_prefix','string','I'), MkParam('pointer_prefix','string','P')]);
    B('field-name-prefix',   'naming', 'info', 'Field name must carry the configured prefix', True,
      [MkParam('field_prefix','string','F')]);
    B('param-name-prefix',   'naming', 'info', 'Parameter name must carry the configured prefix', False,
      [MkParam('param_prefix','string','')]);
    B('method-pascalcase',   'naming', 'info', 'Method/routine name casing', True,
      [MkParam('method_case','string','PascalCase')]);
    B('const-casing',        'naming', 'info', 'Constant name casing', True,
      [MkParam('const_case','stringlist','PascalCase,UPPER_CASE')]);
    B('local-var-casing',    'naming', 'info', 'Local variable name casing', True,
      [MkParam('local_case','string','PascalCase')]);
    B('unit-name-matches-file','naming','info', 'Unit name must equal the file base name');
    B('reserved-word-casing','naming', 'info', 'Reserved words must be lowercase', True,
      [MkParam('keyword_case','string','lowercase')]);
    B('hungarian-or-short-identifier','naming','info','Short or Hungarian-prefixed identifier', False,
      [MkParam('min_identifier_len','int','3'),
       MkParam('hungarian_prefixes','stringlist','lpsz,psz,sz,lp,int,str,dw,b,p,n'),
       MkParam('short_identifier_check','bool','false')]);

    { --- structure --- }
    B('inline-comment-in-multiline-args', 'structure', 'warning', 'Inline comment inside a multi-line argument list');
    B('multiple-statements-per-line',     'structure', 'hint',    'Two or more statements share one source line', False); { OFF by default -- pure style; opt in via "enabled" }

    { --- refactoring (Fowler catalog; v0.79) --- }
    B('magic-literal', 'refactoring', 'hint', 'Unexplained numeric literal -- extract a named constant', False); { OFF by default -- medium-FP, opt in via "enabled" }
    B('boolean-flag-parameter', 'refactoring', 'hint', 'Boolean flag parameter selects behavior -- consider splitting the routine', False); { OFF by default -- see FP-sanity note in DeadCodeChecks.pas }
    B('message-chain', 'refactoring', 'hint', 'Message chain too long -- consider Hide Delegate', True, [MkParam('threshold','int','4')]); { ON by default -- see FP-sanity note in DeadCodeChecks.pas }
    B('public-writable-field', 'refactoring', 'info', 'Public class field -- expose via a property instead', False); { OFF by default -- 44 findings/6 files on src/, mostly intentional field-bag DTOs; opt in via "enabled" }
    B('loop-control-flag', 'refactoring', 'hint', 'Loop exit driven by a boolean flag -- consider Break', False); { OFF by default -- riskiest heuristic of the batch; opt in via "enabled" }
    B('mutable-global-variable', 'refactoring', 'info', 'Mutable global variable -- shared mutable state (Fowler Global Data)', False); { OFF by default -- see FP-sanity note in AstChecks.pas; opt in via "enabled" }
    B('repeated-type-switch', 'refactoring', 'info', 'Same case-selector repeated across 3+ methods -- Replace Conditional with Polymorphism (project-wide)', False); { OFF by default -- medium-FP (message-map dispatches, name-based grouping); opt in via "enabled" }
    B('middle-man', 'refactoring', 'info', 'Class mostly delegates to one field -- Remove Middle Man (inline or expose the delegate)', False); { OFF by default -- facades/interposers/OTA-NTA wrappers are legitimate middle-men; opt in via "enabled" }
    B('feature-envy', 'refactoring', 'info', 'Method accesses another class more than its own -- Move Method closer to the data it uses', False, [MkParam('minAccess','int','3')]); { OFF by default -- target-class resolution is name-based (no type inference), so the own/foreign split is heuristic; opt in via "enabled" }
    B('split-variable', 'refactoring', 'info', 'Local reused for two unrelated purposes (disjoint lifetimes) -- Split Variable into two locals', False); { OFF by default -- M2 two-live-range flow signal (linear routines only); opt in via "enabled" }
    B('separate-query-from-modifier', 'refactoring', 'info', 'Value-returning function also mutates state -- Command-Query Separation violation; split into a pure query and a command', False); { OFF by default -- inherently noisy (lazy getters, fluent mutators); conservative field-write predicate; opt in via "enabled" }

    { --- project-wide --- }
    B('unit-not-in-dpr',       'project-wide', 'warning', 'Unit is referenced but not listed in the .dpr');
    B('used-unit-not-resolvable', 'project-wide', 'warning', 'Used unit resolves to no known unit (project/library/alias)');
    B('unused-unit-in-uses',   'project-wide', 'warning', 'Unit in uses is never referenced');
    B('god-class',             'project-wide', 'info',    'Class has too many members/responsibilities');
    B('unused-public-symbol',  'project-wide', 'info',    'Public symbol is never referenced');
    B('unused-private-member', 'project-wide', 'warning', 'Private member is never referenced');
    B('layering-violation',    'project-wide', 'warning', 'Unit dependency crosses an architectural layer');
    B('interface-reference-cycle','project-wide','warning','Interface reference cycle (ARC leak)');
    B('circular-uses',         'project-wide', 'warning', 'Circular unit dependency (a uses-graph cycle among project units)');
    B('enum-helper-separate-units', 'project-wide', 'warning', 'Enum helper (record/class helper) is declared in a different unit than its target enum -- consider co-locating'); { ON by default (explicit user decision, enum-helper-generator milestone 2026-07-07) -- diverges from the recent OFF-by-default convention for advisory rules; whole-DB helper edge (type_helpers, v15) via ISymbolStore.FindHelpersOfTypeSymbol (symbol-identity match, Task 9b), no heritage string-parsing }

    { --- documentation (ADF milestone) --- }
    B('missing-doc', 'documentation', 'warning', 'Public declaration has no DocInsight doc-comment', False); // OFF by default -- fires 1302x on drag-lint's own first-run wave; opt in via "enabled"
    B('doc-drift',   'documentation', 'warning', 'DocInsight comment has drifted from the code it documents (--fix repairs the mechanically-safe subset)'); { ON by default; marked fixable via FIXABLE_RULE_IDS -- its --fix applies only the safe subset (facts-block refresh + missing param/returns stubs), never rewriting hand prose }

    { --- metrics (CK class metrics; v0.78) --- }
    B('too-many-children', 'metrics', 'info', 'Class has too many direct subclasses (NOC)', True, [MkParam('threshold','int','10')]);
    B('deep-inheritance', 'metrics', 'info', 'Class inheritance is too deep (DIT)', True, [MkParam('threshold','int','6')]);
    B('high-response', 'metrics', 'info', 'Class response set is too large (RFC)', True, [MkParam('threshold','int','50')]);
    B('high-coupling', 'metrics', 'info', 'Class is coupled to too many other classes (CBO)', True, [MkParam('threshold','int','20')]);
    B('low-cohesion', 'metrics', 'info', 'Class methods lack cohesion (LCOM4)', True, [MkParam('threshold','int','26')]);
    { v0.81 coupling metrics -- OFF by default. fan-out aliases high-coupling/CBO
      (so it does not double-fire); fan-in is a whole-project reverse aggregation.
      Both need field-tuned thresholds; opt in via "enabled". }
    B('fan-out', 'metrics', 'info', 'Class depends on too many other classes (efferent coupling Ce; aliases CBO)', False, [MkParam('threshold','int','20')]);
    B('fan-in', 'metrics', 'info', 'Class is referenced by too many other classes (afferent coupling Ca)', False, [MkParam('threshold','int','20')]);
    B('instability', 'metrics', 'info', 'Class instability (I=Ce/(Ca+Ce)) is high -- unstable: depends on many, nothing depends on it', False, [MkParam('threshold','int','80'), MkParam('instability-floor','int','5')]);

    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

class function TRuleCatalog.ScmCategory(const AId: string): string;
begin
  if MatchStr(AId, ['empty-except','empty-on-handler','empty-finally','bare-except',
    'raise-bare-exception','reraise-loses-stack','nil-comparison','not-in-precedence',
    'not-comparison-precedence','self-assignment','comparison-same-operands',
    'classname-string-compare','empty-conditional','empty-loop-body','constant-condition',
    'ifthen-both-branches','uppercase-compare','uppercase-compare-always-false',
    'off-by-one-count','division-by-zero-literal',
    'empty-procedure-body','empty-case-branch','large-magic-number','case-magic-numbers',
    'sleep-in-vcl','parser-error']) then
    Result:= 'bug-patterns'
  else if MatchStr(AId, ['redundant-assigned-free']) then
    Result:= 'resource-lifetime'
  else if MatchStr(AId, ['hardcoded-credential','hardcoded-connection-string','sql-injection-concat',
    'hardcoded-absolute-path','hardcoded-ip-address']) then
    Result:= 'security'
  else if MatchStr(AId, ['inline-assembly','sizeof-pointer-assumption','pchar-arithmetic',
    'unsafe-string-api','locale-sensitive-conversion','gettickcount-wraparound','deprecated-rtl-function']) then
    Result:= 'platform'
  else if MatchStr(AId, ['public-field','goto-statement','with-statement','nested-with','with-multiple-items']) then
    Result:= 'structure'
  else if MatchStr(AId, ['redundant-as-tobject','redundant-not-not','boolean-result-returned-directly',
    'boolean-comparison-true']) then
    Result:= 'dead-code'
  else
    Result:= 'other';  { writeln-in-source, outputdebugstring, compiler-magic-comments, assert-call, inherited-bare, concat-in-loop }
end;

class function TRuleCatalog.BuildCatalog(const ARulesDir, ACategory: string): TArray<TRuleInfo>;
var
  Dir   : string;
  ById  : TDictionary<string, TRuleInfo>;
  Order : TList<string>;
  R     : TRuleInfo;
  F     : string;
  Files : TArray<string>;
  Raw   : string;
  Root  : TJSONValue;
  Obj   : TJSONObject;
  Sc    : TRuleInfo;
  Res   : TList<TRuleInfo>;
  Id    : string;
begin
  if ARulesDir <> '' then Dir:= ARulesDir
  else Dir:= TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'rules');

  ById:= TDictionary<string, TRuleInfo>.Create;
  Order:= TList<string>.Create;
  try
    { built-ins first (they win dedup) }
    for R in BuiltinRegistry do
      if not ById.ContainsKey(R.Id) then begin ById.Add(R.Id, R); Order.Add(R.Id); end;

    { external .scm sidecars }
    if TDirectory.Exists(Dir) then
    begin
      Files:= TDirectory.GetFiles(Dir, '*.json', TSearchOption.soAllDirectories);
      for F in Files do
      begin
        Raw:= '';
        try Raw:= TFile.ReadAllText(F, TEncoding.UTF8); except Continue; end;
        Root:= TJSONObject.ParseJSONValue(Raw);
        if not (Root is TJSONObject) then begin Root.Free; Continue; end;
        try
          Obj:= Root as TJSONObject;
          if Obj.GetValue('id') = nil then Continue;
          Id:= Obj.GetValue('id').Value;
          if (Id = '') or ById.ContainsKey(Id) then Continue; { builtin/dup wins }
          Sc.Id:= Id;
          Sc.Source:= 'scm';
          Sc.Category:= ScmCategory(Id);
          if Obj.GetValue('severity') <> nil then Sc.DefaultSeverity:= Obj.GetValue('severity').Value
          else Sc.DefaultSeverity:= 'warning';
          if Obj.GetValue('message') <> nil then Sc.Title:= Obj.GetValue('message').Value
          else Sc.Title:= Id;
          if (Obj.GetValue('enabled') <> nil) then
            Sc.DefaultEnabled:= not SameText(Obj.GetValue('enabled').Value, 'false')
          else Sc.DefaultEnabled:= True;
          Sc.Params:= nil;
          ById.Add(Id, Sc); Order.Add(Id);
        finally
          Root.Free;
        end;
      end;
    end;

    { emit in (category, id) order; optional single-category filter }
    Res:= TList<TRuleInfo>.Create;
    try
      for Id in Order do
      begin
        R:= ById[Id];
        if (ACategory = '') or SameText(R.Category, ACategory) then Res.Add(R);
      end;
      Res.Sort(TComparer<TRuleInfo>.Construct(
        function(const A, B: TRuleInfo): Integer
        begin
          Result:= CompareText(A.Category, B.Category);
          if Result = 0 then Result:= CompareText(A.Id, B.Id);
        end));
      Result:= Res.ToArray;
    finally
      Res.Free;
    end;
  finally
    Order.Free;
    ById.Free;
  end;
end;

class function TRuleCatalog.Summarize(const ACatalog: TArray<TRuleInfo>): TCatalogSummary;
var
  Counts: TDictionary<string, Integer>;
  Order : TList<string>;
  R     : TRuleInfo;
  C     : string;
  N     : Integer;
begin
  Counts:= TDictionary<string, Integer>.Create;
  Order:= TList<string>.Create;
  try
    Result.Total:= Length(ACatalog);
    Result.PerCategory:= nil;
    for R in ACatalog do
    begin
      if Counts.TryGetValue(R.Category, N) then Counts[R.Category]:= N + 1
      else begin Counts.Add(R.Category, 1); Order.Add(R.Category); end;
    end;
    Result.Categories:= Order.Count;
    for C in Order do
      Result.PerCategory:= Result.PerCategory + [TPair<string, Integer>.Create(C, Counts[C])];
  finally
    Order.Free;
    Counts.Free;
  end;
end;

end.
