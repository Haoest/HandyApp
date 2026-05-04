//
//  WxLxHCompositeType.swift
//  HandyApp3
//
//  Created by Hao Deng on 5/3/26.
//

import Foundation

// MARK: - W × L × H System Type

extension BuiltInTypes {

    /// Width × Length × Height composite with an optional Unit label.
    ///
    /// Typical use cases: room dimensions, furniture size, box/storage volume.
    ///
    /// Fields:
    ///   • Width  — Number   (required)
    ///   • Length — Number   (required)
    ///   • Height — Number   (required)
    ///   • Unit   — Text     (optional, e.g. UnitIndex.feet.symbol → "ft")
    static func widthByLengthByHeight(scope: CompositeTypeScope = .global) -> CompositeTypeDefinition {
        CompositeTypeDefinition(
            name: "W × L × H",
            systemFields: [
                PropertyDefinition(name: "Width",  type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Length", type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Height", type: .basic(.number), isRequired: true),
                PropertyDefinition(name: "Unit",   type: .basic(.text),   isRequired: false),
            ],
            isUserExtensible: false,
            scope: scope
        )
    }
}
