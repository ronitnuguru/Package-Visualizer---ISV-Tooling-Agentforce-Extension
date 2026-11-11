/** Isolated workflow tests using the virtual Salesforce integration boundary. */
@IsTest
private with sharing class HeadlessPushServiceTest {
  @IsTest
  static void shouldPrepare251OrgsWithoutDispatch() {
    HeadlessPushTestSupport.FakeGateway fake = install(251);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(input(251));
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      251,
      result.expectedCount,
      'Preparation must retain every selected org'
    );
    Assert.areEqual(1, fake.createCount, 'One cohort needs one request');
    Assert.areEqual(1, fake.enqueueCount, 'Queue staging after File writes');
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'Preparation must never dispatch'
    );
    Assert.isNotNull(
      result.manifestVersionId,
      'Return the immutable manifest version'
    );
    Assert.isNotNull(result.csvVersionId, 'Return the downloadable cohort CSV');
  }

  @IsTest
  static void shouldPrepare2000Orgs() {
    HeadlessPushTestSupport.FakeGateway fake = install(2000);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(
      input(2000)
    );
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      2000,
      result.expectedCount,
      'The full v1 boundary must be retained'
    );
    Assert.areEqual(
      1,
      fake.createCount,
      'Never split a run into multiple requests'
    );
  }

  @IsTest
  static void shouldReject2001OrgsBeforeWrites() {
    HeadlessPushTestSupport.FakeGateway fake = install(2001);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(
      input(2001)
    );
    Test.stopTest();
    Assert.isFalse(result.isSuccess, 'Oversized selections must fail');
    Assert.areEqual(
      0,
      fake.createCount,
      'Do not silently truncate and create a request'
    );
    Assert.areEqual(
      0,
      fake.savedFiles.size(),
      'Rejected selections have no snapshots'
    );
  }

  @IsTest
  static void shouldRejectUnauthorizedPreparation() {
    HeadlessPushTestSupport.FakeGateway fake = install(1);
    fake.denied = true;
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(input(1));
    Test.stopTest();
    Assert.isFalse(result.isSuccess, 'Authorization is required');
    Assert.areEqual(0, fake.createCount, 'No writes on authorization failure');
  }

  @IsTest
  static void shouldRejectAmbiguousSources() {
    HeadlessPushTestSupport.FakeGateway fake = install(1);
    HeadlessPlanPushAction.Request request = input(1);
    request.sourceFileVersionId = '068000000000001';
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(request);
    Test.stopTest();
    Assert.isFalse(result.isSuccess, 'Supply one cohort source');
    Assert.areEqual(
      0,
      fake.createCount,
      'Invalid source selection cannot create a request'
    );
  }

  @IsTest
  static void shouldRefuseDispatchWithoutConfirmation() {
    HeadlessPushTestSupport.FakeGateway fake = install(1);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 1);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.dispatch(
      '068000000000099',
      manifest.digest,
      false
    );
    Test.stopTest();
    Assert.isFalse(
      result.isSuccess,
      'Client confirmation assertion remains required'
    );
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'No status update before confirmation'
    );
  }

  @IsTest
  static void shouldDispatchExactCompletedCohort() {
    HeadlessPushTestSupport.FakeGateway fake = install(2);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 2);
    fake.platformJobs = HeadlessPushTestSupport.jobs(2);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.dispatch(
      '068000000000099',
      manifest.digest,
      true
    );
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(1, fake.overlapReads, 'Check for conflicts before dispatch');
    Assert.areEqual(
      new List<String>{ 'Pending' },
      fake.statusWrites,
      'Dispatch precisely once'
    );
    Assert.areEqual(
      0,
      fake.createCount,
      'Dispatch must reuse the prepared request'
    );
  }

  @IsTest
  static void shouldRejectDispatchWhenAnotherRequestOverlaps() {
    HeadlessPushTestSupport.FakeGateway fake = install(2);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 2);
    fake.platformJobs = HeadlessPushTestSupport.jobs(2);
    fake.overlapRows.add(new Map<String, Object>{'Id' => '0DX000000000001'});
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.dispatch(
      '068000000000099', manifest.digest, true
    );
    Test.stopTest();
    Assert.isFalse(result.isSuccess, 'A competing attempt prevents dispatch');
    Assert.isTrue(result.errorMessage.contains('overlaps this cohort'), 'Explain the conflict');
    Assert.areEqual(1, fake.overlapReads, 'Revalidate overlaps before dispatch');
    Assert.areEqual(0, fake.statusWrites.size(), 'Do not submit the conflicting request');
  }

  @IsTest
  static void shouldRefuseIncompleteCohort() {
    HeadlessPushTestSupport.FakeGateway fake = install(2);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 2);
    fake.platformJobs = HeadlessPushTestSupport.jobs(1);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.dispatch(
      '068000000000099',
      manifest.digest,
      true
    );
    Test.stopTest();
    Assert.isFalse(result.isSuccess, 'Partial staging is not ready');
    Assert.areEqual(0, fake.statusWrites.size(), 'Do not dispatch a subset');
  }

  @IsTest
  static void shouldRefuseChangedDigest() {
    HeadlessPushTestSupport.FakeGateway fake = install(1);
    savedManifest(fake, 1);
    fake.platformJobs = HeadlessPushTestSupport.jobs(1);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.dispatch(
      '068000000000099',
      'changed',
      true
    );
    Test.stopTest();
    Assert.isFalse(result.isSuccess, 'Reviewed digest must match');
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'Changed snapshot cannot dispatch'
    );
  }

  @IsTest
  static void shouldNotRedispatchPendingRequest() {
    HeadlessPushTestSupport.FakeGateway fake = install(1);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 1);
    fake.parentStatus = 'Pending';
    fake.platformJobs = HeadlessPushTestSupport.jobs(1);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.dispatch(
      '068000000000099',
      manifest.digest,
      true
    );
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'Repeated execute returns current state'
    );
  }

  @IsTest
  static void shouldCancelCreatedRequest() {
    HeadlessPushTestSupport.FakeGateway fake = install(1);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 1);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.cancel(
      '068000000000099',
      manifest.digest
    );
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      new List<String>{ 'Canceled' },
      fake.statusWrites,
      'Cancel through the existing request'
    );
  }

  @IsTest
  static void shouldRefuseCancelRunningRequest() {
    HeadlessPushTestSupport.FakeGateway fake = install(1);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 1);
    fake.parentStatus = 'InProgress';
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.cancel(
      '068000000000099',
      manifest.digest
    );
    Test.stopTest();
    Assert.isFalse(
      result.isSuccess,
      'Running upgrades cannot be rolled back by cancel'
    );
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'No unsupported status transition'
    );
  }

  @IsTest
  static void shouldStage251AcrossProductionChunksWithoutDispatch() {
    HeadlessPushTestSupport.FakeGateway fake = install(251);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 251);
    Test.startTest();
    HeadlessPushService.stage('068000000000099', manifest.digest, 0);
    HeadlessPushService.stage('068000000000099', manifest.digest, 200);
    Test.stopTest();
    Assert.areEqual(
      new List<Integer>{ 200, 51 },
      fake.chunkSizes,
      'Use the production 200-org chunk boundary'
    );
    Assert.areEqual(251, fake.platformJobs.size(), 'Stage every approved org');
    Assert.areEqual(1, fake.enqueueCount, 'Only the intermediate chunk chains');
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'Final staging chunk must leave Created'
    );
  }

  @IsTest
  static void shouldStage2000AcrossExactlyTenChunks() {
    HeadlessPushTestSupport.FakeGateway fake = install(2000);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 2000);
    Test.startTest();
    for (Integer offset = 0; offset < 2000; offset += 200) {
      HeadlessPushService.stage('068000000000099', manifest.digest, offset);
    }
    Test.stopTest();
    Assert.areEqual(
      10,
      fake.chunkSizes.size(),
      'The approved v1 boundary needs ten collection submissions'
    );
    Assert.areEqual(
      2000,
      fake.platformJobs.size(),
      'No lost targets across chunks'
    );
    Assert.areEqual(9, fake.enqueueCount, 'Last chunk must not chain');
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'Staging never dispatches even at full capacity'
    );
  }

  @IsTest
  static void shouldStopCanceledStagingBeforeCollectionWrite() {
    HeadlessPushTestSupport.FakeGateway fake = install(251);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 251);
    fake.parentStatus = 'Canceled';
    Test.startTest();
    HeadlessPushService.stage('068000000000099', manifest.digest, 0);
    Test.stopTest();
    Assert.areEqual(
      0,
      fake.chunkSizes.size(),
      'A canceled request cannot receive another chunk'
    );
    Assert.areEqual(0, fake.enqueueCount, 'Do not continue a canceled chain');
  }

  @IsTest
  static void shouldCancelPartialSubmissionAndPersistReport() {
    HeadlessPushTestSupport.FakeGateway fake = install(251);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 251);
    fake.partialFailure = true;
    Test.startTest();
    HeadlessPushService.stage('068000000000099', manifest.digest, 0);
    Test.stopTest();
    Assert.areEqual(
      new List<String>{ 'Canceled' },
      fake.statusWrites,
      'An incomplete cohort must not dispatch'
    );
    Assert.areEqual(
      0,
      fake.enqueueCount,
      'Do not stage later chunks after a known failure'
    );
    Assert.areEqual(
      3,
      fake.savedFiles.size(),
      'Retain manifest, CSV and partial-submission report'
    );
  }

  @IsTest
  static void shouldNotReplayUncertainSubmission() {
    HeadlessPushTestSupport.FakeGateway fake = install(251);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 251);
    fake.uncertain = true;
    Test.startTest();
    HeadlessPushService.stage('068000000000099', manifest.digest, 0);
    Test.stopTest();
    Assert.areEqual(
      1,
      fake.chunkSizes.size(),
      'Never automatically replay a timed-out write'
    );
    Assert.areEqual(
      0,
      fake.enqueueCount,
      'Uncertain writes require reconciliation'
    );
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'Do not dispatch or guess a remote outcome'
    );
    Assert.areEqual(
      3,
      fake.savedFiles.size(),
      'Persist the uncertain outcome for the operator'
    );
  }

  private static HeadlessPlanPushAction.Request input(Integer count) {
    return HeadlessPushTestSupport.input(count);
  }
  private static HeadlessPushTestSupport.FakeGateway install(Integer count) {
    return HeadlessPushTestSupport.install(count);
  }
  private static HeadlessPushService.Manifest savedManifest(
    HeadlessPushTestSupport.FakeGateway fake,
    Integer count
  ) {
    return HeadlessPushTestSupport.savedManifest(fake, count);
  }
}
