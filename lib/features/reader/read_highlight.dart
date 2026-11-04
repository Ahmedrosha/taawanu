/// اللي بيتنوّر في القراءة: آية كاملة، أو كلمة واحدة منها ([word] من ٠).
class ReadHighlight {
  const ReadHighlight(this.surah, this.ayah, [this.word]);

  final int surah;
  final int ayah;
  final int? word;

  bool isAyah(int s, int a) => s == surah && a == ayah;

  @override
  bool operator ==(Object other) => other is ReadHighlight && other.surah == surah && other.ayah == ayah && other.word == word;

  @override
  int get hashCode => Object.hash(surah, ayah, word);
}
