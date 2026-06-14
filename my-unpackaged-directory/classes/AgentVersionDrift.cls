/**
 * Shared version-drift logic for the ISV agent actions. "Drift" is the number of RELEASED
 * versions newer than the one a subscriber has installed — i.e. the installed version's index
 * in the newest-first released list (Package2Interface.getLatestPackageVersionsList). This is an
 * index-based "N releases behind" measure, NOT a semantic major-version delta; do not relabel it.
 *
 * Extracted from AgentSubscriberLookup.resolveVersionInfo so subscriber lookup and fleet analytics
 * compute drift identically. @TestVisible mock seams let tests inject without Tooling API callouts.
 */
@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentVersionDrift {

    // releasesBehind == 0 -> current; 1-2 -> minor lag; 3+ -> material lag.
    @TestVisible
    private static final Integer MINOR_BEHIND_THRESHOLD = 2;

    // Test seams: when set, queries are short-circuited (mirrors AgentSubscriberLookup).
    @TestVisible
    private static List<ObjectWrappers.PackageVersionWrapper> mockVersions;
    @TestVisible
    private static List<String> mockLatestVersionIds;

    /**
     * @param installedSubscriberPackageVersionId The 04t the subscriber currently has installed.
     * @return Count of released versions newer than the installed one (0 when current/unknown).
     */
    global static Integer releasesBehind(String installedSubscriberPackageVersionId) {
        if (String.isBlank(installedSubscriberPackageVersionId)) {
            return 0;
        }

        ObjectWrappers.PackageVersionWrapper installed = findVersion(installedSubscriberPackageVersionId);
        if (installed == null || String.isBlank(installed.package2Id)) {
            return 0;
        }

        List<String> releasedNewestFirst = (mockLatestVersionIds != null)
            ? mockLatestVersionIds
            : Package2Interface.getLatestPackageVersionsList(installed.package2Id, '50');
        if (releasedNewestFirst == null || releasedNewestFirst.isEmpty()) {
            return 0;
        }

        Integer behind = 0;
        for (String releasedId : releasedNewestFirst) {
            if (installedSubscriberPackageVersionId.equals(releasedId)) {
                return behind;
            }
            behind++;
        }
        // Installed version not in the released list at all — treat as fully behind.
        return releasedNewestFirst.size();
    }

    /**
     * @param releasesBehind Output of releasesBehind().
     * @return Bucket tag: current | minor-behind | major-behind.
     */
    global static String driftTag(Integer releasesBehind) {
        if (releasesBehind == null || releasesBehind <= 0) {
            return 'current';
        }
        return (releasesBehind <= MINOR_BEHIND_THRESHOLD) ? 'minor-behind' : 'major-behind';
    }

    private static ObjectWrappers.PackageVersionWrapper findVersion(String subscriberPackageVersionId) {
        if (mockVersions != null) {
            for (ObjectWrappers.PackageVersionWrapper mockVersion : mockVersions) {
                if (subscriberPackageVersionId.equals(mockVersion.subscriberPackageVersionId)) {
                    return mockVersion;
                }
            }
            return mockVersions.isEmpty() ? null : mockVersions[0];
        }
        ObjectWrappers.FilterWrapper filter = new ObjectWrappers.FilterWrapper();
        filter.fieldName = 'SubscriberPackageVersionId';
        filter.value = subscriberPackageVersionId;
        filter.dataType = 'STRING';
        List<ObjectWrappers.PackageVersionWrapper> rows = Package2Interface.getPackage2Versions(
            new List<ObjectWrappers.FilterWrapper>{ filter },
            null, null, null, null,
            'versionNumber', 'DESC',
            '1', '0'
        );
        return (rows == null || rows.isEmpty()) ? null : rows[0];
    }
}
