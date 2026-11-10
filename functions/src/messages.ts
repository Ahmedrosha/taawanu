import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { cycleRef, db, groupData, groupRef, isManager as isManagerRole, MemberDoc, memberRef, requireMember, requireString, requireUid } from './common';
import { notifyUsers } from './notify';

const MAX_TEXT = 300;
const PER_HOUR = 40;
const REMINDER_EVERY_MS = 6 * 3600 * 1000;

const isManager = (m: MemberDoc) => isManagerRole(m.role);

/** كل شخص لحد ٤٠ رسالة في الساعة (عشان محدش يسيء الاستخدام). الرسالة بتتحسب مرة حتى لو رايحة لكذا حد. */
async function rateLimit(uid: string, count: number): Promise<void> {
  const ref = db.collection('rateLimits').doc(uid);
  await db.runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data() as { start?: Timestamp; count?: number } | undefined;
    const now = Date.now();
    const fresh = !d?.start || now - d.start.toMillis() > 3600 * 1000;
    const used = fresh ? 0 : (d?.count ?? 0);
    if (used + count > PER_HOUR) throw new HttpsError('resource-exhausted', 'Too many messages. Try again later.');
    tx.set(ref, fresh ? { start: Timestamp.fromMillis(now), count } : { start: d!.start, count: used + count });
  });
}

function cleanText(v: unknown): string {
  if (typeof v !== 'string') throw new HttpsError('invalid-argument', 'Message text is required.');
  const t = v.trim().replace(/\n{3,}/g, '\n\n');
  if (t.length < 1 || t.length > MAX_TEXT) throw new HttpsError('invalid-argument', `Message must be 1 to ${MAX_TEXT} characters.`);
  return t;
}

/**
 * قسم الرسائل (زي الشات): كل رسالة بتتحفظ نسخة عند اللي استلمها ونسخة عند اللي بعتها، في users/{uid}/messages.
 * المحادثة (thread):
 * - العضو العادي: محادثة واحدة مع "إدارة المجموعة" (`{groupId}_managers`)، فيها رسايله ورسايل أي حد من الإدارة.
 * - الأدمن والمساعد: محادثة لكل شخص (`{groupId}_{uid}`).
 * تذكير المتأخرين بيتحفظ عند اللي استلموه بس (مش ١٣ محادثة عند الأدمن).
 */
async function saveToMessages(
  groupId: string, groupName: string, uid: string, me: MemberDoc, recipients: string[], text: string, type: string,
): Promise<void> {
  const snaps = await db.getAll(...recipients.map((u) => memberRef(groupId, u)));
  const meManager = isManager(me);
  const base = { groupId, groupName, text, type, fromUid: uid, fromName: me.name, at: FieldValue.serverTimestamp() };
  const writes: { uid: string; data: Record<string, unknown> }[] = [];
  for (const s of snaps) {
    if (!s.exists) continue;
    const m = s.data() as MemberDoc;
    const toManagers = !isManager(m);
    writes.push({
      uid: s.id,
      data: {
        ...base, mine: false, read: false,
        thread: toManagers ? `${groupId}_managers` : `${groupId}_${uid}`,
        peerUid: toManagers ? 'managers' : uid,
        peerName: toManagers ? '' : me.name,
      },
    });
    // نسخة الأدمن/المساعد: محادثة لكل شخص.
    if (type !== 'reminder' && meManager) {
      writes.push({
        uid,
        data: { ...base, mine: true, read: true, thread: `${groupId}_${s.id}`, peerUid: s.id, peerName: m.name ?? '' },
      });
    }
  }
  // نسخة العضو العادي: رسالة واحدة في محادثته مع الإدارة.
  if (type !== 'reminder' && !meManager) {
    writes.push({ uid, data: { ...base, mine: true, read: true, thread: `${groupId}_managers`, peerUid: 'managers', peerName: '' } });
  }
  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    for (const w of writes.slice(i, i + 400)) {
      batch.set(db.collection('users').doc(w.uid).collection('messages').doc(), w.data);
    }
    await batch.commit();
  }
}

/**
 * رسالة جوه المجموعة:
 * - الأدمن والمساعد: لأي عضو أو أعضاء، أو "تذكير المتأخرين" (to = 'late'، مرة كل ٦ ساعات للمجموعة).
 * - العضو العادي: للأدمن أو المساعدين بس.
 * الرسالة بتوصل إشعار وبتتحفظ في الجرس باسم اللي بعتها، وعليها رد.
 */
export const sendGroupMessage = onCall(async (request) => {
  const uid = requireUid(request);
  const groupId = requireString(request.data?.groupId, 'groupId');
  const text = cleanText(request.data?.text);
  const me = await requireMember(groupId, uid);
  const g = groupData(await groupRef(groupId).get());
  const manager = isManager(me);
  const to = request.data?.to;

  let recipients: string[];
  let type = 'message';
  if (to === 'late') {
    if (!manager) throw new HttpsError('permission-denied', 'Only the admin or an assistant can send reminders.');
    if (g.status !== 'active') throw new HttpsError('failed-precondition', 'Khatma has not started.');
    const last = (g as unknown as { lastReminderAt?: Timestamp }).lastReminderAt;
    if (last && Date.now() - last.toMillis() < REMINDER_EVERY_MS) {
      throw new HttpsError('resource-exhausted', 'A reminder was sent recently.', { nextAt: last.toMillis() + REMINDER_EVERY_MS });
    }
    const assignments = await cycleRef(groupId, g.currentCycle).collection('assignments').get();
    recipients = assignments.docs.filter((d) => d.get('status') !== 'done' && !d.get('closed')).map((d) => d.id).filter((u) => u !== uid);
    type = 'reminder';
  } else {
    const list: unknown[] = Array.isArray(to) ? to : [to];
    recipients = [...new Set(list.filter((u): u is string => typeof u === 'string' && u.length > 0 && u !== uid))];
    if (recipients.length === 0 || recipients.length > 300) throw new HttpsError('invalid-argument', 'Choose who to send to.');
    const snaps = await db.getAll(...recipients.map((u) => memberRef(groupId, u)));
    for (const s of snaps) {
      if (!s.exists) throw new HttpsError('not-found', 'Not a member of this group.');
      // العضو العادي بيراسل الإدارة بس.
      if (!manager && !isManager(s.data() as MemberDoc)) throw new HttpsError('permission-denied', 'Members can only message the admin or assistants.');
    }
  }
  if (recipients.length === 0) return { sent: 0 };

  await rateLimit(uid, 1);
  if (type === 'reminder') await groupRef(groupId).update({ lastReminderAt: FieldValue.serverTimestamp() });

  const role = me.role === 'admin' ? { ar: 'الأدمن', en: 'admin' } : me.role === 'assistant' ? { ar: 'مساعد', en: 'assistant' } : null;
  const from = { ar: role ? `${me.name} (${role.ar})` : me.name, en: role ? `${me.name} (${role.en})` : me.name };
  await notifyUsers(recipients, () => ({
    ar: { title: `${from.ar} · ${g.name}`, body: text },
    en: { title: `${from.en} · ${g.name}`, body: text },
  }), { groupId, type, fromUid: uid, fromName: me.name });
  try {
    await saveToMessages(groupId, g.name, uid, me, recipients, text, type);
  } catch (e) {
    logger.warn('saveToMessages failed', e);
  }
  return { sent: recipients.length };
});
