# Third-party content

## Quran text
- Source: [Tanzil Project](https://tanzil.net), as distributed in [khaledhosny/quran-data](https://github.com/khaledhosny/quran-data) and mirrored by [fawazahmed0/quran-api](https://github.com/fawazahmed0/quran-api).
- Used verbatim. The only presentational change: the basmala at the start of each surah (other than Al-Fatiha and At-Tawba) is shown as a surah header instead of inside the first ayah.
- Tanzil terms: the text may be copied and redistributed verbatim with a clear reference to the source; it may not be modified.

## Quarter (rub' al-hizb) boundaries
- Source: [fawazahmed0/quran-api](https://github.com/fawazahmed0/quran-api) `info.json` (`maqras`), released into the public domain (Unlicense).

## Fonts
- Amiri Quran, Reem Kufi, IBM Plex Sans Arabic: SIL Open Font License 1.1, loaded through Google Fonts.

## Madinah Mushaf (optional reader font)
- Text: King Fahd Glorious Quran Printing Complex (KFGQPC), Uthmanic Hafs data v18, used verbatim (`assets/quran/madinah.json`), via [ibnhazm/KFGQPC](https://github.com/ibnhazm/KFGQPC).
- Font: KFGQPC HAFS Uthmanic Script v18, distributed unmodified and free of cost under the KFGQPC end-user license (`assets/fonts/KFGQPC-LICENSE.txt`): use, copy and distribute permitted; no selling or modification.

## Madinah Mushaf pages
- Page and line layout (604 pages, 15 lines, which words sit on each line): Quran.com data, via [zonetecde/mushaf-layout](https://github.com/zonetecde/mushaf-layout) (QPC V2 edition), generated into `assets/mushaf/pages.json` by `tools/build_mushaf_layout.py`. The words themselves are the KFGQPC text above.
- Page fonts (optional "identical to print" mode): KFGQPC QPC V2 page fonts and basmala font, from the same repository. Glyphs unmodified; converted from WOFF2 to TTF only so the app can load them, served free of charge from taawanu.app and downloaded on demand.

## Adhkar
- Daily adhkar and duas: from *Hisn al-Muslim* by Sa'id ibn Ali ibn Wahf al-Qahtani, via [nawafalqari/azkar-api](https://github.com/nawafalqari/azkar-api) (cleaned: elongation characters removed, spacing fixed). Quranic verses are shown from the bundled mushaf text.
- Full Hisn al-Muslim chapters: via [rn0x/hisn_almuslim_json](https://github.com/rn0x/hisn_almuslim_json). Distributed free of charge, as the book permits.
