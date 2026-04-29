@IsTest
private class AgentSubscriberLookupTest {

    private static final String SAMPLE_ORG_KEY       = '00D5g000001abcDE';
    private static final String SAMPLE_PKG_ID        = '0335g000000AaaaAAA';
    private static final String INSTALLED_VERSION_ID = '04t5g000000Vvv1AAC';
    private static final String LATEST_VERSION_ID    = '04t5g000000Vvv4AAC';

    private class Mock implements HttpCalloutMock {
        Map<String, HttpResponse> byContains = new Map<String, HttpResponse>();
        HttpResponse defaultResponse;

        Mock when(String containsFragment, Integer status, String body) {
            byContains.put(containsFragment, buildResponse(status, body));
            return this;
        }

        Mock defaultTo(Integer status, String body) {
            defaultResponse = buildResponse(status, body);
            return this;
        }

        private HttpResponse buildResponse(Integer status, String body) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            return res;
        }

        public HttpResponse respond(HttpRequest req) {
            String endpoint = req.getEndpoint();
            for (String fragment : byContains.keySet()) {
                if (endpoint.contains(fragment)) return byContains.get(fragment);
            }
            if (defaultResponse != null) return defaultResponse;
            HttpResponse empty = new HttpResponse();
            empty.setStatusCode(200);
            empty.setBody('{"records":[]}');
            return empty;
        }
    }

    private static String subscriberRow(String orgKey, String orgName, String orgType, String orgStatus, String instance, String parent, String versionId) {
        return '{'
            + '"Id":"1235g000000AaaaAAA",'
            + '"OrgKey":"' + orgKey + '",'
            + '"OrgName":"' + orgName + '",'
            + '"OrgType":"' + orgType + '",'
            + '"OrgStatus":"' + orgStatus + '",'
            + '"InstanceName":"' + instance + '",'
            + '"ParentOrg":' + (parent == null ? 'null' : '"' + parent + '"') + ','
            + '"MetadataPackageId":"' + SAMPLE_PKG_ID + '",'
            + '"MetadataPackageVersionId":"' + versionId + '",'
            + '"SystemModstamp":"2026-02-20T14:03:00.000+0000"'
            + '}';
    }

    private static String installedVersionRow() {
        return '{"records":[{'
            + '"Id":"05i5g000000AbcdAAC",'
            + '"SubscriberPackageVersionId":"' + INSTALLED_VERSION_ID + '",'
            + '"Package2Id":"' + SAMPLE_PKG_ID + '",'
            + '"MajorVersion":8,"MinorVersion":22,"PatchVersion":1,"BuildNumber":1,'
            + '"IsReleased":true,"CreatedDate":"2026-02-14T00:00:00.000+0000"'
            + '}]}';
    }

    private static String latestVersionsRows(Integer versionsBetween) {
        List<String> rows = new List<String>();
        rows.add('{'
            + '"SubscriberPackageVersionId":"' + LATEST_VERSION_ID + '",'
            + '"MajorVersion":8,"MinorVersion":24,"PatchVersion":0,"BuildNumber":1,'
            + '"CreatedDate":"2026-04-20T00:00:00.000+0000"'
            + '}');
        for (Integer i = 1; i < versionsBetween; i++) {
            rows.add('{'
                + '"SubscriberPackageVersionId":"04t5g000000Vv' + i + 'AAC",'
                + '"MajorVersion":8,"MinorVersion":' + (24 - i) + ',"PatchVersion":0,"BuildNumber":1,'
                + '"CreatedDate":"2026-0' + (4 - i) + '-01T00:00:00.000+0000"'
                + '}');
        }
        rows.add('{'
            + '"SubscriberPackageVersionId":"' + INSTALLED_VERSION_ID + '",'
            + '"MajorVersion":8,"MinorVersion":22,"PatchVersion":1,"BuildNumber":1,'
            + '"CreatedDate":"2026-02-14T00:00:00.000+0000"'
            + '}');
        return '{"records":[' + String.join(rows, ',') + ']}';
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
        Mock m = new Mock()
            .when('PackageSubscriber+WHERE+OrgKey', 200,
                '{"records":[' + subscriberRow(SAMPLE_ORG_KEY, 'Acme Corp', 'Production', 'Active', 'NA45', null, LATEST_VERSION_ID) + ']}')
            .when('SubscriberPackageVersionId+%3D+%27' + LATEST_VERSION_ID + '%27', 200,
                '{"records":[{'
                    + '"SubscriberPackageVersionId":"' + LATEST_VERSION_ID + '",'
                    + '"Package2Id":"' + SAMPLE_PKG_ID + '",'
                    + '"MajorVersion":8,"MinorVersion":24,"PatchVersion":0,"BuildNumber":1,'
                    + '"IsReleased":true,"CreatedDate":"2026-04-20T00:00:00.000+0000"'
                    + '}]}')
            .when('Package2Id+%3D+%27' + SAMPLE_PKG_ID + '%27', 200, latestVersionsRows(1))
            .when('/v1/instances/NA45', 200, '{"status":"OK"}');
        AgentSubscriberLookup.httpMock = m;

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
        Mock m = new Mock()
            .when('PackageSubscriber+WHERE+OrgKey', 200,
                '{"records":[' + subscriberRow(SAMPLE_ORG_KEY, 'Acme Corp', 'Production', 'Active', 'NA45', null, INSTALLED_VERSION_ID) + ']}')
            .when('SubscriberPackageVersionId+%3D+%27' + INSTALLED_VERSION_ID + '%27', 200, installedVersionRow())
            .when('Package2Id+%3D+%27' + SAMPLE_PKG_ID + '%27', 200, latestVersionsRows(3))
            .when('/v1/instances/NA45', 200, '{"status":"OK"}');
        AgentSubscriberLookup.httpMock = m;

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
        Mock m = new Mock()
            .when('PackageSubscriber+WHERE+OrgKey', 200,
                '{"records":[' + subscriberRow(SAMPLE_ORG_KEY, 'Acme Sandbox', 'Sandbox', 'Active', 'NA45', '00D5g000001parentA', INSTALLED_VERSION_ID) + ']}')
            .when('SubscriberPackageVersionId+%3D+%27' + INSTALLED_VERSION_ID + '%27', 200, installedVersionRow())
            .when('Package2Id+%3D+%27' + SAMPLE_PKG_ID + '%27', 200, latestVersionsRows(3))
            .when('/v1/instances/NA45', 200, '{"status":"OK"}');
        AgentSubscriberLookup.httpMock = m;

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
        Mock m = new Mock()
            .when('PackageSubscriber+WHERE+OrgKey', 200,
                '{"records":[' + subscriberRow(SAMPLE_ORG_KEY, 'Acme Corp', 'Production', 'Active', 'NA45', null, INSTALLED_VERSION_ID) + ']}')
            .when('SubscriberPackageVersionId+%3D+%27' + INSTALLED_VERSION_ID + '%27', 200, installedVersionRow())
            .when('Package2Id+%3D+%27' + SAMPLE_PKG_ID + '%27', 200, latestVersionsRows(1))
            .when('/v1/instances/NA45', 500, 'Internal Server Error');
        AgentSubscriberLookup.httpMock = m;

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
        List<String> rows = new List<String>();
        for (Integer i = 0; i < 5; i++) {
            rows.add('{'
                + '"OrgKey":"00D5g00000abc' + i + 'XYZ",'
                + '"OrgName":"Match ' + i + '",'
                + '"OrgType":"Production",'
                + '"MetadataPackageId":"' + SAMPLE_PKG_ID + '",'
                + '"MetadataPackageVersionId":"' + INSTALLED_VERSION_ID + '"'
                + '}');
        }
        Mock m = new Mock()
            .when('PackageSubscriber+WHERE+OrgKey+LIKE', 200, '{"records":[' + String.join(rows, ',') + ']}')
            .when('SubscriberPackageVersionId+%3D+%27' + INSTALLED_VERSION_ID + '%27', 200, installedVersionRow())
            .when('Package2Id+%3D+%27' + SAMPLE_PKG_ID + '%27', 200, latestVersionsRows(3));
        AgentSubscriberLookup.httpMock = m;

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
        Mock m = new Mock()
            .when('PackageSubscriber+WHERE+OrgKey+LIKE', 200, '{"records":[]}');
        AgentSubscriberLookup.httpMock = m;

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
        Mock m = new Mock()
            .when('PackageSubscriber+WHERE+OrgKey+%3D', 200, '{"records":[]}');
        AgentSubscriberLookup.httpMock = m;

        AgentSubscriberLookup.LookupRequest req = new AgentSubscriberLookup.LookupRequest();
        req.orgKey = '00D9999999999999';

        Test.startTest();
        List<AgentSubscriberLookup.LookupResponse> responses =
            AgentSubscriberLookup.lookup(new List<AgentSubscriberLookup.LookupRequest>{req});
        Test.stopTest();

        System.assertEquals(null, responses[0].result.subscriber);
        System.assert(responses[0].result.errorMessage.contains('No subscriber found'));
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
