@IsTest
private class AgentVersionDriftTest {

    private static final String INSTALLED_ID = '04t5g000000Vvv1AAC';
    private static final String NEWER_ID     = '04t5g000000Vvv2AAC';
    private static final String LATEST_ID    = '04t5g000000Vvv4AAC';

    private static ObjectWrappers.PackageVersionWrapper version(String id) {
        ObjectWrappers.PackageVersionWrapper v = new ObjectWrappers.PackageVersionWrapper();
        v.subscriberPackageVersionId = id;
        v.package2Id = '0Ho5g000000AaaaAAA';
        v.majorVersion = 8;
        v.minorVersion = 20;
        v.patchVersion = 0;
        return v;
    }

    @IsTest
    static void shouldReturnZero_WhenInstalledIsLatest() {
        AgentVersionDrift.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ version(LATEST_ID) };
        AgentVersionDrift.mockLatestVersionIds = new List<String>{ LATEST_ID, NEWER_ID, INSTALLED_ID };

        Test.startTest();
        Integer behind = AgentVersionDrift.releasesBehind(LATEST_ID);
        Test.stopTest();

        System.assertEquals(0, behind, 'newest released version is 0 releases behind');
        System.assertEquals('current', AgentVersionDrift.driftTag(behind));
    }

    @IsTest
    static void shouldCountReleasesBehind_WhenOlderInstalled() {
        AgentVersionDrift.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ version(INSTALLED_ID) };
        // newest-first: LATEST(0), NEWER(1), INSTALLED(2)
        AgentVersionDrift.mockLatestVersionIds = new List<String>{ LATEST_ID, NEWER_ID, INSTALLED_ID };

        Test.startTest();
        Integer behind = AgentVersionDrift.releasesBehind(INSTALLED_ID);
        Test.stopTest();

        System.assertEquals(2, behind, 'installed is the 3rd entry, so 2 releases behind');
        System.assertEquals('minor-behind', AgentVersionDrift.driftTag(behind));
    }

    @IsTest
    static void shouldTagMajorBehind_WhenThreePlus() {
        System.assertEquals('major-behind', AgentVersionDrift.driftTag(3));
        System.assertEquals('major-behind', AgentVersionDrift.driftTag(10));
    }

    @IsTest
    static void shouldReturnZero_WhenBlankInstalledId() {
        Test.startTest();
        System.assertEquals(0, AgentVersionDrift.releasesBehind(''));
        System.assertEquals(0, AgentVersionDrift.releasesBehind(null));
        Test.stopTest();
    }

    @IsTest
    static void shouldReturnFullyBehind_WhenInstalledNotInReleasedList() {
        AgentVersionDrift.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ version(INSTALLED_ID) };
        AgentVersionDrift.mockLatestVersionIds = new List<String>{ LATEST_ID, NEWER_ID };

        Test.startTest();
        Integer behind = AgentVersionDrift.releasesBehind(INSTALLED_ID);
        Test.stopTest();

        System.assertEquals(2, behind, 'unfound installed id treated as fully behind (size of released list)');
    }

    @IsTest
    static void shouldRunRealQueryPath_WhenNoMocksInjected() {
        // No @TestVisible seams set: exercise the real Package2Interface callout path
        // (findVersion -> getPackage2Versions). The mock yields no matching version,
        // so the method returns 0 — but the real branch executes for coverage.
        Test.setMock(HttpCalloutMock.class, new ToolingAPICalloutMock());

        Test.startTest();
        Integer behind = AgentVersionDrift.releasesBehind(INSTALLED_ID);
        Test.stopTest();

        System.assertEquals(0, behind, 'no resolvable version via the live query path returns 0');
    }
}
