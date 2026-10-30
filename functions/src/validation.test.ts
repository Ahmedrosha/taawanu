import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { parseNewGroup, ValidationError } from './validation';

const base = { name: 'ختمة الأصحاب', type: 'private', wardQuarters: 8 };

describe('parseNewGroup', () => {
  test('ورد جزء = ٣٠ خانة، والقيم الافتراضية: أسبوع يبدأ الجمعة', () => {
    const g = parseNewGroup(base);
    assert.equal(g.slots, 30);
    assert.equal(g.cycleCount, 1);
    assert.equal(g.cycleUnit, 'week');
    assert.equal(g.cycleStartDay, 5);
    assert.equal(g.lateDefault, 'ask');
  });

  test('عدد الخانات لكل ورد مسموح', () => {
    const expected: Record<number, number> = { 1: 240, 2: 120, 4: 60, 8: 30, 12: 20, 16: 15, 24: 10, 40: 6 };
    for (const [ward, slots] of Object.entries(expected)) {
      assert.equal(parseNewGroup({ ...base, wardQuarters: Number(ward) }).slots, slots);
    }
  });

  test('ورد ٤ أجزاء مرفوض لأنه مبيقسمش المصحف بالتساوي', () => {
    assert.throws(() => parseNewGroup({ ...base, wardQuarters: 32 }), ValidationError);
  });

  test('الاسم بيتقص منه المسافات، والفاضي مرفوض', () => {
    assert.equal(parseNewGroup({ ...base, name: '  ختمة  ' }).name, 'ختمة');
    assert.throws(() => parseNewGroup({ ...base, name: '   ' }), ValidationError);
    assert.throws(() => parseNewGroup({ ...base, name: 'x'.repeat(61) }), ValidationError);
  });

  test('مدة الدورة من ١ لـ٣٠', () => {
    assert.equal(parseNewGroup({ ...base, cycleCount: 30, cycleUnit: 'day' }).cycleCount, 30);
    assert.throws(() => parseNewGroup({ ...base, cycleCount: 0 }), ValidationError);
    assert.throws(() => parseNewGroup({ ...base, cycleCount: 31 }), ValidationError);
    assert.throws(() => parseNewGroup({ ...base, cycleCount: 1.5 }), ValidationError);
  });

  test('نوع المجموعة ووحدة الدورة لازم من القيم المسموحة', () => {
    assert.throws(() => parseNewGroup({ ...base, type: 'secret' }), ValidationError);
    assert.throws(() => parseNewGroup({ ...base, cycleUnit: 'year' }), ValidationError);
  });
});
