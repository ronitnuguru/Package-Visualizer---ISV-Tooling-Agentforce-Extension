/**
 * Direct, read-only PackagePushRequest cohort analysis anchored by a 0DV ID.
 */
public with sharing class AgentforcePushRequestAnalysisService {
  private static final Integer JOB_SCAN_LIMIT = 2000;
  private static final Integer ERROR_SCAN_LIMIT = 10000;
  private static final Integer JSON_LIMIT = 60000;

  public static List<Result> analyze(List<Input> inputs) {
    List<Result> results = new List<Result>();
    if (inputs == null || inputs.isEmpty()) {
      return results;
    }
    if (!AgentforcePushDiagnosticsService.hasPermission()) {
      return failures(
        inputs.size(),
        'FORBIDDEN',
        'You do not have access to Package Visualizer push-request analysis.',
        false
      );
    }
    AgentforcePushDiagnosticsQueryService queryService = AgentforcePushDiagnosticsService.getQueryService();
    if (!queryService.areCoreObjectsAvailable()) {
      return failures(
        inputs.size(),
        'UNAVAILABLE',
        'Package push-request analysis data is not available in this org.',
        false
      );
    }

    List<Selection> selections = new List<Selection>();
    Set<String> requestIds = new Set<String>();
    for (Input input : inputs) {
      Selection selection = selectRequest(input);
      selections.add(selection);
      if (selection.isValid) {
        requestIds.add(selection.requestId);
      }
    }

    Map<String, AgentforcePushDiagnosticsQueryService.RequestRecord> requestsById;
    List<AgentforcePushDiagnosticsQueryService.JobRecord> jobs;
    List<AgentforcePushDiagnosticsQueryService.ErrorRecord> errors;
    Boolean jobsTruncated = false;
    Boolean errorsTruncated = false;
    Map<String, AgentforcePushDiagnosticsQueryService.VersionRecord> versionsById = new Map<String, AgentforcePushDiagnosticsQueryService.VersionRecord>();
    List<String> warnings = new List<String>();
    try {
      requestsById = requestMap(queryService.getRequests(requestIds));
      jobs = queryService.getRequestJobs(requestIds, JOB_SCAN_LIMIT + 1);
      if (jobs.size() > JOB_SCAN_LIMIT) {
        jobs.remove(jobs.size() - 1);
        jobsTruncated = true;
      }
      Set<String> jobIds = new Set<String>();
      for (AgentforcePushDiagnosticsQueryService.JobRecord job : jobs) {
        jobIds.add(job.id);
      }
      errors = queryService.getRequestErrors(
        jobIds,
        ERROR_SCAN_LIMIT + 1
      );
      if (errors.size() > ERROR_SCAN_LIMIT) {
        errors.remove(errors.size() - 1);
        errorsTruncated = true;
      }
      try {
        Set<String> versionIds = new Set<String>();
        for (AgentforcePushDiagnosticsQueryService.RequestRecord requestRecord : requestsById.values()) {
          if (!String.isBlank(requestRecord.packageVersionId)) {
            versionIds.add(requestRecord.packageVersionId);
          }
        }
        versionsById = versionMap(queryService.getVersions(versionIds));
      } catch (Exception ignored) {
        warnings.add('Package-version enrichment is unavailable.');
      }
    } catch (Exception exceptionValue) {
      return failures(
        inputs.size(),
        isAccessException(exceptionValue) ? 'FORBIDDEN' : 'ERROR',
        isAccessException(exceptionValue)
          ? 'You do not have access to the requested package push records.'
          : 'Push-request analysis failed safely. Try again later.',
        false
      );
    }

    Map<String, List<AgentforcePushDiagnosticsQueryService.JobRecord>> jobsByRequest = jobsByRequest(
      jobs
    );
    Map<String, AgentforcePushDiagnosticsQueryService.JobRecord> jobsById = jobMap(
      jobs
    );
    Map<String, List<AgentforcePushDiagnosticsQueryService.ErrorRecord>> errorsByRequest = errorsByRequest(
      errors,
      jobsById
    );
    for (Selection selection : selections) {
      if (!selection.isValid) {
        results.add(
          failure(
            'INVALID_ID',
            'Provide a valid 15- or 18-character PackagePushRequest ID beginning with 0DV.',
            selection.replacementAttempted
          )
        );
        continue;
      }
      AgentforcePushDiagnosticsQueryService.RequestRecord requestRecord = requestsById.get(
        selection.requestId
      );
      if (requestRecord == null) {
        results.add(
          failure(
            'NOT_FOUND',
            'The PackagePushRequest was not found or is not accessible.',
            true
          )
        );
        continue;
      }
      List<AgentforcePushDiagnosticsQueryService.JobRecord> requestJobs = jobsByRequest.get(
        selection.requestId
      );
      if (requestJobs == null || requestJobs.isEmpty()) {
        Result noJobs = failure(
          'NO_JOBS',
          'The PackagePushRequest has no accessible PackagePushJob records.',
          selection.replacementAttempted
        );
        noJobs.pushRequestId = requestRecord.id;
        noJobs.targetPackageVersionId = requestRecord.packageVersionId;
        results.add(noJobs);
        continue;
      }

      List<String> resultWarnings = warnings.clone();
      if (jobsTruncated) {
        resultWarnings.add('The analysis scanned the first 2,000 jobs.');
      }
      if (errorsTruncated) {
        resultWarnings.add('The analysis scanned the first 10,000 error rows.');
      }
      String analysisJson = AgentforcePushDiagnosticsJsonService.buildComparison(
        selection.requestId,
        null,
        requestRecord,
        versionsById.get(requestRecord.packageVersionId),
        requestJobs,
        errorsByRequest.get(selection.requestId) ??
          new List<AgentforcePushDiagnosticsQueryService.ErrorRecord>(),
        jobsTruncated,
        errorsTruncated,
        resultWarnings
      );

      Result ready = new Result();
      ready.state = 'READY';
      ready.message = 'Authoritative push-request cohort context is ready.';
      ready.clearPreviousContext = selection.replacementAttempted;
      ready.pushRequestId = requestRecord.id;
      ready.targetPackageVersionId = requestRecord.packageVersionId;
      ready.analysisJson = boundComparisonJson(analysisJson);
      results.add(ready);
    }
    return results;
  }

  private static Selection selectRequest(Input input) {
    Selection selection = new Selection();
    String userInput = input?.userInput ?? '';
    Matcher matcher = Pattern.compile(
      '\\b0DV[a-zA-Z0-9]{12}(?:[a-zA-Z0-9]{3})?\\b'
    ).matcher(userInput);
    if (matcher.find()) {
      selection.isValid = true;
      selection.replacementAttempted = true;
      selection.requestId = matcher.group();
      return selection;
    }
    Matcher anyIdMatcher = Pattern.compile(
      '\\b[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?\\b'
    ).matcher(userInput);
    selection.replacementAttempted = anyIdMatcher.find() ||
      userInput.toLowerCase().contains('0dv');
    if (selection.replacementAttempted) {
      return selection;
    }
    if (isId(input?.currentPushRequestId, '0DV')) {
      selection.isValid = true;
      selection.requestId = input.currentPushRequestId;
      return selection;
    }
    selection.replacementAttempted = !String.isBlank(
      input?.currentPushRequestId
    );
    return selection;
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

  private static Map<String, AgentforcePushDiagnosticsQueryService.JobRecord> jobMap(
    List<AgentforcePushDiagnosticsQueryService.JobRecord> records
  ) {
    Map<String, AgentforcePushDiagnosticsQueryService.JobRecord> values = new Map<String, AgentforcePushDiagnosticsQueryService.JobRecord>();
    for (AgentforcePushDiagnosticsQueryService.JobRecord recordValue : records) {
      values.put(recordValue.id, recordValue);
    }
    return values;
  }

  private static Map<String, List<AgentforcePushDiagnosticsQueryService.JobRecord>> jobsByRequest(
    List<AgentforcePushDiagnosticsQueryService.JobRecord> records
  ) {
    Map<String, List<AgentforcePushDiagnosticsQueryService.JobRecord>> values = new Map<String, List<AgentforcePushDiagnosticsQueryService.JobRecord>>();
    for (AgentforcePushDiagnosticsQueryService.JobRecord recordValue : records) {
      if (!values.containsKey(recordValue.pushRequestId)) {
        values.put(
          recordValue.pushRequestId,
          new List<AgentforcePushDiagnosticsQueryService.JobRecord>()
        );
      }
      values.get(recordValue.pushRequestId).add(recordValue);
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

  private static String boundComparisonJson(String serialized) {
    if (serialized.length() < JSON_LIMIT) {
      return serialized;
    }
    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      serialized
    );
    for (
      String keyValue : new List<String>{
        'topFailureFamilies',
        'topFailureSignatures'
      }
    ) {
      List<Object> values = (List<Object>) payload.get(keyValue);
      while (
        JSON.serialize(payload).length() >= JSON_LIMIT &&
        values != null &&
        !values.isEmpty()
      ) {
        values.remove(values.size() - 1);
      }
    }
    payload.put('jsonTruncated', true);
    String bounded = JSON.serialize(payload);
    return bounded.length() < JSON_LIMIT
      ? bounded
      : JSON.serialize(
          new Map<String, Object>{
            'incomplete' => true,
            'warnings' => new List<String>{
              'Evidence exceeded the safe serialization budget.'
            }
          }
        );
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

  private static List<Result> failures(
    Integer countValue,
    String stateValue,
    String messageValue,
    Boolean clearValue
  ) {
    List<Result> values = new List<Result>();
    for (Integer indexValue = 0; indexValue < countValue; indexValue++) {
      values.add(failure(stateValue, messageValue, clearValue));
    }
    return values;
  }

  private static Result failure(
    String stateValue,
    String messageValue,
    Boolean clearValue
  ) {
    Result value = new Result();
    value.state = stateValue;
    value.message = messageValue;
    value.clearPreviousContext = clearValue == true;
    return value;
  }

  public class Input {
    public String userInput;
    public String currentPushRequestId;
  }

  public class Result {
    public String state;
    public String message;
    public Boolean clearPreviousContext;
    public String pushRequestId;
    public String targetPackageVersionId;
    public String analysisJson;
  }

  private class Selection {
    private Boolean isValid = false;
    private Boolean replacementAttempted = false;
    private String requestId;
  }
}
