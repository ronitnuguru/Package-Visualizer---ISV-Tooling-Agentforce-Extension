/** Verifies discovery, preview and run lookup through public invocable contracts. */
@IsTest
private with sharing class HeadlessV2ActionsTest {
  @IsTest
  static void shouldResolveOneReadyTarget() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    HeadlessResolvePushTargetAction.Request input=targetInput();
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessResolvePushTargetAction.run(new List<HeadlessResolvePushTargetAction.Request>{input});
    Test.stopTest();
    Assert.areEqual(1,result.size(),'Return one response per invocation');
    Assert.isTrue(result[0].isSuccess,result[0].errorMessage ?? 'Resolution succeeds');
    Assert.areEqual('RESOLVED',result[0].state,'No readiness blockers remain');
    Assert.isNotNull(result[0].targetVersionId,'Return the authoritative version ID');
    Assert.areEqual(0,fake.createCount,'Resolution never creates an upgrade');
  }
  @IsTest
  static void shouldKeepReadinessBlockersDistinctFromLookupSuccess() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    fake.readinessValue.put('eligible',false);
    fake.readinessValue.put('blockers',new List<String>{'The package version is not released.'});
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessResolvePushTargetAction.run(new List<HeadlessResolvePushTargetAction.Request>{targetInput()});
    Test.stopTest();
    Assert.isTrue(result[0].isSuccess,'Retrieving blocker evidence succeeds');
    Assert.areEqual('BLOCKED',result[0].state,'Retrieval success is not eligibility');
    Assert.isTrue(result[0].readinessJson.contains('not released'),'Preserve the actionable blocker');
  }
  @IsTest
  static void shouldRequireSelectionForAmbiguousTargets() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    fake.candidateRows.add(HeadlessV2TestSupport.candidate());
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessResolvePushTargetAction.run(new List<HeadlessResolvePushTargetAction.Request>{targetInput()});
    Test.stopTest();
    Assert.areEqual('NEEDS_SELECTION',result[0].state,'Never silently pick the first version');
    Assert.isNull(result[0].targetVersionId,'No exact target is chosen');
    Assert.areEqual(0,fake.createCount,'Ambiguity cannot create a request');
  }
  @IsTest
  static void shouldReturnNotFoundForMissingTargets() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);fake.candidateRows.clear();
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessResolvePushTargetAction.run(new List<HeadlessResolvePushTargetAction.Request>{targetInput()});
    Test.stopTest();
    Assert.areEqual('NOT_FOUND',result[0].state,'Distinguish no match from ambiguity');
    Assert.isNull(result[0].targetVersionId,'Do not invent a target');
  }
  @IsTest
  static void shouldResolveAnExactVersionWithoutNameLookup() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);fake.candidateRows.clear();
    HeadlessResolvePushTargetAction.Request input=new HeadlessResolvePushTargetAction.Request();input.targetVersionId=HeadlessV2TestSupport.TARGET_ID;
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessResolvePushTargetAction.run(new List<HeadlessResolvePushTargetAction.Request>{input});
    Test.stopTest();
    Assert.areEqual('RESOLVED',result[0].state,'Exact ID still receives readiness assessment');
  }
  @IsTest
  static void shouldRejectMissingTargetDescription() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessResolvePushTargetAction.run(new List<HeadlessResolvePushTargetAction.Request>{new HeadlessResolvePushTargetAction.Request()});
    Test.stopTest();
    Assert.isFalse(result[0].isSuccess,'Require a target selector');
    Assert.areEqual(0,fake.createCount,'Missing selectors never write');
  }
  @IsTest
  static void shouldReturnNoResponsesForNullResolveList() {
    Test.startTest();List<HeadlessPushResponse> result=HeadlessResolvePushTargetAction.run(null);Test.stopTest();
    Assert.areEqual(0,result.size(),'Null invocations are empty');
  }
  @IsTest
  static void shouldRejectMultipleResolveOperations() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessResolvePushTargetAction.run(new List<HeadlessResolvePushTargetAction.Request>{targetInput(),targetInput()});
    Test.stopTest();
    Assert.areEqual(2,result.size(),'Report each rejected operation');
    Assert.isFalse(result[0].isSuccess,'One campaign per invocation');
    Assert.isFalse(result[1].isSuccess,'Never silently drop the second operation');
  }
  @IsTest
  static void shouldPreviewThroughThePublicAction() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(2);
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessPreviewPushAction.run(new List<HeadlessPlanPushAction.Request>{HeadlessPushTestSupport.input(2)});
    Test.stopTest();
    Assert.isTrue(result[0].isSuccess,result[0].errorMessage ?? 'Preview succeeds');
    Assert.areEqual(2,result[0].expectedCount,'Structured contract exposes cohort count');
    Assert.isNotNull(result[0].selectionFingerprint,'Fingerprint is available to preparation');
    Assert.areEqual(0,fake.createCount,'Public preview is read-only');
  }
  @IsTest
  static void shouldRejectMultiplePreviewOperations() {
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessPreviewPushAction.run(new List<HeadlessPlanPushAction.Request>{HeadlessPushTestSupport.input(1),HeadlessPushTestSupport.input(1)});
    Test.stopTest();
    Assert.areEqual(2,result.size(),'Report every rejected input');
    Assert.isFalse(result[0].isSuccess,'Reject bulk campaign operation');
  }
  @IsTest
  static void shouldFindAnEmptyRunHistory() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessFindPushRunsAction.run(new List<HeadlessFindPushRunsAction.Request>{new HeadlessFindPushRunsAction.Request()});
    Test.stopTest();
    Assert.isTrue(result[0].isSuccess,result[0].errorMessage ?? 'Empty lookup succeeds');
    Assert.areEqual('[]',result[0].candidatesJson,'Return an empty collection');
    Assert.areEqual(0,fake.fileReads,'No File bodies are read');
  }
  @IsTest
  static void shouldResumeAnExplicitOwnedManifest() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);
    HeadlessPushService.Manifest saved=HeadlessV2TestSupport.manifest(fake,1);
    HeadlessFindPushRunsAction.Request input=new HeadlessFindPushRunsAction.Request();input.manifestVersionId=HeadlessV2TestSupport.MANIFEST_ID;
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessFindPushRunsAction.run(new List<HeadlessFindPushRunsAction.Request>{input});
    Test.stopTest();
    Assert.isTrue(result[0].isSuccess,result[0].errorMessage ?? 'Owned run resumes');
    Assert.areEqual(saved.digest,result[0].digest,'Return exact internal digest for subsequent tools');
    Assert.areEqual(0,fake.createCount,'Resumption never prepares another request');
  }
  @IsTest
  static void shouldRejectMultipleRunLookups() {
    Test.startTest();
    List<HeadlessPushResponse> result=HeadlessFindPushRunsAction.run(new List<HeadlessFindPushRunsAction.Request>{new HeadlessFindPushRunsAction.Request(),new HeadlessFindPushRunsAction.Request()});
    Test.stopTest();
    Assert.areEqual(2,result.size(),'Return one rejection per operation');
    Assert.isFalse(result[0].isSuccess,'Reject the ambiguous multi-operation request');
  }
  @IsTest
  static void shouldDenyTargetResolutionWithoutProductPermission() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);fake.denied=true;
    Test.startTest();List<HeadlessPushResponse> result=HeadlessResolvePushTargetAction.run(new List<HeadlessResolvePushTargetAction.Request>{targetInput()});Test.stopTest();
    Assert.isFalse(result[0].isSuccess,'Unauthorized identity receives no target evidence');
    Assert.isNull(result[0].candidatesJson,'Do not disclose package candidates');
  }
  @IsTest
  static void shouldDenyPreviewWithoutProductPermission() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);fake.denied=true;
    Test.startTest();List<HeadlessPushResponse> result=HeadlessPreviewPushAction.run(new List<HeadlessPlanPushAction.Request>{HeadlessPushTestSupport.input(1)});Test.stopTest();
    Assert.isFalse(result[0].isSuccess,'Unauthorized identity cannot preview subscribers');
    Assert.areEqual(0,fake.createCount,'Denied preview has no writes');
  }
  @IsTest
  static void shouldDenyRunLookupWithoutProductPermission() {
    HeadlessV2TestSupport.Gateway fake=HeadlessV2TestSupport.install(1);fake.denied=true;
    Test.startTest();List<HeadlessPushResponse> result=HeadlessFindPushRunsAction.run(new List<HeadlessFindPushRunsAction.Request>{new HeadlessFindPushRunsAction.Request()});Test.stopTest();
    Assert.isFalse(result[0].isSuccess,'Unauthorized identity cannot discover runs');
    Assert.areEqual(0,fake.requestBatchReads,'Deny before reading platform requests');
  }
  private static HeadlessResolvePushTargetAction.Request targetInput() {
    HeadlessResolvePushTargetAction.Request input=new HeadlessResolvePushTargetAction.Request();input.packageName='Billing';input.versionNumber='9.41';return input;
  }
}
