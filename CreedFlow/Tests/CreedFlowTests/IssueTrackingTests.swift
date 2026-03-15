import Foundation
import GRDB
@testable import CreedFlowLib

// MARK: - IssueTrackingConfig Tests

enum IssueTrackingConfigTests {
    static func runAll() {
        testInsertAndFetch()
        testProviderEnum()
        testFilterByProject()
        testUpdateConfig()
        testCascadeDeleteOnProject()
        print("  IssueTrackingConfigTests: 5/5 passed")
    }

    static func testInsertAndFetch() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let configId = UUID()

        try! appDb.dbQueue.write { db in
            var project = Project(id: projectId, name: "Test", description: "Test project")
            try project.insert(db)

            var config = IssueTrackingConfig(
                id: configId,
                projectId: projectId,
                provider: .linear,
                name: "My Linear",
                credentialsJSON: "{\"apiKey\":\"lin_api_test\"}",
                configJSON: "{\"teamId\":\"team-123\"}",
                isEnabled: true,
                syncBackEnabled: true
            )
            try config.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try IssueTrackingConfig.fetchOne(db, id: configId)
        }

        assertTrue(fetched != nil)
        assertEq(fetched!.name, "My Linear")
        assertEq(fetched!.provider, .linear)
        assertEq(fetched!.credentialsJSON, "{\"apiKey\":\"lin_api_test\"}")
        assertEq(fetched!.configJSON, "{\"teamId\":\"team-123\"}")
        assertTrue(fetched!.isEnabled)
        assertTrue(fetched!.syncBackEnabled)
        assertNil(fetched!.lastSyncAt)
    }

    static func testProviderEnum() {
        let providers: [IssueTrackingConfig.Provider] = [.linear, .jira]
        assertEq(providers.count, 2)
        assertEq(IssueTrackingConfig.Provider.linear.rawValue, "linear")
        assertEq(IssueTrackingConfig.Provider.jira.rawValue, "jira")
    }

    static func testFilterByProject() {
        let appDb = try! AppDatabase.makeEmpty()
        let project1 = UUID()
        let project2 = UUID()

        try! appDb.dbQueue.write { db in
            var p1 = Project(id: project1, name: "P1", description: "P1")
            try p1.insert(db)
            var p2 = Project(id: project2, name: "P2", description: "P2")
            try p2.insert(db)

            var c1 = IssueTrackingConfig(projectId: project1, provider: .linear, name: "Linear 1")
            try c1.insert(db)
            var c2 = IssueTrackingConfig(projectId: project1, provider: .jira, name: "Jira 1")
            try c2.insert(db)
            var c3 = IssueTrackingConfig(projectId: project2, provider: .linear, name: "Linear 2")
            try c3.insert(db)
        }

        let p1Configs = try! appDb.dbQueue.read { db in
            try IssueTrackingConfig
                .filter(Column("projectId") == project1)
                .fetchAll(db)
        }
        assertEq(p1Configs.count, 2)
    }

    static func testUpdateConfig() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let configId = UUID()

        try! appDb.dbQueue.write { db in
            var project = Project(id: projectId, name: "Test", description: "Test")
            try project.insert(db)
            var config = IssueTrackingConfig(
                id: configId,
                projectId: projectId,
                provider: .linear,
                name: "Old Name",
                isEnabled: true,
                syncBackEnabled: false
            )
            try config.insert(db)
        }

        try! appDb.dbQueue.write { db in
            var config = try IssueTrackingConfig.fetchOne(db, id: configId)!
            config.name = "New Name"
            config.syncBackEnabled = true
            config.updatedAt = Date()
            try config.update(db)
        }

        let updated = try! appDb.dbQueue.read { db in
            try IssueTrackingConfig.fetchOne(db, id: configId)!
        }
        assertEq(updated.name, "New Name")
        assertTrue(updated.syncBackEnabled)
    }

    static func testCascadeDeleteOnProject() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()

        try! appDb.dbQueue.write { db in
            var project = Project(id: projectId, name: "Test", description: "Test")
            try project.insert(db)
            var config = IssueTrackingConfig(projectId: projectId, provider: .linear, name: "Linear")
            try config.insert(db)
        }

        // Delete the project — config should cascade
        try! appDb.dbQueue.write { db in
            _ = try Project.deleteOne(db, id: projectId)
        }

        let configs = try! appDb.dbQueue.read { db in
            try IssueTrackingConfig.fetchAll(db)
        }
        assertEq(configs.count, 0)
    }
}

// MARK: - IssueMapping Tests

enum IssueMappingTests {
    static func runAll() {
        testInsertAndFetch()
        testSyncStatusEnum()
        testUniqueConstraint()
        testCascadeDeleteOnConfig()
        testFilterByConfig()
        print("  IssueMappingTests: 5/5 passed")
    }

    private static func makePrereqs(in db: Database) -> (projectId: UUID, taskId: UUID, configId: UUID) {
        let projectId = UUID()
        let taskId = UUID()
        let configId = UUID()

        var project = Project(id: projectId, name: "Test", description: "Test")
        try! project.insert(db)
        var task = AgentTask(id: taskId, projectId: projectId, agentType: .coder, title: "Fix bug", description: "Fix the bug")
        try! task.insert(db)
        var config = IssueTrackingConfig(id: configId, projectId: projectId, provider: .linear, name: "Linear")
        try! config.insert(db)

        return (projectId, taskId, configId)
    }

    static func testInsertAndFetch() {
        let appDb = try! AppDatabase.makeEmpty()
        let mappingId = UUID()

        try! appDb.dbQueue.write { db in
            let prereqs = makePrereqs(in: db)
            var mapping = IssueMapping(
                id: mappingId,
                configId: prereqs.configId,
                taskId: prereqs.taskId,
                externalIssueId: "ext-123",
                externalIdentifier: "ENG-123",
                externalUrl: "https://linear.app/team/issue/ENG-123"
            )
            try mapping.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try IssueMapping.fetchOne(db, id: mappingId)
        }

        assertTrue(fetched != nil)
        assertEq(fetched!.externalIssueId, "ext-123")
        assertEq(fetched!.externalIdentifier, "ENG-123")
        assertEq(fetched!.externalUrl, "https://linear.app/team/issue/ENG-123")
        assertEq(fetched!.syncStatus, .imported)
        assertNil(fetched!.lastSyncedAt)
    }

    static func testSyncStatusEnum() {
        let statuses: [IssueMapping.SyncStatus] = [.imported, .synced, .syncFailed]
        assertEq(statuses.count, 3)
        assertEq(IssueMapping.SyncStatus.imported.rawValue, "imported")
        assertEq(IssueMapping.SyncStatus.synced.rawValue, "synced")
        assertEq(IssueMapping.SyncStatus.syncFailed.rawValue, "sync_failed")
    }

    static func testUniqueConstraint() {
        let appDb = try! AppDatabase.makeEmpty()
        var caughtError = false

        try! appDb.dbQueue.write { db in
            let prereqs = makePrereqs(in: db)

            // First mapping
            var m1 = IssueMapping(
                configId: prereqs.configId,
                taskId: prereqs.taskId,
                externalIssueId: "ext-dup",
                externalIdentifier: "ENG-1"
            )
            try m1.insert(db)

            // Second task for same project
            let task2Id = UUID()
            var task2 = AgentTask(id: task2Id, projectId: prereqs.projectId, agentType: .coder, title: "Another", description: "Another task")
            try task2.insert(db)

            // Duplicate mapping (same configId + externalIssueId) should fail
            do {
                var m2 = IssueMapping(
                    configId: prereqs.configId,
                    taskId: task2Id,
                    externalIssueId: "ext-dup",
                    externalIdentifier: "ENG-1"
                )
                try m2.insert(db)
            } catch {
                caughtError = true
            }
        }

        assertTrue(caughtError)
    }

    static func testCascadeDeleteOnConfig() {
        let appDb = try! AppDatabase.makeEmpty()
        var configId: UUID!

        try! appDb.dbQueue.write { db in
            let prereqs = makePrereqs(in: db)
            configId = prereqs.configId

            var mapping = IssueMapping(
                configId: prereqs.configId,
                taskId: prereqs.taskId,
                externalIssueId: "ext-456",
                externalIdentifier: "ENG-456"
            )
            try mapping.insert(db)
        }

        // Delete config — mappings should cascade
        try! appDb.dbQueue.write { db in
            _ = try IssueTrackingConfig.deleteOne(db, id: configId)
        }

        let mappings = try! appDb.dbQueue.read { db in
            try IssueMapping.fetchAll(db)
        }
        assertEq(mappings.count, 0)
    }

    static func testFilterByConfig() {
        let appDb = try! AppDatabase.makeEmpty()

        try! appDb.dbQueue.write { db in
            let projectId = UUID()
            var project = Project(id: projectId, name: "Test", description: "Test")
            try project.insert(db)

            let config1 = UUID()
            let config2 = UUID()
            var c1 = IssueTrackingConfig(id: config1, projectId: projectId, provider: .linear, name: "Linear 1")
            try c1.insert(db)
            var c2 = IssueTrackingConfig(id: config2, projectId: projectId, provider: .linear, name: "Linear 2")
            try c2.insert(db)

            let task1 = UUID()
            let task2 = UUID()
            let task3 = UUID()
            var t1 = AgentTask(id: task1, projectId: projectId, agentType: .coder, title: "T1", description: "T1")
            try t1.insert(db)
            var t2 = AgentTask(id: task2, projectId: projectId, agentType: .coder, title: "T2", description: "T2")
            try t2.insert(db)
            var t3 = AgentTask(id: task3, projectId: projectId, agentType: .coder, title: "T3", description: "T3")
            try t3.insert(db)

            var m1 = IssueMapping(configId: config1, taskId: task1, externalIssueId: "a", externalIdentifier: "ENG-1")
            try m1.insert(db)
            var m2 = IssueMapping(configId: config1, taskId: task2, externalIssueId: "b", externalIdentifier: "ENG-2")
            try m2.insert(db)
            var m3 = IssueMapping(configId: config2, taskId: task3, externalIssueId: "c", externalIdentifier: "ENG-3")
            try m3.insert(db)
        }

        let all = try! appDb.dbQueue.read { db in
            try IssueMapping.fetchAll(db)
        }
        assertEq(all.count, 3)
    }
}
