@IsTest
private class AgentPushOpsPlanTest {

    private static final String TARGET_ID = '04t5g000000Vvv4AAC';
    private static final String OLD_ID    = '04t5g000000Vvv1AAC';

    private static ObjectWrappers.PackageVersionWrapper targetVersion() {
        ObjectWrappers.PackageVersionWrapper v = new ObjectWrappers.PackageVersionWrapper();
        v.subscriberPackageVersionId = TARGET_ID;
        v.package2Id = '0Ho5g000000AaaaAAA';
        v.majorVersion = 8;
        v.minorVersion = 24;
        v.patchVersion = 0;
        v.isReleased = true;
        return v;
    }

    private static ObjectWrappers.PackageSubscriberWrapper subscriber(String orgKey, String installedId) {
        ObjectWrappers.PackageSubscriberWrapper s = new ObjectWrappers.PackageSubscriberWrapper();
        s.orgKey = orgKey;
        s.metadataPackageVersionId = installedId;
        return s;
    }

    private static AgentPushWrappers.PushPlan invoke(List<String> orgKeys) {
        AgentPushOpsPlan.PlanRequest req = new AgentPushOpsPlan.PlanRequest();
        req.targetVersionId = TARGET_ID;
        req.orgKeys = orgKeys;
        AgentPushOpsPlan.PlanResponse resp = AgentPushOpsPlan.plan(new List<AgentPushOpsPlan.PlanRequest>{ req })[0];
        return (AgentPushWrappers.PushPlan) JSON.deserialize(resp.resultJson, AgentPushWrappers.PushPlan.class);
    }

    @IsTest
    static void shouldBuildPlan_WhenReviewedWithEligibleCohort() {
        AgentPushOpsPlan.mockTargetIsSecurityReviewed = true;
        AgentPushOpsPlan.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ targetVersion() };
        AgentPushOpsPlan.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber('00D5g000001abcDEFG', OLD_ID),
            subscriber('00D5g000002abcDEFG', OLD_ID),
            subscriber('00D5g000003abcDEFG', TARGET_ID) // already current
        };

        Test.startTest();
        AgentPushWrappers.PushPlan plan = invoke(new List<String>{ '00D5g000001abcDEFG', '00D5g000002abcDEFG', '00D5g000003abcDEFG' });
        Test.stopTest();

        System.assertEquals(2, plan.eligibleCount, 'two orgs are behind the target');
        System.assertEquals(1, plan.alreadyCurrentCount);
        System.assertEquals(1, plan.estimatedChunks);
        System.assertEquals(false, plan.blocked);
        System.assertEquals('8.24.0', plan.targetVersionNumber);
    }

    @IsTest
    static void shouldBlock_WhenTargetNotSecurityReviewed() {
        AgentPushOpsPlan.mockTargetIsSecurityReviewed = false;
        AgentPushOpsPlan.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ targetVersion() };

        Test.startTest();
        AgentPushWrappers.PushPlan plan = invoke(new List<String>{ '00D5g000001abcDEFG' });
        Test.stopTest();

        System.assertEquals(true, plan.blocked);
        System.assert(plan.errorMessage.contains('security review'), 'should explain the security-review gate');
    }

    @IsTest
    static void shouldReportNoneEligible_WhenAllCurrent() {
        AgentPushOpsPlan.mockTargetIsSecurityReviewed = true;
        AgentPushOpsPlan.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ targetVersion() };
        AgentPushOpsPlan.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber('00D5g000001abcDEFG', TARGET_ID)
        };

        Test.startTest();
        AgentPushWrappers.PushPlan plan = invoke(new List<String>{ '00D5g000001abcDEFG' });
        Test.stopTest();

        System.assertEquals(0, plan.eligibleCount);
        System.assertEquals(true, plan.blocked);
        System.assertEquals(1, plan.alreadyCurrentCount);
    }

    @IsTest
    static void shouldReturnError_WhenTargetIdInvalid() {
        AgentPushOpsPlan.PlanRequest req = new AgentPushOpsPlan.PlanRequest();
        req.targetVersionId = 'bad-id';

        Test.startTest();
        AgentPushOpsPlan.PlanResponse resp = AgentPushOpsPlan.plan(new List<AgentPushOpsPlan.PlanRequest>{ req })[0];
        Test.stopTest();

        AgentPushWrappers.PushPlan plan = (AgentPushWrappers.PushPlan) JSON.deserialize(resp.resultJson, AgentPushWrappers.PushPlan.class);
        System.assert(plan.errorMessage.contains('04t'));
    }

    @IsTest
    static void shouldRunRealQueryPath_WhenNoMocksInjected() {
        // No @TestVisible seams: exercise the real findVersion + getIsSecurityReviewed +
        // resolveSubscribers callout/SOQL branches. ToolingAPICalloutMock's
        // SubscriberPackageVersion body has no IsSecurityReviewed, so review resolves null
        // and the plan is blocked — but the live branches execute for coverage.
        Test.setMock(HttpCalloutMock.class, new ToolingAPICalloutMock());

        AgentPushOpsPlan.PlanRequest req = new AgentPushOpsPlan.PlanRequest();
        req.targetVersionId = TARGET_ID;

        Test.startTest();
        AgentPushOpsPlan.PlanResponse resp = AgentPushOpsPlan.plan(new List<AgentPushOpsPlan.PlanRequest>{ req })[0];
        Test.stopTest();

        AgentPushWrappers.PushPlan plan = (AgentPushWrappers.PushPlan) JSON.deserialize(resp.resultJson, AgentPushWrappers.PushPlan.class);
        System.assertEquals(true, plan.blocked, 'unreviewed target via live path is blocked');
    }

    @IsTest
    static void shouldProcessBulk_WhenManyRequests() {
        AgentPushOpsPlan.mockTargetIsSecurityReviewed = true;
        AgentPushOpsPlan.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ targetVersion() };
        AgentPushOpsPlan.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber('00D5g000001abcDEFG', OLD_ID)
        };

        List<AgentPushOpsPlan.PlanRequest> requests = new List<AgentPushOpsPlan.PlanRequest>();
        for (Integer i = 0; i < 200; i++) {
            AgentPushOpsPlan.PlanRequest req = new AgentPushOpsPlan.PlanRequest();
            req.targetVersionId = TARGET_ID;
            requests.add(req);
        }

        Test.startTest();
        List<AgentPushOpsPlan.PlanResponse> responses = AgentPushOpsPlan.plan(requests);
        Test.stopTest();

        System.assertEquals(200, responses.size());
    }
}
