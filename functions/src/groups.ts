// إنشاء المجموعات وإدارتها: الإعدادات، والأدوار، والخروج، والحذف.
import { getAuth } from 'firebase-admin/auth';
import { DocumentSnapshot, FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  assignmentRef, cycleRef, db, groupData, groupRef, memberRef, requireManager, requireMember,
  requireString, requireUid, Role, userDisplay, userGroupIndexRef,
} from './common';
import { releaseMemberWork } from './cycles';
import { segmentFor, slotForSegment } from './rotation';
import { CYCLE_UNITS, LATE_POLICIES, parseNewGroup, parseSegment, ValidationError } from './validation';

/** حد أقصى لعدد المجموعات اللي المستخدم الواحد يقدر يعملها، ضد الإساءة. */
const MAX_GROUPS_CREATED_PER_USER = 20;

function asInvalid(e: unknown): never {
  if (e instanceof ValidationError) throw new HttpsError('invalid-argument', e.message);
  throw e;
}

export const createGroup = onCall(async (request) => {
  const uid = requireUid(request);
  let input;
  let startSegment = 0;
  try {
    input = parseNewGroup(request.data);
    // الأدمن بيختار الجزء اللي هيبدأ بيه (مثلًا لو جاي من ختمة شغالة على الواتساب).
    startSegment = parseSegment(request.data?.startSegment, input.slots) ?? 0;
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
    role: 'admin', slot: slotForSegment(startSegment, 1, input.slots), joinedAt: now, name: me.name, points: 0, readCount: 0,
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

/**
 * الأدمن أو المساعد بيغيّر الجزء بتاع عضو. لو الجزء مع عضو تاني بيتبادلوا.
 * قبل البداية: من الدورة الأولى. بعد البداية: من الدورة الجاية.
 */
export const moveMember = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const target = requireString(request.data?.uid, 'uid');
  await requireManager(groupId, uid);
  const gRef = groupRef(groupId);
  const result = await db.runTransaction(async (tx) => {
    const g = groupData(await tx.get(gRef));
    let segment: number;
    try {
      segment = parseSegment(request.data?.segment, g.slots) ?? -1;
    } catch (e) {
      asInvalid(e);
    }
    if (segment < 0) throw new HttpsError('invalid-argument', 'segment is required');
    const active = g.status === 'active';
    // الرقم اللي الأدمن بيختاره = ورد العضو في الدورة الحالية (أو الأولى لو لسه مبدأتش).
    const n = active ? g.currentCycle : 1;
    const newSlot = slotForSegment(segment, n, g.slots);
    const members = await tx.get(gRef.collection('members'));
    const mine = members.docs.find((d) => d.id === target);
    if (!mine) throw new HttpsError('not-found', 'Not a member.');
    const oldSlot = mine.get('slot') as number;
    if (oldSlot === newSlot) return { applied: 'none' as const };
    const other = members.docs.find((d) => d.get('slot') === newSlot);
    const oldSeg = segmentFor(oldSlot, n, g.slots);

    if (!active) {
      tx.update(mine.ref, { slot: newSlot });
      if (other) tx.update(other.ref, { slot: oldSlot });
      return { applied: 'now' as const };
    }

    // بعد البداية: لو محدش من الاتنين بدأ يقرا، التغيير بيتطبّق على طول في الدورة دي.
    const cRef = cycleRef(groupId, n);
    const myRef = assignmentRef(groupId, n, target);
    const otherRef = other ? assignmentRef(groupId, n, other.id) : null;
    const emptyQuery = groupRef(groupId).collection('portions')
      .where('cycle', '==', n).where('origin', '==', 'empty')
      .where('fromQuarter', '==', segment * g.wardQuarters + 1).limit(1);
    const [cSnap, mySnap, otherSnap, emptySnap] = await Promise.all([
      tx.get(cRef), tx.get(myRef), otherRef ? tx.get(otherRef) : Promise.resolve(null), tx.get(emptyQuery),
    ]);
    const notStarted = (d: DocumentSnapshot | null) => {
      if (!d || !d.exists) return true;
      const x = d.data()!;
      return !x.closed && x.status === 'pending' && (x.quartersRead ?? 0) === 0;
    };
    const emptyDoc = emptySnap.docs[0];
    const emptyFree = !other && (!emptyDoc || (emptyDoc.get('status') === 'open' && (emptyDoc.get('quartersRead') ?? 0) === 0));
    // لازم العضو يكون ليه ورد في الدورة دي عشان نبدّله على طول.
    const canNow = cSnap.exists && mySnap.exists && notStarted(mySnap) && (other ? notStarted(otherSnap) : emptyFree);

    tx.update(mine.ref, { slot: newSlot, nowSegment: canNow ? FieldValue.delete() : { cycle: n, seg: oldSeg } });
    if (other) {
      tx.update(other.ref, { slot: oldSlot, nowSegment: canNow ? FieldValue.delete() : { cycle: n, seg: segment } });
    }
    if (!canNow) return { applied: 'next' as const, nextSegment: segmentFor(newSlot, n + 1, g.slots) };

    const range = (seg: number) => ({ fromQuarter: seg * g.wardQuarters + 1, toQuarter: (seg + 1) * g.wardQuarters });
    const fresh = (seg: number) => ({
      ...range(seg), segment: seg, quarterCount: g.wardQuarters, quartersRead: 0, status: 'pending', closed: false,
    });
    const c = cSnap.data()!;
    const segs = (c.segments as { seg: number; uid: string | null; status: string }[]).map((s) => ({ ...s }));
    const setSeg = (seg: number, owner: string | null) => {
      const s = segs.find((x) => x.seg === seg);
      if (s) {
        s.uid = owner;
        s.status = owner ? 'pending' : 'open';
      }
    };
    tx.set(myRef, fresh(segment));
    setSeg(segment, target);
    if (other && otherRef) {
      tx.set(otherRef, fresh(oldSeg));
      setSeg(oldSeg, other.id);
    } else {
      // الخانة الجديدة كانت فاضية: العضو ياخدها، وخانته القديمة تبقى متاحة للتطوع.
      if (emptyDoc) tx.delete(emptyDoc.ref);
      setSeg(oldSeg, null);
      tx.set(groupRef(groupId).collection('portions').doc(), {
        ...range(oldSeg), cycle: n, quarterCount: g.wardQuarters, assignee: null, status: 'open', origin: 'empty',
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    tx.update(cRef, { segments: segs });
    return { applied: 'now' as const };
  });
  return { ok: true, ...result };
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
