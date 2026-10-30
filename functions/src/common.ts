import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, DocumentReference, DocumentSnapshot, Firestore } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';

// لازم التهيئة تحصل قبل أي استخدام لـFirestore في أي ملف.
if (getApps().length === 0) initializeApp();

// الدوحة: أقرب منطقة لقاعدة البيانات (الدمام) متاحة لـCloud Functions في المشروع.
// وحد أقصى للنسخ عشان التكلفة تفضل تحت السيطرة. هنا عشان يتنفذ قبل تعريف أي Function.
setGlobalOptions({ region: 'me-central1', maxInstances: 10 });

export const db: Firestore = getFirestore();

export type Role = 'admin' | 'assistant' | 'member';

export interface GroupDoc {
  name: string;
  type: 'private' | 'public';
  wardQuarters: number;
  slots: number;
  cycleCount: number;
  cycleUnit: 'day' | 'week' | 'month';
  cycleStartDay: number;
  cycleStartHour: number;
  cycleStartDayOfMonth: number;
  utcOffsetMinutes: number;
  lateDefault: 'ask' | 'carry' | 'distribute' | 'volunteer';
  adminId: string;
  memberCount: number;
  status: 'forming' | 'active';
  currentCycle: number;
  isOpen: boolean;
  hasFreeSlots: boolean;
  khatmasCompleted: number;
}

export interface MemberDoc {
  role: Role;
  slot: number;
  name: string;
  photoUrl?: string;
  points?: number;
  readCount?: number;
}

export interface Segment {
  seg: number;
  uid: string | null;
  status: 'pending' | 'in_progress' | 'done' | 'late' | 'open';
}

export function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

export function requireString(value: unknown, field: string, max = 200): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > max) {
    throw new HttpsError('invalid-argument', `${field} is required`);
  }
  return value;
}

export function groupRef(groupId: string): DocumentReference {
  return db.collection('groups').doc(groupId);
}

export function memberRef(groupId: string, uid: string): DocumentReference {
  return groupRef(groupId).collection('members').doc(uid);
}

export function userGroupIndexRef(uid: string, groupId: string): DocumentReference {
  return db.collection('users').doc(uid).collection('groups').doc(groupId);
}

export function cycleRef(groupId: string, cycle: number): DocumentReference {
  return groupRef(groupId).collection('cycles').doc(String(cycle));
}

export function assignmentRef(groupId: string, cycle: number, uid: string): DocumentReference {
  return cycleRef(groupId, cycle).collection('assignments').doc(uid);
}

export function groupData(snap: DocumentSnapshot): GroupDoc {
  if (!snap.exists) throw new HttpsError('not-found', 'Group not found.');
  return snap.data() as GroupDoc;
}

export function isManager(role: Role | undefined): boolean {
  return role === 'admin' || role === 'assistant';
}

/** بيتأكد إن المستخدم عضو، وبيرجّع بياناته في المجموعة. */
export async function requireMember(groupId: string, uid: string): Promise<MemberDoc> {
  const snap = await memberRef(groupId, uid).get();
  if (!snap.exists) throw new HttpsError('permission-denied', 'Not a member of this group.');
  return snap.data() as MemberDoc;
}

export async function requireManager(groupId: string, uid: string): Promise<MemberDoc> {
  const m = await requireMember(groupId, uid);
  if (!isManager(m.role)) throw new HttpsError('permission-denied', 'Admins only.');
  return m;
}

/** اسم المستخدم وصورته من ملفه، للعرض في لوحة المجموعة. */
export async function userDisplay(uid: string): Promise<{ name: string; photoUrl?: string; locale: string }> {
  const snap = await db.collection('users').doc(uid).get();
  const d = snap.data() ?? {};
  return {
    name: typeof d.name === 'string' && d.name ? d.name : '—',
    photoUrl: typeof d.photoUrl === 'string' ? d.photoUrl : undefined,
    locale: d.locale === 'en' ? 'en' : 'ar',
  };
}
