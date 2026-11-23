import Foundation
import SwiftData

extension ModelContext {
    func all<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try fetch(FetchDescriptor<T>())
    }
}

/// 当前库结构。备份里的 formatVersion 与这里对齐。
enum EstateSchemaV2 {
    static let version = 2
}

enum EstateMigrationPlan {
    static let current = EstateSchemaV2.version
}

enum EstateSchema {
    static let version = EstateSchemaV2.version

    static var models: [any PersistentModel.Type] {
        [
            Community.self,
            Contact.self,
            Property.self,
            MediaAsset.self,
            PropertyStatusEvent.self,
            ClientNeed.self,
            FollowUp.self,
            Viewing.self,
            ViewingItem.self,
            Deal.self,
            DealCommissionAllocation.self,
            MarketComparable.self,
            TaskItem.self,
            WorkspaceRecord.self
        ]
    }

    static var schema: Schema {
        Schema(models)
    }
}
