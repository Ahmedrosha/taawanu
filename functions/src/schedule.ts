// حساب مواعيد الدورات. بنحوّل للتوقيت المحلي للأدمن بفرق التوقيت، ونحسب، ونرجع لـUTC.

export type CycleUnit = 'day' | 'week' | 'month';

export interface CycleSettings {
  cycleCount: number;
  cycleUnit: CycleUnit;
  cycleStartDay: number; // ٠ الأحد … ٦ السبت
  cycleStartHour: number; // ٠–٢٣
  cycleStartDayOfMonth: number; // ١–٢٨
  utcOffsetMinutes: number;
}

const DAY_MS = 24 * 60 * 60 * 1000;

function toLocal(d: Date, offset: number): Date {
  return new Date(d.getTime() + offset * 60_000);
}

function fromLocal(d: Date, offset: number): Date {
  return new Date(d.getTime() - offset * 60_000);
}

/** بيضيف n وحدة (يوم/أسبوع/شهر) على تاريخ، بالتوقيت المحلي. */
export function addUnits(date: Date, s: CycleSettings, n: number): Date {
  const l = toLocal(date, s.utcOffsetMinutes);
  if (s.cycleUnit === 'day') l.setUTCDate(l.getUTCDate() + n);
  else if (s.cycleUnit === 'week') l.setUTCDate(l.getUTCDate() + 7 * n);
  else l.setUTCMonth(l.getUTCMonth() + n);
  return fromLocal(l, s.utcOffsetMinutes);
}

/** أول نقطة بداية مضبوطة على إعدادات المجموعة بعد "دلوقتي" مباشرة. */
export function nextBoundary(now: Date, s: CycleSettings): Date {
  const l = toLocal(now, s.utcOffsetMinutes);
  const b = new Date(Date.UTC(l.getUTCFullYear(), l.getUTCMonth(), l.getUTCDate(), s.cycleStartHour, 0, 0));
  if (s.cycleUnit === 'day') {
    if (b <= l) b.setUTCDate(b.getUTCDate() + 1);
  } else if (s.cycleUnit === 'week') {
    const diff = (s.cycleStartDay - b.getUTCDay() + 7) % 7;
    b.setUTCDate(b.getUTCDate() + diff);
    if (b <= l) b.setUTCDate(b.getUTCDate() + 7);
  } else {
    b.setUTCDate(s.cycleStartDayOfMonth);
    if (b <= l) b.setUTCMonth(b.getUTCMonth() + 1);
  }
  return fromLocal(b, s.utcOffsetMinutes);
}

function approxUnitMs(unit: CycleUnit): number {
  return unit === 'day' ? DAY_MS : unit === 'week' ? 7 * DAY_MS : 30 * DAY_MS;
}

/**
 * نهاية أول دورة: أول نقطة بداية مضبوطة، وبعدها (عدد الوحدات − ١).
 * ولو الدورة الأولى طلعت أقصر من نص وحدة، بنزود وحدة عشان الناس تلحق تقرا.
 */
export function firstCycleEnd(now: Date, s: CycleSettings): Date {
  let end = nextBoundary(now, s);
  if (s.cycleCount > 1) end = addUnits(end, s, s.cycleCount - 1);
  if (end.getTime() - now.getTime() < approxUnitMs(s.cycleUnit) / 2) end = addUnits(end, s, 1);
  return end;
}

/** نهاية الدورة اللي بعدها. */
export function nextCycleEnd(previousEnd: Date, s: CycleSettings): Date {
  return addUnits(previousEnd, s, s.cycleCount);
}

/** نص الدورة: موعد تذكير اللي لسه مبدأش. */
export function midpoint(start: Date, end: Date): Date {
  return new Date((start.getTime() + end.getTime()) / 2);
}

/** قبل النهاية بيوم (أو بربع المدة لو الدورة أقل من يومين). */
export function lastCallTime(start: Date, end: Date): Date {
  const span = end.getTime() - start.getTime();
  const before = span >= 2 * DAY_MS ? DAY_MS : span / 4;
  return new Date(end.getTime() - before);
}
