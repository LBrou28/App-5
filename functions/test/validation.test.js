const { test } = require('node:test');
const assert = require('node:assert/strict');
const { requireText, canBorrow } = require('../lib/validation');
test('rejects blank names and document path injection', () => {
  for (const value of ['', '  ', 'households/other', null, 123]) assert.throws(() => requireText(value, 'id'));
  assert.equal(requireText('  toolbox  ', 'name'), 'toolbox');
});
test('only items with no active loan can be borrowed', () => {
  assert.equal(canBorrow(null), true);
  assert.equal(canBorrow(undefined), true);
  assert.equal(canBorrow('loan-1'), false);
  assert.equal(canBorrow(''), false);
});
