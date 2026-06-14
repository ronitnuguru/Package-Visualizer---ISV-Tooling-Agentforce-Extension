@IsTest
private class AgentPackageCatalogTest {

    private static ObjectWrappers.PackageWrapper pkg(String name, String container, String ns, String descText, String subId) {
        ObjectWrappers.PackageWrapper p = new ObjectWrappers.PackageWrapper();
        p.name = name;
        p.containerOptions = container;
        p.namespacePrefix = ns;
        p.description = descText;
        p.subscriberPackageID = subId;
        return p;
    }

    private static List<ObjectWrappers.PackageWrapper> sampleRows() {
        return new List<ObjectWrappers.PackageWrapper>{
            pkg('Billing Manager', 'Managed', 'bill', 'Invoicing toolkit', '033000000000001AAA'),
            pkg('Reporting Suite', 'Managed', 'rpt', 'Dashboards', '033000000000002AAA'),
            pkg('Internal Utils', 'Unlocked', null, 'Shared helpers', '033000000000003AAA')
        };
    }

    private static AgentPackageWrappers.PackageCatalog invoke(String filter) {
        AgentPackageCatalog.CatalogRequest req = new AgentPackageCatalog.CatalogRequest();
        req.filter = filter;
        return AgentPackageCatalog.getCatalog(new List<AgentPackageCatalog.CatalogRequest>{ req })[0].result;
    }

    @IsTest
    static void shouldReturnAll_WhenFilterAll() {
        AgentPackageCatalog.mockPackages = sampleRows();

        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog = invoke('all');
        Test.stopTest();

        System.assertEquals(3, catalog.packageCount, 'all three packages should be returned');
        System.assertEquals(3, catalog.packages.size(), 'packages list size should match count');
        System.assertEquals('all', catalog.filterApplied);
        System.assertEquals('3 2GP packages.', catalog.headline);
    }

    @IsTest
    static void shouldMapEveryField_WhenReturned() {
        AgentPackageCatalog.mockPackages = new List<ObjectWrappers.PackageWrapper>{
            pkg('Billing Manager', 'Managed', 'bill', 'Invoicing toolkit', '033000000000001AAA')
        };

        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog = invoke('all');
        Test.stopTest();

        AgentPackageWrappers.PackageSummary s = catalog.packages[0];
        System.assertEquals('033000000000001AAA', s.subscriberPackageId, 'subscriber package id should be mapped');
        System.assertEquals('Billing Manager', s.name);
        System.assertEquals('Managed', s.containerOptions);
        System.assertEquals('bill', s.namespacePrefix);
        System.assertEquals('Invoicing toolkit', s.description);
    }

    @IsTest
    static void shouldReturnOnlyManaged_WhenFilterManaged() {
        AgentPackageCatalog.mockPackages = sampleRows();

        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog = invoke('managed');
        Test.stopTest();

        System.assertEquals(2, catalog.packageCount, 'only the two managed packages should be returned');
        System.assertEquals('managed', catalog.filterApplied);
        System.assertEquals('2 managed packages.', catalog.headline);
        for (AgentPackageWrappers.PackageSummary s : catalog.packages) {
            System.assertEquals('Managed', s.containerOptions, 'every returned row must be Managed');
        }
    }

    @IsTest
    static void shouldReturnOnlyUnlocked_WhenFilterUnlocked() {
        AgentPackageCatalog.mockPackages = sampleRows();

        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog = invoke('unlocked');
        Test.stopTest();

        System.assertEquals(1, catalog.packageCount, 'only the single unlocked package should be returned');
        System.assertEquals('unlocked', catalog.filterApplied);
        System.assertEquals('1 unlocked package.', catalog.headline);
        System.assertEquals('Unlocked', catalog.packages[0].containerOptions);
    }

    @IsTest
    static void shouldMatchByName_WhenFilterIsNameCaseInsensitive() {
        AgentPackageCatalog.mockPackages = sampleRows();

        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog = invoke('billing');
        Test.stopTest();

        System.assertEquals(1, catalog.packageCount, 'one package should match the name search');
        System.assertEquals('Billing Manager', catalog.packages[0].name);
        System.assertEquals('name:"billing"', catalog.filterApplied);
        System.assertEquals('1 package matching "billing".', catalog.headline);
    }

    @IsTest
    static void shouldReturnEmpty_WhenNameHasNoMatch() {
        AgentPackageCatalog.mockPackages = sampleRows();

        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog = invoke('nonexistent');
        Test.stopTest();

        System.assertEquals(0, catalog.packageCount, 'no package should match');
        System.assertEquals(0, catalog.packages.size(), 'packages list should be empty');
        System.assertEquals('No packages found matching "nonexistent".', catalog.headline);
    }

    @IsTest
    static void shouldTreatBlankAsAll_WhenFilterBlank() {
        AgentPackageCatalog.mockPackages = sampleRows();

        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog = invoke('   ');
        Test.stopTest();

        System.assertEquals(3, catalog.packageCount, 'blank filter should behave like all');
        System.assertEquals('all', catalog.filterApplied);
    }

    @IsTest
    static void shouldTreatNullAsAll_WhenFilterNull() {
        AgentPackageCatalog.mockPackages = sampleRows();

        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog = invoke(null);
        Test.stopTest();

        System.assertEquals(3, catalog.packageCount, 'null filter should behave like all');
        System.assertEquals('all', catalog.filterApplied);
    }

    @IsTest
    static void shouldProcessBulk_WhenManyRequests() {
        AgentPackageCatalog.mockPackages = sampleRows();

        List<AgentPackageCatalog.CatalogRequest> requests = new List<AgentPackageCatalog.CatalogRequest>();
        for (Integer i = 0; i < 200; i++) {
            AgentPackageCatalog.CatalogRequest req = new AgentPackageCatalog.CatalogRequest();
            req.filter = 'all';
            requests.add(req);
        }

        Test.startTest();
        List<AgentPackageCatalog.CatalogResponse> responses = AgentPackageCatalog.getCatalog(requests);
        Test.stopTest();

        System.assertEquals(200, responses.size(), 'every request must yield a response');
    }

    @IsTest
    static void shouldHandleNullRequest_WithoutThrowing() {
        AgentPackageCatalog.mockPackages = sampleRows();

        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog =
            AgentPackageCatalog.getCatalog(new List<AgentPackageCatalog.CatalogRequest>{ null })[0].result;
        Test.stopTest();

        // null request -> null filter -> all
        System.assertEquals(3, catalog.packageCount, 'a null request should be treated as the all filter');
    }

    @IsTest
    static void shouldUseLiveCallout_WhenNoMockInjected() {
        // No mockPackages injected -> exercises the real Package2Interface.getPackage2('ASC') branch.
        Test.setMock(HttpCalloutMock.class, new ToolingAPICalloutMock());

        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog = invoke('all');
        Test.stopTest();

        System.assertEquals(1, catalog.packageCount, 'the mock returns one Package2 row');
        AgentPackageWrappers.PackageSummary s = catalog.packages[0];
        System.assertEquals('DummyApp', s.name);
        System.assertEquals('Unlocked', s.containerOptions);
        System.assertEquals('033000000000000AAA', s.subscriberPackageId);
    }

    @IsTest
    static void shouldSetErrorMessage_WhenLoadFails() {
        // No mock injected and no HttpCalloutMock registered -> the live callout throws,
        // which resolve() must catch and surface as an errorMessage (never propagate).
        Test.startTest();
        AgentPackageWrappers.PackageCatalog catalog = invoke('all');
        Test.stopTest();

        System.assertNotEquals(null, catalog.errorMessage, 'a load failure should be reported, not thrown');
        System.assertEquals(0, catalog.packages.size(), 'packages should be empty on load failure');
    }
}
