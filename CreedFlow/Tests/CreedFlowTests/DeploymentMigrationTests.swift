import Foundation
import GRDB
@testable import CreedFlowLib

enum DeploymentMigrationTests {
    static func runAll() {
        testV5ColumnsExist()
        testV5ColumnsNullable()
        print("  DeploymentMigrationTests: 2/2 passed")
    }

    static func testV5ColumnsExist() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let deploymentId = UUID()

        // Insert a deployment with all v5 columns populated
        try! appDb.dbQueue.write { db in
            var project = Project(id: projectId, name: "Migration", description: "Test")
            try project.insert(db)
            var deployment = Deployment(
                id: deploymentId,
                projectId: projectId,
                version: "2.0.0",
                deployMethod: "docker-compose",
                port: 9090,
                containerId: "container789",
                processId: 1234
            )
            try deployment.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try Deployment.fetchOne(db, key: deploymentId)
        }

        assertTrue(fetched != nil, "deployment with v5 columns should be fetchable")
        assertEq(fetched!.deployMethod, "docker-compose")
        assertEq(fetched!.port, 9090)
        assertEq(fetched!.containerId, "container789")
        assertEq(fetched!.processId, 1234)
    }

    static func testV5ColumnsNullable() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let deploymentId = UUID()

        // Insert a deployment without any v5 columns
        try! appDb.dbQueue.write { db in
            var project = Project(id: projectId, name: "Migration", description: "Test")
            try project.insert(db)
            var deployment = Deployment(
                id: deploymentId,
                projectId: projectId,
                version: "1.0.0"
            )
            try deployment.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try Deployment.fetchOne(db, key: deploymentId)
        }

        assertTrue(fetched != nil, "deployment without v5 columns should be fetchable")
        assertNil(fetched!.deployMethod)
        assertNil(fetched!.port)
        assertNil(fetched!.containerId)
        assertNil(fetched!.processId)
    }
}
