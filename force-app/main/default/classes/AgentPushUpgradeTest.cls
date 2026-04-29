@IsTest
private class AgentPushUpgradeTest {

    private static final String ORG_KEY           = '00D5g000001abcDE';
    private static final String PKG_ID            = '0335g000000AaaaAAA';
    private static final String INSTALLED_VER_ID  = '04t5g000000Vvv1AAC';
    private static final String LATEST_VER_ID     = '04t5g000000Vvv4AAC';

    private class Mock implements HttpCalloutMock {
        Map<String, HttpResponse> byContains = new Map<String, HttpResponse>();

        Mock when(String fragment, Integer status, String body) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            byContains.put(fragment, res);
            return this;
        }

        public HttpResponse respond(HttpRequest req) {
            String endpoint = req.getEndpoint();
            for (String fragment : byContains.keySet()) {
                if (endpoint.contains(fragment)) return byContains.get(fragment);
            }
            HttpResponse empty = new HttpResponse();
            empty.setStatusCode(200);
            empty.setHeader('Content-Type', 'application/json');
            empty.setBody('{"records":[]}');
            return empty;
        }
    }

    private static String subscriberRow(String versionId) {
        return '{"records":[{'
            + '"Id":"1235g000000AaaaAAA",'
            + '"OrgKey":"' + ORG_KEY + '",'
            + '"OrgName":"Acme Corp",'
            + '"OrgType":"Production",'
            + '"OrgStatus":"Active",'
            + '"InstanceName":"NA45",'
            + '"ParentOrg":null,'
            + '"MetadataPackageId":"' + PKG_ID + '",'
            + '"MetadataPackageVersionId":"' + versionId + '",'
            + '"SystemModstamp":"2026-02-20T14:03:00.000+0000"'
            + '}]}';
    }

    private static String versionRow(String id, Integer major, Integer minor, Integer patch) {
        return '{"records":[{'
            + '"Id":"05i5g000000AbcdAAC",'
            + '"SubscriberPackageVersionId":"' + id + '",'
            + '"Package2Id":"' + PKG_ID + '",'
            + '"MajorVersion":' + major + ',"MinorVersion":' + minor + ',"PatchVersion":' + patch + ',"BuildNumber":1,'
            + '"IsReleased":true,"CreatedDate":"2026-04-20T00:00:00.000+0000"'
            + '}]}';
    }

    private static String latestIds(String firstId) {
        return '{"records":[{'
            + '"SubscriberPackageVersionId":"' + firstId + '",'
            + '"MajorVersion":8,"MinorVersion":24,"PatchVersion":0,"BuildNumber":1'
            + '}]}';
    }

    private static AgentSubscriberWrappers.PushResult parse(AgentPushUpgrade.PushResponse resp) {
        return (AgentSubscriberWrappers.PushResult) JSON.deserialize(
            resp.resultJson, AgentSubscriberWrappers.PushResult.class
        );
    }

    @IsTest
    static void testInvalidOrgKey() {
        AgentPushUpgrade.PushRequest req = new AgentPushUpgrade.PushRequest();
        req.orgKey = 'abc';

        List<AgentPushUpgrade.PushResponse> responses =
            AgentPushUpgrade.push(new List<AgentPushUpgrade.PushRequest>{req});

        AgentSubscriberWrappers.PushResult r = parse(responses[0]);
        System.assertEquals(false, r.success);
        System.assert(r.errorMessage.contains('15 or 18'));
    }

    @IsTest
    static void testSubscriberNotFound() {
        Mock m = new Mock().when('PackageSubscriber', 200, '{"records":[]}');
        Test.setMock(HttpCalloutMock.class, m);

        AgentPushUpgrade.PushRequest req = new AgentPushUpgrade.PushRequest();
        req.orgKey = ORG_KEY;

        Test.startTest();
        List<AgentPushUpgrade.PushResponse> responses =
            AgentPushUpgrade.push(new List<AgentPushUpgrade.PushRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.PushResult r = parse(responses[0]);
        System.assertEquals(false, r.success);
        System.assert(r.errorMessage.contains('No subscriber found'));
    }

    @IsTest
    static void testAlreadyOnLatest() {
        Mock m = new Mock()
            .when('PackageSubscriber+WHERE+OrgKey', 200, subscriberRow(LATEST_VER_ID))
            .when('SubscriberPackageVersionId+%3D+%27' + LATEST_VER_ID + '%27', 200, versionRow(LATEST_VER_ID, 8, 24, 0))
            .when('Package2Id+%3D+%27' + PKG_ID + '%27', 200, latestIds(LATEST_VER_ID));
        Test.setMock(HttpCalloutMock.class, m);

        AgentPushUpgrade.PushRequest req = new AgentPushUpgrade.PushRequest();
        req.orgKey = ORG_KEY;

        Test.startTest();
        List<AgentPushUpgrade.PushResponse> responses =
            AgentPushUpgrade.push(new List<AgentPushUpgrade.PushRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.PushResult r = parse(responses[0]);
        System.assertEquals(false, r.success);
        System.assert(r.errorMessage.contains('Already on the latest'));
        System.assertEquals('8.24.0', r.fromVersion);
    }

    @IsTest
    static void testSecurityReviewError() {
        Mock m = new Mock()
            .when('PackageSubscriber+WHERE+OrgKey', 200, subscriberRow(INSTALLED_VER_ID))
            .when('SubscriberPackageVersionId+%3D+%27' + INSTALLED_VER_ID + '%27', 200, versionRow(INSTALLED_VER_ID, 8, 21, 0))
            .when('SubscriberPackageVersionId+%3D+%27' + LATEST_VER_ID + '%27', 200, versionRow(LATEST_VER_ID, 8, 24, 0))
            .when('Package2Id+%3D+%27' + PKG_ID + '%27', 200, latestIds(LATEST_VER_ID))
            .when('sobjects/PackagePushRequest', 400, '{Specify a package that has passed the AppExchange security review.}');
        Test.setMock(HttpCalloutMock.class, m);

        AgentPushUpgrade.PushRequest req = new AgentPushUpgrade.PushRequest();
        req.orgKey = ORG_KEY;

        Test.startTest();
        List<AgentPushUpgrade.PushResponse> responses =
            AgentPushUpgrade.push(new List<AgentPushUpgrade.PushRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.PushResult r = parse(responses[0]);
        System.assertEquals(false, r.success);
        System.assertNotEquals(null, r.errorMessage);
    }

    @IsTest
    static void testNullRequest() {
        List<AgentPushUpgrade.PushResponse> responses =
            AgentPushUpgrade.push(new List<AgentPushUpgrade.PushRequest>{null});
        AgentSubscriberWrappers.PushResult r = parse(responses[0]);
        System.assertEquals(false, r.success);
        System.assertNotEquals(null, r.errorMessage);
    }
}
