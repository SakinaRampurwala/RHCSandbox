import { LightningElement, api, wire, track } from 'lwc';
import getLogoUrl from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getLogoUrl';
import getSenderInfo from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getSenderInfo';
import saveSignature from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.saveSignature';
import getOrgInfo from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getOrgInfo';

import savePdf from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.savePdf';
import getApplicationStatus from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getApplicationStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import ADDRESS_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Address__c';
import CITY_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__City_Text__c';
import STATE_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__State__c';
import ZIP_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Zip__c';
import COUNTRY_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Country__c';
import CUSTOMER_NAME_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Customer__r.Name';

const FIELDS = [
    ADDRESS_FIELD,
    CITY_FIELD,
    STATE_FIELD,
    ZIP_FIELD,
    COUNTRY_FIELD,
    CUSTOMER_NAME_FIELD
];


export default class ProjectImprovementProgramPhotoReleaseLwc extends LightningElement {
    @api isPreview; 
    @api recordId; 
    @api senderId;
    @api sendDate;

    @track isLoading = true;
    @track logoURL;
    @track senderInfo;
    @track signerName = '';
    @track coSignerName = '';
    @track isSubmitted = false;
    @track isAlreadySubmitted = false;
    @track submitError = '';
    @track checkedItems = new Set();

    // Canvas properties
    signaturePads = {};
    orgName;

    
    address;
    city;
    state;
    zip;
    country;
    customerName;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredProject({ data, error }) {
        if (data) {
            this.address = data.fields.buildertek__Address__c.value;
            this.city = data.fields.buildertek__City_Text__c.value;
            this.state = data.fields.buildertek__State__c.value;
            this.zip = data.fields.buildertek__Zip__c.value;
            this.country = data.fields.buildertek__Country__c.value;
            this.customerName = data.fields.buildertek__Customer__r.displayValue || data.fields.buildertek__Customer__r.value.fields.Name.value;
        } else if (error) {
            console.error(error);
        }
    }

    get projectAddress() {
        return `${this.address || ''}, ${this.city || ''} ${this.state || ''} -  ${this.zip || ''}, ${this.country || ''}`;
    }


    @wire(getOrgInfo)
    wiredOrg({ error, data }) {
        if (data) {
            this.orgName = data.Name;
        } else if (error) {
            this.error = error;
        }
    }

    @wire(getLogoUrl)
    wiredLogoUrl({ error, data }) {
        if (data) {
            this.logoURL = data;
        } else if (error) {
            console.error('Failed to load logo URL', error);
        }
    }

    @wire(getSenderInfo, { senderId: '$senderId' })
    wiredSenderInfo({ error, data }) {
        if (data) {
            this.senderInfo = data;
        } else if (error) {
            console.error('Failed to load sender info', error);
        }
    }

    @wire(getApplicationStatus, { recordId: '$recordId' })
    wiredAppStatus({ error, data }) {
        if (data) {
            if (data.Home_Improvement_Submitted_Date__c) {
                this.isSubmitted = true;
                this.isAlreadySubmitted = true;
            }
            this.isLoading = false;
        } else if (error) {
            console.error('Failed to load application status', error);
            this.isLoading = false;
        }
    }

    get isReadOnly() {
        return this.isPreview === true || this.isPreview === 'true' || this.isSubmitted;
    }

    get displayDate() {
        if (this.sendDate) {
            return new Date(this.sendDate).toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            });
        }
        return new Date().toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric'
        });
    }

    get organizationName() {
        return this.senderInfo?.organizationName || '';
    }

    get street() {
        return this.senderInfo?.street || '';
    }

    get cityStateZip() {
        if (!this.senderInfo) return '';
        const { city = '', state = '', postalCode = '' } = this.senderInfo;
        return `${city}${city && state ? ', ' : ''}${state}${state && postalCode ? ' ' : ''}${postalCode}`;
    }

    get senderName() {
        return this.senderInfo?.name || '';
    }

    get phone() {
        return this.senderInfo?.phone || '';
    }

    get altPhone() {
        return this.senderInfo?.altPhone || '';
    }

    get email() {
        return this.senderInfo?.email || '';
    }

    get signatureCanvasClass() {
        return `signature-pad${this.isReadOnly ? ' read-only' : ''}`;
    }

    get isSubmitDisabled() {
        const ownerPad = this.signaturePads.primary;
        const coOwnerPad = this.signaturePads.secondary;
        const hasOwnerName = this.signerName.trim() !== '';
        const hasCoOwnerName = this.coSignerName.trim() !== '';

        return this.isReadOnly || !ownerPad?.isSigned || !coOwnerPad?.isSigned || !hasOwnerName || !hasCoOwnerName;
    }

    connectedCallback() {
        if (!this.recordId) {
            this.isLoading = false;
        }
    }

    renderedCallback() {
        this.initializeCanvas('primary');
        this.initializeCanvas('secondary');
    }

    initializeCanvas(signatureId) {
        const canvasElement = this.template.querySelector(`canvas[data-signature-id="${signatureId}"]`);
        if (!canvasElement || this.signaturePads[signatureId]?.initialized) return;

        const ctx = canvasElement.getContext('2d');
        this.signaturePads[signatureId] = {
            canvasElement,
            ctx,
            isDrawing: false,
            isSigned: false,
            initialized: true
        };
        this.setCanvasSize(signatureId);
    }

    setCanvasSize(signatureId) {
        const pad = this.signaturePads[signatureId];
        if (!pad) return;

        pad.canvasElement.width = pad.canvasElement.offsetWidth;
        pad.canvasElement.height = pad.canvasElement.offsetHeight;
        pad.ctx.lineWidth = 2;
        pad.ctx.lineCap = 'round';
        pad.ctx.strokeStyle = '#000';
    }

    handleCheckboxChange(event) {
        if (this.isReadOnly) return;
        const id = event.target.dataset.id;
        if (event.target.checked) {
            this.checkedItems.add(id);
        } else {
            this.checkedItems.delete(id);
        }
    }

    handleNameChange(event) {
        if (this.isReadOnly) return;
        this.signerName = event.target.value;
    }

    handleCoSignerNameChange(event) {
        if (this.isReadOnly) return;
        this.coSignerName = event.target.value;
    }

    // Signature Pad logic
    handleMouseDown(event) {
        if (this.isReadOnly) return;
        const signatureId = event.currentTarget.dataset.signatureId;
        const pad = this.signaturePads[signatureId];
        if (!pad) return;

        pad.isDrawing = true;
        pad.isSigned = true;
        const { offsetX, offsetY } = this.getCoordinates(pad.canvasElement, event);
        pad.ctx.beginPath();
        pad.ctx.moveTo(offsetX, offsetY);
    }

    handleMouseMove(event) {
        if (this.isReadOnly) return;
        const signatureId = event.currentTarget.dataset.signatureId;
        const pad = this.signaturePads[signatureId];
        if (!pad || !pad.isDrawing) return;

        const { offsetX, offsetY } = this.getCoordinates(pad.canvasElement, event);
        pad.ctx.lineTo(offsetX, offsetY);
        pad.ctx.stroke();
    }

    handleMouseUp(event) {
        const signatureId = event.currentTarget.dataset.signatureId;
        const pad = this.signaturePads[signatureId];
        if (!pad) return;
        pad.isDrawing = false;
    }

    handleTouchStart(event) {
        if (this.isReadOnly) return;
        event.preventDefault();
        const touch = event.touches[0];
        const mouseEvent = new MouseEvent('mousedown', {
            clientX: touch.clientX,
            clientY: touch.clientY
        });
        event.currentTarget.dispatchEvent(mouseEvent);
    }

    handleTouchMove(event) {
        event.preventDefault();
        const touch = event.touches[0];
        const mouseEvent = new MouseEvent('mousemove', {
            clientX: touch.clientX,
            clientY: touch.clientY
        });
        event.currentTarget.dispatchEvent(mouseEvent);
    }

    handleTouchEnd(event) {
        event.preventDefault();
        const mouseEvent = new MouseEvent('mouseup', {});
        event.currentTarget.dispatchEvent(mouseEvent);
    }

    getCoordinates(canvasElement, event) {
        const rect = canvasElement.getBoundingClientRect();
        const clientX = event.clientX || event.touches?.[0].clientX;
        const clientY = event.clientY || event.touches?.[0].clientY;
        return {
            offsetX: clientX - rect.left,
            offsetY: clientY - rect.top
        };
    }

    clearSignature(event) {
        if (this.isReadOnly) return;
        const signatureId = event.currentTarget.dataset.signatureId;
        const pad = this.signaturePads[signatureId];
        if (!pad) return;

        pad.ctx.clearRect(0, 0, pad.canvasElement.width, pad.canvasElement.height);
        pad.isSigned = false;
    }

    handleSubmit() {
        console.log('handleSubmit');
        
        this.isLoading = true;
        this.submitError = '';
        const primaryPad = this.signaturePads.primary;
        const secondaryPad = this.signaturePads.secondary;
        if (!primaryPad?.canvasElement || !secondaryPad?.canvasElement) {
            this.isLoading = false;
            return;
        }
        const ownerSignatureBody = primaryPad.canvasElement.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, "");
        const coOwnerSignatureBody = secondaryPad.canvasElement.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, "");

        Promise.all([
            saveSignature({
                recordId: this.recordId,
                signatureBody: ownerSignatureBody
            }),
            saveSignature({
                recordId: this.recordId,
                signatureBody: coOwnerSignatureBody
            })
        ])
        .then(([ownerSignatureResult, coOwnerSignatureResult]) => {
            console.log(ownerSignatureResult, coOwnerSignatureResult);

            if (typeof ownerSignatureResult === 'string' || typeof coOwnerSignatureResult === 'string') {
                this.isSubmitted = true;
                this.submitError = typeof ownerSignatureResult === 'string'
                    ? ownerSignatureResult
                    : coOwnerSignatureResult;
                return null;
            }

            return savePdf({
                recordId: this.recordId,
                senderId: this.senderId,
                sendDate: this.sendDate,
                imgUrl: ownerSignatureResult.imgUrl || '',
                signerName: this.signerName,
                signatureId: ownerSignatureResult.cvId || '',
                coSignerImgUrl: coOwnerSignatureResult.imgUrl || '',
                coSignerName: this.coSignerName,
                coSignatureId: coOwnerSignatureResult.cvId || ''
            });
        })
        .then((pdfResult) => {
            console.log(pdfResult);
            
            if (pdfResult === 'Success') {
                this.isSubmitted = true;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Attestation submitted successfully.',
                        variant: 'success'
                    })
                );
            }
        })
        .catch(error => {
            console.error('Error submitting attestation', error);
            this.submitError = error.body?.message || error.message || 'An unknown error occurred';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.submitError,
                    variant: 'error'
                })
            );
        })
        .finally(() => {
            this.isLoading = false;
        });
    }
}
