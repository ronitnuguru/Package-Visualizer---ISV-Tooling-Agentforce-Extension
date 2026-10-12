/**
 * Read-only query boundary for PackagePushJob diagnostic and sibling
 * comparison data. The virtual methods provide a test seam for packaging
 * records that Apex tests can't create.
 */
public virtual with sharing class AgentforcePushDiagnosticsQueryService {
  private static final String PACKAGE_PUSH_JOB = 'PackagePushJob';
  private static final String PACKAGE_PUSH_ERROR = 'PackagePushError';
  private static final String PACKAGE_PUSH_REQUEST = 'PackagePushRequest';
  private static final String METADATA_PACKAGE_VERSION = 'MetadataPackageVersion';
  private static final String PACKAGE_SUBSCRIBER = 'PackageSubscriber';

  /**
   * @return true when the authoritative job and error objects are available.
   */
  public virtual Boolean areCoreObjectsAvailable() {
    return isObjectAvailable(PACKAGE_PUSH_JOB) &&
      isObjectAvailable(PACKAGE_PUSH_ERROR);
  }

  /**
   * @return true when request, version, and subscriber enrichment is available.
   */
  public virtual Boolean areOptionalObjectsAvailable() {
    return isObjectAvailable(PACKAGE_PUSH_REQUEST) &&
      isObjectAvailable(METADATA_PACKAGE_VERSION) &&
      isObjectAvailable(PACKAGE_SUBSCRIBER);
  }

  /**
   * Loads authoritative jobs in a single bulk query.
   *
   * @param jobIds PackagePushJob IDs.
   * @return Normalized job records.
   */
  public virtual List<JobRecord> getJobs(Set<String> jobIds) {
    if (jobIds == null || jobIds.isEmpty()) {
      return new List<JobRecord>();
    }
    List<SObject> records = readable(
      Database.query(
        'SELECT Id, PackagePushRequestId, Status, SubscriberOrganizationKey, ' +
          'SystemModstamp, DurationSeconds, EndTime, StartTime ' +
          'FROM PackagePushJob WHERE Id IN :jobIds ORDER BY Id'
      )
    );
    return toJobs(records);
  }

  /**
   * Loads error evidence for jobs in deterministic server order.
   *
   * @param jobIds PackagePushJob IDs.
   * @param rowLimit Maximum rows to return.
   * @return Normalized error records.
   */
  public virtual List<ErrorRecord> getErrors(
    Set<String> jobIds,
    Integer rowLimit
  ) {
    if (jobIds == null || jobIds.isEmpty()) {
      return new List<ErrorRecord>();
    }
    Integer safeLimit = normalizeLimit(rowLimit);
    List<SObject> records = readable(
      Database.query(
        'SELECT Id, PackagePushJobId, ErrorTitle, ErrorMessage, ErrorType, ' +
          'ErrorDetails, ErrorSeverity, SystemModstamp ' +
          'FROM PackagePushError WHERE PackagePushJobId IN :jobIds ' +
          'ORDER BY PackagePushJobId, SystemModstamp, Id LIMIT :safeLimit'
      )
    );
    return toErrors(records);
  }

  /**
   * Loads owning push requests for target-version enrichment.
   *
   * @param requestIds PackagePushRequest IDs.
   * @return Normalized request records.
   */
  public virtual List<RequestRecord> getRequests(Set<String> requestIds) {
    if (requestIds == null || requestIds.isEmpty()) {
      return new List<RequestRecord>();
    }
    List<SObject> records = readable(
      Database.query(
        'SELECT Id, PackageVersionId FROM PackagePushRequest ' +
        'WHERE Id IN :requestIds ORDER BY Id'
      )
    );
    return toRequests(records);
  }

  /**
   * Loads package/version facts used as optional diagnostic enrichment.
   *
   * @param versionIds MetadataPackageVersion IDs.
   * @return Normalized version records.
   */
  public virtual List<VersionRecord> getVersions(Set<String> versionIds) {
    if (versionIds == null || versionIds.isEmpty()) {
      return new List<VersionRecord>();
    }
    List<SObject> records = readable(
      Database.query(
        'SELECT Id, Name, MetadataPackageId, ReleaseState, MajorVersion, ' +
          'MinorVersion, PatchVersion, BuildNumber ' +
          'FROM MetadataPackageVersion WHERE Id IN :versionIds ORDER BY Id'
      )
    );
    return toVersions(records);
  }

  /**
   * Loads subscriber facts for the selected org/package pairs.
   *
   * @param orgKeys Subscriber organization keys.
   * @param packageIds MetadataPackage IDs.
   * @return Normalized subscriber records.
   */
  public virtual List<SubscriberRecord> getSubscribers(
    Set<String> orgKeys,
    Set<String> packageIds
  ) {
    if (
      orgKeys == null ||
      orgKeys.isEmpty() ||
      packageIds == null ||
      packageIds.isEmpty()
    ) {
      return new List<SubscriberRecord>();
    }
    List<SObject> records = readable(
      Database.query(
        'SELECT MetadataPackageId, MetadataPackageVersionId, InstalledStatus, ' +
          'OrgKey, OrgName, OrgType, OrgStatus, InstanceName ' +
          'FROM PackageSubscriber WHERE OrgKey IN :orgKeys ' +
          'AND MetadataPackageId IN :packageIds ORDER BY OrgKey, MetadataPackageId'
      )
    );
    return toSubscribers(records);
  }

  /**
   * Loads request jobs with one overflow row for explicit truncation reporting.
   *
   * @param pushRequestIds Authoritative PackagePushRequest IDs.
   * @param rowLimit Maximum rows including the overflow sentinel.
   * @return Normalized request jobs.
   */
  public virtual List<JobRecord> getRequestJobs(
    Set<String> pushRequestIds,
    Integer rowLimit
  ) {
    if (pushRequestIds == null || pushRequestIds.isEmpty()) {
      return new List<JobRecord>();
    }
    Integer safeLimit = normalizeLimit(rowLimit);
    List<SObject> records = readable(
      Database.query(
        'SELECT Id, PackagePushRequestId, Status, SubscriberOrganizationKey, ' +
          'SystemModstamp, DurationSeconds, EndTime, StartTime ' +
          'FROM PackagePushJob WHERE PackagePushRequestId IN :pushRequestIds ' +
          'ORDER BY PackagePushRequestId, Id LIMIT :safeLimit'
      )
    );
    return toJobs(records);
  }

  /**
   * Loads request error rows with one overflow row for truncation reporting.
   *
   * @param jobIds Scanned request job IDs.
   * @param rowLimit Maximum rows including the overflow sentinel.
   * @return Normalized request error rows.
   */
  public virtual List<ErrorRecord> getRequestErrors(
    Set<String> jobIds,
    Integer rowLimit
  ) {
    return getErrors(jobIds, rowLimit);
  }

  private static Boolean isObjectAvailable(String apiName) {
    return Schema.getGlobalDescribe().containsKey(apiName);
  }

  private static List<SObject> readable(List<SObject> records) {
    return Security.stripInaccessible(AccessType.READABLE, records)
      .getRecords();
  }

  @TestVisible
  private static List<JobRecord> toJobs(List<SObject> records) {
    List<JobRecord> values = new List<JobRecord>();
    for (SObject recordValue : records) {
      JobRecord value = new JobRecord();
      value.id = stringValue(recordValue, 'Id');
      value.pushRequestId = stringValue(recordValue, 'PackagePushRequestId');
      value.status = stringValue(recordValue, 'Status');
      value.subscriberOrgKey = stringValue(
        recordValue,
        'SubscriberOrganizationKey'
      );
      value.durationSeconds = integerValue(recordValue, 'DurationSeconds');
      value.startTime = datetimeValue(recordValue, 'StartTime');
      value.endTime = datetimeValue(recordValue, 'EndTime');
      value.systemModstamp = datetimeValue(recordValue, 'SystemModstamp');
      values.add(value);
    }
    return values;
  }

  @TestVisible
  private static List<ErrorRecord> toErrors(List<SObject> records) {
    List<ErrorRecord> values = new List<ErrorRecord>();
    for (SObject recordValue : records) {
      ErrorRecord value = new ErrorRecord();
      value.id = stringValue(recordValue, 'Id');
      value.jobId = stringValue(recordValue, 'PackagePushJobId');
      value.title = stringValue(recordValue, 'ErrorTitle');
      value.message = stringValue(recordValue, 'ErrorMessage');
      value.type = stringValue(recordValue, 'ErrorType');
      value.details = stringValue(recordValue, 'ErrorDetails');
      value.severity = stringValue(recordValue, 'ErrorSeverity');
      values.add(value);
    }
    return values;
  }

  @TestVisible
  private static List<RequestRecord> toRequests(List<SObject> records) {
    List<RequestRecord> values = new List<RequestRecord>();
    for (SObject recordValue : records) {
      RequestRecord value = new RequestRecord();
      value.id = stringValue(recordValue, 'Id');
      value.packageVersionId = stringValue(recordValue, 'PackageVersionId');
      values.add(value);
    }
    return values;
  }

  @TestVisible
  private static List<VersionRecord> toVersions(List<SObject> records) {
    List<VersionRecord> values = new List<VersionRecord>();
    for (SObject recordValue : records) {
      VersionRecord value = new VersionRecord();
      value.id = stringValue(recordValue, 'Id');
      value.name = stringValue(recordValue, 'Name');
      value.packageId = stringValue(recordValue, 'MetadataPackageId');
      value.releaseState = stringValue(recordValue, 'ReleaseState');
      value.majorVersion = integerValue(recordValue, 'MajorVersion');
      value.minorVersion = integerValue(recordValue, 'MinorVersion');
      value.patchVersion = integerValue(recordValue, 'PatchVersion');
      value.buildNumber = integerValue(recordValue, 'BuildNumber');
      values.add(value);
    }
    return values;
  }

  @TestVisible
  private static List<SubscriberRecord> toSubscribers(List<SObject> records) {
    List<SubscriberRecord> values = new List<SubscriberRecord>();
    for (SObject recordValue : records) {
      SubscriberRecord value = new SubscriberRecord();
      value.packageId = stringValue(recordValue, 'MetadataPackageId');
      value.installedVersionId = stringValue(
        recordValue,
        'MetadataPackageVersionId'
      );
      value.installedStatus = stringValue(recordValue, 'InstalledStatus');
      value.orgKey = stringValue(recordValue, 'OrgKey');
      value.orgName = stringValue(recordValue, 'OrgName');
      value.orgType = stringValue(recordValue, 'OrgType');
      value.orgStatus = stringValue(recordValue, 'OrgStatus');
      value.instanceName = stringValue(recordValue, 'InstanceName');
      values.add(value);
    }
    return values;
  }

  private static String stringValue(SObject recordValue, String fieldName) {
    Object rawValue = recordValue.get(fieldName);
    return rawValue == null ? null : String.valueOf(rawValue);
  }

  private static Integer integerValue(SObject recordValue, String fieldName) {
    Object rawValue = recordValue.get(fieldName);
    return rawValue == null ? null : Integer.valueOf(String.valueOf(rawValue));
  }

  private static Datetime datetimeValue(SObject recordValue, String fieldName) {
    return (Datetime) recordValue.get(fieldName);
  }

  private static Integer normalizeLimit(Integer rowLimit) {
    return rowLimit == null || rowLimit < 1 ? 1 : rowLimit;
  }

  /** Normalized PackagePushJob query record. */
  public class JobRecord {
    public String id;
    public String pushRequestId;
    public String status;
    public String subscriberOrgKey;
    public Integer durationSeconds;
    public Datetime startTime;
    public Datetime endTime;
    public Datetime systemModstamp;
  }

  /** Normalized PackagePushError query record. */
  public class ErrorRecord {
    public String id;
    public String jobId;
    public String title;
    public String message;
    public String type;
    public String details;
    public String severity;
  }

  /** Normalized PackagePushRequest query record. */
  public class RequestRecord {
    public String id;
    public String packageVersionId;
  }

  /** Normalized MetadataPackageVersion query record. */
  public class VersionRecord {
    public String id;
    public String packageId;
    public String name;
    public String releaseState;
    public Integer majorVersion;
    public Integer minorVersion;
    public Integer patchVersion;
    public Integer buildNumber;
  }

  /** Normalized PackageSubscriber query record. */
  public class SubscriberRecord {
    public String orgKey;
    public String packageId;
    public String orgName;
    public String orgType;
    public String instanceName;
    public String orgStatus;
    public String installedStatus;
    public String installedVersionId;
  }
}
