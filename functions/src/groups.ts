// إنشاء المجموعات وإدارتها: الإعدادات، والأدوار، والخروج، والحذف.
import { getAuth } from 'firebase-admin/auth';
import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  db, groupData, groupRef, memberRef, requireManager, requireMember,
  requireString, requireUid, Role, userDisplay, userGroupIndexRef,
} from './common';
import { releaseMemberWork } from './cycles';
import { CYCLE_UNITS, LATE_POLICIES, parseNewGroup, ValidationError } from './validation';

/** حد أقصى لعدد المجموعات اللي المستخدم الواحد يقدر يعملها، ضد الإساءة. */
const MAX_GROUPS_CREATED_PER_USER = 20;

function asInvalid(e: unknown): never {
  if (e instanceof ValidationError) throw new HttpsError('invalid-argument', e.message);
  throw e;
}

export const createGroup = onCall(async (request) => {
  const uid = requireUid(request);
  let input;
  try {
    input = parseNewGroup(request.data);
  } catch (e) {
    asInvalid(e);
  }

  const created = await db.collection('groups').where('adminId', '==', uid).count().get();
  if (created.data().count >= MAX_GROUPS_CREATED_PER_USER) {
    throw new HttpsError('resource-exhausted', 'Too many groups created.');
  }

  const me = await userDisplay(uid);
  const ref = db.collection('groups').doc();
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(ref, {
    ...input,
    adminId: uid,
    memberCount: 1,
    hasFreeSlots: input.slots > 1,
    status: 'forming',
    currentCycle: 0,
    khatmasCompleted: 0,
    isOpen: true,
    createdAt: now,
  });
  batch.set(ref.collection('members').doc(uid), {
    role: 'admin', slot: 0, joinedAt: now, name: me.name, points: 0, readCount: 0,
    ...(me.photoUrl ? { photoUrl: me.photoUrl } : {}),
  });
  batch.set(userGroupIndexRef(uid, ref.id), {
    name: input.name, type: input.type, role: 'admin', wardQuarters: input.wardQuarters, joinedAt: now,
  });
  await batch.commit();
  return { groupId: ref.id };
});

/** تعديل إعدادات المجموعة (الأدمن والمساعد). الورد والنوع مبيتغيروش. */
export const updateGroupSettings = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  await requireManager(groupId, uid);
  const d = request.data ?? {};
  const update: Record<string, unknown> = {};

  if (d.name !== undefined) {
    const name = typeof d.name === 'string' ? d.name.trim() : '';
    if (name.length < 1 || name.length > 60) throw new HttpsError('invalid-argument', 'name must be 1 to 60 characters');
    update.name = name;
  }
  const ints: [string, number, number][] = [
    ['cycleCount', 1, 30], ['cycleStartDay', 0, 6], ['cycleStartHour', 0, 23],
    ['cycleStartDayOfMonth', 1, 28], ['utcOffsetMinutes', -720, 840],
  ];
  for (const [field, min, max] of ints) {
    if (d[field] === undefined) continue;
    const v = d[field];
    if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max) {
      throw new HttpsError('invalid-argument', `${field} out of range`);
    }
    update[field] = v;
  }
  if (d.cycleUnit !== undefined) {
    if (!(CYCLE_UNITS as readonly string[]).includes(d.cycleUnit)) throw new HttpsError('invalid-argument', 'cycleUnit');
    update.cycleUnit = d.cycleUnit;
  }
  if (d.lateDefault !== undefined) {
    if (!(LATE_POLICIES as readonly string[]).includes(d.lateDefault)) throw new HttpsError('invalid-argument', 'lateDefault');
    update.lateDefault = d.lateDefault;
  }
  if (d.isOpen !== undefined) {
    if (typeof d.isOpen !== 'boolean') throw new HttpsError('invalid-argument', 'isOpen');
    update.isOpen = d.isOpen;
  }
  if (Object.keys(update).length === 0) return { ok: true };

  await groupRef(groupId).update(update);
  if (update.name) {
    const members = await groupRef(groupId).collection('members').get();
    const writer = db.bulkWriter();
    members.forEach((m) => writer.set(userGroupIndexRef(m.id, groupId), { name: update.name }, { merge: true }));
    await writer.close();
  }
  return { ok: true };
});

async function removeFromGroup(groupId: string, uid: string): Promise<void> {
  await releaseMemberWork(groupId, uid);
  await db.runTransaction(async (tx) => {
    const gSnap = await tx.get(groupRef(groupId));
    const g = groupData(gSnap);
    tx.delete(memberRef(groupId, uid));
    tx.delete(userGroupIndexRef(uid, groupId));
    tx.update(groupRef(groupId), { memberCount: Math.max(0, g.memberCount - 1), hasFreeSlots: true });
  });
}

/** العضو يخرج بنفسه. الأدمن لازم ينقل الأدمنية أو يحذف المجموعة الأول. */
export const leaveGroup = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const me = await requireMember(groupId, uid);
  if (me.role === 'admin') throw new HttpsError('failed-precondition', 'Transfer admin or delete the group first.');
  await removeFromGroup(groupId, uid);
  return { ok: true };
});

/** الأدمن أو المساعد يشيل عضو عادي، والأدمن بس يشيل مساعد. */
export const removeMember = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const target = requireString(request.data?.uid, 'uid');
  const me = await requireManager(groupId, uid);
  if (target === uid) throw new HttpsError('invalid-argument', 'Use leaveGroup.');
  const them = await requireMember(groupId, target);
  const allowed = them.role === 'member' || (them.role === 'assistant' && me.role === 'admin');
  if (!allowed) throw new HttpsError('permission-denied', 'Not allowed.');
  await removeFromGroup(groupId, target);
  return { ok: true };
});

/** الأدمن يرقّي عضو لمساعد أو يرجّعه عضو. */
export const setRole = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const target = requireString(request.data?.uid, 'uid');
  const role = request.data?.role as Role;
  if (role !== 'assistant' && role !== 'member') throw new HttpsError('invalid-argument', 'role');
  const me = await requireMember(groupId, uid);
  if (me.role !== 'admin') throw new HttpsError('permission-denied', 'Admin only.');
  const them = await requireMember(groupId, target);
  if (them.role === 'admin') throw new HttpsError('failed-precondition', 'Cannot change the admin.');
  const batch = db.batch();
  batch.update(memberRef(groupId, target), { role });
  batch.set(userGroupIndexRef(target, groupId), { role }, { merge: true });
  await batch.commit();
  return { ok: true };
});

/** الأدمن ينقل الأدمنية لعضو تاني، وهو بيبقى مساعد. */
export const transferAdmin = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const target = requireString(request.data?.uid, 'uid');
  const me = await requireMember(groupId, uid);
  if (me.role !== 'admin') throw new HttpsError('permission-denied', 'Admin only.');
  await requireMember(groupId, target);
  if (target === uid) return { ok: true };
  const batch = db.batch();
  batch.update(memberRef(groupId, target), { role: 'admin' });
  batch.update(memberRef(groupId, uid), { role: 'assistant' });
  batch.set(userGroupIndexRef(target, groupId), { role: 'admin' }, { merge: true });
  batch.set(userGroupIndexRef(uid, groupId), { role: 'assistant' }, { merge: true });
  batch.update(groupRef(groupId), { adminId: target });
  await batch.commit();
  return { ok: true };
});

/** الأدمن يحذف المجموعة بكل بياناتها. */
export const deleteGroup = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const me = await requireMember(groupId, uid);
  if (me.role !== 'admin') throw new HttpsError('permission-denied', 'Admin only.');
  await deleteGroupData(groupId);
  return { ok: true };
});


async function deleteGroupData(groupId: string): Promise<void> {
  const members = await groupRef(groupId).collection('members').get();
  const invites = await db.collection('invites').where('groupId', '==', groupId).get();
  const writer = db.bulkWriter();
  members.forEach((m) => writer.delete(userGroupIndexRef(m.id, groupId)));
  invites.forEach((i) => writer.delete(i.ref));
  await writer.close();
  await db.recursiveDelete(groupRef(groupId));
}

/**
 * حذف الحساب (مطلوب من Apple وGoogle): بيخرج المستخدم من كل مجموعاته،
 * ولو هو أدمن بينقل الأدمنية لمساعد أو لأكتر عضو نقاطًا، ولو لوحده بيحذف المجموعة.
 * وبعدها بيمسح ملفه وحسابه.
 */
export const deleteAccount = onCall(async (request) => {
  const uid = requireUid(request);
  const index = await db.collection('users').doc(uid).collection('groups').get();
  for (const entry of index.docs) {
    const groupId = entry.id;
    const meSnap = await memberRef(groupId, uid).get();
    if (!meSnap.exists) continue;
    if (meSnap.get('role') === 'admin') {
      const others = (await groupRef(groupId).collection('members').get()).docs.filter((d) => d.id !== uid);
      if (others.length === 0) {
        await deleteGroupData(groupId);
        continue;
      }
      const next = others.find((d) => d.get('role') === 'assistant')
        ?? others.sort((a, b) => (b.get('points') ?? 0) - (a.get('points') ?? 0))[0];
      const batch = db.batch();
      batch.update(memberRef(groupId, next.id), { role: 'admin' });
      batch.set(userGroupIndexRef(next.id, groupId), { role: 'admin' }, { merge: true });
      batch.update(groupRef(groupId), { adminId: next.id });
      await batch.commit();
    }
    await removeFromGroup(groupId, uid);
  }
  await db.recursiveDelete(db.collection('users').doc(uid));
  await getAuth().deleteUser(uid);
  return { ok: true };
});
