import Foundation
import Observation

@Observable
final class Photo: Identifiable, Equatable {
    let id: UUID
    var imageData: Data?        // nil after load; populated lazily by views via PhotoStorage
    var thumbnailData: Data?    // nil after load; populated lazily by views via PhotoStorage
    var caption: String
    let addedDate: Date

    init(id: UUID = UUID(), imageData: Data? = nil, thumbnailData: Data? = nil, caption: String = "", addedDate: Date = Date()) {
        self.id = id
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.caption = caption
        self.addedDate = addedDate
    }

    static func == (lhs: Photo, rhs: Photo) -> Bool { lhs.id == rhs.id }
}
