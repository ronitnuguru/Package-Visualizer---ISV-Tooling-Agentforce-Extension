/**
 * Channel-agnostic DTOs for subscriber fleet analytics agent actions.
 * NOTE: the underlying Package2Interface.getSubscriberChartData hard-caps results at the
 * TOP 6 buckets (ORDER BY Count(Id) DESC LIMIT 6), so segmentTotal is the sum of those
 * buckets only — NOT the true fleet total. segmentNote makes that explicit.
 * Drift is expressed as RELEASES behind (index in the newest-first released list),
 * never as semantic major-version deltas.
 */
@JsonAccess(serializable='always' deserializable='always')
global class AgentFleetWrappers {

    @JsonAccess(serializable='always' deserializable='always')
    global class FleetBucket {
        @InvocableVariable
        global String label;
        @InvocableVariable
        global Integer count;
        @InvocableVariable
        global Double percentOfSegments; // share of segmentTotal, not of the whole fleet
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class FleetAnalytics {
        @InvocableVariable
        global String groupedBy; // OrgType | OrgStatus | InstanceName
        @InvocableVariable
        global Integer segmentTotal; // sum of the (up to 6) returned buckets
        @InvocableVariable
        global String segmentNote; // e.g. "Top 6 segments by subscriber count"
        @InvocableVariable
        global List<FleetBucket> buckets;
        @InvocableVariable
        global Integer driftCurrent;
        @InvocableVariable
        global Integer driftReleasesBehind1to2;
        @InvocableVariable
        global Integer driftReleasesBehind3plus;
        @InvocableVariable
        global String headline;
        @InvocableVariable
        global String errorMessage;
    }
}
