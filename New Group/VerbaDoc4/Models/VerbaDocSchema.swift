import SwiftData
import Foundation

// MARK: - Schema Versioning
//
// VerbaDoc uses explicit schema versioning to guarantee safe migrations for
// all users, regardless of which version they last installed.
//
// Lightweight migration rules (SwiftData handles automatically):
//   - Adding optional properties       → safe, no plan needed
//   - Adding properties with defaults  → safe, no plan needed
//   - Removing properties              → data loss (never do this silently)
//   - Changing property types          → crash (requires migration stage)
//
// V1 → V2: added `lastModified: Date` to Document and StudyItem (default: Date())
//           This is a lightweight migration — no explicit stage required.
//           Existing rows get `lastModified = Date()` which is safe.
//
// HOW TO ADD A FUTURE MIGRATION:
//   1. Bump the version below
//   2. Create a new VersionedSchema enum (e.g. VerbaDocSchemaV3)
//   3. Add a MigrationStage to VerbaDocMigrationPlan
//   4. Update ModelContainer in VerbaDoc4App.swift

enum VerbaDocSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Document.self, StudyItem.self] }
}

enum VerbaDocSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Document.self, StudyItem.self] }
}

// V1 → V2 is a lightweight migration (new fields with defaults).
// SwiftData does not require an explicit stage — declaring the plan is
// enough to signal intentionality and enable future stages.
enum VerbaDocMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [VerbaDocSchemaV1.self, VerbaDocSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // Lightweight: SwiftData adds columns with default values automatically.
    // No custom willMigrate / didMigrate logic needed for this version.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: VerbaDocSchemaV1.self,
        toVersion:   VerbaDocSchemaV2.self
    )
}
