/**
 * Channel-agnostic DTOs returned by the package & version intelligence agent actions.
 * Every field is global + @InvocableVariable so the same object can render in-app via a
 * Custom Lightning Type (@apexClassType binding) and serialize to JSON for Slack prompt templates.
 * Inner-class names are a packaged API contract once published — additive changes only.
 */
@JsonAccess(serializable='always' deserializable='always')
global class AgentPackageWrappers {

    @JsonAccess(serializable='always' deserializable='always')
    global class PackageVersionInsight {
        @InvocableVariable
        global String subscriberPackageVersionId;
        @InvocableVariable
        global String packageName;
        @InvocableVariable
        global String versionNumber;
        @InvocableVariable
        global Boolean isReleased;
        @InvocableVariable
        global String releaseState;
        @InvocableVariable
        global Integer codeCoveragePercent; // -1 = unknown
        @InvocableVariable
        global String codeCoverageLabel;
        @InvocableVariable
        global Boolean isSecurityReviewed;
        @InvocableVariable
        global String securityReviewLabel;
        @InvocableVariable
        global Integer dependencyCount;
        @InvocableVariable
        global List<DependencyRef> dependencies;
        @InvocableVariable
        global String promotionReadinessTag; // ready | coverage-gap | not-reviewed | beta | unknown
        @InvocableVariable
        global String summaryLine;
        @InvocableVariable
        global String errorMessage;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class DependencyRef {
        @InvocableVariable
        global String subscriberPackageVersionId;
        @InvocableVariable
        global String packageName; // null/"Unknown" when the dependency is not in this DevHub (expected for third-party)
        @InvocableVariable
        global String versionNumber;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class PackageCatalog {
        @InvocableVariable
        global String filterApplied; // normalized: all | managed | unlocked | name:"<term>"
        @InvocableVariable
        global Integer packageCount;
        @InvocableVariable
        global String headline; // e.g. "3 managed packages"
        @InvocableVariable
        global List<PackageSummary> packages;
        @InvocableVariable
        global String errorMessage;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class PackageSummary {
        @InvocableVariable
        global String subscriberPackageId; // 033 — from PackageWrapper.subscriberPackageID
        @InvocableVariable
        global String name;
        @InvocableVariable
        global String containerOptions; // "Managed" | "Unlocked"
        @InvocableVariable
        global String namespacePrefix; // may be null (unlocked w/o namespace)
        @InvocableVariable
        global String description;
    }
}
