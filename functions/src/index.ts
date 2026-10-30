import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { parseNewGroup, ValidationError } from './validation';

initializeApp();

// نفس منطقة قاعدة البيانات (الدمام)، وحد أقصى للنسخ عشان التكلفة تفضل تحت السيطرة.
setGlobalOptions({ region: 'me-central2', maxInstances: 10 });

const db = getFirestore();

/** حد أقصى لعدد المجموعات اللي المستخدم الواحد يقدر يعملها، ضد الإساءة. */
const MAX_GROUPS_CREATED_PER_USER = 20;

/**
 * إنشاء مجموعة جديدة. اللي بيعملها بيبقى الأدمن، وبياخد أول خانة.
 * بيرجّع { groupId }.
 */
export const createGroup = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }

  let input;
  try {
    input = parseNewGroup(request.data);
  } catch (e) {
    if (e instanceof ValidationError) {
      throw new HttpsError('invalid-argument', e.message);
    }
    throw e;
  }

  const created = await db
    .collection('groups')
    .where('adminId', '==', uid)
    .count()
    .get();
  if (created.data().count >= MAX_GROUPS_CREATED_PER_USER) {
    throw new HttpsError('resource-exhausted', 'Too many groups created.');
  }

  const groupRef = db.collection('groups').doc();
  const now = FieldValue.serverTimestamp();

  const batch = db.batch();
  batch.set(groupRef, {
    ...input,
    adminId: uid,
    memberCount: 1,
    // forming: لسه مبدأتش. أول دورة بتبدأ لما الأدمن يبدأ الختمة.
    status: 'forming',
    currentCycle: 0,
    khatmasCompleted: 0,
    isOpen: true,
    createdAt: now,
  });
  batch.set(groupRef.collection('members').doc(uid), {
    role: 'admin',
    slot: 0,
    joinedAt: now,
  });
  // فهرس "مجموعاتي" للمستخدم: التطبيق بيقراه عشان يعرض مجموعاته.
  batch.set(db.collection('users').doc(uid).collection('groups').doc(groupRef.id), {
    name: input.name,
    type: input.type,
    role: 'admin',
    wardQuarters: input.wardQuarters,
    joinedAt: now,
  });
  await batch.commit();

  return { groupId: groupRef.id };
});
