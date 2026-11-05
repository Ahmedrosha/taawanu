// فحص سريع لمجموعة بالاسم: بيطبع معلومات عامة بس (من غير إيميلات أو أسامي أو IDs)
// لأن سجلّات GitHub Actions في المستودع العام بيشوفها أي حد.
const admin = require('firebase-admin');

admin.initializeApp({ projectId: 'taawanu-4ca70' });
const db = admin.firestore();
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
        const u = await admin.auth().getUser(adminUid);
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
}

main().catch((e) => {
  console.log('::error title=Group lookup::' + e.message);
  process.exit(1);
});
