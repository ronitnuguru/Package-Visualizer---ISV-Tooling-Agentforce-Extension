/** Packaged invocable entry point for the headless push workflow. */
global with sharing class HeadlessCancelPushAction {
  /** Executes one campaign operation; bulk invocation is rejected without writes. */
  @InvocableMethod(
    label='Cancel Prepared Push Upgrade'
    description='Cancels a Created or Pending push request after native client approval. Completed upgrades cannot be rolled back.'
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
        HeadlessPushService.cancel(
          requests[0].manifestVersionId,
          requests[0].digest
        )
      )
    );
    return responses;
  }
  global class Request {
    @InvocableVariable(label='manifestVersionId' required=true)
    global String manifestVersionId;
    @InvocableVariable(label='digest' required=true)
    global String digest;
  }
}
