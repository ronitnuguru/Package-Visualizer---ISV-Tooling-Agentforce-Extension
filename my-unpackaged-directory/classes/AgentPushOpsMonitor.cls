/**
 * Agent action: push-upgrade MONITOR (reads only). Given a PackagePushRequest Id, summarizes the
 * request status and its jobs — succeeded / failed / pending counts — and groups failures by
 * (ErrorType, ErrorTitle) into the top recurring failures with occurrence counts, so the agent can
 * surface root causes instead of a flat error list.
 */
@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentPushOpsMonitor {

    private static final Integer JOB_SCAN_CAP = 2000;
    private static final Integer TOP_FAILURE_CAP = 5;
    private static final Set<String> SUCCESS_STATUSES = new Set<String>{ 'Succeeded', 'SucceededPartial' };
    private static final Set<String> PENDING_STATUSES = new Set<String>{ 'Created', 'Pending', 'InProgress' };

    @TestVisible
    private static List<ObjectWrappers.PackagePushRequestWrapper> mockRequests;
    @TestVisible
    private static List<ObjectWrappers.PackagePushJobWrapper> mockJobs;

    @InvocableMethod(
        label='Monitor Push Upgrade'
        description='Given a PackagePushRequest Id, returns the request status with succeeded/failed/pending job counts and the top recurring failure causes.'
        category='ISV Agent'
        callout=true
    )
    global static List<MonitorResponse> monitor(List<MonitorRequest> requests) {
        List<MonitorResponse> responses = new List<MonitorResponse>();
        for (MonitorRequest req : requests) {
            AgentPushWrappers.PushMonitor pushMonitor = build(req == null ? null : req.pushRequestId);
            MonitorResponse resp = new MonitorResponse();
            resp.result = pushMonitor;
            resp.resultJson = JSON.serialize(pushMonitor, true);
            responses.add(resp);
        }
        return responses;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class MonitorRequest {
        @InvocableVariable(
            label='Push Request Id'
            description='Id of the PackagePushRequest to monitor (starts with 0DV).'
            required=true
        )
        global String pushRequestId;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class MonitorResponse {
        @InvocableVariable(
            label='Push Monitor'
            description='Structured push-request status + failure summary for in-app rendering.'
        )
        global AgentPushWrappers.PushMonitor result;

        @InvocableVariable(
            label='Push Monitor JSON'
            description='JSON serialization of the monitor result. Feed this into the Slack prompt template.'
        )
        global String resultJson;
    }

    private static AgentPushWrappers.PushMonitor build(String rawId) {
        AgentPushWrappers.PushMonitor pushMonitor = new AgentPushWrappers.PushMonitor();
        pushMonitor.topFailures = new List<AgentPushWrappers.JobFailure>();
        pushMonitor.totalJobs = 0;
        pushMonitor.succeededJobs = 0;
        pushMonitor.failedJobs = 0;
        pushMonitor.pendingJobs = 0;

        String requestId = (rawId == null) ? '' : rawId.trim();
        pushMonitor.pushRequestId = requestId;
        if (String.isBlank(requestId)) {
            pushMonitor.errorMessage = 'A PackagePushRequest Id is required to monitor a push upgrade.';
            return pushMonitor;
        }

        try {
            loadRequestStatus(pushMonitor, requestId);
            summarizeJobs(pushMonitor, requestId);
        } catch (Exception e) {
            pushMonitor.errorMessage = 'Could not load push upgrade status: ' + e.getMessage();
        }
        return pushMonitor;
    }

    private static void loadRequestStatus(AgentPushWrappers.PushMonitor pushMonitor, String requestId) {
        List<ObjectWrappers.PackagePushRequestWrapper> requests = (mockRequests != null)
            ? mockRequests
            : PushUpgradesInterface.getPushRequests(idFilter('Id', requestId), 'SystemModstamp', 'DESC', '1', '0');
        if (requests != null && !requests.isEmpty()) {
            pushMonitor.status = requests[0].Status;
        }
    }

    private static void summarizeJobs(AgentPushWrappers.PushMonitor pushMonitor, String requestId) {
        List<ObjectWrappers.PackagePushJobWrapper> jobs = (mockJobs != null)
            ? mockJobs
            : PushUpgradesInterface.getPushJobs(
                idFilter('PackagePushRequestId', requestId), 'SystemModstamp', 'DESC', String.valueOf(JOB_SCAN_CAP), '0'
              );
        if (jobs == null) {
            return;
        }

        Map<String, AgentPushWrappers.JobFailure> failuresByKey = new Map<String, AgentPushWrappers.JobFailure>();
        for (ObjectWrappers.PackagePushJobWrapper job : jobs) {
            pushMonitor.totalJobs++;
            String status = job.Status;
            if (status != null && SUCCESS_STATUSES.contains(status)) {
                pushMonitor.succeededJobs++;
            } else if (status == null || PENDING_STATUSES.contains(status)) {
                pushMonitor.pendingJobs++;
            } else {
                pushMonitor.failedJobs++;
                accumulateFailure(failuresByKey, job);
            }
        }

        List<AgentPushWrappers.JobFailure> sorted = sortByOccurrence(failuresByKey.values());
        for (Integer i = 0; i < sorted.size() && i < TOP_FAILURE_CAP; i++) {
            pushMonitor.topFailures.add(sorted[i]);
        }
        pushMonitor.rootCauseSummary = buildRootCause(pushMonitor, sorted);
    }

    private static void accumulateFailure(
        Map<String, AgentPushWrappers.JobFailure> failuresByKey,
        ObjectWrappers.PackagePushJobWrapper job
    ) {
        ObjectWrappers.JobErrorsWrapper error = firstError(job);
        String errorType = (error == null || error.ErrorType == null) ? 'Unknown' : error.ErrorType;
        String errorTitle = (error == null || error.ErrorTitle == null) ? 'Unknown error' : error.ErrorTitle;
        String key = errorType + '||' + errorTitle;

        AgentPushWrappers.JobFailure failure = failuresByKey.get(key);
        if (failure == null) {
            failure = new AgentPushWrappers.JobFailure();
            failure.errorType = errorType;
            failure.errorTitle = errorTitle;
            failure.subscriberOrgKey = job.SubscriberOrganizationKey;
            failure.occurrenceCount = 0;
            if (error != null) {
                failure.errorMessage = error.ErrorMessage;
                failure.errorSeverity = error.ErrorSeverity;
            }
            failuresByKey.put(key, failure);
        }
        failure.occurrenceCount++;
    }

    private static ObjectWrappers.JobErrorsWrapper firstError(ObjectWrappers.PackagePushJobWrapper job) {
        if (job.PackagePushErrors == null
            || job.PackagePushErrors.records == null
            || job.PackagePushErrors.records.isEmpty()) {
            return null;
        }
        return job.PackagePushErrors.records[0];
    }

    private static List<AgentPushWrappers.JobFailure> sortByOccurrence(List<AgentPushWrappers.JobFailure> failures) {
        List<AgentPushWrappers.JobFailure> sorted = new List<AgentPushWrappers.JobFailure>(failures);
        // Simple insertion sort by descending occurrenceCount — failure-cause cardinality is small.
        for (Integer i = 1; i < sorted.size(); i++) {
            AgentPushWrappers.JobFailure current = sorted[i];
            Integer j = i - 1;
            while (j >= 0 && sorted[j].occurrenceCount < current.occurrenceCount) {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = current;
        }
        return sorted;
    }

    private static String buildRootCause(AgentPushWrappers.PushMonitor pushMonitor, List<AgentPushWrappers.JobFailure> sorted) {
        if (pushMonitor.failedJobs == 0) {
            return (pushMonitor.totalJobs == 0)
                ? 'No push jobs found for this request yet.'
                : 'No failures: ' + pushMonitor.succeededJobs + ' succeeded, ' + pushMonitor.pendingJobs + ' pending.';
        }
        AgentPushWrappers.JobFailure top = sorted[0];
        return pushMonitor.failedJobs + ' job ' + (pushMonitor.failedJobs == 1 ? 'failure' : 'failures')
            + ', most commonly "' + top.errorTitle + '" (' + top.errorType + ') ×' + top.occurrenceCount + '.';
    }

    private static List<ObjectWrappers.FilterWrapper> idFilter(String fieldName, String value) {
        ObjectWrappers.FilterWrapper filter = new ObjectWrappers.FilterWrapper();
        filter.fieldName = fieldName;
        filter.value = value;
        filter.dataType = 'STRING';
        return new List<ObjectWrappers.FilterWrapper>{ filter };
    }
}
