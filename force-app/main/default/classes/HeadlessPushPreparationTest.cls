/** Verifies preparation sources, exclusions, schedules, and saved snapshots. */
@IsTest
private with sharing class HeadlessPushPreparationTest {
  @IsTest
  static void shouldPrepareSameCohortFromCSV() {
    HeadlessPushTestSupport.FakeGateway fake = install(2);
    fake.savedFiles.put(
      '068000000000100',
      String.join(HeadlessPushTestSupport.keys(2), '\n')
    );
    HeadlessPlanPushAction.Request request = input(2);
    request.orgIdsText = null;
    request.sourceFileVersionId = '068000000000100';
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(request);
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      2,
      result.expectedCount,
      'CSV selection must retain the same cohort'
    );
  }

  @IsTest
  static void shouldPreparePackageAndOrgFilters() {
    HeadlessPushTestSupport.FakeGateway fake = install(2);
    HeadlessPlanPushAction.Request request = input(2);
    request.orgIdsText = null;
    request.orgTypes = new List<String>{ 'Sandbox' };
    request.installedVersionIds = new List<String>{ '04t000000000001' };
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(request);
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      2,
      result.expectedCount,
      'Typed filters select the full matching cohort'
    );
  }

  @IsTest
  static void shouldRecordExplicitExclusions() {
    HeadlessPushTestSupport.FakeGateway fake = install(2);
    HeadlessPlanPushAction.Request request = input(2);
    request.excludeOrgIds = new List<String>{
      HeadlessPushTestSupport.keys(2)[0]
    };
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(request);
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      1,
      result.expectedCount,
      'Only the reviewed nonexcluded org is staged'
    );
    Assert.isTrue(
      result.excludedJson.contains('EXCLUDED'),
      'Return the exclusion reason'
    );
  }

  @IsTest
  static void shouldRejectFilterSourceWithoutEnvironment() {
    HeadlessPushTestSupport.FakeGateway fake = install(1);
    HeadlessPlanPushAction.Request request = input(1);
    request.orgIdsText = null;
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(request);
    Test.stopTest();
    Assert.isFalse(
      result.isSuccess,
      'Filter selection requires Sandbox or Production'
    );
    Assert.areEqual(0, fake.createCount, 'No implicit production selection');
  }

  @IsTest
  static void shouldPreserveExplicitFutureSchedule() {
    HeadlessPushTestSupport.FakeGateway fake = install(1);
    HeadlessPlanPushAction.Request request = input(1);
    request.scheduledStartTime = System.now().addHours(1);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(request);
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      request.scheduledStartTime,
      fake.schedule,
      'Never replace the reviewed future start time'
    );
  }

  @IsTest
  static void shouldRejectChangedCSVBeforeDispatch() {
    HeadlessPushTestSupport.FakeGateway fake = install(2);
    HeadlessPushService.Manifest manifest = savedManifest(fake, 2);
    fake.savedFiles.put(manifest.csvVersionId, '00D000000000099');
    fake.platformJobs = HeadlessPushTestSupport.jobs(2);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.dispatch(
      '068000000000099',
      manifest.digest,
      true
    );
    Test.stopTest();
    Assert.isFalse(
      result.isSuccess,
      'Changed CSV must not match the reviewed snapshot'
    );
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'No dispatch after cohort mutation'
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
