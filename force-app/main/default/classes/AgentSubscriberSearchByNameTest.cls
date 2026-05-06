@IsTest
private class AgentSubscriberSearchByNameTest {

    private static ObjectWrappers.PackageSubscriberWrapper subscriber(String orgKey, String orgName, String orgType, String orgStatus, String parent) {
        ObjectWrappers.PackageSubscriberWrapper s = new ObjectWrappers.PackageSubscriberWrapper();
        s.id                       = '1235g000000AaaaAAA';
        s.orgKey                   = orgKey;
        s.orgName                  = orgName;
        s.orgType                  = orgType;
        s.orgStatus                = orgStatus;
        s.instanceName             = 'NA45';
        s.parentOrg                = parent;
        s.metadataPackageId        = '0335g000000AaaaAAA';
        s.metadataPackageVersionId = '04t5g000000Vvv1AAC';
        s.SystemModstamp           = Datetime.newInstanceGmt(2026, 2, 20, 14, 3, 0);
        return s;
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
        AgentSubscriberSearchByName.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>();

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
        AgentSubscriberSearchByName.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber(prodKey, 'Acme Corp', 'Production', 'Active', null),
            subscriber('00D5g000001sbx001', 'Acme UAT', 'Sandbox', 'Active', prodKey),
            subscriber('00D5g000001sbx002', 'Acme DEV', 'Sandbox', 'Active', prodKey),
            subscriber('00D5g000001orph99', 'Orphan Sandbox', 'Sandbox', 'Active', '00D5g000001missed')
        };

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
        List<ObjectWrappers.PackageSubscriberWrapper> rows = new List<ObjectWrappers.PackageSubscriberWrapper>();
        rows.add(subscriber(prodKey, 'Big Co', 'Production', 'Active', null));
        for (Integer i = 0; i < 7; i++) {
            rows.add(subscriber('00D5g000001sbx00' + i, 'Big Co Sbx ' + i, 'Sandbox', 'Active', prodKey));
        }
        AgentSubscriberSearchByName.mockSubscribers = rows;

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
        List<ObjectWrappers.PackageSubscriberWrapper> rows = new List<ObjectWrappers.PackageSubscriberWrapper>();
        for (Integer i = 0; i < 7; i++) {
            rows.add(subscriber('00D5g00000' + i + 'prod01', 'Prod ' + i, 'Production', 'Active', null));
        }
        AgentSubscriberSearchByName.mockSubscribers = rows;

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
