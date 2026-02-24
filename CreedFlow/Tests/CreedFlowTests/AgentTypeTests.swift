import Foundation
@testable import CreedFlowLib

enum AgentTypeTests {
    static func runAll() {
        testAllElevenAgentTypes()
        testAgentTypeRawValues()
        testAgentTypeCaseIterable()
        testStatusRawValues()
        testStatusDisplayNames()
        testAgentTypeThemeColors()
        testAgentTypeIcons()
        print("  AgentTypeTests: 7/7 passed")
    }

    static func testAllElevenAgentTypes() {
        let types = AgentTask.AgentType.allCases
        assertEq(types.count, 11)
    }

    static func testAgentTypeRawValues() {
        assertEq(AgentTask.AgentType.analyzer.rawValue, "analyzer")
        assertEq(AgentTask.AgentType.coder.rawValue, "coder")
        assertEq(AgentTask.AgentType.reviewer.rawValue, "reviewer")
        assertEq(AgentTask.AgentType.tester.rawValue, "tester")
        assertEq(AgentTask.AgentType.devops.rawValue, "devops")
        assertEq(AgentTask.AgentType.monitor.rawValue, "monitor")
        assertEq(AgentTask.AgentType.contentWriter.rawValue, "contentWriter")
        assertEq(AgentTask.AgentType.designer.rawValue, "designer")
        assertEq(AgentTask.AgentType.imageGenerator.rawValue, "imageGenerator")
        assertEq(AgentTask.AgentType.videoEditor.rawValue, "videoEditor")
        assertEq(AgentTask.AgentType.publisher.rawValue, "publisher")
    }

    static func testAgentTypeCaseIterable() {
        // Verify each type can be constructed from rawValue
        for type in AgentTask.AgentType.allCases {
            let reconstructed = AgentTask.AgentType(rawValue: type.rawValue)
            assertTrue(reconstructed != nil, "should reconstruct \(type.rawValue)")
            assertEq(reconstructed!, type)
        }
    }

    static func testStatusRawValues() {
        assertEq(AgentTask.Status.queued.rawValue, "queued")
        assertEq(AgentTask.Status.inProgress.rawValue, "in_progress")
        assertEq(AgentTask.Status.passed.rawValue, "passed")
        assertEq(AgentTask.Status.failed.rawValue, "failed")
        assertEq(AgentTask.Status.needsRevision.rawValue, "needs_revision")
        assertEq(AgentTask.Status.cancelled.rawValue, "cancelled")
    }

    static func testStatusDisplayNames() {
        assertEq(AgentTask.Status.queued.displayName, "Queued")
        assertEq(AgentTask.Status.inProgress.displayName, "In Progress")
        assertEq(AgentTask.Status.passed.displayName, "Passed")
        assertEq(AgentTask.Status.failed.displayName, "Failed")
        assertEq(AgentTask.Status.needsRevision.displayName, "Needs Revision")
        assertEq(AgentTask.Status.cancelled.displayName, "Cancelled")
    }

    static func testAgentTypeThemeColors() {
        // Just verify every agent type has a theme color (doesn't crash)
        for type in AgentTask.AgentType.allCases {
            let _ = type.themeColor
        }
    }

    static func testAgentTypeIcons() {
        // Verify every agent type has an icon string
        for type in AgentTask.AgentType.allCases {
            let icon = type.icon
            assertTrue(!icon.isEmpty, "icon should not be empty for \(type.rawValue)")
        }
    }
}
