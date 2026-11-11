/** Bounded Tooling API lookup for the highest released package version. */
public with sharing class HeadlessPushTargetLookup {
  /** Resolve an exact package identity before selecting the released target. */
  public static List<Map<String, Object>> latest(
    String packageName,
    String selectedPackageId
  ) {
    if (String.isBlank(packageName) && String.isBlank(selectedPackageId)) {
      throw new HeadlessPushService.PushException(
        'Provide a package name or package ID.'
      );
    }
    if (String.isNotBlank(packageName) && packageName.length() > 255) {
      throw new HeadlessPushService.PushException('Package name is too long.');
    }
    String whereClause;
    if (String.isNotBlank(selectedPackageId)) {
      if (
        !Pattern.matches(
          '^0Ho[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$',
          selectedPackageId
        )
      ) {
        throw new HeadlessPushService.PushException('Invalid package ID.');
      }
      whereClause =
        'Id=\'' +
        String.escapeSingleQuotes(selectedPackageId) +
        '\'';
      if (String.isNotBlank(packageName)) {
        whereClause +=
          ' AND Name=\'' +
          String.escapeSingleQuotes(packageName.trim()) +
          '\'';
      }
    } else {
      whereClause =
        'Name=\'' +
        String.escapeSingleQuotes(packageName.trim()) +
        '\'';
    }
    List<Object> packages = Package2Interface.submitQuery(
      'SELECT Id,Name FROM Package2 WHERE IsDeprecated=false AND ' +
        whereClause +
        ' ORDER BY Id LIMIT 2',
      10000
    );
    List<Map<String, Object>> result = new List<Map<String, Object>>();
    if (packages.size() != 1) {
      for (Object item : packages) {
        result.add((Map<String, Object>) item);
      }
      return result;
    }
    String packageId = String.valueOf(
      ((Map<String, Object>) packages[0]).get('Id')
    );
    if (!Pattern.matches('^0Ho[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$', packageId)) {
      throw new HeadlessPushService.PushException(
        'Invalid package identity returned by Salesforce.'
      );
    }
    String q =
      'SELECT SubscriberPackageVersionId,Package2Id,IsReleased,IsDeprecated,MajorVersion,MinorVersion,PatchVersion,BuildNumber FROM Package2Version WHERE Package2Id=\'' +
      String.escapeSingleQuotes(packageId) +
      '\' AND IsReleased=true AND IsDeprecated=false ORDER BY MajorVersion DESC, MinorVersion DESC, PatchVersion DESC, BuildNumber DESC, Id DESC LIMIT 2';
    for (Object item : Package2Interface.submitQuery(q, 10000)) {
      result.add((Map<String, Object>) item);
    }
    if (result.isEmpty()) {
      result.add(
        new Map<String, Object>{
          'Package2Id' => packageId,
          'noReleasedVersions' => true
        }
      );
    } else if (result.size() > 1) {
      Boolean tied = true;
      for (
        String field : new List<String>{
          'MajorVersion',
          'MinorVersion',
          'PatchVersion',
          'BuildNumber'
        }
      ) {
        if (
          String.valueOf(result[0].get(field)) !=
          String.valueOf(result[1].get(field))
        ) {
          tied = false;
          break;
        }
      }
      if (!tied) {
        result.remove(1);
      }
    }
    return result;
  }
  /** Return exact version matches, or released candidates when no version is specified. */
  public static List<Map<String, Object>> lookup(
    String packageName,
    String versionNumber
  ) {
    if (String.isBlank(packageName) || packageName.length() > 255) {
      throw new HeadlessPushService.PushException(
        'Provide an exact package name.'
      );
    }
    String query =
      'SELECT SubscriberPackageVersionId, Package2Id, Package2.Name, IsReleased, IsDeprecated, MajorVersion, MinorVersion, PatchVersion, BuildNumber FROM Package2Version WHERE IsDeprecated=false AND Package2.IsDeprecated=false AND Package2.Name=\'' +
      String.escapeSingleQuotes(packageName.trim()) +
      '\'';
    if (String.isBlank(versionNumber)) {
      query += ' AND IsReleased=true';
    }
    if (String.isNotBlank(versionNumber)) {
      if (
        !Pattern.matches(
          '[0-9]+\\.[0-9]+(\\.[0-9]+){0,2}',
          versionNumber.trim()
        )
      ) {
        throw new HeadlessPushService.PushException(
          'Use a numeric version such as 9.41 or 9.41.0.1.'
        );
      }
      List<String> parts = versionNumber.trim().split('\\.');
      List<String> fields = new List<String>{
        'MajorVersion',
        'MinorVersion',
        'PatchVersion',
        'BuildNumber'
      };
      for (Integer index = 0; index < parts.size(); index++) {
        query +=
          ' AND ' +
          fields[index] +
          '=' +
          String.valueOf(Integer.valueOf(parts[index]));
      }
    }
    List<Map<String, Object>> values = new List<Map<String, Object>>();
    for (
      Object row : Package2Interface.submitQuery(
        query +
        ' ORDER BY MajorVersion DESC, MinorVersion DESC, PatchVersion DESC, BuildNumber DESC LIMIT 11',
        10000
      )
    ) {
      values.add((Map<String, Object>) row);
    }
    return values;
  }

  /** Retrieve identity and tuple even for an explicitly requested unreleased version. */
  public static Map<String, Object> identity(String versionId) {
    String idValue = HeadlessPushService.canonicalId(versionId, '04t');
    List<Object> rows = Package2Interface.submitQuery(
      'SELECT Package2Id,Package2.Name,MajorVersion,MinorVersion,PatchVersion,BuildNumber FROM Package2Version WHERE SubscriberPackageVersionId=\'' +
        String.escapeSingleQuotes(idValue) +
        '\' LIMIT 1',
      10000
    );
    if (rows.isEmpty()) {
      throw new HeadlessPushService.PushException(
        'The selected version was not found in this Dev Hub.'
      );
    }
    return (Map<String, Object>) rows[0];
  }
  /** Check that all supplied selectors identify the same version and package. */
  public static void validateIdentity(
    HeadlessResolvePushTargetAction.Request input,
    Map<String, Object> identity
  ) {
    if (
      String.isNotBlank(input.packageId) &&
      HeadlessPushService.canonicalId(input.packageId, '0Ho') !=
      HeadlessPushService.canonicalId(
        (String) identity.get('Package2Id'),
        '0Ho'
      )
    ) {
      throw new HeadlessPushService.PushException(
        'The selected version does not belong to the requested package ID.'
      );
    }
    Map<String, Object> owner = (Map<String, Object>) identity.get('Package2');
    if (
      String.isNotBlank(input.packageName) &&
      (owner == null ||
      !input.packageName.trim()
        .equalsIgnoreCase(String.valueOf(owner.get('Name'))))
    ) {
      throw new HeadlessPushService.PushException(
        'The selected version does not belong to the requested package name.'
      );
    }
    if (String.isNotBlank(input.versionNumber)) {
      if (
        !Pattern.matches(
          '[0-9]+\\.[0-9]+(\\.[0-9]+){0,2}',
          input.versionNumber.trim()
        )
      ) {
        throw new HeadlessPushService.PushException(
          'Use a numeric version such as 9.41 or 9.41.0.1.'
        );
      }
      List<String> parts = input.versionNumber.trim().split('\\.');
      List<String> fields = new List<String>{
        'MajorVersion',
        'MinorVersion',
        'PatchVersion',
        'BuildNumber'
      };
      for (Integer i = 0; i < parts.size(); i++) {
        if (
          Decimal.valueOf(parts[i]) !=
          Decimal.valueOf(String.valueOf(identity.get(fields[i])))
        ) {
          throw new HeadlessPushService.PushException(
            'The selected version does not match the requested version number.'
          );
        }
      }
    }
  }
}
