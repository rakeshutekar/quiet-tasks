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
        try? FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func decode(_ url: URL) -> [TaskItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.taskDecoder.decode([TaskItem].self, from: data)
    }

    private static func normalized(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.done != rhs.done { return !lhs.done }
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
    @Published private(set) var tasks: [TaskItem] = TaskStore.load()

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
    }

    func add(title: String, notes: String = "", deadline: Date?, priority: TaskPriority) {
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
            completedAt: nil
        ), at: 0)
        persist()
    }

    func update(_ task: TaskItem, title: String, notes: String, deadline: Date?, priority: TaskPriority) {
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
            updated.updatedAt = Date()
            return updated
        }
        persist()
    }

    func markDone(_ task: TaskItem) {
        tasks = tasks.map { item in
            guard item.id == task.id else { return item }
            var updated = item
            updated.done = true
            updated.completedAt = Date()
            updated.updatedAt = Date()
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
        TaskStore.save(tasks)
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

    init(task: TaskItem? = nil) {
        self.task = task
        title = task?.title ?? ""
        notes = task?.notes ?? ""
        hasDeadline = task?.deadline != nil
        deadline = task?.deadline ?? Date()
        priority = task?.taskPriority ?? .normal
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
    @State private var pendingCompletion: TaskItem?
    @State private var pendingDeletion: TaskItem?
    @State private var editingDraft: TaskDraft?
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
                    priority: updatedDraft.priority
                )
                editingDraft = nil
            } onCancel: {
                editingDraft = nil
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

            HStack(spacing: 18) {
                DueDateControl(isEnabled: $newHasDeadline, date: $newDeadline)
                PriorityPicker(priority: $newPriority)
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
                    onDelete: { pendingDeletion = task }
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
        model.add(title: newTitle, deadline: newHasDeadline ? newDeadline : nil, priority: newPriority)
        newTitle = ""
        newHasDeadline = false
        newPriority = .normal
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
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? .secondary : .primary)

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
                    Label(task.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "plus.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
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
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
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
