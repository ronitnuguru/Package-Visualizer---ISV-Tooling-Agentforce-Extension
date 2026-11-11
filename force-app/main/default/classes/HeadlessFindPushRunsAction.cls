/** Global read-only entry point for headless push operations. */
global with sharing class HeadlessFindPushRunsAction {
  /** Processes one operator intent; multi-operation calls fail without side effects. */
  @InvocableMethod(
    label='Find My Push Upgrades'
    description='Find the current Salesforce operator\'s manifest-backed runs, then select one manifestVersionId to resume it. Never dispatches.'
    category='Package Visualizer Push'
    callout=true
  )
  global static List<HeadlessPushResponse> run(List<Request> requests) {
    List<HeadlessPushResponse> responses = new List<HeadlessPushResponse>();
    if (requests == null || requests.isEmpty()) {
      return responses;
    }
    if (requests.size() != 1 || requests[0] == null) {
      for (Request ignored : requests) {
        responses.add(
          HeadlessPushService.response(
            HeadlessPushService.failure(
              'INVALID_INPUT',
              'Invoke one operation at a time.'
            )
          )
        );
      }
      return responses;
    }
    responses.add(
      HeadlessPushService.response(HeadlessPushService.find(requests[0]))
    );
    return responses;
  }
  global class Request {
    @InvocableVariable(label='requestId' required=false)
    global String requestId;
    @InvocableVariable(label='targetVersionId' required=false)
    global String targetVersionId;
    @InvocableVariable(label='manifestVersionId' required=false)
    global String manifestVersionId;
    @InvocableVariable(label='Page before ID' required=false) global String beforeId;
    @InvocableVariable(label='Page before date' required=false)
    global Datetime beforeDate;
  }
}
