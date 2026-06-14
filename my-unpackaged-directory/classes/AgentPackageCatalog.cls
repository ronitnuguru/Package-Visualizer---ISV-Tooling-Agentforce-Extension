/**
 * Agent action: list the org's 2GP packages. Reuses the base package's
 * Package2Interface.getPackage2('ASC') read (up to 500 Package2 rows — Managed and Unlocked),
 * then filters and maps in Apex by an optional caller-supplied filter ("all", "managed",
 * "unlocked", or a package-name search). Returns ONLY a typed displayable PackageCatalog for
 * in-app Lightning-type rendering — no resultJson, no prompt template (this slice is in-app only).
 * @TestVisible seam lets tests inject package rows without a Tooling API callout.
 */
@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentPackageCatalog {

    @TestVisible
    private static List<ObjectWrappers.PackageWrapper> mockPackages;

    @InvocableMethod(
        label='List Packages'
        description='Lists 2GP packages — all, managed, unlocked, or by name — with type, namespace, and subscriber package id.'
        category='ISV Agent'
        callout=true
    )
    global static List<CatalogResponse> getCatalog(List<CatalogRequest> requests) {
        List<CatalogResponse> responses = new List<CatalogResponse>();
        for (CatalogRequest req : requests) {
            CatalogResponse resp = new CatalogResponse();
            resp.result = resolve(req == null ? null : req.filter);
            responses.add(resp);
        }
        return responses;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class CatalogRequest {
        @InvocableVariable(
            label='Filter'
            description='Optional: "all", "managed", "unlocked", or a package name to search. Blank = all.'
        )
        global String filter;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class CatalogResponse {
        @InvocableVariable(
            label='Package Catalog'
            description='Structured package list for in-app rendering.'
        )
        global AgentPackageWrappers.PackageCatalog result;
    }

    private static AgentPackageWrappers.PackageCatalog resolve(String rawFilter) {
        AgentPackageWrappers.PackageCatalog catalog = new AgentPackageWrappers.PackageCatalog();
        catalog.packages = new List<AgentPackageWrappers.PackageSummary>();
        catalog.packageCount = 0;

        List<ObjectWrappers.PackageWrapper> rows;
        try {
            rows = (mockPackages != null) ? mockPackages : Package2Interface.getPackage2('ASC');
        } catch (Exception e) {
            catalog.errorMessage = 'Could not load packages: ' + e.getMessage();
            catalog.headline = 'Could not load packages.';
            catalog.filterApplied = 'all';
            return catalog;
        }
        if (rows == null) {
            rows = new List<ObjectWrappers.PackageWrapper>();
        }

        String term = (rawFilter == null) ? '' : rawFilter.trim();
        String mode = normalizeMode(term);

        for (ObjectWrappers.PackageWrapper row : rows) {
            if (matches(row, mode, term)) {
                catalog.packages.add(toSummary(row));
            }
        }

        catalog.packageCount = catalog.packages.size();
        catalog.filterApplied = (mode == 'name') ? 'name:"' + term + '"' : mode;
        catalog.headline = buildHeadline(mode, term, catalog.packageCount);
        return catalog;
    }

    // Maps a raw filter to one of: all | managed | unlocked | name.
    private static String normalizeMode(String term) {
        if (String.isBlank(term) || term.equalsIgnoreCase('all') || term.equalsIgnoreCase('2gp')) {
            return 'all';
        }
        if (term.equalsIgnoreCase('managed')) {
            return 'managed';
        }
        if (term.equalsIgnoreCase('unlocked')) {
            return 'unlocked';
        }
        return 'name';
    }

    private static Boolean matches(ObjectWrappers.PackageWrapper row, String mode, String term) {
        if (row == null) {
            return false;
        }
        if (mode == 'managed' || mode == 'unlocked') {
            return row.containerOptions != null && row.containerOptions.equalsIgnoreCase(mode);
        }
        if (mode == 'name') {
            return row.name != null && row.name.containsIgnoreCase(term);
        }
        return true; // 'all'
    }

    private static AgentPackageWrappers.PackageSummary toSummary(ObjectWrappers.PackageWrapper row) {
        AgentPackageWrappers.PackageSummary summary = new AgentPackageWrappers.PackageSummary();
        summary.subscriberPackageId = row.subscriberPackageID;
        summary.name = row.name;
        summary.containerOptions = row.containerOptions;
        summary.namespacePrefix = row.namespacePrefix;
        summary.description = row.description;
        return summary;
    }

    private static String buildHeadline(String mode, String term, Integer count) {
        String noun = (count == 1) ? 'package' : 'packages';
        if (count == 0) {
            if (mode == 'name') {
                return 'No packages found matching "' + term + '".';
            }
            return 'No packages found.';
        }
        if (mode == 'managed') {
            return count + ' managed ' + noun + '.';
        }
        if (mode == 'unlocked') {
            return count + ' unlocked ' + noun + '.';
        }
        if (mode == 'name') {
            return count + ' ' + noun + ' matching "' + term + '".';
        }
        return count + ' 2GP ' + noun + '.';
    }
}
