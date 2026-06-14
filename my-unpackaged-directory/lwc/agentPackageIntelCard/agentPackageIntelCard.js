import { LightningElement, api } from 'lwc';

export default class AgentPackageIntelCard extends LightningElement {
    @api value;

    get insight() {
        return this.value || {};
    }

    get hasError() {
        return !!this.insight.errorMessage;
    }

    get hasDependencies() {
        return this.insight.dependencies && this.insight.dependencies.length > 0;
    }

    // SLDS theme variant for the readiness badge.
    get readinessVariant() {
        switch (this.insight.promotionReadinessTag) {
            case 'ready':
                return 'success';
            case 'coverage-gap':
            case 'beta':
                return 'warning';
            case 'not-reviewed':
                return 'error';
            default:
                return 'inverse';
        }
    }

    get securityVariant() {
        if (this.insight.isSecurityReviewed === true) {
            return 'success';
        }
        if (this.insight.isSecurityReviewed === false) {
            return 'error';
        }
        return 'inverse';
    }
}
