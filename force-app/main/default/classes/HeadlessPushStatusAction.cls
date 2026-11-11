/** Packaged invocable entry point for the headless push workflow. */
global with sharing class HeadlessPushStatusAction {
  /** Executes one campaign operation; bulk invocation is rejected without writes. */
  @InvocableMethod(
    label='Get Prepared Push Upgrade Status'
    description='Returns preparation readiness and authoritative upgrade results for the saved snapshot.'
    category='Package Visualizer Push'
    callout=true
  )
  global static List<HeadlessPushResponse> run(List<Request> requests) {
    List<HeadlessPushResponse> responses = new List<HeadlessPushResponse>();
    if (requests == null || requests.isEmpty()) {
      return responses;
    }
    if (requests.size() != 1 || requests[0] == null) {
      for (Request item : requests) {
        responses.add(
          HeadlessPushService.response(
            HeadlessPushService.failure(
              'INVALID_INPUT',
              'Invoke one prepared upgrade operation at a time.'
            )
          )
        );
      }
      return responses;
    }
    responses.add(
      HeadlessPushService.response(
        HeadlessPushService.inspect(
          requests[0].manifestVersionId,
          requests[0].digest,
          requests[0].offset
        )
      )
    );
    return responses;
  }
  global class Request {
    @InvocableVariable(label='Detail offset' required=false)
    global Integer offset;
    @InvocableVariable(label='manifestVersionId' required=true)
    global String manifestVersionId;
    @InvocableVariable(label='digest' required=true)
    global String digest;
  }
}
