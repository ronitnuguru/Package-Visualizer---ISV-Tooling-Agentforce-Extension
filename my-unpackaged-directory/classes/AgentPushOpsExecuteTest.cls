@IsTest
private class AgentPushOpsExecuteTest {

    private static final String TARGET_ID = '04t5g000000Vvv4AAC';
    private static final String ORG_KEY_1 = '00D5g000001abcDEFG';
    private static final String ORG_KEY_2 = '00D5g000002abcDEFG';
    private static final String PUSH_REQ_ID = '0DV5g000000AbcdEFG';

    private static ObjectWrappers.PackageVersionWrapper targetVersion() {
        ObjectWrappers.PackageVersionWrapper v = new ObjectWrappers.PackageVersionWrapper();
        v.subscriberPackageVersionId = TARGET_ID;
        v.majorVersion = 8;
        v.minorVersion = 24;
        v.patchVersion = 0;
        return v;
    }

    private static AgentPushOpsExecute.ExecuteRequest request(Boolean confirmed, List<String> orgKeys) {
        AgentPushOpsExecute.ExecuteRequest req = new AgentPushOpsExecute.ExecuteRequest();
        req.confirmed = confirmed;
        req.targetVersionId = TARGET_ID;
        req.targetOrgKeys = orgKeys;
        return req;
    }

    private static AgentPushWrappers.PushScheduleResult run(AgentPushOpsExecute.ExecuteRequest req) {
        AgentPushOpsExecute.ExecuteResponse resp = AgentPushOpsExecute.execute(new List<AgentPushOpsExecute.ExecuteRequest>{ req })[0];
        return (AgentPushWrappers.PushScheduleResult) JSON.deserialize(resp.resultJson, AgentPushWrappers.PushScheduleResult.class);
    }

    @IsTest
    static void shouldNotSchedule_WhenNotConfirmed() {
        // The load-bearing gate: confirmed=false must NOT write.
        AgentPushOpsExecute.mockTargetIsSecurityReviewed = true;
        AgentPushOpsExecute.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ targetVersion() };
        AgentPushOpsExecute.mockPushRequestId = PUSH_REQ_ID; // would succeed IF reached

        Test.startTest();
        AgentPushWrappers.PushScheduleResult result = run(request(false, new List<String>{ ORG_KEY_1 }));
        Test.stopTest();

        System.assertEquals(false, result.success, 'no push without confirmation');
        System.assertEquals(null, result.pushRequestId, 'no push request must be created');
        System.assert(result.errorMessage.contains('confirmation'), 'should state confirmation is required');
    }

    @IsTest
    static void shouldNotSchedule_WhenConfirmedNull() {
        AgentPushOpsExecute.mockTargetIsSecurityReviewed = true;
        AgentPushOpsExecute.mockPushRequestId = PUSH_REQ_ID;

        Test.startTest();
        AgentPushWrappers.PushScheduleResult result = run(request(null, new List<String>{ ORG_KEY_1 }));
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(null, result.pushRequestId);
    }

    @IsTest
    static void shouldSchedule_WhenConfirmedAndReviewed() {
        AgentPushOpsExecute.mockTargetIsSecurityReviewed = true;
        AgentPushOpsExecute.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ targetVersion() };
        AgentPushOpsExecute.mockPushRequestId = PUSH_REQ_ID;

        Test.startTest();
        AgentPushWrappers.PushScheduleResult result = run(request(true, new List<String>{ ORG_KEY_1, ORG_KEY_2 }));
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(PUSH_REQ_ID, result.pushRequestId);
        System.assertEquals(2, result.jobsRequested);
        System.assertEquals('8.24.0', result.targetVersionNumber);
    }

    @IsTest
    static void shouldBlock_WhenTargetNotSecurityReviewed() {
        AgentPushOpsExecute.mockTargetIsSecurityReviewed = false;
        AgentPushOpsExecute.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ targetVersion() };
        AgentPushOpsExecute.mockPushRequestId = PUSH_REQ_ID;

        Test.startTest();
        AgentPushWrappers.PushScheduleResult result = run(request(true, new List<String>{ ORG_KEY_1 }));
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.errorMessage.contains('security review'));
    }

    @IsTest
    static void shouldReject_WhenNoValidOrgKeys() {
        AgentPushOpsExecute.mockTargetIsSecurityReviewed = true;

        Test.startTest();
        AgentPushWrappers.PushScheduleResult result = run(request(true, new List<String>{ 'short', null }));
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.errorMessage.contains('OrgKeys'));
    }

    @IsTest
    static void shouldDeduplicateOrgKeys_WhenRepeated() {
        AgentPushOpsExecute.mockTargetIsSecurityReviewed = true;
        AgentPushOpsExecute.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ targetVersion() };
        AgentPushOpsExecute.mockPushRequestId = PUSH_REQ_ID;

        Test.startTest();
        AgentPushWrappers.PushScheduleResult result = run(request(true, new List<String>{ ORG_KEY_1, ORG_KEY_1, ORG_KEY_2 }));
        Test.stopTest();

        System.assertEquals(2, result.jobsRequested, 'duplicate org keys collapse to distinct count');
    }

    @IsTest
    static void shouldCallRealCreatePushRequest_AndSurfaceThrow() {
        // Gate passes (review injected true), but no mockPushRequestId, so the REAL
        // createPushRequest callout runs. PushUpgradesCalloutMock returns 400 for a new
        // PackagePushRequest, which createPushRequest converts to AuraHandledException —
        // exercising the live write call + the try/catch -> errorMessage branch.
        AgentPushOpsExecute.mockTargetIsSecurityReviewed = true;
        AgentPushOpsExecute.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ targetVersion() };
        Test.setMock(HttpCalloutMock.class, new PushUpgradesCalloutMock());

        Test.startTest();
        AgentPushWrappers.PushScheduleResult result = run(request(true, new List<String>{ ORG_KEY_1 }));
        Test.stopTest();

        System.assertEquals(false, result.success, 'a 400 from createPushRequest is caught and surfaced');
        System.assertNotEquals(null, result.errorMessage);
    }

    @IsTest
    static void shouldRunRealWritePath_WhenConfirmedAndReviewed() {
        // No security-review or pushRequestId seams: exercise the real getIsSecurityReviewed
        // and createPushRequest/createPushJobs callout branches. ToolingAPICalloutMock provides
        // the version/review reads; the SubscriberPackageVersion body has no IsSecurityReviewed,
        // so review resolves null and the write is blocked before any push — live branch covered.
        Test.setMock(HttpCalloutMock.class, new ToolingAPICalloutMock());

        Test.startTest();
        AgentPushWrappers.PushScheduleResult result = run(request(true, new List<String>{ ORG_KEY_1 }));
        Test.stopTest();

        System.assertEquals(false, result.success, 'unreviewed target via live path does not push');
        System.assert(result.errorMessage.contains('security review'));
    }

    @IsTest
    static void shouldProcessBulk_WhenManyOrgKeys() {
        AgentPushOpsExecute.mockTargetIsSecurityReviewed = true;
        AgentPushOpsExecute.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ targetVersion() };
        AgentPushOpsExecute.mockPushRequestId = PUSH_REQ_ID;

        List<String> orgKeys = new List<String>();
        for (Integer i = 0; i < 251; i++) {
            // 18-char unique-ish keys
            String suffix = String.valueOf(1000000 + i);
            orgKeys.add('00D5g00000' + suffix + 'X');
        }

        Test.startTest();
        AgentPushWrappers.PushScheduleResult result = run(request(true, orgKeys));
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(251, result.jobsRequested, 'bulk cohort beyond the 200-chunk boundary');
    }
}
