//
//  Item.swift
//  HandyApp3
//
//  Created by Hao Deng on 5/2/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
