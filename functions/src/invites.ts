// روابط الدعوة والانضمام للمجموعات.
import { randomInt } from 'node:crypto';

import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  db, groupData, GroupDoc, groupRef, MemberDoc, memberRef, requireManager, requireString, requireUid,
  userDisplay, userGroupIndexRef,
} from './common';
import { adoptEmptySegment } from './cycles';
import { notifyUsers } from './notify';
import { pickCycle, segmentFor, segmentRange, slotForSegment, takenSegments } from './rotation';
import { parseSegment, ValidationError } from './validation';

/** دومين التطبيق: الرابط بيفتح التطبيق مباشرة، أو صفحة تشرح وتوديك للمتجر. */
export const INVITE_BASE_URL = 'https://taawanu.app/j/';

// من غير حروف ممكن تتلخبط (0/O، 1/I/L).
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function newCode(): string {
  let s = '';
  for (let i = 0; i < 8; i++) s += ALPHABET[randomInt(ALPHABET.length)];
  return s;
}

/** كود الدعوة من الكود نفسه أو من الرابط كله. */
function normalizeCode(raw: unknown): string {
  const s = requireString(raw, 'code', 300).trim();
  const last = s.split('/').filter(Boolean).pop() ?? '';
  const code = last.toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (code.length !== 8) throw new HttpsError('invalid-argument', 'Invalid invite code.');
  return code;
}

export const createInvite = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  await requireManager(groupId, uid);
  const days = request.data?.days ?? 7;
  if (![1, 7, 30].includes(days)) throw new HttpsError('invalid-argument', 'days must be 1, 7 or 30');
  const maxUses = request.data?.maxUses ?? null;
  if (maxUses !== null && ![1, 5].includes(maxUses)) throw new HttpsError('invalid-argument', 'maxUses must be 1, 5 or null');

  // نتأكد إن الكود مش متكرر (احتمال ضعيف جدًا، بس بنتأكد).
  let code = newCode();
  for (let i = 0; i < 5 && (await db.collection('invites').doc(code).get()).exists; i++) code = newCode();

  await db.collection('invites').doc(code).set({
    groupId,
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + days * 24 * 60 * 60 * 1000),
    usesLeft: maxUses,
    revoked: false,
  });
  return { code, url: INVITE_BASE_URL + code };
});

export const revokeInvite = onCall(async (request) => {
  const uid = requireUid(request);
  const code = normalizeCode(request.data?.code);
  const ref = db.collection('invites').doc(code);
  const snap = await ref.get();
  if (!snap.exists) return { ok: true };
  await requireManager(snap.get('groupId'), uid);
  await ref.update({ revoked: true });
  return { ok: true };
});

interface InviteDoc {
  groupId: string;
  expiresAt: Timestamp;
  usesLeft: number | null;
  revoked: boolean;
}

function checkInvite(inv: InviteDoc | undefined): InviteDoc {
  if (!inv || inv.revoked) throw new HttpsError('not-found', 'Invite not found.');
  if (inv.expiresAt.toMillis() < Date.now()) throw new HttpsError('deadline-exceeded', 'Invite expired.');
  if (inv.usesLeft !== null && inv.usesLeft <= 0) throw new HttpsError('resource-exhausted', 'Invite used up.');
  return inv;
}

async function groupSummary(groupId: string, g: GroupDoc, forUid: string) {
  const admin = await userDisplay(g.adminId);
  const alreadyMember = (await memberRef(groupId, forUid).get()).exists;
  // الأجزاء المحجوزة، عشان العضو الجديد يختار من الفاضي.
  const pick = pickCycle(g.status, g.currentCycle, false);
  const slots = (await groupRef(groupId).collection('members').select('slot').get()).docs.map((d) => d.get('slot') as number);
  return {
    groupId,
    name: g.name,
    type: g.type,
    wardQuarters: g.wardQuarters,
    slots: g.slots,
    memberCount: g.memberCount,
    cycleCount: g.cycleCount,
    cycleUnit: g.cycleUnit,
    cycleStartDay: g.cycleStartDay,
    status: g.status,
    currentCycle: g.currentCycle,
    adminName: admin.name,
    alreadyMember,
    pickCycle: pick,
    takenSegments: takenSegments(slots, pick, g.slots),
  };
}

/** تفاصيل المجموعة قبل الانضمام (لشاشة "انضم"). */
export const previewInvite = onCall(async (request) => {
  const uid = requireUid(request);
  const code = normalizeCode(request.data?.code);
  const inv = checkInvite((await db.collection('invites').doc(code).get()).data() as InviteDoc | undefined);
  const g = groupData(await groupRef(inv.groupId).get());
  return { code, ...(await groupSummary(inv.groupId, g, uid)) };
});

export const previewPublicGroup = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const g = groupData(await groupRef(groupId).get());
  if (g.type !== 'public') throw new HttpsError('permission-denied', 'Private group.');
  return await groupSummary(groupId, g, uid);
});

function readSegment(raw: unknown, slots: number): number | null {
  try {
    return parseSegment(raw, slots);
  } catch (e) {
    if (e instanceof ValidationError) throw new HttpsError('invalid-argument', e.message);
    throw e;
  }
}

/**
 * بيضيف المستخدم في الجزء اللي اختاره، أو في أول خانة فاضية لو ماختارش.
 * بيرجّع رقم الخانة.
 */
async function addMember(groupId: string, uid: string, inviteCode: string | null, rawSegment: unknown): Promise<number> {
  const me = await userDisplay(uid);
  const gRef = groupRef(groupId);
  const slot = await db.runTransaction(async (tx) => {
    const gSnap = await tx.get(gRef);
    const g = groupData(gSnap);
    const mSnap = await tx.get(memberRef(groupId, uid));
    if (mSnap.exists) return (mSnap.data() as MemberDoc).slot;
    if (!g.isOpen) throw new HttpsError('failed-precondition', 'Group is closed.');
    if (g.memberCount >= g.slots) throw new HttpsError('resource-exhausted', 'Group is full.');

    if (inviteCode) {
      const iRef = db.collection('invites').doc(inviteCode);
      const inv = checkInvite((await tx.get(iRef)).data() as InviteDoc | undefined);
      if (inv.groupId !== groupId) throw new HttpsError('invalid-argument', 'Invite mismatch.');
      if (inv.usesLeft !== null) tx.update(iRef, { usesLeft: inv.usesLeft - 1 });
    }

    const members = await tx.get(gRef.collection('members'));
    const taken = new Set(members.docs.map((d) => (d.data() as MemberDoc).slot));
    const segment = readSegment(rawSegment, g.slots);
    let free: number;
    if (segment !== null) {
      free = slotForSegment(segment, pickCycle(g.status, g.currentCycle, false), g.slots);
      if (taken.has(free)) throw new HttpsError('already-exists', 'Segment taken.');
    } else {
      free = 0;
      while (taken.has(free)) free++;
    }

    const now = FieldValue.serverTimestamp();
    tx.set(memberRef(groupId, uid), {
      role: 'member', slot: free, joinedAt: now, name: me.name, points: 0, readCount: 0,
      ...(me.photoUrl ? { photoUrl: me.photoUrl } : {}),
    });
    tx.set(userGroupIndexRef(uid, groupId), {
      name: g.name, type: g.type, role: 'member', wardQuarters: g.wardQuarters, joinedAt: now,
    });
    tx.update(gRef, { memberCount: g.memberCount + 1, hasFreeSlots: g.memberCount + 1 < g.slots });
    return free;
  });

  await adoptEmptySegment(groupId, uid);

  const g = groupData(await gRef.get());
  const managers = await gRef.collection('members').where('role', 'in', ['admin', 'assistant']).get();
  await notifyUsers(managers.docs.map((d) => d.id).filter((id) => id !== uid), () => ({
    ar: { title: g.name, body: `${me.name} انضم للمجموعة.` },
    en: { title: g.name, body: `${me.name} joined the group.` },
  }), { groupId, type: 'joined' });
  return slot;
}

export const joinGroup = onCall(async (request) => {
  const uid = requireUid(request);
  const code = normalizeCode(request.data?.code);
  const inv = checkInvite((await db.collection('invites').doc(code).get()).data() as InviteDoc | undefined);
  const slot = await addMember(inv.groupId, uid, code, request.data?.segment);
  return { groupId: inv.groupId, slot };
});

export const joinPublicGroup = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const g = groupData(await groupRef(groupId).get());
  if (g.type !== 'public') throw new HttpsError('permission-denied', 'Private group: invite required.');
  const slot = await addMember(groupId, uid, null, request.data?.segment);
  return { groupId, slot };
});

/** القطعة اللي العضو الجديد هيبدأ بيها (للعرض بس). */
export function startingRange(g: GroupDoc, slot: number) {
  const cycle = g.status === 'active' ? g.currentCycle + 1 : 1;
  return segmentRange(segmentFor(slot, cycle, g.slots), g.wardQuarters);
}
