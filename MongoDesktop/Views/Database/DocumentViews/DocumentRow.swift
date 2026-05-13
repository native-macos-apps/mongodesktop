import Foundation
import SwiftBSON

// MARK: - DocumentRow

struct DocumentRow: Identifiable {
    let id: String
    let document: BSONDocument

    init(document: BSONDocument, fallbackIndex: Int) {
        self.document = document
        if let rawId = document["_id"] {
            self.id = "id-\(String(describing: rawId))"
        } else {
            self.id = "row-\(fallbackIndex)"
        }
    }
}
