// بدء الختمة، والدورات، وتسجيل التقدم، والأوراد المتأخرة (portions)، والنقاط.
import { FieldValue, Timestamp, Transaction } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import {
  assignmentRef, cycleRef, db, groupData, GroupDoc, groupRef, MemberDoc, memberRef,
  requireManager, requireMember, requireString, requireUid, Segment,
} from './common';
import { notifyUsers } from './notify';
import {
  BADGES, KHATMA_BONUS, PERSONAL_KHATMA_BONUS, POINTS_PER_QUARTER, regularPoints, RESCUE_POINTS_PER_QUARTER,
} from './points';
import {
  QuarterRange, quarterCount, rangeLabel, segmentFor, segmentRange, slotForSegment, splitRange, TOTAL_QUARTERS,
} from './rotation';
import { CycleSettings, firstCycleEnd, lastCallTime, midpoint, nextCycleEnd } from './schedule';

type PortionOrigin = 'empty' | 'carry' | 'distribute' | 'volunteer' | 'ask' | 'left';

interface PortionDoc extends QuarterRange {
  cycle: number;
  quarterCount: number;
  assignee: string | null;
  status: 'open' | 'assigned' | 'done';
  origin: PortionOrigin;
  originalUid?: string;
}

interface AssignmentDoc extends QuarterRange {
  segment: number;
  quarterCount: number;
  quartersRead: number;
  status: 'pending' | 'in_progress' | 'done' | 'late';
  closed: boolean;
  completedAt?: Timestamp;
  /** لو الأدمن أو المساعد هو اللي سجّل: من غير نقاط، ومش بيتحسب في الالتزام. */
  recordedBy?: string | null;
}

interface CycleDoc {
  number: number;
  startedAt: Timestamp;
  endsAt: Timestamp;
  midAt: Timestamp;
  segments: Segment[];
  remainingQuarters: number;
  khatmaComplete: boolean;
  firstFinisher?: string | null;
}

function settingsOf(g: GroupDoc): CycleSettings {
  return {
    cycleCount: g.cycleCount, cycleUnit: g.cycleUnit, cycleStartDay: g.cycleStartDay,
    cycleStartHour: g.cycleStartHour, cycleStartDayOfMonth: g.cycleStartDayOfMonth,
    utcOffsetMinutes: g.utcOffsetMinutes,
  };
}

function portionsCol(groupId: string) {
  return groupRef(groupId).collection('portions');
}

// ---------------------------------------------------------------------------
// فتح دورة جديدة

async function openCycle(groupId: string, g: GroupDoc, cycleNo: number, start: Date, end: Date): Promise<void> {
  const membersSnap = await groupRef(groupId).collection('members').get();
  const bySlot = new Map<number, string>();
  membersSnap.forEach((m) => bySlot.set((m.data() as MemberDoc).slot, m.id));

  const segments: Segment[] = [];
  const writer = db.bulkWriter();
  for (let seg = 0; seg < g.slots; seg++) {
    const uid = bySlot.get(slotForSegment(seg, cycleNo, g.slots)) ?? null;
    const range = segmentRange(seg, g.wardQuarters);
    segments.push({ seg, uid, status: uid ? 'pending' : 'open' });
    if (uid) {
      const a: AssignmentDoc = {
        ...range, segment: seg, quarterCount: g.wardQuarters, quartersRead: 0, status: 'pending', closed: false,
      };
      writer.set(assignmentRef(groupId, cycleNo, uid), a);
    } else {
      // خانة فاضية: الورد بتاعها متاح لأي متطوع.
      const p: PortionDoc = { ...range, cycle: cycleNo, quarterCount: g.wardQuarters, assignee: null, status: 'open', origin: 'empty' };
      writer.set(portionsCol(groupId).doc(), { ...p, createdAt: FieldValue.serverTimestamp() });
    }
  }
  const mid = midpoint(start, end);
  writer.set(cycleRef(groupId, cycleNo), {
    number: cycleNo,
    startedAt: Timestamp.fromDate(start),
    endsAt: Timestamp.fromDate(end),
    midAt: Timestamp.fromDate(mid),
    segments,
    remainingQuarters: TOTAL_QUARTERS,
    khatmaComplete: false,
    firstFinisher: null,
  });
  writer.update(groupRef(groupId), {
    status: 'active',
    currentCycle: cycleNo,
    cycleStartedAt: Timestamp.fromDate(start),
    nextCycleAt: Timestamp.fromDate(end),
    // أول تذكير: نص الدورة.
    nextReminderAt: Timestamp.fromDate(mid),
    reminderStage: 'mid',
  });
  await writer.close();

  // إشعار بداية الدورة لكل عضو بورده.
  const wardByUid = new Map<string, QuarterRange>();
  for (const s of segments) if (s.uid) wardByUid.set(s.uid, segmentRange(s.seg, g.wardQuarters));
  await notifyUsers([...wardByUid.keys()], (uid) => {
    const r = wardByUid.get(uid)!;
    return {
      ar: { title: g.name, body: `دورة جديدة بدأت. وردك: ${rangeLabel(r, 'ar')}` },
      en: { title: g.name, body: `A new cycle started. Your portion: ${rangeLabel(r, 'en')}` },
    };
  }, { groupId, type: 'cycle_start' });
}

/** الأدمن أو المساعد بيبدأ الختمة. */
export const startKhatma = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  await requireManager(groupId, uid);
  const g = groupData(await groupRef(groupId).get());
  if (g.status !== 'forming') throw new HttpsError('failed-precondition', 'Khatma already started.');
  const now = new Date();
  await openCycle(groupId, g, 1, now, firstCycleEnd(now, settingsOf(g)));
  return { ok: true };
});

// ---------------------------------------------------------------------------
// إغلاق الدورة والانتقال للي بعدها (بالجدولة)

async function closeCycle(groupId: string, g: GroupDoc): Promise<void> {
  const n = g.currentCycle;
  const cRef = cycleRef(groupId, n);
  const cycleSnap = await cRef.get();
  if (!cycleSnap.exists) return;
  const cycle = cycleSnap.data() as CycleDoc;
  const endsAt = cycle.endsAt.toDate();

  const assignments = await cRef.collection('assignments').get();
  const finishers: string[] = [];
  const late: { uid: string; a: AssignmentDoc }[] = [];
  assignments.forEach((d) => {
    const a = d.data() as AssignmentDoc;
    if (a.status === 'done') finishers.push(d.id);
    else if (!a.closed) late.push({ uid: d.id, a });
  });

  const writer = db.bulkWriter();
  let readFromLate = 0;
  const segments = cycle.segments.map((s) => ({ ...s }));

  for (const { uid, a } of late) {
    readFromLate += a.quartersRead;
    writer.update(assignmentRef(groupId, n, uid), { closed: true, status: 'late' });
    const seg = segments.find((s) => s.seg === a.segment);
    if (seg) seg.status = 'late';
    const rest: QuarterRange = { fromQuarter: a.fromQuarter + a.quartersRead, toQuarter: a.toQuarter };
    if (rest.fromQuarter > rest.toQuarter) continue;

    const base = { cycle: n, originalUid: uid };
    if (g.lateDefault === 'carry') {
      writer.set(portionsCol(groupId).doc(), {
        ...rest, ...base, quarterCount: quarterCount(rest), assignee: uid, status: 'assigned', origin: 'carry',
        createdAt: FieldValue.serverTimestamp(),
      });
    } else if (g.lateDefault === 'distribute' && finishers.length > 0) {
      const pieces = splitRange(rest, finishers.length);
      pieces.forEach((piece, i) => writer.set(portionsCol(groupId).doc(), {
        ...piece, ...base, quarterCount: quarterCount(piece), assignee: finishers[i], status: 'assigned', origin: 'distribute',
        createdAt: FieldValue.serverTimestamp(),
      }));
    } else {
      // volunteer أو ask (الأدمن يقدر يحدد حد) أو توزيع ومفيش حد خلص.
      writer.set(portionsCol(groupId).doc(), {
        ...rest, ...base, quarterCount: quarterCount(rest), assignee: null, status: 'open',
        origin: g.lateDefault === 'ask' ? 'ask' : 'volunteer', createdAt: FieldValue.serverTimestamp(),
      });
    }
  }

  writer.update(cRef, {
    segments,
    remainingQuarters: FieldValue.increment(-readFromLate),
  });

  // السلسلة والالتزام لكل عضو كان عليه ورد في الدورة دي.
  const onTime = new Set(
    assignments.docs
      .filter((d) => {
        const a = d.data() as AssignmentDoc;
        return a.status === 'done' && !a.recordedBy && a.completedAt && a.completedAt.toDate() <= endsAt;
      })
      .map((d) => d.id),
  );
  const uids = assignments.docs.map((d) => d.id);
  if (uids.length) {
    const users = await db.getAll(...uids.map((u) => db.collection('users').doc(u)));
    for (const u of users) {
      const d = u.data() ?? {};
      const ok = onTime.has(u.id);
      const streak = ok ? (Number(d.streak) || 0) + 1 : 0;
      const update: Record<string, unknown> = {
        streak,
        longestStreak: Math.max(streak, Number(d.longestStreak) || 0),
        totalCycles: FieldValue.increment(1),
      };
      if (ok) update.onTimeCycles = FieldValue.increment(1);
      const badges: string[] = [];
      if (streak >= 4) badges.push(BADGES.streak4);
      if (streak >= 12) badges.push(BADGES.streak12);
      if (badges.length) update.badges = FieldValue.arrayUnion(...badges);
      writer.set(u.ref, update, { merge: true });
    }
  }
  await writer.close();

  // لو القراءة الجزئية كمّلت الختمة (نادر)، اتأكد.
  await maybeCompleteKhatma(groupId, n);

  // الدورة الجديدة بالإعدادات الحالية (لو الأدمن غيّر المدة، بتتطبق من هنا).
  const fresh = groupData(await groupRef(groupId).get());
  await openCycle(groupId, fresh, n + 1, endsAt, nextCycleEnd(endsAt, settingsOf(fresh)));

  if (late.length && (g.lateDefault === 'ask' || g.lateDefault === 'volunteer')) {
    const managers = await groupRef(groupId).collection('members').where('role', 'in', ['admin', 'assistant']).get();
    await notifyUsers(managers.docs.map((d) => d.id), () => ({
      ar: { title: g.name, body: `فيه ${late.length} ورد متأخر من الدورة اللي فاتت ومتاح للتطوع.` },
      en: { title: g.name, body: `${late.length} unfinished portion(s) from last cycle are open for volunteers.` },
    }), { groupId, type: 'late' });
  }
}

/** تذكير اللي لسه مخلصش (نص الدورة، وقبل النهاية). */
async function sendReminder(groupId: string, g: GroupDoc, stage: string): Promise<void> {
  const cRef = cycleRef(groupId, g.currentCycle);
  const cycleSnap = await cRef.get();
  if (!cycleSnap.exists) return;
  const cycle = cycleSnap.data() as CycleDoc;
  const pending = await cRef.collection('assignments').where('status', 'in', ['pending', 'in_progress']).get();
  const targets = pending.docs
    .filter((d) => (stage === 'mid' ? (d.data() as AssignmentDoc).status === 'pending' : true))
    .map((d) => d.id);
  await notifyUsers(targets, () => (stage === 'mid'
    ? { ar: { title: g.name, body: 'نص الدورة عدى، وردك لسه مستنيك.' }, en: { title: g.name, body: "Halfway through the cycle — your portion is waiting." } }
    : { ar: { title: g.name, body: 'الدورة قربت تخلص، كمّل وردك.' }, en: { title: g.name, body: 'The cycle ends soon — finish your portion.' } }),
  { groupId, type: 'reminder' });

  const next = stage === 'mid'
    ? { nextReminderAt: Timestamp.fromDate(lastCallTime(cycle.startedAt.toDate(), cycle.endsAt.toDate())), reminderStage: 'last' }
    : { nextReminderAt: null, reminderStage: 'none' };
  await groupRef(groupId).update(next);
}

/** كل ١٥ دقيقة: بيقفل الدورات اللي خلصت وبيبعت التذكيرات. */
export const cycleTick = onSchedule({ schedule: 'every 15 minutes', timeZone: 'UTC' }, async () => {
  const now = Timestamp.now();
  const due = await db.collection('groups').where('status', '==', 'active').where('nextCycleAt', '<=', now).limit(50).get();
  for (const d of due.docs) {
    try {
      await closeCycle(d.id, d.data() as GroupDoc);
    } catch (e) {
      logger.error('closeCycle failed', d.id, e);
    }
  }
  const reminders = await db.collection('groups').where('status', '==', 'active').where('nextReminderAt', '<=', now).limit(100).get();
  for (const d of reminders.docs) {
    const g = d.data() as GroupDoc & { reminderStage?: string; nextCycleAt?: Timestamp };
    if (g.nextCycleAt && g.nextCycleAt.toMillis() <= now.toMillis()) continue; // اتقفلت فوق
    try {
      await sendReminder(d.id, g, g.reminderStage ?? 'mid');
    } catch (e) {
      logger.error('sendReminder failed', d.id, e);
    }
  }
});

// ---------------------------------------------------------------------------
// اكتمال الختمة

async function maybeCompleteKhatma(groupId: string, cycleNo: number): Promise<void> {
  const cRef = cycleRef(groupId, cycleNo);
  const completed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(cRef);
    const c = snap.data() as CycleDoc | undefined;
    if (!c || c.khatmaComplete || c.remainingQuarters > 0) return false;
    tx.update(cRef, { khatmaComplete: true, completedAt: FieldValue.serverTimestamp() });
    tx.update(groupRef(groupId), { khatmasCompleted: FieldValue.increment(1) });
    tx.set(groupRef(groupId).collection('khatmas').doc(String(cycleNo)), {
      cycle: cycleNo, completedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!completed) return;

  const g = groupData(await groupRef(groupId).get());
  const members = await groupRef(groupId).collection('members').get();
  const writer = db.bulkWriter();
  for (const m of members.docs) {
    writer.update(m.ref, { points: FieldValue.increment(KHATMA_BONUS) });
    writer.set(db.collection('users').doc(m.id), {
      points: FieldValue.increment(KHATMA_BONUS),
      khatmasGroup: FieldValue.increment(1),
      badges: FieldValue.arrayUnion(BADGES.firstKhatma),
    }, { merge: true });
  }
  await writer.close();
  await notifyUsers(members.docs.map((m) => m.id), () => ({
    ar: { title: g.name, body: 'الحمد لله، الختمة اكتملت. تقبل الله منكم.' },
    en: { title: g.name, body: 'Alhamdulillah, the khatma is complete. May Allah accept it from you.' },
  }), { groupId, type: 'khatma' });
}

// ---------------------------------------------------------------------------
// تسجيل التقدم: الورد العادي والأوراد الإضافية، من العضو نفسه أو من الأدمن/المساعد.
// - العضو بياخد نقاطه لما يخلّص بنفسه، ولو تراجع النقاط دي بتتشال بنفس الرقم.
// - تسجيل الأدمن/المساعد لورد حد تاني: من غير نقاط، ومش بيتحسب في الالتزام.
// - بعد ما الختمة تكتمل مفيش تراجع (مكافأة الختمة اتوزعت خلاص).

export interface Actor {
  uid: string;
  manager: boolean;
}

type Awarded = { pointsAwarded?: number; personalAwarded?: boolean };

/** نقاط ورد عادي قديم اتسجّل قبل ما نحفظ النقاط الممنوحة. */
function legacyRegularPoints(a: AssignmentDoc, c: CycleDoc): number {
  const at = a.completedAt?.toDate();
  if (!at) return regularPoints(a.quarterCount, false, false);
  const onTime = at <= c.endsAt.toDate();
  const early = at <= c.midAt.toDate();
  return regularPoints(a.quarterCount, onTime, early);
}

type AssignmentOutcome =
  | { kind: 'none' | 'partial' | 'doneByManager' }
  | { kind: 'doneSelf'; points: number; bonus: number; first: boolean; personal: boolean }
  | { kind: 'undone'; refund: number; personal: boolean; selfCounted: boolean };

export async function applyAssignmentProgress(groupId: string, target: string, quartersRead: number, actor: Actor) {
  const g = groupData(await groupRef(groupId).get());
  if (g.status !== 'active') throw new HttpsError('failed-precondition', 'Khatma not started.');
  const member = await requireMember(groupId, target);
  const n = g.currentCycle;
  const aRef = assignmentRef(groupId, n, target);
  const cRef = cycleRef(groupId, n);
  const byManager = actor.manager && actor.uid !== target;

  const out = await db.runTransaction(async (tx: Transaction): Promise<AssignmentOutcome> => {
    const [aSnap, cSnap] = await Promise.all([tx.get(aRef), tx.get(cRef)]);
    if (!aSnap.exists) throw new HttpsError('not-found', 'No portion this cycle.');
    const a = aSnap.data() as AssignmentDoc & Awarded;
    const c = cSnap.data() as CycleDoc;
    if (a.closed) throw new HttpsError('failed-precondition', 'Portion already closed.');
    if (quartersRead > a.quarterCount) throw new HttpsError('invalid-argument', 'Too many quarters.');
    const wasDone = a.status === 'done';
    const done = quartersRead === a.quarterCount;
    if (wasDone && done) return { kind: 'none' };
    if (wasDone && c.khatmaComplete) throw new HttpsError('failed-precondition', 'Khatma already complete.');

    const status = done ? 'done' : quartersRead > 0 ? 'in_progress' : 'pending';
    const segments = c.segments.map((s) => (s.seg === a.segment ? { ...s, status } : s));

    if (done) {
      if (byManager) {
        tx.update(aRef, {
          quartersRead, status, recordedBy: actor.uid, completedAt: FieldValue.serverTimestamp(),
          pointsAwarded: 0, personalAwarded: false,
        });
        tx.update(cRef, { segments, remainingQuarters: FieldValue.increment(-a.quarterCount) });
        return { kind: 'doneByManager' };
      }
      const now = new Date();
      const points = regularPoints(a.quarterCount, now <= c.endsAt.toDate(), now <= c.midAt.toDate());
      const personal = ((member.readCount ?? 0) + 1) % g.slots === 0;
      const bonus = personal ? PERSONAL_KHATMA_BONUS : 0;
      const first = !c.firstFinisher;
      tx.update(aRef, {
        quartersRead, status, recordedBy: null, completedAt: FieldValue.serverTimestamp(),
        pointsAwarded: points + bonus, personalAwarded: personal,
      });
      tx.update(cRef, {
        segments,
        remainingQuarters: FieldValue.increment(-a.quarterCount),
        ...(first ? { firstFinisher: target } : {}),
      });
      return { kind: 'doneSelf', points, bonus, first, personal };
    }

    tx.update(aRef, {
      quartersRead, status, recordedBy: byManager ? actor.uid : null,
      ...(wasDone ? { completedAt: null, pointsAwarded: 0, personalAwarded: false } : {}),
    });
    tx.update(cRef, { segments, ...(wasDone ? { remainingQuarters: FieldValue.increment(a.quarterCount) } : {}) });
    if (!wasDone) return { kind: 'partial' };
    const selfCounted = !a.recordedBy;
    return {
      kind: 'undone',
      selfCounted,
      refund: selfCounted ? (a.pointsAwarded ?? legacyRegularPoints(a, c)) : 0,
      personal: selfCounted && (a.personalAwarded ?? false),
    };
  });

  if (out.kind === 'doneSelf') {
    const total = out.points + out.bonus;
    await memberRef(groupId, target).update({ points: FieldValue.increment(total), readCount: FieldValue.increment(1) });
    const badges: string[] = [];
    if (out.first) badges.push(BADGES.starter);
    if (out.personal) badges.push(BADGES.personalKhatma);
    await db.collection('users').doc(target).set({
      points: FieldValue.increment(total),
      quartersRead: FieldValue.increment(g.wardQuarters),
      ...(out.personal ? { khatmasPersonal: FieldValue.increment(1) } : {}),
      ...(badges.length ? { badges: FieldValue.arrayUnion(...badges) } : {}),
    }, { merge: true });
    await maybeCompleteKhatma(groupId, n);
    return { done: true, points: total };
  }
  if (out.kind === 'doneByManager') {
    await maybeCompleteKhatma(groupId, n);
    return { done: true, points: 0 };
  }
  if (out.kind === 'undone' && out.selfCounted) {
    await memberRef(groupId, target).update({ points: FieldValue.increment(-out.refund), readCount: FieldValue.increment(-1) });
    await db.collection('users').doc(target).set({
      points: FieldValue.increment(-out.refund),
      quartersRead: FieldValue.increment(-g.wardQuarters),
      ...(out.personal ? { khatmasPersonal: FieldValue.increment(-1) } : {}),
    }, { merge: true });
    return { done: false, points: -out.refund };
  }
  return { done: false, points: 0 };
}

type PortionState = PortionDoc & Awarded & { quartersRead?: number; recordedBy?: string | null };

type PortionOutcome =
  | { kind: 'none' | 'partial' }
  | { kind: 'doneByManager'; cycle: number; assignee: string | null }
  | { kind: 'doneSelf'; cycle: number; assignee: string; points: number; rescue: boolean; quarters: number }
  | { kind: 'undone'; cycle: number; assignee: string | null; refund: number; quarters: number; selfCounted: boolean };

/** [quartersRead] = 'all' معناها الورد كله. */
export async function applyPortionProgress(groupId: string, portionId: string, quartersRead: number | 'all', actor: Actor) {
  const g = groupData(await groupRef(groupId).get());
  const pRef = portionsCol(groupId).doc(portionId);

  const out = await db.runTransaction(async (tx: Transaction): Promise<PortionOutcome> => {
    const snap = await tx.get(pRef);
    const p = snap.data() as PortionState | undefined;
    if (!p) throw new HttpsError('not-found', 'Portion not found.');
    const isAssignee = p.assignee === actor.uid;
    if (!actor.manager && !isAssignee) throw new HttpsError('permission-denied', 'Not your portion.');
    if (!actor.manager && p.status === 'open') throw new HttpsError('failed-precondition', 'Take the portion first.');
    const count = p.quarterCount;
    const q = quartersRead === 'all' ? count : quartersRead;
    if (q > count) throw new HttpsError('invalid-argument', 'Too many quarters.');
    const wasDone = p.status === 'done';
    const done = q === count;
    if (wasDone && done) return { kind: 'none' };

    const cRef = cycleRef(groupId, p.cycle);
    const c = (await tx.get(cRef)).data() as CycleDoc | undefined;
    const setSegment = await segmentUpdater(tx, groupId, p);
    if (wasDone && c?.khatmaComplete) throw new HttpsError('failed-precondition', 'Khatma already complete.');
    const byManager = actor.manager && !isAssignee;
    const ownCarry = p.origin === 'carry' && p.originalUid === p.assignee;

    if (done) {
      const selfDone = !byManager && p.assignee !== null;
      const points = selfDone ? count * (ownCarry ? POINTS_PER_QUARTER : RESCUE_POINTS_PER_QUARTER) : 0;
      tx.update(pRef, {
        status: 'done', quartersRead: q, completedAt: FieldValue.serverTimestamp(),
        recordedBy: byManager ? actor.uid : null, pointsAwarded: points, doneCycle: g.currentCycle,
      });
      setSegment({ status: 'done', ...(p.assignee ? { uid: p.assignee } : {}) });
      tx.update(cRef, { remainingQuarters: FieldValue.increment(-count) });
      if (selfDone) return { kind: 'doneSelf', cycle: p.cycle, assignee: p.assignee!, points, rescue: !ownCarry, quarters: count };
      return { kind: 'doneByManager', cycle: p.cycle, assignee: p.assignee };
    }

    tx.update(pRef, {
      status: p.assignee ? 'assigned' : 'open', quartersRead: q, recordedBy: byManager ? actor.uid : null,
      ...(wasDone ? { completedAt: null, pointsAwarded: 0, doneCycle: null } : {}),
    });
    setSegment({ status: q > 0 ? 'in_progress' : p.assignee ? 'pending' : 'open' });
    if (wasDone) tx.update(cRef, { remainingQuarters: FieldValue.increment(count) });
    if (!wasDone) return { kind: 'partial' };
    const selfCounted = !p.recordedBy && p.assignee !== null;
    return {
      kind: 'undone', cycle: p.cycle, assignee: p.assignee, quarters: count, selfCounted,
      refund: selfCounted ? (p.pointsAwarded ?? count * (ownCarry ? POINTS_PER_QUARTER : RESCUE_POINTS_PER_QUARTER)) : 0,
    };
  });

  if (out.kind === 'doneSelf') {
    await memberRef(groupId, out.assignee).update({ points: FieldValue.increment(out.points) });
    await db.collection('users').doc(out.assignee).set({
      points: FieldValue.increment(out.points),
      quartersRead: FieldValue.increment(out.quarters),
      ...(out.rescue ? { badges: FieldValue.arrayUnion(BADGES.rescuer) } : {}),
    }, { merge: true });
    await maybeCompleteKhatma(groupId, out.cycle);
    return { done: true, points: out.points, assignee: out.assignee };
  }
  if (out.kind === 'doneByManager') {
    await maybeCompleteKhatma(groupId, out.cycle);
    return { done: true, points: 0, assignee: out.assignee };
  }
  if (out.kind === 'undone' && out.selfCounted && out.assignee) {
    await memberRef(groupId, out.assignee).update({ points: FieldValue.increment(-out.refund) });
    await db.collection('users').doc(out.assignee).set({
      points: FieldValue.increment(-out.refund),
      quartersRead: FieldValue.increment(-out.quarters),
    }, { merge: true });
    return { done: false, points: -out.refund, assignee: out.assignee };
  }
  return { done: false, points: 0, assignee: out.kind === 'undone' ? out.assignee : null };
}

function readQuarters(raw: unknown): number {
  if (typeof raw !== 'number' || !Number.isInteger(raw) || raw < 0) {
    throw new HttpsError('invalid-argument', 'quartersRead must be a non-negative integer');
  }
  return raw;
}

/** العضو بيسجّل (أو بيتراجع عن) ورده في الدورة الحالية. */
export const updateProgress = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const quartersRead = readQuarters(request.data?.quartersRead);
  return await applyAssignmentProgress(groupId, uid, quartersRead, { uid, manager: false });
});

/** العضو بيسجّل (أو بيتراجع عن) تقدمه في ورد إضافي ربع ربع. */
export const updatePortionProgress = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const portionId = requireString(request.data?.portionId, 'portionId');
  const quartersRead = readQuarters(request.data?.quartersRead);
  await requireMember(groupId, uid);
  const r = await applyPortionProgress(groupId, portionId, quartersRead, { uid, manager: false });
  return { done: r.done, points: r.points };
});

// ---------------------------------------------------------------------------
// الأوراد الإضافية: متأخرة، أو موزعة، أو خانات فاضية

/**
 * الخانة الفاضية (empty) أو اللي صاحبها خرج (left) لون خانتها على الخريطة بيتبع الورد الإضافي.
 * بنقرا قبل أي كتابة في الـtransaction، وبنرجّع دالة تكتب التحديث.
 */
async function segmentUpdater(tx: Transaction, groupId: string, p: PortionDoc) {
  if (p.origin !== 'empty' && p.origin !== 'left') return () => {};
  const g = groupData(await tx.get(groupRef(groupId)));
  const cRef = cycleRef(groupId, p.cycle);
  const c = (await tx.get(cRef)).data() as CycleDoc | undefined;
  if (!c) return () => {};
  const seg = Math.floor((p.fromQuarter - 1) / g.wardQuarters);
  return (patch: Partial<Segment>) => {
    tx.update(cRef, { segments: c.segments.map((s) => (s.seg === seg ? { ...s, ...patch } : s)) });
  };
}

export const claimPortion = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const portionId = requireString(request.data?.portionId, 'portionId');
  await requireMember(groupId, uid);
  const pRef = portionsCol(groupId).doc(portionId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(pRef);
    const p = snap.data() as PortionDoc | undefined;
    if (!p) throw new HttpsError('not-found', 'Portion not found.');
    if (p.status !== 'open') throw new HttpsError('failed-precondition', 'Portion already taken.');
    const setSegment = await segmentUpdater(tx, groupId, p);
    tx.update(pRef, { assignee: uid, status: 'assigned', claimedAt: FieldValue.serverTimestamp() });
    setSegment({ uid, status: 'pending' });
  });
  return { ok: true };
});

/** الأدمن أو المساعد بيحدد مين ياخد ورد متأخر، أو بيرجّعه للتطوع (uid = null). */
export const assignPortion = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const portionId = requireString(request.data?.portionId, 'portionId');
  const target: string | null = typeof request.data?.uid === 'string' ? request.data.uid : null;
  await requireManager(groupId, uid);
  if (target) await requireMember(groupId, target);
  const pRef = portionsCol(groupId).doc(portionId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(pRef);
    const p = snap.data() as PortionDoc | undefined;
    if (!p) throw new HttpsError('not-found', 'Portion not found.');
    if (p.status === 'done') throw new HttpsError('failed-precondition', 'Portion already done.');
    const setSegment = await segmentUpdater(tx, groupId, p);
    tx.update(pRef, target ? { assignee: target, status: 'assigned' } : { assignee: null, status: 'open' });
    setSegment(target ? { uid: target, status: 'pending' } : { uid: null, status: 'open' });
  });
  if (target) {
    const g = groupData(await groupRef(groupId).get());
    await notifyUsers([target], () => ({
      ar: { title: g.name, body: 'الأدمن طلب منك تقرا ورد إضافي.' },
      en: { title: g.name, body: 'The admin asked you to read an extra portion.' },
    }), { groupId, type: 'portion' });
  }
  return { ok: true };
});

/** النسخ القديمة من التطبيق: "خلصت الورد ده" مرة واحدة. */
export const completePortion = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const portionId = requireString(request.data?.portionId, 'portionId');
  await requireMember(groupId, uid);
  const r = await applyPortionProgress(groupId, portionId, 'all', { uid, manager: false });
  return { points: r.points };
});

// ---------------------------------------------------------------------------
// الأدمن أو المساعد بيسجّل ورد عضو قراه برة التطبيق: من غير نقاط ولا أوسمة،
// ومش بيتحسب في الالتزام والسلسلة. والعضو يقدر يسجّل بنفسه بعدها عادي.

export const recordProgress = onCall(async (request) => {
  const managerUid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  await requireManager(groupId, managerUid);
  const g = groupData(await groupRef(groupId).get());
  if (g.status !== 'active') throw new HttpsError('failed-precondition', 'Khatma not started.');
  const actor = { uid: managerUid, manager: true };
  const portionId = typeof request.data?.portionId === 'string' ? request.data.portionId : null;

  let notifyUid: string | null;
  if (portionId) {
    // النسخ القديمة كانت بتبعت done بس.
    const raw = request.data?.quartersRead;
    const q: number | 'all' = raw === undefined ? (request.data?.done === true ? 'all' : 0) : readQuarters(raw);
    notifyUid = (await applyPortionProgress(groupId, portionId, q, actor)).assignee;
  } else {
    const target = requireString(request.data?.uid, 'uid');
    await applyAssignmentProgress(groupId, target, readQuarters(request.data?.quartersRead), actor);
    notifyUid = target;
  }

  if (notifyUid && notifyUid !== managerUid) {
    await notifyUsers([notifyUid], () => ({
      ar: { title: g.name, body: 'الأدمن حدّث تقدم وردك.' },
      en: { title: g.name, body: 'An admin updated your portion progress.' },
    }), { groupId, type: 'recorded' });
  }
  return { ok: true };
});

// ---------------------------------------------------------------------------
// مستخدمة من invites.ts و groups.ts

/**
 * عضو جديد دخل والختمة شغالة: لو القطعة بتاعته في الدورة الحالية لسه فاضية ومحدش أخدها،
 * بتبقى ورده بدل ما تفضل للتطوع.
 */
export async function adoptEmptySegment(groupId: string, uid: string): Promise<void> {
  const g = groupData(await groupRef(groupId).get());
  if (g.status !== 'active') return;
  const member = await requireMember(groupId, uid);
  const n = g.currentCycle;
  const seg = segmentFor(member.slot, n, g.slots);
  const range = segmentRange(seg, g.wardQuarters);
  const open = await portionsCol(groupId)
    .where('cycle', '==', n).where('origin', '==', 'empty').where('fromQuarter', '==', range.fromQuarter)
    .where('status', '==', 'open').limit(1).get();
  if (open.empty) return;
  const pRef = open.docs[0].ref;
  const cRef = cycleRef(groupId, n);
  await db.runTransaction(async (tx) => {
    const [pSnap, cSnap] = await Promise.all([tx.get(pRef), tx.get(cRef)]);
    if ((pSnap.data() as PortionDoc | undefined)?.status !== 'open') return;
    const c = cSnap.data() as CycleDoc;
    tx.delete(pRef);
    tx.set(assignmentRef(groupId, n, uid), {
      ...range, segment: seg, quarterCount: g.wardQuarters, quartersRead: 0, status: 'pending', closed: false,
    });
    tx.update(cRef, { segments: c.segments.map((s) => (s.seg === seg ? { ...s, uid, status: 'pending' } : s)) });
  });
}

/**
 * عضو خرج أو اتشال: الجزء اللي لسه مقراهوش من ورده الحالي، وأي ورد إضافي عليه،
 * بيبقوا متاحين للتطوع.
 */
export async function releaseMemberWork(groupId: string, uid: string): Promise<void> {
  const g = groupData(await groupRef(groupId).get());
  const writer = db.bulkWriter();
  if (g.status === 'active') {
    const n = g.currentCycle;
    const aRef = assignmentRef(groupId, n, uid);
    const cRef = cycleRef(groupId, n);
    const [aSnap, cSnap] = await Promise.all([aRef.get(), cRef.get()]);
    const a = aSnap.data() as AssignmentDoc | undefined;
    if (a && !a.closed && a.status !== 'done') {
      const rest: QuarterRange = { fromQuarter: a.fromQuarter + a.quartersRead, toQuarter: a.toQuarter };
      writer.delete(aRef);
      const c = cSnap.data() as CycleDoc;
      writer.update(cRef, {
        segments: c.segments.map((s) => (s.seg === a.segment ? { ...s, uid: null, status: 'open' } : s)),
        remainingQuarters: FieldValue.increment(-a.quartersRead),
      });
      if (rest.fromQuarter <= rest.toQuarter) {
        writer.set(portionsCol(groupId).doc(), {
          ...rest, cycle: n, quarterCount: quarterCount(rest), assignee: null, status: 'open', origin: 'left',
          originalUid: uid, createdAt: FieldValue.serverTimestamp(),
        });
      }
    }
  }
  const mine = await portionsCol(groupId).where('assignee', '==', uid).where('status', '==', 'assigned').get();
  mine.forEach((d) => writer.update(d.ref, { assignee: null, status: 'open' }));
  await writer.close();
}
