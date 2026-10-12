global with sharing class AgentforcePackageDetailAction {
  @InvocableMethod(
    label='Get Package Detail Context'
    description='Resolves a package and returns bounded authoritative package, version, build, and subscriber context.'
    category='Package Visualizer'
    callout=true
  )
  global static List<Response> explain(List<Request> requests) {
    if (requests == null) {
      return new List<Response>();
    }
    List<AgentforcePackageIntelligenceService.PackageDetailInput> inputs = new List<AgentforcePackageIntelligenceService.PackageDetailInput>();
    for (Request requestValue : requests) {
      AgentforcePackageIntelligenceService.PackageDetailInput inputValue = new AgentforcePackageIntelligenceService.PackageDetailInput();
      inputValue.userInput = requestValue?.userInput;
      inputValue.currentPackageId = requestValue?.currentPackageId;
      inputs.add(inputValue);
    }
    List<Response> responses = new List<Response>();
    for (
      AgentforcePackageIntelligenceService.PackageDetailResult resultValue : AgentforcePackageIntelligenceService.explain(
        inputs
      )
    ) {
      Response responseValue = new Response();
      responseValue.state = resultValue.state;
      responseValue.message = resultValue.message;
      responseValue.clearPreviousContext =
        resultValue.clearPreviousContext == true;
      responseValue.package2Id = resultValue.package2Id;
      responseValue.subscriberPackageId = resultValue.subscriberPackageId;
      responseValue.packageDetailJson = resultValue.packageDetailJson;
      responses.add(responseValue);
    }
    return responses;
  }

  global class Request {
    @InvocableVariable(label='Latest User Input' required=true)
    global String userInput;
    @InvocableVariable(label='Current Package2 ID' required=false)
    global String currentPackageId;
  }

  global class Response {
    @InvocableVariable(label='State')
    global String state;
    @InvocableVariable(label='Message')
    global String message;
    @InvocableVariable(label='Clear Previous Context')
    global Boolean clearPreviousContext;
    @InvocableVariable(label='Package2 ID')
    global String package2Id;
    @InvocableVariable(label='SubscriberPackage ID')
    global String subscriberPackageId;
    @InvocableVariable(label='Package Detail JSON')
    global String packageDetailJson;
  }
}
