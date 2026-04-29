@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentSubscriberLookup {

    @TestVisible private static HttpCalloutMock httpMock;

    @InvocableMethod(
        label='Lookup Subscriber by OrgKey'
        description='Resolves a subscriber OrgKey to installed version, last upgrade, org status, and instance health. Supports 6+ character prefix for disambiguation.'
        category='ISV Agent'
        callout=true
    )
    global static List<LookupResponse> lookup(List<LookupRequest> requests) {
        List<LookupResponse> responses = new List<LookupResponse>();
        for (LookupRequest req : requests) {
            AgentSubscriberWrappers.LookupResult r = resolve(req == null ? null : req.orgKey);
            LookupResponse resp = new LookupResponse();
            resp.resultJson = JSON.serialize(r, true);
            responses.add(resp);
        }
        return responses;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class LookupRequest {
        @InvocableVariable(
            label='Org Key'
            description='15 or 18 character Salesforce organization ID, or a 6+ character prefix.'
            required=true
        )
        global String orgKey;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class LookupResponse {
        @InvocableVariable(
            label='Lookup Result JSON'
            description='JSON serialization of the lookup result. Feed this into the Slack prompt template.'
        )
        global String resultJson;
    }

    private static AgentSubscriberWrappers.LookupResult resolve(String rawKey) {
        AgentSubscriberWrappers.LookupResult r = new AgentSubscriberWrappers.LookupResult();
        String key = (rawKey == null) ? '' : rawKey.trim();

        if (String.isBlank(key)) {
            r.errorMessage = 'I need an OrgKey to look up. OrgKeys are 15 or 18 characters, e.g. 00D5g000001abcDE.';
            return r;
        }

        if (Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', key)) {
            AgentSubscriberWrappers.SubscriberSummary match = exactMatch(key);
            if (match == null) {
                r.errorMessage = 'No subscriber found for OrgKey ' + key + '.';
            } else {
                r.subscriber = match;
            }
            return r;
        }

        if (key.length() >= 6 && Pattern.matches('^[a-zA-Z0-9]+$', key)) {
            List<AgentSubscriberWrappers.SubscriberMatch> matches = prefixSearch(key);
            if (matches.isEmpty()) {
                r.errorMessage = 'No subscribers found starting with "' + key + '". Double-check the OrgKey.';
            } else {
                r.disambiguation = matches;
            }
            return r;
        }

        r.errorMessage = 'That OrgKey looks incomplete — OrgKeys are 15 or 18 alphanumeric characters. Try again with the full key.';
        return r;
    }

    private static AgentSubscriberWrappers.SubscriberSummary exactMatch(String orgKey) {
        // Reuse the base-package pattern: FilterWrapper → Package2Interface.get2GPPackageSubscriberList.
        // Same path the packageSubscribersView LWC uses. FLS + stripInaccessible handled upstream.
        List<ObjectWrappers.PackageSubscriberWrapper> rows = queryPackageSubscribers(orgKey, 'STRING', '1');
        if (rows == null || rows.isEmpty()) return null;

        ObjectWrappers.PackageSubscriberWrapper row = rows[0];
        AgentSubscriberWrappers.SubscriberSummary s = new AgentSubscriberWrappers.SubscriberSummary();
        s.orgKey          = row.orgKey;
        s.orgName         = row.orgName;
        s.orgType         = row.orgType;
        s.orgStatus       = row.orgStatus;
        s.instanceName    = row.instanceName;
        s.parentOrgKey    = row.parentOrg;
        s.lastUpgradeDate = (row.SystemModstamp == null) ? null : row.SystemModstamp.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'+0000\'');

        VersionInfo v = resolveVersionInfo(row.metadataPackageVersionId);
        s.installedVersion    = v.installedVersion;
        s.latestVersion       = v.latestVersion;
        s.versionsBehind      = v.versionsBehind;
        s.versionsBehindLabel = v.versionsBehindLabel;
        s.versionHealthTag    = healthTag(v.versionsBehind);

        s.instanceStatus = fetchInstanceStatus(s.instanceName);
        s.deepLinkUrl    = buildDeepLink(s.orgKey);

        return s;
    }

    private static List<AgentSubscriberWrappers.SubscriberMatch> prefixSearch(String prefix) {
        List<AgentSubscriberWrappers.SubscriberMatch> results = new List<AgentSubscriberWrappers.SubscriberMatch>();
        // SEARCH dataType in Package2Interface.getWhereClause uses LIKE '%value%' — contains-match,
        // which is actually more forgiving than a strict prefix and still useful for disambiguation.
        List<ObjectWrappers.PackageSubscriberWrapper> rows = queryPackageSubscribers(prefix, 'SEARCH', '5');
        if (rows == null) return results;

        for (ObjectWrappers.PackageSubscriberWrapper row : rows) {
            AgentSubscriberWrappers.SubscriberMatch m = new AgentSubscriberWrappers.SubscriberMatch();
            m.orgKey        = row.orgKey;
            m.orgName       = row.orgName;
            m.orgType       = row.orgType;
            m.orgStatus     = row.orgStatus;
            m.parentOrgKey  = row.parentOrg;
            VersionInfo v = resolveVersionInfo(row.metadataPackageVersionId);
            m.installedVersion = v.installedVersion;
            results.add(m);
        }
        return results;
    }

    private static List<ObjectWrappers.PackageSubscriberWrapper> queryPackageSubscribers(String value, String dataType, String lim) {
        ObjectWrappers.FilterWrapper fw = new ObjectWrappers.FilterWrapper();
        fw.fieldName = 'OrgKey';
        fw.value     = value;
        fw.dataType  = dataType;
        return Package2Interface.get2GPPackageSubscriberList(
            new List<ObjectWrappers.FilterWrapper>{ fw },
            'SystemModstamp',
            'DESC',
            lim,
            '0'
        );
    }

    private class VersionInfo {
        String installedVersion;
        String latestVersion;
        Integer versionsBehind;
        String versionsBehindLabel;
    }

    private static VersionInfo resolveVersionInfo(String installedPkgVersionId) {
        VersionInfo v = new VersionInfo();
        v.versionsBehind = 0;
        if (String.isBlank(installedPkgVersionId)) return v;

        // Look up the installed version record to get MAJOR.MINOR.PATCH + its Package2Id.
        ObjectWrappers.FilterWrapper fw = new ObjectWrappers.FilterWrapper();
        fw.fieldName = 'SubscriberPackageVersionId';
        fw.value     = installedPkgVersionId;
        fw.dataType  = 'STRING';
        List<ObjectWrappers.PackageVersionWrapper> installedRows = Package2Interface.getPackage2Versions(
            new List<ObjectWrappers.FilterWrapper>{ fw },
            null, null, null, null,
            'versionNumber',
            'DESC',
            '1',
            '0'
        );
        if (installedRows == null || installedRows.isEmpty()) return v;

        ObjectWrappers.PackageVersionWrapper installed = installedRows[0];
        v.installedVersion = formatVersion(installed);
        v.versionsBehindLabel = 'current';
        String package2Id  = installed.package2Id;
        if (String.isBlank(package2Id)) return v;

        // Latest versions for this Package2, sorted by CreatedDate DESC. Base-package method
        // returns just the SubscriberPackageVersionId strings — perfect for a "versions behind" count.
        List<String> latestIds = Package2Interface.getLatestPackageVersionsList(package2Id, '50');
        if (latestIds == null || latestIds.isEmpty()) return v;

        // Index 0 is the newest. Fetch the full record for the latest to get its version string.
        ObjectWrappers.FilterWrapper fwLatest = new ObjectWrappers.FilterWrapper();
        fwLatest.fieldName = 'SubscriberPackageVersionId';
        fwLatest.value     = latestIds[0];
        fwLatest.dataType  = 'STRING';
        List<ObjectWrappers.PackageVersionWrapper> latestRow = Package2Interface.getPackage2Versions(
            new List<ObjectWrappers.FilterWrapper>{ fwLatest },
            null, null, null, null,
            'versionNumber',
            'DESC',
            '1',
            '0'
        );
        ObjectWrappers.PackageVersionWrapper latest = null;
        if (latestRow != null && !latestRow.isEmpty()) {
            latest = latestRow[0];
            v.latestVersion = formatVersion(latest);
        }

        // Count how many released versions are newer than the installed one.
        Integer behind = 0;
        Boolean found = false;
        for (String vid : latestIds) {
            if (installedPkgVersionId.equals(vid)) { found = true; break; }
            behind++;
        }
        v.versionsBehind = found ? behind : latestIds.size();
        v.versionsBehindLabel = buildVersionsBehindLabel(installed, latest, v.versionsBehind);
        return v;
    }

    private static String buildVersionsBehindLabel(ObjectWrappers.PackageVersionWrapper installed,
                                                   ObjectWrappers.PackageVersionWrapper latest,
                                                   Integer versionsBehind) {
        if (versionsBehind == null || versionsBehind <= 0) return 'current';
        if (installed == null || latest == null) return versionsBehind + ' versions behind';
        Integer majorDelta = safeInt(latest.majorVersion) - safeInt(installed.majorVersion);
        Integer minorDelta = safeInt(latest.minorVersion) - safeInt(installed.minorVersion);
        Integer patchDelta = safeInt(latest.patchVersion) - safeInt(installed.patchVersion);
        if (majorDelta > 0) return majorDelta + ' major ' + pluralize('version', majorDelta) + ' behind';
        if (minorDelta > 0) return minorDelta + ' minor ' + pluralize('version', minorDelta) + ' behind';
        if (patchDelta > 0) return patchDelta + ' patch ' + pluralize('version', patchDelta) + ' behind';
        return versionsBehind + ' ' + pluralize('version', versionsBehind) + ' behind';
    }

    private static Integer safeInt(Integer i) { return i == null ? 0 : i; }

    private static String pluralize(String word, Integer count) {
        return (count == 1) ? word : word + 's';
    }

    private static String formatVersion(ObjectWrappers.PackageVersionWrapper w) {
        if (w == null || w.majorVersion == null || w.minorVersion == null || w.patchVersion == null) return null;
        return String.valueOf(w.majorVersion) + '.' + String.valueOf(w.minorVersion) + '.' + String.valueOf(w.patchVersion);
    }

    private static String healthTag(Integer versionsBehind) {
        if (versionsBehind == null || versionsBehind <= 0) return 'current';
        if (versionsBehind <= 2) return 'minor-behind';
        return 'major-behind';
    }

    private static String fetchInstanceStatus(String instanceName) {
        if (String.isBlank(instanceName)) return 'Unknown';
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:pkgviz__Salesforce_Trust/v1/instances/' + EncodingUtil.urlEncode(instanceName, 'UTF-8') + '/status/preview?childProducts=false');
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(10000);
            HttpResponse res = (httpMock != null) ? httpMock.respond(req) : new Http().send(req);
            if (res.getStatusCode() != 200) return 'Unknown';
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Object status = body.get('status');
            if (status == null) return 'Unknown';
            String s = String.valueOf(status);
            if ('OK'.equalsIgnoreCase(s)) return 'Operational';
            if ('MINOR_INCIDENT_CORE'.equalsIgnoreCase(s) || 'MAJOR_INCIDENT_CORE'.equalsIgnoreCase(s)) return 'Major Incident';
            if (s.containsIgnoreCase('DEGRAD')) return 'Degraded';
            if (s.containsIgnoreCase('INCIDENT')) return 'Major Incident';
            return s;
        } catch (Exception e) {
            return 'Unknown';
        }
    }

    private static String buildDeepLink(String orgKey) {
        return URL.getOrgDomainUrl().toExternalForm() + '/lightning/n/pkgviz__X2GP_Visualizer?orgKey=' + orgKey;
    }

}
