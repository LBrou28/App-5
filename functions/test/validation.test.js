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
const { itemFields } = require('../lib/validation');

test('item fields trim text, preserve notes punctuation and constrain photo ownership', () => {
  assert.deepEqual(itemFields({name: '  Toolbox ', category: ' Tools ', notes: ' top/bottom ', photoPath: 'households/h/items/i/photo-1'}, 'h', 'i'), {
    name: 'Toolbox', category: 'Tools', notes: 'top/bottom', locationId: null, photoPath: 'households/h/items/i/photo-1',
  });
  for (const photoPath of ['households/other/items/i/photo', 'households/h/items/other/photo', 'households/h/items/i/../photo', 123]) {
    assert.throws(() => itemFields({name: 'Toolbox', photoPath}, 'h', 'i'));
  }
  for (const data of [{name: ''}, {name: 'x', category: 'x'.repeat(101)}, {name: 'x', notes: 'x'.repeat(2001)}, {name: 'x', locationId: 'other/room'}]) {
    assert.throws(() => itemFields(data, 'h', 'i'));
  }
});
