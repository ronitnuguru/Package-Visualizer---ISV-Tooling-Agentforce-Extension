/** Global read-only entry point for headless push operations. */
global with sharing class HeadlessPreviewPushAction {
  /** Processes one operator intent; multi-operation calls fail without side effects. */
  @InvocableMethod(
    label='Preview Push Upgrade'
    description='Read-only eligibility preview. No request, File, or job is created. Pass the selection fingerprint to preparation; native approval remains required for dispatch.'
    category='Package Visualizer Push'
    callout=true
  )
  global static List<HeadlessPushResponse> run(
    List<HeadlessPlanPushAction.Request> requests
  ) {
    List<HeadlessPushResponse> responses = new List<HeadlessPushResponse>();
    if (requests == null || requests.isEmpty()) {
      return responses;
    }
    if (requests.size() != 1 || requests[0] == null) {
      for (HeadlessPlanPushAction.Request ignored : requests) {
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
      HeadlessPushService.response(HeadlessPushService.preview(requests[0]))
    );
    return responses;
  }
}
