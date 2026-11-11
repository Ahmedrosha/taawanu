import SwiftUI
import WidgetKit

// ويدجتس الشاشة الرئيسية: الصلاة الجاية، وردي، ذكر اليوم.
// التطبيق بيكتب البيانات (JSON بالنصوص جاهزة باللغة المختارة) في App Group، والويدجت بيعرضها من غير نت.

private let groupId = "group.com.taawanu.taawanu"
private let navy = Color(red: 0.078, green: 0.114, blue: 0.184)
private let gold = Color(red: 0.831, green: 0.659, blue: 0.294)
private let muted = Color(red: 0.604, green: 0.659, blue: 0.741)

private func load(_ key: String) -> [String: Any]? {
  guard let raw = UserDefaults(suiteName: groupId)?.string(forKey: key),
        let data = raw.data(using: .utf8) else { return nil }
  return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

private func number(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }

private var openApp: String {
  Locale.preferredLanguages.first?.hasPrefix("ar") ?? true ? "افتح تعاونوا عشان يتظبط" : "Open Taawanu to set this up"
}

private func shortTime(_ d: Date) -> String {
  let f = DateFormatter()
  f.timeStyle = .short
  return f.string(from: d)
}

private extension View {
  @ViewBuilder func widgetBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(navy, for: .widget)
    } else {
      padding(12).frame(maxWidth: .infinity, maxHeight: .infinity).background(navy)
    }
  }
}

// MARK: - الصلاة الجاية

struct PrayerEntry: TimelineEntry {
  let date: Date
  let title: String
  let name: String
  let at: Date?
  let then: String
}

struct PrayerProvider: TimelineProvider {
  private func entries(from now: Date) -> [PrayerEntry] {
    let d = load("widget_prayer")
    let title = (d?["title"] as? String) ?? ""
    let all = ((d?["times"] as? [[String: Any]]) ?? []).map { (($0["n"] as? String) ?? "", Date(timeIntervalSince1970: number($0["t"]) / 1000)) }
    let future = all.filter { $0.1 > now }
    if future.isEmpty {
      let empty = (d?["empty"] as? String) ?? ""
      return [PrayerEntry(date: now, title: title, name: empty.isEmpty ? openApp : empty, at: nil, then: "")]
    }
    var out: [PrayerEntry] = []
    // كل إدخال بيبدأ من وقت الصلاة اللي قبله، وبيعرض الصلاة اللي عليها الدور.
    for i in 0..<min(future.count, 30) {
      let start = i == 0 ? now : future[i - 1].1
      let then = i + 1 < future.count ? "\(future[i + 1].0) \(shortTime(future[i + 1].1))" : ""
      out.append(PrayerEntry(date: start, title: title, name: future[i].0, at: future[i].1, then: then))
    }
    return out
  }

  func placeholder(in context: Context) -> PrayerEntry { PrayerEntry(date: Date(), title: "", name: "—", at: nil, then: "") }
  func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) { completion(entries(from: Date())[0]) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
    completion(Timeline(entries: entries(from: Date()), policy: .atEnd))
  }
}

struct PrayerView: View {
  let e: PrayerEntry
  var body: some View {
    VStack(spacing: 2) {
      Text(e.title).font(.caption2).foregroundColor(muted).lineLimit(1)
      Text(e.name).font(.title2.bold()).foregroundColor(.white).multilineTextAlignment(.center).minimumScaleFactor(0.5).lineLimit(2)
      if let at = e.at {
        Text(shortTime(at)).font(.subheadline.bold()).foregroundColor(gold)
        Text(at, style: .timer).font(.footnote).foregroundColor(.white).multilineTextAlignment(.center).monospacedDigit()
      }
      if !e.then.isEmpty { Text(e.then).font(.caption2).foregroundColor(muted).lineLimit(1) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .widgetURL(URL(string: "https://taawanu.app/prayer"))
    .widgetBackground()
  }
}

struct PrayerWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "PrayerWidget", provider: PrayerProvider()) { PrayerView(e: $0) }
      .configurationDisplayName("الصلاة الجاية")
      .description("الصلاة الجاية ووقتها والوقت الباقي عليها.")
      .supportedFamilies([.systemSmall])
  }
}

// MARK: - وردي

struct WardEntry: TimelineEntry {
  let date: Date
  let group: String
  let title: String
  let progress: Double
  let line: String
  let left: String
  let path: String
  let empty: Bool
}

struct WardProvider: TimelineProvider {
  private func entry(at now: Date) -> WardEntry {
    let d = load("widget_ward")
    let items = (d?["items"] as? [[String: Any]]) ?? []
    // أول ورد لسه مخلصش، وإلا أول ورد.
    guard let item = items.first(where: { !(($0["done"] as? Bool) ?? false) }) ?? items.first else {
      let empty = (d?["empty"] as? String) ?? ""
      return WardEntry(date: now, group: "", title: empty.isEmpty ? openApp : empty, progress: 0, line: "", left: "", path: "/home", empty: true)
    }
    let total = max(number(item["total"]), 1)
    let done = (item["done"] as? Bool) ?? false
    let ends = number(item["endsAt"]) / 1000
    let remain = ends - now.timeIntervalSince1970
    var left = ""
    if ends > 0, remain > 0 {
      let tpl = remain >= 86400 ? (d?["leftDays"] as? String) ?? "" : (d?["leftHours"] as? String) ?? ""
      let n = remain >= 86400 ? Int(remain / 86400) : max(Int(remain / 3600), 1)
      left = tpl.replacingOccurrences(of: "{n}", with: String(n))
    }
    return WardEntry(
      date: now,
      group: (item["group"] as? String) ?? "",
      title: (item["title"] as? String) ?? "",
      progress: min(max(number(item["read"]) / total, 0), 1),
      line: done ? ((d?["doneText"] as? String) ?? "") : ((item["progress"] as? String) ?? ""),
      left: left,
      path: "/group/" + ((item["gid"] as? String) ?? ""),
      empty: false
    )
  }

  func placeholder(in context: Context) -> WardEntry { entry(at: Date()) }
  func getSnapshot(in context: Context, completion: @escaping (WardEntry) -> Void) { completion(entry(at: Date())) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<WardEntry>) -> Void) {
    // كل ساعة عشان "فاضل كام" يفضل مظبوط.
    let now = Date()
    let entries = (0..<24).map { entry(at: now.addingTimeInterval(Double($0) * 3600)) }
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}

struct WardView: View {
  let e: WardEntry
  var body: some View {
    VStack(spacing: 4) {
      if !e.group.isEmpty { Text(e.group).font(.caption2).foregroundColor(muted).lineLimit(1) }
      Text(e.title).font(.title3.bold()).foregroundColor(e.empty ? .white : gold).multilineTextAlignment(.center).minimumScaleFactor(0.5).lineLimit(2)
      if !e.empty {
        ProgressView(value: e.progress).tint(gold)
        Text(e.line).font(.caption).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
        if !e.left.isEmpty { Text(e.left).font(.caption2).foregroundColor(muted).lineLimit(1) }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .widgetURL(URL(string: "https://taawanu.app" + e.path))
    .widgetBackground()
  }
}

struct WardWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "WardWidget", provider: WardProvider()) { WardView(e: $0) }
      .configurationDisplayName("وردي")
      .description("وردك الحالي وتقدمك والوقت الباقي في الدورة.")
      .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// MARK: - ذكر اليوم

struct DhikrEntry: TimelineEntry {
  let date: Date
  let title: String
  let text: String
}

struct DhikrProvider: TimelineProvider {
  private func entry(at date: Date) -> DhikrEntry {
    let d = load("widget_dhikr")
    let items = (d?["items"] as? [String]) ?? []
    let title = (d?["title"] as? String) ?? ""
    if items.isEmpty { return DhikrEntry(date: date, title: title, text: openApp) }
    // نفس اختيار أندرويد: رقم اليوم بتوقيت الموبايل.
    let offset = Double(TimeZone.current.secondsFromGMT(for: date))
    let day = Int(floor((date.timeIntervalSince1970 + offset) / 86400))
    return DhikrEntry(date: date, title: title, text: items[((day % items.count) + items.count) % items.count])
  }

  func placeholder(in context: Context) -> DhikrEntry { entry(at: Date()) }
  func getSnapshot(in context: Context, completion: @escaping (DhikrEntry) -> Void) { completion(entry(at: Date())) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<DhikrEntry>) -> Void) {
    let now = Date()
    let start = Calendar.current.startOfDay(for: now)
    var entries = [entry(at: now)]
    for i in 1...6 {
      if let d = Calendar.current.date(byAdding: .day, value: i, to: start) { entries.append(entry(at: d)) }
    }
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}

struct DhikrView: View {
  let e: DhikrEntry
  var body: some View {
    VStack(spacing: 6) {
      if !e.title.isEmpty { Text(e.title).font(.caption2).foregroundColor(gold).lineLimit(1) }
      Text(e.text).font(.body).foregroundColor(.white).multilineTextAlignment(.center).lineSpacing(4).minimumScaleFactor(0.5)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .widgetURL(URL(string: "https://taawanu.app/adhkar"))
    .widgetBackground()
  }
}

struct DhikrWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "DhikrWidget", provider: DhikrProvider()) { DhikrView(e: $0) }
      .configurationDisplayName("ذكر اليوم")
      .description("ذكر أو دعاء بيتغير كل يوم.")
      .supportedFamilies([.systemMedium, .systemSmall])
  }
}

@main
struct TaawanuWidgets: WidgetBundle {
  var body: some Widget {
    PrayerWidget()
    WardWidget()
    DhikrWidget()
  }
}
