import Foundation
import GRDB
@testable import CreedFlowLib

enum DeploymentModelTests {
    static func runAll() {
        testInsertAndFetchWithNewFields()
        testNewFieldsDefaultToNil()
        testUpdateRuntimeFields()
        testFilterByEnvironment()
        testFilterByStatus()
        print("  DeploymentModelTests: 5/5 passed")
    }

    private static func makeProject(id: UUID = UUID(), in db: Database) throws {
        var project = Project(id: id, name: "Test", description: "Test project")
        try project.insert(db)
    }

    static func testInsertAndFetchWithNewFields() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let deploymentId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            var deployment = Deployment(
                id: deploymentId,
                projectId: projectId,
                environment: .staging,
                status: .pending,
                version: "1.0.0",
                deployMethod: "docker",
                port: 8080,
                containerId: "abc123def456",
                processId: 42
            )
            try deployment.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try Deployment.fetchOne(db, key: deploymentId)
        }

        assertTrue(fetched != nil, "should find deployment")
        let d = fetched!
        assertEq(d.id, deploymentId)
        assertEq(d.projectId, projectId)
        assertEq(d.environment, .staging)
        assertEq(d.status, .pending)
        assertEq(d.version, "1.0.0")
        assertEq(d.deployMethod, "docker")
        assertEq(d.port, 8080)
        assertEq(d.containerId, "abc123def456")
        assertEq(d.processId, 42)
    }

    static func testNewFieldsDefaultToNil() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let deploymentId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            var deployment = Deployment(
                id: deploymentId,
                projectId: projectId,
                version: "1.0.0"
            )
            try deployment.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try Deployment.fetchOne(db, key: deploymentId)
        }!

        assertNil(fetched.deployMethod)
        assertNil(fetched.port)
        assertNil(fetched.containerId)
        assertNil(fetched.processId)
    }

    static func testUpdateRuntimeFields() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let deploymentId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            var deployment = Deployment(
                id: deploymentId,
                projectId: projectId,
                version: "1.0.0"
            )
            try deployment.insert(db)
        }

        // Update with runtime data
        try! appDb.dbQueue.write { db in
            var deployment = try Deployment.fetchOne(db, key: deploymentId)!
            deployment.deployMethod = "direct"
            deployment.port = 3000
            deployment.processId = 9999
            deployment.status = .inProgress
            try deployment.update(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try Deployment.fetchOne(db, key: deploymentId)
        }!

        assertEq(fetched.deployMethod, "direct")
        assertEq(fetched.port, 3000)
        assertEq(fetched.processId, 9999)
        assertNil(fetched.containerId)
        assertEq(fetched.status, .inProgress)
    }

    static func testFilterByEnvironment() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            var staging = Deployment(
                projectId: projectId,
                environment: .staging,
                version: "1.0.0"
            )
            try staging.insert(db)
            var production = Deployment(
                projectId: projectId,
                environment: .production,
                version: "1.0.0"
            )
            try production.insert(db)
        }

        let stagingResults = try! appDb.dbQueue.read { db in
            try Deployment
                .filter(Column("environment") == Deployment.Environment.staging.rawValue)
                .fetchAll(db)
        }
        assertEq(stagingResults.count, 1)
        assertEq(stagingResults[0].environment, .staging)

        let productionResults = try! appDb.dbQueue.read { db in
            try Deployment
                .filter(Column("environment") == Deployment.Environment.production.rawValue)
                .fetchAll(db)
        }
        assertEq(productionResults.count, 1)
        assertEq(productionResults[0].environment, .production)
    }

    static func testFilterByStatus() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            var pending = Deployment(
                projectId: projectId,
                status: .pending,
                version: "1.0.0"
            )
            try pending.insert(db)
            var success = Deployment(
                projectId: projectId,
                status: .success,
                version: "1.1.0"
            )
            try success.insert(db)
            var failed = Deployment(
                projectId: projectId,
                status: .failed,
                version: "1.2.0"
            )
            try failed.insert(db)
        }

        let pendingResults = try! appDb.dbQueue.read { db in
            try Deployment
                .filter(Column("status") == Deployment.Status.pending.rawValue)
                .fetchAll(db)
        }
        assertEq(pendingResults.count, 1)
        assertEq(pendingResults[0].status, .pending)

        let successResults = try! appDb.dbQueue.read { db in
            try Deployment
                .filter(Column("status") == Deployment.Status.success.rawValue)
                .fetchAll(db)
        }
        assertEq(successResults.count, 1)
        assertEq(successResults[0].status, .success)

        let failedResults = try! appDb.dbQueue.read { db in
            try Deployment
                .filter(Column("status") == Deployment.Status.failed.rawValue)
                .fetchAll(db)
        }
        assertEq(failedResults.count, 1)
        assertEq(failedResults[0].status, .failed)
    }
}
