import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getLogoUrl from '@salesforce/apex/NoticeToProceedCtrl.getLogoUrl';
import saveSignature from '@salesforce/apex/NoticeToProceedCtrl.saveSignature';
import savePdf from '@salesforce/apex/NoticeToProceedCtrl.savePdf';
import CASE_NO_FIELD from '@salesforce/schema/buildertek__Project__c.Case_No__c';
import ADDRESS_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Address__c';
import CITY_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__City_Text__c';
import STATE_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__State__c';
import ZIP_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Zip__c';
import COUNTRY_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Country__c';
import CUSTOMER_NAME_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Customer__r.Name';
import CONTRACTOR_NAME_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.Name';
import CONTRACTOR_PHONE_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.Phone';
import CONTRACTOR_BILLING_STREET_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.BillingStreet';
import CONTRACTOR_BILLING_CITY_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.BillingCity';
import CONTRACTOR_BILLING_STATE_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.BillingState';
import CONTRACTOR_BILLING_POSTAL_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.BillingPostalCode';
import CONTRACTOR_BILLING_COUNTRY_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.BillingCountry';

const FIELDS = [
    CASE_NO_FIELD,
    ADDRESS_FIELD,
    CITY_FIELD,
    STATE_FIELD,
    ZIP_FIELD,
    COUNTRY_FIELD,
    CUSTOMER_NAME_FIELD,
    CONTRACTOR_NAME_FIELD,
    CONTRACTOR_PHONE_FIELD,
    CONTRACTOR_BILLING_STREET_FIELD,
    CONTRACTOR_BILLING_CITY_FIELD,
    CONTRACTOR_BILLING_STATE_FIELD,
    CONTRACTOR_BILLING_POSTAL_FIELD,
    CONTRACTOR_BILLING_COUNTRY_FIELD
];

export default class NoticeToProceedLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    @track isLoading = true;
    @track isSubmitted = false;
    @track logoURL;
    @track noticeData = {};

    canvasElement;
    ctx;
    isDrawing = false;
    isSigned = false;

    @wire(getLogoUrl)
    wiredLogo({ error, data }) {
        if (data) {
            this.logoURL = data;
        } else if (error) {
            // no-op for non-critical UI element
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredProject({ error, data }) {
        if (data) {
            const projectAddress = this.buildProjectLocation(data);
            const contractorAddress = this.buildContractorAddress(data);

            this.noticeData = {
                ...this.noticeData,
                caseNumber: getFieldValue(data, CASE_NO_FIELD) || '',
                projectLocation: projectAddress,
                propertyOwner: getFieldValue(data, CUSTOMER_NAME_FIELD) || '',
                contractor: getFieldValue(data, CONTRACTOR_NAME_FIELD) || '',
                telephone: getFieldValue(data, CONTRACTOR_PHONE_FIELD) || '',
                contractorAddress: contractorAddress
            };
        } else if (error) {
            this.noticeData = {};
        }
        this.isLoading = false;
    }

    connectedCallback() {
        if (!this.recordId) {
            this.isLoading = false;
        }
    }

    get isReadOnly() {
        return this.isPreview === true || this.isPreview === 'true';
    }

    get signatureCanvasClass() {
        return `signature-pad${this.isReadOnly ? ' read-only' : ''}`;
    }

    get isSubmitDisabled() {
        return this.isReadOnly || !this.isSigned;
    }

    renderedCallback() {
        if (!this.canvasElement) {
            this.canvasElement = this.template.querySelector('canvas');
            if (this.canvasElement) {
                this.ctx = this.canvasElement.getContext('2d');
                this.setCanvasSize();
            }
        }
    }

    setCanvasSize() {
        this.canvasElement.width = this.canvasElement.offsetWidth;
        this.canvasElement.height = this.canvasElement.offsetHeight;
        this.ctx.lineWidth = 2;
        this.ctx.lineCap = 'round';
        this.ctx.strokeStyle = '#000';
    }

    handleMouseDown(event) {
        if (this.isReadOnly) return;
        this.isDrawing = true;
        this.isSigned = true;
        const { offsetX, offsetY } = this.getCoordinates(event);
        this.ctx.beginPath();
        this.ctx.moveTo(offsetX, offsetY);
    }

    handleMouseMove(event) {
        if (!this.isDrawing || this.isReadOnly) return;
        const { offsetX, offsetY } = this.getCoordinates(event);
        this.ctx.lineTo(offsetX, offsetY);
        this.ctx.stroke();
    }

    handleMouseUp() {
        this.isDrawing = false;
    }

    handleTouchStart(event) {
        if (this.isReadOnly) return;
        event.preventDefault();
        const touch = event.touches[0];
        const mouseEvent = new MouseEvent('mousedown', {
            clientX: touch.clientX,
            clientY: touch.clientY
        });
        this.canvasElement.dispatchEvent(mouseEvent);
    }

    handleTouchMove(event) {
        event.preventDefault();
        const touch = event.touches[0];
        const mouseEvent = new MouseEvent('mousemove', {
            clientX: touch.clientX,
            clientY: touch.clientY
        });
        this.canvasElement.dispatchEvent(mouseEvent);
    }

    handleTouchEnd(event) {
        event.preventDefault();
        const mouseEvent = new MouseEvent('mouseup', {});
        this.canvasElement.dispatchEvent(mouseEvent);
    }

    getCoordinates(event) {
        const rect = this.canvasElement.getBoundingClientRect();
        const clientX = event.clientX || event.touches?.[0].clientX;
        const clientY = event.clientY || event.touches?.[0].clientY;
        return {
            offsetX: clientX - rect.left,
            offsetY: clientY - rect.top
        };
    }

    clearSignature() {
        if (this.isReadOnly) return;
        this.ctx.clearRect(0, 0, this.canvasElement.width, this.canvasElement.height);
        this.isSigned = false;
    }

    buildProjectLocation(recordData) {
        const address = getFieldValue(recordData, ADDRESS_FIELD) || '';
        const city = getFieldValue(recordData, CITY_FIELD) || '';
        const state = getFieldValue(recordData, STATE_FIELD) || '';
        const zip = getFieldValue(recordData, ZIP_FIELD) || '';
        const country = getFieldValue(recordData, COUNTRY_FIELD) || '';

        const cityState = [city, state].filter(Boolean).join(' ');
        const firstPart = [address, cityState].filter(Boolean).join(', ');
        const zipPart = zip ? ` - ${zip}` : '';
        const countryPart = country ? `, ${country}` : '';
        return `${firstPart}${zipPart}${countryPart}`.trim();
    }

    buildContractorAddress(recordData) {
        const street = getFieldValue(recordData, CONTRACTOR_BILLING_STREET_FIELD) || '';
        const city = getFieldValue(recordData, CONTRACTOR_BILLING_CITY_FIELD) || '';
        const state = getFieldValue(recordData, CONTRACTOR_BILLING_STATE_FIELD) || '';
        const postalCode = getFieldValue(recordData, CONTRACTOR_BILLING_POSTAL_FIELD) || '';
        const country = getFieldValue(recordData, CONTRACTOR_BILLING_COUNTRY_FIELD) || '';

        const cityStatePostal = [city, state, postalCode].filter(Boolean).join(' ');
        return [street, cityStatePostal, country].filter(Boolean).join(', ');
    }

    handleSubmit() {
        this.isLoading = true;

        if (!this.canvasElement) {
            this.isLoading = false;
            return;
        }

        const signatureBody = this.canvasElement
            .toDataURL('image/png')
            .replace(/^data:image\/(png|jpg);base64,/, '');

        saveSignature({
            recordId: this.recordId,
            signatureBody
        })
            .then((signatureResult) => {
                return savePdf({
                    recordId: this.recordId,
                    senderId: this.senderId,
                    sendDate: this.sendDate,
                    imgUrl: signatureResult?.imgUrl || '',
                    signerName: '',
                    signatureId: signatureResult?.cvId || ''
                });
            })
            .then((result) => {
                if (result === 'Success') {
                    this.isSubmitted = true;
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Notice To Proceed submitted successfully.',
                            variant: 'success'
                        })
                    );
                }
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error?.body?.message || error?.message || 'An unknown error occurred',
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}
