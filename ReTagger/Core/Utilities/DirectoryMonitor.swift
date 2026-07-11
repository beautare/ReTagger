//
//  DirectoryMonitor.swift
//  ReTagger
//
//  Observes file system changes and notifies on updates.
//

import Foundation
import Darwin
import CoreServices

final class DirectoryMonitor {
    typealias ChangeHandler = @MainActor () -> Void

    private let url: URL
    private let includeSubdirectories: Bool
    private let handler: ChangeHandler

    private var sources: [DispatchSourceFileSystemObject] = []
    private var eventStream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.retagger.directory-monitor", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?
    private var isRunning = false

    init(
        url: URL,
        includeSubdirectories: Bool,
        handler: @escaping ChangeHandler
    ) {
        self.url = url
        self.includeSubdirectories = includeSubdirectories
        self.handler = handler
    }

    func start() {
        guard !isRunning else { return }

        if includeSubdirectories {
            startRecursiveStream()
        } else {
            startFlatMonitor(for: url)
        }

        isRunning = true
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        sources.forEach { $0.cancel() }
        sources.removeAll()

        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }

        isRunning = false
    }

    deinit {
        stop()
    }

    private func startFlatMonitor(for directory: URL) {
        guard let source = makeSource(for: directory) else { return }
        sources.append(source)
        source.resume()
    }

    private func startRecursiveStream() {
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagNoDefer |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseExtendedData |
                kFSEventStreamCreateFlagUseCFTypes
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let monitor = Unmanaged<DirectoryMonitor>.fromOpaque(info).takeUnretainedValue()
                monitor.scheduleDebouncedHandler()
            },
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) {
            eventStream = stream
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func makeSource(for directory: URL) -> DispatchSourceFileSystemObject? {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor != -1 else {
            return nil
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleDebouncedHandler()
        }

        source.setCancelHandler {
            close(descriptor)
        }

        return source
    }

    private func scheduleDebouncedHandler() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handler()
            }
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
}
