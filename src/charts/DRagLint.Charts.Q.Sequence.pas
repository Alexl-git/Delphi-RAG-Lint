unit DRagLint.Charts.Q.Sequence;

{ drag-lint 1.56 -- lane CHB-1: the chart question `sequence` (`ask sequence`).
  G-45: the calls of the target routine in source order, as a sequence diagram.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question
  (written by W2FRAME; another wording is a request to INT). The row is NOT a question yet: it joins QuestionIds,
  the ask verb's list, QuestionPhrase and QuestionVocab when this unit registers its emitter, as every Q unit does:
    initialization
      RegisterChartQuestion('sequence', Emit);
  Scaffold created EMPTY by lane W2FRAME (tranche 2); lane CHB-1 owns this unit. }

interface

implementation

end.
