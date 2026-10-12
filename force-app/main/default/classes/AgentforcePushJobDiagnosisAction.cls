/**
 * Agentforce invocable action that refreshes and verifies authoritative
 * PackagePushJob diagnostic context.
 */
global with sharing class AgentforcePushJobDiagnosisAction {
  /**
   * Diagnoses failed push jobs without performing writes.
   *
   * @param requests Latest utterance and optional persisted job context.
   * @return One diagnostic response per request.
   */
  @InvocableMethod(
    label='Get Push Job Diagnostic Context'
    description='Refreshes and normalizes authoritative evidence for a failed PackagePushJob.'
    category='Package Visualizer'
  )
  global static List<Response> diagnose(List<Request> requests) {
    List<AgentforcePushDiagnosticsService.DiagnosisInput> serviceInputs = new List<AgentforcePushDiagnosticsService.DiagnosisInput>();
    if (requests == null) {
      return new List<Response>();
    }
    for (Request requestValue : requests) {
      AgentforcePushDiagnosticsService.DiagnosisInput inputValue = new AgentforcePushDiagnosticsService.DiagnosisInput();
      inputValue.userInput = requestValue?.userInput;
      inputValue.currentPushJobId = requestValue?.currentPushJobId;
      serviceInputs.add(inputValue);
    }

    List<Response> responses = new List<Response>();
    for (
      AgentforcePushDiagnosticsService.DiagnosisResult resultValue : AgentforcePushDiagnosticsService.diagnose(
        serviceInputs
      )
    ) {
      Response responseValue = new Response();
      responseValue.state = resultValue.state;
      responseValue.message = resultValue.message;
      responseValue.clearPreviousContext =
        resultValue.clearPreviousContext == true;
      responseValue.jobId = resultValue.jobId;
      responseValue.pushRequestId = resultValue.pushRequestId;
      responseValue.targetPackageVersionId = resultValue.targetPackageVersionId;
      responseValue.diagnosticJson = resultValue.diagnosticJson;
      responses.add(responseValue);
    }
    return responses;
  }

  /** Inputs provided by Agent Script. */
  global class Request {
    @InvocableVariable(
      label='Latest User Input'
      description='The latest utterance, which can contain a replacement 0DX PackagePushJob ID.'
      required=true
    )
    global String userInput;

    @InvocableVariable(
      label='Current Push Job ID'
      description='The persisted authoritative 0DX PackagePushJob ID used only when no replacement was attempted.'
      required=false
    )
    global String currentPushJobId;
  }

  /** Safe diagnostic state returned to Agent Script. */
  global class Response {
    @InvocableVariable(label='State' description='Diagnostic state.')
    global String state;

    @InvocableVariable(
      label='Message'
      description='Safe user-facing state message.'
    )
    global String message;

    @InvocableVariable(
      label='Clear Previous Context'
      description='Whether persisted diagnostic and comparison context must be cleared.'
    )
    global Boolean clearPreviousContext;

    @InvocableVariable(
      label='Push Job ID'
      description='Authoritative 0DX job ID.'
    )
    global String jobId;

    @InvocableVariable(
      label='Push Request ID'
      description='Authoritative owning 0DV push request ID.'
    )
    global String pushRequestId;

    @InvocableVariable(
      label='Target Package Version ID'
      description='Authoritative target 04t package version ID when available.'
    )
    global String targetPackageVersionId;

    @InvocableVariable(
      label='Diagnostic JSON'
      description='Bounded normalized authoritative diagnostic evidence.'
    )
    global String diagnosticJson;
  }
}
