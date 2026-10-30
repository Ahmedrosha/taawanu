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
  test('المساعد يغير مدة الدورة', async () => {
    await assertSucceeds(updateDoc(doc(as('asst'), 'groups/g1'), { cycleCount: 2, cycleUnit: 'day' }));
  });
  test('العضو العادي ميغيرش الإعدادات', async () => {
    await assertFails(updateDoc(doc(as('m1'), 'groups/g1'), { cycleCount: 2 }));
  });
  test('حتى الأدمن ميغيرش الورد', async () => {
    await assertFails(updateDoc(doc(as('admin'), 'groups/g1'), { wardQuarters: 4 }));
  });
  test('مدة الدورة لازم من ١ لـ٣٠', async () => {
    await assertFails(updateDoc(doc(as('admin'), 'groups/g1'), { cycleCount: 31 }));
  });
});

describe('الأعضاء', () => {
  test('محدش يضيف نفسه لمجموعة', async () => {
    await assertFails(setDoc(doc(as('stranger'), 'groups/g1/members/stranger'), { role: 'member', slot: 5 }));
  });
  test('الأدمن يرقّي عضو لمساعد', async () => {
    await assertSucceeds(updateDoc(doc(as('admin'), 'groups/g1/members/m1'), { role: 'assistant' }));
  });
  test('المساعد ميرقّيش حد', async () => {
    await assertFails(updateDoc(doc(as('asst'), 'groups/g1/members/m1'), { role: 'assistant' }));
  });
  test('محدش يخلي نفسه أدمن', async () => {
    await assertFails(updateDoc(doc(as('asst'), 'groups/g1/members/asst'), { role: 'admin' }));
  });
  test('العضو يخرج من المجموعة', async () => {
    await assertSucceeds(deleteDoc(doc(as('m1'), 'groups/g1/members/m1')));
  });
  test('الأدمن ميخرجش من غير ما ينقل الأدمنية', async () => {
    await assertFails(deleteDoc(doc(as('admin'), 'groups/g1/members/admin')));
  });
  test('المساعد يطرد عضو عادي', async () => {
    await assertSucceeds(deleteDoc(doc(as('asst'), 'groups/g1/members/m1')));
  });
  test('المساعد ميطردش الأدمن', async () => {
    await assertFails(deleteDoc(doc(as('asst'), 'groups/g1/members/admin')));
  });
});

describe('الأوراد', () => {
  const path = 'groups/g1/cycles/c1/assignments/m1';
  test('صاحب الورد يسجل تقدمه', async () => {
    await assertSucceeds(updateDoc(doc(as('m1'), path), { quartersRead: 3, status: 'in_progress' }));
  });
  test('صاحب الورد يعلّم إنه خلص', async () => {
    await assertSucceeds(updateDoc(doc(as('m1'), path), {
      quartersRead: 8, status: 'done', completedAt: serverTimestamp(),
    }));
  });
  test('ميقدرش يقول خلصت قبل ما يقرا كل الأرباع', async () => {
    await assertFails(updateDoc(doc(as('m1'), path), {
      quartersRead: 5, status: 'done', completedAt: serverTimestamp(),
    }));
  });
  test('ميقدرش يغير حدود ورده', async () => {
    await assertFails(updateDoc(doc(as('m1'), path), { fromQuarter: 1 }));
  });
  test('محدش يسجل في ورد حد تاني', async () => {
    await assertFails(updateDoc(doc(as('asst'), path), { quartersRead: 8 }));
  });
  test('أعضاء المجموعة يشوفوا الأوراد', async () => {
    await assertSucceeds(getDoc(doc(as('asst'), path)));
  });
  test('غير الأعضاء ميشوفوش الأوراد', async () => {
    await assertFails(getDoc(doc(as('stranger'), path)));
  });
});

describe('الدعوات', () => {
  test('محدش يقرا أكواد الدعوات من التطبيق', async () => {
    await assertFails(getDoc(doc(as('admin'), 'invites/ABC123')));
  });
});
