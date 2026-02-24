import Foundation
@testable import CreedLib

enum DependencyGraphTests {
    static func runAll() {
        testSimpleTopologicalSort()
        testCycleDetectionThrows()
        testWouldCreateCycle()
        testReadyTasksNoDeps()
        testReadyTasksPartialComplete()
        testEmptyGraph()
        testDiamondDependencyGraph()
        print("  DependencyGraphTests: 7/7 passed")
    }

    static func testSimpleTopologicalSort() {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()
        let c = UUID()

        graph.addNode(a)
        graph.addNode(b)
        graph.addNode(c)
        graph.addDependency(task: b, dependsOn: a)
        graph.addDependency(task: c, dependsOn: b)

        let sorted = try! graph.topologicalSort()
        assertEq(sorted.count, 3)

        let indexA = sorted.firstIndex(of: a)!
        let indexB = sorted.firstIndex(of: b)!
        let indexC = sorted.firstIndex(of: c)!
        assertTrue(indexA < indexB)
        assertTrue(indexB < indexC)
    }

    static func testCycleDetectionThrows() {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()

        graph.addDependency(task: a, dependsOn: b)
        graph.addDependency(task: b, dependsOn: a)

        do {
            _ = try graph.topologicalSort()
            fatalError("Expected cycle error")
        } catch {
            // Expected
        }
    }

    static func testWouldCreateCycle() {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()
        let c = UUID()

        graph.addDependency(task: b, dependsOn: a)
        graph.addDependency(task: c, dependsOn: b)

        assertTrue(graph.wouldCreateCycle(task: a, dependsOn: c))

        let d = UUID()
        graph.addNode(d)
        assertTrue(!graph.wouldCreateCycle(task: a, dependsOn: d))
    }

    static func testReadyTasksNoDeps() {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()

        graph.addNode(a)
        graph.addNode(b)

        let ready = graph.readyTasks(completedTasks: [])
        assertEq(ready.count, 2)
    }

    static func testReadyTasksPartialComplete() {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()
        let c = UUID()

        graph.addDependency(task: b, dependsOn: a)
        graph.addDependency(task: c, dependsOn: a)

        var ready = graph.readyTasks(completedTasks: [])
        assertEq(ready.count, 1)
        assertTrue(ready.contains(a))

        ready = graph.readyTasks(completedTasks: [a])
        assertEq(ready.count, 2)
        assertTrue(ready.contains(b))
        assertTrue(ready.contains(c))
    }

    static func testEmptyGraph() {
        let graph = DependencyGraph()
        let sorted = try! graph.topologicalSort()
        assertTrue(sorted.isEmpty)
    }

    static func testDiamondDependencyGraph() {
        var graph = DependencyGraph()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()

        graph.addDependency(task: b, dependsOn: a)
        graph.addDependency(task: c, dependsOn: a)
        graph.addDependency(task: d, dependsOn: b)
        graph.addDependency(task: d, dependsOn: c)

        let sorted = try! graph.topologicalSort()
        assertEq(sorted.count, 4)

        let indexA = sorted.firstIndex(of: a)!
        let indexB = sorted.firstIndex(of: b)!
        let indexC = sorted.firstIndex(of: c)!
        let indexD = sorted.firstIndex(of: d)!

        assertTrue(indexA < indexB)
        assertTrue(indexA < indexC)
        assertTrue(indexB < indexD)
        assertTrue(indexC < indexD)
    }
}
