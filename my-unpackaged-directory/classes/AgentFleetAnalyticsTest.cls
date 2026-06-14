@IsTest
private class AgentFleetAnalyticsTest {

    private static final String CURRENT_ID = '04t5g000000Vvv4AAC';
    private static final String BEHIND_ID  = '04t5g000000Vvv1AAC';

    private static AgentFleetWrappers.FleetBucket bucket(String label, Integer count) {
        AgentFleetWrappers.FleetBucket b = new AgentFleetWrappers.FleetBucket();
        b.label = label;
        b.count = count;
        return b;
    }

    private static ObjectWrappers.PackageSubscriberWrapper subscriber(String installedVersionId) {
        ObjectWrappers.PackageSubscriberWrapper s = new ObjectWrappers.PackageSubscriberWrapper();
        s.orgKey = '00D5g00000' + installedVersionId.substring(3, 11);
        s.metadataPackageVersionId = installedVersionId;
        return s;
    }

    private static AgentFleetAnalytics.FleetResponse invoke(String groupBy) {
        AgentFleetAnalytics.FleetRequest req = new AgentFleetAnalytics.FleetRequest();
        req.groupByField = groupBy;
        return AgentFleetAnalytics.getAnalytics(new List<AgentFleetAnalytics.FleetRequest>{ req })[0];
    }

    private static AgentFleetWrappers.FleetAnalytics parse(AgentFleetAnalytics.FleetResponse resp) {
        return (AgentFleetWrappers.FleetAnalytics) JSON.deserialize(
            resp.resultJson, AgentFleetWrappers.FleetAnalytics.class
        );
    }

    @IsTest
    static void shouldBreakdownByOrgType_AndComputePercentages() {
        AgentFleetAnalytics.mockBuckets = new List<AgentFleetWrappers.FleetBucket>{
            bucket('Production', 30),
            bucket('Sandbox', 10)
        };
        AgentFleetAnalytics.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>();

        Test.startTest();
        AgentFleetAnalytics.FleetResponse resp = invoke('OrgType');
        Test.stopTest();

        System.assertNotEquals(null, resp.result, 'typed result for in-app render');
        AgentFleetWrappers.FleetAnalytics analytics = parse(resp);
        System.assertEquals('OrgType', analytics.groupedBy);
        System.assertEquals(40, analytics.segmentTotal);
        System.assertEquals(2, analytics.buckets.size());
        System.assertEquals(75.0, analytics.buckets[0].percentOfSegments, 'Production is 30/40 = 75%');
    }

    @IsTest
    static void shouldComputeDrift_AcrossDistinctVersions() {
        AgentFleetAnalytics.mockBuckets = new List<AgentFleetWrappers.FleetBucket>{ bucket('Production', 2) };
        AgentFleetAnalytics.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber(CURRENT_ID),
            subscriber(BEHIND_ID)
        };
        // Drive AgentVersionDrift via its own seams: CURRENT is newest, BEHIND is 3 back.
        AgentVersionDrift.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{
            versionFor(CURRENT_ID), versionFor(BEHIND_ID)
        };
        AgentVersionDrift.mockLatestVersionIds = new List<String>{
            CURRENT_ID, '04t5g000000Vvv3AAC', '04t5g000000Vvv2AAC', BEHIND_ID
        };

        Test.startTest();
        AgentFleetWrappers.FleetAnalytics analytics = parse(invoke('OrgType'));
        Test.stopTest();

        System.assertEquals(1, analytics.driftCurrent, 'one org on the latest version');
        System.assertEquals(1, analytics.driftReleasesBehind3plus, 'one org 3 releases behind');
    }

    private static ObjectWrappers.PackageVersionWrapper versionFor(String id) {
        ObjectWrappers.PackageVersionWrapper v = new ObjectWrappers.PackageVersionWrapper();
        v.subscriberPackageVersionId = id;
        v.package2Id = '0Ho5g000000AaaaAAA';
        v.majorVersion = 8;
        v.minorVersion = 24;
        v.patchVersion = 0;
        return v;
    }

    @IsTest
    static void shouldReturnError_WhenGroupFieldInvalid() {
        Test.startTest();
        AgentFleetWrappers.FleetAnalytics analytics = parse(invoke('SomethingElse'));
        Test.stopTest();

        System.assertNotEquals(null, analytics.errorMessage);
        System.assert(analytics.errorMessage.contains('OrgType'), 'should list the allowed dimensions');
    }

    @IsTest
    static void shouldHandleEmptyFleet_WithoutError() {
        AgentFleetAnalytics.mockBuckets = new List<AgentFleetWrappers.FleetBucket>();
        AgentFleetAnalytics.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>();

        Test.startTest();
        AgentFleetWrappers.FleetAnalytics analytics = parse(invoke('OrgStatus'));
        Test.stopTest();

        System.assertEquals(null, analytics.errorMessage, 'empty fleet is not an error');
        System.assertEquals(0, analytics.segmentTotal);
    }

    @IsTest
    static void shouldDefaultToOrgType_WhenGroupFieldBlank() {
        AgentFleetAnalytics.mockBuckets = new List<AgentFleetWrappers.FleetBucket>{ bucket('Production', 1) };
        AgentFleetAnalytics.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>();

        Test.startTest();
        AgentFleetWrappers.FleetAnalytics analytics = parse(invoke(null));
        Test.stopTest();

        System.assertEquals('OrgType', analytics.groupedBy);
    }

    @IsTest
    static void shouldRunRealQueryPath_WhenNoMocksInjected() {
        // No @TestVisible seams set: exercise the real getSubscriberChartData -> toBuckets
        // and get2GPPackageSubscriberList drift paths. With no subscriber data the result is
        // empty, but the live branches execute for coverage.
        Test.setMock(HttpCalloutMock.class, new ToolingAPICalloutMock());

        Test.startTest();
        AgentFleetWrappers.FleetAnalytics analytics = parse(invoke('InstanceName'));
        Test.stopTest();

        System.assertEquals('InstanceName', analytics.groupedBy);
        System.assertEquals(null, analytics.errorMessage, 'live empty fleet is not an error');
    }

    @IsTest
    static void shouldProcessBulk_WhenManyRequests() {
        AgentFleetAnalytics.mockBuckets = new List<AgentFleetWrappers.FleetBucket>{ bucket('Production', 1) };
        AgentFleetAnalytics.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>();

        List<AgentFleetAnalytics.FleetRequest> requests = new List<AgentFleetAnalytics.FleetRequest>();
        for (Integer i = 0; i < 200; i++) {
            AgentFleetAnalytics.FleetRequest req = new AgentFleetAnalytics.FleetRequest();
            req.groupByField = 'OrgType';
            requests.add(req);
        }

        Test.startTest();
        List<AgentFleetAnalytics.FleetResponse> responses = AgentFleetAnalytics.getAnalytics(requests);
        Test.stopTest();

        System.assertEquals(200, responses.size());
    }
}
