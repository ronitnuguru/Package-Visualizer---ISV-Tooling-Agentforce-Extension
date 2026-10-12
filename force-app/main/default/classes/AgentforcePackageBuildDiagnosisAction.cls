global with sharing class AgentforcePackageBuildDiagnosisAction {
  @InvocableMethod(
    label='Get Package Build Diagnostic Context'
    description='Refreshes authoritative error context for a failed 08c package-version create request.'
    category='Package Visualizer'
    callout=true
  )
  global static List<Response> diagnose(List<Request> requests) {
    if (requests == null) {
      return new List<Response>();
    }
    List<AgentforcePackageCoreContextService.ContextInput> inputs = new List<AgentforcePackageCoreContextService.ContextInput>();
    for (Request requestValue : requests) {
      AgentforcePackageCoreContextService.ContextInput inputValue = new AgentforcePackageCoreContextService.ContextInput();
      inputValue.userInput = requestValue?.userInput;
      inputValue.currentId = requestValue?.currentBuildRequestId;
      inputs.add(inputValue);
    }
    List<Response> responses = new List<Response>();
    for (
      AgentforcePackageCoreContextService.BuildResult resultValue : AgentforcePackageCoreContextService.diagnoseBuilds(
        inputs
      )
    ) {
      Response responseValue = new Response();
      responseValue.state = resultValue.state;
      responseValue.message = resultValue.message;
      responseValue.clearPreviousContext =
        resultValue.clearPreviousContext == true;
      responseValue.buildRequestId = resultValue.buildRequestId;
      responseValue.package2Id = resultValue.package2Id;
      responseValue.package2VersionId = resultValue.package2VersionId;
      responseValue.diagnosticJson = resultValue.diagnosticJson;
      responses.add(responseValue);
    }
    return responses;
  }

  global class Request {
    @InvocableVariable(label='Latest User Input' required=true)
    global String userInput;
    @InvocableVariable(label='Current Build Request ID' required=false)
    global String currentBuildRequestId;
  }

  global class Response {
    @InvocableVariable(label='State')
    global String state;
    @InvocableVariable(label='Message')
    global String message;
    @InvocableVariable(label='Clear Previous Context')
    global Boolean clearPreviousContext;
    @InvocableVariable(label='Build Request ID')
    global String buildRequestId;
    @InvocableVariable(label='Package2 ID')
    global String package2Id;
    @InvocableVariable(label='Package2Version ID')
    global String package2VersionId;
    @InvocableVariable(label='Diagnostic JSON')
    global String diagnosticJson;
  }
}
