/** Exercises the real Queueable execute/finalizer path with a serialized boundary. */
@IsTest
private with sharing class HeadlessPushStageQueueableTest {
  @IsTest
  static void shouldCompleteRealQueuedStagingWithoutDispatch() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(
      2
    );
    HeadlessPushService.Manifest manifest = HeadlessPushTestSupport.savedManifest(
      fake,
      2
    );
    Test.startTest();
    Id jobId = System.enqueueJob(
      new HeadlessPushStageQueueable(
        '068000000000099',
        manifest.digest,
        0,
        fake
      )
    );
    Test.stopTest();
    AsyncApexJob job = [
      SELECT Status, NumberOfErrors
      FROM AsyncApexJob
      WHERE Id = :jobId
    ];
    Assert.areEqual(
      'Completed',
      job.Status,
      'Production queueable must complete without an HTTP or DML bypass'
    );
    Assert.areEqual(
      0,
      job.NumberOfErrors,
      'No staging or finalizer exceptions'
    );
  }

  @IsTest
  static void shouldStopUnauthorizedQueueAndRunFinalizer() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(
      2
    );
    HeadlessPushService.Manifest manifest = HeadlessPushTestSupport.savedManifest(
      fake,
      2
    );
    fake.denied = true;
    Test.startTest();
    Id jobId = System.enqueueJob(
      new HeadlessPushStageQueueable(
        '068000000000099',
        manifest.digest,
        0,
        fake
      )
    );
    Boolean denied = false;
    try {
      Test.stopTest();
    } catch (HeadlessPushService.PushException expected) {
      denied = true;
      Assert.areEqual(
        'Access denied',
        expected.getMessage(),
        'Authorization must stop worker execution'
      );
    }
    Assert.isTrue(
      denied,
      'Authorization failure must propagate from the real queued worker'
    );
  }
}
