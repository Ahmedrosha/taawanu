import { FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';

import { db } from './common';

export interface LocalizedText {
  ar: { title: string; body: string };
  en: { title: string; body: string };
}

/**
 * بيبعت إشعار لكل مستخدم بلغته. الأخطاء مبتوقفش العملية الأساسية،
 * والأجهزة اللي توكنها بقى قديم بتتشال من ملف المستخدم.
 */
export async function notifyUsers(
  uids: string[],
  text: (uid: string) => LocalizedText,
  data: Record<string, string> = {},
): Promise<void> {
  if (uids.length === 0) return;
  try {
    const refs = uids.map((u) => db.collection('users').doc(u));
    const snaps = await db.getAll(...refs);
    const messaging = getMessaging();
    for (const snap of snaps) {
      const d = snap.data();
      const tokens: string[] = Array.isArray(d?.fcmTokens) ? d!.fcmTokens.filter((t: unknown) => typeof t === 'string') : [];
      if (tokens.length === 0) continue;
      const t = text(snap.id)[d?.locale === 'en' ? 'en' : 'ar'];
      const res = await messaging.sendEachForMulticast({
        tokens,
        notification: { title: t.title, body: t.body },
        data,
        apns: { payload: { aps: { sound: 'default' } } },
      });
      const stale = res.responses
        .map((r, i) => ({ r, token: tokens[i] }))
        .filter(({ r }) =>
          !r.success &&
          ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(r.error?.code ?? ''))
        .map(({ token }) => token);
      if (stale.length) {
        await snap.ref.update({ fcmTokens: FieldValue.arrayRemove(...stale) });
      }
    }
  } catch (e) {
    logger.warn('notifyUsers failed', e);
  }
}
