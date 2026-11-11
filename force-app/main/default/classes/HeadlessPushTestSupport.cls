/** Synthetic data and in-memory boundaries for headless push tests. */
@IsTest
public with sharing class HeadlessPushTestSupport {
  private static final String TARGET = '04t000000000002';
  private static final String OLD = '04t000000000001';
  private static final String PACKAGE_ID = '033000000000001';
  private static final String REQUEST_ID = '0DV000000000001';
  public static HeadlessPlanPushAction.Request input(Integer count) {
    HeadlessPlanPushAction.Request value = new HeadlessPlanPushAction.Request();
    value.targetVersionId = TARGET;
    value.orgIdsText = String.join(keys(count), '\n');
    return value;
  }

  public static FakeGateway install(Integer count) {
    FakeGateway fake = new FakeGateway();
    fake.subscriberRows = subscribers(count);
    HeadlessPushService.gateway = fake;
    return fake;
  }

  public static List<String> keys(Integer count) {
    List<String> values = new List<String>();
    for (Integer i = 1; i <= count; i++)
      values.add(
        HeadlessPushService.canonicalId(
          '00D' + String.valueOf(i).leftPad(12, '0'),
          '00D'
        )
      );
    return values;
  }

  public static List<Map<String, Object>> subscribers(Integer count) {
    List<Map<String, Object>> values = new List<Map<String, Object>>();
    for (String key : keys(count))
      values.add(
        new Map<String, Object>{
          'OrgKey' => key,
          'MetadataPackageId' => PACKAGE_ID,
          'MetadataPackageVersionId' => OLD,
          'OrgType' => 'Sandbox',
          'OrgStatus' => 'Active',
          'InstanceName' => 'NA1',
          'HasRestrictionEnabled' => false,
          'IsCustomUpgradeAllowed' => true
        }
      );
    return values;
  }

  public static List<Map<String, Object>> jobs(Integer count) {
    List<Map<String, Object>> values = new List<Map<String, Object>>();
    for (String key : keys(count))
      values.add(
        new Map<String, Object>{
          'SubscriberOrganizationKey' => key,
          'Status' => 'Created'
        }
      );
    return values;
  }

  public static HeadlessPushService.Manifest savedManifest(
    FakeGateway fake,
    Integer count
  ) {
    HeadlessPushService.Manifest manifest = new HeadlessPushService.Manifest();
    manifest.requestId = REQUEST_ID;
    fake.schedule = System.now();
    manifest.scheduledStartTime = fake.schedule;
    manifest.targetVersionId = HeadlessPushService.canonicalId(TARGET, '04t');
    manifest.initiatorId = UserInfo.getUserId();
    manifest.csvVersionId = '068000000000098';
    manifest.orgIds = keys(count);
    manifest.digest = HeadlessPushService.digest(manifest);
    fake.savedFiles.put('068000000000099', JSON.serialize(manifest));
    fake.savedFiles.put(
      manifest.csvVersionId,
      String.join(manifest.orgIds, '\n')
    );
    return manifest;
  }

  /** Captures query contracts without requiring publisher objects in the test org. */
  public class QueryGateway extends HeadlessPushGateway {
    public String queryText;
    public Map<String, Object> queryBinds;
    public Integer queryCount = 0;
    public Boolean queryDenied = false;
    public List<Map<String, Object>> rows = new List<Map<String, Object>>();

    protected override List<Map<String, Object>> queryRows(
      String query,
      Map<String, Object> binds
    ) {
      queryCount++;
      queryText = query;
      queryBinds = binds;
      if (queryDenied) {
        throw new HeadlessPushService.PushException('Query access denied');
      }
      return rows;
    }

    public List<Map<String, Object>> ownUser() {
      return super.queryRows(
        'SELECT Id FROM User WHERE Id = :userId LIMIT 1',
        new Map<String, Object>{ 'userId' => UserInfo.getUserId() }
      );
    }
  }

  public class FakeGateway extends HeadlessPushGateway {
    public Boolean denied = false;
    public Boolean partialFailure = false;
    public Boolean uncertain = false;
    public List<Integer> chunkSizes = new List<Integer>();
    public Integer createCount = 0;
    public Integer enqueueCount = 0;
    public String parentStatus = 'Created';
    public Datetime schedule;
    public List<String> statusWrites = new List<String>();
    public Map<String, String> savedFiles = new Map<String, String>();
    public List<Map<String, Object>> subscriberRows = new List<Map<String, Object>>();
    public List<Map<String, Object>> platformJobs = new List<Map<String, Object>>();
    public List<Map<String, Object>> overlapRows = new List<Map<String, Object>>();
    public Integer overlapReads = 0;

    public override void authorize() {
      if (denied)
        throw new HeadlessPushService.PushException('Access denied');
    }
    public override Map<String, Object> target(String versionId) {
      Assert.areEqual(
        HeadlessPushService.canonicalId(TARGET, '04t'),
        versionId,
        'Resolve the explicit target'
      );
      return new Map<String, Object>{
        'packageId' => PACKAGE_ID,
        'versionId' => TARGET,
        'managed' => true,
        'reviewed' => true,
        'released' => true,
        'lowerVersionIds' => new List<String>{ OLD }
      };
    }
    public override List<Map<String, Object>> subscribers(
      String packageId,
      Set<String> orgIds,
      Set<String> installedVersions,
      List<String> orgTypes,
      List<String> statuses,
      List<String> instances
    ) {
      Assert.areEqual(
        PACKAGE_ID,
        packageId,
        'Subscriber queries must be package scoped'
      );
      return subscriberRows;
    }
    public override Map<String, Object> request(String requestId) {
      Assert.areEqual(REQUEST_ID, requestId, 'Reuse the prepared request');
      return new Map<String, Object>{
        'Id' => REQUEST_ID,
        'PackageVersionId' => TARGET,
        'ScheduledStartTime' => schedule,
        'Status' => parentStatus
      };
    }
    public override List<Map<String, Object>> jobs(String requestId) {
      return platformJobs;
    }
    public override List<Map<String, Object>> overlappingJobs(
      Set<String> orgIds,
      String targetId,
      String sourceRequestId
    ) {
      overlapReads++;
      Assert.areEqual(REQUEST_ID, sourceRequestId, 'Exclude the prepared request');
      Assert.areEqual(
        HeadlessPushService.canonicalId(TARGET, '04t'),
        targetId,
        'Check overlaps only for the reviewed target'
      );
      return overlapRows;
    }
    public override List<Map<String, Object>> jobDetails(
      String requestId,
      Set<String> jobIds
    ) {
      return platformJobs;
    }
    public override List<Map<String, Object>> reports(
      String requestId,
      String manifestId
    ) {
      return new List<Map<String, Object>>();
    }
    public override ContentVersion file(String versionId) {
      String content = savedFiles.get(versionId.left(15));
      if (content == null)
        throw new HeadlessPushService.PushException('Missing file');
      ContentVersion result = (ContentVersion) JSON.deserialize(
        JSON.serialize(
          new Map<String, Object>{
            'Id' => versionId,
            'CreatedById' => UserInfo.getUserId()
          }
        ),
        ContentVersion.class
      );
      result.VersionData = Blob.valueOf(content);
      return result;
    }

    public override String saveFile(String name, String content) {
      String fileId =
        '068' + String.valueOf(savedFiles.size() + 1).leftPad(12, '0');
      savedFiles.put(fileId, content);
      return fileId;
    }
    public override String createRequest(String versionId, Datetime startTime) {
      createCount++;
      schedule = startTime == null ? System.now() : startTime;
      return REQUEST_ID;
    }
    public override void setStatus(String requestId, String status) {
      statusWrites.add(status);
      parentStatus = status;
    }
    public override List<Object> stageChunk(
      String requestId,
      List<String> orgIds
    ) {
      chunkSizes.add(orgIds.size());
      List<Object> outcomes = new List<Object>();
      for (Integer i = 0; i < orgIds.size(); i++) {
        Boolean accepted = !partialFailure || i != 0;
        outcomes.add(
          new Map<String, Object>{
            'orgKey' => orgIds[i],
            'success' => accepted,
            'jobId' => accepted ? 'accepted' : null,
            'errors' => new List<Object>()
          }
        );
        if (accepted)
          platformJobs.add(
            new Map<String, Object>{
              'SubscriberOrganizationKey' => orgIds[i],
              'Status' => 'Created'
            }
          );
      }
      if (uncertain)
        throw new CalloutException('Response lost after remote commit');
      return outcomes;
    }
    public override String enqueue(
      String manifestId,
      String expectedDigest,
      Integer offset
    ) {
      enqueueCount++;
      return 'queued';
    }
  }
}
