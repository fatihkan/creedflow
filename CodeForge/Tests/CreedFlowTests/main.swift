import Foundation

print("Running CreedFlow Tests...")
print()

NDJSONParserTests.runAll()
DependencyGraphTests.runAll()
DeploymentModelTests.runAll()
DeploymentMigrationTests.runAll()
LocalDeploymentServiceTests.runAll()

print()
print("All tests passed.")
