'use strict';

// DEC-14 (wave 146, lane g2): engine staleness POLICY for a long-lived window.
//
// The private engine copy is refreshed only at activation, on purpose: a live
// language server is never swapped underneath the user. The one thing a window
// can do cheaply is SAY that a newer deployed engine exists and offer the
// existing "Update Engine Copy Now" command. This module is the pure decision;
// extension.js owns the timer, the notification and the stat calls.
//
// Policy, in one line: notify at most once per distinct deployed build, never
// restart anything, and stay silent when either stamp is unknown.

/**
 * @param {string} runningStamp stamp (mtimeMs:size) of the deployed engine the running copy was made from; '' = unknown
 * @param {string} sourceStamp  stamp of the deployed engine now; '' = unreadable
 * @param {string} lastNotified the sourceStamp a notice was already shown for; '' = none
 * @returns {boolean} true when a notice should be shown now
 */
function shouldNotify(runningStamp, sourceStamp, lastNotified) {
  if (!runningStamp || !sourceStamp) return false;
  if (runningStamp === sourceStamp) return false;
  return sourceStamp !== lastNotified;
}

module.exports = { shouldNotify };
