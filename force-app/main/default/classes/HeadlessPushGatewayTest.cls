/** Tests real gateway parsing and File access independently of service fakes. */
@IsTest
private with sharing class HeadlessPushGatewayTest {
  @IsTest
  static void shouldResolveUnlockedTargetWithoutSecurityReviewQuery() {
    TargetMock mock = new TargetMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    Map<String, Object> target = new HeadlessPushGateway()
      .target('04t000000000002');
    Test.stopTest();
    Assert.areEqual(
      false,
      target.get('managed'),
      'Unlocked packages bypass managed security review'
    );
    Assert.areEqual(
      true,
      target.get('released'),
      'Only released targets are returned'
    );
    Assert.areEqual(
      new List<String>{ '04t000000000001' },
      (List<String>) target.get('lowerVersionIds'),
      'Resolve numeric lower versions within the owning package'
    );
    Assert.areEqual(
      2,
      mock.queries,
      'Unlocked targets need only target and version inventory queries'
    );
  }

  @IsTest
  static void shouldRejectUnreleasedTarget() {
    TargetMock mock = new TargetMock();
    mock.released = false;
    Test.setMock(HttpCalloutMock.class, mock);
    Boolean rejected = false;
    Test.startTest();
    try {
      new HeadlessPushGateway().target('04t000000000002');
    } catch (HeadlessPushService.PushException expected) {
      rejected = true;
    }
    Test.stopTest();
    Assert.isTrue(rejected, 'An unreleased target cannot prepare an upgrade');
    Assert.areEqual(1, mock.queries, 'Stop before querying cohorts');
  }

  @IsTest
  static void shouldRejectManagedTargetWithoutSecurityReview() {
    TargetMock mock = new TargetMock();
    mock.kind = 'Managed';
    Test.setMock(HttpCalloutMock.class, mock);
    Boolean rejected = false;
    Test.startTest();
    try {
      new HeadlessPushGateway().target('04t000000000002');
    } catch (HeadlessPushService.PushException expected) {
      rejected = true;
    }
    Test.stopTest();
    Assert.isTrue(rejected, 'Managed targets require verified security review');
    Assert.areEqual(
      2,
      mock.queries,
      'Review failure must stop before version inventory'
    );
  }

  @IsTest
  static void shouldSaveAndReadExactOwnedFileVersion() {
    HeadlessPushGateway gateway = new HeadlessPushGateway();
    String csv = '00D000000000001\n';
    Test.startTest();
    String fileId = gateway.saveFile('headless-test.csv', csv);
    ContentVersion snapshot = gateway.file(fileId);
    Test.stopTest();
    Assert.areEqual(
      csv,
      snapshot.VersionData.toString(),
      'Read the exact saved file bytes'
    );
    Assert.areEqual(
      UserInfo.getUserId(),
      snapshot.CreatedById,
      'Snapshots belong to the operator'
    );
    Assert.areEqual(
      Id.valueOf(fileId),
      snapshot.Id,
      'Do not follow another file version'
    );
  }

  @IsTest
  static void shouldQueryBoundedSubscribersWithTypedFilters() {
    HeadlessPushTestSupport.QueryGateway gateway = new HeadlessPushTestSupport.QueryGateway();
    gateway.rows = HeadlessPushTestSupport.subscribers(1);
    Test.startTest();
    List<Map<String, Object>> rows = gateway.subscribers(
      '033000000000001',
      new Set<String>{ '00D000000000001' },
      new Set<String>{ '04t000000000001' },
      new List<String>{ 'Sandbox' },
      new List<String>{ 'Active' },
      new List<String>{ 'NA1' }
    );
    Test.stopTest();
    Assert.areEqual(
      1,
      rows.size(),
      'Return the query results without dropping subscriber fields'
    );
    Assert.areEqual(gateway.rows, rows, 'Preserve subscriber data');
    Assert.isTrue(gateway.queryText.contains('WHERE MetadataPackageId = :packageId'), 'Scope to the selected package');
    Assert.isTrue(gateway.queryText.contains('OrgKey IN :orgIds'), 'Bind the selected orgs');
    Assert.isTrue(gateway.queryText.contains('MetadataPackageVersionId IN :installedVersions'), 'Bind installed versions');
    Assert.isTrue(gateway.queryText.contains('OrgType IN :orgTypes'), 'Apply org type filter');
    Assert.isTrue(gateway.queryText.contains('OrgStatus IN :statuses'), 'Apply status filter');
    Assert.isTrue(gateway.queryText.contains('InstanceName IN :instances'), 'Apply instance filter');
    Assert.isTrue(gateway.queryText.endsWith('ORDER BY OrgKey LIMIT 2001'), 'Keep stable ordering and overflow bound');
    Assert.areEqual('033000000000001', gateway.queryBinds.get('packageId'), 'Bind the package ID');
    Assert.areEqual(new Set<String>{'00D000000000001'}, gateway.queryBinds.get('orgIds'), 'Bind the exact org selection');
    Assert.areEqual(new Set<String>{'04t000000000001'}, gateway.queryBinds.get('installedVersions'), 'Bind the installed version selection');
    Assert.areEqual(new List<String>{'Sandbox'}, gateway.queryBinds.get('orgTypes'), 'Retain org types');
    Assert.areEqual(new List<String>{'Active'}, gateway.queryBinds.get('statuses'), 'Retain statuses');
    Assert.areEqual(new List<String>{'NA1'}, gateway.queryBinds.get('instances'), 'Retain instances');
  }

  @IsTest
  static void shouldReturnNoJobsForUnknownRequest() {
    HeadlessPushTestSupport.QueryGateway gateway = new HeadlessPushTestSupport.QueryGateway();
    Test.startTest();
    List<Map<String, Object>> rows = gateway.jobs('0DV000000000001');
    Test.stopTest();
    Assert.areEqual(0, rows.size(), 'Never return jobs from another request');
    Assert.isTrue(gateway.queryText.contains('WHERE PackagePushRequestId = :requestId'), 'Scope jobs to the request');
    Assert.isTrue(gateway.queryText.endsWith('ORDER BY SubscriberOrganizationKey LIMIT 2001'), 'Bound and order jobs');
    Assert.areEqual('0DV000000000001', gateway.queryBinds.get('requestId'), 'Bind the exact request');
  }

  @IsTest
  static void shouldRejectInaccessibleRequest() {
    HeadlessPushTestSupport.QueryGateway gateway = new HeadlessPushTestSupport.QueryGateway();
    Boolean rejected = false;
    Test.startTest();
    try {
      gateway.request('0DV000000000001');
    } catch (HeadlessPushService.PushException expected) {
      rejected = true;
      Assert.areEqual('Push request is not accessible.', expected.getMessage(), 'Explain the missing request');
    }
    Test.stopTest();
    Assert.isTrue(
      rejected,
      'Unknown requests must not provide execution context'
    );
    Assert.isTrue(gateway.queryText.endsWith('WHERE Id = :requestId LIMIT 1'), 'Read only the selected request');
    Assert.areEqual('0DV000000000001', gateway.queryBinds.get('requestId'), 'Bind the selected request');
  }

  @IsTest
  static void shouldReturnNoJobDetailsOutsideRequest() {
    HeadlessPushTestSupport.QueryGateway gateway = new HeadlessPushTestSupport.QueryGateway();
    Test.startTest();
    List<Map<String, Object>> rows = gateway.jobDetails('0DV000000000001', new Set<String>{ '0DX000000000001' });
    Test.stopTest();
    Assert.areEqual(
      0,
      rows.size(),
      'Detail queries must be scoped to the request and selected page'
    );
    Assert.isTrue(gateway.queryText.contains('WHERE PackagePushRequestId = :requestId AND Id IN :jobIds'), 'Constrain both request and page');
    Assert.isTrue(gateway.queryText.contains('FROM PackagePushErrors LIMIT 5'), 'Bound errors for each job');
    Assert.isTrue(gateway.queryText.endsWith('ORDER BY SubscriberOrganizationKey LIMIT 10'), 'Bound the detail page');
    Assert.areEqual('0DV000000000001', gateway.queryBinds.get('requestId'), 'Bind the request');
    Assert.areEqual(new Set<String>{'0DX000000000001'}, gateway.queryBinds.get('jobIds'), 'Bind only the selected jobs');
  }

  @IsTest
  static void shouldReturnAccessibleRequest() {
    HeadlessPushTestSupport.QueryGateway gateway = new HeadlessPushTestSupport.QueryGateway();
    gateway.rows.add(new Map<String, Object>{'Id' => '0DV000000000001', 'Status' => 'Created'});
    Test.startTest();
    Map<String, Object> request = gateway.request('0DV000000000001');
    Test.stopTest();
    Assert.areEqual(gateway.rows[0], request, 'Return the selected request fields');
  }

  @IsTest
  static void shouldPropagateQueryAccessFailure() {
    HeadlessPushTestSupport.QueryGateway gateway = new HeadlessPushTestSupport.QueryGateway();
    gateway.queryDenied = true;
    Test.startTest();
    try {
      gateway.request('0DV000000000001');
      Assert.fail('A query failure must not be returned as a missing request');
    } catch (HeadlessPushService.PushException expected) {
      Assert.areEqual('Query access denied', expected.getMessage(), 'Preserve query access errors');
    }
    Test.stopTest();
  }

  @IsTest
  static void shouldExecuteRealQueryBoundaryWithPortableObject() {
    Test.startTest();
    List<Map<String, Object>> rows = new HeadlessPushTestSupport.QueryGateway().ownUser();
    Test.stopTest();
    Assert.areEqual(1, rows.size(), 'Execute the real user-mode query and mapping');
    Assert.areEqual(String.valueOf(UserInfo.getUserId()), rows[0].get('Id'), 'Bind the current user');
  }

  @IsTest
  static void shouldReturnNoReportsOutsideRequest() {
    Test.startTest();
    List<Map<String, Object>> rows = new HeadlessPushGateway()
      .reports('0DV000000000001', '068000000000099');
    Test.stopTest();
    Assert.areEqual(
      0,
      rows.size(),
      'Private diagnostic lookup must be request scoped'
    );
  }

  @IsTest
  static void shouldUseSharedChunkTransportWithoutDispatch() {
    Test.setMock(HttpCalloutMock.class, new TransportMock());
    Test.startTest();
    List<Object> rows = new HeadlessPushGateway()
      .stageChunk('0DV000000000001', new List<String>{ '00D000000000001' });
    Test.stopTest();
    Assert.areEqual(1, rows.size(), 'Return the base chunk response');
    Assert.areEqual(
      true,
      ((Map<String, Object>) rows[0]).get('success'),
      'Preserve accepted outcomes'
    );
  }

  @IsTest
  static void shouldUseSharedStatusTransport() {
    TransportMock mock = new TransportMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    new HeadlessPushGateway().setStatus('0DV000000000001', 'Canceled');
    Test.stopTest();
    Assert.areEqual(1, mock.patchCount, 'Issue one explicit status change');
  }

  private class TransportMock implements HttpCalloutMock {
    Integer patchCount = 0;
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setHeader('Content-Type', 'application/json');
      response.setStatusCode(200);
      if (request.getMethod() == 'GET')
        response.setBody('{"Status":"Created"}');
      else if (request.getMethod() == 'POST')
        response.setBody(
          '[{"id":"0DX000000000001","success":true,"errors":[]}]'
        );
      else {
        patchCount++;
        response.setStatusCode(204);
      }
      return response;
    }
  }

  private class TargetMock implements HttpCalloutMock {
    String kind = 'Unlocked';
    Boolean released = true;
    Integer queries = 0;
    public HttpResponse respond(HttpRequest request) {
      queries++;
      String query = EncodingUtil.urlDecode(request.getEndpoint(), 'UTF-8');
      List<Object> records = new List<Object>();
      if (query.contains('FROM SubscriberPackageVersion')) {
        records.add(new Map<String, Object>{ 'IsSecurityReviewed' => false });
      } else if (query.contains('SubscriberPackageVersionId =')) {
        Map<String, Object> target = version('04t000000000002', 2);
        target.put('Id', '05i000000000002');
        target.put('Package2Id', '0Ho000000000001');
        target.put('IsReleased', released);
        target.put('IsDeprecated', false);
        target.put(
          'Package2',
          new Map<String, Object>{
            'SubscriberPackageId' => '033000000000001',
            'ContainerOptions' => kind
          }
        );
        records.add(target);
      } else {
        records.add(version('04t000000000001', 1));
        records.add(version('04t000000000002', 2));
      }
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setHeader('Content-Type', 'application/json');
      response.setBody(
        JSON.serialize(
          new Map<String, Object>{
            'totalSize' => records.size(),
            'done' => true,
            'records' => records
          }
        )
      );
      return response;
    }
    private Map<String, Object> version(String versionId, Integer major) {
      return new Map<String, Object>{
        'SubscriberPackageVersionId' => versionId,
        'MajorVersion' => major,
        'MinorVersion' => 0,
        'PatchVersion' => 0,
        'BuildNumber' => 1
      };
    }
  }
}
