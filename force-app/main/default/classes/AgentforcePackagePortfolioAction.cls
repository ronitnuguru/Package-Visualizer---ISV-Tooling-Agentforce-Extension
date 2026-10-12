global with sharing class AgentforcePackagePortfolioAction {
  @InvocableMethod(
    label='Get Package Portfolio Context'
    description='Returns authoritative, bounded health context for active 2GP managed and unlocked packages.'
    category='Package Visualizer'
    callout=true
  )
  global static List<Response> summarize(List<Request> requests) {
    if (requests == null) {
      return new List<Response>();
    }
    List<Response> responses = new List<Response>();
    for (
      AgentforcePackageIntelligenceService.PortfolioResult resultValue : AgentforcePackageIntelligenceService.summarize(
        requests.size()
      )
    ) {
      Response responseValue = new Response();
      responseValue.state = resultValue.state;
      responseValue.message = resultValue.message;
      responseValue.totalPackageCount = resultValue.totalPackageCount;
      responseValue.managedPackageCount = resultValue.managedPackageCount;
      responseValue.unlockedPackageCount = resultValue.unlockedPackageCount;
      responseValue.releasedVersionCount = resultValue.releasedVersionCount;
      responseValue.unreleasedVersionCount = resultValue.unreleasedVersionCount;
      responseValue.versionlessPackageCount = resultValue.versionlessPackageCount;
      responseValue.recentFailedBuildCount = resultValue.recentFailedBuildCount;
      responseValue.versionsTruncated = resultValue.versionsTruncated;
      responseValue.createRequestsTruncated = resultValue.createRequestsTruncated;
      responseValue.incomplete = resultValue.incomplete;
      responseValue.portfolioJson = resultValue.portfolioJson;
      responses.add(responseValue);
    }
    return responses;
  }

  global class Request {
    @InvocableVariable(
      label='Latest User Input'
      description='The latest portfolio question.'
      required=false
    )
    global String userInput;
  }

  global class Response {
    @InvocableVariable(label='State')
    global String state;
    @InvocableVariable(label='Message')
    global String message;
    @InvocableVariable(label='Total Package Count')
    global Integer totalPackageCount;
    @InvocableVariable(label='Managed Package Count')
    global Integer managedPackageCount;
    @InvocableVariable(label='Unlocked Package Count')
    global Integer unlockedPackageCount;
    @InvocableVariable(label='Released Version Count')
    global Integer releasedVersionCount;
    @InvocableVariable(label='Unreleased Version Count')
    global Integer unreleasedVersionCount;
    @InvocableVariable(label='Versionless Package Count')
    global Integer versionlessPackageCount;
    @InvocableVariable(label='Recent Failed Build Count')
    global Integer recentFailedBuildCount;
    @InvocableVariable(label='Versions Truncated')
    global Boolean versionsTruncated;
    @InvocableVariable(label='Create Requests Truncated')
    global Boolean createRequestsTruncated;
    @InvocableVariable(label='Incomplete')
    global Boolean incomplete;
    @InvocableVariable(label='Portfolio JSON')
    global String portfolioJson;
  }
}
