/**
 * Channel-agnostic DTOs for the reimagined push-upgrade operations (plan / execute / monitor).
 * The write flow is split: AgentPushOpsPlan returns a PushPlan (dry run, no writes); the user
 * confirms; AgentPushOpsExecute consumes the explicit targetOrgKeys + confirmed flag.
 */
@JsonAccess(serializable='always' deserializable='always')
global class AgentPushWrappers {

    @JsonAccess(serializable='always' deserializable='always')
    global class PushPlan {
        @InvocableVariable
        global String targetVersionId; // 04t
        @InvocableVariable
        global String targetVersionNumber;
        @InvocableVariable
        global Boolean targetIsSecurityReviewed;
        @InvocableVariable
        global List<String> eligibleOrgKeys; // capped sample/cohort the user can confirm
        @InvocableVariable
        global Integer eligibleCount;
        @InvocableVariable
        global Integer alreadyCurrentCount;
        @InvocableVariable
        global Integer estimatedChunks; // ceil(eligibleCount / 200)
        @InvocableVariable
        global Boolean blocked; // true when the target cannot be pushed (e.g. not security reviewed)
        @InvocableVariable
        global String summaryLine;
        @InvocableVariable
        global String errorMessage;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class PushScheduleResult {
        @InvocableVariable
        global Boolean success;
        @InvocableVariable
        global String pushRequestId;
        @InvocableVariable
        global String targetVersionId;
        @InvocableVariable
        global String targetVersionNumber;
        @InvocableVariable
        global Integer jobsRequested;
        @InvocableVariable
        global String errorMessage;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class PushMonitor {
        @InvocableVariable
        global String pushRequestId;
        @InvocableVariable
        global String status;
        @InvocableVariable
        global String targetVersionNumber;
        @InvocableVariable
        global Integer totalJobs;
        @InvocableVariable
        global Integer succeededJobs;
        @InvocableVariable
        global Integer failedJobs;
        @InvocableVariable
        global Integer pendingJobs;
        @InvocableVariable
        global List<JobFailure> topFailures;
        @InvocableVariable
        global String rootCauseSummary;
        @InvocableVariable
        global String errorMessage;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class JobFailure {
        @InvocableVariable
        global String subscriberOrgKey;
        @InvocableVariable
        global String errorType;
        @InvocableVariable
        global String errorTitle;
        @InvocableVariable
        global String errorMessage;
        @InvocableVariable
        global String errorSeverity;
        @InvocableVariable
        global Integer occurrenceCount;
    }
}
