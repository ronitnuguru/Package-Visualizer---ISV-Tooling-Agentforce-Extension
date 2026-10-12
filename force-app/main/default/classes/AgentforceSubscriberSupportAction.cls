global with sharing class AgentforceSubscriberSupportAction {
  @InvocableMethod(
    label='Get Subscriber Support Context'
    description='Returns read-only PackageSubscriber installation, upgrade, sandbox, and support context.'
    category='Package Visualizer'
  )
  global static List<Response> review(List<Request> requests) {
    if (requests == null) {
      return new List<Response>();
    }
    List<AgentforcePackageCoreContextService.ContextInput> inputs = new List<AgentforcePackageCoreContextService.ContextInput>();
    for (Request requestValue : requests) {
      AgentforcePackageCoreContextService.ContextInput inputValue = new AgentforcePackageCoreContextService.ContextInput();
      inputValue.userInput = requestValue?.userInput;
      inputValue.currentId = requestValue?.currentPackageSubscriberId;
      inputs.add(inputValue);
    }
    List<Response> responses = new List<Response>();
    for (
      AgentforcePackageCoreContextService.SubscriberResult resultValue : AgentforcePackageCoreContextService.reviewSubscribers(
        inputs
      )
    ) {
      Response responseValue = new Response();
      responseValue.state = resultValue.state;
      responseValue.message = resultValue.message;
      responseValue.clearPreviousContext =
        resultValue.clearPreviousContext == true;
      responseValue.packageSubscriberId = resultValue.packageSubscriberId;
      responseValue.subscriberPackageId = resultValue.subscriberPackageId;
      responseValue.subscriberPackageVersionId = resultValue.subscriberPackageVersionId;
      responseValue.subscriberJson = resultValue.subscriberJson;
      responses.add(responseValue);
    }
    return responses;
  }

  global class Request {
    @InvocableVariable(label='Latest User Input' required=true)
    global String userInput;
    @InvocableVariable(label='Current PackageSubscriber ID' required=false)
    global String currentPackageSubscriberId;
  }

  global class Response {
    @InvocableVariable(label='State')
    global String state;
    @InvocableVariable(label='Message')
    global String message;
    @InvocableVariable(label='Clear Previous Context')
    global Boolean clearPreviousContext;
    @InvocableVariable(label='PackageSubscriber ID')
    global String packageSubscriberId;
    @InvocableVariable(label='SubscriberPackage ID')
    global String subscriberPackageId;
    @InvocableVariable(label='SubscriberPackageVersion ID')
    global String subscriberPackageVersionId;
    @InvocableVariable(label='Subscriber JSON')
    global String subscriberJson;
  }
}
