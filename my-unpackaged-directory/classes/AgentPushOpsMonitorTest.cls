@IsTest
private class AgentPushOpsMonitorTest {

    private static final String PUSH_REQ_ID = '0DV5g000000AbcdEFG';

    private static ObjectWrappers.PackagePushRequestWrapper request(String status) {
        ObjectWrappers.PackagePushRequestWrapper r = new ObjectWrappers.PackagePushRequestWrapper();
        r.Id = PUSH_REQ_ID;
        r.Status = status;
        return r;
    }

    private static ObjectWrappers.PackagePushJobWrapper job(String status, String orgKey, String errorType, String errorTitle) {
        ObjectWrappers.PackagePushJobWrapper j = new ObjectWrappers.PackagePushJobWrapper();
        j.PackagePushRequestId = PUSH_REQ_ID;
        j.Status = status;
        j.SubscriberOrganizationKey = orgKey;
        if (errorType != null) {
            ObjectWrappers.JobErrorsWrapper err = new ObjectWrappers.JobErrorsWrapper();
            err.ErrorType = errorType;
            err.ErrorTitle = errorTitle;
            err.ErrorMessage = 'Detail for ' + errorTitle;
            err.ErrorSeverity = 'Error';
            ObjectWrappers.PackagePushErrorsWrapper errors = new ObjectWrappers.PackagePushErrorsWrapper();
            errors.records = new List<ObjectWrappers.JobErrorsWrapper>{ err };
            j.PackagePushErrors = errors;
        }
        return j;
    }

    private static AgentPushWrappers.PushMonitor invoke() {
        AgentPushOpsMonitor.MonitorRequest req = new AgentPushOpsMonitor.MonitorRequest();
        req.pushRequestId = PUSH_REQ_ID;
        AgentPushOpsMonitor.MonitorResponse resp = AgentPushOpsMonitor.monitor(new List<AgentPushOpsMonitor.MonitorRequest>{ req })[0];
        return (AgentPushWrappers.PushMonitor) JSON.deserialize(resp.resultJson, AgentPushWrappers.PushMonitor.class);
    }

    @IsTest
    static void shouldSummarizeCounts_AndGroupFailures() {
        AgentPushOpsMonitor.mockRequests = new List<ObjectWrappers.PackagePushRequestWrapper>{ request('InProgress') };
        AgentPushOpsMonitor.mockJobs = new List<ObjectWrappers.PackagePushJobWrapper>{
            job('Succeeded', '00D5g000001abcDEFG', null, null),
            job('Failed', '00D5g000002abcDEFG', 'INVALID_OPERATION', 'Namespace conflict'),
            job('Failed', '00D5g000003abcDEFG', 'INVALID_OPERATION', 'Namespace conflict'),
            job('Created', '00D5g000004abcDEFG', null, null)
        };

        Test.startTest();
        AgentPushWrappers.PushMonitor monitor = invoke();
        Test.stopTest();

        System.assertEquals('InProgress', monitor.status);
        System.assertEquals(4, monitor.totalJobs);
        System.assertEquals(1, monitor.succeededJobs);
        System.assertEquals(2, monitor.failedJobs);
        System.assertEquals(1, monitor.pendingJobs);
        System.assertEquals(1, monitor.topFailures.size(), 'two identical failures group into one cause');
        System.assertEquals(2, monitor.topFailures[0].occurrenceCount);
        System.assert(monitor.rootCauseSummary.contains('Namespace conflict'));
    }

    @IsTest
    static void shouldReportNoFailures_WhenAllSucceeded() {
        AgentPushOpsMonitor.mockRequests = new List<ObjectWrappers.PackagePushRequestWrapper>{ request('Succeeded') };
        AgentPushOpsMonitor.mockJobs = new List<ObjectWrappers.PackagePushJobWrapper>{
            job('Succeeded', '00D5g000001abcDEFG', null, null)
        };

        Test.startTest();
        AgentPushWrappers.PushMonitor monitor = invoke();
        Test.stopTest();

        System.assertEquals(0, monitor.failedJobs);
        System.assert(monitor.rootCauseSummary.contains('No failures'));
    }

    @IsTest
    static void shouldReportNoJobs_WhenEmpty() {
        AgentPushOpsMonitor.mockRequests = new List<ObjectWrappers.PackagePushRequestWrapper>{ request('Created') };
        AgentPushOpsMonitor.mockJobs = new List<ObjectWrappers.PackagePushJobWrapper>();

        Test.startTest();
        AgentPushWrappers.PushMonitor monitor = invoke();
        Test.stopTest();

        System.assertEquals(0, monitor.totalJobs);
        System.assert(monitor.rootCauseSummary.contains('No push jobs'));
    }

    @IsTest
    static void shouldReturnError_WhenIdBlank() {
        AgentPushOpsMonitor.MonitorRequest req = new AgentPushOpsMonitor.MonitorRequest();
        req.pushRequestId = '';

        Test.startTest();
        AgentPushOpsMonitor.MonitorResponse resp = AgentPushOpsMonitor.monitor(new List<AgentPushOpsMonitor.MonitorRequest>{ req })[0];
        Test.stopTest();

        AgentPushWrappers.PushMonitor monitor = (AgentPushWrappers.PushMonitor) JSON.deserialize(resp.resultJson, AgentPushWrappers.PushMonitor.class);
        System.assertNotEquals(null, monitor.errorMessage);
    }

    @IsTest
    static void shouldReturnError_WhenNullRequest() {
        Test.startTest();
        AgentPushOpsMonitor.MonitorResponse resp = AgentPushOpsMonitor.monitor(new List<AgentPushOpsMonitor.MonitorRequest>{ null })[0];
        Test.stopTest();

        AgentPushWrappers.PushMonitor monitor = (AgentPushWrappers.PushMonitor) JSON.deserialize(resp.resultJson, AgentPushWrappers.PushMonitor.class);
        System.assertNotEquals(null, monitor.errorMessage);
    }

    @IsTest
    static void shouldProcessBulk_WhenManyRequests() {
        AgentPushOpsMonitor.mockRequests = new List<ObjectWrappers.PackagePushRequestWrapper>{ request('Succeeded') };
        AgentPushOpsMonitor.mockJobs = new List<ObjectWrappers.PackagePushJobWrapper>{
            job('Succeeded', '00D5g000001abcDEFG', null, null)
        };

        List<AgentPushOpsMonitor.MonitorRequest> requests = new List<AgentPushOpsMonitor.MonitorRequest>();
        for (Integer i = 0; i < 200; i++) {
            AgentPushOpsMonitor.MonitorRequest req = new AgentPushOpsMonitor.MonitorRequest();
            req.pushRequestId = PUSH_REQ_ID;
            requests.add(req);
        }

        Test.startTest();
        List<AgentPushOpsMonitor.MonitorResponse> responses = AgentPushOpsMonitor.monitor(requests);
        Test.stopTest();

        System.assertEquals(200, responses.size());
    }
}
