/** Verifies private manifest resumption and authoritative failed-only recovery. */
@IsTest
private with sharing class HeadlessPushRunServiceTest {
  @IsTest
  static void shouldReadExistingV1Manifest() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(2);
    HeadlessPushService.Manifest saved=HeadlessV2TestSupport.manifest(fake,2);
    Test.startTest();
    HeadlessPushService.Manifest loaded=HeadlessPushRunService.loadManifest(HeadlessV2TestSupport.MANIFEST_ID,saved.digest,fake);
    Test.stopTest();
    Assert.areEqual(saved.orgIds,loaded.orgIds,'Existing immutable v1 cohorts remain readable');
    Assert.areEqual(saved.digest,loaded.digest,'Resumption preserves the original digest');
    Assert.areEqual(0,fake.createCount,'Resumption does not create a new request');
  }
  @IsTest
  static void shouldRejectDifferentManifestOperator() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    HeadlessPushService.Manifest saved=HeadlessV2TestSupport.manifest(fake,1);
    saved.initiatorId='005000000000001';saved.digest=HeadlessPushService.digest(saved);
    fake.files.put(HeadlessV2TestSupport.MANIFEST_ID,JSON.serialize(saved));
    Test.startTest();
    try {
      HeadlessPushRunService.loadManifest(HeadlessV2TestSupport.MANIFEST_ID,saved.digest,fake);
      Assert.fail('A different manifest operator must not resume the run');
    } catch (HeadlessPushService.PushException expected) {
      Assert.isNotNull(expected.getMessage(),'Return a safe ownership failure');
    }
    Test.stopTest();
  }
  @IsTest
  static void shouldRejectWrongManifestDigest() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    HeadlessPushService.Manifest saved=HeadlessV2TestSupport.manifest(fake,1);
    Test.startTest();
    try {
      HeadlessPushRunService.loadManifest(HeadlessV2TestSupport.MANIFEST_ID,'wrong-digest',fake);
      Assert.fail('Digest changes require a fresh reviewed snapshot');
    } catch (HeadlessPushService.PushException expected) {
      Assert.isNotNull(expected.getMessage(),'Return a safe mismatch failure');
    }
    Test.stopTest();
  }
  @IsTest
  static void shouldRejectLiveTargetChange() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    HeadlessPushService.Manifest saved=HeadlessV2TestSupport.manifest(fake,1);
    saved.targetVersionId=HeadlessPushService.canonicalId(HeadlessV2TestSupport.OLD_ID,'04t');
    Test.startTest();
    try {
      HeadlessPushRunService.validateRequest(saved,fake);
      Assert.fail('Live target must match the manifest');
    } catch (HeadlessPushService.PushException expected) {
      Assert.isTrue(expected.getMessage().contains('Target'),'Explain target mismatch');
    }
    Test.stopTest();
  }
  @IsTest
  static void shouldSelectOnlyConfirmedFailedOrgs() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(2);
    HeadlessPushService.Manifest saved=HeadlessV2TestSupport.manifest(fake,2);
    fake.platformJobs=HeadlessPushTestSupport.jobs(2);
    fake.platformJobs[0].put('Status','Failed');fake.platformJobs[1].put('Status','Succeeded');
    Test.startTest();
    List<String> selected=HeadlessPushRunService.failedOrgIds(HeadlessV2TestSupport.MANIFEST_ID,saved.digest,fake);
    Test.stopTest();
    Assert.areEqual(new List<String>{saved.orgIds[0]},selected,'Exclude the successful subscriber');
    Assert.areEqual(0,fake.createCount,'Recovery selection is read-only');
    Assert.areEqual(0,fake.enqueueCount,'Recovery selection stages no jobs');
  }
  @IsTest
  static void shouldBlockRecoveryWhileParentIsActive() {
    HeadlessV2TestSupport.Gateway fake=recovery('Failed');fake.parentStatus='Pending';
    Test.startTest();
    assertRecoveryRejected(fake,'Active parent is not a completed recovery source');
    Test.stopTest();
  }
  @IsTest
  static void shouldBlockRecoveryWithPendingJob() {
    HeadlessV2TestSupport.Gateway fake=recovery('Pending');
    Test.startTest();
    assertRecoveryRejected(fake,'A pending job is not a confirmed failure');
    Test.stopTest();
  }
  @IsTest
  static void shouldBlockRecoveryWithUnknownJobStatus() {
    HeadlessV2TestSupport.Gateway fake=recovery('Unknown');
    Test.startTest();
    assertRecoveryRejected(fake,'Unknown outcomes must be reconciled');
    Test.stopTest();
  }
  @IsTest
  static void shouldBlockRecoveryWithIncompleteJobSet() {
    HeadlessV2TestSupport.Gateway fake=recovery('Failed');fake.platformJobs.clear();
    Test.startTest();
    assertRecoveryRejected(fake,'Missing jobs are not proof of failure');
    Test.stopTest();
  }
  @IsTest
  static void shouldBlockRecoveryWithDuplicateJobs() {
    HeadlessV2TestSupport.Gateway fake=recovery('Failed');
    fake.platformJobs.add(fake.platformJobs[0].clone());
    Test.startTest();
    assertRecoveryRejected(fake,'Duplicate native jobs require reconciliation');
    Test.stopTest();
  }
  @IsTest
  static void shouldBlockRecoveryOverlappingAnotherAttempt() {
    HeadlessV2TestSupport.Gateway fake=recovery('Failed');
    fake.overlaps.add(new Map<String,Object>{'SubscriberOrganizationKey'=>HeadlessPushTestSupport.keys(1)[0],'Status'=>'Pending','PackagePushRequestId'=>'0DV000000000002'});
    Test.startTest();
    assertRecoveryRejected(fake,'Overlapping active attempts must not be duplicated');
    Test.stopTest();
  }
  @IsTest
  static void shouldFindRunsWithoutReadingManifestBodies() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    fake.metadataRows.add(new Map<String,Object>{'Id'=>HeadlessV2TestSupport.MANIFEST_ID,
      'Title'=>'push-manifest-'+HeadlessV2TestSupport.REQUEST_ID+'.json','CreatedDate'=>System.now(),'CreatedById'=>UserInfo.getUserId()});
    HeadlessFindPushRunsAction.Request input=new HeadlessFindPushRunsAction.Request();
    Test.startTest();
    HeadlessPushService.Result found=HeadlessPushRunService.find(input,fake);
    Test.stopTest();
    Assert.isTrue(found.isSuccess,found.errorMessage ?? 'Run lookup succeeds');
    Assert.areEqual(0,fake.fileReads,'Lookup reads metadata only');
    Assert.areEqual(1,fake.requestBatchReads,'Request summaries are fetched in one batch');
    Assert.isTrue(found.candidatesJson.contains(HeadlessV2TestSupport.REQUEST_ID),'Return the matching run');
    Assert.isTrue(found.candidatesJson.contains('Billing 9.41.0.1'),'Operators recognize package names and versions rather than IDs');
  }
  @IsTest
  static void shouldReturnCompositeRunCursorForEqualTimestamps() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    Datetime captured=System.now().addDays(-1);
    for(Integer index=1;index<=10;index++) {
      fake.metadataRows.add(new Map<String,Object>{'Id'=>'068'+String.valueOf(index).leftPad(12,'0'),
        'Title'=>'push-manifest-0DV'+String.valueOf(index).leftPad(12,'0')+'.json',
        'CreatedDate'=>JSON.deserializeUntyped(JSON.serialize(captured)), 'CreatedById'=>UserInfo.getUserId()});
    }
    Test.startTest();HeadlessPushService.Result result=HeadlessPushRunService.find(new HeadlessFindPushRunsAction.Request(),fake);Test.stopTest();
    Assert.isTrue(result.isSuccess,result.errorMessage ?? 'Lookup succeeds');
    Assert.isTrue(result.hasMore,'Full page offers continuation');
    Assert.areEqual(captured,result.beforeDate,'Cursor handles real JSON timestamp strings');
    Assert.areEqual((String)fake.metadataRows[9].get('Id'),result.beforeId,'ID tie-break prevents skipped equal-date Files');
    Assert.areEqual(0,fake.fileReads,'Pagination reads metadata only');
  }
  @IsTest
  static void shouldBindRecoveryLineageIntoTheManifestDigest() {
    HeadlessV2TestSupport.Gateway fake=recovery('Failed');
    HeadlessPushService.Manifest source=(HeadlessPushService.Manifest)JSON.deserialize(fake.files.get(HeadlessV2TestSupport.MANIFEST_ID),HeadlessPushService.Manifest.class);
    HeadlessPlanPushAction.Request input=recoveryInput(source);
    Test.startTest();HeadlessPushService.Result prepared=HeadlessPushService.prepare(input);Test.stopTest();
    Assert.isTrue(prepared.isSuccess,prepared.errorMessage ?? 'Recovery prepares');
    HeadlessPushService.Manifest manifest=(HeadlessPushService.Manifest)JSON.deserialize(fake.files.get(prepared.manifestVersionId.left(15)),HeadlessPushService.Manifest.class);
    Assert.areEqual('pkgviz-headless-push-v2',manifest.format,'Recovery manifests use the lineage-aware format');
    Assert.areEqual(input.recoveryManifestVersionId,manifest.recoveryManifestVersionId,'Retain the verified original manifest');
    String reviewed=manifest.digest;manifest.recoveryDigest='tampered';
    Assert.areNotEqual(reviewed,HeadlessPushService.digest(manifest),'Recovery lineage cannot change under the same digest');
  }
  @IsTest
  static void shouldDispatchRecoveryWithoutTreatingItsOwnStagedJobAsOverlap() {
    HeadlessV2TestSupport.Gateway fake=recovery('Failed');
    HeadlessPushService.Manifest source=(HeadlessPushService.Manifest)JSON.deserialize(fake.files.get(HeadlessV2TestSupport.MANIFEST_ID),HeadlessPushService.Manifest.class);
    HeadlessPushService.Result prepared=HeadlessPushService.prepare(recoveryInput(source));
    Assert.isTrue(prepared.isSuccess,prepared.errorMessage ?? 'Recovery prepares');
    fake.jobsByRequest.put(prepared.requestId,HeadlessPushTestSupport.jobs(1));
    fake.competingRequestId=prepared.requestId;
    fake.overlaps.add(new Map<String,Object>{'Id'=>'0DX000000000001'});
    Test.startTest();HeadlessPushService.Result result=HeadlessPushService.dispatch(prepared.manifestVersionId,prepared.digest,true);Test.stopTest();
    Assert.isTrue(result.isSuccess,result.errorMessage ?? 'Reviewed recovery dispatches');
    Assert.areEqual('Pending',result.state,'Move the reviewed recovery to Pending');
    Assert.areEqual(prepared.requestId,fake.lastExcludedRequestId,'Exclude the exact prepared request, not an unrelated source');
    Assert.areEqual(1,fake.createCount,'Dispatch does not create an extra recovery');
  }
  @IsTest
  static void shouldBlockRecoveryIfOriginalOutcomeChangesBeforeDispatch() {
    HeadlessV2TestSupport.Gateway fake=recovery('Failed');
    HeadlessPushService.Manifest source=(HeadlessPushService.Manifest)JSON.deserialize(fake.files.get(HeadlessV2TestSupport.MANIFEST_ID),HeadlessPushService.Manifest.class);
    HeadlessPushService.Result prepared=HeadlessPushService.prepare(recoveryInput(source));
    Assert.isTrue(prepared.isSuccess,prepared.errorMessage ?? 'Recovery prepares');
    fake.jobsByRequest.put(prepared.requestId,HeadlessPushTestSupport.jobs(1));
    fake.platformJobs[0].put('Status','Succeeded');
    Test.startTest();HeadlessPushService.Result result=HeadlessPushService.dispatch(prepared.manifestVersionId,prepared.digest,true);Test.stopTest();
    Assert.isFalse(result.isSuccess,'A source outcome change invalidates the proposed recovery');
    Assert.areEqual('Created',fake.requestById.get(prepared.requestId).get('Status'),'Do not dispatch the stale recovery');
  }
  private static HeadlessPlanPushAction.Request recoveryInput(HeadlessPushService.Manifest source) {
    HeadlessPlanPushAction.Request input=new HeadlessPlanPushAction.Request();
    input.targetVersionId=HeadlessV2TestSupport.TARGET_ID;
    input.recoveryManifestVersionId=HeadlessV2TestSupport.MANIFEST_ID;
    input.recoveryDigest=source.digest;
    input.scheduledStartTime=System.now().addHours(2);
    return input;
  }
  @IsTest
  static void shouldBlockSuccessfulCompetingJobEvenWhenItsParentWasCanceled() {
    HeadlessV2TestSupport.Gateway fake=recovery('Failed');
    fake.overlaps.add(new Map<String,Object>{'Id'=>'0DX000000000002','Status'=>'Succeeded','PackagePushRequest'=>new Map<String,Object>{'Status'=>'Canceled'}});
    Test.startTest();assertRecoveryRejected(fake,'Canceling a parent cannot undo its successful subscriber job');Test.stopTest();
  }
  private static HeadlessV2TestSupport.Gateway recovery(String status) {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    HeadlessV2TestSupport.manifest(fake,1);
    fake.platformJobs=HeadlessPushTestSupport.jobs(1);fake.platformJobs[0].put('Status',status);
    return fake;
  }
  private static void assertRecoveryRejected(HeadlessV2TestSupport.Gateway fake,String reason) {
    HeadlessPushService.Manifest saved=(HeadlessPushService.Manifest)JSON.deserialize(fake.files.get(HeadlessV2TestSupport.MANIFEST_ID),HeadlessPushService.Manifest.class);
    try {
      HeadlessPushRunService.failedOrgIds(HeadlessV2TestSupport.MANIFEST_ID,saved.digest,fake);
      Assert.fail(reason);
    } catch (HeadlessPushService.PushException expected) {
      Assert.isNotNull(expected.getMessage(),'Return a recovery failure reason');
    }
    Assert.areEqual(0,fake.createCount,'Rejected recovery performs no write');
  }
}
