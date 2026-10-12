@isTest
private with sharing class AgentforcePushRequestAnalysisActionTest {
  @isTest
  static void analyzesDirectPushRequestAndReturnsNoJobs() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    AgentforcePushRequestAnalysisAction.Request inputValue = new AgentforcePushRequestAnalysisAction.Request();
    inputValue.userInput =
      'Analyze ' + AgentforcePushDiagnosticsTestSupport.REQUEST_ID;

    Test.startTest();
    AgentforcePushRequestAnalysisAction.Response ready = AgentforcePushRequestAnalysisAction.analyze(
      new List<AgentforcePushRequestAnalysisAction.Request>{ inputValue }
    )[0];
    stub.jobs.clear();
    AgentforcePushRequestAnalysisAction.Response noJobs = AgentforcePushRequestAnalysisAction.analyze(
      new List<AgentforcePushRequestAnalysisAction.Request>{ inputValue }
    )[0];
    Test.stopTest();

    Assert.areEqual('READY', ready.state, 'Direct 0DV is analyzed');
    Assert.areEqual(
      AgentforcePushDiagnosticsTestSupport.REQUEST_ID,
      ready.pushRequestId,
      'Authoritative request is retained'
    );
    Assert.areEqual('NO_JOBS', noJobs.state, 'Empty cohorts are explicit');
  }

  @isTest
  static void rejectsReplacementAndEnforcesPushPermission() {
    AgentforcePushDiagnosticsTestSupport.readyStub();
    AgentforcePushRequestAnalysisAction.Request invalidInput = new AgentforcePushRequestAnalysisAction.Request();
    invalidInput.userInput = 'Analyze 04t000000000999AAA';
    invalidInput.currentPushRequestId = AgentforcePushDiagnosticsTestSupport.REQUEST_ID;
    AgentforcePushRequestAnalysisAction.Response invalid = AgentforcePushRequestAnalysisAction.analyze(
      new List<AgentforcePushRequestAnalysisAction.Request>{ invalidInput }
    )[0];

    AgentforcePushDiagnosticsService.permissionOverride = false;
    AgentforcePushRequestAnalysisAction.Request forbiddenInput = new AgentforcePushRequestAnalysisAction.Request();
    forbiddenInput.userInput = AgentforcePushDiagnosticsTestSupport.REQUEST_ID;
    AgentforcePushRequestAnalysisAction.Response forbidden = AgentforcePushRequestAnalysisAction.analyze(
      new List<AgentforcePushRequestAnalysisAction.Request>{ forbiddenInput }
    )[0];

    Assert.areEqual('INVALID_ID', invalid.state, 'Wrong type is rejected');
    Assert.isTrue(invalid.clearPreviousContext, 'Stale request is cleared');
    Assert.areEqual(
      'FORBIDDEN',
      forbidden.state,
      'Push permission is enforced'
    );
  }

  @isTest
  static void shouldUsePersistedRequest_WhenNoReplacementAttempted() {
    AgentforcePushDiagnosticsTestSupport.readyStub();
    AgentforcePushRequestAnalysisAction.Request inputValue = new AgentforcePushRequestAnalysisAction.Request();
    inputValue.userInput = 'Compare the sibling failure patterns';
    inputValue.currentPushRequestId = AgentforcePushDiagnosticsTestSupport.REQUEST_ID;

    Test.startTest();
    AgentforcePushRequestAnalysisAction.Response responseValue = AgentforcePushRequestAnalysisAction.analyze(
      new List<AgentforcePushRequestAnalysisAction.Request>{ inputValue }
    )[0];
    Test.stopTest();

    Assert.areEqual(
      'READY',
      responseValue.state,
      'A valid persisted request should support a follow-up turn'
    );
    Assert.areEqual(
      AgentforcePushDiagnosticsTestSupport.REQUEST_ID,
      responseValue.pushRequestId,
      'The persisted request should remain the authoritative context'
    );
    Assert.areEqual(
      false,
      responseValue.clearPreviousContext,
      'A follow-up on the persisted request should not clear context'
    );
  }

  @isTest
  static void shouldReturnUnavailable_WhenCoreObjectsAreUnavailable() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.coreObjectsAvailable = false;
    AgentforcePushRequestAnalysisAction.Request inputValue = new AgentforcePushRequestAnalysisAction.Request();
    inputValue.userInput = AgentforcePushDiagnosticsTestSupport.REQUEST_ID;

    Test.startTest();
    AgentforcePushRequestAnalysisAction.Response responseValue = AgentforcePushRequestAnalysisAction.analyze(
      new List<AgentforcePushRequestAnalysisAction.Request>{ inputValue }
    )[0];
    Test.stopTest();

    Assert.areEqual(
      'UNAVAILABLE',
      responseValue.state,
      'Missing push objects should return an explicit unavailable state'
    );
    Assert.areEqual(
      'Package push-request analysis data is not available in this org.',
      responseValue.message,
      'The unavailable response should be safe and actionable'
    );
  }

  @isTest
  static void shouldReturnSafeError_WhenAuthoritativeQueryFails() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.shouldThrow = true;
    AgentforcePushRequestAnalysisAction.Request inputValue = new AgentforcePushRequestAnalysisAction.Request();
    inputValue.userInput = AgentforcePushDiagnosticsTestSupport.REQUEST_ID;

    Test.startTest();
    AgentforcePushRequestAnalysisAction.Response responseValue = AgentforcePushRequestAnalysisAction.analyze(
      new List<AgentforcePushRequestAnalysisAction.Request>{ inputValue }
    )[0];
    Test.stopTest();

    Assert.areEqual(
      'ERROR',
      responseValue.state,
      'Query failures should return the safe error state'
    );
    Assert.areEqual(
      'Push-request analysis failed safely. Try again later.',
      responseValue.message,
      'Raw query failure details must not be exposed'
    );
    Assert.areEqual(
      null,
      responseValue.pushRequestId,
      'Failed queries should not retain unverified request context'
    );
  }
}
