global with sharing class AgentforcePackageBuildComparisonAction {
  @InvocableMethod(
    label='Compare Package Build Failures'
    description='Compares exact error signatures across recent failed build requests for the same Package2.'
    category='Package Visualizer'
    callout=true
  )
  global static List<Response> compare(List<Request> requests) {
    if (requests == null) {
      return new List<Response>();
    }
    List<String> buildIds = new List<String>();
    for (Request requestValue : requests) {
      buildIds.add(requestValue?.currentBuildRequestId);
    }
    List<Response> responses = new List<Response>();
    for (
      AgentforcePackageCoreContextService.BuildComparisonResult resultValue : AgentforcePackageCoreContextService.compareBuilds(
        buildIds
      )
    ) {
      Response responseValue = new Response();
      responseValue.state = resultValue.state;
      responseValue.message = resultValue.message;
      responseValue.buildRequestId = resultValue.buildRequestId;
      responseValue.package2Id = resultValue.package2Id;
      responseValue.comparisonJson = resultValue.comparisonJson;
      responses.add(responseValue);
    }
    return responses;
  }

  global class Request {
    @InvocableVariable(label='Current Build Request ID' required=true)
    global String currentBuildRequestId;
  }

  global class Response {
    @InvocableVariable(label='State')
    global String state;
    @InvocableVariable(label='Message')
    global String message;
    @InvocableVariable(label='Build Request ID')
    global String buildRequestId;
    @InvocableVariable(label='Package2 ID')
    global String package2Id;
    @InvocableVariable(label='Comparison JSON')
    global String comparisonJson;
  }
}
