unit DRagLint.Charts.Q.ControlFlow;

{ drag-lint 1.56 -- lane CHB-2: the chart question `control-flow` (`ask control-flow`).
  G-44: the control-flow graph of the target routine, with a node cap that says where it stops.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question
  (written by W2FRAME; another wording is a request to INT). The row is NOT a question yet: it joins QuestionIds,
  the ask verb's list, QuestionPhrase and QuestionVocab when this unit registers its emitter, as every Q unit does:
    initialization
      RegisterChartQuestion('control-flow', Emit);
  Scaffold created EMPTY by lane W2FRAME (tranche 2); lane CHB-2 owns this unit. }

interface

implementation

end.
