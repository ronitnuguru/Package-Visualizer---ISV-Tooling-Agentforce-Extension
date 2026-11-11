/** Prepares and dispatches one bounded push using existing platform records and private Files. */
public with sharing class HeadlessPushService {
  @TestVisible
  private static HeadlessPushGateway gateway = new HeadlessPushGateway();
  public static final Integer MAX_ORGS = 2000;
  private static final String FORMAT = 'pkgviz-headless-push-v1';

  /** Immutable manifest VersionData binds request, target, schedule, operator, and cohort. */
  public class Manifest {
    public String format = HeadlessPushService.FORMAT;
    public String requestId;
    public String targetVersionId;
    public Datetime scheduledStartTime;
    public Boolean immediate = true;
    public String initiatorId;
    public String csvVersionId;
    public List<String> orgIds;
    public String digest;
    public String recoveryManifestVersionId, recoveryDigest;
  }

  /** Internal result; serialized into a stable global invocable response. */
  public class Result {
    public Boolean isSuccess = false;
    public Boolean immediate;
    public Datetime scheduledStartTime;
    public String targetVersionId;
    public String errorType,
      errorMessage,
      state,
      requestId,
      manifestVersionId,
      csvVersionId,
      digest;
    public String excludedJson, detailsJson, csvDownloadUrl, reportsJson;
    public Integer nextOffset;
    public String selectionFingerprint, candidatesJson, readinessJson;
    public Datetime capturedAt, beforeDate;
    public String beforeId;
    public Boolean hasMore;
    public Integer suppliedCount, duplicateCount, invalidCount, excludedCount;
    public Integer expectedCount = 0,
      stagedCount = 0,
      succeededCount = 0,
      failedCount = 0,
      pendingCount = 0;
  }
  public class PushException extends Exception {
  }

  /** Creates a prepared request and immutable snapshots, then starts asynchronous staging. */
  public static Result prepare(HeadlessPlanPushAction.Request input) {
    return HeadlessPushPreparationService.prepare(input, gateway);
  }

  /** Previews the cohort without persisting requests, Files, or jobs. */
  public static Result preview(HeadlessPlanPushAction.Request input) {
    try {
      gateway.authorize();
      return HeadlessPushSelectionService.preview(input, gateway);
    } catch (Exception error) {
      return failure(error.getTypeName(), error.getMessage());
    }
  }
  /** Resolves an exact target and explains authoritative readiness blockers. */
  public static Result resolve(HeadlessResolvePushTargetAction.Request input) {
    try {
      gateway.authorize();
      return HeadlessPushSelectionService.resolve(input, gateway);
    } catch (Exception error) {
      return failure(error.getTypeName(), error.getMessage());
    }
  }
  /** Finds only the current operator's manifest-backed runs. */
  public static Result find(HeadlessFindPushRunsAction.Request input) {
    try {
      gateway.authorize();
      return HeadlessPushRunService.find(input, gateway);
    } catch (Exception error) {
      return failure(error.getTypeName(), error.getMessage());
    }
  }

  /** Returns authoritative platform results; readiness requires exact cohort equality. */
  public static Result inspect(String manifestId, String expectedDigest) {
    return inspect(manifestId, expectedDigest, null);
  }

  /** Reads one ten-row page of details while retaining complete cohort counts. */
  public static Result inspect(
    String manifestId,
    String expectedDigest,
    Integer offset
  ) {
    try {
      if (offset != null && (offset < 0 || offset >= MAX_ORGS)) {
        throw new PushException('Invalid detail offset.');
      }
      gateway.authorize();
      Manifest manifest = HeadlessPushRunService.loadManifest(
        manifestId,
        expectedDigest,
        gateway
      );
      Map<String, Object> request = HeadlessPushRunService.validateRequest(
        manifest,
        gateway
      );
      List<Map<String, Object>> jobs = gateway.jobs(manifest.requestId);
      Result result = summarize(manifest, manifestId, request, jobs);
      pageDetails(result, jobs, offset == null ? 0 : offset);
      result.isSuccess = true;
      return result;
    } catch (Exception error) {
      return failure(error.getTypeName(), error.getMessage());
    }
  }

  /** Dispatches only after the external client obtained approval for this exact snapshot. */
  public static Result dispatch(
    String manifestId,
    String expectedDigest,
    Boolean confirmed
  ) {
    try {
      gateway.authorize();
      if (confirmed != true) {
        throw new PushException(
          'Native client approval is required before requesting execution.'
        );
      }
      Manifest manifest = HeadlessPushRunService.loadManifest(
        manifestId,
        expectedDigest,
        gateway
      );
      Map<String, Object> request = HeadlessPushRunService.validateRequest(
        manifest,
        gateway
      );
      Result result = summarize(
        manifest,
        manifestId,
        request,
        gateway.jobs(manifest.requestId)
      );
      String status = (String) request.get('Status');
      if (status != 'Created') {
        if (status == 'Canceled') {
          throw new PushException('A canceled request cannot be dispatched.');
        }
        result.isSuccess = true;
        return result;
      }
      if (result.state != 'READY') {
        throw new PushException(
          'The complete reviewed cohort has not been staged.'
        );
      }
      Map<String, Object> target = gateway.target(manifest.targetVersionId);
      HeadlessPushPreparationService.revalidateSubscribers(
        manifest,
        target,
        gateway
      );
      if (
        manifest.immediate != true &&
        manifest.scheduledStartTime != null &&
        manifest.scheduledStartTime <= System.now()
      ) {
        throw new PushException(
          'The reviewed scheduled time has passed; prepare and review a new request.'
        );
      }
      if (manifest.recoveryManifestVersionId != null) {
        Set<String> failures = new Set<String>(
          HeadlessPushRunService.failedOrgIds(
            manifest.recoveryManifestVersionId,
            manifest.recoveryDigest,
            gateway,
            false
          )
        );
        if (!failures.containsAll(new Set<String>(manifest.orgIds))) {
          throw new PushException(
            'Recovery source outcomes changed; prepare and review again.'
          );
        }
      }
      if (
        !gateway.overlappingJobs(
            new Set<String>(manifest.orgIds),
            manifest.targetVersionId,
            manifest.requestId
          )
          .isEmpty()
      ) {
        throw new PushException(
          'Another active or successful attempt overlaps this cohort; reconcile before dispatch.'
        );
      }
      gateway.setStatus(manifest.requestId, 'Pending');
      result.state = 'Pending';
      result.isSuccess = true;
      return result;
    } catch (Exception error) {
      return failure(error.getTypeName(), error.getMessage());
    }
  }

  /** Cancels a standard request without creating replacement jobs or changing the cohort. */
  public static Result cancel(String manifestId, String expectedDigest) {
    try {
      gateway.authorize();
      Manifest manifest = HeadlessPushRunService.loadManifest(
        manifestId,
        expectedDigest,
        gateway
      );
      Map<String, Object> request = HeadlessPushRunService.validateRequest(
        manifest,
        gateway
      );
      String status = (String) request.get('Status');
      if (status != 'Canceled') {
        if (status != 'Created' && status != 'Pending') {
          throw new PushException(
            'Only Created or Pending requests can be canceled; completed upgrades cannot be rolled back.'
          );
        }
        gateway.setStatus(manifest.requestId, 'Canceled');
      }
      Result result = baseResult(manifest, manifestId);
      result.state = 'Canceled';
      result.isSuccess = true;
      return result;
    } catch (Exception error) {
      return failure(error.getTypeName(), error.getMessage());
    }
  }

  /** Runs a chunk using an explicit integration boundary, restoring transaction-local context. */
  public static void stage(
    String manifestId,
    String expectedDigest,
    Integer offset,
    HeadlessPushGateway boundary
  ) {
    HeadlessPushGateway previous = gateway;
    try {
      gateway = boundary;
      stage(manifestId, expectedDigest, offset);
    } finally {
      gateway = previous;
    }
  }

  /** Runs one bounded chunk in a separate transaction; never automatically retries. */
  public static void stage(
    String manifestId,
    String expectedDigest,
    Integer offset
  ) {
    gateway.authorize();
    Manifest manifest = HeadlessPushRunService.loadManifest(
      manifestId,
      expectedDigest,
      gateway
    );
    if (
      offset == null ||
      offset < 0 ||
      Math.mod(offset, 200) != 0 ||
      offset >= manifest.orgIds.size()
    ) {
      throw new PushException('Invalid staging offset.');
    }
    Map<String, Object> request = HeadlessPushRunService.validateRequest(
      manifest,
      gateway
    );
    if ((String) request.get('Status') != 'Created') {
      return;
    }
    List<String> chunk = new List<String>();
    for (
      Integer index = offset;
      index < Math.min(offset + 200, manifest.orgIds.size());
      index++
    ) {
      chunk.add(manifest.orgIds[index]);
    }
    List<Object> outcomes;
    try {
      Set<String> existing = new Set<String>();
      for (Map<String, Object> job : gateway.jobs(manifest.requestId)) {
        existing.add(
          canonicalId((String) job.get('SubscriberOrganizationKey'), '00D')
        );
      }
      for (String orgId : chunk) {
        if (existing.contains(orgId)) {
          throw new PushException(
            'Jobs already exist for this chunk; reconcile before retrying.'
          );
        }
      }
      outcomes = gateway.stageChunk(manifest.requestId, chunk);
      if (outcomes.size() != chunk.size()) {
        throw new PushException(
          'Submission response was incomplete; reconcile before retrying.'
        );
      }
      Boolean complete = true;
      for (Object outcome : outcomes) {
        if (((Map<String, Object>) outcome).get('success') != true) {
          complete = false;
        }
      }
      if (!complete) {
        gateway.setStatus(manifest.requestId, 'Canceled');
        gateway.saveFile(
          'push-submission-errors-' +
            manifest.requestId +
            '-' +
            offset +
            '.json',
          JSON.serialize(outcomes)
        );
        return;
      }
    } catch (Exception error) {
      // A remote write may have committed. Leave Created and save evidence rather than replaying.
      gateway.saveFile(
        'push-reconciliation-' + manifest.requestId + '-' + offset + '.json',
        JSON.serialize(
          new Map<String, Object>{
            'requestId' => manifest.requestId,
            'offset' => offset,
            'state' => 'RECONCILIATION_REQUIRED',
            'errorType' => error.getTypeName(),
            'message' => error.getMessage()
          }
        )
      );
      return;
    }
    gateway.saveFile(
      'push-submission-' + manifest.requestId + '-' + offset + '.json',
      JSON.serialize(outcomes)
    );
    Integer nextOffset = offset + chunk.size();
    if (nextOffset < manifest.orgIds.size()) {
      gateway.enqueue(manifestId, expectedDigest, nextOffset);
    }
  }

  private static Result summarize(
    Manifest manifest,
    String manifestId,
    Map<String, Object> request,
    List<Map<String, Object>> jobs
  ) {
    Result result = baseResult(manifest, manifestId);
    result.state = (String) request.get('Status');
    result.reportsJson = JSON.serialize(
      gateway.reports(manifest.requestId, canonicalId(manifestId, '068'))
    );
    Set<String> staged = new Set<String>();
    for (Map<String, Object> job : jobs) {
      String orgId = canonicalId(
        (String) job.get('SubscriberOrganizationKey'),
        '00D'
      );
      if (staged.contains(orgId)) {
        throw new PushException(
          'Duplicate jobs exist; reconcile before dispatch.'
        );
      }
      staged.add(orgId);
      String status = (String) job.get('Status');
      if (status == 'Succeeded') {
        result.succeededCount++;
      } else if (
        status == 'Created' ||
        status == 'Pending' ||
        status == 'InProgress'
      ) {
        result.pendingCount++;
      } else {
        result.failedCount++;
      }
    }
    if (!new Set<String>(manifest.orgIds).containsAll(staged)) {
      throw new PushException('Unexpected orgs were added to this request.');
    }
    result.stagedCount = staged.size();
    if (result.state == 'Created') {
      result.state = staged == new Set<String>(manifest.orgIds)
        ? 'READY'
        : 'PREPARING_OR_RECONCILIATION_REQUIRED';
    }
    pageDetails(result, jobs, 0);
    return result;
  }

  private static void pageDetails(
    Result result,
    List<Map<String, Object>> jobs,
    Integer offset
  ) {
    List<Map<String, Object>> page = new List<Map<String, Object>>();
    for (
      Integer index = offset;
      index < Math.min(offset + 10, jobs.size());
      index++
    ) {
      page.add(jobs[index]);
    }
    result.nextOffset = offset + page.size() < jobs.size()
      ? offset + page.size()
      : null;
    Set<String> jobIds = new Set<String>();
    for (Map<String, Object> job : page) {
      jobIds.add((String) job.get('Id'));
    }
    result.detailsJson = JSON.serialize(
      gateway.jobDetails(result.requestId, jobIds)
    );
  }

  public static Result baseResult(Manifest manifest, String manifestId) {
    Result result = new Result();
    result.targetVersionId = manifest.targetVersionId;
    result.scheduledStartTime = manifest.scheduledStartTime;
    result.immediate = manifest.immediate;
    result.requestId = manifest.requestId;
    result.manifestVersionId = manifestId;
    result.csvVersionId = manifest.csvVersionId;
    result.digest = manifest.digest;
    result.csvDownloadUrl =
      URL.getOrgDomainUrl().toExternalForm() +
      '/sfc/servlet.shepherd/version/download/' +
      canonicalId(manifest.csvVersionId, '068');
    result.expectedCount = manifest.orgIds.size();
    return result;
  }

  /** Delegates shared cohort parsing and identity normalization. */
  public static List<String> normalizeIds(String text) {
    return HeadlessPushSelectionService.normalizeIds(text);
  }
  /** Returns the canonical identity shared by all cohort sources. */
  public static String canonicalId(String value, String prefix) {
    return HeadlessPushSelectionService.canonicalId(value, prefix);
  }

  public static Set<String> canonicalVersions(Object values) {
    return HeadlessPushSelectionService.canonicalVersions(values);
  }
  public static Boolean hasItems(List<String> items) {
    return items != null && !items.isEmpty();
  }

  /** Consistency digest of immutable manifest content, not a substitute for native human approval. */
  public static String digest(Manifest manifest) {
    List<Object> fields = new List<Object>{
      manifest.format,
      manifest.requestId,
      manifest.targetVersionId,
      manifest.scheduledStartTime,
      manifest.immediate,
      manifest.initiatorId,
      manifest.orgIds
    };
    if (manifest.format == 'pkgviz-headless-push-v2') {
      fields.add(manifest.recoveryManifestVersionId);
      fields.add(manifest.recoveryDigest);
    }
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(JSON.serialize(fields)))
    );
  }

  /** Returns a structured failure without scheduling side effects. */
  public static Result failure(String errorType, String errorMessage) {
    Result result = new Result();
    result.state = 'ERROR';
    result.errorType = errorType;
    result.errorMessage = errorMessage;
    return result;
  }
  /** Maps the internal result into the managed invocable contract. */
  public static HeadlessPushResponse response(Result result) {
    return (HeadlessPushResponse) JSON.deserialize(
      JSON.serialize(result),
      HeadlessPushResponse.class
    );
  }
}
