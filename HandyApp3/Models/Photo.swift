import Foundation
import Observation

@Observable
final class Photo: Identifiable, Equatable {
    let id: UUID
    var imageData: Data?        // nil after load; populated lazily by views via PhotoStorage
    var thumbnailData: Data?    // nil after load; populated lazily by views via PhotoStorage
    var caption: String
    let addedDate: Date

    /// Absolute instant of the last edit to this photo, including its tombstoning.
    /// `Date` is timezone-free; persisted as ISO-8601 UTC.
    var modifyDate: Date

    var isDeleted: Bool = false
    var deletedAt: Date? = nil

    init(id: UUID = UUID(), imageData: Data? = nil, thumbnailData: Data? = nil, caption: String = "", addedDate: Date = Date(), modifyDate: Date = Date()) {
        self.id = id
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.caption = caption
        self.addedDate = addedDate
        self.modifyDate = modifyDate
    }

    /// Stamps the photo as edited now. Called from AssetStore after any write.
    func touch(_ date: Date = Date()) {
        modifyDate = date
    }

    static func == (lhs: Photo, rhs: Photo) -> Bool { lhs.id == rhs.id }
}
