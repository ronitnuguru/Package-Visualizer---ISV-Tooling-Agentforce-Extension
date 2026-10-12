@isTest
private with sharing class AgentforcePackageQueryServiceTest {
  @isTest
  static void normalizesFixedToolingQueriesAndShortCircuitsEmptyInputs() {
    Test.setMock(
      HttpCalloutMock.class,
      new AgentforcePackageQueryServiceCalloutMock()
    );
    AgentforcePackageQueryService serviceValue = new AgentforcePackageQueryService();
    Set<String> versionIds = new Set<String>{ '04t000000000000AAA' };
    Set<String> buildIds = new Set<String>{ '08c000000000000AAA' };

    Test.startTest();
    Integer packageCount = serviceValue.getActivePackageCount();
    Integer versionCount = serviceValue.getVersionCount();
    Integer buildCount = serviceValue.getRecentBuildCount();
    List<AgentforcePackageQueryService.PackageRecord> packages = serviceValue.getActivePackages(
      500
    );
    List<AgentforcePackageQueryService.VersionRecord> versions = serviceValue.getVersions(
      2000
    );
    List<AgentforcePackageQueryService.VersionRecord> selectedVersions = serviceValue.getVersionsBySubscriberIds(
      versionIds
    );
    List<AgentforcePackageQueryService.BuildRecord> builds = serviceValue.getRecentBuilds(
      2000
    );
    List<AgentforcePackageQueryService.BuildRecord> selectedBuilds = serviceValue.getBuilds(
      buildIds
    );
    List<AgentforcePackageQueryService.BuildErrorRecord> errors = serviceValue.getBuildErrors(
      buildIds,
      100
    );
    Map<String, List<String>> dependencies = serviceValue.getDependencies(
      versionIds
    );
    List<AgentforcePackageQueryService.VersionRecord> noVersions = serviceValue.getVersionsBySubscriberIds(
      new Set<String>()
    );
    List<AgentforcePackageQueryService.BuildRecord> noBuilds = serviceValue.getBuilds(
      new Set<String>()
    );
    List<AgentforcePackageQueryService.BuildErrorRecord> noErrors = serviceValue.getBuildErrors(
      new Set<String>(),
      100
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      packageCount,
      'Package count uses Tooling aggregate syntax'
    );
    Assert.areEqual(
      1,
      versionCount,
      'Version count uses Tooling aggregate syntax'
    );
    Assert.areEqual(3, buildCount, 'Grouped build counts are summed');
    Assert.areEqual(
      60000,
      AgentforcePackageQueryService.TOOLING_TIMEOUT_MILLISECONDS,
      'Agentforce Tooling queries use the extended timeout'
    );
    Assert.areEqual(1, packages.size(), 'Fixed Package2 query is normalized');
    Assert.areEqual(
      '0Ho000000000000AAA',
      packages[0].id,
      'Package2 identity is preserved'
    );
    Assert.areEqual(1, versions.size(), 'Fixed version query is normalized');
    Assert.areEqual(
      '04t000000000000AAA',
      versions[0].subscriberPackageVersionId,
      'Subscriber version identity is preserved'
    );
    Assert.areEqual(1, selectedVersions.size(), 'Version selection is fixed');
    Assert.areEqual(1, builds.size(), 'Fixed build query is normalized');
    Assert.areEqual(1, selectedBuilds.size(), 'Build selection is fixed');
    Assert.areEqual(1, errors.size(), 'Fixed build-error query is normalized');
    Assert.areEqual(
      2,
      dependencies.get('04t000000000000AAA').size(),
      'Dependency IDs are normalized'
    );
    Assert.isTrue(noVersions.isEmpty(), 'Empty version inputs short-circuit');
    Assert.isTrue(noBuilds.isEmpty(), 'Empty build inputs short-circuit');
    Assert.isTrue(noErrors.isEmpty(), 'Empty error inputs short-circuit');
  }

  @isTest
  static void safelyQueriesOptionalEnterpriseAggregates() {
    AgentforcePackageQueryService serviceValue = new AgentforcePackageQueryService();
    Set<String> packageIds = new Set<String>{ '033000000000000AAA' };
    Set<String> versionIds = new Set<String>{ '04t000000000000000AAA' };
    Set<String> subscriberIds = new Set<String>{ '0PS000000000000AAA' };

    Test.startTest();
    List<AgentforcePackageQueryService.SubscriberAggregate> subscriberAggregates = serviceValue.getSubscriberAggregates(
      packageIds
    );
    List<AgentforcePackageQueryService.SubscriberRecord> subscribers = serviceValue.getSubscribers(
      subscriberIds
    );
    List<AgentforcePackageQueryService.PushAggregate> pushAggregates = serviceValue.getPushAggregates(
      versionIds
    );
    List<AgentforcePackageQueryService.SubscriberAggregate> noSubscriberAggregates = serviceValue.getSubscriberAggregates(
      new Set<String>()
    );
    List<AgentforcePackageQueryService.SubscriberRecord> noSubscribers = serviceValue.getSubscribers(
      new Set<String>()
    );
    List<AgentforcePackageQueryService.PushAggregate> noPushAggregates = serviceValue.getPushAggregates(
      new Set<String>()
    );
    Test.stopTest();

    Assert.isNotNull(
      subscriberAggregates,
      'Subscriber aggregates return a safe collection'
    );
    Assert.isNotNull(subscribers, 'Subscriber rows return a safe collection');
    Assert.isNotNull(
      pushAggregates,
      'Push aggregates return a safe collection'
    );
    Assert.isTrue(
      noSubscriberAggregates.isEmpty(),
      'Empty subscriber package inputs short-circuit'
    );
    Assert.isTrue(
      noSubscribers.isEmpty(),
      'Empty subscriber inputs short-circuit'
    );
    Assert.isTrue(
      noPushAggregates.isEmpty(),
      'Empty push-version inputs short-circuit'
    );
  }

  private class AgentforcePackageQueryServiceCalloutMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest requestValue) {
      if (
        requestValue.getEndpoint().contains('COUNT%28Id%29+total') &&
        requestValue.getEndpoint()
          .contains('FROM+Package2VersionCreateRequest')
      ) {
        HttpResponse responseValue = new HttpResponse();
        responseValue.setHeader('Content-Type', 'application/json');
        responseValue.setStatusCode(200);
        responseValue.setBody(
          '{"size":2,"totalSize":2,"done":true,"records":[{"Status":"Error","total":1},{"Status":"Success","total":2}]}'
        );
        return responseValue;
      }
      if (requestValue.getEndpoint().contains('COUNT%28Id%29+total')) {
        HttpResponse responseValue = new HttpResponse();
        responseValue.setHeader('Content-Type', 'application/json');
        responseValue.setStatusCode(200);
        responseValue.setBody(
          '{"size":1,"totalSize":1,"done":true,"records":[{"IsDeprecated":false,"total":1}]}'
        );
        return responseValue;
      }
      if (
        requestValue.getEndpoint().contains('FROM+Package2Version') &&
        !requestValue.getEndpoint()
          .contains('FROM+Package2VersionCreateRequest')
      ) {
        HttpResponse responseValue = new HttpResponse();
        responseValue.setHeader('Content-Type', 'application/json');
        responseValue.setStatusCode(200);
        responseValue.setBody(
          '{"size":1,"totalSize":1,"done":true,"records":[{"Id":"05i000000000000AAA","Package2Id":"0Ho000000000000AAA","SubscriberPackageVersionId":"04t000000000000AAA","IsReleased":false,"ValidationSkipped":false,"MajorVersion":0,"MinorVersion":1,"PatchVersion":0,"BuildNumber":2}]}'
        );
        return responseValue;
      }
      if (
        requestValue.getEndpoint().contains(
          'FROM+SubscriberPackageVersion'
        )
      ) {
        HttpResponse responseValue = new HttpResponse();
        responseValue.setHeader('Content-Type', 'application/json');
        responseValue.setStatusCode(200);
        responseValue.setBody(
          '{"size":1,"totalSize":1,"done":true,"records":[{"Id":"04t000000000000AAA","Dependencies":{"ids":[{"subscriberPackageVersionId":"04t000000000001BBB"},{"subscriberPackageVersionId":"04t000000000002CCC"}]}}]}'
        );
        return responseValue;
      }
      return new ToolingAPICalloutMock().respond(requestValue);
    }
  }
}
