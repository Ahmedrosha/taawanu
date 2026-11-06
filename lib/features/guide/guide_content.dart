import 'package:flutter/material.dart';

/// محتوى دليل الاستخدام. النص بيدعم **عريض** وأيقونات بالشكل {i:اسم} (شوف [guideIcons]).
sealed class GuideBlock {
  const GuideBlock();
}

/// فقرة.
class GText extends GuideBlock {
  const GText(this.text);
  final String text;
}

/// نقط.
class GBullets extends GuideBlock {
  const GBullets(this.items);
  final List<String> items;
}

/// جدول من عمودين.
class GTable extends GuideBlock {
  const GTable(this.rows);
  final List<(String, String)> rows;
}

/// مفتاح ألوان الخريطة: (حالة الورد، الشرح).
class GLegend extends GuideBlock {
  const GLegend(this.items);
  final List<(String, String)> items;
}

/// ملاحظة مميزة.
class GNote extends GuideBlock {
  const GNote(this.text);
  final String text;
}

class GuideSection {
  const GuideSection(this.icon, this.title, this.blocks);
  final IconData icon;
  final String title;
  final List<GuideBlock> blocks;
}

const guideIcons = <String, IconData>{
  'add': Icons.add,
  'link': Icons.link,
  'explore': Icons.travel_explore,
  'bell': Icons.notifications_none,
  'invite': Icons.person_add_alt_1_outlined,
  'more': Icons.more_horiz,
  'zoom': Icons.zoom_in,
  'book': Icons.menu_book_outlined,
  'mail': Icons.mail_outline,
  'play': Icons.play_circle_outline,
  'download': Icons.download_for_offline_outlined,
  'undo': Icons.undo,
  'auto': Icons.visibility_outlined,
  'pin': Icons.push_pin_outlined,
  'record': Icons.edit_note,
  'swap': Icons.swap_vert,
  'shield': Icons.shield_outlined,
};

const guideAr = <GuideSection>[
  GuideSection(Icons.lightbulb_outline, 'فكرة التطبيق', [
    GBullets([
      '**المجموعة:** ناس بيختموا القرآن مع بعض. المصحف بيتقسم أوراد على قد عدد الخانات، وكل عضو معاه ورد.',
      '**الدورة:** المدة اللي كل واحد يقرا فيها ورده (يوم، أسبوع، شهر أو أكتر). لما كل الأوراد تخلص تبقى الختمة كملت.',
      '**التدوير:** كل دورة جديدة، كل عضو بياخد الورد اللي بعد ورده لوحده. لو قريت الجزء ٥، الدورة الجاية معاك الجزء ٦.',
      '**الختمة الشخصية:** لما تكمّل كل الأوراد بالتدوير، تبقى ختمت المصحف كله بنفسك.',
    ]),
  ]),
  GuideSection(Icons.home_outlined, 'الرئيسية', [
    GBullets([
      'فوق: نقاطك، ونسبة التزامك، والدورات المتتالية اللي خلصتها في ميعادها.',
      'كارت لكل مجموعة إنت فيها: وردك والوقت الباقي على الدورة. دوس **اقرا دلوقتي** يفتح المصحف على وردك على طول.',
      'لو ملكش ورد في دورة، هيظهرلك "ملكش ورد الدورة دي".',
    ]),
  ]),
  GuideSection(Icons.groups_outlined, 'مجموعاتي', [
    GBullets([
      '**الفلاتر:** بديرها / مشترك فيها، خاصة / عامة، وحجم الورد.',
      '**الترتيب:** الأحدث، أو الاسم، أو اللي فاضل فيها ورد، أو الحجم.',
      '**التثبيت {i:pin}:** دوس دوسة طويلة على أي مجموعة عشان تثبّتها فوق.',
      '**البحث:** بيظهر لما يبقى عندك أكتر من ٦ مجموعات.',
      'الأزرار اللي فوق: {i:add} مجموعة جديدة، {i:link} انضم برابط أو كود، {i:explore} دوّر على مجموعات عامة فيها خانات فاضية، {i:bell} الإشعارات.',
    ]),
  ]),
  GuideSection(Icons.add_circle_outline, 'إنشاء مجموعة', [
    GBullets([
      '**نوع المجموعة:** خاصة (محدش يدخلها غير برابط الدعوة) أو عامة (بتظهر في البحث لأي حد).',
      '**ورد كل عضو:** من ربع حزب لحد ٥ أجزاء. حجم الورد بيحدد عدد الخانات، يعني عدد الأعضاء. مثلًا ورد جزء = ٣٠ خانة.',
      '**وردك إنت في المجموعة:** الورد اللي هتقراه في أول دورة، ولازم تختاره عشان تنشئ المجموعة. لو جاي من ختمة شغالة على الواتساب، اختار الورد اللي إنت واقف عنده.',
      '**مدة الدورة واليوم اللي بتبدأ فيه.**',
    ]),
    GText('**لو عضو اتأخر**، اللي فاضل من ورده يروح فين:'),
    GBullets([
      '**يترحل عليه:** يكمّله هو في الدورة الجاية جنب ورده الجديد.',
      '**يتوزع على اللي خلصوا:** يتقسم على الأعضاء اللي خلصوا وردهم.',
      '**يتعرض على متطوع:** يظهر كورد إضافي وأي حد ياخده.',
      '**اسألني كل مرة:** يظهر كورد إضافي وإنت تحدد مين ياخده.',
    ]),
  ]),
  GuideSection(Icons.person_add_alt_1_outlined, 'الدعوة والانضمام', [
    GBullets([
      'من لوحة المجموعة دوس {i:invite} وابعت رابط الدعوة على الواتساب أو أي مكان.',
      'اللي معاه الرابط يفتحه، أو يلصقه أو يكتب الكود من {i:link} في مجموعاتي.',
      '**قبل الانضمام لازم تختار وردك.** المحجوز بيظهر رمادي.',
      'لو الختمة بدأت، بتختار من الأوراد الفاضية، وتقراه في الدورة دي وبعدها تكمّل بالترتيب.',
    ]),
  ]),
  GuideSection(Icons.dashboard_outlined, 'لوحة المجموعة', [
    GBullets([
      'فوق: حجم الورد، ومدة الدورة، وعدد الأعضاء، وعدد الختمات.',
      'كارت **وردك** فيه تقدّمك وزرار القراية.',
      '**أوراد إضافية:** الخانات الفاضية والأوراد المتأخرة. لو خلصت وردك خد منها عشان الختمة تكمل، وليك نقاط زيادة.',
      'الأوراد الإضافية متقسمة: **أورادي** (اللي معاك)، و**أوراد متاحة** (تدوس **استلام** وتاخدها)، و**قيد القراءة** (حد واخدها ولسه بيقرا)، وتحتهم سطر **الأوراد المكتملة** وسطر **من الدورات السابقة**، وكل سطر بيفتح صفحته.',
      'قبل البداية تقدر تغيّر وردك لأي ورد متاح. بعد البداية الأدمن بس اللي بيغيّر.',
    ]),
  ]),
  GuideSection(Icons.grid_view_rounded, 'خريطة الختمة', [
    GText('٣٠ مربع، واحد لكل جزء، وتحت كل جزء أوراده بألوانها:'),
    GLegend([
      ('done', 'خلص'),
      ('in_progress', 'جاري: الأصفر بيتملى على قد اللي اتقرا'),
      ('pending', 'لم يبدأ'),
      ('late', 'متأخر: الدورة خلصت ومخلصش، أو فاضل أقل من ربع الدورة ولسه مخلصش'),
      ('late_done', 'اتأخر واتكمّل بعدين من الأوراد الإضافية'),
      ('open', 'متاح: مفيش حد واخده'),
    ]),
    GBullets([
      'النسبة فوق هي اللي خلص من الختمة كلها.',
      'دوس على أي جزء تشوف أوراده ومين معاه كل ورد.',
      '**الدورات اللي فاتت:** بالأسهم فوق الخريطة تشوف خريطة كل دورة وتواريخها. الورد المتأخر اللي لسه محدش خده عليه "خده".',
      '**راسل الإدارة {i:mail}:** تحت الخريطة، تبعت رسالة للأدمن أو مساعد. والرد بيوصلك في الجرس.',
    ]),
  ]),
  GuideSection(Icons.shield_outlined, 'للأدمن والمساعد', [
    GBullets([
      '**بدء الختمة:** تقدر تبدأ قبل ما الخانات تتملى، والباقيين ينضموا بعدين.',
      '**توزيع الأوراد:** من {i:more} فوق. دوس على أي ورد واختار مين ياخده. لو الورد مع حد تاني هيتبادلوا، ولو حد فيهم كان قرا هيتسألك الأول لأن التقدم بيتمسح.',
      '**تسجيل ورد عضو {i:record}:** دوس على العضو في قايمة الأعضاء، أو على خانته في الخريطة. التسجيل ده مش بيدّي العضو نقاط ومش بيتحسب في التزامه.',
      '**المساعد {i:shield}:** بيقدر يعمل كل ده. "خليه مساعد" من قايمة العضو.',
      '**تذكير المتأخرين:** زرار تحت الخريطة بيبعت رسالة جاهزة أو تكتبها لكل اللي وردهم لسه مخلصش (مرة كل ٦ ساعات).',
      '**رسالة لعضو {i:mail}:** من قايمة العضو. وكل الرسايل بتتحفظ في الجرس وعليها رد.',
      '**أوراد الدورات اللي فاتت:** في سطر لوحده تحت الأوراد الإضافية، وتقدر تقفل أوراد دورة لو مش هتتكمّل (بتفضل حمرا في خريطتها).',
      'لو الأدمن خرج من المجموعة، الإدارة بتروح للمساعد، ولو مفيش مساعد بتروح لصاحب أعلى نقاط.',
    ]),
  ]),
  GuideSection(Icons.menu_book_outlined, 'القراية', [
    GBullets([
      '**شكل الصفحات:** نفس سطور وصفحات مصحف المدينة، واللي برا وردك بيظهر باهت.',
      '**زرار الكتاب {i:book}:** فوق أقصى الشمال، بيبدّل بين الصفحات والنص المتصل. في النص المتصل تقدر تكبّر وتصغّر الخط وتغيّر نوعه من زرار الخط اللي جنبهم، والتكبير بإصبعين على الصفحة بيحوّلك للنص المتصل.',
      '**التسجيل:** في آخر صفحة من كل ربع هتلاقي زرار "خلصت الربع".',
      '**مش هتعدّي الربع اللي بعده قبل ما تسجّل اللي قبله**، عشان تقدّمك يتحسب صح. اللي بعده بيظهر باهت لحد ما تسجّل.',
      '**قراءة تلقائية {i:auto}:** من غير صوت وبسرعة ثابتة. وهي شغالة اختار فوق: **آية** (الآية كلها بتتنوّر)، أو **كلمة** (كلمة كلمة)، أو **بدون** (من غير تنوير). في النص المتصل الشاشة بتطلع لفوق بنفس السرعة، وفي الصفحات الصفحة بتتقلب لوحدها. السرعة بـ − و+ تحت (من ×0.5 لـ ×4)، وبتقف في آخر الربع لحد ما تسجّله. وتقدر تبدأ من أي آية: دوس عليها واختار "اقرأ تلقائي من هنا".',
      '**تراجع {i:undo}:** بيلغي آخر ربع سجّلته.',
      'الشاشة مش بتقفل لوحدها وإنت بتقرا.',
    ]),
  ]),
  GuideSection(Icons.record_voice_over_outlined, 'التلاوة', [
    GBullets([
      'دوس {i:play} فوق، أو دوس على آية واختار "استمع من هنا".',
      '**٧ قراء:** العفاسي، الحصري، المنشاوي، عبد الباسط، السديس، الشريم، المعيقلي. اختار من اسم القارئ في الشريط.',
      '**تكرار كل آية:** مرة، أو ٣، أو ٥، أو على طول.',
      '**تحميل الورد {i:download}:** عشان تسمع من غير نت.',
      '**التلاوة بتقف في آخر الربع** لحد ما تسجّله، وبعدها بتكمّل اللي بعده.',
      'التلاوة شغالة والتطبيق مفتوح بس.',
    ]),
  ]),
  GuideSection(Icons.auto_stories_outlined, 'التفسير', [
    GBullets([
      'دوس على أي آية واختار "التفسير".',
      '**٣ تفاسير:** الميسر (شغال من غير نت)، والسعدي، وابن كثير.',
      'لو التلاوة شغالة، التفسير بيمشي مع الآية اللي بتتقري.',
      'بالأسهم تروح للآية اللي قبلها أو بعدها.',
    ]),
  ]),
  GuideSection(Icons.notifications_none, 'الإشعارات', [
    GText('بيوصلك إشعار لما:'),
    GBullets([
      'تبدأ دورة جديدة، وفيه وردك.',
      'توصل لنص الدورة، أو الدورة تقرّب تخلص ووردك لسه مخلصش.',
      'الختمة تكمل.',
      'الأدمن يغيّر وردك، أو يسجّله، أو يطلب منك ورد إضافي.',
      '**للأدمن:** حد ينضم، أو في أوراد متأخرة للتطوع.',
    ]),
    GText('كل الإشعارات بتتحفظ في {i:bell} لمدة ٣٠ يوم.'),
  ]),
  GuideSection(Icons.mosque_outlined, 'الصلاة والأذكار', [
    GBullets([
      '**الصلاة:** المواقيت واتجاه القبلة حسب مكانك (الموقع بيتحفظ على موبايلك بس). تقدر تختار طريقة الحساب ووقت العصر (الجمهور أو الحنفي)، وتشغّل تنبيه وقت الصلاة وتذكير قبلها.',
      '**الأذكار:** الصباح، والمساء، وبعد الصلاة، والنوم. دوس على الذكر عشان العداد يزيد.',
    ]),
  ]),
  GuideSection(Icons.emoji_events_outlined, 'حسابي والنقاط', [
    GNote('**ليه النقاط؟** مش للمنافسة، هي وسيلة تشجيع. مثلًا لو عامل مجموعة لأولادك، اتفقوا على مكافأة لما يوصلوا لعدد نقاط معين أو ياخدوا وسام.'),
    GTable([
      ('كل ربع من وردك', '١٠'),
      ('لو خلصت في ميعاد الدورة', '+٢٠'),
      ('لو خلصت في أول نص الدورة', '+١٠ زيادة'),
      ('كل ربع من ورد إضافي', '١٥'),
      ('الختمة الجماعية تكمل (لكل الأعضاء)', '٥٠'),
      ('ختمة شخصية', '٢٠٠'),
    ]),
    GBullets([
      '**الالتزام:** نسبة الدورات اللي خلصت فيها وردك في ميعاده.',
      '**الدورات المتتالية:** كام دورة ورا بعض خلصت فيها في الميعاد.',
      '**الأوسمة:** أول ختمة، ٤ دورات متتالية، ١٢ دورة متتالية، المبادر (أول واحد يخلص في الدورة)، المنقذ (خلص ورد حد تاني)، ختمة شخصية.',
      '**إعدادات المصحف:** شكل القراية (صفحات أو نص)، وخط الصفحات، وحجم ونوع خط النص، ولون التظليل (ذهبي، أصفر، أخضر، أزرق، وردي).',
    ]),
  ]),
  GuideSection(Icons.help_outline, 'أسئلة شائعة', [
    GBullets([
      '**ليه مش قادر أعدّي للربع اللي بعده؟** لازم تسجّل الربع اللي قبله الأول.',
      '**عايز أغيّر وردي:** قبل بداية الختمة من لوحة المجموعة، وبعد البداية كلّم الأدمن.',
      '**سجّلت بالغلط:** دوس {i:undo} تراجع في شاشة القراية.',
      '**التفسير أو التلاوة مش بيحمّلوا:** محتاجين نت، ما عدا الميسر والتلاوة اللي حمّلتها.',
      '**الإشعارات مش بتوصلني:** اتأكد إنها مفتوحة لتعاونوا من إعدادات الموبايل. وكلها موجودة في {i:bell}.',
    ]),
  ]),
];

const guideEn = <GuideSection>[
  GuideSection(Icons.lightbulb_outline, 'How it works', [
    GBullets([
      '**Group:** people completing the Quran together. The Mushaf is split into portions, one per slot, and each member holds one.',
      '**Cycle:** the time each member has to read their portion (a day, a week, a month or more). When every portion is read, the khatma is complete.',
      '**Rotation:** every new cycle, each member automatically moves to the next portion. Read juz 5 this cycle, and juz 6 is yours next.',
      '**Personal khatma:** once the rotation takes you through every portion, you have read the whole Quran yourself.',
    ]),
  ]),
  GuideSection(Icons.home_outlined, 'Home', [
    GBullets([
      'At the top: your points, your commitment rate, and how many cycles in a row you finished on time.',
      'A card for each of your groups with your portion and the time left. Tap **Read now** to open the Mushaf right at your portion.',
      'If you have no portion in a cycle, you will see "No portion this cycle".',
    ]),
  ]),
  GuideSection(Icons.groups_outlined, 'My groups', [
    GBullets([
      '**Filters:** managed / joined, private / public, and portion size.',
      '**Sort:** newest, name, pending portions, or size.',
      '**Pin {i:pin}:** long-press a group to pin it to the top.',
      '**Search:** appears once you have more than 6 groups.',
      'Top buttons: {i:add} new group, {i:link} join with a link or code, {i:explore} find public groups with free slots, {i:bell} notifications.',
    ]),
  ]),
  GuideSection(Icons.add_circle_outline, 'Creating a group', [
    GBullets([
      '**Type:** private (join by invite link only) or public (anyone can find it).',
      '**Portion size:** from a quarter hizb up to 5 juz. The size sets the number of slots, i.e. members. A one-juz portion means 30 slots.',
      '**Your own portion:** what you will read in the first cycle. You must pick it to create the group. Moving a khatma from WhatsApp? Pick the portion you are on.',
      '**Cycle length and start day.**',
    ]),
    GText('**If a member is late**, the rest of their portion goes to:'),
    GBullets([
      '**Carry over:** they finish it next cycle, alongside their new portion.',
      '**Split among finishers:** divided between members who finished.',
      '**Offer to volunteers:** shown as an extra portion anyone can take.',
      '**Ask me each time:** shown as an extra portion, and you choose who takes it.',
    ]),
  ]),
  GuideSection(Icons.person_add_alt_1_outlined, 'Inviting and joining', [
    GBullets([
      'On the group board, tap {i:invite} and share the invite link on WhatsApp or anywhere.',
      'Whoever has the link opens it, or pastes the link or code from {i:link} in My groups.',
      '**You must choose your portion before joining.** Taken portions are grey.',
      'If the khatma has started, you pick from the free portions, read it this cycle, then continue in order.',
    ]),
  ]),
  GuideSection(Icons.dashboard_outlined, 'Group board', [
    GBullets([
      'At the top: portion size, cycle length, members and khatmas completed.',
      'The **Your portion** card shows your progress and the read button.',
      '**Extra portions:** free slots and late portions. Finished yours? Take one so the khatma completes, and earn extra points.',
      'Before the start you can switch to any free portion. After it starts, only the admin can change portions.',
    ]),
  ]),
  GuideSection(Icons.grid_view_rounded, 'Khatma map', [
    GText('30 tiles, one per juz, each showing its portions by colour:'),
    GLegend([
      ('done', 'Done'),
      ('in_progress', 'In progress: the yellow fills as it is read'),
      ('pending', 'Not started'),
      ('late', 'Late: the cycle ended unfinished, or less than a quarter of the cycle is left and it is unfinished'),
      ('late_done', 'Late, then completed from extra portions'),
      ('open', 'Open: nobody holds it'),
    ]),
    GBullets([
      'The percentage at the top is how much of the whole khatma is done.',
      'Tap any juz to see its portions and who holds each.',
      '**Past cycles:** use the arrows above the map to see each cycle and its dates. An untaken late portion has a "Take" button.',
      '**Message the admins {i:mail}:** below the map, send a message to the admin or an assistant. Replies arrive in the bell.',
    ]),
  ]),
  GuideSection(Icons.shield_outlined, 'For admins and assistants', [
    GBullets([
      '**Start the khatma:** you can start before all slots are filled; others can join later.',
      '**Assign portions:** from {i:more} at the top. Tap a portion and choose who takes it. If someone else holds it they swap, and if either had started reading you will be asked first, since progress is cleared.',
      '**Record a member\'s portion {i:record}:** tap the member in the members list, or their tile on the map. This gives them no points and does not count toward their commitment.',
      '**Assistant {i:shield}:** can do all of the above. Use "Make assistant" from a member\'s menu.',
      '**Remind those behind:** a button below the map sends a ready-made or custom message to everyone who hasn\'t finished (once every 6 hours).',
      '**Message a member {i:mail}:** from the member\'s menu. All messages are kept in the bell with a reply button.',
      '**Past cycles\' portions:** in their own row under extra portions; you can close a cycle\'s leftovers if they won\'t be completed (they stay red on its map).',
      'If the admin leaves, the assistant takes over, or the member with the most points if there is none.',
    ]),
  ]),
  GuideSection(Icons.menu_book_outlined, 'Reading', [
    GBullets([
      '**Pages:** the same lines and pages as the Madinah Mushaf. Text outside your portion is dimmed.',
      '**Book button {i:book}:** at the far left, switches between pages and continuous text. In continuous text you can make the font bigger or smaller, or change it with the font button next to them, and pinching a page also switches to continuous text.',
      '**Recording:** on the last page of each quarter you will find a "Finished this quarter" button.',
      '**You cannot move past a quarter until you record it**, so your progress stays accurate. The next quarter stays dimmed until then.',
      '**Auto-read {i:auto}:** silent, at a steady pace. While it runs, choose at the top: **Ayah** (the whole ayah lights up), **Word** (word by word) or **None** (no highlight). In continuous text the screen scrolls up at the same pace; on pages, pages turn by themselves. Adjust the speed with − and + (×0.5 to ×4). It pauses at the end of the quarter until you record it. To start from any ayah, tap it and choose "Auto-read from here".',
      '**Undo {i:undo}:** removes the last quarter you recorded.',
      'The screen stays on while you read.',
    ]),
  ]),
  GuideSection(Icons.record_voice_over_outlined, 'Recitation', [
    GBullets([
      'Tap {i:play} at the top, or tap an ayah and choose "Listen from here".',
      '**7 reciters:** Alafasy, Al-Husary, Al-Minshawi, Abdul Basit, As-Sudais, Ash-Shuraym, Al-Muaiqly. Tap the reciter name in the bar to change.',
      '**Repeat each ayah:** once, 3 times, 5 times, or continuously.',
      '**Download the portion {i:download}:** to listen offline.',
      '**Recitation pauses at the end of the quarter** until you record it, then carries on with the next.',
      'Recitation plays only while the app is open.',
    ]),
  ]),
  GuideSection(Icons.auto_stories_outlined, 'Tafsir', [
    GBullets([
      'Tap any ayah and choose "Tafsir".',
      '**3 tafsirs:** Al-Muyassar (works offline), As-Saadi and Ibn Kathir.',
      'While recitation plays, the tafsir follows the current ayah.',
      'Use the arrows to move to the previous or next ayah.',
    ]),
  ]),
  GuideSection(Icons.notifications_none, 'Notifications', [
    GText('You are notified when:'),
    GBullets([
      'A new cycle starts, with your portion.',
      'The cycle is halfway through, or ending soon, and your portion is unfinished.',
      'The khatma is complete.',
      'An admin changes or records your portion, or asks you to read an extra one.',
      '**Admins:** someone joins, or late portions are open for volunteers.',
    ]),
    GText('All notifications are kept in {i:bell} for 30 days.'),
  ]),
  GuideSection(Icons.mosque_outlined, 'Prayer and adhkar', [
    GBullets([
      '**Prayer:** prayer times and qibla direction for your location (stored only on your phone). Choose the calculation method and Asr time (standard or Hanafi), and turn on prayer-time alerts and reminders.',
      '**Adhkar:** morning, evening, after prayer and before sleep. Tap a dhikr to count it.',
    ]),
  ]),
  GuideSection(Icons.emoji_events_outlined, 'Profile and points', [
    GNote('**Why points?** Not to compete, but to encourage. For example, in a group with your children, agree on a reward when they reach a number of points or earn a badge.'),
    GTable([
      ('Each quarter of your portion', '10'),
      ('Finished within the cycle', '+20'),
      ('Finished in the first half of the cycle', '+10 more'),
      ('Each quarter of an extra portion', '15'),
      ('Group khatma completed (all members)', '50'),
      ('Personal khatma', '200'),
    ]),
    GBullets([
      '**Commitment:** the share of cycles where you finished your portion on time.',
      '**Cycles in a row:** how many consecutive cycles you finished on time.',
      '**Badges:** first khatma, 4 cycles in a row, 12 cycles in a row, Starter (first to finish in a cycle), Rescuer (finished someone else\'s portion), personal khatma.',
      '**Mushaf settings:** reading style (pages or text), page font, text size and font, and the highlight color (gold, yellow, green, blue, pink).',
    ]),
  ]),
  GuideSection(Icons.help_outline, 'FAQ', [
    GBullets([
      '**Why can\'t I move to the next quarter?** Record the current quarter first.',
      '**I want a different portion:** before the khatma starts, change it on the group board. After that, ask the admin.',
      '**I recorded by mistake:** tap {i:undo} Undo on the reading screen.',
      '**Tafsir or recitation won\'t load:** they need internet, except Al-Muyassar and downloaded recitations.',
      '**I don\'t get notifications:** make sure they are allowed for Taawanu in your phone settings. They are all in {i:bell} too.',
    ]),
  ]),
];
