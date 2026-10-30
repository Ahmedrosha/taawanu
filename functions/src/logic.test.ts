import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { regularPoints } from './points';
import { pickCycle, rangeLabel, segmentFor, segmentRange, slotForSegment, splitRange, takenSegments } from './rotation';
import { CycleSettings, firstCycleEnd, nextBoundary, nextCycleEnd } from './schedule';

describe('التدوير', () => {
  test('الدورة ١: الخانة ٠ تقرا الجزء ١، والدورة ٢ تقرا الجزء ٢', () => {
    assert.deepEqual(segmentRange(segmentFor(0, 1, 30), 8), { fromQuarter: 1, toQuarter: 8 });
    assert.deepEqual(segmentRange(segmentFor(0, 2, 30), 8), { fromQuarter: 9, toQuarter: 16 });
  });
  test('آخر خانة بتلف للجزء ١ في الدورة التانية', () => {
    assert.equal(segmentFor(29, 2, 30), 0);
  });
  test('كل دورة بتغطي المصحف كله من غير تكرار', () => {
    for (const slots of [6, 10, 30, 240]) {
      for (const cycle of [1, 2, 7, 31]) {
        const segs = new Set(Array.from({ length: slots }, (_, s) => segmentFor(s, cycle, slots)));
        assert.equal(segs.size, slots);
      }
    }
  });
  test('slotForSegment عكس segmentFor', () => {
    for (let s = 0; s < 30; s++) assert.equal(slotForSegment(segmentFor(s, 5, 30), 5, 30), s);
  });
  test('بعد عدد الخانات من الدورات، كل عضو قرا المصحف كله (ختمة شخصية)', () => {
    const read = new Set(Array.from({ length: 30 }, (_, c) => segmentFor(3, c + 1, 30)));
    assert.equal(read.size, 30);
  });
});

describe('تقسيم الورد', () => {
  test('جزء على ٣ أشخاص: ٣ و٣ و٢', () => {
    assert.deepEqual(splitRange({ fromQuarter: 9, toQuarter: 16 }, 3), [
      { fromQuarter: 9, toQuarter: 11 },
      { fromQuarter: 12, toQuarter: 14 },
      { fromQuarter: 15, toQuarter: 16 },
    ]);
  });
  test('مفيش حد ياخد صفر لو الناس أكتر من الأرباع', () => {
    assert.equal(splitRange({ fromQuarter: 5, toQuarter: 6 }, 10).length, 2);
  });
});

describe('الوصف', () => {
  test('جزء وحزب وأرباع', () => {
    assert.equal(rangeLabel({ fromQuarter: 49, toQuarter: 56 }, 'ar'), 'الجزء 7');
    assert.equal(rangeLabel({ fromQuarter: 5, toQuarter: 8 }, 'ar'), 'الحزب 2');
    assert.equal(rangeLabel({ fromQuarter: 1, toQuarter: 24 }, 'en'), 'Juz 1–3');
    assert.equal(rangeLabel({ fromQuarter: 3, toQuarter: 3 }, 'ar'), 'الربع 3');
  });
});

const weekly: CycleSettings = {
  cycleCount: 1, cycleUnit: 'week', cycleStartDay: 5, cycleStartHour: 6,
  cycleStartDayOfMonth: 1, utcOffsetMinutes: 240,
};

describe('المواعيد', () => {
  test('الدورة الأسبوعية بتنتهي الجمعة ٦ الصبح بتوقيت دبي', () => {
    // الأربعاء ٤ نوفمبر ٢٠٢٦، ١٠ الصبح بتوقيت دبي = ٦ الصبح UTC
    const end = firstCycleEnd(new Date('2026-11-04T06:00:00Z'), weekly);
    // الجمعة ١٣ نوفمبر ٦ الصبح دبي = ٢ الصبح UTC (الجمعة ٦ كانت بعد يومين بس فاتزودت أسبوع)
    assert.equal(end.toISOString(), '2026-11-13T02:00:00.000Z');
  });
  test('لو البداية قبل الجمعة بأكتر من نص أسبوع، بتنتهي الجمعة الجاية', () => {
    const end = firstCycleEnd(new Date('2026-11-01T06:00:00Z'), weekly); // الأحد
    assert.equal(end.toISOString(), '2026-11-06T02:00:00.000Z');
  });
  test('الدورة اللي بعدها بعد أسبوع بالظبط', () => {
    assert.equal(nextCycleEnd(new Date('2026-11-06T02:00:00Z'), weekly).toISOString(), '2026-11-13T02:00:00.000Z');
  });
  test('الدورة اليومية: الساعة ٦ الجاية', () => {
    const daily = { ...weekly, cycleUnit: 'day' as const };
    assert.equal(nextBoundary(new Date('2026-11-04T01:00:00Z'), daily).toISOString(), '2026-11-04T02:00:00.000Z');
    assert.equal(nextBoundary(new Date('2026-11-04T03:00:00Z'), daily).toISOString(), '2026-11-05T02:00:00.000Z');
  });
  test('الدورة الشهرية: يوم ١ من الشهر الجاي', () => {
    const monthly = { ...weekly, cycleUnit: 'month' as const };
    assert.equal(nextBoundary(new Date('2026-11-04T06:00:00Z'), monthly).toISOString(), '2026-12-01T02:00:00.000Z');
  });
});

describe('النقاط', () => {
  test('جزء في الميعاد وبدري = ٨٠+٢٠+١٠', () => {
    assert.equal(regularPoints(8, true, true), 110);
    assert.equal(regularPoints(8, true, false), 100);
    assert.equal(regularPoints(8, false, true), 80);
  });
});

describe('اختيار الجزء', () => {
  test('قبل البداية: اللي اختار الجزء ٧ يقراه في الدورة الأولى وبعده ٨', () => {
    const slot = slotForSegment(6, pickCycle('forming', 0, false), 30);
    assert.equal(segmentFor(slot, 1, 30), 6);
    assert.equal(segmentFor(slot, 2, 30), 7);
  });
  test('بعد البداية: المنضم ياخد الجزء في الدورة الحالية', () => {
    const cycle = pickCycle('active', 4, false);
    assert.equal(cycle, 4);
    assert.equal(segmentFor(slotForSegment(10, cycle, 30), 4, 30), 10);
  });
  test('النقل بعد البداية بيبدأ من الدورة الجاية', () => {
    assert.equal(pickCycle('active', 4, true), 5);
    assert.equal(pickCycle('forming', 0, true), 1);
  });
  test('الأجزاء المحجوزة محسوبة على الدورة', () => {
    assert.deepEqual(takenSegments([0, 5], 1, 30), [0, 5]);
    assert.deepEqual(takenSegments([0, 29], 2, 30), [0, 1]);
  });
});
