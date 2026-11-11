/** Structured MCP result; native client confirmation remains required for dispatch. */
global with sharing class HeadlessPushResponse {
  @InvocableVariable(label='Selection fingerprint')
  global String selectionFingerprint;
  @InvocableVariable(label='Candidates or runs JSON')
  global String candidatesJson;
  @InvocableVariable(label='Readiness evidence JSON')
  global String readinessJson;
  @InvocableVariable(label='Evidence timestamp')
  global Datetime capturedAt;
  @InvocableVariable(label='Next run-page ID cursor') global String beforeId;
  @InvocableVariable(label='Next run-page date cursor')
  global Datetime beforeDate;
  @InvocableVariable(label='More results may exist')
  global Boolean hasMore;
  @InvocableVariable(label='Supplied entries')
  global Integer suppliedCount;
  @InvocableVariable(label='Duplicate entries')
  global Integer duplicateCount;
  @InvocableVariable(label='Invalid entries')
  global Integer invalidCount;
  @InvocableVariable(label='Excluded orgs')
  global Integer excludedCount;
  @InvocableVariable(label='Target package version ID')
  global String targetVersionId;
  @InvocableVariable(label='Reviewed UTC scheduled start')
  global Datetime scheduledStartTime;
  @InvocableVariable(label='Dispatch as soon as resources are available')
  global Boolean immediate;
  @InvocableVariable(label='isSuccess')
  global Boolean isSuccess;
  @InvocableVariable(label='errorType')
  global String errorType;
  @InvocableVariable(label='errorMessage')
  global String errorMessage;
  @InvocableVariable(label='state')
  global String state;
  @InvocableVariable(label='requestId')
  global String requestId;
  @InvocableVariable(label='manifestVersionId')
  global String manifestVersionId;
  @InvocableVariable(label='csvVersionId')
  global String csvVersionId;
  @InvocableVariable(label='Submission report links')
  global String reportsJson;
  @InvocableVariable(label='CSV download URL')
  global String csvDownloadUrl;
  @InvocableVariable(label='digest')
  global String digest;
  @InvocableVariable(label='excludedJson')
  global String excludedJson;
  @InvocableVariable(label='detailsJson')
  global String detailsJson;
  @InvocableVariable(label='nextOffset')
  global Integer nextOffset;
  @InvocableVariable(label='expectedCount')
  global Integer expectedCount;
  @InvocableVariable(label='stagedCount')
  global Integer stagedCount;
  @InvocableVariable(label='succeededCount')
  global Integer succeededCount;
  @InvocableVariable(label='failedCount')
  global Integer failedCount;
  @InvocableVariable(label='pendingCount')
  global Integer pendingCount;
}
