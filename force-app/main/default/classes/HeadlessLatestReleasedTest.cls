/** Regression tests for selecting the latest released push target. */
@IsTest
private with sharing class HeadlessLatestReleasedTest {
  private static final String RELEASED_ID = '04tRh000001bbG9IAI';
  private static final String BETA_ID = '04t5w000005uiIUAAY';
  private static final String PACKAGE_ID = '0Ho5w000000KyxwCAC';

  private static HeadlessResolvePushTargetAction.Request latestRequest() {
    HeadlessResolvePushTargetAction.Request input = new HeadlessResolvePushTargetAction.Request();
    input.packageName = 'Package Visualizer';
    input.latestReleased = true;
    return input;
  }

  private static HeadlessPushResponse run(HeadlessResolvePushTargetAction.Request input) {
    return HeadlessResolvePushTargetAction.run(new List<HeadlessResolvePushTargetAction.Request>{ input })[0];
  }

  private static FakeGateway install() {
    FakeGateway fake = new FakeGateway();
    HeadlessPushService.gateway = fake;
    return fake;
  }

  @IsTest
  static void shouldResolveHighestReleasedInsteadOfHigherBeta() {
    FakeGateway fake = install();
    fake.latestRows.add(candidate(RELEASED_ID));
    Test.startTest();
    HeadlessPushResponse result = run(latestRequest());
    Test.stopTest();
    Assert.isTrue(result.isSuccess, 'Latest released lookup should succeed');
    Assert.areEqual('RESOLVED', result.state, 'Latest released target must be resolved');
    Assert.areEqual(RELEASED_ID, result.targetVersionId, 'Never choose the higher unreleased 10.0.0.1');
    Assert.areEqual(1, fake.latestCalls, 'Use latest-released selection');
    Assert.areEqual(0, fake.regularCalls, 'Never choose from the regular version list');
    Assert.areEqual(0, fake.writeCount, 'Resolution remains read only');
  }

  @IsTest
  static void shouldAcceptLatestVersionAlias() {
    FakeGateway fake = install();
    fake.latestRows.add(candidate(RELEASED_ID));
    HeadlessResolvePushTargetAction.Request input = new HeadlessResolvePushTargetAction.Request();
    input.packageName = 'Package Visualizer';
    input.versionNumber = 'latest';
    Test.startTest(); HeadlessPushResponse result = run(input); Test.stopTest();
    Assert.areEqual('RESOLVED', result.state, 'Latest alias means latest released for push');
    Assert.areEqual(RELEASED_ID, result.targetVersionId, 'Alias uses the released candidate');
    Assert.areEqual(1, fake.latestCalls, 'Alias selects the authoritative latest lookup');
  }

  @IsTest
  static void shouldReturnNotFoundWhenPackageDoesNotExist() {
    FakeGateway fake = install();
    Test.startTest(); HeadlessPushResponse result = run(latestRequest()); Test.stopTest();
    Assert.areEqual('NOT_FOUND', result.state, 'A missing package must not select a beta');
    Assert.isNull(result.targetVersionId, 'No inferred target');
    Assert.areEqual(0, fake.writeCount, 'No writes');
  }

  @IsTest
  static void shouldExplainWhenExistingPackageHasNoReleasedVersion() {
    FakeGateway fake = install();
    fake.latestRows.add(new Map<String,Object>{'Package2Id' => PACKAGE_ID, 'noReleasedVersions' => true});
    Test.startTest(); HeadlessPushResponse result = run(latestRequest()); Test.stopTest();
    Assert.areEqual('NO_RELEASED_VERSION', result.state, 'An existing package with no release is distinct from a missing package');
    Assert.isNull(result.targetVersionId, 'A beta is never selected as a push target');
    Assert.areEqual(0, fake.writeCount, 'This is a read-only lookup');
  }

  @IsTest
  static void shouldAskForPackageSelectionWhenNamesAreAmbiguous() {
    FakeGateway fake = install();
    fake.latestRows.add(new Map<String,Object>{'Package2Id' => '0Ho5w000000KyxwCAC', 'packageName' => 'Package Visualizer'});
    fake.latestRows.add(new Map<String,Object>{'Package2Id' => '0Ho5w000000KyxnCAC', 'packageName' => 'Package Visualizer'});
    Test.startTest(); HeadlessPushResponse result = run(latestRequest()); Test.stopTest();
    Assert.areEqual('NEEDS_SELECTION', result.state, 'Duplicate package names require explicit disambiguation');
    Assert.isNull(result.targetVersionId, 'Do not guess which package owns the target');
    Assert.areEqual(0, fake.writeCount, 'Ambiguous discovery never writes');
  }

  @IsTest
  static void shouldReturnBlockedWhenLatestReleasedHasIndependentBlocker() {
    FakeGateway fake = install();
    fake.latestRows.add(candidate(RELEASED_ID));
    fake.isEligible = false;
    Test.startTest(); HeadlessPushResponse result = run(latestRequest()); Test.stopTest();
    Assert.areEqual('BLOCKED', result.state, 'Report the latest released target as blocked');
    Assert.areEqual(RELEASED_ID, result.targetVersionId, 'Do not silently substitute an older version');
    Assert.isTrue(result.readinessJson.contains('coverage'), 'Explain the specific blocker');
  }

  @IsTest
  static void shouldDiagnoseExplicitUnreleasedId() {
    FakeGateway fake = install(); fake.isEligible = false;
    HeadlessResolvePushTargetAction.Request input = new HeadlessResolvePushTargetAction.Request(); input.targetVersionId = BETA_ID;
    Test.startTest(); HeadlessPushResponse result = run(input); Test.stopTest();
    Assert.areEqual('BLOCKED', result.state, 'An explicit beta version remains diagnosable');
    Assert.areEqual(BETA_ID, result.targetVersionId, 'Report the version the user requested');
    Assert.areEqual(0, fake.latestCalls, 'Explicit IDs do not trigger latest selection');
  }

  @IsTest
  static void shouldRejectLatestWithAnExplicitNumericVersion() {
    FakeGateway fake = install();
    HeadlessResolvePushTargetAction.Request input = latestRequest(); input.versionNumber = '9.40.0.1';
    Test.startTest(); HeadlessPushResponse result = run(input); Test.stopTest();
    Assert.isFalse(result.isSuccess, 'Latest and a specific version conflict');
    Assert.areEqual(0, fake.writeCount, 'Conflicting input never writes');
  }

  @IsTest
  static void shouldQueryOnlyReleasedVersionsAfterExactPackageResolution() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    List<Map<String,Object>> rows = new HeadlessPushGateway().lookupLatestReleased('Package Visualizer', null);
    Test.stopTest();
    Assert.areEqual(2, mock.queries.size(), 'Resolve package identity before its version');
    Assert.isTrue(mock.queries[0].contains('Package2'), 'First query resolves package identity');
    Assert.isTrue(mock.queries[0].contains('IsDeprecated=false'), 'Exclude deprecated packages');
    Assert.isTrue(mock.queries[0].contains('LIMIT 2'), 'Detect duplicate package names');
    String query = mock.queries[1];
    Assert.isTrue(query.contains('IsReleased=true'), 'Never return an unreleased target');
    Assert.isTrue(query.contains('IsDeprecated=false'), 'Never return a deprecated target');
    Assert.isTrue(query.contains(PACKAGE_ID), 'Restrict the version query to the selected package');
    Assert.isTrue(query.contains('ORDER BY MajorVersion DESC, MinorVersion DESC, PatchVersion DESC, BuildNumber DESC, Id DESC'), 'Order by the version tuple and stable identity');
    Assert.isTrue(query.contains('LIMIT 2'), 'Read two candidates to detect identical latest version tuples');
    Assert.areEqual(RELEASED_ID, rows[0].get('SubscriberPackageVersionId'), 'Released 9.41 wins over unreleased 10.0');
  }

  @IsTest
  static void shouldStopBeforeVersionQueryWhenPackageNameMatchesTwice() {
    LatestQueryMock mock = new LatestQueryMock(); mock.duplicatePackages = true; Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest(); List<Map<String,Object>> rows = new HeadlessPushGateway().lookupLatestReleased('Package Visualizer', null); Test.stopTest();
    Assert.areEqual(1, mock.queries.size(), 'Do not guess a package and query its versions');
    Assert.areEqual(2, rows.size(), 'Return package selection candidates');
  }

  @IsTest
  static void shouldReturnNoReleasedMarkerWhenPackageHasNoReleasedVersion() {
    LatestQueryMock mock = new LatestQueryMock(); mock.noReleased = true; Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest(); List<Map<String,Object>> rows = new HeadlessPushGateway().lookupLatestReleased('Package Visualizer', null); Test.stopTest();
    Assert.areEqual(1, rows.size(), 'The gateway returns the resolved package with a no-releases marker');
    Assert.areEqual(true, rows[0].get('noReleasedVersions'), 'Do not confuse an existing package with a missing package');
    Assert.areEqual(PACKAGE_ID, rows[0].get('Package2Id'), 'Keep the authoritative package identity');
  }

  @IsTest
  static void shouldResolveASelectedPackageAfterNameDisambiguation() {
    FakeGateway fake = install(); fake.latestRows.add(candidate(RELEASED_ID));
    HeadlessResolvePushTargetAction.Request input = latestRequest(); input.packageId = PACKAGE_ID;
    Test.startTest(); HeadlessPushResponse result = run(input); Test.stopTest();
    Assert.areEqual('RESOLVED', result.state, 'An explicitly selected package resolves normally');
    Assert.areEqual(PACKAGE_ID, fake.selectedPackageId, 'Pass the selected package ID into the authoritative lookup');
    Assert.areEqual(RELEASED_ID, result.targetVersionId, 'Return the target belonging to the selected package');
  }

  @IsTest
  static void shouldRejectLatestWithExplicitVersionId() {
    FakeGateway fake = install();
    HeadlessResolvePushTargetAction.Request input = latestRequest(); input.targetVersionId = BETA_ID;
    Test.startTest(); HeadlessPushResponse result = run(input); Test.stopTest();
    Assert.isFalse(result.isSuccess, 'Latest and a specific version ID conflict');
    Assert.areEqual(0, fake.latestCalls, 'Reject conflicting selectors before lookup');
    Assert.areEqual(0, fake.writeCount, 'No writes');
  }

  @IsTest
  static void shouldReturnOnlyReleasedCandidatesWhenNoVersionSpecified() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest(); List<Map<String,Object>> rows = new HeadlessPushGateway().lookupTargets('Package Visualizer', null); Test.stopTest();
    Assert.isTrue(mock.queries[0].contains('IsReleased=true'), 'No-version selection excludes unreleased builds');
    Assert.areEqual(RELEASED_ID, rows[0].get('SubscriberPackageVersionId'), 'Return the released candidate');
  }

  @IsTest
  static void shouldAllowExplicitVersionDiagnosticsForUnreleasedVersion() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest(); List<Map<String,Object>> rows = new HeadlessPushGateway().lookupTargets('Package Visualizer', '10.0.0.1'); Test.stopTest();
    Assert.isFalse(mock.queries[0].contains('IsReleased=true'), 'An explicit version remains available for readiness diagnostics');
    Assert.areEqual(BETA_ID, rows[0].get('SubscriberPackageVersionId'), 'Return the requested version for a blocked readiness check');
  }

  @IsTest
  static void shouldRejectMissingPackageForLatestBeforeCallout() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    try {new HeadlessPushGateway().lookupLatestReleased(null, null); Assert.fail('The package identity is required');}
    catch (HeadlessPushService.PushException expected) {Assert.isTrue(expected.getMessage().contains('package name or package ID'), 'Explain the missing selector');}
    Test.stopTest(); Assert.areEqual(0, mock.queries.size(), 'Reject before callout');
  }

  @IsTest
  static void shouldRejectLongPackageNameBeforeCallout() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    String longName = ''.leftPad(256,'x');
    Test.startTest();
    try {new HeadlessPushGateway().lookupLatestReleased(longName, null); Assert.fail('Long package names must fail');}
    catch (HeadlessPushService.PushException expected) {Assert.isTrue(expected.getMessage().contains('too long'), 'Explain length limit');}
    Test.stopTest(); Assert.areEqual(0, mock.queries.size(), 'Reject before callout');
  }

  @IsTest
  static void shouldRejectMissingPackageForOrdinaryLookup() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    try {new HeadlessPushGateway().lookupTargets(' ', '9.41'); Assert.fail('A package name is required');}
    catch (HeadlessPushService.PushException expected) {Assert.isTrue(expected.getMessage().contains('package name'), 'Explain missing name');}
    Test.stopTest(); Assert.areEqual(0, mock.queries.size(), 'No query for invalid package');
  }

  @IsTest
  static void shouldRejectLongPackageNameForOrdinaryLookup() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    try {new HeadlessPushGateway().lookupTargets(''.leftPad(256,'x'), '9.41'); Assert.fail('Reject too-long names');}
    catch (HeadlessPushService.PushException expected) {Assert.isTrue(expected.getMessage().contains('package name'), 'Return usable feedback');}
    Test.stopTest(); Assert.areEqual(0, mock.queries.size(), 'Do not send oversized query');
  }

  @IsTest
  static void shouldRejectInvalidNumericVersionForOrdinaryLookup() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    try {new HeadlessPushGateway().lookupTargets('Package Visualizer', '9.41 OR IsReleased=true'); Assert.fail('Reject a nonnumeric version');}
    catch (HeadlessPushService.PushException expected) {Assert.isTrue(expected.getMessage().contains('numeric'), 'Explain numeric version requirements');}
    Test.stopTest(); Assert.areEqual(0, mock.queries.size(), 'No callout for invalid input');
  }

  @IsTest
  static void shouldFilterAllFourVersionComponents() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest(); new HeadlessPushGateway().lookupTargets('Package Visualizer', '9.41.0.1'); Test.stopTest();
    String query = mock.queries[0];
    for (String clause : new List<String>{'MajorVersion=9','MinorVersion=41','PatchVersion=0','BuildNumber=1'}) {
      Assert.isTrue(query.contains(clause), 'The exact version lookup must constrain '+clause);
    }
  }

  @IsTest
  static void shouldRejectInvalidSelectedPackageId() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    try {new HeadlessPushGateway().lookupLatestReleased('Package Visualizer', 'not-an-id'); Assert.fail('Reject an invalid package ID');}
    catch (HeadlessPushService.PushException expected) {Assert.isTrue(expected.getMessage().contains('Invalid package ID'), 'Explain invalid package ID');}
    Test.stopTest(); Assert.areEqual(0, mock.queries.size(), 'No callouts for an invalid ID');
  }

  @IsTest
  static void shouldReturnNoMatchesForMissingPackage() {
    LatestQueryMock mock = new LatestQueryMock(); mock.noPackage = true; Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest(); List<Map<String,Object>> rows = new HeadlessPushGateway().lookupLatestReleased('Package Visualizer', null); Test.stopTest();
    Assert.areEqual(0, rows.size(), 'No matching package is an empty result');
    Assert.areEqual(1, mock.queries.size(), 'Do not search versions without a package');
  }

  @IsTest
  static void shouldValidateSelectedPackageIdAgainstPackageName() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest(); List<Map<String,Object>> rows = new HeadlessPushGateway().lookupLatestReleased('Package Visualizer', PACKAGE_ID); Test.stopTest();
    Assert.areEqual(2, mock.queries.size(), 'Validate the package identity then fetch its latest released version');
    Assert.isTrue(mock.queries[0].contains('Id=\'' + PACKAGE_ID + '\''), 'Constrain by selected package identity');
    Assert.isTrue(mock.queries[0].contains('Name=\'Package Visualizer\''), 'Verify the selected package matches its name');
    Assert.areEqual(RELEASED_ID, rows[0].get('SubscriberPackageVersionId'), 'Return latest for the matching selected package');
  }

  @IsTest
  static void shouldAcceptSelectedPackageIdWithoutName() {
    LatestQueryMock mock = new LatestQueryMock(); Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest(); List<Map<String,Object>> rows = new HeadlessPushGateway().lookupLatestReleased(null, PACKAGE_ID); Test.stopTest();
    Assert.areEqual(2, mock.queries.size(), 'An exact selected ID is sufficient to resolve its version');
    Assert.areEqual(RELEASED_ID, rows[0].get('SubscriberPackageVersionId'), 'Return latest released');
  }

  @IsTest
  static void shouldRejectMalformedPackageIdentityReturnedBySalesforce() {
    LatestQueryMock mock = new LatestQueryMock(); mock.malformedPackage = true; Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    try {new HeadlessPushGateway().lookupLatestReleased('Package Visualizer', null); Assert.fail('Returned package identities must be valid');}
    catch (HeadlessPushService.PushException expected) {Assert.isTrue(expected.getMessage().contains('Invalid package identity'), 'Fail closed on invalid identity');}
    Test.stopTest(); Assert.areEqual(1, mock.queries.size(), 'Do not query versions with invalid identity');
  }

  @IsTest
  static void shouldResolveExplicitIdOnlyWhenAllSuppliedSelectorsAgree() {
    FakeGateway fake=install(); HeadlessResolvePushTargetAction.Request input=new HeadlessResolvePushTargetAction.Request();
    input.targetVersionId=RELEASED_ID;input.packageId=PACKAGE_ID;input.packageName='Package Visualizer';input.versionNumber='9.41.0.1';
    Test.startTest();HeadlessPushResponse result=run(input);Test.stopTest();
    Assert.isTrue(result.isSuccess,'Matching selectors should resolve');
    Assert.areEqual('RESOLVED',result.state,'Matching selector resolution');
    Assert.areEqual(RELEASED_ID,result.targetVersionId,'The exact validated ID is retained');
    Assert.areEqual(1,fake.identityCalls,'Cross-check against authoritative version metadata');
    Assert.areEqual(1,fake.readinessCalls,'Assess readiness after identity check');
  }

  @IsTest
  static void shouldRejectExplicitIdWhenPackageNameDoesNotMatch() {
    FakeGateway fake=install();HeadlessResolvePushTargetAction.Request input=new HeadlessResolvePushTargetAction.Request();
    input.targetVersionId=RELEASED_ID;input.packageName='A Different Package';
    Test.startTest();HeadlessPushResponse result=run(input);Test.stopTest();
    Assert.isFalse(result.isSuccess,'Do not ignore a contradictory package name');
    Assert.areEqual(0,fake.readinessCalls,'Mismatch must fail before readiness or write');
    Assert.areEqual(0,fake.writeCount,'No mutation');
  }

  @IsTest
  static void shouldRejectExplicitIdWhenPackageIdDoesNotMatch() {
    FakeGateway fake=install();HeadlessResolvePushTargetAction.Request input=new HeadlessResolvePushTargetAction.Request();
    input.targetVersionId=RELEASED_ID;input.packageId='0Ho5w000000KyxnCAC';
    Test.startTest();HeadlessPushResponse result=run(input);Test.stopTest();
    Assert.isFalse(result.isSuccess,'Do not ignore a contradictory package ID');
    Assert.areEqual(0,fake.readinessCalls,'Mismatch must fail before readiness or write');
    Assert.areEqual(0,fake.writeCount,'No mutation');
  }

  @IsTest
  static void shouldRejectExplicitIdWhenNumericVersionDoesNotMatch() {
    FakeGateway fake=install();HeadlessResolvePushTargetAction.Request input=new HeadlessResolvePushTargetAction.Request();
    input.targetVersionId=RELEASED_ID;input.versionNumber='9.40.0.1';
    Test.startTest();HeadlessPushResponse result=run(input);Test.stopTest();
    Assert.isFalse(result.isSuccess,'Do not ignore a contradictory numeric version');
    Assert.areEqual(0,fake.readinessCalls,'Mismatch must fail before readiness or write');
    Assert.areEqual(0,fake.writeCount,'No mutation');
  }

  @IsTest
  static void shouldDiagnoseExplicitBetaWhenSuppliedSelectorsMatch() {
    FakeGateway fake=install();fake.identityMajor=10;fake.identityMinor=0;fake.isEligible=false;
    HeadlessResolvePushTargetAction.Request input=new HeadlessResolvePushTargetAction.Request();
    input.targetVersionId=BETA_ID;input.packageName='Package Visualizer';input.versionNumber='10.0.0.1';
    Test.startTest();HeadlessPushResponse result=run(input);Test.stopTest();
    Assert.areEqual('BLOCKED',result.state,'An explicit matching beta remains diagnosable');
    Assert.areEqual(BETA_ID,result.targetVersionId,'Report the exact beta selected by the user');
    Assert.areEqual(1,fake.readinessCalls,'Report actual eligibility after validating identity');
    Assert.areEqual(0,fake.writeCount,'Diagnosis never creates a request');
  }

  @IsTest
  static void shouldReturnBothMatchingLatestVersionTuplesAsAmbiguous() {
    LatestQueryMock mock=new LatestQueryMock();mock.tieReleased=true;Test.setMock(HttpCalloutMock.class,mock);
    Test.startTest();List<Map<String,Object>> rows=new HeadlessPushGateway().lookupLatestReleased('Package Visualizer',null);Test.stopTest();
    Assert.areEqual(2,rows.size(),'Equal latest version tuples must require choosing a version ID');
    Assert.areEqual(2,mock.queries.size(),'One package lookup and one bounded version query');
  }

  @IsTest
  static void shouldChooseHighestWhenSecondReleasedVersionHasLowerTuple() {
    LatestQueryMock mock=new LatestQueryMock();mock.lowerReleased=true;Test.setMock(HttpCalloutMock.class,mock);
    Test.startTest();List<Map<String,Object>> rows=new HeadlessPushGateway().lookupLatestReleased('Package Visualizer',null);Test.stopTest();
    Assert.areEqual(1,rows.size(),'Distinct lower tuple is not ambiguous');
    Assert.areEqual(RELEASED_ID,rows[0].get('SubscriberPackageVersionId'),'Return the numerically highest released version');
  }

  private static Map<String,Object> candidate(String versionId) {
    return new Map<String,Object>{'SubscriberPackageVersionId' => versionId, 'Package2Id' => PACKAGE_ID, 'MajorVersion' => 9, 'MinorVersion' => 41, 'PatchVersion' => 0, 'BuildNumber' => 1, 'IsReleased' => true, 'IsDeprecated' => false};
  }

  private class FakeGateway extends HeadlessPushGateway {
    public List<Map<String,Object>> latestRows = new List<Map<String,Object>>();
    public Boolean isEligible = true;
    public Integer latestCalls = 0, regularCalls = 0, writeCount = 0, readinessCalls = 0, identityCalls = 0;
    public String selectedPackageId;
    public Integer identityMajor = 9, identityMinor = 41;
    public override void authorize() {}
    public override List<Map<String,Object>> lookupLatestReleased(String packageName, String packageId) { latestCalls++; selectedPackageId = packageId; return latestRows; }
    public override List<Map<String,Object>> lookupTargets(String packageName, String versionNumber) { regularCalls++; return new List<Map<String,Object>>{candidate(BETA_ID),candidate(RELEASED_ID)}; }
    public override Map<String,Object> targetIdentity(String versionId) {identityCalls++; return new Map<String,Object>{'Package2Id'=>PACKAGE_ID,'Package2'=>new Map<String,Object>{'Name'=>'Package Visualizer'},'MajorVersion'=>identityMajor,'MinorVersion'=>identityMinor,'PatchVersion'=>0,'BuildNumber'=>1};}
    public override Map<String,Object> readiness(String versionId) { readinessCalls++; return new Map<String,Object>{'eligible' => isEligible, 'blockers' => isEligible ? new List<String>() : new List<String>{'Package code coverage check has not passed.'}}; }
    public override String createRequest(String versionId, Datetime timeValue) {writeCount++; return null;}
    public override String saveFile(String name, String content) {writeCount++; return null;}
    public override String enqueue(String manifestId, String digest, Integer offset) {writeCount++; return null;}
    public override void setStatus(String requestId, String status) {writeCount++;}
  }

  private class LatestQueryMock implements HttpCalloutMock {
    public List<String> queries = new List<String>();
    public Boolean duplicatePackages = false, noReleased = false, noPackage = false, malformedPackage = false, tieReleased = false, lowerReleased = false;
    public HttpResponse respond(HttpRequest request) {
      String query = EncodingUtil.urlDecode(request.getEndpoint(), 'UTF-8'); queries.add(query);
      List<Object> rows = new List<Object>();
      if (query.contains('FROM Package2Version')) {
        if (!noReleased) {rows.add(query.contains('IsReleased=true') ? candidate(RELEASED_ID) : candidate(BETA_ID)); if(tieReleased){rows.add(candidate('04tRh000001barxIAA'));} if(lowerReleased){Map<String,Object> lower=candidate('04tRh000001barxIAA');lower.put('MinorVersion',40);rows.add(lower);}}
      } else if (query.contains('FROM Package2')) {
        if (!noPackage) rows.add(new Map<String,Object>{'Id' => malformedPackage ? 'bad-id' : PACKAGE_ID, 'Name' => 'Package Visualizer'});
        if (duplicatePackages) rows.add(new Map<String,Object>{'Id' => '0Ho5w000000KyxnCAC', 'Name' => 'Package Visualizer'});
      }
      HttpResponse response = new HttpResponse(); response.setStatusCode(200); response.setHeader('Content-Type', 'application/json');
      response.setBody(JSON.serialize(new Map<String,Object>{'totalSize' => rows.size(), 'done' => true, 'records' => rows})); return response;
    }
  }
}
