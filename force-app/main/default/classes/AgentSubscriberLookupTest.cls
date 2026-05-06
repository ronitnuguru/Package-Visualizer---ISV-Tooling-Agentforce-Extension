@IsTest
private class AgentSubscriberLookupTest {

    private static final String SAMPLE_ORG_KEY       = '00D5g000001abcDEFG';
    private static final String SAMPLE_PKG_ID        = '0335g000000AaaaAAA';
    private static final String INSTALLED_VERSION_ID = '04t5g000000Vvv1AAC';
    private static final String LATEST_VERSION_ID    = '04t5g000000Vvv4AAC';

    // Mock only for the Salesforce Trust instance-status callout. PackageSubscriber / Package2Version
    // lookups are injected through AgentSubscriberLookup's @TestVisible static fields because the
    // production code uses Database.query / Package2Interface, not HttpCalloutMock-covered callouts,
    // for those SOQL paths.
    private class TrustMock implements HttpCalloutMock {
        Integer status;
        String body;
        TrustMock(Integer s, String b) { this.status = s; this.body = b; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            return res;
        }
    }

    private static ObjectWrappers.PackageSubscriberWrapper subscriber(String orgKey, String orgName, String orgType, String orgStatus, String instance, String parent, String versionId) {
        ObjectWrappers.PackageSubscriberWrapper s = new ObjectWrappers.PackageSubscriberWrapper();
        s.id                       = '1235g000000AaaaAAA';
        s.orgKey                   = orgKey;
        s.orgName                  = orgName;
        s.orgType                  = orgType;
        s.orgStatus                = orgStatus;
        s.instanceName             = instance;
        s.parentOrg                = parent;
        s.metadataPackageId        = SAMPLE_PKG_ID;
        s.metadataPackageVersionId = versionId;
        s.SystemModstamp           = Datetime.newInstanceGmt(2026, 2, 20, 14, 3, 0);
        return s;
    }

    private static ObjectWrappers.PackageVersionWrapper version(String id, Integer major, Integer minor, Integer patch) {
        ObjectWrappers.PackageVersionWrapper v = new ObjectWrappers.PackageVersionWrapper();
        v.subscriberPackageVersionId = id;
        v.package2Id = SAMPLE_PKG_ID;
        v.majorVersion = major;
        v.minorVersion = minor;
        v.patchVersion = patch;
        v.buildNumber  = 1;
        v.isReleased   = true;
        return v;
    }

    // Deserialize the invocable's resultJson output back into a typed LookupResult
    // for assertions. The invocable now only exposes resultJson as an @InvocableVariable
    // to keep the agentscript compiler's action-schema introspection simple.
    private static AgentSubscriberWrappers.LookupResult parse(AgentSubscriberLookup.LookupResponse resp) {
        return (AgentSubscriberWrappers.LookupResult) JSON.deserialize(
            resp.resultJson, AgentSubscriberWrappers.LookupResult.class
        );
    }

    @IsTest
    static void testExactMatchCurrent() {
        AgentSubscriberLookup.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber(SAMPLE_ORG_KEY, 'Acme Corp', 'Production', 'Active', 'NA45', null, LATEST_VERSION_ID)
        };
        AgentSubscriberLookup.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{
            version(LATEST_VERSION_ID, 8, 24, 0)
        };
        AgentSubscriberLookup.mockLatestVersionIds = new List<String>{ LATEST_VERSION_ID };
        AgentSubscriberLookup.httpMock = new TrustMock(200, '{"status":"OK"}');

        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = SAMPLE_ORG_KEY;

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        System.assertEquals(1, responses.size());
        AgentSubscriberWrappers.LookupResult r = parse(responses[0]);
        System.assertNotEquals(null, r.subscriber, 'Expected exact-match subscriber');
        System.assertEquals(0, r.subscriber.versionsBehind);
        System.assertEquals('current', r.subscriber.versionHealthTag);
        System.assertEquals('Operational', r.subscriber.instanceStatus);
        System.assert(responses[0].resultJson.contains('"versionHealthTag":"current"'));
    }

    @IsTest
    static void testExactMatchThreeBehind() {
        AgentSubscriberLookup.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber(SAMPLE_ORG_KEY, 'Acme Corp', 'Production', 'Active', 'NA45', null, INSTALLED_VERSION_ID)
        };
        AgentSubscriberLookup.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{
            version(INSTALLED_VERSION_ID, 8, 22, 1),
            version(LATEST_VERSION_ID,    8, 24, 0)
        };
        // Three versions newer than installed — count distance.
        AgentSubscriberLookup.mockLatestVersionIds = new List<String>{
            LATEST_VERSION_ID,
            '04t5g000000Vv01AAC',
            '04t5g000000Vv02AAC',
            INSTALLED_VERSION_ID
        };
        AgentSubscriberLookup.httpMock = new TrustMock(200, '{"status":"OK"}');

        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = SAMPLE_ORG_KEY;

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.SubscriberSummary s = parse(responses[0]).subscriber;
        System.assertNotEquals(null, s);
        System.assertEquals(3, s.versionsBehind);
        System.assertEquals('major-behind', s.versionHealthTag);
        System.assertEquals('8.22.1', s.installedVersion);
        System.assertEquals('8.24.0', s.latestVersion);
    }

    @IsTest
    static void testExactMatchSandbox() {
        AgentSubscriberLookup.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber(SAMPLE_ORG_KEY, 'Acme Sandbox', 'Sandbox', 'Active', 'NA45', '00D5g000001parentA', INSTALLED_VERSION_ID)
        };
        AgentSubscriberLookup.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{
            version(INSTALLED_VERSION_ID, 8, 22, 1),
            version(LATEST_VERSION_ID,    8, 24, 0)
        };
        AgentSubscriberLookup.mockLatestVersionIds = new List<String>{
            LATEST_VERSION_ID,
            '04t5g000000Vv01AAC',
            '04t5g000000Vv02AAC',
            INSTALLED_VERSION_ID
        };
        AgentSubscriberLookup.httpMock = new TrustMock(200, '{"status":"OK"}');

        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = SAMPLE_ORG_KEY;

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        System.assertEquals('00D5g000001parentA', parse(responses[0]).subscriber.parentOrgKey);
    }

    @IsTest
    static void testExactMatchTrustDown() {
        AgentSubscriberLookup.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber(SAMPLE_ORG_KEY, 'Acme Corp', 'Production', 'Active', 'NA45', null, INSTALLED_VERSION_ID)
        };
        AgentSubscriberLookup.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{
            version(INSTALLED_VERSION_ID, 8, 22, 1),
            version(LATEST_VERSION_ID,    8, 24, 0)
        };
        AgentSubscriberLookup.mockLatestVersionIds = new List<String>{ LATEST_VERSION_ID };
        // Trust returns 500 → instanceStatus should fall back to 'Unknown'.
        AgentSubscriberLookup.httpMock = new TrustMock(500, 'Internal Server Error');

        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = SAMPLE_ORG_KEY;

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.SubscriberSummary s = parse(responses[0]).subscriber;
        System.assertNotEquals(null, s);
        System.assertEquals('Unknown', s.instanceStatus);
        System.assertEquals('8.22.1', s.installedVersion, 'Other fields should still populate');
    }

    @IsTest
    static void testPrefixSearchFiveMatches() {
        List<ObjectWrappers.PackageSubscriberWrapper> rows = new List<ObjectWrappers.PackageSubscriberWrapper>();
        for (Integer i = 0; i < 5; i++) {
            rows.add(subscriber('00D5g00000abc' + i + 'XYZ', 'Match ' + i, 'Production', 'Active', 'NA45', null, INSTALLED_VERSION_ID));
        }
        AgentSubscriberLookup.mockSubscribers = rows;
        AgentSubscriberLookup.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{
            version(INSTALLED_VERSION_ID, 8, 22, 1),
            version(LATEST_VERSION_ID,    8, 24, 0)
        };
        AgentSubscriberLookup.mockLatestVersionIds = new List<String>{
            LATEST_VERSION_ID,
            '04t5g000000Vv01AAC',
            '04t5g000000Vv02AAC',
            INSTALLED_VERSION_ID
        };

        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = '00D5g0';

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.LookupResult r = parse(responses[0]);
        System.assertEquals(null, r.subscriber);
        System.assertEquals(5, r.disambiguation.size());
        System.assertEquals('8.22.1', r.disambiguation[0].installedVersion);
    }

    @IsTest
    static void testPrefixSearchZeroMatches() {
        AgentSubscriberLookup.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>();

        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = 'zzzzzz';

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.LookupResult r = parse(responses[0]);
        System.assertEquals(null, r.disambiguation);
        System.assert(r.errorMessage.contains('starting with "zzzzzz"'));
    }

    @IsTest
    static void testMalformedOrgKeyShort() {
        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = 'abc';

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        System.assert(parse(responses[0]).errorMessage.contains('15 or 18'));
    }

    @IsTest
    static void testMalformedOrgKeySymbols() {
        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = '00D5!@#$%^&*';

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.LookupResult r = parse(responses[0]);
        System.assertNotEquals(null, r.errorMessage);
        System.assertEquals(null, r.subscriber);
        System.assertEquals(null, r.disambiguation);
    }

    @IsTest
    static void testEmptyOrgKey() {
        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = '   ';

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        System.assert(parse(responses[0]).errorMessage.contains('I need an OrgKey'));
    }

    @IsTest
    static void testUnknownOrgKey() {
        AgentSubscriberLookup.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>();

        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = '00D999999999999999';

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.LookupResult r = parse(responses[0]);
        System.assertEquals(null, r.subscriber);
        System.assert(r.errorMessage.contains('No subscriber found'));
    }

    @IsTest
    static void testNullRequest() {
        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{null});
        Test.stopTest();

        System.assert(parse(responses[0]).errorMessage.contains('I need an OrgKey'));
    }

    @IsTest
    static void testJsonPayloadShape() {
        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = '';

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        String json = responses[0].resultJson;
        System.assert(json.startsWith('{'));
        System.assert(json.contains('"errorMessage"'));
    }
}
