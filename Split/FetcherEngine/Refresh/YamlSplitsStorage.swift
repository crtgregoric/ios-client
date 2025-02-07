//
//  YamlSplitsStorage.swift
//  Split
//
//  Created by Javier Avrudsky on 05/01/2021.
//  Copyright © 2021 Split. All rights reserved.
//

import Foundation

struct YamlSplitStorageConfig {
    var refreshInterval: Int = 10
}

class YamlSplitsStorage: SplitsStorage {

    var changeNumber: Int64

    var updateTimestamp: Int64

    var splitsFilterQueryString: String

    private let refreshInterval: Int
    private let eventsManager: SplitEventsManager
    private let fileStorage: FileStorageProtocol
    private var taskExecutor: PeriodicTaskExecutor?
    private var fileParser: LocalhostSplitsParser!
    private let supportedExtensions = ["yaml", "yml", "splits"]
    private let fileName: String
    private let inMemorySplits = SyncDictionarySingleWrapper<String, Split>()

    init(fileStorage: FileStorageProtocol,
         config: YamlSplitStorageConfig = YamlSplitStorageConfig(),
         eventsManager: SplitEventsManager,
         splitsFileName: String, bundle: Bundle) {

        self.fileName = splitsFileName
        self.fileStorage = fileStorage
        self.refreshInterval = config.refreshInterval
        self.eventsManager = eventsManager
        self.changeNumber = -1
        self.updateTimestamp = 1
        self.splitsFilterQueryString = ""

        let fileName = splitsFileName
        guard let fileInfo = splitFileName(fileName) else {
            eventsManager.notifyInternalEvent(SplitInternalEvent.sdkReadyTimeoutReached)
            Logger.e("""
                Localhost file name \(fileName) has not the correct format.
                It should be similar to 'name.yaml', 'name.yml'
                """)
            return
        }

        if !isSupportedExtensionType(fileInfo.type) {
            eventsManager.notifyInternalEvent(SplitInternalEvent.sdkReadyTimeoutReached)
            Logger.e("Localhost file extension \(fileInfo.type) is not supported. It should be '.yaml', '.yml'")
            return
        }

        if !LocalhostFileCopier(bundle: bundle).copySourceFile(name: fileInfo.name,
                                                               type: fileInfo.type,
                                                               fileStorage: fileStorage) {
            eventsManager.notifyInternalEvent(SplitInternalEvent.sdkReadyTimeoutReached)
            Logger.e("Localhost file name \(fileName) not found. Please check name.")
            return
        }

        self.fileParser = parser(for: fileInfo.type)
        if !loadFile(name: fileName) {
            eventsManager.notifyInternalEvent(SplitInternalEvent.sdkReadyTimeoutReached)
            Logger.e("Localhost file \(fileName) not found or empty.")
            return
        }

        logFileInfo(name: fileName)
        eventsManager.notifyInternalEvent(.mySegmentsAreReady)
        eventsManager.notifyInternalEvent(.splitsAreReady)
        if refreshInterval > 0 {
            self.taskExecutor = createTaskExecutor()
            self.start()
        }
    }

    func loadLocal() {
        loadFile(name: fileName)
    }

    func get(name: String) -> Split? {
        inMemorySplits.value(forKey: name)
    }

    func getMany(splits: [String]) -> [String: Split] {
        let names = Set(splits)
        return inMemorySplits.all.filter { return names.contains($0.key) }
    }

    func getAll() -> [String: Split] {
        return inMemorySplits.all
    }

    func update(splitChange: ProcessedSplitChange) {
    }

    func update(filterQueryString: String) {
    }

    func updateWithoutChecks(split: Split) {
    }

    func isValidTrafficType(name: String) -> Bool {
        return true
    }

    func clear() {
        inMemorySplits.removeAll()
    }

    func start() {
        taskExecutor?.start()
    }

    func stop() {
        taskExecutor?.stop()
    }

    private func createTaskExecutor() -> PeriodicTaskExecutor {
        var config = PeriodicTaskExecutorConfig()
        config.firstExecutionWindow = 1
        config.rate = refreshInterval
        let fileName = self.fileName
        return PeriodicTaskExecutor(
            dispatchGroup: nil,
            config: config,
            triggerAction: {[weak self] in
                if let self = self {
                    self.loadFile(name: fileName)
                }
            }
        )
    }

    @discardableResult
    private func loadFile(name: String) -> Bool {
        inMemorySplits.removeAll()
        guard let content = fileStorage.read(fileName: name), let parser = self.fileParser else {
            return false
        }
        let loadedSplits = parser.parseContent(content)
        if loadedSplits.count < 1 {
            return false
        }

        inMemorySplits.setValues(loadedSplits)
        return true
    }

    private func parser(for type: String) -> LocalhostSplitsParser {
        if type == "yaml" || type == "yml" {
            return YamlLocalhostSplitsParser()
        }
        Logger.w("""
                Localhost mode: .split mocks will be deprecated soon in favor of YAML files,
                which provide more targeting power. Take a look in our documentation.
                """)
        return SpaceDelimitedLocalhostSplitsParser()
    }

    private func logFileInfo(name: String) {
        let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        let cacheDirectory = URL(fileURLWithPath: cachePath)
        let path = cacheDirectory.appendingPathComponent(name)
        Logger.d("Localhost file path: \(path)")
    }

    private func splitFileName(_ fileName: String) -> (name: String, type: String)? {
        if let dotIndex = fileName.lastIndex(of: ".") {
            let name = String(fileName.prefix(upTo: dotIndex))
            let type = String(fileName.suffix(from: fileName.index(after: dotIndex)))
            if type != "", name != "" {
                return (name: name, type: type)
            }
        }
        return nil
    }

    private func isSupportedExtensionType(_ type: String) -> Bool {
        return supportedExtensions.filter({ $0 == type.lowercased() }).count == 1
    }
}

class LocalhostFileCopier {
    var bundle: Bundle!

    init(bundle: Bundle) {
        self.bundle = bundle
    }

    func copySourceFile(name: String, type: String, fileStorage: FileStorageProtocol) -> Bool {

        guard let fileContent = loadInitialFile(name: name, type: type) else {
            return false
        }
        fileStorage.write(fileName: "\(name).\(type)", content: fileContent)
        return true
    }

    private func loadInitialFile(name fileName: String, type fileType: String) -> String? {
        var fileContent: String?
        if let filepath = bundle.path(forResource: fileName, ofType: fileType) {
            do {
                fileContent = try String(contentsOfFile: filepath, encoding: .utf8)
            } catch {
                Logger.e("Could not load localhost file: \(filepath)")
            }
        }
        return fileContent
    }
}
