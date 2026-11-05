import { getAuth } from 'firebase-admin/auth';
import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

import { db, memberRef, requireUid } from './common';
import { cleanDisplayName } from './validation';

/**
 * تغيير اسم المستخدم: في ملفه، وفي كل مجموعة هو عضو فيها (الاسم متنسخ في الأعضاء)،
 * وفي حساب الدخول. الإشعارات القديمة بتفضل بالاسم القديم.
 */
export const updateName = onCall(async (request) => {
  const uid = requireUid(request);
  const name = cleanDisplayName(request.data?.name);
  if (!name) throw new HttpsError('invalid-argument', 'Name must be 1 to 60 characters.');

  const userRef = db.collection('users').doc(uid);
  const index = await userRef.collection('groups').get();
  const refs = index.docs.map((d) => memberRef(d.id, uid));
  const existing = refs.length ? (await db.getAll(...refs)).filter((s) => s.exists).map((s) => s.ref) : [];

  const all = [userRef, ...existing];
  for (let i = 0; i < all.length; i += 400) {
    const batch = db.batch();
    for (const ref of all.slice(i, i + 400)) batch.update(ref, { name });
    await batch.commit();
  }
  try {
    await getAuth().updateUser(uid, { displayName: name });
  } catch (e) {
    logger.warn('updateUser displayName failed', e);
  }
  return { name };
});

/**
 * الموبايل ده بقى بتاع الحساب ده: عنوان الإشعارات بيتضاف له، وبيتشال من أي حساب تاني اتسجّل عليه
 * قبل كده (مثلًا حد دخل بحسابين على نفس الموبايل)، عشان إشعارات الحساب التاني متوصلوش.
 */
export const claimFcmToken = onCall(async (request) => {
  const uid = requireUid(request);
  const token = request.data?.token;
  if (typeof token !== 'string' || token.length < 10 || token.length > 4096) {
    throw new HttpsError('invalid-argument', 'Bad token.');
  }
  const others = await db.collection('users').where('fcmTokens', 'array-contains', token).get();
  const batch = db.batch();
  for (const d of others.docs) {
    if (d.id !== uid) batch.update(d.ref, { fcmTokens: FieldValue.arrayRemove(token) });
  }
  const me = db.collection('users').doc(uid);
  const snap = await me.get();
  const tokens: string[] = Array.isArray(snap.data()?.fcmTokens) ? snap.data()!.fcmTokens.filter((t: unknown) => typeof t === 'string') : [];
  if (!tokens.includes(token)) {
    const next = [...tokens, token].slice(-10);
    batch.set(me, { fcmTokens: next }, { merge: true });
  }
  await batch.commit();
  return { moved: others.docs.filter((d) => d.id !== uid).length };
});
