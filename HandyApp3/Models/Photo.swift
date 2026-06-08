import Foundation
import Observation

@Observable
final class Photo: Identifiable, Equatable {
    let id: UUID
    var imageData: Data
    var thumbnailData: Data
    var caption: String
    let addedDate: Date

    init(id: UUID = UUID(), imageData: Data, thumbnailData: Data, caption: String = "", addedDate: Date = Date()) {
        self.id = id
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.caption = caption
        self.addedDate = addedDate
    }

    static func == (lhs: Photo, rhs: Photo) -> Bool { lhs.id == rhs.id }
}
