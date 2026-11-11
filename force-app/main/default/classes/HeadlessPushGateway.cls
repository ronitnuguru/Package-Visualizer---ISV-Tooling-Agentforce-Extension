/** Bounded Salesforce query, File, and existing base-service integration boundary. */
public virtual with sharing class HeadlessPushGateway {
  /** Requires both product permissions and configured OAuth self-callouts. */
  public virtual void authorize() {
    if (
      !FeatureManagement.checkPermission('Package_Visualizer_Core') ||
      !FeatureManagement.checkPermission('Package_Visualizer_Push_Upgrade')
    ) {
      throw new HeadlessPushService.PushException(
        'Package Visualizer core and push permissions are required.'
      );
    }
    if (!Package2Interface.isNamedCredentialEnabled()) {
      throw new HeadlessPushService.PushException(
        'Enable the Package Visualizer Named Credential before headless push operations.'
      );
    }
  }
  /** Resolves the owning package and all known lower package versions in the Dev Hub. */
  public virtual Map<String, Object> target(String versionId) {
    Map<String, Object> v = targetHeader(versionId);
    Map<String, Object> p = (Map<String, Object>) v.get('Package2');
    String kind = (String) p.get('ContainerOptions');
    Boolean reviewed = true;
    String package2Id = (String) v.get('Package2Id');
    List<Object> candidates = Package2Interface.submitQuery(
      'SELECT SubscriberPackageVersionId, MajorVersion, MinorVersion, PatchVersion, BuildNumber FROM Package2Version WHERE Package2Id = \'' +
        String.escapeSingleQuotes(package2Id) +
        '\' LIMIT 2000',
      10000
    );
    if (candidates.size() >= 2000) {
      throw new HeadlessPushService.PushException(
        'Package version inventory reached the 2000-record lookup bound; narrow the package version inventory or enable paginated lookup before preparing an upgrade.'
      );
    }
    List<String> lower = new List<String>();
    for (Object item : candidates) {
      Map<String, Object> row = (Map<String, Object>) item;
      if (isLower(row, v)) {
        lower.add((String) row.get('SubscriberPackageVersionId'));
      }
    }
    return new Map<String, Object>{
      'packageId' => p.get('SubscriberPackageId'),
      'versionId' => versionId,
      'managed' => kind == 'Managed',
      'reviewed' => reviewed,
      'released' => true,
      'lowerVersionIds' => lower
    };
  }
  /** Bounded header checks shared by readiness and preparation; never scans lower versions. */
  public virtual Map<String, Object> targetHeader(String versionId) {
    List<Object> versions = Package2Interface.submitQuery(
      'SELECT Id, Package2Id, SubscriberPackageVersionId, IsReleased, IsDeprecated, MajorVersion, MinorVersion, PatchVersion, BuildNumber, Package2.SubscriberPackageId, Package2.ContainerOptions FROM Package2Version WHERE SubscriberPackageVersionId = \'' +
        String.escapeSingleQuotes(versionId) +
        '\' LIMIT 1',
      10000
    );
    if (versions.isEmpty()) {
      throw new HeadlessPushService.PushException(
        'Target version is not owned by this Dev Hub.'
      );
    }
    Map<String, Object> v = (Map<String, Object>) versions[0];
    Map<String, Object> p = (Map<String, Object>) v.get('Package2');
    if (
      v.get('IsReleased') != true ||
      v.get('IsDeprecated') == true ||
      p == null
    ) {
      throw new HeadlessPushService.PushException(
        'Select a released, non-deprecated target version.'
      );
    }
    String kind = (String) p.get('ContainerOptions');
    if (kind != 'Managed' && kind != 'Unlocked') {
      throw new HeadlessPushService.PushException(
        'Only second-generation managed and unlocked packages are supported.'
      );
    }
    Boolean reviewed = kind == 'Unlocked';
    if (!reviewed) {
      List<Object> review = Package2Interface.submitQuery(
        'SELECT IsSecurityReviewed FROM SubscriberPackageVersion WHERE Id = \'' +
          String.escapeSingleQuotes(versionId) +
          '\' LIMIT 1',
        10000
      );
      reviewed =
        !review.isEmpty() &&
        ((Map<String, Object>) review[0]).get('IsSecurityReviewed') == true;
    }
    if (!reviewed) {
      throw new HeadlessPushService.PushException(
        'The managed target must pass security review and have push upgrades enabled.'
      );
    }
    return v;
  }
  private static Boolean isLower(
    Map<String, Object> left,
    Map<String, Object> right
  ) {
    for (
      String field : new List<String>{
        'MajorVersion',
        'MinorVersion',
        'PatchVersion',
        'BuildNumber'
      }
    ) {
      Decimal a = Decimal.valueOf(String.valueOf(left.get(field)));
      Decimal b = Decimal.valueOf(String.valueOf(right.get(field)));
      if (a != b) {
        return a < b;
      }
    }
    return false;
  }
  /** Reads at most 2001 matching package-scoped subscribers; no OFFSET truncation. */
  public virtual List<Map<String, Object>> subscribers(
    String packageId,
    Set<String> orgIds,
    Set<String> installedVersions,
    List<String> orgTypes,
    List<String> statuses,
    List<String> instances
  ) {
    String query = 'SELECT Id, MetadataPackageId, MetadataPackageVersionId, OrgKey, OrgName, OrgType, OrgStatus, InstanceName, HasRestrictionEnabled, IsCustomUpgradeAllowed FROM PackageSubscriber WHERE MetadataPackageId = :packageId';
    Map<String, Object> binds = new Map<String, Object>{
      'packageId' => packageId
    };
    if (orgIds != null && !orgIds.isEmpty()) {
      query += ' AND OrgKey IN :orgIds';
      binds.put('orgIds', orgIds);
    }
    if (installedVersions != null && !installedVersions.isEmpty()) {
      query += ' AND MetadataPackageVersionId IN :installedVersions';
      binds.put('installedVersions', installedVersions);
    }
    if (orgTypes != null && !orgTypes.isEmpty()) {
      query += ' AND OrgType IN :orgTypes';
      binds.put('orgTypes', orgTypes);
    }
    if (statuses != null && !statuses.isEmpty()) {
      query += ' AND OrgStatus IN :statuses';
      binds.put('statuses', statuses);
    }
    if (instances != null && !instances.isEmpty()) {
      query += ' AND InstanceName IN :instances';
      binds.put('instances', instances);
    }
    return queryRows(query + ' ORDER BY OrgKey LIMIT 2001', binds);
  }
  /** Reads a request under the calling user's record/field permissions. */
  public virtual Map<String, Object> request(String requestId) {
    List<Map<String, Object>> rows = queryRows(
      'SELECT Id, PackageVersionId, ScheduledStartTime, Status FROM PackagePushRequest WHERE Id = :requestId LIMIT 1',
      new Map<String, Object>{ 'requestId' => requestId }
    );
    if (rows.isEmpty()) {
      throw new HeadlessPushService.PushException(
        'Push request is not accessible.'
      );
    }
    return rows[0];
  }
  /** Reads the complete bounded job set and detailed platform errors. */
  public virtual List<Map<String, Object>> jobs(String requestId) {
    return queryRows(
      'SELECT Id, SubscriberOrganizationKey, Status FROM PackagePushJob WHERE PackagePushRequestId = :requestId ORDER BY SubscriberOrganizationKey LIMIT 2001',
      new Map<String, Object>{ 'requestId' => requestId }
    );
  }
  /** Fetches errors only for the displayed ten-job page, bounding response size. */
  public virtual List<Map<String, Object>> jobDetails(
    String requestId,
    Set<String> jobIds
  ) {
    if (jobIds.isEmpty()) {
      return new List<Map<String, Object>>();
    }
    return queryRows(
      'SELECT Id, SubscriberOrganizationKey, Status, (SELECT ErrorTitle, ErrorType, ErrorMessage FROM PackagePushErrors LIMIT 5) FROM PackagePushJob WHERE PackagePushRequestId = :requestId AND Id IN :jobIds ORDER BY SubscriberOrganizationKey LIMIT 10',
      new Map<String, Object>{ 'requestId' => requestId, 'jobIds' => jobIds }
    );
  }
  /** Returns a bounded set of the operator's private submission report links. */
  public virtual List<Map<String, Object>> reports(
    String requestId,
    String manifestId
  ) {
    String pattern = 'push-%' + requestId + '-%';
    String finalizerPattern =
      'push-staging-reconciliation-' +
      manifestId +
      '-%';
    Id operatorId = UserInfo.getUserId();
    List<ContentVersion> reports = [
      SELECT Id, Title, CreatedDate
      FROM ContentVersion
      WHERE
        CreatedById = :operatorId
        AND (Title LIKE :pattern
        OR Title LIKE :finalizerPattern)
        AND IsLatest = TRUE
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 20
    ];
    List<Map<String, Object>> values = new List<Map<String, Object>>();
    for (ContentVersion report : reports) {
      values.add(
        new Map<String, Object>{
          'fileVersionId' => String.valueOf(report.Id),
          'title' => report.Title,
          'downloadUrl' => URL.getOrgDomainUrl().toExternalForm() +
          '/sfc/servlet.shepherd/version/download/' +
          report.Id
        }
      );
    }
    return values;
  }
  /** Reads a specific owned File version; avoids silently following the latest version. */
  public virtual ContentVersion file(String versionId) {
    Id fileId = Id.valueOf(versionId);
    List<ContentVersion> rows = [
      SELECT Id, Title, ContentSize, CreatedById
      FROM ContentVersion
      WHERE Id = :fileId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty() || rows[0].CreatedById != UserInfo.getUserId()) {
      throw new HeadlessPushService.PushException(
        'File version is not owned by the current operator.'
      );
    }
    if (rows[0].ContentSize > 262144) {
      throw new HeadlessPushService.PushException(
        'File exceeds the v1 input bound (256 KB).'
      );
    }
    return [
      SELECT Id, Title, VersionData, ContentSize, CreatedById
      FROM ContentVersion
      WHERE Id = :fileId
      WITH USER_MODE
      LIMIT 1
    ];
  }
  /** Saves a personal, authenticated-access-only artifact, using user-mode DML. */
  public virtual String saveFile(String name, String content) {
    ContentVersion document = new ContentVersion(
      Title = name,
      PathOnClient = name,
      VersionData = Blob.valueOf(content)
    );
    Database.insert(document, AccessLevel.USER_MODE);
    return String.valueOf(document.Id);
  }
  /** Creates the standard request without dispatching. */
  public virtual String createRequest(String versionId, Datetime startTime) {
    return PushUpgradesInterface.createPushRequest(versionId, startTime);
  }
  /** Uses the shared base transport; results are individual records. */
  public virtual List<Object> stageChunk(
    String requestId,
    List<String> orgIds
  ) {
    return (List<Object>) JSON.deserializeUntyped(
      PushUpgradesInterface.stagePushJobChunk(requestId, orgIds)
    );
  }
  /** Uses the constrained status transition after service-level validation. */
  public virtual void setStatus(String requestId, String status) {
    PushUpgradesInterface.updatePushRequest(requestId, status);
  }
  /** Enqueues a new transaction after local File writes have committed. */
  public virtual String enqueue(
    String manifestId,
    String digest,
    Integer offset
  ) {
    return String.valueOf(
      System.enqueueJob(
        new HeadlessPushStageQueueable(manifestId, digest, offset)
      )
    );
  }
  /** Delegates package candidates to the bounded Tooling API selector. */
  public virtual List<Map<String,Object>> lookupTargets(String packageName,String versionNumber) {return HeadlessPushTargetLookup.lookup(packageName,versionNumber);}
  /** Resolves an exact package and highest released target. */
  public virtual List<Map<String, Object>> lookupLatestReleased(
    String packageName
  ) {
    return lookupLatestReleased(packageName, null);
  }
  /** Uses a selected package ID when names collide. */
  public virtual List<Map<String, Object>> lookupLatestReleased(
    String packageName,
    String selectedPackageId
  ) {
    return HeadlessPushTargetLookup.latest(packageName, selectedPackageId);
  }
  /** Reads package identity when several target selectors were supplied. */
  public virtual Map<String,Object> targetIdentity(String versionId) {return HeadlessPushTargetLookup.identity(versionId);}
  /** Returns normalized readiness through the shared selection rules. */
  public virtual Map<String, Object> readiness(String versionId) {
    return HeadlessPushSelectionService.readiness(versionId, this);
  }
  /** Reads only the selected version's coverage and validation flags. */
  public virtual List<Object> readinessFields(String versionId) {
    String idValue = HeadlessPushService.canonicalId(versionId, '04t');
    List<Object> rows = Package2Interface.submitQuery(
      'SELECT HasPassedCodeCoverageCheck, ValidationSkipped FROM Package2Version WHERE SubscriberPackageVersionId=\'' +
        String.escapeSingleQuotes(idValue) +
        '\' LIMIT 1',
      10000
    );
    return rows;
  }
  /** Reads metadata only, retaining owner filtering and stable ordering. */
  public virtual List<Map<String, Object>> manifests(
    String requestId,
    Datetime beforeDate,
    String beforeId
  ) {
    if ((beforeDate == null) != String.isBlank(beforeId)) {
      throw new HeadlessPushService.PushException(
        'Provide both cursor fields.'
      );
    }
    if (String.isNotBlank(beforeId)) {
      beforeId = HeadlessPushService.canonicalId(beforeId, '068');
    }
    Id operatorId = UserInfo.getUserId();
    String pattern = requestId == null
      ? 'push-manifest-%.json'
      : 'push-manifest-' + requestId + '.json';
    return maps(
      Database.queryWithBinds(
        'SELECT Id,Title,CreatedDate,CreatedById FROM ContentVersion WHERE CreatedById=:operatorId AND IsLatest=true AND Title LIKE :pattern' +
          (beforeDate == null
            ? ''
            : ' AND (CreatedDate < :beforeDate OR (CreatedDate = :beforeDate AND Id < :beforeId))') +
          ' ORDER BY CreatedDate DESC,Id DESC LIMIT 10',
        new Map<String, Object>{
          'operatorId' => operatorId,
          'pattern' => pattern,
          'beforeDate' => beforeDate,
          'beforeId' => beforeId
        },
        AccessLevel.USER_MODE
      )
    );
  }
  /** Bulk lookup avoids one request query per File. */
  public virtual List<Map<String, Object>> requests(Set<String> ids) {
    if (ids.isEmpty()) {
      return new List<Map<String, Object>>();
    }
    return queryRows(
      'SELECT Id,PackageVersionId,ScheduledStartTime,Status FROM PackagePushRequest WHERE Id IN :ids ORDER BY Id LIMIT 10',
      new Map<String, Object>{ 'ids' => ids }
    );
  }
  /** Any competing active or successful job blocks replay; no retry of uncertain writes. */
  public virtual List<Map<String, Object>> overlappingJobs(
    Set<String> orgIds,
    String targetId,
    String sourceRequestId
  ) {
    if (orgIds.isEmpty()) {
      return new List<Map<String, Object>>();
    }
    Set<String> ids = new Set<String>(orgIds);
    for (String idValue : orgIds) {
      ids.add(idValue.left(15));
    }
    return queryRows(
      'SELECT Id FROM PackagePushJob WHERE SubscriberOrganizationKey IN :ids AND PackagePushRequestId != :sourceRequestId AND PackagePushRequest.PackageVersionId=:targetId AND (Status=\'Succeeded\' OR (Status IN (\'Created\',\'Pending\',\'InProgress\') AND PackagePushRequest.Status != \'Canceled\')) LIMIT 1',
      new Map<String, Object>{
        'ids' => ids,
        'sourceRequestId' => sourceRequestId,
        'targetId' => targetId
      }
    );
  }
  /** Loads friendly labels for only the versions on a bounded run page. */
  public virtual Map<String, String> versionLabels(Set<String> ids) {
    Map<String, String> labels = new Map<String, String>();
    if (ids.isEmpty()) {
      return labels;
    }
    List<String> quoted = new List<String>();
    for (String value : ids) {
      quoted.add(
        '\'' +
          String.escapeSingleQuotes(
            HeadlessPushService.canonicalId(value, '04t')
          ) +
          '\''
      );
    }
    for (
      Object value : Package2Interface.submitQuery(
        'SELECT SubscriberPackageVersionId,Package2.Name,MajorVersion,MinorVersion,PatchVersion,BuildNumber FROM Package2Version WHERE SubscriberPackageVersionId IN (' +
          String.join(quoted, ',') +
          ') LIMIT 10',
        10000
      )
    ) {
      Map<String, Object> row = (Map<String, Object>) value;
      Map<String, Object> owner = (Map<String, Object>) row.get('Package2');
      labels.put(
        HeadlessPushService.canonicalId(
          (String) row.get('SubscriberPackageVersionId'),
          '04t'
        ),
        String.valueOf(owner.get('Name')) +
          ' ' +
          String.valueOf(row.get('MajorVersion')) +
          '.' +
          String.valueOf(row.get('MinorVersion')) +
          '.' +
          String.valueOf(row.get('PatchVersion')) +
          '.' +
          String.valueOf(row.get('BuildNumber'))
      );
    }
    return labels;
  }
  /** Executes publisher queries with caller permissions; overridable for isolated tests. */
  protected virtual List<Map<String, Object>> queryRows(
    String query,
    Map<String, Object> binds
  ) {
    return maps(Database.queryWithBinds(query, binds, AccessLevel.USER_MODE));
  }
  private static List<Map<String, Object>> maps(List<SObject> rows) {
    List<Map<String, Object>> values = new List<Map<String, Object>>();
    for (SObject row : rows) {
      values.add(
        (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(row))
      );
    }
    return values;
  }
}
