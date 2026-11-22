unit DRagLint.CLI.Wiki;

// ---------------------------------------------------------------------------
// The ``wiki`` verb (lane v1511 SPLIT T07). Moved verbatim out of DRagLint.CLI.
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint wiki: looks up, lists or drift-checks the dl:wiki concept
/// topics stored in the resolved indexes' doc comments.</summary>
/// <param name="AArgs">Parsed CLI args. Exactly one of Term (--term), WikiList
/// (--list) or WikiCheck (--check) selects the mode; DbPath/DbPaths resolve the
/// index set the same way `query` does; AsJson or Format='json' selects JSON.</param>
/// <returns>0 on success; 1 when --term matched nothing or --check found drift;
/// 2 for a usage error or an unresolvable index.</returns>
/// <remarks>
/// Read-only. --term exits 1 on no match ON PURPOSE, so a script can
/// branch on "this word is not in the wiki" without parsing the output.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.OpenReadOnlyStore, DRagLint.CLI.Wiki.CollectWikiTopics, DRagLint.CLI.Wiki.PrintWikiTopic, DRagLint.CLI.Wiki.ResolveSeeCode, DRagLint.CLI.Wiki.WikiTopicToJson, DRagLint.Doc.Wiki.TWikiParser.CompareRanked, DRagLint.Doc.Wiki.TWikiParser.MatchScore, Format, LowerCase, SameText, Trim, Writeln</para>
/// <para>Returns: 2; 0; 1</para>
/// <para>Complexity: 35 (cyclomatic, outer body), 212 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.OpenReadOnlyStore"/>
/// <seealso cref="DRagLint.CLI.Wiki.CollectWikiTopics"/>
/// <seealso cref="DRagLint.CLI.Wiki.PrintWikiTopic"/>
/// <seealso cref="DRagLint.CLI.Wiki.ResolveSeeCode"/>
/// <seealso cref="DRagLint.CLI.Wiki.WikiTopicToJson"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoWiki(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.Model, DRagLint.CLI.ConsumerDbs, Winapi.Windows, System.SysUtils, System.IOUtils,
  System.NetEncoding, System.JSON, System.StrUtils, System.DateUtils, System.Generics.Collections,
  System.SyncObjs, FireDAC.Stan.Async, FireDAC.DApt, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite,
  DRagLint.Doc.Wiki;

{ ---------------------------------------------------------------------------
  drag-lint wiki -- concept topics written as dl:wiki blocks in doc comments.

  WHAT THIS VERB IS FOR
  ---------------------
  Every other query in this tool assumes the caller already has an identifier.
  This one starts from a word a HUMAN uses -- "the scheduler", "delta
  streaming" -- and routes it to the code. The index cannot infer that mapping;
  somebody has to write it down, and a dl:wiki block is where.

  WHY IT READS raw_block RATHER THAN A TABLE OF ITS OWN
  -----------------------------------------------------
  Because a table would be an extraction change, and an extraction change costs
  a full re-parse of every index on the machine (hours). The blocks are already
  stored -- verbatim, by the existing extractor -- so the whole feature is a
  read. See docs\PLAN-wiki-comments.md section 4 and owner ruling R2.
  --------------------------------------------------------------------------- }

/// <summary>Collects every dl:wiki topic across the resolved index set.</summary>
/// <param name="AArgs">Parsed CLI args; only the DB-resolution fields are read.</param>
/// <param name="ATopics">Receives the parsed topics, each stamped with the
/// database it came from.</param>
/// <returns>0 when at least one database was opened, 2 when none resolved or a
/// named one is missing.</returns>
/// <remarks>An index with no wiki blocks contributes nothing and is NOT an
/// error -- most indexes have none, the platform library above all.</remarks>
function CollectWikiTopics(const AArgs: TArgs; out ATopics: TArray<TWikiTopic>): Integer;
var
  PathsToScan: TArray<string>    ;
  DbPath     : string            ;
  Store      : ISymbolStore      ;
  Ok         : Boolean           ;
  Rows       : TArray<TWikiDocRow>;
  Row        : TWikiDocRow       ;
  Parsed     : TArray<TWikiTopic>;
  T          : TWikiTopic        ;
begin
  SetLength(ATopics, 0);
  PathsToScan:= ResolveConsumerDbs(AArgs);
  if Length(PathsToScan) = 0 then
  begin
    Writeln(ErrOutput, 'ERROR: no index database resolved. Pass --db, or run "drag-lint resolve-dbs --project <x.dproj>".');
    Exit(2);
  end;
  for DbPath in PathsToScan do
    if not TFile.Exists(DbPath) then
    begin
      Writeln(ErrOutput, 'ERROR: database not found: ', DbPath);
      Exit(2);
    end;

  for DbPath in PathsToScan do
  begin
    Store:= OpenReadOnlyStore(DbPath, Ok, {AQuiet=}True);
    if (Store = nil) or (not Ok) then Continue;
    Rows:= TSQLiteSymbolStore(Store).FindWikiDocBlocks;
    for Row in Rows do
    begin
      Parsed:= TWikiParser.ParseRawBlock(Row.RawBlock, Row.QName, Row.Kind,
                                         Row.FilePath, Row.StartLine);
      for T in Parsed do
      begin
        var Stamped: TWikiTopic:= T;
        Stamped.DbPath:= DbPath;
        ATopics:= ATopics + [Stamped];
      end;
    end;
  end;
  Result:= 0;
end; // function

/// <summary>Resolves one SeeCode entry to a symbol.</summary>
/// <param name="AStore">The store the topic's own database is open on.</param>
/// <param name="AEntry">The entry as written: bare, class-qualified, or fully
/// qualified.</param>
/// <param name="AHit">Receives the first match; undefined when False.</param>
/// <returns>True when the entry names something in this index.</returns>
/// <remarks>THE SUFFIX PASS IS THE POINT, not a nicety. An author writes
/// <c>TWikiProbe.ApplyDelta</c> because that is how the method is spelled in
/// the code; the index stores <c>uWikiProbe.TWikiProbe.ApplyDelta</c>. Exact
/// qualified-name lookup misses it, and exact NAME lookup misses it too
/// (the name is just <c>ApplyDelta</c>), so without this pass
/// <c>wiki --check</c> would report correct authoring as drift -- and a gate
/// that cries wolf gets switched off.
/// <para>Driven off the indexed exact-name lookup of the LAST segment, so it
/// stays a keyed read rather than a scan.</para></remarks>
function ResolveSeeCode(AStore: ISymbolStore; const AEntry: string; out AHit: TSymbol): Boolean;
var
  Hits: TArray<TSymbol>;
  Leaf: string         ;
  P   : Integer        ;
  S   : TSymbol        ;
begin
  Result:= False;
  if (AStore = nil) or (Trim(AEntry) = '') then Exit;

  Hits:= AStore.FindSymbolsByQualifiedName(AEntry);
  if Length(Hits) = 0 then Hits:= AStore.FindSymbolsByExactName(AEntry);
  if Length(Hits) > 0 then begin AHit:= Hits[0];
  Exit(True); end;

  { Dotted but not fully qualified: look the leaf up and keep only the symbols
    whose qualified name actually ENDS with what was written, so
    'TFoo.Load' can never be satisfied by 'TBar.Load'. }
  P:= LastDelimiter('.', AEntry);
  if P <= 0 then Exit;
  Leaf:= Copy(AEntry, P + 1, MaxInt);
  if Leaf = '' then Exit;
  for S in AStore.FindSymbolsByExactName(Leaf) do
    if EndsText('.' + AEntry, S.QualifiedName) then
    begin
      AHit:= S;
      Exit(True);
    end;
end; // function

/// <summary>Renders one topic as text.</summary>
/// <param name="ATopic">The topic to print.</param>
/// <param name="AStore">Store used to resolve SeeCode entries for display;
/// may be nil, in which case entries print unresolved.</param>
/// <remarks>The owning symbol is printed as the topic's own location -- it is
/// the IMPLICIT SeeCode entry, which is why a single-owner topic needs no
/// SeeCode line at all.</remarks>
procedure PrintWikiTopic(const ATopic: TWikiTopic; AStore: ISymbolStore);
var
  Entry: string ;
  Hit  : TSymbol;
  Line : string ;
begin
  Writeln('== ', ATopic.Name, ' ==');
  Writeln('   owner : ', ATopic.OwnerQName, '  (', ATopic.OwnerKind, ')');
  Writeln('   source: ', ATopic.FilePath, ':', ATopic.HeaderLine);
  if Length(ATopic.Aliases) > 0 then
    Writeln('   aliases: ', string.Join(', ', ATopic.Aliases));
  for Entry in ATopic.SeeCode do
  begin
    Line:= '   see: ' + Entry;
    if AStore <> nil then
    begin
      if ResolveSeeCode(AStore, Entry, Hit) then
        Line:= Line + '  -> ' + AStore.GetFilePath(Hit.FileId) + ':' + IntToStr(Hit.StartLine)
      else
        Line:= Line + '  -> MISSING';
    end;
    Writeln(Line);
  end;
  if ATopic.Body <> '' then
  begin
    Writeln;
    Writeln(ATopic.Body);
  end;
  Writeln;
end; // procedure

/// <summary>Builds the JSON object for one topic.</summary>
/// <param name="ATopic">The topic to serialise.</param>
/// <returns>A fresh TJSONObject; the caller owns it (adding it to a
/// TJSONArray transfers that ownership).</returns>
function WikiTopicToJson(const ATopic: TWikiTopic): TJSONObject;
var
  Arr: TJSONArray;
  S  : string    ;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('name'       , ATopic.Name);
  Result.AddPair('owner_qname', ATopic.OwnerQName);
  Result.AddPair('owner_kind' , ATopic.OwnerKind);
  Result.AddPair('file'       , ATopic.FilePath);
  Result.AddPair('line'       , TJSONNumber.Create(ATopic.HeaderLine));
  Result.AddPair('db'         , ATopic.DbPath);
  Arr:= TJSONArray.Create;
  for S in ATopic.Aliases do Arr.Add(S);
  Result.AddPair('aliases', Arr);
  Arr:= TJSONArray.Create;
  for S in ATopic.SeeCode do Arr.Add(S);
  Result.AddPair('seecode', Arr);
  Result.AddPair('body', ATopic.Body);
end; // function

function DoWiki(const AArgs: TArgs): Integer;
var
  Topics   : TArray<TWikiTopic>;
  Rc       : Integer           ;
  UseJson  : Boolean           ;
  T        : TWikiTopic        ;
  Scores   : TArray<Integer>   ;
  Order    : TArray<Integer>   ;
  I        : Integer           ;
  J        : Integer           ;
  Tmp      : Integer           ;
  Matched  : Integer           ;
  JRoot    : TJSONObject       ;
  JArr     : TJSONArray        ;
  Store    : ISymbolStore      ;
  Ok       : Boolean           ;
  LastDb   : string            ;
  Problems : TArray<string>    ;
  Entry    : string            ;
  Hit      : TSymbol           ;
  Modes    : Integer           ;
  Names    : TDictionary<string, string>;
  Owner    : string            ;
  Key      : string            ;
  Msg      : string            ;
begin
  UseJson:= AArgs.AsJson or SameText(AArgs.Format, 'json');

  Modes:= 0;
  if Trim(AArgs.Term) <> '' then Inc(Modes);
  if AArgs.WikiList          then Inc(Modes);
  if AArgs.WikiCheck         then Inc(Modes);
  if Modes <> 1 then
  begin
    Writeln(ErrOutput, 'Usage: drag-lint wiki --term "<phrase>" [--json] [--db <file.sqlite>]   (look a human word up)');
    Writeln(ErrOutput, '       drag-lint wiki --list            [--json] [--db <file.sqlite>]   (every topic)');
    Writeln(ErrOutput, '       drag-lint wiki --check           [--json] [--db <file.sqlite>]   (SeeCode drift gate)');
    Writeln(ErrOutput, 'Exactly one of --term / --list / --check.');
    Exit(2);
  end;

  Rc:= CollectWikiTopics(AArgs, Topics);
  if Rc <> 0 then Exit(Rc);

  { ---------------------------------------------------------------- --list }
  if AArgs.WikiList then
  begin
    if UseJson then
    begin
      JArr:= TJSONArray.Create;
      try
        for T in Topics do JArr.Add(WikiTopicToJson(T));
        Writeln(JArr.ToJSON);
      finally
        JArr.Free;
      end;
    end
    else
    begin
      for T in Topics do PrintWikiTopic(T, nil);
      Writeln(Format('%d topic(s).', [Length(Topics)]));
    end;
    Exit(0);
  end;

  { --------------------------------------------------------------- --check }
  if AArgs.WikiCheck then
  begin
    SetLength(Problems, 0);
    Names:= TDictionary<string, string>.Create;
    try
      LastDb:= '';
      Store := nil;
      for T in Topics do
      begin
        if T.Name = '' then
          Problems:= Problems + [Format('%s:%d  a "dl:wiki" header carries no topic name',
                                        [T.FilePath, T.HeaderLine])];

        { A duplicate name makes --term ambiguous, and an alias that collides
          with a DIFFERENT topic's name makes it wrong. Both are keyed into one
          case-insensitive namespace, because that is the namespace --term
          searches. }
        Key:= LowerCase(Trim(T.Name));
        if Key <> '' then
        begin
          if Names.TryGetValue(Key, Owner) and (Owner <> T.OwnerQName) then
            Problems:= Problems + [Format('%s:%d  topic name "%s" is already declared by %s',
                                          [T.FilePath, T.HeaderLine, T.Name, Owner])]
          else Names.AddOrSetValue(Key, T.OwnerQName);
        end;
        for Entry in T.Aliases do
        begin
          Key:= LowerCase(Trim(Entry));
          if Key = '' then Continue;
          if Names.TryGetValue(Key, Owner) and (Owner <> T.OwnerQName) then
            Problems:= Problems + [Format('%s:%d  alias "%s" collides with a topic already declared by %s',
                                          [T.FilePath, T.HeaderLine, Entry, Owner])]
          else Names.AddOrSetValue(Key, T.OwnerQName);
        end;

        { SeeCode is resolved against the SAME database the topic came from.
          Resolving it against the whole set would let a name match in an
          unrelated project's index silently vouch for a symbol this project
          does not have -- the exact mechanism that wrote foreign units into
          YADF's source on 2026-08-13. }
        if Length(T.SeeCode) = 0 then Continue;
        if T.DbPath <> LastDb then
        begin
          Store := OpenReadOnlyStore(T.DbPath, Ok, {AQuiet=}True);
          if not Ok then Store:= nil;
          LastDb:= T.DbPath;
        end;
        if Store = nil then Continue;
        for Entry in T.SeeCode do
          if not ResolveSeeCode(Store, Entry, Hit) then
            Problems:= Problems + [Format('%s:%d  topic "%s": SeeCode "%s" resolves to nothing in %s',
                                          [T.FilePath, T.HeaderLine, T.Name, Entry, TPath.GetFileName(T.DbPath)])];
      end;
    finally
      Names.Free;
    end; // try

    if UseJson then
    begin
      JRoot:= TJSONObject.Create;
      try
        JRoot.AddPair('topics_checked', TJSONNumber.Create(Length(Topics)));
        JArr:= TJSONArray.Create;
        for Msg in Problems do JArr.Add(Msg);
        JRoot.AddPair('problems', JArr);
        JRoot.AddPair('ok', TJSONBool.Create(Length(Problems) = 0));
        Writeln(JRoot.ToJSON);
      finally
        JRoot.Free;
      end;
    end
    else
    begin
      for Msg in Problems do Writeln('DRIFT: ', Msg);
      { The COUNT is part of the pass, not decoration: a check that examined
        zero topics and printed "OK" is indistinguishable from a working one,
        and that is precisely how a silently broken query reads. }
      Writeln(Format('%d topic(s) checked, %d problem(s).', [Length(Topics), Length(Problems)]));
    end;
    if Length(Problems) > 0 then Exit(1);
    Exit(0);
  end;

  { ---------------------------------------------------------------- --term }
  SetLength(Scores, Length(Topics));
  SetLength(Order , 0);
  for I:= 0 to High(Topics) do
  begin
    Scores[I]:= TWikiParser.MatchScore(Topics[I], AArgs.Term);
    if Scores[I] > 0 then Order:= Order + [I];
  end;

  { Insertion sort: the candidate set is the number of topics that matched one
    phrase, which is a handful. }
  for I:= 1 to High(Order) do
  begin
    Tmp:= Order[I];
    J  := I - 1;
    while (J >= 0) and
          (TWikiParser.CompareRanked(Scores[Tmp]     , Topics[Tmp].Name,
                                     Scores[Order[J]], Topics[Order[J]].Name) < 0) do
    begin
      Order[J + 1]:= Order[J];
      Dec(J);
    end;
    Order[J + 1]:= Tmp;
  end;

  Matched:= Length(Order);
  if UseJson then
  begin
    JArr:= TJSONArray.Create;
    try
      for I in Order do JArr.Add(WikiTopicToJson(Topics[I]));
      Writeln(JArr.ToJSON);
    finally
      JArr.Free;
    end;
  end
  else if Matched = 0 then
  begin
    Writeln(Format('No wiki topic matches "%s". %d topic(s) were searched.',
                   [AArgs.Term, Length(Topics)]));
    if Length(Topics) = 0 then
      Writeln('Nothing in the resolved index set carries a dl:wiki block yet -- see docs\wiki\Wiki-Blocks-Authoring.md.');
  end
  else
  begin
    LastDb:= '';
    Store := nil;
    for I in Order do
    begin
      if Topics[I].DbPath <> LastDb then
      begin
        Store := OpenReadOnlyStore(Topics[I].DbPath, Ok, {AQuiet=}True);
        if not Ok then Store:= nil;
        LastDb:= Topics[I].DbPath;
      end;
      PrintWikiTopic(Topics[I], Store);
    end;
    Writeln(Format('%d match(es) of %d topic(s).', [Matched, Length(Topics)]));
  end;

  { A word that is not in the wiki is an ANSWER, and a caller must be able to
    branch on it without parsing prose. }
  if Matched = 0 then Result:= 1 else Result:= 0;
end; // function

end.
