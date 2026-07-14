import CoreData
import Foundation

final class PersistenceController {
    let container: NSPersistentContainer

    init(
        storeDescription: NSPersistentStoreDescription? = nil,
        fileManager: FileManager = .default
    ) async throws {
        container = NSPersistentContainer(
            name: "PureVoice",
            managedObjectModel: Self.makeModel()
        )

        if let storeDescription {
            container.persistentStoreDescriptions = [storeDescription]
        } else {
            container.persistentStoreDescriptions = [try Self.productionStoreDescription(fileManager: fileManager)]
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        let viewContext = container.viewContext
        await viewContext.perform {
            viewContext.automaticallyMergesChangesFromParent = true
            viewContext.mergePolicy = NSMergePolicy(
                merge: .mergeByPropertyObjectTrumpMergePolicyType
            )
        }
    }

    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "BookEntity"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        entity.properties = [
            attribute("id", type: .UUIDAttributeType, optional: false),
            attribute("title", type: .stringAttributeType, optional: false),
            attribute("author", type: .stringAttributeType, optional: false),
            attribute("format", type: .stringAttributeType, optional: false),
            attribute("originalFileURL", type: .URIAttributeType, optional: false),
            attribute("canonicalFileURL", type: .URIAttributeType, optional: false),
            attribute("coverFileURL", type: .URIAttributeType, optional: true),
            attribute("position", type: .binaryDataAttributeType, optional: true),
            attribute("lastOpenedAt", type: .dateAttributeType, optional: true),
            attribute("createdAt", type: .dateAttributeType, optional: false)
        ]
        entity.uniquenessConstraints = [["id"]]
        model.entities = [entity]
        return model
    }

    private static func attribute(
        _ name: String,
        type: NSAttributeType,
        optional: Bool
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }

    private static func productionStoreDescription(
        fileManager: FileManager
    ) throws -> NSPersistentStoreDescription {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("PureVoice", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let description = NSPersistentStoreDescription(
            url: directory.appendingPathComponent("PureVoice.sqlite")
        )
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }
}
