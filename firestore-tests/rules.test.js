// اختبارات قواعد أمان Firestore. بتشتغل على المحاكي (emulator) في GitHub Actions.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc, doc, getDoc, serverTimestamp, setDoc, updateDoc,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-taawanu',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

after(async () => { await env.cleanup(); });

// بيانات تجريبية: مجموعة خاصة فيها أدمن ومساعد وعضو، ومجموعة عامة.
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const group = {
      name: 'ختمة الأصحاب', type: 'private', wardQuarters: 8, slots: 30,
      cycleCount: 1, cycleUnit: 'week', lateDefault: 'ask', isOpen: true,
    };
    await setDoc(doc(db, 'groups/g1'), group);
    await setDoc(doc(db, 'groups/g1/members/admin'), { role: 'admin', slot: 0 });
    await setDoc(doc(db, 'groups/g1/members/asst'), { role: 'assistant', slot: 1 });
    await setDoc(doc(db, 'groups/g1/members/m1'), { role: 'member', slot: 2 });
    await setDoc(doc(db, 'groups/g1/cycles/c1/assignments/m1'), {
      fromQuarter: 17, toQuarter: 24, quarterCount: 8, quartersRead: 0, status: 'pending',
    });
    await setDoc(doc(db, 'groups/pub'), { ...group, type: 'public' });
    await setDoc(doc(db, 'users/m1'), { name: 'عضو', points: 10 });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe('المستخدمين', () => {
  test('المستخدم ينشئ ملفه بالحقول المسموحة', async () => {
    await assertSucceeds(setDoc(doc(as('u2'), 'users/u2'), {
      name: 'جديد', locale: 'ar', createdAt: serverTimestamp(),
    }));
  });
  test('المستخدم يسجل أجهزته للإشعارات', async () => {
    await assertSucceeds(updateDoc(doc(as('m1'), 'users/m1'), { fcmTokens: ['token-1'] }));
  });
  test('المستخدم ميقدرش يدّي نفسه نقاط', async () => {
    await assertFails(updateDoc(doc(as('m1'), 'users/m1'), { points: 9999 }));
  });
  test('محدش يعدل ملف حد تاني', async () => {
    await assertFails(updateDoc(doc(as('m2'), 'users/m1'), { name: 'تغيير' }));
  });
  test('غير المسجّل ميقراش', async () => {
    await assertFails(getDoc(doc(anon(), 'users/m1')));
  });
});

describe('المجموعات', () => {
  test('العضو يقرا مجموعته الخاصة', async () => {
    await assertSucceeds(getDoc(doc(as('m1'), 'groups/g1')));
  });
  test('غير العضو ميقراش المجموعة الخاصة', async () => {
    await assertFails(getDoc(doc(as('stranger'), 'groups/g1')));
  });
  test('أي حد مسجّل يقرا المجموعة العامة', async () => {
    await assertSucceeds(getDoc(doc(as('stranger'), 'groups/pub')));
  });
  test('محدش ينشئ مجموعة من التطبيق مباشرة', async () => {
    await assertFails(setDoc(doc(as('m1'), 'groups/new'), { name: 'x', type: 'public' }));
  });
  test('حتى الأدمن ميعدلش المجموعة مباشرة (عن طريق السيرفر بس)', async () => {
    await assertFails(updateDoc(doc(as('admin'), 'groups/g1'), { cycleCount: 2 }));
    await assertFails(updateDoc(doc(as('admin'), 'groups/g1'), { wardQuarters: 4 }));
  });
});

describe('الأعضاء', () => {
  test('أعضاء المجموعة يشوفوا بعض', async () => {
    await assertSucceeds(getDoc(doc(as('m1'), 'groups/g1/members/admin')));
  });
  test('غير الأعضاء ميشوفوش الأعضاء', async () => {
    await assertFails(getDoc(doc(as('stranger'), 'groups/g1/members/admin')));
  });
  test('محدش يضيف نفسه لمجموعة', async () => {
    await assertFails(setDoc(doc(as('stranger'), 'groups/g1/members/stranger'), { role: 'member', slot: 5 }));
  });
  test('محدش يغير دوره أو دور غيره مباشرة', async () => {
    await assertFails(updateDoc(doc(as('asst'), 'groups/g1/members/asst'), { role: 'admin' }));
    await assertFails(updateDoc(doc(as('admin'), 'groups/g1/members/m1'), { role: 'assistant' }));
  });
  test('محدش يمسح عضو مباشرة', async () => {
    await assertFails(deleteDoc(doc(as('m1'), 'groups/g1/members/m1')));
  });
});

describe('الأوراد', () => {
  const path = 'groups/g1/cycles/c1/assignments/m1';
  test('أعضاء المجموعة يشوفوا الأوراد', async () => {
    await assertSucceeds(getDoc(doc(as('asst'), path)));
  });
  test('غير الأعضاء ميشوفوش الأوراد', async () => {
    await assertFails(getDoc(doc(as('stranger'), path)));
  });
  test('حتى صاحب الورد ميسجلش مباشرة (عن طريق السيرفر عشان النقاط)', async () => {
    await assertFails(updateDoc(doc(as('m1'), path), { quartersRead: 8, status: 'done', completedAt: serverTimestamp() }));
  });
  test('الأوراد الإضافية للأعضاء بس، ومحدش يكتب فيها', async () => {
    await assertSucceeds(getDoc(doc(as('m1'), 'groups/g1/portions/p1')));
    await assertFails(getDoc(doc(as('stranger'), 'groups/g1/portions/p1')));
    await assertFails(setDoc(doc(as('m1'), 'groups/g1/portions/p1'), { assignee: 'm1' }));
  });
});

describe('فهرس مجموعاتي', () => {
  test('المستخدم يقرا قايمة مجموعاته', async () => {
    await assertSucceeds(getDoc(doc(as('m1'), 'users/m1/groups/g1')));
  });
  test('محدش يقرا قايمة مجموعات حد تاني', async () => {
    await assertFails(getDoc(doc(as('m2'), 'users/m1/groups/g1')));
  });
  test('المستخدم ميضيفش مجموعة لقايمته بنفسه', async () => {
    await assertFails(setDoc(doc(as('m1'), 'users/m1/groups/g9'), { name: 'x', role: 'admin' }));
  });
});

describe('الدعوات', () => {
  test('محدش يقرا أكواد الدعوات من التطبيق', async () => {
    await assertFails(getDoc(doc(as('admin'), 'invites/ABC123')));
  });
});
