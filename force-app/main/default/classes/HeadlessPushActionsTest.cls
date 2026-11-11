/** Verifies the packaged invocable contracts delegate to the bounded workflow. */
@IsTest
private with sharing class HeadlessPushActionsTest {
  @IsTest
  static void shouldPrepareThroughInvocable() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(
      2
    );
    Test.startTest();
    List<HeadlessPushResponse> results = HeadlessPlanPushAction.run(
      new List<HeadlessPlanPushAction.Request>{
        HeadlessPushTestSupport.input(2)
      }
    );
    Test.stopTest();
    Assert.areEqual(
      1,
      results.size(),
      'Return one result per requested operation'
    );
    Assert.isTrue(
      results[0].isSuccess,
      (results[0].errorMessage ?? 'Operation should succeed')
    );
    Assert.areEqual(
      'PREPARING',
      results[0].state,
      'Preparing does not dispatch'
    );
    Assert.areEqual(
      2,
      results[0].expectedCount,
      'Expose the exact reviewed count'
    );
    Assert.areEqual(0, fake.statusWrites.size(), 'No Pending during prepare');
  }

  @IsTest
  static void shouldInspectThroughInvocable() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(
      2
    );
    HeadlessPushService.Manifest manifest = HeadlessPushTestSupport.savedManifest(
      fake,
      2
    );
    fake.platformJobs = HeadlessPushTestSupport.jobs(2);
    HeadlessPushStatusAction.Request request = new HeadlessPushStatusAction.Request();
    request.manifestVersionId = '068000000000099';
    request.digest = manifest.digest;
    Test.startTest();
    HeadlessPushResponse result = HeadlessPushStatusAction.run(
      new List<HeadlessPushStatusAction.Request>{ request }
    )[0];
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      'READY',
      result.state,
      'Only an exact complete cohort is ready'
    );
    Assert.areEqual(2, result.stagedCount, 'Counts include all approved jobs');
    Assert.areEqual(0, fake.statusWrites.size(), 'Inspect is read-only');
  }

  @IsTest
  static void shouldExecuteThroughInvocable() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(
      2
    );
    HeadlessPushService.Manifest manifest = HeadlessPushTestSupport.savedManifest(
      fake,
      2
    );
    fake.platformJobs = HeadlessPushTestSupport.jobs(2);
    HeadlessExecutePushAction.Request request = new HeadlessExecutePushAction.Request();
    request.manifestVersionId = '068000000000099';
    request.digest = manifest.digest;
    request.confirmed = true;
    Test.startTest();
    HeadlessPushResponse result = HeadlessExecutePushAction.run(
      new List<HeadlessExecutePushAction.Request>{ request }
    )[0];
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      new List<String>{ 'Pending' },
      fake.statusWrites,
      'Dispatch through the existing request'
    );
  }

  @IsTest
  static void shouldCancelThroughInvocable() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(
      2
    );
    HeadlessPushService.Manifest manifest = HeadlessPushTestSupport.savedManifest(
      fake,
      2
    );
    HeadlessCancelPushAction.Request request = new HeadlessCancelPushAction.Request();
    request.manifestVersionId = '068000000000099';
    request.digest = manifest.digest;
    Test.startTest();
    HeadlessPushResponse result = HeadlessCancelPushAction.run(
      new List<HeadlessCancelPushAction.Request>{ request }
    )[0];
    Test.stopTest();
    Assert.isTrue(result.isSuccess, (result.errorMessage ?? 'Operation should succeed'));
    Assert.areEqual(
      'Canceled',
      result.state,
      'Report the actual cancellation outcome'
    );
  }

  @IsTest
  static void shouldRejectBulkPreparationWithoutWrites() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(
      2
    );
    Test.startTest();
    List<HeadlessPushResponse> results = HeadlessPlanPushAction.run(
      new List<HeadlessPlanPushAction.Request>{
        HeadlessPushTestSupport.input(1),
        HeadlessPushTestSupport.input(1)
      }
    );
    Test.stopTest();
    Assert.areEqual(
      2,
      results.size(),
      'Report rejection for each invocable input'
    );
    Assert.isFalse(
      results[0].isSuccess,
      'Do not issue multiple campaigns in one invocation'
    );
    Assert.isFalse(results[1].isSuccess, 'Reject the full ambiguous operation');
    Assert.areEqual(
      0,
      fake.createCount,
      'No preparation side effects for bulk invocation'
    );
  }
  @IsTest
  static void shouldRejectBulkExecuteWithoutWrites() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(
      1
    );
    HeadlessExecutePushAction.Request input = new HeadlessExecutePushAction.Request();
    Test.startTest();
    List<HeadlessPushResponse> results = HeadlessExecutePushAction.run(
      new List<HeadlessExecutePushAction.Request>{ input, input }
    );
    Test.stopTest();
    Assert.areEqual(2, results.size(), 'Reject each input');
    Assert.isFalse(results[0].isSuccess, 'Reject multiple executions');
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'No writes for ambiguous invocation'
    );
  }
  @IsTest
  static void shouldRejectBulkStatusWithoutReads() {
    HeadlessPushStatusAction.Request input = new HeadlessPushStatusAction.Request();
    Test.startTest();
    List<HeadlessPushResponse> results = HeadlessPushStatusAction.run(
      new List<HeadlessPushStatusAction.Request>{ input, input }
    );
    Test.stopTest();
    Assert.areEqual(2, results.size(), 'Reject each input');
    Assert.isFalse(results[0].isSuccess, 'Reject multiple status operations');
  }
  @IsTest
  static void shouldRejectBulkCancelWithoutWrites() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(
      1
    );
    HeadlessCancelPushAction.Request input = new HeadlessCancelPushAction.Request();
    Test.startTest();
    List<HeadlessPushResponse> results = HeadlessCancelPushAction.run(
      new List<HeadlessCancelPushAction.Request>{ input, input }
    );
    Test.stopTest();
    Assert.areEqual(2, results.size(), 'Reject each input');
    Assert.isFalse(results[0].isSuccess, 'Reject multiple cancellations');
    Assert.areEqual(
      0,
      fake.statusWrites.size(),
      'No writes for ambiguous invocation'
    );
  }
}
