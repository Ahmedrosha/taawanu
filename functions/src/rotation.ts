// منطق الخانات والتدوير. دوال صافية من غير Firebase عشان نختبرها.

/** المصحف = ٢٤٠ ربع حزب. */
export const TOTAL_QUARTERS = 240;

/**
 * القطعة اللي صاحب الخانة بيقراها في دورة معينة.
 * الدورة ١: الخانة ٠ تقرا القطعة ٠. وكل دورة الكل بيتحرك قطعة لقدام.
 */
export function segmentFor(slot: number, cycle: number, slots: number): number {
  return (((slot + cycle - 1) % slots) + slots) % slots;
}

/** الخانة اللي بتقرا قطعة معينة في دورة معينة (عكس segmentFor). */
export function slotForSegment(segment: number, cycle: number, slots: number): number {
  return (((segment - (cycle - 1)) % slots) + slots) % slots;
}

export interface QuarterRange {
  fromQuarter: number;
  toQuarter: number;
}

/** حدود القطعة بالأرباع (من ١ لـ٢٤٠). */
export function segmentRange(segment: number, wardQuarters: number): QuarterRange {
  return { fromQuarter: segment * wardQuarters + 1, toQuarter: (segment + 1) * wardQuarters };
}

export function quarterCount(r: QuarterRange): number {
  return r.toQuarter - r.fromQuarter + 1;
}

/** تقسيم مدى متصل على عدد من الناس بأقرب تساوي ممكن، من غير ما حد ياخد صفر. */
export function splitRange(r: QuarterRange, parts: number): QuarterRange[] {
  const total = quarterCount(r);
  const n = Math.max(1, Math.min(parts, total));
  const base = Math.floor(total / n);
  let extra = total % n;
  const out: QuarterRange[] = [];
  let start = r.fromQuarter;
  for (let i = 0; i < n; i++) {
    const size = base + (extra > 0 ? 1 : 0);
    if (extra > 0) extra--;
    out.push({ fromQuarter: start, toQuarter: start + size - 1 });
    start += size;
  }
  return out;
}

/** وصف عربي/إنجليزي لمدى الأرباع (للإشعارات). */
export function rangeLabel(r: QuarterRange, locale: string): string {
  const ar = locale !== 'en';
  const count = quarterCount(r);
  const juzAligned = (r.fromQuarter - 1) % 8 === 0 && count % 8 === 0;
  const hizbAligned = (r.fromQuarter - 1) % 4 === 0 && count % 4 === 0;
  if (juzAligned) {
    const a = (r.fromQuarter - 1) / 8 + 1;
    const b = r.toQuarter / 8;
    if (a === b) return ar ? `الجزء ${a}` : `Juz ${a}`;
    return ar ? `الأجزاء ${a}–${b}` : `Juz ${a}–${b}`;
  }
  if (hizbAligned) {
    const a = (r.fromQuarter - 1) / 4 + 1;
    const b = r.toQuarter / 4;
    if (a === b) return ar ? `الحزب ${a}` : `Hizb ${a}`;
    return ar ? `الأحزاب ${a}–${b}` : `Hizb ${a}–${b}`;
  }
  if (count === 1) return ar ? `الربع ${r.fromQuarter}` : `Quarter ${r.fromQuarter}`;
  return ar ? `الأرباع ${r.fromQuarter}–${r.toQuarter}` : `Quarters ${r.fromQuarter}–${r.toQuarter}`;
}

/**
 * الدورة اللي اختيار الجزء بيتحسب عليها.
 * قبل البداية: الدورة ١. وبعدها: الانضمام بيبقى للدورة الحالية (بياخد الورد الفاضي على طول)،
 * والنقل بيبقى من الدورة الجاية (عشان أوراد الدورة الحالية متوزعة خلاص).
 */
export function pickCycle(status: string, currentCycle: number, forMove: boolean): number {
  if (status !== 'active') return 1;
  return forMove ? currentCycle + 1 : currentCycle;
}

/** القطع المحجوزة في دورة معينة، من خانات الأعضاء. */
export function takenSegments(memberSlots: number[], cycle: number, slots: number): number[] {
  return memberSlots.map((s) => segmentFor(s, cycle, slots)).sort((a, b) => a - b);
}
