/**
 * Agent action: push-upgrade PLAN (dry run, reads only). Given a target SubscriberPackageVersion
 * Id and an optional cohort of subscriber OrgKeys, returns a PushPlan that surfaces the target's
 * security-review status up front, the explicit eligible OrgKey list (those not already current),
 * counts, and estimated chunk count. NO writes happen here — the user reviews the plan and confirms
 * before AgentPushOpsExecute runs. There is deliberately no cryptographic cohort token: the plan
 * returns explicit keys that Execute re-validates at write time.
 */
@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentPushOpsPlan {

    private static final Integer CHUNK_SIZE = 200;
    private static final Integer ELIGIBLE_CAP = 200;

    @TestVisible
    private static Boolean mockTargetIsSecurityReviewed;
    @TestVisible
    private static List<ObjectWrappers.PackageVersionWrapper> mockVersions;
    @TestVisible
    private static List<ObjectWrappers.PackageSubscriberWrapper> mockSubscribers;

    @InvocableMethod(
        label='Plan Push Upgrade'
        description='Dry run for a push upgrade. Given a target version Id and optional subscriber OrgKeys, returns the security-review gate, the eligible cohort, and counts. No upgrade is scheduled.'
        category='ISV Agent'
        callout=true
    )
    global static List<PlanResponse> plan(List<PlanRequest> requests) {
        List<PlanResponse> responses = new List<PlanResponse>();
        for (PlanRequest req : requests) {
            AgentPushWrappers.PushPlan pushPlan = build(req);
            PlanResponse resp = new PlanResponse();
            resp.result = pushPlan;
            resp.resultJson = JSON.serialize(pushPlan, true);
            responses.add(resp);
        }
        return responses;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class PlanRequest {
        @InvocableVariable(
            label='Target Version Id'
            description='SubscriberPackageVersion Id (04t) to upgrade subscribers TO. 15 or 18 characters.'
            required=true
        )
        global String targetVersionId;

        @InvocableVariable(
            label='Subscriber Org Keys'
            description='Optional list of subscriber OrgKeys to evaluate. Leave empty to evaluate the recent subscriber fleet for the target package.'
        )
        global List<String> orgKeys;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class PlanResponse {
        @InvocableVariable(
            label='Push Plan'
            description='Structured push-upgrade dry-run plan for in-app rendering.'
        )
        global AgentPushWrappers.PushPlan result;

        @InvocableVariable(
            label='Push Plan JSON'
            description='JSON serialization of the plan. Feed this into the Slack prompt template.'
        )
        global String resultJson;
    }

    private static AgentPushWrappers.PushPlan build(PlanRequest req) {
        AgentPushWrappers.PushPlan pushPlan = new AgentPushWrappers.PushPlan();
        pushPlan.eligibleOrgKeys = new List<String>();
        pushPlan.eligibleCount = 0;
        pushPlan.alreadyCurrentCount = 0;
        pushPlan.estimatedChunks = 0;
        pushPlan.blocked = true;

        String targetId = (req == null || req.targetVersionId == null) ? '' : req.targetVersionId.trim();
        pushPlan.targetVersionId = targetId;

        if (String.isBlank(targetId) || !Pattern.matches('^04t[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$', targetId)) {
            pushPlan.errorMessage = 'A valid target version Id (starts with 04t, 15 or 18 chars) is required.';
            pushPlan.summaryLine = pushPlan.errorMessage;
            return pushPlan;
        }

        ObjectWrappers.PackageVersionWrapper target = findVersion(targetId);
        if (target != null) {
            pushPlan.targetVersionNumber = formatVersion(target);
        }

        Boolean reviewed = (mockTargetIsSecurityReviewed != null)
            ? mockTargetIsSecurityReviewed
            : Package2Interface.getIsSecurityReviewed(targetId);
        pushPlan.targetIsSecurityReviewed = reviewed;
        if (reviewed != true) {
            pushPlan.errorMessage = 'The target version has not passed the AppExchange security review, so it cannot be pushed to subscribers.';
            pushPlan.summaryLine = pushPlan.errorMessage;
            return pushPlan;
        }

        List<ObjectWrappers.PackageSubscriberWrapper> subscribers = resolveSubscribers(req, target);
        for (ObjectWrappers.PackageSubscriberWrapper subscriber : subscribers) {
            if (targetId.equals(subscriber.metadataPackageVersionId)) {
                pushPlan.alreadyCurrentCount++;
            } else if (pushPlan.eligibleOrgKeys.size() < ELIGIBLE_CAP && String.isNotBlank(subscriber.orgKey)) {
                pushPlan.eligibleOrgKeys.add(subscriber.orgKey);
            }
        }

        pushPlan.eligibleCount = pushPlan.eligibleOrgKeys.size();
        pushPlan.estimatedChunks = (pushPlan.eligibleCount == 0)
            ? 0
            : (Integer) Math.ceil((Double) pushPlan.eligibleCount / CHUNK_SIZE);
        pushPlan.blocked = (pushPlan.eligibleCount == 0);
        pushPlan.summaryLine = buildSummary(pushPlan);
        return pushPlan;
    }

    private static List<ObjectWrappers.PackageSubscriberWrapper> resolveSubscribers(
        PlanRequest req,
        ObjectWrappers.PackageVersionWrapper target
    ) {
        if (mockSubscribers != null) {
            return mockSubscribers;
        }
        List<ObjectWrappers.PackageSubscriberWrapper> subscribers = new List<ObjectWrappers.PackageSubscriberWrapper>();
        if (req != null && req.orgKeys != null && !req.orgKeys.isEmpty()) {
            // Evaluate the explicit cohort the user named via a LIST (IN-clause) filter.
            ObjectWrappers.FilterWrapper filter = new ObjectWrappers.FilterWrapper();
            filter.fieldName = 'OrgKey';
            filter.value = String.join(req.orgKeys, '~');
            filter.dataType = 'LIST';
            subscribers = Package2Interface.get2GPPackageSubscriberList(
                new List<ObjectWrappers.FilterWrapper>{ filter }, 'SystemModstamp', 'DESC', '200', '0'
            );
        } else if (target != null && String.isNotBlank(target.package2Id)) {
            // No explicit cohort — evaluate the recent fleet for the target's package.
            // metadataPackageId on PackageSubscriber is the 033 SubscriberPackageId, which we
            // do not have here; fall back to the recent subscriber list (the user can scope later).
            subscribers = Package2Interface.get2GPPackageSubscriberList(
                new List<ObjectWrappers.FilterWrapper>(), 'SystemModstamp', 'DESC', '200', '0'
            );
        }
        return (subscribers == null) ? new List<ObjectWrappers.PackageSubscriberWrapper>() : subscribers;
    }

    private static String buildSummary(AgentPushWrappers.PushPlan pushPlan) {
        String versionLabel = String.isBlank(pushPlan.targetVersionNumber) ? pushPlan.targetVersionId : pushPlan.targetVersionNumber;
        if (pushPlan.eligibleCount == 0) {
            return 'No subscribers are eligible to upgrade to ' + versionLabel + ' (all already current or none matched).';
        }
        return pushPlan.eligibleCount + ' subscriber ' + (pushPlan.eligibleCount == 1 ? 'org is' : 'orgs are')
            + ' eligible to upgrade to ' + versionLabel + ' across ' + pushPlan.estimatedChunks
            + ' ' + (pushPlan.estimatedChunks == 1 ? 'batch' : 'batches') + '. '
            + pushPlan.alreadyCurrentCount + ' already current. Confirm to schedule.';
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
