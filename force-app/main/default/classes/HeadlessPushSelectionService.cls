/** Shared, side-effect-free cohort selection for preview, preparation, and recovery. */
public with sharing class HeadlessPushSelectionService {
  /** Internal bounded selection; only preparation may persist it. */
  public class Selection {
    public List<String> orgIds = new List<String>();
    public List<String> invalid = new List<String>();
    public Map<String, String> rejected = new Map<String, String>();
    public Map<String, Object> target;
    public String fingerprint;
    public Integer suppliedCount = 0, duplicateCount = 0, invalidCount = 0;
  }
  /** Evaluates the same rules for every cohort source without writes. */
  public static Selection evaluate(
    HeadlessPlanPushAction.Request input,
    HeadlessPushGateway gateway
  ) {
    Selection selection = new Selection();
    if (input == null) {
      throw new HeadlessPushService.PushException(
        'Preparation input is required.'
      );
    }
    String targetId = HeadlessPushService.canonicalId(
      input.targetVersionId,
      '04t'
    );
    if (
      input.scheduledStartTime != null &&
      input.scheduledStartTime <= System.now()
    ) {
      throw new HeadlessPushService.PushException(
        'A scheduled start must be in the future; omit it for immediate dispatch after approval.'
      );
    }
    Boolean recovery = String.isNotBlank(input.recoveryManifestVersionId);
    Boolean explicit = String.isNotBlank(input.orgIdsText);
    Boolean fileInput = String.isNotBlank(input.sourceFileVersionId);
    if ((explicit && fileInput) || (recovery && (explicit || fileInput))) {
      throw new HeadlessPushService.PushException(
        'Choose pasted IDs, a CSV File, or subscriber filters.'
      );
    }
    if (
      (explicit || fileInput || recovery) &&
      (HeadlessPushService.hasItems(input.installedVersionIds) ||
      HeadlessPushService.hasItems(input.orgTypes) ||
      HeadlessPushService.hasItems(input.orgStatuses) ||
      HeadlessPushService.hasItems(input.instances))
    ) {
      throw new HeadlessPushService.PushException(
        'Do not combine explicit IDs or a CSV with subscriber filters.'
      );
    }
    if (
      !explicit &&
      !fileInput &&
      !recovery &&
      !HeadlessPushService.hasItems(input.orgTypes)
    ) {
      throw new HeadlessPushService.PushException(
        'Choose Sandbox, Production, or both for filter-based selection.'
      );
    }
    if (HeadlessPushService.hasItems(input.orgTypes)) {
      for (String kind : input.orgTypes) {
        if (kind != 'Sandbox' && kind != 'Production') {
          throw new HeadlessPushService.PushException(
            'Org types must be Sandbox or Production.'
          );
        }
      }
    }
    List<String> requested = explicit
      ? parse(input.orgIdsText, selection)
      : new List<String>();
    if (fileInput) {
      requested = parse(
        gateway.file(
            HeadlessPushService.canonicalId(input.sourceFileVersionId, '068')
          )
          .VersionData.toString(),
        selection
      );
    }
    if (recovery) {
      HeadlessPushService.Manifest source = HeadlessPushRunService.loadManifest(
        input.recoveryManifestVersionId,
        input.recoveryDigest,
        gateway
      );
      requested = HeadlessPushRunService.failedOrgIds(source, gateway, true);
      selection.suppliedCount = requested.size();
      if (source.targetVersionId != targetId) {
        throw new HeadlessPushService.PushException(
          'Recovery target must match the original run.'
        );
      }
    }
    if (
      (explicit ||
      fileInput ||
      recovery) &&
      requested.isEmpty() &&
      selection.invalidCount == 0
    ) {
      throw new HeadlessPushService.PushException('No org IDs were supplied.');
    }
    if (requested.size() > HeadlessPushService.MAX_ORGS) {
      throw new HeadlessPushService.PushException(
        'Narrow the selection to at most 2000 orgs.'
      );
    }
    Set<String> exclusions = new Set<String>(
      HeadlessPushService.normalizeIds(
        input.excludeOrgIds == null
          ? ''
          : String.join(input.excludeOrgIds, '\n')
      )
    );
    Map<String, Object> target = gateway.target(targetId);
    Set<String> lower = HeadlessPushService.canonicalVersions(
      target.get('lowerVersionIds')
    );
    if (HeadlessPushService.hasItems(input.installedVersionIds)) {
      Set<String> chosen = new Set<String>();
      for (String versionId : input.installedVersionIds) {
        String normalized = HeadlessPushService.canonicalId(versionId, '04t');
        if (!lower.contains(normalized)) {
          throw new HeadlessPushService.PushException(
            'Installed version filters must belong to the target package and be lower than the target.'
          );
        }
        chosen.add(normalized);
      }
      lower = chosen;
    }
    if (lower.isEmpty()) {
      throw new HeadlessPushService.PushException(
        'No lower installed versions are available for this target.'
      );
    }
    Set<String> queryIds = new Set<String>();
    for (String orgId : requested) {
      queryIds.add(orgId);
      queryIds.add(orgId.left(15));
    }
    List<Map<String, Object>> subscribers = requested.isEmpty() &&
      (explicit ||
      fileInput ||
      recovery)
      ? new List<Map<String, Object>>()
      : gateway.subscribers(
          (String) target.get('packageId'),
          queryIds,
          explicit || fileInput || recovery ? new Set<String>() : lower,
          input.orgTypes,
          input.orgStatuses,
          input.instances
        );
    Set<String> eligibleSet = new Set<String>();
    Map<String, String> rejected = new Map<String, String>();
    Set<String> found = new Set<String>();
    for (Map<String, Object> subscriber : subscribers) {
      String orgId = HeadlessPushService.canonicalId(
        (String) subscriber.get('OrgKey'),
        '00D'
      );
      found.add(orgId);
      if (exclusions.contains(orgId)) {
        rejected.put(orgId, 'EXCLUDED');
        continue;
      }
      String installed = HeadlessPushService.canonicalId(
        (String) subscriber.get('MetadataPackageVersionId'),
        '04t'
      );
      if (!lower.contains(installed)) {
        rejected.put(orgId, 'ALREADY_CURRENT_OR_NOT_LOWER');
        continue;
      }
      if (
        subscriber.get('HasRestrictionEnabled') == true &&
        subscriber.get('IsCustomUpgradeAllowed') != true
      ) {
        rejected.put(orgId, 'PUSH_RESTRICTED');
        continue;
      }
      eligibleSet.add(orgId);
    }
    for (String orgId : requested) {
      if (!found.contains(orgId)) {
        rejected.put(orgId, 'NOT_FOUND_FOR_PACKAGE');
      }
    }
    if (
      eligibleSet.size() > HeadlessPushService.MAX_ORGS ||
      subscribers.size() > HeadlessPushService.MAX_ORGS
    ) {
      throw new HeadlessPushService.PushException(
        'Selection exceeds 2000 matching orgs; narrow the filters.'
      );
    }

    List<String> eligible = new List<String>(eligibleSet);
    eligible.sort();
    selection.orgIds = eligible;
    selection.rejected = rejected;
    selection.target = target;
    selection.fingerprint = fingerprint(targetId, eligible);
    return selection;
  }
  private static List<String> parse(String text, Selection selection) {
    Set<String> ids = new Set<String>();
    if (String.isBlank(text)) {
      return new List<String>();
    }
    if (text.length() > 262144) {
      throw new HeadlessPushService.PushException('Input exceeds 256 KB.');
    }
    for (String token : text.trim().split('[,\\s]+')) {
      if (String.isBlank(token)) {
        continue;
      }
      selection.suppliedCount++;
      try {
        String orgId = HeadlessPushService.canonicalId(token, '00D');
        if (!ids.add(orgId)) {
          selection.duplicateCount++;
        }
      } catch (HeadlessPushService.PushException error) {
        selection.invalidCount++;
        if (selection.invalid.size() < 20) {
          selection.invalid.add(token.left(40));
        }
      }
    }
    List<String> result = new List<String>(ids);
    result.sort();
    return result;
  }
  private static String fingerprint(String targetId, List<String> orgIds) {
    return EncodingUtil.convertToHex(
      Crypto.generateDigest(
        'SHA-256',
        Blob.valueOf(
          JSON.serialize(
            new List<Object>{ UserInfo.getUserId(), targetId, orgIds }
          )
        )
      )
    );
  }
  /** Returns bounded evidence; full cohort remains server-side until preparation. */
  public static HeadlessPushService.Result preview(
    HeadlessPlanPushAction.Request input,
    HeadlessPushGateway gateway
  ) {
    Selection selected = evaluate(input, gateway);
    HeadlessPushService.Result result = new HeadlessPushService.Result();
    result.isSuccess = true;
    result.state = selected.invalidCount > 0 ? 'INVALID_INPUT' : 'PREVIEW';
    result.targetVersionId = input.targetVersionId;
    result.expectedCount = selected.orgIds.size();
    result.suppliedCount = selected.suppliedCount;
    result.duplicateCount = selected.duplicateCount;
    result.invalidCount = selected.invalidCount;
    result.excludedCount = selected.rejected.size();
    result.capturedAt = System.now();
    result.selectionFingerprint = selected.fingerprint;
    List<String> sample = new List<String>();
    for (Integer i = 0; i < Math.min(20, selected.orgIds.size()); i++) {
      sample.add(selected.orgIds[i]);
    }
    Map<String, String> exclusions = new Map<String, String>();
    List<String> keys = new List<String>(selected.rejected.keySet());
    keys.sort();
    for (Integer i = 0; i < Math.min(20, keys.size()); i++) {
      exclusions.put(keys[i], selected.rejected.get(keys[i]));
    }
    result.excludedJson = JSON.serialize(exclusions);
    result.detailsJson = JSON.serialize(
      new Map<String, Object>{
        'eligibleSample' => sample,
        'invalidSample' => selected.invalid,
        'samplesTruncated' => selected.orgIds.size() > 20 ||
        selected.rejected.size() > 20 ||
        selected.invalidCount > 20
      }
    );
    return result;
  }
  /** Uses narrow lookup and readiness data; ambiguity never selects a default version. */
  public static HeadlessPushService.Result resolve(
    HeadlessResolvePushTargetAction.Request input,
    HeadlessPushGateway gateway
  ) {
    if (input == null) {
      throw new HeadlessPushService.PushException(
        'Target selection is required.'
      );
    }
    Boolean latest =
      input.latestReleased == true ||
      (String.isNotBlank(input.versionNumber) &&
      input.versionNumber.trim().equalsIgnoreCase('latest'));
    if (
      latest &&
      (String.isNotBlank(input.targetVersionId) ||
      (String.isNotBlank(input.versionNumber) &&
      !input.versionNumber.trim().equalsIgnoreCase('latest')))
    ) {
      throw new HeadlessPushService.PushException(
        'Choose latest released or an exact version, not both.'
      );
    }
    List<Map<String, Object>> candidates;
    if (String.isNotBlank(input.targetVersionId)) {
      if (
        String.isNotBlank(input.packageName) ||
        String.isNotBlank(input.packageId) ||
        String.isNotBlank(input.versionNumber)
      ) {
        Map<String, Object> identity = gateway.targetIdentity(
          input.targetVersionId
        );
        HeadlessPushTargetLookup.validateIdentity(input, identity);
      }
      candidates = new List<Map<String, Object>>{
        new Map<String, Object>{
          'SubscriberPackageVersionId' => HeadlessPushService.canonicalId(
            input.targetVersionId,
            '04t'
          )
        }
      };
    } else {
      if (
        String.isBlank(input.packageName) && String.isBlank(input.packageId)
      ) {
        throw new HeadlessPushService.PushException(
          'Provide a package name or exact version ID.'
        );
      }
      if (String.isNotBlank(input.packageId) && !latest) {
        throw new HeadlessPushService.PushException(
          'A selected package ID is supported for latest released lookup.'
        );
      }
      candidates = latest
        ? (String.isBlank(input.packageId)
            ? gateway.lookupLatestReleased(input.packageName)
            : gateway.lookupLatestReleased(input.packageName, input.packageId))
        : gateway.lookupTargets(input.packageName, input.versionNumber);
    }
    HeadlessPushService.Result result = new HeadlessPushService.Result();
    result.isSuccess = true;
    result.candidatesJson = JSON.serialize(candidates);
    result.capturedAt = System.now();
    result.hasMore =
      candidates.size() > 10 || (latest && candidates.size() >= 2);
    if (candidates.size() != 1) {
      result.state = candidates.isEmpty() ? 'NOT_FOUND' : 'NEEDS_SELECTION';
      return result;
    }
    if (latest && candidates[0].get('noReleasedVersions') == true) {
      result.state = 'NO_RELEASED_VERSION';
      return result;
    }
    if (latest && candidates[0].get('SubscriberPackageVersionId') == null) {
      result.state = 'NEEDS_SELECTION';
      return result;
    }
    result.targetVersionId = (String) candidates[0]
      .get('SubscriberPackageVersionId');
    Map<String, Object> readiness = gateway.readiness(result.targetVersionId);
    result.readinessJson = JSON.serialize(readiness);
    result.state = readiness.get('eligible') == true ? 'RESOLVED' : 'BLOCKED';
    return result;
  }
  /** Normalizes known package version IDs into an efficient membership set. */
  public static Set<String> canonicalVersions(Object values) {
    Set<String> result = new Set<String>();
    for (
      Object value : (List<Object>) JSON.deserializeUntyped(
        JSON.serialize(values)
      )
    ) {
      result.add(HeadlessPushService.canonicalId((String) value, '04t'));
    }
    return result;
  }
  /** Normalizes strict CSV or comma/whitespace-separated IDs; invalid entries are reported, never dropped. */
  public static List<String> normalizeIds(String text) {
    Set<String> ids = new Set<String>();
    if (String.isBlank(text)) {
      return new List<String>();
    }
    for (String token : text.trim().split('[,\\s]+')) {
      if (String.isNotBlank(token)) {
        ids.add(canonicalId(token, '00D'));
      }
    }
    List<String> values = new List<String>(ids);
    values.sort();
    return values;
  }

  /** Canonical Salesforce IDs preserve case-sensitive 15-character identity. */
  public static String canonicalId(String value, String prefix) {
    if (
      String.isBlank(value) ||
      !Pattern.matches(
        '^' + prefix + '[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$',
        value.trim()
      )
    ) {
      throw new HeadlessPushService.PushException(
        'Invalid ' + prefix + ' Salesforce ID.'
      );
    }
    return String.valueOf(Id.valueOf(value.trim()));
  }

  /** Separates successful evidence retrieval from push eligibility without inventory scans. */
  public static Map<String, Object> readiness(
    String versionId,
    HeadlessPushGateway gateway
  ) {
    String idValue = HeadlessPushService.canonicalId(versionId, '04t');
    List<Object> rows = gateway.readinessFields(idValue);
    List<String> blockers = new List<String>();
    if (rows.isEmpty()) {
      blockers.add('Version not found in this Dev Hub.');
    } else {
      Map<String, Object> row = (Map<String, Object>) rows[0];
      if (row.get('HasPassedCodeCoverageCheck') != true) {
        blockers.add('Code coverage check has not passed.');
      }
      if (row.get('ValidationSkipped') == true) {
        blockers.add('Package validation was skipped.');
      }
    }
    try {
      gateway.targetHeader(idValue);
    } catch (HeadlessPushService.PushException error) {
      blockers.add(error.getMessage());
    }
    return new Map<String, Object>{
      'eligible' => blockers.isEmpty(),
      'blockers' => blockers,
      'capturedAt' => System.now()
    };
  }
}
