//
//  SourceEntity.swift
//  OwnFrame
//
//  800 (T024): the App Intents entity for a saved source — id + label projected
//  from the topic-120 library via the registry's sourceOptions closure, the same
//  list the HA select shows (FR-800-06). The id is stable across renames; apply
//  resolves the label from the current library (contracts § SourceEntity).
//

import AppIntents
import AppIntentsKit

struct SourceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Frame Source"
    static let defaultQuery = SourceEntityQuery()

    let id: String
    let label: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)")
    }
}

struct SourceEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SourceEntity] {
        let options = try FrameIntentContext.requireRegistry().sourceOptions()
        return identifiers.compactMap { id in
            options.first { $0.id == id }.map { SourceEntity(id: $0.id, label: $0.label) }
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [SourceEntity] {
        try FrameIntentContext.requireRegistry().sourceOptions()
            .map { SourceEntity(id: $0.id, label: $0.label) }
    }
}
