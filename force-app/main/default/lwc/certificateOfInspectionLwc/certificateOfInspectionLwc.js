import { LightningElement, api, track } from 'lwc';
import CompanyLogo from '@salesforce/resourceUrl/buildertek__Company_Logo';
import getLogoUrl from '@salesforce/apex/CertificateOfInspectionCtrl.getLogoUrl';
import getCertificateData from '@salesforce/apex/CertificateOfInspectionCtrl.getCertificateData';
import saveSignature from '@salesforce/apex/CertificateOfInspectionCtrl.saveSignature';
import savePdf from '@salesforce/apex/CertificateOfInspectionCtrl.savePdf';

export default class CertificateOfInspectionLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    @track isLoading = true;
    @track isSubmitted = false;
    @track isAlreadySubmitted = false;
    @track logoURL = CompanyLogo;
    @track showCustomToast = false;
    @track customToastMessage = '';
    @track customToastVariant = 'success';
    @track certificateData = {
        inspectionDate: '',
        contractor: '',
        projectAddress: ''
    };

    @track isContractor = false;
    @track isHomeowner = false;
    @track isHomsiteRep = false;
    @track isCodeEnforcement = false;

    @track contractorSignatureUrl = '';
    @track homeownerSignatureUrl = '';
    @track homsiteRepSignatureUrl = '';
    @track codeEnforcementSignatureUrl = '';
    @track contractorSigned = false;
    @track homeownerSigned = false;
    @track homsiteRepSigned = false;
    @track codeEnforcementSigned = false;

    homeownerContactIds = [];
    homeownerEmails = [];
    homsiteRepContactIds = [];
    homsiteRepEmails = [];
    codeEnforcementContactIds = [];
    codeEnforcementEmails = [];
    fromAddressId = '';
    fileIds = [];

    canvasMap = {};
    ctxMap = {};
    isDrawing = false;
    activeSignatureId;
    signatureOrder = ['contractor', 'homeowner', 'homsiteRep', 'codeEnforcement'];
    signatureState = {
        contractor: false,
        homeowner: false,
        homsiteRep: false,
        codeEnforcement: false
    };
    toastTimeout;
    submissionStatus = '';
    stageLocked = false;

    connectedCallback() {
        this.initializePageContext();
        if (!this.recordId) {
            this.isLoading = false;
            return;
        }
        this.loadFormData();
    }

    disconnectedCallback() {
        window.clearTimeout(this.toastTimeout);
    }

    initializePageContext() {
        const params = new URLSearchParams(window.location.search);
        this.isContractor = params.get('isContractor') === 'true';
        this.isHomeowner = params.get('isHomeowner') === 'true';
        this.isHomsiteRep = params.get('isHomsiteRep') === 'true';
        this.isCodeEnforcement = params.get('isCodeEnforcement') === 'true';

        if (!this.recordId) {
            this.recordId = params.get('recordId') || params.get('id') || '';
        }
        if (!this.senderId) {
            this.senderId = params.get('senderId') || '';
        }
        if (!this.sendDate) {
            this.sendDate = params.get('sendDate') || '';
        }

        this.homeownerContactIds = this.parseCsvParam(params.get('homeownerContactIds'));
        this.homeownerEmails = this.parseCsvParam(params.get('homeownerEmails'));
        this.homsiteRepContactIds = this.parseCsvParam(params.get('homsiteRepContactIds'));
        this.homsiteRepEmails = this.parseCsvParam(params.get('homsiteRepEmails'));
        this.codeEnforcementContactIds = this.parseCsvParam(params.get('codeEnforcementContactIds'));
        this.codeEnforcementEmails = this.parseCsvParam(params.get('codeEnforcementEmails'));
        this.fileIds = this.parseCsvParam(params.get('fileIds'));
        this.fromAddressId = params.get('fromAddressId') || '';
    }

    async loadFormData() {
        this.isLoading = true;
        const [logoResult, dataResult] = await Promise.allSettled([
            getLogoUrl(),
            getCertificateData({ recordId: this.recordId })
        ]);

        if (logoResult.status === 'fulfilled' && logoResult.value) {
            this.logoURL = logoResult.value;
        } else {
            this.logoURL = CompanyLogo;
        }

        if (dataResult.status === 'fulfilled') {
            this.applyCertificateData(dataResult.value);
        } else {
            this.showToast(
                dataResult.reason?.body?.message || dataResult.reason?.message || 'Failed to load certificate data.',
                'error'
            );
        }

        this.isLoading = false;
    }

    applyCertificateData(data) {
        if (data) {
            this.certificateData = {
                inspectionDate: data.inspectionDate || '',
                contractor: data.contractor || '',
                projectAddress: data.projectAddress || ''
            };
            this.contractorSignatureUrl = data.contractorSignatureUrl || this.contractorSignatureUrl || '';
            this.homeownerSignatureUrl = data.homeownerSignatureUrl || this.homeownerSignatureUrl || '';
            this.homsiteRepSignatureUrl = data.homsiteRepSignatureUrl || this.homsiteRepSignatureUrl || '';
            this.codeEnforcementSignatureUrl = data.codeEnforcementSignatureUrl || this.codeEnforcementSignatureUrl || '';
            this.contractorSigned = !!data.contractorSigned || this.contractorSigned;
            this.homeownerSigned = !!data.homeownerSigned || this.homeownerSigned;
            this.homsiteRepSigned = !!data.homsiteRepSigned || this.homsiteRepSigned;
            this.codeEnforcementSigned = !!data.codeEnforcementSigned || this.codeEnforcementSigned;
            this.signatureState = {
                contractor: this.hasContractorSignature,
                homeowner: this.hasHomeownerSignature,
                homsiteRep: this.hasHomsiteRepSignature,
                codeEnforcement: this.hasCodeEnforcementSignature
            };
            if (!this.isPreviewMode) {
                if (data.isSubmitted) {
                    this.isSubmitted = true;
                    this.isAlreadySubmitted = true;
                    this.submissionStatus = 'already';
                    this.stageLocked = false;
                } else if (this.currentRoleAlreadySigned) {
                    this.isSubmitted = false;
                    this.isAlreadySubmitted = false;
                    this.submissionStatus = 'partial';
                    this.stageLocked = true;
                } else {
                    this.isSubmitted = false;
                    this.isAlreadySubmitted = false;
                    this.submissionStatus = '';
                    this.stageLocked = false;
                }
            }
        }
    }

    parseCsvParam(value) {
        if (!value) {
            return [];
        }
        return value
            .split(',')
            .map((item) => decodeURIComponent(item).trim())
            .filter((item) => item);
    }

    get isPreviewMode() {
        return this.isPreview === true || this.isPreview === 'true';
    }

    get isReadOnly() {
        if (this.isPreviewMode || !this.currentSignerRole) {
            return true;
        }
        return this.isSubmitted || this.stageLocked;
    }

    get showSubmittedMessage() {
        return !this.isPreviewMode && (this.isSubmitted || this.stageLocked);
    }

    get submittedMessage() {
        if (this.isAlreadySubmitted || this.submissionStatus === 'already') {
            return 'Certificate Of Inspection has already been submitted for this record.';
        }
        if (this.submissionStatus === 'partial') {
            return 'Your signature has been saved. The next recipient has been notified to sign.';
        }
        return 'Certificate Of Inspection has been submitted successfully.';
    }

    get currentSignerRole() {
        if (this.isContractor) {
            return 'isContractor';
        }
        if (this.isHomeowner) {
            return 'isHomeowner';
        }
        if (this.isHomsiteRep) {
            return 'isHomsiteRep';
        }
        if (this.isCodeEnforcement) {
            return 'isCodeEnforcement';
        }
        return '';
    }

    get currentSignatureKey() {
        if (this.isContractor) {
            return 'contractor';
        }
        if (this.isHomeowner) {
            return 'homeowner';
        }
        if (this.isHomsiteRep) {
            return 'homsiteRep';
        }
        if (this.isCodeEnforcement) {
            return 'codeEnforcement';
        }
        return '';
    }

    get currentRoleAlreadySigned() {
        switch (this.currentSignatureKey) {
        case 'contractor':
            return this.hasContractorSignature;
        case 'homeowner':
            return this.hasHomeownerSignature;
        case 'homsiteRep':
            return this.hasHomsiteRepSignature;
        case 'codeEnforcement':
            return this.hasCodeEnforcementSignature;
        default:
            return false;
        }
    }

    get currentRoleIndex() {
        return this.signatureOrder.indexOf(this.currentSignatureKey);
    }

    shouldShowSignatureRow(signatureKey) {
        if (this.isPreviewMode || !this.currentSignatureKey) {
            return true;
        }
        return this.signatureOrder.indexOf(signatureKey) <= this.currentRoleIndex;
    }

    get showContractorSection() {
        return this.shouldShowSignatureRow('contractor');
    }

    get showHomeownerSection() {
        return this.shouldShowSignatureRow('homeowner');
    }

    get showHomsiteRepSection() {
        return this.shouldShowSignatureRow('homsiteRep');
    }

    get showCodeEnforcementSection() {
        return this.shouldShowSignatureRow('codeEnforcement');
    }

    get signatureCanvasClass() {
        return `signature-pad${this.isReadOnly ? ' read-only' : ''}`;
    }

    get customToastClass() {
        return `custom-toast custom-toast_${this.customToastVariant}`;
    }

    get hasContractorSignature() {
        if (this.isPreviewMode) {
            return false;
        }
        return this.contractorSigned || !!this.contractorSignatureUrl;
    }

    get hasHomeownerSignature() {
        if (this.isPreviewMode) {
            return false;
        }
        return this.homeownerSigned || !!this.homeownerSignatureUrl;
    }

    get hasHomsiteRepSignature() {
        if (this.isPreviewMode) {
            return false;
        }
        return this.homsiteRepSigned || !!this.homsiteRepSignatureUrl;
    }

    get hasCodeEnforcementSignature() {
        if (this.isPreviewMode) {
            return false;
        }
        return this.codeEnforcementSigned || !!this.codeEnforcementSignatureUrl;
    }

    get canEditContractor() {
        return !this.isReadOnly && this.currentSignatureKey === 'contractor' && !this.hasContractorSignature;
    }

    get canEditHomeowner() {
        return !this.isReadOnly && this.currentSignatureKey === 'homeowner' && !this.hasHomeownerSignature;
    }

    get canEditHomsiteRep() {
        return !this.isReadOnly && this.currentSignatureKey === 'homsiteRep' && !this.hasHomsiteRepSignature;
    }

    get canEditCodeEnforcement() {
        return !this.isReadOnly && this.currentSignatureKey === 'codeEnforcement' && !this.hasCodeEnforcementSignature;
    }

    get isSubmitDisabled() {
        if (this.isReadOnly || !this.currentSignatureKey) {
            return true;
        }
        return !this.signatureState[this.currentSignatureKey] && !this.currentRoleAlreadySigned;
    }

    renderedCallback() {
        const canvases = this.template.querySelectorAll('canvas');
        if (!canvases || canvases.length === 0) {
            return;
        }
        canvases.forEach((canvas) => {
            const signatureId = canvas.dataset.signatureId;
            if (!signatureId || this.canvasMap[signatureId]) {
                return;
            }
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
        if (this.isReadOnly) {
            return;
        }
        const signatureId = event.target?.dataset?.signatureId;
        if (!signatureId || !this.ctxMap[signatureId]) {
            return;
        }
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
        if (!this.isDrawing || this.isReadOnly) {
            return;
        }
        const signatureId = this.activeSignatureId;
        if (!signatureId || !this.ctxMap[signatureId]) {
            return;
        }
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
            this.signatureState = {
                ...this.signatureState,
                [signatureId]: this.hasSignatureOnCanvas(this.canvasMap[signatureId])
            };
        }
        this.activeSignatureId = null;
    }

    handleTouchStart(event) {
        if (this.isReadOnly) {
            return;
        }
        event.preventDefault();
        const touch = event.touches[0];
        event.target.dispatchEvent(new MouseEvent('mousedown', {
            clientX: touch.clientX,
            clientY: touch.clientY
        }));
    }

    handleTouchMove(event) {
        event.preventDefault();
        const touch = event.touches[0];
        event.target.dispatchEvent(new MouseEvent('mousemove', {
            clientX: touch.clientX,
            clientY: touch.clientY
        }));
    }

    handleTouchEnd(event) {
        event.preventDefault();
        event.target.dispatchEvent(new MouseEvent('mouseup', {}));
    }

    getCoordinates(event, canvas) {
        const rect = canvas.getBoundingClientRect();
        const clientX = event.clientX || event.touches?.[0].clientX;
        const clientY = event.clientY || event.touches?.[0].clientY;
        return {
            offsetX: clientX - rect.left,
            offsetY: clientY - rect.top
        };
    }

    clearSignature(event) {
        if (this.isReadOnly) {
            return;
        }
        const signatureId = event.target?.dataset?.signatureId;
        if (!signatureId || !this.canvasMap[signatureId] || !this.ctxMap[signatureId]) {
            return;
        }
        const canvas = this.canvasMap[signatureId];
        const ctx = this.ctxMap[signatureId];
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        this.signatureState = { ...this.signatureState, [signatureId]: false };
    }

    hasSignatureOnCanvas(canvas) {
        if (!canvas) {
            return false;
        }
        const ctx = canvas.getContext('2d');
        if (!ctx) {
            return false;
        }
        const pixelData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        for (let i = 3; i < pixelData.data.length; i += 4) {
            if (pixelData.data[i] !== 0) {
                return true;
            }
        }
        return false;
    }

    getSignatureLabel(signatureKey) {
        switch (signatureKey) {
        case 'contractor':
            return 'Contractor';
        case 'homeowner':
            return 'Homeowner';
        case 'homsiteRep':
            return 'Homsite Representative';
        case 'codeEnforcement':
            return 'Code Enforcement';
        default:
            return '';
        }
    }

    getSignatureUrl(signatureKey) {
        switch (signatureKey) {
        case 'contractor':
            return this.contractorSignatureUrl;
        case 'homeowner':
            return this.homeownerSignatureUrl;
        case 'homsiteRep':
            return this.homsiteRepSignatureUrl;
        case 'codeEnforcement':
            return this.codeEnforcementSignatureUrl;
        default:
            return '';
        }
    }

    async handleSubmit() {
        if (this.isReadOnly || !this.currentSignatureKey) {
            return;
        }

        const signatureKey = this.currentSignatureKey;
        const signatureLabel = this.getSignatureLabel(signatureKey);
        const canvas = this.canvasMap[signatureKey];
        const existingUrl = this.getSignatureUrl(signatureKey);
        const signatureResults = {};
        try {
            this.isLoading = true;
            if (canvas && this.hasSignatureOnCanvas(canvas)) {
                const signatureBody = canvas.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, '');
                const result = await saveSignature({
                    recordId: this.recordId,
                    signatureBody,
                    signatureLabel
                });
                signatureResults[signatureKey] = result;
                this.applySavedSignature(signatureKey, result);
            } else if (existingUrl) {
                signatureResults[signatureKey] = { imgUrl: existingUrl, cvId: '' };
            } else {
                this.showToast(`Please provide the ${signatureLabel} signature before submitting.`, 'warning');
                return;
            }

            const result = await savePdf({
                recordId: this.recordId,
                senderId: this.senderId || '',
                sendDate: this.sendDate || '',
                contractorImgUrl: signatureResults.contractor?.imgUrl || this.contractorSignatureUrl || '',
                homeownerImgUrl: signatureResults.homeowner?.imgUrl || this.homeownerSignatureUrl || '',
                homsiteRepImgUrl: signatureResults.homsiteRep?.imgUrl || this.homsiteRepSignatureUrl || '',
                codeEnforcementImgUrl: signatureResults.codeEnforcement?.imgUrl || this.codeEnforcementSignatureUrl || '',
                contractorSignatureId: signatureResults.contractor?.cvId || '',
                homeownerSignatureId: signatureResults.homeowner?.cvId || '',
                homsiteRepSignatureId: signatureResults.homsiteRep?.cvId || '',
                codeEnforcementSignatureId: signatureResults.codeEnforcement?.cvId || '',
                currentSignerRole: this.currentSignerRole,
                homeownerContactIds: this.homeownerContactIds,
                homeownerEmails: this.homeownerEmails,
                homsiteRepContactIds: this.homsiteRepContactIds,
                homsiteRepEmails: this.homsiteRepEmails,
                codeEnforcementContactIds: this.codeEnforcementContactIds,
                codeEnforcementEmails: this.codeEnforcementEmails,
                fromAddressId: this.fromAddressId || '',
                fileIds: this.fileIds
            });

            await this.loadFormData();

            if (result === 'Success') {
                this.isSubmitted = true;
                this.isAlreadySubmitted = false;
                this.submissionStatus = 'submitted';
                this.stageLocked = false;
                this.showToast('Certificate Of Inspection submitted successfully.', 'success');
                return;
            }
            if (result === 'Already Submitted') {
                this.isSubmitted = true;
                this.isAlreadySubmitted = true;
                this.submissionStatus = 'already';
                this.stageLocked = false;
                this.showToast('This Certificate Of Inspection has already been submitted.', 'info');
                return;
            }
            if (result === 'Missing Signatures') {
                this.isSubmitted = false;
                this.isAlreadySubmitted = false;
                this.submissionStatus = 'partial';
                this.stageLocked = true;
                this.showToast('Signature saved. The next recipient has been notified.', 'success');
            }
        } catch (error) {
            this.showToast(error?.body?.message || error?.message || 'An unknown error occurred.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    applySavedSignature(signatureKey, result) {
        if (!result?.imgUrl) {
            return;
        }

        if (signatureKey === 'contractor') {
            this.contractorSignatureUrl = result.imgUrl;
            this.contractorSigned = true;
        } else if (signatureKey === 'homeowner') {
            this.homeownerSignatureUrl = result.imgUrl;
            this.homeownerSigned = true;
        } else if (signatureKey === 'homsiteRep') {
            this.homsiteRepSignatureUrl = result.imgUrl;
            this.homsiteRepSigned = true;
        } else if (signatureKey === 'codeEnforcement') {
            this.codeEnforcementSignatureUrl = result.imgUrl;
            this.codeEnforcementSigned = true;
        }
        this.signatureState = { ...this.signatureState, [signatureKey]: true };
    }

    showToast(message, variant) {
        window.clearTimeout(this.toastTimeout);
        this.customToastMessage = message;
        this.customToastVariant = variant || 'success';
        this.showCustomToast = true;
        this.toastTimeout = window.setTimeout(() => {
            this.showCustomToast = false;
        }, 5000);
    }

    handleCloseToast() {
        window.clearTimeout(this.toastTimeout);
        this.showCustomToast = false;
    }

    handleLogoError() {
        if (this.logoURL !== CompanyLogo) {
            this.logoURL = CompanyLogo;
        }
    }
}