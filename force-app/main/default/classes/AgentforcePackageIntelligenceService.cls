/**
 * Permission-checked package portfolio and package-detail orchestration for
 * the read-only Package Visualizer Agent.
 */
public with sharing class AgentforcePackageIntelligenceService {
  private static final String CORE_PERMISSION = 'Package_Visualizer_Core';
  private static final Integer PACKAGE_SCAN_LIMIT = 500;
  private static final Integer VERSION_SCAN_LIMIT = 2000;
  private static final Integer BUILD_SCAN_LIMIT = 2000;
  private static final Integer ATTENTION_LIMIT = 25;
  private static final Integer JSON_LIMIT = 60000;

  @TestVisible
  static AgentforcePackageQueryService queryService = new AgentforcePackageQueryService();
  @TestVisible
  static Boolean corePermissionOverride;

  public static List<PortfolioResult> summarize(Integer inputCount) {
    List<PortfolioResult> results = new List<PortfolioResult>();
    if (inputCount == null || inputCount < 1) {
      return results;
    }
    if (!hasCorePermission()) {
      return portfolioFailures(
        inputCount,
        'FORBIDDEN',
        'You do not have access to Package Visualizer package intelligence.'
      );
    }
    if (!queryService.isToolingAvailable()) {
      return portfolioFailures(
        inputCount,
        'UNAVAILABLE',
        'Package portfolio data is not available in this org.'
      );
    }

    PortfolioResult sharedResult;
    try {
      sharedResult = buildPortfolio();
    } catch (Exception exceptionValue) {
      sharedResult = portfolioFailure(
        isAccessException(exceptionValue) ? 'FORBIDDEN' : 'ERROR',
        isAccessException(exceptionValue)
          ? 'You do not have access to the requested package portfolio data.'
          : 'Package portfolio analysis failed safely. Try again later.'
      );
    }
    for (Integer indexValue = 0; indexValue < inputCount; indexValue++) {
      results.add(sharedResult);
    }
    return results;
  }

  public static List<PackageDetailResult> explain(
    List<PackageDetailInput> inputs
  ) {
    List<PackageDetailResult> results = new List<PackageDetailResult>();
    if (inputs == null || inputs.isEmpty()) {
      return results;
    }
    if (!hasCorePermission()) {
      return detailFailures(
        inputs.size(),
        'FORBIDDEN',
        'You do not have access to Package Visualizer package intelligence.',
        false
      );
    }
    if (!queryService.isToolingAvailable()) {
      return detailFailures(
        inputs.size(),
        'UNAVAILABLE',
        'Package detail data is not available in this org.',
        false
      );
    }

    List<AgentforcePackageQueryService.PackageRecord> packages;
    List<AgentforcePackageQueryService.VersionRecord> versions;
    List<AgentforcePackageQueryService.BuildRecord> builds;
    List<AgentforcePackageQueryService.SubscriberAggregate> subscriberAggregates = new List<AgentforcePackageQueryService.SubscriberAggregate>();
    List<String> warnings = new List<String>();
    PushEnrichment pushEnrichment = new PushEnrichment();
    try {
      packages = queryService.getActivePackages(PACKAGE_SCAN_LIMIT);
      versions = queryService.getVersions(VERSION_SCAN_LIMIT);
      builds = queryService.getRecentBuilds(BUILD_SCAN_LIMIT);
      try {
        subscriberAggregates = queryService.getSubscriberAggregates(
          subscriberPackageIds(packages)
        );
      } catch (Exception ignored) {
        warnings.add('Subscriber enrichment is unavailable.');
      }
      pushEnrichment = loadPushEnrichment(versions, warnings);
    } catch (Exception exceptionValue) {
      return detailFailures(
        inputs.size(),
        isAccessException(exceptionValue) ? 'FORBIDDEN' : 'ERROR',
        isAccessException(exceptionValue)
          ? 'You do not have access to the requested package records.'
          : 'Package detail analysis failed safely. Try again later.',
        false
      );
    }

    for (PackageDetailInput input : inputs) {
      PackageSelection selection = selectPackage(input, packages);
      if (!selection.isValid) {
        PackageDetailResult failure = detailFailure(
          selection.state,
          selection.message,
          selection.replacementAttempted
        );
        results.add(failure);
        continue;
      }
      AgentforcePackageQueryService.PackageRecord packageRecord = selection.packageRecord;
      PackageDetailResult ready = new PackageDetailResult();
      ready.state = 'READY';
      ready.message = 'Authoritative package detail context is ready.';
      ready.clearPreviousContext = selection.replacementAttempted;
      ready.package2Id = packageRecord.id;
      ready.subscriberPackageId = packageRecord.subscriberPackageId;
      ready.packageDetailJson = boundedSerialize(
        buildPackageDetail(
          packageRecord,
          versions,
          builds,
          subscriberAggregates,
          warnings,
          pushEnrichment
        ),
        'recentFailedBuilds'
      );
      results.add(ready);
    }
    return results;
  }

  private static PortfolioResult buildPortfolio() {
    Integer totalPackageCount = queryService.getActivePackageCount();
    Integer totalVersionCount = queryService.getVersionCount();
    Integer totalBuildCount = queryService.getRecentBuildCount();
    List<AgentforcePackageQueryService.PackageRecord> packages = queryService.getActivePackages(
      PACKAGE_SCAN_LIMIT
    );
    List<AgentforcePackageQueryService.VersionRecord> versions = queryService.getVersions(
      VERSION_SCAN_LIMIT
    );
    List<AgentforcePackageQueryService.BuildRecord> builds = queryService.getRecentBuilds(
      BUILD_SCAN_LIMIT
    );

    List<String> warnings = new List<String>();
    List<AgentforcePackageQueryService.SubscriberAggregate> subscriberAggregates = new List<AgentforcePackageQueryService.SubscriberAggregate>();
    try {
      subscriberAggregates = queryService.getSubscriberAggregates(
        subscriberPackageIds(packages)
      );
    } catch (Exception ignored) {
      warnings.add('Subscriber enrichment is unavailable.');
    }
    PushEnrichment pushEnrichment = loadPushEnrichment(versions, warnings);

    Boolean packagesTruncated = totalPackageCount > packages.size();
    Boolean versionsTruncated = versions.size() >= VERSION_SCAN_LIMIT ||
      totalVersionCount > versions.size();
    Boolean buildsTruncated = builds.size() >= BUILD_SCAN_LIMIT ||
      totalBuildCount > builds.size();
    if (packagesTruncated) {
      warnings.add('Only the first 500 active packages were scanned.');
    }
    if (versionsTruncated) {
      warnings.add('The package-version scan reached the 2,000-record cap.');
    }
    if (buildsTruncated) {
      warnings.add(
        'The recent create-request scan reached the 2,000-record cap.'
      );
    }

    Map<String, List<AgentforcePackageQueryService.VersionRecord>> versionsByPackage = versionsByPackage(
      versions
    );
    Map<String, List<AgentforcePackageQueryService.BuildRecord>> buildsByPackage = buildsByPackage(
      builds
    );
    Map<String, Integer> subscribersByPackage = subscribersByPackage(
      subscriberAggregates
    );
    List<AttentionSummary> attention = new List<AttentionSummary>();
    Integer managedCount = 0;
    Integer unlockedCount = 0;
    Integer releasedVersionCount = 0;
    Integer unreleasedVersionCount = 0;
    Integer versionlessPackageCount = 0;
    Integer recentFailedBuildCount = 0;
    Integer totalSubscribers = 0;

    for (AgentforcePackageQueryService.VersionRecord versionRecord : versions) {
      if (versionRecord.isReleased == true) {
        releasedVersionCount++;
      } else {
        unreleasedVersionCount++;
      }
    }
    for (AgentforcePackageQueryService.BuildRecord build : builds) {
      if (isFailedBuild(build)) {
        recentFailedBuildCount++;
      }
    }
    for (Integer aggregateCount : subscribersByPackage.values()) {
      totalSubscribers += aggregateCount;
    }
    for (AgentforcePackageQueryService.PackageRecord packageRecord : packages) {
      if (isUnlocked(packageRecord)) {
        unlockedCount++;
      } else {
        managedCount++;
      }
      List<AgentforcePackageQueryService.VersionRecord> packageVersions = versionsByPackage.get(
        packageRecord.id
      );
      if (packageVersions == null || packageVersions.isEmpty()) {
        versionlessPackageCount++;
      }
      AttentionSummary summary = new AttentionSummary(
        packageRecord,
        packageVersions,
        buildsByPackage.get(packageRecord.id),
        subscribersByPackage.get(packageRecord.subscriberPackageId),
        pushSummary(pushEnrichment, packageVersions)
      );
      if (summary.needsAttention()) {
        attention.add(summary);
      }
    }
    attention.sort();

    List<Map<String, Object>> attentionMaps = new List<Map<String, Object>>();
    for (
      Integer indexValue = 0;
      indexValue < Math.min(ATTENTION_LIMIT, attention.size());
      indexValue++
    ) {
      attentionMaps.add(attention[indexValue].toMap());
    }

    Map<String, Object> payload = new Map<String, Object>{
      'capturedAt' => System.now(),
      'totalActivePackages' => totalPackageCount,
      'scannedActivePackages' => packages.size(),
      'managedPackageCount' => managedCount,
      'unlockedPackageCount' => unlockedCount,
      'releasedVersionCount' => releasedVersionCount,
      'unreleasedVersionCount' => unreleasedVersionCount,
      'versionlessPackageCount' => versionlessPackageCount,
      'recentFailedBuildCount' => recentFailedBuildCount,
      'subscriberTotal' => totalSubscribers,
      'packageScan' => scanMap(
        totalPackageCount,
        packages.size(),
        packages.size(),
        PACKAGE_SCAN_LIMIT
      ),
      'versionScan' => scanMap(
        totalVersionCount,
        versions.size(),
        versions.size(),
        VERSION_SCAN_LIMIT
      ),
      'createRequestScan' => scanMap(
        totalBuildCount,
        builds.size(),
        builds.size(),
        BUILD_SCAN_LIMIT
      ),
      'packagesNeedingAttention' => attentionMaps,
      'attentionPackageTotal' => attention.size(),
      'attentionPackageIncludedCount' => attentionMaps.size(),
      'attentionPackageDisplayLimit' => ATTENTION_LIMIT,
      'attentionPackagePresentationLimited' => attention.size() >
      attentionMaps.size(),
      'attentionPackageOmittedCount' => Math.max(
        0,
        attention.size() - attentionMaps.size()
      ),
      'pushEnrichmentIncluded' => pushEnrichment.included,
      'pushOutcomeTotals' => pushSummary(pushEnrichment, versions),
      'incomplete' => packagesTruncated || versionsTruncated || buildsTruncated,
      'warnings' => warnings
    };

    PortfolioResult resultValue = new PortfolioResult();
    resultValue.state = 'READY';
    resultValue.message = 'Authoritative package portfolio context is ready.';
    resultValue.totalPackageCount = totalPackageCount;
    resultValue.managedPackageCount = managedCount;
    resultValue.unlockedPackageCount = unlockedCount;
    resultValue.releasedVersionCount = releasedVersionCount;
    resultValue.unreleasedVersionCount = unreleasedVersionCount;
    resultValue.versionlessPackageCount = versionlessPackageCount;
    resultValue.recentFailedBuildCount = recentFailedBuildCount;
    resultValue.versionsTruncated = versionsTruncated;
    resultValue.createRequestsTruncated = buildsTruncated;
    resultValue.incomplete = packagesTruncated ||
      versionsTruncated ||
      buildsTruncated;
    resultValue.portfolioJson = boundedSerialize(
      payload,
      'packagesNeedingAttention'
    );
    return resultValue;
  }

  private static Map<String, Object> buildPackageDetail(
    AgentforcePackageQueryService.PackageRecord packageRecord,
    List<AgentforcePackageQueryService.VersionRecord> versions,
    List<AgentforcePackageQueryService.BuildRecord> builds,
    List<AgentforcePackageQueryService.SubscriberAggregate> aggregates,
    List<String> sharedWarnings,
    PushEnrichment pushEnrichment
  ) {
    List<AgentforcePackageQueryService.VersionRecord> packageVersions = new List<AgentforcePackageQueryService.VersionRecord>();
    List<AgentforcePackageQueryService.BuildRecord> packageBuilds = new List<AgentforcePackageQueryService.BuildRecord>();
    for (AgentforcePackageQueryService.VersionRecord versionRecord : versions) {
      if (versionRecord.packageId == packageRecord.id) {
        packageVersions.add(versionRecord);
      }
    }
    for (AgentforcePackageQueryService.BuildRecord build : builds) {
      if (build.packageId == packageRecord.id && isFailedBuild(build)) {
        packageBuilds.add(build);
      }
    }

    List<Map<String, Object>> versionMaps = new List<Map<String, Object>>();
    AgentforcePackageQueryService.VersionRecord latestReleased;
    for (AgentforcePackageQueryService.VersionRecord versionRecord : packageVersions) {
      if (versionMaps.size() < 25) {
        versionMaps.add(versionMap(versionRecord));
      }
      if (
        versionRecord.isReleased == true &&
        (latestReleased == null ||
        versionRecord.createdDate > latestReleased.createdDate)
      ) {
        latestReleased = versionRecord;
      }
    }
    List<Map<String, Object>> failureMaps = new List<Map<String, Object>>();
    for (AgentforcePackageQueryService.BuildRecord build : packageBuilds) {
      if (failureMaps.size() == 25) {
        break;
      }
      failureMaps.add(buildMap(build));
    }

    Integer subscriberTotal = 0;
    List<Map<String, Object>> distribution = new List<Map<String, Object>>();
    for (AgentforcePackageQueryService.SubscriberAggregate aggregateValue : aggregates) {
      if (
        aggregateValue.subscriberPackageId != packageRecord.subscriberPackageId
      ) {
        continue;
      }
      subscriberTotal += aggregateValue.subscriberCount;
      distribution.add(
        new Map<String, Object>{
          'subscriberPackageVersionId' => aggregateValue.subscriberPackageVersionId,
          'subscriberCount' => aggregateValue.subscriberCount
        }
      );
    }

    return new Map<String, Object>{
      'capturedAt' => System.now(),
      'package2Id' => packageRecord.id,
      'subscriberPackageId' => packageRecord.subscriberPackageId,
      'name' => packageRecord.name,
      'packageType' => packageRecord.containerOptions,
      'namespacePrefix' => packageRecord.namespacePrefix,
      'isOrgDependent' => packageRecord.isOrgDependent,
      'versionCount' => packageVersions.size(),
      'releasedVersionCount' => countReleased(packageVersions),
      'latestReleasedVersion' => versionMap(latestReleased),
      'versions' => versionMaps,
      'recentFailedBuildCount' => packageBuilds.size(),
      'recentFailedBuilds' => failureMaps,
      'subscriberTotal' => subscriberTotal,
      'subscriberVersionDistribution' => distribution,
      'pushEnrichmentIncluded' => pushEnrichment.included,
      'pushOutcomes' => pushSummary(pushEnrichment, packageVersions),
      'warnings' => sharedWarnings.clone()
    };
  }

  private static PushEnrichment loadPushEnrichment(
    List<AgentforcePackageQueryService.VersionRecord> versions,
    List<String> warnings
  ) {
    PushEnrichment enrichment = new PushEnrichment();
    if (!AgentforcePushDiagnosticsService.hasPermission()) {
      return enrichment;
    }
    if (!queryService.isPushAvailable()) {
      warnings.add('Push-outcome enrichment is unavailable.');
      return enrichment;
    }
    try {
      for (AgentforcePackageQueryService.PushAggregate aggregateValue : queryService.getPushAggregates(
        subscriberVersionIds(versions)
      )) {
        enrichment.byVersionId.put(
          aggregateValue.subscriberPackageVersionId,
          aggregateValue
        );
      }
      enrichment.included = true;
    } catch (Exception ignored) {
      warnings.add('Push-outcome enrichment is unavailable.');
    }
    return enrichment;
  }

  private static Set<String> subscriberVersionIds(
    List<AgentforcePackageQueryService.VersionRecord> versions
  ) {
    Set<String> values = new Set<String>();
    for (AgentforcePackageQueryService.VersionRecord versionRecord : versions) {
      if (!String.isBlank(versionRecord.subscriberPackageVersionId)) {
        values.add(versionRecord.subscriberPackageVersionId);
      }
    }
    return values;
  }

  private static Map<String, Object> pushSummary(
    PushEnrichment enrichment,
    List<AgentforcePackageQueryService.VersionRecord> versions
  ) {
    Integer requestCount = 0;
    Integer jobCount = 0;
    Map<String, Integer> requestStatuses = new Map<String, Integer>();
    Map<String, Integer> jobStatuses = new Map<String, Integer>();
    if (enrichment != null && versions != null) {
      for (AgentforcePackageQueryService.VersionRecord versionRecord : versions) {
        AgentforcePackageQueryService.PushAggregate aggregateValue = enrichment.byVersionId.get(
          versionRecord.subscriberPackageVersionId
        );
        if (aggregateValue == null) {
          continue;
        }
        requestCount += aggregateValue.requestCount;
        jobCount += aggregateValue.jobCount;
        addCounts(requestStatuses, aggregateValue.requestStatusCounts);
        addCounts(jobStatuses, aggregateValue.jobStatusCounts);
      }
    }
    return new Map<String, Object>{
      'requestCount' => requestCount,
      'jobCount' => jobCount,
      'requestStatusCounts' => requestStatuses,
      'jobStatusCounts' => jobStatuses
    };
  }

  private static void addCounts(
    Map<String, Integer> target,
    Map<String, Integer> additions
  ) {
    for (String keyValue : additions.keySet()) {
      target.put(
        keyValue,
        (target.get(keyValue) == null ? 0 : target.get(keyValue)) +
          additions.get(keyValue)
      );
    }
  }

  private static PackageSelection selectPackage(
    PackageDetailInput input,
    List<AgentforcePackageQueryService.PackageRecord> packages
  ) {
    PackageSelection selection = new PackageSelection();
    String userInput = input?.userInput ?? '';
    Matcher packageIdMatcher = Pattern.compile(
      '\\b0Ho[a-zA-Z0-9]{12}(?:[a-zA-Z0-9]{3})?\\b'
    ).matcher(userInput);
    if (packageIdMatcher.find()) {
      selection.replacementAttempted = true;
      return selectByPackageId(selection, packageIdMatcher.group(), packages);
    }
    Matcher subscriberIdMatcher = Pattern.compile(
      '\\b033[a-zA-Z0-9]{12}(?:[a-zA-Z0-9]{3})?\\b'
    ).matcher(userInput);
    if (subscriberIdMatcher.find()) {
      selection.replacementAttempted = true;
      return selectBySubscriberId(
        selection,
        subscriberIdMatcher.group(),
        packages
      );
    }
    Matcher anyIdMatcher = Pattern.compile(
      '\\b[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?\\b'
    ).matcher(userInput);
    if (
      anyIdMatcher.find() ||
      userInput.toLowerCase().contains('0ho') ||
      userInput.toLowerCase().contains('033')
    ) {
      selection.replacementAttempted = true;
      selection.state = 'INVALID_ID';
      selection.message =
        'Provide a valid 0Ho Package2 ID or 033 SubscriberPackage ID.';
      return selection;
    }

    List<AgentforcePackageQueryService.PackageRecord> nameMatches = nameMatches(
      userInput,
      packages
    );
    if (nameMatches.size() == 1) {
      selection.isValid = true;
      selection.replacementAttempted = true;
      selection.packageRecord = nameMatches[0];
      return selection;
    }
    if (nameMatches.size() > 1) {
      selection.replacementAttempted = true;
      selection.state = 'AMBIGUOUS';
      selection.message =
        'That package name is ambiguous. Choose one: ' +
        candidateText(nameMatches);
      return selection;
    }

    Boolean explicitNameAttempt = !String.isBlank(userInput) &&
      normalizeName(userInput).contains('package');
    if (explicitNameAttempt) {
      selection.replacementAttempted = true;
      selection.state = 'NOT_FOUND';
      selection.message =
        'The requested package was not found or is not accessible.';
      return selection;
    }
    if (isId(input?.currentPackageId, '0Ho')) {
      return selectByPackageId(selection, input.currentPackageId, packages);
    }
    selection.state = 'INVALID_ID';
    selection.message =
      'Provide a 0Ho Package2 ID, 033 SubscriberPackage ID, or exact package name.';
    return selection;
  }

  private static PackageSelection selectByPackageId(
    PackageSelection selection,
    String packageId,
    List<AgentforcePackageQueryService.PackageRecord> packages
  ) {
    for (AgentforcePackageQueryService.PackageRecord packageRecord : packages) {
      if (packageRecord.id == packageId) {
        selection.isValid = true;
        selection.packageRecord = packageRecord;
        return selection;
      }
    }
    selection.state = 'NOT_FOUND';
    selection.message = 'The requested package was not found or is not accessible.';
    return selection;
  }

  private static PackageSelection selectBySubscriberId(
    PackageSelection selection,
    String subscriberPackageId,
    List<AgentforcePackageQueryService.PackageRecord> packages
  ) {
    for (AgentforcePackageQueryService.PackageRecord packageRecord : packages) {
      if (packageRecord.subscriberPackageId == subscriberPackageId) {
        selection.isValid = true;
        selection.packageRecord = packageRecord;
        return selection;
      }
    }
    selection.state = 'NOT_FOUND';
    selection.message = 'The requested package was not found or is not accessible.';
    return selection;
  }

  private static List<AgentforcePackageQueryService.PackageRecord> nameMatches(
    String userInput,
    List<AgentforcePackageQueryService.PackageRecord> packages
  ) {
    List<AgentforcePackageQueryService.PackageRecord> values = new List<AgentforcePackageQueryService.PackageRecord>();
    String normalizedInput = normalizeName(userInput);
    for (AgentforcePackageQueryService.PackageRecord packageRecord : packages) {
      String normalizedName = normalizeName(packageRecord.name);
      if (
        !String.isBlank(normalizedName) &&
        (normalizedInput == normalizedName ||
        normalizedInput.contains(normalizedName))
      ) {
        values.add(packageRecord);
      }
    }
    return values;
  }

  private static String candidateText(
    List<AgentforcePackageQueryService.PackageRecord> packages
  ) {
    List<String> values = new List<String>();
    for (AgentforcePackageQueryService.PackageRecord packageRecord : packages) {
      values.add(packageRecord.name + ' (' + packageRecord.id + ')');
    }
    values.sort();
    return String.join(values, ', ');
  }

  private static String normalizeName(String value) {
    return String.isBlank(value)
      ? ''
      : value.toLowerCase().replaceAll('[^a-z0-9]+', ' ').trim();
  }

  private static Map<String, List<AgentforcePackageQueryService.VersionRecord>> versionsByPackage(
    List<AgentforcePackageQueryService.VersionRecord> versions
  ) {
    Map<String, List<AgentforcePackageQueryService.VersionRecord>> values = new Map<String, List<AgentforcePackageQueryService.VersionRecord>>();
    for (AgentforcePackageQueryService.VersionRecord versionRecord : versions) {
      if (!values.containsKey(versionRecord.packageId)) {
        values.put(
          versionRecord.packageId,
          new List<AgentforcePackageQueryService.VersionRecord>()
        );
      }
      values.get(versionRecord.packageId).add(versionRecord);
    }
    return values;
  }

  private static Map<String, List<AgentforcePackageQueryService.BuildRecord>> buildsByPackage(
    List<AgentforcePackageQueryService.BuildRecord> builds
  ) {
    Map<String, List<AgentforcePackageQueryService.BuildRecord>> values = new Map<String, List<AgentforcePackageQueryService.BuildRecord>>();
    for (AgentforcePackageQueryService.BuildRecord build : builds) {
      if (!values.containsKey(build.packageId)) {
        values.put(
          build.packageId,
          new List<AgentforcePackageQueryService.BuildRecord>()
        );
      }
      values.get(build.packageId).add(build);
    }
    return values;
  }

  private static Map<String, Integer> subscribersByPackage(
    List<AgentforcePackageQueryService.SubscriberAggregate> aggregates
  ) {
    Map<String, Integer> values = new Map<String, Integer>();
    for (AgentforcePackageQueryService.SubscriberAggregate aggregateValue : aggregates) {
      Integer priorValue = values.get(aggregateValue.subscriberPackageId);
      values.put(
        aggregateValue.subscriberPackageId,
        (priorValue == null ? 0 : priorValue) +
          aggregateValue.subscriberCount
      );
    }
    return values;
  }

  private static Set<String> subscriberPackageIds(
    List<AgentforcePackageQueryService.PackageRecord> packages
  ) {
    Set<String> values = new Set<String>();
    for (AgentforcePackageQueryService.PackageRecord packageRecord : packages) {
      if (!String.isBlank(packageRecord.subscriberPackageId)) {
        values.add(packageRecord.subscriberPackageId);
      }
    }
    return values;
  }

  private static Map<String, Object> scanMap(
    Integer totalCount,
    Integer scannedCount,
    Integer includedCount,
    Integer cap
  ) {
    return new Map<String, Object>{
      'totalCount' => totalCount,
      'scannedCount' => scannedCount,
      'includedCount' => includedCount,
      'omittedCount' => Math.max(0, totalCount - scannedCount),
      'cap' => cap,
      'truncated' => scannedCount >= cap || totalCount > scannedCount
    };
  }

  private static Map<String, Object> versionMap(
    AgentforcePackageQueryService.VersionRecord value
  ) {
    if (value == null) {
      return null;
    }
    return new Map<String, Object>{
      'package2VersionId' => value.id,
      'subscriberPackageVersionId' => value.subscriberPackageVersionId,
      'versionNumber' => versionNumber(value),
      'isReleased' => value.isReleased,
      'hasPassedCodeCoverageCheck' => value.hasPassedCodeCoverageCheck,
      'validationSkipped' => value.validationSkipped,
      'branch' => value.branch,
      'tag' => value.tag,
      'createdDate' => value.createdDate
    };
  }

  private static Map<String, Object> buildMap(
    AgentforcePackageQueryService.BuildRecord value
  ) {
    return new Map<String, Object>{
      'createRequestId' => value.id,
      'status' => value.status,
      'package2VersionId' => value.packageVersionId,
      'branch' => value.branch,
      'tag' => value.tag,
      'createdDate' => value.createdDate
    };
  }

  private static String versionNumber(
    AgentforcePackageQueryService.VersionRecord value
  ) {
    return value.majorVersion +
      '.' +
      value.minorVersion +
      '.' +
      value.patchVersion +
      '-' +
      value.buildNumber;
  }

  private static Integer countReleased(
    List<AgentforcePackageQueryService.VersionRecord> versions
  ) {
    Integer countValue = 0;
    for (AgentforcePackageQueryService.VersionRecord versionRecord : versions) {
      if (versionRecord.isReleased == true) {
        countValue++;
      }
    }
    return countValue;
  }

  private static Boolean isUnlocked(
    AgentforcePackageQueryService.PackageRecord value
  ) {
    return 'Unlocked'.equalsIgnoreCase(value.containerOptions);
  }

  private static Boolean isFailedBuild(
    AgentforcePackageQueryService.BuildRecord value
  ) {
    return 'Error'.equalsIgnoreCase(value.status) ||
      'Failed'.equalsIgnoreCase(value.status);
  }

  private static String boundedSerialize(
    Map<String, Object> payload,
    String removableListKey
  ) {
    String serialized = JSON.serialize(payload);
    List<Object> removable = (List<Object>) payload.get(removableListKey);
    Integer removedCount = 0;
    while (
      serialized.length() >= JSON_LIMIT &&
      removable != null &&
      !removable.isEmpty()
    ) {
      removable.remove(removable.size() - 1);
      removedCount++;
      payload.put(removableListKey + 'JsonOmittedCount', removedCount);
      serialized = JSON.serialize(payload);
    }
    if (serialized.length() >= JSON_LIMIT) {
      payload.put(
        'warnings',
        new List<String>{ 'Some optional evidence was omitted to keep the response bounded.' }
      );
      payload.remove(removableListKey);
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

  public static Boolean hasCorePermission() {
    return corePermissionOverride == null
      ? FeatureManagement.checkPermission(CORE_PERMISSION)
      : corePermissionOverride;
  }

  public static AgentforcePackageQueryService getQueryService() {
    return queryService;
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

  private static List<PortfolioResult> portfolioFailures(
    Integer countValue,
    String stateValue,
    String messageValue
  ) {
    List<PortfolioResult> values = new List<PortfolioResult>();
    for (Integer indexValue = 0; indexValue < countValue; indexValue++) {
      values.add(portfolioFailure(stateValue, messageValue));
    }
    return values;
  }

  private static PortfolioResult portfolioFailure(
    String stateValue,
    String messageValue
  ) {
    PortfolioResult value = new PortfolioResult();
    value.state = stateValue;
    value.message = messageValue;
    return value;
  }

  private static List<PackageDetailResult> detailFailures(
    Integer countValue,
    String stateValue,
    String messageValue,
    Boolean clearValue
  ) {
    List<PackageDetailResult> values = new List<PackageDetailResult>();
    for (Integer indexValue = 0; indexValue < countValue; indexValue++) {
      values.add(detailFailure(stateValue, messageValue, clearValue));
    }
    return values;
  }

  private static PackageDetailResult detailFailure(
    String stateValue,
    String messageValue,
    Boolean clearValue
  ) {
    PackageDetailResult value = new PackageDetailResult();
    value.state = stateValue;
    value.message = messageValue;
    value.clearPreviousContext = clearValue == true;
    return value;
  }

  public class PackageDetailInput {
    public String userInput;
    public String currentPackageId;
  }

  public class PortfolioResult {
    public String state;
    public String message;
    public Integer totalPackageCount;
    public Integer managedPackageCount;
    public Integer unlockedPackageCount;
    public Integer releasedVersionCount;
    public Integer unreleasedVersionCount;
    public Integer versionlessPackageCount;
    public Integer recentFailedBuildCount;
    public Boolean versionsTruncated;
    public Boolean createRequestsTruncated;
    public Boolean incomplete;
    public String portfolioJson;
  }

  public class PackageDetailResult {
    public String state;
    public String message;
    public Boolean clearPreviousContext;
    public String package2Id;
    public String subscriberPackageId;
    public String packageDetailJson;
  }

  private class PackageSelection {
    private Boolean isValid = false;
    private Boolean replacementAttempted = false;
    private String state;
    private String message;
    private AgentforcePackageQueryService.PackageRecord packageRecord;
  }

  private class AttentionSummary implements Comparable {
    private AgentforcePackageQueryService.PackageRecord packageRecord;
    private Integer recentFailedBuildCount = 0;
    private Boolean missingReleasedVersion = true;
    private Datetime latestReleasedDate;
    private Integer subscriberCount = 0;
    private Map<String, Object> pushOutcomes;

    private AttentionSummary(
      AgentforcePackageQueryService.PackageRecord packageValue,
      List<AgentforcePackageQueryService.VersionRecord> versions,
      List<AgentforcePackageQueryService.BuildRecord> builds,
      Integer subscribers,
      Map<String, Object> pushOutcomeValue
    ) {
      packageRecord = packageValue;
      subscriberCount = subscribers == null ? 0 : subscribers;
      pushOutcomes = pushOutcomeValue;
      for (
        AgentforcePackageQueryService.VersionRecord versionRecord : versions ??
          new List<AgentforcePackageQueryService.VersionRecord>()
      ) {
        if (
          versionRecord.isReleased == true &&
          (latestReleasedDate == null ||
          versionRecord.createdDate > latestReleasedDate)
        ) {
          missingReleasedVersion = false;
          latestReleasedDate = versionRecord.createdDate;
        }
      }
      for (
        AgentforcePackageQueryService.BuildRecord build : builds ??
          new List<AgentforcePackageQueryService.BuildRecord>()
      ) {
        if (isFailedBuild(build)) {
          recentFailedBuildCount++;
        }
      }
    }

    private Boolean needsAttention() {
      return recentFailedBuildCount > 0 ||
        missingReleasedVersion ||
        (latestReleasedDate != null &&
        latestReleasedDate < System.now().addDays(-365));
    }

    public Integer compareTo(Object otherValue) {
      AttentionSummary other = (AttentionSummary) otherValue;
      if (recentFailedBuildCount != other.recentFailedBuildCount) {
        return other.recentFailedBuildCount - recentFailedBuildCount;
      }
      if (missingReleasedVersion != other.missingReleasedVersion) {
        return missingReleasedVersion ? -1 : 1;
      }
      Long thisStaleness = latestReleasedDate == null
        ? Long.valueOf('9223372036854775807')
        : latestReleasedDate.getTime();
      Long otherStaleness = other.latestReleasedDate == null
        ? Long.valueOf('9223372036854775807')
        : other.latestReleasedDate.getTime();
      if (thisStaleness != otherStaleness) {
        return thisStaleness < otherStaleness ? -1 : 1;
      }
      if (subscriberCount != other.subscriberCount) {
        return other.subscriberCount - subscriberCount;
      }
      return packageRecord.name.toLowerCase().compareTo(
        other.packageRecord.name.toLowerCase()
      );
    }

    private Map<String, Object> toMap() {
      return new Map<String, Object>{
        'package2Id' => packageRecord.id,
        'subscriberPackageId' => packageRecord.subscriberPackageId,
        'name' => packageRecord.name,
        'packageType' => packageRecord.containerOptions,
        'recentFailedBuildCount' => recentFailedBuildCount,
        'missingReleasedVersion' => missingReleasedVersion,
        'latestReleasedDate' => latestReleasedDate,
        'subscriberCount' => subscriberCount,
        'pushOutcomes' => pushOutcomes
      };
    }
  }

  private class PushEnrichment {
    private Boolean included = false;
    private Map<String, AgentforcePackageQueryService.PushAggregate> byVersionId = new Map<String, AgentforcePackageQueryService.PushAggregate>();
  }
}
