unit residual_lines;

interface

// v(ADP3 T3f): the THREE loss classes of the repair path, one shape each,
// every one of them reproduced against the shipped exe before the fix and
// documented in docs\lint\URGENT-TODO-2026-07-26-index-doc-tag-coverage.md
// ("New finding"). Every shape below carries a CALLER, so Facts is non-empty
// and Merged is genuinely computed -- the repair-vs-fresh branch is what is
// under test, never the Merged='' early exit.
//
// L1  an unmodeled tag is deleted outright (it has no TParsedDoc field, so
//     the repair path, which rebuilds the comment from the fields it models,
//     simply never re-emits it). Two shapes: a whole line the engine models
//     NOTHING on (ValueBesideSummary) and the harder MIXED line, where an
//     unmodeled container wraps a tag the engine DOES model
//     (ParaWithInlineSee) -- the latter is the repo's own reported repro and
//     is the one that must neither mangle the author's text nor hoist the
//     inline <see cref> out into a fabricated standalone entry.
// L2  a multi-line <example>'s interior indentation is flattened. <example>
//     IS modeled; its normal content is a code sample, where whitespace is
//     semantic. Both the parser (Trim on the captured body, plus
//     StripXmlDocPrefix's own per-line TrimLeft) and EmitTagged (Trim on
//     every continuation line) destroy it.
// L3  trailing author prose sitting beside a modeled tag on the SAME line is
//     deleted, and a fabricated, empty <summary></summary> appears in its
//     place (BuildStandaloneFor strips the <since>, which orphans the
//     trailing prose, which then fires ParseXmlDoc's untagged-prefix
//     summary fallback while the content read from the UNSTRIPPED parse is
//     still empty).
//
// FullyModeledControl is the load-bearing control in the other direction: a
// plain, entirely modeled comment must be completely unaffected -- no
// residual carry-through, no duplicated tag, no reordering.

/// <value>Hand-written value tag; unmodeled, must survive verbatim.</value>
/// <summary>Has a real summary alongside an unmodeled tag.</summary>
procedure ValueBesideSummary;

procedure CallsValueBesideSummary;

/// <para>Body with an inline <see cref="residual_lines.CallsParaWithInlineSee"/> reference.</para>
/// <summary>Real summary, so the region reaches the repair path.</summary>
procedure ParaWithInlineSee;

procedure CallsParaWithInlineSee;

/// <example>
///   Foo := TBar.Create;
///     Foo.Run;
/// </example>
procedure MultiLineExample;

procedure CallsMultiLineExample;

/// <since>1.0</since> Trailing prose the author wrote.
procedure TrailingProseBesideSince;

procedure CallsTrailingProseBesideSince;

/// <summary>Plain, fully modeled comment; nothing here is residual.</summary>
/// <param name="AValue">The input value.</param>
/// <returns>The doubled value.</returns>
function FullyModeledControl(AValue: Integer): Integer;

procedure CallsFullyModeledControl;

implementation

procedure ValueBesideSummary;
begin
end;

procedure CallsValueBesideSummary;
begin
  ValueBesideSummary;
end;

procedure ParaWithInlineSee;
begin
end;

procedure CallsParaWithInlineSee;
begin
  ParaWithInlineSee;
end;

procedure MultiLineExample;
begin
end;

procedure CallsMultiLineExample;
begin
  MultiLineExample;
end;

procedure TrailingProseBesideSince;
begin
end;

procedure CallsTrailingProseBesideSince;
begin
  TrailingProseBesideSince;
end;

function FullyModeledControl(AValue: Integer): Integer;
begin
  Result:= AValue * 2;
end;

procedure CallsFullyModeledControl;
begin
  FullyModeledControl(21);
end;

end.
