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

// v(ADP3 T3f review, IMPORTANT 1): the ACCOUNTED-SPAN MASK must agree with the
// REPRESENTATION MODEL. The first cut of SplitResidualLines matched containers
// with StripElement's attribute-TOLERANT pattern while the parser's own regexes
// are STRICT -- bare <summary>/<remarks>/<returns>/<example>/<since>/
// <deprecated>, and a MANDATORY name=/cref= on <param>/<exception>. Everything
// in that gap was accounted (so never carried through) yet unrepresented (so
// never re-emitted): deleted outright, exactly the L1 class this task exists to
// close. Two of the four shapes below are perfectly VALID XML doc comments.
//
// Each pairs the offending tag with a real <summary>, which is what makes the
// region dispatch as dfXmlDoc -- the isolated form of some of these routes to
// ParseOneline instead and never reaches the repair path at all, which is why
// the isolated fixtures already in preserve_tags.pas did not catch this.

/// <exception>Missing the required cref attribute.</exception>
/// <summary>Real summary, so the region dispatches as XML doc.</summary>
procedure ExceptionNoCrefBesideSummary;

procedure CallsExceptionNoCrefBesideSummary;

/// <param>Missing the required name attribute.</param>
/// <summary>Real summary, so the region dispatches as XML doc.</summary>
procedure ParamNoNameBesideSummary(AValue: Integer);

procedure CallsParamNoNameBesideSummary;

/// <remarks xml:lang="en">Attributed remarks prose must survive.</remarks>
/// <summary>Real summary beside a VALID but attributed remarks element.</summary>
procedure AttributedRemarks;

procedure CallsAttributedRemarks;

/// <example lang="pascal">Attributed example body must survive.</example>
/// <summary>Real summary beside a VALID but attributed example element.</summary>
procedure AttributedExample;

procedure CallsAttributedExample;

// v(ADP3 T3f review, IMPORTANT 2 and 3): retracting a span whose content the
// engine REGENERATES is a one-way ratchet from engine content to author
// content. Below, the tail sits on a line of a LIVE facts fence's own
// </remarks>, and on an engine-MARKED <returns>. Retracting those spans froze
// the fact text as un-maintained, un-strippable author prose and emitted a
// SECOND <remarks>/<returns> beside it.
//
// The fix is to fail closed: such a span is NON-RETRACTABLE, and a residual
// line overlapping one aborts the carry-through for the whole region, which
// falls back to the pre-v(ADP3 T3f) behaviour. That behaviour DOES still drop
// the tail -- pinned below as a disclosed, deliberate non-improvement, chosen
// over a duplicate element plus a permanently stale fact.

/// <summary>Has a LIVE facts fence with an unmodeled tail on its close line.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: residual_lines.STALE_GHOST (residual_lines.pas)
/// <!-- drag-lint:auto END -->
/// </remarks> <value>tail value</value>
procedure FencedRemarksTailValue;

procedure CallsFencedRemarksTailValue;

/// <summary>Has an engine-marked returns with a hand-written tail outside it.</summary>
/// <returns><!-- drag-lint:auto -->Observed: STALE cases</returns> hand tail
function MarkedReturnsTail: Integer;

procedure CallsMarkedReturnsTail;

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

procedure ExceptionNoCrefBesideSummary;
begin
end;

procedure CallsExceptionNoCrefBesideSummary;
begin
  ExceptionNoCrefBesideSummary;
end;

procedure ParamNoNameBesideSummary(AValue: Integer);
begin
end;

procedure CallsParamNoNameBesideSummary;
begin
  ParamNoNameBesideSummary(1);
end;

procedure AttributedRemarks;
begin
end;

procedure CallsAttributedRemarks;
begin
  AttributedRemarks;
end;

procedure AttributedExample;
begin
end;

procedure CallsAttributedExample;
begin
  AttributedExample;
end;

procedure FencedRemarksTailValue;
begin
end;

procedure CallsFencedRemarksTailValue;
begin
  FencedRemarksTailValue;
end;

function MarkedReturnsTail: Integer;
begin
  Result:= 42;
end;

procedure CallsMarkedReturnsTail;
begin
  MarkedReturnsTail;
end;

end.
