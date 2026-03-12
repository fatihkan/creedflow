import Foundation

print("Running CreedFlow Tests...")
print()

NDJSONParserTests.runAll()
DependencyGraphTests.runAll()
DeploymentModelTests.runAll()
DeploymentMigrationTests.runAll()
LocalDeploymentServiceTests.runAll()
GeneratedAssetTests.runAll()
PublishingChannelTests.runAll()
PublicationTests.runAll()
AssetVersioningTests.runAll()
ContentExporterTests.runAll()
PromptRecommenderTests.runAll()
AgentTypeTests.runAll()
MigrationV11V13Tests.runAll()
LocalStorageBackendTests.runAll()
ChainConditionTests.runAll()

print()
print("All tests passed.")
