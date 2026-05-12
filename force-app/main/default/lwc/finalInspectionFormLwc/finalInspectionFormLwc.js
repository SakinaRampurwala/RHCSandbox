import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getLogoUrl from '@salesforce/apex/FinalInspectionFormCtrl.getLogoUrl';
import getFinalInspectionData from '@salesforce/apex/FinalInspectionFormCtrl.getFinalInspectionData';
import saveSignature from '@salesforce/apex/FinalInspectionFormCtrl.saveSignature';
import savePdf from '@salesforce/apex/FinalInspectionFormCtrl.savePdf';
import sendCompanyContactEmail from '@salesforce/apex/FinalInspectionFormCtrl.sendCompanyContactEmail';

const formatDateParts = (month, day, year) => `${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}-${year}`;
const formatDate = (dateValue) => formatDateParts(dateValue.getMonth() + 1, dateValue.getDate(), dateValue.getFullYear());

export default class FinalInspectionFormLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    @track isLoading = true;
    @track isSubmitted = false;
    @track isAlreadySubmitted = false;
    @track submitError = '';
    @track logoURL;
    @track homeownerSignatureUrl;
    @track representativeSignatureUrl;
    @track homeownerSigned = false;
    @track representativeSigned = false;
    @track showCustomToast = false;
    @track customToastMessage = '';
    @track customToastVariant = 'success';
    @track inspectionData = {
        homeownerName: '',
        homeownerAddress: '',
        finalInspectionDate: ''
    };
    @track isVendor = false;
    @track isCompany = false;
    companyContactIds = [];
    companyEmails = [];
    fromAddressId;
    fileIds = [];

    canvasMap = {};
    ctxMap = {};
    isDrawing = false;
    activeSignatureId;
    signatureState = {
        homeowner: false,
        representative: false
    };

    currentDate = formatDate(new Date());
    toastTimeout;
    wiredInspectionResult;
    submissionStatus = '';
    stageLocked = false;

    @wire(getLogoUrl)
    wiredLogo({ error, data }) {
        if (data) {
            this.logoURL = data;
        } else if (error) {
            // no-op for non-critical UI element
        }
    }

    @wire(getFinalInspectionData, { recordId: '$recordId' })
    wiredInspection(result) {
        this.wiredInspectionResult = result;
        const { error, data } = result;
        if (data) {
            const homeownerAddress = this.formatAddress({
                street: data.homeownerStreet,
                city: data.homeownerCity,
                state: data.homeownerState,
                postal: data.homeownerPostal,
                country: data.homeownerCountry
            });
            this.inspectionData = {
                homeownerName: data.homeownerName || '',
                homeownerAddress,
                finalInspectionDate: data.finalInspectionDate || ''
            };
            this.homeownerSignatureUrl = data.homeownerSignatureUrl || '';
            this.representativeSignatureUrl = data.representativeSignatureUrl || '';
            this.homeownerSigned = !!data.homeownerSigned;
            this.representativeSigned = !!data.representativeSigned;
            this.signatureState = {
                homeowner: this.homeownerSigned || !!this.homeownerSignatureUrl,
                representative: this.representativeSigned || !!this.representativeSignatureUrl
            };
            if (data.isFinalInspectionSubmitted) {
                this.isSubmitted = true;
                this.isAlreadySubmitted = true;
                if (!this.submissionStatus) {
                    this.submissionStatus = 'already';
                }
                this.stageLocked = false;
            } else if (this.homeownerSigned && !this.representativeSigned && !this.isCompany) {
                this.isSubmitted = false;
                this.isAlreadySubmitted = false;
                this.stageLocked = true;
                this.submissionStatus = this.isVendor ? 'partial-vendor' : 'partial';
            } else {
                this.stageLocked = false;
                if (this.submissionStatus === 'partial' || this.submissionStatus === 'partial-vendor') {
                    this.submissionStatus = '';
                }
            }
        } else if (error) {
            this.inspectionData = {
                homeownerName: '',
                homeownerAddress: '',
                finalInspectionDate: ''
            };
        }
        this.isLoading = false;
    }

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        this.isVendor = params.get('isVendor') === 'true';
        this.isCompany = params.get('isCompany') === 'true';
        const companyIdsParam = params.get('companyContactIds');
        if (companyIdsParam) {
            this.companyContactIds = companyIdsParam
                .split(',')
                .map(item => decodeURIComponent(item).trim())
                .filter(item => item);
        }
        const companyEmailsParam = params.get('companyEmails');
        if (companyEmailsParam) {
            this.companyEmails = companyEmailsParam
                .split(',')
                .map(item => decodeURIComponent(item).trim())
                .filter(item => item);
        }
        const fromAddressIdParam = params.get('fromAddressId');
        if (fromAddressIdParam) {
            this.fromAddressId = decodeURIComponent(fromAddressIdParam).trim();
        }
        const fileIdsParam = params.get('fileIds');
        if (fileIdsParam) {
            this.fileIds = fileIdsParam
                .split(',')
                .map(item => decodeURIComponent(item).trim())
                .filter(item => item);
        }
        if (!this.recordId) {
            this.isLoading = false;
        }
    }

    disconnectedCallback() {
        window.clearTimeout(this.toastTimeout);
    }

    get isReadOnly() {
        const previewFlag = this.isPreview === true || this.isPreview === 'true';
        if (this.isSubmitted) {
            return true;
        }
        if (this.stageLocked) {
            return true;
        }
        if (this.hasHomeownerSignature && !this.hasRepresentativeSignature && !this.isCompany) {
            return true;
        }
        if (this.isVendor || this.isCompany) {
            return false;
        }
        return previewFlag;
    }

    get showSubmittedMessage() {
        return (this.isSubmitted || this.stageLocked) && !(this.isPreview === true || this.isPreview === 'true');
    }

    get submittedMessage() {
        if (this.isAlreadySubmitted || this.submissionStatus === 'already') {
            return 'Final Inspection Form has already been submitted for this record.';
        }
        if (this.submissionStatus === 'partial-vendor') {
            return 'Your signature has been saved. The program representative has been notified.';
        }
        if (this.submissionStatus === 'partial') {
            return 'Your signature has been saved. PDF will be generated once all signatures are collected.';
        }
        return 'Final Inspection Form has been submitted successfully.';
    }

    get isRepresentativeStage() {
        return this.isCompany && this.hasHomeownerSignature && !this.hasRepresentativeSignature;
    }

    get showHomeownerSection() {
        if (this.isReadOnly) {
            return true;
        }
        if (this.isCompany) {
            return this.hasHomeownerSignature;
        }
        return true;
    }

    get showRepresentativeSection() {
        if (this.isReadOnly) {
            return this.hasRepresentativeSignature || this.isSubmitted || this.isAlreadySubmitted || this.isPreview === true || this.isPreview === 'true';
        }
        return this.isCompany || this.hasRepresentativeSignature;
    }

    get signatureCanvasClass() {
        return `signature-pad${this.isReadOnly ? ' read-only' : ''}`;
    }

    get customToastClass() {
        return `custom-toast custom-toast_${this.customToastVariant}`;
    }

    get isSubmitDisabled() {
        if (this.isReadOnly) {
            return true;
        }
        if (this.isVendor || this.isCompany) {
            if (this.isVendor) {
                if (this.hasHomeownerSignature) {
                    return true;
                }
                return !this.signatureState.homeowner;
            }
            if (this.isCompany) {
                if (this.hasRepresentativeSignature) {
                    return true;
                }
                return !this.signatureState.representative;
            }
        }
        if (this.isRepresentativeStage) {
            return !this.signatureState.representative;
        }
        return !this.signatureState.homeowner || !this.signatureState.representative;
    }

    get hasHomeownerSignature() {
        return this.homeownerSigned || !!this.homeownerSignatureUrl;
    }

    get hasRepresentativeSignature() {
        return this.representativeSigned || !!this.representativeSignatureUrl;
    }

    formatAddress({ street, city, state, postal, country }) {
        const safeStreet = street || '';
        const safeCity = city || '';
        const safeState = state || '';
        const safePostal = postal || '';
        const safeCountry = country || '';

        const cityState = [safeCity, safeState].filter(Boolean).join(', ');
        const firstPart = [safeStreet, cityState].filter(Boolean).join(', ');
        const zipPart = safePostal ? ` - ${safePostal}` : '';
        const countryPart = safeCountry ? `, ${safeCountry}` : '';
        return `${firstPart}${zipPart}${countryPart}`.trim();
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
        const mouseEvent = new MouseEvent('mousedown', {
            clientX: touch.clientX,
            clientY: touch.clientY
        });
        event.target.dispatchEvent(mouseEvent);
    }

    handleTouchMove(event) {
        event.preventDefault();
        const touch = event.touches[0];
        const mouseEvent = new MouseEvent('mousemove', {
            clientX: touch.clientX,
            clientY: touch.clientY
        });
        event.target.dispatchEvent(mouseEvent);
    }

    handleTouchEnd(event) {
        event.preventDefault();
        const mouseEvent = new MouseEvent('mouseup', {});
        event.target.dispatchEvent(mouseEvent);
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
        if (this.isReadOnly) return;
        const signatureId = event.target?.dataset?.signatureId;
        if (!signatureId || !this.canvasMap[signatureId] || !this.ctxMap[signatureId]) return;
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

    handleSubmit() {
        if (this.isReadOnly) {
            return;
        }
        this.submitError = '';

        const signaturePromises = [];
        const signatureResults = {};

        const collectSignature = (signatureId, label, existingUrl, warningMessage) => {
            const canvas = this.canvasMap[signatureId];
            if (canvas && this.hasSignatureOnCanvas(canvas)) {
                const signatureBody = canvas.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, '');
                signaturePromises.push(
                    saveSignature({
                        recordId: this.recordId,
                        signatureBody,
                        signatureLabel: label
                    }).then((result) => {
                        signatureResults[signatureId] = result;
                    })
                );
                return true;
            }

            if (existingUrl) {
                signatureResults[signatureId] = { imgUrl: existingUrl, cvId: '' };
                return true;
            }

            this.showStatusToast(warningMessage, 'error');
            return false;
        };

        if (this.showHomeownerSection) {
            const ok = collectSignature(
                'homeowner',
                'Homeowner',
                this.homeownerSignatureUrl,
                'Please provide the homeowner signature before submitting.'
            );
            if (!ok) {
                return;
            }
        }

        if (this.showRepresentativeSection) {
            const ok = collectSignature(
                'representative',
                'Program Representative',
                this.representativeSignatureUrl,
                'Please provide the program representative signature before submitting.'
            );
            if (!ok) {
                return;
            }
        }

        const hasAnySignature = signaturePromises.length > 0
            || signatureResults.homeowner
            || signatureResults.representative;
        if (!hasAnySignature) {
            this.showStatusToast('No signature found to save.', 'error');
            return;
        }

        this.isLoading = true;

        Promise.all(signaturePromises)
            .then(() => {
                return savePdf({
                    recordId: this.recordId,
                    senderId: this.senderId,
                    sendDate: this.sendDate,
                    homeownerImgUrl: signatureResults.homeowner?.imgUrl || this.homeownerSignatureUrl || '',
                    representativeImgUrl: signatureResults.representative?.imgUrl || this.representativeSignatureUrl || '',
                    homeownerSignatureId: signatureResults.homeowner?.cvId || '',
                    representativeSignatureId: signatureResults.representative?.cvId || ''
                });
            })
            .then((result) => {
                if (result === 'Success') {
                    this.isSubmitted = true;
                    this.isAlreadySubmitted = false;
                    this.submissionStatus = 'success';
                    return refreshApex(this.wiredInspectionResult).then(() => {
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Success',
                                message: 'Final Inspection Form submitted successfully.',
                                variant: 'success'
                            })
                        );
                        this.showStatusToast('Final Inspection Form submitted successfully.', 'success');
                    });
                }

                if (result === 'Already Submitted') {
                    this.isSubmitted = true;
                    this.isAlreadySubmitted = true;
                    this.submissionStatus = 'already';
                    return refreshApex(this.wiredInspectionResult).then(() => {
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Already Submitted',
                                message: 'Final Inspection Form has already been submitted for this record.',
                                variant: 'info'
                            })
                        );
                        this.showStatusToast('Final Inspection Form has already been submitted for this record.', 'info');
                    });
                }

                if (result === 'Missing Signatures') {
                    if (this.isVendor) {
                        return sendCompanyContactEmail({
                            recordId: this.recordId,
                            companyContactIds: this.companyContactIds,
                            companyEmails: this.companyEmails,
                            senderId: this.senderId,
                            sendDate: this.sendDate,
                            fromAddressId: this.fromAddressId,
                            fileIds: this.fileIds
                        }).then((sendResult) => {
                            if (sendResult && sendResult !== 'Success') {
                                throw new Error(sendResult);
                            }
                            this.stageLocked = true;
                            this.isAlreadySubmitted = false;
                            this.submissionStatus = 'partial-vendor';
                            return refreshApex(this.wiredInspectionResult).then(() => {
                                this.dispatchEvent(
                                    new ShowToastEvent({
                                        title: 'Success',
                                        message: 'Signature saved. The request has been sent to the program representative.',
                                        variant: 'success'
                                    })
                                );
                                this.showStatusToast('Signature saved. The request has been sent to the program representative.', 'success');
                            });
                        });
                    }

                    this.stageLocked = true;
                    this.isAlreadySubmitted = false;
                    this.submissionStatus = 'partial';
                    return refreshApex(this.wiredInspectionResult).then(() => {
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Signature Saved',
                                message: 'Signature saved. PDF will be generated once all signatures are collected.',
                                variant: 'success'
                            })
                        );
                        this.showStatusToast('Signature saved. PDF will be generated once all signatures are collected.', 'success');
                    });
                }

                throw new Error(result || 'Unable to submit Final Inspection Form.');
            })
            .catch((error) => {
                const message = error?.body?.message || error?.message || 'An unknown error occurred';
                this.submitError = message;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message,
                        variant: 'error'
                    })
                );
                this.showStatusToast(message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showStatusToast(message, variant = 'success') {
        window.clearTimeout(this.toastTimeout);
        this.customToastMessage = message;
        this.customToastVariant = variant;
        this.showCustomToast = true;
        this.toastTimeout = window.setTimeout(() => {
            this.showCustomToast = false;
        }, 5000);
    }

    handleCloseToast() {
        window.clearTimeout(this.toastTimeout);
        this.showCustomToast = false;
    }
}