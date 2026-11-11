/** Behavioral checks for read-only cohort selection and drift detection. */
@IsTest
private with sharing class HeadlessPushSelectionTest {
  @IsTest
  static void shouldPreviewWithoutRemoteOrLocalWrites() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(2);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.preview(HeadlessPushTestSupport.input(2));
    Test.stopTest();
    Assert.isTrue(result.isSuccess, result.errorMessage ?? 'Preview succeeds');
    Assert.areEqual(2, result.expectedCount, 'Both eligible orgs are counted');
    Assert.areEqual(0, fake.createCount, 'Preview creates no request');
    Assert.areEqual(0, fake.enqueueCount, 'Preview starts no worker');
    Assert.areEqual(0, fake.savedFiles.size(), 'Preview saves no files');
    Assert.areEqual(0, fake.statusWrites.size(), 'Preview never dispatches');
    Assert.isNotNull(result.selectionFingerprint, 'Return a comparison fingerprint');
  }

  @IsTest
  static void shouldCountDuplicateIdsInPreview() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(2);
    HeadlessPlanPushAction.Request input = HeadlessPushTestSupport.input(2);
    input.orgIdsText += '\n' + HeadlessPushTestSupport.keys(2)[0];
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.preview(input);
    Test.stopTest();
    Assert.isTrue(result.isSuccess, result.errorMessage ?? 'Preview succeeds');
    Assert.areEqual(3, result.suppliedCount, 'Count raw supplied IDs');
    Assert.areEqual(1, result.duplicateCount, 'Report the duplicate');
    Assert.areEqual(2, result.expectedCount, 'Do not double-count the cohort');
  }

  @IsTest
  static void shouldExplainInvalidTokensWithoutPreparing() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(1);
    HeadlessPlanPushAction.Request input = HeadlessPushTestSupport.input(1);
    input.orgIdsText += '\ninvalid-org';
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.preview(input);
    Test.stopTest();
    Assert.isTrue(result.isSuccess, result.errorMessage ?? 'Return an explanatory preview');
    Assert.areEqual(1, result.invalidCount, 'Identify the invalid token');
    Assert.areEqual(1, result.expectedCount, 'Retain the valid eligible row');
    Assert.areEqual(0, fake.createCount, 'No request is created');
  }

  @IsTest
  static void shouldRejectInvalidTokensDuringPreparation() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(1);
    HeadlessPlanPushAction.Request input = HeadlessPushTestSupport.input(1);
    input.orgIdsText += '\ninvalid-org';
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(input);
    Test.stopTest();
    Assert.isFalse(result.isSuccess, 'Do not silently omit invalid input on write');
    Assert.areEqual(0, fake.createCount, 'Reject before remote writes');
  }

  @IsTest
  static void shouldKeepFingerprintStableAcrossInputOrdering() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(2);
    HeadlessPlanPushAction.Request first = HeadlessPushTestSupport.input(2);
    HeadlessPlanPushAction.Request second = HeadlessPushTestSupport.input(2);
    List<String> ids = HeadlessPushTestSupport.keys(2);
    second.orgIdsText = ids[1] + '\n' + ids[0];
    Test.startTest();
    HeadlessPushService.Result a = HeadlessPushService.preview(first);
    HeadlessPushService.Result b = HeadlessPushService.preview(second);
    Test.stopTest();
    Assert.isTrue(a.isSuccess, a.errorMessage ?? 'First preview succeeds');
    Assert.isTrue(b.isSuccess, b.errorMessage ?? 'Second preview succeeds');
    Assert.areEqual(a.selectionFingerprint, b.selectionFingerprint, 'Fingerprint binds the canonical cohort');
  }

  @IsTest
  static void shouldBlockChangedCohortBeforePreparationWrites() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(2);
    HeadlessPlanPushAction.Request input = HeadlessPushTestSupport.input(2);
    HeadlessPushService.Result preview = HeadlessPushService.preview(input);
    input.selectionFingerprint = preview.selectionFingerprint;
    fake.subscriberRows = HeadlessPushTestSupport.subscribers(1);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(input);
    Test.stopTest();
    Assert.isFalse(result.isSuccess, 'Review is stale when eligibility changes');
    Assert.areEqual(0, fake.createCount, 'Detect drift before request creation');
    Assert.areEqual(0, fake.savedFiles.size(), 'Stale preview creates no artifacts');
  }

  @IsTest
  static void shouldPrepareUnchangedReviewedCohort() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(2);
    HeadlessPlanPushAction.Request input = HeadlessPushTestSupport.input(2);
    input.selectionFingerprint = HeadlessPushService.preview(input).selectionFingerprint;
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.prepare(input);
    Test.stopTest();
    Assert.isTrue(result.isSuccess, result.errorMessage ?? 'Reviewed cohort prepares');
    Assert.areEqual(1, fake.createCount, 'Create exactly one native request');
    Assert.areEqual(1, fake.enqueueCount, 'Stage the reviewed cohort once');
  }

  @IsTest
  static void shouldPreview251OrgsWithoutPerOrgWrites() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(251);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.preview(HeadlessPushTestSupport.input(251));
    Test.stopTest();
    Assert.isTrue(result.isSuccess, result.errorMessage ?? 'Bulk preview succeeds');
    Assert.areEqual(251, result.expectedCount, 'Retain the complete bulk cohort');
    Assert.areEqual(0, fake.createCount, 'No per-org request writes');
    Assert.areEqual(0, fake.enqueueCount, 'No per-org jobs');
  }

  @IsTest
  static void shouldRejectNullPreviewInput() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(1);
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.preview(null);
    Test.stopTest();
    Assert.isFalse(result.isSuccess, 'Null input is a structured error');
    Assert.areEqual(0, fake.createCount, 'Invalid preview creates no request');
  }

  @IsTest
  static void shouldExplainRestrictionsAndExclusions() {
    HeadlessPushTestSupport.FakeGateway fake = HeadlessPushTestSupport.install(3);
    fake.subscriberRows[1].put('HasRestrictionEnabled', true);
    fake.subscriberRows[1].put('IsCustomUpgradeAllowed', false);
    HeadlessPlanPushAction.Request input = HeadlessPushTestSupport.input(3);
    input.excludeOrgIds = new List<String>{HeadlessPushTestSupport.keys(3)[0]};
    Test.startTest();
    HeadlessPushService.Result result = HeadlessPushService.preview(input);
    Test.stopTest();
    Assert.isTrue(result.isSuccess, result.errorMessage ?? 'Preview succeeds');
    Assert.areEqual(1, result.expectedCount, 'Only the unrestricted, included org qualifies');
    Assert.areEqual(2, result.excludedCount, 'Count both exclusions');
    Assert.isTrue(result.excludedJson.contains('PUSH_RESTRICTED'), 'Explain the restriction');
    Assert.isTrue(result.excludedJson.contains('EXCLUDED'), 'Explain the explicit exclusion');
  }
}
