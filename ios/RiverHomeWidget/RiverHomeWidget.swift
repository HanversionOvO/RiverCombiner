import SwiftUI
import WidgetKit

private let appGroupId = "group.com.example.river.homewidget"

struct RiverWidgetEntry: TimelineEntry {
  let date: Date
  let state: String
  let feedName: String
  let feedLabel: String
  let title: String
  let excerpt: String
  let meta: String
  let replies: Int
  let views: Int
  let topicId: Int
  let accent: Color
}

struct RiverWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> RiverWidgetEntry {
    RiverWidgetEntry(
      date: Date(),
      state: "ok",
      feedName: "latestReplied",
      feedLabel: "最新回复",
      title: "聚河畔小组件",
      excerpt: "展示你关心的帖子动态",
      meta: "河畔社区",
      replies: 0,
      views: 0,
      topicId: 0,
      accent: Color(hex: 0xFF12457A)
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (RiverWidgetEntry) -> Void) {
    completion(loadEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<RiverWidgetEntry>) -> Void) {
    let entry = loadEntry()
    let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }

  private func loadEntry() -> RiverWidgetEntry {
    let defaults = UserDefaults(suiteName: appGroupId)
    let state = defaults?.string(forKey: "river_widget_state") ?? "empty"
    let feedName = defaults?.string(forKey: "river_widget_feed") ?? "latestReplied"
    let feedLabel = defaults?.string(forKey: "river_widget_feed_label") ?? "最新回复"
    let title = defaults?.string(forKey: "river_widget_title") ?? "暂无可展示帖子"
    let excerpt = defaults?.string(forKey: "river_widget_excerpt") ?? "打开聚河畔刷新后重试"
    let meta = defaults?.string(forKey: "river_widget_meta") ?? "河畔小组件"
    let replies = defaults?.integer(forKey: "river_widget_replies") ?? 0
    let views = defaults?.integer(forKey: "river_widget_views") ?? 0
    let topicId = defaults?.integer(forKey: "river_widget_topic_id") ?? 0
    let accentRaw = defaults?.object(forKey: "river_widget_accent") as? Int ?? Int(0xFF12457A)
    let accent = state == "error" ? Color.red.opacity(0.95) : Color(argb: accentRaw)
    return RiverWidgetEntry(
      date: Date(),
      state: state,
      feedName: feedName,
      feedLabel: feedLabel,
      title: title,
      excerpt: excerpt,
      meta: meta,
      replies: replies,
      views: views,
      topicId: topicId,
      accent: accent
    )
  }
}

struct RiverHomeWidgetEntryView: View {
  let entry: RiverWidgetEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(hex: 0xFF162843),
          Color(hex: 0xFF101B2F),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      VStack(alignment: .leading, spacing: 10) {
        header
        titleText
        if family != .systemSmall {
          excerptText
        }
        footer
      }
      .padding(family == .systemLarge ? 18 : 14)
    }
    .widgetURL(launchURL())
    .modifier(RiverWidgetBackgroundModifier())
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .fill(entry.accent)
        .frame(width: family == .systemSmall ? 32 : 42, height: 4)
      Text(entry.feedLabel)
        .font(.caption.weight(.semibold))
        .foregroundStyle(entry.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
          Capsule(style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay(
              Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
        )
      Spacer(minLength: 6)
      Text(entry.meta)
        .font(.caption2)
        .foregroundStyle(Color.white.opacity(0.72))
        .lineLimit(1)
    }
  }

  private var titleText: some View {
    Text(entry.title)
      .font(titleFont)
      .foregroundStyle(.white.opacity(0.95))
      .lineLimit(family == .systemSmall ? 4 : 2)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var excerptText: some View {
    Text(entry.excerpt)
      .font(.footnote)
      .foregroundStyle(Color.white.opacity(0.8))
      .lineLimit(family == .systemLarge ? 4 : 3)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var footer: some View {
    HStack(spacing: 10) {
      metric(text: "回复 \(entry.replies)")
      if family != .systemSmall {
        metric(text: "浏览 \(entry.views)")
      }
      Spacer(minLength: 6)
      if entry.state == "error" {
        Text("同步失败")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(Color.red.opacity(0.92))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func metric(text: String) -> some View {
    Text(text)
      .font(.caption2)
      .foregroundStyle(Color.white.opacity(0.78))
  }

  private var titleFont: Font {
    switch family {
    case .systemSmall:
      return .system(size: 16, weight: .bold, design: .rounded)
    case .systemLarge:
      return .system(size: 20, weight: .bold, design: .rounded)
    default:
      return .system(size: 18, weight: .bold, design: .rounded)
    }
  }

  private func launchURL() -> URL? {
    if entry.topicId > 0 {
      return URL(string: "river://widget/topic/\(entry.topicId)?feed=\(entry.feedName)&homeWidget=1")
    }
    return URL(string: "river://widget/feed/\(entry.feedName)?homeWidget=1")
  }
}

@main
struct RiverHomeWidget: Widget {
  let kind = "RiverHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: RiverWidgetProvider()) { entry in
      RiverHomeWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("聚河畔")
    .description("查看最新发表、最新回复或热门帖子")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

private struct RiverWidgetBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(for: .widget) {
        Color.clear
      }
    } else {
      content
    }
  }
}

private extension Color {
  init(argb: Int) {
    let a = Double((argb >> 24) & 0xFF) / 255.0
    let r = Double((argb >> 16) & 0xFF) / 255.0
    let g = Double((argb >> 8) & 0xFF) / 255.0
    let b = Double(argb & 0xFF) / 255.0
    self = Color(.sRGB, red: r, green: g, blue: b, opacity: a <= 0 ? 1 : a)
  }

  init(hex: Int) {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >> 8) & 0xFF) / 255.0
    let b = Double(hex & 0xFF) / 255.0
    self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
  }
}
