/** Global read-only entry point for headless push operations. */
global with sharing class HeadlessResolvePushTargetAction {
  /** Processes one operator intent; multi-operation calls fail without side effects. */
  @InvocableMethod(
    label='Resolve Push Target'
    description='Resolve the latest released push target when requested, or an exact package version. Set latestReleased=true for latest; report blockers and never prepare or dispatch.'
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
      HeadlessPushService.response(HeadlessPushService.resolve(requests[0]))
    );
    return responses;
  }
  global class Request {
    @InvocableVariable(
      label='Latest released version'
      description='Set true when the user requests the latest released version for push upgrade. Do not infer scheduling approval.'
      required=false
    )
    global Boolean latestReleased;
    @InvocableVariable(
      label='Selected package ID'
      description='Use the selected 0Ho package ID when the exact package name matches multiple packages.'
      required=false
    )
    global String packageId;
    @InvocableVariable(label='packageName' required=false)
    global String packageName;
    @InvocableVariable(label='versionNumber' required=false)
    global String versionNumber;
    @InvocableVariable(label='targetVersionId' required=false)
    global String targetVersionId;
  }
}
