/**
 * Tests the read-only Agentforce push-job diagnosis action contract.
 */
@isTest
private with sharing class AgentforcePushDiagnosticsActionTest {
  @isTest
  static void shouldDiagnoseNewJobAndCollapseExactDuplicateErrors() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.errors.add(
      AgentforcePushDiagnosticsTestSupport.errorRecord(
        '0Yx000000000002AAA',
        AgentforcePushDiagnosticsTestSupport.JOB_ID,
        'Same failure'
      )
    );

    Test.startTest();
    AgentforcePushJobDiagnosisAction.Response response = AgentforcePushJobDiagnosisAction.diagnose(
      new List<AgentforcePushJobDiagnosisAction.Request>{
        AgentforcePushDiagnosticsTestSupport.diagnosisRequest(
          'Please diagnose ' + AgentforcePushDiagnosticsTestSupport.JOB_ID,
          AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID
        )
      }
    )[0];
    Test.stopTest();

    Map<String, Object> payload = AgentforcePushDiagnosticsTestSupport.jsonMap(
      response.diagnosticJson
    );
    List<Object> uniqueErrors = (List<Object>) payload.get('errors');
    Map<String, Object> collapsedError = (Map<String, Object>) uniqueErrors[0];

    Assert.areEqual(
      'READY',
      response.state,
      'A failed job with errors is ready'
    );
    Assert.isTrue(
      response.clearPreviousContext,
      'Explicit jobs replace context'
    );
    Assert.areEqual(
      AgentforcePushDiagnosticsTestSupport.JOB_ID,
      response.jobId,
      'The explicit job should win'
    );
    Assert.areEqual(
      AgentforcePushDiagnosticsTestSupport.REQUEST_ID,
      response.pushRequestId,
      'Request ID should return'
    );
    Assert.areEqual(
      AgentforcePushDiagnosticsTestSupport.VERSION_ID,
      response.targetPackageVersionId,
      'Target version should return'
    );
    Assert.areEqual(1, uniqueErrors.size(), 'Exact duplicates should collapse');
    Assert.areEqual(
      2,
      collapsedError.get('occurrenceCount'),
      'Count is retained'
    );
    Assert.areEqual(
      2,
      ((List<Object>) collapsedError.get('errorIds')).size(),
      'Both error IDs are retained'
    );
  }

  @isTest
  static void shouldUsePersistedJobOnlyWithoutReplacementAttempt() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();

    Test.startTest();
    AgentforcePushJobDiagnosisAction.Response response = AgentforcePushJobDiagnosisAction.diagnose(
      new List<AgentforcePushJobDiagnosisAction.Request>{
        AgentforcePushDiagnosticsTestSupport.diagnosisRequest(
          'What should I try next?',
          AgentforcePushDiagnosticsTestSupport.JOB_ID
        )
      }
    )[0];
    Test.stopTest();

    Assert.areEqual(
      'READY',
      response.state,
      'Same-job follow-up should refresh'
    );
    Assert.isFalse(
      response.clearPreviousContext,
      'Same job retains comparison'
    );
    Assert.areEqual(1, stub.jobQueryCount, 'Persisted job should be queried');
  }

  @isTest
  static void shouldRejectWrongTypeWithoutStaleFallback() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();

    Test.startTest();
    AgentforcePushJobDiagnosisAction.Response response = AgentforcePushJobDiagnosisAction.diagnose(
      new List<AgentforcePushJobDiagnosisAction.Request>{
        AgentforcePushDiagnosticsTestSupport.diagnosisRequest(
          'Diagnose 0DV000000000999AAA',
          AgentforcePushDiagnosticsTestSupport.JOB_ID
        )
      }
    )[0];
    Test.stopTest();

    Assert.areEqual('INVALID_ID', response.state, 'Wrong-prefix ID is invalid');
    Assert.isTrue(response.clearPreviousContext, 'Replacement clears evidence');
    Assert.areEqual(0, stub.jobQueryCount, 'Persisted job must not be queried');
    Assert.isNull(response.jobId, 'No stale job ID should return');
  }

  @isTest
  static void shouldReturnNotFoundAndClearUnknownJob() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.jobs.clear();

    Test.startTest();
    AgentforcePushJobDiagnosisAction.Response response = AgentforcePushJobDiagnosisAction.diagnose(
      new List<AgentforcePushJobDiagnosisAction.Request>{
        AgentforcePushDiagnosticsTestSupport.diagnosisRequest(
          'Diagnose ' + AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID,
          AgentforcePushDiagnosticsTestSupport.JOB_ID
        )
      }
    )[0];
    Test.stopTest();

    Assert.areEqual('NOT_FOUND', response.state, 'Unknown jobs are safe');
    Assert.isTrue(response.clearPreviousContext, 'Unknown replacement clears');
    Assert.isNull(response.diagnosticJson, 'Unknown jobs return no evidence');
  }

  @isTest
  static void shouldReturnNotFailedAndNoErrorsStates() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService notFailedStub = AgentforcePushDiagnosticsTestSupport.readyStub();
    notFailedStub.jobs[0].status = 'Succeeded';
    AgentforcePushJobDiagnosisAction.Response notFailed = AgentforcePushJobDiagnosisAction.diagnose(
      new List<AgentforcePushJobDiagnosisAction.Request>{
        AgentforcePushDiagnosticsTestSupport.diagnosisRequest(
          'Diagnose ' + AgentforcePushDiagnosticsTestSupport.JOB_ID,
          null
        )
      }
    )[0];

    AgentforcePushDiagnosticsTestSupport.StubQueryService noErrorsStub = AgentforcePushDiagnosticsTestSupport.readyStub();
    noErrorsStub.errors.clear();

    Test.startTest();
    AgentforcePushJobDiagnosisAction.Response noErrors = AgentforcePushJobDiagnosisAction.diagnose(
      new List<AgentforcePushJobDiagnosisAction.Request>{
        AgentforcePushDiagnosticsTestSupport.diagnosisRequest(
          'Diagnose ' + AgentforcePushDiagnosticsTestSupport.JOB_ID,
          null
        )
      }
    )[0];
    Test.stopTest();

    Assert.areEqual(
      'NOT_FAILED',
      notFailed.state,
      'Succeeded is not diagnosable'
    );
    Assert.isTrue(notFailed.clearPreviousContext, 'Nonfailed context clears');
    Assert.areEqual('NO_ERRORS', noErrors.state, 'No errors is explicit');
    Assert.isTrue(noErrors.clearPreviousContext, 'Errorless context clears');
  }

  @isTest
  static void shouldReturnPermissionUnavailableAndSafeErrorStates() {
    AgentforcePushDiagnosticsTestSupport.readyStub();
    AgentforcePushDiagnosticsService.permissionOverride = false;
    AgentforcePushJobDiagnosisAction.Response forbidden = diagnoseDefault();

    AgentforcePushDiagnosticsTestSupport.StubQueryService unavailableStub = AgentforcePushDiagnosticsTestSupport.readyStub();
    unavailableStub.coreObjectsAvailable = false;
    AgentforcePushJobDiagnosisAction.Response unavailable = diagnoseDefault();

    AgentforcePushDiagnosticsTestSupport.StubQueryService errorStub = AgentforcePushDiagnosticsTestSupport.readyStub();
    errorStub.shouldThrow = true;
    AgentforcePushJobDiagnosisAction.Response safeError = diagnoseDefault();

    Assert.areEqual('FORBIDDEN', forbidden.state, 'Permission is enforced');
    Assert.areEqual(
      'UNAVAILABLE',
      unavailable.state,
      'Missing objects are safe'
    );
    Assert.areEqual('ERROR', safeError.state, 'Unexpected failures are safe');
    Assert.isFalse(
      safeError.message.contains('raw internal query failure'),
      'Raw exception details must not escape'
    );
  }

  @isTest
  static void shouldKeepReadyWithOptionalEnrichmentWarnings() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.optionalObjectsAvailable = false;

    Test.startTest();
    AgentforcePushJobDiagnosisAction.Response response = diagnoseDefault();
    Test.stopTest();

    Map<String, Object> payload = AgentforcePushDiagnosticsTestSupport.jsonMap(
      response.diagnosticJson
    );
    Assert.areEqual('READY', response.state, 'Core evidence remains usable');
    Assert.isFalse(
      ((List<Object>) payload.get('warnings')).isEmpty(),
      'Missing optional enrichment should be disclosed'
    );
  }

  @isTest
  static void shouldReturnOneResponsePerBulkInput() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.jobs.add(
      AgentforcePushDiagnosticsTestSupport.jobRecord(
        AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID,
        AgentforcePushDiagnosticsTestSupport.REQUEST_ID,
        'Failed',
        '00D2'
      )
    );
    stub.errors.add(
      AgentforcePushDiagnosticsTestSupport.errorRecord(
        '0Yx000000000003AAA',
        AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID,
        'Second failure'
      )
    );

    Test.startTest();
    List<AgentforcePushJobDiagnosisAction.Response> responses = AgentforcePushJobDiagnosisAction.diagnose(
      new List<AgentforcePushJobDiagnosisAction.Request>{
        AgentforcePushDiagnosticsTestSupport.diagnosisRequest(
          'Diagnose ' + AgentforcePushDiagnosticsTestSupport.JOB_ID,
          null
        ),
        AgentforcePushDiagnosticsTestSupport.diagnosisRequest(
          'Diagnose ' + AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID,
          null
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(2, responses.size(), 'Bulk actions return 1:1 responses');
    Assert.areEqual(
      AgentforcePushDiagnosticsTestSupport.JOB_ID,
      responses[0].jobId,
      'Input order is retained'
    );
    Assert.areEqual(
      AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID,
      responses[1].jobId,
      'Second input is retained'
    );
  }

  @isTest
  static void shouldCapUniqueErrorsAndDiagnosticSize() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.errors.clear();
    for (Integer indexValue = 0; indexValue < 130; indexValue++) {
      stub.errors.add(
        AgentforcePushDiagnosticsTestSupport.errorRecord(
          '0Yx' + String.valueOf(indexValue).leftPad(12, '0') + 'AAA',
          AgentforcePushDiagnosticsTestSupport.JOB_ID,
          'Failure ' +
            indexValue +
            ' ' +
            AgentforcePushDiagnosticsTestSupport.longText(900)
        )
      );
    }

    Test.startTest();
    AgentforcePushJobDiagnosisAction.Response response = diagnoseDefault();
    Test.stopTest();

    Map<String, Object> payload = AgentforcePushDiagnosticsTestSupport.jsonMap(
      response.diagnosticJson
    );
    Assert.isTrue(
      response.diagnosticJson.length() < 60000,
      'Diagnostic JSON remains below budget'
    );
    Assert.isTrue(
      ((List<Object>) payload.get('errors')).size() <= 100,
      'At most 100 unique errors are retained'
    );
    Assert.isTrue(
      Decimal.valueOf(String.valueOf(payload.get('omittedUniqueErrorCount'))) >
      0,
      'Omitted unique count is explicit'
    );
  }

  @isTest
  static void shouldExerciseRealQueryAdapterWithoutCreatingPackagingRecords() {
    AgentforcePushDiagnosticsQueryService adapter = new AgentforcePushDiagnosticsQueryService();

    Assert.areEqual(0, adapter.getJobs(new Set<String>()).size(), 'Empty jobs');
    Assert.areEqual(
      0,
      adapter.getErrors(new Set<String>(), null).size(),
      'Empty errors'
    );
    Assert.areEqual(
      0,
      adapter.getRequests(new Set<String>()).size(),
      'Empty requests'
    );
    Assert.areEqual(
      0,
      adapter.getVersions(new Set<String>()).size(),
      'Empty versions'
    );
    Assert.areEqual(
      0,
      adapter.getSubscribers(new Set<String>(), new Set<String>()).size(),
      'Empty subscribers'
    );
    Assert.areEqual(
      0,
      adapter.getRequestJobs(new Set<String>(), 1).size(),
      'Empty request jobs'
    );
    Assert.areEqual(
      0,
      adapter.getRequestErrors(new Set<String>(), 1).size(),
      'Empty request errors'
    );

    if (adapter.areCoreObjectsAvailable()) {
      Set<String> missingJobIds = new Set<String>{ '0DX000000000000' };
      Assert.areEqual(0, adapter.getJobs(missingJobIds).size(), 'Missing job');
      Assert.areEqual(
        0,
        adapter.getErrors(missingJobIds, 1).size(),
        'Missing errors'
      );
      Assert.areEqual(
        0,
        adapter.getRequestJobs(new Set<String>{ '0DV000000000000' }, 1).size(),
        'Missing request jobs'
      );
      Assert.areEqual(
        0,
        adapter.getRequestErrors(missingJobIds, 1).size(),
        'Missing request errors'
      );

      SObject jobRecord = (SObject) JSON.deserialize(
        '{"attributes":{"type":"PackagePushJob"},' +
          '"Id":"0DX000000000000","PackagePushRequestId":"0DV000000000000",' +
          '"Status":"Failed","SubscriberOrganizationKey":"00D000000000000",' +
          '"DurationSeconds":12}',
        SObject.class
      );
      Assert.isTrue(
        AgentforcePushDiagnosticsQueryService.toJobs(
            new List<SObject>{ jobRecord }
          )[0]
          .id
          .startsWith('0DX000000000000'),
        'Job rows are normalized'
      );

      SObject errorRecord = (SObject) JSON.deserialize(
        '{"attributes":{"type":"PackagePushError"},' +
          '"Id":"0Yx000000000000","PackagePushJobId":"0DX000000000000",' +
          '"ErrorTitle":"Failure","ErrorMessage":"Message",' +
          '"ErrorType":"Install","ErrorDetails":"Details",' +
          '"ErrorSeverity":"Error"}',
        SObject.class
      );
      Assert.areEqual(
        'Failure',
        AgentforcePushDiagnosticsQueryService.toErrors(
            new List<SObject>{ errorRecord }
          )[0]
          .title,
        'Error rows are normalized'
      );
    }

    if (adapter.areOptionalObjectsAvailable()) {
      Assert.areEqual(
        0,
        adapter.getRequests(new Set<String>{ '0DV000000000000' }).size(),
        'Missing request'
      );
      Assert.areEqual(
        0,
        adapter.getVersions(new Set<String>{ '04t000000000000' }).size(),
        'Missing version'
      );
      Assert.areEqual(
        0,
        adapter.getSubscribers(
            new Set<String>{ '00D000000000000' },
            new Set<String>{ '033000000000000' }
          )
          .size(),
        'Missing subscriber'
      );

      SObject requestRecord = (SObject) JSON.deserialize(
        '{"attributes":{"type":"PackagePushRequest"},' +
        '"Id":"0DV000000000000","PackageVersionId":"04t000000000000"}',
        SObject.class
      );
      Assert.isTrue(
        AgentforcePushDiagnosticsQueryService.toRequests(
            new List<SObject>{ requestRecord }
          )[0]
          .packageVersionId
          .startsWith('04t000000000000'),
        'Request rows are normalized'
      );

      SObject versionRecord = (SObject) JSON.deserialize(
        '{"attributes":{"type":"MetadataPackageVersion"},' +
          '"Id":"04t000000000000","Name":"Version",' +
          '"MetadataPackageId":"033000000000000","ReleaseState":"Released",' +
          '"MajorVersion":1,"MinorVersion":2,"PatchVersion":3,' +
          '"BuildNumber":4}',
        SObject.class
      );
      Assert.areEqual(
        4,
        AgentforcePushDiagnosticsQueryService.toVersions(
            new List<SObject>{ versionRecord }
          )[0]
          .buildNumber,
        'Version rows are normalized'
      );

      SObject subscriberRecord = (SObject) JSON.deserialize(
        '{"attributes":{"type":"PackageSubscriber"},' +
          '"MetadataPackageId":"033000000000000",' +
          '"MetadataPackageVersionId":"04t000000000000",' +
          '"InstalledStatus":"i","OrgKey":"00D000000000000",' +
          '"OrgName":"Subscriber","OrgType":"Production",' +
          '"OrgStatus":"Active","InstanceName":"NA1"}',
        SObject.class
      );
      Assert.areEqual(
        'Subscriber',
        AgentforcePushDiagnosticsQueryService.toSubscribers(
            new List<SObject>{ subscriberRecord }
          )[0]
          .orgName,
        'Subscriber rows are normalized'
      );
    }
  }

  private static AgentforcePushJobDiagnosisAction.Response diagnoseDefault() {
    return AgentforcePushJobDiagnosisAction.diagnose(
      new List<AgentforcePushJobDiagnosisAction.Request>{
        AgentforcePushDiagnosticsTestSupport.diagnosisRequest(
          'Diagnose ' + AgentforcePushDiagnosticsTestSupport.JOB_ID,
          null
        )
      }
    )[0];
  }
}
