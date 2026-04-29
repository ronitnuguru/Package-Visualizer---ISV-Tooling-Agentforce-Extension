@IsTest
private class AgentSubscriberSearchByNameTest {

    private class Mock implements HttpCalloutMock {
        String body;
        Integer status;
        Mock(Integer s, String b) { this.status = s; this.body = b; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            return res;
        }
    }

    private static String subscriberRow(String orgKey, String orgName, String orgType, String orgStatus, String parent) {
        return '{'
            + '"Id":"1235g000000AaaaAAA",'
            + '"OrgKey":"' + orgKey + '",'
            + '"OrgName":"' + orgName + '",'
            + '"OrgType":"' + orgType + '",'
            + '"OrgStatus":"' + orgStatus + '",'
            + '"InstanceName":"NA45",'
            + '"ParentOrg":' + (parent == null ? 'null' : '"' + parent + '"') + ','
            + '"MetadataPackageId":"0335g000000AaaaAAA",'
            + '"MetadataPackageVersionId":"04t5g000000Vvv1AAC",'
            + '"SystemModstamp":"2026-02-20T14:03:00.000+0000"'
            + '}';
    }

    private static AgentSubscriberWrappers.SearchResult parse(AgentSubscriberSearchByName.SearchResponse resp) {
        return (AgentSubscriberWrappers.SearchResult) JSON.deserialize(
            resp.resultJson, AgentSubscriberWrappers.SearchResult.class
        );
    }

    @IsTest
    static void testEmptyInput() {
        AgentSubscriberSearchByName.SearchRequest req = new AgentSubscriberSearchByName.SearchRequest();
        req.orgName = '   ';

        List<AgentSubscriberSearchByName.SearchResponse> responses =
            AgentSubscriberSearchByName.search(new List<AgentSubscriberSearchByName.SearchRequest>{req});

        AgentSubscriberWrappers.SearchResult r = parse(responses[0]);
        System.assert(r.errorMessage.contains('I need an org name'));
    }

    @IsTest
    static void testTooShort() {
        AgentSubscriberSearchByName.SearchRequest req = new AgentSubscriberSearchByName.SearchRequest();
        req.orgName = 'ab';

        List<AgentSubscriberSearchByName.SearchResponse> responses =
            AgentSubscriberSearchByName.search(new List<AgentSubscriberSearchByName.SearchRequest>{req});

        System.assert(parse(responses[0]).errorMessage.contains('too short'));
    }

    @IsTest
    static void testNoMatches() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"records":[]}'));

        AgentSubscriberSearchByName.SearchRequest req = new AgentSubscriberSearchByName.SearchRequest();
        req.orgName = 'Databook';

        Test.startTest();
        List<AgentSubscriberSearchByName.SearchResponse> responses =
            AgentSubscriberSearchByName.search(new List<AgentSubscriberSearchByName.SearchRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.SearchResult r = parse(responses[0]);
        System.assert(r.errorMessage.contains('No subscribers found'));
    }

    @IsTest
    static void testGroupingProductionAndSandboxes() {
        String prodKey = '00D5g000001prod01';
        String body = '{"records":['
            + subscriberRow(prodKey, 'Acme Corp', 'Production', 'Active', null) + ','
            + subscriberRow('00D5g000001sbx001', 'Acme UAT', 'Sandbox', 'Active', prodKey) + ','
            + subscriberRow('00D5g000001sbx002', 'Acme DEV', 'Sandbox', 'Active', prodKey) + ','
            + subscriberRow('00D5g000001orph99', 'Orphan Sandbox', 'Sandbox', 'Active', '00D5g000001missed')
            + ']}';
        Test.setMock(HttpCalloutMock.class, new Mock(200, body));

        AgentSubscriberSearchByName.SearchRequest req = new AgentSubscriberSearchByName.SearchRequest();
        req.orgName = 'Acme';

        Test.startTest();
        List<AgentSubscriberSearchByName.SearchResponse> responses =
            AgentSubscriberSearchByName.search(new List<AgentSubscriberSearchByName.SearchRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.SearchResult r = parse(responses[0]);
        System.assertEquals(1, r.productions.size());
        System.assertEquals(prodKey, r.productions[0].production.orgKey);
        System.assertEquals(2, r.productions[0].sandboxes.size());
        System.assertEquals(1, r.orphanSandboxes.size());
        System.assertEquals('00D5g000001orph99', r.orphanSandboxes[0].orgKey);
    }

    @IsTest
    static void testSandboxCapAtFive() {
        String prodKey = '00D5g000001prod01';
        List<String> rows = new List<String>();
        rows.add(subscriberRow(prodKey, 'Big Co', 'Production', 'Active', null));
        for (Integer i = 0; i < 7; i++) {
            rows.add(subscriberRow('00D5g000001sbx00' + i, 'Big Co Sbx ' + i, 'Sandbox', 'Active', prodKey));
        }
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"records":[' + String.join(rows, ',') + ']}'));

        AgentSubscriberSearchByName.SearchRequest req = new AgentSubscriberSearchByName.SearchRequest();
        req.orgName = 'Big Co';

        Test.startTest();
        List<AgentSubscriberSearchByName.SearchResponse> responses =
            AgentSubscriberSearchByName.search(new List<AgentSubscriberSearchByName.SearchRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.SearchResult r = parse(responses[0]);
        System.assertEquals(5, r.productions[0].sandboxes.size(), 'Sandboxes should cap at 5');
    }

    @IsTest
    static void testProductionCapAtFive() {
        List<String> rows = new List<String>();
        for (Integer i = 0; i < 7; i++) {
            rows.add(subscriberRow('00D5g00000' + i + 'prod01', 'Prod ' + i, 'Production', 'Active', null));
        }
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"records":[' + String.join(rows, ',') + ']}'));

        AgentSubscriberSearchByName.SearchRequest req = new AgentSubscriberSearchByName.SearchRequest();
        req.orgName = 'Prod';

        Test.startTest();
        List<AgentSubscriberSearchByName.SearchResponse> responses =
            AgentSubscriberSearchByName.search(new List<AgentSubscriberSearchByName.SearchRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.SearchResult r = parse(responses[0]);
        System.assertEquals(5, r.productions.size(), 'Productions should cap at 5');
    }

    @IsTest
    static void testNullRequest() {
        List<AgentSubscriberSearchByName.SearchResponse> responses =
            AgentSubscriberSearchByName.search(new List<AgentSubscriberSearchByName.SearchRequest>{null});
        System.assert(parse(responses[0]).errorMessage.contains('I need an org name'));
    }
}
