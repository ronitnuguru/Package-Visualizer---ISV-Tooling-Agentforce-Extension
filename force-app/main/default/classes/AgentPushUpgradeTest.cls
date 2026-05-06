@IsTest
private class AgentPushUpgradeTest {

    private static final String ORG_KEY           = '00D5g000001abcDEFG';
    private static final String PKG_ID            = '0335g000000AaaaAAA';
    private static final String INSTALLED_VER_ID  = '04t5g000000Vvv1AAC';
    private static final String LATEST_VER_ID     = '04t5g000000Vvv4AAC';

    private static ObjectWrappers.PackageSubscriberWrapper subscriber(String versionId) {
        ObjectWrappers.PackageSubscriberWrapper s = new ObjectWrappers.PackageSubscriberWrapper();
        s.id                       = '1235g000000AaaaAAA';
        s.orgKey                   = ORG_KEY;
        s.orgName                  = 'Acme Corp';
        s.orgType                  = 'Production';
        s.orgStatus                = 'Active';
        s.instanceName             = 'NA45';
        s.parentOrg                = null;
        s.metadataPackageId        = PKG_ID;
        s.metadataPackageVersionId = versionId;
        s.SystemModstamp           = Datetime.newInstanceGmt(2026, 2, 20, 14, 3, 0);
        return s;
    }

    private static ObjectWrappers.PackageVersionWrapper version(String id, Integer major, Integer minor, Integer patch) {
        ObjectWrappers.PackageVersionWrapper v = new ObjectWrappers.PackageVersionWrapper();
        v.subscriberPackageVersionId = id;
        v.package2Id                 = PKG_ID;
        v.majorVersion               = major;
        v.minorVersion               = minor;
        v.patchVersion               = patch;
        v.buildNumber                = 1;
        v.isReleased                 = true;
        return v;
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
        // Inject an empty subscriber list so findSubscriber returns null, bypassing any real
        // PackageSubscriber data that lives in the packaging org.
        AgentPushUpgrade.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>();

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
        AgentPushUpgrade.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber(LATEST_VER_ID)
        };
        AgentPushUpgrade.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{
            version(LATEST_VER_ID, 8, 24, 0)
        };
        AgentPushUpgrade.mockLatestVersionIds = new List<String>{ LATEST_VER_ID };

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
    static void testSuccessfulPush() {
        AgentPushUpgrade.mockSubscribers = new List<ObjectWrappers.PackageSubscriberWrapper>{
            subscriber(INSTALLED_VER_ID)
        };
        AgentPushUpgrade.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{
            version(INSTALLED_VER_ID, 8, 21, 0),
            version(LATEST_VER_ID,    8, 24, 0)
        };
        AgentPushUpgrade.mockLatestVersionIds = new List<String>{ LATEST_VER_ID };
        AgentPushUpgrade.mockPushRequestId = '0DV5g000000AbcdEFG';

        AgentPushUpgrade.PushRequest req = new AgentPushUpgrade.PushRequest();
        req.orgKey = ORG_KEY;

        Test.startTest();
        List<AgentPushUpgrade.PushResponse> responses =
            AgentPushUpgrade.push(new List<AgentPushUpgrade.PushRequest>{req});
        Test.stopTest();

        AgentSubscriberWrappers.PushResult r = parse(responses[0]);
        System.assertEquals(true, r.success);
        System.assertEquals('0DV5g000000AbcdEFG', r.pushRequestId);
        System.assertEquals('8.21.0', r.fromVersion);
        System.assertEquals('8.24.0', r.targetVersion);
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
