// قيم النقاط (زي وثيقة المواصفات).

/** لكل ربع حزب في الورد العادي. */
export const POINTS_PER_QUARTER = 10;
/** بونص لو خلص الورد قبل نهاية الدورة. */
export const ON_TIME_BONUS = 20;
/** بونص إضافي لو خلص في أول نص الدورة. */
export const EARLY_BONUS = 10;
/** لكل ربع من ورد حد تاني (تطوع، أو توزيع، أو خانة فاضية). */
export const RESCUE_POINTS_PER_QUARTER = 15;
/** لكل الأعضاء لما الختمة الجماعية تكتمل. */
export const KHATMA_BONUS = 50;
/** لما العضو يكمّل ختمة شخصية (قرا كل القطع بالتدوير). */
export const PERSONAL_KHATMA_BONUS = 200;

export const BADGES = {
  firstKhatma: 'first_khatma',
  streak4: 'streak_4',
  streak12: 'streak_12',
  starter: 'starter', // أول واحد يخلص في الدورة
  rescuer: 'rescuer', // أخد ورد حد تاني وخلصه
  personalKhatma: 'personal_khatma',
} as const;

export function regularPoints(quarters: number, onTime: boolean, early: boolean): number {
  return quarters * POINTS_PER_QUARTER + (onTime ? ON_TIME_BONUS : 0) + (onTime && early ? EARLY_BONUS : 0);
}
