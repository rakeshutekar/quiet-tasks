import SwiftUI
import UserNotifications
import WidgetKit

struct SubtaskItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var done: Bool
    var createdAt: Date
    var updatedAt: Date?
}

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
    var subtasks: [SubtaskItem]? = nil
    var recurrence: TaskRecurrence? = nil
    var pinned: Bool? = nil

    var taskPriority: TaskPriority {
        priority ?? .normal
    }

    var taskSubtasks: [SubtaskItem] {
        subtasks ?? []
    }

    var isPinned: Bool {
        pinned ?? false
    }

    var completedSubtaskCount: Int {
        taskSubtasks.filter(\.done).count
    }

    var subtaskProgressText: String? {
        guard !taskSubtasks.isEmpty else { return nil }
        return "\(completedSubtaskCount)/\(taskSubtasks.count) subtasks"
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

enum TaskRecurrence: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    var symbol: String {
        switch self {
        case .daily: "repeat"
        case .weekly: "calendar.badge.clock"
        case .monthly: "calendar"
        }
    }

    func nextDate(after deadline: Date, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let component: Calendar.Component = switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        }

        var next = calendar.date(byAdding: component, value: 1, to: deadline) ?? now
        while next <= now {
            next = calendar.date(byAdding: component, value: 1, to: next) ?? now
        }
        return next
    }
}

enum ReminderOffset: Int, CaseIterable, Codable, Identifiable {
    case atDeadline = 0
    case fifteenMinutes = 900
    case oneHour = 3600
    case oneDay = 86400

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .atDeadline: "At deadline"
        case .fifteenMinutes: "15 min before"
        case .oneHour: "1 hour before"
        case .oneDay: "1 day before"
        }
    }

    func fireDate(for deadline: Date) -> Date {
        deadline.addingTimeInterval(-TimeInterval(rawValue))
    }
}

struct NotificationSettings: Codable, Equatable {
    var enabled: Bool
    var reminderOffsets: [ReminderOffset]

    static let `default` = NotificationSettings(enabled: false, reminderOffsets: [.oneHour])
}

enum SharedFiles {
    static var directory: URL {
        let directory = URL(fileURLWithPath: "/Users/Shared/QuietTasks", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum TaskStore {
    static var fileURL: URL {
        SharedFiles.directory.appendingPathComponent("tasks.json")
    }

    private static var legacyFileURLs: [URL] {
        let username = NSUserName()
        let realHome = URL(fileURLWithPath: NSHomeDirectoryForUser(username) ?? "/Users/\(username)", isDirectory: true)
        return [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/QuietTasks/tasks.json"),
            realHome
                .appendingPathComponent("Library/Application Support/QuietTasks/tasks.json"),
            realHome
                .appendingPathComponent("Library/Group Containers/group.com.rakeshutekar.quiettasksnative/QuietTasks/tasks.json")
        ].filter { $0 != fileURL }
    }

    static func load() -> [TaskItem] {
        let primaryTasks = decode(fileURL)
        if let tasks = primaryTasks, !tasks.isEmpty {
            return normalized(tasks)
        }

        if let legacyTasks = legacyFileURLs.compactMap(decode).first(where: { !$0.isEmpty }) {
            let tasks = normalized(legacyTasks)
            save(tasks)
            return tasks
        }

        return normalized(primaryTasks ?? [])
    }

    static func save(_ tasks: [TaskItem]) {
        guard let data = try? JSONEncoder.taskEncoder.encode(tasks) else { return }
        try? FileManager.default.createDirectory(at: SharedFiles.directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func decode(_ url: URL) -> [TaskItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.taskDecoder.decode([TaskItem].self, from: data)
    }

    static func normalized(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.done != rhs.done { return !lhs.done }
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.taskPriority.rank != rhs.taskPriority.rank { return lhs.taskPriority.rank < rhs.taskPriority.rank }
            switch (lhs.deadline, rhs.deadline) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

enum SettingsStore {
    static var fileURL: URL {
        SharedFiles.directory.appendingPathComponent("settings.json")
    }

    static func load() -> NotificationSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder.taskDecoder.decode(NotificationSettings.self, from: data)
        else {
            return .default
        }
        return settings.reminderOffsets.isEmpty && settings.enabled
            ? NotificationSettings(enabled: settings.enabled, reminderOffsets: [.oneHour])
            : settings
    }

    static func save(_ settings: NotificationSettings) {
        guard let data = try? JSONEncoder.taskEncoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(at: SharedFiles.directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum NotificationScheduler {
    private static let identifierPrefix = "quiettasks.deadline."

    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    static func sync(tasks: [TaskItem], settings: NotificationSettings) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let existingIdentifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: existingIdentifiers)

            guard settings.enabled else { return }

            for task in tasks where !task.done {
                guard let deadline = task.deadline else { continue }

                for offset in settings.reminderOffsets {
                    let fireDate = offset.fireDate(for: deadline)
                    guard fireDate > Date().addingTimeInterval(5) else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = task.title
                    content.body = offset == .atDeadline ? "Due now" : "Due \(offset.title.lowercased())"
                    content.sound = .default

                    let components = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: fireDate
                    )
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let request = UNNotificationRequest(
                        identifier: "\(identifierPrefix)\(task.id).\(offset.rawValue)",
                        content: content,
                        trigger: trigger
                    )
                    center.add(request)
                }
            }
        }
    }
}

extension JSONDecoder {
    static var taskDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var taskEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case open
    case today
    case all
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .today: "Today"
        case .all: "All Tasks"
        case .done: "Done"
        }
    }

    var symbol: String {
        switch self {
        case .open: "tray"
        case .today: "calendar"
        case .all: "list.bullet"
        case .done: "checkmark.circle"
        }
    }
}

final class TaskModel: ObservableObject {
    @Published private(set) var tasks: [TaskItem]
    @Published private(set) var notificationSettings: NotificationSettings

    init() {
        tasks = TaskStore.load()
        notificationSettings = SettingsStore.load()
        NotificationScheduler.sync(tasks: tasks, settings: notificationSettings)
    }

    var openTasks: [TaskItem] {
        tasks.filter { !$0.done }
    }

    var completedCount: Int {
        tasks.filter(\.done).count
    }

    var progress: Double {
        guard displayTotalCount > 0 else { return 0 }
        return Double(displayCompletedCount) / Double(displayTotalCount)
    }

    var displayCompletedCount: Int {
        openTasks.isEmpty ? 0 : completedCount
    }

    var displayTotalCount: Int {
        openTasks.isEmpty ? 0 : tasks.count
    }

    func reload() {
        tasks = TaskStore.load()
        notificationSettings = SettingsStore.load()
        NotificationScheduler.sync(tasks: tasks, settings: notificationSettings)
    }

    func add(
        title: String,
        notes: String = "",
        deadline: Date?,
        priority: TaskPriority,
        recurrence: TaskRecurrence?,
        pinned: Bool
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks.insert(TaskItem(
            id: UUID().uuidString,
            title: trimmed,
            deadline: deadline,
            done: false,
            createdAt: Date(),
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            priority: priority,
            updatedAt: nil,
            completedAt: nil,
            subtasks: nil,
            recurrence: deadline == nil ? nil : recurrence,
            pinned: pinned ? true : nil
        ), at: 0)
        persist()
    }

    func update(
        _ task: TaskItem,
        title: String,
        notes: String,
        deadline: Date?,
        priority: TaskPriority,
        subtasks: [SubtaskItem],
        recurrence: TaskRecurrence?,
        pinned: Bool
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks = tasks.map { item in
            guard item.id == task.id else { return item }
            var updated = item
            updated.title = trimmed
            updated.notes = cleanNotes.isEmpty ? nil : cleanNotes
            updated.deadline = deadline
            updated.priority = priority
            updated.subtasks = subtasks.isEmpty ? nil : subtasks
            updated.recurrence = deadline == nil ? nil : recurrence
            updated.pinned = pinned ? true : nil
            updated.updatedAt = Date()
            return updated
        }
        persist()
    }

    func markDone(_ task: TaskItem) {
        tasks = tasks.map { item in
            guard item.id == task.id else { return item }
            var updated = item
            if let recurrence = item.recurrence, let deadline = item.deadline {
                updated.deadline = recurrence.nextDate(after: deadline)
                updated.subtasks = item.taskSubtasks.map { subtask in
                    var reset = subtask
                    reset.done = false
                    reset.updatedAt = Date()
                    return reset
                }
                updated.updatedAt = Date()
                return updated
            }
            updated.done = true
            updated.completedAt = Date()
            updated.updatedAt = Date()
            updated.subtasks = item.taskSubtasks.map { subtask in
                var completed = subtask
                completed.done = true
                completed.updatedAt = Date()
                return completed
            }
            return updated
        }
        persist()
    }

    func restore(_ task: TaskItem) {
        tasks = tasks.map { item in
            guard item.id == task.id else { return item }
            var updated = item
            updated.done = false
            updated.completedAt = nil
            updated.updatedAt = Date()
            return updated
        }
        persist()
    }

    func delete(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        persist()
    }

    func togglePinned(_ task: TaskItem) {
        tasks = tasks.map { item in
            guard item.id == task.id else { return item }
            var updated = item
            updated.pinned = item.isPinned ? nil : true
            updated.updatedAt = Date()
            return updated
        }
        persist()
    }

    func toggleSubtask(taskID: String, subtaskID: String) {
        tasks = tasks.map { item in
            guard item.id == taskID else { return item }
            var updated = item
            updated.subtasks = item.taskSubtasks.map { subtask in
                guard subtask.id == subtaskID else { return subtask }
                var changed = subtask
                changed.done.toggle()
                changed.updatedAt = Date()
                return changed
            }
            updated.updatedAt = Date()
            return updated
        }
        persist()
    }

    func updateNotificationSettings(_ settings: NotificationSettings) {
        if settings.enabled {
            NotificationScheduler.requestAuthorization { [weak self] granted in
                guard let self else { return }
                let savedSettings = NotificationSettings(
                    enabled: granted,
                    reminderOffsets: settings.reminderOffsets.isEmpty ? [.oneHour] : settings.reminderOffsets
                )
                self.notificationSettings = savedSettings
                SettingsStore.save(savedSettings)
                NotificationScheduler.sync(tasks: self.tasks, settings: savedSettings)
            }
        } else {
            notificationSettings = settings
            SettingsStore.save(settings)
            NotificationScheduler.sync(tasks: tasks, settings: settings)
        }
    }

    func tasks(for filter: TaskFilter, search: String) -> [TaskItem] {
        let calendar = Calendar.current
        let searched = tasks.filter { task in
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return task.title.localizedCaseInsensitiveContains(query)
                || (task.notes?.localizedCaseInsensitiveContains(query) ?? false)
        }

        switch filter {
        case .open:
            return searched.filter { !$0.done }
        case .today:
            return searched.filter { task in
                guard !task.done else { return false }
                guard let deadline = task.deadline else { return false }
                return calendar.isDateInToday(deadline)
            }
        case .all:
            return searched
        case .done:
            return searched.filter(\.done)
        }
    }

    private func persist() {
        tasks = TaskStore.normalized(tasks)
        TaskStore.save(tasks)
        NotificationScheduler.sync(tasks: tasks, settings: notificationSettings)
    }
}

struct TaskDraft: Identifiable {
    var id = UUID()
    var task: TaskItem?
    var title: String
    var notes: String
    var hasDeadline: Bool
    var deadline: Date
    var priority: TaskPriority
    var subtasks: [SubtaskItem]
    var recurrence: TaskRecurrence?
    var pinned: Bool

    init(task: TaskItem? = nil) {
        self.task = task
        title = task?.title ?? ""
        notes = task?.notes ?? ""
        hasDeadline = task?.deadline != nil
        deadline = task?.deadline ?? Date()
        priority = task?.taskPriority ?? .normal
        subtasks = task?.taskSubtasks ?? []
        recurrence = task?.recurrence
        pinned = task?.isPinned ?? false
    }
}

struct ContentView: View {
    @StateObject private var model = TaskModel()
    @State private var selectedFilter: TaskFilter = .open
    @State private var search = ""
    @State private var newTitle = ""
    @State private var newDeadline = Date()
    @State private var newHasDeadline = false
    @State private var newPriority: TaskPriority = .normal
    @State private var newRecurrence: TaskRecurrence?
    @State private var newPinned = false
    @State private var pendingCompletion: TaskItem?
    @State private var pendingDeletion: TaskItem?
    @State private var editingDraft: TaskDraft?
    @State private var showingNotificationSettings = false
    @FocusState private var newTaskFocused: Bool

    var visibleTasks: [TaskItem] {
        model.tasks(for: selectedFilter, search: search)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedFilter) {
                Section("Views") {
                    ForEach(TaskFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.symbol)
                            .tag(filter)
                    }
                }

                Section("Progress") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(model.displayCompletedCount) / \(model.displayTotalCount) done")
                            .font(.headline)
                        ProgressView(value: model.progress)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Quiet Tasks")
            .frame(minWidth: 220)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 26)
                    .padding(.bottom, 18)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        addComposer

                        if visibleTasks.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity)
                                .padding(.top, 90)
                        } else {
                            taskList
                        }
                    }
                    .padding(28)
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search tasks")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    selectedFilter = .open
                    newTaskFocused = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                Button {
                    model.reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    showingNotificationSettings = true
                } label: {
                    Label("Notifications", systemImage: model.notificationSettings.enabled ? "bell.badge" : "bell")
                }
            }
        }
        .onOpenURL(perform: handleURL)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
        .alert("Complete task?", isPresented: Binding(
            get: { pendingCompletion != nil },
            set: { if !$0 { pendingCompletion = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingCompletion = nil
            }
            Button("Complete") {
                if let task = pendingCompletion {
                    model.markDone(task)
                }
                pendingCompletion = nil
            }
        } message: {
            Text(pendingCompletion?.title ?? "")
        }
        .alert("Delete task?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                if let task = pendingDeletion {
                    model.delete(task)
                }
                pendingDeletion = nil
            }
        } message: {
            Text(pendingDeletion?.title ?? "")
        }
        .sheet(item: $editingDraft) { draft in
            TaskEditSheet(draft: draft) { updatedDraft in
                guard let task = updatedDraft.task else { return }
                model.update(
                    task,
                    title: updatedDraft.title,
                    notes: updatedDraft.notes,
                    deadline: updatedDraft.hasDeadline ? updatedDraft.deadline : nil,
                    priority: updatedDraft.priority,
                    subtasks: updatedDraft.subtasks,
                    recurrence: updatedDraft.hasDeadline ? updatedDraft.recurrence : nil,
                    pinned: updatedDraft.pinned
                )
                editingDraft = nil
            } onCancel: {
                editingDraft = nil
            }
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NotificationSettingsSheet(settings: model.notificationSettings) { settings in
                model.updateNotificationSettings(settings)
                showingNotificationSettings = false
            } onCancel: {
                showingNotificationSettings = false
            }
        }
        .frame(minWidth: 880, minHeight: 620)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedFilter.title)
                    .font(.largeTitle.bold())
                Text(summaryText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressRing(progress: model.progress)
                .frame(width: 54, height: 54)
        }
    }

    private var summaryText: String {
        if model.tasks.isEmpty { return "No tasks yet" }
        if model.openTasks.isEmpty { return "All clear" }
        return "\(model.openTasks.count) open, \(model.completedCount) done"
    }

    private var addComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Add a task", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($newTaskFocused)
                    .onSubmit(addTask)

                Button(action: addTask) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    DueDateControl(isEnabled: $newHasDeadline, date: $newDeadline)
                        .frame(minWidth: 210, alignment: .leading)
                    PriorityPicker(priority: $newPriority)
                }

                HStack(spacing: 18) {
                    RecurrencePicker(recurrence: $newRecurrence, isEnabled: newHasDeadline)
                    PinToggle(isPinned: $newPinned)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var taskList: some View {
        LazyVStack(spacing: 10) {
            ForEach(visibleTasks) { task in
                TaskRow(
                    task: task,
                    onComplete: { pendingCompletion = task },
                    onRestore: { model.restore(task) },
                    onEdit: { editingDraft = TaskDraft(task: task) },
                    onDelete: { pendingDeletion = task },
                    onTogglePinned: { model.togglePinned(task) },
                    onToggleSubtask: { subtask in
                        model.toggleSubtask(taskID: task.id, subtaskID: subtask.id)
                    }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedFilter == .done ? "arrow.uturn.backward.circle" : "checkmark.circle")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(selectedFilter == .done ? "No completed tasks" : "No tasks here")
                .font(.title3.bold())
                .foregroundStyle(.secondary)
        }
    }

    private func addTask() {
        model.add(
            title: newTitle,
            deadline: newHasDeadline ? newDeadline : nil,
            priority: newPriority,
            recurrence: newHasDeadline ? newRecurrence : nil,
            pinned: newPinned
        )
        newTitle = ""
        newHasDeadline = false
        newPriority = .normal
        newRecurrence = nil
        newPinned = false
        selectedFilter = .open
        newTaskFocused = true
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "quiettasks" else { return }

        switch url.host {
        case "add":
            selectedFilter = .open
            newTaskFocused = true
        case "complete":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "id" }?
                .value
            model.reload()
            pendingCompletion = model.tasks.first { $0.id == id && !$0.done }
        case "subtask":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let taskID = components?
                .queryItems?
                .first { $0.name == "task" }?
                .value
            let subtaskID = components?
                .queryItems?
                .first { $0.name == "subtask" }?
                .value
            if let taskID, let subtaskID {
                model.toggleSubtask(taskID: taskID, subtaskID: subtaskID)
            }
        default:
            break
        }
    }
}

struct TaskRow: View {
    var task: TaskItem
    var onComplete: () -> Void
    var onRestore: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onTogglePinned: () -> Void
    var onToggleSubtask: (SubtaskItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: task.done ? onRestore : onComplete) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? .green : Color(red: 0.62, green: 0.86, blue: 0.88))
            }
            .buttonStyle(.plain)
            .help(task.done ? "Restore" : "Complete")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if task.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color(red: 0.62, green: 0.86, blue: 0.88))
                    }

                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? .secondary : .primary)
                }

                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    PriorityBadge(priority: task.taskPriority)
                    if let deadline = task.deadline {
                        Label(deadline.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }
                    if let recurrence = task.recurrence {
                        Label(recurrence.title, systemImage: recurrence.symbol)
                    }
                    if let subtaskProgressText = task.subtaskProgressText {
                        Label(subtaskProgressText, systemImage: "checklist")
                    }
                    Label(task.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "plus.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !task.taskSubtasks.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(task.taskSubtasks) { subtask in
                            Button {
                                onToggleSubtask(subtask)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: subtask.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(subtask.done ? .green : Color(red: 0.62, green: 0.86, blue: 0.88))
                                    Text(subtask.title)
                                        .strikethrough(subtask.done)
                                        .foregroundStyle(subtask.done ? .secondary : .primary)
                                        .lineLimit(1)
                                }
                                .font(.callout)
                            }
                            .buttonStyle(.plain)
                            .help(subtask.done ? "Restore subtask" : "Complete subtask")
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Button(action: onTogglePinned) {
                    Image(systemName: task.isPinned ? "pin.fill" : "pin")
                }
                .help(task.isPinned ? "Unpin" : "Pin")

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .help("Edit")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct TaskEditSheet: View {
    @State var draft: TaskDraft
    @State private var newSubtaskTitle = ""
    var onSave: (TaskDraft) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Task")
                .font(.title.bold())

            TextField("Task", text: $draft.title)
                .textFieldStyle(.roundedBorder)

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            VStack(alignment: .leading, spacing: 14) {
                DueDateControl(isEnabled: $draft.hasDeadline, date: $draft.deadline)
                PriorityPicker(priority: $draft.priority)
                RecurrencePicker(recurrence: $draft.recurrence, isEnabled: draft.hasDeadline)
                PinToggle(isPinned: $draft.pinned)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Subtasks", systemImage: "checklist")
                    .font(.headline)

                ForEach($draft.subtasks) { $subtask in
                    HStack(spacing: 8) {
                        Toggle("", isOn: $subtask.done)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        TextField("Subtask", text: $subtask.title)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            draft.subtasks.removeAll { $0.id == subtask.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete subtask")
                    }
                }

                HStack(spacing: 8) {
                    TextField("Add subtask", text: $newSubtaskTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addSubtask)
                    Button(action: addSubtask) {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    saveDraft()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft.subtasks.append(SubtaskItem(
            id: UUID().uuidString,
            title: trimmed,
            done: false,
            createdAt: Date(),
            updatedAt: nil
        ))
        newSubtaskTitle = ""
    }

    private func saveDraft() {
        draft.subtasks = draft.subtasks.compactMap { subtask in
            let trimmed = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var cleaned = subtask
            cleaned.title = trimmed
            cleaned.updatedAt = Date()
            return cleaned
        }
        if !draft.hasDeadline {
            draft.recurrence = nil
        }
        onSave(draft)
    }
}

struct DueDateControl: View {
    @Binding var isEnabled: Bool
    @Binding var date: Date
    @State private var showingPopover = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Deadline", isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .fixedSize()

            if isEnabled {
                Button {
                    showingPopover.toggle()
                } label: {
                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                    deadlinePopover
                }

                Button {
                    isEnabled = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear deadline")
            } else {
                Button {
                    isEnabled = true
                    date = Date()
                    showingPopover = true
                } label: {
                    Label("Set date", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var deadlinePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Deadline")
                .font(.headline)

            DatePicker("Date", selection: $date, displayedComponents: .date)
            DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)

            Divider()

            HStack(spacing: 8) {
                Button("Today") {
                    date = Date()
                    isEnabled = true
                }
                Button("Tomorrow") {
                    date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    isEnabled = true
                }
                Button("Next Week") {
                    date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                    isEnabled = true
                }
            }

            HStack {
                Button("Clear") {
                    isEnabled = false
                    showingPopover = false
                }
                Spacer()
                Button("Done") {
                    showingPopover = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct PriorityPicker: View {
    @Binding var priority: TaskPriority

    var body: some View {
        HStack(spacing: 8) {
            Label("Priority", systemImage: "flag")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            Picker("", selection: $priority) {
                ForEach(TaskPriority.allCases) { priority in
                    Text(priority.title)
                        .tag(priority)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190)
        }
        .frame(minWidth: 280, alignment: .leading)
    }
}

struct RecurrencePicker: View {
    @Binding var recurrence: TaskRecurrence?
    var isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label("Repeats", systemImage: "repeat")
                .foregroundStyle(isEnabled ? .secondary : .tertiary)
                .lineLimit(1)
                .fixedSize()

            Picker("", selection: $recurrence) {
                Text("None").tag(TaskRecurrence?.none)
                ForEach(TaskRecurrence.allCases) { recurrence in
                    Text(recurrence.title)
                        .tag(Optional(recurrence))
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 240)
            .disabled(!isEnabled)
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    recurrence = nil
                }
            }
        }
        .frame(minWidth: 330, alignment: .leading)
    }
}

struct PinToggle: View {
    @Binding var isPinned: Bool

    var body: some View {
        Toggle(isOn: $isPinned) {
            Label("Pin", systemImage: isPinned ? "pin.fill" : "pin")
        }
        .toggleStyle(.checkbox)
    }
}

struct NotificationSettingsSheet: View {
    @State private var draft: NotificationSettings
    var onSave: (NotificationSettings) -> Void
    var onCancel: () -> Void

    init(
        settings: NotificationSettings,
        onSave: @escaping (NotificationSettings) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: settings)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Notifications")
                .font(.title.bold())

            Toggle("Notifications", isOn: $draft.enabled)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 10) {
                Text("Default reminders")
                    .font(.headline)

                ForEach(ReminderOffset.allCases) { offset in
                    Toggle(offset.title, isOn: reminderBinding(for: offset))
                        .toggleStyle(.checkbox)
                        .disabled(!draft.enabled)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if draft.enabled && draft.reminderOffsets.isEmpty {
                        draft.reminderOffsets = [.oneHour]
                    }
                    draft.reminderOffsets.sort { $0.rawValue < $1.rawValue }
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func reminderBinding(for offset: ReminderOffset) -> Binding<Bool> {
        Binding(
            get: {
                draft.reminderOffsets.contains(offset)
            },
            set: { enabled in
                if enabled {
                    if !draft.reminderOffsets.contains(offset) {
                        draft.reminderOffsets.append(offset)
                    }
                } else {
                    draft.reminderOffsets.removeAll { $0 == offset }
                }
            }
        )
    }
}

struct PriorityBadge: View {
    var priority: TaskPriority

    var body: some View {
        Label(priority.title, systemImage: priority.symbol)
            .font(.caption.bold())
            .foregroundStyle(priority == .high ? Color(red: 0.95, green: 0.54, blue: 0.42) : .secondary)
    }
}

struct ProgressRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color(red: 0.62, green: 0.86, blue: 0.88), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.caption.bold())
                .monospacedDigit()
        }
    }
}

@main
struct QuietTasksApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
