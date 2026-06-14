import { LightningElement, api } from 'lwc';

export default class AgentFleetAnalyticsCard extends LightningElement {
    @api value;

    get analytics() {
        return this.value || {};
    }

    get hasError() {
        return !!this.analytics.errorMessage;
    }

    get hasBuckets() {
        return this.analytics.buckets && this.analytics.buckets.length > 0;
    }

    // Decorate each bucket row with a display string so the template stays declarative.
    get bucketRows() {
        return (this.analytics.buckets || []).map((bucket) => ({
            ...bucket,
            display: `${bucket.label}: ${bucket.count} (${bucket.percentOfSegments}%)`
        }));
    }
}
