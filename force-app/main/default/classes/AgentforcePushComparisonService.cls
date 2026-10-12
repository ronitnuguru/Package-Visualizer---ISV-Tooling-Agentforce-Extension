/**
 * Builds read-only sibling failure comparisons for authoritative push-request
 * context retained by the Package Visualizer Agent.
 */
public with sharing class AgentforcePushComparisonService {
  private static final Integer JOB_SCAN_LIMIT = 2000;
  private static final Integer ERROR_SCAN_LIMIT = 10000;

  /**
   * Compares sibling failures in bulk while retaining 1:1 response ordering.
   *
   * @param inputs Persisted active-job contexts.
   * @return One safe comparison result per input.
   */
  public static List<ComparisonResult> compare(List<ComparisonInput> inputs) {
    List<ComparisonResult> results = new List<ComparisonResult>();
    if (inputs == null || inputs.isEmpty()) {
      return results;
    }
    if (!AgentforcePushDiagnosticsService.hasPermission()) {
      return failures(
        inputs.size(),
        'FORBIDDEN',
        'You do not have access to Package Visualizer push diagnostics.'
      );
    }

    AgentforcePushDiagnosticsQueryService queryService = AgentforcePushDiagnosticsService.getQueryService();
    if (!queryService.areCoreObjectsAvailable()) {
      return failures(
        inputs.size(),
        'UNAVAILABLE',
        'Package push comparison data is not available in this org.'
      );
    }

    Set<String> selectedJobIds = new Set<String>();
    for (ComparisonInput input : inputs) {
      if (isValidInput(input)) {
        selectedJobIds.add(input.selectedPushJobId);
      }
    }

    List<AgentforcePushDiagnosticsQueryService.JobRecord> scannedJobs;
    Map<String, AgentforcePushDiagnosticsQueryService.JobRecord> selectedJobs;
    List<AgentforcePushDiagnosticsQueryService.ErrorRecord> scannedErrors;
    Set<String> requestIds = new Set<String>();
    Boolean jobsTruncated = false;
    Boolean errorsTruncated = false;
    try {
      selectedJobs = jobMap(queryService.getJobs(selectedJobIds));
      for (AgentforcePushDiagnosticsQueryService.JobRecord selectedJob : selectedJobs.values()) {
        if (isId(selectedJob.pushRequestId, '0DV')) {
          requestIds.add(selectedJob.pushRequestId);
        }
      }
      scannedJobs = queryService.getRequestJobs(
        requestIds,
        JOB_SCAN_LIMIT + 1
      );
      if (scannedJobs.size() > JOB_SCAN_LIMIT) {
        scannedJobs.remove(scannedJobs.size() - 1);
        jobsTruncated = true;
      }
      Set<String> scannedJobIds = new Set<String>();
      for (AgentforcePushDiagnosticsQueryService.JobRecord job : scannedJobs) {
        scannedJobIds.add(job.id);
      }
      scannedErrors = queryService.getRequestErrors(
        scannedJobIds,
        ERROR_SCAN_LIMIT + 1
      );
      if (scannedErrors.size() > ERROR_SCAN_LIMIT) {
        scannedErrors.remove(scannedErrors.size() - 1);
        errorsTruncated = true;
      }
    } catch (Exception queryException) {
      return failures(
        inputs.size(),
        isAccessException(queryException) ? 'FORBIDDEN' : 'ERROR',
        isAccessException(queryException)
          ? 'You do not have access to the requested package push records.'
          : 'Package push comparison failed safely. Try again later.'
      );
    }

    Map<String, AgentforcePushDiagnosticsQueryService.JobRecord> scannedJobsById = jobMap(
      scannedJobs
    );
    Map<String, List<AgentforcePushDiagnosticsQueryService.JobRecord>> jobsByRequestId = jobsByRequest(
      scannedJobs
    );
    Map<String, List<AgentforcePushDiagnosticsQueryService.ErrorRecord>> errorsByRequestId = errorsByRequest(
      scannedErrors,
      scannedJobsById
    );
    Enrichment enrichment = loadEnrichment(queryService, requestIds);

    for (ComparisonInput input : inputs) {
      if (!isValidInput(input)) {
        results.add(
          failure(
            'INVALID_ID',
            'Comparison requires a stored active 0DX PackagePushJob ID. Diagnose a failed job first.'
          )
        );
        continue;
      }
      AgentforcePushDiagnosticsQueryService.JobRecord selectedJob = selectedJobs.get(
        input.selectedPushJobId
      );
      String pushRequestId = selectedJob == null
        ? null
        : selectedJob.pushRequestId;
      List<AgentforcePushDiagnosticsQueryService.JobRecord> requestJobs = jobsByRequestId.get(
        pushRequestId
      );
      if (
        selectedJob == null ||
        !isId(pushRequestId, '0DV') ||
        requestJobs == null
      ) {
        results.add(
          failure(
            'NOT_FOUND',
            'The selected push job and its owning push request could not be verified.'
          )
        );
        continue;
      }

      AgentforcePushDiagnosticsQueryService.RequestRecord requestRecord = enrichment.requestsById.get(
        pushRequestId
      );
      AgentforcePushDiagnosticsQueryService.VersionRecord versionRecord = requestRecord == null
        ? null
        : enrichment.versionsById.get(requestRecord.packageVersionId);
      List<String> warnings = enrichment.warnings.clone();
      if (jobsTruncated) {
        warnings.add('The comparison scanned the first 2,000 jobs.');
      }
      if (errorsTruncated) {
        warnings.add('The comparison scanned the first 10,000 error rows.');
      }

      ComparisonResult ready = new ComparisonResult();
      ready.state = 'READY';
      ready.message = 'Authoritative push-request comparison context is ready.';
      ready.pushRequestId = pushRequestId;
      ready.comparisonJson = AgentforcePushDiagnosticsJsonService.buildComparison(
        pushRequestId,
        input.selectedPushJobId,
        requestRecord,
        versionRecord,
        requestJobs,
        errorsByRequestId.get(pushRequestId) ??
          new List<AgentforcePushDiagnosticsQueryService.ErrorRecord>(),
        jobsTruncated,
        errorsTruncated,
        warnings
      );
      results.add(ready);
    }
    return results;
  }

  private static Enrichment loadEnrichment(
    AgentforcePushDiagnosticsQueryService queryService,
    Set<String> requestIds
  ) {
    Enrichment enrichment = new Enrichment();
    if (!queryService.areOptionalObjectsAvailable()) {
      enrichment.warnings.add(
        'Push request or package-version enrichment is unavailable.'
      );
      return enrichment;
    }
    try {
      List<AgentforcePushDiagnosticsQueryService.RequestRecord> requests = queryService.getRequests(
        requestIds
      );
      Set<String> versionIds = new Set<String>();
      for (AgentforcePushDiagnosticsQueryService.RequestRecord requestRecord : requests) {
        enrichment.requestsById.put(requestRecord.id, requestRecord);
        if (!String.isBlank(requestRecord.packageVersionId)) {
          versionIds.add(requestRecord.packageVersionId);
        }
      }
      for (AgentforcePushDiagnosticsQueryService.VersionRecord versionRecord : queryService.getVersions(
        versionIds
      )) {
        enrichment.versionsById.put(versionRecord.id, versionRecord);
      }
    } catch (Exception ignored) {
      enrichment.warnings.add(
        'Push request or package-version enrichment is unavailable.'
      );
    }
    return enrichment;
  }

  private static Map<String, AgentforcePushDiagnosticsQueryService.JobRecord> jobMap(
    List<AgentforcePushDiagnosticsQueryService.JobRecord> jobs
  ) {
    Map<String, AgentforcePushDiagnosticsQueryService.JobRecord> values = new Map<String, AgentforcePushDiagnosticsQueryService.JobRecord>();
    for (AgentforcePushDiagnosticsQueryService.JobRecord job : jobs) {
      values.put(job.id, job);
    }
    return values;
  }

  private static Map<String, List<AgentforcePushDiagnosticsQueryService.JobRecord>> jobsByRequest(
    List<AgentforcePushDiagnosticsQueryService.JobRecord> jobs
  ) {
    Map<String, List<AgentforcePushDiagnosticsQueryService.JobRecord>> values = new Map<String, List<AgentforcePushDiagnosticsQueryService.JobRecord>>();
    for (AgentforcePushDiagnosticsQueryService.JobRecord job : jobs) {
      if (!values.containsKey(job.pushRequestId)) {
        values.put(
          job.pushRequestId,
          new List<AgentforcePushDiagnosticsQueryService.JobRecord>()
        );
      }
      values.get(job.pushRequestId).add(job);
    }
    return values;
  }

  private static Map<String, List<AgentforcePushDiagnosticsQueryService.ErrorRecord>> errorsByRequest(
    List<AgentforcePushDiagnosticsQueryService.ErrorRecord> errors,
    Map<String, AgentforcePushDiagnosticsQueryService.JobRecord> jobsById
  ) {
    Map<String, List<AgentforcePushDiagnosticsQueryService.ErrorRecord>> values = new Map<String, List<AgentforcePushDiagnosticsQueryService.ErrorRecord>>();
    for (AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord : errors) {
      String requestId = jobsById.get(errorRecord.jobId)?.pushRequestId;
      if (String.isBlank(requestId)) {
        continue;
      }
      if (!values.containsKey(requestId)) {
        values.put(
          requestId,
          new List<AgentforcePushDiagnosticsQueryService.ErrorRecord>()
        );
      }
      values.get(requestId).add(errorRecord);
    }
    return values;
  }

  private static Boolean isValidInput(ComparisonInput input) {
    return input != null &&
      isId(input.selectedPushJobId, '0DX');
  }

  private static Boolean isId(String value, String prefix) {
    return value != null &&
      Pattern.matches(
        '^' + prefix + '[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$',
        value
      );
  }

  private static Boolean isAccessException(Exception exceptionValue) {
    String typeName = exceptionValue.getTypeName();
    return typeName != null && typeName.toLowerCase().contains('noaccess');
  }

  private static List<ComparisonResult> failures(
    Integer countValue,
    String stateValue,
    String messageValue
  ) {
    List<ComparisonResult> values = new List<ComparisonResult>();
    for (Integer indexValue = 0; indexValue < countValue; indexValue++) {
      values.add(failure(stateValue, messageValue));
    }
    return values;
  }

  private static ComparisonResult failure(
    String stateValue,
    String messageValue
  ) {
    ComparisonResult value = new ComparisonResult();
    value.state = stateValue;
    value.message = messageValue;
    return value;
  }

  /** Service input for one sibling comparison invocation. */
  public class ComparisonInput {
    public String selectedPushJobId;
  }

  /** Service output for one sibling comparison invocation. */
  public class ComparisonResult {
    public String state;
    public String message;
    public String pushRequestId;
    public String comparisonJson;
  }

  private class Enrichment {
    private Map<String, AgentforcePushDiagnosticsQueryService.RequestRecord> requestsById = new Map<String, AgentforcePushDiagnosticsQueryService.RequestRecord>();
    private Map<String, AgentforcePushDiagnosticsQueryService.VersionRecord> versionsById = new Map<String, AgentforcePushDiagnosticsQueryService.VersionRecord>();
    private List<String> warnings = new List<String>();
  }
}
