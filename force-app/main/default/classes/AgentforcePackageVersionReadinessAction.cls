global with sharing class AgentforcePackageVersionReadinessAction {
  @InvocableMethod(
    label='Get Package Version Readiness'
    description='Returns authoritative release, coverage, dependency, subscriber-impact, and blocker context for a 04t package version.'
    category='Package Visualizer'
    callout=true
  )
  global static List<Response> assess(List<Request> requests) {
    if (requests == null) {
      return new List<Response>();
    }
    List<AgentforcePackageCoreContextService.ContextInput> inputs = new List<AgentforcePackageCoreContextService.ContextInput>();
    for (Request requestValue : requests) {
      AgentforcePackageCoreContextService.ContextInput inputValue = new AgentforcePackageCoreContextService.ContextInput();
      inputValue.userInput = requestValue?.userInput;
      inputValue.currentId = requestValue?.currentPackageVersionId;
      inputs.add(inputValue);
    }
    List<Response> responses = new List<Response>();
    for (
      AgentforcePackageCoreContextService.VersionResult resultValue : AgentforcePackageCoreContextService.assessVersions(
        inputs
      )
    ) {
      Response responseValue = new Response();
      responseValue.state = resultValue.state;
      responseValue.message = resultValue.message;
      responseValue.clearPreviousContext =
        resultValue.clearPreviousContext == true;
      responseValue.subscriberPackageVersionId = resultValue.subscriberPackageVersionId;
      responseValue.package2Id = resultValue.package2Id;
      responseValue.readinessJson = resultValue.readinessJson;
      responses.add(responseValue);
    }
    return responses;
  }

  global class Request {
    @InvocableVariable(label='Latest User Input' required=true)
    global String userInput;
    @InvocableVariable(label='Current Package Version ID' required=false)
    global String currentPackageVersionId;
  }

  global class Response {
    @InvocableVariable(label='State')
    global String state;
    @InvocableVariable(label='Message')
    global String message;
    @InvocableVariable(label='Clear Previous Context')
    global Boolean clearPreviousContext;
    @InvocableVariable(label='SubscriberPackageVersion ID')
    global String subscriberPackageVersionId;
    @InvocableVariable(label='Package2 ID')
    global String package2Id;
    @InvocableVariable(label='Readiness JSON')
    global String readinessJson;
  }
}
