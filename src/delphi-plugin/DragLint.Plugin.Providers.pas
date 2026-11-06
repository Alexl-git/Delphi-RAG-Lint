unit DragLint.Plugin.Providers;

{ v0.42: a FLEXIBLE provider API so multiple sources can contribute to the same
  popups -- completion items and diagnostics. Today the only sources are the
  drag-lint index (symbols) and the lint engine. Tomorrow an LLM, a second
  analyzer, or a future Embarcadero service can register its own provider and
  its items/diagnostics are merged in, sorted, and shown in the SAME UI -- no
  change to the consumers.

  This is the pattern we'd suggest the IDE adopt natively: the IDE's Code
  Insight is a single sealed provider; here, completion/diagnostics are an open
  list of providers the consumer aggregates.

  Consumers:
    - the completion popup calls AggregateCompletion()
    - the live-diagnostics runner calls AggregateDiagnostics()

  Providers register at startup (e.g. the index provider) and unregister on
  teardown. Everything here is plain data + interfaces -- no ToolsAPI -- so it
  stays testable and reusable. }

interface

uses
  System.Classes
  , System.Generics.Collections
  ;

type { ---- Completion ---- }

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.Providers.pas), DragLint.Plugin.Providers.AggregateCompletion (DragLint.Plugin.Providers.pas)</para>
  /// <para>Used in units: DragLint.Plugin.Providers</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintCompletionItem = record
    InsertText: string ; // what to type into the editor
    Display   : string ; // label in the list
    Kind      : string ; // 'method'|'property'|'const'|'snippet'|'ai'|...
    Signature : string ; // detail line (params/return)
    Doc       : string ; // documentation shown in the preview pane
    Source    : string ; // provider name -- lets the UI badge AI vs index items
    SortRank  : Integer; // lower sorts first (index=100, ai=50 to surface first, etc.)
  end;
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.Providers.pas), DragLint.Plugin.Providers.AggregateCompletion (DragLint.Plugin.Providers.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintCompletionItems = TArray<TDragLintCompletionItem>;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.Providers.pas), DragLint.Plugin.Providers.AggregateCompletion (DragLint.Plugin.Providers.pas)</para>
  /// <para>Used in units: DragLint.Plugin.Providers</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintCompletionContext = record
    FilePath: string ;
    Line    : Integer; // 1-based caret line
    Col     : Integer; // 1-based caret col
    Prefix  : string ; // identifier text already typed
    DbArgs  : string ; // pre-built ' --db "..." --db "..."'
    ExePath : string ; // resolved drag-lint.exe
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.Providers.pas), DragLint.Plugin.Providers.AggregateCompletion (DragLint.Plugin.Providers.pas), DragLint.Plugin.Providers.EnsureLists (DragLint.Plugin.Providers.pas), DragLint.Plugin.Providers.RegisterCompletionProvider (DragLint.Plugin.Providers.pas), DragLint.Plugin.Providers.UnregisterCompletionProvider (DragLint.Plugin.Providers.pas)</para>
  /// <para>Used in units: DragLint.Plugin.Providers</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  IDragLintCompletionProvider = interface
    ['{B2D7F1A0-6E5C-4A1B-9C3D-7F0A1B2C3D40}']
    function Name: string                                                              ;
    /// <param name="ACtx"><!-- drag-lint:auto type -->const TDragLintCompletionContext</param>
    /// <returns><!-- drag-lint:auto type -->TDragLintCompletionItems</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.Providers.AggregateCompletion (DragLint.Plugin.Providers.pas)</para>
    /// <seealso cref="DragLint.Plugin.Providers.IDragLintCompletionProvider.Name"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetItems(const ACtx: TDragLintCompletionContext): TDragLintCompletionItems;
  end;

  { ---- Diagnostics ---- }

  /// <summary><!-- drag-lint:auto sum -->---- Diagnostics ----</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.Providers.pas) ?, DragLint.Plugin.LiveDiagnostics.PublishToCache (DragLint.Plugin.LiveDiagnostics.pas) ?, DragLint.Plugin.LiveDiagnostics.TLintDiagnosticProvider.GetDiagnostics (DragLint.Plugin.LiveDiagnostics.pas), DragLint.Plugin.LiveDiagnostics.TSemanticDiagnosticProvider.GetDiagnostics (DragLint.Plugin.LiveDiagnostics.pas), DragLint.Plugin.Providers.AggregateDiagnostics (DragLint.Plugin.Providers.pas) ?</para>
  /// <para>Used in units: DragLint.Plugin.LiveDiagnostics, DragLint.Plugin.Providers</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintDiagItem = record
    FilePath: string ;
    Line    : Integer; // 1-based
    Col     : Integer; // 1-based
    EndLine : Integer;
    EndCol  : Integer;
    Severity: Integer; // 1=error 2=warning 3=info 4=hint (LSP order)
    Message : string ;
    Rule    : string ;
    Source  : string ; // 'lint'|'compiler'|'ai'|...
  end;
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.LiveDiagnostics.pas), DragLint.Plugin.LiveDiagnostics.PublishToCache (DragLint.Plugin.LiveDiagnostics.pas), DragLint.Plugin.LiveDiagnostics.TLintDiagnosticProvider.GetDiagnostics (DragLint.Plugin.LiveDiagnostics.pas), DragLint.Plugin.LiveDiagnostics.TLiveRunner.OnTick (DragLint.Plugin.LiveDiagnostics.pas), DragLint.Plugin.LiveDiagnostics.TSemanticDiagnosticProvider.GetDiagnostics (DragLint.Plugin.LiveDiagnostics.pas) (+2 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintDiagItems = TArray<TDragLintDiagItem>;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.LiveDiagnostics.pas) ?, declaration (DragLint.Plugin.Providers.pas) ?, DragLint.Plugin.LiveDiagnostics.TLintDiagnosticProvider.GetDiagnostics (DragLint.Plugin.LiveDiagnostics.pas) ?, DragLint.Plugin.LiveDiagnostics.TLiveRunner.OnTick (DragLint.Plugin.LiveDiagnostics.pas), DragLint.Plugin.LiveDiagnostics.TSemanticDiagnosticProvider.GetDiagnostics (DragLint.Plugin.LiveDiagnostics.pas) ? (+1 more)</para>
  /// <para>Used in units: DragLint.Plugin.LiveDiagnostics, DragLint.Plugin.Providers</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintDiagContext = record
    FilePath  : string; // the real (saved) path the diagnostics belong to
    BufferPath: string; // a temp snapshot of the unsaved buffer to analyze
    ExePath   : string;
    { T-05: the manifest's unique DB for the IDE's ACTIVE project, resolved on
      the main thread (OTAPI) before the background run; '' when none. }
    ActiveProjectDb: string;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.LiveDiagnostics.pas), declaration (DragLint.Plugin.Providers.pas), DragLint.Plugin.Providers.EnsureLists (DragLint.Plugin.Providers.pas), DragLint.Plugin.Providers.RegisterDiagnosticProvider (DragLint.Plugin.Providers.pas), DragLint.Plugin.Providers.UnregisterDiagnosticProvider (DragLint.Plugin.Providers.pas) (+1 more)</para>
  /// <para>Used in units: DragLint.Plugin.LiveDiagnostics, DragLint.Plugin.Providers</para>
  /// <para>Implemented by: TLintDiagnosticProvider, TSemanticDiagnosticProvider</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  IDragLintDiagnosticProvider = interface
    ['{C3E8A2B1-7F6D-4B2C-AD4E-8A1B2C3D4E51}']
    function Name: string                                                        ;
    /// <param name="ACtx"><!-- drag-lint:auto type -->const TDragLintDiagContext</param>
    /// <returns><!-- drag-lint:auto type -->TDragLintDiagItems</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.Providers.AggregateDiagnostics (DragLint.Plugin.Providers.pas)</para>
    /// <seealso cref="DragLint.Plugin.Providers.IDragLintDiagnosticProvider.Name"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetDiagnostics(const ACtx: TDragLintDiagContext): TDragLintDiagItems;
  end;

  { ---- registries ---- }

/// <summary><!-- drag-lint:auto sum -->---- registries ----</summary>
/// <param name="AProvider"><!-- drag-lint:auto type -->const IDragLintCompletionProvider</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DragLint.Plugin.Providers.EnsureLists</para>
/// <seealso cref="DragLint.Plugin.Providers.EnsureLists"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure RegisterCompletionProvider  (const AProvider: IDragLintCompletionProvider);
procedure UnregisterCompletionProvider(const AProvider: IDragLintCompletionProvider);
/// <param name="ACtx"><!-- drag-lint:auto type -->const TDragLintCompletionContext</param>
/// <returns><!-- drag-lint:auto type -->TDragLintCompletionItems</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: CompareText, DragLint.Plugin.Providers.IDragLintCompletionProvider.GetItems</para>
/// <para>Catches: Exception (empty)</para>
/// <seealso cref="DragLint.Plugin.Providers.IDragLintCompletionProvider.GetItems"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AggregateCompletion(const ACtx: TDragLintCompletionContext): TDragLintCompletionItems;

/// <param name="AProvider"><!-- drag-lint:auto type -->const IDragLintDiagnosticProvider</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.LiveDiagnostics.StartLiveDiagnostics (DragLint.Plugin.LiveDiagnostics.pas)</para>
/// <para>Calls: DragLint.Plugin.Providers.EnsureLists</para>
/// <seealso cref="DragLint.Plugin.Providers.EnsureLists"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure RegisterDiagnosticProvider  (const AProvider: IDragLintDiagnosticProvider);
/// <param name="AProvider"><!-- drag-lint:auto type -->const IDragLintDiagnosticProvider</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.LiveDiagnostics.StopLiveDiagnostics (DragLint.Plugin.LiveDiagnostics.pas)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure UnregisterDiagnosticProvider(const AProvider: IDragLintDiagnosticProvider);
/// <summary><!-- drag-lint:auto sum -->So the provider list is COPIED under the lock and
/// the lock is released before any provider is called. A provider added or removed
/// mid-run is simply not in this pass's snapshot, which is the same guarantee the old
/// code gave.</summary>
/// <param name="ACtx"><!-- drag-lint:auto type -->const TDragLintDiagContext</param>
/// <returns><!-- drag-lint:auto type -->TDragLintDiagItems</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.LiveDiagnostics.TLiveRunner.OnTick (DragLint.Plugin.LiveDiagnostics.pas)</para>
/// <para>Calls: DragLint.Plugin.Providers.IDragLintDiagnosticProvider.GetDiagnostics</para>
/// <para>Catches: Exception (empty)</para>
/// <seealso cref="DragLint.Plugin.Providers.IDragLintDiagnosticProvider.GetDiagnostics"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AggregateDiagnostics(const ACtx: TDragLintDiagContext): TDragLintDiagItems;

procedure ClearAllProviders; // teardown

implementation

uses
  System.SysUtils
  , System.Generics.Defaults
  ;

var
  GCompletion: TList<IDragLintCompletionProvider> = nil;
  GDiagnostic: TList<IDragLintDiagnosticProvider> = nil;
  GLock      : TObject                            = nil                           ;

procedure EnsureLists;
begin
  if GLock       = nil then GLock:= TObject.Create;
  if GCompletion = nil then GCompletion:= TList<IDragLintCompletionProvider>.Create;
  if GDiagnostic = nil then GDiagnostic:= TList<IDragLintDiagnosticProvider>.Create;
end;

procedure RegisterCompletionProvider(const AProvider: IDragLintCompletionProvider);
begin
  if AProvider = nil then Exit;
  EnsureLists;
  TMonitor.Enter(GLock);
  try
    if not GCompletion.Contains(AProvider) then GCompletion.Add(AProvider);
  finally
    TMonitor.Exit(GLock);
  end;
end;

procedure UnregisterCompletionProvider(const AProvider: IDragLintCompletionProvider);
begin
  if (GCompletion = nil) or (AProvider = nil) then Exit;
  TMonitor.Enter(GLock);
  try
    GCompletion.Remove(AProvider);
  finally
    TMonitor.Exit(GLock);
  end;
end;

function AggregateCompletion(const ACtx: TDragLintCompletionContext): TDragLintCompletionItems;
var
  Acc : TList<TDragLintCompletionItem>;
  P   : IDragLintCompletionProvider   ;
  Item: TDragLintCompletionItem       ;
begin
  SetLength(Result, 0);
  if GCompletion = nil then Exit;
  Acc:= TList<TDragLintCompletionItem>.Create;
  try
    TMonitor.Enter(GLock);
    try
      for P in GCompletion do
      try
        for Item in P.GetItems(ACtx) do Acc.Add(Item);
      except
        { one bad provider must not break the popup }
      end;
    finally
      TMonitor.Exit(GLock);
    end;
    Acc.Sort(TComparer<TDragLintCompletionItem>.Construct(
        function(const L, R: TDragLintCompletionItem): Integer
        begin
          Result:= L.SortRank - R.SortRank;
          if Result = 0 then Result:= CompareText(L.Display, R.Display);
        end));
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end; // try
end; // function

procedure RegisterDiagnosticProvider(const AProvider: IDragLintDiagnosticProvider);
begin
  if AProvider = nil then Exit;
  EnsureLists;
  TMonitor.Enter(GLock);
  try
    if not GDiagnostic.Contains(AProvider) then GDiagnostic.Add(AProvider);
  finally
    TMonitor.Exit(GLock);
  end;
end;

procedure UnregisterDiagnosticProvider(const AProvider: IDragLintDiagnosticProvider);
begin
  if (GDiagnostic = nil) or (AProvider = nil) then Exit;
  TMonitor.Enter(GLock);
  try
    GDiagnostic.Remove(AProvider);
  finally
    TMonitor.Exit(GLock);
  end;
end;

{ THE LOCK PROTECTS THE LIST, NOT THE CALLS -- and holding it across the calls
  DEADLOCKED THE IDE ON EXIT.

  GetDiagnostics spawns drag-lint.exe and waits for it. That is seconds
  normally and MINUTES for a tier-3 compile of a many-dependent unit (measured
  2026-09-11: 6m22s on a 207-dependent unit). While this held GLock for that
  whole run, StopLiveDiagnostics -> UnregisterDiagnosticProvider -> the same
  GLock blocked the MAIN thread. The owner closed the IDE five seconds after a
  forced tier-3 compile began: the window vanished, bds.exe stayed alive with no
  main window, the plugin BPL stayed locked, and the only trace was a
  'LiveDiagnostics: finalization BEGIN' with no matching END. Earlier sessions
  produced access-violation dialogs instead -- the same race landing differently.

  So the provider list is COPIED under the lock and the lock is released before
  any provider is called. A provider added or removed mid-run is simply not in
  this pass's snapshot, which is the same guarantee the old code gave. }
function AggregateDiagnostics(const ACtx: TDragLintDiagContext): TDragLintDiagItems;
var
  Acc  : TList<TDragLintDiagItem>   ;
  P    : IDragLintDiagnosticProvider;
  D    : TDragLintDiagItem          ;
  Snap : TArray<IDragLintDiagnosticProvider>;
begin
  SetLength(Result, 0);
  if GDiagnostic = nil then Exit;

  TMonitor.Enter(GLock);
  try
    Snap:= GDiagnostic.ToArray;
  finally
    TMonitor.Exit(GLock);
  end;

  Acc:= TList<TDragLintDiagItem>.Create;
  try
    begin
      for P in Snap do
      try
        for D in P.GetDiagnostics(ACtx) do Acc.Add(D);
      except
        { one bad provider must not break diagnostics }
      end;
    end;
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end; // try
end; // function

procedure ClearAllProviders;
begin
  if GLock = nil then Exit;
  TMonitor.Enter(GLock);
  try
    if GCompletion <> nil then GCompletion.Clear;
    if GDiagnostic <> nil then GDiagnostic.Clear;
  finally
    TMonitor.Exit(GLock);
  end;
end;

initialization

finalization
FreeAndNil(GCompletion);
FreeAndNil(GDiagnostic);
FreeAndNil(GLock      );

end.
