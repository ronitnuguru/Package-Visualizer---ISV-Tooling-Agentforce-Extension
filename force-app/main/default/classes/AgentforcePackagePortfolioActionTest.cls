@isTest
private with sharing class AgentforcePackagePortfolioActionTest {
  @isTest
  static void summarizesPortfolioWithDeterministicAttentionRanking() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService stub = AgentforcePackageIntelligenceTestSupport.readyStub();

    Test.startTest();
    AgentforcePackagePortfolioAction.Response response = AgentforcePackagePortfolioAction.summarize(
      new List<AgentforcePackagePortfolioAction.Request>{
        new AgentforcePackagePortfolioAction.Request()
      }
    )[0];
    Test.stopTest();

    Map<String, Object> payload = AgentforcePackageIntelligenceTestSupport.jsonMap(
      response.portfolioJson
    );
    List<Object> attention = (List<Object>) payload.get(
      'packagesNeedingAttention'
    );
    Map<String, Object> first = (Map<String, Object>) attention[0];

    Assert.areEqual('READY', response.state, 'Portfolio should be ready');
    Assert.areEqual(2, response.totalPackageCount, 'All packages are counted');
    Assert.areEqual(1, response.managedPackageCount, 'Managed is classified');
    Assert.areEqual(1, response.unlockedPackageCount, 'Unlocked is classified');
    Assert.areEqual(
      AgentforcePackageIntelligenceTestSupport.PACKAGE_ID,
      first.get('package2Id'),
      'A recent failed build ranks first'
    );
    Assert.isTrue(
      response.portfolioJson.length() < 60000,
      'Agent evidence is bounded'
    );
  }

  @isTest
  static void distinguishesAttentionPresentationLimitFromScanCompleteness() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService stub = AgentforcePackageIntelligenceTestSupport.readyStub();
    for (Integer indexValue = 3; indexValue <= 26; indexValue++) {
      String sequence = String.valueOf(indexValue).leftPad(12, '0');
      stub.packages.add(
        AgentforcePackageIntelligenceTestSupport.packageRecord(
          '0Ho' + sequence + 'AAA',
          '033' + sequence + 'AAA',
          'Package ' + indexValue,
          'Managed'
        )
      );
    }
    stub.packageTotal = stub.packages.size();

    Test.startTest();
    AgentforcePackagePortfolioAction.Response response = AgentforcePackagePortfolioAction.summarize(
      new List<AgentforcePackagePortfolioAction.Request>{
        new AgentforcePackagePortfolioAction.Request()
      }
    )[0];
    Test.stopTest();

    Map<String, Object> payload = AgentforcePackageIntelligenceTestSupport.jsonMap(
      response.portfolioJson
    );
    List<Object> attention = (List<Object>) payload.get(
      'packagesNeedingAttention'
    );

    Assert.areEqual(
      25,
      payload.get('attentionPackageDisplayLimit'),
      'The response contract declares its attention-item display limit'
    );
    Assert.areEqual(
      attention.size(),
      payload.get('attentionPackageIncludedCount'),
      'The included attention count matches the serialized evidence'
    );
    Assert.areEqual(
      true,
      payload.get('attentionPackagePresentationLimited'),
      'Additional attention items are identified as a presentation limit'
    );
    Assert.areEqual(
      1,
      payload.get('attentionPackageOmittedCount'),
      'The omitted presentation count is explicit'
    );
    Assert.areEqual(
      false,
      response.incomplete,
      'A presentation limit does not make an authoritative scan incomplete'
    );
  }

  @isTest
  static void enforcesExactVersionAndBuildScanCaps() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService stub = AgentforcePackageIntelligenceTestSupport.readyStub();
    stub.versions.clear();
    stub.builds.clear();
    for (Integer indexValue = 0; indexValue < 2001; indexValue++) {
      stub.versions.add(
        AgentforcePackageIntelligenceTestSupport.versionRecord(
          '05i' + String.valueOf(indexValue).leftPad(12, '0') + 'AAA',
          AgentforcePackageIntelligenceTestSupport.PACKAGE_ID,
          '04t' + String.valueOf(indexValue).leftPad(12, '0') + 'AAA',
          Math.mod(indexValue, 2) == 0,
          System.now().addDays(-indexValue)
        )
      );
      stub.builds.add(
        AgentforcePackageIntelligenceTestSupport.buildRecord(
          '08c' + String.valueOf(indexValue).leftPad(12, '0') + 'AAA',
          AgentforcePackageIntelligenceTestSupport.PACKAGE_ID,
          Math.mod(indexValue, 3) == 0 ? 'Error' : 'Success',
          System.now().addMinutes(-indexValue)
        )
      );
    }
    stub.versionTotal = 2001;
    stub.buildTotal = 2001;

    Test.startTest();
    AgentforcePackagePortfolioAction.Response response = AgentforcePackagePortfolioAction.summarize(
      new List<AgentforcePackagePortfolioAction.Request>{
        new AgentforcePackagePortfolioAction.Request()
      }
    )[0];
    Test.stopTest();

    Map<String, Object> payload = AgentforcePackageIntelligenceTestSupport.jsonMap(
      response.portfolioJson
    );
    Assert.areEqual(2000, stub.requestedVersionLimit, 'Version scan is capped');
    Assert.areEqual(2000, stub.requestedBuildLimit, 'Build scan is capped');
    Assert.areEqual(true, response.versionsTruncated, 'Overflow is reported');
    Assert.areEqual(
      true,
      response.createRequestsTruncated,
      'Build overflow is reported'
    );
    Assert.areEqual(
      true,
      response.incomplete,
      'Capped portfolio is incomplete'
    );
    Assert.areEqual(
      1,
      ((Map<String, Object>) payload.get('versionScan')).get('omittedCount'),
      'Version omissions are explicit'
    );
    Assert.areEqual(
      1,
      ((Map<String, Object>) payload.get('createRequestScan'))
        .get('omittedCount'),
      'Build omissions are explicit'
    );
  }

  @isTest
  static void resolvesPackageByIdsNameAndPersistedContext() {
    AgentforcePackageIntelligenceTestSupport.readyStub();
    List<AgentforcePackageDetailAction.Request> requests = new List<AgentforcePackageDetailAction.Request>{
      detailRequest(
        'Explain ' + AgentforcePackageIntelligenceTestSupport.PACKAGE_ID,
        null
      ),
      detailRequest(
        'Explain ' +
        AgentforcePackageIntelligenceTestSupport.SECOND_SUBSCRIBER_PACKAGE_ID,
        null
      ),
      detailRequest('Tell me about Managed Package', null),
      detailRequest(
        'What are its risks?',
        AgentforcePackageIntelligenceTestSupport.PACKAGE_ID
      )
    };

    Test.startTest();
    List<AgentforcePackageDetailAction.Response> responses = AgentforcePackageDetailAction.explain(
      requests
    );
    Test.stopTest();

    Assert.areEqual(4, responses.size(), 'Bulk order is retained');
    Assert.areEqual(
      AgentforcePackageIntelligenceTestSupport.PACKAGE_ID,
      responses[0].package2Id,
      '0Ho resolves'
    );
    Assert.areEqual(
      AgentforcePackageIntelligenceTestSupport.SECOND_PACKAGE_ID,
      responses[1].package2Id,
      '033 resolves'
    );
    Assert.areEqual(
      AgentforcePackageIntelligenceTestSupport.PACKAGE_ID,
      responses[2].package2Id,
      'Unique exact name resolves'
    );
    Assert.isFalse(
      responses[3].clearPreviousContext,
      'A same-package follow-up retains context'
    );
  }

  @isTest
  static void rejectsAmbiguousUnknownAndMalformedReplacementsWithoutFallback() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService stub = AgentforcePackageIntelligenceTestSupport.readyStub();
    stub.packages.add(
      AgentforcePackageIntelligenceTestSupport.packageRecord(
        '0Ho000000000003AAA',
        '033000000000003AAA',
        'Managed   Package',
        'Managed'
      )
    );

    Test.startTest();
    List<AgentforcePackageDetailAction.Response> responses = AgentforcePackageDetailAction.explain(
      new List<AgentforcePackageDetailAction.Request>{
        detailRequest('Managed Package', null),
        detailRequest(
          'Explain Unknown Package',
          AgentforcePackageIntelligenceTestSupport.PACKAGE_ID
        ),
        detailRequest(
          'Explain 04t000000000099AAA',
          AgentforcePackageIntelligenceTestSupport.PACKAGE_ID
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(
      'AMBIGUOUS',
      responses[0].state,
      'Duplicate names are safe'
    );
    Assert.isTrue(
      responses[0].message.contains('0Ho000000000003AAA'),
      'Candidates include IDs'
    );
    Assert.areEqual('NOT_FOUND', responses[1].state, 'Unknown names are clear');
    Assert.isTrue(
      responses[1].clearPreviousContext,
      'Stale package is cleared'
    );
    Assert.areEqual(
      'INVALID_ID',
      responses[2].state,
      'Wrong prefix is invalid'
    );
    Assert.isNull(
      responses[2].packageDetailJson,
      'No stale evidence is returned'
    );
  }

  @isTest
  static void enforcesCorePermissionAndSafeFailures() {
    AgentforcePackageIntelligenceTestSupport.readyStub();
    AgentforcePackageIntelligenceService.corePermissionOverride = false;
    AgentforcePackagePortfolioAction.Response forbidden = summarize();

    AgentforcePackageIntelligenceTestSupport.StubQueryService unavailable = AgentforcePackageIntelligenceTestSupport.readyStub();
    unavailable.toolingAvailable = false;
    AgentforcePackagePortfolioAction.Response unavailableResponse = summarize();

    AgentforcePackageIntelligenceTestSupport.StubQueryService failing = AgentforcePackageIntelligenceTestSupport.readyStub();
    failing.shouldThrow = true;
    AgentforcePackagePortfolioAction.Response errorResponse = summarize();

    Assert.areEqual(
      'FORBIDDEN',
      forbidden.state,
      'Core permission is enforced'
    );
    Assert.areEqual(
      'UNAVAILABLE',
      unavailableResponse.state,
      'Tooling absence is safe'
    );
    Assert.areEqual('ERROR', errorResponse.state, 'Queries fail safely');
    Assert.isFalse(
      errorResponse.message.contains('raw query failure'),
      'Raw exceptions never escape'
    );
  }

  @isTest
  static void includesPushAggregatesOnlyWithPushUpgradePermission() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService enabled = AgentforcePackageIntelligenceTestSupport.readyStub();
    enabled.pushAggregates.add(
      AgentforcePackageIntelligenceTestSupport.pushAggregate(
        AgentforcePackageIntelligenceTestSupport.VERSION_ID,
        2,
        12,
        3
      )
    );

    AgentforcePushDiagnosticsService.permissionOverride = true;
    AgentforcePackagePortfolioAction.Response enabledResponse = summarize();
    Map<String, Object> enabledPayload = AgentforcePackageIntelligenceTestSupport.jsonMap(
      enabledResponse.portfolioJson
    );

    AgentforcePackageIntelligenceTestSupport.StubQueryService disabled = AgentforcePackageIntelligenceTestSupport.readyStub();
    disabled.pushAggregates.addAll(enabled.pushAggregates);
    AgentforcePushDiagnosticsService.permissionOverride = false;
    AgentforcePackagePortfolioAction.Response disabledResponse = summarize();
    Map<String, Object> disabledPayload = AgentforcePackageIntelligenceTestSupport.jsonMap(
      disabledResponse.portfolioJson
    );

    Assert.areEqual(
      true,
      enabledPayload.get('pushEnrichmentIncluded'),
      'Push aggregates are included for authorized users'
    );
    Assert.areEqual(
      12,
      ((Map<String, Object>) enabledPayload.get('pushOutcomeTotals'))
        .get('jobCount'),
      'Portfolio includes aggregate job outcomes'
    );
    Assert.areEqual(
      false,
      disabledPayload.get('pushEnrichmentIncluded'),
      'Core-only users receive no push enrichment'
    );
    Assert.isFalse(
      disabled.pushAggregatesRequested,
      'Push data is never queried without the push permission'
    );
  }

  @isTest
  static void keepsPortfolioReadyWhenOptionalPushEnrichmentFails() {
    AgentforcePackageIntelligenceTestSupport.StubQueryService stub = AgentforcePackageIntelligenceTestSupport.readyStub();
    stub.throwPushQuery = true;
    AgentforcePushDiagnosticsService.permissionOverride = true;

    AgentforcePackagePortfolioAction.Response response = summarize();
    Map<String, Object> payload = AgentforcePackageIntelligenceTestSupport.jsonMap(
      response.portfolioJson
    );

    Assert.areEqual('READY', response.state, 'Optional enrichment is nonfatal');
    Assert.areEqual(
      false,
      payload.get('pushEnrichmentIncluded'),
      'Failed optional enrichment is not represented as authoritative'
    );
    Assert.isTrue(
      JSON.serialize(payload.get('warnings'))
        .contains('Push-outcome enrichment is unavailable.'),
      'The bounded payload reports the enrichment warning'
    );
  }

  private static AgentforcePackagePortfolioAction.Response summarize() {
    return AgentforcePackagePortfolioAction.summarize(
      new List<AgentforcePackagePortfolioAction.Request>{
        new AgentforcePackagePortfolioAction.Request()
      }
    )[0];
  }

  private static AgentforcePackageDetailAction.Request detailRequest(
    String userInput,
    String currentPackageId
  ) {
    AgentforcePackageDetailAction.Request value = new AgentforcePackageDetailAction.Request();
    value.userInput = userInput;
    value.currentPackageId = currentPackageId;
    return value;
  }
}
