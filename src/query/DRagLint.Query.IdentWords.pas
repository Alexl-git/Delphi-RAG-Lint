unit DRagLint.Query.IdentWords;

{ XERJ item 5 (concept search): the identifier word splitter. A pure function,
  kept OUT of the extractor on purpose -- the split is derived data that the
  `search` index stage stores in symbol_search, so a tokenizer change costs a
  rebuild of one derived table, never a re-parse. }

interface

/// <summary>Splits a Delphi identifier (or a dotted name, or free text) into
/// lower-case words separated by single spaces.</summary>
/// <param name="AName">Identifier, dotted name or free text. May be ''.</param>
/// <returns>The words, lower-cased, single-space separated, no leading or
/// trailing space; '' for an input with no letter or digit.</returns>
/// <remarks>Boundaries: lower-to-upper (ApplyDelta -&gt; apply delta); an
/// upper run followed by upper+lower (HTTPServer -&gt; http server); letter /
/// digit (Server2 -&gt; server 2); and every non-alphanumeric character
/// ('_', '.', space, punctuation) -- so FMyField -&gt; f my field and
/// Get_ID -&gt; get id. Prefix letters (T, F, I, A, p) are kept as words, not
/// stripped. Pure, thread-safe.</remarks>
function SplitIdentifierWords(const AName: string): string;

/// <summary>Self-test for SplitIdentifierWords (selftest ident-words).</summary>
/// <param name="AFailure">Receives the first failing case, '' on success.</param>
/// <returns>True when every case passes.</returns>
function SelfTestIdentWords(out AFailure: string): Boolean;

implementation

function SplitIdentifierWords(const AName: string): string;
begin
  Result:= ''; { XJ5-STUB: sub-lane (a) implements }
end; // function

function SelfTestIdentWords(out AFailure: string): Boolean;
begin
  AFailure:= 'not implemented'; { XJ5-STUB: sub-lane (a) implements }
  Result:= False;
end; // function

end.
