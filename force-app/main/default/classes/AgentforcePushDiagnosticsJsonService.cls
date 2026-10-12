/**
 * Builds bounded, normalized JSON payloads for Agentforce push diagnostics.
 */
public with sharing class AgentforcePushDiagnosticsJsonService {
  private static final Integer MAX_DIAGNOSTIC_CHARACTERS = 60000;
  private static final Integer MAX_UNIQUE_ERRORS = 100;
  private static final Integer MAX_COMPARISON_SIGNATURES = 10;
  private static final Integer MAX_COMPARISON_FAMILIES = 10;
  private static final Integer MAX_SIGNATURE_SAMPLES = 3;
  private static final Integer MAX_ERROR_FIELD_CHARACTERS = 8000;

  /**
   * Builds the bounded diagnostic payload for one failed push job.
   *
   * @param job Authoritative job.
   * @param requestRecord Optional owning request.
   * @param versionRecord Optional target version.
   * @param subscriberRecord Optional subscriber enrichment.
   * @param errorRecords Authoritative error rows in server order.
   * @param warnings Optional enrichment and truncation warnings.
   * @param sourceErrorsTruncated Whether the source row scan was capped.
   * @return JSON below 60,000 characters.
   */
  public static String buildDiagnostic(
    AgentforcePushDiagnosticsQueryService.JobRecord job,
    AgentforcePushDiagnosticsQueryService.RequestRecord requestRecord,
    AgentforcePushDiagnosticsQueryService.VersionRecord versionRecord,
    AgentforcePushDiagnosticsQueryService.SubscriberRecord subscriberRecord,
    List<AgentforcePushDiagnosticsQueryService.ErrorRecord> errorRecords,
    List<String> warnings,
    Boolean sourceErrorsTruncated
  ) {
    Map<String, Object> payload = new Map<String, Object>{
      'packagePushJobId' => job.id,
      'packagePushRequestId' => job.pushRequestId,
      'targetPackageVersionId' => requestRecord?.packageVersionId,
      'metadataPackageId' => versionRecord?.packageId,
      'status' => job.status,
      'subscriberOrganizationKey' => job.subscriberOrgKey,
      'startTime' => job.startTime,
      'endTime' => job.endTime,
      'durationSeconds' => job.durationSeconds,
      'systemModstamp' => job.systemModstamp,
      'version' => versionMap(versionRecord),
      'subscriber' => subscriberMap(subscriberRecord),
      'sourceErrorsTruncated' => sourceErrorsTruncated == true,
      'scannedErrorRowCount' => errorRecords.size(),
      'warnings' => warnings
    };

    List<Map<String, Object>> uniqueErrors = collapseErrors(errorRecords);
    Integer omittedUniqueErrorCount = Math.max(
      0,
      uniqueErrors.size() - MAX_UNIQUE_ERRORS
    );
    if (uniqueErrors.size() > MAX_UNIQUE_ERRORS) {
      List<Map<String, Object>> cappedErrors = new List<Map<String, Object>>();
      for (
        Integer indexValue = 0; indexValue < MAX_UNIQUE_ERRORS; indexValue++
      ) {
        cappedErrors.add(uniqueErrors[indexValue]);
      }
      uniqueErrors = cappedErrors;
    }
    payload.put('errors', uniqueErrors);
    payload.put('includedUniqueErrorCount', uniqueErrors.size());
    payload.put('omittedUniqueErrorCount', omittedUniqueErrorCount);

    String serialized = JSON.serialize(payload);
    while (
      serialized.length() >= MAX_DIAGNOSTIC_CHARACTERS &&
      !uniqueErrors.isEmpty()
    ) {
      uniqueErrors.remove(uniqueErrors.size() - 1);
      omittedUniqueErrorCount++;
      payload.put('includedUniqueErrorCount', uniqueErrors.size());
      payload.put('omittedUniqueErrorCount', omittedUniqueErrorCount);
      serialized = JSON.serialize(payload);
    }
    return serialized;
  }

  /**
   * Builds ranked sibling failure signatures for a push request.
   *
   * @param pushRequestId Authoritative request ID.
   * @param selectedPushJobId Active selected job.
   * @param requestRecord Optional request enrichment.
   * @param versionRecord Optional version enrichment.
   * @param jobs Scanned sibling jobs.
   * @param errors Scanned sibling error rows.
   * @param jobsTruncated Whether job scan was capped.
   * @param errorsTruncated Whether error scan was capped.
   * @param warnings Optional enrichment and truncation warnings.
   * @return Ranked comparison JSON.
   */
  public static String buildComparison(
    String pushRequestId,
    String selectedPushJobId,
    AgentforcePushDiagnosticsQueryService.RequestRecord requestRecord,
    AgentforcePushDiagnosticsQueryService.VersionRecord versionRecord,
    List<AgentforcePushDiagnosticsQueryService.JobRecord> jobs,
    List<AgentforcePushDiagnosticsQueryService.ErrorRecord> errors,
    Boolean jobsTruncated,
    Boolean errorsTruncated,
    List<String> warnings
  ) {
    Map<String, Integer> statusCounts = new Map<String, Integer>();
    Map<String, AgentforcePushDiagnosticsQueryService.JobRecord> jobsById = new Map<String, AgentforcePushDiagnosticsQueryService.JobRecord>();
    for (AgentforcePushDiagnosticsQueryService.JobRecord job : jobs) {
      jobsById.put(job.id, job);
      String status = String.isBlank(job.status) ? 'Unknown' : job.status;
      statusCounts.put(
        status,
        (statusCounts.containsKey(status) ? statusCounts.get(status) : 0) + 1
      );
    }

    Map<String, SignatureSummary> summariesBySignature = new Map<String, SignatureSummary>();
    List<SignatureSummary> summaries = new List<SignatureSummary>();
    Map<String, FailureFamilySummary> familiesBySignature = new Map<String, FailureFamilySummary>();
    List<FailureFamilySummary> families = new List<FailureFamilySummary>();
    for (
      AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord : errors
    ) {
      String signature = errorSignature(errorRecord);
      SignatureSummary summary = summariesBySignature.get(signature);
      if (summary == null) {
        summary = new SignatureSummary(errorRecord);
        summariesBySignature.put(signature, summary);
        summaries.add(summary);
      }
      summary.addOccurrence(errorRecord, jobsById.get(errorRecord.jobId));

      String familySignature = normalizedErrorSignature(errorRecord);
      FailureFamilySummary family = familiesBySignature.get(familySignature);
      if (family == null) {
        family = new FailureFamilySummary(errorRecord);
        familiesBySignature.put(familySignature, family);
        families.add(family);
      }
      family.addOccurrence(errorRecord, jobsById.get(errorRecord.jobId));
    }
    summaries.sort();
    families.sort();

    List<Map<String, Object>> topSignatures = new List<Map<String, Object>>();
    Integer signatureLimit = Math.min(
      MAX_COMPARISON_SIGNATURES,
      summaries.size()
    );
    for (Integer indexValue = 0; indexValue < signatureLimit; indexValue++) {
      topSignatures.add(summaries[indexValue].toMap(selectedPushJobId));
    }

    List<Map<String, Object>> topFamilies = new List<Map<String, Object>>();
    Integer familyLimit = Math.min(MAX_COMPARISON_FAMILIES, families.size());
    for (Integer indexValue = 0; indexValue < familyLimit; indexValue++) {
      topFamilies.add(families[indexValue].toMap(selectedPushJobId));
    }

    return JSON.serialize(
      new Map<String, Object>{
        'packagePushRequestId' => pushRequestId,
        'targetPackageVersionId' => requestRecord?.packageVersionId,
        'metadataPackageId' => versionRecord?.packageId,
        'version' => versionMap(versionRecord),
        'selectedPackagePushJobId' => selectedPushJobId,
        'jobStatusCounts' => statusCounts,
        'scannedJobCount' => jobs.size(),
        'scannedErrorCount' => errors.size(),
        'jobsTruncated' => jobsTruncated == true,
        'errorsTruncated' => errorsTruncated == true,
        'topFailureSignatures' => topSignatures,
        'topFailureFamilies' => topFamilies,
        'similarityMethod' => 'DETERMINISTIC_VOLATILE_TOKEN_NORMALIZATION',
        'warnings' => warnings
      }
    );
  }

  private static List<Map<String, Object>> collapseErrors(
    List<AgentforcePushDiagnosticsQueryService.ErrorRecord> errorRecords
  ) {
    List<Map<String, Object>> groups = new List<Map<String, Object>>();
    Map<String, Map<String, Object>> groupsBySignature = new Map<String, Map<String, Object>>();
    for (
      AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord : errorRecords
    ) {
      String signature = errorSignature(errorRecord);
      Map<String, Object> groupValue = groupsBySignature.get(signature);
      if (groupValue == null) {
        groupValue = errorEvidence(errorRecord);
        groupValue.put('occurrenceCount', 0);
        groupValue.put('errorIds', new List<String>());
        groupsBySignature.put(signature, groupValue);
        groups.add(groupValue);
      }
      groupValue.put(
        'occurrenceCount',
        ((Integer) groupValue.get('occurrenceCount')) + 1
      );
      ((List<String>) groupValue.get('errorIds')).add(errorRecord.id);
    }
    return groups;
  }

  private static Map<String, Object> errorEvidence(
    AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord
  ) {
    Boolean fieldsTruncated =
      isTruncated(errorRecord.title) ||
      isTruncated(errorRecord.message) ||
      isTruncated(errorRecord.type) ||
      isTruncated(errorRecord.details) ||
      isTruncated(errorRecord.severity);
    return new Map<String, Object>{
      'title' => bounded(errorRecord.title),
      'message' => bounded(errorRecord.message),
      'type' => bounded(errorRecord.type),
      'details' => bounded(errorRecord.details),
      'severity' => bounded(errorRecord.severity),
      'fieldsTruncated' => fieldsTruncated
    };
  }

  private static String errorSignature(
    AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord
  ) {
    return JSON.serialize(
      new List<String>{
        safe(errorRecord.title),
        safe(errorRecord.message),
        safe(errorRecord.type),
        safe(errorRecord.details),
        safe(errorRecord.severity)
      }
    );
  }

  private static String normalizedErrorSignature(
    AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord
  ) {
    return JSON.serialize(
      new List<String>{
        normalizeVolatileTokens(errorRecord.title),
        normalizeVolatileTokens(errorRecord.message),
        normalizeVolatileTokens(errorRecord.type),
        normalizeVolatileTokens(errorRecord.details),
        normalizeVolatileTokens(errorRecord.severity)
      }
    );
  }

  private static String normalizeVolatileTokens(String value) {
    String normalized = safe(value);
    normalized = normalized.replaceAll(
      '(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\b',
      '<guid>'
    );
    normalized = normalized.replaceAll(
      '(?i)\\b[0-9][a-z0-9]{14}(?:[a-z0-9]{3})?\\b',
      '<salesforce_id>'
    );
    normalized = normalized.replaceAll('(?i)\\bline\\s+-?\\d+\\b', 'line <n>');
    normalized = normalized.replaceAll(
      '(?i)\\bcolumn\\s+-?\\d+\\b',
      'column <n>'
    );
    return normalized.toLowerCase().replaceAll('\\s+', ' ').trim();
  }

  private static Map<String, Object> normalizedErrorEvidence(
    AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord
  ) {
    return new Map<String, Object>{
      'normalizedTitle' => normalizeVolatileTokens(errorRecord.title),
      'normalizedMessage' => normalizeVolatileTokens(errorRecord.message),
      'normalizedType' => normalizeVolatileTokens(errorRecord.type),
      'normalizedDetails' => normalizeVolatileTokens(errorRecord.details),
      'normalizedSeverity' => normalizeVolatileTokens(errorRecord.severity)
    };
  }

  private static Map<String, Object> versionMap(
    AgentforcePushDiagnosticsQueryService.VersionRecord versionRecord
  ) {
    if (versionRecord == null) {
      return null;
    }
    return new Map<String, Object>{
      'id' => versionRecord.id,
      'name' => versionRecord.name,
      'metadataPackageId' => versionRecord.packageId,
      'releaseState' => versionRecord.releaseState,
      'majorVersion' => versionRecord.majorVersion,
      'minorVersion' => versionRecord.minorVersion,
      'patchVersion' => versionRecord.patchVersion,
      'buildNumber' => versionRecord.buildNumber
    };
  }

  private static Map<String, Object> subscriberMap(
    AgentforcePushDiagnosticsQueryService.SubscriberRecord subscriberRecord
  ) {
    if (subscriberRecord == null) {
      return null;
    }
    return new Map<String, Object>{
      'orgKey' => subscriberRecord.orgKey,
      'orgName' => subscriberRecord.orgName,
      'orgType' => subscriberRecord.orgType,
      'instanceName' => subscriberRecord.instanceName,
      'orgStatus' => subscriberRecord.orgStatus,
      'installedStatus' => subscriberRecord.installedStatus,
      'installedVersionId' => subscriberRecord.installedVersionId
    };
  }

  private static String bounded(String value) {
    if (value == null || value.length() <= MAX_ERROR_FIELD_CHARACTERS) {
      return value;
    }
    return value.substring(0, MAX_ERROR_FIELD_CHARACTERS);
  }

  private static Boolean isTruncated(String value) {
    return value != null && value.length() > MAX_ERROR_FIELD_CHARACTERS;
  }

  private static String safe(String value) {
    return value == null ? '' : value;
  }

  /** Ranked aggregation for one exact error signature. */
  private class SignatureSummary implements Comparable {
    private AgentforcePushDiagnosticsQueryService.ErrorRecord evidence;
    private Integer occurrenceCount = 0;
    private Set<String> affectedJobIds = new Set<String>();
    private List<Map<String, Object>> sampleJobs = new List<Map<String, Object>>();

    private SignatureSummary(
      AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord
    ) {
      evidence = errorRecord;
    }

    private void addOccurrence(
      AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord,
      AgentforcePushDiagnosticsQueryService.JobRecord job
    ) {
      occurrenceCount++;
      Boolean isNewJob = affectedJobIds.add(errorRecord.jobId);
      if (isNewJob && sampleJobs.size() < MAX_SIGNATURE_SAMPLES) {
        sampleJobs.add(
          new Map<String, Object>{
            'packagePushJobId' => errorRecord.jobId,
            'subscriberOrganizationKey' => job?.subscriberOrgKey
          }
        );
      }
    }

    public Integer compareTo(Object otherValue) {
      SignatureSummary other = (SignatureSummary) otherValue;
      Integer affectedComparison =
        other.affectedJobIds.size() - affectedJobIds.size();
      if (affectedComparison != 0) {
        return affectedComparison;
      }
      Integer occurrenceComparison = other.occurrenceCount - occurrenceCount;
      if (occurrenceComparison != 0) {
        return occurrenceComparison;
      }
      return errorSignature(evidence).compareTo(errorSignature(other.evidence));
    }

    private Map<String, Object> toMap(String selectedPushJobId) {
      Map<String, Object> value = errorEvidence(evidence);
      value.put('affectedJobCount', affectedJobIds.size());
      value.put('occurrenceCount', occurrenceCount);
      value.put(
        'affectsSelectedJob',
        affectedJobIds.contains(selectedPushJobId)
      );
      value.put('sampleJobs', sampleJobs);
      return value;
    }
  }

  /** Ranked aggregation for errors equal after volatile-token normalization. */
  private class FailureFamilySummary implements Comparable {
    private AgentforcePushDiagnosticsQueryService.ErrorRecord evidence;
    private Integer occurrenceCount = 0;
    private Set<String> affectedJobIds = new Set<String>();
    private Set<String> exactSignatures = new Set<String>();
    private List<Map<String, Object>> sampleJobs = new List<Map<String, Object>>();

    private FailureFamilySummary(
      AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord
    ) {
      evidence = errorRecord;
    }

    private void addOccurrence(
      AgentforcePushDiagnosticsQueryService.ErrorRecord errorRecord,
      AgentforcePushDiagnosticsQueryService.JobRecord job
    ) {
      occurrenceCount++;
      exactSignatures.add(errorSignature(errorRecord));
      Boolean isNewJob = affectedJobIds.add(errorRecord.jobId);
      if (isNewJob && sampleJobs.size() < MAX_SIGNATURE_SAMPLES) {
        sampleJobs.add(
          new Map<String, Object>{
            'packagePushJobId' => errorRecord.jobId,
            'subscriberOrganizationKey' => job?.subscriberOrgKey
          }
        );
      }
    }

    public Integer compareTo(Object otherValue) {
      FailureFamilySummary other = (FailureFamilySummary) otherValue;
      Integer affectedComparison =
        other.affectedJobIds.size() - affectedJobIds.size();
      if (affectedComparison != 0) {
        return affectedComparison;
      }
      Integer occurrenceComparison = other.occurrenceCount - occurrenceCount;
      if (occurrenceComparison != 0) {
        return occurrenceComparison;
      }
      return normalizedErrorSignature(evidence)
        .compareTo(normalizedErrorSignature(other.evidence));
    }

    private Map<String, Object> toMap(String selectedPushJobId) {
      Map<String, Object> value = normalizedErrorEvidence(evidence);
      value.put('affectedJobCount', affectedJobIds.size());
      value.put('occurrenceCount', occurrenceCount);
      value.put('exactVariantCount', exactSignatures.size());
      value.put(
        'affectsSelectedJob',
        affectedJobIds.contains(selectedPushJobId)
      );
      value.put('sampleJobs', sampleJobs);
      return value;
    }
  }
}
