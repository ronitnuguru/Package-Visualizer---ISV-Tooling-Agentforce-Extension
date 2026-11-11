/** Packaged invocable entry point for the headless push workflow. */
global with sharing class HeadlessPlanPushAction {
  /** Executes one campaign operation; bulk invocation is rejected without writes. */
  @InvocableMethod(
    label='Prepare Bulk Push Upgrade'
    description='Creates an undispatched request and CSV for up to 2000 eligible orgs. Never upgrades an org. Native write confirmation may apply.'
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
      HeadlessPushService.response(HeadlessPushService.prepare(requests[0]))
    );
    return responses;
  }
  global class Request {
    @InvocableVariable(label='targetVersionId' required=true)
    global String targetVersionId;
    @InvocableVariable(label='Reviewed selection fingerprint' required=false)
    global String selectionFingerprint;
    @InvocableVariable(label='Recovery source manifest version' required=false)
    global String recoveryManifestVersionId;
    @InvocableVariable(label='Recovery source digest' required=false)
    global String recoveryDigest;
    @InvocableVariable(label='orgIdsText' required=false)
    global String orgIdsText;
    @InvocableVariable(label='sourceFileVersionId' required=false)
    global String sourceFileVersionId;
    @InvocableVariable(label='installedVersionIds' required=false)
    global List<String> installedVersionIds;
    @InvocableVariable(label='orgTypes' required=false)
    global List<String> orgTypes;
    @InvocableVariable(label='orgStatuses' required=false)
    global List<String> orgStatuses;
    @InvocableVariable(label='instances' required=false)
    global List<String> instances;
    @InvocableVariable(label='excludeOrgIds' required=false)
    global List<String> excludeOrgIds;
    @InvocableVariable(label='scheduledStartTime' required=false)
    global Datetime scheduledStartTime;
  }
}
