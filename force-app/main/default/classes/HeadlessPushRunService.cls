/** Operator-scoped manifest validation, discovery, and recovery-source checks. */
public with sharing class HeadlessPushRunService {
  public static HeadlessPushService.Manifest loadManifest(
    String manifestId,
    String expectedDigest,
    HeadlessPushGateway gateway
  ) {
    ContentVersion file = gateway.file(
      HeadlessPushService.canonicalId(manifestId, '068')
    );
    HeadlessPushService.Manifest manifest = (HeadlessPushService.Manifest) JSON.deserialize(
      file.VersionData.toString(),
      HeadlessPushService.Manifest.class
    );
    if (
      manifest == null ||
      !new Set<String>{ 'pkgviz-headless-push-v1', 'pkgviz-headless-push-v2' }
        .contains(manifest.format) ||
      manifest.initiatorId != UserInfo.getUserId() ||
      manifest.orgIds == null ||
      manifest.orgIds.isEmpty() ||
      manifest.orgIds.size() > HeadlessPushService.MAX_ORGS ||
      manifest.digest != expectedDigest ||
      HeadlessPushService.digest(manifest) != expectedDigest
    ) {
      throw new HeadlessPushService.PushException(
        'The prepared snapshot does not match the reviewed operator and digest.'
      );
    }
    if (
      manifest.format == 'pkgviz-headless-push-v2' &&
      (String.isBlank(manifest.recoveryManifestVersionId) ||
      String.isBlank(manifest.recoveryDigest))
    ) {
      throw new HeadlessPushService.PushException(
        'Recovery lineage is required.'
      );
    }
    if(manifest.format == 'pkgviz-headless-push-v1' && (manifest.recoveryManifestVersionId!=null || manifest.recoveryDigest!=null)){throw new HeadlessPushService.PushException('Recovery requires a versioned manifest.');}
    HeadlessPushService.canonicalId(manifest.requestId, '0DV');
    HeadlessPushService.canonicalId(manifest.targetVersionId, '04t');
    ContentVersion csv = gateway.file(
      HeadlessPushService.canonicalId(manifest.csvVersionId, '068')
    );
    if (
      HeadlessPushService.normalizeIds(csv.VersionData.toString()) !=
      manifest.orgIds
    ) {
      throw new HeadlessPushService.PushException(
        'The CSV does not match the prepared cohort.'
      );
    }
    return manifest;
  }

  public static Map<String, Object> validateRequest(
    HeadlessPushService.Manifest manifest,
    HeadlessPushGateway gateway
  ) {
    Map<String, Object> request = gateway.request(manifest.requestId);
    if (
      HeadlessPushService.canonicalId(
        (String) request.get('PackageVersionId'),
        '04t'
      ) != manifest.targetVersionId
    ) {
      throw new HeadlessPushService.PushException(
        'Target version changed since preparation.'
      );
    }
    Object scheduledValue = request.get('ScheduledStartTime');
    Datetime actual = scheduledValue == null
      ? null
      : (Datetime) JSON.deserialize(
          JSON.serialize(scheduledValue),
          Datetime.class
        );
    if (actual != manifest.scheduledStartTime) {
      throw new HeadlessPushService.PushException(
        'Scheduled start changed since preparation.'
      );
    }
    return request;
  }

  /** Lists metadata first; reads the immutable cohort only after an explicit selection. */
  public static HeadlessPushService.Result find(
    HeadlessFindPushRunsAction.Request input,
    HeadlessPushGateway gateway
  ) {
    if (input == null) {
      throw new HeadlessPushService.PushException(
        'Run lookup input is required.'
      );
    }
    if (String.isNotBlank(input.manifestVersionId)) {
      ContentVersion file = gateway.file(
        HeadlessPushService.canonicalId(input.manifestVersionId, '068')
      );
      HeadlessPushService.Manifest manifest = (HeadlessPushService.Manifest) JSON.deserialize(
        file.VersionData.toString(),
        HeadlessPushService.Manifest.class
      );
      manifest = loadManifest(
        input.manifestVersionId,
        manifest.digest,
        gateway
      );
      Map<String, Object> row = validateRequest(manifest, gateway);
      HeadlessPushService.Result result = HeadlessPushService.baseResult(
        manifest,
        input.manifestVersionId
      );
      result.state = (String) row.get('Status');
      result.isSuccess = true;
      return result;
    }
    String requestId = String.isBlank(input.requestId)
      ? null
      : HeadlessPushService.canonicalId(input.requestId, '0DV');
    String targetId = String.isBlank(input.targetVersionId)
      ? null
      : HeadlessPushService.canonicalId(input.targetVersionId, '04t');
    List<Map<String, Object>> files = gateway.manifests(
      requestId,
      input.beforeDate,
      input.beforeId
    );
    Set<String> requestIds = new Set<String>();
    Map<String, String> requestByFile = new Map<String, String>();
    for (Map<String, Object> file : files) {
      String title = (String) file.get('Title');
      Matcher matcher = Pattern.compile(
          '^push-manifest-(0DV[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?)\\.json$'
        )
        .matcher(title);
      if (matcher.matches()) {
        String idValue = HeadlessPushService.canonicalId(
          matcher.group(1),
          '0DV'
        );
        requestIds.add(idValue);
        requestByFile.put((String) file.get('Id'), idValue);
      }
    }
    Map<String, Map<String, Object>> requestsById = new Map<String, Map<String, Object>>();
    for (Map<String, Object> row : gateway.requests(requestIds)) {
      requestsById.put(
        HeadlessPushService.canonicalId((String) row.get('Id'), '0DV'),
        row
      );
    }
    Set<String> versionIds = new Set<String>();
    for (Map<String, Object> row : requestsById.values()) {
      versionIds.add(
        HeadlessPushService.canonicalId(
          (String) row.get('PackageVersionId'),
          '04t'
        )
      );
    }
    Map<String, String> labels = gateway.versionLabels(versionIds);
    List<Object> runs = new List<Object>();
    for (Map<String, Object> file : files) {
      String idValue = requestByFile.get((String) file.get('Id'));
      Map<String, Object> row = requestsById.get(idValue);
      if (
        row == null ||
        (targetId != null &&
        HeadlessPushService.canonicalId(
          (String) row.get('PackageVersionId'),
          '04t'
        ) != targetId)
      ) {
        continue;
      }
      runs.add(
        new Map<String, Object>{
          'requestId' => idValue,
          'manifestVersionId' => file.get('Id'),
          'createdAt' => file.get('CreatedDate'),
          'targetVersionId' => row.get('PackageVersionId'),
          'state' => row.get('Status'),
          'label' => (labels.get(HeadlessPushService.canonicalId((String)row.get('PackageVersionId'),'04t')) ?? String.valueOf(row.get('PackageVersionId'))) +
          ' / ' +
          String.valueOf(file.get('CreatedDate')) +
          ' / ' +
          idValue
        }
      );
    }
    HeadlessPushService.Result result = new HeadlessPushService.Result();
    result.isSuccess = true;
    result.state = 'RUNS';
    result.candidatesJson = JSON.serialize(runs);
    result.hasMore = files.size() == 10;
    if (!files.isEmpty()) {
      result.beforeId = (String) files[files.size() - 1].get('Id');
      result.beforeDate = (Datetime) JSON.deserialize(
        JSON.serialize(files[files.size() - 1].get('CreatedDate')),
        Datetime.class
      );
    }
    return result;
  }
  /** Returns only confirmed failures from a complete terminal source and reconciles competing attempts. */
  public static List<String> failedOrgIds(
    String manifestId,
    String digest,
    HeadlessPushGateway gateway
  ) {
    return failedOrgIds(manifestId, digest, gateway, true);
  }
  /** Dispatch uses the current request for overlap exclusion after verifying source outcomes. */
  public static List<String> failedOrgIds(
    String manifestId,
    String digest,
    HeadlessPushGateway gateway,
    Boolean checkOverlaps
  ) {
    HeadlessPushService.Manifest manifest = loadManifest(
      manifestId,
      digest,
      gateway
    );
    return failedOrgIds(manifest, gateway, checkOverlaps);
  }
  /** Reuses an already loaded source snapshot without rereading its Files. */
  public static List<String> failedOrgIds(
    HeadlessPushService.Manifest manifest,
    HeadlessPushGateway gateway,
    Boolean checkOverlaps
  ) {
    Map<String, Object> request = validateRequest(manifest, gateway);
    if (
      !new Set<String>{ 'Succeeded', 'Failed', 'Canceled' }
        .contains((String) request.get('Status'))
    ) {
      throw new HeadlessPushService.PushException(
        'Recovery requires a terminal original request.'
      );
    }
    Set<String> seen = new Set<String>();
    Set<String> failed = new Set<String>();
    for (Map<String, Object> job : gateway.jobs(manifest.requestId)) {
      String orgId = HeadlessPushService.canonicalId(
        (String) job.get('SubscriberOrganizationKey'),
        '00D'
      );
      if (!seen.add(orgId)) {
        throw new HeadlessPushService.PushException(
          'Duplicate source jobs require reconciliation.'
        );
      }
      String status = (String) job.get('Status');
      if (status == 'Failed') {
        failed.add(orgId);
      } else if (status != 'Succeeded' && status != 'Canceled') {
        throw new HeadlessPushService.PushException(
          'Pending or uncertain source outcomes require reconciliation.'
        );
      }
    }
    if (seen != new Set<String>(manifest.orgIds)) {
      throw new HeadlessPushService.PushException(
        'Source job cohort is incomplete or changed.'
      );
    }
    if (
      checkOverlaps &&
      !failed.isEmpty() &&
      !gateway.overlappingJobs(
          failed,
          manifest.targetVersionId,
          manifest.requestId
        )
        .isEmpty()
    ) {
      throw new HeadlessPushService.PushException(
        'Overlapping active or successful attempts require reconciliation.'
      );
    }
    List<String> values = new List<String>(failed);
    values.sort();
    return values;
  }
}
