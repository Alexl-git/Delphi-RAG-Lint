unit DRagLint.Charts.Q.DepMatrix;

{ drag-lint 1.56 -- lane CHA-1: the chart question `dependency-matrix` (`ask dependency-matrix`).
  G-40: the unit dependency matrix (library units as one row), drawn by DRagLint.Charts.Adapter.Grid.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question
  (written by W2FRAME; another wording is a request to INT). The row is NOT a question yet: it joins QuestionIds,
  the ask verb's list, QuestionPhrase and QuestionVocab when this unit registers its emitter, as every Q unit does:
    initialization
      RegisterChartQuestion('dependency-matrix', Emit);
  Scaffold created EMPTY by lane W2FRAME (tranche 2); lane CHA-1 owns this unit. }

interface

implementation

end.
