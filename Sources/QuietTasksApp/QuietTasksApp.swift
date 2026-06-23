import AppKit
import AuthenticationServices
import CryptoKit
import Darwin
import Foundation
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
    var source: TaskSource? = nil
    var externalID: String? = nil
    var externalListID: String? = nil
    var externalUpdatedAt: Date? = nil
    var deadlineHasTime: Bool? = nil

    var taskPriority: TaskPriority {
        priority ?? .normal
    }

    var taskSubtasks: [SubtaskItem] {
        subtasks ?? []
    }

    var isPinned: Bool {
        pinned ?? false
    }

    var isGoogleTask: Bool {
        source == .google
    }

    var showsDeadlineTime: Bool {
        deadlineHasTime ?? true
    }

    var completedSubtaskCount: Int {
        taskSubtasks.filter(\.done).count
    }

    var localRevisionDate: Date {
        updatedAt ?? completedAt ?? createdAt
    }

    var subtaskProgressText: String? {
        guard !taskSubtasks.isEmpty else { return nil }
        return "\(completedSubtaskCount)/\(taskSubtasks.count) subtasks"
    }
}

enum TaskSource: String, Codable, Equatable {
    case google
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

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct GoogleSyncSettings: Codable, Equatable {
    static let defaultClientID = "820308341063-g3mm94f5jmt5vnepdd0qk329650k8612.apps.googleusercontent.com"

    var clientID: String
    var isConnected: Bool
    var selectedTaskListID: String?
    var selectedTaskListTitle: String?
    var lastSyncedAt: Date?

    static let `default` = GoogleSyncSettings(
        clientID: defaultClientID,
        isConnected: false,
        selectedTaskListID: nil,
        selectedTaskListTitle: nil,
        lastSyncedAt: nil
    )

    var effectiveClientID: String {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Self.defaultClientID {
            return GoogleOAuthLocalConfig.clientID ?? Self.defaultClientID
        }
        return trimmed
    }
}

struct AppSettings: Codable, Equatable {
    var notifications: NotificationSettings
    var appearance: AppearanceMode
    var googleSync: GoogleSyncSettings

    static let `default` = AppSettings(
        notifications: .default,
        appearance: .system,
        googleSync: .default
    )
}

enum SharedFiles {
    static let appGroupIdentifiers = [
        "group.ai.aifund.quiettasks",
        "group.com.rakeshutekar.quiettasksnative"
    ]

    static var directory: URL {
        if let appGroupDirectory = appGroupDirectories.first {
            return appGroupDirectory
        }

        if FileManager.default.fileExists(atPath: legacySharedDirectory.path) {
            return legacySharedDirectory
        }

        try? FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        return appSupportDirectory
    }

    static var candidateDirectories: [URL] {
        unique(appGroupDirectories + [
            legacySharedDirectory,
            appSupportDirectory,
            realHomeDirectory.appendingPathComponent("Library/Application Support/QuietTasks", isDirectory: true)
        ] + directGroupDirectories)
    }

    static var legacySharedDirectory: URL {
        URL(fileURLWithPath: "/Users/Shared/QuietTasks", isDirectory: true)
    }

    private static var appSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuietTasks", isDirectory: true)
    }

    private static var realHomeDirectory: URL {
        let username = NSUserName()
        return URL(fileURLWithPath: NSHomeDirectoryForUser(username) ?? "/Users/\(username)", isDirectory: true)
    }

    private static var appGroupDirectories: [URL] {
        appGroupIdentifiers.compactMap { identifier in
            FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
                .appendingPathComponent("QuietTasks", isDirectory: true)
        }
    }

    private static var directGroupDirectories: [URL] {
        appGroupIdentifiers.map { identifier in
            realHomeDirectory
                .appendingPathComponent("Library/Group Containers/\(identifier)/QuietTasks", isDirectory: true)
        }
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            return seen.insert(path).inserted
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum GoogleOAuthLocalConfig {
    private struct Root: Decodable {
        var installed: Installed?
    }

    private struct Installed: Decodable {
        var clientID: String
        var clientSecret: String?

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case clientSecret = "client_secret"
        }
    }

    static var fileURL: URL {
        SharedFiles.directory.appendingPathComponent("google-oauth.json")
    }

    static var clientID: String? {
        installed?.clientID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func clientSecret(for clientID: String) -> String? {
        guard let installed,
              installed.clientID == clientID
        else {
            return nil
        }
        return installed.clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static var installed: Installed? {
        let urls = SharedFiles.candidateDirectories.map {
            $0.appendingPathComponent("google-oauth.json")
        }

        guard let data = urls.compactMap({ try? Data(contentsOf: $0) }).first,
              let root = try? JSONDecoder().decode(Root.self, from: data)
        else {
            return nil
        }
        return root.installed
    }
}

enum TaskStore {
    static var fileURL: URL {
        SharedFiles.directory.appendingPathComponent("tasks.json")
    }

    private struct StoredTasks {
        var url: URL
        var tasks: [TaskItem]
        var modifiedAt: Date
    }

    private static var fileURLs: [URL] {
        SharedFiles.candidateDirectories.map {
            $0.appendingPathComponent("tasks.json")
        }
    }

    static func load() -> [TaskItem] {
        let storedTasks = fileURLs.compactMap(readStoredTasks)
        if let primaryStore = storedTasks.first(where: { $0.url.standardizedFileURL == fileURL.standardizedFileURL }) {
            if !primaryStore.tasks.isEmpty {
                let tasks = normalized(mergedTasks(base: primaryStore, stores: storedTasks))
                write(tasks, reloadWidgets: false)
                return tasks
            }

            let freshestNonEmptyStore = storedTasks
                .filter { !$0.tasks.isEmpty }
                .max(by: { $0.modifiedAt < $1.modifiedAt })
            if freshestNonEmptyStore == nil || primaryStore.modifiedAt >= (freshestNonEmptyStore?.modifiedAt ?? .distantPast) {
                write([], reloadWidgets: false)
                return []
            }
        }

        guard let freshestStore = storedTasks
            .filter({ !$0.tasks.isEmpty })
            .max(by: { $0.modifiedAt < $1.modifiedAt })
        else {
            return normalized(storedTasks.first?.tasks ?? [])
        }

        let tasks = normalized(freshestStore.tasks)
        write(tasks, reloadWidgets: false)
        return tasks
    }

    static func save(_ tasks: [TaskItem]) {
        write(normalized(tasks), reloadWidgets: true)
    }

    private static func write(_ tasks: [TaskItem], reloadWidgets: Bool) {
        guard let data = try? JSONEncoder.taskEncoder.encode(tasks) else { return }
        for directory in SharedFiles.candidateDirectories {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appendingPathComponent("tasks.json"), options: .atomic)
        }
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func readStoredTasks(_ url: URL) -> StoredTasks? {
        guard let tasks = decode(url) else { return nil }
        return StoredTasks(url: url, tasks: tasks, modifiedAt: modifiedAt(url))
    }

    private static func mergedTasks(base: StoredTasks, stores: [StoredTasks]) -> [TaskItem] {
        var tasksByID = Dictionary(uniqueKeysWithValues: base.tasks.map { ($0.id, $0) })

        for store in stores where store.url.standardizedFileURL != base.url.standardizedFileURL {
            for task in store.tasks {
                if let currentTask = tasksByID[task.id] {
                    if task.localRevisionDate > currentTask.localRevisionDate {
                        tasksByID[task.id] = task
                    }
                } else if task.localRevisionDate >= base.modifiedAt || task.createdAt >= base.modifiedAt {
                    tasksByID[task.id] = task
                }
            }
        }

        return Array(tasksByID.values)
    }

    private static func modifiedAt(_ url: URL) -> Date {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return .distantPast
        }
        return modifiedAt
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

    private struct StoredSettings {
        var url: URL
        var settings: AppSettings
        var modifiedAt: Date
    }

    private static var fileURLs: [URL] {
        SharedFiles.candidateDirectories.map {
            $0.appendingPathComponent("settings.json")
        }
    }

    static func load() -> AppSettings {
        let storedSettings = fileURLs.compactMap(readStoredSettings)
        guard let freshestStore = storedSettings.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            return .default
        }

        let settings = normalized(freshestStore.settings)
        write(settings, reloadWidgets: false)
        return settings
    }

    static func save(_ settings: AppSettings) {
        write(normalized(settings), reloadWidgets: true)
    }

    private static func write(_ settings: AppSettings, reloadWidgets: Bool) {
        guard let data = try? JSONEncoder.taskEncoder.encode(settings) else { return }
        for directory in SharedFiles.candidateDirectories {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
        }
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func readStoredSettings(_ url: URL) -> StoredSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        if let settings = try? JSONDecoder.taskDecoder.decode(AppSettings.self, from: data) {
            return StoredSettings(url: url, settings: normalized(settings), modifiedAt: modifiedAt(url))
        }

        if let legacyNotifications = try? JSONDecoder.taskDecoder.decode(NotificationSettings.self, from: data) {
            var settings = AppSettings.default
            settings.notifications = legacyNotifications
            return StoredSettings(url: url, settings: normalized(settings), modifiedAt: modifiedAt(url))
        }

        return nil
    }

    private static func modifiedAt(_ url: URL) -> Date {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return .distantPast
        }
        return modifiedAt
    }

    private static func normalized(_ settings: AppSettings) -> AppSettings {
        var normalized = settings
        if normalized.notifications.enabled && normalized.notifications.reminderOffsets.isEmpty {
            normalized.notifications.reminderOffsets = [.oneHour]
        }
        normalized.googleSync.clientID = normalized.googleSync.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.googleSync.clientID.isEmpty {
            normalized.googleSync.clientID = GoogleSyncSettings.defaultClientID
        }
        return normalized
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

struct GoogleTaskList: Codable, Identifiable, Equatable {
    var id: String
    var title: String
}

struct GoogleTask: Codable, Identifiable {
    var id: String
    var title: String?
    var notes: String?
    var status: String?
    var due: Date?
    var updated: Date?
    var completed: Date?
    var parent: String?
}

struct GoogleTaskListResponse: Decodable {
    var items: [GoogleTaskList]?
    var nextPageToken: String?
}

struct GoogleTasksResponse: Decodable {
    var items: [GoogleTask]?
    var nextPageToken: String?
}

struct GoogleTokenResponse: Decodable {
    var accessToken: String
    var expiresIn: Int?
    var refreshToken: String?
    var tokenType: String?
}

struct GoogleAccessToken {
    var value: String
    var expiresAt: Date
}

enum GoogleSyncError: LocalizedError {
    case missingClientID
    case missingRefreshToken
    case missingTaskList
    case invalidResponse
    case oauthCancelled
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            "Add a Google OAuth client ID first."
        case .missingRefreshToken:
            "Connect Google Tasks again."
        case .missingTaskList:
            "Choose a Google task list first."
        case .invalidResponse:
            "Google returned an unexpected response."
        case .oauthCancelled:
            "Google sign-in was cancelled or timed out."
        case let .apiError(message):
            message
        }
    }
}

enum GoogleDateParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value)
    }

    static func string(from date: Date) -> String {
        standardFormatter.string(from: date)
    }
}

extension JSONDecoder {
    static var googleDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = GoogleDateParser.parse(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Google date: \(value)"
            )
        }
        return decoder
    }
}

enum GoogleTokenStore {
    private struct TokenFile: Codable {
        var refreshToken: String
    }

    private static var fileURL: URL {
        SharedFiles.directory.appendingPathComponent("google-token.json")
    }

    static func saveRefreshToken(_ token: String) throws {
        let tokenFile = TokenFile(refreshToken: token)
        guard let data = try? JSONEncoder.taskEncoder.encode(tokenFile) else {
            throw GoogleSyncError.apiError("Could not save Google token.")
        }

        do {
            try FileManager.default.createDirectory(at: SharedFiles.directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw GoogleSyncError.apiError("Could not save Google token.")
        }
    }

    static func loadRefreshToken() -> String? {
        let urls = [
            fileURL,
            SharedFiles.legacySharedDirectory.appendingPathComponent("google-token.json")
        ]
        guard let data = urls.compactMap({ try? Data(contentsOf: $0) }).first,
              let tokenFile = try? JSONDecoder.taskDecoder.decode(TokenFile.self, from: data)
        else {
            return nil
        }
        return tokenFile.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func deleteRefreshToken() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

final class OAuthLoopbackReceiver: @unchecked Sendable {
    private let path: String
    private var port: UInt16 = 0
    private var socketFileDescriptor: Int32
    private let queue = DispatchQueue(label: "QuietTasks.OAuthLoopbackReceiver")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var finished = false

    var redirectURI: String {
        "http://127.0.0.1:\(port)\(path)"
    }

    init(path: String) throws {
        self.path = path

        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw Self.socketError("Could not start the local Google sign-in server")
        }
        socketFileDescriptor = descriptor

        var reuseAddress: Int32 = 1
        _ = Darwin.setsockopt(
            socketFileDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: Darwin.inet_addr("127.0.0.1"))

        var bindAddress = address
        let bindResult = withUnsafePointer(to: &bindAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(socketFileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let error = Self.socketError("Could not bind the local Google sign-in server")
            closeSocket()
            throw error
        }

        guard Darwin.listen(socketFileDescriptor, 1) == 0 else {
            let error = Self.socketError("Could not listen for the Google sign-in callback")
            closeSocket()
            throw error
        }

        var assignedAddress = sockaddr_in()
        var assignedAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &assignedAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.getsockname(socketFileDescriptor, socketAddress, &assignedAddressLength)
            }
        }
        guard nameResult == 0 else {
            let error = Self.socketError("Could not read the local Google sign-in port")
            closeSocket()
            throw error
        }

        port = UInt16(bigEndian: assignedAddress.sin_port)
    }

    deinit {
        closeSocket()
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume(throwing: GoogleSyncError.oauthCancelled)
                return
            }
            self.continuation = continuation
            lock.unlock()

            queue.async { [weak self] in
                self?.acceptCallback()
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.complete(.failure(GoogleSyncError.oauthCancelled))
            }
        }
    }

    func cancel() {
        complete(.failure(GoogleSyncError.oauthCancelled))
    }

    private func acceptCallback() {
        while !hasFinished() {
            let descriptor = currentSocketFileDescriptor()
            guard descriptor >= 0 else { return }

            var clientAddress = sockaddr()
            var clientAddressLength = socklen_t(MemoryLayout<sockaddr>.size)
            let clientDescriptor = Darwin.accept(descriptor, &clientAddress, &clientAddressLength)
            guard clientDescriptor >= 0 else {
                if !hasFinished() {
                    complete(.failure(GoogleSyncError.oauthCancelled))
                }
                return
            }
            defer { Darwin.close(clientDescriptor) }

            guard let callbackURL = callbackURL(from: clientDescriptor) else {
                sendResponse(
                    status: "404 Not Found",
                    body: "Quiet Tasks did not recognize this Google sign-in request.",
                    to: clientDescriptor
                )
                continue
            }

            sendResponse(
                status: "200 OK",
                body: """
                <!doctype html>
                <html>
                <head>
                  <meta charset="utf-8">
                  <title>Quiet Tasks Connected</title>
                  <style>
                    body { font: 15px -apple-system, BlinkMacSystemFont, sans-serif; margin: 48px; color: #202525; }
                    h1 { font-size: 24px; margin-bottom: 8px; }
                    p { color: #5b6363; }
                  </style>
                </head>
                <body>
                  <h1>Quiet Tasks connected</h1>
                  <p>You can close this tab and return to Quiet Tasks.</p>
                </body>
                </html>
                """,
                to: clientDescriptor
            )
            complete(.success(callbackURL))
            return
        }
    }

    private func callbackURL(from clientDescriptor: Int32) -> URL? {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let byteCount = buffer.withUnsafeMutableBytes { rawBuffer in
            Darwin.recv(clientDescriptor, rawBuffer.baseAddress, rawBuffer.count, 0)
        }
        guard byteCount > 0,
              let request = String(bytes: buffer.prefix(byteCount), encoding: .utf8)
        else {
            return nil
        }

        let requestLine = request
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
        guard let requestLine else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let target = String(parts[1])
        guard target.hasPrefix("/") else { return nil }
        guard let url = URL(string: "http://127.0.0.1:\(port)\(target)"),
              url.path == path
        else {
            return nil
        }
        return url
    }

    private func sendResponse(status: String, body: String, to clientDescriptor: Int32) {
        let bodyData = Data(body.utf8)
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(bodyData)

        var bytesSent = 0
        response.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            while bytesSent < response.count {
                let sent = Darwin.send(
                    clientDescriptor,
                    baseAddress.advanced(by: bytesSent),
                    response.count - bytesSent,
                    0
                )
                guard sent > 0 else { return }
                bytesSent += sent
            }
        }
    }

    private func complete(_ result: Result<URL, Error>) {
        let continuationToResume: CheckedContinuation<URL, Error>?

        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        continuationToResume = continuation
        continuation = nil
        closeSocketLocked()
        lock.unlock()

        guard let continuationToResume else { return }
        switch result {
        case .success(let url):
            continuationToResume.resume(returning: url)
        case .failure(let error):
            continuationToResume.resume(throwing: error)
        }
    }

    private func hasFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    private func currentSocketFileDescriptor() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return socketFileDescriptor
    }

    private func closeSocket() {
        lock.lock()
        closeSocketLocked()
        lock.unlock()
    }

    private func closeSocketLocked() {
        guard socketFileDescriptor >= 0 else { return }
        _ = Darwin.shutdown(socketFileDescriptor, SHUT_RDWR)
        Darwin.close(socketFileDescriptor)
        socketFileDescriptor = -1
    }

    private static func socketError(_ message: String) -> GoogleSyncError {
        GoogleSyncError.apiError("\(message): \(String(cString: Darwin.strerror(errno))).")
    }
}

enum GoogleOAuthClient {
    static let scope = "https://www.googleapis.com/auth/tasks"
    private static let callbackPath = "/"

    static func authorize(clientID: String) async throws -> GoogleAccessToken {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else { throw GoogleSyncError.missingClientID }

        let receiver = try OAuthLoopbackReceiver(path: callbackPath)
        defer { receiver.cancel() }

        let verifier = pkceVerifier()
        let challenge = pkceChallenge(for: verifier)
        let state = pkceVerifier()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: trimmedClientID),
            URLQueryItem(name: "redirect_uri", value: receiver.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authorizationURL = components.url else { throw GoogleSyncError.invalidResponse }
        let callbackURL = try await OAuthWebAuthenticationSession.authenticate(
            url: authorizationURL,
            callbackScheme: "http"
        )
        guard let expectedRedirectURL = URL(string: receiver.redirectURI),
              callbackURL.scheme == expectedRedirectURL.scheme,
              callbackURL.host == expectedRedirectURL.host,
              callbackURL.port == expectedRedirectURL.port,
              callbackURL.path == expectedRedirectURL.path
        else {
            throw GoogleSyncError.invalidResponse
        }

        let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first(where: { $0.name == "error_description" })?.value
            throw GoogleSyncError.apiError(description ?? "Google sign-in failed: \(error)")
        }
        guard queryItems.first(where: { $0.name == "state" })?.value == state else {
            throw GoogleSyncError.invalidResponse
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value
        else {
            throw GoogleSyncError.invalidResponse
        }

        let response = try await exchangeCode(
            code,
            clientID: trimmedClientID,
            verifier: verifier,
            redirectURI: receiver.redirectURI
        )
        if let refreshToken = response.refreshToken {
            try GoogleTokenStore.saveRefreshToken(refreshToken)
        }
        return GoogleAccessToken(
            value: response.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        )
    }

    static func refreshedAccessToken(clientID: String) async throws -> GoogleAccessToken {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else { throw GoogleSyncError.missingClientID }
        guard let refreshToken = GoogleTokenStore.loadRefreshToken() else {
            throw GoogleSyncError.missingRefreshToken
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = [
            "client_id": trimmedClientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        if let clientSecret = GoogleOAuthLocalConfig.clientSecret(for: trimmedClientID) {
            body["client_secret"] = clientSecret
        }
        request.httpBody = formEncoded(body)

        let response = try await tokenResponse(for: request)
        return GoogleAccessToken(
            value: response.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        )
    }

    private static func exchangeCode(
        _ code: String,
        clientID: String,
        verifier: String,
        redirectURI: String
    ) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        if let clientSecret = GoogleOAuthLocalConfig.clientSecret(for: clientID) {
            body["client_secret"] = clientSecret
        }
        request.httpBody = formEncoded(body)
        return try await tokenResponse(for: request)
    }

    private static func tokenResponse(for request: URLRequest) async throws -> GoogleTokenResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleSyncError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GoogleSyncError.apiError(apiErrorMessage(from: data) ?? "Google sign-in failed.")
        }
        return try JSONDecoder.googleDecoder.decode(GoogleTokenResponse.self, from: data)
    }

    private static func pkceVerifier() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<64).compactMap { _ in characters.randomElement() })
    }

    private static func pkceChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncoded(_ values: [String: String]) -> Data? {
        let query = values
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
        return Data(query.utf8)
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? String
        else {
            return nil
        }
        if let description = object["error_description"] as? String {
            return "\(error): \(description)"
        }
        return error
    }
}

final class OAuthWebAuthenticationSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    static func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let webSession = OAuthWebAuthenticationSession()
        return try await webSession.authenticate(url: url, callbackScheme: callbackScheme)
    }

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                    self.session = nil

                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if error != nil {
                        continuation.resume(throwing: GoogleSyncError.oauthCancelled)
                    } else {
                        continuation.resume(throwing: GoogleSyncError.invalidResponse)
                    }
                }

                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.session = session

                guard session.start() else {
                    self.session = nil
                    continuation.resume(throwing: GoogleSyncError.apiError("Could not start Google Tasks authorization."))
                    return
                }
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }
}

enum GoogleTasksClient {
    static func fetchTaskLists(accessToken: String) async throws -> [GoogleTaskList] {
        var lists: [GoogleTaskList] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists")!
            components.queryItems = [
                URLQueryItem(name: "maxResults", value: "100")
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let response = try await googleResponse(GoogleTaskListResponse.self, for: request)
            lists.append(contentsOf: response.items ?? [])
            pageToken = response.nextPageToken
        } while pageToken != nil

        return lists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func fetchTasks(
        accessToken: String,
        taskListID: String,
        taskListTitle: String?
    ) async throws -> [TaskItem] {
        var googleTasks: [GoogleTask] = []
        var pageToken: String?

        repeat {
            let encodedListID = taskListID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskListID
            var components = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/lists/\(encodedListID)/tasks")!
            components.queryItems = [
                URLQueryItem(name: "maxResults", value: "100"),
                URLQueryItem(name: "showCompleted", value: "true"),
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "showHidden", value: "true")
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let response = try await googleResponse(GoogleTasksResponse.self, for: request)
            googleTasks.append(contentsOf: response.items ?? [])
            pageToken = response.nextPageToken
        } while pageToken != nil

        return mappedTasks(from: googleTasks, taskListID: taskListID, taskListTitle: taskListTitle)
    }

    static func setCompletion(
        accessToken: String,
        taskListID: String,
        taskID: String,
        done: Bool,
        completedAt: Date
    ) async throws -> GoogleTask {
        let encodedListID = taskListID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskListID
        let encodedTaskID = taskID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskID
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(encodedListID)/tasks/\(encodedTaskID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: googleCompletionBody(done: done, completedAt: completedAt))
        return try await googleResponse(GoogleTask.self, for: request)
    }

    private static func googleResponse<T: Decodable>(_ type: T.Type, for request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleSyncError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GoogleSyncError.apiError(apiErrorMessage(from: data) ?? "Google Tasks request failed.")
        }
        return try JSONDecoder.googleDecoder.decode(T.self, from: data)
    }

    private static func googleCompletionBody(done: Bool, completedAt: Date) -> [String: Any] {
        if done {
            return [
                "status": "completed",
                "completed": GoogleDateParser.string(from: completedAt)
            ]
        }
        return [
            "status": "needsAction",
            "completed": NSNull()
        ]
    }

    private static func mappedTasks(
        from googleTasks: [GoogleTask],
        taskListID: String,
        taskListTitle: String?
    ) -> [TaskItem] {
        let childTasks = Dictionary(grouping: googleTasks.filter { $0.parent != nil }) { task in
            task.parent ?? ""
        }

        return googleTasks
            .filter { $0.parent == nil }
            .map { task in
                let subtasks = (childTasks[task.id] ?? []).map { child in
                    SubtaskItem(
                        id: googleID(listID: taskListID, taskID: child.id),
                        title: cleanedTitle(child.title),
                        done: child.status == "completed",
                        createdAt: child.updated ?? Date(),
                        updatedAt: child.updated
                    )
                }

                return TaskItem(
                    id: googleID(listID: taskListID, taskID: task.id),
                    title: cleanedTitle(task.title),
                    deadline: task.due,
                    done: task.status == "completed",
                    createdAt: task.updated ?? Date(),
                    notes: task.notes,
                    priority: .normal,
                    updatedAt: task.updated,
                    completedAt: task.completed,
                    subtasks: subtasks.isEmpty ? nil : subtasks,
                    recurrence: nil,
                    pinned: nil,
                    source: .google,
                    externalID: task.id,
                    externalListID: taskListID,
                    externalUpdatedAt: task.updated,
                    deadlineHasTime: false
                )
            }
    }

    private static func googleID(listID: String, taskID: String) -> String {
        "google:\(listID):\(taskID)"
    }

    private static func cleanedTitle(_ title: String?) -> String {
        let trimmed = (title ?? "Untitled Google task").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Google task" : trimmed
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any] {
            if let message = error["message"] as? String {
                return message
            }
            if let status = error["status"] as? String {
                return status
            }
        }
        if let error = object["error"] as? String {
            return error
        }
        return nil
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

@MainActor
final class TaskModel: ObservableObject {
    @Published private(set) var tasks: [TaskItem]
    @Published private(set) var settings: AppSettings
    @Published private(set) var googleTaskLists: [GoogleTaskList] = []
    @Published private(set) var isGoogleBusy = false
    @Published var googleStatus: String?
    private var autoSyncTask: Task<Void, Never>?
    private static let googleAutoSyncIntervalNanoseconds: UInt64 = 60 * 1_000_000_000

    var notificationSettings: NotificationSettings {
        settings.notifications
    }

    init() {
        tasks = TaskStore.load()
        settings = SettingsStore.load()
        NotificationScheduler.sync(tasks: tasks, settings: notificationSettings)
        WidgetCenter.shared.reloadAllTimelines()
        startAutoSync()
    }

    deinit {
        autoSyncTask?.cancel()
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
        settings = SettingsStore.load()
        NotificationScheduler.sync(tasks: tasks, settings: notificationSettings)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func syncGoogleTasksIfPossible() async {
        guard settings.googleSync.isConnected,
              settings.googleSync.selectedTaskListID != nil
        else {
            return
        }
        await syncGoogleTasks()
    }

    func add(
        title: String,
        notes: String = "",
        deadline: Date?,
        priority: TaskPriority,
        recurrence: TaskRecurrence?,
        pinned: Bool,
        subtasks: [SubtaskItem] = []
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSubtasks = Self.cleanedSubtasks(subtasks)
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
            subtasks: cleanSubtasks.isEmpty ? nil : cleanSubtasks,
            recurrence: deadline == nil ? nil : recurrence,
            pinned: pinned ? true : nil,
            deadlineHasTime: deadline == nil ? nil : true
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
        let cleanSubtasks = Self.cleanedSubtasks(subtasks)
        tasks = tasks.map { item in
            guard item.id == task.id else { return item }
            guard !item.isGoogleTask else { return item }
            var updated = item
            updated.title = trimmed
            updated.notes = cleanNotes.isEmpty ? nil : cleanNotes
            updated.deadline = deadline
            updated.priority = priority
            updated.subtasks = cleanSubtasks.isEmpty ? nil : cleanSubtasks
            updated.recurrence = deadline == nil ? nil : recurrence
            updated.pinned = pinned ? true : nil
            updated.deadlineHasTime = deadline == nil ? nil : true
            updated.updatedAt = Date()
            return updated
        }
        persist()
    }

    func markDone(_ task: TaskItem) {
        if task.isGoogleTask {
            Task { await setGoogleTaskCompletion(task, done: true) }
            return
        }
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
        if task.isGoogleTask {
            Task { await setGoogleTaskCompletion(task, done: false) }
            return
        }
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
        guard !task.isGoogleTask else {
            googleStatus = "Google task delete is not enabled yet. Remove this in Google Tasks."
            return
        }
        tasks.removeAll { $0.id == task.id }
        persist()
    }

    func togglePinned(_ task: TaskItem) {
        guard !task.isGoogleTask else {
            googleStatus = "Google tasks are read-only. Pin local tasks in Quiet Tasks."
            return
        }
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
            guard !item.isGoogleTask else {
                googleStatus = "Google subtask sync is not enabled yet. Update subtasks in Google Tasks."
                return item
            }
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
                Task { @MainActor in
                    guard let self else { return }
                    let savedSettings = NotificationSettings(
                        enabled: granted,
                        reminderOffsets: settings.reminderOffsets.isEmpty ? [.oneHour] : settings.reminderOffsets
                    )
                    self.settings.notifications = savedSettings
                    SettingsStore.save(self.settings)
                    NotificationScheduler.sync(tasks: self.tasks, settings: savedSettings)
                }
            }
        } else {
            self.settings.notifications = settings
            SettingsStore.save(self.settings)
            NotificationScheduler.sync(tasks: tasks, settings: settings)
        }
    }

    func updateAppearance(_ appearance: AppearanceMode) {
        settings.appearance = appearance
        SettingsStore.save(settings)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updateGoogleSettings(_ googleSettings: GoogleSyncSettings) {
        settings.googleSync = googleSettings
        SettingsStore.save(settings)
    }

    func connectGoogle(clientID: String) async {
        await runGoogleOperation {
            var googleSettings = self.settings.googleSync
            googleSettings.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            if googleSettings.clientID.isEmpty {
                googleSettings.clientID = GoogleSyncSettings.defaultClientID
            }
            self.settings.googleSync = googleSettings
            SettingsStore.save(self.settings)

            let token = try await GoogleOAuthClient.authorize(clientID: googleSettings.effectiveClientID)
            googleSettings.isConnected = true
            self.settings.googleSync = googleSettings
            SettingsStore.save(self.settings)
            try await self.loadGoogleTaskLists(accessToken: token.value)
            if self.settings.googleSync.selectedTaskListID != nil {
                let syncedCount = try await self.syncGoogleTasks(accessToken: token.value)
                self.googleStatus = "Google Tasks connected. Synced \(syncedCount) tasks."
            } else {
                self.googleStatus = "Google Tasks connected. Choose a task list to sync."
            }
        }
    }

    func loadGoogleTaskLists() async {
        await runGoogleOperation {
            let token = try await GoogleOAuthClient.refreshedAccessToken(clientID: self.settings.googleSync.effectiveClientID)
            try await self.loadGoogleTaskLists(accessToken: token.value)
            self.googleStatus = "Google task lists refreshed."
        }
    }

    func syncGoogleTasks() async {
        await runGoogleOperation {
            let googleSettings = self.settings.googleSync
            let token = try await GoogleOAuthClient.refreshedAccessToken(clientID: googleSettings.effectiveClientID)
            let syncedCount = try await self.syncGoogleTasks(accessToken: token.value)
            self.googleStatus = "Synced \(syncedCount) Google tasks."
        }
    }

    private func setGoogleTaskCompletion(_ task: TaskItem, done: Bool) async {
        guard let taskListID = task.externalListID,
              let taskID = task.externalID
        else {
            googleStatus = GoogleSyncError.invalidResponse.errorDescription
            return
        }

        let previousTask = tasks.first { $0.id == task.id } ?? task
        let completedAt = Date()
        applyGoogleCompletionLocally(
            taskID: task.id,
            done: done,
            completedAt: done ? completedAt : nil,
            updatedAt: completedAt
        )

        let wasGoogleBusy = isGoogleBusy
        isGoogleBusy = true
        googleStatus = done ? "Completing in Google Tasks..." : "Restoring in Google Tasks..."

        do {
            let token = try await GoogleOAuthClient.refreshedAccessToken(clientID: self.settings.googleSync.effectiveClientID)
            let updatedGoogleTask = try await GoogleTasksClient.setCompletion(
                accessToken: token.value,
                taskListID: taskListID,
                taskID: taskID,
                done: done,
                completedAt: completedAt
            )

            applyGoogleCompletionLocally(
                taskID: task.id,
                done: done,
                completedAt: done ? (updatedGoogleTask.completed ?? completedAt) : nil,
                updatedAt: updatedGoogleTask.updated ?? Date()
            )
            googleStatus = done ? "Completed in Google Tasks." : "Restored in Google Tasks."
        } catch {
            restoreLocalTask(previousTask)
            googleStatus = googleWriteErrorMessage(error)
        }

        if !wasGoogleBusy {
            isGoogleBusy = false
        }
    }

    private func applyGoogleCompletionLocally(taskID: String, done: Bool, completedAt: Date?, updatedAt: Date) {
        tasks = tasks.map { item in
            guard item.id == taskID else { return item }
            var updated = item
            updated.done = done
            updated.completedAt = completedAt
            updated.updatedAt = updatedAt
            return updated
        }
        persist()
    }

    private func restoreLocalTask(_ task: TaskItem) {
        tasks = tasks.map { item in
            item.id == task.id ? task : item
        }
        persist()
    }

    private func googleWriteErrorMessage(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lowercasedMessage = message.lowercased()
        if lowercasedMessage.contains("insufficient")
            || lowercasedMessage.contains("permission")
            || lowercasedMessage.contains("scope") {
            return "Reconnect Google Tasks once to grant completion sync permission."
        }
        return message
    }

    func disconnectGoogle() {
        GoogleTokenStore.deleteRefreshToken()
        tasks.removeAll { $0.source == .google }
        googleTaskLists = []
        settings.googleSync = .default
        SettingsStore.save(settings)
        persist()
        googleStatus = "Google Tasks disconnected."
    }

    func selectGoogleTaskList(_ list: GoogleTaskList) {
        settings.googleSync.selectedTaskListID = list.id
        settings.googleSync.selectedTaskListTitle = list.title
        SettingsStore.save(settings)
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

    private func startAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncGoogleTasksIfPossible()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.googleAutoSyncIntervalNanoseconds)
                await self.syncGoogleTasksIfPossible()
            }
        }
    }

    private func loadGoogleTaskLists(accessToken: String) async throws {
        let lists = try await GoogleTasksClient.fetchTaskLists(accessToken: accessToken)
        googleTaskLists = lists

        if settings.googleSync.selectedTaskListID == nil, let first = lists.first {
            selectGoogleTaskList(first)
        } else if let selectedID = settings.googleSync.selectedTaskListID,
                  let selected = lists.first(where: { $0.id == selectedID }) {
            settings.googleSync.selectedTaskListTitle = selected.title
            SettingsStore.save(settings)
        }
    }

    @discardableResult
    private func syncGoogleTasks(accessToken: String) async throws -> Int {
        let googleSettings = settings.googleSync
        guard let taskListID = googleSettings.selectedTaskListID else {
            throw GoogleSyncError.missingTaskList
        }

        let syncStartedAt = Date()
        let startingTaskIDs = Set(tasks.map(\.id))
        let syncedTasks = try await GoogleTasksClient.fetchTasks(
            accessToken: accessToken,
            taskListID: taskListID,
            taskListTitle: googleSettings.selectedTaskListTitle
        )
        let latestSavedTasks = TaskStore.load()
        let localTasks = mergedLocalTasksForGoogleSync(
            latestSavedTasks: latestSavedTasks,
            currentTasks: tasks,
            syncStartedAt: syncStartedAt,
            startingTaskIDs: startingTaskIDs
        )
        tasks = TaskStore.normalized(localTasks + syncedTasks)
        settings.googleSync.lastSyncedAt = Date()
        SettingsStore.save(settings)
        persist()
        return syncedTasks.count
    }

    private func mergedLocalTasksForGoogleSync(
        latestSavedTasks: [TaskItem],
        currentTasks: [TaskItem],
        syncStartedAt: Date,
        startingTaskIDs: Set<String>
    ) -> [TaskItem] {
        var localTasksByID: [String: TaskItem] = [:]

        for task in latestSavedTasks where !task.isGoogleTask {
            localTasksByID[task.id] = task
        }

        for task in currentTasks where !task.isGoogleTask {
            if let savedTask = localTasksByID[task.id] {
                if task.localRevisionDate > savedTask.localRevisionDate {
                    localTasksByID[task.id] = task
                }
            } else if !startingTaskIDs.contains(task.id) || task.localRevisionDate >= syncStartedAt {
                localTasksByID[task.id] = task
            }
        }

        return Array(localTasksByID.values)
    }

    private static func cleanedSubtasks(_ subtasks: [SubtaskItem]) -> [SubtaskItem] {
        let now = Date()
        return subtasks.compactMap { subtask in
            let trimmed = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var cleaned = subtask
            cleaned.title = trimmed
            cleaned.updatedAt = cleaned.updatedAt ?? now
            return cleaned
        }
    }

    private func runGoogleOperation(_ operation: @escaping () async throws -> Void) async {
        guard !isGoogleBusy else { return }
        isGoogleBusy = true
        googleStatus = nil
        do {
            try await operation()
        } catch {
            googleStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isGoogleBusy = false
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
    @State private var newSubtasks: [SubtaskItem] = []
    @State private var newSubtasksExpanded = false
    @State private var newRecurrence: TaskRecurrence?
    @State private var newPinned = false
    @State private var pendingCompletion: TaskItem?
    @State private var pendingDeletion: TaskItem?
    @State private var pendingReadOnlyGoogleTask: TaskItem?
    @State private var editingDraft: TaskDraft?
    @State private var showingSettings = false
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
                    refreshTasks()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onOpenURL(perform: handleURL)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshTasks()
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
        .alert("Google task editing is limited", isPresented: Binding(
            get: { pendingReadOnlyGoogleTask != nil },
            set: { if !$0 { pendingReadOnlyGoogleTask = nil } }
        )) {
            Button("OK") {
                pendingReadOnlyGoogleTask = nil
            }
        } message: {
            Text("Complete or restore “\(pendingReadOnlyGoogleTask?.title ?? "this task")” here. Edit and delete Google tasks in Google Tasks.")
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
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(model: model) {
                showingSettings = false
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .preferredColorScheme(model.settings.appearance.colorScheme)
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

    private func refreshTasks() {
        model.reload()
        Task {
            await model.syncGoogleTasksIfPossible()
        }
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

                DisclosureGroup(isExpanded: $newSubtasksExpanded) {
                    SubtaskEditor(subtasks: $newSubtasks, showsTitle: false, showsCompletionToggle: false)
                        .padding(.top, 6)
                } label: {
                    Label(newSubtasks.isEmpty ? "Subtasks" : "\(newSubtasks.count) subtasks", systemImage: "checklist")
                        .font(.headline)
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
                    onComplete: { requestCompletion(for: task) },
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
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.add(
            title: newTitle,
            deadline: newHasDeadline ? newDeadline : nil,
            priority: newPriority,
            recurrence: newHasDeadline ? newRecurrence : nil,
            pinned: newPinned,
            subtasks: newSubtasks
        )
        newTitle = ""
        newHasDeadline = false
        newPriority = .normal
        newSubtasks = []
        newSubtasksExpanded = false
        newRecurrence = nil
        newPinned = false
        selectedFilter = .open
        newTaskFocused = true
    }

    private func requestCompletion(for task: TaskItem) {
        pendingCompletion = task
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "quiettasks" else { return }

        switch url.host {
        case "open":
            selectedFilter = .open
            model.reload()
        case "add":
            selectedFilter = .open
            newTaskFocused = true
        case "complete":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "id" }?
                .value
            model.reload()
            if let task = model.tasks.first(where: { $0.id == id && !$0.done }) {
                requestCompletion(for: task)
            }
        case "google":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "id" }?
                .value
            model.reload()
            pendingReadOnlyGoogleTask = model.tasks.first { $0.id == id }
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

struct SubtaskEditor: View {
    @Binding var subtasks: [SubtaskItem]
    var showsTitle = true
    var showsCompletionToggle = true
    @State private var newSubtaskTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                Label("Subtasks", systemImage: "checklist")
                    .font(.headline)
            }

            ForEach($subtasks) { $subtask in
                HStack(spacing: 8) {
                    if showsCompletionToggle {
                        Toggle("", isOn: $subtask.done)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(Color(red: 0.62, green: 0.86, blue: 0.88))
                    }

                    TextField("Subtask", text: $subtask.title)
                        .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        subtasks.removeAll { $0.id == subtask.id }
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
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtasks.append(SubtaskItem(
            id: UUID().uuidString,
            title: trimmed,
            done: false,
            createdAt: Date(),
            updatedAt: nil
        ))
        newSubtaskTitle = ""
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
                    if task.isGoogleTask {
                        SourceBadge(title: "Google")
                    } else {
                        PriorityBadge(priority: task.taskPriority)
                    }
                    if let deadline = task.deadline {
                        Label(deadlineText(deadline), systemImage: "calendar")
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
                            .disabled(task.isGoogleTask)
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
                .disabled(task.isGoogleTask)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .help("Edit")
                .disabled(task.isGoogleTask)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("Delete")
                .disabled(task.isGoogleTask)
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func deadlineText(_ deadline: Date) -> String {
        if task.showsDeadlineTime {
            return deadline.formatted(date: .abbreviated, time: .shortened)
        }
        return deadline.formatted(date: .abbreviated, time: .omitted)
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
                RecurrencePicker(recurrence: $draft.recurrence, isEnabled: draft.hasDeadline)
                PinToggle(isPinned: $draft.pinned)
            }

            SubtaskEditor(subtasks: $draft.subtasks)

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

struct SettingsSheet: View {
    @ObservedObject var model: TaskModel
    @State private var draft: AppSettings
    @State private var showAdvancedGoogleSettings = false
    var onDone: () -> Void

    init(model: TaskModel, onDone: @escaping () -> Void) {
        self.model = model
        _draft = State(initialValue: model.settings)
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title.bold())

            appearanceSection
            Divider()
            notificationSection
            Divider()
            googleSection

            if let status = model.googleStatus {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Done") {
                    saveSettings()
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Appearance", systemImage: "circle.lefthalf.filled")
                .font(.headline)

            Picker("Appearance", selection: $draft.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: draft.appearance) { _, appearance in
                model.updateAppearance(appearance)
            }
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Notifications", isOn: $draft.notifications.enabled)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 10) {
                Text("Default reminders")
                    .font(.headline)

                ForEach(ReminderOffset.allCases) { offset in
                    Toggle(offset.title, isOn: reminderBinding(for: offset))
                        .toggleStyle(.checkbox)
                        .disabled(!draft.notifications.enabled)
                }
            }
        }
        .onChange(of: draft.notifications) { _, notifications in
            model.updateNotificationSettings(notifications)
        }
    }

    private var googleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Google Tasks", systemImage: "g.circle")
                    .font(.headline)
                Spacer()
                if model.isGoogleBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Optional Google Tasks sync imports tasks into the app and widget. Completing or restoring a synced task here updates Google Tasks too.")
                .font(.callout)
                .foregroundStyle(.secondary)

            DisclosureGroup("Advanced", isExpanded: $showAdvancedGoogleSettings) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use this only if you are running a fork with your own Google Cloud Desktop OAuth client.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Desktop OAuth client ID", text: $draft.googleSync.clientID)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.isGoogleBusy)
                }
                .padding(.top, 6)
            }
            .font(.caption)

            HStack(spacing: 10) {
                if draft.googleSync.isConnected {
                    Button {
                        saveSettings()
                        Task { await model.loadGoogleTaskLists() }
                    } label: {
                        Label("Refresh Lists", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isGoogleBusy)

                    Button {
                        saveSettings()
                        Task { await model.syncGoogleTasks() }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isGoogleBusy || draft.googleSync.selectedTaskListID == nil)

                    Button(role: .destructive) {
                        model.disconnectGoogle()
                        draft.googleSync = model.settings.googleSync
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .disabled(model.isGoogleBusy)
                } else {
                    Button {
                        saveSettings()
                        Task { await model.connectGoogle(clientID: draft.googleSync.clientID) }
                    } label: {
                        Label("Connect Google Tasks", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isGoogleBusy)
                }
            }

            if draft.googleSync.isConnected {
                googleListPicker
                if let lastSyncedAt = draft.googleSync.lastSyncedAt {
                    Text("Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: model.settings.googleSync) { _, googleSync in
            draft.googleSync = googleSync
        }
    }

    private var googleListPicker: some View {
        HStack(spacing: 10) {
            Label("Task list", systemImage: "list.bullet.rectangle")
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { draft.googleSync.selectedTaskListID ?? "" },
                set: { selectedID in
                    guard let list = model.googleTaskLists.first(where: { $0.id == selectedID }) else { return }
                    draft.googleSync.selectedTaskListID = list.id
                    draft.googleSync.selectedTaskListTitle = list.title
                    model.selectGoogleTaskList(list)
                }
            )) {
                if model.googleTaskLists.isEmpty {
                    Text(draft.googleSync.selectedTaskListTitle ?? "No lists loaded").tag(draft.googleSync.selectedTaskListID ?? "")
                } else {
                    ForEach(model.googleTaskLists) { list in
                        Text(list.title).tag(list.id)
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(model.googleTaskLists.isEmpty || model.isGoogleBusy)
        }
    }

    private func saveSettings() {
        draft.notifications.reminderOffsets.sort { $0.rawValue < $1.rawValue }
        if draft.notifications.enabled && draft.notifications.reminderOffsets.isEmpty {
            draft.notifications.reminderOffsets = [.oneHour]
        }
        model.updateAppearance(draft.appearance)
        model.updateNotificationSettings(draft.notifications)
        model.updateGoogleSettings(draft.googleSync)
    }

    private func reminderBinding(for offset: ReminderOffset) -> Binding<Bool> {
        Binding(
            get: {
                draft.notifications.reminderOffsets.contains(offset)
            },
            set: { enabled in
                if enabled {
                    if !draft.notifications.reminderOffsets.contains(offset) {
                        draft.notifications.reminderOffsets.append(offset)
                    }
                } else {
                    draft.notifications.reminderOffsets.removeAll { $0 == offset }
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

struct SourceBadge: View {
    var title: String

    var body: some View {
        Label(title, systemImage: "link")
            .font(.caption.bold())
            .foregroundStyle(Color(red: 0.62, green: 0.86, blue: 0.88))
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
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Quiet Tasks", id: "main") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .windowArrangement) {
                Button("Show Quiet Tasks") {
                    openWindow(id: "main")
                    NSApplication.shared.activate()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
    }
}
