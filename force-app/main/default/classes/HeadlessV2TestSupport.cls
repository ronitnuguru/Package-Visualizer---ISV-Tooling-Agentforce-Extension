/** In-memory Salesforce boundary and synthetic fixtures for v2 actions. */
@IsTest
public with sharing class HeadlessV2TestSupport {
  public static final String REQUEST_ID = '0DV000000000001';
  public static final String MANIFEST_ID = '068000000000099';
  public static final String CSV_ID = '068000000000098';
  public static final String TARGET_ID = '04t000000000002';
  public static final String OLD_ID = '04t000000000001';
  public static final String PACKAGE_ID = '033000000000001';
  public static Gateway install(Integer count) {
    Gateway fake = new Gateway();
    fake.subscriberRows = HeadlessPushTestSupport.subscribers(count);
    HeadlessPushService.gateway = fake;
    return fake;
  }
  public static HeadlessPushService.Manifest manifest(
    Gateway fake,
    Integer count
  ) {
    HeadlessPushService.Manifest value = new HeadlessPushService.Manifest();
    value.requestId = REQUEST_ID;
    value.targetVersionId = HeadlessPushService.canonicalId(TARGET_ID, '04t');
    value.scheduledStartTime = fake.schedule;
    value.initiatorId = UserInfo.getUserId();
    value.csvVersionId = CSV_ID;
    value.orgIds = HeadlessPushTestSupport.keys(count);
    value.digest = HeadlessPushService.digest(value);
    fake.files.put(MANIFEST_ID, JSON.serialize(value));
    fake.files.put(CSV_ID, String.join(value.orgIds, '\n'));
    return value;
  }
  public static Map<String, Object> candidate() {
    return new Map<String, Object>{
      'Id' => '05i000000000002',
      'Package2Id' => '0Ho000000000001',
      'SubscriberPackageVersionId' => TARGET_ID,
      'IsReleased' => true,
      'IsDeprecated' => false,
      'HasPassedCodeCoverageCheck' => true,
      'ValidationSkipped' => false,
      'MajorVersion' => 9,
      'MinorVersion' => 41,
      'PatchVersion' => 0,
      'BuildNumber' => 1,
      'Package2' => new Map<String, Object>{
        'Name' => 'Billing',
        'SubscriberPackageId' => PACKAGE_ID,
        'ContainerOptions' => 'Managed'
      }
    };
  }
  public class Gateway extends HeadlessPushGateway {
    public Boolean denied = false;
    public Map<String,Map<String,Object>> requestById=new Map<String,Map<String,Object>>();
    public Map<String,List<Map<String,Object>>> jobsByRequest=new Map<String,List<Map<String,Object>>>();
    public String competingRequestId;
    public String lastExcludedRequestId;
    public String parentStatus = 'Failed';
    public Datetime schedule = System.now().addDays(1);
    public List<Map<String, Object>> subscriberRows = new List<Map<String, Object>>();
    public List<Map<String, Object>> platformJobs = new List<Map<String, Object>>();
    public List<Map<String, Object>> overlaps = new List<Map<String, Object>>();
    public List<Map<String, Object>> metadataRows = new List<Map<String, Object>>();
    public List<Map<String, Object>> candidateRows = new List<Map<String, Object>>{
      candidate()
    };
    public Map<String, Object> readinessValue = new Map<String, Object>{
      'eligible' => true,
      'blockers' => new List<String>(),
      'securityReviewStatus' => 'UNKNOWN'
    };
    public Map<String, String> files = new Map<String, String>();
    public Integer createCount = 0,
      enqueueCount = 0,
      fileReads = 0,
      requestBatchReads = 0;
    public override void authorize() {
      if (denied)
        throw new HeadlessPushService.PushException('Access denied');
    }
    public override Map<String, Object> target(String versionId) {
      return new Map<String, Object>{
        'packageId' => PACKAGE_ID,
        'versionId' => versionId,
        'managed' => true,
        'reviewed' => true,
        'released' => true,
        'lowerVersionIds' => new List<String>{ OLD_ID }
      };
    }
    public override List<Map<String, Object>> subscribers(
      String packageId,
      Set<String> orgIds,
      Set<String> versions,
      List<String> kinds,
      List<String> statuses,
      List<String> instances
    ) {
      return subscriberRows;
    }
    public override Map<String, Object> request(String requestId) {
      if(requestById.containsKey(requestId)){return requestById.get(requestId);}
      return new Map<String, Object>{
        'Id' => requestId,
        'PackageVersionId' => TARGET_ID,
        'ScheduledStartTime' => schedule,
        'Status' => parentStatus
      };
    }
    public override List<Map<String, Object>> jobs(String requestId) {
      if(jobsByRequest.containsKey(requestId)){return jobsByRequest.get(requestId);}
      return platformJobs;
    }
    public override List<Map<String, Object>> jobDetails(
      String requestId,
      Set<String> ids
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
      fileReads++;
      String body = files.get(versionId.left(15));
      if (body == null)
        throw new HeadlessPushService.PushException('Missing owned file');
      ContentVersion result = new ContentVersion();
      result.VersionData = Blob.valueOf(body);
      return result;
    }
    public override String saveFile(String name, String content) {
      String id = '068' + String.valueOf(files.size() + 1).leftPad(12, '0');
      files.put(id, content);
      return id;
    }
    public override String createRequest(String versionId, Datetime startTime) {
      createCount++;
      String created='0DV000000000002';
      requestById.put(created,new Map<String,Object>{'Id'=>created,'PackageVersionId'=>versionId,'ScheduledStartTime'=>startTime,'Status'=>'Created'});
      return created;
    }
    public override String enqueue(
      String manifestId,
      String digest,
      Integer offset
    ) {
      enqueueCount++;
      return 'queued';
    }
    public override void setStatus(String requestId, String status) {
      if(requestById.containsKey(requestId)){requestById.get(requestId).put('Status',status);return;}
      parentStatus = status;
    }
    public override Map<String,String> versionLabels(Set<String> ids) {
      Map<String,String> labels=new Map<String,String>();
      for(String versionId:ids){labels.put(HeadlessPushService.canonicalId(versionId,'04t'),'Billing 9.41.0.1');}
      return labels;
    }
    public override List<Map<String, Object>> lookupTargets(
      String packageName,
      String versionNumber
    ) {
      return candidateRows;
    }
    public override Map<String, Object> readiness(String versionId) {
      return readinessValue;
    }
    public override List<Map<String, Object>> manifests(
      String requestId,
      Datetime beforeDate,
      String beforeId
    ) {
      return metadataRows;
    }
    public override List<Map<String, Object>> requests(Set<String> ids) {
      requestBatchReads++;
      List<Map<String, Object>> rows = new List<Map<String, Object>>();
      for (String id : ids)
        rows.add(request(id));
      return rows;
    }
    public override List<Map<String, Object>> overlappingJobs(
      Set<String> orgIds,
      String targetId,
      String sourceRequestId
    ) {
      lastExcludedRequestId=sourceRequestId;
      if(competingRequestId!=null && competingRequestId==sourceRequestId){return new List<Map<String,Object>>();}
      return overlaps;
    }
  }
}
