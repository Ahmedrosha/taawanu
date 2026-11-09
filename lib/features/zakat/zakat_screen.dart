import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/prefs.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import '../prayer/prayer_alerts.dart';
import 'zakat_calc.dart';

/// حاسبة الزكاة: فلوس، دهب وفضة، أسهم، تجارة، وتاريخ الحول. كل البيانات على الموبايل بس.
class ZakatScreen extends StatefulWidget {
  const ZakatScreen({super.key});

  @override
  State<ZakatScreen> createState() => _ZakatScreenState();
}

class _ZakatScreenState extends State<ZakatScreen> {
  late final ZakatData _d = ZakatData.fromJson(Prefs.instance.zakatData);
  MetalPrices? _prices = MetalPrices.fromJson(Prefs.instance.metalPrices);
  bool _loading = false;
  bool _failed = false;
  final _controllers = <String, TextEditingController>{};

  static const _hawlBefore = 9101, _hawlDay = 9102;

  @override
  void initState() {
    super.initState();
    _refreshPrices();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshPrices() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final p = await MetalPrices.fetch();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (p != null) {
        _prices = p;
        Prefs.instance.setMetalPrices(p.toJson());
      } else {
        _failed = true;
      }
    });
  }

  void _save() => Prefs.instance.setZakatData(jsonEncode(_d.toJson()));

  double get _gold => _d.goldOverride ?? _prices?.gold[_d.currency] ?? 0;
  double get _silver => _d.silverOverride ?? _prices?.silver[_d.currency] ?? 0;

  NumberFormat get _fmt => NumberFormat.decimalPatternDigits(locale: 'en', decimalDigits: 0);
  String _money(double v) => '${_fmt.format(v)} ${_d.currency == 'EGP' ? AppLocalizations.of(context).egp : r'$'}';

  TextEditingController _c(String key) => _controllers.putIfAbsent(key, () {
        final v = _d.values[key];
        return TextEditingController(text: v == null || v == 0 ? '' : _trim(v));
      });

  static String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Widget _field(String key, String label, {String? suffix, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _c(key),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: hint, isDense: true),
        onChanged: (t) {
          setState(() => _d.values[key] = double.tryParse(t) ?? 0);
          _save();
        },
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children, {String? note}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(note, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _editPrice(bool gold) async {
    final t = AppLocalizations.of(context);
    final c = TextEditingController(text: _trim(gold ? _gold : _silver));
    final v = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(gold ? t.zakatGoldPrice : t.zakatSilverPrice),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: _d.currency == 'EGP' ? t.egp : r'$'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, -1), child: Text(t.zakatUseOnlinePrice)),
          TextButton(onPressed: () => Navigator.pop(context, double.tryParse(c.text)), child: Text(t.save)),
        ],
      ),
    );
    c.dispose();
    if (v == null) return;
    setState(() {
      final val = v < 0 ? null : v;
      if (gold) {
        _d.goldOverride = val;
      } else {
        _d.silverOverride = val;
      }
    });
    _save();
  }

  Future<void> _pickHawl() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _d.hawlStart ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (d == null) return;
    setState(() => _d.hawlStart = d);
    _save();
    await _scheduleHawl();
  }

  Future<void> _scheduleHawl() async {
    final start = _d.hawlStart;
    if (start == null) {
      await PrayerAlerts.instance.cancelOne(_hawlBefore);
      await PrayerAlerts.instance.cancelOne(_hawlDay);
      return;
    }
    final t = AppLocalizations.of(context);
    final h = nextHawl(start, DateTime.now());
    await PrayerAlerts.instance.requestPermission();
    await PrayerAlerts.instance.scheduleOne(_hawlBefore, DateTime(h.year, h.month, h.day - 7, 10), t.zakatHawlSoonTitle, t.zakatHawlSoonBody);
    await PrayerAlerts.instance.scheduleOne(_hawlDay, DateTime(h.year, h.month, h.day, 10), t.zakatHawlTodayTitle, t.zakatHawlTodayBody);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final r = computeZakat(_d, _gold, _silver);
    final cur = _d.currency == 'EGP' ? t.egp : r'$';
    final g = t.gramShort;
    final hawl = _d.hawlStart == null ? null : nextHawl(_d.hawlStart!, DateTime.now());
    final today = DateTime.now();
    final daysLeft = hawl?.difference(DateTime(today.year, today.month, today.day)).inDays;
    return Scaffold(
      appBar: AppBar(title: Text(t.zakatTitle, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // النتيجة.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                Text(t.zakatDue, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(_money(r.due), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  r.reached ? t.zakatReached(_money(r.total), _money(r.nisab)) : t.zakatNotReached(_money(r.total), _money(r.nisab)),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [ButtonSegment(value: 'EGP', label: Text(t.egp)), const ButtonSegment(value: 'USD', label: Text(r'$'))],
                  selected: {_d.currency},
                  onSelectionChanged: (v) {
                    setState(() => _d.currency = v.first);
                    _save();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [ButtonSegment(value: 'gold', label: Text(t.zakatNisabGold)), ButtonSegment(value: 'silver', label: Text(t.zakatNisabSilver))],
                  selected: {_d.nisab},
                  onSelectionChanged: (v) {
                    setState(() => _d.nisab = v.first);
                    _save();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // الأسعار.
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(child: Text(t.zakatPrices, style: const TextStyle(fontWeight: FontWeight.w700))),
                  if (_loading)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(tooltip: t.refresh, onPressed: _refreshPrices, icon: const Icon(Icons.refresh, size: 20)),
                ]),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(t.zakatGoldPrice),
                  subtitle: _d.goldOverride != null ? Text(t.zakatManualPrice) : null,
                  trailing: Text('${_fmt.format(_gold)} $cur'),
                  onTap: () => _editPrice(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(t.zakatSilverPrice),
                  subtitle: _d.silverOverride != null ? Text(t.zakatManualPrice) : null,
                  trailing: Text('${NumberFormat.decimalPatternDigits(locale: 'en', decimalDigits: 1).format(_silver)} $cur'),
                  onTap: () => _editPrice(false),
                ),
                Text(
                  _failed && _prices == null
                      ? t.zakatPricesFailed
                      : t.zakatPricesNote(_prices?.date ?? '—'),
                  style: TextStyle(fontSize: 11, color: _failed && _prices == null ? AppColors.statusLate : AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _section(t.zakatMoney, Icons.account_balance_wallet_outlined, [
            _field('cash', t.zakatCash, suffix: cur),
            _field('bank', t.zakatBank, suffix: cur),
            _field('deposits', t.zakatDeposits, suffix: cur),
          ]),
          _section(t.zakatGoldSilver, Icons.diamond_outlined, [
            _field('gold24', t.zakatGold(24), suffix: g),
            _field('gold21', t.zakatGold(21), suffix: g),
            _field('gold18', t.zakatGold(18), suffix: g),
            _field('silver', t.zakatSilver, suffix: g),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.zakatIncludeJewelry),
              subtitle: Text(t.zakatJewelryNote, style: const TextStyle(fontSize: 12)),
              value: _d.includeJewelry,
              onChanged: (v) {
                setState(() => _d.includeJewelry = v);
                _save();
              },
            ),
            if (_d.includeJewelry) _field('jewelry21', t.zakatJewelry, suffix: g),
          ]),
          _section(t.zakatInvestments, Icons.trending_up, [
            _field('stocks', t.zakatStocks, suffix: cur, hint: t.zakatStocksHint),
          ]),
          _section(t.zakatBusiness, Icons.storefront_outlined, [
            _field('inventory', t.zakatInventory, suffix: cur, hint: t.zakatInventoryHint),
            _field('businessCash', t.zakatBusinessCash, suffix: cur),
            _field('receivables', t.zakatReceivables, suffix: cur, hint: t.zakatReceivablesHint),
          ], note: t.zakatBusinessNote),
          _section(t.zakatDebts, Icons.remove_circle_outline, [
            _field('debts', t.zakatDebtsDue, suffix: cur, hint: t.zakatDebtsHint),
          ]),
          _section(t.zakatHawl, Icons.event_outlined, [
            OutlinedButton.icon(
              onPressed: _pickHawl,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(_d.hawlStart == null
                  ? t.zakatPickHawl
                  : t.zakatHawlStart(DateFormat.yMMMd(lang).format(_d.hawlStart!))),
            ),
            if (hawl != null) ...[
              const SizedBox(height: 10),
              Text(t.zakatHawlNext(DateFormat.yMMMd(lang).format(hawl), hijriLabel(hawl, lang)),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(daysLeft == 0 ? t.zakatHawlIsToday : t.zakatDaysLeft(daysLeft ?? 0), style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text(t.zakatHawlReminder, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              TextButton(
                onPressed: () async {
                  setState(() => _d.hawlStart = null);
                  _save();
                  await _scheduleHawl();
                },
                child: Text(t.zakatClearHawl),
              ),
            ],
          ], note: t.zakatHawlNote),
          const SizedBox(height: 4),
          Text(t.zakatDisclaimer, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
