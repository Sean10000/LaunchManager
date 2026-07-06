import Foundation

/// Watches launchd plist directories and debounces change notifications.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.4

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start(watching paths: [URL]) {
        stop()
        let pathStrings = paths.map(\.path) as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
        )
        stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.scheduleCallback()
            },
            &context,
            pathStrings,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func scheduleCallback() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    deinit {
        stop()
    }
}
