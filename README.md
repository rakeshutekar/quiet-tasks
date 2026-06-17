# Quiet Tasks

Quiet Tasks is a minimal macOS to-do app with a real desktop widget.

I wanted a simple task widget that could live on the macOS desktop like the built-in widgets, show only the tasks that still need attention, and stay visually quiet. I could not find one that felt right, so this project exists for anyone who wants the same thing.

Feel free to download it, use it, fork it, and contribute.

## What It Does

- Native macOS app built with SwiftUI.
- Real WidgetKit desktop widget, available in small, medium, and large sizes.
- Open, Today, All Tasks, and Done views.
- Add, edit, delete, complete, and restore tasks.
- Optional deadlines with a compact date/time popover.
- Low, Normal, and High priority options.
- Global notification defaults for deadline reminders.
- One-level subtasks with completion tracking.
- Daily, weekly, and monthly recurring tasks.
- Pinned tasks that stay above the regular list.
- System, light, and dark appearance modes for the app and widget.
- Optional Google Tasks sync for showing a Google task list in Quiet Tasks.
- Widget shows open tasks only, plus progress for what is currently active.
- Completing local tasks from the widget uses an inline confirmation. Google task completion opens the app to sync back to Google.
- No account or cloud service required for local tasks.

## Why This Is Better

Most to-do apps are either full productivity suites or they do not behave like a proper macOS desktop widget. Quiet Tasks is intentionally smaller:

- It is built around the desktop widget first.
- It keeps the widget readable and minimal instead of busy.
- It keeps completed tasks out of the widget so the desktop stays clean.
- It can show pinned tasks, priority, and subtasks without turning the widget into a dashboard.
- It gives the full app enough tools to manage tasks without turning into a project-management app.
- It is open source, so anyone can improve it.

## Requirements

- macOS with desktop widgets support.
- Xcode installed.
- Swift and WidgetKit support from the installed Xcode toolchain.

The current local development build stores shared app/widget data at:

```text
/Users/Shared/QuietTasks/tasks.json
```

That lets an unsigned local app and WidgetKit extension share task data during development. A production-distributed version should move this to a signed App Group.

## Download

The latest downloadable build is available from GitHub Releases:

```text
https://github.com/rakeshutekar/quiet-tasks/releases
```

Current builds are unsigned development builds. If macOS blocks the app after download, open **System Settings -> Privacy & Security** and allow it, or build from source with Xcode.

## Google Tasks Sync

Quiet Tasks can import tasks from one Google Tasks list and show them in the app and widget. Completing or restoring a Google task in Quiet Tasks syncs that status back to Google Tasks. Google Tasks sync runs after connect, when the app becomes active, when you press Refresh, and every minute while the app is running. Editing, deleting, and subtask writes still happen in Google Tasks.

To use it in the app:

1. Open **Quiet Tasks -> Settings -> Google Tasks**.
2. Click **Connect Google**.
3. Choose a Google account, choose a task list, then click **Sync Now**.

For forks or local builds that use their own Google Cloud project:

1. In Google Cloud, open **APIs & Services -> Library** and enable **Google Tasks API**.
2. Open **APIs & Services -> OAuth consent screen** and configure the app. If the publishing status is **Testing**, add your Google account as a test user.
3. Open **APIs & Services -> Credentials -> Create Credentials -> OAuth client ID**.
4. Select **Application type: Desktop app**, name it `Quiet Tasks`, and create it.
5. Copy the generated **Client ID**. You do not need to add a redirect URI for a Desktop app; Quiet Tasks uses a temporary localhost callback during sign-in.
6. Open **Quiet Tasks -> Settings -> Google Tasks -> Advanced** and paste the Desktop OAuth client ID.

Quiet Tasks requests the Google Tasks scope:

```text
https://www.googleapis.com/auth/tasks
```

If you connected before completion sync was added, disconnect and reconnect Google Tasks once so Google grants the write scope.

Google Tasks due dates are date-only. If a Google task has a due date, Quiet Tasks shows the date without an exact time.

## Install From Source

Clone the repo:

```bash
git clone https://github.com/rakeshutekar/quiet-tasks.git
cd quiet-tasks
```

Build the release app:

```bash
xcodebuild \
  -project QuietTasks.xcodeproj \
  -scheme "Quiet Tasks" \
  -configuration Release \
  -derivedDataPath XcodeDerivedData \
  -destination 'generic/platform=macOS' \
  build
```

Install it into Applications:

```bash
cp -R "XcodeDerivedData/Build/Products/Release/Quiet Tasks.app" /Applications/
```

Open the app once:

```bash
open -a "/Applications/Quiet Tasks.app"
```

Then add the widget:

1. Right-click the desktop.
2. Choose **Edit Widgets**.
3. Search for **Quiet Tasks**.
4. Drag the widget size you want onto the desktop.
5. Click **Done**.

If macOS blocks the app because it was built or downloaded outside the App Store, open **System Settings -> Privacy & Security** and allow it, or build it locally from Xcode.

## Development

Open the project in Xcode:

```bash
open QuietTasks.xcodeproj
```

Main files:

- `Sources/QuietTasksApp/QuietTasksApp.swift` - the macOS app.
- `Sources/QuietTasksWidget/QuietTasksWidget.swift` - the WidgetKit widget.
- `Sources/QuietTasksWidget/WidgetBundle.swift` - widget bundle entry point.
- `Scripts/make-icon.swift` - local icon generation helper.

Build from the command line:

```bash
xcodebuild \
  -project QuietTasks.xcodeproj \
  -scheme "Quiet Tasks" \
  -configuration Release \
  -derivedDataPath XcodeDerivedData \
  -destination 'generic/platform=macOS' \
  build
```

## Contributing

Contributions are welcome. Useful areas to improve:

- Signed release packaging.
- App Group storage for production signing.
- Keyboard shortcuts.
- Two-way Google Tasks sync.
- Better recurring tasks.
- iCloud sync as an optional feature.
- More widget configuration options while keeping the default UI quiet.

Please keep the app minimal, native, and calm. The point is a useful task widget that does not visually take over the desktop.

## License

MIT. Use it freely.
