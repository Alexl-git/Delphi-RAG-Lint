unit DRagLint.Charts.Q.SentNotHandled;

{ drag-lint 1.56 -- lane CHB-2: the chart question `sent-not-handled` (`ask sent-not-handled`).
  G-71: protocol commands that are sent but never handled, over --counterpart-db.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question
  (written by W2FRAME; another wording is a request to INT). The row is NOT a question yet: it joins QuestionIds,
  the ask verb's list, QuestionPhrase and QuestionVocab when this unit registers its emitter, as every Q unit does:
    initialization
      RegisterChartQuestion('sent-not-handled', Emit);
  Scaffold created EMPTY by lane W2FRAME (tranche 2); lane CHB-2 owns this unit. }

interface

implementation

end.
