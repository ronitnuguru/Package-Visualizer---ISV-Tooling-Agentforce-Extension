/**
 * Coordinates permission-checked, read-only PackagePushJob diagnostics and
 * PackagePushRequest sibling comparison for Agentforce invocable actions.
 */
public with sharing class AgentforcePushDiagnosticsService {
  private static final String CUSTOM_PERMISSION = 'Package_Visualizer_Push_Upgrade';
  private static final Integer DIAGNOSTIC_ERROR_SCAN_LIMIT = 10000;

  @TestVisible
  static AgentforcePushDiagnosticsQueryService queryService = new AgentforcePushDiagnosticsQueryService();
  @TestVisible
  static Boolean permissionOverride;

  /**
   * Diagnoses push jobs in bulk while retaining 1:1 response ordering.
   *
   * @param inputs Latest user input and optional persisted job context.
   * @return One safe diagnostic result per input.
   */
  public static List<DiagnosisResult> diagnose(List<DiagnosisInput> inputs) {
    List<DiagnosisResult> results = new List<DiagnosisResult>();
    if (inputs == null || inputs.isEmpty()) {
      return results;
    }
    if (!hasPermission()) {
      return diagnosisFailures(
        inputs.size(),
        'FORBIDDEN',
        'You do not have access to Package Visualizer push diagnostics.',
        true
      );
    }
    if (!queryService.areCoreObjectsAvailable()) {
      return diagnosisFailures(
        inputs.size(),
        'UNAVAILABLE',
        'Package push diagnostic data is not available in this org.',
        true
      );
    }

    List<JobSelection> selections = new List<JobSelection>();
    Set<String> selectedJobIds = new Set<String>();
    for (DiagnosisInput input : inputs) {
      JobSelection selection = selectJob(input);
      selections.add(selection);
      if (selection.isValid) {
        selectedJobIds.add(selection.jobId);
      }
    }
    if (selectedJobIds.isEmpty()) {
      for (JobSelection selection : selections) {
        results.add(
          diagnosisFailure(
            'INVALID_ID',
            'Provide a valid 15- or 18-character PackagePushJob ID beginning with 0DX.',
            selection.replacementAttempted
          )
        );
      }
      return results;
    }

    Map<String, AgentforcePushDiagnosticsQueryService.JobRecord> jobsById;
    Map<String, List<AgentforcePushDiagnosticsQueryService.ErrorRecord>> errorsByJobId;
    Boolean sourceErrorsTruncated = false;
    try {
      jobsById = jobMap(queryService.getJobs(selectedJobIds));
      List<AgentforcePushDiagnosticsQueryService.ErrorRecord> errors = queryService.getErrors(
        selectedJobIds,
        DIAGNOSTIC_ERROR_SCAN_LIMIT + 1
      );
      if (errors.size() > DIAGNOSTIC_ERROR_SCAN_LIMIT) {
        errors.remove(errors.size() - 1);
        sourceErrorsTruncated = true;
      }
      errorsByJobId = errorsByJob(errors);
    } catch (Exception queryException) {
      return diagnosisQueryFailures(inputs, selections, queryException);
    }

    Enrichment enrichment = loadEnrichment(jobsById.values());
    for (Integer indexValue = 0; indexValue < inputs.size(); indexValue++) {
      JobSelection selection = selections[indexValue];
      if (!selection.isValid) {
        results.add(
          diagnosisFailure(
            'INVALID_ID',
            'Provide a valid 15- or 18-character PackagePushJob ID beginning with 0DX.',
            selection.replacementAttempted
          )
        );
        continue;
      }

      AgentforcePushDiagnosticsQueryService.JobRecord job = jobsById.get(
        selection.jobId
      );
      if (job == null) {
        results.add(
          diagnosisFailure(
            'NOT_FOUND',
            'The PackagePushJob was not found or is not accessible.',
            true
          )
        );
        continue;
      }
      if (job.status != 'Failed') {
        DiagnosisResult notFailed = diagnosisFailure(
          'NOT_FAILED',
          'The selected PackagePushJob is not failed.',
          true
        );
        notFailed.jobId = job.id;
        results.add(notFailed);
        continue;
      }

      List<AgentforcePushDiagnosticsQueryService.ErrorRecord> jobErrors = errorsByJobId.get(
        job.id
      );
      if (jobErrors == null || jobErrors.isEmpty()) {
        DiagnosisResult noErrors = diagnosisFailure(
          'NO_ERRORS',
          'The failed PackagePushJob has no accessible PackagePushError records.',
          true
        );
        noErrors.jobId = job.id;
        noErrors.pushRequestId = job.pushRequestId;
        results.add(noErrors);
        continue;
      }

      AgentforcePushDiagnosticsQueryService.RequestRecord requestRecord = enrichment.requestsById.get(
        job.pushRequestId
      );
      AgentforcePushDiagnosticsQueryService.VersionRecord versionRecord = requestRecord == null
        ? null
        : enrichment.versionsById.get(requestRecord.packageVersionId);
      AgentforcePushDiagnosticsQueryService.SubscriberRecord subscriberRecord = subscriberFor(
        enrichment.subscribers,
        job.subscriberOrgKey,
        versionRecord?.packageId
      );
      List<String> warnings = enrichment.warnings.clone();
      addMissingEnrichmentWarnings(
        warnings,
        job,
        requestRecord,
        versionRecord,
        subscriberRecord
      );
      if (sourceErrorsTruncated) {
        warnings.add(
          'The diagnostic error-row scan reached 10,000 rows; additional occurrences may exist.'
        );
      }

      DiagnosisResult ready = new DiagnosisResult();
      ready.state = 'READY';
      ready.message = 'Authoritative failed push-job diagnostic context is ready.';
      ready.clearPreviousContext = selection.replacementAttempted;
      ready.jobId = job.id;
      ready.pushRequestId = job.pushRequestId;
      ready.targetPackageVersionId = requestRecord?.packageVersionId;
      ready.diagnosticJson = AgentforcePushDiagnosticsJsonService.buildDiagnostic(
        job,
        requestRecord,
        versionRecord,
        subscriberRecord,
        jobErrors,
        warnings,
        sourceErrorsTruncated
      );
      results.add(ready);
    }
    return results;
  }

  private static JobSelection selectJob(DiagnosisInput input) {
    JobSelection selection = new JobSelection();
    String userInput = input?.userInput;
    Matcher validMatcher = Pattern.compile(
      '\\b0DX[a-zA-Z0-9]{12}(?:[a-zA-Z0-9]{3})?\\b'
    ).matcher(userInput ?? '');
    if (validMatcher.find()) {
      selection.jobId = validMatcher.group();
      selection.isValid = true;
      selection.replacementAttempted = true;
      return selection;
    }

    Matcher anyIdMatcher = Pattern.compile(
      '\\b[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?\\b'
    ).matcher(userInput ?? '');
    selection.replacementAttempted = anyIdMatcher.find() ||
      (userInput ?? '').toLowerCase().contains('0dx');
    if (selection.replacementAttempted) {
      return selection;
    }
    if (isId(input?.currentPushJobId, '0DX')) {
      selection.jobId = input.currentPushJobId;
      selection.isValid = true;
      return selection;
    }
    selection.replacementAttempted = !String.isBlank(input?.currentPushJobId);
    return selection;
  }

  private static Enrichment loadEnrichment(
    List<AgentforcePushDiagnosticsQueryService.JobRecord> jobs
  ) {
    Set<String> requestIds = new Set<String>();
    for (AgentforcePushDiagnosticsQueryService.JobRecord job : jobs) {
      if (!String.isBlank(job.pushRequestId)) {
        requestIds.add(job.pushRequestId);
      }
    }
    Enrichment enrichment = loadRequestEnrichment(requestIds);
    if (!queryService.areOptionalObjectsAvailable()) {
      return enrichment;
    }
    Set<String> orgKeys = new Set<String>();
    for (AgentforcePushDiagnosticsQueryService.JobRecord job : jobs) {
      if (!String.isBlank(job.subscriberOrgKey)) {
        orgKeys.add(job.subscriberOrgKey);
      }
    }
    Set<String> packageIds = new Set<String>();
    for (AgentforcePushDiagnosticsQueryService.VersionRecord versionRecord : enrichment.versionsById.values()) {
      if (!String.isBlank(versionRecord.packageId)) {
        packageIds.add(versionRecord.packageId);
      }
    }
    try {
      enrichment.subscribers = queryService.getSubscribers(orgKeys, packageIds);
    } catch (Exception ignored) {
      enrichment.warnings.add('Subscriber enrichment is unavailable.');
    }
    return enrichment;
  }

  private static Enrichment loadRequestEnrichment(Set<String> requestIds) {
    Enrichment enrichment = new Enrichment();
    if (!queryService.areOptionalObjectsAvailable()) {
      enrichment.warnings.add(
        'Push request, version, or subscriber enrichment is unavailable.'
      );
      return enrichment;
    }
    try {
      enrichment.requestsById = requestMap(
        queryService.getRequests(requestIds)
      );
      Set<String> versionIds = new Set<String>();
      for (AgentforcePushDiagnosticsQueryService.RequestRecord requestRecord : enrichment.requestsById.values()) {
        if (!String.isBlank(requestRecord.packageVersionId)) {
          versionIds.add(requestRecord.packageVersionId);
        }
      }
      enrichment.versionsById = versionMap(
        queryService.getVersions(versionIds)
      );
    } catch (Exception ignored) {
      enrichment.warnings.add('Push request or version enrichment is unavailable.');
    }
    return enrichment;
  }

  private static void addMissingEnrichmentWarnings(
    List<String> warnings,
    AgentforcePushDiagnosticsQueryService.JobRecord job,
    AgentforcePushDiagnosticsQueryService.RequestRecord requestRecord,
    AgentforcePushDiagnosticsQueryService.VersionRecord versionRecord,
    AgentforcePushDiagnosticsQueryService.SubscriberRecord subscriberRecord
  ) {
    if (!String.isBlank(job.pushRequestId) && requestRecord == null) {
      warnings.add('Owning push-request enrichment was not found.');
    } else if (requestRecord != null && versionRecord == null) {
      warnings.add('Target package-version enrichment was not found.');
    }
    if (subscriberRecord == null) {
      warnings.add('Subscriber enrichment was not found.');
    }
  }

  private static AgentforcePushDiagnosticsQueryService.SubscriberRecord subscriberFor(
    List<AgentforcePushDiagnosticsQueryService.SubscriberRecord> subscribers,
    String orgKey,
    String packageId
  ) {
    for (AgentforcePushDiagnosticsQueryService.SubscriberRecord subscriber : subscribers) {
      if (
        subscriber.orgKey == orgKey &&
        (String.isBlank(packageId) || subscriber.packageId == packageId)
      ) {
        return subscriber;
      }
    }
    return null;
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

  private static Map<String, List<AgentforcePushDiagnosticsQueryService.ErrorRecord>> errorsByJob(
    List<AgentforcePushDiagnosticsQueryService.ErrorRecord> errors
  ) {
    Map<String, List<AgentforcePushDiagnosticsQueryService.ErrorRecord>> values = new Map<String, List<AgentforcePushDiagnosticsQueryService.ErrorRecord>>();
    for (AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord : errors) {
      if (!values.containsKey(errorRecord.jobId)) {
        values.put(
          errorRecord.jobId,
          new List<AgentforcePushDiagnosticsQueryService.ErrorRecord>()
        );
      }
      values.get(errorRecord.jobId).add(errorRecord);
    }
    return values;
  }

  private static Map<String, AgentforcePushDiagnosticsQueryService.RequestRecord> requestMap(
    List<AgentforcePushDiagnosticsQueryService.RequestRecord> records
  ) {
    Map<String, AgentforcePushDiagnosticsQueryService.RequestRecord> values = new Map<String, AgentforcePushDiagnosticsQueryService.RequestRecord>();
    for (AgentforcePushDiagnosticsQueryService.RequestRecord recordValue : records) {
      values.put(recordValue.id, recordValue);
    }
    return values;
  }

  private static Map<String, AgentforcePushDiagnosticsQueryService.VersionRecord> versionMap(
    List<AgentforcePushDiagnosticsQueryService.VersionRecord> records
  ) {
    Map<String, AgentforcePushDiagnosticsQueryService.VersionRecord> values = new Map<String, AgentforcePushDiagnosticsQueryService.VersionRecord>();
    for (AgentforcePushDiagnosticsQueryService.VersionRecord recordValue : records) {
      values.put(recordValue.id, recordValue);
    }
    return values;
  }

  /**
   * @return The active read-only packaging query service.
   */
  public static AgentforcePushDiagnosticsQueryService getQueryService() {
    return queryService;
  }

  /**
   * @return true when the running user has push-upgrade diagnostic access.
   */
  public static Boolean hasPermission() {
    return permissionOverride == null
      ? FeatureManagement.checkPermission(CUSTOM_PERMISSION)
      : permissionOverride;
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

  private static List<DiagnosisResult> diagnosisQueryFailures(
    List<DiagnosisInput> inputs,
    List<JobSelection> selections,
    Exception exceptionValue
  ) {
    List<DiagnosisResult> values = new List<DiagnosisResult>();
    String stateValue = isAccessException(exceptionValue)
      ? 'FORBIDDEN'
      : 'ERROR';
    String messageValue = stateValue == 'FORBIDDEN'
      ? 'You do not have access to the requested package push records.'
      : 'Package push diagnosis failed safely. Try again later.';
    for (Integer indexValue = 0; indexValue < inputs.size(); indexValue++) {
      if (!selections[indexValue].isValid) {
        values.add(
          diagnosisFailure(
            'INVALID_ID',
            'Provide a valid 15- or 18-character PackagePushJob ID beginning with 0DX.',
            selections[indexValue].replacementAttempted
          )
        );
      } else {
        values.add(diagnosisFailure(stateValue, messageValue, true));
      }
    }
    return values;
  }

  private static List<DiagnosisResult> diagnosisFailures(
    Integer countValue,
    String stateValue,
    String messageValue,
    Boolean clearPreviousContext
  ) {
    List<DiagnosisResult> values = new List<DiagnosisResult>();
    for (Integer indexValue = 0; indexValue < countValue; indexValue++) {
      values.add(
        diagnosisFailure(
          stateValue,
          messageValue,
          clearPreviousContext
        )
      );
    }
    return values;
  }

  private static DiagnosisResult diagnosisFailure(
    String stateValue,
    String messageValue,
    Boolean clearPreviousContext
  ) {
    DiagnosisResult value = new DiagnosisResult();
    value.state = stateValue;
    value.message = messageValue;
    value.clearPreviousContext = clearPreviousContext;
    return value;
  }

  /** Service input for one diagnosis invocation. */
  public class DiagnosisInput {
    public String userInput;
    public String currentPushJobId;
  }

  /** Service output for one diagnosis invocation. */
  public class DiagnosisResult {
    public String state;
    public String message;
    public Boolean clearPreviousContext;
    public String jobId;
    public String pushRequestId;
    public String targetPackageVersionId;
    public String diagnosticJson;
  }

  private class JobSelection {
    private String jobId;
    private Boolean isValid = false;
    private Boolean replacementAttempted = false;
  }

  private class Enrichment {
    private Map<String, AgentforcePushDiagnosticsQueryService.RequestRecord> requestsById = new Map<String, AgentforcePushDiagnosticsQueryService.RequestRecord>();
    private Map<String, AgentforcePushDiagnosticsQueryService.VersionRecord> versionsById = new Map<String, AgentforcePushDiagnosticsQueryService.VersionRecord>();
    private List<AgentforcePushDiagnosticsQueryService.SubscriberRecord> subscribers = new List<AgentforcePushDiagnosticsQueryService.SubscriberRecord>();
    private List<String> warnings = new List<String>();
  }
}
