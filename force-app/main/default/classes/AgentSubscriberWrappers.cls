@JsonAccess(serializable='always' deserializable='always')
global class AgentSubscriberWrappers {

    @JsonAccess(serializable='always' deserializable='always')
    global class SubscriberSummary {
        global String orgKey;
        global String orgName;
        global String orgType;
        global String orgStatus;
        global String instanceName;
        global String instanceStatus;
        global String installedVersion;
        global String latestVersion;
        global Integer versionsBehind;
        global String versionsBehindLabel;
        global String versionHealthTag;
        global String lastUpgradeDate;
        global String parentOrgKey;
        global String deepLinkUrl;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class SubscriberMatch {
        global String orgKey;
        global String orgName;
        global String orgType;
        global String orgStatus;
        global String installedVersion;
        global String parentOrgKey;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class LookupResult {
        global SubscriberSummary subscriber;
        global List<SubscriberMatch> disambiguation;
        global String errorMessage;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class ProductionGroup {
        global SubscriberMatch production;
        global List<SubscriberMatch> sandboxes;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class SearchResult {
        global String searchTerm;
        global List<ProductionGroup> productions;
        global List<SubscriberMatch> orphanSandboxes;
        global String errorMessage;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class PushResult {
        global Boolean success;
        global String orgKey;
        global String orgName;
        global String fromVersion;
        global String targetVersion;
        global String pushRequestId;
        global String errorMessage;
    }
}
