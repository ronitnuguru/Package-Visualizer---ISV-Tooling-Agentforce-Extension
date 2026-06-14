import { LightningElement, api } from 'lwc';

const NEXT_STEPS = [
    { value: 'recent-versions', label: 'Recent package versions', description: 'See the latest versions for a package.', say: 'show recent package versions' },
    { value: 'subscriber-count', label: 'Subscriber count', description: 'How many orgs have a package installed.', say: 'how many subscribers' },
    { value: 'dependencies', label: 'Check dependencies', description: "Inspect a package version's dependencies.", say: 'check for dependencies' }
];

export default class AgentPackageCatalogCard extends LightningElement {
    @api value;
    selected;
    hint;

    get catalog() {
        return this.value || {};
    }

    get hasError() {
        return !!this.catalog.errorMessage;
    }

    get hasPackages() {
        return this.catalog.packages && this.catalog.packages.length > 0;
    }

    get submitDisabled() {
        return !this.selected;
    }

    get rows() {
        return (this.catalog.packages || []).map((p, i) => ({
            ...p,
            key: p.subscriberPackageId || `pkg-${i}`,
            badgeVariant: p.containerOptions === 'Unlocked' ? 'success' : 'inverse',
            nsLabel: p.namespacePrefix || '—'
        }));
    }

    get nextSteps() {
        return NEXT_STEPS.map((s) => ({ ...s, selected: s.value === this.selected }));
    }

    handleSelect(event) {
        this.selected = event.target.value;
        this.hint = undefined;
    }

    handleSubmit() {
        const step = NEXT_STEPS.find((s) => s.value === this.selected);
        if (!step) {
            return;
        }
        // Best-effort back-channel: dispatch a composed event the conversation host MAY consume.
        // If no host listens (expected today), the echo hint below is the guaranteed affordance.
        this.dispatchEvent(
            new CustomEvent('agentnextstep', {
                detail: { value: step.value, message: step.say },
                bubbles: true,
                composed: true
            })
        );
        this.hint = `👉 Tell me: "${step.say}"`;
    }
}
