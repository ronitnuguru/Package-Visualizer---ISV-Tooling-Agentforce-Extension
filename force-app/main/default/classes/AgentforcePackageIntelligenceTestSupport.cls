@isTest
public class AgentforcePackageIntelligenceTestSupport {
  public static final String PACKAGE_ID = '0Ho000000000001AAA';
  public static final String SECOND_PACKAGE_ID = '0Ho000000000002AAA';
  public static final String SUBSCRIBER_PACKAGE_ID = '033000000000001AAA';
  public static final String SECOND_SUBSCRIBER_PACKAGE_ID = '033000000000002AAA';
  public static final String VERSION_ID = '04t000000000001AAA';
  public static final String BUILD_ID = '08c000000000001AAA';
  public static final String SECOND_BUILD_ID = '08c000000000002AAA';
  public static final String SUBSCRIBER_ID = '0PS000000000001AAA';

  public static StubQueryService readyStub() {
    StubQueryService stub = new StubQueryService();
    stub.packages.add(
      packageRecord(
        PACKAGE_ID,
        SUBSCRIBER_PACKAGE_ID,
        'Managed Package',
        'Managed'
      )
    );
    stub.packages.add(
      packageRecord(
        SECOND_PACKAGE_ID,
        SECOND_SUBSCRIBER_PACKAGE_ID,
        'Unlocked Package',
        'Unlocked'
      )
    );
    stub.versions.add(
      versionRecord(
        '05i000000000001AAA',
        PACKAGE_ID,
        VERSION_ID,
        true,
        System.now().addDays(-10)
      )
    );
    stub.builds.add(
      buildRecord(BUILD_ID, PACKAGE_ID, 'Error', System.now().addDays(-1))
    );
    stub.errors.add(
      errorRecord('0Xx000000000001AAA', BUILD_ID, 'Build failed')
    );
    stub.subscriberAggregates.add(
      subscriberAggregate(SUBSCRIBER_PACKAGE_ID, VERSION_ID, 12)
    );
    stub.subscribers.add(subscriberRecord(SUBSCRIBER_ID));
    stub.packageTotal = stub.packages.size();
    stub.versionTotal = stub.versions.size();
    stub.buildTotal = stub.builds.size();
    AgentforcePackageIntelligenceService.queryService = stub;
    AgentforcePackageIntelligenceService.corePermissionOverride = true;
    AgentforcePushDiagnosticsService.permissionOverride = true;
    return stub;
  }

  public static AgentforcePackageQueryService.PackageRecord packageRecord(
    String idValue,
    String subscriberPackageId,
    String name,
    String typeValue
  ) {
    AgentforcePackageQueryService.PackageRecord value = new AgentforcePackageQueryService.PackageRecord();
    value.id = idValue;
    value.subscriberPackageId = subscriberPackageId;
    value.name = name;
    value.containerOptions = typeValue;
    value.createdDate = System.now().addDays(-400);
    return value;
  }

  public static AgentforcePackageQueryService.VersionRecord versionRecord(
    String idValue,
    String packageId,
    String subscriberVersionId,
    Boolean released,
    Datetime createdDate
  ) {
    AgentforcePackageQueryService.VersionRecord value = new AgentforcePackageQueryService.VersionRecord();
    value.id = idValue;
    value.packageId = packageId;
    value.subscriberPackageVersionId = subscriberVersionId;
    value.isReleased = released;
    value.hasPassedCodeCoverageCheck = released;
    value.createdDate = createdDate;
    value.majorVersion = 1;
    value.minorVersion = 0;
    value.patchVersion = 0;
    value.buildNumber = 1;
    return value;
  }

  public static AgentforcePackageQueryService.BuildRecord buildRecord(
    String idValue,
    String packageId,
    String status,
    Datetime createdDate
  ) {
    AgentforcePackageQueryService.BuildRecord value = new AgentforcePackageQueryService.BuildRecord();
    value.id = idValue;
    value.packageId = packageId;
    value.status = status;
    value.createdDate = createdDate;
    return value;
  }

  public static AgentforcePackageQueryService.BuildErrorRecord errorRecord(
    String idValue,
    String requestId,
    String message
  ) {
    AgentforcePackageQueryService.BuildErrorRecord value = new AgentforcePackageQueryService.BuildErrorRecord();
    value.id = idValue;
    value.requestId = requestId;
    value.message = message;
    return value;
  }

  public static AgentforcePackageQueryService.SubscriberAggregate subscriberAggregate(
    String packageId,
    String versionId,
    Integer countValue
  ) {
    AgentforcePackageQueryService.SubscriberAggregate value = new AgentforcePackageQueryService.SubscriberAggregate();
    value.subscriberPackageId = packageId;
    value.subscriberPackageVersionId = versionId;
    value.subscriberCount = countValue;
    return value;
  }

  public static AgentforcePackageQueryService.SubscriberRecord subscriberRecord(
    String idValue
  ) {
    AgentforcePackageQueryService.SubscriberRecord value = new AgentforcePackageQueryService.SubscriberRecord();
    value.id = idValue;
    value.subscriberPackageId = SUBSCRIBER_PACKAGE_ID;
    value.subscriberPackageVersionId = VERSION_ID;
    value.orgKey = '00D000000000001';
    value.orgName = 'Subscriber';
    value.orgType = 'Production';
    value.orgStatus = 'Active';
    value.installedStatus = 'i';
    value.instanceName = 'NA1';
    value.customUpgradeType = 'Push';
    value.isCustomUpgradeAllowed = true;
    return value;
  }

  public static AgentforcePackageQueryService.PushAggregate pushAggregate(
    String versionId,
    Integer requestCount,
    Integer jobCount,
    Integer failedJobCount
  ) {
    AgentforcePackageQueryService.PushAggregate value = new AgentforcePackageQueryService.PushAggregate();
    value.subscriberPackageVersionId = versionId;
    value.requestCount = requestCount;
    value.jobCount = jobCount;
    value.requestStatusCounts.put('Completed', requestCount);
    value.jobStatusCounts.put('Succeeded', jobCount - failedJobCount);
    value.jobStatusCounts.put('Failed', failedJobCount);
    return value;
  }

  public static Map<String, Object> jsonMap(String value) {
    return (Map<String, Object>) JSON.deserializeUntyped(value);
  }

  public class StubQueryService extends AgentforcePackageQueryService {
    public Boolean toolingAvailable = true;
    public Boolean subscriberAvailable = true;
    public Boolean shouldThrow = false;
    public Boolean throwPushQuery = false;
    public Boolean pushAvailable = true;
    public Boolean pushAggregatesRequested = false;
    public Integer packageTotal = 0;
    public Integer versionTotal = 0;
    public Integer buildTotal = 0;
    public List<PackageRecord> packages = new List<PackageRecord>();
    public List<VersionRecord> versions = new List<VersionRecord>();
    public List<BuildRecord> builds = new List<BuildRecord>();
    public List<BuildErrorRecord> errors = new List<BuildErrorRecord>();
    public List<SubscriberAggregate> subscriberAggregates = new List<SubscriberAggregate>();
    public List<SubscriberRecord> subscribers = new List<SubscriberRecord>();
    public List<PushAggregate> pushAggregates = new List<PushAggregate>();
    public Map<String, List<String>> dependenciesByVersionId = new Map<String, List<String>>();
    public Integer requestedVersionLimit;
    public Integer requestedBuildLimit;

    public override Boolean isToolingAvailable() {
      return toolingAvailable;
    }

    public override Boolean isSubscriberAvailable() {
      return subscriberAvailable;
    }

    public override Boolean isPushAvailable() {
      return pushAvailable;
    }

    public override Integer getActivePackageCount() {
      failIfRequested();
      return packageTotal;
    }

    public override Integer getVersionCount() {
      failIfRequested();
      return versionTotal;
    }

    public override Integer getRecentBuildCount() {
      failIfRequested();
      return buildTotal;
    }

    public override List<PackageRecord> getActivePackages(Integer rowLimit) {
      failIfRequested();
      return copyPackages(packages, rowLimit);
    }

    public override List<VersionRecord> getVersions(Integer rowLimit) {
      failIfRequested();
      requestedVersionLimit = rowLimit;
      return copyVersions(versions, rowLimit);
    }

    public override List<BuildRecord> getRecentBuilds(Integer rowLimit) {
      failIfRequested();
      requestedBuildLimit = rowLimit;
      return copyBuilds(builds, rowLimit);
    }

    public override List<BuildRecord> getBuilds(Set<String> requestIds) {
      failIfRequested();
      List<BuildRecord> values = new List<BuildRecord>();
      for (BuildRecord recordValue : builds) {
        if (requestIds.contains(recordValue.id)) {
          values.add(recordValue);
        }
      }
      return values;
    }

    public override List<BuildErrorRecord> getBuildErrors(
      Set<String> requestIds,
      Integer rowLimit
    ) {
      failIfRequested();
      List<BuildErrorRecord> values = new List<BuildErrorRecord>();
      for (BuildErrorRecord recordValue : errors) {
        if (requestIds.contains(recordValue.requestId)) {
          values.add(recordValue);
        }
        if (values.size() == rowLimit) {
          break;
        }
      }
      return values;
    }

    public override List<SubscriberAggregate> getSubscriberAggregates(
      Set<String> subscriberPackageIds
    ) {
      failIfRequested();
      return subscriberAggregates.clone();
    }

    public override List<SubscriberRecord> getSubscribers(
      Set<String> subscriberIds
    ) {
      failIfRequested();
      List<SubscriberRecord> values = new List<SubscriberRecord>();
      for (SubscriberRecord recordValue : subscribers) {
        if (subscriberIds.contains(recordValue.id)) {
          values.add(recordValue);
        }
      }
      return values;
    }

    public override List<VersionRecord> getVersionsBySubscriberIds(
      Set<String> subscriberVersionIds
    ) {
      failIfRequested();
      List<VersionRecord> values = new List<VersionRecord>();
      for (VersionRecord recordValue : versions) {
        if (
          subscriberVersionIds.contains(recordValue.subscriberPackageVersionId)
        ) {
          values.add(recordValue);
        }
      }
      return values;
    }

    public override Map<String, List<String>> getDependencies(
      Set<String> subscriberVersionIds
    ) {
      failIfRequested();
      return dependenciesByVersionId.clone();
    }

    public override List<PushAggregate> getPushAggregates(
      Set<String> subscriberVersionIds
    ) {
      pushAggregatesRequested = true;
      if (throwPushQuery) {
        throw new QueryException('raw optional push failure');
      }
      List<PushAggregate> values = new List<PushAggregate>();
      for (PushAggregate aggregateValue : pushAggregates) {
        if (
          subscriberVersionIds.contains(
            aggregateValue.subscriberPackageVersionId
          )
        ) {
          values.add(aggregateValue);
        }
      }
      return values;
    }

    private void failIfRequested() {
      if (shouldThrow) {
        throw new QueryException('raw query failure');
      }
    }

    private List<PackageRecord> copyPackages(
      List<PackageRecord> source,
      Integer rowLimit
    ) {
      List<PackageRecord> values = new List<PackageRecord>();
      for (
        Integer indexValue = 0;
        indexValue < Math.min(source.size(), rowLimit);
        indexValue++
      ) {
        values.add(source[indexValue]);
      }
      return values;
    }

    private List<VersionRecord> copyVersions(
      List<VersionRecord> source,
      Integer rowLimit
    ) {
      List<VersionRecord> values = new List<VersionRecord>();
      for (
        Integer indexValue = 0;
        indexValue < Math.min(source.size(), rowLimit);
        indexValue++
      ) {
        values.add(source[indexValue]);
      }
      return values;
    }

    private List<BuildRecord> copyBuilds(
      List<BuildRecord> source,
      Integer rowLimit
    ) {
      List<BuildRecord> values = new List<BuildRecord>();
      for (
        Integer indexValue = 0;
        indexValue < Math.min(source.size(), rowLimit);
        indexValue++
      ) {
        values.add(source[indexValue]);
      }
      return values;
    }
  }
}
