import { LightningElement, api, wire, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import ModalPreviewWidth from '@salesforce/resourceUrl/buildertek__ModalPreviewWidth85';
import getOrgWideEmailAddresses from '@salesforce/apex/ProjectPreviewEmailController.getOrgWideEmailAddresses';
import getEmailSignature from '@salesforce/apex/ProjectPreviewEmailController.getEmailSignature';
import getRelatedFiles from '@salesforce/apex/ProjectPreviewEmailController.getRelatedFiles';
import getEmailBody from '@salesforce/apex/ProjectPreviewEmailController.getEmailBody';
import saveSignature from '@salesforce/apex/ProjectPreviewEmailController.saveSignature';
import sendEmail from '@salesforce/apex/ProjectPreviewEmailController.sendEmail';

export default class ProjectPreviewEmail extends LightningElement {
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

    @track showSpinner = true;
    @track includeRefId = false;
    @track showFileUpload = true;
    @track isBodyRequired = true;
    @track emailSubject = '';

    @track templateOptions = [
        {
            label: 'Project Improvement Program Photo Release Form',
            value: 'ProjectImprovementProgramPhotoRelease'
        }, 
        {
            label: 'Notice To Proceed',
            value: 'NoticeToProceed'
        }
    ];
    @track orgWideEmailOptions = [];
    @track selectedTemplateId = '';
    @track selectedFromAddress = '';
    @track toContactList = [];
    @track ccContactList = [];
    @track bccContactList = [];
    @track additionalEmailsInput = '';
    @track additionalEmailsList = [];
    @track emailBody = '';
    @track emailEditBody = '';
    @track attachedFiles = [];
    @track useEmailSignature = false;
    @track isCcCurrentUser = false;
    @track saveAsActivity = false;
    @track userData = {};
    contactNamePlaceholder = '{!ContactName}';
    lastSelectedContactName = '{!ContactName}';
    pendingContactName = null;
    signaturePadCanvas;
    signatureContext;
    isDrawing = false;
    signDocumentId = '';

    @track isBodyPreviewExpanded = true;
    @track isProjectImprovementExpanded = true;

    @track showRecordFileModal = false;
    @track relatedFileList = [];
    @track tempSelectedFiles = [];

    @track isSendDisabled = true;

    templatesLoaded = false;
    emailAddressesLoaded = false;
    defaultBodyLoaded = false;
    attachedTemplateLoaded = false;

    richTextFormats = [
        'font', 'size', 'bold', 'italic', 'underline',
        'list', 'indent', 'align', 'link', 'image', 'clean', 'table'
    ];

    // ADDED: split pane state (kept minimal & defaults match 2fr:3fr)
    leftWidth = 40;       // percentage of left pane (approx 2/5)
    dividerPx = 6;        // visual splitter width in px
    minPct = 15;
    maxPct = 85;
    splitDragging = false;

    // ADDED: computed inline grid style (also zeroes gap so the divider is the only line)
    get gridStyle() {
        const d = this.dividerPx;
        return `grid-template-columns: ${this.leftWidth}% ${d}px calc(100% - ${this.leftWidth}% - ${d}px); gap: 0;`;
    }

    get headerTitle() {
        return 'Project Email';
    }

    get selectedTemplatePreviewUrl() {
        if (!this.selectedTemplateId || !this.recordId) {
            return '';
        }
        const today = new Date();
        const month = String(today.getMonth() + 1).padStart(2, '0');
        const day = String(today.getDate()).padStart(2, '0');
        const year = today.getFullYear();
        const sendDate = this.isAnnualCertification ? `${month}-${day}-${year}` : `${year}-${month}-${day}`;
        const recordParam = this.isAnnualCertification ? 'recordId' : 'id';
        return `/apex/${this.selectedTemplateId}?${recordParam}=${this.recordId}&isPreview=true&senderId=${this.userData?.Id || ''}&sendDate=${sendDate}`;
    }

    get hasSelectedTemplate() {
        return !!this.selectedTemplateId;
    }

    @wire(getEmailSignature)
    wiredUser({ error, data }) {
        if (data) {
            this.userData = data;
        } else if (error) {
            console.error('getEmailSignature eError ==> ', error);
        }
    }

    connectedCallback() { 
        loadStyle(this, ModalPreviewWidth);
        this.loadOrgWideEmailAddresses();
    } 

    disconnectedCallback() {
        this.stopSplitDrag();
    }

    renderedCallback() {
        if (this.showSignaturePad) {
            this.initializeSignaturePad();
        }
    }

    // Initialization methods
    initializeComponent() {
        this.showSpinner = true;
        this.templatesLoaded = false;
        this.emailAddressesLoaded = false;
        this.defaultBodyLoaded = false;
        this.attachedTemplateLoaded = true;
        
        // this.fetchDefaultContacts();
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
                this.orgWideEmailOptions = result.map(addr => ({
                    displayName: addr.DisplayName,
                    emailAddress: addr.Address,
                    label: `${addr.DisplayName} <${addr.Address}>`,
                    value: addr.Id
                }));
   
                if (this.orgWideEmailOptions.length > 0) {
                    this.selectedFromAddress = this.orgWideEmailOptions[0].value;
                }
            })
            .catch(error => {
                this.logError('Error loading org-wide email addresses', error);
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
            this.emailSubject = (result && result.subject) ? result.subject : '';
            let emailBody = this.convertParagraphsToSpans(result ? result.htmlBody : '');
            emailBody = this.applyTemplateLink(emailBody, templateKey);

            this.emailBody = emailBody;
            this.emailEditBody = emailBody;

            const pendingName = this.pendingContactName || (this.toContactList && this.toContactList.length > 0 ? this.toContactList[0].Name : null);
            const didUpdate = this.applyContactNameToBody(pendingName);
            if (!didUpdate) {
                this.updateBodyPreview();
            }
        })
        .catch(error => {
            this.logError('Error loading default email body', error);
        })
        .finally(() => {
            this.defaultBodyLoaded = true;
            this.checkAllLoaded();
        });
    }

    convertParagraphsToSpans(body) {
        if (!body) {
            return '';
        }
        
        // Replace opening <p> tags (with or without attributes) with <div>
        let convertedHTML = body.replace(/<p([^>]*)>/gi, '<div$1>');
        
        // Replace closing </p> tags with </div><br>
        convertedHTML = convertedHTML.replace(/<\/p>/gi, '</div><br>');
        
        return convertedHTML;
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        this.updateSignatureState();
        this.loadDefaultEmailBody(this.selectedTemplateId);
    }

    handleFromAddressChange(event) {
        this.selectedFromAddress = event.detail.value;
    }

    handleToLookupChange(event) {
        const { selectedRecords } = event.detail;
        this.toContactList = this.createContactObj(selectedRecords);
        this.handleBtnEnable();

        const primaryName = this.toContactList.length > 0 ? this.toContactList[0].Name : null;
        const didUpdate = this.applyContactNameToBody(primaryName);
        if (!didUpdate) {
            this.updateBodyPreview();
        }
    }

    handleCCLookupChange(event) {
        const { selectedRecords } = event.detail;
        this.ccContactList = this.createContactObj(selectedRecords);
    }
    
    handleBCCLookupChange(event) {
        const { selectedRecords } = event.detail;
        this.bccContactList = this.createContactObj(selectedRecords);
    }

    handleCcCurrentUser(event) {
        let checked = event.target.checked;
        this.isCcCurrentUser = checked;
    }

    handleAdditionalEmailsChange(event) {
        this.additionalEmailsInput = event.target.value;
        this.processEmailInput(event.target.value);
    }

    handleRemoveAdditionalEmail(event) {
        const index = parseInt(event.detail.name);
        this.additionalEmailsList = this.additionalEmailsList.filter((_, i) => i != index);
        this.additionalEmailsInput = this.additionalEmailsList.join(', ');
    }

    processEmailInput(emailString) {
        if (!emailString) {
            this.additionalEmailsList = [];
            return;
        }

        const emails = emailString.split(',').map(email => email.trim()).filter(email => email);
        const validEmails = emails.filter(email => this.validateEmail(email));
        
        this.additionalEmailsList = validEmails;
    }

    validateEmail(email) {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailRegex.test(email);
    }

    handleSubjectChange(event) {
        this.emailSubject = event.target.value;
        this.handleBtnEnable();
    }

    handleBodyChange(event) {
        let htmlValue = event.detail.value;
        
        if (htmlValue) {
            htmlValue = htmlValue.replace(/<p><br><\/p>/g, '<br>');
            htmlValue = htmlValue.replace(/<p><span/g, '<div');
            htmlValue = htmlValue.replace(/<\/span><\/p>/g, '</div>');
            htmlValue = htmlValue.replace(/<p([^>]*)>/gi, '<div$1>');
            htmlValue = htmlValue.replace(/<\/p>/gi, '</div>');
        } else {
            htmlValue = '<div></div>';
        }
        
        this.emailBody = htmlValue;
        this.updateBodyPreview();
    }

    handleEmailSignatureChange(event) {
        let checked = event.target.checked;
        this.useEmailSignature = checked;
        let signature = this.userData.Signature;
        if (checked == true && (signature == null || signature == undefined || signature == '')) {
            this.showToast('No Email Signature Found', 'Please set up your email signature in Salesforce user settings.', 'Warning');
        }
    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        uploadedFiles.forEach(file => {
            this.attachedFiles = [...this.attachedFiles, {
                Id: file.documentId,
                name: file.name
            }];
        });
        this.showToast('Success', `${uploadedFiles.length} file(s) uploaded successfully`, 'success');
    }

    handleRemoveFile(event) {
        const fileId = event.detail.name;
        this.attachedFiles = this.attachedFiles.filter(file => file.Id != fileId);
    }

    setFirstTemplateAsDefault() {
        if (this.templateOptions.length > 0) {
            this.selectedTemplateId = this.templateOptions[0].value;
            this.updateSignatureState();
            this.loadDefaultEmailBody(this.selectedTemplateId);
        }
        this.templatesLoaded = true;
        this.checkAllLoaded();
    }

    get showSignaturePad() {
        return this.isSignatureRequired();
    }

    get isAnnualCertification() {
        return this.selectedTemplateId === 'AnnualCertification';
    }

    isSignatureRequired() {
        return this.selectedTemplateId === 'AnnualCertification';
    }

    updateSignatureState() {
        if (!this.isSignatureRequired()) {
            this.resetSignaturePad();
        }
        this.handleBtnEnable();
    }

    initializeSignaturePad() {
        const canvas = this.template.querySelector('.signature-pad');
        if (canvas && !this.signaturePadCanvas) {
            this.signaturePadCanvas = canvas;
            this.signatureContext = canvas.getContext('2d');
            this.signatureContext.strokeStyle = '#0070d2';
            this.signatureContext.lineWidth = 2;
            this.signatureContext.lineCap = 'round';
        }
    }

    startDrawing(event) {
        if (!this.signaturePadCanvas || !this.signatureContext) return;
        this.isDrawing = true;
        const rect = this.signaturePadCanvas.getBoundingClientRect();
        const x = (event.clientX || event.touches[0].clientX) - rect.left;
        const y = (event.clientY || event.touches[0].clientY) - rect.top;
        this.signatureContext.beginPath();
        this.signatureContext.moveTo(x, y);
    }

    draw(event) {
        if (!this.signaturePadCanvas || !this.signatureContext) return;
        if (!this.isDrawing) return;
        event.preventDefault();
        const rect = this.signaturePadCanvas.getBoundingClientRect();
        const x = (event.clientX || event.touches[0].clientX) - rect.left;
        const y = (event.clientY || event.touches[0].clientY) - rect.top;
        this.signatureContext.lineTo(x, y);
        this.signatureContext.stroke();
    }

    stopDrawing() {
        if (!this.signatureContext) return;
        this.isDrawing = false;
        this.signatureContext.beginPath();
        this.handleBtnEnable();
    }

    clearSignature() {
        if (!this.signaturePadCanvas || !this.signatureContext) return;
        this.signatureContext.clearRect(0, 0, this.signaturePadCanvas.width, this.signaturePadCanvas.height);
        this.handleBtnEnable();
    }

    resetSignaturePad() {
        if (this.signaturePadCanvas && this.signatureContext) {
            this.signatureContext.clearRect(0, 0, this.signaturePadCanvas.width, this.signaturePadCanvas.height);
        }
        this.signaturePadCanvas = null;
        this.signatureContext = null;
        this.signDocumentId = '';
    }

    hasSignature() {
        if (!this.signaturePadCanvas || !this.signatureContext) return false;
        const canvas = this.signaturePadCanvas;
        const ctx = this.signatureContext;
        const pixelData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        for (let i = 0; i < pixelData.data.length; i += 4) {
            if (pixelData.data[i + 3] != 0) {
                return true;
            }
        }
        return false;
    }

    applyTemplateLink(emailBody, templateKey) {
        if (!emailBody || !templateKey) {
            return emailBody;
        }
        return emailBody.replace(/\/[^\/?]+(?=\?id=)/, `/${templateKey}`);
    }

    updateBodyPreview() {
        const previewElement = this.template.querySelector('.email-body-preview');
        if (previewElement && this.emailBody) {
            previewElement.innerHTML = this.emailBody;
        }
        this.handleBtnEnable();
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

        this.pendingContactName = contactName;
        return false;
    }

    validateForm() {
        const errors = [];
        
        if (!this.selectedTemplateId) {
            errors.push('Please select an email template');
        }
        
        if (this.toContactList.length == 0) {
            errors.push('Please add at least one recipient');
        }
        
        if (this.emailSubject == undefined || !this.emailSubject.trim()) {
            errors.push('Please enter an email subject');
        }

        if (this.isBodyRequired) {
            let emailBody = this.emailBody;
            if (emailBody) {
                emailBody = emailBody.replace(/<[^>]*>/g, "");
            }
            if (emailBody == undefined || !emailBody.trim()) {
                errors.push('Please enter email content');
            }
        }

        if (this.isSignatureRequired() && !this.hasSignature()) {
            errors.push('Please add signature');
        }
        return errors;
    }

    handleBtnEnable() {
        this.isSendDisabled = this.validateForm().length > 0;
    }


    handleSendEmail() {
        this.showSpinner = true;  

        const validationErrors = this.validateForm();
        if (validationErrors.length > 0) {
            this.showToast('Validation Error', validationErrors.join(', '), 'error');
            this.showSpinner = false;
            return;
        }

        if (this.isSignatureRequired()) {
            this.saveSignatureAndSend();
        } else {
            this.sendEmailWithSignatureId('');
        }
    }

    saveSignatureAndSend() {
        if (!this.signaturePadCanvas) {
            this.showSpinner = false;
            this.showToast('Validation Error', 'Please add signature', 'error');
            return;
        }

        let signatureBase64Data = null;
        if (this.hasSignature()) {
            let signatureData = this.signaturePadCanvas.toDataURL();
            signatureBase64Data = signatureData.replace(/^data:image\/[a-z]+;base64,/, '');
        }

        const safeRecordId = this.isValidSfId(this.recordId) ? this.recordId : null;

        saveSignature({
            recordId: safeRecordId,
            signatureBase64Data: signatureBase64Data
        })
        .then(result => {
            const signatureId = result?.imgUrl || result?.cvId || '';
            this.signDocumentId = signatureId;
            this.sendEmailWithSignatureId(this.signDocumentId);
        })
        .catch(error => {
            this.logError('Error saving signature', error);
            this.showSpinner = false;
            this.showToast('Error', 'An unexpected error occurred while saving the signature', 'error');
        });
    }

    sendEmailWithSignatureId(signatureId) {
        const emailData = this.generateEmailDataWrap();
        emailData.htmlBody = this.addSignatureParamToBody(emailData.htmlBody, signatureId);
        emailData.htmlBody = this.addPreviewParamToBody(emailData.htmlBody, 'false');
        sendEmail({
            emailData: JSON.stringify(emailData)
        })
        .then(result => {
            if (result.isSuccess) {
                this.showToast('Success', 'Email sent successfully', 'success');
                this.closeModal();
            } else {
                this.logError('Email send failed', result);
                this.showSpinner = false;
                this.showToast('Error', result.errorMessage || 'Failed to send email', 'error');
            }
        })
        .catch(error => {
            this.logError('Error sending email', error);
            this.showSpinner = false;
            this.showToast('Error', 'An unexpected error occurred while sending the email', 'error');
        });
    }

    addSignatureParamToBody(body, signatureId) {
        if (!body || !signatureId || !this.isAnnualCertification) {
            return body;
        }

        return body.replace(/href="([^"]+)"/gi, (match, url) => {
            if (!/AnnualCertification/i.test(url)) {
                return match;
            }
            if (this.isUnsafeHref(url)) {
                return match;
            }
            const normalizedUrl = this.normalizeAnnualCertificationUrl(url);
            let updatedUrl = this.addOrReplaceUrlParam(normalizedUrl, 'PathStoneSignId', signatureId);
            return `href="${updatedUrl}"`;
        });
    }

    addPreviewParamToBody(body, value) {
        if (!body) {
            return body;
        }

        return body.replace(/href="([^"]+)"/gi, (match, url) => {
            if (this.isUnsafeHref(url)) {
                return match;
            }
            const normalizedUrl = this.normalizeAnnualCertificationUrl(url);
            const updatedUrl = this.addOrReplaceUrlParam(normalizedUrl, 'isPreview', value);
            return `href="${updatedUrl}"`;
        });
    }

    addOrReplaceUrlParam(url, key, value) {
        if (!url) {
            return url;
        }

        const encodedKey = encodeURIComponent(key);
        const encodedValue = encodeURIComponent(value);
        const pattern = new RegExp(`([?&])${encodedKey}=[^&]*`);

        if (pattern.test(url)) {
            return url.replace(pattern, `$1${encodedKey}=${encodedValue}`);
        }

        const separator = url.includes('?') ? '&' : '?';
        return `${url}${separator}${encodedKey}=${encodedValue}`;
    }

    normalizeAnnualCertificationUrl(url) {
        if (!/AnnualCertification/i.test(url)) {
            return url;
        }

        try {
            let normalized = url.replace(/(https?:\/\/[^\/]+)\/\/+apex\//i, '$1/apex/');
            const parts = normalized.split('?');
            if (parts.length < 2) {
                return normalized;
            }

            const base = parts[0];
            const query = parts.slice(1).join('?');
            const params = this.parseQueryParams(query);

            if (!params.recordId && params.id) {
                params.recordId = params.id;
                delete params.id;
            }

            if (params.sendDate) {
                const rawDate = params.sendDate;
                const dateOnly = rawDate ? rawDate.split(' ')[0] : rawDate;
                if (dateOnly && /^\d{4}-\d{2}-\d{2}$/.test(dateOnly)) {
                    const [year, month, day] = dateOnly.split('-');
                    params.sendDate = `${month}-${day}-${year}`;
                }
            }

            const updatedQuery = this.buildQueryParams(params);
            return updatedQuery ? `${base}?${updatedQuery}` : base;
        } catch (error) {
            this.logError('normalizeAnnualCertificationUrl failed', error);
            return url;
        }
    }

    parseQueryParams(query) {
        const params = {};
        if (!query) {
            return params;
        }
        query.split('&').forEach(pair => {
            if (!pair) return;
            const idx = pair.indexOf('=');
            const rawKey = idx >= 0 ? pair.slice(0, idx) : pair;
            const rawValue = idx >= 0 ? pair.slice(idx + 1) : '';
            const key = decodeURIComponent(rawKey || '');
            const value = decodeURIComponent(rawValue || '');
            if (key) {
                params[key] = value;
            }
        });
        return params;
    }

    buildQueryParams(params) {
        if (!params) {
            return '';
        }
        return Object.keys(params)
            .filter(key => key)
            .map(key => `${encodeURIComponent(key)}=${encodeURIComponent(params[key] ?? '')}`)
            .join('&');
    }

    isUnsafeHref(url) {
        if (!url) {
            return true;
        }
        const trimmed = url.trim();
        return /^(javascript:|mailto:|tel:|#)/i.test(trimmed);
    }

    isValidSfId(value) {
        if (!value || typeof value !== 'string') {
            return false;
        }
        return /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(value);
    }

    logError(message, error) {
        if (error !== undefined) {
            console.error(`[ProjectPreviewEmail] ${message}`, error);
        } else {
            console.error(`[ProjectPreviewEmail] ${message}`);
        }
    }

    generateEmailDataWrap() {
        const toContactIds = (this.toContactList ?? []).map(con => con?.Id);
        const uniqueToEmails = (this.toContactList ?? []).map(con => con?.Email);
        const uniqueCcEmails = (this.ccContactList ?? []).map(con => con?.Email);
        const uniqueBccEmails = (this.bccContactList ?? []).map(con => con?.Email);

        uniqueCcEmails.push(...this.additionalEmailsList);
        if (this.isCcCurrentUser == true) {
            uniqueCcEmails.push(this.userData.Email);
        }

        const fileIds = this.attachedFiles.map(file => file.Id);

        const emailData = {
            recordId: this.recordId,
            includeRefId: this.includeRefId,
            templateId: this.selectedTemplateId,
            fromAddress: this.selectedFromAddress,
            toContactIds: toContactIds,
            toEmails: uniqueToEmails,
            ccEmails: uniqueCcEmails,
            bccEmails: uniqueBccEmails,
            subject: this.emailSubject,
            htmlBody: this.emailBody,
            useEmailSignature: this.useEmailSignature,
            saveAsActivity: this.saveAsActivity,
            fileIds: fileIds
        };
        return emailData;
    }

    createContactObj (selectedRecords) {
        let contactList = [];
        selectedRecords.forEach(element => {
            let con = {
                Id: element.Id,
                Name: element.Name,
                Email: element.Email
            }
            contactList.push(con);
        });
        return contactList;
    }

    handleBodyToggle() {
        this.isBodyPreviewExpanded = !this.isBodyPreviewExpanded;
        if (this.isBodyPreviewExpanded) {
            setTimeout(() => {
                this.updateBodyPreview();
            }, 300);
        }
    }

    handleAttachmentToggle() {
        this.isProjectImprovementExpanded = !this.isProjectImprovementExpanded;
    }

    openRecordFileModal() {
        this.showSpinner = true;
        this.showRecordFileModal = true;
        this.tempSelectedFiles = [...this.attachedFiles];
        this.fetchRelatedFiles();
    }

    closeRelatedFileModal() {
        this.showRecordFileModal = false;
        this.tempSelectedFiles = [];
    }

    fetchRelatedFiles() {
        getRelatedFiles({
            recordId: this.recordId
        })
        .then(result => {
            if (result && result.length > 0) {
                let files = this.convertFileSizes(result);
                const selectedFileIds = this.attachedFiles.map(file => file.Id);
                
                files.forEach(function(file) {
                    file.isChecked = selectedFileIds.includes(file.ContentDocumentId);
                });

                this.relatedFileList = files;
            } else {
                this.closeRelatedFileModal();
                this.showToast('No Files Found', 'This record does not have any files', 'Warning');
            }
        })
        .catch(error => {
            console.error('Error loading related files:', error);
        })
        .finally(() => {
            this.showSpinner = false;
        });  
    }

    convertFileSizes(files) {
        for (var i = 0; i < files.length; i++) {
            var fileSize = files[i].ContentSize;
            files[i].FormattedSize = this.formatFileSize(fileSize);
        }
        return files;
    }

    formatFileSize(sizeInBytes) {
        if (isNaN(sizeInBytes) || sizeInBytes <= 0) {
            return 'N/A';
        }

        var units = ['B', 'KB', 'MB', 'GB', 'TB'];
        var i = parseInt(Math.floor(Math.log(sizeInBytes) / Math.log(1024)));
        return Math.round((sizeInBytes / Math.pow(1024, i)) * 100) / 100 + ' ' + units[i];
    }

    handleAllFileSelect(event) {
        let checked = event.target.checked;

        this.relatedFileList.forEach(element => {
            element.isChecked = checked;
        });
        
        let tempSelectedFiles = [];
        if (checked) {
            this.relatedFileList.forEach(file => {
                tempSelectedFiles = [...tempSelectedFiles, {
                    Id: file.ContentDocumentId,
                    name: file.Title
                }];
            });
        }
        this.tempSelectedFiles = tempSelectedFiles;
    }

    handleFileCheckboxChange(event) {
        let checked = event.target.checked;
        let fileId = event.target.dataset.id;

        if (checked) {
            let newAttachedFile = this.relatedFileList.find(file => file.ContentDocumentId == fileId);
            let newAttachedFileWrap = {
                Id: newAttachedFile.ContentDocumentId,
                name: newAttachedFile.Title
            };
            this.tempSelectedFiles.push(newAttachedFileWrap);
        } else {
            this.tempSelectedFiles = this.tempSelectedFiles.filter(file => file.Id != fileId);
        }
    }

    addSelectedFiles() {
        this.attachedFiles = [...this.tempSelectedFiles];
        this.closeRelatedFileModal();
    }

    /* ============================
       ADDED: Splitter Handlers
       ============================ */
    startSplitDrag = (e) => {
        e.preventDefault();
        this.splitDragging = true;
        this.template.host.classList.add('dragging');
        window.addEventListener('mousemove', this.onSplitMouseMove);
        window.addEventListener('mouseup', this.stopSplitDrag);
    }

    startSplitDragTouch = (e) => {
        e.preventDefault();
        this.splitDragging = true;
        this.template.host.classList.add('dragging');
        window.addEventListener('touchmove', this.onSplitTouchMove, { passive: false });
        window.addEventListener('touchend', this.stopSplitDrag);
    }

    onSplitMouseMove = (e) => {
        this.resizeSplitToClientX(e.clientX);
    }

    onSplitTouchMove = (e) => {
        if (e.touches && e.touches.length) {
            this.resizeSplitToClientX(e.touches[0].clientX);
            e.preventDefault();
        }
    }

    resizeSplitToClientX(clientX) {
        const container = this.template.querySelector('.email-composer-container');
        if (!container) return;
        const rect = container.getBoundingClientRect();
        let pct = ((clientX - rect.left) / rect.width) * 100;
        pct = Math.max(this.minPct, Math.min(this.maxPct, pct));
        this.leftWidth = Math.round(pct * 10) / 10; // small rounding to reduce churn
    }

    stopSplitDrag = () => {
        if (!this.splitDragging) return;
        this.splitDragging = false;
        this.template.host.classList.remove('dragging');
        window.removeEventListener('mousemove', this.onSplitMouseMove);
        window.removeEventListener('mouseup', this.stopSplitDrag);
        window.removeEventListener('touchmove', this.onSplitTouchMove);
        window.removeEventListener('touchend', this.stopSplitDrag);
    }

    onSplitKey = (e) => {
        const step = e.shiftKey ? 5 : 1;
        if (e.key == 'ArrowLeft') {
            this.leftWidth = Math.max(this.minPct, this.leftWidth - step);
            e.preventDefault();
        } else if (e.key == 'ArrowRight') {
            this.leftWidth = Math.min(this.maxPct, this.leftWidth + step);
            e.preventDefault();
        }
    }

    closeModal() {
        getRecordNotifyChange([{ recordId: this.recordId }]);
            
        setTimeout(() => {
            eval("$A.get('e.force:refreshView').fire();");
        }, 500);
        
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissible'
        }));
    }

}
