import XCTest
import Foundation
@testable import CodeForge

final class DependencyGraphTests: XCTestCase {

    func testSimpleTopologicalSort() throws {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()
        let c = UUID()

        graph.addNode(a)
        graph.addNode(b)
        graph.addNode(c)
        graph.addDependency(task: b, dependsOn: a)
        graph.addDependency(task: c, dependsOn: b)

        let sorted = try graph.topologicalSort()
        XCTAssertEqual(sorted.count, 3)

        let indexA = sorted.firstIndex(of: a)!
        let indexB = sorted.firstIndex(of: b)!
        let indexC = sorted.firstIndex(of: c)!
        XCTAssertLessThan(indexA, indexB)
        XCTAssertLessThan(indexB, indexC)
    }

    func testCycleDetectionThrows() {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()

        graph.addDependency(task: a, dependsOn: b)
        graph.addDependency(task: b, dependsOn: a)

        XCTAssertThrowsError(try graph.topologicalSort())
    }

    func testWouldCreateCycle() {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()
        let c = UUID()

        graph.addDependency(task: b, dependsOn: a)
        graph.addDependency(task: c, dependsOn: b)

        XCTAssertTrue(graph.wouldCreateCycle(task: a, dependsOn: c))

        let d = UUID()
        graph.addNode(d)
        XCTAssertFalse(graph.wouldCreateCycle(task: a, dependsOn: d))
    }

    func testReadyTasksNoDeps() {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()

        graph.addNode(a)
        graph.addNode(b)

        let ready = graph.readyTasks(completedTasks: [])
        XCTAssertEqual(ready.count, 2)
    }

    func testReadyTasksPartialComplete() {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()
        let c = UUID()

        graph.addDependency(task: b, dependsOn: a)
        graph.addDependency(task: c, dependsOn: a)

        var ready = graph.readyTasks(completedTasks: [])
        XCTAssertEqual(ready.count, 1)
        XCTAssertTrue(ready.contains(a))

        ready = graph.readyTasks(completedTasks: [a])
        XCTAssertEqual(ready.count, 2)
        XCTAssertTrue(ready.contains(b))
        XCTAssertTrue(ready.contains(c))
    }

    func testEmptyGraph() throws {
        let graph = DependencyGraph()
        let sorted = try graph.topologicalSort()
        XCTAssertTrue(sorted.isEmpty)
    }

    func testDiamondDependencyGraph() throws {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()

        graph.addDependency(task: b, dependsOn: a)
        graph.addDependency(task: c, dependsOn: a)
        graph.addDependency(task: d, dependsOn: b)
        graph.addDependency(task: d, dependsOn: c)

        let sorted = try graph.topologicalSort()
        XCTAssertEqual(sorted.count, 4)

        let indexA = sorted.firstIndex(of: a)!
        let indexB = sorted.firstIndex(of: b)!
        let indexC = sorted.firstIndex(of: c)!
        let indexD = sorted.firstIndex(of: d)!

        XCTAssertLessThan(indexA, indexB)
        XCTAssertLessThan(indexA, indexC)
        XCTAssertLessThan(indexB, indexD)
        XCTAssertLessThan(indexC, indexD)
    }
}
