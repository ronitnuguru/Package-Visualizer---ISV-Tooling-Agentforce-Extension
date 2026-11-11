/** Exercises real bounded query and callout boundaries introduced by v2. */
@IsTest
private with sharing class HeadlessV2GatewayTest {
  @IsTest
  static void shouldLookupOnlyTheExactPackageAndVersion() {
    QueryMock mock=new QueryMock();Test.setMock(HttpCalloutMock.class,mock);
    Test.startTest();
    List<Map<String,Object>> rows=new HeadlessPushGateway().lookupTargets('Billing','9.41.0.1');
    Test.stopTest();
    Assert.areEqual(1,rows.size(),'Return the bounded exact match');
    Assert.areEqual(1,mock.queries.size(),'Target resolution does not load portfolio/build history');
    Assert.isTrue(mock.queries[0].contains('Package2.Name=\'Billing\''),'Bind selection to exact package name');
    Assert.isTrue(mock.queries[0].contains('MajorVersion=9'),'Constrain the major version');
    Assert.isTrue(mock.queries[0].contains('BuildNumber=1'),'Constrain the requested build');
  }
  @IsTest
  static void shouldEscapePackageNameInput() {
    QueryMock mock=new QueryMock();Test.setMock(HttpCalloutMock.class,mock);
    String supplied='Billing\' OR Name != \'\'';
    Test.startTest();new HeadlessPushGateway().lookupTargets(supplied,'9.41');Test.stopTest();
    Assert.isTrue(mock.queries[0].contains('Package2.Name=\''+String.escapeSingleQuotes(supplied)+'\''),'User text remains inside an escaped literal');
  }
  @IsTest
  static void shouldRejectNonNumericVersionBeforeCallout() {
    QueryMock mock=new QueryMock();Test.setMock(HttpCalloutMock.class,mock);
    Test.startTest();
    try {
      new HeadlessPushGateway().lookupTargets('Billing','9.41 OR IsReleased=true');
      Assert.fail('A version is numeric components, not SOQL');
    } catch(HeadlessPushService.PushException expected) {
      Assert.isTrue(expected.getMessage().contains('numeric'),'Explain the version contract');
    }
    Test.stopTest();Assert.areEqual(0,mock.queries.size(),'Reject before transport');
  }
  @IsTest
  static void shouldReportReadinessWhenChecksPass() {
    QueryMock mock=new QueryMock();Test.setMock(HttpCalloutMock.class,mock);
    Test.startTest();Map<String,Object> result=new HeadlessPushGateway().readiness(HeadlessV2TestSupport.TARGET_ID);Test.stopTest();
    Assert.areEqual(true,result.get('eligible'),'Coverage and authoritative push checks pass');
    Assert.areEqual(2,mock.queries.size(),'Readiness queries coverage and target header, without lower-version inventory');
    Assert.areEqual(0,((List<String>)result.get('blockers')).size(),'Return no blockers');
  }
  @IsTest
  static void shouldReportCoverageAndValidationBlockers() {
    QueryMock mock=new QueryMock();mock.coveragePassed=false;mock.validationSkipped=true;
    Test.setMock(HttpCalloutMock.class,mock);
    Test.startTest();Map<String,Object> result=new HeadlessPushGateway().readiness(HeadlessV2TestSupport.TARGET_ID);Test.stopTest();
    Assert.areEqual(false,result.get('eligible'),'Do not confuse returned evidence with eligibility');
    Assert.areEqual(2,((List<String>)result.get('blockers')).size(),'Report both independent blockers');
  }
  @IsTest
  static void shouldReturnEmptyRequestBatchWithoutQuery() {
    HeadlessPushTestSupport.QueryGateway gateway=new HeadlessPushTestSupport.QueryGateway();
    Test.startTest();List<Map<String,Object>> rows=gateway.requests(new Set<String>());Test.stopTest();
    Assert.areEqual(0,rows.size(),'Empty ID selection returns empty results');
    Assert.areEqual(0,gateway.queryCount,'Empty request lookup does not reach the query boundary');
  }
  @IsTest
  static void shouldReturnNoOtherRequestsForSyntheticId() {
    HeadlessPushTestSupport.QueryGateway gateway=new HeadlessPushTestSupport.QueryGateway();
    Test.startTest();List<Map<String,Object>> rows=gateway.requests(new Set<String>{HeadlessV2TestSupport.REQUEST_ID});Test.stopTest();
    Assert.areEqual(0,rows.size(),'Request ID scope cannot return unrelated records');
    Assert.isTrue(gateway.queryText.endsWith('WHERE Id IN :ids ORDER BY Id LIMIT 10'),'Bound the selected request batch');
    Assert.areEqual(new Set<String>{HeadlessV2TestSupport.REQUEST_ID},gateway.queryBinds.get('ids'),'Bind only selected request IDs');
  }
  @IsTest
  static void shouldReturnNoOverlapForEmptyCohort() {
    HeadlessPushTestSupport.QueryGateway gateway=new HeadlessPushTestSupport.QueryGateway();
    Test.startTest();List<Map<String,Object>> rows=gateway.overlappingJobs(new Set<String>(),HeadlessV2TestSupport.TARGET_ID,HeadlessV2TestSupport.REQUEST_ID);Test.stopTest();
    Assert.areEqual(0,rows.size(),'No selected orgs means no overlaps');
    Assert.areEqual(0,gateway.queryCount,'Empty cohort does not reach the query boundary');
  }
  @IsTest
  static void shouldScopeOverlapLookupToSelectedTargetAndOrgs() {
    HeadlessPushTestSupport.QueryGateway gateway=new HeadlessPushTestSupport.QueryGateway();
    gateway.rows.add(new Map<String,Object>{'Id'=>'0DX000000000001'});
    String orgId=HeadlessPushTestSupport.keys(1)[0];
    Test.startTest();List<Map<String,Object>> rows=gateway.overlappingJobs(new Set<String>{orgId},HeadlessV2TestSupport.TARGET_ID,HeadlessV2TestSupport.REQUEST_ID);Test.stopTest();
    Assert.areEqual(gateway.rows,rows,'Return the detected overlap');
    Assert.isTrue(gateway.queryText.contains('SubscriberOrganizationKey IN :ids'),'Scope overlaps to selected orgs');
    Assert.isTrue(gateway.queryText.contains('PackagePushRequestId != :sourceRequestId'),'Exclude the prepared request');
    Assert.isTrue(gateway.queryText.contains('PackagePushRequest.PackageVersionId=:targetId'),'Match the reviewed target');
    Assert.isTrue(gateway.queryText.contains('Status=\'Succeeded\''),'Completed successes block duplicate upgrades');
    Assert.isTrue(gateway.queryText.contains('Status IN (\'Created\',\'Pending\',\'InProgress\')'),'Active attempts block duplicate upgrades');
    Assert.isTrue(gateway.queryText.contains('PackagePushRequest.Status != \'Canceled\''),'Canceled parents do not count as active attempts');
    Assert.isTrue(gateway.queryText.endsWith('LIMIT 1'),'Only existence is required');
    Assert.areEqual(new Set<String>{orgId,orgId.left(15)},gateway.queryBinds.get('ids'),'Match both Salesforce org ID forms');
    Assert.areEqual(HeadlessV2TestSupport.TARGET_ID,gateway.queryBinds.get('targetId'),'Bind the exact target');
    Assert.areEqual(HeadlessV2TestSupport.REQUEST_ID,gateway.queryBinds.get('sourceRequestId'),'Bind the excluded request');
  }
  @IsTest
  static void shouldPaginateEqualTimestampManifestFilesWithoutSkipping() {
    Datetime timestamp=System.now().addDays(-1);
    List<ContentVersion> files=new List<ContentVersion>();
    for(Integer i=1;i<=12;i++) {
      String title='push-manifest-0DV'+String.valueOf(i).leftPad(12,'0')+'.json';
      files.add(new ContentVersion(Title=title,PathOnClient=title,VersionData=Blob.valueOf('{}')));
    }
    insert files;
    for(ContentVersion file:files) {Test.setCreatedDate(file.Id,timestamp);}
    HeadlessPushGateway gateway=new HeadlessPushGateway();
    Test.startTest();
    List<Map<String,Object>> first=gateway.manifests(null,null,null);
    Datetime cursor=(Datetime)JSON.deserialize(JSON.serialize(first[first.size()-1].get('CreatedDate')),Datetime.class);
    List<Map<String,Object>> second=gateway.manifests(null,cursor,(String)first[first.size()-1].get('Id'));
    Test.stopTest();
    Assert.areEqual(10,first.size(),'First metadata page is bounded');
    Assert.areEqual(2,second.size(),'Equal-date siblings continue via ID tie-break');
    Set<String> seen=new Set<String>();
    for(Map<String,Object> row:first) {seen.add((String)row.get('Id'));Assert.isFalse(row.containsKey('VersionData'),'Never load manifest bodies while listing');}
    for(Map<String,Object> row:second) {Assert.isTrue(seen.add((String)row.get('Id')),'Pages do not overlap');}
    Assert.areEqual(12,seen.size(),'All files remain reachable');
  }
  @IsTest
  static void shouldLoadFriendlyVersionLabelsInOneBoundedQuery() {
    QueryMock mock=new QueryMock();Test.setMock(HttpCalloutMock.class,mock);
    Test.startTest();Map<String,String> labels=new HeadlessPushGateway().versionLabels(new Set<String>{HeadlessV2TestSupport.TARGET_ID});Test.stopTest();
    Assert.areEqual('Billing 9.41.0.1',labels.get(HeadlessPushService.canonicalId(HeadlessV2TestSupport.TARGET_ID,'04t')),'Use a human-readable package version label');
    Assert.areEqual(1,mock.queries.size(),'Resolve only the versions on this run page');
  }
  private class QueryMock implements HttpCalloutMock {
    List<String> queries=new List<String>();Boolean coveragePassed=true,validationSkipped=false;
    public HttpResponse respond(HttpRequest request) {
      String query=EncodingUtil.urlDecode(request.getEndpoint(),'UTF-8');queries.add(query);
      List<Object> records=new List<Object>();
      if(query.contains('SELECT HasPassedCodeCoverageCheck')) {
        records.add(new Map<String,Object>{'HasPassedCodeCoverageCheck'=>coveragePassed,'ValidationSkipped'=>validationSkipped});
      } else if(query.contains('SELECT Id, Package2Id')) {
        records.add(new Map<String,Object>{'Id'=>'05i000000000002','Package2Id'=>'0Ho000000000001','SubscriberPackageVersionId'=>HeadlessV2TestSupport.TARGET_ID,
          'IsReleased'=>true,'IsDeprecated'=>false,'MajorVersion'=>9,'MinorVersion'=>41,'PatchVersion'=>0,'BuildNumber'=>1,
          'Package2'=>new Map<String,Object>{'SubscriberPackageId'=>HeadlessV2TestSupport.PACKAGE_ID,'ContainerOptions'=>'Unlocked'}});
      } else if(query.contains('WHERE Package2Id =')) {
        records.add(new Map<String,Object>{'SubscriberPackageVersionId'=>HeadlessV2TestSupport.OLD_ID,'MajorVersion'=>9,'MinorVersion'=>40,'PatchVersion'=>0,'BuildNumber'=>1});
      } else {records.add(HeadlessV2TestSupport.candidate());}
      HttpResponse response=new HttpResponse();response.setStatusCode(200);response.setHeader('Content-Type','application/json');
      response.setBody(JSON.serialize(new Map<String,Object>{'totalSize'=>records.size(),'done'=>true,'records'=>records}));return response;
    }
  }
}
