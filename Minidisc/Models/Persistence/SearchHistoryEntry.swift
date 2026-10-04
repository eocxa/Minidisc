import Foundation
import SwiftData

@Model
final class SearchHistoryEntry {
    @Attribute(.unique) var entryId: String  // composite: "\(serverId)_\(itemId)"
    var itemId: String
    var itemType: String        // "album" | "artist"
    var displayName: String
    var coverArtId: String?
    var serverId: String        // UUID as String for predicate compat
    var visitedAt: Date
    var artistName: String? = nil
    var albumName: String? = nil

    init(itemId: String, itemType: String, displayName: String,
         coverArtId: String?, serverId: String,
         artistName: String? = nil, albumName: String? = nil) {
        self.entryId     = "\(serverId)_\(itemId)"
        self.itemId      = itemId
        self.itemType    = itemType
        self.displayName = displayName
        self.coverArtId  = coverArtId
        self.serverId    = serverId
        self.visitedAt   = Date()
        self.artistName  = artistName
        self.albumName   = albumName
    }
}
