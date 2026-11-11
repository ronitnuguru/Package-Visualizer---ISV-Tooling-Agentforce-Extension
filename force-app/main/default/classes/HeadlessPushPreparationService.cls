/** Validates selections and prepares undispatched standard push records and immutable Files. */
public with sharing class HeadlessPushPreparationService {
  public static HeadlessPushService.Result prepare(
    HeadlessPlanPushAction.Request input,
    HeadlessPushGateway gateway
  ) {
    HeadlessPushService.Result result = new HeadlessPushService.Result();
    try {
      gateway.authorize();
      if (input == null) {
        throw new HeadlessPushService.PushException(
          'Preparation input is required.'
        );
      }
      HeadlessPushSelectionService.Selection selected = HeadlessPushSelectionService.evaluate(
        input,
        gateway
      );
      if (selected.invalidCount > 0) {
        throw new HeadlessPushService.PushException(
          'Correct invalid org IDs before preparing.'
        );
      }
      if (
        String.isNotBlank(input.selectionFingerprint) &&
        input.selectionFingerprint != selected.fingerprint
      ) {
        throw new HeadlessPushService.PushException(
          'The preview cohort changed; preview and review it again.'
        );
      }
      if (selected.orgIds.isEmpty()) {
        throw new HeadlessPushService.PushException(
          'No eligible subscriber orgs matched; no request was created.'
        );
      }
      String targetId = HeadlessPushService.canonicalId(
        input.targetVersionId,
        '04t'
      );
      List<String> eligible = selected.orgIds;
      Map<String, String> rejected = selected.rejected;
      HeadlessPushService.Manifest manifest = new HeadlessPushService.Manifest();
      manifest.targetVersionId = targetId;
      if (String.isNotBlank(input.recoveryManifestVersionId)) {
        manifest.format = 'pkgviz-headless-push-v2';
        manifest.recoveryManifestVersionId = input.recoveryManifestVersionId;
        manifest.recoveryDigest = input.recoveryDigest;
      }
      manifest.scheduledStartTime = input.scheduledStartTime;
      manifest.immediate = input.scheduledStartTime == null;
      manifest.initiatorId = UserInfo.getUserId();
      manifest.orgIds = eligible;
      result.state = 'RECONCILIATION_REQUIRED';
      manifest.requestId = gateway.createRequest(
        targetId,
        input.scheduledStartTime
      );
      result.requestId = manifest.requestId;
      Map<String, Object> created = gateway.request(manifest.requestId);
      manifest.scheduledStartTime = (Datetime) JSON.deserialize(
        JSON.serialize(created.get('ScheduledStartTime')),
        Datetime.class
      );
      List<String> csvIds = new List<String>();
      for (String orgId : eligible) {
        csvIds.add(orgId.left(15));
      }
      manifest.csvVersionId = gateway.saveFile(
        'push-cohort-' + manifest.requestId + '.csv',
        String.join(csvIds, '\n') + '\n'
      );
      manifest.digest = HeadlessPushService.digest(manifest);
      String manifestId = gateway.saveFile(
        'push-manifest-' + manifest.requestId + '.json',
        JSON.serialize(manifest)
      );
      result = HeadlessPushService.baseResult(manifest, manifestId);
      result.excludedJson = JSON.serialize(rejected);
      result.detailsJson = JSON.serialize(
        new Map<String, Object>{
          'stagingJobId' => gateway.enqueue(manifestId, manifest.digest, 0)
        }
      );
      result.selectionFingerprint = selected.fingerprint;
      result.state = 'PREPARING';
      result.isSuccess = true;
    } catch (Exception error) {
      result.errorType = error.getTypeName();
      result.errorMessage = error.getMessage();
      if (result.state == null) {
        result.state = 'ERROR';
      }
    }
    return result;
  }

  public static void revalidateSubscribers(
    HeadlessPushService.Manifest manifest,
    Map<String, Object> target,
    HeadlessPushGateway gateway
  ) {
    Set<String> lower = HeadlessPushService.canonicalVersions(
      target.get('lowerVersionIds')
    );
    Set<String> ids = new Set<String>(manifest.orgIds);
    for (String orgId : manifest.orgIds) {
      ids.add(orgId.left(15));
    }
    List<Map<String, Object>> rows = gateway.subscribers(
      (String) target.get('packageId'),
      ids,
      new Set<String>(),
      null,
      null,
      null
    );
    Set<String> eligible = new Set<String>();
    for (Map<String, Object> row : rows) {
      String orgId = HeadlessPushService.canonicalId(
        (String) row.get('OrgKey'),
        '00D'
      );
      if (
        lower.contains(
          HeadlessPushService.canonicalId(
            (String) row.get('MetadataPackageVersionId'),
            '04t'
          )
        ) &&
        (row.get('HasRestrictionEnabled') != true ||
        row.get('IsCustomUpgradeAllowed') == true)
      ) {
        eligible.add(orgId);
      }
    }
    if (eligible != new Set<String>(manifest.orgIds)) {
      throw new HeadlessPushService.PushException(
        'Subscriber eligibility changed; prepare and review a new cohort.'
      );
    }
  }
}
