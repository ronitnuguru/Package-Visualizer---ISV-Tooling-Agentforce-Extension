/**
 * Agent action: subscriber fleet analytics. Breaks the subscriber fleet down by a chosen
 * dimension (OrgType / OrgStatus / InstanceName) and summarizes version drift across the fleet.
 *
 * IMPORTANT: the underlying getSubscriberChartData returns only the TOP 6 buckets, so segmentTotal
 * is the sum of those buckets — not the true fleet total. segmentNote states this; we never present
 * a 6-bucket sum as "all subscribers". Drift uses AgentVersionDrift (releases-behind), de-duplicated
 * by distinct installed version to keep callouts bounded. Reads only.
 */
@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentFleetAnalytics {

    private static final Integer DRIFT_SUBSCRIBER_SCAN_CAP = 200;
    private static final Set<String> ALLOWED_GROUP_FIELDS = new Set<String>{
        'OrgType', 'OrgStatus', 'InstanceName'
    };

    // Test seams: inject buckets (never fake AggregateResult) and subscribers for drift.
    @TestVisible
    private static List<AgentFleetWrappers.FleetBucket> mockBuckets;
    @TestVisible
    private static List<ObjectWrappers.PackageSubscriberWrapper> mockSubscribers;

    @InvocableMethod(
        label='Get Subscriber Fleet Analytics'
        description='Breaks the subscriber fleet down by org type, org status, or instance, and summarizes how many subscriber orgs are current vs N released versions behind.'
        category='ISV Agent'
        callout=true
    )
    global static List<FleetResponse> getAnalytics(List<FleetRequest> requests) {
        List<FleetResponse> responses = new List<FleetResponse>();
        for (FleetRequest req : requests) {
            AgentFleetWrappers.FleetAnalytics analytics = resolve(req);
            FleetResponse resp = new FleetResponse();
            resp.result = analytics;
            resp.resultJson = JSON.serialize(analytics, true);
            responses.add(resp);
        }
        return responses;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class FleetRequest {
        @InvocableVariable(
            label='Group By Field'
            description='Dimension to break the fleet down by: OrgType, OrgStatus, or InstanceName. Defaults to OrgType.'
        )
        global String groupByField;

        @InvocableVariable(
            label='Metadata Package Id'
            description='Optional 033-prefixed package Id to scope the fleet to a single package. Leave blank for all subscribers.'
        )
        global String metadataPackageId;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class FleetResponse {
        @InvocableVariable(
            label='Fleet Analytics'
            description='Structured fleet breakdown + drift summary for in-app rendering.'
        )
        global AgentFleetWrappers.FleetAnalytics result;

        @InvocableVariable(
            label='Fleet Analytics JSON'
            description='JSON serialization of the analytics. Feed this into the Slack prompt template.'
        )
        global String resultJson;
    }

    private static AgentFleetWrappers.FleetAnalytics resolve(FleetRequest req) {
        AgentFleetWrappers.FleetAnalytics analytics = new AgentFleetWrappers.FleetAnalytics();
        analytics.buckets = new List<AgentFleetWrappers.FleetBucket>();
        analytics.segmentTotal = 0;
        analytics.driftCurrent = 0;
        analytics.driftReleasesBehind1to2 = 0;
        analytics.driftReleasesBehind3plus = 0;

        String groupBy = (req == null || String.isBlank(req.groupByField)) ? 'OrgType' : req.groupByField.trim();
        if (!ALLOWED_GROUP_FIELDS.contains(groupBy)) {
            analytics.errorMessage = 'I can only break the fleet down by OrgType, OrgStatus, or InstanceName.';
            analytics.groupedBy = groupBy;
            return analytics;
        }
        analytics.groupedBy = groupBy;

        String packageId = (req == null) ? null : req.metadataPackageId;
        List<ObjectWrappers.FilterWrapper> filters = buildFilters(packageId);

        try {
            buildBuckets(analytics, filters, groupBy);
            buildDrift(analytics, filters);
        } catch (Exception e) {
            analytics.errorMessage = 'Could not load fleet analytics: ' + e.getMessage();
            return analytics;
        }

        analytics.headline = buildHeadline(analytics);
        return analytics;
    }

    private static void buildBuckets(
        AgentFleetWrappers.FleetAnalytics analytics,
        List<ObjectWrappers.FilterWrapper> filters,
        String groupBy
    ) {
        List<AgentFleetWrappers.FleetBucket> buckets = (mockBuckets != null)
            ? mockBuckets
            : toBuckets(Package2Interface.getSubscriberChartData(filters, groupBy), groupBy);

        Integer segmentTotal = 0;
        for (AgentFleetWrappers.FleetBucket bucket : buckets) {
            segmentTotal += (bucket.count == null ? 0 : bucket.count);
        }
        for (AgentFleetWrappers.FleetBucket bucket : buckets) {
            Integer count = (bucket.count == null) ? 0 : bucket.count;
            if (segmentTotal == 0) {
                bucket.percentOfSegments = 0;
            } else {
                Decimal pct = (Decimal.valueOf(count) / segmentTotal * 100).setScale(1);
                bucket.percentOfSegments = pct.doubleValue();
            }
        }
        analytics.buckets = buckets;
        analytics.segmentTotal = segmentTotal;
        analytics.segmentNote = buckets.size() >= 6
            ? 'Top 6 ' + groupBy + ' segments by subscriber count'
            : 'All ' + groupBy + ' segments';
    }

    private static List<AgentFleetWrappers.FleetBucket> toBuckets(List<AggregateResult> rows, String groupBy) {
        List<AgentFleetWrappers.FleetBucket> buckets = new List<AgentFleetWrappers.FleetBucket>();
        if (rows == null) {
            return buckets;
        }
        for (AggregateResult row : rows) {
            AgentFleetWrappers.FleetBucket bucket = new AgentFleetWrappers.FleetBucket();
            Object label = row.get(groupBy);
            bucket.label = (label == null) ? 'Unknown' : String.valueOf(label);
            bucket.count = (Integer) row.get('expr0');
            buckets.add(bucket);
        }
        return buckets;
    }

    private static void buildDrift(
        AgentFleetWrappers.FleetAnalytics analytics,
        List<ObjectWrappers.FilterWrapper> filters
    ) {
        List<ObjectWrappers.PackageSubscriberWrapper> subscribers = (mockSubscribers != null)
            ? mockSubscribers
            : Package2Interface.get2GPPackageSubscriberList(
                filters, 'SystemModstamp', 'DESC', String.valueOf(DRIFT_SUBSCRIBER_SCAN_CAP), '0'
              );
        if (subscribers == null || subscribers.isEmpty()) {
            return;
        }

        // Cache releases-behind per distinct installed version to bound callouts.
        Map<String, Integer> behindByVersionId = new Map<String, Integer>();
        for (ObjectWrappers.PackageSubscriberWrapper subscriber : subscribers) {
            String installedId = subscriber.metadataPackageVersionId;
            if (String.isBlank(installedId)) {
                continue;
            }
            if (!behindByVersionId.containsKey(installedId)) {
                behindByVersionId.put(installedId, AgentVersionDrift.releasesBehind(installedId));
            }
            String tag = AgentVersionDrift.driftTag(behindByVersionId.get(installedId));
            if (tag == 'current') {
                analytics.driftCurrent++;
            } else if (tag == 'minor-behind') {
                analytics.driftReleasesBehind1to2++;
            } else {
                analytics.driftReleasesBehind3plus++;
            }
        }
    }

    private static List<ObjectWrappers.FilterWrapper> buildFilters(String packageId) {
        List<ObjectWrappers.FilterWrapper> filters = new List<ObjectWrappers.FilterWrapper>();
        if (String.isNotBlank(packageId)) {
            ObjectWrappers.FilterWrapper filter = new ObjectWrappers.FilterWrapper();
            filter.fieldName = 'MetadataPackageId';
            filter.value = packageId.trim();
            filter.dataType = 'STRING';
            filters.add(filter);
        }
        return filters;
    }

    private static String buildHeadline(AgentFleetWrappers.FleetAnalytics analytics) {
        Integer scanned = analytics.driftCurrent + analytics.driftReleasesBehind1to2 + analytics.driftReleasesBehind3plus;
        return scanned + ' subscriber ' + (scanned == 1 ? 'org' : 'orgs') + ' scanned for drift: '
            + analytics.driftCurrent + ' current, '
            + analytics.driftReleasesBehind1to2 + ' 1-2 releases behind, '
            + analytics.driftReleasesBehind3plus + ' 3+ releases behind.';
    }
}
