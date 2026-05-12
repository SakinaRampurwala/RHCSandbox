import { LightningElement, api, track } from 'lwc';
import getLogoUrl from '@salesforce/apex/HIPApplicationCtrl.getLogoUrl';

export default class HipApplicationLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    @track logoUrl;

    connectedCallback() {
        this.loadLogo();
    }

    loadLogo() {
        getLogoUrl()
            .then((result) => {
                this.logoUrl = result;
            })
            .catch((error) => {
                // Keep rendering even if logo retrieval fails.
                // eslint-disable-next-line no-console
                console.error('Failed to load HIP application logo', error);
                this.logoUrl = null;
            });
    }
}
