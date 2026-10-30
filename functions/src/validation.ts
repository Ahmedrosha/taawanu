// قواعد التحقق من بيانات المجموعة. منفصلة عن Firebase عشان نختبرها بسهولة.

/** المصحف = ٢٤٠ ربع حزب. */
export const TOTAL_QUARTERS = 240;

/** قيم الورد المسموحة بالأرباع: كلها بتقسم ٢٤٠ بالتساوي. */
export const ALLOWED_WARDS = [1, 2, 4, 8, 12, 16, 24, 40] as const;

export const GROUP_TYPES = ['private', 'public'] as const;
export const CYCLE_UNITS = ['day', 'week', 'month'] as const;
export const LATE_POLICIES = ['ask', 'carry', 'distribute', 'volunteer'] as const;

export type GroupType = (typeof GROUP_TYPES)[number];
export type CycleUnit = (typeof CYCLE_UNITS)[number];
export type LatePolicy = (typeof LATE_POLICIES)[number];

export interface NewGroupInput {
  name: string;
  type: GroupType;
  wardQuarters: number;
  slots: number;
  cycleCount: number;
  cycleUnit: CycleUnit;
  /** يوم البداية للدورة الأسبوعية: ٠ الأحد … ٥ الجمعة … ٦ السبت. */
  cycleStartDay: number;
  /** ساعة البداية (بتوقيت الأدمن) للدورة اليومية وكل الأنواع. */
  cycleStartHour: number;
  /** يوم البداية في الشهر للدورة الشهرية (١–٢٨). */
  cycleStartDayOfMonth: number;
  /** فرق توقيت الأدمن عن UTC بالدقايق. */
  utcOffsetMinutes: number;
  lateDefault: LatePolicy;
}

export class ValidationError extends Error {}

function intInRange(value: unknown, min: number, max: number, field: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
    throw new ValidationError(`${field} must be an integer between ${min} and ${max}`);
  }
  return value;
}

function oneOf<T extends string>(value: unknown, options: readonly T[], field: string): T {
  if (typeof value !== 'string' || !(options as readonly string[]).includes(value)) {
    throw new ValidationError(`${field} must be one of: ${options.join(', ')}`);
  }
  return value as T;
}

/** بيتحقق من بيانات إنشاء مجموعة، وبيرجّعها نضيفة مع القيم الافتراضية. */
export function parseNewGroup(raw: unknown): NewGroupInput {
  if (raw === null || typeof raw !== 'object') {
    throw new ValidationError('Request data must be an object');
  }
  const d = raw as Record<string, unknown>;

  const name = typeof d.name === 'string' ? d.name.trim() : '';
  if (name.length < 1 || name.length > 60) {
    throw new ValidationError('name must be 1 to 60 characters');
  }

  const wardQuarters = d.wardQuarters;
  if (typeof wardQuarters !== 'number' || !(ALLOWED_WARDS as readonly number[]).includes(wardQuarters)) {
    throw new ValidationError(`wardQuarters must be one of: ${ALLOWED_WARDS.join(', ')}`);
  }

  return {
    name,
    type: oneOf(d.type, GROUP_TYPES, 'type'),
    wardQuarters,
    slots: TOTAL_QUARTERS / wardQuarters,
    cycleCount: intInRange(d.cycleCount ?? 1, 1, 30, 'cycleCount'),
    cycleUnit: oneOf(d.cycleUnit ?? 'week', CYCLE_UNITS, 'cycleUnit'),
    cycleStartDay: intInRange(d.cycleStartDay ?? 5, 0, 6, 'cycleStartDay'),
    cycleStartHour: intInRange(d.cycleStartHour ?? 6, 0, 23, 'cycleStartHour'),
    cycleStartDayOfMonth: intInRange(d.cycleStartDayOfMonth ?? 1, 1, 28, 'cycleStartDayOfMonth'),
    utcOffsetMinutes: intInRange(d.utcOffsetMinutes ?? 0, -720, 840, 'utcOffsetMinutes'),
    lateDefault: oneOf(d.lateDefault ?? 'ask', LATE_POLICIES, 'lateDefault'),
  };
}
