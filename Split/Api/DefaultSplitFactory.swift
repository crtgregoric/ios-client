//
//  SplitFactory.swift
//  Split
//
//  Created by Brian Sztamfater on 27/9/17.
//
//

import Foundation

/**
 Default implementation of SplitManager protocol
 */
public class DefaultSplitFactory: NSObject, SplitFactory {

    // Not using default implementation in protocol
    // extension due to Objc interoperability
    @objc public static var sdkVersion: String {
        return Version.semantic
    }

    private var defaultClient: SplitClient?
    private var defaultManager: SplitManager?
    private let filterBuilder = FilterBuilder()

    public var client: SplitClient {
        return defaultClient!
    }

    public var manager: SplitManager {
        return defaultManager!
    }

    public var version: String {
        return Version.sdk
    }

    init(apiKey: String, key: Key, config: SplitClientConfig, httpClient: HttpClient?,
         reachabilityChecker: HostReachabilityChecker?,
         testDatabase: SplitDatabase? = nil) throws {
        super.init()

        let dataFolderName = DataFolderFactory().createFrom(apiKey: apiKey) ?? config.defaultDataFolder

        HttpSessionConfig.default.connectionTimeOut = TimeInterval(config.connectionTimeout)
        MetricManagerConfig.default.pushRateInSeconds = config.metricsPushRate
        MetricManagerConfig.default.defaultDataFolderName = dataFolderName

        config.apiKey = apiKey
        let storageContainer = try buildStorageContainer(userKey: key.matchingKey,
                                                         dataFolderName: dataFolderName,
                                                         testDatabase: testDatabase)

        migrateStorageIfNeeded(storageContainer: storageContainer, userKey: key.matchingKey)

        let manager = DefaultSplitManager(splitsStorage: storageContainer.splitsStorage)
        defaultManager = manager

        let eventsManager = DefaultSplitEventsManager(config: config)
        eventsManager.start()

        let splitsFilterQueryString = try filterBuilder.add(filters: config.sync.filters).build()
        let  endpointFactory = EndpointFactory(serviceEndpoints: config.serviceEndpoints,
                                               apiKey: apiKey, userKey: key.matchingKey,
                                               splitsQueryString: splitsFilterQueryString)

        let restClient = DefaultRestClient(httpClient: httpClient ?? DefaultHttpClient.shared,
                                           endpointFactory: endpointFactory,
                                           reachabilityChecker: reachabilityChecker ?? ReachabilityWrapper())

        /// TODO: Remove this line when metrics refactor
        DefaultMetricsManager.shared.restClient = restClient

        let apiFacadeBuilder = SplitApiFacade.builder().setUserKey(key.matchingKey).setSplitConfig(config)
            .setRestClient(restClient).setEventsManager(eventsManager)
            .setStorageContainer(storageContainer)
            .setSplitsQueryString(splitsFilterQueryString)

        if let httpClient = httpClient {
            _ = apiFacadeBuilder.setStreamingHttpClient(httpClient)
        }

        let apiFacade = apiFacadeBuilder.build()

        let impressionsFlushChecker = DefaultRecorderFlushChecker(maxQueueSize: config.impressionsQueueSize,
                                                                  maxQueueSizeInBytes: config.impressionsQueueSize)

        let impressionsSyncHelper
            = ImpressionsRecorderSyncHelper(impressionsStorage: storageContainer.impressionsStorage,
                                            accumulator: impressionsFlushChecker)

        let eventsFlushChecker
            = DefaultRecorderFlushChecker(maxQueueSize: Int(config.eventsQueueSize),
                                          maxQueueSizeInBytes: config.maxEventsQueueMemorySizeInBytes)
        let eventsSyncHelper = EventsRecorderSyncHelper(eventsStorage: storageContainer.eventsStorage,
                                                        accumulator: eventsFlushChecker)

        let syncWorkerFactory = DefaultSyncWorkerFactory(userKey: key.matchingKey,
                                                         splitConfig: config,
                                                         splitsFilterQueryString: splitsFilterQueryString,
                                                         apiFacade: apiFacade,
                                                         storageContainer: storageContainer,
                                                         splitChangeProcessor: DefaultSplitChangeProcessor(),
                                                         eventsManager: eventsManager)

        let synchronizer = DefaultSynchronizer(splitConfig: config, splitApiFacade: apiFacade,
                                               splitStorageContainer: storageContainer,
                                               syncWorkerFactory: syncWorkerFactory,
                                               impressionsSyncHelper: impressionsSyncHelper,
                                               eventsSyncHelper: eventsSyncHelper,
                                               splitsFilterQueryString: splitsFilterQueryString,
                                               splitEventsManager: eventsManager)

        let syncManager = SyncManagerBuilder().setUserKey(key.matchingKey).setStorageContainer(storageContainer)
            .setEndpointFactory(endpointFactory).setSplitApiFacade(apiFacade).setSynchronizer(synchronizer)
            .setSplitConfig(config).build()

        defaultClient = DefaultSplitClient(config: config, key: key, apiFacade: apiFacade,
                                           storageContainer: storageContainer,
                                           synchronizer: synchronizer, eventsManager: eventsManager) {
            syncManager.stop()
            manager.destroy()
        }

        eventsManager.getExecutorResources().setClient(client: defaultClient!)
        syncManager.start()
    }

    private func buildStorageContainer(userKey: String,
                                       dataFolderName: String,
                                       testDatabase: SplitDatabase?) throws -> SplitStorageContainer {
        let fileStorage = FileStorage(dataFolderName: dataFolderName)
        let dispatchQueue = DispatchQueue(label: "SplitCoreDataCache", target: DispatchQueue.global())
        var database: SplitDatabase?

        if testDatabase == nil {
            guard let helper = CoreDataHelperBuilder.build(databaseName: dataFolderName,
                                                           dispatchQueue: dispatchQueue) else {
                throw GenericError.coultNotCreateCache
            }
            database = CoreDataSplitDatabase(coreDataHelper: helper, dispatchQueue: dispatchQueue)
        } else {
            database = testDatabase
        }

        guard let splitDatabase = database else {
            throw GenericError.coultNotCreateCache
        }

        let persistentSplitsStorage = DefaultPersistentSplitsStorage(database: splitDatabase)
        let splitsStorage = DefaultSplitsStorage(persistentSplitsStorage: persistentSplitsStorage)

        let persistentMySegmentsStorage = DefaultPersistentMySegmentsStorage(userKey: userKey, database: splitDatabase)
        let mySegmentsStorage = DefaultMySegmentsStorage(persistentMySegmentsStorage: persistentMySegmentsStorage)

        let impressionsStorage
            = DefaultImpressionsStorage(database: splitDatabase,
                                        expirationPeriod: ServiceConstants.recordedDataExpirationPeriodInSeconds)

        let eventsStorage
            = DefaultEventsStorage(database: splitDatabase,
                                   expirationPeriod: ServiceConstants.recordedDataExpirationPeriodInSeconds)

        return SplitStorageContainer(splitDatabase: splitDatabase,
                                     fileStorage: fileStorage,
                                     splitsStorage: splitsStorage,
                                     persistentSplitsStorage: persistentSplitsStorage,
                                     mySegmentsStorage: mySegmentsStorage,
                                     impressionsStorage: impressionsStorage,
                                     eventsStorage: eventsStorage)
    }

    private func migrateStorageIfNeeded(storageContainer: SplitStorageContainer, userKey: String) {
        let storageMigrator = DefaultStorageMigrator(fileStorage: storageContainer.fileStorage,
                                                     splitDatabase: storageContainer.splitDatabase,
                                                     userKey: userKey)
        _ = storageMigrator.runMigrationIfNeeded()
    }
}
