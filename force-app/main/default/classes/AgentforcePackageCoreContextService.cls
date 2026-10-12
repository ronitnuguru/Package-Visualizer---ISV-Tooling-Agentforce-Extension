/**
 * Read-only build, subscriber, and package-version context services for the
 * Package Visualizer Agent.
 */
public with sharing class AgentforcePackageCoreContextService {
  private static final Integer BUILD_SCAN_LIMIT = 2000;
  private static final Integer ERROR_SCAN_LIMIT = 10000;
  private static final Integer JSON_LIMIT = 60000;

  public static List<BuildResult> diagnoseBuilds(List<ContextInput> inputs) {
    List<BuildResult> results = new List<BuildResult>();
    if (inputs == null || inputs.isEmpty()) {
      return results;
    }
    if (!AgentforcePackageIntelligenceService.hasCorePermission()) {
      return buildFailures(
        inputs.size(),
        'FORBIDDEN',
        'You do not have access to Package Visualizer package build diagnostics.',
        false
      );
    }
    AgentforcePackageQueryService queryService = AgentforcePackageIntelligenceService.getQueryService();
    if (!queryService.isToolingAvailable()) {
      return buildFailures(
        inputs.size(),
        'UNAVAILABLE',
        'Package build diagnostic data is not available in this org.',
        false
      );
    }

    List<IdSelection> selections = new List<IdSelection>();
    Set<String> buildIds = new Set<String>();
    for (ContextInput input : inputs) {
      IdSelection selection = selectId(
        input?.userInput,
        input?.currentId,
        '08c'
      );
      selections.add(selection);
      if (selection.isValid) {
        buildIds.add(selection.idValue);
      }
    }

    Map<String, AgentforcePackageQueryService.BuildRecord> buildsById;
    Map<String, List<AgentforcePackageQueryService.BuildErrorRecord>> errorsByBuildId;
    Boolean errorsTruncated = false;
    try {
      buildsById = buildMap(queryService.getBuilds(buildIds));
      List<AgentforcePackageQueryService.BuildErrorRecord> errors = queryService.getBuildErrors(
        buildIds,
        ERROR_SCAN_LIMIT + 1
      );
      if (errors.size() > ERROR_SCAN_LIMIT) {
        errors.remove(errors.size() - 1);
        errorsTruncated = true;
      }
      errorsByBuildId = errorsByBuild(errors);
    } catch (Exception exceptionValue) {
      return buildQueryFailures(inputs.size(), exceptionValue);
    }

    for (IdSelection selection : selections) {
      if (!selection.isValid) {
        results.add(
          buildFailure(
            'INVALID_ID',
            'Provide a valid 15- or 18-character Package2VersionCreateRequest ID beginning with 08c.',
            selection.replacementAttempted
          )
        );
        continue;
      }
      AgentforcePackageQueryService.BuildRecord build = buildsById.get(
        selection.idValue
      );
      if (build == null) {
        results.add(
          buildFailure(
            'NOT_FOUND',
            'The package-version create request was not found or is not accessible.',
            true
          )
        );
        continue;
      }
      if (!isFailedBuild(build)) {
        BuildResult notFailed = buildFailure(
          'NOT_FAILED',
          'The selected package-version create request is not failed.',
          true
        );
        notFailed.buildRequestId = build.id;
        results.add(notFailed);
        continue;
      }
      List<AgentforcePackageQueryService.BuildErrorRecord> errors = errorsByBuildId.get(
        build.id
      );
      if (errors == null || errors.isEmpty()) {
        BuildResult noErrors = buildFailure(
          'NO_ERRORS',
          'The failed package-version create request has no accessible error records.',
          true
        );
        noErrors.buildRequestId = build.id;
        noErrors.package2Id = build.packageId;
        results.add(noErrors);
        continue;
      }
      BuildResult ready = new BuildResult();
      ready.state = 'READY';
      ready.message = 'Authoritative failed package-build context is ready.';
      ready.clearPreviousContext = selection.replacementAttempted;
      ready.buildRequestId = build.id;
      ready.package2Id = build.packageId;
      ready.package2VersionId = build.packageVersionId;
      ready.diagnosticJson = boundedJson(
        new Map<String, Object>{
          'capturedAt' => System.now(),
          'createRequest' => buildMap(build),
          'errors' => collapsedBuildErrors(errors, 100),
          'totalErrorCount' => errors.size(),
          'errorsTruncated' => errorsTruncated,
          'warnings' => errorsTruncated
            ? new List<String>{
                'The build error scan reached the 10,000-row cap.'
              }
            : new List<String>()
        },
        'errors'
      );
      results.add(ready);
    }
    return results;
  }

  public static List<BuildComparisonResult> compareBuilds(
    List<String> currentBuildIds
  ) {
    List<BuildComparisonResult> results = new List<BuildComparisonResult>();
    if (currentBuildIds == null || currentBuildIds.isEmpty()) {
      return results;
    }
    if (!AgentforcePackageIntelligenceService.hasCorePermission()) {
      return comparisonFailures(
        currentBuildIds.size(),
        'FORBIDDEN',
        'You do not have access to Package Visualizer package build comparisons.'
      );
    }
    AgentforcePackageQueryService queryService = AgentforcePackageIntelligenceService.getQueryService();
    Set<String> validIds = new Set<String>();
    for (String buildId : currentBuildIds) {
      if (isId(buildId, '08c')) {
        validIds.add(buildId);
      }
    }

    Map<String, AgentforcePackageQueryService.BuildRecord> selectedBuilds;
    List<AgentforcePackageQueryService.BuildRecord> scannedBuilds;
    List<AgentforcePackageQueryService.BuildErrorRecord> scannedErrors;
    Boolean buildsTruncated = false;
    Boolean errorsTruncated = false;
    try {
      selectedBuilds = buildMap(queryService.getBuilds(validIds));
      scannedBuilds = queryService.getRecentBuilds(BUILD_SCAN_LIMIT);
      buildsTruncated = scannedBuilds.size() >= BUILD_SCAN_LIMIT ||
        queryService.getRecentBuildCount() > scannedBuilds.size();
      Set<String> failedIds = new Set<String>();
      for (AgentforcePackageQueryService.BuildRecord build : scannedBuilds) {
        if (isFailedBuild(build)) {
          failedIds.add(build.id);
        }
      }
      scannedErrors = queryService.getBuildErrors(
        failedIds,
        ERROR_SCAN_LIMIT + 1
      );
      if (scannedErrors.size() > ERROR_SCAN_LIMIT) {
        scannedErrors.remove(scannedErrors.size() - 1);
        errorsTruncated = true;
      }
    } catch (Exception exceptionValue) {
      return comparisonQueryFailures(currentBuildIds.size(), exceptionValue);
    }

    for (String buildId : currentBuildIds) {
      if (!isId(buildId, '08c')) {
        results.add(
          comparisonFailure(
            'INVALID_ID',
            'Comparison requires a stored active 08c package-version create request ID.'
          )
        );
        continue;
      }
      AgentforcePackageQueryService.BuildRecord selected = selectedBuilds.get(
        buildId
      );
      if (selected == null) {
        results.add(
          comparisonFailure(
            'NOT_FOUND',
            'The active package-version create request was not found or is not accessible.'
          )
        );
        continue;
      }
      List<AgentforcePackageQueryService.BuildRecord> siblingBuilds = new List<AgentforcePackageQueryService.BuildRecord>();
      Set<String> siblingIds = new Set<String>();
      for (AgentforcePackageQueryService.BuildRecord build : scannedBuilds) {
        if (build.packageId == selected.packageId) {
          siblingBuilds.add(build);
          siblingIds.add(build.id);
        }
      }
      List<AgentforcePackageQueryService.BuildErrorRecord> siblingErrors = new List<AgentforcePackageQueryService.BuildErrorRecord>();
      for (AgentforcePackageQueryService.BuildErrorRecord errorRecord : scannedErrors) {
        if (siblingIds.contains(errorRecord.requestId)) {
          siblingErrors.add(errorRecord);
        }
      }

      BuildComparisonResult ready = new BuildComparisonResult();
      ready.state = 'READY';
      ready.message = 'Authoritative sibling package-build comparison is ready.';
      ready.buildRequestId = selected.id;
      ready.package2Id = selected.packageId;
      ready.comparisonJson = boundedJson(
        buildComparisonPayload(
          selected,
          siblingBuilds,
          siblingErrors,
          buildsTruncated,
          errorsTruncated
        ),
        'topFailureSignatures'
      );
      results.add(ready);
    }
    return results;
  }

  public static List<SubscriberResult> reviewSubscribers(
    List<ContextInput> inputs
  ) {
    List<SubscriberResult> results = new List<SubscriberResult>();
    if (inputs == null || inputs.isEmpty()) {
      return results;
    }
    if (!AgentforcePackageIntelligenceService.hasCorePermission()) {
      return subscriberFailures(
        inputs.size(),
        'FORBIDDEN',
        'You do not have access to Package Visualizer subscriber support.',
        false
      );
    }
    AgentforcePackageQueryService queryService = AgentforcePackageIntelligenceService.getQueryService();
    if (!queryService.isSubscriberAvailable()) {
      return subscriberFailures(
        inputs.size(),
        'UNAVAILABLE',
        'PackageSubscriber data is not available in this org.',
        false
      );
    }

    List<IdSelection> selections = new List<IdSelection>();
    Set<String> subscriberIds = new Set<String>();
    for (ContextInput input : inputs) {
      IdSelection selection = selectSubscriberId(
        input?.userInput,
        input?.currentId
      );
      selections.add(selection);
      if (selection.isValid) {
        subscriberIds.add(selection.idValue);
      }
    }
    Map<String, AgentforcePackageQueryService.SubscriberRecord> subscribersById;
    PushContext subscriberPushContext = new PushContext();
    try {
      subscribersById = subscriberMap(
        queryService.getSubscribers(subscriberIds)
      );
      Set<String> installedVersionIds = new Set<String>();
      for (AgentforcePackageQueryService.SubscriberRecord subscriberValue : subscribersById.values()) {
        if (!String.isBlank(subscriberValue.subscriberPackageVersionId)) {
          installedVersionIds.add(
            subscriberValue.subscriberPackageVersionId
          );
        }
      }
      subscriberPushContext = loadPushContext(
        queryService,
        installedVersionIds
      );
    } catch (Exception exceptionValue) {
      return subscriberQueryFailures(inputs.size(), exceptionValue);
    }

    for (IdSelection selection : selections) {
      if (!selection.isValid) {
        results.add(
          subscriberFailure(
            'INVALID_ID',
            'Provide a valid PackageSubscriber record ID.',
            selection.replacementAttempted
          )
        );
        continue;
      }
      AgentforcePackageQueryService.SubscriberRecord subscriber = subscribersById.get(
        selection.idValue
      );
      if (subscriber == null) {
        results.add(
          subscriberFailure(
            'NOT_FOUND',
            'The PackageSubscriber record was not found or is not accessible.',
            true
          )
        );
        continue;
      }
      SubscriberResult ready = new SubscriberResult();
      ready.state = 'READY';
      ready.message = 'Authoritative subscriber support context is ready.';
      ready.clearPreviousContext = selection.replacementAttempted;
      ready.packageSubscriberId = subscriber.id;
      ready.subscriberPackageId = subscriber.subscriberPackageId;
      ready.subscriberPackageVersionId =
        subscriber.subscriberPackageVersionId;
      ready.subscriberJson = JSON.serialize(
        subscriberMap(subscriber, subscriberPushContext)
      );
      results.add(ready);
    }
    return results;
  }

  public static List<VersionResult> assessVersions(List<ContextInput> inputs) {
    List<VersionResult> results = new List<VersionResult>();
    if (inputs == null || inputs.isEmpty()) {
      return results;
    }
    if (!AgentforcePackageIntelligenceService.hasCorePermission()) {
      return versionFailures(
        inputs.size(),
        'FORBIDDEN',
        'You do not have access to Package Visualizer package-version readiness.',
        false
      );
    }
    AgentforcePackageQueryService queryService = AgentforcePackageIntelligenceService.getQueryService();
    if (!queryService.isToolingAvailable()) {
      return versionFailures(
        inputs.size(),
        'UNAVAILABLE',
        'Package-version readiness data is not available in this org.',
        false
      );
    }

    List<IdSelection> selections = new List<IdSelection>();
    Set<String> versionIds = new Set<String>();
    for (ContextInput input : inputs) {
      IdSelection selection = selectId(
        input?.userInput,
        input?.currentId,
        '04t'
      );
      selections.add(selection);
      if (selection.isValid) {
        versionIds.add(selection.idValue);
      }
    }

    Map<String, AgentforcePackageQueryService.VersionRecord> versionsById;
    Map<String, List<String>> dependenciesById = new Map<String, List<String>>();
    List<AgentforcePackageQueryService.SubscriberAggregate> subscriberAggregates = new List<AgentforcePackageQueryService.SubscriberAggregate>();
    List<String> sharedWarnings = new List<String>();
    PushContext versionPushContext = new PushContext();
    try {
      versionsById = versionMap(
        queryService.getVersionsBySubscriberIds(versionIds)
      );
      try {
        dependenciesById = queryService.getDependencies(versionIds);
      } catch (Exception ignored) {
        sharedWarnings.add('Dependency enrichment is unavailable.');
      }
      Set<String> subscriberPackageIds = new Set<String>();
      List<AgentforcePackageQueryService.PackageRecord> packages = queryService.getActivePackages(
        500
      );
      Map<String, AgentforcePackageQueryService.PackageRecord> packagesById = new Map<String, AgentforcePackageQueryService.PackageRecord>();
      for (AgentforcePackageQueryService.PackageRecord packageRecord : packages) {
        packagesById.put(packageRecord.id, packageRecord);
      }
      for (AgentforcePackageQueryService.VersionRecord versionRecord : versionsById.values()) {
        String subscriberPackageId = packagesById.get(
          versionRecord.packageId
        )?.subscriberPackageId;
        if (!String.isBlank(subscriberPackageId)) {
          subscriberPackageIds.add(subscriberPackageId);
        }
      }
      try {
        subscriberAggregates = queryService.getSubscriberAggregates(
          subscriberPackageIds
        );
      } catch (Exception ignored) {
        sharedWarnings.add('Subscriber-impact enrichment is unavailable.');
      }
      versionPushContext = loadPushContext(queryService, versionIds);
      sharedWarnings.addAll(versionPushContext.warnings);
    } catch (Exception exceptionValue) {
      return versionQueryFailures(inputs.size(), exceptionValue);
    }

    for (IdSelection selection : selections) {
      if (!selection.isValid) {
        results.add(
          versionFailure(
            'INVALID_ID',
            'Provide a valid 15- or 18-character SubscriberPackageVersion ID beginning with 04t.',
            selection.replacementAttempted
          )
        );
        continue;
      }
      AgentforcePackageQueryService.VersionRecord versionRecord = versionsById.get(
        selection.idValue
      );
      if (versionRecord == null) {
        results.add(
          versionFailure(
            'NOT_FOUND',
            'The package version was not found or is not accessible.',
            true
          )
        );
        continue;
      }
      List<String> dependencies = dependenciesById.get(selection.idValue) ??
        new List<String>();
      List<String> blockers = new List<String>();
      if (versionRecord.isReleased != true) {
        blockers.add('The package version is not released.');
      }
      if (versionRecord.hasPassedCodeCoverageCheck != true) {
        blockers.add('The package version has not passed its code coverage check.');
      }
      if (versionRecord.validationSkipped == true) {
        blockers.add('Package validation was skipped.');
      }
      Integer subscriberCount = subscriberCountForVersion(
        subscriberAggregates,
        selection.idValue
      );
      VersionResult ready = new VersionResult();
      ready.state = 'READY';
      ready.message = 'Authoritative package-version readiness context is ready.';
      ready.clearPreviousContext = selection.replacementAttempted;
      ready.subscriberPackageVersionId = selection.idValue;
      ready.package2Id = versionRecord.packageId;
      ready.readinessJson = JSON.serialize(
        new Map<String, Object>{
          'capturedAt' => System.now(),
          'package2Id' => versionRecord.packageId,
          'subscriberPackageVersionId' => selection.idValue,
          'package2VersionId' => versionRecord.id,
          'version' => versionMap(versionRecord),
          'dependencies' => dependencies,
          'subscriberCount' => subscriberCount,
          'blockers' => blockers,
          'pushEnrichmentIncluded' => versionPushContext.included,
          'pushOutcomes' => pushMap(
            versionPushContext,
            selection.idValue
          ),
          'securityReviewStatus' => 'UNKNOWN',
          'warnings' => sharedWarnings.clone()
        }
      );
      results.add(ready);
    }
    return results;
  }

  private static IdSelection selectId(
    String userInput,
    String currentId,
    String prefix
  ) {
    IdSelection selection = new IdSelection();
    Matcher matcher = Pattern.compile(
      '\\b' + prefix + '[a-zA-Z0-9]{12}(?:[a-zA-Z0-9]{3})?\\b'
    ).matcher(userInput ?? '');
    if (matcher.find()) {
      selection.isValid = true;
      selection.replacementAttempted = true;
      selection.idValue = matcher.group();
      return selection;
    }
    Matcher anyIdMatcher = Pattern.compile(
      '\\b[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?\\b'
    ).matcher(userInput ?? '');
    selection.replacementAttempted = anyIdMatcher.find() ||
      (userInput ?? '').toLowerCase().contains(prefix.toLowerCase());
    if (selection.replacementAttempted) {
      return selection;
    }
    if (isId(currentId, prefix)) {
      selection.isValid = true;
      selection.idValue = currentId;
      return selection;
    }
    selection.replacementAttempted = !String.isBlank(currentId);
    return selection;
  }

  private static IdSelection selectSubscriberId(
    String userInput,
    String currentId
  ) {
    IdSelection selection = new IdSelection();
    Matcher matcher = Pattern.compile(
      '\\b[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?\\b'
    ).matcher(userInput ?? '');
    if (matcher.find()) {
      selection.replacementAttempted = true;
      selection.idValue = matcher.group();
      selection.isValid = !hasSpecializedPrefix(selection.idValue);
      return selection;
    }
    if (isGenericId(currentId) && !hasSpecializedPrefix(currentId)) {
      selection.isValid = true;
      selection.idValue = currentId;
      return selection;
    }
    selection.replacementAttempted = !String.isBlank(currentId);
    return selection;
  }

  private static Boolean hasSpecializedPrefix(String value) {
    for (String prefix : new List<String>{ '0Ho', '033', '04t', '08c', '0DV', '0DX' }) {
      if (value.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  private static Map<String, AgentforcePackageQueryService.BuildRecord> buildMap(
    List<AgentforcePackageQueryService.BuildRecord> values
  ) {
    Map<String, AgentforcePackageQueryService.BuildRecord> results = new Map<String, AgentforcePackageQueryService.BuildRecord>();
    for (AgentforcePackageQueryService.BuildRecord value : values) {
      results.put(value.id, value);
    }
    return results;
  }

  private static Map<String, List<AgentforcePackageQueryService.BuildErrorRecord>> errorsByBuild(
    List<AgentforcePackageQueryService.BuildErrorRecord> errors
  ) {
    Map<String, List<AgentforcePackageQueryService.BuildErrorRecord>> values = new Map<String, List<AgentforcePackageQueryService.BuildErrorRecord>>();
    for (AgentforcePackageQueryService.BuildErrorRecord errorRecord : errors) {
      if (!values.containsKey(errorRecord.requestId)) {
        values.put(
          errorRecord.requestId,
          new List<AgentforcePackageQueryService.BuildErrorRecord>()
        );
      }
      values.get(errorRecord.requestId).add(errorRecord);
    }
    return values;
  }

  private static Map<String, AgentforcePackageQueryService.SubscriberRecord> subscriberMap(
    List<AgentforcePackageQueryService.SubscriberRecord> values
  ) {
    Map<String, AgentforcePackageQueryService.SubscriberRecord> results = new Map<String, AgentforcePackageQueryService.SubscriberRecord>();
    for (AgentforcePackageQueryService.SubscriberRecord value : values) {
      results.put(value.id, value);
    }
    return results;
  }

  private static Map<String, AgentforcePackageQueryService.VersionRecord> versionMap(
    List<AgentforcePackageQueryService.VersionRecord> values
  ) {
    Map<String, AgentforcePackageQueryService.VersionRecord> results = new Map<String, AgentforcePackageQueryService.VersionRecord>();
    for (AgentforcePackageQueryService.VersionRecord value : values) {
      results.put(value.subscriberPackageVersionId, value);
    }
    return results;
  }

  private static Map<String, Object> buildMap(
    AgentforcePackageQueryService.BuildRecord value
  ) {
    return new Map<String, Object>{
      'createRequestId' => value.id,
      'status' => value.status,
      'package2Id' => value.packageId,
      'package2VersionId' => value.packageVersionId,
      'branch' => value.branch,
      'tag' => value.tag,
      'language' => value.language,
      'asyncValidation' => value.asyncValidation,
      'calculateCodeCoverage' => value.calculateCodeCoverage,
      'calculateTransitiveDependencies' => value.calculateTransitiveDependencies,
      'skipValidation' => value.skipValidation,
      'createdDate' => value.createdDate,
      'systemModstamp' => value.systemModstamp
    };
  }

  private static Map<String, Object> subscriberMap(
    AgentforcePackageQueryService.SubscriberRecord value,
    PushContext pushContext
  ) {
    return new Map<String, Object>{
      'capturedAt' => System.now(),
      'packageSubscriberId' => value.id,
      'subscriberPackageId' => value.subscriberPackageId,
      'installedPackageVersionId' => value.subscriberPackageVersionId,
      'installedStatus' => value.installedStatus,
      'orgKey' => value.orgKey,
      'orgName' => value.orgName,
      'orgType' => value.orgType,
      'orgStatus' => value.orgStatus,
      'instanceName' => value.instanceName,
      'parentOrg' => value.parentOrg,
      'customUpgradeType' => value.customUpgradeType,
      'hasRestrictionEnabled' => value.hasRestrictionEnabled,
      'isCustomUpgradeAllowed' => value.isCustomUpgradeAllowed,
      'systemModstamp' => value.systemModstamp,
      'pushEnrichmentIncluded' => pushContext.included,
      'pushOutcomes' => pushMap(
        pushContext,
        value.subscriberPackageVersionId
      ),
      'warnings' => pushContext.warnings.clone()
    };
  }

  private static PushContext loadPushContext(
    AgentforcePackageQueryService queryService,
    Set<String> subscriberVersionIds
  ) {
    PushContext contextValue = new PushContext();
    if (!AgentforcePushDiagnosticsService.hasPermission()) {
      return contextValue;
    }
    if (!queryService.isPushAvailable()) {
      contextValue.warnings.add('Push-outcome enrichment is unavailable.');
      return contextValue;
    }
    try {
      for (AgentforcePackageQueryService.PushAggregate aggregateValue : queryService.getPushAggregates(
        subscriberVersionIds
      )) {
        contextValue.byVersionId.put(
          aggregateValue.subscriberPackageVersionId,
          aggregateValue
        );
      }
      contextValue.included = true;
    } catch (Exception ignored) {
      contextValue.warnings.add('Push-outcome enrichment is unavailable.');
    }
    return contextValue;
  }

  private static Map<String, Object> pushMap(
    PushContext contextValue,
    String subscriberVersionId
  ) {
    AgentforcePackageQueryService.PushAggregate aggregateValue = contextValue.byVersionId.get(
      subscriberVersionId
    );
    return aggregateValue == null
      ? new Map<String, Object>{
          'requestCount' => 0,
          'jobCount' => 0,
          'requestStatusCounts' => new Map<String, Integer>(),
          'jobStatusCounts' => new Map<String, Integer>()
        }
      : new Map<String, Object>{
          'requestCount' => aggregateValue.requestCount,
          'jobCount' => aggregateValue.jobCount,
          'requestStatusCounts' => aggregateValue.requestStatusCounts,
          'jobStatusCounts' => aggregateValue.jobStatusCounts
        };
  }

  private static Map<String, Object> versionMap(
    AgentforcePackageQueryService.VersionRecord value
  ) {
    return new Map<String, Object>{
      'isReleased' => value.isReleased,
      'hasPassedCodeCoverageCheck' => value.hasPassedCodeCoverageCheck,
      'validationSkipped' => value.validationSkipped,
      'majorVersion' => value.majorVersion,
      'minorVersion' => value.minorVersion,
      'patchVersion' => value.patchVersion,
      'buildNumber' => value.buildNumber,
      'branch' => value.branch,
      'tag' => value.tag,
      'createdDate' => value.createdDate
    };
  }

  private static List<Map<String, Object>> collapsedBuildErrors(
    List<AgentforcePackageQueryService.BuildErrorRecord> errors,
    Integer uniqueLimit
  ) {
    List<Map<String, Object>> values = new List<Map<String, Object>>();
    Map<String, Map<String, Object>> byMessage = new Map<String, Map<String, Object>>();
    for (AgentforcePackageQueryService.BuildErrorRecord errorRecord : errors) {
      String signature = errorRecord.message ?? '';
      Map<String, Object> summary = byMessage.get(signature);
      if (summary == null) {
        if (values.size() == uniqueLimit) {
          continue;
        }
        summary = new Map<String, Object>{
          'message' => errorRecord.message,
          'occurrenceCount' => 0,
          'errorIds' => new List<String>()
        };
        byMessage.put(signature, summary);
        values.add(summary);
      }
      summary.put(
        'occurrenceCount',
        ((Integer) summary.get('occurrenceCount')) + 1
      );
      ((List<String>) summary.get('errorIds')).add(errorRecord.id);
    }
    return values;
  }

  private static Map<String, Object> buildComparisonPayload(
    AgentforcePackageQueryService.BuildRecord selected,
    List<AgentforcePackageQueryService.BuildRecord> builds,
    List<AgentforcePackageQueryService.BuildErrorRecord> errors,
    Boolean buildsTruncated,
    Boolean errorsTruncated
  ) {
    Map<String, Set<String>> buildsBySignature = new Map<String, Set<String>>();
    Map<String, Integer> occurrencesBySignature = new Map<String, Integer>();
    for (AgentforcePackageQueryService.BuildErrorRecord errorRecord : errors) {
      String signature = errorRecord.message ?? '';
      if (!buildsBySignature.containsKey(signature)) {
        buildsBySignature.put(signature, new Set<String>());
        occurrencesBySignature.put(signature, 0);
      }
      buildsBySignature.get(signature).add(errorRecord.requestId);
      occurrencesBySignature.put(
        signature,
        occurrencesBySignature.get(signature) + 1
      );
    }
    List<BuildSignatureSummary> summaries = new List<BuildSignatureSummary>();
    for (String signature : buildsBySignature.keySet()) {
      summaries.add(
        new BuildSignatureSummary(
          signature,
          buildsBySignature.get(signature),
          occurrencesBySignature.get(signature),
          selected.id
        )
      );
    }
    summaries.sort();
    List<Map<String, Object>> topSignatures = new List<Map<String, Object>>();
    for (
      Integer indexValue = 0;
      indexValue < Math.min(10, summaries.size());
      indexValue++
    ) {
      topSignatures.add(summaries[indexValue].toMap());
    }
    Map<String, Integer> statusCounts = new Map<String, Integer>();
    for (AgentforcePackageQueryService.BuildRecord build : builds) {
      String status = String.isBlank(build.status) ? 'Unknown' : build.status;
      statusCounts.put(
        status,
        (statusCounts.get(status) == null ? 0 : statusCounts.get(status)) + 1
      );
    }
    return new Map<String, Object>{
      'capturedAt' => System.now(),
      'package2Id' => selected.packageId,
      'selectedCreateRequestId' => selected.id,
      'scannedCreateRequestCount' => builds.size(),
      'scannedErrorCount' => errors.size(),
      'createRequestsTruncated' => buildsTruncated,
      'errorsTruncated' => errorsTruncated,
      'buildStatusCounts' => statusCounts,
      'topFailureSignatures' => topSignatures,
      'warnings' => new List<String>()
    };
  }

  private static Integer subscriberCountForVersion(
    List<AgentforcePackageQueryService.SubscriberAggregate> aggregates,
    String subscriberVersionId
  ) {
    Integer countValue = 0;
    for (AgentforcePackageQueryService.SubscriberAggregate aggregateValue : aggregates) {
      if (
        aggregateValue.subscriberPackageVersionId == subscriberVersionId
      ) {
        countValue += aggregateValue.subscriberCount;
      }
    }
    return countValue;
  }

  private static String boundedJson(
    Map<String, Object> payload,
    String removableKey
  ) {
    String serialized = JSON.serialize(payload);
    List<Object> removable = (List<Object>) payload.get(removableKey);
    while (
      serialized.length() >= JSON_LIMIT &&
      removable != null &&
      !removable.isEmpty()
    ) {
      removable.remove(removable.size() - 1);
      serialized = JSON.serialize(payload);
    }
    return serialized.length() < JSON_LIMIT
      ? serialized
      : JSON.serialize(
          new Map<String, Object>{
            'incomplete' => true,
            'warnings' => new List<String>{
              'Evidence exceeded the safe serialization budget.'
            }
          }
        );
  }

  private static Boolean isFailedBuild(
    AgentforcePackageQueryService.BuildRecord value
  ) {
    return 'Error'.equalsIgnoreCase(value.status) ||
      'Failed'.equalsIgnoreCase(value.status);
  }

  private static Boolean isId(String value, String prefix) {
    return value != null &&
      Pattern.matches(
        '^' + prefix + '[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$',
        value
      );
  }

  private static Boolean isGenericId(String value) {
    return value != null &&
      Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', value);
  }

  private static Boolean isAccessException(Exception exceptionValue) {
    String typeName = exceptionValue.getTypeName();
    return typeName != null && typeName.toLowerCase().contains('noaccess');
  }

  private static List<BuildResult> buildQueryFailures(
    Integer countValue,
    Exception exceptionValue
  ) {
    return buildFailures(
      countValue,
      isAccessException(exceptionValue) ? 'FORBIDDEN' : 'ERROR',
      isAccessException(exceptionValue)
        ? 'You do not have access to the requested package build records.'
        : 'Package build diagnosis failed safely. Try again later.',
      false
    );
  }

  private static List<BuildResult> buildFailures(
    Integer countValue,
    String stateValue,
    String messageValue,
    Boolean clearValue
  ) {
    List<BuildResult> values = new List<BuildResult>();
    for (Integer indexValue = 0; indexValue < countValue; indexValue++) {
      values.add(buildFailure(stateValue, messageValue, clearValue));
    }
    return values;
  }

  private static BuildResult buildFailure(
    String stateValue,
    String messageValue,
    Boolean clearValue
  ) {
    BuildResult value = new BuildResult();
    value.state = stateValue;
    value.message = messageValue;
    value.clearPreviousContext = clearValue == true;
    return value;
  }

  private static List<BuildComparisonResult> comparisonQueryFailures(
    Integer countValue,
    Exception exceptionValue
  ) {
    return comparisonFailures(
      countValue,
      isAccessException(exceptionValue) ? 'FORBIDDEN' : 'ERROR',
      isAccessException(exceptionValue)
        ? 'You do not have access to the requested package build records.'
        : 'Package build comparison failed safely. Try again later.'
    );
  }

  private static List<BuildComparisonResult> comparisonFailures(
    Integer countValue,
    String stateValue,
    String messageValue
  ) {
    List<BuildComparisonResult> values = new List<BuildComparisonResult>();
    for (Integer indexValue = 0; indexValue < countValue; indexValue++) {
      values.add(comparisonFailure(stateValue, messageValue));
    }
    return values;
  }

  private static BuildComparisonResult comparisonFailure(
    String stateValue,
    String messageValue
  ) {
    BuildComparisonResult value = new BuildComparisonResult();
    value.state = stateValue;
    value.message = messageValue;
    return value;
  }

  private static List<SubscriberResult> subscriberQueryFailures(
    Integer countValue,
    Exception exceptionValue
  ) {
    return subscriberFailures(
      countValue,
      isAccessException(exceptionValue) ? 'FORBIDDEN' : 'ERROR',
      isAccessException(exceptionValue)
        ? 'You do not have access to the requested PackageSubscriber records.'
        : 'Subscriber support analysis failed safely. Try again later.',
      false
    );
  }

  private static List<SubscriberResult> subscriberFailures(
    Integer countValue,
    String stateValue,
    String messageValue,
    Boolean clearValue
  ) {
    List<SubscriberResult> values = new List<SubscriberResult>();
    for (Integer indexValue = 0; indexValue < countValue; indexValue++) {
      values.add(subscriberFailure(stateValue, messageValue, clearValue));
    }
    return values;
  }

  private static SubscriberResult subscriberFailure(
    String stateValue,
    String messageValue,
    Boolean clearValue
  ) {
    SubscriberResult value = new SubscriberResult();
    value.state = stateValue;
    value.message = messageValue;
    value.clearPreviousContext = clearValue == true;
    return value;
  }

  private static List<VersionResult> versionQueryFailures(
    Integer countValue,
    Exception exceptionValue
  ) {
    return versionFailures(
      countValue,
      isAccessException(exceptionValue) ? 'FORBIDDEN' : 'ERROR',
      isAccessException(exceptionValue)
        ? 'You do not have access to the requested package-version records.'
        : 'Package-version readiness analysis failed safely. Try again later.',
      false
    );
  }

  private static List<VersionResult> versionFailures(
    Integer countValue,
    String stateValue,
    String messageValue,
    Boolean clearValue
  ) {
    List<VersionResult> values = new List<VersionResult>();
    for (Integer indexValue = 0; indexValue < countValue; indexValue++) {
      values.add(versionFailure(stateValue, messageValue, clearValue));
    }
    return values;
  }

  private static VersionResult versionFailure(
    String stateValue,
    String messageValue,
    Boolean clearValue
  ) {
    VersionResult value = new VersionResult();
    value.state = stateValue;
    value.message = messageValue;
    value.clearPreviousContext = clearValue == true;
    return value;
  }

  public class ContextInput {
    public String userInput;
    public String currentId;
  }

  public class BuildResult {
    public String state;
    public String message;
    public Boolean clearPreviousContext;
    public String buildRequestId;
    public String package2Id;
    public String package2VersionId;
    public String diagnosticJson;
  }

  public class BuildComparisonResult {
    public String state;
    public String message;
    public String buildRequestId;
    public String package2Id;
    public String comparisonJson;
  }

  public class SubscriberResult {
    public String state;
    public String message;
    public Boolean clearPreviousContext;
    public String packageSubscriberId;
    public String subscriberPackageId;
    public String subscriberPackageVersionId;
    public String subscriberJson;
  }

  public class VersionResult {
    public String state;
    public String message;
    public Boolean clearPreviousContext;
    public String subscriberPackageVersionId;
    public String package2Id;
    public String readinessJson;
  }

  private class IdSelection {
    private Boolean isValid = false;
    private Boolean replacementAttempted = false;
    private String idValue;
  }

  private class PushContext {
    private Boolean included = false;
    private Map<String, AgentforcePackageQueryService.PushAggregate> byVersionId = new Map<String, AgentforcePackageQueryService.PushAggregate>();
    private List<String> warnings = new List<String>();
  }

  private class BuildSignatureSummary implements Comparable {
    private String signature;
    private Set<String> affectedBuildIds;
    private Integer occurrenceCount;
    private Boolean affectsSelectedBuild;

    private BuildSignatureSummary(
      String signatureValue,
      Set<String> buildIds,
      Integer occurrences,
      String selectedBuildId
    ) {
      signature = signatureValue;
      affectedBuildIds = buildIds;
      occurrenceCount = occurrences;
      affectsSelectedBuild = buildIds.contains(selectedBuildId);
    }

    public Integer compareTo(Object otherValue) {
      BuildSignatureSummary other = (BuildSignatureSummary) otherValue;
      if (affectedBuildIds.size() != other.affectedBuildIds.size()) {
        return other.affectedBuildIds.size() - affectedBuildIds.size();
      }
      if (occurrenceCount != other.occurrenceCount) {
        return other.occurrenceCount - occurrenceCount;
      }
      return signature.compareTo(other.signature);
    }

    private Map<String, Object> toMap() {
      List<String> samples = new List<String>(affectedBuildIds);
      samples.sort();
      while (samples.size() > 3) {
        samples.remove(samples.size() - 1);
      }
      return new Map<String, Object>{
        'message' => signature,
        'affectedBuildCount' => affectedBuildIds.size(),
        'occurrenceCount' => occurrenceCount,
        'affectsSelectedBuild' => affectsSelectedBuild,
        'sampleCreateRequestIds' => samples
      };
    }
  }
}
