@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentPushUpgrade {

    @InvocableMethod(
        label='Push Upgrade to Latest Version'
        description='Schedules an immediate push upgrade of the subscriber identified by OrgKey to the latest released package version.'
        category='ISV Agent'
        callout=true
    )
    global static List<PushResponse> push(List<PushRequest> requests) {
        List<PushResponse> responses = new List<PushResponse>();
        for (PushRequest req : requests) {
            AgentSubscriberWrappers.PushResult r = execute(req == null ? null : req.orgKey);
            PushResponse resp = new PushResponse();
            resp.resultJson = JSON.serialize(r, true);
            responses.add(resp);
        }
        return responses;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class PushRequest {
        @InvocableVariable(
            label='Org Key'
            description='15 or 18 character Salesforce OrgKey of the subscriber to upgrade.'
            required=true
        )
        global String orgKey;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class PushResponse {
        @InvocableVariable(
            label='Push Result JSON'
            description='JSON serialization of the PushResult. Feed this into the push upgrade prompt template.'
        )
        global String resultJson;
    }

    private static AgentSubscriberWrappers.PushResult execute(String rawKey) {
        AgentSubscriberWrappers.PushResult r = new AgentSubscriberWrappers.PushResult();
        r.success = false;
        String key = (rawKey == null) ? '' : rawKey.trim();
        r.orgKey = key;

        if (String.isBlank(key) || !Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', key)) {
            r.errorMessage = 'A full 15 or 18 character OrgKey is required to schedule a push upgrade.';
            return r;
        }

        ObjectWrappers.PackageSubscriberWrapper subscriber = findSubscriber(key);
        if (subscriber == null) {
            r.errorMessage = 'No subscriber found for OrgKey ' + key + '.';
            return r;
        }
        r.orgName = subscriber.orgName;

        if (String.isBlank(subscriber.metadataPackageVersionId)) {
            r.errorMessage = 'Subscriber ' + key + ' has no installed package version on record.';
            return r;
        }

        ObjectWrappers.PackageVersionWrapper installed = findVersion(subscriber.metadataPackageVersionId);
        if (installed == null || String.isBlank(installed.package2Id)) {
            r.errorMessage = 'Could not resolve the installed package for subscriber ' + key + '.';
            return r;
        }
        r.fromVersion = formatVersion(installed);

        List<String> latestIds = Package2Interface.getLatestPackageVersionsList(installed.package2Id, '1');
        if (latestIds == null || latestIds.isEmpty()) {
            r.errorMessage = 'No released versions are available for this package.';
            return r;
        }
        String targetVersionId = latestIds[0];

        if (targetVersionId.equals(subscriber.metadataPackageVersionId)) {
            r.targetVersion = r.fromVersion;
            r.errorMessage = 'Already on the latest version (' + r.fromVersion + '). No push upgrade scheduled.';
            return r;
        }

        ObjectWrappers.PackageVersionWrapper target = findVersion(targetVersionId);
        if (target != null) r.targetVersion = formatVersion(target);

        try {
            String pushRequestId = PushUpgradesInterface.createPushRequest(targetVersionId, null);
            PushUpgradesInterface.createPushJobs(pushRequestId, new List<String>{ key });
            r.pushRequestId = pushRequestId;
            r.success = true;
        } catch (Exception e) {
            r.errorMessage = e.getMessage();
        }
        return r;
    }

    private static ObjectWrappers.PackageSubscriberWrapper findSubscriber(String orgKey) {
        ObjectWrappers.FilterWrapper fw = new ObjectWrappers.FilterWrapper();
        fw.fieldName = 'OrgKey';
        fw.value     = orgKey;
        fw.dataType  = 'STRING';
        List<ObjectWrappers.PackageSubscriberWrapper> rows = Package2Interface.get2GPPackageSubscriberList(
            new List<ObjectWrappers.FilterWrapper>{ fw },
            'SystemModstamp', 'DESC', '1', '0'
        );
        return (rows == null || rows.isEmpty()) ? null : rows[0];
    }

    private static ObjectWrappers.PackageVersionWrapper findVersion(String subscriberPackageVersionId) {
        ObjectWrappers.FilterWrapper fw = new ObjectWrappers.FilterWrapper();
        fw.fieldName = 'SubscriberPackageVersionId';
        fw.value     = subscriberPackageVersionId;
        fw.dataType  = 'STRING';
        List<ObjectWrappers.PackageVersionWrapper> rows = Package2Interface.getPackage2Versions(
            new List<ObjectWrappers.FilterWrapper>{ fw },
            null, null, null, null,
            'versionNumber', 'DESC',
            '1', '0'
        );
        return (rows == null || rows.isEmpty()) ? null : rows[0];
    }

    private static String formatVersion(ObjectWrappers.PackageVersionWrapper w) {
        if (w == null || w.majorVersion == null || w.minorVersion == null || w.patchVersion == null) return null;
        return String.valueOf(w.majorVersion) + '.' + String.valueOf(w.minorVersion) + '.' + String.valueOf(w.patchVersion);
    }
}
