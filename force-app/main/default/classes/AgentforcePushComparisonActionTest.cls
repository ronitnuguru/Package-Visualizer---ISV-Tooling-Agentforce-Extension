/**
 * Tests authoritative push-request sibling comparison behavior.
 */
@isTest
private with sharing class AgentforcePushComparisonActionTest {
  @isTest
  static void shouldCompareAndRankExactFailureSignatures() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.jobs.add(
      AgentforcePushDiagnosticsTestSupport.jobRecord(
        AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID,
        AgentforcePushDiagnosticsTestSupport.REQUEST_ID,
        'Failed',
        '00D2'
      )
    );
    stub.jobs.add(
      AgentforcePushDiagnosticsTestSupport.jobRecord(
        '0DX000000000003AAA',
        AgentforcePushDiagnosticsTestSupport.REQUEST_ID,
        'Succeeded',
        '00D3'
      )
    );
    stub.errors.add(
      AgentforcePushDiagnosticsTestSupport.errorRecord(
        '0Yx000000000002AAA',
        AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID,
        'Same failure'
      )
    );
    stub.errors.add(
      AgentforcePushDiagnosticsTestSupport.errorRecord(
        '0Yx000000000003AAA',
        AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID,
        'Same failure'
      )
    );

    Test.startTest();
    AgentforcePushRequestComparisonAction.Response response = compareDefault();
    Test.stopTest();

    Map<String, Object> payload = AgentforcePushDiagnosticsTestSupport.jsonMap(
      response.comparisonJson
    );
    List<Object> signatures = (List<Object>) payload.get(
      'topFailureSignatures'
    );
    Map<String, Object> firstSignature = (Map<String, Object>) signatures[0];
    Map<String, Object> statusCounts = (Map<String, Object>) payload.get(
      'jobStatusCounts'
    );

    Assert.areEqual('READY', response.state, 'Comparison should be ready');
    Assert.areEqual(2, statusCounts.get('Failed'), 'Failed jobs are counted');
    Assert.areEqual(1, statusCounts.get('Succeeded'), 'Successes are counted');
    Assert.areEqual(
      2,
      firstSignature.get('affectedJobCount'),
      'Top signature ranks by affected jobs'
    );
    Assert.areEqual(
      true,
      firstSignature.get('affectsSelectedJob'),
      'Selected-job matching is explicit'
    );
    Assert.isTrue(
      ((List<Object>) firstSignature.get('sampleJobs')).size() <= 3,
      'Signature samples are capped'
    );
  }

  @isTest
  static void shouldDeriveAuthoritativeRequestFromSelectedJob() {
    AgentforcePushDiagnosticsTestSupport.readyStub();

    Test.startTest();
    AgentforcePushRequestComparisonAction.Response response = AgentforcePushRequestComparisonAction.compare(
      new List<AgentforcePushRequestComparisonAction.Request>{
        comparisonRequest(AgentforcePushDiagnosticsTestSupport.JOB_ID)
      }
    )[0];
    Test.stopTest();

    Assert.areEqual(
      'READY',
      response.state,
      'A valid active job is sufficient'
    );
    Assert.areEqual(
      AgentforcePushDiagnosticsTestSupport.REQUEST_ID,
      response.pushRequestId,
      'The owning request is rehydrated authoritatively'
    );
  }

  @isTest
  static void shouldIgnoreLegacyRequestIdAndDeriveFromSelectedJob() {
    AgentforcePushDiagnosticsTestSupport.readyStub();
    AgentforcePushRequestComparisonAction.Request requestValue = comparisonRequest(
      AgentforcePushDiagnosticsTestSupport.JOB_ID
    );
    requestValue.pushRequestId = '0DV000000000999AAA';

    Test.startTest();
    AgentforcePushRequestComparisonAction.Response response = AgentforcePushRequestComparisonAction.compare(
      new List<AgentforcePushRequestComparisonAction.Request>{ requestValue }
    )[0];
    Test.stopTest();

    Assert.areEqual(
      'READY',
      response.state,
      'Legacy input does not block comparison'
    );
    Assert.areEqual(
      AgentforcePushDiagnosticsTestSupport.REQUEST_ID,
      response.pushRequestId,
      'The selected job remains the only authoritative request anchor'
    );
  }

  @isTest
  static void shouldRejectMissingOrInvalidSelectedJobSafely() {
    AgentforcePushDiagnosticsTestSupport.readyStub();

    Test.startTest();
    List<AgentforcePushRequestComparisonAction.Response> responses = AgentforcePushRequestComparisonAction.compare(
      new List<AgentforcePushRequestComparisonAction.Request>{
        comparisonRequest(null),
        comparisonRequest('0DV000000000001AAA')
      }
    );
    Test.stopTest();

    Assert.areEqual(
      'INVALID_ID',
      responses[0].state,
      'Missing context is safe'
    );
    Assert.areEqual('INVALID_ID', responses[1].state, 'Only a 0DX is valid');
    Assert.isNull(
      responses[0].comparisonJson,
      'Invalid input returns no evidence'
    );
  }

  @isTest
  static void shouldGroupSimilarFailureVariationsWithoutLosingExactEvidence() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.jobs.add(
      AgentforcePushDiagnosticsTestSupport.jobRecord(
        AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID,
        AgentforcePushDiagnosticsTestSupport.REQUEST_ID,
        'Failed',
        '00D2'
      )
    );
    stub.errors.clear();
    stub.errors.add(
      AgentforcePushDiagnosticsTestSupport.errorRecord(
        '0Yx000000000001AAA',
        AgentforcePushDiagnosticsTestSupport.JOB_ID,
        'Apex compile failure: Foo: line 84, column 86: Invalid type: 01p000000000001AAA'
      )
    );
    stub.errors.add(
      AgentforcePushDiagnosticsTestSupport.errorRecord(
        '0Yx000000000002AAA',
        AgentforcePushDiagnosticsTestSupport.SECOND_JOB_ID,
        'Apex compile failure: Foo: line 7, column 2: Invalid type: 01p000000000999AAA'
      )
    );

    Test.startTest();
    AgentforcePushRequestComparisonAction.Response response = compareDefault();
    Test.stopTest();

    Map<String, Object> payload = AgentforcePushDiagnosticsTestSupport.jsonMap(
      response.comparisonJson
    );
    List<Object> families = (List<Object>) payload.get('topFailureFamilies');
    Map<String, Object> firstFamily = (Map<String, Object>) families[0];

    Assert.areEqual(
      2,
      firstFamily.get('affectedJobCount'),
      'Volatile line, column, and Salesforce IDs normalize into one family'
    );
    Assert.areEqual(
      2,
      firstFamily.get('exactVariantCount'),
      'Exact variants remain counted separately'
    );
    Assert.areEqual(
      2,
      ((List<Object>) payload.get('topFailureSignatures')).size(),
      'Exact failure evidence remains available'
    );
    Assert.areEqual(
      'DETERMINISTIC_VOLATILE_TOKEN_NORMALIZATION',
      payload.get('similarityMethod'),
      'The comparison discloses its deterministic similarity method'
    );
  }

  @isTest
  static void shouldReportComparisonScanCaps() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.jobs.clear();
    stub.errors.clear();
    for (Integer indexValue = 0; indexValue < 2001; indexValue++) {
      String jobIdValue =
        '0DX' +
        String.valueOf(indexValue).leftPad(12, '0') +
        'AAA';
      stub.jobs.add(
        AgentforcePushDiagnosticsTestSupport.jobRecord(
          jobIdValue,
          AgentforcePushDiagnosticsTestSupport.REQUEST_ID,
          'Failed',
          'ORG' + indexValue
        )
      );
    }
    for (Integer indexValue = 0; indexValue < 10001; indexValue++) {
      stub.errors.add(
        AgentforcePushDiagnosticsTestSupport.errorRecord(
          '0Yx' + String.valueOf(indexValue).leftPad(12, '0') + 'AAA',
          stub.jobs[Math.mod(indexValue, 2000)].id,
          'Failure'
        )
      );
    }

    Test.startTest();
    AgentforcePushRequestComparisonAction.Response response = compareDefault();
    Test.stopTest();

    Map<String, Object> payload = AgentforcePushDiagnosticsTestSupport.jsonMap(
      response.comparisonJson
    );
    Assert.areEqual(true, payload.get('jobsTruncated'), 'Job cap is reported');
    Assert.areEqual(
      true,
      payload.get('errorsTruncated'),
      'Error cap is reported'
    );
    Assert.areEqual(
      2000,
      payload.get('scannedJobCount'),
      '2,000 jobs are scanned'
    );
    Assert.areEqual(
      10000,
      payload.get('scannedErrorCount'),
      '10,000 errors are scanned'
    );
  }

  @isTest
  static void shouldReturnOneSafeResponsePerComparisonInput() {
    AgentforcePushDiagnosticsTestSupport.StubQueryService stub = AgentforcePushDiagnosticsTestSupport.readyStub();
    stub.shouldThrow = true;

    AgentforcePushDiagnosticsService.permissionOverride = false;
    AgentforcePushRequestComparisonAction.Response forbidden = compareDefault();

    AgentforcePushDiagnosticsService.permissionOverride = true;
    stub.coreObjectsAvailable = false;
    stub.shouldThrow = false;
    AgentforcePushRequestComparisonAction.Response unavailable = compareDefault();

    stub.coreObjectsAvailable = true;
    stub.shouldThrow = true;
    List<AgentforcePushRequestComparisonAction.Response> errors = AgentforcePushRequestComparisonAction.compare(
      new List<AgentforcePushRequestComparisonAction.Request>{
        comparisonRequest(AgentforcePushDiagnosticsTestSupport.JOB_ID),
        comparisonRequest(AgentforcePushDiagnosticsTestSupport.JOB_ID)
      }
    );

    Assert.areEqual('FORBIDDEN', forbidden.state, 'Permission is enforced');
    Assert.areEqual(
      'UNAVAILABLE',
      unavailable.state,
      'Missing objects are safe'
    );
    Assert.areEqual(2, errors.size(), 'Bulk failures retain 1:1 responses');
    Assert.areEqual('ERROR', errors[0].state, 'Query failures are safe');
    Assert.isFalse(
      errors[0].message.contains('raw internal query failure'),
      'Raw errors do not escape'
    );
  }

  private static AgentforcePushRequestComparisonAction.Response compareDefault() {
    return AgentforcePushRequestComparisonAction.compare(
      new List<AgentforcePushRequestComparisonAction.Request>{
        comparisonRequest(AgentforcePushDiagnosticsTestSupport.JOB_ID)
      }
    )[0];
  }

  private static AgentforcePushRequestComparisonAction.Request comparisonRequest(
    String selectedJobId
  ) {
    AgentforcePushRequestComparisonAction.Request requestValue = new AgentforcePushRequestComparisonAction.Request();
    requestValue.selectedPushJobId = selectedJobId;
    return requestValue;
  }
}
