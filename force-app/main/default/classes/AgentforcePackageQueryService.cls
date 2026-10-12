/**
 * Fixed, read-only query boundary for Package Visualizer Agent package,
 * build, version, dependency, and subscriber context.
 */
public virtual with sharing class AgentforcePackageQueryService {
  private static final Integer MAX_QUERY_LIMIT = 10000;
  @TestVisible
  private static final Integer TOOLING_TIMEOUT_MILLISECONDS = 60000;

  public virtual Boolean isToolingAvailable() {
    return true;
  }

  public virtual Boolean isSubscriberAvailable() {
    return Schema.getGlobalDescribe().containsKey('PackageSubscriber');
  }

  public virtual Boolean isPushAvailable() {
    return Schema.getGlobalDescribe().containsKey('PackagePushRequest') &&
      Schema.getGlobalDescribe().containsKey('PackagePushJob');
  }

  public virtual Integer getActivePackageCount() {
    return toolingCount(
      'SELECT IsDeprecated, COUNT(Id) total FROM Package2 ' +
      'WHERE IsDeprecated = false GROUP BY IsDeprecated'
    );
  }

  public virtual Integer getVersionCount() {
    return toolingCount(
      'SELECT IsDeprecated, COUNT(Id) total FROM Package2Version ' +
      'WHERE IsDeprecated = false GROUP BY IsDeprecated'
    );
  }

  public virtual Integer getRecentBuildCount() {
    return toolingCount(
      'SELECT Status, COUNT(Id) total FROM Package2VersionCreateRequest ' +
      'WHERE CreatedDate = LAST_N_DAYS:90 GROUP BY Status'
    );
  }

  public virtual List<PackageRecord> getActivePackages(Integer rowLimit) {
    List<Object> rows = toolingQuery(
      'SELECT Id, Name, ContainerOptions, NamespacePrefix, SubscriberPackageId, ' +
        'IsOrgDependent, CreatedDate FROM Package2 WHERE IsDeprecated = false ' +
        'ORDER BY Name, Id LIMIT ' +
        normalizeLimit(rowLimit)
    );
    List<PackageRecord> values = new List<PackageRecord>();
    for (Object rowValue : rows) {
      Map<String, Object> row = (Map<String, Object>) rowValue;
      PackageRecord value = new PackageRecord();
      value.id = stringValue(row, 'Id');
      value.name = stringValue(row, 'Name');
      value.containerOptions = stringValue(row, 'ContainerOptions');
      value.namespacePrefix = stringValue(row, 'NamespacePrefix');
      value.subscriberPackageId = stringValue(row, 'SubscriberPackageId');
      value.isOrgDependent = booleanValue(row, 'IsOrgDependent');
      value.createdDate = datetimeValue(row, 'CreatedDate');
      values.add(value);
    }
    return values;
  }

  public virtual List<VersionRecord> getVersions(Integer rowLimit) {
    return queryVersions(
      'SELECT Id, Package2Id, SubscriberPackageVersionId, IsReleased, ' +
        'HasPassedCodeCoverageCheck, ValidationSkipped, MajorVersion, MinorVersion, ' +
        'PatchVersion, BuildNumber, Branch, Tag, CreatedDate ' +
        'FROM Package2Version WHERE IsDeprecated = false ' +
        'ORDER BY CreatedDate DESC, Id LIMIT ' +
        normalizeLimit(rowLimit)
    );
  }

  public virtual List<VersionRecord> getVersionsBySubscriberIds(
    Set<String> subscriberVersionIds
  ) {
    if (subscriberVersionIds == null || subscriberVersionIds.isEmpty()) {
      return new List<VersionRecord>();
    }
    return queryVersions(
      'SELECT Id, Package2Id, SubscriberPackageVersionId, IsReleased, ' +
        'HasPassedCodeCoverageCheck, ValidationSkipped, MajorVersion, MinorVersion, ' +
        'PatchVersion, BuildNumber, Branch, Tag, CreatedDate ' +
        'FROM Package2Version WHERE IsDeprecated = false AND ' +
        'SubscriberPackageVersionId IN (' +
        quotedIds(subscriberVersionIds) +
        ') ORDER BY Id LIMIT 2000'
    );
  }

  public virtual List<BuildRecord> getRecentBuilds(Integer rowLimit) {
    return queryBuilds(
      'SELECT Id, Status, Package2Id, Package2VersionId, Branch, Tag, Language, ' +
        'AsyncValidation, CalculateCodeCoverage, CalcTransitiveDependencies, ' +
        'SkipValidation, CreatedDate, SystemModstamp ' +
        'FROM Package2VersionCreateRequest WHERE CreatedDate = LAST_N_DAYS:90 ' +
        'ORDER BY CreatedDate DESC, Id LIMIT ' +
        normalizeLimit(rowLimit)
    );
  }

  public virtual List<BuildRecord> getBuilds(Set<String> requestIds) {
    if (requestIds == null || requestIds.isEmpty()) {
      return new List<BuildRecord>();
    }
    return queryBuilds(
      'SELECT Id, Status, Package2Id, Package2VersionId, Branch, Tag, Language, ' +
        'AsyncValidation, CalculateCodeCoverage, CalcTransitiveDependencies, ' +
        'SkipValidation, CreatedDate, SystemModstamp ' +
        'FROM Package2VersionCreateRequest WHERE Id IN (' +
        quotedIds(requestIds) +
        ') ORDER BY Id'
    );
  }

  public virtual List<BuildErrorRecord> getBuildErrors(
    Set<String> requestIds,
    Integer rowLimit
  ) {
    if (requestIds == null || requestIds.isEmpty()) {
      return new List<BuildErrorRecord>();
    }
    List<Object> rows = toolingQuery(
      'SELECT Id, Message, ParentRequestId FROM ' +
        'Package2VersionCreateRequestError WHERE ParentRequestId IN (' +
        quotedIds(requestIds) +
        ') ORDER BY ParentRequestId, Id LIMIT ' +
        normalizeLimit(rowLimit)
    );
    List<BuildErrorRecord> values = new List<BuildErrorRecord>();
    for (Object rowValue : rows) {
      Map<String, Object> row = (Map<String, Object>) rowValue;
      BuildErrorRecord value = new BuildErrorRecord();
      value.id = stringValue(row, 'Id');
      value.requestId = stringValue(row, 'ParentRequestId');
      value.message = stringValue(row, 'Message');
      values.add(value);
    }
    return values;
  }

  public virtual List<SubscriberAggregate> getSubscriberAggregates(
    Set<String> subscriberPackageIds
  ) {
    if (
      !isSubscriberAvailable() ||
      subscriberPackageIds == null ||
      subscriberPackageIds.isEmpty()
    ) {
      return new List<SubscriberAggregate>();
    }
    assertSubscriberFields(
      new Set<String>{ 'MetadataPackageId', 'MetadataPackageVersionId', 'Id' }
    );
    List<AggregateResult> rows = Database.query(
      'SELECT MetadataPackageId packageId, MetadataPackageVersionId versionId, ' +
        'COUNT(Id) subscriberCount FROM PackageSubscriber ' +
        'WHERE MetadataPackageId IN :subscriberPackageIds ' +
        'GROUP BY MetadataPackageId, MetadataPackageVersionId'
    );
    List<SubscriberAggregate> values = new List<SubscriberAggregate>();
    for (AggregateResult row : rows) {
      SubscriberAggregate value = new SubscriberAggregate();
      value.subscriberPackageId = String.valueOf(row.get('packageId'));
      value.subscriberPackageVersionId = String.valueOf(row.get('versionId'));
      value.subscriberCount = Integer.valueOf(
        String.valueOf(row.get('subscriberCount'))
      );
      values.add(value);
    }
    return values;
  }

  public virtual List<SubscriberRecord> getSubscribers(
    Set<String> subscriberIds
  ) {
    if (
      !isSubscriberAvailable() ||
      subscriberIds == null ||
      subscriberIds.isEmpty()
    ) {
      return new List<SubscriberRecord>();
    }
    List<SObject> rows = Security.stripInaccessible(
        AccessType.READABLE,
        Database.query(
          'SELECT Id, MetadataPackageId, MetadataPackageVersionId, InstalledStatus, ' +
            'OrgKey, OrgName, OrgType, OrgStatus, InstanceName, ParentOrg, ' +
            'CustomUpgradeType, HasRestrictionEnabled, IsCustomUpgradeAllowed, ' +
            'SystemModstamp FROM PackageSubscriber WHERE Id IN :subscriberIds ORDER BY Id'
        )
      )
      .getRecords();
    List<SubscriberRecord> values = new List<SubscriberRecord>();
    for (SObject row : rows) {
      SubscriberRecord value = new SubscriberRecord();
      value.id = stringValue(row, 'Id');
      value.subscriberPackageId = stringValue(row, 'MetadataPackageId');
      value.subscriberPackageVersionId = stringValue(
        row,
        'MetadataPackageVersionId'
      );
      value.installedStatus = stringValue(row, 'InstalledStatus');
      value.orgKey = stringValue(row, 'OrgKey');
      value.orgName = stringValue(row, 'OrgName');
      value.orgType = stringValue(row, 'OrgType');
      value.orgStatus = stringValue(row, 'OrgStatus');
      value.instanceName = stringValue(row, 'InstanceName');
      value.parentOrg = stringValue(row, 'ParentOrg');
      value.customUpgradeType = stringValue(row, 'CustomUpgradeType');
      value.hasRestrictionEnabled = booleanValue(row, 'HasRestrictionEnabled');
      value.isCustomUpgradeAllowed = booleanValue(
        row,
        'IsCustomUpgradeAllowed'
      );
      value.systemModstamp = datetimeValue(row, 'SystemModstamp');
      values.add(value);
    }
    return values;
  }

  public virtual Map<String, List<String>> getDependencies(
    Set<String> subscriberVersionIds
  ) {
    Map<String, List<String>> values = new Map<String, List<String>>();
    if (subscriberVersionIds == null || subscriberVersionIds.isEmpty()) {
      return values;
    }

    Set<String> validVersionIds = new Set<String>();
    for (String versionId : subscriberVersionIds) {
      if (!isId(versionId, '04t')) {
        continue;
      }
      validVersionIds.add(versionId);
      values.put(versionId, new List<String>());
    }
    if (validVersionIds.isEmpty()) {
      return values;
    }

    List<Object> rows = toolingQuery(
      'SELECT Id, Dependencies FROM SubscriberPackageVersion WHERE Id IN (' +
        quotedIds(validVersionIds) +
        ') ORDER BY Id LIMIT 2000'
    );
    for (Object rowValue : rows) {
      Map<String, Object> row = (Map<String, Object>) rowValue;
      String versionId = stringValue(row, 'Id');
      if (!values.containsKey(versionId) || row.get('Dependencies') == null) {
        continue;
      }
      Map<String, Object> dependencyEnvelope = (Map<String, Object>) row.get(
        'Dependencies'
      );
      List<Object> dependencyRows = (List<Object>) dependencyEnvelope.get(
        'ids'
      );
      if (dependencyRows == null) {
        continue;
      }
      for (Object dependencyValue : dependencyRows) {
        Map<String, Object> dependency = (Map<String, Object>) dependencyValue;
        String dependencyVersionId = stringValue(
          dependency,
          'subscriberPackageVersionId'
        );
        if (!String.isBlank(dependencyVersionId)) {
          values.get(versionId).add(dependencyVersionId);
        }
      }
    }
    return values;
  }

  public virtual List<PushAggregate> getPushAggregates(
    Set<String> subscriberVersionIds
  ) {
    if (
      !isPushAvailable() ||
      subscriberVersionIds == null ||
      subscriberVersionIds.isEmpty()
    ) {
      return new List<PushAggregate>();
    }
    assertReadableFields(
      'PackagePushRequest',
      new Set<String>{ 'Id', 'PackageVersionId', 'Status' }
    );
    assertReadableFields(
      'PackagePushJob',
      new Set<String>{ 'Id', 'PackagePushRequestId', 'Status' }
    );

    Map<String, PushAggregate> byVersionId = new Map<String, PushAggregate>();
    List<AggregateResult> requestRows = Database.query(
      'SELECT PackageVersionId versionId, Status requestStatus, COUNT(Id) requestCount ' +
        'FROM PackagePushRequest WHERE PackageVersionId IN :subscriberVersionIds ' +
        'GROUP BY PackageVersionId, Status'
    );
    for (AggregateResult row : requestRows) {
      String versionId = String.valueOf(row.get('versionId'));
      PushAggregate summary = aggregateFor(byVersionId, versionId);
      Integer countValue = aggregateCount(row, 'requestCount');
      summary.requestCount += countValue;
      summary.requestStatusCounts.put(
        String.valueOf(row.get('requestStatus')),
        countValue
      );
    }

    List<AggregateResult> jobRows = Database.query(
      'SELECT PackagePushRequest.PackageVersionId versionId, Status jobStatus, ' +
        'COUNT(Id) jobCount FROM PackagePushJob ' +
        'WHERE PackagePushRequest.PackageVersionId IN :subscriberVersionIds ' +
        'GROUP BY PackagePushRequest.PackageVersionId, Status'
    );
    for (AggregateResult row : jobRows) {
      String versionId = String.valueOf(row.get('versionId'));
      PushAggregate summary = aggregateFor(byVersionId, versionId);
      Integer countValue = aggregateCount(row, 'jobCount');
      summary.jobCount += countValue;
      summary.jobStatusCounts.put(
        String.valueOf(row.get('jobStatus')),
        countValue
      );
    }
    return byVersionId.values();
  }

  private static List<VersionRecord> queryVersions(String queryValue) {
    List<VersionRecord> values = new List<VersionRecord>();
    for (Object rowValue : toolingQuery(queryValue)) {
      Map<String, Object> row = (Map<String, Object>) rowValue;
      VersionRecord value = new VersionRecord();
      value.id = stringValue(row, 'Id');
      value.packageId = stringValue(row, 'Package2Id');
      value.subscriberPackageVersionId = stringValue(
        row,
        'SubscriberPackageVersionId'
      );
      value.isReleased = booleanValue(row, 'IsReleased');
      value.hasPassedCodeCoverageCheck = booleanValue(
        row,
        'HasPassedCodeCoverageCheck'
      );
      value.validationSkipped = booleanValue(row, 'ValidationSkipped');
      value.majorVersion = integerValue(row, 'MajorVersion');
      value.minorVersion = integerValue(row, 'MinorVersion');
      value.patchVersion = integerValue(row, 'PatchVersion');
      value.buildNumber = integerValue(row, 'BuildNumber');
      value.branch = stringValue(row, 'Branch');
      value.tag = stringValue(row, 'Tag');
      value.createdDate = datetimeValue(row, 'CreatedDate');
      values.add(value);
    }
    return values;
  }

  private static List<BuildRecord> queryBuilds(String queryValue) {
    List<BuildRecord> values = new List<BuildRecord>();
    for (Object rowValue : toolingQuery(queryValue)) {
      Map<String, Object> row = (Map<String, Object>) rowValue;
      BuildRecord value = new BuildRecord();
      value.id = stringValue(row, 'Id');
      value.status = stringValue(row, 'Status');
      value.packageId = stringValue(row, 'Package2Id');
      value.packageVersionId = stringValue(row, 'Package2VersionId');
      value.branch = stringValue(row, 'Branch');
      value.tag = stringValue(row, 'Tag');
      value.language = stringValue(row, 'Language');
      value.asyncValidation = booleanValue(row, 'AsyncValidation');
      value.calculateCodeCoverage = booleanValue(row, 'CalculateCodeCoverage');
      value.calculateTransitiveDependencies = booleanValue(
        row,
        'CalcTransitiveDependencies'
      );
      value.skipValidation = booleanValue(row, 'SkipValidation');
      value.createdDate = datetimeValue(row, 'CreatedDate');
      value.systemModstamp = datetimeValue(row, 'SystemModstamp');
      values.add(value);
    }
    return values;
  }

  private static Integer toolingCount(String queryValue) {
    List<Object> rows = toolingQuery(queryValue);
    Integer totalCount = 0;
    for (Object rowValue : rows) {
      Map<String, Object> row = (Map<String, Object>) rowValue;
      Object countValue = row.containsKey('total')
        ? row.get('total')
        : row.get('expr0');
      if (countValue != null) {
        totalCount += Integer.valueOf(String.valueOf(countValue));
      }
    }
    return totalCount;
  }

  private static void assertSubscriberFields(Set<String> fieldNames) {
    assertReadableFields('PackageSubscriber', fieldNames);
  }

  private static void assertReadableFields(
    String objectName,
    Set<String> fieldNames
  ) {
    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
    if (objectType == null) {
      throw new NoAccessException();
    }
    Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
    if (!objectDescribe.isAccessible()) {
      throw new NoAccessException();
    }
    Map<String, Schema.SObjectField> fields = objectDescribe.fields.getMap();
    for (String fieldName : fieldNames) {
      if (
        !fields.containsKey(fieldName) ||
        !fields.get(fieldName).getDescribe().isAccessible()
      ) {
        throw new NoAccessException();
      }
    }
  }

  private static PushAggregate aggregateFor(
    Map<String, PushAggregate> byVersionId,
    String versionId
  ) {
    PushAggregate value = byVersionId.get(versionId);
    if (value == null) {
      value = new PushAggregate();
      value.subscriberPackageVersionId = versionId;
      byVersionId.put(versionId, value);
    }
    return value;
  }

  private static Integer aggregateCount(AggregateResult row, String fieldName) {
    Object rawValue = row.get(fieldName);
    return rawValue == null ? 0 : Integer.valueOf(String.valueOf(rawValue));
  }

  private static Integer normalizeLimit(Integer rowLimit) {
    if (rowLimit == null || rowLimit < 1) {
      return 1;
    }
    return Math.min(rowLimit, MAX_QUERY_LIMIT);
  }

  private static List<Object> toolingQuery(String queryValue) {
    return Package2Interface.submitQuery(
      queryValue,
      TOOLING_TIMEOUT_MILLISECONDS
    );
  }

  private static String quotedIds(Set<String> ids) {
    List<String> values = new List<String>();
    for (String idValue : ids) {
      values.add('\'' + String.escapeSingleQuotes(idValue) + '\'');
    }
    values.sort();
    return String.join(values, ',');
  }

  private static Boolean isId(String value, String prefix) {
    return value != null &&
      Pattern.matches(
        '^' + prefix + '[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$',
        value
      );
  }

  private static String stringValue(Map<String, Object> row, String fieldName) {
    Object value = row.get(fieldName);
    return value == null ? null : String.valueOf(value);
  }

  private static String stringValue(SObject row, String fieldName) {
    Object value = row.get(fieldName);
    return value == null ? null : String.valueOf(value);
  }

  private static Boolean booleanValue(
    Map<String, Object> row,
    String fieldName
  ) {
    Object value = row.get(fieldName);
    return value == null ? null : Boolean.valueOf(String.valueOf(value));
  }

  private static Boolean booleanValue(SObject row, String fieldName) {
    Object value = row.get(fieldName);
    return value == null ? null : Boolean.valueOf(String.valueOf(value));
  }

  private static Integer integerValue(
    Map<String, Object> row,
    String fieldName
  ) {
    Object value = row.get(fieldName);
    return value == null ? null : Integer.valueOf(String.valueOf(value));
  }

  private static Datetime datetimeValue(
    Map<String, Object> row,
    String fieldName
  ) {
    Object value = row.get(fieldName);
    return value == null
      ? null
      : (Datetime) JSON.deserialize(
          '"' + String.valueOf(value) + '"',
          Datetime.class
        );
  }

  private static Datetime datetimeValue(SObject row, String fieldName) {
    return (Datetime) row.get(fieldName);
  }

  public class PackageRecord {
    public String id;
    public String subscriberPackageId;
    public String name;
    public String containerOptions;
    public String namespacePrefix;
    public Boolean isOrgDependent;
    public Datetime createdDate;
  }

  public class VersionRecord {
    public String id;
    public String packageId;
    public String subscriberPackageVersionId;
    public Boolean isReleased;
    public Boolean hasPassedCodeCoverageCheck;
    public Boolean validationSkipped;
    public Integer majorVersion;
    public Integer minorVersion;
    public Integer patchVersion;
    public Integer buildNumber;
    public String branch;
    public String tag;
    public Datetime createdDate;
  }

  public class BuildRecord {
    public String id;
    public String status;
    public String packageId;
    public String packageVersionId;
    public String branch;
    public String tag;
    public String language;
    public Boolean asyncValidation;
    public Boolean calculateCodeCoverage;
    public Boolean calculateTransitiveDependencies;
    public Boolean skipValidation;
    public Datetime createdDate;
    public Datetime systemModstamp;
  }

  public class BuildErrorRecord {
    public String id;
    public String requestId;
    public String message;
  }

  public class SubscriberAggregate {
    public String subscriberPackageId;
    public String subscriberPackageVersionId;
    public Integer subscriberCount;
  }

  public class SubscriberRecord {
    public String id;
    public String subscriberPackageId;
    public String subscriberPackageVersionId;
    public String installedStatus;
    public String orgKey;
    public String orgName;
    public String orgType;
    public String orgStatus;
    public String instanceName;
    public String parentOrg;
    public String customUpgradeType;
    public Boolean hasRestrictionEnabled;
    public Boolean isCustomUpgradeAllowed;
    public Datetime systemModstamp;
  }

  public class PushAggregate {
    public String subscriberPackageVersionId;
    public Integer requestCount = 0;
    public Integer jobCount = 0;
    public Map<String, Integer> requestStatusCounts = new Map<String, Integer>();
    public Map<String, Integer> jobStatusCounts = new Map<String, Integer>();
  }
}
