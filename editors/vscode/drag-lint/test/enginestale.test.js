'use strict';
const assert = require('assert');
const path = require('path');
const pkg = require(path.join(__dirname, '..', 'package.json'));
const { shouldNotify } = require(path.join(__dirname, '..', 'lib', 'enginestale.js'));

// same build: silent
assert.strictEqual(shouldNotify('1:10', '1:10', ''), false);
// newer build deployed, never told: notify
assert.strictEqual(shouldNotify('1:10', '2:11', ''), true);
// already told about THAT build: silent (once per build)
assert.strictEqual(shouldNotify('1:10', '2:11', '2:11'), false);
// a still newer build: notify again
assert.strictEqual(shouldNotify('1:10', '3:12', '2:11'), true);
// unknown stamps never notify
assert.strictEqual(shouldNotify('', '2:11', ''), false);
assert.strictEqual(shouldNotify('1:10', '', ''), false);
// the switch exists and ships OFF: no behaviour change by default
const p = pkg.contributes.configuration.properties['dragLint.engineStaleNoticeMinutes'];
assert.strictEqual(p.type, 'number');
assert.strictEqual(p.default, 0);
console.log('enginestale.test.js: all assertions passed');
