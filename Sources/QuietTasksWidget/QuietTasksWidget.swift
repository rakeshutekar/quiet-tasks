import SwiftUI
import WidgetKit

struct TaskItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var deadline: Date?
    var done: Bool
    var createdAt: Date
    var notes: String?
    var priority: TaskPriority?
    var updatedAt: Date?
    var completedAt: Date?

    var taskPriority: TaskPriority {
        priority ?? .normal
    }
}

enum TaskPriority: String, CaseIterable, Codable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }

    var rank: Int {
        switch self {
        case .high: 0
        case .normal: 1
        case .low: 2
        }
    }

    var symbol: String {
        switch self {
        case .low: "arrow.down"
        case .normal: "equal"
        case .high: "exclamationmark"
        }
    }
}

enum TaskStore {
    static var fileURL: URL {
        sharedDirectory.appendingPathComponent("tasks.json")
    }

    private static var sharedDirectory: URL {
        let directory = URL(fileURLWithPath: "/Users/Shared/QuietTasks", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func load() -> [TaskItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.taskDecoder.decode([TaskItem].self, from: data)) ?? []
    }
}

extension JSONDecoder {
    static var taskDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct QuietEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> QuietEntry {
        QuietEntry(date: Date(), tasks: [
            TaskItem(id: "1", title: "Plan sprint review", deadline: Date(), done: false, createdAt: Date(), notes: nil, priority: .high, updatedAt: nil, completedAt: nil),
            TaskItem(id: "2", title: "Send design notes", deadline: nil, done: false, createdAt: Date(), notes: nil, priority: .normal, updatedAt: nil, completedAt: nil)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (QuietEntry) -> Void) {
        completion(QuietEntry(date: Date(), tasks: TaskStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuietEntry>) -> Void) {
        let entry = QuietEntry(date: Date(), tasks: TaskStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30))))
    }
}

struct QuietTasksWidgetView: View {
    var entry: QuietEntry
    @Environment(\.widgetFamily) private var family

    private var openTasks: [TaskItem] {
        entry.tasks.filter { !$0.done }.sorted { lhs, rhs in
            if lhs.taskPriority.rank != rhs.taskPriority.rank { return lhs.taskPriority.rank < rhs.taskPriority.rank }
            switch (lhs.deadline, rhs.deadline) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    private var displayCompletedCount: Int {
        openTasks.isEmpty ? 0 : entry.tasks.filter(\.done).count
    }

    private var displayTotalCount: Int {
        openTasks.isEmpty ? 0 : entry.tasks.count
    }

    private var progress: Double {
        guard displayTotalCount > 0 else { return 0 }
        return Double(displayCompletedCount) / Double(displayTotalCount)
    }

    var body: some View {
        switch family {
        case .systemSmall:
            widgetContent(taskLimit: 2, compact: true)
        case .systemLarge:
            widgetContent(taskLimit: 7, compact: false)
        default:
            widgetContent(taskLimit: 4, compact: false)
        }
    }

    private func widgetContent(taskLimit: Int, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            header(compact: compact)
            progressView(compact: compact)

            if openTasks.isEmpty {
                Spacer()
                Text("No open tasks")
                    .font(compact ? .caption.bold() : .headline)
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                    ForEach(Array(openTasks.prefix(taskLimit))) { task in
                        taskRow(task, compact: compact)
                    }

                    if openTasks.count > taskLimit {
                        Text("+ \(openTasks.count - taskLimit) more")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(Color(red: 0.12, green: 0.13, blue: 0.12), for: .widget)
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: compact ? 1 : 2) {
                Text(entry.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(compact ? .system(size: 9, weight: .bold) : .caption.bold())
                    .foregroundStyle(Color(red: 1.0, green: 0.28, blue: 0.36))
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text("Tasks")
                    .font(compact ? .title2.bold() : .title.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Link(destination: URL(string: "quiettasks://add")!) {
                Image(systemName: "plus")
                    .font(compact ? .headline.bold() : .title2.bold())
                    .foregroundStyle(Color(red: 0.62, green: 0.86, blue: 0.88))
                    .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                    .background(.white.opacity(0.08), in: Circle())
            }
        }
    }

    private func progressView(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 6) {
            Text("\(displayCompletedCount) / \(displayTotalCount) done")
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.62, green: 0.86, blue: 0.88))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                    Capsule()
                        .fill(Color(red: 0.62, green: 0.86, blue: 0.88))
                        .frame(width: max(5, proxy.size.width * progress))
                }
            }
            .frame(height: compact ? 5 : 6)
        }
        .padding(compact ? 9 : 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
    }

    private func taskRow(_ task: TaskItem, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 6 : 8) {
            Link(destination: completeURL(for: task)) {
                Image(systemName: "circle")
                    .font(compact ? .caption.bold() : .callout.bold())
                    .foregroundStyle(Color(red: 0.62, green: 0.86, blue: 0.88))
            }

            VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    WidgetPriorityBadge(priority: task.taskPriority, compact: compact)

                    Text(task.title)
                        .font(compact ? .caption.bold() : .headline)
                        .foregroundStyle(Color(red: 0.62, green: 0.86, blue: 0.88))
                        .lineLimit(compact ? 1 : 2)
                }

                if !compact, let deadline = task.deadline {
                    Text(deadline.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }
            }
        }
        .padding(compact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
    }

    private func completeURL(for task: TaskItem) -> URL {
        var components = URLComponents()
        components.scheme = "quiettasks"
        components.host = "complete"
        components.queryItems = [URLQueryItem(name: "id", value: task.id)]
        return components.url!
    }
}

struct WidgetPriorityBadge: View {
    var priority: TaskPriority
    var compact: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: priority.symbol)
                .font(.system(size: compact ? 7 : 8, weight: .bold))
            Text(priority.title)
                .font(.system(size: compact ? 8 : 9, weight: .bold))
        }
        .foregroundStyle(priorityColor)
        .padding(.horizontal, compact ? 5 : 6)
        .padding(.vertical, compact ? 2 : 3)
        .background(priorityColor.opacity(0.14), in: Capsule())
        .lineLimit(1)
    }

    private var priorityColor: Color {
        switch priority {
        case .high:
            Color(red: 0.98, green: 0.58, blue: 0.45)
        case .normal:
            Color(red: 0.62, green: 0.86, blue: 0.88)
        case .low:
            Color.white.opacity(0.62)
        }
    }
}

struct QuietTasksWidget: Widget {
    let kind = "QuietTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            QuietTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Quiet Tasks")
        .description("Shows open Quiet Tasks on the desktop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
