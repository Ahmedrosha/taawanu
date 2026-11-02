// حماية الحسابات: التطبيق بيدخل بجوجل وApple بس. الإيميل والباسورد مفعّل لحساب مراجعة المتاجر.
// أي حساب جديد بإيميل وباسورد مش في القايمة المسموحة بيتمسح أول ما يتعمل، هو وأي بيانات لحق يعملها.
import { getAuth } from 'firebase-admin/auth';
import { logger } from 'firebase-functions';
import * as functionsV1 from 'firebase-functions/v1';

import { db } from './common';
import { deleteGroupData, removeFromGroup } from './groups';
import { isBlockedSignup } from './validation';


// الجيل الأول (v1) هو اللي فيه تنبيه "حساب جديد اتعمل" من غير ترقية Firebase. منطقته us-central1
// لأن الجيل الأول مش متاح في كل المناطق؛ الدالة دي مش بتتعامل مع المستخدمين مباشرة.
export const guardNewUser = functionsV1.region('us-central1').auth.user().onCreate(async (user) => {
  const providers = user.providerData.map((p) => p.providerId);
  if (!isBlockedSignup(providers, user.email)) return;

  logger.warn('Blocked email/password sign-up', { uid: user.uid, email: user.email });
  const uid = user.uid;
  try {
    // مجموعات عملها في الثواني اللي كان موجود فيها.
    const owned = await db.collection('groups').where('adminId', '==', uid).get();
    for (const g of owned.docs) await deleteGroupData(g.id);
    // مجموعات دخلها.
    const index = await db.collection('users').doc(uid).collection('groups').get();
    for (const entry of index.docs) {
      const member = await db.collection('groups').doc(entry.id).collection('members').doc(uid).get();
      if (member.exists) await removeFromGroup(entry.id, uid);
    }
    await db.recursiveDelete(db.collection('users').doc(uid));
  } catch (e) {
    logger.error('Cleanup after blocked sign-up failed', { uid, error: String(e) });
  }
  await getAuth().deleteUser(uid);
});
