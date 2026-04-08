import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import ModalPreviewWidth from '@salesforce/resourceUrl/buildertek__ModalPreviewWidth85';
import getOrgWideEmailAddresses from '@salesforce/apex/RfqPreviewEmailCustomController.getOrgWideEmailAddresses';
import getEmailSignature from '@salesforce/apex/RfqPreviewEmailCustomController.getEmailSignature';
import getEmailBody from '@salesforce/apex/RfqPreviewEmailCustomController.getEmailBody';
import sendEmail from '@salesforce/apex/RfqPreviewEmailCustomController.sendEmail';

const DEFAULT_TEMPLATE_ID = 'ContractorSelectedForm';
const EMPTY_FROM_OPTION = {
    label: 'No org-wide email addresses available',
    value: ''
};

export default class RfqPreviewEmailCustom extends LightningElement {
    _recordId;

    templateOptions = [
        {
            label: 'Contractor Selected Form',
            value: DEFAULT_TEMPLATE_ID
        }
    ];

    orgWideEmailOptions = [EMPTY_FROM_OPTION];
    selectedTemplateId = DEFAULT_TEMPLATE_ID;
    selectedFromAddress = '';
    homeownerRecipients = [];
    programStaffSelection = [];
    ccRecipients = [];
    bccRecipients = [];
    additionalEmailsInput = '';
    additionalEmailsList = [];
    emailSubject = '';
    emailBody = '';
    emailEditorValue = '';
    useEmailSignature = false;
    isCcCurrentUser = false;
    isBodyPreviewExpanded = true;
    isTemplatePreviewExpanded = true;
    currentUser = {};
    isLoading = true;

    emailAddressesLoaded = false;
    templateLoaded = false;

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

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadSelectedTemplateBody();
        }
        this.syncLoadingState();
    }

    connectedCallback() {
        loadStyle(this, ModalPreviewWidth).catch(error => {
            this.logError('Unable to load modal width stylesheet', error);
        });
        this.loadOrgWideFromAddresses();
    }

    renderedCallback() {
        this.renderBodyPreview();
    }

    disconnectedCallback() {
        this.stopSplitDrag();
    }

    @wire(getEmailSignature)
    wiredCurrentUser({ error, data }) {
        if (data) {
            this.currentUser = data;
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

    get programStaffName() {
        return this.programStaffSelection.length === 1
            ? this.programStaffSelection[0].Name
            : 'No representative selected';
    }

    get programStaffEmailSnapshot() {
        return this.programStaffSelection.length === 1
            ? this.programStaffSelection[0].Email
            : 'This will populate after a Program Representative is selected.';
    }

    get sendButtonDisabled() {
        return this.isLoading || this.validateForm().length > 0;
    }

    get hasCurrentUserSignature() {
        return Boolean(this.currentUser?.Signature);
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

        return `/apex/ContractorSelectedForm?recordId=${this.recordId}`
            + `&isPreview=true`
            + `&senderId=${this.currentUser?.Id || ''}`
            + `&sendDate=${sendDate}`;
    }

    syncLoadingState() {
        const needsTemplateLoad = Boolean(this.recordId);
        this.isLoading = !(this.emailAddressesLoaded && (!needsTemplateLoad || this.templateLoaded));
    }

    loadOrgWideFromAddresses() {
        this.emailAddressesLoaded = false;
        this.syncLoadingState();

        getOrgWideEmailAddresses()
            .then(result => {
                const mappedOptions = (result || []).map(address => ({
                    label: `${address.DisplayName} <${address.Address}>`,
                    value: address.Id
                }));

                this.orgWideEmailOptions = mappedOptions.length > 0 ? mappedOptions : [EMPTY_FROM_OPTION];
                this.selectedFromAddress = mappedOptions.length > 0 ? mappedOptions[0].value : '';
            })
            .catch(error => {
                this.logError('Unable to load org-wide email addresses', error);
                this.orgWideEmailOptions = [EMPTY_FROM_OPTION];
                this.selectedFromAddress = '';
                this.showToast(
                    'Warning',
                    'Org-wide email addresses could not be loaded. The launcher will fall back to the running user if you continue.',
                    'warning'
                );
            })
            .finally(() => {
                this.emailAddressesLoaded = true;
                this.syncLoadingState();
            });
    }

    loadSelectedTemplateBody() {
        if (!this.recordId || !this.selectedTemplateId) {
            return;
        }

        this.templateLoaded = false;
        this.syncLoadingState();

        getEmailBody({
            recordId: this.recordId,
            vfApiName: this.selectedTemplateId
        })
            .then(result => {
                this.emailSubject = result?.subject || '';
                const emailBody = this.normalizeRichText(result?.htmlBody || '');
                this.emailBody = emailBody;
                this.emailEditorValue = emailBody;

                const primaryHomeownerName = this.homeownerRecipients.length > 0
                    ? this.homeownerRecipients[0].Name
                    : null;
                this.applyContactNameToBody(primaryHomeownerName);
                this.renderBodyPreview();
            })
            .catch(error => {
                this.logError('Unable to load email template body', error);
                this.emailSubject = '';
                this.emailBody = '';
                this.emailEditorValue = '';
                this.showToast(
                    'Error',
                    'The Contractor Selected Form template could not be loaded. Deploy the template metadata and verify it exists in Salesforce.',
                    'error'
                );
            })
            .finally(() => {
                this.templateLoaded = true;
                this.syncLoadingState();
            });
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        this.loadSelectedTemplateBody();
    }

    handleFromAddressChange(event) {
        this.selectedFromAddress = event.detail.value;
    }

    handleHomeownerLookupChange(event) {
        const detail = event.detail || {};
        this.homeownerRecipients = this.createContactList(detail.selectedRecords || []);
        const primaryHomeownerName = this.homeownerRecipients.length > 0 ? this.homeownerRecipients[0].Name : null;
        this.applyContactNameToBody(primaryHomeownerName);
    }

    handleProgramStaffLookupChange(event) {
        const detail = event.detail || {};
        const selectedRecords = detail.selectedRecords
            ? detail.selectedRecords
            : (detail.selectedRecord ? [detail.selectedRecord] : []);
        this.programStaffSelection = this.createContactList(selectedRecords);
    }

    handleCCLookupChange(event) {
        const detail = event.detail || {};
        this.ccRecipients = this.createContactList(detail.selectedRecords || []);
    }

    handleBCCLookupChange(event) {
        const detail = event.detail || {};
        this.bccRecipients = this.createContactList(detail.selectedRecords || []);
    }

    handleCcCurrentUser(event) {
        this.isCcCurrentUser = event.target.checked;
    }

    handleAdditionalEmailsChange(event) {
        this.additionalEmailsInput = event.target.value;
        this.additionalEmailsList = this.parseAdditionalEmails(event.target.value);
    }

    handleRemoveAdditionalEmail(event) {
        const index = Number(event.detail.name);
        this.additionalEmailsList = this.additionalEmailsList.filter((_, itemIndex) => itemIndex !== index);
        this.additionalEmailsInput = this.additionalEmailsList.join(', ');
    }

    handleSubjectChange(event) {
        this.emailSubject = event.target.value;
    }

    handleBodyChange(event) {
        const htmlValue = this.normalizeRichText(event.detail.value || '');
        this.emailBody = htmlValue;
        this.emailEditorValue = htmlValue;
        this.renderBodyPreview();
    }

    handleEmailSignatureChange(event) {
        this.useEmailSignature = event.target.checked;

        if (this.useEmailSignature && !this.currentUser?.Signature) {
            this.showToast(
                'No Email Signature Found',
                'Set up your Salesforce email signature before relying on the signature preview.',
                'warning'
            );
        }
    }

    handleSendEmail() {
        const validationErrors = this.validateForm();
        if (validationErrors.length > 0) {
            this.showToast('Validation Error', validationErrors.join(' '), 'error');
            return;
        }

        this.isLoading = true;

        const emailData = this.generateEmailDataWrap();
        emailData.htmlBody = this.prepareEmailBodyForSend();

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
                this.isLoading = false;
            });
    }

    renderBodyPreview() {
        const previewElement = this.template.querySelector('.email-body-preview');
        if (!previewElement) {
            return;
        }

        previewElement.innerHTML = this.emailBody
            ? this.emailBody
            : '<div class="empty-preview">Email body preview appears here as you type.</div>';
    }

    normalizeRichText(value) {
        if (!value) {
            return '';
        }

        return value;
    }

    applyContactNameToBody(contactName) {
        if (!this.emailBody) {
            return;
        }

        const replacementName = contactName || this.contactNamePlaceholder;
        let updatedBody = this.emailBody;

        if (updatedBody.includes(this.lastSelectedContactName)) {
            updatedBody = updatedBody.replace(this.lastSelectedContactName, replacementName);
        } else if (updatedBody.includes(this.contactNamePlaceholder)) {
            updatedBody = updatedBody.replace(this.contactNamePlaceholder, replacementName);
        }

        this.lastSelectedContactName = replacementName;
        this.emailBody = updatedBody;
        this.emailEditorValue = updatedBody;
        this.renderBodyPreview();
    }

    parseAdditionalEmails(rawValue) {
        if (!rawValue) {
            return [];
        }

        return rawValue
            .split(',')
            .map(email => email.trim())
            .filter(email => email)
            .filter(email => this.isValidEmail(email));
    }

    isValidEmail(email) {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailRegex.test(email);
    }

    validateForm() {
        const errors = [];

        if (!this.selectedTemplateId) {
            errors.push('Select a template.');
        }

        if (this.homeownerRecipients.length === 0) {
            errors.push('Add at least one homeowner recipient.');
        }

        if (this.programStaffSelection.length !== 1) {
            errors.push('Select one Program Representative.');
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

    prepareEmailBodyForSend() {
        let body = this.emailBody;
        body = this.addPreviewParamToBody(body, 'false');
        const selectedRepresentative = this.programStaffSelection[0];

        if (this.selectedFromAddress) {
            body = this.addBodyUrlParam(body, 'fromAddressId', this.selectedFromAddress);
        }

        if (selectedRepresentative?.Id) {
            body = this.addBodyUrlParam(body, 'programRepresentativeContactId', selectedRepresentative.Id);
        }

        if (selectedRepresentative?.Name) {
            body = this.addBodyUrlParam(body, 'programRepresentativeName', selectedRepresentative.Name);
        }

        if (selectedRepresentative?.Email) {
            body = this.addBodyUrlParam(body, 'programRepresentativeEmail', selectedRepresentative.Email);
        }

        return body;
    }

    addBodyUrlParam(body, key, value) {
        if (!body || !value) {
            return body;
        }

        return body.replace(/href="([^"]+)"/gi, (match, url) => {
            if (this.isUnsafeHref(url)) {
                return match;
            }

            const updatedUrl = this.addOrReplaceUrlParam(url, key, value);
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

            const updatedUrl = this.addOrReplaceUrlParam(url, 'isPreview', value);
            return `href="${updatedUrl}"`;
        });
    }

    addOrReplaceUrlParam(url, key, value) {
        const encodedKey = encodeURIComponent(key);
        const encodedValue = encodeURIComponent(value);
        const pattern = new RegExp(`([?&])${encodedKey}=[^&]*`);

        if (pattern.test(url)) {
            return url.replace(pattern, `$1${encodedKey}=${encodedValue}`);
        }

        const separator = url.includes('?') ? '&' : '?';
        return `${url}${separator}${encodedKey}=${encodedValue}`;
    }

    isUnsafeHref(url) {
        if (!url) {
            return true;
        }

        return /^(javascript:|mailto:|tel:|#)/i.test(url.trim());
    }

    generateEmailDataWrap() {
        const ccEmails = [
            ...this.ccRecipients.map(contact => contact.Email),
            ...this.additionalEmailsList
        ];

        if (this.isCcCurrentUser && this.currentUser?.Email) {
            ccEmails.push(this.currentUser.Email);
        }

        return {
            recordId: this.recordId,
            includeRefId: false,
            templateId: this.selectedTemplateId,
            fromAddress: this.selectedFromAddress,
            toContactIds: this.homeownerRecipients.map(contact => contact.Id),
            toEmails: this.homeownerRecipients.map(contact => contact.Email),
            ccEmails,
            bccEmails: this.bccRecipients.map(contact => contact.Email),
            subject: this.emailSubject,
            htmlBody: this.emailBody,
            useEmailSignature: this.useEmailSignature,
            saveAsActivity: false,
            programRepresentativeContactId: this.programStaffSelection[0]?.Id || '',
            programRepresentativeName: this.programStaffSelection[0]?.Name || '',
            programRepresentativeEmail: this.programStaffSelection[0]?.Email || ''
        };
    }

    createContactList(selectedRecords) {
        return (selectedRecords || []).map(record => ({
            Id: record.Id,
            Name: record.Name,
            Email: record.Email
        }));
    }

    handleBodyToggle() {
        this.isBodyPreviewExpanded = !this.isBodyPreviewExpanded;
        if (this.isBodyPreviewExpanded) {
            setTimeout(() => this.renderBodyPreview(), 0);
        }
    }

    handleTemplatePreviewToggle() {
        this.isTemplatePreviewExpanded = !this.isTemplatePreviewExpanded;
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
        if (this.recordId) {
            getRecordNotifyChange([{ recordId: this.recordId }]);
        }

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
            console.error(`[RfqPreviewEmailCustom] ${message}`, error);
        } else {
            // eslint-disable-next-line no-console
            console.error(`[RfqPreviewEmailCustom] ${message}`);
        }
    }
}