/**
 * Shared test fixtures and the replaceable packaging-data query seam used by
 * Agentforce push diagnostic action tests.
 */
@isTest
public with sharing class AgentforcePushDiagnosticsTestSupport {
  public static final String JOB_ID = '0DX000000000001AAA';
  public static final String SECOND_JOB_ID = '0DX000000000002AAA';
  public static final String REQUEST_ID = '0DV000000000001AAA';
  public static final String VERSION_ID = '04t000000000001AAA';
  public static final String PACKAGE_ID = '033000000000001AAA';

  public class StubQueryService extends AgentforcePushDiagnosticsQueryService {
    public Boolean coreObjectsAvailable = true;
    public Boolean optionalObjectsAvailable = true;
    public Boolean shouldThrow = false;
    public Integer jobQueryCount = 0;
    public List<JobRecord> jobs = new List<JobRecord>();
    public List<ErrorRecord> errors = new List<ErrorRecord>();
    public List<RequestRecord> requests = new List<RequestRecord>();
    public List<VersionRecord> versions = new List<VersionRecord>();
    public List<SubscriberRecord> subscribers = new List<SubscriberRecord>();

    public override Boolean areCoreObjectsAvailable() {
      return coreObjectsAvailable;
    }

    public override Boolean areOptionalObjectsAvailable() {
      return optionalObjectsAvailable;
    }

    public override List<JobRecord> getJobs(Set<String> jobIds) {
      jobQueryCount++;
      throwWhenRequested();
      return filterJobs(jobIds, jobs);
    }

    public override List<ErrorRecord> getErrors(
      Set<String> jobIds,
      Integer rowLimit
    ) {
      throwWhenRequested();
      return limitErrors(jobIds, errors, rowLimit);
    }

    public override List<RequestRecord> getRequests(Set<String> requestIds) {
      throwWhenRequested();
      List<RequestRecord> matches = new List<RequestRecord>();
      for (RequestRecord requestRecord : requests) {
        if (requestIds.contains(requestRecord.id)) {
          matches.add(requestRecord);
        }
      }
      return matches;
    }

    public override List<VersionRecord> getVersions(Set<String> versionIds) {
      throwWhenRequested();
      List<VersionRecord> matches = new List<VersionRecord>();
      for (VersionRecord versionRecord : versions) {
        if (versionIds.contains(versionRecord.id)) {
          matches.add(versionRecord);
        }
      }
      return matches;
    }

    public override List<SubscriberRecord> getSubscribers(
      Set<String> orgKeys,
      Set<String> packageIds
    ) {
      throwWhenRequested();
      return subscribers;
    }

    public override List<JobRecord> getRequestJobs(
      Set<String> pushRequestIds,
      Integer rowLimit
    ) {
      throwWhenRequested();
      List<JobRecord> matches = new List<JobRecord>();
      for (JobRecord jobRecord : jobs) {
        if (
          pushRequestIds.contains(jobRecord.pushRequestId) &&
          matches.size() < rowLimit
        ) {
          matches.add(jobRecord);
        }
      }
      return matches;
    }

    public override List<ErrorRecord> getRequestErrors(
      Set<String> jobIds,
      Integer rowLimit
    ) {
      throwWhenRequested();
      return limitErrors(jobIds, errors, rowLimit);
    }

    private void throwWhenRequested() {
      if (shouldThrow) {
        throw new StubQueryException('raw internal query failure');
      }
    }
  }

  public class StubQueryException extends Exception {
  }

  public static StubQueryService readyStub() {
    StubQueryService stub = new StubQueryService();
    stub.jobs.add(jobRecord(JOB_ID, REQUEST_ID, 'Failed', '00D1'));
    stub.errors.add(errorRecord('0Yx000000000001AAA', JOB_ID, 'Same failure'));
    stub.requests.add(requestRecord(REQUEST_ID, VERSION_ID));
    stub.versions.add(versionRecord(VERSION_ID, PACKAGE_ID));
    stub.subscribers.add(subscriberRecord('00D1', PACKAGE_ID));
    AgentforcePushDiagnosticsService.queryService = stub;
    AgentforcePushDiagnosticsService.permissionOverride = true;
    return stub;
  }

  public static AgentforcePushJobDiagnosisAction.Request diagnosisRequest(
    String userInput,
    String currentJobId
  ) {
    AgentforcePushJobDiagnosisAction.Request requestValue = new AgentforcePushJobDiagnosisAction.Request();
    requestValue.userInput = userInput;
    requestValue.currentPushJobId = currentJobId;
    return requestValue;
  }

  public static AgentforcePushDiagnosticsQueryService.JobRecord jobRecord(
    String idValue,
    String requestIdValue,
    String statusValue,
    String orgKeyValue
  ) {
    AgentforcePushDiagnosticsQueryService.JobRecord recordValue = new AgentforcePushDiagnosticsQueryService.JobRecord();
    recordValue.id = idValue;
    recordValue.pushRequestId = requestIdValue;
    recordValue.status = statusValue;
    recordValue.subscriberOrgKey = orgKeyValue;
    recordValue.durationSeconds = 60;
    recordValue.startTime = Datetime.newInstance(2026, 7, 27, 9, 0, 0);
    recordValue.endTime = Datetime.newInstance(2026, 7, 27, 9, 1, 0);
    recordValue.systemModstamp = Datetime.newInstance(2026, 7, 27, 9, 1, 1);
    return recordValue;
  }

  public static AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord(
    String idValue,
    String jobIdValue,
    String messageValue
  ) {
    AgentforcePushDiagnosticsQueryService.ErrorRecord recordValue = new AgentforcePushDiagnosticsQueryService.ErrorRecord();
    recordValue.id = idValue;
    recordValue.jobId = jobIdValue;
    recordValue.title = 'Package install failed';
    recordValue.message = messageValue;
    recordValue.type = 'ApexTestFailure';
    recordValue.details = 'ExampleTest.shouldPass';
    recordValue.severity = 'Error';
    return recordValue;
  }

  public static AgentforcePushDiagnosticsQueryService.RequestRecord requestRecord(
    String idValue,
    String versionIdValue
  ) {
    AgentforcePushDiagnosticsQueryService.RequestRecord recordValue = new AgentforcePushDiagnosticsQueryService.RequestRecord();
    recordValue.id = idValue;
    recordValue.packageVersionId = versionIdValue;
    return recordValue;
  }

  public static AgentforcePushDiagnosticsQueryService.VersionRecord versionRecord(
    String idValue,
    String packageIdValue
  ) {
    AgentforcePushDiagnosticsQueryService.VersionRecord recordValue = new AgentforcePushDiagnosticsQueryService.VersionRecord();
    recordValue.id = idValue;
    recordValue.packageId = packageIdValue;
    recordValue.name = '1.2.0.1';
    recordValue.releaseState = 'Released';
    return recordValue;
  }

  public static AgentforcePushDiagnosticsQueryService.SubscriberRecord subscriberRecord(
    String orgKeyValue,
    String packageIdValue
  ) {
    AgentforcePushDiagnosticsQueryService.SubscriberRecord recordValue = new AgentforcePushDiagnosticsQueryService.SubscriberRecord();
    recordValue.orgKey = orgKeyValue;
    recordValue.packageId = packageIdValue;
    recordValue.orgName = 'Acme';
    recordValue.orgType = 'Production';
    recordValue.instanceName = 'NA99';
    recordValue.orgStatus = 'Active';
    recordValue.installedStatus = 'Installed';
    recordValue.installedVersionId = '04t000000000000AAA';
    return recordValue;
  }

  public static List<AgentforcePushDiagnosticsQueryService.JobRecord> filterJobs(
    Set<String> jobIds,
    List<AgentforcePushDiagnosticsQueryService.JobRecord> source
  ) {
    List<AgentforcePushDiagnosticsQueryService.JobRecord> matches = new List<AgentforcePushDiagnosticsQueryService.JobRecord>();
    for (AgentforcePushDiagnosticsQueryService.JobRecord recordValue : source) {
      if (jobIds.contains(recordValue.id)) {
        matches.add(recordValue);
      }
    }
    return matches;
  }

  public static List<AgentforcePushDiagnosticsQueryService.ErrorRecord> limitErrors(
    Set<String> jobIds,
    List<AgentforcePushDiagnosticsQueryService.ErrorRecord> source,
    Integer rowLimit
  ) {
    List<AgentforcePushDiagnosticsQueryService.ErrorRecord> matches = new List<AgentforcePushDiagnosticsQueryService.ErrorRecord>();
    for (
      AgentforcePushDiagnosticsQueryService.ErrorRecord recordValue : source
    ) {
      if (jobIds.contains(recordValue.jobId) && matches.size() < rowLimit) {
        matches.add(recordValue);
      }
    }
    return matches;
  }

  public static Map<String, Object> jsonMap(String value) {
    return (Map<String, Object>) JSON.deserializeUntyped(value);
  }

  public static String longText(Integer lengthValue) {
    String value = '';
    while (value.length() < lengthValue) {
      value += '0123456789';
    }
    return value.substring(0, lengthValue);
  }
}
