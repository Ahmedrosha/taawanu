// آخر نسخة وأقل نسخة مسموحة (config/app)، وإحصائية بعدد المستخدمين على كل نسخة. مفيش بيانات شخصية في السجل.
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

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
})().catch((e) => { console.error(e.message); process.exit(1); });
