import { LightningElement, api, wire, track } from 'lwc';
import getLogoUrl from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getLogoUrl';
import getSenderInfo from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getSenderInfo';
import saveSignature from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.saveSignature';
import getOrgInfo from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getOrgInfo';

// import savePdf from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.savePdf';
// import getApplicationStatus from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getApplicationStatus';
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

    @track isLoading = false;
    @track logoURL;
    @track senderInfo;
    @track signerName = '';
    @track isSubmitted = false;
    @track isAlreadySubmitted = false;
    @track submitError = '';
    
    @track checkedItems = new Set();
    
    attestations = [
        { id: 1, label: 'I acknowledge that a lien will be placed on my property for a period of 2, 5, or 10 years. I must reside in the house for that period or pay the grant back.' },
        { id: 2, label: 'I understand that any changes to the scope of work are my responsibility to pay for.' },
        { id: 3, label: 'I understand that I must promptly reply to any requests for additional or missing documentation or I will be removed from the program.' },
        { id: 4, label: 'I agree to provide access to my home for contractors to work from 8am to 5pm, Monday through Friday, for the duration of the contract.' },
        { id: 5, label: 'I acknowledge that I may be required to contribute a portion of the project cost based on my income.' },
        { id: 6, label: 'I understand that all individuals listed on the deed must sign all necessary paperwork and liens for this project.' },
        { id: 7, label: 'I acknowledge that failure to attend scheduled appointments will result in dismissal from the grant program and rescission of funding.' },
        { id: 8, label: 'I will provide full access to the entire property to the construction manager, inspectors, contractor, and staff during both the application and construction processes.' },
        { id: 9, label: 'I understand that I am responsible for the behavior of myself, residents, visitors, and agents. Aggression, intimidation, or harassment from any of these parties will result in my termination from the program.' },
        { id: 10, label: 'All pets must be secured during appointments and construction. Failure to do so will result in removal from the program.' },
        { id: 11, label: 'I will maintain my property in a clean, safe, and sanitary condition throughout the application and construction processes, as well as during the regulatory period, or I will be removed from the program.' },
        { id: 12, label: 'I acknowledge that not all deficiencies in my property may be addressed, and my home may not be eligible for any repairs due to the type or extent of repairs required.' },
        { id: 13, label: 'I agree to take financial literacy training provided by The Housing Council at PathStone prior to final acceptance into the program.' },
        { id: 14, label: 'I acknowledge my taxes and mortgage have been paid on time for the last 3 months and will continue to be paid on time during the application and construction process.' }
    ];

    // Canvas properties
    canvasElement;
    ctx;
    isDrawing = false;
    isSigned = false;
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

    // @wire(getApplicationStatus, { recordId: '$recordId' })
    // wiredAppStatus({ error, data }) {
    //     if (data) {
    //         if (data.Attestation_Submitted__c) {
    //             this.isSubmitted = true;
    //             this.isAlreadySubmitted = true;
    //         }
    //         this.isLoading = false;
    //     } else if (error) {
    //         console.error('Failed to load application status', error);
    //         this.isLoading = false;
    //     }
    // }

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

    // get signatureCanvasClass() {
    //     return `signature-pad${this.isReadOnly ? ' read-only' : ''}`;
    // }

    get isSubmitDisabled() {
        return this.isReadOnly || !(this.checkedItems.size === this.attestations.length && this.isSigned && this.signerName.trim() !== '');
    }

    connectedCallback() {
        if (!this.recordId) {
            this.isLoading = false;
        }
    }

    renderedCallback() {
        if (!this.canvasElement) {
            this.canvasElement = this.template.querySelector('canvas');
            this.ctx = this.canvasElement.getContext('2d');
            this.setCanvasSize();
        }
    }

    setCanvasSize() {
        this.canvasElement.width = this.canvasElement.offsetWidth;
        this.canvasElement.height = this.canvasElement.offsetHeight;
        this.ctx.lineWidth = 2;
        this.ctx.lineCap = 'round';
        this.ctx.strokeStyle = '#000';
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

    // Signature Pad logic
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

    handleSubmit() {
        this.isLoading = true;
        this.submitError = '';
        const signatureBody = this.canvasElement.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, "");
        
        // saveSignature({
        //     recordId: this.recordId,
        //     signatureBody: signatureBody
        // })
        // .then((result) => {
        //     if (typeof result === 'string') {
        //         // This means the backward compatibility wrapper was called
        //         this.isSubmitted = true;
        //         this.submitError = result; // Show the cache warning
        //         return null;
        //     }
        //     return savePdf({
        //         recordId: this.recordId,
        //         senderId: this.senderId,
        //         sendDate: this.sendDate,
        //         imgUrl: result.imgUrl || '',
        //         signerName: this.signerName,
        //         signatureId: result.cvId || ''
        //     });
        // })
        // .then((pdfResult) => {
        //     if (pdfResult === 'Success') {
        //         this.isSubmitted = true;
        //         this.dispatchEvent(
        //             new ShowToastEvent({
        //                 title: 'Success',
        //                 message: 'Attestation submitted successfully.',
        //                 variant: 'success'
        //             })
        //         );
        //     }
        // })
        // .catch(error => {
        //     console.error('Error submitting attestation', error);
        //     this.submitError = error.body?.message || error.message || 'An unknown error occurred';
        //     this.dispatchEvent(
        //         new ShowToastEvent({
        //             title: 'Error',
        //             message: this.submitError,
        //             variant: 'error'
        //         })
        //     );
        // })
        // .finally(() => {
        //     this.isLoading = false;
        // });
    }
}