@isTest
private with sharing class AgentforceCoreConversationActionsTest {
  @isTest
  static void diagnosesFailedBuildAndComparesSiblingSignatures() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService stub = AgentforcePackageIntelligenceTestSupport.readyStub();
    stub.builds.add(
      AgentforcePackageIntelligenceTestSupport.buildRecord(
        AgentforcePackageIntelligenceTestSupport.SECOND_BUILD_ID,
        AgentforcePackageIntelligenceTestSupport.PACKAGE_ID,
        'Error',
        System.now()
      )
    );
    stub.errors.add(
      AgentforcePackageIntelligenceTestSupport.errorRecord(
        '0Xx000000000002AAA',
        AgentforcePackageIntelligenceTestSupport.SECOND_BUILD_ID,
        'Build failed'
      )
    );

    AgentforcePackageBuildDiagnosisAction.Request diagnosisInput = new AgentforcePackageBuildDiagnosisAction.Request();
    diagnosisInput.userInput =
      'Diagnose ' + AgentforcePackageIntelligenceTestSupport.BUILD_ID;
    AgentforcePackageBuildComparisonAction.Request comparisonInput = new AgentforcePackageBuildComparisonAction.Request();
    comparisonInput.currentBuildRequestId = AgentforcePackageIntelligenceTestSupport.BUILD_ID;

    Test.startTest();
    AgentforcePackageBuildDiagnosisAction.Response diagnosis = AgentforcePackageBuildDiagnosisAction.diagnose(
      new List<AgentforcePackageBuildDiagnosisAction.Request>{ diagnosisInput }
    )[0];
    AgentforcePackageBuildComparisonAction.Response comparison = AgentforcePackageBuildComparisonAction.compare(
      new List<AgentforcePackageBuildComparisonAction.Request>{
        comparisonInput
      }
    )[0];
    Test.stopTest();

    Map<String, Object> comparisonPayload = AgentforcePackageIntelligenceTestSupport.jsonMap(
      comparison.comparisonJson
    );
    Map<String, Object> signature = (Map<String, Object>) ((List<Object>) comparisonPayload.get(
      'topFailureSignatures'
    ))[0];
    Assert.areEqual('READY', diagnosis.state, 'Failed build is diagnosable');
    Assert.areEqual(
      AgentforcePackageIntelligenceTestSupport.PACKAGE_ID,
      diagnosis.package2Id,
      'Owning package is authoritative'
    );
    Assert.areEqual('READY', comparison.state, 'Sibling comparison is ready');
    Assert.areEqual(
      2,
      signature.get('affectedBuildCount'),
      'Exact sibling signatures are grouped'
    );
  }

  @isTest
  static void buildReplacementNeverFallsBackToStaleContext() {
    AgentforcePackageIntelligenceTestSupport.readyStub();
    AgentforcePackageBuildDiagnosisAction.Request inputValue = new AgentforcePackageBuildDiagnosisAction.Request();
    inputValue.userInput = 'Diagnose 0DV000000000999AAA';
    inputValue.currentBuildRequestId = AgentforcePackageIntelligenceTestSupport.BUILD_ID;

    Test.startTest();
    AgentforcePackageBuildDiagnosisAction.Response response = AgentforcePackageBuildDiagnosisAction.diagnose(
      new List<AgentforcePackageBuildDiagnosisAction.Request>{ inputValue }
    )[0];
    Test.stopTest();

    Assert.areEqual('INVALID_ID', response.state, 'Wrong type is rejected');
    Assert.isTrue(response.clearPreviousContext, 'Stale evidence is cleared');
    Assert.isNull(response.diagnosticJson, 'No stale evidence is returned');
  }

  @isTest
  static void reviewsSubscriberWithOptionalReadinessContext() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService stub = AgentforcePackageIntelligenceTestSupport.readyStub();
    stub.pushAggregates.add(
      AgentforcePackageIntelligenceTestSupport.pushAggregate(
        AgentforcePackageIntelligenceTestSupport.VERSION_ID,
        1,
        4,
        1
      )
    );
    AgentforceSubscriberSupportAction.Request inputValue = new AgentforceSubscriberSupportAction.Request();
    inputValue.userInput =
      'Review ' + AgentforcePackageIntelligenceTestSupport.SUBSCRIBER_ID;

    Test.startTest();
    AgentforceSubscriberSupportAction.Response response = AgentforceSubscriberSupportAction.review(
      new List<AgentforceSubscriberSupportAction.Request>{ inputValue }
    )[0];
    Test.stopTest();

    Map<String, Object> payload = AgentforcePackageIntelligenceTestSupport.jsonMap(
      response.subscriberJson
    );
    Assert.areEqual('READY', response.state, 'Subscriber context is ready');
    Assert.areEqual(
      AgentforcePackageIntelligenceTestSupport.SUBSCRIBER_PACKAGE_ID,
      payload.get('subscriberPackageId'),
      'Installed package is included'
    );
    Assert.areEqual(
      AgentforcePackageIntelligenceTestSupport.VERSION_ID,
      payload.get('installedPackageVersionId'),
      'Installed version is included'
    );
    Assert.areEqual(
      true,
      payload.get('pushEnrichmentIncluded'),
      'Authorized support context includes aggregate push outcomes'
    );
  }

  @isTest
  static void assessesVersionReadinessDependenciesAndBlockers() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService stub = AgentforcePackageIntelligenceTestSupport.readyStub();
    stub.pushAggregates.add(
      AgentforcePackageIntelligenceTestSupport.pushAggregate(
        AgentforcePackageIntelligenceTestSupport.VERSION_ID,
        1,
        5,
        2
      )
    );
    stub.dependenciesByVersionId.put(
      AgentforcePackageIntelligenceTestSupport.VERSION_ID,
      new List<String>{ '04t000000000099AAA' }
    );
    AgentforcePackageVersionReadinessAction.Request inputValue = new AgentforcePackageVersionReadinessAction.Request();
    inputValue.userInput =
      'Assess ' + AgentforcePackageIntelligenceTestSupport.VERSION_ID;

    Test.startTest();
    AgentforcePackageVersionReadinessAction.Response response = AgentforcePackageVersionReadinessAction.assess(
      new List<AgentforcePackageVersionReadinessAction.Request>{ inputValue }
    )[0];
    Test.stopTest();

    Map<String, Object> payload = AgentforcePackageIntelligenceTestSupport.jsonMap(
      response.readinessJson
    );
    Assert.areEqual('READY', response.state, 'Version is ready for assessment');
    Assert.areEqual(
      1,
      ((List<Object>) payload.get('dependencies')).size(),
      'Dependencies are authoritative'
    );
    Assert.areEqual(
      AgentforcePackageIntelligenceTestSupport.PACKAGE_ID,
      response.package2Id,
      'Owning package is returned'
    );
    Assert.areEqual(
      5,
      ((Map<String, Object>) payload.get('pushOutcomes')).get('jobCount'),
      'Version readiness includes authorized aggregate push outcomes'
    );
  }

  @isTest
  static void returnsExplicitNotFailedNoErrorsAndUnavailableStates() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService notFailed = AgentforcePackageIntelligenceTestSupport.readyStub();
    notFailed.builds[0].status = 'Success';
    AgentforcePackageBuildDiagnosisAction.Response notFailedResponse = diagnoseBuild();

    AgentforcePackageIntelligenceTestSupport.StubQueryService noErrors = AgentforcePackageIntelligenceTestSupport.readyStub();
    noErrors.errors.clear();
    AgentforcePackageBuildDiagnosisAction.Response noErrorsResponse = diagnoseBuild();

    AgentforcePackageIntelligenceTestSupport.StubQueryService unavailable = AgentforcePackageIntelligenceTestSupport.readyStub();
    unavailable.subscriberAvailable = false;
    AgentforceSubscriberSupportAction.Request subscriberInput = new AgentforceSubscriberSupportAction.Request();
    subscriberInput.userInput = AgentforcePackageIntelligenceTestSupport.SUBSCRIBER_ID;
    AgentforceSubscriberSupportAction.Response subscriberResponse = AgentforceSubscriberSupportAction.review(
      new List<AgentforceSubscriberSupportAction.Request>{ subscriberInput }
    )[0];

    Assert.areEqual(
      'NOT_FAILED',
      notFailedResponse.state,
      'Success is explicit'
    );
    Assert.areEqual(
      'NO_ERRORS',
      noErrorsResponse.state,
      'No errors is explicit'
    );
    Assert.areEqual(
      'UNAVAILABLE',
      subscriberResponse.state,
      'Missing PackageSubscriber is explicit'
    );
  }

  @isTest
  static void coreServicesEnforcePermissionBeforeQuerying() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService stub = AgentforcePackageIntelligenceTestSupport.readyStub();
    stub.shouldThrow = true;
    AgentforcePackageIntelligenceService.corePermissionOverride = false;
    AgentforcePackageCoreContextService.ContextInput buildInput = contextInput(
      AgentforcePackageIntelligenceTestSupport.BUILD_ID
    );
    AgentforcePackageCoreContextService.ContextInput subscriberInput = contextInput(
      AgentforcePackageIntelligenceTestSupport.SUBSCRIBER_ID
    );
    AgentforcePackageCoreContextService.ContextInput versionInput = contextInput(
      AgentforcePackageIntelligenceTestSupport.VERSION_ID
    );

    Test.startTest();
    AgentforcePackageCoreContextService.BuildResult buildResult = AgentforcePackageCoreContextService.diagnoseBuilds(
      new List<AgentforcePackageCoreContextService.ContextInput>{ buildInput }
    )[0];
    AgentforcePackageCoreContextService.BuildComparisonResult comparisonResult = AgentforcePackageCoreContextService.compareBuilds(
      new List<String>{ AgentforcePackageIntelligenceTestSupport.BUILD_ID }
    )[0];
    AgentforcePackageCoreContextService.SubscriberResult subscriberResult = AgentforcePackageCoreContextService.reviewSubscribers(
      new List<AgentforcePackageCoreContextService.ContextInput>{
        subscriberInput
      }
    )[0];
    AgentforcePackageCoreContextService.VersionResult versionResult = AgentforcePackageCoreContextService.assessVersions(
      new List<AgentforcePackageCoreContextService.ContextInput>{ versionInput }
    )[0];
    Test.stopTest();

    Assert.areEqual(
      'FORBIDDEN',
      buildResult.state,
      'Build diagnosis requires Package Visualizer Core access'
    );
    Assert.areEqual(
      'FORBIDDEN',
      comparisonResult.state,
      'Build comparison requires Package Visualizer Core access'
    );
    Assert.areEqual(
      'FORBIDDEN',
      subscriberResult.state,
      'Subscriber support requires Package Visualizer Core access'
    );
    Assert.areEqual(
      'FORBIDDEN',
      versionResult.state,
      'Version readiness requires Package Visualizer Core access'
    );
    Assert.isNull(
      buildResult.diagnosticJson,
      'Forbidden build requests must not expose evidence'
    );
    Assert.isNull(
      comparisonResult.comparisonJson,
      'Forbidden comparisons must not expose evidence'
    );
    Assert.isNull(
      subscriberResult.subscriberJson,
      'Forbidden subscriber requests must not expose evidence'
    );
    Assert.isNull(
      versionResult.readinessJson,
      'Forbidden version requests must not expose evidence'
    );
  }

  private static AgentforcePackageCoreContextService.ContextInput contextInput(
    String userInput
  ) {
    AgentforcePackageCoreContextService.ContextInput inputValue = new AgentforcePackageCoreContextService.ContextInput();
    inputValue.userInput = userInput;
    return inputValue;
  }

  private static AgentforcePackageBuildDiagnosisAction.Response diagnoseBuild() {
    AgentforcePackageBuildDiagnosisAction.Request inputValue = new AgentforcePackageBuildDiagnosisAction.Request();
    inputValue.userInput = AgentforcePackageIntelligenceTestSupport.BUILD_ID;
    return AgentforcePackageBuildDiagnosisAction.diagnose(
      new List<AgentforcePackageBuildDiagnosisAction.Request>{ inputValue }
    )[0];
  }
}
