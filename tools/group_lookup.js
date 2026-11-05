// فحص سريع لمجموعة بالاسم: بيطبع معلومات عامة بس (من غير إيميلات أو أسامي أو IDs)
// لأن سجلّات GitHub Actions في المستودع العام بيشوفها أي حد.
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');

initializeApp({ projectId: 'taawanu-4ca70' });
const db = getFirestore();
const REVIEW = ['review@taawanu.app'];

async function main() {
  const name = process.argv[2];
  const groups = await db.collection('groups').where('name', '==', name).get();
  console.log(`groups named "${name}": ${groups.size}`);
  for (const g of groups.docs) {
    const d = g.data();
    const members = await g.ref.collection('members').count().get();
    const adminUid = d.adminId;
    let who = 'unknown';
    let providers = [];
    if (adminUid) {
      try {
        const u = await getAuth().getUser(adminUid);
        who = REVIEW.includes((u.email || '').toLowerCase()) ? 'the App Review account' : 'another user (not the review account)';
        providers = u.providerData.map((p) => p.providerId);
      } catch (e) {
        who = 'a deleted account';
      }
    }
    const created = d.createdAt && d.createdAt.toDate ? d.createdAt.toDate().toISOString() : 'n/a';
    console.log(`::notice title=Group lookup::created ${created} by ${who} (sign-in: ${providers.join(', ') || 'n/a'}); type=${d.type || d.visibility || 'n/a'}; members=${members.data().count}; status=${d.status || 'n/a'}; cycle=${d.currentCycle ?? 'n/a'}`);
  }
  if (groups.empty) console.log('::notice title=Group lookup::No group with that name now (it may have been deleted).');

  // الجروب ممكن يكون اتمسح: بندوّر في الإشعارات المحفوظة (الجرس) مين استلم إشعارات منه.
  const users = await db.collection('users').get();
  let found = 0;
  for (const u of users.docs) {
    const n = await u.ref.collection('notifications').where('en.title', '==', name).get();
    if (n.empty) continue;
    found++;
    let who = 'another user (not the review account)';
    let providers = [];
    let created = 'n/a';
    try {
      const a = await getAuth().getUser(u.id);
      if (REVIEW.includes((a.email || '').toLowerCase())) who = 'the App Review account';
      providers = a.providerData.map((p) => p.providerId);
      created = a.metadata.creationTime;
    } catch (e) {
      who = 'an account that no longer exists';
    }
    const times = n.docs.map((d) => (d.get('createdAt') && d.get('createdAt').toDate ? d.get('createdAt').toDate().toISOString() : '?')).sort();
    const types = [...new Set(n.docs.map((d) => d.get('type')))].join(',');
    console.log(`::notice title=Recipient ${found}::${who}; sign-in: ${providers.join(', ') || 'n/a'}; account created ${created}; ${n.size} notification(s) [${types}] from ${times[0]} to ${times[times.length - 1]}`);
  }
  console.log(`recipients found: ${found} (of ${users.size} users)`);
}

main().catch((e) => {
  console.log('::error title=Group lookup::' + e.message);
  process.exit(1);
});
