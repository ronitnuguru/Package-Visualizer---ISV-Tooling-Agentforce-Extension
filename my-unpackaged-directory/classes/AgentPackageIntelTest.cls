@IsTest
private class AgentPackageIntelTest {

    private static final String VER_ID = '04t5g000000Vvv4AAC';
    private static final String DEP_ID = '04t5g000000Dep1AAC';

    private static ObjectWrappers.PackageVersionWrapper version(String id, Integer major, Integer minor, Integer patch, Boolean released) {
        ObjectWrappers.PackageVersionWrapper v = new ObjectWrappers.PackageVersionWrapper();
        v.subscriberPackageVersionId = id;
        v.package2Id = '0Ho5g000000AaaaAAA';
        v.name = 'Package Visualizer';
        v.majorVersion = major;
        v.minorVersion = minor;
        v.patchVersion = patch;
        v.isReleased = released;
        return v;
    }

    private static AgentPackageIntel.IntelResponse invoke(String versionId) {
        AgentPackageIntel.IntelRequest req = new AgentPackageIntel.IntelRequest();
        req.subscriberPackageVersionId = versionId;
        return AgentPackageIntel.getIntel(new List<AgentPackageIntel.IntelRequest>{ req })[0];
    }

    private static AgentPackageWrappers.PackageVersionInsight parse(AgentPackageIntel.IntelResponse resp) {
        return (AgentPackageWrappers.PackageVersionInsight) JSON.deserialize(
            resp.resultJson, AgentPackageWrappers.PackageVersionInsight.class
        );
    }

    // Inject an empty dependencies response so enrichDependencies never fires a real callout.
    private static void mockNoDependencies() {
        AgentPackageIntel.mockDependencies = new ObjectWrappers.PackageDependenciesResponse();
        AgentPackageIntel.mockDependencies.dependencies = new List<ObjectWrappers.PackageDependencyWrapper>();
    }

    @IsTest
    static void shouldReturnReady_WhenReviewedAndCovered() {
        AgentPackageIntel.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ version(VER_ID, 8, 24, 0, true) };
        AgentPackageIntel.mockCoverage = '92';
        AgentPackageIntel.mockIsSecurityReviewed = true;
        AgentPackageIntel.mockDependencies = new ObjectWrappers.PackageDependenciesResponse();
        AgentPackageIntel.mockDependencies.dependencies = new List<ObjectWrappers.PackageDependencyWrapper>();

        Test.startTest();
        AgentPackageIntel.IntelResponse resp = invoke(VER_ID);
        Test.stopTest();

        // Both surfaces populated from one invocation (render-once seam).
        System.assertNotEquals(null, resp.result, 'typed result must be populated for in-app render');
        System.assert(String.isNotBlank(resp.resultJson), 'resultJson must be populated for Slack render');

        AgentPackageWrappers.PackageVersionInsight insight = parse(resp);
        System.assertEquals('8.24.0', insight.versionNumber);
        System.assertEquals(92, insight.codeCoveragePercent);
        System.assertEquals(true, insight.isSecurityReviewed);
        System.assertEquals('ready', insight.promotionReadinessTag);
    }

    @IsTest
    static void shouldFlagCoverageGap_WhenBelowSeventyFive() {
        AgentPackageIntel.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ version(VER_ID, 8, 24, 0, true) };
        AgentPackageIntel.mockCoverage = '60';
        AgentPackageIntel.mockIsSecurityReviewed = true;
        mockNoDependencies();

        Test.startTest();
        AgentPackageWrappers.PackageVersionInsight insight = parse(invoke(VER_ID));
        Test.stopTest();

        System.assertEquals(60, insight.codeCoveragePercent);
        System.assertEquals('coverage-gap', insight.promotionReadinessTag);
    }

    @IsTest
    static void shouldFlagNotReviewed_WhenSecurityReviewFalse() {
        AgentPackageIntel.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ version(VER_ID, 8, 24, 0, true) };
        AgentPackageIntel.mockCoverage = '90';
        AgentPackageIntel.mockIsSecurityReviewed = false;
        mockNoDependencies();

        Test.startTest();
        AgentPackageWrappers.PackageVersionInsight insight = parse(invoke(VER_ID));
        Test.stopTest();

        System.assertEquals('Not reviewed', insight.securityReviewLabel);
        System.assertEquals('not-reviewed', insight.promotionReadinessTag);
    }

    @IsTest
    static void shouldReportUnknownCoverage_WhenCoverageBlank() {
        AgentPackageIntel.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ version(VER_ID, 8, 24, 0, true) };
        AgentPackageIntel.mockCoverage = '';
        AgentPackageIntel.mockIsSecurityReviewed = true;
        mockNoDependencies();

        Test.startTest();
        AgentPackageWrappers.PackageVersionInsight insight = parse(invoke(VER_ID));
        Test.stopTest();

        System.assertEquals(-1, insight.codeCoveragePercent);
        System.assertEquals('Unknown', insight.codeCoverageLabel);
    }

    @IsTest
    static void shouldCountDependencies_AndResolveKnownNames() {
        AgentPackageIntel.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{
            version(VER_ID, 8, 24, 0, true),
            version(DEP_ID, 2, 1, 0, true)
        };
        AgentPackageIntel.mockCoverage = '88';
        AgentPackageIntel.mockIsSecurityReviewed = true;
        ObjectWrappers.PackageDependenciesResponse deps = new ObjectWrappers.PackageDependenciesResponse();
        ObjectWrappers.PackageDependencyWrapper dep = new ObjectWrappers.PackageDependencyWrapper();
        dep.subscriberPackageVersionId = DEP_ID;
        deps.dependencies = new List<ObjectWrappers.PackageDependencyWrapper>{ dep };
        AgentPackageIntel.mockDependencies = deps;

        Test.startTest();
        AgentPackageWrappers.PackageVersionInsight insight = parse(invoke(VER_ID));
        Test.stopTest();

        System.assertEquals(1, insight.dependencyCount);
        System.assertEquals(1, insight.dependencies.size());
        System.assertEquals('2.1.0', insight.dependencies[0].versionNumber, 'known dependency should resolve its version');
    }

    @IsTest
    static void shouldReturnError_WhenIdInvalid() {
        Test.startTest();
        AgentPackageWrappers.PackageVersionInsight insight = parse(invoke('not-a-04t'));
        Test.stopTest();

        System.assertEquals('unknown', insight.promotionReadinessTag);
        System.assert(insight.errorMessage.contains('04t'), 'should explain the expected id format');
    }

    @IsTest
    static void shouldReturnError_WhenNullRequest() {
        Test.startTest();
        AgentPackageIntel.IntelResponse resp = AgentPackageIntel.getIntel(new List<AgentPackageIntel.IntelRequest>{ null })[0];
        Test.stopTest();

        AgentPackageWrappers.PackageVersionInsight insight = parse(resp);
        System.assertNotEquals(null, insight.errorMessage);
    }

    @IsTest
    static void shouldProcessBulk_WhenManyRequests() {
        AgentPackageIntel.mockVersions = new List<ObjectWrappers.PackageVersionWrapper>{ version(VER_ID, 8, 24, 0, true) };
        AgentPackageIntel.mockCoverage = '90';
        AgentPackageIntel.mockIsSecurityReviewed = true;
        mockNoDependencies();

        List<AgentPackageIntel.IntelRequest> requests = new List<AgentPackageIntel.IntelRequest>();
        for (Integer i = 0; i < 200; i++) {
            AgentPackageIntel.IntelRequest req = new AgentPackageIntel.IntelRequest();
            req.subscriberPackageVersionId = VER_ID;
            requests.add(req);
        }

        Test.startTest();
        List<AgentPackageIntel.IntelResponse> responses = AgentPackageIntel.getIntel(requests);
        Test.stopTest();

        System.assertEquals(200, responses.size(), 'every request must yield a response');
    }
}
