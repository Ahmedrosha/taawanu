// الأذكار: نصوص من الأحاديث الصحيحة (حصن المسلم)، والآيات بتتقري من نص المصحف نفسه.

class Dhikr {
  const Dhikr({required this.id, this.text, this.quran, required this.count, required this.source});

  final String id;
  final String? text;

  /// آيات من المصحف: (سورة، من آية، لحد آية).
  final (int, int, int)? quran;
  final int count;
  final String source;
}

enum AdhkarCategory { morning, evening, afterPrayer, sleep }

const _ayatAlKursi = (2, 255, 255);
const _ikhlas = (112, 1, 4);
const _falaq = (113, 1, 5);
const _nas = (114, 1, 6);

const adhkar = <AdhkarCategory, List<Dhikr>>{
  AdhkarCategory.morning: [
    Dhikr(id: 'm_kursi', quran: _ayatAlKursi, count: 1, source: 'النسائي'),
    Dhikr(id: 'm_ikhlas', quran: _ikhlas, count: 3, source: 'أبو داود والترمذي'),
    Dhikr(id: 'm_falaq', quran: _falaq, count: 3, source: 'أبو داود والترمذي'),
    Dhikr(id: 'm_nas', quran: _nas, count: 3, source: 'أبو داود والترمذي'),
    Dhikr(
      id: 'm_asbahna',
      text: 'أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ',
      count: 1,
      source: 'مسلم',
    ),
    Dhikr(
      id: 'm_bika',
      text: 'اللَّهُمَّ بِكَ أَصْبَحْنَا، وَبِكَ أَمْسَيْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ النُّشُورُ',
      count: 1,
      source: 'الترمذي',
    ),
    Dhikr(
      id: 'm_sayyid',
      text: 'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي، فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ',
      count: 1,
      source: 'البخاري',
    ),
    Dhikr(
      id: 'm_bismillah',
      text: 'بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ',
      count: 3,
      source: 'أبو داود والترمذي',
    ),
    Dhikr(
      id: 'm_radeet',
      text: 'رَضِيتُ بِاللَّهِ رَبًّا، وَبِالْإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ صَلَّى اللَّهُ عَلَيْهِ وَسَلَّمَ نَبِيًّا',
      count: 3,
      source: 'أبو داود',
    ),
    Dhikr(
      id: 'm_tahleel',
      text: 'لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ',
      count: 10,
      source: 'النسائي',
    ),
    Dhikr(id: 'm_subhan', text: 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ', count: 100, source: 'مسلم'),
    Dhikr(id: 'm_istighfar', text: 'أَسْتَغْفِرُ اللَّهَ وَأَتُوبُ إِلَيْهِ', count: 100, source: 'البخاري ومسلم'),
  ],
  AdhkarCategory.evening: [
    Dhikr(id: 'e_kursi', quran: _ayatAlKursi, count: 1, source: 'النسائي'),
    Dhikr(id: 'e_ikhlas', quran: _ikhlas, count: 3, source: 'أبو داود والترمذي'),
    Dhikr(id: 'e_falaq', quran: _falaq, count: 3, source: 'أبو داود والترمذي'),
    Dhikr(id: 'e_nas', quran: _nas, count: 3, source: 'أبو داود والترمذي'),
    Dhikr(
      id: 'e_amsayna',
      text: 'أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ',
      count: 1,
      source: 'مسلم',
    ),
    Dhikr(
      id: 'e_bika',
      text: 'اللَّهُمَّ بِكَ أَمْسَيْنَا، وَبِكَ أَصْبَحْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ الْمَصِيرُ',
      count: 1,
      source: 'الترمذي',
    ),
    Dhikr(
      id: 'e_sayyid',
      text: 'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي، فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ',
      count: 1,
      source: 'البخاري',
    ),
    Dhikr(
      id: 'e_bismillah',
      text: 'بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ',
      count: 3,
      source: 'أبو داود والترمذي',
    ),
    Dhikr(
      id: 'e_kalimat',
      text: 'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ',
      count: 3,
      source: 'مسلم',
    ),
    Dhikr(id: 'e_subhan', text: 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ', count: 100, source: 'مسلم'),
  ],
  AdhkarCategory.afterPrayer: [
    Dhikr(id: 'p_istighfar', text: 'أَسْتَغْفِرُ اللَّهَ', count: 3, source: 'مسلم'),
    Dhikr(
      id: 'p_salam',
      text: 'اللَّهُمَّ أَنْتَ السَّلَامُ وَمِنْكَ السَّلَامُ، تَبَارَكْتَ يَا ذَا الْجَلَالِ وَالْإِكْرَامِ',
      count: 1,
      source: 'مسلم',
    ),
    Dhikr(id: 'p_subhan', text: 'سُبْحَانَ اللَّهِ', count: 33, source: 'مسلم'),
    Dhikr(id: 'p_hamd', text: 'الْحَمْدُ لِلَّهِ', count: 33, source: 'مسلم'),
    Dhikr(id: 'p_takbir', text: 'اللَّهُ أَكْبَرُ', count: 33, source: 'مسلم'),
    Dhikr(
      id: 'p_tahleel',
      text: 'لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ',
      count: 1,
      source: 'مسلم',
    ),
    Dhikr(id: 'p_kursi', quran: _ayatAlKursi, count: 1, source: 'النسائي'),
  ],
  AdhkarCategory.sleep: [
    Dhikr(id: 's_kursi', quran: _ayatAlKursi, count: 1, source: 'البخاري'),
    Dhikr(id: 's_ikhlas', quran: _ikhlas, count: 3, source: 'البخاري'),
    Dhikr(id: 's_falaq', quran: _falaq, count: 3, source: 'البخاري'),
    Dhikr(id: 's_nas', quran: _nas, count: 3, source: 'البخاري'),
    Dhikr(id: 's_bismika', text: 'بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا', count: 1, source: 'البخاري'),
    Dhikr(id: 's_subhan', text: 'سُبْحَانَ اللَّهِ', count: 33, source: 'البخاري ومسلم'),
    Dhikr(id: 's_hamd', text: 'الْحَمْدُ لِلَّهِ', count: 33, source: 'البخاري ومسلم'),
    Dhikr(id: 's_takbir', text: 'اللَّهُ أَكْبَرُ', count: 34, source: 'البخاري ومسلم'),
  ],
};
