import { LightningElement, api } from 'lwc';

export default class AgentPushOpsCard extends LightningElement {
    @api value;

    get data() {
        return this.value || {};
    }

    get hasError() {
        return !!this.data.errorMessage;
    }

    // The same card renders a PushPlan (has eligibleCount) or a PushMonitor (has totalJobs).
    get isPlan() {
        return this.data.eligibleCount !== undefined && this.data.eligibleCount !== null;
    }

    get isMonitor() {
        return this.data.totalJobs !== undefined && this.data.totalJobs !== null;
    }

    get hasFailures() {
        return this.data.topFailures && this.data.topFailures.length > 0;
    }

    get failureRows() {
        return (this.data.topFailures || []).map((failure) => ({
            ...failure,
            display: `${failure.errorTitle} (${failure.errorType}) ×${failure.occurrenceCount}`
        }));
    }
}
