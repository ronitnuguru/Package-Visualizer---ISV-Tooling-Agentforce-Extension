/**
 * Agent action: package & version intelligence. Given a SubscriberPackageVersion Id (04t),
 * resolves code coverage, security-review status, release state, and dependencies into a single
 * PackageVersionInsight. Returns BOTH a typed displayable result (in-app Lightning-type render)
 * AND a resultJson string (Slack prompt-template render) from one invocation — the "render once,
 * run many" seam. Reads only; calls the synchronous Package2Interface methods (never the
 * continuation controllers). @TestVisible seams let tests inject without Tooling API callouts.
 */
@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentPackageIntel {

    private static final Integer COVERAGE_GATE = 75;
    private static final Integer DEPENDENCY_ENRICH_CAP = 10;

    @TestVisible
    private static String mockCoverage;
    @TestVisible
    private static Boolean mockIsSecurityReviewed;
    @TestVisible
    private static List<ObjectWrappers.PackageVersionWrapper> mockVersions;
    @TestVisible
    private static ObjectWrappers.PackageDependenciesResponse mockDependencies;

    @InvocableMethod(
        label='Get Package Version Intelligence'
        description='Given a SubscriberPackageVersion Id (04t), returns code coverage, security-review status, release state, dependencies, and a promotion-readiness assessment for a 2GP package version.'
        category='ISV Agent'
        callout=true
    )
    global static List<IntelResponse> getIntel(List<IntelRequest> requests) {
        List<IntelResponse> responses = new List<IntelResponse>();
        for (IntelRequest req : requests) {
            AgentPackageWrappers.PackageVersionInsight insight = resolve(req == null ? null : req.subscriberPackageVersionId);
            IntelResponse resp = new IntelResponse();
            resp.result = insight;
            resp.resultJson = JSON.serialize(insight, true);
            responses.add(resp);
        }
        return responses;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class IntelRequest {
        @InvocableVariable(
            label='Subscriber Package Version Id'
            description='15 or 18 character SubscriberPackageVersion Id (starts with 04t). Pass exactly as provided — do not pad, truncate, or normalize.'
            required=true
        )
        global String subscriberPackageVersionId;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class IntelResponse {
        @InvocableVariable(
            label='Package Version Insight'
            description='Structured package version intelligence for in-app rendering.'
        )
        global AgentPackageWrappers.PackageVersionInsight result;

        @InvocableVariable(
            label='Package Version Insight JSON'
            description='JSON serialization of the insight. Feed this into the Slack prompt template.'
        )
        global String resultJson;
    }

    private static AgentPackageWrappers.PackageVersionInsight resolve(String rawId) {
        AgentPackageWrappers.PackageVersionInsight insight = new AgentPackageWrappers.PackageVersionInsight();
        String versionId = (rawId == null) ? '' : rawId.trim();
        insight.subscriberPackageVersionId = versionId;
        insight.dependencies = new List<AgentPackageWrappers.DependencyRef>();
        insight.dependencyCount = 0;
        insight.codeCoveragePercent = -1;

        if (String.isBlank(versionId) || !Pattern.matches('^04t[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$', versionId)) {
            insight.errorMessage = 'A valid SubscriberPackageVersion Id (starts with 04t, 15 or 18 chars) is required.';
            insight.promotionReadinessTag = 'unknown';
            insight.summaryLine = insight.errorMessage;
            return insight;
        }

        ObjectWrappers.PackageVersionWrapper version = findVersion(versionId);
        if (version != null) {
            insight.versionNumber = formatVersion(version);
            insight.packageName = version.name;
            insight.isReleased = version.isReleased;
            insight.releaseState = (version.isReleased == true) ? 'Released' : 'Beta';
        }

        insight.codeCoveragePercent = resolveCoverage(versionId);
        insight.codeCoverageLabel = (insight.codeCoveragePercent < 0)
            ? 'Unknown'
            : insight.codeCoveragePercent + '%';

        insight.isSecurityReviewed = resolveSecurityReview(versionId);
        insight.securityReviewLabel = (insight.isSecurityReviewed == null)
            ? 'Unknown'
            : (insight.isSecurityReviewed ? 'Passed' : 'Not reviewed');

        enrichDependencies(insight, versionId);

        insight.promotionReadinessTag = assessReadiness(insight);
        insight.summaryLine = buildSummary(insight);
        return insight;
    }

    private static Integer resolveCoverage(String versionId) {
        String coverage = (mockCoverage != null) ? mockCoverage : Package2Interface.getPackageVersionCodeCoverage(versionId);
        if (String.isBlank(coverage)) {
            return -1;
        }
        try {
            Integer parsed = Integer.valueOf(coverage);
            return (parsed < 0) ? -1 : parsed;
        } catch (Exception e) {
            return -1;
        }
    }

    private static Boolean resolveSecurityReview(String versionId) {
        return (mockIsSecurityReviewed != null)
            ? mockIsSecurityReviewed
            : Package2Interface.getIsSecurityReviewed(versionId);
    }

    private static void enrichDependencies(AgentPackageWrappers.PackageVersionInsight insight, String versionId) {
        ObjectWrappers.PackageDependenciesResponse deps = (mockDependencies != null)
            ? mockDependencies
            : Package2Interface.getPackageDependencies(versionId);
        if (deps == null || deps.dependencies == null || deps.dependencies.isEmpty()) {
            return;
        }
        Integer count = 0;
        for (ObjectWrappers.PackageDependencyWrapper dep : deps.dependencies) {
            insight.dependencyCount++;
            if (count >= DEPENDENCY_ENRICH_CAP) {
                continue;
            }
            count++;
            AgentPackageWrappers.DependencyRef ref = new AgentPackageWrappers.DependencyRef();
            ref.subscriberPackageVersionId = dep.subscriberPackageVersionId;
            // Names resolve only when the dependency is a package in this DevHub.
            // Third-party dependencies stay unresolved — expected, not an error.
            ObjectWrappers.PackageVersionWrapper depVersion = findVersion(dep.subscriberPackageVersionId);
            if (depVersion != null) {
                ref.packageName = depVersion.name;
                ref.versionNumber = formatVersion(depVersion);
            }
            insight.dependencies.add(ref);
        }
    }

    private static String assessReadiness(AgentPackageWrappers.PackageVersionInsight insight) {
        if (insight.isSecurityReviewed == false) {
            return 'not-reviewed';
        }
        if (insight.codeCoveragePercent >= 0 && insight.codeCoveragePercent < COVERAGE_GATE) {
            return 'coverage-gap';
        }
        if (insight.isReleased == false) {
            return 'beta';
        }
        if (insight.isSecurityReviewed == true && insight.codeCoveragePercent >= COVERAGE_GATE && insight.isReleased == true) {
            return 'ready';
        }
        return 'unknown';
    }

    private static String buildSummary(AgentPackageWrappers.PackageVersionInsight insight) {
        String versionLabel = String.isBlank(insight.versionNumber) ? insight.subscriberPackageVersionId : insight.versionNumber;
        return 'Version ' + versionLabel
            + ' — coverage ' + insight.codeCoverageLabel
            + ', security review ' + insight.securityReviewLabel
            + ', ' + insight.dependencyCount + ' ' + (insight.dependencyCount == 1 ? 'dependency' : 'dependencies')
            + ' (' + insight.promotionReadinessTag + ').';
    }

    private static ObjectWrappers.PackageVersionWrapper findVersion(String versionId) {
        if (mockVersions != null) {
            for (ObjectWrappers.PackageVersionWrapper mockVersion : mockVersions) {
                if (versionId.equals(mockVersion.subscriberPackageVersionId)) {
                    return mockVersion;
                }
            }
            return null;
        }
        ObjectWrappers.FilterWrapper filter = new ObjectWrappers.FilterWrapper();
        filter.fieldName = 'SubscriberPackageVersionId';
        filter.value = versionId;
        filter.dataType = 'STRING';
        List<ObjectWrappers.PackageVersionWrapper> rows = Package2Interface.getPackage2Versions(
            new List<ObjectWrappers.FilterWrapper>{ filter },
            null, null, null, null,
            'versionNumber', 'DESC',
            '1', '0'
        );
        return (rows == null || rows.isEmpty()) ? null : rows[0];
    }

    private static String formatVersion(ObjectWrappers.PackageVersionWrapper w) {
        if (w == null || w.majorVersion == null || w.minorVersion == null || w.patchVersion == null) {
            return null;
        }
        return w.majorVersion + '.' + w.minorVersion + '.' + w.patchVersion;
    }
}
