/**
 * Agentforce invocable action that compares failure patterns across the
 * authoritative push request derived from the active diagnosis.
 */
global with sharing class AgentforcePushRequestComparisonAction {
  /**
   * Compares sibling push failures without performing writes.
   *
   * @param requests Persisted authoritative job context.
   * @return One comparison response per request.
   */
  @InvocableMethod(
    label='Compare Push Request Failures'
    description='Derives the owning PackagePushRequest from an active PackagePushJob and compares exact and normalized sibling failure patterns.'
    category='Package Visualizer'
  )
  global static List<Response> compare(List<Request> requests) {
    List<AgentforcePushComparisonService.ComparisonInput> serviceInputs = new List<AgentforcePushComparisonService.ComparisonInput>();
    if (requests == null) {
      return new List<Response>();
    }
    for (Request requestValue : requests) {
      AgentforcePushComparisonService.ComparisonInput inputValue = new AgentforcePushComparisonService.ComparisonInput();
      inputValue.selectedPushJobId = requestValue?.selectedPushJobId;
      serviceInputs.add(inputValue);
    }

    List<Response> responses = new List<Response>();
    for (
      AgentforcePushComparisonService.ComparisonResult resultValue : AgentforcePushComparisonService.compare(
        serviceInputs
      )
    ) {
      Response responseValue = new Response();
      responseValue.state = resultValue.state;
      responseValue.message = resultValue.message;
      responseValue.pushRequestId = resultValue.pushRequestId;
      responseValue.comparisonJson = resultValue.comparisonJson;
      responses.add(responseValue);
    }
    return responses;
  }

  /** Input sourced only from authoritative persisted Agent Script variables. */
  global class Request {
    @InvocableVariable(
      label='Legacy Push Request ID'
      description='Deprecated compatibility input. Ignored; Apex derives the authoritative 0DV from the selected 0DX.'
      required=false
    )
    global String pushRequestId;

    @InvocableVariable(
      label='Selected Push Job ID'
      description='Stored authoritative active 0DX PackagePushJob ID. Apex derives its owning 0DV request.'
      required=false
    )
    global String selectedPushJobId;
  }

  /** Safe sibling comparison state returned to Agent Script. */
  global class Response {
    @InvocableVariable(label='State' description='Comparison state.')
    global String state;

    @InvocableVariable(
      label='Message'
      description='Safe user-facing state message.'
    )
    global String message;

    @InvocableVariable(
      label='Push Request ID'
      description='Authoritative 0DV push request ID.'
    )
    global String pushRequestId;

    @InvocableVariable(
      label='Comparison JSON'
      description='Bounded normalized sibling failure comparison evidence.'
    )
    global String comparisonJson;
  }
}
