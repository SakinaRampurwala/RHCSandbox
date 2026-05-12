import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getLogoUrl from '@salesforce/apex/NoticeToProceedCtrl.getLogoUrl';
import getNoticeData from '@salesforce/apex/NoticeToProceedCtrl.getNoticeData';
import saveSignature from '@salesforce/apex/NoticeToProceedCtrl.saveSignature';
import savePdf from '@salesforce/apex/NoticeToProceedCtrl.savePdf';

export default class NoticeToProceedLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    @track isLoading = true;
    @track isSubmitted = false;
    @track isAlreadySubmitted = false;
    @track stageLocked = false;
    @track submissionStatus = '';
    @track logoURL;
    @track noticeData = {};
    @track showCustomToast = false;
    @track customToastMessage = '';
    @track customToastVariant = 'success';
    noticeWireResult;

    // Role flags — read from URL params
    @track isPropertyOwner = false;
    @track isContractorRep = false;
    @track isProgramRep = false;

    // Chain email params — read from URL, passed to Apex savePdf which handles sending
    contractorRepContactIds = [];
    contractorRepEmails = [];
    programRepContactIds = [];
    programRepEmails = [];
    fromAddressId = '';
    fileIds = [];

    // Signature state from saved record
    @track propertyOwnerSignatureUrl = '';
    @track contractorRepSignatureUrl = '';
    @track programRepSignatureUrl = '';
    @track propertyOwnerSigned = false;
    @track contractorRepSigned = false;
    @track programRepSigned = false;

    // Canvas state
    canvasMap = {};
    ctxMap = {};
    isDrawing = false;
    activeSignatureId;
    signatureState = { propertyOwner: false, contractorRep: false, programRep: false };

    @wire(getLogoUrl)
    wiredLogo({ data }) {
        if (data) { this.logoURL = data; }
    }

    @wire(getNoticeData, { recordId: '$recordId' })
    wiredNoticeData(result) {
        this.noticeWireResult = result;
        const { data } = result;
        if (data) {
            this.noticeData = {
                ...this.noticeData,
                ...data
            };
            this.isSubmitted = !!data.isSubmitted;
            this.isAlreadySubmitted = !!data.isSubmitted;
            this.propertyOwnerSignatureUrl = data.propertyOwnerSignatureUrl || '';
            this.contractorRepSignatureUrl = data.contractorRepSignatureUrl || '';
            this.programRepSignatureUrl    = data.programRepSignatureUrl    || '';
            this.propertyOwnerSigned = !!data.propertyOwnerSigned;
            this.contractorRepSigned = !!data.contractorRepSigned;
            this.programRepSigned    = !!data.programRepSigned;
            this.signatureState = {
                propertyOwner: this.propertyOwnerSigned || !!this.propertyOwnerSignatureUrl,
                contractorRep: this.contractorRepSigned || !!this.contractorRepSignatureUrl,
                programRep:    this.programRepSigned    || !!this.programRepSignatureUrl
            };
            this.applySubmissionState(data);
        }
        this.isLoading = false;
    }

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);

        // Read role from URL
        this.isPropertyOwner = params.get('isPropertyOwner') === 'true';
        this.isContractorRep = params.get('isContractorRep') === 'true';
        this.isProgramRep    = params.get('isProgramRep')    === 'true';

        // Fallback: read core params from URL if @api props not yet set by VF page
        if (!this.recordId) { this.recordId = params.get('recordId') || params.get('id') || ''; }
        if (!this.senderId) { this.senderId = params.get('senderId') || ''; }
        if (!this.sendDate) { this.sendDate = params.get('sendDate') || ''; }

        // Chain email params — passed to Apex savePdf so it can send the next email server-side
        const cIds = params.get('contractorRepContactIds');
        const cEmails = params.get('contractorRepEmails');
        const pIds = params.get('programRepContactIds');
        const pEmails = params.get('programRepEmails');
        const fIds = params.get('fileIds');

        this.contractorRepContactIds = cIds    ? cIds.split(',').filter(Boolean)    : [];
        this.contractorRepEmails     = cEmails ? cEmails.split(',').filter(Boolean) : [];
        this.programRepContactIds    = pIds    ? pIds.split(',').filter(Boolean)    : [];
        this.programRepEmails        = pEmails ? pEmails.split(',').filter(Boolean) : [];
        this.fromAddressId           = params.get('fromAddressId') || '';
        this.fileIds                 = fIds    ? fIds.split(',').filter(Boolean)    : [];

        if (!this.recordId) { this.isLoading = false; }
    }

    // ── Section visibility ──────────────────────────────────────────────────────

    get showPropertyOwnerSection() {
        if (!this.isRoleDrivenView || this.isSubmitted || this.isPreviewMode) return true;
        if (this.isPropertyOwner) return true;
        return this.propertyOwnerSigned;
    }

    get showContractorRepSection() {
        if (!this.isRoleDrivenView || this.isSubmitted || this.isPreviewMode) return true;
        if (this.isPropertyOwner) return this.contractorRepSigned;
        if (this.isContractorRep) return true;
        if (this.isProgramRep) return this.contractorRepSigned;
        return false;
    }

    get showProgramRepSection() {
        if (!this.isRoleDrivenView || this.isSubmitted || this.isPreviewMode) return true;
        if (this.isProgramRep) return true;
        return this.programRepSigned;
    }

    // ── Computed getters ────────────────────────────────────────────────────────

    get isReadOnly() {
        return this.isPreviewMode || this.isSubmitted || this.stageLocked;
    }

    get signatureCanvasClass() {
        return `signature-pad${this.isReadOnly ? ' read-only' : ''}`;
    }

    get hasPropertyOwnerSignature() { return this.propertyOwnerSigned || !!this.propertyOwnerSignatureUrl; }
    get hasContractorRepSignature()  { return this.contractorRepSigned || !!this.contractorRepSignatureUrl; }
    get hasProgramRepSignature()     { return this.programRepSigned    || !!this.programRepSignatureUrl; }

    get isSubmitDisabled() {
        if (this.isReadOnly) return true;
        if (this.isPropertyOwner) return !this.signatureState.propertyOwner && !this.hasPropertyOwnerSignature;
        if (this.isContractorRep) return !this.signatureState.contractorRep && !this.hasContractorRepSignature;
        if (this.isProgramRep)    return !this.signatureState.programRep    && !this.hasProgramRepSignature;
        // Admin view — require all 3
        return (
            (!this.signatureState.propertyOwner && !this.hasPropertyOwnerSignature) ||
            (!this.signatureState.contractorRep && !this.hasContractorRepSignature) ||
            (!this.signatureState.programRep    && !this.hasProgramRepSignature)
        );
    }

    // ── Current signer role string (sent to Apex so it knows who just signed) ──
    get currentSignerRole() {
        if (this.isPropertyOwner) return 'isPropertyOwner';
        if (this.isContractorRep) return 'isContractorRep';
        if (this.isProgramRep)    return 'isProgramRep';
        return '';
    }

    get isPreviewMode() {
        return this.isPreview === true || this.isPreview === 'true';
    }

    get isRoleDrivenView() {
        return this.isPropertyOwner || this.isContractorRep || this.isProgramRep;
    }

    get showSubmittedMessage() {
        return !!this.submissionStatus;
    }

    get submittedMessage() {
        if (this.submissionStatus === 'already') {
            return 'Notice To Proceed has already been submitted for this record.';
        }
        if (this.submissionStatus === 'final') {
            return 'Notice To Proceed has been submitted successfully.';
        }
        if (this.submissionStatus === 'partial') {
            return 'Your signature has been submitted. The next signer has been notified.';
        }
        return '';
    }

    get customToastClass() {
        return `custom-toast custom-toast_${this.customToastVariant}`;
    }

    // ── Canvas / drawing ───────────────────────────────────────────────────────

    renderedCallback() {
        const canvases = this.template.querySelectorAll('canvas');
        if (!canvases || canvases.length === 0) return;
        canvases.forEach((canvas) => {
            const signatureId = canvas.dataset.signatureId;
            if (!signatureId || this.canvasMap[signatureId]) return;
            this.canvasMap[signatureId] = canvas;
            const ctx = canvas.getContext('2d');
            this.ctxMap[signatureId] = ctx;
            this.setCanvasSize(canvas, ctx);
        });
    }

    setCanvasSize(canvas, ctx) {
        canvas.width = canvas.offsetWidth;
        canvas.height = canvas.offsetHeight;
        ctx.lineWidth = 2;
        ctx.lineCap = 'round';
        ctx.strokeStyle = '#000';
    }

    handleMouseDown(event) {
        if (this.isReadOnly) return;
        const signatureId = event.target?.dataset?.signatureId;
        if (!signatureId || !this.ctxMap[signatureId]) return;
        this.isDrawing = true;
        this.activeSignatureId = signatureId;
        this.signatureState = { ...this.signatureState, [signatureId]: true };
        const canvas = this.canvasMap[signatureId];
        const ctx = this.ctxMap[signatureId];
        const { offsetX, offsetY } = this.getCoordinates(event, canvas);
        ctx.beginPath();
        ctx.moveTo(offsetX, offsetY);
    }

    handleMouseMove(event) {
        if (!this.isDrawing || this.isReadOnly) return;
        const signatureId = this.activeSignatureId;
        if (!signatureId || !this.ctxMap[signatureId]) return;
        const canvas = this.canvasMap[signatureId];
        const ctx = this.ctxMap[signatureId];
        const { offsetX, offsetY } = this.getCoordinates(event, canvas);
        ctx.lineTo(offsetX, offsetY);
        ctx.stroke();
    }

    handleMouseUp(event) {
        this.isDrawing = false;
        const signatureId = event?.target?.dataset?.signatureId || this.activeSignatureId;
        if (signatureId && this.canvasMap[signatureId]) {
            const hasSignature = this.hasSignatureOnCanvas(this.canvasMap[signatureId]);
            this.signatureState = { ...this.signatureState, [signatureId]: hasSignature };
        }
        this.activeSignatureId = null;
    }

    handleTouchStart(event) {
        if (this.isReadOnly) return;
        event.preventDefault();
        const touch = event.touches[0];
        event.target.dispatchEvent(new MouseEvent('mousedown', { clientX: touch.clientX, clientY: touch.clientY }));
    }

    handleTouchMove(event) {
        event.preventDefault();
        const touch = event.touches[0];
        event.target.dispatchEvent(new MouseEvent('mousemove', { clientX: touch.clientX, clientY: touch.clientY }));
    }

    handleTouchEnd(event) {
        event.preventDefault();
        event.target.dispatchEvent(new MouseEvent('mouseup', {}));
    }

    getCoordinates(event, canvas) {
        const rect = canvas.getBoundingClientRect();
        const clientX = event.clientX || event.touches?.[0].clientX;
        const clientY = event.clientY || event.touches?.[0].clientY;
        return { offsetX: clientX - rect.left, offsetY: clientY - rect.top };
    }

    clearSignature(event) {
        if (this.isReadOnly) return;
        const signatureId = event.target?.dataset?.signatureId;
        if (!signatureId || !this.canvasMap[signatureId] || !this.ctxMap[signatureId]) return;
        const canvas = this.canvasMap[signatureId];
        const ctx = this.ctxMap[signatureId];
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        this.signatureState = { ...this.signatureState, [signatureId]: false };
    }

    hasSignatureOnCanvas(canvas) {
        if (!canvas) return false;
        const ctx = canvas.getContext('2d');
        if (!ctx) return false;
        const pixelData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        for (let i = 3; i < pixelData.data.length; i += 4) {
            if (pixelData.data[i] !== 0) return true;
        }
        return false;
    }

    // ── Submit ─────────────────────────────────────────────────────────────────

    handleSubmit() {
        if (this.isReadOnly) return;

        const signaturePromises = [];
        const signatureResults = {};

        const collectSignature = (signatureId, label, existingUrl, warningMsg) => {
            const canvas = this.canvasMap[signatureId];
            if (canvas && this.hasSignatureOnCanvas(canvas)) {
                const signatureBody = canvas.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, '');
                signaturePromises.push(
                    saveSignature({ recordId: this.recordId, signatureBody, signatureLabel: label })
                        .then((result) => { signatureResults[signatureId] = result; })
                );
                return true;
            }
            if (existingUrl) {
                signatureResults[signatureId] = { imgUrl: existingUrl, cvId: '' };
                return true;
            }
            this.showToast(warningMsg, 'info');
            return false;
        };

        // Collect only the current signer's section
        if (this.isPropertyOwner || (!this.isPropertyOwner && !this.isContractorRep && !this.isProgramRep)) {
            if (!collectSignature('propertyOwner', 'Property Owner', this.propertyOwnerSignatureUrl,
                'Please provide the Property Owner signature before submitting.')) return;
        }
        if (this.isContractorRep || (!this.isPropertyOwner && !this.isContractorRep && !this.isProgramRep)) {
            if (!collectSignature('contractorRep', 'Contractor Representative', this.contractorRepSignatureUrl,
                'Please provide the Contractor Representative signature before submitting.')) return;
        }
        if (this.isProgramRep || (!this.isPropertyOwner && !this.isContractorRep && !this.isProgramRep)) {
            if (!collectSignature('programRep', 'Home Improvement Program Representative', this.programRepSignatureUrl,
                'Please provide the Program Representative signature before submitting.')) return;
        }

        this.isLoading = true;

        Promise.all(signaturePromises)
            .then(() => {
                // Pass ALL chain email params to Apex — it handles sending the next email internally
                return savePdf({
                    recordId:                 this.recordId,
                    senderId:                 this.senderId  || '',
                    sendDate:                 this.sendDate  || '',
                    propertyOwnerImgUrl:      signatureResults.propertyOwner?.imgUrl || this.propertyOwnerSignatureUrl || '',
                    contractorRepImgUrl:      signatureResults.contractorRep?.imgUrl || this.contractorRepSignatureUrl || '',
                    programRepImgUrl:         signatureResults.programRep?.imgUrl    || this.programRepSignatureUrl    || '',
                    propertyOwnerSignatureId: signatureResults.propertyOwner?.cvId   || '',
                    contractorRepSignatureId: signatureResults.contractorRep?.cvId   || '',
                    programRepSignatureId:    signatureResults.programRep?.cvId      || '',
                    // Chain params — Apex will send next signer email using these
                    currentSignerRole:        this.currentSignerRole,
                    contractorRepContactIds:  this.contractorRepContactIds,
                    contractorRepEmails:      this.contractorRepEmails,
                    programRepContactIds:     this.programRepContactIds,
                    programRepEmails:         this.programRepEmails,
                    fromAddressId:            this.fromAddressId || '',
                    fileIds:                  this.fileIds
                });
            })
            .then((result) => {
                if (result === 'Success') {
                    this.submissionStatus = 'final';
                    return this.refreshNoticeData().then(() => {
                        this.showToast('Notice To Proceed submitted.', 'success');
                    });
                }
                if (result === 'Already Submitted') {
                    this.submissionStatus = 'already';
                    return this.refreshNoticeData().then(() => {
                        this.showToast('This form has already been submitted.', 'info');
                    });
                }
                if (result === 'Missing Signatures') {
                    this.submissionStatus = 'partial';
                    return this.refreshNoticeData().then(() => {
                        this.showToast('Signature saved. The next recipient has been notified.', 'success');
                    });
                }
                return null;
            })
            .catch((error) => {
                this.showToast(error?.body?.message || error?.message || 'An unknown error occurred.', 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    applySubmissionState(data) {
        if (this.isPreviewMode) {
            this.stageLocked = true;
            this.submissionStatus = data.isSubmitted ? 'final' : '';
            return;
        }

        if (data.isSubmitted) {
            this.isSubmitted = true;
            this.isAlreadySubmitted = true;
            this.stageLocked = false;
            this.submissionStatus = this.submissionStatus === 'final' ? 'final' : 'already';
            return;
        }

        const roleSigned =
            (this.isPropertyOwner && data.propertyOwnerSigned) ||
            (this.isContractorRep && data.contractorRepSigned) ||
            (this.isProgramRep && data.programRepSigned);

        this.stageLocked = this.isRoleDrivenView && roleSigned;
        this.submissionStatus = this.stageLocked ? 'partial' : '';
        this.isAlreadySubmitted = false;
    }

    refreshNoticeData() {
        if (!this.noticeWireResult) {
            return Promise.resolve();
        }
        return refreshApex(this.noticeWireResult);
    }

    showToast(message, variant = 'success') {
        this.customToastMessage = message;
        this.customToastVariant = variant;
        this.showCustomToast = true;
    }

    handleCloseToast() {
        this.showCustomToast = false;
    }
}