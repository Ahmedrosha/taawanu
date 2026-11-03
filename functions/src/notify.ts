import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';

import { db } from './common';

export interface LocalizedText {
  ar: { title: string; body: string };
  en: { title: string; body: string };
}

/** الإشعارات بتتمسح لوحدها بعد المدة دي (سياسة TTL على expireAt). */
const KEEP_DAYS = 30;

/**
 * بيحفظ الإشعار في صفحة الإشعارات (الجرس) بتاعة كل مستخدم، باللغتين عشان يظهر بلغة التطبيق.
 */
async function saveToInbox(uids: string[], text: (uid: string) => LocalizedText, data: Record<string, string>): Promise<void> {
  const expireAt = Timestamp.fromMillis(Date.now() + KEEP_DAYS * 24 * 3600 * 1000);
  for (let i = 0; i < uids.length; i += 400) {
    const batch = db.batch();
    for (const uid of uids.slice(i, i + 400)) {
      const t = text(uid);
      batch.set(db.collection('users').doc(uid).collection('notifications').doc(), {
        ar: t.ar,
        en: t.en,
        groupId: data.groupId ?? null,
        type: data.type ?? null,
        createdAt: FieldValue.serverTimestamp(),
        expireAt,
      });
    }
    await batch.commit();
  }
}

/**
 * بيبعت إشعار لكل مستخدم بلغته، وبيحفظه في الجرس. الأخطاء مبتوقفش العملية الأساسية،
 * والأجهزة اللي توكنها بقى قديم بتتشال من ملف المستخدم.
 */
export async function notifyUsers(
  uids: string[],
  text: (uid: string) => LocalizedText,
  data: Record<string, string> = {},
): Promise<void> {
  if (uids.length === 0) return;
  try {
    await saveToInbox(uids, text, data);
  } catch (e) {
    logger.warn('saveToInbox failed', e);
  }
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
