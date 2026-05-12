import { LightningElement, api, wire, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import ModalPreviewWidth from '@salesforce/resourceUrl/buildertek__ModalPreviewWidth85';
import getOrgWideEmailAddresses from '@salesforce/apex/InspectionPreviewEmailController.getOrgWideEmailAddresses';
import getEmailSignature from '@salesforce/apex/InspectionPreviewEmailController.getEmailSignature';
import getEmailBody from '@salesforce/apex/InspectionPreviewEmailController.getEmailBody';
import sendEmail from '@salesforce/apex/InspectionPreviewEmailController.sendEmail';

export default class InspectionPreviewEmail extends LightningElement {
    _recordId;

    @track showSpinner = true;
    @track templateOptions = [
        {
            label: 'Certificate Of Inspection',
            value: 'CertificateOfInspection'
        },
        {
            label: 'Final Inspection Form',
            value: 'FinalInspectionForm'
        }
    ];

    @track orgWideEmailOptions = [];
    @track selectedTemplateId = '';
    @track selectedFromAddress = '';
    @track contractorContactList = [];
    @track homeownerContactList = [];
    @track homsiteRepContactList = [];
    @track codeEnforcementContactList = [];
    @track vendorContactList = [];
    @track companyContactList = [];
    @track emailSubject = '';
    @track emailBody = '';
    @track emailEditBody = '';
    @track attachedFiles = [];
    @track useEmailSignature = false;
    @track userData = {};
    @track isBodyPreviewExpanded = true;
    @track isProjectImprovementExpanded = true;
    @track isSendDisabled = true;

    templatesLoaded = false;
    emailAddressesLoaded = false;
    defaultBodyLoaded = false;
    attachedTemplateLoaded = false;

    richTextFormats = [
        'font', 'size', 'bold', 'italic', 'underline',
        'list', 'indent', 'align', 'link', 'image', 'clean', 'table'
    ];

    leftWidth = 40;
    dividerPx = 6;
    minPct = 15;
    maxPct = 85;
    splitDragging = false;

    contactNamePlaceholder = '{!ContactName}';
    lastSelectedContactName = '{!ContactName}';
    pendingContactName = null;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.initializeComponent();
        }
    }

    connectedCallback() {
        loadStyle(this, ModalPreviewWidth).catch(error => {
            this.logError('Unable to load modal width stylesheet', error);
        });
        this.loadOrgWideEmailAddresses();
    }

    disconnectedCallback() {
        this.stopSplitDrag();
    }

    @wire(getEmailSignature)
    wiredUser({ error, data }) {
        if (data) {
            this.userData = data;
        } else if (error) {
            this.logError('Unable to load current user signature', error);
        }
    }

    get headerTitle() {
        return 'Preview & Email';
    }

    get gridStyle() {
        const dividerWidth = this.dividerPx;
        return `grid-template-columns: ${this.leftWidth}% ${dividerWidth}px calc(100% - ${this.leftWidth}% - ${dividerWidth}px); gap: 0;`;
    }

    get hasSelectedTemplate() {
        return Boolean(this.selectedTemplateId && this.recordId);
    }

    get selectedTemplatePreviewUrl() {
        if (!this.hasSelectedTemplate) {
            return '';
        }

        const today = new Date();
        const month = String(today.getMonth() + 1).padStart(2, '0');
        const day = String(today.getDate()).padStart(2, '0');
        const year = today.getFullYear();
        const sendDate = `${year}-${month}-${day}`;

        return `/apex/${this.selectedTemplateId}?id=${this.recordId}&isPreview=true&senderId=${this.userData?.Id || ''}&sendDate=${sendDate}`;
    }

    get isFinalInspectionForm() {
        return this.selectedTemplateId === 'FinalInspectionForm';
    }

    initializeComponent() {
        this.showSpinner = true;
        this.templatesLoaded = false;
        this.defaultBodyLoaded = false;
        this.attachedTemplateLoaded = true;

        this.setFirstTemplateAsDefault();
    }

    checkAllLoaded() {
        setTimeout(() => {
            if (this.templatesLoaded && this.emailAddressesLoaded && this.defaultBodyLoaded && this.attachedTemplateLoaded) {
                this.showSpinner = false;
            }
            this.handleBtnEnable();
        }, 700);
    }

    loadOrgWideEmailAddresses() {
        getOrgWideEmailAddresses()
            .then(result => {
                this.orgWideEmailOptions = (result || []).map(address => ({
                    displayName: address.DisplayName,
                    emailAddress: address.Address,
                    label: `${address.DisplayName} <${address.Address}>`,
                    value: address.Id
                }));

                if (this.orgWideEmailOptions.length > 0) {
                    this.selectedFromAddress = this.orgWideEmailOptions[0].value;
                }
            })
            .catch(error => {
                this.logError('Unable to load org-wide email addresses', error);
                this.showToast('Error', 'Failed to load email addresses', 'error');
            })
            .finally(() => {
                this.emailAddressesLoaded = true;
                this.checkAllLoaded();
            });
    }

    loadDefaultEmailBody(templateKey) {
        if (!templateKey) {
            templateKey = this.selectedTemplateId;
        }

        if (!this.recordId || !templateKey) {
            this.defaultBodyLoaded = true;
            this.checkAllLoaded();
            return;
        }

        getEmailBody({
            recordId: this.recordId,
            vfApiName: templateKey
        })
            .then(result => {
                this.emailSubject = result?.subject || '';
                const emailBody = this.convertParagraphsToSpans(result?.htmlBody || '');
                this.emailBody = emailBody;
                this.emailEditBody = emailBody;

                const contactList = this.isFinalInspectionForm ? this.vendorContactList : this.contractorContactList;
                const primaryName = this.pendingContactName || (contactList.length > 0 ? contactList[0].Name : null);
                const didUpdate = this.applyContactNameToBody(primaryName);
                if (!didUpdate) {
                    this.updateBodyPreview();
                }
            })
            .catch(error => {
                this.logError('Unable to load email template body', error);
                this.emailSubject = '';
                this.emailBody = '';
                this.emailEditBody = '';
                this.showToast(
                    'Error',
                    'The Certificate Of Inspection template could not be loaded. Deploy the template metadata and verify it exists in Salesforce.',
                    'error'
                );
            })
            .finally(() => {
                this.defaultBodyLoaded = true;
                this.checkAllLoaded();
            });
    }

    setFirstTemplateAsDefault() {
        if (this.templateOptions.length > 0) {
            this.selectedTemplateId = this.templateOptions[0].value;
            this.loadDefaultEmailBody(this.selectedTemplateId);
        }
        this.templatesLoaded = true;
        this.checkAllLoaded();
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        this.loadDefaultEmailBody(this.selectedTemplateId);
        this.handleBtnEnable();
    }

    handleFromAddressChange(event) {
        this.selectedFromAddress = event.detail.value;
        this.handleBtnEnable();
    }

    handleContractorLookupChange(event) {
        const detail = event.detail || {};
        this.contractorContactList = this.createContactObj(detail.selectedRecords || []);
        this.handleBtnEnable();
        const primaryContractorName = this.contractorContactList.length > 0 ? this.contractorContactList[0].Name : null;
        const didUpdate = this.applyContactNameToBody(primaryContractorName);
        if (!didUpdate) {
            this.updateBodyPreview();
        }
    }

    handleHomeownerLookupChange(event) {
        const detail = event.detail || {};
        this.homeownerContactList = this.createContactObj(detail.selectedRecords || []);
        this.handleBtnEnable();
    }

    handleHomsiteRepLookupChange(event) {
        const detail = event.detail || {};
        this.homsiteRepContactList = this.createContactObj(detail.selectedRecords || []);
        this.handleBtnEnable();
    }

    handleCodeEnforcementLookupChange(event) {
        const detail = event.detail || {};
        this.codeEnforcementContactList = this.createContactObj(detail.selectedRecords || []);
        this.handleBtnEnable();
    }

    handleVendorLookupChange(event) {
        const detail = event?.detail || {};
        const selectedRecords = detail.selectedRecords
            ? detail.selectedRecords
            : (detail.selectedRecord ? [detail.selectedRecord] : []);
        this.vendorContactList = this.createContactObj(selectedRecords);
        this.handleBtnEnable();

        const primaryName = this.vendorContactList.length > 0 ? this.vendorContactList[0].Name : null;
        const didUpdate = this.applyContactNameToBody(primaryName);
        if (!didUpdate) {
            this.updateBodyPreview();
        }
    }

    handleCompanyLookupChange(event) {
        const detail = event?.detail || {};
        const selectedRecords = detail.selectedRecords
            ? detail.selectedRecords
            : (detail.selectedRecord ? [detail.selectedRecord] : []);
        this.companyContactList = this.createContactObj(selectedRecords);
        this.handleBtnEnable();
    }

    handleSubjectChange(event) {
        this.emailSubject = event.target.value;
        this.handleBtnEnable();
    }

    handleBodyChange(event) {
        const htmlValue = this.convertParagraphsToSpans(event.detail.value || '<div></div>');
        this.emailBody = htmlValue;
        this.updateBodyPreview();
    }

    handleEmailSignatureChange(event) {
        this.useEmailSignature = event.target.checked;

        if (this.useEmailSignature && !this.userData?.Signature) {
            this.showToast(
                'No Email Signature Found',
                'Set up your Salesforce email signature before relying on the signature preview.',
                'warning'
            );
        }
    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files || [];
        uploadedFiles.forEach(file => {
            this.attachedFiles = [...this.attachedFiles, { Id: file.documentId, name: file.name }];
        });
    }

    handleRemoveFile(event) {
        const fileId = event.detail.name;
        this.attachedFiles = this.attachedFiles.filter(file => file.Id !== fileId);
    }

    handleSendEmail() {
        const validationErrors = this.validateForm();
        if (validationErrors.length > 0) {
            this.showToast('Validation Error', validationErrors.join(' '), 'error');
            return;
        }

        this.showSpinner = true;
        this.sendEmailWithDataWrap();
    }

    sendEmailWithDataWrap() {
        const emailData = this.generateEmailDataWrap();
        sendEmail({
            emailData: JSON.stringify(emailData)
        })
            .then(result => {
                if (result?.isSuccess) {
                    this.showToast('Success', 'Email sent successfully.', 'success');
                    this.closeModal();
                    return;
                }

                this.showToast('Error', result?.errorMessage || 'Failed to send email.', 'error');
            })
            .catch(error => {
                this.logError('Unable to send email', error);
                this.showToast('Error', 'An unexpected error occurred while sending the email.', 'error');
            })
            .finally(() => {
                this.checkAllLoaded();
            });
    }

    updateBodyPreview() {
        const previewElement = this.template.querySelector('.email-body-preview');
        if (previewElement && this.emailBody) {
            previewElement.innerHTML = this.emailBody;
        }
        this.handleBtnEnable();
    }

    convertParagraphsToSpans(body) {
        if (!body) {
            return '';
        }

        let convertedHTML = body.replace(/<p><br><\/p>/gi, '<br>');
        convertedHTML = convertedHTML.replace(/<p><span/gi, '<div><span');
        convertedHTML = convertedHTML.replace(/<\/span><\/p>/gi, '</span></div><br>');
        convertedHTML = convertedHTML.replace(/<p([^>]*)>/gi, '<div$1>');
        convertedHTML = convertedHTML.replace(/<\/p>/gi, '</div><br>');

        return convertedHTML;
    }

    applyContactNameToBody(contactName) {
        const placeholder = this.contactNamePlaceholder;

        if (!contactName) {
            this.pendingContactName = null;

            if (!this.emailBody) {
                this.lastSelectedContactName = placeholder;
                return false;
            }

            if (this.lastSelectedContactName && this.lastSelectedContactName !== placeholder && this.emailBody.includes(this.lastSelectedContactName)) {
                const updatedBody = this.emailBody.replace(this.lastSelectedContactName, placeholder);
                this.emailBody = updatedBody;
                this.emailEditBody = updatedBody;
                this.lastSelectedContactName = placeholder;
                this.updateBodyPreview();
                return true;
            }

            this.lastSelectedContactName = placeholder;
            return false;
        }

        if (!this.emailBody) {
            this.pendingContactName = contactName;
            return false;
        }

        const tokens = [];
        if (this.lastSelectedContactName) {
            tokens.push(this.lastSelectedContactName);
        }
        if (!tokens.includes(placeholder)) {
            tokens.push(placeholder);
        }

        let updatedBody = this.emailBody;
        let replaced = false;

        for (const token of tokens) {
            if (token && updatedBody.includes(token)) {
                updatedBody = updatedBody.replace(token, contactName);
                replaced = true;
                break;
            }
        }

        if (!replaced && /\{\!ContactName\}/i.test(updatedBody)) {
            updatedBody = updatedBody.replace(/\{\!ContactName\}/gi, contactName);
            replaced = true;
        }

        if (replaced) {
            this.emailBody = updatedBody;
            this.emailEditBody = updatedBody;
            this.lastSelectedContactName = contactName;
            this.pendingContactName = null;
            this.updateBodyPreview();
            return true;
        }

        this.lastSelectedContactName = contactName;
        this.pendingContactName = null;
        return false;
    }

    validateForm() {
        const errors = [];

        if (!this.selectedTemplateId) {
            errors.push('Select a template.');
        }

        if (!this.selectedFromAddress) {
            errors.push('Select a From Address.');
        }

        if (this.isFinalInspectionForm) {
            if (this.vendorContactList.length === 0) {
                errors.push('Please add at least one homeowner recipient');
            }
            if (this.companyContactList.length === 0) {
                errors.push('Please select a program representative contact');
            }
        } else {
            if (this.contractorContactList.length === 0) {
                errors.push('Add at least one contractor recipient.');
            }

            if (this.homeownerContactList.length === 0) {
                errors.push('Add at least one homeowner recipient.');
            }

            if (this.homsiteRepContactList.length === 0) {
                errors.push('Add at least one Homsite Representative recipient.');
            }

            if (this.codeEnforcementContactList.length === 0) {
                errors.push('Add at least one Code Enforcement recipient.');
            }
        }

        if (!this.emailSubject?.trim()) {
            errors.push('Enter an email subject.');
        }

        const plainBodyText = (this.emailBody || '').replace(/<[^>]*>/g, '').trim();
        if (!plainBodyText) {
            errors.push('Enter email content.');
        }

        return errors;
    }

    handleBtnEnable() {
        this.isSendDisabled = this.showSpinner || this.validateForm().length > 0;
    }

    generateEmailDataWrap() {
        const vendorContactIds = (this.vendorContactList ?? []).map(contact => contact?.Id);
        const companyContactIds = (this.companyContactList ?? []).map(contact => contact?.Id);
        const vendorEmails = (this.vendorContactList ?? []).map(contact => contact?.Email);
        const companyEmails = (this.companyContactList ?? []).map(contact => contact?.Email);

        return {
            recordId: this.recordId,
            templateId: this.selectedTemplateId,
            fromAddress: this.selectedFromAddress,
            contractorContactIds: this.contractorContactList.map(contact => contact.Id),
            contractorEmails: this.contractorContactList.map(contact => contact.Email),
            homeownerContactIds: this.homeownerContactList.map(contact => contact.Id),
            homeownerEmails: this.homeownerContactList.map(contact => contact.Email),
            homsiteRepContactIds: this.homsiteRepContactList.map(contact => contact.Id),
            homsiteRepEmails: this.homsiteRepContactList.map(contact => contact.Email),
            codeEnforcementContactIds: this.codeEnforcementContactList.map(contact => contact.Id),
            codeEnforcementEmails: this.codeEnforcementContactList.map(contact => contact.Email),
            vendorContactIds: vendorContactIds,
            vendorEmails: vendorEmails,
            companyContactIds: companyContactIds,
            companyEmails: companyEmails,
            subject: this.emailSubject,
            htmlBody: this.emailBody,
            contactNameToken: this.contactNamePlaceholder,
            lastSelectedContactName: this.lastSelectedContactName,
            useEmailSignature: this.useEmailSignature,
            saveAsActivity: false,
            fileIds: this.attachedFiles.map(file => file.Id)
        };
    }

    createContactObj(selectedRecords) {
        return (selectedRecords || []).map(record => ({
            Id: record.Id,
            Name: record.Name,
            Email: record.Email
        }));
    }

    handleBodyToggle() {
        this.isBodyPreviewExpanded = !this.isBodyPreviewExpanded;
        if (this.isBodyPreviewExpanded) {
            setTimeout(() => this.updateBodyPreview(), 0);
        }
    }

    handleAttachmentToggle() {
        this.isProjectImprovementExpanded = !this.isProjectImprovementExpanded;
    }

    startSplitDrag = event => {
        event.preventDefault();
        this.splitDragging = true;
        this.template.host.classList.add('dragging');
        window.addEventListener('mousemove', this.onSplitMouseMove);
        window.addEventListener('mouseup', this.stopSplitDrag);
    };

    startSplitDragTouch = event => {
        event.preventDefault();
        this.splitDragging = true;
        this.template.host.classList.add('dragging');
        window.addEventListener('touchmove', this.onSplitTouchMove, { passive: false });
        window.addEventListener('touchend', this.stopSplitDrag);
    };

    onSplitMouseMove = event => {
        this.resizeSplitToClientX(event.clientX);
    };

    onSplitTouchMove = event => {
        if (event.touches && event.touches.length) {
            this.resizeSplitToClientX(event.touches[0].clientX);
            event.preventDefault();
        }
    };

    resizeSplitToClientX(clientX) {
        const container = this.template.querySelector('.email-composer-container');
        if (!container) {
            return;
        }

        const rect = container.getBoundingClientRect();
        let widthPercent = ((clientX - rect.left) / rect.width) * 100;
        widthPercent = Math.max(this.minPct, Math.min(this.maxPct, widthPercent));
        this.leftWidth = Math.round(widthPercent * 10) / 10;
    }

    stopSplitDrag = () => {
        if (!this.splitDragging) {
            return;
        }

        this.splitDragging = false;
        this.template.host.classList.remove('dragging');
        window.removeEventListener('mousemove', this.onSplitMouseMove);
        window.removeEventListener('mouseup', this.stopSplitDrag);
        window.removeEventListener('touchmove', this.onSplitTouchMove);
        window.removeEventListener('touchend', this.stopSplitDrag);
    };

    onSplitKey = event => {
        const step = event.shiftKey ? 5 : 1;
        if (event.key === 'ArrowLeft') {
            this.leftWidth = Math.max(this.minPct, this.leftWidth - step);
            event.preventDefault();
        } else if (event.key === 'ArrowRight') {
            this.leftWidth = Math.min(this.maxPct, this.leftWidth + step);
            event.preventDefault();
        }
    };

    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant,
            mode: 'dismissible'
        }));
    }

    logError(message, error) {
        if (error !== undefined) {
            // eslint-disable-next-line no-console
            console.error(`[InspectionPreviewEmail] ${message}`, error);
        } else {
            // eslint-disable-next-line no-console
            console.error(`[InspectionPreviewEmail] ${message}`);
        }
    }
}