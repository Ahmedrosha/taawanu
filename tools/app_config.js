// آخر نسخة وأقل نسخة مسموحة (config/app)، وإحصائية بعدد المستخدمين على كل نسخة. مفيش بيانات شخصية في السجل.
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');

initializeApp({ projectId: 'taawanu-4ca70' });
const db = getFirestore();
const valid = (v) => /^\d+\.\d+\.\d+$/.test(v);

(async () => {
  const ref = db.collection('config').doc('app');
  const update = {};
  for (const [env, field] of [
    ['LATEST_ANDROID', 'latestAndroid'], ['LATEST_IOS', 'latestIos'],
    ['MIN_ANDROID', 'minAndroid'], ['MIN_IOS', 'minIos'],
  ]) {
    const v = (process.env[env] || '').trim();
    if (!v) continue;
    if (v === 'none') update[field] = FieldValue.delete();
    else if (valid(v)) update[field] = v;
    else throw new Error(`${env}: "${v}" is not a version like 1.0.18`);
  }
  if (Object.keys(update).length) await ref.set(update, { merge: true });
  const cfg = (await ref.get()).data() || {};
  console.log(`::notice title=Config::${JSON.stringify(cfg)}`);

  const users = await db.collection('users').select('appVersion', 'appPlatform').get();
  const counts = {};
  users.docs.forEach((d) => {
    const k = `${d.get('appPlatform') || '?'} ${d.get('appVersion') || 'older than 1.0.18'}`;
    counts[k] = (counts[k] || 0) + 1;
  });
  const lines = Object.entries(counts).sort().map(([k, n]) => `${k}: ${n}`);
  console.log(`::notice title=Users per version (${users.size})::${lines.join(' | ')}`);

  // أرقام مجمّعة بس (من غير أسماء ولا إيميلات ولا UIDs).
  try {
    const now = Date.now(), day = 86400000;
    let total = 0, anon = 0, new7 = 0, new30 = 0, act1 = 0, act7 = 0, act30 = 0;
    let token;
    do {
      const page = await getAuth().listUsers(1000, token);
      for (const u of page.users) {
        total++;
        if (!u.providerData.length) anon++;
        const made = Date.parse(u.metadata.creationTime);
        const seen = Date.parse(u.metadata.lastRefreshTime || u.metadata.lastSignInTime || u.metadata.creationTime);
        if (now - made < 7 * day) new7++;
        if (now - made < 30 * day) new30++;
        if (now - seen < day) act1++;
        if (now - seen < 7 * day) act7++;
        if (now - seen < 30 * day) act30++;
      }
      token = page.pageToken;
    } while (token);
    console.log(`::notice title=Accounts::total ${total} (guest ${anon}) | new 7d ${new7} | new 30d ${new30} | active 1d ${act1} | active 7d ${act7} | active 30d ${act30}`);
  } catch (e) {
    console.log(`::warning title=Accounts::${e.message}`);
  }
  const groups = await db.collection('groups').select('status', 'memberCount', 'khatmasCompleted').get();
  let active = 0, members = 0, khatmas = 0;
  groups.docs.forEach((d) => {
    if (d.get('status') === 'active') active++;
    members += d.get('memberCount') || 0;
    khatmas += d.get('khatmasCompleted') || 0;
  });
  console.log(`::notice title=Groups::total ${groups.size} | active ${active} | memberships ${members} | khatmas completed ${khatmas}`);
})().catch((e) => { console.error(e.message); process.exit(1); });
