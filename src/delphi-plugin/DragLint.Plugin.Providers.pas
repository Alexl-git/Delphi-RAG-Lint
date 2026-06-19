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

  TDragLintCompletionItem = record
    InsertText: string ; // what to type into the editor
    Display   : string ; // label in the list
    Kind      : string ; // 'method'|'property'|'const'|'snippet'|'ai'|...
    Signature : string ; // detail line (params/return)
    Doc       : string ; // documentation shown in the preview pane
    Source    : string ; // provider name -- lets the UI badge AI vs index items
    SortRank  : Integer; // lower sorts first (index=100, ai=50 to surface first, etc.)
  end;
  TDragLintCompletionItems = TArray<TDragLintCompletionItem>;

  TDragLintCompletionContext = record
    FilePath: string ;
    Line    : Integer; // 1-based caret line
    Col     : Integer; // 1-based caret col
    Prefix  : string ; // identifier text already typed
    DbArgs  : string ; // pre-built ' --db "..." --db "..."'
    ExePath : string ; // resolved drag-lint.exe
  end;

  IDragLintCompletionProvider = interface
    ['{B2D7F1A0-6E5C-4A1B-9C3D-7F0A1B2C3D40}']
    function Name: string                                                              ;
    function GetItems(const ACtx: TDragLintCompletionContext): TDragLintCompletionItems;
  end;

  { ---- Diagnostics ---- }

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
  TDragLintDiagItems = TArray<TDragLintDiagItem>;

  TDragLintDiagContext = record
    FilePath  : string; // the real (saved) path the diagnostics belong to
    BufferPath: string; // a temp snapshot of the unsaved buffer to analyze
    DbArgs    : string;
    ExePath   : string;
  end;

  IDragLintDiagnosticProvider = interface
    ['{C3E8A2B1-7F6D-4B2C-AD4E-8A1B2C3D4E51}']
    function Name: string                                                        ;
    function GetDiagnostics(const ACtx: TDragLintDiagContext): TDragLintDiagItems;
  end;

  { ---- registries ---- }

procedure RegisterCompletionProvider  (const AProvider: IDragLintCompletionProvider);
procedure UnregisterCompletionProvider(const AProvider: IDragLintCompletionProvider);
function AggregateCompletion(const ACtx: TDragLintCompletionContext): TDragLintCompletionItems;

procedure RegisterDiagnosticProvider  (const AProvider: IDragLintDiagnosticProvider);
procedure UnregisterDiagnosticProvider(const AProvider: IDragLintDiagnosticProvider);
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

function AggregateDiagnostics(const ACtx: TDragLintDiagContext): TDragLintDiagItems;
var
  Acc: TList<TDragLintDiagItem>   ;
  P  : IDragLintDiagnosticProvider;
  D  : TDragLintDiagItem          ;
begin
  SetLength(Result, 0);
  if GDiagnostic = nil then Exit;
  Acc:= TList<TDragLintDiagItem>.Create;
  try
    TMonitor.Enter(GLock);
    try
      for P in GDiagnostic do
      try
        for D in P.GetDiagnostics(ACtx) do Acc.Add(D);
      except
        { one bad provider must not break diagnostics }
      end;
    finally
      TMonitor.Exit(GLock);
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
