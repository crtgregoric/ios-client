//
//  NotificationManagerKeeper.swift
//  Split
//
//  Created by Javier L. Avrudsky on 01/09/2020.
//  Copyright © 2020 Split. All rights reserved.
//

import Foundation

protocol NotificationManagerKeeper {
    var publishersCount: Int { get }
    func handleIncomingPresenceEvent(notification: OccupancyNotification)
}

class DefaultNotificationManagerKeeper: NotificationManagerKeeper {

    struct PublishersInfo {
        var count: Int
        var lastTimestamp: Int
    }

    let kChannelPriIndex = 0
    let kChannelSecIndex = 1

    /// By default we consider one publisher en primary channel available
    var publishersInfo = [
        PublishersInfo(count: 1, lastTimestamp: 0),
        PublishersInfo(count: 0, lastTimestamp: 0)
    ]

    var publishersCount: Int {
        var count = 0
        DispatchQueue.global().sync {
            count = publishersInfo[kChannelPriIndex].count + publishersInfo[kChannelSecIndex].count
        }
        return count
    }

    private var broadcasterChannel: PushManagerEventBroadcaster

    init(broadcasterChannel: PushManagerEventBroadcaster) {
        self.broadcasterChannel = broadcasterChannel
    }

    func handleIncomingPresenceEvent(notification: OccupancyNotification) {
        let channelIndex = getChannelIndex(of: notification)

        if channelIndex == -1 {
            return
        }
        if isOldTimestamp(notification: notification, for: channelIndex) {
            return
        }
        update(timestamp: notification.timestamp, for: channelIndex)
        let prevPriPublishers = publishers(in: kChannelPriIndex)
        let prevSecPublishers = publishers(in: kChannelSecIndex)
        update(count: notification.metrics.publishers, for: channelIndex)

        if publishersCount == 0 && prevPriPublishers + prevSecPublishers > 0 {
            broadcasterChannel.push(event: .pushSubsystemDown)
            return
        }

        if publishersCount > 0 && prevPriPublishers + prevSecPublishers == 0 {
            broadcasterChannel.push(event: .pushSubsystemUp)
            return
        }
    }

    private func isOldTimestamp(notification: OccupancyNotification, for channelIndex: Int) -> Bool {
        var timestamp = 0
        DispatchQueue.global().sync {
            timestamp =  publishersInfo[channelIndex].lastTimestamp
        }
        return timestamp >= notification.timestamp
    }

    private func update(count: Int, for channelIndex: Int) {
        DispatchQueue.global().sync {
            publishersInfo[channelIndex].count = count
        }
    }

    private func update(timestamp: Int, for channelIndex: Int) {
        DispatchQueue.global().sync {
            publishersInfo[channelIndex].lastTimestamp = timestamp
        }
    }

    private func publishers(in channelIndex: Int) -> Int {
        var count = 0
        DispatchQueue.global().sync {
            count =  publishersInfo[channelIndex].count
        }
        return count
    }

    private func getChannelIndex(of notification: OccupancyNotification) -> Int {
        if notification.isControlPriChannel {
            return kChannelPriIndex
        } else if notification.isControlSecChannel {
            return kChannelSecIndex
        } else {
            Logger.w("Unknown occupancy channel \(notification.channel ?? "null")")
            return -1
        }
    }

}
