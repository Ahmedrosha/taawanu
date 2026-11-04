import 'package:flutter/widgets.dart';

/// نصوص الجولة التعريفية: (عربي، إنجليزي) لكل عنصر.
const tourTexts = <String, (String, String)>{
  // الرئيسية
  'home.stats': (
    'هنا نقاطك، ونسبة التزامك، وكام دورة ورا بعض خلصت فيها في الميعاد.',
    'Your points, your commitment rate, and how many cycles in a row you finished on time.',
  ),
  'home.card': ('ده وردك في كل مجموعة، والوقت الباقي على الدورة.', 'Your portion in each group, and the time left in the cycle.'),
  'home.read': ('دوس هنا يفتحلك المصحف على وردك على طول.', 'Tap here to open the Mushaf right at your portion.'),
  'home.newGroup': ('اعمل مجموعة لأهلك أو أصحابك من هنا.', 'Create a group for your family or friends here.'),
  'home.nav': ('من تحت: مجموعاتك، والصلاة، والأذكار، وحسابك.', 'Down here: your groups, prayer, adhkar and your profile.'),
  // مجموعاتي
  'groups.bell': (
    'كل أخبار مجموعاتك هنا: الدورات الجديدة، والأعضاء اللي انضموا، وأي تغيير في وردك.',
    'All your group news: new cycles, members who joined, and any change to your portion.',
  ),
  'groups.join': ('معاك رابط دعوة أو كود؟ الصقه هنا.', 'Got an invite link or code? Paste it here.'),
  'groups.explore': ('دوّر على مجموعات عامة فيها أماكن فاضية وانضم لها.', 'Find public groups with free slots and join them.'),
  'groups.filters': (
    'فلتر المجموعات أو رتّبها. ودوسة طويلة على أي مجموعة بتثبّتها فوق.',
    'Filter or sort your groups. Long-press any group to pin it to the top.',
  ),
  // لوحة المجموعة
  'board.invite': ('ابعت رابط الدعوة لأهلك وأصحابك على الواتساب.', 'Send the invite link to family and friends on WhatsApp.'),
  'board.menu': ('إعدادات المجموعة، وتوزيع الأوراد، والخروج.', 'Group settings, assigning portions, and leaving.'),
  'board.mine': ('تقدّمك في وردك، وزرار القراية.', 'Your progress on your portion, and the read button.'),
  'board.map': (
    'كل مربع جزء. الأخضر خلص، والأصفر جاري، والرمادي لسه، والأحمر متأخر، والفاضي متاح. دوس على أي جزء تشوف مين معاه.',
    'Each tile is a juz. Green is done, yellow in progress, grey not started, red late, and hollow is open. Tap a juz to see who holds it.',
  ),
  'board.extra': (
    'خلصت وردك؟ خد ورد من هنا عشان الختمة تكمل، وليك نقاط زيادة.',
    'Finished yours? Take a portion from here so the khatma completes, and earn extra points.',
  ),
  'board.members': (
    'دوس على أي عضو عشان تسجّل ورده، أو تغيّره، أو تخليه مساعد.',
    'Tap any member to record their portion, change it, or make them an assistant.',
  ),
  // المصحف
  'reader.page': (
    'نفس صفحات مصحف المدينة، واللي برا وردك بيظهر باهت. دوس على أي آية عشان تسمعها أو تشوف تفسيرها: الميسر، والسعدي، وابن كثير.',
    'The same pages as the Madinah Mushaf; anything outside your portion is dimmed. Tap any ayah to listen to it or read its tafsir: Al-Muyassar, As-Saadi and Ibn Kathir.',
  ),
  'reader.play': (
    'اسمع وردك بصوت ٧ قراء. التلاوة بتقف في آخر الربع لحد ما تسجّله.',
    'Listen to your portion with 7 reciters. Recitation pauses at the end of the quarter until you record it.',
  ),
  'reader.auto': (
    'قراءة تلقائية من غير صوت بسرعة ثابتة: تنوّر آية آية أو كلمة كلمة أو من غير تنوير. وبتقف في آخر الربع زي التلاوة.',
    'Silent auto-read at a steady pace: highlight ayah by ayah, word by word, or nothing. It pauses at the end of the quarter, like recitation.',
  ),
  'auto.mode': (
    'اختار تنوّر الآية كلها، أو كلمة كلمة، أو من غير تنوير خالص.',
    'Highlight the whole ayah, word by word, or nothing at all.',
  ),
  'auto.speed': ('غيّر سرعة القراءة من هنا.', 'Change the reading speed here.'),
  'reader.view': (
    'زرار الكتاب بيبدّل بين صفحات المصحف والنص المتصل، ومكانه ثابت في الاتنين. وفي النص المتصل تقدر تكبّر وتصغّر الخط.',
    'The book button switches between Mushaf pages and continuous text, and stays in the same place in both. In continuous text you can make the font bigger or smaller.',
  ),
  'reader.mark': (
    'الزرار ده بيظهر في آخر صفحة من الربع. مش هتعدّي للي بعده قبل ما تسجّله.',
    "This button appears on the quarter's last page. You can't move on until you record it.",
  ),
  'reader.undo': ('سجّلت بالغلط؟ تراجع من هنا.', 'Recorded by mistake? Undo it here.'),
  // شريط التلاوة
  'recite.reciter': ('غيّر القارئ أو عدد مرات تكرار كل آية.', 'Change the reciter or how many times each ayah repeats.'),
  'recite.download': ('حمّل الورد عشان تسمع من غير نت.', 'Download the portion to listen offline.'),
  // الصلاة
  'prayer.times': ('مواقيت الصلاة حسب مكانك، والموقع بيتحفظ على موبايلك بس.', 'Prayer times for your location, which is stored only on your phone.'),
  'prayer.location': ('حدّث مكانك، أو اختار مدينة.', 'Update your location, or pick a city.'),
  'prayer.qibla': ('دوس هنا عشان تعرف اتجاه القبلة.', 'Tap here to find the qibla direction.'),
  'prayer.settings': (
    'طريقة الحساب، ووقت العصر، وتنبيه وقت الصلاة والتذكير قبلها.',
    'Calculation method, Asr time, prayer alerts and reminders before each prayer.',
  ),
  // الأذكار
  'adhkar.cats': ('الصباح، والمساء، وبعد الصلاة، والنوم.', 'Morning, evening, after prayer and before sleep.'),
  'adhkar.item': ('دوس على الذكر عشان العداد يزيد.', 'Tap a dhikr to count it.'),
  'adhkar.reset': ('يرجّع العدادات من الأول.', 'Resets the counters.'),
  'adhkar.hisn': ('حصن المسلم كامل، وفيه بحث.', 'The full Hisn al-Muslim, with search.'),
  // حسابي
  'profile.name': ('غيّر اسمك اللي بيظهر للمجموعات.', 'Change the name your groups see.'),
  'profile.points': (
    'النقاط للتشجيع. مثلًا اتفق مع أولادك على مكافأة لما يوصلوا لعدد معين أو ياخدوا وسام.',
    'Points are for encouragement. For example, agree on a reward with your children when they reach a number or earn a badge.',
  ),
  'profile.guide': ('شرح مفصّل لكل حاجة في التطبيق.', 'A detailed guide to everything in the app.'),
  'profile.mushaf': (
    'شكل القراية: صفحات المصحف أو نص متصل، ومنها تختار خط الصفحات (حفص أو خط مجمع الملك فهد)، وحجم ونوع خط النص.',
    'Reading style: Mushaf pages or continuous text, the page font (Hafs or the King Fahd Complex font), and text size and font.',
  ),
  'profile.replay': ('عايز تشوف الشرح ده تاني؟ دوس هنا.', 'Want to see this tour again? Tap here.'),
};

String tourText(BuildContext context, String id) {
  final pair = tourTexts[id];
  if (pair == null) return '';
  return Localizations.localeOf(context).languageCode == 'en' ? pair.$2 : pair.$1;
}
