/**
 * Agent action: push-upgrade EXECUTE (confirmation-gated WRITE). Schedules a push upgrade of the
 * explicit targetOrgKeys (carried from AgentPushOpsPlan) to the target version.
 *
 * The Apex-level `confirmed == true` guard is the LOAD-BEARING gate: it is the only confirmation
 * that ships inside the managed 2GP package and survives even if a subscriber re-wires the agent.
 * The agent-script require_user_confirmation + conversational "reply yes" are additional layers.
 * Security review is RE-VALIDATED here at write time, and the AuraHandledException that
 * createPushRequest throws on a non-reviewed version (or any non-201) is caught and mapped to
 * errorMessage so the agent never surfaces a raw exception.
 */
@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentPushOpsExecute {

    @TestVisible
    private static Boolean mockTargetIsSecurityReviewed;
    @TestVisible
    private static String mockPushRequestId;
    @TestVisible
    private static List<ObjectWrappers.PackageVersionWrapper> mockVersions;

    @InvocableMethod(
        label='Execute Push Upgrade'
        description='Schedules a push upgrade for an explicit set of subscriber OrgKeys to a target version. Requires confirmed=true; does nothing without explicit confirmation.'
        category='ISV Agent'
        callout=true
    )
    global static List<ExecuteResponse> execute(List<ExecuteRequest> requests) {
        List<ExecuteResponse> responses = new List<ExecuteResponse>();
        for (ExecuteRequest req : requests) {
            AgentPushWrappers.PushScheduleResult result = run(req);
            ExecuteResponse resp = new ExecuteResponse();
            resp.result = result;
            resp.resultJson = JSON.serialize(result, true);
            responses.add(resp);
        }
        return responses;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class ExecuteRequest {
        @InvocableVariable(
            label='Confirmed'
            description='Must be true. Set only after the user has explicitly confirmed the push upgrade. If false or absent, no upgrade is scheduled.'
            required=true
        )
        global Boolean confirmed;

        @InvocableVariable(
            label='Target Version Id'
            description='SubscriberPackageVersion Id (04t) to upgrade subscribers TO.'
            required=true
        )
        global String targetVersionId;

        @InvocableVariable(
            label='Target Org Keys'
            description='Explicit subscriber OrgKeys to upgrade, taken from the confirmed push plan.'
            required=true
        )
        global List<String> targetOrgKeys;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class ExecuteResponse {
        @InvocableVariable(
            label='Push Schedule Result'
            description='Structured push schedule outcome for in-app rendering.'
        )
        global AgentPushWrappers.PushScheduleResult result;

        @InvocableVariable(
            label='Push Schedule Result JSON'
            description='JSON serialization of the result. Feed this into the Slack prompt template.'
        )
        global String resultJson;
    }

    private static AgentPushWrappers.PushScheduleResult run(ExecuteRequest req) {
        AgentPushWrappers.PushScheduleResult result = new AgentPushWrappers.PushScheduleResult();
        result.success = false;
        result.jobsRequested = 0;

        // LOAD-BEARING GATE: never write without explicit confirmation.
        if (req == null || req.confirmed != true) {
            result.errorMessage = 'Push upgrade not scheduled — explicit confirmation is required before any subscriber is upgraded.';
            return result;
        }

        String targetId = (req.targetVersionId == null) ? '' : req.targetVersionId.trim();
        result.targetVersionId = targetId;
        if (String.isBlank(targetId) || !Pattern.matches('^04t[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$', targetId)) {
            result.errorMessage = 'A valid target version Id (starts with 04t, 15 or 18 chars) is required.';
            return result;
        }

        List<String> orgKeys = sanitizeOrgKeys(req.targetOrgKeys);
        if (orgKeys.isEmpty()) {
            result.errorMessage = 'No valid subscriber OrgKeys were provided to upgrade.';
            return result;
        }

        ObjectWrappers.PackageVersionWrapper target = findVersion(targetId);
        if (target != null) {
            result.targetVersionNumber = formatVersion(target);
        }

        // RE-VALIDATE the security-review gate at write time (state can change after the plan).
        Boolean reviewed = (mockTargetIsSecurityReviewed != null)
            ? mockTargetIsSecurityReviewed
            : Package2Interface.getIsSecurityReviewed(targetId);
        if (reviewed != true) {
            result.errorMessage = 'The target version has not passed the AppExchange security review, so it cannot be pushed.';
            return result;
        }

        try {
            String pushRequestId = (mockPushRequestId != null)
                ? mockPushRequestId
                : PushUpgradesInterface.createPushRequest(targetId, null);
            if (mockPushRequestId == null) {
                PushUpgradesInterface.createPushJobs(pushRequestId, orgKeys);
            }
            result.pushRequestId = pushRequestId;
            result.jobsRequested = orgKeys.size();
            result.success = true;
        } catch (Exception e) {
            // createPushRequest/createPushJobs throw AuraHandledException on failure — surface gracefully.
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    private static List<String> sanitizeOrgKeys(List<String> rawKeys) {
        List<String> orgKeys = new List<String>();
        if (rawKeys == null) {
            return orgKeys;
        }
        Set<String> seen = new Set<String>();
        for (String rawKey : rawKeys) {
            if (rawKey == null) {
                continue;
            }
            String key = rawKey.trim();
            if (Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', key) && !seen.contains(key)) {
                seen.add(key);
                orgKeys.add(key);
            }
        }
        return orgKeys;
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
