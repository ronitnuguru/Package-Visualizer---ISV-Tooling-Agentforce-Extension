global with sharing class AgentforcePushRequestAnalysisAction {
  @InvocableMethod(
    label='Analyze Push Request Context'
    description='Returns authoritative job outcomes and failure patterns for a direct 0DV PackagePushRequest.'
    category='Package Visualizer'
  )
  global static List<Response> analyze(List<Request> requests) {
    if (requests == null) {
      return new List<Response>();
    }
    List<AgentforcePushRequestAnalysisService.Input> inputs = new List<AgentforcePushRequestAnalysisService.Input>();
    for (Request requestValue : requests) {
      AgentforcePushRequestAnalysisService.Input inputValue = new AgentforcePushRequestAnalysisService.Input();
      inputValue.userInput = requestValue?.userInput;
      inputValue.currentPushRequestId = requestValue?.currentPushRequestId;
      inputs.add(inputValue);
    }
    List<Response> responses = new List<Response>();
    for (
      AgentforcePushRequestAnalysisService.Result resultValue : AgentforcePushRequestAnalysisService.analyze(
        inputs
      )
    ) {
      Response responseValue = new Response();
      responseValue.state = resultValue.state;
      responseValue.message = resultValue.message;
      responseValue.clearPreviousContext =
        resultValue.clearPreviousContext == true;
      responseValue.pushRequestId = resultValue.pushRequestId;
      responseValue.targetPackageVersionId = resultValue.targetPackageVersionId;
      responseValue.analysisJson = resultValue.analysisJson;
      responses.add(responseValue);
    }
    return responses;
  }

  global class Request {
    @InvocableVariable(label='Latest User Input' required=true)
    global String userInput;
    @InvocableVariable(label='Current Push Request ID' required=false)
    global String currentPushRequestId;
  }

  global class Response {
    @InvocableVariable(label='State')
    global String state;
    @InvocableVariable(label='Message')
    global String message;
    @InvocableVariable(label='Clear Previous Context')
    global Boolean clearPreviousContext;
    @InvocableVariable(label='Push Request ID')
    global String pushRequestId;
    @InvocableVariable(label='Target Package Version ID')
    global String targetPackageVersionId;
    @InvocableVariable(label='Analysis JSON')
    global String analysisJson;
  }
}
